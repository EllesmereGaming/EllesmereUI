local ADDON_NAME = ...
local IGS = CreateFrame("Frame")

-- -----------------------------------------------------------------------------
-- EllesmereUI integration: palette + third-party skin scaffold
-- (see EllesmereUI/SKINNING_API.md; everything is a silent no-op without EUI)
-- -----------------------------------------------------------------------------

local PALETTE = {
    accent = "0cd29f", -- EllesmereUI teal; follows the user's live EUI accent when skinned
    dim    = "8c8c8c", -- unassigned / "none"
    err    = "ff6b6b", -- soft error red
}

local function AC()   return "|cff" .. PALETTE.accent end
local function DIMC() return "|cff" .. PALETTE.dim end
local function ERRC() return "|cff" .. PALETTE.err end

local function PREFIX() return AC() .. "Loadout Manager|r" end

local Skin = {
    S = nil,                                   -- EUI skin facade (set by RegisterSkin callback)
    reg = {},                                  -- { { kind = ..., obj = ... }, ... }
    done = setmetatable({}, { __mode = "k" }), -- objects already painted ("native"/"facade")
    accented = {},                             -- accent-colored regions, recolored live
}

-- Guarded call into the facade: one bad primitive never aborts the whole skin.
local function TrySkin(fn, ...)
    if type(fn) ~= "function" then return false end
    return (pcall(fn, ...))
end

