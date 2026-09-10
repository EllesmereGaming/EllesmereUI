if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUILoadoutManager.lua
--
--  Applies Blizzard Equipment Manager gear sets and saved talent loadouts
--  automatically when you enter an instance context, resolved per
--  specialization.
--
--  This file is the engine only: it owns the saved variables, the context
--  resolution, and the swap/verify machinery. The settings surface lives in
--  the LoadOnDemand options addon (EUI_LoadoutManager_Options.lua) and drives
--  everything through the ns API published at the bottom of this file.
--
--  Resolution order, first match wins. Within each level the current spec's
--  assignment is checked before the All Specs layer:
--
--    instance + difficulty  ->  instance  ->  specific type (Mythic+,
--    Timewalking, Delve)  ->  general type  ->  Open World (on exit)
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options file reads this module ns via the registry

local IGS -- created only when automation or an explicit action needs events

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

-- One request per channel. Deferred event work retains request identity so an
-- older operation cannot apply after another selection, reset, or context.
local requests = {}
local REQUEST_KINDS = { "gear", "talent" }
local lastTalentRequest
local FIX_REVISION = "LM-20260906-6"
local MAX_SWAP_RETRIES = 10
local autoCheckSerial = 0
local lastAutoInstanceKey = nil
local GetCurrentSpecID, BuildAutoInstanceKey
local TryEquipSet, TryLoadTalentLoadout, VerifyEquippedSet
local RetryRequest, FinishRequest, CancelRequests, RequestIsCurrent
local HideSpecChangeWarning

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
local function RequestRefresh()
    if not EllesmereUI.GetActiveModule or EllesmereUI:GetActiveModule() ~= ADDON_NAME then return end
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(0, function()
        refreshScheduled = false
        -- The parent fast refresh only updates widget values. Our context
        -- labels and dropdown choices are built once and need a page rebuild.
        if EllesmereUI.GetActiveModule and EllesmereUI.RefreshPage
            and EllesmereUI:GetActiveModule() == ADDON_NAME then
            EllesmereUI:RefreshPage(true)
        elseif ns.OnStateChanged then
            ns.OnStateChanged()
        end
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
HideSpecChangeWarning = function()
    if specChangeWarningFrame then specChangeWarningFrame:Hide() end
end

local function ShowSpecChangeWarning(message)
    EnsureDB()
    if not EllesmereUILoadoutManagerDB.specWarning then return end
    message = message or "DONT MOVE - CHANGING SPECS"

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

-- A populated catalog can prove that a name is missing. An empty catalog is
-- not evidence of readiness; pending lookups wait for equipment/bag events.
local function EquipmentCacheReady(allowEmpty)
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return true end
    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return false end
    if #ids == 0 then return allowEmpty == true end
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
    EnsureDB()
    local listening = EllesmereUILoadoutManagerDB.enabled and EllesmereUILoadoutManagerDB.gearEnabled
    if listening and cacheGearDetailed then return cacheGearDetailed end
    local sets = {}
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return sets end
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then table.insert(sets, { name = name, icon = icon }) end
    end
    table.sort(sets, ByNameAsc)
    -- While automation is off we do not receive catalog events. Read live on
    -- demand, and never keep an empty login cache indefinitely.
    if listening and #sets > 0 then cacheGearDetailed = sets end
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

-- Request lifecycle shared by gear and talents. Automatic requests are tied
-- to a context; explicit button actions also work with automation switched off.
RequestIsCurrent = function(request)
    if not request or requests[request.kind] ~= request then return false end
    local db = EllesmereUILoadoutManagerDB
    if not db or (not request.manual and (not db.enabled
        or not db[request.kind == "gear" and "gearEnabled" or "talentEnabled"])) then
        FinishRequest(request)
        return false
    end
    if request.contextKey ~= BuildAutoInstanceKey(GetCurrentInstanceContext()) then
        FinishRequest(request)
        return false
    end
    return true
end

FinishRequest = function(request)
    if not request or requests[request.kind] ~= request then return end
    requests[request.kind] = nil
    if request.kind == "talent" then
        request.outcome = request.outcome or "cancelled"
        HideSpecChangeWarning()
    end
    UpdateRegenRegistration()
end

CancelRequests = function(automaticOnly)
    autoCheckSerial = autoCheckSerial + 1
    for _, kind in ipairs(REQUEST_KINDS) do
        local request = requests[kind]
        if request and (not automaticOnly or not request.manual) then FinishRequest(request) end
    end
end

local function BeginRequest(kind, value, reason, manual)
    FinishRequest(requests[kind])
    local request = {
        kind = kind, value = value, reason = reason, manual = manual,
        contextKey = BuildAutoInstanceKey(GetCurrentInstanceContext()),
        tries = 0,
    }
    requests[kind] = request
    UpdateRegenRegistration()
    return request
end

local function ScheduleRequest(request, checkOnly)
    if not RequestIsCurrent(request) then return end
    if request.resumeQueued then
        if not checkOnly then request.resumeCheckOnly = false end
        return
    end
    request.resumeQueued, request.resumeCheckOnly = true, checkOnly
    -- Batch one burst of native events after their handlers have unwound.
    -- No elapsed duration decides whether data is ready or a swap succeeded.
    C_Timer.After(0, function()
        local verify = request.resumeCheckOnly
        request.resumeQueued, request.resumeCheckOnly = nil, nil
        if RequestIsCurrent(request) then RetryRequest(request, verify) end
    end)
end

local function DeferRequest(request, message, combat, waitReason)
    if not RequestIsCurrent(request) then return end
    if combat then
        if not EllesmereUILoadoutManagerDB.queueInCombat then
            Announce("In combat. " .. (request.kind == "gear" and "Gear" or "Talent") .. " swap skipped.")
            FinishRequest(request)
            return
        end
        request.waitingCombat = true
    else
        if request.tries >= MAX_SWAP_RETRIES then
            Print(message .. " Retry limit reached; use Check Now when ready.")
            FinishRequest(request)
            return
        end
        request.waitingCombat = nil
    end
    request.waitReason = combat and "combat" or waitReason or "availability"
    if not request.announcedWait then
        request.announcedWait = true
        Announce(message .. (combat and " Queued for after combat." or " Waiting for a game update; Check Now can retry."))
    end
    UpdateRegenRegistration()
end

TryEquipSet = function(request)
    if not RequestIsCurrent(request) then return end
    if request.verifying then return end
    if InActiveKeystone() then
        Print("Keystone active: gear is locked until the run ends. Swap skipped.")
        FinishRequest(request)
        return
    end
    if InCombatLockdown() then
        DeferRequest(request, "In combat.", true)
        return
    end
    request.waitingCombat, request.waitReason = nil, nil

    local setName = Trim(request.value)
    if setName == "" then FinishRequest(request); return end
    local info = GetSetInfoByName(setName)
    if not info then
        if not EquipmentCacheReady() then
            DeferRequest(request, "Equipment sets are not available yet.", false, "catalog")
        else
            Print("Could not find Equipment Manager set named " .. ERRC() .. setName ..
                "|r. It may have been renamed or deleted - use Verify Sets on the settings page to find stale assignments.")
            FinishRequest(request)
        end
        return
    end
    if info.isEquipped then FinishRequest(request); return end

    if info.numLost and info.numLost > 0 then
        Announce("Gear set " .. AC() .. info.name .. "|r has " .. tostring(info.numLost) ..
            " missing item(s) - they may be in the bank or void storage. Equipping the rest.")
    end
    request.setID, request.setName = info.setID, info.name
    request.verifying = true
    request.swapFinished = nil
    request.tries = request.tries + 1
    UpdateRegenRegistration()
    local okCall, result = pcall(C_EquipmentSet.UseEquipmentSet, info.setID)
    if not RequestIsCurrent(request) then return end
    if not okCall or result == false then
        request.verifying = nil
        DeferRequest(request, "Gear swap could not apply " .. AC() .. info.name .. "|r.")
        return
    end
    Announce("Equipping gear " .. AC() .. info.name .. "|r" ..
        (request.reason and (" (" .. request.reason .. ")") or "") .. ".")
    ScheduleRequest(request, true)
end

-- -----------------------------------------------------------------------------
-- Talent loadouts
-- -----------------------------------------------------------------------------

GetCurrentSpecID = function()
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
    EnsureDB()
    local listening = EllesmereUILoadoutManagerDB.enabled and EllesmereUILoadoutManagerDB.talentEnabled
    if listening and cacheTalents and cacheTalentSpec == specID then return cacheTalents end
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
    if listening and #loadouts > 0 then
        cacheTalents, cacheTalentSpec = loadouts, specID
    end
    return loadouts
end

local function GetTalentLoadoutInfoByID(configID)
    configID = tonumber(configID)
    if not configID or not C_Traits or not C_Traits.GetConfigInfo then return nil end
    local specID = GetCurrentSpecID()
    if not specID or not C_ClassTalents or not C_ClassTalents.GetConfigIDsBySpecID then return nil end
    local okIDs, configIDs = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not okIDs or type(configIDs) ~= "table" then return nil end
    local belongsToSpec = false
    for _, id in ipairs(configIDs) do
        if id == configID then belongsToSpec = true; break end
    end
    if not belongsToSpec then return nil end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, configID)
    if not okInfo or not info then return nil end
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
    local currentSpec = GetCurrentSpecID()
    if stored.specID and currentSpec and tonumber(stored.specID) ~= tonumber(currentSpec) then return nil end

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

