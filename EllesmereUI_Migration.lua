if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_Migration.lua -- loaded after EllesmereUI_Lite.lua, before
--  EllesmereUI_Profiles.lua; runs at ADDON_LOADED for "EllesmereUI" (before
--  child addons init). Legacy migrations removed: the beta-exit wipe (reset
--  version 5) guarantees a clean slate for every user.
--------------------------------------------------------------------------------

local floor = math.floor

--- Round all width/height values in a table to whole pixels. Call from each child
--- addon's OnInitialize after its DB loads. keys: field names to round (e.g.
--- {"width", "height"}); tables: profile sub-tables to scan.
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
--  RegisterMigration({id, scope, description, body}) runs a one-time migration
--  reliably across upgrades/characters/profiles/specs. scope picks ctx + flag
--  host: "global" -> ctx.db=EllesmereUIDB (flag on EllesmereUIDB); "profile" ->
--  ctx.profile/profileName (flag on profileData); "specProfile" ->
--  ctx.specProfile/specKey (flag on specProfData) -- all under ._migrations[id].
--  Runner walks ALL profiles/spec profiles each pass. Bodies run in pcall; flag
--  stamps only on success so a failed body retries next session. Only the
--  "early" phase exists (parent ADDON_LOADED, before child addons init).
--
--  RULES: (1) IDs are forever, never change one -- register a new id instead.
--  (2) Bodies must be idempotent (predicate-gated) even with the flag. (3)
--  Don't iterate profiles/specs inside a body, the runner does that. (4) No
--  live game APIs (UnitClass, GetSpecialization, C_CooldownViewer) -- unreliable
--  at "early" phase. (5) Walk raw ctx.profile/ctx.specProfile, never
--  child.db.profile: child addons haven't initialized.
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
        -- Per-profile store: spellAssignments.profiles[name].specProfiles, seeded
        -- from the legacy flat store by cdm_per_profile_spell_store_v1 (registered
        -- first). Flags ride on each specProfData._migrations, carried by seeding.
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

-- Public: run all migrations. Called once from the parent ADDON_LOADED handler.
function EllesmereUI.RunRegisteredMigrations()
    if not EllesmereUIDB then
        -- Fresh install: no SavedVariables yet. Must stamp globals now, not skip --
        -- an unstamped catalog would run the whole chain at next load against
        -- whatever exists by then (e.g. an imported profile), treating current-format
        -- data as legacy (concretely: CDM consolidate/detach would rebuild an
        -- imported spell store, pixel-rounding would floor imported positions/sizes,
        -- the colors seed would replace imported palettes). Profile-scoped stamps
        -- live inside each profile (and ride exports), so they need no genesis pass.
        EllesmereUIDB = {}
        local flags = GetFlagTable(EllesmereUIDB)
        for _, spec in ipairs(_migrations) do
            if spec.scope == "global" then
                flags[spec.id] = true
            end
        end
        return
    end
    for _, spec in ipairs(_migrations) do
        RunMigration(spec)
    end
end

--------------------------------------------------------------------------------
--  Registered migrations
--------------------------------------------------------------------------------

-- Hovercast macro bindings ignored their Friendly/Enemy toggles (filter applied
-- only to spell bindings). Now honored: creation defaults (hoverFriendly=true,
-- hoverEnemy=false) would silently break enemy macros, so seed both flags true
-- on existing bindings to stay unfiltered; toggles apply going forward.
EllesmereUI.RegisterMigration({
    id          = "clickcast_macro_hover_reaction_v1",
    scope       = "profile",
    description = "Keep existing hovercast macro bindings unfiltered now that Friendly/Enemy applies to them",
    body        = function(ctx)
        local rf = ctx.profile.addons and ctx.profile.addons.EllesmereUIRaidFrames
        local cc = rf and rf.clickCast
        if type(cc) ~= "table" then return end
        local function seed(list)
            if type(list) ~= "table" then return end
            for _, b in ipairs(list) do
                if type(b) == "table" and b.type == "macro" and b.hovercast then
                    b.hoverFriendly = true
                    b.hoverEnemy    = true
                end
            end
        end
        seed(cc.globals)
        if type(cc.specs) == "table" then
            for _, list in pairs(cc.specs) do seed(list) end
        end
    end,
})

--------------------------------------------------------------------------------
--  Position snap helpers
--  Used by position_snap_v3 and exposed as EllesmereUI.SnapProfilePositions for
--  profile import. MakeSnappers reads EllesmereUIDB.ppUIScale and
--  GetPhysicalScreenSize() at CALL time (once SavedVariables + screen API are up).
--------------------------------------------------------------------------------

local function MakeSnappers()
    local physH = select(2, GetPhysicalScreenSize())
    local perfect = physH and physH > 0 and (768 / physH) or 1
    local uiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or perfect
    if uiScale <= 0 then uiScale = perfect end
    local onePixel = perfect / uiScale

    local function snap(v)
        if type(v) ~= "number" or v == 0 then return v end
        -- Epsilon-guarded round (matches PP.SnapForES): values a hair off a
        -- half-pixel boundary must snap as at runtime, or frames shift 1px.
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

-- Snap all positions in a single profile data table. Called per profile by the
-- position_snap_v3 migration, and once by profile import.
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

    local cursor = addons.EllesmereUICursor
    if type(cursor) == "table" then
        if cursor.gcd then snapPos(cursor.gcd.pos) end
        if cursor.cast then snapPos(cursor.cast.pos) end
    end
end

-- Expose for profile import
EllesmereUI.SnapProfilePositions = SnapProfilePositions

-- Flattens every per-profile spec-profile table into one array. After seeding
-- (cdm_per_profile_spell_store_v1), CDM data lives at profiles[name].specProfiles,
-- not the flat legacy store -- global-scope bodies call this for LIVE data.
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
--  Registered migrations -- one-time transforms gated by the runner's per-scope
--  flag; bodies must be idempotent. Legacy flag checks bridge old inline
--  migrations and can be dropped once all users have passed through.
--------------------------------------------------------------------------------

-- Registered FIRST (precedes all specProfile migrations). Forks the legacy account-wide
-- CDM store (spellAssignments.specProfiles, shared per spec) into per-profile stores
-- (profiles[name].specProfiles), DeepCopied into every profile so copies own
-- independent CDM data (else deleting a bar in one mutates the shared bucket and wipes
-- the origin). DeepCopy keeps _migrations flags, so specProfile migrations already run
-- don't re-run. Legacy flat table stays as a dormant, unread backup -- distinct from
-- EllesmereUIDB.specProfiles (the spec-to-profile auto-switch map).
--
-- Below: Spec Overrides fresh start wipes groups/value entries/unlock overrides
-- (backend moved to whole-layout LAYERS). RB Advanced output lives there, so an
-- already-migrated profile is RE-ARMED first (restored from
-- rb.advancedSpecsBackup, flag cleared) so RB init rebuilds cards into the clean
-- store same login. Re-running MergeThresholds converges: first-run inserts are
-- spec-only and get stripped before identical re-insertion.
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

    -- Recovery for profiles wiped WITHOUT the re-arm above: cards are gone but the
    -- source sits in rb.advancedSpecsBackup, so re-arm once and RB's init
    -- re-creates them. Guard: only re-arm when the store holds no RB-module
    -- entries, since cards created AFTER the wipe (early runner precedes RB
    -- init) would otherwise get duplicates.
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

