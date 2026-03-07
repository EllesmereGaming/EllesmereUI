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

local function StripDefaults(db, defaults)
    -- Remove values that match defaults (for clean SavedVariables on logout)
    for k, v in pairs(defaults) do
        if type(v) == "table" and type(db[k]) == "table" then
            StripDefaults(db[k], v)
            if not next(db[k]) then
                db[k] = nil
            end
        elseif db[k] == v then
            db[k] = nil
        end
    end
end

local dbRegistry = {}      -- all db objects, for logout cleanup
local dbRegistryBySV = {}  -- SavedVariables name -> db object

--- Create or open a database. Replaces AceDB:New(svName, defaults, true).
-- Returns a db object with .profile pointing to the active profile table.
-- @param svName  Global SavedVariables name (string)
-- @param defaults  Table with a .profile sub-table of default values
function EUILite.NewDB(svName, defaults)
    -- Get or create the global SV table
    local sv = _G[svName]
    if type(sv) ~= "table" then
        sv = {}
        _G[svName] = sv
    end

    -- Determine profile key
    local charKey = UnitName("player") .. " - " .. GetRealmName()
    if type(sv.profileKeys) ~= "table" then sv.profileKeys = {} end
    local profileName = sv.profileKeys[charKey] or "Default"
    sv.profileKeys[charKey] = profileName

    -- Get or create the profile table
    if type(sv.profiles) ~= "table" then sv.profiles = {} end
    if type(sv.profiles[profileName]) ~= "table" then sv.profiles[profileName] = {} end
    local profile = sv.profiles[profileName]

    -- Merge defaults into profile (fills missing keys only)
    local profileDefaults = defaults and defaults.profile
    if profileDefaults then
        DeepMergeDefaults(profile, profileDefaults)
        -- Validate: if any top-level default sub-table is missing or wrong
        -- type after merge, the profile is corrupt (e.g. AceDB migration
        -- leftovers).  Wipe and re-merge from scratch.
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
        end
    end

    -- Build the db object
    local db = {
        sv = sv,
        profile = profile,
        _svName = svName,
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

    -- Register for logout cleanup and for cross-addon profile tooling.
    -- The profile system uses the registry to look up the current defaults
    -- for a SavedVariables table before applying imported snapshots.
    tinsert(dbRegistry, db)
    dbRegistryBySV[svName] = db

    return db
end

--- Look up a registered db object by its SavedVariables name.
--- This intentionally exposes the live defaults metadata so suite-level
--- profile import/export code can re-merge current defaults after swaps.
function EUILite.GetRegisteredDB(svName)
    return dbRegistryBySV[svName]
end

--------------------------------------------------------------------------------
--  Logout handler: strip defaults so SavedVariables stay clean
--------------------------------------------------------------------------------
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    for _, db in pairs(dbRegistry) do
        if db._profileDefaults and db.profile then
            StripDefaults(db.profile, db._profileDefaults)
        end
        -- Clean up empty profile tables
        local sv = db.sv
        if sv and sv.profiles then
            for key, tbl in pairs(sv.profiles) do
                if type(tbl) == "table" and not next(tbl) then
                    sv.profiles[key] = nil
                end
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
        while #enableQueue > 0 do
            local addon = tremove(enableQueue, 1)
            if addon.enabledState then
                statuses[addon.name] = true
                safecall(addon.OnEnable, addon)
            end
        end
    end
end)
