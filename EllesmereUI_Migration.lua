--------------------------------------------------------------------------------
--  EllesmereUI_Migration.lua
--  Loaded via TOC after EllesmereUI_Lite.lua, before EllesmereUI_Profiles.lua.
--  Runs at ADDON_LOADED time for "EllesmereUI" (before child addons init).
--
--  All legacy migrations have been removed. The beta-exit wipe (reset
--  version 5) guarantees every user starts from a clean slate.
--------------------------------------------------------------------------------

local floor = math.floor

--- Round all width/height values in a table to whole pixels.
--- Call from each child addon's OnInitialize after its DB is loaded.
--- keys: list of field names to round (e.g. {"width", "height"})
--- tables: list of profile sub-tables to scan
function EllesmereUI.RoundSizeFields(keys, tables)
    for _, tbl in ipairs(tables) do
        if type(tbl) == "table" then
            for _, key in ipairs(keys) do
                local v = tbl[key]
                if type(v) == "number" then
                    tbl[key] = floor(v + 0.5)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  ONE-TIME MIGRATION RUNNER
--
--  Single, global system for any addon to register a one-time data migration
--  that needs to run reliably across upgrades, multiple characters, multiple
--  profiles, and multiple specs.
--
--  USAGE:
--    EllesmereUI.RegisterMigration({
--        id          = "cdm_pandemic_glow_color_table",
--        scope       = "profile",  -- "global" | "profile" | "specProfile"
--        description = "Migrate flat pandemicR/G/B keys to pandemicGlowColor table",
--        body        = function(ctx)
--            -- ctx fields depend on scope:
--            --   global       -> ctx.db (= EllesmereUIDB)
--            --   profile      -> ctx.profile, ctx.profileName
--            --   specProfile  -> ctx.specProfile, ctx.specKey
--            local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
--            local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
--            if not bars then return end
--            for _, b in ipairs(bars) do
--                if b.pandemicR and not b.pandemicGlowColor then
--                    b.pandemicGlowColor = { r = b.pandemicR, g = b.pandemicG, b = b.pandemicB }
--                end
--            end
--        end,
--    })
--
--  GUARANTEES:
--    - Migration body wraps in pcall: a buggy body cannot break the runner.
--    - Flag is stamped only on success: a failed body retries next session.
--    - "global" scope flag lives at EllesmereUIDB._migrations[id]
--    - "profile" scope flag lives at profileData._migrations[id], runner walks
--      ALL profiles so multi-character is handled in one pass.
--    - "specProfile" scope flag lives at specProfData._migrations[id], runner
--      walks ALL spec profiles so multi-spec is handled in one pass.
--    - Phase: currently only "early" (parent ADDON_LOADED, before child
--      addons init). Add more phases lazily if a real need appears.
--
--  AUTHORING RULES:
--    1. IDs are forever. Never change an existing migration's id; register a
--       new migration with a new id if logic needs to change.
--    2. Bodies must be idempotent. Even with the flag, the body should be
--       safe to re-run on already-migrated data (predicate-gated).
--    3. Don't iterate profiles inside a body if scope = "profile" -- the
--       runner does that for you. Same for "specProfile".
--    4. Don't call live game APIs (UnitClass, GetSpecialization,
--       C_CooldownViewer, etc.) -- only "early" phase exists, none of these
--       are reliable yet.
--    5. Walk raw stored data via ctx.profile / ctx.specProfile, not via
--       child.db.profile -- child addons haven't initialized yet.
--------------------------------------------------------------------------------

local _migrations = {}              -- ordered registration list (1..N)
local _migrationsById = {}          -- id -> spec, for dedup + lookup
local _migrationErrors = {}         -- session-only error buffer for /eui migrations
EllesmereUI._migrationErrors = _migrationErrors

local VALID_SCOPES = { global = true, profile = true, specProfile = true }

