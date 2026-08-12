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

local PS  = "\30"   -- path segment separator
local FS  = "\31"   -- folder/path separator inside an fkey
local NIL_SENT = "__SPECOV_NIL__"

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
    EllesmereUIFriends           = { "_EFR_ApplyFriends" },
    EllesmereUIMythicTimer       = { "_EMT_Apply" },
    EllesmereUIDamageMeters      = { "_EDM_Apply" },
    EllesmereUIDataBars          = { "_EDB_Apply" },
    EllesmereUIQuickdraw         = { "_EQD_Apply" },
    EllesmereUIAuraBuffReminders = { "_EABR_RequestRefresh", "_EABR_ApplyUnlockPos" },
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

local L = function(s) return EllesmereUI.L and EllesmereUI.L(s) or s end

-- Forward declarations
local ExitGroupEdit, EnterGroupEdit, ShowEditBanner, HideEditBanner, SetEditStatus
local _unlockRoundtrip = nil -- session to restore after an options-entered
                             -- unlock roundtrip: { kind = "spec"|"cond", id = groupId }
local UpdateIndicator, RequestGoldWalk, RefreshCardsPopup, SweepUncaptured
local TeardownEditSession, EnterDefaultView, ExitDefaultView
local EnsurePanelHideHook, PanelShown, ApplyEditOverlay
local _enterSnap = nil       -- profiles snapshot from session start (set by editing-as
                             -- enter flows; baseline for exit-sweep + HarvestGroup revert detection)
local _editGroup = nil       -- group table ref while "editing as" is active
local _defaultView = false   -- panel open in Default Editing Mode: live holds
                             -- the stored DEFAULT values for captured paths

-------------------------------------------------------------------------------
--  Small utilities
-------------------------------------------------------------------------------
local function DeepCopy(src)
    local t = {}
    for k, v in pairs(src) do
        if type(v) == "table" then t[k] = DeepCopy(v) else t[k] = v end
    end
    return t
end

local function CurrentSpecID()
    local id = EllesmereUI._specID
    if not id or id == 0 then
        if EllesmereUI._RefreshSpecID then EllesmereUI._RefreshSpecID() end
        id = EllesmereUI._specID
    end
    return (id and id ~= 0) and id or nil
end

local function SpecName(specID)
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
    return EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
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
    },
}

-- The one predicate every capture/apply/prune gate uses: folder-blacklisted
-- OR setting-blacklisted. Enforced in BOTH directions plus prune.
local function BlacklistedFKey(fkey)
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
    -- namespace, not a local, because the function is defined later in this file.
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

local function RunRefreshers(folders)
    if InCombatLockdown() then
        _combatFolders = _combatFolders or {}
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

-------------------------------------------------------------------------------
--  Harvest / Apply  (save-on-leave, apply-on-enter)
-------------------------------------------------------------------------------
local _inTransition = false   -- suppresses HarvestCurrent between leave & apply
local _activeSpec = nil       -- spec whose values currently sit in the live db
                              -- (ignoring a temporary Editing-as swap)

-- Reads the live value of every captured path into a map.
local function HarvestMap()
    local store = GetStore()
    if not store or #store == 0 then return nil end
    local maps = {}
    for i, entry in ipairs(store) do
        local m = {}
        for fkey in pairs(entry.values.default) do
            if not FKeyLoaded(fkey) then
                -- Disabled child addon: keep the recorded default so the equality
                -- branch retains each spec's stored value instead of banking NIL_SENT over it.
                m[fkey] = entry.values.default[fkey]
            else
                local v = ReadLive(fkey)
                if v == nil then
                    m[fkey] = NIL_SENT
                elseif type(v) == "table" then
                    m[fkey] = entry.values.default[fkey]   -- structure changed; keep default
                else
                    m[fkey] = v
                end
            end
        end
        maps[i] = m
    end
    return maps
end

-- REVERT SEMANTICS shared by the spec-side banks: a value the USER moved back onto
-- the entry's recorded default is a REVERT ("set back to default = no longer an
-- override") and clears instead of storing. CRITICAL: bare equality is NOT proof of
-- a revert -- the default is movable (Default Editing Mode edits rewrite it), and
-- once edited ONTO a group's value every held override compares equal; clearing on
-- equality alone would dissolve overrides one harvest at a time as the next default
-- edit drags them along. HarvestGroup treats equality as a revert ONLY when the
-- session actually changed the value (live differs from the session-start snapshot);
-- Harvest has no session context and never clears a held key on equality alone.
local function Harvest(specID)
    if not specID then return end
    local store = GetStore()
    local maps = HarvestMap()
    if not maps then return end
    -- Per-spec adoption is for GROUP MEMBERS only: an ungrouped spec's live data
    -- mirrors the shared defaults (panel edits go through the Default view), so any
    -- diff here is a foreign write (unlock layer size stamp, deleted-group leftover,
    -- out-of-panel edit) that would plant a permanent self-renewing phantom override.
    -- Ungrouped specs keep their existing stored maps (legacy pre-group data).
    if not SpecInAnyGroup(specID) then return end
    for i, entry in ipairs(store) do
        local m = maps[i]
        local prev = entry.values[specID]
        local has = false
        for fkey, dv in pairs(entry.values.default) do
            if MatchOwnedFKey(fkey) then
                -- Match-owned size keys: live is the match engine's write, never a user
                -- edit; Apply skips them so live permanently diverges from stored.
                -- Banking it would adopt the matched width into every spec map it
                -- touches (store-wide homogenization) -- retain stored verbatim.
                if prev then m[fkey] = prev[fkey] else m[fkey] = nil end
            elseif m[fkey] == dv then
                -- Equal to default is never a revert outside a session (the default
                -- may have moved onto the override); retain the stored value. No
                -- and/or chain: a stored boolean false must survive retention.
                if prev then m[fkey] = prev[fkey] else m[fkey] = nil end
            end
            if m[fkey] ~= nil then has = true end
        end
        entry.values[specID] = has and m or nil
    end
end

-- Garbage-collects fkeys no group map holds a value for (their harvests all
-- diff-cleared as reverts), and entries left with no fkeys. NEVER judges by equality
-- against the default: the default is movable (Default view edits rewrite it), and
-- equality-pruning against a moved default deletes intentional overrides.
local function PruneRedundantValues()
    local store = GetStore()
    if not store then return end
    local changed = false
    for i = #store, 1, -1 do
        local e = store[i]
        local def = e.values and e.values.default
        if def then
            for fkey in pairs(def) do
                local held = false
                for k, m in pairs(e.values) do
                    if k ~= "default" and type(m) == "table" and m[fkey] ~= nil then
                        held = true
                        break
                    end
                end
                if not held then
                    -- GC only when live actually matches the recorded default: a cleared
                    -- holder whose repaint has not landed (spec-nil login window,
                    -- deferred heal apply) still has the override LIVE, and dropping the
                    -- default would orphan it permanently. Blacklisted paths are never
                    -- applied and GC freely; an unloaded module can't be verified and is kept.
                    local canGC = BlacklistedFKey(fkey)
                    if not canGC and FKeyLoaded(fkey) then
                        local dv = def[fkey]
                        if dv == NIL_SENT then dv = nil end
                        local cur = ReadLive(fkey)
                        if type(dv) == "table" or type(cur) == "table" or cur == dv then
                            canGC = true
                        end
                    end
                    if canGC then
                        def[fkey] = nil
                        changed = true
                    end
                end
            end
            if not next(def) then
                table.remove(store, i)
                changed = true
            end
        end
    end
    if changed then
        RebuildFKeyIndex()
        RequestGoldWalk()
    end
end

-- Banks live values into EVERY member spec of a group. Entries owned by a CONFLICTING
-- group (shared specs) are skipped entirely -- those slots are blocked in the UI and
-- the other group's values must survive untouched. Revert detection: a live value
-- equal to the recorded default clears the members' override ONLY when this session
-- moved it there (live differs from the session-start snapshot); merely comparing
-- equal without having moved it retains each member's stored value instead.
local function HarvestGroup(group)
    if not group then return end
    local store = GetStore()
    local maps = HarvestMap()
    if not maps then return end
    for i, entry in ipairs(store) do
        if not ConflictSpec(entry, group) then
            local m = maps[i]
            local preserve
            for fkey, dv in pairs(entry.values.default) do
                if MatchOwnedFKey(fkey) then
                    -- Match-owned size keys never bank FROM live (see Harvest): the
                    -- broadcast below would stamp the match engine's write onto EVERY
                    -- member at once. Route through preserve so each member keeps its own value.
                    preserve = preserve or {}
                    preserve[fkey] = true
                    m[fkey] = nil
                elseif m[fkey] == dv then
                    local s = _enterSnap and SnapValue(_enterSnap, fkey)
                    if type(s) == "table" then s = nil end
                    s = (s == nil) and NIL_SENT or s
                    if not _enterSnap or s == m[fkey] then
                        -- Untouched this session: not a revert. Each member
                        -- keeps its own stored value below.
                        preserve = preserve or {}
                        preserve[fkey] = true
                    end
                    m[fkey] = nil
                end
            end
            for _, specID in ipairs(group.specs or {}) do
                local prev = entry.values[specID]
                local out = next(m) ~= nil and DeepCopy(m) or nil
                if preserve and prev then
                    for fkey in pairs(preserve) do
                        local pv = prev[fkey]
                        if pv ~= nil then
                            out = out or {}
                            out[fkey] = (type(pv) == "table") and DeepCopy(pv) or pv
                        end
                    end
                end
                entry.values[specID] = out
            end
        end
    end
    PruneRedundantValues()
end

-- Raw writer: puts the given spec's stored values into the live profile
-- tables. Returns the set of folders whose values actually changed, or nil.
local function WriteSpecValues(specID)
    local store = GetStore()
    if not store or #store == 0 or not specID then return nil end
    local touched = nil
    for _, entry in ipairs(store) do
        local m = entry.values[specID] or entry.values.default
        for fkey, def in pairs(entry.values.default) do
            -- Apply-side folder blacklist: legacy entries can carry paths into
            -- hands-off addons (CDM runs its own per-spec system; a stale write
            -- re-injects frozen spell data and its unmapped folder forces a full
            -- RefreshAllAddons mid-play). Match-owned keys: the match engine owns
            -- them while a link exists, so stored is a stale copy.
            if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey) then
                local v = m[fkey]
                if v == nil then v = def end
                if v == NIL_SENT then v = nil end
                -- Key-removal markers are honored ONLY for keys with no registered
                -- default: on defaults-backed keys the marker is harvest residue (see
                -- HasRegisteredDefault) and writing nil strips a key consumers read
                -- raw. Skip; live keeps the merged default and the next harvest self-heals.
                local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
                local cur = ReadLive(fkey)
                -- Table values are never written or compared: a stored table
                -- reference NEVER equals live -> phantom "write" plus a full
                -- module refresh on every apply.
                if not nilPoison and type(v) ~= "table" and type(cur) ~= "table" and cur ~= v then
                    if WriteLive(fkey, v) then
                        local folder = SplitFKey(fkey)
                        if folder then
                            touched = touched or {}
                            touched[folder] = true
                        end
                    end
                end
            end
        end
    end
    return touched
end

-- Group variant: seeds from the group's first member spec.
local function WriteGroupValues(group)
    local seed = group and group.specs and group.specs[1]
    if not seed then return nil end
    return WriteSpecValues(seed)
end

-- Default variant: writes the stored DEFAULT values (what specs outside any
-- group use). Powers the panel's Default Editing Mode view.
local function WriteDefaultValues()
    local store = GetStore()
    if not store or #store == 0 then return nil end
    local touched = nil
    for _, entry in ipairs(store) do
        for fkey, def in pairs(entry.values.default) do
            -- Same apply-side blacklist + match-ownership skip as WriteSpecValues.
            if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey) then
                local v = def
                if v == NIL_SENT then v = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues,
                -- plus its table guards: a stored table reference never
                -- equals live, so comparing/writing one registers a phantom
                -- change and forces a full module refresh on every apply.
                local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
                local cur = ReadLive(fkey)
                if not nilPoison and type(v) ~= "table" and type(cur) ~= "table" and cur ~= v then
                    if WriteLive(fkey, v) then
                        local folder = SplitFKey(fkey)
                        if folder then
                            touched = touched or {}
                            touched[folder] = true
                        end
                    end
                end
            end
        end
    end
    return touched
end

-- Banks live values into the entries' DEFAULT maps (Default Editing Mode
-- edits are edits to the shared baseline).
local function HarvestDefaults()
    local store = GetStore()
    local maps = HarvestMap()
    if not maps then return end
    for i, entry in ipairs(store) do
        -- Match-owned size keys never bank FROM live: live holds whatever the
        -- match engine last wrote (it re-pulls and persists on every target
        -- resize, including the Default view's own value writes), never a user
        -- default edit. Keep the recorded default verbatim.
        local m = maps[i]
        local prev = entry.values.default
        for fkey in pairs(m) do
            if MatchOwnedFKey(fkey) then
                if prev ~= nil then m[fkey] = prev[fkey] else m[fkey] = nil end
            end
        end
        entry.values.default = m
    end
    PruneRedundantValues()
end

local function ApplyValuesFor(specID)
    _inTransition = false
    if specID then _activeSpec = specID end
    -- While Editing-as (or the Default view) holds swapped values live, generic
    -- re-applies (e.g. a fallback RefreshAllAddons) must preserve the swap.
    if _editGroup then
        return WriteGroupValues(_editGroup)
    end
    if EllesmereUI._CondOv and EllesmereUI._CondOv._edit then
        -- Editing-as-conditional view: shared defaults with the session group's
        -- values overlaid (forSession: they show even over spec-owned fkeys).
        -- Falling through to WriteSpecValues repaints spec values into the open
        -- session and the exit bank records them as the conditional's edits.
        local touched = WriteDefaultValues()
        local t2 = EllesmereUI._CondOv.WriteValues(EllesmereUI._CondOv._edit.id, true)
        if t2 then
            touched = touched or {}
            for k in pairs(t2) do touched[k] = true end
        end
        return touched
    end
    if _defaultView then
        return WriteDefaultValues()
    end
    return WriteSpecValues(specID)
end

--- Values-only apply, called at the TOP of EllesmereUI.RefreshAllAddons so
--- every profile swap / import picks the current spec's overrides up through
--- the full refresh that follows. No refresh of its own.
function EllesmereUI.SpecOverrides_ApplyValues(specID)
    ApplyValuesFor(specID or _activeSpec or CurrentSpecID())
    -- Unlock layout overrides ride the same hook: stores must hold the current
    -- spec's effective layout before every module refresh that follows. Always
    -- keyed to the REAL spec -- editing-as swaps option values, never layout.
    if EllesmereUI.SpecOverrides_ApplyUnlock then
        EllesmereUI.SpecOverrides_ApplyUnlock(specID or _activeSpec or CurrentSpecID())
    end
    if EllesmereUI.SpecOverrides_ApplyBm then
        EllesmereUI.SpecOverrides_ApplyBm(specID or _activeSpec or CurrentSpecID())
    end
    if EllesmereUI.SpecOverrides_ApplyDm then
        EllesmereUI.SpecOverrides_ApplyDm(specID or _activeSpec or CurrentSpecID())
    end
    -- Conditional value overlay rides last (spec values always win their
    -- own fkeys; the two sets are disjoint by the ownership gate).
    if EllesmereUI._CondOv then EllesmereUI._CondOv.ApplyValues() end
    -- Close the import window (see ImportProfile): this is the first apply on a
    -- session OTHER than the importing one (its runtime flag died at the ReloadUI).
    -- Converge live to the imported store's layer truth exactly once: the exported
    -- blob carries whatever layer was LIVE on the exporter at export time
    -- (SnapshotAllAddons copies stores verbatim), and nothing on the normal login
    -- path re-applies the recipient spec's layer over it (import-tail ApplyLayer's
    -- flush died at the ReloadUI; the plain login apply early-outs on
    -- want == s.active). Forced apply resolves the spec's fork, else the exporter's
    -- true baselineLayout; FlushUnlock's equality guards no-op once blob and bucket
    -- agree, and its pend overlay keeps post-clear boundary banks intent-true until
    -- the flush lands. Clear-first so an apply error can never wedge the window shut.
    if not EllesmereUI._importGuardArmedNow then
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            -- Resolve the spec BEFORE closing the window: a spec-less apply must leave
            -- the flag set (bounded stuck-window, next apply retries) rather than burn
            -- the one-shot converge with nothing to converge to. pcall so a converge
            -- error can't abort the caller's module fan-out (RefreshAllAddons runs
            -- ApplyValues as its first statement).
            local sid = specID or _activeSpec or CurrentSpecID()
            if sid then
                prof._importEstablishPending = nil
                -- One converge serves both windows: the forced apply below
                -- also satisfies a pending reset-pointer converge.
                EllesmereUI._unlockResetConvergePending = nil
                if EllesmereUI.SpecOverrides_ApplyUnlock then
                    pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyBm then
                    pcall(EllesmereUI.SpecOverrides_ApplyBm, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyDm then
                    pcall(EllesmereUI.SpecOverrides_ApplyDm, sid, true)
                end
            end
        end
    end
    -- Reset-pointer converge (see SpecOverrides_UnlockResetActive): a profile
    -- activation restored baseline links and cleared a live layer pointer, but
    -- module elem positions still hold that layer's geometry. A baseline-spec
    -- login early-outs on want == active == nil, leaving the desync for the next
    -- harvest to bank into baselineLayout; one forced apply paints the pointer's
    -- truth instead. Same contract as the import converge (spec resolved before
    -- clearing, clear-first, pcall'd). No ApplyBm -- the BM pointer is never
    -- reset, so it is never lied about.
    if EllesmereUI._unlockResetConvergePending then
        local sid = specID or _activeSpec or CurrentSpecID()
        if sid then
            EllesmereUI._unlockResetConvergePending = nil
            if EllesmereUI.SpecOverrides_ApplyUnlock then
                pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
            end
        end
    end
end

--- Full apply: values + targeted refresh of the touched addons.
--- deferLogin: first-login call -- waits two frames so child addon OnEnable and
--- deferred registrations complete first (mirrors the profile switcher).
function EllesmereUI.SpecOverrides_Apply(specID, deferLogin)
    if deferLogin then
        C_Timer.After(0, function()
            C_Timer.After(0, function() EllesmereUI.SpecOverrides_Apply(specID) end)
        end)
        return
    end
    local touched = ApplyValuesFor(specID)
    if touched then RunRefreshers(touched) end
    -- Unlock layout overrides: a same-profile spec change never runs RefreshAllAddons,
    -- so this is its only unlock apply; on the profile-switch path ApplyValues already
    -- ran it and this repeat is a value-equal no-op.
    if EllesmereUI.SpecOverrides_ApplyUnlock then
        EllesmereUI.SpecOverrides_ApplyUnlock(specID)
    end
    if EllesmereUI.SpecOverrides_ApplyBm then
        EllesmereUI.SpecOverrides_ApplyBm(specID)
    end
    if EllesmereUI.SpecOverrides_ApplyDm then
        EllesmereUI.SpecOverrides_ApplyDm(specID)
    end
    if UpdateIndicator then UpdateIndicator() end   -- passive owner may change
    -- Spec changed with the cards popup open: rebuild so each group's unlock
    -- icon reflects the new spec's membership (the click handler re-checks
    -- membership regardless).
    if RefreshCardsPopup then RefreshCardsPopup() end
    -- Spec changed with the panel open: return it to the Default view.
    if PanelShown and PanelShown() and not _editGroup and not _defaultView
       and EnterDefaultView then
        EnterDefaultView()
    end
    -- Conditional overrides re-arm after every spec transition: the engine
    -- bails while the value system is mid-swap; this is its retry point.
    if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
    -- Import-window close + one-shot layer converge; contract identical to the
    -- copy in SpecOverrides_ApplyValues above.
    if not EllesmereUI._importGuardArmedNow then
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            local sid = specID or _activeSpec or CurrentSpecID()
            if sid then
                prof._importEstablishPending = nil
                -- One converge serves both windows: the forced apply below
                -- also satisfies a pending reset-pointer converge.
                EllesmereUI._unlockResetConvergePending = nil
                if EllesmereUI.SpecOverrides_ApplyUnlock then
                    pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyBm then
                    pcall(EllesmereUI.SpecOverrides_ApplyBm, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyDm then
                    pcall(EllesmereUI.SpecOverrides_ApplyDm, sid, true)
                end
            end
        end
    end
    -- Reset-pointer converge; same contract as the copy above.
    if EllesmereUI._unlockResetConvergePending then
        local sid = specID or _activeSpec or CurrentSpecID()
        if sid then
            EllesmereUI._unlockResetConvergePending = nil
            if EllesmereUI.SpecOverrides_ApplyUnlock then
                pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
            end
        end
    end
end

--- Spec transition entry point, called by the profile system's spec handler
--- BEFORE any spec-profile switch.
function EllesmereUI.SpecOverrides_OnSpecChanged(oldSpecID, newSpecID)
    -- Unlock layout: bank live into the outgoing layer FIRST, while live still
    -- belongs to the old state (the new spec's values/refreshers have not run
    -- yet). The per-spec layer apply rides ApplyUnlock later.
    if EllesmereUI.SpecOverrides_HarvestUnlockLayout then
        EllesmereUI.SpecOverrides_HarvestUnlockLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestBmLayout then
        EllesmereUI.SpecOverrides_HarvestBmLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestDmLayout then
        EllesmereUI.SpecOverrides_HarvestDmLayout()
    end
    -- An editing-as-conditional session banks and ends here; the transition
    -- re-establishes canonical live itself (noRestore).
    if EllesmereUI._CondOv and EllesmereUI._CondOv.ExitEdit then
        EllesmereUI._CondOv.ExitEdit(true)
    end
    if _editGroup then
        -- Bank unsaved Editing-as changes (plus a sweep of uncaptured writes)
        -- to the group's members. Live holds group values, so the outgoing
        -- spec must NOT be harvested from it.
        local g = _editGroup
        _editGroup = nil
        if SweepUncaptured then SweepUncaptured(g) end
        HarvestGroup(g)
        if TeardownEditSession then TeardownEditSession() end
    elseif _defaultView then
        -- Live holds the DEFAULT values; bank them there. The outgoing spec's
        -- own values were banked when the view was entered.
        _defaultView = false
        HarvestDefaults()
        if UpdateIndicator then UpdateIndicator() end
    elseif oldSpecID and oldSpecID ~= newSpecID then
        Harvest(oldSpecID)
    end
    _activeSpec = newSpecID
    _inTransition = true
end

--- Harvest the live values of the spec currently in the live db. Called on
--- logout and before manual profile switches/imports/exports so normal
--- options-page edits are never lost. An active Editing-as session is banked
--- to its group and ended, and canonical live data restored (the caller is
--- about to snapshot or switch).
function EllesmereUI.SpecOverrides_HarvestCurrent()
    if _inTransition then return end
    -- Unlock layout: bank live into its current layer (callers are about to
    -- snapshot or swap stores).
    if EllesmereUI.SpecOverrides_HarvestUnlockLayout then
        EllesmereUI.SpecOverrides_HarvestUnlockLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestBmLayout then
        EllesmereUI.SpecOverrides_HarvestBmLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestDmLayout then
        EllesmereUI.SpecOverrides_HarvestDmLayout()
    end
    -- An editing-as-conditional session: bank it and end it. ExitEdit restores
    -- canonical live, but with the panel shown its tail re-enters the Default view,
    -- which banks the real spec's values and swaps the DEFAULTS live -- harvesting the
    -- spec from that state diff-clears its entire map (every value equals its default).
    -- Fall through to the _defaultView branch below. noRecheck: shared banking plumbing
    -- (logout, export, profile switch), never "the user finished editing". A
    -- conditional transition resolved here would run ApplyUnlock, whose flush is two
    -- frames out -- at LOGOUT it never lands, leaving the advanced active pointer to
    -- early-out the next login's apply with module position stores still on the OLD
    -- layer. Values still bank (Cond.HarvestEdit inside); only the flip waits.
    if EllesmereUI._CondOv and EllesmereUI._CondOv._edit then
        EllesmereUI._CondOv.ExitEdit(nil, true)
        if not _defaultView then
            Harvest(_activeSpec or CurrentSpecID())
            return
        end
    end
    -- Conditional values bank ONLY over canonical live data: in the session
    -- branches below this runs AFTER WriteSpecValues restores the real values.
    -- Banking while a session's swapped values sit live rebanks view-state
    -- values into the cond defaults (default poisoning).
    local function BankCond()
        if EllesmereUI._CondOv then
            EllesmereUI._CondOv.Harvest(EllesmereUI.Conditions_AppliedGid
                and EllesmereUI.Conditions_AppliedGid() or nil)
        end
    end
    if _editGroup then
        local g = _editGroup
        _editGroup = nil
        if SweepUncaptured then SweepUncaptured(g) end
        HarvestGroup(g)
        if TeardownEditSession then TeardownEditSession() end
        local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
        if touched then RunRefreshers(touched) end
        BankCond()
        return
    end
    if _defaultView then
        -- Bank default-view edits, then restore the real spec's values so the
        -- caller (export/switch/logout) sees canonical live data.
        _defaultView = false
        HarvestDefaults()
        if UpdateIndicator then UpdateIndicator() end
        local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
        if touched then RunRefreshers(touched) end
        BankCond()
        return
    end
    BankCond()
    Harvest(_activeSpec or CurrentSpecID())
end

-------------------------------------------------------------------------------
--  Unlock Layout Overrides
--  Per-GROUP overrides for unlock-mode layout aspects: element position (pos),
--  anchor link (anchor), grow direction (grow), width match (wm), height match (hm).
--  Stored OUTSIDE the fkey entries system: anchors and matches live in GLOBAL
--  EllesmereUIDB tables the Lite registry can't address, and unlock values bank
--  one-per-group, not one-per-spec.
--
--  Legacy per-aspect shape (still reachable from old import strings):
--    profile.specUnlockOverrides = {
--        groups   = { [groupId] = { [elementKey] = {
--                        pos    = saved-position entry (incl. tgt* follow
--                                 baselines for CDM/AB grow bars) | NIL_SENT,
--                        anchor = { target, side, offsetX, offsetY } | NIL_SENT,
--                        grow   = direction string | NIL_SENT,
--                        wm     = targetKey | NIL_SENT,
--                        hm     = targetKey | NIL_SENT } } },
--        baseline = { [elementKey] = same aspect shapes },
--        applied  = { [elementKey] = groupId },
--    }
--  baseline shadows the SHARED value of every overridden aspect and is the restore
--  source for a non-member spec / a removed override. applied is PERSISTED: after a
--  /reload the live globals still hold the previous spec's override values, so the
--  map lets the next apply restore exactly the overlaid elements -- never the whole
--  baseline bucket, which would clobber live drift (anchor-offset upkeep) on every
--  RefreshAllAddons. The CURRENT shape is the layer model: see GetUnlockStore.
-------------------------------------------------------------------------------

EllesmereUI.SPECOV_NIL = NIL_SENT
EllesmereUI._SPECOV_GOLD = { GOLD_R, GOLD_G, GOLD_B }

local function GetUnlockStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.specUnlockOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.specUnlockOverrides = s
    end
    -- Layer model: layouts[gid] = a COMPLETE unlock-layout fork for that group;
    -- baselineLayout = the shared layout, stored whenever a group layer is
    -- live; active = which layer the LIVE stores currently hold (nil =
    -- baseline).
    s.layouts = s.layouts or {}
    return s
end

function EllesmereUI.SpecOverrides_CurrentSpec()
    return CurrentSpecID()
end

function EllesmereUI.SpecOverrides_GroupById(gid)
    return GroupById(gid)
end

--- READ-ONLY view-state probe: true ONLY while the panel's Default Editing
--- Mode swap is live. Editing-as sessions (spec group or conditional)
--- deliberately preview their OWN swapped values, so the RF effective overlay
--- must stay OFF there ("click an override" keeps previewing that override).
--- Only the Default view needs panel-closed effective resolution.
--- (_CondOv, not the Cond local: Cond is declared further down the file.)
function EllesmereUI.SpecOverrides_ViewActive()
    if _editGroup then return false end
    local C = EllesmereUI._CondOv
    if C and C._edit then return false end
    return _defaultView and true or false
end

--- READ-ONLY: the CUSTOM unlock-layer fork of the override session being edited
--- (editing-as group or conditional); nil when no session is open or the
--- session's group has no custom unlock mode. Second return is the shared
--- baselineLayout for per-element fallback. Lets the RF real preview mirror the
--- session's unlock positions (recorded layer elems; anchored containers use
--- their recorded bookkeeping coordinates).
function EllesmereUI.SpecOverrides_EditSessionUnlockLayer()
    local s = GetUnlockStore()
    if _editGroup then
        local layer = s and s.layouts and s.layouts[_editGroup.id]
        if layer then return layer, s.baselineLayout end
        return nil
    end
    local C = EllesmereUI._CondOv
    local e = C and C._edit
    if e and e.id then
        local cs = C.GetUnlockStore and C.GetUnlockStore()
        local layer = cs and cs.layouts and cs.layouts[e.id]
        if layer then return layer, s and s.baselineLayout or nil end
    end
    return nil
end

--- READ-ONLY: display name of the override session being edited (editing-as
--- group or conditional), nil when none. Drives the preview chrome while a
--- session's own values are on screen.
function EllesmereUI.SpecOverrides_EditSessionName()
    if _editGroup then return _editGroup.name or _editGroup.label end
    local C = EllesmereUI._CondOv
    local e = C and C._edit
    if e and e.id and EllesmereUI.Conditions_GroupById then
        local cg = EllesmereUI.Conditions_GroupById(e.id)
        return cg and (cg.name or cg.label)
    end
    return nil
end

--- READ-ONLY owning group for a spec's VALUES: first group in creation order
--- containing the spec. Unlock-layout ownership (OwnerGid) is a different,
--- layout-carrying rule -- never use it for values.
function EllesmereUI.SpecOverrides_OwningGroupFor(specID)
    if not specID then return nil end
    for _, g in ipairs(GetGroups() or {}) do
        for _, sid in ipairs(g.specs or {}) do
            if sid == specID then return g end
        end
    end
    return nil
end

--- READ-ONLY effective-value resolver for ONE folder: what the value system
--- WOULD hold live for the current REAL spec with the panel closed. Mirrors
--- WriteSpecValues' ladder (values[spec] or default per fkey, blacklist/
--- match-owned skipped, table values never resolved) with Cond.WriteValues'
--- RUNTIME overlay on top (the applied conditional's values for fkeys the spec
--- store does not own -- spec always wins). NIL_SENT stays ENCODED in the
--- returned map (decode against EllesmereUI.SPECOV_NIL); like the writers it is
--- decoded conceptually BEFORE the table-type skip, so sentinel deletions
--- always resolve. Returns (flatMap fkey->value or nil, specSrc, condSrc).
--- ZERO writes, no store creation, safe from any module at any time.
function EllesmereUI.SpecOverrides_PeekEffectiveValues(folder)
    if not folder then return nil end
    local specID = CurrentSpecID()
    local out, specSrc, condSrc
    local store = GetStore()
    if store and specID then
        for _, entry in ipairs(store) do
            local m = entry.values[specID] or entry.values.default
            for fkey, def in pairs(entry.values.default) do
                if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
                   and SplitFKey(fkey) == folder then
                    local v = m[fkey]
                    if v == nil then v = def end
                    if v == NIL_SENT or type(v) ~= "table" then
                        out = out or {}
                        out[fkey] = v
                        if not specSrc and m ~= entry.values.default
                           and m[fkey] ~= nil then
                            local g = EllesmereUI.SpecOverrides_OwningGroupFor(specID)
                            specSrc = (g and (g.name or g.label))
                                or L("Spec Override")
                        end
                    end
                end
            end
        end
    end
    local C = EllesmereUI._CondOv
    if C and C.GetStore then
        local cstore = C.GetStore()
        if cstore and #cstore > 0 then
            local gid = EllesmereUI.Conditions_AppliedGid
                and EllesmereUI.Conditions_AppliedGid() or nil
            for _, entry in ipairs(cstore) do
                local map = gid and entry.values[gid] or nil
                for fkey, def in pairs(entry.values.default) do
                    if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
                       and not EntryOwning(fkey) and SplitFKey(fkey) == folder then
                        local v = def
                        local fromCond = false
                        if map and map[fkey] ~= nil then
                            v = map[fkey]
                            fromCond = true
                        end
                        if v == NIL_SENT or type(v) ~= "table" then
                            out = out or {}
                            out[fkey] = v
                            if fromCond and not condSrc then
                                local cg = EllesmereUI.Conditions_GroupById
                                    and EllesmereUI.Conditions_GroupById(gid)
                                condSrc = cg and (cg.name or cg.label)
                            end
                        end
                    end
                end
            end
        end
    end
    return out, specSrc, condSrc
end

--- Active layer gid; nil = the baseline layout is live.
function EllesmereUI.SpecOverrides_UnlockActive()
    local s = GetUnlockStore()
    return s and s.active or nil
end

--- Deterministic owner layer for a spec: the FIRST group in creation order that
--- contains specID and HAS a layout. Specs in no such group use the baseline.
local function OwnerGid(specID)
    if not specID then return nil end
    local s = GetUnlockStore()
    if not s or not next(s.layouts) then return nil end
    for _, g in ipairs(GetGroups() or {}) do
        if s.layouts[g.id] then
            for _, sid in ipairs(g.specs or {}) do
                if sid == specID then return g.id end
            end
        end
    end
    return nil
end

--- READ-ONLY: the RESOLVED effective unlock-layer fork for the current REAL
--- spec -- the owner group's fork, else the applied conditional's fork, else
--- nil (baseline effective: live positioning is already correct). Mirrors
--- SpecOverrides_ApplyUnlock's want resolution WITHOUT reading s.active: the
--- live pointer lags membership and panel-open unlock-mode edits, and the RF
--- real preview must show the layer that WOULD apply at the next boundary.
--- Second return is baselineLayout for per-element fallback.
function EllesmereUI.SpecOverrides_EffectiveUnlockLayer()
    local s = GetUnlockStore()
    if not s then return nil end
    local specID = CurrentSpecID()
    if not specID then return nil end
    local want = OwnerGid(specID)
    if want and s.layouts and s.layouts[want] then
        return s.layouts[want], s.baselineLayout
    end
    local C = EllesmereUI._CondOv
    local cond = C and C.ResolveGid and C.ResolveGid() or nil
    if cond then
        local cs = C.GetUnlockStore and C.GetUnlockStore()
        local layer = cs and cs.layouts and cs.layouts[cond]
        if layer then return layer, s.baselineLayout end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Layer harvest / apply
--
--  A LAYER is the complete unlock layout, captured and applied WHOLESALE:
--    anchors / widthMatch / heightMatch   global unlock link tables, verbatim
--                                         (incl. offsets, growth-edge pins)
--    cdmPos / abPos                       raw saved-edge stores incl. the
--                                         tgt* follow baselines
--    cdmGrow / abGrow                     grow directions by bar key
--    elems[key] = {point,relPoint,x,y,w,h} generic registered elements via
--                                         their own loadPosition/getSize
--  No diffs, no per-aspect baselines, no size companions: whatever edited the live
--  layout during play (drags, sliders, value-override applies, match propagation,
--  offset upkeep, blesses), harvest-on-leave records the final live truth into the
--  owning layer and apply-on-enter reproduces it -- convergent by construction.
--  TBB_/TBBG_ keys are excluded (natively spec-scoped / globally shared).
-------------------------------------------------------------------------------

local function LiteProfile(folder)
    local a = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon(folder, true)
    return a and a.db and a.db.profile or nil
end

local function LayerSkipsKey(key)
    if type(key) ~= "string" then return true end
    if key:sub(1, 4) == "CDM_" or key:sub(1, 4) == "TBB_"
       or key:sub(1, 5) == "TBBG_" then
        return true
    end
    local abk = EllesmereUI._abBarKeys
    return (abk and abk[key]) and true or false
end

-- Tracking Bar CHILD-role link entries (key "TBB_<idx>") are per-spec data
-- owned by the CDM link buckets (SyncTBBUnlockLinks): layers never carry them
-- and never wipe them, or an apply would stamp one spec's links onto another
-- spec's bars. Entries where a TBB key is only the TARGET live under the
-- child's key and stay layer-managed like any other element.
local function IsTBBChildKey(key)
    return type(key) == "string" and key:find("^TBB_%d+$") ~= nil
end

