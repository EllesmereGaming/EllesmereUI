if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
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
    -- v6.6 split-out addons (were previously bundled under the retired
    -- EllesmereUIBasics, removed from the suite v8.7.x).
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
    { folder = "EllesmereUIMythicTimer",       display = "Mythic+ Tools",       svName = "EllesmereUIMythicTimerDB",       suffix = "MythicTimer"       },
    { folder = "EllesmereUIQuestTracker",      display = "Quest Tracker",       svName = "EllesmereUIQuestTrackerDB",      suffix = "QuestTracker"      },
    { folder = "EllesmereUIMinimap",           display = "Minimap",             svName = "EllesmereUIMinimapDB",           suffix = "Minimap"           },
    { folder = "EllesmereUIDamageMeters",     display = "Damage Meters",       svName = "EllesmereUIDamageMetersDB",      suffix = "DamageMeters"      },
    { folder = "EllesmereUIChat",             display = "Chat",                svName = "EllesmereUIChatDB",              suffix = "Chat"              },
    { folder = "EllesmereUIDataBars",         display = "DataBars",            svName = "EllesmereUIDataBarsDB",          suffix = "DataBars"          },
    { folder = "EllesmereUIQuickdraw",        display = "Quickdraw",           svName = "EllesmereUIQuickdrawDB",         suffix = "Quickdraw"         },
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
--  Account data that must never travel in a profile string
--
--  These keys held per-character state -- character names, realms, classes,
--  gold balances, scan caches -- inside a module's profile blob, so a shared
--  profile carried the exporter's character list to everyone who imported it
--  (visible in the DataBars gold tooltip). They live top-level in EllesmereUIDB
--  now, but strings exported by older versions still carry them, and an
--  imported blob would otherwise sit in the recipient's profile and ride THEIR
--  next export -- propagating one player's characters indefinitely. So strip
--  on the way out AND on the way in.
--
--  The folder literals contain "EllesmereUI", which the standalone packager
--  renames to the build token, so they match the local keyspace on every
--  build; the canon lookup covers a decoded payload's canonical keys.
-------------------------------------------------------------------------------
local PRIVATE_ADDON_KEYS = {
    ["EllesmereUIDataBars"] = { "characters" },  -- gold ledger -> EllesmereUIDB.dataBarsGold
    ["EllesmereUIQoL"]      = { "chars" },       -- upgrade calc -> EllesmereUIDB.qolUpgradeCalcChars
}

-- Strip account data from an addons table, in place. Accepts either keyspace
-- (local folder keys before canonicalization on export, canonical keys in a
-- decoded payload), so one pass serves both directions.
local function StripPrivateAddonData(addons)
    if type(addons) ~= "table" then return end
    for folder, keys in pairs(PRIVATE_ADDON_KEYS) do
        local blob = addons[folder] or addons[FOLDER_TO_CANON[folder] or folder]
        if type(blob) == "table" then
            for _, key in ipairs(keys) do blob[key] = nil end
        end
    end
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

-- Deserializer Optional cooperative-yield hook: when set (async decode),
-- DeserializeValue calls it periodically with the current parse position so a wrapping
-- coroutine can spread the work across frames. nil (the default) keeps all synchronous
-- callers exactly as before.
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

    -- Sync handoff: pull synced module data from the outgoing profile into the incoming
    -- one, so a group member is current the moment it loads. activeProfile is already
    -- set to the new name by callers, so the copy MUST source from the registry's
    -- not-yet-repointed profile name -- SyncModuleToProfiles cannot be used here (it
    -- sources from the active profile, which is already the incoming one). Mirror
    -- group: the pull only happens when BOTH the outgoing and the incoming profile are
    -- members of the module's group; a profile outside the group never pushes into it.
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
    -- Restore unlock layout from the profile. Callers stamp a missing snapshot BEFORE
    -- flipping activeProfile (see StampUnlockLayoutIfMissing); this is the last-resort
    -- stamp for any flow that missed it. By now the flip already happened, so the
    -- baseline source resolves against the INCOMING store -- for a truly snapshot-less
    -- profile that store is empty and the stamp records raw live (the old inherit, but
    -- RECORDED: the links stop mutating on every switch and the baseline restore
    -- contract holds from here on).
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
        if EllesmereUI.SpecOverrides_DmResetActive then
            EllesmereUI.SpecOverrides_DmResetActive(profileData)
        end
        -- Tracking Bar link entries in the snapshot are stale copies of whichever spec
        -- last saved unlock mode -- TBB links are per-spec (CDM-owned buckets).
        -- Re-assert the active spec's own entries over the freshly restored stores.
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
        -- The fonts DB was just rewritten in place; drop the resolution cache.
        EllesmereUI.InvalidateFontCache()
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
        if prof and type(prof.condDmOverrides) == "table" then
            data.condDmOverrides = DeepCopy(prof.condDmOverrides)
        end
        if prof and type(prof.specDmOverrides) == "table" then
            data.specDmOverrides = DeepCopy(prof.specDmOverrides)
        end
        if prof and type(prof.unlockOverrideAnchors) == "table" then
            data.unlockOverrideAnchors = DeepCopy(prof.unlockOverrideAnchors)
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

    -- Any open editing-as session (spec group / conditional / Default view) must close
    -- BEFORE the live tables are wiped and refilled: the exits bank against the
    -- outgoing store, and the post-apply establish (Conditions_MarkStale + Recheck)
    -- refuses to run under a live session, which would strand the incoming profile
    -- un-overlaid ("bricked") until the next zone change.
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
                -- Pre-dropdown imports carry showPlayerAbsorb as the legacy boolean
                -- toggle. The conversion migrations are SKIPPED for imported profiles
                -- (inherited migration flags), and a boolean reaches the texture
                -- resolver as a key -- which used to abort unit frame init outright.
                -- The resolver now refuses non-string keys, so this is no longer fatal,
                -- but without the conversion the absorb still renders as a fallback
                -- texture instead of honouring the setting. Normalise on the way in,
                -- matching the mapping the migrations use.
                if entry.folder == "EllesmereUIUnitFrames" then
                    for _, unitCfg in pairs(profile) do
                        if type(unitCfg) == "table" then
                            local v = unitCfg.showPlayerAbsorb
                            if v == true then
                                unitCfg.showPlayerAbsorb = "striped"
                            elseif v ~= nil and type(v) ~= "string" then
                                unitCfg.showPlayerAbsorb = "none"
                            end
                        end
                    end
                end
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
                -- Pre-split imports carry the legacy single miniboss color but no
                -- boss color. The mini-boss/boss split migration is SKIPPED for
                -- imported profiles (inherited migration flags), so forward-copy
                -- here BEFORE DeepMergeDefaults fills the DEFAULT boss color and
                -- changes the user's boss nameplates.
                if entry.folder == "EllesmereUINameplates"
                    and profile.boss == nil and type(profile.miniboss) == "table" then
                    profile.boss = DeepCopy(profile.miniboss)
                end
                -- Pre-dropdown imports carry the legacy coordsBelow / clockInside /
                -- zoneInside toggles but none of the new mode keys. The minimap
                -- migrations are SKIPPED for imported profiles (inherited migration
                -- flags), so forward-copy here BEFORE DeepMergeDefaults fills the new
                -- defaults and masks the legacy keys.
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
                    -- Only pre-dropdown exports (no mode key) are mapped: a post-update
                    -- export can carry a stale showClock/ hideZoneText alongside a
                    -- deliberately-set mode, which must win. Hidden via the removed
                    -- Show Blizzard Elements Zone/Clock checkboxes maps to "none".
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
                -- Pre-enum imports carry the legacy anchorFirstRow boolean but
                -- no rowGrowDirection. The conversion migration
                -- (cdm_row_grow_direction_v1) is SKIPPED for imported profiles
                -- (inherited migration flags), so forward-copy here so the
                -- pinned-row behavior survives the import.
                if entry.folder == "EllesmereUICooldownManager"
                    and type(profile.cdmBars) == "table" and type(profile.cdmBars.bars) == "table" then
                    for _, bar in ipairs(profile.cdmBars.bars) do
                        if bar.anchorFirstRow then
                            if bar.rowGrowDirection == nil then
                                bar.rowGrowDirection = bar.verticalOrientation and "RIGHT" or "DOWN"
                            end
                            bar.anchorFirstRow = nil
                        end
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
        -- The fonts DB was just rewritten in place; drop the resolution cache.
        EllesmereUI.InvalidateFontCache()
    end
    -- Custom colors are GLOBAL appearance, not per-profile: never wipe or restore
    -- EllesmereUIDB.customColors from a profile snapshot. (See the detailed note in the
    -- sibling apply path; this block previously wiped the live colors UNCONDITIONALLY
    -- before a conditional restore, so applying a profile with no/stale color snapshot
    -- reset every custom color to default.) Restore unlock mode layout data
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