local function RegisterSkinnable(kind, obj)
    if not obj then return end
    Skin.reg[#Skin.reg + 1] = { kind = kind, obj = obj }
    if Skin.PaintOne then Skin.PaintOne(kind, obj) end -- paint at creation, facade or native
end

local SkinWarningFrame -- forward (needs the warning frame local below)

local DEFAULTS = {
    enabled = true,
    gearEnabled = true,
    talentEnabled = true,
    announce = true,
    debug = false,
    delay = 2,
    queueInCombat = true,

    -- Gear mappings use Blizzard Equipment Manager set names.
    instanceSets = {},      -- [instanceID] = equipment set name
    difficultySets = {},    -- [instanceID:difficultyID] = equipment set name
    typeDefaults = {},      -- party/raid/scenario/arena/pvp = equipment set name

    -- Talent mappings store { configID = number, name = string, specID = number }.
    talentInstanceSets = {},
    talentDifficultySets = {},
    talentTypeDefaults = {},

    -- Spec-aware layer: [specID] = the same six mapping tables as above.
    -- The root tables above act as the "All Specs" fallback layer.
    specDefaults = {},
    specSwap = true, -- re-run swaps when your specialization changes inside an instance
    uiScale = 1.0,   -- window scale (/lm scale 0.5-2.0)
    specWarning = true,  -- our themed "DONT MOVE" panel
    raidWarningText = false, -- Blizzard's orange RaidWarningFrame text; off by
                             -- default, the themed panel already covers it
}

local INSTANCE_TYPES = {
    world = true, -- pseudo-type: not in an instance (open world), applied on exit
    party = true,
    mplus = true, -- pseudo-type: Mythic/Mythic+ dungeons, outranks the party default
    delve = true, -- pseudo-type: Delves (report as scenarios)
    timewalking = true, -- pseudo-type: Timewalking dungeons and raids
    raid = true,
    scenario = true,
    arena = true,
    pvp = true,
}

local INSTANCE_TYPE_ORDER = {
    { key = "world", label = "Open World", hint = "Applied when you LEAVE an instance and return to the open world. Leave empty to keep whatever you are wearing." },
    { key = "party", label = "Dungeon / Party" },
    { key = "mplus", label = "Mythic+ Keystone", hint = "Mythic and Keystone dungeons. Beats the Dungeon / Party default." },
    { key = "timewalking", label = "Timewalking", hint = "Timewalking dungeons and raids. Beats their normal type default." },
    { key = "delve", label = "Delve", hint = "Delves. Beats the Scenario default." },
    { key = "raid", label = "Raid" },
    { key = "scenario", label = "Scenario" },
    { key = "arena", label = "Arena" },
    { key = "pvp", label = "Battleground / PvP" },
}

local queuedSetName = nil
local queuedSetReason = nil
local queuedTalent = nil
local queuedTalentReason = nil

-- Equipment sets and talent configs are not cached the instant we log in or
-- zone into an instance: C_EquipmentSet.GetEquipmentSetIDs() can return an
-- empty list for a second or two. A swap firing in that window used to print
-- "Could not find Equipment Manager set named X" for a set that exists and
-- then drop the swap entirely. These hold the pending retry so the swap
-- survives the cache warming up.
local pendingGear = nil        -- { name = ..., reason = ..., tries = n }
local pendingTalent = nil      -- { stored = ..., reason = ..., tries = n }
local MAX_LOOKUP_RETRIES = 10
local lastLoadedConfigID = nil -- re-synced to the talent UI on TRAIT_CONFIG_UPDATED
local expectedSet = nil        -- { name = ..., at = time } verified on EQUIPMENT_SWAP_FINISHED
local RetryPendingGear, RetryPendingTalent -- forward
local lastAttemptKey = nil
local lastAttemptTime = 0
local lastTalentAttemptKey = nil
local lastTalentAttemptTime = 0
local lastAutoInstanceKey = nil

local UI = {
    frame = nil,
    selectedSet = nil,
    selectedTalent = nil,
    defaultRows = {},
    scopeTabs = {},
    assignScope = nil, -- nil = All Specs layer; otherwise a specID
}

local RefreshUI
-- Several events commonly fire together (equipment set changed + swap finished
-- + loadout changed). Each used to schedule its own full rebuild, so one gear
-- swap could run RefreshUI half a dozen times. Coalesce them into one pass.
-- Lightweight counters for /lm perf. Incrementing an integer is negligible and
-- this is the only way to see which event is actually spinning in a live raid.
local Perf = { events = {}, refreshes = 0, swapAttempts = 0, talentAttempts = 0, checks = 0, since = nil }
local function PerfCount(bucket)
    Perf[bucket] = (Perf[bucket] or 0) + 1
end

local refreshScheduled = false
local function RequestRefresh(delay)
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(delay or 0.2, function()
        refreshScheduled = false
        Perf.refreshes = Perf.refreshes + 1
        RefreshUI()
    end)
end

local function Print(msg)
    print(PREFIX() .. " " .. tostring(msg))
end

-- Varargs, not a pre-built string: callers pass pieces so the concatenation
-- (and its garbage) only happens when debugging is actually enabled. These sit
-- in the swap hot path, which runs on every equipment/talent event.
local function Debug(...)
    if not (InstanceGearSwapDB and InstanceGearSwapDB.debug) then return end
    local n = select("#", ...)
    if n == 1 then
        Print("|cffaaaaaaDebug:|r " .. tostring((...)))
        return
    end
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    Print("|cffaaaaaaDebug:|r " .. table.concat(parts))
end

local function Trim(s)
    -- gsub returns (string, count); capture one value so callers can safely
    -- pass Trim() results into multi-argument functions like tonumber.
    local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

local function SplitFirst(s)
    s = Trim(s)
    local first, rest = s:match("^(%S+)%s*(.-)$")
    return first or "", Trim(rest or "")
end

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- CopyDefaults walks the whole defaults tree; EnsureDB() guards ~30 call sites
-- including every gear/talent swap, so do the walk once and cheap-guard after.
-- Reset on ADDON_LOADED, when saved variables replace the global.
local dbReady = false
local function EnsureDB()
    if dbReady and InstanceGearSwapDB then return end
    InstanceGearSwapDB = CopyDefaults(DEFAULTS, InstanceGearSwapDB)
    dbReady = true
end

local function Announce(msg)
    if InstanceGearSwapDB and InstanceGearSwapDB.announce then Print(msg) end
end


-- -----------------------------------------------------------------------------
-- Specialization scopes
-- Assignments live in two layers: per-spec buckets in DB.specDefaults[specID],
-- and the legacy root tables as the "All Specs" layer. UI.assignScope picks
-- which layer the window edits (nil = All Specs).
-- -----------------------------------------------------------------------------

local SPEC_TABLE_KEYS = {
    "instanceSets", "difficultySets", "typeDefaults",
    "talentInstanceSets", "talentDifficultySets", "talentTypeDefaults",
}

local function GetSpecTables(specID, create)
    if not specID then return nil end
    EnsureDB()
    local bucket = InstanceGearSwapDB.specDefaults[specID]
    if not bucket then
        if not create then return nil end
        bucket = {}
        InstanceGearSwapDB.specDefaults[specID] = bucket
    end
    for i = 1, #SPEC_TABLE_KEYS do
        local k = SPEC_TABLE_KEYS[i]
        if not bucket[k] then bucket[k] = {} end
    end
    return bucket
end

-- A class's specialization list never changes during a session, but SpecName()
-- is called several times per refresh and each call rebuilt the table from API
-- queries. Cache the first non-empty result (it is empty until spec info loads).
local specListCache = nil
local function GetSpecList()
    if specListCache then return specListCache end
    local list = {}
    local n = (GetNumSpecializations and GetNumSpecializations()) or 0
    for i = 1, n do
        local id, name, _, icon = GetSpecializationInfo(i)
        if id then list[#list + 1] = { id = id, name = name, icon = icon } end
    end
    if #list > 0 then specListCache = list end
    return list
end

local function SpecName(specID)
    if not specID then return nil end
    local list = GetSpecList()
    for i = 1, #list do
        if list[i].id == specID then return list[i].name end
    end
    return "Spec " .. tostring(specID)
end

local function ScopeSuffix(scopeID)
    if scopeID then return " for " .. AC() .. tostring(SpecName(scopeID)) .. "|r" end
    return " for " .. AC() .. "all specs|r"
end

-- Copy every assignment table from another scope into the active one.
-- Talent entries belong to a spec: copying into a spec scope keeps only that
-- spec's loadouts; the All Specs destination keeps everything.
local CopyScopeFrom -- assigned below (needs Print/RefreshUI upvalues resolved late)

-- Read-only stand-in when a spec has no bucket yet.
local EMPTY_SCOPE = {
    instanceSets = {}, difficultySets = {}, typeDefaults = {},
    talentInstanceSets = {}, talentDifficultySets = {}, talentTypeDefaults = {},
}

local function GetWriteTables()
    if UI.assignScope then
        return GetSpecTables(UI.assignScope, true), UI.assignScope
    end
    EnsureDB()
    return InstanceGearSwapDB, nil
end

CopyScopeFrom = function(sourceID)
    EnsureDB()
    local dst, dstID = GetWriteTables()
    local srcT = sourceID and (GetSpecTables(sourceID, false) or EMPTY_SCOPE) or InstanceGearSwapDB
    local skippedTalents = 0
    for _, k in ipairs(SPEC_TABLE_KEYS) do
        local copy = {}
        for key, v in pairs(srcT[k] or {}) do
            if type(v) == "table" then
                if dstID and v.specID and tonumber(v.specID) ~= tonumber(dstID) then
                    skippedTalents = skippedTalents + 1
                else
                    local t2 = {}
                    for a, b in pairs(v) do t2[a] = b end
                    copy[key] = t2
                end
            else
                copy[key] = v
            end
        end
        dst[k] = copy
    end
    local srcName = sourceID and tostring(SpecName(sourceID)) or "All Specs"
    local msg = "Copied assignments from " .. AC() .. srcName .. "|r" .. ScopeSuffix(dstID) .. "."
    if skippedTalents > 0 then
        msg = msg .. " Skipped " .. skippedTalents .. " talent entr" .. (skippedTalents == 1 and "y" or "ies") ..
            " belonging to other specs."
    end
    Print(msg)
    RefreshUI()
end

local function GetReadTables()
    if UI.assignScope then
        return GetSpecTables(UI.assignScope, false) or EMPTY_SCOPE, UI.assignScope
    end
    EnsureDB()
    return InstanceGearSwapDB, nil
end

local specChangeWarningFrame = nil
local specChangeWarningTimer = nil

local function HideSpecChangeWarning()
    if specChangeWarningFrame then
        specChangeWarningFrame:Hide()
    end
end

local function ShowSpecChangeWarning(message, duration, force)
    EnsureDB()
    if not force and not InstanceGearSwapDB.specWarning then return end
    message = message or "DONT MOVE - CHANGING SPECS"
    duration = tonumber(duration) or 4

    -- Blizzard's raid-warning channel renders as big orange centred text,
    -- separate from our themed panel below. Opt-in only.
    if InstanceGearSwapDB.raidWarningText
        and RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
        RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
    end

    if not UIParent or not CreateFrame then return end

    if not specChangeWarningFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetSize(560, 92)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.title:SetPoint("CENTER", f, "CENTER", 0, 13)
        f.title:SetTextColor(1, 0.12, 0.08, 1)

        f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.subtitle:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.subtitle:SetTextColor(1, 1, 0.25, 1)
        f.subtitle:SetText("Wait until the loadout finishes.")

        f:Hide()
        specChangeWarningFrame = f
        SkinWarningFrame()
    end

    specChangeWarningFrame.title:SetText(message)
    specChangeWarningFrame:Show()

    if specChangeWarningTimer and specChangeWarningTimer.Cancel then
        specChangeWarningTimer:Cancel()
    end

    if C_Timer and C_Timer.NewTimer then
        specChangeWarningTimer = C_Timer.NewTimer(duration, HideSpecChangeWarning)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(duration, HideSpecChangeWarning)
    end
end

local function BuildDifficultyKey(instanceID, difficultyID)
    if not instanceID or not difficultyID then return nil end
    return tostring(instanceID) .. ":" .. tostring(difficultyID)
end

-- Called several times per refresh and on every zone event. The result is
-- always consumed immediately and never stored, so reuse one table instead of
-- allocating a fresh one each call.
local contextCache = {}
local function GetCurrentInstanceContext()
    local inInstance, instanceType = IsInInstance()
    local name, instanceType2, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, lfgDungeonID = GetInstanceInfo()

    instanceType = instanceType2 or instanceType or "none"

    local ctx = contextCache
    ctx.inInstance = inInstance
    ctx.instanceType = instanceType
    ctx.name = name or "Unknown"
    ctx.difficultyID = difficultyID
    ctx.difficultyName = difficultyName
    ctx.instanceID = instanceID
    ctx.maxPlayers = maxPlayers
    ctx.instanceGroupSize = instanceGroupSize
    ctx.lfgDungeonID = lfgDungeonID
    return ctx
end

-- -----------------------------------------------------------------------------
-- Gear sets
-- -----------------------------------------------------------------------------

-- True when the client has cached at least one equipment set. An empty list
-- right after login/zoning means "not ready yet", not "no sets exist".
local function EquipmentCacheReady()
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return true end
    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return false end
    if #ids == 0 then return false end
    -- IDs present but names not yet populated is also "warming up"
    local name = C_EquipmentSet.GetEquipmentSetInfo(ids[1])
    return name ~= nil
end

local function GetEquipmentSetIDByName(setName)
    if not setName or setName == "" or not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then
        return nil
    end

    local wanted = tostring(setName):lower()
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name and name:lower() == wanted then
            return setID, name
        end
    end
    return nil
end

local function GetSetInfoByName(setName)
    local setID, canonicalName = GetEquipmentSetIDByName(setName)
    if not setID then return nil end
    local name, iconFileID, equipmentSetID, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return {
        setID = setID,
        name = canonicalName or name,
        iconFileID = iconFileID,
        isEquipped = isEquipped,
        numItems = numItems,
        numEquipped = numEquipped,
        numInInventory = numInInventory,
        numLost = numLost,
        numIgnored = numIgnored,
    }
end

-- Enumerating equipment sets and talent configs allocates a table per entry and
-- sorts; RefreshUI used to do it four times per call, and equipment events fire
-- constantly in a raid. Cache the results and rebuild only when the game tells
-- us they changed (see InvalidateGearCache / InvalidateTalentCache).
local cacheGear, cacheGearDetailed, cacheTalents, cacheTalentSpec

local function ByNameAsc(a, b) return a.name < b.name end
local function ByNameLowerAsc(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end

local function InvalidateGearCache()
    cacheGear, cacheGearDetailed = nil, nil
end

local function InvalidateTalentCache()
    cacheTalents, cacheTalentSpec = nil, nil
end

local function ListEquipmentSetsDetailed()
    if cacheGearDetailed then return cacheGearDetailed end
    local sets = {}
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return sets end
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then table.insert(sets, { name = name, icon = icon }) end
    end
    table.sort(sets, ByNameAsc)
    cacheGearDetailed = sets
    return sets
end

local function ListEquipmentSets()
    if cacheGear then return cacheGear end
    local sets = {}
    for _, set in ipairs(ListEquipmentSetsDetailed()) do
        sets[#sets + 1] = set.name -- already sorted by name
    end
    cacheGear = sets
    return sets
end

local function SetExists(setName)
    return GetEquipmentSetIDByName(setName) ~= nil
end

local GetAssignedSetForContext -- defined after GetCurrentSpecID (spec-aware)

local function InActiveKeystone()
    if not (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive) then return false end
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    return ok and active == true
end

local function TryEquipSet(setName, reason)
    EnsureDB()

    if InActiveKeystone() then
        Print("Keystone active: gear is locked until the run ends. Swap skipped.")
        return
    end

    if not InstanceGearSwapDB.enabled or not InstanceGearSwapDB.gearEnabled then
        Debug("gear swapping disabled; not swapping")
        return
    end

    setName = Trim(setName)
    if setName == "" then return end

    if InCombatLockdown() then
        if InstanceGearSwapDB.queueInCombat then
            queuedSetName = setName
            queuedSetReason = reason or "queued"
            Announce("In combat. Queued gear set " .. AC() .. "" .. setName .. "|r for after combat.")
        else
            Announce("In combat. Gear swap skipped.")
        end
        return
    end

    local info = GetSetInfoByName(setName)
    if not info then
        -- Distinguish "cache not ready" from "set really is gone"
        local tries = (pendingGear and pendingGear.name == setName and pendingGear.tries or 0) + 1
        if tries <= MAX_LOOKUP_RETRIES and not EquipmentCacheReady() then
            pendingGear = { name = setName, reason = reason, tries = tries }
            Debug("equipment sets not cached yet; retry ", tries, " for ", setName)
            C_Timer.After(1, RetryPendingGear)
            return
        end
        pendingGear = nil
        Print("Could not find Equipment Manager set named " .. ERRC() .. "" .. setName ..
            "|r. It may have been renamed or deleted - run " .. AC() .. "/lm verify|r to find stale assignments.")
        return
    end
    pendingGear = nil

    if info.isEquipped then
        Debug("already wearing ", info.name)
        return
    end

    local now = GetTime and GetTime() or 0
    local attemptKey = tostring(info.setID) .. ":" .. tostring(reason or "auto")
    if attemptKey == lastAttemptKey and (now - lastAttemptTime) < 1.5 then
        Debug("throttled duplicate gear swap attempt for ", info.name)
        return
    end
    lastAttemptKey = attemptKey
    lastAttemptTime = now

    if info.numLost and info.numLost > 0 then
        Announce("Gear set " .. AC() .. "" .. info.name .. "|r has " .. tostring(info.numLost) ..
            " missing item(s) - they may be in the bank or void storage. Equipping the rest.")
    end
    expectedSet = { name = info.name, at = (GetTime and GetTime()) or 0 }

    Perf.swapAttempts = Perf.swapAttempts + 1
    local ok = C_EquipmentSet.UseEquipmentSet(info.setID)
    if ok == false then
        queuedSetName = info.name
        queuedSetReason = reason or "retry"
        Announce("Gear swap call failed. Queued retry for " .. AC() .. "" .. info.name .. "|r.")
    else
        Announce("Equipping gear " .. AC() .. "" .. info.name .. "|r" .. (reason and (" (" .. reason .. ")") or "") .. ".")
    end
end

-- -----------------------------------------------------------------------------
-- Talent loadouts
-- -----------------------------------------------------------------------------

local function GetCurrentSpecID()
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then
        local ok, specID = pcall(PlayerUtil.GetCurrentSpecID)
        if ok and specID then return specID end
    end

    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local specID = GetSpecializationInfo(specIndex)
            return specID
        end
    end
    return nil
end

local function NormalizeTalentStored(stored)
    if not stored then return nil end
    if type(stored) == "table" then return stored end
    if type(stored) == "number" then return { configID = stored } end
    if type(stored) == "string" then return { name = stored } end
    return nil
end

local function ListTalentLoadouts()
    local specID = GetCurrentSpecID()
    if cacheTalents and cacheTalentSpec == specID then return cacheTalents end
    local loadouts = {}
    if not specID or not C_ClassTalents or not C_ClassTalents.GetConfigIDsBySpecID or not C_Traits or not C_Traits.GetConfigInfo then
        return loadouts
    end

    local ok, configIDs = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not ok or type(configIDs) ~= "table" then return loadouts end

    for _, configID in ipairs(configIDs) do
        local okInfo, info = pcall(C_Traits.GetConfigInfo, configID)
        local name = okInfo and info and info.name
        if configID and name then
            table.insert(loadouts, { configID = configID, name = name, specID = specID })
        end
    end

    table.sort(loadouts, ByNameLowerAsc)
    cacheTalents, cacheTalentSpec = loadouts, specID
    return loadouts
end

local function GetTalentLoadoutInfoByID(configID)
    configID = tonumber(configID)
    if not configID or not C_Traits or not C_Traits.GetConfigInfo then return nil end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or not info then return nil end
    local specID = GetCurrentSpecID()
    return { configID = configID, name = info.name or ("Loadout " .. tostring(configID)), specID = specID }
end

local function FindTalentLoadoutByName(name)
    if not name or name == "" then return nil end
    local wanted = tostring(name):lower()
    for _, loadout in ipairs(ListTalentLoadouts()) do
        if loadout.name and loadout.name:lower() == wanted then
            return loadout
        end
    end
    return nil
end

local function GetTalentLoadoutFromStored(stored)
    stored = NormalizeTalentStored(stored)
    if not stored then return nil end

    if stored.configID then
        local info = GetTalentLoadoutInfoByID(stored.configID)
        if info then return info end
    end

    if stored.name then
        return FindTalentLoadoutByName(stored.name)
    end

    return nil
end

local function StoreTalentLoadout(loadout)
    if not loadout then return nil end
    return {
        configID = tonumber(loadout.configID),
        name = loadout.name,
        specID = loadout.specID or GetCurrentSpecID(),
    }
end

local function TalentDisplayName(stored)
    local info = GetTalentLoadoutFromStored(stored)
    if info and info.name then return info.name end
    stored = NormalizeTalentStored(stored)
    if stored and stored.name then return stored.name end
    if stored and stored.configID then return "Loadout " .. tostring(stored.configID) end
    return nil
end

local function TalentExists(stored)
    return GetTalentLoadoutFromStored(stored) ~= nil
end

-- Difficulty IDs that map onto pseudo-types. Delves report as scenarios and
-- Timewalking keeps its parent type, so both are identified by difficulty.
local MPLUS_DIFFICULTIES = { [8] = true, [23] = true }        -- Keystone, Mythic
local TIMEWALKING_DIFFICULTIES = { [24] = true, [33] = true } -- TW dungeon, TW raid
local DELVE_DIFFICULTIES = { [208] = true, [209] = true, [210] = true, [211] = true }

-- Ordered list of type keys to try for a context, most specific first.
local function TypeKeysForContext(ctx)
    if not ctx or not ctx.inInstance then return { "world" } end
    local diff = ctx.difficultyID
    local base = ctx.instanceType
    if diff and TIMEWALKING_DIFFICULTIES[diff] then return { "timewalking", base } end
    if base == "scenario" and diff and DELVE_DIFFICULTIES[diff] then return { "delve", base } end
    if base == "party" and diff and MPLUS_DIFFICULTIES[diff] then return { "mplus", base } end
    if base then return { base } end
    return {}
end

-- A stored talent loadout is only usable by the spec it belongs to.
local function TalentMatchesSpec(stored, specID)
    local sid = type(stored) == "table" and stored.specID or nil
    if not sid or not specID then return true end
    return tonumber(sid) == tonumber(specID)
end

-- Shared resolver. Within each specificity level (difficulty > instance > type)
-- the current spec's assignment wins over the All Specs assignment. Returns
-- value, source, key, scopeSpecID (nil scope = matched the All Specs layer).
local function ResolveForContext(ctx, kInst, kDiff, kType, validator)
    EnsureDB()
    if not ctx then return nil, "no-context" end
    local specID = GetCurrentSpecID()
    local spec = specID and InstanceGearSwapDB.specDefaults[specID] or nil

    -- Outside an instance only the Open World default applies (no instance ID
    -- to key specific mappings against).
    if not ctx.inInstance then
        local candidates = {
            { spec and spec[kType], specID },
            { InstanceGearSwapDB[kType], nil },
        }
        for i = 1, #candidates do
            local tbl = candidates[i][1]
            local value = tbl and tbl["world"]
            if value and (not validator or validator(value, specID)) then
                return value, "type", "world", candidates[i][2]
            end
        end
        return nil, "unassigned"
    end

    if not ctx.instanceID then return nil, "missing-instance-id" end

    local instanceKey = tostring(ctx.instanceID)
    local diffKey = BuildDifficultyKey(ctx.instanceID, ctx.difficultyID)

    local candidates = {
        { spec and spec[kDiff], diffKey, "difficulty", specID },
        { InstanceGearSwapDB[kDiff], diffKey, "difficulty", nil },
        { spec and spec[kInst], instanceKey, "instance", specID },
        { InstanceGearSwapDB[kInst], instanceKey, "instance", nil },
    }
    -- Type-level keys, most specific first (mplus/timewalking/delve before
    -- their parent type).
    local typeKeys = TypeKeysForContext(ctx)
    for i = 1, #typeKeys do
        candidates[#candidates + 1] = { spec and spec[kType], typeKeys[i], "type", specID }
        candidates[#candidates + 1] = { InstanceGearSwapDB[kType], typeKeys[i], "type", nil }
    end
    for i = 1, #candidates do
        local c = candidates[i]
        local tbl, key = c[1], c[2]
        local value = tbl and key and tbl[key]
        if value and (not validator or validator(value, specID)) then
            return value, c[3], key, c[4]
        end
    end
    return nil, "unassigned"
end

GetAssignedSetForContext = function(ctx)
    return ResolveForContext(ctx, "instanceSets", "difficultySets", "typeDefaults")
end

local function GetAssignedTalentForContext(ctx)
    return ResolveForContext(ctx, "talentInstanceSets", "talentDifficultySets", "talentTypeDefaults", TalentMatchesSpec)
end

-- The talent UI keeps its own idea of the selected loadout. After we load a
-- config the dropdown still shows the previous entry (and its Apply Changes
-- state goes stale) unless we tell the frame directly. Handles the 11.0+
-- PlayerSpellsFrame and the older ClassTalentFrame.
local function SyncTalentUI(configID)
    local tab = (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame)
             or (ClassTalentFrame and ClassTalentFrame.TalentsTab)
    if not tab then return end

    -- autoApply=false, skipLoad=true: the config is already loaded, this only
    -- moves the frame's selection so the dropdown and buttons match reality.
    if tab.SetSelectedSavedConfigID then
        pcall(tab.SetSelectedSavedConfigID, tab, configID, false, true)
    end
    -- Blizzard has renamed these across expansions and the dropdown lives in a
    -- different child each time, so try every known refresh path; each is a
    -- no-op when absent. One of them owns the checkmark.
    if tab.lastSelectedSavedConfigID ~= nil then tab.lastSelectedSavedConfigID = configID end
    for _, method in ipairs({ "RefreshLoadoutOptions", "UpdateConfigButtonsState",
                              "UpdateSelections", "RefreshConfigID", "UpdateStarterBuildHighlights" }) do
        if tab[method] then pcall(tab[method], tab) end
    end
    for _, child in ipairs({ "LoadoutDropDown", "LoadSystem", "DropDown" }) do
        local dd = tab[child]
        if dd then
            if dd.SetSelectionID then pcall(dd.SetSelectionID, dd, configID) end
            for _, m in ipairs({ "UpdateSelections", "Update", "GenerateMenu" }) do
                if dd[m] then pcall(dd[m], dd) end
            end
        end
    end
end

-- Enum.LoadConfigResult with numeric fallbacks in case the enum moves.
local function LoadResultCodes()
    local e = Enum and Enum.LoadConfigResult
    return (e and e.Error) or 0, (e and e.NoChangesNecessary) or 1, (e and e.LoadInProgress) or 2
end

local function TryLoadTalentLoadout(stored, reason)
    EnsureDB()

    if InActiveKeystone() then
        Print("Keystone active: talents are locked until the run ends. Swap skipped.")
        return
    end

    if not InstanceGearSwapDB.enabled or not InstanceGearSwapDB.talentEnabled then
        Debug("talent swapping disabled; not swapping")
        return
    end

    local loadout = GetTalentLoadoutFromStored(stored)
    if not loadout then
        -- Talent configs are also cached late; only complain once they exist.
        local tries = (pendingTalent and pendingTalent.tries or 0) + 1
        if tries <= MAX_LOOKUP_RETRIES and #ListTalentLoadouts() == 0 then
            pendingTalent = { stored = stored, reason = reason, tries = tries }
            Debug("talent configs not cached yet; retry ", tries)
            C_Timer.After(1, RetryPendingTalent)
            return
        end
        pendingTalent = nil
        Print("Could not find the assigned talent loadout for your current spec.")
        return
    end
    pendingTalent = nil

    if InCombatLockdown() then
        if InstanceGearSwapDB.queueInCombat then
            queuedTalent = StoreTalentLoadout(loadout)
            queuedTalentReason = reason or "queued"
            Announce("In combat. Queued talent loadout " .. AC() .. "" .. loadout.name .. "|r for after combat.")
        else
            Announce("In combat. Talent swap skipped.")
        end
        return
    end

    if C_ClassTalents and C_ClassTalents.CanChangeTalents then
        local okCan, canChange = pcall(C_ClassTalents.CanChangeTalents)
        if okCan and canChange == false then
            if InstanceGearSwapDB.queueInCombat then
                queuedTalent = StoreTalentLoadout(loadout)
                queuedTalentReason = reason or "queued"
                Announce("Cannot change talents here yet. Queued " .. AC() .. "" .. loadout.name .. "|r.")
            else
                Announce("Cannot change talents here. Talent swap skipped.")
            end
            return
        end
    end

    local activeSavedID
    if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID then
        local specID = loadout.specID or GetCurrentSpecID()
        local okLast, lastID = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
        if okLast then activeSavedID = lastID end
    end
    if tonumber(activeSavedID) == tonumber(loadout.configID) then
        Debug("talent loadout already selected: ", loadout.name)
        return
    end

    local now = GetTime and GetTime() or 0
    local attemptKey = tostring(loadout.configID) .. ":" .. tostring(reason or "auto")
    if attemptKey == lastTalentAttemptKey and (now - lastTalentAttemptTime) < 2 then
        Debug("throttled duplicate talent loadout attempt for ", loadout.name)
        return
    end
    lastTalentAttemptKey = attemptKey
    lastTalentAttemptTime = now

    if not C_ClassTalents or not C_ClassTalents.LoadConfig then
        Print("Talent loadout API is not available on this client.")
        return
    end

    ShowSpecChangeWarning("DONT MOVE - CHANGING SPECS", 4)
    -- autoApply = true: apply and commit rather than staging changes behind the
    -- talent UI's "Apply Changes" button.
    Perf.talentAttempts = (Perf.talentAttempts or 0) + 1
    local okLoad, result = pcall(C_ClassTalents.LoadConfig, loadout.configID, true)
    if not okLoad then
        queuedTalent = StoreTalentLoadout(loadout)
        queuedTalentReason = reason or "retry"
        Print("Talent loadout failed: " .. tostring(result))
        return
    end

    -- pcall succeeding only means the call did not error; the API reports the
    -- real outcome in its return code. Treating Error as success is what made
    -- the addon claim it loaded a build that was only staged, never applied.
    local ERR, NO_CHANGE, IN_PROGRESS = LoadResultCodes()
    if result == ERR then
        local openUI = (PlayerSpellsFrame and PlayerSpellsFrame:IsShown())
                    or (ClassTalentFrame and ClassTalentFrame:IsShown())
        if openUI then
            Print("Could not apply " .. AC() .. "" .. loadout.name ..
                "|r while the talent window is open - close it and run " .. AC() .. "/lm now|r.")
        else
            queuedTalent = StoreTalentLoadout(loadout)
            queuedTalentReason = reason or "retry"
            Print("Could not apply talent loadout " .. ERRC() .. "" .. loadout.name ..
                "|r yet (unspent points or the game refused the change). Queued a retry.")
        end
        return
    end

    if C_ClassTalents.UpdateLastSelectedSavedConfigID then
        pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, loadout.specID or GetCurrentSpecID(), loadout.configID)
    end
    SyncTalentUI(loadout.configID)
    lastLoadedConfigID = loadout.configID

    if result == NO_CHANGE then
        Debug("talents already match ", loadout.name)
        return
    end
    Announce("Loading talents " .. AC() .. "" .. loadout.name .. "|r" .. (reason and (" (" .. reason .. ")") or "") .. ".")
end

-- -----------------------------------------------------------------------------
-- Assignment helpers
-- -----------------------------------------------------------------------------

local function CheckAndSwap(reason)
    EnsureDB()
    if not InstanceGearSwapDB.enabled then return end

    if InActiveKeystone() then
        Print("Keystone active: gear and talents are locked. Swaps skipped until the run ends.")
        return
    end

    Perf.checks = Perf.checks + 1
    local ctx = GetCurrentInstanceContext()
    Debug("CheckAndSwap reason=", tostring(reason), " inInstance=", tostring(ctx.inInstance), " type=", tostring(ctx.instanceType), " instanceID=", tostring(ctx.instanceID), " difficultyID=", tostring(ctx.difficultyID))

    if not ctx.inInstance then
        -- Silent no-op unless an Open World default is configured, so players
        -- who do not use it never see gear changes out of instances.
        local worldGear = GetAssignedSetForContext(ctx)
        local worldTalent = GetAssignedTalentForContext(ctx)
        if not worldGear and not worldTalent then
            Debug("no open-world default configured; nothing to revert to")
            return
        end
    end

    local setName, gearSource = GetAssignedSetForContext(ctx)
    if setName and InstanceGearSwapDB.gearEnabled then
        local label = ctx.name
        if gearSource == "difficulty" then label = ctx.name .. " - " .. tostring(ctx.difficultyName or ctx.difficultyID) end
        if gearSource == "type" then
            label = ctx.inInstance and (tostring(ctx.instanceType) .. " default") or "open world default"
        end
        TryEquipSet(setName, label)
    end

    local talentStored, talentSource = GetAssignedTalentForContext(ctx)
    if talentStored and InstanceGearSwapDB.talentEnabled then
        local label = ctx.name
        if talentSource == "difficulty" then label = ctx.name .. " - " .. tostring(ctx.difficultyName or ctx.difficultyID) end
        if talentSource == "type" then
            label = ctx.inInstance and (tostring(ctx.instanceType) .. " default") or "open world default"
        end
        TryLoadTalentLoadout(talentStored, label)
    end
end

local function DelayedCheck(reason)
    EnsureDB()
    local delay = tonumber(InstanceGearSwapDB.delay) or 2
    C_Timer.After(delay, function()
        CheckAndSwap(reason)
    end)
end

local function BuildAutoInstanceKey(ctx)
    if not ctx then return nil end
    if not ctx.inInstance then
        -- One key for "in the open world" so leaving any instance triggers the
        -- world default once, not on every zone change out there.
        return "world:" .. tostring(GetCurrentSpecID() or 0)
    end
    if not ctx.instanceID then return nil end
    return tostring(ctx.instanceType or "none") .. ":" .. tostring(ctx.instanceID) .. ":" .. tostring(ctx.difficultyID or 0) .. ":" .. tostring(GetCurrentSpecID() or 0)
end

local function HandlePossibleInstanceEntry(reason)
    EnsureDB()

    local ctx = GetCurrentInstanceContext()
    local key = BuildAutoInstanceKey(ctx)

    if not key then
        lastAutoInstanceKey = nil
        return
    end

    if key == lastAutoInstanceKey then
        Debug("same context; auto-swap skipped: ", tostring(key))
        return
    end

    local leaving = (not ctx.inInstance)
    lastAutoInstanceKey = key
    Debug("new context detected; auto-swap scheduled: ", tostring(key), " reason=", tostring(reason))
    DelayedCheck(leaving and "left instance" or "entered instance")
end

RetryPendingGear = function()
    if not pendingGear then return end
    local p = pendingGear
    TryEquipSet(p.name, p.reason)
end

RetryPendingTalent = function()
    if not pendingTalent then return end
    local p = pendingTalent
    TryLoadTalentLoadout(p.stored, p.reason)
end

-- The API call succeeding does not mean every piece went on: items in the bank,
-- soulbound restrictions, or a swap interrupted mid-cast leave you partly
-- geared. EQUIPMENT_SWAP_FINISHED is where the truth shows up.
local function VerifyEquippedSet()
    if not expectedSet then return end
    local wanted = expectedSet.name
    expectedSet = nil

    local info = GetSetInfoByName(wanted)
    if not info then return end

    if not info.isEquipped then
        local missing = tonumber(info.numItems or 0) - tonumber(info.numEquipped or 0)
        if missing > 0 then
            Print("Gear set " .. ERRC() .. "" .. wanted .. "|r did not fully equip - " .. missing ..
                " item(s) missing" .. ((info.numLost and info.numLost > 0) and " (check bank/void storage)" or "") .. ".")
        else
            Print("Gear set " .. ERRC() .. "" .. wanted .. "|r did not finish equipping. Try " .. AC() .. "/lm now|r.")
        end
        return
    end
    Debug("verified ", wanted, " is fully equipped")
end

local function RunQueuedAfterCombat()
    local hadQueued = false

    if queuedSetName then
        local setName = queuedSetName
        local reason = queuedSetReason or "after combat"
        queuedSetName = nil
        queuedSetReason = nil
        hadQueued = true
        C_Timer.After(0.25, function()
            TryEquipSet(setName, reason)
            RefreshUI()
        end)
    end

    if queuedTalent then
        local talent = queuedTalent
        local reason = queuedTalentReason or "after combat"
        queuedTalent = nil
        queuedTalentReason = nil
        hadQueued = true
        C_Timer.After(0.5, function()
            TryLoadTalentLoadout(talent, reason)
            RefreshUI()
        end)
    end

    return hadQueued
end

local function AssignCurrentLoadouts(includeDifficulty)
    EnsureDB()
    local ctx = GetCurrentInstanceContext()
    if not ctx.inInstance or not ctx.instanceID then
        Print("You are not inside a raid/dungeon/instance with a valid instance ID. Use Manual Map by ID instead.")
        return false
    end

    local changed = false
    local instanceKey = tostring(ctx.instanceID)
    local diffKey = BuildDifficultyKey(ctx.instanceID, ctx.difficultyID)
    local W, scopeID = GetWriteTables()

    if UI.selectedSet and SetExists(UI.selectedSet) then
        if includeDifficulty then
            W.difficultySets[diffKey] = UI.selectedSet
        else
            W.instanceSets[instanceKey] = UI.selectedSet
        end
        changed = true
    end

    if UI.selectedTalent and TalentExists(UI.selectedTalent) then
        local stored = StoreTalentLoadout(UI.selectedTalent)
        if scopeID and stored and stored.specID and tonumber(stored.specID) ~= tonumber(scopeID) then
            Print("Skipped talents: " .. AC() .. "" .. tostring(stored.name) .. "|r belongs to " .. tostring(SpecName(stored.specID)) .. ". Switch specs to assign " .. tostring(SpecName(scopeID)) .. " talents.")
        else
            if includeDifficulty then
                W.talentDifficultySets[diffKey] = stored
            else
                W.talentInstanceSets[instanceKey] = stored
            end
            changed = true
        end
    end

    if changed then
        Print("Assigned selected gear/talents to " .. AC() .. "" .. ctx.name .. (includeDifficulty and (" - " .. tostring(ctx.difficultyName or ctx.difficultyID)) or "") .. "|r" .. ScopeSuffix(scopeID) .. ".")
    else
        Print("Nothing selected to assign.")
    end
    return changed
end

local function ClearCurrentLoadouts(includeDifficulty)
    EnsureDB()
    local ctx = GetCurrentInstanceContext()
    if not ctx.instanceID then
        Print("No current instance ID found.")
        return false
    end

    local W, scopeID = GetWriteTables()
    local key = includeDifficulty and BuildDifficultyKey(ctx.instanceID, ctx.difficultyID) or tostring(ctx.instanceID)
    local gTbl = includeDifficulty and W.difficultySets or W.instanceSets
    local tTbl = includeDifficulty and W.talentDifficultySets or W.talentInstanceSets
    local oldG, oldT = gTbl[key], TalentDisplayName(tTbl[key])
    gTbl[key], tTbl[key] = nil, nil
    Print("Cleared " .. (includeDifficulty and "instance+difficulty" or "instance") ..
        " assignments" .. ScopeSuffix(scopeID) ..
        " (was G: " .. tostring(oldG or "none") .. ", T: " .. tostring(oldT or "none") .. ").")
    return true
end

local function AssignTypeLoadouts(instanceType)
    EnsureDB()
    instanceType = Trim(instanceType):lower()
    if not INSTANCE_TYPES[instanceType] then
        Print("Invalid type. Use: world, party, mplus, timewalking, delve, raid, scenario, arena, or pvp.")
        return false
    end

    local changed = false
    local W, scopeID = GetWriteTables()
    if UI.selectedSet and SetExists(UI.selectedSet) then
        W.typeDefaults[instanceType] = UI.selectedSet
        changed = true
    end
    if UI.selectedTalent and TalentExists(UI.selectedTalent) then
        local stored = StoreTalentLoadout(UI.selectedTalent)
        if scopeID and stored and stored.specID and tonumber(stored.specID) ~= tonumber(scopeID) then
            Print("Skipped talents: " .. AC() .. "" .. tostring(stored.name) .. "|r belongs to " .. tostring(SpecName(stored.specID)) .. ". Switch specs to assign " .. tostring(SpecName(scopeID)) .. " talents.")
        else
            W.talentTypeDefaults[instanceType] = stored
            changed = true
        end
    end

    if changed then
        Print("Assigned selected gear/talents as the " .. AC() .. "" .. instanceType .. "|r default" .. ScopeSuffix(scopeID) .. ".")
    else
        Print("Nothing selected to assign.")
    end
    return changed
end

local function ClearTypeLoadouts(instanceType)
    EnsureDB()
    instanceType = Trim(instanceType):lower()
    if not INSTANCE_TYPES[instanceType] then
        Print("Invalid type. Use: world, party, mplus, timewalking, delve, raid, scenario, arena, or pvp.")
        return false
    end
    local W, scopeID = GetWriteTables()
    local oldG = W.typeDefaults[instanceType]
    local oldT = TalentDisplayName(W.talentTypeDefaults[instanceType])
    W.typeDefaults[instanceType] = nil
    W.talentTypeDefaults[instanceType] = nil
    if oldG or oldT then
        Print("Cleared the " .. instanceType .. " default" .. ScopeSuffix(scopeID) ..
            " (was G: " .. tostring(oldG or "none") .. ", T: " .. tostring(oldT or "none") .. ").")
    else
        Print("The " .. instanceType .. " default" .. ScopeSuffix(scopeID) .. " was already empty.")
    end
    return true
end

local function AssignManualLoadouts(includeDifficulty)
    EnsureDB()
    if not UI.manualInstanceBox then return false end
    local instanceID = tonumber(Trim(UI.manualInstanceBox:GetText()))
    local difficultyID = tonumber(Trim(UI.manualDiffBox and UI.manualDiffBox:GetText() or ""))

    if not instanceID then
        Print("Missing or invalid instance ID.")
        return false
    end
    if includeDifficulty and not difficultyID then
        Print("Missing or invalid difficulty ID.")
        return false
    end

    local changed = false
    local instanceKey = tostring(instanceID)
    local diffKey = includeDifficulty and BuildDifficultyKey(instanceID, difficultyID) or nil
    local W, scopeID = GetWriteTables()

    if UI.selectedSet and SetExists(UI.selectedSet) then
        if includeDifficulty then
            W.difficultySets[diffKey] = UI.selectedSet
        else
            W.instanceSets[instanceKey] = UI.selectedSet
        end
        changed = true
    end

    if UI.selectedTalent and TalentExists(UI.selectedTalent) then
        local stored = StoreTalentLoadout(UI.selectedTalent)
        if scopeID and stored and stored.specID and tonumber(stored.specID) ~= tonumber(scopeID) then
            Print("Skipped talents: " .. AC() .. "" .. tostring(stored.name) .. "|r belongs to " .. tostring(SpecName(stored.specID)) .. ". Switch specs to assign " .. tostring(SpecName(scopeID)) .. " talents.")
        else
            if includeDifficulty then
                W.talentDifficultySets[diffKey] = stored
            else
                W.talentInstanceSets[instanceKey] = stored
            end
            changed = true
        end
    end

    if changed then
        Print("Mapped selected gear/talents to instance ID " .. tostring(instanceID) .. (includeDifficulty and (" difficulty " .. tostring(difficultyID)) or "") .. ScopeSuffix(scopeID) .. ".")
    else
        Print("Nothing selected to map.")
    end
    return changed
end

-- Compatibility wrappers for old slash commands.
local function AssignCurrentInstance(setName, includeDifficulty)
    EnsureDB()
    setName = Trim(setName)
    if setName == "" then Print("Missing gear set name.") return false end
    local setID, canonicalName = GetEquipmentSetIDByName(setName)
    if not setID then Print("Could not find Equipment Manager set named " .. ERRC() .. "" .. setName .. "|r.") return false end
    local ctx = GetCurrentInstanceContext()
    if not ctx.inInstance or not ctx.instanceID then Print("You are not inside a valid instance.") return false end
    if includeDifficulty then
        InstanceGearSwapDB.difficultySets[BuildDifficultyKey(ctx.instanceID, ctx.difficultyID)] = canonicalName
    else
        InstanceGearSwapDB.instanceSets[tostring(ctx.instanceID)] = canonicalName
    end
    Print("Assigned gear " .. AC() .. "" .. canonicalName .. "|r.")
    return true
end

local function AssignTypeSet(instanceType, setName)
    EnsureDB()
    instanceType = Trim(instanceType):lower()
    setName = Trim(setName)
    if not INSTANCE_TYPES[instanceType] then Print("Invalid type.") return false end
    local setID, canonicalName = GetEquipmentSetIDByName(setName)
    if not setID then Print("Could not find Equipment Manager set named " .. ERRC() .. "" .. setName .. "|r.") return false end
    InstanceGearSwapDB.typeDefaults[instanceType] = canonicalName
    Print("Assigned gear " .. AC() .. "" .. canonicalName .. "|r as default for " .. AC() .. "" .. instanceType .. "|r.")
    return true
end

local function ClearTypeByName(instanceType)
    EnsureDB()
    instanceType = Trim(instanceType):lower()
    if not INSTANCE_TYPES[instanceType] then Print("Invalid type.") return false end
    InstanceGearSwapDB.typeDefaults[instanceType] = nil
    Print("Cleared gear default for " .. instanceType .. ".")
    return true
end

-- -----------------------------------------------------------------------------
-- Text output
-- -----------------------------------------------------------------------------

local function PrintCurrentContext()
    local ctx = GetCurrentInstanceContext()
    Print("Current location:")
    print("  Name: " .. tostring(ctx.name))
    print("  In instance: " .. tostring(ctx.inInstance))
    print("  Type: " .. tostring(ctx.instanceType))
    print("  Instance ID: " .. tostring(ctx.instanceID))
    print("  Difficulty: " .. tostring(ctx.difficultyName or "Unknown") .. " (" .. tostring(ctx.difficultyID) .. ")")

    local setName, source, key = GetAssignedSetForContext(ctx)
    print("  Gear: " .. tostring(setName or "none") .. (source and (" [" .. tostring(source) .. "]") or ""))

    local talent, talentSource = GetAssignedTalentForContext(ctx)
    print("  Talents: " .. tostring(TalentDisplayName(talent) or "none") .. (talentSource and (" [" .. tostring(talentSource) .. "]") or ""))
end

local function PrintSets()
    local sets = ListEquipmentSets()
    Print("Available Equipment Manager sets:")
    if #sets == 0 then print("  none") return end
    for _, name in ipairs(sets) do print("  " .. name) end
end

local function PrintTalents()
    local loadouts = ListTalentLoadouts()
    Print("Available talent loadouts for current spec:")
    if #loadouts == 0 then print("  none") return end
    for _, loadout in ipairs(loadouts) do
        print("  " .. loadout.name .. "  (ID " .. tostring(loadout.configID) .. ")")
    end
end

local function PrintHelp()
    Print("Commands:")
    print("  " .. AC() .. "/lm|r - open the clickable loadout window")
    print("  " .. AC() .. "/lm current|r - show current instance ID/type/difficulty")
    print("  " .. AC() .. "/lm sets|r - list Blizzard gear sets")
    print("  " .. AC() .. "/lm talents|r - list talent loadouts for your current spec")
    print("  " .. AC() .. "/lm now|r - force a gear/talent check now")
    print("  " .. AC() .. "/lm warning|r - test the spec-change warning")
    print("  " .. AC() .. "/lm on|r or " .. AC() .. "/lm off|r - enable/disable")
    print("  " .. AC() .. "/lm gear on/off|r - enable/disable gear swaps")
    print("  " .. AC() .. "/lm talent on/off|r - enable/disable talent swaps")
    print("  " .. AC() .. "/lm specswap on/off|r - re-run swaps when your spec changes inside an instance")
    print("  " .. AC() .. "/lm scale 0.5-2.0|r - resize the window")
    print("  " .. AC() .. "/lm perf|r - event/swap counts, to spot anything firing too often")
    print("  " .. AC() .. "/lm gc|r - force garbage collection and report reclaimed memory")
    print("  " .. AC() .. "/lm verify|r - list assignments pointing at missing gear sets")
    print("  " .. AC() .. "/lm warning on/off|r - themed spec-change panel (on by default)")
    print("  " .. AC() .. "/lm raidwarning on/off|r - Blizzard orange raid-warning text (off by default)")
    print("  Per-spec defaults: open " .. AC() .. "/lm|r and use the Assign for tabs (All Specs / your specs).")
    print("  Slash assignment commands (set, type, ...) always write to the All Specs layer.")
end

-- Scratch tables reused across refreshes; this function only returns a string,
-- so nothing outside it can hold a reference to them.
local assignmentLines, assignmentKeyMap, assignmentKeys = {}, {}, {}

local function BuildAssignmentsText(scopeTables)
    EnsureDB()
    local R = scopeTables or InstanceGearSwapDB
    local lines = wipe(assignmentLines)

    local function AddMappingLines(title, gearTable, talentTable)
        local keysMap = wipe(assignmentKeyMap)
        for key in pairs(gearTable or {}) do keysMap[tostring(key)] = true end
        for key in pairs(talentTable or {}) do keysMap[tostring(key)] = true end

        local keys = wipe(assignmentKeys)
        for key in pairs(keysMap) do table.insert(keys, key) end
        table.sort(keys, function(a, b)
            local an, bn = tonumber(a), tonumber(b)
            if an and bn then return an < bn end
            return tostring(a) < tostring(b)
        end)

        table.insert(lines, title)
        if #keys == 0 then
            table.insert(lines, "  - none")
            return
        end

        for _, key in ipairs(keys) do
            local gear = gearTable and gearTable[key]
            local talent = talentTable and talentTable[key]
            local displayKey = tostring(key)
            local i, d = displayKey:match("^(%d+):(%d+)$")
            if i and d then displayKey = "ID " .. i .. " / Diff " .. d else displayKey = "ID " .. displayKey end
            table.insert(lines, "  - " .. displayKey)
            table.insert(lines, "    G: " .. tostring(gear or "none") .. "    T: " .. tostring(TalentDisplayName(talent) or "none"))
        end
    end

    AddMappingLines("Specific instances", R.instanceSets, R.talentInstanceSets)
    table.insert(lines, "")
    AddMappingLines("Specific instance + difficulty", R.difficultySets, R.talentDifficultySets)
    return table.concat(lines, "\n")
end

-- -----------------------------------------------------------------------------
-- EllesmereUI house style engine
-- Every widget is painted flat/dark to EUI's visual spec at creation, no
-- dependencies. When EUI's skinning facade is active it takes over instead, so
-- the window tracks the live theme; fonts and accent colors always resolve
-- through EUI when it is installed, facade or not.
-- -----------------------------------------------------------------------------

-- Font resolution: facade font > EllesmereUI's exported Expressway > stock.
local function GetHouseFont()
    local S = Skin.S
    if S and S.GetFont then
        local ok, path = pcall(S.GetFont)
        if ok and path then return path end
    end
    if EllesmereUI and EllesmereUI.EXPRESSWAY then return EllesmereUI.EXPRESSWAY end
    return STANDARD_TEXT_FONT
end

-- Re-font any FontString/EditBox to the house font at its current size.
local function ReFont(obj, r, g, b, a)
    local _, size = obj:GetFont()
    obj:SetFont(GetHouseFont(), size or 12, "")
    if r and obj.SetTextColor then obj:SetTextColor(r, g, b, a or 1) end
end

-- Accent resolution: facade > EllesmereUI's live accent table > our palette.
local function GetAccentRGB()
    local S = Skin.S
    if S and S.GetAccentColor then
        local ok, r, g, b = pcall(S.GetAccentColor)
        if ok and r and g and b then return r, g, b end
    end
    -- EUI's parent framework exports a live accent getter (theme-resolved at
    -- login, updated on theme changes) that works even when its Blizz UI
    -- Enhanced skinning child is missing or disabled.
    if EllesmereUI and EllesmereUI.GetAccentColor then
        local ok, r, g, b = pcall(EllesmereUI.GetAccentColor)
        if ok and r and g and b then return r, g, b end
    end
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg and eg.r then return eg.r, eg.g, eg.b end
    local hex = PALETTE.accent
    return tonumber(hex:sub(1, 2), 16) / 255,
           tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
end

local function GetPanelRGBA()
    local S = Skin.S
    if S and S.GetPanelColor then
        local ok, r, g, b, a = pcall(S.GetPanelColor)
        if ok and r then return r, g, b, a or 0.97 end
    end
    return 0.05, 0.07, 0.09, 0.97 -- EUI PANEL_BG
end

-- -----------------------------------------------------------------------------
-- Themed window art: loads EllesmereUI's own background files and follows the
-- user's active EUI theme (incl. Custom/Class accent tinting), so the window
-- carries the same artwork as EUI's panels. Falls back to the flat shell when
-- EllesmereUI is not installed or a file goes missing.
-- -----------------------------------------------------------------------------
local EUI_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
local THEME_BG_FILES = {
    ["EllesmereUI"]   = "backgrounds\\eui-bg-all-compressed.png",
    ["Horde"]         = "backgrounds\\eui-bg-horde-compressed.png",
    ["Alliance"]      = "backgrounds\\eui-bg-alliance-compressed.png",
    ["Midnight"]      = "backgrounds\\eui-bg-midnight-compressed.png",
    ["Dark"]          = "backgrounds\\eui-bg-dark-compressed.png",
    ["Class Colored"] = "backgrounds\\eui-bg-all-compressed.png",
    ["Custom Color"]  = "backgrounds\\eui-bg-all-compressed.png",
}

-- EUI's art files bake in their window chrome (logo, close box, header streak
-- with an angled end, sidebar divider, footer seam) and sit inset on a canvas
-- with transparent shadow margins. These regions were measured pixel-exact on
-- the 8.8.6 art (1500x1154 canvas, panel at 99..1399 x 104..1049) and sample
-- only clean areas. Coordinates are normalized to the full canvas.
local ART_AMBIENT = { 0.280, 0.920, 0.260, 0.815 } -- clean speckled field in EUI's art

-- EUI's art baseline is ~14% gray, so additive layers sampled from it render as
-- ghost rectangles. The glow line and corner blooms therefore ship as our own
-- assets in media/: extracted from EUI's art, baseline-subtracted and edge-
-- feathered to true black (seam-free under ADD), then vertex-tinted with the
-- live accent so every theme colors them correctly.
local IGS_MEDIA = "Interface\\AddOns\\InstanceGearSwap\\media\\"
local GLOW_Y, GLOW_H = -42, 40                       -- line position under the strip
local BLOOM_W, BLOOM_H, BLOOM_ALPHA = 0.50, 0.34, 0.70 -- top-right radiance
local AURA_W, AURA_H, AURA_ALPHA = 0.55, 0.42, 0.55    -- bottom-left echo (flipped)

local function GetResolvedTheme()
    local theme = "EllesmereUI"
    if EllesmereUI and EllesmereUI.GetActiveTheme then
        local ok, t = pcall(EllesmereUI.GetActiveTheme)
        if ok and t then theme = t end
    end
    if theme == "Faction (Auto)" then
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        theme = (faction == "Horde") and "Horde" or "Alliance"
    end
    return theme
end

-- Mirrors EUI's own bg tinting: named themes use their art as-is; accent-driven
-- themes desaturate the base art and re-tint it with the accent color.
local function ApplyThemeArtTint(tex, theme)
    local named = THEME_BG_FILES[theme] and theme ~= "Class Colored" and theme ~= "Custom Color"
    if named then
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, 1)
    else
        local r, g, b = GetAccentRGB()
        local minBright, maxBright, floorV = 1.10, 1.60, 0.08
        local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        local bright = minBright + (1 - lum) * (maxBright - minBright)
        tex:SetDesaturated(true)
        tex:SetVertexColor(
            math.min(floorV + r * bright, 1),
            math.min(floorV + g * bright, 1),
            math.min(floorV + b * bright, 1), 1)
    end
end

local function RefreshThemeArt()
    local f = UI.frame
    if not f then return end
    local theme = GetResolvedTheme()
    if f._igsArt then
        f._igsArt:SetTexture(EUI_MEDIA .. (THEME_BG_FILES[theme] or THEME_BG_FILES["EllesmereUI"]))
        ApplyThemeArtTint(f._igsArt, theme)
    end
    if f._igsGlowLayers then
        local r, g, b = GetAccentRGB()
        for i = 1, #f._igsGlowLayers do
            f._igsGlowLayers[i]:SetVertexColor(r, g, b, 1)
        end
    end
end

-- Keep chat/status text colors in sync with the resolved accent.
local function RefreshPalette()
    local r, g, b = GetAccentRGB()
    PALETTE.accent = string.format("%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Accent-painted regions (checkbox checks, warning underline/subtitle): recolored live.
local function RegisterAccented(obj, kind, alpha)
    Skin.accented[#Skin.accented + 1] = { obj = obj, kind = kind, alpha = alpha or 1 }
end

local function RecolorAccents()
    local r, g, b = GetAccentRGB()
    -- Toggles paint their own track from the live accent
    for i = 1, #Skin.reg do
        local entry = Skin.reg[i]
        if entry.kind == "toggle" and entry.obj.UpdateVisual then
            entry.obj:UpdateVisual()
        end
    end
    for i = 1, #Skin.accented do
        local e = Skin.accented[i]
        if e.kind == "tex" then
            e.obj:SetColorTexture(r, g, b, e.alpha)
        else
            e.obj:SetTextColor(r, g, b, e.alpha)
        end
    end
end

-- ---- Native painters (EUI visual spec, straight from EllesmereUI's constants)

local Native = {}

-- Zero out template art (textures only; FontStrings survive).
function Native.StripArt(frame)
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local rg = regions[i]
        if rg.GetObjectType and rg:GetObjectType() == "Texture" then rg:SetAlpha(0) end
    end
end

-- 1px border made of four textures; returns them for hover/recolor.
function Native.Border(frame, a, anchorRegion)
    local edges = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, a)
        edges[i] = t
    end
    local to = anchorRegion or frame
    edges[1]:SetPoint("TOPLEFT", to); edges[1]:SetPoint("TOPRIGHT", to); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", to); edges[2]:SetPoint("BOTTOMRIGHT", to); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", to); edges[3]:SetPoint("BOTTOMLEFT", to); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", to); edges[4]:SetPoint("BOTTOMRIGHT", to); edges[4]:SetWidth(1)
    return edges
end

local function SetEdgeAlpha(edges, a)
    for i = 1, 4 do edges[i]:SetColorTexture(1, 1, 1, a) end
end

function Native.Shell(f)
    local frameW = (f.GetWidth and f:GetWidth()) or 820
    local frameH = (f.GetHeight and f:GetHeight()) or 694
    if not frameW or frameW == 0 then frameW = 820 end
    if not frameH or frameH == 0 then frameH = 694 end
    local pr, pg, pb, pa = GetPanelRGBA()
    local layers = {}
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(pr, pg, pb, pa)
    layers[#layers + 1] = bg
    if EllesmereUI then
        -- Clean speckled field across the whole window (live EUI themed file)
        local ambient = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        ambient:SetAllPoints()
        ambient:SetTexCoord(ART_AMBIENT[1], ART_AMBIENT[2], ART_AMBIENT[3], ART_AMBIENT[4])
        layers[#layers + 1] = ambient
        f._igsArt = ambient

        f._igsGlowLayers = {}
        local function GlowLayer(sub, file)
            local t = f:CreateTexture(nil, "BACKGROUND", nil, sub)
            t:SetTexture(IGS_MEDIA .. file)
            t:SetBlendMode("ADD")
            layers[#layers + 1] = t
            f._igsGlowLayers[#f._igsGlowLayers + 1] = t
            return t
        end
        -- Bottom-left aura: corner bloom flipped 180 degrees
        local aura = GlowLayer(-6, "glow-corner.png")
        aura:SetTexCoord(1, 0, 1, 0)
        aura:SetPoint("BOTTOMLEFT")
        aura:SetSize(frameW * AURA_W, frameH * AURA_H)
        aura:SetAlpha(AURA_ALPHA)
        f._igsAura = aura
        -- Top-right radiance
        local bloom = GlowLayer(-5, "glow-corner.png")
        bloom:SetPoint("TOPRIGHT")
        bloom:SetSize(frameW * BLOOM_W, frameH * BLOOM_H)
        bloom:SetAlpha(BLOOM_ALPHA)
    end
    local strip = f:CreateTexture(nil, "BACKGROUND", nil, -4) -- dark title strip
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(46)
    strip:SetColorTexture(0, 0, 0, 0.25)
    layers[#layers + 1] = strip
    if EllesmereUI and f._igsGlowLayers then
        -- EUI's signature glow line riding the strip's bottom edge
        local glow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
        glow:SetTexture(IGS_MEDIA .. "glow-line.png")
        glow:SetPoint("TOPLEFT", 0, GLOW_Y)
        glow:SetPoint("TOPRIGHT", 0, GLOW_Y)
        glow:SetHeight(GLOW_H)
        glow:SetBlendMode("ADD")
        layers[#layers + 1] = glow
        f._igsGlowLayers[#f._igsGlowLayers + 1] = glow
    end
    local div = f:CreateTexture(nil, "BACKGROUND", nil, -3)
    div:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
    div:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
    div:SetHeight(1)
    div:SetColorTexture(1, 1, 1, 0.05)
    layers[#layers + 1] = div
    local edges = Native.Border(f, 0.06)
    for i = 1, 4 do layers[#layers + 1] = edges[i] end
    f._igsNative = layers
    RefreshThemeArt()
end

function Native.Panel(box)
    local layers = {}
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.30)
    layers[#layers + 1] = bg
    local edges = Native.Border(box, 0.05)
    for i = 1, 4 do layers[#layers + 1] = edges[i] end
    box._igsNative = layers
end

-- UIPanelButtonTemplate swaps the label's font object on hover/disable, which
-- would wipe a direct SetFont. Route the label through our own font objects so
-- Blizzard's swap mechanism applies the EUI text style (0.55 -> 0.70 white).
local btnFontNormal, btnFontHover
local function GetButtonFonts()
    if not btnFontNormal then
        btnFontNormal = CreateFont("IGSButtonFontNormal")
        btnFontHover  = CreateFont("IGSButtonFontHighlight")
        btnFontNormal:SetFont(GetHouseFont(), 12, "")
        btnFontHover:SetFont(GetHouseFont(), 12, "")
        btnFontNormal:SetTextColor(1, 1, 1, 0.55)
        btnFontHover:SetTextColor(1, 1, 1, 0.70)
    end
    return btnFontNormal, btnFontHover
end

function Native.Button(b)
    Native.StripArt(b)
    local layers = {}
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.061, 0.095, 0.120, 0.6)
    layers[#layers + 1] = bg
    local edges = Native.Border(b, 0.3)
    for i = 1, 4 do layers[#layers + 1] = edges[i] end
    local n, h = GetButtonFonts()
    b:SetNormalFontObject(n)
    b:SetHighlightFontObject(h)
    b:SetDisabledFontObject(n)
    b:HookScript("OnEnter", function()
        bg:SetColorTexture(0.061, 0.095, 0.120, 0.65)
        SetEdgeAlpha(edges, 0.45)
    end)
    b:HookScript("OnLeave", function()
        bg:SetColorTexture(0.061, 0.095, 0.120, 0.6)
        SetEdgeAlpha(edges, 0.3)
    end)
    b._igsNative = layers
end

function Native.Checkbox(cb)
    Native.StripArt(cb)
    local layers = {}
    local box = cb:CreateTexture(nil, "BACKGROUND")
    box:SetPoint("TOPLEFT", 3, -3)
    box:SetPoint("BOTTOMRIGHT", -3, 3)
    box:SetColorTexture(0.10, 0.12, 0.16, 1)
    layers[#layers + 1] = box
    local edges = Native.Border(cb, 0.10, box)
    for i = 1, 4 do layers[#layers + 1] = edges[i] end
    local check = cb:CreateTexture(nil, "ARTWORK")
    local ar, ag, ab = GetAccentRGB()
    check:SetColorTexture(ar, ag, ab, 0.9)
    cb:SetCheckedTexture(check)
    check:ClearAllPoints()
    check:SetPoint("TOPLEFT", 8, -8)
    check:SetPoint("BOTTOMRIGHT", -8, 8)
    RegisterAccented(check, "tex", 0.9)
    layers[#layers + 1] = check
    local hl = cb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.06)
    layers[#layers + 1] = hl
    if cb.label then ReFont(cb.label, 1, 1, 1, 0.85) end
    cb._igsNative = layers
end

function Native.EditBox(eb)
    Native.StripArt(eb)
    local layers = {}
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.03, 0.04, 0.6)
    layers[#layers + 1] = bg
    local edges = Native.Border(eb, 0.10)
    for i = 1, 4 do layers[#layers + 1] = edges[i] end
    ReFont(eb)
    eb:SetTextColor(1, 1, 1, 0.9)
    eb._igsNative = layers
end

function Native.Scroll(scroll)
    local bar = scroll.ScrollBar or (scroll.GetName and scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"])
    if not bar then return end
    local function MuteButton(btn)
        if not btn then return end
        local t = btn.GetNormalTexture and btn:GetNormalTexture()
        local p = btn.GetPushedTexture and btn:GetPushedTexture()
        local d = btn.GetDisabledTexture and btn:GetDisabledTexture()
        local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
        for _, tex in ipairs({ t, p, d }) do
            if tex then tex:SetDesaturated(true); tex:SetVertexColor(1, 1, 1, 0.45) end
        end
        if h then h:SetAlpha(0) end
    end
    local barName = bar.GetName and bar:GetName()
    MuteButton(bar.ScrollUpButton or (barName and _G[barName .. "ScrollUpButton"]))
    MuteButton(bar.ScrollDownButton or (barName and _G[barName .. "ScrollDownButton"]))
    if bar.GetThumbTexture then
        local thumb = bar:GetThumbTexture()
        if thumb then thumb:SetColorTexture(1, 1, 1, 0.22) end
    end
end

-- Hide our native layers when the facade repaints a frame (avoids double art).
local function HideNativeLayers(obj)
    if not obj._igsNative then return end
    for i = 1, #obj._igsNative do obj._igsNative[i]:SetAlpha(0) end
end

-- ---- Paint dispatch: facade primitives when active, native painters otherwise

function Skin.PaintOne(kind, obj)
    local S = Skin.S
    local mode = S and "facade" or "native"
    if Skin.done[obj] == mode or (Skin.done[obj] == "facade") then return end
    local wasNative = Skin.done[obj] == "native"
    Skin.done[obj] = mode

    -- Shared styling first (identical in both modes)
    if kind == "shell" then
        Native.Shell(obj)
        return
    elseif kind == "panel" then
        Native.Panel(obj)
        return
    elseif kind == "title" then
        ReFont(obj, 1, 1, 1, 0.95)
        return
    elseif kind == "header" then
        ReFont(obj, 1, 1, 1)
        obj:SetAlpha(0.60)
        return
    elseif kind == "label" then
        ReFont(obj, 1, 1, 1)
        obj:SetAlpha(0.75)
        return
    elseif kind == "text" then
        ReFont(obj)
        return
    elseif kind == "toggle" then
        -- Our own widget in both modes: just font the label and repaint with
        -- the current accent (RecolorAccents drives it on theme changes).
        if obj.label then ReFont(obj.label) end
        if obj.UpdateVisual then obj:UpdateVisual() end
        return
    elseif kind == "row" then
        if obj._igsStriped then return end
        obj._igsStriped = true
        local i = obj._stripeIndex or 1
        local stripe = obj:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.20 or 0.10)
        local hl = obj:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        if obj.label then ReFont(obj.label) end
        if obj.gear then ReFont(obj.gear) end
        if obj.talent then ReFont(obj.talent) end
        return
    end

    if wasNative then HideNativeLayers(obj) end

    if mode == "facade" then
        if kind == "button" then
            TrySkin(S.Button, obj)
            local fs = obj.GetFontString and obj:GetFontString()
            if fs then ReFont(fs, 1, 1, 1) end
            TrySkin(S.WhiteButtonLabel, obj)
        elseif kind == "close" then
            local fs = obj.GetFontString and obj:GetFontString()
            if TrySkin(S.CloseButton, obj) then
                if fs then fs:SetText("") end -- the house glyph replaces our text X
            else
                Native.Button(obj) -- same look either way
            end
        elseif kind == "checkbox" then
            TrySkin(S.Checkbox, obj)
            if obj.label then ReFont(obj.label, 1, 1, 1, 0.85) end
        elseif kind == "editbox" then
            TrySkin(S.EditBox, obj)
            ReFont(obj)
        elseif kind == "scroll" then
            local bar = obj.ScrollBar or (obj.GetName and obj:GetName() and _G[obj:GetName() .. "ScrollBar"])
            if bar then TrySkin(S.ScrollBar, bar) end
        end
    else
        if kind == "button" or kind == "close" then
            Native.Button(obj)
        elseif kind == "checkbox" then
            Native.Checkbox(obj)
        elseif kind == "editbox" then
            Native.EditBox(obj)
        elseif kind == "scroll" then
            Native.Scroll(obj)
        end
    end
end

function Skin.Apply()
    for i = 1, #Skin.reg do
        Skin.PaintOne(Skin.reg[i].kind, Skin.reg[i].obj)
    end
end

-- Warning banner: always styled in the house look (native panel spec + accent),
-- with colors/fonts resolving through EUI's getters when it is present.
SkinWarningFrame = function()
    local f = specChangeWarningFrame
    if not f or f._igsStyled then return end
    f._igsStyled = true
    local pr, pg, pb = GetPanelRGBA()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(pr, pg, pb, 0.92)
    Native.Border(f, 0.08)
    ReFont(f.title)
    ReFont(f.subtitle)
    f.title:SetTextColor(1, 0.35, 0.30, 1) -- softened warning red on the flat panel
    local line = f:CreateTexture(nil, "OVERLAY") -- accent underline, EUI tab-style
    line:SetPoint("BOTTOMLEFT", 1, 1)
    line:SetPoint("BOTTOMRIGHT", -1, 1)
    line:SetHeight(2)
    local ar, ag, ab = GetAccentRGB()
    line:SetColorTexture(ar, ag, ab, 0.9)
    f.subtitle:SetTextColor(ar, ag, ab, 1)
    RegisterAccented(line, "tex", 0.9)
    RegisterAccented(f.subtitle, "text", 1)
end

-- -----------------------------------------------------------------------------
-- UI helpers
-- -----------------------------------------------------------------------------

local function MakeButton(parent, text, width, height, onClick, skinKind)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 90, height or 22)
    b:SetText(text or "Button")
    b:SetScript("OnClick", onClick)
    RegisterSkinnable(skinKind or "button", b)
    return b
end

-- EllesmereUI-style toggle switch: accent-filled pill with the knob to the
-- right when on, dark track with the knob left when off. Exposes the same
-- SetChecked/GetChecked/.label surface the old checkbox had, so call sites and
-- RefreshUI are unchanged.
local TOGGLE_W, TOGGLE_H = 34, 18
local TOGGLE_PAD, KNOB = 2, 14

local function MakeCheckbox(parent, label, onClick)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(TOGGLE_W, TOGGLE_H)

    cb.track = cb:CreateTexture(nil, "ARTWORK")
    cb.track:SetAllPoints()
    cb.track:SetTexture(IGS_MEDIA .. "toggle-track.png")

    cb.knob = cb:CreateTexture(nil, "OVERLAY")
    cb.knob:SetSize(KNOB, KNOB)
    cb.knob:SetTexture(IGS_MEDIA .. "toggle-knob.png")

    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    cb.label:SetText(label)

    cb._checked = false
    cb._hover = false

    function cb:UpdateVisual()
        local r, g, b = GetAccentRGB()
        self.knob:ClearAllPoints()
        if self._checked then
            self.track:SetVertexColor(r, g, b, self._hover and 1 or 0.9)
            self.knob:SetPoint("RIGHT", -TOGGLE_PAD, 0)
            self.knob:SetVertexColor(1, 1, 1, 1)
            self.label:SetTextColor(1, 1, 1, self._hover and 0.95 or 0.85)
        else
            self.track:SetVertexColor(0.16, 0.19, 0.23, self._hover and 1 or 0.9)
            self.knob:SetPoint("LEFT", TOGGLE_PAD, 0)
            self.knob:SetVertexColor(1, 1, 1, self._hover and 0.65 or 0.5)
            self.label:SetTextColor(1, 1, 1, self._hover and 0.8 or 0.6)
        end
    end

    function cb:SetChecked(value)
        self._checked = value and true or false
        self:UpdateVisual()
    end
    function cb:GetChecked() return self._checked end

    cb:SetScript("OnEnter", function(self) self._hover = true; self:UpdateVisual() end)
    cb:SetScript("OnLeave", function(self) self._hover = false; self:UpdateVisual() end)
    cb:SetScript("OnClick", function(self, ...)
        self:SetChecked(not self._checked)
        if onClick then onClick(self, ...) end
    end)

    cb:UpdateVisual()
    RegisterSkinnable("toggle", cb)
    return cb
end

local function MakeEditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width or 80, 22)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    RegisterSkinnable("editbox", eb)
    return eb
end

-- -----------------------------------------------------------------------------
-- Flat menu + dropdown (replaces UIDropDownMenuTemplate: house style, no taint)
-- -----------------------------------------------------------------------------
local Menu = { frame = nil, catcher = nil, buttons = {}, owner = nil }

local function CloseMenu()
    if Menu.frame then Menu.frame:Hide() end
    if Menu.catcher then Menu.catcher:Hide() end
    Menu.owner = nil
end

local function GetMenuFrame()
    if Menu.frame then return Menu.frame end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:SetScript("OnClick", CloseMenu)
    catcher:Hide()
    Menu.catcher = catcher

    local m = CreateFrame("Frame", "LoadoutManagerMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(20)
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
    Native.Border(m, 0.20)
    m:Hide()
    Menu.frame = m
    return m
end

local function OpenMenu(anchor, items, width)
    local m = GetMenuFrame()
    local ar, ag, ab = GetAccentRGB()
    local shown = 0
    for i = 1, #items do
        local item = items[i]
        local b = Menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, m)
            b:SetHeight(22)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(1, 1, 1, 0.08)
            b.mark = b:CreateTexture(nil, "ARTWORK")
            b.mark:SetPoint("TOPLEFT", 0, -3)
            b.mark:SetPoint("BOTTOMLEFT", 0, 3)
            b.mark:SetWidth(2)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(16, 16)
            b.icon:SetPoint("LEFT", 8, 0)
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.label:SetJustifyH("LEFT")
            ReFont(b.label)
            Menu.buttons[i] = b
        end
        b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
        b:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 22)
        if item.icon then
            b.icon:SetTexture(item.icon)
            b.icon:Show()
            b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        else
            b.icon:Hide()
            b.label:SetPoint("LEFT", 8, 0)
        end
        b.label:SetPoint("RIGHT", -6, 0)
        b.label:SetText(item.text or "")
        if item.checked then
            b.mark:SetColorTexture(ar, ag, ab, 0.9)
            b.mark:Show()
            b.label:SetTextColor(ar, ag, ab, 1)
        else
            b.mark:Hide()
            b.label:SetTextColor(1, 1, 1, 0.75)
        end
        b._func = item.func
        b:SetScript("OnClick", function(self)
            CloseMenu()
            if self._func then self._func() end
        end)
        b:Show()
        shown = shown + 1
    end
    for i = shown + 1, #Menu.buttons do Menu.buttons[i]:Hide() end
    m:SetSize(width or 210, shown * 22 + 8)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    Menu.catcher:Show()
    m:Show()
end

-- Flat dropdown field: bg + border + selected text + arrow glyph
local function MakeDropdown(parent, name, width)
    local dd = CreateFrame("Button", name, parent)
    dd:SetSize(width, 26)
    local bg = dd:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
    local edges = Native.Border(dd, 0.20)
    dd.text = dd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dd.text:SetPoint("LEFT", 8, 0)
    dd.text:SetPoint("RIGHT", -26, 0)
    dd.text:SetJustifyH("LEFT")
    ReFont(dd.text)
    dd.text:SetTextColor(1, 1, 1, 0.75)
    dd.arrow = dd:CreateTexture(nil, "ARTWORK")
    dd.arrow:SetSize(14, 14)
    dd.arrow:SetPoint("RIGHT", -7, 0)
    dd.arrow:SetTexture(IGS_MEDIA .. "arrow-down.png")
    dd.arrow:SetVertexColor(1, 1, 1, 0.55)
    dd._items = {}
    function dd:SetItems(items) self._items = items end
    -- Building the item list allocates a table and a closure per entry. Only
    -- the open menu needs them, so build on click instead of on every refresh.
    function dd:SetItemProvider(fn) self._provider = fn end
    function dd:GetItems()
        if self._provider then return self._provider() end
        return self._items
    end
    function dd:SetSelectedText(text) self.text:SetText(tostring(text or "")) end
    dd:HookScript("OnEnter", function(self)
        SetEdgeAlpha(edges, 0.32)
        self.text:SetTextColor(1, 1, 1, 0.9)
        self.arrow:SetVertexColor(1, 1, 1, 0.85)
    end)
    dd:HookScript("OnLeave", function(self)
        SetEdgeAlpha(edges, 0.20)
        self.text:SetTextColor(1, 1, 1, 0.75)
        self.arrow:SetVertexColor(1, 1, 1, 0.55)
    end)
    dd:SetScript("OnClick", function(self)
        if Menu.frame and Menu.frame:IsShown() and Menu.owner == self then
            CloseMenu()
        else
            OpenMenu(self, self:GetItems(), self:GetWidth())
            Menu.owner = self
        end
    end)
    return dd
end

-- Tooltips: title plus wrapped explanation lines. Every control that is not
-- self-explanatory gets one.
local function AddTooltip(frame, title, ...)
    if not frame or not GameTooltip then return end
    local lines = { ... }
    frame:HookScript("OnEnter", function(self)
        -- eui-style: allow tooltip (rich title+body tooltips; must work without EUI installed)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        for i = 1, #lines do
            local line = lines[i]
            if type(line) == "function" then line = line() end
            if line then GameTooltip:AddLine(line, 0.75, 0.75, 0.75, true) end
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Spec scope tabs: [All Specs][Holy][Protection][Retribution]... built once,
-- lazily, because spec info is only reliable after login.
local function BuildScopeTabs()
    if not UI.scopeRow or UI.scopeTabsBuilt then return end
    local specs = GetSpecList()
    local entries = { { id = nil, name = "All Specs" } }
    for _, s in ipairs(specs) do entries[#entries + 1] = { id = s.id, name = s.name } end
    if #specs == 0 then return end -- retry next refresh once spec info exists

    local anchor
    for _, e in ipairs(entries) do
        local tab = CreateFrame("Button", nil, UI.scopeRow)
        tab.specID = e.id
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.label:SetPoint("CENTER", 0, 0)
        tab.label:SetText(e.name)
        ReFont(tab.label, 1, 1, 1, 0.55)
        local textW = (tab.label.GetStringWidth and tab.label:GetStringWidth()) or 60
        tab:SetSize(math.max(64, textW + 24), 24)
        if anchor then
            tab:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
        else
            tab:SetPoint("LEFT", UI.scopeRow, "LEFT", 70, 0)
        end
        anchor = tab

        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetPoint("BOTTOMLEFT", 4, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -4, 0)
        tab.underline:SetHeight(2)
        local ar, ag, ab = GetAccentRGB()
        tab.underline:SetColorTexture(ar, ag, ab, 0.9)
        RegisterAccented(tab.underline, "tex", 0.9)
        tab.underline:Hide()

        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)

        tab:SetScript("OnClick", function(self)
            UI.assignScope = self.specID
            RefreshUI()
        end)
        if e.id then
            AddTooltip(tab, e.name .. " assignments",
                "Saves and shows assignments used only while you are " .. e.name .. ".",
                "These beat the All Specs entries.")
        else
            AddTooltip(tab, "All Specs",
                "Assignments used by every specialization.",
                "A spec's own assignment takes priority when one exists.")
        end
        UI.scopeTabs[#UI.scopeTabs + 1] = tab
    end
    UI.scopeTabsBuilt = true
end

local function SelectGearSet(setName)
    UI.selectedSet = setName
    if UI.gearDropdown then UI.gearDropdown:SetSelectedText(setName or "Select gear set") end
end

local function SelectTalentLoadout(loadout)
    UI.selectedTalent = StoreTalentLoadout(loadout)
    if UI.talentDropdown then UI.talentDropdown:SetSelectedText(loadout and loadout.name or "Select talent loadout") end
end

local function BuildGearMenuItems()
    local items = {}
    for _, set in ipairs(ListEquipmentSetsDetailed()) do
        local name = set.name
        items[#items + 1] = {
            text = name,
            icon = set.icon,
            checked = (UI.selectedSet == name),
            func = function() SelectGearSet(name); RefreshUI() end,
        }
    end
    return items
end

local function RefreshGearDropdown()
    if not UI.gearDropdown then return end
    UI.gearDropdown:SetSelectedText(UI.selectedSet or "Select gear set")
end

local function BuildTalentMenuItems()
    local items = {}
    for _, loadout in ipairs(ListTalentLoadouts()) do
        local selected = { configID = loadout.configID, name = loadout.name, specID = loadout.specID }
        items[#items + 1] = {
            text = loadout.name,
            checked = (UI.selectedTalent and tonumber(UI.selectedTalent.configID) == tonumber(loadout.configID)),
            func = function() SelectTalentLoadout(selected); RefreshUI() end,
        }
    end
    return items
end

local function RefreshTalentDropdown()
    if not UI.talentDropdown then return end
    UI.talentDropdown:SetSelectedText(TalentDisplayName(UI.selectedTalent) or "Select talent loadout")
end

RefreshUI = function()
    if not UI.frame then return end
    -- Nothing here is visible while the window is hidden, and rebuilding it
    -- allocated tables, strings and a closure per dropdown entry on every
    -- event. Defer to the next OnShow instead.
    if not UI.frame:IsShown() then
        UI.refreshPending = true
        return
    end
    UI.refreshPending = false
    EnsureDB()

    local gearSets = ListEquipmentSets()
    if (not UI.selectedSet or not SetExists(UI.selectedSet)) and #gearSets > 0 then
        UI.selectedSet = gearSets[1]
    end

    local talents = ListTalentLoadouts()
    if (not UI.selectedTalent or not TalentExists(UI.selectedTalent)) and #talents > 0 then
        UI.selectedTalent = StoreTalentLoadout(talents[1])
    end

    UI.enabledCheck:SetChecked(InstanceGearSwapDB.enabled)
    UI.gearCheck:SetChecked(InstanceGearSwapDB.gearEnabled)
    UI.talentCheck:SetChecked(InstanceGearSwapDB.talentEnabled)
    UI.announceCheck:SetChecked(InstanceGearSwapDB.announce)
    UI.queueCheck:SetChecked(InstanceGearSwapDB.queueInCombat)
    if UI.specSwapCheck then UI.specSwapCheck:SetChecked(InstanceGearSwapDB.specSwap) end

    BuildScopeTabs()
    for _, tab in ipairs(UI.scopeTabs or {}) do
        local active = (tab.specID == UI.assignScope)
        if active then tab.underline:Show() else tab.underline:Hide() end
        tab.label:SetTextColor(1, 1, 1, active and 0.95 or 0.55)
    end
    local R, scopeID = GetReadTables()
    local scopeName = scopeID and tostring(SpecName(scopeID)) or "All Specs"
    if UI.rightHeader then
        UI.rightHeader:SetText("Type Defaults - " .. scopeName .. "  |cff999999(click row to assign selected gear/talents)|r")
    end
    if UI.assignmentsHeader then
        UI.assignmentsHeader:SetText("Saved Mappings - " .. scopeName)
    end
    UI.delayBox:SetText(tostring(InstanceGearSwapDB.delay or 2))

    RefreshGearDropdown()
    RefreshTalentDropdown()

    if UI.countText then UI.countText:SetText("Gear sets: " .. tostring(#gearSets) .. "    Talent loadouts: " .. tostring(#talents)) end

    local ctx = GetCurrentInstanceContext()
    local specID = GetCurrentSpecID()
    local gear, gearSource, gearKey, gearScope = GetAssignedSetForContext(ctx)
    local talent, talentSource, talentKey, talentScope = GetAssignedTalentForContext(ctx)
    local function ScopeTag(assigned, sc)
        if not assigned then return "" end
        return " " .. DIMC() .. "[" .. (sc and tostring(SpecName(sc)) or "all") .. "]|r"
    end
    -- One field per line, split into a label column and a value column so the
    -- two FontStrings stay row-aligned (same line count, same spacing).
    local talentName = TalentDisplayName(talent)
    local diffText = tostring(ctx.difficultyName or "Unknown")
    if ctx.difficultyID then diffText = diffText .. " (" .. tostring(ctx.difficultyID) .. ")" end

    UI.currentLabels:SetText(table.concat({
        "Current", "Type", "Spec", "Instance ID", "Difficulty", "Gear", "Talents",
    }, "\n"))

    UI.currentText:SetText(table.concat({
        AC() .. tostring(ctx.name) .. "|r",
        tostring(ctx.instanceType or "none"),
        AC() .. tostring(specID and SpecName(specID) or "Unknown") .. "|r",
        tostring(ctx.instanceID or "none"),
        diffText,
        (gear and (AC() .. gear .. "|r") or (DIMC() .. "none|r")) .. ScopeTag(gear, gearScope),
        (talentName and (AC() .. talentName .. "|r") or (DIMC() .. "none|r")) .. ScopeTag(talent, talentScope),
    }, "\n"))

    for i, info in ipairs(INSTANCE_TYPE_ORDER) do
        local row = UI.defaultRows[i]
        local gearName = R.typeDefaults[info.key]
        local talentName = TalentDisplayName(R.talentTypeDefaults[info.key])
        row.gear:SetText("G: " .. (gearName and ("" .. AC() .. "" .. gearName .. "|r") or "" .. DIMC() .. "none|r"))
        row.talent:SetText("T: " .. (talentName and ("" .. AC() .. "" .. talentName .. "|r") or "" .. DIMC() .. "none|r"))
    end

    UI.assignmentsText:SetText(BuildAssignmentsText(R))
    if UI.assignmentsChild then
        UI.assignmentsChild:SetHeight(math.max((UI.assignmentsText:GetStringHeight() or 0) + 16, 74))
    end
end

local function CreateUI()
    if UI.frame then return end

    local pad = 18
    local gutter = 14
    local frameW, frameH = 820, 780
    local innerW = frameW - (pad * 2)
    local leftColW = 340
    local rightColW = innerW - leftColW - gutter

    local f = CreateFrame("Frame", "InstanceGearSwapFrame", UIParent)
    f:SetSize(frameW, frameH)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnShow", function()
        RefreshPalette()
        RecolorAccents()
        RefreshThemeArt()
        if UI.refreshPending then RefreshUI() end
    end)
    f:SetScript("OnHide", CloseMenu)
    f:Hide()
    UI.frame = f
    RegisterSkinnable("shell", f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", pad, -16)
    title:SetText("Loadout Manager")
    RegisterSkinnable("title", title)

    local close = MakeButton(f, "X", 24, 22, function() f:Hide() end, "close")
    close:SetPoint("TOPRIGHT", -16, -14)

    UI.enabledCheck = MakeCheckbox(f, "Enabled", function(self)
        InstanceGearSwapDB.enabled = self:GetChecked()
        RefreshUI()
    end)
    -- Anchored to the frame (not the title) so the row clears the glow line,
    -- which spans GLOW_Y..GLOW_Y-GLOW_H under the title strip.
    UI.enabledCheck:SetPoint("TOPLEFT", pad - 2, -80)

    UI.gearCheck = MakeCheckbox(f, "Gear", function(self)
        InstanceGearSwapDB.gearEnabled = self:GetChecked()
        RefreshUI()
    end)
    UI.gearCheck:SetPoint("LEFT", UI.enabledCheck.label, "RIGHT", 12, 0)

    UI.talentCheck = MakeCheckbox(f, "Talents", function(self)
        InstanceGearSwapDB.talentEnabled = self:GetChecked()
        RefreshUI()
    end)
    UI.talentCheck:SetPoint("LEFT", UI.gearCheck.label, "RIGHT", 12, 0)

    UI.announceCheck = MakeCheckbox(f, "Announce", function(self)
        InstanceGearSwapDB.announce = self:GetChecked()
        RefreshUI()
    end)
    UI.announceCheck:SetPoint("LEFT", UI.talentCheck.label, "RIGHT", 12, 0)

    UI.queueCheck = MakeCheckbox(f, "Queue in combat", function(self)
        InstanceGearSwapDB.queueInCombat = self:GetChecked()
        RefreshUI()
    end)
    UI.queueCheck:SetPoint("LEFT", UI.announceCheck.label, "RIGHT", 12, 0)

    UI.specSwapCheck = MakeCheckbox(f, "Spec swap", function(self)
        InstanceGearSwapDB.specSwap = self:GetChecked()
        RefreshUI()
    end)
    UI.specSwapCheck:SetPoint("LEFT", UI.queueCheck.label, "RIGHT", 12, 0)
    AddTooltip(UI.enabledCheck, "Enabled", "Master switch. When off, nothing is swapped automatically.")
    AddTooltip(UI.gearCheck, "Gear", "Allow automatic gear set swaps.")
    AddTooltip(UI.talentCheck, "Talents", "Allow automatic talent loadout swaps.")
    AddTooltip(UI.announceCheck, "Announce", "Print a chat message each time gear or talents are swapped.")
    AddTooltip(UI.queueCheck, "Queue in combat",
        "If a swap is triggered during combat, do it as soon as combat ends instead of skipping it.")
    AddTooltip(UI.specSwapCheck, "Spec swap",
        "Re-run the swap when you change specialization inside an instance.",
        "Example: switching Retribution to Holy mid-run loads your Holy defaults for that content.")

    local delayLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    delayLabel:SetPoint("LEFT", UI.specSwapCheck.label, "RIGHT", 14, 0)
    delayLabel:SetText("Delay")
    RegisterSkinnable("label", delayLabel)
    AddTooltip(delayLabel, "Delay",
        "Seconds to wait after zoning before swapping.",
        "Raise it if swaps fire before the game has finished loading you in.")

    UI.delayBox = MakeEditBox(f, 40)
    UI.delayBox:SetPoint("LEFT", delayLabel, "RIGHT", 6, 0)
    UI.delayBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value and value >= 0 then
            InstanceGearSwapDB.delay = value
            Print("Swap delay set to " .. tostring(value) .. " seconds.")
        else
            self:SetText(tostring(InstanceGearSwapDB.delay or 2))
            Print("Invalid delay. Use a number such as 1, 2, or 3.")
        end
        self:ClearFocus()
        RefreshUI()
    end)

    local currentBox = CreateFrame("Frame", nil, f)
    currentBox:SetSize(innerW, 132)
    currentBox:SetPoint("TOPLEFT", pad, -110)
    RegisterSkinnable("panel", currentBox)

    -- Two columns so the labels line up: dim labels left, values right.
    UI.currentLabels = currentBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.currentLabels:SetPoint("TOPLEFT", 12, -10)
    UI.currentLabels:SetWidth(78)
    UI.currentLabels:SetJustifyH("LEFT")
    UI.currentLabels:SetSpacing(3)
    RegisterSkinnable("label", UI.currentLabels)

    UI.currentText = currentBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.currentText:SetPoint("TOPLEFT", 96, -10)
    UI.currentText:SetWidth(360)
    UI.currentText:SetJustifyH("LEFT")
    UI.currentText:SetSpacing(3)
    RegisterSkinnable("text", UI.currentText)

    local checkNow = MakeButton(currentBox, "Check Now", 128, 22, function()
        CheckAndSwap("manual UI")
        RequestRefresh()
    end)
    checkNow:SetPoint("TOPRIGHT", -12, -10)
    AddTooltip(checkNow, "Check Now",
        "Re-runs the automatic swap for where you are standing right now.",
        "Use if you zoned in before the addon was ready, or after changing assignments.")

    local equipSelected = MakeButton(currentBox, "Equip Now", 128, 22, function()
        if UI.selectedSet then TryEquipSet(UI.selectedSet, "manual UI") end
        if UI.selectedTalent then TryLoadTalentLoadout(UI.selectedTalent, "manual UI") end
        RequestRefresh()
    end)
    equipSelected:SetPoint("RIGHT", checkNow, "LEFT", -8, 0)
    AddTooltip(equipSelected, "Equip Now",
        "Immediately equips the gear set and talent loadout selected on the left.",
        "Does not save them as a default for anything.")

    local assignCurrent = MakeButton(currentBox, "Save (Any Diff)", 128, 22, function()
        if AssignCurrentLoadouts(false) then RefreshUI() end
    end)
    assignCurrent:SetPoint("TOPRIGHT", -12, -40)
    AddTooltip(assignCurrent, "Save (Any Diff)",
        "Saves the selected gear/talents for the instance you are currently in, on ANY difficulty.",
        "Overrides the type default for this instance.",
        function() return "Saving for: " .. (UI.assignScope and tostring(SpecName(UI.assignScope)) or "All Specs") end)

    local assignDiff = MakeButton(currentBox, "Save (This Diff)", 128, 22, function()
        if AssignCurrentLoadouts(true) then RefreshUI() end
    end)
    assignDiff:SetPoint("RIGHT", assignCurrent, "LEFT", -8, 0)
    AddTooltip(assignDiff, "Save (This Difficulty Only)",
        "Saves the selected gear/talents for this instance on THIS difficulty only.",
        "Example: a different build for Heroic than Normal in the same raid.",
        "Beats the any-difficulty save above.")

    local clearCurrent = MakeButton(currentBox, "Clear (Any Diff)", 128, 22, function()
        if ClearCurrentLoadouts(false) then RefreshUI() end
    end)
    clearCurrent:SetPoint("TOPRIGHT", -12, -70)
    AddTooltip(clearCurrent, "Clear (Any Difficulty)",
        "Removes the saved gear/talents for this instance.",
        "The matching type default (Raid, Dungeon, etc.) applies again afterwards.")

    local clearDiff = MakeButton(currentBox, "Clear (This Diff)", 128, 22, function()
        if ClearCurrentLoadouts(true) then RefreshUI() end
    end)
    clearDiff:SetPoint("RIGHT", clearCurrent, "LEFT", -8, 0)
    AddTooltip(clearDiff, "Clear (This Difficulty Only)",
        "Removes the saved gear/talents for this instance on this difficulty only.")

    local scopeRow = CreateFrame("Frame", nil, f)
    scopeRow:SetSize(innerW, 24)
    scopeRow:SetPoint("TOPLEFT", currentBox, "BOTTOMLEFT", 0, -12)
    UI.scopeRow = scopeRow

    local scopeLabel = scopeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scopeLabel:SetPoint("LEFT", 0, 0)
    scopeLabel:SetText("Assign for")
    RegisterSkinnable("label", scopeLabel)

    local copyBtn = MakeButton(scopeRow, "Copy from...", 96, 20, function(self)
        local items = {}
        local function AddScope(id, name)
            if id ~= UI.assignScope then
                items[#items + 1] = { text = name, func = function() CopyScopeFrom(id) end }
            end
        end
        AddScope(nil, "All Specs")
        for _, s in ipairs(GetSpecList()) do AddScope(s.id, s.name) end
        OpenMenu(self, items, 150)
        Menu.owner = self
    end)
    copyBtn:SetPoint("RIGHT", scopeRow, "RIGHT", 0, 0)
    AddTooltip(copyBtn, "Copy from...",
        "Copies every assignment from another specialization (or All Specs) into the tab you are on.",
        "Talent entries belonging to other specs are skipped.")
    AddTooltip(scopeLabel, "Assign for",
        "Which specialization the buttons below save to.",
        "All Specs is the fallback used when the current spec has nothing saved.")
    -- tabs themselves are built lazily by BuildScopeTabs (spec info needs login)

    local selectHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectHeader:SetPoint("TOPLEFT", scopeRow, "BOTTOMLEFT", 0, -10)
    selectHeader:SetText("Selected Loadouts")
    RegisterSkinnable("header", selectHeader)

    local selectBox = CreateFrame("Frame", nil, f)
    selectBox:SetSize(leftColW, 152)
    selectBox:SetPoint("TOPLEFT", selectHeader, "BOTTOMLEFT", 0, -6)
    RegisterSkinnable("panel", selectBox)

    local gearLabel = selectBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gearLabel:SetPoint("TOPLEFT", 10, -14)
    gearLabel:SetText("Gear set")
    RegisterSkinnable("label", gearLabel)

    UI.gearDropdown = MakeDropdown(selectBox, "InstanceLoadoutGearDropdown", 258)
    UI.gearDropdown:SetItemProvider(BuildGearMenuItems)
    UI.gearDropdown:SetPoint("TOPLEFT", 10, -30)
    AddTooltip(UI.gearDropdown, "Gear set",
        "Equipment Manager set to use with the Save and Equip buttons.",
        "Create and edit sets in the character pane, not here.")

    local talentLabel = selectBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    talentLabel:SetPoint("TOPLEFT", 10, -74)
    talentLabel:SetText("Talent loadout")
    RegisterSkinnable("label", talentLabel)

    UI.talentDropdown = MakeDropdown(selectBox, "InstanceLoadoutTalentDropdown", 258)
    UI.talentDropdown:SetItemProvider(BuildTalentMenuItems)
    UI.talentDropdown:SetPoint("TOPLEFT", 10, -90)
    AddTooltip(UI.talentDropdown, "Talent loadout",
        "Saved talent loadout to use with the Save and Equip buttons.",
        "Only loadouts for your current specialization are listed.")

    -- The dropdowns above already display the selected gear set and loadout,
    -- so only the counts (new information) are kept here.
    UI.countText = selectBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UI.countText:SetPoint("BOTTOMLEFT", 10, 10)
    RegisterSkinnable("text", UI.countText)

    local rightHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightHeader:SetPoint("TOPLEFT", scopeRow, "BOTTOMLEFT", leftColW + gutter, -10)
    UI.rightHeader = rightHeader
    RegisterSkinnable("header", rightHeader)
    rightHeader:SetText("Type Defaults  |cff999999(click row to assign selected gear/talents)|r")

    local defaultsBox = CreateFrame("Frame", nil, f)
    defaultsBox:SetSize(rightColW, 344)
    defaultsBox:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -6)
    RegisterSkinnable("panel", defaultsBox)

    for i, info in ipairs(INSTANCE_TYPE_ORDER) do
        local row = CreateFrame("Button", nil, defaultsBox)
        row:SetSize(rightColW - 18, 34)
        row:SetPoint("TOPLEFT", 10, -6 - ((i - 1) * 37))
        row.typeKey = info.key
        AddTooltip(row, info.label .. " default",
            "Click to save the selected gear/talents as the default for " .. info.label .. " content.",
            info.hint or "Used when the instance has no specific assignment of its own.")
        row:SetScript("OnClick", function(self)
            if AssignTypeLoadouts(self.typeKey) then RefreshUI() end
        end)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(110)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(info.label)

        row.gear = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.gear:SetPoint("TOPLEFT", 116, -2)
        row.gear:SetWidth(rightColW - 190)
        row.gear:SetJustifyH("LEFT")

        row.talent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.talent:SetPoint("TOPLEFT", 116, -18)
        row.talent:SetWidth(rightColW - 190)
        row.talent:SetJustifyH("LEFT")

        row.clear = MakeButton(row, "X", 26, 20, function(self)
            if ClearTypeLoadouts(self:GetParent().typeKey) then RefreshUI() end
        end)
        row.clear:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        AddTooltip(row.clear, "Clear " .. info.label,
            "Removes the gear and talent default for " .. info.label .. " in the current tab.")

        row._stripeIndex = i
        RegisterSkinnable("row", row)
        UI.defaultRows[i] = row
    end

    local manualHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    manualHeader:SetPoint("TOPLEFT", selectBox, "BOTTOMLEFT", 0, -12)
    manualHeader:SetText("Manual Map by ID")
    RegisterSkinnable("header", manualHeader)

    local manualBox = CreateFrame("Frame", nil, f)
    manualBox:SetSize(leftColW, 90)
    manualBox:SetPoint("TOPLEFT", manualHeader, "BOTTOMLEFT", 0, -6)
    RegisterSkinnable("panel", manualBox)

    local idLabel = manualBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idLabel:SetPoint("TOPLEFT", 10, -14)
    idLabel:SetText("Instance ID")
    RegisterSkinnable("label", idLabel)

    UI.manualInstanceBox = MakeEditBox(manualBox, 70)
    UI.manualInstanceBox:SetPoint("LEFT", idLabel, "RIGHT", 8, 0)

    local diffLabel = manualBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diffLabel:SetPoint("LEFT", UI.manualInstanceBox, "RIGHT", 14, 0)
    diffLabel:SetText("Diff")
    RegisterSkinnable("label", diffLabel)

    UI.manualDiffBox = MakeEditBox(manualBox, 48)
    UI.manualDiffBox:SetPoint("LEFT", diffLabel, "RIGHT", 8, 0)

    local mapID = MakeButton(manualBox, "Save by ID", 88, 22, function()
        if AssignManualLoadouts(false) then RefreshUI() end
    end)
    mapID:SetPoint("TOPLEFT", 10, -42)
    AddTooltip(mapID, "Save by Instance ID",
        "Saves the selected gear/talents for the instance ID typed above, without being there.",
        "Find an instance's ID by standing in it - it is shown in the status box at the top.")

    local mapDiff = MakeButton(manualBox, "Save by ID + Diff", 110, 22, function()
        if AssignManualLoadouts(true) then RefreshUI() end
    end)
    mapDiff:SetPoint("LEFT", mapID, "RIGHT", 8, 0)
    AddTooltip(mapDiff, "Save by Instance ID + Difficulty",
        "As above, but only for the difficulty ID typed in the Diff box.")

    local assignmentsHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    assignmentsHeader:SetPoint("TOPLEFT", manualBox, "BOTTOMLEFT", 0, -12)
    assignmentsHeader:SetText("Saved Mappings")
    UI.assignmentsHeader = assignmentsHeader
    RegisterSkinnable("header", assignmentsHeader)

    local assignmentsBox = CreateFrame("Frame", nil, f)
    assignmentsBox:SetSize(leftColW, 92)
    assignmentsBox:SetPoint("TOPLEFT", assignmentsHeader, "BOTTOMLEFT", 0, -6)
    RegisterSkinnable("panel", assignmentsBox)

    local assignmentsScroll = CreateFrame("ScrollFrame", nil, assignmentsBox, "UIPanelScrollFrameTemplate")
    assignmentsScroll:SetPoint("TOPLEFT", 8, -8)
    assignmentsScroll:SetPoint("BOTTOMRIGHT", -28, 8)
    RegisterSkinnable("scroll", assignmentsScroll)

    UI.assignmentsChild = CreateFrame("Frame", nil, assignmentsScroll)
    UI.assignmentsChild:SetSize(leftColW - 36, 74)
    assignmentsScroll:SetScrollChild(UI.assignmentsChild)

    UI.assignmentsText = UI.assignmentsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.assignmentsText:SetPoint("TOPLEFT", 0, 0)
    UI.assignmentsText:SetWidth(leftColW - 44)
    UI.assignmentsText:SetJustifyH("LEFT")
    RegisterSkinnable("text", UI.assignmentsText)

    local refresh = MakeButton(f, "Refresh", 74, 22, RefreshUI)
    refresh:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 16)

    local help = MakeButton(f, "Help", 64, 22, PrintHelp)
    help:SetPoint("RIGHT", refresh, "LEFT", -8, 0)
end

local ToggleUI -- forward: the addon compartment click handler below needs it

ToggleUI = function()
    EnsureDB()
    CreateUI()
    if UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.assignScope = GetCurrentSpecID()
        UI.frame:SetScale(tonumber(InstanceGearSwapDB.uiScale) or 1)
        UI.refreshPending = true
        UI.frame:Show() -- OnShow re-syncs the palette, then runs the refresh
    end
end

-- Minimap addon-compartment launcher (## AddonCompartmentFunc in the TOC)
function InstanceGearSwap_OnAddonCompartmentClick()
    ToggleUI()
end

-- -----------------------------------------------------------------------------
-- Slash commands and events
-- -----------------------------------------------------------------------------

local function SlashHandler(msg)
    EnsureDB()
    local cmd, rest = SplitFirst(msg)
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "gui" or cmd == "config" or cmd == "options" then
        ToggleUI()
    elseif cmd == "help" then
        PrintHelp()
    elseif cmd == "current" then
        PrintCurrentContext()
    elseif cmd == "sets" then
        PrintSets()
    elseif cmd == "talents" or cmd == "talentlist" then
        PrintTalents()
    elseif cmd == "now" then
        CheckAndSwap("manual")
        RequestRefresh()
    elseif cmd == "warning" then
        local value = Trim(rest):lower()
        if value == "" then
            Print("Themed spec-change panel is " .. (InstanceGearSwapDB.specWarning and "on" or "off") ..
                "; Blizzard raid-warning text is " .. (InstanceGearSwapDB.raidWarningText and "on" or "off") ..
                ". Use " .. AC() .. "/lm warning on|off|r or " .. AC() .. "/lm raidwarning on|off|r.")
        else
            InstanceGearSwapDB.specWarning = value == "on"
            Print("Themed spec-change panel " .. (InstanceGearSwapDB.specWarning and "enabled" or "disabled") .. ".")
        end
    elseif cmd == "raidwarning" then
        local value = Trim(rest):lower()
        InstanceGearSwapDB.raidWarningText = value == "on"
        Print("Blizzard raid-warning text " .. (InstanceGearSwapDB.raidWarningText and "enabled" or "disabled") .. ".")
    elseif cmd == "testwarning" then
        ShowSpecChangeWarning("DONT MOVE - CHANGING SPECS", 4, true)
    elseif cmd == "on" then
        InstanceGearSwapDB.enabled = true
        Print("Enabled. Automatic swaps will only run when you enter a new instance. Use /igs now or Check Now to run manually.")
        RefreshUI()
    elseif cmd == "off" then
        InstanceGearSwapDB.enabled = false
        Print("Disabled.")
        RefreshUI()
    elseif cmd == "gear" then
        local value = Trim(rest):lower()
        InstanceGearSwapDB.gearEnabled = value ~= "off"
        Print("Gear swaps " .. (InstanceGearSwapDB.gearEnabled and "enabled" or "disabled") .. ".")
        RefreshUI()
    elseif cmd == "talent" or cmd == "talentswap" then
        local value = Trim(rest):lower()
        InstanceGearSwapDB.talentEnabled = value ~= "off"
        Print("Talent swaps " .. (InstanceGearSwapDB.talentEnabled and "enabled" or "disabled") .. ".")
        RefreshUI()
    elseif cmd == "set" then
        AssignCurrentInstance(rest, false)
        RefreshUI()
    elseif cmd == "setdiff" then
        AssignCurrentInstance(rest, true)
        RefreshUI()
    elseif cmd == "type" then
        local instanceType, setName = SplitFirst(rest)
        AssignTypeSet(instanceType, setName)
        RefreshUI()
    elseif cmd == "cleartype" then
        ClearTypeByName(rest)
        RefreshUI()
    elseif cmd == "verify" then
        EnsureDB()
        if not EquipmentCacheReady() then
            Print("Equipment sets are still loading - try again in a moment.")
            return
        end
        local problems = 0
        local function CheckTables(tbl, scopeName)
            for _, key in ipairs({ "instanceSets", "difficultySets", "typeDefaults" }) do
                for mapKey, setName in pairs(tbl[key] or {}) do
                    if type(setName) == "string" and not SetExists(setName) then
                        problems = problems + 1
                        print("  " .. ERRC() .. tostring(setName) .. "|r - " .. key .. " [" .. tostring(mapKey) .. "] in " .. scopeName)
                    end
                end
            end
        end
        CheckTables(InstanceGearSwapDB, "All Specs")
        for specID, bucket in pairs(InstanceGearSwapDB.specDefaults or {}) do
            CheckTables(bucket, tostring(SpecName(specID)))
        end
        if problems == 0 then
            Print("All gear assignments point to existing Equipment Manager sets.")
        else
            Print(problems .. " assignment(s) reference missing gear sets (listed above). Reassign them, or clear with the X buttons.")
        end
    elseif cmd == "perf" then
        local now = (GetTime and GetTime()) or 0
        local mins = math.max((now - (Perf.since or now)) / 60, 0.01)
        Print("Activity since login (" .. string.format("%.1f", mins) .. " min):")
        local names, total = {}, 0
        for name, count in pairs(Perf.events) do
            names[#names + 1] = name
            total = total + count
        end
        table.sort(names, function(a, b) return (Perf.events[a] or 0) > (Perf.events[b] or 0) end)
        for i = 1, #names do
            local count = Perf.events[names[i]]
            local rate = count / mins
            local flag = (rate > 60) and (" " .. ERRC() .. "<-- very frequent|r") or ""
            print(string.format("  %-32s %6d  (%.1f/min)%s", names[i], count, rate, flag))
        end
        print(string.format("  %-32s %6d", "UI refreshes", Perf.refreshes))
        print(string.format("  %-32s %6d", "gear swap attempts", Perf.swapAttempts))
        print(string.format("  %-32s %6d", "talent load attempts", Perf.talentAttempts or 0))
        print(string.format("  %-32s %6d", "context checks", Perf.checks))
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            local kb = GetAddOnMemoryUsage(ADDON_NAME) or 0
            print(string.format("  %-32s %6.2f MB", "memory attributed", kb / 1024))
            print("  Note: this figure is memory allocated since the last garbage")
            print("  collection, not a leak. " .. AC() .. "/lm gc|r forces a collection to compare.")
        end
    elseif cmd == "gc" then
        local before = 0
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            before = GetAddOnMemoryUsage(ADDON_NAME) or 0
        end
        collectgarbage("collect")
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            local after = GetAddOnMemoryUsage(ADDON_NAME) or 0
            Print(string.format("Memory before %.2f MB, after collection %.2f MB (reclaimed %.2f MB).",
                before / 1024, after / 1024, (before - after) / 1024))
            Print("If the after figure stays high, that is real retained memory worth reporting.")
        else
            collectgarbage("collect")
            Print("Garbage collection requested.")
        end
    elseif cmd == "scale" then
        local value = tonumber(Trim(rest))
        if value and value >= 0.5 and value <= 2 then
            InstanceGearSwapDB.uiScale = value
            if UI.frame then UI.frame:SetScale(value) end
            Print("Window scale set to " .. tostring(value) .. ".")
        else
            Print("Usage: " .. AC() .. "/lm scale 0.5-2.0|r (current: " .. tostring(InstanceGearSwapDB.uiScale or 1) .. ")")
        end
    elseif cmd == "specswap" then
        local value = Trim(rest):lower()
        InstanceGearSwapDB.specSwap = value ~= "off"
        Print("Spec-change swaps " .. (InstanceGearSwapDB.specSwap and "enabled" or "disabled") .. ".")
        RefreshUI()
    elseif cmd == "announce" then
        local value = Trim(rest):lower()
        InstanceGearSwapDB.announce = value ~= "off"
        Print("Announcements " .. (InstanceGearSwapDB.announce and "enabled" or "disabled") .. ".")
        RefreshUI()
    elseif cmd == "debug" then
        local value = Trim(rest):lower()
        InstanceGearSwapDB.debug = value == "on"
        Print("Debug " .. (InstanceGearSwapDB.debug and "enabled" or "disabled") .. ".")
    elseif cmd == "status" then
        Print("Enabled: " .. tostring(InstanceGearSwapDB.enabled) .. ", gear: " .. tostring(InstanceGearSwapDB.gearEnabled) .. ", talents: " .. tostring(InstanceGearSwapDB.talentEnabled) .. ", delay: " .. tostring(InstanceGearSwapDB.delay))
        PrintCurrentContext()
    else
        Print("Unknown command: " .. cmd .. ". Use " .. AC() .. "/lm help|r.")
    end
end

IGS:SetScript("OnEvent", function(self, event, ...)
    Perf.events[event] = (Perf.events[event] or 0) + 1
    if not Perf.since then Perf.since = (GetTime and GetTime()) or 0 end
    if event == "ADDON_LOADED" then
        dbReady = false -- saved variables just replaced the table
        local addon = ...
        if addon == ADDON_NAME then
            EnsureDB()
            SLASH_INSTANCEGEARSWAP1 = "/lm"
            SLASH_INSTANCEGEARSWAP2 = "/loadoutmanager"
            SLASH_INSTANCEGEARSWAP3 = "/igs" -- legacy alias
            SLASH_INSTANCEGEARSWAP4 = "/ilm" -- legacy alias
            SlashCmdList.INSTANCEGEARSWAP = SlashHandler
            Print("Loaded. Use " .. AC() .. "/lm|r to open the loadout manager.")
            -- Ours is loaded; every later ADDON_LOADED belongs to some other
            -- addon and only costs us a wakeup, so stop listening.
            pcall(self.UnregisterEvent, self, "ADDON_LOADED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshPalette()
        RecolorAccents()
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            -- Seed the current context without swapping. This prevents reload/login inside
            -- combat or inside an already-running dungeon from triggering a fresh auto-swap.
            lastAutoInstanceKey = BuildAutoInstanceKey(GetCurrentInstanceContext())
            Debug("initial login/reload; auto-swap key seeded without firing: ", tostring(lastAutoInstanceKey))
        else
            HandlePossibleInstanceEntry("entering world")
        end
        C_Timer.After(0.3, RefreshUI)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        HandlePossibleInstanceEntry("zone changed")
        C_Timer.After(0.3, RefreshUI)
    elseif event == "PLAYER_REGEN_ENABLED" then
        RunQueuedAfterCombat()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if ... == "player" then
            EnsureDB()
            InvalidateTalentCache() -- loadout list is per spec
            ShowSpecChangeWarning("DONT MOVE - CHANGING SPECS", 3)
            UI.selectedTalent = nil
            if InstanceGearSwapDB.specSwap then
                -- The auto-key includes the spec, so this re-fires the swap for
                -- the new spec's assignments when it happens inside an instance.
                C_Timer.After(1, function() HandlePossibleInstanceEntry("spec change") end)
            end
            C_Timer.After(0.3, function()
                if UI.frame and UI.frame:IsShown() then UI.assignScope = GetCurrentSpecID() end
                RefreshUI()
            end)
        end
    elseif event == "EQUIPMENT_SETS_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" or event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" or event == "SELECTED_LOADOUT_CHANGED" then
        -- Game state changed: drop the cached enumerations so the next read
        -- rebuilds them (and only then).
        if event == "EQUIPMENT_SETS_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" then
            InvalidateGearCache()
        end
        if event == "TRAIT_CONFIG_UPDATED" or event == "SELECTED_LOADOUT_CHANGED"
            or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
            InvalidateTalentCache()
        end

        -- The cache just became available: finish any swap that was waiting on it.
        if event == "EQUIPMENT_SETS_CHANGED" and pendingGear then
            C_Timer.After(0.1, RetryPendingGear)
        end
        if event == "EQUIPMENT_SWAP_FINISHED" and expectedSet then
            C_Timer.After(0.2, VerifyEquippedSet)
        end
        if (event == "TRAIT_CONFIG_UPDATED" or event == "SELECTED_LOADOUT_CHANGED") and pendingTalent then
            C_Timer.After(0.1, RetryPendingTalent)
        end
        -- A load that reported LoadInProgress finishes here: re-sync the talent
        -- UI so its dropdown matches what was actually applied.
        if event == "TRAIT_CONFIG_UPDATED" and lastLoadedConfigID then
            local configID = lastLoadedConfigID
            lastLoadedConfigID = nil
            C_Timer.After(0.1, function() SyncTalentUI(configID) end)
        end
        RequestRefresh()
    end
end)

local function SafeRegister(eventName)
    local ok = pcall(IGS.RegisterEvent, IGS, eventName)
    if not ok then
        -- Some talent events are client-version dependent. Ignore if unavailable.
    end
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("ZONE_CHANGED_NEW_AREA")
SafeRegister("PLAYER_REGEN_ENABLED")
SafeRegister("PLAYER_SPECIALIZATION_CHANGED")
SafeRegister("EQUIPMENT_SETS_CHANGED")
SafeRegister("EQUIPMENT_SWAP_FINISHED")
SafeRegister("TRAIT_CONFIG_UPDATED")
SafeRegister("ACTIVE_COMBAT_CONFIG_CHANGED")
SafeRegister("SELECTED_LOADOUT_CHANGED")

-- -----------------------------------------------------------------------------
-- EllesmereUI skin bootstrap
-- EUI loads first (## OptionalDeps), queues this callback, and runs it at
-- PLAYER_LOGIN when its Blizz UI Enhanced skinning is active for this addon.
-- Errors in the callback are isolated by EUI and never break either addon.
-- -----------------------------------------------------------------------------
-- Baseline palette sync at load: EUI's exported accent when installed, else house teal.
RefreshPalette()

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin(ADDON_NAME, function(S)
        Skin.S = S
        RefreshPalette()
        RecolorAccents()
        if S.OnLooksChanged then
            pcall(S.OnLooksChanged, function()
                RefreshPalette()
                RecolorAccents()
                RefreshThemeArt()
                RefreshUI()
            end)
        end
        Skin.Apply() -- repaints via the facade anything already drawn natively
        RefreshUI()
    end)
end
