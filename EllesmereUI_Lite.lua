--------------------------------------------------------------------------------
--  EllesmereUI_Lite.lua
--  Lightweight replacement for AceAddon-3.0, AceEvent-3.0, and AceDB-3.0
--  Zero-overhead event dispatch (direct frame handlers, no CallbackHandler)
--  Reads existing AceDB SavedVariables format — no migration needed
--------------------------------------------------------------------------------
local _, ns = ...

local EUILite = {}
EllesmereUI = EllesmereUI or {}
EllesmereUI.Lite = EUILite

-- Lua APIs
local pairs, type, next, rawset, rawget, setmetatable, wipe =
      pairs, type, next, rawset, rawget, setmetatable, wipe
local tinsert, tremove = table.insert, table.remove
local xpcall, geterrorhandler = xpcall, geterrorhandler

local function errorhandler(err) return geterrorhandler()(err) end
local function safecall(func, ...)
    if type(func) == "function" then return xpcall(func, errorhandler, ...) end
end

--------------------------------------------------------------------------------
--  Addon Registry + Lifecycle
--------------------------------------------------------------------------------
local addons = {}          -- name -> addon table
local initQueue = {}       -- addons waiting for OnInitialize
local enableQueue = {}     -- addons waiting for OnEnable
local statuses = {}        -- name -> true if enabled

--- Create a new addon object. Replaces AceAddon:NewAddon().
-- Returns a table with :RegisterEvent / :UnregisterEvent mixed in.
function EUILite.NewAddon(name)
    if addons[name] then
        error("EUILite.NewAddon: addon '" .. name .. "' already exists.", 2)
    end
    local addon = { name = name, enabledState = true }
    addons[name] = addon
    tinsert(initQueue, addon)

    -- Mix in event methods
    addon.RegisterEvent   = EUILite._RegisterEvent
    addon.UnregisterEvent = EUILite._UnregisterEvent

    return addon
end

--- Retrieve an addon by name (for cross-addon access).
-- Replaces LibStub("AceAddon-3.0"):GetAddon(name).
function EUILite.GetAddon(name, silent)
    if not addons[name] and not silent then
        error("EUILite.GetAddon: addon '" .. name .. "' not found.", 2)
    end
    return addons[name]
end

--------------------------------------------------------------------------------
--  Event System (direct frame handlers, no CallbackHandler overhead)
--------------------------------------------------------------------------------
-- Each addon gets its own hidden frame for events. When RegisterEvent is
-- called with a function callback, we store it and route through a single
-- OnEvent script. No securecallfunction dispatch loop, no registry tables.
--------------------------------------------------------------------------------

local function GetOrCreateEventFrame(addon)
    if addon._eventFrame then return addon._eventFrame end
    local f = CreateFrame("Frame")
    f._handlers = {}
    f:SetScript("OnEvent", function(self, event, ...)
        local handler = self._handlers[event]
        if handler then
            handler(addon, event, ...)
        end
    end)
    addon._eventFrame = f
    return f
end

--- Register for a Blizzard event. Compatible with AceEvent calling conventions:
--   addon:RegisterEvent("EVENT_NAME", function(self, event, ...) end)
--   addon:RegisterEvent("EVENT_NAME", "MethodName")
--   addon:RegisterEvent("EVENT_NAME")  -- calls self:EVENT_NAME(event, ...)
function EUILite._RegisterEvent(self, eventname, callback)
    local f = GetOrCreateEventFrame(self)
    local handler
    if type(callback) == "function" then
        handler = function(addon, event, ...) callback(addon, event, ...) end
    elseif type(callback) == "string" then
        handler = function(addon, event, ...)
            if addon[callback] then addon[callback](addon, event, ...) end
        end
    else
        -- No callback: look for self:EVENT_NAME
        handler = function(addon, event, ...)
            if addon[eventname] then addon[eventname](addon, event, ...) end
        end
    end
    f._handlers[eventname] = handler
    f:RegisterEvent(eventname)
end

--- Unregister a Blizzard event.
function EUILite._UnregisterEvent(self, eventname)
    local f = self._eventFrame
    if not f then return end
    f._handlers[eventname] = nil
    f:UnregisterEvent(eventname)
end

--------------------------------------------------------------------------------
--  Database (reads existing AceDB format, zero-dependency)
--------------------------------------------------------------------------------
-- AceDB stores data as:
--   GlobalSVName = {
--       profileKeys = { ["CharName - RealmName"] = "Default" },
--       profiles = { Default = { ... } }
--   }
-- We read from that same structure so existing settings carry over.
--------------------------------------------------------------------------------