--- Per-module refresh steps for RefreshAllAddons, in load-bearing order.
--- Kept as an array of closures so the budgeted path can run each step (or a
--- time-boxed slice of steps) as its own watchdog execution. Every step is a
--- stateless re-apply reading the LIVE db at call time, so a step firing a
--- frame or two after the swap reads the same settled data the synchronous
--- path would have.
local REFRESH_ADDON_STEPS = {
    -- ResourceBars (full rebuild)
    function() if _G._ERB_Apply then _G._ERB_Apply() end end,
    -- CDM: skip during spec-profile switch. CDM's SPELLS_CHANGED handler
    -- will detect the spec key mismatch and rebuild with the correct spec.
    -- Running it here would race with that rebuild.
    function()
        if not EllesmereUI._specProfileSwitching then
            if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
                local curKey = _G._ECME_GetCurrentSpecKey()
                if curKey then _G._ECME_LoadSpecProfile(curKey) end
            end
            if _G._ECME_Apply then _G._ECME_Apply() end
        end
    end,
    -- Cursor (style + position), Crosshair, and the QoL extras (FPS counter +
    -- Secondary Stats -- one call for both: the FPS readout may be drawn by
    -- the Secondary Stats block, so the two owners re-evaluate together).
    function()
        if _G._ECL_Apply then _G._ECL_Apply() end
        if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
        if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
        if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
        if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
        if EllesmereUI._applyFPSDisplay then
            EllesmereUI._applyFPSDisplay()
        elseif EllesmereUI._applySecondaryStats then
            EllesmereUI._applySecondaryStats()
        end
    end,
    -- AuraBuffReminders (refresh + position)
    function()
        if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        if _G._EABR_ApplyUnlockPos then _G._EABR_ApplyUnlockPos() end
    end,
    -- ActionBars (style + layout + position)
    function() if _G._EAB_Apply then _G._EAB_Apply() end end,
    -- UnitFrames (style + layout + position)
    function() if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end end,
    -- Raid Frames + Party Frames (style + layout + size; positions re-applied
    -- by the tail)
    function() if _G._ERF_RefreshAll then _G._ERF_RefreshAll() end end,
    -- Nameplates
    function() if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end end,
    -- Quest Tracker
    function() if _G._EQT_RefreshAll then _G._EQT_RefreshAll() end end,
    -- Chat (sidebar icons, borders, fonts, visibility)
    function() if _G._ECHAT_RefreshAll then _G._ECHAT_RefreshAll() end end,
    -- Friends List + Mythic Timer
    function()
        if _G._EFR_ApplyFriends then _G._EFR_ApplyFriends() end
        if _G._EMT_Apply then _G._EMT_Apply() end
    end,
    -- Damage Meters
    function() if _G._EDM_Apply then _G._EDM_Apply() end end,
    -- DataBars (bar set + blocks + layout + positions are all per-profile)
    function() if _G._EDB_Apply then _G._EDB_Apply() end end,
    -- Quickdraw (enable state + palette count drive the override bindings),
    -- Dragon Riding HUD, Minimap (flyout button state)
    function()
        if _G._EQD_Apply then _G._EQD_Apply() end
        if _G._EDR_Rebuild then _G._EDR_Rebuild() end
        if _G._EMIN_RefreshFlyout then _G._EMIN_RefreshFlyout() end
    end,
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    function() if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end end,
    -- Re-register unlock elements for all modules whose bar sets can
    -- differ between profiles. Without this, _applySavedPositions uses
    -- stale registrations from the outgoing profile and anchors fail
    -- for elements that only exist in the incoming profile (they land
    -- at CENTER/CENTER = screen center).
    function()
        if _G._ECME_RegisterUnlock then _G._ECME_RegisterUnlock() end
        if _G._ECME_RegisterTBBUnlock then _G._ECME_RegisterTBBUnlock() end
        if _G._ERB_RegisterUnlock then _G._ERB_RegisterUnlock() end
        if _G._EABR_RegisterUnlock then _G._EABR_RegisterUnlock() end
        if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
        if _G._EUI_BattleRes_RegisterUnlock then _G._EUI_BattleRes_RegisterUnlock() end
        if _G._EDB_RegisterUnlock then _G._EDB_RegisterUnlock() end
    end,
}

--- Completion tail shared by both RefreshAllAddons drivers. In the budgeted
--- path this runs from the drain's final execution, so its ordering
--- guarantees ("after all addons have rebuilt") hold identically.
local function RefreshAllAddonsTail()
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions, re-apply centralized grow-direction positioning (handles
    -- lazy migration of imported TOPLEFT positions to CENTER format) and resync anchor
    -- offsets so the anchor relationships stay correct for future drags.
    -- Triple-deferred so it runs AFTER debounced rebuilds have completed and frames are
    -- at final positions. Position re-application and anchor resync are deferred to
    -- OnSpecSwitchComplete (if spec switching) or run inline here for non-spec profile
    -- switches (manual switch from options). This also clears _abAnchorSuppressed
    -- (inside _applySavedPositions), so the suppression window spans every
    -- module step regardless of driver.
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

--- Trigger live refresh on all loaded addons after a profile apply.
--- `budgeted` true runs the module steps through EllesmereUI.RunBudgeted --
--- each step (or time-boxed slice of steps) in its own script-watchdog
--- execution -- so a full-suite refresh can never hit 12.1's "script ran too
--- long" on slow machines. Pass it ONLY from MANUAL swap sites (profile
--- dropdown, profile keybind, options spec-assign apply): spec-DRIVEN
--- switches must stay synchronous, because CDM's SPELLS_CHANGED pipeline
--- calls OnSpecSwitchComplete on its own clock and could otherwise apply
--- saved positions mid-drain, before some modules have re-applied.
function EllesmereUI.RefreshAllAddons(budgeted)
    -- Spec Overrides: write the current spec's override values into the live
    -- profile FIRST, so every module refresh below picks them up. This makes
    -- profile swaps and imports override-correct without their own pass.
    -- (The import-time default re-bank runs SYNCHRONOUSLY inside
    -- ImportProfile, never from here: by the time any RefreshAllAddons fires,
    -- overlays may already be live and re-banking would poison defaults.)
    -- The whole preamble stays in the caller's execution in both drivers:
    -- these are cheap flag/value writes that later steps depend on.
    if EllesmereUI.SpecOverrides_ApplyValues then
        EllesmereUI.SpecOverrides_ApplyValues()
    end
    -- Suppress stale anchor moves on AB bars during the rebuild phase. LayoutBar
    -- positions them from the new profile's barPositions; resize hooks would reposition
    -- them with old-profile offsets (1-frame blink). Separate flag from
    -- _applyingSavedPositions so CDM's early-return in ApplyAnchorPosition (which
    -- checks _applyingSavedPositions) isn't triggered prematurely by the wider window.
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
    if budgeted and EllesmereUI.RunBudgeted then
        EllesmereUI.RunBudgeted(REFRESH_ADDON_STEPS, 8, RefreshAllAddonsTail)
    else
        for i = 1, #REFRESH_ADDON_STEPS do
            REFRESH_ADDON_STEPS[i]()
        end
        RefreshAllAddonsTail()
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
        -- true = budgeted: manual swap site, watchdog-sliced module refresh.
        EllesmereUI.RefreshAllAddons(true)
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