-- Captures made before numeric-segment path walkers existed banked NIL sentinels
-- (reads missed numeric bars[i] keys); applying via the FIXED walkers would null
-- live CDM settings on the next spec swap. Drop every CDM-bars capture from both stores.
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

-- The Skyriding HUD sub-DB registers its own folder (EllesmereUIDragonRiding),
-- dodging the BlizzardSkin capture blacklist, so a width-match write could be
-- auto-captured into an unrelated entry; applying it hits a folder with no
-- targeted refresher, so the unmapped-folder fallback escalates every apply
-- into a full RefreshAllAddons (minutes of refresh under spec-change traffic).
-- Folder is now blacklisted; strip its keys from both stores (empty default map = drop whole).
EllesmereUI.RegisterMigration({
    id          = "specov_strip_dragonriding_fkeys_v1",
    scope       = "profile",
    description = "Strip stowaway Dragon Riding fkeys from spec/conditional override stores (unmapped-folder RefreshAllAddons storm).",
    body        = function(ctx)
        local prof = ctx.profile
        if not prof then return end
        local PREFIX = "EllesmereUIDragonRiding\31"
        local function strip(store)
            if type(store) ~= "table" then return end
            for i = #store, 1, -1 do
                local e = store[i]
                local vals = type(e) == "table" and e.values
                if type(vals) == "table" then
                    for _, m in pairs(vals) do
                        if type(m) == "table" then
                            for fkey in pairs(m) do
                                if type(fkey) == "string" and fkey:sub(1, #PREFIX) == PREFIX then
                                    m[fkey] = nil
                                end
                            end
                        end
                    end
                    if type(vals.default) ~= "table" or next(vals.default) == nil then
                        table.remove(store, i)
                    end
                end
            end
        end
        strip(prof.specOverrides)
        strip(prof.condOverrides)
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
        -- Ensure the active/Default profile has a bucket even when db.profiles
        -- lacks it (very early / minimal-state installs).
        seed(db.activeProfile or "Default")
        sa._perProfileSeeded = true
    end,
})

-- Consolidates auto-seeded per-profile CDM buckets into spell LAYOUTS: collapses
-- identical duplicates into one, keeps distinct setups as their own layouts,
-- backs up originals (seeding copied one CDM setup into every profile, else
-- users would see a redundant layout each). Only auto-seeded buckets (no
-- `meta`) are touched; user-created/imported layouts are left alone.
EllesmereUI.RegisterMigration({
    id          = "cdm_consolidate_profile_layouts_v1",
    scope       = "global",
    description = "Collapse identical auto-seeded per-profile CDM buckets into single spell layouts; keep distinct ones; dormant backup at spellAssignments._preConsolidateBackup.",
    body        = function(ctx)
        local db = ctx.db
        local sa = db and db.spellAssignments
        if not sa or type(sa.profiles) ~= "table" then return end
        local DeepCopy = EllesmereUI._DeepCopy or (EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy)

        -- Deep value-equality IGNORING "_"-prefixed bookkeeping keys (e.g.
        -- _migrations), so copies differing only in flags count as identical.
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

        -- Auto-seeded buckets have no `meta`; only they are consolidation candidates.
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

        -- Active profile first so its name is the kept representative for the live
        -- setup; the rest alphabetically for determinism.
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

        -- Active layout is remembered PER EUI PROFILE: point each profile at the
        -- surviving layout holding its own pre-consolidation CDM, so a profile
        -- switch loads that setup. Never clobber a user-set pointer.
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

-- Detaches CDM spell layouts from profiles: the implicit per-profile active-layout
-- map (activeLayoutByProfile) becomes OPT-IN bindings (profileBindings) plus one
-- account-wide active layout. Behavior-identical (profiles stay bound to the
-- layout they used; user detaches by removing bindings). Runs AFTER
-- cdm_consolidate_profile_layouts_v1, inheriting deduped layouts+pointers.
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
        -- Account-wide active = current profile's layout, so the live CDM is
        -- byte-for-byte unchanged here. Fall back to the old global pointer,
        -- then any valid layout.
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
    id          = "friend_notes_wipe_v1",
    scope       = "global",
    description = "Wipe legacy bnetAccountID-keyed friendAssignments and friendNotes (sessions 15-17 rebuild).",
    body = function(ctx)
        -- DESTRUCTIVE (wipes global.friendAssignments + .friendNotes): the
        -- _friendNotesMigrated bridge is critical, a re-run destroys data since.
        if EllesmereUIDB and EllesmereUIDB.global
           and EllesmereUIDB.global._friendNotesMigrated then return end

        local g = ctx.db.global
        if not g then return end

        -- One-time popup flag only if the user actually had group assignments
        -- pre-wipe, so users who never used the feature see no "reset" popup.
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

-- Pixel-perfect snapping splits global (unlock anchors, spec profiles) from
-- per-profile (positions+sizes). Per-profile half runs on every profile incl.
-- future imports; global half keeps its original flag so existing users skip it.
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

        local erb = addons.EllesmereUIResourceBars
        if erb then
            local erbSizeKeys = { "width", "height", "pipWidth", "pipHeight" }
            snapSection(erb.primary, erbSizeKeys)
            snapSection(erb.secondary, erbSizeKeys)
            snapSection(erb.health, erbSizeKeys)
            snapSection(erb.castBar or erb.castbar, erbSizeKeys)
        end

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

        local cdm = addons.EllesmereUICooldownManager
        if cdm then
            snapPosMap(cdm.cdmBarPositions)
            if cdm.cdmBars and cdm.cdmBars.bars then
                for _, bd in ipairs(cdm.cdmBars.bars) do
                    roundFields(bd, { "iconSize", "spacing", "width", "height" })
                end
            end
        end

        local dm = addons.EllesmereUIDamageMeters
        if dm then
            snapPos(dm.unlockPos)
            roundFields(dm, { "dmWidth", "dmHeight" })
        end

        local chat = addons.EllesmereUIChat
        if chat then
            snapPos(chat.unlockPos)
            roundFields(chat, { "chatWidth", "chatHeight" })
        end

        local abr = addons.EllesmereUIAuraBuffReminders
        if abr and abr.display then
            snapPos(abr.display.unlockPos)
            roundFields(abr.display, { "iconSize", "iconSpacing" })
        end
    end,
})

EllesmereUI.RegisterMigration({
    id          = "rf_targeted_spells_bool_to_mode_v1",
    scope       = "profile",
    description = "Convert RaidFrames PARTY Targeted Spells tsEnabled boolean to tsMode (false->never, true->whenHealing; nil leaves the default). Raid is NOT migrated -- it hard-defaults to never.",
    body = function(ctx)
        local rf = ctx.profile.addons and ctx.profile.addons.EllesmereUIRaidFrames
        if type(rf) ~= "table" then return end
        -- Self-gating on the new key: idempotent, never clobbers a user choice.
        if rf.tsMode == nil then
            if rf.tsEnabled == false then rf.tsMode = "never"
            elseif rf.tsEnabled == true then rf.tsMode = "whenHealing" end
            -- tsEnabled == nil: leave unset so DeepMergeDefaults applies the default.
        end
        -- Raid intentionally NOT migrated: tsRaidEnabled ignored, tsRaidMode left
        -- unset so DeepMergeDefaults applies the "never" default.
    end,
})

EllesmereUI.RegisterMigration({
    id          = "nameplates_miniboss_boss_color_split_v1",
    scope       = "profile",
    description = "Split nameplate mini-boss/boss colors: seed the new 'boss' color from the user's existing 'miniboss' color so bosses keep their current color until changed.",
    body = function(ctx)
        -- Self-gating on boss == nil: idempotent, never clobbers a user choice.
        -- Copies only a customized miniboss; unset leaves both to default via
        -- DeepMergeDefaults. Import forward-copies in ApplyProfileData.
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
        -- Self-gating: powerBorderSize of 0 (or absent) is skipped, so this runs
        -- once per profile and never touches a border set after the flag stamps.
        -- Scoped STRICTLY to EllesmereUIUnitFrames -- RaidFrames' own unrelated
        -- powerBorderSize (border already worked) must NOT be zeroed here.
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
    id          = "cdm_pandemic_glow_color_table",
    scope       = "profile",
    description = "Migrate CDM bar flat pandemicR/G/B keys into a pandemicGlowColor table, plus default pandemicGlowStyle.",
    body = function(ctx)
        -- No legacy flag to bridge. Idempotent by predicate: fires only when the
        -- legacy flat keys exist AND pandemicGlowColor is missing.
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
        -- Self-gating via `if not bd.key` -- no-op once every bar has a key. The
        -- round-trip (StripDefaults -> save -> load -> DeepMergeDefaults) restores
        -- identity fields in every normal path (profile switch, import); this pass
        -- is purely one-time recovery for already-broken data.
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
        -- Self-gating via the barType check: a no-op once misc bars are gone.
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        -- Pass 1: remove misc bars (reverse iteration keeps indices valid).
        local miscKeys = {}
        for i = #bars, 1, -1 do
            if bars[i].barType == "misc" then
                miscKeys[bars[i].key] = true
                table.remove(bars, i)
            end
        end

        -- Pass 2: clear anchorTo on bars that referenced a removed misc bar.
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
        -- Self-gating: no-op once no bar holds 'none'. MUST register before
        -- cdm_active_state_per_bar_to_per_icon, which depends on the post-rename
        -- 'hideActive' value.
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
        -- Self-gating: a no-op once no bar carries 'mouseover'.
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
        -- Idempotent: nil to nil. Pure legacy cleanup -- frame-tree serialization
        -- into TBB configs is gone, so no live code writes these fields.
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
        -- Idempotent: removedSpells wiped after run. Skips entirely when no bar has
        -- removedSpells, so cold specs get no empty ghost bar entry -- the runtime
        -- getter creates it on first real write.
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

        local ghostBS = barSpells[GHOST_CD]
        if not ghostBS then
            ghostBS = {}
            barSpells[GHOST_CD] = ghostBS
        end
        if not ghostBS.assignedSpells then ghostBS.assignedSpells = {} end

        local existing = {}   -- dedupe against spells already on the ghost bar
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

-- Inline copy of every race's racial spell IDs (mirrors RACE_RACIALS in the CDM
-- addon). Ghost CD bar cleanup needs this without depending on the CDM child
-- addon (loads after this runner) or per-character _myRacialsSet. New race =
-- update both.
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
        -- Idempotent: junk entries gone after first run. Customs detection is
        -- best-effort -- customs predating bs.customSpellIDs stamping, or tracked
        -- via the now-wiped legacy bs.customSpells, are undetectable and stay on
        -- the hidden ghost bar (cosmetic-only impact).
        local barSpells = ctx.specProfile.barSpells
        if type(barSpells) ~= "table" then return end

        local GHOST_CD   = "__ghost_cd"
        local GHOST_BUFF = "__ghost_buffs"

        local ghostBS = barSpells[GHOST_CD]
        if not (ghostBS and ghostBS.assignedSpells) then return end

        -- Spells currently on real bars + currently stamped as custom.
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
        -- Idempotent (nil to nil). Cold profiles with legacy data LOSE those entries
        -- rather than being auto-ported -- schema has drifted too far for porting to
        -- produce valid entries. Bar comes up with assignedSpells == nil, which
        -- new-spec auto-population fills with defaults.
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
        -- Idempotent: no-op once extra buff bars are gone and main-buffs
        -- assignedSpells is nil. Main "buffs" bar is Blizzard-owned/auto-populated
        -- from the CDM viewer, so it must never carry manual assignedSpells;
        -- extra/custom buff bars (custom_5_1234 etc.) are removed entirely --
        -- list entries AND spell data both go.
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

        -- 2. Walk every spec profile: nil stale main-buffs assignedSpells and
        -- prune orphaned spell data for the deleted extra bars.
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

        -- 3. Wipe the old manual flag bytes: the runner's flag replaces them.
        ctx.db._buffBarMigrationV2Done = nil
        ctx.db._buffsBarCleanupV2      = nil
    end,
})

