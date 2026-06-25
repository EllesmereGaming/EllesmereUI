--------------------------------------------------------------------------------
--  EllesmereUI_ExternalModules.lua
--  Public extension surface for third-party addons to register as native
--  EllesmereUI modules with their own sidebar entry and options page.
--
--  Two layers live here:
--    1. Callback bus  -- EllesmereUI.RegisterModuleCallback / FireModuleCallback
--       Lets external modules subscribe to host lifecycle events they cannot
--       otherwise observe (e.g. in-session profile switches). It uses
--       CallbackHandler-1.0, so callbacks receive (eventName, ...) and can be
--       registered by function reference or method name.
--    2. RegisterExternalModule(spec) -- injects a third-party addon into the
--       sidebar builder, page dispatch, and reset roster, with full error
--       isolation so a buggy module cannot brick the options UI. (Layer 2 is
--       added by a follow-up commit on this branch.)
--
--  Loaded after EllesmereUI.lua. All API surface is exposed on the
--  _G.EllesmereUI table; this file intentionally adds NO locals to
--  EllesmereUI.lua's main chunk, which sits at the Lua 5.1 200-upvalue limit.
--------------------------------------------------------------------------------
local ADDON_NAME = ...

local EllesmereUI = EllesmereUI or {}
_G.EllesmereUI = EllesmereUI

-- Lua/WoW API locals (kept on this file's chunk, not EllesmereUI.lua's)
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local xpcall, geterrorhandler, debugstack = xpcall, geterrorhandler, debugstack

-------------------------------------------------------------------------------
--  Layer 1: External Module Callback Bus
-------------------------------------------------------------------------------
local CallbackHandler = LibStub and LibStub("CallbackHandler-1.0", true)
local moduleCallbackTarget = {}
local moduleCallbackRegistry = CallbackHandler and CallbackHandler:New(
    moduleCallbackTarget,
    "RegisterModuleCallback",
    "UnregisterModuleCallback",
    "UnregisterAllModuleCallbacks"
)

--- Subscribe to a host lifecycle event.
-- Known events (fired by the host):
--   "ProfileChanged"  -- fired by EllesmereUI.SwitchProfile after the active
--                       profile is repointed. Receives (eventName, profileName).
-- Usage mirrors CallbackHandler:
--   EllesmereUI.RegisterModuleCallback(owner, "ProfileChanged", fn)
--   EllesmereUI.RegisterModuleCallback(owner, "ProfileChanged", "MethodName")
-- @param owner  table|string|thread callback owner, used for unregistering
-- @param event  string event name
-- @param method function|string callback function or owner method name
function EllesmereUI.RegisterModuleCallback(owner, event, method, ...)
    if not moduleCallbackTarget.RegisterModuleCallback then return end
    return moduleCallbackTarget.RegisterModuleCallback(owner, event, method, ...)
end

--- Unsubscribe one callback event for an owner.
-- @param owner table|string|thread callback owner
-- @param event string event name
function EllesmereUI.UnregisterModuleCallback(owner, event)
    if not moduleCallbackTarget.UnregisterModuleCallback then return end
    return moduleCallbackTarget.UnregisterModuleCallback(owner, event)
end

--- Unsubscribe all callback events for one or more owners.
-- @param ... table|string|thread callback owners
function EllesmereUI.UnregisterAllModuleCallbacks(...)
    if not moduleCallbackTarget.UnregisterAllModuleCallbacks then return end
    return moduleCallbackTarget.UnregisterAllModuleCallbacks(...)
end

--- Fire a lifecycle event to all registered listeners. Internal use only.
-- External modules subscribe via RegisterModuleCallback; only the host fires.
-- @param event  string event name
-- @param ...    payload forwarded after event name
function EllesmereUI.FireModuleCallback(event, ...)
    if moduleCallbackRegistry then
        moduleCallbackRegistry:Fire(event, ...)
    end
end