-------------------------------------------------------------------------------
-- Blizz UI Enhanced account-global settings ("Window & Tooltip Skins").
-- These keys live at the TOP LEVEL of EllesmereUIDB (account-wide, shared by
-- every profile) and cover exactly the first two Blizz UI Enhanced tabs:
-- Window Skins and Tooltips, Menus & Popups. The bundle is OPT-IN on export
-- (Include dropdown, default off) and OPT-IN on import (Include Window Skins
-- checkbox + confirmation), because applying it overwrites the recipient's
-- settings across ALL of their profiles.
--
-- CO-MAINTAIN with the module onReset key list in
-- EllesmereUIBlizzardSkin/EUI_BlizzardSkin_Options.lua: a new account-global
-- setting added to either tab must be added here too or it will not travel.
--
-- Deliberately absent (state, not settings): lfgSavedRoles (the player's saved LFG
-- roles), charSheetCollapsedSections (transient UI state), characterFramePos /
-- friendsFramePos (dragged panel positions, resolution- bound), tooltipFixedPos (stale
-- account key; the live one is per-profile and rides the profile itself),
-- blizzWindowModernBG (dead key, read nowhere).
-------------------------------------------------------------------------------
local BLIZZ_SKIN_GLOBAL_KEYS = {}
do
    local keys = BLIZZ_SKIN_GLOBAL_KEYS
    local function add(list)
        for _, k in ipairs(list) do keys[#keys + 1] = k end
    end
    -- Tooltips, Menus & Popups tab
    add({
        "customTooltips", "tooltipFontScale", "tooltipPlayerTitles",
        "tooltipItemLevel", "tooltipMythicScore", "tooltipShowMount",
        "tooltipShowGuildRank", "tooltipShowTarget", "tooltipShowMode",
        "tooltipShowModifier", "tooltipGrowthDirection",
        "uberTooltips", "uberTooltipsManual", "tooltipHideHealthStrip",
        "tooltipAnchorCursor", "tooltipCursorPosition",
        "tooltipCursorOffsetX", "tooltipCursorOffsetY",
        "tooltipBgColor", "tooltipBgOpacity", "tooltipBorderSize",
        "showSpellID", "spellIDModifier", "showIconID", "showItemID",
        "showItemMaxStacks", "itemStackModifier",
        "reskinPopupsMenus", "reskinGameMenu", "reskinQueuePopup",
        "showQueueTimer", "queueTimerTextColor", "queueTimerTextSize",
        "queueTimerBarHeight", "queueTimerTextOffsetY",
        "resurrectAcceptGlow",
        "reskinWidgetBars", "widgetBarMinSize", "reskinExtraActionButton",
        "popupMenuButtonBackgroundColor", "popupMenuButtonTextColorMode",
        "popupMenuButtonTextColor",
        "accentReskinElements",
    })
    -- Shared border-editor key sets (tooltip / popup menu / popup menu button)
    for _, prefix in ipairs({ "tooltip", "popupMenu", "popupMenuButton" }) do
        for _, suffix in ipairs({
            "BorderTexture", "BorderThickness", "BorderColor",
            "BorderColorMode", "BorderOpacity", "BorderOffsetX",
            "BorderOffsetY", "BorderShiftX", "BorderShiftY", "BorderBehind",
        }) do
            keys[#keys + 1] = prefix .. suffix
        end
    end
    -- Window Skins tab: per-window enables + skin styles + shared look
    add({
        "themedCharacterSheet", "themedInspectSheet",
        "reskinLFGMenu", "reskinGreatVault", "reskinCollections",
        "reskinPlayerSpells", "reskinAdventureGuide", "reskinProfessionsBook",
        "reskinProfessions", "reskinWorldMap", "reskinGuild", "reskinCalendar",
        "reskinAchievements", "reskinMail", "reskinCatalyst", "reskinSocket",
        "reskinItemUpgrade", "reskinLoot", "reskinLootToast", "lootToastQualityStrip",
        "lootToastQualityStripMoney", "lootToastScale",
        "reskinBNetToast",
        "reskinLootRoll", "reskinLootHistory", "reskinGroupInvite",
        "reskinReadyCheck",
        "reskinMicroMenu", "reskinHousing", "reskinDressUp", "reskinTransmog",
        "reskinMerchant", "reskinAuctionHouse", "reskinMacros",
        "reskinSettings", "reskinAddonList", "reskinCraftOrders",
        "reskinTrainer", "reskinGossip", "reskinQuest", "reskinInspectRecipe",
        "reskinDelves", "reskinSocialUI",
        "reskinQueueStatus", "reskinDelvePicker", "reskinPlayerChoice",
        "reskinTrade",
        "blizzWindowSkinStyles", "blizzWindowModernDefault",
        "blizzWinAccentBar", "blizzWinBarFill", "blizzWinLinks",
        "thirdPartySkinsOff", "thirdPartySkinAddons",
    })
    -- Window Skins tab: per-window card options
    add({
        -- Character Sheet card
        "statCategoryColors", "statCategoryUseColor", "statSectionsOrder",
        "showMythicRating", "showItemLevel", "showUpgradeTrack", "showGems",
        "showEnchants", "showPvpItemLevel", "charSheetSocketPanel",
        "charSheetIconZoom", "charSheetEnchantNames", "charSheetEnchantSize",
        "flyoutItemLevels", "showCharSheetDurability", "charSheetDurabilityLocation",
        "charSheetDurabilityShowLabel", "showSecondaryRaw", "showSecondaryBoth",
        "showTertiaryRaw", "showTertiaryBoth", "showAdjustedStats",
        "showManaStat",
        -- Inspect card
        "inspectShowEnchants", "inspectShowItemLevel", "inspectShowUpgradeTrack",
        -- LFG / Merchant cards
        "lfgRememberRoles",
        "merchantShowAsList", "merchantListRowHeight", "merchantShowItemLevel",
    })
end

-- Snapshot the bundle for export. nil-valued keys are simply absent from the
-- snapshot; the import side clears keys absent from the bundle, so the
-- recipient lands on the exporter's EXACT two-tab configuration (absent =
-- that setting's default).
local function SnapshotBlizzSkinGlobals()
    if not EllesmereUIDB then return nil end
    local out = {}
    for _, k in ipairs(BLIZZ_SKIN_GLOBAL_KEYS) do
        local v = EllesmereUIDB[k]
        if v ~= nil then out[k] = DeepCopy(v) end
    end
    return out
end

-- Apply an imported bundle: every allowlisted key takes the bundle's value,
-- INCLUDING nil (absent = exporter default), so mixed old/new state can't
-- linger. Bundle keys this build doesn't know yet apply too (a newer exporter's keys
-- are inert on builds that never read them). Callers reload right after -- these
-- settings install at load, so no live re-apply is needed or attempted.
function EllesmereUI.ApplyBlizzSkinGlobals(bundle)
    if type(bundle) ~= "table" or not EllesmereUIDB then return end
    local known = {}
    for _, k in ipairs(BLIZZ_SKIN_GLOBAL_KEYS) do
        known[k] = true
        EllesmereUIDB[k] = DeepCopy(bundle[k])
    end
    for k, v in pairs(bundle) do
        if not known[k] then
            EllesmereUIDB[k] = DeepCopy(v)
        end
    end
end

function EllesmereUI.ExportProfile(profileName, includedFolders, includeLayout, includeCDM, cdmSpecs, includeGlobals, includeOverrides, includeBlizzSkin)
    if includeLayout == nil then includeLayout = true end  -- default ON
    -- Overrides (value stores + groups + unlock-layer forks + BM forks)
    -- default ON: headless full calls (Wago, partner installers) keep
    -- carrying the complete override system exactly as classic full exports
    -- always did; the export UI passes the user's explicit Include choice.
    if includeOverrides == nil then includeOverrides = true end
    -- CDM spell layouts default ON with every spec included (cdmSpecs nil =
    -- all specs with data). Headless callers -- the Wago UI Packs creator
    -- export and partner installers -- call this bare and must receive a
    -- COMPLETE profile; the opt-in + spec-picker experience belongs to the
    -- options UI, which always passes includeCDM and cdmSpecs explicitly.
    -- (The old nil=OFF default silently shipped every Wago pack without its
    -- CDM spell layouts: the exporter never saw it because the in-game export
    -- flow passes explicit values.)
    if includeCDM == nil then includeCDM = true end
    if includeGlobals == nil then includeGlobals = true end  -- default ON ("Include Global Settings")
    -- Blizz UI Enhanced account-global bundle: headless full calls (the Wago
    -- creator export, partner installers) default ON so a pack delivers the
    -- creator's complete look -- there is no UI in that path to opt in. The
    -- export UI always passes its explicit "Window Skins" Include choice
    -- (default off there: manual sharers opt in deliberately).
    if includeBlizzSkin == nil then includeBlizzSkin = true end
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
    -- never let it ride an export string. The import-flow stamps below it are
    -- payload metadata, never profile data -- strip any stale copies too (the
    -- export re-stamps them deliberately further down).
    exportData._importEstablishPending = nil
    exportData.overridesIncluded = nil
    exportData.overridesExcluded = nil
    exportData.partialImport     = nil
    exportData.layoutExcluded    = nil
    exportData.blizzSkinGlobals      = nil
    exportData.applyBlizzSkinGlobals = nil
    exportData.applyUIScale          = nil
    -- UI accent color (per-profile): serialize the RESOLVED accent for THIS profile
    -- (works for active and non-active profiles; never mutates the stored profile, and
    -- is rename-immune since it is a data-root field, not an addons[] folder key).
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
    -- Profile-global appearance (fonts, custom colours, dark mode, accent)
    -- and the account UI scale ride only when "Global Settings" is included
    -- (default ON) -- full and subset exports alike, since the unified export
    -- flow offers the toggle for both (2026-07-20 redesign; the old subset
    -- path dropped uiScale unconditionally, which would have regressed scale
    -- transfer once the separate full-export button was removed). Off = the
    -- recipient keeps their own look and scale.
    if not includeGlobals then
        exportData.fonts        = nil
        exportData.customColors = nil
        exportData.darkMode     = nil
        exportData.euiAccent    = nil
        exportData.uiScale      = nil
    end
    -- Blizz UI Enhanced account-global bundle ("Window & Tooltip Skins"):
    -- rides when includeBlizzSkin resolves true -- explicit opt-in from the export UI's
    -- "Window Skins" Include item, or the headless default (see the nil-default above:
    -- Wago packs deliver the creator's complete look). Gated on the module being loaded
    -- so a build without Blizz UI Enhanced never ships an empty bundle. Bundle presence
    -- in a string is therefore always deliberate, which is what lets the importer treat
    -- presence as the apply signal (the import dialog's checkbox strips the bundle for
    -- recipient-side opt-out).
    if includeBlizzSkin and EllesmereUI.IsModuleAddonLoaded("EllesmereUIBlizzardSkin") then
        exportData.blizzSkinGlobals = SnapshotBlizzSkinGlobals()
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
    -- Override system (2026-07-20 redesign): ALL-OR-NOTHING under the single
    -- "Overrides" include. Value stores, group definitions, the spec/cond unlock-layer
    -- FORKS, and the BM forks travel together or not at all -- there is no per-module
    -- override merging anymore (and forks were never per-module separable anyway).
    -- Excluded -> strip everything and stamp overridesExcluded so the importer KEEPS
    -- the recipient's stores instead of reading the stripped nils as "exporter had
    -- none, wipe yours". Included on a SUBSET export -> stamp overridesIncluded: subset
    -- strings default to keep-recipient at import (matching legacy subset behavior), so
    -- carrying overrides needs the positive marker.
    if includeOverrides then
        if includedFolders then
            exportData.overridesIncluded = true
        end
    else
        exportData.specOverrides       = nil
        exportData.specOverrideGroups  = nil
        exportData.specOverrideNextId  = nil
        exportData.condOverrides       = nil
        exportData.condOverrideGroups  = nil
        exportData.condOverrideNextId  = nil
        exportData.specUnlockOverrides = nil
        exportData.condUnlockOverrides = nil
        exportData.specBmOverrides     = nil
        exportData.condBmOverrides     = nil
        exportData.specDmOverrides     = nil
        exportData.condDmOverrides     = nil
        exportData.unlockOverrideAnchors = nil
        exportData.overridesExcluded   = true
    end
    -- Layout deliberately excluded: stamped for the importer's baseline
    -- layout handling (kept for compatibility; fork keep/take is governed by
    -- the overrides stamps above since the 2026-07-20 redesign).
    if not includeLayout then
        exportData.layoutExcluded = true
    end
    -- A subset export IS a partial import regardless of what the recipient
    -- checks: stamp it at the source so the store merge takes the same
    -- keep-existing subset path the import dialog stamps on deselection.
    if includedFolders then
        exportData.partialImport = true
    end
    -- Per-character account data (gold ledger, upgrade-calc caches) never rides
    -- a shared string -- see PRIVATE_ADDON_KEYS. exportData is already a deep
    -- copy, so this strips the payload without touching the stored profile.
    StripPrivateAddonData(exportData.addons)
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

-------------------------------------------------------------------------------
--  FULL ACCOUNT EXPORT  (separate format, purely additive)
--
--  A string that carries the WHOLE central store: every account-global key
--  plus the ACTIVE profile. The recipient ends up with the exporter's entire
--  setup, including everything a normal profile string deliberately refuses
--  to carry -- HoverCast bindings, CDM spell assignments, Quality of Life
--  account settings, unlock anchors and size matches, UI scale, profile
--  keybinds, spec assignments, first-install state.
--
--  It shares NOTHING with ExportProfile / ImportProfile: no include toggles,
--  no per-module filtering, no canonical re-keying, no store merging, no
--  partial/override stamps. Those functions are untouched and never see a
--  full-account payload -- the import UI routes on the `fullExport` stamp
--  before the normal flow is reached.
--
--  The builder copies the store WHOLESALE and subtracts, rather than listing
--  what to include: any account key added in a future version rides
--  automatically instead of being silently missed.
--
--  Excluded by design -- per-character data that is nobody else's:
--    dataBarsGold         cross-character gold ledger
--    qolUpgradeCalcChars  Upgrade Calculator per-character cache
--  (The same two blobs PRIVATE_ADDON_KEYS strips from normal strings, at
--  their current top-level homes.)
-------------------------------------------------------------------------------
local FULL_EXPORT_TYPE = "fullaccount"
local FULL_EXPORT_EXCLUDED = {
    dataBarsGold        = true,
    qolUpgradeCalcChars = true,
}

--- Builds a full-account export string, or nil.
function EllesmereUI.ExportFullAccountData()
    if not EllesmereUIDB then return nil end
    if not LibDeflate then return nil end
    -- Same freshness boundary the profile export uses: bank live override
    -- edits into their stores before snapshotting.
    if EllesmereUI.SpecOverrides_HarvestCurrent then
        EllesmereUI.SpecOverrides_HarvestCurrent()
    end
    local db = GetProfilesDB()
    local activeName = db.activeProfile or "Default"
    local out = {}
    for k, v in pairs(EllesmereUIDB) do
        if k ~= "profiles" and not FULL_EXPORT_EXCLUDED[k] then
            out[k] = DeepCopy(v)
        end
    end
    -- ONLY the active profile travels; the exporter's other profiles are
    -- their own business and would overwrite same-named profiles on import.
    out.profiles = {}
    local prof = db.profiles and db.profiles[activeName]
    if prof then
        local copy = DeepCopy(prof)
        -- Freshen profile-global appearance and the unlock layout from live,
        -- mirroring what ExportProfile does for the active profile -- but on
        -- the COPY. A full export never mutates stored data.
        copy.fonts        = DeepCopy(EllesmereUI.GetFontsDB())
        copy.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        copy.darkMode     = DeepCopy(EllesmereUI.GetDarkModeDB())
        copy.unlockLayout = SnapshotUnlockLayout()
        -- Recipient-local import bookkeeping never rides a string.
        copy._importEstablishPending = nil
        -- The gold ledger and Upgrade Calculator cache also have LEGACY homes
        -- inside the module profile blobs (see PRIVATE_ADDON_KEYS); an older
        -- profile can still carry them there, and they are excluded from a
        -- full export at every address they have ever lived at.
        StripPrivateAddonData(copy.addons)
        out.profiles[activeName] = copy
    end
    out.activeProfile = activeName
    out.profileOrder  = { activeName }
    local payload = {
        version     = 3,
        type        = FULL_EXPORT_TYPE,
        fullExport  = true,     -- the routing stamp the import flow reads
        profileName = activeName,
        data        = out,
    }
    local serialized = Serializer.Serialize(payload)
    local compressed = LibDeflate:CompressDeflate(serialized)
    return EXPORT_PREFIX .. LibDeflate:EncodeForPrint(compressed)
end

--- True for a decoded payload produced by ExportFullAccountData. The import
--- UI checks this BEFORE handing anything to the normal profile flow.
function EllesmereUI.IsFullAccountPayload(payload)
    return type(payload) == "table"
        and (payload.fullExport == true or payload.type == FULL_EXPORT_TYPE)
end

--- Applies a full-account payload and reloads. Replaces every account-global
--- key the string carries and installs its profile, then reloads so every
--- module rebuilds from the new store. Caller owns the confirmation.
function EllesmereUI.ImportFullAccountData(payload)
    if not EllesmereUI.IsFullAccountPayload(payload) then return false end
    local data = payload.data
    if type(data) ~= "table" or not EllesmereUIDB then return false end
    local activeName = data.activeProfile or payload.profileName or "Default"

    -- 1) Account globals, wholesale. profiles/profileOrder/activeProfile are
    --    handled below; the excluded per-character blobs are refused on the
    --    way IN as well, so a hand-edited string cannot plant a gold ledger.
    for k, v in pairs(data) do
        if k ~= "profiles" and k ~= "profileOrder" and k ~= "activeProfile"
           and not FULL_EXPORT_EXCLUDED[k] then
            EllesmereUIDB[k] = DeepCopy(v)
        end
    end

    -- 2) The carried profile. The recipient's OTHER profiles survive; a
    --    same-named profile is replaced (that is the import).
    if type(EllesmereUIDB.profiles) ~= "table" then EllesmereUIDB.profiles = {} end
    if type(data.profiles) == "table" then
        for name, pdata in pairs(data.profiles) do
            local copy = DeepCopy(pdata)
            -- Legacy per-profile homes of the excluded blobs (see the export
            -- side): refused on the way in too.
            StripPrivateAddonData(copy.addons)
            EllesmereUIDB.profiles[name] = copy
        end
    end
    if type(EllesmereUIDB.profiles[activeName]) ~= "table" then
        EllesmereUIDB.profiles[activeName] = {}
    end

    -- 3) Order list: keep the recipient's and append, never replace -- a
    --    wholesale copy would drop their own profiles out of the picker.
    local order = EllesmereUIDB.profileOrder
    if type(order) ~= "table" then order = {}; EllesmereUIDB.profileOrder = order end
    local listed = false
    for _, n in ipairs(order) do
        if n == activeName then listed = true; break end
    end
    if not listed then order[#order + 1] = activeName end
    EllesmereUIDB.activeProfile = activeName

    -- 4) Re-point the live db objects at the imported profile's tables before
    --    reloading. Lite's PLAYER_LOGOUT write-back copies every db.profile
    --    into profiles[activeProfile].addons[folder]; still pointing at the
    --    OLD tables it would overwrite the freshly imported blobs with the
    --    recipient's current values on the way out. Pointer swap ONLY -- no
    --    defaults merge, no sync handoff, no module refresh: the reload
    --    rebuilds all of that from the imported store.
    local registry = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if registry then
        local pdata = EllesmereUIDB.profiles[activeName]
        if type(pdata.addons) ~= "table" then pdata.addons = {} end
        for _, dbo in ipairs(registry) do
            if dbo.folder then
                if type(pdata.addons[dbo.folder]) ~= "table" then
                    pdata.addons[dbo.folder] = {}
                end
                dbo.profile = pdata.addons[dbo.folder]
                dbo._profileName = activeName
            end
        end
    end

    ReloadUI()
    return true
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
    -- Same nil-default as ExportProfile: bare (headless/API) calls get the
    -- complete profile including CDM spell layouts for every spec; the
    -- options export flow always passes the user's explicit choice.
    if includeCDM == nil then includeCDM = true end
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
    -- Per-character account data (gold ledger, upgrade-calc caches) likewise
    -- never rides a shared string -- see PRIVATE_ADDON_KEYS. SnapshotAllAddons
    -- deep-copies each module's live profile blob, so a profile still holding
    -- the legacy keys (any profile other than the one cleaned at login) would
    -- otherwise ship its character list through this path.
    StripPrivateAddonData(profileData.addons)
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
    -- Drop account data an older exporter left in the string, before any
    -- consumer (preview UI, ImportProfile, Wago) can write it to a profile.
    -- Type-checked, not just truthy: a corrupt string can deserialize to a
    -- non-table data field, and indexing that would raise instead of letting
    -- the caller report its own decode failure.
    if type(payload.data) == "table" then StripPrivateAddonData(payload.data.addons) end
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
            -- Same strip as the sync path: account data never reaches a profile.
            if type(payload.data) == "table" then StripPrivateAddonData(payload.data.addons) end
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