EllesmereUI.RegisterMigration({
    id          = "cdm_wipe_legacy_glows_tbb_locations",
    scope       = "global",
    description = "Wipe legacy bar glows / TBB / tbbPositions storage locations. The data was moved to per-spec storage in v5.5.7. No live code writes to these locations anymore -- they are dead bytes that the previous inline migration was still trying to copy out.",
    body = function(ctx)
        -- Idempotent (nil=nil). Anything remaining belongs to cold profiles/specs;
        -- active users already ported to per-spec storage. Discriminator is
        -- LOCATION not content: top-level spellAssignments.barGlows and the parent
        -- profile's CDM block are legacy by definition -- live code writes only to
        -- spellAssignments.specProfiles[specKey].X.

        local sa = ctx.db.spellAssignments
        if sa then
            sa.barGlows = nil
        end

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
        -- Idempotent: after the first run no 10[12]_ keys remain. Action bar keys
        -- (1_* through 8_*) and the new cdm_<id> format keys are left alone.
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
        -- Idempotent: IDs/TBB bars gone after first run. customSpellDurations is the
        -- safety guard: a real class spell sharing an ID (e.g. Shaman Heroism 32182)
        -- never carries this stamp since it came from the regular picker, not the
        -- preset adder, so real spells are never collateral. presetVariants wipe is
        -- separate stale-field cleanup; nothing reads it.
        local removedPresets = { [2825] = true, [32182] = true, [80353] = true,
            [264667] = true, [390386] = true, [381301] = true, [444062] = true, [444257] = true, -- Bloodlust variants
            [104316] = true, [265187] = true, [264119] = true, [111898] = true, -- Warlock pets
        }
        local removedPopularKeys = { bloodlust = true, time_spiral = true,
            call_dreadstalkers = true, demonic_tyrant = true,
            summon_vilefiend = true, grimoire_felguard = true }

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
        -- Idempotent: only NEGATIVE ids are removed, so a re-run finds none.
        local sp = ctx.specProfile
        local barSpells = sp and sp.barSpells
        if type(barSpells) ~= "table" then return end

        -- Resolves BUFF bar keys from this profile's bar config (barType); "buffs"
        -- is always seeded even if config is absent. Only buff bars are stripped --
        -- cooldown/utility bars keep legitimate trinket/potion markers.
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
        -- Self-gating: predicate false once targeting anchors are cleared. Buff key
        -- set unions ALL profiles, so inactive-profile buff bars count too.
        local anchors = ctx.db.unlockAnchors
        if not anchors then return end

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
        -- Mixed scope: outer walk is per-profile (cdmBars.bars, gated by the
        -- runner's per-profile flag); inner per-spec-profile walk
        -- (barSpells/spellSettings) is done by the body itself, self-gating via
        -- bd.activeStateAnim="blizzard" after migrating. REQUIRES
        -- cdm_active_state_anim_none_to_hideactive first (renames legacy 'none' to
        -- 'hideActive', which this body matches).
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local cdmBars = cdm and cdm.cdmBars
        local bars = cdmBars and cdmBars.bars
        if type(bars) ~= "table" then return end

        -- Spell store is per-profile (spellAssignments.profiles[name].specProfiles).
        -- Collect buckets directly, not via ns.GetSpecProfiles: CDM hasn't
        -- initialized at early phase, but seeding already ran so buckets exist.
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
                                -- Skip icons with an explicit per-icon active state already set.
                                if not ss.activeSwipeMode and not ss.activeSwipeR then
                                    ss.activeSwipeMode = "none"
                                end
                            end
                        end
                    end
                end
                -- Clear the per-bar setting so re-runs find nothing.
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
        -- Under the unified model EnsureAssignedSpells lazily seeds the buff bar
        -- from live icons, so stale stored data must be cleared to re-seed clean.
        local bs = ctx.specProfile.barSpells
        if not bs then return end
        local buffData = bs["buffs"]
        if buffData and buffData.assignedSpells then
            buffData.assignedSpells = nil
        end
    end,
})

--------------------------------------------------------------------------------
--  Bar Texture -> global setting
--  Bar Texture dropdown writes db.profile.healthBarTexture instead of per-unit
--  keys. Promote first non-"none" texture among player/target/focus (in order)
--  to the global key, then strip per-unit overrides so none shadows it.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "v67_bar_texture_global",
    scope       = "profile",
    description = "Promote per-unit healthBarTexture to a single global profile key.",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end

        local winner   -- first non-"none" override, in canonical order
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
--  Quest Tracker: reset stale enabled=false inherited from Basics.
--  v66_basics_split_data copied the whole questTracker table across; old
--  "enabled" meant "disable the custom overlay" (Blizzard's tracker still
--  showed), but new QT's EvalVisibility reads it as "completely hide the
--  tracker" -- an inherited false hid it with no way back (not exposed).
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
        local oldStyle = np.borderStyle
        if oldStyle == "none" then
            np.showBorder = false
        else
            np.showBorder = true
        end
        np.borderSize = 1
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

EllesmereUI.RegisterMigration({
    id          = "uf_absorb_style_boolean_sweep_v1",
    scope       = "profile",
    description = "Normalise any remaining boolean showPlayerAbsorb to a style string. uf_absorb_style_dropdown_v1 walked a fixed unit list and stamps per profile, so a profile that arrived AFTER it ran -- an import or a preset, both of which inherit the recipient's migration flags -- kept the legacy boolean.",
    body = function(ctx)
        -- Walk every table in the UF blob, not a fixed unit list: the earlier pass
        -- missed unnamed units, and any unit's bad value causes the crash.
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end
        for _, unitCfg in pairs(uf) do
            if type(unitCfg) == "table" then
                local v = unitCfg.showPlayerAbsorb
                if v == true then
                    unitCfg.showPlayerAbsorb = "striped"   -- v1's mapping for true
                elseif v ~= nil and type(v) ~= "string" then
                    unitCfg.showPlayerAbsorb = "none"
                end
            end
        end
    end,
})

-- Remove the ghost buff bar (buff visibility is managed by Blizzard CDM settings): drop
-- the bar entry from all profiles and the spell data from all spec profiles.
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
        -- Existing users with the old toggle ON get both bars set to "right" (look
        -- unchanged); false/absent -> "overlay" default. Idempotent: unset keys only.
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

        for _, unitKey in ipairs({ "target", "focus" }) do
            local s = uf[unitKey]
            if s then
                local cw = s.castbarWidth or 0
                if cw == 0 then
                    s.castbarWidth = s.frameWidth or 181
                end
            end
        end

        -- Default unlock anchors only for cast bars with no position and no anchor.
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
        -- Copies old shared overrides into BOTH new tables so each mini renders
        -- identically. Overwrites unconditionally: totPet only exists pre-split, so
        -- any targettarget/focustarget present are default-merge artifacts (e.g.
        -- an import's DeepMergeDefaults), never user-authored. Deleting totPet
        -- after makes re-runs a no-op regardless of the flag.
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
        -- Simple Debuff Display defaults ON ("left"); renderer reads simple* text
        -- keys, which DeepMergeDefaults fills false/14 on profiles predating them,
        -- so a customized regular size stays stored but unread. Seed simple keys
        -- from regular ones before the merge masks them -- regular defaults
        -- (10/false) are the "was it customized" sentinels, since StripDefaults
        -- nils default-equal values.
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
        -- nil = never touched (old default = disabled): stamp false so the new
        -- nil-means-enabled logic can't flip them on. Explicit values are kept.
        if ctx.db.themedCharacterSheet == nil then
            ctx.db.themedCharacterSheet = false
        end
    end,
})