local function HarvestLayer()
    local layer = {
        anchors     = DeepCopy(EllesmereUIDB and EllesmereUIDB.unlockAnchors or {}),
        widthMatch  = DeepCopy(EllesmereUIDB and EllesmereUIDB.unlockWidthMatch or {}),
        heightMatch = DeepCopy(EllesmereUIDB and EllesmereUIDB.unlockHeightMatch or {}),
        cdmGrow = {}, abGrow = {}, elems = {},
    }
    -- Strip TBB child-role entries: per-spec data, not layer data.
    local stripSets = { layer.anchors, layer.widthMatch, layer.heightMatch }
    for i = 1, 3 do
        local t, kill = stripSets[i], nil
        for k in pairs(t) do
            if IsTBBChildKey(k) then
                kill = kill or {}
                kill[#kill + 1] = k
            end
        end
        if kill then
            for _, k in ipairs(kill) do t[k] = nil end
        end
    end
    local cdm = LiteProfile("EllesmereUICooldownManager")
    if cdm then
        layer.cdmPos = DeepCopy(cdm.cdmBarPositions or {})
        if cdm.cdmBars and cdm.cdmBars.bars then
            for _, bar in ipairs(cdm.cdmBars.bars) do
                if bar.key and bar.growDirection then
                    layer.cdmGrow[bar.key] = bar.growDirection
                end
            end
        end
    end
    local ab = LiteProfile("EllesmereUIActionBars")
    if ab then
        layer.abPos = DeepCopy(ab.barPositions or {})
        if ab.bars then
            for k, cfg in pairs(ab.bars) do
                if type(cfg) == "table" and cfg.growDirection then
                    layer.abGrow[k] = cfg.growDirection
                end
            end
        end
    end
    local elems = EllesmereUI._unlockRegisteredElements
    if elems then
        for key, elem in pairs(elems) do
            if not LayerSkipsKey(key) then
                local e
                if elem.loadPosition then
                    local ok, p = pcall(elem.loadPosition, key)
                    if ok and p and p.point then
                        e = { point = p.point, relPoint = p.relPoint or p.point,
                              x = p.x, y = p.y }
                    end
                end
                if elem.getSize then
                    local ok, w, h = pcall(elem.getSize, key)
                    if ok then
                        if type(w) == "number" and w > 0 then e = e or {}; e.w = w end
                        if type(h) == "number" and h > 0 then e = e or {}; e.h = h end
                    end
                end
                if e then layer.elems[key] = e end
            end
        end
    end
    return layer
end

-- Generic-element writes are deferred to the flush: their savePosition/setWidth
-- closures are only re-registered AFTER profile-switch applies, and the flush
-- carries the combat gate. Raw CDM/AB stores go through the stable Lite db
-- objects, so they are always safe to write immediately.
local _unlockDeferredElemLayout = nil
-- Baseline geometry for elements the INCOMING layer has no elems entry for
-- ("missing means baseline, never keep outgoing residue"): stashed by ApplyLayer,
-- applied by the flush after the layer's own entries, consumed per-key so live
-- drift is never re-stomped. Without it a layer missing a key (late registration,
-- fork saved before the element existed) leaves the OUTGOING layer's geometry live
-- and the next harvest bakes that residue into the incoming layer permanently.
local _unlockDeferredElemFallback = nil

-- Anchored children's positions are OWNED by the anchor system: a layer/baseline
-- elem recorded for a currently-anchored key is derived bookkeeping (whatever
-- geometry the anchor produced at harvest time) and must NEVER be painted back
-- through savePosition -- doing so stomps freshly anchor-applied windows and
-- poisons their module-saved positions. Mirrors the ApplyCenterPosition
-- anchored-skip, applied at the flush's write sites.
local function UnlockElemAnchorOwned(key)
    local a = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    local info = a and a[key]
    return type(info) == "table" and info.target ~= nil
end
local _unlockSettleWanted = false
local _unlockFlushScheduled = false
local _unlockFlushCombatWatch  -- one-shot PLAYER_REGEN_ENABLED re-flush frame
local ScheduleUnlockFlush

-- Loose elem-geometry equality (position keywords exact, coordinates and
-- sizes within the flush's 0.5 write tolerance).
local function ElemNear(a, b)
    if not a or not b then return false end
    if (a.point or false) ~= (b.point or false) then return false end
    if (a.relPoint or a.point or false) ~= (b.relPoint or b.point or false) then return false end
    local function near(x, y)
        if x == nil and y == nil then return true end
        if type(x) ~= "number" or type(y) ~= "number" then return false end
        return math.abs(x - y) < 0.5
    end
    return near(a.x, b.x) and near(a.y, b.y) and near(a.w, b.w) and near(a.h, b.h)
end

--- Writes a layer into the live stores. CRITICAL: the raw CDM/AB position tables
--- are mutated IN PLACE (wipe + refill) -- the owning addons keep mirror references
--- to these exact tables that only refresh on profile applies, so replacing the
--- table identity orphans them on same-profile spec swaps. baseline: the store's
--- baselineLayout when LAYER is a group/conditional fork (nil when applying the
--- baseline itself); every sub-store the layer is missing falls back to it
--- ("missing means baseline, never keep the outgoing layer's residue").
local function ApplyLayer(layer, baseline)
    if not layer then return end
    if EllesmereUIDB then
        local anchors = EllesmereUIDB.unlockAnchors
        if not anchors then anchors = {}; EllesmereUIDB.unlockAnchors = anchors end
        -- Fallback links belong to the child/target pair, not the spec: carry
        -- each over when the arriving layer keeps the same target. TBB child
        -- entries (per-spec, bucket-owned) ride the wipe whole, fallback
        -- included, and layer-borne ones are skipped on refill.
        local fallbacks, tbbKept
        for k, info in pairs(anchors) do
            if IsTBBChildKey(k) then
                tbbKept = tbbKept or {}
                tbbKept[k] = info
            elseif info.fallback then
                fallbacks = fallbacks or {}
                fallbacks[k] = { tgt = info.target, fb = info.fallback }
            end
        end
        wipe(anchors)
        for k, info in pairs(layer.anchors or {}) do
            if not IsTBBChildKey(k) then
                anchors[k] = DeepCopy(info)
                local f = fallbacks and fallbacks[k]
                if f and f.tgt == info.target then anchors[k].fallback = f.fb end
            end
        end
        if tbbKept then
            for k, info in pairs(tbbKept) do anchors[k] = info end
        end
        EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
        local wm = EllesmereUIDB.unlockWidthMatch
        if not wm then wm = {}; EllesmereUIDB.unlockWidthMatch = wm end
        local wmKept
        for k, v in pairs(wm) do
            if IsTBBChildKey(k) then
                wmKept = wmKept or {}
                wmKept[k] = v
            end
        end
        wipe(wm)
        for k, v in pairs(layer.widthMatch or {}) do
            if not IsTBBChildKey(k) then wm[k] = v end
        end
        if wmKept then
            for k, v in pairs(wmKept) do wm[k] = v end
        end
        local hm = EllesmereUIDB.unlockHeightMatch
        if not hm then hm = {}; EllesmereUIDB.unlockHeightMatch = hm end
        local hmKept
        for k, v in pairs(hm) do
            if IsTBBChildKey(k) then
                hmKept = hmKept or {}
                hmKept[k] = v
            end
        end
        wipe(hm)
        for k, v in pairs(layer.heightMatch or {}) do
            if not IsTBBChildKey(k) then hm[k] = v end
        end
        if hmKept then
            for k, v in pairs(hmKept) do hm[k] = v end
        end
    end
    local cdm = LiteProfile("EllesmereUICooldownManager")
    if cdm then
        -- A layer harvested while CDM was disabled has no cdmPos; restore the
        -- baseline's instead of leaving the outgoing layer's positions live
        -- (they would be harvested INTO this layer next).
        local pos = layer.cdmPos or (baseline and baseline.cdmPos)
        if pos then
            local t = cdm.cdmBarPositions
            if not t then t = {}; cdm.cdmBarPositions = t end
            wipe(t)
            for k, v in pairs(pos) do t[k] = DeepCopy(v) end
            -- Per-bar missing-means-baseline: a layer's cdmPos is a snapshot from its
            -- last harvest, so bars created AFTER it have no entry in older layers and
            -- fall to their DEFAULT (centered) placement at layout time ("CDM centered
            -- on this one spec"). Fill the gaps from the baseline (mirrors the grow-key
            -- rule below); the layer self-heals to full coverage at its next harvest.
            local bpos = baseline and baseline.cdmPos
            if bpos and bpos ~= pos then
                for k, v in pairs(bpos) do
                    if t[k] == nil then t[k] = DeepCopy(v) end
                end
            end
        end
        if cdm.cdmBars and cdm.cdmBars.bars then
            -- Grow keys follow missing-means-baseline too. A grow store is AUTHORITATIVE
            -- only when its layer was harvested with CDM loaded (cdmPos present <=>
            -- the harvest's cdm block ran); a layer that never saw CDM knows nothing
            -- about grows. Per bar: layer value, else baseline, else CLEAR (module
            -- default), so one fork's grow can't stick to every other layer.
            local lg = (layer.cdmPos ~= nil) and layer.cdmGrow or nil
            local bg = (baseline and baseline.cdmPos ~= nil) and baseline.cdmGrow or nil
            if lg or bg then
                for _, bar in ipairs(cdm.cdmBars.bars) do
                    if bar.key then
                        local gd
                        if lg then gd = lg[bar.key] end
                        if gd == nil and bg then gd = bg[bar.key] end
                        bar.growDirection = gd
                    end
                end
            end
        end
    end
    local ab = LiteProfile("EllesmereUIActionBars")
    if ab then
        local pos = layer.abPos or (baseline and baseline.abPos)
        if pos then
            local t = ab.barPositions
            if not t then t = {}; ab.barPositions = t end
            wipe(t)
            for k, v in pairs(pos) do t[k] = DeepCopy(v) end
            -- Per-bar missing-means-baseline, same as cdmPos above.
            local bpos = baseline and baseline.abPos
            if bpos and bpos ~= pos then
                for k, v in pairs(bpos) do
                    if t[k] == nil then t[k] = DeepCopy(v) end
                end
            end
        end
        if ab.bars then
            -- Same authority rule and per-bar fallback as cdmGrow.
            local lg = (layer.abPos ~= nil) and layer.abGrow or nil
            local bg = (baseline and baseline.abPos ~= nil) and baseline.abGrow or nil
            if lg or bg then
                for k, cfg in pairs(ab.bars) do
                    if type(cfg) == "table" then
                        local gd
                        if lg then gd = lg[k] end
                        if gd == nil and bg then gd = bg[k] end
                        cfg.growDirection = gd
                    end
                end
            end
        end
    end
    -- REPLACE the pending map, never merge: it always represents the ACTIVE layer's
    -- intended element state. Anything still unapplied from the previous layer was
    -- already banked back by the transition harvest (which overlays pending intent),
    -- and flushing it under the new layer would cross-contaminate.
    _unlockDeferredElemLayout = nil
    if layer.elems and next(layer.elems) then
        _unlockDeferredElemLayout = {}
        for key, e in pairs(layer.elems) do
            _unlockDeferredElemLayout[key] = DeepCopy(e)
        end
    end
    -- Missing means baseline: elements the incoming layer has no entry for restore
    -- their BASELINE geometry at flush time instead of keeping the outgoing layer's
    -- residue. Replaced wholesale with the pending map; entries consumed as they apply.
    _unlockDeferredElemFallback = nil
    if baseline and baseline ~= layer and baseline.elems then
        local fb
        for key, e in pairs(baseline.elems) do
            if not (layer.elems and layer.elems[key] ~= nil) and not LayerSkipsKey(key) then
                fb = fb or {}
                fb[key] = DeepCopy(e)
            end
        end
        _unlockDeferredElemFallback = fb
    end
end

-- ---- apply engine -----------------------------------------------------------

--- Swaps the live unlock layout to the given spec's layer (its owning group's layout,
--- or the baseline). Same-layer arrivals are a no-op: live drift (offset upkeep,
--- blesses) stays live and is banked by the transition harvests. NEVER harvests here
--- -- by apply time the value system has already written the NEW spec's data into
--- module configs, so a harvest here would bank it into the OLD layer (the
--- transition harvest in OnSpecChanged/HarvestCurrent runs while live is still old).
function EllesmereUI.SpecOverrides_ApplyUnlock(specID, force)
    local s = GetUnlockStore()
    if not s then return end
    specID = specID or _activeSpec or CurrentSpecID()
    if not specID then return end
    -- TIER 1: the spec's own group layer. When it exists, conditional layouts
    -- are ignored ENTIRELY for this spec.
    local want = OwnerGid(specID)
    local target
    if want then
        target = s.layouts[want]
    else
        -- TIER 2: the applied conditional group's layout (namespaced pointer
        -- "cond:<gid>" -- one pointer, one harvest target, one heal path).
        local cond = EllesmereUI._CondOv and EllesmereUI._CondOv.ResolveGid
            and EllesmereUI._CondOv.ResolveGid() or nil
        if cond then
            local cs = EllesmereUI._CondOv.GetUnlockStore()
            if cs and cs.layouts[cond] then
                want = "cond:" .. cond
                target = cs.layouts[cond]
            end
        end
    end
    if want == s.active and not force then
        -- Same-layer arrival: live drift stays live (never re-apply). BUT module
        -- POSITION stores can carry persisted gaps: a layer snapshot missing bars
        -- created after its last harvest leaves them entryless (default centered
        -- placement), and this early-out skips ApplyLayer every same-layer login, so
        -- the gap never heals without a layer transition. ADD-ONLY heal: fill missing
        -- bar keys from the live layer then the baseline; existing entries (live
        -- drift) are never touched, and the settle only runs if something was missing.
        local base = s.baselineLayout
        local function GapFill(prof, storeKey, layerPos, basePos)
            if not prof then return false end
            local t = prof[storeKey]
            if not t then t = {}; prof[storeKey] = t end
            local added = false
            if layerPos then
                for k, v in pairs(layerPos) do
                    if t[k] == nil then t[k] = DeepCopy(v); added = true end
                end
            end
            if basePos and basePos ~= layerPos then
                for k, v in pairs(basePos) do
                    if t[k] == nil then t[k] = DeepCopy(v); added = true end
                end
            end
            return added
        end
        local cdm = LiteProfile("EllesmereUICooldownManager")
        local ab = LiteProfile("EllesmereUIActionBars")
        local added = GapFill(cdm, "cdmBarPositions",
            target and target.cdmPos, base and base.cdmPos)
        if GapFill(ab, "barPositions",
            target and target.abPos, base and base.abPos) then added = true end
        if added then
            -- Same settle ApplyLayer uses: repositions bars from the now
            -- complete store (the flush self-defers in combat).
            _unlockSettleWanted = true
            ScheduleUnlockFlush()
        end
        return
    end
    -- TIER 3: baseline.
    if not target then target = s.baselineLayout end
    s.active = want
    if target then
        -- Forks fall back to the baseline for every sub-store they are
        -- missing (nil when the target IS the baseline).
        ApplyLayer(target, target ~= s.baselineLayout and s.baselineLayout or nil)
        _unlockSettleWanted = true
        ScheduleUnlockFlush()
    end
end

--- Banks the LIVE unlock layout into the layer it belongs to (the active group
--- layer, else the baseline). Runs at every transition boundary while live
--- still belongs to the outgoing state: spec change, profile
--- switch/export/logout, and unlock Save & Exit.
function EllesmereUI.SpecOverrides_HarvestUnlockLayout(userCommit)
    local s = GetUnlockStore()
    if not s then return end
    -- Zero-cost for non-users: nothing to bank into until a layer exists.
    local condStore = EllesmereUI._CondOv and EllesmereUI._CondOv.GetUnlockStore()
    if not s.active and not next(s.layouts) and not s.baselineLayout
       and not (condStore and next(condStore.layouts)) then return end
    -- Mid-establish (a profile apply whose Conditions establish was combat-deferred):
    -- live is MIXED -- baseline links restored over the incoming profile's
    -- layer-valued module data. Banking it anywhere (especially into baselineLayout
    -- via the reset active pointer) poisons the store; skip until the pending
    -- establish converges, then banks resume on the next boundary.
    if EllesmereUI.Conditions_EstablishPending and EllesmereUI.Conditions_EstablishPending() then
        return
    end
    -- Import window (see ImportProfile): from an imported profile's activation until
    -- the first apply of a LATER session, the store holds the exporter's layers
    -- verbatim while live geometry is mid-import residue (inherited link tables,
    -- unconverged anchors). Banking any boundary in that window (import-tail
    -- Conditions recheck, the reload's PLAYER_LOGOUT, first post-login spec
    -- transition) would wholesale-replace a pristine bucket with that residue.
    -- Fail-open like the guards above: skip; banks resume once the window closes.
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            if userCommit then
                -- Unlock Save & Exit: a user-committed layout is converged,
                -- live-authoritative state; close the window and bank it.
                prof._importEstablishPending = nil
            else
                return
            end
        end
    end
    -- Reset-pointer window (see SpecOverrides_UnlockResetActive): a profile activation
    -- cleared a live layer pointer while module elem positions still hold that layer's
    -- geometry. Banking before the forced converge lands would file the outgoing
    -- layer's positions into baselineLayout via the nil pointer. Fail-open like the
    -- import window, user-commit bypass included: a Save & Exit layout is
    -- live-authoritative by definition.
    if EllesmereUI._unlockResetConvergePending then
        if userCommit then
            EllesmereUI._unlockResetConvergePending = nil
        else
            return
        end
    end
    -- Default Editing Mode / editing-as session: live module sizes are the VIEW's
    -- swapped values, not the active layer's state (value writes resize bars); banking
    -- that geometry poisons the layer bucket. Fail-open: skip, next clean boundary
    -- banks. (_CondOv, not the Cond local: Cond is declared later and would read nil here.)
    if _defaultView or _editGroup
       or (EllesmereUI._CondOv and EllesmereUI._CondOv._edit) then return end
    local snap = HarvestLayer()
    -- Deferred entries still awaiting their element are the layer's INTENDED state:
    -- live (the shared module store) hasn't caught up, so bank the intent, not the
    -- stale value. Pending BASELINE fallback entries are intent too -- without them a
    -- fast double-swap bakes the OUTGOING layer's still-live residue into this layer.
    if _unlockDeferredElemFallback then
        for key, e in pairs(_unlockDeferredElemFallback) do
            snap.elems[key] = DeepCopy(e)
        end
    end
    if _unlockDeferredElemLayout then
        for key, e in pairs(_unlockDeferredElemLayout) do
            snap.elems[key] = DeepCopy(e)
        end
    end
    -- Resolve the live layer's owning bucket: group layer (numeric active),
    -- conditional layer ("cond:<gid>" active), else baseline.
    local condGid = type(s.active) == "string" and tonumber(s.active:match("^cond:(%d+)$")) or nil
    local condBucket = condGid and condStore and condStore.layouts[condGid] or nil
    -- Preserve entries for elements not currently registered (conditional /
    -- late registration: party+raid containers, CDM bars mid-rebuild).
    -- Absence from the registry means "unknown right now", never "deleted".
    local prev
    if condGid then
        prev = condBucket or s.baselineLayout
    else
        prev = s.active and s.layouts[s.active] or s.baselineLayout
    end
    if prev and prev.elems then
        local elems = EllesmereUI._unlockRegisteredElements
        for key, e in pairs(prev.elems) do
            if snap.elems[key] == nil and not (elems and elems[key]) then
                snap.elems[key] = DeepCopy(e)
            end
        end
    end
    -- Bake-in guard for GROUP/COND buckets: a key this layer never carried whose live
    -- geometry still MATCHES the baseline is baseline-FOLLOWING, not a layer edit, and
    -- banking it would freeze the baseline's value into the fork forever
    -- (late-registered elements, forks saved before an element existed). Keys that
    -- differ from the baseline are genuine edits and bank normally; the baseline
    -- bucket itself always banks everything.
    if prev and prev ~= s.baselineLayout and s.baselineLayout and s.baselineLayout.elems then
        local be = s.baselineLayout.elems
        local pe = prev.elems
        for key, e in pairs(snap.elems) do
            if (pe == nil or pe[key] == nil) and ElemNear(e, be[key]) then
                snap.elems[key] = nil
            end
        end
    end
    if condGid then
        if condBucket then
            condStore.layouts[condGid] = snap
        else
            s.baselineLayout = snap
            s.active = nil   -- heal: the condition layout was deleted
        end
    elseif s.active and s.layouts[s.active] then
        s.layouts[s.active] = snap
    else
        s.baselineLayout = snap
        s.active = nil   -- heal a dangling pointer (layout deleted elsewhere)
    end
end

--- Baseline link tables for profile unlockLayout snapshots: while a group layer
--- is LIVE the snapshot must come from the stored baseline, never the live
--- (group-valued) globals. Returns nil when live IS baseline.
function EllesmereUI.SpecOverrides_UnlockBaselineLinks()
    local s = GetUnlockStore()
    if s and s.active and s.baselineLayout then
        return s.baselineLayout.anchors or {},
               s.baselineLayout.widthMatch or {},
               s.baselineLayout.heightMatch or {}
    end
    return nil
end

--- Resets the active pointer after a profile-level unlockLayout restore wrote
--- baseline links into the live globals (profile switch/import). The per-spec
--- overlay re-applies the correct layer right after, but only when the incoming
--- spec WANTS a layer: a baseline spec early-outs on want == active == nil while
--- module elem positions still hold the previous session's layer geometry (only
--- LINKS were restored), and the next harvest would bank that geometry into
--- baselineLayout via the freshly nil'd pointer. Clearing a LIVE pointer therefore
--- arms a runtime converge flag: layout banks stay suppressed until one forced
--- apply paints the pointer's truth (consumed in the Apply/ApplyValues tails
--- beside the import converge). Never arms for a pointer that was already nil.
function EllesmereUI.SpecOverrides_UnlockResetActive(profRoot)
    local s = profRoot and profRoot.specUnlockOverrides
    if not s then return end
    if s.active ~= nil then
        EllesmereUI._unlockResetConvergePending = true
    end
    s.active = nil
end

--- Completes a pending unlock-layer apply: performs deferred generic-element
--- writes (safe now that unlock re-registration has run), then runs one settle
--- so the screen reflects the swapped stores. Called from OnSpecSwitchComplete
--- (after CDM's spec rebuild) and from a two-frame fallback timer for paths
--- where that never fires.
function EllesmereUI.SpecOverrides_FlushUnlock()
    -- Combat defer: both halves reposition SECURE unit frames (savePosition closures
    -- re-anchor boss chains; the settle SetPoints unit buttons), blocked in lockdown as
    -- ADDON_ACTION_BLOCKED. Hold ALL pending state untouched and re-run once at
    -- PLAYER_REGEN_ENABLED (the settle is idempotent, only measures post-rebuild geometry).
    if InCombatLockdown() then
        _unlockFlushScheduled = true  -- keeps ScheduleUnlockFlush deduped
        if not _unlockFlushCombatWatch then
            _unlockFlushCombatWatch = CreateFrame("Frame")
            _unlockFlushCombatWatch:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if _unlockFlushScheduled then EllesmereUI.SpecOverrides_FlushUnlock() end
            end)
        end
        _unlockFlushCombatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    _unlockFlushScheduled = false
    local pend = _unlockDeferredElemLayout
    _unlockDeferredElemLayout = nil
    local keep
    local wroteLayerSizes = false
    if pend then
        -- Sanctioned-write flag: several modules (Unit Frames, ABR) gate their
        -- setWidth/setHeight writes on unlock mode being active; the layer flush
        -- restores sizes OUTSIDE unlock mode and must pass those gates or the
        -- restore silently no-ops ("matched width bleeds to the default layout").
        EllesmereUI._unlockLayerApplying = true
        local elems = EllesmereUI._unlockRegisteredElements
        for key, e in pairs(pend) do
            local elem = elems and elems[key]
            if not elem then
                -- Conditional/late registration (party+raid containers, CDM
                -- bars mid-rebuild): hold the entry; RegisterUnlockElements
                -- pokes a re-flush the moment the element appears.
                keep = keep or {}
                keep[key] = e
            end
            if elem then
                -- Value-equal guards throughout: the arriving layer matches
                -- live for most elements; only real deltas write and settle.
                -- Anchor-owned keys never take elem positions (see
                -- UnlockElemAnchorOwned): the anchor is the authority.
                if e.point and elem.savePosition and not UnlockElemAnchorOwned(key) then
                    local cur = elem.loadPosition and elem.loadPosition(key)
                    if not (cur and cur.point == e.point
                        and (cur.relPoint or cur.point) == (e.relPoint or e.point)
                        and cur.x == e.x and cur.y == e.y) then
                        pcall(elem.savePosition, key, e.point, e.relPoint or e.point, e.x, e.y)
                        -- Re-anchor through the element's OWN authority: noInitHook
                        -- elements (the RF raid container) are skipped by the settle's
                        -- saved-positions loop, so without this the DB gets the layer's
                        -- position but the frame stays where module init anchored it
                        -- from the PRE-flush value (login-only stale-layout visual).
                        if elem.applyPosition then pcall(elem.applyPosition, key) end
                        _unlockSettleWanted = true
                    end
                end
                local curW, curH
                if elem.getSize then curW, curH = elem.getSize(key) end
                if e.w and elem.setWidth and not (curW and math.abs(curW - e.w) < 0.5) then
                    pcall(elem.setWidth, key, e.w)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                if e.h and elem.setHeight and not (curH and math.abs(curH - e.h) < 0.5) then
                    pcall(elem.setHeight, key, e.h)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
            end
        end
        EllesmereUI._unlockLayerApplying = nil
    end
    if keep then _unlockDeferredElemLayout = keep end
    -- Missing means baseline: elements the incoming layer carried no entry for
    -- restore their BASELINE geometry (stashed by ApplyLayer). The layer's own
    -- entries always win (pend/keep); each fallback entry is CONSUMED once applied
    -- so later flushes never stomp live drift, and still-unregistered elements are
    -- retained for the registration poke like kept pend entries.
    if _unlockDeferredElemFallback then
        local fb = _unlockDeferredElemFallback
        local elems = EllesmereUI._unlockRegisteredElements
        EllesmereUI._unlockLayerApplying = true
        for key, e in pairs(fb) do
            if (pend and pend[key] ~= nil) or (keep and keep[key] ~= nil) then
                fb[key] = nil   -- the layer owns this key
            elseif elems and elems[key] then
                local elem = elems[key]
                -- Same anchor-owned skip as the pend path above.
                if e.point and elem.savePosition and not UnlockElemAnchorOwned(key) then
                    local cur = elem.loadPosition and elem.loadPosition(key)
                    if not (cur and cur.point == e.point
                        and (cur.relPoint or cur.point) == (e.relPoint or e.point)
                        and cur.x == e.x and cur.y == e.y) then
                        pcall(elem.savePosition, key, e.point, e.relPoint or e.point, e.x, e.y)
                        -- Same authority re-anchor as the pend path above
                        -- (the settle never moves noInitHook elements).
                        if elem.applyPosition then pcall(elem.applyPosition, key) end
                        _unlockSettleWanted = true
                    end
                end
                local curW, curH
                if elem.getSize then curW, curH = elem.getSize(key) end
                if e.w and elem.setWidth and not (curW and math.abs(curW - e.w) < 0.5) then
                    pcall(elem.setWidth, key, e.w)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                if e.h and elem.setHeight and not (curH and math.abs(curH - e.h) < 0.5) then
                    pcall(elem.setHeight, key, e.h)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                fb[key] = nil   -- applied once; live drift owns it from here
            end
        end
        EllesmereUI._unlockLayerApplying = nil
        if not next(fb) then _unlockDeferredElemFallback = nil end
    end
    -- Element sizes live in MODULE settings (the same keys the value system
    -- captures), so a layer size stamp can overwrite a per-spec or Default view value
    -- applied before this deferred flush ran -- the flush runs last and would win,
    -- banking a value-overridden size into the shared baseline layer and stamping it
    -- onto specs that never had it. Re-run the value overlay so captured settings
    -- win (the layer's own store self-heals at its next harvest); runs BEFORE the
    -- settle so an active width/height match still owns matched sizes, and skips
    -- mid-transition (that apply is imminent).
    if wroteLayerSizes and not _inTransition then
        local touched = ApplyValuesFor(_activeSpec or CurrentSpecID())
        if EllesmereUI._CondOv then
            local t2 = EllesmereUI._CondOv.ApplyValues()
            if t2 then
                touched = touched or {}
                for k in pairs(t2) do touched[k] = true end
            end
        end
        if touched then RunRefreshers(touched) end
    end
    if not _unlockSettleWanted then return end
    -- Never fight an open unlock session; its own save/close flows settle.
    if EllesmereUI._unlockModeActive then return end
    _unlockSettleWanted = false
    if EllesmereUI.ApplyAllWidthHeightMatches then pcall(EllesmereUI.ApplyAllWidthHeightMatches) end
    if EllesmereUI._applySavedPositions then pcall(EllesmereUI._applySavedPositions) end
    if EllesmereUI.ResyncAnchorOffsets then pcall(EllesmereUI.ResyncAnchorOffsets) end
    if EllesmereUI.ReapplyAllUnlockAnchorsForced then
        EllesmereUI._reapplyForceEdgePreserve = true
        pcall(EllesmereUI.ReapplyAllUnlockAnchorsForced)
        EllesmereUI._reapplyForceEdgePreserve = false
    end
end

ScheduleUnlockFlush = function()
    if _unlockFlushScheduled then return end
    _unlockFlushScheduled = true
    -- Two frames: a profile-switch RefreshAllAddons finishes its child applies
    -- and unlock re-registration first. The CDM spec-rebuild path also flushes
    -- from OnSpecSwitchComplete; whichever runs first wins, the other no-ops.
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            if _unlockFlushScheduled then EllesmereUI.SpecOverrides_FlushUnlock() end
        end)
    end)
end

--- Re-flush poke from RegisterUnlockElements: deferred layer writes whose
--- elements were missing become applicable the moment they register. The
--- schedule is deduped, so a registration burst costs one flush.
function EllesmereUI.SpecOverrides_UnlockPokeFlush()
    if (_unlockDeferredElemLayout and next(_unlockDeferredElemLayout))
       or (_unlockDeferredElemFallback and next(_unlockDeferredElemFallback)) then
        ScheduleUnlockFlush()
    end
end

-- ---- layer management ---------------------------------------------------------

--- True when the group has a custom unlock layout.
function EllesmereUI.SpecOverrides_UnlockHasLayout(groupId)
    local s = GetUnlockStore()
    return (s and s.layouts[groupId] ~= nil) and true or false
end

--- Deletes a group's custom unlock layout. When it is the ACTIVE layer, the
--- baseline layout is applied back to live.
function EllesmereUI.SpecOverrides_RemoveUnlockLayout(groupId)
    local s = GetUnlockStore()
    if not s or s.layouts[groupId] == nil then return false end
    s.layouts[groupId] = nil
    if s.active == groupId then
        s.active = nil
        if s.baselineLayout then
            ApplyLayer(s.baselineLayout)
            _unlockSettleWanted = true
            EllesmereUI.SpecOverrides_FlushUnlock()
        end
    end
    return true
end

-- ---- conditional unlock layouts (engine in EllesmereUI_Conditions.lua) -------

--- Deletes a conditional group's custom unlock layout; when live, the
--- baseline layout is applied back. Mirrors SpecOverrides_RemoveUnlockLayout.
function EllesmereUI.Conditions_RemoveUnlockLayout(condGid)
    local cs = EllesmereUI._CondOv and EllesmereUI._CondOv.GetUnlockStore()
    if not cs or cs.layouts[condGid] == nil then return false end
    cs.layouts[condGid] = nil
    local s = GetUnlockStore()
    if s and s.active == ("cond:" .. condGid) then
        s.active = nil
        if s.baselineLayout then
            ApplyLayer(s.baselineLayout)
            _unlockSettleWanted = true
            EllesmereUI.SpecOverrides_FlushUnlock()
        end
    end
    return true
end

-------------------------------------------------------------------------------
--  Buff Manager forks (Raid Frames "Buff Manager" tab): the unlock LAYER model
--  applied to the BM settings subtree. A BM LAYER is the complete subtree,
--  captured and applied WHOLESALE as deep copies:
--    indicators (bmIndicators), simple (bmSimple),
--    displayMode (bmDisplayMode, resolved), iconZoom (bmIconZoom, resolved).
--  Opt-in per override group via the full-page overlay on the BM tab during an
--  editing session. Harvest-on-leave / apply-on-enter at the SAME boundaries as
--  unlock layers; spec groups win over conditionals; establish transitions
--  apply without harvesting. Stores are profile-root siblings of the unlock
--  stores: specBmOverrides { layouts, baselineLayout, active } and
--  condBmOverrides { layouts }.
-------------------------------------------------------------------------------

local function GetBmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.specBmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.specBmOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

local function GetCondBmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.condBmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.condBmOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

--- Deterministic BM owner for a spec (first group in creation order with a BM
--- layer containing the spec). Independent of unlock ownership: a group can
--- fork one system without the other.
local function BmOwnerGid(specID)
    if not specID then return nil end
    local s = GetBmStore()
    if not s or not next(s.layouts) then return nil end
    for _, g in ipairs(GetGroups() or {}) do
        if s.layouts[g.id] then
            for _, sid in ipairs(g.specs or {}) do
                if sid == specID then return g.id end
            end
        end
    end
    return nil
end

--- Builds a BM layer from the live RF profile. nil when RF's profile is absent
--- or never initialized -- never bank an empty layer over a stored one. The v2
--- payload (bm2 spec forks) rides the same layer; 12.1-born profiles may have
--- no legacy bmIndicators table at all, so either subtree qualifies the snap.
local function BmHarvestLayer()
    local rf = LiteProfile("EllesmereUIRaidFrames")
    if not rf then return nil end
    local fork = _G._ERF_BM2HarvestFork and _G._ERF_BM2HarvestFork() or nil
    if type(rf.bmIndicators) ~= "table" and not fork then return nil end
    return {
        indicators  = DeepCopy(rf.bmIndicators or {}),
        simple      = DeepCopy(rf.bmSimple or {}),
        displayMode = rf.bmDisplayMode or "custom",
        iconZoom    = rf.bmIconZoom or 0.08,
        bm2         = fork,
    }
end

--- Writes a BM layer into the live RF profile IN PLACE (wipe + refill: RF's
--- ns.db.profile IS this table and open BM pages capture subtable references)
--- and runs the BM-only refresh. Nothing here touches secure frames, so no
--- combat deferral is needed. noPageRefresh: skip the options-page repaint
--- (callers running DURING a page build repaint themselves; a nested
--- RefreshPage would rebuild inside a rebuild). Returns true only when the
--- paint actually LANDED -- callers gate pointer moves on it.
local function BmApplyLayer(layer, noPageRefresh)
    if not layer then return false end
    local rf = LiteProfile("EllesmereUIRaidFrames")
    if not rf then return false end
    local ind = rf.bmIndicators
    if type(ind) ~= "table" then ind = {}; rf.bmIndicators = ind end
    wipe(ind)
    for k, v in pairs(layer.indicators or {}) do ind[k] = DeepCopy(v) end
    local simple = rf.bmSimple
    if type(simple) ~= "table" then simple = {}; rf.bmSimple = simple end
    wipe(simple)
    for k, v in pairs(layer.simple or {}) do
        simple[k] = type(v) == "table" and DeepCopy(v) or v
    end
    rf.bmDisplayMode = layer.displayMode or "custom"
    rf.bmIconZoom = layer.iconZoom or 0.08
    -- v2 payload: applied through the BM2 bridge, which also converts
    -- legacy-only layers in place on first touch.
    if _G._ERF_BM2ApplyLayer then _G._ERF_BM2ApplyLayer(layer) end
    if _G._ERF_BMRefresh then _G._ERF_BMRefresh(noPageRefresh) end
    return true
end

--- Banks the LIVE Buff Manager into the layer it belongs to (active group
--- layer, conditional layer, else baseline). Runs at every transition boundary
--- while live still belongs to the outgoing state.
function EllesmereUI.SpecOverrides_HarvestBmLayout()
    local s = GetBmStore()
    if not s then return end
    -- Zero-cost for non-users: nothing to bank into until a fork exists.
    local cs = GetCondBmStore()
    if not s.active and not next(s.layouts) and not s.baselineLayout
       and not (cs and next(cs.layouts)) then return end
    -- Import window: same suppression as HarvestUnlockLayout (the BM forks
    -- arrived verbatim in the same import; live is residue).
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then return end
    end
    local snap = BmHarvestLayer()
    if not snap then return end
    -- Editing-as-conditional session swap: while a conditional's fork is
    -- session-applied (edited OUT of its real context), live belongs to THAT
    -- fork, never the runtime pointer's layer. Covers every transition boundary
    -- funneling through here (logout, export, profile switch) without touching
    -- the runtime pointer.
    local sessGid = EllesmereUI._bmSessionGid
    if sessGid then
        if cs and cs.layouts[sessGid] then
            cs.layouts[sessGid] = snap
        end
        return
    end
    local condGid = type(s.active) == "string" and tonumber(s.active:match("^cond:(%d+)$")) or nil
    if condGid then
        if cs and cs.layouts[condGid] then
            cs.layouts[condGid] = snap
        else
            -- Dangling pointer (layout deleted elsewhere): bank to baseline
            -- and heal, mirroring the unlock harvest.
            s.baselineLayout = snap
            s.active = nil
        end
    elseif s.active then
        if s.layouts[s.active] then
            s.layouts[s.active] = snap
        else
            s.baselineLayout = snap
            s.active = nil
        end
    else
        s.baselineLayout = snap
    end
end