-- Per-profile CDM spell store helpers. The CDM spell/bar-content store lives at
-- EllesmereUIDB.spellAssignments.profiles[name].specProfiles -- a top-level table
-- OUTSIDE the profile blob, so it never travels with profile export or module sync
-- (both operate on the profile's addons blob). These helpers fork/move/drop a profile's
-- CDM bucket in lockstep with the profile itself. Defined above ImportProfile so all
-- profile-lifecycle functions can use it.
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

-- Build an imported profile's per-profile CDM spell bucket on the same
-- merge-base-on-active contract as the addon blobs: START from a copy of the ACTIVE
-- profile's spell store, so specs the incoming string does not carry keep the current
-- profile's layouts VERBATIM (they are the user's own current data -- no import flags
-- or migrations touch them), THEN overlay the incoming specs and arm
-- import-authoritative ghosting on THOSE ONLY, so the importer's tracked-but-unplaced
-- spells get hidden (not spilled onto a default bar) once the profile is active. Runs
-- even with no incoming specs (inherit-only): an imported profile must never pair
-- inherited CDM bar definitions with an empty spell store. Existing bucket keys other
-- than specProfiles are preserved on overwrite, and the active bucket may BE the target
-- bucket (overwriting the active profile): inheritance copies into a fresh table before
-- specProfiles is replaced, so that case is a clean self-copy plus incoming overlay.
local function BuildImportedCDMSpellBucket(profileName, activeName, incomingSpecs, importedBarsCfg)
    if not EllesmereUIDB then return end
    EllesmereUIDB.spellAssignments = EllesmereUIDB.spellAssignments or { profiles = {} }
    local sa = EllesmereUIDB.spellAssignments
    sa.profiles = sa.profiles or {}
    local bucket = sa.profiles[profileName] or {}
    sa.profiles[profileName] = bucket
    local inherited = {}
    local activeBucket = sa.profiles[activeName]
    if activeBucket and type(activeBucket.specProfiles) == "table" then
        for specKey, sp in pairs(activeBucket.specProfiles) do
            if type(sp) == "table" then inherited[specKey] = DeepCopy(sp) end
        end
    end
    bucket.specProfiles = inherited
    if type(incomingSpecs) ~= "table" then return end
    -- Import-authoritative ghosting is computed against the player's LIVE Blizzard CDM
    -- tracked set (viewer pools + category API). That set is only guaranteed settled
    -- after a reload, and the ghost pass is a ONE-SHOT that stamps _barFilterModelV6
    -- the first time it succeeds -- so a pass that runs against a mid-change tracked
    -- set writes a permanently wrong ghost list. Runtime-only flag (dies with the
    -- session) telling the pass to wait for a later session. The interactive import
    -- flow never noticed because its caller ReloadUI()s in the same frame ImportProfile
    -- returns, which kills the queued reanchor that would have run the pass; a caller
    -- that defers its reload (installer wizards) gets the pass mid-session instead.
    if EllesmereUI then EllesmereUI._cdmImportGhostDeferred = true end
    for specKey, specProf in pairs(DeepCopy(incomingSpecs)) do
        bucket.specProfiles[specKey] = specProf
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
            -- Collided-buff cooldownID claims moved from the
            -- assignedBuffCdIDs side-table to cd-claim markers inside
            -- assignedSpells; convert old-format imports too (idempotent),
            -- or their claims sit unread and the slots silently unclaim.
            if EllesmereUI.MigrateCdmBuffCdClaims then
                EllesmereUI.MigrateCdmBuffCdClaims(specProf)
            end
            -- Strings exported before _buffDisplayOrderUserModified existed carry a
            -- drag-arranged buffDisplayOrder without the flag; stamp it or the first
            -- live reconcile resyncs the imported order to Blizzard order (idempotent).
            if EllesmereUI.MigrateCdmBuffOrderUserFlag then
                EllesmereUI.MigrateCdmBuffOrderUserFlag(specProf)
            end
        end
    end
