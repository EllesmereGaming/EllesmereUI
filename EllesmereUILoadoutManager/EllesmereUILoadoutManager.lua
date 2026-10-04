if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUILoadoutManager.lua
--  Applies Equipment Manager gear sets and saved talent loadouts when you
--  enter content, per specialization. Engine only: the settings page
--  (EUI_LoadoutManager_Options.lua) drives it through the ns API at the end.
--  First match wins, the current spec before All Specs at each level:
--  instance + difficulty -> instance -> Mythic+ / Timewalking / Delve ->
--  content type -> Open World (on exit).
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.HexColor and EllesmereUI.COLOR_CODES) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options file reads this module ns via the registry

local IGS -- created only when automation or an explicit action needs events

-- Chat colours follow the live EllesmereUI accent.
local function AC() return EllesmereUI.HexColor(EllesmereUI.GetAccentColor()) end
local ERR = EllesmereUI.COLOR_CODES.BAD

local DEFAULTS = {
    -- Off until the user opts in; switching it on is what registers events.
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

-- Chat lines name a type the way the settings page does ("Mythic+ Keystone"),
-- never by its internal key.
local TYPE_LABELS = {}
for _, info in ipairs(INSTANCE_TYPE_ORDER) do TYPE_LABELS[info.key] = info.label end
local function TypeLabel(key) return TYPE_LABELS[key] or tostring(key) end

local SetEventsEnabled -- forward: defined with the event gating at the end
local UpdateRegenRegistration -- forward: same

-- One request per channel. Deferred event work retains request identity so an
-- older operation cannot apply after another selection, reset, or context.
local requests = {}
local REQUEST_KINDS = { "gear", "talent" }
local lastTalentRequest
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

-- Coalesce a burst of events into one refresh of the settings page, and only
-- while that page is open.
local refreshScheduled = false
local function RequestRefresh()
    if EllesmereUI:GetActiveModule() ~= ADDON_NAME then return end
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(0, function()
        refreshScheduled = false
        -- A value refresh repaints the page's live widgets; a forced rebuild
        -- would orphan any menu open on it.
        if ns.OnStateChanged then ns.OnStateChanged() end
    end)
end

-- EllesmereUI's taint-safe print (it mutes itself in raid combat and keys).
local function Print(msg) EllesmereUI.Print(AC() .. "Loadout Manager|r", msg) end

-- Fill defaults once per session; dbReady resets when saved variables load.
local dbReady = false
local function EnsureDB()
    if dbReady and EllesmereUILoadoutManagerDB then return end
    if type(EllesmereUILoadoutManagerDB) ~= "table" then EllesmereUILoadoutManagerDB = {} end
    EllesmereUI.Lite.DeepMergeDefaults(EllesmereUILoadoutManagerDB, DEFAULTS)
    dbReady = true
end

local function Announce(msg)
    if EllesmereUILoadoutManagerDB and EllesmereUILoadoutManagerDB.announce then Print(msg) end
end


-- -----------------------------------------------------------------------------
-- Specialization scopes
-- Assignments live in two layers: per-spec buckets in DB.specDefaults[specID],
-- and the root tables as the "All Specs" layer. UI.assignScope picks which
-- layer the settings page edits (nil = All Specs).
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

-- The spec list is fixed for the session: cache the first non-empty result
-- (it is empty until spec info loads).
local specListCache = nil
local function GetSpecList()
    if specListCache then return specListCache end
    local list = {}
    local _, _, classID = UnitClass("player")
    for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
        local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
        if id and id ~= 0 then list[#list + 1] = { id = id, name = name, icon = icon } end
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
    message = message or "DONT MOVE - CHANGING TALENTS"

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

        -- Styled with the parent's primitives so it follows the active theme.
        local bgc = EllesmereUI.DARK_BG
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(bgc.r, bgc.g, bgc.b, 0.92)
        EllesmereUI.MakeBorder(f, 1, 1, 1, 0.08)
        local font = EllesmereUI.GetFontPath()
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
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    specChangeWarningFrame.accentLine:SetColorTexture(ar, ag, ab, 0.9)
    specChangeWarningFrame.subtitle:SetTextColor(ar, ag, ab, 1)

    specChangeWarningFrame.title:SetText(message)
    specChangeWarningFrame:Show()
end

-- A started key reports Mythic Keystone (8), but entries are at Mythic (23)
-- and swaps are locked mid-run. Read 8 as 23: a slot saved mid-run applies on
-- the next entry, and starting the key is not a change of context.
local function AssignmentDifficulty(difficultyID)
    if difficultyID == 8 then return 23 end
    return difficultyID
end

local function BuildDifficultyKey(instanceID, difficultyID)
    if not instanceID or not difficultyID then return nil end
    return tostring(instanceID) .. ":" .. tostring(AssignmentDifficulty(difficultyID))
end

local function DifficultyName(difficultyID)
    local name = difficultyID and GetDifficultyInfo(difficultyID)
    if name and name ~= "" then return name end
    return "Difficulty " .. tostring(difficultyID)
end

local function InstanceName(instanceID)
    local name = instanceID and GetRealZoneText(instanceID)
    if name and name ~= "" then return name end
    return "Instance " .. tostring(instanceID)
end

-- An instance assignment key ("2657" or "2657:15") as the page shows it:
-- "Nerub-ar Palace (Any Difficulty)" or "Nerub-ar Palace (Heroic Only)".
local function AssignmentLabel(key)
    local instanceID, difficultyID = tostring(key):match("^(%d+):(%d+)$")
    if instanceID then
        return InstanceName(tonumber(instanceID)) .. " (" .. DifficultyName(tonumber(difficultyID)) .. " Only)"
    end
    return InstanceName(tonumber(key)) .. " (Any Difficulty)"
end

-- One reused table: callers consume the result at once and never keep it.
local contextCache = {}
local function GetCurrentInstanceContext()
    local inInstance, instanceType = IsInInstance()
    local name, instanceType2, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    local ctx = contextCache
    ctx.inInstance = inInstance
    ctx.instanceType = instanceType2 or instanceType or "none"
    ctx.name = name or "Unknown"
    ctx.difficultyID = difficultyID
    ctx.difficultyName = difficultyName
    ctx.instanceID = instanceID
    return ctx
end

-- -----------------------------------------------------------------------------
-- Gear sets
-- -----------------------------------------------------------------------------

-- A populated catalog can prove that a name is missing. An empty catalog is
-- not evidence of readiness; pending lookups wait for equipment/bag events.
local function EquipmentCacheReady(allowEmpty)
    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return false end
    if #ids == 0 then return allowEmpty == true end
    -- IDs present but names not yet populated is also "warming up"
    local name = C_EquipmentSet.GetEquipmentSetInfo(ids[1])
    return name ~= nil
end

local function GetEquipmentSetIDByName(setName)
    if not setName or setName == "" then return nil end

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
    local _, _, _, isEquipped, numItems, numEquipped, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return { setID = setID, name = canonicalName, isEquipped = isEquipped,
             numItems = numItems, numEquipped = numEquipped, numLost = numLost }
end

local function ByNameAsc(a, b) return a.name < b.name end
local function ByNameLowerAsc(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end

-- Read live: only the settings page lists sets, and only while it is open.
local function ListEquipmentSetsDetailed()
    local sets = {}
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then table.insert(sets, { name = name, icon = icon }) end
    end
    table.sort(sets, ByNameAsc)
    return sets
end

local function SetExists(setName)
    return GetEquipmentSetIDByName(setName) ~= nil
end

local GetAssignedSetForContext -- defined after GetCurrentSpecID (spec-aware)

local function InActiveKeystone()
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    return ok and active == true
end

local function RestrictionActive(kind)
    local restriction = Enum.AddOnRestrictionType[kind]
    return restriction ~= nil and C_RestrictedActions.IsAddOnRestrictionActive(restriction)
end

-- SwitchToLoadoutByName is flagged as restricted, so the talent load waits out
-- the add-on restrictions below. Map is not one of them: Midnight raids,
-- dungeons and arenas keep it up, and the load works there (tested on the
-- live client). Combat is last because it only lags the end of lockdown.
local SWAP_RESTRICTIONS = { "PvPMatch", "Encounter", "Combat" }
local RESTRICTION_TEXT = { Encounter = "during this encounter",
    PvPMatch = "while a PvP match clears", Combat = "right after combat" }

-- An arena or battleground keeps the PvP match restriction up in the
-- preparation area too, where the load works (tested on the live client);
-- once the match is under way talents stay locked until it is over.
local function PvPMatchBlock()
    local instanceType = GetCurrentInstanceContext().instanceType
    if instanceType ~= "arena" and instanceType ~= "pvp" then return "PvPMatch" end
    if C_PvP.GetActiveMatchState() >= Enum.PvPMatchState.Engaged then return "match" end
end

-- The first reason a talent load cannot start now. Cheap checks only: the
-- talent tree is never read while one of them holds.
local function TalentLoadBlocker()
    if InActiveKeystone() or RestrictionActive("ChallengeMode") then return "keystone" end
    if InCombatLockdown() then return "combat" end
    if UnitIsDeadOrGhost("player") then return "dead" end
    for i = 1, #SWAP_RESTRICTIONS do
        local kind = SWAP_RESTRICTIONS[i]
        if RestrictionActive(kind) then
            local block = kind
            if kind == "PvPMatch" then block = PvPMatchBlock() end
            if block then return block end
        end
    end
    local ok, canEdit = pcall(C_ClassTalents.CanEditTalents)
    if not ok or canEdit == false then return "edit" end
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
    if request.kind == "talent" then HideSpecChangeWarning() end
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

-- quiet: announce no wait (automatic swaps held while you are dead, short
-- restrictions, a talent loadout most likely in place). A request that
-- announced an earlier wait still says when it gives up.
local function DeferRequest(request, message, combat, waitReason, quiet)
    if not RequestIsCurrent(request) then return end
    local silent = quiet and not (request.announcedWait or request.announcedCombat)
    -- Queue In Combat off drops a swap that comes due in combat, but not one
    -- waiting out a restriction: an encounter usually ends in combat.
    if combat and not EllesmereUILoadoutManagerDB.queueInCombat and request.waitReason ~= "restricted" then
        if not silent then Announce("In combat. " .. (request.kind == "gear" and "Gear" or "Talent") .. " swap skipped.") end
        FinishRequest(request)
        return
    end
    -- Every wake-up spends one try (RetryRequest), so a wait cannot retry forever.
    if request.tries >= MAX_SWAP_RETRIES then
        if not silent then Print(message .. " Retry limit reached; use Check Now when ready.") end
        FinishRequest(request)
        return
    end
    request.waitReason = combat and "combat" or waitReason or "availability"
    -- One line per kind of wait. Combat lines can be muted (EllesmereUI.Print
    -- in raid combat) and quiet waits print nothing; neither may swallow a
    -- later wait's line.
    local flag = combat and "announcedCombat" or "announcedWait"
    if not request[flag] and not quiet then
        request[flag] = true
        Announce(message .. (combat and " Queued for after combat."
            or request.waitReason == "alive" and (request.kind == "gear" and " Gear" or " Talent") .. " swap waits until you are alive."
            or request.waitReason == "restricted" and " The swap waits until they are allowed again."
            or " Waiting for a game update; Check Now can retry."))
    end
    UpdateRegenRegistration()
end

TryEquipSet = function(request)
    if not RequestIsCurrent(request) then return end
    if request.verifying then return end

    local setName = strtrim(tostring(request.value or ""))
    if setName == "" then FinishRequest(request); return end
    local info = GetSetInfoByName(setName)
    if not info then
        if not EquipmentCacheReady() then
            DeferRequest(request, "Equipment sets are not available yet.", false, "catalog")
        else
            Print("Could not find Equipment Manager set named " .. ERR .. setName ..
                "|r. It may have been renamed or deleted - Verify Assigned Sets (the Gear Set cog) finds stale assignments.")
            FinishRequest(request)
        end
        return
    end
    -- Already worn: nothing to do, and nothing to wait for. Automatic checks
    -- stay quiet (most entries need no change); a button press says so.
    if info.isEquipped then
        if request.manual then Print("Gear set " .. AC() .. info.name .. "|r is already equipped.") end
        FinishRequest(request)
        return
    end
    if InActiveKeystone() then FinishRequest(request) return end -- gear is locked mid-key
    if InCombatLockdown() then
        DeferRequest(request, "In combat.", true)
        return
    end
    if UnitIsDeadOrGhost("player") then
        DeferRequest(request, "You are dead.", false, "alive", not request.manual)
        return
    end
    request.waitReason = nil

    if info.numLost and info.numLost > 0 then
        Announce("Gear set " .. AC() .. info.name .. "|r has " .. tostring(info.numLost) ..
            " missing item(s) - they may be in the bank or void storage. Equipping the rest.")
    end
    request.setID, request.setName = info.setID, info.name
    request.verifying = true
    request.swapFinished = nil
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

-- The spec info call reports 0, not nil, for a slot with no specialization.
GetCurrentSpecID = function()
    local specID = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())
    if specID and specID ~= 0 then return specID end
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
    local loadouts = {}
    if not specID then return loadouts end

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
    return loadouts
end

local function GetTalentLoadoutInfoByID(configID)
    configID = tonumber(configID)
    if not configID then return nil end
    local specID = GetCurrentSpecID()
    if not specID then return nil end
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
local DELVE_DIFFICULTIES = { [208] = true }                    -- Delves

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
    local DB = EllesmereUILoadoutManagerDB
    local specID = GetCurrentSpecID()
    local spec = specID and DB.specDefaults[specID] or nil
    local candidates = {}
    if ctx.inInstance then
        if not ctx.instanceID then return nil, "missing-instance-id" end
        local instanceKey = tostring(ctx.instanceID)
        local diffKey = BuildDifficultyKey(ctx.instanceID, ctx.difficultyID)
        candidates = {
            { spec and spec[kDiff], diffKey, "difficulty", specID },
            { DB[kDiff], diffKey, "difficulty", nil },
            { spec and spec[kInst], instanceKey, "instance", specID },
            { DB[kInst], instanceKey, "instance", nil },
        }
    end
    -- Type keys, most specific first; outside an instance that is just "world".
    for _, key in ipairs(TypeKeysForContext(ctx)) do
        candidates[#candidates + 1] = { spec and spec[kType], key, "type", specID }
        candidates[#candidates + 1] = { DB[kType], key, "type", nil }
    end
    for i = 1, #candidates do
        local c = candidates[i]
        local value = c[1] and c[2] and c[1][c[2]]
        if value and (not validator or validator(value, specID)) then
            return value, c[3], c[2], c[4]
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

local function HasStagedTalentChanges(activeID)
    if not activeID then return nil end
    local ok, staged = pcall(C_Traits.ConfigHasStagedChanges, activeID)
    if ok and type(staged) == "boolean" then return staged end
    return nil
end

local function GetTalentSelection(configID)
    if not configID then return nil end
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
                local subTreeChoice = node.type == Enum.TraitNodeType.SubTreeSelection
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
    local activeID = C_ClassTalents.GetActiveConfigID()
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

local function CompleteTalentRequest(request)
    if not RequestIsCurrent(request) then return end
    FinishRequest(request)
    -- The native UI started this load and owns its completion/selection.
    -- Loading it again here takes the no-change path and can leave a stale
    -- menu selected. Do not start another operation after confirmation.
    RequestRefresh()
end

local function CheckTalentCompletion(request)
    if not RequestIsCurrent(request) or not request.inFlight or request.callingLoad or request.commitFailed then return end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if not activeID or HasStagedTalentChanges(activeID) == true then return end
    local matches = ActiveTalentsMatch(request)
    -- The UI command has no acceptance result. An unrelated active-config
    -- update alone cannot prove it was accepted when node data is missing.
    if matches == true then
        CompleteTalentRequest(request)
    elseif matches == nil and request.commitCastSucceeded and request.commitSignal
        and C_ClassTalents.GetLastSelectedSavedConfigID(request.specID) == request.configID then
        CompleteTalentRequest(request)
    end
end

local function TalentCommitUpdated(request, configID)
    if issecretvalue(configID) then return end
    if not RequestIsCurrent(request) or not request.inFlight then return end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if not activeID or configID ~= activeID then return end
    request.commitSignal = "active configuration update"
    ScheduleRequest(request, true)
end

local function TalentCommitFailed(request, configID)
    if issecretvalue(configID) then return end
    if not RequestIsCurrent(request) or not request.inFlight then return end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if configID and configID ~= activeID and configID ~= request.activeConfigID and configID ~= request.configID then return end
    request.commitFailed = true
    if request.callingLoad then return end
    request.inFlight = nil
    HideSpecChangeWarning()
    DeferRequest(request, "Talent change was interrupted.", InCombatLockdown())
end

local function TalentCastEvent(event, unit, castGUID, spellID)
    if issecretvalue(unit) or issecretvalue(castGUID) or issecretvalue(spellID) then return end
    local request = requests.talent
    if unit ~= "player" or spellID ~= Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID
        or not RequestIsCurrent(request) or not request.inFlight then return end
    if castGUID and castGUID == request.supersededCastGUID then return end
    if event == "UNIT_SPELLCAST_START" then
        if request.commitCastGUID and request.commitCastGUID ~= castGUID then
            FinishRequest(request)
            return
        end
        request.commitCastGUID = castGUID
        request.casting = true
        if not request.callingLoad then ShowSpecChangeWarning("DONT MOVE - CHANGING TALENTS") end
    elseif request.commitCastGUID and request.commitCastGUID == castGUID then
        request.casting = nil
        HideSpecChangeWarning()
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            request.commitCastSucceeded = true
            request.commitSignal = "talent cast succeeded"
            ScheduleRequest(request, true)
        elseif event == "UNIT_SPELLCAST_STOP" then
            ScheduleRequest(request, true)
        else
            TalentCommitFailed(request)
        end
    end
end

-- Holds (or drops) a talent request that TalentLoadBlocker stopped.
-- quiet: the loadout is most likely in place already, so say nothing.
local function HoldTalentRequest(request, blocker, quiet)
    if blocker == "match" then
        -- Locked until the match is over: a load on the scoreboard helps no one.
        if not quiet then Announce("Talent changes are locked once a PvP match starts. Talent swap skipped.") end
        FinishRequest(request)
    elseif blocker == "combat" then
        DeferRequest(request, "In combat.", true, nil, quiet)
    elseif blocker == "dead" then
        DeferRequest(request, "You are dead.", false, "alive", quiet or not request.manual)
    elseif blocker == "edit" then
        DeferRequest(request, "Cannot change talents here yet.", false, nil, quiet)
    else
        -- A restriction: resume when it lifts. The Combat one outlasts
        -- lockdown by moments, and a PvP match outside its arena or
        -- battleground is clearing, so neither announces its wait.
        request.restriction = blocker
        DeferRequest(request, "Talent changes are blocked " .. RESTRICTION_TEXT[blocker] .. ".", false, "restricted",
            quiet or blocker == "Combat" or blocker == "PvPMatch")
    end
end

TryLoadTalentLoadout = function(request)
    if not RequestIsCurrent(request) then return end
    if request.inFlight then return end
    local stored = NormalizeTalentStored(request.value)
    if not stored then FinishRequest(request); return end
    if not TalentMatchesSpec(stored, GetCurrentSpecID()) then
        Print("The selected talent loadout belongs to a different specialization. Select a loadout for your current spec.")
        FinishRequest(request)
        return
    end
    local blocker = TalentLoadBlocker()
    if blocker == "keystone" then FinishRequest(request) return end -- talents are locked for the whole run

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
    request.configID, request.specID = loadout.configID, loadout.specID
    local selected = C_ClassTalents.GetLastSelectedSavedConfigID(loadout.specID) == loadout.configID
    if blocker then
        -- Nothing reads the talent tree while a check blocks the load. A
        -- selected loadout is most likely in place already, so an automatic
        -- swap holds it without a word; the comparison below settles it.
        HoldTalentRequest(request, blocker, selected and not request.manual)
        return
    end
    request.waitReason, request.restriction = nil, nil

    -- Already applied (selected, and its talents match the live build): like
    -- a worn gear set, nothing to load; only a button press says so.
    request.talentSelection = nil
    if selected then
        request.talentSelection = GetTalentSelection(loadout.configID)
        if ActiveTalentsMatch(request) == true then
            if request.manual then Print("Talent loadout " .. AC() .. loadout.name .. "|r is already active.") end
            FinishRequest(request)
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
    request.activeConfigID = C_ClassTalents.GetActiveConfigID()
    request.talentSelection = request.talentSelection or GetTalentSelection(loadout.configID)
    request.supersededCastGUID = lastTalentRequest and lastTalentRequest.commitCastGUID
    lastTalentRequest = request
    request.callingLoad, request.inFlight = true, true
    request.commitSignal, request.commitCastGUID, request.commitFailed = nil, nil, nil
    request.commitCastSucceeded = nil
    request.casting = nil
    UpdateRegenRegistration()
    local okLoad, loadError = pcall(C_ClassTalents.SwitchToLoadoutByName, loadout.name)
    -- This command has no load-result return. Confirm through native events
    -- and applied-node evidence, never merely because the call returned.
    request.callingLoad = nil
    if not RequestIsCurrent(request) then return end
    if not okLoad or request.commitFailed then
        request.inFlight = nil
        HideSpecChangeWarning()
        DeferRequest(request, "Could not apply talent loadout " .. ERR .. loadout.name .. "|r" ..
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
        -- Each wake-up of a waiting swap spends one try (see DeferRequest).
        request.tries = request.tries + 1
        if request.kind == "gear" then TryEquipSet(request) else TryLoadTalentLoadout(request) end
    end
end

-- -----------------------------------------------------------------------------
-- Assignment helpers
-- -----------------------------------------------------------------------------

-- Where a resolved assignment came from, for the swap's chat line:
-- "Nerub-ar Palace", "Nerub-ar Palace, Heroic" or "Mythic+ Keystone default".
local function SourceLabel(ctx, source, key)
    if source == "type" then return TypeLabel(key) .. " default" end
    if source == "difficulty" then
        return ctx.name .. ", " .. DifficultyName(AssignmentDifficulty(ctx.difficultyID))
    end
    return ctx.name
end

local function CheckAndSwap(reason, manual)
    EnsureDB()
    local db = EllesmereUILoadoutManagerDB
    if not manual and not db.enabled then return end
    -- This check expresses new intent, including the absence of an assignment.
    -- Cancel an older request before resolving the new context.
    CancelRequests()

    if InActiveKeystone() then return end -- gear and talents are locked mid-key

    local ctx = GetCurrentInstanceContext()
    local setName, gearSource, gearKey = GetAssignedSetForContext(ctx)
    local talentStored, talentSource, talentKey = GetAssignedTalentForContext(ctx)
    if not (manual or db.gearEnabled) then setName = nil end
    if not (manual or db.talentEnabled) then talentStored = nil end
    if not setName and not talentStored then
        -- Automatic checks stay silent (most places have nothing assigned,
        -- and outside instances only an Open World default applies).
        if manual then
            Print("Nothing is assigned for " .. (ctx.inInstance and ctx.name or "the open world") .. ".")
        end
        return
    end

    if setName then
        TryEquipSet(BeginRequest("gear", setName, SourceLabel(ctx, gearSource, gearKey), manual))
    end
    if talentStored then
        TryLoadTalentLoadout(BeginRequest("talent", StoreTalentLoadout(NormalizeTalentStored(talentStored)),
            SourceLabel(ctx, talentSource, talentKey), manual))
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
        tostring(AssignmentDifficulty(ctx.difficultyID) or 0) .. ":" .. tostring(GetCurrentSpecID() or 0)
end

local function HandlePossibleInstanceEntry(reason)
    EnsureDB()
    local ctx = GetCurrentInstanceContext()
    local key = BuildAutoInstanceKey(ctx)
    if key == lastAutoInstanceKey then return end
    lastAutoInstanceKey = key
    -- Switched off, only button presses run, and RequestIsCurrent already
    -- drops one whose context changed; the untracked key proves nothing.
    if not EllesmereUILoadoutManagerDB.enabled then return end
    CancelRequests()
    if not key then return end
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
            Print("Gear set " .. ERR .. wanted .. "|r did not fully equip - " .. missing ..
                " item(s) missing" .. ((info.numLost and info.numLost > 0) and " (check bank/void storage)" or "") .. ".")
        else
            Print("Gear set " .. ERR .. wanted .. "|r did not finish equipping. Press Check Now to retry.")
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

-- One assignment slot for chat: "Holy Raid / Elle Raid", "Holy Raid / no talents".
local function PairText(gear, talentStored)
    return tostring(gear or "no gear") .. " / " .. tostring(TalentDisplayName(talentStored) or "no talents")
end

-- One slot's tables in the scope being edited: a type default, an instance
-- ("2657") or an instance on one difficulty ("2657:15").
local function SlotTables(key, isType)
    EnsureDB()
    local W, scopeID = GetWriteTables()
    if isType then return W.typeDefaults, W.talentTypeDefaults, scopeID end
    if tostring(key):find(":", 1, true) then return W.difficultySets, W.talentDifficultySets, scopeID end
    return W.instanceSets, W.talentInstanceSets, scopeID
end

-- Save the selected set and loadout into one slot. label names it in chat.
local function SaveSlot(key, isType, label)
    local gTbl, tTbl, scopeID = SlotTables(key, isType)
    local changed = false
    if UI.selectedSet and SetExists(UI.selectedSet) then
        gTbl[key] = UI.selectedSet
        changed = true
    end
    if UI.selectedTalent and TalentExists(UI.selectedTalent) then
        local stored = StoreTalentLoadout(UI.selectedTalent)
        if scopeID and stored.specID and tonumber(stored.specID) ~= tonumber(scopeID) then
            Print("Skipped talents: " .. AC() .. tostring(stored.name) .. "|r belongs to " .. tostring(SpecName(stored.specID)) ..
                ". Switch specs to assign " .. tostring(SpecName(scopeID)) .. " talents.")
        else
            tTbl[key] = stored
            changed = true
        end
    end
    if changed then
        Print(label:gsub("^%l", string.upper) .. ScopeSuffix(scopeID) .. " now uses " .. AC() .. PairText(gTbl[key], tTbl[key]) .. "|r.")
    else
        Print("Nothing selected to assign.")
    end
    return changed
end

local function ClearSlot(key, isType, label)
    local gTbl, tTbl, scopeID = SlotTables(key, isType)
    local oldG, oldT = gTbl[key], tTbl[key]
    if oldG == nil and oldT == nil then return false end
    gTbl[key], tTbl[key] = nil, nil
    Print("Cleared " .. label .. ScopeSuffix(scopeID) .. " (was " .. PairText(oldG, oldT) .. ").")
    return true
end

-- This instance's slot key, or nil (with a chat line) outside an instance.
local function CurrentInstanceKey(perDifficulty)
    local ctx = GetCurrentInstanceContext()
    if not ctx.inInstance or not ctx.instanceID then
        Print("You are not inside a dungeon, raid or other instance.")
        return nil
    end
    return perDifficulty and BuildDifficultyKey(ctx.instanceID, ctx.difficultyID) or tostring(ctx.instanceID)
end

-- Every instance assignment in the scope being edited, sorted by name, for
-- the settings page's Saved Instances list: { key, label, gear, talent }.
local function ListInstanceAssignments()
    local R = GetReadTables()
    local list, byKey = {}, {}
    local function Add(tbl, field)
        for key, value in pairs(tbl or {}) do
            local entry = byKey[key]
            if not entry then
                entry = { key = key, label = AssignmentLabel(key) }
                byKey[key] = entry
                list[#list + 1] = entry
            end
            entry[field] = value
        end
    end
    Add(R.instanceSets, "gear")
    Add(R.talentInstanceSets, "talent")
    Add(R.difficultySets, "gear")
    Add(R.talentDifficultySets, "talent")
    table.sort(list, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

-- -----------------------------------------------------------------------------
-- Slash commands and events
-- -----------------------------------------------------------------------------

-- List every assignment pointing at an Equipment Manager set that no longer
-- exists. Driven by Verify Assigned Sets on the settings page's Gear Set cog.
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
                    local where = key == "typeDefaults" and (TypeLabel(mapKey) .. " default") or AssignmentLabel(mapKey)
                    EllesmereUI.Print("  " .. ERR .. setName .. "|r - " .. where .. ", " .. scopeName)
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
        Print(problems .. " assignment(s) point to missing gear sets (listed above). Reassign or clear them: "
            .. "content type defaults on their own rows, instances under Saved Instances.")
    end
end

local TALENT_CATALOG_EVENTS = {
    TRAIT_CONFIG_UPDATED = true, TRAIT_CONFIG_CREATED = true, TRAIT_CONFIG_DELETED = true,
    TRAIT_CONFIG_LIST_UPDATED = true, ACTIVE_COMBAT_CONFIG_CHANGED = true, SELECTED_LOADOUT_CHANGED = true,
}

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
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
        ResumeRequests("combat")
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideSpecChangeWarning()
    elseif event == "CHALLENGE_MODE_START" then
        CancelRequests()
    elseif event == "PLAYER_STOPPED_MOVING" or event == "PLAYER_UPDATE_RESTING" then
        ResumeRequests("availability")
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- Only the lift of the restriction the talent swap waits on resumes
        -- it. The probe reads false during this dispatch, so the re-check
        -- runs next frame.
        local restriction, state = ...
        local request = requests.talent
        if not request or issecretvalue(restriction) or issecretvalue(state) then return end
        if request.waitReason == "restricted" and state == Enum.AddOnRestrictionState.Inactive
            and restriction == Enum.AddOnRestrictionType[request.restriction] then
            ScheduleRequest(request)
        end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        -- PLAYER_ALIVE also fires on release, when you are still a ghost.
        if not UnitIsDeadOrGhost("player") then ResumeRequests("alive") end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- It also fires without a spec change (entering an arena, for one);
        -- only a real change, which changes the context key, cancels a
        -- pending check and re-runs it.
        if ... == "player" and BuildAutoInstanceKey(GetCurrentInstanceContext()) ~= lastAutoInstanceKey then
            EnsureDB()
            CancelRequests()
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
            local request = requests.gear
            if request then
                if event == "EQUIPMENT_SWAP_FINISHED" and request.verifying then
                    local _, setID = ...
                    if issecretvalue(setID) then return end
                    if not setID or setID == request.setID then
                        request.swapFinished = true
                        ScheduleRequest(request, true)
                    end
                elseif event ~= "EQUIPMENT_SWAP_FINISHED" and (request.verifying
                    or request.waitReason == "catalog" or request.waitReason == "availability") then
                    -- Combat and resurrection waits have their own wake-up event.
                    ScheduleRequest(request)
                end
            end
        end
        if TALENT_CATALOG_EVENTS[event] then
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
    SetEventState("ADDON_RESTRICTION_STATE_CHANGED", talent and talent.waitReason == "restricted")
    local alive = (gear and gear.waitReason == "alive") or (talent and talent.waitReason == "alive")
    SetEventState("PLAYER_ALIVE", alive)
    SetEventState("PLAYER_UNGHOST", alive)
end

SetEventsEnabled = function(on)
    eventsOn = on and true or false
    UpdateRegenRegistration()
end

-- Every setting lives on the settings page; /lm opens it.
SLASH_EUILOADOUTMANAGER1 = "/lm"
SlashCmdList.EUILOADOUTMANAGER = function() EllesmereUI:ShowModule(ADDON_NAME) end

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
function ns.ListInstanceAssignments() return ListInstanceAssignments() end
-- The key this instance's assignments are stored under (nil outside one),
-- and the name of the difficulty a per-difficulty assignment here covers.
function ns.AssignmentKey(ctx, perDifficulty)
    ctx = ctx or GetCurrentInstanceContext()
    if not ctx.inInstance or not ctx.instanceID then return nil end
    if perDifficulty then return BuildDifficultyKey(ctx.instanceID, ctx.difficultyID) end
    return tostring(ctx.instanceID)
end
function ns.DifficultyName(ctx)
    ctx = ctx or GetCurrentInstanceContext()
    return DifficultyName(AssignmentDifficulty(ctx.difficultyID))
end

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
function ns.AssignCurrent(perDifficulty)
    CancelRequests(true)
    local key = CurrentInstanceKey(perDifficulty)
    return key ~= nil and SaveSlot(key, false, AssignmentLabel(key))
end
function ns.ClearCurrent(perDifficulty)
    CancelRequests(true)
    local key = CurrentInstanceKey(perDifficulty)
    return key ~= nil and ClearSlot(key, false, AssignmentLabel(key))
end
function ns.ClearInstanceAssignment(key) CancelRequests(true); return ClearSlot(key, false, AssignmentLabel(key)) end
function ns.AssignType(key) CancelRequests(true); return SaveSlot(key, true, "the " .. TypeLabel(key) .. " default") end
function ns.ClearType(key) CancelRequests(true); return ClearSlot(key, true, "the " .. TypeLabel(key) .. " default") end
function ns.CopyScopeFrom(sourceID) CancelRequests(true); return CopyScopeFrom(sourceID) end

-- The master switch also decides which events are registered: route through here.
function ns.SetEnabled(value)
    EnsureDB()
    CancelRequests()
    EllesmereUILoadoutManagerDB.enabled = value and true or false
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
    UpdateRegenRegistration()
    RequestRefresh()
end

function ns.SetQueueInCombat(value)
    EnsureDB()
    EllesmereUILoadoutManagerDB.queueInCombat = value and true or false
    if not value then
        for _, kind in ipairs(REQUEST_KINDS) do
            local request = requests[kind]
            if request and request.waitReason == "combat" then FinishRequest(request) end
        end
    end
end

function ns.SetSpecWarning(value)
    EnsureDB()
    EllesmereUILoadoutManagerDB.specWarning = value and true or false
    if not value then HideSpecChangeWarning() end
end
function ns.Verify() VerifyAssignments() end

-- Reset hook for the page's Reset button (onReset)
function ns.ResetAll()
    CancelRequests()
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