local function RecordTalentEvent(request, event)
    request.history = request.history or {}
    local history = request.history
    if #history == 10 then table.remove(history, 1) end
    history[#history + 1] = event
end

local function HasStagedTalentChanges(activeID)
    if not activeID or not C_Traits or not C_Traits.ConfigHasStagedChanges then return nil end
    local ok, staged = pcall(C_Traits.ConfigHasStagedChanges, activeID)
    if ok and type(staged) == "boolean" then return staged end
    return nil
end

local function GetTalentSelection(configID)
    if not configID or not C_Traits or not C_Traits.GetConfigInfo
        or not C_Traits.GetTreeNodes or not C_Traits.GetNodeInfo then return nil end
    -- Compare purchased ranks and choices, not serialized export strings or
    -- automatic grants that can differ between a saved and an active config.
    local ok, value = pcall(function()
        local info = C_Traits.GetConfigInfo(configID)
        if not info or type(info.treeIDs) ~= "table" or #info.treeIDs == 0 then return nil end
        local entries, purchased = {}, 0
        for _, treeID in ipairs(info.treeIDs) do
            local nodes = C_Traits.GetTreeNodes(treeID)
            if type(nodes) ~= "table" or #nodes == 0 then return nil end
            entries[#entries + 1] = "tree:" .. tostring(treeID)
            for _, nodeID in ipairs(nodes) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                if not node or type(node.ranksPurchased) ~= "number" then return nil end
                local subTreeChoice = Enum and Enum.TraitNodeType and node.type == Enum.TraitNodeType.SubTreeSelection
                if node.ranksPurchased > 0 or (subTreeChoice and (node.activeRank or 0) > 0) then
                    local entryID = node.activeEntry and node.activeEntry.entryID
                    if not entryID then return nil end
                    entries[#entries + 1] = nodeID .. ":" .. node.ranksPurchased .. ":" .. entryID
                    purchased = purchased + 1
                end
            end
        end
        if purchased == 0 then return nil end -- empty/unpopulated data is not proof
        table.sort(entries)
        return table.concat(entries, ";")
    end)
    return ok and value or nil
end

local function ActiveTalentsMatch(request)
    local activeID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if GetCurrentSpecID() ~= request.specID or HasStagedTalentChanges(activeID) ~= false then return nil end
    local target = request.talentSelection or GetTalentSelection(request.configID)
    local active = GetTalentSelection(activeID)
    if not target or not active then return nil end
    return target == active
end

local function HasUniqueLoadoutName(loadout)
    -- The native command chooses the first case-insensitive name match.
    -- Validate before the load, while its target still belongs to this spec.
    local ok, unique = pcall(function()
        local matches = 0
        for _, configID in ipairs(C_ClassTalents.GetConfigIDsBySpecID(loadout.specID)) do
            local info = C_Traits.GetConfigInfo(configID)
            if not info or not info.name then return false end
            if strcmputf8i(info.name, loadout.name) == 0 then matches = matches + 1 end
        end
        return matches == 1
    end)
    return ok and unique
end

local function CompleteTalentRequest(request, signal)
    if not RequestIsCurrent(request) then return end
    request.outcome = "confirmed: " .. signal
    RecordTalentEvent(request, request.outcome)
    FinishRequest(request)
    -- The native UI started this load and owns its completion/selection.
    -- Loading it again here takes the no-change path and can leave a stale
    -- menu selected. Do not start another operation after confirmation.
    RequestRefresh()
end

local function CheckTalentCompletion(request)
    if not RequestIsCurrent(request) or not request.inFlight or request.callingLoad or request.commitFailed then return end
    local activeID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if not activeID or HasStagedTalentChanges(activeID) == true then return end
    local matches = ActiveTalentsMatch(request)
    -- The UI command has no acceptance result. An unrelated active-config
    -- update alone cannot prove it was accepted when node data is missing.
    if matches == true then
        CompleteTalentRequest(request, request.commitSignal or "matching talent nodes")
    elseif matches == nil and request.commitCastSucceeded and request.commitSignal
        and C_ClassTalents.GetLastSelectedSavedConfigID(request.specID) == request.configID then
        CompleteTalentRequest(request, request.commitSignal)
    end
end

local function TalentCommitUpdated(request, configID)
    if issecretvalue(configID) then return end
    if not RequestIsCurrent(request) or not request.inFlight then return end
    local activeID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    RecordTalentEvent(request, "TRAIT_CONFIG_UPDATED " .. tostring(configID))
    if not activeID or configID ~= activeID then return end
    request.commitSignal = "active configuration update"
    ScheduleRequest(request, true)
end

local function TalentCommitFailed(request, configID)
    if issecretvalue(configID) then return end
    if not RequestIsCurrent(request) or not request.inFlight then return end
    local activeID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if configID and configID ~= activeID and configID ~= request.activeConfigID and configID ~= request.configID then return end
    request.commitFailed = true
    RecordTalentEvent(request, "commit failed")
    if request.callingLoad then return end
    request.inFlight = nil
    HideSpecChangeWarning()
    DeferRequest(request, "Talent change was interrupted.", InCombatLockdown())
end

local function TalentCastEvent(event, unit, castGUID, spellID)
    if issecretvalue(unit) or issecretvalue(castGUID) or issecretvalue(spellID) then return end
    local request = requests.talent
    local traitConsts = Constants and Constants.TraitConsts
    local commitSpellID = traitConsts and traitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID
    if unit ~= "player" or not commitSpellID or spellID ~= commitSpellID
        or not RequestIsCurrent(request) or not request.inFlight then return end
    if castGUID and castGUID == request.supersededCastGUID then return end
    if event == "UNIT_SPELLCAST_START" then
        if request.commitCastGUID and request.commitCastGUID ~= castGUID then
            RecordTalentEvent(request, "superseded by another talent cast")
            FinishRequest(request)
            return
        end
        request.commitCastGUID = castGUID
        request.casting = true
        RecordTalentEvent(request, "talent cast started")
        if not request.callingLoad then ShowSpecChangeWarning("DONT MOVE - CHANGING TALENTS") end
    elseif request.commitCastGUID and request.commitCastGUID == castGUID then
        request.casting = nil
        HideSpecChangeWarning()
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            request.commitCastSucceeded = true
            request.commitSignal = "talent cast succeeded"
            RecordTalentEvent(request, request.commitSignal)
            ScheduleRequest(request, true)
        elseif event == "UNIT_SPELLCAST_STOP" then
            ScheduleRequest(request, true)
        else
            TalentCommitFailed(request)
        end
    end
end

TryLoadTalentLoadout = function(request)
    if not RequestIsCurrent(request) then return end
    if request.inFlight then return end
    if InActiveKeystone() then
        Print("Keystone active: talents are locked until the run ends. Swap skipped.")
        FinishRequest(request)
        return
    end
    local stored = NormalizeTalentStored(request.value)
    if not stored then FinishRequest(request); return end
    if not TalentMatchesSpec(stored, GetCurrentSpecID()) then
        Print("The selected talent loadout belongs to a different specialization. Select a loadout for your current spec.")
        FinishRequest(request)
        return
    end
    if InCombatLockdown() then DeferRequest(request, "In combat.", true); return end
    request.waitingCombat, request.waitReason = nil, nil

    local loadout = GetTalentLoadoutFromStored(stored)
    if not loadout then
        if #ListTalentLoadouts() == 0 then
            DeferRequest(request, "Talent loadouts are not available for your current spec yet.", false, "catalog")
        else
            Print("Could not find the assigned talent loadout for your current spec.")
            FinishRequest(request)
        end
        return
    end
    if not C_ClassTalents or not C_ClassTalents.SwitchToLoadoutByName then
        Print("Talent loadout API is not available on this client.")
        FinishRequest(request)
        return
    end
    if C_ClassTalents.CanEditTalents then
        local okCan, canChange = pcall(C_ClassTalents.CanEditTalents)
        if not okCan or canChange == false then
            DeferRequest(request, "Cannot change talents here yet.")
            return
        end
    end

    if not HasUniqueLoadoutName(loadout) then
        Print("Talent swap skipped: the assigned loadout needs a unique saved name. Check for duplicate names, then use Check Now.")
        FinishRequest(request)
        return
    end

    -- Start through Blizzard's UI-aware command so it records the target
    -- before the commit, including when the panel is closed or not loaded.
    -- LastSelected alone is not proof of the applied build.
    request.configID, request.specID = loadout.configID, loadout.specID
    request.activeConfigID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    request.talentSelection = GetTalentSelection(loadout.configID)
    request.supersededCastGUID = lastTalentRequest and lastTalentRequest.commitCastGUID
    lastTalentRequest = request
    request.outcome, request.displayResult = nil, "native UI load requested"
    RecordTalentEvent(request, "UI load requested: " .. loadout.name .. " (" .. loadout.configID .. ")")
    request.callingLoad, request.inFlight = true, true
    request.commitSignal, request.commitCastGUID, request.commitFailed = nil, nil, nil
    request.commitCastSucceeded = nil
    request.casting = nil
    request.tries = request.tries + 1
    UpdateRegenRegistration()
    local okLoad, loadError = pcall(C_ClassTalents.SwitchToLoadoutByName, loadout.name)
    -- This command has no load-result return. Confirm through native events
    -- and applied-node evidence, never merely because the call returned.
    request.loadResult = okLoad and "no return value" or "API error"
    request.callingLoad = nil
    if not RequestIsCurrent(request) then return end
    if not okLoad or request.commitFailed then
        request.inFlight = nil
        HideSpecChangeWarning()
        if not okLoad then RecordTalentEvent(request, tostring(loadError)) end
        DeferRequest(request, "Could not apply talent loadout " .. ERRC() .. loadout.name .. "|r" ..
            (loadError and (": " .. tostring(loadError)) or "."))
        return
    end
    if request.casting then ShowSpecChangeWarning("DONT MOVE - CHANGING TALENTS") end
    Announce("Requesting talents " .. AC() .. loadout.name .. "|r" ..
        (request.reason and (" (" .. request.reason .. ")") or "") .. ".")
    ScheduleRequest(request, true)
end

RetryRequest = function(request, checkOnly)
    if not RequestIsCurrent(request) then return end
    if request.kind == "gear" and request.verifying then
        VerifyEquippedSet(request)
    elseif request.kind == "talent" and request.inFlight then
        CheckTalentCompletion(request)
    elseif not checkOnly then
        if request.kind == "gear" then TryEquipSet(request) else TryLoadTalentLoadout(request) end
    end
end

-- -----------------------------------------------------------------------------
-- Assignment helpers
-- -----------------------------------------------------------------------------

local function CheckAndSwap(reason, manual)
    EnsureDB()
    if not manual and not EllesmereUILoadoutManagerDB.enabled then return end
    -- This check expresses new intent, including the absence of an assignment.
    -- Cancel an older request before resolving the new context.
    CancelRequests()

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
    if setName and (manual or EllesmereUILoadoutManagerDB.gearEnabled) then
        local label = ctx.name
        if gearSource == "difficulty" then label = ctx.name .. " - " .. tostring(ctx.difficultyName or ctx.difficultyID) end
        if gearSource == "type" then
            label = ctx.inInstance and (tostring(ctx.instanceType) .. " default") or "open world default"
        end
        TryEquipSet(BeginRequest("gear", setName, label, manual))
    end

    local talentStored, talentSource = GetAssignedTalentForContext(ctx)
    if talentStored and (manual or EllesmereUILoadoutManagerDB.talentEnabled) then
        local label = ctx.name
        if talentSource == "difficulty" then label = ctx.name .. " - " .. tostring(ctx.difficultyName or ctx.difficultyID) end
        if talentSource == "type" then
            label = ctx.inInstance and (tostring(ctx.instanceType) .. " default") or "open world default"
        end
        TryLoadTalentLoadout(BeginRequest("talent", StoreTalentLoadout(NormalizeTalentStored(talentStored)), label, manual))
    end
end

local function QueueAutoCheck(reason)
    EnsureDB()
    autoCheckSerial = autoCheckSerial + 1
    local serial = autoCheckSerial
    local contextKey = BuildAutoInstanceKey(GetCurrentInstanceContext())
    C_Timer.After(0, function()
        if serial ~= autoCheckSerial or not EllesmereUILoadoutManagerDB.enabled then return end
        if contextKey ~= BuildAutoInstanceKey(GetCurrentInstanceContext()) then return end
        CheckAndSwap(reason)
    end)
end

BuildAutoInstanceKey = function(ctx)
    if not ctx then return nil end
    if not ctx.inInstance then return "world:" .. tostring(GetCurrentSpecID() or 0) end
    if not ctx.instanceID then return nil end
    return tostring(ctx.instanceType or "none") .. ":" .. tostring(ctx.instanceID) .. ":" ..
        tostring(ctx.difficultyID or 0) .. ":" .. tostring(GetCurrentSpecID() or 0)
end

local function HandlePossibleInstanceEntry(reason)
    EnsureDB()
    local ctx = GetCurrentInstanceContext()
    local key = BuildAutoInstanceKey(ctx)
    if key == lastAutoInstanceKey then return end
    CancelRequests()
    lastAutoInstanceKey = key
    if not key or not EllesmereUILoadoutManagerDB.enabled then return end
    QueueAutoCheck(not ctx.inInstance and "left instance" or reason or "entered instance")
end

VerifyEquippedSet = function(request)
    if not RequestIsCurrent(request) or not request.verifying then return end
    local wanted = request.setName
    local info = GetSetInfoByName(wanted)
    if not request.swapFinished and (not info or not info.isEquipped) then return end
    request.verifying = nil
    FinishRequest(request)
    if not info then return end
    if not info.isEquipped then
        local missing = (tonumber(info.numItems) or 0) - (tonumber(info.numEquipped) or 0)
        if missing > 0 then
            Print("Gear set " .. ERRC() .. wanted .. "|r did not fully equip - " .. missing ..
                " item(s) missing" .. ((info.numLost and info.numLost > 0) and " (check bank/void storage)" or "") .. ".")
        else
            Print("Gear set " .. ERRC() .. wanted .. "|r did not finish equipping. Press Check Now to retry.")
        end
    end
    RequestRefresh()
end

local function ResumeRequests(waitReason)
    for _, kind in ipairs(REQUEST_KINDS) do
        local request = requests[kind]
        if request and (not waitReason or request.waitReason == waitReason) then
            ScheduleRequest(request)
        end
    end
    UpdateRegenRegistration()
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
    if not EquipmentCacheReady(true) then
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
local function PrintTalentDiagnostics()
    local function Read(fn, ...)
        if type(fn) ~= "function" then return "unavailable" end
        local ok, value = pcall(fn, ...)
        if not ok then return "API error" end
        if issecretvalue(value) then return "restricted" end
        return value == nil and "none" or tostring(value)
    end
    local specID = GetCurrentSpecID()
    local talents = C_ClassTalents or {}
    local activeID = talents.GetActiveConfigID and talents.GetActiveConfigID()
    Print("Diagnostic " .. FIX_REVISION .. "; spec=" .. tostring(specID))
    Print("Active=" .. tostring(activeID) .. "; saved selection=" .. Read(talents.GetLastSelectedSavedConfigID, specID))
    -- Read only, on explicit /lm debug. Do not load, show or mutate the UI.
    local panel = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if panel then
        local menu = panel.LoadSystem
        Print("Panel shown=" .. Read(panel.IsShown, panel) .. "; selection=" .. Read(menu and menu.GetSelectionID, menu)
            .. "; committing=" .. Read(panel.IsCommitInProgress, panel) .. "; inspecting=" .. Read(panel.IsInspecting, panel))
    else
        Print("Panel=not loaded")
    end
    local request = requests.talent or lastTalentRequest
    if not request then Print("No talent load attempted this session."); return end
    Print("Target=" .. tostring(request.configID) .. "; result=" .. tostring(request.loadResult)
        .. "; state=" .. (request.outcome or request.waitReason or "pending native confirmation"))
    Print("Staged=" .. tostring(HasStagedTalentChanges(activeID)) .. "; node match=" .. tostring(ActiveTalentsMatch(request))
        .. "; display=" .. tostring(request.displayResult))
    Print("Events: " .. table.concat(request.history or {}, " -> "))
end

local function SlashHandler(msg)
    EnsureDB()
    local cmd, rest = SplitFirst(msg)
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "gui" or cmd == "config" or cmd == "options" then
        if EllesmereUI.ShowModule then
            EllesmereUI:ShowModule(ADDON_NAME)
        end
    elseif cmd == "debug" then
        PrintTalentDiagnostics()
    elseif cmd == "raidwarning" then
        -- Blizzard's orange raid-warning text for the spec-change notice.
        EllesmereUILoadoutManagerDB.raidWarningText = Trim(rest):lower() == "on"
        Print("Blizzard raid-warning text " .. (EllesmereUILoadoutManagerDB.raidWarningText and "enabled" or "disabled") .. ".")
    else
        Print("Settings live on the EllesmereUI panel - " .. AC() .. "/lm|r opens the Loadout Manager page.")
    end
end

local TALENT_CATALOG_EVENTS = {
    TRAIT_CONFIG_UPDATED = true, TRAIT_CONFIG_CREATED = true, TRAIT_CONFIG_DELETED = true,
    TRAIT_CONFIG_LIST_UPDATED = true, ACTIVE_COMBAT_CONFIG_CHANGED = true, SELECTED_LOADOUT_CHANGED = true,
}

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        InvalidateGearCache()
        InvalidateTalentCache()
        local initialLogin, reloading = ...
        if initialLogin or reloading then
            CancelRequests()
            lastAutoInstanceKey = BuildAutoInstanceKey(GetCurrentInstanceContext())
        else
            HandlePossibleInstanceEntry("entering world")
            ResumeRequests()
        end
        RequestRefresh()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        HandlePossibleInstanceEntry("zone changed")
        ResumeRequests("availability")
        RequestRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ResumeRequests()
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideSpecChangeWarning()
    elseif event == "CHALLENGE_MODE_START" then
        CancelRequests()
    elseif event == "PLAYER_STOPPED_MOVING" or event == "PLAYER_UPDATE_RESTING" or event == "UNIT_AURA" then
        ResumeRequests("availability")
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if ... == "player" then
            EnsureDB()
            CancelRequests()
            InvalidateTalentCache()
            UI.selectedTalent = nil
            local ctx = GetCurrentInstanceContext()
            if EllesmereUILoadoutManagerDB.enabled and EllesmereUILoadoutManagerDB.specSwap and ctx.inInstance then
                HandlePossibleInstanceEntry("spec change")
            else
                lastAutoInstanceKey = BuildAutoInstanceKey(ctx)
            end
            UI.assignScope = GetCurrentSpecID()
            RequestRefresh()
        end
    elseif event == "CONFIG_COMMIT_FAILED" then
        TalentCommitFailed(requests.talent, ...)
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        TalentCastEvent(event, ...)
    else
        if event == "EQUIPMENT_SETS_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED"
            or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
            InvalidateGearCache()
            local request = requests.gear
            if request then
                if event == "EQUIPMENT_SWAP_FINISHED" and request.verifying then
                    local _, setID = ...
                    if issecretvalue(setID) then return end
                    if not setID or setID == request.setID then
                        request.swapFinished = true
                        ScheduleRequest(request, true)
                    end
                elseif event ~= "EQUIPMENT_SWAP_FINISHED" and not request.waitingCombat then
                    ScheduleRequest(request)
                end
            end
        end
        if TALENT_CATALOG_EVENTS[event] then
            InvalidateTalentCache()
            local request = requests.talent
            if request then
                if event == "TRAIT_CONFIG_UPDATED" and request.inFlight then
                    TalentCommitUpdated(request, ...)
                elseif event == "TRAIT_CONFIG_DELETED" and ... == request.configID then
                    FinishRequest(request)
                elseif request.inFlight then
                    ScheduleRequest(request, true)
                elseif request.waitReason == "catalog" then
                    ScheduleRequest(request)
                end
            end
        elseif event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_NODE_CHANGED" or event == "TRAIT_TREE_CHANGED" then
            local request = requests.talent
            if request and request.inFlight then ScheduleRequest(request, true) end
        end
        RequestRefresh()
    end
end

local CONTEXT_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_SPECIALIZATION_CHANGED", "CHALLENGE_MODE_START" }
local GEAR_REQUEST_EVENTS = { "EQUIPMENT_SWAP_FINISHED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }
local TALENT_REQUEST_EVENTS = { "CONFIG_COMMIT_FAILED", "PLAYER_TALENT_UPDATE", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CHANGED" }
local TALENT_CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }
local eventsOn = false
local registeredEvents

local function SetEventState(event, wanted, playerOnly)
    wanted = wanted and true or false
    if not IGS then
        if not wanted then return end
        IGS = CreateFrame("Frame")
        IGS:SetScript("OnEvent", OnEvent)
        registeredEvents = {}
    end
    if (registeredEvents[event] or false) == wanted then return end
    registeredEvents[event] = wanted or nil
    if not wanted then
        IGS:UnregisterEvent(event)
    elseif playerOnly then
        IGS:RegisterUnitEvent(event, "player")
    else
        IGS:RegisterEvent(event)
    end
end

UpdateRegenRegistration = function()
    local gear, talent = requests.gear, requests.talent
    local db = EllesmereUILoadoutManagerDB
    local wantWork = eventsOn or gear or talent
    for _, event in ipairs(CONTEXT_EVENTS) do SetEventState(event, wantWork) end
    SetEventState("EQUIPMENT_SETS_CHANGED", (eventsOn and db.gearEnabled) or gear)
    for event in pairs(TALENT_CATALOG_EVENTS) do
        SetEventState(event, (eventsOn and db.talentEnabled) or talent)
    end
    for _, event in ipairs(GEAR_REQUEST_EVENTS) do SetEventState(event, gear) end
    for _, event in ipairs(TALENT_REQUEST_EVENTS) do SetEventState(event, talent) end
    for _, event in ipairs(TALENT_CAST_EVENTS) do SetEventState(event, talent and talent.inFlight, true) end
    SetEventState("PLAYER_REGEN_ENABLED", gear or talent)
    SetEventState("PLAYER_REGEN_DISABLED", talent)
    local availability = (gear and gear.waitReason == "availability") or (talent and talent.waitReason == "availability")
    SetEventState("PLAYER_STOPPED_MOVING", availability)
    SetEventState("PLAYER_UPDATE_RESTING", availability)
    SetEventState("UNIT_AURA", talent and talent.waitReason == "availability", true)
end

SetEventsEnabled = function(on)
    eventsOn = on and true or false
    UpdateRegenRegistration()
end

SLASH_EUILOADOUTMANAGER1 = "/lm"
SLASH_EUILOADOUTMANAGER2 = "/loadoutmanager"
SlashCmdList.EUILOADOUTMANAGER = SlashHandler

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
function ns.CheckAndSwap(reason) CheckAndSwap(reason or "manual", true) end
function ns.EquipSelected()
    EnsureDB()
    CancelRequests()
    if UI.selectedSet then TryEquipSet(BeginRequest("gear", UI.selectedSet, "manual", true)) end
    if UI.selectedTalent then
        TryLoadTalentLoadout(BeginRequest("talent", StoreTalentLoadout(NormalizeTalentStored(UI.selectedTalent)), "manual", true))
    end
end
function ns.AssignCurrent(includeDifficulty) CancelRequests(true); return AssignCurrentLoadouts(includeDifficulty) end
function ns.ClearCurrent(includeDifficulty) CancelRequests(true); return ClearCurrentLoadouts(includeDifficulty) end
function ns.AssignType(instanceType) CancelRequests(true); return AssignTypeLoadouts(instanceType) end
function ns.ClearType(instanceType) CancelRequests(true); return ClearTypeLoadouts(instanceType) end
function ns.CopyScopeFrom(sourceID) CancelRequests(true); return CopyScopeFrom(sourceID) end

-- The master switch also decides whether the module listens to anything at
-- all, so the options page must route through this rather than writing the
-- saved variable directly.
function ns.SetEnabled(value)
    EnsureDB()
    CancelRequests()
    EllesmereUILoadoutManagerDB.enabled = value and true or false
    InvalidateGearCache()
    InvalidateTalentCache()
    if UI.selectedTalent and not TalentMatchesSpec(UI.selectedTalent, GetCurrentSpecID()) then
        UI.selectedTalent = nil
    end
    lastAutoInstanceKey = BuildAutoInstanceKey(GetCurrentInstanceContext())
    SetEventsEnabled(EllesmereUILoadoutManagerDB.enabled)
    RequestRefresh()
end

function ns.SetChannelEnabled(kind, value)
    if kind ~= "gear" and kind ~= "talent" then return end
    EnsureDB()
    EllesmereUILoadoutManagerDB[kind == "gear" and "gearEnabled" or "talentEnabled"] = value and true or false
    local request = requests[kind]
    if not value and request and not request.manual then FinishRequest(request) end
    if kind == "gear" then InvalidateGearCache() else InvalidateTalentCache() end
    UpdateRegenRegistration()
    RequestRefresh()
end

function ns.SetQueueInCombat(value)
    EnsureDB()
    EllesmereUILoadoutManagerDB.queueInCombat = value and true or false
    if not value then
        for _, kind in ipairs(REQUEST_KINDS) do
            local request = requests[kind]
            if request and request.waitingCombat then FinishRequest(request) end
        end
    end
end

function ns.SetSpecWarning(value)
    EnsureDB()
    EllesmereUILoadoutManagerDB.specWarning = value and true or false
    if not value then HideSpecChangeWarning() end
end
function ns.Verify() VerifyAssignments() end

-- Reset hook for the parent's "Reset ALL EUI Addon Settings"
function ns.ResetAll()
    CancelRequests()
    InvalidateGearCache()
    InvalidateTalentCache()
    lastAutoInstanceKey = BuildAutoInstanceKey(GetCurrentInstanceContext())
    EllesmereUILoadoutManagerDB = nil
    dbReady = false
    EnsureDB()
    UI.selectedSet, UI.selectedTalent, UI.assignScope = nil, nil, nil
    SetEventsEnabled(EllesmereUILoadoutManagerDB.enabled)
    RequestRefresh()
end

-- Use the shared startup callback, which creates no module event frame or
-- event registration. Disabled characters do not build the runtime or DB.
EventUtil.ContinueOnVariablesLoaded(function()
    dbReady = false
    if EllesmereUILoadoutManagerDB and EllesmereUILoadoutManagerDB.enabled then
        EnsureDB()
        SetEventsEnabled(true)
    end
end)