end

--- Drop applied Visibility override MARKERS (store.visibilityOverride) from imported
--- addon data. Every other applied override value is an ordinary setting and stays, as it
--- always has; this one key is different because it REPLACES an element's whole Visibility
--- setting and has no control of its own outside an editing session. Arriving without the
--- override store that owns it, it would pin that element on Never/Always/Mouseover with
--- nothing able to write it back. A marker the recipient's OWN override still owns is
--- restored by that override's next apply, so stripping is safe in both directions.
local function StripStrandedVisOverrides(addons)
    if type(addons) ~= "table" then return end
    local seen = {}
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        t.visibilityOverride = nil
        for _, v in pairs(t) do
            if type(v) == "table" then walk(v) end
        end
    end
    for _, snap in pairs(addons) do
        if type(snap) == "table" then walk(snap) end
    end
end

--- Import a profile string. Returns: success, errorMsg
--- The caller must provide a name for the new profile.
function EllesmereUI.ImportProfile(importStr, profileName)
    -- A concurrent silent import (e.g. the Wago path) invalidates any pending
    -- INTERACTIVE import session: its selection UI is stale against the
    -- profile data this call is about to change. The interactive flow's own
    -- commit sets `committing` around this call, so it never cancels itself.
    do
        local s = EllesmereUI._apiImportSession
        if s and s.state ~= "done" and not s.committing then
            EllesmereUI._FinishApiImportSession(false)
            if EllesmereUI._ProfilesResetToMain then pcall(EllesmereUI._ProfilesResetToMain) end
        end
    end
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
        -- The Blizz UI Enhanced bundle + its opt-in marker are payload-root
        -- transport, never profile data -- strip so they can't ride into the
        -- stored profile (applied separately below).
        imported.blizzSkinGlobals      = nil
        imported.applyBlizzSkinGlobals = nil

        -- UI scale (account-wide): PRESENCE IS CONSENT (2026-07-20, matching Window
        -- Skins). The import dialog's scale-mismatch popup runs before its commit and
        -- STRIPS uiScale from the payload when the user picks Keep Mine (or the
        -- scales already match), so a value still present is either the dialog's
        -- accepted Match Scale choice or a headless (Wago / partner / silent API)
        -- full-string import -- which applies the creator's scale by default,
        -- matching overrides, CDM spell layouts, and window skins. Writing the
        -- account keys here lets the caller's imminent reload apply the new scale
        -- (EllesmereUI_Startup reads ppUIScale). Range matches PP.PixelBestSize's
        -- clamp; out-of-range values are ignored.
        if type(payload.data.uiScale) == "number" and EllesmereUIDB then
            local s = payload.data.uiScale
            if s >= 0.40 and s <= 1.15 then
                EllesmereUIDB.ppUIScale = s
                EllesmereUIDB.ppUIScaleAuto = false
            end
        end

        -- Blizz UI Enhanced account-global bundle ("Window & Tooltip Skins"):
        -- applied whenever the string CARRIES it -- presence is consent (2026-07-20):
        -- a bundle only ever rides via the exporter's explicit "Window Skins" Include
        -- choice or the headless full-export default, and the import dialog's
        -- "Include Window Skins" checkbox STRIPS the bundle when unchecked (after its
        -- overwrite confirmation), so the recipient-side opt-out still holds.
        -- Headless (Wago / partner / silent API) full-string imports therefore apply
        -- the creator's window skins by default, matching overrides and CDM spell
        -- layouts. Writes the account-wide keys now; the caller's imminent reload
        -- applies them (these skins install at load).
        if type(payload.data.blizzSkinGlobals) == "table" then
            EllesmereUI.ApplyBlizzSkinGlobals(payload.data.blizzSkinGlobals)
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
        -- Per-profile migration stamps must reflect the PAYLOAD's data vintage, not the
        -- base profile's. On a fresh install the base (active) profile carries no
        -- stamps yet, so without this the next load would run every profile-scope
        -- migration over the just-imported data as if it were legacy. A current-version
        -- export carries its own stamps; a genuinely old string carries none and still
        -- gets migrated, which is the intended behavior for old data.
        if type(imported._migrations) == "table" then
            merged._migrations = DeepCopy(imported._migrations)
        end
        -- Take fonts/colors from import if present. A string exported without
        -- "Global Settings" lacks these keys entirely, so the base copy's
        -- (recipient's) appearance stands; presence means the exporter chose
        -- to share the look, and it applies regardless of module selection.
        if imported.fonts then merged.fonts = DeepCopy(imported.fonts) end
        if imported.customColors then merged.customColors = DeepCopy(imported.customColors) end
        if imported.darkMode then merged.darkMode = DeepCopy(imported.darkMode) end
        -- Override stores: ALL-OR-NOTHING (2026-07-20 redesign; the old per-folder
        -- value merge in SpecOverrides_MergeImportedStores is retired and must not be
        -- re-wired). Taking -> the exporter's complete override system (values + groups
        -- + unlock-layer forks + BM forks) replaces the recipient's wholesale, ids
        -- verbatim: an incoming store is internally consistent, and with nothing
        -- merging there is nothing to remap or dedupe. Not taking -> the base copy's
        -- (recipient's) stores stand untouched. Gate: the explicit overridesIncluded
        -- stamp (new subset exports / the import dialog's Include Overrides checkbox),
        -- or a FULL string without an exclusion stamp (classic full-import semantics).
        -- Legacy subset strings (partialImport, no positive stamp) keep the recipient's
        -- stores, preserving their old keep-mine behavior.
        do
            local takeOverrides = imported.overridesIncluded == true
                or (imported.partialImport ~= true and imported.overridesExcluded ~= true)
            if takeOverrides then
                local OV_KEYS = {
                    "specOverrides", "specOverrideGroups", "specOverrideNextId",
                    "condOverrides", "condOverrideGroups", "condOverrideNextId",
                    "specUnlockOverrides", "condUnlockOverrides",
                    "specBmOverrides", "condBmOverrides",
                    "specDmOverrides", "condDmOverrides",
                    "unlockOverrideAnchors",
                }
                for _, k in ipairs(OV_KEYS) do
                    merged[k] = imported[k]
                end
            else
                -- The recipient's stores stand, so nothing in the incoming addon data
                -- owns an applied Visibility override marker it carries.
                StripStrandedVisOverrides(merged.addons)
            end
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
                -- CONTRACT (see SnapshotUnlockLayout): while a spec/cond group's unlock
                -- layer is LIVE, the raw globals hold that FORK's links -- overlaying
                -- them raw stamped the fork as the new profile's baseline (the one
                -- snapshot writer the Cluster-A hardening missed: importing while
                -- playing a forked spec leaked its geometry onto every spec of the new
                -- profile). Source through the same baseline-resolved snapshot every
                -- other writer uses; TBB child entries are carried from live inside it.
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
        -- BASELINE-LINKS == PROFILE-LINKS contract (imported-profile DM
        -- window snap, 2026-07-20): whichever override store this profile ends up
        -- with (kept from the recipient on a partial import, or taken from the
        -- exporter), its baselineLayout link tables must mirror the freshly merged
        -- unlockLayout above -- a kept store's baseline predates the merge, and a
        -- taken store's mirrors the exporter's layout rather than the per-module
        -- mix. The import-establish forced converge applies baseline LINKS over the
        -- live tables at the first post-import login, so stale ones silently wiped
        -- the recipient's just-merged anchors there. Links only: elems stay
        -- untouched (elems of anchored children are additionally inert via the
        -- FlushUnlock anchor-owned guard).
        do
            local s2 = merged.specUnlockOverrides
            local ul2 = merged.unlockLayout
            if type(s2) == "table" and type(s2.baselineLayout) == "table" and type(ul2) == "table" then
                s2.baselineLayout.anchors     = DeepCopy(ul2.anchors     or {})
                s2.baselineLayout.widthMatch  = DeepCopy(ul2.widthMatch  or {})
                s2.baselineLayout.heightMatch = DeepCopy(ul2.heightMatch or {})
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
        -- CDM spell allocation: inherit-then-overlay via the shared builder
        -- (BuildImportedCDMSpellBucket above): specs missing from the string
        -- keep the ACTIVE profile's spell layouts -- the same
        -- merge-base-on-active contract the addon blobs use -- and incoming
        -- specs arm ghosting + the old-format migrations. Runs for strings
        -- with no cdmSpells too (inherit-only), so an imported profile never
        -- pairs inherited bar definitions with an empty spell store. Note:
        -- db.activeProfile still names the PRE-import active profile here
        -- (activation happens further down), which is exactly the inheritance
        -- source the contract wants.
        do
            local importedBarsCfg = payload.data.addons
                and payload.data.addons["EllesmereUICooldownManager"]
                and payload.data.addons["EllesmereUICooldownManager"].cdmBars
                and payload.data.addons["EllesmereUICooldownManager"].cdmBars.bars
            BuildImportedCDMSpellBucket(profileName, db.activeProfile or "Default",
                payload.data.cdmSpells, importedBarsCfg)
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
            -- Import window guard, spec_locked flavor: the merged profile was built on
            -- the dirty active profile all the same, so its first ACTIVATION (e.g. a
            -- later login preseeding onto an auto-assigned spec) hits the same
            -- unguarded pre-apply harvest as a direct import. The flag sits inert while
            -- the profile is stored; whichever session first activates it clears it at
            -- its first apply. Runtime armed flag deliberately NOT set here: this
            -- session keeps its own active profile.
            db.profiles[profileName]._importEstablishPending = true
            -- First-install captures: an imported profile is a chosen layout.
            -- Stamp the one-shot capture flags so a capture that has not
            -- fired yet cannot overwrite this stored profile's layout data
            -- once a later session activates it.
            db._capturedOnce_EAB = true
            db._capturedOnce_CDM = true
            db._capturedOnce_RF = true
            return true, nil, "spec_locked"
        end
        -- Flush the OUTGOING (currently active) profile's LIVE unlock data into its
        -- snapshot BEFORE switching to the imported profile. The live
        -- EllesmereUIDB.unlock* tables are the source of truth; a profile's stored
        -- unlockLayout only LAGS them (it is refreshed on switch-away/export, not
        -- continuously). SwitchProfile does this flush (~2326); import did NOT -- so
        -- importing, switching back to the old profile (which then restored its STALE
        -- snapshot over the live anchors), then deleting the import silently dropped
        -- every anchor / width-match the user had set on the old profile since it was
        -- last saved (they survived only inside the imported profile, so deleting it
        -- lost them for good). This is the reported "bars lose their anchors and width
        -- match after import" bug. Spec Overrides: sync the outgoing profile's
        -- current-spec values with live edits before the imported profile takes over.
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
        -- Import window guard: suppress unlock/BM LAYOUT banks from now until the first
        -- apply of a later session. The imported store already holds the exporter's
        -- layers verbatim; live geometry in this window is mid-import residue
        -- (inherited link tables, unconverged anchors), and any boundary harvest -- the
        -- import-tail Conditions recheck, the caller's ReloadUI firing PLAYER_LOGOUT,
        -- the first post-login spec transition -- would wholesale-replace a pristine
        -- bucket with it. Persisted on the profile root so it survives the reload; the
        -- companion runtime flag stops THIS session's applies (the SpecOverrides_Apply
        -- below) from closing the window early. Cleared unconditionally at the first
        -- apply of any later session; value harvests are never suppressed.
        db.profiles[profileName]._importEstablishPending = true
        EllesmereUI._importGuardArmedNow = true
        -- Custom colours resolve live via GetCustomColorsDB. In GLOBAL colour mode the
        -- shared palette comes from colorsPullFrom (or the first profile); a recipient
        -- who pinned a specific source would store the imported palette but keep seeing
        -- their own. When the import actually carries colours, point the global source
        -- at the imported profile so its palette is what shows. Getter-redirect only --
        -- never wipes or restores a live colour table (that is banned). Per-profile
        -- mode reads the active (now imported) profile already, so it needs no change.
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
        -- NO default re-bank here. The imported entries carry the EXPORTER's recorded
        -- values.default, consistent with the imported addon blobs by construction
        -- (MergeImportedStores partitions per folder). The old
        -- SpecOverrides_RebaselineDefaults pass overwrote those recorded defaults with
        -- the imported LIVE blob -- which holds the exporter's CURRENT SPEC's override
        -- values (SnapshotAllAddons restores canonical spec values, not defaults) --
        -- permanently destroying the exporter's true defaults and bleeding one spec's
        -- values into every unassigned spec on the recipient. Spec Overrides: apply the
        -- imported profile's stored values for the current spec on top of the
        -- just-applied addon data.
        if EllesmereUI.SpecOverrides_Apply then
            EllesmereUI.SpecOverrides_Apply(curSpecID)
        end
        -- First-install captures: an imported profile is a chosen layout. Stamp the
        -- one-shot capture flags (central-store root keys; the capture handlers
        -- re-check them at fire time) so a capture that has not fired yet -- deferred
        -- past login, spec-gated, or armed by a module first enabled in a later session
        -- -- can never overwrite the imported data with live-captured layout state.
        db._capturedOnce_EAB = true
        db._capturedOnce_CDM = true
        db._capturedOnce_RF = true
        -- The minimap capture flag is per-profile. Stamp the imported profile's minimap
        -- table (after ApplyProfileData, so the write sticks) in case the payload
        -- predates the flag or came from an install that never ran the Minimap module.
        do
            if not merged.addons then merged.addons = {} end
            local mm = merged.addons.EllesmereUIMinimap
            if type(mm) ~= "table" then
                mm = {}
                merged.addons.EllesmereUIMinimap = mm
            end
            if type(mm.minimap) ~= "table" then mm.minimap = {} end
            mm.minimap._capturedOnce = true
        end
        -- A successful import means real user data exists: close the first-install
        -- window now instead of at the next login's data-detection pass, so first-run
        -- popups and capture paths stay quiet from here on.
        db.firstInstallPopupShown = true
        EllesmereUI._firstInstallPending = nil
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
        if payload.data.condDmOverrides then merged.condDmOverrides = DeepCopy(payload.data.condDmOverrides) end
        if payload.data.specDmOverrides then
            merged.specDmOverrides = DeepCopy(payload.data.specDmOverrides)
        end
        if payload.data.unlockOverrideAnchors then
            merged.unlockOverrideAnchors = DeepCopy(payload.data.unlockOverrideAnchors)
        end
        -- Kept override stores survive a partial import by design (the base profile
        -- continues), but BM forks are Raid Frames-scoped: drop kept ones when the
        -- payload replaces RF settings they were built against. UN-PARKING NOTE: this
        -- branch only STORES the profile (never activates it), so it must NOT call
        -- SpecOverrides_RebaselineDefaults here -- that re-banks the ACTIVE profile's
        -- stores. When this branch is revived, run the re-bank synchronously at
        -- activation time, scoped to payload.data.addons folders (mirror the
        -- full-import call after ApplyProfileData). Never a deferred flag: the import
        -- flow ends in ReloadUI, which destroys in-memory state.
        do
            local folders = {}
            if payload.data and payload.data.addons then
                for folder in pairs(payload.data.addons) do folders[folder] = true end
            end
            if folders["EllesmereUIRaidFrames"] then
                if not payload.data.specBmOverrides then merged.specBmOverrides = nil end
                if not payload.data.condBmOverrides then merged.condBmOverrides = nil end
                if not payload.data.specDmOverrides then merged.specDmOverrides = nil end
                if not payload.data.condDmOverrides then merged.condDmOverrides = nil end
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
        -- CDM spell allocation: same inherit-then-overlay contract as the full branch
        -- (BuildImportedCDMSpellBucket). Subset strings carry cdmSpells only when the
        -- CDM module was included in the export; either way the imported profile's
        -- spell bucket pairs coherently with its (imported or inherited) bar
        -- definitions instead of being dropped entirely, which this branch previously
        -- did for the modern cdmSpells format.
        do
            local importedBarsCfg = payload.data and payload.data.addons
                and payload.data.addons["EllesmereUICooldownManager"]
                and payload.data.addons["EllesmereUICooldownManager"].cdmBars
                and payload.data.addons["EllesmereUICooldownManager"].cdmBars.bars
            BuildImportedCDMSpellBucket(profileName, current,
                payload.data and payload.data.cdmSpells, importedBarsCfg)
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
    -- Global colour source: deleting the source profile must not leave a
    -- dangling pointer (the stale name showed in Pull Colors From, the shared
    -- palette silently fell back, and colour editing locked because the user
    -- could never be "on" the deleted source). nil = default (first profile).
    if EllesmereUIDB.colorsPullFrom == name then
        EllesmereUIDB.colorsPullFrom = nil
        EllesmereUI.ApplyColorsToOUF()
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
    -- Keep the global colour source following the renamed profile (same
    -- palette table, so no colour refresh is needed).
    if EllesmereUIDB.colorsPullFrom == oldName then
        EllesmereUIDB.colorsPullFrom = newName
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

    -- An open unlock session cannot survive a profile switch (same rule as spec changes
    -- and condition flips): its movers, snapshots, and pending edits all belong to the
    -- OUTGOING profile's stores -- committing or harvesting them after the swap would
    -- write them into the WRONG profile's layers and snapshots. Discard-close first.
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

        -- Unlock mode cannot survive a spec transition: movers, session snapshots, and
        -- pending edits all belong to the OUTGOING spec's layout (unlock mode always
        -- displays the current spec), so a stale save would corrupt both baseline and
        -- spec-override data. Force- close DISCARDING the session before any harvest or
        -- apply runs. Combat parity is free: the whole handler defers to REGEN above.
        if specTransition and EllesmereUI.ForceCloseUnlockDiscard then
            EllesmereUI.ForceCloseUnlockDiscard()
        end

        -- Spec Overrides: harvest the outgoing spec's live values into the still-active
        -- profile BEFORE any spec-profile switch below, and mark the transition so
        -- mid-swap harvests can't mis-key values. Cross-char re-entries pass no old
        -- spec (live values may belong to another character's spec).
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
            -- No spec assignment for this character and character changed (alt swap).
            -- If the current activeProfile is spec-assigned (left over from the
            -- previous character), switch to the last non-spec profile so this
            -- character doesn't inherit another character's spec layout. Skip on plain
            -- /reload (same char) to respect the user's intentional profile choice.
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

        -- Spec Overrides: apply the incoming spec's stored values. Any spec-profile
        -- switch above already applied values inside its RefreshAllAddons pass, so this
        -- duplicate is a value-equal no-op there; it is the ONLY apply for same-profile
        -- spec changes and plain first logins.
        if specTransition and EllesmereUI.SpecOverrides_Apply then
            EllesmereUI.SpecOverrides_Apply(specID, isFirstLogin)
        end
    end)
