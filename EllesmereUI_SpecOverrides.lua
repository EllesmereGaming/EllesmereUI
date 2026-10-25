if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SpecOverrides.lua
--
--  Spec Overrides ("Editing as"): per-spec-group values for individual
--  settings inside ONE profile, instead of a duplicate profile per spec.
--
--  Model:
--  * SPEC GROUPS ("cards"): named icon'd spec sets (a spec belongs to at most
--    one group). The spec button by the module search bar opens the cards
--    popup: Yourself (default), saved groups, Add New, management list link.
--  * Selecting a card enters "Editing as <group>": the group's stored values
--    swap into the live profile (captured paths only) and the user edits with
--    the REAL options widgets -- full fidelity by construction.
--  * AUTO-CAPTURE: every setting changed during a session is captured. A
--    watcher diffs the addon profiles on a short ticker; writes are attributed
--    to the options slot under the mouse (or whose dropdown / cog popup /
--    color picker is open). Unattributed writes (bar drags, background
--    bookkeeping) are absorbed silently, never captured.
--  * Exiting (Yourself, another card, logout, profile/spec switch) harvests
--    live values of every captured path into ALL member specs, then restores
--    the real spec's values. Values apply per spec via the profile system's
--    save-on-leave / apply-on-enter handler. Stored maps are the source of
--    truth; a /reload mid-edit self-heals via the login apply.
--  * GOLDEN BORDERS: slots with an active override get a 1px gold pixel border
--    on their real options rows, matched by module + element + page + section
--    + slot label.
--  * Management list ("Spec Overrides" tab under Profiles & Presets): per
--    group, each captured setting with Go To Setting / Remove buttons.
--
--  Storage (active profile root; rides export/import):
--    profile.specOverrides       = { { label, slotLabel, crumb, module, page,
--                                      element, section, group = groupId,
--                                      values = { default = { [fkey]=v },
--                                                 [specID] = { [fkey]=v } } } }
--    profile.specOverrideGroups  = { { id, name, icon = {kind, key}, specs } }
--    profile.specOverrideNextId  = counter
--  fkey = folder .. FS .. path; path segments joined with PS (control chars,
--  so keys containing "." can never corrupt a path). NIL_SENT marks "key not
--  present" (a setter that removes its key at the default value).
-------------------------------------------------------------------------------