--- Swaps the live Buff Manager to the given spec's layer: the owner group's
--- fork, else the applied conditional's fork, else the baseline. Mirrors
--- SpecOverrides_ApplyUnlock (incl. the force flag for establish transitions);
--- NEVER harvests here.
function EllesmereUI.SpecOverrides_ApplyBm(specID, force, noPageRefresh)
    local s = GetBmStore()
    if not s then return end
    -- Import window: NO apply may run between the store merge and the post-reload
    -- converge. Pre-reload the child Lite DBs still hold the OUTGOING profile's
    -- tables (the reload IS the switch), so a paint would "land" on the wrong
    -- profile while the pointer moves anyway, stranding imported fork content under
    -- the new pointer for the first harvest to bank over baselineLayout. The
    -- converge clears the flag before its forced apply, the first legal paint.
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            return
        end
    end
    specID = specID or _activeSpec or CurrentSpecID()
    if not specID then return end
    local want = BmOwnerGid(specID)
    local target
    if want then
        target = s.layouts[want]
    else
        local cond = EllesmereUI._CondOv and EllesmereUI._CondOv.ResolveGid
            and EllesmereUI._CondOv.ResolveGid() or nil
        if cond then
            local cs = GetCondBmStore()
            if cs and cs.layouts[cond] then
                want = "cond:" .. cond
                target = cs.layouts[cond]
            end
        end
    end
    if want == s.active and not force then return end
    if not target then target = s.baselineLayout end
    if target then
        -- The pointer advances ONLY when the paint lands. A silent no-op apply (RF
        -- store not ready, malformed layer) must never strand live content under the
        -- wrong pointer, or the next harvest banks it into the wrong layer (baseline
        -- overwritten by fork content). Failed applies retry naturally: want ~= active
        -- still holds at the next boundary.
        if BmApplyLayer(target, noPageRefresh) then
            s.active = want
        end
    elseif s.active == nil then
        -- Virgin store (no baseline banked yet): live IS the baseline, so the
        -- pointer may move without a paint.
        s.active = want
    else
        -- A layer is live but there is nothing to paint back (no
        -- baselineLayout): KEEP the old pointer so harvests keep banking live
        -- into the layer it actually holds.
    end
end

-------------------------------------------------------------------------------
--  BM session swap: unlike unlock layouts (WYSIWYG against real frames), Buff
--  Manager settings need no real-context editing, so an editing-as-conditional
--  session may edit the group's fork ANYWHERE. The fork applies for the session via
--  a RUNTIME-ONLY flag (never persisted: a mid-session reload comes back on the
--  runtime pointer's layer, fail-safe); the session-aware branch in
--  SpecOverrides_HarvestBmLayout routes every mid-session bank into the fork. Spec
--  forks never need this: their member-spec gate guarantees the fork already IS
--  the runtime layer while editing is allowed.
-------------------------------------------------------------------------------

--- Applies the conditional's fork as the session-live BM layer. Idempotent.
local function BmSessionEngage(gid)
    if EllesmereUI._bmSessionGid == gid then return end
    local cs = GetCondBmStore()
    local layer = cs and cs.layouts[gid]
    if not layer then return end
    -- Flag only on a LANDED paint: a session flag over unswapped live banks
    -- the runtime layer's content into the fork at release.
    if BmApplyLayer(layer, true) then   -- callers run during a page build
        EllesmereUI._bmSessionGid = gid
    end
end

--- Banks the session's live edits into the fork and restores the runtime
--- layer. noApply: a transition is about to apply the runtime layer itself.
function EllesmereUI.SpecOverrides_BmSessionRelease(noApply)
    local gid = EllesmereUI._bmSessionGid
    if not gid then return end
    local cs = GetCondBmStore()
    if cs and cs.layouts[gid] then
        local snap = BmHarvestLayer()
        if snap then cs.layouts[gid] = snap end
    end
    EllesmereUI._bmSessionGid = nil
    if not noApply then
        EllesmereUI.SpecOverrides_ApplyBm(_activeSpec or CurrentSpecID(), true, true)
    end
end

--- Name of the override group whose Buff Manager fork is LIVE (session-applied
--- conditional first, then the runtime pointer), or nil when live is the
--- baseline. Drives the BM page's "Override Active" label.
function EllesmereUI.SpecOverrides_BmActiveInfo()
    local gid = EllesmereUI._bmSessionGid
    local isCond = gid ~= nil
    if not gid then
        local s = GetBmStore()
        local a = s and s.active
        if type(a) == "string" then
            gid = tonumber(a:match("^cond:(%d+)$"))
            isCond = true
        elseif type(a) == "number" then
            gid = a
        end
    end
    if not gid then return nil end
    local g
    if isCond then
        g = EllesmereUI.Conditions_GroupById and EllesmereUI.Conditions_GroupById(gid)
    else
        g = GroupById(gid)
    end
    return g and g.name or nil
end

--- kind ("spec"/"cond") + gid of the fork LIVE on the Buff Manager page, or nil
--- when not on that page / live is the baseline. The page is hard-bound to the
--- live fork (the prelude force-activates it), so every consumer (card locks,
--- session-entry blocks, passive chrome) keys off this.
function EllesmereUI.SpecOverrides_BmPageLockInfo()
    local mod = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
    if mod ~= "EllesmereUIRaidFrames" then return nil end
    local page = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
    if page ~= "Buff Manager" then return nil end
    if EllesmereUI._bmSessionGid then return "cond", EllesmereUI._bmSessionGid end
    local s = GetBmStore()
    local a = s and s.active
    if type(a) == "number" then return "spec", a end
    if type(a) == "string" then
        local cg = tonumber(a:match("^cond:(%d+)$"))
        if cg then return "cond", cg end
    end
    return nil
end

--- True while the Buff Manager page is bound to a live fork (any kind).
function EllesmereUI.SpecOverrides_BmPageLocked()
    return EllesmereUI.SpecOverrides_BmPageLockInfo() ~= nil
end

--- True when the group has a custom Buff Manager.
function EllesmereUI.SpecOverrides_BmHasLayout(groupId)
    local s = GetBmStore()
    return (s and s.layouts[groupId] ~= nil) and true or false
end

--- Deletes a group's custom Buff Manager; when it is the ACTIVE layer the
--- baseline is applied back to live.
function EllesmereUI.SpecOverrides_RemoveBmLayout(groupId)
    local s = GetBmStore()
    if not s or s.layouts[groupId] == nil then return false end
    s.layouts[groupId] = nil
    if s.active == groupId then
        -- Pointer moves only with a landed paint (or nothing to restore).
        if not s.baselineLayout or BmApplyLayer(s.baselineLayout) then
            s.active = nil
        end
    end
    return true
end

--- Conditional twin of SpecOverrides_RemoveBmLayout.
function EllesmereUI.Conditions_RemoveBmLayout(condGid)
    local cs = GetCondBmStore()
    if not cs or cs.layouts[condGid] == nil then return false end
    cs.layouts[condGid] = nil
    local s = GetBmStore()
    if s and s.active == ("cond:" .. condGid) then
        if not s.baselineLayout or BmApplyLayer(s.baselineLayout) then
            s.active = nil
        end
    end
    -- Deleted while session-applied (cards popup is reachable mid-session):
    -- drop the flag and put the runtime layer back, discarding the orphan.
    if EllesmereUI._bmSessionGid == condGid then
        EllesmereUI._bmSessionGid = nil
        EllesmereUI.SpecOverrides_ApplyBm(_activeSpec or CurrentSpecID(), true)
    end
    return true
end

--- Orphan-heal for a stored profile's BM pointer (import/restore path).
--- Deliberately NOT an unconditional reset: BM live data and pointer travel
--- together inside the profile blob (export harvests first), so a consistent
--- foreign pointer converges via the establish force-apply. Only a pointer at a
--- DELETED layout is healed -- nil-ing a consistent pointer makes the next
--- harvest bank fork data into the baseline.
function EllesmereUI.SpecOverrides_BmResetActive(profRoot)
    local s = profRoot and profRoot.specBmOverrides
    if not s or s.active == nil then return end
    local a = s.active
    if type(a) == "string" then
        local gid = tonumber(a:match("^cond:(%d+)$"))
        local cs = profRoot.condBmOverrides
        if not (gid and cs and type(cs.layouts) == "table" and cs.layouts[gid]) then
            s.active = nil
        end
    elseif not (type(s.layouts) == "table" and s.layouts[a]) then
        s.active = nil
    end
end

-------------------------------------------------------------------------------
--  Debuff Manager forks: the BM layer model applied to the RF dmDebuff subtree.
--  A DM LAYER is { dm = deep copy of the profile's dmDebuff table }. Same
--  boundaries and precedence (spec groups beat conditionals), independent
--  opt-in: a group can fork either manager without the other. Stores:
--  specDmOverrides { layouts, baselineLayout, active } and condDmOverrides
--  { layouts }. Live apply/harvest runs through the _ERF_DM* bridges exported
--  by the Debuff Manager file; every call is existence-guarded, so the feature
--  is inert when that file is absent.
-------------------------------------------------------------------------------

local function GetDmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.specDmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.specDmOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

local function GetCondDmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.condDmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.condDmOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

--- Deterministic DM owner for a spec (first group in creation order with a
--- DM layer containing the spec). Independent of BM/unlock ownership.
local function DmOwnerGid(specID)
    if not specID then return nil end
    local s = GetDmStore()
    if not s or not next(s.layouts) then return nil end
    for _, g in ipairs(GetGroups() or {}) do
        if s.layouts[g.id] then
            for _, sid in ipairs(g.specs or {}) do
                if sid == specID then return g.id end
            end
        end
    end
    return nil
end

--- Builds a DM layer from the live profile via the bridge. nil when the Debuff
--- Manager is unavailable -- never bank an empty layer over a stored one.
local function DmHarvestLayer()
    local dm = _G._ERF_DMHarvestFork and _G._ERF_DMHarvestFork() or nil
    if not dm then return nil end
    return { dm = dm }
end

--- Writes a DM layer into the live profile through the bridge (wipe + refill in
--- place) and runs the DM-only refresh. Returns true only when the paint landed
--- (pointer moves gate on it).
local function DmApplyLayer(layer, noPageRefresh)
    if not layer or not layer.dm then return false end
    if not _G._ERF_DMApplyLayer then return false end
    return _G._ERF_DMApplyLayer(layer.dm, noPageRefresh) and true or false
end

--- Banks the LIVE Debuff Manager into the layer it belongs to. Runs at every
--- transition boundary while live still belongs to the outgoing state (mirror
--- of SpecOverrides_HarvestBmLayout).
function EllesmereUI.SpecOverrides_HarvestDmLayout()
    local s = GetDmStore()
    if not s then return end
    local cs = GetCondDmStore()
    if not s.active and not next(s.layouts) and not s.baselineLayout
       and not (cs and next(cs.layouts)) then return end
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then return end
    end
    local snap = DmHarvestLayer()
    if not snap then return end
    local sessGid = EllesmereUI._dmSessionGid
    if sessGid then
        if cs and cs.layouts[sessGid] then
            cs.layouts[sessGid] = snap
        end
        return
    end
    local condGid = type(s.active) == "string" and tonumber(s.active:match("^cond:(%d+)$")) or nil
    if condGid then
        if cs and cs.layouts[condGid] then
            cs.layouts[condGid] = snap
        else
            s.baselineLayout = snap
            s.active = nil
        end
    elseif s.active then
        if s.layouts[s.active] then
            s.layouts[s.active] = snap
        else
            s.baselineLayout = snap
            s.active = nil
        end
    else
        s.baselineLayout = snap
    end
end

--- Swaps the live Debuff Manager to the given spec's layer (mirror of
--- SpecOverrides_ApplyBm). NEVER harvests here.
function EllesmereUI.SpecOverrides_ApplyDm(specID, force, noPageRefresh)
    local s = GetDmStore()
    if not s then return end
    -- Import window: same suppression as SpecOverrides_ApplyBm (pre-reload
    -- paints land on the outgoing profile's tables).
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            return
        end
    end
    specID = specID or _activeSpec or CurrentSpecID()
    if not specID then return end
    local want = DmOwnerGid(specID)
    local target
    if want then
        target = s.layouts[want]
    else
        local cond = EllesmereUI._CondOv and EllesmereUI._CondOv.ResolveGid
            and EllesmereUI._CondOv.ResolveGid() or nil
        if cond then
            local cs = GetCondDmStore()
            if cs and cs.layouts[cond] then
                want = "cond:" .. cond
                target = cs.layouts[cond]
            end
        end
    end
    if want == s.active and not force then return end
    if not target then target = s.baselineLayout end
    if target then
        -- Pointer advances ONLY when the paint lands (see the BM twin: a
        -- silent no-op apply must never strand live content under the wrong
        -- pointer, or the next harvest banks it into the wrong layer).
        if DmApplyLayer(target, noPageRefresh) then
            s.active = want
        end
    elseif s.active == nil then
        s.active = want
    end
end

--- Applies the conditional's fork as the session-live DM layer (mirror of
--- BmSessionEngage; runtime-only flag, never persisted).
local function DmSessionEngage(gid)
    if EllesmereUI._dmSessionGid == gid then return end
    local cs = GetCondDmStore()
    local layer = cs and cs.layouts[gid]
    if not layer then return end
    if DmApplyLayer(layer, true) then   -- flag only on a landed paint
        EllesmereUI._dmSessionGid = gid
    end
end

--- Banks the session's live edits into the fork and restores the runtime
--- layer. noApply: a transition is about to apply the runtime layer itself.
function EllesmereUI.SpecOverrides_DmSessionRelease(noApply)
    local gid = EllesmereUI._dmSessionGid
    if not gid then return end
    local cs = GetCondDmStore()
    if cs and cs.layouts[gid] then
        local snap = DmHarvestLayer()
        if snap then cs.layouts[gid] = snap end
    end
    EllesmereUI._dmSessionGid = nil
    if not noApply then
        EllesmereUI.SpecOverrides_ApplyDm(_activeSpec or CurrentSpecID(), true, true)
    end
end

--- Name of the override group whose Debuff Manager fork is LIVE, or nil when
--- live is the baseline.
function EllesmereUI.SpecOverrides_DmActiveInfo()
    local gid = EllesmereUI._dmSessionGid
    local isCond = gid ~= nil
    if not gid then
        local s = GetDmStore()
        local a = s and s.active
        if type(a) == "string" then
            gid = tonumber(a:match("^cond:(%d+)$"))
            isCond = true
        elseif type(a) == "number" then
            gid = a
        end
    end
    if not gid then return nil end
    local g
    if isCond then
        g = EllesmereUI.Conditions_GroupById and EllesmereUI.Conditions_GroupById(gid)
    else
        g = GroupById(gid)
    end
    return g and g.name or nil
end

--- kind + gid of the fork LIVE on the Debuff Manager page, or nil when not
--- on that page / live is the baseline (mirror of BmPageLockInfo).
function EllesmereUI.SpecOverrides_DmPageLockInfo()
    local mod = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
    if mod ~= "EllesmereUIRaidFrames" then return nil end
    local page = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
    if page ~= "Debuff Manager" then return nil end
    if EllesmereUI._dmSessionGid then return "cond", EllesmereUI._dmSessionGid end
    local s = GetDmStore()
    local a = s and s.active
    if type(a) == "number" then return "spec", a end
    if type(a) == "string" then
        local cg = tonumber(a:match("^cond:(%d+)$"))
        if cg then return "cond", cg end
    end
    return nil
end

--- True while the Debuff Manager page is bound to a live fork (any kind).
function EllesmereUI.SpecOverrides_DmPageLocked()
    return EllesmereUI.SpecOverrides_DmPageLockInfo() ~= nil
end

--- True when the group has a custom Debuff Manager.
function EllesmereUI.SpecOverrides_DmHasLayout(groupId)
    local s = GetDmStore()
    return (s and s.layouts[groupId] ~= nil) and true or false
end

--- Deletes a group's custom Debuff Manager; when it is the ACTIVE layer the
--- baseline is applied back to live.
function EllesmereUI.SpecOverrides_RemoveDmLayout(groupId)
    local s = GetDmStore()
    if not s or s.layouts[groupId] == nil then return false end
    s.layouts[groupId] = nil
    if s.active == groupId then
        if not s.baselineLayout or DmApplyLayer(s.baselineLayout) then
            s.active = nil
        end
    end
    return true
end

--- Conditional twin of SpecOverrides_RemoveDmLayout.
function EllesmereUI.Conditions_RemoveDmLayout(condGid)
    local cs = GetCondDmStore()
    if not cs or cs.layouts[condGid] == nil then return false end
    cs.layouts[condGid] = nil
    local s = GetDmStore()
    if s and s.active == ("cond:" .. condGid) then
        if not s.baselineLayout or DmApplyLayer(s.baselineLayout) then
            s.active = nil
        end
    end
    if EllesmereUI._dmSessionGid == condGid then
        EllesmereUI._dmSessionGid = nil
        EllesmereUI.SpecOverrides_ApplyDm(_activeSpec or CurrentSpecID(), true)
    end
    return true
end

--- Orphan-heal for a stored profile's DM pointer (import/restore path);
--- same only-heal-dangling policy as SpecOverrides_BmResetActive.
function EllesmereUI.SpecOverrides_DmResetActive(profRoot)
    local s = profRoot and profRoot.specDmOverrides
    if not s or s.active == nil then return end
    local a = s.active
    if type(a) == "string" then
        local gid = tonumber(a:match("^cond:(%d+)$"))
        local cs = profRoot.condDmOverrides
        if not (gid and cs and type(cs.layouts) == "table" and cs.layouts[gid]) then
            s.active = nil
        end
    elseif not (type(s.layouts) == "table" and s.layouts[a]) then
        s.active = nil
    end
end

--- "Customize Unlock Mode" on a CONDITIONAL group card. Only valid while the group
--- is the ACTIVE conditional (WYSIWYG: author the dungeon layout in a dungeon --
--- mirror of "member spec required" for spec groups) and the current spec's own
--- group has NO layout (spec layers void conditionals entirely). First click forks
--- from live (= baseline, since no layer is applied) behind a confirm popup.
function EllesmereUI.Conditions_EnterUnlockForGroup(g)
    if type(g) == "number" then g = EllesmereUI.Conditions_GroupById(g) end
    if not g then return end
    -- Dark Mode groups are values-only: no unlock layer may ever exist for them
    -- (the card never builds the button; this is the belt guard).
    if g.conds and g.conds.darkmode then return end
    if EllesmereUI._unlockModeActive then return end
    local cur = CurrentSpecID()
    if OwnerGid(cur) then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("Your current spec has its own custom unlock mode, so conditional unlock modes never apply to it. Swap to a spec without one to customize this."),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    local activeG = EllesmereUI.Conditions_ActiveGroup and EllesmereUI.Conditions_ActiveGroup()
    if not activeG or activeG.id ~= g.id then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("This conditional is not active right now. Meet one of its conditions first (for example, enter the dungeon) so you can arrange the layout in its real context."),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    local cs = EllesmereUI._CondOv.GetUnlockStore(true)
    local s = GetUnlockStore(true)
    if not cs or not s then return end
    if cs.layouts[g.id] == nil then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("This will create a fully unique unlock mode for this conditional group. Changes made to your default unlock mode will no longer affect it."),
            confirmText = L("Create"),
            cancelText = L("Cancel"),
            onConfirm = function()
                if cs.layouts[g.id] ~= nil then return end
                -- Bank live into its current owner (the baseline: the guards
                -- above ensure no layer is applied), fork it, activate in place
                -- (live is byte-identical to the new layer).
                EllesmereUI.SpecOverrides_HarvestUnlockLayout()
                -- Virgin-store baseline seed: without it there is nothing to
                -- restore when the condition ends (see the spec fork twin in
                -- SpecOverrides_EnterUnlockForGroup).
                if not s.baselineLayout and not s.active then
                    s.baselineLayout = HarvestLayer()
                end
                cs.layouts[g.id] = HarvestLayer()
                s.active = "cond:" .. g.id
                EllesmereUI.Conditions_EnterUnlockForGroup(g)
            end,
        })
        return
    end
    -- Layout exists but is not the live layer yet (fresh login before any
    -- flip): route through the engine so the layer applies first.
    if s.active ~= ("cond:" .. g.id) then
        if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
        if GetUnlockStore().active ~= ("cond:" .. g.id) then return end
    end
    if _editGroup then ExitGroupEdit(true) end
    local panel = EllesmereUI._mainFrame
    if panel and panel:IsShown() then panel:Hide() end
    C_Timer.After(0, function()
        if EllesmereUI._openUnlockMode then EllesmereUI._openUnlockMode() end
    end)
end

-- ---- special unlock entry ------------------------------------------------------

--- "Customize Unlock Mode" on a group card. Only valid when the current spec is
--- a member (unlock always shows the current spec's layout). The FIRST click is
--- the fork moment and asks for confirmation; afterwards it just opens unlock
--- mode, which edits the group's (active) layer.
function EllesmereUI.SpecOverrides_EnterUnlockForGroup(g)
    if type(g) == "number" then g = GroupById(g) end
    if not g then return end
    local cur = CurrentSpecID()
    local member = false
    for _, sid in ipairs(g.specs or {}) do
        if sid == cur then member = true; break end
    end
    if not member then return end
    if EllesmereUI._unlockModeActive then return end
    -- Exclusive layer ownership: when ANOTHER group's layout already provides this
    -- spec's unlock mode, refuse fork creation AND editing here. A fork born under a
    -- non-owner group can never apply to this spec; it sits dead until a group or
    -- layout deletion promotes it, replacing the spec's unlock mode with a stale layout.
    do
        local own = OwnerGid(cur)
        if own and own ~= g.id then
            local og = GroupById(own)
            EllesmereUI:ShowConfirmPopup({
                title = L("Customize Unlock Mode"),
                message = string.format(L("The override group '%s' already provides the custom unlock mode for your current spec. Customize it there, or remove this spec from that group."), (og and og.name) or "?"),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    local s = GetUnlockStore(true)
    if not s then return end
    if s.layouts[g.id] == nil then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("This will create a fully unique unlock mode for this override group. Changes made to your default unlock mode will no longer affect these specs."),
            confirmText = L("Create"),
            cancelText = L("Cancel"),
            onConfirm = function()
                local s2 = GetUnlockStore(true)
                if not s2 or s2.layouts[g.id] ~= nil then return end
                -- Fork from the current live layout: bank live into its owner
                -- first (keeps that layer current).
                EllesmereUI.SpecOverrides_HarvestUnlockLayout()
                -- First-ever layer on a virgin store: capture the shared BASELINE from
                -- the pre-fork live layout (live IS the baseline when no layer is
                -- active). Without it, a non-member spec taking over has nothing to
                -- restore to: the fork's edits stick and the next harvest adopts them
                -- AS the default layout.
                if not s2.baselineLayout and not s2.active then
                    s2.baselineLayout = HarvestLayer()
                end
                -- Seed from the BASELINE whenever any OTHER layer is live (conditional
                -- or another spec group): harvesting live would seed the new fork with
                -- a layout its specs never owned. Live-harvest seeding is only correct
                -- when live IS the baseline -- a spec group voids conditionals
                -- entirely, so its layer must never be born from a dungeon/raid arrangement.
                local fromCond = type(s2.active) == "string"
                local fromOtherGroup = type(s2.active) == "number" and s2.active ~= g.id
                if (fromCond or fromOtherGroup) and s2.baselineLayout then
                    s2.layouts[g.id] = DeepCopy(s2.baselineLayout)
                else
                    s2.layouts[g.id] = HarvestLayer()
                end
                if OwnerGid(cur) == g.id then
                    s2.active = g.id
                    -- Baseline-seeded fork while another layer was showing:
                    -- that layer ceased to apply for this spec, so switch the
                    -- screen to the new (base-identical) layer now.
                    if fromCond or fromOtherGroup then
                        ApplyLayer(s2.layouts[g.id], s2.baselineLayout)
                        _unlockSettleWanted = true
                        EllesmereUI.SpecOverrides_FlushUnlock()
                    end
                end
                if RefreshCardsPopup then RefreshCardsPopup() end
                EllesmereUI.SpecOverrides_EnterUnlockForGroup(g)
            end,
        })
        return
    end
    -- Editing-as and unlock sessions never coexist. Banking the panel session
    -- first also restores canonical live values.
    if _editGroup then ExitGroupEdit(true) end
    local panel = EllesmereUI._mainFrame
    if panel and panel:IsShown() then panel:Hide() end
    C_Timer.After(0, function()
        if EllesmereUI._openUnlockMode then EllesmereUI._openUnlockMode() end
    end)
end

-------------------------------------------------------------------------------
--  CONDITIONAL OVERRIDES integration (engine in EllesmereUI_Conditions.lua). Same
--  machine as spec overrides keyed by conditional GROUP instead of spec: entries
--  carry values = { default = {fkey=v}, [gid] = {fkey=v} }; "no condition active"
--  plays the role of a non-member spec (defaults write). PRECEDENCE: a SPEC-owned
--  fkey (EntryOwning) is off-limits, checked at every conditional write, so
--  later-created spec overrides evict conditional claims silently. Unlock layouts
--  ride the layer engine via the namespaced active pointer ("cond:"..gid); a spec
--  whose group has a layout ignores conditional layouts entirely (first branch of
--  layer resolution). Functions live in one table (file local budget).
-------------------------------------------------------------------------------
-- Contexts excluded from BOTH override systems: no glow overlay, no auto-capture,
-- no slot marks, entries pruned. true = whole module; table = specific pages;
-- nested table = specific sections of a page. (Declared here so both systems bind it.)
local EXCLUDED_CONTEXTS = {
    [PROFILES_MODULE] = true,                  -- Profiles & Presets (incl. list tab)
    ["_EUIPatchNotes"] = true,                 -- Patch Notes
    ["_EUIGlobal"] = true,                     -- Global Settings (whole module)
    -- (Global Settings -> Fonts & Colors stays eligible)
    -- Blacklisted modules (see FOLDER_BLACKLIST): their pages are fully
    -- outside the system, so the editing-as overlay/absorb covers them too.
    ["EllesmereUIBlizzardSkin"]      = true,
    ["EllesmereUIDamageMeters"]      = true,
    ["EllesmereUIMythicTimer"]       = true,
    ["EllesmereUIQuestTracker"]      = true,
    ["EllesmereUIFriends"]           = true,
    ["EllesmereUIBags"]              = true,
    ["EllesmereUIQoL"]               = true,   -- whole module
    ["EllesmereUIAuraBuffReminders"] = true,
    -- CDM: module eligible (bar settings override); these two tabs are
    -- spell/spec-coupled systems with their own per-spec storage.
    ["EllesmereUICooldownManager"] = {
        ["Bar Glows"] = true,
        ["Tracking Bars"] = true,
    },
    -- Raid Frames: HoverCast bindings live in the account-global clickCast
    -- store (never per-profile), so overrides can't apply to them.
    ["EllesmereUIRaidFrames"] = {
        ["HoverCast"] = true,
    },
    -- Unit Frames: Player Aura Bars is a bar-CRUD system (custom bar lists,
    -- shared filter registry, structural per-bar tables), not per-spec slot
    -- values; the whole tab stays outside overrides.
    ["EllesmereUIUnitFrames"] = {
        ["Player Aura Bars"] = true,
    },
}

local Cond = {}
EllesmereUI._CondOv = Cond

-- Condition icon art (media\icons\overrides). battleground uses the horde crest
-- art; the toolbar button rests on the dungeons icon.
Cond.ICON_DIR = "Interface\\AddOns\\EllesmereUI\\media\\icons\\overrides\\"
Cond.ICONS = {
    keybind      = "override-keybinds.png",
    dungeon      = "override-dungeons.png",
    raid         = "override-raid.png",
    arena        = "override-arena.png",
    battleground = "override-horde.png",
    solo         = "override-solo.png",
}

--- True while EITHER override editing session (spec or conditional) is live.
function EllesmereUI.SpecOverrides_EditSessionActive()
    return (_editGroup ~= nil) or (Cond._edit ~= nil)
end

--- Overlay policy for the Raid Frames Buff Manager page, evaluated at page build.
--- nil = no overlay (Default view / no session, or the edited group's fork is live
--- and editable WYSIWYG). Otherwise:
---   { mode = "activate"|"info", kind = "spec"|"cond", gid, text, sub }
--- "info" blocks the whole page: edits there would land in whatever layer is live
--- and bank to the WRONG owner at the next harvest.
function EllesmereUI.SpecOverrides_BmOverlayState()
    local g, kind
    if _editGroup then
        g, kind = _editGroup, "spec"
    elseif Cond._edit then
        g, kind = Cond._edit, "cond"
    else
        return nil
    end
    local cur = CurrentSpecID()
    local s = GetBmStore()
    local liveKey, forked, eligible, text, sub
    if kind == "spec" then
        liveKey = g.id
        forked = (s and s.layouts[g.id] ~= nil) or false
        local member = false
        for _, sid in ipairs(g.specs or {}) do
            if sid == cur then member = true; break end
        end
        local owner = BmOwnerGid(cur)
        eligible = member and (owner == nil or owner == g.id)
        if not member then
            text = L("This group's custom Buff Manager can only be activated or edited while playing one of its specs.")
        elseif not eligible then
            text = L("Another override group already provides the custom Buff Manager for your current spec.")
        end
    else
        liveKey = "cond:" .. g.id
        local cs = GetCondBmStore()
        forked = (cs and cs.layouts[g.id] ~= nil) or false
        -- No real-context requirement: unlike unlock layouts these are plain
        -- settings and the session swap (BmSessionEngage) makes the fork live
        -- anywhere. Only the spec-wins precedence gate remains.
        local specOwner = BmOwnerGid(cur) ~= nil
        eligible = not specOwner
        if specOwner then
            text = L("Your current spec has its own custom Buff Manager, so conditional Buff Managers never apply to it.")
        end
    end
    if forked and eligible then
        -- PURE query: report a stale live pointer (fresh login ordering) via the second
        -- return; BmPagePrelude performs the heal/session engage. A session-applied
        -- fork IS the live layer even though the runtime pointer does not say so.
        local liveNow = EllesmereUI._bmSessionGid
            and ("cond:" .. EllesmereUI._bmSessionGid) or (s and s.active)
        return nil, liveNow ~= liveKey
    end
    if not eligible then
        return { mode = "info", kind = kind, gid = g.id, text = text, sub = sub }
    end
    return {
        mode = "activate", kind = kind, gid = g.id,
        text = kind == "spec"
            and L("This will create a fully unique Buff Manager for this override group. Your current Buff Manager settings are copied as its starting point, and changes made to your default Buff Manager will no longer affect these specs.")
            or L("This will create a fully unique Buff Manager for this conditional group. Your current Buff Manager settings are copied as its starting point, and changes made to your default Buff Manager will no longer affect it."),
    }
end

--- Page-build entry point for the RF Buff Manager page: call FIRST, before any
--- content builds. Heals a stale live layer (so the page renders the edited
--- group's fork; the heal skips the page repaint because THIS build is the
--- repaint) and returns the overlay state (nil = no overlay).
function EllesmereUI.SpecOverrides_BmPagePrelude()
    -- Outside any session: ensure the runtime layer the page is about to edit is
    -- actually LIVE. A spec owning a BM fork gets it auto-activated here; a stale
    -- pointer (login ordering, interrupted session) heals instead of letting the
    -- page edit an off-screen layer ("changing settings does nothing" with no error).
    if not _editGroup and not Cond._edit then
        EllesmereUI.SpecOverrides_ApplyBm(CurrentSpecID(), false, true)
    end
    -- Editing-as-conditional with an existing fork that is not the runtime layer
    -- (condition not met right now): engage the session swap so the page and
    -- on-screen frames show the fork being edited. Spec-wins gate still blocks
    -- when a spec owner exists.
    if Cond._edit then
        local cs = GetCondBmStore()
        if cs and cs.layouts[Cond._edit.id]
           and EllesmereUI._bmSessionGid ~= Cond._edit.id
           and not BmOwnerGid(CurrentSpecID()) then
            local s = GetBmStore()
            if not (s and s.active == ("cond:" .. Cond._edit.id)) then
                BmSessionEngage(Cond._edit.id)
            end
        end
    end
    local state, needHeal = EllesmereUI.SpecOverrides_BmOverlayState()
    if needHeal then
        EllesmereUI.SpecOverrides_ApplyBm(CurrentSpecID(), true, true)
    end
    -- Re-evaluate passive chrome on EVERY BM page build: fork deletion,
    -- activation, and heals all rebuild this page without a SelectPage.
    if EllesmereUI.SpecOverrides_UpdateBmPassiveChrome then
        EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    end
    return state
end

--- Creates the edited group's BM fork (the overlay's Activate click, no second
--- popup -- the overlay text IS the confirmation). Re-validates every gate (race
--- guard), banks live into its current owner, then seeds: spec forks born while a
--- conditional BM layer is live seed from the BASELINE (spec layers void
--- conditionals -- never fork a dungeon state); everything else seeds from live.
function EllesmereUI.SpecOverrides_ActivateBm(kind, gid)
    local state = EllesmereUI.SpecOverrides_BmOverlayState()
    if not state or state.mode ~= "activate" or state.kind ~= kind
       or state.gid ~= gid then return end
    local cur = CurrentSpecID()
    EllesmereUI.SpecOverrides_HarvestBmLayout()
    -- Virgin-store baseline seed: the first-ever BM layer must capture the
    -- shared baseline from the pre-fork live state (live IS the baseline when
    -- no layer is active), or leaving the fork later has nothing to restore and
    -- the next harvest adopts the fork's edits as the default Buff Manager.
    do
        local s = GetBmStore(true)
        if s and not s.baselineLayout and not s.active then
            s.baselineLayout = BmHarvestLayer()
        end
    end
    if kind == "spec" then
        local s = GetBmStore(true)
        if not s or s.layouts[gid] ~= nil then return end
        local fromCond = type(s.active) == "string"
        if fromCond and s.baselineLayout then
            s.layouts[gid] = DeepCopy(s.baselineLayout)
        else
            local snap = BmHarvestLayer()
            if not snap then return end
            s.layouts[gid] = snap
        end
        if BmOwnerGid(cur) == gid then
            s.active = gid
            -- Baseline-seeded fork while a conditional was live: the
            -- conditional ceased to exist for this spec, so swap the screen to
            -- the new (base-identical) layer. RefreshPage below is the repaint.
            if fromCond then BmApplyLayer(s.layouts[gid], true) end
        end
    else
        local cs = GetCondBmStore(true)
        if not cs or cs.layouts[gid] ~= nil then return end
        local s = GetBmStore(true)
        -- Seed from the BASELINE when any layer is live (another conditional
        -- applied right now); live IS the baseline only when nothing is.
        local snap
        if s and s.active and s.baselineLayout then
            snap = DeepCopy(s.baselineLayout)
        else
            snap = BmHarvestLayer()
            if not snap then return end
        end
        cs.layouts[gid] = snap
        local ag = EllesmereUI.Conditions_ActiveGroup and EllesmereUI.Conditions_ActiveGroup()
        if ag and ag.id == gid then
            -- In-context creation: the fork is the runtime layer from here.
            if s then s.active = "cond:" .. gid end
        else
            -- Out-of-context creation: session-scoped apply only. The runtime
            -- pointer must never point at a layer whose condition is not met.
            BmSessionEngage(gid)
        end
    end
    if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
end

--- Overlay policy for the Debuff Manager page (mirror of BmOverlayState;
--- same eligibility rules and returns).
function EllesmereUI.SpecOverrides_DmOverlayState()
    local g, kind
    if _editGroup then
        g, kind = _editGroup, "spec"
    elseif Cond._edit then
        g, kind = Cond._edit, "cond"
    else
        return nil
    end
    local cur = CurrentSpecID()
    local s = GetDmStore()
    local liveKey, forked, eligible, text, sub
    if kind == "spec" then
        liveKey = g.id
        forked = (s and s.layouts[g.id] ~= nil) or false
        local member = false
        for _, sid in ipairs(g.specs or {}) do
            if sid == cur then member = true; break end
        end
        local owner = DmOwnerGid(cur)
        eligible = member and (owner == nil or owner == g.id)
        if not member then
            text = L("This group's custom Debuff Manager can only be activated or edited while playing one of its specs.")
        elseif not eligible then
            text = L("Another override group already provides the custom Debuff Manager for your current spec.")
        end
    else
        liveKey = "cond:" .. g.id
        local cs = GetCondDmStore()
        forked = (cs and cs.layouts[g.id] ~= nil) or false
        local specOwner = DmOwnerGid(cur) ~= nil
        eligible = not specOwner
        if specOwner then
            text = L("Your current spec has its own custom Debuff Manager, so conditional Debuff Managers never apply to it.")
        end
    end
    if forked and eligible then
        local liveNow = EllesmereUI._dmSessionGid
            and ("cond:" .. EllesmereUI._dmSessionGid) or (s and s.active)
        return nil, liveNow ~= liveKey
    end
    if not eligible then
        return { mode = "info", kind = kind, gid = g.id, text = text, sub = sub }
    end
    return {
        mode = "activate", kind = kind, gid = g.id,
        text = kind == "spec"
            and L("This will create a fully unique Debuff Manager for this override group. Your current Debuff Manager settings are copied as its starting point, and changes made to your default Debuff Manager will no longer affect these specs.")
            or L("This will create a fully unique Debuff Manager for this conditional group. Your current Debuff Manager settings are copied as its starting point, and changes made to your default Debuff Manager will no longer affect it."),
    }
end

--- Page-build entry point for the Debuff Manager page (mirror of
--- BmPagePrelude): call FIRST, before any content builds.
function EllesmereUI.SpecOverrides_DmPagePrelude()
    if not _editGroup and not Cond._edit then
        EllesmereUI.SpecOverrides_ApplyDm(CurrentSpecID(), false, true)
    end
    if Cond._edit then
        local cs = GetCondDmStore()
        if cs and cs.layouts[Cond._edit.id]
           and EllesmereUI._dmSessionGid ~= Cond._edit.id
           and not DmOwnerGid(CurrentSpecID()) then
            local s = GetDmStore()
            if not (s and s.active == ("cond:" .. Cond._edit.id)) then
                DmSessionEngage(Cond._edit.id)
            end
        end
    end
    local state, needHeal = EllesmereUI.SpecOverrides_DmOverlayState()
    if needHeal then
        EllesmereUI.SpecOverrides_ApplyDm(CurrentSpecID(), true, true)
    end
    if EllesmereUI.SpecOverrides_UpdateBmPassiveChrome then
        EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    end
    return state
