-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker.lua
--
-- Slim loader. Blizzard's ObjectiveTrackerFrame remains the rendering engine;
-- we only skin it, drive its visibility, and layer on the auto-accept /
-- auto-turn-in / quest-item hotkey / SplashFrame QoL features.
--
-- The three feature modules are wired up on PLAYER_LOGIN after
-- Blizzard_ObjectiveTracker has loaded.
-------------------------------------------------------------------------------
local addonName, ns = ...

local EQT = {}
ns.EQT = EQT
_G.EllesmereUIQuestTracker = EQT

-------------------------------------------------------------------------------
-- DB defaults. Legacy keys from the 3807-line custom tracker are intentionally
-- omitted; the migration entry in EllesmereUI_Migration.lua archives any
-- stored values into a _legacy subtable.
-------------------------------------------------------------------------------
local QT_DEFAULTS = {
    profile = {
        questTracker = {
            enabled              = true,
            forceOnScreen        = true,
            visibility           = "always",
            visOnlyInstances     = false,
            visHideHousing       = false,
            visHideMounted       = false,
            visHideNoTarget      = false,
            visHideNoEnemy       = false,

            -- Raid auto-hide mode: "always" hides the tracker the whole time
            -- you are in a raid; "boss" (default) only hides it during boss encounters.
            hideInRaidMode       = "boss",

            -- Skin toggles
            skinHeaders          = true,
            accentHeaders        = true,
            -- Show Blizzard's native quest type icons/buttons (right side)
            -- instead of our custom classified icons. Off = our icons. Reload-gated.
            showQuestIcons       = false,

            -- Font sizes (single source of truth used by skin code)
            titleFontSize        = 12,
            objectiveFontSize    = 10,

            -- Background (rendered behind ObjectiveTrackerFrame, our own frame)
            bgR                  = 0.035,
            bgG                  = 0.035,
            bgB                  = 0.035,
            bgAlpha              = 0.75,
            showTopLine          = true,

            -- Text colors. All apply via SetTextColor on their respective
            -- FontStrings (titles, objective lines, focus override).
            titleR               = 1.000, titleG = 0.910, titleB = 0.471,  -- FFE878
            completedR           = 0.251, completedG = 1.000, completedB = 0.349,  -- 40FF59
            focusR               = 0.871, focusG = 0.251, focusB = 1.000,  -- DE40FF

            -- QoL
            autoAccept           = false,
            autoAcceptPreventMulti = true,
            autoAcceptShiftSkip  = true,
            autoTurnIn           = false,
            autoTurnInShiftSkip  = true,
            questItemHotkey      = nil,
        },
    },
}

local _qtDB
local function EnsureDB()
    if _qtDB then return _qtDB end
    if not EllesmereUI or not EllesmereUI.Lite then return nil end
    _qtDB = EllesmereUI.Lite.NewDB("EllesmereUIQuestTrackerDB", QT_DEFAULTS)
    _G._EQT_DB = _qtDB
    return _qtDB
end

function EQT.DB()
    local d = EnsureDB()
    if d and d.profile and d.profile.questTracker then
        return d.profile.questTracker
    end
    -- Fallback when the persistent DB isn't ready yet (login races, profile
    -- switch windows, spec swaps). Must contain `enabled=true` + a valid
    -- visibility mode, otherwise EvalVisibility returns false and the shared
    -- visibility dispatcher will alpha-0 the tracker whenever an unrelated
    -- event (combat, target change, zone) fires during an unready window.
    if not EQT._tmpDB then
        EQT._tmpDB = { enabled = true, visibility = "always" }
    end
    return EQT._tmpDB
end

function EQT.Cfg(k) return EQT.DB()[k] end
function EQT.Set(k, v) EQT.DB()[k] = v end

-------------------------------------------------------------------------------
-- Cross-module suppression API. Other EUI modules (e.g. M+ Timer preview
-- mode) can call _EQT_SetSuppressed(key, true) to temporarily hide our
-- tracker. Suppression stacks across callers.
--
-- Top-level only: never walk into the frame's children. We reparent the
-- ObjectiveTrackerFrame to a hidden container; mouse state is implicit.
-------------------------------------------------------------------------------
local _qtSuppressors = {}
function _G._EQT_SetSuppressed(key, on)
    if not key then return end
    _qtSuppressors[key] = on and true or nil
    if EQT.ApplySuppression then EQT.ApplySuppression(next(_qtSuppressors) ~= nil) end
end
function EQT.IsSuppressed() return next(_qtSuppressors) ~= nil end

-------------------------------------------------------------------------------
-- Loader
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")

-- Blizzard_ObjectiveTracker is part of the base Midnight UI and is loaded
-- before our addon, so ADDON_LOADED for it never fires. Seed _sawOT from
-- IsAddOnLoaded (or the frame's existence) so init still triggers.
local _sawSelf, _sawOT, _loggedIn = false, false, false
local _isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
if (_isLoaded and _isLoaded("Blizzard_ObjectiveTracker")) or _G.ObjectiveTrackerFrame then
    _sawOT = true
end

local function TryInit()
    if not (_sawSelf and _sawOT and _loggedIn) then return end
    EnsureDB()
    if EQT.InitSkin       then EQT.InitSkin()       end
    if EQT.InitVisibility then EQT.InitVisibility() end
    if EQT.InitQoL        then EQT.InitQoL()        end
    loader:UnregisterAllEvents()
end

loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then _sawSelf = true end
        if arg1 == "Blizzard_ObjectiveTracker" then _sawOT = true end
    elseif event == "PLAYER_LOGIN" then
        _loggedIn = true
    end
    TryInit()
end)

-- Profile-swap refresh: called from EllesmereUI.RefreshAllAddons to re-read
-- DB and refresh all visuals after a profile switch without /reload.
_G._EQT_RefreshAll = function()
    if EQT.RefreshFonts then EQT.RefreshFonts() end
    if EQT.UpdateVisibility then EQT.UpdateVisibility() end
    if EQT.RestyleAll then EQT.RestyleAll() end
    if EQT.ApplyBackground then EQT.ApplyBackground() end
    if EQT.ApplyForceOnScreen then EQT.ApplyForceOnScreen() end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SLASH_EQT1 = "/eqt"
SlashCmdList.EQT = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "show" then
        EQT.Set("enabled", true)
        if EQT.UpdateVisibility then EQT.UpdateVisibility() end
    elseif msg == "hide" then
        EQT.Set("enabled", false)
        if EQT.UpdateVisibility then EQT.UpdateVisibility() end
    elseif msg == "toggle" then
        EQT.Set("enabled", not EQT.Cfg("enabled"))
        if EQT.UpdateVisibility then EQT.UpdateVisibility() end
    else
        if InCombatLockdown and InCombatLockdown() then return end
        if EllesmereUI and EllesmereUI.ShowModule then
            EllesmereUI:ShowModule("EllesmereUIQuestTracker")
        end
    end
end