-- Editing-spec GROUP buckets of the Buff Manager, Debuff Manager and Player
-- Aura Bars pages, in menu order. Names run through L() at build time.
EllesmereUI.SPEC_GROUP_BUCKETS = {
    { key = "allspecs",  name = "All Specs",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
    { key = "nonhealer", name = "All Non Healers/Aug",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
    { key = "tanks",     name = "All Tanks",
        icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
    { key = "dps",       name = "All DPS (Non-Aug)",
        icon = "Interface\\Icons\\Ability_DualWield" },
    { key = "healers",   name = "All Healers/Aug",
        icon = "Interface\\Icons\\Spell_Holy_Renew" },
}
EllesmereUI.SPEC_GROUP_BUCKET_INFO = {}
for _, g in ipairs(EllesmereUI.SPEC_GROUP_BUCKETS) do
    EllesmereUI.SPEC_GROUP_BUCKET_INFO[g.key] = g
end

-- Editing-spec roster: the group buckets, "---a", then every spec in the
-- game as "spec<ID>". lead(values, order, icons) may add entries after the
-- divider and returns a set of specIDs to leave out. Returns fresh tables:
-- values, order, icons, classes (class file per "spec<ID>" key).
-- WoW Forever: All Specs, "---a", then one row per class keyed by the
-- bucket that class edits (foreverKeyFor(classToken); a nil key skips the
-- class). No role buckets there and lead is not called.
function EllesmereUI.BuildSpecBucketRoster(lead, foreverKeyFor)
    local values, order, icons, classes = {}, {}, {}, {}
    if EllesmereUI.IS_FOREVER then
        local all = EllesmereUI.SPEC_GROUP_BUCKET_INFO.allspecs
        values.allspecs = EllesmereUI.L(all.name)
        order[1] = "allspecs"
        icons.allspecs = all.icon
        local list = EllesmereUI.ForeverClasses()
        for i = 1, #list do
            local token = list[i]
            local key = foreverKeyFor and foreverKeyFor(token)
            if key and values[key] == nil then
                if #order == 1 then order[2] = "---a" end
                values[key] = EllesmereUI.ForeverClassName(token)
                order[#order + 1] = key
                icons[key] = EllesmereUI.ForeverClassIcon(token)
                classes[key] = token
            end
        end
        return values, order, icons, classes
    end
    for _, g in ipairs(EllesmereUI.SPEC_GROUP_BUCKETS) do
        values[g.key] = EllesmereUI.L(g.name)
        order[#order + 1] = g.key
        icons[g.key] = g.icon
    end
    order[#order + 1] = "---a"
    local skip = lead and lead(values, order, icons) or {}
    for classID = 1, (GetNumClasses and GetNumClasses() or 0) do
        local className, classFile = GetClassInfo(classID)
        local numSpecs = GetNumSpecializationsForClassID
            and GetNumSpecializationsForClassID(classID) or 0
        for si = 1, numSpecs do
            local specID, specName, _, sIcon = GetSpecializationInfoForClassID(classID, si)
            if specID and not skip[specID] then
                local key = "spec" .. specID
                values[key] = (specName or "") .. " " .. (className or "")
                order[#order + 1] = key
                icons[key] = sIcon
                classes[key] = classFile
            end
        end
    end
    return values, order, icons, classes
end

-- Right-click "Add To" items: the roster minus dividers, the edited bucket
-- (selKey, the source) disabled. foreverKeyFor: see BuildSpecBucketRoster.
function EllesmereUI.SpecBucketMenuItems(selKey, lead, foreverKeyFor)
    local values, order, icons = EllesmereUI.BuildSpecBucketRoster(lead, foreverKeyFor)
    local items = {}
    for i = 1, #order do
        local key = order[i]
        if not key:match("^%-%-%-") then
            items[#items + 1] = {
                key = key, label = values[key], icon = icons[key],
                disabled = key == selKey,
            }
        end
    end
    return items
end

local PS  = "\30"   -- path segment separator
local FS  = "\31"   -- folder/path separator inside an fkey
local NIL_SENT = "__SPECOV_NIL__"

-- Exact border sizes ride a companion key beside a surface's border size key
-- ("<key>Px", see EllesmereUI.BorderPx). An entry that captured a size key
-- captures the companion with it (AutoCapture), so a spec or condition holding
-- only the legacy size also clears an exact size set on the shared baseline
-- (NIL_SENT: no registered default, so the apply writes nil) instead of that
-- size riding along wherever the steps coincide. An entry made before the
-- companion existed gains it only once the profile really has an exact size
-- (PxCo.Pair); a store on a profile without one is never rewritten.
-- One table: this file is local-heavy. Partner() names exactly the size keys
-- that gained a companion (last path segment, Raid Frames party twins
-- included); shared names on solid-only surfaces (a boss powerBorderSize) are
-- harmless, their companion is never read.
local PxCo = {
    keys = {
        borderSize = true, borderThickness = true, bgBorderThickness = true,
        auraBorderSize = true, powerBorderSize = true, customBorderSize = true,
        panelBorderThickness = true, tabBorderThickness = true,
        windowBorderSize = true, iconBorderSize = true,
        hoverBorderSize = true, targetBorderSize = true, borderWidth = true,
        party_borderSize = true, party_hoverBorderSize = true,
        party_targetBorderSize = true, castBorderSize = true,
    },
    memo = {},
}
function PxCo.Partner(fkey)
    if type(fkey) ~= "string" then return nil end
    local p = PxCo.memo[fkey]
    if p == nil then
        local leaf = fkey:match("([^\30\31]+)$")
        p = (leaf and PxCo.keys[leaf]) and (fkey .. "Px") or false
        PxCo.memo[fkey] = p
    end
    return p or nil
end

-- Theme color #c7a65a (antique gold): slot borders and all accent work in the
-- cards popup / creation popup.
local ACCENT_R, ACCENT_G, ACCENT_B = 199/255, 166/255, 90/255
local EDIT_R, EDIT_G, EDIT_B = 1, 0.72, 0.2
local GOLD_R, GOLD_G, GOLD_B = 199/255, 166/255, 90/255

local PROFILES_MODULE = "_EUIProfiles"
-- The management tab under Profiles & Presets. Both override list pages live behind
-- this ONE tab (a segmented toggle picks the builder that renders); every
-- SelectPage target and "am I on the list page?" check uses this constant.
local LIST_PAGE = "Overrides"

-- Modules excluded wholesale: CDM has its own per-spec system; the rest are
-- account/character-level UI (window skins, social, bags, chat, minimap, meters,
-- timers, tracker) where per-spec values make no sense. Enforced on capture
-- (AutoCapture validate + SweepUncaptured), apply (WriteSpec/ WriteDefaultValues) and
-- prune (PruneOrphanEntries strips persisted paths and drops emptied entries).
local FOLDER_BLACKLIST = {
    EllesmereUIBlizzardSkin      = true,
    -- Skyriding HUD's sub-DB (EllesmereUIDragonRidingDB) registers from inside
    -- BlizzardSkin, dodging that blacklist entry; unmapped folders force a full
    -- RefreshAllAddons per write (minutes of refresh after combat spec changes).
    -- Blacklisted here too; a migration strips existing captured entries.
    EllesmereUIDragonRiding      = true,
    EllesmereUIDamageMeters      = true,
    EllesmereUIMythicTimer       = true,
    EllesmereUIQuestTracker      = true,
    EllesmereUIFriends           = true,
    EllesmereUIBags              = true,
    EllesmereUIQoL               = true,
    EllesmereUIAuraBuffReminders = true,
    EllesmereUIForeverEssentials = true,
    -- Each action menu picks its own specs (Assign to Spec) instead.
    EllesmereUIQuickdraw         = true,
    -- A per-character store outside the profiles; each assignment picks its
    -- own spec (Assign For) instead.
    EllesmereUILoadoutManager    = true,
    -- Its settings are look and search filters, not spec choices.
    EllesmereUIGroupFinder       = true,
    -- Its settings live in a store of its own outside the profiles.
    EllesmereUISimpleLootCouncil = true,
    -- Minimap + Chat + CooldownManager ARE override-eligible; their
    -- spell/engine-coupled settings are excluded per-path via
    -- SETTING_BLACKLIST below (CDM spell data itself lives OUTSIDE the profile
    -- at EllesmereUIDB.spellAssignments and is not capturable).
}

-- folder -> global apply-function names (mirrors EllesmereUI.RefreshAllAddons).
-- EVERY override-eligible folder (not in FOLDER_BLACKLIST) MUST have an entry: an
-- unmapped folder falls back to a full RefreshAllAddons, which once recursed from
-- inside a conditional transition and froze the game ("script ran too long").
local REFRESH_FNS = {
    EllesmereUICooldownManager   = { "_ECME_Apply" },
    EllesmereUIMinimap           = { "_EMM_FullRebuildMinimap" },
    EllesmereUIResourceBars      = { "_ERB_Apply" },
    EllesmereUIActionBars        = { "_EAB_Apply" },
    EllesmereUIUnitFrames        = { "_EUF_ReloadFrames", "_EUF_RefreshUnitNames" },
    EllesmereUIRaidFrames        = { "_ERF_RefreshAll" },
    EllesmereUINameplates        = { "_ENP_RefreshAllSettings" },
    EllesmereUIQuestTracker      = { "_EQT_RefreshAll" },
    EllesmereUIChat              = { "_ECHAT_RefreshAll" },
    EllesmereUIFriends           = { "_EFR_ApplyFriends", "_EFR_ProcessFriendButtons", "_EFR_RedecorateTiles" },
    EllesmereUIMythicTimer       = { "_EMT_Apply" },
    EllesmereUIDamageMeters      = { "_EDM_Apply" },
    EllesmereUIDataBars          = { "_EDB_Apply" },
    EllesmereUIQuickdraw         = { "_EQD_Apply" },
    EllesmereUIAuraBuffReminders = { "_EABR_UpdateGroupAuraRegistration", "_EABR_ApplyAllIconBorders", "_EABR_RequestRefresh", "_EABR_ApplyUnlockPos" },
    -- Capture/apply-blacklisted (see FOLDER_BLACKLIST); insurance so a leaked
    -- key can never hit the unmapped-folder fallback's full RefreshAllAddons.
    EllesmereUIDragonRiding      = { "_EDR_Rebuild" },
}

-- Class glyph sprite (toolbar button) + modern class sprite (group icons)
local GLYPH_SPRITE  = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\glyph.tga"
local MODERN_SPRITE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\modern.tga"
-- Generic multi-spec group icon (standalone image, not a sprite)
local MULTISPEC_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\multispec.png"
local CLASS_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS
local CLASS_ORDER = EllesmereUI.CLASS_TOKEN_ORDER
-- Modern role icons (shipped with RaidFrames; loaded by path, no addon dep)
local ROLE_MEDIA = "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\"
local ROLE_ICONS = {
    TANK    = ROLE_MEDIA .. "tank-modern.png",
    HEALER  = ROLE_MEDIA .. "healer-modern.png",
    DAMAGER = ROLE_MEDIA .. "dps-modern.png",
}
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

local L = function(s) return EllesmereUI.L(s) or s end

-- Forward declarations
local RequestGoldWalk -- assigned by EUI_SpecOverrides_Borders.lua
local _editGroup = nil       -- group table ref while "editing as" is active

-------------------------------------------------------------------------------
--  Small utilities
-------------------------------------------------------------------------------
local DeepCopy = EllesmereUI.Lite.DeepCopy

-- WoW Forever reports one spec per class; there the player is the first
-- retail spec of the class (class order) that a group of the active profile
-- holds, else the class's first spec. nil until the client knows its spec.
local function CurrentSpecID()
    local id = EllesmereUI._specID
    if not id or id == 0 then
        EllesmereUI._RefreshSpecID()
        id = EllesmereUI._specID
    end
    if EllesmereUI.IS_FOREVER and id and id ~= 0 then
        return EllesmereUI.SpecFor(id, EllesmereUI._SO_InAnyGroup)
    end
    return (id and id ~= 0) and id or nil
end

local function SpecName(specID)
    -- WoW Forever: a retail spec ID reads "Spec - Class" from the shared spec
    -- table; a WoW Forever spec ID reads as its class.
    if EllesmereUI.IS_FOREVER then
        local token = EllesmereUI.SpecClassOf(specID)
        if token then
            local sn, cn = EllesmereUI.RetailSpecName(specID), EllesmereUI.ForeverClassName(token)
            return sn and (sn .. " - " .. cn) or cn
        end
    end
    -- The by-id lookup is not registered on WoW Forever.
    if not GetSpecializationInfoByID then return "Spec " .. tostring(specID) end
    local _, name, _, _, _, _, className = GetSpecializationInfoByID(specID)
    if name and className then
        -- Title-case is byte-based; only safe on ASCII class names. Localized
        -- clients (koKR and friends) return multibyte names -- mangling the
        -- first byte drops the first character, so leave those untouched.
        if className:find("^%a") then
            className = className:sub(1, 1):upper() .. className:sub(2):lower()
        end
        return name .. " - " .. className
    end
    return name or ("Spec " .. tostring(specID))
end

-------------------------------------------------------------------------------
--  Storage
-------------------------------------------------------------------------------
local function GetProfileRoot()
    return EllesmereUI.GetActiveProfileData()
end

local function GetStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    if not prof.specOverrides and create then prof.specOverrides = {} end
    return prof.specOverrides
end

local function GetGroups(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    if not prof.specOverrideGroups and create then prof.specOverrideGroups = {} end
    return prof.specOverrideGroups
end

local function NextGroupId()
    local prof = GetProfileRoot()
    if not prof then return 1 end
    local id = (prof.specOverrideNextId or 0) + 1
    prof.specOverrideNextId = id
    return id
end

local function GroupById(id)
    for _, g in ipairs(GetGroups() or {}) do
        if g.id == id then return g end
    end
    return nil
end

-- True when the spec belongs to at least one spec override group.
local function SpecInAnyGroup(specID)
    if not specID then return false end
    for _, g in ipairs(GetGroups() or {}) do
        for _, sid in ipairs(g.specs or {}) do
            if sid == specID then return true end
        end
    end
    return false
end

-- CurrentSpecID's WoW Forever predicate (CurrentSpecID is declared above
-- this local), and the current spec for Unlock Mode (loads before this file).
EllesmereUI._SO_InAnyGroup = SpecInAnyGroup
EllesmereUI.SpecOverrides_CurrentSpecID = CurrentSpecID

-- WoW Forever: card tooltip lines for a group. A class held whole reads as
-- the class; a partial class lists its specs; a group holding specs of the
-- player's class but not the one this character uses says so.
function EllesmereUI._SO_ForeverGroupNames(specs, curSpec)
    specs = specs or {}
    local set, out, done = {}, {}, {}
    for _, id in ipairs(specs) do set[id] = true end
    local player = select(2, UnitClass("player"))
    local inactive = false
    for _, id in ipairs(specs) do
        local token = EllesmereUI.SpecClassOf(id)
        local ids = EllesmereUI.ForeverClassSpecIDs(token)
        if not ids then
            out[#out + 1] = SpecName(id)   -- a class WoW Forever lacks
        elseif not done[token] then
            done[token] = true
            local whole = true
            for i = 1, #ids do
                if not set[ids[i]] then whole = false; break end
            end
            if whole then
                out[#out + 1] = EllesmereUI.ForeverClassName(token)
            else
                for i = 1, #ids do
                    if set[ids[i]] then out[#out + 1] = SpecName(ids[i]) end
                end
            end
            if token == player and curSpec and not set[curSpec] then inactive = true end
        end
    end
    if inactive then
        out[#out + 1] = string.format(L("Inactive on WoW Forever: this character uses %s"), SpecName(curSpec))
    end
    return out
end

-- First existing group (creation order) whose member specs hold banked values on
-- the entry. Exits bank into every non-conflicting entry, so entry A can carry
-- group B's values too; if A is deleted the entry RETAGS to a holder instead of
-- being destroyed, or B's overrides and the shared default are lost.
local function EntryHolderGroup(e)
    for _, og in ipairs(GetGroups() or {}) do
        for _, sid in ipairs(og.specs or {}) do
            local mv = e.values and e.values[sid]
            if type(mv) == "table" and next(mv) ~= nil then
                return og
            end
        end
    end
    return nil
end

-- An entry owned by another group whose specs overlap G's is a CONFLICT for the
-- shared spec(s) (that group's values own the setting). Returns the first overlapping specID, or nil.
local function ConflictSpec(entry, group)
    group = group or _editGroup
    if not group or not entry.group or entry.group == group.id then return nil end
    local og = GroupById(entry.group)
    if not og then return nil end
    for _, sid in ipairs(group.specs or {}) do
        for _, osid in ipairs(og.specs or {}) do
            if sid == osid then return sid end
        end
    end
    return nil
end

-- STRANDED: a per-spec value on a group-owned entry whose spec is not a member of
-- the owner and whose every group is conflict-locked against it -- unreachable by
-- any session, yet still applied every boundary, pinning the spec off the shared
-- default. Ungrouped specs aren't stranded (self-heal covers them); legacy entries
-- (group == nil) keep per-spec values by design.
local function SpecStrandedOnEntry(entry, specID)
    if entry.group == nil then return false end
    local owner = GroupById(entry.group)
    if not owner then return false end
    for _, sid in ipairs(owner.specs or {}) do
        if sid == specID then return false end
    end
    local inAnyGroup = false
    for _, g in ipairs(GetGroups() or {}) do
        local hasSpec = false
        for _, sid in ipairs(g.specs or {}) do
            if sid == specID then hasSpec = true; break end
        end
        if hasSpec then
            inAnyGroup = true
            if not ConflictSpec(entry, g) then return false end
        end
    end
    return inAnyGroup
end

-- fkey -> owning entry index (rebuilt whenever entries change)
local _fkeyIndex = nil
local function RebuildFKeyIndex()
    _fkeyIndex = {}
    for _, entry in ipairs(GetStore() or {}) do
        for fkey in pairs(entry.values and entry.values.default or {}) do
            _fkeyIndex[fkey] = entry
        end
    end
end
local function EntryOwning(fkey)
    if not _fkeyIndex then RebuildFKeyIndex() end
    return _fkeyIndex[fkey]
end

-------------------------------------------------------------------------------
--  Live profile access by fkey
-------------------------------------------------------------------------------
local function DBFor(folder)
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg then return nil end
    for _, db in ipairs(reg) do
        if db.folder == folder then return db.profile end
    end
    return nil
end

local function SplitFKey(fkey)
    return fkey:match("^([^\31]+)\31(.*)$")
end

-- True when the fkey's child addon registered its DB this session. A DISABLED
-- module reads nil for every path, so banking it would overwrite real stored data
-- with deletion markers (NIL_SENT) at the next boundary. Every bank must treat
-- "module not loaded" as "unknown right now", never "value removed" (same rule as
-- the unlock registry).
local function FKeyLoaded(fkey)
    local folder = SplitFKey(fkey)
    return folder ~= nil and DBFor(folder) ~= nil
end

-- Single-SETTING exclusions, matched against EVERY path segment of the fkey per
-- folder (covers flat keys, nested maps, whole subtrees). Chat's Sidebar Icons are
-- engine-coupled (icon buttons build at login from these keys; order applies on
-- reload). CDM excludes spell-coupled subtrees (per-spell tiers, active states)
-- and stores owned by the unlock LAYER system (positions, grow).
local SETTING_BLACKLIST = {
    EllesmereUIChat = {
        showFriends = true, showDurability = true, showCopy = true,
        showPortals = true, showVoice = true, showSettings = true,
        showScroll = true, sidebarIconOrder = true,
        foreverBorder = true, -- reload-gated WoW Forever Border Style (latched with the look)
    },
    EllesmereUIMinimap = {
        foreverBorder = true, -- reload-gated WoW Forever Border Style (latched with the look)
        blizzBorder   = true, -- reload-gated Blizzard Style Border Style on WoW Forever (likewise)
    },
    EllesmereUICooldownManager = {
        barSpellSettings   = true,   -- "Apply to Bar (All Specs)" per-spell tier
        customActiveStates = true,   -- per-spell active state rules
        cdmBarPositions    = true,   -- unlock-layer territory
        growDirection      = true,   -- unlock-layer territory
    },
    EllesmereUIRaidFrames = {
        bmIndicators  = true,   -- buff-manager layer territory
        bmSimple      = true,   -- buff-manager layer territory
        bmDisplayMode = true,   -- buff-manager layer territory
        bmIconZoom    = true,   -- buff-manager layer territory
        bm2           = true,   -- buff-manager v2 layer territory
        dmDebuff      = true,   -- debuff-manager layer territory
        partyFrameStyle = true, -- reload-gated Party page Frame Style (latched at load, like the Style flags)
    },
}

-- Only the COMPOUND half of the unified Visibility row is excluded: the mode SET
-- (a table this system cannot bank), the match mode and the option lanes, which
-- only mean anything while they agree with the scalar and which a per-leaf capture
-- can therefore only ever hold part of. The legacy scalar stays capturable on
-- purpose, so Never / Always / a single legacy mode keep overriding exactly as they
-- did before the unified row existed. Only override-ELIGIBLE folders hosting the
-- row are listed; the rest already sit in FOLDER_BLACKLIST above.
local VIS_OV_FOLDERS = {
    "EllesmereUIActionBars", "EllesmereUIChat", "EllesmereUICooldownManager",
    "EllesmereUIDataBars", "EllesmereUIMinimap", "EllesmereUIResourceBars",
    "EllesmereUIUnitFrames",
}

-- visibilityModes covers the mode set and its hide lanes at once: the gate below
-- tests every path segment, so the leaves under it never need naming.
for i = 1, #VIS_OV_FOLDERS do
    local folder = VIS_OV_FOLDERS[i]
    local set = SETTING_BLACKLIST[folder]
    if not set then set = {}; SETTING_BLACKLIST[folder] = set end
    set.visibilityModes = true
    set.visibilityMatch = true
end

-- WoW Forever: the buff clear mark (EllesmereUI_Migration.lua) is bookkeeping,
-- never a setting. The loop above guaranteed the Unit Frames set exists.
if EllesmereUI.FvBW then SETTING_BLACKLIST.EllesmereUIUnitFrames[EllesmereUI.FvBW.KEY] = true end

-- The lanes come from the shared VIS_OPT_KEYS, never a copy, so one added later
-- cannot silently become capturable again. Lazy because this file can load first;
-- the loop above already guaranteed every folder has a set. Idempotent.
local _visLanesDone = false
local function EnsureVisLaneBlacklist()
    if _visLanesDone then return end
    local keys = EllesmereUI.VIS_OPT_KEYS
    if not keys then return end
    for i = 1, #VIS_OV_FOLDERS do
        local set = SETTING_BLACKLIST[VIS_OV_FOLDERS[i]]
        for k = 1, #keys do set[keys[k]] = true end
    end
    _visLanesDone = true
end

-- The one predicate every capture/apply/prune gate uses: folder-blacklisted
-- OR setting-blacklisted. Enforced in BOTH directions plus prune.
local function BlacklistedFKey(fkey)
    EnsureVisLaneBlacklist()
    local folder, path = SplitFKey(fkey)
    if not folder then return false end
    if FOLDER_BLACKLIST[folder] then return true end
    local set = SETTING_BLACKLIST[folder]
    if not set or not path then return false end
    for seg in path:gmatch("[^\30]+") do
        if set[seg] then return true end
    end
    return false
end

-- The blacklisted RF subtrees the Buff/Debuff Manager LAYER system banks wholesale
-- per override group. Blacklisted for the slot engine, but an edit made on those
-- pages has still landed in the edited group's fork, so the capture status must
-- confirm that instead of refusing a write that already happened.
local LAYER_OWNED_SEGS = {
    bmIndicators = "bm", bmSimple = "bm", bmDisplayMode = "bm",
    bmIconZoom = "bm", bm2 = "bm", dmDebuff = "dm",
}
local function LayerOwnedFKey(fkey)
    local folder, path = SplitFKey(fkey)
    if folder ~= "EllesmereUIRaidFrames" or not path then return nil end
    local head, sub = path:match("^([^\30]+)\30?([^\30]*)")
    -- bm2's filter library is shared profile-wide: _ERF_BM2HarvestFork banks
    -- specs + seeded only, so a filter edit is NOT scoped to the fork.
    if head == "bm2" and sub == "filters" then return nil end
    return LAYER_OWNED_SEGS[head or ""]
end

-- Width/height-match ownership for module size keys: a size key whose unlock
-- element is a match CHILD is written by the match engine (propagation persists
-- the matched size on every target resize, unlock open or closed), so a captured
-- VALUE is a stale copy under some other layer's link set -- applying/banking it
-- fights the engine ("bar reverts to a stale width"). Skipped at APPLY time
-- (WriteSpecValues/WriteDefaultValues/conditional overlay) and BANK time
-- (HarvestDefaults, unlock-session SnapCommit) whenever a live match link exists,
-- checked against the account-global link tables ApplyLayer swaps to the active
-- layer's set. Static map, Resource Bars only; the GCD bar's setters swap dims by
-- orientation, so either link kind owns both of its keys.
local MATCH_OWNED_FKEYS = {
    ["EllesmereUIResourceBars\31health\30width"]        = { elem = "ERB_Health",        dim = "w" },
    ["EllesmereUIResourceBars\31health\30height"]       = { elem = "ERB_Health",        dim = "h" },
    ["EllesmereUIResourceBars\31primary\30width"]       = { elem = "ERB_Power",         dim = "w" },
    ["EllesmereUIResourceBars\31primary\30height"]      = { elem = "ERB_Power",         dim = "h" },
    ["EllesmereUIResourceBars\31secondary\30pipWidth"]  = { elem = "ERB_ClassResource", dim = "w" },
    ["EllesmereUIResourceBars\31secondary\30pipHeight"] = { elem = "ERB_ClassResource", dim = "h" },
    ["EllesmereUIResourceBars\31castBar\30width"]       = { elem = "ERB_CastBar",       dim = "w" },
    ["EllesmereUIResourceBars\31castBar\30height"]      = { elem = "ERB_CastBar",       dim = "h" },
    ["EllesmereUIResourceBars\31gcdBar\30width"]        = { elem = "ERB_GCDBar",        dim = "both" },
    ["EllesmereUIResourceBars\31gcdBar\30height"]       = { elem = "ERB_GCDBar",        dim = "both" },
    ["EllesmereUIResourceBars\31swingTimer\30width"]    = { elem = "ERB_SwingTimer",    dim = "w" },
    ["EllesmereUIResourceBars\31swingTimer\30height"]   = { elem = "ERB_SwingTimer",    dim = "h" },
}

local function MatchOwnedFKey(fkey)
    local info = MATCH_OWNED_FKEYS[fkey]
    if not info then return false end
    if not EllesmereUIDB then return false end
    local dim = info.dim
    if dim ~= "h" then
        local wm = EllesmereUIDB.unlockWidthMatch
        if wm and wm[info.elem] ~= nil then return true end
    end
    if dim ~= "w" then
        local hm = EllesmereUIDB.unlockHeightMatch
        if hm and hm[info.elem] ~= nil then return true end
    end
    -- While a group/cond layer is LIVE the account-global tables hold that layer's
    -- links -- but a key the BASELINE matches is match-owned everywhere: its recorded
    -- default is a match-written artifact (banked under the baseline's link set), and
    -- applying it on a spec whose layer drops the link stomps that layer's stamped
    -- size with a stale number no corrector can fix (e.g. baseline matched Power,
    -- group layer did not; default 360 overwrote the layer's 280). UnlockBaselineLinks
    -- returns nil when live IS baseline (already covered above). Looked up via the
    -- namespace, not a local, because the function is defined in EUI_SpecOverrides_Layers.lua.
    if EllesmereUI.SpecOverrides_UnlockBaselineLinks then
        local _, bw, bh = EllesmereUI.SpecOverrides_UnlockBaselineLinks()
        if bw and dim ~= "h" and bw[info.elem] ~= nil then return true end
        if bh and dim ~= "w" and bh[info.elem] ~= nil then return true end
    end
    return false
end

-- CDM bar-def settings live in an ARRAY (cdmBars.bars[i].*): numeric-path capture
-- is allowed for EXACTLY that subtree. Bars only APPEND; a DELETION shifts later
-- indices, so the delete flow calls SpecOverrides_OnCDMBarsRestructured to drop
-- every capture in the subtree (re-capture beats stomping one bar's override onto another).
local CDM_BARS_PREFIX = "EllesmereUICooldownManager\31cdmBars\30bars\30"
local RAID_SIZE_OV_PREFIX = "EllesmereUIRaidFrames\31raidSizeOverrides\30"
local function NumAllowedFKey(fkey)
    return fkey:sub(1, #CDM_BARS_PREFIX) == CDM_BARS_PREFIX
        or fkey:sub(1, #RAID_SIZE_OV_PREFIX) == RAID_SIZE_OV_PREFIX
end

function EllesmereUI.SpecOverrides_OnCDMBarsRestructured()
    local function sweep(store, rebuild)
        if not store then return end
        local removed = false
        for i = #store, 1, -1 do
            local e = store[i]
            local hit = false
            if e.values and e.values.default then
                for fkey in pairs(e.values.default) do
                    -- CDM bars ONLY: NumAllowedFKey also matches the raid-size tier
                    -- subtree; sweeping on it here would destroy captured raid-size
                    -- overrides whenever a CDM bar is deleted.
                    if fkey:sub(1, #CDM_BARS_PREFIX) == CDM_BARS_PREFIX then hit = true; break end
                end
            end
            if hit then
                table.remove(store, i)
                removed = true
            end
        end
        if removed and rebuild then rebuild() end
    end
    sweep(GetStore(), RebuildFKeyIndex)
    if EllesmereUI._CondOv then
        sweep(EllesmereUI._CondOv.GetStore(), EllesmereUI._CondOv.RebuildIndex)
    end
    RequestGoldWalk()
end

-- Fkey paths store NUMERIC table keys as strings (DiffTables uses tostring(k)):
-- cdmBars.bars[5] has fkey segment "5". Every path walk must convert back or
-- numeric subtrees silently read nil / write string-key garbage. The stored
-- string key wins when it exists (settings tables never mix "5" and 5).
local function SegKey(t, seg)
    if t[seg] ~= nil then return seg end
    local n = tonumber(seg)
    if n ~= nil and t[n] ~= nil then return n end
    return seg
end

local function ReadLive(fkey)
    local folder, path = SplitFKey(fkey)
    local t = folder and DBFor(folder)
    if type(t) ~= "table" then return nil end
    local segs = { strsplit(PS, path) }
    for i = 1, #segs - 1 do
        t = t[SegKey(t, segs[i])]
        if type(t) ~= "table" then return nil end
    end
    return t[SegKey(t, segs[#segs])]
end

--- True when the fkey resolves to a REGISTERED DEFAULT in the owning module's
--- defaults table (same walk as ReadLive, against _profileDefaults). A stored
--- NIL_SENT ("key removed") for such a key is never legitimate: the Lite defaults
--- merge guarantees the key exists live at every login, so honoring the removal
--- strips a key module code reads RAW under the completeness contract (e.g. a
--- NIL_SENT resource-bar text size nilled the live key post-merge and crashed
--- SetFont). Apply sites skip those writes; the next harvest banks live over the
--- marker, so poisoned stores self-heal.
local function HasRegisteredDefault(fkey)
    local folder, path = SplitFKey(fkey)
    if not folder or not path then return false end
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg then return false end
    local t
    for _, db in ipairs(reg) do
        if db.folder == folder then t = db._profileDefaults; break end
    end
    if type(t) ~= "table" then return false end
    local segs = { strsplit(PS, path) }
    for i = 1, #segs - 1 do
        t = t[SegKey(t, segs[i])]
        if type(t) ~= "table" then return false end
    end
    return t[SegKey(t, segs[#segs])] ~= nil
end

local function WriteLive(fkey, v)
    local folder, path = SplitFKey(fkey)
    local t = folder and DBFor(folder)
    if type(t) ~= "table" then return false end
    -- Raid-size tier overrides are the ONE allowlisted subtree whose numeric
    -- segments are DICTIONARY keys (tier 10/15/25/30), not array indices: absent
    -- means "not customized yet", and RF's options UI fabricates sub-tables on
    -- demand too, nil-guarding sparse tier tables so fabricate-and-write is safe.
    local isRaidSizeOv = fkey:sub(1, #RAID_SIZE_OV_PREFIX) == RAID_SIZE_OV_PREFIX
    local segs = { strsplit(PS, path) }
    for i = 1, #segs - 1 do
        local k = SegKey(t, segs[i])
        local nxt = t[k]
        if type(nxt) ~= "table" then
            if v == nil then return false end   -- nothing to remove
            -- NEVER fabricate a container for a purely-numeric segment: it points at
            -- an ARRAY ENTRY (e.g. a CDM bar by index), and if missing, that entry is
            -- gone (deleted bar, different profile after import). Creating it plants
            -- a skeleton "ghost" row that crashes every keyed consumer downstream, so
            -- skip the write. (Raid-size tier keys are exempt -- see isRaidSizeOv.)
            if tonumber(segs[i]) ~= nil and not isRaidSizeOv then return false end
            nxt = {}
            -- A fresh raidSizeOverrides ROOT must carry the offset-scheme markers RF
            -- stamps in _EnsureRaidSizeOverrides, or the next _NormalizeTierOffsetAnchors
            -- pass silently shifts offsets that were never old-scheme.
            if isRaidSizeOv and i == 1 then
                nxt._topLeftAnchored = true
                nxt._cornerAnchored = true
            end
            -- Fabricate under the NUMERIC key (mirrors the leaf write below): RF reads
            -- tiers numerically, so a string-keyed fabrication never renders and
            -- SegKey would prefer the phantom over the real tier forever.
            local n = tonumber(k)
            if type(k) == "string" and n ~= nil then k = n end
            t[k] = nxt
        end
        t = nxt
    end
    local k = SegKey(t, segs[#segs])
    if t[k] == nil and v ~= nil then
        local n = tonumber(k)
        if type(k) == "string" and n ~= nil then k = n end
    end
    t[k] = v
    return true
end

-- Reads a value out of a profiles snapshot (pre-change originals).
local function SnapValue(snap, fkey)
    local folder, path = SplitFKey(fkey)
    local t = folder and snap[folder]
    if type(t) ~= "table" then return nil end
    local segs = { strsplit(PS, path) }
    for i = 1, #segs - 1 do
        t = t[SegKey(t, segs[i])]
        if type(t) ~= "table" then return nil end
    end
    return t[SegKey(t, segs[#segs])]
end

-------------------------------------------------------------------------------
--  Targeted addon refresh (combat-deferred)
-------------------------------------------------------------------------------
local _combatFolders = nil
local SetCombatFolders -- built at the end of this file (combatFoldersSetters)

local function RunRefreshers(folders)
    if InCombatLockdown() then
        if not _combatFolders then SetCombatFolders({}) end
        for f in pairs(folders) do _combatFolders[f] = true end
        return
    end
    local fallback = false
    for f in pairs(folders) do
        local fns = REFRESH_FNS[f]
        if fns then
            for _, name in ipairs(fns) do
                local fn = _G[name]
                if fn then pcall(fn) end
            end
        else
            fallback = true
        end
    end
    if fallback and EllesmereUI.RefreshAllAddons then
        EllesmereUI.RefreshAllAddons()
    end
end

-- Main-chunk locals the EUI_SpecOverrides_*.lua files re-import by name.
-- editGroupSetters and the lists beside it: every file that reads one of
-- these names keeps its own copy and adds a setter here; each place that
-- assigns it writes through the Set<Name> function built below, which runs
-- them all.
-- broken: true while an EUI_SpecOverrides_*.lua file loads; a file that
-- fails leaves it set, and the files behind it return at their first lines.
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
EUI_NS.NewInternals(EUI_NS, "_soInternals", {
    ACCENT_B = ACCENT_B, ACCENT_G = ACCENT_G, ACCENT_R = ACCENT_R,
    BlacklistedFKey = BlacklistedFKey, CLASS_COORDS = CLASS_COORDS, CLASS_ORDER = CLASS_ORDER,
    ConflictSpec = ConflictSpec, CurrentSpecID = CurrentSpecID, DBFor = DBFor,
    DeepCopy = DeepCopy, EDIT_B = EDIT_B, EDIT_G = EDIT_G, EDIT_R = EDIT_R,
    EntryHolderGroup = EntryHolderGroup, EntryOwning = EntryOwning, FKeyLoaded = FKeyLoaded,
    FOLDER_BLACKLIST = FOLDER_BLACKLIST, FS = FS, GetGroups = GetGroups,
    GetProfileRoot = GetProfileRoot, GetStore = GetStore, GLYPH_SPRITE = GLYPH_SPRITE,
    GOLD_B = GOLD_B, GOLD_G = GOLD_G, GOLD_R = GOLD_R, GroupById = GroupById,
    HasRegisteredDefault = HasRegisteredDefault, L = L, LayerOwnedFKey = LayerOwnedFKey,
    LIST_PAGE = LIST_PAGE, MatchOwnedFKey = MatchOwnedFKey, MODERN_SPRITE = MODERN_SPRITE,
    MULTISPEC_ICON = MULTISPEC_ICON, NextGroupId = NextGroupId, NIL_SENT = NIL_SENT,
    NumAllowedFKey = NumAllowedFKey, PROFILES_MODULE = PROFILES_MODULE, PS = PS, PxCo = PxCo,
    ReadLive = ReadLive, RebuildFKeyIndex = RebuildFKeyIndex, ROLE_ICONS = ROLE_ICONS,
    ROLE_ORDER = ROLE_ORDER, RunRefreshers = RunRefreshers, SegKey = SegKey,
    SnapValue = SnapValue, SpecInAnyGroup = SpecInAnyGroup, SpecName = SpecName,
    SpecStrandedOnEntry = SpecStrandedOnEntry, SplitFKey = SplitFKey, WriteLive = WriteLive,
    editGroupSetters = { function(v) _editGroup = v end },
    combatFoldersSetters = { function(v) _combatFolders = v end },
    goldWalkSetters = { function(v) RequestGoldWalk = v end },
    defaultViewSetters = {}, enterSnapSetters = {}, inTransitionSetters = {},
    activeSpecSetters = {}, watchResyncSetters = {}, exitGroupEditSetters = {},
    sweepSetters = {}, teardownSetters = {}, panelShownSetters = {},
    enterDefaultViewSetters = {}, updateIndicatorSetters = {}, refreshCardsSetters = {},
}, {
    SetEditGroup = "editGroupSetters", SetDefaultView = "defaultViewSetters",
    SetEnterSnap = "enterSnapSetters", SetCombatFolders = "combatFoldersSetters",
    SetInTransition = "inTransitionSetters", SetActiveSpec = "activeSpecSetters",
    SetWatchResync = "watchResyncSetters", SetRequestGoldWalk = "goldWalkSetters",
    SetExitGroupEdit = "exitGroupEditSetters", SetSweepUncaptured = "sweepSetters",
    SetTeardownEditSession = "teardownSetters", SetPanelShown = "panelShownSetters",
    SetEnterDefaultView = "enterDefaultViewSetters",
    SetUpdateIndicator = "updateIndicatorSetters", SetRefreshCardsPopup = "refreshCardsSetters",
}, "EUI_NS")
SetCombatFolders = EUI_NS._soInternals.SetCombatFolders