end

--- Creates the edited group's DM fork (mirror of SpecOverrides_ActivateBm,
--- including the virgin-store baseline seed and conditional seeding rules).
function EllesmereUI.SpecOverrides_ActivateDm(kind, gid)
    local state = EllesmereUI.SpecOverrides_DmOverlayState()
    if not state or state.mode ~= "activate" or state.kind ~= kind
       or state.gid ~= gid then return end
    local cur = CurrentSpecID()
    EllesmereUI.SpecOverrides_HarvestDmLayout()
    do
        local s = GetDmStore(true)
        if s and not s.baselineLayout and not s.active then
            s.baselineLayout = DmHarvestLayer()
        end
    end
    if kind == "spec" then
        local s = GetDmStore(true)
        if not s or s.layouts[gid] ~= nil then return end
        local fromCond = type(s.active) == "string"
        if fromCond and s.baselineLayout then
            s.layouts[gid] = DeepCopy(s.baselineLayout)
        else
            local snap = DmHarvestLayer()
            if not snap then return end
            s.layouts[gid] = snap
        end
        if DmOwnerGid(cur) == gid then
            s.active = gid
            if fromCond then DmApplyLayer(s.layouts[gid], true) end
        end
    else
        local cs = GetCondDmStore(true)
        if not cs or cs.layouts[gid] ~= nil then return end
        local s = GetDmStore(true)
        local snap
        if s and s.active and s.baselineLayout then
            snap = DeepCopy(s.baselineLayout)
        else
            snap = DmHarvestLayer()
            if not snap then return end
        end
        cs.layouts[gid] = snap
        local ag = EllesmereUI.Conditions_ActiveGroup and EllesmereUI.Conditions_ActiveGroup()
        if ag and ag.id == gid then
            if s then s.active = "cond:" .. gid end
        else
            DmSessionEngage(gid)
        end
    end
    if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
end

--- True for module folders excluded wholesale from the override systems (drives
--- the sidebar lock during an editing session). Includes the management
--- surfaces (Profiles & Presets, Patch Notes, Global Settings): they lock like
--- every other excluded module.
function EllesmereUI.SpecOverrides_ModuleExcluded(folder)
    return (type(folder) == "string" and EXCLUDED_CONTEXTS[folder] == true)
        or false
end

--- True when a module page is excluded (page-scoped entry, or the whole
--- module). Drives the page-tab lock while a session is active.
function EllesmereUI.SpecOverrides_PageExcluded(module, page)
    local ex = module and EXCLUDED_CONTEXTS[module]
    if ex == true then return true end
    if type(ex) == "table" and page then return ex[page] == true end
    return false
end

function Cond.GetStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    if not prof.condOverrides then
        if not create then return nil end
        prof.condOverrides = {}
    end
    return prof.condOverrides
end

function Cond.GetUnlockStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.condUnlockOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.condUnlockOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

-- fkey -> entry index over the conditional store (parallel to _fkeyIndex,
-- never merged into it: EntryOwning stays spec-only by definition).
Cond._fkeyIndex = nil
function Cond.RebuildIndex()
    Cond._fkeyIndex = {}
    for _, e in ipairs(Cond.GetStore() or {}) do
        if e.values and e.values.default then
            for fkey in pairs(e.values.default) do
                Cond._fkeyIndex[fkey] = e
            end
        end
    end
end
function Cond.EntryOwning(fkey)
    if not Cond._fkeyIndex then Cond.RebuildIndex() end
    return Cond._fkeyIndex[fkey]
end

--- Writes the effective conditional values for the given active group (nil = no
--- condition: defaults). Mirrors WriteSpecValues plus the spec-wins gate.
--- forSession: painting an EDITING session's view (conditional-over-default),
--- where the conditional's own values must show even for fkeys the SPEC store
--- also tracks. Runtime applies (transitions, overlays, restores) omit it --
--- spec overrides always win at apply time.
function Cond.WriteValues(gid, forSession)
    local store = Cond.GetStore()
    if not store or #store == 0 then return nil end
    local touched = nil
    for _, entry in ipairs(store) do
        local map = gid and entry.values[gid] or nil
        for fkey, def in pairs(entry.values.default) do
            if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
               and (forSession or not EntryOwning(fkey)) then
                local v = def
                if map and map[fkey] ~= nil then v = map[fkey] end
                if v == NIL_SENT then v = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues.
                local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
                local cur = ReadLive(fkey)
                -- Table values are never written or compared: a stored table
                -- reference NEVER equals live, so it would register a "write"
                -- and force a full module refresh on EVERY transition.
                if not nilPoison and type(v) ~= "table" and type(cur) ~= "table" and cur ~= v then
                    if WriteLive(fkey, v) then
                        local folder = SplitFKey(fkey)
                        if folder then
                            touched = touched or {}
                            touched[folder] = true
                        end
                    end
                end
            end
        end
    end
    return touched
end

--- Writes an entry's recorded DEFAULT values back to live. Called right BEFORE a
--- conditional entry is removed: a conditional's values sit in live for as long as
--- its condition holds, including while the options panel is open (the Default
--- Editing Mode swap covers the SPEC store only), so dropping the entry without
--- this would silently turn the override's values into the profile's own
--- settings. The spec delete flow needs no equivalent (live already holds the
--- shared defaults there); its one path that CAN hit this, the orphan drop in
--- PruneOrphanEntries, carries the same restore. Guards mirror Cond.WriteValues
--- exactly, so this only writes keys the conditional overlay could have written
--- (blacklisted/match-owned/SPEC-owned/unloaded-module skipped; NIL_SENT on a
--- defaults-backed key is harvest residue, not a real removal).
--- touched: folder-set accumulator; the caller refreshes once.
function Cond.RestoreEntryDefaults(entry, touched)
    local def = entry.values and entry.values.default
    if not def then return end
    for fkey, dv in pairs(def) do
        if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
           and not EntryOwning(fkey) and FKeyLoaded(fkey) then
            local v = (dv == NIL_SENT) and nil or dv
            local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
            local cur = ReadLive(fkey)
            if not nilPoison and type(v) ~= "table" and type(cur) ~= "table"
               and cur ~= v then
                if WriteLive(fkey, v) then
                    local folder = SplitFKey(fkey)
                    if folder then touched[folder] = true end
                end
            end
        end
    end
end

--- Garbage-collects conditional fkeys no group map holds a value for (the
--- diff-semantics harvests clear reverts at bank time), and entries left empty.
--- NEVER judges by equality against the default: the default is movable, and
--- equality-pruning against a moved/poisoned default silently deletes
--- intentional override values.
function Cond.PruneRedundant()
    local store = Cond.GetStore()
    if not store then return end
    local changed = false
    for i = #store, 1, -1 do
        local e = store[i]
        local def = e.values and e.values.default
        if def then
            for fkey in pairs(def) do
                local held = false
                for k, m in pairs(e.values) do
                    if k ~= "default" and type(m) == "table" and m[fkey] ~= nil then
                        held = true
                        break
                    end
                end
                if not held then
                    def[fkey] = nil
                    changed = true
                end
            end
            if not next(def) then
                table.remove(store, i)
                changed = true
            end
        end
    end
    if changed then
        Cond.RebuildIndex()
        RequestGoldWalk()
    end
end

--- Banks live values into the given group's maps (nil = the default maps) for
--- every fkey the conditional store tracks. Mirrors the spec Harvest. Group
--- maps use diff semantics (bank when live differs from the recorded default,
--- clear when it matches) so a transition harvest never seeds default-equal
--- junk maps onto entries the group never customized; the default maps
--- themselves always track live verbatim.
function Cond.Harvest(gid)
    local store = Cond.GetStore()
    if not store or #store == 0 then return end
    -- Defaults may only rebank over CANONICAL live data: while any editing session or
    -- the Default view holds swapped values, banking poisons the recorded defaults.
    -- (HarvestCurrent orders its call after the canonical restore; this is the belt
    -- for any other caller.)
    local sessionLive = _defaultView or _editGroup or Cond._edit
    -- SPEC-OWNED fkeys are never harvested in either direction: while the spec store
    -- tracks an fkey, live reflects SPEC values (runtime applies skip it), so banking
    -- live here would poison the conditional's default/group maps with spec-scoped
    -- values; Cond values stay dormant until the spec override is removed. TABLE-typed
    -- live values are never banked either (structure change; mirror of HarvestMap --
    -- would alias store to profile).
    for _, entry in ipairs(store) do
        if gid then
            local map = entry.values[gid]
            for fkey, dv in pairs(entry.values.default) do
                -- FKeyLoaded: a disabled module reads nil for every path, which would
                -- poison the maps with deletion markers. MatchOwnedFKey: match-engine
                -- writes never bank (mirrors spec-side Harvest; Cond.WriteValues skips
                -- these at apply time).
                if not EntryOwning(fkey) and FKeyLoaded(fkey)
                   and not MatchOwnedFKey(fkey) then
                    local live = ReadLive(fkey)
                    if type(live) ~= "table" then
                        local defVal = (dv == NIL_SENT) and nil or dv
                        if live == defVal then
                            -- Equality is NOT proof of a revert outside an edit session
                            -- (the default may have been edited onto the group's
                            -- value): retain the held value. Real reverts clear in
                            -- Cond.HarvestEdit, which has the session snapshot to prove them.
                        else
                            if not map then map = {}; entry.values[gid] = map end
                            map[fkey] = (live == nil) and NIL_SENT or live
                        end
                    end
                end
            end
            if map and not next(map) then entry.values[gid] = nil end
        elseif not sessionLive then
            local map = entry.values.default
            for fkey in pairs(map) do
                if not EntryOwning(fkey) and FKeyLoaded(fkey)
                   and not MatchOwnedFKey(fkey) then
                    local live = ReadLive(fkey)
                    if type(live) ~= "table" then
                        map[fkey] = live == nil and NIL_SENT or live
                    end
                end
            end
        end
    end
    Cond.PruneRedundant()
end

--- Values-only overlay for profile-apply paths (RefreshAllAddons): re-paints
--- the applied conditional group's values after spec values. While an
--- editing-as-conditional session holds swapped values live, generic re-applies
--- must preserve the session's view instead.
function Cond.ApplyValues()
    local gid
    if Cond._edit then
        gid = Cond._edit.id
    else
        gid = EllesmereUI.Conditions_AppliedGid and EllesmereUI.Conditions_AppliedGid()
    end
    -- forSession while a session is open: without it the spec-wins gate skips
    -- spec-owned fkeys and the session view is never repainted over whatever a
    -- generic re-apply just wrote there. Returns the touched folder set so
    -- callers outside RefreshAllAddons (the FlushUnlock value overlay) can
    -- refresh what actually changed.
    return Cond.WriteValues(gid, Cond._edit ~= nil)
end

-------------------------------------------------------------------------------
--  Profile-import store merge + default re-baseline
-------------------------------------------------------------------------------