local function DeepMergeDefaults(dest, src)
    -- Merge src into dest, only filling in keys that don't exist yet
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dest[k]) ~= "table" then
                dest[k] = {}
            end
            DeepMergeDefaults(dest[k], v)
        else
            if dest[k] == nil then
                dest[k] = v
            end
        end
    end
end

-- Expose for use by the profile system when applying old snapshots
EUILite.DeepMergeDefaults = DeepMergeDefaults

local function StripDefaults(db, defaults)
    -- Remove values that match defaults (for clean SavedVariables on logout)
    for k, v in pairs(defaults) do
        if type(v) == "table" and type(db[k]) == "table" then
            StripDefaults(db[k], v)
            -- Keep empty array entries; DeepMergeDefaults fills them on login.
            if not next(db[k]) and type(k) ~= "number" then
                db[k] = nil
            end
        elseif db[k] == v then
            db[k] = nil
        end
    end
end

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

local dbRegistry = {}  -- all db objects, for logout cleanup

-- Expose so the profile system can update db.profile in-place after injection
EUILite._dbRegistry = dbRegistry

--- Create or open a database backed by the central EllesmereUIDB store.
-- Returns a db object with .profile pointing to the active profile table
-- inside EllesmereUIDB.profiles[name].addons[folder].
-- @param svName  Global SavedVariables name (string), e.g. "EllesmereUIActionBarsDB"
-- @param defaults  Table with a .profile sub-table of default values
-- @param defaultToCharKey  (ignored, kept for call-site compat)
function EUILite.NewDB(svName, defaults, defaultToCharKey)
    -- Derive the addon folder name from the SV name (strip trailing "DB")
    local folder = svName:match("^(.+)DB$") or svName

    -- Resolve the active profile name from the central DB
    local profileName = "Default"
    if EllesmereUIDB and EllesmereUIDB.activeProfile then
        profileName = EllesmereUIDB.activeProfile
    end

    -- Ensure the profile and addons tables exist in the central DB
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if type(EllesmereUIDB.profiles[profileName]) ~= "table" then
        EllesmereUIDB.profiles[profileName] = {}
    end
    local profileData = EllesmereUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end
    if type(profileData.addons[folder]) ~= "table" then
        profileData.addons[folder] = {}
    end
    local profile = profileData.addons[folder]

    -- One-time flat-SV migration: if the centralized slot is empty and the
    -- global SV contains data from a previous version, copy it into the slot.
    -- Handles two legacy formats:
    --   1) Flat data (e.g. Nameplates wrote directly to _G[svName])
    --   2) Old Lite/AceDB format with profiles/profileKeys sub-tables
    if not next(profile) then
        local globalSV = _G[svName]
        if globalSV and type(globalSV) == "table" then
            if not globalSV.profiles and not globalSV.profileKeys then
                -- Format 1: flat data, copy everything
                for k, v in pairs(globalSV) do
                    if type(v) == "table" then
                        profile[k] = DeepCopy(v)
                    else
                        profile[k] = v
                    end
                end
            elseif globalSV.profiles and type(globalSV.profiles) == "table" then
                -- Format 2: old profile-based SV. Extract the matching
                -- profile (or "Default") so settings carry over.
                local oldProfile = globalSV.profiles[profileName]
                if not oldProfile and globalSV.profileKeys then
                    -- Try the character-keyed profile name
                    local charName = UnitName("player")
                    local realm = GetRealmName()
                    if charName and realm then
                        local charKey = charName .. " - " .. realm
                        local mappedName = globalSV.profileKeys[charKey]
                        if mappedName then
                            oldProfile = globalSV.profiles[mappedName]
                        end
                    end
                end
                if not oldProfile then
                    -- Fall back to "Default" or first available profile
                    oldProfile = globalSV.profiles["Default"]
                    if not oldProfile then
                        for _, v in pairs(globalSV.profiles) do
                            if type(v) == "table" then oldProfile = v; break end
                        end
                    end
                end
                if oldProfile and type(oldProfile) == "table" then
                    for k, v in pairs(oldProfile) do
                        if type(v) == "table" then
                            profile[k] = DeepCopy(v)
                        else
                            profile[k] = v
                        end
                    end
                end
            end
        end
    end

    -- Merge defaults into profile (fills missing keys only)
    local profileDefaults = defaults and defaults.profile
    if profileDefaults then
        DeepMergeDefaults(profile, profileDefaults)
        -- Validate: if any top-level default sub-table is missing or wrong
        -- type after merge, the profile is corrupt. Wipe and re-merge.
        local corrupt = false
        for k, v in pairs(profileDefaults) do
            if type(v) == "table" and type(profile[k]) ~= "table" then
                corrupt = true
                break
            end
        end
        if corrupt then
            wipe(profile)
            DeepMergeDefaults(profile, profileDefaults)
            -- One-time warning per session
            if not EUILite._corruptionWarned then
                EUILite._corruptionWarned = true
                C_Timer.After(5, function()
                    print("|cffff6600EllesmereUI:|r Profile data for " .. folder .. " was corrupted and has been repaired. Your settings may have been reset to defaults.")
                end)
            end
        end
    end

    -- Build the db object
    local db = {
        sv = EllesmereUIDB,
        svName = svName,
        folder = folder,
        profile = profile,
        _profileName = profileName,
        _defaults = defaults,
        _profileDefaults = profileDefaults,
    }

    --- Reset the current profile to defaults.
    function db:ResetProfile()
        wipe(self.profile)
        if self._profileDefaults then
            DeepMergeDefaults(self.profile, self._profileDefaults)
        end
    end

    -- Register for logout cleanup
    tinsert(dbRegistry, db)

    return db
