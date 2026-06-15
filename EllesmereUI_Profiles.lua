-------------------------------------------------------------------------------
--  EllesmereUI_Profiles.lua
--
--  Global profile system: import/export, presets, spec assignment.
--  Handles serialization (LibDeflate + custom serializer) and profile
--  management across all EllesmereUI addons.
--
--  Load order (via TOC):
--    1. Libs/LibDeflate.lua
--    2. EllesmereUI_Lite.lua
--    3. EllesmereUI.lua
--    4. EllesmereUI_Widgets.lua
--    5. EllesmereUI_Presets.lua
--    6. EllesmereUI_Profiles.lua  -- THIS FILE
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
--  LibDeflate reference (loaded before us via TOC)
--  LibDeflate registers via LibStub, not as a global, so use LibStub to get it.
-------------------------------------------------------------------------------
local LibDeflate = LibStub and LibStub("LibDeflate", true) or _G.LibDeflate

-------------------------------------------------------------------------------
--  Reload popup: uses Blizzard StaticPopup so the button click is a hardware
--  event and ReloadUI() is not blocked as a protected function call.
-------------------------------------------------------------------------------
StaticPopupDialogs["EUI_PROFILE_RELOAD"] = {
    text = "EllesmereUI Profile switched. Reload UI to apply?",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Addon registry: display-order list of all managed addons.
--  Each entry: { folder, display, svName }
--    folder  = addon folder name (matches _dbRegistry key)
--    display = human-readable name for the Profiles UI
--    svName  = SavedVariables name (e.g. "EllesmereUINameplatesDB")
--
--  All addons use _dbRegistry for profile access. Order matters for UI display.
-------------------------------------------------------------------------------
-- `suffix` is the rename-immune module id (the folder name minus the
-- "EllesmereUI" prefix). It NEVER contains the contiguous "EllesmereUI" token,
-- so the standalone packager's textual rename leaves it byte-identical in every
-- build. It is the anchor for the canonical export/import key (see below).
local ADDON_DB_MAP = {
    { folder = "EllesmereUIActionBars",        display = "Action Bars",         svName = "EllesmereUIActionBarsDB",        suffix = "ActionBars"        },
    { folder = "EllesmereUINameplates",        display = "Nameplates",          svName = "EllesmereUINameplatesDB",        suffix = "Nameplates"        },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",         svName = "EllesmereUIUnitFramesDB",        suffix = "UnitFrames"        },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",    svName = "EllesmereUICooldownManagerDB",   suffix = "CooldownManager"   },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",       svName = "EllesmereUIResourceBarsDB",      suffix = "ResourceBars"      },
    { folder = "EllesmereUIRaidFrames",       display = "Raid Frames",         svName = "EllesmereUIRaidFramesDB",        suffix = "RaidFrames"        },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders",  svName = "EllesmereUIAuraBuffRemindersDB", suffix = "AuraBuffReminders" },
    -- v6.6 split-out addons (were previously bundled under EllesmereUIBasics).
    -- The old Basics entry is intentionally removed -- it's a shim with no
    -- user-visible profile data and listing it produced a misleading
    -- "Not included: Basics" warning on every imported v6.6+ profile.
    { folder = "EllesmereUIQoL",               display = "Quality of Life",     svName = "EllesmereUIQoLDB",               suffix = "QoL"               },
    -- BlizzardSkin is excluded: it stores settings on the shared
    -- EllesmereUIDB root, not through NewDB, so it has no per-profile data.
    { folder = "EllesmereUIBags",              display = "Bags",                svName = "EllesmereUIBagsDB",              suffix = "Bags"              },
    { folder = "EllesmereUIFriends",           display = "Friends List",        svName = "EllesmereUIFriendsDB",           suffix = "Friends"           },
    { folder = "EllesmereUIMythicTimer",       display = "Mythic+ Timer",       svName = "EllesmereUIMythicTimerDB",       suffix = "MythicTimer"       },
    { folder = "EllesmereUIQuestTracker",      display = "Quest Tracker",       svName = "EllesmereUIQuestTrackerDB",      suffix = "QuestTracker"      },
    { folder = "EllesmereUIMinimap",           display = "Minimap",             svName = "EllesmereUIMinimapDB",           suffix = "Minimap"           },
    { folder = "EllesmereUIDamageMeters",     display = "Damage Meters",       svName = "EllesmereUIDamageMetersDB",      suffix = "DamageMeters"      },
    { folder = "EllesmereUIChat",             display = "Chat",                svName = "EllesmereUIChatDB",              suffix = "Chat"              },
}
EllesmereUI._ADDON_DB_MAP = ADDON_DB_MAP

-------------------------------------------------------------------------------
--  Canonical addon keys (suite <-> standalone profile-string interop)
--
--  Profile strings key each addon's data by the addon FOLDER NAME. In a
--  standalone build the packager textually renames "EllesmereUI" -> the build's
--  token, so the local folder/db key (e.g. "EUIStandaloneBags") diverges from
--  the suite's ("EllesmereUIBags") and cross-build imports never match.
--
--  Fix: every exported string uses a CANONICAL key = the suite folder name,
--  which both builds can reconstruct. The packager renames only the CONTIGUOUS
--  token "EllesmereUI", so writing the prefix split as "Ellesmere".."UI" leaves
--  no contiguous match -- it stays "EllesmereUI" at runtime in EVERY build. The
--  bare `suffix` is likewise never a rename target, so canon = prefix..suffix ==
--  the suite folder name everywhere. Live DBs keep their own (renamed) folder;
--  only the serialized string is normalized. In the suite canon == folder, so
--  every translation is content-identity (no behavior change, no SV migration).
-------------------------------------------------------------------------------
local EUI_CANON_PREFIX = "Ellesmere" .. "UI"  -- split literal: rename-immune
local FOLDER_TO_CANON = {}
local CANON_TO_FOLDER = {}
for _, entry in ipairs(ADDON_DB_MAP) do
    local canon = EUI_CANON_PREFIX .. (entry.suffix or "")
    entry.canon = canon
    FOLDER_TO_CANON[entry.folder] = canon
    CANON_TO_FOLDER[canon] = entry.folder
end

-- Re-key an addons table from this build's local db.folder keys to canonical
-- keys (used on export). Unknown keys pass through unchanged.
local function AddonsToCanon(addons)
    if type(addons) ~= "table" then return addons end
    local out = {}
    for k, v in pairs(addons) do
        out[FOLDER_TO_CANON[k] or k] = v
    end
    return out
end

-- Re-key an addons table from canonical keys to this build's local db.folder
-- keys (used on import). Unknown keys pass through unchanged.
local function CanonToLocal(addons)
    if type(addons) ~= "table" then return addons end
    local out = {}
    for k, v in pairs(addons) do
        out[CANON_TO_FOLDER[k] or k] = v
    end
    return out
end

-------------------------------------------------------------------------------
--  Unlock-element key -> owning module (LOCAL folder) resolver
--
--  The selective-layout export/import attributes each anchor / size-match
--  relationship (keyed by unlock-element key) to a module so layout can be
--  exported per-module. Authoritative source is a passed-in folder (elem.folder
--  stamped at registration, or a payload keyToFolder value); this static
--  prefix/bare-word resolver is the fallback that covers every key in use today
--  (verified) plus any future key the authoritative source misses.
--
--  Returns a LOCAL folder name: the literals below contain "EllesmereUI", which
--  the standalone packager renames to the build token, so on each build this
--  matches the local selectedAddons keyspace and the stamped elem.folder. (Only
--  the payload keyToFolder is canonicalized -- see ExportProfile.) nil = unknown.
-------------------------------------------------------------------------------
local KEY_PREFIX_FOLDER = {
    ["CDM_"]   = "EllesmereUICooldownManager",
    ["TBB_"]   = "EllesmereUICooldownManager",
    ["ERB_"]   = "EllesmereUIResourceBars",
    ["ECHAT_"] = "EllesmereUIChat",
    ["EBS_"]   = "EllesmereUIMinimap",
    ["EDR_"]   = "EllesmereUIBlizzardSkin",
    ["EMT_"]   = "EllesmereUIMythicTimer",
    ["EABR_"]  = "EllesmereUIAuraBuffReminders",
    ["RF_"]    = "EllesmereUIRaidFrames",
    ["ECL_"]   = "EllesmereUIQoL",
    ["EUI_"]   = "EllesmereUIQoL",
}
-- Bare-word (un-prefixed) keys, by owning module. These appear as anchor TARGETS
-- (e.g. a castbar anchored to "player", a bar anchored to "Bar4") even when the
-- child carries a stamped folder, so the resolver must know them.
local AB_BAREWORD = {
    MainBar=true, Bar2=true, Bar3=true, Bar4=true, Bar5=true, Bar6=true,
    Bar7=true, Bar8=true, StanceBar=true, PetBar=true, XPBar=true, RepBar=true,
    ExtraActionButton=true, EncounterBar=true, QueueStatus=true,
    MicroBar=true, BagBar=true,
}
local UF_BAREWORD = {
    player=true, target=true, focus=true, pet=true, targettarget=true,
    focustarget=true, boss=true, classPower=true,
    playerCastbar=true, targetCastbar=true, focusCastbar=true,
}
-- providedFolder (already a local folder: elem.folder, or a payload value that
-- has been CanonToLocal'd) wins; the static resolution is the fallback.
local function ResolveKeyToFolder(key, providedFolder)
    if providedFolder then return providedFolder end
    if type(key) ~= "string" then return nil end
    for prefix, folder in pairs(KEY_PREFIX_FOLDER) do
        if key:sub(1, #prefix) == prefix then return folder end
    end
    if AB_BAREWORD[key] then return "EllesmereUIActionBars" end
    if UF_BAREWORD[key] then return "EllesmereUIUnitFrames" end
    return nil
end
EllesmereUI.ResolveKeyToFolder = ResolveKeyToFolder

-- Set of folders that have NO import/export checkbox (not in ADDON_DB_MAP), so
-- their anchor/match edges are never exported -- the element keeps its own saved
-- absolute position on import (decision: always export them unanchored). Today
-- this is only EllesmereUIBlizzardSkin (the Dragon Riding cluster).
local NO_CHECKBOX_FOLDER = {}
do
    local has = {}
    for _, entry in ipairs(ADDON_DB_MAP) do has[entry.folder] = true end
    -- Any folder the resolver can return that isn't a checkbox module:
    for _, folder in pairs(KEY_PREFIX_FOLDER) do
        if not has[folder] then NO_CHECKBOX_FOLDER[folder] = true end
    end
end
EllesmereUI._NoCheckboxFolder = NO_CHECKBOX_FOLDER

-------------------------------------------------------------------------------
--  Serializer: Lua table <-> string (no AceSerializer dependency)
--  Handles: string, number, boolean, nil, table (nested), color tables
-------------------------------------------------------------------------------
local Serializer = {}

local function SerializeValue(v, parts)
    local t = type(v)
    if t == "string" then
        parts[#parts + 1] = "s"
        -- Length-prefixed to avoid delimiter issues
        parts[#parts + 1] = #v
        parts[#parts + 1] = ":"
        parts[#parts + 1] = v
    elseif t == "number" then
        parts[#parts + 1] = "n"
        parts[#parts + 1] = tostring(v)
        parts[#parts + 1] = ";"
    elseif t == "boolean" then
        parts[#parts + 1] = v and "T" or "F"
    elseif t == "nil" then
        parts[#parts + 1] = "N"
    elseif t == "table" then
        parts[#parts + 1] = "{"
        -- Serialize array part first (integer keys 1..n)
        local n = #v
        for i = 1, n do
            SerializeValue(v[i], parts)
        end
        -- Then hash part (non-integer keys, or integer keys > n)
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "number" and k >= 1 and k <= n and k == math.floor(k) then
                -- Already serialized in array part
            else
                parts[#parts + 1] = "K"
                SerializeValue(k, parts)
                SerializeValue(val, parts)
            end
        end
        parts[#parts + 1] = "}"
    end
end

function Serializer.Serialize(tbl)
    local parts = {}
    SerializeValue(tbl, parts)
    return table.concat(parts)
end

-- Deserializer
local function DeserializeValue(str, pos)
    local tag = str:sub(pos, pos)
    if tag == "s" then
        -- Find the colon after the length
        local colonPos = str:find(":", pos + 1, true)
        if not colonPos then return nil, pos end
        local len = tonumber(str:sub(pos + 1, colonPos - 1))
        if not len then return nil, pos end
        local val = str:sub(colonPos + 1, colonPos + len)
        return val, colonPos + len + 1
    elseif tag == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, pos end
        return tonumber(str:sub(pos + 1, semi - 1)), semi + 1
    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "N" then
        return nil, pos + 1
    elseif tag == "{" then
        local tbl = {}
        local idx = 1
        local p = pos + 1
        while p <= #str do
            local c = str:sub(p, p)
            if c == "}" then
                return tbl, p + 1
            elseif c == "K" then
                -- Key-value pair
                local key, val
                key, p = DeserializeValue(str, p + 1)
                val, p = DeserializeValue(str, p)
                if key ~= nil then
                    tbl[key] = val
                end
            else
                -- Array element
                local val
                val, p = DeserializeValue(str, p)
                tbl[idx] = val
                idx = idx + 1
            end
        end
        return tbl, p
    end
    return nil, pos + 1
end

function Serializer.Deserialize(str)
    if not str or #str == 0 then return nil end
    local val, _ = DeserializeValue(str, 1)
    return val
end

EllesmereUI._Serializer = Serializer

-------------------------------------------------------------------------------
--  Deep copy utility
-------------------------------------------------------------------------------
local function DeepCopy(src, seen)
    if type(src) ~= "table" then return src end
    if seen and seen[src] then return seen[src] end
    if not seen then seen = {} end
    local copy = {}
    seen[src] = copy
    for k, v in pairs(src) do
        -- Skip frame references and other userdata that can't be serialized
        if type(v) ~= "userdata" and type(v) ~= "function" then
            copy[k] = DeepCopy(v, seen)
        end
    end
    return copy
end

local function DeepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            DeepMerge(dst[k], v)
        else
            dst[k] = DeepCopy(v)
        end
    end
end

EllesmereUI._DeepCopy = DeepCopy

-------------------------------------------------------------------------------
--  Selective-layout core helpers (shared by export, import, and the
--  connectivity-aware checkbox UI). All operate on an unlockLayout table
--  { anchors, widthMatch, heightMatch, phantomBounds } and LOCAL folder keys.
-------------------------------------------------------------------------------

-- Build { [key] = localFolder } for every key referenced in an unlockLayout
-- (anchor children + targets, width/height-match children + values), using the
-- live registry's elem.folder first, then the static resolver. Also returns a
-- `stale` set of keys NOT in the live registry (deleted/other-spec bars) so the
-- caller can prune dead edges. Use at EXPORT time (needs the exporter registry).
function EllesmereUI.BuildLayoutKeyToFolder(ul)
    local reg = EllesmereUI._unlockRegisteredElements or {}
    local k2f, stale = {}, {}
    local function add(key)
        if type(key) ~= "string" or k2f[key] ~= nil then return end
        local elem = reg[key]
        local folder = ResolveKeyToFolder(key, elem and elem.folder)
        if folder then k2f[key] = folder end
        if not elem then stale[key] = true end
    end
    if type(ul) == "table" then
        if type(ul.anchors) == "table" then
            for child, info in pairs(ul.anchors) do
                add(child)
                if type(info) == "table" then add(info.target) end
            end
        end
        if type(ul.widthMatch) == "table" then
            for child, target in pairs(ul.widthMatch) do add(child); add(target) end
        end
        if type(ul.heightMatch) == "table" then
            for child, target in pairs(ul.heightMatch) do add(child); add(target) end
        end
    end
    return k2f, stale
end

-- Return a NEW unlockLayout keeping only entries whose BOTH endpoints resolve to
-- a folder in `folderSet` (set of LOCAL folders), with both endpoints live (not
-- stale), known, and NOT in a no-checkbox folder. This is the per-entry filter
-- that guarantees no retained relationship references an excluded module.
-- k2f/stale may be passed (e.g. import-side, built from payload meta) or omitted
-- (export-side, built from the live registry).
function EllesmereUI.FilterLayoutToFolders(ul, folderSet, k2f)
    if type(ul) ~= "table" then return ul end
    if not k2f then k2f = EllesmereUI.BuildLayoutKeyToFolder(ul) end
    -- Classification is by the static resolver (registry-independent) so this can
    -- never over-drop just because the unlock registry isn't fully populated yet.
    -- An edge survives only if BOTH endpoints classify to a folder in folderSet and
    -- neither is a no-checkbox module. (A dead/deleted-bar edge that happens to
    -- survive is harmless: its missing child frame just no-ops on apply.)
    local function endpointOK(key)
        if type(key) ~= "string" then return false end
        local f = k2f[key]
        if not f then return false end                     -- unclassifiable -> drop
        if NO_CHECKBOX_FOLDER[f] then return false end     -- never export no-checkbox edges
        return folderSet[f] == true                        -- both endpoints in S
    end
    local out = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {} }
    if type(ul.anchors) == "table" then
        for child, info in pairs(ul.anchors) do
            if type(info) == "table" and endpointOK(child) and endpointOK(info.target) then
                out.anchors[child] = DeepCopy(info)
            end
        end
    end
    if type(ul.widthMatch) == "table" then
        for child, target in pairs(ul.widthMatch) do
            if endpointOK(child) and endpointOK(target) then out.widthMatch[child] = target end
        end
    end
    if type(ul.heightMatch) == "table" then
        for child, target in pairs(ul.heightMatch) do
            if endpointOK(child) and endpointOK(target) then out.heightMatch[child] = target end
        end
    end
    return out
end

-- Union-find over modules: two folders share a component if any LIVE, non-no-
-- checkbox anchor/match edge connects them. Returns folderToMembers where
-- folderToMembers[folder] = { set of folders in folder's component }. A folder
-- with no cross-module edge is absent (treat as a singleton: just itself).
-- Drives the hard-couple checkbox auto-toggle. k2f/stale may be passed in.
function EllesmereUI.BuildModuleComponents(ul, k2f)
    if not k2f then k2f = EllesmereUI.BuildLayoutKeyToFolder(ul) end
    local parent = {}
    local function find(x)
        while parent[x] and parent[x] ~= x do x = parent[x] end
        return x
    end
    local function union(a, b)
        if not parent[a] then parent[a] = a end
        if not parent[b] then parent[b] = b end
        local ra, rb = find(a), find(b)
        if ra ~= rb then parent[ra] = rb end
    end
    local function edge(c, t)
        if type(c) ~= "string" or type(t) ~= "string" then return end
        local fc, ft = k2f[c], k2f[t]
        if not fc or not ft then return end
        if NO_CHECKBOX_FOLDER[fc] or NO_CHECKBOX_FOLDER[ft] then return end
        if fc ~= ft then union(fc, ft) end
    end
    if type(ul) == "table" then
        if type(ul.anchors) == "table" then
            for c, i in pairs(ul.anchors) do if type(i) == "table" then edge(c, i.target) end end
        end
        if type(ul.widthMatch) == "table" then for c, t in pairs(ul.widthMatch) do edge(c, t) end end
        if type(ul.heightMatch) == "table" then for c, t in pairs(ul.heightMatch) do edge(c, t) end end
    end
    local rootMembers = {}
    for f in pairs(parent) do
        local r = find(f)
        rootMembers[r] = rootMembers[r] or {}
        rootMembers[r][f] = true
    end
    local folderToMembers = {}
    for _, members in pairs(rootMembers) do
        for f in pairs(members) do folderToMembers[f] = members end
    end
    return folderToMembers
end

-- IMPORT side: build { [key] = CANON folder } for every key in an imported
-- unlockLayout. The payload's keyToFolder meta wins (already canonical); for any
-- key it lacks -- including ALL keys when importing an OLD string with no meta --
-- fall back to the static resolver (LOCAL) re-canonicalized via FOLDER_TO_CANON.
-- This is what keeps a meta-less string from classifying nothing and dropping the
-- whole layout. Matches selectedImports' CANON keyspace.
function EllesmereUI.BuildImportKeyToFolder(ul, metaK2F)
    metaK2F = metaK2F or {}
    local k2f = {}
    local function add(key)
        if type(key) ~= "string" or k2f[key] ~= nil then return end
        local f = metaK2F[key]
        if not f then
            local localF = ResolveKeyToFolder(key, nil)
            if localF then f = FOLDER_TO_CANON[localF] or localF end
        end
        if f then k2f[key] = f end
    end
    if type(ul) == "table" then
        if type(ul.anchors) == "table" then
            for c, i in pairs(ul.anchors) do add(c); if type(i) == "table" then add(i.target) end end
        end
        if type(ul.widthMatch) == "table" then for c, t in pairs(ul.widthMatch) do add(c); add(t) end end
        if type(ul.heightMatch) == "table" then for c, t in pairs(ul.heightMatch) do add(c); add(t) end end
    end
    return k2f
end

-- IMPORT merge: build the new profile's unlockLayout by merging the imported
-- (already module-filtered) relationships INTO the base (current-profile) layout,
-- PER MODULE. The new profile keeps the base's relationships for modules NOT
-- imported, and takes the imported relationships for modules that ARE imported.
-- Ownership is by the CHILD key's module (an anchor/match entry positions/sizes
-- its child). importedFolders = set of LOCAL folders being imported. For a full
-- import (every module) this reduces to "replace with imported" (every child is
-- owned by an imported module). LOCAL keyspace throughout.
function EllesmereUI.MergeImportedLayout(base, imported, importedFolders)
    base = (type(base) == "table") and base or {}
    imported = (type(imported) == "table") and imported or {}
    importedFolders = importedFolders or {}
    local out = {
        anchors       = DeepCopy(base.anchors       or {}),
        widthMatch    = DeepCopy(base.widthMatch    or {}),
        heightMatch   = DeepCopy(base.heightMatch   or {}),
        phantomBounds = DeepCopy(base.phantomBounds  or {}),
    }
    -- 1) Drop base entries OWNED by an imported module (child in importedFolders),
    --    so the imported module's layout fully replaces the base's for that module.
    --    Classify the BASE children via the live (recipient) registry + static
    --    resolver, since these are the recipient's own profile keys.
    local baseK2F = EllesmereUI.BuildLayoutKeyToFolder(base)
    local function childImported(child)
        local f = baseK2F[child]
        return f ~= nil and importedFolders[f] == true
    end
    for child in pairs(out.anchors)     do if childImported(child) then out.anchors[child]     = nil end end
    for child in pairs(out.widthMatch)  do if childImported(child) then out.widthMatch[child]  = nil end end
    for child in pairs(out.heightMatch) do if childImported(child) then out.heightMatch[child] = nil end end
    -- 2) Overlay the imported entries (already filtered to the imported modules).
    if type(imported.anchors) == "table" then
        for child, info in pairs(imported.anchors) do out.anchors[child] = DeepCopy(info) end
    end
    if type(imported.widthMatch) == "table" then
        for child, t in pairs(imported.widthMatch) do out.widthMatch[child] = t end
    end
    if type(imported.heightMatch) == "table" then
        for child, t in pairs(imported.heightMatch) do out.heightMatch[child] = t end
    end
    return out
end

-- Build the (filtered) unlockLayout + canonical keyToFolder meta to embed in an
-- export string, honoring the "Include layout" toggle and the selected modules.
--   unlockLayout : the profile's live layout (active profile == EllesmereUIDB.*)
--   includeLayout: false -> returns (nil, nil); no relationships embedded
--   folderSet    : set of LOCAL folders to keep (subset export); nil -> all
--                  checkbox modules (full export, still drops no-checkbox edges)
-- Returns (filteredUnlockLayout, meta) where meta.keyToFolder is CANONICAL.
function EllesmereUI.BuildExportUnlockLayout(unlockLayout, includeLayout, folderSet)
    if not includeLayout or type(unlockLayout) ~= "table" then return nil, nil end
    if not folderSet then
        folderSet = {}
        for _, entry in ipairs(ADDON_DB_MAP) do folderSet[entry.folder] = true end
    end
    local k2f = EllesmereUI.BuildLayoutKeyToFolder(unlockLayout)
    local filtered = EllesmereUI.FilterLayoutToFolders(unlockLayout, folderSet, k2f)
    local meta = { keyToFolder = {} }
    local function addMeta(key)
        if type(key) == "string" and meta.keyToFolder[key] == nil then
            local localF = k2f[key]
            if localF then meta.keyToFolder[key] = FOLDER_TO_CANON[localF] or localF end
        end
    end
    for c, i in pairs(filtered.anchors)     do addMeta(c); if type(i) == "table" then addMeta(i.target) end end
    for c, t in pairs(filtered.widthMatch)  do addMeta(c); addMeta(t) end
    for c, t in pairs(filtered.heightMatch) do addMeta(c); addMeta(t) end
    return filtered, meta
end



-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in EllesmereUIDB.profiles = { [name] = profileData }
--  profileData = {
--      addons = { [folderName] = <snapshot of that addon's profile table> },
--      fonts  = <snapshot of EllesmereUIDB.fonts>,
--      customColors = <snapshot of EllesmereUIDB.customColors>,
--  }
--  EllesmereUIDB.activeProfile = "Default"  (name of active profile)
--  EllesmereUIDB.profileOrder  = { "Default", ... }
--  EllesmereUIDB.specProfiles  = { [specID] = "profileName" }
-------------------------------------------------------------------------------
local function GetProfilesDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if not EllesmereUIDB.profileOrder then EllesmereUIDB.profileOrder = {} end
    if not EllesmereUIDB.specProfiles then EllesmereUIDB.specProfiles = {} end
    return EllesmereUIDB
end
EllesmereUI.GetProfilesDB = GetProfilesDB

-------------------------------------------------------------------------------
--  Anchor offset format conversion
--
--  Anchor offsets were originally stored relative to the target's center
--  (format version 0/nil). The current system stores them relative to
--  stable edges (format version 1):
--    TOP/BOTTOM: offsetX relative to target LEFT edge
--    LEFT/RIGHT: offsetY relative to target TOP edge
--
--- Check if an addon is loaded
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

--- Re-point all db.profile references to the given profile name.
--- Called when switching profiles so addons see the new data immediately.
local function RepointAllDBs(profileName)
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if type(EllesmereUIDB.profiles[profileName]) ~= "table" then
        EllesmereUIDB.profiles[profileName] = {}
    end
    local profileData = EllesmereUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end

    -- Sync handoff: pull synced module data from the outgoing profile into
    -- the incoming one, so a group member is current the moment it loads.
    -- activeProfile is already set to the new name by callers, so the copy
    -- MUST source from the registry's not-yet-repointed profile name --
    -- SyncModuleToProfiles cannot be used here (it sources from the active
    -- profile, which is already the incoming one).
    -- Mirror group: the pull only happens when BOTH the outgoing and the
    -- incoming profile are members of the module's group; a profile outside
    -- the group never pushes into it.
    local sm = EllesmereUIDB.syncedModules
    if sm then
        local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
        local outName = reg and reg[1] and reg[1]._profileName or "Default"
        local outProf = EllesmereUIDB.profiles[outName]
        if outProf and outProf.addons and outName ~= profileName then
            for folder, targets in pairs(sm) do
                if type(targets) == "table" and targets[profileName] and targets[outName]
                   and outProf.addons[folder] then
                    local exclusions = EllesmereUI._syncExclusions and EllesmereUI._syncExclusions[folder]
                    local dst = profileData.addons[folder]
                    if not (exclusions and next(exclusions)) then
                        profileData.addons[folder] = DeepCopy(outProf.addons[folder])
                    elseif type(dst) == "table" then
                        -- Overlay leaf-by-leaf so excluded keys (including
                        -- nested and wildcard paths) keep the dest's values
                        EllesmereUI._SelectiveOverlay(outProf.addons[folder], dst, exclusions, DeepCopy)
                    else
                        -- First sync to this profile: no dest values to preserve
                        profileData.addons[folder] = EllesmereUI._SelectiveCopy(outProf.addons[folder], exclusions)
                    end
                end
            end
        end
    end

    local registry = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not registry then return end
    for _, db in ipairs(registry) do
        local folder = db.folder
        if folder then
            if type(profileData.addons[folder]) ~= "table" then
                profileData.addons[folder] = {}
            end
            db.profile = profileData.addons[folder]
            db._profileName = profileName
            -- Re-merge defaults so new profile has all keys
            if db._profileDefaults then
                EllesmereUI.Lite.DeepMergeDefaults(db.profile, db._profileDefaults)
            end
        end
    end
    -- Restore unlock layout from the profile.
    -- If the profile has no unlockLayout yet (e.g. created before this key
    -- existed), leave the live unlock data untouched so the current
    -- positions are preserved. Only restore when the profile explicitly
    -- contains layout data from a previous save.
    local ul = profileData.unlockLayout
    if ul then
        EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
        EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
        EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
        EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
    end
    -- Seed castbar anchor defaults ONLY on brand-new profiles (no unlockLayout
    -- yet). Re-seeding every load would clobber a user's deliberate un-anchor
    -- or manual position with the default "target BOTTOM" anchor the next
    -- time the profile is applied (e.g. via spec profile assignment).
    if not ul then
        local anchors = EllesmereUIDB.unlockAnchors
        local wMatch  = EllesmereUIDB.unlockWidthMatch
        if anchors and wMatch then
            local CB_DEFAULTS = {
                { cb = "playerCastbar", parent = "player" },
                { cb = "targetCastbar", parent = "target" },
                { cb = "focusCastbar",  parent = "focus" },
            }
            for _, def in ipairs(CB_DEFAULTS) do
                if not anchors[def.cb] then
                    anchors[def.cb] = { target = def.parent, side = "BOTTOM" }
                end
                if not wMatch[def.cb] then
                    wMatch[def.cb] = def.parent
                end
            end
        end
    end
    -- Restore fonts and custom colors from the profile
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
    end
    -- Sidebar sync icons key off the ACTIVE profile's group membership;
    -- re-evaluate them on every repoint (switch/create/delete/rename/import)
    if EllesmereUI._syncRefreshFns then
        for _, fn in pairs(EllesmereUI._syncRefreshFns) do fn() end
    end
end

-------------------------------------------------------------------------------
--  ResolveSpecProfile
--
--  Single authoritative function that resolves the current spec's target
--  profile name. Used by both PreSeedSpecProfile (before OnEnable) and the
--  runtime spec event handler.
--
--  Resolution order:
--    1. Cached spec from lastSpecByChar (reliable across sessions)
--    2. Live GetSpecialization() API (available after ADDON_LOADED for
--       returning characters, may be nil for brand-new characters)
--
--  Returns: targetProfileName, resolvedSpecID, charKey  -- or nil if no
--           spec assignment exists or spec cannot be resolved yet.
-------------------------------------------------------------------------------
local function ResolveSpecProfile()
    if not EllesmereUIDB then return nil end
    local specProfiles = EllesmereUIDB.specProfiles
    if not specProfiles or not next(specProfiles) then return nil end

    local charKey = UnitName("player") .. " - " .. GetRealmName()
    if not EllesmereUIDB.lastSpecByChar then
        EllesmereUIDB.lastSpecByChar = {}
    end

    -- Prefer cached spec from last session (always reliable)
    local resolvedSpecID = EllesmereUIDB.lastSpecByChar[charKey]

    -- Fall back to live API if no cached value
    if not resolvedSpecID then
        local specIdx = GetSpecialization and GetSpecialization()
        if specIdx and specIdx > 0 then
            local liveSpecID = GetSpecializationInfo(specIdx)
            if liveSpecID then
                resolvedSpecID = liveSpecID
                EllesmereUIDB.lastSpecByChar[charKey] = resolvedSpecID
            end
        end
    end

    if not resolvedSpecID then return nil end

    local targetProfile = specProfiles[resolvedSpecID]
    if not targetProfile then return nil end

    local profiles = EllesmereUIDB.profiles
    if not profiles or not profiles[targetProfile] then return nil end

    return targetProfile, resolvedSpecID, charKey
end

-------------------------------------------------------------------------------
--  Spec profile pre-seed
--
--  Runs once just before child addon OnEnable calls, after all OnInitialize
--  calls have completed (so all NewDB calls have run).
--  At this point the spec API is available, so we can resolve the current
--  spec and re-point all db.profile references to the correct profile table
--  in the central store before any addon builds its UI.
--
--  This is the sole pre-OnEnable resolution point. NewDB reads activeProfile
--  as-is (defaults to "Default" or whatever was saved from last session).
-------------------------------------------------------------------------------

--- Called by EllesmereUI_Lite just before child addon OnEnable calls fire.
--- Uses ResolveSpecProfile() to determine the correct profile, then
--- re-points all db.profile references via RepointAllDBs.
function EllesmereUI.PreSeedSpecProfile()
    local targetProfile, resolvedSpecID = ResolveSpecProfile()
    if not targetProfile then
        -- No spec assignment resolved; lock auto-save if spec profiles exist
        if EllesmereUIDB and EllesmereUIDB.specProfiles and next(EllesmereUIDB.specProfiles) then
            EllesmereUI._profileSaveLocked = true
        end
        return
    end

    EllesmereUIDB.activeProfile = targetProfile
    RepointAllDBs(targetProfile)
    EllesmereUI._preSeedComplete = true
end

--- Get the live profile table for an addon.
--- All addons use _dbRegistry (which points into
--- EllesmereUIDB.profiles[active].addons[folder]).
local function GetAddonProfile(entry)
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder == entry.folder then
                return db.profile
            end
        end
    end
    return nil
end

--- Snapshot the current state of all loaded addons into a profile data table
function EllesmereUI.SnapshotAllAddons()
    local data = { addons = {} }
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                data.addons[entry.folder] = DeepCopy(profile)
            end
        end
    end
    -- Include global font and color settings
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    local cc = EllesmereUI.GetCustomColorsDB()
    data.customColors = DeepCopy(cc)
    -- Include unlock mode layout data (anchors, size matches)
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
        -- UI accent color (per-profile). Serialize the RESOLVED accent so an
        -- imported profile reproduces the source's visible accent regardless of
        -- whether it came from an explicit per-profile value or the fallback.
        local u, r, g, b = EllesmereUI.ResolveProfileAccent(EllesmereUI.GetActiveProfileData())
        -- Serialize useClass explicitly (false included) so an imported custom
        -- profile reports the right mode to the swatch on a character whose
        -- global useClassAccentColor is true.
        data.euiAccent = { useClass = u, custom = (not u) and { r = r, g = g, b = b } or nil }
    end
    return data
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
--- Snapshot a single addon's profile
function EllesmereUI.SnapshotAddon(folderName)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == folderName and IsAddonLoaded(folderName) then
            local profile = GetAddonProfile(entry)
            if profile then return DeepCopy(profile) end
        end
    end
    return nil
end

--- Snapshot multiple addons (for multi-addon export)
function EllesmereUI.SnapshotAddons(folderList)
    local data = { addons = {} }
    for _, folderName in ipairs(folderList) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    data.addons[folderName] = DeepCopy(profile)
                end
                break
            end
        end
    end
    -- Always include fonts and colors
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    data.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    -- Include unlock mode layout data
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    return data
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

--- Apply imported profile data into the live db.profile tables.
--- Used by import to write external data into the active profile.
--- For normal profile switching, use SwitchProfile (which calls RepointAllDBs).
function EllesmereUI.ApplyProfileData(profileData)
    if not profileData or not profileData.addons then return end

    -- Build a folder -> db lookup from the Lite registry
    local dbByFolder = {}
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder then dbByFolder[db.folder] = db end
        end
    end

    for _, entry in ipairs(ADDON_DB_MAP) do
        local snap = profileData.addons[entry.folder]
        if snap and IsAddonLoaded(entry.folder) then
            local db = dbByFolder[entry.folder]
            if db then
                local profile = db.profile
                -- CDM spell content (barSpells, TBB, barGlows) lives in the
                -- per-profile store at spellAssignments.profiles[name], NOT in
                -- this profile blob. No save/restore needed here: ImportProfile
                -- sets the new profile's bucket directly, and on a profile switch
                -- the live accessor + RefreshAllAddons rebuild pick it up.
                for k in pairs(profile) do profile[k] = nil end
                for k, v in pairs(snap) do profile[k] = DeepCopy(v) end
                -- Pre-split imports carry the shared totPet table but no
                -- targettarget/focustarget. The login split migration is SKIPPED
                -- for imported profiles (ImportProfile builds merged =
                -- DeepCopy(current), which inherits the current profile's
                -- migration flags), so forward-copy here -- BEFORE
                -- DeepMergeDefaults would otherwise fill in DEFAULT minis.
                if entry.folder == "EllesmereUIUnitFrames" and type(profile.totPet) == "table" then
                    if profile.targettarget == nil then profile.targettarget = DeepCopy(profile.totPet) end
                    if profile.focustarget  == nil then profile.focustarget  = DeepCopy(profile.totPet) end
                end
                if db._profileDefaults then
                    EllesmereUI.Lite.DeepMergeDefaults(profile, db._profileDefaults)
                end
                -- Ensure per-unit bg colors are never nil after import
                if entry.folder == "EllesmereUIUnitFrames" then
                    local UF_UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
                    local DEF_BG = 17/255
                    for _, uKey in ipairs(UF_UNITS) do
                        local s = profile[uKey]
                        if s and s.customBgColor == nil then
                            s.customBgColor = { r = DEF_BG, g = DEF_BG, b = DEF_BG }
                        end
                    end
                end
            end
        end
    end
    -- Apply fonts and colors
    do
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        if profileData.fonts then
            for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    do
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        if profileData.customColors then
            for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
        end
    end
    -- Restore unlock mode layout data
    if EllesmereUIDB then
        local ul = profileData.unlockLayout
        if ul then
            EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
            EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
            EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
            EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
        end
        -- If profile predates unlockLayout, leave live data untouched
    end
    -- Re-resolve + apply the UI accent for the now-active profile so an applied
    -- (imported) profile's accent takes effect immediately, consistent with the
    -- fonts/colors applied above. activeProfile is already repointed before
    -- ApplyProfileData runs, so this reads the correct profile's euiAccent and
    -- falls back to the frozen global root when none is set.
    if EllesmereUI.RefreshAccent then EllesmereUI.RefreshAccent() end
end

--- Trigger live refresh on all loaded addons after a profile apply.
function EllesmereUI.RefreshAllAddons()
    -- Suppress stale anchor moves on AB bars during the rebuild phase.
    -- LayoutBar positions them from the new profile's barPositions; resize
    -- hooks would reposition them with old-profile offsets (1-frame blink).
    -- Separate flag from _applyingSavedPositions so CDM's early-return in
    -- ApplyAnchorPosition (which checks _applyingSavedPositions) isn't
    -- triggered prematurely by the wider window.
    EllesmereUI._abAnchorSuppressed = true
    -- Phase 3: RefreshAllAddons runs on a real profile apply (swap/import) and on
    -- a per-spec-profile spec switch -- both load a NEW cdmBarPositions table with
    -- its own saved edges + follow baselines, so clear the follow-ready flag.
    -- Anchored CDM growth bars then re-pin to the new profile's absolute edge
    -- (delta 0) until that profile's chain settles and the settle debounce re-arms
    -- follow. A SHARED-profile spec change does NOT call RefreshAllAddons, so the
    -- flag stays set there and the bars track the sliding target smoothly.
    EllesmereUI._anchorFollowReady = nil
    -- Re-resolve + apply the UI accent color for the now-active profile BEFORE
    -- child modules refresh, since several re-read GetAccentColor() during their
    -- own apply (chat, cursor, mythic timer, glows, borders). Per-profile accent
    -- falls back to the frozen global root, so swapping profiles never changes
    -- the accent for users who never set a per-profile one.
    if EllesmereUI.RefreshAccent then EllesmereUI.RefreshAccent() end
    -- ResourceBars (full rebuild)
    if _G._ERB_Apply then _G._ERB_Apply() end
    -- CDM: skip during spec-profile switch. CDM's SPELLS_CHANGED handler
    -- will detect the spec key mismatch and rebuild with the correct spec.
    -- Running it here would race with that rebuild.
    if not EllesmereUI._specProfileSwitching then
        if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
            local curKey = _G._ECME_GetCurrentSpecKey()
            if curKey then _G._ECME_LoadSpecProfile(curKey) end
        end
        if _G._ECME_Apply then _G._ECME_Apply() end
    end
    -- Cursor (style + position)
    if _G._ECL_Apply then _G._ECL_Apply() end
    if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
    if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
    if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
    -- AuraBuffReminders (refresh + position)
    if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    if _G._EABR_ApplyUnlockPos then _G._EABR_ApplyUnlockPos() end
    -- ActionBars (style + layout + position)
    if _G._EAB_Apply then _G._EAB_Apply() end
    -- UnitFrames (style + layout + position)
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    -- Raid Frames + Party Frames (style + layout + size; positions re-applied below)
    if _G._ERF_RefreshAll then _G._ERF_RefreshAll() end
    -- Nameplates
    if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
    -- Quest Tracker
    if _G._EQT_RefreshAll then _G._EQT_RefreshAll() end
    -- Chat (sidebar icons, borders, fonts, visibility)
    if _G._ECHAT_RefreshAll then _G._ECHAT_RefreshAll() end
    -- Friends List
    if _G._EFR_ApplyFriends then _G._EFR_ApplyFriends() end
    -- Mythic Timer
    if _G._EMT_Apply then _G._EMT_Apply() end
    -- Damage Meters
    if _G._EDM_Apply then _G._EDM_Apply() end
    -- Dragon Riding HUD
    if _G._EDR_Rebuild then _G._EDR_Rebuild() end
    -- Minimap (flyout button state)
    if _G._EMIN_RefreshFlyout then _G._EMIN_RefreshFlyout() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
    -- Re-register unlock elements for all modules whose bar sets can
    -- differ between profiles. Without this, _applySavedPositions uses
    -- stale registrations from the outgoing profile and anchors fail
    -- for elements that only exist in the incoming profile (they land
    -- at CENTER/CENTER = screen center).
    if _G._ECME_RegisterUnlock then _G._ECME_RegisterUnlock() end
    if _G._ECME_RegisterTBBUnlock then _G._ECME_RegisterTBBUnlock() end
    if _G._ERB_RegisterUnlock then _G._ERB_RegisterUnlock() end
    if _G._EABR_RegisterUnlock then _G._EABR_RegisterUnlock() end
    if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
    if _G._EUI_BattleRes_RegisterUnlock then _G._EUI_BattleRes_RegisterUnlock() end
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions, re-apply centralized grow-direction positioning
    -- (handles lazy migration of imported TOPLEFT positions to CENTER format)
    -- and resync anchor offsets so the anchor relationships stay correct for
    -- future drags. Triple-deferred so it runs AFTER debounced rebuilds have
    -- completed and frames are at final positions.
    -- Position re-application and anchor resync are deferred to
    -- OnSpecSwitchComplete (if spec switching) or run inline here
    -- for non-spec profile switches (manual switch from options).
    if not EllesmereUI._specProfileSwitching then
        C_Timer.After(0, function()
            C_Timer.After(0, function()
                if EllesmereUI._applySavedPositions then
                    EllesmereUI._applySavedPositions()
                end
                if EllesmereUI.ResyncAnchorOffsets then
                    EllesmereUI.ResyncAnchorOffsets()
                end
            end)
        end)
    end
    -- If CDM is loaded, it calls OnSpecSwitchComplete from ProcessSpecChange
    -- after its SPELLS_CHANGED rebuild finishes. If CDM is NOT loaded,
    -- complete immediately since there's nothing to wait for.
    local cdmLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager")
    if not cdmLoaded then
        EllesmereUI.OnSpecSwitchComplete()
    end
end

--- Called by CDM (or RefreshAllAddons if CDM not loaded) when the spec
--- switch rebuild is fully settled. Clears the suppression flag and
--- re-applies width/height matches so all matched frames pick up
--- the new profile dimensions.
function EllesmereUI.OnSpecSwitchComplete()
    EllesmereUI._specProfileSwitching = false
    if EllesmereUI.ApplyAllWidthHeightMatches then
        EllesmereUI.ApplyAllWidthHeightMatches()
    end
    if EllesmereUI._applySavedPositions then
        EllesmereUI._applySavedPositions()
    end
    if EllesmereUI.ResyncAnchorOffsets then
        EllesmereUI.ResyncAnchorOffsets()
    end
end

-------------------------------------------------------------------------------
--  Profile Keybinds
--  Each profile can have a key bound to switch to it instantly.
--  Stored in EllesmereUIDB.profileKeybinds = { ["Name"] = "CTRL-1", ... }
--  Uses hidden buttons + SetOverrideBindingClick, same pattern as Party Mode.
-------------------------------------------------------------------------------
local _profileBindBtns = {} -- [profileName] = hidden Button

local function GetProfileKeybinds()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profileKeybinds then EllesmereUIDB.profileKeybinds = {} end
    return EllesmereUIDB.profileKeybinds
end

local function EnsureProfileBindBtn(profileName)
    if _profileBindBtns[profileName] then return _profileBindBtns[profileName] end
    local safeName = profileName:gsub("[^%w]", "")
    local btn = CreateFrame("Button", "EllesmereUIProfileBind_" .. safeName, UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        local active = EllesmereUI.GetActiveProfileName()
        if active == profileName then return end
        local _, profiles = EllesmereUI.GetProfileList()
        local fontWillChange = EllesmereUI.ProfileChangesFont(profiles and profiles[profileName])
        EllesmereUI.SwitchProfile(profileName)
        EllesmereUI.RefreshAllAddons()
        if fontWillChange then
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = "Font changed. A UI reload is needed to apply the new font.",
                confirmText = "Reload Now",
                cancelText  = "Later",
                onConfirm   = function() ReloadUI() end,
            })
        else
            EllesmereUI:RefreshPage()
        end
    end)
    _profileBindBtns[profileName] = btn
    return btn
end

function EllesmereUI.SetProfileKeybind(profileName, key)
    local kb = GetProfileKeybinds()
    -- Clear old binding for this profile
    local oldKey = kb[profileName]
    local btn = EnsureProfileBindBtn(profileName)
    if oldKey then
        ClearOverrideBindings(btn)
    end
    if key then
        kb[profileName] = key
        SetOverrideBindingClick(btn, true, key, btn:GetName())
    else
        kb[profileName] = nil
    end
end

function EllesmereUI.GetProfileKeybind(profileName)
    local kb = GetProfileKeybinds()
    return kb[profileName]
end

--- Called on login to restore all saved profile keybinds
function EllesmereUI.RestoreProfileKeybinds()
    local kb = GetProfileKeybinds()
    for profileName, key in pairs(kb) do
        if key then
            local btn = EnsureProfileBindBtn(profileName)
            SetOverrideBindingClick(btn, true, key, btn:GetName())
        end
    end
end

--- Update keybind references when a profile is renamed
function EllesmereUI.OnProfileRenamed(oldName, newName)
    local kb = GetProfileKeybinds()
    local key = kb[oldName]
    if key then
        local oldBtn = _profileBindBtns[oldName]
        if oldBtn then ClearOverrideBindings(oldBtn) end
        _profileBindBtns[oldName] = nil
        kb[oldName] = nil
        kb[newName] = key
        local newBtn = EnsureProfileBindBtn(newName)
        SetOverrideBindingClick(newBtn, true, key, newBtn:GetName())
    end
end

--- Clean up keybind when a profile is deleted
function EllesmereUI.OnProfileDeleted(profileName)
    local kb = GetProfileKeybinds()
    if kb[profileName] then
        local btn = _profileBindBtns[profileName]
        if btn then ClearOverrideBindings(btn) end
        _profileBindBtns[profileName] = nil
        kb[profileName] = nil
    end
end

--- Returns true if applying profileData would change the global font or outline mode.
--- Used to decide whether to show a reload popup after a profile switch.
function EllesmereUI.ProfileChangesFont(profileData)
    if not profileData or not profileData.fonts then return false end
    local cur = EllesmereUI.GetFontsDB()
    local curFont    = cur.global      or "Expressway"
    local curOutline = cur.outlineMode or "shadow"
    local newFont    = profileData.fonts.global      or "Expressway"
    local newOutline = profileData.fonts.outlineMode or "shadow"
    -- "none" and "shadow" are both drop-shadow (no outline) -- treat as identical
    if curOutline == "none" then curOutline = "shadow" end
    if newOutline == "none" then newOutline = "shadow" end
    return curFont ~= newFont or curOutline ~= newOutline
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
--- Apply a partial profile (specific addons only) by merging into active
function EllesmereUI.ApplyPartialProfile(profileData)
    if not profileData or not profileData.addons then return end
    for folderName, snap in pairs(profileData.addons) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    for k, v in pairs(snap) do
                        profile[k] = DeepCopy(v)
                    end
                end
                break
            end
        end
    end
    -- Always apply fonts and colors if present
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k, v in pairs(profileData.fonts) do
            fontsDB[k] = DeepCopy(v)
        end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k, v in pairs(profileData.customColors) do
            colorsDB[k] = DeepCopy(v)
        end
    end
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

-------------------------------------------------------------------------------
--  Export / Import
--  Format: !EUI_<base64 encoded compressed serialized data>
--  The data table contains:
--    { version = 3, type = "full"|"partial", data = profileData }
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"

function EllesmereUI.ExportProfile(profileName, includedFolders, includeLayout)
    if includeLayout == nil then includeLayout = true end  -- default ON
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    -- If exporting the active profile, ensure fonts/colors/layout are current
    if profileName == (db.activeProfile or "Default") then
        profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        profileData.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    local exportData = DeepCopy(profileData)
    -- UI accent color (per-profile): serialize the RESOLVED accent for THIS
    -- profile (works for active and non-active profiles; never mutates the
    -- stored profile, and is rename-immune since it is a data-root field, not
    -- an addons[] folder key).
    do
        local u, r, g, b = EllesmereUI.ResolveProfileAccent(profileData)
        -- Serialize useClass explicitly (see SnapshotAllAddons).
        exportData.euiAccent = { useClass = u, custom = (not u) and { r = r, g = g, b = b } or nil }
    end
    -- Only export addons that are actually loaded (supports standalone installs)
    -- When includedFolders is provided, further filter to user's selection
    if exportData.addons then
        for folder in pairs(exportData.addons) do
            if not IsAddonLoaded(folder) then
                exportData.addons[folder] = nil
            elseif includedFolders and not includedFolders[folder] then
                exportData.addons[folder] = nil
            end
        end
    end
    -- Exclude spec-specific data from export
    exportData.trackedBuffBars = nil
    exportData.tbbPositions = nil
    -- CDM spell assignments are NOT exported -- users share spell layouts
    -- via Blizzard's built-in CDM sharing system instead.
    exportData.spellAssignments = nil
    -- HoverCast (click-cast) bindings are account-global, not per-profile. They
    -- live at EllesmereUIDB.clickCast (top-level, parallel to spellAssignments),
    -- so importing someone else's profile must never overwrite the user's own
    -- click-cast setup. Strip defensively in case a payload ever carries it.
    exportData.clickCast = nil
    -- fonts/customColors/euiAccent are profile-GLOBAL appearance and are not
    -- separable per-addon, so a subset export must not carry them (they'd clobber
    -- the recipient's). Only a full-profile export carries them.
    if includedFolders then
        exportData.fonts        = nil
        exportData.customColors = nil
        exportData.euiAccent    = nil
    end
    -- Layout relationships (unlockLayout) are governed by the "Include layout"
    -- toggle and FILTERED per-module: only relationships whose both endpoints are
    -- in the selected modules survive (subset export), and no-checkbox-module
    -- (Dragon Riding) + stale (deleted-bar) edges are always dropped. A canonical
    -- keyToFolder meta rides along so the importer can attribute each edge. Full
    -- export (no includedFolders) keeps all checkbox-module relationships.
    local fLayout, layoutMeta = EllesmereUI.BuildExportUnlockLayout(
        exportData.unlockLayout, includeLayout, includedFolders)
    exportData.unlockLayout     = fLayout      -- nil when includeLayout is off
    exportData.unlockLayoutMeta = layoutMeta   -- nil when includeLayout is off
    -- Normalize local db.folder keys -> canonical (suite) keys so the string
    -- imports correctly into any build. No-op in the suite (canon == folder).
    exportData.addons = AddonsToCanon(exportData.addons)
    local payload = { version = 3, type = "full", data = exportData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

-- Re-encode a decoded payload back to an import string.
-- Used by the import page to strip unchecked addons before calling ImportProfile.
function EllesmereUI.EncodePayload(payload)
    if not payload then return nil end
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
function EllesmereUI.ExportAddons(folderList)
    local profileData = EllesmereUI.SnapshotAddons(folderList)
    local sw, sh = GetPhysicalScreenSize()
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 3, type = "partial", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

-------------------------------------------------------------------------------
--  CDM spec profile helpers for export/import spec picker
-------------------------------------------------------------------------------

--- Get info about which specs have data in the CDM specProfiles table.
--- Returns: { { key="250", name="Blood", icon=..., hasData=true }, ... }
--- Includes ALL specs for the player's class, with hasData indicating
--- whether specProfiles contains data for that spec.
function EllesmereUI.GetCDMSpecInfo()
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    local specProfiles = sa and sa.specProfiles or {}
    local result = {}
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID, sName, _, sIcon = GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            result[#result + 1] = {
                key     = key,
                name    = sName or ("Spec " .. key),
                icon    = sIcon,
                hasData = specProfiles[key] ~= nil,
            }
        end
    end
    return result
end

--- Filter specProfiles in an export snapshot to only include selected specs.
--- Reads from snapshot.spellAssignments (the dedicated store copy on the payload).
--- Modifies the snapshot in-place. selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.FilterExportSpecProfiles(snapshot, selectedSpecs)
    if not snapshot or not snapshot.spellAssignments then return end
    local sp = snapshot.spellAssignments.specProfiles
    if not sp then return end
    for key in pairs(sp) do
        if not selectedSpecs[key] then
            sp[key] = nil
        end
    end
end

--- After a profile import, apply only selected specs' specProfiles from the
--- imported data into the dedicated spell assignment store.
--- importedSpellAssignments = the spellAssignments object from the import payload.
--- selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.ApplyImportedSpecProfiles(importedSpellAssignments, selectedSpecs)
    if not importedSpellAssignments or not importedSpellAssignments.specProfiles then return end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { specProfiles = {} }
    end
    local sa = EllesmereUIDB.spellAssignments
    if not sa.specProfiles then sa.specProfiles = {} end
    for key, data in pairs(importedSpellAssignments.specProfiles) do
        if selectedSpecs[key] then
            sa.specProfiles[key] = DeepCopy(data)
        end
    end
    -- If the current spec was imported, reload it live
    if _G._ECME_GetCurrentSpecKey and _G._ECME_LoadSpecProfile then
        local currentKey = _G._ECME_GetCurrentSpecKey()
        if currentKey and selectedSpecs[currentKey] then
            _G._ECME_LoadSpecProfile(currentKey)
        end
    end
end

--- Get the list of spec keys that have data in imported spell assignments.
--- Returns same format as GetCDMSpecInfo but based on imported data.
--- Accepts either the new spellAssignments format or legacy CDM snapshot.
function EllesmereUI.GetImportedCDMSpecInfo(importedSpellAssignments)
    if not importedSpellAssignments then return {} end
    -- Support both new format (spellAssignments.specProfiles) and legacy (cdmSnap.specProfiles)
    local specProfiles = importedSpellAssignments.specProfiles
    if not specProfiles then return {} end
    local result = {}
    for specKey in pairs(specProfiles) do
        local specID = tonumber(specKey)
        local name, icon
        if specID and specID > 0 and GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            name = sName
            icon = sIcon
        end
        result[#result + 1] = {
            key     = specKey,
            name    = name or ("Spec " .. specKey),
            icon    = icon,
            hasData = true,
        }
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

-------------------------------------------------------------------------------
--  CDM Spec Picker Popup
--  Thin wrapper around ShowSpecAssignPopup for CDM export/import.
--
--  opts = {
--      title    = string,
--      subtitle = string,
--      confirmText = string (button label),
--      specs    = { { key, name, icon, hasData, checked }, ... },
--      onConfirm = function(selectedSpecs)  -- { ["250"]=true, ... }
--      onCancel  = function() (optional)
--  }
--  specs[i].hasData = false grays out the row and shows disabled tooltip.
--  specs[i].checked = initial checked state (only for hasData=true rows).
-------------------------------------------------------------------------------
do
    -- Dummy db/dbKey/presetKey for the assignments table
    local dummyDB = { _cdmPick = { _cdm = {} } }

    function EllesmereUI:ShowCDMSpecPickerPopup(opts)
        local specs = opts.specs or {}

        -- Reset assignments
        dummyDB._cdmPick._cdm = {}

        -- Pre-check specs that have data; all specs remain selectable
        local preCheckedSpecs = {}
        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID and sp.checked then
                preCheckedSpecs[numID] = true
            end
        end

        EllesmereUI:ShowSpecAssignPopup({
            db              = dummyDB,
            dbKey           = "_cdmPick",
            presetKey       = "_cdm",
            title           = opts.title,
            subtitle        = opts.subtitle,
            buttonText      = opts.confirmText or "Confirm",
            disabledSpecs   = {},
            preCheckedSpecs = preCheckedSpecs,
            onConfirm       = opts.onConfirm and function(assignments)
                -- Convert numeric specID assignments back to string keys
                local selected = {}
                for specID in pairs(assignments) do
                    selected[tostring(specID)] = true
                end
                opts.onConfirm(selected)
            end,
            onCancel        = opts.onCancel,
        })
    end
end

function EllesmereUI.ExportCurrentProfile(includeLayout)
    if includeLayout == nil then includeLayout = true end  -- default ON
    local profileData = EllesmereUI.SnapshotAllAddons()
    -- CDM spell assignments are NOT exported -- users share spell layouts
    -- via Blizzard's built-in CDM sharing system instead.
    profileData.spellAssignments = nil
    -- HoverCast (click-cast) bindings are account-global, not per-profile; never export.
    profileData.clickCast = nil
    -- Layout: honor the "Include layout" toggle, and even on a full export drop the
    -- no-checkbox-module (Dragon Riding) + stale (deleted-bar) edges. folderSet=nil
    -- keeps all checkbox modules. Attach the canonical keyToFolder meta.
    local fLayout, layoutMeta = EllesmereUI.BuildExportUnlockLayout(
        profileData.unlockLayout, includeLayout, nil)
    profileData.unlockLayout     = fLayout
    profileData.unlockLayoutMeta = layoutMeta
    local sw, sh = GetPhysicalScreenSize()
    -- Use EllesmereUI's own stored scale (UIParent scale), not Blizzard's CVar
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    -- Normalize local db.folder keys -> canonical (suite) keys (no-op in suite).
    profileData.addons = AddonsToCanon(profileData.addons)
    local payload = { version = 3, type = "full", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < 5 then return nil, "Invalid string" end
    -- Detect old CDM bar layout strings (format removed in 5.1.2)
    if importStr:sub(1, 9) == "!EUICDM_" then
        return nil, "This is an old CDM Bar Layout string. This format is no longer supported. Use the standard profile import instead."
    end
    if importStr:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "Not a valid EllesmereUI string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = importStr:sub(#EXPORT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return nil, "Failed to deserialize data"
    end
    if not payload.version or payload.version < 3 then
        return nil, "This profile was created before the beta wipe and is no longer compatible. Please create a new export."
    end
    if payload.version > 3 then
        return nil, "This profile was created with a newer version of EllesmereUI. Please update your addon."
    end
    return payload, nil
end

--- Reset class-dependent fill colors in Resource Bars after a profile import.
--- The exporter's class color may be baked into fillR/fillG/fillB; this
--- resets them to the importer's own class/power colors and clears
--- customColored so the bars use runtime class color lookup.
local function FixupImportedClassColors()
    local rbEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUIResourceBars" then rbEntry = e; break end
    end
    if not rbEntry or not IsAddonLoaded(rbEntry.folder) then return end
    local profile = GetAddonProfile(rbEntry)
    if not profile then return end

    local _, classFile = UnitClass("player")
    -- CLASS_COLORS and POWER_COLORS are local to ResourceBars, so we
    -- use the same lookup the addon uses at init time.
    local classColors = EllesmereUI.CLASS_COLOR_MAP
    local cc = classColors and classColors[classFile]

    -- Health bar: reset to importer's class color
    if profile.health and not profile.health.darkTheme then
        profile.health.customColored = false
        if cc then
            profile.health.fillR = cc.r
            profile.health.fillG = cc.g
            profile.health.fillB = cc.b
        end
    end
end

-- Per-profile CDM spell store helpers.
-- The CDM spell/bar-content store lives at
-- EllesmereUIDB.spellAssignments.profiles[name].specProfiles -- a top-level
-- table OUTSIDE the profile blob, so it never travels with profile export or
-- module sync (both operate on the profile's addons blob). These helpers
-- fork/move/drop a profile's CDM bucket in lockstep with the profile itself.
-- Defined above ImportProfile so all profile-lifecycle functions can use it.
local function GetSpellStoreProfiles()
    if not EllesmereUIDB then return nil end
    local sa = EllesmereUIDB.spellAssignments
    if not sa then
        sa = { profiles = {} }
        EllesmereUIDB.spellAssignments = sa
    end
    if not sa.profiles then sa.profiles = {} end
    return sa.profiles
end

--- Import a profile string. Returns: success, errorMsg
--- The caller must provide a name for the new profile.
function EllesmereUI.ImportProfile(importStr, profileName)
    local payload, err = EllesmereUI.DecodeImportString(importStr)
    if not payload then return false, err end

    -- Normalize canonical (suite) addon keys -> this build's local db.folder
    -- keys, so a suite string imports into a standalone (and vice versa). Runs
    -- before all downstream addon-key handling. No-op in the suite.
    if payload.data and payload.data.addons then
        payload.data.addons = CanonToLocal(payload.data.addons)
    end

    local db = GetProfilesDB()

    if payload.type == "cdm_spells" then
        return false, "This is a CDM Bar Layout string, not a profile string."
    end

    -- Check if current spec has an assigned profile (blocks auto-apply)
    local specLocked = false
    do
        local si = GetSpecialization and GetSpecialization() or 0
        local sid = si and si > 0 and GetSpecializationInfo(si) or nil
        if sid then
            local assigned = db.specProfiles and db.specProfiles[sid]
            if assigned then specLocked = true end
        end
    end

    if payload.type == "full" then
        -- Merge import: start from the current profile and overlay imported
        -- addon data on top. This preserves settings for addons not present
        -- in the import (e.g. importing from a standalone install).
        local imported = DeepCopy(payload.data)
        -- Strip spell assignment data from imported profile (lives in dedicated store)
        if imported.addons and imported.addons["EllesmereUICooldownManager"] then
            imported.addons["EllesmereUICooldownManager"].specProfiles = nil
            imported.addons["EllesmereUICooldownManager"].barGlows = nil
        end
        imported.spellAssignments = nil
        -- HoverCast (click-cast) bindings live at EllesmereUIDB.clickCast (account-
        -- global), never inside a profile. Strip any stray clickCast from the
        -- payload so an import can never overwrite the user's own click-cast setup.
        imported.clickCast = nil

        -- Base: deep-copy current active profile, then overlay imported addons
        local current = db.profiles[db.activeProfile or "Default"]
        local merged = current and DeepCopy(current) or {}
        if not merged.addons then merged.addons = {} end
        if imported.addons then
            for folder, snap in pairs(imported.addons) do
                merged.addons[folder] = DeepCopy(snap)
            end
        end
        -- Take fonts/colors from import if present (the partial-import OnClick nils
        -- these so a subset import keeps the base profile's appearance).
        if imported.fonts then merged.fonts = DeepCopy(imported.fonts) end
        if imported.customColors then merged.customColors = DeepCopy(imported.customColors) end
        -- Layout: the new profile's unlockLayout is the active profile's CURRENT
        -- layout, with the imported relationships merged in PER MODULE.
        --
        -- Build the base UNCONDITIONALLY (even when the import carries no layout):
        -- the user's anchors frequently live ONLY in the live EllesmereUIDB.unlock*
        -- tables -- the stored profile.unlockLayout snapshot lags until a switch/
        -- export, and EllesmereUIDB.unlockAnchors itself can be absent. So fold the
        -- live tables onto the stored copy here; otherwise a "Include layout = off"
        -- (or layout-less) import would drop the current profile's live anchors.
        do
            local baseUL = merged.unlockLayout or {}
            baseUL.anchors       = baseUL.anchors       or {}
            baseUL.widthMatch    = baseUL.widthMatch    or {}
            baseUL.heightMatch   = baseUL.heightMatch   or {}
            baseUL.phantomBounds = baseUL.phantomBounds or {}
            local function overlayLive(dst, live)
                if type(live) == "table" then for k, v in pairs(live) do dst[k] = DeepCopy(v) end end
            end
            if EllesmereUIDB then
                overlayLive(baseUL.anchors,     EllesmereUIDB.unlockAnchors)
                overlayLive(baseUL.widthMatch,  EllesmereUIDB.unlockWidthMatch)
                overlayLive(baseUL.heightMatch, EllesmereUIDB.unlockHeightMatch)
            end
            merged.unlockLayout = baseUL  -- current full layout (kept when no import layout)

            -- Per-module merge of the imported relationships: keep base for modules
            -- NOT imported (e.g. ActionBars self-anchors); take imported for those
            -- that ARE. imported.addons keys = imported modules (LOCAL).
            if imported.unlockLayout then
                local importedFolders = {}
                if imported.addons then
                    for folder in pairs(imported.addons) do importedFolders[folder] = true end
                end
                merged.unlockLayout = EllesmereUI.MergeImportedLayout(
                    baseUL, imported.unlockLayout, importedFolders)
            end
        end
        -- UI accent color travels with the profile. A new-format string always
        -- carries euiAccent, so the imported value wins; an old string leaves
        -- merged.euiAccent inherited from the current profile (correct fallback).
        if imported.euiAccent then merged.euiAccent = DeepCopy(imported.euiAccent) end

        -- Snap all positions to the physical pixel grid (imported profiles
        -- may come from a different version without pixel snapping)
        if EllesmereUI.SnapProfilePositions then
            EllesmereUI.SnapProfilePositions(merged)
        end
        db.profiles[profileName] = merged
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        -- Per-profile CDM spell store. The export payload never carries CDM
        -- spell content (it is stripped above and lives outside the profile
        -- blob), so set the new profile's bucket by intent:
        --   * import string INCLUDED the CDM module -> empty bucket, so the
        --     default cooldown/utility/buff bars get the spec's default
        --     population and any imported custom-bar shells stay empty.
        --   * import OMITTED CDM (subset/merge import) -> fork the current
        --     profile's bucket so its spell allocations carry over unchanged.
        -- Done BEFORE the specLocked early-return so locked-spec imports still
        -- get a bucket. db.activeProfile is still the source profile here (it is
        -- repointed to profileName below), so forking from it is correct.
        do
            local profiles = GetSpellStoreProfiles()
            if profiles then
                local cdmIncluded = payload.data and payload.data.addons
                    and payload.data.addons["EllesmereUICooldownManager"] ~= nil
                if cdmIncluded then
                    profiles[profileName] = { specProfiles = {} }
                else
                    local cur = profiles[db.activeProfile or "Default"]
                    profiles[profileName] = cur and DeepCopy(cur) or { specProfiles = {} }
                end
            end
        end
        -- Remove the new profile from all sync targets so the pre-logout
        -- sync doesn't overwrite it. Other profiles' sync relationships
        -- are preserved (per-profile sync system).
        if EllesmereUIDB and EllesmereUIDB.syncedModules then
            for folder, targets in pairs(EllesmereUIDB.syncedModules) do
                if type(targets) == "table" then
                    targets[profileName] = nil
                end
            end
        end

        if specLocked then
            return true, nil, "spec_locked"
        end
        -- Make it the active profile and re-point db references
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        -- Apply imported data into the live db.profile tables. We MUST pass
        -- payload.data here (a SEPARATE table) and NOT merged: RepointAllDBs already
        -- pointed db.profile INTO merged.addons, and ApplyProfileData clears db.profile
        -- before copying the snapshot in -- passing merged would clear-then-copy the
        -- same table and wipe every addon. payload.data.addons only holds the imported
        -- modules, so non-imported modules keep their (base) live data untouched.
        -- BUT the live unlock layout must be the per-module-MERGED one, otherwise the
        -- filtered import wipes the live anchors of non-imported modules (e.g.
        -- ActionBars self-anchors). Override it before applying.
        payload.data.unlockLayout = merged.unlockLayout
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- Don't ReloadUI() here: the caller (options panel import flow)
        -- may need to show the CDM spec picker popup before reloading.
        -- The caller handles the reload/refresh after the popup completes.
        return true, nil
    --[[ ADDON-SPECIFIC EXPORT DISABLED
    elseif payload.type == "partial" then
        -- Partial: deep-copy current profile, overwrite the imported addons
        local current = db.activeProfile or "Default"
        local currentData = db.profiles[current]
        local merged = currentData and DeepCopy(currentData) or {}
        if not merged.addons then merged.addons = {} end
        if payload.data and payload.data.addons then
            for folder, snap in pairs(payload.data.addons) do
                local copy = DeepCopy(snap)
                -- Strip spell assignment data from CDM profile (lives in dedicated store)
                if folder == "EllesmereUICooldownManager" and type(copy) == "table" then
                    copy.specProfiles = nil
                    copy.barGlows = nil
                end
                merged.addons[folder] = copy
            end
        end
        if payload.data.fonts then
            merged.fonts = DeepCopy(payload.data.fonts)
        end
        if payload.data.customColors then
            merged.customColors = DeepCopy(payload.data.customColors)
        end
        -- Store as new profile
        merged.spellAssignments = nil
        db.profiles[profileName] = merged
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        -- Write spell assignments to dedicated store
        if payload.data and payload.data.spellAssignments then
            if not EllesmereUIDB.spellAssignments then
                EllesmereUIDB.spellAssignments = { specProfiles = {} }
            end
            local sa = EllesmereUIDB.spellAssignments
            local imported = payload.data.spellAssignments
            if imported.specProfiles then
                for key, data in pairs(imported.specProfiles) do
                    sa.specProfiles[key] = DeepCopy(data)
                end
            end
            if imported.barGlows and next(imported.barGlows) then
                -- barGlows is now per-spec in specProfiles, not global. Skip import.
            end
        end
        -- Backward compat: extract specProfiles from CDM addon data (pre-migration format)
        if payload.data and payload.data.addons and payload.data.addons["EllesmereUICooldownManager"] then
            local cdm = payload.data.addons["EllesmereUICooldownManager"]
            if cdm.specProfiles then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                for key, data in pairs(cdm.specProfiles) do
                    if not EllesmereUIDB.spellAssignments.specProfiles[key] then
                        EllesmereUIDB.spellAssignments.specProfiles[key] = DeepCopy(data)
                    end
                end
            end
            if cdm.barGlows then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                if not next(EllesmereUIDB.spellAssignments.barGlows or {}) then
                    -- barGlows is now per-spec in specProfiles, not global. Skip import.
                end
            end
        end
        if specLocked then
            return true, nil, "spec_locked"
        end
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        EllesmereUI.ApplyProfileData(merged)
        FixupImportedClassColors()
        -- Reload UI so every addon rebuilds from scratch with correct data
        ReloadUI()
        return true, nil
    --]] -- END ADDON-SPECIFIC EXPORT DISABLED
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name)
    local db = GetProfilesDB()
    local current = db.activeProfile or "Default"
    local src = db.profiles[current]

    -- Count existing profiles BEFORE adding the new one
    local profileCountBefore = 0
    for _ in pairs(db.profiles) do profileCountBefore = profileCountBefore + 1 end

    -- Count existing profiles BEFORE adding the new one
    -- Deep-copy the current profile into the new name
    local copy = src and DeepCopy(src) or {}
    -- Ensure fonts/colors/unlock layout are current
    copy.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    copy.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    copy.unlockLayout = {
        anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
        widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
        heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
        phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
    }
    db.profiles[name] = copy
    -- Fork the source profile's CDM spell store so the copy owns an independent
    -- set of cooldown/bar spell assignments. The store lives outside the profile
    -- blob, so the DeepCopy(src) above did not carry it; without this fork the
    -- copy would share the origin's spec buckets and deleting a bar in the copy
    -- would wipe the origin (the reported bug).
    do
        local profiles = GetSpellStoreProfiles()
        if profiles then
            local srcBucket = profiles[current]
            profiles[name] = srcBucket and DeepCopy(srcBucket) or { specProfiles = {} }
        end
    end
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end

    -- Bags is the ONE module that auto-syncs: bag settings should match
    -- across profiles. Every other module is strictly opt-in via the sync
    -- popup, and new profiles never inherit its group membership.
    if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
    local bagsGroup = EllesmereUIDB.syncedModules.EllesmereUIBags
    if profileCountBefore == 1 then
        -- First second profile: create the default Bags group
        if type(bagsGroup) ~= "table" then
            bagsGroup = {}
            EllesmereUIDB.syncedModules.EllesmereUIBags = bagsGroup
        end
        bagsGroup[current] = true
        bagsGroup[name] = true
    elseif type(bagsGroup) == "table" and bagsGroup[current] then
        -- A copy of a bags-synced profile joins the group. Copies of a
        -- profile the user deliberately removed from it stay out.
        bagsGroup[name] = true
    end

    -- Switch to the new profile using the standard path so the outgoing
    -- profile's state is properly saved before repointing.
    EllesmereUI.SwitchProfile(name)
end

function EllesmereUI.DeleteProfile(name)
    local db = GetProfilesDB()
    db.profiles[name] = nil
    for i, n in ipairs(db.profileOrder) do
        if n == name then table.remove(db.profileOrder, i); break end
    end
    -- Clean up spec assignments
    for specID, pName in pairs(db.specProfiles) do
        if pName == name then db.specProfiles[specID] = nil end
    end
    -- Drop the profile's CDM spell store bucket so it doesn't linger.
    do
        local profiles = GetSpellStoreProfiles()
        if profiles then profiles[name] = nil end
    end
    -- Clean up sync targets: remove deleted profile from every module's list
    if EllesmereUIDB.syncedModules then
        for folder, targets in pairs(EllesmereUIDB.syncedModules) do
            if type(targets) == "table" then
                targets[name] = nil
            end
        end
    end
    -- Clean up keybind
    EllesmereUI.OnProfileDeleted(name)
    -- If deleted profile was active, fall back to Default
    if db.activeProfile == name then
        db.activeProfile = "Default"
        RepointAllDBs("Default")
    end
    -- Refresh all sync buttons (hide them if down to 1 profile)
    if EllesmereUI._syncRefreshFns then
        for _, fn in pairs(EllesmereUI._syncRefreshFns) do fn() end
    end
end

function EllesmereUI.RenameProfile(oldName, newName)
    local db = GetProfilesDB()
    if not db.profiles[oldName] then return end
    db.profiles[newName] = db.profiles[oldName]
    db.profiles[oldName] = nil
    -- Move the profile's CDM spell store bucket to the new name.
    do
        local profiles = GetSpellStoreProfiles()
        if profiles and profiles[oldName] ~= nil then
            profiles[newName] = profiles[oldName]
            profiles[oldName] = nil
        end
    end
    for i, n in ipairs(db.profileOrder) do
        if n == oldName then db.profileOrder[i] = newName; break end
    end
    for specID, pName in pairs(db.specProfiles) do
        if pName == oldName then db.specProfiles[specID] = newName end
    end
    -- Move sync group membership to the new name so the renamed profile
    -- keeps syncing and no dead entry lingers in any module's group
    if EllesmereUIDB.syncedModules then
        for _, targets in pairs(EllesmereUIDB.syncedModules) do
            if type(targets) == "table" and targets[oldName] then
                targets[oldName] = nil
                targets[newName] = true
            end
        end
    end
    if db.activeProfile == oldName then
        db.activeProfile = newName
        RepointAllDBs(newName)
    end
    -- Update keybind reference
    EllesmereUI.OnProfileRenamed(oldName, newName)
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    if not db.profiles[name] then return end

    -- Save current fonts/colors into the outgoing profile before switching
    local outgoing = db.profiles[db.activeProfile or "Default"]
    if outgoing then
        outgoing.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        outgoing.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        -- Save unlock layout into outgoing profile
        outgoing.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end

    -- If settings were changed this session and any synced modules have
    -- targets, a live re-point won't fully apply cached addon state.
    -- Prompt the user to reload so every addon starts clean.
    if EllesmereUI._settingsChanged and name ~= (db.activeProfile or "Default") then
        local sm = EllesmereUIDB.syncedModules
        if sm then
            -- Mirror group: only flush groups the OUTGOING profile belongs
            -- to. A profile outside a group never pushes into it.
            local outName = db.activeProfile or "Default"
            local hasSyncTargets = false
            for folder, targets in pairs(sm) do
                if type(targets) == "table" and targets[outName] then
                    hasSyncTargets = true
                    break
                end
            end
            if hasSyncTargets then
                -- Flush sync so the other group members have the latest data
                for folder, targets in pairs(sm) do
                    if type(targets) == "table" and targets[outName] then
                        EllesmereUI.SyncModuleToProfiles(folder, targets)
                    end
                end
                -- Switch the active profile immediately (persisted on logout)
                db.activeProfile = name
                RepointAllDBs(name)
                -- Prompt for reload
                EllesmereUI:ShowConfirmPopup({
                    title = "Reload Recommended",
                    message = "You changed settings while profile sync is active. Please reload your UI for sync changes to take effect.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    onConfirm = function() ReloadUI() end,
                })
                return
            end
        end
    end

    db.activeProfile = name
    RepointAllDBs(name)
end

function EllesmereUI.GetActiveProfileName()
    local db = GetProfilesDB()
    return db.activeProfile or "Default"
end

function EllesmereUI.GetProfileList()
    local db = GetProfilesDB()
    return db.profileOrder, db.profiles
end

function EllesmereUI.AssignProfileToSpec(profileName, specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = profileName
end

function EllesmereUI.UnassignSpec(specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = nil
end

function EllesmereUI.GetSpecProfile(specID)
    local db = GetProfilesDB()
    return db.specProfiles[specID]
end

-------------------------------------------------------------------------------
--  AutoSaveActiveProfile: no-op in single-storage mode.
--  Addons write directly to EllesmereUIDB.profiles[active].addons[folder],
--  so there is nothing to snapshot. Kept as a stub so existing call sites
--  (keybind buttons, options panel hooks) do not error.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    -- Intentionally empty: single-storage means data is always in sync.
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
--
--  Single authoritative runtime handler for spec-based profile switching.
--  Uses ResolveSpecProfile() for all resolution. Defers the entire switch
--  during combat via pendingSpecSwitch / PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------
do
    local specFrame = CreateFrame("Frame")
    local lastKnownSpecID = nil
    local lastKnownCharKey = nil
    local pendingSpecSwitch = false   -- true when a switch was deferred by combat
    local specRetryTimer = nil        -- retry handle for new characters

    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        ---------------------------------------------------------------
        --  PLAYER_REGEN_ENABLED: handle deferred spec switch
        ---------------------------------------------------------------
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingSpecSwitch then
                pendingSpecSwitch = false
                -- Re-resolve after combat ends (spec may have changed again)
                local targetProfile = ResolveSpecProfile()
                if targetProfile then
                    local current = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                    if current ~= targetProfile then
                        local fontWillChange = EllesmereUI.ProfileChangesFont(
                            EllesmereUIDB.profiles[targetProfile])
                        -- _specProfileSwitching disabled (see doSwitch comment)
                        EllesmereUI.SwitchProfile(targetProfile)
                        EllesmereUI.RefreshAllAddons()
                        if fontWillChange then
                            EllesmereUI:ShowConfirmPopup({
                                title       = "Reload Required",
                                message     = "Font changed. A UI reload is needed to apply the new font.",
                                confirmText = "Reload Now",
                                cancelText  = "Later",
                                onConfirm   = function() ReloadUI() end,
                            })
                        end
                    end
                end
            end
            return
        end

        ---------------------------------------------------------------
        --  Filter: only handle "player" for PLAYER_SPECIALIZATION_CHANGED
        ---------------------------------------------------------------
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end

        ---------------------------------------------------------------
        --  Resolve the current spec via live API
        ---------------------------------------------------------------
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0
            and GetSpecializationInfo(specIdx) or nil

        if not specID then
            -- Spec info not available yet (common on brand new characters).
            -- Start a short polling retry so we can assign the correct
            -- profile once the server sends spec data.
            if not specRetryTimer and (lastKnownSpecID == nil) then
                local attempts = 0
                specRetryTimer = C_Timer.NewTicker(1, function(ticker)
                    attempts = attempts + 1
                    local idx = GetSpecialization and GetSpecialization() or 0
                    local sid = idx and idx > 0
                        and GetSpecializationInfo(idx) or nil
                    if sid then
                        ticker:Cancel()
                        specRetryTimer = nil
                        -- Record the spec so future events use the fast path
                        lastKnownSpecID = sid
                        local ck = UnitName("player") .. " - " .. GetRealmName()
                        lastKnownCharKey = ck
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        if not EllesmereUIDB.lastSpecByChar then
                            EllesmereUIDB.lastSpecByChar = {}
                        end
                        EllesmereUIDB.lastSpecByChar[ck] = sid
                        EllesmereUI._profileSaveLocked = false
                        -- Resolve via the unified function
                        local target = ResolveSpecProfile()
                        if target then
                            local cur = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
                            if cur ~= target then
                                local fontChange = EllesmereUI.ProfileChangesFont(
                                    EllesmereUIDB.profiles[target])
                                -- _specProfileSwitching disabled (see doSwitch comment)
                                EllesmereUI.SwitchProfile(target)
                                EllesmereUI.RefreshAllAddons()
                                if fontChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = "Font changed. A UI reload is needed to apply the new font.",
                                        confirmText = "Reload Now",
                                        cancelText  = "Later",
                                        onConfirm   = function() ReloadUI() end,
                                    })
                                end
                            end
                        end
                    elseif attempts >= 10 then
                        ticker:Cancel()
                        specRetryTimer = nil
                    end
                end)
            end
            return
        end

        -- Spec resolved -- cancel any pending retry
        if specRetryTimer then
            specRetryTimer:Cancel()
            specRetryTimer = nil
        end

        local charKey = UnitName("player") .. " - " .. GetRealmName()
        local isFirstLogin = (lastKnownSpecID == nil)
        -- charChanged is true when the active character is different from the
        -- last session (alt-swap). On a plain /reload the charKey stays the same.
        local charChanged = (lastKnownCharKey ~= nil) and (lastKnownCharKey ~= charKey)

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), skip if same character
        -- and same spec -- a plain /reload should not override the user's
        -- active profile selection.
        if event == "PLAYER_ENTERING_WORLD" then
            if not isFirstLogin and not charChanged and specID == lastKnownSpecID then
                return -- same char, same spec, nothing to do
            end
        end
        lastKnownSpecID = specID
        lastKnownCharKey = charKey

        -- Persist the current spec so PreSeedSpecProfile can guarantee the
        -- correct profile is loaded on next login via ResolveSpecProfile().
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.lastSpecByChar then EllesmereUIDB.lastSpecByChar = {} end
        EllesmereUIDB.lastSpecByChar[charKey] = specID

        -- Spec resolved successfully -- unlock auto-save if it was locked
        -- during PreSeedSpecProfile when spec was unavailable.
        EllesmereUI._profileSaveLocked = false

        ---------------------------------------------------------------
        --  Defer entire switch during combat
        ---------------------------------------------------------------
        if InCombatLockdown() then
            pendingSpecSwitch = true
            return
        end

        ---------------------------------------------------------------
        --  Resolve target profile via the unified function
        ---------------------------------------------------------------
        local db = GetProfilesDB()
        local targetProfile = ResolveSpecProfile()
        if targetProfile then
            local current = db.activeProfile or "Default"
            if current ~= targetProfile then
                local function doSwitch()
                    -- _specProfileSwitching disabled: was causing width/height
                    -- matches to never re-apply because SPELLS_CHANGED fires
                    -- before PLAYER_SPECIALIZATION_CHANGED (CDM completes
                    -- before the flag is set, flag stuck true forever).
                    -- EllesmereUI._specProfileSwitching = true
                    local fontWillChange = EllesmereUI.ProfileChangesFont(db.profiles[targetProfile])
                    EllesmereUI.SwitchProfile(targetProfile)
                    EllesmereUI.RefreshAllAddons()
                    if not isFirstLogin and fontWillChange then
                        EllesmereUI:ShowConfirmPopup({
                            title       = "Reload Required",
                            message     = "Font changed. A UI reload is needed to apply the new font.",
                            confirmText = "Reload Now",
                            cancelText  = "Later",
                            onConfirm   = function() ReloadUI() end,
                        })
                    end
                end
                if isFirstLogin then
                    -- Defer two frames: one frame lets child addon OnEnable
                    -- callbacks run, a second frame lets any deferred
                    -- registrations inside OnEnable (e.g. SetupOptionsPanel)
                    -- complete before SwitchProfile tries to rebuild frames.
                    C_Timer.After(0, function()
                        C_Timer.After(0, doSwitch)
                    end)
                else
                    doSwitch()
                end
            elseif isFirstLogin or charChanged then
                -- activeProfile already matches the target. If the pre-seed
                -- already injected the correct data into each child SV, the
                -- addons built with the right values and no further action is
                -- needed. Only call SwitchProfile if the pre-seed did not run
                -- (e.g. first session after update, no lastSpecByChar entry).
                if not EllesmereUI._preSeedComplete then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(targetProfile)
                        end)
                    end)
                end
            end
        elseif charChanged then
            -- No spec assignment for this character and character changed
            -- (alt swap). If the current activeProfile is spec-assigned
            -- (left over from the previous character), switch to the last
            -- non-spec profile so this character doesn't inherit another
            -- character's spec layout. Skip on plain /reload (same char)
            -- to respect the user's intentional profile choice.
            local current = db.activeProfile or "Default"
            local currentIsSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == current then currentIsSpecAssigned = true; break end
                end
            end
            if currentIsSpecAssigned then
                -- Find the best fallback: lastNonSpecProfile, or any profile
                -- that isn't spec-assigned, or Default as last resort.
                local fallback = db.lastNonSpecProfile
                if not fallback or not db.profiles[fallback] then
                    -- Walk profileOrder to find first non-spec-assigned profile
                    local specAssignedSet = {}
                    if db.specProfiles then
                        for _, pName in pairs(db.specProfiles) do
                            specAssignedSet[pName] = true
                        end
                    end
                    for _, pName in ipairs(db.profileOrder or {}) do
                        if not specAssignedSet[pName] and db.profiles[pName] then
                            fallback = pName
                            break
                        end
                    end
                end
                fallback = fallback or "Default"
                if fallback ~= current and db.profiles[fallback] then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(fallback)
                        end)
                    end)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Popular Presets & Weekly Spotlight
--  Hardcoded profile strings that ship with the addon.
--  To add a new preset: add an entry to POPULAR_PRESETS with name, author,
--  description, tags, image, and the import/editMode string tables (keyed by
--  resolution p1080/p1440, then UI scale variant s64 = 0.64 / s53 = 0.53). The
--  variant closest to the user's UI scale is auto-selected on Import / Copy.
--  Canonical tag vocabulary (reuse these for consistency): Class Colored,
--  Dark Theme, All Roles, Healer, Tank, DPS, Performance, Fantasy, Thematic,
--  Minimal.
--  To update the weekly spotlight: change WEEKLY_SPOTLIGHT.
-------------------------------------------------------------------------------
EllesmereUI.POPULAR_PRESETS = {
    {
        name        = "EllesmereUI",
        author      = "Ellesmere",
        description = "The signature EllesmereUI layout exactly as designed. Vibrant class colors, clear cd tracking, and every module working in harmony.",
        tags        = { "Class Colored", "All Roles", "Performance", "EUI Architect" },
        image       = "Interface\\AddOns\\EllesmereUI\\media\\profiles\\ellesmereui.png",
        -- EUI profile import strings. The scale variant closest to the user's UI
        -- scale is auto-selected;
        import = {
            p1080 = {
                s64 = "",
                s53 = "",
            },
            p1440 = {
                s64 = "!EUI_S3xwZTnssd(xXVSrS7dslUVMN0HpumwwAKK7z6jMiCarcjI1qa8da02A6y(VV5rDIdsk1UVMwUJoKeirvzLvExzL5p9x7cYEOOph(LKSInLxViVQO25WOG)YFTloRBrBrr97QDdcCmEWFV2lmY5V8FW3U)X1fWpUBtvf(gFPOTRSPU2h(6bzlZPH21lBtDvZIp)(8hB20dpjolVEXQM2o(tVRzXMUtY76VnVfEsuwFE79f9DH8NGF)M7URRO)hRr4iiRRCzb81o(IBU5IZ1F8)a(yaQCDZE9vh)jCap2EatPp4YMVw0AoOheTFJkbnmSTdW0vpG(z3CXLMWyOeip50Z)0M(YQY(hnhox)m8tw00uTS5R1wl)dComX333XlXnmom0BBZtC8HHoW)CJ998IieJNaZoEniX5MOLTn4rX0a6lgWj28MAe3RDp)Sx)XZ(0X599vfxvGKikcIOS1v5pAV5zmMbzV)1V5gtC9bjcW0cJAHTJzILQ8Uoy2A20UOWI2yBybANucuMJAC255L1a1N1qfEyGBuuSBCOxQxASMgzcaN38ICD8dDdJ8WjYZLjmaAWMh(u0Nct8I(KBC6VeephefsuA(bjobjE(8cDmDZtCHgMD1zV9DwBrrhgb4eCAIsIdX5jn76Eq(qXaM3P289p0jeqNXjUEHfh4eUf2Udscomf(xukSEc8imQF2ABw5DqGnLiNdIyElySiAZjzf2kz7mcYWb1j7RLl7xDEE)IvOSYbIg6CNK6DiBPANBmyQOEhjiwl91wE6KZjl1Dvr59R6zGvGswLxdeRh3SPEz3p9FiIO8LlBQr2AGE(1vvfDpu0w8XZoArpO5a2ZjLcXzR30TQy5jeX(jnvnOMbxqVbYp6MDlQLYbvt5MDp87j(P0V3c)EAmrU6gM1TQ5Rhxv(V)3NTag67FdmNozRaGScb0Bk(w)M2IBavy1E4B7LbkGUSPReHeemcYa4XNM4hRpimbL1KK1wuDztzDpSwo51F4MxF1FfWvRh8e3SVXAJOXismgrPhcsaK)dLa8egoxNabtjYyYRr3S)2MInfadt)gcXHaQxI3HiRWtySpWZtdTEQvS)tCy0JrICm8tFIyTdCnxL86KqIHYHmaG1N0QJalLOkfAY95mmeOe)9y)8aFhqkpTncSXFRVnxWdSPVVPwcLUjhsB3I)90w4EHiLWizQevIBCYHXbPPojbbXE7KwuQJcjSpiW3ffBhf547KKeWAhUSqyVftecd)ZgUpaGigWj0DGIyc0q8u35r8BQqCYh7kin9KafuCGNwCWOpZjdSYe4RAZ7lUO(eH9y4BfMjTo71lVVy4l6cAriHxh30USO96Y)DrnjPkk7wTWOJQwdchjPzrwdh999oK(Kun4nCWa9nTnlEBvZxzR2PVV(HArMOOs)y0exwuzS43BHxHXnB6kiPK5TlpfmzhLbJRsx1mmAf6M19)SjVTaLR2bQZHLWdnWW0aoaCni09OQkyeabQsyKeYkwSgt319pwvGFZyluWZtEVuNXq56jzLay(pBAEOoKKlcsn7kQkw0dBrWA1Wggt1d)mu9eGksSvG4blWn19xy4hdSBDlXQFjOsSS(Ewjuq2xk7Eh4GZhAEDDXdpIyhxHLx)D0yaYhO0SBV)1153wvSe(cXz1BE4QMV2XOyqpgr5DCXQYA8ZHbGFYKiwjLHubkrveK95IhVfEDgIrxRivQll7Wz9gGBOVCnsNeNvWacshKKbE4DXDxLxFFbnzW6cbGi5W9MM6EtAtwD(9c16sAYKSva5e8UiIqVoH5hPWArSJ5cg8NS6R5p2HKEhtOuIOuHkphr9eMcgbf69gYto8H(zpKVOTbHnI7ZL2jIan9OdTev(fi6J)U33281tlBb6h0mbG5TagCWs)eCxG4iedqQIOgjj)rgtYisGwn)Ey9DulmyDxHMJGdo4oUeq2nsAWwe7Cmz1t(6cdXfOODyXGgdDPXKYydMU4MvLl(CDrxh6spq0i4iF428EeNASdausec(ACsGVDDtn4Vea4e59(T7gK9PU8VqmFgsbboKkakUzvBZM7xXIp4TvGiyzrn)e2fK3rwAkxWdi5iLfOupjTL83qJdzhc9iSbqL(zC)chz79Q)H5EvOjTRb9byWlqi(xz2eM0qHeSiJe8EMkEibEi61MapgyRn5rDy5v4QzsUuhX(hpDY9z12)(ZUdIIycb2MyWG2UMQYLehTb9KGqazUKecSmj)b2SrydEinEhTuECE2nfUHwfJrXJzsSeL6MbIAa(WCINe8BAf83)BGFoVIi(L6RhWI7tBHNJdhcr46ca782FOSR8wkYmGKwLMnAKmeazYRBjFxiT0cqfplcL)CrD1JNv3rE5IIqrj2exLGUEm2emPGyDj)QaPekLTRlkwIK6eDIsG37yPNcrkYVmZSnWRKPENF9umnXgWlAEErZdjA8xanpVOJbTx7pO6ySI(HpEedgUnSFkuSvtKGNxrFj4(ejzxju1WCNP01mR2KNUv2dv2ejS4Hujy4WGs5XyTpKHbpfnnJ9dzG2NX459t7Zek8n0ujT0BYOwn2sVP3oKwnnq0WCUlmTrwZR)CS4HPxauqjOiC9BR2ZNob3VpvU(uTl8f)9uhg6Fe83BxADrZUFXZo2dpWhvYd1Fd9SBMGSSf1EB33R9vV6qLHHz1y8xiFYg5M2(6VLTBQtycXSE0nNNA)2R)mm7FCjF4OteIKNKIZPvqgYN6yDGdrtUfJuMq9iB6IrKC4WcoD88g52(7U4QZ(Nx8HBo69BXp3iXjnw7o640Mn8CCuFEDnT7v0(9b99RTDhMNXYVTwE8hg)2FX0I9jE7)HnuY7Y0IxcAmDOFVyAHDqDn8Z(P7d1uhL3uMJmic5BXr9z8QF)IvmoUFNDqN8VLYcKxo2sXX78YXw(YXw(YXw(YXw(YXw(B(Xws5b4VTU)80nA4LaV(sI28REI2SlVJEjWRV4D0eb47xGaVor(b99pWRp30MzVp4sRui)3wnqVeaUxYLtDcK(BxUCUlvmVeaUxuXS9Zq6PBl9(gaUj0Wq3sSPYwMbNtiFpBnU0nU7vW4cg9EFNJmxu2vfR)(C4v)P6S)03ARFBvB)0j2)Vwhh5KtwCBmE5gA87QBOXU0Q)IJJ)UsRUTYRqX9aAYRk1VSza7ECFk0oxUNz4kDZg(UMGRec67SI55UcV)blZwtYoVCrBZVKwyyM(TB96FTF5D01w3aM5VDEtNdsJVA07J9bed2VixuZxCR)xa36vvDKxUHM75n0Cx6))9Tx98147)cVlMt4qlDnyM7oA(7Lm597x62SLBwPTrqE7Vh8JtO34Sp9awfBOIYXLLFROQtvHymVNMJNKVZwveLDC(9)zszSUCFSp6HFPGjSRcMWlP)6FQt)1x8t)3v(P)7f9XVCaVt5ekwE684I6bwe)WQZsDjyhawrjqgPqv1msEbH5QmNrrSd0wlkFD3MF)vfyLH5S6lQlGNJvuj)SY(IhQk(srfwsL012oUeiP(WbvPIerf25TnvlVPnFXNbqtyJ7M22I6fpsvNgQ2qKMbZ81Ws42CSA)uLVUtw4BWpyvZxVUPThRCf8scE4j593u2xvWfreQkIGfWO7pV5lfFO56vL3jQnnWZ(HYUn5v809Hp8t1EbPjoj)f8NEPbWpd9WQZwTBQFSBK4NP4ZDCdOp3blgP03dMk89IIcHFgfe6etFEqKh(3EX(4pdJDCXF6hNe4J)TBCk9CX4efheHJFuStmoF(WFcZpmEbEH)L)dbH(o43a(zSaYeqSpcH4ZtW3iinncHq8N4mG)u(CesdDDsjipjmgH4qx3iEfK6sRmxpxyfGRCA8fFp3qxFp(VDca4a)BALHWfJ58teJJN45e8aVFcIrI8HHKNpX6iIWGaMlKEEuAmbFrP03x(3agZNgxNuCEvF)OGicJcyUu8ZnhFED5GZhIjdX)o2pXhNh8N08KKcyw6NUiC6hcya4NEj0oQlSor8te(wc8FaVU8IL4h87HuiW6hXhs8GpTtcaeGpbclcmrcmIaIalCaJscdPfqsuicaXaOcdyqQta9NHb(0(uysa9ZuNeaEGDHqEFkmHG)apSgSw75MM6a)TVxQdmQUH(H0JdGxG2(HFcppWjog)yVGiAwGh7GutoPH0QpW1lbxnPU(e2d)jmQjU4LOt(d6TcGfb(FW7eghtuaIFc0HUW7gMgsWDueH3GLbmd433p2NOqdHngctbOAChXpXdxbW6l1d3PWVhH6aUacwH9y87dpNEp)OyIY1pbOPWr2nnWbPDrUgM7k11Lgr4Neng8tAMtDjApGOcXHUjjU4wHRFmdRaZxirJ4fXCZXWqJJBcHRXAVk(xor4op(tK3hMkpepatLRdoBGOcMIobO5ySfDJyVzvXRoQ9HM2hz2AbzLsaesEnKDxkysYws)Kz3i2)zjd3xXccYvP4bjz7qPedKlkLAqt)KYhhknriV85lvXwoRE5zYEnHuhH84Dj9zO865KgjLJlLkjLNlLMnu6KsoVHuqdPuOuSHY)nLAP0hiLEX6fEIsXinIhT8lG68nTfV6Y2I1)xHCiKTkHmyaRnCL11flpdmqbT2XZX45SLm3uUMSds9gcdCeVbwEljJjkUh4qXksBbMO2UzNa2pT5bSebI2gLI1pVnR)q(dfJXQKjjQpNnq6gakdZi((HVUPiH5EvWUQ3wK3(QxxVcl3wpalKNny46NH4NxDDr)RWb9zbpjz)9I81ao5v)FF1nTL1FUymaT7fgBRhwf7qiImP8SA08tCVZf3joLRuJlf7iLe2potuAW4s42FBtrx)R49CCeT2czR8WZEJjn4Vh(38gV8VNAbj3XWaXAHYgqqGM9oA7b)oGDUllE1BBAwcZOB2LTn3v0H9wa6pVQi)EecWfmmdNx2TOaS1TUOzd95gRl9swrT)byrF8JV(BRZRXrKRpLigR4U8nv9k71XIWaqr3uT5bznD0dRr0CvP8H19pQXTSN2fmr2sXgbZPOlpRm6vwOenS3okBzrF(IvI1f7Uadu4CDvE9YMhaZZz)eGNkywf(wi5xR)8ew(ZCY4WWlS)EEBTQQCk49jVkWYHiobeuJF)JwkjEWQqkmoi52hxFpU1Cw9YYf59nTiDdGvmCc68h7xvU4MYhaQhAvqvEYQnD381g6P8K0C7)pSeA(LIHLUjNd5A5nwSAnQQ3uzXagS1vL9xxH9Wb7ACBaxQeX3s8RIGJHUe1kQSEjS3nieDHC(ffWwAGFd443ObEqjkfgFrrBUGkqRnTlk6UCr)LnDaz)7p64xJfVaFGya(0Jj3WevVCSOusqabLGEk8xXQsPpxgO5Ysjv2xH3JL1AbQi6dbxRAUQlJGBl(szXxzkKEenlq5tvMfLGbn3I6nc9oOmeAIfJbWKu2cYqSwcuyxPLa)Burxxue8xwK3VQ7SAYJszr8S8(6JQQW9zabj6aaWUGIcOZOCzYRyIo542I8pJ9adECuF93MVMlOYoz31c6r4sqjyoj8mq2NXUcoLW(d4epv78V4JF4MpD5RVclB7kKlHMw1wuOOnrUryvG)TEHeM1PzKtymmHTEFXDuPKN9ihVDulZRAQlaYbsGlxEy)h1jrMT6aKmq(z)i4eI3HPUrrGb2XrG1)0XsNF3DLFZaZW8FhTahqMFedvbxKGjAW3NFBrfV5PO4jPCllwc2SZK(M0SabBA2h)WPV(QpD8rxrAeOPaNyUWuIeAm14h7k4Pgf2WCqFC9cqQu99xJCoC10LEPab(Bqn(ei1OtRIOCe)kr6WuGaUts8lqNWkuTNFsZdRZBloVzjw1z)WfF41WRKAqOJ7GdeimdFlStQ2KKLetQOEJZpopvf9flpVSQQSRyrt9sKJdNkvmsWIPn89hcCNwu1NJ12tejW7wNsSdI3FXN157quwBZxrczQWCZm(mrpZ)5N1dRi4Pvl1KaE(2ZjbOdQ03kmmlOrZHhWRaZ9raiPNTZkXkQsOvWMbo9ZbkZqKpAn36kWIpk6x(zRY7w9(Y6DpW46eita559urqgrfRkYR6x9HnpaYujAY(M14xGlm6e(kw0ZGqXs6kdlOgAzz36IkSQOdRtSOJlR07c1qVbRsSlRE8dxEcvJZ9YwWTjOpc6eb202nR7lbRMu1q4P0Qqky4y)vbm)iSzvWGr6)B3C3Dyu2maAF5Cj0fbECZlpbc4MM1azgXVH4tIdpFtB(PyfOhStb5k02maGE5dRBAbs5EmCLuLGNYfgs0yQagiAkvpTaKQ3aK33b41aafcMchgMDgUWVlFrX)cu4FrD3)YyJ9F9qXYY8)f9v)xGSeGKS7R5pE4n3WXZ8oj(eayKYxwKRpGArdQcxUWgiUEcHLVhChgP0fLByJ6iDBE5YZZB)SOW57rRgxg1DVGDLnlWnRgMvRYQnix2KAAN01av8qm8oFhbZkIZfHrfgLfyXDMASudlB8u53xZuYTSe5X2bk1U7UBa7Uo6EWRhfrhg5lPGsmunsgz3eU8vdSYmlXOAkoiQ)HsURaOPfW67Oj1ibdbzkcEWQZLylOIRA26PM6(hc17u)YbTkWe)YuJKAxNS)h0xIZBULqG6sOPx0y6uv5gNpv9itwGDI)NIWhL10vts8eIgU4lfTv5pkjyOLm2Sh6VT5Be14)aaCr5TcPTi(eR1JElLn1FYEqZuMcPqvKgrQcVFAZgqOIW6DyVywUsWGpKGe8EEXN3VsAQOjPHKJs5k86cmcOPh8FEK4j)mnpgAZkW00SUfL(sYUjbqNvdkcVnh7ZzIAPUpjTI0D7k(DD9uN6lacbVupDG3yJTxmwhWGGc2sWjqiiGeT8ECNdOUSO7SEjSYbw)53L3zZdfP3As0MP6WcUDYwSqlDEQPWIZkuk20gSWIwOGDancuxn8zTkOqCnffEMkQ9JrAfiGrBFjyTHyGpHSECNmfGQi5uoQftaKB7v1w3XytKVqzlyV4Ms9bSLiL9FjQ43cFXA6W1)UbCWiyLSZHLDFSDaa)VHgEzNWG4QSALlyrEhhiWZtP8u2hAZTiJTdz3mJgjbQNfudqVcIq(dWnCAJJmyx1ubz2cTNQsb7ohYTgptwI9blO07BRMFIw3boVorA2r5VJSJ4VZcQ1RHJTAPa6(NLJGVazPL)ongWZzFTL7WJCInWr7gRHDMUSJXreBpUoMIYH69fg6PiXfeubSzWw37BWsxVnZSRgphRzMt4gyZ4sL5qMboRXaJybrVilmWPYgbHvpvmqha4kP9WHpjdCRP8wyVxj)lnr3SX8cyf6iYk0vQsM8CQQ6uY0pYpOulT7wuXg2lOAleOBcarmfbc98gPdRrO2sapFETJUQIZhXNUBYmpLbRSeiHPIMSiw8GGCidzRg1fBNShY)MyPwtqihMh2lqURMWHeZCVMD6MBHhcf07gMnzhrhMWniSgMBAliybMTatRvHF2Nfss29SbKokMFdbYGNfR7(qrE7(txcsijdlOvRwufIdaN)q1TJ0mRf7J6tSePYECtddzMjhdnt1LVfW5GVMH8ytZIYWgRM4d7zk3Gye7iwkBSesoyienzgTD2GtldTaNxW2wbIsBxVUyPIU2GQwZljeCYeiKrSOWb0s)czJcCtjjDZKQAGdWEAzfsrtmVscHpahzrLTNvtUZY(ao2rkTqP4jmF1QxyYkccneiQdAzqihxSqLhXxw0IbrP2xy7PLvZAVoP(CMO1gAeNq3qs8Uh48MWXl8KBeXTMosfwN3q3YWT5aTBxSN8cpPBZBlEDvzp1MJyXcc7h1KVw2uyR5K2HaMFahwHDcOyYRmkyaml(6FO2LBfpWgGUh4iG)jejyzZoVPjewyjaAfE)M2hgAPp6dCwsZNl)ard0j)2UM2BpPQiVMbfEVc2dLUTA5aVPD2BXFmdxui(2jHQinYZAOS8C5hRD9qYJPiC3vGAzobw)OqYKrODNUzCPD6dLkTBmUrG8UuerqRv8GyLOKWS7r223UD)9t5WejOEgfSb25)RxNVWO7RzRhrBtpyCIoongIizBczCPLywxuLXq3suC1sxR5nKaJbXWjuD8vE3KKEyBocycKmmKvjOfY1F(dnduuPnxKdeSkeeORqAtoPpZv8ODIGtjW2k4ocE8Y7WthQeeOGMBze2jryEr3vjBwq(FqTNHBFwKhQ3ehhHgoPXB2nYeQHFP95t8ROjAWVI4yy3MySzDkGXGIwEiAnXQMU(sJO(5O1HWjehhh1HcZnIYHNsMRARILY6Yxhtogmdq0g2byYUJDErdlK1rlrif1Gq0czHnSsLjU(isLTWfdMaqHB0cT8fFt5Ss4nFTvjARdfHxqPzAo3Qj6yWIJf0gU2ie79wlHA8XxlJil4f5JfT8HBvxSPVnVsh8HTz(plU5dxEcDKtKvNYWfAlnCQ2bhb2y4fmTjDKGIyghkKuW07uBTDKDNwlqlfL7GzcbdFZqQFA(d53xCEb4ma1SKZw(aIpsZUvEQygXpnemhVFXkQVq2085hYB)C3pbo9agldwNxN(xaL98zSGQD2RWbyEQPGposkjXHBjpRmu5hAh5rY(pkz8Po)vrCoGK0h4c9IhXD)F0kMcWMHuQbDY8LGDURlwqIevg8sOo2qb8ls)P6ym4ZgexwdMvyauhZdnRMVcEy22F6of2rzdGkI1jz59Tnlk7FKCS8jCkVGABcjH7cJASQulO(nLvvg3mwAEn1sjr6VLlSZSNxVd1eiAlNiUYblTcYMyN(cy5dEoDLWDymQ(6yYjh1JPp10dl2y0OSvlPLV1ji5Hn9YBb)rOtzvElPeFZDJt5DzoBgUUO6o(KZyAkc0eWc9agUXvadJyMnizgyskUVCdcYA(kjg4RL1lXZ0BdAXnhrsa0ox2q8Og4hmLXIVy3pHSyGgXnTxZzBcrwdQ520E65upSfLeLKTw0KWf9LyWEmQEXe666hs2MHDjz3yFUfihh445lAsYCpsV2LIAEuwvZIptDovzpxWh7b(uEfPNto4fdMtzt(E2zsn062LaPkABZeh8JbZua3CbNBfnX8qOaR5Hf(mxpMmqZrSBsgqTHnNR15ck5ehCmNWUU80Ji1aUiDG2HhHzpcYwWmoHFU0xdP5HhjU6H0JSf1KIps4taBDLhkfRQ6DLD9y2QYeTm5Bmg5eSTdtHnXKnJWASSqMIv0RIXhOT0W4OyXmqMOxX8aaCehgvGyMeC)EIUc5MOBrpMnpNvFvEj9imVIypNKYF4Vior6R8G8m5yHUes2No4B7f3uAHeHhqDFcOuqIaIlWUdSS1xkZMjfSOYTbkreGrwIufhMibicZ1foRPwCNUP((cozUCji(c8l2)iRyIaGbiXbzlqQoaFHIGUHg95Lsb4tl1bVOgWWZOuJznW4XsmnnTMacomSyBqROCygHugwfdu9EDgXosbih3ODBHH1SlTeyOoijfOoPLM2TqWM4cq)D3QRax9LyzIpBGzxoHjjEGCX0ax2qc(qKg)yYyD7h)FOlLtKPHrYgX(551GbsyKsbxWw(aYsr)UUBulUmphJXJ9VVQO(S6CoHZyBsWCNu8e8RivgaMHP777MFb00srN9EQkqmhJLCHEOUs6Edj9vHy5owO3YUDDBBcLp2SHrP)I2nFhnQd6f3cZ155Ym2mMR(e5BDK8CkMVGAa86yWJsZKixCAjBro2QnJZcWLcYqZHaDIdGw2ECmPpjPyKb9DcM2dqsjHSWd5ZqapDfQ1KB2EKTTfbS1IwP30y6o(4(4TAf)wP1OdBv3yIF9AmrNMvxKyJIxIJpAb1uCfnfcPc8sXqqzGiIrZ2DTNUAYXwYj3dezbfoh4wifUUuvlR8cD)oMZ5QXTn(PQUwJ60lhqett1jJ40qYKitPcuqpQdvHcVCSWIjsuTvpc3On8JNXKa7bcd5)qG4f20YSNcZzzz64d0nBBtBGr7LgvqW)EYogNTPN6g0)AYmgN9r1KU3SIMq6ygXrDhlPILFTyj1sceH)Eglc)(WfQkpdXPjPPK1uBPH3)cl5VgSKZVb8evrcdeQx)7ihjfWGfFM0AzeG3DQ1mmJSWyknMd0ir5LlPYud9tPU0un7VySMdfgaszhifFNMZSNAj1C9S)Lk)jiNLS0HkKZBi4FSoraq)dHoXPlzSIGD98vnoVB07uh5EY8bE40G(PDvo4sL4WtOOKuV5HRA(AhPIFAZwPZBbpTDY4PUVwUUqE6e0jqmsr2alme(DpRD0wx8bXXbDvXdL1Y4fX5hmMCRaGi)e2OKPnMzlvzoJtJBWbGkToFWf1FSeeAEt1NQhhMk8w6aMY((x)g2kfT)gxuFYPKBgc7XFdUm(Re(Cqu)cZyNzOlAh61(GJ0yFno3sv73fHnYKZgpAiqw6sWOnTD7Zs9IjuM5EMXz9oAFGTd1ZZ(ngeYhJGiAsVkKzn0fBJAeNw8eh(oF)0OOi(clWSyNScpUaX1K0cQhqN8CnNFiYW6GfhqClC2zWtz)t0sEDpewdW)ID8tDtrMeB5U2jQdNDj0kdj(WCPNoGek8s)mnTpiBbH(SJHMiE)uIVY3qogBVznLZ5VfylqZ8T4)NTHbBlPAKvVQ9AbBgiP6DLlxwu)QtofuJpWivNSYU3IhqiFZm06WTCs3qRMQYJf6MgMgJrmM9QhMNp9P7XH6tlwsoTmTnN7Ry6zWK0XTiWISKVDl5gtyq622(POpfM4f9j340zeHB7sOsGTW9t91l1CRAGSloQ)271t6TYCDTXHYPEAYJNkbePitSfrXWE37lVROl)lL13pLIml5OAIethYm3yeCTtRPDI0MBpctc4CZ2ujaF84qMmToXjcMWip3SdTI(A9nkBmL79wNEZOiM4jcl)aXRZDs4I7nWZv(68w2om7u13IcZDpbv)wYdnrCoLjpaDoZtfhRPIrJ9WQtCOF2IEnxcIy5mxGFm)QOUKFMXybZWLPK6)SKvLiLvf)PWG4yqyvG)try1KsDT0Sm2m1H4dYCYHb6CBTk9jJK2S9u)zSK8zj5kjJVtsVctZ5UxbQXEL7qZjTd4YuYN)DOWlBTati0Y2eNbM8n6OMhBL4SoUshe2yJb3Q0Qb7Dkbl7NVSBnWvtigeboLva)xV4kT(wm3FydzWWdHNEeDTVwwCSiDVO6CrO4eJu3pb0ySjmbsC((hqj7tswBrfNHbrzYtsiiR)((hRdsIPlWDsSJRlDffcZwtFvLBEzFR(axh6oGl(h6rm9(FRg(GyqNOFGtqyGkDL5fIHuob84rhK)KWJCA1qiEW90v21WEvX48CgfrKRKyMqFHpsSNspdWszH03bKT2memBfCIped67mOyaJWjBeD88UoyBfnj7H81Rbl8OmbrPsGZXi04QM6JPcaSWS6flPRxN4mpeFHC82Dsf6Mk8WCml(d6uqtDN0OnBHJi(ouOeFfMj3V6)DX9zV60sWEZIxD5M21nDf)FWV5d4vGpk7OtU5SF41YPHV0DYuBai3FtBZdNC65VH4acZ6kQkwG3QDE5Hk05vDWF6w1Ezr)zCR2l25pDB1(zEr()PBvhK5ge)NTLnNGzTfDFUSMVAtuMadwDZrjftQumemzoJY02Rk6A20UOqLbj6l5zAwfLO6l(mEo1SmBUwD8EXZPtnbVSl1lEe)o0Tps9eWN3dt4RrpwxZYxwwu3BKh2GbM0XC3NxjRYdSUM7xS8ym2P5TpkJKNvI2giNtDysdZURSQIMXu0uehS6k6elc7U(M3qPfMotGuzhiDRFuqoNqVdc3gLuB23pvSCUXllC1Jr8kY3ln0p0JZ1h2jja9ZViFNanwDCMCQhfrIelo1Nv511fvi(h3n5vi8ghIfusSoQMgN67rbM1AqvBw69pkjyWnIiUMXWU)oiUuwdI6neRbekWctbrxHfofXFk3F4eL4hRpietKmDc)XP5U8YoyNzl61nUQCt98CDCcH)bOqMOrqAHxZlQygzp3YSTGXXaWX08ZEQ60sx4nW(fOgekC4SzeNFrudmEIA0uieo0w8TgAdWrktKqPJoefjxTDE7jNkjZPqltWNoLK1OhKSo1fOQJaZJtH)tKvFQjf3TWbwVJZ7lC5KsuOoKPKQBAWH4yjcjo81WlRjAPwXYx)WA8(vEDF(90TPtpGmPQIdHOdrUDMSuq46Q4hoTSfrDV7IRo7FEXhU5O3JJ1MAmDz5sdLB2JIrCc)k2ID8XICYH3l4zhP4J9ssCttsJd88cO0noo7(I6cXnPWUZFnaYMp52TNn5FbK5y5ZGUZh81IBQCWzUetIVTUdlza6YHnjIAWvlaSIxvqKaH5DunHLjYmk5kuUuNMbYn)8nRkEal5gdtgvlR65clHOeHjjuTLPrc9HVNC25n6HsSKYM4pJgufrHTugJ0XEytgv)ImJnLRV6BcGkEhAxiXt0bHVjcJ42K0iUphtepyJfkrGBTCKI6AU7UUcTSGTMU(BjTV90i1lxiUsSAuGic5BLS1K1tjErCBfuByw3Au1t51ITegruLb0cwlJKPPmFdb41mq3hjk9CtE9kKsy8ChkHXDRsggBEGqjnUjakYn(hUFluFpXNiTcq4kisio4oIPWaK5kgsqiFcJZw3w(ay2XVj8ZIsziFhP3kNmR9wNRVih63Foz3KScQa6D2DFOrANiPuyOG8dCd9OOn80JkZEjSGdLXoeqiPsznd)klUqsobe6n6CtDSkq5YLzaTuEUdtsMxucEd(KYNVmVTVmVsuh(gjpzkHoyvIr(6APf2cu2o7RX8)0eSm390YqGdzp5weSmYZc(EvmLMrvaX)LrIIuJH0MeXPE130xG5NpDTMmngEKbFdSh)ztpyENvyjfYmqxu9qmU0IM6jPOKYf9XTic0AZgepheBCPfWjWkvgtYAAwyCD(gB8tI4SXwIw5cwUPga0Ow2Nfkt85CJML9pofSSz(fEO8d5vBk66CYixKmDcCN2jbJW6Y1wx3gdBW03PUbgPq1rZY76FDfxRTnLCcUcCAZxRPeFyhQNv(bkkPYyAODxf4XGit4TTUr7ziDWmrYcXS8TK8KJLA7NoWtGNI8Bl73W2DH0FdHRU2KZEGiKn5TllZRr35ENOgzYx5zL5f(KTzZC7nvukK9(slb4v3u2aQ((ImGBeIrZXIIludKaP)MYVGrfr4WRucj(orUHrjrEXbHoPIAQmqSyCNegk3xbjIn2XfTjdUk2)DXvgkoc7geY8vsyxt7M6IURPAocNRssm7zTn13Trufv5A2aZSKIuZM3NmP4DrQboJpZ2zVqcoiY6G6ql84ztGPNmzlM8GNNx31uxQJHhu7aNI4KkAiVfVbIfLv64iK(kJsflwC2PD)uTl2wsMYphZ3tqEWJKHKLu6bIYDWaVLMKyzxB1MUBHYehlHflbMs6rwuKWnn1IK313cY1aHG7z4bLyAmIoCACOyyX2M2sBA(P2l8uAKSBluNSIQKIuoqG)Ixu26I2UYUE8te3s0ZZ)gNQhI6sPtwz96n9xuFtZAGgpKY7oz(Czy4RhDjIXbcdCczCkQJ9hAkxG)LOoVMGPEwvZT5vZlDreAZRl6XMFfkxszcjFWE6lmoNi385oV(roT4uvKl(2tYTYyrbP)yQG2J1MKB159hDhqGrH7wv0TXvE5ofxpKYLa)D(YItlQYFSMUhYktyOjHRLvxVOTPIQ81yvViVtv35KhPOxcLkNEjEGUAuS5tqk)bP(Hh6a)ljY3joKlw1jI7CBtvpi2RMV89YnjbFcwuK0RmDXDeSpEtFfSvtfZAZngEpw44BuMC1FDFBr999RQ5RvMNCCPkMS(YrDjwmGReTOJX0xm6bNa9PEZrnhRcdyZ(sEdifFnRsSa7zgxSoKug0D3IlqYwRvUXrWqkU7iON4ctSWfpgwjUwnDKqqTI8TMr2GGvSU33N)WArKAIY(FDw2)RZFfzORal)dtvUdWl6nE4)8jcWNgAG5Tj9V18EYS0BZ77Rkax8gMKPt1L69YwkQjZgLN9q1dTscySSFItUXvTgTqkFToWOOLzOmmR3B4WX(0HNHV66PWHic3r)NnnpiADBUY7t5u1RwCdaV9T0pB50cW6AlomIuw3as8K0xvIMVzzEcGqp)Y3)XR)0rF40pD1rNDkYKU2Q63)J1hGrejmX3lk0hOzqEqDPX)GGiWWx3Oyhh)iSTmjeHUH71eNKxT4I1uxsbqv3v221F1M6tBQXBYlMWhTaXXBkR46Myq27kABOy28dy1tjhVt4jzGaYhwl62ho6M5dEJ5b4)X(veXrizkontPmzsFt7dV6GxDuBr(Rc9WpWnZaUGhGvtRfRWsgoSXIv)gm0KGBMDm(fRNe5vL32M3l7eFeaFEE9M8QJwUK((Hy9tEtXpXx4zQdMil5D)Ap7Yv(dfTf)Mn3n1F(x75gSvG2Xx3cYN)1DYP4OVytBh1OqanNfFdEGZjN6LcCttzz)Kx43Pm60QVvmJBfZKh6EGfiyT2ybvA35JEcpB0tkBxqflRbjid4JDRrX6vnZuzQimlNkMEj8HOaIBrMgmC9rz4jiUPJRZEXzTy7TKqa1yrLbnyzmK4NTPRWQQAkXA(V5O438gILQVnVSIcK69lWspPj8QMvkZJ3xyvdDHzvI6S5obocc4T03q)J1czNX8KalHzDiQE8cuFIAGiiej9jg)qbT42QMMLvB6qZlTRcaQRZsW4wI(ekNSLThYI2hlr)FuFqOtYHXHooXb(jrOF36(zciTp6qSh3f6bIZ9sab6SvtMTjOsS7QUMGxSC7Y)(0KI4XZrhp0X9uLiXiK(tDX39YUTFGvorzBQPglwXsodUOIQLLPaNZaHrcEbscFF5TNEmAyKRZNoEZ9xNV4ZGrl8zprDk2287qRLjBEM6uRai5y4LW5MTCcvyHwSFwnA4cBvg1ixWMnpS(eTqdUeEIhebyPi7a39GoO(FaBrvSrF06HbxAMPUbrfyLJ0hGtW5Hmo3WFbGWTHRnFM2BaUK0SUO(8sWu6ZlQ3Cb8RlbRVpPclDUQUndOUcRonyVyPhdVdcire4tFIa1YGhTkfgS5N56TIuQsDDG8fGJavfIDZAIfCCDhk1LS723j0nMQVQpbR2bkpYIFmJe8fvaq8WEKyqcBFw9DnuCW6Y)sXsYikwufBFgyu7)ZM8wSQMILuk8I2jOrm2OffSGPYJFVSCcPW0SIoWd4Xc5TcoB426KbkaqEnGvJDhxubgDRpluXLxdJKhGBTUvyH0UaoQInbMMzWTGtKmS)t02jr6e4N9Pf5RXtQF5fGOE2xoYKv(aVXu3hbMlBlwaMy3ulF6i5xOXzcxjq6yYYkIgGqGsQozTwNRQudPgLLQBCXCol9McCPA5QQaXurps0nK5LmNCj4ZFB(du7CI1zjspAaFYqILOerrWgeWGZHnWnN6YKShKLqmfxlpv)BaXYm2CyPqGblgqNwE3DLlaoxsn6az70gmi5HDMaR3qSnGgcl)yDz)BWEDLq6aYQdk36LfZsP6uQc1iQB5XznGABUUkkkv3iJmxC(f1nPbLfhSMrtnCavjcueolps4cnJ4DxvxFhrl9)ArROSgRkBwIA6IzYVoLVhPQ6rOiXs0aNOoPjQq5cqwRWNnLMlVokGv44DQr5eZSQYGz4nS0LzA1Ul1yCf0w(9TRl22Ojv0MWSo3SaUy8sGxJu55uvgtZ303qYpjcuJzILlOxAWocLj54LcMw1dBsoIZZhH2Rk(c4PBbM9bagYddVcgLuMaaJ7Sj0XeJ8oOOK2HLMauQdbc655iWAhD5mcKUtVKiEQg9WkJ2IdmY8c2uoLhsjPjy4wMJS(ocM1O6(pcsjz7GsmtYCPtvbfP3veXeUwrt5A2E17jWWWzalCdlqcpiYtUJnbAdZu8Vr19boSgIs5ktkY7xHyq(wH1GvrTSuvNGfIHm2XvK)M7wImndrHIkMPzH0LRzWQvlJVe94at1n0sKdoROMgzu6(PYqiQRwroRyH1psaCdy2uK8gsmS42ecjgWDAMooIYU3qAeX2YpwFGa1oqMKGnprZHS15vD2hk8fFzMfllTOnkECEzElzTegBpcKIOEhtjdhnegD0gjTIyNIu9IDnevJMG2ho2OCWjB)qMmjIjcDxatQQtl7wdYVniLaRoPpXMnhLSziqsjVa0grQLmAtIUuBsCOKtbokauyD)kYXMDlDetrnyjz0Jfjk(1afVO3hWP9PUFaqHJ9w(0QYWlHa(tzVWYK5xLMHIcASIEMJTnX3HmOasEgPASOBdaqRAsjrAUeHuEXUy1KOWyqroH1n1)Gp3wacrnqLQyoWNyazrvMMsz5uBrXUpZPonqS9yfk8Het4FfUsjtuTUupr8DaVxvYxnYczgxjk8S2xyfSXXZBwY0FMQe2jruKzvciNrJNacPUlTkNEqoJj1cQkV(YcMiDRRe1gDLCo1sXs6NbJ4yH6QmqvBUHIptyl4GAw4UAVot1kj4(unvZeMl3PEgwKbMbYTg4ILsYjUSQHUlXKxaocSyV)wQ68Bjj00QnrT0DclUGxLEn0lxb2Lf0Hvju14XgCnRPvCjyEu9nFklBMX8ftLqknocFmohd6nbbEyJn0gFWb3xvLnLffvCzjA9QIQX3qRzmBvkZ00hyg5DzudyZD)Tmj1isS91MMjvNJHgygfbaxKCbkv9)eSizcjbSR8KiLbkxC4NAydrQEYTO4aZpy6q1gOwTKXrLakbgyw42U50ZPGEc9MtPPBsXnphfuFFvPy0fmTK390LQpJ4BsoDmwwQ9csJ9OSiJfKhfehMg5447g74XvKvQXpgge7gL6e7f4hWY3L9LCTWhMzJ2lPepEAr8IUOeLc2SlQr09wSTMCqT)wb9b4Rr)T0XyknAwNd2sXBkDLJD0e3f1M9yj6BKJKCf6w(pe0FQEdI3Rc0IouihxQLb98t7s3wCEBlQNe9LLbCFZ7Fg3Mb1DMxhRa8Yg2pYnnyviLByz9k80JV3QMjduf93QClu3f82QlCm32y3vMGuYUNyrIoisblFWeDTP93PoSdjixG2Jer4XTWMbgip0)mW0ocCmK4PbpBvS4UZCHIzOZyeKrlrLRhYhyz)Y0(PiAphJuXAQ(MhgKtxjjwz3lxVJXSJfZxJb(yz7UJQ2GOcbHjVLEzWJnzf4uQKrlKFsEuSTsBNyVZarnJRqc3sg5P1qhprNhmS859IGIR7nGw94oYr5u1MTYHqlrcY(cLiEiSSHzCiCcFUNUAqn1bC8m8vAApANnUECqP4GhEe13C01WTzdl24Cpa0RmvC)M1HkLHS2SU2(tjUKBgBEQQqLLtbIYex8mKNwE6mjuAhCtbxXC(8XXzMRY(Ca8M19yqg1aEClY658SzsVoOzAIlYdEgyA76vBECY2CDtfEWh7kayyX5wklDKqtI9zyXEF((HSkS7prxTMpYg0HMZnUNNGdxCyJhvSS)JSFwIWGmRt4t5e2KX36xyxW2Pe39ZBlraZNu20ZW9RGXwgkd3JvlSv7T4(5Qg1VNx9ZokYYHbmxDuWBM3LTiWD8CWE7ZQxInIn8Ejlc(7V8UYnYpjL1oBvHO9PfOGxZqxMiRILuLSefz)IZD)xRZDGZl75PikmTbpstXPgoILgSrDadHrkK8hdhb9WM3Mfp9KDx793DrFRs30)v5UODt(fTg7z4v48EJSB)fh6(1m(xPI(HP)vwMOrhp7Z2bZP9zu27BK(cIvLBHJPA7qh6U0iFFyBdLbow75PrWqbXZgN1ivGrg435mXcEMJ27j55jZvRcCGHf2tECNJ9VCw3CMZdtVNVNgJ0xRoMJPoUVTe3lSbqAeKklps5q)i3Xu(m9eoYVX(HnN3qpvpu5C3btWbLunvt6FMtFBxzYYexJFSW6oDESSnV1M2P0TC4Jt6340HXEsF3gyGP(0cZBN(wo8uZ8brsrPDwDloKURd5BCwIOTuEgNqrZ2Sp8IT5P5o9sDhh(9VkUPIoEyPCML3qTDv76rckiv0DWq3w9fUWINXeO26NrDHbvvqXR57Wq5jGkT71IIvdxnj1L3sDDMCIKZew7amXUN)mFFD6SbdGxIStug5pSqAoUG5mnabcSiKK6QHP6ULh4t)6(oqMDg5hRpWxuTjFc5OQO(5yHJpWtbp(JQHi7lOH5PpkMNcIMAHkkWxpTIneyfoDK2)SjeWKdfhOFUeNCUZlo4JHNxrtxN8kes3ZGXq)EMGJkDp7Ttidpy9r55005Q40AfgbLImCZ(8nhFEppXOTBN4FYJEBMCdAlNP140mEI0Htn8tPoxKX4dZcTX5rZSwgkpQI5ZFTTQMyqEgYnXxhDIKoBw2mml3EYPfN6cJBNtJ7kxwN37KrepQ7J6mzyZmhKYZnITtKNGit7yvkVWlQs(THET)cVyv)kz1A4fEr9Lw4jE6jZYlckq))3ExBn12wBH)f1ZO7Ys9jNGtGPCBas7PpXiabOgBzFSLlH2P)3pRB7B6ITjKMwMX9LseyzP9ETx3xFFu)D5ap1XuPJLMejM91IiLx46u1wmUo1Z4R91xwLwrLPn(2t)RbFjoo52URRmXk9c6QnKggMDtrt7SL3xtTT5ITmCsh(NPR32AjxsYhOZ36R59FD952lVqlqOs2b0OsMHnWROG)WE6f(onp336kY0Bs96Vf6gOEmyIC0oQpz2IMNnhilK(JMAnl9Xs(NiIjxgU8)(lOZgOiVwD9U2S1UumhgV8(2vcNrwRL6KiHaccocgVQM3BOE1JqnwhfhCZUjT)2xtlAJa8G7D0mlhVXA0peAoWMNvlGlnnxln4Sg7VpDfiOE280yzk1(SMNqndyNsQ(z88g(Z8C5r4TJ((C1CAW8W2PytfzcIzv)rOCdHnEjMct3TBTGBM05VGr6)w7vXUYWKkicpcWjUUZuoGff3Mh27zOZETvQAtrQf0s8b7A9JQPo1JhU6oD8yhR7Qzmvs5VEwa21gJ0EReKPntwsVTlPmnjMwV7RT)jBjPyH6XBCUA62gBVIEX0XESaeAHDG62xC6O7RBuA3bMdvbV2LlthgTvdNpCRF2URTgCah6PMFCAS39wGAGC9)cQ)YWDH6ads0RR8H7CYV2CPy6R8I6Xo1EGO25AmUXb)YUpX1JKvR6oo0aD9nOWJo(052JZ2MFu5PundKCRjBvLsXjckhUSBfAVRgQaKdmkXdvfM(lZeSeG23KHFtBCdRG(GvwSNQ9nqsL6TTxhykRBPNDhhkWnugrtlTAprpBQjh3qBW(kQ27lVyJTMOWb7a2Hiu2bNL8bMCSofOdC7X4)sxtp6U8vijfvIT6Kf8xrHghOb4yVm5UbuKAXSjVHYsU1ckous5BvIpDdbpud7)1nCHBQuI6YPTp3P7ZDQfwdOnnSVogDMn(V51XGDcMNRD017EgR3b7m3oa0qV5ZSBhnkyN5wGkH(s7YMtyPBffhrJK)MgrTbmRpYntDcwaZ3opzi5mGGK1u8ZOuu7UedEegiTK2JoQe41qTGuFzWCJtLXMm2pmsd0xZ(SXq86fYC63xNwNMJWbl6LGkjdLav7BZlA29BppYwDN(UNRNTA)TNG4hYH9(JfVpFcySUvHWEkSuI7VeEG44J16P4NUi33dCMfSAecE4p5FP(pHmot8l7qoqOlalMefKBSqGqC58BRAEMZDbpVvipn3ch)AHjxX51Z5rX1GStDr7lo04EbJEBgsOlNi0LZK44lr8hJaNkhK8dFEri54IYzv1io7YOK6TZRxTEgIZBoVmiU7LxsyBtqEX6hqyK7Aep3jKhRzvZYQpZ)mJ(K4IFqoHRXX5pHOOhRZOQ(ZpF9ntly4Pl)j8pGxox8y1T0nOE9SBqWKKECklw284uKpvXleNF)0Iv4hfNX5I7MIdf5O8NGxG7xVe)hiWzpx(UkMTyA19pZF0r5lRAkVU4UFtelMwmRSzE9dRXhBmbcWVDvrn(m4hL)uzXI51xxwF7J8ld4c8YQfWneUBC3SGVkVdFtqCzJzRHaHdUxuEBvX0vNIj5IXIt8rc1VSS8(YLllV7xO7)e(2l0v21RxvENfQwIQHbPt1h5dWlM7Fj6UmSfi4ndbeoj5ZEUbwjPNqZhfx1S)Scanxmf2gncaCIsBCUQIVV(bI9ItZVJb3guEG7i5pHcpk02chJUAAQlhreP7vpVGj4208VWakLWGFZrmdV5z539S87ciyGqwfDUXhSU(HY511s7qHO6UjtrSGpcr5Oi2KVaV3Rw9ubE6mjFPs(2c7uaTcOQKlBww0uaRzNm5GJ(0j9Z(VHP0GHsZGFQ8Zc63yJsRoNAbbxcapvaJo5hqGGvSJjquLLc7W0tU8mYpyOpOTGSpudl2MOmc9ANKVxAFUbNlGDuc5Eyy(e3XTfRjuWtupt6ikQG3SW8vFMNx5BGpWA88tC(JZyQoejd5MN4F7Y51)bE(dp2UK0c7G8TSfHZAEeupDs1QvYHVyqdeRS15VU7thPpX80bpwe8nIOrYVp)A8MGBdGwAeXOF66NkFEjCELHOASvDUx()ek1JjDS4U5pbpPegqcwsQMvc6jxHh)z1g3GO42YpFnFOxU5tRw1usq)6kep5X)uWxQNbTCZBiDEKZw3R(qmysh6G35RHhqc2evq0()R1v2YuiBGIL(Q3VfnaWU(HyC34BVTCbIcsGAlZ)(8LL)oOZ4K1tB4n6BEG46bcI30O8pd4BinUIi9WHup2k4I2TZrGTRP8oDZXPVcEJcIjVpZOVYRwVeuGEjsmnx(5Qf8rgY448fiRlyl8rYtKTEP1ScHTNMPLgIlq4Ac9xhsYfHresjnaCEI0sR5Hh5Gu4gIFmMBtKlGaQFM1)UnXUC481OGl8WkpGeBVQzhfcp(5fmiKKB(TsI6BBX3c8wcVEWywzVezN8fqK6fSq2frkr9ZgePu8bxqhekBLGVwRRirzeempE9Qg2vfCTh2EN5ARrxSjWmfcrbhIChr5075hrqMUfyNY)9ikh2IH19drSojZZplXJX2esDRfD14Xn5c1yle)14fMf4hNKrfupc)Y43JTpG4i1BnF9Itb)mu8wkz2HRQW7MwwE3QXRqwicrXn606IcLUCkNz4iJOWWmW0NcuwbTRAK6QDTSdI5LOXW(4fLRQ(JsDFRqaCQ6wk3oDXgb1mlNpLy5b2GhrCU2zvZzngbEQ7TG)dgPvOnpCmnOfhXrbRnp0OE5u1BmOmg2Hy1KeYywSOM(wzVBoaCHPEfiJkC1Cx4Iu)YSJ7iWkVSEcwg)8knyziaKP69Vftl8isFhwiBdP4amZuwmLX(GwYyCNrHYvsZAtyTJcvOjaBc)MDwoHti4MgDKrbBMslkJlNo)TmPjp5lW6DnZOhGpbGvnA5ok)IZoEI(beuJENQnOtfU4W69XI4Xa)OmcRTwbCxy0OZdiSsig666gWCfPVaDxMGW0dQwIkyaN8nZaaSOrYggQCDtLMe9IfxtePf0Gqv5tgYXnEed(CFPojGgKcDwWzKuK1Kq3cuvbsj3mQ7k5P1MQtSrot8vqDM7swoH(ywlBwE41BRSKkFTWQdcHUcEkWkp6CUZnhluRfJ6bC2cangZMpV5rKeYLLz6KKLujjTap701jjssbJScRLfBjwcYe4khtkufnw3pHTt5WxBl9JaETOROf(n1dOsZ(YxofvT48w1tJZiSBeQKsTs5i7ZAgoMhMg4(XDgU5iIcSZWR4GiV8EA33dMcAaljiVHGB0GNE0snvznC9MDUIJn3CUvYUe44ytrZAsvslBqmrrJ0IZ8LhC(LmYsaVw4LS0LRQw3dhaETIo4P5XhbMTlFeI6KFp31jEo1sgVLwBHN4jYwquKzEd2oQEcI70Ej(smMivjARYcbZzxPVC9SzZRpVS(ojcBEJdDlazjDkrkO2BJ065ZRwnVwlUgmkjomjZlXl1ZOqn1lnklllmmiXps3SBAlZ4wS2MeTEHd7ivYFENfx61YI0jPrwcNwGCS6Z4bX6u1OXK5do7xoLuRmuTBAtfVSDGUu0l7Gr7RZehq7tlAasaF8v6tybcjnOwTPB)ONkQLQJWVJxzwwcaLHwh63UmbhoeSgPC1rurzFa4QIAI955dsSztx7sUz1JCcdbXsZziWb5PSCJ4HZHZxw9hqS4femW7briOpcr5qqShGRyku3jKDNDAj90U6pVc(pfLBimMGSxhNFXrF8qrHak5c67GdYY7bAUML5PViLzMogHT0W1Bo9usF0ImizwwSczofw6ijbe1ZgLfMeefs(frctHJcdYIt8d9J5rsJXNpVSK4mF8KXi)mWPFuws1LyAqwUThzX5nZjsk7iK2gUPGSqM5S)7GeSwUiy3kQOh0YdYqO3lhnf9DHlQjAdiMZRTWezf9GPnDpcclGj1ryjIlsWLpvTqO)Iwuzql(oD31Dco2YoAB8mMJf0OZg0LrEiJUnA4owboALpDlRwoxvdE5Yv36rml4eNjrA9mIocBGvLYkozqRoVC5fG7y4ridZHYauMgEKzNJGTtlh1IYpEYhOCo64gXjfpuDRwOmmcbkXO0G0aFbDirHYO04iVrXXHXPEzSSkIKZCw1v6TOdDmChZ2CiRiF4NytJK9bWW(ZV)XsfPIWwTLv(w2xT8stjfekkeDHiySPsMo1jUkvehS)DT82DrHRdS2QceGEwhDJUxEHtngWE048lVMsX85e7JlE0c)wmS7EcxlJoNWuMh4B)vJbZpj5hoz8XtUa2Dpy8jJ)4KlWLzkmyh(4nG9OVvaL0YmRmZOrTR)w62wCb73nP5aeN4GvzLWKhsge)uvDq0J73BTI)dsD(wu0x8IrSVYFQg7RiJ39Pm3)TZJJ6pe5XT8UDGzM(TUSajMUil34mWXnFvmsPkkIfwcDOwMZ5SX7xVuuyJQGzU)3Mb9(pjHCOjIjlk(oP8NIN(TZL6l(fhJdIpNjNiKKblMafpoT0uQtxIgMcTdk25ugeyP292(28un4ptVERGZFC88QWx0a9R52y13LG1p7Z3BvnOZ(NeTBTce7TWcEsXmbzBuCC6y93(xqlmMWoSqqPlfkz74fuX69C9Txkr8sMNmfZtvnJsM9nv7tsgUOW3vO)pN5r1Z9Ztlj1Xk)8yXzmKJLGzpKhcITItA7VDIow(WVesIq4gTBt1imbzPJIcPeMP99ONlJEQ06Y4ZCpPtqdAjTdzsakuFRtN7yocOHrwflObKzu9OWoMwiS4TDs8c46MjVp7YABBwxrsGN5Y2MzqAFFj7ZnS8Xo7AcXS)JA3mZKjpUgQNFXrtU8QRp8SJ)1)KrlcyPvBq7)wZAEXkiE3oUuaA4FQg5ZpkYoM2X1dnNR7cgZIGPpHWt7egCO57M3EK071n)BUovzyKSO8MNj2qf9THSZro(Psmtl)V4yruvjuLVuW8M1d423mzxp13LoRS)kZN0qaL7UULG8Q7Qz66hdGEksR2Hz)iYNZjctRQ9Qln)QZoNDCqQWNR)cUU1HUE0z9x39l2)kXL2)67USIYnOEFu1YxAX09Ik3vJfd2iQKMgbM5RJ8tcPm25ecaiSOcwLdb4BR0cNA1ZhF84do609kBUTQw4i5)LRSXNRvOwBtCsMV3pwh455bM0RHy1scb9pbrGOfbO)wcvV90aTbvlBXqMw5eycQN6c1NjmxRoFLMUWAmd2ez3ciAEw67HxR5R(uc0Y3a2cgztYh)jJyc6Y3iFqUaKoccavoHbX6qREb27gsdvhBRVwJzC4vNC2P)01NC0Lx9ltg)ZtUyV7qs9G(xT7qii9APGcI5a0zHAKs4PP9nTcPDvRZEVNrsrCkXT5dY)BKMkmSEBXfK4FbfuGgl)22VgHEq)3TtrPQaWo4OlF)rNF8rNozVEN3c6DWeuBjiLffokAFKywr6VpsmU4fKAhMnf1UrNIwOaNNbFM)NlESS8j)8z)0KlUE8N(4jto9QXxD0zNUx5ZBbLpunBT8323ZddTpmXBuaiBfMKfftz0FV3p7vdzPgY3nJqr(HzOvRiFVamoE4)NmkbKFYI9JB7983f3H06Ko)Ijxo5IFEVoP3oPkY1JOWeIJhRdtddss3RlcRSYEDr26IC9jkmjXpgcflmjfeDG)FCCweejFyAs6Or41dLCi99oV1JYV8WXNm(0RbvsxD2f7vj9MrLe2C3gVKYsjmgDVlr7vdzRgI5mgvOzj(bzGwOaV0ippmXqrrzTlT63fpHsZp4IpD0b7v60P)i)3EjZCKNcb7xV9lm2(8qxGD1h36v29hZxDxC4wWmSbT)X6uWavn4euAkedF0OOqWTNiiwSWV)kGW8wPg0nNwNvpZkMEMYP1xX(2J6DtCu(Sh0GmPVA)WY5ZigQEYDpGdfRV7Ocyndb(5Zkx(G0M9CdvQAYs3PLZaP4zXbGtJ(PjrPEX8ODr9wgnDP(oqkXhwwvwFhJBe3R)z)DNHKf4Aur2vm6r0unT8JcSbiJjd1Vsz8m23AqN0Z7nn3M4Nv1ox8m2YtBYfLpaYE4KkHFhky6G)wgA4ArGVGMNzgQvTN(z5otyTg9BpTygnEKUaaIzoRXNFNzxVdzCO(Ki4Dynz1m(UltQk1JV61O3Xp9CxXdcqtRO5yV)HB2ZmoO40ctONBqO9GFt7Fhv)7vnL0GJy9jWrGooHEs2iIYBn15b5RxvIJuEDZvf3iRD0OpZS3dUrXVQ2Fr0Ksd66jbv4g4YI7r53xqDg87kQRlxU6d0KZt4SaoMX82ew)EK0FQBq5YeevkUPyAhCIWpF(6gCftgfdEu)juvOCDf)GdF(r6NcACU5Vi9WrbrBLmkjiLMpzDZzoki0CeINddAiJWZtJu)Ya440F9x))d",
                s53 = "!EUI_S3xwZTnssd(xXVSrS7d2lUVMN0Hpumww6tsUNPNyIWbejKiwbcWpaqBRPJV)7BEuN4Gu029XmTChDijqWQYkR8UYkZF5V2fKTUOph(LKSITLxViVQO25vH(Y)9x(RDXzDlAlkQFxTBqGJXd(B1EHro)L)hCu6FCtb8J72wvHFJpx02v2ux7dVEq2YCAkC9Y2wx1S4H3N)yZ2E4jXz51lw102HFQB2RV64pDsEx)X5TWdIY6ZBVVOVlL(GlB(srl(vAU7UUI(FU(Lr0G3vUSaE3JV4MBU4C9N)3Rjidg17AwSTJhkZrnK)aZr0vpG(z3CXLMJwipCEcGA84jbxZb05vPPPXHHjHPb(XH7y4J9FvOJJBIVRtyquQa0p50Z)02(YQY(hnbDx)m8tw00uTS5l1wRHxg9kxh)q3WiVWIx6SR5mneNg)Sn2iMOSnv5pAJRXT9DGQFzuebX(cSdUjER9M4KONNYgOF2R)4zF648((QIRkqkffHXEG0GS3)63CJ5M4lteGPf6Zc1gZuHv5DDWS1STDrHfr3UOrisejqzoQXzNNxwdK120VVkaipIsds8c8Ct1iJjaCc)65Y77a5CZ6pf9PWeVOp5gN(KPnCFLd8ViKaXZnjzh0JVmjGxmJj0NBXa0V(Eob(bHXomFpXAgMD1zV9DwBdXiy4655aVORhrfMMDDpilOyaR)K7WitvQFsAuqQdqLVZvbVH7X86tqwoHuG9qRZYbaUgIjzsk9dM)bgtCqDY(s5Y(vNN3VyfkrCaBEN7KeNgIhN5nSfTo3lnyjPiKhH)GTuHOZHm8k6fwY7QIY7x1ZlhbsBvEnq7ECZ26LD)cUOJYYxUSPg5RbY7xxvv0TUOT4JND0IEqdcqpqkhIZ2STBvXYtiA)tAQAqveUG(dKH0n7wqRvKta973d)EIpYp5M1c)EASpTNfM1TQ5lhxv(V(xNTag67FdmNozRaGScb0Bk(A)22IBavz1E432ldeIDztxjcjiyeKbWJpnXpc6FsjczhGf2Zlej5tYAlQUSPSUhwxN86pCZRV6VcyRndEIB2xRFPdXee6fMeNW0XKIuycIetqSNMspjaxBhW4d8vMSzcfk)xBl2waCA9BjSkUk8IJqvpo(oHUXHOmHdywEPNFG13wUg8uiPqsOJRJhiQl5hhskrob(Pid7HaZUKWucvhkhLaVdCuiXakrHkKPRhVAJsCH92ddWeMsbGvSy8adboSLMVtmTtdck(AFBUGhABFFtTeejfnha6YdwgJeqtuoa5cT3ZeX7DyLA1iQ)GWuI3XjoYlf4vjjbxwim9JzVCykNax3a)dKUKzUS0Wq73bkQgYASdanierNkKd9XUcYgbssekhXtlhz0N5Kb6bbEU28(IlQpry2g(TcZKgX96L3xm8l6cQ)iPEh30USO96Y)vrnjIlk7wTuSJQ2asvjXGrwdh9(EVI(Kun4nCWa5(TnlEBvZxyZ)P3x)qTSwugRFmA1nlJnw87TWxbj6sZ22vqIxZBxEkyZpk8gxLUQzy0k0nR7)EBEBbkqUdmsawcRBGHPb8G4AqA9rvvWiasILWijDwSynMUR7FSQaFZyluW3MIcPYMHkesYkbW8F00SUgO8r8aa(fvfl6HTiyTAyzKPELVdDwbOgiBnpEWcCBD)fcVGqXwWU1Tep(LGU0Y67zTxbzFUS7DGjyFO511fRFeXoUc75(BODgGhsOHx3E)RRZVTQyj8cXz1BxFvZx6yumOaKO8oUyvzn(5WaWpzseRKYqQ5LOkcYEO4XBHVodXOFzKU4LLD4SEdWn0xUbPtIZkyabPdsYaxeV4URYRVVGMmyDHaqKC4EttDVjTjBhW9c7bK0KjzRaYj47Iic96eMFKcRfXoMlyWH0QVK)yhs6DmHsjIsfQ8Ce1tykyeuO3BiNlXh6NToFrBdcBe3NlTtebMfGEetu5xGOp(DVVT5lNw2c0pO9faZBbm4Gpcj4UaXrigGufrnss(ZmMKrKaTA(9W67OwyW6UcTJbhCWVEjGSFK0GTOFwUf1TkFtHH4IyEXGwrDPXKYydMU4MvLlEOUORdJjaq0i4ixFBEpItn2bakjcbFnojWBx3udEAbaorE)02DdY(ux(NjMpdPGahsfaf3SQTz79RyXh82kqeSSOMFc7yZ7ituLl4bKCKYcuQNK2s(BOvLsplqSbqL(aUFHJS9E1F3CVk0K21G(aSugie)RmBctAOqcwKrcEptfpKape9AtGhdS1M8OoS8kC1mjxQJy)JNo5(SA7)PZUdIIycb2yAW63UMQYLehTb9KGqGL4BWkAs1lhkJ3vlDhh)9tzBOnXyu8yMdlrOUzGigG)lN4fbxXwb)9)c4JZRiyuQNEaRTpT1DooCieHRhaSZB)PYUYBPa3asyvA0ybOezplbMSQhignePleqAbJINfHICUOU6XZQ7iVLrPMOqAAefKY0qcgoqmOKBxGSaLk1nfflrcAIAqjw7DSmsHGd5lZSuARsj)sM678BN6Njq3pRF5z9lKaWFf0V8u0KmKDpsORHuk(ScLFhuOmLi2dvXHT6Ge8an6lb3JiDbkXPgMZmLoLz1AC4wr)0vrmwzkPXFoDhJndAkhm(E0XOWwgMOnu1ohVWbrNASvBtJ6LwanqaWCM(pTbtZRLCSqadfQY1KmGsuyP(9vh5HtC9htvOhkl7Z(UrhlQW96)W772(0TIMs)SxAS3AG)MuSu(D0lTzcyYouXTB)PEQ6qhAEvywnglfYpRrUE99OLKIuZathcFvIkti8XZUyw1OJJj3qvMJgRNMpAt4e80QFcZ(7xYNE6eH74GuCoTcYq(WjRdCKHC0YlxdZENa(yNCnIkdhIVPJn3ixXF3fxD2)4IpCZrVFhEZgjoUXA30x5gP(hfZQ5c1gF2WVUM29kA)XG((T2UdZZn5zlpebr77k4WpB5Xtj06)BBuJ3NLhphFy689(JILhtfFyHrUtEgo7lsUpvlp(EI5RH2WPCN22mdFA180TD5jeeyAi)bBGbDa6uED88rq(JqlZZhbj5zdN7a)BRYKNpcsoNlE(iifzEWWmq45JG8h4rqs5R3Zo58Jq9ZZo58NANCEo8Q)HYjN)mgEv)FGHxD8y9d27NiW7N7)XeGW9FaK7mz22rchmBM(mFUgoDuyP0X(QIn)AUG)p0aktUjtjW)VV2P8FGPkfNFAI0U95uX9puPI7(cQ6Z2B8hk7nSJazOifHMjjx)HKmuZFqUhEcR80Jv6OSHIs815sgQXNI7H6L0Gt9LqS)GTezUl31)MLUujzNxUOT5xtlmmZPR)iysL9LC(jzFaXy(8n5zhzlWHYH(7zAIPUl8pFdFEI3WN9zwXFSpRw(6G8NO7YJTzfE0TBzMqB8J6yA3H7W)yZqSVV8)IXfZDMY)GnrW6EP)7RBOhUXDpNnYpFts)n)MK(u0Z88n95pAxD0PUPp)kRU5qYkOPVjnJVRNtKHtu1RzQ7a6uPe)p(7f6t8o7ORPgpRK55ZK95YvGOOuD7mPcY(uY8Cms)dvmsF(mz)(C55x5ZKLliI4DaclcFyjqPUCnx(gqgPqvjdsElD5AaNrjM7487ffxUBZV)QcS8RCw9f1fWZXYwKFwzFX6QIpxuH1TiDLNJRZqQpCqjHirugBEBt1YBAZx8aaAIabSTTTOEXJujGHkndPzWmFnSeUnhlPov5B6Kvxg8dw18LRBA7XIIbVKGhEsE)nL9vf8fRMkvhyvc6(ZB(CXhAUEv5DIcad8SFQSBBEfpDF4d)sTxqAItYFb)PxAa8ZqpSWNv7M6h7gj(zk(Ch3a6ZD88GNJVhmv43lkke(zuqOtm95brE4F7f7J)mm2Xf)PFCsGp(3UXP0ZfJtumwCtH3p2jgNpF4pH5hgVaSa4rqOVd(gWpJfqMaI9rieFEc(ncstJqie)jod4pLphH0qxNucYtcJrio01nIxbPU0kZ1Zfwb4kNgFX75g667X)Ttaah4FtRmeUymNFIyC8epNGh47NGyKiFyi55tSoIimiG5cPNhLgtWxuk9(Y)gWy(046KIZR69JcIimkG5sXp3C851LdoFiMme)7y)eFCEWFsZtskGzPF6IWPFiGbGF6Lq7OUW6eXpr43sG)d41LxSe)GVhsHaRFeFiXd(0ojaqa(eiSiWejWicicSWbmkjmKwajrHiaedGkmGbPob0Fgg4t7tHjb0ptDsa4b2fc59PWec(d88sr8LBAQd83(EPoWO6g6hspoa(c02p8t45boXX4h7ferZc8yhKAYjnKw9bUEj4Qj11NWE4pHrnXfVDBYFqFRayrG)h8DcJJjkaXpb6qx47gMgsWDueH3GLbmd477h7tuOHWgdHPaunUJ4N4HRay9L6H7u47rOoGlGGvypgFF4503ZpkMOC9taAkCKDtdCqAxKRH5UsDDPre(jrJb)KM5uxI2diQqCOBscwtcbCBmdRaZxirJ4fXCZXWqJJBcHRXktl(xor4op(tK3hRRHiEaMkxhC2arfmfDcqZXyl6QQEZQIxCu76M2hz2AbzLsaesEnKDxkysYws)Kz3i2)zjdFQIfeKRsXdsY2Hsjgixuk1GM(jLpouAIqE53UufB5S6LNj71esDeYJ3N0NHYRNtAKuoUuQKuEUuA2qPtk58gsbnKsHsXgk)3uQLsFGu6fRx4aLIrAepA5Nb15BBlEXLTfB(pc5qiBvczWawa2kRRlwEgyGcATJNJXZzlzUPCdzhK6BimWr8nWAijzmrX9ahkwsyl4IW(jG9tBxJ1Hp02OuSi1TDZhYxxmgRsMKO(C2aPB4Yp6BlYBFXRRxHvPQ1a08npwHzKmKHGIP4Lzbd)me)8IRl6FbcpFtJrs2FRiFdGtEX)3xCtBz9dfJxl7hyyB9WsfhcrKjLNvJMFI7DU4oXPC5qCPyhPKW(XzIkZfUrs1hLU(xW754iATfYw5HbnIjn43d)BEJx(3tTG6eyz80QSqzdiiMCNfFhWo3LfV4TnnlHz0n7Y2M7k6Woaa9NxvKFpcb4cgMHZl7wua26wx0SL(CJ1LEjRO2)aSOp(Xx)1n514iYfbseJvCx(2QEL96y1raOOBQ2UwgjcpScoZL(X1B6FuJBzpTly6ZLIncMtrxduz0RSAeAyVDu2YI(8fReRl2DbgOW56Q86LnRbZZz)eGNkywf(wi5xRFycl)zozCy4f2FlVTwv6lf8(KxfynheNacQX3)OLsIhSuFcJdsU9Xn3JBnNvVSCrEFtls3ayfdNGo)X(vLlUPCnq9qRcQ8owTT7MV0qpLNKMB))H1PYpxmSW758kUsBJvewJAUnDRUGbBtvz)1vyVBWUqYgW1Jq8Bj(vXvbdDjQvul7WQ(lilhHOlKZVOkXsd8Bah)gnWdQdOW4lkjYfuvqTPDrr3Ll6VSPdi7F)rh)ASQc4dedWNEm5gMkmoyvEucLGEk8xXs)OpvRUbcieWOARk89yzTwGkI(qW1QWM6Yi42Ipxw8fMcPhrZcu(u10qjyqZTOqGqFhugcnXIXayskBbziwlbQWwqiA(3OsIUOi2VSiVFv3z1KhLYkLz591hvvH7Z6I3pSlOOa6mQjL8kMOtoUTi)bSFuWJJ61FB(gUQf7KDxlOhHR8HG5KWZazFg7k4uc7pGt8uTV)Ip(HB(0LV(kSqQRqUeAAvBrHI2e5gHvb(36fsywNMroHXWe269f3rf6D2JCSmkUmVQPUaihibUCny9VdUkKGv6y5d(zWZdxSCSNedE0MYDOJ0S87UR8RgOdMP7Of4OWmHy8j4YVlr49(8BlQ4DmfzojABzXsWqDME3KqfOstZ(4ho91x9PJp6ksnanf4eZ1)rK6Ijb)yxbp1OegMT5JBwaIIQV)AKDHRtT0xkqG0gufnb6lkMpe5I4xj6fMSdqyskEboewHQn6tAwVjVT48MLy9C9dx8HxdFLudQBCBBGuGzywHTp1oJSmusLlBC(X5PQOVy55LvvLDflAQxISz4uPcmcU5bV)qG70IQ(CSeAIibE36uIhq89x8GorXIYAB(cs9sL8AMBNP0zMo)SEyfbpTAPMeWZ3EojaDqn0wHHzPlA26aEfyUpcaj9S9wRtr9aTcElWtFo6ygY5rt42ubM5rH8YpBvE3Q3xwV)bgxNazcieVNkVWiQyvrEv)QpSDniiLOj7B2GVaxYXj8vSONBGYI01Evq3ZYYUnfvy9ghwNy58wwd1f6EEdwhwxw94hU8eQ6H7LTG7jqFeuec8MTB30xcMkPQoVtPkH0QWb8Rc44ryZQu8I0)3U9U7WqRza0(Y5sOacCZMxEceWnnBaYmIFdXNehE(228tXA7oyCcYvOnuaa9Y1BAAbs5EmgLunwNQaRK8Wubmq0uQ2mbikVbiVVdWRbakemDomm7mCHFx(II)jOL)I6U)PXg7)CDXYY8)j9Q)tqwcqs29L8hF1n3WbX8oj(eayKYxw(OFj1YduLeCHHpC19blMo4omsPlkKVgvO528YLNN3(GOK0ZP2IlJ6UxWUY2c4MvdZQvbRgegBsnTx6AGkEigEVFhbZkIZfXofgLfyztM6Iudli7uHTxZuYDre5nth0KD3D3agBD09GRokIomCxsbLy8zKmYyB1HVq7cwIrvRBqu)6sUE7RPfW8g2KAKGHGmfbpyQ5sShqX1JA9udMIiN5uQpnGMcyIFzQrsxRt2)n6aX5n3siqDXR0lAmDQQqEZft(itwG9I)NIWhL10vts8eIgU4ZfTv5pkjyeLc5vL9328vIAe1clk2uiTfXNyTE0BPS99t2wyMY(hfQI0is1o9tB2ccveMSd7fZYvcw5HeKGlZlE4PvfQf9lhKCukxHxxGran9GtZJep5NP5XqdvbMMMnTO0xs2nja6SAqr4T5ytntuLY9jPvKUBxXVRRu5uf3xi4L6wc8gBS9IX6ufeuWwcobcbbKOL3J7Ca1LfDN1xctAH6hExENnpuKERjrBBQdl42jBXcT05PMcloRqPytBWclHGc2b0YpDDMN1QGcX1uu4bPO2pgPvGagTrLG1gIb(eYKX9YuaQIKt5OM3aqU9KQN5ogBICz3Fb762uQpGTePS)lrf)w4lwthU(3pGdgbRKDoSG2JfAF4)n0Wl7XeexLvtsbt)rCGa3nLYtzhNn3Im2oKDFmAKeOEwqna9kic5paFVPnoYGDvheKzl0UNkfS78kUl5yYs8uWck9(2Q5NOPyGZRtKMDu(7i7i(7SGA9A4yRI1VULw5i4lqwA5VtJb8C2bB5o8ipxdC0(UAyNPl7nCeX2JRJPOCOUkHHEksCbbvaBgS19(gSCXBZmt9virJHrZmNWL3LXfUYHmdCjUhmIfe9ISWaNkBee22UWOBaGRK2J7RsGBnL3c79k5FPj6()LxaRqhrwHUsvYKNtvvNsM(r(bLAPD3Ik2WEbvdxaDtaiIPWoON3iDSmc1wc45ZRD0)uC(i(09tM5PmyLLajmv0KfXIheKdziB1OIu7KTo)RILAT4AprUWO15rXsXZAVM90MRk0cf07hMnzhrhMWniSduyAliybMTatRvHF2dcjj7F2ashfZVHazWZInDFOiV9PtxcsijdlOvRwuf3vki1TJ0mRf7J6tSePYECtddzMjh4mt1LVfKJb(AgYJnnlkdBSApoSNPCRxrSJyPSXsi5GHqucG12zdoTm0cCEbBBfikTDZMILk6AdQAnVKqWjtGqgXIchql9lK9UVTLK0ntjidCa2tlRqkAI5vsi8b4ilQS9mUjzW(ao2rkTqP4jmF1Q3vYkcOMBNO9aQJuzqihmSqLhXxw0IbrPMRlB(2wnR96K6GyIHZi4GUHK4DpW5nHJx4X1icwnDokSoVHULHBZbA3Uyp5fEs3M3w86QYEQbcXIfe2pQjFTSPWwZjTdfbIrX4Mq7nOxzuWayw8n)uTl3KBGnaD3Lra)tisWYMDEttiSWsa0k86x(uyOL(OpWzjnFU8deTMM8B7AAV9KQI8Agu49kypu62QLd8M2zVd)XmCrH4BNeQI0ipRHcBaCkpx(5ASVMonH7(IolZjW6hfsMmIN70T5kTtFOuP9JXncK3LIicATIheReLeM9pY2(2T)3pLdtKG6zuWgyN)VEt(cJ(AMTEeTn9GXj640yiIKTjKXLwIzDrvgdDlrXvlDTwwH60dIHtO64R8Ujj9WgjeWeizyiRsqlKRF4dnduuPnxKdeSkeeORqAtoffQA(r7fbNsRDRG7i4XlVdpsOsqGcAULryNeH5fDxLSzb5)b1EgU9zrEO(M44i0WjnEZUnurTslTpFIFfnrd(vKOh2TjgBwNcymOOzcIwtSQPRV0iQFoADiCwWXXrDOWCJOC4PK5Q2QyPSU89FNJbZaeTHDaMS7ypn0WczD0sesrnieTqwyRGuzIRpIuzlCXGjau4gnPkFXBkNvcV5RTkrBDOi8ckntZ5wnrhdwCSG2W1gHyV3AjuJpZAzezbViFSOLprR6IT9T5v6GpSlZ)zXnF4YtOZzIS6ugUqBPHt1O1iWgdVGPnPJeueZ4qHKcMEN6mSJS70AbAPOCpmtiy4Bgs9tZxNFFX5fGZau)loB5AeFKMDR8OWmIFAiyoE)IvuhxSP5H15Tp09lGtpGXYG151P)fqzpFglOANNiVT(Oszdcmp3e5bKHk)q7ips2zpjJpTtAvajPpWf6lEe3y(rRykaBgsPwFjZxc25UPybzUIYGxc1XgkGVi9NQJXGpqqCznywHbqDmp0SA(vWtW2(t3RWokfaurSojlVVTzrz)JKJLhWr7c2BsijCxyullL6k0VPSQYOKcqZRPwkjs)TCDuMpv93HAcen8sex5G1YgzBItxYG9bpNUs4omgvFDm5KJ6X0NA6HfBmAu2QL0Y36eK8W2j5TG)i0rRkBT1I3C)4uExMtHHRlQUJp5mMMIanbSqpGHBCfWWiModsMbMKIBp2GGSMVqIb(sz9s8m92IwCZrKeaTZLnHoQHactzS4f7(fKfd0iUT9AoftiYAqn322tpN6oSCNiEJOVDl64VUES1)FT2Znu0B75(tETlDkprzvnlEGA(OYktfMtO)puwdPhCokfdgCm5sNBWPGd8ehCoWgdg8GaUT9RBq3tVkOJcyYjcwUSKL5AnJbAY99tpa6eSzlTo0pjB2GZWe2sLhnejJ3f3K1EZiSPrqtc2OjCILEnKGgEKOjispslhbjzsXhjm4NnDYdfrvv9UYUEm)tzksM2mgdlc2TEPyIyYdrwSZc6yYrrl(fFG2mcJZzvSTZhYp4LnmQaLkLalVNOL4lYlkKgEHZQVkVKEeMPqSBrsHl8lItK(smipWnwIkHK9Pt12EXnLkgHV)QBiaLureqCb2uDLTpsz(jPGfvIlqzzamYsKQ4KcjarylUWtm1I70T13xWPNLlbXxGVy)JSwhcagGehKkaP6O3fkIOgArNxkf9oTif8QxadpJsnM1aJhlX000Aci4WWYKbvEYHzeszy5Yt16Yze7iTBCqH2V5dwZUun)qfmskqDAinTpFGbVfGY5Uvxb(XlXYeF2aBQCcts88d9sdCD1HaXD8JjlXTF8)dk5WlY0Qhz)l)88AW6hmmOG)vlxJSu0VRBIZIRNZXyWw)BRkQpRoNtHmc7tzdP4j4RiL0d2yPBx6MVaA3OOHypv51tCdzMPneNi79UhtOk7gDTTjs(4RIc9fnQ9oYuNbDXAH545KonZyVyIaut6rIZHG48pwOBeyWXWbLMjXO4env3JHm4MLDZ0UuYdH66gaLSD2ygCscW4KuzyxMgtNQxJzsKFMj0leVor91Z2QdWQkAnFtJPJ3t2lSNtDdzb1XgTDCH05xrhzHahXsRhFYbkC6vInYoHaPxI7RgcldMT2jn99LMTrtUxiYVjeYWnpkqCPQ2a5f6EfmlWJcSo3kZHhiewXRNX12(xkIpUHftOobUXQB1CNDLKDwhsjVbOo4gPZ2cB0T6N2gTSE8uJe2Mburw4AMQsHzFllnHxvwTLA7oBS0Kv0gPrvZkoEMZaQw8b7NxmoBl47pzi)pkoXrTPzT93c(Y4SpQM0ruSsEcPnfs(rti9jWnkvSyXamnTW3gx4G9uWlzb3Ii22ZWIEy8GwK7gCGY6)ZSTg(F4mItvP0MQIHoQDtqSKZj8DAjLtWBoqjZ3ld5i5kJyjnvlmlx489M)dKnegiuv(pqMqkaalEG0wziIB(kTIG3mmJmQGS0FGUKru8swtn0pMX0MD(xnUXHAJbvfdiz2RiZdwTi7tPYfcY)iB9td1EjIwHPMqHoT9Rj83zgWPRSNF38HZ758qDKJyiNN5tLHSy85bgGLGMwTjvXg9oCXHJqrbPE76RA(shRH24SOmnbvAalDYk45Qt2r19LYnfYZHGoRboYouISXxZLrgfkCdpiBXkm6RA3UzBO1M6lxmxvSUSwgyiorGXSyfGd5NiT)20E2DOmEkZnNTg8mwCccN2SZyM)2L3JjSBXf1NCk5uHWq83Ga6FLryJeSmqy5t1cCBvPP6tpKdhgEfGaa49V(nCwhmHvG2A(DdZyVOO7ShgUaRdkzEbiZh)hmrXm3Imod3ruySBcEE2FJbr7Xi4GmHc)aHSRHUKyuvm1IPsEf35vtJII4lIaZQDcrikUZJwq9Gda)B1y(HidRdmCaTSWq5bpDOJjUVI7gPXo(PUPipHT8x7eWHZAeALHuIyoYth8bfzjc)8nBG)Otcyc))aS82nuoK)wG3aTPWInF2Q48qJ4nTZuWFbYGEx5YLf1V4Ktrv3ZshaVyz3BXd8JVPfZ4URHwnhzJ6n0nnmngJamleegQp9P7XH6tlwswinTnNprBKaXCnye0UkV(ErUtq3Ke64tesrFQbyataq6kZ(POpfM4f9j340zeuB7PUqO8u5Oh5dS5g2uKmA0PP3kZe4HDiAge1mLAHzlYLO(Mbw7jkFjQOhW3uksPXCsPHD03xEhic)ZL13pLC6Dib0CBI5sT25uSZc4rF5Bpylc3Nu6qzBm4dnk27jS7ci(hglHrT)GP0qokFlh6VQj75ip2gjPDUd7wKb5w5kQ6on80cDY8cbgNxIMBFtYeyf4tC3nBy3yBYyEnHJ62mx6edYsB(HeCflcnwj6GZiCK1y7qC1tlWk)qLwLiLwf)PWG4yqCvG)HiUAIqOyy(4mIsM2c1jcY50bMAUGCEGgqoz6qtIA3LCQKm(Eg9cm1L7EbOk7fUZhJbBZe)Mfunr28(dWMYPKwn0Q6rYWTfCnGpF0Hip2orDSQg4clDkyJnh8xrHu7WjUjJASfZ(3MKQPKQpvKSMtq13RTI7vEL2kcmxEydzWWdrh1mMmKllowK(wuXQiuCirQWwJgJnHjqIZR)LugnKK1wuXzmquM8GlcY6VV)X6i(czN6NKgfqP(Fy2g6vvUtL916x667rhFUBiwHIqldPV)xRD9Itngaz(hZRedHCcaYJssSjbi58Qbr8e6P7GRXPijgNVLrre6kjQjItiGixh)q3qKB4qal876655aUJGjPkaKkZa14(xfkXyjP85Q8TSrO8SdXhYnI4a)KieONBFaGiofJOZT31bB6NjzRZ3SbS4JY)dLfUCMfH(d3uF82(Er2GqhijMLBICdr8c54D6KQPnv4b9ywNh0jEM6MOr5DMW1fFhkGJVaZF7x8)U4(SxCAjy)zXlUCB7MMUI)p4BUgV47rzhDYnN9tVwon8vTtMZdatXBABwFYPN)gIpjmRROQybEx25Lh3oKXvDWFcx1EXo)PBv7Lf9NrcCVi))0TvhK5ge)NTLnN5zTfDpuwZxOjk)FbhX4OyIPskgOMmNr5x7vfDnBBxuOsTe9v7mnRIsp9fpGNLnlZMRqhVx8C6SvWR4s9IhX3HUZrQNCf(T4lppwcZYxwwu3BK91GXN0j63NxjRTdSUM7xS8ymy95TpkJZNv61giNtDqudZURSQIMX0u3OiqZDuOtmfcESKqN31rkJO8ftNIqynyGYprk1EvqoNgVdckhLTB23kvSYTXllC1JXflY3ln0p0Jtci2Pxa9ZFr(MaAS6483upkI0hwyV7Q866Ike)J7M8ke(gVcRDKyjtnno13JcBR1GQ2S07FuQXWPUivLEM03yRbr9neRbekWYrbrxHLlfXFk3F4OC(Z1VmensuNjGCYTlVId2rzxVUXvLBQNNRJti8pafYencsl8YDr1Ti75MdcipdxVbaoMMF2JBNw6cpf2tWBmYeohonhX5xK(ogprnAkechFl(UcTf4iLzyOmsnefjxJDE7jNkjZPaptWNorK1OhKSo1fOQJcdCtH)tKUFQjf3TWbwVJZ7lCLJsuEoKzCRxG4I(VGziE96n4nP86(87P7nNEqyYtfxbr7HC4mPOGy1vXdCAzlsB8UlU6S)XfF4MJEpowBRXu(LR8tUzpkgXjm0Dhg4hlsXfg)ZZosLh7LK4MMKgh4Hlk6MxWxoTPswgoKNJddkFNzhEX91vIAsKXGW6dMvRklrGW1oQCSYB6gf(ekrNtZa5ypCZQI1yHVyywJAzLnxEhevNljHJTmgsim8EYzN3egkbrkRG)mAqvBy2retja0DuJIw)fzgnkPC15JVk2e8bVi(N4mphfa1DX5tIkNmyTgluI4ZA5if90C3DDfAEZDM087i)S90i1lxiUyQAuGkDTA0zL2qIDt2cf7U4odO2WSU7MQNYRfBoErnHbqLyffsMpXCE6ZRzqCBKOQVn5LCqXX7g8ku6H4iYq09o5AhRU2mF7gTFluN(kqL7akbPwzHRziH4GBQLcdqMpyWDt(OfNDFrDH4kqnQzMzkOz(BLITWd5FbOoSU3qZXM2Y1GPg)UiZquPc5Bd9oLwWrZ2iCU)QiTWnjRGkvEND3hAK2gskfgki)LUHCSH4)H0Hhses4a38Kenf)k(sdiF5jfhj5jyDe)glCss8cSv7q(GEfWS7wQr3Jbj7mXcumrxM32xMxjQ9EJKEnLioSYWivMOLnzl(A3clmesFyIXM7UzziEJSMujgJf2nYxc(kwmLUxv4X)1rMLuNK0IesMfEhV7lWu1NUvtMM)oYeVbNo13mnG51xHLtip7rZSGw6vdRHenUJ4b5I74oeaATb78kNGyJ7VaobwzTtswtZcJRT3yZRsehP9s0UwYyuXaGMXYEPq5BiNX0S2fZJUqUogO4hTg(NYR2w015KnYTV9AjgqnUPCJ1nVXWkp9DNBGzqu9YS8U(xxX1GBt5MGX)N28LAawMKjBSDCW7jQxYy6ODxf4JGiV4TTFs7liDmnJ(ws(WXYS9zp0pm7VffGw2dwBAwpq2W282LL51OxAVtuWl57VSYkfFYeVzUkMkYbYKE0asw6TDElCoM8CKP4Q3N1dmE1RzlrzcQbsGzFt5NXGDi8Jvk6d)orUHrjrEXbHoPIlvaqryCnegAWNcseUcnUcmzW6WULlUIqXry)CqM4bcZJA3wx0Dnvar4eusIzpRTP(UTIsIkxagyoIuKK18(JjLBtJ4SUcBNOcj4GilyWS8wCgey3zsIIjSkfV(4s0PTIOPC7Y(Syh5pfNfrd1mXBAyvvLcMJ0TxuCxXIZoT7xQDXMjYuUiz(9eKe8iziYiLEGOEfmWrRjjq232RjhokSBSOtSgwkrASmgHhEQfjVtVdKRbcb3ZWZ8W0YcDKX4OQWYJnnd30QsTZ1P8fA1QzoDYkQuisjsa(lErzBkA7k76XprCtqpp)RCUCikSKozL1B22Fr9nn492jKsWozcCzypRhD5GXbcJbczZjQ88NAkxG)LOqTMG5AwvZT5vZlrreLYRl6XwwfklszpigUmmZ)KPcpFS3CEmU5rw8MQKAX3qsUdhlkJ8htLHES4ICRorDP75bmkCpMIUXTYlWP4kGuUe4PZxwCArv(J1U44QSnHMeUyuD9I2MkQ0vJLTI8ovHJtEOH(8Xs66eLG9iMdtw(lDDd4AmDI420s3LQlQ57mVCRrWDG1Yi96HRjJC9lcmYDBFfSftvHAZneEVv4RCuMCvFDFBr999RQ5RlMNCKPsDS(UDDjwfFRenuJX0vmAbNa9XBZb(glFcyR5sE7gfVMvTrGD0IRYgskc6kAXv2yRvl3Mhyif3ve0rCffw4XgdRe3QM(XiGKezBnJUbbQyvQVpF9grWDIY(FDw2)RZFbz5Qap)ttvNcWlXnEk)Cq95d0mW8MI(F18EYoZBZ77Rkap2y42ObOkIrP1ZerY0lBPOOkBuF1dvp0kBFX62jcegxNA00N8n6yCA5E6WHHNs8S6v3dfoQs4o6)OPzTOrRDWnZARRJOmhvP8AMzS0becpn8vLO9ywMIai0ZV89F86pD0ho9txD0zNImNBguR6Fzqc4hkW7fN454sHbvx36FPNBc9HU((HyxDti6Cl3ziojVAXfBOEAcS1CxzBx)vBRpTPgVLUyMD0cehVPSIl4HbzVROTHcZZpHL9KC8(ENKbcgxVr0BoC0TEh82WdW)J9RiIJqY2AAMszYK(M21V4LV4O2I8xe6HFGBMbCbpaldwlwH16BydflBny0mbFf7ypeWcbrEv5TyY8txTE49ra(886T5vhTCj9(HyjCBBXVWxMzQFJiRvD)wp7Yv(6I2IF3M7M6h(TEUbBeOD8nTG85FBNCk07l222rT1dqJzXxHh4CYPEPa3K2(pTv8tztOvdLyMacpzGobUQYASIzSGQ(6eVJWYc(mJWd18KY2fuTTscE(V5O43aFEugEiEB74cCNciO6ncwFBW2qJOMLKtfcVePAm8qN0hOzCwl2gkPLEnwhyqtugbzGYPTDfwfctnWsms9T5LvuexVFbwPiLW7BO)zaVECuKeDHJ9aVAOlmRsuAm3lWzHjzDp25TnIENoB)NAzkpumqeeIQ(eJLOOqCBvtZYQTDOzL2xVF19vjqDdeus3NqPKTS9qw0(Ks0d9dEvycFbysPcL2es0bX5PjbOz1SHtMD1NsSzOUHaySq5Y)(0OdSkOshP0X9uzgX4yaM6mP8YUTFGzorzBRP(awXsolSOYHLLTaNZaHrsAbIcFF5TNEmAzKRZNoE79xNV4bWQf(8QOg7AB(DOzYKrptDsxaKCm8LW5MnDc1yHMQFwnA5cBwg1cw(kq5cRprZVGl(M4HxaMkYEUDpOeQ)NWokfB1hTEyWLMzQpoubM5in()eCEiRYnCuaOFB4QQNPbkGVinBkQpVeSH(8I6Txa)6sWS7tQWIERQpXa6RWspd2fv6Xa2WeWi4tFIa1YGhTkfwS5N56TI0Qs9lG8fGhavfIDtUccpQQcfsxePdiAlGn9S7R4jbjrveA9S67AOqy1L)5ILK5scHvKfyG5R)3BZBXcpkw1NWBTMGyWyhvuNSMkdx9YYPvptCkAsoGpjK)i4SXf(JjQafawQbSlS74IkW86r3dnm3laKO1f8kKq34OkW2mXXGl0Mi)w)hOvsIZ(3p7tlY3GhR(Ylar9gbJIpPA8YYGaZLTflaJPBQLpDSmlSofYonGeSKnu0MnHaLKxYYHo5VgMocwKDYQPnUyoNLytPAIA5QksWuPls0LI5LmNji4ZFB(AQnlX6PexOoaFYqILmdrDQgKKGZHnWntS1abwRLv5lf7jpv)laXYCWCWMqGblPpNwE3DLlawu6ocnqkoTbdIyyQeqFPWApdPIFSUS)nypOsiga5PbfA9Y6nPuFkvNzeLw84SgqTnx6dfvtBKJLRF(IQF0GIBdEdOOEcGQk(jcyLhjfHMr8AFQlbJOn9FPOvu5Hvf)kXLb1mtvXDBSdpq)SvgNCzTes47Kg4ev4mrrexaYAf8SrZCberbScNStnkkywfLeUCQktlQ9xWW4ICT89TlD12Ojv8KWej38(NB8La)cPkOPQsJMVTVHeuseOgZelxqV0GDek5WXl7lTQh2hBeh2pcTxv8zWN2cm1eamKhgafm2Nmbagn5b3oEGyK3bfvDoyV9wuQdbc655iW6MADPT3L)sIOKA0MPm6CnWiZlyt5uEiLKMGH7QnYsWiqxOAqpkhS5CprmtbuG8eKFQ9DrSr4Y5mLyypP2dbgOndyH7Pas4brEYDSjqByAD)vQuoWbWquTvzqI3VcXW4TcltQIYnPQu(kedzSJRi)n3TePfgIcff1sZADliw2C1Y4lrBiWuDdTe5WVkQlrgvxFQ)6GkLvKZkwy9JufyjlMnfjVHedlUTH7sYSNIQWSufEtu88gsJi2w(56xkqTdKjjyZt0Ci7CEvNOHcFXxCrv4AKI2OiV5L5TK1syS9iqkIssmL5A0qy00zK0kIDks1l2ypu9ccAF4yJI6MSdbzYKiMi05eKQ)0YUnG8BdsjW8s6tSzZXRJIHajL8cqBePwYO9f6sTVWHsof4OaqH19Rihz2V0rm3YGLKrVpKO43au8I2taNJM6s2pfW1B5dyA0fC0K5xLtGIAoSIEMJEnX3HmOasEgPASOBdaqRAsjrAUSwuEdTy1KOWyqroH1n1)Gp3wacrnqvtyoeNyOxrvMm7UPOgf7(mPv5aX2JvOWNVlnKkCLQWVQwxQNiEhWBvL8vJugMXvIAdR9TlbBO7c92ICvMkw1jrumyvciNrJNacPU(SkzCqoJj1cQQa(YYEivfKrZpnLZPwkwp1GrCSqDv6IMQKyO4Ze2coOYdUVoGZuD7b8UIzuqRNYN(VblY8CfTS3ILsYjUmkG(fXKxaokg8S9wQa6Bjj00Qnr5UvJc00G93sFn0DwXdzbDyT(0ohVbxOu0udNkPYbdr7tBzZmMVyQeA(s6Nh27b5yhjXhCy8v1ktwSkqKbllrlrLEYyRzm7MjZ0xgyg59zudyZD)Tmj1isS9BtdDItdjZ3RIaJfOu1)byrYescyF2jrkduU4Wp1WgIun21Imam)GPdvBGA1s7uL)UkwdAQyBf0tO30wthl)ysXnFlkO(XQsXOrvAjV7WLQpJ4BsoDmgjoVG0ypkPV4M(suqCyAKJJVBSJO4st9MXWGy3OuNyVaF(inbdKNMzJ2lPSsEAr8IgDeLF2SlQr0LmSTMCqT)wb9b4Rr)T0bwknAwNG2sXBk5uJD0e3f1M9yj6BKJKJYeB0MPdYBqmZpql6qdE4cMmONFAx62HZB7q9KO1PmG7BE)Z4obOU55gqUboHRzaKlfgAzXk80JV3QAhdMN1FRYvqDZPBNUTXCyJDrzcYh7wvfjUG2(T87s0mLE6oYHnUa5c0EKiInUZYmWO4H(KbMZrGJHuon4zRRd3rMl8ldDaJGmAjQC3q(alBwM23erxZyuN9axTsv28WWHkvSyv26YvQymVHWSWyGFv2U4iaVzCQsVm4XMS8Bk1WOvXhKxe7Qc1jwogiQzC)r4kYiVRmVyiOww0Hbdu37fHEuhxdRwph5CCQAZw5eOLyaz7AsedewEWmoboHF2tFmptFJA0gV)e9pAAVyNnwES5ACadpIANn6Q63SHcBCMfa6sMkwFZ6eLY4vBwxBFOe3cnJnpDf(BS7bEXZqEovD2XkIKt7O2C(5XXwMRp(Cq7M1Lyqg1aEClY658MzspnOzAIJnapGlTGb1MhNknx3uHh2X(c6fwj)KYshj0KyFgwM219fjzZFcV0jCse9T5E18rZGosCUF6m3nlzcNS4qfp6sQ9VZ(wjc9XSoEpviLNmMw)k721EL4(08WseK8jLn9n7YLmQowntwTtHtgGv8uzTcnh15Lx9DhSy5WawLokgnZ7zwuwvroyw9z1lXwIgExHf(88RVhBJChsN(B7shO9HcOGxZiu(SFB)hUFBGpkpXdiuybJUBHn(g1cMIoGjWinq(3dF88WwNMfF8K926)06jODB1fn06BWHV5D0y)Uco0ZQzCDsfmdZqryz9fzE53SVJt7oOSH0iDZdla0cFo1Myo0tOrU1WM9n2PsJyB6A5DevCpg4s5mH29hHtLmNSkMaggpp5Pxo21Xz9GzoNh)oCIyKEz1Pwm1P3TJWyHTCrJyoz5Sjhvh5oMYDOd4e8g7I1Co6COhohNkoy(kmQzVmNFG7lXuM4YrH1mYPtlLD5i20(BUJZsCYZUB6OspPBztFcwdli1624YHh)RH(HUdFn33z2TRJjzg)lnpSfbz4oCICVoGUNZY(3epqrFkSuiZYBOgDQDThbfK2vI5nPi1SyVtXJmcuB9DuFwqvfuOy((hkyKy)L)glvmaFgVQ0EE)nos6StdgaVKe6MjFa5YzIFkDLq4kijTDaISi0K82CjV1iXrEPyFW8Gg)x67hstGSNvAFOUaq)sFh8GpoayMUVhMrTahfbug4f7ferDe6dye99JgIfW0XhvfqXqtHkefGRd7IjdwNtfX)rB2CTbvxTs1vn0jGDm(pIETW3lbmNI8IZ6y4Xv001jVxG8niye0)eZPrzZi7P7CYWZsFOnwZKEItR5yeuksQn7J00XkB95Zn(au4p0dc5PTnt6aTJJXACMfprgWPg(PYFgr2GpmXZgN6mZA9OmJdMpL12PQeprKCKx1BXvgDysZ4Ot5bXenD6hUdR4g(fu3cCDYuGPa5(sF159GzeXJ66Mots1mZ5O8TgW2b5Hls6Y8)dvB8mVygwkF5GJBN3TpZlQtZxQHgdQ0EMxSz9WJBzF5M2S8IYu6YQ8rhsNCSiVqcj0oLHFUWZhyC1uz0238PQmWZnLY3jsznq5KLHW)C9))27kTP22An8VO2r7B9tobNatzBmK2B)eJaeGASL9vsUeAN(F)(UCw1ITHKqA61D6mjXG1Y58EE3FFESB0QxuJSHePWIRZB7M5CMT)Tl4(MR1Y4jM4BtJUT1kUabAsf39TqiovmMcrZO5G9R)xIwBBl1zbIGYmohzoomrxVibcioqhV)vVGmdMRVHBuUrkhd6zGY38Plw1(KUm05IUHMAal1jXUfs9BEh4z1wdklvV(1YjXyLuLzjewpWXS4ZQb9gRF8WnpBnfCdTjAXTxsByJW1GLUhJXd87SM5dbAdSbzvI3IgJRJkBwf9RtN)b6J1png91T5jnhbxjGDdP8VJw9W)oJ0ceQ5OUoxUKg(oS9j2u1MGGuvFfApfBipmVM2B3kb3ureixNxtnX9xR(rSVmmPaIqxaC8P19XPSn9l(enVz88JGqzrVbl7ZTKvBk0mVoIpyNPFuf1zE8Ks3B4Z6zoxohP2De3U3iKMBLGmTE6rgS9iftmIUv7EP9lzhjfdypEJZot)2w7ZO3lTSglGWmU1sFUdy3G9Fw3USCSs51TUzQybmAK8XBVZ(zeFKbxyGI)X5ZE3BZPrs6)ZiVmJ3PPJmGqFE1rCNl)(MRjZq1zCW(NBNl24ghOlZ()wnQvDka5ydQ1xGkqA5fNDFmBAYrMms5SnYTFSr5kfooqjQLDLWqr7idj4WdsZyLJz46nblbOnnXqTPmOHLsF0smoqz)gjZrd2ARJm90D0TURnZ641tu32QMtQZMAKXn0QRFgL995x1Xotk4OD56yC)6OZi(itewVPgcC1r7ZsFZnQo5vp9Fs841EkE)mQ44iD8g7zj3XFcPwmLXBO(KBTYIJL59o16tiqowdU9sts6MQPOQcD7tq6(eKAGHaktd7lwrVzE)LEoC0eKYo(YZRo6U9iDs(G5(PhWlmysl73oJc0VClqGWqjAzZzL0USHjcmDUlCxOD9yeZ6j25MtGIV8LZrm8B6SxymD(m6dzG0euPODhn3JGlPDNl)X6fPHGvKno5fBYy)4iiWqD9ZgdRBqOWzyFD6CAoahEONdAJmwktnVmpRzYFSUA)zLFNTA)DGa3hZH9HJ)EiFc4APjbMqjgjXnAcp0B8XA105tFixysoBcgD7apuNMvTe(viJZevWoMdeQQSIfoajOkeHdRxEtz7tC(k4zQcPt5oiXNne0dIXvl55zxJyt9rXRnaD8MKwakvztXs9jkjo(YziCmHj(Yck(WNxeQnMvSOScrkxgNtVzzvZ6fiqTz9YGaNxwbHznEz5RVhXbURq0xNquS2M26YpY)DgvjXfFVmczIdZEeHbpwNrz1hF6QRNNZ4lx2J4VaVCU6HYBOlq16fxJGcj94uKx3(WCKutXpim7U55n4xfND58BNJd(ys2JWlWDRRX)bc51lf3R8fRMxE3t8xnjRUST4Q8B)DHyX88ffTlRUFn(yJiFa8tBYRWNb3GShlYxTS6QIQBEGFzaxGRlxbxq4QXTSc(Q8g8nbXBnMaf8eed(QIBkZN3CkMylgJnXhju)sDXDf11f3(R01FkF5f8h2vRBkU1aDk5Q2O(kVdEXS)nr3LHTaboYqZpFu2INAHvs6ju)vXvnZVl(gecNeMdBJAbao5O2FQKKV(bINHJZULbTguEGBn5pGcpsu0chvUkAYkti2S9YNwXSmBC2NyGIsqX8lr0(U9jXp7jXpZJG3bXQO1f(G1v3xSSss6G2Omel4JGlokIn9tW7DtZJ54PZOSAP8TbMOaAfqvjx0wN3MdRzNm9GJ(WjdtbV(X0WFsZwFS4VlQYVj4RADQfeCji4ucP5KFaEc0EDcHoQSuyp6DYM6p(bnl(Sfe7H6CXUCxHVZlJIHWzuIqHhgBoXDztrzteoL0lKxs6rB(iphYxdFH14zMWShwWCmiYcXTpY)06Lv)jEMdpQwtAETaXw2kWzTpaQKoPSPrCGle06WkyT(T7)0r6qegmiKGTHGIrezr(JLxHxeCPh0CI488Jx9yXt1WzugyPXEW5oXFsykpMOX8Bx(i8Ks45iy9OCrbOBSbpYZQkUgrKT6pEfFqxCXNx20wqa2kb1S4Vk4)0tGMTLTKEoYbR7KFjgcO9TqP81WdibbIsGv))25t2Y0fVzGd2a0(z39q8QBYn3uScr0iqvL(FFEDXFa6joz98wEJgPAeNF0H4PufM8ZSwkYFQiQnCi1GTcmo7MLii11wCRQR3uFcEH8cjpotPB5LRRbLMxG8dZfFSCfFmHj90vihjyk8rYtK9Drpx5dBpTZl00mGGziu3oKsk8diupAeO5e5dw9dps(NWfe)Am7Ji(aeg8jcix8V7s9khUCnk4cpSIhqIMvv8xcHI(8cgegY1)EbX5SDyhbElHxpy8NCqGCwCdi(0cwi7JUKOozn6sk87MDdHZqj4F16ssugb0YJx30YUNGR9W27cB7lQIkbMMqOh4qKPhkMFh)icY0DaUu(3hrSWouBURpIBjPoUProubiyvSgekdP(s0XkedZ44N65ggLsTyvaEZ43JTp43idyTC9QtbFlKegkzQHRKWBMxuCBZKgKcHqezJoTUkxQ)McUbh6CjEKbM7KaSk4xHc1T6wZAVqEjAcSpoROP8plunKcbwPYlP4YPkQiOMPE5CIBg4ultWYVzM0SwJrqK6ody9GrnfAZdNrdAXr4CGXMhAiVyU8ngugd7qSAscLlZxvr3v2JMda3wQAazubjj3h6hvVm74ocSYlwpbRHFSr1tocWUu((BXNcG9eK2neYU0kdFsg9qNX0GoYyClpHYvmG0Y4BMekNPr9fVZwlNSjL3RfxO9kxAT06xKPQ4PFcwSRys4aCcamPrR1bzZo74PQNoqh6TYMBowqFggVmgK)f44K(w3513EvrbZoGKkb9NRRAbBvKYc0)yclspOSg1UaE1RBOBmqeuWqtyRBS(J86BltGq0lNQ9iuz4Mr)q2ejUQGqplIjbmq5ksbRjpKyc2L4dR8O1fS4a91mwGmCEBW(sjMpPHRdYBnBDgwg6D8Yo9jedRGh3TwSbfdlwUS9bKKVflO0bgdHprop4ds0IdPhrSwQe56i9b7(O2lMPMYBnUEc2lLJpTRqoIr1cvcDGCPbWbA2n9I5OgeR3Qb6dgbLdH6IKRuws5ScGJ5bMbUEDpmiXNmuIYcD4490(Vhm)Wagmqs9a3Kah6OLAQOz46n7dfl0PpEkQsp4FyBE7AsJrhtnmPmJCwZY6do)cgyiGxl8JmuzlhjW7paCof9JtrYocA(R4biGs(9CxNK5ydz8okNf8Wo1kEc9v63GTdeNG4oTxIVetiMoI2Q48YrHMWEmFX6flwwDEr1TIGN5no06pYc5uosqL0AP1Zxw2SSsjU6Lef6hL6e5e7O1Bg7ehKMM677f5Y4ZReENP1wClwz6HwVWbAKQgpVZIl9kzr6KuIHWPbUel)ooqymLTkyu(GZ(1tjtzJb2i9OszsDFFI1L1939Zzq9V7PfwZkgVoQuryJeDdUS4rnVChMWWN5NQIGnc8k5kB(sJUWDy8qfvI17SHLVzgMeaDLg6e2frgwziCi748gbE9BE44Y8kI535dzSLtBRt2jZtGuV0vLCLucn0K8NWlNdxwx(Nqm45eSU7arjOoFr5oWWYGerDqTUWLKrYrttgcEoqifeMn7O3FOqvbktdAcHJ4I3cyvlNpnqpMc3sVONHydDFdMipPCjT(cYSf5ni1NWYnrriJ9MK6h5fWSKejM5N47Lgg567gc)p9XyVE6KgfM6INzsCtbV(z(jqRqBqxYcZAxsSl2rizlCDoTVLAT1BbRRgUjy2XPOl0IhKXGIxoCk6EHlQrktl6tYDa4yjREPeOsG4cyExewI4kdCXJLReKwrhEjWMOHFgAvbpBzpT1UgZbdQ1MdA5ihbr)g1C4QaBzfF7o2ZS(ufsKl(0TE6YaBW5XpunHOin2UsQgJZauZ5f1ZaxYqjtn5EYoCOW6yooly70WzTGSJN(okrJGZrAv2NKFF5nkHs)aeaidI9I9Cfq9ikugehg4Keg6hg7KYYQiSmZPsx6Cg5FlJDXS1iY(Y7(z2Ojz5am5)0BFOqsfiSYEXkFhlVg(VjLc8f6cTX7xStsMp3kWkzihSNFD84DvUTtSAvbbSUJpuHn(IwPC8ZLH)cCy4Ss(yyF)49bkqrRaMSbKw4NIXQpqmEP0zlMD8GycUCcymlk7WPtoE6mqI4GjNm59tNH3Fk2zlU01JJeOtuO0wdRa8qq5TYUEhV3u904k2Sf53oicYr4YATj)T4ebOcMc1MsQK17s)GOGGRYhoitkTeZlijQM)6s4)qsxItXS2(IUXQlYr(KlWqFOgBT5pfJwQKIAHLqhRp5SoB8211cf2OkyM4RnPKIFmYNTslSxrgYe18uedq3eO(SfMqxc4ZzIteImalS)j8f1qtPkFjk8h0mQyRtzqWLkhFhAJqcxPmR41aN)4a6Lb2OqTx9LXWFDW6N557TQg0A)teXROJI7x6ycl2Oi8ub7V9BqNocZmGrqPRmApRijKrb(u1nxiI6LmpPRGNSegfmPzk3NeP4IcHx2LECQhLp3pnVGuhlDXJfNXGrQbZEiPceAeb12F7e6y5dYIGveSNr3EtnaZqwCsGpLXmLVhd8XONkD(y8zEGukOGSKUbtjqauxtVv2X8eGTEHmkrnULkbr4DmVqyfB75Hj46MoXp7YABxkurKbp9hBAMbPF9A2DBy5dxFhCMMKnVf5j71l0PYJlC65ZoA6fxE1HND8V9x4NWUmjlmgNmciSYDCza0u)yfsmFu8Ew02Exxf0MebtycUjTxWX(67Twxpid2p5B2ouP5qSGS2NiIlf9RHSxro9jtxthFV4KOPE7fSrfePLXd423ijFtuof8FQylr2F6VX0)meQ5URBXlR82kM28XqRNJSGTF6pH0VCebOdgE1fND5zNZobikRNTTFB36q3i6ThOGnfZFKWL2)(vvwr6oZGpMQrTujMUxuPHevWWC1IkXXbGz(Qa3iFkxEwHaaclYGv5qa(YkTW9PY5toEYbhD6)Au2qTpMjHf(VoLnUCXcvABcJsDD(PkphhhWKEfeRwKpO)XlaeTi05)vwdeewnecaBvKiN4xS1QnOAX2qwVO1hWyeORFaLrdhSm2rbM5cyNnD1XGI0mZxgtydPeyqlyKIgI0S0IjOlFjUGCbiD45bQC89cfHR(SS3nMgQE(O85AmJdV6KZo9NV6KJU4YFD6KFz6S9UdjAIM)r7oeoe(gkOGyoaDwOgPiESzFLvi9Q5(8ExIErEpJ5B1uCj0ngSJfaASC7A)kb9G(RTtrXYaWo4OlE7rNF8rNoDVENVh07GjO2qqknWpjyFKyciBzFKyu93OIxqoiXuJOYn6y0cf48m4Z83U4XsZM(lN9ZtND1Kp8(tME6LtU8OZoDVYNVhu(q1S1WFBxhhm0E)iNepq2YpkniKYO)EVF6uNO))o3HU2zekW1pfTAf464HXXd)zusei)Kg6g2175xf3Hu6KoF20lMo7x2RtI5oLVmb1)vnV0u3(Q1j5hre2yLFSVxu8EDr7DjQJlregpAkVe5gcHI5hfdIoWFggMgarY7hhfNKGFUVihsV25Toj7IdNCYKtVcujD5zZ2Rs67gvsyFoQLWsJj0dDVlr7DjYiYmAQp1cjrUEPGwipN4ahhmXqbbPDlT6RINqXzhm7dhDWELonM9I03d(bzBwdSF9TOWy7Zd9)S7Id7cMHnO9pvfdgOQaNGIJHy4dsc8b3EcGyX8F9vaH5Ts2pCwToRAAw09mLvRVk6dnX0SO70ZurB1(U6LliMNE6T3JdfRR9qcym9aUzlkQVx0EMC)uk7Xs7PLtJv4PHEGpJUXrbXoH8qoqTwgnDPUwWiX7QllQULXkI7u)DioRHy0PHy(ybenkz6kgXiAlNx8EbubiMFgA2zs55QVZeqz25aP03v2nx8m2YJHYSI7lxwHJWeEpKqNbFxgB4ArWUGMNzgsvnN(zXvMWxn6NEA(cA8iTb9d9CwJp)wZUEpw2q(nra7WyYQzGBxmPQKphQ1O3Wp9CtXdYpZlP5yF4HB2rpoO40ctOKRNV5GFt7Fhv9hLTf0O6y8nWrGomIEs2iuXBm15EzRBkWrkVQ9Y8RfRD0OpJxgEtMFvnVr0KsdQ6jbv4cyZo7bz3Ltng8BYRQkQBEhn58e2kGJzmVnH9Vqy2DiEqaYLrisuCD(8EydHB2Y1T4kMy4y5r9NqsHI1L8do89tupf04CZ3i1utbbBfLe5ftZNmDsbBb)epF9riEmmOPpcppLi)HEWXP)(V)F",
            },
        },
        -- Blizzard Edit Mode layout strings (shown in a copy popup), same keying.
        editMode = {
            p1080 = {
                s64 = "",
                s53 = "",
            },
            p1440 = {
                s64 = "2 50 0 0 0 4 4 UIParent 0.0 -164.4 -1 ##$$%/&''%)$+$,$ 0 1 0 0 0 UIParent 898.1 -1079.3 -1 ##$$%/&$'%(#,# 0 2 0 4 4 UIParent 0.0 -523.8 -1 ##$$%/&$'%(#,# 0 3 0 0 0 UIParent 841.9 -1142.0 -1 ##$$%/&&'%(#,$ 0 4 0 0 0 UIParent 726.7 -1029.2 -1 ##$'%/&&'%(#,$ 0 5 0 5 5 UIParent -2.2 74.7 -1 #$$$%/&('%(#,$ 0 6 0 4 4 UIParent 0.0 -400.0 -1 ##$$%/&('&(#,# 0 7 0 7 7 UIParent -19.4 181.7 -1 ##$$%/&('%(#,$ 0 10 0 4 4 UIParent -385.0 -145.0 -1 ##$$&('% 0 11 0 3 3 UIParent 436.5 -283.3 -1 ##$$&('%,# 0 12 0 4 4 UIParent -1.7 -278.3 -1 ##$$&('% 1 -1 0 2 8 PlayerFrame -24.0 -30.0 -1 ##$$%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 7 7 UIParent -298.0 384.0 -1 $$3# 3 1 0 7 7 UIParent 302.0 384.0 -1 %#3# 3 2 0 4 4 UIParent -180.2 119.2 -1 %#&$3# 3 3 0 0 0 UIParent 597.1 -361.5 -1 '$(#)#-].;/#1$3#5#6(7-7$8( 3 4 0 0 0 UIParent 151.2 -26.1 -1 ,#-[.9/#0#1#2(5#6(7-7$8( 3 5 0 2 2 UIParent -55.8 -293.5 -1 &#*$3# 3 6 0 2 2 UIParent -55.0 -290.2 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.0 -202.0 -1 # 5 -1 0 4 4 UIParent 273.0 0.0 -1 # 6 0 0 0 0 UIParent 1495.5 -11.0 -1 ##$#%#&.(()( 6 1 1 2 8 BuffFrame -13.0 -15.0 -1 ##$#%#'+(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 1 1 UIParent -18.3 -130.0 -1 # 8 -1 0 4 4 UIParent -796.5 -428.5 -1 #'$>%$&g 9 -1 0 0 0 UIParent 1311.5 -731.2 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 8 2 BagsBar 0.0 4.0 -1 # 12 -1 0 0 0 UIParent 1803.0 -259.2 -1 #*$#%# 13 -1 0 0 0 UIParent 71.2 -1154.0 -1 ##$#%)&) 14 -1 0 7 7 UIParent 536.2 2.0 -1 ##$#%( 15 0 1 7 7 StatusTrackingBarManager 0.0 0.0 -1 &- 15 1 1 7 7 StatusTrackingBarManager 0.0 17.0 -1 &- 16 -1 0 5 5 UIParent -668.7 -379.5 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 1 1 UIParent 314.3 -1002.0 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 4 4 UIParent -31.8 -58.7 -1 ##$/%$&&'*(-($)#+$,$-$ 20 1 0 6 8 EssentialCooldownViewer 4.0 0.0 -1 ##$'%$&%')(U)#+$,$-# 20 2 0 7 1 EssentialCooldownViewer 29.9 4.0 -1 ##$$%$&&'((-($)#+$,$-$ 20 3 0 4 4 UIParent -916.8 0.0 -1 #$$$%#&('((-($)#*%+$,$-$.H 21 -1 1 7 7 UIParent -410.0 380.0 -1 ##$# 22 0 0 5 5 UIParent -1368.7 -122.3 -1 #$$$%#&('((#)U*$+$,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+$ 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+$ 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 0 0 0 UIParent 1731.3 -1050.0 -1 ##$#%#&-&$'7())U+$,$--.(/U",
                s53 = "2 50 0 0 0 7 7 UIParent 0.0 402.0 -1 ##$$%/&''%)$+$,$ 0 1 0 1 1 UIParent -200.0 -702.0 -1 ##$$%/&$'%(#,# 0 2 0 1 1 UIParent 186.0 -702.0 -1 ##$$%/&$'%(#,# 0 3 0 0 0 UIParent 841.9 -1142.0 -1 ##$$%/&&'%(#,$ 0 4 0 1 1 UIParent -371.7 -902.0 -1 ##$'%/&&'%(#,$ 0 5 0 5 5 UIParent -2.2 74.7 -1 #$$$%/&('%(#,$ 0 6 0 4 4 UIParent 0.0 -400.0 -1 ##$$%/&('&(#,# 0 7 0 7 7 UIParent -19.4 181.7 -1 ##$$%/&('%(#,$ 0 10 0 4 4 UIParent -385.0 -145.0 -1 ##$$&('% 0 11 0 3 3 UIParent 436.5 -283.3 -1 ##$$&('%,# 0 12 0 4 4 UIParent -1.7 -278.3 -1 ##$$&('% 1 -1 0 2 8 PlayerFrame -24.0 -30.0 -1 ##$$%# 2 -1 0 1 1 UIParent 1122.0 -22.0 -1 ##$#%( 3 0 0 7 7 UIParent -298.0 384.0 -1 $$3# 3 1 0 7 7 UIParent 302.0 384.0 -1 %#3# 3 2 0 4 4 UIParent -180.2 119.2 -1 %#&$3# 3 3 0 0 0 UIParent 597.1 -361.5 -1 '$(#)#-].;/#1$3#5#6(7-7$8( 3 4 0 0 0 UIParent 151.2 -26.1 -1 ,#-[.9/#0#1#2(5#6(7-7$8( 3 5 0 2 2 UIParent -55.8 -293.5 -1 &#*$3# 3 6 0 2 2 UIParent -55.0 -290.2 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.0 -202.0 -1 # 5 -1 0 4 4 UIParent 273.0 0.0 -1 # 6 0 0 2 2 UIParent -268.0 -10.0 -1 ##$#%#&.(()( 6 1 0 0 0 UIParent 1997.0 -150.0 -1 ##$#%#'+(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 1 1 UIParent -18.3 -130.0 -1 # 8 -1 0 0 0 UIParent 62.0 -1145.0 -1 #'$r%$&+&$ 9 -1 0 0 0 UIParent 1311.5 -731.2 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 8 2 BagsBar 0.0 4.0 -1 # 12 -1 0 0 0 UIParent 2227.0 -362.0 -1 #0$#%# 13 -1 0 0 0 UIParent 89.0 -1385.0 -1 ##$#%,&) 14 -1 0 7 7 UIParent 739.2 22.0 -1 ##$#%( 15 0 1 7 7 StatusTrackingBarManager 0.0 0.0 -1 &- 15 1 1 7 7 StatusTrackingBarManager 0.0 17.0 -1 &- 16 -1 0 4 4 UIParent 552.0 -200.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 1 1 UIParent 314.3 -1002.0 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 4 4 UIParent -31.8 -58.7 -1 ##$/%$&&'*(-($)#+$,$-$ 20 1 0 6 8 EssentialCooldownViewer 4.0 0.0 -1 ##$'%$&%')(U)#+$,$-# 20 2 0 7 1 EssentialCooldownViewer 29.9 4.0 -1 ##$$%$&&'((-($)#+$,$-$ 20 3 0 4 4 UIParent -51.0 100.0 -1 #$$$%#&('((-($)#*%+$,$-$.H 21 -1 1 7 7 UIParent -410.0 380.0 -1 ##$# 22 0 0 5 5 UIParent -1368.7 -122.3 -1 #$$$%#&('((#)U*$+$,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+$ 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+$ 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 0 0 0 UIParent 1731.3 -1050.0 -1 ##$#%#&-&$'7())U+$,$--.(/U",
            },
        },
    },
    {
        name        = "Midnight Lily",
        author      = "Lily",
        description = "A dark, elegant healing setup built around raid frames and a clean display of information to help keep your team alive at a glance.",
        tags        = { "Dark Theme", "Healer", "Minimal", "Performance" },
        image       = "Interface\\AddOns\\EllesmereUI\\media\\profiles\\midnightlily.png",
        -- EUI profile import strings. The scale variant closest to the user's UI
        -- scale is auto-selected;
        import = {
            p1080 = {
                s64 = "!EUI_S3xwZXTrY6(xrVCUlpqEX(MFIlswkgrrDOO9ypXebdWUbjXrGa9aGws0oM)738lZQkuan6UjLTh7zm1eJjz3a1sUNzLvM)8FPli7(I(C6xsYkwx(Hf5vf1ohgf8n)LU4SUfTff1VU21jXX6d(R1UPEoFZ)eVD)dRkOFCZ6Qk8gFQOTRSPU2NE8GSL58q76LTUUQzXhFB(dnR7PpjolVEXDnTD0V75LDYPND1I1D9n3Fv8vUjEoP(xLgqFxuwFE7Tf90VSQk)HIw8Qn3Ctxr)pslthhNGe3G00WOW0ypFpEw7kxwqVWXNF5LNF2Wl8d1hefDOl9V4KuV40qxSdCDZE5fhF1j5D9hN3ApLUXY3uL31DrrxZ62ff2tVlpwM)nm1(zxE(7TNxfOIgFp7jio7S8YA6thnQHhgY)l1X3liDyudYE7lF1LJ2oYki2ZniYlkoaBNXaZGRIjGz0vrUX7dy6FOtOBCyCIRxyXboH7y7OGIUbHoUPH(cDaTnc)63CHzx8MV91J2D8MZjXpnjWpoetsktNC9Ac9)uWtEjhMKKKg7t0iP(wq05XtPzFONiolMqnmlY6a3ddcd8d9999cjyXya3CBQeSyiuBItsykJXIYEFXusV5PmCpmkkkokjm0jjwyWys95OmsfAdluerOdW36(YQY(h2h5ay33bNuOcMg7e6qKmFZ)eCsozFUCz)DNL3V4oA8tz2N338zsKGRVWJ30uTS5Z1Dt57M7bMH9BUhZtjIWiOq(fAg8vFd4TVoV1imr46VRO8276Lfl(e)Sv3LxtIGoUzD9YUFgBPOS8LlBQzPuKCIQQIU7lAl(U3C0IEskhrIGVIeuSAD3DflpHfHDstvdeK4sY4CjWOB21qIQdeP6MDl97ern)7T0Vt0LSyOWSU7A(8XvL)0p9Mf0qF7ROpmvnWFxxblgIhA6lOfZDeMhBSY6BpQU8(CSE6igi3Omnu(LlVT4dL)urT3HyD45qV0T3vHT9LfFPFDBXLKW7Ai0K(oIqkN(S8(IZRprHNWufoA8MUsOPt27h30USOLNoEJgLD9WE5OkaBzGHxgHkEFtxjVGzfqey0NHxpuFqyqYHe3KpXu5eMerVrswBr17BkRHsGtE57U8Lx8x6cZwn5tCZ(cbnHGZa30up3erMbp6rQrpWj5W4qhhFwuxYtBWpinXNxAUEPjjEjmwJOr)sFBUICyDFFtTEN4NazOpHv)b((JvuiaKiFw8LBKJByeWv7CinYCa84a3KiiZikW1JesXaeIY)7lURCrvXl)sjufZZsqsWHU4j5)fVVzzarGPjjHLmzEznyprn6KSXddCJIjyUxkKB9uakeSMH6XboE(bSetJYMVgaKwyjw4erYHXXXjrEezxcZhgLDrXkr0pg9yNXBTN0ANXMHz)W7)1C8igOxwVGer1x0omUbjHKufZ)EAWyiqY(FgymmAaqb)OGddPN5RIPK4B2adA0Vzy7Jtpmia6stEY8nZW1te5)3RlwxqAY7xZIOPDrqQWm8vrJ76eOSbX26aHauT2jiezS1EPVTjajdBGiRi)y)WuI5ES5akYBMgnM4DsIJ27OpM)NGMmZtIBe96dwQbtRLr3XJ5aizlU(pv((dICyztK0qxNyA1dXlPdkzMQsG0W22S4BRA(S4MbRuY18HBOAjnBDxbRrmVD5PKReqFlulgpsL0xN(w3SU)X682cOSvP38(gA(Aipy(aPj(OQkOn1ZS8yDLSkSi711h6FOQalkAalQkw0tQczBneR6SSoyQo3KSsAU)Bnn3xtubyGhaqd7jy7GFmuek2oeR(9wATa79TuQ)lW8JaOvES2ypcitszox5S1bG0JwHxZk5Epzxez5HapcY(uz3Rj7rExZlRlU)bbAiMH9xHfH1WAY0SRV9L15xxvSKEG4S613FrZN7mwfW2pCmPAQgFpnaxZFYSyxn0qBffRyli7JfpCn96Ys(hKromBzzhM1ljBA6lxbcO4SczHamCsg5s653CrE9Tf8Kr7lSaI0d3RAQ7TXhInDQ9ozdN4gzs2De5d9UaqmSpP5huuTa6yVHjhGR(C(dDGu7ygKYeHgq5zSeEgseoaEVKHP4d9ZUpFrBdwBSnxUaetR52c4botvFoaFYZEBBZNpTSLOoHrxKfIfq9buMrybMdO2fMwqCVAJhb16pkqsg9bJCZVfwB2sdw3fWksm4bdlK9dKMGI(r22t2038vfwIlGbi0Mbwe)ERjvGgcDXLKnmFSUORdXGGiAuIfU)68EatTWaeLedG)aMe6PRBQj)4PfotF)4WUeZqfnFxExBZ6BVdRdpfcKq3llQLpri5Fn7yHa0iS)yIlwWl4P1ur6Fd(ci2u6X7BIE8JaZiUbyJv(bBSsOnvQfLG4GWFryieIaZ2DebJIlZ27cw(kaKJjLJjgyBUrsVR27Mz5hDuykz60yudI(XZytcDeuU40czsvxtv5sMPZIYrHYbBKgLlsFiZQzYjnqCctJBgXZtmeIluKxS3r)9prmw5vm2WsmOsMINqZRfnQypSXr7NvWNrqNHXb7lSQP9zE73x2vEn7Io8(KLrWlEJYjlk7iBzl2SXJwG)GqkgbXiNxx9WBQ74aCWQsncCETi9siKfggfHmd(i38ygr2vzIN3OQCvrXsqoRuGjykluH1ZQ9cCKBzZTaMQLHLs8SwMDOLzWIiqmTFQVzu)mIA4z1p)BL6hXs1Nv)aLRKIuwn6VJQF2QC5Tym4VoAG2QcUhHQMWSAy44w10mwHAq4Hb(EoPKdPKh7S05hVgNz9RyIkNnNGFL1)Szac20EUn15c2mTTrtmYCEtMiLwx1L)j2LqRyGUHorwb928Gy7MVVDfXBAV6uJlsh0HpkEDpRpwzZ8ViV(EwF8JXN5)J1DWN1hZbRAu4zEwFSoknpRpwcZQL)GwNsYJrrSoiWZeTN5vehkhnDDGdtuUdpTNXFvjkawX)rcB48X7BdB5E95x8M)25V7YJE7o8CosDC01UQO9ZH8pghr5wdFNeROPhg0VqW322wB1(MTejGnnaz(abyL9dZglINdfW1QKi4RpGZSb6)EgW5GSQIB6FoCZphUz9H68FYHB2JpSUFJd38o0GnJ5fZh(459z364QuHuEhHpEwN5FQo)mX5Fg(9RS)(CkJGKVCC88)X6NpwtjvxEwlZZhQ5ZhQzosHWNputo56fJgF(qnHZIpHd1ejb)Zkz(Tk3z(D3vMWSwKDhp7lZZ(Y8NbFzEo1z(dxQZmk3PFojnv585Jln(EojnFe5g0)XEQCpNKM)H6u5EojnTYI0)iMKM23fQFHhR0FQovooyJ8DN65KP55KP557wH62qVTqmVV7wXZjtZFOuB)CYT(uppS)LNCRB5wP)luh()QtnKKSZkx02OUKZpMf))5MFUJlkj)oBxXmhW8FmV7Lp1JV43ZCK55alZ2l)8DYevof5Mp)FwjjZwU7lBnpzESx8YDF5zE6xJ85ZvMDKVnJJJHK9p)cVomZMeQpUuIzUKPzJJWKRZehNF7Z6w139fUIy8C00)nkA6mpXVNAxFUKh8CjpWuJm(ps1Rt0cXfyUFJZb1NQ51pI79YFqk5bEa89403(iZoiP0CAQ)EBuRJcn1ziD9DqkkGw1CqsFnxkRcZUo)wC9t)qtBpsrx56OqFiQxhhTC5j59f320(GuqzOp)SMpv8UMpCx5nCDMGha6HUSSVskqGUCX9HhJ3v01F8dV8lRYRrHCvQka0N)9LDRZR4AkZp)U39Z1EHoEHjFtTBQFSt83q)nQ3KFtn9XE4pJcc5poinXHEm6N(br4ZJdIsXFhghspUxuIFui(BxVu3V5F(Z14fWhGXJ)PJtOJ8Za8I4V9v)0tgyEaJC8DXFh66KYFp9tAc51hTaOHL)A6X5HL(PpnS0YnIEA8uE0FIYGLdpBjHE8Om9NwJo)9r0Y16N(Prrb0Ft)KxL4N4Vdd99X2pm0lMFVqANlGdABZpxmax0ptu)DcwU4VvJtcVSDqDRv)Z)5ptamAGOrJhZKagtK6GN1f1Kum3bjbjas465NW)TFS)o(jEopEoWiO(jgx6fJamYlika7z67DiiVBAIhMx3ux)u65JIcP)6P(F5rtnB8pJimdMLX)e7yzxhgfXew(EOupciIBetWffW0jbErcKI(BMa01JHS0NhW7(4yx(5IJLDjizv)eq8G4eqpZFoVBPFcmiHbemwuCetW6M4W4A3KexGhC9JJca(W1nkfWRicSrZyukwhUXboaJY)epnHnIJOXH(FCvl4Y7kEXrT3t8V)BhVWxNeHFTyH0swE0SskjqJzP2qIela8OLFQOgfFOx8(2Iv)zJNdeMrSsdDfZs0AWvowYWJ8BpvQXAAvpLfqtvCMQOcjLKP)71KQLx8M(I77UCyev6QqLASaA3CZoPPUB99y4WGKIIx26vVl)(InreSYmZ3l1)oESJZ(2I82x8Y67qLo6Ec39vpwHzm340LInJ6wxg(zy7(Ipu0)cSE(QgJKS)Ar(kcM8I)FV4Y2Y6pwS5Ez)lgPubEDE9h)azKW15OU6vLVQJlXC03Gso23T6228LfVPEz5I8(MwjC6e29IcuW4Et951fKri4f8ZkPnwvXNkQGPmd19yvPgBDBBr9IheZfKYcjmAzYuBmCbwZ8(Y66ILm5HSKuw5qFUm)xwUIRrESzk4nullMGINcSjWaWRR3uddMKkISyVdBuKSKGV(YekeK4VLHt)3Zb27u0c4o5ocXoHSDw6p8mxc47l(2MML0m6M9(2MBk6Gzw8FErr(TyfG1nndNv2TOGqs1fnR5V3IbAG3YWjDAXn5RR6fCeTTjZnvMe(Y7x1)GA)tCMcmuQaIFBt1sArT4JL14DeqRP4CsyFdAEOOPPQ3lfcV1Yrqzyb6f51lBUNeqyOFuOwf9JGsww0NV4o1wwOQqj7bYyQwFV5qZ5nrNUErRkBPPE(hgegft2geh4XRhUA(gjf41Kyhxxucb1vj6yuq(LQNpbxBlQY7l)uHutPPjvAua471CjSL0cK8VM3wlahHoceEmedfOVxjM1BzK(zp0Fx5IllVNiY4xHRHHvR7U8Zn8NQk5Kx))GIX4NkMwUUCoukn4OuFAvKW5kAenyRQk7)qfkP6JRqOKLl63s9RQ6sj47AvfYn(zc4v0565xXGWd8RY763yGvJRuUcrrkKlbZeLrbxQpBAxu09(f9egIa3V9OJFjUM7(Y3EmlMXC8)OahQxLHYcgdOQUulL9qUaIsVNaMgTub4dl3rvVtxba3w8PYIplLfGEaMvG85QeA6Lbp3ka7YI8(7We8MA2RiRrICfQSL0SnAJi0Cajj)gxj3vvH0EmaKuXJwWsTOVgNDz5T1OKYw8LEcoPA2bKUtlOi(ocEEForu6NDY5F37U8Q3)Ylqjp3amysOJBlY)ikJ(scn2OXLFB(kP2R7KDtlPVuQ(HWkAgLW7XoRnOJaQGGsl4nd5URTOqtUMspMXrrqtgM1jIiuv9VeRX5TfKpMM6zik0GlZRAQjMnXIaPYJ(d1PEPOQth55hM4ZLgF939J1Uos5MMCqJCTJbRPz53Ct5xgm7G2JaXlWyrFbQNIs9NLjkFB(1fCj8virocVVuZdP1VzDj1GcNdjxiyMdBQAIKon77E3PV8IRo(Ol4VwOtMuI9iYi2)zMEq9RmbbtD5jCCF3QfKqX6B)a40K64kwma4U4Jw1gk)b2afCK2Agu8jn3VkVT4SgUTp8UZF3l5k0pMa8vvf9flpRSQQSRyrt9sWUqF90x)0IQ(CukifV7nFDNf81pRNicObUAP1NILRM7c0itKcTfHfcU6uM(t0uFnzkOrgedsuH2G8HnJOvtpW15a3GyYfis8qDCe8uYfEV6gY(AsehQ2Ma)goQ3iYJEJaY9Q4aYhnxYDE4Hf7HpIwbFUhKp1zUj0ZH4a4YbxWnICLJCG1b)x)ePoSgM5g5spP9IXHwhjKgh69qqgCJyhGdczI0Omz1)iw08AWEB6bpijpsXcfXnXnaoPQR64QfnnY7(50R5yR1SFknCOuIqJgc9a5okduiNr51CGJxMBa5gRdc8rehzagSfXaAa8eOb)GrwJSBaCRnoL(p(Uiadj8SejDEbanIOx4NRJzqmhwOucTrU(YUjhKsU9YJm)G2R5ys9nW3aANYJjcYc6MjwWzN9HQPrMHZbwRzpeSPyeGaxpgchIDTRtKnXbr25JOZKIierpbwTXKGi6DqmQuRzAK9Sg5qefbYUd8yHisdUiWwdacIYmebaGSsHwbi0cejjGAoeGz4XimriqqjEiKb8d4H4p46G2SIH(LaR(imcPiIlUHs8h4NdXUzaXsBfxFGi5Gz4ZKwj8woKOlSqS2G)9(gmcl1AZhZuw(ews2jroec9NRJCzoVyaOtbXcruPEeH3IqH7KLstCyZQeb(Vu8FIzWdJQCDfffAoaBCEaOPzAUuePi3ao(lawOa7GgHa7iSvUUm3rympY0loakPflnxe6nMy3R9yaFIdgQqHQWhcmiwuWfecQ9iW65smCa9j9panFK96BVCEm40woumtyg4dATyMLkmG7Ea6TVnBkevsus0ZMGWsreiSWuAFY7ngrqB)9cLirBenSpcAwymZzIjMesJDhX)R4lWA1E3XsuiAymPr4L519aLmn17MPutdmIzBFCsXe9jj5HJ4glZ0vIMhqde0crUdimcNd(nAleWbJZd)QBaZDIWzBXRpsPeJyDaXajifJONgCk4kAQ3gksjxKM3DlLJ32aMBllFxaFfQKWr7JcmmeAaTg3ieVxscnlQfsi5D1a5bK2SBQiEPse)bq1rmty6KWkQtzz9K0SbjdekFRufAky7T9o3p(qipTNH4xow7mRgTBGoKeIlvJdPf4iD5KA(A00nGMiwSil0gAA0VbrenIOBN0jaVcL6iQTBH6qJsDTTwzNamnTVnd1EupqK0zUHG2NjOzAu5mkcWoM0vOfuYp5iP47MDb7q6niI7ipmQKmxaWylTs9Xy7NAuqtGcOaGL1Wh1HBIemCcfzbFT5QiBXOHkIzCICGa4y2IpAHREfX0nBdY2TnCGbNwU7uMLIFKWB7uXcgkInylaFrfU2GJr0U7LUCIfk7qneZKbDMpks3Xm47fHbn6evZyf5InFKIVDAQhtLce(irkBbZ7ddj3N5MkMjyZ02mRsZmnstpuhhZk5jksqSZmbboAPaSYUqBjQqtwSyGfoFqI9G18tA1S0wBdk3TnakHWe)N)ohz1gK5L2ISxn10OLloASeMO3x0KXggtQuTv)ocpSDtWyR4WkGbvoWY1eC0w4aTyMznmqePyBU3ELTWCQJCdzNguRaBWW7D6UIwE4iA79T851IwMBaKhaCCk7JrG4qcCzeh7PYQGiY3cLTRZz3cdpibg7xGL4cKnKBN(cbHmet4wvGOKad2I9Ols2Z7BRQ8yfw)TtohL)NGQEFeG8epY8Z94Mc)cWOLTlOKTCOT5ZiaxQ0RebuqcgMe7kv8iP)YoYBE(JJ9bhFKj9wjtKBKGtoevqC0hQqNYPdXYIL0IuIVghrS92Mfq40BLOWfi9l3XDrsCOwRQY75d6Yli7g0hsww9aIXSkC(85EjhQsFXxqSF75wVd(G7kYR6V79fTigyCGU6BwHNqA6JQKU7MMfRLgh5qNdXZdDfPvfvOzCram0BR09wsvmRFLAT8U3FcFEmEzlKwK73vxIq41UEvF51v8z2Xn0M5cbn)PICuubiXABu3Rbbud9ZvKflwlAF9CPcCnz8OS9uqGlBwz6JpEoz5RBZpfDUYYMAeZmjEv4DOvD59RAA7ZR7rZYK79yChlHhXu10ZesMEs5qUcsyKM6(UWWS3GT8n5lk(7hTC551D)DRq()3VVyzz(FNF0)orP0w01958ho8YlLtktJvbQebDt3vLoGijKTfhnq1XUifOwupybYfu3QUEtswEFBZIY(h4G21MxU8S82pQ65MAqeJKUvhvt(eeCZQPzEuVCYj7(8VCkd67QrKpj6YPqX9sDtgIzHqSXR0OTajVo37xN2vY4gA2atN0vu1DrRygZlHhv3gVy(YanT9g9KkIV8(sPRYnGzrwqBtwXZsqMHY9II8LOh4kKUdrZ3F4yji)waLBkA30xMx)XJU922MHgBdr39pWbAFwZ1tzUI2KOZ0TQKoEfb5AwnhhXCeSVTSUORMHcXebjXnF(NkARYFqJL5nhsUS(RB(ctg9diAEsu)z4jOVhs0lAPpGEKdhC2ww7ChYHauOH1GFXj)GRSqFFZ98seq(TXrr7CqN9H(8fF8X1PAcLTm4EvsduBnAI45CdHk(w8gyXXaBvvBsFYuVP(eUdxn0oUi9PGCaHW3v97dTKlUjYPexYn8pbngpEZy1xTmKRJe3fzwjdsPzKN94VF(o0PxQ)4RZ7yssZwGBoSQgm8WPsjM(sCKAE1t4tGXMnIOhgPBzelwOnPkVdLAceTiusJXr(0LkNCcKXXFji7WFyLEHbwiSne2ZAago450jl39ducnt5O2YfQF0e54JQPi5yHLLZjAHCsUZOAGGzA56VhAWhbZeUoS93)6MK4zyLMsSybGT4E1km4gX34ljuImyL3Ge4G0gcYSHoExy2hrpSJ()w9NlDh2Nhnfg4q1PiUyXGIz1r0zAt(IKZHdRwlh35qXRbjBm0wrqWOhkA5d)rzPgGodkR5JxEZ7QdMchUTKk016FhCM43XezdapEudQBO5BJmTZmgQFNhd63XyezqMBCK1bodhATLfIK5f0lMKDFzD51KqgdxyAYqF(2JCRq0U5CyORUJrZMsQvzXctunQsWv)2g0f2gZy7oaLjFk1dOCCaiFgG9Ggbkc3jAwJdZYGgeYIuIDGjlI1m2mLoAK8hrsM1KG88q0gdwCTFsz5GopQQszzHC80A1CISdvpF1Y8aZTCJPo8gPU1avrU7QrGiTl1abx1z1jjpausO7zIrz5x310E9jvf51IMsb0GoDUbiORm5e5QTmvllLNk4Ccpk7hcBUI0xmL9GnWx3r9ePqwNLk5sJgZPh0dWUe9zXHdeooRUyDFBE1GQQDtoO5X3p(IKVze9yj7L8nyv37kYBF8uHWIcJDBdIKKKnxlluBphJfgeWd1hJKEkKr8OWgqca4GoCq7(TeKU)UoZvMfx0bTzoJMf5GNLglQKefJ1cAPXEU2tcSBM9pB06JgegHpXSpANExE3DGxt5s2qJNC8IZuCvTjtM4vkFdeukZhzHmjINgnYVsqO)MA27sv2QmqgEAZAY1m8XeBaXvdkVzuIPL9BiT4EIVAwhY(i1XBpRZudYV8hBp8GFHsQvWYVtSs7h3qT87282Ixwv2ZDTwXYaLXRAa6(PLdgCysC4MLYp1YMrmVB6RHcXmwLi2HOL5UU9tfONJsmKAYcXo8vFpYegXbJbUGr3RcHGzoZ2vVcSYy)Bs0AsPPC)p4G72tCxAGHx)f8cxz3GecaLJ)cZRXnuTR4QOkmy79OzyqrQ2BxfB3G7og3FzDJKNIlECwNnYbhKKqGgzoAY9LPw6t1ZsILvUDnF3DMuwAzm2(raI70Fyv(c0LSzDx2(mHazP0WkkJyZm3)Wo2)V9)8PJ8xuhjbK7u9TLRkwEWN8qO16Zxr)XGuad)6G3WsyCi3AuGbXlIbBlhaqC4PgcbdTVn5137LCEIq6KgMP(VSXKQXtw2GmiV2kUkVwhPeT)HS9IkEfTpYkInOK)DntuSnyFPkxs1rJG0QXeNwkTfXVko5bZes5pEuiCguhy1XEfGbStXKmOKMqL7PB4jRXeT5u6nUDmZTu6bBKu)km8K(vG6iks2Ei29vYgdffam34UMU(sRi55mO7XDWul5q7jrcIWmoGl8yrdDrf9tIcUyDjZtQDnYGAezYUHQgD4i5H7Nm2YsPr(T6oYqRHySOKPnYP29plJnjzsx2UdrSG4LT8CkEMW8mYgJlBwzVCfJuK8cwCEkAqZy4aG2KkblwWgQpyMZysLjUCkcs0FiifuHozVbiq7ibinF37pHtaw2qws4mhoXXsuNRZLZdb02AROtlVX0Y1bvhbgvIfNeWtXZ1fMqTjwVidO4Q7ULsJfGVDQyFA(953wCwbKtH4RNT8EaksZUwN)Swrxnm7(8(f3XBAKiPVB99xloSspFtZhVpV9JD)Cnog9VPo8BQfMbF27MhL(l7eX2JLgzNgQS0aAhJGAbJvps8ju5C3qU3Jx0Z1k)v5x8O6f31aHX30wuGvCjmKIzojJPxvSGfDBSQ2eP)e(b5)0CQjdoTnzwPbWK1S8So6viXTlBhc8SyZhYN)zJFnFWid4t2)yNWKep)qV0axYvzTfJZ8XG1zYhdCVN4ofqgBC7AXTiO9vLvvwjAlV40AOb0wd7)wD)shaSxddUUSPPQVCfyjCqxuFZg0Up5Z2f87LWNzWG(p9OESmQe11s20Dl7CJWNPw32jnEntdkPeoBUaUNoJXb7xQgz2Km47)rfse5YA8HIQBuxjdMGKxUyhO3pYUnfJU20q2GmcSQzVeYs5AwquYnFMTEMnHvbrvIae1c0xTS9mDJLN79qIXc0hp(2NeN95Y6LK32)myOjT0RB)GCpAy2gsz862tpdhQLa0diRX6B(WNZxjxpdAytYw10vIyKPUtjEoXQw)XxqsaLEOBuuKxyACeNzBMg0NNdiTJYQAw8XILejHU1c6Ht4BVRhGg39CN68vo3IwEbYWxupXeZ0P0mJoDqnF4iMzgKdAgYzALprbdCx7NqY(9)bPflneudvU2dogfpH(k0R1xqcgBQkHVwEq6vv1Rl76X9HfdZ95FHeBlNALYF(neGjcafyGQfkIJYLeR)M6lYlXvEJeTIN5O6sI5cxalAsP5KKEQIraFgIQWs2HZHZMkNVkqQb80113wWxuEYGaAiLB6GB2d1KI8dDDD8irAPEQG49fKcIrhg45Le6gseysyehjoKpn10HWigQStaIj9s5WioiVzdalU0w0Yq2Tdlow)ZBzIwrZQfMNJ1IauULytpTSfxojcOeKD65)13HfiRrHJGhSwMe2AJyMtpkFb(yq05Rj6O3udjxlqmjSovCCx7z(ZHvSg)4YF25WdQ(heTHYhzlYw0Wy)q8(AafKaU6aFVy)uVqPDAIBkMFu8Ho(Xij(LKvxn2wwQZN()MQgLRzczzhTNP9cWdI(csRSEtmDdlRYHXEG0xm5C)g2mAA0MCmvlNMQF4cxnVVSUzTfKHcD3DrEVk2ZkT3J0iRvbZ)Kij)M)5)eQzJSnX6esXiUisNLxtMAblBJZwS8EWGY)UCjdHusc8aa3X4eN)R3vu)M6C5(Vj2ZGlUP6tWJOf(tg0TSOlVhhUprnlVcpg07HYsbnpY1SJ0kJZwxtMPUNpIXughdOxHe)xdX30RESs(tCgPO9csBctLn2cmF0iBGcf1gTJPwvvjjDOgvU3tK3K6o7tFA0nvBhvqS5QtlSjISnxl(iljBWj0XgQqwxJCejntJmWAKn45yT3kmtNArFK6uBy6BOICYUt8qf3UvEw5lfQ6vVGbqkrphkNlYSfRUX28KKjqMlBSpkkcHbHdVRrIEol(StfVeXok1SESW8t6WvMtiQTPXsAQOkCPypcy1gSxXgFQ((TQRXweh2zkMu12uirvwTiYpL7CLq)RUPw4Da8LJrwAgzNtF5cu0uklQ7z1mYfUYS3LRRM9Nr2)u3lIO3OpmWNoWSnEy5ITAtaQQN8UAO4OZMwn)d3oFLhd3LtKdAV1eaYFRP5E(GYuGesyN8hkWUi8ZGS(wTKAaD(lQI)nlETB9koZy(2to9s2mPP1gDSh2hswmyyGHvDCjwUmjmSXzR7lR0PkZxd76g8ls2vrIjeZkKJdvO1uommpZ6U610ZHYuSZXzFNzhSDMzbCpWkBVV3KrMijxiLibEJmekJFZyPhZBgQGxBkpEEb4JD1ytw7jcMMPrzJ7o7lVyK9lE)7iZ9GOrLHqks6bU6jIl)LYqBQyKBAtUik8PZBVDS)tuBmnqWcGVAnXBYApN(xLsNP6FvHLH0D(9ZfhGDqdQySdZy7xMk9ymT(ah9WMDt(5Xuf)MXe)vQjEdvMBOAEt(xL9AQmE04hOLU5zyFnksS0D(ls98i9f)y9Uv7YbJtzIg9Sk6JzufpNA)5uppRTS)s5N3Rc6j6yuAO3Tjxk33JZAGhExKt(bRoye2AoBRQjb8dNAkr(R7WOA7R5C8dzUaBcx3NlxvyUz(kdHjHoCAdk1GOnm4XeNIf3bdkhcyKOHCWteDsuErX9L16iBjjlnY3xADO)gLLNBO(DhQ0NZw35KUWwYTPbdm1J6q(WHe9bAVUKe1oy4mYyATdrNxt2sb)Guoa8kS4)lmqCIPjBx27J3nG5ibFYYCCdZeN4469eI(cchqv5p9t5TiGpZAeB6aTJesruhHOTTPIUmoOfMYRXit4hzB(E8syqWQeUotWpyPpQckXjmDgxHfCgt3mkfuMvseoImBkTrvlKT54W8tJHUF0aQSdFcbT4a3M8IIZcth)rhB5wKmtEJWZlO6W9iq7l3id)EkEsSzYtn5irMXtINQ3)Z6b28sXaU2i0rKhS)WfG0PGTZ(QGRIt8CIUkYnEEbBJm9zc1VbZUfPWtRdoM1PcnplVuq2CYh3LtkJtLqj7NvKr6OImiSvLN9tTAcF8yFb2UCms()Pf3uu3rsjGrEZ12r2DaL2MmnBCPHbr5l8GTd)QltlCWFFd)XC6j2mTbNgo2OmTdntsWtRB(WEeTnsM4ELST9GySFdS4GEQprqvAFANWBJVseB4HJTvvZKsRJosAvOk1hHUCE2YPzn2KH5I5W2sv2FPMCns0HiHDIw5zS5ANrmmmRU4tfTtfbP0)t8nVUC5YI6xCYPeFJyzf9HxD1TibpUAHOFDl6kPhSS7BXdkxOUTWdzrXiYchcz3wdQZoC7FoBI)nrqC8vUKG4u)Rsd2IfMZzL3Mr0DesvKZocLnpr3CICNk5FBEuUPYZzlR37WGY5iK5sz182rs0iVVPV7f)VEXf5lkZRMjoxBvH08HuEg5UZQBASaqjEGBiE(Rl2YpcH67X00XXdE)HzEmF2GK79lZDIcxZLAZBBP7eW9pUqppRu7VErVip5iSu2TQFYNselLz6ziSLtOzBYEhBRWCwGWoARowSzci9mcF3AGZF0wuU1Ot)BUbL6a3EvcjhlWn09Qu)Tyr52mICVUfBZLQLSP5NnrH6Xk1IyM22zVnN4ljHO2Q)WBEJzK4SSdHyHdgr(Izd42uZr30yHDzUOvHn(3qPwBPvq914d9MNSVY75Vs7fduxjB(uWmEcVDZs3V9IBZT3XIN2PqWrC975wwSfzxJvumJGS)fAU4MNI78YWW5YZ3)3LfhRcLcxeSdvNfV5MFGJDZ4BQLjrQ8v5aPuHMGkKRK1wdQT0LsxlxqY(s9bbrEh6r)l1XXp1rQbyZ59REgCtCo0HEwNq3yjFmEkZMVx6HP0)8tsJcs4BGhU5rIV2Uox5M65fhFLFi38LZEO(GOKdrDev)VN48HvlxhsL)PUxJQ5ZwuSz7feYVGh6icoitz252ZePkKukh4jWgNK4y)ehPkjze8Ncb)(UExfKy2CE8fA7PaaJLBdSv(myw5XjhMKKK66fHoFWtBCzT(kDeQb8jUYe7gmuoHiUjEUx5gNywGPEC(59u2UEo84AovudDESZHHHHeGgToJN6O67hdAEN4Oa3ihVVbSFsA2sJVFMxye9ZKS7ZxTQS(wobvm(iizxlcbAt9XR77vzSiN1mizVv5VO6bYfHuPz3wzN(ZdIUiYtjN)50)h7vLZG(o8Xm9cClCEX)NIBZEXPLFQSU4fVFD7QMUI)V4jVhvr2OSJo5Y389Vupnwb4rszNx12C)jNE2RyPmHzDfvflqvMv2E0ceCHzr()zCth(NUnnrFhL(B8UwiMfhlmu4Q7KZVp03GR25pJ764FR31)XtwwqMBqeu78Nor4Ohy(B5M(pM81U)jBxRkAefDFSSwUz88D9YxFWS46cHihN5SXnQ6IIUM1Tlkm53RQKGrqW0Sk(snU4JidbfRsKIYWBvFoNeQ4Y0xV4b8mYnC3l72flpghZDEl)XYRIU6t(sK2KJsjBjjm7ZR0L7lXEkRHWe5c7Rr1ONGtawyZxy2nLvvxGKThDne9)4BdQNuAe4tzGZgZHmW2SjK7OvSkTl1r43krdiVhXTxy8nif9ZizNXabjmgkWI1ED0sws0IH3uD7Wu(uFxEDDrfa9ark7k6n2CxnGJmWG0S114MSmKX8FngUhjDfG5oKJH7nJklPLc33IpIAxgt4HIPN6p1ipj(Y)y9bHikdd31bPMYOV5SJJe8a0b7D(C6d1WvUNTGURX4Ptopxzq)WkA9i8bB5OUvBsvyfECHnHhEg2mUZvOjlmdMbeOZOtCVaw3oKnU647YuNsdF4Bp5unJJSXmuBcIyaIaACtHlubRbjagSbIcb6lnDfvBL0C3MCcomy4F0Jb)UfMJxE)kuLo(qF(TCLkCyafYwd)cWlmtVqIQiIjJ8u8dNw2IDXRp)I383o)DxEK0izeKJInIZgDfZc2ujC9AtgpWonHrM9972I6cv5tzJwf(O5AR3wXPS4gYtudcu3nmuS(MlRM3wcFlLvMPvnQH(Ofl0zsQpGBVGULCqsP74gRLCX7TkYE81TinJKN(XlVR4ECdlMELMg5oQu8VunEgDYFpJuk650ZUG6Mkpsl5r(oEqnO5XN8PrOGls7QHNvyi57h0Wf10eroBH0snHAVhp0Scf28Mhazq69gtLoAvPLk1W5TMkX6hX)V59ICh5p7CQ2gabMeOVz4sdmLRWCShBarmsjux)wZUsLsiEd7Z3VOxQpnZiMGe1PbhwQK2YvFD(J2Xi5GRdNXOQoXj93brQAlMzgmQb3PKaBzgAf3QCHguA23wFZj1Tb4rlOGJzrC2Q2Y7jRo(DHTv13QKA3kl1CBmSYTN0YSIrmSHzRkAxTYgnAaO7LJfnfkvJBKeXkcu2H9dORXXfc33CZ7A02cYR9PgrCGBGeorV4esg9Ede64OkRcANn)2wKFW1jO9i)yQOO)vipzoE8DyU5WsC4kwXx0Mnf5TzzQYclRX8BNdy3s6ucFSgXXMtl3HQXczMp572QvuBkTbvncT0M3N32xMxPBnvZjUYDNkXhUm2sRau(hRS4jjuZsGfBd6tWKfrZ(Kkn1C6O3LzlOEN1xGlsj7BLTzVJmO0(gUPUgs7p1e2Fw2ZkggNfSJTfX22B(afK(nMsA6MGALH(dkzXcF0HjpNqeV4dJJt4(lTC)PFcb)xorHnnZkrLaKlH9JUjHUE(r(orKPCqRVAjbJJh5IOIS3CFRS8UutQymmWsPlN4AB4l5(K1l4hv21Bz0NCZZunQUjMckkXmFO1J6WLLUVpVADrxNtMGxlw8Mt5YzICeABJbCgEg(sadhqkVP)LvsR11wFaUZ4nFU226S31yUNJBOsIeiTQCL(oDlKDd66mkJegyvlhfxYGBQA(S2Hfj1gwcPFBGqf3zu3pZXArmucAh5n2O4d3h3byzAAeQIpGYiRzSk1JSTzDE7YY8A4l6Rv1jqvZ3CY2sBbAiliXmOQN6v4gqZ39CLNZwy2jwoteeeS162NUH7v7vBsAaUM8EjobjOZMPVwSklVAxxx09Hs03bX6jXSjFtBt9nRv1MFzFiSoPyfPRtxPhgh67Kef4Ms)ILMLN292LgrvNU0BQqFzQv3JJnOFabdFVpMpdDvKvaDSbz18g9o9QipBPIXwvYOlrRsyLTMJKSMMfdUcz0yWN5iTSTQc9NChxnR587g)IxeSmSRSRhFJQcACw(xKAbRQgAhX19vvXK0QeGso3JxQafuh09Gomok0p0XpGRmpH8fIqNn8wwM6XvffmFiChSBOG777Bk5c)GQC6NGusTQ5AKAHOq3tRaPyC)2MBVm)Arvb72)I2MQkjeF8Fx03JtuL(ezjOfamuXDubzc1bPZA(exqjLysG9JqL4hZjBKppXQos9XCtToi7QILL9O5A(UMEAnFAz39LDDSh1CD6)6HmDxDBZNffRUHisLueZ)qiSqDhzjXUKVS40IQ8hyX5dfecKgU1Rw3FE9LnC9gYNmeiVZu8o1NGTVlxKyID88Irxt6jPA8G0axyDuCGtGlArAS3q6IoRk4zjQcDbx5JoVMRdsQl((ajJ0mT3abjDxbLloO7lu1X1Igry8jnRKc6Hf1rTKCfKTDR7RikuUbNAtOiiCLbQKgvcDoPPqFqKt4Hb(EoK0exh2QTNG5chqVI3H(bHrb0RRQ9)ezNSx5AAi29J2tImVn5Ye8MQwWifRa4z1WUxU9A4bgv2DImKgFOVTO(wIyvBVTY2oAiS4xvvlbxMuKe1H(JCF(9RuXYjk7)6nz)xN9coirQ3Z6sRAYMCvfptFwaSOLaBrl)3nVLTcLyr7Rkih)em(cyoYOIT(OptzpKx2svR5WkeOOuWdshDjmr0Mnu5gmfQdyOHDrjavkF1WzFlRqcTykrgc3GP4fOlIpYOVzNoOvkCe4SM5FQsIvR80nqbGhpZMy3Ajcim7DV87XfoFWigrq9AP16FsE1IZxj96w3SfTe(6vLvsnbmi71fTnCu)(EuZ6YrXIijJKME)kvLJWj7OLFIm4ADlZlgKHYzf6b5e24MY2U(lwxFAtDbY(lcDv10SSADh0gmjacBUK5WyUyDBh3TUhfGW5UFTZK4(MUc920OsK8R7kgxDONXsQTKQWsfM(KY2fsLQ0JeukLuiL3IrzioYR7KOAzwnCfgc9of0U5zj5OX58fA36)QJIFLs7cI()q9qioRfT8D(PQr5xJtcELIoH5D6ojmlNRX4s3d0hhj1UxL8no9rSkFf)pm)7ynjsCgTMyLK2RjsarBEjuNQbaoNCQx6PZbl3wzUtc2moxcI8fRNReWdh3iyVetzNM92YQhwLxv9Wlo4f)T1v)V)Fk5YSMRnFa9bO2Gtif(36qPUeIjjN(7u5roW5vLxJI)dxruONhSmNLxVoV6OLlvbS6FSUyDXplLNixzUjnVD9D7B2vV42gzuz5SN)DUCzXMX8SFFt9hPP(Y7AjqW877F1N5OS303vrt(EM4FTb4KcqSLjP03VpO9V6tD6GskAUpQTi)fHE)RGoJX1j2QipRefsUvSOt0siKFFErzMuw94EUKQzfI95UpuEzx3JIk3GHe0WUU(22M1RkwkjrO(OGyBPBZVbMjZ2Mn3Hird3X5l(igaPdXdvrWW93udRee5BCZ0)lKedArYm16(yfkZwKbAIg7BjyE)3NVUszCeVOKLepZCR3QQdQOeJ9obZJiT6Qf5RGOKLNtYWXhfcVh4QKK2OIdyD3KNmnRkQpRKCh4SI61Nt)6sYg6tQq3mHDuhRwsEaQ5FO)43JOsigRA(gfGsmIJ3UkZK8ZC9qDFnv6ou5liZ8Rku4MAUVATrbBmi5jM0OPHSf3sbLmuYtAekun4Jb1VP(MgXPP8pvSuQ8sIsc2giYzT)X68w0FD8nGkDhBXdlOnkirBC7PqYNc4Kz7PCJPJD1ctPGjM5mYiOwdzcv3XfvnF2IUsvyTquUiG6O7(Eid(XOQG(IVDtQqxQux)VbdxKdPhv5XvszQumUfvpuuWauSzajso6ILZ7BlwuYv(t7dHZuyjLC1EeYCJcpLqkpVJCsw1)TOx1qwxZgKHp4mrrkhApZMghUfwSkpNikjuWOLDoxMgyIoEYu1omcAkQ1gt4BIKip4gmSelrTRTGVuCa5EDjt1WVktYpra0bwAzvHQR4PL3Ct5cINLR8yBA2GLTRIgvROm8D1L9VQf1BorMayWjRk6LIn8GzwC15t1wCIZAQREq6aqQodd4ALMKKQgroPKaI7iexG5nfUwtT4WmJOgqmuASXs5ZfTQoVHY28zBOqJm2hg)ZcN0fvrfSFyXPIbIQFbQwYdgXQlvBJQd0Qy2LAvZunzteybKopHohM2F9uvQC46N3QuUTbysCqg1EZ13CJD1PZ6LipY4sfUQlQifhxwyPU20BAMIcXPPextyK6EinSO9Uv1Rr7ElAeChOl7I8hw2xG7SCxbYfaIEZdUWIagkuciAO2ltHIuqLAvEHzxdro8AzORhEuv5TdfbqsMo)sQqwz1KqT7jqOAsIzDSRJ69NHOzysuFejfG7Xa6saRkjCm1BAgdQInH0Ga4mw5r1aWqC6SOCLo1cABICV4Gl1QQ(v0MGkKSMFHVDBsexu1jFHPrqws(sZYlnDEaDr6GG020vgsFBeKkfTautvLXh45KExIzRkalvhMIfERY5iE)jbFtPUXQ7tkc4diPt3EhHsVBFvdv(HN28lvXR3sMHHFtetRLAWXvYlZd3fE1gXiIrhnrUTbWL)xE9tcrMqYOWyK8Ev5UyeZVHoW8PJwl6226PLDRirIKimMBIXEgWPuNigIGct1AQY7sDVCcN0Mm7wISKeOsAZOdf24nKEOKBH76fHXo2QY6Q7MK28pM6tYOTVsqDSILzm3pK8zjx3qIsAQyvw3avlQEfHu0Jfjztfvr2Iygg1Yyk2uwhQgtL1(F)sBjpBn9wvJQyfpOHSwmNvxkAvcCNtA2gy1bDtgYQTLtH6knKONeAoiT4SKiBfq4ZhleHXXQ0RLlP7kT02sxLmpXWZVT67JIwGnmJle9cblY4e1CAargXH)OCDWDgu)9d6(L5aKDuliuPwf6ig3RjI8T6dww9(UioEXgzJBrtNAfc0IYWaX1dBPEg0XafLAhz1dE1vy6uLWQrY9upUOu3inCGpJwL2s4hKURwmIjQtAYg7RRhoxBadH9ZQNFmxS1(kSfJmaCzHe8mnD0hy)rGxrI1FJeXYfNRbLedYEnTqGzS266(RzsACGnk4P0sDqr4ECMyt(nnO4DIyETKOrDzV5SQzEviWZqJCf1YyUtZf9n6Xqej45McrUiUKKDrBlEanvyl7n6BvU7AkLXOBTnFtlCC)nuiC20wgLjCIP2hXJeoTFPxpzBL7J2uhFv7PDwtDMv)pIDalIAtfCwWdTTc71(Lb1JXwILTczIIhFIEghHLZYOJ0bKXOEMkzVs)1OheQW3ZRhzgRa2H(65S2ym(YiICKgpnvZMA8(A0J9RNMhvOu09zRrsd3Hwa12Xq7yKR(1kUpAl8Dm7UkjVKKrFSeFvJUKthAXt1i(YV2wZ(P2FTb3t)oFwFwMpZ2MKAK1z0yUP)MajnyDZeR(0o7Q8Nu1g9EA(bISQdT8AOnwLdiBZzUnDBZ4jWt1LTD4qM0NNjz0QeWWbnUc)eVy3iNavZN32VmvWCmIfTmgfH586JVDsdFG(mR(wPUjJVtnQIfJkJL5OnbqMYM5nPGgFEuS0aMcyKty4MPVrx3esHTKQm(f4TJrLMD97CSByC25tpQLKQH1W4M780OTmuO2zpPTmnvVhM3bcRg)Rr4NXrx9RAHzM3pjetoD)wAK6w79TvBaC2ykoNdOt8UAhTnHKHqtyhEfgNW4qzxXwjoN6Ag2Zjwc5RTehC(UVuJ0q9b5dukhgahS8cJphB6OK4Y4u3tgKFy8A6j4W7wZMwq)zlrqNXoS0LzTZDl(LTJimnxN14P6IKeW2nA7b23lf24(yn8EmLVdIZHk0H16icBl)vrOVnVJmd7uE0nDoYM69PgfXT6f2oCIsmsCQ1)dnYXbFEK24Oe7yPngHOOgVfA75QpIs(nOc5jkTiA)v2iYaB1xge2DJkol2(nJm3Gha)AhrmAnO4kNQLg1ljTf3B8DtSwDiqVFv(FT9azWzsH02c36rase6Zft854r(T09R))T31AtnUrZ6FrqPl2swoFIe8MLAb2TaVjV5tucql431i7JTCiCsL)7N(2CtAgBliHS5esLQG1yllntp91N(Pnr)3JWVaNPOvSobR7lX6(dwdvTYdgE3EJnyERje75vOunADTYpE4i6FbXY5Z8fE7ATW1nCUUtL(xNO2yalP0g6m8VnhlBBwxZiUEsQBNG6WQ70C)wYonzBvhDhT)TTSt7nt0(dTldeCkbF3pP(2z3u2G9jm94UTZ(7BWFb0U1nfW7BYAT81Qve76C(zfbys6qKxIK)JmI3k)NIBSmyO6vwn)ZlAqoFJ6bdUYJ9r4UW2Yji1t2ojfukArWWb72x(eJW45LXrJx3M)n5B4agfMKVnQer0hIwPvOruzTUDbjPoFd8ST1zbNXt8lk4swhTtLcT1D03IcA)z9uvqCq66COwh1N7jOqvgSDGODpi5wGWOdlgLNHtgWi6xy)LBfxkjE2kUuA3HclqFhsltC8fx1SyjTTeoHVoHNIT51skmkcMlTdtz3XMY1eONXMU1IWeiW12rk2rlSoDPDlZypDXnqg4cKY2Wrl7l809jgA8KPjgY)t9bCDmz7lQKuBfzBGetslKwddFPMiAzSFP(aP)RvPlmqLS005FOA04l4nUz2iXqvDkDIIIKT9faneQMDa08942cH2nn38O8DlbT7jKA3GWdw9XorN3kwiDEQuL2IwXzFWSRa22Iz2tD0uvbUtfh9fTjHqOofqEh1tKf4SRNiCxJLTxRIrnRd7vDY3ocB8vDO(gPw82cS1Fq3bQukxrdpbFhiJa(XQI3q8cNv2xqWZbsJYwIPEl1QKS(STiO9IFbRer1kdIBfsj4kD4aO7w3eWXdVbi)s9ndImSLjFwLkHns3oKftEMc(RKCchDnISNRPgKMO61eHYbIIYhMnQNT)tAb2QX55fJItsgPAgjA02ycLh(wqcuf)((T6dIJthqdjCDlM3LJC90asC3AWxuNl9bj5m)VMfhLoKygLE0)sPfmt3MhLLMitSCeFjC7zrRpjm17MomRinTNx(dslYomoooAykSXtDmgIfrC9XDBioJb6QzvPhpecpYsxw1T9qEAOB3j)WQFsUdX(cRv77IVDUzOLLyANFuu8qCSq33v9UInqSzOtcuQgTw773fMwjmqOeUrHLErYlBqQnPg3JNDW7hoPu0dobMHES7CWGrclqLKpOqi(wmHG85W2vUzX61Q26oJI)pMLxStn2EbYtTXVNnCo7ysMVKTq(vayIfaJLUOvkjvsrfhwCRQr3grJQk3Gm)M99HGDkV1UtbrQ2GN2Fwv43Dapu2c5e11BjF1YOdIj7GAIaHyWqrSnCkdxNyxmaRHNMp0iSLIVALZHTcwSaicmmGtc4)CV8sZxQuyygfYY7UGgulHkmVE(n6SNGS(FgN)6K5SaUO92zrhyb)2zr0COqU0VINfvyBdr5nzrgjh3HezPX0EDgXl9u56ahVOPba46YIMpPkR0)KTDUflC9cj498WSdaJft2DBhPVbSO2p0t3lRQEG4yGkbfW62FHgAdbi9Gi(mieD)Z12z2ytOu7jQAXo3yBD40ZQSUAlXEavls2pu8Es8ySNoVqO26VwVbymbAWoH84s7kZ1gZcBT7K2g0d812h7jMDrI6WE5raS2GIdn1bqkqvlq7U1mZeeWUVsf6vsJlh1rGc9w4(KRWiKmYT6t1ETt1Bhe8gUgVCPI93Tr9QgVOQhDS1tEyzZtDPZd0o62GpZZfxWVQLgwQvGtPHP1xVTdZZbCWJSwj1PzgjBiVDIuF6zLqLgMymAh1dmuCvbd3FGeJS(I7f001zCnrUUCvV7PK)kQzmsapu3VRsmKGE3w6S5AO96GizqpR5UXQ5tknZYXdJKPle6pQ63r)rXFNBnyIVV0xNPlOEdgXL22QmnCus)rOK(sTVhyT0D3ulwwiGna2nHJa9T5zFPGMMtLsFbnn848YQO92ksBsl5gSRzoPMmPXOw1bZ1Ek1Dhl1SKx7I82PI4sf16IuB7Tuq22OVWl(T3s9b3)ANBG)SfeETkkYZQE6m9q0cfW9USyovAvQUJhgvie4Xt2V(lANWplyzEEbf(YhS960BXcnp0hCTgYfFyxSLAblQUxcC2Di0QILpaWa6AgI8HGy)kewJKJkU0AGhG2lvUVfq79JeGozF2lYaCjWa1eCOf0acIbHU5TnqhH2ctaHYq8EGmGDIlGEgjFi0n4bWaiaCAXMBHWnvi0ea2UmgH6ksPbHLAa7zKQitEsh5QT3XWeYt)EeSqXHXTVhW17TFNTmI64ivaICOLkAFD2mbEdlKiW9oFiKi4Rjyd2hb2UBOkle6MUJl9U4D6pnWfWT9ShWf4N7Y9rctmev4gRuXOemtEOGIUN29srJg7favdcg)TaCakGv)9Hd7WP5gg9eUBRgfafxpBoPGbnO)2FSlmc8aAtv2p9GUamWUUq8CRWiaVxOTmUbhqZfEaEp3DJKltU1TRdvw4nflsCTir2yZvm7K2iA3qOK(0TMAex(ryez2BB(Lgq3J3mHeZxUifzJeGOdG3GvR4qGqnCtlBVeOpdyJmsdpf4nDjBtbadaiNoDwzMElKXGpJS7O989qRq(1K2Qskdqew0hYBjqAAWm88C55a3gXwHz)Efm6Uuf4J4Dc1gw(dsWNMkIcnfSk8)JQsz8GHevIZ)p1FS90jjx8p)CWraxSG)CQ6Hh3s66iAqxjF2OiGJiVDLlf6IPD3MV7I)R5mRqnVDaajhOVydwSIWDXzO6EeS8gbRTTFS69mrmqQMYBvm(gJijWkVQIiWVkmoc9Im2E4Cqyb2h2psBmVbVf6aonN697XG1dpMyBK0zr(LB1IBM18eNLdMNl2SQerlMdfhpCC9cMtommoN78cS7rGToQiq6KMmxrmIH7WqP74vJJobzgrIuADOku8(f5nOlQEywno9nfYGEr96npGupPZddYK)JRiw4kzC5M7qMT8kCUlq0KydYThFft4wUqhY4IpeJopjiFez4toy8z1F9PRUEEjXaHjJFeFd8Y5Y7NDdDbQ38W1iThtRTvLRAUFooZWXxa2Jb)BrY2eZoA5TZXUJE04hHhGVSzf(pqU9FH8Dv(WY5Z(Yt8hD04vZAQUQ82)Riwmh0a1SO(Un8acG(RRlRX7bqB4JvLlxuFvv9n3xwJpmfJVz1SLWfeUAmZKJpkFp(KGmgjpstsy2ndhIvZkNV(CmDym5qtnjliGTQ6lvRwvD7ptx)j8LxMvHxTznspkoeyniDQ(iVdEWCFNyjHGTaHHtioflB8dp1aRK0DO5JIRA2FwcBRTNwwDbZyFqLNnElXrDeNy2MY5GKIsgtnNbpGIWlhN6x4Hhu4IZ21Nrjrv8kyVfZTz9iAYZp9PLvc9A(Bm15j)Rfid03WK5F(4NK)go191Bjox4J3uFxfoY75RTlo55)noGfq51j)gSiUE9JL8rD64NIV7LPlavDKlBwv2ucl)Nn54t(8z0CqZzy5JHnKMt9shHRIC53La6T30Dua0A0bDazEjrOi9Ji2eNtwyNP9u24vQJ2M2XIhXx7G8XyUI3DRJO2x4ycSNqSngtw23GBVsaa4(NTepPzqiRCs9r5msD76VIhuZgFn8b2GhTgo((h4PE6GXpSO5r(VUArnn7oWt0Ryf0SlAFS5EqB1zZwVgolIu67qqHeR7Dh3rK6fZDeCRq8mlMMZFDXv4fbp8dkvRw3S4XRES6PvWXxKpyPzJXIVi)CoRlB99L3U4r4UJiRwWWYShQa1MRrTbSwKRrgNC1xVI1bix85Zw3urKwoT8HV1IXRFcu6Hd7d(sFB1xuFiMpXtDgecBGBWPiXUQM6f)pTEfpOdiJTesJR0CzW5GZE53tn8MWVIifCE0n3uTKOTyCwmJoJy9wkiw6C6MvGMTlXzV0LFDgoGqCS6XNLNUyjoKxWhOuyTPzELzQLGhDWbzlohhy5h4ZuDJ5niWyDX1)3QBAM9RwFuHmhn3gBH3CX4Sui4ook5qMpyqIHHhdiRQM)PfZGt6Mb)xx8BJOSpoon9qfFYKs4oxp)(Oz)AGza6D8qZbHrf(M8192Y(cnZ8OjOIEQKMZnXevVYLZRAQUfNbqPeH2iFk9ifYh7y4D4i8iX)LjzCxYs7a0qAMfj8qh2wF9087LUh1J(t(H369WEXkxz8HQq9(XVMi69dgcncAFAvfoljoBZ8MztfUZ3IPFrJaAM(fl4eYjkxwn)lVdh0etlR)66JUEbiGa3gssiyhU4Q6c(oUzgT9G0o8PBw3WoIXsL0f79483bVGQtET4o6a0mWHGmrEYWbfrXfzrukWyf7dZgLLKpyyuXOighDe254xiTijEywbHe2b4XC(MD30KbokhxSz55GZrQP4mNL0LL2tTmq7LHMwbdPQXnniRRjtYo1zNNJZxSapHUcxsznv8fsUi6cKck6wbVtSwFCNYihvnxFN1pK1((If3jXb3qp90xkO95PF4(kfBSJEeunhNSAiPKc6(NnFoRHMys4YL1cErWp8XGZu1RbTdYKJ3dt0PEk23L58X4agc(UrXYzvpAgi5f04dfvgmiMl7SojvGr4VUwtHeYm)wTi5mzA8YfcQWUifeyUsykZZLbkJzyyIsyYVIsvChWOcddVfCw8X5HO3tkOOVCmXycpMsXUZfGN71t(nylRgCOL8JgU3OztfS7CXhpDI(UgwXUv18f50DlOjdxn5ViZ4ddhqBgzzN1hWHwr2Q1HqqkN4D4n1nGnxKv)HRoizHmY6XZwHgjGaxSMFRqKxWdZ(wKoEDV5EAnxE4WbHlzxNBCtMjAzl94RGufosytm5Nlfzhou4bflMtKxYIk0hXATXQD59LowydMv7z91YoyaRaDoF6MEwA0fGAjCwNbNxEyXIM7HNiI92H1s6GNitGNRLCQYVoTU89ZRQOPjdbsy)cKWgpkrYdSXYMUxpo672VosS(IofsTTuMgkoMU5iIdCOAoQdY5XYtIkKjmhQhqTu5iAXQHoL76F46XotBoiOWxg(ko8lgVPA9GigqPaavN6yA1NxRvIq02pUJa7OmRCQeLy1UGZInBi1jo3OsZ83MIMgGwFYhniLSgP1r45LPYC4(U1wHqjllRfQQvE3XWza0D2AMkxsK6D(9v3dHCZlv7BfqZToJ0YcbFjSuqalz6fHDtuY00JgehWhIJMJoNt72gMOtcC4Ynp8aC(SQ(wj9cIjiTHrXSNrIhCoC9cAKbrI8zga9nCehkhbdPHmNyHhhrzcdJmGRoiR)juRakkGl0AHx6Sxeei(SgHAPho(It(X3Zkimc5wCqV6s19mWozsk7P4mBlJauv3H7m)u161XNWyfVWA1Ua(r9GibHBjGpfh)Pl74FM12DUKtU91inQJSZjplsww8Ib)kztJSb1w0IRl8KeeSQPTt4AaH9mNh2GWtd5P4IvZ(FxudbgZrPDT58b7QUXYGWlAWkgzQttC4h)XF(CVwSTyXCLQid3oapBLS4S0rwS5GogIX3h8hi)LLQaYtzsLWeDycK)QkxttVmAkZPKesPjRkltdHdWEwGU1HF1OlzRqkv(3)aozZOeDApz0digRdMHgeIMXzDMe0NVvh1WZogSD9hFOg0Q17VnA6(B(2sfg0FNFB8X4w47M6bAqJTTPlhAd3YBgBGaJXcqlOxlyz8o5NkqCaEDy8pstl1ibvjgd1N7TjOfvClOrMtlxtrQ31QHUqNwgWpR8Uz3O1MLBAYN0cJ2SuyNcxgyx)qttGW7MLC(ay1YKI239bw)pL(lryJ4EjLN9C4eYrFf2j196QKTslWoXuoDNdP3unFUoLBCq0nlOPb6j4yw66sRbI5u(pGNo3rA71oVlw9SDJW)FtZnVwEZ94SLs2JHhwEiKcEfp9i4iE243p5OtNCbifE8rND0po5coKbmW3lQwdNO0TNGK7LLLgdhU0fRy)scqJvlHpJ2rlWH7AXY2GaRCNs(C64NeO6JdVrC1fCvdhcUuENA5NiAivLWtEZLuX85Ae)rMOJoiryHG84IOOE2(68msFKXjxh)NGq31TvGPs98RIXCmJ89NRTdE3I(FjBmGelnpLMxrYWR)9P0)9oAwvkk1jLLYSEqCwUDIXpinJ7()8bfXJOzpCpYDeeLgYicPPdJlgwa6yzhKTox(dBwzuhFiP7YH5TomlLhvxqWxA)I8ftTk4bNDmFYbAIkTtGy6PiqB)LvnYJkscdrlPVLS8pgm4yN9GD7eN9USivwR61C7HEbLtFmPcezdRJ8E3FbTaqMnFEPC3LZBeLudClqf11t13CPeGjQ8elILq5F4jxLJyYeStDJbNg5yfxUA2Vw2urLhKFLvL13vzPQIZDVufhoXuYIhxEeDkHnj7aN5b6asv6wXWtT9sRRkbfrQXd711PJlXSRGdZwDWr7EHmC9JtyNDSL(qDP2P0PL6DLSPBy8dgF6K3Xk4ww6(Nm(h7KSVDM)SrJV(bEcXdBHm0c1kj6eGPRNnGovBfGGShNwntgX48DBIFcIRGeI6sOswCrjLMiiKb(I1A(flV6U3mADbu4NxtunoooW1VA9NQwDXIhPr1KXfjfHYTNPJmf3QTY8cVLXA2SCQzN7lWrzJ299nBnQXWU2)hC(0lXpcX4IlSPC6F0PZrOEF6831pym9Yf9(txCYKlNE17)4P)YVZduoqpR2O5)P(asFawY3B3ZyuGf2hRXjcmPHWXrz)lDKhMQj7CNG)tnF1g9tGyw3mpAl7zxuMbJBEAjMZoueG0IrNbu5JYiKl59rKOP5GPkjYGQozOxRDJBRqFN3NSNIBUlS)cpoEOO9LmOUtj(KXZUTg9wndowcUgU(3RZZhmQ47QheNLoe(rE(OrFxDCuuwe8JuYERzYzc)60pc73Cq28jcxLsTot4BxX4CT16HOpGgkRjJ)0rNE0XNC(FtYug1KVjuTZYDJ1MgrAax4kLu1W0HzPGa0WSIyqqkjkkcIeToozaiTrmZLLqvokujgT(RqM6nLsKLLVPvkre0Or(bZi7Oysaknjb0lLMmejRQxFLrdhF2hp)dxD2jxo9NNC0pn5cYgxxLZETVfOj7Fo23GyEARUKlEOxRBH17kM4KrnSGNdqB(l1eNK(xVM4Wu2WrLX)etPd7RDxdiTCFyRw5cCDnIrXXfzGMjq7u2ObGvoq)tM02ROsRwZfAxRBEDJPL5nVore0vez6Yl(lD8jx(dN8Ptp58jF7irj9II2tnJ7s7uGI8x)1YNP)(eOsalBGbS64IbPJga)m)7QtttIY0UqX(oH5RIeXyoA0kKclhO(lseRy8KF6JFyYfxD0N)XZMC(0JMEYhp)13183CJQ)(Mt1f2YmiimHENNMfnkbL0YkgmSTp5V5(KkNt)7nMoQkl2YnPfO2PbXrjOF4WpZgbQOslggZ1B91oMoToPpDXKlNCXp9MoPBMvlZhIV1DnhDZ0iBLMniDaitLMNMWiv)Tq584W0)I1fX4twLkG0SS4HqS)Pz5GOd8ZHdlga(KNMNr5Aknl9VPq7gn(Y3F0zhD(vGkPPF8I3uj9pgvsmiUvsyf5ur3Ftn0BQH4elWzKKbPVsijloPa0cLeLpikc8ic(VckmTxBpHYhF8fF(KJFtPdMUavXb)NqDtCZWDky)6Tezhk)J)717h38ypQifc7khmqvdobLNdXWpy0GuWTNbqSyPV(kGm4s8SYvFTALtPZ7IYyDT6WIhqWaI7Hgc7TfcGwF3QfpqZiRj3Eh1krUqs1cRQXJFOA1DcEIyqXPaIKBdByqxxXWeWDX48Sb5rdnqSeS4Zy6XQBNE3Qzv13YDE9x0)E8(tqqmKMnea1uSPiBMnV6hLELvWAnLg7cUFwBnj6TZaAb9zvnXg3Sxs3cvD3Sf1iI5zqWWxx(BjoIHD1S5ZAEcmGvo)XYNwt1CGBOqMQZGpNUj6KRmXLu0F98YhO26XTB5H)L0sD49Vt7E6bfhM2FN)MOoqJ5ZCU83CX81RrWFh)BmCoaXQ5s7l6DMHhzqya2MBefvMKA1yB8E5j1)6SMkbO3AmjG3jd5Ec0hro7zaXcRDBwxH9MzDZ0YRL1o8BMgil8Mm2P)0dN(lIA3tEUNKIxa3bA9GXFPKqp33xwxJhjOMnLAVyKd64TjSXFrYvOUbLlZW(A(6Y5EAo6fBAWvmbzNC3XcF2cSf84BC4ZpsFxahEuKDNgtQJYhqtzN00O8m(OI1eO8WbJggNfxKKgLLfvaNF(J)4)7",
                s53 = "!EUI_S33vZXnsY6(xrVCUMheVW7MNOrggJiPouCCBSrOaSBqsCiiqVaOLeNj2)738lZQaky6UjLzm7qf7oKSBGYK(mRSY83((gVK7YAtPFjkjBD(7wKwKvATNVR(FF333eM0SOolR81L2wrwgFWpvAh7y9D)BmkT3VkJ(XvRlkWB8HS6M8QYsx6X9swMYtHTtY6YIQf3(M07Rw3sFsysA5IBQQB4vYbP1U0VeK0MwFDwl9TNKMxsFkEWQRUQjR9xkD4rSjFzwJBYfN92(V7Nl51sCYHhDY7VCn98MdMDyYlo)G3FyrAtZ5znvRRxKzoUUU7r7zhF7yAZh6VLzjypBlxFB)ah)SNB5J502wg80MwA5(yMwBmRY)8Sdc31MJbso7giPgwhx)4y)O(r1l5nV4LxycZEUTa0ExlHkYgT6Nfd8CN9c4)5ee7A541p6(jNF8RE9GH3Xlg7qV4aRyawzIfAw8)83dZml27z19pcTGzji5TzJrgZUDSD3loook2j02oWnERWkhNa(HddJDIdI)U)nW9wjFmFz7nNK2U4gAxfZKcVT6JelGTltmUOQQyz1hlBgtPm3dmdD6CpMJIlrXROzAOzWv9nGA8Y06o(jHo9MS8RVPvwS4tCtwDtAzB1DhuTUCzZVHTuqs6YLvLG)XHOSlkYAUlRo7hoE)fTexnH(WxrCuRw3Ct2Ydx3qV)HvfvG03M4PTjOODYLKKKalqFyNCn97rm01oPM(94qxMXXpP5MQpEqr(V(RhVGg6RFj9HXQb(hAYy(vEOPVGwm3qm(yJLxE9(L53LI1tdrXzhKOHYVy51zVl)xZkD2dRdhl6LU(McSTVi7tTRRZUGewXcsOVJKJKsFwAB2zLhQWtyQ8hmEJxj00j79dQQxMvZthVrdsUSFVSFbGTmWWjHqfVTQjNxWMI7StUNeCbbW1zfVTkVSLG)h(ItV4fN)9n(jRg9j2jFsKZXSrbma)(splaAFedXZJJcusU(VxNToJy)BxZyvmAXqKXJy0ST886wtq8egLNhegcULy3O4aViaE26q2XxJT4ZD8IyMAFxpl)q9A9hZUjFrr2l(uouFWZIxeew)iwSrKsmn8lsnkUoq07Jyqi4x4aHzFo7yT0ySH3KGsVoOPvWJCjgjkN9t(53kY1XAm0c6KFe7uEmi63xuUGKq0Mv3pwEem4rnwSUgMWnud4dEKlhnGVtwEh8joc6LII8JdDSa39JztYVQvSfbZCTfniWIHp1wNQe6TUTTQupzUrp2LTB8mkAfIM4DsaBsO45nw)MI0BN8SdzW88yMQGKZZw9LrEayvCVq2XIejnm1vlEvr1hfZlzHY2DF4erRXjRBYyncP1lpImDe6BGAHWbIK)803yN08VwNwNbLnk9g3vrZxfzX67inr7xuaTjoDlpwxblcpWCD9U27lYWIIgWSISfTKQawxRy1HH2XX6CIsYP5(FuvDxP)EaZdvWkau)Ec6oDjXEADNHQFVMwle82uP2xG6xpOvAO2ihcitS5NPm3(5GoNwHxYK)VLSlG08Y6oT9s(qEZRj9XNw9IYS7UxGgI9i)eSiIvRfNC51VOm9YISL0deMuU(UZR(ytNwrw)5bKy9s890aCj)jZID1qdTvemxQxYTz3Fj96Ys(Njgk89(jlZBW0EbPuVnFfOGctYKvcqXrjKpiND15PLxNXZgTXWkiqpEVSQS1eHig1CTY4gfIGgMBi6h6DbKOFJAqSccGDpoKRqfFm9(gqeEadSzYZoG8jSWxgg53d4VGH24dDtUlDrDfw0S1i2mokGmQa(IX07NbaR8Sxxx9XJYRj6wyocz7ugKSdrMe(H5nudqChph2g)IaJzelm)l9AyhwnnynNd7RWGtEuQxi7Expc5jU3XgfMUkZqqc0ZqBgyR4BnMubAiumxqwgCBzwtd8gLiNucmU7Y0watnqnengdGFhMe6PlRkjxbPfot5)Wq7eBsbnFxCtD16RVbRdhfcKOdwMvkFIWm8A2KBbO5pMQJ1OaUDn5L(3GvYrkDVyFteQ3cmJyGS2yxGv(ztSIVj5RbLGy683lSkcrq32DabJI)Z0UBMygaYH04HeRTjFQLiod7Mz5uTuykz60y0oe9dNLNehjOCXCEYcNMQI8LmtTbLJcLlEhab81qy1q6BcF0)f9cMSti5bepH4Fb5I3n0F)ReVvAbJynKrscCyl)De6ETGtge07uYi(sxgBCcEbSje5oDkImOvPTAA9pM3KFzErE79W1mwmHiQKjJfzTE8eoyrGaIWdmjN(SYI7pUSHDYNvM2jy51I4lHGvgrfblpKKJomdh7SiXB3PSCvw2sq2QuHjyedqUXZQ9dAGxlZTa(lLEgf)8F5vZmGA4VjQzu4U)YRMrSv9j1mqTdPWKvx(Nr1mBurW2v0mVoH500Sb9yZONzSgf)KsyI4u1AmpYiLm(7556yfhfg4t)YJtJZiplu6RgQXzY4)vw9dTFgfURPMTnfOdUmTjqJSLCElJifLVVj9dSpHgbbCIkrggSjpi2Sv6Bwp8uZshJUJ7vHpiiypPowzA8F0E99K64UiQ)xoV(EsDmFspdIpZtQJ7DR8j1XKLggEdAC0epe9W6GaptmDMxpSVC0SKZXmn5wCMEgVvflImIYJe1W5d33e74E9zNF8)4StVy)3Sf)MduhhBPD4EH9)drYFJbPB(tJ5le8TTOyonWppg7pMpmagNo)SrI4PabCPkoZp04np1ba288)idRSxsr2vT)jiOY)NI3(pfu5)uzEXqFJDI3lWjw9)4tn7BUt)9hi6d7mMMX8J5CkFlQjNlo6kh5hes8hzWOhf45jGYVYrbOll6ggj)FP8VIN2jBSWtN25d)0o)tJAPNoRZNoRtZKLC2dn9B6zDYuGpUZ6KtHZNoRZh8zDIeD()euZ8us18itQg)KAK2h)jW9NN0Z8KEM)YPNHJ9)t6zEi6zcsoi9Avk8(qId4)HFCMCgZ)0Xz(144mNgur2mG)idQ4FIYv1NcR4t6v)gOxDyyfD)7uOevzu0xXqjYGVVfHpKVatpPL5RHwMhBySNr9ZtjnZtjnJCW4pDvjgK9nFfdF438JZ6PCy9bDfk209s9H463wYGMFVtbKOKtYxux9KFRtk)gpzwH6gD(WUkEBIWDdIt(J051)8et4N8D9jFx)g476gTr4XAJ)d)MVS9JV8bMYlJUrNZC1xMMEpBjnzEmxdZUBuz)ff5Z2F1TNhnKIMbvnJXx1F9n58Vqx1F(0OFk5xE4j)YFIcFkhyRNUQ)QcI1tx1)F)t)fUge816gy(yUR)psvhZDt))YUv)tkHbilcFyQDM)MsOJZGUaamQYc9f6B6FJUDhO4(40xmLMuDK87kwq6QeHug9mQsFhKEnxj38tUm9ACFvFxvDlkDiYfyH(quhp2F5YdtBZUUQ(EPqZqF(jvFi70Q3Dt(vT0N5yPF2ZkZOb9NsRlZlVUBuonRP9G7FXNwLwII9PedwAu(X8M1PfC1M53o90FR0X3YXp67kTJDdTc)o6VTP)9DL0h7G)mWZN)yV4il6XOF66fGpp0lig)TFOp94obrUb(4VTDqX063qDQZcFagp(Nww(wYp9WlI)2v9thzG5bma14l(9SI5VN(jnH86Jwa0WYFn948Ws)0LgwA5gqpnEkh6pT9TDT4zlY3HhLX)0y05VpGwUg)0noiWJ(B6N8Qe)e)TVVRl2(((oH875t7CbCqBB(5cb4I(zK6VJWYf)TACI4LTvmd2KF(V)ncGrdenA8yg5XyIyl8S2OWNI52lYlcqcBh3i(VDdD3YpXZ5WZbgb1pX4sVyaGroEbEyptFVfb5TJJCW8AhB7gtpFqGp9xp2)lpAQzJ)zaHzWSm8Nyhl7A)GaMWY1jkuGmOuRs)mWJPt8Cceif93mbOTddzPp3J39HH28Zfgk7sqYQ(jG4EHrGEM)CE3s)eyqcYlySGWaMG1oYIX12rr2apy7gg4b8HTDqmGxbeyJMXGySoSd9SagL)jEAcBGkHi2vCDo4IBYE2(13rCW)LJx4ZtIWxlwiTKLhmRKsc0qwQjsKybG7V8dzLOSe9S3wNT6VB8CGWmakbouxlT6lUuoKDmPxFKuw20kFYZGUQWevzickx4A0qt7ZoUn7UMl6hrL2kuQsZG(n7KdRkBwFhgomiXOSMTE1PP3LnfrW6d7(EPM5HX2pH5Gg)6MmxB6vTdtEvwA9ZEr5nOSkDhH2)Sxg2Ujy7(S3L1(mmOFwRNOKFklDfbtE2)VNDrDE5Tztxq7EJjLxWltlV9DKzcxMIAXxr6QgU4ZrFdoHTFy111PlZoUCz(I02QAjLYiS75zOuYDCPyXaEb3KCAJvK9HScymtFTcwveYwxxNvU4EXCbPuscZwgn1DgDa7zEBEzz2sM8qwsk7COpxM)lYxXvpp2yh8gQLftqXtb2eya411XLWKjPoHbsxfHMSKWHkktOqqI)wgo9FphyxtxH7X7ae7iYwa2MqeHN5caFF2RQQwsZODYBRRUkRbMzX)55zPxJvaw30mCsEZImcjvMvTM)EdgOEERooPJYUkDDrRGJGHEO6elfWW7w1EVA)tCMcmukAIVQQyjTOwCRycOaA7kON02OdnpQwN5qdaZGSCaugt35PLlRUl)xZ6OFuOwf9JGswM1MU4g1wwOQqr(bYykwFxxPkK3en6ASSQsTg74UNNFqizBqONdNFjjFI0)geWfX8OqlBBKQP6cTCiQP8snsNGR1zfPT5FitklZ0KEWzxCXzNGVxS6wOwUiVTqk50KruAQiq2XWlu4(EPywVHr6NCF7n5lUi)oIeJFfU2gwSU5IpwXFk2Lrjvx()GI04hYgFd)S2tkM2OWABuwT5kGenyRkYBFxbkc5dRPOKDl63s9RQczj46Qvf(n(z84v0z65xXEWd8ltBANmWQXvkJHO4fYveAIUiJloOv1lYAE7Iwc)qa73S)bVaxmEx5BpGfYOkF4OyiYxQnEV5llymGUsz5voJFUKJsVNqIoyPcWhwUdk3N2caUo7d5zFuog0waMvG85kvL6Lbp3ka7YS02BWeCCjJ1ngjYrO8AsV2GnIqXHnI8BCTpxv3sBXaqYe3FblZI3APf5xxIIqB2NAj4KQE6tAonGICfdSQ(UuIK0n5WZ(HtV49V9fNJAgEhWGjHoOol9wu45LloChT0RsxjvRCRKRQjTLsfee2qZOeEp2ySbTeqfetAaVzi3n1zzAY1y6X6yeanPFsJiGypMhJWt9JZBYiFmPnIWOHct4Y0IQsIvtShqQiP)m5kIR3E2XH(wXHb(i9t1F3VqSXX7r(NqoZyB5t(vWNKA6vxL)jJkAPOWsGXI2cu6fLkwltu(M0lZ4I(RqISpEFDns0K2LiCJt(Htp6fN)(d2)CM9VFzlbV3ApUZrq8ocDYOk)krgXb9KPhu)ktqWuxoch3pSAbjsS863bonP(UcTCa4U4wJIjfb00Sbk4iT16qXhwD3Q06StQwIkC6PND6l4AApEf8vfzTzlpjVOiVjBrv5sWUqF94x)OSI2uu6ifF77(6gd4RBslreqdCXsJpflxn3fOrgjfAdcleC1rm9NON(sYqWozqmirfAdcPNqeoXp32652EHKdqK4HYWa4NKn8D1gueKhweCwKvZVHL6ncCO3WJCUk0J8qZMCMh(xX(3JyvWHVI8OoXoIEoefaIcJDqJCKJCF1c)x3ijOT(j2b20tAUySO1rePVHEpeIb7a29xpFM3pqwlUpGfnVgm3MoW)rYFuSqrutS9GlQ2w6QcU8cWP3T9C61COXA2nMgUWq44Pfc8a5mkduixrP1SlTMJHBMyoTqyuOVbWfh6PeOGNLdbjmgrBp4mBym9FCTryfI4rpq6diakeqVWVvsm3yGqWGIj0f5Wl7CSxSu2)bQdycJroarDGEdE4qqH4ftpO1A3yxEYj6Mqs2eizaclMhpeLgcvXvtqfva9CUiimXiqq2(a7AhgdGahkQ(fPJXI0hblGmVapgjIcum0sTFNtKG(WpFYyeckHiiq0EamzrqI(hZJEmGjICqKb4hWbHzW2IgZ(LibhrvPVmgbwX2xcZa)Cien8ZXiiARqIuP9mhZcxMgkcbYY2NWTgystAJD(gm0m2yZhYKqUsVwGq1bw8uhyZSyHGMnguh2iKj8JimreIBR8oAkxt6mWJtqgcohHOPqBywkqhHjpYEdKva6sqKrkwaYMdZcGfkWorUbWoIofpoeWjeaExx2QgfOKwSekLM2qm3omGpYcdLVqv4InfXlcYEFqEhWSpeNfqFcfRMXXC9zBbesah6nwYualldYNu0AaCAYqeYeMEUGwlK5H8jqrp1brR5aYroeJ8utybq5hrR6EWpTP9WSUnydj5Ignxerm)qMRbthjdgdmXMBScn3t8UHOCbQjaVmVA7xH0u7ao5qeso65yr4mDPfX5jdklCZCq3(BOyE9PvlItyelhNSxaJmZKtlbTSnI203L2cECK2CWVA7X8Kiw1gC4d05SjPHkcEIazJigwSgr1pqIX2ehOvHz(cBflOyPaQFBeGkIzc(VDYo1Wb5m7GFteTAkmyhYyzPd0cyl0iSgtIxYd8dHmDUveRGpM1vqchzgoIezhK6A44a91KQ8Yy24brdxelVgQc0O(WrOQTsSaDBIE4TPWu2tMwKS1nNw0NjbWoWSKeSeBI(N89fu1SAB5ui8WoMutioJaAr6jhiaNdbnBgHTeEBrQHpcLTO9MEdIcpWbJQnZshWwtf7Ix1nwl7hGci7NflZhMbz5oBnfjnszBbnq7sKIypMPy8DAygVgn5yjZ4OvyalTmWcI0dzJfj4HHkxcVXl2y8FczvUS6FAtYWlymeXhSb1YI2BT4QbyRTjcwBNJP8TTObIjEG6YDr6YGnnvMhGZydfZSKEI5wWqyCuogGaIlAKkCX8oskXwTQtlwBG1ASgclyiueoqeCmimbIsFlRFgMyTdlqPvWUesPzUhOThQKdzf9ePjiHzUbpvV7tz(UVPPWqVwOyKfokqIpHxWIpMAn2MBXTBhGs0jueTRrw4ynLDUtwxgbpy5VvTDaeXwJzAp9MnlJfMd28DGefB0bJZgmnxZqmWNJTAuTskkStEtMsRzAgSz2KCgTyUHEsSvPxeNEa5mHYS15mEreXa6YTkzrZxyA36dWVhc2pqEW2DeGxlaCTdLtIiHDjjqJWgyQ9oCXquJafo7u7bj(cMBUlMtM(Zue(wKmZ6LQR(icWfFtLLyfkbdtIDLkEK0Fzg5nh3HX(GJpYOUXuxKBKGt2hvqCWhQqNYjdXYSLKX2s814iITZ(GdcMETQpEinTTH9DrCKwRksB5J5Iag3K2CZBYl39aJMbz2NqKGB5g0d)YzPfT382SAermoSxTvRWtinnr1n8(QQfRLgVyF3iXXbnvPvzfOzErGp0BS09MrveSFjABkllU)03EiF2mojlKMI6puMJa6vVEvB(Lf853XT9M5cin)PIGwubjXABqpUjgRyU6Qm5RC1ZNku2Y2H2IkOWfvR664powjPRRtpcD)X8QsefT(G4tR887wvv3Mw2Igoj3)Y4EEch504KLzOhZYKwD91X(SR0l5QQY2gF)KJX2(Q0fz)Z9xU8SYM)PXHa8pVlBzE6)KF0)jr7uN108X0737IlKto7kn0KW)imC6(V0ZjIezBXXhuDmmsrUf1uwGGb9UQ)4eLK2wxTiV9EomE1P5lpjT(wvFRK7GR0yXiQR1bYKptb7KsAMh01NSsUl9thX79MsoyNbjPx2uvF5HfzPLYRtMxrFrKju3ebse3lq)fIBsQJBFzCNpRNxtAFO62E2Cif0j2KILQNMsEsFQI4jVlx6bD94qKT0xDfsmkHYNNkVKo60ZZsxEFhHAFK8D7pscY3dqNgJ2t8fPL3U)1xxx13eCikS)fok7tQUCmRuWuYRUoyL0fScmbF7uecoTknhbVDeCqirhsmYN9HS6I071ixvdl6M82lR(et98ZW5pj8)GoGjRnygSmqyYzeoB3EDUt7qGq0W2HXXrafKCzvBB1D8sCBmseveysFxB6IBFyv5sFzldMwLqa1wJMiEoNrOrplbwCeHRs(cVY5db44Yd5wGvF)6I0XcstelFB1V33ZU4CsxjPK7vGconC4MrGWmCVJ2DGKoIgWqsNbzQ54VBAd0IykV91Pnm9z3wG83vVdI6pEkXSyIhvlZ8q(OygWtrc6a6mFrhrV0k2OvRwITbrin9kXV4uFAIfikuQXQObbh(dJtq1ZavzOwsiozo2(tEM0gOgDzHUBWHF3uoOBDHIonXg)GAxFwg4xzRVqom3z0fqsb0cYFluIpaskBjS9396o0GjAmzIba2GVvRHG7rFd6LYeFLGcVczWbP(dCf9ndpD)KMFrdGTFYTOT3r))bDxnWIca3m7EYiOflgjKvzeg219ADvzJ94()i0hyXDgDHxt)7Gxd)oKUycyoyqpPRVtuJuORBmmj3PFhJrqhsAYPr7z1FE0gg)zZbVGWUdmXAa2vs0eTrre2)(SA(KTiwfIJ8nvO1RnKP0U)C9jFffLFw7jH6N75Ig6Y6v91ZeawmtIdY2sIQMXUHA(tEbGEO)(eEt)WkbuMtaSXSPeBzLq1Dk6qwMYjzUFrHYqbynZaD(DDxqgyqRltJuf6x2WTPnpcNotcfbmabtsJ4msOB1fh0NMdKxzAGO(OQiGLH4WHnTtO8JnQs3orzeUZaf8DZdYtynnfsXt9ezRozqNbOlDl2tKXmiV4mb69MbGbenzX(t9nmPmBDBDArVAOTrU42XTUBHlKeSon0gm8Kj)RAonlT(HtLsCeSnemySxOJCs)9tcCstvAc1Ia1WCLgr(0Q7wuscXyQp8vKSP2BiAtvLwevCBTXlMd1eDzdeE2BMQO)WqPSCE0sFivYTcd)igzKPykolV8OQ1KloQ1Rafg6i10f6V03tv75Vh5aQtpQwlfsy3ir5sV(hIzpwAiKQetPxF8eGfssHHgaZSCbSn)S3MJu5p2BebHoWa3E36KeHq67)g5WJTVwI9eVRqkiqUnPC5bPpLkp14e6uYaHoxBeNLfX4(D(dRCQTZ23EYWbk6djxGQZErrEl3xCfdmuMl3T5ftMx9Ji7veVzysxXFx1IurtiYlMXeBbXO(gd5mmz8SU227X7iYRE(g9xWRk0zsPjE3S3K43fpmtBmntEWIGGZAplvgw35Nx)UPZfv2hoj(lWuCDRRf3TLoVo(fLxhJ1HoQJ2AW0zWC2R1aQ8Eiqa2rIvPl0TW658XFxPVLWXf07SLET(CL(tt)T29IkEG)zAh2j0AtBD(QSLp)do80zeTHDpOKVedSiU3SoXYxLKzJevB(EBTxV40DpP2qrXyxm6KbODzwaFg5U0BL0BYiyhVEerMK7ykcDThSm1fSUT82tRgPAQ3wrvcFQ7v3Ws0HQErtFUdG0B3Cm)PMHvHuHmowr7gKiBtq9ZUgi29PJDxV4aTT2Dcp9nm3Sp3ovjp0WUUm35O7ncr9RWIr6xbOMw3C0zyNqjRju0vWWIBQAAZncfNvV(f7EBzKdPNnyfI54yOWJfn0zf0pPDw26CowFAH3DOqrmTTVoEqMsk3n8ZGlBKQioQU9kCzTd9kN5qDU7HN8HJvaQ88rAwnWWyeRbsgHHhoiPiXJQxgaId02kIfThTnHAhDeB4IWmHTQ30AYOLf8sO3oMHb40CVhLCxEz(LvnCKG5iOghjXiJtYupj0zGaW3wsBIHUgmY5taip9ThY5YkBlUooGdLdoxZjNzLHKBtKQwcwxxvhuCe4uj21KLICAtcnC)oPBFOJ6N1EI5cdChDhywSQCnt16JsVl96StYiB7auJSO9omLXjxQZpwJyL6NCxA7IByibsu0txF3LkF28eH(pmTOUSFkpON1m1RL4vBMzP6SRfQLHDO7lX6ufUV(CThiEskvFkPYV4(LlUPQMuaCvDwgYI0CyWdZ)soPTkBbVr)yE5sKyORlBlzcOi(5yaD3XKiUVGD1OjLgOU03LN0bVcj4EzDFCLf7cr67pB4P5tcziTNVLFuKJRVtSNnrsRj1N5JzQ(HpTW91H3MCDAXLgO(L5ffgzwlV402jO8bJb9Vs3q1bxZRHDxxuvv0MVcmowOnRpTnT7s(VDo)Er8rc0RKrJqpqgvICBjBaVH5Ob4Zan0OSeVKjkLCaN9HcxlNH4GDl(JSetg8D)OI)8YDZ4DzfxPUbgmqHxUyhO3pYUngJU5HWGRPJMFtOkLBvbrix9rA)d9r9quLGcrXb9vlRpr355bmIf4ZqSHx2KqfPCZVboCsF)663jxBgMRH0RVU(OtW5wjaDpsREB17(y6k5(yqdBuYQQMCerm1viXXZzpl6FUw(2HkvZFIVYMs6sCtgKku64k3H(IQf3MTKOi0nFqhCIE7C5aS4dDQX9d2CQf9RF2tnu7pzQJ13vgNXZw022N9r)zy0gJhtFo4Wg188deCWOxqFs(UjUhtckRQU9U06BB(n6dik)s)VRuSpX8P)zPro1h6evE5dErf32MRlIKllRi7AEDEtlUyTyyUl9tKgc1XDjMzmr0OizveHQ6FJ4uHjnihxEEAoU7CKmB8m7xMtST4MCrI5lOhaqF2GDoUxQWG2GdWtZ)OoyVUb8O1LxNj34EBrIUYRg8YJeHcHIoXgYnvXgJp81yv(xPLrH7)gcHTI0pYkCp0OVdDJD8dLX4tixOc3ZYneP2UKk3QvrVjTSkT3WCcyrYdRgKXegc44AeSK8ACdNiWHxYrN9tNInaVL4W7bB5jb4MOK5uwZ3bqgAF2AIE54sinCbcbJy9tVio4lGOcrhAyDKv3ariwlNbWB798RyqeXtQ53nHIdxlo69fYadSMNXhRPoKlMYfvROniTWX8ikCiT66bz8UtuK2d3LPRhb64AVNTTLdP7m2rfzzs2LLxWEEoor(2(bomg0ideqvnGZXnJ5xBlZy9NAQ((7U18EsswKMrwG0CZ5PTQdRvzxWaD9AL7ABy)U)9)gkWdmTM7qsLlUttNKwsw1XgpsE1U8ocQ1D6dI5Dl47A67JFVDKNRTZ79I4I2CY9Lp3HJCreUGFIwOGeC9PEX593eW(pb08phvUcvS2KH179HrowbVpWUBuTJa56wh1UR0fpOUsoAJaMkdQT17TJDCcdFVRF3WgicOF4RvCzgel)vdBeab2(2VNyy1GaBpryXwg2zxSiqyYInKgvhsgW7J5wUadxzZ726G6LOUELaaei5CiTqvyvTKNNBhbr4pIDnt06Zh2r3GqYPCP)5GQobH)ECJhFbrP)5ee7AjPxC)E3hyFh73Bhg1bqJ3jaDenLkBsdtwt(HtYx6GISY3hou0J8aemkKhvmFGCd6KRTlSeHeGarlhaqZpDtw5XLPYDkv8yaxfA1NGhrBFf5e1YSM0wKEmK0l5v4XGEpuOxO5rU6QKHVi7u0sDzH7eMqcBozv1TLKny0Rqwyvc7uOx9aLI4WeYw2UgK9qFCCtUn7EtAd2GnvTbvhFF2mf3esApzrPzuEhC7p3AlTut71BkjRPJDRzXTSk9(JKsVefrZKBUi40XjAPsnSts8gSxQCKErVV6Y6YzmgScD0UtcyeUV48SYxZA1(98oLpK917jhijsIcaJhyQ1q3kIuqMlQmdciHWGkPtRKyOq4lYnDLjeIGr1SEGoXAe4BNawDpuuHlft(NEADdDja9FBHMqLxsK9pvKbqd04ZMYQ0XQ2McjQYvlXCc5Emkkcu3(r8oa(YoqhNqUs0MVaLHO8SYw2El5ie627Yva18ZixmkBflwgrN9lKOnmUZvRzLJbXKa8N1E0PGIdsZd183xVlu(KFtkroOdBIyc0)OQ6onYwPowajkWUqd2HSELGSeW13RQm)YhSEfNBzV6WJUGDfzCJla7bYxOTIKflN7zybazog2oXzF2SRt4xKCuKeti2xJOdnKpCgMvLGbIr7hNZV8zrzk25WKFqeiVvMzbC3ZkBUVNYi3PmMmWJ2i9XwufGGV(S0d5n3S845fGpI1DYbXpsW0eJ57SDW0AEV98dcJTSDC98daH8F1y07ftQy1MWHps05xkZ9MLz(zZN)vtZSYyRVIS5Zvdf54rovxm)XBrT(yNl7n9sXK7NW2YmwsYq6(EU7(n7uE7HufFZyO)m1kpr95dGxE36PD93ZV)FqP7qE5onmgkv)I0BpWUVDPpMJdUY2n6zvrmFgD0ZzpGT26hd92ZAK7xkZ9o1CpYssw19dK91omPcHc580YRZuzGaBN3UT3MpbBKMFSjDnFmFvwx5TqXmsgyWzKRuLV2Gf4KHWM51ep79oLOtn5ZZUlVuhhz54pqYZtlb93igHosH)Mz9hZ)n18E20GPIuu5q(IBGrX9odO(4EFHoRKmJYW2)xIf73lWRj2(R3M4uGFhbTwsgM1zM3d3pGHkZN1CZhG3aeXJ4ghxd1qGirGFkY)1FnTMmdFZMaUz1qi5wnrwgz5IrMeniBSCg(gdoBJjYMM4cXWygoNzgoSZrIyVdzKjxEtgTqhKrqF(sMMFyvEamIqwzG(Opv8SRxhcOohklnUpLSKtobvhnIisfifCWskkqCPC0U09LlDsKxA664euQkV1EGUySzzxBjefBqsgqWDIG0Ii2LWT(a4ye(UniMZC8fC0SXzyu4mmeWjNA2q5KEjBq8Yu3s3SeUPEhIeku5oCVGl19zzCumWhpuCcYeqDGEgkCJK)Fu2vzLnKmdeAJn5)7g9DCts4mbUDSfkyGHfdFUc6EOH9yOUIPPR70JOq45gYFUdHwdnp00FOj2qnrQ18X6G4wMpJH1Yo6cecF(a6tFNPH3yOrgLB593tQHgtPorwZ5FBNUIUakSv9oZhcXHlO(eMzobBBmZ43CCtgiarjWEI6BtRoG5xBnQI(jLzFiREQvwMXwtIQjXy9(3FnYaR3VaAEhtO1h6DRK8MxHhuUaRBGHYGQcyzLpo0S868LlZkF2Hh1SXa)8Lzr5xOCyJdrydYHNAs1CH7fzY3mgUzIVEiYIMlmRBXlZ5UpgI3gBSDamVDNpybYUjVTQT5z)VE25PlYtl2Im5HsZKi8nvH0CHCEQE)px5W7YGt)(WX2z3YgoqHTPX40QUG5UngjXRwXRodpkKOxVzP0QRq8qZjhlWPtC5dx28gLeVrRrpOl0)pczYxkrJU7eV1zd7CEOVr94J2UBxy8Jj61ZifEKNEFX2woWcTniN4Ztk2ShW6geJnRqRn5K(aRiNAA4gmdB(OvTXiGVzK9mcVC2qC4yHDBwm4wmT0V30YNPcf3u3NNvx)SwMp(KZ2GyKPsf)k438SIXMkWAO1MZjt9RJDLswZnXb4Tz04gfN9WowTnzN88MVoGzB338P5KEnNb(ZjqBt2qoqF7xx5vt0YIJMNOS5JGxfRfu(OL8VLSP0nXXpG(zuYDPRwLxEnFU6DwUi5DlSFUQ8aU3SP0ETyjFv2vz2O6bsLeCko56cCCzMfv5(K4U76VY5(KYyrxloI4pdx3QN9)j76KNDu(hYlZE2BxxVQQj7)lEY7qbLniz)dV44F8f6PrUG7QtebBZxwxD3HhDYl5DUFstwr2cuWzLTh9KiPxscC)B3MMq1Hw)DCxhe)nEx3NxFw7PiV57gZFCe4GT(BnU(pF7AIT2)BmQwWRIjTDiBLvT)XilZlX2lajc2F7eHJm)7B5M(pFe4GT2(Vz7A5oBwN1CBEPCB457kgzbRCAs4EeHGALyn5YxDEwt166fzDPLy)L(koPGVAKlU9vD8XYfg(nQpNVog4MOxU4E8mYnG3j56flpaNLwAn)X6Rbo6jniBVgurhKChRnTqxNVe7Pmgc9bWm4(vn4j482dz2QFYv5ffid88uzhk)d(gN6yCbX5KiRpdQ72eYL3kuLPvsqhhfsrov3hwlYqJns2zmqqo9sfyXyVoyjlzRv)BQU2yQqlCtAzzwba9ark7keCHj7QECuhmiozDjUKl9zz(ZTTCKSL1Z2X1hhWWJnXDdK(fGgIiOcj)26VHnX7f4eR(FQ8)qkVFlUf1ZmMMeLCp1FQXRs4S(LYNZRS(lKLuCw0xn3H5nzpGdGf(af91GCUZUGEWXWPtodkzqF3kA9iSiBivkuByL3p74ee6VZbQ(QGrPsYsUCeyb1nyDGaDoQH7aXAI)vNFHAV6ycxPTq8QdpsZtjBSUHvqk9qeq(3vEdvWAqDGbRNErG(sRzr18j7UruQUVdAapOwslzap8vjB5lUBfQkCVRn9AUOp0pGcfDhReWlS8aH6vrFt2eOyvokVg7IxF25h)po70l2xA3mcYrbV48RvXhHnvexz3KXdCAJ4g4mS(6SYmv9xzsNJDWCTXR44yU)oYtuMYuxRlua)Mlpn3ukSkfRRXfwQ(ETflpA0nif5JTUXDqcWB4MVLuufmQjFCcKhNqIAV9IBYUd5m(4BR0apvLQHKQ90Oj3Mrag9C6zxqDJfvPfkjFhpODO5HriStabxZG6FwHHKVzl93UZUyWyk)weGpt8dEacfMMl1qgKEVXuPdwvAPsvxDvtwR6CNgW)p9YuULSaen1UXA96bbDPeCvFAqpMRO7eYMar6KsOUZUD7k1XH70VpF7IwPQRmJycsuNgCyOTAd3x25dBxNKdUbBfIQXeb8ir6bQ(yu3m0PHCRscmLzO1PRIFbO0mR)iDHKBc4rlOG9XmmzvD(DKbj)HW2Q6UvsnDLLAUjgwqPpWIJbmS(jRYQxTYen2bq3jhlrLUu1ChHfHSaLTyAb6SCC5Y94RoTsBMiV2NAFbhrZhRnfAYKTBuHq0QLVmRmJXIF(9qgYC81BX6Z(Ly)jycmN1uXCtRPAgywn2EZu9Bx6MsGJXio06A5S2gkyz(t)FJwonvcdkcfAjmVnTUnpTq30QMteL9wvC3jQjwvoSEecVmemX2A(imnr0GpOWhnVU4TzEcQRuTz4kGrsHgAE7adhNjFk3DI39aYj4HNJ60liIP6u(A)jDFmLuZP6jug03Rmfl8bhN3Ccl48)7XkSqvJOhwRvKmkyjSn0oYN8TjW1kGmttk)lsM1GAorhQUN8U72Hyu0ogkqYKrsDbQM4c5MLJlDcpbNOUt7gg0j3tgvVOBKzEIcQUp04rT4It0pMwSoRPXkrot8SfhFeFD7vv7LnWOnJsE(U7cNlYVQ9ffs)X1uwpUW3vFS00YlJdYFI6gcETkFL(MUp2Z5ofnWsUaDlhfj(8vfvFu7mIcHcPCtqOIRkQBt2qlmJu5wYsT)7D2FWf9HTi)z8fTsfwaLbuZyXPdz3Y606L5PLWpZxRQ07Q2VPQtQQ3wARl9zHhDdQ6PEjUVM8Djx5vSbMDKvXebbbBnURCtCDANAnI9qjbWjYYlcT8mDoYPSQQEDzwZ7YrNheRNOUn5X1vLxTwvD(L9HW6eJvKUaohVxOVRvuGh6eKWHrTgKP5XX2ULH0iQ61LSWDz6u3XXj0mGirvnEMAJFhfbqbtiLM3i2XxwYzRxmMQmgCn)ucOgwAxRQw07AtNMb(YatU1BuP5p8gU0vZjjf(fNayPxtEtl(gvXU4K0pjj2HQGzhW1iwvDL0OMGsoRJxsQ7j2Xr7fg476B56XLNhF(UlQZixJmzWHRnky(q4ly3kbh3pwLZvQbvjZpcjgxr1Li3MmRNcCmyKcY57wuxvuiXXJ)7S2wCSP0NitUMDVVG7OUnGOkiDs1h4Y(iFnLjFhPTOuAVFt11xKEPe1g8PQEq9bCdhMefkWcJBtyx((XvIUl7Z8w(83j5jgqpDb6qDrzNf3tBV8YvRBpR8IkUMc5MKVKyysxMDuwr69Sa9(ybPoHFPyuQQOgTvPnDvHz99j3ZlEVGy0cJSTCTEK3R(NBB7glDGvhAi47RViQ8WQv4(ZgZudcFLBihxUbeosB0EcYs6JckhxqFwOOHlLr9JTr80yAKsP73rwVTUTGOt5MBQj5IG8vMGs6sPL1O2b9ZdS83ZZ1XI2pONX(4mu450R4ShU7IE0RRQ9)ejOGM5QohivgSNePDsL9GRvuNvYvok5sZOQwhC5gscat0m8LksbAVnOa5e0rD8U26SYRj4V24AjYP9H6eLVp0vKBtVBLk2mbj)xhN8FDYZ4QU67ZwM3c45PvTeK(O8M7YBA4y)OQdA6W(ZIw8mfT8Fx9g2AtIdQTiJCKtW1lGjidUKfd(SUeUDPQ9By08yr1Fhen6QnY4Bo0Gqh4NC6l(ru4oO9OESguhHn1C1vecms5dDf3zCHhpTRcXOZFo5N1ITqgzCRh)fJNEjASW(hZB2nk1fDfuaDJfCT0o9pmTyXzRKoCRtYv51nTNVU8OQsU)OBNSOMWGVmVqk11EjVoRUIHn)iQTDP4cUhLqYxVBL62UBLS)YpqMDTUMj48sqvUIZkdcDvuvTSyDd0gmkGagcNuqxoSKlwx3i9O7zSQzUONn7TTFUCLQRrrlY4Nx4OdjCukRpAN7M3XrP6tFyE9cP2wo99q9ekT2Oc23n)CpWaTlf0X5vvXRuULMejhfbI126gjuxHj1Ox4N9j6ZlrTyJ1yPu4j83RBYguaSr33bpU7l3p8LOPWt8L1P5qxMlosQzxV9ZkKp(qxR9RoUU9(H7NCstdwC8kqwCVK)hT40FG1Hh5eF0o3CI)Q4ygiAvaAEVav4TjS8MjSdsoUTPiV4(N98NDXn1PfCTm3oXGhG(aFuxPxNXIePxge(NKwUoTy)LlfbLanxKFjkoji42OY2sOm(vBq10epe59Fd4wzHwXjVHM1v0eIP(FSU4)9)toxJ3(DyUd55(UQYB3XUElBIP755HmDGo1UUZkqAQ3Vol9z(o)oTRJ4Dnj)7UFVb4KxumYMmnQPTzxZ(xxGod2Jm1qEsok5BRybTO8Tk)(8oj0vlOoOLlbAgrmFU7QStYLTOEFzybrqY6YRRRwVkBPKUG6t2HT0To9kyRmBu2CNjenChKU4wmasBHh6DGD7hxc7CeXACh0)tKKlArQAjzsP)f1biYYmXLZRjIT2FmDDHYQiErjljEM5URvrdK0iEcCiMhXyN3ViDfeLS8msEVu4KPVKlJlABkidtHV3bjvRYkpjN8j4KSY1Nr)6sYO5dlqFkH9nhRwsSbQoFOP43Iar0B7p)nkaLy9gVDvwj5My7GIbBS0wOsxq25xKPWnsZsBsPt0pkMl7u2oXrrp2GrzB7fSxqqORFKlQSVIKREqjd2pU8QkX)P0pKTuktmg2AqMF)VwNwJURdQUM4U(QibhC(Hg3ZoNKugmi0CQIHp5Sf7OfgFbfmxDdY8O6hDzDr4Siq5aRXiLre6adPcMlX4B0vZqLUS)dy6JCs7OkmUs1aKmpGSUyFTOISz8T1zlY5Y9jBs2C2PSzZl0ohcIAHoxtYP89Dp2LLXuIILSIn(Ni6Y5CbPBN)lLpNDEv5gareHQlTS9XUxsn4xHMHdzJUmZsjwRdFOoLlvzpQw82dnLlAs0lo(WR9yFSfNoUtxXu7yvL36xjOAp3SSQqri8O8RUkFbXUYvfPrgVmWgCoYE2MI4(HY82xwJAHfKS5Y82KHnTsPgU3IkUYHPQE1HjvLf3lnfhvJIbmSshrsvohhvUYW1QIBshD1Twv0BC6NrC3O7lL2yP8XSAvNHO76kptxgInU)A1LLrzKFCxvCw5Vs)Itf9dv3auTK7n2txgPgufOvrOl2Oqs31tjaLGusS1jQ0URlVs)or)8dkxfJatItXOmzU(QRmRCwgVKJQiNR6uisTXL1tPlJ9DTkrHnORaxtyKYwiimR(MvLRrxDlyaChORXDHGZXDLSjdNQprC5GWLGWdkuci2NMltHIuqLATD(jxMvW1oycD31td3Vi)AulrvLZDB5LubRYOPGA2uk0L3Dtjv9O(oIM(jr9reNl3Sc0TdJiu011)pox1ueIDKRQGtingeoruEqT(leUodYyPvBHMNi3ns4sKQQw2pfUH0Z8t8fSrc5IQQ6lljbZjznllWSRJfOlJaqyKbrwhFGj2sL5vaXPk449mGshwOBRkqovtPI11OsLiE)jrrsfJmJgnPUh5Dt(13q43hs19FAFUufQEdoJ(g6clgwl0IdSKtIdUyUJrG6ql2xWE51VnZyzs)OWyKWF19WFGKGo6GUpDWAr3LwpkVzfjFKKNXSwm2RdCk3yY(aPWmoDf8DH(FeB1uoFd5xsErjDu0(sr8ejUkHy0scySdmQaU6oiPqkoi2pc)4yP2Hk(NHIcGyqdH8DKOKAlw)1vqpJko(wr75g7Bfyh6iTbbrc3yryKrDDJOI3DmIvuKO6DvgGIDlfMC2Tt6tx(8Oyh7OWflC1LptLG45KYnbb3RZAmqDQztQ78LO)eAuiT7Sektft4ZhkpHr3QCRLR07kT3MsDLClPJ9FdNgmXVWKfSvBC9PxODroLOMZoquxv5)xkL(wIvVEXFw3Vm7bTdA4Gk9Tq5XWl5uGRrxYYO)5fWbpUto5gubQwIaVOSyqChXucyh(ONKsTLmA9U6QcDSYo0bYavpUOTVtYypphTknL23lPxTyeBdn6ZHpKEK4CnjmCn0m6SFZzU8NHrAKLHlZKaOPjKEhhdu4PKyw4aXTC1SPxHHPPCQwlWmMHDz7Lmnnojhf8u6ApOmE3jlvScBw7TeZ01sLmI(88M7mV6e4TyNGLUI(ZK6yIdAx0dHis807kE4IOtIHM2w8akdgKtySrFJYf4EZB2yZxEyN3siCmLl3rYY87Sn47ZnkiCO)sVNIt(wLu7hUnqkFKg2Qu6kXlZylaINalJAQYod4H2UHDAltVQs0M30D66bLLkM5AKohlHLZWaK4EKXGcSlz7s7LCx2umuzEfjZyrWw0DpNLhdXxKmsHcXq7NDGMQzQkVphfzF9u9OcVIUtEnqA4wudO2oD0oDePFUI7rJtBo(oMDNt635L4RAgMCgplUWgWx916s2b22l7W90VRA3udTtjUtwxNkZPoIcKuVLoJSau7fSYrtvF5)X5GisIo0YRH6yvQGSjV8M6pxNxbpwF52INAs3EMKrRTFdnHc3iNqIw2t1Z5nDyJPiODHwSOHHPi0NxEW1M9FbW01EPrtiw3KX3QgvXKrLHZCSOaitz)8ukOHD0uwAatbmWHSz7jNqkSHuLHVaVD6uP17S8yxY4eWNEudjv9RHHnDLXHHPV6sZUyByBQEpmVZeg9n4oHFDEaRFvdmZ8(mHyrQ7Fwdu3AUVnUylZwufMZz0rEATLY1tuVxiMXDHXjmou2vSvIZj2GH9CgNq(DlXgxQE(iRtVx(aLYHEWblVOZPJPonjUpo2)KE5hQx1l5r487gtEwq)zkrqNepS0LzTZDd(OTLqpnx7a4X6J0Gav3NvGMx9ev)2ubVhs5BHyEOIPOQb7pmqGkc9n5EuOgnoMhDQ3rMuVp2WlUr3W2IxuIrIJT(VVfq27ZJ0eqKuMsAcri8QHBG2EhnIfw01OqpyWYVrFzq92PtfNbB)0q217bWx7OJrRbnvsFaVKOjeyyK34VBuKR6Ja8NL)xBoOgCYviDrXnESGOiyotWYNldl(tN7xKXumeBOZ6ic7ecOlI7Omvjh2vVRddco(yN1GJgBmG2CAOnlrj7FYd1J(5sq3hOVCZP(ANUZnTFj)n0RT))T3v2YTnsY2ViRGyNG9tQBr3wH1wij399(KcijijoMeKxsWwTMoM)9j3QnGQ4ISBnxpHC4iSmfrbGQYkRC5KN0kY1Qg0k7ighEzjNYMTLbILT3a82ZPomTpTyMuD8P7dsFys7vhbz9nfHAVrJwSaOJlD5WP9vGn7h3C)K7QAXsaMe520E(D1PVaA16hg4DnGTw2y1XtDDv9Ah3ZYuv7jAyg3my6e4tX8vgmu7v4m)(5fihOrDtdxzPUaLkYsiVbduEFSCdusCHx3aXgCx)QXN4gepFm127CRDFmUG))yhff2SEhZyPOAdtFk74ysYbzdheNIaaM6ELG1TD2xyfz19ndKDCWKtNnhNjjg826p23mgAFT4AFNugI9yxNn4ALwU7McL2WUoJ2FtLB2dXETCro2qehq)GxFtjr1o(MsQDC9nLMMyFmUPD(cAzjCqFDCrfRYRf0MdVcUB3)uoXaYMjmaQh3qEtUr)t3yszc58A)OQfiAzEs8yhVC94qKj8ESVSckl0HKXjGkSwFviJT8ZCh8swQSzJxYFGYAzWSUY5Y3B0hPzkYxtNCS1rqwBRzhpM9gCvn5KhkNm99USJlZoUlr3dFEkd(Kz7PmF29M8v2nE2Sng(8BuQeGEEoJb(ju7Bku6h3I)5D9c0cveDtgNSBiO3YEsHgvD6Gn57HN6(8aLHPJJBBiIA3ysgtmKpIkjJGkgmT(9AABDDIEZiUXxsH2xh02uwbHnkYc)RYxB9v7gaGqjXXtE4che2VbFLde1Kn4c9gsnjDqZgCy2oct(rXW(fZGnI2ev8hXmGOdnvi3R1azZkzLFpSxd8sSJgtvhAKatQn5hGNBOGhlDYm1Smq0)a6wKkKkkFRnCt3w3j7QAepwgx3h9stbBno2CtJadUGFg1u52Iz9uBY4WflbbWz8aTSPu7hpEqsAgPGzpkT50HiysZZXkwkfUykudiIs4kYY0kCPh4uQ)1URpVGQuoGf4OKmGesXrjJYk1UokwPFghhoJwWWetEjSRJID8tCFPGzG9yCimvwTAfPkspdfZ8iZo3aEjPddohHhi6HaFTkY3RhNerKWvC9dXfjhuc)zy5W4ImgeY78thSkJWtw1uCLc6sSgSB2uMVALQIRZPyQ0tMFhrKPfG82rpz6M0)EX(TdMI0KsJVKP27PuYiT3SEXHgmGk8UOquLufKs28aXjx4kvgDa4eM4ngjt0hdp(J(b)mfYAHWX7NJOKnGE8LRHEP5VhQgcy(pdBWo4GmoLk3u1lk)A6jPUUi5vJRmFqhydzk1AO3i0UcaLVWOdjGnW7N9DbXeKVJg3fC80rmdLJPs1sug)J92rx4nKMrLwp)xk5W7LP175o1nKa8VpBs9acX(7od641RElkR5O7wuHsV6URC7BM0ijpeYfc4HFGKcheBwHvPfcrQb3QfutUuLf7js68VdeR5db(zoSUoBZgZvX5zSvsOjWrkZXAN3EHkZp7uXn83WrPHu153BIqhMUTZ6((CI6goY(7Z(0x7HPkEYCd7u1n7aVaCMpmT)wW(hEUx6bdK3MqBJ2(H5HHoDaWmfyVVFd4cQr4n6OuBhK2reXgaTcVQmXQ3D7bhSin9qoVj(dWItFJOJ1F6znDnihwpiS1sDXzWgl1OnbxaVr1D3WzlYEg2ZpciZslpWe3EHlF9qBNBcscbXzRV8ZAfpMxbcA3PCXw6(IQGXtYbkO0HyQJTyAxGCR)SZYvQJo3Sc1UyzEUcYJsQD3la3gi7SOH(ApWhpBr7lgGPyXihmbethQ2hWlVwK8gmPUDa51owdoBkLU9bZBCPudeEQFLxdyEhAnpQdbCcM6iDu4Tsl8(uKjHsPlrIZirkPt4odDwLhY7pWFrYsXDanvmgViCB1Y9Ugq(7ixVi)qrvWUk4rcAB7OWMnr4TbbXGowZtJLjU27IgiTkfCFK6NrJtXFMRXxIYU0JZ1ZPI8fXr2MYImSrsFjuGzP8odE86UAQfllfqcaRMuGxEBb5ScjyDRWYTuWQFRzFEtjunUJCtNK0U90sJDWnNDoQQuxIuVSFF3rwT9skiBB0x4fV1ElA0Dpd36yQfobGo55Zd8n2EwW5AuytL)IKK8DVmDbB3TWDk6RxVGwge)39Q9N(4LwYUyGKTSvWL5f0BEGx((IW0avrvhbqrIjaw1HvWoFFloONce)TcDCHTpm2hAM9SEnPVxkTQU3r0VDINRq0kUnMiWBI89bY4Eaxiise6hnOaLPzN03hkQW7qs83Ak83lpnd75ShCXJaIHkcUTJ84qj7hoFYCqtFbgnatvDemLmdmXGhRjLjR(mng2oEQbJGzZnmw69KVEVfHS1bLoglfG1f6Og2x5gt(pyvUXCHo6fjaD9oWPER8qRe2MuOslebegBJ2D18UjKS7pZ)BO2O5JRuy4rdNtFfCaF(axyJkQEGHLJVcgyxlqZnaD0VbWc86qfaZY1UvceBfQ5TgnpMoMZl(IE1SkbdZpF5zZdaydLOJDhZMEqmaJu8WyaaF8O1EMpdWtq8GGEEUXt5G2JFk8g4LEyTKd17w5cIUv2PQsFdtnlU5fzO0HXdBWAafwEdpsepCdumisaklW12Mybmxvund)lWcrdteXeOWCMc0BtTFCnmoGxaUVjTgESztzV4gvDyF7LQREZ1zVhIdYV63ormnftS7(WilbcMdvGdk00UNewGBfvRdVZ(4L620oalY9OwNq1tLFVh8PTYpqy(XoRMV1GmWxTb4267duIfVdYGqj1C75fviIS9nnN)ibYa48of72QO6ngLtG9aQSMa)OaPl6dzSSXvgRfy5yBs5FP(RqyyaPKKa2wyf3rScLqIMfjwULZVBs7l0DGpY)W1lRqAOZMvJ70QmYg1mNzGddXZ1hkoBSJqGu3nDkgX(ZU9wT(Din2thSnFqCNNd9GIpViMDVSE2KgS3AY0Zksr9RNH0nPZldsE)JQjg3kEu16hr2S8gS9kqm0xlYDhFfdqxHqxY4Kp4Ho3NhFgz1t8srMM)RVCZTtRi2cmE0Z4xGNox80K7ObOz9SBrgoMECQRw2(0uSJGJFaSgdMHJeSjgn1Q7NIv)8WrpdVapSEj(Fq68FUCVQMTy6KhEHV0HJwoPT(MQ7)hIyX0Qz1TZBECn3taOF7QQg8zaCq556QfZBUPU5oW6c8LbSwE5KfWacJgkSKsVk)m(MG8fj35sILUW(I67MunD1zynoWKhnveSWb)lRFOE5Y67)DA8hZdV0UbVz9kK(tCOLAq6uDjFeEXC)Mi2IGLaHbti(dlF0SxAHzs6j0CP4SM91s4vTBdVIb)4EGPVpOcxBB1uqEqjjP6MnFG8jSaBpx4weueIRC9VGYBkh9WkeMlw6Hu3J)6xwulDO0)KjZl5)nhBMbTVi9Y0xKFxmXHnYeVZaF06MhRX2wpp2UuNg))XENakvo(pHPQvREUI3qtBYuTobX4AQm4UQDzvBfmjF64Jo(lNQ6e9UCbvsbd7sm62fYplHaWEP1zBo2khSALIFGaSrSW95hs8coZsS9Axt5JwQ2aBkOkUVCTfoeJj5A3LoI0EHndWAcHNFMyRVdxEfR)X1pB5ABg6Kusunbe1tgT6R42rWZv4cwJBGYg90mU9KI9Z)2N5F7Y5nut5a33UKvdZ2NDE7tGoPtNSAfSJJ5S8krd7wEIiLiYjgWte8OqejlwaT)X8BWbr8iVEv78NV556xwcBsz6UhdL0dY)oL1yT6PQ7N)m80rSrlC8XKz1GYXv4EEwxXTiHsU8R3W70LbF6KvT1eDKttF4xTC0QxavByVoGh67RFqDrezHhN40HdwdpGxJ82QQrw8)15t8GtGC(8oQVIwiDbhS)j)jQK1egtezyZdV7U6feHeJ9tz0aeRVsjrcNxVEjO)6kSrkD1xNGTgehg7N3lF98fy3BbFHsG5M2P1MgsckfJDCwSbnWYpW1uFN5lG52v3hnl4uqpW6EZLKIxI5hJ5jDK1iqJWG4dyQCbZ)8EcQ(OOe78xZWA82hXzWbes6d0HoFK98eHxf(L8v41YIb1D7YO3)IrZV9FutTVA3zbec4ZrIiTT(ES5(Kq0sJma6EfKVqo5HFUnD8wCgvwbOgTmls4HORTU9uJ2LEC19OtEEW67WWXtgz89Ru99XBdpVbh3ze0Uyzn2sioD902jx3NiFXdb0e5lMgkKztUQE6dFeBhfxx181vhE7CysdEmKqNWgsX56fSqC9eALczv4twVQLnWILkPb7tyR1bhq1oVo8dDaYc4GO0SbLdhKughLLBi5VIS8H5Xf8VKHAhcJwqyQiolTCquz(GHuMcsXT58d7UeYzIUYpdmbcE3i6WKJR6Ik7wqgihziEv4GuvFHgo7wxUw9Y(o3WLVCoUdDjoLYAQ4bsgeDAtbfDlHVjMbq(XqO2aZ47m)HCV3dwmGe7qd92t3uq7Zl)Yt1kEwhTiOEk2pXqAgf09pz6uwdnruWvlAOBhFXhbMm1Sc2XiD)Dp8jN6TyxNMHTH89gflNu)SPPIxMr4xz0F2KgXw3OJqfCi8xxPBr6cGEutso0oQkEeomAGkycKUcmqjmX35A7qeJut00b5hXOqYcsQORHJQZKp2qd9Utbf9LTjMJWJOGY7maCdQE8FclznGzRK1YWZg1AEGvNlp)KX6NAyg7Ev5Aui8MWt4SjFJm9fmSBRzKLDMFaZwfzRoBcbPCIjHx30cN5I81pSBhKSWI6(OjlrfNG7jwfff4rf8YSRjTJN3BFIMZLxoSOTOZ15cwG5ww(KE8tqMahPDjMBZLi)cBk8GTfZoYRyrf6sSMBSk4DFXIfwGz1Ew3w2adygO3(t3yZskCrTeoZZGXlZMpV9j4nsA7y8gprMa3xlbuL)CAE5NNwxtDegwHMxbsyHhLi5UVyvB)XJ9UU7NJTfarNcP2wsSd5TsFq0Yooupf1b58A5bjqsRJd1dOMQCeTynjNW1TpmESX0MnckEEe)ewFNiAZlQwViYbOCdGt21HJgODLMRvIq0YpUIaROm3AQeLy1UGXITRj1jopOsSHTjAjkpe45jfdttOZx06i88Xett4(T1NcHswwNwOYV5Jhb7bqZz5GkG5JKBWN1pbowZtv7AotlS2J05ecEiSuqatz6jHTZ3XuBEgehWxIdNIgNtR2g(KtCC4Q1ZMb7pRBUxcIGCeK(Gr5ypJe)fZNSAo1tEirEQQmzDWzsf0rGtkJz2kC7iktO1aqZoi39jKJakkGt0AHxPTjSUzsRMDkU84F9tSccJqUhYVP)EGnWhu0tz)oVm9M47Z56(PhRKaVps(vSQOag9dDrbHibHljGnfhDXv9SpZA5UqI8w3dPdrjtOoYE78SiotXkg8wYhnYhO2HCBDtxGWYaugeKNAWTNPCJXdEBilfNVCY)CEd4ym7L2TM9hShkMtge2ntYAoS4QmDJwYJ5da1rsGDaORfuSQh49QYQjOigTEvVdH7BeGgHlw6WbzV6QvuFidfP1YZjulsLReeWva2Qc8bcV1O5ylrsr(V(mMpnkuMChNvNVFFIWg)34O9OAsTCn1I9dFyoqZm6hD(VFgfsqIY9Xsv(F95gqJ2EF3gIAbn3nvca36DJbVdz1G2kaH3vjf22NC5W93wgZyJnyyIK1hhcPq4klivrE3iaMM1QKRpnuVX3MJvqRen2vrYguKUIeJyiwTNWm021Dcgrzu3DA1JtUtRTRWuNqjCVhNKosY4MaeBAiE0fjDZXlGvBtkI)4N5ZhOWJPWdotR0ES)ttz2gg)YSkyGafgsc)7LVRE6uN9tzJA5gC5XyFw62kRwHP05lXnXBjg(AB8LdhTT2W)VtteVwg998KfsOKbJC42pky881hcY75J(04dpz8LGa7rhE6H)64lzplq)JVSEfS2QbVSeIMfvMZxC5gw5yoXpow7f(oA7ub7vSfLAdc2YtkzAQJ5uGgs2liXIyWIoWzmo8uDmNepVvfxu2bns2(lniWMmor9H40xvZqFOXayhBRa361meNjf(8NI(JmH8lGv5IpIOTzYQbikrHpAAnj)U6VUM(d1Obvk8PTMCrBWCNGN27E6a0VW9i24mxn4SX7xwV0Ot(GC9gp9MU8KC6QaVV0gg5ZPAL3doRf(wH1u(FxRn1vewx7Lv12JYtcn7YBgbl60eSEXo6bBxrK9kPiU1OAWg29UcrtNTmRUlESrCz2bYz2fdHYC3o5Kw511ln3DL4GjEhWuvje4hULuziM0B6upyW2m2xXflN8hvT1usa5pzzvZJQUVl(jCS7LC1qrdwtrDKd3kk6vhAypb9qD1mnGW6i7VxxbEdUNTUcuMIrxb7uSANJ2(kvqqvIkeTdFth7TuIHUUSNo6KXFK1sTOY9xLnszlSyOohGkFgtU14NnC0TZ429oSeYGruRiONdMUw3aklT1SfHD1x3G9WX724)e84sEkIQ6C7ZkwvVefMiWLbEW60yILpD7lgDgafQ61umJJDdC(RwDr9YlN)m18LmMjPGj1ogoYe06nRiVWlJSInlJtmVaHSLx1X0N(WjvROZO71zlIycfz(CXfrWnwEUZe0fl6td8rDM5mtgODhD5xo(OBUC8vxF(LhE9XNF2FHFoFRT7HyyQBVFh9cbM6EUb78VKoahZH7o5yeKbT(s7L2vckXCJ5xf8fe2Wy9LTLqSfWSZ8s6O2xwGbMdxNjvvKGUkOtgjzj4ooV)CFneJ7R1D1Eb01tp0QwwBdEZ6SxNSe0YCcYXzYREjsPBDCZHDDGjDR(RMKKcPz5mcZhmjlOLVlgD95xiAqCVP)pnFa)UDKWHzoprR13mnUv6F9MkMOvf(UuY(lLmSemrQPaCAPjklROO4NAshMMme(NKYmWjq0UAuaItcOLcsqasDoZFdsqm8HU4Wto8OJp7MpD(j)VVR7HoL4hcDpzjzGUhqIkVmAWp1eJ8Ewg8)JttbboTmf15FFxRKKxY3p7sF2fgw(HrKausCmQlkoBaN9q6WS)dOmkB0PNF2NV50JV66FF8H)24l3h9rbyHH9Wwi9HCHoZLIJK2mmJ1qEp5wmeIs8XR3qiVMWeYoOW19NTjpI1hCiX2ndHcmW8HwOfVgtIIIkZbDonrr5dtlj9r5Cfsh6KT(6BTmBv85pS9My0k6A3AeO(JdtmC8jyz9nhD8v)YXxCYXNn()cKOiF3(VAjk0PkljQy4Oo4eTMOsWOj0ikWaQKK4bGrvPr5j4HEdgKtMrT7YyeeavH9N85y)KXgYIyrkrS3EZNE3M8Vbp3aRXhcANe5N0IIHG54SyutusP(yq2)(3utYho6QpD4PhE27bf4hZGcuco6PSIcZC57gF)UX3CaPmNPLhfxcNBfpOiDaOXjf(tPjoac4)Ft16uoA8VD(NhF5nxC54RgF5V9ESiBEub0SFiIhqsEAskyLusrsCEHXpoeuQVRc6DvqDvbLKNhLb6GsYlarh4FZYktbh3skYjJHsalRTJhatN()NrN0HF5xpD8zx)UoPFW0jLcwuJMzNKpa5yr4FltZmgxt4v9DDtVRBQRUPuWfm0tFq(jgdYn8V5db39tkZIyeTYXO8T27m2JFFW1lQpgI18gNUUGuPrUuqbXhxoFg1FRgF)Juvc5I2ulyOgnAw9Yhf4aX4ztHJi3AXWamUYSyqFEurEAXayphCneg5aFty06mE606vWOw)LJ)4Yj1n3ZLo9d6FokhrHeMgzv9atae1tPBj18IHnOUgrlz7KP1)QugScmQPuKwYLQANwfVDaTkPRvvQACDCjfcu9JtM3GGHNX3cpU8Djur3H1(nvRG0mfED6sLtgzIyPOF7zvZOk2XTg4H)Nu4C4ZVtLC6bGgM6xNVtuXLXSzoN0Bol(65i43J)ogPgN)WdtLkt0Bt9EGbfOyfSrCszCIvnRXRLh38htARfmCRXnk(KKXv(Np2A2thCfM7wVQgl7YM2RRUvM7W7m1eB4fzSu9Pxo9nIQKtUjOKGdGBdNkD0dve43(5QMM6LR(ivhPuLdRrgkvtVi7i00IYL5yvwFB1up19881T4mMui5CHVcxBjwDD8doC9d1pfGiScZMA4Ko0QA5eWZl2(ZBzKkMJkNoWYA4p)7",
            },
            p1440 = {
                s64 = "!EUI_S3xwZXTrY6(xrVCUlpiEX(MFIlAHHff1HI2J9eteka7gKehbc0daAjr7y(VFZVmRQqb0O7Mu2EShBQiSjz3a1sUNzLvM)832fKDxrFo9ljzfRlF)I8QIANdIc(MVTloRBrBrr9RRDdcCS(G)wTxyKZ38VWB3F)Qc6hxVUQcVXNkA7kBQR9PhpiBzop0UEzRRRAw8X3KFFZ6E6tIZYRxCBtBhVcokV1N(LOS(82Bk6PV9S8YA6tXd2C91Df9)yT7brrrXjjX(rPXPE843vUSOZp7YZF3Wt(d18kln74to7dxTMEB7H2no7fxC0hoUkVR7IIUM1TlkSNfVWds899JdC88d8t2XSeDGRJFOByKxyXZDcXC66kdEExpT4FmtRdpRd)BF7ogM5TFyM)bXHoooPoHPPordJAq2BEXlV0gO98nwcmq899eIQyYUzw8ZZdpWXjko1XnY113lHbkgKuy2fN(QxpAgDJcoinnnjMWMPrPc5entHF9BRzMfEBfegg44hfeM4JPjk7DftXqZtZfCa9kEXHXPbP07A2oZa)uBN0WuFNuA3a6bNSpxUS)2ZY7xClTRszYJ318zIjX1Njqx00uTS5Z1DtPEM7bMH2DUhZtXhP4M0Sv0m4R(gqHEvERHJtODVTO8MB7Lfl(e)Sv3Mx33C3rnRRx29ZylfLLVCztn4P8iQ9QQIU7kAl(UtpCrpX3tOp8vex2Q1D3wS841D07FCtvdyhCjUExci6MDfKX4aHmUz3q)EIFk)7T0VNgZij3WSUBB(8rvL)0pD6cAOV5L0hMQg4VRRG5H5HM(cAXCljmaBSY6BoSU8UCSE6iko3Omnu(flVP49L)urT3byD45qV0n3wHT9LfFPFDBXLK4SAiCH(os2so9z59fNxFScpHPkC04nDLqtNS3pQPDzrlpD8gnk7QH9YHva2YadVmcv8UMUsEbBlq0n7Esygen3wu9UMY6Ec(F8lE7LV4IVTlmB1KpXn7lISpMnkIb43xh4KEGlj6u(x8JB4Eor1FGTCjGyiYWV03MRW4R77BQvZ1Z9tap)Jy9(CF)HLmeOHL8ZdJIG0(h6A2W2diWZDJez4Q)Pem)9f3wUOQ4fFPe6F4zjij4RhYKKWkKmlrnyprn6(knj6vXJdQKMKmfSBKn(1aH0YRaaccQSjiyU6lkwjc5XOh7mEV9Ow7m6mm7hE3VMJhXK8I6fKyO(I2HXnizmM(XToNQYvJbJ1yWOhlT8mynJAfdP9V2RzsW9)96I1fKM6(1SWxW0N(OyGgKQWeiobS5mJ1(ZKDrP7fMytQfemdPMr3RIqEVs4gZEtmuZYAeyGWUUh4rw945q69zBqEmYJI8sHoFLfGbIE80b9etLQtkjBBw8QQMpl2oZ6vCnF4gAhsZw3vWk1YBxEczFmuzcnBXJ0Q81PY0nR7FUoVTa6lvQ(URHMVgYS83tktpSQcke9mlpwDhRfkYED9((7RkWIIgWIQIf9K2m2Cbb3zPGFQAZKSsAU)7nn3vhEaG9WkcfaAypb1)(XWEur9FS63BP1cbVT1l)lWcIaOyDScvpcitcrox5tXZHjD0k8kwj27itBiJhy1)UbzFQS71KjfVT5f1f3DVanetQ(BWOowZCA2v38I68RQkwspqCw967UO5ZDgf7SjahrQEQX3tdWv8Nml2vdn0gcXkUcY(yX9xrVUSK)bzKdZww2Hz9sYSK(YvGakoRqwiadNKr(zD(1xKxFtbpz0(clGi9W9YM6EB8Hyw2nkZZu4bAyULiFO3faIH9jn)GIQfqh7nm5vx1NZVVdKAhXGuMi0akpJfGZqIWbW7LmmfFOF2D5lABWAJnBYfGyAn3wa3kzQ6Zb4tE2BAB(8jLTe1jSBImYRaAha3oHfyoGAxgvMA4Sa16pkqsg9b7uZVbgm2sdw3fWqqm4KtX6fY(bstqr)Oq)aRxZxvyjUaMErBgyu77SMubAi0fxs2O8X6IUo4ynr0OelC3v59aMAHbikjga)Emj0tx3ut(XslCM((HHDjMHkA(U822M13ClwhEkeiHUxwulFIqY)A23abOry)XexSKxWtRPI0)gmNpHPJ949nrp(rGzel51wLdSYpyJvcTPsTOeeB8)wHHqicmB3remkUmBhey5RaqoMuoMyGT5gDeHwy3ml)OJctjtNgJAq0pCgBsOJGYf)oilM6AQkxY8UwuokuU4gJftNn99G)nt4CCZigFIRqCfI8g9w6V)jI7kVIrjwYcvcw8ecFT8rfpInIA)8d(mw6mmoyZHLoTzZB)(YUYRkRk7VhErYck4DLrd1mK3IKwpwtXO1gIYd)2Ku6ZRRU)06oosfSQuJaNxlsVeczHHrriZdj5PgZiYE7s88gvLRkkwcYzLcmbtzHkSEwTJCJC7AUfWtAzUsPD5HQLzWIiqhTFcVzu)mIA4j1p)hL6hXs1Nu)a1rKIuwn6Fev)SfJb)1r5Zw1T9a0YeMvddhFGkzccpiW3ZjnjokK(LhNgNz9RyIkNnNGFL1)SzKa20EUnv3c2mTTrtmYCEtMinLFOl)tSlHwHXCdDISc6T5bX2nFF7kI30E1P2vKoOdFu84EsFSYM5FrE99K(4hIpZ)P1DWN0hZbRAu4zEsFSoknpPpwcZQL)GwhcYdrrSoiWZeTN5vehkNUCDGdtuUdNSNXFvjaawX)rcB48X7BdB5E95xC6F)83E5HVzhEohPor5A34dIh(hsQITg(ojwrtpRNFHGVTTT2Q9nBjsaBAaY8bcWk)cMnwepfkGhBOa20hd2a9Fpd4CqwvX19pfU5Nc3S(qD(Zv4M1NWGDiy)nosZ7qd2mMxmFKJNpkXBg58De(4zDM)X68Z)UI3mNZmpDSMQtj9HDWxp8J18jTm6Jc6Pd18Pd10o9nN90rF6qn)Z5HAIuY(jLm)wL7m)URKjmRfz3Xt(Y8KVm)50xMNsDgR065pIPoZO0K(jVz(nYBgoF1(9mMzpLKMpLKMMS69PK0KJb1Vo5jZJn8upGJR7pNjPP9vD6x4Xk9xQtLJV(z8vJ6PKP5PKP5P7wH6cnVTdYCF3TINsMMNsMgRlM(KlUXdq78F5sU1TCRZ)fQd)F3Pgss2zLlABu3H5hYI)pV5N7K7x8VV2vmdl3FmV7Lpwl9)90F)NcSmBV8t3jtu8tKB(8FUssMTC3x2AEY8qVZL7oOap(Rr(85kZoY3M5Y(Nh(fWC2i4oBsO(WUcmZLmniFxhDVm56yYr538KUv9DFHljgpOOPZrg(PsEWosb6n505lL8VNAxFkA6pfn9)Chn9jAHuvqdD5i4pnv7GTE80pCnUpKsEaaFpm9TtvTo(sEyUIlOu94nuAK2OwhfAk9p6s7Gux)SkBGK(AUMvfMDv(n46N((M2EuClKRJc9HOEDC4YLhN3xCtt79sbLH(8ZA(uXBBE)TLxZLycEaOh6YY(kPg)5Yf3hEmEBrx)r3)IVSkVgvNuPQaqF(3x2ToVIRPm)8BF7px7f64fM8n1UP(XoXFd93U0)(MA6J9WFgfeYFCqAId9y0p9dIWNhheLI)omoKECVOe)Oq83UEPUFZ)6NRXlGpaJh)thNqh5Nb4fXF7R(PNmW8ag547I)o01jL)E6N0eYRpAbqdl)10JZdl9tFAyPLBe904P8O)0n013HNTKqpEuM(tRrN)(iA5A9t)0OOa6VPFYRs8t83HH((y7hg6fZVxiTZfWbTT5NlgGl6NjQ)oblx83QXjHx2oPmyt(5)6Njagnq0OXJzsaJjsDWZ66tWam3bjbjas465NW)TFS)o(jEopEoWiO(jgx6fJamYlika7z67DiiVBAIhMx3ux)u65JIcP)6X()5rtnB8pJimdMLX)e7yzxhgfXew(EjXcKXnIj4Icy6KaVibsr)nta66Xqw6Zd4DFCSl)CXXYUeKSQFciEqCcON5pN3T0pbgKG8cglkoIjyDtCyCTBsIlWdU(XrbaF46gLc4veb2OzmkfRd34ahGr5FINMWgXrmMuQAbxEBXZoS9oI)9)44f(6Ki8RflKwYYdMvsjbAml1gsKybGhU8tf1O4d9S31wS6VA8CGWmIvAORywIwdU4VsgEKFZjsnwtR6PSaAQIZufviO0Hl9ID9p70(I76UCyev6QqjzSaA3CZoUPUB9Dy4WGKIIx26vVn)UInreSYmZ3l1)oESJZEvrE7ZEr9TOshDhH7(QhRWmMBC6sXMrDRld)mSDF27l6FgwpFvJrs2FRiFfbtE2)VNDzBz9hl2CVS)fJuQaVkV(JVNms4QCux9QYx1XLyo6Bqjh77wDtB(YItRxwUiVVPvcNoHDVOafmUtRpVUGmcbVGFwjTXQk(urfmLzO0fRk1yRBBlQxCVyUGuwiHrltMAJHlWAM3vwxxSKjpKLKYkh6ZL5)YYvCnYJntbVHAzXeu8uGnbgaEDDAnmysQgyI9oSrrYsc(6ltOqqI)wgo9FphyVtrlG7K7ie7eY2zP)WZCjGVp7vnnlPz0n7DTnxx0bZS4)8II8BWkaRBAgoRSBrbHKQlAwZFVfd0aVLHt6KIRZxx1l4iABtMBQmj8f3TQ)E1(N4mfyOubeFvt1sArT4JL14DeqRP4CsyFdAEWdcv9EPq4TwockdlqViVEzZDKacd9Jc1QOFeuYYI(8f3Q2Ycvfkzpqgt167mhAoVj60L8zvDln1Z)GGWOyY2G4apE9GAXAIQuiNe746cl41195yu27LQ4obxBlQY7l)uHuLOPj9OZV8YZpdFVMlHTKwGK)T82Ab4i0rGWJHyOa99sXSElJ0p7((BlxCz5Derg)kCnmSAD3LFUH)uvjN8Q)humg)uX0Y1LZbs19gL6tR68nxrJObBvvz)7RqvrFCfcLSCr)wQFvvxkbFxRQqUXptaVIoxp)kgeEGFzEx)gd8KIDPZbb8AbLqtuQpBAxu09Uf9egIa3V5WJEbUM7(Y3EelMXC8)OahQxLHYcgv9qFPHaiL9qUaIsVNaMgTub4dl3rvVtxba3w8PYIplLfGEaMvG85QeA6Lbp3ka7YI8(BXeCAn7vK1irUcv2sA2gTreAoGKKFJlg7QQqApgasQ4HlyPw8wlVQ8MAuszl(spbNuf4Fs3PfueFhbpVlNik9Zo(8V7Tx(H39Ilqrm3amysOJAlY)iQe(sX6RrJlFv(kP8P7KDDlPVuFDuvL8aEp2zTbDeqfeuAbVzi3TTffAY1u6XmokcAYWSoreXbCjdMWtdJZBkiFmnLYquObxMx1utmBIfbsLh9hQt9srrLoYZpmXNRU96V7hrrvMRRWKdAKRDmynnl)6Rl)YGzh0EeiEbgl6lqPuuQ)Smr5BYVQGlHVcjYH49LAEiT(nRlXbDNdixiyMdBQAIKon77E7jV4IpC0HxWFTqNmPe7rKrS)Zm9G6xzccM6Yt44(UvliHI138EWPj1XvSyaWDXhTQnu(dSbk4iT1mO4JBUBvEBXznlrLm9TN)2xWfzFmb4RQk6lwEwzvvzxXIM6LGDH(6PV(jfv95OuqkE3B(6ol4RFwpreqdC1sRpflxn3fOrMifAlcleC1jm9NOP(kYuqJmigKOcTb5dBgr9N(CxNN7getUarIhQJJGNsUW7v3q2xtI4q15d43Wr9grE0BeqUxfhq(O5sUZdpSyp8r0k4Z9G8PoZnHEoehaxo4cUrKRCKdSo4)7Ni1H1Wm3ix6jTxmo06iH04qVhcYGBe7aCqitKgLjR(hWIMxd2Btp4bj5rkwOiUjUbWjvD5fxTOPrE3pNEnhBTM9tPHlogUE6GqpqUJYafYzuEnh44L5gqUX6GaFeXrgGbBrmGgapbAWpyK1i7ga3AJtP)NVlcWqcplreVKcAerVWpxhZGyoSqPeAJC9LDtoiLC7Lh5WqGrSg5ie)b6n4HdHhIwUMbfO79HLPbLbXbwdQhgOyeBaxpg4gInSRtKnDbrX5JaZKIGdrpbwOXKmi6Dq4PgwUEwJCicGazYbESqeKbxetRbyarugcF)jduOvaIQarncaMdbtgEmcjecCtIhIwa)aEi0dUo0yoq6squFebHueSf3qj0d8ZHW2mGtPTIRpWHCCm8zQQeElhsKew4uBQL9(gHHesn1AZhZev(jCvxKybICYCPPoYLz6IbGof0je9K6re2kcfUtUjMUGMlBUKiW6LI)xmdEyuLRROJqt8BJZda5mtULIGe5gWHEbWcfyh0ieyhrSY1LzmcJ5rMEXbqjTyP5IqVXeNEThd4tCWqfkuf(qwbXDcgGqqOhbUoxIxdOpH2vZczV(2lthdoTznIzcZaFqRfZCtHbE2BFBouiLKOKONnbrKIiqy5O0(K3BmIG2(7fkrSCenSpIxwymebYc)i5Zy3rS(k(cSwT3DSWeIggtAeEzEDpqjtt9Uzk10a2uOXKP9qxaVmybeiaSKmynbyymrGssD4OTXYlDLi5b8abUqu7agJq6GHJgTaoqCE4xDdy2tekBlM9rkKymRdOgyPs4fvWtbzrt92Wrqdbb2P5D37cEFdGUTC8Db9v4scjTpsqEbms41ULmX0iqKZUiLaWKa5b7b0q47DqsW7yIjkaAFIzcCNewxFkRUGKkY4nsWoTnHixo06m7fHeazrcXzQrB0Gns1nPvVoLTJqwMjSGAq8OFdcWyt9UhzXSslORFBBAns0122KDU30sWSrp7eFc6jIApeu7mjmtvkNira2WK6bTSr(jhj4E3miQXMiNJ8WOsIzb8ITRk1hJTFQHLJafqMplEHpyd3ej03egsXSrd0(eGiwMzBV1EnrJ3v2SNKbD0kmI5aJCGO8y2SrcEyPQLWB7uxciOjI(TqciAT12ymcBTxYYjgLSdnpm)autUFkxcgm28P9IWGsCIQzSUBXcpsx3onStBWMTq5DG5PbDFgxcsncUaZK2MLuAMPrk3Hg4ywVorrcIDMjiq1Hbv2VhAldfkVIfBQWPbsShSYEsrMLcABq5Uv7Re7s8F(7CKvBqMxAlw2QPMgTCXbHLW8a(IUlwvhPf1wJ7i8W2T6If8JvadQCGXQj4GSWXxXmZAyGisX2cV9kBHzCh50XoTHwb2GT2705eT6)r027B5ZRfTm3ai1b44u2QHaX9d4GioKtLOPiYDcL5QZzQIiIb0W7uYIEXAB)1dWZhAShPnEN2JOKjdgL98CcuyFBELhRWeWDYlP8)e057JKKN4r2GUhFv4xagUSDrNSfJTnFgb4s1FlqafKGHjXUsfps6VSJ8MN)4yFWXhzsVvYe5gj4Kdrfeh9Hk0PC6qSSyjTiL4RXreBVTzbeo9wjkCbESUYXncsCOwRQY75d6Yli7A0cswwDpIXSkC(85EjhQsFXxqSF75wVd(GBlYR6V9DfTigyCGU6BwHNq6BJQKU76MfRLE)4qtdXZdDfPvfvOzCram0BR0ThsvmRFPAT823DmFEmEzlKE163vxIq41UEvF5vv8z2Xn0M5cbn)PIKvubiXABu3Rbbud9DwKflwlAF9CP7ajCunPTNccCzZktF8XZjlFDB(jO5tw2uJyMjXRcVdTQlVBvtBFEDp63LCVhJ7yj8iMQMEMqY0wjhYvqcJ0u33fgMDk2YxNVO4FC4YLNx39pSc5))4UILL5)d(r)heLsBrx3NZV)GlVuoPmnwfOse0nDxv65ejHST4ObQo2fPa1I6blqUG6w11BsYY7BBwu2Fph0U28YLNL3(rvBZKmoMhlgjDJoQM8ji4MvtZ8OE5Kt2D5F5eg03vJiFs0LtHI7L6gX9DaHyJxPrBbsEDU9ToTRKXn0SbMoPXMQ7IwX8gqcpQUnEX8LbAA7n6jveF5DLsxLBaZISG2MSINLGmdL7ff5lV3q6oenF)HJLGC6auUPORkFzE9hp8MBABgASneD3)ehO9znxnL5kAtIot3Qs64veKRz1CCeZrW(MY6IUAgketeKe385FQOTk)EnwM3Ci5Y6VQ5lmz0pGO5Hpv4Ky67He9Iw6dOh5WbNTRZo3HCiafAyn4xCYp4kl033ChVebKFBCu0oh0zVVpFXhFyDQMqzldUxL0a1wJMiEo3qOIVfVbwCmWwv1M0Nm1P1hZD4QH2XfPpfeIie(UQFFOLCXnroL4sUH)jOX4XBgR(QLHCDK4UiZkzqknJ8Sh)9Z3Ho9s9hFDEhtsA2cKVT6DqYWPsjgdtCKAE1J5tGXMnIOhgPBzelwOnPkVdjxRy6n97GJ8Plvo5eiJJ)sq2H)Wk9cdSqyBiSN1amCWZPtwU7hOeAMYrDKlu)OjYXhutrYXcllNt0c5KCNr1abZ0Y1Fh0GpcMjCDy7V)1njXZWknLyrjDfaylUxTcdUr8n(scLidw51iboiTHGmBOJ3fM9r0d7O)BuRstu)WJMcdCG6uexSyqXS6i6m9RDrP)WHvRLJ7CG4hHKngARiiy09fT8H)OSudqNbL18LQyZ7QdMchUrmlCM6FhCM43XezdapAudQBO)zJmTZmg2mh0VJXiYGm34iRdCgo0AllejZlOxmj7UY6YRiHmgUW0KHw1Th5OHODZ5Gqx5uLqBu0sLflmr1Okbx9BAqxyBmJT7auM8YupGYzcG8za2dAeOiCNJNLbniKfPe7atweRzSzk9oK6WKKznjippK8Qbf87NuwoOZdRQuwwihpTwnNi7q1ZxTmpWCl3yQdVrQBnqvK7UAeis7snqWvDwDsYdaLe6EMyuw(vDnTxDCvrETOPuanOzLBac6ktorUAlt1Ys5PcoNWJY(HmWaP2d2OyDh1tKczDwQKlnAmNEqFo2LOploCGWXz1fR7BZRguvTBYbnp((XxK8nJOhlzVKVbR6EBrE7dNkewuySBBqKKKS5AzHA75ySWGaEiDBK0tHmIhf2asaah0HdA3xrIQ6VTZCLzr1bqBMZOzro4zPXIkjrXyTGwASNR9Ka7Mz)ZgT(ObHr4tm7J2P3M3Dl41uUKPi42yX9Jdnu1bjbt8k1BajRL6i87KiEARs(vcc9tRzVlvzRYaz4jnRjxZWhtSbexnO8MrjgXFZVJH0k0sw3q2hPoE7zDMAq(L)y7Hh8lusTcw(DIvA)4gQLF3M3w8IQYEUR1kwgOmEvdq3pTCWGdtId3Su(Pw2mI5DtFnuignyrujIDiAzURB)ub65OedPMSqSdF13x7kTZ1alUGr3RcbmpNz7QxbwzS)nj6kP0uU)hCWD7jUlnWWR)cEHRSBqcbGYXFH514gQDZafg5BS9E0mmOiv7TRITBWDhJ7VSUrYtXfpmRZg5GdssiqJmhn5(Yul9j7zjXYk3UMV7otklTmgB)iaXD63VkFHPlzB7ZecKLsdROmInZC)d7y))2)ZNoYFrDKeqUt13wUQy5Z)KhcTwF(k6pgKcy4xh8gwcJd5wJcmiErmyB5aaIdp1qiyidum5137KCEIq6KgMP(VSXKQXtw2GmiV2kUkVwhPeT)HS9IkEfTpYkInOK)TntuSnyFPkxs1rJG0QXeNwkTfXVko5bZes5pEuiCguhy1SEfGbStXKmOKMqL7PB4jRXeT5u6nUDmZTu6bBKu)km8K(vG6iks2EirEwSMcaMBCBtxFPvK8Cg094oyQLCY9KibryghWfESOHUOI(jrbxSUK5j1UgzqnImz3qvJoCK8W9tgBzP0i)wDhzl9qmwuY0g5u7(NLXMKmPlB3Hiwq8YwEofptyEgzJXLnRSxUIDasEblopfnOzmCaqBsNGflyd1hmZzmPYexofbj6peKcQqNS3aeODKaKMV9DhZjalBiRoCIJLOoxNlNhcOT1wrNwEJPLRdQocmQelojGNINRlmHAtSEXY509GbXcW3ovSpj)U8BkoRaYPq81ZwEhafPzxPZFwRORgMDxE)IB5nnsK03U(URehwPNVP5J3L3(XUFMmCJKBxh(n1cZGp7DZds)LDIy7XsJStdvwAaTJHIvyS6HIpHkN7gN79EUw5Vk)IhwV42gim(62IcSIlHHumZjzm9QIfSOBJv1Mi9NWpi)NMtnzWPTjZknaMSMLN1rVcjUDz7qGNfB(q(8pB8R5dgzaFY(h7eMK45h6Lg4sUkRTyCMpgSot(yG79e3PaYyJBxlUfbTVSSQYkrB5fNwdnG2Ay)R09lDaWEnm46YMMQ(YvGLWbDr9n7n7(KpBxWVxcFMbd6)0J6rYOsuxlzt3TSZncFMADBN041mnOKs4S5c4E6mghSFPAKztYGV)hvirKlRX7lQUwDLmycsE5IDGE)i72um6AtdzdYiWQM9silLRzbrj38z26z2ewfevjcqulqF1Y2Z0nwEUR9lglqF8yAX4SpxwVS5ZD)myOjT0RBFVCpAy2gsz862todhQLa0diRX6BE)NZxjxpdAytYw10vIyKPUtjEoXhiIJ)cYkO0dCJII8ctJJ40BZ0G(84CEpkRQzXhlwsKe6wlOhoHV9UEaAC3ZDQZx5ClA5fidFr9etmtNsZm60b18HJyMzqoOziNPv(efmWDTFcj73)hQFoK2neudvU2dogfpX2BfkEq6vv1Rl76X9HfdZD5FHeBlNALYF(neGjcafyGQfkIJYLeRFA9f5L4kVrIwXZCyDjXCHlGfjnUIEaGDy7g4ZqufwYoCoC2u58vbsnGNSU(Mc(IYtgeqdPCthCZUVMuKFGRRJhjsl1tfeVVG0qm6GapVKq3qIatcJ4iXH8PPMoegXqLDcqmPxkhgXb5nBayXL2IwgYUDyXX6FEdt0kAwTW8CSweGYneB6jLT4YjraLGSto)V9wSaznkCe8G1YKWwBeZC6r5lWhdIoFnrhDAnKCTaXKW6uXXDTN5phwXA8Jl)zNdpO6Vx0gkFKTiBrdJ9dX7Rbuqc4Qd89I9t9cJf1ke)TFu8bo(Xij(LKvxn2wwQZN()MQgLRzczzhTNP9cWdI(csRSEtmDdlRYHXEG0xm5C)g2mAA0MCmvlNMQF4cxnVVSUzTfKHcD3ErEVk2ZkT3J0iRvbZ)Kij)M)1)cQzJSnX6ysXiUisNLxtMAblBJZwS8oWGY)UCjdHusc8aa3r4eN)B3wuFADUC)34VIV4MQpbpIw4pzq3YIU8EC4(e1S8k8yqVhklf08ixZosRmoBDnzM6E(igtzCmGEfs8FneFtV6rk5pXzKI2liTjmv2ylW8rJSbkuuB0oMAv1Zb0HAKfZ6NrK3K6o7tFA0nvBhvqS5QbASjISnxl(iljBWj0XgQqwxJCejntJmWAKn45iT3kmtNArFO6uBy6BOICYUt8qf3UvEw5lfQ6vVGbqkrphiNlYSfRUX28KOGmx2yFuuecdchEBJe9Cw8zNkEjIDuQz9iH5N0HRmNquBtJL0urv4sXEeWQnyVIn(u99BvxJTioGqvmPQTPqIQSArKFk35kH(xDtTW7a4lN5nPzKDo9LlqrtPSOUNvZix4kZExUUA2Fgz)tDViIEJUJoF6aZ24HLl2QnbOQZL4QHIJoBA18pC78vEmCBoroO9wtai)9MM7WHTbKTskK8hkWUi8ZGSELwsnGoFRQ4FZIx7wVIZmMxD8jxYMjnTm8G9W(qYIbddmSQJlXYLjHHnoBDFzLovz(Ayx3GFrYUksmHywHCCOcTMYHH5zw3vVMEouMIDoo77m7GTZmlG7bwz799MmYej5cPejWBKHqz8Bgl9yEZqf8At5XZlaFSRgBYAprW0gwVyUNTw82EAczIu6)y4ThKmQSdsrrpWuprA5Vu(ztbJuhchY64gY8yHt(RI1E7i)hPYyAGGbaF1kI3KZEo1VkDotv)QIkdP687NlmaZ0R2X13(fxaRvy10HzS5ltfEmMuFGHEyZUj78yQIFZ4H)kveVHgZn0mVj7RYCnvcpAO52n7RrpILQZFrANhPU4hR3TwxowCkl0ONvrFmJM45RyOBWipVKWFP8Z7v)8evmkf0BXIlDAiIJX49K2WLKIE7tcQbo8Dro5wS6CsyJ72Vr2CI(H0xGTJR7ZLRkmxpFL1WKOho3bLcr0wm7EIaLbNq0l8lkURSwhuljpPrQ(sZU(BugDUHM3hR28z7BbSzCBATG(iKVfgepeWl1hp4h051KjugbkPzVel8VLbBtSiz7YCF4w)phPhziH5mWLG8Hk7drcOQXkpaNcCdZeV54c)ecddIlqv5p9t5TKAMXsZ8gDopZfOcJQ(rMTpYE894zWG0ujeDMaEWwmOu7DmJB4QQGZycMrPDYSIFWXIztInQcHSnNfMFAmXKB0aQS9EcLS40grhoK1cK(NIEXbHPJ)OJQClIJjpq45fKC4UdO9FBKXEpoVhebn2oiUX6vTNNXrI5D(FRUsmR)xXzZj0cyDJ0grKW(LJHKPGTY(dbFioXZj6drUXZlrBKGQzJGaQvNBjggtldoMfQcJpNEXGSfZjDzhHMyRPR4CgnPYY(PgnHpESNa4EFOdRZyXzKG)tkUUOUJenaB8MRPJS7WjTnrB24sHvzSqMz9F(xUKmcdUzOoMlKi7xiNr(6eKYW1EypY4gjCCVI42Eem2V5vCep1hhOkNpTtkYX3hIn8VX2MQzYN1rNhTkoL6ZpxomB5OSgBQWCbCyB5j7VudUgj5qe1or38mwCTZWfAAIrJLaPCRGyBED5YLf1p74ti2gjki0h(HpCdYUJpSaUUnn6(gLM0dw29k8GYTPBlSqwumIOWH41T1i6SdF(NZI4FtKdh)bxsoCQ)hsdMxo8euZCHYf523mIoTrzBtWZm0Itf8Vn)j3ul6J1GYznFBhIF9ZExtF3Z(F9SlYxuMxTJ4nUDfS2sAvkJ2u478XRCSqqjKGkXNdU391fE5hGdYpaJshcB0(J084ZsBRrJAdBlNEhbmY392wcpPdy9(d(8SIU)6L)ImLJqsz3O(jForSOMPNIWwoJMTjaES9cZzfc7R92dj9msG38urMlU0)rZCsDqB)qcjglWn09dP(BXEY5nHCt2XrkA2MGn9Xdzcb1dvO1oSzDoPxsYqTf3H3kINRfFBXeYWbtiF2SrBBQXOBARWmYRMZ8HFdfxTL2a1UDBEEHQBEQ(k)0)knxmqDxJ5taZ4r8wLA9l4SYglyANI)gXVVNByXwKAn1FGneH9VrRfNrw1SUcHZKNV7Vllosf9eUayhQohEZT(ah5MXZullIu5QYZ9c9oiinnfvPEuXUqmqAlQKS3kkthgBDj114ls2xQFEOR3bHooo(jUbOWNPUNkB4fSEUiZX4CTANZWG1Pyk8sCoGMbufhtcD0PBQYrBxNp4M65fh)b)qUVlNDF9ZJsoaLqu9)230nSfrgI8CxA(4sqQ8p1vAunF2sIn7PGq(f8qZqWbjjZJF35Keh7N4ivyxJC)ui33317dbjMnNhFx225mmzdflxeyRuzyaBmER(OgxwDVsfHEat8piMiLuus7LuA8cvSFWqPgIyO45(b34eZ6n9bq9mz375WJR58rnu9JPs2hmDevVFQGXnKi0eiPBln6(zEHr0ptYUlF1QY6B4evXO4vYYweb0M6Jw33RYCro7zqsFRYJr1dKlcSsZUPcN)SobFgeJriqj3)5Rba2Pk)c9D4ZB6z4248S)pf3K9Stk)uzDXZE362vnDf)FXtEhQMSrzhE8LN(9VqpnY1CxDEJq8YlBBU74to7LSeNWSUIQIfOAZkBp6jr2bLf5)xXnD4F520e9Du6VX7AHywCVWqHRUBo)(qFdUAN)kURJ)TEx)hpzzbzKXmqPZF5eHJEH5VLB6)yYx7(xSDTQ4ru09XYA5gYZ35lF95YIRnecICMZg3SQlk6Aw3UOWKNVQsdgbbtZQ4l34Ip(kJmBP4m8g1NZjJkUu91lUhpJCt39YUzXYJqYeK3YFSyqd6Up5lr6tok1SLKXSpVsx2Ve7PSgcjUJtUovJEcoryHxiHzxxwvDbs6(iR)X3kupPejW2CXzL5qMyB2eYD1kwL(L6G9BL1b(sYYp(MKI(AKSZyGGedefyXAVoAjlP)4WBQULyQy6DBEDDrfa9ark7keUYn2vd4idminBDnUrldzo)ZDDDpaGJ4u)euReF8UfejnlG5o(JHRtJk5PL653IpIsAgthIASN6p14s5uI)rYFteaIHRaHuQz0xO2XrhEaybqbFu(HAWm3kxqt3y80jh0RmOVFfTEe2ITCA4QnPkIdpSiQWdpdBg3ql0ujMbZac0j6jUUaRBhssxDgoWeRsFG4vhFIMps2ygIpbrmarajpd(TG1GIad2anIa9LEXIQBtQVYtUB49ekeicVYlUBfkEhVVp)gUagomGcvSH9b4fwgGqXQOPjB(uShNu2Iv4Rp)It)7N)2lpu6VmcYrXvXjPUI3bBQeUmUjJh4UMWbOUoxO(6nxIiVTC0wQemtl0tdT(kw(Wejo4chO7IgKa1oUxyj3vER6IhFdjsZirFF8YBlUdxkIP3cPrEok1RlvVIrNV2ZiqHEo9SlG1PIo0cjKVJhudky8HIzyyDr6sn8ScZcFLEgUBLMaPzlpvkJt794CMLHDZtqh0S69gtbnAvPLy0yLQlJZF4nVkJ7iNxNtl0aiWKZ7nd55)ukwZ5uSbeXWbRUXSMDL6KZ8g2NVBrVuszMHfMedPbhwAp2YTvD(ZIXCrg5sNzmketDf9K42iv5aZmdgnw7Kl1MFwRJvfpbqPzFb7njMWgGhntmhEH4SBkQlu1cPn67)JKqS1RE8u90gLkOGIWZXQ2Y7iJq(Dr0GQDwjL0vwQ52ekixQslRmgjuimBvr7Qv2KkgK2ELkqCclv9ZrseRi0AhMtGMjhxFCp9632OnnKx7BAtryaFVAL)T3GKotKb1KL72OcHjrlpBwzutf39VdzwZjhzhwFoSehU5val6SPy1nREvwyznMF7Cz7wAQsaN1io26A5Qvnwq28NI6wTIAtjAOysOLO9U82(Y8kDhRAorIU7uCGXGLuoBIEuclTeeY2D(imtrSyysrNAoD)7Yufu6Z6lWDQKDVY2u3rgrA7VJ6gjT)uuy)zCpRWzCYXo2ghB7T5dyqA9ykjOBcQvg3pO8gl8rNTCIkvBwccx3Kqxp)iFNisanBT6M2HzEby83gVGASHLTJC3trZAUdvw3ISXszS5ouxJWn8lCFcQfaT6cVBzvOCBYunFUj2kkAGmFO1J6WLAUVpVADrxNtMGGkwC6jCjkrvkw2c3Zme)8f7fEpuED)lQK2LRTWCCpWB(CTT5BVTXC3f3qFcbVwvUsFpTf6NbfvgnjcNOQnIIBkW1vnFwKSmNQdFF(88C9sts4CY(rC6xmmrCHrDvnhBDRHas7lVX2hFmt7qw00ScqfIGTNdUEKntRZBxwMxd)pFTQKbQ6dNtGgAlBdzbjMbv9uVexgA(AOR8GZIGyIf5eDeHsSUiQB4s1E1GKgGBmVxItqc60z6BiRYIU211fDVVeTGqSEsmBYtBBQVETQm9l7dHJlfRiDj7k9G4qFNKOa3u6xS0M84UcV0iQQ0uSGEz6u3LJni1G0f(UFmFg6kP73sGc2ug0SQ3MEtKNTsXyR(y0DOvjxZwBrswtZIb3QmAj(g1zWzve6p(wUywZjZd(fViybyxzxp(gvb04S8ViLcwvj0oIl7RQAjPvfaLCIhVubQNoODcDqCuOFOJFaxyEc57gHoD4TSa1Jlkky(qynyxAbh333uY19bv10pbjLAvZvi5cTlEfCSzKc257x02uvjX0J)7I(ECeQ0NitUoMedLAhvyKqbq6SMpXvssUgaq(TsBrPyF)MMBUm)kjAo4tvTJ6J4oADq2hkww2JoR5BB6Pv8jLD3v21X(MZfP)RgUtoQYyMn0tD11Dv3c9zX9ipBRxTU)86lB4QjKFw5sIHjFzXjfv53Z6bgQoe0Ix)1VVVTO(M(BLl5UpzsqENPIEQpmBFxUYXe745fJEvYJse5Ztd449fh4e4IENMrI5XnRWDupLjke2l)yoPTgr)inw7nWzsNwq5xd6edvDCDPrKgJX2kCBmPsTKTfKbDR7RiYvUzNAt1i0akRsjnX0YAsdI(5roHhe475qItCDyZ2EeAlEo9kEh4hegfqVUQpaquIcVcxFdbP1O9Ki0tQniCXI68AU0rjxwjvDHrkCbCmGsMH9urrq7TjvJhaPKYYjOPhcb9qiqrz5dTh5(87wPIluu2)1Pz)xN9moGtQ1U1Lw1Kp5QcEM(iayrlb2f5J)7M3WwEsCq9vfKdEcsEbSCzuTwF0NPkabEzlvDMdRqDIkbpOw0vWerd2qHBWuNoGnj21KauO8vdN9fUcj1IPczi09MAxGUg(iJ(qYtKRYy1wHLchXm)tvgSALR7b8xmDMnXO1Itpm7TV47XL9DWEhjzjwlDw)JZRwC(kPv36MTOLWxVSSskjGbzVUOTHJG43JswxoQvejzK007wPkCeozhU8tKTzRBz6QGmunRqliNWgxx221FX66tAQlqcGfY2qZZuA2BkRUFvEv19p75p7VVU6)9)tjx1RCTxx0hGs18IBrhDbfdPgADYP0rFNkPErrEUQ8kulw4cub98ylCwE968QdxUufOG)56I1f)SuTyCL5MOD76723SREXTnYOqFzp)7C5YKXX8SFxt9hPP(YBBjqW877F1N5OSt77QOjFpt8V2aCsUc2YexZD7dA)R(uNoi0GM7dBlYFwO3)oOZ445VyDBN0P5NXK85c78C3dqtNnFBMfsYYx3vmQcNpjNUkvf6kDWkKkJ(XLTlKkSQhzcGukSuprugoOJ1DsODnRaUYyHE(tp4jHriOHp9fAN6)YdJFPY4iC8ud1XJ4SwYmjYdh6PQrzdKnXszHMOjA6QpmlNRn(sBW0hhH6UxL81L(bSkFj)pm)7ynjA8gTMyB8SxtKMT28synOga4C8jEPNW2FmxzFAlb9wo1fC4zKGpSM(GaI4ywCvvtZYQ1DW05jrvDt57SSLeBvKNvI6i3k(LrhHq(95xF4iY4dn6OEUIQzfU(5UruEzx1JAkNLTdrzRRVPTz9kY7eo3b1hReBQBB(1Wyz2CS5oqkA4okFXhXainiEOkcgUFAnSsqit4EP)xiapTizLi62yfQYwKnzIg7BiE8(VpFDLYEiErjljEM5oVvvhurjUcCmMhbP)Hf5Ra2y55eRGAv0q6O7oQOIS2H9GPzvr9zLKZaNvuV(C6xxswlFCfAIjSt5yvs6DqP(dTf)Ee4IbJ(5VrbGe714TPY8i)mxpuUxtLMcv(cYa)Qcfor6ZBBuNgds5WxN4K6K45atGFewvMgXzWSxqGBGtKU5snaczW9P1x3iooL)PILsXxs43y7GidU)NRZBrl2bfutC15vKEwyAt5iAJlofs5ugOiuEQYSp5Zf7VfMnGiMZDyCO5nspLrBY3ZzlRMuJEqCXiy8OBdFiJNWORqgseaNuNUujX(Fh2ViNjpQ1JReRg580ysLuLC1f0lVRTyrjx6pvLsWXf3kHCEedxT0R02IyIa2jwr8kw3Vc9PgY0A2Am8bNjcJ4udXSvXPKHbv5caroHIfTSFf6Dn4t3IDCvN3NQmIre(IjvJbZkROrd7IMl97YLGuy0NYBxWKkoGCNU8PAyEfo1FIaRd83YQevAXtkV(6YfedmxfY2uuSLHSI5CwHC47Ql7FzlkQnIacWTtsQ7Lcp8GQlUs9PAroXzn1v3lDdivxIbSYsdtsvViNuEaXDgIl28MIyRP4CyMru9jgkt2yP85Iwvx4Wu4aM6baS0Nw4gl)HNaSKkDbwub8hwCQaIO6DGQL8GXa6Y22OAcTkODPw1pvtgfbkdPluOZJP9xBvLQiU(5TkRBBaMehKrD4C91xBxP6SEjY9mUSHR6OksHYL1CX0LwZKizyyRryK6EiISO92v1RrRFlAeChOl7c(hw2xuqUe3vGKmas4ti)sredfkbeou7LPqrkOsT(VWSRG6bETm0bepSQ8MHccijONFjv8RSAyO29hiuzjXSo2ps9(Zq0mmjQpIKkW9BaD5GvL5nMApnJbvXMqAwaCAQ8GAgyiODwuUsxBbTqrUVCWLDvvVlAtqfsyZVW32njIlQAMVW0iiljNPPVtvlWnDShLqslSTH03gbPYlla1uvC8bEoPpMy2QcWs1TPyvnQenI3FsqKurkZQtukbplGKoDZTek929vzu5hEAJWufWElzgg(nrSTwQbhxjVmpC14vBeJigDaghkfWQJEAkjJcJrY)vf)Irm)g6aZNoATOBHRNu2TIejsIWyUjg7zaNs9vziCkmvRPIVl1aZjCsBYSBjYsYAkPLJouKJ3q6HsUfUVxeg7iRQSRUZsAZ)yQinJ2(kb1XkwMXC)qYNLCDdjkPPIvzDnuTOIMVuaKfjztfvrM1zgg1Yyk2uwhQMuL1(F)sBjpfm9zvJUyfpOHSwSTvxwAvcCNtA2gy1bDtgjrBlrc13sCrpjKgtAXzjr2kGWNpwicJJvPylxE3vAPTLUkPBIHNFB19hfTaBEgxu6fcwKMjQ50aImId)rjmBodQ)(bDVZCaYoQDeQuRcDeJ77er(w9el56oXDOZioEXgzJBrtNAfc0IYWaXUmBTPg0XafLAhz1pE1vBAjvcMi3t94IsDJ0Wb(mAvAlHFq6UAXiogA1fdFiDaX5Ajysma56002IjYxHTyKbGllKasOPJEp7ycCvsS(BKiwUSGnOKyq2RPDcmJ1wx1FftsJZWrbpL2Rdki3JZgBY7TbfVteZRLenQJ7nNvnZRcbUlAKROwgZK8IEOhspgIirs3uuYfXLKSlABXdOPYBzVrFJY7ktzngDUT5BGHJ71HcHZM2YOmHtm1(qEKqwci99jBRCFWM64RAvTZAQZS6)rGeyruBQGZcEOTvyV2VmOEm2sSSv8tu84t0Z4iSCwgDKoGmg1)uj7v6Vc9Jqf(EE9ieLXuRa2H(65S2ym(YiICKgpnvZMA8(A0J9RNMhv8v09CRrsd3Hwa12Xq7yKR(1kUpAl8Dm7oBu(8s8vn9sopR192pCbyBRz)u7VYG7PFNpRplZNzBtsnY6mAm30FtGKgSUzIvFANDv(tQAu)po)arQ0H2Fn0gRscKT5m3MUTz8e4X6Y2oCit65ZKmAHrZZbnXc)eVy3iNavJO32Vm1jzBelAzmkI55vhDZKM)a9zw9WsDdhFNAuflgvglZXCcGmLnZBsbnUZLYsdykGroHnBh4esHTKQm(f4TJrL2GpXtDdJt7F6rTKunSgg3ONNgTLHI2o7jTLPP69W8oqy1eGnc)mo6QFvlmZ8(jHGrQ79sJu3AVVTAjGZgHXXMIjl3jExTJ6uyYqOjSdVcJtyCOSRyReNtDnd75CnH81wchnFHxQrUNEV8bkLddGdwEHXNJnDucsH209Kb5hgVMEeo8U1uOf0F2se0PVdlDzw7C3IFz7ictZDClpwxKGcKzoOd7l8cBCFSgEpMY3bX5qf6WAjGbJJ3NIqFBEhzg2P8OB6CKn17JnkIB1lSD4eLyK4uR)hAQJd(8iNEGKSuslncrrnEl02ZvUeLqFQc5jQ1iA)v2iYaB1xg47JrfNfB)MrMBWdGFTJigTguCLt1sJ6NK2I7n(U59AZCobps)V2EGm4tMEOhlp)5voVFyZXJ8ho3ViJPypw3Wz95cS(8oRbrRstIF89JDRXTMZ8Szjkv5a4dZJ(hPVC))BVR0MACJT2)IGYA3Y5tKGNmudltbmj38jkbiaNXi7xB5q4nv(VFpB9Mu3EHzczYnKkvbJXwwQ7tFwFophEkuXXY5Z8fE7AzKVF4C9Nq9VorTXOxsPn0zqGBow21SUMkP9Ku3Eb1Hv3P9H1KDAY2Qo6ob5Gwrr2j70(CeqPoTtOD5GGtf47(rn3o5MQwS5GLg8i8z)Tn4VaA32PG)4WYf)pT81Qte76C(zfbyCs3wLQB(pf3yzaMStz18Rx0GC(g1djCLh7dTCEZBobfW(AfoOu0IGHd2V38jwHXZlJjfSFh)g)nCaJcdZVLfOuCMdRwkhajnT8bpB7CwWzuf)ffCjRJ2PsH26o21IcA)z9uvqCO66COwh1N7jOqvgSBGO9pi5wGWb7xoSihNsGdOFHDPStCPK4zN4sjvnuyb67qAzIJV4Q2zZPTLWj81j8uSpVMthiiSV0nmLnhBkxta5aeM80JAOijxBSPRTimbcCTBKI90cRtxQkDR6zeWU6IBGmWfiLTHJw2x4PBtm04jttmK)NM946yY(wQssTvKTbsmjTqAny8LAIOLX(LM9Kg7wLUWavYsQkx4Ga9f8gEl3jsANOOizBFbqdHQzhanFpUUqODtZnpwFxtq7EcP2ni8GvFSx05DIfQxmH0ko7dMDfWwxmZEQJgpw99uXrFrBsigQxbK3q9ezbo76jc31yz71QyuZ9WDQo5RhHn(qm7UgPg4vmPOZx1bnXY7cNbw)x3kLYv0WtW3bYiGFSQ4neVWzL9li45aPrznXuVMAvswFwxe0EXVGvIO6KbX1cPeCLoCa09RBsOaK)s9ndImSJjFwLkn5TD7Swm5zkSWsYjC01iYEahIuDcvCkpdTFr8mqszor8rQpm3msuPunHYp65gKrvXKOGSfBKTtgy1hu8KRHcd8avuU1n4lQZLEV48Y9lllhMwKgfZTWc89G3zWJwzYWY80HCZOpVdb96)Rb0LrfcuVafvSFj2Ry5dtk1JM69OVGSbdkJYYIPE8AB)cq0iIRqUBer5mhs9I2heQLvxdBKuFZS3xzgLbwxIlC463D422o7m41pwwxGv9KmIfH0R7zgO7UdlliYnRwUK07Px8jh23bOdtRegquc3OrAzV8uUVOvSq72FVb()uJ4DNyl5ykKnsyonTlFaVDcbCJJj(F2T2nZwUu1q45uga6DIAlH5P28h48qNw6Alb0zpJY8LSd2VcauSaOS0fVsXjssQ4aJ7K0IUyAuv7gK)3SVpe0t5T6Dkqs1fe1(r9h)Ud4JcARLhXuDN7IE8xYx1m6HzYE4Miqqgmye7cOYWvk2ffWAaQ5dpcRP8RwqrATWflaMadd5KaEqVt(P5lzkmqJEPjNUJqfMzp)MD(FQZF9YDwaN0E7SOdWGF7SiAduOy6xXZIk0TPP2De2FzepSXKFDEg7lcMBZi415clnR9JSf8)zF2Dnw48acVD8iRdqIfdZ9B(OVbSBUtWE)RHf1aQedulOaw3(l0qBiiPheZNbbP7xxBN2Xs5lZjEQNl27gRRhNErf2v7jShy1I89dfWNepg7PZxiyB9xT3aeOanQNqwxPBT56IAH12FsRd8b(A8JTe1Ui9ByV8iqwlTCFtLaKsu1b2URn3mbHS73qL6T09jxHsiziCTl171ozV9WWB4Q8YflUdIK0WbLYH42vLxu1Jo26XpoV95(S7bAhDDaO5LIm4x1IdlvlWP4W06R3gI5Lap4HwRK6enJSmK3ErAx6ALqfhMikAh1dmyCvbdV7qjgjbg3lOPVZ4QICD1IDURs(ROQXiF8qndVkXqc(D7OZMpt86GjzqpR5UXc(tkwYHAdfzgdH(JQ(D0Fu835MdMO)l915Yzu3bJitBD1MgokP)iuAFPg4dSw6UBQfllf4ga7MWrGDT9z)sHnnNkLDf20WJZxwnTxxzAJ7i30P0VBUy39SuZsEDlZBVAIl1uRpwTT3sbzBJ(cVi4EnviC7REUba0wG41QSiVOkQZSgrhCaVZfgZPwRs9D8qO5HGp(w2HrBeaAbl0ZxqPV8bCVEDxSq3d7cYwd5IpSl2rTGfl6tPY(6odKwvS8bGgqFZqKpeeFcHaBKCuXLyd8a1EP29DGAVFSa0l7ZEXgGpin3d34brHq)6ChONq7GkGqziElWgWgrgWofEB4us7bYaieC2UkbOQrDVUzgSDzmc1xKsZteQXSNrQIm5j9KR2EhduipD8rWsfhg5(EGxV3oE2YiQJJubOYHoQO91BZe8nSWIa398HWIGtKdoD3LhUQW2DdvzHq30DCP3fXtF1Gxa34ZEGxqOb)SwxTMXJzqQWTwPItjyU8qbgDpn8LAzyRGOAq44VgOdqbS6VtCyhon3WONW9B2Oa446fZkfmSb93aKcJ8y5QPhyBQY(Ph8fGoK2hKNRfib49cTLXOrdnx4pvn(bBCpYSWBkw6botojU9rnCVwBQpDkSEQBXLHegsoJTo)sdO7XBMqI4l3afDJeGQdG3GvZ4qv1oCBlBVeOpdyJnsdtf4nDjRtbadbiNEDwzMEn0XGpJSBOb99qSq(1K2PskPyxyTl03sG00GctVuMoWTvSvO2FNcgDtQc8r9oHAel)bj4ttfrmHcwf(NDLoCpZMMrmlo))uhYUJoj5Ia6xcoc4sW)1PEiEClPVJObDL8fJIaoI8UvUuimMU9B(Ml(VM1Sc1(2bGKCGoJnyXkwleE9I0HGL3iyTT7BKDBOtKaigirtKOkoFJrKeyLxvre4xfohHErgsBCVZAbFo2psBuVbVf6aon5697XG1dVcNkidZTyg2yw03aBB)GvlQqgpXMep7qCGzJAMXC0HHb66FeyTtlcKDPjZv0Cr0DEO0FYTXrNGtoeItKDyou8(fzoOZRFCsdodofUHEwZYvpImsPZddsS)JQjE4kEu1Q7rcV8kC0lq0LylYUhFgt4wHqYS4IpeJoppiFcj8toy8jnF(5RUEAfr0HXJEcFd8Y58hMCdDbAw941izYsRT1vlAFyko5WXxa2Jb)Bro4eZoA1TtX(JE4ONGhG7wTa)hiv)pt(UQEC(0j39m)rhoAXK26RQU9xfXIPGgO2zn3VINxa0FDzvdEpaAdFQUA(SMRQBU5HQg8HPC0nlMmhUGWvJXBg(O894tcYCK8WqjMBSEC2vnPA6YtXoHGPCxQnzbbSf13vVyr9T)mD9hZxEzefE1QLibP4qfWG0P6J8o4bZ9DILec2ceooHyvS8rp(ClSss3HMpkUQz)zj0T2Diz1hmJ7asb3ZgVL4e2ItmBB1uqsrjJPgHH7rr4vGd7l8WdkCXz76tOKOkEfS7I5gTEin)5V8551u(blg97m55j)Rz4iqa7ss6V9S83WjVVElX5cF4QM7RXbFpFTDrkp)VXjUakVo(3HfXLlFQIpQth)udCbX)AQ6ix0UOQTcw(pz8Hh9PtOXFMZiZh1)LuqTepHRIc53La6T30Dua0zOdTNqaNmPtFaXrZCYc7nWNYhTqD020qw8K9Ad0pgtD8UBDet)chtG9eIVXyUA)gC7vcaa3)SL4jndcfqtQpQMqQBx(z8GA(ORHpWk8Ov2OhEKh2PPJECw7t8FDXSgAuEGNOxWkOzx0oR9bqB1jtwUeolIm8BgOqI19UH7is9I5ocUviENfjsPFB2v4fbp8dkvRx2o7PREQ(5fWXxKxyPzFWS7KFoL1LT8HQBN9eC3rKxlyyzYJ1GAZLO2awlY1iNtU4ZxX6aKl(0jlBRjAGMw(W3A5OLpdk9WP)bFPVT(o1hIPZ(eN5IWk4g8sKQxvZ9I)VoVIh0bKZwcPPuAHm7CWjW87PwEtyyrKeop4MBQNtSzmorMrNrSElLepDE5QfGMTlWP20fFEcoqrCOUA(S8LZMJZ8f8bkbwBANwBgJjCJbrVOGMs4ZuFJ5niWyD21)A9nTt(nRpQeFO52G5zwVJ9emolYUgbC549zgHbPgMDCQchfLKSVIrzsOruIES9XG12)4f9EEg6GWOcFt(6FBzFHgvE0OtrpWtl42yIQx58P1T8ibkHO0g5tPNWq(4hdpCDHEsBMZ9jlTdqJQzwKWd7yB91tJTx6Eupvr5hER3d7fRCLXhQs17h)AgqVFWqOrq7JlQXrlXjRM2o5sz0nyX1VOranx)IfCczfLlQNE37W5oXLvnFE5bxpdeqGBdjjeSlwCvDbFhxnH2EqIh(4vlBzxVyPs6I9ECG8Gxq1jVoCiDaIgyFqMOiolTCquz(akfySI9S8H5XfPzdkhoGXrhHDo(fskJJYYljKWMIhZ5B2ntug4eCC2Q5NcohPgEZCwsNxzpVZaTxgIAfmKQMY0GLCnDs2Ro784B(8z4j0f4skRPIVqYfrxGuqr3c4DI16J7vg5OQ567S(H823DwSNehCd90tFPG2NN)HhQvKZo6rq9uCMSH0skO7FY0PSgAIlHRM3i4fb)Whcot1Se0oiZpEpCrN6PyBxMlgHZoh47gflNu)KzSKxMPA6J0iUSZ6KubgH)8snjsiJ6B1IKZGQXlBiOYSaPGaZvctAEUCqjZA3KeM8RefuscsQWWWBbNfFCKig6Kck6thSeG4WdwPikn7oxeEKxp(3HTTgWPwYxA4(JgyvWo05ND8y9DoSQDRQbmkO7yqBgUIYR)MjkgoN2mYZoRrGtTI8vNdIGKoX(WRAAb7Uir)dxDq6c5L1dNSanuabVyn6wH4TGhMTTqD8AF7d06U8WHZaxY2o3(MmF0Yw7XxbjmCK2Mykqxk0oCWWdswmNkVGfxOpI1AJvtZ3LL(iZafIQpRVw2jdyfO3zu309qTXfQPWzDgCG5XzZAFaEIKbwgF4tuFINTL8QYVoTU89tRRP50boUIusIDekHnEuQKh3JvT9VECe4DFDCUci6viv3sPAOyz6NNio4H6POEiNhlpjRqypfuxGAPYr0IvfDm37)W1JDO2CqqHXm8vCyzmEt16brmIsbbQo5XSRpVwReHOTFChboeYCZPsuIv9com2UIuP4CJkT0FxIAkfTavmmnHSiP1t45LPsD4(U1wIWdxwwmuDa99hcNbqxABycDjwQ553x)ae2nVuTTvbTW6mshRe8LWsbbSKPxe2mDjtdoAqCaFioyk6GoTBB4Joj4Hlw94JW5Z6MBLumiMH0ghftFgj(poBYYz0uRIe5ZnG6lBihohbfPmMzSWJJOmHHxgWvhK7)ecwaffWfATWlD2Baem(KwHGPZgD(r)47zfegHClMOxDP6FgWm4acWNV2dWz2EgbQQ(Z1z(PQZRZnKQWoSwTma3MO3RhSzCN(isq4wc4xXHF8IE(OzTDxi5LBBnuJ6i7DYZI4nfpzWVs28iBuTd546crjHocOKBl31qOpt5zPh80qEloBXK))znqWXCKAxBoFWURBSmiSJMuhCyZv5(gTLhZga1ztG1X31lkw1d8Cvzn3uehxVONr4(oci17sjirhKazV6QL0mHIg6CkPGeA4QYYZq4aSNf4ne(vJUKTajv5)4d48IIs0jpRA1vW3NiSoygAuiAMO15seO0AGMy1p8SF(ukHHerEgb2T(Zp0aA025VTC0jmZ3gLSuqYDJFB4ZCc71G2laH3wjf22wUC4oClNzSXcmgoaTMgcDq4wPy)WoxkklH6d92C0c6LOXNknHwhhjoWq9tkD(FZ6nbhOmQ6oP6(j3O10vyAcOKsJMUeyNKxMuEars2C(cyv2Ks439b22aLEmXhZH0IHhx)0STn7cMUJyLCAAbjkw5tVJX3upDQZrPSrT84W8iCgnDDL1GZuMtM453nKCFTl(IDrBhn8)30C4RL)EpnzUKJzW)gEyLc(nF5bGOE(O3p(GJhFoiRE4bNCWpo(CoWcm84ZRxcN70nXGKHM5vgtlU0kRyHtcJJvCHpJ2XuWbfBXg3GmTCNsEL64jfOCKdcsCggCMdIfJZovhpjrtTQ0IIBXsC6FQbrPKjgQ9uClwru5GbO9NDidZuVOJ9pbLbGUEybb4RfDm1ZNFvmQKju0bSIx8Uf)8Ygdi3szpAAnjjV8pUK(V3rd4srTpfPKmtie3P7M(89sYzocOiTmAinWI3LNU9hYnsFwuzwjOjMDH2605pSAHrP9(56tNAD25jeTvalrgpN8f5Tk8cNDmFYb6zkqx3rfRk9DOw1TpQqnm8XK2xolhObRs2PyyZARS3KfHYgvdPBpBmOe)JzEGy5fD45B(lOdkZSP9lL)WCYLOmFyhw2Zn3CHebkQbfR0LWmG4bxLNAYuVtDJbhg5GjNVyYVv1wt1qKFLfvn3RMOV4RWj4xk1dN9kzXJRHIoVXMmIGJgbDeRkWRJXVA7gxFnck(wJhqSltgvHPGbhdT6ON28czWImJQnTZXthn5kXq3y6thD843X6YMx5(NmollEYZzXYN3MBmjBdhD9J8KKh2cz8hQ1r0lcux3FavQ26)azpo3BM0MXjf3eGfC7scr95DjlkRKYLeetbFX6mZJLxDZBgDUakq2R5ZghNl4ICT8J1loF2t0eDY4hLI352YCwMGoCzLAgEBKvSz5bZg3xeFQXiQpUAjzjVhpSfHEOGJTEjgsioxETZKvgl2sdcI9rJLvUY3F88JgFXLx9(Zo(x(dEUYbQ902e)pn7rN3X6(E7wgKcSW9udoSvjnaoEl7FPH8XunNP7f9FI5R2O)beJ6N(rBzl7kZKoQ955ys7WTyslfjJRsiLriws8JiXstFrvMKbvzYGWw7L2AX)ohpKQMUSMl7f2FHNkpu4(sAu3OeD8Oj32GB45WXoWZVL)rtrr6WYVRjnkpjd(rrXWHFhsBU5dGFKqMtntvt4xV8my)MJYML4Dve1rM33UIgkH2RhY5DAqTgp6JhC8bhE0P)njtzun(Mq1gR5nwGAeUbC1Rusvzjz5jGauwEzeiifJJrvq8kkofK2OP)KLqvbkujgQ(RqM6nLsKLJVPvkr80Or(btj7Wisakjog0lLeNnGYu4RTYOSrNC2PF4Qto6Il)5Xh8tJpNSX1x5Sx7Bb60(xI9niKglZhwvq0R1TW6DftCu6U)AAItY)RxtCiwDGfnDIoXK6W(s33aYUyLlW11igffvMdAMaTt5dtbRCG(NCP3xrLw0yfoKaLx3y6yEZRtebDfHmUvO8x6WJU4ho6JhF0PJ)2rIsAifTNAg3L2Oaf5p(xtbkod0(9z6VpbQyWYgyaRjQmnzyk8ZIVRjjjEqU2fk23jmDuKig7ETvidwoq9xKiw5OX)0zFy85xDWN(XtgF6LhC5rND6RVR5V5g1U7BobrblZGGWe6DEs(GHXOKwEzAwxFYFZ9jvoL(3BmDuu82YnjLO2P0ObXOF4WpZhcQOskZI4cU(A7gLwN0hpF8fJp)NEtN0ntAUxbuKVTDnhb4Kr2kjpnjfKPsksIz4Q)wOCECy6FX6IqVQTLxYJYGy)tYlarh4NzzLPGp5jf5uUMsYt(Bk0UHJU49hCYbNEfOs6YZo)nvs)JrLeJKBvYMklOkR)MAO3udXjwGZijdaiLqsEuCjOfkEqr6GbGhrW)vsHP9A7juXOdp)thD4BkDW0fOk(3)eQBIBgUta7xVLiBQQuVP2XsTJBEShwMaHDvagOAaNGkkGy4thMMaU9KcXIL86RaIt7Qp88f1hKXsL6uWM0QmYLcywF3IzpstjRX3Ep1krUWr1cNQrJESEX9csHyqVPGyKBdByqpxzwm4PyurEAXGmdelbJ9mADS62P3TysDZTCNxFN(3J2EccsMS3Qbeg3)1TtMw)JsVYk4SMYKDj3pReMWYhPMf92j)SK(SQMyJB2lPBHQVFYSgeT8m(w4Rl)TeQD8WwhNAOqMQZGpNUj6KRmXLu0F90QhP26XTf6H)L0sD49Vt7E6bGgM2FN)MOoqJ5ZCUY3CD81RrWFh)Bmsno7U7MkTVO3Pg(admrX2CJOOY4eRgBJ3lpQ53M0wlG8wdSu8ojJ7jqFe5SNMjew7wTSg7nZM2lRUww7WVzAGSWBYyN(tpC6ViQDp55EscEbChP1PJURIWf33x10uVy57OMnf(QyaxYBtyJ)IKRqtlkxMJ9181vt90C0Zw1IRycMn5UJf(SLyl4X34WNFO(Uao8Oi7onMthwKstpPKKbf58rfj5ceQKthMfLhvgNmipFqjC(5p)Z)l",
                s53 = "!EUI_S3xwZTnsY6(xXVCUlpyDXoiq)Kw8wmww(iREBIjchqKqs4yiaEaaTT6oM)738lZQqvyHKs2U3oTCmtljsGAj3ZSYkZF9F0gKEBExg9llsZ3u8ULzL5vohe6R)339pAJtBx2KNx9Yk3GahRp4hR8cJC(U)ngLU7wNt)4QnLL4n(yEtBrDvLp94bPRY4PW1lDtvz9Yp86S7Q30rFsCAw1YBQBA5vYrzn(0VeL2L1CDEh9TNMvurFkEW6RUQnV7NR84rSTyvERF6fN9wZ39tv8Ajj94to99xUHEE7bZno9zNF07pUmRT98826nnlZThxFVdssswehN4LeTyXoMLNgDGRJFOByKxy(tDcXK66kJEwBhTEFiZR7bo9)JgW9T7yOK3EHsUjMbki91p75xydNEQRaOExhb(ZhTGNfQ)uFEzUyH7IqNy7rpm98x9Ixoy498sWt7655e74ZZfVSd3)YEbqcXjbbl89cIn7HzMLXaoAwIsFB(y4)SBhxFgzN4f76g5VByLNxKfLrY39Vb62j9tfR6U50SUL3q7Qeg7)26prK9U(mb4Y66Yv1FQQDmXXCpWm0MtEmHk7M8IRVPtMx8j(PRVjRQR(2JQ3uTQ9xXQlknB1Q6kq(7r0LLL5T3M3K)9V6WLDetjHjWxrmeR30Et(QJ30sV)X1L1GW1LyjDjaVB6LKGGiNa(3VM(9fmGYnTH(9KyFMSpmT9M6pDuzXV8lVAjn0x)C6dtud833MZSB8qtFbTyUH4Bbtsr11hwvCBgwpTeXJBuQgG9SvxN)UIFjVY7aSo8COx66BkX2(I8p3TPj)cswdlhG(osmqg9zzD5NvDScKJPkCW4nELqtNS3pQUzvEdpD8gnk9sZE5WsaBzGHx6LznVTUTGxW2sRCtVJK7a5Nn5LVTUOQJG)h)S3CXZo)F0gMUE0N4M(zrmfZreXa87QcCaO9bmepnzrKsUZ)5M8n5eNC3ggRIrlbIVEaJMRtqq)AccxWO80OyS135W0ZwIT1t98wOwt)q(nfllZF2NlGuEE0cwazBpGf1Ifg40c1O47bzcpGbHGtXdK)CF3zAHMyJP2xmglOh64e9axkl84nuy6p9wrKlwlKaYh2WWJbrp(SQLehFxEJzScO96dc6yenhRbWrpWLJga3lMvdFID2l1JHpbqzEXaT0FURjtjPAtxxDLEe9x8qxB(jZOOJPaIDcevuoEHE(7fSztneegpw7MLEhf91EzahY5eeWCZrPNNV(RJ2aWWeJeZXY3i1fn1lFrz9Net9yjSU9F4e5KjPBAZzX7znRoHmJdkpGm(4bYx)YuE4M2(FVjRjhAoukbUTMMVAY6X3rQvoSSeQg86xESGFwECK966DD3vMJffnG5L5l7i560YuJvSu1nwbYI0cAU)N113wfEaKpb9PkaKzpbfH(XGDxuegR(9gHM1wd1xHU0aOIzOQfpcit84NPm99PG(NwHxYSfVLuYtQrzfHUbPFSO9LKY13u)SQ8BVtGgID0)iSuH1rLKE51pRk7YY8v0deNwT52ZR)uBVkowz4rKS7k890aCj)jZID1qdTjbm3Bq6hYV7s61LL8prkrW3hMUQOft7fKg6UI1GckonxwjafViL8h4SRopR66CE2Ongwbr6X751vD2ieXcLRvwQOqe0WCdr)qVlGeMnQfXkia2)4qULu(PS7Abr4rmWMjp7bYNYsEzyuObWFbdTXh6NEB2YMASOztlCzCuezHa8lIP3pdaw5zVUP(tNu0q0TW2cYqOCiwhcYj8dZBOgGKEEoSn(zbgZiwylx21WOQgAWAphglHbN8UtVq2)UEeYtC1ITWlBDULGeiTK2mWWV3AnPc0qOyUGu))HQ82w4ziroPeyC7LzDaMAHAiAmga)omj0txvxrULrlCMY)(H2j2KsA(U4MM6nxFdwhEkeirhSkVs(eHz4LS9ZcqlCmvhRPbC7AYl9VbtEfBB849nrO(bGzeRD1wUcSYpzJvcTjFTOee7G)hcRIqe0VDhqWO4)SnIMjMbGCinEmXABZNs(WRnIFwovhfMsMongThrF)z5jXrckxSnNmVPTUSyfZuBr5Oq5IP(qaFdewnK(MWhMVWiyYnLKhq8eIZcKRx3q)9Vq8wzLmcXsgjjWHnJ3tO71cozSTXdJr8L(m24u8cytiYD6vezrRsB1SMFOOT4YIYIU7GFwSycrujtglYA9jLjM)XIahSIqKk4zHeAFwv5DVQQL9eN1S2lL5LISmH6vgEf170XN8NHzfzFcjU(E1ORZZxbcALYnbxzHmSEwT7odCozUvZFP0aP40)lVcObKg)nrbKc39xEfqIvSpQacQxjvPSI0)mQaARQi2TkO51wmNoOTOHBgnqJ11eMwbJhNQWJ5rgQ(ji8GaFpNKfXrH0V8Wu)mYNdE4hP(z64)nw9dTFgfvRPg0nfOdUmTXrJSYCEBMifLVVn7JS3IwX6BIkrggSnFl2U97Bxp8udwhJUtmQW1QJ5yG9O6yLrZ)r7p4JQJ7dC(F58h8r1XCCSge5MhvhBC48r1XKLgwEdADIf3h9W6Wdpt0EMxpCOCyQvbomn5oCZEgVvflISI)JepX5de4e74E5zN)Q)5zV5IdF9o8BosDQRvUXheB(hIX)wdF38hsZxj4BxX3CAiHEi2FmFyaSpxJhT84BHLhtDaGnp)pYaohKwMFv3Fcc38)tXB)hd38FQmVyOVXEjhe5LO(F85P9BUt)MJk9(D6tZy(XCoLVd1KZfHDLJ8dcwU6ZSIv(oJm9OWambu(noka9P62Wy8)Zv)v8CqzJfE8CqV)Nd6FAul94PG(4PGANtKZECQ)MEkOmf4d7uq5m18XtbvNmrFfNcksA5)NGcOhteNhyI4eM2Guf5pbog9OgOh1a9xonq8Pc8OgOVonqrPhLDTkHGVpXo8)HFeOCY3)yGi)TjqKSbc)rgiY)eL5RpgkYh14(BGg3rzj6FNc)OklK(gg(rFa((TiKJ8DH6rTmFl0Y8qd99mQFEmrBEmrBE8Ixi38SbzSZ3Wqo(B(rG9yEVEVU2fB72VEFC9BhzDZV3PnYI0tlw2u)OFRtkYgpAwH6(HE)UyFBJWDlIt(J051)8eT4h9D9rFx)nW31TAJWd1g)7)TLz3h559mnzgD)qN56YmnLG2rQ18qUhN93ctZLl5l2F1DN7nKIMbfGJXfoa9T)8Vqfoa(eSFmHzU)jmZFIcFkhyRhlCaQAL1JfoGF)tzgUIg8Wszgod9E8al)ApWstfm6R0R1)gDxrqreYZu0MMufMc7lkr6QrHu79SkTFhLDnx(3ctVm7AC7xFxDthkrjY1HH(quVqoC1QJZ6YVUU5oPG2qF(P1Fm)n1V7MIR6OpZZr)SNvLtd6pM1uvuDD)O8M82UJU7zFEDwfkWNs0zPr5hkA3KvYv1MF9nV5xR8cD8cx8DvUj(XoXFh93U0)(Uk6J9WFgfeYFCqYch6XOF6heHppoikb)DyCi94Erl8JcXF76HI51VIIBNd(amE8pDCcDKFgGxe)TV6NEYaZdyKJVl(7qxNe(7PFstiV(OfanS8xtpopS0p9PHLwUr0tJNYJ(t3qxFhE2we6XJY4FAn683hrlxRF6Neffq)n9tEvIFI)om03hB)WqVy(9cPDUaoOTn)CXaCr)CH6VxGLl(B14SGx2ojmyt(5)(xjagnq0OXJ5IagtK4GN11NGbyUdweSaqcxp)f8F7h7VJFINZJNdmcQFIXLEXiaJ8cIcWEM(EhcY7MSaLYt6NU(j0Zhffs)1d9)YJMA24Fgrygmld)j2XYUomkIjS89welqg3iMGlkGPtc8Ieif93mbORhdzPppG39XOmNY)u2LGKv9taXdIxa6z(Z5Dl9tGbjiVGXIIJycw3fomU2DXcxGhC9JJca(W1nkbWRicSrZyucwhUXboaJY)epnHnIJymPu1eU4M8NCyZTeh8F54f(YKi8TIfslz5EZkPKanKLAIejwa4HR(yEfk)rp5Tn5R)7gphimJGsGJ11SltrSYZfFXjs5FtR8Pih6QItvv4iOCHR4dTDp5vD532EHzevARq9nnh63CtpUUQDZTy4WGKGYN2M1Vj728PicwFy)3l1Mpm2HPmh04x3M5ABVQBC6lYZAEYZQUbvSPBj0(x8YW1pfB3N8U8UNGb9lA9Si9hZZwtWKN8)7jx0uu9H8PlO9VXKYy4LzvF4DKzcxMHA(xz26wUi3rFdk6zF)6RBYwL)QQvflZ6QBKKnJWUNNJsw3RQelgWl4NwqBSY8pMxcJzmfyyvXoBtttE1Y7eZfKswjmBz0u3B0bSN5Tfvv5RyYdzjPSZH(Cz(VOynxL(yJDWBOwwmbfpfytGbGxxVQcMmj1Jmq6Qi0KLeCeqMqHGe)TmC6)EoWUMUc3k4bi2rKTaSnHicpZfa((KxuxVIMr3032uFvElmZI)ZZZZUgRaSUPz40I2L5esQkVEd)9wmqgEREoPtYVkBtzNGJGHEOKglfkXBx3DNA)tCMcmukoJVOUCfTOw(bXeqb02x4qPTrpAEunvZJgaMbz1aOmMUZZQwvFBXVK3t)OqTk6hbLSkVlB5nQTSqvHsgeKXuU52(sIiVjA1fMzvLInXZ)GGWOyY2G4apoZtq9LDru0br0)we746I0tvxDMJrDKxQr6eCTjVmRR4J5sTCMM0Jo7Ilo7u89Iv3c1YffDLsDQMmIstfbYogEHce4ZfZ6Tms)076UPy5ff3sKy8RW1qXYnTx8PA(tXUCrA9L)xOyq(X8X3xqNdKkWnkcPw1IBUEkrd26YIU3vIIq(WAxkz3I(Tu)QQGzcUUgvnLJFMaEfDME(vSh8a)8S2UjdSACLYLiksICzKMOlY5IqADZY823USJWpeW(1hE0ZW1S3x(2JyHmQAook6ISd48EluwWya9LYRVu2f5sBk9Ecj6GLkaFy5oOSI6ka4M8pwK)j5as7aywbYNRKyQxg8CRaSRYZ6UbtWRQySU1irocv0q61gSrekoSrKFJly6Q6JAhgasM4Hlzzw8wlRS46kuSBZ)ChbNu1tFsZPfuKRmH1n3MrKK(PhF23)MlE)BF25OqJ3dmysOJAYZ(ak88Y1qUNw6fzRLsCUt6vnK2sPsfcBOzucVhBT2GocOcIjTG3mK7MM8Cn5Ac9y9mcGMmmTveqCaZJr4jZ486CYhtAJimAOMhUkRSUIy1e7bKkF6prUI4hCGBsCOtsCuismv939ZeBCYbK)jKZmUoHKFf8zSMD1vfF2QYzkkSeySOTaL4rPY4YeLVo7YCU4clKihI3xx(fTPDjc3K0V)nN8SZF)rhEoZ(Bw2sy9DoG8VG5De6KrvywImIdhktpO(vMGGPU8eoUVF9ssKy11VdCAsDKfA5aWD5hSknveqtZgOGJ0wRhfFC9TRZAYpTEfQKQV5S38mUq4JxbFvzEx(QtlkllAZxwxTcSl0xp(1pjVSldvLsX3((VU1c(6N2reb0axUY6tXYvZDbAKrsH2IWcbxDct)j6PVKmeSxgedsuH2Gq6PeHtYtDDEQBqm5aejEOkoc(j5cFxDbfb5HfbNfz18B4OEJip6nciNRIdip0CjN5H)vS)9iwfCb4M8Oo1Db9Cikaefg7Gg5ih5(Qd(V(lKW5gM6g5spP9IXHwhli9n07Hqm4gXU)geY8(rYAX)ESO51G920d(ps(JIfkIAIBaCr11HKMBw00iV7NtVMJTwZ(j0WfhdhpDqGhiNrzGc5kknY(0AobUzI50bHrH(gax8KU6bnIboEeKWAeDdGZSXj0)X3fHvybp6retIckerVWVwrm3yGqWGsi0f5Wl7CCqI0xdaQdycRrocrDGEdE4qqH4fJb06SFSByin5eDtmjBcKmaHLWJhIsdHQ4AtOIkGEoFeeMeeii3qGDDJtaqGdfLzr6zTidrWciZlWJrIOafdTun7CIeme(5tgJqqjebbI2dGjhcsyESa6XaMyHhIma)aEimdUo0yAwIeCevf)Qeeyf3qjmd8ZHq0WphJGOTcjsL2ZCml8zAOfiqwUHeU1ctAtBS33GHMjwB(yMeYxACdebFKdp1rUmlwmOzta1Hlczc)icteH42jVJMY1Mod84eKHGZlq0uOnmlfONWKh5GbYkaDjiYiflazZHzbWcfyNi3ayhrNIhhc4edaVVpBvJcuslwcLstBmMBpgWVWbdvOqv4JnfXlcY(qqEhXSpeNfqFcfRMXXE956aeseh6nwYuelldYNu0AaCAZqeZeMb(GwlM5HcjqHH6GO18a5ihIrEQjSaO8xqRAd4N20byw3fSHKCrJMpIiwymZ1GPJKbJbMyZTwH27jE3quUa1eHxMxTMvin1EGtogHKJEoweotx6qCEYGYsdTh0D)gkM3qA1I4eUGLJt2lGrMzYPLGw2grBg6tBHaosBOpqqlqMNeXQ2IdFGoNTjnurWteiBfXWI1iQ(bsm2L4aTkm7xyNybflfq97IaurmtW)Dt2PgoiNzp8BIOvBHb7rgllDGwa7GgH1ys8sbGFiMPZDwWk4tyDfKWrMHJir2dPUgooqFnPkVkHnEq0WTGLxdvbAuF8iu1ojwGgEO4E3kmL9KTfj7CZPf9ztaShmljbl1LO)jFFbvnR2wofIaSJj1eIZiGwKEYbcW5qqZMr4kH3wKAeIqzl2WqVbrHh5Hr1LzPJyRPs8XR6NOL9dqbK9ZIL5dZGSCNTMIKgPSTGgO9jsrShZwm(EnmJxJ2CSKzC0kmILwg5ar6XSXIe8WsLlH34fBc(pXSkxw9pTjz4fmgI4d2IAzr7TwC1aS1UebRTZXw(2o0aXepqD5(iDzWMMklaWzSHsywYaXClyimokhlqaXfnsfUyEhjLyNw1PfRnWAnwdHdmeAboqeCmimbIsFlRFgMyThlqPvW(esPzUhOThQKJzf9ePjiHzUHav76tz(EOTPWqVwSyKfokqIpHxWIpMAn22BXDBhGs0jueTVrw4yTLDUxwxgbpy5VtTDaeXwJzBp92nlJfMd289GefB0bJZwmnxZqmWNJDAuTskkStEBMsRzAgSz2MCgTyUHEsStPxeNEe5mHYS15mEreXa6YDkzrZxyB369WVhc2pqEWUDeGxlaCThLtIiH9jjqJWgyQ9ECXquJafo7v7bj(cMBUpMtM(Zwe(oKmZ6LAQ)ecWLQvBGakibdtIDLkEK0Fzh5np)HX(GJpYOU(uFKBKGtAIkio4dvOt5KHyv(kYyBj(ACeX2B)2bbtVrIcxG0z4g2SgXrATUmRJpMlcyCtw7nVUOA)dm9SD5FgrcUJBeq8lNNv2DZBZBqeX4WE1vVgpH0Pfv397RQxUr6wJMUEINhAEtRZlrtdJaFOhCPBOJQiy)C0EwwvE3BE7X8zZ4LUu6dQFFvbcOxZM1DfxwYNFh3EDMlG08NkcAr9OeRTb9sNeSI5kYYKVYxpFQqzlBhAlQGcxuVUVZc55KMTPj7e0YilQRqu0mbXNw5f3UUUPlRQdDPsUpPX1oioYPjPRYrFLLjT6BgKM8Umi9Q6QU2WW0xHT9vzlZ)xhUA1zvT)lRdb4FDB(QIS)f)O)lI2PjVT9tz3DWfxiNC2vAOjH)ry4095PNsejY2IJpO6yyKsMlQqTabd6DvF4zrAwxt9YIU74W41KvS60SMpOA2LKLZ8yXiQR1bYKptb30kAMh0DPCsVn7ZNW792koyNrPzx2w3C5XL5zvYRtMxrFXcBOUncKiUxI(ye3Kuh3M04oSMHxt65O62R2Cif0X3K2wuGMsEs)WI4jVTq61DgCiYJ6RUcjgLq5ZtvqApD655zRURNq1ejFFZrsq(Ea60e0sIViR6dhE91n1MwQdrH9FJJY(06lhZkfnL8QVtzjDBRiBW3EfHGtRsZrWBhbhet0HeJ8zFmVPm7onYv1yKUPO7Y6pZup)eC(tc)pOdyYAlMbhleMCgHZ2IyN70oeienS9yCCeqrPxw31vFlVe3fJerfbM031LT8d3VAMzOSLbtRsiGARrtepNZi0WWsGfhr4QKVWRC(qaEv1XCR2Y0xW4wfPelFx1VB6nyC2QRKuY9KqbNgpCZiqygU3t7oqshrdyjPZIm1E83pTbA4mvF4LzTm9z)wG83vVdwyoEkXSyIhvlZ8y(OygWtrc6a6SyzprV0Y3OvRwITfrin9kXV4uFAteikuQrVKOHa)H1jOgyHQSuljeNmhR5KNjTbQrxwO7hCe2pLd6kyOxwrSX3R2cOJf(v26lLdZDgDbKuaTG83cL4dGKYwcB)9VUJTyIgtMybGT4B1Ai4Eb4GgWmXxjOWRqgCqQ)axHPP7PB868lAbSdt)aAVE0)FqxCdSOaWnZUNmcA5YrczvgHHDTrRRkpTh3NjH(aNidVM(3bVg(DiDXgWC0GEFNP9vJuOttTR)DEmOphJrupsAYPrh4yopAlJ)C5Gxqy3bMyna7kjAI2Oic7FxEdFYweRcXr(6A0v3gYuYnuDvZf1WukH6N7TJw6YmQ(mmbGfZM4GSTKOQzSBSM)KxaOV5FiH30pSsaL9eaBmBRWwwjuDVIoKLPCsMhwwQmuawZmqNFFxmKbg06Y2ivH(LnCBAROWR3KqradqWK0ioJe6xDjrM0CG8ktSGW5a9rvrallXHdBoOq5hBuLUTLQUla2k47NhKNW9iRiZe5QozqVbOlD37tKXmiV4Sb6gZaWaIM5O5uFJtRY301KvAudTlYf)EU19lCHKG1RH2IHNm5FD7BYZAU)uPehbBdbdgncDKt63mjWjnv5mulcudZvAe5tRUFrjjeJT(WxqYM6UHOnvvNru)U1gVyput0Lnq4PXmvr)HLsz58OL(DQKBfw(rmYitXuCwE5j1BixCuRxbkm0rQPl0F207wn83JCa1ZGQ1sHe2nsuoTTjxiHy2xjnEsvIPy0hpbyHKuyObWmlxeBZp7T5iv(J9grqOdmW14wNKieS1rlSYHh3qTe7jExHuqGCBs5YdsFkvEQXj0PKbc9U2iollI0d79hw5uBVTVgYWbk6JjxGAYFwzrh3)DfdmuMl3V5ftMx)di7veVzysxXFx1IurtiYlMXeBbXO(gl5mmz8SU2A84De5LHVr)f8QcDavAI3p7nj(D59Z0gBZKhSii4S2ZsDZhv7NNz307Ik7dNKRwWuCDlYf3TLEVo(zLxhJ1HoQZ5AX0zXCA0AavE3hia7iX6SL6wL9C(4VV03s44ImoBPxRpvP)02FR9VOsg4FM2HDcT221uSoF1t)OhpDwrBy)dk5lXalInM1jw(QKmBLOAZ3dTdmIt3)K6cffJDXOxgG2Lzb8zL7sVvsVjRGD8YrezsUJPi01EWYuxW62Qp8M6rQMm2kQs4tDpbhwIou1lAU09aeJDZj8NAhwfsfY4yfTFqISnb1p7AGy3No2DgXbABT7fEgAzUPj3ovjp0WU7m3HQngHO(vySd9RautRBo6mStOK1ek6kyyXn1TDfwHIZXOFX1ylJCi9SbRqmhhdfESOHoVK(jTZY3uWX6tl8UhfkIPDd1YjSLuUF4Nfx2ivrCuDnkCzTdgLZCOo3)Wt(WXkavE(iT(gyymI1ajJWYdhKuK4r1ldaXbABnXIAqBtO2rN3gUimtyRmMwtgTSKxcg7yggGt79(I0BlQkUSULJemhb1KfsmY4KmnqcDgiacDL0MyORbJC(eaY382J5CzLTfxhhWHYbNRjOZSYqYTnsvlbRV7TdkocCQe7AZsroTjHg2St63h6O(5CGyUWa3r3dMfRkF7uT(KSBZUo)0CY2oa1ilAVftzs6L68J1kwPHP3M1T8ggsGef9nBU9sLpBbIq)7NwuF2pL71ZAN61s8QTZSuD21c1YWo0dLyDQc3Njx7bINKszsjv(fpSA5n1nKcGRAYZrwKwadEy(xYjT15l5n6NkQwHedDtvxftaTGFogq3FmjI7lyxnAsPbQp9D5jDWRqcUx1yIRSyxisF)zdpnFsidP9cDcxSWZp0ljWLiP1K6Z8Xmv)WNw4(6XBtUoT4sd088IYsRmRLxCA7eu(GXG(xO7v7GR5LWURlQRl7kwdghh0b3N2o49j)3oNFVf8rcyuYOrOhjJkrUTInG3YC0i8zGgAuwIxXeLsoGZ(qHRLZqCW(f)rwIjd((FuXFE5Uz8U8YRu3adgOWlxSd07hz3MGr3(qyW10rZVjuLYTQGiKR)eT)H(idevjOquCqF1QMt19XEaJyb(meB4Lnjwrk3(RGdN03VP5DY1MH5Ai96BAo5uCUvcqpG0Q3v)UpLTwUpg0WUiDDDBbIiM6kK4f4DGd9pFNq3yLQ5pZxztjDjUjhsfQ88bTzuAz9YpKVIOi0TYqpCIE7D5aS49DQX9d2EQf9RFXtnu7pzQt03vgVXZ2IDTpnr)zy0gtgtFo4Wg188deCWOxqFs(UjUhtckRR)WTznFO9xPpGO8Rc)UkX(e7N(NK2cLj0jQ8Yh8IkUTTxXejxwwt218YI2oCXAXWCB2NjneQJ7smZyIOrrYQicv1niXPctAqEv15zf4UZrYSXZCyvbX2IBYfjMVKEaa9zd254EPcdAloapn)J6G96hWt2uDDUCJ7Dfj6kVAWlpsekh4Rel5MQyJXh(AIk)R0YOW9FdHWwr6VWj(a02WJ9t8cJLX4ZixOIpWXpgP2UKk3QvHXKwwL2RzobSi5HvdYycdbCCncwsrdUHte4ii9KZ(X3GnaVL4W7bB5jb42OK5uwZ3bqgAF2gIE5vvqA4secgX6hJio4lGOcrhAyDKv3criwlNbWB3D8RyreXtQ93nHIdxlo69fYalSwG1hRPoKlMYf1RPniTWX8ikCiT66bz8UtuKAG7Y0zqGE(Uh4664r6ot8urwMKD5eeDqGN3Iq3WipgdALbcOQgW54M18RTLzS(tnvV5UBnVNKKfP5KfiT3CEwN6WAv2fmqxVw5U2g2V7F)VHc8iBR5oMu5I700PzvKvDSXJKxTRULGA9N(GyE3s(UM((K37UiW3179bl4Y5C6Dvp1JpD0f4c(jAHIsX1N6zNBUjGMpb08pfvUcvS2KHn49Xl8CIEFKB)O6UaKR7Cu7Vsx8G6l5OncyQmOUoV3nXZlo(9(H9dBKiG((VwXLzqS8xnSlaiWn099edRge4gicl2XWo7IfbctwSX0O6rYaEFc3mgy4kBE3oh0Gu11ReaGijNdPfQcRQL88u3fqe(dyxZeTH8HDOhKhiowY13(TxiqWEUV3nMB3(y75MSxy2iYgvcJgNUHC1MeH0dOy9R3Fava5Kh4fiNMysD5sYj3mxySbjJaspoc7(F8M8QxvLjxBuXPaCBNvFcEeTjuKFsRYBZ6qgWqcOKxHhd69qTCHMh52Ps22IeqrlyLLFtaBjY4KHtFOImZIEfYiQkykc9QhP01gNsMR23rTh6gJF6hYVZg9Z2KPkmO6q4ZwI4Nsc0jJgTdK7Gl45o7bMAYlJ1ISYm2ZLLFG1ABo1j9suK(sEYI4pNKQf80Y(bXBqJG3f6f9HQ7JlNuyWqZr7ojMq4kHZZkFtQv73Z71VqMqFGCMJipjamEG1ud9CyHcYCrTDC(ieg068MAjmje(I8exzLGWxOM1J05oJaF7LHQB6IkCPyv)0dKBOv)OHDl0eQupImXPMSXzGs9a4DVsnQABkKOkVPelgKRQOiRxDbhX7a4l7JCsk5TqxXsuPHkYR6ytQKtjOFVl3Yt7pJ8IOQtmkzeD2ptsVW4oxHMvoPdBcqvZr1vdfhKjhQ53usluUDFtgroOJmIyLZ)SU(wnYwPXvajkWUqd2JSEHGSeW1)qvw(LpyZAo9XEXXNCb7TX4Uwa2dK7o7ejlghByybazog2EXzFXSRt4xK0qKetiMqdsKH8HZWSQemqmA)WCUEplktXohN(9Ia5DYmlGBdRS9(EkJCV(wYgoAJycFOkgaF7zPhYBUD5XZlaFeR7KZAFKGPj2R3BEGTb7bhegfN4465hegbc5)QXOBetQy1uYjnC4JeD(1YCVDzMFX85FZ0mRSN6BiB(C1oyoKJt1fZF8ouRp2)rJPxkM8Wu2wMXssgs3B4UnB2P82dPk(nJH(luR8e1N3dE59RN2p8GqZ)Gs3H8Y9AySuQ(vP3EGDF7tFmhQBLTB0ZQck(m6ONZEG50BpRrUFTm37vZ9iljzv33t2x340AeTJZZQUoxLKbSDE73EB(qQrM8XM01(PI159vWcfZizGbN0TsH8AlwGtgcBN6s8SBCkrN9XNNFBrLouXYjCG8JNwc6VrmcDKc)TZ6pM)BQ59SPbtfPOst8L3aJInodO(yJVqNvrMrzz7)ZXI9FiWRj2(R3M4GEFhbTwrgM1BM393pGHkZN1CZ7H3aeXJ4ghxM0qSgrSDkl(LFjRHmdF7MaUD1qi)vTrwwjYIvYcniHR8g(gdo(IjYMM4cXWWcoNzgESZrIyVJzKjxbtgTqhK0pF5sMMFyvEamIqwzG(Opv8SZOdbuNdLLMyY6k5WrqbqJiIuXkbNDKIce37gTlDF9sNe5L2UoobLQsnT7PlgBx21ocrXwKKbeCViiTiI9jCZeahRi0TfXC2JVGJMnodJcNHLao5GXgkNmiDlIxM6w62LWn17qKZGk3HncUuxzLXrXaF8qXjiz)0b6zOWns()j5xLx1sYmqOn2M)VB13XTjHZg42ZwOGbwwm8LkO7(g2JH6kMMrUtpfcHNBi)5EeAn08qB)HMyd1ePwZhRdIBz(Kcwl7Opqi8raOpGDMgERHgzu6JBUkudnMsDOR2Z)UoafDnsyN6DMpeIdxqMCIzobBBn533ECtgiarjWEI6BBRoG5x7mQIHPv5FmVzQvw2XwtIQjXy9(3FnsYQ3VeAEhtOzIUUtAr7lWdk3r1TWqzrvbSSYhhAwEzXQv5vp54tA3AGF(6SO8RuoS15eSf5WtnPAUW9IK1Bgd3SXx3hzrZfM1D4L5Cx5cXBJT2gCM3UZ7Taz)03w31(K)xp58SLfzL7qM8qPzse(MQqAUqopvV)xQC49zWzOjCS92TSLduyxAmEtDFWC3fJK4vReRglpkKOxVDP0QBj8qZjhlWPxC59x28wLeVvRrpQp0)pazYxQ6hK6d1wNWRZ5H(w1JpA7UBHXpKOxpJu4rE69vBB5al02ICIVmPyZEgQBrm2ScT2Mt6dSICQPHBXmS5Jw1wJa(2r2Zi8YBlXHJf2TDXG7W0YqJPLprfkUPUppRU(zTmF8jNTfXitLk(nWV5zfJnvG1qRnNtM63g7kLeJBIdW7YOXTko7(DSABZo55nFDaZ2(VCtyZ0NsokPxZzG)Cc02MnKd03(TvE1eTS4O5jkB(i4vXAbviAjfBjBk9t9cJOFUi92S1RlQUMpx9ElxKuRf2pxxDe3y2uAVwUIVT6QKxu9azsomLKEDjoUm76MSjpT7Vq3C6nPmw03HJi(tWnQ6j)FYVo9jNu8XIQ8N82nnRRBZ))IN8wuZyJsp84lE1p8m90i3HD1jIGT5ZBQV94to958opmTnVmFjQPSY2JEsKxlPr()TBttO6yN)oURJs(nExBsDpNduK381F5pocCWw)BnU(pF7AITo83yuTGxfLc9iBLEH)yKLfK6geHeb7VDIWrY99B5M(pFe4GT29Vz7A5Az2K3(HIk5cVZxhmYcw50KWvfcb1k1zY9R68826nnlZ7tlrZ96kjTKV9Jl)Wl65JL7e8RvFoFJlWLnVA5D4zKl5Ux61lxDeolTSg(J130B02zq2EnOOni5owxwPUuEj2tzne6dGzWvOAWtW5ThsE1W0Rkklrg4fGoeI(F8Lk1Z6oGZjrMjjP73eY9ZkwLPvsqhhfsroB2hwUXqVls2zmqqo9sfyXAVoyjlzRL5nv3mmvOfUjRQkVeGEGiLDfcUWKDLbh1ddss3uH7XIjrY)ssL2iPhaObbcSxsOnZTMj5GiVe1)tLWhsj7B5hqnkJjcrz0t9NAePe)QFU6PH6KjuFTJ6l4FsKu5jDmKcWb(eed1WyUBTG(QXWPto0jPkU8U106r4j2sUtO2Wk3D2ZrgyUhbQELGv5pYrUWdyb1py9GaDsPH71WgIHvNqHA34ykvPvp8IJprZejBS(HvqkgAhqV3xYcvWAqoGbZqGiqFPDROAOK93YjFGiqMSdhsYx9SBxJQ7276YUMlEdMbrqg98laxWm9cjQIiMu8R4hoPObR8xE25V6FE2BU4qPTXiiefmItIwfZc2il4k0MmEGDAejpNg1xNxLRQJkt6nSdMRTEvfhZI3tsIYnM66zHcX3CjJ52YtvPOBnUarz6zwSqNr3euK016gWbjLULBIwsXrWQ26XzjEskjp9dxCt(TiXWhFRJg4oQuvJuTzgnj2msPONtp7cQBS8iTKh574bThnpmmG9cf4A)J5zfMq(gQyULM9bAXwiTuMOMjib3dbbttyAi3rV3yQ0bRkTKO6RUQnVtD4sd45NEPi3rQ(HMt3yvBgqqFE)wBY15XCf9hd2eisVKb1DVTFxPoZBpZ(8Tl7KQNYmIgiXBAWHLkPTCVxNp2C9sl4gLvmkBIeWJeJhP6hr9ZqVAWDkjWwMHwXTkifGsZUoI0h3TjGhTGc2rY401nf3swD8hcBRQlvj1MvwQ52yybL(aZkgWWgMUoVz9AB0ypaDVCSev6kvtAeM9Xcu2H9dOdXXL92xD1BQ12cYR9Xgr8u5IQ(qVupAYKDBiHq0QLVmRmJXIF(9qgYC817WetZs0CmLaZ5mvm30AJMfMvJT3ov)ULUPe4ynIdnHwS2AOGL5pI)TAT0ujmOysOLW82SMUISsDZNAoruU7uXDVOgr0Yds4LLGj2(YhGPjIg8bfWO51fVlZtq9HQlh3ZlskKy9PUcYmWyXzsAY9NDD3Je)D4HLo9wGyRoLV(Esxetj1CkOwzeVrzkw4doZU5ew4LW37E5FWKGhQGdvDFEy9trsHGvWor3fHUE(r(orKjBsjDrsLguhj6r7gs9(RdIvH4yOWjBMk1nMAIpJBxMU0D7SDzbLfwnutUymQ(l3it(eLvZ9OoCbh6hYk3K326KkhcE(YxDcFf6vvWLTW0ndpdFFCHZffx19SsPN3Al3hxI76pvzBfM1j3pr1dbVwxSwF71h7QCVshHbw1grrMoFvz9N0oJOqOqI3eeQ4QI66Jn0AZfQKjzL2H9EBr4c5WoKfn(MvPIdGYyQzS(0JSHztwZQISk4N5lvvVDvl1C02sBPziliPFqvp1ZXf0KVF4kVITWSJSqMiiiyR1LJBIBu7vdssaUM)ElCcwG2yMoP4uwy1SPkV9DfOBcI1ZI(n5RAQRUAJQI7l7dH1jbRiDrzo5G4qFNfrbO7ocx)1AtMM4g76AfsJOU)vkIQX0PUuJtOzarIQc7m1E)EkcGcMqknVbTJVDKZwdySvFm4E9PeqnSCTwxV04MtVwc(2)sU1Bv94p(gUCuZzff(fViy1xBrBh(gvbS40SplzYHQiyhX19vvTI0QoFsoUJxsQLjUjloiok0p0XpGl5oH8LvuNcUwPUGhxVtW8HWxWUycoUFOUGR(cQYG)cKjCL1xIKzYUgjWXGrkYMVBztDzPe4o(VZ76W5KsFIm5A2Dtr0rD9)qLn606pYLYr(Ejt(rsBrPCD)66RVi7sjQn4tv9v6J4MimjkuGfwxFW(e8JRUCxAs1w(a3j5jwqpDr3qDZyNf3tBVIQ1B6oR6IAUob5NwSIyyYwLFsEz2DSaDtSGuhPVuGjvvjJU6S2(kRS(cKheKCqucAlrUo(opW7k)tDD9tKUQQhne8DWxevEC9ACHztyQbHVYpMJl3achP1ypbzj9gbLtmO3ju2YLNiZyBfpnMgPs6ODKLCB6kj6uUHLAtUiiFL5OKUuAznQfp)0iNWdc89CO9d6dSpmdfEk9kEhGlRya96Q65prckOzUsYbsLb7jrANuTo46)0zvC1GsULmQkWbxcHKGXSyg(sfPaT3gu0BI6PoExxtE11e8xBOTe5uLplaotI6qNoUl721Q40eL(F8Q0)JtFcxjvFF(QIoapFtDhbPpPO92I2wooqQABMoo)SOLaBrl)N1VMT8K4G6kZjN6eC9sycYGBvXGpRpdBxPAPgwnewur3brJUcIm(QcnimcHPV5z)akgh0EupwdQnW2AU6R6aw54HUk6mUyIN1x1xyEwC6I8pBeBHSsX2a(lgp9s0yH9p2xLBu(k6RGa6Mf4gPf5FCw5YZwlDTwV0RkAA7oFt1j1vCpp3nDzdHbFErPu(QdsFzEtndB(buV6YWnAFrkjF921QR3Ut6HR(iz21MgMGlifvUkonmi0vzD9QYnTqBWOGdyjCsbD5quUCttR03TNXQM5IK2SxV(5soQ(M)SiJFEHJEKWrPu9OD0BENiLkk9XfnlL6v503d1iOSgRQsF)8Z91c0cuqxKxvzUY42uYc5OiqC320kH9koTb93(8ptFEfQVASglLcpH)EtB(GIAn6Oo4X9F(HXphn6DIVSjRa6Y8Xzqn761mRq(49DTAwDCT49J3n5OLgS44vGS4Eo)pAXP)aNJpXl5K9U5eFxXXmq0Qa08EbQWBty5ntyhL(QU2YIY7EYtFYf30KvY1NC3ulEa6dcrTIEtolsKEzq4FAw1MSYdxTseuc0CzXLOAKGaDJQvlHY4xTfvit8qEPDTGBLfALK(AAwxttiM6)5MY)3)xfCDB73H5oMN7BRR(WE217ytmDpppKPh0P219wbst9Hn5zpj073PD9cExtY)U93Bao5ffJSjtJA7A33S)TfOZG9f2AipTaLXT1SGwuswLFFENe6RVth1XL1mRONp3Lt2l9YoudVSSGikDt11n1BwNVsYpq9P8Ww62KDfSvMnkBUZhIgUJYw(bmasREh6DGD7VQc25iI14UI)Njjx0Iu1MXKY5lk8pKLzIlNxteBD)q2MsLvr8Isws8mZDmRYwiPr8e4ympIXoVFz2Aikz1zK8EPyitFjx3w02uqgMcFVJsRxNxDAb5tWP5vBoJ(1vKrZhxIEpc7BowTKyduX9qJUVdbIWy7p)nkaLy9gVDvwj5N66Hc8AI0QNYws25xMRWnvEsfSAurGmY1)GixxNf(jlc4ae8acgLRBuezSESxKUCRrZTbsYq9xvDvT4(u2hZxjLfgltniRV)V3K1GgMdkyM4U9QOahCuIw3RoV0mgkiKCQ6Bp5Rf7NfgFbdmxDcY(K6hD5Cr0Sii5aJXiDre2adPcKlH7B0vXqLES)ty5JCq7OWkUwmrKZ8IjH(AznzY4BBYxwWvWt2IS5mtz7wxO9ne00czUMIt567bUCa1gtjkwYk24FQOlNt(J(T(px9u25vLBaereQy0Y(hBFjxGFbAWnKn6YulLnTEeI6eVu15OgXBp0OTOjzWQlG9XwC64wDvqTNvvERFHaRgUzzvHcl4jfxDvXsIDLldsJmEzGn4CK9CTfX99vfDpVbf)kizZN5TjdB6KYhSXIkUuHPQi1XP1vL3jn6gvZFbmSsxosvIghvFYW9OIB8g91Iwv0B8mZiUm0MYJnwkFkVr1Th6VFYZ05GMZi)K(kZSYFfZItf9dvh(tTKng7PRBudQSZQi0LyvCO77teGsqkZ16mtA)1AxPhMOFER6k1eWK4umk9LBU6k7sLL1l5PkC5QU)HuVBz9u6stFF7puyd6lA1egPQdccZBUzD1g0P2Iga3b6ACNf4CC5iBZXj8texEiCji8GcLaI9P9YuOifuPwBxy6L5LC9aMq399PWdllUg1huvjA3vEjvWQSA0N2nAcDjB3wuLb13t0yMe1hrCUCdiq3IlwGcPU()XjNMIqSNCvfCcPzFWjLY9QDEHW1zrglTpl0qe5omcx2tv1N(PWnKpMFMVrnsixuvkFzjjyojnzzjM9DHaDDdacJSiY65dSXwQmVciovre3WakDnH(TQa5unAkwzJkvI49NefjvmYSAEK6(E3nfxFdHFVpvS)P9UsvO6TeGyAslSyyTqloWsEPE4M4ogbQdTOPi8YRFxMXYM(rHXiH)QlE)ajb90b9F6G1IUZREsr7As(ijpJzTySxp4uUIKMaPWmo9fXDH(FeB1uoFl5xsosjDjut5fEIOeLqmAjbm2rwv1wDxHuifhe7hHFCSu7yf)ZqrbqmOLq(EsusTfR)6kONrfhFNfh4Ne6e5g7jT2arc3yryKrD9JOI3DmIvuKO6hvwGI9lfMC2Tx6tFU9Oyh7PWflC11ltLG45KYnbbB0zngOo1Uj1L8s0FcnkK2DwcLTIj85dLNWOBvY0YvVDL2BBPUsEM0Z(VLtgM4xyYc2SnUMZl0Ui)suZzpiQVs7)ZvsViXXOx8N09atdODqteuPVfkpgERMI8T68vw9eVio4X9Yj3Ikq1se4fLfdI7i2sa7Xhgsk1wYQD6QR0Zjkdrhidu94I2(EjJgEoAvAlT3iPxTyeBdT6DH3N(E4Cn(lCVZS6wFZzV8xGrAKLHRYLaOPjKEhhdu4PKyw4aXTC5RXOWW2uov7cygZWUS7sMMgNKJcEkDIhuAU7LLkwHnR9wIz6APswrFEEZDMxDc8wSxWsFv(zsHlXdTa6HqejE69feCr0jXqtBlEaLbdYjS2OVw5cSX8MT2qLh2nTechB5Y9KSm)oBd(HCZ)bh6V0pP4eXvj1((BdelfElM9mRTaiEcSmQPk7SGhA7g2RTmgvLO1TP7E1dQdvmZ1iDooclNLbijgKXGkQlz7s3LCNZumuzEfjZyrWo0DpNLhdXxKmsHcXs7NBKMQzQkVVefzF7u9OcVIU7CnqA4oudO2o9kg6js)sf3JMH2C8Dm7oNaWZlXx1Gl5SFwCHnIVRRnvSdSDx2J7PFx1cPgANssVSUEvMtDefijJLoJSau7fSYrtvV2)H5GisOo0gRH6yvQGSnV8M6pxVxbpuF52HNAshCMKrRTFdnwc)fEXeTCGQpYB7Wgtrq7cTyrldtrOpV8ORT7PcGPR7sRglSUXHVtnQIjJkdN5GrbqMY(5Puqd7sPS0aMcyGdzZ2NnHuylPkdFbE70RsZ4S8yxY4KXNEuljvM1WWgPY4WWykN0Sl2w2MQ3dZ7mHvVaUx4xVhW6x1cZmVptiyK6EI1a1T27BRl2YSvrH5CgDKNw7O(8SW4fIDCxyCcJdLDfBL4CInyypNXjKF3sSXLYLpYa17KpqPCWaoy5f9oDm1PjX9XX(NyKFOE1G0hGZVBnrAb9NTebDs8WsxM1o3T4J2oc90C1))hQpsdIuTjRaTVgkQEOPcEpKY3bX8qftrvtZFyGave6BZ9OynACmp6uVJSPEFOHxCRUHTdVOeJehB9VPToA85rAShsktjnwieE14TqBVNMRcl6AuOhSy53QVmOa70RIZITFAi7mEa8To6y0AqtLyc4LenHilJ8g)DJSw1eb4Vi)V2Eqn4KRq6mIB9ybrvVCMGLpxgw8No3ViJPyi2qN1rA0qiG(0Qb1Lk5y6nDoXbbhFSZAQ7q48b0MtdTzjkz)tUVE0pxc6Ep9LBo1x71DUP9a5FF8At30vfhXKWlRotzdBPwT())27kDPghjB9turyjzjz75x0nU6IOylaQUV3Friab4PSL9yl30C7yE3NZwUQm9cv1mtnxQOIaWlPKY8KN8S8D(oQEKLMOodeG3oo1HP9PfZKQJpDFq6TsAV6OmSTPiuhmA0IfaEU0vaN2xb2SFCZ9tURQflbysKBt753vN(IOvRByG31a2AzJLNN66Q61oUNCl3ZlyNIjRmaO2Rqy(9ZZpo4I6M)TY6Cb(uK1pbdaOaVxlx)KKve01pSr11TK7jcajWltTVo3c0hJf4)b7COqz17ywkf1zyktzNfZYoiFqV0(iOFPUqjyrR3EbROPUVzD0ZPsof2CSLK4UBRZyFZsO93fx79sti2RCD2uRvu5UdkwQc9DaDyYbWuKmxju7OJdOhmCqzb2yd7r)sq)rjrvp)rjvnU(JsttSFf30oFbTSepqVoULIv51cAZrqb3T7tkNmazZeg00JBipi3OpPBmrmXCyTBK0IeHSajB0ZZ2aobzcPh7)QGScDyyCcIcRPxfMylFl3bpJLkB24z8hOmvgntRC(7dgXrAMI8V0jVAEcYA7l98soyav1mqES8W01Jsp3KDCrIUgH8og8dZ27y(86n5FSBmSz7kc5ROG()oElJb7jwpAkwkh3Ip5(E(zHec)eWj7gI6HCG0MrvNoyh(E4DEiVozO544QgII2nMyXmdHJOsSiOIbtLFNoZMVJZBgLnHse0(6u2MYeiSrrw4Fv(xR)2Uo9hlXnbY9w8aV(n4FCKiLSb3M3q6ifOM5JRf9PJ2rvkmYf2V4eSreMOI5iM1dD4OI5sTg8AwjO87H9AGNHEAmvTHrcaP2KFaEUHcsS0jZuhXar8dOBrQkQKIT2vnD7pNS7Pj8yzCxF0lnLC)xeBsPjGbxWVJAQCBvSbGakoCPIJ)oJhOLv1rT7paTjzxhoq9eLjpvHFXTUw6gRp1Vz31bcuzYbJa7KPz9iHrCuYPmoTRJIvQLXXHZwfmmPK3a76OyhBet)4fhN9BYHWlz1QvKkh9mukZxm7CdZLKcmyyeUHOvi82PSyFwRGd64fDxXYpKsLq3EChHZcsvzjM35NsK5RwPkB6ckWiDeI3ryvAHQUD01e)m33jaUEadsZYmHYiAeungakIQmDah0WUI6fAaFOeQ)8HXPKlMJ66YqxG4eoegCmhJD8F8G2ZHfYgvoHsyqNC13bAcrSNNX(Nhygt7t1mQY3ioCdbYmRlCC1GdZeepeIIA4NglDNwd9gXNve84fhIhrmQD)mylkWEcDw3UaghpXmC6HQ3krR7p2BhDXOq)CQ(45)tz4DVSvEp3PUHSy)9ztAaKe2D3zupPE1Brznh(Brfo6YFx523mT19JrCzpsMDJcWQ4Q0IbR0OB1IQjxkvI9eoCH3bIfUHGHmhUspN9YJcWyroBoeAtBc86C6BM3EHk9n7ufk8xWrPXu1f29GyhMUTZ6((CIAW9Pka(6xnqVLhMQi7YnStv3IccIsz(W0UBb7E45EPhmsYxITnA7hMhh)ZrqKuK9(HnGlQgH3OJsT9eAhH1Aeih8QsNQE3DaWSICTd5LMy4plo9ncX1W5y10RFCOUG4wl5dwGnwVqBkN)bdt7UbwwKcmSNFeKI1F4bMaXleYBaE4Ct4kikyzdLKvRaS8kGb7oLq1HUpOkS4KDGcpCiW4ylME9PyLl3gDcwf(zXY8CfUfL8ZUxOMnskwXWRPD1E8SfTVyqxIfTAWSimDOAxuR8AHJB0mZ6HuRDSqA2uEz7Ii30G5LLRJUxdIChynpQJPBgMliDy1TYZ7(uPiXYrlXkZiBiPZAoJ)vLhY7p6DrgpXDanL9fViCB1Y9Uqo(Ri5TijprLHUkkrcKz9uyZMi82adyqhR5UXYex7Dr9KgCcUps97OXP4VZfQlX7w6X565uL6IGbBtPfg2iP)kuKwPejdE86UAQflhkHAbwnPuH92IuzfCU8ltYTu1PFRPtEtzin1tUXlRRUvMAVa5zg77Ao7CuLAUe6Dz)(UdpA7Luq22OViiOPdw5N7EkR1XuBtDUylW0gapgBpT2CHgSPAyrY69UxRTGT7wGhLz4bVQ9mkiU7uapDb9SKUWizpzRieliY1cGr89fMOrkfkpbqrIjcGZHvqVpVfPYtrC)wHtT8B(KVM8Xl1hL)ve9BNiRkeYHBJobcMz(qifUdseIcTGUrdksTw6Lp(yrfEhYk)wZj)E5Pz8y2eaC7icxOkzB7Whow27HZNmh00vGrJsuvF8s1WsHjg8ynPwx1NPX4WjqHuen9SXbeFGeWhSsIToO0XyPiuNGNA4q1mm5)GvndZvRyWu777DGtrtfGBiSnPqLwiczl2gT7Q5DtWrpCQ83qboZhxPaLJgtMHQAagyhC1jQ4RbgNnHq9)UwLLBa)NFdz))1LMFMDGClNh2kuZtnAEmDmxqad9QPgcg3EHYZwauSglrh7oimdabagU3XtQpE7rR9mPeGNGeag88CtGA6SdjtemWlDapjhQ3TsOd(LNPQCDJZVkU5fzG0xWJBWAefwbdpscpC9u0aseEhW12MubDwvuH)(ZWcrdZMWmSbSNc0BtTVDn0gqquQVjTgbSztzV4gvDyF5LsKEZflFa2)jS6xViM2hZL)(qRkrcMdvLck4XUNSoGBzrRrq)(4L620oalYD4hNyffvyVhcPTkmYw(XoRMBiJfFFsjY2s8Y3N8x(oidiwO5))cYa48off1Q4RngotG9aQSMa)QGDl6fzCkXL3Qf63yBs53u)rimmG8kseBlSI7iUoGSflYoClNF3K2xORaFK)HRxwHCjNn1e7r6F5JAMZ0OHH946YLGBSToG8VnDkww3gxs3wEg7Pd2RoicWZHJpX7xeeUxwpBsd2rmzowf5z(1ZqoJ05HbzG)r1eTzLoQA9JiLuEd2JeiA2RfjGJVIbORu48yCYh8qN7oJpJuZj(vr6I)RVCZTtRik)lD0Z4hGNox80K7ObOz9SBrAkMUDQRw2(0uSpEJVaSgdMHJSKjgn1Q7NILW8GrpdpapSEj(hiN8pxUwvZwmDYdVWF1bJwoPT(MQ7)7IyX0Qz1TZBECntS)07UQQbVhahuEUUAX8MBQBUdSUaFyaRLxozbmGWOXmko(O8t4tcY6JC7hjv6D6lQVBs10vNHfTaZa0uLSch8VS(H6LlRV)3OXFmp8s)d8M1RqomXHBPbPt1x5JWdM7NeXweSei0qcrcyfJM9slmts3HMVkoRz)DjaO63bRyuoUha57dQW12wnfKhussQwsZhiFclX(TfUfbfH4Yp)lO8MYrpSmF5kEEa1Z3V(Lf1sFf9pyg5s(R5yhjO9fPdK(I8EPer0it8od8rRBESgB288y7grm(VXgGakvo(pGPQvREUI3qtBYu9)aX4AQw2UQDzvBfmjF64Jo(lNQ6F8Ue6uwjJVsm62LYVlHaWEP1zBo2pgS6nIFGaSrQqG5hsK7nt1RD6)sfJwQ2aBQqkUrBTfIaJzQA3LoI5DHndWAcbqFMDQVdxEfR)X1pB5ABA2Kusunbe1ZgT6R42rWZv4lSg3aLp6PzCpgf7c)TpZV7Y5nuN1a33UKvdZ2NDE7tGoPtNSAfSJJjE8krd7wUJiLiYjgWDeCRq0blwfS)(8BWbr8iVEv78NV556xwcBszoRhn24b5NtznwREQ6(5pd3DeNYchFmzwnOCCfUNN1vClYkKl)6n8oDzWNozvBnXP400h(rhoA1lGQnSHfWd991pO(seJFNM50Mcwd3GxJKVQQBu8p8ELa4eOGpVJAuOLsRSb76XFIQbnH2dX07D4D3vVGyvySliJadX6JmKysZRxVe0FDf2nKU6RtW(7HdT7Z7LVE(cSfSGpqzWCt70AtxfH76u0lkWSe(o13z(ayUD1ngZsof09SU2CnMeKD9XyEshznc0i0l9aMpwW8pVNOKpjjZo)1mSgV9rCgShbn(iTCZhzppr4vHFOqvpTSyqTRUCAXOC08B)71utN2DAcX69CKnrBRVh7qpze3YidGUH)ekKtbizBt3HdNrLvaQ9iZIebyRARlp1TCPBxDt3KNhS(mmC8KrgF(gQ(84LHN3GJ7mcAxSSg7RdNUEA7KR7YgV4HaA24ftdfspjxvp9HpI9uIRRA(6QdVDomPb3gsOtydP4C9cwiUEcTsHud8jRx1YgyXsL0G9jS)4GdOANNhlphPI)piPFEVHd6LnmnjVWWuFL5fdksl53KHAh1w)tYktZ7pSxYWIEdO6VOpUnNVz3LqotCo(zGjqWZgXPLCCvxuz3hXa5id7PchKQAUZWz366VQt235UM8LZXDOlXPuwtfpqYGOtBkOOBj8jXmaY3gc)eygFN5pKa9EWIgJyGMrp90ff0(8Yp)uTIS0rlcQNI96mKRqbD)tMoL1qtKJq1Ig6YXF5JatMAwb7yKE2EasHt9uSRtZW2q(AJILtQF20kWhMt4xbRvJe26gDeQGdH)6kDJnxa0JAsYH7qvXJWHwcubtG0vGbkHzVoxBhyc7MmDq(vmkKSGKYPDCuDM8XouyWDkOOVSnXCeEcfuENbG740J)dyjRbmBLSwgU3O(RdS6C55NmwFxdZy3RkxJsH8dEcNn5lKP5EHTmnJSSZ8dy2QiB5TjeKYj6aEDtlCMls6(WUDqYcRs7JMSevCcUNyvLtGhvWdZUM0oEEV9jAoxE4WQWIoxNlybMGy5t6XxbPZBK7KyckxI8lSPia2wm7iVIfvOVI1CJvfShkwSWcmR2Z6YYgyaZaD2F6gBwsHlQLWzEgmEz285TpbprsVdJ34jYe4(AjGQ8RtZl)006AQTUWk0ckqcl8Oej3cfRA7oES31(VosU)IofsTTKyhYBLUblIDCOEkQdY5XkasGK()gQhqnv5iAXAsoHleFy8yJPnBeuK1i(kS(or0MxuTEqKdqjyaO21HJgODLMRvIq0YpUIaROmbzQeLy1UGXITRj1jo3OsSHTzljkpe45jLd6NrNVO1re4LjQJW9tRpfcLSSoTqLFZhpc2dGMZ2W9fQuvx6S(jWXAEQAxZzAP1EeVti4HWsbbmLPNe2oPft9TzqCaFioCkACoTABifoXXHRwpBgS)SU5EjicYrq6dgLJ9ms8xmFYQ5uJ1He5PYSK1bNlLkhboPCMEQWTJOmHwdan7GeWNW2bOOaorRfELEFW6MjTA6M4YJ)LpXkimc5byWMU7b2aPor3LDBLY0tsOxNR7No0mc88i5xXQIciXEyK4FQYOTibHljGnfhDXvDSpZA5UuI8M)H0X4vjuhzNDEwSFPyfdEj5Jg5du9yOw30fi0gaLbb5UgC7zk3D7GNgYsX5lN8)nVbCmM9s7wZ(d2dfZjdcfLjznhwCvMUrl5P8bG6ijWoa4BbfR6bEUQSALjIrRx15q4UgbOr4ILoCq2RUAf1mXqrAT8Cg1Nt5kbbCfGTQaVHWlnAo2sKzJ)ZpJ5tJcLPx))pKiSX)noApQonlx8SydUhMd00B(rN)BNrHeK4nFS2J)NFg7kn79vBa3uvuxnvca36vdFMZyRg0wbiKNkPW2(Klhc82YygBSbdtKS(4yifcxzbPkY7gbW0SwLc9PH6n(2KMcALOXUks2GI0vIyedrn9eMH2UUtWikJ6UtRECYDATDLM6ekBih4ku6ilNQtiyQszfejDZXlGvBtkI)4N5ZhOWJPWdoZn0bS)tZ71gA7YSkyGafgsIW7LVRE6uN9t5JA5Uu5XyZs62kR(zP0(kXnXBjg(AB8LdhTT2i87PztxlJ(EEYcjuYGroCpefmE(6db59IrFA8HNm(sqG9Odp9WFz8LSNfO)XxwVcwB1GxwcrZIkZ5lUe8QCmN4hhR9cFgTDQG9k2IxSbbB5oLmn1XCkqdj7fKyrmyrh4mghEkpZjXZBvXfLDqJKT)sdcSjJtuFiT)E2ePyQkyGXayhBRa36108Mjf(8RI(JmH8lGv5I3IOTzYQbikrHpAAnj)U6pVM(h1Tavk8PTMCrBWKHqG(1E)EOFH7rSX5NiNnE)86LgDYhWDUF7M05bfzfY8GXWOqovR8EWzTi0kSM3(9T2uxry(2lRQThLNeAkI3mcwCIjy9ID0d2UIi7vsrCRrveD2nGcrtNTmRUvCSrCz6b5m7IHqzUlh3iYiF(ez2RRxAU7kXbt8kGPQsyHpClPYqmPbZPUXGTzSVIlwo53RARPKaYVYYQMhvTqx8v4y3l5QHIgSMZ5ihUv8SRo0Wbc6H6BZ86bRJS7EDf4n4gV6kqzkgDfSDVQDoA7Rurt7oQq0o8nE2BPedDDzV)Otg)rwl1Ik33kFKYwyXqDoavHmMCRXpBWOBNX9SDyjKbJOwrqhhmDTUbuwARzlbBnVUb7HJ3TX)j42LeIqvDUnlfRQxIcte4YapyEDxy5v3(IH3aOqvVMZyCSBGZF1QlQxE58NPoOKXmjfmP2XWrMHwVzf5fEzKvSzzCI5biMT8Q2E(0hoPAfDgDN2trcA8XGrZNlUicUXYZDMGUyXhAGpQZmNzYaT7Ol)YXhDZLJV66ZV8WRp(8Z(t815lTDJadtD797OxiWu3Zny77L0b4yoS)KJrqg06l9iAxjOmZf2O)b2Wy9HTLqSfWSZ8s)rTVSadmhUotQQibDvqNmsYsWDCE(5Utig3xRRQ9cORNEOvTS2g8I5TxNSe0YCcYXzYREjsPBDClGDDGjDR(ZMSSsPJ3mcZhmjlOLVlhD95xiAqCVO)pnFa)SEs4WmxGO1gAMg3k9pFtft0QcFxkz)LsgmemrQPeCAPjjpVSS8V10NAzPn9ZgMdobI2vJcqCsaTuqccqQZz(lqcIHp0fhEYHhD8z38PZp5)9DDp0Pe)qO7jplh09asufdt693As71RxAo83P97dcCAzkQ99(UwjlBNF)Sl6SlmS8dsibOS0uuxuAEpo7H0Hz)Bqzu(Otp)SpFZPhF11)24d)1XxUp6JIWcd7HTq6d5IDMlfhjTzygRHcEYTyieL4JxVHqbnHjMDqXR7pBtEeRp4qITBgcfzG5dTqlEnMeLKmSa050KKumO)qsFubxH0XozRR(wlZwfF(JVNfJwHVDRjG6pomXWXNGL13C0Xx9ZhFXjhF24)lqII8D7)QLOqNQSKOsHJ6Gt0AsgcgnHgrbgqLLL2dmQQFsrgEOxVEfKzu7UmgbbqvG4jFo2pzSbSiwIse7T38P3Tj)BWZnWA8bG2jr(PFz5aWCCwmQjjBO(yq2)(3utYhm6QpD4PhE27bf4hZGcmeC0tzffM5Y3n((DJV5aszotRijDiCUvAVY(9ano9H)n0ehab8)VPADgoA8VE(NhF5nxC54RgF5V(ESiBEub0SFiIhqwr)S(GvszLzPfLg)4yEU(9OsQZD27()ZXUUOijh0bLvucIoWpZZh2hCClRSGmgkdSS2oEaOBEVXwcP1jD4x(LthF21VRt6hmDs9blQrZSZk6HCSi8ZH9Zngxt4v9DDtVBEKV5r9bxWqp9b5Numi3WplgaU7NnmpHr0khJY3AVZyp(dbxVKUyiwZBC66csLg5Hcki(4Y5ZOgw147FKQsix0MAbd1KrZQx(OahigpBkCe5wlggGXnmpf0NNuw0VShSNdHTdbkBoUfovv9hxoPU5EU0PFq)7jfikKW0iRQhycGObkDlPMxmSb11iAjBNmT(xKYGvGrnLI0HCPQ61V3TdO1q67QkvnUoUKcbQ(XjZBqWWZ4BHhx(QeRO7WA)MQvqAMc)E6sLtgzIyPO39SQzuf74wd8WFjfohE)7ujNbaOHP(15RevCzmBMZj9MZIVEocEF89yKAC(dpmvQmXGDM7EguGIvWgXjLPzw1SgVwECZVpPTwWWTg3O4Dsox5FHyR5aTHvyUB9QASSlBAVU6wzUdVYu3QHxKXs1NE40xiQso5MGsgoaUDqQ(JEOIa)2pv10uVC1hP6iLQCynYqPA6fzhHMwuUSaRY6BRMgOUNNVUfNXKcjNl8v47oeRUo(gh((d03fGiScZMA4KoWQA5eWZl2(ZBzKkMJkNoWYA4F)R)",
            },
        },
        -- Blizzard Edit Mode layout strings (shown in a copy popup), same keying.
        editMode = {
            p1080 = {
                s64 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 903.0 -912.5 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -460.8 -534.9 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 8 2 DebuffFrame 15.0 4.0 -1 ##$#%#&3(')( 6 1 0 0 0 UIParent 1313.7 -96.0 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 0 0 UIParent 18.5 -1016.2 -1 #'$&%$&h 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 0 0 UIParent 1862.7 -248.0 -1 #F$#%# 13 -1 0 8 8 UIParent -7.3 209.1 -1 ##$#%#&% 14 -1 0 8 8 UIParent -9.8 239.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 244.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##$# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
                s53 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -460.8 -534.9 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 0 0 UIParent 1761.8 -13.0 -1 ##$#%#&3(')( 6 1 0 2 8 BuffFrame -15.0 -4.0 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 6 6 UIParent 19.0 15.0 -1 #&$)$$%%&# 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 0 0 UIParent 2289.0 -256.5 -1 #F$#%# 13 -1 0 8 8 UIParent 0.0 247.4 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 283.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##$# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
            },
            p1440 = {
                s64 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 903.0 -912.5 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -460.8 -534.9 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 8 2 DebuffFrame 15.0 4.0 -1 ##$#%#&3(')( 6 1 0 0 0 UIParent 1332.5 -94.0 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 0 0 UIParent 17.4 -1032.0 -1 #&$s%$&Z 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 0 0 UIParent 1862.7 -248.0 -1 #F$#%# 13 -1 0 8 8 UIParent -7.3 209.1 -1 ##$#%#&% 14 -1 0 8 8 UIParent -9.8 239.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 244.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##$# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
                s53 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -460.8 -534.9 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 0 0 UIParent 1804.5 -10.0 -1 ##$#%#&3(')( 6 1 0 2 8 BuffFrame -15.0 -4.0 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 6 6 UIParent 19.0 15.0 -1 #&$)$$%%&# 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 0 0 UIParent 2289.0 -256.5 -1 #F$#%# 13 -1 0 8 8 UIParent 0.0 247.4 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 283.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##$# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
            },
        },
    },
    {
        name        = "Shadow Lily",
        author      = "Lily",
        description = "The damage dealer cut of Midnight Lily. A focused, low-clutter layout that keeps your rotation and cooldowns front and center.",
        tags        = { "Dark Theme", "DPS", "Tank", "Performance", "Minimal" },
        image       = "Interface\\AddOns\\EllesmereUI\\media\\profiles\\midnightlilydps.png",
        -- EUI profile import strings. The scale variant closest to the user's UI
        -- scale is auto-selected;
        import = {
            p1080 = {
                s64 = "",
                s53 = "",
            },
            p1440 = {
                s64 = "",
                s53 = "",
            },
        },
        -- Blizzard Edit Mode layout strings (shown in a copy popup), same keying.
        editMode = {
            p1080 = {
                s64 = "",
                s53 = "",
            },
            p1440 = {
                s64 = "",
                s53 = "",
            },
        },
    },
    {
        name        = "Eternal Horizon",
        author      = "Trenchy",
        description = "A bright, minimalist layout with a clean aesthetic. Crafted for any role with clear information and a calm but focused feel.",
        tags        = { "Class Colored", "DPS", "Tank", "Minimal", "Performance" },
        image       = "Interface\\AddOns\\EllesmereUI\\media\\profiles\\eternalhorizon.png",
        -- EUI profile import strings. The scale variant closest to the user's UI
        -- scale is auto-selected;
        import = {
            p1080 = {
                s64 = "",
                s53 = "",
            },
            p1440 = {
                s64 = "!EUI_S3xAZTTrw7(xXF5TQ79dsVeRKe5tAXBvIS1iPKjzQPkxqKqI4AsaoaG2wXv(VFpB9gw4IShpjEKsLYsKyP7tF2pN(P)8pwhMSkRjf(LjjzBYVEw6YSIrhhh(d)y94K6zvzzfVQWlmCK1h83l8JIh9d)bE3npSod(N72SCjEhFiRQoVSOiaU8WK5P0J2ZpztXYYzV)NsFOCtd8jJtslMTOSQM)27kNTP(S06MBtRGpjoPjT6(SM6i(BWRV8U7QZA(TcCCeMuNppdUStF7n382lmF9VcFnmQ88so78lE3MM8L5npy)aJtwVm9HSk7N4r(hps9JNF0(889LbipmDFb8N5(cgD8KGGGWGOrrtIMAEdbj382lTh(Eb8LooCKFqyiozcsw7(k8gN88p1uLEYSgGsF6MMMYIVS5Z4KlsZlo1L2hMaFGV9dEi6uNzbVieqlcZklxoV8Jf4kTEDfNcxD67oBzAD9vz1LBQML94Ft0inY(5RNqo0fVWJNQ)jyIzzik5Qx)YxDJ9crR5kmFMstNB3a8HotLwtZh)0aiymVtpcckk3HkjmLOZxw(Xmh5Q(edoWv3EwbTjlwV4hpfHwydpSf24jJnlSHj)0ZFHZ6ABH9)a5uhL8X85nlUiTz2cuHuRL06(zxBP3YOSYAUdS8kfo99qS)6wR(AHfwF2IS87x0OgHAbj1JNL3wViTOPC1PLBkMx)zCQfNKoFEjj857L88LlZQxLvL9ZVwuEKYAGhNSEt9IS5NTPgU)ZkxwISlEGsApGy6LClAsyeAtWl5E43NeGkX8sQGFF64asCpkPEr5hpDz(V)7VEgOx6EGU7pkzbmUxIJ9BY(uZMQSBa7ffOswG8bA7VSSohvJHddA5oGEXpueen9yVy1p4A6KKQSLxwMx0atRZE(BU55x9JarFDRpXl5tfh5nY3)4i2cf8qJLhQxy8X6Nz8b)q9JLhkSG832KTj76M0MnefehXt9poe0VmAsy4y)d8HdMfWPBuC40qVqp9i3xE4hfp9lyOl2QbkXe9GDmqFomIkm3Cwsuuxu1lsaokkApEOkzsCDYpGgz22F4huWxLj7yzGfgIRBFDMSO6O9FYQTSqCL((DiG9zmx9g8ddj69yVXr(trpQoerGqVO2UsmnbyylMLXw6nZcW7hVi)OjJrP6d5DeFS3OGiVOy)OSJgrYBXjxM1y)c8ypAKFoSxaXDeNCv2AZtmAktv4FoqXm4bI6QMk67(56mYhesJhOVcwnu(R8853N9Ouec68aFtb9cvPnzVT4mX)NxqAGxa(TIM3ZlU)KI8vPKQp8fdkYjnWNwwnpR668FpRGu3gNCRrJ6jlrn8Kk5yNbkD9(hJFd8swxvo7Lll)yNzhyHq(k2pF6j5LuNTmBwd8UbRbwEobuPn1zKc90Q5NdUYJxampGVqRvV94fEA)RnPvzOjazITQeEmLqGbxd2hoz5sC66RhjK9azkz96UU5HLzinZ38U6z1IjA2Mw8joSC41)pklxverc(OTrzMBwtrJAbJJ1g1gl)EfmCaMeBBxFb2fdrRCUw3ct(qE9RaoHxbugGtajPbj3soYFjyVg(OcCA4PVW3u(8ISvpGxON4K4Fh9yHIgAAYT3)8I0BxMnhUGXjfBwDv5hRzIkyKL4OonBrEb(9WBczcViDwvjs3Wpkm59zpCl89VLcYcJIImOppVgFS3aSWn5RXL(Xjz8BcxeNKabZ927UkTqevK5sS6X9IYIgB6n7mX9ItfcDgEmly6assmtelzrCCU7Ndet5YpM(qnYMXrfrmGAI4fGBraxooHJuRaVP8gYLBMWScjk4GMKN8O1GyWRdmOwIJ(TiPKV27Rk)455vGGdkcdIJzWdhIRCcs)jUF5bmvlPItJFJjXmfgC7k9Euvqf8WQVc9sIxo0dKDpRBT29BmXfDglDDML0jQOeMmOpAxA9szQbZJCZI8zVViRUgdRhyxe9HRUnTbPPwlnGhHeb(A8LamfazB96S50yFgsM3VvE)KzlHx5nlQk3C)cCO4lRHaRW8Scwtbhu0RihGvCMTy8iRzO8SIdt9BOdQti3t9PPoWR(ECXH1IP01Jlm)Q9ctKnhmZmqAJzf4)ilSW8b6PlFzIMmMGASTGxlABbPLUS5JbPxB7mJyfw4SrPzs5Qnnpgjlw8RtTOQxR71KvVpiqJdVQZ(LdEsxxUmhxdvRUSkMaA8mXMHs4eWLNOeuZEfqvEJTAhJ5PwItEjLv5GOcB5dMnlG)(3brU0Le)P2yHf3MplpWlqCgGq9LPv)sED(TuoEGrFbkMYJEM43xum9sja2qKN1r5NZ7uuigBpxTfXJr1jVTy5dVUOMCWISs68y)niMexltedfOEMeKeUBIwdUcqcOFgxUbDbAZNRZYMJ84IfnEAATwyDTkpfCca6j7oIKezFFq7odWs)K5fs67BV5LWKIYISNSTO8h57kBlCSHHEbH(JjwRHm0yImB)8gCpTanbRyrtoeo035MFqRMwXf1V1N2RgFLnf1nTzU(7Hwn73faLVtT8dDBHo01vRHnM21r0TylLsH2t2s3lBPhQu7tgzFYiRuJbouUV5bWjb9)DKr2WNcG7RsaC7HfuIu)v2OzuYVEPK97VqRL9NaIiU4NfHJ6nW6yjJmUXIALjAxBNCEb7pHEDI9)vV9Qx)pE7BU5KFAlr6gl1(SWdRy)GzEJZXZZlOq5ZQ(6qX(w7FHDXtEYdJN8W47PSe)VNW45eT9xQue)9Nhg(sfzh7pkEsafA5F2ZxSLzTVTjmMeP3RegVh(B0LW)v25dUja5M00kj5s2SFQQLDRA5tzpMIAJtX(FLlozyY7Qt)a1ved6TB3sw(xq7rFpuYYbln3q2Huv)0Q8zhAUQo0szYvZE3LYCQPKFpQYzoyMV7RoN9vR3(Q9zFfQSD6K7jIL9ZCu)Md7KcwtxmsDC4twKuPi7qRNj5b6)jt1Ausf2nhp1Tmhs3Y8KbPVt7HMNSfX90ZGgX)tTbjNMx)jBspwBs099FsBsp1cNpMw48jJspzu6wPHUB3y3FxeG0FnnkzVNzEQQHBTQHukoPDk2tvC7PkU9uf3(oCtz89xf3EQNEu7sTVSnLXEuJT)D0tpdTRF)cnv)TUDvMKCr(SQYdOxBu7X2E2tz93Ds29SlxggsdD)HDm08F4DR3H0sWT3Yrw5PNGheN9wDRebOATQN2JNU7XZNQw6FUQw6JRjD(VMKa89GJe9yWCRDSZFIYo9w2tph6E(ClkZBxArP5HDRuQp1mQ7rIPPl8)ivkngcS9(NSnR2cSeWT8u(5FS5N))41momzz2DpvY4dcGf(VgdZFp0dthcSl8NiJYB3s6H3CThu7l9xXSZJyluKd8n1byJI0WvKcgmye2Zca)aB7eWZfLCB6942I96YQgeuk4DGd8HioJCY85NL2KDFzfbEqiyeD)fLFi7nLxVi)UggbpGpdUOBYBwMzH1jXQh8nvPZEpcCk6NWVKxVjDjbgoF(ZfEtgfhf8dfXtdN8d)XB(CHFKFO3KFOWZFYeFVF4p(m(Ff(XtIJg9dW3g5fnM(3jHXWvf4h5fU7)1pmyCa8Ag(FXNe8CgnD0y45cVgFCmeghIV1qVGrtL)fUQjJ99I1dTO4y4wXbzyq8i4R9d8Nmw(K4PrEWNepEe9VJ9c9hZ3jq9gLCZISNDs1kGc3DMtK8tM)HSceIvE2LvzR)tkHaNlXjZZAsNT4QS07HrmWHXGwgWFCoJeukMP8SAA2t8ikgmemeZqwsVKZklQ3ScVdKhDkcwsBw)M0vzDPhehO(7zG26g4zhLqe123Un9EOB1BCYlZsRE2ZlwGGXYkyU8OhgEbjVUjB1ZUoR5z4d9rnEMK83Zsxd0KN9)(SBQYlEFw3b0UNymMKDliiEnizFBkIWnltxxtqAf8ni(g9ZRVVkDE2RlMNplTrHPDWI0vziav96I3wKbRRi0CgKKdtSLzFiBjQ)XG8NcUgTPQkRy2dSu(pweqI0qKIfbbJHFd8hSiWNeXOpleePzGaDkP4O7qK1kHQQUmVOiBosxre6IMuQpNhN3KVMWUl9DidF5oGxbozXhan(FDbQnKHrplgsEOJo9ZVWNrVr8V5hN6V7B5rX)HLo0HbOf7nw9)omB41aAnNN9SxwwohEJEjxwvExwncn20FkIypdh3WB4I86zzWIzrw5g67)BBYQvJVXjcoXPL4op7U0nlB41sgK8e99pF16MhebsqiLPHmKT9YYLZjv55f46ptAzyaKHnRXggIwG2eDTVbgrN(WZ)060cCAOP2OzgW6W8Yv5)oIyFWZbUAzj2WVbu9mwECUAXIw3bM4nR0GLgnrQvGcRc1whfZWn7Nk8chJbIOq91Xi(zZq8lqfRYwM2K)HmgJybvZm8GJFVs2HmkY0T)EAvHgW6ObIGBzkBG494BBY9IhAwKp7M8veykRatTLBQV5JL0NkGI3T))quH7dzTbQKrhZtdebDTWpxsOjoPE9Y8MRxIq1SlgfY16HUl5xLTxbkOvjihfdkuHKCXBvdarKGEYViTUPZtwEWMTApH44Wkygb3GLvZYQVCwdSEuhKC6jxrKz67oLu)iWemI8Au(qObzepEXDUFabjOc2RrqyiCFmvYzGIupCW6aVGEmy1vL9H8SpYmwniv(sMI3h04Pgg07wGln6EqnecaFs)nWgNxbMZCMcuiU0uG)ncDJfOmFEwAZI6xxqEjP22h53xG4zz2NqKQxGqCynOut)TWrqEgtSjNwLL(Eet05NJ(YFz6Ag0phLCxfySKXFn)yP5iPHa(aSgf8tLOilQYY0CHOmOWAqsSZZMx4Zso1Imp4MdTqyOp)eeFnozyPjejZMNUSSaKNqZNJfio8xlMgmIqGvVPEW)Jpv139BfErbhti6Z4WOOPe700K07Ul)tw0c2w1jZqLW8cRINcSeXFmogygGtWBMruTqh(sGPCAYp)MZF(vVJznH5MEm7uRiMY1cejboeesD5fC5xPvCIXXNfL(51Za9Af3FnkcXqfPGaQgwrKW3sIDa5kGOs4Oiihi0zW2NE5)SYvRtRYUOCoEGk8M3(MNJ0UM8zV3S)JaVXSenj87SSAvAdScC5ZVcbfB(E0UYJWBkeTr7xY5zlBsreRdTEWi3n(6xM1Kn)I8LlZRZGqjMtkq4vRZjba8Vb1oGPaTsgI0WqIp4rFIx4NjOeOaHtvW9Bp4x9IMIoMJEqq45lDDXFUG87FAmEDHbyia4MhTayQapZXd(GOOXFUioaFc(GQpogi(MtMEK3OJaZb76Pq3X4eyuBUJEFKHwxW2NaWJmCKFci6AEKtJGzbcr6GygeLGN)uiydppmIiCgZx)Nl26LHt4j7d1dNoTimb4RyRpFACuv(ruldb6TmIyYAKyLJbjnaZm8PlNBKwbhfD4EiEKwOORwoITcyu)gY8IoI1J4pBNqBk61rLOde4IqHshiShJNynyXNIXaH1206f)uEXUFW48eKCaBTneMRsaACw6YMfxMbw8kAGOJbv7KgOMY141rKdGrKuwXNwjOPddivcEkmpVED2sb4LrynwJQ0mSR(ce4lNV8H3C5zOoe4oMb2Kbs)pd(Ha2MR2SUjhCutdMP9z4N8bGfeW0HIJnhKlfe(lxtBUMoFvG69PCzG4cGPOqlUPCnO3HXApqVu6MQ0ZrqSgD2dVen(McJ88vRlRaLT0zvboLVMaNsY61uims8yYG4S047py8Ue0VGzWneOGGdArrjVgN33Lol7FEY85VTO(FALGJ)5QS55P)t6s)NGrmGXS(JPpC8n3GeVaWePqob2autMczDpYNwMu4KS4Il)HiwIGRZi)Ua7PGf0vjxliFAysvA(8lsREVGb3(cSVsRu3BTpq9skG3RdA(cMsT5Q2j)nWn3MgVZ7bTxBwUSx5HN2mekZPZ6J24vnb11gHu(GCqTjDbpqGfliSYtUhIdxZ9nHXBqY844yJlIEtya1feTzzdnHN9bfb1yWFJv5egKBXxGBHW7Udtrfdx50OimrZ7dXenhpSEyK818YzaOL9gZxIW0EeB2cNax7)cdC6IYBTfpXymJ7YYQH7y6Wkc4nSOS7CHOpzau5tDbPcuus82pKvTm9bXzKJfq3BrEZTLFIym)1cpfS7GSyKidlOHJjy(ywt5q769O5OphxzkfiZRzkqV4H4JlBAkxrdXTkKcCAi351nqeJ7hIlkhwtOgbLggLgt(L2JgjJ4ghJbWsrJAYjNxxa(KCBkE(kXl)EbekwZhbj0Vry(CCqKVF4OXbJNcbkYkhnkJjKKN7q9XUtjleBwZm7OmfyjSuMYCTeZO9Z31u4iF8iajoy84i)X0r9epC77ZncGGM03)Q0AxbWyZY6etaj8PSa4u2SzUIsaZIJ(hhDtrkTVAJz8eXxFpOZ)GRJeHhTSsFjYtI)btPKoVYSyYueYmcBCHgrMJwaWyKOS6mcD03PufqyvVY2O9mAqzVGb(rwR9C(TNXXS3NPiGOPSJCj6kHdrJNt48F3dCiciTGwBEiHgGuyt(1b91mQ1qG)U7PqXe(HLFhMepW8lUOPnnJHbBBNHFK0IG6ybIEK86aFOqGhxe0tCMwppbM)IdiAbSq)OrJ8dcgnjaDlxX8YSXOSgNFGUyqUebhsRC9vOh44gFoJOdUdr0q(Duch)CodegY5Po4JU5ajAKivqIx2siWVZPurT02jzfHJmPRWYLviCe(grnF48OpwM2g4mQxaHmqo(NkXZYaxrzpJIak)vcUgYNZegpWyPehEqJieY(yZzbUhdYeeRHLVvyqWyDFGjG6I5W(jNw1wxhs3Ic2oOaVxU8CYrokI3aElB7Q)W1Pd9jPIK3rXHVoQ9r6eY5t(hGKpnVnWMsPPspoNgBs(vKXhe)aEGoUhR6WhdenlfQwijFB1lACbKIeYiostaFhhz4C1qMm1odZP(4wB)cHqS6Z57XjfzBAQsxAoPc2clbqSFpEUia))U18aZjTMhlDVq8iRRFtwA1bWjcgvqNq4dHoNZfNrjRs)KWnWNExUmMo8SCQtOha5nks6a)wTmL(sq)uZcyzNdiavpP8(Xbf(5upWNIfCAdDnOyzxcKbmRFNxUbcKsEVg)LB7UoprDdKdvVYbQG8TTgOkfS6vXil9iMu6gcg(z2tBxHBfZSVHbqPcsHJdiXaI9fTM(6ckcyo7xCCvgZ(IsFmsekqy75NpeLLeHewYfPKbun4yyw2kiTDZKf46yTje1Xg5Zjwj(fRWlsbelz0lqf)l6oEFrqAuKgActJJ)FI0)0goDmlgsljz4zD8zW1yiPMrSQKpJwB0Kn2l91)IQqiHwIbwCyaZhXW0Nt9YTGUzSBIjEOxaVYDFHMy8BDSXyOdQVqGLFvoqC05PJ5vClND9duCP9k35XBSBIClyO1IONrSOLVLQ3QK(ejrj4j3KoqNFtc0PVv(DLfEwSG1DlkNSYBF)hQqgNKq7M7MuZXIF960z6tFjiG6z7LlNT98wz49ikUs3qb39izkBQw4YuPPGsUDv(6S5h9rW((rFWVhphCC8ecPXX5BJdKwPH(sjF2GjzJAslEEp0ks7it0EUPcmxzm2wBNjyyRC18kv2xubisEbkYdQOKjQg6DCX7FtzlRxgVgPQzysIbgpKRHz0hsndJTvLP0NlMk5OVb1uWhjKClzhMsHr0QRScN1u8JuNJqJtQsRYE(Y8g6mIIdkIpUKTpAFOqvnH0j)kfwl7VkWcEBDz1TSlrOz9Su6G9DrzDtUvEbhzSCWN3qCcxzBoDmLYhyoGCNYCGErG1T6fjKahTB7Mp1Ythh7oEog9mjzrIdHNJNHZnEbNZraEO5P9N14Saj3xJ5GaelTWQlFD2pTYLuG8mudhKyJwbqCnWyXUd3lEIlrjhF2mYBAn4eH(4y50I9SCsYQ8I8BlRnUupDI58r1pKZ2gUUeXv9q6zbLrqiAZhYQi)mzMS3C5zuTfPpcu9qjC0Skq8jtgfm13lkEsSVLD3E(yIxZ9Q5kG7SgR0TO30hJzsTOfKLqMkNfCkhsTweCSWUdgg81hyxm9ZtxLEF2fzG3(0PtBY8v4A00KBvvh1kjTrG7NnZwqug8e46nBwDlt9GRVS89RsREF9NbgDWNaW90cvvBr342lv42LsNBTF7Ijsc)uaZ82m4eoDssirMMLaVriKitviPB8e(Koh9hlldhX4HtOkUN61zO3iwUmRRAaVPbO)ux)eokeCA16TcpaDTpP3Q9TGnhK73UBXBS5m6nj5uzz27A)d6DOaIWvbN2CuINkT6f5lxALyD69ABhwr0FPcKGqPLxHoqjNlHCnk)G5SaZGTRbGg4RO7BcvZbtg)up1tPV1ee3OJzjR4KfZPPVtPR8Xd3pGZJl6kpGa3C4RC30uEvMBnMRZwEhpYzEkwpgpwOpGh3tXNUYVnubd2TukjeMZIB3fGzS8JSaYCy8PMRKojWeY8QluNJy0jxgs(9s(yEXCSYVBkAuN4K6vRDoDgl3E9NPMIB2MQZVGonp5tr21Yj7S0ep(EST7pv4njcl4U6qUN19USC27Pgztd378nOqNE)jb)WF069Wh1NpM3dq4327rux7kYyLStQ7kCfm5LsGmBxLiK9JzWqKYDWtBp4UmooqEiqlIipf43ICG3z)rsAlaxrwNTC5RYRBWUpfRyUIDFmgVoECTsbRBZEto)Z6G41DID3J(aJNpC092MFCDZgH8fo(o91zRWHuN(tQLu(W6d78QxxCvAoDWjInQNMesPkGtYeommNmUkltSQqUiSuhn4o17ZsHKQatrljflu7FHhAPQtQp(T6EyEQpHQXgqbE2kXpPUI4q5TyGcnpOoag1tVZ3uCFgF8sYKuLMmK8HlpSwSw6qrJ7(tT6GkjRxugx5MOb1tKw58AdPxGlzDS1Nzglw8H0JXQS18OSxYspC548cps3NNDtjEKmd)Tvv6daNPP(2qnnbBHklWT19R4anTqw)XXb(qLb2nRxCvAJufhrmZ1eK3OOjt8dI8Ng6Xhueuzx65JjpPCV6)apuO9JTDprDSnFrAb4McLqsWJ85RGjT9rwV5mevDkWZlV79jvprXIO8k(L8egNSbcra4ifTTpMrbEGOsDb87IFNF04GG43nn2tEGh55)fCoEFKFRtbCKGdXNr0tU5YmNRWYXK9Pij5VViR41fPC7uYoxHn(R8j4LOSMjNZYCJz23XXzysQyUSoNo8rvzFKufDQsrn5(gM3vq34PK8T7jQSRpGb4bflA8toLVRjF5ADAktQ0dKxVDoQA3UJ6x8vkhmDpKtTaTEoObSZKPrk1qVYR9ev7L2hCiWTTRA42YpbYjszUBQcTRdy6xdtCan0ykfNMOeyqka2fVaf12CcPlS9PfmPHbDzOff0En4L6tPCmf98jrnO2rm1DmxiNEoJNDDWBIq9VP0KgKEpeOBJbua9s0EkVQUyjb21Dph7)q7H9Vj1fTtPY00pZAC)ogyzZJIqxFJcfPVdhCUrJulfspgIJFKNGYw8u95D4BnNdVuOn125(c7tGUNGXDGZ9J66WAlgD9MNwyoTYT0Wh70IePYZD9H5oFQol2x41d5sLGdSxb(vUl3yngwhzZWhSzn1nrV8SZVb9PSdWFXLnEOdfBh9fgLd2Kcoarw5Gw18Jx1qh5jUX0Us56Uub(HuwS3AgAlu1wBG0J5YPxV58uxcPTT4TOByCYpZ2MmX2ilxrjSMDANdHE9HEtSm)3)90Q50flAhSjH9P4JvSBlB7QTvxMVEyQD1tOTbc(3aKxNd6AzABDKX3wwUFdpUQfoIcdAqJrDRTEB5(bJKOTtYUbskccgnOY(x4XOSyV1ioKcdBDnTmOaJZUQk6rx3W6iOgBFVvsqlh7JsI(xC3YzNpxTySi3uuXYPBR6ZCQV6UDXqCr8rRdPJoG2K92BJxJVgIyCuc5rwFM3BjhyeCnJ6T4VcBpZv3tV2FEKM0h2ITJM8buI1RXHow1DL1CnMAjxgk5cGvyzxucxrQhVD8UI594Bu3ZLfYqUzQ(MsAtkWfqV7H5hNI6(et3Ul29yqNmIVfH1TL3exd72UPkw1hy0OBHBSmqG3ZZbVdmUfgMmBbwNxJVXDdca0DAQEmiuGhm64sRkCaQcEygZP4LR)y(6mv1Ti9n9fmqVoo5eHGujXRYwLxOZyiz7h7OA4nQ(gvClS5oXy7Wc4s2NPw9K3fCdeKGWK02TasZ2udfHtljUdqbQQS78WMxOoTb7N8S3waoEzf6WlWX(pYuRUU6moPetyZvPf3NjvOJtfFVHo0vpJJq(bRLb8dCB(O4yfAl(mA0i4DCm9Z4rbt9MkDWXU8AFh6BCuEyRUrsMi94jMAz)26WT0QRjAXy)RfKUbS(H2SyoPfFOGkWUR0(MC6TNw8S6OACUdoiP2phNk06M7oZ(WRB7BH1aq40GHp3jbaR0ak(TWSPrhpcZJ(WQP6j8Yw1kQBuhoI2TfoJskY(qwv7KpW6xavkV7D3Jvf(DZa)Kf7ZWN(Q85ZZkE2zNdwPnCCs9vZRFjEl8w9zaXhlEhD2EI8MgnDmvY52wsfI9xAmuG(N(u56ep9(MkM(tI1aQH7QS5rPyEaIPRUM(vJXPg)xm1UcwbkE360kmAjxoqYWXGGJs3u3yYZFN8UqTsw)AJb5CEZJ8mDcDEgWY8SWobVnCim2b8OZYr70vTdfRT6(sz3M3nNepsFc5kX5AXRFhL0r9P8iQvMs2HQ5Hl8t7W1ep3m6PhCN04pulwGkQ3RS9mCSFNsntTetK2HaPgud1pJ4gzGZ4UU7SLoAX4QGOFV)OOCFWMwhY18ARDwe1VGhDqzes60LH8O1jXqChlyKtSt6S0GZyHqUQSH6r)xLTCn3KQyFVnp7ujpgi0daCBRZMrD5qmE0Lnjzv6615f3tLovBiq2w5ZWh3PesXk5FE2CAVZq)1uYFe4cszQ(0K7Him7RsDGgCUDJOUbbxqelfbJOq5Eg2EFp7)t29jp788pKxK9Sl3uTUSo7)lELRWTHCCYjNDZR)fAJiJVgR9sd3igVOQC1zNFXlW85JTmr2YSz4wiMNECrcds8Jg9FHZAVriKd(FtR18ooRkdc9PGBABPbNexOXEDb9FjzuN2b6QS6YnvZY01dYS1uMMSKAaVzVhIKr4P5UW7NKpNkdj2a0fZEaVgU1Q9tUF28tX47sROpMfhq0gkDEEwrJXnYXs5b0fw36ozlyTCNZ5zlL4hmmqLOOjDPAFZYs0u36ssOzZL6jOZxTASCEEf6xN9jIVzEtv0HlKVPmzyFJHL)3TRhrSwINDeHGdouinoUnpq7iyUFPjNKurSiTOiBjUiGlPrj3LVCjARWN28oMMPG7zLnfy)CW4gHxYdfhfmzc1YhYpWfDa1i9igsjm3nW9WaFH0cMTAriNfhnTlMr6czjg3e6ZEpUtFRvlWC2c(TIJIuo7Z5RqAqVRveB29zI9Mx5n0mKIiDpMqZXEVNGPbYfu97KDNLHXORb39EVa0cQ3bBWvgYI13D0PqMI8JaaHZ(ivMb4QhnJPza24gBazvNnaT1q0KwoKesEFYafXlp7CLufpR0SHmT1qoa6hZcA9yvpmd3nt)1cWmFNUVFMIYY4gHLLFE(Q14wkb8CdcMLcEtPCGxl0pgI5eVxMxv9uXFhhwtO2TGxau92R(EPlG22X8nJIsJHhg1PsC303xzJ4nPrhhgLTyF7TwObWTO(EYvbdeTaLwjHBLxTS2v3KIKPjGMT3FZISv4wDPDdV44wbV3qfScr1vn9ORaUofcqWuS26dms(JXwCL7tiQf(CutY630QfOTNO5AzUFQZrmD(NoCjo)iYps1s6uYP9qcSB9Aq(q10J4pCgvsOkHwGGbyWIb6U9t274rDh7(Mh3LZA4UD2qjyHmMOICDucH05zOZtt5Cp3JIdNBuR5PYmq)sLkQHm37CIDzBpc3EPQR3ykrlO6rTAy)(3pq7zQ4YbDUX4DBlQcsnBX2Oit5SHh6ZWUr(nIAY7Xj3NvKj7dVTpBB1aSPnvLylFHpd2sblBQ(l8iXN7)jimLQ8vGphFB1riWLfJGjKMXH0o0XtchTdGsEyW3yl6RDLyNQhaEY5curc2lzHhLkdPayzeEu967EtPYNpAW6QhPpjvxR8gDliNZo0TGGvHgzBuJRVfkC6xXnW9wA6(IU(9POfSu5WQd6zJy3JKVo7WDuN0UvJvVxjw9b1VGBKaf58sGxjpDPGLuUkOgqShrDa9TB0jQe31En0R(gBodrRvV6C06LiDLwAAiV72H2LHvL46hbXsZ7FBBvrDDa(X0pEkDxuq04wIPjdBxoQjOTDBXXDp7yvKGm(QKHkwvNDD7B7WIXJyy4cJqcaXeTGdScH0nTv3o(nr4sw(DnpFjdHR2QmQdtoV8Jcenbpf39MdNn55iJuiUAlPrcD9ezgC6ziw6QNq86tLHBRc2jYUHv5I(k1YNoRNp3i2kuOPRnwxEESAeJTAGvlpS)L0LBYQRhLW(C76kxl)Tat1cGCIvv7ULGJ9stIz8XtkpvRRJxY(6WKlWIiJ6GUA49bpa2KwnppTaJI6vc8EXrVWUhdgDdO4TgqtZePWcZjp4rFjzL(KC7oBAWUuiLtJW7BD(AvVDtbjIytibVPVi)dywmCcgqaWv(ZG70Q37AR9xpKL4V7I1gTuXR765XXHJv2lypSbvtvBkYQVohH2pUA(ks6RRklUBJG8B82)KfdMIdqBufvPt3wgrhz8aPryc(qeSBJuaZVbzy1xNxQN381mSjMjjLLZmHn4KIy78J0FCFuAu6Z7XwHgelBZUWOruKIghjHWa5KDAHvzNTGqPiQow4V4hNSoRQoVUb)gzdACr6N4mBlq(0OK8I1BAEBXnLyhTgrDIVQoxw55bSKTaHwUkDVkaFsAdwDq2qWVuMdSDACvBcwDWLL3MUCybdb8)UoRPbtdnLsh81RIf3SzP4nzdxG614ob3EZKqYEbuMGfaF(uepIPDV7TMgOqQajLSJzvLlxYPjhZresFWEcv29hZb2005zNNTm9bguB0EVO6QluR(isxjcxuP1AqArLRPiFqn)OrJcJgpoMqmQdjxtEErHhpf)Xpy8icikr0QLHZAAB6i9jldhsX2FLGv2kOvurDzyXt8phHnVL10UTYqwTYgeTykiPDCsUqqUUPkR4(MfCcPa3h30Se4LiSc1E9Mxf11AXEylW(kJMA(QHnbaIsF(qBRdQbRFBbTb74pVlNmVRvX3KzVqW5(f3IJ45lGEpMXxwpW6kVryXu4O9VLX7qh6eocavhi8a3KUATKaJ4K)NxL8)CXZGVe8jHxASQHQvBYZvPqYfnxLIqBb3)w5pr(tDBAtZYmiGeKjQVZUpNptNM45c(iAHTTrjQp0PVkcLmgQ2hmKaFD3gI3rU39jPYU2m0BbZoz0QkX8Ub)GpYn60GA22CaVLkWD7yhLjaH8Il)PF(63DYBo)DxDYRphxjx3cQGpYFQhknnjEeilsaeIbRGpYZBkkP6hegpkaHvqwX6gge7plD5S3UMGwwyj5U8Q6MR2uCEzbUtqWTiDfWu8I8LmEbfM8QSQskrA)cUPItXnH1Keq)YQ158oYAK5OyazTHX)dnliMIiYpb6nn1WE8SJE2jvzPplYh)cp7Xf8biEumBbIwNWcjUVXXyDHiBQbzuoLrGex(Tydpr74n46Xb8fPfBsxEY85sSX)RnzBY(mTdKaLj3GyU)IhG38nlQsxsWf03Gx8u5fVOS8UVPVBkJQZ2uvZij(q7CNoP)R38S2NBfg8Uwqw7E3NWDAYtIpYswKrgPZYRMr4WqRs2cHfv9EtVIRFNe4smjb0TGCkykBJssjqpGa0M4eSunBQ5KcooPcrM)SpzjXbMwP)o4fNm(fSjYn1zUqZKp4gbU7UNrq1YliU5MQ08LKQ17NHqFG94v)w95upk4b(ogRMrxuYs0Mb(W5b3lOF6o44IF1EW1(JmpNrNDU)uqlsptst1kaXkKm9oAmqbAE7YYY5l3uJ(D1AnZATE)0wfeeSBTvtJIdMoke0wX(gy5h4f5f5RsxtJeeGi4FVF2ASMgunaoTH2zRwvNRVIi4NCBtlZTXjBkOtoLS5C7cqaPGJ9nzaP7MaCepMSjEwv6DOVFKplDQ)aEsb1uCA6S3JVabiWreMfCz71fOjx2ha8j98pbSBWKqGHzgMrQbMrWbfwT79Gw0MFbpYkyNdPbnpMO3mHLWlRrEx2J2ZW3d)gE3S01yDQM)wGdxu8xwwnV(0miKv42bFTlxNvqNeXxKvS5TWVohCB6SLieQrrsGJsqJlUJNriwVbtNaosInFJqa5XhnnfFncs88rGNykduTPZapBxMjRzmi22zpOhoEk5c5OjHHJ9pqpqNggJTiAuC40qVqEBwJjVxrcjY9RlURKQauD6hYM)pklxrEgQCPa8k9FbHoJG4za6MnJIKIhG0oaVvjt3DSWJaffOR747I3FuDRVIT4xRDFcMReGO60bOre5hFGc1NlcAl8qq6NM)bA3NlKkU52xZBhFgwNrSpa3crc3ohM9mKl5YQSz54XvI6yJwg0wbKh4kgk4s8ajuiKcAHnNROR2ZPj0u6cw7lv6F9K(34Wa4RqDqSWtCtxd9seanbVDz5gPTGbMD(PLI8WoSEOxg4RqT2gkhlPk)WrXs2l(vk4FqlUYVJFhORSeTjkaCt6FE(D3LpdezPDbql7o9raWQut7JAhqA)NlYBEbEywiAhqrDW4udJ)jgBJO7yk40zCsjyjJrihbZbr5ygowLTAFRngm2yKe4zQbIdjvd(KYf6nI9JUbBFqFv)ywLazzAqwO95i7TmJdUzYP)TI9UBQEJTlXcygCzOLPcUAymutHiDGvlGWSNoqtJKrQPgSsXCd4LZqzLQRs2jYCiGaL66T2ZLDitCOIiOIS5U7S3lyw3KVGRsAWqmDttjP(ubfwACINfm0OUdSIuqixldOWDHxDPzjWz3vydpxNH1sg1QJXCJzTIzaWeaAp6yEsEfuWzeCx0JMeOHGbxPpb8uWSxVbL70nj53Y6CqqHOxSvhgmQSLS9rojddddZ6ypjW2KmVqHvYxAua5nfq8dc7NMjvcuNHFmQbt2l0ggtVK1yHrQw14bjEQvSEiBy)O9jANCX6Jey8Ihs86vegY)ceiUfyjsdJAmz3MxuZ(BVAjhBiijua)iBeQLXkr9SLPxcA2Yk1XX1iEkY5qusGKfgKYzFbmvRL61IWMpsgCTe20S8wAm0INSMnxqWrLumcI8iafr2xfT5rKLLFR4iH02sNKiMpXiHS13ROcJr0nU9JO9SGo9dkvBuAG8t8N3z5rikcK3zEewqFUIxrwPidWiATlqZkEuBbRdNAb(ikeR3wirErymby7XCEE9Aq)TfRe41j9nUI5OMnl92A9f0HqbmuSohK84ZbPwlMcnkeSQE)ckOGDRDuMswNEoeh)AGJhDk3LyV7hNTWVU7Ye0StZpZ(1sYDOakRVTpTADwTnMM0AK6RHWKu)O0iJ7ok2BdIQBB)H7LEBfie3G0ZKecvjMmT1YY9vGwCFG8(3sTDxdkC54OxUMwPL20Zl9NO7)jJ(vhaOtmVIgnCXdgienLDBvBqJa)YKy(0DsX0pGfpzesNvH8exCnf3qVkSlwBfuJVQk45HXmVw650tfhTFwcIDvQR3uIg3n0YzsSJwqe4(GR6SLMwylm3Jgk8bVncyW(FCWEKbUbYNMOzZvSt8(qbJwI9iJ8PDa3ZS)cG5K7AkLJfgUWMBjoBmDZYhoOlxd6CflX1RZs95FZaoXyBksB3PtER8XdhhxQcNCAnYoXkx7l6kuPH189NKW6Srr7baxZUywAFE4GH8FlZF1HFB3o4WrI1RTDmpbdyvGNsmS3l(bSt3tqF4q)tkah)OtPjeawvNApwzrrKNAzWPRFftnJbhVUbxsAULqDFvWJgtvB1naX9793IDpgsDpcazMc2Orl9ppglwFDTXyDOk5Oa8WvZZJlq70bRpxD0fBu2WIv06KSZ54gh2vLUaE(up0YHKgt78LkGVIKhK1Ei2IMBPALPCs20eTknyATsDdSexKmU5440xNahDQHJfWyEOXaIDVf6hh6MJ0pcdfi3wczBlgLee5UL8v7OY0GllFAYyos3yE6EIhdg4kDcoUPcF6P37GaEE4vQJ)ZC2gT1y1yPOUXLabv1w1C7tLffpGtWwc4rV)rVHyCRAc6(KWC8AmOzdjbAyOMcaaDgPFVliDwmFAlUm3eVyawrYpul3uv3Void1hmCid6LybqCn7ifjmi7zL5eWHgRwX3nmaf0kUQEJaDGGQiAnrq04GD)gGbAkxp(RHG65y6zOMdBWrcb8jUnZH4djNY5OJH1soROdeTuprQEqXSmCVyoEapkC8hUVCyH8H2AiCowaDPX69)zFXWzVXdOaJhcgKmwP3ZWK6TkFohfjCAagRwzCz6zGsUd3ifHdLCXtiSi3iNnu0s6NFBX1UblzZQFOjvenWJ64215HaUXf42TW2sJqt71d)TeX3wcgwsFPLFmgDat1oUR5ngkUglF80wtBNFoDEz3vQTOctrsHTneJqkRsTA7Vt7k3xy4tdNTcQq2m6QpCHS7jmkozWD791)Ye9uBHm5ClClPtU)0g)njSQoSI7mMk3qNgk5WsQW7vRYJiwk(irqPnY5GiZuaJ9lulSQknl(Itj8xwmxXGI4uWP6xxmhpr7WnzPeqt7C8(TmwmoQRbs7PBaY6XRD(iNiEa8uqz05XP15ANKKT)Khuwpnk3av7tQ5H(i1xQUNQr7(lxqA(bTfi79GoC4cS1kwoVjTXg6wX1jvP)VIX15MRu0aWGHVnORjTD)4a9ZRDv4Oqv23yNWMJqDaCyW0zW4sVbk6gceYayxU((IAKtxyROgBh7KvQfreEtIiZUhwDRTwhVlzF7uP61edj4YSvrb5CqYjkrhpU5T0kmYbQi1xHajBvJuTtNdFeq0nYYbZk9beIP)Jo2qF0Toht2UGhH1IHUeJdhmj7eLDvLoOyFhQyvdfU2HwqoU9BWEuqRguHn8BVPt6RujMcxyxv2bIqDBbF1FqNBPYH9fo4ws8yhNYC6Kfv5qm5(2wMYjwZdiZxTtxYwQl9UkrxVO3E3g)W4V8qjxRtji2AnP3z8PBjkuuTa3XNhyv7WqiCegzDA0MtXDphIkoLJ3amm0ajKuS5wadzYoK5XSzubd6ufcnH4sW6sy4XEXXXtgpYZJozJpKTAtWi)JN652PJ(Yi259WTE1NKwCCnDEhfNOWD)EELu04ydiihLWWq1po64joiqd(epYN2rOOC4(8qbrmo(EyY)yOI2hdZ4yA6uI8jicQmlpYpYbWBoGXNZ5tR1K2ZF6Kj85AgmP9dMEC0KGyVjEXHJWEGAFN)u7gQowFv73kUjmpGfEQd6mT7hql9cO1MXH4EbH3rNW4C6KyQnAdMmnoKoD927XPGwPFP898(fsQBr7spuwxR2ly85tB)Q(7YrVN9QO(0rU7g6zp7kXozMT)2oS)X9aTkOBt5WXapGNudwkOER3e3Yp93Ep90KA6Io0DdYEqox0NteCFVmK3A95nt7kdpqr0T7wnHY1B7pXTlzRwiK2Vg0(Fqop90hRb93Mz93SHBXJaRhT4ux7hHE)72xdYbbgz(yNQpnudV1tptmuXKF02o7P5)qPADeSUjBpI7Bx6SJk2(8Sg(8wgv6TkhFvAszTGFpnbdU)Xj7AIQT29RXJQ1yIe)sCl7(xJJC0H5jAN3ycKP3ABipyCD9hU1)(Bih3Gpv7h4b6bN2DCdVjW)Y65M9kpXGlH2mmQQ8r85hwoK56tDGDRJjNb2fxT)EZzG8eJQS0ED88vRBEWi0MAGCwgQ5irxtUi5kL9vSPF4CmaMKT6pCFbNm6xp8waE)D07TTtc9r85cOBVbXybMtVbzQM2JODwLJSFQuN64HXTAp2q47xNdDell01YCpA3z5acG)wDBAJUebQdi3c2VG(Q8wNIs01awxRL4z1M7lY0Z5FB7)iUvZjo7E7)iCVTt7foLd3AufXrGM14)TPzLGvbZOXkiwBPWrsLaq5q1VJMsWFN3EqeUpOFo3us7piCh(STKobQQ03cf(lDyldru7UAQ5yNk9Cie2RoNGh0gOXD7ezbjw7xtv529BBXJ3E6WkLR3mds39gZw2kkpYu7R9MEOScnqU28B5oc2iUVUGAQhERu2z32GiyVJ83U7ja0x89SJWS5saXfthy0BFI1xzBXZa9Q81zZLKSJTAGPF7nfmu7Kw)DF6xqQxFS9Hw3(S4q3xriyFy7Ra3Cw4X6kvoAtJZyVzP2s5qmD5b3HzcUYlhI60gHxqIPH6PJonHv7mi2tTro02OP)CZUF9V(263oZMfZQZq3v5uyijTtt41o)59KsCpctC6R6kdUDa3)YS0rQvej6jd4UvzXVZDAHITugKWJsA2Vn(FryTN3y969rODWKhsd911RcYXrcYjW8WAmatE70YLJE63phprD7o0bllJTnt7Z1ENnn4U2xnhqTQ3wx9nqIAoKeMaYfgdXDxl17wwtdbOxorZ(CIOn28XqqSDWPVoduWmx7nq1q1RzG9K6WnwRtPcLxEp9QzFfQrGjvt3h6UhmhElEXMZufZu6l1DT5o6dti6uA3bb4((Zn5))27AB522ij6Vs(bSlccsqs4NyIOIuzDReLJ38elijijetbWLe0YkU2)9TpD3ZGzaajTsIDf7I7dRvajahmtF)YPBeFW)g5JzB59qmKvQokLcqaUH)gDXA98F3stPUPgNST0W8puWo2CEAiJyu8KX2o8siWPDctUkyaIHtZc9xMy5lLEStYxOBGZdHK2sjrjY)paqdCsZB0sVIcrSBOSdB1h8g9HBRXBAZfetTUMUrLB3Svx2EqF8BbujCZBRNe2ys9BXWMatfCTLM1u67Vg1yqu8gcZJBGbuDKBk91T1dwMciVTEtDBfz4lnTWBRz2BfzeAxmDTiu3dXb5L085Bj2u7k)VT3IM170mt5p(I8LExcMAZTMnvlcT7qsBcejExB6f)bkdrbDut8FbnO9gtCu7zhAlTVuBHGYj3f1638nLlOwmiOzsG2O9QgZy3mafS1MGVEwG0W9vplq7o5nVyCp4Vy2E2CMZAqwBbW7n0c1BmXI)1QJInKlOgL2WE2pVG)Ado0E2VCg8SAjjS7z)686o8SGsYaJ5V5i)sxxQKcpqpcYJeuV0Y9dZEAmtIcudAhVEzcqrkpq(RFCEH0QVvifvTr6FdDaBbZXDhkJidz(GCFZrSJeklGg2m0x5bgGy9ca)WmvMzeWIuLuKVA9Jae58Eza09fZZNxa0xRVhyu3mGE30vgexIGs(b5VfeveM)3nEUaDZpbm6tmvnl)dpp765jc23f)e(caMTwwS4HSB4hq(6hVgqnjVCstww(WCm))Wfi3pi)sXTIOqMC7C05JdJFkl)27wVe)hyS9wO)wjpUyE2Dpl36W4LzLPZsU9pupwMN8yAzr(9RXYg1ga9PRsYXAGifEknzrr(ma3PYld575YSf0dKEAc1YILP3LUCz6ThI1eYCq5djWT5SK8zltb8AdyVKn50(DFp)CNipw8jo3ZIhksZZ(0SIS5mqjktFR0BYsMV6me4A5bka1PIlMGIMShXUuOxEDOtnB9keLyaxq0XKI4nCrFgf)4ZL0Un)wGdKFgNhab7a28JxU(KFBZPt4kAdMWMNKwhFqEqqqKoFL4lbuHcpl0xBllM)tVlhho8kdVdNvuEwA6TmoZQzuchThmz8vh92Zo(xpI3EbsVXpOpdEU3thP06opD5pnDr2YuAvnmEgkc2PMwyR(x5kgXlXXG3A3m7fEvFe8NbyaWaNTabTe(wSAxAY9c6u2Co)Gd5rk5vpViLrd7bXFsWBlDS6uaC2U8zD0m8S(zDL0fkNDEp4dwNFFArEUwnA(fuUW5cejh8it(eDEUA1tjpZSaaHQTO6TIv3CJ(mTCzszcDCE6Kdo(DNYJehVHTjGCLWbC2FzPEd0)wJHPlrKNqhaq6otTIxPyYTaeUJz4IvsFs9jlcGRlD8VVQciCKPFZoqQiUwrRpy(IgWGnPtfi(sRJpIXMorzGnsA8rHGSIzIbSrn0hSqUKmICKiC)aeNefFnDdRHaG(Xp8Omj8W0hT8j5txwK)NqacK7SSesg8ynfpPoV8H0LRonJenisp6tIqfTfEF7MRowGy1QJwwm8wcyA5JfZWdbIRi1aPRklEA2tPpVKKsiyqnm09o9FziThjNi52INOvkJrMKWNShtjb9RaNVi37AaYDl)WmruJ(WNtIYszCTLL6GV6O4vptIPlkzH20J(207m3KWhg6bK5RPfiJQKsjV2n()6Ff70oIba(iDWSJg3IhAeOD3)qw(rCDglJyJRVxASjnx(aUJgFZnPlaeCsYvR(VVyz6hjzzNUEEjoABV)VT44V7VppyP6RvcxX1)r6nLzFmTAWbOy28nfajalLj6I(9hXlGRwVKO0MIXeZ0pKTq2IBzKnxbLZ6BUf3WAcT0CPii)EyEFe2dijfgfJLZtXcEKduBDvXcmthKu53equ17cpgz2COxWovS5hA17lljPLCQyHiFb9(DwHAEP74SBi46z74CDyCcDeMxAoNBcyNq(CfGDQrzrbtfgGucJtxNXVV8ykF2IKAJ1FGVPNSEvPyqgosOL)J(6hf0cuuTINYrycsKohF7UD0hSyvyT23FK(HAi70zXGIyGelsnaMv8t8RqDTHjO(DY2YUbAbmoPkwV4mYUlfsAyfG8C8M3cze2RcWAui5u(q63bGwdP)eBfIad9TV6Yc2TwLVvhqrrkkj(2izoLRxHhJ3SjW880FcB1vqcriJn4z5G0WbC(BDZ3T3UnAz97A7hwuwFjjA55F5HudWodZesNJzpeakqs8E2CYQmi4L7D8KfYarsU5dilbZxrYgyPOvKEw12IzAnHTt7M1x4zfmLSXzIcmqIX(SKx57WVw0o0HfljgQ5moAtKV6PdME68MD1gkzQOUH6Da0ANEJj(1cokp8Bm4ge8QWVIvdyjcS1h6FY4Ch7zLj8jvN42sgMFby(CdaLYphIFxzQB2kuKb5cbjFWbQc73XBTk2Ko5tevxozyTitwtmILusHdv8wrQpU1uB9sXSrEeIXpICKv1DTEsgWDLXtcDHIWFJ1cgCYs2sgxdINGtg8xGT7vBQgMsQzaMW2A3HSLsb9J60xeflLByZldldRDzb3bTm1ahVoGm8MFhCANLwyWSvJTcMJij2SJgQX(mZVJiM64wl)kIPbwsPJugTU7mliW114qhztsji4Th(LMmLLmftxahF2bt(pSbhsnkiyfkotaq)PiULLbrUEfXqR9DmC90apMtfUi(2CikCabY(CN79LwvbT1x)TOXHF5GYjb9hpRyQa1CdzVB2g1pRyOHKu)0yXbrYk9VsQCBtXFPOiqrsOfYAIDpRguTAFnQx2nkkmjRChcawR52IwRCh8Q6NNtoyQ1RHvstnHoeZRepNgKAkE5IdkpvgMCCwt3hdO7QINACSOGZQKpdfJ1OTQXWZ1DeBb7gR9uIHZYu2UEZQtuVvFxZuap9bYzAbjxatWjsZ6rY6aDBatF6kVFiFLQMXUYoGeFHc9JVuCENw8clrDJemwq4Oj6QKCgG69TuYSWFfpqSqcLBi7hd(1IIYhm8WQQwhUoPkUW93I4gvifX17O)0PgrH8ZEbJI6myyVWGWbsKuz5NTCzi)S2LBxJMfUT5G5qMqEsYkE4o00ChBLgUirqE315LK3A8SbcBWm0k2QiznDP17BZV8xNwE5LACYv6RmlJitHadmtn5B7NSo3AWsjzaWTOltxrhv2APMpjLaZiIU8S(Wu5s(2FAHYS7pGCkh(VM3td9ISMRmpVDZaistYVWS0NyzP0lfPQ3YIOwnDWftL4C8fc7(0lrLUJAM67QSrFU9DKfVBCC2WWSir5Y45LHchRTjKEtvUMtQPjHtk)OLjFZ6WHD4gvhUNq81f1VkahW06RF8rYeS08B1y5QMzBHcv3dD(T)IISvf5wH4K5jvbUIBdu74nGj98miGpJqLpBSiL(1SEt4y5eMajGjYqPXKEgLUEwR3jEDEwPfntp483FgtF7YruzZrlKVc7S1KQDLebTGnWgX2Q7qqf4XE45cShuVifDtthlAVEgnonypl1G(jB0kVp5Fo8csTCxS33yBmhEvRs(w39BMUB1vPJkwM9Nf5Lj8CjH(AvC160OuSFdJvddwgIMtHD9C6tzl059Jri7HyASzCfBdkTWrPOXGv5OV)tnMo2l(YZpzcROY1HPAog5yccruLMScJFlypuNxldMtrdsi3EWm97RJgygAovIOy6Fn282A)Sj(9aN3CDlTgQmh5AKTBpi151IJlBSyw5XIoj8fBNJL5FzK1gNnAqxnMbFhkfVXTA5B(4D26on5(SBQr1JqsjlASPHOC56GIR0uJffKJDmlp)sC4BDD2vn41tKSQCJPGi9YwsgJ5wUTgaVqiIFpcEbW)rXxmFUxLZQ2a(UC0jj0UxvNOJq19cIG9R62N7RZUMikiuI(e09IpzYHILCUlzMGZqu7y3H4(lyKOhZAmzxnhssNZHpbymk9bJysazQHsAiVAmjbmk(OjJpzYLRgeFW4th)RtUuS7PrSgKamZE9z2C4aMWrk2JlYqJW(j1gJaKp3W0sZwYozIWktNBOs47Knrpscle4WHLCEkV1S6ZxX)Vd56w0nehsLydVBttGBx9uREQcgOgBit8dQIeGoDXu9kvwqdBbSovAeOPVJCCq0PvmNFPMjk5vbrD5PkBNWOWU8KP9LqNnmiGZZYWEd7mCipdcqoaLPT6XyUKDDIogwReS3MZiJ0c(u0644gCBsrTJCawNkyeDi(SYDBNAVspOnMrocu(L1lDKehzBA6kHWHMrNRh1WUTcZ9OEtEHBdXMnQKC3AWhVwHK7(NQgM)4oJAmSmThgOGHDch1vNq0oXFR5LHEQAFBHDworEo)MPAaGGmmK9EfHerzbBSyNNGxgBO04OJlHSEN9XKYuUYiKRSmj)EZu8TkfIv3KPT4KEjudrJ2yHSKdnmRY9A2tjUrMhnqLql8NoTkf2V8gh6IDGQz(qbIegWAHMG5JOxTnkzIxsUMnAnJ(RwK9heJypop5zKwlY9Lk9lAMYacQ0vyH9SnCN5byy81pkJID6WwgimwtRAy5Mze3lCFO0asUHm03mx3VvshqvOLLuTRcDPtpY(Cl3HZWNHogCMauSjeKT(YdZtPbz9NC1DZhv7biR4QHIi9NorYws3(QlsxEj56TuJnMH5VP1Q)ctRsi0(54WUOOwlPOQaiV7xGoAKpi(a2FfjnXSokjNnG5cZDEny0KPtsa8C0nYjAA3)uDjAGk)YLQZ)IlpEY0RMDWXt)LJV4KJpBYNfSBI0eCZhwzJCJwhTKiI6UCGHsNAjSAfkdXo0g7t5yOWYPZv2KTnAK)wNxKM0HATp9viKnvpoDKshNVSl9Jl5NBbB1lU85fiCaGkGf5XSbMO8wrNRXStjQ5byPo(hHRGo)Q7oOPcjxnB593E)DjSwKuRw0FGQ5q2E9cglrLGAZz1NZdg1doGGb7pzZkSNmo7wo9voCbdIV68luljfNTCMAE14byNRBK9O22TX55)7Bo5I1K4iVJIkPr7Pw2c1YaIsPB)W(JcFtEVGOqoS5mjJ)0KLOEisgtiG)hMMrAvOlgFY4do(SzhD(j)(EPo6q(ue)B5oLHo7)(K6quqrefezg6OGoVjVl5Bs3(G0QxVHePLHMkacT2lhsgfqSa89ATyTwilmddycOWUDjrrHD73rWOdilIhYLEwX91vyu)4tp)S3o70JNE17Nm(3MC5poYJ4eq(JVvqbJIiHnqauKI1lGosg)5wyjDVzq7f)ignh0pyaPVQhjhkOsDfCj9BOuNbXhC57o(GzxsEGD(LJV64Zp7hh5oCkc(NuUJMsX)D59vy4a2oiGDSoQV(sf7WbAZlce79(Ao3dm)q6RozAC0BYhmaUR3V)GbKZy9gcmhMS)zu)Wk33)gB(ZO4j)25VDYLZg)UF90jND1ErrAap)Ekqq9c60z4O3Khg1zyxIYkmAuV(sIvztQLQNCVTq7Dftqtytae7feocbqKOF6cDz0)gnKetrsKc67Otts7OL(5RD8Hggp9OXNo(S9whjDeLjhmFpjsAePPZi)rQoI9IF2l(Xx8tuq3rKNyD7mOxNoWJSE9gvziK2SUFZK6yTe6cYPSjx(B7Te67qlHcJ6f2J0KfoiSRa)dIfq7tkwTYSEF0G4ObfIUQIKbfgnGiDO)TF)r9ca9t0GHKZzHrHEbN(BCMYcmjPFFIYKYq57jtGiJRRNB(9oITxmuvB1v5i2Gb9G)7(zL)BPxxiT8(10TPdPrlxLCBwAo6h4M9bJxFq5xMNsvvF4YIhVeTt8KBVNbSGbELsQtNnee)y6Y71A0vQ9qtD2637XvZkNr97sIRdge1BqN(WndPQYjxpK2CAY85PRONA67o(WL07WTc2hDN9VBd1dAD8)Ra(Tb9Cf8pQmJHMboA3k6IZP6DKGTlA1eVi7tPZ9di(i(wvCU41sl9QLUy69zf5OzPu0WGzyKFKncVcDv4vqGzAAPzrDd9jZyDm)Pms8i1W96vPaynYlVk5ApK3aVcE4xIxvckGMtfcuj)AaRj6itUiP2QKA2YUnrFo(mPCbp)U7MNXyzsRWxr3qhu(qo3oo)JzLPCXM2l(UeU5L)5eaJq8ltNQs5elK(YalP1rLu1P7POr8yWlYh5USOEHmI(WjfqAl)FgajidJ4Ybpe7KvOYT0Pl2slfq3bsljtr2vBWB5G6ZmIXChqhiISmcG8Z1jZBbPGkwxI9lUUKheR)x0npcyIHCgspGH21bqmP))p",
                s53 = "!EUI_S3xAZTTrw7(xrF5TQ79dsVeRKe5tAXlQsKLgjLmjtnv5cIesextcWba02kUY)97zR3WcPOINmjEuMAktbcc09Pp7Nt)0F57RdtwL1KcFyss2M8BMLUmRy0rrbQ)77((6Xj1ZQYYkEBHxy4iRl83l8JIh9D)g(uAECDg8p3Vz5s8x8XSQ68YIIa42dtMNsVcp)KnfllN9HFi9XYnnWvgNKwmBrzvn)T3xoBt9PP1n3LwbxjoPjT6HSM6i(BW7V8(7RZA(LcCCeMuNppdUTtU82BV8cZx)ZWxdJkpVKtp7I3VPjFzEZJ2pW4K1ltFmRY(jEO)rJu)NNF0t45hMCsAvK9ZDCYfP5fWvDEWEHhnv)Fbtmp5OKRp)nV9w7bERbbml0pt7xe9Q9TFldn6dsU9YR6sAcisZSYYLZl)ubs)1uBVXjV66tE)PltRRVoRUCt1SSN)BkizDgUu784)Ctv6XZAaoKt200uw87BDyknxUBdWASpZJGj0Ys80Wj(brtnllDizhoczn889hnEuaYBalltjI0vLFkZHvTpoR9EPHz77rqqre3xjbIDjC)4uJNm2qsct(Hx9Ahg12Il)gkWnk5t5ZBwCrAZSfOiDlUS6(zTAj5Be3HFVdPqZeXc3lYYFyrJ6LPzWulb4nbCFlslAkxDs5MI51FbhLXjPZNxs88(EjVA5YS6vzvz)45chzkRoACY6n1lYMF6MA43FA5YsCH2d0y5b0fVK7a9KXJcPp)a85jbilKxsf85PJdifqrj1lk)0jlZ)1F98zaZ(daj0FuYcyCVeh73M95Mnvz3ckplqnoaLau9DvzDokBGddALlGEXpweerSSrJ9hhfmfhgtsQYwEvzErdmTo9vV72xD93d0V1TUIxYNlo0BKFaPIZliiYlK1Bdp9y5P7fgHp94rb(J9cr1u71t3p2JvZn2dOe4Sh0J0wqxEvh6pjIePI8JMmEcs42N3vuOz07REKXthFue8mJcJMoEcsn3JhPyfdOgtu06PtokC60jEXtMggH2X2Jh3HazqtFrle4Q3HrKsMT(yuYz4cMFaWibJGOOrHEKohBtb8tmaLr3JbMzEowgvHHb08C84P(GUW97X5mpr9lp15P2YhXzIZuKXmyIxiSmk2U)BBY2KDttAZgsEeMVHaxZZES6nkmezqe14SoC4Xxmldw21CrbK2A)WXtJIc83tYr8rEJazROy)OSdhrRzXjxL1y9cI8qxx23LS4KRZwBEkrtdrcbz6k0FphLDmMHYQtfTD)yDgz4N03bARaHyLtcVA(dzpl1GGgpWnnyDSkTj7YItfNoEnP)Db4chAPlV4HJlYxLsk(WxmOgN0)Esz18SQBY)1ScszBCYDg9PhVe1VtkKJDgO097Fe(nWlzDv5S3SS8tDMDG9b5RyxFPNKxsD2YSznW7gSfy5thqL2uNrQZtRMFg4vlEdW8a(cTo92Jx4P9V2KwLHgaKj2Qs4Xuc(iFdyD44LlXPRVEKqwdKPK1R7MMhxMH0mFZ7QNvlMOzByHzpYHx))OSCvr0rKLgZm3SMIM0cghRnPnw(CfmCaMeBlx)oSkgI24CTTfM8X863cCcVfOmaNassdsUJ8n8kWAnCPcCA4PVX3v(QISvpI3ON4KWFhD9GcmyAYDp8QI07wMnhUHXjfBwDD5NQzIkyIL4OojBrEb(9WBczcViDwvjs3WlfM8HShVd((lP4nWakiZ5ZZRXh7TalCt(ACPFCsg)MWfXjjqCnxE)1PfIOImxIvpUxxw0ytVzxjEqCPqOZWJzbthqsIzIyjlIJZD)CGWRw(P0hRr2m2rBIbuteVaCkc4YXjCKAf4DL3sEFYeMvirbh0K8KhTged(CGX3rC0xIKs(EFOQ8tNLxbcoOimioMbpCisOji9N4(LhWuTKkon(fMeZuyWPR0hqvbvWdR(A0hjE5qpq29SU1A3VWex0vS01zwsNOPtyYGEODL1lLPgmpYTlYN9HIS6AmcxGDr0hU6U0gKMAT0a(dse4BWxcWuaKT1RZMtJ9ziz(PTY7NmBj8kVDrv5MhwGdfFzneyfMNvWAkyNIFl5(RIZSfJhzpdLNvCyQpHUNoHSW6ttDGx9d4IdRftPRhxy(z7fMiBoyMzG0gZkW)EwyH5d0tx(2enzmb1yBbVx02cslDzZhdsV22zgXkSWzJsZKYrBAEmswS4xNArvVw3RjREFqGghEvN9kh8JUUCzoUgQwDzvmb04zIndLWjGlprjOM9kGQ8oB1ogZtTeN8skRYbrf2YhmBwa)9VcICPlj(tTXclUnFwEGxG4KHG6ltR(P8687O0DaJ(cumLh9mXVVyy6LsaSHipRJYpN3POqm2EUAlIhJQtUSy5JNxutUyrwjDES)cerIRLjIHcuptcsc3nrRbxbib0VGl3GUaT5Z1zzZrECXIgpnTwlSUxLNcor98IDhrsISVpODNbyPFX8cj99hV5LWKIYISxSTO8h5BkBlhnbZ9EOxqO)yI1AidnMiZEAEd(eTanbtEFtoeo034MF44W1Xf1V1N2RgFLnfb2MBLMdx)9qRM97cGY3Pw(HUTqh66Q1Wgt76i6wSLs5m7fBPpjBP7Ru7lgzFXiRuHbouU)WdGtc6)V0gzhmqLxIIRD0THuWupPa4EcwqPN2xzJMrj)8vsUW)DATS)eqeXvXSiCuVbwhlzKXnwuRmr7A7KZly)j0RtS)V9YRp)FC57U94Fylr6glv(SWdls3GzEJZXZRkOq5ZQ(6qX(J2)c7YN8IhgV4HX3szj(FpHXZjA7VuPi(BbpmCtrSF4rEXW)n2Fu8Kak0Y)S7PHLzT)ytymjs)1YFJUe(VYoFWDEh3VIwjjxYM9lvTSBvlFj7XuuBCk2)RCXjdtEFD6hPUIyqVD7wYY)cAp6BHswU3r8QQ(Pv5Z23CvTVLYKRM9UlL5utj)EwLZCWmF3xDo7RwV9v7Z(kuz70j3telpnZr9BoStkynTZh1KHVyrsLIS9TEMKhO)NmvRrjvy3C8s3YSpDlZlgK(gThAEXwe3tpdAe)p1gKIHqKEyps3OQnJ7PT66pbT2LTK9eLOw9RoyOmwoCdlUpvfTDxxz5Qc183M22(LuvV1uvtXvtBkHxsZ7lP59L08(nyNa)TqAE37WQ)VP2b2n05)8xi5H2HI)onv)hDnsNKCr(SQYx84Q7w6Rvgru1Z)LnwK7gl6Lu0)NRu0)8Qm8)1KoKVfCKOLTssZ0qLi(prPdzlnr((UjJ2sOZTZL9WB3iPRTTQHGCVTsppbCn)hj98oBA)xYq)Znd90V7)KzO)Ln06ZzdT(Fn2K(wOMX7Z2C9pr2K2UHK9VzM2RYf)xZu0RbeQxQz8te7f6gI0)XRzCyYYS7FPKX7fal8I9Oxkz8DIiFByx5BI2x6VI2JqSfkYb(M6aSrrA4rsbdgm(6zbFFNK(abuyrj3L(aUTyVPSQbbLcEh4axeXzKJNp)00MShkRiWdcbJOhUO8JzVR8Mf533Wi4bCn4MUnVzzMfwNeREW3wLo7diWPOFc)uE9M0Ley48LVu4nzuCuW3vG4Z139BV7lf(r(HEt(Ucp)jt89(UF7l4)RWpEsC0OVd(2iVOX0)ojmgURaFeF(25)6hgmoaEnd)V4tcEoJMoAm8CHxJpogcJHOHHFLxWOPY)c31KX(EX6HwuCmIZLWGmmiEe81(b(tglxjEAKhCL4XJO)DSxO)y(xcuVrj3Ui7GJRwbu4UZCIKF88pMvGqSYbxvLT(pPecCUeNmpRjD2IRZsFagXahgdAza)XzmsqPyMYZQPzpXJOyWqWRldzj9soTSOEZk8xG8OtrWsAZ63LUkRl9G4a1Fpd0w3Y4P4BYsRo4vflqevzfmGE2pROeAbQ9qXETBWHrqY5nzRo4MSMdWXZZ6zmj5VNLUgOjh8)EWTv5fFiR7Cz3dggtYUdeeVbKSVlfr4MLPRRjiTc(geFJ(X1puLop78I55ZsBuyAhSiDDgcqvNxCzrgSUIaZzqsomXwM9XSLO(hdUFk4A0MQQSIzpYs5FFrajsh(DWNcgdFc8hSiWNeXORfcI0mmGoLuC0DiYALqvvxLxuKnhPRicDrtk115X5T5RjS7s)lKHV8lGxbozXhan(pVa1gYWONfdjp0XgfLFHhqVr8V5hN6V7B5Pw4zWU4WHbOf7DV8P49aAnNNDWBklNdVrVKRQkVpRgrjA6pfrSdWXn8gUiVEwgSywKvUH(()2MSA14BCIGtCAjUZYUpDZYgETKbjprF)RwTU5rrGeeszAidzBVPC5CsvEEbU(ZKwggazyZASHHOfOnr377Gr0jp(QpVoTaNgAQnAMbSomVCv(VIi2h8CG7wwIn8BavpJfLNRwSO1DGjEZknyPrtKAfKWQGQ1resDIGNPx4ymqefMVogH7zgREbQyv2Y0M8pMXielOAMrkB87vYoKrrMU93tRk0awhnqeCltzde)n(2MCV4XMf5ZUnFfbcYkWuB5M6B)ujDvbu8U7)hIkCFmRnqLm6iEAG4NRf65scnXj1RxM3CZseILDXOqUYY0Vs(OS9kqbTkb5OyqHkKKlUunaerc6j)606Mopz5bB2Q9esZcRGzeCdwwnlR(QznW6rDqYjhFnrMPV7es9JasWiYRrBoxAqgXJxCN7hqGcQG9Aeegc)oMk5mqrQhoyDGxqpgS6QY(yE2NygRgKkFftX7dA8udd6DlWLg9BqnecaFs)nWgNxbMZCMcuiU0uG)eHTX0tjaSmM2SO(8cYlj12(i)HceplZ(mcA7c4MdRbLA6VfocYZyIn5KQS0pGaro)C03(BsxZG(5OK7RaJLm(R5hlnhjneWhG1OGFQefzrvwMMleLbfwdsIDE28cc5uJsQfzEWnhAHWqF(bi(ACYWstisMnpDzzbipHwEhlqC4px45fgqylRx0KOy8PQ(UFPiyuWrX(HtIcc8IIPgtFAs693N)zlAbBR64zOsyEHvXtbwI4lJJbMb4y8hZiQwOdFjWuon5hF3zV663ZSMWCtpMDAusMY1cejboeeNJ5fC5J0koX44ZIs)46zGETIhUbfHyOIuqavdRis4BjXoGCfqujCueKde6my7tV8FA5Q1PvzxuohpBbE3LV7viTRjF2hm7)iWBmlrtc)olRwL2aRax9QRriXM)nAx5r4nfI2O9l5SSLnPiI1HwpyC7gF9lZAYMFr(YL51zqOeZjfi8Q1zKaa(3GAhWuGwjdrAyOOh8OpXl8leucuGWPk4(Th8rVOPOJ5OheuBIs3x8xki)(NgJ3xyagcaU5rl8IrpZ)EqJtu04VuehGpbFq1hhde)JtMEO3OdbZb7(PeoY)lftJG3ccG5Gya4fVN)uiyaGrMbhs5PgA9u3(Ca(fWJnbKEnJJT(kWjZKDtz4h6ogUibCCI30(On41TgtwepIYxv(juldb6TmIyYAKyLJbjnaZmC1LZnsRGJIoCpepslu0vlhXwbmQFdzErhX6r812j0MIEDuj6abUiuO0ba7X4jwdw8PymqyTnTEXpKxS7hmopbjhWwBdH5QeGgNLUSzXvzGfVIgi6yq1oPbQPCnEFe5ayejLv8b3bA6WasLGNcZZRxNTuaEzewJ1Oknd7QVgb(Y5lF8DxDkQdb(fZaBYaP)hb)qaBZvBw3KdoQPbZ0(m8t(aWSSy6qXXMdYLcc)LRPnxtNVkq9(uUmqCbWuuOf3wUg07WyThOxkDtv6ziiwJo7H3IgFtHrE(Q1LvGYw6yBaNY3qGtjz9AkySepEkioln6(dgVlb9lygCdbki4GwuuY548((0zz)ZJNp)YI6)Pvco(NRYMNN(pPB9FcgXagZ6pL(4r3Els8catKc5eydqnzkK19qFAzsHtYIlU8frSebxNr(Db2tblORsUrq(0WKQ085xKw9bbdU9fyFLwPEWAFG6LuaVxh08fmLAZvTt(BGBUnnEN)g0ETz5YELhEAZqOmNoJoAJx1euxBes5JXb1M0f8abwSGWkp(bioCn33egVbjZJJbl5kbBVjSotq0MLn0eE2hueuJb)nwLtyqUfFb2Jc3FpMIkgUYPrryIM3hIjAoEU1Wi5R5LZaql7nMVeHP9i2SfobU2)fg40fL3zlEIXyg3LLvd3X052dWByrz35crFYaOYN6csfOOK4YpMvTm9rXzKJK23yrEZDLFMymbNPuWUdYIrImSGgoMG5JznLdTR3dMJ(CCLPuGmVMPa9IhIpUSPPCfne3QqkWPHCN30arm(0qCr5Clc1iO0WO0yYV0E0ize34ymawkAuto5CEb4tYDP45PdV87rhaeYbqc9jcZNJdI89dhnoymEKoWkhnkJjKKNZb(y3PKfInRzMDuMcSewktzUwKzewxCe1v)Odjgjeosk(WBtRDLNihLLXUj(c(yta8XA2mxjJ2VdhvnrkLPABt04cF1I2b0xEWtqIoIgkPVezXW)GN4YUiYS2WtqYQaBRGgrMtkaW2I80pLa78DkKaRdQxzBWBgTp8Kq19rwlLC6QNXHG3NLfGOPmlCf6zGdrJNt48F3dCiGgTCtBwclkSjD5G6xgeAiSC39qLyc)WYVhZjhynfx00wAHje)djTLiVQ5RuhYp0ZKxi4d5b84FGEKZ06TjW5xCOqlWe6dHP5hemAsa6MTI)Jt(ak7WX73ftXLiYqILRT)EGxB85mk2izQ(mkXIFMZOGHEEIdENBoEHgnXiHO(m9mGRZPirT22j5dHJmPFWYfu(y)b(HOMmCE0hptBdwg1f4ktXh(Hs8SjWvw2ZKihkFucofYNBegpQyXehMqJmekHAZAbU7ccfeVHLVsyqTyDCGjG6M5W4jNq1wlhs5IcgoOaPxU8mYXmkc2aEly7QaX1jc9jJIKhrXbUoQXHHRTJpSqbYTbCPuwN0dZPXMCzfzCPWpGhNJ7XinCzGMzPq1cy4BREr34KuGngXrA8774xcN6fYcO23wotg3z7MheXuF(spoPiBttv6sZbpWw4iaA9hWJ5a4)VBnpWCsR5Xs3leEX663LLwThmIGrf0Nc(4vZ5yUzuYQ0plmd8rXLlFPdllNje6bqoxIKoWnullJVbup1Sa0BX(3JANuoZ4aQ(CMe4dLcolGUguSSlb8uM1VZk3aXfjVxJ7VT9(MNOUXLHjnKJ7azBBnqv6x1RIrwQrmzOnmsDcFz7zBRqG9nmaknqkyzajgqOSO10ZlOaA5KzXHjzm7tkOJPalO4ATNF(qqtsapyfuKkaqLuJrnzRyU2ntwGRFYMiohBKpNyLhxSGTOaQyjJEbQWzrVR7lGqJE0qtuxC48tKDMIHthtkH0HrgEwhFgCTfs2jfJk5ZivhAYg7096FsvxJqlXalomG5Jyy6ZhD5NGUzSBIjEgwaVYDFJMq2BDkWyOdQVqqzFvknC05PdHv8YMD9duCPDY25XBmBIClyKYIONrSOLVLQ3QKnejVh4bXKoULFrIBPVv(DLuDwSG1DlkNSsdF)NrqgtmOzZDtQ5qRVzD6m9HPeeF8SNMlN2rp4ozg5hINzGbJhh5pMoF7yh6776QWRDdfC3d9PSPDHTuLMck52v5RZMF4Na)bo8J(94PHJNQqinoERBCR0kn0xj5ZgC1XOx1siXdn70oug90wfyUY6TT6rtWWw5Q5TQSVOcqK8AueGurjtbrHUtx8H3v2YCNXltQAgMKyGbq5Ajh95uZHzBgAkDDX2kh9nOxdUKqYTe2ykfgrRUYkCwtXlPohHgNuLwL9QL5n0zefhffFYbBF0(qHQA8Wv(ifwl7FlWZExDz1DCqaOFazP0zf7IY6MCR8coYW4XN3qCcxzJuDS9YhyoGGQY(HErGvg7fjKah1H7Mp1Y1ihdvEo(zzsYIe3cphpfNB8coNJa8qZt7)RX7csrrnMdcqo2cRU81z)0kxsyv6WNHA4GeB0Sb2j)gt8D4EXtCjk54ZMrEFRbNi0PilVCSNLtswLxKFxzTXf8PtmNoQ(HC22W1LiUQhsplOSAcHN(ywf5ykZK9URoLQTiDjqxfLWrZQaXNmzuWuFVO4jXG2h98ONlt8AU3nxbCN1yLUf9(VBmtQf1MSeYu5SGt5bR1IGJj5DWWGV(a7IPFw6Q0hYUidcpGoBAtMVcxJMMCNQ6OwjPnc8xTz2cIYGNaxVBZQ7yQhC)LLFyvA1hQ)cWOdora(ZwOQAl633tsNVDP09j)3SlMij8tbyZ76RJ50jjHqzAwc8hcHqzQcj9dpMp0Vrh4YYWrmEiCOI0VEDg6(ILp26QgW7Fl6p11pHdBbNwTERWdqx7t6TA)tWMdY9B3T4n2Cg9MKCQSmp5A)d6DOiOWvbN2CucalT615lxALyD69AB4wr0FJcKGqPL3IECjNlHCnk)O5SaZGTRbGg4RPF3eQMdMm(PEQNqFRjQVrhXswXjlMttFNsx5JhUFaNhx0vEab(fX35UPP8Qm3Am3KT8EEKZ8uSEmESqxGh3tXNUYrpubd2TukjeMZIB3fGzS8tSaYCy8PMRKojWeY8QluNJy0jxgs(9s(uEXCSYVBkAuN4K6vRDoDgl)86Vqnf3SnvNDbDAEYhRURLZ1zPjE89yB3FUWB6ukVmAGDN)Q4e8WYNAMnfK07pj47(TwpC(89CWhUV)ykuLbE4af35HlkMDfoSYdk1hfUIG8IgqqTRheYOXSsiM4o45Qh8RmUiq(cqlxi3d4HIC02zFj927elT4Y3Mx3G9zkwBCfJ9ymuE8GzLIJ3MrMIlG12WRWeJThDbJpoCG)2gAC9ahBFCo0p99zRAHuC(dQfo(y5d7XQZlUonNoIeXwYttcPSiGxfpwWNNDBjEm)c)nRRJRYk1YcGBwwZ4(mfijpWuvssZb1Fx4PsQ6O4JZ1L7P1P(CNg7We4zRKVKchIdLlXqhAEuv3GoCbS8dnOLGmqYgUSW6PAPLenF7p1QhPKeHr5GLfhqnbPvoV3q6f4sohBDTZ2u8qgDywAX)rpgRctZJYEPl0sd)4npkGAH)aZXtSY9aR6XhaUntDOHA6cw9u2ABRLxXbAAwS(dXd8wkdSqwV460gPEnIyMRXgVrrtM4he5pn0JpsiOqW65YKptU39VHhj((X2oIOoGMViTaCibZvje4W8vOif9zZbERC(nFcMc1)(ISIZls5(8JT6JDKQCf8wuQzLda4(W6lP97h4WxDI6qi9e9b1m6DgjlZxY9S(117Ka8xJQLLZF6AYlJwNZVKkOGKuYoID6wCAep6y6)eRZyySZS0dLRvod5EGCAmcRNhhR67r7F(BAFEw3Y2f5yJmRzZ3OAmr)3rCE)7dcAaAlW4I5hBAIAjgObUEti(I1(uSL06JMYAr)yp1X2bMweGxbjbDIr1VnLuNn6EolHCD)yIScCBPDzHKdjA7JO4(oqOhc8C5HIUIh6KZAt8)fPCFDkaKEnZS62Vrnlf3uCKUEVabuyNcgUpyuRgslWHlLiNbL9ZP6JJVlnhtSSUwkN(8jrTrHNWa0bNXpu4SBFknJDi3RUgvplscc7NN6VDknQScyo4OLLBLlL6ttp(4gwuhYJj5wfVwTj6)m3(v8mY6SegUWM1uBU8Mtp7w0VNoGd42vy4WmA0ny7ujh5cRByCYMg6WZ9RRMbiK5Rv(uk1s(PRzyajzxX9(vj03b99aY3IIHXj)OIa0kiJOewZoTLwqlHO9C5GWN4Xf1d2KWUkh6tS2vz7txfbEAvZ7ngI86Ccm3vrrBX3(1r4Qj4qY)8qrvux9gdRJqKHg0X32o35QJOJOT0y9ph1eIBqIwHUyEQs8V7btaPWWvDvx7VIoJ(0ryoH(hwhb1X1pzLe0YXtrjr)lUB5qDNR7j2Vbu4AYXUQ6AovkC3EyaVh0FONToKoEh0MS3gVdmowiIXrjKhzuO4TCuPLCGrW1mQ7tS1X2GRUhSbQ6C0U)mTMpm)PJM8buI1RXHocPBZESLCjbyqT8eKvo5ks9v0cEF6RhqU0CRgXSHC6dez6tmDaVH2IWkAeFlcRBlmFxd722wiR6dlA66ozyYSfyjknEe)uD6NQGeMXwkSY6pLVotvDfsTs)U83RtVorci1Y66Sv5f6Cwrg5XE6fENQVrczPBKddln7noPedC)6uiOwPumC(duHW0AxP11najRS94eowS960gSDMZUSaCVYk6GxJd8VNiwUUb0N9BofEuxrYBymIA2oSaDtIJfAcUT5GBEAx73BfkadZ2ChXHhEyd4TfKn1lhuEM18ZfKjqSor2lKT6CFRCvY8I25QStEw0BkkSV8SFQwLyJTWDkXOl7guNBTvta8CdGO9iWPVuAX8k(Z06QCKq26mDDzW7i8iqloE8OGPEtLOz0ezovT4UIf4dKDSiMtAH1diZCPWb(Pb03BbNBJoAeMx3TODYQlsCiGDBcQUrD4iX3wEnkPi7JzvTZ9Gykgu28285ZZko40ZadYCCgWfF)7FalI57Nn32jlPWF51Vb)sEpOmqO3wK9r8HuEqqK30OPJPAH22sQW4nymud6L7trbSt2pEQjIr7)(7JFVF04GG43pn2Ba1Z9P2SVC0WcFCiMoRA96sORENb022E9gi8fVFDAfgLOlhizizpuoBYg9nTZ3c1lu9REg0hXBMHd0jX5aGt5GWHt7ZwSV2FIRAR9Up9(UcoYMFExEcUdf3Wx3BoE6AHrN3htQi61NOHDkzhog6yCOD8Asuiw6OhQg)cuL(Cvsp4EhPvEKCdCvJE(MDDY2kNbL5AhgbD8R944G7UzX0ulUgDBTNxOwF7W9kLqsUZ6nTJTurZLs3iWyN0zPtDXARCDzd1T5VnB5AUDlXo4AE2jsEmiq2iss1ToCFUABQCgl1UJlOrv2sUuJXjQ4Ov7dFZvWc8ruyjcl5jCOhTlM3Jhcq(GNIobl)ogj9R6vpW89ocBQRP(bJhrBZP9zq67b2I1)x83HLxaCrCD2mQNgIXdQSjjRsxVoV4bQqPA90YMiFgUgDcbr3so9NnN2Pm0FnL88dUHuSDYiOubcBVp2BWSi3CruVFG0oXMCWik(4dWU)7G)pzpKCWz5FmVi7GR2uTUSo7)lENRWnDCCYXNE75)eTTJXxJ1oNHB7IxxvU60ZU414SeBqISLzZWnmmp94cfgK4hn6)cN1EJc)VSznYeGGUbeOzb3t3s7mjbRGD2c6(xYOon)Z1z1LBQMLPlYMzJRmnzj1UDZ(a4xJWtZ9C3pixNkxm2F0fZEeVhUZR9tEy28tWyTsROlZIdi2cLoppROXeZXyjhN6IRB9lzV8B1OpopBPm)GjjQGenPlv7swwIMAMxscnBoO11uJuWMJASCwEf6wS95FVzEtLjJlMVP2JyqMybXD7XrezL4zhri4aXfsJtBmoqljy(9slnj53zrArr2sCraxsJsUpF5syEFKpTnFm9wb3HkBkWo3GrjcVKhlomyYuuROF00GPtd3xDQbK(y4zehojmGAEogMlKgUSvU6DwC00UygxlKLyClNp7d4(6TwTaZ26)LIdJuHsXv1rIM)gfXMJjHyV5vEdndPisVIj0CS18jqzGCSx)o5Geyql6gWz6piWQG6DWn(HmKLUazh9fKPG)iCp4SRrLzaU6rZyAgGnVXgqw1z7oBnezFGu1IJ8TNHfI3C6zkPkEwPzdzARHCa0pMf06XIRh4dZWDRcJwOymFNUNCMIYY42ELLFE1Q14oo5MM0hO95G5XWRfA9aeZj(BzEv1tf)moSMqTEbVaO6Kx9VLUbAtgZ)yuuAm8WKUic3V49vloEpCODGNq1dUsLiTU9op0aVwuho5QGbIftYbJ4ll1Qn2)eQthbnBF42fzRWDct7UFXXTcE7PkidIQ9n6rxbCFk8EGPyT1hyK8hJn0k3Rqud75OMKJavRwG27xM7L5(PUhX0NF6Gr5KMi)NucQo1D9jib2tKuwtpI)Wzujf2o0cYladwmS290K9oAu3XUV5XD1SgU3MnucwiJjQixhLLiDwC6800sJuJBTTy70lJkZa9lvQwSL5Ehea12EeUF4v3VXuIwq1JASW(l90anJPIlh05gJ)ABr1TBBuKPC2Ed9zy3i)grT094KhYkYKTP32NTTA310MQsS)VWNbBPG12P(l8aWN7bki0VQ8vGph)XQJqahlgVsinJdPDOJNeoAhaL8WGVXw0x7kXovpG4ILamKG9sw4rPYqQQygH(uNF)7kv(8rd22UmSNbhYXW3J8TRVbgnsCYNuAV6vJecOfA0VrnB(JqnfBCUT6EGNV00cmD9wunxyz5HvI0ZM72IUPwR15)PJsO2TJS69URI(JB2af58kGdlpDPG3uUQ1gqzbcLb6FUrtQYDxTVg9QLYMZq011RMkx3oS0pr(eUdDsdRaY17dsqGDkWwbwBBPkDxuq04gGPjd7brkFm2UT44UNDSksNgTJe9nSze7S(XQ6S7DR2oSy8iggUWiKGlmrl4qwf0lOO14yzFSegnI7l2E8LIqMS87BE1sg)xTvJuhMCw5NeqAQLdxtKcNohztcX1sjDDO7OOQaNMZILD6jSV(ui4wGGor7nSAy0)Pw(5z985g0wHdnDT76YrJ1)zSvJTA519pLUCtwD9Oex9JmlzlFWaZ3cKCILB9(LGZ(sF4z87t2tYTUpwOQNi)899rKbC04yFi2pKuVpztd7fAtKFi(lRc9t6vqx17(qa1BsRMNNwGbE9wb)V4aEypQb70qeKeTO3niIMtHC6hD)K14tcT9K1Dxhr7sav(zY7Ns9ZriFVo)JykpCICqW2v(ARZxB13JTv6RhSsW6DHTJwA21Tj944WXkZe6UjUAtrw9n5iQ)HV9jAI55vLf3VrafoEMWYhtXbOnGJQuL3BTGhiNdtWhIaRBu4E8BqgwJWVv1s9SxbCtqmNVHHnR0B1uA1FhLLZmHG0FOIetBp6RTtgJXptikroxOwax2PliilI6Ed8d(XjRZQQZRBWVr2dhxK(zUycc(pnkjVy9MMllUTeBV1iQh8vfx0knqGjRfioZvPBRa4kPnyfzz7e)uz(mC9uazTjyTxxwEx6YHfceKa8MSMgml1ugFWxVkuDZoNI38nC5DwJ7JC79BcjNfqjkwq)5tqWjM2kV3z6DdPQVuUqMvvUCjxAcmfsi9bBUoUPkYNdmMPZZolBz6JmGIODtXPhWj1Mi2rLwRr4fvQOI8bn(GcPWOXJJj4JAFui55ffEewCaU6aYgHbbKfbph0B(dAwfty1I8vcWzRWzrf1LXipX9Ded9wwtB9kdz1kzr0IPaR2XAcYnnvzfp0SGZxf4N4MMLaVebCO2R38QOUb7Th2cgWYqRMVAytOHOPBRVIhESYHUSW8ExfFfMQhX5eg3OJ4PmGENMX3wpG7kVDyXxH2dwg1dNi7piQFVVSG2VF4abuwGyfCt6Q1s(nIt(FEBY)ZfhaFj4Yct))P(2mGYEhvsvnxeJqBb3)w5pqUBDxAtZYmiEfKjQVZuvNRPZI8CbSeTa62Oe1fD6cJqjHIQTkdjWx3Dxi4i37(K0j200roGxnf4(seK0TQupVdX37JfQ29giwuqWfflitZXIkqiV4QF4hV59h)UZE)1hF(z4c66w4g8H(t9qPPjXG)bbe8Iyao4d98MIsQ(bHXJcqmgKvSUHr0(ttxo7Y1eoZclj3Nxv3C9MIZklWDFdUFPRaMIxNVKrBOWK3Mvvs5z7NWDyCkUhPMKa6xwToN2WuGdb6ZLbKXcg)p2SGykagGLLLZxUPg1E7Ke(NXCoiiy3Z5PrXbthfsZ5yCNuwZiRT2dehVe6KES(8Dwb0Zsvq6n9ydSNzxK9zyum60Z8NcRJa5oVa3(WZiWdHPDy9AonVAgHkbGoF6xe86Jh)A47JtWIsSPMt)LgXPjOwysciCLoBbvBKOKuccay8Gb3YFPvFW0A7JtQqSQNE2ko7EgnbjBQZA11YIKZRPes0uLMVKuX8WmeiauJ3xt)N141NtpNGq27y8AgDrjlrfN9sQAn4iwsRbx)zqRvHF6o9uzZhwjqs07P3pnxrNLiHKPgnBhC4bhxLLEqKp(fE2IuWfqGybwpOpvJ4FaMfhi67AUo(0I9Y87WoNK2pNW9JYAxKwSjD5XZNlz95FTjBt2xO9xhmPUfp7iw8i8MVDrv6scNS(d4fpvEXlklV)p03nnTN4CybKxKVkDnPbbXkc(Z9VEJf8GY2)jn0EG1Q0D9vHb)K7AAzZnoztbDiQa(jt9saHPcow3UGhe6wnahXJjRSNwLEp65h5XsNItGhAqnfNKo7d4lqWeCeSzbh2oVan4YocGpPx9zqwdMecImZiosnO2aCpHvC8aWi28t4Pxb7NbnO5Xe9Mjyfg85GZQaH7yW7HFdVFw6ASiwZVe0fjQ9llRMxFsge7k8ZbpTlxNvqNp8xKvS5s4JZbVipDjc)AuWd4OeyAXTenI26nyEfWrsS5Becip(OPP4PrqINpIbftzmRnDg4x7YmznRGGnIo7m9OjJj)pJ9gfer(WUh(F65fogdjEY4Xt9NYqWfMzFfjKi3NxCFjvEO60pMn)FuwUI8lu5qb4t6)ccsgba0a0jBgbkT9)Rv9u3DuVJanKOJ747I3rADTUyRcRvxcJjnbiQoDGBer(XhOq97fAeKoy6FGw95QSI7(91cWSkvVTc77PmHBNdREgYLCvv2mWTWYc2T5(mTg4kgkqu8aPoiKczH1iQOR2Zj2d2lytpuFbON0)cheG4JRCMSWtCtFA9ge7nbFDz5gPL6aMD(PLI8WAwp5uJGEfQ12jIV9kNXrXs2v(vkKGqlUYVJFfORSenFFuxKLMp)S87VpFgiYsg)7ArRdbalHnTrRDWR9FSiV5145AHODaf1blZnmuOyCmaDgtHSoJtkbFoyWYrWRquoMHYvzZR3ARyJ9KkH7MAm5qVze0VrSnSnW8d6P6NYQe4otJcdTpHVVJzCWDBo9VvSbYP6D(U4tUzWLHMLl4sLXOofIJaw9hcZE6GsnsoJMAGnfZpaVDgvRuTCYobPdbpOu3V1wxRdzIdueXxKn3FV9UVZ6h5lqSKgift30usQpvOILgY4zbdna8aRifeQ3YGrCxKwx6KcC2Dn2I51zyHMrT6qOXuwQygamvF2JoMNKxbfihbB(q0Kanemqm9XGBsfguQ0J)rs(SSoseuG7fB1HXukBjBFFhgggX1XgwGTjzEHcRKVG)HYBkG4he2pntQeMoJezu3N8KqQym5swmVmi3QgpiXtTI1dzdBmXpt7DowFKGOx8qIxVIW4(xGyYTGqrAevJj728IA2F7vl5eebjHcoizdUTmolQNTm9sacxcpCKmBttroNHs6JSWVugiRbt1APETiS5sYGRLWMML3sJHw8KvT7IhoQuIrOLhHgbckU0Mhrww(LIdfsBlDsIy(eJeYwFVIkmgC34EtI2Ui6KpOuTrjbYpXFENLhHOiOFN5ryfsVIxrwPOshIa3UaRRy3(cRdNyHsjkWR3wirEryuwyVZCwE9Aq)TfRe41j9nUI5OMnl92A9f05rH7rIe3mXT1Ck0OqWU1dlOiI2T2rzkzDq6qC8RboE0PCxI9UFC2c)6m0iaBNMFM9RLK7qbuwFBFA16SABmnP1i1x3Ijz8rPrg3wFS9CIQBB)H3hd2kqiUbPHkjWQsmsBRLLB6aT4(a55VLA7Ugu46YrVCnTslTPNx6Ri3dI2IQJOdhSOtmVIgnCbmM4alO51cTUJ5d6jft)aw8KriDSfYtCX1uCluRW9yTvqn2SQWXhg(8APNtpvC0(zji2vPUE3dAC3qlNjXoAHwGpfizNT00cxI5g4qbT495J8ZWJmWnq(GfnBUIDI3cqy0sSpGKpTd4EM9xamNClvPCSWWf2ChXzJ5CwU4GUCnOZvSexVol1N)nd4eJTPiTDNojTZhpNCCPkCQP1qafRCTVORqLgwZ3FqcRZgbUhaNn7cFP95HdgY)Dm)vh(TD7GdFw70RTDmpbdyvGNsmI5l(bSt3taR(K)jfGJF0b2upAh4O7j1mTm4mIVQLFftnJbhVUbxsAUJaSFvWJgtvB1naX97NUf7EmK6EAaYmfSrJw6FEowS(6AJX68vYrb4(RMNhxG2P9wFU6um2OSHfRO1jztlYDvSRkDb49PgSLdjnM2wmvaFfjpiR9qSfn3rvkt5KSPdBvAW0AL6gyjUizCZXXPVobo6u6glmYCFJbeBDu0po0nhP)dgkqUTeY2wmkjO5Dl5R2rLPXzw(KOXC6UX809epgmWv6eCCtfU6jp4avEE4DQJ)ZCmhT1y1yPOUXLabv1w1C7t0ffpGtWwcos)0JEdH7w1e09jH541yqZalyTdddDgPFVliDwmFAlUm3eVybVFOFOwUPQ(96Gmuxy4qg0lXc24A2Uksyq2ZkZPNdnwT0dpmkr0kUQEJaDGGQiAnrq0qID)gGbAkxn(BGG65y6zW9d7Jrc98jUn0EGt9q5BcZygNv0bIwQNiv3RywgSrW9hpGhfo(d3xoSq(qBneoNqGU0yXRZ(JHZExji7fyWVhSSHk44uaEwJp8pXWK6DRw4CmMWPbySALXLPNXm5oCJueouYfpMGLCJC2qrlPF(Tfx7gSKnR((Mur0apQJBxNLc4UAG75cBlncnTxp83seFBjyyj9Lw(Xy48NQDCxZBmuCnw(4PTM2o)C68YURuBrfMIKcBBigXCwLA12FN2vUFNHpnC2kOA4ZaT(Gv8db7M2j2MtgCNnu0)EJEIpY6y7S)UdFQTugbOmBnFY9N34)Jfxfi2zLyroog3iMgkNWdeXKQ7B2zoHvn9efCKZrvMPofpTiQWIN0S43DMFBhALRfX(dOkg0YMcEmFEXC8OUd3ELs0k)7pqRTaSu7iTMUbaRhYwhb7EtipXFjORohFLtKKO9N8GU6P)3gOAEsnnWslAx9ov)Z9xUGW8dAlt27zG4WfqRvSAIOGBSAsL3)DhR2Z3)1)nfjNB2rrD)dgW2GoJ02HJ90ZUEc4RD0sdvvObsg2qbg2jkhKPWUe99fPiNIWwrk2j4pbnM7PAHuCUuqzghkBhfrhhmz37uURycJukdD)E0ZjnrhBU511kKYbQo1xHGkzN65uC60RaQeoBIsOt0LdV7F3N4m5(irhJ6wtoIRpH6QhoCCISJs2fmAVcRDO6qnuKy7BT24oRbB)GoyB827NK(RcIk0d7CRSLC7TTyR6pMYTuyW(I2dwlB58Lvxe2XXmtESTLjCIBCpYILPcn2LFEWIPSLsqVRQX1TDomHlURAImuk16u4HTwj6Dgv6wI9eDUG7ZZ9SwDyryCCSM1ErBif3TCi8kuTxSQvRablkfhGaa3yvqGMsr(GlPcvLtRfv6po2v4Ua(SmQCN4rAoEn5B4DoHKd32PHfEbQDfJQVU7R5eCFKCGYpP(2Y6Gm4z2HwDYsv)TG1GC1UDxM04oovPXBKSbc3JwryWSL3A0jT5WwsuF39fypD2JotT9PFv6912nutxn8dAvuLUTHBfNT2UhTAzk(iofB2D5OeBWggO)2QARkMD7Whn5TVg)bC)ZC5wzvFOt9PoS16DK(anlWaoG8C1D0tlpHYVA)6DtXye3TI0rQtS9jamFwQR0LmCRS)1O1m1I49u6FCxYsQZWU0d8pVDvQFwneqKOx2TyJFnoZfhMJz)tw2GEW2Qr82w7V9SBdHU(U2t23JLJW0ohVNTBYazxVYP)ZXFD8mOKoNBFwTEaVHgvQ0gipAq8e2Cqob6VF5yZ2J(NCtlyvJSEciAVYSgQxtFUS)QvRBE0inNYBIDcpinh7SM(FIlCWxXEGWx2zR2TcPVGFa939JF9Yz3H85PMJry8qkRDw7S9wCV7Up50pNQ8JogcCFhJ9h7tRrkoKRsvFwO7ynGLriWqB1DPn6KQQo6ql4oJSp7OD6lgltNd2zD4w809fzAb3)yBhdzBMHC292og4g9L2AqWnqRgAqvWrWMnf8htVBiNf98OXY7EBPWrccTsNy4YNrBm4N5DlbTj41ZQBlPTlbUHh2wWDGkl9pHIlGogAb7WURMAo2Pslybgpz2N9D)e0R)Vp9EmXTzG61pwMZUNgor5mfvF9E2QaBPZ8FMzc1YpzhMlUBfeDmdeFTFlFvWEt88c6xYEy3zdiG4PUJmOoK8(BE3NEdYyZLaIl2PAQN2MrNWCtcV7jpMMMNr7X2wcqFBvL9z3XndMJZ9BBu0puSZ18IDpXEtHmusGDRr2avXC4Qw3jbSTsxxN9GH0jY7tJc0F)r80QX826OiZ(NYQ332vYJzezStBg1onI9KzqpQS19L84b3Wt7twKBjekcl9Kiq3ChdCXT(LwO6gHij4PPlhEf)ViQEZBDy9oLYoSY9PLL66Oa5liHNayoNyvMglfuloQ1U1thn54CPB)VnyoNTndAFiE7STO21ohypQw326BPbIJEFsknixyOyDxl17hqf2RBTCIwY5iunMXXKMz7ZsF9(KazO2BrKHsB9a76UHBDqhDIYlVNUrRVCvlOePP)QC3LzdVjw6Rmc7S917BxV3FrL6df(S2kbw5JUtw)E(PH2Qzpexrn2iWwwgC)6zxkZDLF5TVH(CBJYHkmyFPs6RuYo2wEQvhA7Y()LtMSiKi41eV))2VtAc30wRa(PWycdYT2494rtXHHbb0Ldgf5noc9uU7zyrpdaqhnLmCRHjFsx80)9Mn1CYJfE(X2yDhzl4ZWvhX4t4tDm1kX8Q5UFShojdcIINgqNN67bnnyse9Jjc0yc(1T2sqi8U7pDcHPbgAirA9Jcia8Xli2h(Q9yAy3UC0lio(5JF8(HHTh)igMS8)F7D1TCBBSK(vjVaofbajbjYvmr0XQSLKlj64SxXcscschtbWLe0Y64AF33(R7E(da0YE3yhDsXCtKjjagmtpF9pt3FTXxr7KeNExFdtmC1E7hauVH6FHeEiO3iCkm))DJHeKx9OFSzJ4EY7WEJ6uNcXT3qVU)mMPvzt3j1T7wRlF5Kfm8iwKCY6lvuc79K87XroBkE9fQwtXC7oji4Ed6jztv760CFhYDFfHLjdY7R4u)sz6W3(bh7N7WHvZEVuJq)wX06iBgcyNVLQp)lev2N6uH7VgnBxQzMeJ8Bk6rpL64(CIFFzSq)UGlXYk0acF1nhow0G4TA9y5WXIwD4yrzoO4)tPuXEow0GuG4qwj0HzvoS9BvZD6jgEy73F5B)8kGyy2tNowuKAq7SDBYHBKbmL4OSQAPwFDufvlc7UZbVjHSTx6f3Nq8bdsesb(DBapUwHmZ9vbSbigVGXpm9hB2f4OSRQR2U7EWICbVmG7(Y4UHmy6RD3csQBjORB6tsZAWbK)b5VfM5e5OvC2kH5MFaK0NyQAz1hEC5LRYfYVl7b8dapBTPE9DLxX3GQD3FjiztE4uKVP5UvO7aIpG86JCAcxkYU)8RxHsFCs2dLvxFZUn4FaoMUwFw53VEv5npkxk5vvztXY8R)xAALTk)(IM6QB3HHnsIg6B3MxHXq0WShkYxxxTeugP8Ymn7QnLRPBiD3KKnB9MIBk2SP46xIXeoRSM7YHpDL5vl3ua21gmukBYP93(E((oxUT4B8UM13vxuv(PL1LRyMsu6nxfxvMVA7P4yAKBOqtPkJGkLkLBOqV8AlPA5UTiJfaFbrltkL3WbFAC29p2qZ28Bbwq(vSEakSdS0pN)ETBgkJthXrb4BW30xWTHYO44bPdsIiGj58eBYxrIogHotpP6fJGNVPO3TapHG0MC0dVdn1DtYiJ6yTIpU6jC3GCXJRlyMQon7tcByPDeN615Ov5ODqHh1Vlwo9AzIn4gF0UQBlQRQu)VdPsjzBfylCiap)t0K92TpK)ilFcsK2Y42A2gWLPZfnBYBYP56tMF0XV7eUB2e0NmrsqKKYjJaNAtP6FRbS1FfoarqjcE3mNCSdcd9oJzYw5K8A3EpazAPDj)ToAQrA6hpbpcbb(rTw60whk371o(OQOOOXAh5I)iqvyq(cf74M6v)eMVZfkGct)Nw3CArX1m)TQNbagZhnF2Ix96tp(3FfVLd0)hFJ(mCR(902CswUQyZpDX6Ynf0OAs2sK(0xyQRX2)Kfm7Vs7UjjhMEJe7NKrGBhftBJAsQYiD5L0ZNgPFaykJZUKUGDafyu2D3lnlp0GsBEq(2n1v)BGIaWNnnaEiy)P4o1zn3vSz7jLe(GaHmIWrfvgb)6UJogv0n6OHftYLGSw(y9sCtaMfPlOyBt9dlFO4XneuHWd14mWVr))mT2JdWl)66hOrkZuMecu59feA)wS9xa)UeuD3MpSuWB0B(kcpRGP2xg6b)0PzBFKWQRByKB6wFDXnMlIN4JtciZ8D0aCb4wsMrSPh9)D4NyBTrCotnwBq)Ox4XTkcu07FOS6vCEhlTuJlVvonynfwaPhn7QRkwJufMaxD)73UP4JeUZj7w1GL2(j9wlx(7)85(r0i(5NMvF5)Q4QMYpw4AEagIUSg8bytb3Gx0F)uEaSy3gss7c01yU4dLRLP4o1uRVzd6BUL9W6YU2Cg4ipp0FpsgcRbq3ASzvbgWt9iCRf1RrFDqYGLU0IQEv42iDKd9d0CcnrUPU3xgXQNZD0Yw(scV5ncTPJSB2qy3ZEj7BcGiNwcRAmRZDPTtOhWrBNAOwukvHpdXKSIDL87l3N4xUopGAxX5TDDXBiN0eRYWscn8VpujPWzGI(vCxEf6IefRWVoEGEJLuGOvr8pv)snUDqxu1TSEkzlslAMvCw87qEEIwy)nY0Ytt3c4uRQ3T(uY4lLyAyfTKAyDkKtJihT1OeZP8L0ZbuxdPNwnBL2QOV9UpwyWvxzh7LJhsU4X7WimNMDBXTjO)eyUF6JWMur2gfYQBqZ4vOJu3ZiyQgC(1n99uflcoNWvE83URWWTZWwKIvOpebUcKW2lxr2LbuxMnsZxlnhj5IpISfSAlbmWqOo5oRTbIHADzUt7m1x5cfmMuKP9wquUbsm3NHDLFd)AvJDVBODtRyQ0MKD1LgYuHpWZ0UztYyr6NJKcky2Nu7HUDH3YplnJEmVU83)IPB7rWcbTJfxhVf2WaPApUbAZdi2uYoB5zWRgyKzFuOLKTMt(DRzfZ)ejhvr2llOS6r)bB04QtrP5umSifcxBQtKu(Hto65EjDjzuWEDCvLC7pxwMdNTSzgL3wPwapYldBZIwVm8yVBaJWHFgpH79DrJgpyKGQYwk2ZhZzuB4Vwisq55ztKZE9GT7ggn7sOLDHFgrwBWUoOMQX7KTmwLv6ciJMhj6SA5nEsmSkAd0OzERnRwrtPyU5Rmhvi7Ij7T0b2XNE08)KTQqswhjhmftCWNaozgSNJad5Km6T4JH7LgoW8czFcFzEsiotOTVZe8c4)SJiBtzzesv6Vn)0fZpVZEFLUF6QgHFzGghHyhpT(cHf5MWUg9L2aWO9DGhdpGko8qwiDhuBFDVFtQAZzdKDtGmT0TCfnVjoOxH2Muowsg8TXp2FfKsZ)8vWdSFDf5PGMRsd(5i3gb9pXwfPZSPDi2a5ogPkw0UzqJnD1o(miBPuJM83N0jsEsh2l045l6JTe83AVCEgGL77Hf6cQ3asSXO7LPJiOUZSygGGeBA83f3rEdj8ZcKUFJumEesheuJ4Dr(q4t4pXH540RNhkYok7CX7lAmll2Tv6BSiWt5YI8kM25dT8XmWFb3KRqor0bWh96166M7mBxvTNa2rO)OWsbQ)1EoHaGX5IQAyQFzbHayA(7Q3dzFQkoMjyv0y5Ct4TSZOTolfl0S4kQD9sNAi9nmA64bPtgMeLKkHGLbQ75JbqDRpwg8TT7XsgrRZfI4Dxvd52g3OGWkZ(rA0eoUDbD(1pg75nsM0mA7HuH0yJiZIWoEwmm0iqmoJD7KyLDCwGpGDk68IT0hzlGaEDxc)JGX1Y8dFJD4BfMJnP83ThrUKdVxRgQb4XxRxqf3eyYajilIkmOl9MqsD2nuQzth92lKOP8vwyN0lHt1sld99vyQ33rE7ZFAUC2S9ADUUNK7zgkLS2hA((YTtVtNMqWm7EnwnIfsmjlMC0fks2rWFU87uAoJJx5U7VNmrRO6AneUQT1wcs2FHMFJFBD526kl8ozfJlKydK)wBRbSmwG6hEDb0iPXkq6Pz9FWZal05rGEzJ0flUzSgpWe9bz7QkBSSy6rN9(t5nC(I(HtoTez19Tp9PgOSHlMc(s5HlwZd2me4UBa5VizVwx)i2x(96q663KAdjfPB1j)YHdqOd9yHNnwqZHV1AKqVRbDlWi1lPxvVP8Fxx1KZDLe6N52pR6iDgWzyYqm0yxoV4HY1A3(Hf)i)ZFj6eBgVW2JYnSGkgOWQMuj)lmwtom78ZEZCwHMVVsbRdglYyHys0QiFl6yvs1TPnqywlqYeP(vbS64uj5Qnf8ITxlObM3Mx0Dz3h43MVhPT4K5X(Q08l5o22izC1VGa3X0jyxmDot69LJTa3wjJwmVpscf13p2o5qFjzKEN1aDV9Ew3Ds(TLx1AhacfLmOXKgIULV3m(4OoSlrOJFjE5R99ZvTjoamw1LXsq(ImgpA9RcgEGqc)S9iMzDHU)rMkVAvqwLRMi(Uku4uoBqErCmcr33Y5NepIRV5ytWeejXqb6HzVz(lfl(8hYSaNrOME)mHgrI9o8eIn40ZKnHcy88rAklciDmus34Izeo44SxnF2BMFoH9F0StM97ZpxTDPDygKObVoFFsp(XbZsJloxJD(B6vPaaUUJTOM5ghuwVxRCwslQ5w3Pe)oz2mq2Ws)ICCjxvWZrB)8c()Ej6)xKjhoSpX3v4rCroCrBO6TSlAGAOsnHBWf4aTjJPQzCMCdZbSUDAq203roAjAtkMpiRE611rPFRczrdILEi7OSgz65y0hYUmNdLg5GTvDAFr4zQschIohVEFqF4M2wmaVqJTE(UKBUI(LVDAbT6x9Gq(TDB8WEhBPlahSBIPr5gSS)0wC5VMUpxZTXtZzJlI0yiS4t)OAreq(9KgJDF9hLOOjdsMgR9UEpNJ7(XqZuRFTSbwwrES6Ql0axa8yCy9kPjcFsnwNZ(NASDsJyUyS)6nLFmVPGtec18)8QBl0TDUdL0Drg1GsXYQHusRCwou5AmvLR1mNsB74nJrkMSSr0Rk9To3U3WxHzu)w6nj(3YDwjaITcNb3T8OxEogv2GI5bsXdAFdkTdLVBr5pWEWNmo)tYU8EPbRtlXsBFXAcvhl0mTSEzphnbRhLHE4sxlH73f9ybMvXuP1mYAC7EcVwmdn161NNytfil7LBwGjwKvEYN(07EADdKrSR1hs)PxSILJTF7Bl2Co5rnGlCnNFvV(xR7EjWSlVi(jkKLqr5fSWN(fyGgjes6N9oXyFLNsutfTojRUEJEUN)mg9KqMNcq(4KE6hymjj48)gB4jT6N)UJpA55ZVyXzNpBXXND6NLZPvxw5g1OeZjcAOTJgWlnyYMPz0b6SKMiOP2hQaFBZhyBnNMg2YTlCYli2tARRouclX9Gf37e7mnnI62sq(cG(hW6WSMhxdx(HCad1XBemb61jPRbVZ)937eU8gIpzeu1CfPLv7Kbz8d1i2RTgz5ddL8rEHitVbrMDmTRKSbD7NRssshN8lvKg9KHs17NH0LjCFqA2IZERAZy4d)pREb(TT2jWou35yI6BghRP)pDfxeC0VlIlwJFhhia4WJEMiTOb095L0YKPKnrvPPdjjMrJstt)LQHtgMmH(FjthLWBDzbiisgaKscqMqe)DqcsQrO3o7nZo64tx(QZEZ)vpyqFhfQ(pgmONLsvJsgXyqJgpnAWVufpyWG4r0)oE4qsGZbkDavkmtk(Bqh2Zs5hCcktIybOK4yGffpAGNYS)gaJgLDYzN(6LNC8flE)8z)X8Z)NbEeFUK)vAt0Zs5POOPJJG8u8WXkLgbDAiOVE60oyu0pEtOFMkUGkmNGDiCOiN6QW2Opj5893eO0mYilYpSLhD8f)2XV9nhF68)zG7WhnW)8XDMsMsdtRhmySZuAK2jhGDK2E4FtEU)8e2HC(kkMSDMmrUAy04ePyzGMkeENFWEFfzGEo48LgklPKmmvHet(bC4Y8d70ZGaafLmTnIJuZwwwU5GHohm0HJvyAk5pEBSgHvEScl)imZzs2fVA2jZo9jI58H498mfYzAQKJcqvLC0ZhWAoyDJWkvMZLyCu8uYNQ4bPdhma(wnC4uNnXA58(df1zA28)4Sxp)8LV985xm)8)yFh11byNNPWojJhMmKSvojnjECQlSYhCW6qyL1mDmackbfrfHbLmoLeDO))Orthgb5NXPtMGppjimZ)n41LftA27(9tMF6Idysv)NL3xdJgma2uNmEWKyYH(KXthossCv(C4p4k2bSP(WMgsUTJqfsYpX4StP))4jJj5NPJIg5D0x)O9otstD)IV1uk0O6PYVUSOc1DB36DrtJwBDkljAVumjt1u27LBQVNBXMZV(wMzcsdYKuVYAik7(In3Q5IRK6HM8PnS2WCnjQPJIj09O0Xdthq7arsZWL00VaMeikGeKE5g614AHPJUX(39rVb92T)1oHQPTFkSDutjZbdCyUL0iBghTZPczXOzn86YpvSkms4t5l1KyxYeMMxIf3wwxH6IsP9c(2kpK9YJcXkpkiCUon0S0RHENzcOL)wMJvKsLD32cWGgvnlYVmGInWRqarLeKUGcl844Bk5PbsLyG0YUKuSsYzm70e9947K8g8SBUzvjtAj9YtfXjE05HSUDC1hlBk4CnDy2n5Cn3(R5GGy4xMbU80edKrsd5zmODcKpAg(usV(oKSripDzP3cHfHXk15M5FB6GcU)a9FAwmLMjDuuVuAl2Fi4OdCEKSejiVhBo7T9Zm1WCdOBisSCmynOlZx1d1dvVRbZxCAjNMP)l6INcYVqwdPBWe74aCHZ)l",
            },
        },
        -- Blizzard Edit Mode layout strings (shown in a copy popup), same keying.
        editMode = {
            p1080 = {
                s64 = "",
                s53 = "",
            },
            p1440 = {
                s64 = "2 50 0 0 0 7 7 UIParent 0.0 42.0 -1 ##$$%/&&'%)$+$,$ 0 1 1 7 7 UIParent 0.0 45.0 -1 ##$$%/&('%(#,$ 0 2 0 1 1 UIParent 0.0 -1162.0 -1 ##$$%/&&'%(#,$ 0 3 0 0 0 UIParent 611.9 -1122.0 -1 ##$%%/&&'%(#,$ 0 4 0 0 0 UIParent 1298.5 -1122.0 -1 ##$%%/&&'%(#,$ 0 5 0 6 0 ChatFrame1 -48.0 64.0 -1 #$$$%/&&'%(#,$ 0 6 1 1 4 UIParent 0.0 -50.0 -1 ##$$%/&('%(#,$ 0 7 1 1 4 UIParent 0.0 -100.0 -1 ##$$%/&('%(#,$ 0 10 0 1 1 UIParent 0.0 -1102.0 -1 ##$$&%'% 0 11 0 7 7 UIParent 0.0 78.0 -1 ##$$&&'%,# 0 12 0 4 4 UIParent -227.0 -500.0 -1 ##$$&('% 1 -1 0 0 0 UIParent 1152.0 -1242.4 -1 #%$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 7 7 UIParent -238.0 324.0 -1 $#3# 3 1 0 7 7 UIParent 238.0 324.0 -1 %#3# 3 2 0 0 2 TargetFrame -31.5 -3.5 -1 %#&#3# 3 3 0 0 0 UIParent 648.7 -542.0 -1 '$(#)#-k.)/#1#3.5%627-7$8( 3 4 0 0 0 UIParent 2.0 -602.0 -1 ,$-5.-/#0#1#2(5%6-7-7$8( 3 5 0 2 2 UIParent -4.3 -535.0 -1 &$*#3# 3 6 1 5 5 UIParent 0.0 0.0 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 7 7 UIParent 3.0 1362.0 -1 # 5 -1 0 7 7 UIParent -267.0 602.0 -1 # 6 0 0 2 2 UIParent -257.2 -12.8 -1 ##$#%#&.(()( 6 1 0 2 2 UIParent -271.8 -159.2 -1 ##$#%#'+(()(-$ 6 2 0 1 1 UIParent 0.0 -882.0 -1 ##$#%$&((()(+#,-,$ 7 -1 0 1 1 UIParent -779.7 -2.0 -1 # 8 -1 0 6 6 UIParent 60.8 44.0 -1 #'$&%$&i 9 -1 1 7 7 UIParent 0.0 45.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 8 8 UIParent 0.0 220.0 -1 # 12 -1 0 1 1 UIParent 1142.0 -302.0 -1 #3$#%# 13 -1 0 1 1 UIParent -877.7 -2.0 -1 ##$#%)&- 14 -1 0 0 6 MicroMenuContainer 0.0 -4.0 -1 ##$#%( 15 0 0 7 7 UIParent 0.0 1182.0 -1 &- 15 1 1 7 7 StatusTrackingBarManager 0.0 17.0 -1 &- 16 -1 0 8 6 MinimapCluster -4.0 0.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 8 6 MinimapCluster -4.4 -0.4 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 1 1 UIParent 0.0 -926.5 -1 ##$7%$&('+(-($)#+$,$-# 20 1 0 0 0 UIParent 1188.1 -1051.1 -1 ##$)%$&('+(-($)#+$,$-# 20 2 0 0 0 UIParent 1247.1 -884.5 -1 ##$$%$&('+(-($)#+$,$-# 20 3 0 0 0 UIParent 1159.2 -1127.0 -1 #$$$%#&('+(-($)#*%+$,$-#.U 21 -1 1 7 7 UIParent -410.0 380.0 -1 ##$# 22 0 0 4 4 UIParent 302.0 0.0 -1 #$$$%$&('((#)U*$+#,$-$.$/U0% 22 1 0 1 1 UIParent 0.0 -442.0 -1 &('()U*#+$ 22 2 0 4 4 UIParent 0.0 296.0 -1 &('()U*#+$ 22 3 0 4 4 UIParent 0.0 220.0 -1 &('()U*#+$ 23 -1 0 4 4 UIParent 639.0 -620.0 -1 ##$#%#&S&$'_(#)U+#,$--.*/-/$",
                s53 = "2 50 0 0 0 7 7 UIParent 0.0 42.0 -1 ##$$%/&&'%)$+$,$ 0 1 1 7 7 UIParent 0.0 45.0 -1 ##$$%/&('%(#,$ 0 2 0 1 1 UIParent 0.0 -1162.0 -1 ##$$%/&&'%(#,$ 0 3 0 0 0 UIParent 611.9 -1122.0 -1 ##$%%/&&'%(#,$ 0 4 0 0 0 UIParent 1298.5 -1122.0 -1 ##$%%/&&'%(#,$ 0 5 0 6 0 ChatFrame1 -48.0 64.0 -1 #$$$%/&&'%(#,$ 0 6 1 1 4 UIParent 0.0 -50.0 -1 ##$$%/&('%(#,$ 0 7 1 1 4 UIParent 0.0 -100.0 -1 ##$$%/&('%(#,$ 0 10 0 1 1 UIParent 0.0 -1102.0 -1 ##$$&%'% 0 11 0 7 7 UIParent 0.0 78.0 -1 ##$$&&'%,# 0 12 0 4 4 UIParent -227.0 -500.0 -1 ##$$&('% 1 -1 0 0 0 UIParent 1152.0 -1242.4 -1 #%$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 7 7 UIParent -238.0 324.0 -1 $#3# 3 1 0 7 7 UIParent 238.0 324.0 -1 %#3# 3 2 0 0 2 TargetFrame -31.5 -3.5 -1 %#&#3# 3 3 0 0 0 UIParent 648.7 -542.0 -1 '$(#)#-k.)/#1#3.5%627-7$8( 3 4 0 0 0 UIParent 2.0 -602.0 -1 ,$-5.-/#0#1#2(5%6-7-7$8( 3 5 0 2 2 UIParent -4.3 -535.0 -1 &$*#3# 3 6 1 5 5 UIParent 0.0 0.0 -1 -#.#/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 7 7 UIParent 3.0 1362.0 -1 # 5 -1 0 7 7 UIParent -267.0 602.0 -1 # 6 0 0 1 1 UIParent 782.0 -2.0 -1 ##$#%#&.(()( 6 1 0 8 6 DurabilityFrame -4.0 0.0 -1 ##$#%#'+(()(-$ 6 2 0 1 1 UIParent 0.0 -882.0 -1 ##$#%$&((()(+#,-,$ 7 -1 0 1 1 UIParent -779.7 -2.0 -1 # 8 -1 0 0 0 UIParent 50.0 -1226.0 -1 #'$&%$&i 9 -1 1 7 7 UIParent 0.0 45.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 5 5 UIParent -60.5 -260.0 -1 # 12 -1 0 1 1 UIParent 1142.0 -302.0 -1 #3$#%# 13 -1 0 1 1 UIParent -877.7 -2.0 -1 ##$#%)&- 14 -1 0 0 6 MicroMenuContainer 0.0 -4.0 -1 ##$#%( 15 0 0 7 7 UIParent 0.0 1182.0 -1 &- 15 1 1 7 7 StatusTrackingBarManager 0.0 17.0 -1 &- 16 -1 0 8 6 MinimapCluster -4.0 0.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 8 6 MinimapCluster -4.4 -0.4 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 1 1 UIParent 0.0 -926.5 -1 ##$7%$&('+(-($)#+$,$-# 20 1 0 0 0 UIParent 1188.1 -1051.1 -1 ##$)%$&('+(-($)#+$,$-# 20 2 0 0 0 UIParent 1247.1 -884.5 -1 ##$$%$&('+(-($)#+$,$-# 20 3 0 0 0 UIParent 1159.2 -1127.0 -1 #$$$%#&('+(-($)#*%+$,$-#.U 21 -1 1 7 7 UIParent -410.0 380.0 -1 ##$# 22 0 0 4 4 UIParent 302.0 0.0 -1 #$$$%$&('((#)U*$+#,$-$.$/U0% 22 1 0 1 1 UIParent 0.0 -442.0 -1 &('()U*#+$ 22 2 0 4 4 UIParent 0.0 296.0 -1 &('()U*#+$ 22 3 0 4 4 UIParent 0.0 220.0 -1 &('()U*#+$ 23 -1 0 4 4 UIParent 639.0 -620.0 -1 ##$#%#&S&$'_(#)U+#,$--.*/-/$",
            },
        },
    },
}

EllesmereUI.WEEKLY_SPOTLIGHT = nil  -- { name = "...", description = "...", exportString = "!EUI_..." }
-- To set a weekly spotlight, uncomment and fill in:
-- EllesmereUI.WEEKLY_SPOTLIGHT = {
--     name = "Week 1 Spotlight",
--     description = "A clean minimal setup",
--     exportString = "!EUI_...",
-- }


-------------------------------------------------------------------------------
--  Initialize profile system on first login
--  Creates the "Default" profile from current settings if none exists.
--  Also saves the active profile on logout (via Lite pre-logout callback)
--  so SavedVariables are current before StripDefaults runs.
-------------------------------------------------------------------------------
do
    -- Register pre-logout callback to persist fonts, colors, and unlock layout
    -- into the active profile, and track the last non-spec profile.
    -- All addons use _dbRegistry (NewDB), so no manual snapshot is needed --
    -- they write directly to the central store.
    EllesmereUI.Lite.RegisterPreLogout(function()
        if not EllesmereUI._profileSaveLocked then
            local db = GetProfilesDB()
            local name = db.activeProfile or "Default"
            local profileData = db.profiles[name]
            if profileData then
                profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
                profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
                profileData.unlockLayout = {
                    anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
                    widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
                    heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
                    phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
                }
            end
            -- Track the last active profile that was NOT spec-assigned so
            -- characters without a spec assignment can fall back to it.
            local isSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == name then isSpecAssigned = true; break end
                end
            end
            if not isSpecAssigned then
                db.lastNonSpecProfile = name
            end
        end
    end)

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        local db = GetProfilesDB()

        -- On first install, create "Default" from current (default) settings.
        -- If activeProfile is already set (user deleted Default intentionally),
        -- don't recreate it.
        if not db.activeProfile then
            db.activeProfile = "Default"
            if not db.profiles["Default"] then
                db.profiles["Default"] = {}
            end
            local hasDefault = false
            for _, n in ipairs(db.profileOrder) do
                if n == "Default" then hasDefault = true; break end
            end
            if not hasDefault then
                table.insert(db.profileOrder, "Default")
            end
        end
        -- Safety: if the active profile doesn't exist, fall back to the first
        -- available profile or create Default as a last resort.
        if not db.profiles[db.activeProfile] then
            local fallback
            for _, n in ipairs(db.profileOrder) do
                if db.profiles[n] then fallback = n; break end
            end
            if not fallback then
                fallback = "Default"
                db.profiles["Default"] = {}
                if not db.profileOrder[1] then
                    db.profileOrder[1] = "Default"
                end
            end
            db.activeProfile = fallback
        end

        ---------------------------------------------------------------
        --  Note: multiple specs may intentionally point to the same
        --  profile. No deduplication is performed here.
        ---------------------------------------------------------------

        -- Restore saved profile keybinds
        C_Timer.After(1, function()
            EllesmereUI.RestoreProfileKeybinds()
        end)
    end)
end

-------------------------------------------------------------------------------
--  Shared popup builder for Export and Import
--  Matches the info popup look: dark bg, thin scrollbar, smooth scroll.
-------------------------------------------------------------------------------
local SCROLL_STEP  = 45
local SMOOTH_SPEED = 12

local function BuildStringPopup(title, subtitle, readOnly, onConfirm, confirmLabel)
    local POPUP_W, POPUP_H = 520, 310
    local FONT = EllesmereUI.EXPRESSWAY

    -- Dimmer
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.25)

    -- Popup
    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PanelPP)

    -- Title
    local titleFS = EllesmereUI.MakeFont(popup, 15, "", 1, 1, 1)
    titleFS:SetPoint("TOP", popup, "TOP", 0, -20)
    titleFS:SetText(title)

    -- Subtitle
    local subFS = EllesmereUI.MakeFont(popup, 11, "", 1, 1, 1)
    subFS:SetAlpha(0.45)
    subFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    subFS:SetText(subtitle)

    -- ScrollFrame containing the EditBox
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     20, -58)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 52)
    sf:SetFrameLevel(popup:GetFrameLevel() + 1)
    sf:EnableMouseWheel(true)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() or (POPUP_W - 40))
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    local editBox = CreateFrame("EditBox", nil, sc)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(FONT, 11, "")
    editBox:SetTextColor(1, 1, 1, 0.75)
    editBox:SetPoint("TOPLEFT",     sc, "TOPLEFT",     0, 0)
    editBox:SetPoint("TOPRIGHT",    sc, "TOPRIGHT",   -14, 0)
    editBox:SetHeight(1)  -- grows with content

    -- Scrollbar track
    local scrollTrack = CreateFrame("Frame", nil, sf)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    -2, -4)
    scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2,  4)
    scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
    scrollTrack:Hide()
    local trackBg = scrollTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(1, 1, 1, 0.02)

    local scrollThumb = CreateFrame("Button", nil, scrollTrack)
    scrollThumb:SetWidth(4)
    scrollThumb:SetHeight(60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
    scrollThumb:EnableMouse(true)
    scrollThumb:RegisterForDrag("LeftButton")
    scrollThumb:SetScript("OnDragStart", function() end)
    scrollThumb:SetScript("OnDragStop",  function() end)
    local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(1, 1, 1, 0.27)

    local scrollTarget = 0
    local isSmoothing  = false
    local smoothFrame  = CreateFrame("Frame")
    smoothFrame:Hide()

    local function UpdateThumb()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        if maxScroll <= 0 then scrollTrack:Hide(); return end
        scrollTrack:Show()
        local trackH = scrollTrack:GetHeight()
        local visH   = sf:GetHeight()
        local ratio  = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * ratio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = sf:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            sf:SetVerticalScroll(scrollTarget)
            UpdateThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
        UpdateThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self)
        if maxScroll <= 0 then return end
        SmoothScrollTo((isSmoothing and scrollTarget or self:GetVerticalScroll()) - delta * SCROLL_STEP)
    end)
    sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    -- Thumb drag
    local isDragging, dragStartY, dragStartScroll
    local function StopDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end
    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false; smoothFrame:Hide()
        isDragging = true
        local _, cy = GetCursorPosition()
        dragStartY      = cy / self:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
            isSmoothing = false; smoothFrame:Hide()
            local _, cy2 = GetCursorPosition()
            cy2 = cy2 / self2:GetEffectiveScale()
            local trackH   = scrollTrack:GetHeight()
            local maxTravel = trackH - self2:GetHeight()
            if maxTravel <= 0 then return end
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            local newScroll = math.max(0, math.min(maxScroll,
                dragStartScroll + ((dragStartY - cy2) / maxTravel) * maxScroll))
            scrollTarget = newScroll
            sf:SetVerticalScroll(newScroll)
            UpdateThumb()
        end)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopDrag() end
    end)

    -- Reset on hide
    dimmer:HookScript("OnHide", function()
        isSmoothing = false; smoothFrame:Hide()
        scrollTarget = 0
        sf:SetVerticalScroll(0)
        editBox:ClearFocus()
    end)

    -- Auto-select for export (read-only): click selects all for easy copy.
    -- For import (editable): just re-focus so the user can paste immediately.
    if readOnly then
        editBox:SetScript("OnMouseUp", function(self)
            C_Timer.After(0, function() self:SetFocus(); self:HighlightText() end)
        end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
    else
        editBox:SetScript("OnMouseUp", function(self)
            self:SetFocus()
        end)
        -- Click anywhere in the scroll area should also focus the editbox
        sf:SetScript("OnMouseDown", function()
            editBox:SetFocus()
        end)
    end

    if readOnly then
        editBox:SetScript("OnChar", function(self)
            self:SetText(self._readOnly or ""); self:HighlightText()
        end)
    end

    -- Resize scroll child to fit editbox content
    local function RefreshHeight()
        C_Timer.After(0.01, function()
            local lineH = (editBox.GetLineHeight and editBox:GetLineHeight()) or 14
            local h = editBox:GetNumLines() * lineH
            local sfH = sf:GetHeight() or 100
            -- Only grow scroll child beyond the visible area when content is taller
            if h <= sfH then
                sc:SetHeight(sfH)
                editBox:SetHeight(sfH)
            else
                sc:SetHeight(h + 4)
                editBox:SetHeight(h + 4)
            end
            UpdateThumb()
        end)
    end
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if readOnly and userInput then
            self:SetText(self._readOnly or ""); self:HighlightText()
        end
        RefreshHeight()
    end)

    -- Buttons
    if onConfirm then
        local confirmBtn = CreateFrame("Button", nil, popup)
        confirmBtn:SetSize(120, 26)
        confirmBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)
        confirmBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(confirmBtn, confirmLabel or "Import", 11,
            EllesmereUI.WB_COLOURS, function()
                local str = editBox:GetText()
                if str and #str > 0 then
                    dimmer:Hide()
                    onConfirm(str)
                end
            end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(120, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 14)
        cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(cancelBtn, "Cancel", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    else
        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(120, 26)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(closeBtn, "Close", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    end

    -- Dimmer click to close
    dimmer:SetScript("OnMouseDown", function()
        if not popup:IsMouseOver() then dimmer:Hide() end
    end)

    -- Escape to close
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            dimmer:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return dimmer, editBox, RefreshHeight
end

-------------------------------------------------------------------------------
--  Export Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowExportPopup(exportStr)
    local dimmer, editBox, RefreshHeight = BuildStringPopup(
        "Export Profile",
        "Copy the string below and share it",
        true, nil, nil)

    editBox._readOnly = exportStr
    editBox:SetText(exportStr)
    RefreshHeight()

    dimmer:Show()
    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Copy Popup (read-only string with a custom title/subtitle)
--  Same auto-highlight behavior as ShowExportPopup, but the caller supplies the
--  title and subtitle (e.g. for the preset "Copy Blizz Edit Mode" string).
-------------------------------------------------------------------------------
function EllesmereUI:ShowCopyPopup(title, subtitle, str)
    local dimmer, editBox, RefreshHeight = BuildStringPopup(
        title or "Copy", subtitle or "", true, nil, nil)

    editBox._readOnly = str or ""
    editBox:SetText(str or "")
    RefreshHeight()

    dimmer:Show()
    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Apply a Blizzard Edit Mode layout from a preset's export string.
--  Decodes the string with C_EditMode.ConvertStringToLayoutInfo, writes it into
--  the saved-layout list, then persists with C_EditMode.SaveLayouts +
--  SetActiveLayout. We deliberately do NOT use EditModeManagerFrame:ImportLayout:
--  its MakeNewLayout indexes self.highestLayoutIndexByType, which is nil until the
--  player has opened Blizzard Edit Mode at least once this session, so it errors
--  out of the box. The low-level C_EditMode path has no such dependency (this is
--  how the layout list is managed internally). The CALLER must ReloadUI()
--  immediately after a successful import so both land together and the addon taint
--  introduced into Edit Mode is wiped. Must be out of combat. Returns true if a
--  layout was applied.
-------------------------------------------------------------------------------
function EllesmereUI.ApplyPresetEditMode(layoutString, layoutName)
    if type(layoutString) ~= "string" or layoutString == "" then return false end
    if not layoutName or layoutName == "" then return false end
    if InCombatLockdown() then return false end
    local mgr = EditModeManagerFrame
    if not (C_EditMode and C_EditMode.ConvertStringToLayoutInfo and C_EditMode.GetLayouts
        and C_EditMode.SaveLayouts and C_EditMode.SetActiveLayout) then return false end
    -- Edit Mode account settings populate on EDIT_MODE_LAYOUTS_UPDATED (login);
    -- once present, C_EditMode.GetLayouts is usable without opening the UI.
    if not (mgr and mgr.accountSettings) then return false end
    if not (EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts) then return false end

    local imported = C_EditMode.ConvertStringToLayoutInfo(layoutString)
    if not imported then return false end  -- malformed or version-incompatible string
    imported.layoutType = Enum.EditModeLayoutType.Account
    imported.layoutName = layoutName

    -- Bring the imported layout up to THIS client's Edit Mode schema. A string
    -- exported from an older build carries only the systems/settings that existed
    -- then, so newer per-system options (e.g. the Tracked Bars "Display Mode",
    -- "Bar Width", "Show Timer", and crucially "Hide When Inactive") would be
    -- absent and never appear in Edit Mode. Reconciling adds them with their modern
    -- defaults so the imported layout behaves like a natively-created one.
    if mgr.ReconcileWithModern then
        mgr:ReconcileWithModern(imported)
    end

    local info = C_EditMode.GetLayouts()
    if not (info and info.layouts) then return false end
    if mgr.ReconcileWithModern then
        for _, l in ipairs(info.layouts) do mgr:ReconcileWithModern(l) end
    end

    -- C_EditMode.GetLayouts returns only the saved layouts; the live game keeps
    -- Blizzard's built-in presets ahead of them, and SaveLayouts / SetActiveLayout
    -- index into that combined view. Rebuild it -- presets first, then the saved
    -- layouts -- so the active index we hand back lines up with what the game uses.
    local layouts = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    local presetCount = #layouts
    for _, l in ipairs(info.layouts) do
        layouts[#layouts + 1] = l
    end

    -- Re-importing a preset should refresh, not duplicate: drop any earlier copy of
    -- our layout. Only the editable (post-preset) range can hold one.
    for i = #layouts, presetCount + 1, -1 do
        if layouts[i].layoutName == layoutName then
            table.remove(layouts, i)
        end
    end

    -- The game lists layouts as presets, then Account, then Character. Slot ours in
    -- just before the first Character layout (or at the end when there is none) so
    -- it stays grouped with the Account layouts.
    local slot = #layouts + 1
    for i = presetCount + 1, #layouts do
        if layouts[i].layoutType == Enum.EditModeLayoutType.Character then
            slot = i
            break
        end
    end
    table.insert(layouts, slot, imported)

    info.layouts      = layouts
    info.activeLayout = slot
    C_EditMode.SaveLayouts(info)
    C_EditMode.SetActiveLayout(slot)
    return true
end

-------------------------------------------------------------------------------
--  Import Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowImportPopup(onImport)
    local dimmer, editBox = BuildStringPopup(
        "Import Profile",
        "Paste an EllesmereUI profile string below",
        false,
        function(str) if onImport then onImport(str) end end,
        "Import")

    dimmer:Show()
    C_Timer.After(0.05, function() editBox:SetFocus() end)
end

-------------------------------------------------------------------------------
--  Wago UI Packs API
--  ExportProfile and ImportProfile already exist above with the right
--  signatures. The functions below fill in the rest of the spec:
--  https://github.com/methodgg/Wago-Creator-UI/blob/main/
--  WagoUI_Libraries/LibAddonProfiles/ImplementationGuide.lua
-------------------------------------------------------------------------------
function EllesmereUI.DecodeProfileString(profileString)
    local payload = EllesmereUI.DecodeImportString(profileString)
    return payload and payload.data or nil
end

function EllesmereUI.SetProfile(profileKey)
    EllesmereUI.SwitchProfile(profileKey)
end

function EllesmereUI.GetProfileKeys()
    local _, profiles = EllesmereUI.GetProfileList()
    local keys = {}
    if profiles then
        for k in pairs(profiles) do keys[k] = true end
    end
    return keys
end

function EllesmereUI.GetProfileAssignments()
    return nil
end

function EllesmereUI.GetCurrentProfileKey()
    return EllesmereUI.GetActiveProfileName()
end

function EllesmereUI.OpenConfig()
    if not InCombatLockdown() then EllesmereUI:Show() end
end

function EllesmereUI.CloseConfig()
    EllesmereUI:Hide()
end