--- RETIRED, no callers: ImportProfile uses ALL-OR-NOTHING override semantics (take
--- the exporter's complete override system or keep the recipient's; see the Include
--- Overrides controls). Reference only -- do NOT re-wire: the partition/union/remap
--- machinery here is the bug surface that redesign deliberately eliminated.
--- Merged PER-MODULE into a deep copy of the CURRENT profile: overrides ride with
--- their addon and fully replace every imported module; non-imported modules keep
--- the recipient's untouched.
---   * value entries (spec + cond): partitioned by each fkey's addon FOLDER. Imported
---     folders: recipient entries shed those fkeys (entry dropped when emptied),
---     incoming entries come in verbatim. Non-imported: recipient survives, incoming
---     discarded. Defaults are consistent by construction (one exporter); the
---     ApplyProfileData re-bank (SpecOverrides_RebaselineDefaults) covers strings
---     exported while an override was applied.
---   * groups: recipient groups untouched; incoming groups come along ONLY when
---     something surviving the partition references them, so a subset import can't
---     fill the dropdown with do-nothing groups. Ids re-number on collision with
---     every reference remapped (entry group fields, per-gid value maps, fork
---     layout keys, active pointers).
---   * unlock layout forks: whole-layout snapshots spanning ALL modules, so they
---     can't ride per-module. Full import: recipient's dropped, incoming's taken
---     when carried. Partial/subset (incoming.partialImport, stamped by the import
---     dialog on deselection AND by ExportProfile on subset exports) and
---     incoming.layoutExcluded ("Include layout" OFF at either end): recipient's
---     KEPT, incoming's never taken -- stripped-nil must never read as "exporter
---     had none, wipe yours".
---   * Buff Manager forks: Raid Frames data, so per-module -- replaced (or cleared)
---     when RF is imported, kept when it is not.
function EllesmereUI.SpecOverrides_MergeImportedStores(merged, incoming)
    local function maxNumericId(groups)
        local m = 0
        for _, g in ipairs(groups or {}) do
            if type(g.id) == "number" and g.id > m then m = g.id end
        end
        return m
    end

    -- Equivalence comparators: importing your OWN export must collapse each incoming
    -- group onto the recipient's original instead of appending a re-numbered twin
    -- (else the original survives as a dead card while the twin holds the values).
    local function sameSpecGroup(a, b)
        if (a.name or "") ~= (b.name or "") then return false end
        local as, bs = a.specs or {}, b.specs or {}
        if #as ~= #bs then return false end
        local set = {}
        for _, id in ipairs(as) do set[id] = true end
        for _, id in ipairs(bs) do
            if not set[id] then return false end
        end
        return true
    end
    local function sameCondGroup(a, b)
        if (a.name or "") ~= (b.name or "") then return false end
        if (a.key or "") ~= (b.key or "") then return false end
        local ac, bc = a.conds or {}, b.conds or {}
        for k in pairs(ac) do if not bc[k] then return false end end
        for k in pairs(bc) do if not ac[k] then return false end end
        return true
    end

    -- Union group lists; returns (unioned, remap oldIncomingId -> newId). An
    -- incoming group EQUIVALENT to an existing one (per `same`) adopts the
    -- existing group's id (remapped) and pushes its icon (incoming priority);
    -- only genuinely new groups append, re-numbered on id collision.
    local function unionGroups(existing, incomingGroups, same)
        local remap = {}
        if type(incomingGroups) ~= "table" then return existing, remap end
        local out, used = {}, {}
        for _, g in ipairs(existing or {}) do
            out[#out + 1] = g
            if type(g.id) == "number" then used[g.id] = true end
        end
        local nextId = maxNumericId(existing)
        local incMax = maxNumericId(incomingGroups)
        if incMax > nextId then nextId = incMax end
        -- Each existing group may be matched by ONE incoming group per union: users can
        -- hold two groups with identical name+specs/conds, and both twins matching the
        -- same target would collide their remapped gid references (pairs-order data
        -- loss in cond value maps / fork keys). Claimed-once collapses twin pairs onto
        -- their own originals; an unmatched extra falls through to the append path.
        local claimed = {}
        for _, g in ipairs(incomingGroups) do
            local match
            if same then
                for _, eg in ipairs(existing or {}) do
                    if not claimed[eg] and same(eg, g) then match = eg; break end
                end
            end
            if match then
                claimed[match] = true
                if g.id ~= match.id then remap[g.id] = match.id end
                -- Type guard: a corrupt/hand-edited string with a non-table
                -- icon must not abort the whole import inside DeepCopy.
                if type(g.icon) == "table" then match.icon = DeepCopy(g.icon) end
            else
                local ng = DeepCopy(g)
                if type(ng.id) == "number" and used[ng.id] then
                    nextId = nextId + 1
                    remap[g.id] = nextId
                    ng.id = nextId
                end
                if type(ng.id) == "number" then used[ng.id] = true end
                out[#out + 1] = ng
            end
        end
        return out, remap, nextId
    end

    -- Imported-folder set: the per-module partition key for value entries.
    local importedFolders = {}
    if type(incoming.addons) == "table" then
        for folder in pairs(incoming.addons) do importedFolders[folder] = true end
    end
    -- Stamped by the import dialog when any module checkbox was deselected.
    local partial = incoming.partialImport == true

    -- Per-module entry partition: strip fkeys of the given polarity from an entry
    -- list. keepImported=false keeps only NON-imported-folder fkeys (recipient side,
    -- filtered in place -- merged is already a deep copy); true keeps only
    -- imported-folder fkeys (incoming side, deep-copied). Entries emptied by the
    -- strip are dropped. Partition is per-FKEY (via SplitFKey), not per
    -- entry.module: the fkey's folder decides which addon a setting rides with.
    local function partitionEntries(entries, keepImported)
        local out = {}
        for _, e in ipairs(entries or {}) do
            local ne = keepImported and DeepCopy(e) or e
            local def = ne.values and ne.values.default
            if def then
                for fkey in pairs(def) do
                    local folder = SplitFKey(fkey)
                    local isImported = folder and importedFolders[folder] or false
                    if isImported ~= keepImported then
                        def[fkey] = nil
                        for k, m in pairs(ne.values) do
                            if k ~= "default" and type(m) == "table" then m[fkey] = nil end
                        end
                    end
                end
                if next(def) ~= nil then out[#out + 1] = ne end
            end
        end
        return out
    end

    -- Re-keys a cond entry's per-gid value maps after the group union.
    local function remapEntryValues(e, remap)
        if not next(remap) or type(e.values) ~= "table" then return end
        local nv = {}
        for k, m in pairs(e.values) do
            if k ~= "default" and remap[k] then nv[remap[k]] = m else nv[k] = m end
        end
        e.values = nv
    end

    local function remapKeys(map, remap)
        if type(map) ~= "table" or not next(remap) then return map end
        local out = {}
        for k, v in pairs(map) do out[remap[k] or k] = v end
        return out
    end

    local function remapActive(active, sRemap, cRemap)
        if type(active) == "number" then return sRemap[active] or active end
        if type(active) == "string" then
            local cg = tonumber(active:match("^cond:(%d+)$"))
            if cg and cRemap[cg] then return "cond:" .. cRemap[cg] end
        end
        return active
    end

    -- Partition both stores' entries per module: recipient keeps only
    -- non-imported folders, incoming contributes only imported folders. Runs
    -- even when the string carries no entries (an imported module with no
    -- incoming overrides clears the recipient's for it -- replaced wholesale).
    local keptSpec = partitionEntries(merged.specOverrides, false)
    local incSpec  = partitionEntries(incoming.specOverrides, true)
    local keptCond = partitionEntries(merged.condOverrides, false)
    local incCond  = partitionEntries(incoming.condOverrides, true)

    -- Only incoming GROUPS that still carry something come along: taken when a
    -- SURVIVING incoming entry references it, or an incoming fork passing its gate
    -- below does -- a subset import of one module must not populate the dropdown with
    -- the exporter's unrelated groups as dead cards. Recipient groups are never touched.
    local rfImported = importedFolders["EllesmereUIRaidFrames"] and true or false
    -- layoutExcluded (stamped by ExportProfile / the import dialog when
    -- "Include layout" is OFF): layout was deliberately excluded, so the fork
    -- stores must be KEPT from the base copy -- taking the branch below with
    -- nil incoming tables would wipe the recipient's group layouts.
    local takeUnlockForks = not partial and incoming.layoutExcluded ~= true
    local specNeeded, condNeeded = {}, {}
    for _, e in ipairs(incSpec) do
        if e.group ~= nil then specNeeded[e.group] = true end
    end
    for _, e in ipairs(incCond) do
        if e.group ~= nil then condNeeded[e.group] = true end
        if type(e.values) == "table" then
            for k in pairs(e.values) do
                if k ~= "default" then condNeeded[k] = true end
            end
        end
    end
    -- Forks reference groups via layout keys and active pointers (a spec
    -- store's active can point at a COND group via "cond:N").
    local function noteForkGids(store, needed, condNeededToo)
        if type(store) ~= "table" then return end
        for gid in pairs(store.layouts or {}) do needed[gid] = true end
        for gid in pairs(store.groups or {}) do needed[gid] = true end   -- legacy shape
        local a = store.active
        if type(a) == "number" then needed[a] = true end
        if condNeededToo and type(a) == "string" then
            local cg = tonumber(a:match("^cond:(%d+)$"))
            if cg then condNeededToo[cg] = true end
        end
    end
    if takeUnlockForks then
        noteForkGids(incoming.specUnlockOverrides, specNeeded, condNeeded)
        noteForkGids(incoming.condUnlockOverrides, condNeeded)
    end
    if rfImported then
        noteForkGids(incoming.specBmOverrides, specNeeded, condNeeded)
        noteForkGids(incoming.condBmOverrides, condNeeded)
        noteForkGids(incoming.specDmOverrides, specNeeded, condNeeded)
        noteForkGids(incoming.condDmOverrides, condNeeded)
    end

    local function filterGroups(groups, needed)
        local out = {}
        for _, g in ipairs(groups or {}) do
            if g.id ~= nil and needed[g.id] then out[#out + 1] = g end
        end
        return out
    end

    -- Group unions (referenced incoming groups only) + id remaps.
    local specRemap, condRemap = {}, {}
    if incoming.specOverrideGroups then
        local wanted = filterGroups(incoming.specOverrideGroups, specNeeded)
        if #wanted > 0 then
            local unioned, remap, nextId = unionGroups(merged.specOverrideGroups, wanted, sameSpecGroup)
            merged.specOverrideGroups = unioned
            specRemap = remap
            merged.specOverrideNextId = math.max(
                merged.specOverrideNextId or 0, incoming.specOverrideNextId or 0, nextId or 0)
        end
    end
    if incoming.condOverrideGroups then
        local wanted = filterGroups(incoming.condOverrideGroups, condNeeded)
        if #wanted > 0 then
            local unioned, remap = unionGroups(merged.condOverrideGroups, wanted, sameCondGroup)
            merged.condOverrideGroups = unioned
            condRemap = remap
        end
    end

    -- Apply the remaps to the surviving incoming entries, then concatenate
    -- with the recipient's kept entries.
    for _, e in ipairs(incSpec) do
        if e.group and specRemap[e.group] then e.group = specRemap[e.group] end
        keptSpec[#keptSpec + 1] = e
    end
    for _, e in ipairs(incCond) do
        if e.group and condRemap[e.group] then e.group = condRemap[e.group] end
        remapEntryValues(e, condRemap)
        keptCond[#keptCond + 1] = e
    end
    merged.specOverrides = keptSpec
    merged.condOverrides = keptCond

    -- Unlock layout forks: cross-module whole-layout snapshots. Full import:
    -- drop kept, take incoming (remapped; old-format strings may carry the
    -- legacy {groups, baseline, applied} shape, remapped too). Partial import:
    -- keep the recipient's, never take incoming.
    if takeUnlockForks then
        if incoming.specUnlockOverrides then
            local t = DeepCopy(incoming.specUnlockOverrides)
            t.layouts = remapKeys(t.layouts, specRemap)
            t.groups  = remapKeys(t.groups, specRemap)
            if type(t.applied) == "table" and next(specRemap) then
                for el, gid in pairs(t.applied) do t.applied[el] = specRemap[gid] or gid end
            end
            t.active = remapActive(t.active, specRemap, condRemap)
            merged.specUnlockOverrides = t
        else
            merged.specUnlockOverrides = nil
        end
        if incoming.condUnlockOverrides then
            local t = DeepCopy(incoming.condUnlockOverrides)
            t.layouts = remapKeys(t.layouts, condRemap)
            merged.condUnlockOverrides = t
        else
            merged.condUnlockOverrides = nil
        end
    end

    -- Buff Manager forks: Raid Frames data, so per-module rule -- full
    -- replacement when RF is imported, untouched when not.
    if importedFolders["EllesmereUIRaidFrames"] then
        if incoming.specBmOverrides then
            local t = DeepCopy(incoming.specBmOverrides)
            t.layouts = remapKeys(t.layouts, specRemap)
            t.active = remapActive(t.active, specRemap, condRemap)
            merged.specBmOverrides = t
        else
            merged.specBmOverrides = nil
        end
        if incoming.condBmOverrides then
            local t = DeepCopy(incoming.condBmOverrides)
            t.layouts = remapKeys(t.layouts, condRemap)
            merged.condBmOverrides = t
        else
            merged.condBmOverrides = nil
        end
        if incoming.specDmOverrides then
            local t = DeepCopy(incoming.specDmOverrides)
            t.layouts = remapKeys(t.layouts, specRemap)
            t.active = remapActive(t.active, specRemap, condRemap)
            merged.specDmOverrides = t
        else
            merged.specDmOverrides = nil
        end
        if incoming.condDmOverrides then
            local t = DeepCopy(incoming.condDmOverrides)
            t.layouts = remapKeys(t.layouts, condRemap)
            merged.condDmOverrides = t
        else
            merged.condDmOverrides = nil
        end
    end

    -- NO post-import default re-bank. Imported entries carry the exporter's recorded
    -- values.default, consistent with the imported addon blobs by construction
    -- (per-folder partition above). A RebaselineDefaults follow-up here would
    -- overwrite those defaults with the imported LIVE blob -- the exporter's CURRENT
    -- SPEC's override values, not defaults -- destroying the true defaults and
    -- bleeding one spec's values into every unassigned spec. RebaselineDefaults stays
    -- defined but must NEVER be wired back into the import flow.
end

--- Rewrites override entry DEFAULT maps (both stores) from the live profile, then
--- rebuilds both fkey indexes. Runs once right after a profile import lands: kept
--- entries' defaults were captured against the PREVIOUS profile, and restoring
--- those stale values when an override deactivates would permanently overwrite the
--- imported profile's own settings. Per-spec/per-group values are absolute and
--- untouched. MUST run before the overlays re-apply (SpecOverrides_ApplyValues),
--- while live still holds the pure imported values. folderSet limits the re-bank
--- to the given addon folders (partial imports: kept folders' profile tables can
--- hold ACTIVE override values, which must never be banked as defaults); nil = all.
function EllesmereUI.SpecOverrides_RebaselineDefaults(folderSet)
    -- Never re-bank while an editing view holds swapped values live (the import
    -- flow closes sessions first; this guards any other caller).
    if _editGroup or _defaultView or Cond._edit then return end
    local function Rebank(store)
        for _, entry in ipairs(store or {}) do
            local def = entry.values and entry.values.default
            if def then
                for fkey in pairs(def) do
                    local folder = SplitFKey(fkey)
                    -- Folder filter + loaded-module guard: an unloaded child
                    -- addon has no Lite DB, so ReadLive returns nil for EVERY
                    -- fkey and nil-poisons the whole default map.
                    if folder and (not folderSet or folderSet[folder]) and DBFor(folder) then
                        local live = ReadLive(fkey)
                        -- Table values are never banked (aliasing/reference-
                        -- compare policy); keep the stored default.
                        if type(live) ~= "table" then
                            def[fkey] = (live == nil) and NIL_SENT or live
                        end
                    end
                end
            end
        end
    end
    Rebank(GetStore())
    Rebank(Cond.GetStore())
    RebuildFKeyIndex()
    Cond.RebuildIndex()
end

--- Prune: strip blacklisted folders, spec-owned fkeys (spec-wins eviction),
--- excluded-context entries, and maps for deleted groups; drop empty entries.
function Cond.PruneEntries()
    local store = Cond.GetStore()
    if not store then return end
    local removed = false
    for i = #store, 1, -1 do
        local e = store[i]
        local drop = false
        if e.module then
            local ex = EXCLUDED_CONTEXTS[e.module]
            if ex == true then drop = true
            elseif type(ex) == "table" and e.page then
                local pex = ex[e.page]
                if pex == true then drop = true
                elseif type(pex) == "table" and e.section and pex[e.section] then drop = true end
            end
        end
        if not drop and e.group ~= nil
           and not (EllesmereUI.Conditions_GroupById and EllesmereUI.Conditions_GroupById(e.group)) then
            drop = true
        end
        if not drop and e.values and e.values.default then
            -- Blacklisted paths strip; SPEC-OWNED fkeys are deliberately KEPT (dormant):
            -- spec wins at runtime, but the conditional's value must survive so it
            -- resumes if the spec override is removed -- stripping here would
            -- permanently destroy it the moment the setting gains a spec override.
            for fkey in pairs(e.values.default) do
                if BlacklistedFKey(fkey) then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then m[fkey] = nil end
                    end
                    removed = true
                end
            end
            if not next(e.values.default) then drop = true end
        end
        if drop then
            table.remove(store, i)
            removed = true
        end
    end
    if removed then Cond.RebuildIndex() end
end

--- The engine's transition handler: harvest the outgoing group, overlay the
--- incoming one, swap unlock layers, refresh. Returns false when the value
--- system is mid-swap (spec transition / edit sessions); the engine retries on
--- its next signal (the spec Apply tail calls Conditions_Recheck).
local _condBusy = false   -- re-entrancy latch (see below)

-- _defaultView is deliberately NOT a refusal reason: the engine steps OUT of the
-- Default view for the duration of a real flip (Conditions_Recheck ->
-- SpecOverrides_SuspendDefaultView) and back in once the applied pointer has
-- advanced, so live is canonical here as on every other boundary. Refusing instead
-- would strand the flip whenever the panel is open -- for the Dark Mode condition
-- that is ALWAYS (its only inputs are options widgets).
function EllesmereUI.SpecOverrides_CondTransition(oldGid, newGid, establish)
    if _inTransition or _editGroup or Cond._edit then return false end
    -- NON-RE-ENTRANT: the refresh fan-out below can reach RefreshAllAddons
    -- (unmapped-folder fallback, module internals), whose tail calls
    -- Conditions_MarkStale + Recheck; re-entering mid-flight rewrites values
    -- against a stale applied pointer and recurses until the client watchdog kills
    -- the frame. Refuse; the engine flags the flip pending and the next signal (or
    -- the establish flag) converges it.
    if _condBusy then return false end
    _condBusy = true
    -- Values: bank the outgoing state, write the incoming one. An ESTABLISH transition
    -- (post profile-apply) has no outgoing owner: live is the incoming store's raw data
    -- (possibly the EXPORTER's overlaid state), so banking it corrupts the new
    -- profile's default maps and baseline layer. Apply only; never harvest.
    if not establish then
        Cond.Harvest(oldGid)
    end
    -- Unlock/BM layout: bank live into whichever layer is live now, BEFORE the
    -- incoming conditional's values are written -- value writes mutate module
    -- settings (sizes) that a later harvest would bank into the OUTGOING layer's
    -- elems. Re-resolution uses the NEW applied gid, passed explicitly (the engine
    -- updates its pointer only after this handler succeeds).
    if not establish and EllesmereUI.SpecOverrides_HarvestUnlockLayout then
        EllesmereUI.SpecOverrides_HarvestUnlockLayout()
    end
    if not establish and EllesmereUI.SpecOverrides_HarvestBmLayout then
        EllesmereUI.SpecOverrides_HarvestBmLayout()
    end
    if not establish and EllesmereUI.SpecOverrides_HarvestDmLayout then
        EllesmereUI.SpecOverrides_HarvestDmLayout()
    end
    local touched = Cond.WriteValues(newGid)
    if EllesmereUI.SpecOverrides_ApplyUnlock then
        Cond._resolveOverride = newGid or false   -- false = explicit none
        -- Forced on establish: the incoming raw stores may hold the layer that
        -- was live at export/save time while the imported active pointer was
        -- reset, and a nil==nil early-out would strand them.
        EllesmereUI.SpecOverrides_ApplyUnlock(CurrentSpecID(), establish)
        if EllesmereUI.SpecOverrides_ApplyBm then
            EllesmereUI.SpecOverrides_ApplyBm(CurrentSpecID(), establish)
        end
        if EllesmereUI.SpecOverrides_ApplyDm then
            EllesmereUI.SpecOverrides_ApplyDm(CurrentSpecID(), establish)
        end
        Cond._resolveOverride = nil
    end
    if touched then RunRefreshers(touched) end
    if Cond.UpdateButton then Cond.UpdateButton() end
    -- Condition applied/removed with the panel open: the labeled "Override
    -- Active" slot overlays must follow immediately.
    RequestGoldWalk()
    _condBusy = false
    return true
end

--- The conditional gid unlock layer resolution should use: during a condition
--- transition the engine's applied pointer is still the OLD one, so the handler
--- passes the target explicitly via _resolveOverride.
function Cond.ResolveGid()
    local ov = Cond._resolveOverride
    if ov ~= nil then
        return ov or nil
    end
    return EllesmereUI.Conditions_AppliedGid and EllesmereUI.Conditions_AppliedGid() or nil
end

-------------------------------------------------------------------------------
--  Element-context providers for selector pages ("which bar / frame is selected").
--  Options pages with an element selector register a provider so captured entries
--  carry their element, making labels and golden borders element-aware.
-------------------------------------------------------------------------------
local _captureContexts = {}

--- fn() -> display label of the module's currently selected element (or nil).
function EllesmereUI.RegisterCaptureContext(folder, fn)
    if type(folder) == "string" and type(fn) == "function" then
        _captureContexts[folder] = fn
    end
end

local function CurrentContext()
    local modFolder = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
    local ctxFn = modFolder and _captureContexts[modFolder]
    if not ctxFn then return nil end
    local ok, ctx = pcall(ctxFn)
    if ok and type(ctx) == "string" and ctx ~= "" then return ctx end
    return nil
end

-------------------------------------------------------------------------------
--  Profile snapshots + diffs (the auto-capture watcher's engine)
-------------------------------------------------------------------------------
local function SnapshotProfiles()
    local snap = {}
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg then return snap end
    for _, db in ipairs(reg) do
        if db.folder and type(db.profile) == "table" then
            snap[db.folder] = DeepCopy(db.profile)
        end
    end
    return snap
end

local function DiffTables(old, new, prefix, out, numFlag)
    for k, nv in pairs(new) do
        local ov = old[k]
        local isNum = numFlag or (type(k) == "number")
        local path = prefix and (prefix .. PS .. tostring(k)) or tostring(k)
        if type(nv) == "table" and type(ov) == "table" then
            DiffTables(ov, nv, path, out, isNum)
        elseif nv ~= ov then
            out[#out + 1] = { path = path, val = nv, num = isNum }
        end
    end
    for k in pairs(old) do
        if new[k] == nil then
            local isNum = numFlag or (type(k) == "number")
            local path = prefix and (prefix .. PS .. tostring(k)) or tostring(k)
            out[#out + 1] = { path = path, removed = true, num = isNum }
        end
    end
end

local function DiffProfiles(snap)
    local out = {}
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg then return out end
    for _, db in ipairs(reg) do
        local old = db.folder and snap[db.folder]
        if old and type(db.profile) == "table" then
            local changes = {}
            DiffTables(old, db.profile, nil, changes)
            for _, c in ipairs(changes) do
                c.folder = db.folder
                c.fkey = db.folder .. FS .. c.path
                out[#out + 1] = c
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  Unlock-session value-edit banking: CAPTURED settings edited from unlock mode
--  (cog width/height inputs write the shared module store) happen panel-closed, so
--  no view owns them and the sticky harvest never adopts foreign live diffs --
--  without this the next value apply REVERTS the unlock-mode resize. A NORMAL
--  unlock session edits the shared baseline exactly like Default Editing Mode, so
--  Save & Exit banks captured diffs into values.default. Special (group fork)
--  sessions hide the size inputs and never bank here; Cancel discards.
-------------------------------------------------------------------------------
local _unlockValueSnap = nil

function EllesmereUI.SpecOverrides_UnlockValueSnapBegin()
    _unlockValueSnap = nil
    local store = GetStore()
    if not store or #store == 0 then return end
    if EllesmereUI._specialUnlockGroup then return end
    _unlockValueSnap = SnapshotProfiles()
end

function EllesmereUI.SpecOverrides_UnlockValueSnapDiscard()
    _unlockValueSnap = nil
end

function EllesmereUI.SpecOverrides_UnlockValueSnapCommit()
    local snap = _unlockValueSnap
    _unlockValueSnap = nil
    if not snap then return end
    -- Sessions/views cannot be live while unlock mode is open (the panel
    -- force-closes on entry); this guards any flow that changes that.
    if _editGroup or _defaultView or Cond._edit then return end
    local changed = false
    for _, c in ipairs(DiffProfiles(snap)) do
        local entry = EntryOwning(c.fkey)
        -- Match-owned size keys: an unlock-session diff on these is the match
        -- engine's write (re-pull on target resize), never a cog edit. Skip.
        if entry and not BlacklistedFKey(c.fkey) and not MatchOwnedFKey(c.fkey)
           and FKeyLoaded(c.fkey) then
            local live = ReadLive(c.fkey)
            if type(live) ~= "table" then
                entry.values.default[c.fkey] = (live == nil) and NIL_SENT or live
                changed = true
            end
        end
    end
    if changed then RequestGoldWalk() end
end

-- EXCLUDED_CONTEXTS is declared earlier, shared with the conditional-overrides
-- block. section is optional: callers with no section context (page overlay, gold
-- walk) treat a section-scoped page entry as NOT excluded -- only the listed
-- sections are outside the system, enforced where the section is known
-- (AutoCapture attribution and entry pruning).
local function IsExcludedContext(section)
    local module = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
    local ex = module and EXCLUDED_CONTEXTS[module]
    if ex == true then return true end
    if type(ex) == "table" then
        local page = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
        local pex = page and ex[page]
        if pex == true then return true end
        if type(pex) == "table" then
            return (section and pex[section]) and true or false
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Golden borders: slots with an active override get a 1px gold PP border. Slots
--  match entries by READ-TRACING: getters are side-effect-free by convention (the
--  refresh system calls them constantly), so a walk swaps the addon profile tables
--  for read-tracking proxies, runs each visible slot's getters once, and matches
--  the recorded paths against entry fkeys. Needs no label metadata and is
--  inherently element-aware on selector pages (Bar 1 selected -> getters read
--  bar1 paths -> only Bar 1's entries match).
-------------------------------------------------------------------------------
local _traceSink = nil
local _traceReal = nil

local function MakeReadProxy(real, folder, prefix)
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, k)
            local v = real[k]
            local path = prefix and (prefix .. PS .. tostring(k)) or tostring(k)
            if type(v) == "table" then
                return MakeReadProxy(v, folder, path)
            end
            if _traceSink then
                _traceSink[folder .. FS .. path] = true
            end
            return v
        end,
        __newindex = function(_, k, v) real[k] = v end,
    })
    return proxy
end

local function BeginTrace()
    local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not reg or _traceReal then return false end
    _traceReal = {}
    for _, db in ipairs(reg) do
        if db.folder and type(db.profile) == "table" then
            _traceReal[db] = db.profile
            db.profile = MakeReadProxy(db.profile, db.folder, nil)
        end
    end
    return true
end

local function EndTrace()
    if not _traceReal then return end
    for db, real in pairs(_traceReal) do
        db.profile = real
    end
    _traceReal = nil
end

-- Runs a slot's getters under the read proxies; returns the set of fkeys read.
local function TraceSlot(cfg)
    _traceSink = {}
    local accs = cfg.accessors or { cfg }
    for _, acc in ipairs(accs) do
        if acc.getValue then pcall(acc.getValue) end
    end
    local sink = _traceSink
    _traceSink = nil
    return sink
end


local function MakeBorderHost(region, r, g, b)
    local host = CreateFrame("Frame", nil, region)
    host:SetAllPoints()
    host:SetFrameLevel(region:GetFrameLevel() + 30)
    if EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
        EllesmereUI.PP.CreateBorder(host, r, g, b, 0.9, 1, "OVERLAY", 7)
    end
    return host
end

-- mode: false (clear), "gold" (overridden), "red" (owned by a conflicting group
-- while editing: red border + click-blocking tooltip overlay), or "condActive" (the
-- APPLIED conditional owns this setting NOW -- the on-screen value is the
-- override's, an edit would bank into it at the next boundary, not the default;
-- labeled overlay + click blocker pointing at its edit mode).
local function SetSlotMark(region, mode, conflictSpecID, condName)
    if mode == "gold" and not region._specOvGold then
        region._specOvGold = MakeBorderHost(region, GOLD_R, GOLD_G, GOLD_B)
    end
    if mode == "red" and not region._specOvRed then
        local host = MakeBorderHost(region, 0.9, 0.2, 0.2)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(region:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local tint = blocker:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(0.9, 0.2, 0.2, 0.05)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        host._blocker = blocker
        region._specOvRed = host
    end
    if mode == "condActive" and not region._specOvCondActive then
        -- Same look as the RF party-tab sync overlays (solid dark blue cover, centered
        -- label in the global font) plus override identity: gold border + gold label.
        -- The border goes on the BLOCKER at a high sublevel so it renders above the
        -- solid background (a border on the host would be covered).
        local host = CreateFrame("Frame", nil, region)
        host:SetAllPoints()
        host:SetFrameLevel(region:GetFrameLevel() + 30)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(region:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local bg = blocker:CreateTexture(nil, "OVERLAY")
        bg:SetAllPoints()
        bg:SetColorTexture(13/255, 17/255, 25/255, 1)
        if EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
            EllesmereUI.PP.CreateBorder(blocker, GOLD_R, GOLD_G, GOLD_B, 0.9, 1, "OVERLAY", 7)
        end
        local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local flag = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
        local label = blocker:CreateFontString(nil, "OVERLAY")
        if EllesmereUI.PrimeFontShadow and EllesmereUI.GetFontUseShadow then
            EllesmereUI.PrimeFontShadow(label, EllesmereUI.GetFontUseShadow())
        end
        label:SetFont(font, 13, flag)
        label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
        label:SetPoint("LEFT", blocker, "LEFT", 4, 0)
        label:SetPoint("RIGHT", blocker, "RIGHT", -4, 0)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(false)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        host._blocker = blocker
        host._label = label
        region._specOvCondActive = host
    end
    if region._specOvGold then region._specOvGold:SetShown(mode == "gold") end
    if region._specOvRed then
        region._specOvRed:SetShown(mode == "red")
        if mode == "red" and region._specOvRed._blocker then
            region._specOvRed._blocker._tipText = string.format(
                L("This setting already has an override for %s"),
                conflictSpecID and SpecName(conflictSpecID) or "?")
        end
    end
    if region._specOvCondActive then
        region._specOvCondActive:SetShown(mode == "condActive")
        if mode == "condActive" then
            local host = region._specOvCondActive
            if host._label then
                host._label:SetText(string.format(L("Override Active: %s"), condName or "?"))
            end
            if host._blocker then
                host._blocker._tipText = string.format(
                    L("Showing the '%s' override's value. Edit it from that override's editing mode."),
                    condName or "?")
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Edit locks: regions that must be non-interactive while ANY Editing-as session is
--  active (same red prevention frame as cross-group conflicts). Used by hands-off
--  systems with their own per-spec handling (e.g. Resource Bars' Threshold & Hash
--  Lines slots). Regions register per page build; dead pages release their locks
--  via the weak table.
-------------------------------------------------------------------------------
local _editLocks = setmetatable({}, { __mode = "k" })

local function UpdateEditLocks()
    local specOn = _editGroup ~= nil
    for _, host in pairs(_editLocks) do
        -- Predicate locks decide their own visibility per session (e.g. the
        -- Dark Mode condition locks); plain locks show for any spec session.
        if host._predicate then
            host:SetShown(host._predicate() and true or false)
        else
            host:SetShown(specOn)
        end
    end
end

-- AttachEditLock predicate for widgets writing the dark-mode CONDITION's input
-- flags (UF darkTheme, RF healthColorMode, the Fonts & Colors master; the Class
-- Resource Bar flag is NOT an input -- DarkModeMasterOn excludes it). True when
--   (a) the editing-as session is a CONDITIONAL group with the Dark Mode
--       condition: capturing a dark flag into it lets the override flip its own
--       activation condition (apply -> false -> restore -> true -> ...); or
--   (b) ANY conditional session is active AND a Dark Mode group exists: a dark
--       flag captured into a dungeon/keybind/solo group fights the Dark Mode
--       group through the resolution ladder (same oscillation, two groups).
-- Spec-group sessions never lock these: spec activation does not read dark
-- state, so a spec-captured dark flag settles in one apply.
function EllesmereUI.SpecOverrides_DarkCondEditActive()
    local g = Cond and Cond._edit
    if not g then return false end
    if g.conds and g.conds.darkmode then return true end
    local groups = EllesmereUI.Conditions_GetGroups and EllesmereUI.Conditions_GetGroups()
    if groups then
        for _, og in ipairs(groups) do
            if og.conds and og.conds.darkmode then return true end
        end
    end
    return false
end

function EllesmereUI.SpecOverrides_AttachEditLock(region, tip, predicate)
    if not region then return end
    local host = _editLocks[region]
    if not host then
        host = MakeBorderHost(region, 0.9, 0.2, 0.2)
        local blocker = CreateFrame("Button", nil, host)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(region:GetFrameLevel() + 45)
        blocker:EnableMouse(true)
        local tint = blocker:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(0.9, 0.2, 0.2, 0.05)
        blocker:SetScript("OnEnter", function(self)
            if self._tipText and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._tipText)
            end
        end)
        blocker:SetScript("OnLeave", function()
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        host._blocker = blocker
        _editLocks[region] = host
    end
    host._blocker._tipText = tip
    host._predicate = predicate
    if predicate then
        host:SetShown(predicate() and true or false)
    else
        host:SetShown(_editGroup ~= nil)
    end
end

local function GoldWalk(frame, forceOff, condGid, condName)
    local cfg = frame._captureCfg
    if cfg and not cfg.noCapture and not forceOff then
        local entry, condActive
        for fkey in pairs(TraceSlot(cfg)) do
            -- Applied-conditional context (no session): a slot whose fkey the
            -- LIVE conditional banks a value for shows that override's value
            -- right now -- labeled overlay instead of plain gold.
            if condGid and not condActive then
                local ce = Cond.EntryOwning(fkey)
                local m = ce and ce.values and ce.values[condGid]
                if m and m[fkey] ~= nil then condActive = true end
            end
            if not entry then
                entry = EntryOwning(fkey) or Cond.EntryOwning(fkey)
            end
            if entry and (condActive or not condGid) then break end
        end
        if condActive then
            SetSlotMark(frame, "condActive", nil, condName)
        elseif entry then
            local conflict = ConflictSpec(entry)
            SetSlotMark(frame, conflict and "red" or "gold", conflict)
        else
            SetSlotMark(frame, false)
        end
    else
        if frame._specOvGold then frame._specOvGold:Hide() end
        if frame._specOvRed then frame._specOvRed:Hide() end
        if frame._specOvCondActive then frame._specOvCondActive:Hide() end
    end
    local kids = { frame:GetChildren() }
    for i = 1, #kids do GoldWalk(kids[i], forceOff, condGid, condName) end
end

local _goldWalkQueued = false
RequestGoldWalk = function()
    if _goldWalkQueued then return end
    _goldWalkQueued = true
    C_Timer.After(0, function()
        _goldWalkQueued = false
        local root = _G.EllesmereUIFrame
        if not (root and root:IsShown()) then return end
        -- Excluded contexts never show slot marks (walk still clears stale ones)
        if IsExcludedContext() then
            GoldWalk(root, true)
            return
        end
        if BeginTrace() then
            -- Applied-conditional context for the walk: only outside every
            -- session (a session view shows session values, not the overlay).
            local condGid, condName
            if not _editGroup and not Cond._edit then
                condGid = EllesmereUI.Conditions_AppliedGid
                    and EllesmereUI.Conditions_AppliedGid() or nil
                local g = condGid and EllesmereUI.Conditions_GroupById
                    and EllesmereUI.Conditions_GroupById(condGid) or nil
                if g then condName = g.name else condGid = nil end
            end
            -- pcall is LOAD-BEARING: while the trace is active every db.profile
            -- in the Lite registry is a read-tracking PROXY that iterates EMPTY
            -- under pairs/next. An error escaping GoldWalk would skip EndTrace,
            -- strand the proxies for the session, and the next snapshot/logout
            -- write-back would PERSIST empty module profiles (total settings
            -- wipe). EndTrace must run on every path.
            local ok, err = pcall(GoldWalk, root, nil, condGid, condName)
            EndTrace()
            if not ok and err then geterrorhandler()(err) end
        end
    end)
end

-------------------------------------------------------------------------------
--  Auto-capture watcher (runs while Editing-as is active)
-------------------------------------------------------------------------------
local _watchSnap = nil
local _watchTicker = nil
local _lastRegion, _lastRegionTime = nil, 0
local _watchResync = false   -- absorb the next tick's diff (page rebuild seeds)
local _sessionIgnored = {}   -- fkeys written on excluded pages this session
                             -- (never captured, and skipped by the exit sweep)

local function PrettyKey(fkey)
    local _, path = SplitFKey(fkey)
    local last = (path and path:match("([^\30]+)$")) or tostring(fkey)
    last = last:gsub("(%l)(%u)", "%1 %2")
    return (last:gsub("^%l", string.upper))
end

-- Tracks which options slot the user is interacting with. Popups (dropdown
-- menus, cog popups, color picker) keep the previous slot attribution;
-- anything outside the options UI clears it.
local function SampleAttribution()
    local foci = GetMouseFoci and GetMouseFoci()
    local f = foci and foci[1]
    if not f or f == WorldFrame then return end
    local inPanel, popup, region = false, false, nil
    local n = f
    while n do
        if n._captureCfg then region = n end
        if n._euiOptionsPopup or n == EllesmereUI._colorPickerPopup then popup = true end
        if n == _G.EllesmereUIFrame then inPanel = true end
        n = n:GetParent()
    end
    if region then
        _lastRegion, _lastRegionTime = region, GetTime()
    elseif popup then
        -- keep the previous attribution (edits flow through the popup)
        _lastRegionTime = GetTime()
    elseif not inPanel then
        _lastRegion = nil   -- interacting with the world / other UI
    end
end

local function EntryForSlot(module, element, page, section, slotLabel)
    for _, entry in ipairs(GetStore() or {}) do
        if entry.slotLabel == slotLabel and entry.module == module
           and (entry.element or "") == (element or "")
           and (entry.page or "") == (page or "")
           and (entry.section or "") == (section or "") then
            return entry
        end
    end
    return nil
end

local function AutoCapture(changes)
    -- Hidden search prebuild: selector setters and lazy page seeding write
    -- db.profile from a pass the user never sees -- never capture them.
    if EllesmereUI._prebuilding then return end
    -- Attribution required: without a known slot, absorb silently (background
    -- bookkeeping like drag positions must never become overrides). The 3-second
    -- window bounds this mouse-focus FALLBACK (the notified-write path attributes
    -- exactly); longer lets unrelated background writes (match propagation,
    -- combat-end refreshers) land under the last slot touched.
    local region = _lastRegion
    if not (region and region._captureCfg and (GetTime() - _lastRegionTime) < 3) then
        return
    end
    -- Excluded contexts (whole modules, pages, or single sections) never factor into
    -- spec overrides: absorb, and shield these paths from the exit sweep. Section is
    -- derived up front so section-scoped (nested-table) entries apply.
    local row = region._isOptionRow and region or region:GetParent()
    local hdr = row and row._sectionHeader
    local section = hdr and hdr._sectionName or nil
    if IsExcludedContext(section) then
        for _, c in ipairs(changes) do
            _sessionIgnored[c.fkey] = true
        end
        return
    end
    local store = GetStore(true)
    if not store then return end

    -- Validate + collect
    local paths, skippedNum, skippedBlack = {}, false, nil
    for _, c in ipairs(changes) do
        if c.num and not NumAllowedFKey(c.fkey) then
            skippedNum = true
        elseif BlacklistedFKey(c.fkey) then
            skippedBlack = c.folder
        elseif MatchOwnedFKey(c.fkey) then
            -- Match-owned size keys are the match engine's territory: apply
            -- skips them and every bank preserves, so capturing one only
            -- creates a dead slot the harvests must tiptoe around.
            _sessionIgnored[c.fkey] = true
        else
            paths[#paths + 1] = c.fkey
        end
    end
    if #paths == 0 then
        if skippedBlack then
            if skippedBlack == "EllesmereUICooldownManager" then
                SetEditStatus(L("Cooldown Manager has its own per-spec system and can't be overridden here."), 1, 0.55, 0.35)
            elseif FOLDER_BLACKLIST[skippedBlack] then
                SetEditStatus(L("This module is excluded from Spec Overrides."), 1, 0.55, 0.35)
            else
                -- Setting-level exclusion (SETTING_BLACKLIST hit).
                SetEditStatus(L("This setting can't be overridden."), 1, 0.55, 0.35)
            end
        elseif skippedNum then
            SetEditStatus(L("That setting is stored by list position and can't be safely overridden."), 1, 0.55, 0.35)
        end
        return
    end
    if #paths > 12 then return end   -- burst; not a slot edit

    local cfg = region._captureCfg
    local slotLabel = tostring(cfg.text or "?")
    local module = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
    local page = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
    local element = CurrentContext()

    -- Session routing: a conditional session banks into the CONDITIONAL store
    -- (own fkey index, group id space, per-GROUP value maps instead of
    -- per-spec). Everything else is identical.
    local condSession = Cond._edit
    local sStore = condSession and Cond.GetStore(true) or store
    local entry
    for _, e in ipairs(sStore or {}) do
        if e.slotLabel == slotLabel and e.module == module
           and (e.element or "") == (element or "")
           and (e.page or "") == (page or "")
           and (e.section or "") == (section or "") then
            entry = e
            break
        end
    end
    local isNew = false
    if not entry then
        isNew = true
        local crumbParts = {}
        local modTitle = module and EllesmereUI.GetModuleTitle and EllesmereUI:GetModuleTitle(module)
        if modTitle then crumbParts[#crumbParts + 1] = L(modTitle) end
        if element then crumbParts[#crumbParts + 1] = L(element) end
        if page then crumbParts[#crumbParts + 1] = L(page) end
        if section then crumbParts[#crumbParts + 1] = L(section) end
        entry = {
            label = slotLabel,
            slotLabel = slotLabel,
            crumb = table.concat(crumbParts, "  >  "),
            module = module, page = page,
            element = element, section = section,
            group = condSession and condSession.id or (_editGroup and _editGroup.id or nil),
            values = { default = {} },
        }
        sStore[#sStore + 1] = entry
    end

    -- Record originals (pre-change snapshot values) as the shared default; conditional
    -- sessions also seed the group's map. Live values bank at session exit. The REAL
    -- spec's map is deliberately NOT seeded: the per-key default fallback in
    -- WriteSpecValues already restores the bystander spec at exit, and a stored copy
    -- would pin it at this old default forever once the default is later edited
    -- (permanent phantom override on an unassigned spec).
    for _, fkey in ipairs(paths) do
        if entry.values.default[fkey] == nil then
            local orig = SnapValue(_watchSnap, fkey)
            -- Spec-session capture of a cond-owned fkey: the snapshot may hold an
            -- APPLIED conditional's overlay value, not the shared baseline. Seed from
            -- the cond store's recorded default instead. (Inert in a cond session:
            -- captured fkeys there are never cond-owned.)
            local ce = Cond.EntryOwning(fkey)
            if ce then
                orig = ce.values.default[fkey]
                if orig == NIL_SENT then orig = nil end
            end
            if type(orig) == "table" then orig = nil end
            entry.values.default[fkey] = (orig == nil) and NIL_SENT or orig
            if condSession then
                local gm = entry.values[condSession.id]
                if not gm then gm = {}; entry.values[condSession.id] = gm end
                gm[fkey] = entry.values.default[fkey]
            end
        end
    end

    if condSession then Cond.RebuildIndex() else RebuildFKeyIndex() end
    RequestGoldWalk()
    if isNew then
        local sessName = condSession and condSession.name or (_editGroup and _editGroup.name) or "?"
        SetEditStatus(string.format(L("'%s' is now customized for %s."), slotLabel, sessName), 0.35, 1, 0.35)
    end
end

local function WatchTick()
    if not _editGroup and not Cond._edit then return end
    SampleAttribution()
    local root = _G.EllesmereUIFrame
    if not (root and root:IsShown()) then return end
    -- Hidden search prebuild mid-session: its selector setters and lazy page
    -- seeding write db.profile; absorb the whole tick (resync) so those writes
    -- can never diff into captures.
    if EllesmereUI._prebuilding then
        _watchSnap = SnapshotProfiles()
        return
    end
    if not _watchSnap then
        _watchSnap = SnapshotProfiles()
        return
    end
    local diffs = DiffProfiles(_watchSnap)
    if #diffs == 0 then return end
    if not _watchResync then
        local newOnes = nil
        for _, c in ipairs(diffs) do
            if Cond._edit then
                -- Conditional session: spec-owned fkeys are editable here too
                -- (each store keeps its own value; the session shows
                -- conditional-over-default) but spec still wins at RUNTIME.
                -- Cond-owned fkeys bank at exit.
                if not Cond.EntryOwning(c.fkey) then
                    newOnes = newOnes or {}
                    newOnes[#newOnes + 1] = c
                end
            elseif not EntryOwning(c.fkey) then
                newOnes = newOnes or {}
                newOnes[#newOnes + 1] = c
            end
        end
        if newOnes then AutoCapture(newOnes) end
    end
    _watchResync = false
    _watchSnap = SnapshotProfiles()
end

-- Page rebuilds lazily seed defaults into profiles; absorb those writes instead of
-- capturing them (fast-path refreshes don't rebuild rows and keep capture armed).
-- Also the panel-lifecycle bootstrap: page activity means the panel exists/opened,
-- so install the show/hide hooks and enter the Default view when idle.
local function OnPageRebuilt()
    _watchResync = true
    RequestGoldWalk()
    if ApplyEditOverlay then ApplyEditOverlay() end   -- chrome-page suppression
    if EnsurePanelHideHook then EnsurePanelHideHook() end
    -- The toolbar button disables on excluded pages; re-evaluate per page.
    if EllesmereUI._specOvBtnPageState then EllesmereUI._specOvBtnPageState() end
    -- BM passive chrome follows page navigation: shows on the Buff Manager page
    -- with a live fork, clears when leaving it.
    if EllesmereUI.SpecOverrides_UpdateBmPassiveChrome then
        EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    end
    if not _editGroup and not _defaultView then
        C_Timer.After(0, function()
            -- _unlockRoundtrip: the post-unlock page restore rebuilds pages before the
            -- OnShow restore consumes the stash, so entering the Default view here
            -- would only churn (the session re-enter exits it a tick later).
            if not _editGroup and not _defaultView and not _unlockRoundtrip
               and _G.EllesmereUIFrame and _G.EllesmereUIFrame:IsShown()
               and EnterDefaultView then
                EnterDefaultView()
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Notified writes: the widget factory calls _NotifySettingWrite on EVERY widget
--  setValue. Primary capture path -- exact frame-based slot attribution, processed
--  next frame, immune to page-rebuild seed absorption (a forced refresh triggered
--  by the setter itself can never swallow the user's edit). The polling ticker is
--  only the fallback for writes outside the factory.
-------------------------------------------------------------------------------
local _pendingWrites, _pendingWriteQueued = nil, false

local function ProcessNotifiedWrites()
    _pendingWriteQueued = false
    local frames = _pendingWrites
    _pendingWrites = nil
    if not (_editGroup or Cond._edit) or not _watchSnap then return end
    -- Prebuild writes are never user edits: absorb via resync (see WatchTick).
    if EllesmereUI._prebuilding then
        _watchSnap = SnapshotProfiles()
        return
    end
    -- Exact attribution from the notified frames (first that resolves wins).
    for _, f in ipairs(frames or {}) do
        if type(f) == "table" then
            local n, region = f, nil
            while n do
                if n._captureCfg then region = n; break end
                n = n:GetParent()
            end
            if region then
                _lastRegion, _lastRegionTime = region, GetTime()
                break
            end
        end
    end
    local diffs = DiffProfiles(_watchSnap)
    if #diffs == 0 then return end
    local newOnes
    for _, c in ipairs(diffs) do
        -- Ownership filter mirrors WatchTick's session branch: in a cond
        -- session cond-owned fkeys bank at exit (HarvestEdit); everything else
        -- captures immediately here.
        local owned
        if Cond._edit then
            owned = Cond.EntryOwning(c.fkey)
        else
            owned = EntryOwning(c.fkey)
        end
        if not owned then
            newOnes = newOnes or {}
            newOnes[#newOnes + 1] = c
        end
    end
    if newOnes then AutoCapture(newOnes) end
    _watchSnap = SnapshotProfiles()
end

--- Called by the widget factory whenever any options widget writes a value.
function EllesmereUI._NotifySettingWrite(frame)
    -- Conditional sessions capture through this path too. Without them in the gate they
    -- fall back to watcher/exit-sweep capture only, losing edits whenever a setter's
    -- forced refresh raises the resync absorb before a tick can attribute them.
    if not (_editGroup or Cond._edit) then return end
    _pendingWrites = _pendingWrites or {}
    _pendingWrites[#_pendingWrites + 1] = frame or false
    if not _pendingWriteQueued then
        _pendingWriteQueued = true
        C_Timer.After(0, ProcessNotifiedWrites)
    end
end

-------------------------------------------------------------------------------
--  Exit-sweep safety net: anything that changed during the session and never
--  got captured (bespoke widgets, frame drags) must not leak into the real
--  spec. Sweeping it into the group lets the exit restore undo it live.
-------------------------------------------------------------------------------
SweepUncaptured = function(group)
    if not _enterSnap or not group then return end
    local store = GetStore(true)
    if not store then return end
    local added = false
    for _, c in ipairs(DiffProfiles(_enterSnap)) do
        -- MatchOwnedFKey: a match-owned size diff is the match engine's write,
        -- never a session edit; minting an entry from it hands the key to the
        -- harvest broadcast (proliferation vector).
        if not EntryOwning(c.fkey) and (not c.num or NumAllowedFKey(c.fkey)) and not BlacklistedFKey(c.fkey)
           and not MatchOwnedFKey(c.fkey)
           and not _sessionIgnored[c.fkey] then
            local orig = SnapValue(_enterSnap, c.fkey)
            -- Same guard as AutoCapture: a cond-owned fkey's snapshot may be
            -- an applied conditional's overlay; seed from the cond store's
            -- recorded default instead.
            local ce = Cond.EntryOwning(c.fkey)
            if ce then
                orig = ce.values.default[c.fkey]
                if orig == NIL_SENT then orig = nil end
            end
            if type(orig) == "table" then orig = nil end
            local entry = {
                label = PrettyKey(c.fkey),
                crumb = (EllesmereUI.GetModuleTitle and EllesmereUI:GetModuleTitle(c.folder)) or c.folder,
                module = c.folder,
                group = group.id,
                values = { default = { [c.fkey] = (orig == nil) and NIL_SENT or orig } },
            }
            -- The real spec's map is deliberately not seeded (see AutoCapture).
            store[#store + 1] = entry
            added = true
        end
    end
    if added then
        RebuildFKeyIndex()
    end
end

-------------------------------------------------------------------------------
--  Editing-as core
-------------------------------------------------------------------------------
local editBanner, editBannerText, editBannerStatus
local panelHideHooked = false

EnsurePanelHideHook = function()
    if panelHideHooked or not _G.EllesmereUIFrame then return end
    panelHideHooked = true
    _G.EllesmereUIFrame:HookScript("OnHide", function()
        -- Unlock-mode roundtrip: when the panel hides because Unlock Mode was opened
        -- FROM the options window, remember the active editing session so the
        -- auto-reopen restores the same override view. The session still tears down
        -- normally below (values bank safely; only the SELECTION is remembered). A
        -- hide with no session leaves any pending stash untouched -- the panel can
        -- flash shown/hidden while unlock force-closes.
        if EllesmereUI._unlockReturnModule ~= nil then
            if _editGroup then
                _unlockRoundtrip = { kind = "spec", id = _editGroup.id }
            elseif Cond._edit then
                _unlockRoundtrip = { kind = "cond", id = Cond._edit.id }
            end
        end
        if ExitGroupEdit then ExitGroupEdit() end
        if Cond.ExitEdit then Cond.ExitEdit() end
        if ExitDefaultView then ExitDefaultView() end
        if EllesmereUI._specOvCardsPopup then EllesmereUI._specOvCardsPopup:Hide() end
        if Cond._cardsPopup then Cond._cardsPopup:Hide() end
        -- Name/icon popups parent to UIParent and would survive the panel closing; their
        -- Create/Save buttons enter an edit session, and a session entered with the
        -- panel HIDDEN snapshots before the deferred page rebuild's lazy seeding, so the
        -- exit sweep adopts those seeds as phantom captures. Close them with the panel.
        if EllesmereUI._specOvNamePopup then EllesmereUI._specOvNamePopup:Hide() end
        if Cond._namePopup then Cond._namePopup:Hide() end
    end)
    -- Re-entering the panel returns to the Default Editing Mode view, or after
    -- an options-entered unlock roundtrip back to the session that was active
    -- when unlock hid the panel.
    _G.EllesmereUIFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if not (_G.EllesmereUIFrame and _G.EllesmereUIFrame:IsShown()) then return end
            local rt = _unlockRoundtrip
            if rt then
                -- One-shot: consumed only on a show that processes (the
                -- force-close flow can flash the panel shown->hidden).
                _unlockRoundtrip = nil
                if rt.kind == "spec" and EnterGroupEdit then
                    for _, g in ipairs(GetGroups() or {}) do
                        if g.id == rt.id then EnterGroupEdit(g); return end
                    end
                elseif rt.kind == "cond" and Cond.EnterEdit then
                    local cgroups = EllesmereUI.Conditions_GetGroups and EllesmereUI.Conditions_GetGroups()
                    for _, g in ipairs(cgroups or {}) do
                        if g.id == rt.id then Cond.EnterEdit(g); return end
                    end
                end
                -- Group vanished mid-roundtrip: fall through to Default view.
            end
            if EnterDefaultView then
                EnterDefaultView()
            end
        end)
    end)
end

local function EnsureEditBanner()
    if editBanner then return editBanner end
    local root = _G.EllesmereUIFrame or UIParent
    editBanner = CreateFrame("Frame", nil, root)
    editBanner:SetSize(680, 44)
    -- Sits ON TOP of the visible panel: banner bottom flush with the window's
    -- top edge (the click area is the actual window; the outer frame includes
    -- the background art's shadow padding).
    editBanner:SetPoint("BOTTOM", _G.EllesmereUIClickArea or root, "TOP", 0, 0)
    editBanner:SetClampedToScreen(true)
    editBanner:SetFrameStrata("DIALOG")
    local bg = editBanner:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    local brd = editBanner:CreateTexture(nil, "BORDER")
    brd:SetPoint("BOTTOMLEFT"); brd:SetPoint("BOTTOMRIGHT")
    brd:SetHeight(1)
    brd:SetColorTexture(EDIT_R, EDIT_G, EDIT_B, 0.7)
    editBannerText = editBanner:CreateFontString(nil, "OVERLAY")
    editBannerText:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
    editBannerText:SetPoint("TOPLEFT", editBanner, "TOPLEFT", 16, -8)
    editBannerText:SetTextColor(EDIT_R, EDIT_G, EDIT_B, 1)
    editBannerStatus = editBanner:CreateFontString(nil, "OVERLAY")
    editBannerStatus:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
    editBannerStatus:SetPoint("BOTTOMLEFT", editBanner, "BOTTOMLEFT", 16, 7)
    editBannerStatus:SetTextColor(1, 1, 1, 0.6)
    local done = CreateFrame("Button", nil, editBanner)
    done:SetSize(74, 24)
    done:SetPoint("RIGHT", editBanner, "RIGHT", -12, 0)
    EllesmereUI.SolidTex(done, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local dbrd = EllesmereUI.MakeBorder(done, 1, 1, 1, 0.22)
    local dlbl = EllesmereUI.MakeFont(done, 11, nil, 1, 1, 1, 0.9)
    dlbl:SetPoint("CENTER")
    dlbl:SetText(L("Done"))
    done:SetScript("OnEnter", function() if dbrd and dbrd.SetColor then dbrd:SetColor(EDIT_R, EDIT_G, EDIT_B, 0.8) end end)
    done:SetScript("OnLeave", function() if dbrd and dbrd.SetColor then dbrd:SetColor(1, 1, 1, 0.22) end end)
    done:SetScript("OnClick", function()
        if _editGroup then ExitGroupEdit() end
        if Cond.ExitEdit then Cond.ExitEdit() end
    end)
    editBanner._done = done   -- passive chrome hides it (nothing to exit)
    return editBanner
end

SetEditStatus = function(text, r, g, b)
    if editBannerStatus then
        editBannerStatus:SetText(text or "")
        editBannerStatus:SetTextColor(r or 1, g or 1, b or 0.6)
    end
end

ShowEditBanner = function(group)
    EnsureEditBanner()
    if editBanner._done then editBanner._done:Show() end   -- passive mode hides it
    editBannerText:SetText(string.format(L("Editing as %s"), group.name or "?"))
    SetEditStatus(L("Any setting you change now applies only to this group's specs."), 1, 1, 0.6)
    editBanner:Show()
    -- Lock excluded modules on the sidebar for the session's duration.
    if EllesmereUI.RefreshSidebarOverrideLocks then EllesmereUI.RefreshSidebarOverrideLocks() end
end

HideEditBanner = function()
    if editBanner then editBanner:Hide() end
end

-- Background glow overlay shown while Editing-as. Aligned 1:1 with the options
-- panel background layers (both fill EllesmereUIFrame edge to edge), one frame
-- level above them and below all content frames.
local EDIT_GLOW_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\backgrounds\\eui-glow-override.png"
local editOverlay
local editOverlayTexture = EDIT_GLOW_TEXTURE

function EllesmereUI.SpecOverrides_SetEditBackground(texturePath)
    editOverlayTexture = texturePath or EDIT_GLOW_TEXTURE
    if editOverlay and editOverlay._tex then
        editOverlay._tex:SetTexture(editOverlayTexture)
    end
end

-- The glow suppresses itself on excluded contexts (chrome pages + Global
-- Settings General) and returns on normal module pages.
local _overlayWanted = false

ApplyEditOverlay = function()
    if not editOverlay then return end
    editOverlay:SetShown(_overlayWanted and not IsExcludedContext())
end

local function SetEditOverlayShown(shown)
    _overlayWanted = shown and true or false
    if shown and not editOverlay then
        local root = _G.EllesmereUIFrame
        if not root then return end
        editOverlay = CreateFrame("Frame", nil, root)
        editOverlay:SetAllPoints(root)
        editOverlay:SetFrameLevel(root:GetFrameLevel() + 1)
        editOverlay:EnableMouse(false)
        local tex = editOverlay:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetTexture(editOverlayTexture)
        editOverlay._tex = tex
    end
    ApplyEditOverlay()
end

TeardownEditSession = function()
    if _watchTicker then _watchTicker:Cancel(); _watchTicker = nil end
    _watchSnap = nil
    _enterSnap = nil
    _sessionIgnored = {}
    HideEditBanner()
    SetEditOverlayShown(false)
    UpdateIndicator()
    UpdateEditLocks()   -- release threshold/hands-off locks
    RequestGoldWalk()   -- clear conflict-red marks back to gold
    -- Unlock the sidebar (session over for either system).
    if EllesmereUI.RefreshSidebarOverrideLocks then EllesmereUI.RefreshSidebarOverrideLocks() end
end

-- Passive override chrome: the Buff Manager page binds to the live fork even
-- WITHOUT an editing session (the prelude auto-activates it), so the session's
-- glow + banner must show there too. A real session owns the chrome outright;
-- this only fills the no-session case and cleans up after itself.
local _bmPassiveChrome = false

function EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    if _editGroup or Cond._edit then return end   -- real session owns chrome
    local kind = EllesmereUI.SpecOverrides_BmPageLockInfo
        and EllesmereUI.SpecOverrides_BmPageLockInfo() or nil
    local status = L("Buff Manager changes on this page apply only to this override.")
    local nameFn = EllesmereUI.SpecOverrides_BmActiveInfo
    if not kind then
        -- Same chrome serves the Debuff Manager page (one page is active at a
        -- time, so the two locks can never both report).
        kind = EllesmereUI.SpecOverrides_DmPageLockInfo
            and EllesmereUI.SpecOverrides_DmPageLockInfo() or nil
        if kind then
            status = L("Debuff Manager changes on this page apply only to this override.")
            nameFn = EllesmereUI.SpecOverrides_DmActiveInfo
        end
    end
    if kind then
        local name = (nameFn and nameFn()) or "?"
        EnsureEditBanner()
        editBannerText:SetText(string.format(L("Override Active: %s"), name))
        SetEditStatus(status, 1, 1, 0.6)
        if editBanner._done then editBanner._done:Hide() end   -- nothing to exit
        editBanner:Show()
        SetEditOverlayShown(true)
        _bmPassiveChrome = true
    elseif _bmPassiveChrome then
        _bmPassiveChrome = false
        HideEditBanner()
        SetEditOverlayShown(false)
        if editBanner and editBanner._done then editBanner._done:Show() end
    end
    -- The toolbar glyph's lock state tracks the same signal (fork created or
    -- deleted mid-page never goes through a page selection).
    if EllesmereUI._specOvBtnPageState then EllesmereUI._specOvBtnPageState() end
end

-------------------------------------------------------------------------------
--  Default Editing Mode view: while the options panel is open WITHOUT an
--  Editing-as session, the stored DEFAULT values swap into the live paths so
--  the panel always shows and edits the shared baseline, even when the current
--  spec belongs to an override group. Closing the panel (or entering
--  Editing-as) banks default edits and restores the spec's values.
-------------------------------------------------------------------------------
PanelShown = function()
    local root = _G.EllesmereUIFrame
    return root and root:IsShown() or false
end

EnterDefaultView = function()
    if _defaultView or _editGroup or Cond._edit or _inTransition then return end
    local store = GetStore()
    if not store or #store == 0 then return end
    -- Bank the real spec's live edits first, then swap the defaults in.
    EllesmereUI.SpecOverrides_HarvestCurrent()
    _defaultView = true
    local touched = WriteDefaultValues()
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild: default values may drive different page structure than
    -- the spec values they replaced.
    if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    UpdateIndicator()
end

ExitDefaultView = function(restore)
    if not _defaultView then return end
    _defaultView = false
    HarvestDefaults()
    if restore ~= false then
        local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
        if touched then RunRefreshers(touched) end
    end
    UpdateIndicator()
end

--- Steps OUT of the Default view for the duration of a CONDITIONAL flip, and back
--- in afterwards. Returns true when the view was actually suspended (caller must
--- then resume it).
---
--- Why not just refuse the flip: the Dark Mode condition's only inputs (the two
--- Fonts & Colors masters, the UF/RF dark toggles) live INSIDE the options panel,
--- so its flips are ALWAYS raised with the view up, and only a zone change/roster
--- update/combat end/reload re-drives a deferred flip -- it can stay pending a
--- whole session. While pending, the outgoing conditional stays APPLIED and keeps
--- reporting itself as the applied group, so later banks file plain baseline
--- edits into its map until the flip converges and repaints the untouched
--- defaults over them.
---
--- Suspending mirrors how a SPEC transition uses this view (banks edits, restores
--- canonical live on the way out via OnSpecChanged/HarvestCurrent, SpecOverrides_
--- Apply's tail re-enters). Resuming AFTER the applied pointer advances is
--- load-bearing: EnterDefaultView harvests through HarvestCurrent, which resolves
--- the applied gid, so re-entering first would bank the INCOMING conditional's
--- live values into the OUTGOING group's maps.
function EllesmereUI.SpecOverrides_SuspendDefaultView()
    if not _defaultView then return false end
    ExitDefaultView()
    return true
end

function EllesmereUI.SpecOverrides_ResumeDefaultView()
    if PanelShown() then EnterDefaultView() end
end

--- noRecheck: this exit is a PREAMBLE inside another operation (entering a
--- different session, a membership/delete rewrite, opening unlock mode, a profile
--- apply) rather than the user finishing, so it must not have a conditional
--- transition wedged into it -- most sharply the unlock and profile paths, where
--- the transition's ApplyUnlock schedules its flush TWO FRAMES out and it would
--- land inside unlock mode's snapshot window, or after a profile swap refilled
--- the live tables. Mirror of Cond.ExitEdit's noRecheck.
ExitGroupEdit = function(noRecheck)
    if not _editGroup then return end
    WatchTick()   -- catch trailing edits from the last sub-tick window
    local g = _editGroup
    _editGroup = nil
    SweepUncaptured(g)
    HarvestGroup(g)
    TeardownEditSession()
    local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild: restored values can change page STRUCTURE (sections
    -- shown/hidden by a visibility dropdown); the fast refresh only re-reads
    -- widget values and would leave stale structure on screen.
    if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    RequestGoldWalk()
    -- Back to Default Editing Mode: the open panel returns to the baseline.
    if PanelShown() then EnterDefaultView() end
    -- A condition flip raised mid-session was deferred (the handler bails while
    -- a session holds swapped values live); resolve it now, like ExitEdit.
    if not noRecheck and EllesmereUI.Conditions_Recheck then
        EllesmereUI.Conditions_Recheck()
    end
end

--- Force-closes every editing-as session (spec group, conditional, Default view).
--- Profile apply/import/switch call this BEFORE swapping stores: the exits bank and
--- restore against the OUTGOING profile, and the post-swap establish
--- (Conditions_MarkStale + Recheck) must never find a live session -- the
--- transition handler refuses under one, stranding the incoming profile
--- un-overlaid until the next zone change.
function EllesmereUI.SpecOverrides_CloseEditSessions()
    -- Unlock-open window: remember the active session so the post-unlock reopen
    -- restores it. Same stash the panel-hide hook takes, but OpenUnlockMode closes
    -- sessions BEFORE the panel hides (the value snapshot must be taken over
    -- canonical live data), so the hook finds no session and would lose the roundtrip.
    if EllesmereUI._unlockReturnModule ~= nil then
        if _editGroup then
            _unlockRoundtrip = { kind = "spec", id = _editGroup.id }
        elseif Cond._edit then
            _unlockRoundtrip = { kind = "cond", id = Cond._edit.id }
        end
    end
    if _editGroup and ExitGroupEdit then ExitGroupEdit(true) end
    -- noRecheck: every caller here drives its own choreography and must NOT have a
    -- conditional transition wedged into it. A deferred flip resolved from this exit
    -- would run ApplyUnlock, whose flush is scheduled TWO FRAMES out; on the profile
    -- apply/switch callers that lands AFTER the live tables are wiped and refilled,
    -- writing the OUTGOING profile's layer geometry into the INCOMING profile's
    -- module stores. Not stranding: the profile paths run Conditions_MarkStale +
    -- Recheck right after the swap, unlock open re-resolves on close, and
    -- PromoteGroupToProfile ends in a ReloadUI.
    if Cond._edit and Cond.ExitEdit then Cond.ExitEdit(nil, true) end
    if _defaultView and ExitDefaultView then ExitDefaultView() end
end

EnterGroupEdit = function(group)
    if _editGroup == group then return end
    if not group or not group.specs or #group.specs == 0 then return end
    -- BM page lock: while the Buff Manager page is bound to a live fork, only
    -- THAT group's session may open from the cards popup; any other context
    -- would edit settings the page is not displaying.
    do
        local lockKind, lockGid
        local lockLabel = "Buff Manager"
        if EllesmereUI.SpecOverrides_BmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_BmPageLockInfo()
        end
        if not lockKind and EllesmereUI.SpecOverrides_DmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_DmPageLockInfo()
            if lockKind then lockLabel = "Debuff Manager" end
        end
        if lockKind and not (lockKind == "spec" and lockGid == group.id) then
            EllesmereUI:ShowConfirmPopup({
                title = string.format(L("%s Override Active"), L(lockLabel)),
                message = string.format(L("The active override's custom %s is bound to this page. Leave the %s tab to switch to another override."), L(lockLabel), L(lockLabel)),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    -- Preamble teardown, not the user finishing: no conditional recheck (a
    -- deferred flip resolves at the session end that really ends editing).
    if _editGroup then ExitGroupEdit(true) end
    if Cond.ExitEdit then Cond.ExitEdit(nil, true) end   -- sessions never coexist
    -- Leave the Default view (banks default edits, restores spec values), then
    -- bank the real spec's live edits and swap the group in.
    ExitDefaultView()
    EllesmereUI.SpecOverrides_HarvestCurrent()
    _editGroup = group
    local touched = WriteGroupValues(group)
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild (structure may differ under the group's values); runs
    -- before the snapshot so lazy page seeding is absorbed.
    if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    _watchSnap = SnapshotProfiles()
    _enterSnap = _watchSnap   -- session baseline for the exit sweep
    _sessionIgnored = {}
    _lastRegion = nil
    _watchTicker = C_Timer.NewTicker(0.4, WatchTick)
    ShowEditBanner(group)
    SetEditOverlayShown(true)
    UpdateIndicator()
    UpdateEditLocks()
    RequestGoldWalk()
    EnsurePanelHideHook()
end

-------------------------------------------------------------------------------
--  Editing-as-CONDITIONAL: the same session machinery banking into the
--  conditional store. Mutually exclusive with editing-as-spec and the
--  Default view. Spec-owned fkeys are refused at capture time (spec wins).
-------------------------------------------------------------------------------

--- Banks live values into the edited group's maps. EVERY entry is examined, not just
--- the group's own: an fkey first overridden by another conditional lives in THAT
--- group's entry, and this session's edit to it must still bank here (entry.group is
--- card bookkeeping, not harvest ownership; the spec side harvests the whole store
--- the same way). Per fkey: live equal to the recorded default clears the group's
--- override, anything else banks; empty maps drop so cards only list entries the
--- group actually customizes.
function Cond.HarvestEdit(g)
    for _, entry in ipairs(Cond.GetStore() or {}) do
        if entry.values and entry.values.default then
            local map = entry.values[g.id]
            for fkey, dv in pairs(entry.values.default) do
                local live = ReadLive(fkey)
                -- Table-typed live: structure change, never bank (aliasing).
                -- FKeyLoaded: a disabled module reads nil, never bank that.
                -- MatchOwnedFKey: match-engine writes never bank (mirrors the
                -- spec-side Harvest); the held value stays as-is.
                if FKeyLoaded(fkey) and type(live) ~= "table"
                   and not MatchOwnedFKey(fkey) then
                    local defVal = (dv == NIL_SENT) and nil or dv
                    if live == defVal then
                        -- Equal to the default: a REVERT only if this session
                        -- moved it there. An untouched key that merely compares
                        -- equal (the default was edited onto the group's value)
                        -- keeps its held value instead of dissolving.
                        local s = _enterSnap and SnapValue(_enterSnap, fkey)
                        if type(s) == "table" then s = nil end
                        if map and _enterSnap and s ~= live then
                            map[fkey] = nil
                        end
                    else
                        if not map then map = {}; entry.values[g.id] = map end
                        map[fkey] = (live == nil) and NIL_SENT or live
                    end
                end
            end
            if map and not next(map) then entry.values[g.id] = nil end
        end
    end
    Cond.PruneRedundant()
end

--- Exit sweep: uncaptured session diffs become new conditional entries
--- (mirror of SweepUncaptured with conditional ownership rules).
function Cond.SweepUncapturedEdit(g)
    if not _enterSnap or not g then return end
    local store = Cond.GetStore(true)
    if not store then return end
    local added = false
    for _, c in ipairs(DiffProfiles(_enterSnap)) do
        -- Spec ownership does NOT block cond capture (coexistence: each store
        -- keeps its own value; spec wins only at runtime). MatchOwnedFKey:
        -- never mint from a match engine write (see SweepUncaptured).
        if not Cond.EntryOwning(c.fkey)
           and (not c.num or NumAllowedFKey(c.fkey)) and not BlacklistedFKey(c.fkey)
           and not MatchOwnedFKey(c.fkey)
           and not _sessionIgnored[c.fkey] then
            local orig = SnapValue(_enterSnap, c.fkey)
            if type(orig) == "table" then orig = nil end
            local entry = {
                label = PrettyKey(c.fkey),
                crumb = (EllesmereUI.GetModuleTitle and EllesmereUI:GetModuleTitle(c.folder)) or c.folder,
                module = c.folder,
                group = g.id,
                values = { default = { [c.fkey] = (orig == nil) and NIL_SENT or orig } },
            }
            store[#store + 1] = entry
            added = true
        end
    end
    if added then Cond.RebuildIndex() end
end

--- noRestore: a spec transition is taking over. Even then the SPEC layer is written
--- back first -- the session swapped shared defaults over the spec-owned fkeys, and
--- the transition's Harvest(oldSpec) must bank real spec values, never the
--- session's default baseline. noRecheck: the caller drives its own choreography
--- and must not have a conditional transition interleaved (see CloseEditSessions).
Cond.ExitEdit = function(noRestore, noRecheck)
    if not Cond._edit then return end
    WatchTick()   -- catch trailing edits from the last sub-tick window
    -- Release the Buff Manager session swap FIRST: banks the session's BM edits
    -- into the group's fork while live still holds them, then puts the runtime
    -- layer back (skipped on noRestore: the transition's ApplyBm does it).
    if EllesmereUI.SpecOverrides_BmSessionRelease then
        EllesmereUI.SpecOverrides_BmSessionRelease(noRestore and true or false)
    end
    if EllesmereUI.SpecOverrides_DmSessionRelease then
        EllesmereUI.SpecOverrides_DmSessionRelease(noRestore and true or false)
    end
    local g = Cond._edit
    Cond._edit = nil
    Cond.SweepUncapturedEdit(g)
    Cond.HarvestEdit(g)
    TeardownEditSession()
    local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
    if not noRestore then
        -- Canonical live = spec values + the APPLIED conditional's overlay.
        local t2 = Cond.WriteValues(
            EllesmereUI.Conditions_AppliedGid and EllesmereUI.Conditions_AppliedGid() or nil)
        if t2 then
            touched = touched or {}
            for k in pairs(t2) do touched[k] = true end
        end
        if touched then RunRefreshers(touched) end
        -- FORCED rebuild: see ExitGroupEdit (stale structure otherwise).
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
        RequestGoldWalk()
        if PanelShown() then EnterDefaultView() end
        -- A mid-session condition flip was deferred (the transition handler
        -- bails during edit sessions); resolve it now.
        if not noRecheck and EllesmereUI.Conditions_Recheck then
            EllesmereUI.Conditions_Recheck()
        end
    end
    -- noRestore: store writes only -- the transition applies + refreshes.
    if Cond.UpdateButton then Cond.UpdateButton() end
    if Cond.RefreshCards then Cond.RefreshCards() end
end

Cond.EnterEdit = function(g)
    if Cond._edit == g then return end
    if not g then return end
    -- BM page lock: while the Buff Manager page is bound to a live fork, only
    -- that fork's own conditional session may open; anything else would edit
    -- settings the page is not displaying.
    do
        local lockKind, lockGid
        local lockLabel = "Buff Manager"
        if EllesmereUI.SpecOverrides_BmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_BmPageLockInfo()
        end
        if not lockKind and EllesmereUI.SpecOverrides_DmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_DmPageLockInfo()
            if lockKind then lockLabel = "Debuff Manager" end
        end
        if lockKind and not (lockKind == "cond" and lockGid == g.id) then
            EllesmereUI:ShowConfirmPopup({
                title = string.format(L("%s Override Active"), L(lockLabel)),
                message = string.format(L("The active override's custom %s is bound to this page. Leave the %s tab to switch to another override."), L(lockLabel), L(lockLabel)),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    -- Preamble teardown, not the user finishing: no conditional recheck (a
    -- deferred flip resolves at the session end that really ends editing).
    if Cond._edit then Cond.ExitEdit(nil, true) end
    if _editGroup then ExitGroupEdit(true) end
    -- The session's baseline is the SHARED DEFAULT view: a conditional layers on the
    -- defaults, so a fresh one must look exactly like "no overrides", never like the
    -- current spec's override view. Spec values only win at APPLY time; while editing a
    -- conditional the panel shows conditional-over-default.
    local touched
    if _defaultView then
        -- Panel already shows the defaults; bank its edits and keep them live
        -- (no spec restore) -- that IS our baseline.
        ExitDefaultView(false)
    else
        EllesmereUI.SpecOverrides_HarvestCurrent()
        touched = WriteDefaultValues()
    end
    Cond._edit = g
    local t2 = Cond.WriteValues(g.id, true)
    if t2 then
        touched = touched or {}
        for k in pairs(t2) do touched[k] = true end
    end
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild (structure may differ under the conditional's values).
    if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    _watchSnap = SnapshotProfiles()
    _enterSnap = _watchSnap
    _sessionIgnored = {}
    _lastRegion = nil
    _watchTicker = C_Timer.NewTicker(0.4, WatchTick)
    ShowEditBanner(g)
    SetEditStatus(L("Any setting you change now applies only while this conditional is active."), 1, 1, 0.6)
    SetEditOverlayShown(true)
    UpdateIndicator()
    UpdateEditLocks()
    RequestGoldWalk()
    EnsurePanelHideHook()
    if Cond.UpdateButton then Cond.UpdateButton() end
end

-------------------------------------------------------------------------------
--  Group icon rendering
-------------------------------------------------------------------------------
local function ApplyGroupIcon(tex, icon)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1, 1)
    if icon and icon.kind == "cond" and Cond.ICONS[icon.key] then
        tex:SetTexture(Cond.ICON_DIR .. Cond.ICONS[icon.key])
    elseif icon and icon.kind == "multi" then
        tex:SetTexture(MULTISPEC_ICON)
    elseif icon and icon.kind == "role" and ROLE_ICONS[icon.key] then
        tex:SetTexture(ROLE_ICONS[icon.key])
    elseif icon and icon.kind == "class" and CLASS_COORDS[icon.key] then
        tex:SetTexture(MODERN_SPRITE)
        local c = CLASS_COORDS[icon.key]
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        -- Default (no group icon): the player's class glyph in natural colors,
        -- matching the toolbar button.
        tex:SetTexture(GLYPH_SPRITE)
        local _, classFile = UnitClass("player")
        local c = classFile and CLASS_COORDS[classFile]
        if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
    end
end

-------------------------------------------------------------------------------
--  Toolbar button + active-group indicator
-------------------------------------------------------------------------------
local specBtn, indicatorBtn

-- The spec-overrides button keeps ONE identity: the natural class glyph and the
-- standard tooltip regardless of editing/active state (no icon or tooltip
-- morphing). The second indicator icon stays retired.
UpdateIndicator = function()
    if indicatorBtn then indicatorBtn:Hide() end   -- retired second icon
    if not specBtn or not specBtn._tex then return end
    specBtn._tex:SetTexture(GLYPH_SPRITE)
    local _, classFile = UnitClass("player")
    local c = classFile and CLASS_COORDS[classFile]
    if c then specBtn._tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
    specBtn._tex:SetDesaturated(false)
    specBtn._tex:SetVertexColor(1, 1, 1, 1)
end

--- The toolbar button is DISABLED while the active page is excluded from the
--- override systems (blacklisted module pages, QoL Shifter/Upgrade Calc):
--- dimmed, click refused, explanatory tooltip. Re-evaluated on every
--- module/page selection (called from OnPageRebuilt).
EllesmereUI._specOvBtnPageState = function()
    if not specBtn then return end
    local off = IsExcludedContext()
    -- Buff Manager page bound to a live fork: block the dropdown entirely (the
    -- page edits that fork no matter what).
    local bmLock = false
    if not off and EllesmereUI.SpecOverrides_BmPageLocked then
        bmLock = EllesmereUI.SpecOverrides_BmPageLocked()
    end
    if not bmLock and not off and EllesmereUI.SpecOverrides_DmPageLocked then
        bmLock = EllesmereUI.SpecOverrides_DmPageLocked()
    end
    specBtn._ovPageDisabled = off or nil
    specBtn._ovBmLocked = bmLock or nil
    specBtn:SetAlpha((off or bmLock) and 0.35 or 0.9)
end

--- Draws attention to the toolbar glyph: a gold pulsing wash + ring over the
--- button for ~8 pulses, or until it is clicked. Used by the Settings Overrides
--- announcement's "Show Me" landing.
local function StopButtonPulse()
    if specBtn and specBtn._pulse then
        specBtn._pulseAG:Stop()
        specBtn._pulse:Hide()
    end
    if specBtn and specBtn._pulseTip then
        specBtn._pulseTipAG:Stop()
        specBtn._pulseTip:Hide()
    end
end

function EllesmereUI.SpecOverrides_PulseButton()
    if not specBtn then return end
    local p = specBtn._pulse
    if not p then
        p = CreateFrame("Frame", nil, specBtn)
        p:SetPoint("TOPLEFT", specBtn, "TOPLEFT", -5, 5)
        p:SetPoint("BOTTOMRIGHT", specBtn, "BOTTOMRIGHT", 5, -5)
        -- Soft gold wash (low alpha so the glyph stays readable) plus a gold
        -- ring; the whole frame's alpha is what pulses.
        local wash = p:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints()
        wash:SetColorTexture(1, 0.82, 0.30, 0.14)
        EllesmereUI.MakeBorder(p, 1, 0.82, 0.30, 0.9)
        local ag = p:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local a1 = ag:CreateAnimation("Alpha")
        a1:SetFromAlpha(1); a1:SetToAlpha(0.15)
        a1:SetDuration(0.45); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
        local a2 = ag:CreateAnimation("Alpha")
        a2:SetFromAlpha(0.15); a2:SetToAlpha(1)
        a2:SetDuration(0.45); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
        ag:SetScript("OnLoop", function(self)
            self._loops = (self._loops or 0) + 1
            if self._loops >= 8 then StopButtonPulse() end
        end)
        specBtn._pulse = p
        specBtn._pulseAG = ag
    end
    -- Bouncing callout chip below the button: "New Overrides System".
    local tip = specBtn._pulseTip
    if not tip then
        tip = CreateFrame("Frame", nil, specBtn)
        tip:SetFrameStrata("DIALOG")   -- above the page content below the bar
        local lbl = EllesmereUI.MakeFont(tip, 12, nil, 1, 0.82, 0.30, 1)
        lbl:SetPoint("CENTER")
        lbl:SetText(L("New Overrides System"))
        local w = (lbl:GetStringWidth() or 120) + 20
        tip:SetSize(w, 24)
        tip:SetPoint("TOP", specBtn, "BOTTOM", 0, -8)
        local tbg = EllesmereUI.SolidTex(tip, "BACKGROUND", 0.05, 0.06, 0.08, 0.95)
        EllesmereUI.MakeBorder(tip, 1, 0.82, 0.30, 0.85)
        local ag = tip:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local t1 = ag:CreateAnimation("Translation")
        t1:SetOffset(0, -4); t1:SetDuration(0.45); t1:SetOrder(1); t1:SetSmoothing("IN_OUT")
        local t2 = ag:CreateAnimation("Translation")
        t2:SetOffset(0, 4); t2:SetDuration(0.45); t2:SetOrder(2); t2:SetSmoothing("IN_OUT")
        specBtn._pulseTip = tip
        specBtn._pulseTipAG = ag
    end
    specBtn._pulseAG._loops = 0
    p:Show()
    tip:Show()
    specBtn._pulseAG:Play()
    specBtn._pulseTipAG:Play()
end

--- Decorates and wires the toolbar button created in the tab bar (main panel).
function EllesmereUI.SpecOverrides_SetupButton(btn)
    specBtn = btn
    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(GLYPH_SPRITE)
    -- Natural-color glyph: 90% opacity idle, full on hover.
    local _, classFile = UnitClass("player")
    local c = classFile and CLASS_COORDS[classFile]
    if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
    btn._tex = tex
    btn:SetAlpha(0.9)
    btn:SetScript("OnEnter", function(self)
        if self._ovPageDisabled then
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, L("This page is excluded from overrides."))
            end
            return
        end
        if self._ovBmLocked then
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, L("Overrides are locked: this page's custom Buff Manager is active. Leave the Buff Manager tab to manage overrides."))
            end
            return
        end
        self:SetAlpha(1)
        if EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, L("Settings Overrides"))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha((self._ovPageDisabled or self._ovBmLocked) and 0.35 or 0.9)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    btn:SetScript("OnClick", function(self)
        StopButtonPulse()   -- attention served the moment it is clicked
        if self._ovPageDisabled then return end
        if self._ovBmLocked then
            -- Blocked: explain at the icon instead of opening the dropdown.
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, L("Overrides are locked: this page's custom Buff Manager is active. Leave the Buff Manager tab to manage overrides."))
            end
            return
        end
        -- First-ever press shows the Settings Overrides video guide instead of
        -- the cards popup; later presses behave normally (FireOnce returns
        -- false once seen; the nil-guard covers standalone builds).
        local VG = EllesmereUI.VideoGuides
        if VG and VG.FireOnce("settings_overrides") then return end
        EllesmereUI.SpecOverrides_ToggleCardsPopup(self)
    end)
    UpdateIndicator()
    EllesmereUI._specOvBtnPageState()
end

-------------------------------------------------------------------------------
--  Group creation: spec picker -> name + icon popup
-------------------------------------------------------------------------------
local nameIconPopup

local function ShowNameIconPopup(specIDs, editing)
    if not nameIconPopup then
        local p = CreateFrame("Frame", nil, UIParent)
        p:SetSize(380, 300)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetFrameLevel(220)
        p:EnableMouse(true)
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
        EllesmereUI.MakeBorder(p, 1, 1, 1, 0.15)

        local title = EllesmereUI.MakeFont(p, 14, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        title:SetPoint("TOP", p, "TOP", 0, -14)
        title:SetText(L("New Spec Group"))
        p._title = title

        local nameLbl = EllesmereUI.MakeFont(p, 12, nil, 1, 1, 1, 0.6)
        nameLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -44)
        nameLbl:SetText(L("Name"))

        local nameBox = CreateFrame("EditBox", nil, p)
        nameBox:SetSize(340, 26)
        nameBox:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -62)
        nameBox:SetAutoFocus(false)
        nameBox:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
        nameBox:SetTextColor(1, 1, 1, 1)
        nameBox:SetTextInsets(8, 8, 0, 0)
        nameBox:SetMaxLetters(24)
        EllesmereUI.SolidTex(nameBox, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        EllesmereUI.MakeBorder(nameBox, 1, 1, 1, 0.12)
        nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        p._nameBox = nameBox

        local iconLbl = EllesmereUI.MakeFont(p, 12, nil, 1, 1, 1, 0.6)
        iconLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -102)
        iconLbl:SetText(L("Icon"))

        -- Icon grid: multi-spec + 3 modern role icons + 13 modern class icons
        p._iconBtns = {}
        local defs = { { kind = "multi" } }
        for _, role in ipairs(ROLE_ORDER) do
            defs[#defs + 1] = { kind = "role", key = role }
        end
        for _, cls in ipairs(CLASS_ORDER) do
            defs[#defs + 1] = { kind = "class", key = cls }
        end
        local PER_ROW, SZ, GAP = 8, 34, 8
        for i, def in ipairs(defs) do
            local col = (i - 1) % PER_ROW
            local rowI = math.floor((i - 1) / PER_ROW)
            local b = CreateFrame("Button", nil, p)
            b:SetSize(SZ, SZ)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", 20 + col * (SZ + GAP), -122 - rowI * (SZ + GAP))
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            ApplyGroupIcon(t, def)
            local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.10)
            b._def = def
            b._brd = brd
            b:SetScript("OnClick", function(self)
                p._selectedIcon = self._def
                for _, ob in ipairs(p._iconBtns) do
                    if ob._brd and ob._brd.SetColor then
                        ob._brd:SetColor(1, 1, 1, ob == self and 0 or 0.10)
                    end
                    if ob._brd and ob._brd.SetColor and ob == self then
                        ob._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                    end
                    ob:SetAlpha(ob == self and 1 or 0.7)
                end
            end)
            b:SetAlpha(0.7)
            p._iconBtns[#p._iconBtns + 1] = b
        end

        local create = CreateFrame("Button", nil, p)
        create:SetSize(110, 28)
        -- +44 centers the action+cancel pair (110 + 8 gap + 80 = 198 wide).
        create:SetPoint("BOTTOM", p, "BOTTOM", 44, 14)
        EllesmereUI.SolidTex(create, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local cbrd = EllesmereUI.MakeBorder(create, ACCENT_R, ACCENT_G, ACCENT_B, 0.5)
        local clbl = EllesmereUI.MakeFont(create, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        clbl:SetPoint("CENTER")
        clbl:SetText(L("Create Group"))
        p._createLbl = clbl
        create:SetScript("OnEnter", function() if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end end)
        create:SetScript("OnLeave", function() if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5) end end)
        create:SetScript("OnClick", function()
            -- EDIT mode: rename/re-icon the existing group (specs were already
            -- applied by the picker's Next step).
            local editing = p._editing
            if editing then
                local name = p._nameBox:GetText()
                if name and name ~= "" then editing.name = name end
                if p._selectedIcon then editing.icon = p._selectedIcon end
                p:Hide()
                if UpdateIndicator then UpdateIndicator() end
                if RefreshCardsPopup then RefreshCardsPopup() end
                local ap = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
                if ap == LIST_PAGE then EllesmereUI:RefreshPage(true) end
                return
            end
            local specs = p._specs
            if not specs or #specs == 0 then p:Hide(); return end
            local groups = GetGroups(true)
            if not groups then p:Hide(); return end
            local id = NextGroupId()
            local name = p._nameBox:GetText()
            if not name or name == "" then name = L("Group") .. " " .. id end
            local g = {
                id = id, name = name,
                icon = p._selectedIcon or { kind = "role", key = "DAMAGER" },
                specs = specs,
            }
            groups[#groups + 1] = g
            p:Hide()
            -- Auto-activate: a new group goes straight into its "Editing as"
            -- session. EnterGroupEdit self-guards the BM page lock and tears
            -- down any active session.
            EnterGroupEdit(g)
            if UpdateIndicator then UpdateIndicator() end   -- current spec may have joined
            if RefreshCardsPopup then RefreshCardsPopup() end
        end)

        local cancel = CreateFrame("Button", nil, p)
        cancel:SetSize(80, 28)
        cancel:SetPoint("RIGHT", create, "LEFT", -8, 0)
        EllesmereUI.SolidTex(cancel, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local xbrd = EllesmereUI.MakeBorder(cancel, 1, 1, 1, 0.22)
        local xlbl = EllesmereUI.MakeFont(cancel, 12, nil, 1, 1, 1, 0.7)
        xlbl:SetPoint("CENTER")
        xlbl:SetText(L("Cancel"))
        cancel:SetScript("OnEnter", function() if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.4) end end)
        cancel:SetScript("OnLeave", function() if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.22) end end)
        cancel:SetScript("OnClick", function() p:Hide() end)

        nameIconPopup = p
        EllesmereUI._specOvNamePopup = p   -- panel-hide hook closes it (lexical: local declared below the hook)
    end
    nameIconPopup._specs = specIDs
    nameIconPopup._editing = editing
    nameIconPopup._title:SetText(editing
        and string.format(L("Edit Group: %s"), editing.name or "?")
        or L("New Spec Group"))
    nameIconPopup._createLbl:SetText(editing and L("Save") or L("Create Group"))
    nameIconPopup._nameBox:SetText(editing and (editing.name or "") or "")
    nameIconPopup._selectedIcon = nil
    for _, ob in ipairs(nameIconPopup._iconBtns) do
        -- EDIT mode pre-selects the group's current icon.
        local sel = editing and editing.icon and ob._def
            and ob._def.kind == editing.icon.kind
            and ob._def.key == editing.icon.key or false
        if sel then nameIconPopup._selectedIcon = ob._def end
        ob:SetAlpha(sel and 1 or 0.7)
        if ob._brd and ob._brd.SetColor then
            if sel then
                ob._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
            else
                ob._brd:SetColor(1, 1, 1, 0.10)
            end
        end
    end
    nameIconPopup:Show()
end

local function StartGroupCreation()
    if not EllesmereUI.ShowSpecAssignPopup then return end
    local dummyDB = { _specOv = { _specs = {} } }
    EllesmereUI:ShowSpecAssignPopup({
        db        = dummyDB,
        dbKey     = "_specOv",
        presetKey = "_specs",
        title     = L("New Spec Group"),
        subtitle  = L("Select the specs this group edits:"),
        buttonText = L("Next"),
        preCheckedSpecs = {},
        onConfirm = function(assignments)
            -- Specs may belong to multiple groups; settings a shared spec
            -- already overrides in another group are conflict-locked (red)
            -- while editing this one.
            local specs = {}
            for specID, on in pairs(assignments or {}) do
                if on and type(specID) == "number" then
                    specs[#specs + 1] = specID
                end
            end
            table.sort(specs)
            if #specs == 0 then return end
            ShowNameIconPopup(specs)
        end,
    })
end

-------------------------------------------------------------------------------
--  Cards popup
-------------------------------------------------------------------------------
local cardsPopup

local function BuildCardRow(parent, y, opts)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(parent:GetWidth() - 20, 40)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    local brd = EllesmereUI.MakeBorder(row, 1, 1, 1, opts.active and 0 or 0.08)
    if opts.active and brd and brd.SetColor then
        brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
    end
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    if opts.iconApply then opts.iconApply(icon) end
    local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, opts.dim and 0.55 or 0.9)
    name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    name:SetText(opts.name)
    if opts.tooltip then
        row:SetScript("OnEnter", function(self)
            if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self, opts.tooltip) end
        end)
        row:SetScript("OnLeave", function()
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
    end
    if opts.locked then
        -- BM page lock: not selectable while another override's Buff Manager is
        -- bound to the open page. Dim + inert (tooltip only).
        row:SetAlpha(0.4)
        row:SetScript("OnClick", function(self)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, L("The active override's Buff Manager is bound to the open page. Leave the Buff Manager tab to switch overrides."))
            end
        end)
    else
        row:SetScript("OnClick", opts.onClick)
    end
    local del
    if opts.deletable then
        del = CreateFrame("Button", nil, row)
        del:SetSize(20, 20)
        del:SetPoint("RIGHT", row, "RIGHT", -6, 1)
        del:SetFrameLevel(row:GetFrameLevel() + 2)
        -- Same close glyph the Blizzard window skins use.
        local xt = del:CreateTexture(nil, "OVERLAY")
        xt:SetAtlas("uitools-icon-close")
        xt:SetSize(15, 15)
        xt:SetPoint("CENTER", del, "CENTER", 0, -2)
        xt:SetVertexColor(1, 1, 1, 0.75)
        del:SetScript("OnEnter", function(self)
            xt:SetVertexColor(1, 1, 1, 1)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, L("Delete Override Group"))
            end
        end)
        del:SetScript("OnLeave", function()
            xt:SetVertexColor(1, 1, 1, 0.75)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        del:SetScript("OnClick", opts.onDelete)
    end
    local ed
    if opts.onEdit then
        ed = CreateFrame("Button", nil, row)
        ed:SetSize(16, 16)
        if del then
            -- del sits 1px high; -2 relative lands the pencil 1px low on the row.
            ed:SetPoint("RIGHT", del, "LEFT", -1, -2)
        else
            ed:SetPoint("RIGHT", row, "RIGHT", -5, -1)
        end
        ed:SetFrameLevel(row:GetFrameLevel() + 2)
        local ico = ed:CreateTexture(nil, "OVERLAY")
        ico:SetAllPoints()
        if ico.SetSnapToPixelGrid then ico:SetSnapToPixelGrid(false); ico:SetTexelSnappingBias(0) end
        ico:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png")
        ed:SetAlpha(0.75)
        ed:SetScript("OnEnter", function(self)
            self:SetAlpha(1)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, L("Edit Override Group"))
            end
        end)
        ed:SetScript("OnLeave", function(self)
            self:SetAlpha(0.75)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        ed:SetScript("OnClick", opts.onEdit)
    end
    if opts.onUnlock then
        local ub = CreateFrame("Button", nil, row)
        -- Native art is 37x42; keep the aspect ratio at 16px height.
        ub:SetSize(16 * 37 / 42, 16)
        if ed then
            -- The pencil sits 1px low; +1 recenters the unlock icon on the row.
            ub:SetPoint("RIGHT", ed, "LEFT", -4, 1)
        elseif del then
            ub:SetPoint("RIGHT", del, "LEFT", -4, -1)
        else
            ub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        end
        ub:SetFrameLevel(row:GetFrameLevel() + 2)
        local ico = ub:CreateTexture(nil, "OVERLAY")
        ico:SetAllPoints()
        if ico.SetSnapToPixelGrid then ico:SetSnapToPixelGrid(false); ico:SetTexelSnappingBias(0) end
        ico:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-unlocked-small.png")
        local enabled = opts.unlockEnabled
        ub:SetAlpha(enabled and 0.75 or 0.3)
        ub:SetScript("OnEnter", function(self)
            if enabled then self:SetAlpha(1) end
            if EllesmereUI.ShowWidgetTooltip then
                local tip
                if enabled then
                    tip = L("Customize Unlock Mode")
                else
                    -- Owner-locked (another group provides this spec's unlock mode) has
                    -- its own text; non-membership gets the switch-spec hint.
                    tip = opts.unlockLockedTooltip
                        or L("Switch to a spec in this group to customize its Unlock Mode")
                end
                EllesmereUI.ShowWidgetTooltip(self, tip)
            end
        end)
        ub:SetScript("OnLeave", function(self)
            self:SetAlpha(enabled and 0.75 or 0.3)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        ub:SetScript("OnClick", function()
            if enabled then opts.onUnlock() end
        end)
    end
    return row, 44
end

-- Seed-map copy for membership adds, MINUS match-owned size keys: a seed member's map
-- can carry stale match-engine widths, and copying them forward replicates the poison
-- onto every spec added to the group. Returns a fresh filtered table per call (never
-- aliases one table across member ids), nil when nothing survives.
local function CopySeedMap(seedMap)
    if not seedMap then return nil end
    local out
    for k, v in pairs(seedMap) do
        if not MatchOwnedFKey(k) then
            out = out or {}
            out[k] = (type(v) == "table") and DeepCopy(v) or v
        end
    end
    return out
end

-- Applies a membership change: ADDED specs receive the group's current override values
-- (copied from the seed member, falling back to the defaults), REMOVED specs lose their
-- stored values (reverting to the baseline on their next apply). The live profile
-- re-syncs immediately so a current-spec join/leave takes effect without a spec swap.
local function SetGroupSpecs(g, newSpecs)
    if _editGroup == g then ExitGroupEdit(true) end
    local oldSet, newSet = {}, {}
    for _, id in ipairs(g.specs or {}) do oldSet[id] = true end
    for _, id in ipairs(newSpecs) do newSet[id] = true end
    local seed = g.specs and g.specs[1]
    for _, entry in ipairs(GetStore() or {}) do
        if entry.group == g.id then
            -- capture the group's canonical values BEFORE removals (the seed
            -- member itself may be leaving)
            local seedMap = seed and entry.values[seed]
            for id in pairs(oldSet) do
                if not newSet[id] then entry.values[id] = nil end
            end
            for _, id in ipairs(newSpecs) do
                if not oldSet[id] then
                    -- Seed ONLY from a real member map: a verbatim copy of
                    -- values.default would pin the new member at the CURRENT
                    -- default forever (the sticky harvest retains held values).
                    -- With no map, WriteSpecValues' per-key default fallback
                    -- gives the same live result and keeps following future
                    -- default edits. Match-owned keys are filtered out.
                    entry.values[id] = CopySeedMap(seedMap)
                end
            end
        end
    end
    g.specs = newSpecs
    -- Added specs must receive the group's values EVERYWHERE those values live, not
    -- only on creator-tagged entries: auto-capture binds edits to an existing entry
    -- by slot identity across the WHOLE store, and session exits bank into every
    -- non-conflicting entry, so a group's member values routinely sit on entries it
    -- never created. The owned-entry loop above misses those, leaving the added spec
    -- with NO map there, so WriteSpecValues' per-key default fallback would resolve
    -- it to the shared default at every apply instead ("the override took my live
    -- value" for a joining CURRENT spec). Mirrors HarvestGroup's store-wide scope.
    -- Runs AFTER g.specs = newSpecs so conflicts judge against NEW membership, and
    -- BEFORE the ex-member sweep so a leaving seed member's foreign maps are still
    -- readable. Empty/absent seed maps write NOTHING, so the default fallback keeps
    -- following future edits and a foreign entry's existing legacy data is untouched.
    for _, entry in ipairs(GetStore() or {}) do
        if entry.group ~= g.id and entry.values and not ConflictSpec(entry, g) then
            local seedMap = seed and entry.values[seed]
            if seedMap and next(seedMap) ~= nil then
                for _, id in ipairs(newSpecs) do
                    if not oldSet[id] then
                        -- Fresh filtered copy PER id; nil when only
                        -- match-owned keys existed.
                        local copy = CopySeedMap(seedMap)
                        if copy then entry.values[id] = copy end
                    end
                end
            end
        end
    end
    -- Removed specs must lose their values EVERYWHERE, not only on this group's
    -- creator-tagged entries: session exits bank into every non-conflicting entry
    -- (shared slots), so a removed spec's values can live on another group's
    -- entries the loop above never looked at, leaving the spec overridden forever
    -- while "not assigned" to anything. Only specs left in NO group are cleared; a
    -- spec still in another group keeps its maps (that group's flows re-derive
    -- them). LEGACY entries (group == nil) are exempt: their per-spec values are
    -- user data this group never owned.
    for id in pairs(oldSet) do
        if not newSet[id] and not SpecInAnyGroup(id) then
            for _, entry in ipairs(GetStore() or {}) do
                if entry.values and entry.group ~= nil then entry.values[id] = nil end
            end
        end
    end
    -- Ingress guard for STRANDED values: a removed spec still in ANOTHER group is
    -- skipped by the blanket sweep above, but values THIS group's sessions banked
    -- onto foreign non-conflicting entries stay behind -- and when every group the
    -- spec still belongs to is conflict-locked against that entry's owner, no
    -- session can ever edit or remove them again (permanently pinned off the shared
    -- default, invisible in the list's group buckets). Removing the spec from this
    -- group means "stop overriding it here", so clear exactly those: only entries
    -- this group could reach BEFORE the change (its own swept in the first loop),
    -- and only values stranded under the NEW membership; values another group can
    -- still reach are kept. Pre-existing strays this group never could reach are
    -- untouched -- the management list surfaces those with a Remove control.
    local oldGroupView = { id = g.id, specs = {} }
    for id in pairs(oldSet) do
        oldGroupView.specs[#oldGroupView.specs + 1] = id
    end
    for id in pairs(oldSet) do
        if not newSet[id] and SpecInAnyGroup(id) then
            for _, entry in ipairs(GetStore() or {}) do
                if entry.values and entry.values[id] ~= nil
                    and entry.group ~= nil and entry.group ~= g.id
                    and not ConflictSpec(entry, oldGroupView)
                    and SpecStrandedOnEntry(entry, id) then
                    entry.values[id] = nil
                end
            end
        end
    end
    if EllesmereUI.SpecOverrides_Apply then
        EllesmereUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
    end
    UpdateIndicator()
    RequestGoldWalk()
    RefreshCardsPopup()
end

local function EditGroupSpecs(g)
    if not EllesmereUI.ShowSpecAssignPopup then return end
    if cardsPopup then cardsPopup:Hide() end
    local preChecked = {}
    for _, id in ipairs(g.specs or {}) do preChecked[id] = true end
    local dummyDB = { _specOv = { _specs = {} } }
    EllesmereUI:ShowSpecAssignPopup({
        db        = dummyDB,
        dbKey     = "_specOv",
        presetKey = "_specs",
        title     = string.format(L("Edit Group: %s"), g.name or "?"),
        subtitle  = L("Select the specs this group edits:"),
        buttonText = L("Next"),
        preCheckedSpecs = preChecked,
        onConfirm = function(assignments)
            local specs = {}
            for specID, on in pairs(assignments or {}) do
                if on and type(specID) == "number" then
                    specs[#specs + 1] = specID
                end
            end
            table.sort(specs)
            SetGroupSpecs(g, specs)
            -- Step 2: name + icon (same screen the creation flow ends on).
            ShowNameIconPopup(nil, g)
        end,
    })
end

RefreshCardsPopup = function()
    local p = cardsPopup
    if not p or not p:IsShown() then return end
    -- clear old rows
    for _, r in ipairs(p._rows or {}) do r:Hide(); r:SetParent(nil) end
    p._rows = {}

    local y = -40
    local function add(row, h)
        p._rows[#p._rows + 1] = row
        y = y - h
    end

    -- Default editing mode (exit editing-as). The border tracks the EDITING selection
    -- only (which card's values the panel edits), never the runtime-applied state:
    -- standing in a dungeon must not light the dungeon card while Default is selected.
    add(BuildCardRow(p, y, {
        name = L("Default Editing Mode"),
        active = not _editGroup and not Cond._edit,
        iconApply = function(tex) ApplyGroupIcon(tex, nil) end,
        tooltip = L("Edit normally: changes apply to your current spec"),
        onClick = function()
            ExitGroupEdit()
            if Cond.ExitEdit then Cond.ExitEdit() end
            RefreshCardsPopup()
        end,
    }))

    -- BM page lock: while the Buff Manager page is bound to a live fork,
    -- every group card except the bound one is dimmed and inert.
    local bmLockKind, bmLockGid
    if EllesmereUI.SpecOverrides_BmPageLockInfo then
        bmLockKind, bmLockGid = EllesmereUI.SpecOverrides_BmPageLockInfo()
    end
    if not bmLockKind and EllesmereUI.SpecOverrides_DmPageLockInfo then
        bmLockKind, bmLockGid = EllesmereUI.SpecOverrides_DmPageLockInfo()
    end

    -- Saved groups
    local curSpec = CurrentSpecID()
    -- Exclusive unlock-layer ownership: a shared spec's unlock mode belongs to
    -- ONE group (first in creation order with a layout). Every other group's
    -- unlock button is owner-locked for this spec: dimmed with a tooltip naming
    -- the owner (the entry function refuses too; this shows it before a click).
    local curOwnerGid = OwnerGid(curSpec)
    local curOwnerName
    if curOwnerGid then
        local og = GroupById(curOwnerGid)
        curOwnerName = (og and og.name) or "?"
    end
    for _, g in ipairs(GetGroups() or {}) do
        local names = {}
        local isMember = false
        for _, id in ipairs(g.specs or {}) do
            names[#names + 1] = SpecName(id)
            if id == curSpec then isMember = true end
        end
        local ownerLocked = (isMember and curOwnerGid and curOwnerGid ~= g.id) or false
        add(BuildCardRow(p, y, {
            name = g.name or "?",
            active = _editGroup == g,
            locked = (bmLockKind and not (bmLockKind == "spec" and bmLockGid == g.id)) or nil,
            iconApply = function(tex) ApplyGroupIcon(tex, g.icon) end,
            tooltip = table.concat(names, "\n"),
            deletable = true,
            unlockEnabled = isMember and not ownerLocked,
            unlockLockedTooltip = ownerLocked
                and string.format(L("This spec's custom unlock mode is owned by '%s'. Customize it there, or remove the spec from that group."), curOwnerName)
                or nil,
            onUnlock = function()
                p:Hide()
                EllesmereUI.SpecOverrides_EnterUnlockForGroup(g)
            end,
            onEdit = function() EditGroupSpecs(g) end,
            onClick = function()
                if _editGroup == g then
                    ExitGroupEdit()
                else
                    EnterGroupEdit(g)
                end
                RefreshCardsPopup()
            end,
            onDelete = function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Spec Group"),
                    message = string.format(L("Delete the group '%s'? Its captured overrides are removed with it; settings keep their current live values."), g.name or "?"),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if _editGroup == g then ExitGroupEdit(true) end
                        local groups = GetGroups()
                        if groups then
                            for i, gg in ipairs(groups) do
                                if gg == g then table.remove(groups, i); break end
                            end
                        end
                        -- The group's overrides go with it (settings keep
                        -- whatever is live; with the panel open that is the
                        -- Default view's baseline).
                        local st = GetStore()
                        if st then
                            -- Values-aware removal: entries CREATED by this group can carry
                            -- OTHER groups' banked values (session exits bank into every
                            -- non-conflicting entry), so deleting wholesale would destroy
                            -- those overrides plus the shared default. RETAG to the first
                            -- surviving group holding values on the entry; delete only when
                            -- none does (the group is already off the list, so
                            -- EntryHolderGroup sees only survivors).
                            for i = #st, 1, -1 do
                                local e = st[i]
                                if e.group == g.id then
                                    local holder = EntryHolderGroup(e)
                                    if holder then
                                        e.group = holder.id
                                    else
                                        table.remove(st, i)
                                    end
                                end
                            end
                            -- Ex-members now in NO group also lose their values on SURVIVING
                            -- entries (other groups' / shared slots): session exits bank into
                            -- every non-conflicting entry, and without this sweep the deleted
                            -- group's values keep applying to its ex-members forever with no
                            -- card or list row showing why. LEGACY entries (group == nil) are
                            -- exempt: user data this group never owned.
                            for _, sid in ipairs(g.specs or {}) do
                                if not SpecInAnyGroup(sid) then
                                    for _, e in ipairs(st) do
                                        if e.values and e.group ~= nil then e.values[sid] = nil end
                                    end
                                end
                            end
                        end
                        -- The group's custom unlock mode goes with it; if it
                        -- was live, the baseline layout is applied back.
                        if EllesmereUI.SpecOverrides_RemoveUnlockLayout then
                            EllesmereUI.SpecOverrides_RemoveUnlockLayout(g.id)
                        end
                        -- Same for its custom Buff Manager: otherwise the fork stays
                        -- orphaned AND live, with the BM page and preview showing it
                        -- until a reload's establish heals the dangling pointer.
                        if EllesmereUI.SpecOverrides_RemoveBmLayout then
                            EllesmereUI.SpecOverrides_RemoveBmLayout(g.id)
                        end
                        if EllesmereUI.SpecOverrides_RemoveDmLayout then
                            EllesmereUI.SpecOverrides_RemoveDmLayout(g.id)
                        end
                        RebuildFKeyIndex()
                        RequestGoldWalk()
                        UpdateIndicator()   -- current spec may have been a member
                        RefreshCardsPopup()
                        if EllesmereUI.GetActivePage and EllesmereUI:GetActivePage() == LIST_PAGE then
                            EllesmereUI:RefreshPage(true)
                        end
                    end,
                })
            end,
        }))
    end

    -- Add new group
    add(BuildCardRow(p, y, {
        name = L("+ Add New Spec Group"),
        dim = true,
        iconApply = function(tex)
            tex:SetTexture(GLYPH_SPRITE)
            tex:SetTexCoord(0, 0.125, 0, 0.125)
            tex:SetDesaturated(true)
            tex:SetVertexColor(1, 1, 1, 0.25)
        end,
        onClick = function()
            p:Hide()
            StartGroupCreation()
        end,
    }))

    -- ---- Conditional Overrides section (one popup, two systems) ----
    -- Centered, matching the "Spec Overrides" title at the top of the popup.
    do
        local hdr = CreateFrame("Frame", nil, p)
        hdr:SetSize(p:GetWidth() - 20, 26)
        hdr:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y - 6)
        local hl = EllesmereUI.MakeFont(hdr, 13, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        hl:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 4)
        hl:SetText(L("Conditional Overrides"))
        local sub = EllesmereUI.MakeFont(hdr, 12, nil, 0.55, 0.55, 0.55, 1)
        sub:SetPoint("TOP", hl, "BOTTOM", 0, -2)
        sub:SetText(L("(Spec prio'd for settings conflicts)"))
        p._rows[#p._rows + 1] = hdr
        y = y - 52
    end

    for _, g in ipairs(EllesmereUI.Conditions_GetGroups and EllesmereUI.Conditions_GetGroups() or {}) do
        add(BuildCardRow(p, y, {
            -- Border = editing selection only (never the runtime-applied
            -- state); the keybind toggle state gets a text badge.
            name = (g.name or "?")
                .. (g.conds and g.conds.keybind and g.keyOn and ("  |cffc7a65a" .. L("On") .. "|r") or ""),
            active = Cond._edit == g,
            locked = (bmLockKind and not (bmLockKind == "cond" and bmLockGid == g.id)) or nil,
            iconApply = function(tex) ApplyGroupIcon(tex, g.icon) end,
            tooltip = Cond.GroupTooltip(g),
            deletable = true,
            -- Dark Mode groups are values-only: no custom unlock mode can exist
            -- for them, so the button is not built.
            unlockEnabled = not (g.conds and g.conds.darkmode),
            onUnlock = (not (g.conds and g.conds.darkmode)) and function()
                p:Hide()
                EllesmereUI.Conditions_EnterUnlockForGroup(g)
            end or nil,
            onEdit = function()
                p:Hide()
                Cond.ShowPickerPopup(g)
            end,
            onClick = function()
                -- Click = editing-as toggle, exactly like spec group cards.
                if Cond._edit == g then
                    Cond.ExitEdit()
                else
                    Cond.EnterEdit(g)
                end
                RefreshCardsPopup()
            end,
            onDelete = function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Conditional Group"),
                    message = string.format(L("Delete the conditional '%s'? Its captured overrides and custom unlock mode are removed with it."), g.name or "?"),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if Cond._edit == g then Cond.ExitEdit() end
                        local groups = EllesmereUI.Conditions_GetGroups()
                        if groups then
                            for i, gg in ipairs(groups) do
                                if gg == g then table.remove(groups, i); break end
                            end
                        end
                        local st = Cond.GetStore()
                        if st then
                            -- Put each entry's recorded default back on the live profile
                            -- BEFORE dropping it: while this conditional is applied its
                            -- values ARE the live values (the Default view swap covers the
                            -- spec store only), and a removed entry with no writer left would
                            -- silently leave its values as the profile's settings.
                            -- Value-equal no-op when the group was not applied.
                            local touched = {}
                            for i = #st, 1, -1 do
                                if st[i].group == g.id then
                                    Cond.RestoreEntryDefaults(st[i], touched)
                                    table.remove(st, i)
                                end
                            end
                            if next(touched) then RunRefreshers(touched) end
                        end
                        Cond.RebuildIndex()
                        if EllesmereUI.Conditions_RemoveUnlockLayout then
                            EllesmereUI.Conditions_RemoveUnlockLayout(g.id)
                        end
                        -- The group's custom Buff Manager goes with it; if it was live
                        -- (or session-applied) the runtime layer is applied back, else
                        -- the fork stays orphaned AND live until a reload.
                        if EllesmereUI.Conditions_RemoveBmLayout then
                            EllesmereUI.Conditions_RemoveBmLayout(g.id)
                        end
                        if EllesmereUI.Conditions_RemoveDmLayout then
                            EllesmereUI.Conditions_RemoveDmLayout(g.id)
                        end
                        if EllesmereUI.Conditions_RebuildKeyBindings then EllesmereUI.Conditions_RebuildKeyBindings() end
                        if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
                        RequestGoldWalk()
                        RefreshCardsPopup()
                        -- FORCED rebuild on EVERY page, not just the management tabs: deleting
                        -- an APPLIED conditional changes live values (default restore above
                        -- plus the transition's writes for surviving entries), so open widgets
                        -- would show the deleted override's values until they re-read. Forced
                        -- because restored values can change page STRUCTURE too.
                        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
                    end,
                })
            end,
        }))
    end

    add(BuildCardRow(p, y, {
        name = L("+ Add New Conditional Group"),
        dim = true,
        iconApply = function(tex)
            tex:SetTexture(Cond.ICON_DIR .. Cond.ICONS.dungeon)
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetDesaturated(true)
            tex:SetVertexColor(1, 1, 1, 0.25)
        end,
        onClick = function()
            p:Hide()
            Cond.ShowPickerPopup(nil)
        end,
    }))

    -- Link to the management list (one link for both systems).
    local link = CreateFrame("Button", nil, p)
    link:SetSize(p:GetWidth() - 20, 22)
    link:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y - 2)
    local ll = EllesmereUI.MakeFont(link, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    ll:SetPoint("CENTER")
    ll:SetText(L("View All / Remove Overrides"))
    link:SetScript("OnEnter", function() ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end)
    link:SetScript("OnLeave", function() ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end)
    link:SetScript("OnClick", function()
        p:Hide()
        -- Profiles & Presets is session-locked (excluded module): leave any
        -- editing session first or the navigation is refused.
        if EllesmereUI.SpecOverrides_CloseEditSessions then
            EllesmereUI.SpecOverrides_CloseEditSessions()
        end
        EllesmereUI:SelectModule(PROFILES_MODULE)
        if EllesmereUI.SelectPage then EllesmereUI:SelectPage(LIST_PAGE) end
    end)
    p._rows[#p._rows + 1] = link
    y = y - 26

    p:SetHeight(-y + 12)
end

function EllesmereUI.SpecOverrides_ToggleCardsPopup(anchorBtn)
    if cardsPopup and cardsPopup:IsShown() then
        cardsPopup:Hide()
        return
    end
    if not cardsPopup then
        local p = CreateFrame("Frame", nil, _G.EllesmereUIFrame or UIParent)
        p:Hide()   -- born hidden so the first Show() fires OnShow (click-off arming)
        p:SetSize(280, 100)
        p:SetFrameStrata("DIALOG")
        p:SetFrameLevel(210)
        p:EnableMouse(true)
        p:SetClampedToScreen(true)
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.07, 0.99)
        EllesmereUI.MakeBorder(p, 1, 1, 1, 0.15)
        local title = EllesmereUI.MakeFont(p, 13, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        title:SetPoint("TOP", p, "TOP", 0, -12)
        title:SetText(L("Spec Overrides"))

        -- Click-anywhere-to-close, same pattern as the dropdown widgets: a
        -- global mouse-down listener (non-blocking, world clicks pass through).
        -- Clicks on the spec button / indicator are excluded so their own
        -- OnClick handles the toggle instead of close-then-reopen.
        local clickOff = CreateFrame("Frame")
        clickOff:Hide()
        clickOff:SetScript("OnEvent", function()
            -- A modal dialog (delete confirm / spec picker) owns clicks while
            -- shown; interacting with it must not close the popup.
            local confirmDim = _G.EUIConfirmDimmer
            if confirmDim and confirmDim:IsShown() then return end
            local assignDim = _G.EUISpecAssignDimmer
            if assignDim and assignDim:IsShown() then return end
            if p:IsShown() and not p:IsMouseOver()
               and not (specBtn and specBtn:IsMouseOver())
               and not (Cond._btn and Cond._btn:IsMouseOver())
               and not (indicatorBtn and indicatorBtn:IsShown() and indicatorBtn:IsMouseOver()) then
                p:Hide()
            end
        end)
        p:HookScript("OnShow", function()
            -- Defer registration one frame so the mouse-down that opened the
            -- popup does not immediately close it.
            C_Timer.After(0, function()
                if p:IsShown() then
                    clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN")
                    clickOff:Show()
                end
            end)
        end)
        p:HookScript("OnHide", function()
            clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            clickOff:Hide()
        end)

        cardsPopup = p
        EllesmereUI._specOvCardsPopup = p
    end
    cardsPopup:ClearAllPoints()
    if anchorBtn then
        cardsPopup:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 4, -8)
    else
        cardsPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    cardsPopup:Show()
    RefreshCardsPopup()
    EnsurePanelHideHook()
end

-------------------------------------------------------------------------------
--  CONDITIONAL OVERRIDES UI: toolbar button, cards popup, condition picker
--  (with keybind capture), name/icon popup. Mirrors the spec-overrides UI
--  one-for-one; the group icon picker reuses the class/role set.
-------------------------------------------------------------------------------

function Cond.CondLabel(id)
    for _, def in ipairs(EllesmereUI.CONDITIONS or {}) do
        if def.id == id then return L(def.label) end
    end
    return id
end

function Cond.GroupTooltip(g)
    local parts = {}
    for _, def in ipairs(EllesmereUI.CONDITIONS or {}) do
        if g.conds and g.conds[def.id] then
            local line = L(def.label)
            if def.id == "keybind" then
                line = line .. ": " .. (g.key and (GetBindingText and GetBindingText(g.key) or g.key) or L("no key set"))
            end
            parts[#parts + 1] = line
        end
    end
    return table.concat(parts, "\n")
end

-- ---- name + icon popup (cond variant; icon grid reuses role/class art) ------
function Cond.ShowNameIconPopup(conds, keyStr, existing)
    local p = Cond._namePopup
    if not p then
        p = CreateFrame("Frame", nil, UIParent)
        p:SetSize(380, 300)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetFrameLevel(220)
        p:EnableMouse(true)
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
        EllesmereUI.MakeBorder(p, 1, 1, 1, 0.15)

        local title = EllesmereUI.MakeFont(p, 14, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        title:SetPoint("TOP", p, "TOP", 0, -14)
        p._title = title

        local nameLbl = EllesmereUI.MakeFont(p, 12, nil, 1, 1, 1, 0.6)
        nameLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -44)
        nameLbl:SetText(L("Name"))

        local nameBox = CreateFrame("EditBox", nil, p)
        nameBox:SetSize(340, 26)
        nameBox:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -62)
        nameBox:SetAutoFocus(false)
        nameBox:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
        nameBox:SetTextColor(1, 1, 1, 1)
        nameBox:SetTextInsets(8, 8, 0, 0)
        nameBox:SetMaxLetters(24)
        EllesmereUI.SolidTex(nameBox, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        EllesmereUI.MakeBorder(nameBox, 1, 1, 1, 0.12)
        nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        p._nameBox = nameBox

        local iconLbl = EllesmereUI.MakeFont(p, 12, nil, 1, 1, 1, 0.6)
        iconLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -102)
        iconLbl:SetText(L("Icon"))

        -- Conditional icon set (one per condition), in ladder/display order.
        p._iconBtns = {}
        local defs = {}
        for _, cdef in ipairs(EllesmereUI.CONDITIONS or {}) do
            if Cond.ICONS[cdef.id] then
                defs[#defs + 1] = { kind = "cond", key = cdef.id }
            end
        end
        local PER_ROW, SZ, GAP = 8, 34, 8
        for i, def in ipairs(defs) do
            local col = (i - 1) % PER_ROW
            local rowI = math.floor((i - 1) / PER_ROW)
            local b = CreateFrame("Button", nil, p)
            b:SetSize(SZ, SZ)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", 20 + col * (SZ + GAP), -122 - rowI * (SZ + GAP))
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            ApplyGroupIcon(t, def)
            local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.10)
            b._def = def
            b._brd = brd
            b:SetScript("OnClick", function(self)
                p._selectedIcon = self._def
                for _, ob in ipairs(p._iconBtns) do
                    if ob._brd and ob._brd.SetColor then
                        ob._brd:SetColor(1, 1, 1, ob == self and 0 or 0.10)
                    end
                    if ob._brd and ob._brd.SetColor and ob == self then
                        ob._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                    end
                    ob:SetAlpha(ob == self and 1 or 0.7)
                end
            end)
            b:SetAlpha(0.7)
            p._iconBtns[#p._iconBtns + 1] = b
        end

        local create = CreateFrame("Button", nil, p)
        create:SetSize(110, 28)
        -- +44 centers the action+cancel pair (110 + 8 gap + 80 = 198 wide).
        create:SetPoint("BOTTOM", p, "BOTTOM", 44, 14)
        EllesmereUI.SolidTex(create, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local cbrd = EllesmereUI.MakeBorder(create, ACCENT_R, ACCENT_G, ACCENT_B, 0.5)
        local clbl = EllesmereUI.MakeFont(create, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        clbl:SetPoint("CENTER")
        p._createLbl = clbl
        create:SetScript("OnEnter", function() if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end end)
        create:SetScript("OnLeave", function() if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5) end end)
        create:SetScript("OnClick", function()
            local conds2 = p._conds
            if not conds2 or not next(conds2) then p:Hide(); return end
            local name = p._nameBox:GetText()
            local newGroup
            if p._existing then
                local g = p._existing
                if name and name ~= "" then g.name = name end
                if p._selectedIcon then g.icon = p._selectedIcon end
                g.conds = conds2
                g.key = conds2.keybind and p._key or nil
                if not conds2.keybind then g.keyOn = nil end
            else
                local groups = EllesmereUI.Conditions_GetGroups(true)
                if not groups then p:Hide(); return end
                local id = EllesmereUI.Conditions_NewGroupId()
                if not name or name == "" then name = L("Conditional") .. " " .. id end
                -- Default icon: the first checked condition (ladder order).
                local defIcon = p._selectedIcon
                if not defIcon then
                    for _, cdef in ipairs(EllesmereUI.CONDITIONS or {}) do
                        if conds2[cdef.id] and Cond.ICONS[cdef.id] then
                            defIcon = { kind = "cond", key = cdef.id }
                            break
                        end
                    end
                end
                newGroup = {
                    id = id, name = name,
                    icon = defIcon or { kind = "cond", key = "dungeon" },
                    conds = conds2,
                    key = conds2.keybind and p._key or nil,
                }
                groups[#groups + 1] = newGroup
            end
            p:Hide()
            if EllesmereUI.Conditions_RebuildKeyBindings then EllesmereUI.Conditions_RebuildKeyBindings() end
            if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
            -- Auto-activate: a new conditional goes straight into its edit
            -- session (matches the spec-group create flow). Cond.EnterEdit
            -- self-guards the BM page lock and any active session.
            if newGroup then Cond.EnterEdit(newGroup) end
            Cond.UpdateButton()
            Cond.RefreshCards()
            if EllesmereUI.GetActivePage and EllesmereUI:GetActivePage() == LIST_PAGE then
                EllesmereUI:RefreshPage(true)
            end
        end)

        local cancel = CreateFrame("Button", nil, p)
        cancel:SetSize(80, 28)
        cancel:SetPoint("RIGHT", create, "LEFT", -8, 0)
        EllesmereUI.SolidTex(cancel, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local xbrd = EllesmereUI.MakeBorder(cancel, 1, 1, 1, 0.22)
        local xlbl = EllesmereUI.MakeFont(cancel, 12, nil, 1, 1, 1, 0.7)
        xlbl:SetPoint("CENTER")
        xlbl:SetText(L("Cancel"))
        cancel:SetScript("OnEnter", function() if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.4) end end)
        cancel:SetScript("OnLeave", function() if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.22) end end)
        cancel:SetScript("OnClick", function() p:Hide() end)

        Cond._namePopup = p
    end
    p._conds = conds
    p._key = keyStr
    p._existing = existing
    p._title:SetText(existing and L("Edit Conditional Group") or L("New Conditional Group"))
    p._createLbl:SetText(existing and L("Save") or L("Create Group"))
    p._nameBox:SetText(existing and (existing.name or "") or "")
    -- Pre-select the group's saved icon, else the icon matching its first
    -- checked condition (ladder order).
    local want
    if existing and existing.icon then
        want = existing.icon
    else
        for _, cdef in ipairs(EllesmereUI.CONDITIONS or {}) do
            if conds and conds[cdef.id] and Cond.ICONS[cdef.id] then
                want = { kind = "cond", key = cdef.id }
                break
            end
        end
    end
    p._selectedIcon = nil
    for _, ob in ipairs(p._iconBtns) do
        local sel = want and ob._def
            and want.kind == ob._def.kind and want.key == ob._def.key
        ob:SetAlpha(sel and 1 or 0.7)
        if ob._brd and ob._brd.SetColor then
            if sel then
                ob._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                p._selectedIcon = ob._def
            else
                ob._brd:SetColor(1, 1, 1, 0.10)
            end
        end
    end
    p:Show()
end

-- ---- condition picker popup (checklist + keybind capture) -------------------
function Cond.ShowPickerPopup(existing)
    local p = Cond._pickerPopup
    if not p then
        p = CreateFrame("Frame", nil, UIParent)
        p:SetSize(340, 100)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetFrameLevel(220)
        p:EnableMouse(true)
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
        EllesmereUI.MakeBorder(p, 1, 1, 1, 0.15)

        local title = EllesmereUI.MakeFont(p, 14, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        title:SetPoint("TOP", p, "TOP", 0, -14)
        p._title = title
        local sub = EllesmereUI.MakeFont(p, 11, nil, 1, 1, 1, 0.5)
        sub:SetPoint("TOP", p, "TOP", 0, -32)
        sub:SetText(L("Select the conditions that activate this group:"))

        p._rows = {}
        local y = -52
        for _, def in ipairs(EllesmereUI.CONDITIONS) do
            local row = CreateFrame("Button", nil, p)
            row:SetSize(300, 24)
            row:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y)
            local box = row:CreateTexture(nil, "ARTWORK")
            box:SetSize(14, 14)
            box:SetPoint("LEFT", row, "LEFT", 0, 0)
            box:SetColorTexture(0.10, 0.10, 0.11, 0.9)
            local check = row:CreateTexture(nil, "OVERLAY")
            check:SetSize(8, 8)
            check:SetPoint("CENTER", box, "CENTER", 0, 0)
            check:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            check:Hide()
            local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1, def.comingSoon and 0.35 or 0.85)
            lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
            lbl:SetText(L(def.label) .. (def.comingSoon and ("  |cff888888" .. L("Coming Soon") .. "|r") or ""))
            row._check = check
            row._condID = def.id
            if def.comingSoon then
                row:SetScript("OnEnter", function(self)
                    if EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, L("This condition is coming in a future update."))
                    end
                end)
                row:SetScript("OnLeave", function()
                    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                end)
            elseif def.requires then
                -- Requirement-gated condition (e.g. Dark Mode needs the master toggle
                -- ON). CHECKING is refused while unmet; UNchecking always works so an
                -- existing group can never be trapped by a requirement that later went
                -- false. Dim state is per-open (rows build once, the popup is reused).
                row._reqFn = def.requires
                row._lbl = lbl
                row:SetScript("OnClick", function(self)
                    if not p._staged[self._condID] and not self._reqFn() then return end
                    p._staged[self._condID] = not p._staged[self._condID] or nil
                    self._check:SetShown(p._staged[self._condID] and true or false)
                    p._syncKeyRow()
                    if p._refreshReqRows then p._refreshReqRows() end
                end)
                row:SetScript("OnEnter", function(self)
                    if not p._staged[self._condID] and not self._reqFn()
                       and def.requiresHint and EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, L(def.requiresHint))
                    end
                end)
                row:SetScript("OnLeave", function()
                    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                end)
            else
                row:SetScript("OnClick", function(self)
                    p._staged[self._condID] = not p._staged[self._condID] or nil
                    self._check:SetShown(p._staged[self._condID] and true or false)
                    p._syncKeyRow()
                end)
            end
            p._rows[#p._rows + 1] = row
            y = y - 26
        end

        -- Re-evaluated per open and per click: requirement-gated rows dim while
        -- unmet; checked rows stay bright (uncheckable-only, never trapped).
        p._refreshReqRows = function()
            for _, r in ipairs(p._rows) do
                if r._reqFn and r._lbl then
                    local bright = r._reqFn() or p._staged[r._condID]
                    r._lbl:SetAlpha(bright and 1 or 0.4)
                end
            end
        end

        -- Keybind capture row (shown only while the keybind condition is
        -- checked): click, press a key, ESC cancels.
        local keyRow = CreateFrame("Frame", nil, p)
        keyRow:SetSize(300, 26)
        keyRow:SetPoint("TOPLEFT", p, "TOPLEFT", 20, y - 4)
        local keyLbl = EllesmereUI.MakeFont(keyRow, 12, nil, 1, 1, 1, 0.6)
        keyLbl:SetPoint("LEFT", keyRow, "LEFT", 0, 0)
        keyLbl:SetText(L("Toggle Key"))
        local keyBtn = CreateFrame("Button", nil, keyRow)
        keyBtn:SetSize(150, 22)
        keyBtn:SetPoint("LEFT", keyLbl, "RIGHT", 12, 0)
        EllesmereUI.SolidTex(keyBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local kbrd = EllesmereUI.MakeBorder(keyBtn, 1, 1, 1, 0.22)
        local kl = EllesmereUI.MakeFont(keyBtn, 11, nil, 1, 1, 1, 0.85)
        kl:SetPoint("CENTER")
        p._keyRow, p._keyLblFS = keyRow, kl
        local function ShowKeyText()
            if p._capturing then
                kl:SetText(L("Press a key..."))
            elseif p._stagedKey then
                kl:SetText(GetBindingText and GetBindingText(p._stagedKey) or p._stagedKey)
            else
                kl:SetText(L("Click to Set Key"))
            end
        end
        p._showKeyText = ShowKeyText
        keyBtn:SetScript("OnClick", function()
            p._capturing = not p._capturing
            p:EnableKeyboard(p._capturing and true or false)
            if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(not p._capturing) end
            ShowKeyText()
        end)
        p:SetScript("OnKeyDown", function(_, key)
            if not p._capturing then return end
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
               or key == "LALT" or key == "RALT" then
                return
            end
            p._capturing = false
            p:EnableKeyboard(false)
            if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(true) end
            if key ~= "ESCAPE" then
                local mods = ""
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                p._stagedKey = mods .. key
            end
            ShowKeyText()
        end)
        local keyClear = CreateFrame("Button", nil, keyRow)
        keyClear:SetSize(20, 20)
        keyClear:SetPoint("LEFT", keyBtn, "RIGHT", 6, 0)
        local kx = EllesmereUI.MakeFont(keyClear, 13, nil, 1, 1, 1, 0.6)
        kx:SetPoint("CENTER")
        kx:SetText("x")
        keyClear:SetScript("OnEnter", function() kx:SetTextColor(1, 0.4, 0.4, 1) end)
        keyClear:SetScript("OnLeave", function() kx:SetTextColor(1, 1, 1, 0.6) end)
        keyClear:SetScript("OnClick", function()
            p._stagedKey = nil
            ShowKeyText()
        end)

        p._syncKeyRow = function()
            keyRow:SetShown(p._staged.keybind and true or false)
            local extra = p._staged.keybind and 34 or 0
            p:SetHeight(-y + 56 + extra)
            ShowKeyText()
        end

        local nextBtn = CreateFrame("Button", nil, p)
        nextBtn:SetSize(110, 28)
        -- +44 centers the action+cancel pair (110 + 8 gap + 80 = 198 wide).
        nextBtn:SetPoint("BOTTOM", p, "BOTTOM", 44, 14)
        EllesmereUI.SolidTex(nextBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local nbrd = EllesmereUI.MakeBorder(nextBtn, ACCENT_R, ACCENT_G, ACCENT_B, 0.5)
        local nlbl = EllesmereUI.MakeFont(nextBtn, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        nlbl:SetPoint("CENTER")
        nlbl:SetText(L("Next"))
        nextBtn:SetScript("OnEnter", function() if nbrd and nbrd.SetColor then nbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end end)
        nextBtn:SetScript("OnLeave", function() if nbrd and nbrd.SetColor then nbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5) end end)
        nextBtn:SetScript("OnClick", function()
            if not next(p._staged) then return end
            if p._staged.keybind and not p._stagedKey then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(nextBtn, L("Set the toggle key first (or uncheck Keybind)."))
                end
                return
            end
            local conds = {}
            for k, v in pairs(p._staged) do conds[k] = v end
            p:Hide()
            Cond.ShowNameIconPopup(conds, p._stagedKey, p._editing)
        end)

        local cancel = CreateFrame("Button", nil, p)
        cancel:SetSize(80, 28)
        cancel:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
        EllesmereUI.SolidTex(cancel, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local xbrd2 = EllesmereUI.MakeBorder(cancel, 1, 1, 1, 0.22)
        local xlbl2 = EllesmereUI.MakeFont(cancel, 12, nil, 1, 1, 1, 0.7)
        xlbl2:SetPoint("CENTER")
        xlbl2:SetText(L("Cancel"))
        cancel:SetScript("OnEnter", function() if xbrd2 and xbrd2.SetColor then xbrd2:SetColor(1, 1, 1, 0.4) end end)
        cancel:SetScript("OnLeave", function() if xbrd2 and xbrd2.SetColor then xbrd2:SetColor(1, 1, 1, 0.22) end end)
        cancel:SetScript("OnClick", function()
            p._capturing = false
            p:EnableKeyboard(false)
            if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(true) end
            p:Hide()
        end)

        Cond._pickerPopup = p
    end
    p._editing = existing
    p._staged = {}
    p._stagedKey = existing and existing.key or nil
    p._capturing = false
    if existing and existing.conds then
        for k, v in pairs(existing.conds) do p._staged[k] = v end
    end
    for _, row in ipairs(p._rows) do
        row._check:SetShown(p._staged[row._condID] and true or false)
    end
    if p._refreshReqRows then p._refreshReqRows() end
    p._title:SetText(existing and string.format(L("Edit Conditional: %s"), existing.name or "?")
        or L("New Conditional Group"))
    p._syncKeyRow()
    p:Show()
end

-- ---- cards popup: UNIFIED with the spec overrides popup ----------------------
-- Conditional cards render as a second section inside RefreshCardsPopup; this alias
-- points every cond-side refresh at the one popup, and both toolbar buttons open it.
Cond.RefreshCards = function()
    if RefreshCardsPopup then RefreshCardsPopup() end
end

function EllesmereUI.Conditions_ToggleCardsPopup(anchorBtn)
    EllesmereUI.SpecOverrides_ToggleCardsPopup(anchorBtn)
end
-- ---- toolbar button ---------------------------------------------------------
-- One identity, always: no icon or tooltip morphing.
Cond.UpdateButton = function()
    local btn = Cond._btn
    if not btn or not btn._tex then return end
    btn._tex:SetTexCoord(0, 1, 0, 1)
    btn._tex:SetTexture(Cond.ICON_DIR .. Cond.ICONS.dungeon)
    btn._tex:SetDesaturated(false)
    btn._tex:SetVertexColor(1, 1, 1, 0.9)
end
EllesmereUI.Conditions_UpdateButton = Cond.UpdateButton

function EllesmereUI.Conditions_SetupButton(btn)
    Cond._btn = btn
    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    btn._tex = tex
    btn:SetAlpha(0.9)
    btn:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, L("Conditional Overrides: override settings by condition (dungeon, raid, keybind...)"))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.9)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    btn:SetScript("OnClick", function(self)
        EllesmereUI.Conditions_ToggleCardsPopup(self)
    end)
    Cond.UpdateButton()
end

-------------------------------------------------------------------------------
--  Management list page ("Spec Overrides" tab under Profiles & Presets).
--  Purely a list: per group, each captured setting with Go To / Remove.
-------------------------------------------------------------------------------
local function TitleCase(s)
    local out = s:gsub("(%a[%w']*)", function(w)
        return w:sub(1, 1):upper() .. w:sub(2):lower()
    end)
    return out
end

local function BuildListRow(parent, y, entry)
    local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

    local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
    name:SetPoint("LEFT", row, "LEFT", 20, 0)
    name:SetText(L(entry.label or "?"))

    local crumb = EllesmereUI.MakeFont(row, 11, nil, 1, 1, 1, 0.3)
    crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
    crumb:SetText(entry.crumb and TitleCase(entry.crumb) or "")

    local function MakeBtn(text, xOff, w)
        local b = CreateFrame("Button", nil, row)
        b:SetSize(w or 110, 22)
        b:SetPoint("RIGHT", row, "RIGHT", xOff, 0)
        EllesmereUI.SolidTex(b, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.22)
        local lbl = EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1, 0.8)
        lbl:SetPoint("CENTER")
        lbl:SetText(L(text))
        return b, brd
    end

    -- One row serves BOTH stores: entries created by an editing-as-conditional
    -- session live in the conditional store and remove from it.
    local isCondEntry
    do
        local cst = Cond.GetStore()
        if cst then
            for _, e in ipairs(cst) do
                if e == entry then isCondEntry = true; break end
            end
        end
    end
    local rm, rmBrd = MakeBtn("Remove Override", -20, 116)
    rm:SetScript("OnEnter", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 0.35, 0.35, 0.8) end end)
    rm:SetScript("OnLeave", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 1, 1, 0.22) end end)
    rm:SetScript("OnClick", function()
        EllesmereUI:ShowConfirmPopup({
            title = isCondEntry and L("Remove Conditional Override") or L("Remove Spec Override"),
            message = string.format(L("Remove '%s'? The setting keeps its current live value."), entry.label or "?"),
            confirmText = L("Remove"),
            cancelText = L("Cancel"),
            onConfirm = function()
                local st = isCondEntry and Cond.GetStore() or GetStore()
                if st then
                    for i, e in ipairs(st) do
                        if e == entry then table.remove(st, i); break end
                    end
                end
                if isCondEntry then Cond.RebuildIndex() else RebuildFKeyIndex() end
                RequestGoldWalk()
                EllesmereUI:RefreshPage(true)
            end,
        })
    end)

    local go, goBrd = MakeBtn("Go to Setting", -144, 104)
    go:SetScript("OnEnter", function() if goBrd and goBrd.SetColor then goBrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8) end end)
    go:SetScript("OnLeave", function() if goBrd and goBrd.SetColor then goBrd:SetColor(1, 1, 1, 0.22) end end)
    go:SetScript("OnClick", function()
        local mod = entry.module
        if not mod then
            for fkey in pairs(entry.values and entry.values.default or {}) do
                mod = SplitFKey(fkey)
                break
            end
        end
        if mod and EllesmereUI.GetModuleTitle and EllesmereUI:GetModuleTitle(mod) then
            EllesmereUI:SelectModule(mod)
            if entry.page and EllesmereUI.SelectPage then
                EllesmereUI:SelectPage(entry.page)
            end
        end
    end)

    return row, 38
end

-- Row for one STRANDED per-spec value (see SpecStrandedOnEntry): shows the spec
-- and the setting it silently overrides, with a per-value Remove returning the
-- spec to the shared default. Removal is the only possible action -- no editing
-- session can reach them.
local function BuildStrandedRow(parent, y, entry, specID)
    local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

    local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
    name:SetPoint("LEFT", row, "LEFT", 20, 0)
    name:SetText(SpecName(specID))

    local owner = GroupById(entry.group)
    local crumb = EllesmereUI.MakeFont(row, 11, nil, 1, 1, 1, 0.3)
    crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
    crumb:SetText(string.format("%s  -  %s", L(entry.label or "?"),
        string.format(L("held by '%s'"), (owner and owner.name) or "?")))

    local rm = CreateFrame("Button", nil, row)
    rm:SetSize(116, 22)
    rm:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    EllesmereUI.SolidTex(rm, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local rmBrd = EllesmereUI.MakeBorder(rm, 1, 1, 1, 0.22)
    local rmLbl = EllesmereUI.MakeFont(rm, 11, nil, 1, 1, 1, 0.8)
    rmLbl:SetPoint("CENTER")
    rmLbl:SetText(L("Remove Override"))
    rm:SetScript("OnEnter", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 0.35, 0.35, 0.8) end end)
    rm:SetScript("OnLeave", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 1, 1, 0.22) end end)
    rm:SetScript("OnClick", function()
        EllesmereUI:ShowConfirmPopup({
            title = L("Remove Stranded Override"),
            message = string.format(L("Remove the stranded '%s' override for %s? The spec returns to the shared default."),
                entry.label or "?", SpecName(specID)),
            confirmText = L("Remove"),
            cancelText = L("Cancel"),
            onConfirm = function()
                entry.values[specID] = nil
                if EllesmereUI.SpecOverrides_Apply then
                    EllesmereUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
                end
                RequestGoldWalk()
                EllesmereUI:RefreshPage(true)
            end,
        })
    end)

    return row, 38
end

-- Prunes entries whose owning group no longer exists. Entries with no group at
-- all (legacy captures) are kept.
local function PruneOrphanEntries()
    local store = GetStore()
    if not store then return false end
    local removed = false
    local touched
    -- Restore an entry's recorded defaults live before dropping it as an ORPHAN: the
    -- dead group's values may be the ones currently applied, and with the entry gone
    -- nothing would ever write the default back (residue becomes the permanent
    -- baseline). Loaded, non-blacklisted scalar paths only; excluded-context drops
    -- deliberately keep live as-is (those settings left the system).
    local function RestoreEntryDefaults(e)
        if not (e.values and e.values.default) then return end
        for fkey, def in pairs(e.values.default) do
            if not BlacklistedFKey(fkey) and FKeyLoaded(fkey) then
                local v = def
                if v == NIL_SENT then v = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues.
                local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
                local cur = ReadLive(fkey)
                if not nilPoison and type(v) ~= "table" and type(cur) ~= "table" and cur ~= v then
                    if WriteLive(fkey, v) then
                        local folder = SplitFKey(fkey)
                        if folder then
                            touched = touched or {}
                            touched[folder] = true
                        end
                    end
                end
            end
        end
    end
    for i = #store, 1, -1 do
        local e = store[i]
        local drop = false
        if e.group ~= nil and not GroupById(e.group) then
            -- Dangling creator id: retag to a surviving holder like the delete
            -- flow does; drop (with live restore) only when no group holds
            -- values on the entry.
            local holder = EntryHolderGroup(e)
            if holder then
                e.group = holder.id
                removed = true
            else
                RestoreEntryDefaults(e)
                drop = true
            end
        end
        -- Entries captured in contexts later excluded from the system (module-,
        -- page-, or section-scoped) drop wholesale so they stop applying and
        -- vanish from the management list.
        if not drop and e.module then
            local ex = EXCLUDED_CONTEXTS[e.module]
            if ex == true then
                drop = true
            elseif type(ex) == "table" and e.page then
                local pex = ex[e.page]
                if pex == true then
                    drop = true
                elseif type(pex) == "table" and e.section and pex[e.section] then
                    drop = true
                end
            end
        end
        -- Strip paths into blacklisted folders: legacy entries can carry
        -- Cooldown Manager paths, and applying those re-injects frozen per-spec
        -- spell data (cross-spec spells flashing on bars). An entry left with
        -- no paths is dropped entirely.
        if not drop and e.values and e.values.default then
            local stripped = false
            for fkey in pairs(e.values.default) do
                if BlacklistedFKey(fkey) then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then m[fkey] = nil end
                    end
                    stripped = true
                end
            end
            if stripped then
                removed = true
                if not next(e.values.default) then drop = true end
            end
        end
        if drop then
            table.remove(store, i)
            removed = true
        end
    end
    -- Self-heal: on group-created entries, per-spec value maps for specs in NO group
    -- are phantoms (leftovers from membership edits / group deletes). They silently
    -- pin the spec off the defaults and are invisible in the management list (buckets
    -- show creator + member deviations only). Legacy pre-group entries (group == nil)
    -- keep their per-spec values: that is their model.
    local healed = false
    for _, e in ipairs(store) do
        if e.group ~= nil and e.values then
            for k in pairs(e.values) do
                if type(k) == "number" and not SpecInAnyGroup(k) then
                    e.values[k] = nil
                    healed = true
                end
            end
        end
    end
    if healed then
        removed = true
        -- Put the healed specs' live data back on the shared defaults. DEFERRED one
        -- frame: this runs from PLAYER_LOGIN and from inside the list-page build,
        -- where a synchronous Apply fires module refreshers (and can re-enter a page
        -- rebuild) mid-build. Safe to defer: PruneRedundantValues' live-guard refuses
        -- to GC a recorded default while live still differs, so nothing is lost.
        C_Timer.After(0, function()
            if EllesmereUI.SpecOverrides_Apply then
                EllesmereUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
            end
        end)
    end
    if touched then RunRefreshers(touched) end
    if removed then
        RebuildFKeyIndex()
        RequestGoldWalk()
    end
    return removed
end

--- Generic fork-management row (name + gold crumb + Delete behind a confirm
--- popup). opts: crumb, title, message ('%s' = group name), removeFn. Defaults
--- describe the unlock-layout fork.
local function BuildUnlockLayoutRow(parent, y, g, opts)
    opts = opts or {}
    local crumbText = opts.crumb or "Custom Unlock Mode"
    local titleText = opts.title or "Delete Custom Unlock Mode"
    local msgText = opts.message
        or "Delete the custom unlock mode for '%s'? Its specs return to your default unlock mode layout."
    local removeFn = opts.removeFn or EllesmereUI.SpecOverrides_RemoveUnlockLayout

    local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

    local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
    name:SetPoint("LEFT", row, "LEFT", 20, 0)
    name:SetText(g.name or "?")

    local crumb = EllesmereUI.MakeFont(row, 11, nil, GOLD_R, GOLD_G, GOLD_B, 0.75)
    crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
    crumb:SetText(L(crumbText))

    local b = CreateFrame("Button", nil, row)
    b:SetSize(116, 22)
    b:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    EllesmereUI.SolidTex(b, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.22)
    local lbl = EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1, 0.8)
    lbl:SetPoint("CENTER")
    lbl:SetText(L("Delete"))
    b:SetScript("OnEnter", function() if brd and brd.SetColor then brd:SetColor(1, 0.35, 0.35, 0.8) end end)
    b:SetScript("OnLeave", function() if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end end)
    b:SetScript("OnClick", function()
        EllesmereUI:ShowConfirmPopup({
            title = L(titleText),
            message = string.format(L(msgText), g.name or "?"),
            confirmText = L("Delete"),
            cancelText = L("Cancel"),
            onConfirm = function()
                if removeFn then removeFn(g.id) end
                EllesmereUI:RefreshPage(true)
            end,
        })
    end)

    return row, 38
end

--- Row presets for the Buff Manager forks (spec + conditional variants).
local BM_ROW_SPEC = {
    crumb = "Custom Buff Manager",
    title = "Delete Custom Buff Manager",
    message = "Delete the custom Buff Manager for '%s'? Its specs return to your default Buff Manager.",
    removeFn = function(gid) EllesmereUI.SpecOverrides_RemoveBmLayout(gid) end,
}
local BM_ROW_COND = {
    crumb = "Custom Buff Manager",
    title = "Delete Custom Buff Manager",
    message = "Delete the custom Buff Manager for '%s'? Its conditions return to your default Buff Manager.",
    removeFn = function(gid) EllesmereUI.Conditions_RemoveBmLayout(gid) end,
}

--- Row presets for the Debuff Manager forks (spec + conditional variants).
local DM_ROW_SPEC = {
    crumb = "Custom Debuff Manager",
    title = "Delete Custom Debuff Manager",
    message = "Delete the custom Debuff Manager for '%s'? Its specs return to your default Debuff Manager.",
    removeFn = function(gid) EllesmereUI.SpecOverrides_RemoveDmLayout(gid) end,
}
local DM_ROW_COND = {
    crumb = "Custom Debuff Manager",
    title = "Delete Custom Debuff Manager",
    message = "Delete the custom Debuff Manager for '%s'? Its conditions return to your default Debuff Manager.",
    removeFn = function(gid) EllesmereUI.Conditions_RemoveDmLayout(gid) end,
}

-------------------------------------------------------------------------------
--  Promote Override to Profile (one-shot rescue)
--
--  Makes the selected spec group's stored state the profile's own: captured values
--  become the shared defaults, its unlock mode and Buff Manager forks (where
--  present) become the baseline layouts, then EVERY spec override group on the
--  profile is deleted. For profiles accidentally built entirely inside an override
--  group. Purely additive: only existing writers repaint live, and the end state is
--  indistinguishable from a profile that never had spec overrides. Conditional
--  overrides are untouched and ride the new baseline.
-------------------------------------------------------------------------------
local _promoteSelGid = nil   -- list-page dropdown selection (runtime only)

local function PromoteGroupToProfile(g)
    if not g or not g.specs or #g.specs == 0 then return end
    -- Combat re-check (the typed-confirm popup can sit open while combat starts): the
    -- tail must flush secure-frame repositioning synchronously before the reload, which
    -- lockdown blocks. Nothing is written yet, so refusing here is a clean abort.
    if InCombatLockdown() then
        EllesmereUI:ShowConfirmPopup({
            title = L("In Combat"),
            message = L("Promoting an override reloads the UI and cannot run in combat. Leave combat and try again."),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    -- Bank any open session and leave the Default view so the stores hold the
    -- freshest edits and live holds canonical spec values.
    if EllesmereUI.SpecOverrides_CloseEditSessions then
        EllesmereUI.SpecOverrides_CloseEditSessions()
    end

    -- 1) VALUES: the group's stored values become the recorded defaults.
    --    Resolution mirrors WriteGroupValues (first member spec's map, per-fkey
    --    fallback to the current default), so the promoted baseline is exactly
    --    what "editing as" the group shows.
    local store = GetStore()
    local seed = g.specs[1]
    if store then
        for _, entry in ipairs(store) do
            local def = entry.values and entry.values.default
            local m = entry.values and entry.values[seed]
            if def and m then
                for fkey in pairs(def) do
                    local v = m[fkey]
                    -- Blacklisted paths never apply; match-owned size keys belong to
                    -- the match engine (the layer promote below carries the real
                    -- geometry). NIL_SENT markers promote as-is: the default writer
                    -- decodes them behind its own nil-poison guard.
                    if v ~= nil and type(v) ~= "table"
                       and not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey) then
                        def[fkey] = v
                    end
                end
            end
        end
    end
    -- Write the promoted defaults live while the entries still exist (the store
    -- is wiped below and nothing could repaint them afterwards). Writes are
    -- value-equal no-ops for specs already on the group's values.
    WriteDefaultValues()

    -- 2) UNLOCK LAYOUT: the group's fork becomes the baseline, resolved as
    --    ApplyLayer resolves a live fork: links wholesale, position stores with
    --    per-key baseline gap-fill, grow keys under the authority rule, elems
    --    overlaid onto the baseline's. All copies -- the new baseline shares no
    --    tables with the wiped fork buckets.
    local s = GetUnlockStore()
    if s then
        local layer = s.layouts and s.layouts[g.id]
        local base = s.baselineLayout
        if layer then
            local nb = { anchors = {}, widthMatch = {}, heightMatch = {},
                         cdmGrow = {}, abGrow = {}, elems = {} }
            for k, v in pairs(layer.anchors or {}) do
                if not IsTBBChildKey(k) then nb.anchors[k] = DeepCopy(v) end
            end
            for k, v in pairs(layer.widthMatch or {}) do
                if not IsTBBChildKey(k) then nb.widthMatch[k] = v end
            end
            for k, v in pairs(layer.heightMatch or {}) do
                if not IsTBBChildKey(k) then nb.heightMatch[k] = v end
            end
            local function MergePos(lp, bp)
                local out = lp and DeepCopy(lp) or (bp and DeepCopy(bp) or nil)
                if lp and bp then
                    for k, v in pairs(bp) do
                        if out[k] == nil then out[k] = DeepCopy(v) end
                    end
                end
                return out
            end
            nb.cdmPos = MergePos(layer.cdmPos, base and base.cdmPos)
            nb.abPos = MergePos(layer.abPos, base and base.abPos)
            -- A grow store is authoritative only when its layer was harvested
            -- with the owning module loaded (pos store present); effective =
            -- layer's grow, else the baseline's.
            local function MergeGrow(out, lAuth, lg, bAuth, bg)
                if bAuth and bg then
                    for k, v in pairs(bg) do out[k] = v end
                end
                if lAuth and lg then
                    for k, v in pairs(lg) do out[k] = v end
                end
            end
            MergeGrow(nb.cdmGrow, layer.cdmPos ~= nil, layer.cdmGrow,
                      base and base.cdmPos ~= nil, base and base.cdmGrow)
            MergeGrow(nb.abGrow, layer.abPos ~= nil, layer.abGrow,
                      base and base.abPos ~= nil, base and base.abGrow)
            if base and base.elems then
                for k, e in pairs(base.elems) do
                    if not LayerSkipsKey(k) then nb.elems[k] = DeepCopy(e) end
                end
            end
            for k, e in pairs(layer.elems or {}) do
                if not LayerSkipsKey(k) then nb.elems[k] = DeepCopy(e) end
            end
            s.baselineLayout = nb
        end
        wipe(s.layouts)
        s.active = nil
    end

    -- 3) BUFF MANAGER: BM layers are complete wholesale subtrees; the fork
    --    (when present) becomes the baseline verbatim.
    local bs = GetBmStore()
    if bs then
        local bl = bs.layouts and bs.layouts[g.id]
        if bl then bs.baselineLayout = DeepCopy(bl) end
        wipe(bs.layouts)
        bs.active = nil
    end

    -- 3b) DEBUFF MANAGER: same wholesale promote as the BM store.
    local ds = GetDmStore()
    if ds then
        local dl = ds.layouts and ds.layouts[g.id]
        if dl then ds.baselineLayout = DeepCopy(dl) end
        wipe(ds.layouts)
        ds.active = nil
    end

    -- 4) DELETE the spec override system: every group and entry. The promoted
    --    values are already live and the promoted layouts are the baselines,
    --    so from here the profile simply IS the override.
    local groups = GetGroups()
    if groups then wipe(groups) end
    if store then wipe(store) end
    RebuildFKeyIndex()

    -- 5) CONVERGE live onto the new baselines, forced: with the groups gone the
    --    resolver wants the baseline (or a live conditional fork over it), and
    --    the same-layer early-out would skip the repaint for a spec that was
    --    NOT on the promoted fork. Where live already matches, writes are
    --    value-equal and the flush's equality guards no-op. pcall like the
    --    import converge: an error must not strand the cleanup half-done.
    local sid = CurrentSpecID()
    if sid then
        if EllesmereUI.SpecOverrides_ApplyUnlock then
            pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
        end
        if EllesmereUI.SpecOverrides_ApplyBm then
            pcall(EllesmereUI.SpecOverrides_ApplyBm, sid, true)
        end
        if EllesmereUI.SpecOverrides_ApplyDm then
            pcall(EllesmereUI.SpecOverrides_ApplyDm, sid, true)
        end
    end
    -- 6) RELOAD. The converge's element writes are DEFERRED (FlushUnlock) and
    --    reloading inside that window strands them: the logout bank keeps the
    --    intent in the bucket, but the post-reload login early-outs on the nil
    --    active pointer and never paints it back into module DBs. Flush
    --    synchronously first (out of combat by the gate above), then reload --
    --    every runtime cache, ticker and session structure rebuilds clean.
    if EllesmereUI.SpecOverrides_FlushUnlock then
        pcall(EllesmereUI.SpecOverrides_FlushUnlock)
    end
    ReloadUI()
end

--- Page builder for the "Spec Overrides" tab (called from the Profiles &
--- Presets module registration).
function EllesmereUI.SpecOverrides_BuildListPage(parent, startY)
    local W = EllesmereUI.Widgets
    local y = startY
    -- Skip during a hidden search pre-build: the page is only indexed for its
    -- static labels, and pruning mutates saved profile data -- not something a
    -- read-only indexing pass may do as a side effect.
    if not EllesmereUI._prebuilding then PruneOrphanEntries() end
    local store = GetStore()
    local groups = GetGroups() or {}
    local us = GetUnlockStore()
    local layoutGroups
    if us then
        for _, g in ipairs(groups) do
            if us.layouts[g.id] ~= nil then
                layoutGroups = layoutGroups or {}
                layoutGroups[#layoutGroups + 1] = g
            end
        end
    end
    local bs = GetBmStore()
    local bmGroups
    if bs then
        for _, g in ipairs(groups) do
            if bs.layouts[g.id] ~= nil then
                bmGroups = bmGroups or {}
                bmGroups[#bmGroups + 1] = g
            end
        end
    end
    local dds = GetDmStore()
    local dmGroups
    if dds then
        for _, g in ipairs(groups) do
            if dds.layouts[g.id] ~= nil then
                dmGroups = dmGroups or {}
                dmGroups[#dmGroups + 1] = g
            end
        end
    end

    if (not store or #store == 0) and not layoutGroups and not bmGroups and not dmGroups then
        local _, h = W:SectionHeader(parent, L("Spec Overrides"), y);  y = y - h
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = CreateFrame("Frame", nil, parent)
        hint:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 80)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
        local fs = EllesmereUI.MakeFont(hint, 13, nil, 1, 1, 1, 0.5)
        fs:SetPoint("TOPLEFT", hint, "TOPLEFT", 20, -10)
        fs:SetWidth(hint:GetWidth() - 40)
        fs:SetJustifyH("LEFT")
        fs:SetText(L("No spec overrides yet. Click the spec glyph next to the module search bar, select or create a spec group, and any setting you change while editing as that group is saved here."))
        y = y - 90
        return -y + 40
    end

    -- TOP section: custom unlock modes (one whole-layout fork per group).
    if layoutGroups then
        local _, hh = W:SectionHeader(parent, "Custom Unlock Modes", y);  y = y - hh
        for _, g in ipairs(layoutGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g)
            y = y - rh
        end
    end

    -- Custom Buff Manager forks (Raid Frames Buff Manager tab).
    if bmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Buff Managers", y);  y = y - hh
        for _, g in ipairs(bmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, BM_ROW_SPEC)
            y = y - rh
        end
    end

    -- Custom Debuff Manager forks (Raid Frames Debuff Manager tab).
    if dmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Debuff Managers", y);  y = y - hh
        for _, g in ipairs(dmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, DM_ROW_SPEC)
            y = y - rh
        end
    end

    -- Bucket entries under EVERY group that customizes them: a slot is ONE
    -- shared entry across groups (a second group's edits bank into the first
    -- group's entry), so an entry lists under its creating group AND under any
    -- group whose member specs store a value differing from the entry's shared
    -- default. Derived live -- no stored ownership metadata.
    local function GroupCustomizes(entry, g)
        if entry.group == g.id then return true end
        local def = entry.values and entry.values.default
        if not def then return false end
        for _, sid in ipairs(g.specs or {}) do
            local m = entry.values[sid]
            if m then
                for fkey, dv in pairs(def) do
                    if m[fkey] ~= nil and m[fkey] ~= dv then return true end
                end
            end
        end
        return false
    end
    local byGroup, ungrouped = {}, {}
    for _, entry in ipairs(store or {}) do
        local listed = false
        for _, g in ipairs(groups) do
            if GroupCustomizes(entry, g) then
                byGroup[g.id] = byGroup[g.id] or {}
                table.insert(byGroup[g.id], entry)
                listed = true
            end
        end
        if not listed then ungrouped[#ungrouped + 1] = entry end
    end

    for _, g in ipairs(groups) do
        local list = byGroup[g.id]
        if list and #list > 0 then
            local _, hh = W:SectionHeader(parent, g.name or "?", y);  y = y - hh
            for _, entry in ipairs(list) do
                local _, rh = BuildListRow(parent, y, entry)
                y = y - rh
            end
        end
    end
    if #ungrouped > 0 then
        local _, hh = W:SectionHeader(parent, "Ungrouped", y);  y = y - hh
        for _, entry in ipairs(ungrouped) do
            local _, rh = BuildListRow(parent, y, entry)
            y = y - rh
        end
    end

    -- STRANDED values: per-spec overrides no editing session can reach (see
    -- SpecStrandedOnEntry). They apply at every boundary but are invisible in
    -- the group buckets above, so each gets a row with a per-value Remove.
    local stranded
    for _, entry in ipairs(store or {}) do
        if entry.values then
            for k in pairs(entry.values) do
                if type(k) == "number" and SpecStrandedOnEntry(entry, k) then
                    stranded = stranded or {}
                    stranded[#stranded + 1] = { entry = entry, spec = k }
                end
            end
        end
    end
    if stranded then
        table.sort(stranded, function(a, b) return a.spec < b.spec end)
        local _, hh = W:SectionHeader(parent, "Stranded Overrides", y);  y = y - hh
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = EllesmereUI.MakeFont(parent, 11, nil, 1, 1, 1, 0.45)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD + 20, y)
        hint:SetWidth(parent:GetWidth() - CONTENT_PAD * 2 - 40)
        hint:SetJustifyH("LEFT")
        hint:SetText(L("These specs hold override values that no group's editing mode can reach anymore (left behind by membership changes). They still apply. Remove one to return that spec to the shared default."))
        y = y - 34
        for _, s in ipairs(stranded) do
            local _, rh = BuildStrandedRow(parent, y, s.entry, s.spec)
            y = y - rh
        end
    end

    -- DANGER ZONE: one-shot "this override IS my profile" rescue. Rendered only
    -- while a group exists to promote.
    if #groups > 0 then
        y = y - 14
        local _, hh = W:SectionHeader(parent, "Promote Override to Profile", y);  y = y - hh
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = EllesmereUI.MakeFont(parent, 11, nil, 1, 1, 1, 0.45)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD + 20, y)
        hint:SetWidth(parent:GetWidth() - CONTENT_PAD * 2 - 40)
        hint:SetJustifyH("LEFT")
        hint:SetText(L("Rescue tool for a profile built inside an override: the selected group's settings and layouts become this profile's own baseline, then ALL spec override groups are deleted. Conditional overrides are not affected."))
        y = y - 44
        local ddValues, ddOrder = {}, {}
        for _, gg in ipairs(groups) do
            ddValues[gg.id] = gg.name or ("Group " .. gg.id)
            ddOrder[#ddOrder + 1] = gg.id
        end
        if not _promoteSelGid or not GroupById(_promoteSelGid) then
            _promoteSelGid = groups[1].id
        end
        local _, dh = W:WideDropdown(parent, "Override to Promote", y, ddValues,
            function() return _promoteSelGid end,
            function(v) _promoteSelGid = v end,
            ddOrder, 300)
        y = y - dh
        y = y - 6
        local BTN_W, BTN_H = 300, 38
        local lerp = EllesmereUI.lerp
        local DARK_BG = EllesmereUI.DARK_BG or { r = 0.05, g = 0.07, b = 0.09 }
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", parent, "TOP", 0, y)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        btn:SetAlpha(0.85)
        local brd = EllesmereUI.MakeBorder(btn, 0.8, 0.2, 0.2, 0.5, EllesmereUI.PanelPP)
        local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bg:SetAllPoints()
        local lbl = EllesmereUI.MakeFont(btn, 13, nil, 0.9, 0.3, 0.3)
        lbl:SetAlpha(0.7)
        lbl:SetPoint("CENTER")
        lbl:SetText(L("Promote Override & Delete ALL Overrides"))
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                lbl:SetTextColor(lerp(0.9, 1, t), lerp(0.3, 0.35, t), lerp(0.3, 0.35, t), lerp(0.7, 1, t))
                brd:SetColor(0.8, 0.2, 0.2, lerp(0.5, 0.8, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        end
        btn:SetScript("OnClick", function()
            local pg = GroupById(_promoteSelGid)
            if not pg then return end
            -- The promote ends in a synchronous flush + ReloadUI, neither
            -- of which belongs in combat lockdown.
            if InCombatLockdown() then
                EllesmereUI:ShowConfirmPopup({
                    title = L("In Combat"),
                    message = L("Promoting an override reloads the UI and cannot run in combat. Leave combat and try again."),
                    confirmText = L("OK"),
                    hideCancel = true,
                })
                return
            end
            -- Modules with captured overrides must be loaded: promoted
            -- values for an unloaded module cannot be written live, and the
            -- store they lived in is deleted at the end -- silent loss.
            local missingSet, missingList
            for _, entry in ipairs(GetStore() or {}) do
                for fkey in pairs(entry.values and entry.values.default or {}) do
                    if not BlacklistedFKey(fkey) and not FKeyLoaded(fkey) then
                        local folder = SplitFKey(fkey)
                        if folder and not (missingSet and missingSet[folder]) then
                            missingSet = missingSet or {}
                            missingSet[folder] = true
                            missingList = missingList or {}
                            missingList[#missingList + 1] = folder:gsub("^EllesmereUI", "")
                        end
                    end
                end
            end
            if missingList then
                EllesmereUI:ShowConfirmPopup({
                    title = L("Enable Modules First"),
                    message = string.format(L("Captured overrides reference disabled modules (%s). Enable them and reload before promoting, or those settings would be lost."), table.concat(missingList, ", ")),
                    confirmText = L("OK"),
                    hideCancel = true,
                })
                return
            end
            EllesmereUI:ShowConfirmPopup({
                title = L("Promote Override to Profile"),
                message = string.format(L("This permanently overwrites this profile's settings with the override '%s': its captured settings and its custom Unlock Mode and Buff Manager layouts (where present) become the profile's own baseline for every spec. ALL spec override groups on this profile are then deleted and the UI reloads. Conditional overrides are not affected."), pg.name or "?"),
                disclaimer = L("This cannot be undone. Consider exporting this profile as a backup first."),
                typeToConfirm = "Confirm",
                confirmText = L("Promote & Reload"),
                cancelText = L("Cancel"),
                onConfirm = function() PromoteGroupToProfile(pg) end,
            })
        end)
        y = y - BTN_H - 10
    end

    return -y + 40
end

--- Page builder for the "Conditional Overrides" tab (mirror of the spec tab).
function EllesmereUI.Conditions_BuildListPage(parent, startY)
    local W = EllesmereUI.Widgets
    local y = startY
    Cond.PruneEntries()
    local store = Cond.GetStore()
    local groups = EllesmereUI.Conditions_GetGroups() or {}
    local cs = Cond.GetUnlockStore()

    local layoutGroups
    if cs then
        for _, g in ipairs(groups) do
            if cs.layouts[g.id] ~= nil then
                layoutGroups = layoutGroups or {}
                layoutGroups[#layoutGroups + 1] = g
            end
        end
    end
    local cbs = GetCondBmStore()
    local bmGroups
    if cbs then
        for _, g in ipairs(groups) do
            if cbs.layouts[g.id] ~= nil then
                bmGroups = bmGroups or {}
                bmGroups[#bmGroups + 1] = g
            end
        end
    end
    local cds = GetCondDmStore()
    local dmGroups
    if cds then
        for _, g in ipairs(groups) do
            if cds.layouts[g.id] ~= nil then
                dmGroups = dmGroups or {}
                dmGroups[#dmGroups + 1] = g
            end
        end
    end

    if (not store or #store == 0) and not layoutGroups and not bmGroups and not dmGroups and #groups == 0 then
        local _, h = W:SectionHeader(parent, L("Conditional Overrides"), y);  y = y - h
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = CreateFrame("Frame", nil, parent)
        hint:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 80)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
        local fs = EllesmereUI.MakeFont(hint, 13, nil, 1, 1, 1, 0.5)
        fs:SetPoint("TOPLEFT", hint, "TOPLEFT", 20, -10)
        fs:SetWidth(hint:GetWidth() - 40)
        fs:SetJustifyH("LEFT")
        fs:SetText(L("No conditional overrides yet. Click the Conditional Overrides button next to the module search bar and create a conditional group (Dungeon, Raid, Keybind...). Spec overrides always take precedence over conditionals."))
        y = y - 90
        return -y + 40
    end

    -- TOP section: custom unlock modes (one whole-layout fork per group).
    if layoutGroups then
        local _, hh = W:SectionHeader(parent, "Custom Unlock Modes", y);  y = y - hh
        for _, g in ipairs(layoutGroups) do
            local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
            local row = CreateFrame("Frame", nil, parent)
            row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
            local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
            name:SetPoint("LEFT", row, "LEFT", 20, 0)
            name:SetText(g.name or "?")
            local crumb = EllesmereUI.MakeFont(row, 11, nil, GOLD_R, GOLD_G, GOLD_B, 0.75)
            crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
            crumb:SetText(L("Custom Unlock Mode"))
            local b = CreateFrame("Button", nil, row)
            b:SetSize(116, 22)
            b:SetPoint("RIGHT", row, "RIGHT", -20, 0)
            EllesmereUI.SolidTex(b, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.22)
            local lbl = EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1, 0.8)
            lbl:SetPoint("CENTER")
            lbl:SetText(L("Delete"))
            b:SetScript("OnEnter", function() if brd and brd.SetColor then brd:SetColor(1, 0.35, 0.35, 0.8) end end)
            b:SetScript("OnLeave", function() if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end end)
            local gid = g.id
            local gname = g.name or "?"
            b:SetScript("OnClick", function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Custom Unlock Mode"),
                    message = string.format(
                        L("Delete the custom unlock mode for '%s'? Its conditions return to your default unlock mode layout."),
                        gname),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if EllesmereUI.Conditions_RemoveUnlockLayout then
                            EllesmereUI.Conditions_RemoveUnlockLayout(gid)
                        end
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end)
            y = y - 38
        end
    end

    -- Custom Buff Manager forks (Raid Frames Buff Manager tab).
    if bmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Buff Managers", y);  y = y - hh
        for _, g in ipairs(bmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, BM_ROW_COND)
            y = y - rh
        end
    end

    -- Custom Debuff Manager forks (Raid Frames Debuff Manager tab).
    if dmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Debuff Managers", y);  y = y - hh
        for _, g in ipairs(dmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, DM_ROW_COND)
            y = y - rh
        end
    end

    -- Captured value entries bucketed under EVERY conditional group that
    -- customizes them (creator, plus any group whose stored map differs from
    -- the entry's shared default -- same shared-slot rule as the spec list).
    for _, g in ipairs(groups) do
        local list = {}
        for _, entry in ipairs(store or {}) do
            local owns = entry.group == g.id
            if not owns and entry.values and entry.values.default then
                local m = entry.values[g.id]
                if m then
                    for fkey, dv in pairs(entry.values.default) do
                        if m[fkey] ~= nil and m[fkey] ~= dv then owns = true; break end
                    end
                end
            end
            if owns then list[#list + 1] = entry end
        end
        if #list > 0 then
            local _, hh = W:SectionHeader(parent, g.name or "?", y);  y = y - hh
            for _, entry in ipairs(list) do
                local _, rh = BuildListRow(parent, y, entry)
                y = y - rh
            end
        end
    end

    return -y + 40
end

-------------------------------------------------------------------------------
--  Hooks + events
-------------------------------------------------------------------------------
-- Golden borders + watcher seed-absorption on page changes. RefreshPage only
-- rebuilds rows when forced; the fast path neither seeds nor re-rows.
if EllesmereUI.SelectModule then
    hooksecurefunc(EllesmereUI, "SelectModule", OnPageRebuilt)
end
if EllesmereUI.SelectPage then
    hooksecurefunc(EllesmereUI, "SelectPage", OnPageRebuilt)
end
if EllesmereUI.RefreshPage then
    hooksecurefunc(EllesmereUI, "RefreshPage", function(_, force)
        if force then
            _watchResync = true
        end
        RequestGoldWalk()
    end)
end


local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_LOGOUT")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- De-alias repair for stores that banked live TABLE references, which aliased
        -- the store to the live profile (any later live edit silently mutated the
        -- stored "override"). DeepCopy every table-typed value once so stores own their
        -- data. Harvests skip table values, so it cannot recur.
        local function DeAlias(store)
            for _, e in ipairs(store or {}) do
                if e.values then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then
                            for fkey, v in pairs(m) do
                                if type(v) == "table" then m[fkey] = DeepCopy(v) end
                            end
                        end
                    end
                end
            end
        end
        DeAlias(GetStore())
        if EllesmereUI._CondOv then DeAlias(EllesmereUI._CondOv.GetStore()) end
        -- One-time tidy: drop orphaned entries plus fkeys no group holds a value for.
        PruneOrphanEntries()
        PruneRedundantValues()
        if EllesmereUI._CondOv then
            EllesmereUI._CondOv.PruneEntries()
            EllesmereUI._CondOv.PruneRedundant()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Keep the current spec's stored values in sync with live edits so a
        -- shared profile opened on another character applies fresh data. Also
        -- banks + restores an active Editing-as session.
        EllesmereUI.SpecOverrides_HarvestCurrent()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if _combatFolders then
            local fl = _combatFolders
            _combatFolders = nil
            RunRefreshers(fl)
        end
    end
end)