-------------------------------------------------------------------------------
--  Growth direction independent of anchoring
--  Anchoring no longer clears growDirection; stamp an explicit value on every
--  anchored CDM/AB bar so existing layouts stay visually identical. Anchor side
--  -> growth direction mapping is orientation-aware:
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

        -- CDM bars: always CENTER (nil meant CENTER for CDM), so the explicit stamp
        -- preserves behavior and avoids edge preservation on bars with no growEdge.
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
        -- growEdge promotion is handled by cdm_clear_stale_growedge_v1, run after.

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
-- Converts CDM bar positions from CENTER+growEdge to direct edge format:
-- positions store the growth-edge anchor directly (LEFT for RIGHT-grow etc.) so
-- SetSize preserves the fixed edge with no re-anchoring; growEdge is promoted
-- into the primary fields, everything else stays as-is.
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
                pos.point = ge.anchor
                pos.x = ge.x
                pos.y = ge.y
                pos.growEdge = nil
            elseif ge then
                pos.growEdge = nil   -- incomplete: drop it
            end
        end
    end,
})

-------------------------------------------------------------------------------
-- Replaces the CDM "Anchor First Row" boolean with the rowGrowDirection enum.
-- anchorFirstRow pinned the leading perpendicular edge (TOP horizontal, LEFT
-- vertical), equivalent to "DOWN"/"RIGHT"; unset stays unset (centered growth default).
-------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "cdm_row_grow_direction_v1",
    scope       = "profile",
    description = "Migrate CDM anchorFirstRow booleans to the rowGrowDirection enum.",
    body = function(ctx)
        local cdm = ctx.profile.addons and ctx.profile.addons.EllesmereUICooldownManager
        local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
        if not bars then return end
        for _, bar in ipairs(bars) do
            if bar.anchorFirstRow then
                if bar.rowGrowDirection == nil then
                    bar.rowGrowDirection = bar.verticalOrientation and "RIGHT" or "DOWN"
                end
                bar.anchorFirstRow = nil
            end
        end
    end,
})

