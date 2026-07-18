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
    -- BlizzardSkin itself is excluded: it stores settings on the shared
    -- EllesmereUIDB root, not through NewDB, so it has no per-profile data.
    -- Dragon Riding is the one exception inside that addon -- it owns a real
    -- per-profile DB (EllesmereUIDragonRidingDB) but ships as a file inside the
    -- BlizzardSkin addon, so it is NOT a separately loadable addon. hostAddon
    -- tells the loaded check (export strip + import/export checkboxes) to resolve
    -- "installed?" through the BlizzardSkin folder instead of the (nonexistent)
    -- EllesmereUIDragonRiding addon. Without this it would always be stripped.
    { folder = "EllesmereUIDragonRiding",      display = "Dragon Riding",       svName = "EllesmereUIDragonRidingDB",      suffix = "DragonRiding",     hostAddon = "EllesmereUIBlizzardSkin" },
    { folder = "EllesmereUIBags",              display = "Bags",                svName = "EllesmereUIBagsDB",              suffix = "Bags"              },
    { folder = "EllesmereUIFriends",           display = "Friends List",        svName = "EllesmereUIFriendsDB",           suffix = "Friends"           },
    { folder = "EllesmereUIMythicTimer",       display = "Mythic+ Timer",       svName = "EllesmereUIMythicTimerDB",       suffix = "MythicTimer"       },
    { folder = "EllesmereUIQuestTracker",      display = "Quest Tracker",       svName = "EllesmereUIQuestTrackerDB",      suffix = "QuestTracker"      },
    { folder = "EllesmereUIMinimap",           display = "Minimap",             svName = "EllesmereUIMinimapDB",           suffix = "Minimap"           },
    { folder = "EllesmereUIDamageMeters",     display = "Damage Meters",       svName = "EllesmereUIDamageMetersDB",      suffix = "DamageMeters"      },
    { folder = "EllesmereUIChat",             display = "Chat",                svName = "EllesmereUIChatDB",              suffix = "Chat"              },
    { folder = "EllesmereUIDataBars",         display = "DataBars",            svName = "EllesmereUIDataBarsDB",          suffix = "DataBars"          },
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
-- folder -> the addon whose loaded-state proves this module is installed. Most
-- modules host themselves; a sub-module (e.g. Dragon Riding) maps to its host.
local FOLDER_HOST = {}
for _, entry in ipairs(ADDON_DB_MAP) do
    local canon = EUI_CANON_PREFIX .. (entry.suffix or "")
    entry.canon = canon
    FOLDER_TO_CANON[entry.folder] = canon
    CANON_TO_FOLDER[canon] = entry.folder
    FOLDER_HOST[entry.folder] = entry.hostAddon or entry.folder
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
-- Optional cooperative-yield hook: when set (async decode), DeserializeValue
-- calls it periodically with the current parse position so a wrapping
-- coroutine can spread the work across frames. nil (the default) keeps all
-- synchronous callers exactly as before.
local deserializeYieldHook
local deserializeOps = 0

local function DeserializeValue(str, pos)
    if deserializeYieldHook then
        deserializeOps = deserializeOps + 1
        if deserializeOps >= 2048 then
            deserializeOps = 0
            deserializeYieldHook(pos)
        end
    end
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

-- Install/clear the deserializer's cooperative-yield hook (async decode).
function Serializer.SetYieldHook(fn)
    deserializeYieldHook = fn
    deserializeOps = 0
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
--      darkMode = <per-profile Dark Mode palette + class/power/resource darken>,
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

--- Is the module behind this profile folder actually installed/loaded?
--- Resolves through hostAddon for sub-modules (e.g. Dragon Riding lives inside
--- the BlizzardSkin addon, so its folder is never a loadable addon on its own).
--- Unknown folders fall back to a direct check so behaviour is unchanged.
function EllesmereUI.IsModuleAddonLoaded(folder)
    return IsAddonLoaded(FOLDER_HOST[folder] or folder)
end

--- Builds a profile unlockLayout snapshot (anchors + size matches + phantom
--- bounds). CONTRACT: unlockLayout snapshots hold BASELINE links only -- the
--- restore side writes them into the live globals and resets the active
--- unlock-layer pointer, ASSERTING baseline. While a spec/conditional
--- group's unlock layer is live, the live globals hold that layer's links:
--- snapshotting them raw stamped a group fork as the profile's "baseline",
--- and the next layer harvest banked the fork into baselineLayout
--- permanently (the default-layout corruption class). Unlock Save & Exit
--- already honors this via SpecOverrides_UnlockBaselineLinks; every profile
--- snapshot writer must go through here. TBB child-role entries are
--- per-spec bucket data that layers never carry -- they ride from live so a
--- baseline-sourced snapshot does not drop them (mirrors ApplyLayer).
local function SnapshotUnlockLayout()
    if not EllesmereUIDB then return nil end
    local ba, bwm, bhm
    if EllesmereUI.SpecOverrides_UnlockBaselineLinks then
        ba, bwm, bhm = EllesmereUI.SpecOverrides_UnlockBaselineLinks()
    end
    local snap = {
        anchors       = DeepCopy(ba  or EllesmereUIDB.unlockAnchors     or {}),
        widthMatch    = DeepCopy(bwm or EllesmereUIDB.unlockWidthMatch  or {}),
        heightMatch   = DeepCopy(bhm or EllesmereUIDB.unlockHeightMatch or {}),
        phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds or {}),
    }
    if ba then
        for k, v in pairs(EllesmereUIDB.unlockAnchors or {}) do
            if type(k) == "string" and k:find("^TBB_%d+$") then snap.anchors[k] = DeepCopy(v) end
        end
        for k, v in pairs(EllesmereUIDB.unlockWidthMatch or {}) do
            if type(k) == "string" and k:find("^TBB_%d+$") then snap.widthMatch[k] = v end
        end
        for k, v in pairs(EllesmereUIDB.unlockHeightMatch or {}) do
            if type(k) == "string" and k:find("^TBB_%d+$") then snap.heightMatch[k] = v end
        end
    end
    return snap
end

--- Stamp-on-first-touch: a profile with NO unlockLayout snapshot gets one
--- recorded the moment it is activated, sourced from the current (baseline-
--- resolved) live links. This replaces the old "leave the live unlock data
--- untouched" inherit: the inherited links were never RECORDED, so they
--- mutated with every subsequent switch, got baked into whatever profile was
--- switched away from next, and broke the restore contract that snapshots
--- always hold baseline links. Callers stamp BEFORE flipping activeProfile
--- so the baseline source resolves against the OUTGOING store (the store the
--- live tables actually belong to). Brand-new profiles also receive the
--- castbar anchor/width-match defaults the old first-touch branch seeded.
local function StampUnlockLayoutIfMissing(prof)
    if not prof or prof.unlockLayout ~= nil then return end
    local snap = SnapshotUnlockLayout()
    if not snap then return end
    local CB_DEFAULTS = {
        { cb = "playerCastbar", parent = "player" },
        { cb = "targetCastbar", parent = "target" },
        { cb = "focusCastbar",  parent = "focus" },
    }
    for _, def in ipairs(CB_DEFAULTS) do
        if not snap.anchors[def.cb] then
            snap.anchors[def.cb] = { target = def.parent, side = "BOTTOM" }
        end
        if not snap.widthMatch[def.cb] then
            snap.widthMatch[def.cb] = def.parent
        end
    end
    prof.unlockLayout = snap
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
                    -- Override-owned settings never sync: merge both profiles'
                    -- override-entry paths into the static exclusions
                    -- (fail-open -- a derive error keeps the static set).
                    local exclusions = EllesmereUI._syncExclusions and EllesmereUI._syncExclusions[folder]
                    local exFn = EllesmereUI._SyncExclusionsWithOverrides
                    if exFn then
                        local ok, m = pcall(exFn, folder, exclusions, outProf, profileData)
                        if ok and m then exclusions = m end
                    end
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
    -- Callers stamp a missing snapshot BEFORE flipping activeProfile (see
    -- StampUnlockLayoutIfMissing); this is the last-resort stamp for any
    -- flow that missed it. By now the flip already happened, so the baseline
    -- source resolves against the INCOMING store -- for a truly snapshot-less
    -- profile that store is empty and the stamp records raw live (the old
    -- inherit, but RECORDED: the links stop mutating on every switch and the
    -- baseline restore contract holds from here on).
    local ul = profileData.unlockLayout
    if not ul then
        StampUnlockLayoutIfMissing(profileData)
        ul = profileData.unlockLayout
    end
    if ul then
        EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
        EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
        EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
        EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
        -- unlockLayout snapshots always carry BASELINE links (CommitPositions
        -- sources them from the stored baseline layout while a group layer is
        -- live), so live now holds the baseline: reset the incoming profile's
        -- active-layer pointer to match. SpecOverrides_ApplyUnlock re-applies
        -- the right group layer for the incoming spec right after.
        if EllesmereUI.SpecOverrides_UnlockResetActive then
            EllesmereUI.SpecOverrides_UnlockResetActive(profileData)
        end
        -- Buff Manager forks have NO baseline snapshot restore (the RF addon
        -- profile is the live data and travels with the blob), so their
        -- pointer stays consistent -- only orphan pointers are healed.
        if EllesmereUI.SpecOverrides_BmResetActive then
            EllesmereUI.SpecOverrides_BmResetActive(profileData)
        end
        -- Tracking Bar link entries in the snapshot are stale copies of
        -- whichever spec last saved unlock mode -- TBB links are per-spec
        -- (CDM-owned buckets). Re-assert the active spec's own entries over
        -- the freshly restored stores.
        if EllesmereUI._TBBRestoreUnlockLinks then
            EllesmereUI._TBBRestoreUnlockLinks()
        end
    end
    -- (Castbar anchor defaults for brand-new profiles are seeded into the
    -- stamped snapshot by StampUnlockLayoutIfMissing and arrive via the
    -- restore above -- re-seeding live on every load would clobber a user's
    -- deliberate un-anchor the next time the profile is applied.)
    -- Restore fonts and custom colors from the profile
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    -- Custom colors: with "Apply to All Profiles" ON (default) the shared palette
    -- doesn't change with the active profile, so nothing to re-apply on switch.
    -- In per-profile mode (toggle OFF) the colours DO change with the active
    -- profile, so re-apply them. GetCustomColorsDB() resolves the right table
    -- LIVE (edits write straight to the profile's own customColors -- never a
    -- wipe/restore, which is what once let a combat-end spec switch reset colours).
    -- ApplyColorsToOUF self-guards combat on its action-bar branch.
    if EllesmereUIDB and EllesmereUIDB.colorsApplyToAllProfiles == false and EllesmereUI.ApplyColorsToOUF then
        EllesmereUI.ApplyColorsToOUF()
    end
    -- Dark Mode settings are ALWAYS per-profile, so the active profile's dark
    -- palette + darken amounts change on every repoint. Re-read and repaint.
    -- RefreshDarkMode() also runs ApplyColorsToOUF, so the (possibly different)
    -- darken propagates to class/power colours even in global colour mode.
    if EllesmereUI.RefreshDarkMode then
        EllesmereUI.RefreshDarkMode()
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

    -- Stamp BEFORE the flip: the baseline source must resolve against the
    -- OUTGOING store the live link tables belong to.
    StampUnlockLayoutIfMissing(EllesmereUIDB.profiles and EllesmereUIDB.profiles[targetProfile])
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
        -- Host-aware: Dragon Riding's folder is not a loadable addon (it lives
        -- inside BlizzardSkin), so a bare IsAddonLoaded(entry.folder) would drop
        -- it from every full-profile export. IsModuleAddonLoaded resolves through
        -- the hostAddon, matching the per-addon export path (ExportProfile).
        if EllesmereUI.IsModuleAddonLoaded(entry.folder) then
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
    -- Dark Mode palette + darken amounts (always the active profile's own).
    data.darkMode = DeepCopy(EllesmereUI.GetDarkModeDB())
    -- Spec Overrides ride with the profile (freshen the current spec's stored
    -- values from live first so exports never lag recent edits).
    if EllesmereUI.SpecOverrides_HarvestCurrent then
        EllesmereUI.SpecOverrides_HarvestCurrent()
    end
    do
        local prof = EllesmereUIDB and EllesmereUIDB.profiles
            and EllesmereUIDB.profiles[EllesmereUIDB.activeProfile or "Default"]
        if prof and type(prof.specOverrides) == "table" and #prof.specOverrides > 0 then
            data.specOverrides = DeepCopy(prof.specOverrides)
        end
        if prof and type(prof.specOverrideGroups) == "table" and #prof.specOverrideGroups > 0 then
            data.specOverrideGroups = DeepCopy(prof.specOverrideGroups)
            data.specOverrideNextId = prof.specOverrideNextId
        end
        if prof and type(prof.condOverrideGroups) == "table" and #prof.condOverrideGroups > 0 then
            data.condOverrideGroups = DeepCopy(prof.condOverrideGroups)
        end
        if prof and type(prof.condOverrides) == "table" and #prof.condOverrides > 0 then
            data.condOverrides = DeepCopy(prof.condOverrides)
        end
        if prof and type(prof.condUnlockOverrides) == "table" then
            data.condUnlockOverrides = DeepCopy(prof.condUnlockOverrides)
        end
        if prof and type(prof.specUnlockOverrides) == "table" then
            data.specUnlockOverrides = DeepCopy(prof.specUnlockOverrides)
        end
        if prof and type(prof.condBmOverrides) == "table" then
            data.condBmOverrides = DeepCopy(prof.condBmOverrides)
        end
        if prof and type(prof.specBmOverrides) == "table" then
            data.specBmOverrides = DeepCopy(prof.specBmOverrides)
        end
    end
    -- Include unlock mode layout data (anchors, size matches). Baseline-
    -- sourced while a group layer is live (see SnapshotUnlockLayout).
    if EllesmereUIDB then
        data.unlockLayout = SnapshotUnlockLayout()
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

    -- An open unlock session's snapshots and pending edits belong to the
    -- OUTGOING data about to be replaced: discard-close before the wipe
    -- (mirrors SwitchProfile / spec changes / condition flips).
    if EllesmereUI._unlockModeActive and EllesmereUI.ForceCloseUnlockDiscard then
        EllesmereUI.ForceCloseUnlockDiscard()
    end

    -- Any open editing-as session (spec group / conditional / Default view)
    -- must close BEFORE the live tables are wiped and refilled: the exits
    -- bank against the outgoing store, and the post-apply establish
    -- (Conditions_MarkStale + Recheck) refuses to run under a live session,
    -- which would strand the incoming profile un-overlaid ("bricked") until
    -- the next zone change.
    if EllesmereUI.SpecOverrides_CloseEditSessions then
        EllesmereUI.SpecOverrides_CloseEditSessions()
    end

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
                -- Old-profile imports carry customized boss regular text keys
                -- but no simple* twins. Simple Debuff Display defaults ON and
                -- reads the simple* keys, which DeepMergeDefaults fills with
                -- false/14, orphaning the user's stored sizes. The seed
                -- migration (uf_boss_simple_text_seed_v1) is SKIPPED for
                -- imported profiles (inherited migration flags), so
                -- forward-copy here BEFORE the merge masks the nil keys.
                if entry.folder == "EllesmereUIUnitFrames" and type(profile.boss) == "table" then
                    local b = profile.boss
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
                end
                -- Pre-MultiBag imports carry the legacy bagDefaultOneBag boolean
                -- but no bagDefaultBagType. The conversion migration is SKIPPED for
                -- imported profiles (inherited migration flags), so forward-copy
                -- here BEFORE DeepMergeDefaults fills the "all" default and masks
                -- the legacy key from the resolver.
                if entry.folder == "EllesmereUIBags"
                    and profile.bagDefaultBagType == nil and profile.bagDefaultOneBag == true then
                    profile.bagDefaultBagType = "onebag"
                end
                -- Pre-tsMode imports carry tsEnabled/tsRaidEnabled booleans but no
                -- tsMode/tsRaidMode. The bool->mode migration is SKIPPED for imported
                -- profiles (inherited migration flags), so forward-copy here BEFORE
                -- DeepMergeDefaults fills the tsMode default and masks the legacy keys.
                -- Party only: raid hard-defaults to "never" (not migrated), so leave
                -- tsRaidMode unset and let DeepMergeDefaults apply the default.
                if entry.folder == "EllesmereUIRaidFrames" then
                    if profile.tsMode == nil then
                        if profile.tsEnabled == false then profile.tsMode = "never"
                        elseif profile.tsEnabled == true then profile.tsMode = "whenHealing" end
                    end
                end
                -- Pre-split imports carry the legacy single miniboss color but no
                -- boss color. The mini-boss/boss split migration is SKIPPED for
                -- imported profiles (inherited migration flags), so forward-copy
                -- here BEFORE DeepMergeDefaults fills the DEFAULT boss color and
                -- changes the user's boss nameplates.
                if entry.folder == "EllesmereUINameplates"
                    and profile.boss == nil and type(profile.miniboss) == "table" then
                    profile.boss = DeepCopy(profile.miniboss)
                end
                -- Pre-dropdown imports carry the legacy coordsBelow /
                -- clockInside / zoneInside toggles but none of the new mode
                -- keys. The minimap migrations are SKIPPED for imported
                -- profiles (inherited migration flags), so forward-copy here
                -- BEFORE DeepMergeDefaults fills the new defaults and masks
                -- the legacy keys.
                if entry.folder == "EllesmereUIMinimap"
                    and type(profile.minimap) == "table" then
                    local mm = profile.minimap
                    if mm.coordsMode == nil then
                        if mm.coordsBelow then
                            mm.coordsMode = "always"
                            mm.coordsPosition = "belowMap"
                        else
                            mm.coordsMode = "hover"
                            mm.coordsPosition = "topLeft"
                            -- The X/Y nudge only applied in below-map mode; clear
                            -- leftovers so they don't shift the hover coordinates.
                            mm.coordsBelowOffsetX = nil
                            mm.coordsBelowOffsetY = nil
                        end
                    end
                    -- Only pre-dropdown exports (no mode key) are mapped: a
                    -- post-update export can carry a stale showClock/
                    -- hideZoneText alongside a deliberately-set mode, which
                    -- must win. Hidden via the removed Show Blizzard Elements
                    -- Zone/Clock checkboxes maps to "none".
                    if mm.clockMode == nil then
                        if mm.showClock == false then
                            mm.clockMode = "none"
                        else
                            mm.clockMode = (mm.clockInside == false) and "edge" or "inside"
                        end
                    end
                    if mm.locationMode == nil then
                        if mm.hideZoneText == true then
                            mm.locationMode = "none"
                        else
                            mm.locationMode = mm.zoneInside and "inside" or "edge"
                        end
                    end
                    if mm.omniumFolioMode == nil then
                        mm.omniumFolioMode = (mm.showOmniumFolio == false) and "never" or "always"
                    end
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
    -- Apply fonts (account-wide store) ONLY when the profile carries a font
    -- snapshot. A partial import nils profileData.fonts to keep the recipient's
    -- own fonts -- wiping unconditionally here reset them to the default
    -- (Expressway/shadow) instead. Mirrors SwitchProfile's guarded restore.
    -- Custom colours are getter-redirected (GetCustomColorsDB) and must NEVER be
    -- wiped/restored here (see the custom-colours global-mode design).
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    -- Custom colors are GLOBAL appearance, not per-profile: never wipe or
    -- restore EllesmereUIDB.customColors from a profile snapshot. (See the
    -- detailed note in the sibling apply path; this block previously wiped the
    -- live colors UNCONDITIONALLY before a conditional restore, so applying a
    -- profile with no/stale color snapshot reset every custom color to default.)
    -- Restore unlock mode layout data
    if EllesmereUIDB then
        local ul = profileData.unlockLayout
        if ul then
            EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
            EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
            EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
            EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
            -- Tracking Bar link entries in the snapshot are stale copies of
            -- whichever spec last saved unlock mode -- TBB links are
            -- per-spec (CDM-owned buckets). Re-assert the active spec's own
            -- entries over the freshly restored stores.
            if EllesmereUI._TBBRestoreUnlockLinks then
                EllesmereUI._TBBRestoreUnlockLinks()
            end
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
    -- Spec Overrides: write the current spec's override values into the live
    -- profile FIRST, so every module refresh below picks them up. This makes
    -- profile swaps and imports override-correct without their own pass.
    -- (The import-time default re-bank runs SYNCHRONOUSLY inside
    -- ImportProfile, never from here: by the time any RefreshAllAddons fires,
    -- overlays may already be live and re-banking would poison defaults.)
    if EllesmereUI.SpecOverrides_ApplyValues then
        EllesmereUI.SpecOverrides_ApplyValues()
    end
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
    -- Crosshair
    if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
    -- QoL extras (FPS counter + Secondary Stats) -- per-profile, so re-apply on swap
    if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
    if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
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
    -- DataBars (bar set + blocks + layout + positions are all per-profile)
    if _G._EDB_Apply then _G._EDB_Apply() end
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
    if _G._EDB_RegisterUnlock then _G._EDB_RegisterUnlock() end
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
    -- The open options window caches per-profile pages (e.g. the CDM bar
    -- dropdown). A live profile swap re-points db.profile but leaves those cached
    -- pages showing the OLD profile until a /reload. Drop the cache so any page
    -- rebuilds fresh on next view, and rebuild the one on screen now. The profile
    -- DROPDOWN switch already does this inline; routing it through here also
    -- covers profile keybind + spec-driven auto-swaps, which only call us.
    if EllesmereUI.InvalidatePageCache then EllesmereUI:InvalidatePageCache() end
    if EllesmereUI.IsShown and EllesmereUI:IsShown() and EllesmereUI.RefreshPage then
        EllesmereUI:RefreshPage(true)
    end
    -- Conditional overrides: a profile apply swaps every store wholesale, so
    -- the engine's applied pointer refers to the OLD profile's groups. Reset
    -- it and re-establish the overlay against the incoming profile.
    if EllesmereUI.Conditions_MarkStale then
        EllesmereUI.Conditions_MarkStale()
        EllesmereUI.Conditions_Recheck()
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
    -- Unlock spec-overrides: perform any deferred generic-element position
    -- writes and the override settle BEFORE the matches/positions/resync
    -- below, so this pass lays out against the final swapped stores.
    if EllesmereUI.SpecOverrides_FlushUnlock then
        EllesmereUI.SpecOverrides_FlushUnlock()
    end
    if EllesmereUI.ApplyAllWidthHeightMatches then
        EllesmereUI.ApplyAllWidthHeightMatches()
    end
    if EllesmereUI._applySavedPositions then
        EllesmereUI._applySavedPositions()
    end
    if EllesmereUI.ResyncAnchorOffsets then
        EllesmereUI.ResyncAnchorOffsets()
    end
    -- A conditional establish/flip that found the spec pipeline mid-flight
    -- deferred itself (the transition handler returns false while busy).
    -- The pipeline is settled now -- resolve it. No-op when nothing changed.
    if EllesmereUI.Conditions_Recheck then
        EllesmereUI.Conditions_Recheck()
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
        local skinsWillChange = EllesmereUI.ProfileChangesWindowSkins(profiles and profiles[profileName])
        EllesmereUI.SwitchProfile(profileName)
        EllesmereUI.RefreshAllAddons()
        if fontWillChange or skinsWillChange then
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = fontWillChange
                    and "Font changed. A UI reload is needed to apply the new font."
                    or "Window skins changed for this profile. A UI reload is needed to apply them.",
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

--- Returns true if switching to profileData would cross the per-profile
--- "Disable Window Skins" flag in either direction. Skins install at load,
--- so a crossing needs a UI reload to fully apply -- callers pair this with
--- the same reload popup as the font check above. Must be called BEFORE
--- the switch (compares the CURRENT active profile root against the target).
function EllesmereUI.ProfileChangesWindowSkins(profileData)
    if type(profileData) ~= "table" then return false end
    local cur = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
    local a = (cur and cur.disableWindowSkins) and true or false
    local b = profileData.disableWindowSkins and true or false
    return a ~= b
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

-- Snapshot the per-profile CDM spell allocation (which spells sit on which bars +
-- per-spell settings, per spec) for export. The bar DEFINITIONS already travel in
-- the addon blob; this carries the content that sits on them. Strips the sharer's
-- ghost bar + migration flags so the importer rebuilds ghosting against THEIR own
-- tracked spells. Returns nil when there's nothing to carry, or when the CDM addon
-- itself isn't part of a subset export.
local function SnapshotProfileCDMSpells(profileName, includedFolders, cdmSpecs)
    if includedFolders and not includedFolders["EllesmereUICooldownManager"] then return nil end
    -- Reconcile the ACTIVE spec's default-bar store against the live icons
    -- before snapshotting: untouched base-bar spells render via the
    -- frames-as-truth fallback without being recorded, and an export taken
    -- before the login reseed ran would ship them missing (the importer's
    -- ghost pass then hides them). No-ops when the CDM child is disabled,
    -- when an import's ghosting is pending, or when no live icons exist.
    if EllesmereUI.CDMReconcileActiveSpecSpells then
        EllesmereUI.CDMReconcileActiveSpecSpells()
    end
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    local bucket = sa and sa.profiles and sa.profiles[profileName]
    if not bucket or type(bucket.specProfiles) ~= "table" or not next(bucket.specProfiles) then
        return nil
    end
    -- cdmSpecs (a set keyed by string specKey) limits the export to the chosen
    -- specs; nil = every spec with data.
    local snap = {}
    for specKey, specProf in pairs(bucket.specProfiles) do
        if type(specProf) == "table" and (not cdmSpecs or cdmSpecs[specKey]) then
            local copy = DeepCopy(specProf)
            if type(copy.barSpells) == "table" then copy.barSpells.__ghost_cd = nil end
            copy._barFilterModelV6 = nil
            copy._importGhostMode = nil
            snap[specKey] = copy
        end
    end
    if not next(snap) then return nil end
    return snap
end

-- Collect the spec IDs the account-global spec->profile map currently points at
-- this profile. Embedded in every export as a flat list of spec IDs; the importer
-- only applies them when "Auto Assign to Specs" is enabled. Returns nil when the
-- profile is not assigned to any spec (the common case), so the field is absent.
local function CollectAssignedSpecs(profileName)
    local sp = EllesmereUIDB and EllesmereUIDB.specProfiles
    if type(sp) ~= "table" then return nil end
    local list
    for specID, prof in pairs(sp) do
        if prof == profileName then
            list = list or {}
            list[#list + 1] = specID
        end
    end
    return list
end

function EllesmereUI.ExportProfile(profileName, includedFolders, includeLayout, includeCDM, cdmSpecs, includeGlobals)
    if includeLayout == nil then includeLayout = true end  -- default ON
    if includeCDM == nil then includeCDM = false end  -- default OFF (opt-in, spec-picked)
    if includeGlobals == nil then includeGlobals = true end  -- default ON ("Include Global Settings")
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    -- If exporting the active profile, ensure fonts/colors/layout are current
    if profileName == (db.activeProfile or "Default") then
        profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        profileData.darkMode = DeepCopy(EllesmereUI.GetDarkModeDB())
        profileData.unlockLayout = SnapshotUnlockLayout()
    end
    local exportData = DeepCopy(profileData)
    -- Import-window guard flag (see ImportProfile) is recipient-local state;
    -- never let it ride an export string.
    exportData._importEstablishPending = nil
    -- UI accent color (per-profile): serialize the RESOLVED accent for THIS
    -- profile (works for active and non-active profiles; never mutates the
    -- stored profile, and is rename-immune since it is a data-root field, not
    -- an addons[] folder key).
    do
        local u, r, g, b = EllesmereUI.ResolveProfileAccent(profileData)
        -- Serialize useClass explicitly (see SnapshotAllAddons).
        exportData.euiAccent = { useClass = u, custom = (not u) and { r = r, g = g, b = b } or nil }
    end
    -- UI scale (account-wide) rides with a FULL profile so an importer can opt
    -- to match the scale the profile was designed at. Concrete number; absent
    -- when never set (old profiles carry no scale to exclude). Dropped on a
    -- subset export below alongside the other profile-global appearance.
    exportData.uiScale = (EllesmereUIDB and type(EllesmereUIDB.ppUIScale) == "number")
        and EllesmereUIDB.ppUIScale or nil
    -- Only export addons that are actually loaded (supports standalone installs)
    -- When includedFolders is provided, further filter to user's selection
    if exportData.addons then
        for folder in pairs(exportData.addons) do
            if not EllesmereUI.IsModuleAddonLoaded(folder) then
                exportData.addons[folder] = nil
            elseif includedFolders and not includedFolders[folder] then
                exportData.addons[folder] = nil
            end
        end
    end
    -- Exclude spec-specific data from export
    exportData.trackedBuffBars = nil
    exportData.tbbPositions = nil
    -- Legacy account-wide spell store never travels (the per-profile snapshot below
    -- carries CDM content instead).
    exportData.spellAssignments = nil
    -- CDM spell allocation travels WITH the profile: which spells sit on which bars
    -- + per-spell settings, per spec. Bar definitions already ride in the addon blob.
    if includeCDM then
        exportData.cdmSpells = SnapshotProfileCDMSpells(profileName, includedFolders, cdmSpecs)
    end
    -- Spec->profile assignments (which specs auto-load this profile) ride along as
    -- a flat spec-ID list. Always embedded; the importer only applies it when the
    -- recipient enables "Auto Assign to Specs". nil when unassigned.
    exportData.assignedSpecs = CollectAssignedSpecs(profileName)
    -- HoverCast (click-cast) bindings are account-global, not per-profile. They
    -- live at EllesmereUIDB.clickCast (top-level, parallel to spellAssignments),
    -- so importing someone else's profile must never overwrite the user's own
    -- click-cast setup. Strip defensively in case a payload ever carries it.
    exportData.clickCast = nil
    -- fonts/customColors/darkMode/euiAccent are profile-GLOBAL appearance and are
    -- not separable per-addon, so a subset export must not carry them (they'd
    -- clobber the recipient's). Only a full-profile export carries them.
    if includedFolders then
        -- UI scale has its own dedicated import toggle and never rides a subset
        -- export (it is not part of "Include Global Settings").
        exportData.uiScale = nil
        -- Profile-global appearance (fonts, custom colours, dark mode, accent)
        -- rides a per-addon export only when "Include Global Settings" is on
        -- (default). Off = the recipient keeps their own look.
        if not includeGlobals then
            exportData.fonts        = nil
            exportData.customColors = nil
            exportData.darkMode     = nil
            exportData.euiAccent    = nil
        end
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
    -- Spec-group / conditional unlock-layer FORKS (whole cross-module position
    -- layers, specUnlockOverrides/condUnlockOverrides): governed by the same
    -- "Include layout" toggle, and they NEVER ride a subset export -- the
    -- layers are not per-module separable, and the import-side subset strip
    -- only triggers when the RECIPIENT deselects payload modules, so an
    -- export-side subset used to smuggle the exporter's full fork set through
    -- (wiping or replacing the recipient's own group layouts on import).
    if not includeLayout or includedFolders then
        exportData.specUnlockOverrides = nil
        exportData.condUnlockOverrides = nil
    end
    -- Layout deliberately excluded: mark it so the store merge KEEPS the
    -- recipient's fork stores instead of reading the stripped (nil) tables
    -- as "exporter had none, wipe yours" (see MergeImportedStores).
    if not includeLayout then
        exportData.layoutExcluded = true
    end
    -- A subset export IS a partial import regardless of what the recipient
    -- checks: stamp it at the source so the store merge takes the same
    -- keep-existing subset path the import dialog stamps on deselection.
    if includedFolders then
        exportData.partialImport = true
    end
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

        -- Optional: specs that are forced ON and cannot be toggled (numeric IDs).
        -- opts.lockedSpecs is a set keyed by string specKey; value may be a
        -- tooltip string (or true). opts.disabledSpecs likewise grays specs out.
        local lockedOnSpecs, disabledSpecs = {}, {}
        if opts.lockedSpecs then
            for k, v in pairs(opts.lockedSpecs) do
                local numID = tonumber(k)
                if numID and v then lockedOnSpecs[numID] = v end
            end
        end
        if opts.disabledSpecs then
            for k, v in pairs(opts.disabledSpecs) do
                local numID = tonumber(k)
                if numID and v then disabledSpecs[numID] = v end
            end
        end

        EllesmereUI:ShowSpecAssignPopup({
            db              = dummyDB,
            dbKey           = "_cdmPick",
            presetKey       = "_cdm",
            title           = opts.title,
            subtitle        = opts.subtitle,
            subtitleColor   = opts.subtitleColor,
            subtitleAtBottom = opts.subtitleAtBottom,
            buttonText      = opts.confirmText or "Confirm",
            disabledSpecs   = disabledSpecs,
            lockedOnSpecs   = lockedOnSpecs,
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

function EllesmereUI.ExportCurrentProfile(includeLayout, includeCDM, cdmSpecs)
    if includeLayout == nil then includeLayout = true end  -- default ON
    if includeCDM == nil then includeCDM = false end  -- default OFF (opt-in, spec-picked)
    local profileData = EllesmereUI.SnapshotAllAddons()
    -- Legacy account-wide spell store never travels (the per-profile snapshot below
    -- carries CDM content instead).
    profileData.spellAssignments = nil
    -- CDM spell allocation travels WITH the profile (see SnapshotProfileCDMSpells).
    local activeName = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if includeCDM then
        profileData.cdmSpells = SnapshotProfileCDMSpells(activeName, nil, cdmSpecs)
    end
    -- Spec->profile assignments ride along; applied on import only via "Auto
    -- Assign to Specs". nil when this profile is not assigned to any spec.
    profileData.assignedSpecs = CollectAssignedSpecs(activeName)
    -- HoverCast (click-cast) bindings are account-global, not per-profile; never export.
    profileData.clickCast = nil
    -- UI scale (account-wide) rides with the full profile (see ExportProfile).
    profileData.uiScale = (EllesmereUIDB and type(EllesmereUIDB.ppUIScale) == "number")
        and EllesmereUIDB.ppUIScale or nil
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

-------------------------------------------------------------------------------
--  Async import decode
--
--  DecodeImportString runs decode -> decompress -> deserialize in one
--  synchronous call; on very large strings that stalls the client for
--  seconds. DecodeImportStringAsync produces the identical payload but
--  spreads the work across frames on a small per-frame time budget:
--    - the printable decode runs in fixed-size slices (the codec is
--      block-based, so slicing on 4-char boundaries is lossless),
--    - decompression uses the client's native inflate when available
--      (LibDeflate fallback otherwise -- both read the same deflate stream),
--    - deserialization yields through the Serializer hook above.
--
--  onDone(payload, err) fires exactly once -- on a later frame, or
--  immediately for the cheap validation failures. onProgress(fraction) is
--  optional and approximate, for UI feedback. Returns a handle with
--  :Cancel() (drops the run; onDone never fires), or nil when onDone was
--  already called synchronously. Starting a new run cancels an active one.
-------------------------------------------------------------------------------
do
    local BUDGET_MS = 8       -- per-frame work slice
    local SLICE_LEN = 65536   -- printable-decode slice (multiple of 4)

    local driver    -- shared OnUpdate frame, hidden while idle
    local active    -- state table of the in-flight run, or nil

    local function StopRun(run)
        if active == run then
            active = nil
            Serializer.SetYieldHook(nil)
            if driver then driver:Hide() end
        end
    end

    function EllesmereUI.DecodeImportStringAsync(importStr, onDone, onProgress)
        -- Cheap validations first (same messages as DecodeImportString).
        if not importStr or #importStr < 5 then
            onDone(nil, "Invalid string")
            return nil
        end
        if importStr:sub(1, 9) == "!EUICDM_" then
            onDone(nil, "This is an old CDM Bar Layout string. This format is no longer supported. Use the standard profile import instead.")
            return nil
        end
        if importStr:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
            onDone(nil, "Not a valid EllesmereUI string. Make sure you copied the entire string.")
            return nil
        end
        if not LibDeflate then
            onDone(nil, "LibDeflate not available")
            return nil
        end

        if active then StopRun(active) end
        local run = {}
        active = run

        local sliceStart = 0
        local function Yield(frac)
            if onProgress and frac then onProgress(frac) end
            -- Only ever yield our own coroutine: the Serializer hook stays
            -- installed while this run is parked, and a synchronous
            -- Deserialize from elsewhere must never be yielded.
            if coroutine.running() ~= run.co then return end
            if debugprofilestop() - sliceStart > BUDGET_MS then
                coroutine.yield()
            end
        end

        run.co = coroutine.create(function()
            local encoded = importStr:sub(#EXPORT_PREFIX + 1)

            -- Printable decode in slices (block codec: 4 chars -> 3 bytes,
            -- so any 4-char boundary is a clean cut; the tail of the final
            -- slice is handled by the codec itself).
            local total = #encoded
            local pieces, pn = {}, 0
            local i = 1
            while i <= total do
                local j = i + SLICE_LEN - 1
                if j > total then j = total end
                local piece = LibDeflate:DecodeForPrint(encoded:sub(i, j))
                if not piece then return nil, "Failed to decode string" end
                pn = pn + 1
                pieces[pn] = piece
                i = j + 1
                Yield((i / total) * 0.4)
            end
            local decoded = table.concat(pieces)
            pieces = nil
            Yield(0.42)

            -- Decompress: native inflate when the client provides it, else
            -- LibDeflate (single call). A native failure of any kind just
            -- falls through to the library path.
            local decompressed
            if C_EncodingUtil and C_EncodingUtil.DecompressString
               and Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate then
                local ok, res = pcall(C_EncodingUtil.DecompressString, decoded,
                    Enum.CompressionMethod.Deflate)
                if ok and type(res) == "string" and #res > 0 then
                    decompressed = res
                end
            end
            if not decompressed then
                decompressed = LibDeflate:DecompressDeflate(decoded)
            end
            if not decompressed then return nil, "Failed to decompress data" end
            decoded = nil
            Yield(0.5)

            -- Deserialize with the cooperative hook installed.
            local dtotal = #decompressed
            Serializer.SetYieldHook(function(pos)
                Yield(0.5 + (pos / dtotal) * 0.5)
            end)
            local payload = Serializer.Deserialize(decompressed)
            Serializer.SetYieldHook(nil)

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
        end)

        local function Step()
            if active ~= run then
                if driver then driver:Hide() end
                return
            end
            sliceStart = debugprofilestop()
            local ok, payload, perr = coroutine.resume(run.co)
            if not ok then
                StopRun(run)
                onDone(nil, "Failed to read import data")
                return
            end
            if coroutine.status(run.co) == "dead" then
                StopRun(run)
                onDone(payload, perr)
            end
        end

        if not driver then
            driver = CreateFrame("Frame")
            driver:Hide()
        end
        driver:SetScript("OnUpdate", Step)
        driver:Show()

        run.Cancel = function() StopRun(run) end
        return run
    end
end

-------------------------------------------------------------------------------
--  Spell Layout string codec (CDM spell layouts -- SEPARATE from profiles)
--
--  Reuses the same serializer + deflate pipeline as profile export, but with a
--  distinct prefix ("!EUISL_") so the two string kinds can never be confused,
--  and with NO profile version gate -- spell layouts carry their own schema
--  version inside the payload (payload.version). Kept here so the Serializer /
--  LibDeflate locals stay in one place. The CDM layout system
--  (EllesmereUICdmLayouts.lua) calls these; they never touch any profile data.
-------------------------------------------------------------------------------
function EllesmereUI.EncodeLayoutString(payload)
    if type(payload) ~= "table" then return nil, "Invalid payload" end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local serialized = Serializer.Serialize(payload)
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return "!EUISL_" .. encoded
end

function EllesmereUI.DecodeLayoutString(str)
    if type(str) ~= "string" or #str < 7 then return nil, "Invalid string" end
    if str:sub(1, 7) ~= "!EUISL_" then
        return nil, "Not a valid EllesmereUI Spell Layout string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = str:sub(8)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if type(payload) ~= "table" then return nil, "Failed to deserialize data" end
    return payload, nil
end

-------------------------------------------------------------------------------
--  Imported media reconciliation
--
--  A profile string can reference SharedMedia statusbar textures that are
--  not installed on the importing client. LSM silently substitutes its
--  default texture in that case, so the import renders with swapped-in bars
--  and no visible cue that files are missing. For media families known to
--  ship as their own separate install, pin any dangling references to the
--  "Texture Not Found" placeholder texture at import time instead: the
--  affected bars render empty and the selection reads as exactly what
--  happened (clearly missing rather than subtly wrong), and the user can
--  pick any texture from the normal dropdowns afterwards.
--
--  One-shot by design: this rewrites only the incoming payload inside
--  ImportProfile, before it is merged or stored. Existing profiles, presets,
--  exports, profile sync and runtime media resolution are never touched.
--  Media families are matched by signature; per repo convention third-party
--  addon/pack names are not embedded in source.
-------------------------------------------------------------------------------
local RECONCILE_TEX_NAME = "Texture Not Found"
local RECONCILE_TEX_PATH = [[Interface\AddOns\EllesmereUI\media\textures\blank.tga]]

-- Register the placeholder through the same channel real media uses (LSM),
-- so pinned values resolve everywhere -- every texture lookup table and
-- dropdown picks it up -- with no special cases downstream.
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        LSM:Register(LSM.MediaType.STATUSBAR, RECONCILE_TEX_NAME, RECONCILE_TEX_PATH)
    end
end

-- Signatures (djb2) of texture names known to ship as separate installs.
local RECONCILE_BAR_SIGS = {
    [3860001264] = true,
    [1502800144] = true,
    [1922316589] = true,
    [3302863399] = true,
    [2397640933] = true,
    [3314165376] = true,
    [2062452265] = true,
}

local function ReconcileImportedMedia(data)
    if type(data) ~= "table" then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end

    local function Signature(s)
        local h = 5381
        for i = 1, #s do
            h = (h * 33 + s:byte(i)) % 4294967296
        end
        return h
    end

    local function Walk(t, depth)
        if depth > 40 then return end
        for k, v in pairs(t) do
            if type(v) == "table" then
                Walk(v, depth + 1)
            elseif type(v) == "string" and #v >= 9 and #v <= 26 then
                -- Saved texture values are either plain names or carry the
                -- "sm:" dropdown key prefix.
                local base = v:match("^sm:(.+)") or v
                if RECONCILE_BAR_SIGS[Signature(base)] then
                    if not LSM:Fetch("statusbar", base, true) then
                        t[k] = "sm:" .. RECONCILE_TEX_NAME
                    end
                end
            end
        end
    end

    Walk(data, 1)
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
    if profile.health then
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
    -- Accepts either an encoded string or an already-decoded payload table.
    -- The options import page decodes asynchronously and passes the table,
    -- which skips a full re-encode/re-decode of the data at commit time.
    local payload, err
    if type(importStr) == "table" then
        payload = importStr
    else
        payload, err = EllesmereUI.DecodeImportString(importStr)
    end
    if not payload then return false, err end

    -- Normalize canonical (suite) addon keys -> this build's local db.folder
    -- keys, so a suite string imports into a standalone (and vice versa). Runs
    -- before all downstream addon-key handling. No-op in the suite.
    if payload.data and payload.data.addons then
        payload.data.addons = CanonToLocal(payload.data.addons)
    end

    -- Reconcile media references against locally installed SharedMedia before
    -- the payload is merged or stored (see Imported media reconciliation above).
    ReconcileImportedMedia(payload.data)

    local db = GetProfilesDB()

    if payload.type == "cdm_spells" then
        return false, "This is a CDM Bar Layout string, not a profile string."
    end

    -- Resolve the current spec so we can (a) honor "Auto Assign to Specs" if the
    -- payload carries spec assignments and (b) decide whether the freshly imported
    -- profile may auto-apply. The auto-apply gate (specLocked) is finalized AFTER
    -- any auto-assign below, since assigning the current spec to this profile makes
    -- activating it correct rather than locked.
    local curSpecID
    do
        local si = GetSpecialization and GetSpecialization() or 0
        curSpecID = si and si > 0 and GetSpecializationInfo(si) or nil
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

        -- UI scale (account-wide) is applied ONLY when the importer explicitly
        -- opted in: the import page's "Exclude UI Scale" toggle defaults ON, so
        -- the applyUIScale marker is absent by default, and a raw-string / Wago
        -- import (no options UI) never sets it either -- the user's own scale is
        -- left untouched. Writing the account keys here lets the caller's imminent
        -- reload apply the new scale (EllesmereUI_Startup reads ppUIScale). Range
        -- matches PP.PixelBestSize's clamp; out-of-range values are ignored.
        if payload.data.applyUIScale and type(payload.data.uiScale) == "number" and EllesmereUIDB then
            local s = payload.data.uiScale
            if s >= 0.40 and s <= 1.15 then
                EllesmereUIDB.ppUIScale = s
                EllesmereUIDB.ppUIScaleAuto = false
            end
        end

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
        if imported.darkMode then merged.darkMode = DeepCopy(imported.darkMode) end
        -- Override stores: union-merge with incoming priority, the fork drop
        -- rules, and a post-apply default re-baseline (kept stores' defaults
        -- are stale against the imported values -- restoring them when an
        -- override deactivates would overwrite the imported profile's own
        -- settings). Full semantics in SpecOverrides_MergeImportedStores.
        if EllesmereUI.SpecOverrides_MergeImportedStores then
            EllesmereUI.SpecOverrides_MergeImportedStores(merged, imported)
        end
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
                -- CONTRACT (see SnapshotUnlockLayout): while a spec/cond
                -- group's unlock layer is LIVE, the raw globals hold that
                -- FORK's links -- overlaying them raw stamped the fork as
                -- the new profile's baseline (the one snapshot writer the
                -- Cluster-A hardening missed: importing while playing a
                -- forked spec leaked its geometry onto every spec of the
                -- new profile). Source through the same baseline-resolved
                -- snapshot every other writer uses; TBB child entries are
                -- carried from live inside it.
                local liveSnap = SnapshotUnlockLayout()
                if liveSnap then
                    overlayLive(baseUL.anchors,     liveSnap.anchors)
                    overlayLive(baseUL.widthMatch,  liveSnap.widthMatch)
                    overlayLive(baseUL.heightMatch, liveSnap.heightMatch)
                end
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
        -- CDM spell allocation: apply the imported per-profile spell store (which
        -- spells sit on which bars + per-spell settings) into THIS profile's store,
        -- and arm import-authoritative ghosting so the importer's tracked-but-unplaced
        -- spells get HIDDEN (not spilled onto a default bar) once the profile is
        -- active. Bar definitions already arrived in the addon blob, so the bar keys
        -- match by construction. Older strings (no cdmSpells) skip this untouched.
        if type(payload.data.cdmSpells) == "table" and EllesmereUIDB then
            EllesmereUIDB.spellAssignments = EllesmereUIDB.spellAssignments or { profiles = {} }
            local sa = EllesmereUIDB.spellAssignments
            sa.profiles = sa.profiles or {}
            local bucket = sa.profiles[profileName] or {}
            sa.profiles[profileName] = bucket
            bucket.specProfiles = DeepCopy(payload.data.cdmSpells)
            local importedBarsCfg = payload.data.addons
                and payload.data.addons["EllesmereUICooldownManager"]
                and payload.data.addons["EllesmereUICooldownManager"].cdmBars
                and payload.data.addons["EllesmereUICooldownManager"].cdmBars.bars
            for _, specProf in pairs(bucket.specProfiles) do
                if type(specProf) == "table" then
                    if type(specProf.barSpells) == "table" then specProf.barSpells.__ghost_cd = nil end
                    specProf._barFilterModelV6 = nil    -- re-run the migration on activate
                    specProf._importGhostMode  = true   -- ghost tracked-but-unplaced spells
                    specProf._dormantMerged    = true   -- imported data is already current-model
                    -- Old-format strings (pre tiered-settings) carry per-bar
                    -- spellSettings; transform NOW so the live session reads the
                    -- new shape (the registered migration also covers it on the
                    -- next reload -- both idempotent, flag lives in the bucket).
                    if EllesmereUI.MigrateCdmSpellSettingsShape then
                        EllesmereUI.MigrateCdmSpellSettingsShape(specProf, importedBarsCfg)
                    end
                    -- Hosted-buff settings moved family stores (CD -> BUFF);
                    -- relocate old-format imports the same way (idempotent).
                    if EllesmereUI.MigrateCdmHostedBuffSettings then
                        EllesmereUI.MigrateCdmHostedBuffSettings(specProf)
                    end
                    -- Strings exported before _buffDisplayOrderUserModified
                    -- existed carry a drag-arranged buffDisplayOrder without
                    -- the flag; stamp it or the first live reconcile resyncs
                    -- the imported order to Blizzard order (idempotent).
                    if EllesmereUI.MigrateCdmBuffOrderUserFlag then
                        EllesmereUI.MigrateCdmBuffOrderUserFlag(specProf)
                    end
                end
            end
        end
        -- Old-format strings can carry the per-bar Custom Active State Decimals
        -- keys (bd.faDecimals*); convert them to the per-spell Threshold Text
        -- stamps the same way the login migration does (the old keys are
        -- consumed, so this is idempotent). Runs outside the cdmSpells guard:
        -- even a string without a spell store must have its bar keys retired.
        if EllesmereUI.MigrateCdmThresholdText then
            local importedCdm = merged.addons and merged.addons["EllesmereUICooldownManager"]
            if type(importedCdm) == "table" then
                local sa2 = EllesmereUIDB and EllesmereUIDB.spellAssignments
                local bucket2 = sa2 and sa2.profiles and sa2.profiles[profileName]
                local sp2 = type(bucket2) == "table" and bucket2.specProfiles or nil
                EllesmereUI.MigrateCdmThresholdText(importedCdm, sp2)
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

        -- "Auto Assign to Specs": the exporter's spec->profile assignments ride in
        -- payload.data.assignedSpecs (a flat list of spec IDs). The import UI strips
        -- this field unless the recipient enabled the toggle, so its mere presence
        -- means "apply": point each listed spec at the newly imported profile.
        if type(payload.data.assignedSpecs) == "table" then
            for _, specID in ipairs(payload.data.assignedSpecs) do
                if type(specID) == "number" then
                    db.specProfiles[specID] = profileName
                end
            end
        end

        -- Finalize the auto-apply gate. If the current spec is assigned to a
        -- DIFFERENT profile (a pre-existing assignment, or an auto-assign just
        -- applied to other specs), the spec auto-switch would immediately pull us
        -- off this profile, so save it but don't activate. If the current spec is
        -- unassigned -- or was just auto-assigned to THIS profile -- activate.
        local assignedNow = curSpecID and db.specProfiles[curSpecID]
        if assignedNow and assignedNow ~= profileName then
            -- Stored but not activated: migrate legacy Resource Bars Advanced
            -- data now (the runner's flag was inherited from the base profile,
            -- so it would never run for this import otherwise).
            if EllesmereUI.MigrateRBAdvancedProfile then
                EllesmereUI.MigrateRBAdvancedProfile(db.profiles[profileName])
            end
            -- Import window guard, spec_locked flavor: the merged profile was
            -- built on the dirty active profile all the same, so its first
            -- ACTIVATION (e.g. a later login preseeding onto an auto-assigned
            -- spec) hits the same unguarded pre-apply harvest as a direct
            -- import. The flag sits inert while the profile is stored;
            -- whichever session first activates it clears it at its first
            -- apply. Runtime armed flag deliberately NOT set here: this
            -- session keeps its own active profile.
            db.profiles[profileName]._importEstablishPending = true
            return true, nil, "spec_locked"
        end
        -- Flush the OUTGOING (currently active) profile's LIVE unlock data into its
        -- snapshot BEFORE switching to the imported profile. The live
        -- EllesmereUIDB.unlock* tables are the source of truth; a profile's stored
        -- unlockLayout only LAGS them (it is refreshed on switch-away/export, not
        -- continuously). SwitchProfile does this flush (~2326); import did NOT -- so
        -- importing, switching back to the old profile (which then restored its
        -- STALE snapshot over the live anchors), then deleting the import silently
        -- dropped every anchor / width-match the user had set on the old profile
        -- since it was last saved (they survived only inside the imported profile,
        -- so deleting it lost them for good). This is the reported "bars lose their
        -- anchors and width match after import" bug.
        -- Spec Overrides: sync the outgoing profile's current-spec values
        -- with live edits before the imported profile takes over.
        if EllesmereUI.SpecOverrides_HarvestCurrent then
            EllesmereUI.SpecOverrides_HarvestCurrent()
        end
        local outgoing = db.profiles[db.activeProfile or "Default"]
        if outgoing and EllesmereUIDB then
            outgoing.unlockLayout = SnapshotUnlockLayout()
        end
        -- Make it the active profile and re-point db references (stamp a
        -- missing unlockLayout before the flip -- see StampUnlockLayoutIfMissing)
        StampUnlockLayoutIfMissing(db.profiles[profileName])
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        -- Import window guard: suppress unlock/BM LAYOUT banks from now until
        -- the first apply of a later session. The imported store already holds
        -- the exporter's layers verbatim; live geometry in this window is
        -- mid-import residue (inherited link tables, unconverged anchors), and
        -- any boundary harvest -- the import-tail Conditions recheck, the
        -- caller's ReloadUI firing PLAYER_LOGOUT, the first post-login spec
        -- transition -- would wholesale-replace a pristine bucket with it.
        -- Persisted on the profile root so it survives the reload; the
        -- companion runtime flag stops THIS session's applies (the
        -- SpecOverrides_Apply below) from closing the window early. Cleared
        -- unconditionally at the first apply of any later session; value
        -- harvests are never suppressed.
        db.profiles[profileName]._importEstablishPending = true
        EllesmereUI._importGuardArmedNow = true
        -- Custom colours resolve live via GetCustomColorsDB. In GLOBAL colour
        -- mode the shared palette comes from colorsPullFrom (or the first
        -- profile); a recipient who pinned a specific source would store the
        -- imported palette but keep seeing their own. When the import actually
        -- carries colours, point the global source at the imported profile so
        -- its palette is what shows. Getter-redirect only -- never wipes or
        -- restores a live colour table (that is banned). Per-profile mode reads
        -- the active (now imported) profile already, so it needs no change.
        if imported.customColors and EllesmereUIDB
           and EllesmereUIDB.colorsApplyToAllProfiles ~= false then
            EllesmereUIDB.colorsPullFrom = profileName
        end
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
        -- Resource Bars: migrate legacy Advanced/per-spec-enable data carried
        -- by old export strings (ApplyProfileData refilled the live RB table
        -- from the raw payload, so this must run after it). Idempotent.
        if EllesmereUI.MigrateRBAdvancedProfile then
            EllesmereUI.MigrateRBAdvancedProfile(db.profiles[profileName])
        end
        -- NO default re-bank here. The imported entries carry the EXPORTER's
        -- recorded values.default, consistent with the imported addon blobs
        -- by construction (MergeImportedStores partitions per folder). The
        -- old SpecOverrides_RebaselineDefaults pass overwrote those recorded
        -- defaults with the imported LIVE blob -- which holds the exporter's
        -- CURRENT SPEC's override values (SnapshotAllAddons restores
        -- canonical spec values, not defaults) -- permanently destroying the
        -- exporter's true defaults and bleeding one spec's values into every
        -- unassigned spec on the recipient.
        -- Spec Overrides: apply the imported profile's stored values for the
        -- current spec on top of the just-applied addon data.
        if EllesmereUI.SpecOverrides_Apply then
            EllesmereUI.SpecOverrides_Apply(curSpecID)
        end
        -- Don't ReloadUI() here: the caller (options panel import flow)
        -- reloads unconditionally right after this returns. (The old CDM
        -- spec-picker popup flow is gone -- CDM spells import as-is.)
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
        if payload.data.darkMode then
            merged.darkMode = DeepCopy(payload.data.darkMode)
        end
        if payload.data.specOverrides then
            merged.specOverrides = DeepCopy(payload.data.specOverrides)
        end
        if payload.data.specOverrideGroups then
            merged.specOverrideGroups = DeepCopy(payload.data.specOverrideGroups)
            merged.specOverrideNextId = payload.data.specOverrideNextId
        end
        if payload.data.condOverrideGroups then merged.condOverrideGroups = DeepCopy(payload.data.condOverrideGroups) end
        if payload.data.condOverrides then merged.condOverrides = DeepCopy(payload.data.condOverrides) end
        if payload.data.condUnlockOverrides then merged.condUnlockOverrides = DeepCopy(payload.data.condUnlockOverrides) end
        if payload.data.specUnlockOverrides then
            merged.specUnlockOverrides = DeepCopy(payload.data.specUnlockOverrides)
        end
        if payload.data.condBmOverrides then merged.condBmOverrides = DeepCopy(payload.data.condBmOverrides) end
        if payload.data.specBmOverrides then
            merged.specBmOverrides = DeepCopy(payload.data.specBmOverrides)
        end
        -- Kept override stores survive a partial import by design (the base
        -- profile continues), but BM forks are Raid Frames-scoped: drop kept
        -- ones when the payload replaces RF settings they were built against.
        -- UN-PARKING NOTE: this branch only STORES the profile (never
        -- activates it), so it must NOT call SpecOverrides_RebaselineDefaults
        -- here -- that re-banks the ACTIVE profile's stores. When this branch
        -- is revived, run the re-bank synchronously at activation time,
        -- scoped to payload.data.addons folders (mirror the full-import call
        -- after ApplyProfileData). Never a deferred flag: the import flow
        -- ends in ReloadUI, which destroys in-memory state.
        do
            local folders = {}
            if payload.data and payload.data.addons then
                for folder in pairs(payload.data.addons) do folders[folder] = true end
            end
            if folders["EllesmereUIRaidFrames"] then
                if not payload.data.specBmOverrides then merged.specBmOverrides = nil end
                if not payload.data.condBmOverrides then merged.condBmOverrides = nil end
            end
        end
        -- Resource Bars: migrate legacy Advanced data from old export strings.
        if EllesmereUI.MigrateRBAdvancedProfile then
            EllesmereUI.MigrateRBAdvancedProfile(merged)
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
        StampUnlockLayoutIfMissing(db.profiles[profileName])
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
    -- Freshen the override stores from live before snapshotting (same as the
    -- export path): the whole-profile DeepCopy below carries every override
    -- store with it, and without this bank the current spec's most recent
    -- override edits could lag one harvest boundary behind.
    if EllesmereUI.SpecOverrides_HarvestCurrent then
        EllesmereUI.SpecOverrides_HarvestCurrent()
    end
    local src = db.profiles[current]

    -- Count existing profiles BEFORE adding the new one
    local profileCountBefore = 0
    for _ in pairs(db.profiles) do profileCountBefore = profileCountBefore + 1 end

    -- Count existing profiles BEFORE adding the new one
    -- Deep-copy the current profile into the new name
    local copy = src and DeepCopy(src) or {}
    -- Never inherit the import-window guard flag (see ImportProfile).
    copy._importEstablishPending = nil
    -- Ensure fonts/colors/unlock layout are current
    copy.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    copy.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    copy.darkMode = DeepCopy(EllesmereUI.GetDarkModeDB())
    copy.unlockLayout = SnapshotUnlockLayout()
    db.profiles[name] = copy

    -- CDM spell content lives in the per-profile spell store at
    -- EllesmereUIDB.spellAssignments.profiles[<name>], OUTSIDE the profile blob.
    -- DeepCopy(src) above carried only the bar DEFINITIONS (in the addon blob),
    -- NOT the spell allocations / per-icon settings / RPT-sync specs / TBB
    -- broadcast set that ride on this bucket. Fork the whole bucket so the new
    -- profile is a true 1:1 of the source's CDM (which spells sit on which bars,
    -- etc). Without this the copy renders bars with no spells on them.
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    if sa and type(sa.profiles) == "table" and type(sa.profiles[current]) == "table" then
        sa.profiles[name] = DeepCopy(sa.profiles[current])
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
    -- CDM spell content lives in the per-profile spell store at
    -- EllesmereUIDB.spellAssignments.profiles[<name>] (OUTSIDE the profile blob).
    -- Drop it alongside the profile so no orphaned bucket lingers (and so a future
    -- profile created with the same name never inherits this profile's stale CDM).
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    if sa and type(sa.profiles) == "table" then
        sa.profiles[name] = nil
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
    -- If deleted profile was active, fall back to Default. A freshly
    -- auto-created Default gets the current baseline links STAMPED (the
    -- deleted profile is gone -- inheriting unrecorded would resurrect the
    -- mutating-links bug, and wiping would be unrecoverable).
    if db.activeProfile == name then
        StampUnlockLayoutIfMissing(db.profiles["Default"])
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
    -- CDM spell content lives in the per-profile spell store at
    -- EllesmereUIDB.spellAssignments.profiles[<name>] (OUTSIDE the profile blob),
    -- keyed by profile name. Move the bucket to the new name so the renamed
    -- profile keeps its CDM spell allocations (otherwise they vanish on rename).
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    if sa and type(sa.profiles) == "table" and sa.profiles[oldName] ~= nil then
        sa.profiles[newName] = sa.profiles[oldName]
        sa.profiles[oldName] = nil
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
        -- Rename repoints the SAME profile table: unlockLayout rides it, so
        -- the stamp is a no-op unless the table never had one.
        StampUnlockLayoutIfMissing(db.profiles[newName])
        db.activeProfile = newName
        RepointAllDBs(newName)
    end
    -- Update keybind reference
    EllesmereUI.OnProfileRenamed(oldName, newName)
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    if not db.profiles[name] then return end

    -- An open unlock session cannot survive a profile switch (same rule as
    -- spec changes and condition flips): its movers, snapshots, and pending
    -- edits all belong to the OUTGOING profile's stores -- committing or
    -- harvesting them after the swap would write them into the WRONG
    -- profile's layers and snapshots. Discard-close first.
    if EllesmereUI._unlockModeActive and EllesmereUI.ForceCloseUnlockDiscard then
        EllesmereUI.ForceCloseUnlockDiscard()
    end

    -- Close any editing-as session against the OUTGOING profile first (the
    -- exits bank their edits), so the harvest below runs unguarded and the
    -- post-switch establish never finds a live session.
    if EllesmereUI.SpecOverrides_CloseEditSessions then
        EllesmereUI.SpecOverrides_CloseEditSessions()
    end

    -- Spec Overrides: sync the current spec's stored values with any live
    -- edits before leaving the outgoing profile (suppressed while a spec
    -- transition is mid-flight -- the spec handler already harvested).
    if EllesmereUI.SpecOverrides_HarvestCurrent then
        EllesmereUI.SpecOverrides_HarvestCurrent()
    end

    -- Save current fonts into the outgoing profile before switching. Custom
    -- colors are GLOBAL (not per-profile) and are deliberately NOT saved here --
    -- snapshotting them per profile let a combat-end spec switch restore a stale
    -- snapshot and reset the user's custom power / class-resource colors.
    local outgoing = db.profiles[db.activeProfile or "Default"]
    if outgoing then
        outgoing.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        -- Save unlock layout into outgoing profile (baseline-sourced while
        -- a group layer is live -- see SnapshotUnlockLayout).
        outgoing.unlockLayout = SnapshotUnlockLayout()
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
                StampUnlockLayoutIfMissing(db.profiles[name])
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

    StampUnlockLayoutIfMissing(db.profiles[name])
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
    local pendingOverrideOldSpec = nil -- outgoing spec for a combat-deferred Spec Overrides transition
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
                -- Spec Overrides: run the combat-deferred leave/enter
                -- transition (harvest old spec, apply below).
                local overrideTransition = pendingOverrideOldSpec ~= nil
                    and pendingOverrideOldSpec ~= lastKnownSpecID
                if overrideTransition and EllesmereUI.SpecOverrides_OnSpecChanged then
                    EllesmereUI.SpecOverrides_OnSpecChanged(pendingOverrideOldSpec, lastKnownSpecID)
                end
                pendingOverrideOldSpec = nil
                -- Re-resolve after combat ends (spec may have changed again)
                local targetProfile = ResolveSpecProfile()
                if targetProfile then
                    local current = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                    if current ~= targetProfile then
                        local fontWillChange = EllesmereUI.ProfileChangesFont(
                            EllesmereUIDB.profiles[targetProfile])
                        local skinsWillChange = EllesmereUI.ProfileChangesWindowSkins(
                            EllesmereUIDB.profiles[targetProfile])
                        -- _specProfileSwitching disabled (see doSwitch comment)
                        EllesmereUI.SwitchProfile(targetProfile)
                        EllesmereUI.RefreshAllAddons()
                        if fontWillChange or skinsWillChange then
                            EllesmereUI:ShowConfirmPopup({
                                title       = "Reload Required",
                                message     = fontWillChange
                                    and "Font changed. A UI reload is needed to apply the new font."
                                    or "Window skins changed for this profile. A UI reload is needed to apply them.",
                                confirmText = "Reload Now",
                                cancelText  = "Later",
                                onConfirm   = function() ReloadUI() end,
                            })
                        end
                    end
                end
                -- Spec Overrides: apply the (possibly re-resolved) current
                -- spec's stored values. No-op when a profile switch above
                -- already applied them.
                if overrideTransition and EllesmereUI.SpecOverrides_Apply then
                    EllesmereUI.SpecOverrides_Apply(lastKnownSpecID)
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
                                local skinsChange = EllesmereUI.ProfileChangesWindowSkins(
                                    EllesmereUIDB.profiles[target])
                                -- _specProfileSwitching disabled (see doSwitch comment)
                                EllesmereUI.SwitchProfile(target)
                                EllesmereUI.RefreshAllAddons()
                                if fontChange or skinsChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = fontChange
                                            and "Font changed. A UI reload is needed to apply the new font."
                                            or "Window skins changed for this profile. A UI reload is needed to apply them.",
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
        local prevSpecID = lastKnownSpecID
        -- True whenever Spec Overrides must run a leave/enter transition.
        local specTransition = isFirstLogin or charChanged or prevSpecID ~= specID
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
            -- Remember the outgoing spec so the deferred Spec Overrides
            -- transition can harvest it after combat.
            if specTransition and not charChanged then
                pendingOverrideOldSpec = prevSpecID
            end
            return
        end

        -- Unlock mode cannot survive a spec transition: movers, session
        -- snapshots, and pending edits all belong to the OUTGOING spec's
        -- layout (unlock mode always displays the current spec), so a stale
        -- save would corrupt both baseline and spec-override data. Force-
        -- close DISCARDING the session before any harvest or apply runs.
        -- Combat parity is free: the whole handler defers to REGEN above.
        if specTransition and EllesmereUI.ForceCloseUnlockDiscard then
            EllesmereUI.ForceCloseUnlockDiscard()
        end

        -- Spec Overrides: harvest the outgoing spec's live values into the
        -- still-active profile BEFORE any spec-profile switch below, and mark
        -- the transition so mid-swap harvests can't mis-key values. Cross-char
        -- re-entries pass no old spec (live values may belong to another
        -- character's spec).
        if specTransition and EllesmereUI.SpecOverrides_OnSpecChanged then
            EllesmereUI.SpecOverrides_OnSpecChanged(
                (not charChanged and prevSpecID ~= specID) and prevSpecID or nil, specID)
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
                    local skinsWillChange = EllesmereUI.ProfileChangesWindowSkins(db.profiles[targetProfile])
                    EllesmereUI.SwitchProfile(targetProfile)
                    EllesmereUI.RefreshAllAddons()
                    if not isFirstLogin and (fontWillChange or skinsWillChange) then
                        EllesmereUI:ShowConfirmPopup({
                            title       = "Reload Required",
                            message     = fontWillChange
                                and "Font changed. A UI reload is needed to apply the new font."
                                or "Window skins changed for this profile. A UI reload is needed to apply them.",
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

        -- Spec Overrides: apply the incoming spec's stored values. Any
        -- spec-profile switch above already applied values inside its
        -- RefreshAllAddons pass, so this duplicate is a value-equal no-op
        -- there; it is the ONLY apply for same-profile spec changes and
        -- plain first logins.
        if specTransition and EllesmereUI.SpecOverrides_Apply then
            EllesmereUI.SpecOverrides_Apply(specID, isFirstLogin)
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
                s64 = "!EUI_S332wnoss7(Qu38VpCbS0zllUItMIvxuWaU7UQ5gwcBHTgKL8VKCvfnlEJ(3pfZl2oImYmvMsPm2av1DpfSwZ0fcP8qKr8fhYiZ4HFPYlQ((LjW)52vzz4VUiPogE(GOQjLjj5Vp32k0AVFPkmkzv6vtIZsYT2nWBVMx53ZTh6yT3J4t(sszvArEU7EyBnnM1w2orRYZkMC3hIVVyvn(eROVMoTE(zX1tMJ)UBuDC5SK6dJRQVjUSkG)7SpM(N0)FNx9xQggD8LhC9ffFf6B4VE4rND9KIISPfFnVc(EB2FgF7dIn(cdOxilUQ6YKQIvLts68ASjxC(K5fLvW4ni6IeS5yeQIBVTkP(t57yZiuIHo8xolon)aCi6fvLofPYF44rJB(MpNB7TRNYpiregWyxVQonlT(ETEW2Yzxh8hpFRbwdu7SGOLzX3N00xbrhC(4XNFMAVTd)Zf)GDNB0YKATEXtBw44quIvv1flUEW12HowdDVEO367j7DTv)b7PEBPwurlTr52pjn01ErWYGtR(P1R9Yx5gYMF3ScEd9LT(7jtmFYo1nA85xO2NoD7thxvIAiqu9S9TVEO7a9HG(WDTe1oDRB4UHn)mKXK2skuRZS0BEHK8wUMPl42FhSDKqtDKocZA6PoqpB5uAy0v1aiss75JDO2lVEwr)Olp9K3pEJy593u(WnQBmWYRlt7D9aqMo46aBDUVq)D9B(jy74(mGzHl5FRUmE)j1GYMdwvxxKRlC7O)vQ9idW75HG42pVrxc4tZ6rm5ZtsNnVM0esswlNhNdKZdkwLpT6HhzmoGY39NmjjhzpdJwvLW43hHJaI4JArJUb0nh6Bnm0YDOJTFqisRTJkHh7nWR5pmG94zWuGnic00pFgzbam0Ul5(XfJavGji)QrfLa(ZXzzjvlskt(1tfpg102wtwLtG6REix16zX5XZW1)Evp8uFyln8RBe1OvZw9L(1806rLXlsQeYnTEboJgRnioH18ccJdwZRyIbEDVElRrEkkIQfrRJCqQfx7uHKoxd9QJPB9)QszK1nvBzUx)TMcy6AAVEbOEkAidMynDF)kEF6vhPzcR)vrzt)OBlYRjBoNLvCtCgA88XFBzzsv1xJVNX(dcTzP5jNvWa0QMhdnYJ4xepDkWyHYUHQ9ZOY0eeAbxsUv(VT9I(sA17bSRZaKN6KPJynE18IVE(T3IDatBWnZ2pdrOq9h(rGSDYbmOqyybFE6nKWo03zWWRI98CGKDyrwr5ji(eIg7cnZLWVy5Vhd)b(YZZZU)08k2AkcSP(DqpSRFa(UazpEvDbIfUSMMhNM)L0A2NadUIsaS6sAa5hnbXQyTWhXvTXiXpDsr(v13NHKQfafRmhNhvmpBW5udz4JfhNNS4(r4xHZtAEBTRRp16YxBmJxDe5Ptvcbupo(MXck0j0aYvcCZgtJi6Wbm6aRnDIIzFl7pJd3MbZ7lwvLMpBe7z3gZzXZZbHZrSrdUoDzYm4XNcZWQXnKd(6Jh7vyDV4nuPX4YryG7EnF3(e9WI9DhWEKCgrK4brj5X3KLmDmnvorSKkAIteSg0VEv6FGezMshpvoY)rXhEG0LvwvGkBGEPmonBuFRnkSOErfaRZVphCwnD60K8r9T40I8ZgZZt(g0TwhEKZWJyd0jam2HPLtYsyAAJbGOjZztq5aXIM6LWYXy2NNxuUioJT(vTmU8UJLeL10NUJ2FWi28lMXxfQrqzA2lJNMUQk31I4ns5shOKYOh7H5WOSKB0Sjt305JpmaJ)Y9g5x1gSIzYi2p6CdndENEg89axmiQo5B1Ra4na7bhsxlOUI(wmEBOuMezn0LdJUjROyAgaz)q7bGF0hp(3o(s1jb9fabd42tQO4ymbz7oNBqxhwBmAkZtj8K5XSWQKxKNWGrP3IrhFGBt2ECt2y)xcqLBugJdE6QYyuk)Cf7nHzk1q)AJfGHmiT)zrXICMr90VZe186cmlNOdPjdjsAtlsIUKEOtljC95)NeGS6JZplh)Rwod4bsomoBY5lzQWaYWeyHTEuAwnZKYWOdNhVyj8XJqRrEFszbJp63sG)ECoPfy)PFbGeboIs2lD291ZhrUTDBAzv9LRYpciYJzklNmpMfGgqV9hsZUFjOGOQU6D78U)5QS)3)R0CAqOmYyqn)3RswL8a1aO0b7HvzfWGg9XjQUIpPq4HS0BG5lX35tZhqF9Q4S9NYSwNmO(06Qmyaa9845LXzzM7412BkJRnTJbRDo5F))acTlxMaD9zff5V7KvXLt)bnVhsuDy(E)trZFTN6GfoyFdYDl(H31dyD9II87EI17xBcoWM)l)7)FL)7)NSmONVOSy10fffLj)WwULQWHUF)YK43578JGMZM7RZ0zwKTRwMaDEEWG9EGSqkjlzc0SNfVCjOyjNalxq)w1dpWnaRXLm2BmeT7(RQa32cG7DLq2OvTC35bTqJklwa24ZGYMmDXvWmM9rEmdobLD7F44t)TJfTnZAu2lOQuZJzAwLRv0bGRcVdnG9D)FsMf9UJs)cyl(7Uyv5YIQK)VyRimhSKzC1J)sUJV1R6KUzYwM)x2jTTxq4pJl12)8Tuh49t4C2)ppM72tQoZADIYRNiT1pJl0d)jef7vEs)3IfANbw)mQV6NqL0bb)mUq)t4KoW9NW5C4pBq30(0Ip8ljxbEz(lj3ddtlYD1PlG37IIQu8tWGrHrAJVZDSj4957ypiy3a5p02X(TCkpRktYUOinh3B8dp(JJXy15hTu7jKZ389EAiU3tU2ox7foq0(ooQ5SXqE7VZaRb7oq(t4w0D(rI8AH1(Ad)N34pmYywdWgNUoQzmqaBLTEw93YdGjaUH(2Ud88zbOKiNHTNxIEuMgdghxSw9(C3b6TQ2WZhhEo2xBpiuU6n0Dx3MFeux7HTj6B)IzRm455rn8A)(VuQXGOM0rJpKANprRFi5e0MI96TaPNjzy3z9m4hDSeTNT112dDCgm4AxFPavqRCGsSKh2MoSz93JCKRdOWv7fH7C(d0g1oN2mhC7mu2ijd78vRnzZlQQoEYDh2evFw2Fq7G7yabQoDjFlDxTKT)XNC4rJv2l2qAVy57uH62(mikF1Ill(Afbi7ZFNXZtNCxo0qYn(ieZzKBsZNEc9Mg3nk5lDzoFFh4)((zPZYH2kl52Aj(8WOdvswtxEwyQUhmYDEmS1gwOSZiIPNNOVoxMtK0oZIePtRtwWiFJ7UNLmYDC5ymBzva07zZNcO9AL)wJt(w9yL59(WWzyF7H8aCpeNGQpPemc60dMj3cx9n8BS8forsjoqoxDflt8nuduqxKLoTlv4t5oM23iBXBrKa(wydD3VzCF(1xAK7xf9qP(qXQlour6qWET3O6q(NmUqU)zsk3bIvc1nOEiM2X1PtIZohtiGA2Ur1K8c)c9PJK0kE6b4q)2XsdcAL(abYv5rfcjQqgrggm68a8Skqzp)E81ww251xw25vqwUdnULWnrSK6pAjSQX8Au2wFnrv4UrCuP1FjY3MeK1e)6k)AhvxS8suqhA0CVNwK2EVomZMeQ1fiErs1stlgZgPkCHVgI39GZjbsOD)VxqadI6q)mRS4RhLwMmH)UIuVwvOxf(OpfipH4UbTd9HKWvfni6xfmA)aK4DnjXRjGRreSvAamhw)bPmxtEUVvIwGc6c1o0C80CYFk0zmw(jzEjYeiHMuQwglyK)81XiaUhrg4yBS7RdIbbh28PMqlCCJaFyJRX0QirLQyiNUAJ(QJ08YaomGl9kzsqx7LgYCR)IS4jjZz5BmYbmAlHowRvcDaLmPE3DVNe1qxL1tay4ZcTq)gi4PSsFEotdUJt0TfaI9LjlGzclrF45t4gazW1NO1aCTmTTuag64qCzg017ZOKxPEqx0nKya1Kyk(EfMv6y8oeuDWXjT(RHu9cHFur3e2CX6P7G3SnWJjybXWwmYy0iNaIgHzk0SKMLE(GHhtNAgvjDbW2Ctw6F8hXLtnIgzfv910LYmdDWATyrJ1r3W(xG)hTP)AuG(W)0(Il5ciD1f3R0N5o9tQGshYiWSSmnKE5Fbw3a2zjq3gcp1GPXLBL8TQ9QI8Tt4ZZuMwT7NfialJHP4I0jNKv81r9KwTxjLehzqJGYHPrZZLwles9SDrMCEAKjGDVyv953EzC(SKZbCPSyo26AXOggnsS4Sn4upltA8EAHmn7yoORTE6M5yTxBOQEDg0icXgyu4gJx1hOIf1hnznFR4vyoQc9yjPU6ht8EQeOpjYr1oOuTvhQIt5qbzNP6ctRAHniJBJAnqt04QLjjtjNG2iFR6hDPhylZoGAmvVnB7sdH5sPsrnKQ1y(equuNSYLFcusNsOTxgT2jdB(byt99)qk0s5HgiPYnUyBHZifMgdY(tJP98DlRtiumyaGomM6Qch)RhCmtWIuKNz4yat3rj3MKxbCQ9BXvBYOFuEYxWtLJUyEFsL9cSd9EA1jZlyNbTXTJINI0MDNJnbBHYk66RNHF(1tMQoLOJ0W7o8OQxD)lT3mWyDRg7IoBqy)zJrBaO6vfIwN1Bd8N1idCV4EplWzJ6LmOWTvSVueZEktjBfQ1EyS30O7yeB1iiSjSSD6WG0duCVqQkBjUkK6MdwRdY3puC)QNwdwCit1js9Ro92ZsR4eiHaTB0ff1vV7)17Uegb8JmK2i95af3eVHNWLxZkHnA0Yldw2XGgiTRoIVZ2zUbqB9Au5b9HH1lSvBFL7XOOoazRjWxVqxN7vpHriV2ESQY)PbPzIzSlIM5qK1fKR9(nPcWjKx8B0P)oEOu2EhN7HVVlkMz8U(HX26O393dGptAH3EVP7Ik4VNj8U1GZUjUwB2ounf9g3g4xgQNMvcCKoJ5WHrOokJp4NDCK34SeySm93SPGLCDC1nxacGXLNLoJDqyg)e8vRbjzdDSdwxy)jo(4ykdNad)UlnNo6VvJPRBMEUnbyhM8jYlRLHraWv9yG9tEMV1rTf4VdyzagBDgp6SKqcE2HqewyzMze85xE6)88poE)pWYOl(FeByhwMKCBAwg(BEbTskPqISaKIXQdjHQvmwp5tUN1qdjoFaE)UZGXr1jc3UOHwswwJBOCb288KmS5iphfhBvbYya0wazIKhAg1OOQqkt0QFwF8CGy8qZSlnnZWZIPu1aPnXce5y)YXlwIx9dGCZmXjPxoTKPCXSjtzxWiXL3Z2Cc)9OJ5(cbWPhBaWUMUY9h0o)Q6Cu7fZp1Ttxn0N01CsUdFtNrsi4sHyimYeUTKG0Cq0fumHMgc54Z5747TN6k8L8mlu87YPiEeTHU(d8NpsUo9zXeH3NxHB7g0tnXPK1G0fLcav9cs1iDQVu(yDraLMNspgK0HMLkUriT4I3Vb)MTpIINpwH6Yo4)0DAWa(UnwhNDe)u92j4aet5bgzk9eTz3KQyFdmEMygpOL8Y(8lAcSt3NVQstLfjLnx7aTM3hiYSuERCjdRGL1vlltxa9dDcWrH2r45lhteTLjLlxspEoq(XnIsF)k59tyuY3qLyNE7hleqG0Leb2AmSi9ExGuztOehYW95sUJv)qjJUXJgV0oZGoe(GMHSsaHbvgPvSFdtsv6qxQm5UigSMfmMfpE8A3)r(ERh8zy0ueQEEYIKwoM2mvKj3GS7KJbmTjqzyYGbryGwdMFlWgszhOHe3wm6O(3mNMut3xcsehwo7W7YpR0Loisq6T1hNbtdqafxnPRmhVOpYqWfOFbw9TVLRr1JkhlSqmrDnNhQJfff1ZrDNJ69YxPOXrJUef1lIQUit7awG06wfBBbQKMw2LHR)nt2KrXsL9R56EX0LzHj1kQINhieSuEMqyBJrTA4zV0W(g3vZDi79jK3bgWQuhm73tiYK2pg01KfWY1M9kWaegG)Law0mTbeRbTYApdEhxUcmT)YeYIxSz4Rcj5ZzxpgGvT3c2IFzpsSpSoud1xNYck)(XJSIMhxn)3IZwbUKyfrEKKm50JQEGDvKXYZCK4EGcO)LC(BvihU597ZNldJwMU896I7Sj9vPlwMLmQnMX42PjkrAq63U2H(2oUbUwb2wwoTJUMJFxqd5DHMx0rG)omAcmEoVFrxJoKAuUXU)UJDbI9z5MdywAKiNxQ6tKz2It4KsjT4K1qlU0yti51Hj)vkb)MRxwzz3eyNSJpWuhl)RQMdCYAV3PiTL2M5ghVHAcDd7hWQJf4GpDmccPFxqwgXSyygElCKgNFAzr(TRkPnjimQOysJSoqw4IKJqN4Ilh1fzBONL7aBNqlVq7b0rmai3)UIEkbwRHTJXuK6BRwSJIjdkRvONxI7EsvYOnrFKZl9mVq6JSP4CiOOOH6VhGvybWyCx2Yd4C2TmeLmi(S4VXcVqF31wAAX7GyEIi(Hgbb7rb0EcPsYkrWmKLLf1Nolh4IUionxmxg3wvNDlDpb8G4O91eJvxvqKNWCxyjTp2D120DkEGqRdApvCw98o2nlJe4ty28FMMhBYkufP8av7DBRcxyJrhtB7kyOlUjaPS7CVEjSmnydfb1KB7nh6wRj0MXW0yV75otRJLRgdiVQSVjRXEwMsA2kctw7RBGPbb5o5n5ASSw3wdJgHkKMTFH2pAVr2pkCeXr6P)Z12XbrZsYtkJZEOtufyPPIynaVO4klMq5u)t4gImgm4fZ2JS5xrDYckoGgtJnfub91L2KoLWrzqD2gMXy6XlqDtXOR)w9yA(paJuQhxc6eOl9wh8Ujs7jg4)XyivZUMh3Dix7c7bTZFlw2EXej85x)Y4BjzBMjc5o7QUCnxOMtkq7ARjJLC9gQUd7Si5W7Qd4g(rzzgY)nWEDx4M4vR54vL5NsBR1sPYB8szFGDGL3q3qNboCD322UU7c)o)pSnN2ohLRXZlktWB4TZwLvNszMAZ44k083RUlD54EcO4aFoVWTfL4v93vSAsWyfHMG1GycEsPN9VYeUFjxhmFnI554aTScYLViPCFKQV4idHmDPE((Kywy07XxxLp8sjhsFGYxpjEjYZp9CyXt9Y3uehVIB(xjSy7RZcItV7aBm4dLUS)hfViEwYz49Vh7E0lAk7MLEiUXiGlNz4nTNuO0HRaRm5weV6sm2FgIxMdUTL3KusgmWKjbJVB1GQ5mLTPCMsv(ya513nff3Tad3h6(i0UGzx5d3BnxUK4XhFkl3YPXVLwGtvcLOnW8KpvCWEC5bogJ667tb1HmpVXlhYYpa24kCUf(1ZrCN677iqpWx49uJbXHwd213Z1zG7qhFwq1zYuUbd2fTX3AOl8vpQfzxBc8szx8C0hwheRGgUaVtXzCd4xHmrNMF0Q8zjIKTb3XhGtN7PHNYRDzCkpcI4ZWnppMNVtvacBco5W)qZKXXfd2KLJZqVHo2IZhRJLxWUEooG7C(boSzJdJoH9Y54(QjaGgjNDQKqABh1hsK6tg7Im3457yECP4Xn3nMIhkVAb8g6jVu0DggkVGbW7x4hvd2pdkaOn8al4qkOwe)n0SSCFH(wY3lxRwBPTlfAi83jMiEYbOmiBn2BVa12obhB5cuhsx3Df9OZ)9pkSn5jLT048XorlOnWyt87pkEWv67KmivbAdRsk(cD0nQ4P3GUmoDodWIndGrRFJelZTkqQQmj(oCNJnXmlOOpXeczUNwEWS(VVvf3ZQdu2Gp6uwvX3o0PSE)P7QaXRQEun47s47rccVDh3mS0Gf6JPaOQkFnv6DS97KugAXNs96TMUaen6(GdBh2BP5JwnUinppz6vjz3osKZkmxVA8rulFMTiWC5A2(8TYh137gb8KDKbr5oFl)WqhxFaTWMcyht00WJN19XK5dLOqjNQ3kjziOB6407XupF1xJxI3BSPtyYvl5zAGe7Yxa(oWLFHuYTDWIpJNSQ8QKkwPnYwDZfCCPJmugtnaZzv4vp6mm9xqgShA3wRRZh6IBeNlO5FOVRGnUVE22Z)f2ZdbZfWFge4m0D4ZBuegU2bbDfLI8AMwPuGA73hqkLf(iZac6cChKGeqYb02XjHe0KF8A4rEAHyx5OCtExwdRl(SUKOIm7aBCWl)pLVJlnSzIrDzF1ctf7lBzdxVEQPhEw)2WViMSx7hQsYyw0OrBvh4ISu4wLSVMVcBS4l8GmHtWZngOSOXmIXAzi0XtNLq2JTRTmr5uVaDuk3wSij6hyksI746Vv3Un8C3U)6jZZD)9dIUmzzZWDqNcA122GS60HNC2ZRdpH(Ubode7R3obHSRyf7bGHmdTd32M35jiU2HTVbx2uIRt0X5S7nCwknX7gVo3ypmWNovOOTAoeiACBXY2oddBFx4SvTO4k)bSs3WWDNHdBVfRB(9P0NU4vNfrCB14gy8(j65pA1lCveBsNB(gSpC93QRajk59EuP0WS(MFRPi(RNRElV(EKdxax8FG3y1yQfVs4cK3qJS0wEQlgBtAczh9BjGjlzjh)T0AXeXl00ABy4ZDPvwyREEODuQmUCv18KPTvLXIVcDJWDaRMosO4mdgNdkzYqfnkr7x6IwGvJlAdh42U(iaMNmKB5n1Xh0yERhFtrypNRJKznIdT7TQ6CApEDCAgwD(Bw6PMUi5wv6TxWmrjdv9PDNhiD)3RIltKvQfSy1WDWc3XR9b3vOk3vLmPnzM9psN82MeaJwvsWZJUZ2Ykk)DX2LU59UrCvwjaIT5vYjYbz5bgCgAjqj4zq1LmROyguHwjCw8KYcEk3bwImtlK)lW)yRcprtI5A(YdKNOLSHUOs)njlDYDJNxwSA28rY0beAK7e34aR7(WiF1c2cc3qmWqfMTcCtM8831Z1XAy4GamUo88mML4Yf51BqaUsuRBm0Oq7(APvy4bhTs)dOLzNJKMJZZ42BNKNcRd74iaKdEwAGpRKSVwDIzmQJ(ISjt4N8OT7sLW4LfH883fWznE4rUZZXltoOvntP50uAUMPiQDy81dUP30AeXfACjQBIxHcjlUjUgL00oG10JvoufB6z1WL4GBzj)aTfTnXZdAYCr80PYdeFNBZeUl(DRvnocVsa1k5tfLnkjHMnWg0CWVUqrwLEzf2LMPwyBbrEaTDB49vMYk4ykKWU1hNNATU7HGcDIHvpanV7gbrLuUkGm6NJDgfnrfcGMWgrPVsVo(mGhkzKXGx2(ixnLRUp9IOVy9QdLr55pDZOivReCgYHRMlegJ1Shn4u5HBsLv8t64hD36etBR3S1T6XZ6m56N5AxL5JsMXJZen5OLd6uY2J3g99XMjGDvryMJTxq1Eaj6bsrFgmsZVJ3uG(Mc03uG(Mc03uG(Mc0Fykqvcmv)N5tXol4z90zt12Q)08Ys)CRn7iIA4xO4V030E7GN0v6nUFT2()uQ12j8ptf1F6VGkQ3jy9hz6FmQQfRl)i0oV9QF((O52XGM7DCFfuDVL6w6tLEhTlDnjWPFRD6E7dX2iYVVASnxbQFvux)e6f0G)nzkulvZ7myZ0n)5V76MnyLZ4xU65rS9w8G4zpHJTDjSJxh24Ame0l66Q4VWcFV2IHoW2WMw20cO1EVqnU9rjA2u4(1ZBuXBpsNVP99hOBYw)yDt()Kv((FcUg3NxTDSL2SMGUMs)k4rSY1r5ps)Hh)APGThBl(zYV3T0STUAz6l1G2CDVJEM6E7bNW8Q3lqpQp65QT1l111Ee3BR(QLo2EMKMf46JMBg)ZK6BJRoBVXDBiT2iIAhD)B(L6wpAD2suot6K6xPUM2YEzJ7aEysiTLHlwpdLupLPlVe1vMllb9ITzckSVO(AWiNEuhyw7MrlImF1K2R1q9EelnPeR7bfVp1AFp1FTLG3ptB5wV5UM0cAgcEBmb)z5hrBDforRw2XUZ1VhrRZduZbSOBaIzr6C4BQlEtDXBQlEtDXBQlEtDXAvx0k1XFlsD)LosD)mgqUTYJ6)2epUUyYBz84mxSp3(yQzoCD9TrwgTu0ywZyW6Z)oUFxDSfQ3ef87s446yyZ37T66fhrUWOZsHj9B7bMXZH0p30JMdZ0BzHZBzHZBzHZBzHZZnlCS38SW5htIZ(3O0WX7)8tdhTZR8B6AEtxZW3018NJUgxt6A8FtxZpj6Ac)pFDnnxplVPO5nfnHVPO5nNA((F0c(rK7J)nsnZWFsuZm4TZD(BN783o35VDUZF7CN)25o)h65ox9sZ8TdE(wEWZ9(zp1Ag8Mo7)kMZndEtp9F3peC)PPE(74XGl4TJb3wL0neFH4o)KxjcOjTY1p6rX1XIkwgvGVz)fKT4aUDLIMqxRH7GGwddlqHAWE0DlU4B6C7YoS5woT9faRV8R0rrAgpILCSpc1U)YxvgJfi)ltwa0lQk4mmQmoDkRS5)GSKrCE9C4VEwALSubwjjmsTlSlV8BGxFfv39QU7EQ8LwwK)hyH7b5cR)k7FCBrj(saXpLv(IMJL2MXpkrl(yrUqWBkp5FqTiRwG9ufvSdwwMClWRdVaqQUJxa0VgwKOkZlwyepkTAzw89NvmnbgilyvfbQ6VKF39hKfp5U)zroVqDQoNylFIwVOyQEJRoJDI(kvGXXBM(LqZZ(LY06KRJN(VyZ)PjXtZUFmhfh4mNrGd3MfVibK(NTkHQMaLPlxMr)5qwHD42vL03vxvxMExcJIjk8JFnjEzr(1j5tGf3AQjtIlRbUKVqnItugV(EeVAgwtvVgPjm1jPmIBnvMoIxaD7T3tF0qAWxbKE6VIKQRVbPvuTGdj2ujNcRI58vZIP4INJNOaJmjnoRsDrCmV6pYjQ)oBWFmn2vPUSdPzmWxw9q)SzyvejlTcqQHX81S3PIkmufzeRxXcAWpn52RPraLr(3Kuvx81R)AY9LWiRGQ8KEry9wiP8UMxfBQBjAhwx2G2Vc5tOgfq7bChGfEbJEnn5lfxJdz2VvDpSexudmcM5MhtW3148QUrWJzM2uIDLvV6UNJQ6yr1xXgkXWOzBdSctPfVBowPoaptCLgBQAl5r1GhCW)R4xkQq(yHjIFFgamWLad8v1WFjgyZp74Jo9xpdh6FtRmrwOuJJ4miAnjViajB16UhNKjRkRkk3VUoEYCzXccH3XvJJ)gWvvvby4BCjasTAd50UGH2QivUJphBwFfR5pBUcW6eAQGKVZZ9s)NyAuGUpCECn7gOEc9pgY(h86ZeDDwtMiDf8)yvkJM4MtAqQ4IUq3egD91a7Wnm79DJsNMLmkEAYrjaZOO8UkRJp8nLblRrNbguiQas9wgYaFFOHGWBmTA8fZ0qqzaaxWGxqUWte1Nv(hkn26H2FIsnp83ksbJ3CLRMhwS8EXTCkdukPgRlhvGsZhLnZi0VNPuXZs8rK6tbnayVtYNXTfLgExQJhrovvxaiyxOx0z2XDGd7(RpiWDONLNS2e4zJ3p)dGhzpWBBQEfTl9F4fGo4EdSycOHilbV0ODw83yLi4CBlUn04axT8N0ufS0kcyGUBqductHzBUcQgOXluj0UZOSajHoeIXX30yygpU68x34XVj0W0GaGrbl8HytjaGrlZklYYgXvrTeCspFCbRUtfYR1BmFjppNvwQOfvw9zH501hkMno(MXD4oK8Ghiohbi8paDVyjVeahe9FDA0)1zVJaMGHv7f9alk8T2dhyB5lx0H)nWm45h4bpFOZwvqkK83uvT56KPP14s0hr9mOrolalZiorl2ysuF4hgU7GaFxFlxp7WoYung3QwOBCmuOB(1806riAFffYkrb(v8iGheGky1CuFQaCYnXb)N1ch9b9SfvKI6Lj1JvCRM()Pkqj9pFu2suHj9M6By4hnLioBrvA(GMsr4qlEaPG)W(3a6mU5G2LJRbHEU2GGPV3qlhz14Yw8i7HbwkXZr)Xu9HswPL(eV2rCdySmvtF4oGad2dzosEiqvtYR189tmSKYsY)OdFcXx9C94Loj(uxZJa2Jv8sg8DO4RjLQXNaRzKG3LlWHAtP9ZMNPWSx)IKsep4tRRqltUeZI9J4KNmbW6eQVBeWDO)aYCHFr5QLG2Y4P3RBPIttvxWrsNDfLlrSbO6thJn4PDFtD89jX8wB5xSVxiuNvNr4zPtXk2KIRtHnvhljbFmZZPE(2wwI5pqodDvkSBHoCJXAnf)SioJn1KljpdiDrMNwFZhG)AhUjxgNgokrX5pZRkEc(LplJFIYYL8etTi(BhLGCUn3pvSs8pRuqtfvpmenGwx68vVe04cEgw3UW6nwZskCjuUEO7cBNzU8GNtIehMLeNtgz4sYvy5NKna9yZlXiqgecPy2fiVSOJAiaYI9mJxxlKsQC)FwW9ZSaagJJfOrn9PCSAiQqOFnknxZGzS0oJdjohkAbXg4mzXk62BBhLf6ZAOJj84SjHeAXrWyvKCuSr14MQxVpQID5sCEjw5KVl2vxsX2clbI0cM60ITgZtnGPmgNtkl(A98kQQdsQdPXlpGOwy9h1vuYKvgska22IAQOcF8hkMeRNxgGtean)cMkgot7ynOrnga0npsGr7XTn6h4cO5X56LZDjxLOgWXBSp1HTtVO5GocIoOKm9cotdzNDZu1Qr7GyUkQTC69SepgdfZzXL3jQbX8mauTfu1TifW(i6yMutjFHK3Qn4ytq3szlwJvMNFw91KT2MDgZjoDbwZyzx)zEIY7Hb(Rf3SBJcvLfNHkf0qnyK(3xal(6PIQ4(3uajxmVoToaSGFjXUXeI(KixqAwcA0r440ZA9yvzlQjadPA)Uu8GdLGluDLw2pFUL2yTJVBCxRA6FbrPMqs4emeG5lLgrtvAyQW)RxajprMqA13iTujGBrbPvHvcOoqpqU7Af0O(t8VNX)3pQPiH5JHtKZuPImgVVsnawcO8l4UPb)pLyRZKwA35n2w0yAHd3mbo3TwjgwZoHU2JnqvxwBDVos2DuoACh8s8JAEB11x5ol28O9ZsNPEYGvmYuIqRV(CPmJUue4KHSx4ImsNhj8GGPlDuZgYWGtPPpW(JryCzY0o4IFwK)eKTPQsVJ7ycIuQHE5wkugOny3KKhqdc6ZnxyhkM1ACdgCCfSoOa0Vppba6IzLi(X9SjKK))xbJPXD7zP2F2cmUVnIfzvTn6Qdg0der)77rZUsrupEWRveAT5cTxexwFpnoBQTCBc5uYoRvHvRwuuWCJIVXReBSqCaS2ijdRTXI5FRvvtBoJBJ5I8YZmjh40vgrx1TffurYccWUbtS(hi2pMw2tQ4AyZYVItpob9SK0SvLoeQIwzz3kYKXosFDqYqRklN7WMudiWTThaQw61y0rJMig3mYGtAJmmQ18lzd22ZMnXUXi(Pjc4MhvnDtFM4B3uJ8S5)BCMe47Z1WGrSoHM)NfplDslgqWfiYYp2N5r14FCCqrlGTS9GP1lU1cBH2oDoNq7V7bcOp)wWDMIn94g9lnMt7PeyMJWkKRybFSzpvhTj6Nm6gZ61c1H1BDbKyTo20kyfEb7Tno30YUW14RIdjCOsCuIPOh506fC3k0PbM9NPf8DFE5eQVEPXx1wdjxVKoSngTR65RnEeTh(Y1eMPfQ)LrgaQnyVBFAPhQpz0KYmynWgdxBWXSr9eDPwUZ3JncsbcZR3TJ1MIHnJLeUluNQJ6eBSG9KmvgK66ZRqLWL4y1f87WvWCOrdqdSzGBqRuzGJ0PQJre(0hOaOix41b630GGgkIshls3NMpnf8NUOXTIngDATX60161mwNSc8)ZmwN7ksuAkJP)Zi0NM81si))DpQMgJy5OTnwJIJPY2eRr7WwcCCxHwJuC4ghIYHTzGvW50KhDF1IEPUreoduwZ384w(8nnSDioD6id3TSlBK)PxZkg)IchQj7h2(iI(xYaGUw7i6yBa(5XaVLoRPDWwRs3uarFUreD0lpIO9O)0HTteky48bXZlaQMcVqRaumqLg2oatHnr5r8VvRB3wYnA5p34S2oEQ(kZjDNI3(qT2YroXcslJQdPDoNwhhxW2S2XBAqyDjVtAXN3eaoW7ef7u6wn47KnssVF7eOtJboEnwO5Zd9Oo8QWz3BA50BOY4uYcJ5RXY1UBv9gMzNwMkPhfDZrNsXoDFRNmU0Mcq66c2rF7hJPq0IsnEbk)mq65RHhpR7JF8jJFiWzW47KuDfwpt(NS1X1U)au1jWNAOXmswyV(254nC3gdjd7p6)W8VLyXN478QEK)LZwYVj5OLhK3xqecnFpvB0fp3DfBahUtC8qJQBuHCOnKpEXiU3Dhc6e8XE3BG(IywlQg3iNnCFZmEYrmUVbFhc2FBxV3Yq9V5HORBG)v1fkYXkNEd9VPnYDdI7zFXUqDRW6nA8FVI))63LTw7mVPRL7VFb)BTbL61ERe2Y96ceWBjOjz2v2KZ1U9tVgBRGXyWT(9LPJ7oTDoFt2HbRo(mHZa8O9Wug2kclhVyz99RNWQACjzdtFzEs3(wFSPecm31Lkbg3gI(2q8NmgD9Vr3677Gsq)w7go0o)A2Gn4(XMe77HToqwAbHYBBdc1FDIZK9lmotE)1jf7E25r3O)eYJUqA7tZxTyRJV1AIJLFR4yTJ7gMSDEMJwf78kXoCsBsWQCFUPAxVrMYG1)LBJtbBC659cJnvOPytn6PJn1)F27kD5Mizz9RcVa4BVVi)lBJf4yaBFTfZaNGiiKLAB3hK72hTWahhZ7(nxQLS6nj7HHziUqqqJK6U6QYkRC5lZkRNq26n5hM0YJb2yiuPA4JOvvFZK2l1B)VX4s1xM6nz3XLQpaO6ooFoiq98Whvs8TDtL3nCLI)MbSu4pEjWNgq(oqPPp)E606Mj7E6(fUnyv627LEo)HA5OBhyw1r8Eu5R9agCTZockmvmU)4vo5Bgye9LFzDH0WJm17AGi2KNAYh6BDh8Je6D9MdI)z1L1ghPHsfXgXGUfKer9bjXqgUp5XL(H9GjHD6Tdqj6WRQD01XwqugoVp8i6hRUUYHINoKy7oks9717Ftqz0hWysSx6eUGEbHiChbHOjQw9a)qFH5PbEl9M)lFdqtOxFmblAlxoBrX2GwO7uFBaeP7dFHTb(9aHm5PKiJDJaDl0VAayG7(a6Dvpxh1ChCznGa0oM3oadKHl91GwVTSr0bat95RIBY9f6P8eLZFMZGfwa1S12KqKDnhUOG33)mkDXgr6PXwq60PKObgbTjdCTzaB8oMxXFKhpmzvV)wjIkT)dvEdO2EN(jDTVU9Em7HxNTfPQzt9Y2lZ8NCZMg1pmEVy9FsEC7uy(f4299EcDyj0n4gCniiyVa7FuTyuYJIi4UZp)t17m5o1a9UNhf3KaVRVaExRQNNC3a)Qwporwv0EmBOBANW(Ny07lbZ0qc8B2DA(Kd(IC36TydgR7AHHj75Ad1Ux(c8j6OoegXHSzrfikymeTpqWimhlemiUit6nyOzszdG6MIPICVZlpZM8DPwOBdZ0B8)gR(sCmZYiwEa4v6XC1N6wIPvw21NLFS7f9yP(JjnWDGeniAVKCqotMxqe8FytdTGOzFd9ykupjJqB66fM8PVHLdD5uzRN(LQefPbejD7iMosCDKfD9STYEugP0VtP9LkEnTdwK7hDB)Xa5OxpMr0bmYDV8PXS7H6PfPza5(7z4icz9oTWKPDS2DA3xQB3MHoTNDTFRqF66clV2LL1FGQ(a1zLfJ(IxQk(mQsuN2B)QA2SBl0u6B5avDqWokLn3fkzLLAiFOQYRSeGikHmDRE7NIz(PyMFkMPlVn(hHOLuPnfG9mRuf0fcBRSKMC47L6rfxlRXHn9YjWBOAusJeEShGIDwYgWygTQ8U7xuCyp5gxNqiRRJiO5xGVoFsEYhGpChlwt6D95oHfDhB5IhnE0bzQX6l6Bhs1aB6EsS)2l6FebCLkArgcUUehTfeG)MLX)9GjUVOpTYfaRhP8I(II6q530wIWkhXmhs1tvJvNR6hqHzFsCeyzyZ(UH3OrqFwY8PkJIo46B0a1wCvxrbEh2YrsIwt877Okd1P9eDHy0K(21PsrXEz7fMh7L4NgKfn0(EOhZsCKXM2EdFn8(4RhLnnLW3oCSdTdk31T6War0TlBGAiyQ9ikQPK6UVLD3wQbJzDN4U33gbSvaU7mxnhgl1UqUVLbt)Lwca2DB(6BpF2PvFDeDaZI8Urq)rv3C6igm9vnm6Raa8OmFSN8cpBuDT(KPEVOHdsZajRaSQXr9SuGFVPpW23()Tklv9KrbdbAExPhshBw2N8(0QJ9nZGrQRNqpSRBfIUdatJaaY40wV(8VdEBk1xF1FPEB2oDO)hNxLTnM87RZJ6v9x9JGZJDBHwV(T1PbG7G7IDlwTpP(Bb5Rout3ZEnQLxLg097Zyn3Iwru8E(zXQ)MV)FJqa19K4FAiGI)jQp)Zf1NUfeVTLOpcSF6x5ZoSKUTNaT8HVpqI2k2pHUrIwr)AveCr7(a7Xwtv82G0rRNw9PxnD1b3CZY6ZuN6gVP(kSMQp2neAKjfITTACRTfjNFrUq2a0R)ZMIvaH9kAa5CmPmB2rlRVxx8TdW6XnwkRx81xPNN0jJUkRfPWewoBc0PPEmVNXO(OACRz4qAnNpdp)ZbelHjo462uhJE9l90ZpAiPbQtHOBRxTUCHmuD2m8oxSBBuw(x6KI77s2TR7QVUyTj9R0NHSOByckMOZFyZYEuKxMi1ZTL9Om9rVs7Yr32s7Guhk9U43dN0CxUOMxxWiYHhVvvZlURKpCsOZCPiRJi7kytMK5cB(wPeCkrSMuENqKI9KXb4kPfRWtYzxISu9hkmPfEwNuhXxNhb0zaK4GvjLoVhmg8kvoTcHRu5AH6j80MbwU(Q6VqF57TL5CNUM1tkLdhelpBlDFdp)mjTXuL)d3V5ay74xcQdq5fZk(FXvXiJ3VvU(2ZU6FxqUsZ7rcDhwMXGSukY)g5ywVfMoSLpUvAjtYtNRGidho6(7lkUE6MfKigfKZgow28Jm9Uk0KpbVC69vbc9GskIAdYmB2UDwtLqX1VOc30lLfRo7SJMyC3zILOUI3fvQZAlTotTZQQdOkxsMSAvHKmy882kJOJYReYBISjouKnXHI0joeDeEiZowbxrSKRqKXXooSgZFdttC2kC6U8K673LZ2jIThy5TcyyFvlSYOYtSdMGqR(KyTreo76D5UZvjkQHkfehnsjO64hc1IjGjUNsDsUdlPqbviFUNC(rtkxZholeHXKY8bkPw23jLowvQ8u7w7jvficEFBsM7s(d8mS4h5EI7PGGxjqSb65Wuzd5QCSjusNDo)eTTItqbSsNDwqKk1)OWjwKZn5ggbAViiFs3FQrJ6ivZURoG5SY7qZVMwrP5LLmQYRq7rCHgbLvtelWAO3xVqc41MHVnhvcZVF1P1KHdcEMCdgeVUE2NQ3S(GvGo2FFoAv5YALb81GWwTrhg23mFRAC)m7U7knrlVqR4Wotf5oJFEtbE6e2JP(gCinch5H79)AL)EkZrBiNzNuCkML2fB5NPaOrOVl2k51MrK0PdvXgWE3f2eDuacL4y9jWnWJS4GmBjhlwSB5cIc3Vzk8rv2XmHOqRTxz5cuxjvK7WHl5v34CeIY6x1tmbTnBPX(8liVDTcrv5oeInDMOJrzSdOa3AgKyTSRSQ2ExL7WPkSTlvieWj0dXUl)A)cfMh7UHEOdakS9mlzPCHt7RXMswMKO)ApLffwDdTjU924YXstJO2Ubk(o2Z4SpO87Sk0P2lxIvzokqAlmYXavBzmyiB)mrlR5piK)gqwO2qzId7Y7CocQu2fyxTytGyRzakoF3600yve1wwC8IY1f2xPwOTWhq3Z2ZVbfWiP4BGfsvHNyh5UUK36DKGAbIn0qDNlJinZ6GgeYl2nPI(8B1CcrPGU62PRUfpfIugFRuz7B9R7PSVFtv8SThJDZJhAFD8bf4TojKpEA4Gzt27KIRs0mmNOzOB58zZscqQZIvH8qh3jENRqmK55114EVXv54qY9fkaXL)nS0msm)B39WsUXEm6qV7532uDx57Xysu4T0XyBXDu363Uf8ZhNB59vuRZ7Z9KQ)TEX7RjMf6gAIt641ExpHNzMcvlMttzdGt8e5L3wwSyUyMxTmIL3PONSXHSLUSmzzvr3tyR6yZsn6OjRYCothRtQajsdboDrwZG06MgUuX83oE(L5AW2ojz3zI15vycfgl6WGOQ00gNOuJsIDk9mPsfhVOEdqvhB2L6n8qks92SIot2VvAIOC90e2ou3Un220hDm)wcMItOm1II67O62VXr1T7mX7CNjaBE1Y27TSMfRKKs0i0Tnb(f82C0UrVACxMiAH2wxmD5UleqLmi48NB58G8BARSh5Ob(ckpAD493l2HnwxlJBmqzG0MSBhYI3vwv(ySsfi5OX6oGyeWyGAqnPtlbCLcQoudJJhrvyIRNoR4dhmF(zvR(Gan3pCxX8YPFGU1pypdj3BYKXg7aoyXcrXv0X9ctTpXDHMdhuIreX4nlwGDWEStIpR(YSBwQDBdB32W03rnc8kAHgSketXDjpXzfKuzHEMqbKU1hqH2ARYAlVcxN3dsApsTcOvAAfOXTlgA0rKN2AuVSwI4AHMqH9JRbdniaVlG50PYFbIA6V)5QdWBHvSo5JMtSaSyALANb8JT91SyDT2xkwhw6BuTAS(2iqYPYp2AQR797DBdHApNByRTE8YkbAhTUyd7FJd3FQBFsfF6nAfsgANPe1RRWuvFXcttdyQ1Ce7Ifpo0ODbQtJolNXqolDUhqxqCnzyPK9urCD0o7zGKoquVB6aikNafybfQvV79D9acbsM(vtpWDMNEFvtJ7vwB3Pxi25knpQWnQUJyw7aMjcaW7egkjuN3mYg)5R8xU(EBReqk3VnCj2IwGVIh0M0p4yTPyu)02lN01lvH8az1kQDkJ2mYmV3LLhvOrgOFEX6vJ3EfCLXD1fxMOM(u1USpjX0Dllw4mBuOt(n0b0oXCshPXRrWJzQCE7m1irbuGXZJX4rJ7Qxp9QIftmfNCQ1oCzX0pHzG5yJzzVOykWBW3hEgVU8Kkq80RvHgMnxJE)Mtn3jwxt4305ZWjAG)61hC4XVMb7uBNcg7efWhyThA(0fWeNwrBAST4PBTSbpOz1P7f23oPIapFSv(xRivM1L2xwYpmlz6mGutWgryjz3tW6)Nf6npbjHrxsmSfzdi0Xo6S3E6KpE(XxGOCZ(gGpkyrv5YMVqrOBBSWkZ2zBkLvcxJ9XYzShlKHGD19lkxpMItsdLKwWoDCtk2LenDjEKxVEkkM1wiyoFzXNll(9XIdHD161a7AkvHnjC06BbH63wVyUWRCDvYFZQjWVst0QYfyZxpLdfrJo9StpMyan)(khN8j(J20Pq7eAUDgnmujWCkMrRGjTQsdYfN8YxX9zldkF(LRtkO3xfG5xh8NSq4Vr8jb(mvjok3pCVa4NYI9sJ5DdJIIDW1xx(Lc9rngoPaYK(9wtkXTKVOcfxQHB3zTxKZApyHx(O3E6lo(IpE4bxGoXas7XvDQaLB2joaNiQzBoN1NWCoFqFRwr8MYflkxva2OpFfxeL02khf0uWPsWakxA2Ney8KyNF)9A9SB(OPizW5in8kPNmxIegY3O4r(j(Ja2K8N779C)O0hQI8c2Vkd6XGMnyUepkSY3hZqSCgo)4eVr(rpuLegbFDqeEJj(0TeQVL4m6wI8GNpfe5u57tnvmD3rEX67lhE3qtf4Jnvqg2uj4ThfPULGq(wI8XV2dCIaVf82Z9W)nmlt3wPJ8ZFOcpvZH2kgFDz(WTe4fHpAmhENKrW4JAr)WeOtNcdRQGC8oY8OUyU26z(vlPmd3hGhHOnYhjn0tryQ8td1KaXnhjU5Trr9GUqesrJW3QFm(VrjH0WvrfOzZGhQcsbQqCq6(vj5P4nt3MxKHWNqtqXH(4Cn8AtItO3n2D9YKKk42atCGVN6Eb0Bnjkv9UT9oFO3H)ykny9YW7imNMVdqL3va9CFONfeJVTiv3bENGeTQSCDw0qDTqjvbzfZX)jL6JG8aIFkxmuGrCmoVNLa3rQpXnr3SxqQ42c3sRPNusLVEFIaNgrt3r0G3Z0xboKaXnhhq86PifioJ4nsKKCKJWNMpYWfz5edFgXIeJnAfWfVpoTa3teEl(bHeLMgs(u(jb3tgCpHidsCk1myp0NMs88tOBbmqX01BZpbDDEQv01hEoMgSznwoaS9v5j0mmXKLrJyC8yxrgJRiPbcUAZphhSb0t6hhlzUdgEiPBpsArormYPojTmmmJy28K8qYUAc1EE48swUpTwNM8ZtLR1Lt7eFroT6ngficZP47li3xSqdgCHy3nLx24hqJkQLJsfYVsG7ld6b5KCMyw2e9mHbosBK89KiS0uIx2JMkIISRH1sUtK9zuatckqlJi5HKqC)qFdzjTbzzykPQ3dcacqHYPrefG6fXE0iojt2791nnmjfIKHCIxpIK7LgrmJHbmlCY(9k9jivYX5PA0KGTi9JuCTDzvS(UTPMtZeLlLLNgsc79KDVihnNdPUtlVWDcOhfF6Bw28OSbE6eA5uIllmsmpTdCTS0THfQXQqKmIdPlrtOCKcoKOyTSh5InA5sfPToKy1Zi2R48ujNRZRyijKMNiwo7nSui98P8LmO8i9axUamLmniajv5mtFmlDmrUmXzj72elq0k5taStW8vAo8pH(iDnlL4EsJftXzdB5b1nCMI3Qs5m7YBAL4qA61w2PvEduDSlMLtgofhj7fsg8HLYO4Y93ISfTzljBJuPzscDucIJReI0LqQisZyBYK2xHw2IYxOz3CA9EugjBWtATrEBrg0J7OMbxrLsDlp6EtOL3rrzcvJH47djnKUwFQhft8IHHslWY2Moz9mPCiVTwM1lTn1rkTZb7WktMe60d6NwwHlpHBHglE0I3iMbn0xWPfnG0rTOuNbD)ThRvDlktvZWjBBjV6(Y2blqytYDeXnGT5AjdzosrhWHg0cW93rz5sg0bnxvt(dhKIYI73MuEvtfmOr0eZiA1fOsfAPyYsls4j1R8JKmTbBxUgBfNC94GMZPfz4yvW283KxZVTL6A5HoDMbhLA(60M(k1L4w16ZWTiIZwbAzSlL1mxgnevoeqzaNgvPDcXln6CkSk6cF2UbdC9IDQasZatbVbl2L5wKy4szmhA13E)S67WS6hrbHdH5kBGxnGKSAcJoOeK4YQY7MEpHt1DM)Fgbd8BMw6EMKBlBXUvgQGKr13xu9MYzlRFtr1MZG)785WGKsJyv8fMx8smfuGHJktwVRQCZDJRxuwBQX24DnzjNU2hUz9AEh76HV)oQc1yaiQN9Pl1WiQoeji40NoBnIL5HRReiEJf2Zkt0eEqDcoWrUKVrNZLQnv3SSEZ9fZ5Uc9azMQAPQC(f7NTxygiamXdwGe0B5bmplEpqamWZ6hKL73BXcSN6Spdm)bZNJ7ZFeDZ13PyDXWtxatnFghSQkplEVhTC61ygdDgopnwxKCocPytK76X1UP9h(OyLK(fLxFD5Snlw)1XnRCxDvOWkKfhdAAb6(qtngZGa8JmW7u0f(Y6LtX(kxOF4yaHJ4YQcoIc3Se48)vCdwqVBkcOluBunAkHNqgRIhn0M)RAyKWZst65GbjC0hNn9EmmHZpdOQCgRTqvZ9DITiwRGRoe4cX3fJKz3128ejtmZgQchHBHqdykTdjA4Fs1118SWMvfnpFI(V1vfgQhMfA1qBD(YIzWQG6QoQfBikSC97D1)zZ0LCiTwwVE66c167X9CW)W43EMDuyxT(VGEHU0FeWtPnk4jRGL7lwGKEEOOjMUliBsKFpwiw33YNOc(riOD7wId8oO7vGb31WO0QlaTrMAJuQxvOM9zg9PFUyo2Vu0kGaOYZFvEVjM2CYUOJqkT61nLAvT8dLMKyPSZdNEZk(qM(QP3qffJYQlkia2lVFfhff4xEfTIQAoiH()ISDye)wxC3IIpxS4TWSVnyH8PMZ0BeP0l1chHYDhxx5UnyGFqTnKoRQa6lMx4rW8(n1l)6LidWdeL(iG0S5oCj6kkwG0QiA3lbSfhm)ZqFgwy8mGj7EAuA(DU3nHQIPhS8U6LnFCVrtUT4z0p91(Euys93kMEp0hE2)ZZMSSS6tfRx9KAOWrNaKUNDzX6N9YIPpTot6i8rF2Xv3IsxrXOprAcRoNMFwS5UQvMTBl8vRo3vnrEqOQQV6NhPorJaX)tr1YSoaOPo8Sjto7nV(4XtSArshn5SZXVIPJk(jGLxplZHj0Wr1GnjaKmtJZ5i3Q6ucXW4GCnFfeCeckvxO)nMf(KkMRILCaFnQH506lVT861MMby4RkMRVvo2MyRxUI0gO6ILfCCWuYDyDe0247z4SjBvsSIZDInk16Y6Z0BoyZ66l5vp(6AM9fftVb6NCxmiqtz4mrW8I5qsZANEz9I5ARl4DUdB70nlNoVWuIXNy2SpNOPPyKBVrvOuWLNWR5kk4XlME)kwPhrI(1YvBMUGu4(WPNIoy6Ha5HyqMIUheetonwbFn6Vsqc4ZbEnkpZlJUgc8gW3NgHEDeefNIw2gGrmmg)md7f6AsgAin1E0vpkeo4veRb6ZHQRbCdtnyIxi6ca8CeaH01ev)d6aqZ6RUDQzHROr1q3L8PcURaY9gWtw6TLfhe21vrRtxty0P0xdZtsI4RuVeVsyBghgMqxdsd5ROz)i5a9VeVV0u(AM6ZOtC0vv7KrDBVCISXx)Jh(dehMSyIsehNfrZe5EzKxiqVmIqolkdPeGpEz0Ndtdh4kEFb07aBb1vSDHBiHCFocHFK(EpgFUaceICW)y0bUe03(h7)sTwS4AIhM3gnVIJyEuhNKqmwHbzPmLXpHANKiIpjkiHPujOpBedgrzHVpIgTPP(58vEuISSQRH03Z(hIF2tDnHP88mwcTf0EGWgG9NeC(JWEinbXGiaCxNDQdiBiUa5KVNG7QzHQRe2dHPPj846xAlD()Vn9(lUk6(HtCWttO43kPiAHR7S0eLqyxPkTekBupJgcQuHsk3ugiw9PMQngRTxdFcsVeyL4NgR1fEjDIJSKY45jYgxP0fB8X6V)uqz6HFLsod0hbvztCZYLfvZ(kRq6p0wQIAjzf2)20LvkfYogoYpaA8a)Uy104N5bM(ZDzwN2oXw2Q1Wm0oTddVNjO24N9Y6650hpFz91WDJoSJFuP1)zOcz4n8MYvZka6zvbyBrdZkSwC8hTQ(iOhU05OTQ6Ju8Lzl2aEgvoFEr1lrd9wnEz9DABoYug)T5URAKPN5YZfxZrgcxBE6OmVyYSY)cpnDJgHWd81llwC94YLykTx9PvhCv9NlS7LCZpQkXE4dq0df2szQdY41RqkvdVJTh9v2YXNUsq8BlNEVTI4gm6TNtgHcokA3UF(oBLL(ZUtWe4PCHOeC)rNVHPJQ5C(vLjzCswrMyRsy7Vuf5RpAz59FeovsjX5XZVPWwUgGwaS5BTz9ct2GLCQeh7IZE9XQD4JBf5txlapVy5fq3kU9XBQ64DJjFVz6xOTVeFo1cwQENXytQVNp64F9SF54l(4bV9LV54tNCWKto70hEWaCP8G8Fu5C1bbJpv)0BWyLoA(JztR6JjF68gLadmlZG1uRWSdYZldKvc68WJ7C4AUoyYr2hCRBnYuObzQNohWWm7DLMR65mcsaHuT9BrylP7WWIXhci3Bp(Su(erpNC5OBB)(kvQIjjknsf(BWnDLHH1MiFXI(WobwBZnxBMnz2KB8wcqSv2IPtxDo9rw1A03SiAE2fJn9O2b8Il5(7FmaJtY3ngNqC3jHmqKTcryepbLYGXrO5F)TZaLHmqQz6VXCqrJygZFGzGytzU8vh8Mdo9JxC8Lto7ITjsk)7eJvEA0pf)8dR4hVVtCjj(u0Id8a)hbxfIG)K79tPo)ZxQd4WXbV(GxCYPF8vN963pKjq(FNyLIdJjNDbVo9rVo988Oy5hefHzq1pLf9JQSOGVxMcb(Yrz8bWhHPYquicaYpfg9pFHrPJEXfV9KxSJwa99sGuyyAYF7YD()AVR2MABCGW)IkJF3oCFIcKwMc9Yq81R9tDmutAMMMWehU27y4)(Pv7kTRKStc9MHRDg4B444ilTAFt7(88SENFu9opvQDugNGIvwxo055LL6kymdkf(mvqyPp7n0VekGuZpkLpF8KZME8zto)S3E6wuazabaXtzlsvdd09BtQckkWCDzFoktFqkqThMMMafDxwCrQUzYIk2I01aG9UR0L7mJJuvFBDKlf)NLK6rSEy5RhLeZasJdTs8djt9i219WdYuporzL70lF3oTYL(uzMRilfoIX0Y0elbw9S9UF98Zo7jtGPqzOdYrDzkCUGP55JG2Qs5Uuj0bbPkTtp739VcM9InM92roaEQsMTYjk4qqi7BzLAXj0mh0Tdpls9ZViv(Hx87V9nF8IZMw)NNE07o9YT5hv2tGFuXJkWEiQOIAoSIQK)x8Akj)NbVMIt7x8O(Nq3MEGa4j4WIvdxGq)MQgwJ7VobEVbIYemI7fnZMF99myZKzpL)sMFmsPwS0Ci8c82CKGl66z(TIhCoNZVl)iHKIBoEVVE165)ZQLBAwqc7wwGuTAy8Ffq3YgLCjFq(zbLarJ3jGVgyBKJ)C71FrG0VfYPPH1MWG7JfJzWTSNBhggmmdlBD9t1N780L2WI53I4xfEs)6(jzrlwOh3xR)B8y8CV(AZ3jC(BMNzLyC(ZuIejcY5dMPgVA9jtMowq)XA8m1R2jM)P2ZVRBdIeI1crP)E51tPvsD5iZuGccFM4kcG9y4l7TRN)xnB04TBNKx7iEoeVP1nlN1wVA1InZVT2caw8TygPeNcm3wxc1O4)3eDm1NAVPDzNTnIg5GDWo4a8sBrsVpOqiXgc7bmS6qSqM6gX2skZoPznIgI5iNFCBJNwQqu(QNLkBH9SzLUAVjsOzF8IaEVVO57N3UCMgEire1IwwW9roJOk3pBFiHsln7qibAMU7F4TVJDuBXCoq0HTq3uWK3k(IJeI5sGMW0Rfedx5soHyXfrLLukxrsJsIZlQkskZeuWuH6)IgvfLcFAjTeR)TP9n4pomQ5s3jYuB8QnA0XpR0hV5UUHyqKkHQi7NNclzi47(zODB8rU5qMP6M56YE3uOoEyGoWkwlw4Ppb0)C5QfTQD7qHvv7RB)LlAfy)AmJNKLmMIfNtW0fl7njCjRumhSvrtKCvfZoOKiAQzLMLm1ytNqIdQbqsTavx7CrDXFpdh5Ohm8eUZGPpoIdQxkxth5QzyxRvC3XPwU60)CQj8VPmMcAFvt4c7q7leShPEs9jTqeLAaCIxiMiDiA(CsPKR5m7E5PH(kOB4kQg3i0UM4imVsMJQTmleZZ2o9qz58(WItdmKcRVt4CtWOwmwEFGpjAJBJTEv9k2IBhXqP041d5k7N5(rCJKlhXcgNXZRkSZ(busJgLo93iwWtVo0dJEVLfe91Gd2DlHU(I1u8cvW9hahOFouJ3zXgfhheJ)LQI6ViR)URmS1mrK9Rhf9EBBsSZQgp9m6sMIaBCnvaH0Bk3)w0lL1lOANNg8YIB)0(aGOES5NP2RqrHIxupUSLajwJP8mSq0ou5X7zQGyZQlBbN)ptAU3QospbOCrOTPRLlk1y)aqoiTCKTrLVzOn3amDp8OpXwmQN30rnITClwG97BEzaHXQTTyRLxL3ui1842SUBZs4iI3Sw(fQNPdSOUhwWErCspgXyVF7tTuVmrCOIw8dGI0v4cDPqWWZnvQ(F)d)DojzjhKa)vwKwKA25e9i2RyPIA2vRmhxRCuLSBw8JNE8(IsFQRPIIVqeuItC5TU(w9blGZ3EtFZ6b80bwvKqKcVAWeZUbTvAc3y8w5oJH4he3qxgBc7K2LYnT3iTQzQi8ZoS(O3cl)V(0Jo)0lvcENC0fh9kC9iwffGUkOjRkQj0fggjKuPjuWQDH3bHHJ0sXiXKa9Q)XQVJAZemeiQxO52LeJH10VSMnCPHijGspscW3WJL835Iq3jcv3Iq3U6QgOZOa4gBsbHAMuRpE8BWlD1xPiD89MXrR5(4xXDlNZaGSrSWLf0JgIFChMfmYLXblknEhhkp(U1DmR7vWyrrbsOYmFjVPZzokJqMxBuB6yOe(5TNrOLtZBHe7Ep9KGg50fraumsGJ9uWcWhAkJZMWEGyOXH0Txo28kdZb4ye3zIOYLhnDdwW47FFQkIuYKC7jerTNa5PfsVcEa2TV)H7dIOJcU67u90auqylapIHALqSHLJShw9pvKquWfCMC(7ZQQDN0vH(oWZxET8VvbI1Aflp5TDw8ADIsP39S0rCCzrwzuEvvcN5R(IYCwpxN40rn9fpHYprxT36H1Jbm5wQGD0jctV1YQWQ3EYbFvgKktfIycI0jxOgF3R4GFYUTes4S4hi7YDbDJIP3tu7gb(6K7CBP1ihkKBi2nx(NKIgcV(SEU(deb9S3jVijYn87GZSreznSaPdaq9LmwlGvrp7Vc1bEPSONxIRECVCKQsBAnd5d8qxpSY(cpv(MsxF9q5bYMV9HiP8m2N3DBMA)Ps(CzaXwNPR07GeY1eAn)DLG2YMfDYudtVg24FhqdSDJOPFR2fWkfDWO8Krwve2im0so(XrMyCh17PkuyKiyP2Wlpl8YmMYOrsa0dJARa607(6xxTCsRkYjSXjtmz7WSsZ5D0sjrx5r6GHkyT3kYu7CAxdDs2kKzMsnBKkjgZ1LA3RKU64WX2sfg8CAUmhGKQhGTHTdB4wne0Uo2IId)OAPhW6FKJwvpF0CDxVDGy1HRwT2HKCeorsS3yH8kG3sD(zXbVX0dr2DmY0PDyy7M8zoIU8GbNMYTkjfakS6nvE8Sfo5GsYt0IrZ(S3u7Qh5dj1xKWpVitC1EjeQphg1U0zZAibnu6xIjRNRIzDJAaQDaDSr7H)o14kNWRqvTJL(p(EP)JKgz6KnkSQJNWhngZk5vkxUNohadEe2z(K)VDq2cXGVFjWku6JCqTUR)NLvbNOj86eQTLpd04TxkyEF7pSJd8o2CwKMuyINHAh1ZNz)2JrHRZjjkiX9eZyApyzSoRoMhOEL4A2b(U7vx8F)",
                s53 = "!EUI_S3x2YXnos7(Q4B(plxyfCFtxPTsTcBzPPe7UTMBuqvfvvCelYAizzBnk0B0)5PyEXojqcacqcwlYYD3ZVlhXmTefjwsK5xUbG85pu7e180Yu4)8WQ8CYVUiTjbEUFu9KQ00IFPW0iW4WpuheLUk7Mjj5Pfgh4AZ)3HTV6VxygAzC4lKN8L0Q6SYIcYF3jAAcTnnTIwvKxo5XpM8u5QgYtmI(A20M5xM0mzo53nJoB8X3DssDZXjv1M2rNC6L3nPSmFA5xlQPnrts1S0g8)N8g4pr(K7tQ(qDiTfUU8RPA)(oVFTh73H)Kp235j11JtRlxvnjTxlqNCjftMxwvdJxVORtjJukbR8HhQtB(CX7TSCpGrEC8DSo8dIEbERltYkoMmqDIQZMsO8F8SrXTF)TfineifKEEvtwEwZtkDGPHJCB6fTmp5P02M0l64RIJV6s5g99wh4X)xazDd6c7OLPnkTSJHCdBzHt(v1nLlUZ)oZalJq77cDwFpzEGG7WX0ZN0td2sQeotdXO032iy3NKA6ANiGAB1PF68A74cKzGGw6hGKYq687(vWBOUunCpPJFt0P2rXxDTctH3bDx(SSLjQbar1X018UqBF1HGPtlrnWETe1EDRD7un0iG2TDfHu6md1MNlBTJRzQWad3b7ijSVeqh4K10t9Wz2XPuy0nnaUrA35ZoHv4gn(IZ)fvEXb44D3w2WTRx6ZXRks7CNpis7DNNPkZxGy2zh4P2XBM5t3cgSI)TMQKJM0aQxoEvttzrxW3wbfdv2DkE3RdaXEywJ(eWEtKETkYJppnB28gu3hkyTCEsbqopUCvX06NFHY3aQDpAYK0cc3zq0Q6uk7(iYiaj(e9Mr3dALdCncdmSdTmD9c8oK84k4XaFv7FWN(4zWuGoi8u0iFjQ7hgApM(uC5iqPxkHDvRQra(5S8806fPvP)6f8htuB3v5vTLN8REctz6LjfjZiR)dQDytFyhZfw3iQvPMP8l9RfznJQswKwZLB68cmgnABGCcR5f4MdSMxrhd86E9o2FSjkIS1pRJCGAfx7ubLoxd9QNTud)QczK1nv7yA3WTMew6AAVbbO2enKctSMUFy9UBE1ryLW6FvISPB0dLfnOvMZYlVpjNyU8zFBzvAD9xtEIY(dcT5zfPxwsb0QNNanYlKViz6uGXIi7gi3pJQYsjqlKLKhe)SPt0xYQ)fa76sa5PjD6iAJxpV8Rx9WdKoGQn4(zhLtqOmpKm6az70JPqHWWc(8S7rHDOVZHHxn95faj7KY8YQZj4te1B2qZmg(fd3dP4pWxEvr(txuutxtjaBYF3XeVn8iVlq2tw1usWcx2GZJlk(swd9tGbxzfawnghqUrtiyv0w4tKvTycXpBszXnnpLtivlakwvbzEut9PHmNAjdFQ8SI0fpnI8vK5joVnoW2fBDXRft5vhH(2uNIa1Xj3hZPqNJdiBbWnDmncPdhtPd020kkH(T0)mz42oy(LYv1zfZgrF2djmw8Icq4CeD0qwNgNodE8fWmSoULCWwFCOVcT75VHmnMSCe4HUYHF3ri9WG(DhtFKygHKy)O0IK7ZtNgJtLZ5lP8M4CoRb(R3K9ViezQshhzoY)w5hFg1LvvxwHEjMXygimgJgAnsIv1jQeEZFFo4UA20PPfJgArQZYaDSpp9Bq3BCYPwHNshWta4StYQMKNs14MaastMtNOIbIbscQGLLy6NxuwTijNo4RxMu94zcIJM(0fKqi8tu)Q5da7rh5pAKeHLQHVkzA2Q6cBJd7tyEzaMeTYu2rZMmD9u3otkxyGL8LN0Y8QmduirY8fTdFlPj6i6)Ezyyd)OM0V1ScG5amiYO5oo1L3T8HAlLsNOlWUwLKLpIAf195LLtZbi7N72XUrF6SF7SXYdD8lGzfWTNwJuTje2TRyg01J1MehL5ziEY8eAavkklsPWO4BrjDpZSj7qMjB0)lcOYmkJY5oDvvcrk)kj7nHzi2q)ARfGbuiT)Ez5cWlVd5)ovuZPpWSyIgItguK0e5S4Dj(qRos4QZ)pZbzvhN3kg)Rwodw5tpjjFYvlByeWhYQQBgVQ40sQ6eGWmbwIBgLL3qnYmi6K5jlwcn3iI9j)sAvjvC43sH)EsbQx4OPFbajbEJk6lD5tnZhHklNmpHgsgZWw0L39(3DuvAY7CTqRALgxpt)gcxl9NQZlHXjXTMOMACE4g9pxLUk95xyGc5z3dZwKBZfh7G26vj5hnLARo5JnJ(yw(tlbLt1n1qV)3xL))(FKvOV3fn)ggiBDVBfD()()gevxUKmZVSSS4DNVkPA6FmDpq4Pt(K88N20u)TMWdyEx0uNNr7545vWy4pOo2NoPxuw84g6538vBZOp8V))v9V)VZZHE(6QYvtxuwwL(h0IDaDEdyDl(JDTMo1xNPZ0yAxVmf68cWv7NrlKsZtNan7LjlxckukqWYf4Vv)8ZmdWADjJ(gHe7U)AlWnXhBtMB1ciBIvTm35bTpJQkxa24tbUMmDXnWmM(QoudobLChDs8f)2z82MAnk9fKvM5qnnR22i6yWvH3rmG9D)FsNf9UtZ(cyl(7UEv1YY60)VKwHBoyf14Qx(qHLRXpFtAVG305mFM2o3)R4C25NV1ztNFgxPj575NprA3)8wO7oP6nRvjkVDy3EH)eQWY34NprAlxZFcfP9(zCH(NYj9pJ2Jz)Z2CgZzj5HFj9gWJRpK(emmnqx3MUaEVRlRZiFcjWmKOoXYIfDc(uX7TcTOZSVvGXrSkn)6YScsUHp5SpftIvLB0sLNGbAGL7LqsUxSnTUZjWx0M28289(ITtIVPHBWo0fUr8TYbTnHEH1M9tK(wpQdI0MRC6i12YGUU1mR5BfbMEhya)Z2W10NoSXbHVVyNc4q3Pa8ErKWETJfAR(uHDG)bMEEwHgwb2ixKye5sgrwM3z6hiMY(Iu(77ttJoDGAg2UzscOpE3x16Stv2EcGtW3)K2pQDhvX6z)dcH)56yzz7zlpkq6TPvyqGLyuy7BtFSJTlWt59AgrKUZoi0ZbyRuwhu3yuKUZ4viFyzWBptJ7mdTS89VZ2viG4j2jr(gb2TRS9yV2U(7fg6ZXy4xDIizc(zmXJZXKsqclVucr0KbNojnYjQUjzYJN0gLA6UzaZizmGI0KTKLIYvlP5d98tonwk3IbyUfzrExoZf(rfRwmU8R1i8Ql7DINNn5XcOHebYpGShiUpRy654BQnRkIxACblo6SF)O8SzfqBLN(qJaJnm6eLDIiUpcLZPGitAbDcaVuK(5tphEFDLyl(HzAKqKUOjDbL8f3phCuYDsvmzFFkbkRpjkMEyUdzVvC63AILM3hbdNWHYjQpjxytiQaXnmd0PhptKss1exflEHZfuIJfZvB(YelXqGs2Y8SP9PcFUWsxEqm5VfscyPKf6UFtBERvxAe5FbFOqNgF1Lmuj0bVd7M41a2NexkYhKGYDmFLqoHRHKnoBt2KK8Rij4UHMDL2KX)b8thjOvS0DBH)2zcL6DshUNyvEujxIkGsKHbJkpall5s5W6L3AzzR3EzzR3az5E04oc3iXsO)OJWQcZRwzB11ezH7wXrPw)7r(wNGSI4xF5xZOMYLJjc6qJw4SzrAZd7XmRtOwvG47sQwybrmDKkXf(wiEpaoNaibnRCqqanI6q)mRQ8RNMvLoH9U8DsSSqVm8Xqkq2G4UgTddHKWuf5h9RCgT)aK4T1jXRiGRqemLAaYEY8qDZW3wf5kYYdTk0bqqvG2cNFxuG(drCMIUxBgPHlsh8GI8PsU31Yz(2O(N5Nth4R(Od6Lh1bqyzhbUEM0q2zaPYed2EAAqDOeWvXWrha22ID0fgxhQ0BbIHkuiiWrCj)68KjPZP7BwYQ)OVBlc0Q4tRcD7d3iorpePw763eGHln8adBGGJ0Y(vfun4wwrpuci2JtxaZo6gxHT)42cidM(eLgGPLPRLcWqNmexMdD9ruQ7nYNBdvdj8XMKSLvVHSlRjXSGVsaooP0FseUVpFj6lcYT8I2FpcVFxiiDqe8bpF8rBnlpKsr2)lZsBzhydjw0zAO0MSfa3295z)R)vs10EwjAev)1SLI96OVQH0wDDjrbYq14((GqDSrwN3hDP(kZ8HWav(IXmJs6jIPkdQVJyMbGOhNqjMuiRa8L)aSgbmWcCUTenQfKWcNgcov5EvJ(7D38LoT8TCmGLjWKCr2KZZl)6O1HbZ2MO3iKe1HyiD4quWP6Sui012hNYAlWP8jBS5REyCsXS0RaCP8eQVOBaJkmAeFPAxWPEvM04SzXlf7yewipeXx1OhJd1yGul6WqgN1Ns(DcCnaUIEhOgWRhTHAWahPTBOCvhO0XkktH(SgxQ0YT50b1YcdDovzgzddZnrjUlgMVIGZnlttNIUfTvEBPyp725AH2nSSEBxAPdJfQevqTuTnrbRciaYtmXAocqPoRvYVyNSlAYoowYV)hZGwQiqd5tK6HDfyJjAdu9ttFiTOgwQQ1bRTrZS2sVXgwlOm8Sk(L8ccd4BhbWqZb0MIGbrY6siDJks)c5uMOkDpKa4Ga7afiR(85L0ZuvSySzeD3DZip9Ujtv4EnpSBK(AxZWTJ)7o50ALTx9BjqS52beRAXyFK514aApS4bxg7Gh9NkACFM2obxwlBrh)a7lf1heEd2nAB170IOYRRCUY3KDKBh67oeHhTiSADSDT4MBbM8GyRsz6vgBv1ctD4PV3SVBOdciR1HI1aghq1tsO91x8WLz1CAZWMEOqEg4miTEJlBDhTdO8GkJh0EQxlc9qwSYX0SJUUSP(D)VE3yGOtotk)GTZCBG36ltOXYZ(yAdcJ1n9jBcwBnH(67hXtxgP0z85AtpZyTHPFlX3gIJxdU3GmQYaGCwj3wtAE3XkHHBhDJwtyZKaZ0c7TE0SDpWE)Lh)7nXf7(qdUh(gb9P3AuvumTq4dytWwJ4Pyvat3S2TQHwOoC7lCxs99xdt3KQlZMrp)gyy5yNrAcxYLPWyC6VzgVboP1GLSLUXblh0)edFmg3LsGXFpMvGhL16y82tzGthp9WrprC3JegbqxnXGaI4mmRIAZfk9P7Il6sn5iGIIfKZcdbBfwPPgeF14l(7x9P4J(iDxzX(JKgg3qppKLNt(nhpP)HwurjlaPiwEiXD3He3NIjprBOq0Omay)XlHXr95ChVWHwAEo32hpUiArrAoP5qFh5h)soOOh0wazcfdAh1eHZaMbG8w9w1XZX8XdoZgRBMroBHcLdO(edqsJ(lNTyj5QmaeDMXpz4IPLylxmBYu6fMrs1t0ew4EiESTxW1i6qha0lAQc32T5IxOJ1HAo6485NC60Ld7jETDuyXGkjKqWTc(qyKofYccsRtMCkgpsgOO9TfV315q5v4XSDhi)3ftrYrng66pYE(iX60T8jcRpVHK2nONAJAjTbXl(dqDPyNZH7YMVVD5MYYHqGzDbifN4FwOYJtyAx7yAW7WwZf5ym2X8NhlrUPNSD8q77Zs)yts(PSJTAVWgGCPhRLl1H3M93LfhPHtuh35XDeGoIDtkq60JylZ4uzrAv75QVZ8(y(2fL1kJPGh0TH1YQSfq)GhXzIu8iYbNMSZ0wMwTCj(45a5NKHk1KyEo3wN0VruMDXdFQKJjI3ccKwJcoP27COlte24ekGptuow(dfC(ApZ3cJ086r49AhYkzYAAwn93i78u8ufkn5UobmSfSRfpI7sxWpUoRhnkmAkb7EE6I0oNM92PIiwUIUtmgi7JcIqnQIM78XAuc0b9b1(b6sj5jdVwjANttAWlcabeeDt8W6YBL6slc0q2dnNLdtdqaLSAI3jmorFIcPZHd9mmoCOtp)G6IK5yHfIjYR5i8x9IYYM5eLPJg82fPS1NJ(ef5BAjDqvEoVIngPWIY(mzdNozD2cl04VM7WeD3md60TilsEmxys6zCbSTgPQLpDSMek3x9Da99r0wFn4tYdgXt6LotMrKE9TBbSGTnk)AGTamVuWSMPTaxTiughQXf5QvGr9JtrZEjndBviTyo9ATamT9bWo8XdiL(86qkKFDCRq5omgKr08K65)ws(kWZjJi0xK0jxCA9Z07xl6gjNqCpwcOFmJNwgMHzM)rS5sy0YSL)IQioDsFt2IL5PJ6Ite3DVIIKgc97aZaxtY(A2WZ0WWQBMATC7duiUGVCIof81HstGXZvdlUQ1lDTYnMd3D0BfRBf5iqV0isohRnHrkSfNZiLcAX5RHwmwBti41Hj)nsr3MPlwAzxhaNOJpwxhl(RYMaC(AVmLqnKM65gJ3sTF2bddy1ZmCWbokbb1PZjlJOwjmJCVsKLuCrvzXdRQWmfeevwoPvwhilmrYrep5sQg1hzl0XW230kWWjW0pKszaY9VlPBIJ12FhxPnUxDvf2tzKgf0s0ZXKuOuNoAB0b5imt2jWX6vRpYetkhNIsSw)xayfAOlI7ZwEmJZUJXNOrWxM8nAygg6cKsrZDpeZZ55)qli4akGoKlvIwgcMESSQS5Izfax01jzf85sCxvDMD094XcFJYxJmw9vbHUdZ8Jf1(y2xBt)P4XCToeBOsYBM3ZwzrKa3GPY)zAsSolpLKY9KTXTRkCUng9mNTVGHQ4ghKQ7biR1AuVTueurUDi7pxVzZ6XWuyVh4caRN1QAJkVSSVoRXEvMsQ3kcDw4RAGPgb5oryCTwtRARHwJq5sZMFN2pAUv2pYD(Ws4D)R12r)OzPfPvj5p3lsc0nycFnGCfLvvob3y9BW1drGyi3YyVqNFLnPlWGbQDZ0kHkOUU0L0jftknQZ2YnrMAmcKZ0kENUQgyZ)gyKstCfOtiLD569p78en8)Kaj1qV7cpiKPDH(GUBIl6w(Iks4IwKrFlbBZmEQrO3FJR5wICsjXU2g0yjBNq5eUtJEdRRoMz4hUvZi8F(Rz7ibsX3)psPHfwDGBdQI5QXjx54(MEgoH2bw(CT4MM22ha)o7pSlh(olPBPYRRsjxxzxUkVjdJio5VfVQQ4cqppyi8npMTmEG4l67Y4kEOSICz9Dd9s2FKK4JNXW5)(UjjljCrtVcihXsB)(LmLXSflQlK(k7siB2QL0TTP6QKiGY4vw5VKMqdQ(ao9k9HJfSk6rNnjUcQUJMfOdYJkKcY(IhbBmyJG(S)NMSizw6LKRqoYkUv00f4DehHpzAso5UOtiuAXuGvL(abVAmjEFAIrMfj7L3NwHgmqLjbJV70GYBDktDBDkz5dF0RV7llFCbjeFe3hH2fm7Qi8W1Ctjsoh4tPB0CC8BOeSuPWhAcSmft5NUhBw0JjrA9xYa1HupVj34HvFeSXL7Cl8RxrWDAEQNaTVl37PwdIdm8pW1X2Y3o0Y1pGljz75FaXgFJqB4RErjAUMi4LC(7WhPSvqjpGWPCrXPRkMLwYUkajj5byNz(v4i9AJtYyXiK8ms(YtyBXPAapLUFGj)H2HULT5bMasGvOtOLziBOBz44DGJLf48MRNfDSBrPkKE5ksQ04WnJedCzcgMGr1HeQSKYCi2o8S0KNuXFC717i)HI74dNqhX96TvyG4EbGCf5(IC89PY7aTHfgbluD0IKVrmcRWLRDf90Y2WOZM2Hzjt3CuE6v)(NORjsJ2otIURuDnpWYuSs1LgI5xe5rdewISrjPw(ClvM6JtK0LUGCnRZ5R58xVWFWnQ5qgKQaTH1PLFbphh1SD5GQmoEydi1ofazw9A2vCsnaPQQ0Khjznw3WHpL3WuKWUpT64zdFjIYV8q9LYYhEuRQz5eDkT33Cx5XFv5ZRblvH)cHGWA342HLcSWqChavv6RXkjJPRXHR7KeiFNnJ3QFADFWIUvpuvCWwnUoROiD6nP5pmIV1vOUE16JOYorMD(aeRzhX2tjeT82rG0qpPsIKi5MaiWY2fWpmXa2rfw184z9FmA0qfrmLr17SxzqOB8m17q1)DZxtwsU6tZMqfWwY2Ylc0m8gkWkWYX3WNJMz6sZ8PtONbXKMxKmKWGriMSQ6M0AAH7bn0kNQoqjRN0BmaYgeO60lj7(ecF3ZDBRTDmz7sVLjcbu3au7W2nkmDCFnJIGa69kHHVNvOnMe1VNrrqq)bbEZCsyh1TykHpVUdWgr12NO2yGxC5Gqghh3dZsNa1qreZPLnAZY52Ir528U0gwvcR7bAUJhPmuKRE4Hpx8EBCytL06ZHRejl6xQAW(WoZPgbx3Ui0eyBNUpuMKrn6rH2kpW57MHhKoobSvyTfDGNfBmfY5ld0N0A7rSYgi6SPZsrt2oWuSL6KVSCKkSu4L2rG4QSbKEfxAhooB03e2(6E4ANYR9AgXlAC6Y2HON4MHbS1Zi4v0G0AsHJygBqek9dTcmCdd5T37dCqGeFhdlBhNDT5TAjO85SMY112sqTIoRGEVyt37tSM2r0YV(TrbDS6XBqdX4ZnWJJD((W2DYs4UCHTWAD(n9dEZ7GTyWUDhj95RFlx(bjV)g5UaMSjxxXTm3jSD764icYUPHTbV3Sz385BxNOwgMqoHWG2rUq0YXju0XMBM6IBFVxKQ0jTnVyg47jUVR(oznC7ZgBzfS1dsABWVqGS950sVGW2B6PDJzaw8(TuWEK80Z(wwdF050Ejsf65YzkcceKw4h3zgx7xnMfEluTCv980PDvcrJ9aEVTDmTSaI4VuRbNdQhYjQiKcLVWJmpJwpYc9T7EJ(FqGDiZSASJpU12vhwgpOpNPDJAhHfMAwzTfDhVwwTdRE)nd1nFoFxRk1BFhZePDsRlM6DG09pxLuLkQTiKYRcZ7js6Soc8fbR1u1ITLj1M(rQK3UKay0ktcED0DA(OWnMlPDX7hV75xwvCywtwThc9hwCaaNr0HxbM9xpMA)d1uiI(9ltMuvY2uDGneZuIN)cYFStPsODR3Q)s7KTvkPdDt2aFsE2KhJNxvUA28rIn8h0ipYUBbw7TErXQf0feMjuGjgun(mJDS5hBC6gsUSOzlcyvQCrnb7yLlHLoHvhCCk7FbTmTUO0EkJI7M(vhjUf6gMhOaSDDb5zvOXWYZfTbp0LVJW4(9oA3UIzEF4HR7u15XyhE(fM3WjltpUtL9O9usQVYEWRWvS1aMHY46clsmEdvJBiYclUpPHiqPeEm8XsNnHT9yx0VYKSPXVVYI4242ao3Uoz6uXzGV3fxclCKkfyL3Z2HRmFkavlft5f7ibHNcI63E0UUwsEDOTGvqxjr2ZrZ2LU1qCLz(AjA2O0DNtaq)dYeX)cAjQtFUj8IQWDAaHT(kYKbhCsZofrlKoEJAPLXNfiyclbRsYHtBXqCZlrU8vJoZiji8ZKRYoINkfbf7wueLtfHsjJ59SBwhjWrXXqsMR6wvOH(52qxg4MToEy2getWf7jpL3M4HnWX(q35ccHPXLf8WVoGJcd9X6PW91fSX1hvO0bGjgaurDgmsXLH9Ak3RPCVMY9Ak3RPCVMY3EnLsbvA4JNjpk)ogBEZpTRkkhADBiU22us4FGF7)cw30E3aOu1UfpS6z3NxBFQvh9ac57vuVZkQV9)yuu3ki9)80uRxPZ)HPnwpKLgdV1RoPVD3Vcdy6F9arZa4F4QPJFRut33kfRHX77zJZRuf9N)HRIwFbaEa9W7O(8(6z8a9mZ2GhS95EJxhI4Ami0j6U6KVqdiVIUyv4SW2ww36PXHFNAChnaLOnbT715(FC6Cn2RZDVo3)QRZvC3GUxL7pVQChAx7S9QFh9kv)oasH(LVVdvPUeNxnn(EdU8qY7dISPrMQJoy9x(6dqx0t41PgFOLUHI42BIAFnAY7ygW2FRS1LPXkA1YxfINEEPHvYRO8CqE6EqjdaYP1wMDuV1MmN57sd2Rorb6Gj1R3tRnqdPdrVUVbSysNrbdBT0GhzsD640DWV1QDBWCu8wf63Dm(OVkR90PetNfG60lPZQQDxF32BDVwZq1QjFqnM6mATFGIPr8mCVoJ96m2RZyVoJ96m2RZyZ6m6S5V3Vtw(lyW6(PmMC7Kl173Wk7C0pgkMD7wkUgYul9QTEtIoNo45FqHMZCaRGgydc(x0yZnGvB)4cpxq0LzWKEFoX0EcU(5ME0ECL2NHW97kN9ziCFgcFRZq4FA7E24FWgISphH7Irikh6496A2RRzVUM96A2RRzVUMFa6AAVgv2ROzVIM9kA2ROz)2EC)2E8hJAg)9PPB)boF)boF)boF)boF)bo)hZbox(wSC)joFhpX5o7DdCVBG7DdCVBG7J3425iO3Ehb3nhbrgd(n4jRObGtAPlt0ttAs4fxmSGCt)le(IJzBrlEtOQ4W23RZWWa0P6DiEhFZ)ME3vSHT3zPDVoxDfFLkos74HVMt6JaL7r8vvjKcA)40fa9clynHrvjztPL5(Nfv3HRAMd)1lZQfv1VAbHrOGHEjIFp86RWsKx9JpHvA0QYI)fPaarydB(k9hEOSI8saXNuMICJMtQcnXViGl(uzbxYBkBJ(quKSAbPNQX6sWYQ0haMD4fas1JScw(DWIeweDj1WWtZQxMN80LLttHbYcAbmalDlfp(0X5jtE8VxwWQPMYZj6YhV1llNQ24YZyROVI1)BYne)sO5P)svwt6Djt)h05)00KP5pfZWXboZzi6Wd5jlsbX)zRsP35(tQYwUmh)Zb0AWWdRQWVRPUPk7XukfJxJg)AAYYYI7slMalUnytMMu1aCjFbBeROC2jiiz1ms5p9ocnHQqjJsCBWkQrYcOBF4j8JcXbFnq6X)kHuD39eAfw22ieB6A2xjfzC2Qz5uYINLdVwGmjljVwErmMvOgze1FNo4pdh7Yux6PZmb4lRFEy2msb)ipRgGQHX8D03PgRkJL5iRx5cCWpn9H7Wrqm(zP1nLF9UVM(ufmYkXIePtePUhKw9y7RsAQhqAhPeQbTFnHpbBuaUhWDaw4fu6100VuEhzit)T6NGL4YgGrqp3CmIF3qMxnTcEul1MISR0sl3tmuvldSui2sjcJMTlWkuTwSU5mPs27m(fuSUcJKdw3Cid(FL8L8cypPQcXUldag4kGb(Mg4VKaS5xE2Px8Rxsg6FtPIowkvGIymiknjRW9iA1M(htKjRQQlRoQPjzYCrb(HaVtwno7BaxvDnGHV11Vh5keKv3A7zN6j57DzyZQRyT)z9fRvR2lI8ahXTt)7FT3c7itJe09jZtAO3N0tWFiK(dmJrXlNA0gPBG)hTIv0gydudsnt0f6MGO7UdyhUNAYVDu2080rjttpnfyg5vIvrj3jGvJ4QsbZC)skVyfnyfddC)bhcChYukhxuBdbLbaCbfEHWfEoNx5U0PzneW7preOiO5lavqCRRiF6iIVltXsxfTuivU8ju)hFsa8NPfZywtIT)yvaf0XOMsac6A1Q3Y7DSDOlybHwbwwIBQEttxNdcj)ZY23WBxU167xC9SapuGvdaoJSMYkKuxM8nA54TW0GzfmzGlxhrARbvkLGlq5lOcjLQXR7YkwbYyv8JxqlxXLMlKL95YHj33Azfli4Sxx7zvkqZ0arqjsgKhsAk8jeE1U0Apd3dCSTmmd9nnCDe0AdxRdSDC9CGNVt3D)K4eqRyBu)kVQGwkPgX0PTeCSViUCjUxTPfqfQ)yFSCwCY9Xc32VjTHuwvAzopMxdNO)vWY48C0iqIEcaJFXswz91l6)6IO)RlFhV(z(BLzyDBZtMQt9I45UIcsLDt6Nr9dRLdNFf9kpabJbzLric5NfVMWGd89CTDna0g25zsEfxOsrUGZyPPGZ8RfznJiO91yuR41Ix(JawyaQGwEqDXALjZehYp2W91h0ZwwJkQxM2el5yn()J1is8hFr0syne9(M7P4hTL1ntEbv(42Qgyi)KRc)HJUh0zC)XDRCw(bo2M2(wUoHgwIcNLj)rMHEgsH0r9XibwuXJ(mRsqCpySmwBDSWXfmypH6j5javnTOrX5p(Wsikk(JwSjepwpoSsyeBQR4ra9XsUjd(ou(10k5iuqkVJG7Llid126YhwZKTXxNvo))mVw2nbWabMJpqcGf8)uCMf9nMggi(r1K86C14s4eEYffkKa4sahMVKw9fiFfwU4Ol1BZP1RTV)mFUPSeZMB0I7RbFwCb5BQwTS5YSPKQJKYzywujQee1yQ3rd8TDS2Y1xe)pBP6SwGfpiXQtXB5HtST(xj4laji0e0M7)i8x7XXagndycGpzufHGn9wtPXUKXuCRikjsRf3YliXls(2PPe2Z2lGkAj3NwAMXIChjqmaeuHsx1Tq3flmxYflxDTliQ(P2BQ)zoVcY3FsEAsbAjHnk8qkqK0bOdfYJpcerAqilDnHHL3rTearXxMYqRe4izwCXsGA9kBmZIAE3kgUAc)dX)fPwSD80AoYji3dQqird3jnOqp8Gs0uSvLtzbiMl03HFGYOiMm0XtCBPKNkMTCjzgXx2eVlzHzmg(ks9iexTKNq0f4qCrFkLR58QYV2mVglbGOIBCc(7SAEhP8GAZRAXsdjjiztEboewhjSkefpFSCsI6gVaCtaO2xtvIW4yJva)uw9joYHIlkpURz9aLfNhxPwB1fSu8QTgRX(CpEo1ICdXvEIliPtVMXU0pwNYttEbCtTt)mpqzK4SCzs1J8AbmlCBYTGSIdHG1NiEDjudYwdfxAdCaSjeFoPRtXstXBLFnrRTDhkCK9MJXel66Bb7KXz09ZAjy8ZbPqEtkeDHssHkWhdh3Fd2sPKE2HJ5pZ0i(Qek7QFTlMBNffec5TAxyKuzOl5fTszT8wqZWQsR04EseSz84gOdZOSJjTuAdwz1DyHrloqGiHLGZ(2YmCDBfwQpwn8Qhy1wcFfkRSyVozYJLl4ynaKNl2Ean3lSyXJnXqfp0c7u3E0WRvfj)NNX(5x6GdQq86I5eYx4bY0JD4JSBLQKSl0KZSRucGvSxOVTx(YQ06G5AfoaZtlghtRHmCkPLABFtjUkM5wE9m2yCAY0NgALlSDPZ2TRPO3Ybv4IPXClQ7yAWN5Q1rQkJv1hC)DjYMA1FwOI9QcQElYFeWmDvw(pULK0rVJTci3N5BXkSj68U(kd)nZ)7OcTHeglBoTMib)7ZtbSXeAD6pw7f1HMe5z5patWWjYGL(c0VTBGxlU)4tyWbLorYjeNWlRMRxHJJkZEDsvZtmHwbZ1r5zZKpz52mYklu4TwIdJK2Ym32qwfYhsAyTemCKvYyjZU4syGPmP5KQymbQzrzj1FTb3ro2TMGYkbZm5hwwePgiGIXatljQ4lPH7VD9v2lNUGzhlU5Eunsvc8iK3qD0KrT7si8qHyvQ86cHzcFBN6gNDy7UfWZUR3cBoVLT5RuwS5wUJFTR93Ybw6YPQ4LJID(ttL4v6L8UxKn6tDw5A2wn8mz)mzw556YSyGen7uKwCzYSSjD4Vaym0Mr6N5WkdYw8ijqxyEw3slZyJDsNOSM3aZF4bjyi3DizTIo9yokiSfu5P3YDhNP5Jg1N28ToAB0NP17N1RGQNc51fSI16muNaz4Weg3shI6yw5A8YXcnzqM4ifgch0x3RzoKOsd07juh83H8pkqD9sHVQR6rMlEQGWKiH1mFTXXO7WxSMiQ4)8)YinyRAmxEiv0HQtgfPmnOUcgGnzNGgx6gnqKN6efGbmfqiqOF9UBC4KmRpwq4UwEQoQxCZ8ouWuPrQBi)jLIYILrFWVtwbZHwTbTWME4Ugs(kSchyYAw4Hw9zmUlIf(Uq6Bxasd4rUJgS7lkMMbEIxwDBXUIoT24GAB8wghuh3xFCqpimW3ZLKwb6p8AclQ2T0YUeouDEo(dpmOAdX5ODn4K87eOHcoPwlsc6iPXSmCnIVbhUTH0mSlNReaNIGO9Bs0ozTRK1dw(sl2BFCoF92hU1HeDq7fI3(WJQZ)rnggS7HhD7Jg6qgG)diMOR1aHEk9jFEcW7OY6z6TZ6Q1fJ0xBqsh99hK0bumArtnHe4S4iYPZ(PxDqv7f8njcz3qkf0gme(plx)TnePF5p3GW2nyR6crgzo44j9pFHxgAE8S(p(LxtuC744hFnTJb3byc7rwH4sAsEJ3P476kTkQ6hp44IKjm9lj892etcNK76LR(qsVgJ3CzldQaWCFSVVJV2dfI61K7R1TP13bNv1KoifR5Dn2yWV1KXW1g0JbY3dzU2rB7UeugyTMYijwVL4L05mYi9Pow4R0WrwQx4(vaKPtu2HvP9PIMHS1FwoCC)96c7Jc59c9pFgHocjgISqR86JEO2dvWa(SzFapxCKKYXIXS6kyFzUHczIAEb6fZXbZiG(W4Rnu9BBG1hopEBFIoEZZkWwfZGnLeG(SxIW6TTrfuwLjFpCzD4ab(NeiCvgcXKoKXat2)hBtUohmMg6cNUMyY)JmlaRlDF6JEJLt4bTUksqlKJ4RUSNV2GpTnX8VBmB0hTFyfRdhIyftkRn92bdRlLaVfb()hz4txF2A6bP951DXIRpDcBk4vwwDj6k3V89taMsOzoBXYMNwpUKSDRu8jRorzrn)9RjFD6YgHu80SpuNEC6GJCENOAd0UDAK6njQ2AtSW2Ln7ozT8L2n93Z7CGSuccLJUGq5hnuYJ)RtuMm)oJYK7Hdz5eU7YEBc20REJ1n6pHnwxaMLZIvl254xTM4u52jovV3El38Do6Jgf9qkrprs)q36Ddg5jnUAwTlEG(Q2UEVNhTUnfrQG)42WEXB1oZl(p1DMhgdJ1ffQoUX1QWV7(2ZlKFmuCnm9p8noMudTX9GN))N9EsBUTns2)k(pG9d3huFsY20r1kBPNeZM4TsvPGiHKWZuaAjPCSxv6)(RpMJEagqsj7KSBTzRTmJibMR(UN(yF9j13GZNEz8tkM(27q7zF8Pu63nNkL(hwK9nwWa8SdUp)(zzmRx86NLz7FOagVdVH8ThLvE9Z0GOsiEKGXO3TqoW3mXl2IrGd9RXioPyVTwCe)Jn77MJoEQML7Z7g(UWL(3mX0NBSlgAnn8xzh)0ZHfgwnJE7LB16HzJvOlg4bKKrcwrVwYSvprmwqy(TkF3NZmSqApH04ocZoHI)ADWLHp20XCAXZ25zJArcWvOz18L1BXpgBZhcBnvz(dp6gh6XfPVl65MHrDBr6bF)dvXNGD0)b53Ib(XCCVk7nsEgZX1p3axCBH38tl8fJ32TNU1lhUNhecoW)T(oUpie(BiDG3dkWNt7g8D5bH9Yzx7Y5KSCoocCofi3GZ(bQZjIpNJwwZvva2lvPg(K5PwNuP1fW4icTEjCLFahCpyb4pYlu2MfDY36KCJyYVgMOtr84etoINM8eYq8(5BPAKZdYu5HEEyqHidMJJvttsqs0tldM5jqz6KAEcuJCWtyOK(9bpeIJJuJsswKo75lttlEklp3uk9BA1zc8QERUx(8xECkWAGn6rrcBsZEI7xcO7cncTw4Lexg9m29HshAQpcIIm77IaAF3)n36e9OkZFF2afD4sVET(IosJzMv1OlZyVA(a5yIfy9Kb90YSrVr0cjtaq6FDLim9cklSXPxU1zTXfjh4LwlZrbnl3AxLzlbI70IGOKSYWyVXO(7mLrXNvE1miS8gtZroVt97ELNWTp1ZlQrjVc3z6TiRnR15C2zye9HgjcfgE6EU(0D4Dnn0q1bV97uErQNRy6FJmEJ4UrsDTVrLts3wm71xhfJYfJPnYwcMp)0c9asVt3CL9QasVh(ithqB82JRhxttlhpE(PVjVJLM)BXvOE8B(GCLY1UwMKMz4FOQ6d5TULrFX7uL2gvfWtR5ABhRgI1py6h5q11Yy3SYH7CflWgTRLIJ6vFsefOg)Y42pUp(873FX95V4(8xCF(ZN7tUuBeqtO1QkJd5(SIS(O)VcR7qoku23JKrbBRiP0lUlhXN1o0ZrCafTU5wWoSJgjk786nBDHmbvCdTZv25fWx2dLC2OeV7LBX9Kxh)U5A8rsAG91F5(Ur3eD5wYCuRlot)oCvV(dyR9L7J6U0mR01o5E6yeLJZR55k4zq(o98ZiZDCDYSRrCGiEcpvV802EcR5N5O)AzWwZ7nFmi759gXf4n4gfMnYDAVhzgL8uzWnhS)Y1htDMXcaaFxvEpDFckEvCzAqwyEurY2sHd)QefvOWXFZih9jEYJTrKGnuaHNAi1Orr42Ylup3Q(wV4GXYjqF32I3kyGLU3)jIRKV8d2XLY7TwfmulR(3D)odymF6F5P8inqLSr0tC0CuXV75ht9XTeLaJN2(ft660nr6xLmAaeSFHC4i56spKDFiA(VfGHEV3WN5jPH6yfGON61LmUZ99M5roBAj)9rdpIDLeSEZQAVrmX2IpF)2jT1ybYZDw7P8ij3WRNn2DE44oFzuLm8Y78CJodt0m21VDBo7pmpNjvB4YFxTDDynz5F7SrDFThDlgo9TBBQMs9spz)YtvLXVFMN(Km5CO6mJKmrJtOUhgG632yp2y6x7XXT)RNbOgpZpg54U1Xkmj9vHfPQ)F5FM(xYp48B2)sP)BIlLgc()JL6DB5U2FguV6IOPpsLrltSEjy2Iqv)mh2ds4HAD5xHu)Sz2dFhf7Ez3QdXbvXxurqqzYnuj7nkFYMQ2p9dvRp86Rx1DQQVH8(UlXIc)u3BOMmAwK9TPdsqtoGyCD5dCw(pVVEnC8EjTHCcyT5ZF9QU70vp8iSGIJLY7LF9h0qlDmZRQSI01r2mFgSOPvmRioTgv7BnwhEGZbyXl)CeDi0OJ9pUzrCJxkFBRCszdQEf9HZE92yvOAZs30TEtZs5niAdL9sr2UOCbBJt4iUxrIOcICs9gtmKPkg7KjPIJtXI)O(fUjD1ONJXEBHBQq3zzggrt7kShYDad7o7ScPo8Gr109QFfHn3R2f132W9LfQJtjm)zFD2vIkKUVyzht0YEAKttKzn3kyfjAhqmth8DC6mbXcZDGxZjuxc1r3a1ZJUq0hlU8Art4bJfOQ5FszTH6X0HETggEgs0(r3zM46alikiRT2lQuZwezrJUPk0rudomM(zq8b9x77gEccpqglZR)FrYDej8NA2CZPx()vtgHp15e0zFOKs557vki4kmuf3DaE4p2AiGAUuq1LydFNeB47KKQYXk9jkA36BQVQ6(LeplLpWny5S(mf60O0eieVR6UwL)zWamOUftvNM61NE6R5GGdSNcRG7Tu0XGiQS3u0alo8p7hCyZSN1Qi0t1UX0cE1M7RQxd9jEmUCgGNEojPwtImyDf4a(8BNRJruQ5nF(GaPJGeM2cHQgzOjagSoYLyBdYqHy3mZwMpXkMl(KGSFCogTMSu6GKjg7yURTC2RN1SHBTmHf9GHo13hw6lXxcd7RwvcUCJTHBbSApWEdagMpX9i0FDVwhyPzwPCzqEEgQH2cUy8nCOyd70jiTSiDUGblVq5ydcJB2wkETXYRv89UR1(WEj3kBkRa0ZdOy4JqvKoA7XhAxMSEMGcPNGFJlsdKYeCUQI8jlUB9h6iniSl(OsJVmoPB(N6UFZHRb5P)2cuhZvDQ091zt0JitI3ZqeLWjt0zPvNjqP8PqwUXBJTAn04n2D)92WxPC1tpwc7Jatj8yFUgO5Znj3IE1FtpLXI5aFOT(Eq72L2GMuCFkIgquK7nuspAzHTaOLksXVOK4(5ckxNjlem0T6rvukIhAse3ELu4gc1FCDnQN7GQARgSQuL)MMnx29fsS8h1Goxnr6LaJrLdlHjkfRa(vJRFHw7zhxN5YGAGrv8nyuBN9YmR0VOy7kiL3)PUeB9jGfk86KhsOw2wnHT)MQeBXWldLlfnEABoUVH5kj2f2(fP78HjVhhREDGolAL8nBTIqRMXHfw0M8Sqt)zYQXItmOh6TQ5TwCphMFE6iSKSABgB0pEFOa7lP(JJFP1tvn71RUQhrOvYZSU7(OtR1sPlKf(BdDzRQpQsfKdZR9zTVQAv9Bx2SP2UEuiLs7gDBPPFhQDtso(a6MQcxXg)DvdN(H4(q6Lh6CyVlNk9J0bfRoH6jImlJhCQt90A6OWaFrWisSbnPu3wjipCGCZNu6nlpa1a6WEYJvgWkmolLAPpyqR9ZsExzASJJ1yZdSXSFjiiAOn4kh7LQ2EU6a1tgVvKR82dWUAPGDPPLhlRmicT81JL5GWrPNYERGDJhx4QPG8IZa(H3qDF36Bjoq)0nG57iqJt5QbnP0xjzbznopud8Q1d0mNO8Zr)W9X2y3TOJIzbAG6f30uVCHalqrIWm9uqro0myLFzEZYmpjqSSyYx(KAiH0y9Gwvuii97qKdWw1DurdCHZuNUjepxs7D7dQ29rvGJaKbvTrLLnmVcJBxLkf5KhEiVAN6NtUuKYB6Uhw8tn(bVhBIe1Sz5vMDWGqfrFPB6Rwh1gWER30F6ODU0Pko34R22RX6j5H96j5UML1ZmcqFynZ8rRcBPkwN0zKotLmr1bQ1AVwdUZdAt0DBHks06Xmqjzvnrz90orcavKMlpFr9hV7or(8y1ikT32HDB2S9RHrEBtBZtrpwvYPkZyqYxOgNI0lojImlgloSQ7mMMoHYD5RQMx)lhUyXPTR)fHxD)LBRx0u9l0J(l2MH5RMnBQrdNdxUuuWiDS9WPkrqxK79lxIRbLiDHQBw3w5tjjUFfwylig7xq2nuUXp3w4p3qtjnpoPdZjwxTd3M9hOVASocBFSdYAHOqYTvWTfpIRz9rzEC7JrmNQAjj0UOh9NN7IAN3dMvbex9VeaRN2agrB66QvpHZ1ihfb9FpbdRGldyd9YiwYwFDLfehXU3JG1zF5wWsyQDxvKQBMasU9aVcJiAJ259Y7Y4rqU9No79uGkSqsy54pjLyBNOBDWv9LH8YqgHw)IjDrtphaRPxVq21Q1Of7JIroB)9XnAgPu9msL4upIRySELSNhM6B7NXb0ARmKMbkuDO39ayDw0G1NXRkYxqWLktAy1(etscNb8ZALw6B5U52xnUYrc2ub5tpTEeYM77y0V56kg1SobK(JB5(BQL0ooF4fFrFR9gAmyh2QNqOcH0weaqMa9zxgMpKcrxggfh6YIGIGYrfPr2ebSVV36DjmOCcsl(ZQ3SE6UlYSSVyD9rtIIVQy1jCXRJn42zNnAsil(9uhMNWbPEY8g0)X84u6jDCu60BSczk2AGxFs1L1lNzkK60OD0Q6QpHXFNTUx8M6katr5BA8zoUf4WCI6QHv37ao)MUg8mRzk8mD2CeYcyBNC4rV9e25lA9tWR6qzzmwrLwuTeGuATqZtTf6DRgnydWvhez4A74wY)5tTyHdUmYcFIvzU3apcZIbWDbXNGXV(HJ6)lR32cehjCLPtSTfbCjSWE9P)4hM9RN92ZrSnwTF8vbnPAw1Fcf3o7aw)Dsn7CFTspVwjFRX1YBzD9DlB2mL8PxpbDwFG6ybuQ7ru1kSNDVPc5NABuuNTQ(Zn1)2urxKxrGgzjDuL3Q4jBUb4EFt3Yfof7rUggC)6zWVsaAvTqU)0trsrYKpC6hElHaA(91IHlHXpgEofBbOLwiACSI)BfgrPGQSQ6qY5h)UFGxZweuUbSRdkiGlDyu(RkklldtW0E7a7V9Xw4VXSzoTOmpmmjtXEIux(QRA(sT6I0jGcq6)BdakPdyJW3ZOMidVMsjTxIdThq4vo5h)WBE75)6rhEok9h49JuD6lKwRUaGjIcWwWHgoaZ52aTII49nlx2SUgueyXAUEqP9AtsuF(JkgdiFP5FsCj0zw47V1PHULtQWJbbCRCYLslyUapyidIsNeMfobqtkFzyWldtYFOnji6G2cyfdCqbyj2VdlpaJqSs2l)PPztclFOnph)X4Ia9xxmjmbFD4RZb2maeKE90eCOscs1pxjmFp0MffcFDuubodz4JNKOEKOy(rscXVoinGEe8XldcP5Sqpw58sjbhLOuC6kcHhjkibF1u2fZztG9enIHXzWEjh2kTrL4tueqlXsTJr4PwEAS91a8kPzbUVsEm(WjX4PwES(iq8WjIholobx60zuwyP6fTNObWsibprtWznmf)3KSyA7wi2C54MljhGC4(poiN2Cb0Mlxa4aiuACicGH5nlnJMC8XckKNvWJbA5aFpT(IOPndhEAYTlVqy5H)yoTBdkWNalBbWZfHcMBHd0dEaW)tXzd3QmKjkexQL6OJHqkIehlPrecuooQPf0bEM(Hjmw5dhLdG)0iyeZkXfqiD(eKKk23XighSUkX)jN23XzfesAPACPnEMyCbKwyfNxc)tCi(gf5e2AUDzd4FPsqpbhJqKSWsGYOnkPaFL00s5Ix(kX54cIbbHr0ZslUKC5KiXVYIWHpKqwYi0IY4c6ChjfBXYAbmS4pNIJDbrfgsaVGWmZOM5IiUvSc9PJ8f2o(HgO6UW9tY3cufWsolmERKcr7yxP4huSRtiZ23zTrJxaIWvugsepeyOmxc4K7)eCNNNI4ue3UKcIFyGIAJb07c(Qy2Lbph(6LetPuMrg9oXrHIXdFoKJsgYbRGoPIjo1HXHY1PelExVaD26WYdrzlZiIyIEQGiaZ0C6PvmWGicbH5jLeqdjTtj(nbzfsMPH6rgGlX4wVmKqtigJ5jeipoIrCZoyu8WOC5YnqnOzr7I9OgZvUb3PuacZn3bZLPRrKOIsswqAIevQuYeqkyuVIDWC2Miss(7(sD5qaNMRGRWaMt4yXjsEioRXDjXKeuLBikZtijFj0crkXpgjeq8acFbqAPTdjgiowEc5WDhN9ImynMhsSeiiTfgZs0CGyBt0MEd6mfG5WaMmb2IPtoAMcdL7VKTi)vd4Kd6EXuvs7Lt6neHIMkze(uMSktsI4qTUn2aemEp2Be67EG1g3hfFlshzX9s6UTj33S3Ce1bi4aqmLy)r7quejCkglGjfBxbkM5Ju4)w5cP4BwSl1A1OqXoc4WDygTyYiPb5fmYICOt2pjbr7qnfnNBjwpk8b4tuqcMOLmrCNKuiial2tg2aHkrUNNtuCevussIZkGPODKXTdsBAOD0fBBA6PKqhTNOWjBHPMsTUSDqJ1IAEb7d6yjG0llHxwXom7D20B5H5Js5(DRNPQZ(09a3Nuizp0dHgqhSeKqTKWstrCCqPzIyOuQpF2o0Mfz(DWUrrPvPCYZjH5HfelXcfshsvfiGJXB5mvHsKUtDNvJv0wSnqDkgTdbmkGs0EGSMr8r31MKbj7gsWe47IUwBLOJ(hJlfMvYAh6wPpMJ3bxThnUwI9Dj7Aj2RLS3quXlkfoCAVkTxE8s7DoLVk851E)odCZY695koyhtbZG13LLwpXqbdDeFLQ)4DZ7UfdzF0li81xU2EHRgNKSEg7DqPtIBABUT6oYpv3A(Vli3a)(QMLt9xwKDl(uO7WwSOR9OnTImbjIgK3HrdbSh476T722M7VDA3YMUpQIBmygvoLoN9k9N92iXW7EOB(NUq7ZqvWasXIu18nOJlntFPUeN3AURGhuP(iFPK8d6eUH33E9QU7VREXr3VzJ6fkmvjtvvcmlk4vGwSG6WKPyJvYbbcl65IZa7dPuVXFbi0FNca9PgxwGx)pVVAfxPIUcqkFF3NX9OQ)8GhUVEv1vyecDkclmnWWxJhuZO7cU7U6233mFv37RBV)u4)CXca3JcSBoT2GbbRy1VP5QRAMF)YnFDA)sbMVkpwTm6zi4cSbGHI6n94FYqB6x0xf1lvTqbCk)hDaqGpNNns7gjEYVoV6o867wCkCWyxUZwXrWd)(QEb4M2JGVfHGSNhhRQx7a)vrBNAhOCcFmWgLBg2xVcO)(7ywz82VSzv1XTx1XEgxGeZOJ67GiyY)QRT2CuaqJQpxVa3S(QrBX4jfhcHoi1Xtw1TPAtTI0C6ifHB21RNAxlZm0C)dyvORncoqbBLxaqjwUexzQARChSYoBv9CG2RR10ituRpdi0PsXX1roaQClSOQXRDLoN0yOXtGVTFLaaxDhsSkyO)upZJjv9PRIspKCvLIVOwKKPPTMV(jlyIqDP7kFPQMLrK08un9X(mGShgCjLy1cvcVywK89iS5wuiXJSCmbRZJQUEn3iSVS6Ae4CABn8D)u1QwaeXOkQF58Q2fad6)vnxFqA2uF7Y6pxV8hHti7vcY92NQRfxIoncVgz7oTRvgrz0pOsAiEEnt4RbCNR7w91lqKOhOZHxdh13FlsZUMUkq6CHY1ia2F4IpdBqGq7facWD0U0878QdfBKo5Wv32TQ)Rhmz2n1VG(PVo2RcOi)uD1DWA4f)pVy2QM2pvVz9ZAGINCmC09IlQ38I3vx98wm5tWx9fVT9gKHlcBFMNjQYvfcFwE)TTRnPCl8vRpZvWrzKUI6gwMO67sGeHkuQmlwagQJoD2StF)jVD6mRGL8jZo9m8R4Zrf(eGDQHYQu9sJr1dnjcyvt7Zfi2QQ2OBqCqSMVcsAIbXSl1)251Osrh3Yyvm3h4RrHpFO7IBAUAJzyoRPTTEH(r5R2eh9M1K4b1sSPMVgmfVlwObLCEVaHMSsjPkm3z2lPw3scQU(W730Dbt9eQl32NxxDnSo5LyuK(KHdlbZeZInyXvVRB5cTWdoVDyvNUEv1IAtn(EMjvFowFMIxC71Q6IcsEctZL0DhVS6U16iEf)b4LuNE0(sZBGQlnnT8pnR5oZV0(P(J1unrm(o0IfyD8PP6dOlOcI)kDxm3oTkiboTt1F)hGt4J(kDHDitDTaWvRQBN)vsJHhEudD)7nRVVAj)LF4dOnGbO3grVmNJ2agLsgY2cFnAkvugyPa(zcywtb9zmGwdFFEcATtusAoQtEuwbAid83SjdOvtfOzJ04rFgqxef(j6Wd6VJvFgXdmnGzbXORMH3JC1b9zMA9blayydvponSWNO5aWYLm3dEQiYgMW4aA2ksJI99Py0PpZyZ20FgxMLLWFsRs8tYDMPXXz0Nr5X8NOHt4XbAXl(C558NfQ)gn9I(unof0YoOKo24pF8HhrNbvKsNePPfjeKOmOGS5gwLjKjLjf4jbyxub93X5XB5t85IO5ahb1N44cpqg52He0qm67dydxJipKucwSJ2wMH(V4P(V0OLk(mlaJ4K(FI7yExNMLriwXrf58jdywp(zwcHNKeLXNuzOnMecgDYcFFcTBZZdl5p5DjIYQ(mM(E2hX4FhO(mJp5ziwgLmppqERG9Azri5fM48m0S(OWWm2bKWXg6A)sY)Z5jbfXQpjF2eNNNX7R)2qbl)3g49V5kJ()4yh88yk(9IlIM56EZnrXe2LRYaMYp2xXrwmaQ8alwHftJ)nlct)3(uRtRN4aD16PgQx9WWNzgkn(fVRRBb9NNTQ7k4Prt4X)uj1)fOazygEFZ651GOZ2Aq3IEQvy144XbfFe0KxQ9FRk(i1Fz(Y7bRRaZJRBFhQO36PR6UvRZrHs5V7V9YEXZzPSZZAAAjrQisBWB501Q(DQF1MmbTz5RxuV8QPnRWOzV9tRp8YoDPpWuQ8adEFZzxyslMnQ0A)n1vlmlg0j2a)U8G0Ic2Azv5eHMq1s16IR(FVQfDSgpVDobse9TltL(JQlpudxbuVzqlrpcmlEPn))cDs1LXJjuydxX1mqWikDqlMpPJJqyv4OXrQfPOUkYT)sBIkxQkvjTeIqqb85BxCDnBOOOB5S2StujDadeaD1urH25NEYBvzcKBboqxEbpRE15WYlDylDv1Z74JX3x9fkbNOMPl8YeoMZaMqtbguM3VYwsuVRcvpEwx3Ynn3nRFBN59vx3m)bB4pAb152IYsS6o(kCR0iUGPsr1suwALzZA2z1BrxCdV(nWWt5SqIjWPXduyBHLutSRqXasB5hvSDz0la4ck1VrP7BPlrN7z7kQn8Dt98pjsU0mjb84oSTs2DE0ogMjOW1tVqXUsVaeEFmL3Ctx2ChhZ1miJCeky3cXp6Hz0)B6ugcCB1xu5f519ANq5cIiNCFK9c(jMFuhf2Zef8B7l9ZsgCI4JKqNTnRzvqkkWRkDsDpNCdT1y98(K5lBw7M8Xy)ttwzP0OEgVuAXzsDWz(A78lu4HKL(wmqoNZuuXFDPU)SSQ5ZGOqQ1liRdLQYFkF)bnAdgxpZej52hqFEUEMMMVgmc7Z1CurQRFN80TQQ9AdH5JJvhugcHmIGacp0VeksQ9PWOHacGrYj1Txtzul3fBRKqEd7nfzvVUVLPIoPsdTeYd1)ay09)QRDt1YPsVN70rgRrp6zRjW8(IRQSTy5QJonvLBn3AMPhHoCEbffMMvKfLNikfyGYsPbG(wX4VMRINwAU1nkBAYXvTL7VUlaHKspYeAwczF1kHHeBMuydJD5Qbzt8WQJ2vnKVxkCpU3VMI9YL9QmSiT45Gysq2ok3F23q7fRqGWnS1AMHIvnSkhwhGzCmlhdv(w6Pa0Lq(B9eGTaNvGkEiKWoxHiIlzjfEGr)XOjxERXFoRzpGE25h)2lM9R)WPN8XhEWCLGIcsB0KMfTQc9)Aps0b80Nujcdtt(fh1)It6CBVG2jANdiisrbQ5dCdTvb6HqD4NNyN1Dx9byhGPuFHwD)wRQYxOxPMEpnVs1mEurGT8ePNV7Lp)p3(svPUeBQmd7(D9ZZUcByGlZbp6YLwBVFrFZpVEbDLq3AMqZxV7RkgfQ7rZem26b6P1yWULuaMzLaw2dwjLKNt3zFqaz(mgjvpYI4vOuV54lE9XNDYXF4TBbXsNb2EoagdXA8Is7qel7IhdaUukGlktihgGxFECCeET4QDeVvECueWrMyxeqxuzjQtF0kjm7BgTYpSBe8TNeQLFsNrkIUptCpVCw8skRcBHZo8KdFZXFyxST0DQ3)JIVL5Mn(l2wpd2wMmoYs6de(K3TsZkdr3mfeeqHvuuscgBNp(4wqGI(VqbF))T317pnooq0)IUvnXoo)y)uULwwel0Q2a7YNqL7kCOdkicO9KoX)73m2JTh7K02vN0E3hcFBZsdj2tFZy73BEJj(Is8H1vRjFgehHSkvkWD80LV7OLxCYrxVeY5nFzDZjZpFxisJasJascrUA34oJWoJWoOWdqwTQzcAwwEUMg1suDtsrzMycbavwn9Y5NoD51laiOPlVCVqqIrmOrmiHskWd8vKlsX2lZUkcsoIgnIgjukafccyu5c8uAfzzLOs8GCz6ncqaRH2vuur1QpxFw95hyvrLJisJisLqIUDcdnzegAegsLO1XB6KCjsrfj8tzNkHQV44ZMEEZERekBe3ze3rcpA4(Alutkq6kjuLALIUlOOXZdzekccCey)ffdG00NtIkrgwXgS4mKrKVtkJ4S5NF61NDYQMVoT(YPl31HHi)zDyijLkJiCvfKCQvoBv(N3rFOPd2)5h9rIO)WOM))D2hSdR3XsV8QNnwUrOW82f1ckjdTz7Fsh0ChkkCauc4xssJzfGQ61w9HAdF8V)hB2IeXbcoy0r6WrCETTpAfqo5ACNU1yThexpcCw)mpVI4eBIAQ4OMimSiQH0xgrKoQpCtUzweV8iIR5AS9E6tf1QNZ6R3nMrKuyDNpXq5hAjUDPFs9gh7XEoyrYfZ(4h1znz0CyXt33sAVX06x9ePu5Bw6zfkQvsRPnHJcygYkPBKOr03injISnbpc09XXnoD3n7TTO87yXtYCLnE6dc9paQAUrvq9it0UAm10oc7H0preTi1nIsSLlxtmqVVEpG)6c)srVwgYyezfeLg2vzAm82)knrSBf5kP(XYX4sdha9JTbr3SOEtSPOsBBh6oY7RpTCdINEsaZRk4Z7hDF7M1TB8CPnjgb7dWq9hFN5mIEMyfsuvNrMQr038WTFzDlz20Wa0GCpbhtVnkHKM9L018s7RGr6WEWagiuZXGyhDiDe9DwWCo(M04ScuZSruYwI2HEertkS32EVV1VsfsvOPZdZgwSSkQRBj4FRIy(iN4XnKQMum(B6sBQHrd5D2vUge)MB7dWSJrAKOSVHh3FHXAt2qZ5olpi3TVdmKbEeYPYz2mDeNX8sXRudBruRxw1uFoMi5ZtR)Y0LW3ooQ(S6JnIcpP6zdRKjayya9bRNLrXdboDfNfYrm4dtLz8yfuY3Fc(Wqgv8zHClH1pVL2L81d)1vPNSPd1J)Zd7X)Ptcz5wuCN0)DKdzewhKErmmQitInmtLSirvk(3dPcd7WOZDeBBNzRScMhXyZ6zNAU0npsK8mMhSbGA791cgH0VwlE5E4BFVcrjALspJ7veEIi3VR7oKxAKXPTmJR8beb8tV9sR3Ocv(oCHIglPhuKjE9KK7ioHwtt4Ke(a53Bgn0HEtCuyvxPoyKIGNpNQswBVNO(j(FkTwdrxPvm8ZHH71mNJoTWfLsGq(LHjze(KjtvBoY(WMWPAV(eMq6tGSwcJHve5rnX6k4qAG6mfCa3nuE87O9LyDIP(apS(67RTmUBhtY4AS73gvXQByKQaTiN7Pab2mQhSEE4ga4Zv1nUMpu54HmEPf(9mY7zhzentTz4BBy(IDplVYKkeQwwNpv)g5G9IWVky3Lb9Yu2GvG974ZnCyCGpuVhDFbUI2)J2osnXkSe4ByOpF6f5npfhBAzyFqN)d36g6E97656w)55WP2CCj(o7vNrVzCMXyMjtC)240xu2C3eb)TAON(B(XERiCpNKs66B4DlKXfPZQ757qaEZqmU3TFbdzM5ccTlki9W9v(YGrj7TPyGY5(wqJU)VGiRTRFWv1g7X3JzMfuxpRQyRiD2x3wAYhkZslDsrR8JV3z1loaHN7ZX3KmHdKYmL3Ux(UUx2V60GsTnrJRE7XhFA7InWAsmT2GuR6RStREHvC1a9tNEaeDlQnwhroFo6wosBQh9ehpTZH2oJVzGIP)lALtSkwcmyBoaHV0(mUQmiOg04HDVa4VQ16211PPQUgcTqxaW4IcW93S0RBICFXYQ2(LRiR2tYqhv8RGPgAzQQyLXEHAiSt9sXnlk2kTKatpGY0l8kMKwKhoNTITLFU1PehdhSK19)vn7smdCFmD1A0cUsRUyr4IW97now2LtrgT8A))6lRF2Veh6EWuAxN8x8LIzasNXl17Bb7NHbVLKkQYb2UWVZDEJgVakqE19y3G3i7IFpglOtWVzt6(v0oO0RZeMD1)JTfDpGaP9(npydyBzAGzhSnp6tF1E2y1e7oLAjiUzdRBjDAk)Hazd2OtMVSNAFMoaVfR1bQ8orp8FZxRD7Fdx8Fo",
            },
            p1440 = {
                s64 = "!EUI_S33w3TnoY6(xjVSpN95H4fVFZp5BkTxDCShB2DNmV4fTeTehlrQHKkjE8k)3pfqbacqcqlz7KU7jUxR9EIPiXLcv9vxqbup8RnEjT3Voh(FUDZYLK)CvEBg88WKMP155L)sPTNN1()Atus(MIRMMTmV0AVaV97EL)O0XpWA)VrEYNZRBkQklD3N0wZYOTLTtYMYLvtV79z3xTPL8eRKVumRDXzzTtxq(B7KtU8WRpkRP9WS6gB3KJo(SRNwvTCw1xkBOnrBw988w8)p5nW)f5tUjR(xBIPTWfvFjx73379Bcy)n8tHyFVmRP5Y8MQn1tZh0c0jxw50fv1nW4ni5ICYiLsOQU92M82pw(w7W49IJJJCdDCJ9J2)xf9c8wNLvuEizG6L0umJqXF)jts7((pvA7VNf9)CIJSCCjeuGUqggBAlww0EVsVfATNNDqGTFKLNLBGCNfKSEz295D9vqYHNNME(zY92BT3ZXlo2nkoWlYZnI0DUjRZBv6fpAVeAh67e7ehk3looijAttB1QRdV2oYXk296yVX7wR9ICDDcDGjPDyOfTFn2u9OVwo7fdZzl)axBF7DFkt7BP)J03EjWQItVo6jV055e5HZPy6u6MnWBO04wYTToEpr34MKE(fY9IJRY4Ns5CLPCraLZdOmxh7gQ0P2SbORLpSugnkLBq366Uh0Bobo2GCoq2)2qXjZZWo5SX5fTe)xGJpTlasZxBRZoyAlaOC4M22Qs1vjhN98jslwUE(w(oY9kLrEB4dJC8cTcTCTDO9PkkZiRBdGF2v2U4KRAb8K8(GiCmKWqqEliECgr)Klp9D)IkN4ErbobE(2XUbUXX5VvNeM31HGewW1b2H9XuOJupqkZpYz3yt0jytfU8vNG7(uAOWLQ(Ixk5lBXq21CtoCipuoD)VHJXf5fZx0Ik5qPM1lYkHvGdR2uoR5HVrzea9QhmDAEjHFlkzttoD4oH0N46frbzYnecSVfOAWn2X2piIa5BNudp2l0R7hcPpEomOPdIafvVNHk3HH2D53Nwnb0ULtiFA1bcylNSCzEZQ868F7u(Jj6N7RyQXjq(vpIP18SSYS5ewgJ47p2h2ZUGXgrD6LSLFPFRSODsD2Q8go3yVxGHVqBdCTFKxGR3FKxrhU1yVEpdnEmkISzoJroq1AJovqb6rOxdmAY8RkKkgBQ2ZgoZTMe44iTNrmThJgs1oms3BwP6JV6iu6p(RsKn9tUTQSfnNC(YQBYwsSl(KVUUoVP5lz3tz)bH2LfL5NvrvU0SidAKVr(ISzZaglISBKC)mPUiNaTqwsUv8VT9s(CrZVaOvNbipT5ZMqB8MfvF58BVL0bue3BMFWsccfbJ2pbKTZpKc(bdl4ZlUbf2H(Ejm8AOpVeizhvTSQ(De8jIkdxOzUe(dl)9P4pWxEE5Y7pTSHUMsa2K)oOh2dmRyFkzpBtBfblCDlopoT8ZfT0pbgCv1ay1L4aYpzkbRI2cFGSQLsi(ftRkVQ9(Les1kGIvxsMhnuNwiZPoYWhQoPmF19tiFfzEIZBR9C9Xwx8APuE1jOtmn5iqDA2nPCk07WbKRa4MoMMG0HdP0bAB6KKr)w6ptgUDdMFPAttr58j0NDBgJfVSeeoNqhnK1PlZNdp(uyg2K2royRpE0xH2983qMgtwoIcC3V77oaPhw0V7q6JeZiKehMKxMDZY8zP4u5D8LuEt8ooRb(Nxv8FiezQshpzoY)r17Fa1Lv3uru2a9sDwXYjMwBKyr9sQawN)yb4hAXSz5LtmT4yGb1fub)v4VTo6yN4JPV3ual7OI6PlZrptly8LeEu5HKfseQHfMuABuwvVkBj9BAwNvF3jcYt)fFkLmJYrfzTF3OWDYbHtMirAP64RZMvSPP0fDYodqhNUaA2VzGdrRaLBY8PZ2P5JpmMY(89A5C1o4Nq)pv(IUbVZWb)qIsysB(xB3aWBa2dzGCnNMY7r(OSJ(OtKT)SKAf1nlRQMTeGSFOp7GFYho53p5s5Ho(fWWf42ZBqc3ucB35CJz7ZAtcuYIcepzrgnIjLvL5uyu8TOZsUPACBZO)ViGkZOmkh8Sn1zeP8ZLSWuDi8rUGn24)wNvHruyU)zv1kWTU9nozXxJkv6XAEEVIIQo9eYJXUh)r791mo)Ky8Vz9CyLp)OSLtpFnvfgqgMclSTtkw2snPmk5OfzRwdF8eI1i)sEDfL753ZHFpRefApy2NbirGJOM(sNDF7IjOFy3wu30E5MYJbICkvz50fz0yVyh3HU8M3(MdQZZEJVdoeKgxuGM)9M8n5pGFoHZK(WMLvWqM4uusBdBkrWfwwCdmBrUoFC2aAR3KT8GzuB1)gTVFFXY7xNTC59qF)p3S8)7)QO8huFhKCABZYcApNUOggd)G64q6KEvv5DpsppA3jnW26EoI2ZGa3QF0uBW6q6knygstBZJ17VStCA)pM1J0422Soh68shFR9FaTsiFz(uODplB9AaCLc6eLSc)RMhEGzesNBj03iMy75x6aVQzGve)nfWwel7yU0ciXtQRwb25oH)XutUOFMh1SlqVWbhLE6VFcrEF6Svxb0e6pldS7rnpPX1k5qWC53qmI7n)V5ZtEZXfFgSh9nxSPEDvt()psNWnjQMAGX3itA7F(M0bE)eoN9FrNZDZ16Y)6YChe)tOeDO1pFR02Ebr)eYF7h8Z3Kg8((NWf6F64UrhFjp8Z5xbgO9R53ddtl0sVzRG37IQMcYNqCLH4YflUV0j49I9qooYl0Z2bde36QIsYoWC0jFiL4ANDYxld2Z2Y132pWXp)T04YeLuNV8cLxf9yHfhZysCmDTDU2lkK3Boor7jVXuM6T3gosx4NW3LtABg5SNVXgYY8ankr7Utr7Exh6EqcJ(4OiNi6Yz78wGmyHtGqplhxpV95uXiCpJS9bEWWyPHJy)L0mkyT69LUH(0nxh33BCN4fdpFYWZX(A7WiXIwS72rgDSS2IvQEBJRcfWnoi22o4XPaE4JHPFGxG)lafimPlneEslkoryklefAzBh68IUOOMZaKUZ6jWd6yXBpBRRTJDCcdV21xiTeeocNnWZzQH)gdS5qmagEjK9s5bm09lWi7rcWLuaf1el0EHDf8)RnB6Dh1fYg6(bIX0pfqvAlwZcY)M10Du4DhDCQu05JWOZZIDLC4)ctk3S6YQV0uYIce(oPlkMExj0qIqHfr2fXBkkN9o8n1gAsXlDj(so8)(GLfZlH2Az(TTcm34KJusAhmLBKJkNiw0r9IFLuCX4tppEFXBG36GXQNqKoTnFfL8Lomk2uYDwDkj1OKaPneoYam67S3kn)RTPsZ7dGHtSPDviKel5PevI4MmdD6HZfb1xn6VPIx4DckXHI5QlFzIfIvqPB1YIzdPcFSedwBVWdAZFlKeW2udO7(DT78J6sJiAL4df644RUKHkHoeSF)TUiI9jPvIiQkOChYxjK3YIysoM1wmnB55KTiQLgFYUTZ6xXpDIGwDjp4Q0)6eHs(EBOuGyvEsfxIkIsKHbJkpaBFMKIc83EPLLDE5LLDEjLL5809eUrILqrrpHvTIZQlddLHLLW1k89IiJlnKvLb1kAlZnRF7O6Zl2JLEeblvPdvrC7K2Q1xsgoWmQ0BFtY2cljsPVUeVOoHCnWmALULqmCX9oGdDzpQSVgjCO9Nxx9LJlQZNYExEg1PiRBgtZGwKhrMxb(0isctvuyYVX5j(biX7QtIxraFOcLTr7Tbc1wjUtgpIH5NW0IurIUN4VoPxzPBhC(DAj6FeX5k6UvpXa2GYYLmqqNGlZ3JNhoGoCLTagyaxSKbH6qfCCtahqZAj7PwUmrOjvdKHzbk9c9BP1aQsTkizVmwamamziUXZr)pt40N6AEJbf3U7)OqbJOk0iWaQEtWYzavWtAv(8sQIAhNKBRai5lZxbtl6U5YsKKTazGXHQ0am1i9niag5eQZ6LqxFaLSELC(kRAVqi2KKC76ks6iscvbFjaCesP)KOBpxxg6drWnWI2F3bV)amgb7d1htnlLE09gEEEhdGTjZnGHgl4mTuAuXkOdUzzX)5)KvpdtiMVuSwKoqH7332v5KFqcDsfU4z4GrFkVYGxpmupEJl5yAK39kbZ0KbjnuqhZISmS(rat(oc)TFfwNaMyb02od(4mq5ada8i6kzt6ta7zW85tCz)1zWezvX03TS6ltEU2QiLHYkgR0BzqOyDi8KZa4Pq1Vf52dWFPAt753Ezw588ZbyPLzuREFeBxItMWxM2fCQNKLlEBHyLSHehAuNBp7nS2VpKLrF)0cknePqNbkBjWL66LHKWs2zhtghAHnuxIwQAuQgXwfYYh5PM0aCQH6z7WQCWOJt1zsYMoU1hP9rUcvKvUADE(mQJg9CGxhY1ahQ1BYKwmznUqPZTezcXLcvGkOgdTV5qjnEktoXwd07h0UZPSTBWMD0uKF)3xaCkLrObUY)GGlQ05jylftugwQpo)28Ygy5QrhA2JAp126TLo7InBcQwvUYlqVJtB1cGPdx0tyoG2ndWiswFcRFsz(NjPJTQ0TPq6zeGhOifnVBrf9WhKkVIGzJ6Bo64gf5o797hrp20Xk56RNtAORNotjpeFPDJ0E7aJvTACi6Cp)cEIOYMzFEjrMnXlUfy06vBycdubOwNC2ZhN(X9e95e7AdwnP3MYHOVAHP1HP(2bybgaRnc82LbT2YaVkW5Jc22l4uMaS7J2OCkwhdWoIQpLSm0C6TNv0OpWzAna1u27RQZ3CSfgy25aZ4u1eRA5YZdH2rsVKBYfvTnV5)ZBUei0KK4(hquY2c4nJqxD(m3dnZia2G9irJ0SgcQcb)5bSPBVM0GQnsG10YlStqy68tqlBUHidiHU9iiRpjiUUiaoI4QEqoZyxpPW393f0oT5zWoSraArg8FPa60BCQQfh7SDPdJzKEqpfZd4aD(DgG)Mdng6pmDeUoR5MlG5Bw9zfZPz5ngwo2HjK85NLdJVz)UD6JWsnQq9w5AhmTP)edBKDQCad)UROepZxnP4DiGHJrk9ueovCiRJtaj72uGZtCy)urS5yVH0K3IUwtoPuO8bjJ5jORWsn1e6ZV80)55Fi9G3tZvl2psAymZqUTy5sYF5fi9FO9tuYcqksLhsC3FiH)PC690gkgbTbO97odghnVJVTs4qlF5souqaxwTSmFjP5AuoVsC8XaOTaYekh0nQjsPrmfe8w9tQJNd5JhCMDPUzg5eajWoPSPKesb)JtwTMCMFbzN58JqPyAjYSI5tNrpz5z13t3Ki)9XZ34koYPhDaqV6vkDS7N7xdoJL85N8UMlhau88Tx6W2BzcjeCPGpeMOd4wqq6obICk2hz7ZdkB)PY367TV8k8LSKcK)3IPi5e5bD97zpFIyDseFbwFEfz31GEQlIL0gepH8ayYZi1HuP(c5JXIfkop)OqPhNoi7m8nC72KwU5sym(4u(ZtLOU0t8jEywdzBQyB2YJzhNRbrnazkpultPhVnhM7ehOHXthZ4H9KxoGDcJjD6bSvvCQSIEouzWW9M3hYtkuwRCjfRGMCvRRlwb9dE0)icTtihSqsILToVE96TYAZOK8VsuFD6TFOIdcINpys7rrJu7FowLnItCefHNj7Mk)HcwDdNrvMQTanK(2fapZcqzljzsByxIeZkAOReINbWeIx8ImWuwWsw84FkDlK47no6tCYmcw9I8v5kJ(dzlwmudE2cr(5pIMfWTkqmgmMLnOknqbjzZVmbNyh11dFsQhCiI5f32EYsyicsFKfk8IqWl5dO5RB1w7oUUOr08iZWQ3ByxMPvDi4Kl9aXsZ0w8y(QE1Imea6T2(k3zmpb8iHXJd5QmNvfgdzcfYXNjpYNox2JclDiLLERdzsj9mfu6neYr6u4mcYuhl6LA2O4HANJOVpYAeQbpsEmDa3e(Qopc7ZPimwmyOjkG5MDr4xdKfG3LdwWmRd0QJQAn8q2haYjlON3zWu1BbBRf0(EaepmgyG8RJ5qKVrbxyiTiRzXVNTCd4LHvc6Kr(0tpU5b6DldnXVje0dLaZVKXqlJKWCUJWcH2JSUy9VOkPxVbCr5QIvRxMpPpkrA)S8enWNqN2ZoY32XnW1kW2YYXaQH)qudXvCJxYXGxmukdmQo38ATwCeDqaU2M7o69cZNEKuBcjQxoCRHuzVf0H3PJoOeccfyRbCsVJhReutR0cUoDMIU9qDDR4xLvW)UrVcrqTF265dt3svBUrJDvJibfzBq3vuY8nGhsfzLNwxvE7MAmG)rjvvt7KJbccJ4nH4qww9KHazXEwUH2orwEr2HykscCw)HKUtoEA)58LK9SOjFY2OEW1EV(QMEkQhSXalWN7eZJ)fqONgXGuD(JG(EXCAA8SvEIWa1ZY(k1L)g9jFfX6TQ2tNxc9Xf4LiuQr7t33ikMfHoFL0wVaMlO2W8PwQQQGaTIfC1wdvkGcOVRSlB4Shc5lB3Z3qBBYw2UyGbQIaV9O2N(xn7qLe)cKTS0(rnLuJaOQzIQ3pkCRcd0JVRZwJoxC923yCu1P0Buldv5DnUZ1QU1OAIHQKToJGEs2TPZgZHwQPAiNg5voET9qZ1g1qOrnCZ(zAPgtB5a7QhAS24B43tWiTWK55L51zlFyG760S4GVqqU4BQRMstv4XPusb3GCv38n6uTQnFfgGnTX5wcdqDrPpvukop2dJMZwMuwQoIlVxL4fkOAWc)hGTcTP1a4oEnc6qUQluEIgCnsWzAPxCw7fZwDPpOFcsrtjkQCb)UEL8wcoO58THjWF8ROSPvedlBrBwC9ILdNmnejSU6qMnxyQyryfdhj3Obr5B(x50qTQoWDbvXCn1KBS2q7alVy3ihLJ8MQIABBx39G3G9QMpGAosxrAxuNtU9CoBZY2cmkZKFlDtD5PGQCWg0RURyDQbNSd9zCf3wvtUgLUIEvoprc7mWYe2PBY1tZwt4IMDoqosLYC91mfSSflQFBHkzIJlB1s6QEtDvseKw8(s7xYZObQ2ONMIp8sbRIXdLr(u1KewGoipQqki7lUdSBGncgY(FC2QS55NrUrJiR4ojZwHxqre(Kzzlj3DrcHshMcS68Bj4wxscQ2qrCqeQCZQBYRrde4jkPGzpe9H6MQQ7wrckgXzm4LaBGkJz3Vn6LdStwmJk8d6o)iyY8(9EMyVQPXH8xka4wQVPK7jR63d2FYHDH)8CcGr79dKed95(E0zSAKv4E(EUoHUXo(Hud1jm8UbH7rSu2k2n0NVBxIOerrDK3sl8rk7Fd5bKL4tlpEt588k2vkfzhpa(qM15EsV2LzfZq2xYZiBCCglFFAaGWCYuH8dDdDhWmBBqe2j2l2XoMn0DS8c2ZZXjcp917JXFdMZKE5CYMkXXjMig4YemCFkvhsOcpQ2nrUHZYRXSA(J7UaW4p8b(naRtCK4k(Wl2tC24jxSIFtoy3ubvG2WCa3b1JSk7RKT7P0NRwe9xX1IVVU8XReLE4(2D85)XhORmsJzXurwtsOgv8o2IvQ(0qCZ2qt9JewtOll9gS9PVte4qjM6dZKucUIC58Y5R58x49jWxkkNXpSvsGfc1)YmOWWNSdKK2936DB65y3hoatnFYDUpG5QE7nkscjqSRop7oYMSQD8gseDbDQn5vGhlIJrJf5Xho38Drh7oOJtt7EnBDBbnzhereIh)vd4VQ8PBGTXA)czqYoxtPDdtfCdqiQhD6X7t)(FYeJmGkERkFvHI3KwAnV3HUOQQYGTADrrzz(SRYxERitJPUyziTEvY63HE8aCO1ebsD8p9e3jI4(w(rroU(aWKngdnkkGMhpF4JXeyDH0kcwvhS9LoXHJAXibUJZCEaBJ4jgQ4MaicIRIJpqvJrvCh1XTPaV51nRF81AxHe2J(UXe2loexaoxO9K6szFZPrbE8K57rnf4QVKTMCPewmLUqSMLVbc9d(C1zHUSR6nMXtwmpTNUP(Q8gAjXazkws1KQS7P047tskJ6JpJKslej0h63wJ15XU4DVUVDSVRn)wU7X7zBp)NsphBH3h7HboXUXp7rru0WbbMmfurM(Id927rQjmQgGB25S(Pch8PNkoCru5qV(akY8RutHKzR6SzjIExoZ35w2fiO27T6hePSb5Kxb6p6mejvj3Aoz28CCKTxxoSiF7XivesOrf0V39trxEmtVTo87VD)6DXGEXH7jAtBV9S3Iin(2GyRXBYawt6zVDBT1BJJC3QbCqYL5R7idHwp3yJkQiiBbvLCD9y3lScgspGtkP3VQ0KdItlI83UT5RFbKWy3OVOz8utQbkLGFl3as2B5c3iSc(jF8IxY1kqi(FqUCnj5c6gUD7EXbBvZAtSKFlw8uRvhixrVB5iEwRrAw3aZJxX9KFxdTDcyBnlGOKBOL7vECAh1xsCKwKFj44gSLacJXfaRA)EoOuDz(jFTOLpw92ssr0wcmiQKhpn2F8kzA9MMf5Z6ReIglb8kn7qAXKcrIPMgTa0pSKOJqkq8cl3cS8eMRfh62)6HgwpIzgtJD8HDwK6X2Se6ZzA3O6lDWD5uwVXaFqC6gwd(nl1e8LNANs92ZyMiL)Z(uorcP7FVjRoxCr1tUR(z(Xq2bQdwUeFk8mEQlsTuFIk5TpjagTYKGNgDNUNry2RsAx8eNFd)EBcwIJXlaySewGUjlo4CZjAZRbBGBUKASj1UtIM(ZYMwxXs8mB2fiU0klI8uUzfLKGgXa2AOMUQtRwDtwlHaPCyS1fAsDzCpoywrgi9SwYbFAVm8vSKOKlpZh7soh3F)UR5C(yU3OGSPIftVlDrD1M5lWX1nunvxKnBgpo0SC67YSY7iuLD5mMlQZimt1yg7TR3s76QhbDNNM0EBdvaB9)b8t74OPj5U1E2mEFc7GYL8WWqA6WihYd)qLo(rDasjR75(XPC2l6Dzzm8cOx8mMpsaEDPXlKFv6IYwRRWEPCo2VqsGzI5G2IeJRuV09DXHApwzFEQXXCSTX8zdEWDOH1JLAu14(Zt4gpN8oAtVv7izP7tKp6dyKyjcWSIceUqiej3MODWgZ9M2bYpFBcuJ0qC7LhgSXwGF)f)hOhzffdDfVaHyGssuiw62MPCxA6R)IaLL51uuCEGcuJmPtYM1sCssG2gp4Ogp8tW6BVbKqOfxFXtgAQEt(nbmRNqneOulSSz0gdaWg0LOodMOy()ZrHxpnz6u38uwLhsDgOXy07Hev1T9bD983ZZ1XkokmGS5f7kF7JH)oUSKzTmMxRdsipRgJ7M8etlQQwGYD4geCCPhfDHpr0gd6WLKG1UenuLTbUDdYgBZTBJEZO2rn06n655OxwVDLg11kXU0n1mHUPxDRE4OD3sRHN1vsa3y4W6mWvVYytQEnycHgnYt(tsJSE8)bglQthRoZRgXAmDgVPlPt2jd91xMQmQavVoWHkqLIvK5J2jpw1EwBrEkTJ6p1VSyMBTlW6H7f29FrJnT3n4jvLEPM1A7)tPwBNO)mvu)X)cQO(TbJFZZ8JrvnFD5hH25Dx9Z3hn3oA0CJzDZZu19oQBXKk9bAxgAsGJzRDgEN5q3F1VVAS1xWmFrux)i6fuG)1zkupvZVnC70n)PV76Mne3HNP65j09D7WS5pIJTdjSPJHnoIHGEjx3K9zA42vwmub2I7AzDlGw7)m14AIs0TrSM1ZRvXRbPZx1((d0nzRFSUj)FZkF)VbxJn5v7aBP1RjqZo(889iwC)M8J1F4xSiuBW2IFM87DhnBZGFDE)SRJj81qX(xrDmHVQJ5V76y(tlQRFh1Ye8QwMDulJprlJT1Rz5YRz5YRz5YRz5YRz5YRz5YOz5sxU9)AoI8QJjVMJiVMJiVMJiVMJi)WYrKEhnNx39L)sRa6NXnzrVC7F3vTm0LGDm(x6l3O7Uwb9HhZuYjOnqfA1YPXA2)oMddd0pym5V)UO2yGfiFVtFHND8VIsoRaM0VMxdkh8Zx9T7vF7E13Ux9T7vF7E13UFy(21D(9Fnr2Fnr2Fnr2Fnr2FQjYU92Ni7)y0983Omz37)(ZKDLlLNx118QUM4x118NJUgxD6A8FvxZpj6AI(VFDnDxUGVQO5vfnrVQO5vNA((F6C)rC8H(BKAM4)7xnZW7f1FU3kltxmUBpvzYtKQyyUStPfW2DiK7UgKF96szBVUuqng878t2fHpcfiD9JECwBg5EEDIOmxt)fcC5HS9hH3eQMA5gg0dRZcMQb7J3p48VzWTlBC3TCA)lawFXxPQ5TB8WP9K(is5oiFtDgPmXFz(kaLflznXj1zfZOfp(he1k6ZBxa)6zfnI6cwJGWimjJEbKFd86BAPvS5M7UhRjG1vL)hsjaIWo0(f6)42QAYlbeFsHkYpzbP01K(nHs0puvYviXl(getV2SI0tn41X)668BbfGWlaKQ7yLb8RHfPzuQcPeIECrZ6Lz3Fw1SCyGSIEV9J1aMY7U)WLztV7FwvYkULYZj6YhV1RQMP24YZyNKVGLzBYDk)AO5P)rDrB(1zZ(x05)S8SzlVpLz5dOpBoQ082LzRYbuN5BWAI306I1RxI)CeT0dC7MA87ABARlUlNsXYzjq)xYZwxvEDE5uyXTfBY8S6wGl5ZyJ4KSKv0gZ2mNu7rVMqtOMGvqjUTyL3iBf0T3Ep(rX4GVbi94VsivxFdHwH1WncXMUM9fsT8MTAwnJS454XRJ(tlYw2iViMYk)ImI6Fqh8NGJDzQl9ahLb8LnpyMnJuqpww0aygWy(A670Gfj8QLiRx1kCWpl)2RXraEyeUjVPT6lx)L87RHrwfTYub0sszPiV(UUxL0u3I0osrudA)gcFc2OGvqGQyGfEfLEnl)ZvxtgY0)Q5EyjUQfye0ZnNIw20sMxTDcEuFBMHSR0Il39mBnCSWlQ6okrCY8DbwHAmhRBorQQ5oNFLgRRcl5HvWgYG)3iFjVoXtkprS7hbGbUgyGVc0H2MbS5NDYXN(BNrg6FvPoowjvPJymiknjRccjA12HNKMPBQBQQpOTnB6Ij8kfeXsiYQXjFf4QAAam8HfcidwwkxQHWQuRurmTxfL8T(mSz1vSUFwFfz1jSFXvWWTIU89DV5RCEKPrc6(OfzT0BG6P4)iM(pyvPj86SgdsWvW)hTgx05ebQbPHj6cDtuY1xdSd3qDs2nPy2Y8jzZYpohygPLak5s6fZdvsLk6mqZoVqdHLjWFVQaRYvojnyhZJzHs18I6NeOcaajOGkeEV3XRzJSpu46Xd9)ePYsiT)kDfRHhvT(E(DLkfkkVLurnAavLFt0mtiw4mRzI8hHkn5ZCGPoVColim4W7svuim(dTvaU1fQfdL36g6qx6dcCJ9S8g5cX3JU4hcVKDON5A8NMAYNtqYAyjeWajmcSYy1zzFLwOElTTyPJdzGlxVs6kyvkfamqJnO3jNQMSpVaw)ZyLye0bvPfibGbx4n7Mopuy1pLRZNv0sA7pqGfj6KxbgsGKWintde2LiorEiPPyvEy4V6tRdSWC(Xoo02YFeAn8RWQINFGh8MXoMP1rS6fhn8nNxsRtvtykcxdEMxMwTgDjJwXwOgz((Q5Pz3KoGRtWBFiVo7s)vWjZLlrlhjkxafdRwZQ(Vbj)pNM8)C2BqlVq6S2dQ1if3scLKzgDC0EHb(U(wUE2rdKU6mUvUy14OPy18BLfTtiO9nOZe8QXl)ra3iavqlqO(y1YKzId5F2YJogONTQbvuVoVnvkuu4)FSkrI)ZVjAjSkIEt7nuKePsalVekFyx5hmMv7Uj)Wb3a6mU5W(vklBBq(03lgyzcS6QuwHrEU8FXPliOQVmwbJevOQpYQue3aglJ1Lhw4jGb7ruxAocOQ5LTkPyeFyjKQe)OdBcXw9C9WjdFQ3VgG1EJuGIbFhQ(sETCm9i1esWR2vKHAxb(ZML2e0xNvr9)O5iAyZCoJg(dEwppfq94QVLe1XFGWCr(I6nRbTLzZUxL(70v1f6OZU8IMiPbUIuz(WqQ(4XisE89r(8wz5NN)MeqpRbJWZkMrQ6ssUof1vvXee8uQNtg(2EwI5hkMHUs1CTihMXy9MIFIhC(UAzMGNbKUqZtBV59WVoGBYLYPrgLeX5pXkKDC(LpjUWiKwUezR)QSVECoHZT7(UIwA3P1OBSo4r82h0)IhT81GUxWZW2(1cVuflPilHI1dvxyhmZfN5EuK4OL5zLOrgUOCfPiushGE05fFeicnNqm7ccVmVJ6iaIkZmLxx58VkZ9)jo3p1waymMYrJ66tXyvt0sj(1i1CDdMUYG7riNdI5NPHZKgd1BVTFShXp7i1sUpzdx4qc94iOSkcok6OkTR0Y7tu2UEnzEXx5eVlPRUeJ5lPQfIlyYtl6AmloPZOmoVRU6lTlAW6IhQHghVSnrWIu5rD51WyPHKeGncCyPWh)(QPzQbPgCIaO5xqvXWyAtvGgvyaiU5HcmkpUVr)axaopoxTaSl4Q(ehEhBSpoGTtTO5qCeK4Gs(SlymnOD2DtvRoTd85kV(WP2Zc8ysOyolR(oEbdMTDOYTGSUfHa2hioMj0uYwizTAho2uIBP0fRuP55NKFnrRTDhVEKtNJ1Kk66pXYAips4W7Xn72PqvAXjwQqqQaJyEZ0SyRNsQInh2tbxmR0Rgc2YVgz3OcrFKh35ULGoDeoogwRtLLTWMamKQ)7I7tsKaCblc0I(5t90gRC0XY0zvJPfePAPjItqrawSwykkwVHtX4LPu4nFNy35AVryPsaZIcP6VFVkl7EwbDQ)4)75S)93uuKq92WjXzMqrgL3xQaalau(vsiBH)pPTJGkT0VZ7STOZ0chMzcmUBL6lSIDcdThluwxwFDVoc2DICu6a8sYh192YRVITJV7rhSSyU8PstYitbcT66ZLIT3ssGtKb4CNLj0zHV5uDPt62NskCko9jL8)26I15ZgGl(j(5aaTnvw6nDGjicPg8L7PqjuzWUnjbVce0N6URsKmRv72U54YzDicq)XICaOlJwz(tnSZ9yKaUcgtPd7zH2F6cmzNg4lYYABuvheAaI4rleZK42qPESGxlj0AZeAViRU9ECC2vB52gYPGDwP2O2SQQI6gflBfq2yU4ayTr(sAv8Ln)7TQQBBED7mxKvrLr5aNHYiQQUTWGkIwqyhOL1)q((X0ZEsjxd7w(LC6XjWWss3o47GOkkfNDReDg7i81Hqg6vz5CJ7YNMa3(EaiBPxNrhDAIOCZegCuBKMrTIFjBrcu0L4hDgXplNd38nzt36vvPT7QrE22Dfr(aFFMggseRZX5)zzZlM2JbeCbcT8J(zEyD9NmoWOfqx2Eq36fZAHDqBNkNtK939abyYVfYotrNEmJ(fgZP80pXRY3mBwOHHSltdMSn6N06gZ4AHgW6nwajg1XMEbRWly)DX5ME2foIVkoOWHmXPlKdemnIWWfm3kuPb69NPh8TjVCIuxVu4R6RHKPxsf2MeTR2fJgpI(dFXAIO6)Z)LjAaQ1yVRjT0XQtgfPmnwdS1W1ACmBIHOl1ZDEd2iiei0VE3pwBsg2KkiCxipvNmi2yb7lyQ0i1zYRqPWL4yne87OnWCOtdqhSzGBqVtghdPtwhdp8PpGbqrSWRc0VTbbnIhLoASPpTCwb4pDvNBfBn60OX6016LmwN06o)tmwN7XpWV4j)9pJqFQZxlU8)39OAQnILt21ynYZzVDjwJ2r9e4yUcnIuC0whIY4(mWs4CkYJUVyrVu1icNqP18TpULpDtd7hItNbYWdl7YA5FmAwr6ZkCO6SFy3Ji6Fjda6O2rmW2aYNNb8wQSM2b7SkDDbe9Pgr0jp)iIAq)PdDNiKWWzdINwau1fEHEbOiuMg2patrDr5H)VLRB3wInA5p34S2pEQ(sZjvNI39qT2Zro(cspJQJW9qhxhtROBwB62gewx07KE85DbGd8orYoLHvd(bzJKW73bb6uBGJhXcnFwOhhaVQ1P3iPXPGfMK5gRhD3QmgMzNEMkPgfD9rNsYoDFRhnU06cq6yb7W0(XykeTE9t4iuysZJNp8XF7rJFiWzq57euDjwpD(NSZX12CaQge4tf0ykjlYOVDoEX71zizK5O)dZ)EIfFKTZRQr(xmBr)MeJwwqEFgriu)v0Twx8C3JVbCKDIJfAuvJkedTy24LeX9H7qWGGpACVbmfXSEunMroB5(MP94wPDFd(oeS)(UEVJH6F7dr3Wa)lRlKNTvogd9VUnYDlI7PPyxiVvygJg)3R4)p(US1BN51DJK)9l4FJguQx6Tsyh3RlqaVNGMGzxAtohD7NEj2wbTXGB89LzG7o9DoFB2HbRb(mrMbKdzcvzyViSCYQ1T3poHv24s0ggtzEYW(wDSjfcm3XsLaTBdHPne)rJrN5n6wDFhKc63OB4q)8Rzl2G7V1LyFpSZbYsjiuE7AqO(RtCMSFMXzY7VoPy3top6M8NqE0fHBFA5Mv7C8Tgjow(9IJ1BD3YKTZtF0QONxj6HtABcwL7tnv70gzkdw)FZU4uWwNEEpZytfPl2utEPInLs26LQpQu98Wl9p1eYddPXyXJQN3HDk57NUEHw7)chrkt5Ox62hrktHEs)o8Pe7P36UtPV3JBK82frj)xSqk5(3Vu3JhkEnXNH7PZn984rRDnPBFI(5(yburVFlgk6sdCXvt0Q0StpSm1Ey8h2Ap)KSn0)7EOhmLnzAIRGohT2LeV7jLNH2DE(DnnqDAJL1lHARrSoES0pS3(opimeEMcdXygRNUBPCOH4q0TiRjqeA8KsXDX))S3ZAZTTrs(xX)bSoamdEr)jjzrhvRSKoj6e7TsvUOiHKWjkaTKuoXRk)F)6hZt8IWkXBIVZvLYmICWGz6UN(D3t)Ml2YTKIL95dI(9pxx5nXZ3nyJ3Zr9BP7FrUVOpNH56VLoDrqVoEqmshp00tw94YH(cTtdFS0BoV8NGhe61Usql2Y1lwvSl3j0D6UnGxO7ZNc7YH3deMKNtYl2xyp7jKiZA7Wa)6a69vVuh1Cp)YACcq7yE75yGmKnG2P17kBe9CGPUvO4NCFIaLLOC(ZCgCidGSTktcNSR5GvfCD)Z(Ul26VUyRt60PKOXncAfh4EZao5DGJXFK3pSSoDLUsavQ(dvwdOQ40We3c2oT3conO)km1RSivtBAqYEnLyHvTAOqSNxvK3XC2Ej8fVukIku2Oi5EXzcrCwAIKCErpfkRmMlC9uzqKqk7DB46qh3xGmlopIoa39lqp)srCqCws)Gj)Adv9AcEoaCHAM8XKpNPIRGvdotHMItY3lCxLWFNyPqxFrAHKpNLMt1YYfgTAX1Urem2fhvLUpBGLkvNbWLoQfXcwROc0XxSxzFI8CWsS3VGUczwVX)mZLDaiTPyUt62fKB9GFsQ1BTImDv)34axINwwgUYd4rLEuB95wfmTsSU(u8JTROh11)AY8BpVGchvtYdbEbbrs4)H1m063m7BOhnH6j)dAdxVWKc9nuCOlRjB90VrLBin8ns3wGPd(whjoxpvs2xLok9BnAFzFxt1GDs3JUv)yG0YRhTi6WZXDF8Pb210ocCL8NhUNHIqW8LB5mM2Hx3BEFJPnh0iAP9uO(TI2PVDS8zxwo2(QwcuNTyp6lEJQFZOAwJAZ8RQzTUT(KspK9vT(a7U0D6UqXzRu7Rh6cLXT)F401y6wE1pyZ8d2m)Gntxgy83cwlPU6uaAVSr1wzihALL0KcFpqh9x5PdytdBIcgQTK0ihh7XdXEhzJyxgTP8(hwvCqpPdxN(ow36qq1VaZBUZTZVIpChhwt6985OCcDhvzXxTJOJYu71x3xrr1WP09Kl)Tp0)veJvQX7ya46(B0oC97FAj5Fpodp0znTX3)vFL8l6lWPdLst7iOQCqY8avpxjwDEQFabM9XXXX9f2eUB4AlcwZUeFQoNON3HnsGAZUQRa)oIQmYfO10j(D0yH6uFIUIvWS(k0uxwXbGLH5XbjHPrzYHk1HEulXJhBA7A8A4s3RhHnn5W3ocSdv0KJT6ggO0c6shOgmMAVJKn5u39qgVUudgM6oD7EF1(xRyA3z6zoSRu7YX9Tuy6BAv)pED(6Rmp7uRVocoG5qE3oq)RQv50riy6Rby0xn))vP(ypPcE2K6AD30Ep5WXOzGSuao14jE2LHFV5nWUR4)wDIQEsLGH8zExzesh1h7ZU0S6OuzgmqD9e5HXw9dDh)LgX)JDcB92Zh0AZDzL)FpT5SDEq)3oBl)HDKFT2r2PYAJx5U30YFn9y6y3Sy70eGESEC0IPBzvPXP5J64yOmEVWSy1)L)x5XXUXC)HDbu8p86ZFFpT2nl4dQgU9Q(v47N(pCpIJXTTeO1b4(Cs0o99JWp4Zk4xR(ElQ3hOp22cUB0BJWgPXGtHOg3Qqh5ShQHhzs5P4KITBr)ptgv6eonyhU4W11pO7P2ryB2g7v1R(8pPXf6CmpLbV6F)CCv6D)0KZVl1outAHqvoXfE5NIiKVji36zwhaE9uF65ho05E19Y1T1B2wUYnOC203o3PuAu64x6L)6Jj111lvg4z7Ma097eyWLdCZzX3QYFKoL7JWPNgLPVYHA3R5WlHTQLf3xYxji0vCI0AlWy93tkToNvEVZ5wNRfgHJUHWV7L2fH6OTtxRuoxkjyAOmFXDkvXv)qG2kzIexDFIGT6FN6b3L2ym3et4bOlxv7DfifbC)WJhlk(VFSGvk9xk3E7zx9)uqwoYvbaDohEYz1p4rFANtVU9FVTvHmDu8XvRtVyuAW1OjFVU465pUIo3PCZQHlglYntx8CM4U)M5pOROocCJljNulnDcyZd245ROeiabNS1iSg69Ipzf7NzrBQk0xLtDUat(EgZdhpg7K58q3SCzp4Mq3EgE59PhrwB)o5BcMtk743JWrUtWxEG5IaiNFDvAEKFWhnAGLEFVWVCSDkB0OyFaDd8mSFbixR5lXfnmIRpWRUX7MiIUDoo)WzLB5Rqe8qQbQ2GDAn8wMxD3(3CZ6AVor5IfZA2zz1e9ucyznVxzfShN7dBCroLBEykT1DxdHAqGd(M9XU6KSh4YYBYtcKD)14cqu)A5ez1TNWOERV3hE4Um9avP(BFBXia8KADwIsdlDsXzVDg02)VHt6r(Krdzzo9PmIYC(63vzKRuELJWiPnLXK2ugtgZM2thiGvRx2)MBm2(K6f3v)4293aIy(TLO6tRRxnv1h8lU)ZhxX3ca2eutK21fQPqx98A(6wmPsAILHndvuzT3ToxgA7jyiS5uhdtE4NRc3lSHCBJUhX(yfU(N2Dd1BXctHoqRqGpYccozCObSokEeuyBLDV74ffNRIgTorUNHmptwOvSFyMfILMqReVmnJAlHzoytRUfz5o(pCC8dqklxs1gsIWetQOcluVYInND2HQ(Ex52RQ)DIX4h0AlLoz5dBoT2L3GQvvSOxbeYg9eMP2CoK1Xr3Q8W9tHvdM8el1CKWcKJ1YQVTHUIcLA7U4FqNyI49u2gGCxT98lbf6YkcH)g6skjU0kj)yPrfSXDDC6tGILN1mt8ZuQs5139d9el6vZoHD2R0u1DKdG0dJ4i)1tkpk204cUMvIfTuD8fhSEBoEVaV2oePTugYLwt5Ath13q048n3I3NlEL)XWz3kWugoD9tZ30Kq8pNoQJl7zGorPqdnZLxxYvegXGWXFceN5r3xlAgtCf407q6y002vH9g1vAuE7EtJ(GJcIRetZKgavw5FGkvnkPd9h13uYCe(f2xaFz2DRv9IuTOn7XFB2pBLK5utSWypw)cBzxvZszpXLICma21ZxxC0QYTfwrdbAMev3Dsnwvj(C3hsIaELh6GPSWLqFRBXJFZA5aEdfDpkMOlj8DFL76PEHBGsaLsVLUbjvSk)LBbBCr0ix8mTUEx3ZvuMthKisb(m8CN5L0zkuh5w)hxTc)bBqLhxQteOr(xEBzXQLh5EnvzInckkIJjiBKfZo3T5Fh4OecZ4GHnTpc3NLIQyS7AoEOsf5rfalqoAX81JNgYCTP7X(u6W4Xuh1rHnOn8uB1eViMdMXTJUIn9cLlkbWRLSK6kQ611pcyGPMQ3UHahP6TzphL8Qw5sHYZyUNrS0fe2STZL6Gk2y6wFx77HnU23Z90r9d(2GGQE24MqMGeOJiCCnkx5F2sEQXOS1QQvKU60ot0QDeZy0uL0qENdmh1F1bYIkw(WdovwIvVkRrcXkAmGUulxT3ECMYEI7lRkn1jaXYoZ2qyJDKqejfQdnoCHDUqLIM8VqhRyCOsd1mImADz5lQUr)IJNqTxHRNVO4x3F5YZQ28Ro(18xVVyz58FLg6VAVaf3B2SPgft3F1kNolONIPVVJwAN1pbXSpPaOSt7IRdl)47QUm1JaCzXC8vZkxZJ3OuOw7RSUoh)(gMFAvXRvzVhB40EwL(Ujep6BuF3rUUvSULEW0dZ9p8QQdF3JnnmDVJiOSRO30P9Yw3pM1ak4r50YXXQiof3QRsPplh2WVn61)l7bxy6hcer6BRVQHJwtTWVWy7ElJBE8oLsZyoIK6Z9WRjf2cg1DXj3u3N2LtRqld1lNi7Q1s5PWWUfoh2YAHX8mn1kStfOTEyqF5rOuIDm694bthJPBg5oEjMqoZaUh3ZOfm10XTIwgcA8hQotAztlwyCzW02EJ36(OwRotEj5(awUoGktEuUEMl1eF1O5L(bx2unnr0MXcwpf8ETIjzE8iAYE6pEZPYZbZUSGueHg0TTA7dv(e0MLkOU8nzhgM2(CKrbmR4l3SGX1y0UdBwtJLA4pMgUoEdDhVdAqFEX2nt3DtiLDwMVPEsvpsRS)oxKRJ42XHcMjTJK13s3X4eriDR8Uf9SmZ5iVD24KO8LGXgJP4986MtMFvXQzM(RnnBhSUy(Dygfo1OB1RlMd0o84Wls01hxb8UorfQtwNl69BUcyNzncHFtNVaPda6Vt2)GJoHDrNwBdmUisJa9QLZxb4vTALPX2()Tv)e82mvN(s4A74kYZ6oolTv84Y6sillIaWsMfZH1yINbCc7gbR))SwZh4asy3i5STDYUnyHD4zV70zF88JUadelRab(OGErLRB(cDcqzRdE1U6P5)y5D8y5CejCUqHtMS5bW26PK)(Ain16YtpPeX(GiW68xxSA7CKBQTJMC(6Ipvw8BUxC)QJZr2ZuQEzKyY2BbM33wVAPJ126g9(JBMb)kHOvD8UMVEkNaKto9StpIian)(gNPtY0hTHtclcn3IrfcLa75ygAckMQ60fxC8B(jLfUgcu(k4wNKlVVkpuUxCscE9ahKj4k8AHQfbH1SmwYUzc4)KXoxr07F91L)EH(2YcrkapPFRfsjUf)f1SKAO29o7j9o7bh8YN8UtF9rx8Xd2)c0EeqAaEQlrfPgTIiaLikbBjNfJaoNV1QvNiEB5QvLBkaDywUH7gqAL9KrnzCQymG8LwCNtKWsS43FRwJDZNmhbdE3kFx5ApYLiGH0HlEsys4eGmj)LHbVmuM(uLmi6vvzWkgK8b4s82Ck)vygpLZo1pojysO8PQeHe(6ijoWKqAic9qIZOHidGNpfy5ufgstvmnAzqSEC5W7gMQOqCQIYWPkbhUuQgsKGhIme)AGwGgco88a8Ffzz65kDsy(tv4fYnmxX4RllegsuGeF0yDqjG9hnJHIeyrNcBRQOCCezb0smx7qe(v7czgEnapcbBCFKurGcWufMk0GaNblDg8UGObWsqIquj(wdJX)vMiOTRckqyZONWQh)vvXrPVQkjpfhmnSaPbWNqiOy4GfGRHxBsCc9UXLBqMlOcggOce890YlIERjYu172U6cHvh(JP0MnidhHiNW3rshKjSrHJTVQkNanXi1wyAo(mrgqpT(YDHJPccqh4SnZgbTkopcKadgso(pP0(KwaanzUlQi1fvesG1ujHKL0woqny6LN4myS88bai8MZiCNGwqHIq3hi29bsXvcdRdXXgZRkjA9yf(h9IAIudjdgIaPrIX5kJ28HewjimHgcOJIzF0MKcwpm21zznmAMqlznorKHiYecjt0zzz0ZPXtechjhJIX9HurdcRiqmgSQJDOFIgEdPpItSlWnsiTDsOZc5ImIAlWL(XDHMqZxqkIJYdPd7eepp19jeUpXqKmkkW4DGk1qGeyCzWciN4ZeZ8MONrezj5tBSKhExQMACjaStRYiEtcMvxwab8SOT8Mt9W8BHJ8r4xNkPJLsjDqL2JjzUChd1tkGve4gppKOyioDPsI2te5cIDP3gK7JMClq9ajr7M7hrrJeYi4VI4(lciYsAXh7GTZBCENoYgr44SCIbFS0DN6o4rW(kZFNoOGqIl2Oo9L3a(fNQ4Zatykr2jKUKtECqhwUOMFGlFny9blM0C4FeH40NLsumPXoG7KDnonMpYDLJlMSeySPHePiH)zMBMLIliFey00gVcbmmzgHwfeGKEtHHHo8CardsbsOtSWGZKeQHKCj8y65oZdYLsVBDHJPKgdrO04C(KrmZXmXLcZtIYU4wqSF8Ojr2VPeCpGKvMqKfsP35v3TXo4jZNVh1X6mlJa6u6GAbOxkEYdhKdMsLZSH1MIzC5U)gKdMs5ZDC0NOQeEIiXnxcTosiriPzSsBUkGHQ(INJj8CoDSxMrkWeK6OysEl9AysNrqXWVgxomd9(0yjH3dmeDVc)dNpiogPP0Pu6KNukTQsQzl5DYlI4ZHYAbejPGCsSJe8OXC4KLc1lho153SDPcIghg7XjKr446lhj0IO5aoPL7UL8aw0mhqpIKpSi8mtWDWdcXQW3YatOIgiBxQSOGLX7A7qGWDaWrvdF1oSzqZxZLNtkXvimJ4eMPa6O23boyrXWqp2Ampo9dzwMAsJgGktF6WJx3aBTkab(QrOIAcXTyN7zYsIbmGqXIyNSSvVYODiSunDj7Wkef5IyhCWSHxH9DPUWJjxRqEdrLPRuUXP9Q0O84L27CkFv0L)z72zGBxnQoHm7yk4ny9DzU1tmu6rhXbi9DpSO(EmR7rVGWbgBJn8PgNKSzg7DqxNexwvE)8hi)uDV5)pJCd8BNx6FTAB7fV(D6i0DylxwxDW2kNIHiIMK3GzycSh4i3wFFv5J3pTEvz9hunjj4nQslxvgG)Po7DYy0iQxC3LAFgQU0diFNpFXw0XLMxFUUbxxzISWtQetHRCnEGEzZ2Jv3SU(XhkwEWJB3QEGmtxyu175GJa7Lec6aiYZKISE7eDWPXK9GZLGa7eQUZ6PDa2zBHh9Pg3Cr38VEC(Ao(fxdeLVT(t4Eu1SurG7HRNFnM)pNH4cZTR)HiGAgLVx1puu92YfRRFBr1JNb)Vlxc0EuAEZvOfmjy)q(1LxFD5IhxT9ZtB23P6Qnxv42Ahi8cSbGPAkgmv8pzSn9l6ar9sv41Xx5)SgqcmCEwpxffIjFCX8hWO3T8maWyxUZwZr0NFE1Ti32QdGVfXGSNh77oAYd)RcvUAhOCcVayqXxvY3Sgo)9ZyjCC0VVD98JRUUM9mUdrmtoQJbrWK)DDvHbuayJ5FQyjUz7QHGjqifNOIEe1IjRR3oFBH6OzFxS9SRxpZUwMzoZ9pHvHUlu4HfS5ddqsSAfUYu9N3AyLD(6IfWzV6ktvXOwFguOxBjBFDeOVhwufyuxj4KMcvmb(2Mn8fC1TpXQGX(t749yIVjfkk9uYD5iomT4rMYQco8tw0er6sXFFLkxVOJ08RA6xAYaYl5GoebaBMAcbgTi54iS9EuiXxy5WoSopy(nB4Rj5RMFd1JhkRUOG8VE5dBysf4x(j6iw1sGb9)gjJXa(TT4(vfFQy17aiKnwH89(Y8BCsGfAgoez7oTUY)onc(bvfgDwvbSwmVWdbANBQx)5lrIONi4WHaO(X7XZSBOqbsWfQWKaC)(l)eSMHdAVaiaEG2LMFNxDZOM65(RVVEDZhpyYSBlEb9tFUVhfir(LI5paRHx8F9IzRlRURy7MN1ejMCma6EXLfBFXBkM)8wmPtWh9fhvDlYWfXTptyclnNWpRE8(QnMQhf(QnN7l4ipsOAcQH5s1DYdiryokvMflat1bNnB2zV9KJMoZkxjDYSZoh)kgoQONaQtnwMJsOHIQbzseWQM2NlrQvvvfziCqQMpdsAeGy2v6FJjHpUIPQyUpWxJcFoT(YBlVERzAac(QIL6HYH2eN9YnK4b1sSSGddMI3fl0GktVxGytwPKyfL7mBqQ1DPM53S)JBRVKp9eQ76Zxum)gyDYlXOinKHtubZlMfBWIREt9QLAHhCE(ZQoDZ65llmnm7zMQ)5ynmfdC7nQ((bE8eEnxrXoE18h2Wsbjq0pxU5X5RizXpD6POvtbOF8qVCMIwnfftwNubFnQ3EucOIn(PeSXjJ(ua0gW3NkrdgIKXPOITryqbJX)M9hhA9rg6EbA(OpdOi4GFIohG(BH6ZiEIPjmjqGo0fEok0c0NjQ1hSaGPnunCAAHprDQHLlzBbmQiYdvGn40Bllos01NoZo9zcBdN(trEsIK)KwL4NKhcJfIe6ZOub)j6bdeCGglIJlnL)mt93Onl0NQ5jJw2b5eyJ)8lp9f0XjzXeKamXwsyI8GmY3mWQus2xkZqibygxg93IuXaFIJlIEh4mO(eNxyajKFoKOTr03hWwXgr(Iihm2fnklb9cWx7)sZwSZNjbyAB08tChZ764KeIWseLLYqMWeAEsKeDIe0pnu93zmbgbzHVxs7wWK)C(tExIKSQpf03ZUDf)7a1NjmKNXyjuDt9ezOp70VSqYTpI0e0IUiqrz2)uaydDAEo5s3uzqMq9j5ferAAcVV(hT5o))3qV)dFbDF3Xo45Xu8plUiAMRJMBIIjSpxLwmLnINrfbvIqjHBkfeRURPyJPA91WNGKlbAjE3uTSWlP7pJ1ucHoZDYvcDXjFQ(7pfeMEWNPCZa1FxBRZ61fvl(mlq6lAnvrPKSa7Fz(6kLazpfh5havEGFxSyA8V5nM(V7sToTEIT0vRHAODQhgoMzO04x8M66L0FE(66RHrJMWJ)PsQ)lqbYWB4TLBwuaWZQcq3IgQvy144lTAMgOjV0nbTYSITBWVXPqvYuQ7949x1ifoZDVlxnxZfrQCqR1t51r8(gDdWkNGwP85llwD90Y1yMrxD3M9VQ(tQSDJUkw0)4uDw0TvLgSVUy(sNwLbnVQxTndOqNRcSStdIZYISDQIMd)loqtV9V05sGY2t60nUGFz98hSTf2OjV7Cs1vWevBTDf6vQk9NXOGIZZ5UXiy0KojftNuZjeSk9Z4mZIumpwFdxid1jpNxZVO5T0UQWCWuxDJz3OA(hmAao0QY8Slo7KJuvZJFBoq3C8oVy9fWsmU9v8PuNUW4mcBhSniIxNotBEHK8253uUWG)sLo5WOfpjurzHrdaqau2DRIrHKwDyoC(4ABJ812wlD(6DxZNEu5UBf9AUrzqbFVZrM(Dk6C3ByfD9zrpPhCntF93aunnXDeLbanNUQ8boxNNA8hfz1WBWPt1RvV6EJbbBytOp)IJp6YzF8No7Kp80tgFk70O8IMuUSsv4uyNAVXTidas7mN717WRA1iMkRwEqthVv7FOYmKDE52LozJcqX9ZvZ1ltgAGPx2lce26ZUVm06Hefjp6HVngN8QxrMcWW95)qLkt9C35n8XZny5P50rOzRF1fUZMXbRs8Ed2tKj(4iDFBgPdxTbJuPmdufqcAFcsYbLCPGmfeqQ4PYPOUw86liRTOTZscz3WPOsNLVz5aWQFRIkY8VW(Hqrs96JV8WJp)KJp9ObiS09e7oM3EjT6VhFTtsRUH)92ktgdTvdQOEX9wW0FcKxDqoBX)yQJetHKmxs2fGbctiIWqiPikyQHVAAm3JiptsOozI05j(olHDvCVoF)t2)1hF6UyBfg(DhFlJJX(BaBlB6F)Fe(wavlzbgykuiAkuqqaf54iWk(CX3q2wdqaf9dbFF)i4d1wNYVaGocdPUuGwL)nxE3RV4Dh)6pEbiZ7Sl2F2XND6qCK(bdPVFyijePj)1W35hSD(oITdiCcZ4hkbIIJttP83ctJcGbuESi4BmdO8jh9ZN9po6IpEoWc6Ol(5DYcs8dEqFhXdkrkWGsisfrQgo9)Xvcs(dUrF)WnsKKaCHacMKubgjbrCCowhgGSmYracWaWV5kfLn5YFA)3U)PJuRO8FWr67hos5PY)Aydf8)fyd9)2ExT9222aH)fTc9ULs(KxsCArtAdQv3w(uHwJIRbCKdSCxBxr)VpE8oY74l(LoS1HI18PefllkYJ3DK85EE()IBOQunMWZsMuahJAH6NMVzzcn91xE9fVO9Gzcv(d)oF)43Pqn0a7RDEvsnCK65vnu1d)T3v0popKVN2wOuaw7WEFJq8OaQSm1k2ulodqTZ)U(Kkp56x(IN)MRF282F9IP)YfVAFhgsXpomK)XpmK0MkSaQQQPkmSYY2UbMtP5XTN4PdzL)hE2hFrqSOh2eOX5q99iSl8yR1K0NlGoW7HoD8JrJeG(QRShpnv1rcgnva)KsnZwgsJu7QsH6mh5UGtZsD1vgZXHBRPJfN3Tbz42YejymUmUhOOY1qy3JvnCg14GQ7UpD276XQnjx)sDD3hVQFyHM))ItPDgup8PH3oNAfAaAZypWGPI(HrDvnHmt6ML)r3wnZnokBWKogI30s7P63Azlm(dyEDO)PXQ4tR6XhXMUHf9TRxVA7YhBXj3OqdsQUUvPxi6eSqx2opD9ML)56HTDRM54qGjcYKt6HYCGvkuSHGQV4aOjv62djNsUyhQjlTu5LoBsrjx0zXGXdGdKk1NkPPojhURjejdPF2ewnWho0QziYKyqUEsYP0o5ZOSqoPOrnW5mjPstGtD(CFBejp6(LAaORzTsaJ9ectooLlE1kPrzwcA)CZMLQo(TQhQUiucaoZpVQxW3QPmdroHj)R0scsqSz(nbdFvaIJS0pTfIqKNbpFWdgguwdriI2sTUsVKXcZ4mlGAeStL(UQOYyk6qHLmBriETl1xP8KTJUZ0fvWwH4B1HKxrDX6d2YO04feWuinVyeNOTDmUq0GZyW6hsY5t84UJcMxYU2KOjA3QugvZpezgsqjlI(HXuBVfXsEtSkJjCguPZUDupqOEAF4D9daVMQS(SyTdWQLEKCwm9oT5KX4a1BFIaVdtfYGbSSUYuuPJEeaBjseM(t9mi7645bFTJClI40m217hGskJ9q8t5vLpPoppViTmnrtEEXRlYK9vkKYyHCdoZ2LsWFRwphsqy5LSk7oB9MZVz(mpahsOXJ1qgn(edimxTxdK(AnpUwpOBEXDlqwLZcOq06I7PDmQfg7i9MNFcksfgjQLJbxyY0e6TxVQx9MawheBvV7hESCxC0Ova4Nx1ns1)OeAM3Y8i69EjaBIkyXiRkMmQboULf7(IH1qIoLYeFw8yHhrSNFknli8tM2a4gEL(Ss5K6f)iqNm2U(v9q6PpZjpGA5mpv6a9DJ9bKB7eMz9YN0q1)nBA4P1W5XIK55Zhamk1XZv8xm9Tw)jf(yBfXqNJ8JDlj0J31FLk2aYw2TcrPAUZYnaVaUbOSsmI0MviJLEQHrkPxVp2D5o3QJTyJ1OjrmhqYVf62HquKlerT4QyRrJeycv6fN0o9fGp4NEX0RU4vQVIZNE90lrNiPQSa1a8LMYRs(yfYkU6aMUsTmIRzoFOQMt3dISrc3MY0cUNcYZR6nWl1x78Pd7EfgEUFNXHZPz(bRe6HUp(0yjdgrpomlrq6JSLk0ahpxhCltsjCM)AFV)zf)D84hprj5IBvgcAR7zphDE97pqPQ7LfK6BYavCysI0GZv4Tn5Njt(mOVnuWw3TevaRr4(4j6i8OC273W(tEsfdr7ku2RTDW1mEVDWRFbXXUIf8KLktn84wOOwft67rLRb4aGZu(Nuo51ViQFBrpcb6zcWslei4mdF3hXfRxwN6MI6)avP9EyrdJAXKOYOyjta18MK8yhd0)ecO)KyyGI)G8PRw8WiVgA4V8wkp3H5vBcyuXyJJqIvQvSQLpKHC5N29Qgo1xe(FIWN5lD3ojoQruvpP)(i1oc2WJNkpkoTMeZPvVo4PtuM6taMIOTU0MPwpjEXVsdk0HJs8ACmnCYrJDSFm7vsxSkLzxcbK)46TKxNXGkXWu3fQabGUcY19Sm3thvzmuQRrbsq(ZKtzrui86lICDJ80C8BFuP1fNZy6ezcJWajkWjteJeoCjpF5q17oSPV5R7vI8jzR)JqjHomVd7CcrAkFqnvODpc(ZUIpvkRLerrd148ABm0R)6KxDmUo12TB3Sj97Z6EeDeqeC8hvMxdDROnIYwit0SDslby3SCAX4nyQsNdrdrjpPPmRXwBwn2Ck4L4XjXLzw0HRTCHyNIWnTfFyHxEr4L)sqgRogMZF)dpSE4MEv22yDgMzk2iZGmVNrwPkGijL(3TCGSA9DKAfiDogfTgI6jHcBFwn71f6ungagoBXvAVRL5ej2swEDOG3)wH6gYP2xOLPrBtg66HSm2aIhpke)VrzjcSIpk42QVzsIJ0Hu2zEG(Bl2uG7XD1VrRFCsweRKxbITmIu1I5I88akXNetCnCnkMDD03VZToXselUegiNlo5d7on4pLXDDXhEExkoyAgGZSAnnfoXRDPzpQvuMmFUv)ZSzFXU46ZT7KhXJs(FtwHebJbnBZ6h0zmbl)gnqKPsJ(CNjZ343C2cC01mTRev2EZB4JfI1w7AvkUZxcCPowZz3531fSz54IS)zqAK0BiTA8v)hd1XoE07c98Yhxv6P79Om9U7BpWbwMAoAitTdINPZivXJfFv(EDofnHuKNzAthHEBnAD6yQnM3Yznp(z1f)Rp",
                s53 = "!EUI_S332YXnosA)Q4B2))9)cRGNpPR0PswrBzPrID3wZnkOQIQkoIfznKSSTAf6n6)TyFXwKibabibRdsYU7EC1rS7yXIehsK5xEca5t)sTtuZJlsj)p3Vmph(Z5PnjKN7hvpUknT4dfMoog7)l1brPlZUECsEAHXEU28)B)2x93lSC9m2)z4jFjTQoRSOa(DNOjj0200kAzrE54h(yYJLlBGNye91SjnZopPz8m4VTJAsQMM2CusDZDjv1ES)M(X4)e))37v)L6WOtU6WBVS8RK(M8RhD853oUSmFs5xlQjFVj9NH3(WeTVGp(c5j11xLwxUSACAVxJo5skgpRSQMmE9IUmfAokbR8(7RtB(CX7ndacgFOt(LZtYkoegIor1ztaQ9hpzuC73CtHPlq3iJrO3w2KLN18OsJAAyUxi))ccKBFVOf5jpM228ErhErC8fNl3bV3e6a7OfPnkTRJYq1YcNUlRBkNFR)TMbwgH23g6SbT9GFBhIJH9lCW7erOHwDATxgHoKouVBj5HkTNcXqhdHOLTJIV4s5g2YJseSLjcbeIGJPR5TH2(QRMMoRKi0R1TdO8hD45hES3k3SwYQQGXBg5G20QYSROT7jmV2HDy01nebX0UJ51k85gD1zN(bfMcdb7LRABT1TeYEPkk4CRpruW7wptvMGa3TJhaxTiRcFRPk5GXne81dx20uwOksyPiFrL43uHl7HxH6p71TKJStZsZMoRbX0rU2fZskiKIdlxwmP(PNPlFe1jhmECAbWweeTSoLYznc6tKWb6dIUJOTjW1imWWo0Y01lWBF4XvKh7470(d(0hpfwkHU0trtZ5OonYq7H0hJlhraZtbUgTq(er4tYZtRNNwL(RNXFmOZOlaDTLN8REetjX5jfjtHfYbrex3h2rx1QgrTq3MYV0VwK1mQkzEAnNXUZlW4FOTbU2VIxGRMBfVIo(Yv96D0RUokISU9vroqDeRCQGIzRGE1ZiKHFvHuXQMQDmCz4wtcsBfT3GGlRJgsHcwr3pSUR1V6iuNU6xfKnDJUVSObTEAAE5Dj5GzGN8TfvP11Fn5rk7prOnpRi98skOv9SesJ8m8fjtMqySaz3a5(zuvwkaTalj3l(3MorFjR(de0QZjipnPtgrB86zLF9I7Vh6ak49DtpihqOa4E3iISD6HuWpYWI85z3Hc7K(oNm8QPpVGqYoQmVS6uaFYAFG6E30Ri)HbGQtWFiF5ff5pEwrnDnfa2K)UdbRO9G3Lq2tw2ucyHlAW5XzfFjRH(jKbxzfbS6kCa5gngWQOTWNGvTyG4NnUS46MhZbs1CcfRQaMh1uB1H5ulz4tLNuKo)XrWxbZtCEBSNTl26IxlMYRocTzVofbQJtUlMtHofhq2cGB6yAeshoKshOTPvuc9BP)mmCBhmFOCzDwX0r0NDFcJfVOGiCoIoAG1PRsNsE8zKzyDCl5GT(4qFfA3ZFdzAmSCe4HUOGF3bi9WG(DhsFKygHKy)O0IK7YtNeJtLt5lP8M4uoRb(NxN9harMQ0XrMJ8Fu(XNqDzv1LvO3pzmMbGXy0qRrsSQorLK383NrCdlBYK0IrdTinaJQnrv83i)TXrhBfEm99gtW0okRACEkvTBcbvA8m6SvmAmq6qfzTjM(5fLvZtYPZG6fjvpCIGc1D9N2mjuMkQzy8bG9Od8hnsI6svZxLmjBzDHTX(9PoppaNIwbl7OPJNSPZhxYyk5lpQL5v7GFe9)uznAh8wdm47tz8JAs)wZscmhbdcgn3YjS8ULpuBjs6eDjSRvjz5JOwrDxEz5KCcK9tDzdCJ(0j)2jxjpUXVGqJiC7P1ip5yGD7cHHWDyTH4dmldXtMLqduqrzrkfgfFl6SJBQg32m6)lcOYmkJY5ozzvciLFHKfMKzi2q)ARfGQdl89cqyoqCZPp4SyYgIFjkwAIRn8UfFOvhPCSH)NLLZzFq3X5nIX)Yftjl7PhLKp(IfuvyeYWyYcAZOS8gQjLbrhnlz(cYhpcSg5dPvLuwNFlL87jfOW6bt(cbsKWjurFPZFSz2i0DP7ZQQBUAzXXeICmvz54zj0qnq0B)XS8hxququ3u)U3)U)5Y8)V)RScCqinYEI(vGua9FvNxsgPGtjrn14mXn6FVmDzk12Carip7oY8f53CX5drF9YK8dMqTw)zQ2wO3j8aZxxxlA71mk24UoeN4j55p(dVV9IoRPopJ2ZXZQiJHFqDSpDspVS4H10ZV1R0eZlp9)5)pb7AXIusxFEzzX7oDzs1KFqmAHTkrjD)bvPjVZ16hbrNo5xLXR0OLwViL05fE(7)eAJsAE6ysZEEYIfeiDkKxq0C8VQF6jMjqTofrFJqWY3V2cDwXGkbVDfGMGDLmhQj4)JQkNtSYMcMmEY8Rjtt6h5qn5JOq6GJIp73oH32u7bPVGS6ehQXr12grhsmw)DGjKV7)oDA07oo7leRHF3LlRwuwN()dAfUbzvuZBE(xkSCn(zCsB(Z3K2Z5NW5S7FEZ5UtQEZAvIYBhZTx4pHs0(VTWyTt2QI)YoPnD8c(5Bw759Z3C2Y9NYj9pJC32)SnNX4Qap8lPxtme)xsFKmmnql6NmN8ExwwNbFc4Xmekaw6fOtWhlEVvOnDM9TI37ThXEwY)5A6BA5BN(EtKSvLMFzzwbKqUJo5tXqmfCJwO8e0FyTj6M2l2(b7bnTn04Ub73VfyJbxAWj10NuFA4PNM2MMb(0200LWR7hYNfg75(Ig1Q5KK2u2wU0LYMPnFRiWmCpNWWahFhtlmSi4OWsA2iY)P2(N2spwyhycTuODqONtGZ(kddxyyyzERPFGyIg6ZNCwggBZKlmsFA35Zo6(NW1Z02imy9ZuhV3GzQFu7E5Gnm8OlJwwbbbMDggUk8mRHv6ft8fKPqGmzBADRtGVqaXsq99n2gwlldEZAACRziPD8V12v0UEIMLSuVXn7ZmGMdXqG5ebzJ7jm5pZWycdHgvkE0AIIENa3tCHVjz8dh1gLqAgLXScftamAYwWst0Yf0CsD6rhhlLFNam)oSOFkh9y)OILZVQ8R1fS4iIVt8SSXpuqAirWudG8qFxwXKtX3uBqTfV0vfS4yY(7dYZMwqAR807BeWPHrhjTvMSz7rj546kYMrWWbaLp9C49fVbEVfMThGiDwt6Ck5lUFEqOK7KQyypLjH)Qpq2MEy(ByVvC63AILM3hqgoHdLxkFiveJbTD42uG0PhovKwi18gelEHtfuIdfZvB(Yel48e9PL5zt6tf(CHLU4qBYFlKeWslgP7(nT5ouDPredC8Hc1x8vxyOc0bV97M8Ra2NexkIjVGYDiFLqoPxHWMYRjBCs(fqsgBOr4UnHO)c(PJe0kwkhTW)6eH(7oPK0tSkpQKlrfqjYKbJkpaltLs5r453AzzR3EzzR3az5E04oc3iXsOTOJWQcZRwzB11ezH7wXrPw)1iFRtqwr8RV8Rzut5IRabDsJw4SErAZ97XmRtOwvG4vjvl0kgthPsCHVfI3dGZjasWKioiiGgrDs)mTQ8RhNvLoM9U8D6OSqVm8XqkqwJ4UgTddHKWuf5h9RCgTFas826K4veWvicMsnWn4(hT)m8TvrUIS8qRcDaeufOTW53zfORpGFt097WinCr6GhuKpLrh0Zz(2O(N5ath4R(Od6Lh1bqyzhr8YmPbYoBQmXGTVsguhkaUkgo6aW2uSJUW46qLElqmuHcjcCG33xMNmoDgDVlcR(JE1weOvXNwf627VwCIEiss(6UgadxAKag2abhPL9lkOAWTSIUVKGyFv6CYSJU5by7rPnaYGPprPbyAz6APazOddXf5KU(ak19A59vUK0NfL1XhBvyNdEnSzxHiuWxmiUiP0Ls0UxN7eDq7q7UOD1dKxTlaKlpakn05u2CYS4U8S)4psQM0od4dsCU5HumyVimnTLTWCiahDqQYaAQM1kVTAKGkunQ)v47rxcVYUDzieqLV4kMjj9eW6SH08A5wKfN1paygheG)2VqwQiCXcWUnesQfPWITZ2(A2cX(6ZVv54r01U64xK5lDMv3WXawKqMoZZgFAE5xhTkmy2w17AHKOoedP9tVcovNfdHU2(4uwBaoLpS5sV4(RskMMEbbxkpH6l6AWOcJgXxL2gCQxKjnoBGyQSDmhY3vJDnvx1yhJ9765ZGUeo864gyF4gJBneIIb2hTBk3EUCQZflTyODS9OVD0YKOppSdwA52C6GEzHrjNQmd20MCtuI7IL5Ri4C9I00ju3IuSuvJzkdfBLnZ)cT7Cu9gW0stUsWjPGHOAGIcwfHkip7el7iaL6uxBQJz5EGFCxKF)pMrAPIan0qrQg2w0nM8nHP7407tlQjRx16W20U1JxnEMEFY0IrpGhrQyzYRlmqq9Gzkk8rdc0g6)brY6sdDJks)cSt)vLThIFCqGDYCpR(0zL0Z1sC3O4jXXA2BRytNegr3E7u4ZVD8e5LoC7r)UJoU(nfi2CZaIvTySpY8kCaDlWK1cl1x92RZuYHGK1c5oWY)geGqR9FzqZAeD6cZP4E7qaTBVPLAJFDafVh(W6ZU)8SAoa6q2u2hQvlMSoOT33tH(aiZdIW2U9SnLry3CS7ooLoiY8qr3zlbM7IBPCAK7Gph)IWNB9qTNbNdgjUUg78wGqZXXSJUSSP(D)FE3veYmCUa(be(SnaIBq4RdLIDT(SVUc8SU5rPZ6xpGTvedS3s3NhW4Y1h0D1G0RJ9RpEMMyRoGdCDuzOpc)DJ42RfEthGLwOTvBY32hkVV3WCdJWUPyCdglKT1Z6(6gD3xh823JSdmO6rDgq9wc052AR97go0F4of52K67UKalKuDE2u6o4hdlh7CQcF(5PKvIj)Mz8A4RwbeYg6ghzDH(tmSXyCdjrm(7HSc84ewhJ3cedCcLPhq1XIRAHWicIvtmrCrCosvrS5yV(0nSfftbobEOqcCAiaivY6m1i4lU6S)5fFk(Gps3awSFeAyCt7CFwEo8xoEs)hAcfLSqifXYdjEuLH4(um(rAdfIyue88hoNmoQpL7Zfo0sZZ5w74XfylksZHMRw5iWXzv9iTfHmHYdTJAquLJhYB1BuhphYhp4m7kDZm4GKj0jGQrmiIC0)4K5lGJtobJEk)05kMwITCX0XtOxAbjvpstyH7(4rNDoh70HoaOxInfU(9J0jHxNpNKtHUCipXRlHclgyjq2iUsW72r6GRfeHwxk5ujEceqqHBkEVRZ(YRQxX28F8)wmTGt3jPR)i75JeRn3WNiS(8AivBKEQniL0geVWfiWtI9seUZAI(wXwTnUui6cXIvfbuCQkIEJGu0UcXuX3H5LlyXyFJ5ppwIatpdX4XJ2NLKXMK8JzhqWEXfa5fpulVOdVn7Vxkoqd)MoEWd7iMCa7mRdD6bSfwCQmNEYMzOVDM3hY3)NSw5kkebDZwTOkBoPFWdtkiRocoIQWUnBrA1If4JNri)qEOutv5P8WzN(nqRYz3)PsoYhEEZHwJcbP27CakteC4ikSotGnw(df86dCwNzwX51JW71oKvYx1KSA6FbBLu8iJjn5UmHy1kXOv8OAlDDP46SAmNWOjac9S054TlqROE7urSNgeDNyma7wcqmgTtGRTDfq9DWBqDCenMq2WWZsB7CACdEARfGo0TQdRlVrQlTaWGS7BojNmnicOWQjE7B4e9jkWnh0ZZWy)HoNYdQXrMJLSqmwEnhb8QNxw2mduzoAW7XHYwhk6tuKVfB0bo5z1UXk9CEbavclk7ZWnCcK1zlSqh)kU5i0Du41Pzrw88qUGL0Z4cBBmQvlp7vAsHCFf2b03hrE91GvjpyoyG8wiSz0RVLkeJqBZlGgimc(xkXqMjTGyTOvg7RXH4QLeJ6VkfnNhAg2QqAXm655Nyj79eJJVAaj2NwfQH8RJB(j3HXJmIMLup73sYxs8CYic9fjD8zhx)e9wnIUNWbI7HsG(xX4VLHCywQFaBUegTiBXhuf3Pt6RZMVipDuxmJ4U7ouK0a0V9mdCnTS9Sn8mnmS6ginl3(GgIRvjNOJjU5qPjKXZfdl6Q1vuTYnMd3D07IOBejeqV0isoVIDnFP6(UcBXPf89zpJwC6kOfxPTje86Kj)1sX8MPxwAzxhyNOJpuxhl(vzZboDLxHnO2st9CJXBOMq7veWKEgEtCzJsqq97CYcgf1PW5lplP4SQYI7xwH5giiQSCCRSoHSWejhb(ULunQpYwOJHTVPvGHtGj9mseaK7FxspfhRvtwf1L(0UQf7PysJYAj65vqstQthTj6JSXn6pzn12fDf4fPpYeJIlNIc2Q)bcScn0fX9zlpKXz3Xqu0G4Zt(gncwdDT9OOfVhI5PTjYudi4akG2NlvIwjsmdzrvzZztliCrxMKvWNlXDv1z2r3Jhl(gkFnYy1xfe6amZZvu7JzFTn9NIhY16a2tLK3mRNDZIiYSgZM)Z08yDwHkjL7jBVBxv4CBm6zABFbdvXnoiv3thwRLPEBOiOIC7q2IUAtO1JHPWERnrnASCvBm4LL91zn2lYus9wrOZAFvdm1ii3j27R0YAvBn0AekxA28vA)O5gz)i3relHN(VuBh9JMMwKwLK)uVOkq3sk81a4AMQQCmUv6xJBiIWWa3TtptNFLnPZXW)PDhSjHkOUU0L0jffknQZ2WDmMA8cKtMkEtAQgkZ)bXiLM4kIoHu2vA2)UZt0W)dHrQHEJXTxit7c9bDthmDtErfjCzx8QWBjyBMYZjc9wZBf3nFJlb7ABqJLSDcLtXUTBBxDiZWpCZLb8F(MR6U7dUL(IxwvCwb1PTfcL3Mgw75B6z4eAhy5Z1DBAABVh5Vz)W2Cw6SKUraVSkfUSOoFzEtgg572XX1G5Vx)q2I4bIPOVlJx4(Yk4Uj7A6f19ijHgVbrmTJUDCYcG3zYfeIqS02SFbtfmBjI64OVYgbYMTgjDZgQU2icCmE9a(H0eAWZhWvxPp8kbdIEmztWbq1DUSatGhhVY7(xP0q6RYccF7deBmyJL(S)hNmpzA65Wv5f9k5kAc9sQnesgcXLZC4s7siuAXuGvLEpGxDfe7pnXlZcst5DPvObduzsIX3DAq50BzQl9wYYh(OxF3vw(WCiCFG7JK2Ly2vri76qsVOJz0Sj0Twoo(nucCQuOenjmpft4NNhBwSJHOU(HmI6qQN3W9mx1hj24YDUL8Nxa4onp2tG23L79uRbXbg(756yB5BhAHXvNktz75VhyJVrOTVlIN2IyXswk9bYzXdFKYwafEaW5CwXXllMMwYUy2GK7qyVzEx4i9AxLKXIAi8mih5jST2unbvLUtGHFODcyzBUNjbzWk0j0YKFGTTmC82ZXYI4cNRNfEzrtPnqVCbK)moOZiXaxMSHzyuDiHQmPSiITbplR4jv8hZVA9cep8j(9OSvyG4wBXj0rC0)HRN0NLJXpv(NqBybtWcvknp5BGPyfUCDSO)w2gQ8pyc(qwgwoyLgEDg1DxA6AvGLPyPPhrRFUpp(IF)tClr0TJd7LO4tfXavIP(WejDPZHl3AoFnNZ6z(dUwnhYePkI2W60YVGNCJA22zqvghpEbqLyGGrRE5MkoBgePQQ0KhGegRB4WPXRbSay0NuD40HV6g5xzJ(s51dpCv1SSGoH27RVR84VQ8j0GLCWpaeew7g3oSuGfgInHqvL(ASUuy62BJyOeFk5Bkx8MCtR7dw0eRRQcHTACzwrr6KRtZVFeFpQqD9Q1hrL9UmBV)lwZoGLbFqFVDeHlTN8iid6A4geyz7sqomXa2rft184P9FmA(qfiGYO6D2umi0nEk6DO6NV(RjlGRGYSXujTfSnyGahZwZfpHLPBaEd)XSJWGn7hVS660AAT)aTUkNQdqjrN0QgcSFHQo(CyJRamBp1TT20bITlxP2g01MoUVKUoaJnJHVNvOnMS0nQRL9NLwZo60ZptXbaUnDRvsaVR6ePb6S(e1ec82GMidXbO9WeYjafuKGCA5swVySTyuUjVlTHvfG6EcL74WjdKG4N)NlEVnoSPcs9zGvcuf9l7yf3G(QPgGw3UaWaQSt3hktYO20OqBLh48TNW9sNpa2kS2BY9Ne70e40Irux0AurSYwd6KjttrlY2ZuS14KVOBKQcn0yj6I(XqVVr8mOSUoU((E2(RZje2g1Mxpie3OnKpfLaO)N3W3OnHgMdEJ2qBspwt6ykUjEcdS2cNJ8IUkDr7K13W8feRurPKPl9Y03dVMyi2Ozp0TZJo6fzv5Kc6vpmDVkXNLb8TaXwD5cPVgFanOXGKEJvt353Vo2wEc6EO9wmOCJ(8LVjKD(DcdsEFbJe1k)cUcgWBlBV1oGWnd3ZsvVbEZ4By3geEXUx51DtrjkRmDy1m9d2gonXGMG58pG79wyV6UK7SHNbEjgz6fe64YPfMepNOp23p0k0FB4anJ(TuIbb5PN8TSg(GhUbHWwoGYxVvKaBjo4TJVbV0IwSSEw6KUQdOU7J3(zhslxyisi1SRzeG6CaSwkM5cJS8mCewwf6B39clFVa7qM9RyhFyRrIoSulqFotpdvJUfMduzC7UJxlR2HvVFZqDxxY3zOs92RyMiTxJDXCCtiD)7LjvPIsNau9iyUPa5n6aIr)yP0PwSJhPgppsL82LeqgTYKGxgDNM4hCZVcTlElZDh)EGIRiXKvAvqxofNTUPG20kI911xrTeHAucOP98KXvLS9UgrB(uLaNph(rLTNRR0wAv)fLhBxksh6MSb(48SXpepRQC50zJe7RosJ8a7y7VYluIILZPlimJzik7P4)CZo47(y6MkVSOzdImuQYrWG2Xk3VjDIFnXdLS)G0Y0k(q7b7jUBEyCK4wO7CycfGT9gGNvHMLkpx0gVox(2WI7G5OT72Br71RG48Q5X4gE6zMxNjlspClRBb863dBjGzXkUSGmE8vL(Bsjquy(DjnG8KsaOWhlDao20ZXGnYN2XMxFL1PnXgDC8FzYKjIdpEVR9dM7W9lrewC73jkjkMWRwlcAlDG53E66VusIeFzjoK2PwqxXnw0FTBz3LMYsOvsKWTVSu0)ubbM7tldxdDqJRW86d82xaDggfojcGI8fsPVwT8z4Zc7kWyWQwwOtzIv31Vi6YxV6rzKE(6BgjbzPazGUMiDvNOPMCOcAY4nuHm(SkKr)0mOlfytx1QhBhAjw)0xLy0FMd1E0PWjhUCGhK0bmOFOpwpbSVIa9CSdIJoaiXaqkQZGrk29Vtn5o1K7utUtn5o1K7ut(gRMukSqdF4h5Hx3Xy97VOTvlP(LLH5wBZfG)E(T)xWQM2Bh8KQQT4H1n7Ut38pCDZF(VG6MFV3Qp7W)NN25Tx9Z3hn3wA0C)E73av3BPULHuP3t7sFtcSg2AN(xdp0eZ99vJT(Y76BI661Oxqb(xNPqDun)E)nt38nF31nRXkN4xV65r0SLDyY014(AFcB8QWgxHHGor3wN8fAO4vwmub2cBBzDlGg7)k14oeLOnjPdRNxRI3bKo3P99hONXg)y9m()Kv((FcUgpKxT9SLwVMG(Ms)g4rS4oY8hR)WXVvkyhW2IFM87DlnBRVwMH26gBUU3rVqDVdGtOF17vOh1f8C1041666aI7kOT6GnhyAom9vdE4gO4wlg52Y692O9xlqBptc28B4rT1w9ognOhbBf6Y3s(4EOh6Ks1A5YwQMADgV8AuyPdUAfOB6adhkUVApxlAviOx)MwBI0zDXGwdn4HouNsS(hD6HuR99u)1wcE)cTLB1M72fG2kA5IbrH3gRWhcYEWu6O1aZT3iNv4dQ(qw0peX0yDgUtHXofg7uyStHXofg7uySgfgD2G37Iw3FPJw3pJbLBR8Q(VnXKRpQ8wgto9v(YTpUA6dz3qjZsRTIA35mAS)8VJ58QNXqdULa)UesUEg289oDxV6OYfeDEgzsVlpyAp)q)CtpApCs72jo72jo72jo72joV0DIJ5MVtC(XS5z)B0wXX5)83kokN24D6A2PRjCNUM)C01yRtxJ7oDn)KORj4)8110E)MStrZofnb7u0SZPMV)hVGFe7)X)gPMj8Ne1m(7uZS7eMV7eMV7eMV7eMV7eM)D4eM3EtuUBJGStDZUJT1UJT1B7X26pn1mFhp4wE7o4wB5wer(AfE3fzYMErMGYt8BQt2TWpYSiDPHECstcVADH13A6VaIthYSRK3eQABT996S8zqMQE7J3Q28VP3DcBy7DtA3RTvxXxPI(2oE40EOpcuU5UxwLa1e(RsNt4ZWkatyuvs2eALI)jr5s4IMzKF98SArzYRwqyeALPxB33rE9LynNR(HhXs3zvzXFa1whGDO5R0)X9LvWlri(qfaYnAguwxIFwGY(PYcoG1e2w8b0(UCo0t14f9)IQ07jyeKxGqQEGv)VVLSiHvLwOOaECw9I8KhpVCskzGmNwraWQGsXdpEyEY4h(NLfSIuP8CIU8XB9YYjQnU8m2k6RyX1gUt2xqAE6FuL1KEBYK)fD(pjnzs(JXmTFej6PiO695jZtjOMtxMsVL7hxLTyro(Zb0IAW9lRWVRPUPk7HukfJx0d)AAYIYIBtlgtwCBWMmnPQHWL8fSrSIYz12IKLtH6j6TanHQgoJsCBWsurYCs3E)J4hfId(AcPh)vGuD7DaTcRdAaXMUM9vOcEZwnlNalEwo8IRX4SK8A5fXywLpKru)D6G)eCSltDPhhZecFz9tdZMbvqJ8SAcMbzmFl9DQXYCyzoY6vohh8tsV)wCeG78(7sRBk)6TFn9XkYiReR6IorqLgiT6H2xfAQ7rAhutYiTFnWNGnkrljbVMWcpNsVMK(LYBHHm9VQFKSex2qye0ZnhJQ9AG5vtRGh182ji7kTwT9itBKLbEbP3sjcJMUnWkuL9SU5ePAG7u(frSHMAmKdwrAGb)VcFjV6WdfOh2nxaHbUIWaFDd5xsiS5NFYXN9RNdd9VPuIelLQ1pmgeLMKvsCeTAt)dnY4Lv1Lvh00KmEMO05aQfHvJt(gHRQUMGH3VG4mGYs5AVJv3ILzNc047DzyZQRyT)S(QFQva)wb)9wB11cURma9rZsAO3o0JX)ri9FWQgr4vnnAa51K)pALGaUiR9GkBFnr(a(CwP(58KVrlyQfMgmRrz12jwjxav7LnjpDuYK0JtjSH8IAQO61Ws6cumFoNOtNx3FW6T3VvMHfRiIpI4GH71ABbtIxvMjG)e4bkCcmkoLxlszFOWO0N6(js13pA)vylw9oQCXJ8BPukiuAdubkQjkjFw0mJaBBMGfnk(hHQl5ZCc7CAXuMn74W7kv8hSercOcej65lyvfvVO)RZI(Vo)Di)kHUFPA9w59EgU75yBzyg6BA46iQodgUw7z7465qEEO12DH2dR8O5a1XI1u5Y7rBLFsQYReitNfs8duv9isS3MojRbuH(jawd0PoNyia31GMK7AnCL1inLe48UeaNaAb3WX1W02XkqqamDDOvnGqlBFJT5o4Nmr6ZNJy2GSi8qyuX0qr(2GOBVLG6DhnCabSkJg1t9lkOfUPrmfElw2CrrC5cmNc06zc1yYpwono5U4E8yco5d5NAcgfw7HssHpxYaZHRHDelQi2fKsnJrzsyqz14vc9WG989CTDnSDWQPKbokjU9KNpsTqUyPPqU8RfznJam9A0LbEjSL)icUcbwGwvnDXsmjZqg4F2WddcrBAznQoErAtSuqhW))yrwe)NplAjS0BExZDuuJ2YIMjVoeFyBX2lKXgd)Wb3r0mC3HDl4uMM2(wUoHeXnpJ2coLFGJn)xSAJ2L6lJ1)irLeIF8qVJysmwZAyUNrgShrDC5icvnTOrXZy(WsGWk(rl2eITQz7WknqSPUID)0hlfdbIhcLFnTso6nqvrK479CyO2wi7mz76x6RZQc(FEvLsy0fmAKX4NIKXeHyUs6wXBl8ha2x4lQwUGOtmzYJQ0FR2kIqlD2MxCaHgaRaBu2G17CR847Z85TYYpBEtRxUg9gHNNnbQirkhwAr1FsqWJP(hnW32XElxFXm0wQ0LfyXpXGQtXB4rHTTMtj4zisxOrOn39rYV2JBYMYPbJsaW4gwDFJZVCJi6sslxIt)08KVDCkW52EFtrlI90IDmw24aF6jAqWJf9cIEwI)FnDlDCXk2lblHI1dvhv7nZ)mNDcfjokpnPanOWgLRGITiDa6qNx8rGiencXSlbEzPZVoJaikNXuEDLaUjZ9FdN7NQ3NmgJ5OrT9PySQjMzG3lsnx7GPTkYEeY5GXeirdNjnsA3FF3yqHFwlDmLffsbKqhockRIGJIoQIBRp7UGwXflG5fFLt8UqxXRG)zuDcq1GrAArxJzP5FcLX50QYV2mRgRREO1n44LfUydOcBAZlkWsdjjaBtEvduIp(JLJtu3Jfexfi08lPQyymTXkqJkmaGZCOaJYJ7AApHlaNhxOwWYfCv8ACgRX(Cp2o1cAd4Uh4gs6KlzmnObyTtvJwTd85kV2PP2Zc8yiGlNNu9aVk7Y2nFYTGSUfHa2Na3VeAkzlKFMBKhhhBm48jDXkwAEEJ8RjATn7eJJC6CSMyrxFdBtV7aHfTd3SDRcvPfNqPc2NcmYWznXGTEkPkE4GBk4IzvIuFIPPlq2nQq0N57RJ2LGwDewwdSwhllBHnbXqQUVlgT8ab4cw5Kf9ZnD0gRCuCt0zvZqlis18qeNGIamBHWaqSU6I(TOwGepvS5YAUtyPIhZIcuRcT8m1PWQUNHxR6p()Ek7F)SIIeQnRwrwtekYO8(s19wbGYVabML8)jL5bQ0s3oV12IwtlSyMjW4UvkRUk2j03EmFzDzD19Ajy3b5O4E4LWh1(2YRVI8U2(OdYZMkFkFLmYuGqRU(CLy3zjjWjsOb3XyGol8dNQlDuB6QOWP40hQt(nvzlsN0dx8g(UKaTnvw6nUNjicPg8L7OqXxzWUjBrafiOBAV(nKmRvB6xSS5SoGa0VplLa0Lqlc6XdKIw0R)RjJP4(9Sq7pDbgYNaFrwwBJQ6a)bGiwFDi2Mr9yHOwsO1Kj0EzsvZJ44STUVTjKtb7SsfeTEEzj1nkwAPr2yU4aXAJ0CO69YN)Dwv1L6k7wZfzfGyuoWQVmIQQBdm0HOfeMEAz9pKN1Lo2tk5Ay7YVKtpwEdSK0MixlevrPiKBePZyhHVoazOtvFZoSDJtWQ7JsEaiBPxRrhTAIOCZadoQnsZOwXVKniPWTP4V1i(jPC4MNLnDRtXz2ST(1zA2wS09CDzAyG4sNIZ)ZtMMnUddiXfi0Yp6N5GvXEyCGrlGUS9KU1lM1cBH2ovoNaZV7bcyi)wG8prNEmJ(fgZP80B4vDDMnl0qo2MX5rBI(jTUXSATq9y9wvajwPJnDcwHJ3(BJZnDSlCf(QyHchYehPik6GoTEjZTcvAGE)z6aFpKxobQRxk8vD1qY0lPcBdr7Qz2kJhr3HVynrum85)Yina1AS3DiT0HQtgfPmnwdSXW1ACmB0arxQJ78dyJGqGq)6D3yTjzytSGWDP8uDuVyJ5TVGPsJu3qEfkfUelJ(GFhTKmhA1a0cB6z71zJEWq6K1XWdF6tyauel8Qa9BAqqd4rPJgz6ZkMKr8NUS1TIngDALX6024TmwN0sv)lmwN7fg475czqH(p(Zi0N681Il))DpQMAJy5OTnwJ8JCY2eRrZGocCmxHwHuCWghIYWUmWs4CkYJ2VzrVu1iclFP18npULVCtd7gItREYW9ljYA5Fg0SI4xv4q1z)W2hr0)sga0vAhrpBdGppHWBPYAA6T1Q01fq0xAerh96Ji6a6pTOzIqcdNniEzbqvx4f6eGcFzAy3amf0gLh()wUMABis0YFUXzTB8uDLMtQofV9HATJJC8fKogvhGj7gxhJlPjRnEtdcRn6Dsh(82aWr8orYoL(vQ9E75iH3V9c0P2ahVcl0CzHESh8QwNEdKgNcwyyJiSyLzRAWWmB1Xuj1OORp6us2P7AS24sRlaPRkyhdLpMHcrRJN0)1gTwnpEA)h)8AJFiHZGY3jO6sSE68pzRJR9WbOQxGpvqJPKSGb9TZYjCVwdjdgo6)K5FhXIpZY8QAK)fZw0VjXOLfK3xrec1LAGbCXZEpEc4GmXXcnQQrfIHwiB8crCVFgc6f8XbZnWqrmRdvJzKZgM3mTNRgT5n47qW(7669wgQ)npeD9d8VSUq(wYYAWq)RlrUBqCphk2fYPcBWOX)9k()RolBDYmVUlz7VFb)BLbL6TovcBzUUic4De0em7sj5CLPF6TiTcAJb3QZltp3D66C(MKHbJE(mbZa4OKqvg2jclNmFrZJRMWkBCjAdZq78K(9T6ytkey2RAReOnnedLq81gJUHt0TAEhKc63kt4q39xZgKG7NB3yFpT1bYsjiuoBBqO(RtCMwBkT3W4n5mK2WvzUUMik9I3mCJ(tyZWfG5aTy58vgKQEgpBpzLrJYTt0OEV9gUL5C0hZj6zlIEqI2Kqoz)s3WCAJV0a2WF32yA)gVj7ELrykyfBPH3KGmPST7I1hEPoUQf)N6oRdfRxvGL64MxR26U77oFJ9FJdT0qB2U4np0sdfdj9PQRB(GT)ZBN45(MfIi7)(Tv84Hwxt8w4EUCxhpy0ANs8MVX9Sxxas07hIsyhfW4AszHMaqPnDU9JLWg7fNKDEUF3dJGS5yVNMDKbniJO4iRACEQE3N2MTt3lA3dA26p3T0WV1nqbmiHvyWA3KsmAGWCPrx4)l79S2uBJKT)vYFGKRKA905tabNHAjaxWzMmBnvLYGfG2yKyTSZmzPY)975r3QpTEzdjZmBQlBTv8GDRwDF6Z7(84rllSRZfchY5cJPc(ST4BHV5SMOpNryfo0J3i6Vwd0RZz63f)965Hb9k32D)W3GNWC8xIPf9mSHT)n5TIHVjRUUTOxpdmO)gu7O)gA7aRb80qpowu6cObdXLVdomy3CBX4oqO)aCBe)opKxe2wiY6g8VtFAbPyVXmaNZpdC7hZ66BarYZkCnBp3JDRqLXX0)ueaBCl9wm))PeodDIUc2fAC8ZCkq1bW5okNjIUM9xMZz3p77UiR)6ISoPZWmSXncgfn4kWao59CIJ)iVBzPIMSEMG0u(hQnIqNSQ(Xb68t17XLrUIuHupvjEj2uDvPEmtNs7nf31M3tyLj9ldMlUkvQU008hLHXEVkYZZpv57ff9OwGUj25306Rj0O6S(E5tFbYPIQEsJnNdrjpM0SMYI1VHTMV0rKM9xqG)R7o6rNC3uLfNemXPb4IxSVNkITEeECLFe(THbjbaGl7rv7b8j4L5(hiqnwurqIz2)QpqEpybwRwq3HmBWBYmvsydcsYNlcCoVmRV4JtS(DvLAYv)wKrXoAw1W3DeVQmGQQp18zPtiYnKYECUCoSpp25y42XFMbHVkoZxfL6bNPz6(MP15z23Wak5mqKe0fUEEtWW3sFL(SJSZt)wDuE0Y5i9lb0CnA9ecCdKtypk1pg2o0HIJU2Q2kcCJ(vRyKaSBa9e6X3V9t(060DFZXIuEFM)RAWiuCDtOJ3y6Er5oZ7BnZB779CGuUVZ9w6Aflt7YCY3txcF6TOPrFXB11hgD13Z4iTYkwHARtPmdzp6XL7s50DUMXzHXlpQGwvTdrvEPFHxpZM5z2mpZMPpZk(VcwljsDka9zQ11wgYZjPXTXWFfwnzCucST)Md8gRaJ0kAfhW3WoKSbSBIQlUdmKD)bcSTE9ASPiGGQFbgQ8jzliaF4EiwJhK(CNC)Cp5lXJ2f0bP696Bgk9MA5o6bIk)Ue9pMBjnrcWnLZOTB693NW1Fa3G7lwt1UUM6rYVyOBpDSGtAl3SkFlzoGQNQeREP6hrG5qCCeUPWg6CJNLqWAwI8PR0Hoovw4S52SR67YF3H8fsc0A7c)Ekrq9QprF3uWSHszujRyV0xPYIa79scsdhlPfgqTehESjDZwRXtcVbe20MdF3RGDS0FCxZtHrssG(0bQfJPU7OW2CQ7Fi7UUuJEp196k9HYIVoxQDVbA54UiTV76QJct)PM)(7UoFdLWM9Q1xp(9VHiVFFI)Ok6n9Cpkdvklgk79FuQpoqqDNoPQY0IOFv4O37YyHPaq14iEwYWFWahy75UFNAk1aXsWyEfVVR4RNmD9jNKv9K0lJwLpg4gf218yO)BqR19hW(HTA9zJAT5WQi)SXMFFn2SRoMpBt5GI57xXTH4s3RAH7GrK9ZSTB4YVfpHnScODSQSX9(dro6wXjcJELFAK()N93jvz)NwFZuLrp71N)7LcTFoXBtUXJW3pdt4SdeVDTeOJn8d5KOT67hL71iRHFDQGTOEFG(yRPYvBqYK1Zl)0pnVEVBUzv1P6gkY7QUel75tDVpnsLcroNg1jNg5aWSLlBs4P4481RrhutwDkUopaeC1bRQU3uQSdWQNnwcQx(LFYCyzcN8eg(B(9ZWTHtxkkJFxAqGb3db7Cel8YphqWJctegXDgHB7LjGTzpPVqDZ79KZoymUg6gX0Tv1RlwkVspBeGNjsPgTfcfob90ofVtrsiRTQcqD7hWCnbqvS47KbqHI0(rjQTrPMUpt3a0NP8UyzLBpIkXb6VlbkuNtATmKinvPe5SFCW2OGSTm7Q)QsnHpaosNwJccbNvCNGFKOJbz3)ovHFLqvy4XCIMeFt8fqTfjNsA9T2M)cCcODxh6HtT1i6b7PnjwhcqDE7jtadzWAaFjfney3oHnXGv7EWnJZm2uZ(vVU9AE7NNGKdK1Yv5)VBYzf6)LI13E6L)RCYQBgWIDbIgZcA7yiyf4eMJMKvA)ogetSAHHpR6(TVWcBq0qtOFt(1Z3SKytPDB9TUOFPM0kSjOeE787l1wBvA4F6G6JCX21wX1TadhSrdSRHV8m7zqnNCv6guMrASb3rx3H)3i0hyH3cPozsz(gqs0sB8djmpu0tmmPKc1VoKHARaPPpN95A3Be)nmyriu0Niq3VPJjORJegkLomvYAoQPiE3LEZjJ2LzERMvuB66WMjJdNvzCUjit2H2S3L340UMOwyYzhmRyn3NvWQ(F194lInvxF3biiLU8IDdxrR5whyIQzBqX7S1xlAxs4iL8GwnOqZrNzgdSPJfqb8(YgbrfxkKEfAJ1Sqlt3WitPfaEAnFFhWTLzSJgb85uBwya(1velaR)T9KSZDU(ax8IwYHCap2uhb2MD4rsr)MjgfTnadJZAQNjO4APxHa5zGkGtYKf3xFsfj)su1CZA86XXvx9PQnR3RgKw)7lq9yxvT0vGTvDkD)wusQWyx6wrJlUDRgeJqvHgNB2WlJ3y3)ZL(VsRJBlwmBhxnX58yx8jQMaX5OlYYlwMXlbrUhCTPRdCE5GYXuazDczmGtG9rfZXubQSvtS0mHVA3n2aamVT4SDHOgdoS8smaqlYRp90d0vrWI1xw9hKW(F1MR)gfQB1Psb2Qdiphp7Ky)FWLzQuEAxBZYMubSabLUKyS6U5c8ThxHHjVR2yJkeb7rRLlG9zFT5TGSU1gfDMZi002nTHOfcEA2q6sHFNX8Mnfm3iXM02ZkDjPWSOJb8YTCZQl13QLPFQnHntI9BA2rwvJCY6k)ElCD6ChtqgkWFJAukWrj02ix281dLuTtyB9D12CYs3vBrt)PTuxcff6y9bN(vLwwrdWYIciYJeJc2sKXDHnYQ5RYpCzX68MKrlWOiGWAa3(y43HIKKK1pG2PRIu0mxCDbNBGKWjHJLi4WoxQsAhCeHUqzzc2ii(Po9uzt7n2IPOL1RzqkSP9PKaYjo0mwvBaRXBBRSdxbSn9GXX2hektOVscab5idkwhZzBxjbKNHgbc(Uw7JeTZ6CJfnAh4KZAHADCSOqX2k3HWyIofwKp0VQNMCQFxTNuROG8(Pary3snAtTGPF52IL545eN4rD6tQVsYasucomWRgjCZCI1VEYidxMWC7hvFx26ZPlUTiF5cXbRgXNzPPH)SwTSIomNxzIGysIb8vWVugs0L8yOUCRoqgKETW1SaNZMMBcJjj12lA4k7yYSpPNJunJo6k16hLWllxXwwEAt9n91Gtk3llmnjszeVPAdaDN2K97nAVPmTyznpDhBLK2yP9POCXzdtdsDGUEDRheXglWgQhN73QhNhXEJawcorIbOzBBxZ0H4osZ6ZXUhBMyHbpwtQH1AunPnUqkKt9o2Toco16kLTISLH2ziaQOgI3FViXAS26e1AReRLiCvJgdKJFVROSOjpkijIP2kFBKGDBqOs7fGMl3fp44sfkz4EJ7sAfMfQgPbwNhPBABrrtOuM865xL)B7TyXPL1)MWJV)2D5lkM)B0q)nBRG8vZMnTbqU3YLIQNOJ1cofBbINYMLlXfwt)Cxt2Vlo8RJshChxm1Ud3Te7UlN)pqtcWtRTstcyyazow(8vpcvyvnoaDxk96wZ9esETcETOtnvaExXuMmsVX(yH0REVXQTDBz9AYBJiGwY9FC3dNJcITna36sXoLPbHxnmS0FPrJtP0ZDXxAo(6Y6SIelm3pYUYt5Y1ViNN2fA1exgtoLfYoW2(Zw52Q7ezZOoZDB4jYOyR1V8jF326rGGU79154T1iI4Eb03kIHjGZfAThBHsbkbtBFHN0T2E2Wq2(MzFNi05JyM5yQAgZtEipN04faPWDXvazSuRXV0bET9GulmphDDS(2PZ67x77beCJCnv2Xxdcl1)G(Gthips1oqFF2IWwnX1XnkRl9B(H2KlF7vPlfRR4rLCh60Y2tL09QUOV16AJgSEBXlWxd7TbaeAxwBUE(jDr9nf(ubBdhRPSL3VgjCT9Mrl3GwtD0EyZDw(66PBVySYxVIRlhc11kUIHl(tJMlTmtwH823r9qDcvJ6hXRrNcZKUzDJmJyDy12yCWuS9YwF88lZxoRPYItZ2(RYN)jmcmN2O(0BYNdil84W(T7QJkHf5X6RgMvRIE)nT82zwRh430zxHhUac3X7T)HhZEeXOdcEVh6k8ewVHwmFjCyzuMmjYw5ZTATGn9xt4EHRTJkjNIp1Ii25git7tajZQgoxAwma6lWwdmdT)JuZ)L1psEcqcxPEfBBr0aclSdo99Nm7JND4549sZsWWhf0wQyv7xO4kzBrPLAxST9oJ0jj2hlJVmbrBtoEs99llwpLyv3sQM1TLoAvf5cIMVc7n1RNJSnNA7o0RY)Cr(Vpv0N010ObwQiDXFsnz9Tak(TvlximgXuI73upd(v6GwxR)A)6PyOiCYjNEYHecyZVxlMUqg)OlCszpqZSNOkLwFP5yeTcQRQlVhNF0B)jEnBrq5wmUjOG(1YGOeQ9jhK4fLq9vAZVbSV9dIbv9YY8dvjEbIgH9ExFDXFKB6ty4HcWf637COe1HJI(srsAW2DO9cDO9acVSjV)K3C45FC)9ohfsdS)rQUyTyoJMaaMikNAbh1NWzo3BU1ueVRy5YI6CqAZIAUUjzUlZWG2Sk1mgq(sx9jXLyfBpF)9kZPB2K5iyWPFeEP0kLlqadPlv0e)y)jaAs2l99EPFyYdLHaaTmfwXGmr4Se7JvzVgJqmcVpEsuS3e)WhkJvHWxheIdm2NgIYmKOuAiHEWZNaSCGtmAQIOrh6fzgxg8UHPkWhNQGuCQIXHhgQhsGIhsOp(1ErE0qWHN5H)Rkn1mxjt8ZEOmjeNLGi81L6ddjWleF0i2hWXtG9hnJ(QyyrNaBRYGmCePE0smZOjf)QLqMXxdWJqWg5JKO80aMs)eLbeigCOyWBdI6blHqeIgIVv)i8FdJv02nvS5sWnxycCkI7FLxcT58OnxIz(IPtOiqfs4WgEVXrX0lhhMxQewbdd0oc(EA9fqV2yC6PxUD55dlp8htODRxkocvgDGhGYRlba6RFaOfIW3gUv5tMaFCPMfjohJWZr8jdWZi)Su4TheMINSrmEOb(LiHF(eSijKozcPLPNy)QqmnywZW)jH2VQ4uc5SzoXXfiMZieDknggBIpHKspMxqI8bYKN4jkcLq(IXVg3K((PiTvgHNNsygr44kHn9RXddymHP0(wrWx6v6tHBemMuymkeVaR0dW0GViF6GWZpMgcOxsdyOlAeSC5duXYD8twAd2IkyBeRWqiOAgH6hHCt8tYWLrqMVaDjy8nJbvGypKrGHmA5r0DQuc5YtEk4SiP5ZljdNAFc)NoUZSNBiAM8CBC8TyMrjGyQW1BctN4hqJGM6WebqiggxkSeYiolrm3i6zubg(l0eglwckKbrmYqkLwmkIjSVYxmX4cayFcK2r0lLMEcvYpuj4QI02rj6hhgscTgvHIPcgsaE(LeshoHH0XfTVItL8a9nRr4SqHB2mczoK4NLesyBQaghn(1dYurqZGmZ0tACW24QzqBLNVBL5nbeCyoeWNV4zAAgXcpkuUlLdECeyZwi0rQ5iI6izQ7kTMCwh8i0Gb7W5zBs(ygMJYNK1gyBkbyqELmkdsG3EeCgd0E0IMoc9cJKhHjohHJjIYSbD4fpg)Xg2aoWVXeVzogLVIr5izEdsA2esBGaCFNX0dr05EwSe3YHkFu(cAAt)TqPzoQc2oGNf91MsyuzGPwAEI8CmP6ggoJrIPr9shxFiMPKeLABCNOvQJgAil7Sy(eGWPs91YAf4ukh5F4MlMwwXKmIKuwlSubyg1LfjBPd3mIkpmLKZ7Li0uc46du844YG)r5JtxAcjOmjss44W5ySj28aomNWDwcnTEKYgXe)HqZkMGJGUoeNGKesAnrGfgg2cZi1fyeQqaob(8jOqeH(Rus18s3gywl4oyhiyPLQdxKTPCymRKFpkzfVdeJeMQZoMw(EKu)q(fAe3YINhxQCjQDWOZcRzY2uirdAvB7iWWhvYpzumoudWxVJ8iK4yJQUQHKxnYo3qR5Q54O6XPNveVjGKJIalq5gYeR4ijkJ8iCC0Cn5qWwqTm0zsnchxrpd2KJaQHw3ASPTs8A2FolJTQUxmd0gZsfnnPAlm8(AJRLyFxAsuBY1kK3q03WpfhBgVkTtE8Y4DoTVk67EI63zGRxUtbDn7yk4ny9DzM1tmuKnhWxB67V)QQ7Wq0h9ccFBK12lvTXjj1ZyVdkDsCrzXDZVN8t1Dn)3PKBGF38ILduesDRmubXtQUpV8DfxTQ6D5LBof(pxSa2Kui)QVRIf5VfJsey7W3Er1DLfBUBA1YIQMYQnoQzR4l5F)nRxZzSRh((7PWtJ3ir1vF6cJBe1DacYb6ZVAn6lZ9xxk84nwQolBUbHh4IEP(6v4b64S9nL3SQAZ95l4Lc9aPnLKstTkuL(QWmZ)lCWAfiWJGluI9xWahOK6Z(JFVflW07hDQ5670ySysRKdNiFg3J6silo2dwn)AmwEofpEMAQnohGaQzYKDCDPt0FHpkw8OFtX1xxC1MLR)Y02fSR(Qpy5on0c8LalFyQO6ul(NS)2Plv4pwVAoUw567dFZA4oUOmNViHBwbi8)mMte07MUrZL68tJoj4ZHPmxfCo)NvWoHpCMnqtJvn5Jxn)E8UswCkav1PnKUi77CfHyH1TCFa5dFxSdm7VjxflXDzSp9Tq4w)ZaCr7wI2(hvEDfFkSPoVDpf6)uvM3a9WyeRcMRZwLFfG8xv2tjydD(kxgXR)3BMVIBkSRQwpFDUMSE6avxA2TTNA3fwI0)jSkmv8Ja(iTvDoPgOYxUeb98wXamDPdBdK)vSOQ(AlEI(opuaJ(BjmW7GLxoEhTnikDwcWCKQZFsdvH(0Nr0N)58f46sdRaaGoM71rKM4yZj4FoaH06x3CAwnSn0cqIKSm3F(n1CJH(Y53Ga2tlZHV7xMVQeaV8LNO)LZNxUaym)Fq0o8Q9wNF3Y8pNV89WPV9wb5oDZ8BezJfndhGSBNwv62fNGFqN5q87T5fEaCUFt1QVCbIa8abPpaanBUdjrRPRaKOIOeocql2BXNbEjaHXlaKS7PDzZVZRUzuLmDVv3vTQ9J7nz2T5VG(PVm0JchQ)s(87H1Wl(FEXSvfLFkFD9tAIutocaDV4I81V4T5ZFAlMKj4J(IdlVf5UISrFIWewkoD(SCZDL1nzzl8v1N5kDilqPl2R(zH6UqeW(FoknMLbat1(NoB2PV74dNoZk8izYStpd)kgoQXNauEZPmF7GnyuTqtcaoZ0(CbITQBlinioiwZxaghkqw6sZVDEoQm0rLmwfZ5a(AucZjvxCBX1RBMMZkklZxygkFLM4Sxutsd0lXIC(6V08Dyzeuk59c80KvgjsJ5oZE50MQ5Z8B2BZ6QlyQhFtvW(8853aRtEjgeyGmCej08I5BIMLo92QLlmkvWzrdRY0nRMViVP4MpRjXBoYatXlS9gD9rbjpHxZL0DgVC(91Mauf)b4H0qpAFz4nq1jNIs(NMvCFZVu(P2Z1udrm(m0IfyD8PPga0fu9KFLPDEBFT6tc81o189Naq49)cDrDOGdtlzy1Q8YR(cPwWdF1C6(Zf1BMVK)YtobT8WdDrjAgdwnSrN6HM2wcFnAQvqmyUe(zywQxk9PcqRHVpjenykimkb1fpiofnta(B2bJOvvPOs)08rF6rx6e(j6ne6Vv6pd4jMMWypfAOc8CKt7OpJ1RpybatRVE400cFIMbalxYCqyubKh48vE0Blnkq13NIzN(mM9xU5tvwCCi)jTkXpjxEgPuX0Nbjk(t0vri4aTighxsc)zQ(Vr7pPp1ZtkTS9YiWg)5xF4RONIsJiibygDiDsK5LswmbRYqYx(HPiKampnL(BvIAKpXXfqVdCg0FIZlmGyYhdHOltPV3JVXGaYo9mWyw0mZy0XTp2)LMTiXNXEyKM0(tChZ76O4ycXsfKMWqgWSF8Z4qcpjmiMHuXO9LecgbzHVpK2TGzZz8N8Uerz1FQOVN9Jm(3E6pJzipFIftzwZdK3myFzcgQsojjjgDwsGVFm7iqaSHEHnJ8rnyuDQs)j5GgvssmVV(hDfS8)3oE)hUYO)HJDWtJP43lUigMR7m3entyxUkDyk)12koYIbqLhyXkSyA8VzryM)Up16m6j2rxTwQH2REy4yMHsJFXBRQwq)5zRQUggnANo(NAP(VafidVH3vuFvoi6Smh0TOLAfwno(ANIocAHl17R1fDK8)4QLBalJkwSiV8TOIE1txvDNrNJuTYFBU7YwHRzMSx2207pcIgO6U0u0e(tSd4gobDpWxUiF51tlwHbLE5NQ37YQpRJ5nQN0y(rDL1dFacEODPuQU5dVUgHuTSo220RSvHptvD4xwn)EBHWnyY7pJucfmu0M(C(oPe1WbYjOc8CU(tcM)ycZWKjvCO7QdGmo2QivSJmDlIqFt7GLZoi8OKIwZdxCto7nfDY6GrtADZorh1)m4d0Ysh3yNF6XhQZWh36lGPuaEw(QZHLxu3wtQo85zW47M)huMeX9y2utx1b(Q2T)E0gI7A0iL2Gzto8Np9FC45FCV3)23D4jZ2B2rNEYdp04utzh6FsXcDYzZQ4Q3MC(F3BUbB854LDcO9IYfTk2fyWNb0C1yqd55LcmKablylmh(mZClQH2hCRDMUeyczOQo0WUbtpPgKOMyQdo6)9stAY6tvnEx6kRp5SMnrpMBZLKYEOAdzSoiYKWLw9ul54)q5l5eDP2wEBIDEylMuS7bJ2xk6SxQE3oa6BHXBeaRcnDlKGdUUGZSJBOyRBJN)1rqCI)RaXrHj5aIarcKdXl(eK8bAGG6y9DgbkCsdIWoJ)KI4pw8UNrGAJaXEsbarhEXSp(MJU4GJo74Jo5Wr4izs516Ey6oe61WjAZyOxyGIerxkzwiP0mEBykvaELqHG(6uOo6f7jZMW6D6f3btRNJ2)2qZ6hRVdP8JcBZbp97dUup019MJ66BS7S9oEV3C0jF8No94FDm5D()5Z2cWQiZha949r94988OBfnambnt9SCVFSL7f8xGCpqdE6UZb8imulcvOjLplV7hg5DV583F0B(45GmVtpFRAG)Np(KsLe)mFNFS578xaBhq4eg6muqXgfLKqrUwigFsHGg3kVNza9dcdOgNaCgWc6WZ)5TYcs9xapO4qf6rDvIkOPdZ8mZOFqvck8VceMyGle6TOef6gCvuuggXKGSSem4BvGbApRu0pm8KsNCXpT3727KDuROSoiy)FT312sTnsq0VOKsswxHN4MjPcK1fw7UWtPeeHJRyKPSmBijf)77mt3Z090Jm4KD3SfvbVHkz75sp9TP7Z5FDbSQI0xud98wnu0)9sj5XMURkjQivFhGPQ)QEXtONlADITPE8jsl0VGKzR8RwFjiyIftlmgXG8lQR))xePEMisLTZP)27F3ho9TtR)ZJ27po6Shlx2P)YYLDCvo0zr5Ly7IL7OwGxYCD8OHfTQDcLjz)FK6AobOmfWZoCgq8H7PnZMFL7A)lszOodX6fJWg8k1C7ZWSuYWLEvKGp5hbmElCN9tw1(X5ML4XSl3NHHIvmQTBGTJy4B2wIajb1)qJ4AVxPzoKd(u7vFMbBU58APyZITeG(W6Yg6gZ9MY5Ey7jbKQzyHnSy(TakwbZBttKSOfkZJVxB(B84hO2laH8kO6fci2VKi4RDYQ5lxPom8nOa(hZO7yAe6iek1rI131lf(CvIaURkGQm(0YdMB7CLH82GKPoYAC8YvhozkGlvEKZJTaeC93XSdBwbOmAgwXkEJZTrR2aeYq46JRmAwV0uB1iIwTnF)61GtBU)K2UzgkAHxQfcCodfeEJA)6Bl7w3SOgBCgKcAq03l10kn0Bn2tJhbyGr70QBnbIauH5fqQKDAQ2YilHSeLFX9uLeNLxMNuKMr9gweu)oyj(qDkwU6TIQkJgP)ufiwaz(TXdAWpUEut1btKTqZJISrOrcFdXDgfyfV81URMIN5nfepHXya(QILmZxx0clF3UA(F1S2a3Y9Ccvejyt4Lw10nRTE5YfRNFBTdT1OxXks0dk8N7k6LAyX)lSw1tPbSTR31)A5gyHQj4yFiXtD9Ct5TZLYOI1Q0sykkdUc(2uBv5SLlAvNB0vrfGkQ6hEItrKff7GYeJeVNei2OlZkMEqOL8oZHb31oHAW4WsdRwAqpo25pDjUJRMyNoP7aMtuQca4sfzIcZHaF14SUqdiZy9yXsWw9aD69b16JgR2awXsPS5bSGOWLyQVusmJ0juOUooYrTR0Bg8QL0V8P2onvkPwsHt)MX42Iq5rQVPHKxr6ovcn4atuGBVE0fFgwhycduJOYsdHpAelDhUI)gO(3WceZHyGKTqXP(SHa2WSDTlVSD1Axn6PjiyJnQXopCoMgt9itkJZabgsUzw33JSQO6imR06MHrQ0z4gm3yGmt5XSuM5ypGEwAL(CKG4URt3bxKIQxLwA1vfnC)qg2dLG(SBAUhzORzIkRuAib4ByMWJrlIW7by1so)0nAY1B8mujQ0uwmLvWZby8wVfovTjulQ5tDDiAKDCvZiuUO0YmtSo03bNtfE2KPiqk57)kvTTn9TbKjxbbqCJkQq4c0JVW8ljXu8q0GJ9exvLEsdSouqRp2vbRlRxVFaRUASP5kix1Nf46g)gT9XSaxHmtv3NX(DoWs(wy58vXjdy8K8I9XiEkHocZK)3Lc8JY)Pe4zYSNZ5bCqysCciXP8qBdOMXB0KpDPWpFNJktKSrziQIcMnClfItqCpmRXgwkNrH8E5EP13Bxho(Y046vNWcEQakqrTlDhpCoAnaoSrzQ148JraaBilmOMqYq)yBa)4rrQj7QmAHXIMpDN69EV2k4BoAVto6mLm2H7D6EhdBKXkFMmvTmA4qTEUWcp1OslwJNx5vLY89Fdlu02cuyIU36pq9HvhG0JfK2cAUfkZ4r4XwHuskPdDtWUFraS77BS5C)GScc60V6XVWYlDQb6mm2RX2KfOwsnbjp(DWJU8g0brZ6KL09K6iF69WiLnN5ecgBLp8zT8OnXNTBMCj0odF9WUMW08EWDRi9UVoNIVp3W4XUHP2FnbBHaqPRZBxtaBKBhBFKFWcNptSBaHCwCf5v7(iTEaGn8yel6pJ9UvAgQ7f2e1A5u6)KE9LelSGlTvZCHKthXGS2q7j6W1PMmicBYahbD0jau8K4GMdyB4zfqk28MQVnnwg8iOgILnIaGDL88tljCel9t6u(qmR)q6dChRUm0TbsVP4alz7iu0UGjNjSPrkUjxnYqceEcgOgY1GDsgcd7QcTJUg3Lm7Lovqd2EmWyyJmekteHzdlJPHEB4hbvSkEDLr40)c0wDFqdHyB)d1Xln1nsnrn3qJhRmgYV4axgW)RyxIVdcF(SbEULUA26KZKe5hHSy5VGh3REdc4dKiN(F9UOW0klUAjPneojw9Jn5qDFUKmgYi3Hov4K1z(G8fLiE9G(X4es3ehHNXd5K746L)J0QjCKpi9Ugms(ELWvxZcSPXBUB9YZA1z2(T8uLmCIeDjK3M(3NcoJIEDvwsvACCrEArKdrezk3ouT0XOq6W8wbMxSFdLLj03T81Faz6CbpPzgqSxeYGpmIdF8SWh)G0s8(lAzSPdlA8Imz44GW)07U5MLDtAvlXaGfKyt)UvkshNNiV7soYpud8fDcx0XWIsgnu(pfPakZTlApVwy7XlpoCVK7JelRXjwmJXraHz8uuI620CbjF25YfD)W9tOxYyaZjJ2b49qMpMiZiMZFI2ItpQewKV2iBhZbRa2uQwX9bYnMzUhoIA9rmou9ezk)IVuXg0VXG69MmpDcQSoiUnEI9jl2uaU(wZOJFkfNqghp0LerekAmbg5LAYCY9lwadLEXHbAUhZ9V8CU)LOcE4cb0KGdQDFcDfFeDHxQ8jF6Cn6UdakZhLocei(drKVVMcNmPYvTZB(hZRhCZAFmu5nDJLYRywCFJIp9fpXTkgBVSqREw4Mo7XU4m9hsXU3nIYyx9e7yAli)RENAfBpVCf5GF)3vp8V)",
            },
        },
        -- Blizzard Edit Mode layout strings (shown in a copy popup), same keying.
        editMode = {
            p1080 = {
                s64 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 2 2 UIParent -171.8 -4.0 -1 ##$#%#&3(')( 6 1 0 2 2 UIParent -187.7 -90.2 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent 2.0 -56.5 -1 # 8 -1 0 0 0 UIParent 10.6 -1031.9 -1 #&$E%$&` 9 -1 0 4 4 UIParent 0.0 -628.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 0 0 UIParent 1861.3 -187.2 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
                s53 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 1 1 UIParent 808.5 -2.0 -1 ##$#%#&3(')( 6 1 0 2 8 BuffFrame -15.0 -4.0 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 0 0 UIParent 11.6 -1220.9 -1 #&$p%%&/ 9 -1 0 4 4 UIParent 0.0 -625.7 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 0 0 UIParent 2288.0 -223.5 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
            },
            p1440 = {
                s64 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 2 2 UIParent -171.8 -4.0 -1 ##$#%#&3(')( 6 1 0 2 2 UIParent -187.7 -90.2 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 6 6 UIParent 12.6 8.1 -1 #&$=%$&^ 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 5 5 UIParent -11.7 108.2 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 ##$%$&('%(-($)#+$,$-# 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #$$$%#&('((-($)##+$,$-$.-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#-$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #$$$%#&('((#)U$+$,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U#+$ 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U#+$ 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
                s53 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 2 2 UIParent -171.8 -4.0 -1 ##$#%#&3(')( 6 1 0 2 2 UIParent -187.7 -90.2 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 0 0 UIParent 11.6 -1272.9 -1 #&$=%$&^ 9 -1 0 4 4 UIParent 0.0 -638.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 0 0 UIParent 2288.0 -184.8 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
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
                s64 = "!EUI_S33w3TnoY6(xjVSpN95H4fVFr(jFtUZQJJ9yZU7K5fVOLOL4yjsnKujXJx5)(PkuaGaKGYs2oP7EI71AVNyksCPqvF1naup8R1EJAUFvg8)C76flW)Czwtk88Wr1tQYYk(LcBRiR9)16OrzRZVAs6IScR9c82V9v(Jc7yhR9)g(KpNvvNxwu4Up2wttzTLTZO1flkNC37tVVCDd(eRrFjFAZ8ZsBMmh)B7rNC5HxFuADZHPv12UJo64ZUEsz5IPLFPOM1enPvZYAO))4hGVX6M8f5n3)R1XSV)IYVKz8RD5Fn2b3aDqa)VHFkK65fP11xMvxUUAswVwGn1slMmVSQMgTkDoJyvE7T1znFSaPuIg3WaXBuD(0m4no88KKZpR9l)uXBT2lYv9)qcQJd1cRRBkxED412rowXUxh7P1PV12YzpF1Eoy0QfP3NvT79O(kXgMBgOBYEZDuY5xO2vM6jrtP1h2(Bfb0F0LV70FjrRlW20BemO91h1D7AL2pC0zP5fWNSPgggsIw2Dy6r)MQhrWEVaL)lKObxK1Jo)w7OhPP9g9(tgByqIlkFTPk9GjnGq4HRBAkl0A6OxiUe3rR6SW5P)AQDZGmX7E)YwfC0Pw72c8GKUoqedVs3IDSZYw6GyBq4Qd62U2rXJUQbGRY6Yz9OmwdjxPVe6DDiSegCDGDOwZ77TNTkd(My12kichx1Unc4C8S9TVo2vVFTT93T(Y1DV(Or0h1rsC7GJ6Zuzrld4RFZA4zVuaPoDiXFJGSNNLpBEdPnLyMxnpTaiAhwUUyA9dFJnAaf4hmzswbY5fnADDgRthJdgIeJ62gDdUu4Bfhz5g7y7hefSp(4k4XEHET)qi7XZWPk2LbA64pJSIagA3LDFs5yGIXOTgv3clZNSyrw9YSQSF7DIhJgc0vxBTtG6REeFL4S0I0z4c(Gqnp2hkw(RDSvFVFRiVzCv6YSAv8SbFfs9tNxGdgZMnKwKn8ccfcB4vmbYVPxVdt7JrjuTKAtlmeu8g6yMoInqS6zu2WVQeOAtZZowioCRPGoUH2BqiVhJa2Xw2nrdhgF7XxLKqlB(vrzt)r3ww0GyqbJMTO8M0fOb4N81vvz11Fj9E2ygeAxKxKDwjtrt98uOry4IPtNcmyOSBKA)mUkpdHwWvNBL)BBVrFoV(xaSRZaKNMSPJznE98YVC(T3IDadM8MzhSarOS3hhDGSD2HmuryybFE(nKWo03lGHxn75fWI3rLlkRofXNC2hzWUz2LWFyHG0a(d8LNxS4(3vuZwErGn1Vd6H98dW3fi7PRBkrSWvn084DfFoVH9jWGRScaRUKgq(JMGyvSw4di)tcs8ZNuwCvZ9lqs1sGIvvGZJAM3r4CQLm8HYtkYwE)y8RW5jnVT2Z1NAD5RLWyBhtElvNra1jP3KiOqNsdixjWnBmnMOdhYOdS20zuk7Bz)moCBhm)s5668IzJzp72uo3ErbiQpMnAW1PlZMbp(DWmSoPLCWxF8yVcR7fVHkngxoIcC3V97oGOhwSV7q2JKZiIehokRi9MfzttOPYPILurtCQG1G(ZRY)pirMP0XtLJ8Fu((hiDzv1LOYgOxQsZxmEO1gfwuVrLaRZFmhC4nF60SIXdT40H8ZgZZZ(k0TwhDSt8XSb6eq2)O8QjlYyAAtbmPjZztq5aXIM6vWYrc7ZlkRwMUGT(vVkT6UtKeLn0NUJpiCmB(LY4RI0iOmn7vPtZxxx4Ar8g5CPdusz83gG5WOSK7OztMUTZhFyaM(57hGFLg8Jz)3qd(e1bVZad(bGlch1K91M1a8gG9GdPRfuxrFjgVTuktISg6Y4r3SOSC6caY(HUda)rF4KF)KlvNe0xaemGBpRMr9qSJ)zz5sWS1US1y0yMNtyjZtzHLPOSiJbHsVfJg(a3ES95MRX(FjWuUbzmU3PRRsrj8Zvm7eMLud9BTw)bZYjOKG67rdtMOMxFGz5enM(ssK0MwKeDl9qNoRP6D2NeGS6J1pjNdRxnd4bYokDXKZx1Wd(YeyHTzC(IgMjLrJoAE6YvWhpgTk5xYQkzW4)Eg87PfKwGdM(zase4iQyV0z33mFm5r2T5v1nxUU4yGqNWuwozEklmpGTbVpFX9Rafe1n1V5TV5FUEX)3)vEbniugzmOM)96S1zpqnakDWEy9IsyqJEYmQPMpPq4Hf53aZxIVZNMpG(61PloykZAD89IBX2G((GQS0347yUV3yhQm02H((Y1L11PzRHU(ke8RkT(h08oIr1b()Lpgj)fFAhY66LLf3bDDY8Q0fl(HTyZy1Go8(F4Z6GrVRPEroRN30K(LTJXUEJwUYcoD9QmOZb4A)9FGSqjBr2eODplD1kayNb6fnAj9x1p8a3aOwxJyVrmA37xAbprFCT5U1kHnrRk5UtdAbgxvUeSXES4JzM7XEzpMjFG6Mdok5D)(jiwZKPlVcOjSFwvPIhZ0OAxRrhcMQ)g0aY38)MnB0Boo)ZGTWV5I1vRkRZ()HDIWCSkMXnF7xlC8T(ZBsRpN6nL7stEbN02)8nPd8(jCo)YkrlMPTZ9)kYChe)tOeDO1pFR02Ebr)eYF7h8Z4K(NWv6a3F2MZuAvWh(5SRaRs)1S7HHPfzE70LW7DrzDo(jOJsOJX8aUZMG3ZYQRAkUyZYVYD2UkBXfL5fyURo6KpKGUw7pAL2tixJmUtaynVJJfVjFRBOw(T2HEWFKiBvS2mI2wbp9XPEMczdoBx1uyfYwbBM181IW4awcY9d8I9S92xq286s2e9OmzLghxSw9(cp7498HV3Z13YpkyFTHNpo8CSV2omsUkf3L2Xg1ow7ebiEK5Cw(0OawDF)NlfiCu7ExHyESdBxP7Np9DFEhJZBxBNR9IcB5qB7K3g2BsTTDIJLOtSTU2ogA1WRD9L9sGsNyhT9RAFJdSCif8hVrykPEGs7XCk0OyWbvclRH4i3jK1G)RnPtU7O2yKXYLkLpKeaGOjFfpbjRxXYgZPhDCIsMnIOmBWJ9NAqudhvSE5LLFPMqo95VtY88j3vanKmuIrygyVjVy6P0BAm2UYx6YcEu84)9blYNvaT1ISBBKWNXJosBVvr7mk1i6jJJFuNW)Pe(tX0Zt0xIg4TouEoqI07AYwYiFj9ZaaJCNwLG7Fnf82bcLBaL5c(BLK91MeL59bWWjEOmYeIrKFcQDJYCp0PhotMqe9WNNiFHtLuIdLZvxXYep80G(ZYf5t7tf(yHJPOWAlElIeWtie0D)UXSMPV0iJam9qP6kXQlour6qW(Dt7te)tskLrKws5ouSsOMUNyCJa2KpjDX5y61AyX2TnvG)k9PJL0kEY2CO)6eP(6ojJlqUkpUuirfXiYWGrNhGNJoLOO)TxAzzN)wil3JfNleho63eBVODte2mR6lJySuX0WyqMfKnkYBswUpaKU88WstD443sb7wSdBDbAxNHeOnaP89usgA7zvLF548QmMfVkkj7ivpGW7PQWIBPK8qaeKKScBWpa5yxtYXAITQ0t8nLnaWL3USQYu9YksRjloKGrh5EDcUdn)Exb5ad69dl)9JnWtAcnqtirdnyiXXxa0aU3iDy06RZ2mGKjPFh3rGVIPny2gZujg89jXGYtixPC4ycSzB1Z3vgYO0(lGAEDChqEd9H(IfPtYMZ2lE4Q)4NTEEJQZmQM29XHi2aq0G4fCLz(m)5hwTVNYY(5fm9YooJUTeCK4YSLWSJLqC(EUzlGm47JeTg4qjiPM(FyOJdXvlGU(ag19k1TmQU5bHutI7DSRWDUjgKbXkb43Jw)Pq4EEwv0xeuypfR)UdE)nSc0bypuFqYAsNGUl(6aA(IWQ0WOr5lbUUBwK)F(pPvtP9o0xYxj35uHda4QUVr6RxsQEVlauhDLM8NOlLxBVlme(N2ximfRVY3bXCuGLDWjO5bb3sGi63(vyPc4JLWD7SnkdI)ZXToAo201jpb3ocAfd0AyNrRsH5ZY8jNUO8lJhyhNDLua0eqHY2wxdEQZQWPcNB7c84X2ZhZYAHRSnoK)OGhVCDZ53EzAXSSZbPIfP3peSNZ(kEnpwSgTl4upjtA82cXkv7yoCWDTyhZDS2VlK1GU6zqS1aP)5bDPRrXOTt64tAapd6lWPdZ6Pso(OatXG8YagOQct5qb2MP5c35Hc7rs6cAfQjIC1QSSPfE7Vvqxi2o2sTB32HceshJanU5hnBRslb5sv)eAXk0TfrducObQZn5kmHePpX1Y7zNSEAZp(tQV)7ZHwQiYafuMBGDffJlkdu1JZUnROgwTQFCmSTXPR2JqsheSbup0xP9qOyQlqCeWDaaZtAoGXO6piswxcR)OISpJ7CDDz7HyBheHhM351NoVKT56t6gBof2y7ogf0U0r7W33C0X1YPM1ORVEg2Oxpz6lU)L2BhySUvJ9rN3GtOBpQChLR9WJFgEYUfyXpEGMgeRRJlG9fOmamBsdKbvC9JpDlo4Jz942ht6bmkAJXYsbM1iESjyT32tOFau5brxvsgRk662JB3X3ZHqL7cRODYq3eYCetVjUmu)UBplVMtJ64jIoO8g9VFRmYCWWIz2jyZMY9DaHwXetymFrzt9B()8Mlb6pUF3)oBN5waTniS1HkUAAoHPBahRBMr0r)6bRTHWF9CDE2O1Fgr)0bihqdZtbNZexH)qaGdbWQIcQljT7yGgDKWeQMz8VHH129y693bGqdr88PAyQFRHPVHhsSxCGqZMQ21Kxd5595b(PBNqFdGma1rB2JRtRV5cyGLwDw(m2MsNclh)CxIKPZYGb20F3o5ryN2aoYw6zhSAW(jo(ycTTIad)UlVGoEC1j0jFFGtnk7axorE9CepcGTAsaUo55Iuh1wG)gYirSvx84LrYg4g8hHvHfxMLXNF57(NN)HKdEpBBuX)rSHDy76KBZxSa)lp9lYcC5MrwasrI6qsWlGrqPyY9SgkMaMam97odgh1NkCeJgAzlwiGbceYPffzlWMJ8LuC0UeiIbqBbKPpYzceJAucnIdckA1pPpEoumEOz2LMMz45vsQyG0LybWTS)4KLRWJjniTmtCAtLtl5gPy2KPSdHFA19Sew4VpDuqxkWl9yda21HtHJF4EHY)lAFdhhvX8tn1AQH(KUkakC4EXJKqWLcXqySj4AjbP9WAkOyIKjq4fFQ4T(E7RUcFjF78j(B5uepgJqx)E(ZhlxNKh5lEFEfM2nONAdxjRbPltaaGIVVESEk7dnnQVu(ytbcLMNYa7iPdQodFJqfUYYTqcJZhNiEEIc1LD4yPZ9BipBJnPloMFY365CgXuEOrMsprB2pbRhyGXZeZ4HDKxoGFySXo9a(QknvwMv1E0C7mVpuSDo5TYLmSc2EPAvv(sOFOtjjk0ogpdM4MwBvw1Qv0JNdKFmHu65S8uHjszFfvD9UB)qPacKoi1yRXWI07DbsLnHsCedFNl5MO(HsgDJhFuPXKb9i8bTdzTexnnVM9x4odLozuktUlsbtyblyXJqQ2D3IV3MbFIhnfHQNNTmRtSdBNkYq3k7o5yaa4X36JKHcI44Vbm)oGnKYoq1jMwm6GI2oNM0qNPyjIJnxVm2LFsPlDqKG8BBozbmnabuC1KUEj8g9bgcUe9lYAaJh3GQhvowyHyI6Aopm0lllBMJ6ohp4fuqzR3f9jkQ3Bl9rMERT)ZDJ9kTOSpd3Wzs2KTWsL9B4krW0b(2KAfvXZdfcwkptiST1OwT8SxAixY91ChXEFc5n0awL6Gr(KEzYKB0yqFtwadSBdlUbima)ldSOzAliwlAL1(g8oUAnyr)LzKzUyZWxfYkMZoc5GPS3cwGF5asSpSjud1xNz0BH)W4rwJMNwp)3txSg8eXAe5is2K3DC9dSRRh2o9gjUhQa6FjN)wfYH763b85s8Ov5R(fDXD2K(Q8LRwKnUlMrs3GRrKgK(TNDKVTJBGRvGTLvVqT543h0qEFb5n6yWBrgnbgpNpSO7wVRWCThU7yx2oFsMUaZsJe5Kwz7Mejn2It5KsjT40nqlU0yti51Hj)vkb)MRxwzz3eyNSJp0uhl)vvZboDJ3nlK2sBZCJjBPMq3OHbS6zbo47gJGq63fKLXmlgMTg8QkpT4DvLf3UUIssq0OYYjkPaZtisogDIlTACFKTypl3qBqJKxKDymJYaK7)qrpLaRT)MTYqar6RwSNIjdkRvONxIzpPoB82OpY9PDSniTq2uqne0r088FbatyrRiPpZ4HC(5oMFsMbFw6xzHsyOBHgnD39Wjpve1qJqFdO2zFHSizBiy8XQQYM3nRa4DUinVqmxs6QGZUJgNaEeB0(AIDQVIhY)xUJRKoh7(6y6pfpuORbTIkDrZ8EwllJ73JyS8FMgfBY2tfz7avRC7Q4wyzrpdA7loOlKjGMS7DJ3iShnylf80KwTgEFqSbdNnJCPXEpWTjup7vnggEvjEt2G9KmG0STdMSXx3SsdcYDsR4gTNw3cdJMEkKMTFMwnAVvwnkD)q6F)t1IXWrZYkYQsx8qVyjW2hgI1a8kuQQCcTp3FeNpKrEbVYI(gB(v2KTKI(NX0pQGkOVU0L0PeekdkX2YTlMEucuZFkDXqQhjZ)byAstsfOtGUoiDWRneTNyG)hJCud7cqBVyU2f2d0ZbwaTzVyIe(KDyS3sY2mtKhKa)nFvZnPeTMTHmrY1lwn)sU(TD1HCZ9OnzgY)fo8E4gJQ9n)RmwCG1h4UGQyHYB8MCo0oWYl2nYj0HRf3221Dp4V5)WUCy5CuUQ7UOkdVfKoB9IMCke44VLSUQ4DGEEW83RUlFvYabum0NZvCBzfEDyDf7U)ESI4tWGyNUJUEs6kKlA65a5irz)2VIRmMVyXCCmuBBc5YxTuUY(0xLKrqMU37(LSuwu0hWvxLp8sjRIz0zB0bq9TWSeDqDuruq(xChyJbFe0N9)40LPZYodVzQy3WuJMYUZvJXKzaoAUaVdQKcLoCfyvz3I4vxIr8ZquYCWuvEtwfzWatMem5UtdQU3PSnT3PuLpcjF9UPS8ULyq(qNgH2fm7QiE)nCTRHNu7PSDwon(T0cxQsaeTbwMIPyQ2qR5C5HlgJ16VKdQdz(BJxBAvVhSSv4sl8NNJ4on33tGo0x4ZuRzWrwH75756e6g74ZcLotsYniCp0YERy3qFr28KX7IbEPMYo6rkQhdzpa5uExXXRlMLj2SJywDa2zU3eEkV2LP58OeIpdtqEkFpnvd4Pz4ub)H2HUJR9E2asGtSxSJDmFO7y5fSNNJd4YMFGdBS7WOkyVCoMWmbCZy5axLGrPuuFirklzmhY9)opN4PvIhlUN4IKpuE5J4f7jVCGDIJKNCF8E28BQb0NjVd0gEWdCi1rlt)kAewHVq7k5FLRf37h54vHs3pBKhF(F8b2kJYywovuvifAW8ahB5kvxAiLqrIhnsAjYJkj1YN7OZuFyQIU0L4D1SGVwWF9nXdUspTXGufOnSoR8Z0b3OMVLg0LXPtxawkhaKz97Qt5UsbKQQYsVdZ2UPHJyk)itrKDFA1HZg(2iuClegQKwp6SvvZtc6uwV)4DvG4vvpGg8Cd(libH3UjTdlnyHb4lqQQYxtf2cBFR930Xhq9IFLUBYm6(GdlB66ko4RgxKxuKn9QSf3owSpvyUE16JO2g21IaZLRzhWtBpQL3Deih0tQeLeXZ5FKJRpGFytHPJjSA4XZ6)yYOHkumLt17SXyiOB6OX7X0)D1xsxH3OI5tycCR47QajAgDJk4e54fAfkaIdjqU4a7yBpB6kKJBiHfNqmzD1vz1S6jITAMgC4xY)lyAhy(WcV6XNHBHcKV7HUT12oMIDD2Zb(Vyll3ybN(qJcBp)N5OikApl8)cdCIDJ9vhfWyZloWcn2BZJIOOnoi(gdOazhnTyQGpVPtSgQA7dmBmOB)yqitGJhq5PtIAOjI51Yg94Y5UYr528USgwxct39LEEKYrro)2B)yXBDPHntsRphENd9k8L6gSpSZC6XT1VlcncB719HQKmMrpA0w1bUy7lCRYUZMVcB8sm)b5orbpqzG(KwBps022yNmDwgzY2ETNqg1RZgL6ucleJ(bXSBVJOqlBBPBkV1Jh5XTob9MRxj0TfIF3lie(v6Xt9Edjy0LzRANd(XdDVYOCSdhocQIIrI8(3X32R9IhjaACW(smS6U(SarTTJszfozt0zNGig8L4kDzN2seNuWUaEzBikE)4f5BkdMp9lcg2Siq062GHI26xRnWKioIWGTbdhJCI21wxCJ9464JTEODiObtEF9ehBTtx7rF8IwQrO1t8ApYE0)aVduX9b7AHT8E870hD2yB0w(NexSEPDHys4Ie6mjUbwmTlUw(aP5rjV0M67Bk1Ab1M3P9Ybk0FxxP8v5MLTeEDybsiw2(o(r8mSSnJpwtkUTFCdCzns7K8jS6dRB)Egy8YISt(AEJyW6fzc)jk6PE1AjlGuePW30AMuIl01kiomyxU8Iat7xTUEE20U6ZyHXGUK2oKv6ZiOCMHLZbnnlqTnkzfq6CxGvRZDXHUDVLXHXAm3cDQJpS1mypEYtypNROKzsIdLBxvfpDhVooTdRE)ML(gxxSTNv6TNXmrztR6tiaaP7FVoTktwRdWY9a3rmmZyhaU1q1(MA5w6K5EWyDYBxsamAvjbpn6ol1w0E6fBx6YW7gX1xfSeht3JZubrHCTwEEcNHMdubEquFjZukMvvOPcNLoPQKVH8S53d9kRSewvX6Lmsczpey1YmTqKmPC5nPnibs7KEAkQOM2g80Gzjoq6y4Ld90oNHg5sI2UHBMPZlO4UYNV3mu8tLgZDgfyQNZNCxY8QY1ZMtJRByMPCr60PYtmnTxhVmT4o51QW2E8bevTgUrFCJv7Ez)3FcOFz)BAtn1E8Js6KbSa(6)d0N2YrZomaw7zZ59r2HnCtvW9GLrouh(HAD8we5Xm1sDbn1pzWRBi5XgVFzeWryZpGMxmynDqNUOLVDn2lTZ3)fkcmJhoEXeX4k9A3Glnu7Wk7l2ZGI4ImEdhLOo3VjwpwI9QODlaYnEo(og32V2rQs3ku8qEeDrbyE9LIwiKIKpUlA(IXCNPDG6Z3MO)Ome3E5HE5uBo83)hOh5vyLE17cvXaTnkICPBBMYThBbZ3rZ8DKodfx4jRE0mDgTELcNKcO9GhO2bpuyW6BNbKuOLwFPdcBIz3cgcy2mHQpqPry5HrBgaaEaDj6ZGXA(e8Cu41rtMj1npLv5(uNEAm24veLU62UGUEGdqUowXrHbycp2v(2hd)DZYsdRLz416Gr4ZQOOkPoXmIQAeOChUif3S0JMUWNiAZa6WvKGnUe1xL9aC7diBSnhCrZMrTJAOnB0ZZrVSz7khuxRc7s7uBi0nZQBndhT7wA1)ubJHUJJdBYaxZkJhs17aMqyqJ84)K0iBg)VNXIM0XAY8QnynMjJ3mTFx2jd9nxUZgubQzDG9vGQebPHp5MI0b4z947sQDv)P5LLH5wBtJH6joJYt(qt7DdEsxPxYWAT9)PuRTt0FMkQ)4Fbvu)2GnFJ88JrvTyD5hH25Dx9Z3hn3og0C)w3xav37OULHuP3t7sFtcCg2AN(3LqSSh(9vJT5AU6lI66hrVGg8VjtH6OA(THBNU5p9Dx38aXD4zQEEml3FhMo7rCSTpHnztyJBWqqVrxxN(zw421wm0b2IBBztlGw7)m14oeLOntUdRN3OI3bKoFv77pq3KT(X6M8)nR89)gCnEiVA7zlTznbgY4ZZ3JyLlQ)FK(d)IfH6bST4Nj)E3rZ26RLzOn2Z2R7D8tu37a4eMx9Eg6r9rpxTTEndRVMH1xZW6Rzy91mS(Agw3ygwB3rKVMFYxZp5R5N818t(A(jFn)K)WYpzNTn(Rr(7V0kG(zmaF7Kh6)Tr1sFxc2X47zcY(POvWC4)gkXygduHrTCgSM9VJ5pRN(Hb34HFxuB0ZcKV3Po7zhHVOrNLdt6xZPMXd(1p30J2J60R7QNx3vpVUREEDx98u3vp2B)U65hJJU)nAB949F)BRhTZQ8R6AEvxt8R6A(ZrxJRjDn(VQR5NeDnr)mSfsBV(yE9iESJhXJWxt85Rj(81eF(AIpFnXNVM4ZFOj(S9(u7v)dF1)WOx9p81yr(9)eg(J4iq83iVdJ)VFVdBVlq)zER1e(Qlo)vCp3e(QBn)D)q19NM3mFhpwDbVES62PnDdXxiUZp5vSaAsRC9JECAtQOYMrL)B2VGSfhYDdx0e6AnCz33SQddR9cHNrxW4IVP3TlBC7TCA3lawF5xPJI0oEel5yFePDjMVUkflF(xMTeOxu1YjEuvA(uwr1)bzPL48M5WVEwETSKcwljmsTlSBW8BGxFnvF(QV7EQ4Mwvw8FWQpeYf28f2)42Yk8LaIpwJK8hnhlbojFtIw8HYcHG3u(M)b1ISEj2t1urryvv2TaVo8caP6oE5r)AyrIQBVybu8486vlsV)SYPzWazjR6jq1nMI7U)WfPtU7FwwWlJNQZj2YNO1llNQ34QZyNrFHk)441t)kO5z)rvEt21Pt)xS5)0S0PlUpHJIdCMZiWHBxKUmdK(NToJkPav5RwTG(5iwbG421v031u3uLFxgJIjkqKFjlDvzX1zftGf3gQjZsRAaUKptnIZOf86as66zyfx9AKMWuNKZiUnu58iDj0T3Ep9rX0GVgi90VIKQRVbPvunJdj2S1SVG14C(Qz5uCXZXtuisMKNUOwDrmHxLi5e1)Gn4pHg7Qux2H(mf4lRFyy2mSAJSiVgqQHX81S3PMkjKLliwVYL0GFA2TxtJa6aHDtwDt5xU(lz3xbJSsQcv6ncl6czv31(QytDlr7W63g0(1iFc1OaApG7aSWlz0RPzFU8ACiZ(R67HL4YgGrWm3CcbF3GZRMwbpMzAtj2vwDT7EoQQJfvhgBPeXJMTlWkmLw8U5eLQe8mXvASPQYKhv0EWb)VHFPO(5JL0i(9JaWaxbmWx1a)skWMF2jh)UF7mCO)vTYjzPs1rIZGO1K8QoKSvB6FAgNSUQUS6GMM0jZhlQUqi8oUACYxbUQ6AadFRlEqQLNiNUfw0ofZY36ZXM1xXA)zZ1hwNWW2cvWUuVgi2dfq6JMN2WURPNq)Jy2)GxdNOlUAYyORG)pwHXO1vBsxrnxif6MOrxFnSWFdZYE3r5txKnoDA2XzaBNOGVkRSp844Gf6OZathe1ejQwe(7L5unWc8TH6yH3wA16lMPFaypahWGpqUStf1Pv(hknM6HUFIsTpK1FfUYvRJkxDV4wrLb6K1GfFJAqPifccLgxYwBP95KIsbnayKZkMXT6KgOxQJ8qUp1ucyvxOxJzCJCyfAa9lA(yp7opDhkGe4ICNE5TbwuIuSJdTT8L14b4F7SNRhw5hcTJ3L(Xb8nc4paOuKlJxbTol9RS6qCHTf3aCKwOwavAl(wA1EmqXpO(kJPTTlJgv614L6KVzSehYm()MwR54bpMVoA8iJgzy4tO2O0i(qSPeO2O5CvLlwWpV(SsjhZHZZly14QXC9DRap(lskxrrTGvzxyEQ9(YzjP3K0JLtYyFO4WhG6ma8(LR41x4Gr)pVB0)ZzVHHaED208gKi9bunbAJYsWWkI9A4A(h2HJr30NYlNUidIOkXhhTxyGVRVLRNDupzRwJyvRQnogQQn)wrEZyevVMsaVOG)kEeWUaafSAqQpvqo5MYG)ZgHd9G(0YAsH8QSMef3NP))uHOK(NFt2suHk9MMBy4iT1ooBrvB(W2stiRYtGRHWpCWnGUHBoSBrZZ22n0X3lgewcSIKXQjmYZv8loTXTr)LPIbLSSk9rEbk5gWOyQa(WD0agShXCy8iGQMv0O5JNyyjz7L)OdFcXx9C941jj(uxZYF2Jv8gg8rO8lzvQXHaRHKGxKlXHABX)ZMVJGzV(fzvOO7h3uHxMC9LfJhXjmzcG0jut3kt6q)aYCHFr16vGwX0P3Rt)DARUcT0zxrbveBaQE1XydEC30uhFFumV1w(fBhaevYQ3i8S8Py5zsXfPO2sHLKGNW8qAGVTJfx(HYzORsHElYHB0vNP4NeXtSTaCj5zaPlYm0MBEp8R94MCzCA4OefN)eVk5j4x(KmojklxYtg1Y0VECgY52EVwXk0)SsdnvK9WqXaAFPRXJvGMxWdWMUfAVenlMWLq56HURQ9M5Y73esK4OfzPfKjgUKCfwGkzdqp28smcKbBqkMDbYll6OwcGS4pZ411cDKk3)NeC)m9)WymrGg12NYXQHO)G(VO0CTdM2kT7reNdfvGudCMSycD7TDJMc9zT0XmE80KqcD4iySksok2OkPTA27JAfxTcNxIvo57ID1LumSWsIiTGPoTyRX8CjmLX4CAv5xAMxtvHqY2eA8Yd8PfwHsDffozLHKcGTTOglQWh)(YjP6jYbCwaO5xWuXWzAt0Gg1yaq35ibgTh314EGlGMhNRxE3LCvIc(gVX(yp2o9IJd6Wh6is20l4mnKv2TtvRwTdI5QOqYP3Zs8ymKlNLwDNOMeZ3PFQTGQUfPa2hqhWKAk5lK8wTfhBc6(jBXkrzE(j1xt2AB3vzcXPlWAsKD9N4BiEpmaFD4MDBvOQS4eRu9c1Grgo()w81tfvXdh8FjxmVUTgc2VVIy3ycrFuShfAxcA1r44mWADIQSf1eGHuDFxkUVrsWfQotl7Np1rBS2X0n1KvndTGOuaijCcgcW8vs7EPArCcfxmTQf5PYmy3CJ0sLaUffKwfwPE6q9a2UNvqR6pX)Eg)F)nnfjm3bCg5mvQiJX7RuCGLak)kM1m4)tjg6mPLUDERTfTMw4WntGZDRv7H1StOV9yHQ6Y6Q71rYUJYrj9WlXpQ9TvxFLzqS9rhSiFM6jawXitjcT(6ZLYuaRiWjdnVWvzKol9mNPlDCBIxyWP00hy)XijUkBApCXpj2wzKTPQsVj9mbrk1qVChfkHAd2TzpvPbb9P27fkfZAnMibhxbRdka9hZZaGUuwX)pzGKnsE)FfmMs63ZsT)Sfym)mIfzvTn6QdchaIy48B0M9jI6XdsTIqRnxO9I0QM7PXzBnKBBiNs2zTYPA9YYsMBu8eSsSXcXbWAJSfyTowm)7SQAkjmUTMlYlxZKCGtFzeDv3wuWdjlia7gmX6FOiVlDSNuX1W2LFfNECcgyjPnLKoeQIwHB3AKjJDK(6GKHovqo342TaqGBxpauT0R1OJwnrmUzKbN0gzyuR5xYwKEZ2Kv3Ae)0mbCZ3unDtFM4B3wl8S5)BCMe47Z1WGrMoJM)NLolFshgqWfiYYp2N5r18FCCqrlGTS9GP1lU1c7G2oDoNi7V7bcyi)wWmqXMECJ(LgZP90pjQr9CBwyHESn3PJ3g9tgDJzZAH6X6TPasSrhB6eScVG93fNB6yx4g8vXHeoujokHb0JCA9cUBf60aZ(Z0b(EiVCI0xV04R6QHKRxsh2gJ2vZ8ngpIUdF5AcZ0c1FzSbGAd27oKw6y9jJMuMbRb2A4AdoMnEGOl1XD(bSrqkqyE9UBS2umSjrs4UqDQoUxSXc2xYuzqQBiVcvcxIJvFWVJwdZHwnaTWMbUbD2YcCKovDmIWN(afaf5cVoq)2ge0iru6ybN(DftZb)PlBDRyRrN2ySoDTEjJ1jRA()eJ15EIZpcDqs(Zi0NM81si))DpQMgJy54DnwJI916UeRr7OocCCxH2GuC0whIY4UmWk4CAYJUVyrVu3icNqL18TpULpDtd7gItNEYW9lVYg5Fg0SIKNv4qnz)WUhr0)sga0nAhrpBdWppf4T0znTd2zv6Mci6tnIOJF(reDa9NoSmrOGHZhepTaOAk8cDcqrOknSBaMIAJYJ4FRwFUTKjA5p34S2nEQ(kZjDNI39qT2XroXcshJQJOKDtRJjLSK1MSTbHnG8oPdFEBa4aVtuStPFvFV3Uos69BVaDAmWXBWcnFEOh1Hxfo7EthNEJugNswyC3ASAJzRAWWm70Xuj9OOBo6uk2P7B9OXL2uas3uWogkFmMcrlk14fO8FHcIMPhpR)J)2Jg)qGZGX3jP6kSEM8pzNJR9WbOQxGp1qJzKSOb9TZXlEVwdjJgo6)W8VJyXh5zEvpY)Yzl53KC0YdY7ZicHMlhcgDXZDprc4WmXXdnQUrfYHwmF8IrCVFgc6f8XbZnWqrmRdvJBKZwM3mJNqeJ5n47qW(7669ogQ)TpeD9d8VQUqX(vZzWq)BkrUBrCphk2fQPcBWOX)9k()BolBDYmVPQ)W3VG)TXGs9sNkHDmxxGaEhbnjZUsso3y6NEjsRGXyWT58Y0ZDNUoNVnzyWQNpt4mapcpmLHDIWYjlx1C)MjSQgxs2Wm0opPFFRp2ucbM7M2kbgtdXqje)rJr3Wj6wpVdkb9BJjCO7(RzlsW93A3yFpSZbYsliuE7AqO(RtCME0uAVLXBYBW4nr7xSxM4n9K3QCJ)tyRYfrziTy9YDoewBiuv(Dcv1BD3Y9tNN5asXo6rSZz02epk3N6UPBWGpzWa)QDXU)TEh49md)u0g2VdVirGsBp5L83MnFhj5VPyp1XtWwf6D3AEHw7)ch9PH2pEjBF0NgkmtMZMNwCMER7oTv9ECdI3UOh5)If(i3FyBtp99T04N2w0teYDdXHzipBmA)sY2VH(CFSaNy0)KT0yyZP)PxKQ2LTAXqgDjnc8)p79K2uBKSK)v8FaZ2Dx9P4tag5H4zdSG8m2VyIWHqQb6fr38KeEg)i4)(Mh1DFijMz8B8UEIjOTKQUoYkR8oZAvTldMpw)6OO(9n5K)0m8GVUt9kahWlPA5SfL7E425zfSjV0aom0Oc4Njl21BCh(hL5wN2oY1diJB5V5wMFiUpZpmKq6t2G1h(dNxfDzUcdVHoSxrxkC5yzIqzXL1ZuLI59zxI(TzxxXsXFOGNRdFsmKUU)hYag9zomBlU0Prc610dIT00d(2YQhJo0LngBBKLEd6L)emHWGUFydgsOdpk0RXN7ZucBkoz7PM1SZbRypwz2pM4ebDeHIbDeHIAL7B7l7w2W1Xca5ixkL1P3uyh2DWeUL2ZLnHgh)mNbhXaqCR0KWk6AoCrjNF)ST7sm2RlXyKofPoTzeucuW1GbSZ7yZg)rE2ktlXNyLOSOgB2fDJXW4K9cZtK)FX(9Zt7LgR8Tc)MHnsD)QmT1cT4yRKizDp2OTTPt7HazpoMSna9cDS16rqPlXpB92Vv60ypfP62OikRY3re10tkMSt0U6x81(clhFEHw(bUBcudKBG9qUP3uJTBVl6ThZDs)gFOdn38LDYNjth22YBqFRcJWZbiUc3kdG6MvRu(cjrWi5LOC7STEFImwXCSYXGwFzsVR7CBImalSYPwbXxqHXVaPzgBalYJLtdRSBEaQgdyeN)trVOBCN)W0lI3lTiuKKhefd)JFq84VVep6MHXHkeGwNv3bYgEYDueUNgJGcf2TG4rFug89bBp042ksiSZYpqwqH6SuKrFXBLvRgznTtPprDdluJX6xQMCGSGkywL2D3fYydQszvjQQNBxjrSQ5mp3Qcj8dYm)GmZpiZ0MmJaqkIn)3FxiZKzlFX5nvRKLShYEn5P(y77LfqvMlUoP0vErffmK0DErrzp2L254BeBCQvv3)WIYd7jG760I1QItckkgOa1D21Fz8L74GBAVNv3ktF3rECSZM)okxUwFtFPDLN5W7jBbAtayx8EBMnaxvdQ(M4w3(ndFO1CALR9X2rAh9532HcAQn4tx2bDoGQxk3Rop1paZZ(O(yz3eJTpgo7LG5SnYNSgm64Oan3O2KR6YVZBrEmzd08DuqhLUOUn8rhMOAsFPYQT0Fb57jkscsdZIYJhkzk6refhASzTZISHtoWEy80w30w2FEG0YCBZFIbCGCxYd5ryQ9kk2NsD3nz7LRAqxK3Pr87l7cB5p9oda0HnzBxUbOLWt)Lwxb2E5)6lrs7ucWoC(G(qE3gOFNkgpD49M(kXg9vvb2jrj7jyZZh10OUwR3lEyp(mqSraNACypBtWV3OvyZ1uGw16QEcGHHSsFhEdSRmW9fN8xDKmodw9r6267BD(v0TJY8coaoU9AwF(oyw82A8Vl6FAZ1(Q)s1)SDKw)3o9mBls53w1jvN9V67b1j7woT(ik3Mlzp5p0lvpYbKOSB6Z9RuNVwLcxhNPHmyCDOQKQovptUeXkRkSQcq8wxYzBzNBO7afv3ZpUkWcoBOqSNq)F7YOiK25skfHCCut6GDORSJ0yCLhMdKyDMueyiVyVqNvWoudE9nj3lCMc9ebADxZHPr6ke9U0BgRgqBqYEij9LUoTkkbdahF9FaaPDG4RgLOiUml)G37pa04zlp3(I2jAxVBrPXGv)AQ42gLbB4139ttxDWn3SS5m5fPX7BUclt6JDpQrm6TYq1KwzajhlMUgsbOw8VESCfqq4kImHZnFYSzhTS5bvv2ocl82y5(DXx)jfbdvCNldDrcQwnBcmPPzmNEy0CusZqr5g1fIJNHx)LiciuPcXi(6t42ovJWCZgj95UAgD65hnKEhYBDOBBwTUAHTN2mHbEHvw3ifwVYjQN2QaEsUJ8o4qQIHQ6YNd1CYcCAn5BLKqXwzgKWQ8hLRUQvAhd)Bk8dYC2g2gXTTr96gdZhbdVRRQNxEFfFtLqxatXgfl2wJhjSKKeyC7eDiyqdbaYjv3BXu36wYHzFF5Ig3k2VomiXFPvqkRiCt3fqxADbpC1nwxonye4mD2DsvdKnlq29w76sdQyrbbKVRA9vn)o9oFs9sfs5G7DTKBpP1L3FX((Z4nB7rq6lKQYSY)B8SoIb(lvRV9SR(Fkj1G5mQGe3agj7Wk0kThSNesjaRveR8(EcU63(Oyn(oQ)6BkVE6JliQrsBgRXFzX5Zv5AOMs9BN(qDKjxwGw(HA9r0QRSoxhBcuNydwACIY2KZ2U7JQuYv(L1yK5wvU6SZoYeJxtmW)vCgyjVpUusZQ0jvEjw5cDTtnK2wldRWh4T3HDq06GJBHxyfIYoQBMWFdVuDYoo1mzsZdBgeumQbWqv0ZDkdMZMPJq9Oy)9k8CRvI5kpG4ZIjt2IoWT6PeNuOuDZ(QTIf0NUxto)OjvR5lFfuYo5sLcZzJLiKkSty9iGMCJW2HsGxfD67SkG48(MGu3D3ikqJUFK3DVxHEErPmG96oe3A1DuKLNgKeUDUAgnevDmXVbMA33a77QHsOQ1gQZwFV7C9tU3ckwu1(OYMirJQUh1YyAnjrnXiaJ3nv0iAU1auMbz1eRJpEIjyLCLo7LFYL4(8hwDAJngkxwKvMu4DnZUR5X1hSc4)(BZr96w2iVZfSOB7KN9kooM9clRiduEorTiBjvGFoBgzpgAZjQjDYl4h(56W9KAV5rhzZ4Kzo7rBd)1zs7SyDzIL5EsWezVWCT8rqPXfMWG0YAswxUprUEqKAArUPGKLyLODrXI991yIQ7J5weUnsKLxyz(uIF5M55zo)DElwukIUQVmYab0wQY2ip2I14LjHrfTl4isP0aAV9XApKXJ0xSnfTPT1YghmUxPzSlsnS5IeMXpHbajUNe9pzBj7SwJazQLAjuTBIcrxtu4gM(ynfaCk1xESIjxzTkm3fJUJhM2CCXCXhOV5D2qhHFCYVQWoRHDY7Nm3cH04EiwzKA1r(lpXj9N1FQFhilZRAaDZJFzUnR4p5CfvjPYy2QnbESrCgzvMXHW42qTy50LLhVOADPz(i5TAlYV7fd6FcvfjBk)aMLSSrXQmEDfNPF46W2GBeCyRRnj(rDGkTY08dT4QMOjcEwT(w5nz0TGMN4DnKuebjV8WwSo3L8jgqZAP4SmsUt85mlv(1sqRe6IZbJxSpAtTk15yMX0TzoFVr9LOqprq9yHAKLWXFKHo0(03nWklFA2Fm5tSn2IZPMcVzW2CTD7ivGTBEaYB3s3tTL3teu(LBbf7XDgoRHADHEUxObpn0QcBO0CTu1rtCcFo(Qa(HYf(K(7L0KZs0raSa1X6lVTQCXCR9y5XaMmMevH9VjlgmtQ1ofqcSMw8rugs1(WsFxxRY4fW2IeroB2YBsuuIaaM648DESCub2BRAx4p7c1LLdrPwrm9aTdmSf0XX1ZKWl2fPMmBMeVP5ryYpwNS7Ekoflhnd9W09Bf7hs1r1(IdzTBCyn9rhPWTn3IJ)jv8(77Y7o07Y7UWry0p5QUai5RVnAAjpsIK8OJaE6ceekjQ3DOTtd7QkYzD9DP3LClVhKwsBejaK4zMn8fLh8HhSY4gJaojUlha9XNfSb6Np6(Q6QDrquzsIQtsoGKnzwuTjs8I1bMFUlsR8cnmjzeLTKxpDw5VEW85NvV6xTmW7VEF58QP)k10F1CtrU3KjMm)8GflSkTIokq4uSfixL(4If4CyClmfhApDiPdFL6LBQSeBxAC3MvXhRZ9P7RqOc3VRe)MeJS(U31GP4PR9fhs3cKQGwrplEVgwVgKeUGVhL2EzB4Hfzmm72P8FNr4YgJ7lJqfUIuzXME36qH2(VBvutaGSYPl3bWSLb8u4qVoYiZej(U7fDVJlemwHlZS1eMywh5jQQXVn5CGyGMhmd18CYGOpe5UthzF9WJvMwXttqjpzNqfTThXJCSdMEWYTLQi3qwjlnK1VfOVHehn2AoX45nLZtuxQLk0KTI7TM7pBDfRqaHyf5SbvWKJ7X2kgiJN5I81xtBc6iPCETpB12jagB)0A29PUuV2qvskVK0RboHmQpIOkgfOGOXwQKuBBSVlwsXQirLQ1fuFSW3dc)XRSxcg5)KA(I90CqvK123x03(Sw7znRAt1liuQ0Jj4CqcU(KodZAFwrvSuTun1(AzWG39HvLOxiTkbzoWUp6Ekd5aqYQFE56vJ3CvCLTSQRzvIL4(wtnlVu4OnTz0z9VSya)E6oxNqiO7U41O9I5(PODmfLkLCxRRXy8oID17MEv5Ij66qo1BhUSC6D01)VwEI3uofqt42H3aRlpPgi18ozyvWwLGgF9Dz7eJYi8iD(mCBfq1E3bhE87ykrkHsqhIi9VgwaIMpDbSnPK1mlXuN0nIXGxdSQGWcNBNut2lFSbfSLZiZ7I)ktchisONmaIli(hOaB37JQ)LXazbwGe2uqwlBRy0dMyhD2hoDYNp)4lqxQXNtXxfeFQAP)aA5DwVZy5MjRp)EBlSyETc2RXL2EzD1dlQwpMmeNh3oJLlD0ZjXfenDjE3wVEksqDS52LEz5xQk)TXw3R6YtNrMJoY6zIy06BbY332SyULgtQcI)JRMa)kTrlpw6p8uS)ep60Zo9ycbu)7RS6Uyg)OnCsy2qlm7OcHKJ(umotb5xLL6Jlo5T)epNniO8vsUkY5(yDry8EjPP4fiDqUGD86mz5vkcJfo8cRwa)V2)DKmYxFD1VxQUvXWnf4O)V1AtjPfzezVKPX2Do7f7C2do4vm6dN(MJV4ZhEWfi)CGWpEQlv6PfLCdaMiYdBohlMWEoFJElpr8(QflQwvcc)oFfxjLugakoYN(OKWasxA2DwEFo1S)(BnQD3IrtrWGZTx4v2QTCjcyiTGsgfMgocqtkEDyWRdJZEQooiA)6CygduqH9s8wVQyFS6cuWYUKKgmkm(P6urm81rXydtdPMiunjjNAsCa8(zajN6WqQRsOwhhKOAxbm2qxffIDvuo2vPyZJJLnjsWnjoe)AaxGAc28Ia8VI8CvFLnkS4P6SySxIsWHlpeAsuqm(QjkzVG1h1JHIuysNblR6OcSf5b0uSqjmfp02qMHNdWRqWg7xjteibm1HzcfiWQXXwnEtq0aykeJq0yCudtW)gNkOLRekq7MrpvhLbqHKOS9RtlYWgtnliwd4tPnOe4GfSxddBAskn240ni3gubndeBc(EA6frJAACMCSnZUqy2H)ygTydYXwikO97iKhDnap3hMzrj4OflNoWycu0QZlsSH6rwqLn9c8s2(f2I1Uar6G5wb(NmATd0si80clepO3OVUG2gtWtgHzf46lsJMqiE275PrydcPnWuARQqKtaJa7PCI1RiYWPbd8dXbjHNsXOaD1WiSpUxblM4C8xJee4pKqdO4scAto0gboOjyNLtN3cP9PGWuQjGulWSlu0nsgmH49BR51WB80Ip37msocUsPTDc6NNtVxEG(nq4Qd4Iwse0pVGoBLeBHxfn8YsD0pFBa80EVZEf1FbzfyxhsebiaFrMn6O90Dy8b5jWKnSLQWVsH2LdZGcIauct0IEhruOnaZf)QxQLuBXZ1jeIpE6guXMgxrS9MSD)nmHq5mf60iCSYIPvBCmT(PvxAUnSku1ZWgIaxYfHekdr8llMq(ermkB6(9sckkZgdlq2PPrBGeiX9AZeSyMEBbVoeZkbzQW4O4pwaOY1reEoSJvypnJDyJUf8(gc9xT1B3PdTVYmaT59SjoHedOmnjHSyIJwmbUcSiwICvZeeJoNds2eDtWblpfMszezPiAZ0SnsyDzoyD4wcnVebeHccBkPiZE94medraupPCaxdXEtTPzpedsOrncP2WysyGiKztbJHNWK(sTpty)gdFExsZlFtesLOWi9dCytXdV5ecMGWNqueRPSWNEBF89uaLq7dCdXvxVgDyNbi5WwBcrVJwP4zgaAkSFd7DQnsBHWFSHJWjjODzfWFeH46ipJiiMzZMpDl2Hi8mHdtpCbNsK4tj2bz5SGz2czHI3I0xOURGoNhNthscYSp(6GbhrKdqUnaiHeDm1rmghcid17szZ245ij(Ka7oect4tH0YjHWTfchw5cNjWqVHKVa0ZefMSm6upndIJJDf4kJ4Ip85x5ow0MjLWeLDi0ne15A8bSAOdrbuJIz5ifoSyDw691yjrZ8bKSxcyc3a7p1coFBfcXE(TjqoFAzdhsq5)2FdIlRiGyt5oJwrH5evYCjnjKPzGfNnXMG4PEmRSzWi7JOboXiHYjBIyJSDrBqpc5MXgxDQdQoseIRZmcWgqRIuI)CSd5In2ovp7WRyt02jg4202hItEgTRmi1ntHNLTDPDPYLTgI0HIueSPSQ0wzXlL15K2QOlRU3TXaxVOCRIjBYWuWiySDzHXsmuGphX(r9dpmR5Emw9rRGW(ryLXlRAJKSAcBDqBJexvxD)0hi7uDV(FNtMb(9tRw0tDk1T2nHMdB(8M6dxxBLjiruN8wmMhG1a7G3M7RRE8(XnlQA(KmcWGru6(bzoA(LoR90OJhAMD3LkBgkJGpkEIMoBnA4s9WxOkJN1Ahf8e7kDPVi5g6eJGpwFZYMhFOC(HpUET8fY1P7NmXNaKX9sdbzgef5XICzAqb0xs3dO0aC8tJ2Pe)RZcRpAtnU2qV6F940LCUiFnGu((MVGRrzjLfbUhTC61yCaDgUxOlEYhHaQjKtHBEOS(9vZw28(Y6hpd(NZNd4EuyAZPgk0jy5I(nvxFD1ShxS(RJ9RKwDv4UkDUsnWHdwaqxngdoa8J8Un9lkhx9A5LoaoK)ZgytGHZt6P2Glg95ztFa9F38ZaaJz6ozjhNo87lVT9wxFi8T4oiB5X(UlRC2)LXnNCfincVaOSYxP03Seo)9ZyUBC8VVE50tQVUHTmUfsmJoQ8brWO)DtDPgua7gt)s5CCX2vjotGqkoyaDqQfJw2SE66s5rZX9uTOztVEMzUmrFM7FcZcvT0WzxWuFIbuIflWzMSkg3aZSZxwodo71uRVeqKZp9wOtHw7a1La19WKQe97kbNuyOIrW36x2AWz3bePcE3FChJJ2z7KROuDjxRMyp1IhzQQlz3pz2MiuxYrTlKvDe6inpuJF2NaKbyWLGKLZL53IEsY(ry99itINz(twKopC6nR4Rt6RMEdU5CwDj8D)Y0L1WweJQi)LlMwphiq)Vl56QC16Y7xu(LYfFaGqgxcY3potVXky1PE4iKS74MA3SBb(bzQfXJREapcWDUPz5xVerIEIGdhbG6hVhpZUICfibxOmsc27py(xGfiCq7vacWd0Qu)78SdzBKm6GL33S0)1dgn52Yxr)0x77vbuKFPC6dWC4v)xVAYYQ67kxV6f1rIrNaGUxDz56x92YPVSjt2i8vF1X13IeCX92ximH5Mt7plE8(6v6Sxh(QvN7Y4OisLnVHfXY7UiGhXuKRmZOa6QdpBYKZE)7oE8ed3ISrto7C8Ry4OeFcWov7YSxc1yuEOjraPAADohXwL3uiAeheR5RaNgbWMDH63UOefk6KAgRIP(aFnY850MlVT6616U58Q66Y5QMYU2e79Qve7b5uSQKDdMK2fZ0GYpVxH7MSqjjsm3jgNuRQ1otV5Ghx3CjF6juv0SVOC6nW8KNIrrkidhtc6bMzBWSREBZI5kMhCM4WIoDZYPZl1fa9j6K35efmfDC7nYQxcE8egMRiFhVy6dRuX1k(dWljHE06srBGQInv18pnP6b9VuFNFFnwDigFhAYcKoUBScaDjv65xQUeWndRCNah2XQV)uacF4xjh2He1vmaxUSSE2xjjgE6z1U7pxT6XPl4V80trTXcqRpIMBod1glkHuQTg(AuTQOuq5b8zmOCAo9uaO1W3NfJkhffNKHYKhH(Zmb)mBnzudQCu5gQ)ONbKZNWNOPsOplKpJ4oM6W0abAYz49iRAsptLZpycaDBOS5u3cpr1bGPlP6h0QiYecHIaA0YtIeD90Q3PNPSY3QNII00y(jnlXNKbzteIu6zuMGFIMGcbhO2Vy7YY4N5YpJAJrpL9tonTdkiWg)85NEgnJuEcbjssYJPDIIGCsZqywgtggiohHeGQO50NfzIbEITlIgdShKpX(fAqkzxPyubl67dyZpergjPa0Ehv3mfny7U(xQ3sSEMgGrCI)tCfZR6K0ucXseLNXqgqfF8zAmHNedcBhk)CoJGrqw47JPvBwwyb)KxLikR8PG(E2(X4NdKptzipVJLsr22tKLlyJAckKtASMLIAUgbs9Z22gaBO5yliBtNfhKlKpjJYjYYs511)OnJL))227)WLh93DKdEzef)ZIkII46wtnrse2LQslIYp7l4iZgafEGzRWSPXpZSWuFUlX6uYj2swnpXq7uomSntqUXV6TnnZPpE(YMRHwJQWJFuY1)vidzyeEF1QzLaRZ6sq2cpXkmsC0U4JGQ8s3y2s1kwVc)gN8uHf37X7VYliolSVZB1xsi8f5qhfyiDsJ8x4nLB8iulLVEz5IRhxTedK067wDWvnFP0KV46FuNSlRLzP(BkNo3QoHq9RCOnrafAyBGUxwqsEEKPmD438NTGMokZfBDDzzQSEQcdXVSC6dMIBB0OpCoj6kOIQjZ9cDsGL(dauqW5PCnLeuAsfKIzJA4qcwg(zCKzrcMNOkTsXHQREwovKgVS5EkappE(nLSIHYu1bJc1v6vImVc4Taq2mzuNDXzV7yz(94wYduL3VZlxEbm9sAFnOkZMpgm((P)oL2s89zBm1Dyax(4sLg(5UvreNRFF3l5L3p9MQzpzcYXyDrGlZSNk0UrsxcghdyjNFPm9oVxlQ8kw5YZV4KJVCYN)PZE3NE6jT1wTkeErJQMxlt0iSQS7D2iB08DjRydXKiCUx2aIrghqiyfA194CGizmWxgOXbS)j)Meeqm)ef6cEZ8TmBlZGEM39SSwGefa)vyluMIVO1wBJAaFP2KOzyS1BiLiKTxrFrgxB2qdplICdMIxwvbAwxrVo6J1VwA7G5(jnuUja7StOOXMPMoq6Bplu3EwRrvgJPDspBbMyba24(OX4QW)euYLIGYNz1CV8No49hC6NVaWRo7IdMCYzNoaMvX3imRIS4)Ve2JxmR(Dm6JXgj9JKeg8ncljnKI4OOaqdaGKdwR8lc(bvN)(t1bK29G3DWBo50nXjlm8BeQuIiHuxb0Bie1BiiiG8DCeOYBH4h0I(ULwu03ieiuQCkcda8i0p7Xcuf2Fqm6V)eJYg9Ml(WjVzlLa6BfbjHil9h0D(ULUZ3kYoaZjms3Oq2jjjlJIromCjacqfjIFin03feGKQ1)MtU8Oto)DNC6XdqasLm5o7l9Iv1FrpVnwLhmPtSMEQR4UynDUu778WoIf5TFmm(thOjMJoySTNqXozrmzVFm09eIimQ2KM0GTLXZ7kYvpig9Tx0pYxNhzSrbDop295LN5H44F(S)XXx85ZbUChFXpVrUCIDL(1)B7DTTBBCde9lkbAVVRYtk2wkfXoviAtB8tbBSxRiuzzdTYnUTW)7LdNHCgYLRSsrRrcQ9Bws7fsoCMdjN5C(NgMlpnboKOKIKyRKg9C8UF8WzN(KzWKRc0PmyYlsGt2jjlRcQMhfCj92pMOM4(mU7Fec7z9jn5dZo7K3v)O(KYEQwkN6Uc7RDs(Os4WgtYROs66zFt)q6Bk)jZWbYvza9aE43PqfiPqtOqId5ZWZ(K(U3Nu24Z(5392pD2pTO(xpzYVCY73hq80))aexFM7)NbepQkhRLR8sQg(YTe8ApdPOKWws1F3H72OEfWHvREzbncCH6LIfMG5BBVCL(AMkOvQ(KVkREJIJI2WM9VUXLA1Ds(b3t5ElO4ih9L2l(nbb9Mlt)IHN6WS)JG26fKAuXiJSv1OE75ujGOsiDVW01RUfz5kmzj0vFY62zWZV7VQ1)nD6dIlGV)rf0j6RFBDoL)sQdI6Coeg5cpOEnr9kmuJXj6NABcgMZQMedmZN37O)RCykvhI2DJnnMpa)sEYoyCKR4yzEU2Ifz5XnBrEhmBKmtg6jIcb0dI(9cww5Cx3mhlAHSJKOBqN1C)PTBwQzB4xzijsiHTjLI5qyQvNbnpD7ZkIneDBMQlkN3CZ2v)5nB21SEQJVnMi8gnUfkIbwntXgjQqKBafTt79JuPn3mdQkoktfUoUinJlPSqjPdK5g5QF1OQYrjWvvquiK(ztt5Who8wZjaJrlNahUpOzQ0BBCA4LuYcnKiDKRzPPMESJCFnu7QvqwMhNeACrN1me1RscR361std1GJE638TRu947upgDTLm1phxE96wbTQgXeZybZPxrzenzXgBZ7pUviA4o2IP6ke5u18hK8sRTMGHAkvJ7cNywvICIIVqdDxJgW6jodA3BCYaj(E9n3SEhMB5gpvoMMXQqf3FX67USv9RVSDd6GdsYjoZ61KN4bceunS3PFHvJvFvffbi8B1yfwHJDHnuq1f1JVUrnOGShCeH9moAImMrSPmQSmUVrWa)QT(odK)EwPFLdg5nzllebeA4uyESIsWlRS20rXr19OtT4aMXVauzozYNnpsHmSa2Jcpv8R80JknL0vMBkL0opNQzYXqEUOwtNjkzFzFiwqDlytHmnNCD3gOOXyVeVijk(LzJu)LRwnbPgy3V5fLLLA1imljQSkk5BR2hLHN431yBhQbycra6qLDGwTyLUbt4MZR5YskZL6VrWS58DeALyDCONGGuxU5rv7LNMqE)PhRTzpO)KeFnZYXzHvtnKiOECjJEKwUFFFlaXLZ0UAH7kmRnx11201AnvkI8rE)YKcZ(dOhGT4SQTDjqsHEAt3odsVR2tew136dces6r6Z4kwRuGOlKxGGIIBcntV3kHz4nEDQ8WK71KdP)jdKeEffEhhsgSparLJBvoYgqqid2Bkds2zXyTd8ZLjCznv3p9e7HOCd61zdS)jGSzPBUgOIyXqQESHgqs9Wxo1SSlYAMRMSkThmk7Wthxp5Dq)9BozYPN8E1KKJNC2Kzgbn9wmrBjFLQoV17L7(dl0fvozCRNfah0GxQH5coQ5wt(Y2m8C5u2R4quuFHhf1NrrN7l90dKe3rciz5vcw7Mq1bFzQb8PeVupV0ApwFW3VCkjnOffqXNBLj2SyujrttRksl)MKmujSzoyrjVeuLDbyJoz6Br7QRBvJPeCctkkt238USmsfszftNWgtvx59MAPFEPVwfpS8qKjd0lsuChmHhD32owZ8Yz6CihvpBJbha4YdPhsUTx1UPtZFc6L)iGTDyRHslbeTTOU1afF)rQU3TntfgOEffWqQQV1l8JhijYdMTtdtNw6Uuk9UohrV72goh7hr5ypj6bOuk4PEk(5g)HO5jIQqqD3Gs6EpuUHrhGqwrv4q3S(Yao30(AfshFihkNB0hIp3pMo761ddjIKLxPBApSLbvYK2R8UpDxFZn7(Ib5kfFGTV8csIO6vHZGa3iKDRhSGfCcExguYnfwhocbd78)q0jq16aCQrH(nGZPn(RRx5rykgcL)uqSi5crwgOqmKesq7rLeq(Nuvb6)5ld85gLI5W3VgF4824sAWwQVsfdhgzqv2yK9xddFY4YfoUB)xVvrURSB(wF9HVpEeR1Pa(YxvgX17vy6ZKlVtcsuwoqEt2ECiaMDrybQwi1d6y7JoeW(9kRPnnRjga3wir0Css9M59hXwlyfKIC7r)l7B3CQivsvT0(PH3vOdyxyEruS)gXqI458E8(DixJvzXv2s0QYSn16EU(RV62qYBwQylLIfQkB)pEz)p(bVOcotgwC31xFZM5TQfZGv)FSPiMmwv8EoD(auotaFXwHOZUz2o14w)1oCUCdaGUvJltd5TGoJb)WyzvjwPNi0O)2kobicCxvRvSvEK7oqEDTTcOvzK4CTbq(4pPUNaB5JsQS6bHJG8golLge7g4)hBUybH(xtHf8AymHByClW4(2v)EZoTcR1jxj0X4UrIx0kN1CIYJa)dm7wb9LMOPQPv4JyBZMLIfBvs2AQ3OhCbCtAQyU8tGaLDILmhaejvtC4oSX7D6vIUO0mzb5XRWfmYwip7YmPRAy(BT)Mu94UNC(5yBkzmkpKgmRhKqf6T4YpkFdp2UjLDtfyyMf(WpjsVHqAt1szPZslXWstL4D)OeVl1LqL8xU195C(C7yDkVC8NVEXkG)3XQb8Y(dAEZLrhMVgu9jTjIYcq)pBkdDmJx2pYeFEIr7)eL9U6ZFKZnoYC(DMJZcpsYoQsnt)MIC5CmNczDp28oDaAgwN1h5dujQCbVGdviQhE4V)",
                s53 = "!EUI_S33wZTnYU6(xjVSpxEiU49lYpfFrjPM4yVS1mtY6fx0s0sCzjsTiPsIhx5)(bOr3n7MSjLuStYmN4PQ9Eftr2xqd8b0aOB8WVv5nQ((1PW)ZTBwUe)ZvP1jWZdhvnTmnn)n52wrwh(BvrJs3KD10KLP5wh47k(VdBE1)m3o2X6WVIp5tPLvzf554V7nAwcRnTDgTjFzX07ExY9fBQXNyn6ZzZQxCws90f4FBp60lp66JtQQpkPSY2D0XNC21tlkwoR4Z5vSMOoPCEAn9)h)a8n2uNTmR((FRkM99xu85uJFTl)RXo4gOdc4)n8tHupVmPQ6Y0QInLtt70cSPws(0ffLvpy(ByKUIBVTkT(d5iDt0fQdnKMuLnlTYD0KZVO5l(yoJ8PpP6Vf7ob5nBWOJoFYKZpRtl74qFXMQ6IvxhETDKJvS71XEADYlJ8pawATJTITdJdIv7ZGrRxMCVYuWuF9sRdSSSSJCTT89cIc95ZkL12bMvgOQBHGj(wTg12FNOv(JU8TV(nt60MEJGrPV(WeNvUbbo2arluR5dhDwswo8fd1U2UhehhhAzh6g56hj7f3U9ITJJvOLRTZw6Lo0Jx6EqGJBCGJNLJRNBu6lT8js0fPDO7V0o07Gix498T8J8JhUV8g9UthRpHOfwyb7l1LjVAAniYF0M66ICTUjY)BHdkYv9)WoYD06wRXUhy5Bh6hgbek2mvPF6LxFhyDDBAwSJveD)gKgnZZYw5D6V52j6pJHcwSbzmVyh2IrliU(7GgSVTHA0c0Dasql04T1WXJUQgGttBZxc0(dSdc8TCJTcC2FbTxgEGDyGBCSJRvSFOqgqNJW76qGJi46a7qTo33d7BX)foiRB3LwdSToUQDBeWi6z7BFnaHOpPT93V(Y19G2DL4JAjLVBiHD5V4ls4RFZg4z7ko1(bH7yDasO9IS46kiLflsZMVOMSmGySxVijhiHhvSjFw1dFLn2aJsE10PP5ixz0OnvPSoDmoyicoQNE0n4cJVvCeWr5y7hefCi(4s4XEHEn)qi7XZXjo2LbA2RCgzzem0Ul9(jfJb6hJsB00byr)0LltRwLwM(7Vv8y0OM263RCcuF1J5RlNLKNmhx(7fhBBFylJPgAe1aAAR(s)EEw94YKvPvc9HTEboKpRnivzd8ccvqd8kMuLm0R3IvEBuevRdhICqyZd0XmnrdqS6yOz)VQeqBO5zlRE7V1uquhO96fiCBeqb(YaJG(r72(QJeOz4xfLn9hDBrEnIifmA(YIBswIBM40VSUmTQ6Zj3Zy)bH2Lz5PNvWucvTibAegkzYSzaJfk7gP2pJlZsrOfCv5w5)22B0NYQEdGDDgG8uNoBmRXRwu85ZV9wSdyGM3m)vlrek7dXrhiBNEet7imSGpp7gsyh67LWWRI98CGKDCXYIYxJ4tohImw3m)seAfXtb8h4lppF59VnVITSIaBQF3r4EXcW3fi7jBQlqSW11084T5FkRM9jWGROeaRUKgq(JMIyvSw494Q2eK4NnTi)Q67xIKQvafRmhNhvSD8HZPgYW7lonpD19JXVcNN0826axFQ1LV2eg76yANFvPeq9KKBMiOqVMgqUsGB2yAmrhoIrhyTPZOe23Y(zC42myEtXMQS85Jzp72eoxEEoWKoMnAW1PltNdp(TWmSAsd5GV(4XEfw3lEdvAmUCefqB0L(Uxr0dl23De7rYzerIdhLMNCZY0ztOPYRflPIM41cwd6pVk7VqImtPJNkh5)Q4Dpq6YkRkkP9qNXzgqgJX9TgPWQ6nQaEZ)CbSz(SzZsZh33IupmQUGQ4Va)T1XN4eFc79McWAhNvoDzktTBcamnDbB2khnweDOewBMW(88IYvjlzZGQ1jL3DQKc1E9N1mjmMkMRheda3XVkC8yfQltnFzYSSnv5Uwh2L681E4umky5oA(0z768XhgtjF6EJmVgh8Jz)NoRrZG3PNbFxkt4O60VuVbG5amiC0CTGWk6wXqTHizs0fyxltYwoMzf1nllkMTeGSztFgsaYr61MxwNfXF07p9po9sQfaAgW9Nwr8Otr2VZLMr2Ivh960ImcFzrcZ9t5f5Pmyv6TyZwHPBcB1y)Veal3ingN8SnLjOu)5kBjbMXud97nwestS)DrXkWw7d7orno5W5gBYqIO206KOlPh60MkPn))Ga0vFC(r54FZ65aBq6XjlNE(6Aob82SYQ6l3KFsbt9cqyMcl51JZwwZm6mA0XlswTgAUXO9kVjTSGXC9hPWVNKtIZVA2NaqtGxPK9sNDF9IXKYZPlsixyf3G28Ix(IxvMM8cFhYkxLX1d438F3KUj9b6ZrXd2dRwwadzCxoJQR4tjeFyz2nWSL4(8PXoO9EtYYxnJz7o(f2JEx2Y7xdkRQQRGE)FVz5)7)twU5EFWUuzWTR9omZz9EYYL3VT((PEMd4pVTUAzgRNNSOegd)G64q2KEvr(DBPNFYj3rSEge3x9dNAhp6YnfvvjPBGU(kuDxzs1pIPnJlFilzzoGVADk05aST)HpqwSKUmDk0UNLSEnaWNtGvRO)Q6Hh4ge1Sfj2BeJ2b)5gGZsoqjU3xjKjALjF71G2GXLfRaBUhl(yM5FSpZJzciOG6vhp5T)XPiYY0zRUcOjSFwv5IhZuPkxRrhbMU)c0GYx8)jD(OxCs2NaBJFXfBkxxuL()f7eH5zLmJD(6VL74B9ZBsRpN6mLBttEcN02)6nPd8(fCo)0kr3mxlZ)7lZDq8VGs0Hw)6TsB7fe9li)TFWVIt6FbxPdC)vBotECaF4NsVcSk93sVhgMwK5TZwbV3ffvz4NGMpJBmM74D2e8(8xAhzJXKY3p02jkM8e66ISCmCwhF67NG7N2E0xejiGAWJIgvMU8cT3LSDN7j5y0tYW7ETxuOO7CCIfHaZlmGcEd04HwEMBWUdhMv9IyBHTPvVJzR(hKrJmgtr2GXUjmDE2SXO3O651FjpoMf3Ra)aVypBVdfKqpB577yhQmCKb604mJ1Q3N77gsXeo2lYXJyUKdpFC45yFTDyKCfJpkWiWfbs5IrDCK8XXwr7b5SzfRvKovPgoE(bwUbUBNAyfihhu2g9yPgHJAYRMh)cUEk0Wzk3rza3qpCU576554g52BV5yj6nBRRTJDCcdV21xkee4lddCONTuiWomuYhbDWoVc(vo4ZrKdI8gHHV6bkujlipOIosuX7Tg85Cl3Cd7XToz6Dh34hnw8xPyOmbarQZwZdQYM1Si486JpzIs0qIOOHW9nOQVwdhLVz1LfFUIWu95VZKfztVlhAiPRgJWO2Etw(SxtVPrxalFPlzVe2)Vc6)GdLWQXJowjFYIXeDRoBAYYZXqUuZ8VxNaUeI0WjyA2PazQ7YqfFtkMUEIXIWFHV0HIvcs0EBD6kg5Cs3Oiy2FViWolZ1u9kRC(IZY4dvcwruFHYjaNmhnNh7eAj83OgP5xLR76UEFIsGDIOjdF5I7sBqxBXYSzSCkCDYuuzlVHOXUu9J3OLP3wlcgp250KNhojyq8hgJ5Mor4dIWpnVS4ZNKvMoLV(zhqXeIVyHdVoXnkI3utkKUVwsopIRvwlErTwq)qo3P)ILGLzZBMyCcjpIDo0FDQujFhFxhi5SgxieYIylOqZRZ3Xd1NIJ3)6tT4TZ)ieV7W9ZLXdh97ImyYOuJMqIMJ)nVe)iKKBGoK6T6NNXmxRrWats2DXG0L17xSQfF)ElJ3kAmUC2NUs2gaumls3lGHkK(wLNBJmOO3SLS9G4GBrwUv057tNcjjRWg8dqo21KCSMyRk9eFtzdaC52)GeR1vA1JWrlzFDIUdnhFBoT3hCJtSubWOuHrmbnrfnmH(ekFcWe4BDzqgvdQ4r(OMp1euGJ7iy)Mj1yeltvPkgsFI2S(6I17iwqViNDL3Fk04BcsmMTf8lwMmnDbl1(qoGXdHLSVwa0bIZKsB3TdyOBKvF4fCLz(m3a0VAFpLv6ZZz6LDCgDBbSLJltxbZewm05PUZoazWn1rRboscsQP)hg64qC9sORFfJsELAEOQqUCyCpHuRI5u3vyoGIUNqq4HnjP1LnuRhjcul0oYAkwxDh8QDTyM79KA2CkBfmlUzz2F9xjLZmTucukmu8ZtByaA4u0aDSgv95S1YCTkSdggmpLutvMD9eoPRAjP292ipTuvAAlmTP6Az8rFaFAFHWsSossgrzoMrRqqiZ9mx8oI(TFdwGaExjQ2EBxIZHg3DLj8)9gcQZQ1hfs7RtGj0QSPVEzXNhe)HN5AxjLahBqtGs6X3A3iA0pP(1UisoDqKc1)wsenG(LIn1NF7Lj5ZtphWLwMWXwheJkE0yX61(Gt9nzsJ3oiMQAhZr9VJADZDSmHW33e3K4Sb0Hhh0vpGlihn2pnPR6UywvpMvQHOyYeAvIKaqsd2YG9nnawoKJXzQWWmyuylYK2WxHAInxTonDwU3H7ei2acyMHWmk)BmJknB)sdb5s1Dp0aUnGjuabrDIkx0jSkDQGXGOYJ8Gn)KBP((VldAP8idKtzGg2xyoUaoSiFs6TP5vWsxLjqoJPK7WaBnhxfvCnn119UJ2lLkvKDbhaShamt4IEsdcmgaGErYAtc9hLN(jmb41fS7JBTxaEGiNv96ffSJ7Xe5yZA01xphF61tNPHq1wwRzTIYt4xC8jv6EI7jF)L27gySUvJDrNvfYBVIODW)2D85(WtEYbP15i7fi(Yb39PjTJFdiZg1k1l6OkVJoM(2SS8BYJ1FyiRkhawY4(BhefDhqO7fPTjDLTvrA1n90e66ljXrvG)EHNngTGUAAIy6orcF1BV9SSktAGmA15KVja5EDowFgv2V(yJMTSZO1AgUiq1ChDrrD1l(F9IlbcmMU8)aCF2oaV1R)ZA2ZC71Q(WSmetadatpI9GUZyAd4oTEpttM2DBB3C9TaPzI5ZVpC02XTtXnE9Pq4jcRZK8RrOUHHU2BN593FWoUcDJPvW(BqQUU0oWEpYnBB2M0oyP9PREFnl1iqNFJP2VOFx)rzXW1jv3CbmWskplBolx2j3YXp(M4NFwkWfm7pSNSfgPbK53Xn0bRgSFIJnoHYgjWWV7YYPtzx1e6403Zb3LDUnNkVFrIhb4E1ta5d5XRuhXwG9gYYwl2QlEW0iPc8CbGORWIlZK4ZV8T)7ZF)Kx9ow2xX)rSHDyz4XTzlxI)LxqG(LhqerwasXe1HKiMtO)FYNEpRHIjtWaO97odghvVwSLlAOLUCPWCNaHeAEE6sS5Q0ozyc8WaOTaYeX53mQrztHpffT6h1hphjgp0m7stZm8yoj1SW0KGzQc9hNUAnEkRbPL5caE50IJY4Gh3o2z5pP8EwWj8pKorPReGLESba7gcctbrrMaf5e5EOHt1Qy(PgAnvFFs3Oa5oYeSY1JptOtjkS)cX4zSjGBj1P5aGkiFcpBqGhFm)L(EhQUCFjpLaf)TC(INgsORFh)5JLlAs3kW7ZRWyWb9uJFmzniDbfaOvpM0zsBPqkSmKhsP5Pm)jK0b1DgFZCPhEKR9cXnot9eXZNOqDzh4w6SehYd9yDYYt4NEUoolG4qpYihQNOn7gT1xzGl0eN5rTeEEf)aEJD6R4RQ0uzvAzZX9T18(irkHYBLlzahSCTADz2kOFOBdlucEmEEoXeCBDA5610JxaKFmQu6bV81c3DN(fup2BV99fc8q6WzJTgdysV3fWw2eKXXmWEUy8e1puYO3ZbdMRlnOdHpOziRyOjO)iRI9xy2LsNUkLj3fjGzTGvT05Aw56CX3ByKO4rZqC7fPROJIFJqFZur6hxz3jhdaAp(wFGStqOdEafaTqEinFGEumgzKj2nZPP10rtwc)yh2a)WZxpQ))Os)7GWcz3wF6syobsR4slDVv4n69mSDjUyuFr0CaLsQSVWQYuvgaU54RkkQxGAvh37nGqrZ2p6sHuVGGEAGPKMv2LDR)4kBYGyPE)bUKfmDQXnPHrv48iHyLYZeIA7mMvdh7LgcHCxL4rS3NWDdnGuPoyKpPLInPDKbDTEbmmTjqbgaWa0VuW4MznqynyvwhAytYLBal7VmL2Yj2m8vH08fSJ(oyD7TGX4x2J86ddHzO(6mZNZ97hnYA0IKQf)rYYnW2NSgrBijD6BpP6b2fael3WrI7rkq(xYzOvbC4wV)k(CjE06S1VzaHDgf4QSvRxMoUn8XK25fkrNqI5b2r(2oUbUwb2wwoT37PJFxid51rK3OtGTqYiqWG78(fC35SfZ1U)UJDh(8rzadmlAs0wAzUDAJQXJ8AoDvslE9a0Iln2esgFyYFLAILsQOv4bmb1j74Jm1XYFv1YGxp4v)cP402mR5KDuPOBu)OxDSmh2thJGqQ6fKLXmJhMVb2Tvws(BllYVDtjf8GOrfftvIqONq(CmU5UKYXDH5I9SCXCE3YlYomMrzaY9FQOLsa8AVdrb0GsXoQLmO3wHEEjgvLQ0XFp1gztHKtqcrJ0FdaQW8EXKU8HhXzLBzekzm8zjFH5DH(UFB0uA3bV81cNiAecSh1phkedjlebRowxwu)255aBZfjz5I5YK2k6SBP5Hh8F9VM4K6QaI2smFVSKUh7U6A6ofpsOZbTLkzz9Io2mlDe4wmz(NPPXMSavrSoq1w32kWfwy0XS2Usc6YxcuP2hwSgRsd6rMZe2V02t7MZ2KC2zkpjgWwAZiyA86Tf7nAWQblUk0JBKbBa(MmP0K19AMuQBDWUBk5GwuRJqA1RmT9J0gs7DZgsdQjFmwrgoAEAEAzYYh64Dbw2QiwfW7MPYIPuAWVLDGi9fdEHi9v2SSOoDf5CqJPvRccHoXTnbuXhvg0LTJzwMUFdudnnD9tQ7OZ)fyHs9Ksq)qk)Ea7)26jgwsqFjvZUM1oiMRPH9G2j3flDUyco(K5yS3sY8mxexg2vn3axODtlqJARjlLC9IvD4URFtxDe3QpknYqUWW(Zdj05338FszUjwFG7c6Sf6WTTCoi0oWYl2nYj0HFm4SXdCi838FypohJGUWMluVlktXBsPZ2SSoJ8qo(Bt2uM)wqNpyf8v3LTEsp(Bm0NZvCBrjE1EDf72sxfgnWQ)qGF90K1ix0SZbYXeL0XFnxXmFXITzYqT8fYLVAPCXaQVkjDWmD769M0eMt27bZs5dVuYQyoVNSXnfQNtZs0b1rfrb5FXDG9g8rqx2)tswLmp9m82TcxXDgnBfD9vH8jZswIxtwsHshUYSY0BruRlrFaAWVzoy8mVjTKmEGjtcwE3QbvJ2LTPODPkFWH)VPO4UvOB)WnscTlycwEm)klYSOJ9OfZyjCon(T0CGQIlfTbwM8zym4ql7C5oqg9(6BYavIS9GJxgBLVdmWvOAe(ZZrCN677iqZVfZVHDYU5ssrwHh4756e6g74hkosW2UbHhGg4t395FvZdV2e4LA48OhPODlK9aKt5T5NSjFEQiriXG(aSZ8nv4P8AxMKX9Bi(mm25j8uEQcWtzjjm(dndDhx7dSbKaNyVyh7y(q3XYl4aphhyNB(b0n6TdJQG9Y5yC1eWnJLdCvcgfJr9HePYKXCitpEEYaLukECZnpN4HpiU2HDIJKxRjEXEY7da8288RQU4NjVd0gUdfCi1rRs(cAnuUVq7kTnlxR2zHA4Hgdt5jN)NVNTMOmABnjAVs12ibhB5kvBAifVrIhnsApIP0rStCJFT09Nkm1hLOOlDfEJql4Rf8xFv8GR0dPmivbAdRsl(eDEoQOK)PLmoD4dWIGbGmRFJGktBcqQQmn5oms8MgoIP8walq29zLhnV)73qX9AyOsu)OJEvfpgPZy9(27QaXRQE(n4Ho8nibH3UtAgwAWc9XDauvLVMkji2(who0Xlq96LLUXZmzrlm7WGTRR4GVACrwEE6SRsxERmjwyBdRz)IAP1SfbMlxZEfpQ(OwE3rG0qhPsuseldcroU(a(HTDK8oc3WJN39XKrdLOykNQ3kJajOB6W07X0)D1NtwJ3kJztzcyR5jDGenZfVMmSS9D8JcLOz2uPJqA9GfF2pDt5vPvSYUITAahCCPZu0sMkb2MyHx9KZWCRHNuN6T1UoqC9fk16RRT98FKDDueRNTcdCIDPiMUBDDu0G9mD)tICBMwRuGF7FFGuMm8EMje0vOmidjGPdOaZjbf0KG8A4s2UySRCuUlVlRH1fG6CzeOFUA4GeWE()q(lDPHntqQldCRJ8k8L62J3)E109oRFBayev2R9dvjzmBA0OTQdCrYlCRsUzZxHnEdO)GmpuWZsgOUOX0IjAPm2PZMNswKDGTm5FvVdCukRk0LXrK4(kj0kMDDQ05(kHU7pC9KzZqOFuVEzKDt0lVArcAUlzcDID6)Qfj2YA4MmG3KE2YR)LycNG((ihX0WjAVU(xcgDz66gcsOS9db7YI6De3nojdm4D2xQTDaB6eA74576muEqCAo7M7LLsucsuKNWe4M6Tb)Q8zNVuCmxIC(w99mJkiUcFCDCKSsbrklHY7gPyF7W96cr6dx89BfeeC)x4TOkMoSBe2Thy7jxi9hQtC8LVONVDVDIEHLHXReAjx(cd1UxLejTh2bUn3Mo(bdmlKvTHT38TMbs5(aqU3D4Ly)TZORo4TP62LBySTJTZwave3FqDNXps2hyb(psblAwME6xYQfZapjIsqCdxAuZ8YXzVWzKfolI(eg8iP40nx16nvlsN1wXhZDg0va3rSIghH5ZmWCbOsAjQwsjsbsZjdS8K2qgh62((l)Gi3yUL6uhFuJ5WE8aQWEoxJkZ2fhkuVQAOApEDCAgwD(nl9SpvKB0k92JyMOKZ4(uC9bs3)DtszQSYkGfxc(gYWOL9ky7nuL2PsM5NSTjmwN82MeaJwvsW3gDNfUlk1FX2LUQ9UrCXxblXX0Tenv2vOTylpTHZr7gkHDsuDjZMlM5xOnfNLmTSGNQE28B4ELvwQIsrF)dQvxlU5nwIz3QBsQrsKIpumD4e69iib2mPML)oWwvHbwRB(i2Z6CSmMp09VppJnuUb(BYnzZx3H80nLr7T5u(PlZME3KfLfBMVGOD3WulErYSzYZEnLCKqlFh)Yyy3p7RgUd(JWpMXiYnx1S7MBomktAhmmfMxTZprdln7CbaZsoZpYp0C1yy0TQo8joF53R56ClGmYqHvFN2fG2XwqS9Lt79sksEcG6wZgCe7vaWZZ7Rqs0IEPfnEnEoTRfGluKFg3VBKjsZv6fjcxAO2AVh(IKlu4UKX9wpuADvJSL95fmQKYKaK15C8DmMDW2rQI6NQEYri38IYY8sAfTmiL92(g78fJ5wt6a1NVlUesziU71yJobABb83)f0JS65sBVl6mAZADPcT8irU2T9HRafSfAxVhGwjddbvBquA)RVi9D41GL7wWEs5zA5MoeTtmVVI(aYnt06IwUNar9qi7rlJ(myS2goEmkd3bfspn6s6O2yWByQwkf2oE8(WdVnW4HfTgqvuVR1bJWNvsUMsDIzeI1iQ5ECnnz8UprkqQzNZ3i4JjZJ2QCUjC)E427r2yxov3gnFAFvxB2YNhJsAZ2C2RIxf2LMPwFOBM19AgoA)bB7EKIr))XG2nBRMzDZ9PjUh7jmOGE8pjf0MX)7yhPPcmLjBTgW0mtwYzkNy2RTcyUwR1RcuZ6a7QavXJu9FCpfbsWZIdrmuYuTN6pnVS0p36qh2J(M27h8KUsVj9R12)xsT2o8WgHbTk0)NPs7p83qL2Vmy4RYNFmQTnTg9JqR9(Rw67JgDhdA0FP7tGkDtOW9PpVJQLU2d40VPoDVlIyXF8hU66NW9tVf9cAW)MmfQLQ5xgUB6M)43DDZ7TRcEuQThZIf4rjZ3YgE7sWNmeo5agi6n66QKpXCrV2IKoixCtlBAHDiNVUtAI7Js0eM4(1)BuHCpcUpRv(N0wPT(XUv6Fvuk))pSv6(2fChBVnR5Wq0JE87Gw5QS8FKkK7XCKFL2N8EQ4UN9b69RUUhzHKkiIQKup7h3)2P8X0A0ZAF(NR2NFA(V97O(NGN1)SN6F8r9p2wpNlnpNlnpNlnpNlnpNlnpNlnFZ5stZPx45mr55DW8CMO8CMO8CMO8CMO8dltu0o3ppNvfpNvfQzvr8ZzvXp)SQW1uwv4)3VSQWE3ZQI)57fThvAvyzkTkI(1nTkIgDwgmRFoXkmEAI)1ME0CSyF24KNno55u(85u(8zJt(XNZNE)6ACsRBEJNt2X)XOp67NtzdhDn7wYJDf4Cr2xsxktQ8)jOoYmsW)0DwB3yU9pUSnPh7eg6qjysvuxvV9OeYKs2VtjzYGbb9jYjSBt9Z(RSX8L3Srn3F)Y2K(URT29ngo(BCJH9WpUx4h78M8cFogOphd0NJb6ZXa95yG(Cmq)Hgd0M7GZN9X4Z(yu1hJrp7JXN9X43HJv()0peBp9Eym(x5tvEZnm9Z3gm76TbdHFiUUt5fTbIHr5Mx9KK6ervwJQj6SFbLRoIBWPOj0vi7YUaEvxVToieEgDjSl(MoxSUXnxWRTV7B9LFLooCZ4rq7X(is7IEFtzYrBU92ltxbmMubdkEuzs2m8PSOetvxJZRxa)6zzvYkSyLKWivwZUL3VbE9nu5kS6U7PA(Azr(FHfGjKDO(ZS)XTfL4lbeFSmr5pAbwfGM8vjK67lYfixZ4HVgvkVzf2tvuDHyDz6Tasj8caP6oEnJ)AyrIkNXy9K8KSQ1ltU)SIzPWazfRasqLoN87U)OLjtV7FxKZlOPQZj2YNO1lkMP34QZyNrFMQj74v4)AO5z)rzwD61jZ(pS5)S0KzlVFcxpiabmNqxVDzYQua(C(MuQSluMTE9s6NJy1aJB3usFxDvDz2DPmkMOEz(50K1f5xNMpfwCRPMmnPSg4s(e1ioJwYlfkjBMJ1E2RrActHCgJ4wtv0KKvq3E790hftd(kG0t)ksQU(gKwrLBqKyZwZ(mw435RMfZWfphprTyzAwYYk1fXj8IMjNO(NSb)P0yxL6YofujaFz1d9ZMHfCLLzvaMbmMVM9ovufYSyjX6vSIg8ZsV9AAeqhkIBsRQl(81Fo9(syKvKZR7GyHPiT8UMxfBQBjAhwc7G2Vc5tOgfuxcaZal8kg9Aw6NkUghYS)Q6EyjUOgyemZnpH0)vJZR6gbpMvVZi2vwP97EUgjhl6IVVHsepA((aRW06Z7MtvQxYZf3MZMkmvEuDlch8)o(LNGxd2aynwvN4jAeWaxcmWxvd)scWMF2PN82F)mCO)fTQRzHsbIIZGO1K8cNKSvR7EEEMUPSQO8v11jtxilWsOErC140VaCvvvagE36NupAxvRqtoTRZQTQTNV0NJnRVI18ZMRuUUwE7D9kG4muWNpErsn7g2Ek9pIz)dEfSIUUUP9lEf8)XQBi4LboS7byPgepWpNxyOol5lSsTBUnJDYJvbqGbX1xdSb3WprnzZwMoozw6jPatOOA4kl1r89SGv(PZan6IIefvCg)JImQOGbBIKglID0Qv8ZavdaaxkdpwTZ9zCFVwuoB5nH0k1hAk(3GEJeEuXu65Cx5Q4XfRVxCzWYaJsRXcxsfOS8RYMzmAJZmQIJj(isTPGgaS1P5Z5BwNgExQJdnHKJb0bqYE1AEH1ny0)ZBh9)C2lmwhd5w7tAWRMilyBQfWLMA7LwT1Hx(241tLVsMT3qMKcUwKu21PZYQrY87rOiup4kq5TWU(6KBAL1GUJQlai4l0RPqyrpXlooYoik2Z3T)khGTVpUxsBhhRqR(RvdWyUlRjHYIsp4dXXKaLfn)QSy5s(HqLv97y73(8Cwz5Amx)0AyNv5tkwtHlHvTAy2(9UI5tsUzshwHXIv0JK3AWqp3AU)Yal)d8CDSSJdTT8fL2Kxc)BNdC98d8GNh7SF17bfwyYiv(sOXZv2avpuK6XTuoo6GWaFxFlxp7OoIpn2VQw0FCmu0F(98S6XiGEfTFbrPpw8iavbqfyvGvFQCKYTIb)N1cxJaQslQiDXRtRNO4hc6)pvgoP)5xLTevMwVP(ggOrtLZZwu)QpQPWmgBX3na8dV6gqTWnh1UKbgg55A7g647fB5ilEG2IhzhhyP4nm9ht1klzvNsCgEVbShMQVr89Pcd2Jz7A5yGQMMxRT)yXWskWk)rh(eIV61uMIC9L7Zrqh02ba7XkUpe2RqXNtlv9UdwonHTJVch3n1brBE(SXE9lslryMp0)(CT5BgJTPyXzNDkaniux3aA4q)aYPHFr5M1G2XKz3RBzIttbMWrs0Df1wsSbOs3hJNy77lwD89bX8wJxqeameb1QZi8SSzyPSs74TllBysc(e2oL65BBz5LFOCg6QuZ7ICe7JxFk(rHlBBkwzsgiquJmhT(M3b)AhwlWaAa8a2FgdAhSV3zgZ)WCgMpktKaL1lzwmSk5lNKI8Xn3nxtXjmR8BtfCqC79GMPCTUQDrhCIMPtqdZmdKynTdu4yuM0YslojAC8Y0KCYUcxLpGxPcBvIsCJB8HDGBl6BSCykDRJuY8cKJx5EjGtLKvlBMeHwcyOkJixN0RaDxk9HjqjpxVUPBWLB4EEuA0MHutbk(y(mN1zjg4I16Sp2CWXvK15oRxaC0IVHXqjNpSXdl2cKfl(Oo51RrsKy5v(U4QYLKldXvgYej1jeJrG7JTzmURxxw856fvuzBKuUstqUtNTuhgk462IcrjS8HSLO2R3vmnr3VMW2jak8fmnrCU5jAGMAl64g(irjTh328FGAsJDT1tRgojrzZJ3yYWhR(vFK2GdUDqCBkPZUGZysw71mnTAuGiMNIsXNEVkrPrhYCws5DII2m)iDO2cQQFKYEVh3EMuzkFHJ3QnOBtXnNYwCMOmh)O6RjBTD7W(t80caOjYU(J8e(0dDDQeRvKlss5mLfMyfPpn)H1FWwS4RkkAR735NsUwEHTnemdEnXQXeAK5LxZsqJMdhNEwRNOklrnbyRv73LCREKeaJke3Y(5JT0rRLNDjDn8PNfeAtsm35nwAwnvDMNyaE71s4T6BKwVeWbBiDlSIEvRcZ7bwbnAbf)758)9xBPozwQsMM52WVRy3N1itqjmzJ29CJ9fnMx4WnvGZlRvkM1SvORbAHk2x0ghfTxP5h14h1rfXFVPjvxvBY8efHxPkA5AXhff3zUq6VH(Sg()ovnSOQA5f2PIL7AMkEVMDaly4g3eWkg(jrfaEE05IRtN1mnAb5hXnAvvMDsNzHuwHE5wTrO2WDxYOanGhzsJiqxWECIP4Y44kiAOuZFUifq3sMwN9P0j9eoxYfaxbdPjD7yPYDgHbdYGynwv9IELJlShCHTxlRD5epUFRjDZlwtcQsMOxTmBUA2A6PuC92fcRKhwbP1MdmCrsz99tuSgsiHaMxKUeRg0igYQIc2MY6nCNUnY78sznxeQRGIUgBf730LWAJuDKiQmTm1ubfPHtqDRqXIN2wfKdbVOvq7du7vcnqUM0y7PutTG7CIyZUCKmU6fg3kIKsQyCc6WOOTfKDis5CghdTKwOQ)QQHyTQK32nLaqB7M6RFGVpxHo6v6uYQ8ZsMNnTf7fSThVy5N5f6la8j3fWOepyA1GBlWURlR1EnIS)U7jGE3WIhF6XnExYaO9ujko3IeMJgBI584DrFKXnLmS2MowYoKhjgCdkT8wHxWH7ZMuAz13a78WHKsujok(M0J2N6f8nmOtdmV7Kw409TNLi91ln(Q2w3Z1BRJpJU7QEXG(GO9WxUMWWku)LXgWwnynBFAJJ1NmAszgu7VZiYg2Y14E8OuB7pmBlGuGW86DBNTPyb7ejH7c1P64o(dl4qjtLbPU(2VNIhsCS6c(D8gyo04xIgyZa3GwPtihPtvvIW)Ppq2rkx41r83vVGgjCBcZr3VnFwgSt5IMnnSZOtd6StxRNsND659T7FZdIJcd8r3XZ(h)mC3PrBh)U7ctJUNC8(6yrXXYPphlAC)irTK04MCpG4B0H7Q7iJBZ5QaWPji6(DYtLobYY2TVLD4Ft9AzV2omz39GPjRsFsCF5U7TYEn5(P3NLdASqhdaWppb4J0zdTd2B92M8N53Qdnh)4DOzpkjDyHyqbOwMTOMSLARoaTV9Q1YNtHQeY2(nkQX)nI)TAbi3sggLFU(lTTFr7ZpyEbk)xJlXm845DF8x)wC4AlpRjwtBz8DefGDIvysblQUt2vxXQIbZwfBTNEBvZz6wt87Kysrc)Z1XBNg9E8agY5Zxg6aaB07k95n5b8R3qj1)ESXvdHRrZYEFRT6NAdr(BqNF0t8yW5AlnVAlMBXdHWAnJrsUERWlzAJjJn7df5(M63ltD9DPkGmBIgXJqH8PYMbtNL1964Eye1c2NeYB70E5mI2uKCiY972JWpFM8QFp7FRjdb8OdjOthR(7kZ1N7t0D(FhF(1RB)n7pEJ(UFxJaw)XC7NOh(3j)hSvV73H96JYJFZoYFOQYuKAxoh2Jx)rpERZqiN0XCgymecB1jHd5FJUxccMDq)3Xqcmu42m7jhhpPn(ErSSprnOEMIU9GoIAxItqB)30tecCBZHixXuIazh)l)9ogaFpDL6WHLPdKw7TS)eeAbhN2eDTOPziw(QUP50vRRVFyCjv7wz4toT84IEO2hi2ZMcfHIV1Cp0KEC2GdpmnmTbgZ4fLEtHQnymi2Tax3k0LFTjl)EyVDQLMdP82xhs93hFozVTi4UJ(EY7W(SHIYxSNgxq9nNQCJ)jKQCrui4Y3SAV9Q1aEVYVL3REP7oMoDEM9rf7iiXoVr7IlQec19MGb95CkJ(GQNnDEZ(Sx0FuEPk6hAE2n5NUlQ210QJK8hYfvT2JxJ1aTt6UUo78P0Hv9LbEt2Dhw9i8mfjMUR(MAhmcURVM()XEpzl32gB5VI)bSha0n2OEssw0w1vBJeDI9TsvUOeHKWykaDjPCIVQ8)(Cw6vSrifhNKkopygrc0lN(SV1D5RP4VzoBs8Dl588tFMPpVeZt7nOoC8I2mMlhJJxMn(04tSn3J0PXiJtl7EclulxtnEJ36xVohD48f28(QxsX(OhxDn7BMplAAtrVQ3bYvkxD1YINUr5n811SNBwhgAT37JS3C6YPRFle01PVM8dAY0wXHULZpK70JhjgYUKzBlLd)9wJfD57cRCIoCErxMC5PEFO6ocOHdjfl6X9ed4JVUYXIFxzpxhUuAiJM)ZYBf94GixVt0PJO619eIVPUNOt3t22dq96SOVb(IyiJ13MRe6iec96B6(CMW2su2EAlqp5uuShhu3mx5IYT1jMQvX1WfbbDK20kbCBlU3TCdSNJcYqXxApEVTewSV08EuofMRimoHBofO9ayFRQMWjDC2Bzb3mayhrfB4bMgB9dLMhOXxdAnn4g2ao4DGfG)iVAzjM6YU1RGfXAen22NssYzO5KFRkIkg)NqzH6udLQronW0CattLrMIpnu8KQ4uHYlmkBFudEWtUY099NZZCiAukO)(gjcK5VTctI03k2PjzIDgCu6eEXvVQA4sYuJqSLKjj7PvXVUEquJZeffA8kDkHZ8u3(uT1(76S0KkApVHqf7fawPdobvC4ydib1GM9e5JKlewG91f0NiZ6nkMzUu1GWKI5oPzxqEMnp7sToyvKPRN)gepjEAtz4cpGRv6rB0NBPU0kH66tbpUAp73XhJ2CdppEgz7QOsfljPJd0SZqp650t(e0gUQgMUImuBRiB92Vr1ktA4BKU9ZPosBDK3C9uFypjvq63k0(s(UMQ0AwJ9PNXazLxpAn0H3H7M8PXP7E6JfxH(kUwTC6stZEAQFyV1FFJj9n6jTrfm5BDktVY8E2v1IF6SXQrFXBu9pgvR4tRnFvnR5G13t6hzxvCsS7s3H7Cf3SsTpDern6MhoDbMULw9dwl)G1YpyT4ZAri(ldRLux9ianwwR6LlKhsYsAIH)Q0aQ)yzv6RLvxbd1dsAKLJ94jyps2i2DqRlV7(Lf71toT1PpI1HXev5cSm5tUT8t8LF(eRJYZZDuEfpzVphLP24VUVQHQH3O7jj(BZb4Pei1uxOVUPj9DjcR97f8qN10AF3t9ezE0xiuhkbM2s4v5yL5bQEUIV6KYEaPN9X(XX7ewpmmCrfbRzxKV1DK)fgXrT5D1viGhr5f5c0A6N(oAPqDQCrxEiQNm43xLVGSHQPHEumXJlBA7k6A4c1RhXnn583o6RdvIKJTmhgiaUDPfudUrT3rYM8Q7(rEc1O7qHOUthN3xL(1kE2DMEMd7M0UC9ElvM(dTw(hVwF9LuMDQ3xho83qz3TtXFsT5MoIys36o1FP8)KuGSN04oBsDT(cs9vYHJYYa5Maq14jt2LlFVziW2ky0oA1u9K0ad5z8oIaxxvd7ZUgS6OMzgiVG7T)Lm2IyO7Gt1iG8SFwR3C2G2B202(WxjIZcIKj5HIKD(RQvNTuGVLcRYxH7a9w5pbRl)HLKpvlj7wdTo0hVtv)gHvJDZBTptYgqxYrlMULDLgVTpkYXq7T6Kmsg9Nj5y3NC)Wjq)JH0TB(X7vnCRv9j4kO(P3EgoeASCngJRGe(Hrwb)A1ZBrLabLZ2qn42O0jBMx9P3oF9U3CZQ6tv3clhxFj2L0N6h7xs)cNsxnUv1nYPGPVhCa41)5HI1aG9sAd5DPJD1v7VQ(EDB1oc702ytQE5xER(CsNU56Qvhb4Lxndw00kMlImAnQ23AeoewZPUWl)CeHsycFQEm1byxpPNC2(dXAqDnnDB96nLlDJwNnbVZDQgeLzaLE5W0OsFj1s9OInMeTsF5jH2K5aXCw871SjhjdYCY8CBtoktFB00o783wodK6bPhJrqCAXDXYAMUikrFnGvTO4Us(6gHU(uKwRsgR7Mmjzio8Tsh4ucynR8ohwk2BDfaRKiwH3Ktgr3MVVWr)w4D9shKqDsbqx9roxvkP0n4Gr7xxjvRrVxQSZq9gbATbl3Cz9VrF5hSvjO3sZAwLY6dcLNvSUVTxyMlSX03(f70CdSDpycIdq(fxv8)IuXiI3pxU52tV8)RGSRMlrc9c2n3azUuKXoU7zDX6SxlfrR0CMCVyIIKgmC0w4xxC98hwsSyuEG2GXY6IKPlzqtoi8M53xf5ih0fIOYY1RUAC3XwjuO9lQWCMTSy9PNUVn7RMzbQR5QQtDxKPLzQTCvDXC5dYC7nviid2pVRYW6O8sh(nsBw)iTz9JuN1p0LYHBEW6Gve7Iv4KLXEwVgZFddt8UNQ0l5z13pMR7kcThq5TmyydxlS8OYtSBMiHvEsSwjcV6C2T6CvSIAisbDQgjeuDHcHsXCCuCp90KCpusVusJUjtoB)zLB4RBfcWysr(ifxl7Cs5svLQ1RCR9sGcybVJnXY9b)rbgu899VEcvoHxXqSH)ZHJYg8v5OtO4o7DxvzhfVWcy5o7rqK6k)r5PyNKKj3Giq1EG7B6)tngupUA2k6aoZkVdv)AEfLZwwWOktcTxEfA3PSEMdbwd5(Acjax7kC28ejS4(1Nutko4GZKBCiXr1x9P6h2S7Aqg7VUa1QCvTsb(AGzRwPdd6BwOvmEyMT4Ust08l0coSNus)t8ZAYWtNNxm034usdZrE7E)pvf(kL6On4ZmkbNoNsJrx(RuERXrExSLZRUX(Z5UqvXdG(UlTzPOJhPCUOEI8JdjZoiZ2GXIDkwUiPOz9vY9XXmhwHwDVYYDCbljICe3(MxEJ311glFvFWe1wTLgL5xuE7w(HQ5M4W207Gog5XoGaCRAqo0Y(8QABDvUhMQJUDPomb8IdrSp5x7j0r9y)c4HUsNWXZqYsPdN2wJhkzEsoRx7LlPJw3WyIL2gx4TnvIA7kOe6PpJxDpf2zpNtv7wouzEcqAZmYtbvBpkyiD)mXlR5p4W)nI0qTHWep0L37DPsP0lWsTyZ(xRAakmF)g20uvm1wvCWYYnf2PuZ02Xgq)7tWVbnXix23akKQvpXgYDDjxQDeJAh33qB1r3xrAMecnaKNpoUIH8SAU7NYvC5MV(w8AKsP8TsKDO1UUNtz)MQWzBVh7ghxyNo(Q)72dCVqMWl)gm5YEVl7QencZHAe6wgF2O29XdChIvh(HEMt8EFMyiYZr1yzZ4lCCi((ocarY)gAAkDo)TfpSl2ypkDORp(TDu3vgFmLyfElD1zwChTS(5Bb78XZwUKGAD7N(kxX)wR4d1aZc9anZl78AxsI4TGPJOfZvpTXHt8b5f3wwSCHZjVImI53PGNSYHSMUmpz3A4iWrx1Pgsn6shRYCFChRtRaxpne5TezjdUA30WKkg)2ZYVmFf2gfNDVdwVPWexmM1HXJQUQ24fYAKtSxFLj1vWXRRFaGQtnfPEdlKKQzZY6mzNwjkIY0ttm8qz72aDt)PN63UotXlUMAwr9DVMh24En3)K49(NeGoVAE792DYIvCsjyeA2MJ)l4cz0wixnEktGTqDRlMVA8mbuPdcE(5wBQk7MgXT8aOGVdKh1o8(7DkpgRPLXn2OSJ0MnURnX7kRkFkAPcGCuzDpNyeX(a141Ko1eWNlO66kmoEcvfKxp)QIFz3floTA9V44n3F5UIfLZ)f6r)f7Tc5RMnZwrN7UCPtxw0Z8ctbX6tO5HbLyyrm9HLlXfyp6jXx2Iz2(hX4kq72kM(EAqGPOL3GvXBkUl(jEuqUcl0NekhPBTb0rATvyTfxH7Q7rjT3Pwg0kjToEJBmkA0ryO2AiWSAI4RHMJa7N2akmEaEmoZPtH)oEut)9Vuf(phTy9YinVyby9PvQ9eim2UwZI1DwFx26aPVr0Qr7BddjNwlshiPDxeXTveQ9zUbT2AXlleOD06InO)Ez(GGx2hwXxvJwMKc7jLt)KsKQwlw300Wn1AmIXOXJhmAu3f7AzwE7HCM7CpoDb9Rj7wk3vQtCD0g7zCjDKt7UPdhr5fOaRtHAT6(qxVGddjZ6QPf4ENtFOQPY9kTT70ke7zLgh1XmQUJyw7aM5eaG37OOKJ48Mr243Dl6QHT32gbKY8BdwITTeeQWbTzaeUxBYgnmTn5KUPf6WpWTzf1oPrBgzMp4JYVMUY7bQOZk2SE62BeRSFx99lJSPnvT76tU(0DlelCAo6it(y6kxNqoP7V4nOZJzOCEh9KBLJcmwEmfVaDxF08llwoZ0rYPrBVvfZ)eMoM2B1QxxmhWn4NdVwExDyfWE6ivOHz11O53CD7oZAAcptNDfEqd4xhT7EhCe7StTEkyStuo(a77qlMVeo40cAzE286ZQzdE3aRZ9lCTDyf588Pw(FTIuzwxsFzo)WPKzXaCnbDebsYUpG1)FwxVf4asyVl5STDsnqyHT)PV7KzF8Sdoh9YnBBa(QGgvLRAoHoHUTbHvMDX2KlRR7ASVwo77Xc3qWU((LLBMsXjPHqsRZo9mtk2henFfEzwVzoYMDQ9g4DvXNll(1PoxR6k61ilnLQ1LiMS5wGP(T1lx41Pe5UdWdRNb)kDqRAKWnNEkhkKto50toGqan)(ApJ8j8J2WjH9an3EIkekgMZX0BfuPv1vpo)W38wEnBrq5BKCDgcbSvdJsFvwEEEOetHNDS)2hQIKzVkh)PGSKWu37l7DV(6YFRqfLD6qb4j9RTouIBXFrfkUud2UhTN0J2di8YN8UtE9bN)X929C0igGBps1PcuUPWCamruY2cofqHZC(k8wrrCC5YLLRlaD0xSMBAsADLLrnzCQymG8LU6to(4jXE((R16t38jZrWG31t4LUwYCbcyiBJINeMeobqtYFzyWldLPpwjdI2PkdwXGKn4SeVQuZ3btxSC2D(XjbtcLpwLiKWxJPog8iH0Ji0psCg9iYa49tbwoWPjnuX0tldI1pxom3WqffIdvugouj4JlLQhjsWpIme)6aWic8rWhppa)xrwMESsNeM)yvQehLOyC6YcHhjkqIVAmhENKjW(JgXqrcSOtHTvvuo(ezb0smxR9mp1UqMTVgsMeg9yvmUgYssGHpK2zXj4lgPnkGbHoJ82GLbWKlryPehUWy8FLjcAOvZnDocZDukm3XWuvLKNIpm9ybYyNLiC0elcXtzyAtOfxKe3vbzUaj4XaLBGVNwEr0SMitvZTD1fcRo8htf50yGpHiNoPJqIZkasUdSYIIXztQwoWCc8YQYYDpPHHsGRhmH9qGaU2tL0gvePGE8o1b6nMTSaXYGLuo(pP0wwKKriM5oaWSTH)Rp9CXlsfbQtmyXk045ol2yNhwKIlagAhItsmVyKiYrfGfVdE4aBdzweTTjabHgfs5Ne8mzWZiq0KyCWYOvziDWeeMOxL0bTZep4jo8c8rUZlm8zpnfniq2gDCmSSbA)QmIqsW0Lzb0Q3fHkAlBpf1oX5iNam50YJijfze6xGlCWBrsJxqAoo0HeDpDaKN6s3N6EKHik50HCmICeMMJZxuEOdMt8woA1WGe45YGvqoXZjM5trVJiY7OWDnpmVkfJuKQoMW)XtAWICAYfsdGiRb7SmCBLq0PeDtwgDkNf4SCHbncpjtL0wwkjGaTftYCbyH6roBlKWviuPx0rlpsIVNAqtI2gdqnPwI75go3jiqlJ4SkiIAe64G)M6H)sKCeFHSCInFS0fpk3LQpvq8(dCxWspbPdi9JyZmwAmpY4(oIvhyBfFvpOUCqJJOvjstaeKKmTKyhcsG7PuGybe2cGVs7gIpVq4Yw0dAgsNpPssqPK2CbUy4PEy44WrcSfbeYiHKfNBXhsBSMhIjPMTFEpNtUd0O4K6IxLsAaeHcCYz07yMikXLGWdtCuu8UVbGMaqS0C4FeH4PCwkXvnn2ra94GBO0VMi59jgudFcDj8gs2Uz76jJBlm5zk1TtGYCGCL0VnwrewI7sjvYK04RKJRIiIThCmK7(kcp5E4goHOFsizdPzS6zUQAHQ3IKT0zForLlZimTGuhkNSTXNvZ4YtGd(yP0bEaH9MqK7sPhRopEndVuiajqetQfNMssPjSfPuAvvsF4l8g4Tr2t6D7bX3Ic4mL8iiGjgkdZhH2yE6coSsMmT8iiHjwKEac6OlGqKK8i7JN6(WdcNRqCVbgq1QmBeQQWgC4YuCilpuG(4TrvG2GSZwuRwp5UOTPKe)WmItAMcfh1CoWrlfXG7CMp42z)XsWgqWLgZ0x90bvwurMenoKOTTFRa03DmiVDzzht2VnQDfDq2aMzOahdPaJ6OxSfUB2Eml77s3UIl7nevoeqzaN2RsJYJxAVZP8vrx(NTBNbUzzXOsYBYXuWmy9DzU1tmucshXHw9D3Fv9Dyw9JEbHdH5ABGxnojz9m27GUojUSQ8U53t(P6oZ)Fg5g4JNxUSNwsQFJIcDh2If1v7TPYPmrIOb5nyENa7bv6RExv5d3nTEzz9huPtgmJQKWvfy0p3zBMgJ2q9vF6cTpdv3jeKVZNF1g0XLMPpx3KoRmHo4roBFuHPKFqVBLQhQUzv9d3xSyVh2Sr9czM(pPUVekYPG43Dl7d14G(5E6CID298rpOXn951)NhMVIl45RbuWJR)mUJu9kweuU)Q5xJ5a0PiK30vK3hblZOaexFFr1XLxTQ(4IQhof(FxSaW0OC5MRFnyqW(a9RlV(6YREy5MVmTzt6QREcwH39MboDWgagQPy2bG)jF2s)IoawVuDZcGt5)Uga5muDwpn9BXKpE187Xy4T4uaWyxUZwXjVp)(QRnVnv7bFlEEX(zS7wcRW)0wLpEQDGYL7cG5iFhsFZkGA7NWI64GFBZQ5hwDDn7hChuwg5thXHGj)36QcdOaonM)5If4MTRUNMaHuCsg6HclMSQEZ8nfkcX(Uu)zhTEQDTmZqH9VHvHUHD4DkytCgaLy5sCLPApX1Wk7SvfxbuA1vMB6d16ZCe61d32vNbE3blQcm2ReCsJHkMaFBZgIdU62LymWN(t7yEmXKMc8KEi5wcfhEqKKPSQGd2K9yIqDPGJVuvdJebmpvt)At2nEzr0(iaqvEmMfjh1Gn3HIe(klV1Hr5EZVznF)rF58BO2Hrz15fK30lVFnJQa)YBjsSQfa74)Bb3WKl3uC3YIpxS8DaeYgzq(sWz(no5Vlnc7JmzNwx5xZlWpOQ5OtRkG1Izc3hWDUPE1xUarIEKGd7dG6hUdPzxtb(JGluPkbN97U4ZWAgi0EbGaCpTln)oV6qHeXt2D1D1RA(6btMDBXlOF6l99QakYpxm)Eyn8I)NxmBvz1Nk2S(znqIjhcGUxCrXMx8MI5pVft6e8vFXbv3ImCXZ2NjmHLDtNplF4UQ1MARf(Q1N5lMips3bCdZLQlOiqIWCugmlwagQ9oD2Stp(OdMoZkpjDYStpd)kgoQWNaSt9Pmhtqdgvd0KiGvnTpxGyRQRaedIdI18fqsJaeQUu)Bmk8HvmwfZ9b(Au4Zj1xCB51BmddGWxvSq)OCGmXrVCnjEqTell4GEP4DXcnOA27f4PjRcsScZDMnK06g6Z8B29Hn1xWupH6ME95fZVbwN8smksdz40oWmXSydwC1BQxUql8GlthwrPBwnFrHPZMpZuzphQHPyyAVr1IuqYtyAUKIu8Y53VMLcsGOFQC9dZxsYIF8KtqdKcqh3HAGNIgifft29vbFnAWrucOen(PeSojJ(ua4gW3NkrZgIKXPOASGMUO((WFZE3cTTidD(anE0Nbu8AWpr3gq)Tq9zepW0aMeiqx2cVh50F6Ze16dwaWWgQECAyHprnOHLlzue8urKBxatUPzllos01NoJo9zcB9L(trEsIK)KwL4NKRbJfIe6ZOub)jQJpcoq7cXNlnL)mt93Ovj0NQXjJw2b5eyJ)8Rp(v0LkzXeKam9xsNe5bzKNBGvPKSmuMHqcWiTm6VfPIb(eFUiAoWrq9joUWdKqgDlrZ3PVpGT)mICPqoyhgA2vc6GZN6)sJwSZNjbysA08tChZ764KecXseLLYqgSD1xHlocprgLWqQe0omcbJGSW3lPDlyDFo)jVlruw1Nc67zFFG)DG6ZegYZNyju9M9iztp7RKSqYheI0e0AXiWEB2coaSHEjpN8RsQmitO(K8yHinnH3x)R2CN)N2X7)Yxq3F7yh88yk(TIlIM56O5MOyc7ZvPftzJ4zurqLius4MsbXQp1uSXuT(A4BqYLaTe)0uTSWlORpKvu6npZDWvcDXbFQ(7pbeMU3xOmXa1FxBRZQvfvx9fwG0x1AQIsjzb2)88vvkbYEkoYVaQ8apxSyA8V5nM(V7sToTEIT0vRHAODQhg(mZqPXV4n11lO)8Sv1xdpnAWo(NkP(VafidZWXLRVQaGNvfGUfnuRWQXXxB1QrqtEPBkBLzfBwJFJx9RWQ79WDx2iroZDVwwnx4hrX90fxmjo5FGxMRYjOvkF5IILxpTCfMX6vFA9Uxw)5cBPIB(XP6CMBJQg1FDX8fMLc6EAG1CAqCwgBDSQtIqtNAHADGvZV)RoqtpJ5Ko3dw223NUzr8ZRMFVTh6gn5DNrQUcMOARiWqVQDP)eafuCEo34kbJM0PKy6KAoTGvjBgNhwKI5X67jePQ6OYvLO00v13r555blUPGnmuLtOywOU2StuLvaFeaeSQCm78tp6avXa53j)09qWZkwDoS8IBFxNQU93yW4XZ)nQsNO7zw04I7mQQUMnU7SZp8GlM9X3E6rF4Xhn(209k7Fs5IkvvbHnC9g4MPtw0zzTQD)4LTk66YQfnAsgyEObeIRXirkZa(RsqKoWEe0CG85Eqaj3uKB69mlAwza9CD1LcJmd9c2X28gwpQLkCS)RvQk4vzNV6Wd9t1AJJjtXst2sIluZHMUxLDzUqPgEQ4gSoTCAc0SnCngO3x9sLn9lAw2Tz20CZTKCNAxAMKCV9QqFDvTbnLtsNWn8rN0bOzMpRRmH)xWitkFf)kBHScL61hEX(hE2rhEYbdGyXLAqNtrVOw9xp)dHAHXBlMIwuUK0JddnHqeHo4xHVXiA9IJ1tL66JJ5dY9WH6I(Pt443aCQUqD6ft7jHt1druFhkppCUEj3uXF5SDpA3xF4jBJTvy43j(waQfPwlOFziQFzqqaf2TiW0OCX)eyB1iLL)BaFlRZXgabk67eceQcefCwapcJqPuGM68d5D)DqE3Rp)Dh(6pEoiZ70Z3D2HNEYqCK(oHpjePj)GVZFB5789ITdiCctegkXHIJttP0nsIP8HuKhlc(bdO)6ZakBYfVD3J39KrYbk)7eQvEQ8h8F(BREpbFNWsscPS1pkivI(bwc)x(FOCD()BVR2EABKGW)Iaf)UD6NsHeAvH2Oe3ELpv5cMCrxWbfdx7Dv8F)2zNz3z212KCsvCxLGVrGKyV74N5LDMNNxqD(5G6umE6N(W7MU4lZvWotx8P9g4t0ZvKpPXrW5lfLffAfROxGG(1dck(zZGjvf7JYGjnlcouOOKKcO1xvrqRl)yuA0lPI9RfM0KpE2ftFF5EXKsEUYUx9Pc11okDuoCoLrPfMHL8fSPFfXMsF2mCIaA5cmG0NBEmmipQm2ujNbTcXlys)Vhtkz8fF49V7lx82LL)20jFA6IN6WqIF2omKGIuCuIsZPzflnp8LJ(G5a4UgqL)NE2hHjV6rYGYQGEZ2U705lXwbrOxUxuTA9v2HnjlwqdnSCzerZXvUROqG7hratn1FJmypsE4KPXviwRm1JAXM6ZG3u7pk1)mB2J2JWF(U6RxR3bMjoa)ZgARbfTo0gwt5NrJr2xUWTHiCp57DGGKCYVxF1Fiid4u5DYW7Cm))y3eDO1OmRw2uPUO42lGiti9X4pBZ67qYTAMDKf0nwkUSuk(pfAnvwGKY98vrcJi4Se59WsHejRj5upQmZ2TeO9a0tbg9PWc(aQij0IaLevjZ82RtNSGxp0U8HOXH61zhMVkWvbFmwz25dz1PkRpnTdMyCHk)sL9jrxE1QN1bbPPbDvXF1C1sY2s3Q2SwWG8ik1wgk7lCgiUB36)S6EnXd3kv7ps9hXhrxBBJIslpGX)dMRjsAfupQu30Qhyke27B2bhlu94xZQ6YTB3C)67O2uh4zZlQ((51nR00c5RmCHk0a5Ki2SFAMDK7YONyfA1xhIcqJ1dj0B2UB9FVT5(QnZCaOzXgy04AyOkyjCfVxrzXSb0hm96bjTvoDQuF9besMQHbjQWAcZIfAVuQ63gvKpkc(RzebgP)UPh3XVC4QMBiNrM(Kx5H5rnzQExLZnEo18sdjLiPAoIQQdln3vfQUzTUR3tDE0HFdGeyTzJhdWPniNVBTAv(E1)PE(wWgqhEI8ClOIHkfPhbT23Z7UFKjUH8A1mSfGCrxftygANXieejWJDWE)DdwSgm7CfqcY8Qioedg6CbyWoGwgKSVBXjyPhlz3RGqLdXVF1MhUUw9MVUUbroHEQIBKFgbvQtdQTJw9NLAd4BkeoGIvvBa4Gs22)oUWnJdVrXxMoIiFc1IxEoEcnZNLvlaiuENNPuVyJDkqoeckLD05XAYj9XTMgcpM9aqnuMLzcnq)6L0z2aDoJ9osJvLP)58Wuhwx(DyesM2WtYtndQABhfMrt6M(p6eQxIMZjKXKOCxJTptYg3dnWGQXibhfhwOv3WGrfXb5PdoLLhfOYT64u1pJk0di9GZBPwaTjo7DLxAFSp1LQLgzizD57DPl(9RdaeONTHtvU1qXIXDIsFki6csjNupkpRFO(daA9OGqF0v1kc6I1VfrlWxhzDzZIsPxNScDgP2602FLytWYMeINg7cZzdeTv3Z0My(kPzGKA(tIP4j91taNIDV6626Q26omGAg7gkkRWo(03miwAOTnzpVcxcIjuIEVlHqk6jgV7QOxJhHVCr4S9HE1Ruex40RPo)jCUpxOwEujpaweLw59e3vCTRbywru0WLOaoFiXh)aeCp(UYdFX)p8zZNiRQ82uJ0pl5gFJ9cqMKuj1A8DKuJGutC7NnqvRaPftFVACjptmoFA4sN(l21n(mt28KHlpADfAluQv5Jhxo59WA9BMo58PluwkNo5IjNHGobQ4r1DDmbKRwF28ekTXaf(bdc1BPM9VXtUUX05KQ7AiP9QQh7c1TLflCi28pZJn)nIqohUFmXrSoHw15lsdL8XoW7fhhaG2zzPjQihjKPJscv(db9SnUilopRFW8UUcE0lcBgFpNRQGAxuN)1S3HiM3wR2bOqt8HUoKDKhAwZSGSXGZvx0hnKi5oSuyaz0Ct)b6iq(o5HDmU3XPCncsrDhNLq57BDmBIj(5vKrtyGmJZdlYgTsPuxJAydWOaNOw4vE5eiNE8P7qsXPfj9qKuhgUWMvzyGx8OYBx42FQS0m3vXdpWiA4bOytq9rWJXT9B6)dHsZfJxH6tdMv9NG5qmAJesURcGzZia0JPGg2ui8(95V4stAmFTRRygf1Z3c7gPp7YgFIJpHQjHRE)JtscN7xAX(MQLmt2JW7Xq5wOIepNY1UTuiJ19u0qmsDLRnWhoMGHfGR3PXb)uguJsf2tcfYjr4my)wcqeZUdWr3BaCBszZ0z2rmtkIAXfeItEkTLooC0gUUAyoQXcYFY4P6PNxFvpV(JKY7C41qYp3dwWz5qxGDgTUTOasm)3W2N0nDMdG(p97kc2ZwfYUk8D3WtSg(IOz(M6bKYNuAXDhkQlnFgYYJAJI8Wfd(CrUuDQ8RkUN2NOYbAwx(7k7QMQn0ukw9W9Bxud1Q(TYAJna8ktthuzH3hdjn64IKWc7aMzck36Qqq(oHManC3YJffFcN4o8RQ7lVQ7lpyb1UuACU8HBVvTywRwaWjJm0uMCZUmxqQlhGFC6bF166fnd8YIoJtctM)zIDP1GFzOzgxTApxg2IWxNFbhNaeuURQ7kkYhH9a6iS9waUgnsVUoUT0XFr9zcS4pQ(QQViww)wyVPlfzj7DedIWojHzmv(kGVMwaoC72Do6MZiZ8WHLzYuNsruXUEcezYb7ylLNAQtCuVEtTqAMefLjlXVQmofA6qY7VQtzFgs4DUrugmK52nA0pxPzmZVtT1sSvxH3gRszqOh6mBOOsPzPm3jzke5DMm0q3uXraA7btzqNNZh2hl745J)6TlxdS9oonIx7xY)opEG1Y41GSpPlMUA3x)ln5DobsiEVUGV8zwg8QN8KR9E3xUNZNoWCGHgBv8mpBPj1m(Ff4SZzJkuP9qZ10biJyTwyNhPPM6ko282FOEX)5d",
            },
            p1440 = {
                s64 = "!EUI_S3xwZXnoY6(xXVCU3Z9bRG7B6jTvQv0wwAKQUBR5ffuvrvIJyrwdjlBRwH)VFrIeaeGeGQ0s7E84QJ4CglwKyjrMF5csG8XFTXlP9HvzK)NBxxua)5YS2uYZdtAMvNLv(lL2EEw7(RnrjzRZVCwArwP1obE729k)rPJFG1UFdEYNZQBYRklD3fAR5P02Y2jzDzr1S7)q6dvRBHNyL8L85T3DAA7S7G)2o5Ol2)6dsBA3pTUX2n5Gdp96zvvfZR(szdTjAtRxK1I))HpaEJ1T5f5Tp8RnX0V)8QVKP9RDzFn0b3q6Ga2Ft(PqSNlsBAUiRPAD9SSbTaDQLwo7UQ6gC0k15uIv1T32K1(PsGsXBCndeVKM85zK3y)ZMo9St7(YRkFV1orUY)hqqDCWwyDtB1YRdV2oYXk296ypLo992wo7eBhey5h4A7BlpgcswvK(qw9ZVV5FzVUYFhl()f7gTrtxVKpC0KPYDOf2b4hQ0bVK23p5Ito(xg2bEjeMjF1MxUbdtonnVK8oJ1sIbKNtKNvKODDnVUpSDDtME25YTQdsaopd437rHdJ3joooYn0Xn2pA8gEiPvmEDIJSCORKap(xBRt3Bwlr2C)1TTvLk9ze(nb2wU(2(bVn8pUjR6T26zTJNDqODOVtStCOC3yKrFd6xNqhYC1omuA1XPhn9ftf7w17dIyE9VdDzSXUDhJUvGJpTlur5gbzPh83ZSFItUSLaNL1N3JZ6fgswFcIF(Yk7ef4e45Bh7g4ghN9EKYPU46DDizXn46a7qLo33BhceMFGxSNTN14mHdKNqgbp7Wil)4O4aA36k3TreEkpc441XUQ9RnBToY2LiWy)86xx3Da(DpxFl)i)y6IOIUSrwd1O5XChzJRBWe6M1KN9w1UoUkIU7(nCgCxw(I7Ar1ZiV)Q7slj0X9RwxoV5XVrhnelc2B2SSsGtnkzDtgTtNadgKQdkltUbwD8TiWrUXoe4LiyT1oPM8yVqVUFiK(4fa2n0LbkgnCkAwczODF2dtRMq0bqvnPv)nzL)OIISMLz1z)2j8hdww0x5DJtG8REat3YPPLPlG1DJ4sp1h2ZIMXgrDGG2YV0VvM3oPoDzwdxtwVxGbNtBduL0iVaxxZiVIo1eJ969uh)uuezt0gJCG43JovqPYrOxdm4Z8Rka2gBQ2Z6tZTMeY6iTNraXNIgs1Pos3BgY7PxDeqlJ)QGSPFYTvLTaguqYIIQBslal6p6RRQZAA(s6du2FIqBrEz2Pvuftn3LsAeQrpPZNtySaz3i5(zsDEgaTalj3k(32EjFoV5xiyxNsqEAZMpb(9BQQjI)htb(i)1I9ka4ja72pHiyNTp9xiJjY3MFdkPt64cYyRH(8sc96GQIkOn2jYzxG0EZIli)HL)UuWhYxEwzXdNu2qxqbun5VJ0d74haVlHMNUUTcacx1ItItk)CEl9t4d1lWbKFYmaOI2cFewYMcu(8zvLx2(qbqNwsix1LW8OH6RfmN6ObFS6OYSLpmb(kyEIZBRDC9Xwx8AtPmQtqFVAYqu6PP3mLtHydixbQnDmnbPd7tPd020jjL(T0FggUDdMFPADtE5Ij0NDBkJ)USKizoHoAAUR6lxKTG84tiZWMPDKd26Jh9vODp)nKPXWYruG7UDF3Ei9WI(D7tFKygX5gYktVPiB(uCQCSyj1M(rND7Taxj2tyJEz(Fc0zQshpzoY)r1hEe1Lv3ubkBiDuDAEXetlpDSOKNvr4E(J7iEqNpFEw5etRpg4rDjQG)k5VTo4qN4dPV3mcw2b51ZkYOQBtjOrZUJorfJglKeutwwMs)8YQ6LPf01XMvP13FKG40FPN2mPu(PiRD7gaUt2lCYejclv9ED6881nLUwipsotkbKyM8ndmjALPCtwmB(MoF8jJP0p)Gw(wTd(j0)tLROBW7yyWpKYeM0M9121e4ncBemAUMty5DlFO2rK0j1QP3ItUPOQAEbbY(X(Sd(jF8OF)OlKh)4xqOver4Sgm4kZa2UZeE(2J1gcXZD5iKYDP0y9uwvMrLiW3Iol5MQXTnJ()IyQmJYOCWZxxNcc6Njz6jzMIn0V1zbyefv7FwvTKyG9U8)MkQ5neBwmrJXjdksAJRp8UeFOtpHC15)N44SQJZReJ)1Rwqw(ZoiTy2zRAzrZzgzHTDsErl1KYOKdUlD5kYhpbSg5xYQROSq)Eg53tlrH29M)zcQiHJOM(sN(q7Dtqp4UnVUP9I1LhsiYtPklNDxkg3O4o0L39(3TxDw678DWHG04Ic08VxNTo7r8ZbXc6dBkQidzW1MK2g2ucWfkYVHmBrUoFC2q0wVoTyV5uB1)gTV)qEXdRslkEG03)Z1f)F)x5LFN67GKtABkYP9807QjJHVtDCiDsVSQ8(NONhT7KgyBAptmrJsUjMd0028ue836ENyyf07eX9LFFxRPt9XSEKgX5MvzKoV0X3A3hrdfYkYMrA3ttxTIaUwIaglX)Q5Xhz2H05wc9nIbBp)sh4vndSc83uaBbg3XCPLGepPUAjXo3j8pMA1f9Z8OwEruoS3btp53pcK3NnF5Lecb9NLb29OwO04ALSpXC53b2X9U)3SfjV7W8ptmT4DNVUEvvt2)pOt4wfvtnW4BWK2(NVjDG3pHZz)305C3CTU8)CzUdI)juIo06NVvABVGOFc5V9d(5BstCa)NWf6F64UrhFHh(5SljgO9RzpqgMwOLEZxsEVZRAYHpbCLb8tJf3x6e8HY3BhPSlG0yXTQkVe2gLdo6Jtb37St(AjMmb1zfNR8JOpkSixgdrU0125AVOqE774eTJ7g0(VpKgVh9DHFcF3tOTzKZo(VKbAuI2nZI2920GXrC6Er7xldJd2jiqSTw7YPvEMOvIDvttpZA1hk9SJ3XpIVTt0n7QBi5ddjh7RTdJelnXUBgPZXAtwD6TvAB(S2IUfFS)l8nywhM0LegitID4yRO93M6NEbwnNlymIw0nm02NategBMA6gIPLruOLTDOJXEZXI3B2wxBh74egETRVGXpySPei2zOHrjAItA3NxIXkfdblkndYaoUjeGL0wiwjzNuIc)aYb8IoyatLFmniTtOScS9yaE6Pz1lYM)72yWyaSS9lY)Z)mTMgEMOKRtBU58SAsFEA(cQ)JtvdHJdIas7yiIP8UCkS0d7EZJ4MfChglriKAsXX8j3GaimZTPZU)GUilf0fq4PeCS28vtWhSEfDpmo(GdNkTLar4wcWIwMCuhdtkxV8IQV0uYcw19zpCtE589kYxusg9fz32cRoShFm(AAJeQ4LUGbRtM5tHCZscRvGWhNCGs6nHjNKsmaJHKXQnN41(zWMs0sdhwVyHsinSoLh(mNDh(0Ri884MfqziAZwsjLmk0Eq(GzyxkiZu(yFsfN4hTR0Kf(64DhgnEdHlxkSIS1LaGoT)cXokOg35PIxa5fe7UreoHW(Ckl4Ue19vf5ZPP22Q0zG(ElDXU0Mp6XblBNuiDZVRD7MuxEeXmfFOqRkNzHmVzJQ7YNDFjHBuebx1TpjI1ctReH0vqw3NZdjVTjb42TWwqGj9uHyWVIF3eb9ITbro4FDKWed1D0sSflr0)G07QSRSn3skUZF7Tww255llpKlQNCS5LGxIOSEOdMKCyYVXZIhTYXkuy19XqIVwvkyCb1oKfH6tDYFdfr1jGRtiTt6zmqrdSJUjlQR(YH51zu7tLu3THYUgW0gr(uN4SgGKNPCSeQHRZUVAH3(IPgaPFwsVg1rGsYsShFhKJD1jh3NiAGPzt0n)kLPHHMyeFfMsHkYM9e6vep1QheMWJzKLwT6geMKbgEkDKdrhgk83HrW8yIZti(ZHWdMLC1IsmQXN6y3niNPI286ajmy4ZBJ((bakQcJVo8bzaEfDDpbGGwqDtWcmvw(0Olyw7UN0c7zLu1Vooj3wrCz4ISLKjaDNIz5KYgGmWsYcLgyFbQOIAEYqhgIRkiD9Euc4LYj4ReCIdLbjeBvinXUeYSriQhC6nXTmLUuIO96WBgkUXTCI2F3tE)Eyl6Xcc6MR9y1GDCErwhuJTwJE0IkjRQsK1sSWc1sPQ5ljT1nmx8EZTjrX8X(lb9M(6uf0Jp5cEk6aV7LcgRrru4Cf82a5xGHP(XdJShH)2Vsw(iS3cCUNTlho9fHzGHhqxuBM(caFgWPi0MSkLmpwMp74IQVmzdaHgGYlLg4k2R0BD4yrMB9L8vI8wlCdaOcHmj8SBViTCr2zeCPI0nbJkozcFX45Gt9ISCX7PfsuSEGHDzY4jvdnSgWny2OnjNXhqhFf(8OUczH)vxkxQhn0Gvu6GC86BUKo(ozQYN4JKbmtSvFYpDy2TzLnKfKMnoytQawHkYgxUklBEPN(ivOthQz0fT4wgaa1NZG6CorM(CHSldDWgJzPuVzRyZh69dA3Bw2gAyZoRrYV)hYjCsLrOLUY)GGl7j9otlGMbBJhfntRsG(WzDhfiz0mvfIdCkrVcxLLKJ5utDGzAIII2TyWiswFYNFsz2NH06wvg3etMrmDcVEEZX3vrpedtLfVWSA9DhCyJc9a7f5GNXMowjxF9cOHUEMIndV5UrAVzGXQwnoeDwbm9LIiRXKRH63ED2sQInBifBLTK0eSwFM63iazDkz7fb6byNVg3vvzSJOy9W32CYTNM3Wblnz64qyvT4V6alF)arEdOWgru7s(wBzevfC6rrr7f3ntiX9byuoTL)vGep9fHe3f(GXWIhrp7Rfv2O7rCuq3KZRABE3)N3DbHQdjd(3HOKTbWBgHU68zUhA2taGjTZhgwT7HPnsuTEfMHQjMugmYuNH9AHzFjGC64k8nJ(PJhugauLD(5d9zW4ZHiz6X8mdL9IIz3pkGFAZLHxa6NrNegGaokq1R1U09hAuIQHbVmtr5aD(DEt9oZH(dZ(BJNSt6b7BM4urhNqeeBNswcfhbpvWpomwinFQOui4em1DUUW8ScompzWKYAhhAwsCBErb8xEbs)h2i8ECF2h3MVKljXw06oEEOXzwK3z29Ns63ggzZLnuYkk629bgtEzzwb0(nkhzioysa2FFQ3ihyVJy4h8w9kgGeeWMYzpaVItSy2DHUzN4LpM)YqALGZKJwUco2TeoSf8dYOyAX3Tc8eFx6WouulMnNEuVtRFaPw(4n2sPJD)0WASWyRUVeu0mcBdceG70tBAXHSZQZebnQ38V7y)XjqFI16Oi1vLV33tzf(cwA4X)B6MuWoqJq)(b2ZNiKAqipwhEjm0iDtx47OTgEG0jcWSuZX6LK7yk0wbV)ybgeNKc7Teebjo3HQfKwI5srmE3P8NpvIetpRL8Jrk8wepJ4dsCFE58RDQ5rUX91XnsW0yn8W9ECp(2clrhUqZZeRzDYk7XoJVq)UhBjgNslPNeucoh)vjqNu)up7It(NN9XP79bvAY(880K96xqXpOPu2Q68LKUhpnEGq8e4S(bjP2QS6vR2id3IsY(kOa4KB)yfheep1Uq7rrOS1IFzJ4ghq1oXaIMk)HczbdhBuMkGanRiT3r4RUJO)hYVZg296W88g6cK4zeydXlEEkXQqIrHWzvu5sfHkUncAuCYCaR(USLzkJ(9fmN8UyF(e3M(sFcvVoI7S9S)hTW48SAy3KgCupzOA2rD9Wvs9GdGgKFB7rfKbkrofwUWBOaVKpIwaUrgCj0AoGSpI(iz2y9(z6YSsPtHKaf2dX)KVbqgIp9EB)xBo5kmaBidL5nx1oPQZnI(sHc96SdAVGtq3MskD8HL4zecl6qLGlRbb)7Sw8mkRQvAeGRow1l0SlRd1AhrFFK5iudwL8WE4tewjpcQveyixx021azrWaZiAvN3bA11(wdSRIqYZkVJEeKjw9DlX6uXEK1dG4XXadKFDQzLLJSEALCxAZD)EAXAI56wjO16zZo5WMhPx3l0mZgiK7lbWFbJRwgjHzvlW)GAgwLV6xKKXhdCyQoZr6YcUbyd(dXge3WmEjhsCIIsfiJGZmZTVXjnLRT5UJETSCf3(tdsDibutYNOYchX8iLkezh5B74g4cx9xwdsFic64Q6Q2twusqFopnV8xilIFGD7jmGl6yEihqTSsl260xkgg7RByi(vzf(hp6L6bQ5Zwpp40nuTMBK58)zOZbA0yfLSyDA9880YtQRkVDDng38OKQQzs7yMhN4nb8FoTwd(wSNLBOTtKLxKnnjZJaoT)qc9NdK2FoFbe6)MSjBI(bx7Dc0Mr(pp9d2O3585oy(mNxHfzG61K)5L5lxvKjV6FXimHgsP3jQGUb6n)Da7j3oddAc21iIMfq3VuAhnu0BJMuFA6xPUVZdXHIudYcmUIGUnD4yMuQcOpkBFmgteWQM0I27gyGQiQvpP9P)DAhQwnesYGbYMwAYAXbwuouwSVBPYxFjCZcd0BwihVXwXVxVDFktB0AJTzBd3yDdQo8OAGHQmUwJFEr2WPfeuvzSwtY0iUQyXxVDcqrY1A3NWtt7xPfAmr2(wv)9WiTWKfzLz1PfpoWLEAgvWxbGlcN6Qzyszpk3Mu0pGBFMVrNQvTzlXaSPDxYuV3SucuJkvuk0yJVb4w72p3LmZuj7S(WGf(pi2l0oTMaJI3SFoWLtHYt0GRbbmQLE5pTtmB1L(a1DSjatgjktk)(XfElbh0cEu7d8h)IdBwfOcRfTBX1lwoSR0WNW6Q9z2HHjbfWkgosUfteIV5FLrJMU6a3LOoMRTgULFdTdS8IDJCcDmQS2221DhYBWEvZh7mhPlUSZRZGl0Mtxx0MJ5rj8BtxxxEcrDoXU0lVpF1udUxh6Zcn1Tv1WnB0L07fAz3vdSmH3zdoVOMu0ISaFf3ytTgmZr1Czlzs3cBQlvIi3IxLz)swk7SWzWptXhEHGFH18i9aDn)6zPRa275NrwfLVTXC5x3y3tSyw0xmooQtNH4TnMk7)HPltxKDkCjdrpBEjZxI3zqaFY80c46esiu6W0CvNDlGsDbeRTHI4erOY1lVjRgnqGTpjDm7HOpu3uvD)siOyGZyKxIy3tzm7sFrVCa5BQZsVh2iP9tLKZxcxyO4rAEE9jIuTLnwObU8xYjyVuhvH7XQ6pqmiLJbt(ZZaCK2hgiwg6ZTlSZ61iRWD89CDcDJD8dPwUdC)UbH7aMoBf7g6Z3djH)GuGl5nkcFKs(gcpaykoP8W1LlYQyx5tqQeq4jzMR7j9AxKMphzkGNbBiBklpAAi4Ez4UpMw3VnDS4p9myNy4icteJkzQbU1uQ9hQAJQhtKq1t49g)XD3ix8h(i)6x1josC)A4f7joy6WfB43Kd9nvIKmXzUA7GG(lt)kSXoL(CdwrVtCzxfAWmOB1YH4QHnbcZj2l2XoMTA5y5fSJNJteCVtZUeKhU1xhE2F8r6kJ00smBLvgfQrFVJTyLQpzg3el0w)iHPf6YXTbBk5XI4hkXuRvwGUiZ5VWZ7)xYlNdB(j0VU7YKe402aHjb94tjIuqRtStf3Eeh7(qdygVdxM)e8x17xrrAzQK(Ms7AiAZpPpi6wBYQiEnX3YEov6jOkWz)fhHp9Rkpz(eXT7U05(xGEMD(FqtmjV5(Q4aKxL95YhJay0l9XyPkW2NnX0X5O4NP81WjEfvP16uh6M22tFfsNppVSmB(Lzf3oHNueuhLewf2lQmixaE4M9OQxU8lPRGBsU8zu(6vSDkwibHheCkkxOdEe7D8JddcW7jmMUwlMcRzRRVmRHwogWEVGI1kR42Xfz)iV6HNcPwbenUh73wJpsIDi)HLLTJJvOLl)Uc7P7BBp)xsFh7a9gbhjkkYoY71okIIgoiWnbPNS1tYutWcQHMKXxQi11d7fWBH7WGihxFcEOnU9euiznpEXWhJJqHo49yjwayGNBcb8ub7EeZXjIrkWoyUr)rQndn4P3xi7ROHXRBU(0s7UuzMn6D7f)wxSBuf3uDCHGcYB9(uD7iuGR)ZhCYkjKbvZUn7sMAAv43Nlb0Q71)HYuUoDhCOnZ3(MSBDZi6TTmFZEz3UGAVzPFuKE7WbAIO6OZuKPkzU0rZxKHMMTJTidUKVFxKknf0af637sOOldHPx0f(9Zja9ECqVAVf3Jg(2MUoq6DfxeeBnEtgWAsp7nB7UEFCK7gnGdsUiBvhzi061gUurXPydOQq1yWUxoEyiJcoQKEhOsVKn40Ii)nBR)247ef9vre8krXFdxkTJ8hN2WVZACD83WLYryo8t(05V5RE87Lf3GnCop2iuTsCGmf9UuI4z(f0wUbMBkXfzFxdTzdWnMdqupD0Y8kpohExqzGNYo5FaxaPqISUM7PGh72d6Pg32GVdBI8HDYVNrSPQi7OVM3Yh(EBi1jAdHkeffOxwIbXkYge1mgpMn74ggimiimmGzjn)gkBFADTcHTPMhChr1zbO(uki(cx)IdDfTBGLx)B7zYQhgbGGKvRBUJ06D2b7Xs8r6Zz6iPMo5G7AQSsMbQKjJ3)9606m(99ozCQKRU8uRvQlEfdFPSn2NYSktw6p0z31qY6uSz19b0XwrgFUauTwtSZQ5cQ5j01oqT7PPZQRyjogXPUfkzLWs4h7Dnv3LcMQZVin37LCVSMvKp7(P3vxTEXDtez0gPrUhiQtEIR6GY1lP0EMHoen)uKCMzGE(7456yfhfgaHwHLcZ0KsTQCtmFlt(cMhhfkhTXEXZMy2A(FsAz6DuF3z3yAVnKXgUd8yULIjzlHCWCfeEwnA1Q8etBc14Zt3jMtIS7zHn(scq7j)xCyRcySgp(nM7SPRY2V3nSo32UBmCdRZR0iS1dwWxW1iKlu7sKUcqGGIjTXZHqWnVjTv6KiSPNbPH3w8p1Cjuz9Ct8taNNNNoFUyZegCLmWCdF4LEVd3VacyF5CEjOqSgqXUc7I0W5sIX4llXj1nTJ6lJYctSBNyHKFdbDuDjYRlk737DhEGxaFeOfpitND2ACR9b(8ZG5e6KJ0KurwdPMxQEP)RV8DigFp9QKpFbzWux65pDZOFVaaquPl9dD3T)kaPIZVImNMsgzOBxWwmgpSfl0gYCXGidKudkHjgJgo8ywTsASZmK2dbeofX2bpqLt1BpV5pUVYa9I96zlncQAaLWaLqDgmrXs(Tkq3QaDRc0Tkq3QaDRc0VBkqLc7J5ZZhFBg8SSE6866zQ)up0XMPeFQzk2i876HL62RLWDc7(p2frGwT2(JzUHbv3gKW)Hu)nETG93Lk7p9FGQSFFW4xqlFFuAZxx(jspTJg904wLR7Us(zOO2a8IgB1hOp5zQJAZ0B7J7Y3FTQT1OUz6BLM7Hw(ykvyny1tp10VpCZ0t3ZcFDLBWEw09C1DRxXNrD0dDIZKEg3T6z2QNzREMT6z(oQN57J)HFFv0y)6u049FZkAKtILTQA(HlkKwFFJc5wnn)Wg5r9GhA0ZOhuudyYMPqr6kD9hVWn(uoT8FpHvC6yAsEMwAmulJP8IZKgN3Kyj(wfHqTQE6pd9bh2STET7NNzzADcpBMgyJGI6beU5zJIpqbFFTTk6kFBu(RrJ7RSGdOtBKEioJ7XBFa6NPCZ4MmmYorRvAUNfow7(8vz9CHBELA42S7TXrWl1bVAAF40yYKbTldq2nyALo1MgnRY4jkxN6WrSw0KMY)Quj(wy33iBYZanMphtYnOhyOFc9vb4KSE1aBphFB4nRSuN1Qd3)nAa(I3QUyR6ITQl2QUyR6ITQlgvDrVZaZpDPm4BF85EASInlQCBd(2pdbF7vUlpMYVVN9w4Op0CMtvGnprbnhkMFm3VhnXJBO2EDQqgXGHXT46vV)o6ucBW4XrcvN(7LX(XRkk50Cc1Wqkag3X4OLnA6ZkACma0RBs)m9i4jHzSbbJR3m38Mu9IJDx3rwDBQ4Vnv83Mk(Btf)TPI)2uX)7wQ4hqu)SyRI4(xpdBZgLTj(yxIpgV1J4)w0(6QlXh93M4J)mK4Jr)xFg27SvrZwfnQkAI2QOzBg2)xPIMVhje5puhKR4)BwnZWBVTTXAfVEl)zwTB42aT(FIB4z42GR(d(Pn4h8yQou3AW2ZBWl48giFNeV96nztVEtWBnB(9R6GRLuFXp1ZuGURY0x29NQJOHP3ZO2yrJqChKoyG0DhWYkGbiBnHCVFr(F(NP1ZpmTnfURxNikvZ0FbK53NL4f309aLlboPwHwOdW8csmy6FhVkXwalv7vuGvgi8AzvDOd03iLBL811PqTI)ISLeMDSM24NKsEk(VAetpH()hXk1qrEdzvNWiDn9DAWARtvb9)TPAjwwiMND71i2hYsDtwtB1xU(lzputWeRW6gKxcCr2NvFF3RgN08WYBYRAZNHPgkuPRi9sdyLd20e8sYI(Tv1lPV)8SpxDnmWzdKBN(nHUHpwvYHGNpfnjgmNy9syc1Gv2H8Y7Fy)I0z3)pRk5vetFAbr8W8MvfPpCA18mcZ8sALFaRPO1z3sWkjSHek89S6y(1K1I5QKok7c)vRQMR(MYewNKVG17B4QSF1D0jFusDEB21PZ)x0kIW8S05fpmLPpNarTavtCBr6YmcfDXAK(nRoF1Qc8NJOvXIBxxJFxBtBD(9WR5KKXCl7lzPRQkVoRCgHrKvRvZsRBj8CFgBeNKcwA6MUEbu8tVgioudlYPe3wCDjDjPBV9b8JIXbFdH0J)kqMV(gGoJfmoGYnLcec1t8PG553sirWQKJhVi(plpTOrzrKv2tze1)Go4pch7YuxAElwNMph4XBEuuq7pR9och3P5nmDNMy0jcPKxFDlYuF)dyTTTUQ8pZOd1LvTFHnMRBP0O0C6S5oOsnzGdCcQ)Tf6W2obpe7t9PCdLFVpwmsMJSI0It3dSFZXcVhR7MbXjlEw3o1GfjSrXrsfE3fC4qDfLjpwPTHm3(n4lpeUAOj6dGIEe7qbt4jRj8Kx2s(LucD70Jo8KF7uyO)v1uAsUWosJSpBLxPHzfKjrB3omxQNTUUPQEV220z3jQ)OGcCGX7OVsyxAAiAB24kiKCnkcR3Ts1I4WKkrDF6B6kBRoH9l3cMUT93PFbF00vpUVm09b3L2sVgSNH)Jy6)GvCNq9EOrSxs()OLddOSxeaLh)gc2n85ScI0PPFLwdylTPSsE0kzbzqC91ewGBO(V5MKpNOjkDE2HzegWs)Ev(lwmlHkA0PenrDfLiGI97v5y9YI4blow4(uRuvJy)MU8CXNY8Dmxdj7nfgq)yxrKMihsWkk7wUoOA1dmPcXyHVNsu4LSwOgC0quM(nrZmbmdBowpU4ncQ0MtgiC1zLly(qGdVluHpWJocO3Ii3VCfR6VgK8)CsY)ZPVtBH4JzsnQHVzQOwLPV0Kiv8yIKjjczu5IRnsxWcFY1zZZBb1zFe0Vc63wsqc5(B0MEtNXWmpKARiiQNRwIFCJCOmUrHw22JuOdJ9S79EgkaarAynNYjU7Zl4N01mIhfffS4drR3Bux(pRKwxQMWu0SAD7zLtRwHg6tR3kuZt)q1IPP3mDahaYHccXWaaM)DRaDvDf25EzDlr3Ag1Mafbft1IphQ0zps47dSWuRYoo02Y3BemclFNDC98d8iVz8ierlA)Wl26Xr7eg476B56zhnq2PZ2v5IxJJMIxZVvM3obaZzXpKxLE5pIGQqqfYQPlx0IPjvJ5QSwQ2XBQAyMoGEFJ))z2TaVDlpmobS3aVGiP)gwKrVP9gkOHufILxHL3VRGegZKgGFyVBikdUz)(vtVWipxB3qhFVyAzSMf9n(JSJdS6kOt9EmsGf1uj(zh7gIXfyD6H57izWEa1POdiu1SYwLWIZhwcwkXp6WMqSvpxpCYWN69RvvT3OSZbRQ(swTCOLGsgjXt3LWqTRQaAZUaNOVoRM7)jEzYBgrmNWC8RGNGK)pL4qGU5rdFh)GkbVox)ChEHtaVDob(I61Ri2ZKo)HEUM1r8De0BxFwrZcAGlHA2hgGVn5OO1n(ePrTcBapFtbKtRbJWtZNdvJjLqplQhwcc)uQ)tg(w15NRDxSDD9d7C50HzZvVP4v8qf3vfUe8oePm0nP2B(a5xhWvrmfMGVtSZLIQtSc1Hw3W4moxjc0L06L4yfSm9RhMbSWDxMl0sOpT(rJvApWftIgPsLUQF12BQITsKgMA9hYIAhiXXinP)eNtcLkoOilTenPWv6dyLOVEropqY1E34E03yXWueZjHq55aNpxoQJkjkZZujdLaeklRCfpQ1u7ciJUPsGzazuj8xAdbi46Iul2nEMk0xFaBAtxos1WcR0zx1Dk9Ke4z7qah9OhtdLBsW0rhpt7ks9(GU4vRa6dFTv8UWsYfyimHLf0Ui5jeLlGTNAZPSwhxx9L27AW6NiQneNGSWEBbv2uxE1qwAijHTJylw01rG)e0G9HQzPQBPjXSCc1(CQ2igB9ufuuLvFiIeOmLYJ7B4pF(1BwB1XtDfxva2AITtaN(8vjBeDCEg4Hs28ZzSOddOT8CKxs5u7qXPne8U9uIZM8somlUAYTGS6hHa4hbxZektztWpXnNKdXnd8BLUinvA6DL8RjATnjmPCEBOHNk62RyxXzEqWEfGT84nk03kTGelvzd7fzot74JfBXqstT5aZYgQ8vOjm5LpX9vPJQ3PXWXXWk7uzXOpvosr2URzVQ3RPSvqP6mTXejVdVEEM0jZcTKgRsXORkQ1kYJfBtu7nctvcyims1N)9vdp)owbHcCz()Eb7FZc2qx)GqsuWM7wzAN9KS4QdOJlhizpOnN9uPQcRydWqBUcLSBOpezNsebAUmmh8jYh66UfpX2(QssVyt35nPJNUKySw14FIvwCPrygq7Mib7YQ0WHe)3wjs5dkFnfFejlKFgIh4kiwKYQjvLR0NCfYdpHSbAeBpSYqLr9MKS(kylxPdq9tg2Zihxo(fmG)J7YiyyP0Y2)0Ufriw58fsUB(xsgwth25I(Pzzvf1FJgfDhkukNqdOap9YTVel0Ef5lKpiL2mX1ZtRBFahJDvoUnHAk4Yv3Kt6Aflc3scICBE4Yle7iYkGkwRDhTv2FIiwljJEpL1om4hwnBgfxCgkkPObMi42NkI7aAKOb1iGTpFJy6zMPeirmF43xpJvIEdviRX7VqPeVBHpRxrAxJ3moyqeHcWo18Ap0agjaN(187ozwkxna1IYTASAqXReMC9bsYyGVkXg4f7SPINzcCQIYKYgn7aReY2DvE(aFFgwoeq6m0Y8ttxKpRZ9h0mojorIjEyL(h0jHrlGU48OoMkpCTcFVd08BQUxez)xUF)M8rP36lSTqYd6R4UwZm(GgmXUn)EYMOJsRdiJRlAai5ybEyu)r6fucVGDhZNe5GqeS7ad8gXrdhK9xM4ifcsTG2gnlxfN2KZjrQRukSsplBS6dJcb8Q9UrJabGidYVNZCYrSkrLIL)LjdFzHR7dmO1am8tH2QZQaTmtxXhMdCYAIHGk1xEyuReeIj65cKSYzQgVRKOGNl3LtggJogZMgPrtMyifLehRHGFhSMmleynbUbDXMWR3jSNH0POsXMrK2JTX7AZdg6dWq)RwC1jIvLviWENlVQLpDzpALBUly(TMZD00T)1FL0ME9TU4Z(CckBeJekf3up14MYd2J54M2hfY)LhA0D4NJz8an)CJuQ9BuKs9EtIuke6TuY64jLZZNL2wvByGG8XV44Eo5VH4EgHgJwUE5Zl2NUZhfiXFx1qJ(E3nm4OE6JnknhrOjeYMeAu3Xnb0CasnghuV(BEms6184fdF8ZjsPgTHz6gf10OX9i(noWPt3OiKo9V1iKYnYTNem(BbAcFAN3G9JFAOLPyM(wh00PBEqtDOBCHK1MIqqOZQT(Ua4QlGQMcpXg5OZghzv)3SqR6(Dl0QA9)7LeEvxglmn4EdGB0g3cTbJD6Mhmw3Ni37vJaip7w1eFih3(ctcUp5yGPjoRAJ02Gya)mD9xxqEny5j6ntVbpp2E9cDm3iF0mEraA4yd6doT2ijR4enderztnykhFrXk2UlC4xtO9JeY4xRkSbBg3etEhmsGrhetzptXuEmNPM(eHuU3wGmrVJ8YH9BquL15J3eDSpxvQ1PPHrpE84LQ1Hi9buCqaZhlIM)fg94X2jgDBabFl2L3JNErrWy4jC3DZIES(iyOpgYMJOWWtI6RkWWV8GvBmaTetvZRNvKnwqK3G9av)(nOpyYp1MAS5B4YBzaL1Uxw9INS1UQzGW7Dy5oHsSOrekPan6VB)WfhbizmjRNkwXVK0Rr)2iI5QdggKZicSKfGbgCjfKK9lYWJpagqw)UOW63f5vEKLfHrGB8aMu8qJRHva(rCk3pPYEeDFscrwSUoIJyg0W9s30ZbjnMjLeyM(yWnPHBeAVWI44TtqSTRFKLJh5FGYrD(v31sgGz7TklzXEp6Nyan8(VEOjMd(6Jz5JBp)M0dmZdcPM07Yqka8S2zmZMOAioidq1eJrtkM1Msx4NyaVrtiK6ToUFPUv3JfjjRSQlnoM13U2nhHu1KXy7DeCBympnMuMgYrnzBB)gBK00WtHzFxKCKbwpthC0eWL4ThC8kGGWm1uttwoKGEiksZsLJqBy3rIWkUBJFCJOPbopFwFebjebFx19MNxaq)lD3P0hLDT7f1OzW6thj2NtgS(3yyAhjjB24ezvRk8)YtovJappRugLFmHnf2uTo8g1BZtyzP1irtnA3nnrtJzhou14CXT3rkoRUVz5G6lkqR)TLjQVY4RAkRu1Ketp3iR(JCgOow4vFw7b7BzWvN86Ziv97Z5ZmMRVSeyDdJ1AOm1TV9YrDk54)B5ZLTLy3I(7nty7hwwFP5upFqFbjdRwJT7fZ2OK))S3ZAtTTsY(xj)bcxjn6P5tecohQLaCbNZjNTovLYyRa(gJeRTj5KLk)3V9J5rp6LnSzz3SBQkfk2wA0m97UNE6Moqs6D1OMoXntEuXYT7mdkuAvd5ttNNx0MBFxhHoTT1KPnf17GEDevzZBzvdlnZfZqlbnEu0URNix2VP8DAGyuRPz)WbFmNxWRt2wWR7m5nqvtnuh6to1tuC7lH6hocia2MOISZdbHupET4NrPdhHWbIQQCXtGR89hExRhiZm(ofF8UdD5ULWHpQ0cAGun0pC69gTVEt(6otwXDiQA7SFEic3N(0onk0Zwm7hE2sf7HtaSDnHSBfaLDCdJKQYmUMg1xUy3xG47oq6DfrPE28JvpQ9ePRyZ0Dkv)VMWWpWwdiddFFr5zW0f87x2C)y3XVHIu8)IIuViUXQ9hm1UBPqSPB07qS43wQg26821zu)y5FEHE5OBVBZxhgniTG0Go6jFbAeze)nJVZS(UZSfnkUypxykY7uXoh2QunFE3z7IxS8fGYHZ57U2s3EYzA1EMdxhEk70vklr8XoVEXA9XsxqgTxuUOAHeK6vf7(z41)z41)z41)Nz41dlI3l0xB))GHxNkjd)yXY2nM8rFu6AYkN8tU3)9L7TBX02saJKfjozVW8e9)k6Lt47iR8ok7OT2K(4DBXLYfmLUoxurDgvUoobO9enmpUUOUkEjDgxmtHib3zoWGKpjlL4O13DWFL2l)1oLpKDCuIE0rylcRks3c(W96(o6vnI1wp7HuBM2hrk(t11kCsGOgBLzA)HZdPVB7Xup5LzOyoT2pLSEK879TNu9QNAl55pBBShCQd)47KzU9bXRB2sHL22v(wo4rDDuRAe0lP6GN2gf192M1rCaLjLNes1kqyDLRHDQ2FyDVD6VIm8Rb57PkscsdZIYJhQoV0FEJUZhi(NM1gDLGODREzG4p2xPuyOd35UUXDDSxADBYtdHATPx1NRihdE33IV(PS93Ywa2zGUk8LV6Z024Wy8ydD0GbC(XSBH9ynxVbNT7OKT7g51xGk70mVbob(Dh1Qh1EF2mexDBzu7aXzLL9OmwSNTMiFuDTPZqSx8WbGQ7ZGFF1wGE3r2TDAx7OMx1ZjGzOW5P8O(xpzBhH5w2s2rvgQRDQtYl3LeM2Bj3aEX1zmO7nk68b(SEZ5pdonkfDV6)2JZtBdmFEDi0WBV6hHW50TyT(K42JTJB1XV(mN8jMoKTT5PN9bVDksQ8Z4AVYvKPkL6v9m5kn6(CPeTDzjUJkjA76q636kVQHboliDVM7ifwVsdvQ9EAVfLo(YAJh0VNGERnQb9wmuLhwDegeMJv8F5KIai5fnIY2opvBhkC9mDG5vNJKiFthyM(YN(u1fsbcNHJssrsCsErE)vD2Ku(1T1k3Bety4JXctdBqz8yXFHY9)XaAIIEkKc2aF(KiLAxqCrtYau2MYMSAKQRexYfNg10nVy924F5YAwIdhRKmEqobOMWI2a5uPy2bI0ND4Q67mvw7iSyBJfP6LF9xmsymB2tgRu287NJZtVwUub)U0cqmcZr7f5mg5LFoIe3AXQMr2COomd9PNF4qoTPBCu3uVEZILUKVwviY9ArwnRbpl8Qfc7szqWmvzGNlZuPwqeyqMaUjM8TscBLOChflY36CthZPDXEaBvyvZlVDb3mqOgWsSZq9Dn4nz08CYIBfAkfnwfLWep439oTpHgPCuRps0osW8)z6SpPDlt)dgeiXxTy2KPvF6GRVEv9yhfOMQyxM0RMUQ8OLl2uAZopI5mcm2a5oMv()EFjh8HFBXMBo7Q)VsYfoo9hjnUapWK678QJ)Sba4V8EFAwZAg)PF3)jePNHfaefBX0OzZVU8JtVF5gKXvhHuRMzw7DUjJoSJ1BMExvKdzIpAJAQeyyowy1RiLvu7JHMPSn29Ioz78N4WA6ecvNWjY13l1PWNafVliMVhzEj1lvKPqLyfKiNRIdoGNNvj66ofmow)zCgKgsW0xz7GafYiBBw(A3IQmsB9q7k)eeuMFuAJJBrPGDLoxJkCp1qP8TR9gyC3d7JhNF4KfB42DJo25W7WlzHkgvd4EdJv)YkW0MWm02zRdwkeGFyJgbiOwCMJJtNl2WeOHgfoE5A2zVtcUt0KxGQD6L8aAzwwvXzDrQZIOWeVGc7dqPsSFt64MfBUQ(pj203BCypQnJKa8uiAjdgF01UBZSfn0JjDdA2U1Q6Ygn)U1NwlXyCvLW4q(j1Z(u99BoynOl5lZrptwvVSfxR3sn1tGLaxLOTF3TmnfJXPRVbBeh7Y81YsWl(7(1QW90EdbGXp9ltxtlgHnjdyssMhcBx2xWz6Gk7PVXr)iberj(y3MulkFYlxmX0XJOHD8uwWL4SGirONUquITiPVBpoJb(V9gyq8yMvwHNDOfLRp7SdN0Ke(3nQuJBCQbyxzb6VEuca2VTO3AWuxmeD3oFAK)zCG3lfPiLYDVfPUJzBIPlaEtdJhvA2ujbb4zjDa8oLdRsH08p)ADc1wJquLL2Mo9Eg7MVFbbX)BOvbVT(QgucWKFgjn1fz9WwAp2oXzUVuHTtce25b8txbCe2vkWpbTMxcbPjeh4j1yQY5ZeM7qgHodFZI8M3n5pKIl2LfJLSI7lz30tdNTrU2lSgtk8xhauPXJjw5uEDC0HpV2fEsL8wDnn5jWfk0Xo6mTjsSDRFCbFiBiQfr4Hilk2XTsQ9oKR3LBpQhVaxNyf7DwLTRa7ahA5vA13HT4VFu1jTiY4cFT8szgAKRW8IaHom3Bjr8sCuCjIAXgGYo2iSzBYxKU(zz8t2x35YCMO6fcWmH9gYD4syHdoyT6Fe6nvJXXDKj2nDpqtbBo3QBxor7mpymPU6gQ)vQf49B3aUUIOpoXxB1ps3luCEDDGRqJMvRKZjEfGrqeFl)31P0sIMnd7upybH89sJHZ91xTl6QTB9jQkI3(F2IxwaTSszeiK1WOogR2MPQVUkREB0LEC7Bo4V7373q7yA8v8R0tMtSG12EMpJcBGZLJd2grfwBB7q2MnPtoL8Q3pOGDVC8ptsz)667VAPUxM1H)pX61VJVnD)wz1GoaZYPNRaOrijpRYLoL7joY4bvdYXE7O4(Eq3WSCYHvFoWygwGbrq43gF4vC5XFJ7IzT1TqUKKruXI8JtNv(hhmF(zvR)drq0(JBlNVy6Fq36F46pF7nzI(OobYZkNU6rOdv7F3wjulqtneOd0cZ7UtuCsCInf2mPZZgyA1W862hxUeDM3VOAHnWR04kK6ZHEvlDnwPvF7ts7ziDeB5KnoknS7qzdq1oj8ZjJwlhAI1m2dwUuCsvJKgb9E7om6cVLxUfLWHDcGSId1vh2ZYDCWC3POz3o1KTvM8EEqYKoI1QGjg3aU6sY(aJsWlVzr5Y5UjDM5hCfPbhQZDYBi0wAhrcYkXjYLsmuE4C)YLiwR3edEBzZsNUl7I8yEJLQylOLApncld7okn(7YOuGXlJCrwDxBe8Ew87evLik2BzogTCU8Yl2ZIDG1rVgScIeoL4raBxyclE3vpEDUjXY1BVXTrEb)XTsZDZ9CHvczPHDywfE48NyRYWWl9Dvw7(wCLiq6XoXuXoWxSjM4(bT0wJh8at7sLL0QxYl6NfSS2(c(sSjIuEIWuTwO2iD6NBREztuGoqoE5krJzLnDFK6vfczSZNg(ziIv7Ui9ro690HDJk835GSrvL3Vz10L7MoS2zTxUNI7MY2(h)usPyJupUI7pMT9vCVqLtke())M13ClHKRUpgQdeKRggI((57zIaa4g5iZzmxWAkBsboBtF36sSZelomGEwf3imXRPoypScpVCZ6X7(HFNJpmJiJ18uIPMxU9y41m6Jz50cJDEl13Wj6mQz9UbdJmF3fTZKGuTwwRRiJXwf76tMEv5sowYBOalT8(1t(sDdplB14nmDUY10(GmfOE4GBqJXXvGeMt05yaBdan3SnDwxXv(8vLFEr5xyJcQnMHGBtI2)ySGImF6saHzSuLfRRPWAVJBobyUW4PBUibIP3eBXPXz8d2yDNqIuSZeG(fmba8nUBaIhcvheG5i4OPGqqbJ4zCpKszsadciECfTxaJD4dWi2fRA(6l61B6C3uVJPqhwBuOF)BUbe1Et9Y5(zp2DlxSzmfaWgfyvNAcVGfL4d6MUc7UZBMIILz2KshPNizlHjWHN9UtN8HZp6cCdQfDFCn7CKJNtJ9keeSWKVCNMG2csK(HiUNX(80oQw7AzTNtmEun69nO5YMsCO4rNE2PhXJULoM7N3M0m79vfHX7LKMITR3GCf3kfMPRGkryIJH5lHc(xCIOFsFWh)4I)SuV)ZeAcKH8LU140LU8Irxjn8)sCeilJsgfMgocGtfVmm4LHXzpufheTFvoilfKnbKXyV3SyF8GYuWriojnyuy8dvPQy4RJIXBmnKUfL5wsYPBjoaE(mGfUkmKgQe6UJdsm3xb8UHHkkehQOCCOsXBpowFlrk(wIdXVgaA0TG3Era(xvEUzSYgfw8qvwmokrj4RlpeULOGy8rtytLshbRpAedvPWKodwwvrf4DKhqtXctOi4xTeYm8CaEec2iFKmvGgWufMPmGaXnhlU5TbrdGPqmcrJX3Ayc(34ufTCZflUmCXfNbyrC9RcYOfxaT4YmJxkHHsasqazdV30Ku6LJ3wqUewb3wya(408lIETP4WtVC30leME4pMrR2GC8oufecpcvOvba09FaOYtW3gUuzmtuiovlmwDY4hbyzRikAXejEIeKgipfwqzHeLfT2cIKlEfs2btUc8pz0naSDeLAHG0dgn6RliezcYBeMvGlWOcnqI5G2gJJHvlrmpvz47Mb5H4ZLWZJ4m7klZhwKgHdzirCKsKbfQCcoJrLUcWdaewH)Cco2508iKqwbHP0TaMgaJtOQBsndcqsxom2NMM5n4uYrqwkH7liYVC65YdSprrZfwVIaOrpA4LLraq(2arw6fVxonEbzf4qhsuyeEOitI5KuyrzWqMaeuWZIZIqInmWmLzm92qWAsSu4(YHhVGiUtyjx0ZOIcfckr21e6LHmTGZV0qPIfdf(kbHRaJFc9AObmpGawkPyTmjv4wOVPhaE5riAjlM(T4y6UPfwAUCKdnJmGku4QTiKiwiHFzXezNkIjwt3VxjqrzsARa9GMgTfrGet4orX2aiqYccJija5fKe(KybHvcQzHVfeauGa1iImhWyfY5ASNU0HuaAiSsLideoLIY6YPBvrZleJlM4YxrVKegXhfs1rdRC0W8lNqWKfGIzfWFuH4WNNr8OzjsSUsYBKqlAIFM09ehh7yomk(8a(S0OSysLAmHVcKtOmp1bdPAZSQ9uhaECcIKiSNIMqKwHqkJbja4wUhlUvoQdkoYiLrcjZidhIqHgfm3qclGmvcj9ig2fXcBH4LSizadr083HBHB1cccLSIdPU3UI804TtsNK03dl1rBIs62Ot1k9r7dZuKjBbsQfLN2oCvLsWRuspqwoBxwUq4oADlkEHWHfehEConYbEkn8KgSlpGNKzu3sgTocOPDkXMhh7jX1tV0qgxPPggIHttnO2fUyKAq5T8qmfP0pKGyjehHsPeYrJ2gRMgtLUd8lSGzpXBdjHUcVattsHDaDtXmmYx6Q3AQVBwtgKUlsSt9hZTy2jBDY2mkrBwKABGDZeWtLXag9JMdU)wSVXmMss1msUryojomxBRhA8BGquLA7a0OTABfnsizuePwfHpGueYpS0ejE0tfqF3SMGpA7So0kEBludOXtPRuIJEzUvMBn(nFB2sRNyr7GtpzecyqXBCmTerTbZl2IrV70xF0fF4vhCboqRQ)cgXUuk7EMIbMqufet4GpBIJ2BxSC5I1LZQRMVEInUouyy446GH1z2NePjBU4owvo9t4jvu2HrP4vAJJt2iBTT4O)KcT(CBDOWeXqzCiZhzl9wXr6iVofpZQhSCPUZ5CXXV5xMyJ2j)KJ9BPLuOf3SCN6QwC8bH5RlyFfUjnLJZrCmME3DZQVfZ0Em4m8guQlSCs8Xmmq5W08KdE1rNWH4sgK4fvlUD6DueNU1()ZPWa)2Plw2tJCYV5GIWK5ZRRE1MkXrHiIgK3GjIcSA0HW92Qf3F746LlQTPKdExhGpohASn3YWpaM95E6nxZWAl6LM4)PRu70gwnD2geMBNifMkYBLD3cEGtct95bLVrx6Hft1Tu6SYAoBB6dXdObCV0qqONQipwL37r6bK(KUhihcmdjLk6p9CuJ6SQy7oOQBKjBnM6oLa4)Z4ktJJrW2HRM(rmnHodXf2AO6H4sqxPvHBAYkE3XF19B2qhWx4LSux0O9aI(TOvGEyQEhhsdB0IwXmbbFjWuhEbJTVkS(I(6fah(S7xUbJOlYDZ9ON1)T7NUQSNQuu7IMVA0hMn9oCd(MFgaB4a6EnWFV5xXdvXr)5MvtpU6J6YTiGFFfSiVEfqGYYn6Sx4OgD)6s)uftVq0XzwbYfVH3Df8Bn7Z3lZ5WDlOEzaNz3gcg93RRkDqJ4rZQHf55RkNbKW1vD3cDniHgLNZv1BMUPuZyoUNQHil28m3esxwxXDVbHniDcxpF4T)eP0wuvY8vo4iXkt7S)Y1m4aHH3XKkJ)wtqHlJCMTQE5Y)AD9TmWgFV4N4huJb8xF)oEgn3VzBcgiCUfwvL4g7AN4S477RO5s5C9G(GUn9yexO)6Xu2quFxz1BxaZQ3wwD)zW)D(CqClDmgSII(RaoYvAneitVen6qeZTMzMM(5Y54YcZGtwxTq05RME9AUDDC10Rr0ZzvLW39BtxvbijUgmO)LlafnGO6)EjV9rl2uE7YYpxUe00i2nqUfvm9ArkUtJWHOy3X1v(7gn8d6tye)ETVWdbQNRRx91lrYOhiK6HaC6(BrU310wbsaw6Gjbexhm)ZGexGt7fa96D0Q0(78Sd7dZjJoy1T1RA(4bJMCt5lOF6R99Oao(3kNEhmhEX)ZlMSAr1Nk3S(jnqQrhdGUxCz5Mx8MYPpTjt2i8rFXrv3GcDrLnpryIUM3I4NL3FB1A7b5g(Q1N7R8OiYCKAdlI1TpeqRWuCVvyvdWq9QZMm5S3EYrJN40TKnAYzNJFfdh10ta9VblZ7nRLIQbzsei0MwNZrQvD)FZs4GunFfKoRaLRln)2fLObmhxXuvS8h4RrLpNwF5nl(4g7WC(IQQY5MBLlY74OVynPOqpfxuYBOLw6fR(GoNEVaXMRNWCwmL7e3MuBA5dtV(G73uFjZ9eAkrPxuo9AyEYtXOidKHthb7lM1cYkUEt9Y5gDH8MYXgrD9QPZlTfp1j2Z)ZXgykUHWxRRohi7j8AUI2x5LtVBnRpKar)6I13pDjPl(HtpfDioaJXigo5m0H4OeYL1k4RrFvIsbxaWRXGNN50vfqBaFFwm6TtuCsgA5DeU9Ej4N5iSIUeLJrfHgp6AaTft4vmSh0Nv6Rr8atdyAGcJPm8C02nqxt1ZpycadBO(2PHfUIg9dtxYFk4UIO4MfQcO3wEsKQRRIrNUMYEwBUQkstJ5R0SeVsHDnrPsPRrzk(k6NlcoqVzX7llJVMR)m6tfDvpo500oOGaB81V9W3WqcLNqqcWfPyctueKtHucMLXKx)X5iKa8TmN(SktnWv8(IO3boc6R44c3qkfdIym8i03hWXwiI8XUa8ghDAmfJb7J9V0OLiUMgGPTrZR4kMx1jPPeHLkkpJHmHP04Kgt0jXGnQH6pNZeyeKf((yA1MLfwWx5vjsYQVQOVNdjm(5a91ugYZySukDZEGIebhoY8qkKmQSum0hrGXYC0hbWggDHckCZzXb5k9vYlwvwwkVU(lTLo)FBO3)IVIUF4eh80ek(9skIr46olnrle2xQslHYw1Z4j)wRcLuUPnqS6tnvBm2yVg(eKEjWkXpn2Ol8sQEYVY0rSCdUwPlo4JnF)PGY0x9vkGgO7gghjxTQSA2xzfsFZyPQEm454Kf3TULHJ8dGgpWVlwnn(z(HmFUlZ6m2j2YwTgMH2PDy49mb1g)I3uxpN(45RQ)iC3OJ74h1A9FbQqgEdVDX6zLa8SQeSTOHzfoloAxmnq)uP(rI2hPnRXVrC0MY1M7D)Tx1iDp9AJA2c2EKUVZ16P86qi)ZPv8HLwESa)Fz5YpoEXkmx1R(06dUQMR7bCMlz)XXM0MBJ(yu)6YPUtHagzDq0CwqsEEuSOOzqVo9e1LEAn)(VjGMn6EZUoKISvzX5c7VTA6DUk8A0O3Doz6k4IPRope6DCx6p3pbdNNYfTmWPjtSaZgvZjnSoFc5CSImmpXubHIdnvWF(SknEv9TuUDE08Rl5u(uNOWycOU2Us0hOagfamS6m76IZo5i9HkZp1InvTUZlxDbm9sA3jc1H85QBTgLsZ2Irh9RN9xo6IpCW7EZBp60jhm54Zo9HhSbjvwc3gTyUUT1hoAbE8bB2PSM)OoHR4XaC(R8dBdMwzaV3AmlNccYbzQGUrSu)dxlmPWsS7b36bKmdgqgoXrlPwqabF6lv6Sux7NUgnGHSBTnOJMNY2QrOJgYAdhCKMQtS4Be8LRXJCLLu0fCx9Hmz9UMb7ZBEsDZDhYu5PEyCRz57REzyFttZzDAd61wmHzBeyUyX80(EDXYu4p5aeoPpBeoySu3hjGiBkIXnPfuEdgrHMj(FaeqXJy35)pg6NCK(Hyk(ghmf4dhD5Kp86JV8WJp)KJp9ObKizQr3D8k6LYQ)cdyBklFuE30o9u078PD6Cb3hpXZp1KJdcZmNeABFlIjxBW9AuPIWTPlg8QIs)0aTxdpoQQUPy7dD80O26KY1XQ(noa0NFWjh86Jp9d)YzN87dPVl8zsSfaYjpGaxrcrxrcccOnloc8IUq9t9E)WQ3l65sVhyTmTL8aDeMvhXk0R4FQV7hb9DV(I3D8R)WfGoVZUyRwG)mrpPuzP)uUZpSYDEUe7akNWC9HYHVKKSmkP6WuzaeavKOc(PaO)9xaKniaNdIGo6IFDRIGupxYGsJv4McOYur2EGXpfg9JNrqXpBemPGuimArzkms(QKKc8mAa6YYWeyubEV8tJI(rqMu(Ol)LdE7bNUJwfv8mrGvKf)tXqpfYN))27QB32gPh6tul0))4CLBsKBrtAcI9UFTxvOTrXXyDKnSCA7xlY7(oCiNHCgjf7fyrrxSnxQKyjndhYdPjpNFkCdf8dYkjlupIOrb5jWxJzI6NYFHe6FbEDcnLE8aLf6hvXSv4QHVeeQQBj56GyyX3GzW4xMu)8BsLo5YRE3B)4LVz(I)35t)9ZV55QLDY)DQLDu6pKAzhwMHZ1vwbn9EzwUHVNfuy8WMql(zP010ZnR45xwVC1NSkpvEYjmN0WClwmnRAzcf(ZUDagw2RQEPnhzYPV9z1vbHRBU6Uv53Qc1oF7Yj6VwA3pLmz3lm(PAMJDSRG44OCrtTY6Kf(r8v3Jcn1F)8QN1Q1R2I8kvLTbY19U5m4zG6jfnDFDS0RBHRKvGw8Xarwj60G5o2SMOa6hunl7kSyZGgjWQWeQpE8tGwWoSxVshMmv0BjPAkiDCwGYNGt33nZ5KdpUjrHUcZK512kX)lptTCOPeWuZ7Q8Lq2)cdqcA9xzC6bgblgP75HmA0v0FCWR4L1F9IM2LAgMDqYRRVs95Wjv5o7p6B01Bw1rnvTGy5r6MN56O0cZaFkSGytWmnBgv7ZURdiZv3Ts3x0julT0tceGMpsUKffGw3xVB1MDQTIVHtBsLVRGxTUrq9N5mNufYeXtykzwZBccbm00Ul5uR8476c5EvOD1jcY(yG30Aiet9(jjYjSC9rRxAo8nEIMB1bf6c2Wm(wOzXcxUgZSvRaC32CHYAbj9tISTSVidlaiM2bY51mJCNiEiIdozWfg7uESVBynsr8skMVWmXcPJOyNsnkKNR1Gjp2UI5mpt42CXzgNNNWjnWCVyBhTCszU0Z7Ii4nVNhG)hScVwsY7s7FscndmTyVwzb(TnT7RxxX3f6bfXqc)vCNq9IWiJqIbGbEIzRFmcYiS6(aMSMyxEiAOordIqPDYZdP5moUdXFZDd3lBMaD))2pnNmR0ZUbtf8MwUQPTJiFlG4J3T6Z171uBDNulJjnqf)NwzB2QfwkbK)dmEHOFPjAI6OaEl2v3USzXMnR3VA7cCFdvk0feZY1558i15mfNoX(o9Hp194lQfkGPUvoxSXyVXgItpkSp2cZMLypmom6LPbQFYkvyOIgDifFrrbkkFPXHfLHXJpMIArUMim8LEOfJSBOgih5oB9hoODkRDTvB2D21ZpgQ9NVTWYboxgA7cK(znppl867sOp(0RT2Ub0hKH4uVrog)IzUJDAHrQh)iIhncbo5e7euNsdCOEOrCBrYpi1oBOpnVOUJgawLH8vUGUvxP)XQT1014bhls7m)AUKlSCbnOISgtoZ8e22aTK4EtdKgWBCoGKlwz9mlkKH6uhHAQ7A8Zx5L5mzrgNBYoMxZCyzA5ZRDLyBnmVp8roRSkP2VCe7f9ueVUbbw(9f6FQQ0ox)JhMRv6wCk5U1hvupalOJ2xrQVRq)3lgkJn6Z7kNe37ewjptQ6)DuO8rssp0KBebW3jrqHCU59GAFaGKE6OUuLAj1BpsWV4608VSABdnZDk72Zg4UKkZ5WPpF90kdSNeHKhMnA1r3J2cgwLTYkM9WNaaQBhioUOUc)r1caqbPOUhQaMRZBgskIfC)ebecEM6k1arOEKpzYIPVdCB)6ZNEX53O(ioB6LtNzuV0Ty7gtUluyox7HmJDPweCYi5P8ER2d4aOtUoA(3oTEBBmXK(J7ZlHDP71i6JYK)PcywKOrK7l(4kh4lOjyG6i9FZp8ucPMO55WWXpUcD(I0iuostskZtkYhp8046dCmT7bpAtREBL9eHWLrUynv4ZW2P3Sadg4MBGNhVeqJo8Kv4X18ca(WDdbbDCXVy0ONWYSlsVeI0DfqGu2oIe2o6epX05anM2Jf1tsdklcIlJGwG7qdSqEAwHAVg)FsmCBEp14gPHE5pskPV)1xoW1neS7DhVK8W(Ly3(fYXJqDmdgC(NH4yjk5xT7XHV8Y4yBnpWcb0alqrJrbjXXPOjDZbmrGuR8CGIWi5m9tqhc77CuQhfSY6VQfiLwQJaQ7HQFy7atKib4OCH3zV3ulIL3l1Bfphz(ZrXXym29WMn7V3aiJMRkNQz4HNbpAO84dqQq8bw3E9aSWhpg6CzHNRxHM8NkIrC4xJegIYXq97(zm(bQGUD9gZeZqLOoScAnbpq3shkIDWWjp0O(fiMisZVAo(AB5NmUvEs15OO(vQybWkTonf1(K5Vg2oCdpldf(pUZaYVNTcO91e((atEV5CLO(RACmK8r10GYGeqTeNQEYvzUlIBpByOyof)50h31X(tYqzBhlNvIJ3PJhdiMBY1QipR03zQGtn3nAjyi(S(RkRL261uwX2bUIczrA27yh1SqXn38drX2bVSmnQ0oIzLoIl)CugyOm2hsjzteZAwKqik6F5L9V8tJcHYX4D(Jp8GkJTgvUoivfezQuUXkaY10lXnIxxAUFv7Tvd6F0wRz)qew34SHAFadP2vyJJR8uznPfjcrmEGiPwNPA0(9e4npG3ZObjhlGqukFzTz1OpId6K9P33GSRIFPgNc8JL0)PaWjjrJzYRaVMDAIrzGsw6vkYak2iD52MpRVdbu8bi0qLyE84SPH3K5IVwmReh3V6WIcZCmyWe(8a8VlyA0HkcODGgT6aoPYmduOUJRGFy1OGAuZlbHYnr2l6atUjQcia4neygd2plxaTlNCcDOchoqvd1iqTLTUt)E1A1QckXbBrE6fnwMsbggPsc9X1uex5TLoY4d76rY1LmFyWq0qM8jgwC33F6PN(Rd",
                s53 = "!EUI_S33wxXnU26(xjVSpN95by4734jUvegDiWcC3DY6fgMQmv5fUSRTTRKqZG)7hn1uswYw2ufqs6Eh6XyVxbx26YuZ538MKMp8B1orn3VkL8)C768C4pxM2KqEUFu90Q00I3xy64yS3VvheLUo7QPj5Pfg76AZ)V9AF1)SWY1ZyVhHN8L0Q6SYIc43DIMLqBttRO1f5LtV7dj3xUUbEIr0xZM1S4SKMPlG)2m64lp46dtQBoiPQ20o6WJo76PLL5Zk)ArnTjAsQMN2G))HpaEJ1nz5zn3)B1H0V)IYVMQ9RTzFn0b3q6ap2Ft(jFSNZtQRVmTUCD100ETaDQLumDrzvnoAL6CkrR82BRtB(ubqX4nUMbItuD2SuYBCW5XXNFw7x(5IDm2nWw()acQLf2cRRBkxET)1MbwgH2xh6O0P7yAyTRRCp7fTkp5(0QTVhvxjgzUPHUj6n7O4ZVqUR01t8MsPpmD3icOB0LNEY7Jv6cOnDIidAx1r9Uggg2EEwMekNVsZ7hDwswb5lgRDnT3nmm03W03oW2nq0l297ftlldFdBtRNOx6rE2XExpl7qplhdlBh7G0DmCrs0fP9wg2X03biNo2UgUbUHJ3xorF44jQtiAtdRFFRPkz)Pne51dw30uwO0nbVsmu2rR6SgBVRHRPVRFaHqrNPs9ZGm8pvhdlYTnRyvYAyo4nIwrx8jlmEb(oHwucxhSKH7GwqMTwiufTBePWoWGBBhfgDvdbxlTlpgHoURPNNRHDOHN12l0SJ)UM(E2HHw2gHU(C(z1vxNR9jRUEx7z6R05UoqFZ)p)rzd3iKglB5UnGWu5y6AEnboqDsB6UD9LT9U9b1WpQJe7MHQ1N)ZaxKGx)M1KN9AHhB1He)iI8VinB(IguPmYQVArsbHODq56Iz1p8iD0qShy)Pttla(YGO11P0oDcmyqsmOIm6gyPW1imGWdzz66f4Th84kYJD8DA)bF6JNdtvOl9umv4m0OeYq7U07JlNqOyuARwT2KL5JZZtRxMwL(7NYFmyprxv21wEYV6HSvIZsksMdl4dIc9uFyh7ygBe1c5zk)s)ErwZKQKLP1CTzDEbgGnTnqfrJ8cCfiJ8k6uem2R3H59POiYgMng5arRhDQGswJqV6zM3WVQafBSPAhBohU1KGrhP9ge97POHuvOJ09dJV90RocOLXFvq20n62YIgadYlAEE5nj5GD8h)TvvP11Fn5Ek7prOnpRi9SsQAO6fjKgHIlMmBgHXcKDdK7NjvzPa0cSKCR4FB6e9LS63tWUoJG80KoBcTXRxu(1ZV9wOdOWK3mF)CaHYCpy0rKTtpGIksgwKpp7guyN035KHxn95fes2HL5LvNa4tw7bu3BMFjyahastWFiF55f53FArnDnfa2K)Uda3G8G3Lq2tw3ucyHRAW5XPfFjRH(jKbxzfbS6sCa5gnfWQOTWhHvTyG4NnTS4QM7Zbs1scfRQaMh1uNTG5ulz4JLhxKU8(jWxbZtCEBSRTl26IxlMYRobD6QofbQJtUjMtHobhq2cGB6yAcshoGshOTPvuc9BP)mmCBhmVVCDDwX8j0NDBcJfVOGiCoHoAG1PltNtE8PKzyDCl5GT(4qFfA3ZFdzAmSCe4H(yIF3(i9WG(DhqFKygHKy)O0IKBYtNfJtLt4lP8M4eoRb(NxL9xarMQ0XrMJ8Fv(HhqDzv1LGYgsVuLKLpzO1gjwuNOscRZFUG4)C2SzPftgAXzaguBIk4Vr(BJdpYk8i67nLGLDyw108u0t6mgFjWJkpKmqIqfzHjM2gfLvltYPFt9QKQ7owqE6U4h32X2t23FYeqVEcb2B6c67liTuD8vjZYwxxyBqf6sOmIbudv0YHOvGYoA(0zB18XLmat(Y9A5CLgfdnYJLh5OupoHNq)Vh1su8JAs)wZAc8gb7bgixZPP8EKpkBPp6ez7olPwrDtEz5SCcK9dDzhCJ(4X)XXxkp6XVGmXiC7P1iHBkW2DUWqXoS2qaEwKH4jlsOr6POSiLcJIVfDwYnvJBBg9)fbuzgLr5GNTUkbKYpxY0tYmfBOFV1cWakK2)USCjXA694)nvuZPpWSyIgItguK0erF4Dj(qRos4QZ)pXbzvhNFwm(xVAozXp9WK8PNVQHraVnRQU5Y1fhvsvNqimtjl1ntYYBOgzgeD4IKLRin3eW(K3Nwvsb2)JuYVNuGIX7p7leqscpsf9Lo7(MftqLLtxKGrlkSfD5D78U9RstENRfAvR04Ic08)SoDD6d4Nd8W0hwNxsgYGFmrn1SPeGlKNDdz2ICDU4yNOTEDs((ZO2QdFHz0hYYVFfr5uDtnP3)3RZ))(FYk037J2LsdUnT3jZCAVNKNF)t13V2ZCcUZPn15z0EoErfzm8dQJ9Pt6LLf39e98Ro5oG2ZeX9L)WP2HrxUUSUojDnPRVcuZvLu)JyAt5YhZYvASURxLs6CcCT7EpGwOKMNoL0UNLSAfbyVabRwI)v9dpWmaQ1Li6Bec29(1wGZkgqj4RRaYeSQK5onrlWKQYLeBSNW)yQ5E0pZHAYhrf0(hgF6FCmGSmD2YRi0e6plRuXHAAuTTr0bet1Fhya57(VtNh9UJY(cXw43DX6QvL1P))GoHBowf14Mh)TclxJFEtA15uVPCxAYR4K28xVjTNZVGZ5xxj625AvXFFzU9c)fuI234xVvAthVGFb5VD9(vCs)l4kTN9VAZzmsdWd)s6veRs)T07jdtd082zljV3fL1zWNaMpdogZc0oDcEFXoMbM8So544Hzp5BfyKpQsZVOmRaYD1Hh)XyW1A3Ovkpb9tq7gkG28wwgSMChBFr(TCX8WTP9GBepBv02SDeBh4y(YgYQjnKoonTD2LNjlxJa6IzZ8MVv4h6r)bxpNqhtN94uqNwkOfD4W7rrMm1oUOT69foMH76kY)U3Ekdpxy4zzETPFGybluqgDCDS4uxlJTIaegPp9LppkGHZRWS2pQDhWG8oM(IzQxiFM2U4B7yUvSrTt6qysBBADTtGFlNAaNw6B4Y7eFFkjEt7cldExyACTzOLLV)12UI(WZtqxncOB6jKEhS5RDpYqAoaJgKteKyQhW8GSadtkeTqPOZQjWYDIHnXH2MKP3DyBqZOjxftqsmbXOjBflJjRxrtpZjhEuSuQocWuDWceOCSu9JkwV8YYVwJaOUS3jEr207kinKiUIbqkzVjRy2j4BQnoVIx6Ycwy9y)9(5zZliTvE6Tnc80WOdv2Zw4oUsoeNIa7h0jEGsbEKp9C49fVb2Xct8bqKoTjDjL8f3pLauYDsvmS)4KaGhi2UEyQmyVvC63AILM37tgoHdLIgFiW8tb1DyQ8jD6bZfzirnu6XIx4ebL4aXC1MVmXIxnrHAzE2S(uHpvyPlSSM83cjbSmer6U)qBA0uxAeHdgFOq)fF1fgQaDWBVU5bkG9jXLIWtlOChWxjKZ)tiSbdBYMMKFoKVTgAWEBZn4VHF6ebTIL9nl8VowOaVt258eRYtk5subuImzWOYdWsANui1F81ww26FeYY9yXzcX(r)oF3iTDIW6zvFDeJfQQggdsVGSwrEDYY9bGuLNhwAQdh)gky3ID0jpl2wdjqRbs57PKmPTNxv(1JYQsPMalPKSJu9acVNidlUHsYdbqGsYsSb)aKJT1jhRi2ktpH3u0aeUCZFqI1kYJdjC0r2xLOBHZXtlqVAaxIOj1xRuHwmbfrffmHHekFfWeyoPmkJApqoKpQ9t1bfyzhr8KmPbYfzQmvrZgHOlRVQy9lsjVw59xhf99HedPoxFrEY00f0nPhWbmzmSKTv3FpioDkTTFAadfWLbXlykZCPo4pSAFhPv6ZlO6LTSIUTK4tXLPljZeA2XzBcNnaYGTXsuAGdeGKk6)jdDyiUkN017tPKxjVhsvnpWhBsyFXDfSvoHOoWP6exGu6Vws1le(H8tS4C0qhJzljlI3KN9x)vs1SwJROD(DKpUlwKru9xZwj2Qt(ste(yLs1S8qQgKW95PTmdTCnpjauhTiAqnK3hj91ojuY3faQJgtDEv0L(RSLogc)t5lUKVHKG39kbl1OIF671pjJkDiLEs3Bwb4l)BKvjc)SaPBRTvHj4kyCL7vjbCRGNdUuV29ZCiGvjKP4YSPNKx(1jphtxK2I7kwU0zHqONTpYK1tJmryUlx3C(TxMump9CcUuEcdBDumQWOj81MTbN6zzsJZEpPyTIDmhOXCHog6ySxxWQbDYBiJZ6tjFHax6XsaybOFA3ZPBIfvA0wQQcsNyRmj6tCSL(Ww6GiLHQSWyEt1HbBkrUXiXDbU8verUAvA6ScN92IqJObNvl0LIfVA3zK6TAPLCCPSpdTquJy4eHkip7eR3iAK6uxBsrzzsWKDUPKF)pKrAPIan0qrId2wCmMynH0Fu6TPf1K1R6xhuS2ZxshqSbnrt1Klv8l5ffgW3aay6WdDegtRn2(dIK1Ly6gvK(fyRSRkDpue8geyNqUZQpzrj9GBelgBgrxF9C4PxpDMcbPRvbTRA4o)9DhEuTAe(E19V0CZaJvTASp68Wc)pBGATWV9HP7dA8IHO1V99hnGgJAWPcuTozSnePMZEyhDrzt97()8UljSfWojUteW6PM(PmWCZdEDavxa8T1NE7zz1CW1NiUxsWWAD2DuW1na4Eqa42DLSPmaSQnN6aD3bPcY6dge1wrF0wcu3XSgva6HoZdQ6530qK1Z53HTQ4vbD2sd6SYHX9hq4Z2a4TbJFwRpZDaWgeZQBkr0yqJgs6GOqVeZp1fIkT4AJe4nfG6xlqm9MBkleO9q4eS3ZbgtByMgrcvlm24OtBDW7(7pE2WkZ30O)Z1u52A(57ybb7vbIBqJq15H6aQTFMosRdPZTfPt7wSqluhULpUoP(MliZ9KQZYMt3L6yy5yhetGODwkHRy2Fyg)emwJijVH(ZrOc0FIHngJ7ZiIHF3LvGNxU6y8OWpWrWLEcmNkU2pcJiyxnXe5fXbLufXMJ96t3hw01D4uMHsjWo(hqxjl7utIp)Yt)3N)X49)aDFvX(rOHTO7dLBZYZH)YXZt9G)hGKfcPiwEiXD5bc1tX07PnuicqrG2V7mY4O(eUZx4qlnpNBAJhxITOinhAUALZ6fhv0J0weYekv0oQbzvU1I8w9ZQJNd4JhCMDPUzgCaMeAhOCTWwrb)JJxUcoV0e5O58JFQyAj2ifZNoJEQ8tQUNMCc39WZg6sogkUfFOxZo0nxOMZKkFojNon5aDI3hafwm0sGSrCJG3Tt0bBlicTNytovIB1eku)5IDCD2tEv9s2E6J)3IPfCcgjD9hypFIyT5Z8jcRpVcs1gPNAdnjTbXBuackcBB9y8C2bAkuCHmXyb9eNNc9Pc6GSdW3mxeYzXsmxQIX7gZFESe1LEczXd)RpldJnj5hXo(B9IoaYiEGwgrhEB2pPQ7RHzthd4bDKr2NDISHoDF2QkovwMw1AAqN59b890jRvUKIpq3)uRQYws6h8OsccQtGdIjS11wLwTAf(4feYpK8j1CuY6NGO0VbkVo92pwYH9Wttn0Au8h1ENJozIidhsX0zsRXYFOGrFGt0lZqmVEeEV2HSKUlIAISA6FbBpu84rjn5UiHy9kX4v80YkDJR46moGty0maEEr6Y0ohm22PYbCDXIUtmgiG6WB9j0ubUpgJGZ3pOVegaI6sivyy0aANttBWJtSaXXKzWn0LFwQlTaKGSBBooNmnicOWQjE3s4e9rkQTaXlyOCvoI6gzowYcXu51CeTREzzzZcqF5KbVLckBDSOprr(YBPpY0oMUgIDCONrWZaOsypzFgUHtGSolHfk4DhlWk9pW36uRilEEaxWs6zCHTng1QLN9sn5kUV26a67JiV(AWQKhmIN0r1MWHgV(MPqSaTnTaAGWi4FPeRyM1cI1IwzSNgVHRwtmP)Yu09sOzyRcPflONJCIvT3sSb)YbKyFymud5xNANEH7W4rgrlsQx8hj5Rj(nzeHEIKo90JQFGEN9q3U3aX9ajq)lz83YqomJ23NnxcJwLT69QI70j9vzlxLNoPlMrC3n8jsAa63UMbUMw2E2gEMggwDD30YTpOH4sdYj6iI)auAcz8C(WIUB8obZ2C4UJEt78zrAb0lnIKtCLTBQIuyloHrkf0ItgHwCP2MqWRtM8xjTzuz6LLw21b2j64d01XIFv2CGtg9cAb1wAQNBmEd1eAhmmGvpRUj(RrjiO(DozbZ2481epPYskoTQS421vyIbcIklNkLcqhUi5eWXTKQj9r2cDmS9njAKCcm9dPugc5(pL0tXXAn3G9IGg1I9umPrzTe98siJj1Pt2e9r2wpBDqMyU34urW483tGsObRiUpR4bmU5ogFIgbFwY3OHvyOlIgfn39qjpHhJqTaFdO0zpUKiAziX0JvvLnNoVGW5CrswbFUe3v9Mzh9nES4YO81iZuF1oOhVszl9e2Jv0W0FkEaxtdydvsEZIE2klI23tyQ8pttI1z5PKKTNSnUDvBZTRON5S9fgufX4atDpLxTwJ6THIDkYQdUx5g1Sz94wkS3AtBUgRv1g0Dz5DDwG9SmFuVLd6SWx1OsncY92FKJynTQ9fAn8KlnB(cTz0CJSzu48HW7(NR9I(rZtlsRsYFOxKeO7cf(AaCBhvvof3z7pHRhI4Ua3ArpsNFLnPlX49PnpIsOcQRlDjDsHDsJkSnCJHPgJa5uEH3nKQXU8FrmmPjUIOtaVriTGBoeLNOH)hIBud9oqB3qM2f6d6UpTO7QlQiHlAfg9TeSnZ5zaHEpWnYTn30sWw2g0ajBNq5uOB722vhWm2d3nza)N)iPZMifFZ)jLg53UPSBLq1nCNq7B6z4eAhy5lomEM227s(B2pSnNuolPB7UlQsHR9OZwN3KHb9g(T41vfNs0Ztm(9Q7Ywfpq4e9DzCf3wwb3iwxrVfXNij(4zmCcGUEAYkGlA25eYrS0oSFftzmBXI62OVYMbYMTAjDR9PUkjIzmE139(0eACZhWrxPp8sbRIE0ztW9p1TPSaDqEuHuq2xChXgd2iOp7)rjltMNEgCvubR4wrZwI31uaFYSKC4oTsiuAXuGvLElGxDjeVpnXiZcYq5nPvObduzsIb3DAq5eAzQlHwYYh(ONE3uwE3sieFGlJK2Ly2vri7(fsVOJz0Iz09qoo(nucwQu4dnjSmfZG0SbwZzZcwmeP13Nruhs92gU50Q(aXUwUdTK)8Ca3P5(Ec0Sli8BOhdBMKuGH)UUo2w(2HwU(8yYyA75VlyxpETI)OkILpo4OpqoVD4Jusvf8aGF50IJwxmpTKDXIbzZHWuZ8OWr61UmjJfPq4zqsXty7LPAcQAkmHGFODcyzBURjbpWk0j0YmKnbSmC821XYI42MRhELzBrPnqVCoK)moOZeXaxMSHjJvDiHQmPSiI99oBdbLuXFC7Lfh)HpWVzGTcde3ejoHoIJWpCHB(OCq9Ps9eAdlacwOsPLjFdmfRWLRJf9XY2qL)bZOhYYWsAQ0WRZOU7stxRcSmfln9iA9Z95rN)NFKBjIU9AyVudFIiUNsm1hKiPlDjCDnZ5R5CwpYFWvQznMivr0gwNw(f8iAW3gbQY445jakoeeKz1RRtXU5IivvLMChKnvDdhon(jalag9zvhmF4lJq(LqOVuI8WttvnlTNZO9(t3vE8xv(izWYg47bccRDJBhwkWcdXMqOQsFnwQmmDn2BSJkG8D)kE9KP19blAcVvvCWwnUiROiD2vP53k2BDuxVA9ruz7kBGG5I1S9zzwh0YBhr4s7jpcYGWz9pWY2LGCyIbPJkMQ5XZ7)y0OHkqaLr17SFyqOB8WW7q1)D1xtwbxHIztPsARyj(xGJzd3Z)gMUwUb(cCmtSQmiSEWGn7NUU6Q0AA5iXuo5cw24XekNQsG64k5vp6myl3W2NMQT1MoqSD5k1gQRnDCFHDDqaTNn89ScTXSJUzDDqWO9mEzrcCB6wRKaEh2lqCZj8rQje49BmrgIdq7HjHtakOib50YL80IX2Ir5M8U0gwvaQ7wwQJdNmqcIF(FQyhBCytfK6Za35uSs(sv7Xh2xn1GY62fagqLD6(qzsg1MgfAR8aNVFeUvA7wZwH1E3K)GyRLaNqmI6IwJkIv23mhpBEkAr2UMITEJ8fwJuflbVani8R0l(dh)qBdtD36i4DnJn7M2WXKWl7O3VeEr9qCz14z7SRJJJRzOHJvO8n5sRRm0Mp0WK28b(gMM(wJ38ESM3XuCzTegG3HlMeducS2g3M8IUmDvlbX3KEDOWAhZbhXM0l0exxiSXHgEJpGTAP2Hu0Hapxh3qNbP2MEMqzYWYWZ03ZF4wNS(ECb9E2LUnN40LaXTTINT4gi6fCnVOVu0GxYlUTxEoHIRoODmBhcooHBZf(cLGXVBEST86WwWwTdPL9f7GqpNaNT6Ip6tx0BXwIRzSfBBFw1)z4LdZO)fC7OcBg21CJ79AV0D8ndTgUti(USlF9XmCWorTKWqxe8nSXYBKryOVJTuxW3mFqhqygaQwqGRRBOXWZcrPxOT5T21h(psZ7zeo8mGZke6fAA(eYeUDKjSD8DcX7gjDdEtcovWgSeqBB(1dKTNdvCdl8qbVC2hYc8FKsm(jp94VL1WNbyBannHlIT7a8TmdS3w2EBbnX3fXjciusFZXO4UK19aBtdxhVH4zWBQPvRRxKoRRosAKpWR2TdO1Dnu9a1w0feTx5GgmPejiS80ZWryUzOVD37LCYIviZOESJpO1Yzhw(wOpNP8LAMJfMmyzLzDhVwwTdRE)MH6EuLVxsL6TxWmrAdN7Ij7Nq6(FwNuLkQqcqrIG57gKmT9jEcHvmNAX((K6rXevYBxsaz0ktcEE0DA2WWTbm0U4vO3n874kUwutwfub9dxCudNdMyurC6O(sQ5zul1aZpolzAvjBh8rmXzUs2ewc)yNl89295R(Bbq2E1Ko0nzd8P5ztVlErv565lMi2DHKg5o(LwWyxPgfRxsxqyw4rSaIQWIzlMJ7Uoe9QHb(EqiJyNra6EHUSOzdIDwQCvAahfsNJIEr4N4dx2FrAzAHEO98(e3ntvosSo09eoHCW20hWZQqd3LNyAJJPlFZPXDbFY2DVuO9(MqCe(8ySgp8iZV8KvPhSL1QaEn7HTEWSPhxJqUqTlr93hxGqYYBsAajnL41Hpw6aUSPh4yBKdUJlc(klABIln4K5IKzZehP(ExikSOh0VgryXD3HONPygVCTii00bMF7X39cjzv8LLyxANAbDfezHi3UL3xAklHJjrc3(6sr)tpf4DeToCPpXjErv4wFay0ph6mmOLseafHnKsFLA9ZWNfLAGXGvUSqFyfRUp9IOlF9QhLr65pDZijvlf3h0tU27ugT1kdf4uXzJsMv8tQ4h9ZfJUmgoFSvp2MytS(PVCXO)0OP9OLHtoC5ap2TX69AzOpwpbSVkc9CSdcQoaiXaqkQZGjkoP8Mc03uG(Mc03uG(Mc03uG(dtbQuuSg(a3YZtHJXtVrT2w9N6xwgMBTn)k(yKKW)lySP92bpPQ0lEyT2U)sQ12k4NPI6p93qf178e3Oe)yuvBf8Jt782R(57JMBlnAU3X(vq1To02H0B3tfsF9(wdBst)BPiAAm)HRwo(1tT8tG)RaZRZKNoQG3XFZ0b)5V76G3sloEHQNNqtP4bjZFchB7tWJhdBCedbDIUUo5l0W3RSiPcSf22Y6wyn27fQXDikrB2MhwpVwfVdi4(M23FGUjB8J1n5)3SY3)3GRXd5vBpBP1RHOVP0VcEelvDa(hPI3bm74xj)E3sf091Ym0(tzZ19o5zQ7DaCc9REVa9OUGNRMgVuxxhqCVR6Ro6yhysQxGBiAUE8pDQV1U6STmGBmTwlIApD)B(1E5aAD2suoD6KgwPUI2YbzJ7bEOtiTJHlgpdLupLPlVe1v6RSbdITPdkCOO(Q9qbPvDGETBATis)9S6Gwdn4P3uNsS(N78HuR991XXT07QNLTCJBURoTG6HG3gtWFw(r0vxHv06v9S7C8CenMhO6JLr)aetJ0z4BQlEtDXBQlEtDXBQlEtDXOQl6SLYFlsD)TosD)kgqUTYJ6)XepU(yYBz840zs1ZjMA6dx3q54sRLIA31mAS(8vjIC6Sf57yEW6zl0GBuWVlHJRNHnBV5TA1O)9lICbrNLrM0VLdmThkSFTPhTN0P32foVTlCEBx482UWz0DHJ5MVlC(PT7y)B82WX5x3THJY5y(nDnVPRj8nDn)C01yRtxJ7B6A(NRUgdD6Ac(1vxt718YBkAEtrtWBkAEZPMxPJwW)03GJV(U0e(lUAg)3o35VDUZF7CN)25o)TZD(BN78FON782l3ZFL3Ii(VP75VJ7De)3038p9dZ1)8dQwFT4EVDCU2YnpI8nY8BxVjB61BckpXVZpzf5aKzr66h9OKMeEXqdRx40FbeNoGzxjVju12AtVfQLx(mitvV9WlTC(3072LnS9woT7faRR4RurFBhpCAp0hbkxm6RRsGAS)LPlj8zyb2jmQkjBgTY7)GOAuCEZcYVEwwTOkewlimcTY0Bf9BiV(ASK(vF39y1qTQS4VGcweWo08v6)42Yk4LieFOSk5gTaQAoXpkqz)yzbhWAgBZ)aAFxVe6PASokSQk9wcgb5fiKQ7y1t9RjlsyH(fQ5IhLvVkp5(ZkNLsgilPfCbSiZuC39hKNm9U)DzbRUFkpNOlF8wVSCMAJlpJTI(kwVYHR8(vKMN(hvznPxNm7)qN)ZstMLFFmt7hrIEocQEBEYYucQ581PyzkOkB1QC8NdO1mIBxxHFxtDtv2DPukgVMs(10KvLfxNwmLS42GnzAsvdHl5lyJyfLZkDijRNdLO1RbAcvnCgL42GvaKKLKU927Xpkeh81esp(RaP66BaAfwM5aInDn7RqrrNTAwodw8SC41UKPzj51YlIXScljJO(N0b)X4yxM6spKMje(Y6hgMndkqj5z1emdYy(A67uJvrYYCK1RCjo4NLE714ia3r(3Kw3u(1R)A69vKrwjwulDIGc5qA1DTVk0u3I0oOKVrA)AGpbBuIwscEnHfEjLEnl9lLxddz6FvFpzjUSHWiONBogv71aZRMwbpQ5TZq2vAPW7EM2ildS0n2sjcJMVnWkuL9SU5yPYk8C(vASHMs4KdwWFGb)VdFjVG7d1)iwwRimWveg4RAi)scHn)SJp60F)myO)nLkqzPuPuIXGO0KSkoKOvB6FCsMUUQUSA)MMKPlevMiqTiSAC83iCv11em8(1BObuwkxAJS6wls7u)l3XLHnRUI1(Z6lOS2g8BWCVax3HVs8ng5Ug3vgR(Wfjn0RC6P4)iK(py19j8(RgTL8kY)hTMB0gdDuLrntwL0nbrxFnz9)gQJr2rzZYtNKml9Ouc3hVuXkQjqSSWaLiPZiQY5vtjSkg(hLzyjGI4Ai2XCNvBldv86BnbZNGkqrraMTt4v4v2hkSf9HUFIuvtK2Ff2IfTdlxDp)YmLI9K2a11JAIUXhrtABBCb3THYNJ6l50ac)CAXCMr74a9svai07ZMscK1fQ1SghtOAEfgy6fe64Ap81nVPRlwObSm8nShRSualYD6LD8mWaeAg6d3x9IAfHHR1U2oUEoHScKWgxYdjUws4piiQaxgR2BDwY3OvW4ctdM)laTqU2S0w2UuQxze9)eTyPuLUDz0WY1gRkQ8O2IJi13PButrob3460zznqB(raCf0SVKyocUAeOz4JG3Gqj8qOP4G3GvDvL55SZnjT8Zr9x)8cA1XActT3Q1nNxexUc3I30Igd1KYpuopo5M4ESCcg7d4Nbbq1bb2F5kwLj2l6)60O)RZEhAxfYyQ9SinC1ce6WjGf6ZyfIxGbHxD5dd213Z121W2XmONSvRTSYfmhlnfmNFViRzcaUxJ(oWlvW8hryxiaf0QxQlwkpzw0a)ZgE8qiQvlRr9YRsBILI(a()hlHL4)8rrlHL40BAUHIJ0w(5m5175dAlQHHgmpdi)W(3qurCZbDl0E(bo2M2(wUoHgwIsUNj)rMHEgsH9s9XyDMsuXM(edS(gITXyTbI5NgzWEi1dMdju10IgfxK5dlbBV4hTyti2QNTdRemXM6koaqFSuWeiUku(10k5W4avFsIt4lHHABbd0KTXGPV(fPvGO7NgRKnJ(Irdrg)GMmLG0X1wljtI)aWCbFr16veLJjZUx1WeR2ISGLGoBZlcJqdGv6okBWt7LR847t85TYYppnxaQKrVr4zzZGk)KKNsbTvzlbbpM6O0aFBhdVC9fZqBPsexGfpxLQtXpZdhBBT9sWZqKUqRrBU5dKFTh3KnLtdgLG48Nz1xpo)YNfHzsA5sCaPwM8TJsbo32RJQPqlrlQ0y55dCUNO9fpo1RiAEjoc20Te9fRy4eSekwpu9yT3mxCoZrrIdZttkqtmSr5kOOwshGo05fFeiIvJqm7cGxM3rTearzJMYRRe5nzU)pZ5(P6)jJXyoAuBFkgRAcEg4gJuZ1oyARrVhICoyWbs0WzsdP2T32nyu4N1shtzHJuaj0HJGYQi4OOJQ426GVlOvC1kyEXx5eVl0vxIHaekMI4cM80IUgZ2HaZOmoNuv(1Mf1y9leTnbhVS4gBa2(yZl5YsdjjaBtE1zuIp(dLttu3HgeFgi08lOQyymTXkqJkmaGxDOaJYJ7AJpHlaNhNRwy4fCv8AjhRX(up2o1AKd43h4ps6SlymnOv2TtvJwTd85kVg1P2Zc8yiYlNLuDhVAgZ2iGYTGSUfHa2hb)WeAkzlKSwTfhBk4fkDXkwAE(z5xt0AB2rkh505ynXIU(ZS9lVdeF0oCZ2TkuLwCcLkmIkWidN(ed26PKQ4HJYPGlMvXx9j2VVcz3OcrFIV1pAxcA1ryznWADSSSf2eedP6(UyyZdeGlyfQw0pFUJ2yLtRBsFRAgEbrQ2sI4eueGfRe29I1V4ym8ykfIYte7)SMBewQ4XSOa1QqR4tDkGT7A41Q(J)VNZ(3pQOiH6oGvK1mHImkVVu9fwaO8BqeAj)FsPGGkT0TZBTTO10clMzcmUBLYxSIDc9ThZxwxwxDVwc2DqokUhEj8rTVT86RibSTpA)8S5YheyjJmfi0QRpxk2yxscCImBWDvgOZcpZP6sN0M3kkCko9jS)qafxLoRhU4N5Bxc02uzP34EMGiKAWxUJcfFLb7MSxbuGG(C79ZHKzTAZdJLnN1beG(ZfPeGUKPnzFjnEGC1IE)Ffzmf3VNfA)PlWqIf4lYYABuvh4paeXtxVNTzupwSQLeAnzcTxKu1CpooBlLCBc5uWoRuPwRxwwsDJILFAKnMloqS2inhQsY85FNvvD5WYU1CrwHEgLdS6lJOQ62aJHiAbbXUbDS(hWt)sh7jLCnSD5xYPhlVbwsAZORfIQOuS3nI0zSJWxhGm0PqYzh2Udk8S76bGSLETgD0QjIYndm4O2inJAf)s2GSd3MR)wJ4NLYHBEu20TofbBZ2sINPzBrP3Z1LPHbcqDko)plzE20omGexGql)OFMJVlFCGrlGUS9GU1lM1cBH2ovoNaZV7bcyi)wGerrNEmJ(fgZP80pZRU9mBwOHESn1Zt2e9tADJzCTq9y9glGeJ6ytNGv44T324Cth7chXxflu4qM4iDszCqNwVG5wHknqV)mDGVhYlNa11lf(QUAiz6LuHTHOD1Sy04r0D4lwtOMwi)lt0auRXE3H0shQozuKY0ynWgdxRXXSjdeDPoUZpGnccbc9R3DJ1MKHnXcc3fYt1j9InM3EcMknsDd5vOu4sSm6d(D4AYCOvdqlSPNTxND8bdPtwhdp8PpGbqrSWRc0VPbbnGhLoAWPpTywgXF6Yw3k2y0PrJ1PTXRzSoDCF(X6Cx((Ig3G0)mc9Pwtk)UhotTHQCY2gKr(f)Z2eKrZGosAmFGgr8nyJJnzyxoxjaofbr7xTWwQA9GLV0I9MhWYNVnHBCSnh0EH4xuCo1zyW2hQZ)wgzZrnqONsF4Zti8oQSEMEBTUADr685gQZjV8qDoGIrlAkgKaNfNioD2p9SdnANWp4lti7g(OG2y4W)3YfHBdrAu(5gf1UrlDOWH54j9FTrgtZJN3)Xp(CcdBhN84RPDm4oateoYkexstKB8MgGwzCx6QyhN8nLnHPFDHV3(ss4yCVyGQnMYJy8MlBzOhaSw)HhkgZJKeRX28(BHZQAJHLK18Ugpz0R1fg1XcjYazTbMRD02QSy(eblKSwtzKeR3s8s6CgzI(4sl8vA4Gp1lOMkaY0jkBBb3(urZa7oNvdgoFYiQdS)NyPsvnu(Ize6iKyiYIA7liKF6VNP16ZM9U8mQbPwJL2D1vW(YCdfYe1Ca0l8Idg9F9XetFu83W8InC24(zgL)njMbpzK(7XE95n9(ix6q93YQZ20Awdf)Fi43QmeIjDiJbgYPYMep0bJPr)ly1bdw)3R0dmws40h9glNWDBDveqlKt1NUCGpAWN2Kug0nMndKSa7UCiIvmP8s2B3imwgKEnYmW3ZWNoEgA6bP11n9xHCnyz1LOFS825SFoWucnZXlx1C)44sY2TsXNS6eLf1eWpsgP1LxcP4PzVNo940bhCwAOAd0UVyK6njQ2OPByZsNDN8x(y7g77HToqwkbHYzBdc1FFIZK5lmotSG1QX2jCFI96eUPN9wKBYpHTixaMz0I1l36iynsKQC7ePQDS3W9rNJ(4rrp5r0Jz0Meok7N7UOtBSNgWzZB2gFq)rfDQGr2NdVkbOszV4fRp0uD8ml(N62TdL5hlOuD8QRv)F3nJNVXEVYHLAODGx8MhwQxq8N2XER2CEpTPUBweLCF1cPK9pSnMN6ovAYZBt5XJ5JMWRWDw5Mnj8kXB(w4Z(PccIwxog1w6))S3t6sTn2A(QKxGWiPJwoY8lGGtOA2gWP7KB1vLYylanXiX12KUZLkV7Z3YzvB2qsNUZm5w3kQXw(S8D(23ognQgu5VoCe1tjjlA4Nchf1s6p0Jt(R27eUQ)9skyk9QkhilPC5SffDKygINJz5pRCnm0AE3hyN30Lpw)wiFBifVBgSKXTI5ClNEeVBpEIyi7rMSbhr8vxBfD5ZcR0IoCArxMA5PwFOQpZ2WrKI59LwI97BVUYNIVQeORdxjnKXY)D5LIECmKRxj60bu96wcX3u3s0PBjB75NEDs03cFq00NKBYVbDeVGEDeDFEoytjiBp96NNCwk2xyqhmXNB4kGGD7WXqnCpRIxwxX42ZhasKXN2z2BkTd7ozc3s)9Yf7fN)mNbKxaKUvzs4KDn7VOGlZF2htjg2CzjwxmPzZzCJGw9cUvmGdEhN54xYRwgoQlfvVYpKRXwvz1gLLTJG)FjCgUVTvvRFbrQg4SGuvDHNfgifMA3nuiuttCq8tP2DXsrMn)NXHuZJE5h8egkxN2GWGqzOERhhRKPcaezUbGe(0wQ(1)5xXkfgjc06VNdtTRxrC0ZyC5swvnCPM9Pil1S9tSFCQ8jvL1uzWQHTrjryfGlKHXP5z9xQ4VuKhTtc(MbjHzuJeONAf31DLMzjk4j35b8YpTbWdE5Zfrqf6gaqRJTbvQ8y7lb9rg7iZhjprmh7kmORvM0BqqLUCoazsftDYmVGCPn18YS(NviJ3Ttk0upLYm81hWdn9OD7ZTGzALdE9PNixSO97)KT2(fphMgfVtAEOirgeb4LkFyA9dNDg6rDPEshH2W1lmzBFRal1280w)6xRAeknC0s3UlvhOUos1UEk6SNKMm9BEBF5RxtnJnRX(0CzGe5Rh9q6WjZDt(040DF9XIRUd5a5VgJGYV1o8StZO13uLZERE)glGxRxanQikFZFzAxMl1EQMfuNTNn6dETQt0O6ZFAdeQQznvSo4s)k7Pc5IDx6oCxOyDwQDCe1IEDBpio9tMUf79t2m)KnZpzZ4ZMreL)pfwlzU6ua6ZSs17DiNUitBIHVdOu)UEAp20pArbd1btAKWK94Uzps2i2dtRkV7(ff73t6X1PJO1Dzeu9lWsOp6EdjG)4oiwt7L(CR8ODhfKXt2R2rs1E9v9v)un8YDpP9FBI(Ns4yZCb46Mj13L402V31dDwtR8DY1tKFrFbIDO0FAdbPLJ4MhO65kXQtI5bey2hhhhhGyDIXWLHeSMDr(w1r2ByKa1MDvxbsElkijxGwtF)3rpiQt9j6kedt6RMuD14lqUJipjinmlsgpuXr0JAjE8yZAxoydxLF9iSPjF)2HZDO6RCBRxIbkwHU0bQbJP27O4MCQ7(v2EDPgmM3D6j((ktWwbiVZ88CyxW2LV8BPW0FPniGTxNV(YUZo16RJiiyiY72l7pPUQthHGPVELrFThGNK6J9Kp4Yr116RP6DIhoSndKYdavJN4zxg(9MecBU5a0QPv1tEjmKx37iKEDvkTp7I5QJIVzW2is3UrFRRgIUJ2vJy(Z(YTE95)FkRnB3Lu(hNvLTvM8Ngp2R88U1qRp2XBT8XTWcYUnmSB(VBWvydyuxdRknU)VpL18BPfXj7ektu))8D)BKOS7dXVAxaL8tV(8pxc3UzeBir7XHlpbF)0VWNNHhG6Wg(NTVFe(XPwb)A1ICr9(a9Xwt9d3OSrRNw9X3mD1E3CZY6ZuxDjNuFf2G1h7hCzsLcNYEnPvLrY5dGVlBa41)(HIvaG9kAd5DxZmB2blRVx3yUJWE1n2HGx853OpN0PQEgpu6V)CCh4DviLZRu1UxJ2HqCoFiE5NIiqrPoVK4RFHB7K(3EJsPcwVEEp98dgIHH62E626vRlx4gnpBEKN7uSjkJdk9svQTklPuNlhxS2Kpx67Cw0snhGQZIF)M9nP4aPtcUB7Bss9vCt706iXg)A9rtGIhSl8FBY3OwN1kbijkssxmZUraBI)XgYSLoRcT5Miyu3BjigVB9QdWXjL35WqY5YjIz9C5IA)g(VjJ8WVPvQoRZsb6kyY5(zXRcLTFmMjptN9rLjjQViq7oqk5VXPHnfiD3E8atyU6d7DViDx0MBhaXUnxXBgGcsoqwlZk(VrcEeb83kxF7zx9)uqwDZWvWAlS34xrP9bc6v2bXQc4EdoXiVvA(vEu7GXLaTl2M338Yk2GPHgq)QIRN(WcIjLYP136J)j1fSO5q51tVVszHeEBzymQXY0g5KTD35x4D7M5wfcO6S2lnXcQxXL0N6gptl0v)BI21dd0dUKYYGGpEs99BtR3KU(pCtexpSChmdNuD2Z(2e(t49VxcXH0I7BUmgu9TcDMB1ALhBw5CsQ6wwmEvkTB99Qy60uWIMqqpbrd1ouS3yekTsPl(KZpys5A(2zHTWUWY2mp1MzxrcRuWKqvRqabQumk2oCcLcATajcdiHYhARlvuEEWtI4b(34HWIEg(l9Suha(nyzWHZqX027MXYYj1locwgpUC(uXkqX51Zn)sfA82kyim3SRPcMOb)vxaIT(saE5T4Rq5nNMhO92hq7fMvtCOXAO1GtcwAe8BuQjHxjZVF1P1KSjN(TBUXDghxp7J1pSEVvGS4)yoQG6YALVdBYdXKbTU0g8zKkMxRTs08UsWC0bW4Wsd)sEpD)VwfUJsV1g8t28rrM3rX2WCB2mtvPePkZSBBOkNIORQ4bqT4f2SL0XxvoxfqAflDxiGYVucxDkPSVxY)rDdsRsnXjw1TK5o(ILKgUnoUvrY0GjlMExfvyLrwwS6SZoq1OblxFv9FssQFV2xHj(iMnpdtqgN9RLHwDApFM5lSSTbw5JQbX9GYtUyNtu3nRvZH1CxxVBr5T73jkKGLtxwC4IY1f2ZwTk3w1I9Ryi6IIcpvmuIuAYPnd5HsM3JZ(WElw6t0HvohxpVnPB2SK)qp9x8k0QWoBFDQIfZHUYRzA3MhdDRbQC)SwB5T7I)eoI2kHdDfBAUsXARjL(QSTsvw8o6c8oVR2ks08uhjA2mv2wakQP3JL72imB4eBo3tVE)l(WVbTBjxg9awPQPurJC51LC5csYfD8pebn26oGsZCCi2hw7wInorxHUJOQm3hYjg9xvYYz2IU2N(CkjzxyOMLLQpt30UxpB6WlBhmD0ENVctk0KJ0iATmnTrJdGViHvMuTzYZapc9g6pMq4jhxJ10JVjGdjPaVkkD4XzPiC69hovuP27HgG278DPG)H62qS6PpHB8Pajb3sxPNkbx)2TLlkWdyUMLADJSUtOfLp0A)FO(G2ibCIxU(1UkkJcBSn6qXn4q(YBllwm3bRqr1WCmvNtCWxz9OzU6U1BsGZPptrZqJ20w9DN6QsMbx3xe5DGQU2srDRb4MxMbWZLNDY(c8SmRBbs8eVBcYgZMW4Rwxvq8I)nPUVB3UjZvUZRQFawKJnLqFdJPIvZMv2A6UTsaLiRLjhO1EXg1C6p90s31vmEbjvBvwF3K6HnUj19nyZJ6ievbUP)zAXxirX10ZKO3Phbuz1gwb69IM6q3rsMxxv2VPgo2AG9gX2YrdKCaVOAK3FVt57yTXlPXUjvjpzMrjlU8zlRknvHbjvvA7VUjomRJIfo1BQPm7afmipLACysJeTiYO1GLnP6ArmjzevVLxpDwXVV385NvT63D857VFxX8YP)o9Q)U9ANCNjtgBGI7TyHtFC0Z2ctSAD1R0SlLUmQK2DzwAOtBYGyg9WIf4sVhLP4lTpPThwSDLnEMJPNA9KLk(6o6x6yIF7FHj5MAQJPx91Bn5ZrESvCSfnX0)49jSvNI4WumD52luR7yvTX4Kz1XWxllhGYtBafJ8npvx47wnIq3Z4wDEUU2qZ84Lro8OyemvUO5uMpc)Ggy9yDMfGhMyxIsUt)7uguBdbyMp3gNgBshONDxcZnBDsb(6l)oF)5OK16LFQDLUpoUSDlUtyncRCRi8uVdA7G30OsdlwRSB2Zjo6aslKg2GsCz7ZVjg7M901q0YWoJ7MJAOWf1hj8D9JNOCRVDATcFFx)ahElE2P)oLQcQeXXv5bHHVLNt5ToaZD9Pkfw4S9TvgnTlVYjgqXjoELWAKvIwVrhXSnJCWxDd9IUjmb1fpQIViqTCDezTd5f9PFXyYTH8W2YdcvqbhplcIfAYBmmRnnIMFMJ8C3a964V5gAP6rv1WlPROBqFy)DEX6vJ3CJDL96UVRoIvn7TYH6MuoRA7sGdLKJ02tOBRDcJKUUJxJosMjaZBNXQPQnOX4GX41k7QJNEvXIjMoyonA7VSy6hXmWCSr5HxvmfWuu(zfFNJQaCWJvHgMlSEA(nx)TtSwpWZ05ZWtwaB7492)WJz58AnqWiFOCJh27IMpDbCsPvOmlX2H1T6SG3CS609cxBhvrosFSflSvyiLDjdLzOdNiMfdG7cyhG9RDFyQ)VSEUkWbKWUqYzB7KnGWc7GZE7Pt(W5hEbkbI1Gh)PGUsLlBoHoXLTbzM0UyB6ChxFSy)z5C8IDUFMthT6(fLRhtrCOHSpldepZOt8brtxIxh2RNI8xhBVqQxw8PYI)ySZnYUIanYs)OAKuIrRVf4MFB9I5EDzrUzd8WQjW3sh0QMqCZPNYHI4rNE2PhsiGMVFLZWfZ4hTHtc7bAU9eviuQunfZOvqzvvNb5IJE9B41SfbLVmZ1jfeWIpmkBhzEEEymwZV7A)U3dkLj3jh)QazAyMU4AjfIV(6Y)SqFrKHhkaP)F06qjPfVefp9md2UhTxShThq4Lp6TN(QdV4d7V3fOviaVFKQlvjTrRSaGjIIZMZz9jCMZxc4kkItkxSOCvbiRA(kUvmPJMzCutMKkgdiFPzF0rR4u757FuRpDZhnfbdEx4Hx5AJYLiGH04kzuyA4ianj)LHbVmmo7XQ4GODRKWkgKPcNL4fLv(UygILZTAXK0GrHXpwLkIHpokgFX0q6ve6xjrsVsCa87ZawoWPjnuj0BhhKOFVCyUHHkkehQijouP4RhhRELib)kXH4hhKeqVc(65b4)kKs9yLnkm)XQSyCuIsWPtgcVsuqm(ttylBshb7pAedfPWIod2wvr54BidOLyU2Vg8u7cz28AiDuy0Jvj4AqMMcdFiTZssXFyKwfFge6mYBcwgatEmclJXHlmb)34ubn0sNTvgUTIZGjhNxrqgTTcOTvMZAeoBseH4XmmVP0QlkgFTaPlucEnqVk4ZP1xenTP4WttUD5fclp8lZe50yGVHiNoQJqQZkauU7JavqcoB4wLptIcXLAUo7yiuXihWsugahtaWwvAooMH0woiw)dO9IWfoIOT54)KrBkrQKW9YD27In8A04M7VqsIiC4mC7LiPZ8uVfrUZlNLjiKIa3TvIZliYWzMH3HiukHxfXg8dexw6TVWzoKWmsjCGCHKaY4Kubhca4vGFDco2sIylKoPcctPxbuzbgNqr34zWKYN4ot6wD0dqZyqbGQSuCmdLXevoHaieommYmtEwmr4etdyGZqfn8wqtJl3e4WCO4bbPXlapbL5HezbbZZTWCzdQDGQUkN2wXe2NKo4tLQ1mFSUPttfhSu49KWkiN40KWCNOFJik0HzisyMqO6i5jySmnuIyxuPuxujaidKu4UIoufeFB8hBxJrBGqsTeHPoc59MfNt4i0jjX7iiv6Ysmup)WjHa3R5HeEbUuaPX0HSiIXlt3TxonrEq(a1GMgTbwDK8PnHCQPHZAYBimIi1L5ep8Ky39L7ltCeYfeNtuEiq6tqfJWbweNNyZHK1Pxq(e19i1t)YUd)qyfSOpxoqdldutS7IibluauMLd)JiehEzgTUYsCLz5bp7JCwt(5XaDdsezPxURNbfJP30Etbyamq0shYccxGMPWWqxIhVdzKwiJ2Nbep7uc8ghlDpKDNJb5pP33UG1mszHiKYlNPpsygkPUyEEu0dYMqFq4IhLrOPXKS3mHg1ZY6voWROxbEsD3GyAwKVl96qY(ntHNeqGQaoCti(K0wvgqGtH7VWf)Fywtk9vs3eESsfG0T4GHWVeEIdXTzkbjtjHhzswRnPdZwuRxKPenC5e7GyjPpqGRcy59OMGhhLnnozK8NSyMVgcAYrWyej5cWEYD4UdYPj(bzze5hrsfhh3qDkP)wEJs2jzMBwujtRUfKO8EYJt2qBUk8bm90CgqVumJXQfaYyEBbchXW1BV33GQXoDF5bbTeV7nT5v4fYTstL0gYggsvEnZvPhZ1bm9b1mC3Tu3BxUPzKwaHsI5OuD8J2ng4OFJyWtlw9MnQvdRE(aALRo33OCC17fTbEEQZMTypYgtVzBOzrrBscKANoKUlQDq4g0ettdk2aBmBpgM9DPUqTjxRqEdHV8Gi)Sz8Q0w5XlT35u(QORiK0TZaxVOyBsGj2XuWmy9DzU1tmC3rMdA6BVFw9Dy25JEbHdO4kBivnojz1e27GUojUSQ8UP3t(P6oZ)TKCd8jtlx0tBn1VZqHUdB(86Q9xx5udir0G8Am1qG9ahn367QkF4UX1lkRFVkhWGzuLaTQkm6tD28QXypup7JxQ9zO6(KG8t(0zRrhxAM(CD3fVYeRGh5GIPIff)IE53)dv3SS(H7lMV)dRxR(bstdUu3rdf5uu47UHaIMBtFDpnyWo7a)Oh04Mi9Q)9dtxY1481ak4j1Fc3rQ(nlckpy50RX005meYB6SYhGGLjuM4vFFr1jLZwwFsr1dNb)NZNdyAuczZ1VgmiytL(vLxFD5ShwS(ZJB2vU6QjGv4MEl0PaSbGHAmgOt8p5Zw6B0X(6LQBNaCk)x1aiNHQt65o9qm6dZMEpg8U5Nbag7YDYsofB4FV6k3BD1(WNINxSFg7UdZk8pTvX9wTduUCxaSk57C6BwcuB)kwsgh(NRxo9OQRRz)G7GYYiF6ioem6)uxvyafWPX0pvmh3SD1U0eiKIt7ppuyXOL1RNUUqrioUNwjn7O1ZSRLjgkS)fSk09OdVtbBZlgqjwSaxzQwCCnSYoFzXmGsRUYCBHOwFMJqVM2g3s3GtL7Gfvbg0vcoPXqfJGpTz7WbxD7rmg4t)XDmpMMDnf4j9qY9akomTijtzvbhSj7XeH6sXgFHQggjcyEQg)LMSBSadU1MSCUQ6wmlsoQbRVdfj8fwJahgL7p9Mv89n9vtVH6agLvxuqEtV8(vmQc8nVHiXQMdSJ)pfC)xUCDXDlk(uXI3cqiBua5lqNP34evxAeoazYoUUYnjePVqvXqNvvaRfZeEaG7Ct9YpFjIe9ibhoaa1pChsZUIc8hbxOcnco73B(NG1mqO9cab4EAxA(EE1HcjsgT3Y7Qx28NhmAYTfVG(Qp33pfqr(TIP3dRHx8F9IjllR(yX6vpRbsm6ia09Illw)Ixxm95TyYgH)0xCy1Tidx8S9zctyz305ZIhURALP2AHpA15(IjYJ09L4W8yvjXbseMIYGzXcWqT)ztMC2jhF44jw5jzJMC254hXWrf(eGDQpL5ycAWOAGMebSQP95CeBvDXIyqCqSMpdsAeGq1f6VJrHpQIXQyUpWhJcFoT(YBlVETzyae(QI56xLdKjo6LRiXdQLyzbh0lfVlwObviEVapnzvqsuyUtSHKw3dFMEZEpSU(sM6ju3vTVOy6nW6KxIrrAidNecMjMfBWIRED9I5AHhCj2WkkDZYPZlmnq(jMQY5inmfdt7nQUIcsEctZvuKIxm9(vSuqce9RLREy6csw8JNEkAWua6op0XTzObtrjKHqvWhJMCeLcQuJpJbJ(K0tbGBaFEwmA4quCsgQglOrmQYp83Sk9O1fs0upA8ONbu8AWNOZdO)wOEgXdmnGPbc05TWVJuyNEMQwFWcag2q1Rtdl8e1GgwUKzrWBfr2yaMNtZMmjs01tNrNEMYg1QFkYttJ5N0QeFsE4mrisPNrzc(jAlacoqteX3llJFkv)nAJc9unosAzhKtGn(5xE8lOJvKjeKamMpMojYdKKDYWQmMm4owIqcWucj93ImXapX3lIMdCeupXXfEHuYNlXOFcPppGnRpI8QqoyIlAewk6PZN6)sJwIZZ0amjnA(e3X8UojnLqSerYmgYeMsJtAmHNehLYqQu0ymcbJGSWNht7wWA)C(jVlruw1tb95SJxX)oq9mLH88jwkLQLpsM3Z(5tgsUGsKLIg9gbwCZw6bGn00(CYPUzXbsH6j5VfrwwkVV(L2CN))BhV)IVGUF4yh88yk(TIlIM56wZnrXe2NRslMYgXZOIGkrOKWnLcIvFSPyJXA91WFbjxc0s8JJ1YcVKUcswsP53e3bxj0fh8X6p)uqy6(FMYedu)DTTolxwun7ZSaPVO1ufLsYcS)TPlRucK9uCK)bOYd8CXIPX)M3y6)Ul1606j2sxTgQH2PEy47mbLg)IxxxpN(ZZxwFn82Ob74FQK6)cuGmmdNuUAwbapRkaDlAOwHvJJV0QvJGM8s3Y2kZkwVc)eVsmHv37H7UQr2BM7ELUAUer4wVthDXfvkB(x6fbB8i0kLpFzXIRhxUeZF8QpUAVRQ)Kk32OBZg9xAQtL1QQt)vftNBwkO)AbwZzbjsjBDSQnHqtNAHADGvZp)loqtpJ5IDUzTSDSpDhG43wo9EBtZnA0BpNuDfmr1wyNHE1Ks)z8jO48uUxvcgnPtjXSr1C(aRs2mopSifZt0x(cXQcykxvfrJxwFhLtNho)Mc2Wqv13GPD6kZorvwa8raqWQYXSlo74dvLSJFBVq32apVy5fWYlP99KQ6oLJbJNm9pPkoIUJArJlUZOQkThYhD4VE2VC4fFyV3(6to80j7n5OZo9Xhn(409A)Fu5CvvIhsTA9giPzJM3zrSQ9d5vTkw0YQ5nYIBmH0akYvyIefeiboTGet8AwhEMRCnm1yzM3mp)75sWldgqg6XTP17T3fDklJ05yhCOOX5EzO1YE1Xfosa4wv0UzyfJ4ENv6(7FFLkFYCbhn8nXny9tzqzTz7NQeWwTDqWuVPWIoL6F0XUYjE0kRRu7AXPV7RwJ20ftNW(oRtVRneLRAIk)LbqCs)UH4iWYJarGinnIXaGcI0bvRqLh)MHajreiVS08VrmO4rku5F0rGyxSaW1dVCYhE1rxEWrNF8rNE4aCKIE6iw9x(6TrSATM7a1PNAQERqDCrk6cI4d3)lcTXs9GzetcfoU8yYyhmAzcregfSyWolk7odsdE6Op9GA2F3s5zGG1KIRl6sva8oFVJ37vhD6hEZzh)(HK3f(DITfa2j7IaducrducccOq3gb2wNl(PCVFyL7f99sUhOdnfGFapcdfESaTv(NY7(rqE3RU4Th9QpCbiZ7Sl2Og4FNWNW7yVFY35hw(oFVy7acNWmwLsX1KKSmkbUIXunpg04we8tgq)ZNbKC0LVzVt270TKdu(3juRCvzR9t(p)iQ3tqxyj)VT3vBZTTnm4FrPN17s5BPjXP7AsNVyTULp1tnr1Z3CK9zLS2TE5)(iiajajLS9UBTxZT4Vff)Iej4dabbEE(gyLKhPRpZ4jfPWbjKQEv9cQZZauhBQhNPGDo)63V3aFs(Ef5tEAcCaLjfjXwTU6fiONFqqPF3myYvX(a5OUibovXKSSkO1SurqxaLIFsEYlBf7zbMuKj1J7jTqFVsMTkUA4qqOmVLwOnNWeWbT7WlMu)4BsLD8v)87E7hU6NMx)RNFY7p)6DLl70)FKlB95D)Tpx2rv5y)dLxsDfxULpvdmvIsg2wP(hPux)elFBWPupD92ZMnhlfeHa5EvZIL3AB2KIubn0WAHrc1gFLU0CgoRMamw0WfYG14bozACSIvktDRwSQ9c4d1)1A9RPtFYEe(Z22E3s981uXb4FXWR(j5OJmI1SYzYXiflx5wqeUN89wqTro93BV9peC6CU8jz85qM)FeK)TGwJkSAztJ6MIlVaImH0hJ)0vl3GuD1uBllOlSuCyPw8ofYlvHdfP5ZUzgrWzoYOH1cnrwZaVECyMTAjq7bOMcm8MMf8beosOebQjYlMz0uNkzbVFOz5drwd1JZYAwioYvbFmwz2(dzXzkRpnB2MzW6K)OY6KyaHajCCqWuAqvv8xD3oNST0LQnZJZiBFsLLHY(c7bInBx(NnpO5n4EPa)rc(iUyDPTmkQTe)f)gm3t91MI4OTRx3Wui45NTnowSA5x3I261Rx9WYnuzQd0h6vnF5Y2UfAHJXkXeqbKteq9HqdXodJE6tOv8CiIfmv3KqVz92L)96UhAwn1bMNvBHjh3cnvbRAR4ZkQeMDG(GPhpiPTYPsLgQoGqoImoklVmpUivO9s5Q)Asv5Ke4)wqeyK(3MwUJ)4WDnxqotm1jVYR5tA2qDtJZdEjv8sJPni5AoIQjGmLdvHQpTux175olD4paibwRw5SoycAqoB7s1O8dQ3PU)wWcqhwrEPfuXqOD0sqR99SW5JcXdKxPMHLaKl6Qdxu2ziIuncbPxpyfSpC1GLQbZUubKGCQkIdXGHo3agSdOKbj77ESdwgWs29oiw5A8l3U6X7AvF47A7qKtOMQ4c5NrqLcWGA6Ox)DPMa(ScHdeHj1ea2OK9dpJlCZ4WBu8TPJQXNrL4LNJNyt)zzj8FcL3znL6ID2Ua5qOoA2rNh3gNnedhAOLy2davqzwnNXa9RhsNAd55c27i1wvM6NZdtDCH43rcRyM9oRm30OQ9HIObuzD(lDI1drZ48MWS)zOX2VrYg3JDqJQXibhLQv(HH7SYJIIMKmEJvQfhBs(Uw4fio78CUAmqg7vi)Rl9LVFk4Nq3SvwQY)fQOlUTo6UWIRifxsTMD6Wy6hag6rrX(WOQre0xQFTGwHxhzBCZGsTxjRcLaP2m0wiLy1UYZ9oKySpEgVblDXrBcURMA2rQkpjwBNyWAbUjwMQl7BB6Bd0dVc2FtsrLTpP)0OGMX26H9YMEs7sBg)PeIDyGG520qxJ7vVsrCRdbtnOmdx5uuPo)lSbpVwn8O2LayruB1XtCwX1UgWtfHld3IcC7Xew89QkgfINkpGe))HvUGyfJN3neSwYnqg7nGC3q1unWhOMfy5hcaYxmAEqFaFwn(ENk6BpnUyabTZ(RNA2Wlz4Y9qxL2cLQj(0JRp5DWy9Bo)Klp)ALLYzNC1jxGGorQap1LxmHyRgFwTdXgyKm8GrB6nuZoY4wu3y6CAZgS4Gti7yp8UuglCmY1VWJC9ncmohxFkrgSoXqf8dPHs(LaC8QxfLREvuKNPcrKqMoklw54ljjjnTQiTSyyW8q8)N8cLMX3l50qOMf1B0A6BreZ7BvZaumi(qxhYmYJDlzYp2yW5Q55tgtnChxwkGTU8PHJOrG8D6JBzCVxLZjdihLlzZTjeUOJztkreVITUehj3A5HfcJwnuABrv2bOoGtvd8kVCcKtpIZDmjRYIKEiQzddxy3(yCKxGNYhx4X)Cz2y20WDjWeQlbOGqq9DWHH9JcQU)druve9rH6BdAk9DqrigLlczXvbWSPw)hWuqdBkev)H8xyL6Xpg6kMrr98TWUrgYUSZxAVYOKp4QL)ylJWBYlVAFTVsHzBIWNXqDwO0dpJ2uDFTqVQhiRHyi5kxBGpCCNewaUbB7g8BzufgvypjuRMmHZGdrF5uBAXPtncFaUHY8AFqtIyAje1GlOVKC7ylDC4OeKH6tokncYxfC77mW1xmW1nsDZHNSi)nzyL9CrOlWmdkJitSVBy6t6MUWbq))8Nkc2ZMUXqP8om8eRHViAMpRwGuVtne3T7NSsyGmpO2OipCHEVuSPPGu8QI7PFhPiqtVYFrzx11SIAhXMhFy91TqI8)jzsWgbEL5Jdk)V7JkKM8QQS4kBNKzck36QWrPi34RQA6VjrwMWwRd)PcV8IWlpAMZUrACo)X7Vxny2QgaWwGm2KpCZSmN5PBgHiCgaF166fnd82UCbVjm5(pZSdTg8ldFY4kk7LYWwe(68ZS4jatK7QxJIS5rypGsrAFeG7rJgRRJBl)4pO(ob66hLaf1p0t8w4Sp01IDj7DwcIWojzwmxEfWxtpahUE9whHGAIPX3W8jzsiPiQyxpbIDYbZyZfNYLBCuVEvRqeLezFPiZp9lozu6q23Ftq(DggVmcpkctwNYKIXpNszCNFNztAyVovUDwDSKqp07SHIkLAAYsNntHiVtLHg6UvCeG2Ecug05z8zdYkMt5XF8(5lbADh5uM78ZTFWYdmxgVguUjDwZvZ(6)ORCOJY8UqWx(mlJ2DB049PVzpNkDK5mcn2Q4b22tTKz6)kWzNJsviWqXM7PdqWV6TWoprD3YTCS59FvDX)5",
            },
        },
        -- Blizzard Edit Mode layout strings (shown in a copy popup), same keying.
        editMode = {
            p1080 = {
                s64 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 2 2 UIParent -171.8 -4.0 -1 ##$#%#&3(')( 6 1 0 2 2 UIParent -187.7 -90.2 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 6 6 UIParent 12.6 8.1 -1 #&$=%$&^ 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 5 5 UIParent -11.7 108.2 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
                s53 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 2 2 UIParent -171.8 -4.0 -1 ##$#%#&3(')( 6 1 0 2 2 UIParent -187.7 -90.2 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 6 6 UIParent 12.6 8.1 -1 #&$=%$&^ 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 5 5 UIParent -11.7 108.2 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
            },
            p1440 = {
                s64 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 2 2 UIParent -171.8 -4.0 -1 ##$#%#&3(')( 6 1 0 2 2 UIParent -187.7 -90.2 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 6 6 UIParent 12.6 8.1 -1 #&$=%$&^ 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 5 5 UIParent -11.7 108.2 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 ##$%$&('%(-($)#+$,$-# 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #$$$%#&('((-($)##+$,$-$.-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#-$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #$$$%#&('((#)U$+$,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U#+$ 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U#+$ 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
                s53 = "2 50 0 0 0 0 0 UIParent 820.0 -1402.0 -1 ##$$%/&&'&)$+$,$ 0 1 0 0 0 UIParent 820.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 2 0 7 7 UIParent 231.2 1.0 -1 ##$$%/&&'&(#,$ 0 3 0 7 7 UIParent 518.0 0.0 -1 ##$%%/&&'&(#,$ 0 4 0 0 0 UIParent 1281.0 -1363.0 -1 ##$$%/&&'&(#,$ 0 5 0 0 0 UIParent -0.0 -271.0 -1 ##$$%/&('%(&,$ 0 6 0 0 0 UIParent -0.0 -322.0 -1 ##$$%/&('%(&,$ 0 7 0 3 3 UIParent -0.0 325.5 -1 ##$$%/&('%(&,$ 0 10 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('% 0 11 0 0 0 UIParent 820.0 -1329.0 -1 ##$$&('%,# 0 12 0 7 7 UIParent 429.0 80.0 -1 ##$$&('% 1 -1 1 4 4 UIParent 0.0 0.0 -1 ##$#%# 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -196.0 -225.0 -1 $#3# 3 1 0 4 4 UIParent 193.0 -223.0 -1 %#3# 3 2 0 4 4 UIParent 342.0 40.0 -1 %#&$3# 3 3 0 0 0 UIParent 641.3 -1112.0 -1 '$(#)$-k.G/#1#3#5#6)7-7$8% 3 4 0 0 0 UIParent 904.3 -915.1 -1 ,#-k.G/#0&1$2(5%6/7U8# 3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3# 3 6 0 2 2 UIParent -339.3 -307.6 -1 -k.G/#4&5#6(7-7$8( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 0 1 1 UIParent 0.5 -190.3 -1 # 5 -1 0 7 7 UIParent -493.8 291.2 -1 # 6 0 0 2 2 UIParent -171.8 -4.0 -1 ##$#%#&3(')( 6 1 0 2 2 UIParent -187.7 -90.2 -1 ##$#%#'3(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 3 3 UIParent -0.0 -56.5 -1 # 8 -1 0 6 6 UIParent 12.6 8.1 -1 #&$=%$&^ 9 -1 1 6 0 MainActionBar 0.0 5.0 -1 # 10 -1 0 3 3 UIParent 356.0 -4.0 -1 # 11 -1 0 8 8 UIParent -4.1 248.9 -1 # 12 -1 0 5 5 UIParent -11.7 108.2 -1 #&$#%# 13 -1 0 8 8 UIParent 0.0 241.6 -1 ##$#%#&% 14 -1 0 8 8 UIParent 0.0 273.8 -1 ##$#%( 15 0 0 3 3 UIParent 988.7 711.5 -1 &- 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 &- 16 -1 0 7 7 UIParent 0.0 2.0 -1 #( 17 -1 0 1 1 UIParent -0.0 -219.0 -1 ## 18 -1 0 8 8 UIParent 0.0 337.1 -1 ## 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 0 0 UIParent -0.0 -115.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 0 0 0 UIParent -0.0 -170.0 -1 #+$,$-%(&('%(')#+$,$-( 20 2 0 0 0 UIParent -0.0 -70.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 0 0 0 UIParent -0.0 0.0 -1 #+$$%#&('((-($)#*#+$,$-..-.$ 21 -1 0 3 3 UIParent 418.0 -256.5 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1# 22 0 0 4 4 UIParent 453.5 49.5 -1 #.#/$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+$ 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U",
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
                profileData.darkMode = DeepCopy(EllesmereUI.GetDarkModeDB())
                profileData.unlockLayout = SnapshotUnlockLayout()
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

-------------------------------------------------------------------------------
--  Paste absorber for import edit boxes
--
--  Multiline edit boxes process pasted text one character at a time and
--  re-layout after every one, so pasting a large profile string stalls the
--  client for seconds -- and anything past the box's own cap is silently
--  lost. The absorber keeps the visible box capped small while collecting
--  the complete paste through OnChar into a plain Lua buffer: the box stays
--  cheap to lay out, nothing is truncated, and once the paste settles the
--  box shows a short summary line instead of the raw string.
--
--  local absorber = EllesmereUI.AttachImportPasteAbsorber(editBox, onRetry)
--  absorber.GetText() -> the captured string, or the box's own (trimmed)
--  text when nothing was absorbed. A manual user edit after a capture drops
--  the capture (the user is starting over). onRetry (optional) is called if
--  a paste overflowed the box without reaching the buffer; the cap is
--  lifted so pasting again lands fully in the box.
-------------------------------------------------------------------------------
function EllesmereUI.AttachImportPasteAbsorber(editBox, onRetry)
    local CAP = 2048
    editBox:SetMaxLetters(0)
    editBox:SetMaxBytes(CAP)

    local buf, bufN, lastN = {}, 0, 0
    local captured
    local settingText = false

    local function Finalize()
        editBox:SetScript("OnUpdate", nil)
        local s = strtrim(table.concat(buf, "", 1, bufN))
        wipe(buf)
        bufN, lastN = 0, 0
        local boxText = editBox:GetText() or ""
        if #s > #boxText then
            -- The box rejected part of the paste; the buffer holds all of it.
            captured = s
            settingText = true
            editBox:SetText(EllesmereUI.Lf("[ Import string captured (%1$s characters) ]", tostring(#s)))
            editBox:SetCursorPosition(0)
            settingText = false
        elseif #boxText >= CAP then
            -- The box filled to its cap but the buffer saw nothing beyond
            -- it: the paste could not be absorbed. Lift the cap so a second
            -- paste lands fully in the box (slower, but complete).
            captured = nil
            editBox:SetMaxBytes(0)
            settingText = true
            editBox:SetText("")
            settingText = false
            if onRetry then onRetry() end
        else
            captured = nil
        end
    end

    editBox:HookScript("OnChar", function(_, c)
        bufN = bufN + 1
        buf[bufN] = c
        if bufN == 1 then
            lastN = 0
            -- Finalize on the first frame where no further characters
            -- arrived (a paste delivers its whole burst before then).
            editBox:SetScript("OnUpdate", function()
                if bufN == lastN then
                    Finalize()
                else
                    lastN = bufN
                end
            end)
        end
    end)

    editBox:HookScript("OnTextChanged", function(_, userInput)
        if userInput and not settingText and captured then
            captured = nil
        end
    end)

    return {
        GetText = function()
            return captured or strtrim(editBox:GetText() or "")
        end,
    }
end

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

    -- Absorb large pastes so the box never has to lay out a huge string
    -- (import mode only; export boxes are read-only and set text directly).
    -- Attached after the OnTextChanged SetScript above so the hook survives.
    local absorber
    if not readOnly then
        absorber = EllesmereUI.AttachImportPasteAbsorber(editBox)
    end

    -- Buttons
    if onConfirm then
        local confirmBtn = CreateFrame("Button", nil, popup)
        confirmBtn:SetSize(120, 26)
        confirmBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)
        confirmBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(confirmBtn, confirmLabel or "Import", 11,
            EllesmereUI.WB_COLOURS, function()
                local str = absorber and absorber.GetText() or editBox:GetText()
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
function EllesmereUI:ShowImportPopup(onImport, title, subtitle)
    local dimmer, editBox = BuildStringPopup(
        title or "Import Profile",
        subtitle or "Paste an EllesmereUI profile string below",
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