function EllesmereUI.RegisterMigration(spec)
    if type(spec) ~= "table" then
        error("RegisterMigration: spec must be a table", 2)
    end
    if type(spec.id) ~= "string" or spec.id == "" then
        error("RegisterMigration: spec.id must be a non-empty string", 2)
    end
    if type(spec.body) ~= "function" then
        error("RegisterMigration: spec.body must be a function", 2)
    end
    if not VALID_SCOPES[spec.scope] then
        error("RegisterMigration: spec.scope must be 'global', 'profile', or 'specProfile' (got '" .. tostring(spec.scope) .. "')", 2)
    end
    if _migrationsById[spec.id] then
        error("RegisterMigration: duplicate migration id '" .. spec.id .. "'", 2)
    end
    _migrations[#_migrations + 1] = spec
    _migrationsById[spec.id] = spec
end

-- Get (and lazily create) the per-scope flag table on the host table.
local function GetFlagTable(host)
    if not host._migrations then host._migrations = {} end
    return host._migrations
end

-- Run a single migration body, stamp the flag on success, log on error.
local function RunOne(spec, ctx, flagHost)
    local flags = GetFlagTable(flagHost)
    if flags[spec.id] then return end
    local ok, err = pcall(spec.body, ctx)
    if ok then
        flags[spec.id] = true
    else
        _migrationErrors[#_migrationErrors + 1] = {
            id    = spec.id,
            scope = spec.scope,
            err   = tostring(err),
            time  = GetTime(),
        }
    end
end

-- Iterate one migration across the appropriate set of targets for its scope.
local function RunMigration(spec)
    if spec.scope == "global" then
        RunOne(spec, { db = EllesmereUIDB }, EllesmereUIDB)

    elseif spec.scope == "profile" then
        if EllesmereUIDB.profiles then
            for profName, profData in pairs(EllesmereUIDB.profiles) do
                if type(profData) == "table" then
                    RunOne(spec, {
                        profile     = profData,
                        profileName = profName,
                    }, profData)
                end
            end
        end

    elseif spec.scope == "specProfile" then
        -- Per-profile spell store: spellAssignments.profiles[name].specProfiles.
        -- The cdm_per_profile_spell_store_v1 migration (registered first) seeds
        -- these buckets from the legacy flat store before any specProfile
        -- migration runs, so iterating the nested structure covers every
        -- profile's per-spec data in one pass. Flag still lives on each
        -- specProfData._migrations table (carried forward verbatim by seeding).
        local sa = EllesmereUIDB.spellAssignments
        local profiles = sa and sa.profiles
        if profiles then
            for profName, bucket in pairs(profiles) do
                local sp = type(bucket) == "table" and bucket.specProfiles
                if type(sp) == "table" then
                    for specKey, specProfData in pairs(sp) do
                        if type(specProfData) == "table" then
                            RunOne(spec, {
                                specProfile = specProfData,
                                specKey     = specKey,
                                profileName = profName,
                            }, specProfData)
                        end
                    end
                end
            end
        end
    end
end

-- Public: run all registered migrations. Called once from the parent
-- ADDON_LOADED handler (the legacy beta-wipe that used to precede it is gone).
function EllesmereUI.RunRegisteredMigrations()
    if not EllesmereUIDB then return end
    for _, spec in ipairs(_migrations) do
        RunMigration(spec)
    end
end

-- Inspection helper for the slash command.
function EllesmereUI.GetMigrationStatus()
    local out = {
        registered = {},
        errors     = _migrationErrors,
    }
    for _, spec in ipairs(_migrations) do
        local entry = {
            id          = spec.id,
            scope       = spec.scope,
            description = spec.description or "",
            ranScopes   = {}, -- list of {target, ran}
        }
        if spec.scope == "global" then
            local flags = EllesmereUIDB and EllesmereUIDB._migrations
            entry.ranScopes[1] = { target = "global", ran = (flags and flags[spec.id]) and true or false }
        elseif spec.scope == "profile" then
            if EllesmereUIDB and EllesmereUIDB.profiles then
                for profName, profData in pairs(EllesmereUIDB.profiles) do
                    if type(profData) == "table" then
                        local flags = profData._migrations
                        entry.ranScopes[#entry.ranScopes + 1] = {
                            target = profName,
                            ran    = (flags and flags[spec.id]) and true or false,
                        }
                    end
                end
            end
        elseif spec.scope == "specProfile" then
            local profiles = EllesmereUIDB and EllesmereUIDB.spellAssignments and EllesmereUIDB.spellAssignments.profiles
            if profiles then
                for profName, bucket in pairs(profiles) do
                    local sp = type(bucket) == "table" and bucket.specProfiles
                    if type(sp) == "table" then
                        for specKey, specProfData in pairs(sp) do
                            if type(specProfData) == "table" then
                                local flags = specProfData._migrations
                                entry.ranScopes[#entry.ranScopes + 1] = {
                                    target = profName .. "/" .. specKey,
                                    ran    = (flags and flags[spec.id]) and true or false,
                                }
                            end
                        end
                    end
                end
            end
        end
        out.registered[#out.registered + 1] = entry
    end
    return out
end

-- /eui migrations slash command. Lists registered migrations, run status
-- per scope target, and any session errors.
SLASH_EUIMIGRATIONS1 = "/euimig"
SLASH_EUIMIGRATIONS2 = "/euimigrations"
SlashCmdList["EUIMIGRATIONS"] = function()
    local status = EllesmereUI.GetMigrationStatus()
    print("|cff0cd29fEllesmereUI Migrations|r")
    print(string.format("  Registered: %d", #status.registered))
    for _, entry in ipairs(status.registered) do
        local ranCount, totalCount = 0, #entry.ranScopes
        for _, s in ipairs(entry.ranScopes) do if s.ran then ranCount = ranCount + 1 end end
        local marker
        if totalCount == 0 then
            marker = "|cffaaaaaa(no targets)|r"
        elseif ranCount == totalCount then
            marker = "|cff00ff00OK|r"
        elseif ranCount == 0 then
            marker = "|cffff8800PENDING|r"
        else
            marker = string.format("|cffffff00%d/%d|r", ranCount, totalCount)
        end
        print(string.format("  [%s] %s (%s)", marker, entry.id, entry.scope))
        if entry.description ~= "" then
            print("      |cffaaaaaa" .. entry.description .. "|r")
        end
    end
    if #status.errors > 0 then
        print(string.format("|cffff4444Errors this session: %d|r", #status.errors))
        for _, e in ipairs(status.errors) do
            print(string.format("  |cffff4444[%s]|r %s", e.id, e.err))
        end
    else
        print("|cff00ff00No errors this session.|r")
    end
end

--------------------------------------------------------------------------------
--  Position snap helpers
--  File-scope helpers used by the position_snap_v3 migration below AND
--  exposed on EllesmereUI for profile import (import path calls
--  EllesmereUI.SnapProfilePositions(profData) to snap imported positions).
--
--  These are FUNCTION definitions only -- the bodies run on demand, not at
--  file load. Reads of EllesmereUIDB.ppUIScale and GetPhysicalScreenSize()
--  inside MakeSnappers() happen whenever the function is called, by which
--  time SavedVariables are loaded and the screen size API is available.
--------------------------------------------------------------------------------

local function MakeSnappers()
    local physH = select(2, GetPhysicalScreenSize())
    local perfect = physH and physH > 0 and (768 / physH) or 1
    local uiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or perfect
    if uiScale <= 0 then uiScale = perfect end
    local onePixel = perfect / uiScale

    local function snap(v)
        if type(v) ~= "number" or v == 0 then return v end
        -- Epsilon-guarded round (matches PP.SnapForES): position values sitting
        -- a hair off a half-pixel boundary must snap the same way here as at
        -- runtime, or the one-time migration shifts frames 1px.
        local result = floor(v / onePixel + 0.5 + 0.001) * onePixel
        -- Clean floating point dust
        local rounded = floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end
    local function snapPos(tbl)
        if type(tbl) ~= "table" then return end
        if tbl.x then tbl.x = snap(tbl.x) end
        if tbl.y then tbl.y = snap(tbl.y) end
    end
    local function snapPosMap(map)
        if type(map) ~= "table" then return end
        for _, pos in pairs(map) do snapPos(pos) end
    end
    local function snapAnchors(anchors)
        if type(anchors) ~= "table" then return end
        for _, info in pairs(anchors) do
            if type(info) == "table" then
                if info.offsetX then info.offsetX = snap(info.offsetX) end
                if info.offsetY then info.offsetY = snap(info.offsetY) end
            end
        end
    end
    return snapPos, snapPosMap, snapAnchors, snap
end

-- Snap all positions in a single profile data table.
-- Called by the position_snap_v3 migration (for each profile) and by
-- profile import (for a single imported profile).
local function SnapProfilePositions(profData)
    if type(profData) ~= "table" then return end
    local snapPos, snapPosMap, snapAnchors = MakeSnappers()

    local ul = profData.unlockLayout
    if ul then snapAnchors(ul.anchors) end

    local addons = profData.addons
    if type(addons) ~= "table" then return end

    local uf = addons.EllesmereUIUnitFrames
    if uf then snapPosMap(uf.positions) end

    local eab = addons.EllesmereUIActionBars
    if eab then snapPosMap(eab.barPositions) end

    local cdm = addons.EllesmereUICooldownManager
    if cdm then snapPosMap(cdm.cdmBarPositions) end

    local erb = addons.EllesmereUIResourceBars
    if type(erb) == "table" then
        for _, section in pairs(erb) do
            if type(section) == "table" and section.unlockPos then
                snapPos(section.unlockPos)
            end
        end
    end

    local abr = addons.EllesmereUIAuraBuffReminders
    if type(abr) == "table" and abr.unlockPos then
        snapPos(abr.unlockPos)
    end

    local basics = addons.EllesmereUIBasics
    if type(basics) == "table" then
        if basics.questTracker then snapPos(basics.questTracker.pos) end
        if basics.minimap then snapPos(basics.minimap.position) end
        if basics.friends then snapPos(basics.friends.position) end
    end

    local cursor = addons.EllesmereUICursor
    if type(cursor) == "table" then
        if cursor.gcd then snapPos(cursor.gcd.pos) end
        if cursor.cast then snapPos(cursor.cast.pos) end
    end
end

-- Expose for profile import
EllesmereUI.SnapProfilePositions = SnapProfilePositions

-- Collect every per-profile spec-profile data table into a flat array. After
-- the cdm_per_profile_spell_store_v1 seeding migration, CDM spell data lives at
-- spellAssignments.profiles[name].specProfiles (per profile), not the legacy
-- flat spellAssignments.specProfiles. Global-scope migration bodies that used to
-- walk the flat store call this so they transform the LIVE per-profile data.
-- Seeding is registered first, so the buckets exist by the time any body runs.
local function CollectSpecProfiles(sa)
    local out = {}
    if type(sa) ~= "table" then return out end
    local profiles = sa.profiles
    if type(profiles) == "table" then
        for _, bucket in pairs(profiles) do
            local sp = type(bucket) == "table" and bucket.specProfiles
            if type(sp) == "table" then
                for _, specProfData in pairs(sp) do
                    if type(specProfData) == "table" then
                        out[#out + 1] = specProfData
                    end
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
--  Registered migrations
--  Each migration below is a one-time data transformation gated by the runner's
--  per-scope flag. Bodies must be idempotent. Legacy flag checks bridge the
--  transition from old inline migrations; they can be removed after a few
--  release cycles once all existing users have been through the new system.
--------------------------------------------------------------------------------

-- IMPORTANT: this migration is registered FIRST so it runs before any
-- specProfile-scoped migration. It converts the legacy account-wide CDM spell
-- store (spellAssignments.specProfiles, shared by all profiles on a given spec)
-- into a per-profile store (spellAssignments.profiles[name].specProfiles) by
-- DeepCopying the legacy data into EVERY existing profile. This is what makes a
-- profile copy own an independent CDM: before this, deleting a bar in a copied
-- profile mutated the one shared bucket and wiped the origin. The DeepCopy
-- carries each spec's _migrations flags forward verbatim, so already-run
-- specProfile migrations do not re-run against the seeded copies. The legacy
-- flat table is left in place as a dormant backup for one release; nothing
-- reads it after seeding. NOTE: this is the spellAssignments.specProfiles store,
-- NOT the unrelated EllesmereUIDB.specProfiles spec-to-profile auto-switch map.
-- Spec Overrides fresh start (2026-07-11): the unlock override backend was
-- rewritten from per-aspect diffs to whole-layout LAYERS, and the value/group
-- stores accumulated tester-era data shaped for the old model. User-directed
-- full wipe: groups, value entries, and unlock overrides all reset.
--
-- The RB Advanced migration's output lives in these same tables, so a
-- profile that already ran it must be RE-ARMED before the wipe: the source
-- data is restored from rb.advancedSpecsBackup and the run flag cleared, so
-- Resource Bars' init re-creates its spec override cards into the clean
-- store on this same login. Re-running MergeThresholds on the already-merged
-- Simple list converges (first-run inserts serve only that spec, so the
-- strip pass removes them before identical copies are re-inserted).
do
    local function RearmRBAdvancedMigration(prof)
        local rb = prof and prof.addons and prof.addons.EllesmereUIResourceBars
        if type(rb) ~= "table" or not rb._rbAdvMigrated then return end
        local backup = rb.advancedSpecsBackup
        if type(backup) == "table" then
            rb.advancedSpecs = backup.advancedSpecs
            if type(backup.disabledSpecs) == "table" then
                for secKey, ds in pairs(backup.disabledSpecs) do
                    if type(rb[secKey]) == "table" then
                        rb[secKey].disabledSpecs = ds
                    end
                end
            end
            rb.advancedSpecsBackup = nil
        end
        rb._rbAdvMigrated = nil
    end

    EllesmereUI.RegisterMigration({
        id          = "spec_overrides_fresh_start_v1",
        scope       = "profile",
        description = "Wipe all spec override data (groups, value entries, unlock overrides) for the layer-model fresh start.",
        body        = function(ctx)
            local prof = ctx.profile
            if not prof then return end
            RearmRBAdvancedMigration(prof)
            prof.specOverrideGroups = nil
            prof.specOverrides = nil
            prof.specUnlockOverrides = nil
        end,
    })

    -- Recovery for profiles that ran an early fresh-start build WITHOUT the
    -- re-arm above: their RB-migrated cards were wiped, but the source data
    -- still sits untouched in rb.advancedSpecsBackup. Re-arm those profiles
    -- once so Resource Bars' init re-creates the cards. No-ops everywhere
    -- else: on a first login where both migrations are pending, the fixed
    -- fresh start has already cleared the RB flag before this runs (and the
    -- reverse order would converge to the same state anyway).
    --
    -- Guard: a profile whose FIRST login with the RB migration happened on a
    -- fresh-start build got its cards created AFTER the wipe (early runner
    -- precedes RB init), so they still exist -- re-arming there would append
    -- duplicates. Only re-arm when the store holds no RB-module entries.
    EllesmereUI.RegisterMigration({
        id          = "rb_adv_remigrate_after_wipe_v1",
        scope       = "profile",
        description = "Re-run the RB Advanced migration for profiles whose migrated spec override cards were wiped by the fresh start.",
        body        = function(ctx)
            local prof = ctx.profile
            if not prof then return end
            if type(prof.specOverrides) == "table" then
                for _, e in ipairs(prof.specOverrides) do
                    if type(e) == "table" and e.module == "EllesmereUIResourceBars" then
                        return
                    end
                end
            end
            RearmRBAdvancedMigration(prof)
        end,
    })
end

-- CDM bar captures recorded before the numeric-segment path walkers existed
-- banked NIL sentinels for every value (the reads missed the numeric bars[i]
-- keys entirely); applying them through the FIXED walkers would null out
-- live CDM bar settings on the next spec swap. The broken window was a
-- tester build measured in hours -- drop every CDM-bars capture from both
-- override stores; users re-capture with working walkers.
EllesmereUI.RegisterMigration({
    id          = "cdm_bars_capture_reset_v1",
    scope       = "profile",
    description = "Drop corrupt CDM bar captures recorded by the pre-numeric-walker override builds.",
    body        = function(ctx)
        local prof = ctx.profile
        if not prof then return end
        local PREFIX = "EllesmereUICooldownManager\31cdmBars\30bars\30"
        local function sweep(store)
            if type(store) ~= "table" then return end
            for i = #store, 1, -1 do
                local e = store[i]
                local def = type(e) == "table" and e.values and e.values.default
                if type(def) == "table" then
                    for fkey in pairs(def) do
                        if type(fkey) == "string" and fkey:sub(1, #PREFIX) == PREFIX then
                            table.remove(store, i)
                            break
                        end
                    end
                end
            end
        end
        sweep(prof.specOverrides)
        sweep(prof.condOverrides)
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_per_profile_spell_store_v1",
    scope       = "global",
    description = "Fork the shared per-spec CDM spell store into every profile so profile copies own independent CDM data.",
    body        = function(ctx)
        local db = ctx.db
        local sa = db and db.spellAssignments
        if not sa then return end               -- fresh install: nothing stored yet
        if sa._perProfileSeeded then return end -- already converted
        local legacy = sa.specProfiles          -- old account-wide per-spec store
        if not sa.profiles then sa.profiles = {} end
        local DeepCopy = EllesmereUI._DeepCopy or (EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy)
        local function seed(name)
            if not name then return end
            if sa.profiles[name] then return end -- idempotent: never clobber an existing bucket
            local sp = {}
            if legacy and DeepCopy then sp = DeepCopy(legacy) end
            sa.profiles[name] = { specProfiles = sp }
        end
        if db.profiles then
            for name, pd in pairs(db.profiles) do
                if type(pd) == "table" then seed(name) end
            end
        end
        -- Ensure the active/Default profile has a bucket even if it is not yet
        -- present in db.profiles (very early / minimal-state installs).
        seed(db.activeProfile or "Default")
        sa._perProfileSeeded = true
    end,
})

-- Consolidate the auto-seeded per-profile CDM buckets (created by the migration
-- above) into spell LAYOUTS: collapse identical duplicates into one, KEEP any
-- genuinely-different setups as their own layouts, and back up the originals.
-- The per-profile seeding copied one CDM setup into every profile, so users
-- otherwise see a redundant layout per profile. Only touches auto-seeded buckets
-- (no `meta`); user-created/imported layouts (which have `meta`) are left alone.
EllesmereUI.RegisterMigration({
    id          = "cdm_consolidate_profile_layouts_v1",
    scope       = "global",
    description = "Collapse identical auto-seeded per-profile CDM buckets into single spell layouts; keep distinct ones; dormant backup at spellAssignments._preConsolidateBackup.",
    body        = function(ctx)
        local db = ctx.db
        local sa = db and db.spellAssignments
        if not sa or type(sa.profiles) ~= "table" then return end
        local DeepCopy = EllesmereUI._DeepCopy or (EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy)

        -- Deep value-equality, IGNORING "_"-prefixed bookkeeping keys (e.g.
        -- _migrations) so two seeded copies that only differ in migration flags
        -- still count as identical.
        local function ContentEqual(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for k, v in pairs(a) do
                if not (type(k) == "string" and k:sub(1, 1) == "_") then
                    if not ContentEqual(v, b[k]) then return false end
                end
            end
            for k in pairs(b) do
                if not (type(k) == "string" and k:sub(1, 1) == "_") then
                    if a[k] == nil then return false end
                end
            end
            return true
        end

        -- Auto-seeded buckets have no `meta`; user-created layouts do. Only the
        -- seeded ones are candidates for consolidation.
        local seeded = {}
        for name, bucket in pairs(sa.profiles) do
            if type(bucket) == "table" and not bucket.meta then
                seeded[#seeded + 1] = name
            end
        end
        if #seeded <= 1 then return end  -- nothing to collapse

        -- One-time dormant backup of every bucket (safety net; recoverable).
        if DeepCopy and not sa._preConsolidateBackup then
            sa._preConsolidateBackup = DeepCopy(sa.profiles)
        end

        -- Process the active profile first so its name is the kept representative
        -- for the live setup; rest alphabetically for determinism.
        local activeName = db.activeProfile or "Default"
        table.sort(seeded)
        local ordered = {}
        if sa.profiles[activeName] and not sa.profiles[activeName].meta then
            ordered[#ordered + 1] = activeName
        end
        for _, n in ipairs(seeded) do
            if n ~= activeName then ordered[#ordered + 1] = n end
        end

        local kept = {}
        local repOf = {}   -- every processed seeded name -> its surviving layout
        for _, name in ipairs(ordered) do
            local bucket = sa.profiles[name]
            local rep
            for _, kn in ipairs(kept) do
                if ContentEqual(sa.profiles[kn].specProfiles or {}, bucket.specProfiles or {}) then
                    rep = kn; break
                end
            end
            if rep then
                sa.profiles[name] = nil   -- identical duplicate: drop it
                repOf[name] = rep
            else
                kept[#kept + 1] = name
                repOf[name] = name
            end
        end

        -- The active layout is remembered PER EUI PROFILE: point each profile at
        -- the surviving layout holding its own (pre-consolidation) CDM, so
        -- switching profiles loads that profile's setup. Don't clobber a pointer
        -- the user already set.
        sa.activeLayoutByProfile = sa.activeLayoutByProfile or {}
        if db.profiles then
            for pname in pairs(db.profiles) do
                if not sa.activeLayoutByProfile[pname] and repOf[pname] then
                    sa.activeLayoutByProfile[pname] = repOf[pname]
                end
            end
        end
        local activeRep = repOf[activeName] or kept[1] or activeName
        if not sa.activeLayoutByProfile[activeName] then
            sa.activeLayoutByProfile[activeName] = activeRep
        end
        -- Global last-active = default for any profile without a pointer yet.
        if not sa.activeLayout or not sa.profiles[sa.activeLayout] then
            sa.activeLayout = activeRep
        end
    end,
})

-- Detach CDM spell layouts from profiles. Converts the implicit per-profile
-- active-layout map (activeLayoutByProfile) into OPT-IN bindings (profileBindings)
-- plus a single account-wide active layout. Behavior-identical on update: every
-- profile is bound to exactly the layout it used, so swapping profiles still
-- auto-activates that layout. The user detaches by removing bindings.
-- Runs AFTER cdm_consolidate_profile_layouts_v1 (registration order), so it
-- inherits the deduped layouts + per-profile pointers.
EllesmereUI.RegisterMigration({
    id          = "cdm_detach_spell_layouts_v1",
    scope       = "global",
    description = "Convert per-profile active CDM spell layouts (activeLayoutByProfile) into opt-in profile bindings + a single account-wide active layout. Zero behavior change.",
    body = function(ctx)
        local db = ctx.db
        local sa = db and db.spellAssignments
        if type(sa) ~= "table" then return end
        local byProfile = sa.activeLayoutByProfile
        sa.profileBindings = sa.profileBindings or {}
        if type(byProfile) == "table" then
            for prof, layout in pairs(byProfile) do
                if type(prof) == "string" and type(layout) == "string"
                   and type(sa.profiles) == "table" and type(sa.profiles[layout]) == "table" then
                    -- Don't clobber a binding the user may already have set.
                    if sa.profileBindings[prof] == nil then
                        sa.profileBindings[prof] = layout
                    end
                end
            end
        end
        -- Account-wide active = the current profile's layout, so the live CDM is
        -- byte-for-byte unchanged on this character. Fall back to the old global
        -- pointer, then any valid layout.
        local cur = db.activeProfile or "Default"
        local active = sa.profileBindings[cur]
        if type(active) ~= "string" or not (sa.profiles and sa.profiles[active]) then
            if type(sa.activeLayout) == "string" and sa.profiles and sa.profiles[sa.activeLayout] then
                active = sa.activeLayout
            else
                active = nil
                if type(sa.profiles) == "table" then
                    for n, v in pairs(sa.profiles) do if type(v) == "table" then active = n; break end end
                end
            end
        end
        sa.activeLayout = active
        -- Retire the old per-profile resolution table (back up first, then clear).
        if byProfile then
            sa._preDetachBackup = byProfile
            sa.activeLayoutByProfile = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "quest_tracker_sec_color_default",
    scope       = "profile",
    description = "Clear questTracker.secColor if it matches the legacy hardcoded green default, so accent color fallback can take over.",
    body = function(ctx)
        -- Legacy bridge: skip if the old inline migration already ran.
        -- Old flag location: EllesmereUIDB._questTrackerSecColorMigrated
        if EllesmereUIDB and EllesmereUIDB._questTrackerSecColorMigrated then return end

        local addons = ctx.profile.addons
        local basics = addons and addons.EllesmereUIBasics
        if not basics or not basics.questTracker then return end
        local sc = basics.questTracker.secColor
        if type(sc) == "table"
           and sc.r == 0.047 and sc.g == 0.824 and sc.b == 0.624 then
            basics.questTracker.secColor = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "quest_tracker_blizzard_skin_rebuild_v1",
    scope       = "global",
    description = "Archive obsolete custom-tracker keys (width/height/alignment/bg/font/color/zone/world/prey/topLine) into _legacy so they stop polluting questTracker defaults after the rebuild to a skin+QoL layer.",
    body = function()
        local sv = _G.EllesmereUIQuestTrackerDB
        if type(sv) ~= "table" then return end
        local profiles = sv.profiles
        if type(profiles) ~= "table" then return end

        local OBSOLETE = {
            "width", "height", "alignment",
            "bgR", "bgG", "bgB", "bgAlpha",
            "showTopLine",
            "showZoneQuests", "showWorldQuests", "showPreyQuests",
            "showQuestItems", "questItemSize",
            "zoneCollapsed", "worldCollapsed", "preyCollapsed",
            "delveCollapsed", "questsCollapsed", "achievementsCollapsed",
            "titleFontSize", "objFontSize", "completedFontSize",
            "secFontSize", "focusedFontSize",
            "titleColor", "objColor", "completedColor", "secColor", "focusedColor",
            "secColorUseAccent",
            "focusBgOpacity",
            "hideBlizzardTracker",
        }

        for _, prof in pairs(profiles) do
            if type(prof) == "table" and type(prof.questTracker) == "table" then
                local qt = prof.questTracker
                local legacy = qt._legacy or {}
                local moved = false
                for _, k in ipairs(OBSOLETE) do
                    if qt[k] ~= nil then
                        legacy[k] = qt[k]
                        qt[k] = nil
                        moved = true
                    end
                end
                if moved then qt._legacy = legacy end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "friends_data_wipe_v1",
    scope       = "profile",
    description = "Wipe legacy friends list data across all profiles (sessions 15-17 module rebuild).",
    body = function(ctx)
        -- Legacy bridge: skip if the old inline migration already ran.
        -- Old flag location: EllesmereUIDB._friendsWipeDone
        -- DESTRUCTIVE: this resets basics.friends to { enabled = wasEnabled }.
        -- The bridge is critical -- without it, re-running would wipe any
        -- configuration the user has made since the original migration.
        if EllesmereUIDB and EllesmereUIDB._friendsWipeDone then return end

        local addons = ctx.profile.addons
        local basics = addons and addons.EllesmereUIBasics
        if not basics or not basics.friends then return end

        local wasEnabled = basics.friends.enabled
        basics.friends = { enabled = wasEnabled }
    end,
})

EllesmereUI.RegisterMigration({
    id          = "friend_notes_wipe_v1",
    scope       = "global",
    description = "Wipe legacy bnetAccountID-keyed friendAssignments and friendNotes (sessions 15-17 rebuild).",
    body = function(ctx)
        -- Legacy bridge: skip if the old inline migration already ran.
        -- Old flag location: EllesmereUIDB.global._friendNotesMigrated
        -- DESTRUCTIVE: wipes EllesmereUIDB.global.friendAssignments and
        -- .friendNotes. Without the bridge, re-running would destroy any
        -- data the user has accumulated since the original migration.
        if EllesmereUIDB and EllesmereUIDB.global
           and EllesmereUIDB.global._friendNotesMigrated then return end

        local g = ctx.db.global
        if not g then return end

        -- Set the one-time popup flag only if the user actually had
        -- group assignments pre-wipe (so users who never used the feature
        -- don't see a popup about it being "reset").
        local hadAssignments = false
        if g.friendAssignments then
            for _ in pairs(g.friendAssignments) do
                hadAssignments = true
                break
            end
        end
        if hadAssignments then
            g._friendGroupReassignPopup = true
        end

        g.friendAssignments = {}
        g.friendNotes = {}
    end,
})

-- Pixel-perfect snapping split into global (unlock anchors, spec profiles) and
-- per-profile (positions + sizes). The per-profile half runs on every profile
-- including future imports (flag is per-profile so the runner catches new ones).
-- The global half keeps the original flag so existing users don't re-run it.
EllesmereUI.RegisterMigration({
    id          = "pixel_perfect_comprehensive_v11",
    scope       = "global",
    description = "Snap global unlock anchors and spec-profile TBB positions/sizes to the physical pixel grid.",
    body = function(ctx)
        local snapPos, snapPosMap, snapAnchors, snapVal = MakeSnappers()
        local function roundFields(tbl, keys)
            if not tbl then return end
            for _, key in ipairs(keys) do
                if type(tbl[key]) == "number" then
                    tbl[key] = snapVal(tbl[key])
                end
            end
        end

        -- Global: unlock anchors
        snapAnchors(ctx.db.unlockAnchors)

        -- Spec profiles (per-profile store): TBB positions + bar sizes
        for _, specData in ipairs(CollectSpecProfiles(ctx.db.spellAssignments)) do
            local tbbPos = specData.tbbPositions
            if tbbPos then
                for _, pos in pairs(tbbPos) do
                    if type(pos) == "table" then snapPos(pos) end
                end
            end
            local tbb = specData.trackedBuffBars
            local tbbBars = tbb and tbb.bars
            if tbbBars then
                for _, bar in ipairs(tbbBars) do
                    if type(bar) == "table" then
                        roundFields(bar, { "width", "height" })
                    end
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "pixel_perfect_profile_v1",
    scope       = "profile",
    description = "Snap all per-profile positions and sizes to the physical pixel grid. Runs on each profile individually so imported profiles are covered.",
    body = function(ctx)
        local snapPos, snapPosMap, _, snapVal = MakeSnappers()
        local function roundFields(tbl, keys)
            if not tbl then return end
            for _, key in ipairs(keys) do
                if type(tbl[key]) == "number" then
                    tbl[key] = snapVal(tbl[key])
                end
            end
        end
        local function snapSection(section, sizeKeys)
            if not section then return end
            roundFields(section, sizeKeys)
            snapPos(section.unlockPos)
        end

        local addons = ctx.profile.addons
        if type(addons) ~= "table" then return end

        -- Action Bars: positions + icon sizes
        local eab = addons.EllesmereUIActionBars
        if eab then
            snapPosMap(eab.barPositions)
            if eab.bars then
                for _, bs in pairs(eab.bars) do
                    if type(bs) == "table" then
                        roundFields(bs, { "buttonWidth", "buttonHeight", "width", "height" })
                    end
                end
            end
        end

        -- Resource Bars: positions + bar sizes + pip sizes
        local erb = addons.EllesmereUIResourceBars
        if erb then
            local erbSizeKeys = { "width", "height", "pipWidth", "pipHeight" }
            snapSection(erb.primary, erbSizeKeys)
            snapSection(erb.secondary, erbSizeKeys)
            snapSection(erb.health, erbSizeKeys)
            snapSection(erb.castBar or erb.castbar, erbSizeKeys)
        end

        -- Unit Frames: positions + frame/cast bar sizes
        local uf = addons.EllesmereUIUnitFrames
        if uf then
            snapPosMap(uf.unlockPositions or uf.positions)
            local ufSizeKeys = { "frameWidth", "healthHeight", "powerHeight",
                "castbarWidth", "castbarHeight", "playerCastbarWidth", "playerCastbarHeight",
                "bottomTextBarHeight" }
            for _, unitKey in ipairs({ "player", "target", "focus", "boss" }) do
                if uf[unitKey] then
                    roundFields(uf[unitKey], ufSizeKeys)
                end
            end
        end

        -- CDM: bar positions + icon sizes
        local cdm = addons.EllesmereUICooldownManager
        if cdm then
            snapPosMap(cdm.cdmBarPositions)
            if cdm.cdmBars and cdm.cdmBars.bars then
                for _, bd in ipairs(cdm.cdmBars.bars) do
                    roundFields(bd, { "iconSize", "spacing", "width", "height" })
                end
            end
        end

        -- Damage Meters
        local dm = addons.EllesmereUIDamageMeters
        if dm then
            snapPos(dm.unlockPos)
            roundFields(dm, { "dmWidth", "dmHeight" })
        end

        -- Chat
        local chat = addons.EllesmereUIChat
        if chat then
            snapPos(chat.unlockPos)
            roundFields(chat, { "chatWidth", "chatHeight" })
        end

        -- ABR
        local abr = addons.EllesmereUIAuraBuffReminders
        if abr and abr.display then
            snapPos(abr.display.unlockPos)
            roundFields(abr.display, { "iconSize", "iconSpacing" })
        end

        -- Basics (minimap, quest tracker)
        local basics = addons.EllesmereUIBasics
        if basics then
            if basics.questTracker then snapPos(basics.questTracker.pos) end
            if basics.minimap then snapPos(basics.minimap.position) end
            if basics.friends then snapPos(basics.friends.position) end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "basics_minimap_hide_buttons_split",
    scope       = "profile",
    description = "Split legacy minimap.hideButtons boolean into per-button keys (hideZoomButtons, hideTrackingButton, hideGameTime).",
    body = function(ctx)
        -- Self-gating: only fires when the legacy hideButtons key still
        -- exists. After running once, mp.hideButtons is nil and the body
        -- is a no-op for that profile.
        local basics = ctx.profile.addons and ctx.profile.addons.EllesmereUIBasics
        local mp = basics and basics.minimap
        if not mp or mp.hideButtons == nil then return end

        if mp.hideButtons == true then
            mp.hideZoomButtons    = true
            mp.hideTrackingButton = true
            mp.hideGameTime       = true
        else
            mp.hideZoomButtons    = false
            mp.hideTrackingButton = false
            mp.hideGameTime       = false
        end
        mp.hideButtons = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "rf_targeted_spells_bool_to_mode_v1",
    scope       = "profile",
    description = "Convert RaidFrames PARTY Targeted Spells tsEnabled boolean to tsMode (false->never, true->whenHealing; nil leaves the default). Raid is NOT migrated -- it hard-defaults to never.",
    body = function(ctx)
        local rf = ctx.profile.addons and ctx.profile.addons.EllesmereUIRaidFrames
        if type(rf) ~= "table" then return end
        -- Self-gating on the new key being absent keeps this idempotent and never
        -- clobbers a value the user has since chosen.
        if rf.tsMode == nil then
            if rf.tsEnabled == false then rf.tsMode = "never"
            elseif rf.tsEnabled == true then rf.tsMode = "whenHealing" end
            -- tsEnabled == nil: leave unset so DeepMergeDefaults applies the default.
        end
        -- Raid is intentionally NOT migrated: it hard-defaults to "never" for all
        -- users (existing tsRaidEnabled is ignored), so tsRaidMode is left unset
        -- here and DeepMergeDefaults applies the "never" default.
    end,
})

EllesmereUI.RegisterMigration({
    id          = "nameplates_miniboss_boss_color_split_v1",
    scope       = "profile",
    description = "Split nameplate mini-boss/boss colors: seed the new 'boss' color from the user's existing 'miniboss' color so bosses keep their current color until changed.",
    body = function(ctx)
        -- Self-gating on boss == nil keeps this idempotent and never clobbers a
        -- value the user has since chosen. Only copies when the user actually
        -- customized miniboss; an unset miniboss leaves boss unset too, so
        -- DeepMergeDefaults applies the (shared) default to both. The import
        -- path forward-copies the same way in ApplyProfileData.
        local np = ctx.profile.addons and ctx.profile.addons.EllesmereUINameplates
        if type(np) ~= "table" then return end
        if np.boss == nil and type(np.miniboss) == "table" then
            np.boss = { r = np.miniboss.r, g = np.miniboss.g, b = np.miniboss.b }
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "uf_power_border_size_zero_v1",
    scope       = "profile",
    description = "Zero out Unit Frames per-unit powerBorderSize. The detached power bar border size only became functional this build; older non-zero values were set while the control did nothing, so clear them so each UI stays visually identical. Users can re-enable a border afterward.",
    body = function(ctx)
        -- Self-gating: once a unit's powerBorderSize is 0 (or absent) it is
        -- skipped, so the body is naturally idempotent on top of the runner's
        -- per-profile flag. Runs once per profile ever; any border the user
        -- sets AFTER the flag is stamped is never touched.
        --
        -- Scoped STRICTLY to EllesmereUIUnitFrames. The RaidFrames addon has its
        -- own, unrelated powerBorderSize (its power border already worked) which
        -- lives at ctx.profile.addons.EllesmereUIRaidFrames and must NOT be
        -- zeroed here.
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end
        local UNIT_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
        for _, unitKey in ipairs(UNIT_KEYS) do
            local u = uf[unitKey]
            if type(u) == "table" and type(u.powerBorderSize) == "number" and u.powerBorderSize ~= 0 then
                u.powerBorderSize = 0
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "basics_minimap_round_to_circle",
    scope       = "profile",
    description = "Rename minimap.shape value 'round' to 'circle'.",
    body = function(ctx)
        local basics = ctx.profile.addons and ctx.profile.addons.EllesmereUIBasics
        local mp = basics and basics.minimap
        if not mp then return end
        if mp.shape == "round" then
            mp.shape = "circle"
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "basics_minimap_strip_scale",
    scope       = "profile",
    description = "Strip the deprecated minimap.scale field. Direct sizing via the snapshot replaces it.",
    body = function(ctx)
        local basics = ctx.profile.addons and ctx.profile.addons.EllesmereUIBasics
        local mp = basics and basics.minimap
        if not mp then return end
        mp.scale = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_pandemic_glow_color_table",
    scope       = "profile",
    description = "Migrate CDM bar flat pandemicR/G/B keys into a pandemicGlowColor table, plus default pandemicGlowStyle.",
    body = function(ctx)
        -- No legacy flag to bridge: original inline migration was self-gated
        -- by the `pandemicR and not pandemicGlowColor` predicate. Body is
        -- naturally idempotent (only fires when the legacy flat keys exist
        -- AND the new table is missing) so the runner's per-profile flag
        -- stops further runs after the first successful pass.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        for _, barData in ipairs(bars) do
            if type(barData) == "table"
               and barData.pandemicR
               and not barData.pandemicGlowColor then
                barData.pandemicGlowColor = {
                    r = barData.pandemicR or 1,
                    g = barData.pandemicG or 1,
                    b = barData.pandemicB or 0,
                }
                barData.pandemicGlowStyle = barData.pandemicGlowStyle or 1
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_repair_bar_keys_v1",
    scope       = "profile",
    description = "Repair CDM bars that lost their `key` field via Lite DB delta-strip. Assigns missing core keys (cooldowns, utility, buffs) in order.",
    body = function(ctx)
        -- Self-gating via `if not bd.key` -- once every bar has a key,
        -- the loop is a no-op. The runner's per-profile flag stops
        -- further runs after the first successful pass.
        --
        -- Originally paired with a Tier 2 defensive guard in
        -- BuildAllCDMBars; that inline guard was deleted after verifying
        -- the round-trip (StripDefaults -> save -> load -> DeepMergeDefaults)
        -- correctly restores identity fields in every code path
        -- including profile switch and import. The runner pass is the
        -- one-time recovery for any user with pre-existing broken data.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        local CORE_KEYS = { "cooldowns", "utility", "buffs" }
        local CORE_NAMES = { cooldowns = "Cooldowns", utility = "Utility", buffs = "Buffs" }

        local present = {}
        for _, bd in ipairs(bars) do
            if bd.key then present[bd.key] = true end
        end
        local missing = {}
        for _, ck in ipairs(CORE_KEYS) do
            if not present[ck] then missing[#missing + 1] = ck end
        end
        if #missing == 0 then return end

        local mi = 1
        for _, bd in ipairs(bars) do
            if not bd.key and mi <= #missing then
                bd.key = missing[mi]
                bd.name = bd.name or CORE_NAMES[missing[mi]]
                if bd.enabled == nil then bd.enabled = true end
                mi = mi + 1
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_remove_misc_bars",
    scope       = "profile",
    description = "Remove obsolete CDM bars with barType=='misc' and clear anchorTo references that pointed at them.",
    body = function(ctx)
        -- Self-gating via the barType check -- once misc bars are gone,
        -- the predicate is false and the body is a no-op. Previously ran
        -- every BuildAllCDMBars call against the active profile only;
        -- the runner promotes this to once-per-profile-ever and walks
        -- all profiles automatically.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        -- Pass 1: find and remove misc bars (reverse iteration so removal
        -- doesn't shift indices we still need to visit).
        local miscKeys = {}
        for i = #bars, 1, -1 do
            if bars[i].barType == "misc" then
                miscKeys[bars[i].key] = true
                table.remove(bars, i)
            end
        end

        -- Pass 2: clear anchorTo on any remaining bar that referenced
        -- a removed misc bar.
        if next(miscKeys) then
            for _, bd in ipairs(bars) do
                if bd.anchorTo and miscKeys[bd.anchorTo] then
                    bd.anchorTo = "none"
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_active_state_anim_none_to_hideactive",
    scope       = "profile",
    description = "Rename CDM bar activeStateAnim value 'none' (No Animation) to 'hideActive' (Hide Active State).",
    body = function(ctx)
        -- Self-gating via the value check -- once no bar holds the legacy
        -- 'none' value, the body is a no-op. MUST register before
        -- cdm_active_state_per_bar_to_per_icon, which depends on bars
        -- carrying the post-rename 'hideActive' value.
        --
        -- Previously ran every BuildAllCDMBars call against the active
        -- profile only; the runner promotes this to once-per-profile-ever
        -- and walks all profiles automatically.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        for _, bd in ipairs(bars) do
            if bd.activeStateAnim == "none" then
                bd.activeStateAnim = "hideActive"
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_mouseover_visibility_to_always",
    scope       = "profile",
    description = "Rewrite CDM bar barVisibility 'mouseover' to 'always' (mouseover mode was removed).",
    body = function(ctx)
        -- Self-gating: once no bar carries 'mouseover', the body is a no-op.
        -- Previously ran every CDMFinishSetup against the active profile;
        -- the runner promotes this to once-per-profile-ever and walks
        -- all profiles automatically.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        for _, bd in ipairs(bars) do
            if bd.barVisibility == "mouseover" then
                bd.barVisibility = "always"
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_strip_tbb_linked_frames",
    scope       = "specProfile",
    description = "Strip stale _linkedFrame/_linkedCdID/_linkedGen fields from Tracked Buff Bar configs (legacy bloat from removed frame-tree serialization).",
    body = function(ctx)
        -- Naturally idempotent: setting nil to nil is a no-op. The runner's
        -- per-spec-profile flag stops further runs after the first pass.
        --
        -- Previously ran every CDM OnInitialize against every spec profile.
        -- The runner promotes this to once-per-spec-profile-ever.
        --
        -- The bug-producing code (frame tree serialization into TBB
        -- configs) was removed -- this migration is pure legacy cleanup,
        -- nothing in the live codebase writes these fields anymore.
        local tbb = ctx.specProfile.trackedBuffBars
        local tbbBars = tbb and tbb.bars
        if type(tbbBars) ~= "table" then return end

        for _, barCfg in ipairs(tbbBars) do
            barCfg._linkedFrame = nil
            barCfg._linkedCdID = nil
            barCfg._linkedGen = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_removed_spells_to_ghost_cd_bar",
    scope       = "specProfile",
    description = "Move per-bar removedSpells (legacy filter mechanic) into the ghost CD bar's assignedSpells. The ghost bar replaced the per-bar removedSpells filter.",
    body = function(ctx)
        -- Naturally idempotent: removedSpells is wiped after migration,
        -- so a second run finds nothing. The runner's per-spec-profile
        -- flag also stops further runs after the first pass.
        --
        -- Previously ran in EnsureGhostBars which was called from
        -- BuildAllCDMBars on every CDM rebuild (login, spec change,
        -- profile swap, options change, layout reset, etc.). The runner
        -- promotes this to a single per-spec-profile pass.
        --
        -- Skips work entirely if no bar has any removedSpells, so cold
        -- specs without legacy data don't get an empty ghost bar entry
        -- pre-created on their behalf -- the runtime getter creates the
        -- ghost bar entry when something actually needs to write to it.
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end

        local GHOST_CD   = "__ghost_cd"
        local GHOST_BUFF = "__ghost_buffs"

        -- First pass: is there anything to migrate?
        local hasWork = false
        for barKey, bs in pairs(barSpells) do
            if barKey ~= GHOST_CD and barKey ~= GHOST_BUFF
               and type(bs) == "table"
               and bs.removedSpells and next(bs.removedSpells) then
                hasWork = true
                break
            end
        end
        if not hasWork then return end

        -- Ensure ghost CD bar entry exists in the spell store.
        local ghostBS = barSpells[GHOST_CD]
        if not ghostBS then
            ghostBS = {}
            barSpells[GHOST_CD] = ghostBS
        end
        if not ghostBS.assignedSpells then ghostBS.assignedSpells = {} end

        -- Build dedupe set from any spells already on the ghost bar.
        local existing = {}
        for _, sid in ipairs(ghostBS.assignedSpells) do existing[sid] = true end

        -- Second pass: migrate and wipe.
        for barKey, bs in pairs(barSpells) do
            if barKey ~= GHOST_CD and barKey ~= GHOST_BUFF
               and type(bs) == "table"
               and bs.removedSpells and next(bs.removedSpells) then
                for sid in pairs(bs.removedSpells) do
                    if not existing[sid] then
                        existing[sid] = true
                        ghostBS.assignedSpells[#ghostBS.assignedSpells + 1] = sid
                    end
                end
                wipe(bs.removedSpells)
            end
        end
    end,
})

-- Inline copy of every racial spell ID across every race. Mirrors
-- RACE_RACIALS in EllesmereUICooldownManager.lua. Used by the ghost CD
-- bar cleanup migration so we can identify racials without depending
-- on the CDM child addon (which loads after the migration runner fires)
-- or the per-character _myRacialsSet (which only contains the current
-- character's racials). If a new race ships, update both copies.
local CDM_ALL_RACIAL_SPELL_IDS = {
    [7744]    = true, [20549]   = true,
    [20572]   = true, [33697]   = true, [33702]   = true,
    [202719]  = true, [50613]   = true, [25046]   = true, [69179]   = true,
    [80483]   = true, [155145]  = true, [129597]  = true, [232633]  = true, [28730]   = true,
    [20594]   = true, [26297]   = true,
    [28880]   = true, [59543]   = true, [59545]   = true, [121093]  = true,
    [59544]   = true, [370626]  = true, [59547]   = true, [59548]   = true, [59542]   = true, [416250]  = true,
    [58984]   = true, [59752]   = true,
    [265221]  = true, [20589]   = true, [69041]   = true, [68992]   = true, [69070]   = true,
    [107079]  = true, [274738]  = true, [255647]  = true, [256948]  = true, [287712]  = true,
    [291944]  = true, [312411]  = true, [312924]  = true,
    [357214]  = true, [368970]  = true,
    [436344]  = true, [1287685] = true,
}

EllesmereUI.RegisterMigration({
    id          = "cdm_ghost_cd_bar_cleanup_v3",
    scope       = "specProfile",
    description = "Strip junk entries from the ghost CD bar: negative IDs (presets/trinkets), racials, customs (best-effort), and duplicates of spells already on a real bar.",
    body = function(ctx)
        -- Naturally idempotent: after the first run, the junk entries
        -- are gone, and the runner's per-spec-profile flag stops
        -- further runs anyway.
        --
        -- Previously ran in EnsureGhostBars on every CDM rebuild and
        -- gated by a manual prof._ghostBarCleaned3 flag. The runner
        -- promotes this to a single per-spec-profile pass with its
        -- own flag, so the manual one is gone.
        --
        -- Customs detection is best-effort: the bs.customSpellIDs
        -- stamping was added in v6.1, so customs added before that
        -- won't be detected. Customs that were tracked via the legacy
        -- bs.customSpells field are also undetectable now (C5 wiped
        -- those). Stale customs that slip through stay on the ghost
        -- bar (which is hidden, so the impact is purely cosmetic).
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end

        local GHOST_CD   = "__ghost_cd"
        local GHOST_BUFF = "__ghost_buffs"

        local ghostBS = barSpells[GHOST_CD]
        if not (ghostBS and ghostBS.assignedSpells) then return end

        -- Build sets of spells currently on real bars + currently stamped as custom.
        local realBarSpells = {}
        local customSet = {}
        for bk, bs in pairs(barSpells) do
            if bk ~= GHOST_CD and bk ~= GHOST_BUFF and type(bs) == "table" then
                if bs.assignedSpells then
                    for _, sid in ipairs(bs.assignedSpells) do
                        if sid and sid > 0 then realBarSpells[sid] = true end
                    end
                end
                if bs.customSpellIDs then
                    for sid in pairs(bs.customSpellIDs) do
                        customSet[sid] = true
                    end
                end
            end
        end

        for i = #ghostBS.assignedSpells, 1, -1 do
            local sid = ghostBS.assignedSpells[i]
            if sid and (
                sid <= 0
                or customSet[sid]
                or CDM_ALL_RACIAL_SPELL_IDS[sid]
                or realBarSpells[sid]
            ) then
                table.remove(ghostBS.assignedSpells, i)
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_ghost_strip_racials_v1",
    scope       = "specProfile",
    description = "Remove racial spells from ghost CD bar (racials should never be ghosted)",
    body = function(ctx)
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end
        local ghostBS = barSpells["__ghost_cd"]
        if not (ghostBS and ghostBS.assignedSpells) then return end
        for i = #ghostBS.assignedSpells, 1, -1 do
            local sid = ghostBS.assignedSpells[i]
            if sid and CDM_ALL_RACIAL_SPELL_IDS[sid] then
                table.remove(ghostBS.assignedSpells, i)
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_strip_legacy_spell_keys",
    scope       = "specProfile",
    description = "Strip legacy trackedSpells/customSpells keys from CDM bar data. The current shape is bs.assignedSpells; legacy keys are no longer written by any code path.",
    body = function(ctx)
        -- Naturally idempotent: setting nil to nil is a no-op. The runner's
        -- per-spec-profile flag stops further runs after the first pass.
        --
        -- Previously ran on every GetBarSpellData/GetBarSpellDataForSpec
        -- call as a lazy in-getter migration. That hot read path executed
        -- the nil-check on every spell read, route lookup, picker query,
        -- BuildAllCDMBars iteration, etc. The runner promotes this to a
        -- single per-spec-profile pass.
        --
        -- Cold profiles with legacy data lose those entries rather than
        -- being auto-ported into the new shape -- the schema has drifted
        -- enough that auto-porting would likely produce broken entries.
        -- The bar simply comes up with assignedSpells == nil, which the
        -- new-spec auto-population path correctly interprets as "never
        -- seen" and fills with defaults.
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end

        for _, bs in pairs(barSpells) do
            if type(bs) == "table" then
                bs.trackedSpells = nil
                bs.customSpells  = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_consolidate_buff_bars",
    scope       = "global",
    description = "Remove all extra (custom) buff bars across every parent profile, nil stale assignedSpells on the main buffs bar across every spec profile, and prune orphaned spell data for the deleted bars. Replaces the old _buffBarMigrationV2Done and _buffsBarCleanupV2 inline migrations.",
    body = function(ctx)
        -- Naturally idempotent: after the first run, no extra buff bars
        -- exist to remove and main-buffs assignedSpells is already nil.
        -- The runner's global flag also stops further runs.
        --
        -- The main "buffs" bar is Blizzard-owned and auto-populated from
        -- the CDM viewer -- it should never have manual assignedSpells.
        -- Extra/custom buff bars (custom_5_1234 etc.) were removed from
        -- the system entirely; their bar list entries and spell data
        -- both need to go.
        --
        -- This consolidates two previous inline migrations:
        --   _buffBarMigrationV2Done (v5.6.5) -- the full cleanup
        --   _buffsBarCleanupV2      (v6.0.4) -- defensive re-run of the
        --                                       main-buffs nil step
        -- Both have been live since late March / early April 2026 so
        -- most users have already had them run; for those users the
        -- new migration is a pure no-op.
        local removedBuffBarKeys = {}

        -- 1. Walk every parent profile, drop extra buff bars from the
        -- bar list, and remember their keys for the spell-data prune.
        if ctx.db.profiles then
            for _, profData in pairs(ctx.db.profiles) do
                local cdm = profData.addons and profData.addons.EllesmereUICooldownManager
                local cdmBars = cdm and cdm.cdmBars
                local bars = cdmBars and cdmBars.bars
                if type(bars) == "table" then
                    local kept = {}
                    for _, bd in ipairs(bars) do
                        if bd.barType == "buffs" and bd.key ~= "buffs" then
                            removedBuffBarKeys[bd.key] = true
                        else
                            kept[#kept + 1] = bd
                        end
                    end
                    cdmBars.bars = kept
                end
            end
        end

        -- 2. Walk every spec profile (all profiles' per-spec buckets), nil
        -- stale main-buffs assignedSpells and prune orphaned spell data for
        -- deleted extra bars.
        for _, specProf in ipairs(CollectSpecProfiles(ctx.db.spellAssignments)) do
            local barSpells = specProf.barSpells
            if type(barSpells) == "table" then
                if barSpells["buffs"] then
                    barSpells["buffs"].assignedSpells = nil
                end
                for removedKey in pairs(removedBuffBarKeys) do
                    barSpells[removedKey] = nil
                end
            end
        end

        -- 3. Wipe the old manual flag bytes -- the runner's own flag
        -- replaces them and the old ones are dead bloat in SV.
        ctx.db._buffBarMigrationV2Done = nil
        ctx.db._buffsBarCleanupV2      = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_wipe_legacy_glows_tbb_locations",
    scope       = "global",
    description = "Wipe legacy bar glows / TBB / tbbPositions storage locations. The data was moved to per-spec storage in v5.5.7. No live code writes to these locations anymore -- they are dead bytes that the previous inline migration was still trying to copy out.",
    body = function(ctx)
        -- Naturally idempotent: nil = nil. The runner's global flag
        -- also stops further runs.
        --
        -- Previously the inline CDMFinishSetup migration COPIED these
        -- locations into the active spec profile, then left the
        -- legacy data in place. After ~2 weeks of v5.5.7+ shipping,
        -- any still-unmigrated data in these locations belongs to
        -- cold profiles/specs the user hasn't logged into. Active
        -- users have already had their data ported to per-spec
        -- storage and don't need this migration to do anything.
        --
        -- Discriminator is location, not content: anything at the
        -- top-level spellAssignments.barGlows or under the parent
        -- profile's CDM addon block is by definition legacy because
        -- no current code writes there. Live code writes to
        -- spellAssignments.specProfiles[specKey].X exclusively.

        -- 1. Wipe global barGlows on the spellAssignments root.
        local sa = ctx.db.spellAssignments
        if sa then
            sa.barGlows = nil
        end

        -- 2. Wipe per-parent-profile CDM trackedBuffBars / tbbPositions.
        if ctx.db.profiles then
            for _, profData in pairs(ctx.db.profiles) do
                local cdm = profData.addons and profData.addons.EllesmereUICooldownManager
                if cdm then
                    cdm.trackedBuffBars = nil
                    cdm.tbbPositions    = nil
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_strip_position_based_glow_keys",
    scope       = "specProfile",
    description = "Strip old position-based CDM bar glow assignment keys (101_*, 102_*) from barGlows.assignments. These were tied to bar index + button index and broke when CDM icons reordered during reanchor. The new format keys are cdm_<cooldownID>.",
    body = function(ctx)
        -- Naturally idempotent: after the first run no 10[12]_ keys
        -- remain. The runner's per-spec-profile flag also stops further
        -- runs. Action bar keys (1_* through 8_*) and the new cdm_<id>
        -- format keys are left alone.
        --
        -- Previously ran in MigrateCDMAssignments, called from
        -- ns.InitBarGlows, called once from CDMFinishSetup on every
        -- login/reload. The runner promotes this to a single
        -- per-spec-profile pass.
        local bg = ctx.specProfile.barGlows
        local assignments = bg and bg.assignments
        if type(assignments) ~= "table" then return end

        for key in pairs(assignments) do
            if type(key) == "string" and key:match("^10[12]_") then
                assignments[key] = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_remove_discontinued_presets",
    scope       = "specProfile",
    description = "Remove preset versions of discontinued spells (Bloodlust + variants, Time Spiral, warlock pets) from CDM bars and TBB bars. These presets were removed from the picker because they can't be tracked via cooldown detection.",
    body = function(ctx)
        -- Naturally idempotent: after the first run the IDs and TBB bars
        -- are gone, and re-running finds nothing. The runner's per-spec-
        -- profile flag also stops further runs.
        --
        -- Previously ran in CDMFinishSetup on every login/reload, walking
        -- every spec profile every time. The runner promotes this to a
        -- single per-spec-profile pass.
        --
        -- The customSpellDurations guard is the safety mechanism: a real
        -- class spell with the same ID (e.g. a Shaman's Heroism (32182))
        -- has no customSpellDurations stamp because it was added via the
        -- regular picker, not the preset adder. Only spells added as a
        -- preset variant get the duration stamp, so the guard prevents
        -- collateral damage to real class spells.
        --
        -- The presetVariants wipe is a separate stale-field cleanup --
        -- nothing in the live codebase reads or writes presetVariants
        -- anymore, but old data may still have it on bars.
        local removedPresets = { [2825] = true, [32182] = true, [80353] = true,
            [264667] = true, [390386] = true, [381301] = true, [444062] = true, [444257] = true, -- Bloodlust variants
            [104316] = true, [265187] = true, [264119] = true, [111898] = true, -- Warlock pets
        }
        local removedPopularKeys = { bloodlust = true, time_spiral = true,
            call_dreadstalkers = true, demonic_tyrant = true,
            summon_vilefiend = true, grimoire_felguard = true }

        -- Clean preset versions of these spells from ALL bars + wipe stale presetVariants.
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) == "table" then
            for _, bs in pairs(barSpells) do
                if type(bs) == "table" then
                    if bs.assignedSpells and bs.customSpellDurations then
                        for i = #bs.assignedSpells, 1, -1 do
                            local sid = bs.assignedSpells[i]
                            if removedPresets[sid] and bs.customSpellDurations[sid] then
                                table.remove(bs.assignedSpells, i)
                                bs.customSpellDurations[sid] = nil
                            end
                        end
                    end
                    bs.presetVariants = nil
                end
            end
        end

        -- Clean removed presets from TBB. Other popular presets (potions etc.) are kept.
        local tbb = ctx.specProfile.trackedBuffBars
        if tbb and type(tbb.bars) == "table" then
            for i = #tbb.bars, 1, -1 do
                local bar = tbb.bars[i]
                if bar.popularKey and removedPopularKeys[bar.popularKey] then
                    table.remove(tbb.bars, i)
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_strip_buff_bar_item_ids_v1",
    scope       = "specProfile",
    description = "Remove item-ID (negative -itemID) entries from CDM buff bars. Buff bars track auras only (positive spell IDs); items can no longer be placed on them. CD/utility bars (which legitimately hold trinkets/potions) are left untouched.",
    body = function(ctx)
        -- Idempotent: only NEGATIVE ids are removed, so a re-run finds none. The
        -- per-spec-profile flag also stops further runs.
        local sp = ctx.specProfile
        local barSpells = sp and sp.barSpells
        if type(barSpells) ~= "table" then return end

        -- Resolve which bar keys are BUFF bars from this profile's bar config
        -- (barType). The default buff bar is always "buffs" even if the config is
        -- absent, so seed it unconditionally. Only buff bars are stripped --
        -- cooldown/utility bars keep their legitimate trinket/potion markers.
        local buffKeys = { buffs = true }
        local prof = EllesmereUIDB.profiles and EllesmereUIDB.profiles[ctx.profileName]
        local cdm = prof and prof.addons and prof.addons.EllesmereUICooldownManager
        local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
        if type(bars) == "table" then
            for _, b in ipairs(bars) do
                if type(b) == "table" and b.barType == "buffs" and type(b.key) == "string" then
                    buffKeys[b.key] = true
                end
            end
        end

        for barKey, bs in pairs(barSpells) do
            if buffKeys[barKey] and type(bs) == "table" and type(bs.assignedSpells) == "table" then
                local as = bs.assignedSpells
                for i = #as, 1, -1 do
                    local id = as[i]
                    -- Negative ids are item markers (-itemID / trinket slots);
                    -- positive ids are real buff spell IDs and are kept verbatim.
                    if type(id) == "number" and id < 0 then
                        table.remove(as, i)
                        -- Drop any per-id side data so nothing dangles.
                        if type(bs.spellSettings) == "table" then bs.spellSettings[id] = nil end
                        if type(bs.spellDurations) == "table" then bs.spellDurations[id] = nil end
                        if type(bs.customSpellDurations) == "table" then bs.customSpellDurations[id] = nil end
                    end
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_unanchor_buff_bars",
    scope       = "global",
    description = "Clear unlock anchors that target CDM buff/custom_buff bars or the AuraBuff Reminders frame. Dynamic bars (resize with auras) cause cascading position shifts when used as anchor targets.",
    body = function(ctx)
        -- Self-gating implicitly: once anchors targeting buff bars are
        -- cleared, the predicate `buffKeys[info.target]` is false on
        -- the next pass and the body is a no-op.
        --
        -- Previously ran every CDMFinishSetup and read only the active
        -- profile's bar list to build the buff key set. The runner
        -- promotes this to once-per-install and the body now unions
        -- across ALL profiles so buff bars defined in inactive profiles
        -- are also recognized.
        local anchors = ctx.db.unlockAnchors
        if not anchors then return end

        -- Collect every buff/custom_buff bar key across every profile.
        local buffKeys = {}
        if ctx.db.profiles then
            for _, profData in pairs(ctx.db.profiles) do
                local cdm = profData.addons and profData.addons.EllesmereUICooldownManager
                local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
                if type(bars) == "table" then
                    for _, bd in ipairs(bars) do
                        if bd.barType == "buffs" or bd.key == "buffs" or bd.barType == "custom_buff" then
                            buffKeys["CDM_" .. bd.key] = true
                        end
                    end
                end
            end
        end
        -- AuraBuff Reminders is also dynamic regardless of profile.
        buffKeys["EABR_Reminders"] = true

        for childKey, info in pairs(anchors) do
            if info.target and buffKeys[info.target] then
                anchors[childKey] = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_active_state_per_bar_to_per_icon",
    scope       = "profile",
    description = "Promote per-bar activeStateAnim='hideActive' to per-icon activeSwipeMode='none' across every spec profile, then reset the bar-level value to 'blizzard'.",
    body = function(ctx)
        -- Mixed scope: outer walk is per-profile (cdmBars.bars), inner
        -- walk is per-spec-profile (barSpells/spellSettings). Body does
        -- its own spec-profile iteration; the runner's per-profile flag
        -- gates the outer pass.
        --
        -- Self-gating via the bar value reset: after migrating, the body
        -- writes bd.activeStateAnim = "blizzard", so the next pass sees
        -- nothing to migrate.
        --
        -- Depends on cdm_active_state_anim_none_to_hideactive having run
        -- first (which renames legacy 'none' values into 'hideActive'
        -- so this body has something to migrate).
        --
        -- Previously ran every BuildAllCDMBars call against the active
        -- profile's bar list only. The runner promotes this to
        -- once-per-profile-ever and the new "walk all profiles" behavior
        -- catches custom bars that exist in inactive profiles too.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        -- The spell store is per-profile (spellAssignments.profiles[name].
        -- specProfiles). We collect every profile's per-spec buckets directly
        -- (not via ns.GetSpecProfiles) since CDM hasn't initialized by the time
        -- this runs (early phase, before child OnInitialize). Seeding has
        -- already run, so the buckets exist.
        local specProfs = CollectSpecProfiles(EllesmereUIDB and EllesmereUIDB.spellAssignments)

        for _, bd in ipairs(bars) do
            if bd.activeStateAnim == "hideActive" and not bd.isGhostBar then
                for _, prof in ipairs(specProfs) do
                    local barSpells = prof and prof.barSpells
                    local bs = barSpells and barSpells[bd.key]
                    if bs and bs.assignedSpells then
                        if not bs.spellSettings then bs.spellSettings = {} end
                        for _, sid in ipairs(bs.assignedSpells) do
                            if sid and sid > 0 then
                                if not bs.spellSettings[sid] then bs.spellSettings[sid] = {} end
                                local ss = bs.spellSettings[sid]
                                -- Only migrate if the user hasn't already
                                -- explicitly set a per-icon active state.
                                if not ss.activeSwipeMode and not ss.activeSwipeR then
                                    ss.activeSwipeMode = "none"
                                end
                            end
                        end
                    end
                end
                -- Clear old per-bar setting so the body's predicate
                -- becomes false on any future re-run.
                bd.activeStateAnim = "blizzard"
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_buff_assignedspells_reseed_v1",
    scope       = "specProfile",
    description = "Clear buffs.assignedSpells so the unified model re-seeds from live icons (buff/CD unification).",
    body = function(ctx)
        -- The buff bar previously never wrote to assignedSpells. With the
        -- unified model, EnsureAssignedSpells lazily seeds from live icons.
        -- Any stale data from the first options-panel open (before the route
        -- map fix for TBB diversions) must be cleared so it re-seeds cleanly.
        local bs = ctx.specProfile.barSpells
        if not bs then return end
        local buffData = bs["buffs"]
        if buffData and buffData.assignedSpells then
            buffData.assignedSpells = nil
        end
    end,
})

--------------------------------------------------------------------------------
--  v6.6 addon split: copy per-module saved data out of EllesmereUIBasics
--  into the new per-addon folders. Lite stores everything under
--  EllesmereUIDB.profiles[p].addons[folder], so this is a straight copy
--  from addons.EllesmereUIBasics.<key> to addons.EllesmereUI<Name>.<key>.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "v66_basics_split_data",
    scope       = "profile",
    description = "Move Basics per-module data into new per-addon folders (Minimap/Friends/Chat/QuestTracker/QoL cursor).",
    body = function(ctx)
        local addons = ctx.profile.addons
        if type(addons) ~= "table" then return end
        local basics = addons.EllesmereUIBasics
        if type(basics) ~= "table" then return end

        local function ensureFolder(name)
            if type(addons[name]) ~= "table" then addons[name] = {} end
            return addons[name]
        end

        -- minimap -> EllesmereUIMinimap.minimap
        if type(basics.minimap) == "table" then
            local dst = ensureFolder("EllesmereUIMinimap")
            if dst.minimap == nil then
                dst.minimap = basics.minimap
            end
        end

        -- friends -> EllesmereUIFriends.friends
        if type(basics.friends) == "table" then
            local dst = ensureFolder("EllesmereUIFriends")
            if dst.friends == nil then
                dst.friends = basics.friends
            end
        end

        -- chat -> EllesmereUIChat.chat (kept for future rebuild even though UI is coming-soon)
        if type(basics.chat) == "table" then
            local dst = ensureFolder("EllesmereUIChat")
            if dst.chat == nil then
                dst.chat = basics.chat
            end
        end

        -- questTracker -> EllesmereUIQuestTracker.questTracker
        if type(basics.questTracker) == "table" then
            local dst = ensureFolder("EllesmereUIQuestTracker")
            if dst.questTracker == nil then
                dst.questTracker = basics.questTracker
            end
        end

        -- cursor -> EllesmereUIQoL.cursor
        if type(basics.cursor) == "table" then
            local dst = ensureFolder("EllesmereUIQoL")
            if dst.cursor == nil then
                dst.cursor = basics.cursor
            end
        end
    end,
})

--------------------------------------------------------------------------------
--  v6.6 addon split: if the user had EllesmereUIBasics disabled for this
--  character, disable the new Minimap/Friends/QuestTracker addons to match
--  (since those now host what Basics used to host). Prompt a reload so the
--  change takes effect.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "v66_basics_split_disabled_state",
    scope       = "global",
    description = "Carry EllesmereUIBasics disabled state onto Minimap/Friends/QuestTracker addons.",
    body = function(ctx)
        if not C_AddOns or not C_AddOns.GetAddOnEnableState then return end
        local char = UnitName("player")
        if not char then return end

        -- GetAddOnEnableState: 0 = disabled, 1 = enabled-for-char, 2 = enabled-for-all
        local basicsState = C_AddOns.GetAddOnEnableState("EllesmereUIBasics", char)
        if basicsState == nil or basicsState ~= 0 then return end

        -- Basics is disabled for this character. Mirror that onto the new addons.
        local targets = { "EllesmereUIMinimap", "EllesmereUIFriends", "EllesmereUIQuestTracker" }
        local disabled = {}
        for _, name in ipairs(targets) do
            local state = C_AddOns.GetAddOnEnableState(name)
            if state ~= 0 then
                if C_AddOns.DisableAddOn then
                    C_AddOns.DisableAddOn(name)
                    disabled[#disabled + 1] = name
                end
            end
        end

        if #disabled > 0 then
            -- Defer the popup: UI systems aren't ready at this phase.
            C_Timer.After(3, function()
                if EllesmereUI and EllesmereUI.ShowConfirmPopup then
                    EllesmereUI:ShowConfirmPopup({
                        title       = "EllesmereUI Addon Split",
                        message     = "EllesmereUI Basics has been split into separate addons. Since you had Basics disabled, Minimap, Friends, and Quest Tracker have been disabled to match. A reload is required to apply this change.",
                        confirmText = "Reload Now",
                        cancelText  = "Later",
                        onConfirm   = function() ReloadUI() end,
                    })
                end
            end)
        end
    end,
})

--------------------------------------------------------------------------------
--  v67 Bar Texture -> global setting
--
--  The Bar Texture dropdown now writes to db.profile.healthBarTexture instead
--  of per-unit keys. Find the first non-"none" texture among player/target/
--  focus (in that order) and promote it to the global key, then strip the
--  per-unit overrides so nothing silently shadows the global.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "v67_bar_texture_global",
    scope       = "profile",
    description = "Promote per-unit healthBarTexture to a single global profile key.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end

        -- Pick the first non-"none" override in the canonical order.
        local winner
        for _, unit in ipairs({ "player", "target", "focus" }) do
            local s = uf[unit]
            local v = type(s) == "table" and s.healthBarTexture
            if type(v) == "string" and v ~= "" and v ~= "none" then
                winner = v; break
            end
        end

        if winner and (uf.healthBarTexture == nil or uf.healthBarTexture == "none") then
            uf.healthBarTexture = winner
        end

        -- Strip per-unit overrides so the global value is the single source.
        for _, unit in ipairs({ "player", "target", "focus", "pet", "totPet", "boss" }) do
            local s = uf[unit]
            if type(s) == "table" then s.healthBarTexture = nil end
        end
    end,
})

--------------------------------------------------------------------------------
--  v6.7.1 Quest Tracker: reset stale enabled=false inherited from Basics.
--
--  The v66_basics_split_data migration copied the entire old
--  EllesmereUIBasics.questTracker table into the new QT addon's profile.
--  The old "enabled" flag meant "disable the custom overlay" (Blizzard's
--  tracker still showed). The new QT uses "enabled" in EvalVisibility to
--  mean "completely hide the tracker." Users who had the old custom tracker
--  disabled inherited enabled=false, which hid the tracker with no way to
--  re-enable it (the option isn't exposed in the new QT settings).
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "qt_minimap_ensure_enabled_v2",
    scope       = "profile",
    description = "Ensure quest tracker / minimap have enabled=true and visibility=always when missing or false.",
    body = function(ctx)
        local addons = ctx.profile.addons
        if type(addons) ~= "table" then return end
        local qt = addons.EllesmereUIQuestTracker
            and addons.EllesmereUIQuestTracker.questTracker
        if type(qt) == "table" then
            if not qt.enabled then qt.enabled = true end
            if not qt.visibility then qt.visibility = "always" end
        end
        local mm = addons.EllesmereUIMinimap
            and addons.EllesmereUIMinimap.minimap
        if type(mm) == "table" then
            if not mm.enabled then mm.enabled = true end
            if not mm.visibility then mm.visibility = "always" end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "mt_bestruns_wipe_v1",
    scope       = "global",
    description = "Wipe obsolete Mythic+ bestRuns data (feature removed). Clears EllesmereUIDB.global.bestRuns and every profile's addons.EllesmereUIMythicTimer.bestRuns.",
    body = function(ctx)
        if ctx.db.global then ctx.db.global.bestRuns = nil end

        local profiles = ctx.db.profiles
        if type(profiles) == "table" then
            for _, profData in pairs(profiles) do
                local mt = profData and profData.addons and profData.addons.EllesmereUIMythicTimer
                if type(mt) == "table" then mt.bestRuns = nil end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "power_color_defaults_v5",
    scope       = "global",
    description = "Migrate users on old power color defaults (Mana/Rage/Focus/Energy) to new defaults",
    body = function(ctx)
        local cc = ctx.db.customColors
        if not cc or not cc.power then return end
        -- Old defaults that shipped before this migration
        local function near(a, b) return math.abs(a - b) < 0.01 end
        local function matchesOld(cur, old)
            return cur and near(cur.r, old.r) and near(cur.g, old.g) and near(cur.b, old.b)
        end
        local OLD = {
            MANA   = { { r = 0x33/255, g = 0x59/255, b = 0xD9/255 } },
            RAGE   = { { r = 1.000, g = 0.000, b = 0.000 } },
            FOCUS  = { { r = 1.000, g = 0.500, b = 0.250 }, { r = 0.770, g = 0.530, b = 0.240 } },
            ENERGY = { { r = 1.000, g = 1.000, b = 0.000 } },
            RUNIC_POWER = { { r = 0.000, g = 0.820, b = 1.000 } },
            LUNAR_POWER = { { r = 0.300, g = 0.520, b = 0.900 } },
            MAELSTROM   = { { r = 0.000, g = 0.500, b = 1.000 } },
        }
        for key, oldList in pairs(OLD) do
            local cur = cc.power[key]
            for _, old in ipairs(oldList) do
                if matchesOld(cur, old) then
                    cc.power[key] = nil
                    break
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "power_color_fury_to_classcolor_v1",
    scope       = "global",
    description = "Migrate Fury (DH) power color from old purple default to DH class color (A330C9).",
    body = function(ctx)
        local cc = ctx.db.customColors
        if not cc or not cc.power then return end
        local cur = cc.power.FURY
        if not cur then return end
        local function near(a, b) return math.abs(a - b) < 0.01 end
        if near(cur.r, 0.788) and near(cur.g, 0.259) and near(cur.b, 0.992) then
            cc.power.FURY = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "chat_mouseover_to_always_v1",
    scope       = "global",
    description = "Migrate chat visibility from 'mouseover' to 'always' (mouseover removed, idle fade replaces it).",
    body = function(ctx)
        local chatDB = _G.EllesmereUIChatDB
        if not chatDB or not chatDB.profiles then return end
        for _, profile in pairs(chatDB.profiles) do
            if profile.chat and profile.chat.visibility == "mouseover" then
                profile.chat.visibility = "always"
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "np_border_ellesmere_to_simple_v3",
    scope       = "profile",
    description = "No-op (superseded by np_border_v5).",
    body = function() end,
})

EllesmereUI.RegisterMigration({
    id          = "np_border_v5",
    scope       = "profile",
    description = "Migrate borderStyle/simpleBorderSize to showBorder/borderSize. 'none' -> showBorder=false, everything else -> showBorder=true, borderSize=1.",
    body = function(ctx)
        local np = ctx.profile.addons and ctx.profile.addons.EllesmereUINameplates
        if not np then return end
        -- Migrate from old keys to new keys
        local oldStyle = np.borderStyle
        if oldStyle == "none" then
            np.showBorder = false
        else
            np.showBorder = true
        end
        np.borderSize = 1
        -- Clean up old keys
        np.borderStyle = nil
        np.simpleBorderSize = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "uf_absorb_style_dropdown_v1",
    scope       = "profile",
    description = "Migrate showPlayerAbsorb from boolean toggle to style string dropdown. true -> 'striped', false/nil -> 'none'.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if not uf then return end
        for _, unitKey in ipairs({ "player", "target", "playerTarget", "focus" }) do
            local unitCfg = uf[unitKey]
            if unitCfg then
                local v = unitCfg.showPlayerAbsorb
                if v == true then
                    unitCfg.showPlayerAbsorb = "striped"
                elseif v == false or v == nil then
                    unitCfg.showPlayerAbsorb = "none"
                end
            end
        end
    end,
})

-- Remove ghost buff bar: buff visibility is now managed by Blizzard CDM
-- settings. Clean up the bar entry from all profiles and spell data from
-- all spec profiles. One-time migration.
EllesmereUI.RegisterMigration({
    id          = "cdm_remove_ghost_buff_bar_v1",
    scope       = "profile",
    description = "Remove __ghost_buffs bar entry from cdmBars.bars array (original, wrong path).",
    body = function() end,
})
EllesmereUI.RegisterMigration({
    id          = "cdm_remove_ghost_buff_bar_v2",
    scope       = "profile",
    description = "Remove __ghost_buffs bar entry from cdmBars.bars array (correct path).",
    body = function(ctx)
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
        if not bars then return end
        for i = #bars, 1, -1 do
            if bars[i].key == "__ghost_buffs" then
                table.remove(bars, i)
            end
        end
    end,
})
EllesmereUI.RegisterMigration({
    id          = "cdm_remove_ghost_buff_spelldata_v1",
    scope       = "global",
    description = "Remove __ghost_buffs spell data from all spec profiles.",
    body = function(ctx)
        for _, specData in ipairs(CollectSpecProfiles(ctx.db and ctx.db.spellAssignments)) do
            if specData.barSpells then
                specData.barSpells["__ghost_buffs"] = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "rf_split_absorb_edge_mode_v1",
    scope       = "profile",
    description = "Split the shared Raid Frames absorbFromRightEdge toggle into independent absorbEdgeMode / healAbsorbEdgeMode (overlay/right/left) per bar.",
    body        = function(ctx)
        local rf = ctx.profile.addons and ctx.profile.addons.EllesmereUIRaidFrames
        if type(rf) ~= "table" then return end
        -- Existing users who had the old single toggle ON get BOTH bars set to
        -- "right" so their look is unchanged; false/absent -> "overlay" (default).
        -- Idempotent: only writes the new keys when they are still unset.
        local function split(oldKey, absKey, healKey)
            local old = rf[oldKey]
            if old == nil then return end
            local mode = (old == true) and "right" or "overlay"
            if rf[absKey]  == nil then rf[absKey]  = mode end
            if rf[healKey] == nil then rf[healKey] = mode end
        end
        split("absorbFromRightEdge",       "absorbEdgeMode",       "healAbsorbEdgeMode")
        split("party_absorbFromRightEdge", "party_absorbEdgeMode", "party_healAbsorbEdgeMode")
    end,
})

EllesmereUI.RegisterMigration({
    id          = "uf_castbar_standalone_v1",
    scope       = "profile",
    description = "Resolve castbar width=0 to real frame width and set default unlock anchors for standalone cast bars.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if not uf then return end
        local positions = uf.positions or uf.unlockPositions
        local anchors = EllesmereUIDB and EllesmereUIDB.unlockAnchors

        -- Resolve player castbar auto-width
        local playerS = uf.player
        if playerS then
            local pw = playerS.playerCastbarWidth or 0
            if pw == 0 then
                playerS.playerCastbarWidth = playerS.frameWidth or 181
            end
            local ph = playerS.playerCastbarHeight or 0
            if ph == 0 then
                playerS.playerCastbarHeight = playerS.castbarHeight or 14
            end
        end

        -- Resolve target/focus castbar auto-width
        for _, unitKey in ipairs({ "target", "focus" }) do
            local s = uf[unitKey]
            if s then
                local cw = s.castbarWidth or 0
                if cw == 0 then
                    s.castbarWidth = s.frameWidth or 181
                end
            end
        end

        -- Set default unlock anchors for cast bars that have no position and no anchor
        if anchors then
            local CASTBAR_DEFAULTS = {
                { key = "playerCastbar", target = "player" },
                { key = "targetCastbar", target = "target" },
                { key = "focusCastbar",  target = "focus" },
            }
            for _, def in ipairs(CASTBAR_DEFAULTS) do
                local hasPos = positions and positions[def.key]
                local hasAnchor = anchors[def.key]
                if not hasPos and not hasAnchor then
                    anchors[def.key] = {
                        target = def.target,
                        side = "BOTTOM",
                        offsetX = 0,
                        offsetY = 0,
                    }
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "mythic_timer_default_pos_to_otf_v2",
    scope       = "profile",
    description = "Wipe M+ Timer position if it matches the old hardcoded default (0,0) so the new OTF-based default kicks in.",
    body = function(ctx)
        local emt = ctx.profile.addons and ctx.profile.addons.EllesmereUIMythicTimer
        if not emt then return end
        local pos = emt.standalonePos
        if not pos then return end
        if pos.centerX and pos.centerY
           and math.abs(pos.centerX) < 3 and math.abs(pos.centerY) < 3 then
            emt.standalonePos = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "np_stacking_spacing_50_to_75_v2",
    scope       = "profile",
    description = "Bump nameplate stacking spacing from old default 50 to 75 for better separation.",
    body = function(ctx)
        local np = ctx.profile.addons and ctx.profile.addons.EllesmereUINameplates
        if not np then np = {}; ctx.profile.addons = ctx.profile.addons or {}; ctx.profile.addons.EllesmereUINameplates = np end
        local cur = np.stackSpacingScale
        if not cur or cur == 50 then
            np.stackSpacingScale = 90
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "break_blizz_owned_anchors_v1",
    scope       = "global",
    description = "Remove anchor relationships involving MicroBar, BagBar, and QueueStatus (Blizzard-owned frames that cannot participate in anchor chains).",
    body = function(ctx)
        local anchors = ctx.db.unlockAnchors
        if not anchors then return end
        local BLIZZ_OWNED = { MicroBar = true, BagBar = true, QueueStatus = true }
        for childKey, info in pairs(anchors) do
            if BLIZZ_OWNED[childKey] or (info.target and BLIZZ_OWNED[info.target]) then
                anchors[childKey] = nil
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "ab_queuestatus_reset_visibility_v1",
    scope       = "profile",
    description = "Reset stale QueueStatus (LFG eye) visibility/mouseover settings to neutral. EUI used to control the eye's visibility but now only controls its position; old saved values (e.g. barVisibility 'mouseover' with mouseoverAlpha 0) could leave the eye permanently invisible with no UI left to restore it.",
    body = function(ctx)
        local ab = ctx.profile.addons and ctx.profile.addons.EllesmereUIActionBars
        local qs = ab and ab.bars and ab.bars.QueueStatus
        if type(qs) ~= "table" then return end
        -- Neutral defaults (matches the EXTRA_BARS defaults): always-visible, no
        -- mouseover fade, no combat/housing/instance hiding.
        qs.barVisibility      = "always"
        qs.alwaysHidden       = false
        qs.mouseoverEnabled   = false
        qs.mouseoverAlpha     = 1
        qs._savedBarAlpha     = nil
        qs.combatHideEnabled  = false
        qs.combatShowEnabled  = false
        qs.housingHideEnabled = false
        qs.visHideHousing     = false
        qs.visOnlyInstances   = false
    end,
})

EllesmereUI.RegisterMigration({
    id          = "uf_per_unit_portrait_style_v1",
    scope       = "profile",
    description = "Copy global portraitStyle into player/target/focus per-unit tables.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if not uf then return end
        local global = uf.portraitStyle or "attached"
        for _, unitKey in ipairs({ "player", "target", "focus" }) do
            local s = uf[unitKey]
            if s and s.portraitStyle == nil then
                s.portraitStyle = global
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "uf_split_totpet_into_tot_focus_v1",
    scope       = "profile",
    description = "Split shared totPet unit-frame settings into independent targettarget and focustarget tables.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end
        local tp = uf.totPet
        if type(tp) ~= "table" then return end
        -- Self-contained deep copy (do not depend on an external helper).
        local function DCopy(t)
            if type(t) ~= "table" then return t end
            local c = {}
            for k, v in pairs(t) do c[k] = DCopy(v) end
            return c
        end
        -- Copy the user's old shared overrides into BOTH new tables so each
        -- mini renders identically to before. Overwrite unconditionally:
        -- totPet only exists on un-migrated pre-split data, so any
        -- targettarget/focustarget already present here are default-merge
        -- artifacts (e.g. from an import's DeepMergeDefaults), never
        -- user-authored. Deleting totPet afterward makes this a no-op on
        -- re-run regardless of the per-profile migration flag.
        uf.targettarget = DCopy(tp)
        uf.focustarget  = DCopy(tp)
        uf.totPet = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "uf_boss_simple_text_seed_v1",
    scope       = "profile",
    description = "Seed boss simple-display cooldown-text show/size from customized regular keys so old profiles keep their text settings under the default-on Simple Display.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        local b = type(uf) == "table" and uf.boss
        if type(b) ~= "table" then return end
        -- Simple Debuff Display defaults ON ("left"), and while it is on the
        -- renderer reads the simple* text keys -- which DeepMergeDefaults
        -- fills with false/14 on a profile predating them. A customized
        -- regular debuff/buff text size stays stored but is never read, so
        -- the user sees hidden text (or 14) instead of their size. Seed the
        -- simple keys from the regular ones BEFORE the merge masks them.
        -- The regular defaults (10 / false) act as the "was it customized"
        -- sentinels; StripDefaults nils default-equal values at logout, so a
        -- stored value is always a genuine customization.
        if b.simpleDebuffCooldownTextSize == nil
            and type(b.debuffCooldownTextSize) == "number" and b.debuffCooldownTextSize ~= 10 then
            b.simpleDebuffCooldownTextSize = b.debuffCooldownTextSize
        end
        if b.simpleDebuffShowCooldownText == nil and b.debuffShowCooldownText == true then
            b.simpleDebuffShowCooldownText = true
        end
        if b.simpleBuffCooldownTextSize == nil
            and type(b.buffCooldownTextSize) == "number" and b.buffCooldownTextSize ~= 10 then
            b.simpleBuffCooldownTextSize = b.buffCooldownTextSize
        end
        if b.simpleBuffShowCooldownText == nil and b.buffShowCooldownText == true then
            b.simpleBuffShowCooldownText = true
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "charsheet_default_enabled_v1",
    scope       = "global",
    description = "Preserve disabled default for existing users when flipping themedCharacterSheet to default-on.",
    body = function(ctx)
        -- Existing users who never touched the toggle have nil (old default =
        -- disabled). Stamp false so the new nil-means-enabled logic doesn't
        -- flip them on. Users who already set true/false keep their value.
        if ctx.db.themedCharacterSheet == nil then
            ctx.db.themedCharacterSheet = false
        end
    end,
})

-------------------------------------------------------------------------------
--  Growth direction independent of anchoring (v7.7.1)
--
--  Previously, anchoring an element cleared its growDirection and the grow
--  button was disabled while anchored. Now growth is independent: the user
--  can set any orientation-appropriate direction while anchored. This
--  migration stamps an explicit growDirection on every anchored CDM/AB bar
--  so the new code (which no longer clears growth on anchor) preserves the
--  exact same visual layout existing users had.
--
--  Mapping: anchor side -> growth direction (orientation-aware)
--    Horizontal: LEFT->LEFT, RIGHT->RIGHT, TOP->CENTER, BOTTOM->CENTER
--    Vertical:   TOP->UP, BOTTOM->DOWN, LEFT->CENTER, RIGHT->CENTER
-------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "unlock_grow_independent_v1",
    scope       = "profile",
    description = "Set explicit growDirection on anchored CDM/AB bars to match their anchor side.",
    body = function(ctx)
        local anchors = EllesmereUIDB and EllesmereUIDB.unlockAnchors
        if not anchors then return end

        local HORIZ_MAP = { LEFT = "LEFT", RIGHT = "RIGHT", TOP = "CENTER", BOTTOM = "CENTER" }
        local VERT_MAP  = { TOP = "UP", BOTTOM = "DOWN", LEFT = "CENTER", RIGHT = "CENTER" }

        -- CDM bars: always set CENTER. CDM bars previously always had nil
        -- growDirection when anchored (the old code cleared it). nil = CENTER
        -- for CDM. Setting CENTER explicitly preserves the exact same behavior
        -- and avoids triggering edge preservation for bars with no growEdge data.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars and cdm.cdmBars.bars
        if cdmBars then
            for _, bar in ipairs(cdmBars) do
                local anchorKey = "CDM_" .. bar.key
                local ai = anchors[anchorKey]
                if ai and ai.side and not bar.growDirection then
                    bar.growDirection = "CENTER"
                end
            end
        end
        -- Note: growEdge promotion to direct edge positions is handled by
        -- the cdm_clear_stale_growedge_v1 migration (runs after this one).

        -- Action bars
        local ab = ctx.profile.addons and ctx.profile.addons.EllesmereUIActionBars
        local abBars = ab and ab.bars
        if abBars then
            local AB_KEYS = {
                MainBar = true, Bar2 = true, Bar3 = true, Bar4 = true,
                Bar5 = true, Bar6 = true, Bar7 = true, Bar8 = true,
            }
            for barKey, cfg in pairs(abBars) do
                if AB_KEYS[barKey] then
                    local ai = anchors[barKey]
                    if ai and ai.side then
                        local cur = cfg.growDirection
                        -- Only migrate bars at default ("up" or nil)
                        if not cur or cur == "up" then
                            local isVert = (cfg.orientation == "vertical")
                            local map = isVert and VERT_MAP or HORIZ_MAP
                            cfg.growDirection = (map[ai.side] or "CENTER"):lower()
                        end
                    end
                end
            end
        end
    end,
})

-------------------------------------------------------------------------------
-- Convert CDM bar positions from CENTER+growEdge format to direct edge format.
-- Positions are now stored using the growth-edge anchor directly (LEFT for
-- RIGHT-grow, etc.) so SetSize naturally preserves the fixed edge without any
-- post-resize re-anchoring. If growEdge exists, promote its values to the
-- primary position fields. If not, leave as-is (CENTER-grow bars or bars that
-- were never positioned in unlock mode with a non-CENTER direction).
-------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "cdm_clear_stale_growedge_v1",
    scope       = "profile",
    description = "Convert CDM bar positions to direct edge-anchor format.",
    body = function(ctx)
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmPositions = cdm and cdm.cdmBarPositions
        if not cdmPositions then return end
        for _, pos in pairs(cdmPositions) do
            local ge = pos.growEdge
            if ge and ge.anchor and ge.x and ge.y then
                -- Promote growEdge to primary position
                pos.point = ge.anchor
                pos.x = ge.x
                pos.y = ge.y
                pos.growEdge = nil
            elseif ge then
                -- Incomplete growEdge, just remove it
                pos.growEdge = nil
            end
        end
    end,
})

-------------------------------------------------------------------------------
-- Migrate per-profile secondary threshold settings into the new thresholdSpecs
-- array. If the user had thresholdEnabled, create an "All Specs" entry with
-- their existing threshold and tick values. If disabled, leave empty.
-------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "resource_bars_threshold_specs_v1",
    scope       = "profile",
    description = "Migrate secondary threshold settings into per-spec thresholdSpecs entries.",
    body = function(ctx)
        local erb = ctx.profile.addons and ctx.profile.addons.EllesmereUIResourceBars
        local sec = erb and erb.secondary
        if not sec then return end
        -- Already migrated
        if sec.thresholdSpecs then return end
        if sec.thresholdEnabled then
            sec.thresholdSpecs = {
                {
                    specIDs = { 0 },  -- All Specs
                    hashValues = sec.tickValues or "",
                    thresholdCount = sec.thresholdCount or 3,
                    thresholdPartialOnly = sec.thresholdPartialOnly or false,
                },
            }
        else
            sec.thresholdSpecs = {}
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "resource_bars_power_threshold_specs_v1",
    scope       = "profile",
    description = "Migrate power bar threshold settings into per-spec thresholdSpecs entries.",
    body = function(ctx)
        local erb = ctx.profile.addons and ctx.profile.addons.EllesmereUIResourceBars
        local pri = erb and erb.primary
        if not pri then return end
        if pri.thresholdSpecs then return end
        if pri.thresholdEnabled then
            pri.thresholdSpecs = {
                {
                    specIDs = { 0 },
                    thresholdEnabled = true,
                    thresholdPct = pri.thresholdPct or 30,
                    thresholdPartialOnly = pri.thresholdPartialOnly or false,
                    thresholdR = pri.thresholdR or 1.0,
                    thresholdG = pri.thresholdG or 0.2,
                    thresholdB = pri.thresholdB or 0.2,
                    thresholdA = pri.thresholdA or 1,
                },
            }
        else
            pri.thresholdSpecs = {}
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "resource_bars_health_threshold_specs_v1",
    scope       = "profile",
    description = "Migrate health bar threshold settings into per-spec thresholdSpecs entries.",
    body = function(ctx)
        local erb = ctx.profile.addons and ctx.profile.addons.EllesmereUIResourceBars
        local hp = erb and erb.health
        if not hp then return end
        if hp.thresholdSpecs then return end
        if hp.thresholdEnabled then
            hp.thresholdSpecs = {
                {
                    specIDs = { 0 },
                    thresholdEnabled = true,
                    thresholdPct = hp.thresholdPct or 30,
                    thresholdR = hp.thresholdR or 1.0,
                    thresholdG = hp.thresholdG or 0.2,
                    thresholdB = hp.thresholdB or 0.2,
                    thresholdA = hp.thresholdA or 1,
                },
            }
        else
            hp.thresholdSpecs = {}
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "ab_default_grow_to_center_v1",
    scope       = "profile",
    description = "Convert AB bars with default UP growth to CENTER (UP now has real edge preservation).",
    body = function(ctx)
        local ab = ctx.profile.addons and ctx.profile.addons.EllesmereUIActionBars
        local abBars = ab and ab.bars
        if not abBars then return end
        for barKey, cfg in pairs(abBars) do
            if not cfg.growDirection or cfg.growDirection == "up" then
                cfg.growDirection = "center"
            end
        end
    end,
})


EllesmereUI.RegisterMigration({
    id          = "enhance_five_bar_off_existing_v1",
    scope       = "profile",
    description = "Existing profiles default enhanceFiveBar to false; new installs get true from defaults.",
    body = function(ctx)
        local erb = ctx.profile.addons and ctx.profile.addons.EllesmereUIResourceBars
        local sec = erb and erb.secondary
        if sec and sec.enhanceFiveBar == nil then
            sec.enhanceFiveBar = false
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "auto_open_containers_preserve_v1",
    scope       = "global",
    description = "Preserve autoOpenContainers for existing users after default changed from on to off.",
    body = function(ctx)
        local db = ctx.db
        -- Existing users ONLY. On a fresh install (or right after a factory
        -- reset) the DB has no profiles yet at early-migration time, and the
        -- key is nil because the user is NEW -- not because they predate the
        -- default flip. Without this gate the migration fired on first
        -- install and enabled Auto Open Containers against the OFF default.
        if not (db.profiles and next(db.profiles)) then return end
        if db.autoOpenContainers == nil then
            db.autoOpenContainers = true
        end
    end,
})

-------------------------------------------------------------------------------
--  Bags profile migration: copy flat EllesmereUIDB root keys into each
--  profile's addons.EllesmereUIBags so the Bags module can use NewDB().
-------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "bags_to_profile_v1",
    scope       = "global",
    description = "Migrate Bags settings from EllesmereUIDB root to per-profile storage.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end

        local function DCopy(t)
            if type(t) ~= "table" then return t end
            local c = {}
            for k, v in pairs(t) do c[k] = DCopy(v) end
            return c
        end

        local PROFILE_KEYS = {
            "bagScale", "bagColumns", "bagCatTitleSize", "bagCountFontSize",
            "itemlevelFontSize", "showItemlevelInBags", "showUpgradeIndicator",
            "bagShowTrackRank", "itemlevelUseCustomColor", "itemlevelCustomColor",
            "bagHideEmptyCategories", "bagSidebarCollapsed", "bankSidebarCollapsed",
            "bagShowPinnedItems", "bagShowRecentItems", "bagPinnedInOneBag",
            "bagRecentInOneBag", "bagShowPinRecentTips", "bagShowSortIcon",
            "bagHideRandomize", "bagDefaultOneBag", "bagNestByExpansion",
            "bagHideOneBagWarning", "bagHideAddCategory", "bagMoveNoShift",
            "enableGoldTracking", "detachReagentBag", "enhancedBags",
            "bagCategoryState", "bagCategoryOrder", "bagDisabledCategories",
            "bagUserCategories", "bagsPosition", "bankPosition",
            "bagVisualOrder", "bagHiddenInAllItems", "currencyOrder",
        }

        for profName, profData in pairs(db.profiles) do
            if type(profData) == "table" then
                if not profData.addons then profData.addons = {} end
                if not profData.addons.EllesmereUIBags then
                    local bags = {}
                    for _, k in ipairs(PROFILE_KEYS) do
                        local v = db[k]
                        if v ~= nil then
                            bags[k] = DCopy(v)
                        end
                    end
                    if next(bags) then
                        profData.addons.EllesmereUIBags = bags
                    end
                end
            end
        end

        -- (The Bags sync enable that used to live here moved into the
        -- mirror-group reset migration below, which seeds the default
        -- Bags group after wiping the old-format sync links.)
    end,
})

-- The Bags "Default Open to OneBag" boolean became a three-way "Default Bag
-- Type" dropdown (all / onebag / multibag). Seed the new key from the legacy
-- boolean so existing users keep their OneBag default, then drop the old key.
-- Runs AFTER bags_to_profile_v1 (registered above) so the legacy key already
-- lives in the per-profile bags table. Imported profiles skip this migration
-- (they inherit migration flags), so the import path forward-copies the legacy
-- key in ApplyProfileData (EllesmereUI_Profiles.lua) before DeepMergeDefaults.
EllesmereUI.RegisterMigration({
    id          = "bags_default_bag_type_v1",
    scope       = "profile",
    description = "Convert legacy bagDefaultOneBag boolean into the bagDefaultBagType string (all/onebag/multibag).",
    body = function(ctx)
        local bags = ctx.profile.addons and ctx.profile.addons.EllesmereUIBags
        if not bags then return end                       -- fresh profile: defaults handle it
        if bags.bagDefaultBagType ~= nil then return end  -- already migrated (idempotent)
        bags.bagDefaultBagType = (bags.bagDefaultOneBag == true) and "onebag" or "all"
        bags.bagDefaultOneBag = nil                       -- drop the legacy key
    end,
})

-- Guardian Druid Ironfur bar ships ON by default (DEFAULTS.secondary.guardianIronfurBar
-- = true) so brand-new installs get it out of the box. Existing users, however,
-- are used to Guardian having no class resource bar, so we pin every profile that
-- already exists to OFF. This runs at parent ADDON_LOADED, BEFORE any child NewDB
-- has populated EllesmereUIDB.profiles -- so the only profiles present here were
-- loaded from SavedVariables (i.e. existing users). Fresh installs have no profiles
-- yet, so nothing is pinned and they inherit the ON default. Global scope means it
-- runs exactly once: profiles created later (including by existing users) also
-- inherit the new ON default.
EllesmereUI.RegisterMigration({
    id          = "resourcebars_guardian_ironfur_existing_off_v1",
    scope       = "global",
    description = "Pin the Guardian Druid Ironfur bar OFF for existing users' profiles; fresh installs and future profiles inherit the new ON default.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end
        for _, profData in pairs(db.profiles) do
            -- Only touch profiles that already hold real child-addon data, so a
            -- stray empty/stub profile can't be mistaken for an existing user's.
            if type(profData) == "table" and type(profData.addons) == "table"
               and next(profData.addons) then
                local rb = profData.addons.EllesmereUIResourceBars
                if type(rb) ~= "table" then
                    rb = {}
                    profData.addons.EllesmereUIResourceBars = rb
                end
                if type(rb.secondary) ~= "table" then rb.secondary = {} end
                if rb.secondary.guardianIronfurBar == nil then
                    rb.secondary.guardianIronfurBar = false
                end
            end
        end
    end,
})

-- Prot Warrior Ignore Pain bar ships ON by default (DEFAULTS.secondary.
-- protIgnorePainBar = true) so brand-new installs get it out of the box.
-- Existing users are used to Prot having no class resource bar, so pin every
-- profile that already exists to OFF. Same mechanism as the Guardian Ironfur
-- migration above: runs at parent ADDON_LOADED before any child NewDB populates
-- EllesmereUIDB.profiles, so only existing users' profiles are present; fresh
-- installs have none and inherit the ON default. Global scope = runs once;
-- future profiles inherit ON too.
EllesmereUI.RegisterMigration({
    id          = "resourcebars_protwar_ignorepain_existing_off_v1",
    scope       = "global",
    description = "Pin the Prot Warrior Ignore Pain bar OFF for existing users' profiles; fresh installs and future profiles inherit the new ON default.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end
        for _, profData in pairs(db.profiles) do
            -- Only touch profiles that already hold real child-addon data, so a
            -- stray empty/stub profile can't be mistaken for an existing user's.
            if type(profData) == "table" and type(profData.addons) == "table"
               and next(profData.addons) then
                local rb = profData.addons.EllesmereUIResourceBars
                if type(rb) ~= "table" then
                    rb = {}
                    profData.addons.EllesmereUIResourceBars = rb
                end
                if type(rb.secondary) ~= "table" then rb.secondary = {} end
                if rb.secondary.protIgnorePainBar == nil then
                    rb.secondary.protIgnorePainBar = false
                end
            end
        end
    end,
})

-- Unit Frame cast bars now count the spell icon as part of the bar's width by
-- default (DEFAULTS.player.playerCastbarIconInWidth / *.castbarIconInWidth =
-- true), so fresh installs get the icon inside the bar footprint out of the box.
-- Existing users are used to the icon sitting to the LEFT of the bar (outside
-- its width), so pin every already-existing profile to OFF. Same mechanism as
-- the Guardian Ironfur migration: runs at parent ADDON_LOADED before any child
-- NewDB populates EllesmereUIDB.profiles, so only existing users' profiles are
-- present; fresh installs have none and inherit the ON default. Global scope =
-- runs once; future profiles inherit ON too. Nameplates have their own cast bar
-- settings and are intentionally NOT touched.
EllesmereUI.RegisterMigration({
    id          = "uf_castbar_icon_in_width_existing_off_v1",
    scope       = "global",
    description = "Pin cast-bar icon-in-width OFF for existing users' Unit Frames profiles; fresh installs and future profiles inherit the new ON default. Nameplates unaffected.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end
        for _, profData in pairs(db.profiles) do
            -- Only touch profiles that already hold real child-addon data, so a
            -- stray empty/stub profile can't be mistaken for an existing user's.
            if type(profData) == "table" and type(profData.addons) == "table"
               and next(profData.addons) then
                local uf = profData.addons.EllesmereUIUnitFrames
                if type(uf) ~= "table" then
                    uf = {}
                    profData.addons.EllesmereUIUnitFrames = uf
                end
                if type(uf.player) ~= "table" then uf.player = {} end
                if uf.player.playerCastbarIconInWidth == nil then
                    uf.player.playerCastbarIconInWidth = false
                end
                for _, unitKey in ipairs({ "target", "focus", "boss" }) do
                    if type(uf[unitKey]) ~= "table" then uf[unitKey] = {} end
                    if uf[unitKey].castbarIconInWidth == nil then
                        uf[unitKey].castbarIconInWidth = false
                    end
                end
            end
        end
    end,
})

-- Profile sync rebuilt as two-way mirror groups: a module's sync set is now a
-- membership group (the configuring profile is written into it) and only
-- group members push their data at logout/switch. Old sets stored receivers
-- only, with no record of who the sender was, so they cannot be translated
-- reliably -- and under the old code ANY active profile pushed into them,
-- which could silently overwrite profiles with data from an unrelated one.
-- Reset every sync link; profile data itself is untouched. Users re-enable
-- sync from the sidebar sync icons, which write the new group format.
-- EXCEPTION: Bags keeps syncing by default -- but ONLY for the profiles
-- that were in the old Bags set. Those members were already receiving bags
-- pushes on every logout, so mirroring exactly them adds zero new overwrite
-- exposure. Profiles OUTSIDE the old set may hold deliberately divergent
-- bags data and must stay out: imports were always stripped from sync sets
-- (preset imports included), and users could manually unsync Bags in the
-- old popup. Never seed those.
-- Registered LAST on purpose: it must run after the older Bags data-move
-- migration so accounts jumping many versions end up in the new shape.
EllesmereUI.RegisterMigration({
    id          = "sync_reset_for_mirror_groups_v2",
    scope       = "global",
    description = "Reset all profile sync links for the mirror-group rework (profile data untouched; sync is re-enabled via the module sync icons). The Bags group carries over its previous members only.",
    body = function(ctx)
        local db = ctx.db
        if not db then return end
        -- Capture the old Bags membership before wiping. Legacy boolean
        -- format (pre per-profile sets) meant "all profiles".
        local oldBags = db.syncedModules and db.syncedModules.EllesmereUIBags
        local carried, count = {}, 0
        if db.profiles then
            if oldBags == true then
                for profName in pairs(db.profiles) do
                    carried[profName] = true
                    count = count + 1
                end
            elseif type(oldBags) == "table" then
                for profName, v in pairs(oldBags) do
                    if v and db.profiles[profName] then
                        carried[profName] = true
                        count = count + 1
                    end
                end
            end
        end
        db.syncedModules = {}
        if count >= 2 then
            db.syncedModules.EllesmereUIBags = carried
        end
    end,
})

-- Custom colours are gaining an opt-in "Save Colors Per Profile" mode. Seed every
-- existing profile's customColors from the current account-wide table so that, the
-- moment the mode is enabled, every profile starts with identical colours (no
-- jarring change). The global EllesmereUIDB.customColors is left intact and stays
-- the source of truth while the mode is off. One-time, account-wide overwrite --
-- prior per-profile customColors snapshots were inert (never restored) so there is
-- nothing meaningful to preserve.
EllesmereUI.RegisterMigration({
    id          = "global_colors_per_profile_seed_v1",
    scope       = "global",
    description = "Seed every profile's customColors from the global table for the opt-in per-profile colours mode.",
    body        = function(ctx)
        local db = ctx.db
        if not db or type(db.customColors) ~= "table" or type(db.profiles) ~= "table" then return end
        local DeepCopy = EllesmereUI._DeepCopy or (EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy)
        if not DeepCopy then return end
        for _, pd in pairs(db.profiles) do
            if type(pd) == "table" then
                pd.customColors = DeepCopy(db.customColors)
            end
        end
    end,
})

-- Secondary Stats + FPS counter moved off the account-wide EllesmereUIDB root
-- into the per-profile QoL blob (folder EllesmereUIQoL) so they travel with
-- profiles, export/import, and module sync (see EllesmereUI.QoLExtrasGet/Set in
-- EllesmereUIQoL.lua). Seed EVERY existing profile from the old account-wide
-- values -- DeepCopy so each profile owns independent color/position tables --
-- so nobody loses their current setup on any profile. The root keys are left in
-- place as the read-time fallback for profiles created later (and as a dormant
-- backup). Per-key nil guard keeps it safe to re-run.
EllesmereUI.RegisterMigration({
    id          = "qol_secondary_stats_fps_per_profile_v1",
    scope       = "global",
    description = "Seed every profile's QoL data with the formerly account-wide Secondary Stats + FPS settings.",
    body        = function(ctx)
        local db = ctx.db
        if not db or type(db.profiles) ~= "table" then return end
        local DeepCopy = EllesmereUI._DeepCopy or (EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy)
        if not DeepCopy then return end
        local KEYS = {
            "showSecondaryStats", "secondaryStatsColor", "showTertiaryStats",
            "tertiaryStatsColor", "secondaryStatsPos",
            "showFPS", "fpsTextSize", "fpsColor",
            "fpsShowWorldMS", "fpsShowLocalMS", "fpsHideLabel", "fpsPos",
        }
        for _, pd in pairs(db.profiles) do
            if type(pd) == "table" then
                if type(pd.addons) ~= "table" then pd.addons = {} end
                local q = pd.addons.EllesmereUIQoL
                if type(q) ~= "table" then q = {}; pd.addons.EllesmereUIQoL = q end
                for _, k in ipairs(KEYS) do
                    local v = db[k]
                    if v ~= nil and q[k] == nil then
                        if type(v) == "table" then
                            q[k] = DeepCopy(v)
                        else
                            q[k] = v
                        end
                    end
                end
            end
        end
    end,
})

-- "Disable Slug Outline" (neverShowSlug) and "Outline Icon Text" (outlineIconText)
-- moved off the account-wide EllesmereUIDB root into the per-profile fonts DB so
-- they travel with profile export/import and module sync. Seed the live working
-- fonts table (active profile) AND every EXISTING profile fonts snapshot from the
-- old account-wide values so nobody's look changes on any profile. Profiles with
-- no fonts snapshot are left untouched -- creating a partial one would reset their
-- global font / outline mode on the next switch; their getter fallback covers the
-- read side. The root keys stay in place as the read-time fallback (getters in
-- EllesmereUI.lua) and a dormant backup. Per-key nil guard keeps it safe to re-run.
EllesmereUI.RegisterMigration({
    id          = "fonts_slug_iconoutline_per_profile_v1",
    scope       = "global",
    description = "Seed every profile's fonts DB with the formerly account-wide Disable Slug Outline + Outline Icon Text settings.",
    body        = function(ctx)
        local db = ctx.db
        if not db then return end
        local slug = db.neverShowSlug
        local oit  = db.outlineIconText
        if slug == nil and type(oit) ~= "table" then return end
        local function seed(fonts)
            if type(fonts) ~= "table" then return end
            if fonts.neverShowSlug == nil and slug ~= nil then
                fonts.neverShowSlug = slug and true or false
            end
            if fonts.outlineIconText == nil and type(oit) == "table" then
                local t = {}
                for k, v in pairs(oit) do t[k] = v end
                fonts.outlineIconText = t
            end
        end
        -- Live working copy = what a full export of the active profile snapshots
        -- via DeepCopy(GetFontsDB()).
        seed(db.fonts)
        -- Existing stored snapshots = so exporting a non-active profile carries it.
        if type(db.profiles) == "table" then
            for _, pd in pairs(db.profiles) do
                if type(pd) == "table" then seed(pd.fonts) end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "blizzskin_reskin_master_split_v1",
    scope       = "global",
    description = "Split the old 'Reskin Blizzard Elements' master (customTooltips) into independent Reskin Popups and Menus + per-window reskins, seeding each from the old master value once so what is reskinned stays exactly the same.",
    body        = function(ctx)
        local db = ctx.db
        if not db then return end
        -- customTooltips is now tooltip-only, but at migration time it still holds
        -- the OLD combined-master value, so seed the split-out keys from it once.
        local master = (db.customTooltips ~= false)
        -- The old game-menu / group-finder defaults ANDed in the queue-popup state
        -- (a nil queue popup counted as on), matching the live default formula.
        local queueNotFalse = (db.reskinQueuePopup ~= false)
        if db.reskinPopupsMenus == nil then db.reskinPopupsMenus = master end
        if db.reskinQueuePopup  == nil then db.reskinQueuePopup  = master end
        if db.reskinGreatVault  == nil then db.reskinGreatVault  = master end
        if db.reskinGameMenu    == nil then db.reskinGameMenu    = master and queueNotFalse end
        if db.reskinLFGMenu     == nil then db.reskinLFGMenu     = master and queueNotFalse end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "texture_kringel_diamonds_to_blinkii_v1",
    scope       = "profile",
    description = "Rename the saved 'kringel-diamonds' bar texture value to its replacement 'blinkii-diamonds' across Unit Frames, Raid Frames, Nameplates, Resource Bars, and Damage Meters.",
    body = function(ctx)
        -- The kringel-diamonds texture was replaced by blinkii-diamonds (same slot,
        -- new art). The dropdown value is the texture KEY string, stored under
        -- different fields per module (healthBarTexture, general.barTexture,
        -- castBar.texture, per-unit overrides, dm.barTexture). "kringel-diamonds"
        -- only ever appears as a texture-selection value, so a recursive value swap
        -- over each module's saved data catches every storage location and is
        -- idempotent (nothing left to match on a second pass).
        local addons = ctx.profile.addons
        if type(addons) ~= "table" then return end

        local function swap(t, depth)
            if type(t) ~= "table" or depth > 8 then return end
            for k, v in pairs(t) do
                if v == "kringel-diamonds" then
                    t[k] = "blinkii-diamonds"
                elseif type(v) == "table" then
                    swap(v, depth + 1)
                end
            end
        end

        local MODULES = {
            "EllesmereUIUnitFrames", "EllesmereUIRaidFrames", "EllesmereUINameplates",
            "EllesmereUIResourceBars", "EllesmereUIDamageMeters",
        }
        for _, name in ipairs(MODULES) do
            swap(addons[name], 1)
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "purge_anchor_debug_log_v1",
    scope       = "global",
    description = "Remove the temporary _anchorDebugLog table left in the central DB by the combat-reload anchor diagnostics.",
    body = function()
        if EllesmereUIDB then
            EllesmereUIDB._anchorDebugLog = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "minimap_coords_mode_position_v1",
    scope       = "profile",
    description = "Convert the minimap 'Show Coordinates Below Map' toggle into coordsMode/coordsPosition dropdown values, preserving each user's current coordinate behavior.",
    body = function(ctx)
        -- Only profiles that have used the Minimap module are migrated; fresh
        -- installs take the new defaults (always / topLeft). The addons key
        -- survives the logout default-strip even when every minimap setting is
        -- default (empty table), so an all-default existing user still lands
        -- on hover -- their old effective behavior. Runs AFTER
        -- v66_basics_split_data (registration order), so pre-split Basics
        -- minimap data has already been moved to this path.
        local emm = ctx.profile.addons and ctx.profile.addons.EllesmereUIMinimap
        if type(emm) ~= "table" then return end
        local mm = emm.minimap
        if type(mm) ~= "table" then
            mm = {}
            emm.minimap = mm
        end
        if mm.coordsMode ~= nil then return end  -- already on the new keys
        if mm.coordsBelow then
            mm.coordsMode = "always"
            mm.coordsPosition = "belowMap"
        else
            mm.coordsMode = "hover"
            mm.coordsPosition = "topLeft"
            -- The X/Y nudge only applied in below-map mode; clear leftovers so
            -- they don't shift the newly position-aware hover coordinates.
            mm.coordsBelowOffsetX = nil
            mm.coordsBelowOffsetY = nil
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "minimap_clock_location_mode_v2",
    scope       = "profile",
    description = "Convert the minimap Clock Inside / Zone Inside toggles into clockMode/locationMode dropdown values (none/inside/edge). Elements hidden via the removed Show Blizzard Elements Zone/Clock checkboxes become 'none'. Replaces the never-shipped _v1 (deleted).",
    body = function(ctx)
        -- Same gate as minimap_coords_mode_position_v1: only profiles that have
        -- used the Minimap module migrate; fresh installs take the new defaults
        -- (inside / inside). Stored data is default-stripped, so absent keys
        -- mean the old defaults: showClock defaulted ON (only false is ever
        -- stored), hideZoneText defaulted OFF (only true is ever stored),
        -- clockInside defaulted ON, zoneInside defaulted OFF.
        local emm = ctx.profile.addons and ctx.profile.addons.EllesmereUIMinimap
        if type(emm) ~= "table" then return end
        local mm = emm.minimap
        if type(mm) ~= "table" then
            mm = {}
            emm.minimap = mm
        end
        -- Hidden via the removed Show Blizzard Elements checkboxes wins, even
        -- over a mode already stamped by the unshipped v1 pass (dev/testers).
        if mm.showClock == false then
            mm.clockMode = "none"
        elseif mm.clockMode == nil then
            mm.clockMode = (mm.clockInside == false) and "edge" or "inside"
        end
        if mm.hideZoneText == true then
            mm.locationMode = "none"
        elseif mm.locationMode == nil then
            mm.locationMode = mm.zoneInside and "inside" or "edge"
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "minimap_omnium_folio_mode_v1",
    scope       = "profile",
    description = "Convert the minimap Show Omnium Folio toggle into the omniumFolioMode dropdown (never/hover/always), preserving each user's current visibility.",
    body = function(ctx)
        -- Same gate as the other minimap mode migrations: only profiles that
        -- have used the module migrate; fresh installs take the new default
        -- (always). Stored data is default-stripped, so only an explicit
        -- showOmniumFolio == false is ever present (default was ON).
        local emm = ctx.profile.addons and ctx.profile.addons.EllesmereUIMinimap
        if type(emm) ~= "table" then return end
        local mm = emm.minimap
        if type(mm) ~= "table" then
            mm = {}
            emm.minimap = mm
        end
        if mm.omniumFolioMode == nil then
            mm.omniumFolioMode = (mm.showOmniumFolio == false) and "never" or "always"
        end
    end,
})

-------------------------------------------------------------------------------
--  CDM per-spell settings: tiered-store shape transform
--
--  OLD shape: barSpells[barKey].spellSettings[sid] = { ... } (bar-scoped; a
--  spell moved to another bar lost its settings and left an orphan behind) plus
--  barSpells[barKey]._syncIconSettings (Sync All Bar Buttons: stamped one
--  spell's whole block onto every other spell on the bar).
--
--  NEW shape:
--    specProf.spellSettingsCD[sid] / specProf.spellSettingsBuff[sid]
--        per-spell entries, family-scoped, travel with the spell across bars
--    barSpells[barKey].barSettings
--        "Apply to Bar" tier (per spec); seeded from synced bars
--    bd.barSpellSettings (profile-level bar definition; NOT written here)
--        "Apply to Bar (All Specs)" tier, starts empty
--
--  Faithfulness rules (nothing changes visually):
--    * Entries move only when the spell is CURRENTLY assigned to the bar the
--      entry lives on (authoritative), or is not visibly assigned anywhere
--      (hidden/removed spells keep their styling for when they return).
--    * Stale orphans for spells now owned by a DIFFERENT bar are dropped --
--      that spell renders default today; adopting the orphan would change it.
--    * Synced bars promote their uniform stamped block to barSettings and drop
--      the per-spell copies that match it. A divergent copy is kept as a
--      per-spell override, with explicit `false` fillers for any seed key it
--      lacks (false is render-equivalent to nil for every settings key) so the
--      new bar tier cannot bleed through a key the spell never had.
--
--  Shared with the profile-import path so old-format strings imported after
--  this update are transformed immediately (the registered migration also
--  covers them on the next reload -- both are idempotent).
-------------------------------------------------------------------------------
local function CdmFlatSettingsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

-- Classify a barSpells bucket key into its settings-family store key.
-- Mirrors the runtime rule (ns.SettingsFamilyKey): only barType "buffs" (and
-- the default "buffs" bar) are buff-family; custom_buff and the ghost bar are
-- not. Stale buckets for deleted bars fall back to a key heuristic -- their
-- entries are orphan candidates at most, so a miss is inert.
local function CdmBarFamilyKey(barKey, barsCfg)
    if barKey == "buffs" then return "spellSettingsBuff" end
    if barKey == "__ghost_cd" then return "spellSettingsCD" end
    if type(barsCfg) == "table" then
        for _, b in ipairs(barsCfg) do
            if type(b) == "table" and b.key == barKey then
                return (b.barType == "buffs") and "spellSettingsBuff" or "spellSettingsCD"
            end
        end
    end
    if type(barKey) == "string" and barKey:find("buff", 1, true) then
        return "spellSettingsBuff"
    end
    return "spellSettingsCD"
end

function EllesmereUI.MigrateCdmSpellSettingsShape(specProf, barsCfg)
    if type(specProf) ~= "table" then return end
    local barSpells = specProf.barSpells
    if type(barSpells) ~= "table" then return end

    -- Pass 0: visible assignment map per family. Ghost-bar assignments do NOT
    -- count as visible, so a hidden spell's orphaned entry still migrates and
    -- un-hiding restores its styling on any bar.
    local visibleAssign = { spellSettingsCD = {}, spellSettingsBuff = {} }
    for barKey, bs in pairs(barSpells) do
        if barKey ~= "__ghost_cd" and type(bs) == "table"
           and type(bs.assignedSpells) == "table" then
            local famKey = CdmBarFamilyKey(barKey, barsCfg)
            for _, sid in ipairs(bs.assignedSpells) do
                if type(sid) == "number" and sid ~= 0 then
                    visibleAssign[famKey][sid] = barKey
                end
            end
        end
    end

    -- Pass 1: relocate entries whose spell is assigned to the bar the entry
    -- lives on. Pass 2: adopt entries for spells not visibly assigned anywhere.
    for pass = 1, 2 do
        for barKey, bs in pairs(barSpells) do
            local old = type(bs) == "table" and bs.spellSettings
            if type(old) == "table" then
                local famKey = CdmBarFamilyKey(barKey, barsCfg)
                local assign = visibleAssign[famKey]
                for sid, entry in pairs(old) do
                    if type(entry) ~= "table" or next(entry) == nil then
                        old[sid] = nil
                    else
                        local takeIt
                        if pass == 1 then
                            takeIt = (assign[sid] == barKey)
                        else
                            takeIt = (assign[sid] == nil)
                        end
                        if takeIt then
                            local store = specProf[famKey]
                            if not store then store = {}; specProf[famKey] = store end
                            if store[sid] == nil then store[sid] = entry end
                            old[sid] = nil
                        end
                    end
                end
            end
        end
    end

    -- Pass 3: promote synced bars to the bar tier, then clear the flag and
    -- drop whatever old-shape residue remains (stale different-bar orphans).
    for barKey, bs in pairs(barSpells) do
        if type(bs) == "table" then
            if bs._syncIconSettings == true and type(bs.assignedSpells) == "table"
               and type(bs.barSettings) ~= "table" then
                local famKey = CdmBarFamilyKey(barKey, barsCfg)
                local store = specProf[famKey]
                local seed
                if store then
                    for _, sid in ipairs(bs.assignedSpells) do
                        local e = store[sid]
                        if type(e) == "table" and next(e) ~= nil then seed = e; break end
                    end
                end
                if seed then
                    local copy = {}
                    for k, v in pairs(seed) do copy[k] = v end
                    bs.barSettings = copy
                    for _, sid in ipairs(bs.assignedSpells) do
                        local e = store[sid]
                        if type(e) == "table" then
                            if CdmFlatSettingsEqual(e, copy) then
                                store[sid] = nil
                            else
                                -- Divergent override: block seed keys it lacks
                                -- so the new bar tier can't bleed through.
                                for k in pairs(copy) do
                                    if e[k] == nil then e[k] = false end
                                end
                            end
                        end
                    end
                end
            end
            bs._syncIconSettings = nil
            if type(bs.spellSettings) == "table" then
                bs.spellSettings = nil
            end
        end
    end
end

EllesmereUI.RegisterMigration({
    id          = "cdm_spell_settings_tiers_v1",
    scope       = "specProfile",
    description = "Move CDM per-spell icon settings from per-bar spellSettings into per-spec family stores (settings now travel with the spell across bars), and promote Sync All Bar Buttons bars into bar-level Apply-to-Bar settings.",
    body = function(ctx)
        local prof = EllesmereUIDB.profiles and EllesmereUIDB.profiles[ctx.profileName]
        local cdm = prof and prof.addons and prof.addons.EllesmereUICooldownManager
        local barsCfg = cdm and cdm.cdmBars and cdm.cdmBars.bars
        EllesmereUI.MigrateCdmSpellSettingsShape(ctx.specProfile, barsCfg)
    end,
})

-- Relocate HOSTED-buff per-spell settings from the CD family store into the
-- BUFF family store, for every bar that hosts the buff. Hosted buffs (a buff
-- placed on a CD/utility bar) originally resolved per-spell settings through
-- the host bar's family key (CD); they now resolve the BUFF store, frame-keyed,
-- so the same spellID's cooldown icon can hold independent settings. Without
-- the move, pre-existing hosted-buff settings would silently stop applying.
-- Idempotent: moves only while a CD-store entry exists for a flagged id, and
-- never overwrites keys already present in the BUFF-store entry. (A cooldown
-- twin's own settings under the same id move too -- unsplittable in the old
-- shared-entry shape, and that state was already rendering wrong.)
-- assignedSpells conversion (plain id -> hosted marker) is NOT done here: it
-- needs the live viewer/catalog data to tell the buff and cooldown forms
-- apart, so the options panel normalizes it lazily (EnsureAssignedSpells);
-- rendering handles both shapes in the meantime.
function EllesmereUI.MigrateCdmHostedBuffSettings(specProf)
    if type(specProf) ~= "table" or type(specProf.barSpells) ~= "table" then return end
    local stCD = specProf.spellSettingsCD
    if type(stCD) ~= "table" then return end
    for _, sd in pairs(specProf.barSpells) do
        local hosted = type(sd) == "table" and sd.hostedBuffSpellIDs
        if type(hosted) == "table" then
            for hsid in pairs(hosted) do
                local e = stCD[hsid]
                if type(e) == "table" then
                    local stBuff = specProf.spellSettingsBuff
                    if type(stBuff) ~= "table" then
                        stBuff = {}
                        specProf.spellSettingsBuff = stBuff
                    end
                    local tgt = stBuff[hsid]
                    if type(tgt) ~= "table" then
                        stBuff[hsid] = e
                    else
                        for k, v in pairs(e) do
                            if tgt[k] == nil then tgt[k] = v end
                        end
                    end
                    stCD[hsid] = nil
                end
            end
        end
    end
end

EllesmereUI.RegisterMigration({
    id          = "cdm_hosted_buff_settings_v1",
    scope       = "specProfile",
    description = "Move hosted-buff per-spell icon settings from the CD family store to the BUFF family store (hosted buffs now share the buff-family settings entry with the buffs bar, independent of the same spell's cooldown icon).",
    body = function(ctx)
        EllesmereUI.MigrateCdmHostedBuffSettings(ctx.specProfile)
    end,
})

-- Convert the per-bar "Custom Active State Decimals" (bd.faDecimals*) into the
-- per-spell Threshold Text settings that replaced it. The old bar toggle drove a
-- 1-decimal countdown (+ optional color change) on custom/preset icons' hardcoded
-- timers; the new model stores Threshold Seconds / Threshold Decimals / Threshold
-- Color per spell. For every bar that had the toggle on, each custom spell/item
-- member gets stamped so it renders exactly as before:
--  * cd/utility bars: item presets and custom/racial spells stamp the
--    profile-level customActiveStates entry (their menu + Fake-Active engine read
--    that store). Trinket SLOT presets resolve their settings key by the EQUIPPED
--    item at runtime; stamped here only when the inventory API already answers
--    (best effort -- re-arming per trinket is one click).
--  * buff-family bars: custom buffs (cast-timer entries / tagged custom ids)
--    stamp the spec BUFF family store. Blizzard-tracked buffs were never covered
--    by the old toggle, so they are not stamped.
-- The old bd.faDecimals* keys are consumed (removed) in the same pass. Shared
-- with profile import so old-format strings transform immediately.
function EllesmereUI.MigrateCdmThresholdText(cdm, specProfiles)
    local barsCfg = cdm and cdm.cdmBars and cdm.cdmBars.bars
    if type(barsCfg) ~= "table" then return end
    for _, bd in ipairs(barsCfg) do
        if type(bd) == "table" then
            local thr = tonumber(bd.faDecimalsThreshold) or 5
            if thr > 59 then thr = 59 end
            if bd.faDecimals == true and thr > 0 and bd.key then
                local colorOn = bd.faDecimalsColorEnabled == true
                local cr = bd.faDecimalsColorR or 1
                local cg = bd.faDecimalsColorG or 0.2
                local cb = bd.faDecimalsColorB or 0.2
                local isBuffFam = (bd.barType == "buffs") or (bd.key == "buffs")
                local function Stamp(e)
                    if type(e) ~= "table" then return end
                    e.thresholdSeconds = thr
                    e.thresholdDecimals = true
                    if colorOn then
                        e.thresholdColorEnabled = true
                        e.thresholdColorR = cr
                        e.thresholdColorG = cg
                        e.thresholdColorB = cb
                    end
                end
                local function StampCas(key)
                    if type(cdm.customActiveStates) ~= "table" then
                        cdm.customActiveStates = {}
                    end
                    local e = cdm.customActiveStates[key]
                    if type(e) ~= "table" then
                        e = {}
                        cdm.customActiveStates[key] = e
                    end
                    Stamp(e)
                end
                if type(specProfiles) == "table" then
                    for _, specProf in pairs(specProfiles) do
                        local bs = type(specProf) == "table"
                            and type(specProf.barSpells) == "table"
                            and specProf.barSpells[bd.key]
                        local assigned = type(bs) == "table" and bs.assignedSpells
                        if type(assigned) == "table" then
                            for _, sid in ipairs(assigned) do
                                if type(sid) == "number" then
                                    if isBuffFam then
                                        -- Custom buffs: cast-timer entries (stored
                                        -- duration) and tagged custom ids.
                                        if sid > 0 and ((type(bs.spellDurations) == "table"
                                                and (tonumber(bs.spellDurations[sid]) or 0) > 0)
                                            or (type(bs.customSpellIDs) == "table"
                                                and bs.customSpellIDs[sid])) then
                                            local st = specProf.spellSettingsBuff
                                            if type(st) ~= "table" then
                                                st = {}
                                                specProf.spellSettingsBuff = st
                                            end
                                            local e = st[sid]
                                            if type(e) ~= "table" then
                                                e = {}
                                                st[sid] = e
                                            end
                                            Stamp(e)
                                        end
                                    elseif sid <= -2000000000 then
                                        -- Hosted-buff marker: a real Blizzard buff,
                                        -- never covered by the old toggle.
                                    elseif sid == -13 or sid == -14 then
                                        local ok, itemID = pcall(GetInventoryItemID, "player", -sid)
                                        if ok and itemID then StampCas(-itemID) end
                                    elseif sid < 0 then
                                        StampCas(sid)
                                    elseif (type(bs.customSpellIDs) == "table" and bs.customSpellIDs[sid])
                                        or (type(cdm.customActiveStates) == "table"
                                            and type(cdm.customActiveStates[sid]) == "table"
                                            and (tonumber(cdm.customActiveStates[sid].duration) or 0) > 0) then
                                        -- Tagged custom spell ids, plus racials or
                                        -- other injected spells that already carry a
                                        -- user-defined active state.
                                        StampCas(sid)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            bd.faDecimals = nil
            bd.faDecimalsThreshold = nil
            bd.faDecimalsColorEnabled = nil
            bd.faDecimalsColorR = nil
            bd.faDecimalsColorG = nil
            bd.faDecimalsColorB = nil
        end
    end
end

EllesmereUI.RegisterMigration({
    id          = "cdm_threshold_text_v1",
    scope       = "global",
    description = "Replace the per-bar Custom Active State Decimals with per-spell Threshold Text: opted-in bars' custom spell/item members get per-spell Threshold Seconds/Decimals (+ Color) stamps, and the old bar keys are removed.",
    body = function(ctx)
        local db = ctx.db
        if not db or type(db.profiles) ~= "table" then return end
        local saProfiles = db.spellAssignments and db.spellAssignments.profiles
        for profName, profData in pairs(db.profiles) do
            local cdm = type(profData) == "table" and type(profData.addons) == "table"
                and profData.addons.EllesmereUICooldownManager
            if type(cdm) == "table" then
                local bucket = type(saProfiles) == "table" and saProfiles[profName]
                local sp = type(bucket) == "table" and bucket.specProfiles or nil
                EllesmereUI.MigrateCdmThresholdText(cdm, sp)
            end
        end
    end,
})

-- The default buffs bar's displayed order (sd.buffDisplayOrder) is auto-resynced
-- to Blizzard's current viewer order by ReconcileBuffDisplayOrder unless
-- sd._buffDisplayOrderUserModified is set. The flag arrived together with the
-- live-path reconcile and is only ever written by the options drag-reorder --
-- but before the flag existed, buffDisplayOrder itself was created exclusively
-- by a manual drag, so every pre-existing stable-key array IS a user's
-- hand-arranged order. Stamp the flag so the first live reconcile after
-- updating preserves that order instead of re-sorting it to Blizzard order.
-- Numeric-format legacy arrays are skipped: the reconcile (and the old options
-- build before it) discards that format outright, so there is no order a stamp
-- could preserve. Shared with profile import so orders exported from older
-- builds keep their protection.
function EllesmereUI.MigrateCdmBuffOrderUserFlag(specProf)
    local bs = type(specProf) == "table" and type(specProf.barSpells) == "table"
        and specProf.barSpells.buffs
    if type(bs) ~= "table" then return end
    if type(bs.buffDisplayOrder) == "table" and type(bs.buffDisplayOrder[1]) == "string" then
        bs._buffDisplayOrderUserModified = true
    end
end

EllesmereUI.RegisterMigration({
    id          = "cdm_buff_order_user_flag_v1",
    scope       = "specProfile",
    description = "Protect pre-existing manually-arranged Tracked Buffs orders from the live-path Blizzard-order resync by stamping _buffDisplayOrderUserModified on every stable-key buffDisplayOrder.",
    body = function(ctx)
        EllesmereUI.MigrateCdmBuffOrderUserFlag(ctx.specProfile)
    end,
})

-- The Mythic+ Timer's Enemy Forces bar historically shared one bar texture with
-- the main timer bar (both read barTexture / barBgTexture). The Forces bar now
-- has its own enemyBarTexture / enemyBarBgTexture so the two can be styled
-- independently. Seed the new keys from the old shared ones on every existing
-- profile so an existing user's Forces bar looks exactly as before; fresh
-- installs have no profiles here yet and inherit the new "none" default for
-- both. Global scope runs once, and it only seeds when the new key is unset, so
-- a later reset of the Forces texture is respected (not re-seeded each login).
EllesmereUI.RegisterMigration({
    id          = "mythictimer_split_forces_bar_texture_v1",
    scope       = "global",
    description = "Give the M+ Timer Forces bar its own texture keys, seeded from the shared bar texture so existing users' Forces bar is unchanged.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end
        for _, profData in pairs(db.profiles) do
            if type(profData) == "table" and type(profData.addons) == "table" then
                local mt = profData.addons.EllesmereUIMythicTimer
                if type(mt) == "table" then
                    if mt.enemyBarTexture == nil and mt.barTexture ~= nil then
                        mt.enemyBarTexture = mt.barTexture
                    end
                    if mt.enemyBarBgTexture == nil and mt.barBgTexture ~= nil then
                        mt.enemyBarBgTexture = mt.barBgTexture
                    end
                end
            end
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "uf_clear_stale_attached_power_border_v1",
    scope       = "profile",
    description = "Zero stale powerBorderSize on attached power bars so the new attached divider does not appear uninvited for users who set a border size while detached and later reattached.",
    body = function(ctx)
        -- Before attached dividers existed, the Border Size slider was
        -- disabled while the bar was attached, so a stored size > 0 with an
        -- attached position is always a leftover from a detached phase --
        -- never a divider the user asked for. Clearing it back to the
        -- default (0 = off) keeps frames looking identical across the
        -- update; opting into the divider is one slider drag.
        -- Positions other than above/below are untouched: detached keeps
        -- its full border, and "none" renders nothing either way.
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end
        -- Units whose powerPosition DEFAULT is attached ("below"); for them a
        -- missing powerPosition key still means attached. The mini frames
        -- default to "none", so a missing key there renders no border.
        local attachedDefault = { player = true, target = true, focus = true, boss = true }
        for unitKey, s in pairs(uf) do
            if type(s) == "table"
                and type(s.powerBorderSize) == "number" and s.powerBorderSize > 0 then
                local pos = s.powerPosition
                if pos == nil and attachedDefault[unitKey] then pos = "below" end
                if pos == "above" or pos == "below" then
                    s.powerBorderSize = nil
                end
            end
        end
    end,
})

-- Shared body: convert collided-buff cooldownID claims (bs.assignedBuffCdIDs,
-- a side-table with no order) into cd-claim markers stored inside
-- assignedSpells. Naturally idempotent: assignedBuffCdIDs is cleared after
-- migrating, so a second run finds nothing per bar. Also called at
-- profile-import time (EllesmereUI_Profiles.lua) so old export strings
-- carrying the side-table keep their claims.
--
-- Mirrors ns.CD_CLAIM_MARKER_BASE / ns.CdClaimMarker in
-- EllesmereUICooldownManager.lua (-(3000000000 + cooldownID)). Inlined
-- rather than called: the CDM child addon loads AFTER the login migration
-- runs, so its ns table isn't available yet.
function EllesmereUI.MigrateCdmBuffCdClaims(specProf)
    local CD_CLAIM_MARKER_BASE = 3000000000
    local barSpells = type(specProf) == "table" and specProf.barSpells
    if type(barSpells) ~= "table" then return end
    for _, bs in pairs(barSpells) do
        if type(bs) == "table" and type(bs.assignedBuffCdIDs) == "table"
           and next(bs.assignedBuffCdIDs) then
            if not bs.assignedSpells then bs.assignedSpells = {} end
            -- Dedup against any marker already present (e.g. a prior
            -- partial run interrupted by an error).
            local present = {}
            for _, id in ipairs(bs.assignedSpells) do
                if type(id) == "number" and id <= -CD_CLAIM_MARKER_BASE then
                    present[-id - CD_CLAIM_MARKER_BASE] = true
                end
            end
            for cdID in pairs(bs.assignedBuffCdIDs) do
                if type(cdID) == "number" and not present[cdID] then
                    bs.assignedSpells[#bs.assignedSpells + 1] = -(CD_CLAIM_MARKER_BASE + cdID)
                end
            end
            bs.assignedBuffCdIDs = nil
        end
    end
end

EllesmereUI.RegisterMigration({
    id          = "cdm_buff_cd_claim_markers",
    scope       = "specProfile",
    description = "Convert collided-buff cooldownID claims (bs.assignedBuffCdIDs, a side-table with no order) into cd-claim markers stored inside assignedSpells, so a claimed slot gets a real position and can be drag-reordered like any other tracked buff.",
    body = function(ctx)
        EllesmereUI.MigrateCdmBuffCdClaims(ctx.specProfile)
    end,
})

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EllesmereUI" then return end
    self:UnregisterEvent("ADDON_LOADED")

    ---------------------------------------------------------------------------
    --  Boot sequence (runs at parent ADDON_LOADED, before child addons init)
    --  The legacy beta-wipe (PerformResetWipe/StampResetVersion) has been
    --  removed entirely -- it was the nuclear _resetVersion purge whose
    --  fresh-vs-old heuristic was fragile (and looped on standalone renames).
    --  Only the registered-migration runner remains.
    --
    --  RunRegisteredMigrations: runs every migration registered via
    --  EllesmereUI.RegisterMigration. The runner walks each migration and
    --  iterates the appropriate scope (global/profile/specProfile),
    --  pcall-wrapping each body and stamping per-scope flags on success.
    ---------------------------------------------------------------------------
    EllesmereUI.RunRegisteredMigrations()

    -- DM: fontSize was split into leftFontSize + rightFontSize.
    -- DeepMergeDefaults fills new keys with default 11 before the runtime
    -- fallback chain (c.leftFontSize or c.fontSize or 11) can reach the old
    -- value, so existing users who changed fontSize lose their setting.
    -- Copy the old value forward before defaults merge overwrites it.
    if EllesmereUIDB and EllesmereUIDB.profiles then
        for _, profData in pairs(EllesmereUIDB.profiles) do
            local dm = profData.addons
                and profData.addons.EllesmereUIDamageMeters
                and profData.addons.EllesmereUIDamageMeters.dm
            if dm and dm.fontSize and dm.fontSize ~= 11 then
                if dm.leftFontSize == nil then dm.leftFontSize = dm.fontSize end
                if dm.rightFontSize == nil then dm.rightFontSize = dm.fontSize end
            end
        end
    end

    -- Unconditional ghost buff purge: catches imported profiles that
    -- bypass migration flags. Cheap scan, runs once at login.
    if EllesmereUIDB and EllesmereUIDB.profiles then
        for _, profData in pairs(EllesmereUIDB.profiles) do
            local bars = profData.addons
                and profData.addons.EllesmereUICooldownManager
                and profData.addons.EllesmereUICooldownManager.cdmBars
                and profData.addons.EllesmereUICooldownManager.cdmBars.bars
            if bars then
                for i = #bars, 1, -1 do
                    if bars[i].key == "__ghost_buffs" then
                        table.remove(bars, i)
                    end
                end
            end
        end
        for _, specData in ipairs(CollectSpecProfiles(EllesmereUIDB.spellAssignments)) do
            if specData.barSpells then
                specData.barSpells["__ghost_buffs"] = nil
            end
        end
    end

end)

--------------------------------------------------------------------------------
--  RESOURCE BARS: Simple/Advanced -> Spec Overrides migration
--
--  Retires the Resource Bars Advanced per-spec mode (advancedSpecs copy-on-
--  unsync sections) and the per-spec bar enables (health/primary/secondary
--  .disabledSpecs) by converting them into Spec Overrides groups + entries:
--    * one card per advanced spec (named after the spec, class icon), holding
--      one entry per section whose copy DIFFERS from the Simple config --
--      only differing leaf keys become overrides.
--    * one card per per-spec enable ("Class Resource" / "Power Bar" /
--      "Health Bar") for specs disabled via the Simple disabledSpecs picker.
--  Threshold data (thresholdSpecs / tickValues / thresholdFormMode) is NEVER
--  diffed into overrides. When an advanced copy carries threshold edits that
--  differ from Simple, those spec-scoped entries are retargeted to the spec
--  and merged into the Simple threshold list (the threshold system is
--  natively per-spec via entry.specIDs), preserving resolution behavior.
--  The raw advanced data survives in rb.advancedSpecsBackup for later cleanup.
--
--  CRITICAL BASIS: stored profile tables are SPARSE (Lite defaults are merged
--  at NewDB time, not persisted) while unsync copies are FAT snapshots of the
--  merged runtime table. All comparisons therefore run over DEFAULTS-MERGED
--  effective values, and entries store effective scalars -- raw-table diffs
--  mis-classify real edits as drift and strip runtime-injected defaults.
--  This requires the RB DEFAULTS table, so the migration runs from Resource
--  Bars' OnInitialize (which exports EllesmereUI._RBSectionDefaults and then
--  walks every stored profile) AND directly on imported profile data (old
--  export strings), self-guarded by a flag on the RB profile table so all
--  paths are idempotent. With no defaults available (RB addon disabled) the
--  migration is a no-op WITHOUT stamping the flag, so it runs when RB loads.
--------------------------------------------------------------------------------
do
    local PS, FS = "\30", "\31"
    local NIL_SENT = "__SPECOV_NIL__"
    local RB_FOLDER = "EllesmereUIResourceBars"
    local RB_PAGE = "Class, Power and Health Bars"

    -- Static spec map: migration bodies must not call live game APIs.
    local SPEC_INFO = {
        [62]={"Arcane","MAGE"},[63]={"Fire","MAGE"},[64]={"Frost","MAGE"},
        [65]={"Holy","PALADIN"},[66]={"Protection","PALADIN"},[70]={"Retribution","PALADIN"},
        [71]={"Arms","WARRIOR"},[72]={"Fury","WARRIOR"},[73]={"Protection","WARRIOR"},
        [102]={"Balance","DRUID"},[103]={"Feral","DRUID"},[104]={"Guardian","DRUID"},[105]={"Restoration","DRUID"},
        [250]={"Blood","DEATHKNIGHT"},[251]={"Frost","DEATHKNIGHT"},[252]={"Unholy","DEATHKNIGHT"},
        [253]={"Beast Mastery","HUNTER"},[254]={"Marksmanship","HUNTER"},[255]={"Survival","HUNTER"},
        [256]={"Discipline","PRIEST"},[257]={"Holy","PRIEST"},[258]={"Shadow","PRIEST"},
        [259]={"Assassination","ROGUE"},[260]={"Outlaw","ROGUE"},[261]={"Subtlety","ROGUE"},
        [262]={"Elemental","SHAMAN"},[263]={"Enhancement","SHAMAN"},[264]={"Restoration","SHAMAN"},
        [265]={"Affliction","WARLOCK"},[266]={"Demonology","WARLOCK"},[267]={"Destruction","WARLOCK"},
        [268]={"Brewmaster","MONK"},[269]={"Windwalker","MONK"},[270]={"Mistweaver","MONK"},
        [577]={"Havoc","DEMONHUNTER"},[581]={"Vengeance","DEMONHUNTER"},[1480]={"Devourer","DEMONHUNTER"},
        [1467]={"Devastation","EVOKER"},[1468]={"Preservation","EVOKER"},[1473]={"Augmentation","EVOKER"},
    }
    local CLASS_TITLE = {
        WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue",
        PRIEST="Priest", DEATHKNIGHT="Death Knight", SHAMAN="Shaman", MAGE="Mage",
        WARLOCK="Warlock", MONK="Monk", DRUID="Druid", DEMONHUNTER="Demon Hunter",
        EVOKER="Evoker",
    }

    local RB_SECTIONS = {
        { key = "secondary", label = "Class Resource", enableLabel = "Show Class Resource" },
        { key = "primary",   label = "Power Bar",      enableLabel = "Show Power Bar" },
        -- health is OPT-IN at runtime (`hp.enabled and ...`; nil = hidden),
        -- unlike power/secondary (`enabled ~= false`; nil = shown).
        { key = "health",    label = "Health Bar",     enableLabel = "Show Health Bar", optIn = true },
    }

    -- Effective "is this section's bar shown" for a config table, matching
    -- each section's runtime truthiness over the DEFAULTS-MERGED value, with
    -- the per-spec disabledSpecs filter folded in when a spec is given.
    local function SectionEff(sec, t, defs, specID)
        local en = t.enabled
        if en == nil then en = defs and defs.enabled end
        local eff
        if sec.optIn then
            eff = en and true or false
        else
            eff = en ~= false
        end
        if eff and specID and type(t.disabledSpecs) == "table" and t.disabledSpecs[specID] then
            eff = false
        end
        return eff
    end

    -- Threshold-system keys are never diffed into overrides; disabledSpecs
    -- and enabled are folded into effective enables (SectionEff) instead.
    local RB_SKIP_KEYS = {
        thresholdSpecs = true, tickValues = true, thresholdFormMode = true,
        disabledSpecs = true, enabled = true,
    }

    local function DeepCopyT(src)
        if type(src) ~= "table" then return src end
        local out = {}
        for k, v in pairs(src) do out[k] = DeepCopyT(v) end
        return out
    end

    local function DeepEq(a, b)
        if a == b then return true end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        for k, v in pairs(a) do
            if not DeepEq(v, b[k]) then return false end
        end
        for k in pairs(b) do
            if a[k] == nil then return false end
        end
        return true
    end

    -- Walk a section table by a PS-joined relative path, falling back to the
    -- defaults subtree wherever the table side runs out (effective value).
    local function GetPathEff(t, defs, path)
        for seg in string.gmatch(path, "[^\30]+") do
            local tv = (type(t) == "table") and t[seg] or nil
            local dv = (type(defs) == "table") and defs[seg] or nil
            t, defs = tv, dv
            if t == nil and defs == nil then return nil end
        end
        if t ~= nil then return t end
        return defs
    end

    -- Union of differing leaf paths between a Simple section and an advanced
    -- copy, compared over DEFAULTS-MERGED effective values on BOTH sides
    -- (stored Simple is sparse; copies are fat merged snapshots -- raw
    -- comparison mis-reads defaults as user edits and vice versa). Skips
    -- threshold/disabledSpecs/enabled keys, numeric keys, and table shape
    -- mismatches. Emitted leaves may involve nil ONLY when neither side nor
    -- the defaults define the key's counterpart -- those keys are inline-
    -- fallback keys the renderers already tolerate as absent.
    local function DiffSection(simple, copy, defs, prefix, out)
        simple = type(simple) == "table" and simple or {}
        copy = type(copy) == "table" and copy or {}
        defs = type(defs) == "table" and defs or {}
        local keys = {}
        for k in pairs(simple) do keys[k] = true end
        for k in pairs(copy) do keys[k] = true end
        for k in pairs(defs) do keys[k] = true end
        for k in pairs(keys) do
            if type(k) ~= "number" and not RB_SKIP_KEYS[k] then
                local sv, cv, dv = simple[k], copy[k], defs[k]
                local effS = (sv == nil) and dv or sv
                local effC = (cv == nil) and dv or cv
                local path = prefix and (prefix .. PS .. tostring(k)) or tostring(k)
                if type(effS) == "table" and type(effC) == "table" then
                    DiffSection(
                        type(sv) == "table" and sv or nil,
                        type(cv) == "table" and cv or nil,
                        type(dv) == "table" and dv or nil,
                        path, out)
                elseif type(effS) ~= "table" and type(effC) ~= "table"
                   and effS ~= effC then
                    out[path] = true
                end
            end
        end
    end

    -- Q1-A threshold merge: make the spec resolve in the SIMPLE list exactly
    -- as it did in the advanced copy. The copy's entries matching the spec
    -- (explicit or All-Specs) are retargeted to specIDs={spec} and inserted
    -- at the FRONT of the Simple list in resolver tier order (spec+talent,
    -- spec plain, all+talent, all plain); the spec is stripped from
    -- pre-existing Simple entries so nothing else can match it.
    local function MergeThresholds(simpleSec, copySec, specID, backup)
        local cList = copySec.thresholdSpecs
        if type(cList) ~= "table" or #cList == 0 then return end
        if DeepEq(cList, simpleSec.thresholdSpecs) then return end
        if copySec.thresholdFormMode or simpleSec.thresholdFormMode then
            -- Form-mode thresholds resolve by druid form, not spec; a per-spec
            -- retarget cannot represent them. Keep them in the backup only.
            backup.thresholdFormMergeSkipped = true
            return
        end
        local specTalent, specPlain, allTalent, allPlain = {}, {}, {}, {}
        for _, entry in ipairs(cList) do
            if type(entry) == "table" and type(entry.specIDs) == "table" then
                local mSpec, mAll = false, false
                for _, sid in ipairs(entry.specIDs) do
                    if sid == specID then mSpec = true end
                    if sid == 0 then mAll = true end
                end
                if mSpec or mAll then
                    local cp = DeepCopyT(entry)
                    cp.specIDs = { specID }
                    local bucket
                    if entry.talentSpellID then
                        bucket = mSpec and specTalent or allTalent
                    else
                        bucket = mSpec and specPlain or allPlain
                    end
                    bucket[#bucket + 1] = cp
                end
            end
        end
        simpleSec.thresholdSpecs = simpleSec.thresholdSpecs or {}
        local target = simpleSec.thresholdSpecs
        -- Strip this spec from pre-existing Simple entries (drop entries that
        -- only served this spec).
        for i = #target, 1, -1 do
            local entry = target[i]
            if type(entry) == "table" and type(entry.specIDs) == "table" then
                local changed = false
                for j = #entry.specIDs, 1, -1 do
                    if entry.specIDs[j] == specID then
                        table.remove(entry.specIDs, j)
                        changed = true
                    end
                end
                if changed and #entry.specIDs == 0 then table.remove(target, i) end
            end
        end
        -- Front-insert retargeted entries in tier order.
        local merged = {}
        for _, bucket in ipairs({ specTalent, specPlain, allTalent, allPlain }) do
            for _, entry in ipairs(bucket) do merged[#merged + 1] = entry end
        end
        for i = #merged, 1, -1 do
            table.insert(target, 1, merged[i])
        end
    end

    --- Migrates one profile root table (EllesmereUIDB.profiles[name] shape:
    --- .addons.EllesmereUIResourceBars + spec-override tables at root).
    function EllesmereUI.MigrateRBAdvancedProfile(prof)
        if type(prof) ~= "table" then return end
        local rb = prof.addons and prof.addons.EllesmereUIResourceBars
        if type(rb) ~= "table" then return end
        if rb._rbAdvMigrated then return end
        -- Defaults are mandatory for effective-value comparison; without them
        -- (RB addon not loaded) do nothing and leave the flag unset so the
        -- migration runs when RB initializes.
        local DEFS = EllesmereUI._RBSectionDefaults
        if type(DEFS) ~= "table" then return end
        rb._rbAdvMigrated = true

        local adv = rb.advancedSpecs
        local activeAdv = {}
        if type(adv) == "table" then
            for _, e in ipairs(adv) do
                if type(e) == "table" and type(e.specID) == "number" and e.enabled ~= false then
                    activeAdv[#activeAdv + 1] = e
                end
            end
        end
        local hasDisabled = false
        for _, sec in ipairs(RB_SECTIONS) do
            local s = rb[sec.key]
            if type(s) == "table" and type(s.disabledSpecs) == "table" and next(s.disabledSpecs) then
                hasDisabled = true
                break
            end
        end
        if #activeAdv == 0 and not hasDisabled and not (type(adv) == "table" and #adv > 0) then
            return   -- nothing to migrate
        end

        prof.specOverrides = prof.specOverrides or {}
        prof.specOverrideGroups = prof.specOverrideGroups or {}
        local store, groups = prof.specOverrides, prof.specOverrideGroups
        local function nextId()
            local id = (prof.specOverrideNextId or 0) + 1
            prof.specOverrideNextId = id
            return id
        end

        local backup = { advancedSpecs = adv, disabledSpecs = {} }

        -- One card per advanced spec (created lazily).
        local specCards = {}
        local function SpecCard(specID)
            local g = specCards[specID]
            if not g then
                local info = SPEC_INFO[specID]
                local name
                if info then
                    name = info[1] .. " - " .. (CLASS_TITLE[info[2]] or info[2])
                else
                    name = "Spec " .. tostring(specID)
                end
                g = {
                    id = nextId(),
                    name = name,
                    icon = info and { kind = "class", key = info[2] } or nil,
                    specs = { specID },
                }
                specCards[specID] = g
                groups[#groups + 1] = g
            end
            return g
        end

        for _, sec in ipairs(RB_SECTIONS) do
            local simple = rb[sec.key]
            if type(simple) == "table" then
                local defs = type(DEFS[sec.key]) == "table" and DEFS[sec.key] or {}
                local enabledFkey = RB_FOLDER .. FS .. sec.key .. PS .. "enabled"
                local simpleEff = SectionEff(sec, simple, defs)

                -- 1) Threshold merges + per-spec diffs (defaults-merged)
                local union = {}
                local copyBySpec = {}
                local specsWithDiffs = {}
                for _, e in ipairs(activeAdv) do
                    local copy = e[sec.key]
                    if type(copy) == "table" then
                        MergeThresholds(simple, copy, e.specID, backup)
                        copyBySpec[e.specID] = copy
                        local out = {}
                        DiffSection(simple, copy, defs, nil, out)
                        for path in pairs(out) do
                            union[path] = true
                            specsWithDiffs[e.specID] = true
                        end
                    end
                end

                -- 2) Effective enables: advanced copies fold their own enabled
                --    + disabledSpecs; Simple disabledSpecs cover non-copy specs.
                local effEnable = {}
                for specID, copy in pairs(copyBySpec) do
                    local eff = SectionEff(sec, copy, defs, specID)
                    if eff ~= simpleEff then
                        effEnable[specID] = eff
                        specsWithDiffs[specID] = true
                    end
                end
                local dsSpecs = {}
                local ds = simple.disabledSpecs
                backup.disabledSpecs[sec.key] = ds
                if type(ds) == "table" then
                    for specID, on in pairs(ds) do
                        if on and type(specID) == "number" and not copyBySpec[specID] and simpleEff then
                            effEnable[specID] = false
                            dsSpecs[#dsSpecs + 1] = specID
                        end
                    end
                end
                table.sort(dsSpecs)
                if next(effEnable) then union["enabled"] = true end

                -- 3) Spec-card entries: full union, values for EVERY copy-
                --    holding spec (order-independent for shared keys), plus
                --    partial enabled-only maps for enable-card specs.
                if next(union) then
                    local default = {}
                    for path in pairs(union) do
                        local v = GetPathEff(simple, defs, path)
                        local fkey = RB_FOLDER .. FS .. sec.key .. PS .. path
                        default[fkey] = (v == nil or type(v) == "table") and NIL_SENT or v
                    end
                    local valuesBySpec = {}
                    for specID, copy in pairs(copyBySpec) do
                        local m = {}
                        for path in pairs(union) do
                            local v = GetPathEff(copy, defs, path)
                            local fkey = RB_FOLDER .. FS .. sec.key .. PS .. path
                            m[fkey] = (v == nil or type(v) == "table") and NIL_SENT or v
                        end
                        if union["enabled"] then
                            -- effective enable (section truthiness + the
                            -- copy's own disabledSpecs folded in)
                            m[enabledFkey] = SectionEff(sec, copy, defs, specID)
                        end
                        valuesBySpec[specID] = m
                    end
                    for _, specID in ipairs(dsSpecs) do
                        valuesBySpec[specID] = { [enabledFkey] = false }
                    end

                    for specID in pairs(specsWithDiffs) do
                        if copyBySpec[specID] then
                            local g = SpecCard(specID)
                            local entry = {
                                label = sec.label,
                                crumb = "Resource Bars  >  " .. RB_PAGE,
                                module = RB_FOLDER,
                                page = RB_PAGE,
                                group = g.id,
                                values = { default = DeepCopyT(default) },
                            }
                            for sID, m in pairs(valuesBySpec) do
                                entry.values[sID] = DeepCopyT(m)
                            end
                            store[#store + 1] = entry
                        end
                    end

                    -- 4) Enable card for Simple disabledSpecs specs.
                    if #dsSpecs > 0 then
                        local g = {
                            id = nextId(),
                            name = sec.label,
                            icon = { kind = "multi" },
                            specs = dsSpecs,
                        }
                        groups[#groups + 1] = g
                        local entry = {
                            label = sec.enableLabel,
                            crumb = "Resource Bars  >  " .. RB_PAGE,
                            module = RB_FOLDER,
                            page = RB_PAGE,
                            group = g.id,
                            values = { default = { [enabledFkey] = default[enabledFkey] } },
                        }
                        -- every diverging spec gets its effective value so
                        -- apply order over the shared key can never clobber
                        for specID, eff in pairs(effEnable) do
                            entry.values[specID] = { [enabledFkey] = eff }
                        end
                        store[#store + 1] = entry
                    end
                end

                simple.disabledSpecs = nil
            end
        end

        -- 5) Backup + strip the retired mechanisms.
        rb.advancedSpecsBackup = backup
        rb.advancedSpecs = nil
        rb.advancedSelectedSpec = nil
        rb.barDisplayMode = nil
    end
end

-- NOTE: deliberately NOT registered with the early migration runner -- the
-- comparison needs Resource Bars' DEFAULTS table, which only exists once the
-- RB addon loads. RB's OnInitialize exports EllesmereUI._RBSectionDefaults
-- and then invokes MigrateRBAdvancedProfile for every stored profile; the
-- profile import paths call it directly for imported data.