end

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

-------------------------------------------------------------------------------
--  Interactive Import API (separate from the silent ImportProfile above; the
--  Wago path keeps calling ImportProfile unchanged).
--
--  A partner addon hands over an import string and the USER completes the
--  import through the normal options import flow: UI-scale prompt, per-module
--  selection page, profile name, final Import click. Contract:
--    * callback(true)  -- the user completed the final Import step. The forced
--      reload is SUPPRESSED and the options panel closes: the CALLER now owns
--      the ReloadUI() at the end of its own install flow. (The imported-but-
--      not-yet-reloaded state is the same one the silent Wago path has always
--      produced.)
--    * callback(false) -- the user closed the options panel without importing,
--      the string failed to decode, or a silent ImportProfile call replaced
--      the session. Tab switches inside the panel do NOT decline (the user
--      can navigate back and resume), and a combat auto-close keeps the
--      session alive to resume when the panel reopens.
--    * The callback may never fire if the player reloads or logs out with the
--      session open -- callers must not hard-block waiting on it.
--  One session at a time: a second call while one is live fails fast.
--
--  opts: importString (required), profileName (optional prefill for the name
--  box), source (optional display name of the caller), callback (optional).
--  Returns true, or false + reason when the call could not start a session.
-------------------------------------------------------------------------------
function EllesmereUI.ImportProfileInteractive(opts)
    if type(opts) ~= "table" or type(opts.importString) ~= "string"
        or opts.importString == "" then
        return false, "invalid arguments"
    end
    if InCombatLockdown() then return false, "in combat" end
    local existing = EllesmereUI._apiImportSession
    if existing and existing.state ~= "done" then
        return false, "an interactive import is already pending"
    end

    -- First-open split (see _SplitFirstOpen): on the session's first open the
    -- navigation below only LOADS and the panel builds next frame, so the
    -- Profiles page -- and with it _ProfilesConsumeApiImport -- does not exist
    -- yet. Re-run the whole call next frame instead; the session is not created
    -- until then, so the re-entry is not blocked as "already pending".
    if EllesmereUI:_SplitFirstOpen(function()
        EllesmereUI.ImportProfileInteractive(opts)
    end) then return true end

    EllesmereUI._apiImportSession = {
        str      = opts.importString,
        name     = type(opts.profileName) == "string" and opts.profileName or nil,
        source   = type(opts.source) == "string" and opts.source or nil,
        callback = type(opts.callback) == "function" and opts.callback or nil,
        state    = "pending",   -- pending -> active (import page up) -> done
    }
    -- Land on the Profiles page (opens the panel if needed). The page builder registers
    -- _ProfilesConsumeApiImport when it builds -- either during this navigation or from
    -- an earlier cached visit -- so after navigating, enter the import flow through the
    -- CURRENT build's registered entry. Never force a rebuild here: a rebuild
    -- mid-consume orphans the async decode's continuation on destroyed page frames.
    EllesmereUI:NavigateToElementSettings("_EUIProfiles", "Profiles")
    EllesmereUI._EnsureApiImportCloseHook()
    if EllesmereUI._ProfilesConsumeApiImport then
        EllesmereUI._ProfilesConsumeApiImport()
    end
    return true