end

--------------------------------------------------------------------------------
--  Logout handler: strip defaults so SavedVariables stay clean
--  Fires pre-logout callbacks first so systems like Profiles can snapshot
--  the full profile data before defaults are stripped.
--------------------------------------------------------------------------------
local preLogoutCallbacks = {}

--- Register a function to run before StripDefaults on logout.
--- Used by the profile system to save a complete snapshot.
function EUILite.RegisterPreLogout(fn)
    tinsert(preLogoutCallbacks, fn)
end

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    -- Fire pre-logout callbacks while data is still intact
    for _, fn in ipairs(preLogoutCallbacks) do
        safecall(fn)
    end

    -- Strip defaults from a COPY of each profile table, then write the
    -- stripped copy back into the central store. This keeps the live
    -- db.profile references untouched (important if any pre-logout
    -- callback still reads from them after this point).
    local activeProfile = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
    local profileData = EllesmereUIDB and EllesmereUIDB.profiles and EllesmereUIDB.profiles[activeProfile]
    if profileData and profileData.addons then
        for _, db in pairs(dbRegistry) do
            if db._profileDefaults and db.profile then
                local stripped = DeepCopy(db.profile)
                StripDefaults(stripped, db._profileDefaults)
                profileData.addons[db.folder] = stripped
            end
        end
    end
end)

--------------------------------------------------------------------------------
--  Lifecycle driver (replaces AceAddon's ADDON_LOADED / PLAYER_LOGIN handler)
--------------------------------------------------------------------------------
-- OnInitialize fires on ADDON_LOADED (SavedVariables are available).
-- OnEnable fires on PLAYER_LOGIN (game data is available).
-- This matches AceAddon's exact timing.
--------------------------------------------------------------------------------

local lifecycleFrame = CreateFrame("Frame")
lifecycleFrame:RegisterEvent("ADDON_LOADED")
lifecycleFrame:RegisterEvent("PLAYER_LOGIN")
lifecycleFrame:SetScript("OnEvent", function(self, event, arg1)
    -- Process init queue on every ADDON_LOADED (same as AceAddon)
    while #initQueue > 0 do
        local addon = tremove(initQueue, 1)
        safecall(addon.OnInitialize, addon)
        tinsert(enableQueue, addon)
    end

    -- Process enable queue once logged in
    if IsLoggedIn() then
        -- Ensure PP.mult is current before any addon's OnEnable runs.
        -- PP is defined in EllesmereUI.lua (loaded after this file) so it
        -- exists by the time PLAYER_LOGIN fires.
        if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
            EllesmereUI.PP.UpdateMult()
        end
        -- Apply spec-assigned profile data into each child SV before any
        -- OnEnable runs. The spec API is available here (after OnInitialize,
        -- before OnEnable) so we can resolve the current spec and inject the
        -- correct profile snapshot. This is the earliest safe point to do
        -- this -- ADDON_LOADED is too early (spec API not ready yet).
        if EllesmereUI and EllesmereUI.PreSeedSpecProfile then
            EllesmereUI.PreSeedSpecProfile()
        end
        while #enableQueue > 0 do
            local addon = tremove(enableQueue, 1)
            if addon.enabledState then
                statuses[addon.name] = true
                safecall(addon.OnEnable, addon)
            end
        end
    end
end)