-------------------------------------------------------------------------------
-- Migrates per-profile secondary threshold settings into thresholdSpecs:
-- thresholdEnabled becomes an "All Specs" entry carrying existing values; disabled leaves array empty.
-------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "resource_bars_threshold_specs_v1",
    scope       = "profile",
    description = "Migrate secondary threshold settings into per-spec thresholdSpecs entries.",
    body = function(ctx)
        local erb = ctx.profile.addons and ctx.profile.addons.EllesmereUIResourceBars
        local sec = erb and erb.secondary
        if not sec then return end
        if sec.thresholdSpecs then return end   -- already migrated
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
        -- Existing users ONLY: on fresh install/factory reset no profiles exist yet
        -- at early-migration time, so nil here means NEW not "predates the flip" --
        -- without this gate a first install would get Auto Open Containers turned ON.
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

        -- The Bags sync enable lives in the mirror-group reset migration below,
        -- which seeds the Bags group after wiping the old-format sync links.
    end,
})

-- The Bags "Default Open to OneBag" boolean became a three-way "Default Bag Type"
-- dropdown (all / onebag / multibag): seed the new key from the legacy boolean,
-- then drop it. Runs AFTER bags_to_profile_v1 so the legacy key already lives in
-- the per-profile bags table. Imported profiles inherit migration flags and skip
-- this, so ApplyProfileData (EllesmereUI_Profiles.lua) forward-copies the legacy
-- key before DeepMergeDefaults.
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

