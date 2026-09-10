if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Engine for the Loadout Manager: saved variables, context resolution and the
--  swap/verify machinery. The settings surface is EUI_LoadoutManager_Options.lua
--  and drives this through the ns API published at the bottom of the file.
--  Resolution order, first match wins, current spec before the All Specs layer:
--  instance + difficulty -> instance -> specific type (Mythic+, Timewalking,
--  Delve) -> general type -> Open World (on exit).
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options file reads this module ns via the registry

local IGS = CreateFrame("Frame")

-- Chat colours follow the live EllesmereUI accent rather than a fixed teal.
local function AccentHex()
    if EllesmereUI.GetAccentColor then
        local ok, r, g, b = pcall(EllesmereUI.GetAccentColor)
        if ok and r and g and b then
            return string.format("%02x%02x%02x",
                math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
        end
    end
    local eg = EllesmereUI.ELLESMERE_GREEN
    if eg and eg.r then
        return string.format("%02x%02x%02x",
            math.floor(eg.r * 255 + 0.5), math.floor(eg.g * 255 + 0.5), math.floor(eg.b * 255 + 0.5))
    end
    return "0cd29f"
end

local function AC()   return "|cff" .. AccentHex() end
local function ERRC() return "|cffff6b6b" end

local function PREFIX() return AC() .. "Loadout Manager|r" end

local DEFAULTS = {
    -- Off until the user opts in: installing or updating the suite must not
    -- start swapping anyone's gear. Everything below only applies once this
    -- is switched on, and switching it on is what registers the events.
    enabled = false,
    gearEnabled = true,
    talentEnabled = true,
    announce = true,
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

local SetEventsEnabled -- forward: defined with the event gating at the end
local UpdateRegenRegistration -- forward: same

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
local expectedSet = nil        -- { name = ..., at = time } verified on EQUIPMENT_SWAP_FINISHED
local RetryPendingGear, RetryPendingTalent -- forward
local lastAttemptKey = nil
local lastAttemptTime = 0
local lastTalentAttemptKey = nil
local lastTalentAttemptTime = 0
local lastAutoInstanceKey = nil

-- Selection + edit scope shared with the options page (the page reads and
-- writes these through the ns API rather than owning any state itself).
local UI = {
    selectedSet = nil,
    selectedTalent = nil,
    assignScope = nil, -- nil = All Specs layer; otherwise a specID
}

-- Several events commonly fire together (equipment set changed + swap finished
-- + loadout changed). Coalesce them into a single options-page refresh, and
-- only when that page is actually open.
local refreshScheduled = false
local function RequestRefresh(delay)
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(delay or 0.2, function()
        refreshScheduled = false
        if ns.OnStateChanged then ns.OnStateChanged() end
    end)
end

local function Print(msg)
    print(PREFIX() .. " " .. tostring(msg))
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
    if dbReady and EllesmereUILoadoutManagerDB then return end
    EllesmereUILoadoutManagerDB = CopyDefaults(DEFAULTS, EllesmereUILoadoutManagerDB)
    dbReady = true
end

local function Announce(msg)
    if EllesmereUILoadoutManagerDB and EllesmereUILoadoutManagerDB.announce then Print(msg) end
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
    local bucket = EllesmereUILoadoutManagerDB.specDefaults[specID]
    if not bucket then
        if not create then return nil end
        bucket = {}
        EllesmereUILoadoutManagerDB.specDefaults[specID] = bucket
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
local CopyScopeFrom -- assigned below (needs Print upvalue resolved late)

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
    return EllesmereUILoadoutManagerDB, nil
end

CopyScopeFrom = function(sourceID)
    EnsureDB()
    local dst, dstID = GetWriteTables()
    local srcT = sourceID and (GetSpecTables(sourceID, false) or EMPTY_SCOPE) or EllesmereUILoadoutManagerDB
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
    RequestRefresh()
end

local function GetReadTables()
    if UI.assignScope then
        return GetSpecTables(UI.assignScope, false) or EMPTY_SCOPE, UI.assignScope
    end
    EnsureDB()
    return EllesmereUILoadoutManagerDB, nil
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
    if not force and not EllesmereUILoadoutManagerDB.specWarning then return end
    message = message or "DONT MOVE - CHANGING SPECS"
    duration = tonumber(duration) or 4

    -- Blizzard's raid-warning channel renders as big orange centred text,
    -- separate from our themed panel below. Opt-in only.
    if EllesmereUILoadoutManagerDB.raidWarningText
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

        -- Panel styling straight from the parent's primitives, so it tracks
        -- the active theme without carrying its own art.
        local bgc = EllesmereUI.DARK_BG
        local pr, pg, pb = (bgc and bgc.r) or 0.05, (bgc and bgc.g) or 0.07, (bgc and bgc.b) or 0.09
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(pr, pg, pb, 0.92)
        if EllesmereUI.MakeBorder then
            pcall(EllesmereUI.MakeBorder, f, 1, 1, 1, 0.08)
        end
        local font = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()
        if font then
            f.title:SetFont(font, 26, "OUTLINE")
            f.subtitle:SetFont(font, 16, "")
        end
        local line = f:CreateTexture(nil, "OVERLAY")
        line:SetPoint("BOTTOMLEFT", 1, 1)
        line:SetPoint("BOTTOMRIGHT", -1, 1)
        line:SetHeight(2)
        f.accentLine = line

        f:Hide()
        specChangeWarningFrame = f
    end

    -- Re-tint per show: the accent may have changed since the panel was built.
    if specChangeWarningFrame.accentLine and EllesmereUI.GetAccentColor then
        local ok, ar, ag, ab = pcall(EllesmereUI.GetAccentColor)
        if ok and ar then
            specChangeWarningFrame.accentLine:SetColorTexture(ar, ag, ab, 0.9)
            specChangeWarningFrame.subtitle:SetTextColor(ar, ag, ab, 1)
        end
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
-- sorts; the options page used to do it four times per build, and equipment events fire
-- constantly in a raid. Cache the results and rebuild only when the game tells
-- us they changed (see InvalidateGearCache / InvalidateTalentCache).
local cacheGearDetailed, cacheTalents, cacheTalentSpec

local function ByNameAsc(a, b) return a.name < b.name end
local function ByNameLowerAsc(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end

local function InvalidateGearCache()
    cacheGearDetailed = nil
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

    if not EllesmereUILoadoutManagerDB.enabled or not EllesmereUILoadoutManagerDB.gearEnabled then
        return
    end

    setName = Trim(setName)
    if setName == "" then return end

    if InCombatLockdown() then
        if EllesmereUILoadoutManagerDB.queueInCombat then
            queuedSetName = setName
            queuedSetReason = reason or "queued"
            UpdateRegenRegistration()
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
            C_Timer.After(1, RetryPendingGear)
            return
        end
        pendingGear = nil
        Print("Could not find Equipment Manager set named " .. ERRC() .. "" .. setName ..
            "|r. It may have been renamed or deleted - use Verify Sets on the settings page to find stale assignments.")
        return
    end
    pendingGear = nil

    if info.isEquipped then
        return
    end

    local now = GetTime and GetTime() or 0
    local attemptKey = tostring(info.setID) .. ":" .. tostring(reason or "auto")
    if attemptKey == lastAttemptKey and (now - lastAttemptTime) < 1.5 then
        return
    end
    lastAttemptKey = attemptKey
    lastAttemptTime = now

    if info.numLost and info.numLost > 0 then
        Announce("Gear set " .. AC() .. "" .. info.name .. "|r has " .. tostring(info.numLost) ..
            " missing item(s) - they may be in the bank or void storage. Equipping the rest.")
    end
    expectedSet = { name = info.name, at = (GetTime and GetTime()) or 0 }

    local ok = C_EquipmentSet.UseEquipmentSet(info.setID)
    if ok == false then
        queuedSetName = info.name
        queuedSetReason = reason or "retry"
        UpdateRegenRegistration()
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
    local spec = specID and EllesmereUILoadoutManagerDB.specDefaults[specID] or nil

    -- Outside an instance only the Open World default applies (no instance ID
    -- to key specific mappings against).
    if not ctx.inInstance then
        local candidates = {
            { spec and spec[kType], specID },
            { EllesmereUILoadoutManagerDB[kType], nil },
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
        { EllesmereUILoadoutManagerDB[kDiff], diffKey, "difficulty", nil },
        { spec and spec[kInst], instanceKey, "instance", specID },
        { EllesmereUILoadoutManagerDB[kInst], instanceKey, "instance", nil },
    }
    -- Type-level keys, most specific first (mplus/timewalking/delve before
    -- their parent type).
    local typeKeys = TypeKeysForContext(ctx)
    for i = 1, #typeKeys do
        candidates[#candidates + 1] = { spec and spec[kType], typeKeys[i], "type", specID }
        candidates[#candidates + 1] = { EllesmereUILoadoutManagerDB[kType], typeKeys[i], "type", nil }
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

local function LoadResultCodes()
    local e = Enum.LoadConfigResult
    return e.Error, e.NoChangesNecessary, e.LoadInProgress
end

local function TryLoadTalentLoadout(stored, reason)
    EnsureDB()

    if InActiveKeystone() then
        Print("Keystone active: talents are locked until the run ends. Swap skipped.")
        return
    end

    if not EllesmereUILoadoutManagerDB.enabled or not EllesmereUILoadoutManagerDB.talentEnabled then
        return
    end

    local loadout = GetTalentLoadoutFromStored(stored)
    if not loadout then
        -- Talent configs are also cached late; only complain once they exist.
        local tries = (pendingTalent and pendingTalent.tries or 0) + 1
        if tries <= MAX_LOOKUP_RETRIES and #ListTalentLoadouts() == 0 then
            pendingTalent = { stored = stored, reason = reason, tries = tries }
            C_Timer.After(1, RetryPendingTalent)
            return
        end
        pendingTalent = nil
        Print("Could not find the assigned talent loadout for your current spec.")
        return
    end
    pendingTalent = nil

    if InCombatLockdown() then
        if EllesmereUILoadoutManagerDB.queueInCombat then
            queuedTalent = StoreTalentLoadout(loadout)
            queuedTalentReason = reason or "queued"
            UpdateRegenRegistration()
            Announce("In combat. Queued talent loadout " .. AC() .. "" .. loadout.name .. "|r for after combat.")
        else
            Announce("In combat. Talent swap skipped.")
        end
        return
    end

    if C_ClassTalents and C_ClassTalents.CanChangeTalents then
        local okCan, canChange = pcall(C_ClassTalents.CanChangeTalents)
        if okCan and canChange == false then
            if EllesmereUILoadoutManagerDB.queueInCombat then
                queuedTalent = StoreTalentLoadout(loadout)
                queuedTalentReason = reason or "queued"
                UpdateRegenRegistration()
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
        return
    end

    local now = GetTime and GetTime() or 0
    local attemptKey = tostring(loadout.configID) .. ":" .. tostring(reason or "auto")
    if attemptKey == lastTalentAttemptKey and (now - lastTalentAttemptTime) < 2 then
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
    local okLoad, result = pcall(C_ClassTalents.LoadConfig, loadout.configID, true)
    if not okLoad then
        queuedTalent = StoreTalentLoadout(loadout)
        queuedTalentReason = reason or "retry"
        UpdateRegenRegistration()
        Print("Talent loadout failed: " .. tostring(result))
        return
    end

    -- pcall succeeding only means the call did not error; the API reports the
    -- real outcome in its return code. Treating Error as success is what made
    -- the addon claim it loaded a build that was only staged, never applied.
    local ERR, NO_CHANGE, IN_PROGRESS = LoadResultCodes()
    if result == ERR then
        local openUI = PlayerSpellsFrame and PlayerSpellsFrame:IsShown()
        if openUI then
            Print("Could not apply " .. AC() .. "" .. loadout.name ..
                "|r while the talent window is open - close it and press Check Now on the settings page.")
        else
            queuedTalent = StoreTalentLoadout(loadout)
            queuedTalentReason = reason or "retry"
            UpdateRegenRegistration()
            Print("Could not apply talent loadout " .. ERRC() .. "" .. loadout.name ..
                "|r yet (unspent points or the game refused the change). Queued a retry.")
        end
        return
    end

    if C_ClassTalents.UpdateLastSelectedSavedConfigID then
        pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, loadout.specID or GetCurrentSpecID(), loadout.configID)
    end

    if result == NO_CHANGE then
        return
    end
    Announce("Loading talents " .. AC() .. "" .. loadout.name .. "|r" .. (reason and (" (" .. reason .. ")") or "") .. ".")
end

-- -----------------------------------------------------------------------------
-- Assignment helpers
-- -----------------------------------------------------------------------------

local function CheckAndSwap(reason)
    EnsureDB()
    if not EllesmereUILoadoutManagerDB.enabled then return end

    if InActiveKeystone() then
        Print("Keystone active: gear and talents are locked. Swaps skipped until the run ends.")
        return
    end

    local ctx = GetCurrentInstanceContext()

    if not ctx.inInstance then
        -- Silent no-op unless an Open World default is configured, so players
        -- who do not use it never see gear changes out of instances.
        local worldGear = GetAssignedSetForContext(ctx)
        local worldTalent = GetAssignedTalentForContext(ctx)
        if not worldGear and not worldTalent then
            return
        end
    end

    local setName, gearSource = GetAssignedSetForContext(ctx)
    if setName and EllesmereUILoadoutManagerDB.gearEnabled then
        local label = ctx.name
        if gearSource == "difficulty" then label = ctx.name .. " - " .. tostring(ctx.difficultyName or ctx.difficultyID) end
        if gearSource == "type" then
            label = ctx.inInstance and (tostring(ctx.instanceType) .. " default") or "open world default"
        end
        TryEquipSet(setName, label)
    end

    local talentStored, talentSource = GetAssignedTalentForContext(ctx)
    if talentStored and EllesmereUILoadoutManagerDB.talentEnabled then
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
    local delay = tonumber(EllesmereUILoadoutManagerDB.delay) or 2
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
        return
    end

    local leaving = (not ctx.inInstance)
    lastAutoInstanceKey = key
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
            Print("Gear set " .. ERRC() .. "" .. wanted .. "|r did not finish equipping. Press Check Now to retry.")
        end
        return
    end
end

local function RunQueuedAfterCombat()
    local hadQueued = false
    -- Whatever happens below, the debts are settled by the end of this call;
    -- re-evaluate at the end so the regen handler can be dropped again.

    if queuedSetName then
        local setName = queuedSetName
        local reason = queuedSetReason or "after combat"
        queuedSetName = nil
        queuedSetReason = nil
        hadQueued = true
        C_Timer.After(0.25, function()
            TryEquipSet(setName, reason)
            RequestRefresh()
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
            RequestRefresh()
        end)
    end

    UpdateRegenRegistration()
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





-- -----------------------------------------------------------------------------
-- Text output
-- -----------------------------------------------------------------------------





-- Scratch tables reused across refreshes; this function only returns a string,
-- so nothing outside it can hold a reference to them.
local assignmentLines, assignmentKeyMap, assignmentKeys = {}, {}, {}




-- -----------------------------------------------------------------------------
-- Slash commands and events
-- -----------------------------------------------------------------------------

-- List every assignment pointing at an Equipment Manager set that no longer
-- exists. Driven by the settings page's Verify Sets button.
local function VerifyAssignments()
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
    CheckTables(EllesmereUILoadoutManagerDB, "All Specs")
    for specID, bucket in pairs(EllesmereUILoadoutManagerDB.specDefaults or {}) do
        CheckTables(bucket, tostring(SpecName(specID)))
    end
    if problems == 0 then
        Print("All gear assignments point to existing Equipment Manager sets.")
    else
        Print(problems .. " assignment(s) reference missing gear sets (listed above). Reassign them, or clear with the X buttons.")
    end
end

-- Every setting and action lives on the settings page now; the slash exists
-- to open it. The one exception is raidwarning, which has no page control.
local function SlashHandler(msg)
    EnsureDB()
    local cmd, rest = SplitFirst(msg)
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "gui" or cmd == "config" or cmd == "options" then
        if EllesmereUI.ShowModule then
            EllesmereUI:ShowModule(ADDON_NAME)
        end
    elseif cmd == "raidwarning" then
        -- Blizzard's orange raid-warning text for the spec-change notice.
        EllesmereUILoadoutManagerDB.raidWarningText = Trim(rest):lower() == "on"
        Print("Blizzard raid-warning text " .. (EllesmereUILoadoutManagerDB.raidWarningText and "enabled" or "disabled") .. ".")
    else
        Print("Settings live on the EllesmereUI panel - " .. AC() .. "/lm|r opens the Loadout Manager page.")
    end
end

IGS:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        dbReady = false -- saved variables just replaced the table
        local addon = ...
        if addon == ADDON_NAME then
            EnsureDB()
            SLASH_EUILOADOUTMANAGER1 = "/lm"
            SLASH_EUILOADOUTMANAGER2 = "/loadoutmanager"
            SlashCmdList.EUILOADOUTMANAGER = SlashHandler
            -- Only now do we know whether this character opted in.
            SetEventsEnabled(EllesmereUILoadoutManagerDB.enabled)
            -- Ours is loaded; every later ADDON_LOADED belongs to some other
            -- addon and only costs us a wakeup, so stop listening.
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- (Accent colours resolve per call from the parent now, so there is
        -- nothing to re-sync here.)
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            -- Seed the current context without swapping. This prevents reload/login inside
            -- combat or inside an already-running dungeon from triggering a fresh auto-swap.
            lastAutoInstanceKey = BuildAutoInstanceKey(GetCurrentInstanceContext())
        else
            HandlePossibleInstanceEntry("entering world")
        end
        C_Timer.After(0.3, RequestRefresh)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        HandlePossibleInstanceEntry("zone changed")
        C_Timer.After(0.3, RequestRefresh)
    elseif event == "PLAYER_REGEN_ENABLED" then
        RunQueuedAfterCombat()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if ... == "player" then
            EnsureDB()
            InvalidateTalentCache() -- loadout list is per spec
            ShowSpecChangeWarning("DONT MOVE - CHANGING SPECS", 3)
            UI.selectedTalent = nil
            if EllesmereUILoadoutManagerDB.specSwap then
                -- The auto-key includes the spec, so this re-fires the swap for
                -- the new spec's assignments when it happens inside an instance.
                C_Timer.After(1, function() HandlePossibleInstanceEntry("spec change") end)
            end
            C_Timer.After(0.3, function()
                UI.assignScope = GetCurrentSpecID()
                RequestRefresh()
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
        RequestRefresh()
    end
end)

-- -----------------------------------------------------------------------------
-- Event gating. Switched off the module wants none of these, except
-- PLAYER_REGEN_ENABLED while a swap is still owed to the end of combat --
-- dropping it would strand the queued swap for the session. ADDON_LOADED
-- retires itself. PEW is both a work event (instance entry) and the migration
-- bootstrap, so the migration hook releases it when the module is off and
-- SetEventsEnabled re-registers it on opt-in.
-- -----------------------------------------------------------------------------
local WORK_EVENTS = {
    "PLAYER_ENTERING_WORLD", -- instance entry via loading screen
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_SPECIALIZATION_CHANGED",
    "EQUIPMENT_SETS_CHANGED",
    "EQUIPMENT_SWAP_FINISHED",
    "TRAIT_CONFIG_UPDATED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
    "SELECTED_LOADOUT_CHANGED",
}

local eventsOn = false
local regenOn = false

local function CombatDebtOutstanding()
    return (queuedSetName ~= nil) or (queuedTalent ~= nil)
end

UpdateRegenRegistration = function()
    local want = eventsOn or CombatDebtOutstanding()
    if want == regenOn then return end
    regenOn = want
    if want then
        IGS:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        IGS:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

SetEventsEnabled = function(on)
    on = on and true or false
    if on ~= eventsOn then
        eventsOn = on
        for i = 1, #WORK_EVENTS do
            if on then
                IGS:RegisterEvent(WORK_EVENTS[i])
            else
                IGS:UnregisterEvent(WORK_EVENTS[i])
            end
        end
    end
    UpdateRegenRegistration()
end

-- Bootstrap only. Everything else is registered by SetEventsEnabled once the
-- saved variables are loaded and only if the user has switched the module on.
IGS:RegisterEvent("ADDON_LOADED")
IGS:RegisterEvent("PLAYER_ENTERING_WORLD")


-- -----------------------------------------------------------------------------
-- Module namespace: everything the options page drives
-- -----------------------------------------------------------------------------
ns.INSTANCE_TYPE_ORDER = INSTANCE_TYPE_ORDER

function ns.DB() EnsureDB() return EllesmereUILoadoutManagerDB end

-- Selection + edit scope (the "Assign for" scope and the two pickers)
function ns.GetScope() return UI.assignScope end
function ns.SetScope(specID) UI.assignScope = specID end
function ns.GetSelectedSet() return UI.selectedSet end
function ns.SetSelectedSet(name) UI.selectedSet = name end
function ns.GetSelectedTalent() return UI.selectedTalent end
function ns.SetSelectedTalent(stored) UI.selectedTalent = stored end
function ns.TalentDisplayName(stored) return TalentDisplayName(stored) end
function ns.StoreTalentLoadout(loadout) return StoreTalentLoadout(loadout) end

-- Listings
function ns.GetSpecList() return GetSpecList() end
function ns.SpecName(specID) return SpecName(specID) end
function ns.GetCurrentSpecID() return GetCurrentSpecID() end
function ns.ListEquipmentSets() return ListEquipmentSetsDetailed() end
function ns.ListTalentLoadouts() return ListTalentLoadouts() end

-- Current context and what resolves for it
function ns.GetContext() return GetCurrentInstanceContext() end
function ns.ResolveGear(ctx) return GetAssignedSetForContext(ctx or GetCurrentInstanceContext()) end
function ns.ResolveTalent(ctx) return GetAssignedTalentForContext(ctx or GetCurrentInstanceContext()) end

-- Reads for the settings page
function ns.ReadTables() return GetReadTables() end

-- Actions
function ns.CheckAndSwap(reason) CheckAndSwap(reason or "manual") end
function ns.EquipSelected()
    if UI.selectedSet then TryEquipSet(UI.selectedSet, "manual") end
    if UI.selectedTalent then TryLoadTalentLoadout(UI.selectedTalent, "manual") end
end
function ns.AssignCurrent(includeDifficulty) return AssignCurrentLoadouts(includeDifficulty) end
function ns.ClearCurrent(includeDifficulty) return ClearCurrentLoadouts(includeDifficulty) end
function ns.AssignType(instanceType) return AssignTypeLoadouts(instanceType) end
function ns.ClearType(instanceType) return ClearTypeLoadouts(instanceType) end
function ns.CopyScopeFrom(sourceID) return CopyScopeFrom(sourceID) end

-- The master switch also decides whether the module listens to anything at
-- all, so the options page must route through this rather than writing the
-- saved variable directly.
function ns.SetEnabled(value)
    EnsureDB()
    EllesmereUILoadoutManagerDB.enabled = value and true or false
    SetEventsEnabled(EllesmereUILoadoutManagerDB.enabled)
end
function ns.Verify() VerifyAssignments() end

-- Reset hook for the parent's "Reset ALL EUI Addon Settings"
function ns.ResetAll()
    EllesmereUILoadoutManagerDB = nil
    dbReady = false
    EnsureDB()
    UI.selectedSet, UI.selectedTalent, UI.assignScope = nil, nil, nil
    SetEventsEnabled(EllesmereUILoadoutManagerDB.enabled)
    RequestRefresh()
end

IGS:HookScript("OnEvent", function(self, event)
    if event ~= "PLAYER_ENTERING_WORLD" then return end
    if not eventsOn then
        -- Bootstrap is done and the module is off: stop listening entirely.
        -- SetEventsEnabled re-registers this if the user opts in later.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
