--------------------------------------------------------------------------------
--  EllesmereUI_Lite.lua
--  Lightweight replacement for AceAddon-3.0, AceEvent-3.0, and AceDB-3.0
--  Zero-overhead event dispatch (direct frame handlers, no CallbackHandler)
--  Reads existing AceDB SavedVariables format — no migration needed
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local EUILite = {}
EllesmereUI = EllesmereUI or {}
-- TEMPORARY 12.1 compatibility flag. At 12.1 launch the live build reports
-- 120100+, this flips true automatically, and a post-launch cleanup pass
-- deletes the legacy branches and this flag. Documented exception to the
-- CLAUDE.md "no version branches" rule for the dual-client window.
EllesmereUI.IS_121 = (select(4, GetBuildInfo()) or 0) >= 120100
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
        return addons[name]
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

EUILite.DeepCopy = DeepCopy

local dbRegistry = {}  -- all db objects, for logout cleanup

-- Expose so the profile system can update db.profile in-place after injection
EUILite._dbRegistry = dbRegistry

-- Pre-SavedVariables db tracking. A NewDB call at FILE SCOPE in the addon
-- that OWNS the central store runs before WoW loads that addon's
-- SavedVariables: it builds its profile inside a fresh table, and the real
-- saved table then replaces the global right after, orphaning the db --
-- session writes go to the orphan and are never serialized (settings
-- silently stop saving). In the suite this can't happen (children's files
-- execute long after the parent's SVs loaded), but in a STANDALONE build
-- everything is one addon, so a file-scope NewDB (Bags) hit exactly this.
-- Any db created before the owning addon's ADDON_LOADED is recorded here
-- and re-rooted in place against the real loaded store at that moment.
-- STANDALONE-GATED: the suite has no pre-SV NewDB callers (children init
-- after the parent's SVs load), so the queue is provably empty there; the
-- gate makes that a hard guarantee instead of a convention. The folder-name
-- test is rename-immune (the standalone build never renames "Standalone").
local IS_STANDALONE = type(ADDON_NAME) == "string" and ADDON_NAME:find("Standalone") ~= nil
local _svLoaded = false   -- true once ADDON_NAME's SavedVariables are live
local _preSVDBs = {}      -- dbs created before that, awaiting re-root

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

    -- Child SV globals are vestigial (all data lives in EllesmereUIDB).
    -- Wipe in-place (not replace) so WoW's SV serializer, which holds
    -- the original table reference from load time, saves the empty table.
    if _G[svName] and type(_G[svName]) == "table" then
        wipe(_G[svName])
    else
        _G[svName] = {}
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
                    EllesmereUI.Print("|cffff6600EllesmereUI:|r Profile data for " .. folder .. " was corrupted and has been repaired. Your settings may have been reset to defaults.")
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

    -- Created before the owning addon's SavedVariables loaded: the real
    -- saved table will replace EllesmereUIDB momentarily, so queue this db
    -- for the in-place re-root at ADDON_LOADED (see _preSVDBs above).
    if IS_STANDALONE and not _svLoaded then
        tinsert(_preSVDBs, db)
    end

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

--------------------------------------------------------------------------------
--  Stale central-DB guard
--------------------------------------------------------------------------------
-- WoW executes a child addon's ENTIRE WTF SavedVariables file when the child
-- loads -- including variables its TOC no longer declares (the TOC only
-- controls what gets WRITTEN at logout). A child TOC that ever declared
-- "## SavedVariables: EllesmereUIDB" left a full copy of the central DB in
-- that child's WTF file; if the child was then disabled, the copy froze.
-- Re-enabling the child executes the frozen copy AFTER the parent loaded the
-- real DB, replacing it -- and the next logout persists the stale data over
-- the real file (all profiles wiped).
--
-- The guard captures the authoritative table at the parent's own ADDON_LOADED
-- (the only moment it is guaranteed to be the freshly-loaded real data) and
-- re-points the global at it if any later load in the startup batch swapped
-- the table. It runs before the init queue below, so a poisoned child's own
-- OnInitialize never sees the stale table. Armed only until PLAYER_LOGIN:
-- every suite child is a hard dependency (never LoadOnDemand), so all of
-- them -- and any possible stale file -- load before then. Post-login
-- ADDON_LOADEDs (Blizzard on-demand addons) and intentional table swaps
-- (full reset + ReloadUI) are never touched. If the parent DB failed to
-- load (nil), the guard stays unarmed and behavior is unchanged.
local _parentDBRef           -- the table the parent's own SV file produced
local _dbGuardArmed = true   -- true from load until PLAYER_LOGIN

-- Re-root dbs created before the owning addon's SavedVariables loaded (see
-- _preSVDBs above): resolve the profile inside the REAL loaded central store,
-- merge defaults, and update the db object IN PLACE so every closure holding
-- it reads and writes the table WoW will serialize at logout. The vestigial
-- child SV global is re-wiped in place (its saved copy loaded after NewDB's
-- file-scope wipe and would otherwise persist junk).
local function RerootPreSVDBs()
    if #_preSVDBs == 0 then return end
    local profileName = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if type(EllesmereUIDB.profiles) ~= "table" then EllesmereUIDB.profiles = {} end
    if type(EllesmereUIDB.profiles[profileName]) ~= "table" then
        EllesmereUIDB.profiles[profileName] = {}
    end
    local profileData = EllesmereUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end
    for _, db in ipairs(_preSVDBs) do
        if type(profileData.addons[db.folder]) ~= "table" then
            profileData.addons[db.folder] = {}
        end
        local profile = profileData.addons[db.folder]
        if db._profileDefaults then
            DeepMergeDefaults(profile, db._profileDefaults)
        end
        db.sv = EllesmereUIDB
        db._profileName = profileName
        db.profile = profile
        if _G[db.svName] and type(_G[db.svName]) == "table" then
            wipe(_G[db.svName])
        else
            _G[db.svName] = {}
        end
    end
    wipe(_preSVDBs)
end

local lifecycleFrame = CreateFrame("Frame")
lifecycleFrame:RegisterEvent("ADDON_LOADED")
lifecycleFrame:RegisterEvent("PLAYER_LOGIN")
lifecycleFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            _parentDBRef = EllesmereUIDB
            if IS_STANDALONE then
                _svLoaded = true
                RerootPreSVDBs()
            end
        elseif _dbGuardArmed and _parentDBRef and EllesmereUIDB ~= _parentDBRef then
            -- A stale SavedVariables copy from a child's WTF file replaced
            -- the central DB. Restore the real table; the stale copy purges
            -- from the offending file on its next logout (its TOC no longer
            -- declares the variable).
            EllesmereUIDB = _parentDBRef
        end
    elseif event == "PLAYER_LOGIN" then
        _dbGuardArmed = false
    end

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