-------------------------------------------------------------------------------
--  Layer 2: RegisterExternalModule
-------------------------------------------------------------------------------
-- Mirrors the official EllesmereUI:RegisterModule pipeline but bypasses the
-- internal-folder allowlist (we do our OWN caller-folder verification instead)
-- and routes third-party modules into a dedicated "External" sidebar group so
-- users can tell official from community at a glance.
--
-- spec schema (v1):
--   folder            string  REQUIRED  addon directory name (must equal the
--                                                caller's actual folder)
--   display           string  REQUIRED  sidebar label (English; localized via L)
--   apiVersion        number  REQUIRED  EllesmereUI.API_VERSION targeted
--   title             string  REQUIRED  page header title
--   pages             table   REQUIRED  array of page (tab) names, English
--   buildPage         fn      REQUIRED  (pageName, parent, yOffset) -> totalH
--   description       string  OPT       page header subtitle
--   icon              string  OPT       reserved (sidebar row has no left icon)
--   searchTerms       string  OPT       sidebar search haystack (else display)
--                          | table
--   onPageCacheRestore fn    OPT       (pageName) called on cache fast-path
--   onReset           fn      OPT       () called by "Reset module" buttons
--   comingSoon        bool    OPT       row shown but greyed/not clickable
--   maintenance       bool    OPT       same as comingSoon, different semantics
--
-- Returns: true on success; false, errMsg on validation failure.

-- Constants for the External sidebar group. The label is run through L() so
-- community translators can override it via Locales/<code>.lua.
local EXTERNAL_GROUP_KEY   = "external"
local EXTERNAL_GROUP_LABEL = "External"

-- Returns the ADDON_GROUPS entry for the External group, creating it (appended
-- to the end of EllesmereUI.ADDON_GROUPS) on first call. Idempotent.
local function GetOrCreateExternalGroup()
    local groups = EllesmereUI.ADDON_GROUPS
    if not groups then return nil end
    for i = 1, #groups do
        if groups[i].key == EXTERNAL_GROUP_KEY then return groups[i] end
    end
    local g = { key = EXTERNAL_GROUP_KEY, label = EXTERNAL_GROUP_LABEL, members = {} }
    groups[#groups + 1] = g
    return g
end

-- Add folder to a group's members if not already present. Idempotent.
local function AddToGroupMembers(group, folder)
    local m = group.members
    for i = 1, #m do
        if m[i] == folder then return end
    end
    m[#m + 1] = folder
end

-- Wrap a buildPage callback so an error inside it cannot brick the options
-- UI. On error, the wrapper renders a red error page in place and forwards
-- the error to the global error handler so it surfaces in the usual debug
-- stream (BugGrabber / Blizzard /errors).
local function WrapBuildPage(original)
    if type(original) ~= "function" then return nil end
    return function(pageName, parent, yOffset)
        local lastErr
        local function capture(err) lastErr = err; local h = geterrorhandler(); if h then h(err) end end
        local ok, totalH = xpcall(original, capture, pageName, parent, yOffset)
        if ok then return totalH end
        -- Error fallback: render a red-text notice on the page wrapper.
        -- parent is the freshly-created Frame for this page (see
        -- EllesmereUI.lua:8544); a FontString anchored to TOPLEFT is the
        -- minimum viable error surface.
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontRedLarge")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, (yOffset or -6) - 20)
        fs:SetWidth(math.max(200, (parent:GetWidth() or 600) - 40))
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetText("Module page failed to render: " .. tostring(lastErr))
        return math.abs(yOffset or -6) + 60
    end
end

local function WrapOptionalCallback(original)
    if type(original) ~= "function" then return nil end
    return function(...)
        local function swallow(err) local h = geterrorhandler(); if h then h(err) end end
        xpcall(original, swallow, ...)
    end
end

function EllesmereUI.RegisterExternalModule(spec)
    if type(spec) ~= "table" then
        return false, "spec must be a table"
    end

    -- Required field validation
    if type(spec.folder)     ~= "string" or spec.folder     == "" then return false, "spec.folder required"      end
    if type(spec.display)    ~= "string" or spec.display    == "" then return false, "spec.display required"     end
    if type(spec.apiVersion) ~= "number"                              then return false, "spec.apiVersion required" end
    if type(spec.pages)      ~= "table"  or #spec.pages      == 0    then return false, "spec.pages required"       end
    if type(spec.buildPage)  ~= "function"                          then return false, "spec.buildPage required"  end

    -- Caller-folder verification: the registration call site must physically
    -- live inside the addon folder named by spec.folder. This prevents addon A
    -- from registering a panel under addon B's identity. Uses the same
    -- debugstack technique as EllesmereUI:RegisterModule.
    local caller = debugstack(2, 1, 0) or ""
    local callerFolder = caller:match("AddOns/([^/]+)/")
    if callerFolder ~= spec.folder then
        return false, "caller folder '" .. tostring(callerFolder) ..
                      "' does not match spec.folder '" .. spec.folder .. "'"
    end

    -- API version handshake
    local hostAPI = EllesmereUI.API_VERSION or 0
    if spec.apiVersion > hostAPI then
        EllesmereUI.Print(("|cffff6600EllesmereUI:|r External module '%s' requires API version %d (host has %d). Update EllesmereUI.")
                          :format(spec.folder, spec.apiVersion, hostAPI))
        return false, "api version too new"
    end
    if spec.apiVersion < hostAPI then
        -- Allow but mark. Currently impossible (host is 1) but forward-compat.
        EllesmereUI.Print(("|cffffcc00EllesmereUI:|r External module '%s' targets API version %d (host has %d). Some features may be unavailable.")
                          :format(spec.folder, spec.apiVersion, hostAPI))
    end

    -- Build the roster info entry. alwaysLoaded is forced false so the power
    -- toggle (Blizzard enable/disable) shows for the real addon folder. Sync
    -- is forced off via _syncExempt below (external modules do not implement
    -- the host profile-sync protocol).
    local info = {
        folder       = spec.folder,
        display      = spec.display,
        search_name  = spec.searchTerms or spec.display,
        alwaysLoaded = false,
        comingSoon   = spec.comingSoon  and true or nil,
        maintenance  = spec.maintenance and true or nil,
        -- Marker so host code can identify external entries if needed later.
        isExternal   = true,
    }

    -- Inject into the roster and the folder lookup. Idempotent: if the folder
    -- is already known (e.g. re-registration after a reload), replace in place
    -- rather than appending a duplicate.
    local roster = EllesmereUI.ADDON_ROSTER
    local existingIndex
    if roster then
        for i = 1, #roster do
            if roster[i].folder == spec.folder then existingIndex = i; break end
        end
        if existingIndex then
            roster[existingIndex] = info
        else
            roster[#roster + 1] = info
        end
    end
    if EllesmereUI._addonInfoByFolder then
        EllesmereUI._addonInfoByFolder[spec.folder] = info
    end

    -- Add to the External sidebar group (creates the group lazily).
    local group = GetOrCreateExternalGroup()
    if group then AddToGroupMembers(group, spec.folder) end

    -- Opt out of the profile-sync icon entirely. External modules don't
    -- populate EllesmereUI's sync tables; showing the icon would mislead users
    -- into thinking sync works for them.
    if EllesmereUI._syncExempt then
        EllesmereUI._syncExempt[spec.folder] = true
    end

    -- Build the config that RegisterModuleConfig consumes. The buildPage and
    -- optional callbacks are xpcall-wrapped so a buggy module cannot brick
    -- the options panel.
    local config = {
        title       = spec.title,
        description = spec.description,
        pages       = spec.pages,
        buildPage   = WrapBuildPage(spec.buildPage),
        onPageCacheRestore = WrapOptionalCallback(spec.onPageCacheRestore),
        onReset     = WrapOptionalCallback(spec.onReset),
        searchTerms = spec.searchTerms or spec.display,
    }
    EllesmereUI._RegisterModuleConfig(spec.folder, config)

    return true
end