-- Guardian Druid Ironfur bar ships ON (DEFAULTS.secondary.guardianIronfurBar=true)
-- for new installs; existing users expect no class resource bar, so pin every
-- already-existing profile OFF. Runs at parent ADDON_LOADED BEFORE any child NewDB
-- populates EllesmereUIDB.profiles, so only SavedVariables profiles (existing
-- users) are present; fresh installs have none and inherit ON (global scope runs once).
EllesmereUI.RegisterMigration({
    id          = "resourcebars_guardian_ironfur_existing_off_v1",
    scope       = "global",
    description = "Pin the Guardian Druid Ironfur bar OFF for existing users' profiles; fresh installs and future profiles inherit the new ON default.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end
        for _, profData in pairs(db.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
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

-- Prot Warrior Ignore Pain bar ships ON (DEFAULTS.secondary.protIgnorePainBar=true)
-- for new installs; existing users expect no class resource bar, so pin every
-- already-existing profile OFF. Same mechanism as the Guardian Ironfur migration above.
EllesmereUI.RegisterMigration({
    id          = "resourcebars_protwar_ignorepain_existing_off_v1",
    scope       = "global",
    description = "Pin the Prot Warrior Ignore Pain bar OFF for existing users' profiles; fresh installs and future profiles inherit the new ON default.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end
        for _, profData in pairs(db.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
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

-- Unit Frame cast bars count the spell icon as part of the bar's width by default
-- (*.castbarIconInWidth = true). Existing users expect the icon OUTSIDE the width
-- (to the LEFT), so pin every already-existing profile OFF, same mechanism as the
-- Guardian Ironfur migration. Nameplates have their own setting, NOT touched.
EllesmereUI.RegisterMigration({
    id          = "uf_castbar_icon_in_width_existing_off_v1",
    scope       = "global",
    description = "Pin cast-bar icon-in-width OFF for existing users' Unit Frames profiles; fresh installs and future profiles inherit the new ON default. Nameplates unaffected.",
    body = function(ctx)
        local db = ctx.db
        if not db or not db.profiles then return end
        for _, profData in pairs(db.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
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

-- Profile sync is now two-way mirror groups: a module's sync set is a membership group
-- (configuring profile is written into it) and only members push at logout/switch. Old
-- sets stored receivers only with no record of the sender, so they can't translate
-- reliably and any active profile pushed into them, silently overwriting an unrelated
-- profile. Reset every sync link (profile data untouched); users re-enable via the
-- sidebar sync icons, which write the new format. EXCEPTION: Bags keeps syncing, but
-- ONLY for profiles in the old Bags set -- they already received bags pushes every
-- logout, so mirroring exactly them adds zero new overwrite exposure, while profiles
-- outside it may hold deliberately divergent data. Registered LAST so it runs after the
-- older Bags data-move migration, landing multi-version jumps in the new shape.
EllesmereUI.RegisterMigration({
    id          = "sync_reset_for_mirror_groups_v2",
    scope       = "global",
    description = "Reset all profile sync links for the mirror-group rework (profile data untouched; sync is re-enabled via the module sync icons). The Bags group carries over its previous members only.",
    body = function(ctx)
        local db = ctx.db
        if not db then return end
        -- Capture old Bags membership before wiping; the legacy boolean format
        -- (pre per-profile sets) meant "all profiles".
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

-- Seeds every profile's customColors from the account-wide table so the opt-in
-- "Save Colors Per Profile" mode starts identical everywhere. Global
-- EllesmereUIDB.customColors stays the source of truth while the mode is off.
-- One-time overwrite: prior per-profile snapshots were inert, nothing is lost.
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

-- Secondary Stats + FPS counter moved from the account-wide EllesmereUIDB root
-- into the per-profile QoL blob (EllesmereUIQoL) so they travel with profiles,
-- export/import and module sync (see EllesmereUI.QoLExtrasGet/Set in
-- EllesmereUIQoL.lua). Seeds EVERY existing profile from the old
-- values, DeepCopy so each owns independent color/position tables. Root keys
-- stay as the read-time fallback + dormant backup; per-key nil guard = re-run safe.
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
-- moved from account-wide root into the per-profile fonts DB for export/import +
-- module sync. Seeds the live working fonts table (active profile) AND every
-- EXISTING profile fonts snapshot; profiles with NO snapshot are left untouched
-- (a partial one would reset global font/outline mode next switch; getter
-- fallback covers reads). Root keys stay as that fallback (getters in
-- EllesmereUI.lua) + dormant backup; nil guard = re-run safe.
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
        -- Live working copy = what a full export snapshots via DeepCopy(GetFontsDB()).
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
        -- customTooltips is now tooltip-only, but at migration time still holds the
        -- OLD combined-master value, so seed the split-out keys from it once.
        local master = (db.customTooltips ~= false)
        -- Old game-menu/group-finder defaults ANDed in queue-popup state (nil
        -- queue popup counted as on), matching the live default formula.
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
        -- Dropdown value is the texture KEY string, stored under different fields
        -- per module (healthBarTexture, general.barTexture, castBar.texture, etc).
        -- "kringel-diamonds" appears only as a texture value, so a recursive swap
        -- catches every location.
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
        -- Only profiles that have used the Minimap module migrate; fresh installs
        -- take the new defaults (always/topLeft). The addons key survives the
        -- logout default-strip even when every setting is default, so an
        -- all-default existing user still lands on hover (old behavior). Runs
        -- AFTER v66_basics_split_data, so pre-split data already lives here.
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
        -- Same gate as minimap_coords_mode_position_v1; fresh installs take the new
        -- defaults (inside/inside). Data is default-stripped, so absent keys mean
        -- old defaults: showClock ON, hideZoneText OFF, clockInside ON, zoneInside OFF.
        local emm = ctx.profile.addons and ctx.profile.addons.EllesmereUIMinimap
        if type(emm) ~= "table" then return end
        local mm = emm.minimap
        if type(mm) ~= "table" then
            mm = {}
            emm.minimap = mm
        end
        -- Hidden via the removed Show Blizzard Elements checkboxes wins over any
        -- already-stamped mode.
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
        -- Same gate as the other minimap mode migrations; fresh installs take the
        -- new default (always). Data is default-stripped, so only an explicit
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
--  OLD: barSpells[barKey].spellSettings[sid], bar-scoped -- a spell moved to
--  another bar lost its settings and left an orphan; plus
--  barSpells[barKey]._syncIconSettings (Sync All Bar Buttons stamped one spell's
--  block onto every other spell on the bar).
--
--  NEW: specProf.spellSettingsCD[sid]/.spellSettingsBuff[sid] are per-spell,
--  family-scoped, travel with the spell across bars; barSpells[barKey].barSettings
--  is the per-spec "Apply to Bar" tier (seeded from synced bars); bd.barSpellSettings
--  (profile-level, NOT written here) is "Apply to Bar (All Specs)" and starts empty.
--
--  Faithfulness (nothing changes visually): entries move only when the spell is
--  CURRENTLY assigned to the bar the entry lives on, or not visibly assigned
--  anywhere (hidden spells keep styling for their return); orphans for spells now
--  owned by a DIFFERENT bar are dropped (that spell renders default today, so
--  adopting the orphan would change it); synced bars promote their uniform block
--  to barSettings and drop matching per-spell copies, while a divergent copy is
--  kept as an override with explicit `false` fillers for any seed key it lacks
--  (false is render-equivalent to nil) so the bar tier can't bleed through.
--
--  Shared with profile import so old-format strings transform immediately; the
--  registered migration also covers them next reload (both idempotent).
-------------------------------------------------------------------------------
local function CdmFlatSettingsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

-- Classifies a barSpells bucket key into its settings-family store key.
-- Mirrors the runtime rule (ns.SettingsFamilyKey): only barType "buffs" (and the
-- default "buffs" bar) are buff-family; custom_buff and the ghost bar are not.
-- Stale buckets for deleted bars fall back to a key heuristic -- a miss is inert
-- (entries are orphan candidates at most).
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

-- Relocates HOSTED-buff per-spell settings from the CD family store to the BUFF family
-- store. Hosted buffs (a buff on a CD/utility bar) used to resolve settings through the
-- host bar's family key (CD); they now resolve the frame-keyed BUFF store, so the same
-- spellID's cooldown icon holds independent settings -- without the move, hosted-buff
-- settings silently stop applying. Idempotent: moves only while a CD-store entry exists
-- for a flagged id, never overwriting keys already in the BUFF entry (a cooldown twin
-- under the same id moves too: unsplittable in the old shared-entry shape).
-- assignedSpells conversion (plain id -> hosted marker) is NOT done here: it needs live
-- viewer/catalog data to tell buff and cooldown forms apart, so the options panel
-- normalizes it lazily (EnsureAssignedSpells).
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

-- Converts the per-bar "Custom Active State Decimals" (bd.faDecimals*) into the
-- per-spell Threshold Text settings that replaced it: old toggle drove a
-- 1-decimal countdown (+ optional color) on custom/preset icons' hardcoded
-- timers; new model stores Threshold Seconds/Decimals/Color per spell. Every
-- custom spell/item on an opted-in bar is stamped to render as before:
--  * cd/utility bars: item presets and custom/racial spells stamp the
--    profile-level customActiveStates entry (menu + Fake-Active engine read it).
--    Trinket SLOT presets key off the EQUIPPED item at runtime, stamped only
--    when the inventory API already answers (best effort).
--  * buff-family bars: custom buffs (cast-timer entries / tagged custom ids)
--    stamp the spec BUFF family store; Blizzard-tracked buffs are not stamped
--    (never covered by the old toggle).
-- Old bd.faDecimals* keys are consumed in the same pass. Shared with profile
-- import so old-format strings transform immediately.
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
                                        -- Tagged custom ids, plus racials/injected
                                        -- spells already carrying a user-defined
                                        -- active state.
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

-- ReconcileBuffDisplayOrder auto-resyncs the default buffs bar's displayed order
-- (sd.buffDisplayOrder) to Blizzard's current viewer order unless
-- sd._buffDisplayOrderUserModified is set (only options drag-reorder writes that
-- flag). Before the flag existed, buffDisplayOrder was created solely by a
-- manual drag, so every pre-existing stable-key array IS hand-arranged: stamp
-- the flag so the first live reconcile preserves it instead of Blizzard-sorting.
-- Numeric-format legacy arrays are skipped -- reconcile discards that format
-- outright, so there's no order to preserve. Shared with profile import so
-- orders exported from older builds stay protected.
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

-- M+ Timer Enemy Forces bar shared barTexture/barBgTexture with the main timer
-- bar; it now has its own enemyBarTexture/enemyBarBgTexture. Seeds the new keys
-- from the old shared ones on every existing profile so Forces looks unchanged;
-- fresh installs inherit the "none" default. Runs once, only seeds when the new
-- key is unset, so a later reset is respected.
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
        -- Border Size slider was disabled while attached, so a stored size > 0 with
        -- an attached position is always a leftover from a detached phase, never a
        -- divider the user asked for; clear to default (0=off). Positions other
        -- than above/below are untouched (detached keeps its full border; "none"
        -- renders nothing either way).
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        if type(uf) ~= "table" then return end
        -- Units whose powerPosition DEFAULT is attached ("below"): a missing key
        -- still means attached. Mini frames default to "none" (missing = no border).
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

-- Shared body: converts collided-buff cooldownID claims (bs.assignedBuffCdIDs, an
-- unordered side-table) into cd-claim markers inside assignedSpells. Idempotent:
-- assignedBuffCdIDs cleared after migrating. Also called at profile-import time
-- so old export strings keep their claims. Mirrors ns.CD_CLAIM_MARKER_BASE /
-- ns.CdClaimMarker in the CDM addon (-(3000000000 + cooldownID)); inlined rather
-- than called because CDM loads AFTER the login migration runs.
function EllesmereUI.MigrateCdmBuffCdClaims(specProf)
    local CD_CLAIM_MARKER_BASE = 3000000000
    local barSpells = type(specProf) == "table" and specProf.barSpells
    if type(barSpells) ~= "table" then return end
    for _, bs in pairs(barSpells) do
        if type(bs) == "table" and type(bs.assignedBuffCdIDs) == "table"
           and next(bs.assignedBuffCdIDs) then
            if not bs.assignedSpells then bs.assignedSpells = {} end
            -- Dedup against any marker already present (e.g. an interrupted run).
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

EllesmereUI.RegisterMigration({
    id          = "qol_movement_alert_precision_normalize_v2",
    scope       = "profile",
    description = "Normalize Movement Alert precision to a clean 0 or 1. A legacy numeric-input control could leave a non-binary value -- the string \"1\", or a stored -0 -- that the Show Decimal toggle mishandled and that built an invalid \"%.-0f\" format string. Normalized unconditionally (no type guard) because -0 is a number, so the earlier number-only guard skipped it. Positive -> 1 (decimals on); zero/negative/garbage -> 0 (off).",
    body = function(ctx)
        local qol = ctx.profile.addons and ctx.profile.addons.EllesmereUIQoL
        local ma = qol and qol.movementAlert
        if type(ma) ~= "table" or ma.precision == nil then return end
        ma.precision = (tonumber(ma.precision) or 1) > 0 and 1 or 0
    end,
})

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EllesmereUI" then return end
    self:UnregisterEvent("ADDON_LOADED")

    ---------------------------------------------------------------------------
    --  Boot sequence (runs at parent ADDON_LOADED, before child addons init).
    --  RunRegisteredMigrations walks every registered migration, iterating the
    --  right scope (global/profile/specProfile), pcall-wrapping each body and
    --  stamping per-scope flags on success.
    ---------------------------------------------------------------------------
    EllesmereUI.RunRegisteredMigrations()

    -- DM fontSize split into leftFontSize + rightFontSize. DeepMergeDefaults fills
    -- the new keys with 11 before the runtime fallback (c.leftFontSize or
    -- c.fontSize or 11) can reach the old value, losing a changed fontSize: copy
    -- it forward before the defaults merge overwrites it.
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
--  Retires the RB Advanced per-spec mode (advancedSpecs copy-on-unsync sections)
--  and per-spec bar enables (health/primary/secondary .disabledSpecs), turning
--  them into Spec Overrides groups + entries: one card per advanced spec (spec
--  name, class icon) holding one entry per section whose copy DIFFERS from
--  Simple (only differing leaf keys become overrides), plus one card per
--  per-spec enable ("Class Resource"/"Power Bar"/"Health Bar") for specs
--  disabled via the Simple disabledSpecs picker. Threshold data (thresholdSpecs/
--  tickValues/thresholdFormMode) is NEVER diffed into overrides: differing
--  threshold entries are retargeted to the spec and merged into the Simple list
--  instead (natively per-spec via entry.specIDs), preserving resolution
--  behavior. Raw advanced data survives in rb.advancedSpecsBackup for cleanup.
--
--  CRITICAL BASIS: stored profile tables are SPARSE (Lite defaults merge at
--  NewDB time, not persisted) while unsync copies are FAT snapshots of the
--  merged runtime table, so ALL comparisons run over DEFAULTS-MERGED effective
--  values -- raw-table diffs would mis-classify real edits as drift and strip
--  runtime-injected defaults. That needs the RB DEFAULTS table, so this runs
--  from Resource Bars' OnInitialize (exports EllesmereUI._RBSectionDefaults,
--  then walks every stored profile) AND directly on imported profile data, both
--  self-guarded by a flag on the RB profile table (idempotent). With no
--  defaults available (RB disabled) it's a no-op WITHOUT stamping the flag, so
--  it runs when RB loads.
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

    local DeepCopyT = EllesmereUI.Lite.DeepCopy

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

    -- Union of differing leaf paths between a Simple section and an advanced copy,
    -- compared over DEFAULTS-MERGED effective values on both sides (stored Simple
    -- is sparse, copies are fat merged snapshots; raw comparison would mis-read
    -- defaults as edits). Skips threshold/disabledSpecs/enabled/numeric keys and
    -- table-shape mismatches; an emitted leaf involves nil only when neither side
    -- nor defaults define it (renderers already tolerate that as absent).
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

    -- Threshold merge: makes the spec resolve in the SIMPLE list exactly as it did
    -- in the advanced copy. Copy entries matching the spec (explicit or All-Specs)
    -- are retargeted to specIDs={spec} and front-inserted in resolver tier order
    -- (spec+talent, spec plain, all+talent, all plain); the spec is stripped from
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
        -- Strip this spec from pre-existing Simple entries (dropping any that
        -- served only it).
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
        -- Defaults are mandatory for effective-value comparison: without them (RB
        -- not loaded) do nothing and leave the flag unset so it runs when RB inits.
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

-- Deliberately NOT registered with the early migration runner: comparison needs
-- RB's DEFAULTS table, which exists only once the RB addon loads. RB's
-- OnInitialize exports EllesmereUI._RBSectionDefaults then invokes
-- MigrateRBAdvancedProfile per stored profile; import paths call it direct.

-- Per-character data leaked through shared profiles: the DataBars cross-character gold
-- ledger (addons.EllesmereUIDataBars.characters) and the QoL upgrade calculator's
-- per-character scan state (addons.EllesmereUIQoL.chars) sat at profile scope, so
-- exported profiles carried the sharer's character names, realms and gold. Both stores
-- are account-wide now (EllesmereUIDB.dataBarsGold / .qolUpgradeCalcChars); module init
-- drops the keys from the ACTIVE profile, this sweep drops them from every stored
-- profile (cleanup, not the safety line -- string export paths strip them too).
-- Deliberately DROP rather than merge into the account stores: any profile may be an
-- import with no durable record of that, so merging could copy a stranger's characters
-- into permanent account-wide storage; nothing is lost since each character re-records
-- on login/next scan. Folder literals contain "EllesmereUI", which the standalone
-- packager renames to the build token, matching each build's stored profile keys.
EllesmereUI.RegisterMigration({
    id          = "per_character_data_account_wide_v1",
    scope       = "global",
    description = "Drop leaked per-character data (DataBars gold ledger, QoL upgrade-calc state) from every stored profile; both are account-wide now.",
    body        = function(ctx)
        local db = ctx.db
        if not db or type(db.profiles) ~= "table" then return end
        for _, pd in pairs(db.profiles) do
            local addons = type(pd) == "table" and type(pd.addons) == "table"
                and pd.addons or nil
            if addons then
                local dbars = addons["EllesmereUIDataBars"]
                if type(dbars) == "table" then dbars.characters = nil end
                local qol = addons["EllesmereUIQoL"]
                if type(qol) == "table" then qol.chars = nil end
            end
        end
    end,
})

-- The options panel is pinned to physical pixels (baseScale =
-- GetScreenWidth()/physW), holding a constant physical size that does NOT follow
-- the UI Scale slider. Fine at 1080p, but above it the same pixel count covers
-- far less screen: the panel arrives small and the slider appears to do nothing.
-- New installs seed panelScale from display height in EllesmereUI_Startup.lua;
-- this brings existing displays onto the same value. 1440p is the reference: a
-- panel of H units covers H*panelScale/physH of the screen, so physH/1440
-- reproduces 1440p's screen fraction anywhere (4K seeds 1.5, reads like a 2K
-- monitor). The two halves are deliberately asymmetric:
--   ABOVE 1440p -- ONE-TIME RESET overwriting whatever is stored. The old default
--   (1.0) rendered the panel undersized there, so a raised stored value is a
--   WORKAROUND for that bug, not a preference, and would now be an oversized
--   stale compensation (popups no longer scale quadratically with it).
--   Migrations stamp done and never re-run, so this fires exactly once; anything
--   chosen afterward is kept forever.
--   AT OR BELOW 1440p -- nothing was broken, seed is 1.0 anyway, so a stored
--   value can only be a genuine preference. Left alone, except v1-seed residue
--   (physH/1080): a value matching v1's output ON a save carrying v1's stamp.
EllesmereUI.RegisterMigration({
    id          = "panel_scale_highdpi_reset_v3",
    scope       = "global",
    description = "Reset the options-panel scale on displays above 1440p to the corrected default, and seed it elsewhere.",
    body        = function(ctx)
        local db = ctx.db
        if not db then return end
        local _, physH = GetPhysicalScreenSize()
        if type(physH) ~= "number" or physH <= 0 then return end
        -- Snap BEFORE the reset test: the dropdown offers only fixed steps, so an
        -- off-menu seed (1600p lands on 1.111) would leave the control reading
        -- "Normal (100%)" while the panel renders larger. Testing the SNAPPED
        -- value keeps the reset honest: a display rounding back to 1.00 has
        -- nothing to correct and must not fire the overwrite branch.
        local seeded = math.max(1, math.min(physH / 1440, 2))
        if EllesmereUI.SnapPanelScale then seeded = EllesmereUI.SnapPanelScale(seeded) end

        if seeded > 1 then
            -- Above the reference: one-time reset (see above).
            db.panelScale = seeded
            return
        end

        -- At or below the reference: only fill in an unset/default value, or
        -- clear v1 residue.
        local cur = db.panelScale
        local isDefault = (cur == nil or cur == 1.0)
        local v1Ran = db._migrations and db._migrations.panel_scale_highdpi_seed_v1
        local oldSeed = math.max(1, math.min(physH / 1080, 2))
        local isV1Residue = v1Ran and cur ~= nil and math.abs(cur - oldSeed) < 0.001
        if not isDefault and not isV1Residue then return end
        if seeded ~= (cur or 1.0) then db.panelScale = seeded end
    end,
})

--------------------------------------------------------------------------------
--  Player castbar spell target -> None. The player castbar never rendered the
--  spell target before the display fix (an "and ownerUnit ~= 'player'" guard
--  swallowed it), so any inherited or explicitly-set side would make the text
--  pop in on update. Pin existing profiles to None; the player default is now
--  false too, so only users who opt back in see it.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "uf_player_cast_target_none_v1",
    scope       = "profile",
    description = "Pin the player castbar spell target to None (it never displayed before the fix).",
    body = function(ctx)
        local uf = ctx.profile.addons and ctx.profile.addons.EllesmereUIUnitFrames
        local p = uf and uf.player
        if type(p) == "table" then p.showCastTarget = false end
    end,
})

--------------------------------------------------------------------------------
--  Raid Frames: dispellableDebuff* keys moved party-sync sections
--
--  Their controls are drawn under the DISPELS header but the keys were filed
--  under "debuffDisplay", so on the Party tab they were editable whenever
--  Dispels was unsynced while the write routed through Debuff Display. They now
--  file under "dispels".
--
--  Writing one required BOTH sections custom, but re-syncing DISPELS afterwards
--  only deleted keys mapped to "dispels", so these could survive as a live
--  override under a custom Debuff Display with Dispels synced. Under the new
--  mapping that value would go dormant; the mirror case (dormant under a synced
--  Debuff Display, live once Dispels is custom) would switch on.
--
--  Clear the override whenever its live/dormant state would flip. In the
--  flip-to-live case that preserves exactly what the party renders today; in
--  the flip-to-dormant case the party inherits raid either way, and clearing
--  stops the value reviving later. An override live in BOTH mappings (both
--  sections custom, the normal case) is left untouched.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "rf_dispellable_debuff_party_section_v1",
    scope       = "profile",
    description = "Clear dispellableDebuff* party overrides whose live/dormant state would flip when the keys moved to the Dispels sync section.",
    body = function(ctx)
        local rf = ctx.profile.addons and ctx.profile.addons.EllesmereUIRaidFrames
        if type(rf) ~= "table" then return end
        local ss = type(rf.partySyncSections) == "table" and rf.partySyncSections or nil
        local wasLive    = (ss and ss.debuffDisplay == false) and true or false
        local willBeLive = (ss and ss.dispels       == false) and true or false
        if wasLive == willBeLive then return end
        rf.party_dispellableDebuffLocation      = nil
        rf.party_dispellableDebuffGrowDirection = nil
        rf.party_dispellableDebuffOffsetX       = nil
        rf.party_dispellableDebuffOffsetY       = nil
        rf.party_dispellableDebuffSize          = nil
    end,
})

--------------------------------------------------------------------------------
--  Raid Frames: threatBorderSize moved party-sync sections
--
--  The "Threat Borders" slider is drawn on the Health Bar row but the key was
--  filed under the Indicators party-sync section, so editing it on the Party
--  tab wrote the shared raid value. The key now files under "healthBar", which
--  matches where its control lives.
--
--  Writing party_threatBorderSize through the UI required both sections custom,
--  but the legacy showThreat -> slider conversion writes it directly, bypassing
--  that gate. So the override can be live under one mapping and dormant under
--  the other, in either direction. Clear it whenever that state would flip: in
--  the flip-to-live case that preserves exactly what party renders today, and
--  in the flip-to-dormant case party inherits raid either way while clearing
--  stops the value reviving later. An override live under BOTH mappings (the
--  normal both-custom case) is left untouched.
--------------------------------------------------------------------------------
EllesmereUI.RegisterMigration({
    id          = "rf_threat_border_party_section_v2",
    scope       = "profile",
    description = "Clear a party threat border override whose live/dormant state would flip when threatBorderSize moved to the Health Bar sync section.",
    body = function(ctx)
        local rf = ctx.profile.addons and ctx.profile.addons.EllesmereUIRaidFrames
        if type(rf) ~= "table" then return end
        -- Consume the legacy party conversion HERE. ERF:OnInitialize performs
        -- the same rewrite, but child addons initialize after the parent's
        -- ADDON_LOADED, so deferring to it would let a dormant 0 land after
        -- this body had already decided and stamped. Clearing the flag makes
        -- that later block a no-op; the raid showThreat key is untouched.
        if rf.party_showThreat ~= nil then
            if rf.party_showThreat == false then rf.party_threatBorderSize = 0 end
            rf.party_showThreat = nil
        end
        if rf.party_threatBorderSize == nil then return end
        local ss = type(rf.partySyncSections) == "table" and rf.partySyncSections or nil
        local wasLive    = (ss and ss.indicators == false) and true or false
        local willBeLive = (ss and ss.healthBar  == false) and true or false
        if wasLive ~= willBeLive then
            rf.party_threatBorderSize = nil
        end
    end,
})