end

--- Fire the session callback exactly once and clear the session. pcall'd so a
--- partner error can never break the import flow that invoked it.
function EllesmereUI._FinishApiImportSession(accepted)
    local s = EllesmereUI._apiImportSession
    if not s or s.state == "done" then return end
    s.state = "done"
    EllesmereUI._apiImportSession = nil
    if s.callback then pcall(s.callback, accepted and true or false) end
end

--- Decline-on-close: closing the options panel with a live session counts as
--- "no". Installed once on the main frame (ours, so HookScript is safe); the
--- success path finishes the session BEFORE hiding the panel, so this handler
--- only ever fires for genuine user closes.
do
    local hooked = false
    function EllesmereUI._EnsureApiImportCloseHook()
        if hooked then return end
        local mf = EllesmereUI._mainFrame
        if not mf then return end  -- panel not built yet; consumer retries
        hooked = true
        mf:HookScript("OnHide", function()
            local s = EllesmereUI._apiImportSession
            if not s or s.state == "done" then return end
            -- Combat auto-close is not a decision: keep the session so it
            -- resumes when the panel reopens out of combat.
            if InCombatLockdown() then return end
            EllesmereUI._FinishApiImportSession(false)
            -- Clear the stale import page out of the cached Profiles wrapper
            -- so reopening the panel shows the normal Profiles view.
            if EllesmereUI._ProfilesResetToMain then pcall(EllesmereUI._ProfilesResetToMain) end
        end)
    end
end

-------------------------------------------------------------------------------
--  Silent partner-installer import (public API, additive)
--
--  Ports a creator's export string EXACTLY for installer addons that own the
--  whole setup (no EUI dialogs); the interactive dialog flow is untouched.
--  Fonts, custom colors, accent, CDM spell layouts, overrides, the
--  window/tooltip skin bundle and UI scale all apply as carried (presence is
--  consent), so the recipient lands on the creator's complete look.
--
--  opts:
--    importString  (required) the creator's export string.
--    profileName   (required) target profile name.
--    disableAddons (optional) suite child FOLDER names the pack replaces with
--                  external addons. Strips them from the payload (addon blobs
--                  incl. hosted sub-modules; CDM spell layouts if the CDM
--                  module is listed; the window/tooltip skin bundle if the skin
--                  module is listed); filters cross-module layout relationships
--                  down to kept modules so no anchor or size-match edge can
--                  reference a module that will have no frames; after a
--                  successful import disables those folders and ENABLES every
--                  other suite child (authoritative list -- children added after
--                  a pack shipped enable by default), recording the bags choice
--                  so the bag-addon auto-disable respects the pack's
--                  composition. The shared-services shim and the parent addon
--                  are load-bearing for every child and are never disabled.
--    cleanSlate    (default true) delete an existing profile of the same name
--                  first: importing onto an existing name inherits its
--                  name-keyed external buckets (CDM spell store, spec
--                  assignments, sync targets), and DeleteProfile is the one
--                  path that purges them all.
--    applyUIScale  (default true) false strips the string's UI scale so the
--                  user keeps their own.
--    autoAssignSpecs (default false) true keeps the exporter's spec->profile
--                  assignments; headless presence would apply them, so
--                  installers opt in deliberately.
--
--  Returns ok, err. NEVER reloads: the caller owns the ReloadUI at the end of
--  its own flow (addon enable/disable state also only applies then).
-------------------------------------------------------------------------------
function EllesmereUI.ImportProfileSilent(opts)
    if type(opts) ~= "table" or type(opts.importString) ~= "string"
        or opts.importString == "" then
        return false, "invalid arguments"
    end
    if type(opts.profileName) ~= "string" or opts.profileName == "" then
        return false, "profileName is required"
    end
    if InCombatLockdown() then return false, "in combat" end
    local profileName = opts.profileName

    -- Decode once and hand ImportProfile the TABLE. Never re-encode a decoded
    -- payload: a serializer round trip is not identity on decoded content.
    local payload = EllesmereUI.DecodeImportString(opts.importString)
    if type(payload) ~= "table" or type(payload.data) ~= "table" then
        return false, "could not decode import string"
    end

    -- Normalize + guard the disable set.
    local disable
    if type(opts.disableAddons) == "table" then
        disable = {}
        for _, folder in ipairs(opts.disableAddons) do
            if type(folder) == "string" then disable[folder] = true end
        end
        disable["EllesmereUI"] = nil
    end

    if disable then
        -- Partition profile-data modules into stripped vs kept (canonical keys,
        -- matching the payload), resolving hosted sub-modules through their host addon.
        local keepCanon, stripCanon = {}, {}
        for _, e in ipairs(ADDON_DB_MAP) do
            local canon = FOLDER_TO_CANON[e.folder] or e.folder
            if disable[e.folder] or (e.hostAddon and disable[e.hostAddon]) then
                stripCanon[canon] = true
            else
                keepCanon[canon] = true
            end
        end
        if payload.data.addons then
            for canon in pairs(stripCanon) do
                payload.data.addons[canon] = nil
            end
        end
        -- CDM spell layouts live outside the addon blob.
        if disable["EllesmereUICooldownManager"] then
            payload.data.cdmSpells = nil
        end
        -- The account-global window/tooltip skin bundle belongs to the skin
        -- module; a pack that replaces it must not apply the bundle.
        if disable["EllesmereUIBlizzardSkin"] then
            payload.data.blizzSkinGlobals      = nil
            payload.data.applyBlizzSkinGlobals = nil
        end
        -- Keep only layout relationships whose endpoints both survive: the
        -- same per-element filter the import dialog applies on deselection.
        local ul = payload.data.unlockLayout
        if ul then
            local meta = payload.data.unlockLayoutMeta
            local k2f = EllesmereUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
            payload.data.unlockLayout = EllesmereUI.FilterLayoutToFolders(ul, keepCanon, k2f)
        end
    end
    -- Meta is transport-only; never let it persist into the profile.
    payload.data.unlockLayoutMeta = nil

    if opts.applyUIScale == false then
        payload.data.uiScale      = nil
        payload.data.applyUIScale = nil
    end
    if not opts.autoAssignSpecs then
        payload.data.assignedSpecs = nil
    end

    -- Clean slate (see doc block above).
    if opts.cleanSlate ~= false then
        local db = GetProfilesDB()
        if db.profiles and db.profiles[profileName] then
            EllesmereUI.DeleteProfile(profileName)
        end
    end

    local ok, err, status = EllesmereUI.ImportProfile(payload, profileName)
    if not ok then return false, err end

    -- Apply the pack's folder composition (takes effect at the caller's
    -- reload). Enabling sweeps the whole suite so children added after a
    -- pack shipped default ON instead of ending up in neither set.
    if disable and C_AddOns and C_AddOns.EnableAddOn then
        local exists = C_AddOns.DoesAddOnExist
        local seen = {}
        local function apply(folder)
            if seen[folder] then return end
            seen[folder] = true
            if exists and not exists(folder) then return end
            if disable[folder] then
                C_AddOns.DisableAddOn(folder)
            else
                C_AddOns.EnableAddOn(folder)
            end
        end
        for _, e in ipairs(ADDON_DB_MAP) do
            apply(e.hostAddon or e.folder)
        end
        -- The pack made the bags decision; keep the bag-addon auto-disable
        -- from overriding it later.
        if EllesmereUIDB then EllesmereUIDB.bagsUserChosen = true end
    end

    return true, nil, status
end

-------------------------------------------------------------------------------
--  External installer registration
--  A partner installer that owns the whole first-run experience calls this at
--  its ADDON_LOADED (every session). While registered, the suite's own
--  first-install picker stays silent -- the picker's reload-handshake flag
--  still arms, so first-run popups stay quiet until the installer's import
--  completes (the import stamps first-install state). Fail-open: if the
--  installer never imports, the picker returns on a later login without a
--  registration.
-------------------------------------------------------------------------------
function EllesmereUI.RegisterExternalInstaller(displayName)
    EllesmereUI._externalInstaller = (type(displayName) == "string" and displayName ~= "")
        and displayName or true
end

