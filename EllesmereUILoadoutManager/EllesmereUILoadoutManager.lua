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
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.HexColor and EllesmereUI.COLOR_CODES and EllesmereUI.NewCombatQueue and EllesmereUI.ApplyModuleFont and EllesmereUI.HELD_BACK_ADDONS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
-- Held back from this release (EllesmereUI.HELD_BACK_ADDONS): nothing runs,
-- and with no namespace published the options page never registers.
if EllesmereUI.HELD_BACK_ADDONS[ADDON_NAME] then return end
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options file reads this module ns via the registry

-- Both frames are born here, so their work bills this addon, and both stay
-- inert while the module is off: the event frame registers events only for
-- live automation, a pending swap or the open settings page, and the combat
-- queue only while it holds a swap.
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))
local CombatQueue = ns.CombatQueue
local eventFrame = CreateFrame("Frame")
local LM = EllesmereUI.Lite.NewAddon(ADDON_NAME)

-- Chat colours follow the live EllesmereUI accent.
local function AC() return EllesmereUI.HexColor(EllesmereUI.GetAccentColor()) end
local ERR = EllesmereUI.COLOR_CODES.BAD
local function Hi(text) return AC() .. tostring(text) .. "|r" end
local function Bad(text) return ERR .. tostring(text) .. "|r" end
local NO_ENTRIES = {} -- read-only stand-in for a missing table in a loop

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
    specSwap = true,     -- re-run swaps when your specialization changes inside an instance
    specWarning = true,  -- the DON'T MOVE panel while a talent loadout loads
}

-- Labels are the settings page's English row text; its widgets translate them.
local INSTANCE_TYPE_ORDER = {
    { key = "world", label = "Open World" },
    { key = "party", label = "Dungeon / Party" },
    { key = "mplus", label = "Mythic+ Keystone" },
    { key = "timewalking", label = "Timewalking" },
    { key = "delve", label = "Delve" },
    { key = "raid", label = "Raid" },
    { key = "scenario", label = "Scenario" },
    { key = "arena", label = "Arena" },
    { key = "pvp", label = "Battleground / PvP" },
}

-- Chat lines name a type the way the settings page does ("Mythic+ Keystone"),
-- never by its internal key.
local TYPE_LABELS = {}
for _, info in ipairs(INSTANCE_TYPE_ORDER) do TYPE_LABELS[info.key] = info.label end
local function TypeLabel(key) return EllesmereUI.L(TYPE_LABELS[key] or tostring(key)) end

local UpdateRequestEvents -- forward: the event gating near the end
local TryEquipSet, TryLoadTalentLoadout, VerifyEquippedSet, CheckTalentCompletion
local RetryRequest, FinishRequest, CancelRequests, RequestIsCurrent
local HideSpecChangeWarning

-- One request per channel. Deferred event work keeps the request identity,
-- so an older operation cannot apply after another selection, reset, or
-- context.
local requests = {}
local REQUEST_KINDS = { "gear", "talent" }
local lastTalentRequest
local MAX_SWAP_RETRIES = 10
local autoCheckSerial = 0
-- The place (an instance on a difficulty, or the open world) and the spec
-- automation last saw: a new place is an entry, a new spec a spec change.
local lastPlaceKey, lastSpecID
-- True while the settings page is on screen (ns.SetPageShown).
local pageShown = false
-- Bumped by every assignment write and scope change (the page's list memo).
local assignVersion = 0

-- Selection + edit scope shared with the options page (the page reads and
-- writes these through the ns API rather than owning any state itself).
local UI = {
    selectedSet = nil,
    selectedTalent = nil,
    assignScope = nil, -- nil = All Specs layer, where every session starts; otherwise a specID
}

-- The saved table. Reading never creates it, so a character that never
-- changes a setting keeps none: reads fall back to DEFAULTS, which nothing
-- writes. Defaults are merged once into each table the global holds.
local mergedDB
local function EnsureDB()
    local db = EllesmereUILoadoutManagerDB
    if db ~= nil and db == mergedDB then return db end
    if type(db) ~= "table" then
        db = {}
        EllesmereUILoadoutManagerDB = db
    end
    EllesmereUI.Lite.DeepMergeDefaults(db, DEFAULTS)
    mergedDB = db
    return db
end

local function ReadDB()
    if type(EllesmereUILoadoutManagerDB) ~= "table" then return DEFAULTS end
    return EnsureDB()
end

-- Automation can act: the module is on with at least one Auto-Swap channel.
local function AutomationLive()
    local db = ReadDB()
    return (db.enabled and (db.gearEnabled or db.talentEnabled)) and true or false
end

-- EllesmereUI's taint-safe print (it drops lines in raid and PvP combat and
-- during a running key).
local function Print(msg) EllesmereUI.Print(AC() .. EllesmereUI.L("Loadout Manager") .. ":|r", msg) end

local function Announce(msg)
    if ReadDB().announce then Print(msg) end
end

-- A button press always gets its line; automatic swaps follow Announce.
local function Notify(request, msg)
    if request.manual then Print(msg) else Announce(msg) end
end

-- Coalesce a burst of events into one refresh of the settings page, and only
-- while that page is the active one.
local refreshScheduled = false
local function FlushRefresh()
    refreshScheduled = false
    -- A value refresh repaints the page's live widgets; a forced rebuild
    -- would orphan any menu open on it.
    if ns.OnStateChanged then ns.OnStateChanged() end
end
local function RequestRefresh()
    if refreshScheduled or EllesmereUI:GetActiveModule() ~= ADDON_NAME then return end
    refreshScheduled = true
    C_Timer.After(0, FlushRefresh)
end

-- The spec info call reports 0, not nil, for a slot with no specialization.
local function GetCurrentSpecID()
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then return nil end
    local specID = C_SpecializationInfo.GetSpecializationInfo(index)
    if specID and specID ~= 0 then return specID end
    return nil
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

-- A spec's bucket; create makes it (and the saved table) when missing.
local function GetSpecTables(specID, create)
    if not specID then return nil end
    local db = create and EnsureDB() or ReadDB()
    local bucket = db.specDefaults[specID]
    if not bucket then
        if not create then return nil end
        bucket = {}
        db.specDefaults[specID] = bucket
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
    return EllesmereUI.Lf("Spec %s", tostring(specID))
end

-- Read-only stand-in when a spec has no bucket yet.
local EMPTY_SCOPE = {
    instanceSets = {}, difficultySets = {}, typeDefaults = {},
    talentInstanceSets = {}, talentDifficultySets = {}, talentTypeDefaults = {},
}

local function GetWriteTables()
    if UI.assignScope then
        return GetSpecTables(UI.assignScope, true), UI.assignScope
    end
    return EnsureDB(), nil
end

local function GetReadTables()
    if UI.assignScope then
        return GetSpecTables(UI.assignScope, false) or EMPTY_SCOPE, UI.assignScope
    end
    return ReadDB(), nil
end

-- Copy every assignment table from another scope into the one being edited.
-- Talent entries belong to a spec: copying into a spec scope keeps only that
-- spec's loadouts; the All Specs destination keeps everything.
local function CopyScopeFrom(sourceID)
    local dst, dstID = GetWriteTables()
    local srcT = sourceID and (GetSpecTables(sourceID, false) or EMPTY_SCOPE) or EnsureDB()
    local skippedTalents = 0
    for _, k in ipairs(SPEC_TABLE_KEYS) do
        local copy = {}
        for key, v in pairs(srcT[k] or NO_ENTRIES) do
            if type(v) == "table" then
                if dstID and v.specID and tonumber(v.specID) ~= tonumber(dstID) then
                    skippedTalents = skippedTalents + 1
                else
                    copy[key] = CopyTable(v)
                end
            else
                copy[key] = v
            end
        end
        dst[k] = copy
    end
    assignVersion = assignVersion + 1
    -- The page shows the copy; only what it left out gets a line.
    if skippedTalents > 0 then
        Print(EllesmereUI.Lf("Skipped %d talent loadout(s) that belong to other specializations.", skippedTalents))
    end
    RequestRefresh()
end

-- The DON'T MOVE panel shown while a talent loadout loads.
local warningFrame = nil
HideSpecChangeWarning = function()
    if warningFrame then warningFrame:Hide() end
end

local function ShowSpecChangeWarning()
    if not ReadDB().specWarning then return end
    local f = warningFrame
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetSize(560, 92)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
        f.title = f:CreateFontString(nil, "OVERLAY")
        f.title:SetPoint("CENTER", f, "CENTER", 0, 13)
        f.subtitle = f:CreateFontString(nil, "OVERLAY")
        f.subtitle:SetPoint("TOP", f.title, "BOTTOM", 0, -6)

        -- Styled with the parent's primitives so it follows the active theme.
        local bgc = EllesmereUI.DARK_BG
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(bgc.r, bgc.g, bgc.b, 0.92)
        EllesmereUI.MakeBorder(f, 1, 1, 1, 0.08)
        local line = f:CreateTexture(nil, "OVERLAY")
        line:SetPoint("BOTTOMLEFT", 1, 1)
        line:SetPoint("BOTTOMRIGHT", -1, 1)
        line:SetHeight(2)
        f.accentLine = line

        f:Hide()
        warningFrame = f
    end

    -- Font and accent are read per show, so a change since the last one lands.
    EllesmereUI.ApplyModuleFont(f.title, nil, 26)
    EllesmereUI.ApplyModuleFont(f.subtitle, nil, 16)
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    f.accentLine:SetColorTexture(ar, ag, ab, 0.9)
    f.title:SetTextColor(1, 0.12, 0.08, 1)
    f.subtitle:SetTextColor(ar, ag, ab, 1)
    f.title:SetText(EllesmereUI.L("DON'T MOVE - CHANGING TALENTS"))
    f.subtitle:SetText(EllesmereUI.L("Wait until the loadout finishes."))
    f:Show()
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
    return EllesmereUI.Lf("Difficulty %s", tostring(difficultyID))
end

local function InstanceName(instanceID)
    local name = instanceID and GetRealZoneText(instanceID)
    if name and name ~= "" then return name end
    return EllesmereUI.Lf("Instance %s", tostring(instanceID))
end

-- An instance assignment key ("2657" or "2657:15") as the page shows it:
-- "Nerub-ar Palace (Any Difficulty)" or "Nerub-ar Palace (Heroic Only)".
local function AssignmentLabel(key)
    local instanceID, difficultyID = tostring(key):match("^(%d+):(%d+)$")
    if instanceID then
        return EllesmereUI.Lf("%1$s (%2$s Only)", InstanceName(tonumber(instanceID)), DifficultyName(tonumber(difficultyID)))
    end
    return EllesmereUI.Lf("%s (Any Difficulty)", InstanceName(tonumber(key)))
end

-- Fills ctx with where you are. GetCurrentInstanceContext reuses one table:
-- callers consume the result at once and never keep it.
local function ReadContext(ctx)
    local inInstance, instanceType = IsInInstance()
    local name, instanceType2, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    ctx.inInstance = inInstance
    ctx.instanceType = instanceType2 or instanceType or "none"
    ctx.name = name or EllesmereUI.L("Unknown")
    ctx.difficultyID = difficultyID
    ctx.difficultyName = difficultyName
    ctx.instanceID = instanceID
    return ctx
end

local contextCache = {}
local function GetCurrentInstanceContext() return ReadContext(contextCache) end

-- "world", or instance type, ID and assignment difficulty (nil inside an
-- instance that reports no ID).
local function BuildPlaceKey(ctx)
    if not ctx.inInstance then return "world" end
    if not ctx.instanceID then return nil end
    return tostring(ctx.instanceType or "none") .. ":" .. tostring(ctx.instanceID) .. ":" ..
        tostring(AssignmentDifficulty(ctx.difficultyID) or 0)
end

-- A request's context: the place plus the spec. Either changing ends it.
local function BuildAutoInstanceKey(ctx)
    local place = BuildPlaceKey(ctx)
    if not place then return nil end
    return place .. ":" .. tostring(GetCurrentSpecID() or 0)
end

local function NoteCurrentPlace()
    lastPlaceKey = BuildPlaceKey(GetCurrentInstanceContext())
    lastSpecID = GetCurrentSpecID()
end

-- -----------------------------------------------------------------------------
-- Gear sets
-- -----------------------------------------------------------------------------

local function GetEquipmentSetIDs()
    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if ok and type(ids) == "table" then return ids end
end

-- A populated catalog can prove that a name is missing. An empty catalog is
-- not evidence of readiness; pending lookups wait for equipment/bag events.
local function EquipmentCacheReady(allowEmpty)
    local ids = GetEquipmentSetIDs()
    if not ids then return false end
    if #ids == 0 then return allowEmpty == true end
    -- IDs present but names not yet populated is also "warming up"
    local name = C_EquipmentSet.GetEquipmentSetInfo(ids[1])
    return name ~= nil
end

local function GetEquipmentSetIDByName(setName)
    if not setName or setName == "" then return nil end

    local wanted = tostring(setName):lower()
    for _, setID in ipairs(GetEquipmentSetIDs() or NO_ENTRIES) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name and name:lower() == wanted then
            return setID, name
        end
    end
    return nil
end

-- setID, name, isEquipped, numItems, numEquipped, numLost for a set name.
local function GetSetInfoByName(setName)
    local setID, canonicalName = GetEquipmentSetIDByName(setName)
    if not setID then return nil end
    local _, _, _, isEquipped, numItems, numEquipped, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return setID, canonicalName, isEquipped, numItems, numEquipped, numLost
end

local function ByNameAsc(a, b) return a.name < b.name end
local function ByNameLowerAsc(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end

-- Read live: only the settings page lists sets, and only while it is open.
local function ListEquipmentSetsDetailed()
    local sets = {}
    for _, setID in ipairs(GetEquipmentSetIDs() or NO_ENTRIES) do
        local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then table.insert(sets, { name = name, icon = icon }) end
    end
    table.sort(sets, ByNameAsc)
    return sets
end

local function SetExists(setName)
    return GetEquipmentSetIDByName(setName) ~= nil
end

local function RestrictionActive(kind)
    local restriction = Enum.AddOnRestrictionType[kind]
    return restriction ~= nil and C_RestrictedActions.IsAddOnRestrictionActive(restriction)
end

-- A running key locks gear and talents for the whole run: nothing at all
-- happens then, and nothing is said.
local function KeystoneRunning()
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    return (ok and active == true) or RestrictionActive("ChallengeMode")
end

-- SwitchToLoadoutByName is restricted, so a talent load waits out these
-- add-on restrictions. Map is not one of them: raids, dungeons and arenas
-- keep it up and the load works there. Combat is last because it only lags
-- the end of lockdown.
local SWAP_RESTRICTIONS = { "PvPMatch", "Encounter", "Combat" }

local function RestrictionText(kind)
    if kind == "Encounter" then return EllesmereUI.L("Talent changes are blocked during this encounter.") end
    if kind == "PvPMatch" then return EllesmereUI.L("Talent changes are blocked while a PvP match clears.") end
    return EllesmereUI.L("Talent changes are blocked right after combat.")
end

-- An arena or battleground keeps the PvP match restriction up in the
-- preparation area too, where the load works; once the match is under way
-- talents stay locked until it is over.
local function PvPMatchBlock()
    local instanceType = GetCurrentInstanceContext().instanceType
    if instanceType ~= "arena" and instanceType ~= "pvp" then return "PvPMatch" end
    if C_PvP.GetActiveMatchState() >= Enum.PvPMatchState.Engaged then return "match" end
end

-- The first reason a talent load cannot start now. Cheap checks only: the
-- talent tree is never read while one of them holds.
local function TalentLoadBlocker()
    if KeystoneRunning() then return "keystone" end
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
    if not request.manual then
        local db = ReadDB()
        if not (db.enabled and db[request.kind == "gear" and "gearEnabled" or "talentEnabled"]) then
            FinishRequest(request)
            return false
        end
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
    UpdateRequestEvents()
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
    UpdateRequestEvents()
    return request
end

-- One flush per frame serves every queued request, after the handlers of a
-- burst of native events have unwound. No elapsed duration decides whether
-- data is ready or a swap succeeded.
local flushQueued = false
local function FlushRequests()
    flushQueued = false
    for i = 1, #REQUEST_KINDS do
        local request = requests[REQUEST_KINDS[i]]
        if request and request.resumeQueued then
            local verify = request.resumeCheckOnly
            request.resumeQueued, request.resumeCheckOnly = nil, nil
            if RequestIsCurrent(request) then RetryRequest(request, verify) end
        end
    end
end

-- checkOnly re-checks a swap in progress without spending a try.
local function ScheduleRequest(request, checkOnly)
    if not request then return end
    if request.resumeQueued then
        if not checkOnly then request.resumeCheckOnly = false end
        return
    end
    if not RequestIsCurrent(request) then return end
    request.resumeQueued, request.resumeCheckOnly = true, checkOnly
    if not flushQueued then
        flushQueued = true
        C_Timer.After(0, FlushRequests)
    end
end

-- Run once combat ends. The queue has no cancel, so each re-reads its
-- channel's live request and skips one that ended or stopped waiting on combat.
local RESUME_AFTER_COMBAT = {
    gear = function()
        local request = requests.gear
        if request and request.waitReason == "combat" then ScheduleRequest(request) end
    end,
    talent = function()
        local request = requests.talent
        if request and request.waitReason == "combat" then ScheduleRequest(request) end
    end,
}

-- The second sentence of a wait's chat line: when the swap runs.
local function WaitSuffix(request)
    local reason = request.waitReason
    if reason == "combat" then return EllesmereUI.L("Queued for after combat.") end
    if reason == "alive" then
        if request.kind == "gear" then return EllesmereUI.L("The gear swap waits until you are alive.") end
        return EllesmereUI.L("The talent swap waits until you are alive.")
    end
    if reason == "restricted" then return EllesmereUI.L("The swap runs once they are allowed again.") end
    return EllesmereUI.L("It retries on its own.")
end

-- quiet: announce no wait (automatic swaps held while you are dead, short
-- restrictions, a talent loadout most likely in place). A request that
-- announced an earlier wait still says when it gives up.
local function DeferRequest(request, message, combat, waitReason, quiet)
    if not RequestIsCurrent(request) then return end
    local silent = quiet and not (request.announcedWait or request.announcedCombat)
    -- Queue In Combat off drops a swap that comes due in combat, but not one
    -- waiting out a restriction: an encounter usually ends in combat.
    if combat and not ReadDB().queueInCombat and request.waitReason ~= "restricted" then
        if not silent then
            if request.kind == "gear" then
                Notify(request, EllesmereUI.L("Gear swap skipped: you are in combat."))
            else
                Notify(request, EllesmereUI.L("Talent swap skipped: you are in combat."))
            end
        end
        FinishRequest(request)
        return
    end
    -- Every wake-up spends one try (RetryRequest), so a wait cannot retry forever.
    if request.tries >= MAX_SWAP_RETRIES then
        if not silent then Print(message .. " " .. EllesmereUI.L("Retry limit reached; try again when ready.")) end
        FinishRequest(request)
        return
    end
    request.waitReason = combat and "combat" or waitReason or "availability"
    if combat then CombatQueue.Defer(request.kind, RESUME_AFTER_COMBAT[request.kind]) end
    -- One line per kind of wait. Combat lines can be muted (EllesmereUI.Print
    -- in raid combat) and quiet waits print nothing; neither may swallow a
    -- later wait's line.
    local flag = combat and "announcedCombat" or "announcedWait"
    if not request[flag] and not quiet then
        request[flag] = true
        Notify(request, message .. " " .. WaitSuffix(request))
    end
    UpdateRequestEvents()
end

TryEquipSet = function(request)
    if not RequestIsCurrent(request) or request.verifying then return end
    if KeystoneRunning() then FinishRequest(request) return end -- gear is locked mid-key

    local setName = strtrim(tostring(request.value or ""))
    if setName == "" then FinishRequest(request) return end
    local setID, name, isEquipped, _, _, numLost = GetSetInfoByName(setName)
    if not setID then
        if not EquipmentCacheReady() then
            DeferRequest(request, EllesmereUI.L("Equipment sets are not available yet."), false, "catalog")
        else
            Print(EllesmereUI.Lf("Gear set %s not found; it may have been renamed or deleted.", Bad(setName)))
            FinishRequest(request)
        end
        return
    end
    -- Already worn: nothing to do, and nothing to wait for. Automatic checks
    -- stay quiet (most entries need no change); a button press says so.
    if isEquipped then
        if request.manual then Print(EllesmereUI.Lf("Gear set %s is already equipped.", Hi(name))) end
        FinishRequest(request)
        return
    end
    if InCombatLockdown() then
        DeferRequest(request, EllesmereUI.L("You are in combat."), true)
        return
    end
    if UnitIsDeadOrGhost("player") then
        DeferRequest(request, EllesmereUI.L("You are dead."), false, "alive", not request.manual)
        return
    end
    -- Blizzard's own Equip button refuses while the set holds a locked item
    -- or you are casting; wait that out like any other availability hold.
    -- The cast name can read secret: only its type is tested.
    local castName = UnitCastingInfo("player")
    if C_EquipmentSet.EquipmentSetContainsLockedItems(setID) or type(castName) ~= "nil" then
        DeferRequest(request, EllesmereUI.L("Gear swap held: an item is locked or you are casting."), false, "availability")
        return
    end
    request.waitReason = nil

    if numLost and numLost > 0 then
        Announce(EllesmereUI.Lf("Gear set %1$s has %2$d missing item(s), maybe in your bank. Equipping the rest.", Hi(name), numLost))
    end
    request.setID, request.setName = setID, name
    request.verifying, request.swapFinished = true, nil
    UpdateRequestEvents()
    local okCall, result = pcall(C_EquipmentSet.UseEquipmentSet, setID)
    if not RequestIsCurrent(request) then return end
    if not okCall or result == false then
        request.verifying = nil
        DeferRequest(request, EllesmereUI.Lf("Could not equip gear set %s.", Bad(name)))
        return
    end
    if request.reason then
        Announce(EllesmereUI.Lf("Equipping gear set %1$s (%2$s).", Hi(name), request.reason))
    else
        Announce(EllesmereUI.Lf("Equipping gear set %s.", Hi(name)))
    end
    ScheduleRequest(request, true)
end

-- -----------------------------------------------------------------------------
-- Talent loadouts
-- -----------------------------------------------------------------------------

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
    return { configID = configID, name = info.name or EllesmereUI.Lf("Loadout %s", tostring(configID)), specID = specID }
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
    if stored and stored.configID then return EllesmereUI.Lf("Loadout %s", tostring(stored.configID)) end
    return nil
end

local function TalentExists(stored)
    return GetTalentLoadoutFromStored(stored) ~= nil
end

-- A stored talent loadout is only usable by the spec it belongs to.
local function TalentMatchesSpec(stored, specID)
    local sid = type(stored) == "table" and stored.specID or nil
    if not sid or not specID then return true end
    return tonumber(sid) == tonumber(specID)
end

-- The talent pick, or nil while it belongs to another spec than yours.
local function SelectedTalent()
    local selected = UI.selectedTalent
    if selected and not TalentMatchesSpec(selected, GetCurrentSpecID()) then return nil end
    return selected
end

-- Difficulty IDs that map onto pseudo-types. Delves report as scenarios and
-- Timewalking keeps its parent type, so both are identified by difficulty.
local MPLUS_DIFFICULTIES = { [8] = true, [23] = true }        -- Keystone, Mythic
local TIMEWALKING_DIFFICULTIES = { [24] = true, [33] = true } -- TW dungeon, TW raid
local DELVE_DIFFICULTIES = { [208] = true }                    -- Delves

-- The type keys to try for a context, most specific first (one or two).
local function TypeKeysForContext(ctx)
    if not ctx.inInstance then return "world" end
    local diff, base = ctx.difficultyID, ctx.instanceType
    if diff and TIMEWALKING_DIFFICULTIES[diff] then return "timewalking", base end
    if base == "scenario" and diff and DELVE_DIFFICULTIES[diff] then return "delve", base end
    if base == "party" and diff and MPLUS_DIFFICULTIES[diff] then return "mplus", base end
    return base
end

local function Pick(tbl, key, validator, specID)
    local value = tbl and key and tbl[key]
    if value and (not validator or validator(value, specID)) then return value end
end

-- One type key: the current spec's assignment, then the All Specs one.
local function PickType(db, spec, kType, key, validator, specID)
    if not key then return nil end
    local value = spec and Pick(spec[kType], key, validator, specID)
    if value then return value, "type", key, specID end
    value = Pick(db[kType], key, validator, specID)
    if value then return value, "type", key, nil end
end

-- Shared resolver. Within each specificity level (difficulty > instance > type)
-- the current spec's assignment wins over the All Specs assignment. Returns
-- value, source, key, scopeSpecID (nil scope = matched the All Specs layer).
local function ResolveForContext(ctx, kInst, kDiff, kType, validator)
    local db = ReadDB()
    local specID = GetCurrentSpecID()
    local spec = specID and db.specDefaults[specID] or nil
    local value
    if ctx.inInstance then
        if not ctx.instanceID then return nil, "missing-instance-id" end
        local diffKey = BuildDifficultyKey(ctx.instanceID, ctx.difficultyID)
        value = spec and Pick(spec[kDiff], diffKey, validator, specID)
        if value then return value, "difficulty", diffKey, specID end
        value = Pick(db[kDiff], diffKey, validator, specID)
        if value then return value, "difficulty", diffKey, nil end
        local instanceKey = tostring(ctx.instanceID)
        value = spec and Pick(spec[kInst], instanceKey, validator, specID)
        if value then return value, "instance", instanceKey, specID end
        value = Pick(db[kInst], instanceKey, validator, specID)
        if value then return value, "instance", instanceKey, nil end
    end
    -- Type keys, most specific first; outside an instance that is just "world".
    local key1, key2 = TypeKeysForContext(ctx)
    local source, key, scope
    value, source, key, scope = PickType(db, spec, kType, key1, validator, specID)
    if value then return value, source, key, scope end
    value, source, key, scope = PickType(db, spec, kType, key2, validator, specID)
    if value then return value, source, key, scope end
    return nil, "unassigned"
end

local function GetAssignedSetForContext(ctx)
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

-- A talent commit casting now (the talent UI's Apply, or an earlier load)
-- refuses another load until it ends. The cast's spell can read secret.
local function CommitCastRunning()
    local spellID = select(9, UnitCastingInfo("player"))
    if type(spellID) == "nil" or issecretvalue(spellID) then return false end
    return spellID == Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID
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

-- final: combat started, so the load ends here whatever the evidence says.
CheckTalentCompletion = function(request, final)
    if not RequestIsCurrent(request) or not request.inFlight or request.callingLoad or request.commitFailed then return end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if not activeID or HasStagedTalentChanges(activeID) == true then
        if final then FinishRequest(request) end
        return
    end
    local matches = ActiveTalentsMatch(request)
    -- The UI command has no acceptance result. An unrelated active-config
    -- update alone cannot prove it was accepted when node data is missing.
    if matches == true then
        CompleteTalentRequest(request)
    elseif matches == nil and request.commitCastSucceeded and request.commitSignal
        and C_ClassTalents.GetLastSelectedSavedConfigID(request.specID) == request.configID then
        CompleteTalentRequest(request)
    elseif matches == false and request.commitCastSucceeded and request.updatedAfterCast then
        -- The commit went through and the active build updated since, yet it
        -- still differs: part of the loadout could not be applied.
        Notify(request, EllesmereUI.Lf("Talent loadout %s did not fully apply.", Bad(request.loadoutName)))
        FinishRequest(request)
    elseif final then
        FinishRequest(request)
    end
end

local function TalentCommitUpdated(request, configID)
    if issecretvalue(configID) then return end
    if not RequestIsCurrent(request) or not request.inFlight then return end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if not activeID or configID ~= activeID then return end
    request.commitSignal = true
    if request.commitCastSucceeded then request.updatedAfterCast = true end
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
    DeferRequest(request, EllesmereUI.L("The talent change was interrupted."), InCombatLockdown())
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
        if not request.callingLoad then ShowSpecChangeWarning() end
    elseif request.commitCastGUID and request.commitCastGUID == castGUID then
        request.casting = nil
        HideSpecChangeWarning()
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            request.commitCastSucceeded = true
            request.commitSignal = true
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
        if not quiet then Notify(request, EllesmereUI.L("Talent changes are locked once a PvP match starts. Talent swap skipped.")) end
        FinishRequest(request)
    elseif blocker == "combat" then
        DeferRequest(request, EllesmereUI.L("You are in combat."), true, nil, quiet)
    elseif blocker == "dead" then
        DeferRequest(request, EllesmereUI.L("You are dead."), false, "alive", quiet or not request.manual)
    elseif blocker == "edit" then
        DeferRequest(request, EllesmereUI.L("Talents cannot be changed here yet."), false, nil, quiet)
    else
        -- A restriction: resume when it lifts. An automatic swap waits out the
        -- Combat one (it outlasts lockdown by moments) and a PvP match
        -- clearing outside its arena or battleground without a word.
        request.restriction = blocker
        DeferRequest(request, RestrictionText(blocker), false, "restricted",
            quiet or (not request.manual and (blocker == "Combat" or blocker == "PvPMatch")))
    end
end

TryLoadTalentLoadout = function(request)
    if not RequestIsCurrent(request) or request.inFlight then return end
    local blocker = TalentLoadBlocker()
    if blocker == "keystone" then FinishRequest(request) return end -- talents are locked for the whole run
    local stored = NormalizeTalentStored(request.value)
    if not stored then FinishRequest(request) return end
    if not TalentMatchesSpec(stored, GetCurrentSpecID()) then
        Print(EllesmereUI.L("The selected talent loadout belongs to another specialization."))
        FinishRequest(request)
        return
    end

    local loadout = GetTalentLoadoutFromStored(stored)
    if not loadout then
        if #ListTalentLoadouts() == 0 then
            DeferRequest(request, EllesmereUI.L("Talent loadouts are not available yet."), false, "catalog")
        else
            Print(EllesmereUI.L("The assigned talent loadout was not found for your current specialization."))
            FinishRequest(request)
        end
        return
    end
    request.configID, request.specID, request.loadoutName = loadout.configID, loadout.specID, loadout.name
    local selected = C_ClassTalents.GetLastSelectedSavedConfigID(loadout.specID) == loadout.configID
    if blocker then
        -- Nothing reads the talent tree while a check blocks the load. A
        -- selected loadout is most likely in place already, so an automatic
        -- swap holds it without a word; the comparison below settles it.
        HoldTalentRequest(request, blocker, selected and not request.manual)
        return
    end
    if CommitCastRunning() then
        DeferRequest(request, EllesmereUI.L("Talent swap held: a talent change is in progress."), false, "availability")
        return
    end
    -- The load drops changes staged in the talent UI without the confirmation
    -- Blizzard's own loadout menu asks for, so an automatic swap waits, without
    -- a word while its loadout is selected (most likely in place already).
    if not request.manual and HasStagedTalentChanges(C_ClassTalents.GetActiveConfigID()) == true then
        DeferRequest(request, EllesmereUI.L("Talent swap held: you have unsaved talent changes."), false, "availability", selected)
        return
    end
    request.waitReason, request.restriction = nil, nil

    -- Already applied (selected, and its talents match the live build): like
    -- a worn gear set, nothing to load; only a button press says so.
    request.talentSelection = nil
    if selected then
        request.talentSelection = GetTalentSelection(loadout.configID)
        if ActiveTalentsMatch(request) == true then
            if request.manual then Print(EllesmereUI.Lf("Talent loadout %s is already active.", Hi(loadout.name))) end
            FinishRequest(request)
            return
        end
    end

    if not HasUniqueLoadoutName(loadout) then
        Print(EllesmereUI.L("Talent swap skipped: another loadout has the same name. Rename one, then use Check Now."))
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
    request.commitCastSucceeded, request.updatedAfterCast, request.casting = nil, nil, nil
    UpdateRequestEvents()
    local okLoad = pcall(C_ClassTalents.SwitchToLoadoutByName, loadout.name)
    -- This command has no load-result return. Confirm through native events
    -- and applied-node evidence, never merely because the call returned.
    request.callingLoad = nil
    if not RequestIsCurrent(request) then return end
    if not okLoad or request.commitFailed then
        request.inFlight = nil
        HideSpecChangeWarning()
        DeferRequest(request, EllesmereUI.Lf("Could not load talent loadout %s.", Bad(loadout.name)))
        return
    end
    if request.casting then ShowSpecChangeWarning() end
    if request.reason then
        Announce(EllesmereUI.Lf("Loading talent loadout %1$s (%2$s).", Hi(loadout.name), request.reason))
    else
        Announce(EllesmereUI.Lf("Loading talent loadout %s.", Hi(loadout.name)))
    end
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
    if source == "type" then return EllesmereUI.Lf("%s default", TypeLabel(key)) end
    if source == "difficulty" then
        return ctx.name .. ", " .. DifficultyName(AssignmentDifficulty(ctx.difficultyID))
    end
    return ctx.name
end

local function CheckAndSwap(manual)
    local db = ReadDB()
    if not manual and not db.enabled then return end
    if KeystoneRunning() then return end -- gear and talents are locked mid-key
    -- This check expresses new intent, including the absence of an assignment.
    -- Cancel an older request before resolving the new context.
    CancelRequests()

    local ctx = GetCurrentInstanceContext()
    local setName, gearSource, gearKey, talentStored, talentSource, talentKey
    if manual or db.gearEnabled then setName, gearSource, gearKey = GetAssignedSetForContext(ctx) end
    if manual or db.talentEnabled then talentStored, talentSource, talentKey = GetAssignedTalentForContext(ctx) end
    if not setName and not talentStored then
        -- Automatic checks stay silent (most places have nothing assigned,
        -- and outside instances only an Open World default applies).
        if manual then
            if ctx.inInstance then
                Print(EllesmereUI.Lf("Nothing is assigned for %s.", ctx.name))
            else
                Print(EllesmereUI.L("Nothing is assigned for the open world."))
            end
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

-- One automatic check per frame: the latest request wins, and CancelRequests
-- (which bumps the serial) drops one still queued.
local autoCheckQueued, autoCheckQueuedSerial, autoCheckKey = false, nil, nil
local function RunAutoCheck()
    autoCheckQueued = false
    if autoCheckQueuedSerial ~= autoCheckSerial or not AutomationLive() then return end
    if autoCheckKey ~= BuildAutoInstanceKey(GetCurrentInstanceContext()) then return end
    CheckAndSwap(false)
end

local function QueueAutoCheck()
    autoCheckSerial = autoCheckSerial + 1
    autoCheckQueuedSerial = autoCheckSerial
    autoCheckKey = BuildAutoInstanceKey(GetCurrentInstanceContext())
    if not autoCheckQueued then
        autoCheckQueued = true
        C_Timer.After(0, RunAutoCheck)
    end
end

local function HandlePossibleInstanceEntry()
    local place = BuildPlaceKey(GetCurrentInstanceContext())
    if place == lastPlaceKey then return end
    lastPlaceKey = place
    lastSpecID = GetCurrentSpecID()
    -- Switched off, only button presses run, and RequestIsCurrent already
    -- drops one whose context changed.
    if not AutomationLive() then return end
    CancelRequests()
    if place then QueueAutoCheck() end
end

-- A gear swap ends once its set is worn or a swap has finished; a set that
-- is not worn by then gets a line naming what did not equip. The set can read
-- unworn for a moment after the swap finishes (its last items still landing,
-- which re-run this), so the verdict waits 1.5s from the swap's end.
VerifyEquippedSet = function(request)
    if not RequestIsCurrent(request) or not request.verifying then return end
    local wanted = request.setName
    local setID, _, isEquipped, numItems, numEquipped, numLost = GetSetInfoByName(wanted)
    if not isEquipped then
        if not request.swapFinished then return end
        local left = request.swapFinished + 1.5 - GetTime()
        if left > 0 then
            if not request.settleTimer then
                request.settleTimer = true
                C_Timer.After(left, function()
                    request.settleTimer = nil
                    if RequestIsCurrent(request) and request.verifying then ScheduleRequest(request, true) end
                end)
            end
            return
        end
    end
    request.verifying = nil
    FinishRequest(request)
    if setID and not isEquipped then
        local missing = (tonumber(numItems) or 0) - (tonumber(numEquipped) or 0)
        if missing <= 0 then
            Print(EllesmereUI.Lf("Gear set %s did not finish equipping.", Bad(wanted)))
        elseif numLost and numLost > 0 then
            Print(EllesmereUI.Lf("Gear set %1$s did not fully equip: %2$d item(s) missing (check your bank).", Bad(wanted), missing))
        else
            Print(EllesmereUI.Lf("Gear set %1$s did not fully equip: %2$d item(s) missing.", Bad(wanted), missing))
        end
    end
    RequestRefresh()
end

local function ResumeRequests(waitReason)
    for i = 1, #REQUEST_KINDS do
        local request = requests[REQUEST_KINDS[i]]
        if request and (not waitReason or request.waitReason == waitReason) then
            ScheduleRequest(request)
        end
    end
end

-- One slot's gear and talent tables in an assignment layer: a type default,
-- an instance ("2657") or an instance on one difficulty ("2657:15").
local function SlotTables(layer, key, isType)
    if isType then return layer.typeDefaults, layer.talentTypeDefaults end
    if tostring(key):find(":", 1, true) then return layer.difficultySets, layer.talentDifficultySets end
    return layer.instanceSets, layer.talentInstanceSets
end

-- Save the selected set and/or loadout into one slot of the scope being
-- edited; an empty picker keeps that half as saved. The page shows the
-- result, so only a refusal gets a chat line.
local function SaveSlot(key, isType)
    local layer, scopeID = GetWriteTables()
    local gTbl, tTbl = SlotTables(layer, key, isType)
    local changed = false
    local setName = UI.selectedSet
    if setName and SetExists(setName) then
        gTbl[key] = setName
        changed = true
    end
    local talent = SelectedTalent()
    if talent and TalentExists(talent) then
        local stored = StoreTalentLoadout(talent)
        if scopeID and stored.specID and tonumber(stored.specID) ~= tonumber(scopeID) then
            Print(EllesmereUI.Lf("Talents not saved: %1$s belongs to %2$s.", Hi(stored.name), SpecName(stored.specID)))
        else
            tTbl[key] = stored
            changed = true
        end
    end
    if changed then
        assignVersion = assignVersion + 1
    else
        Print(EllesmereUI.L("Nothing selected to assign."))
    end
    return changed
end

local function ClearSlot(key, isType)
    local gRead, tRead = SlotTables((GetReadTables()), key, isType)
    if gRead[key] == nil and tRead[key] == nil then return false end
    local gTbl, tTbl = SlotTables((GetWriteTables()), key, isType)
    gTbl[key], tTbl[key] = nil, nil
    assignVersion = assignVersion + 1
    return true
end

-- This instance's slot key, or nil (with a chat line) outside an instance.
local function CurrentInstanceKey(perDifficulty)
    local ctx = GetCurrentInstanceContext()
    if not ctx.inInstance or not ctx.instanceID then
        Print(EllesmereUI.L("You are not inside a dungeon, raid or other instance."))
        return nil
    end
    return perDifficulty and BuildDifficultyKey(ctx.instanceID, ctx.difficultyID) or tostring(ctx.instanceID)
end

local function AddAssignments(list, byKey, tbl, field)
    for key, value in pairs(tbl or NO_ENTRIES) do
        local entry = byKey[key]
        if not entry then
            entry = { key = key, label = AssignmentLabel(key) }
            byKey[key] = entry
            list[#list + 1] = entry
        end
        entry[field] = value
    end
end

local function ByLabelThenKey(a, b)
    if a.label ~= b.label then return a.label < b.label end
    return tostring(a.key) < tostring(b.key)
end

-- Every instance assignment in the scope being edited, sorted by name, for
-- the settings page's Saved Instances list: { key, label, gear, talent }.
-- One list per frame serves a whole page refresh; the scope, the saved table
-- and every assignment write invalidate it.
local listMemo, listStamp, listVersion, listScope, listDB
local function ListInstanceAssignments()
    local now, db = GetTime(), EllesmereUILoadoutManagerDB
    if listMemo and listStamp == now and listVersion == assignVersion
        and listScope == UI.assignScope and listDB == db then
        return listMemo
    end
    local R = GetReadTables()
    local list, byKey = {}, {}
    AddAssignments(list, byKey, R.instanceSets, "gear")
    AddAssignments(list, byKey, R.talentInstanceSets, "talent")
    AddAssignments(list, byKey, R.difficultySets, "gear")
    AddAssignments(list, byKey, R.talentDifficultySets, "talent")
    table.sort(list, ByLabelThenKey)
    listMemo, listStamp, listVersion, listScope, listDB = list, now, assignVersion, UI.assignScope, db
    return list
end

-- -----------------------------------------------------------------------------
-- Verify Assigned Sets (the settings page's Gear Set cog)
-- -----------------------------------------------------------------------------

local GEAR_TABLE_KEYS = { "instanceSets", "difficultySets", "typeDefaults" }

-- Lists, in chat, every assignment of one layer pointing at a set that no
-- longer exists; returns how many.
local function ListStaleSets(layer, scopeName)
    local problems = 0
    for i = 1, #GEAR_TABLE_KEYS do
        local tableKey = GEAR_TABLE_KEYS[i]
        for mapKey, setName in pairs(layer[tableKey] or NO_ENTRIES) do
            if type(setName) == "string" and not SetExists(setName) then
                problems = problems + 1
                local where
                if tableKey == "typeDefaults" then
                    where = EllesmereUI.Lf("%s default", TypeLabel(mapKey))
                else
                    where = AssignmentLabel(mapKey)
                end
                EllesmereUI.Print("  " .. Bad(setName) .. " - " .. where .. ", " .. scopeName)
            end
        end
    end
    return problems
end

local function VerifyAssignments()
    if not EquipmentCacheReady(true) then
        Print(EllesmereUI.L("Equipment sets are still loading; try again in a moment."))
        return
    end
    local db = ReadDB()
    local problems = ListStaleSets(db, EllesmereUI.L("All Specs"))
    for specID, bucket in pairs(db.specDefaults) do
        problems = problems + ListStaleSets(bucket, tostring(SpecName(specID)))
    end
    if problems == 0 then
        Print(EllesmereUI.L("All gear assignments point to existing Equipment Manager sets."))
    else
        Print(EllesmereUI.Lf("%d assignment(s) point to missing gear sets (listed above).", problems))
    end
end

-- -----------------------------------------------------------------------------
-- Events
-- -----------------------------------------------------------------------------

local TALENT_CATALOG_EVENTS = {
    "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_CREATED", "TRAIT_CONFIG_DELETED",
    "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "SELECTED_LOADOUT_CHANGED",
}
local TALENT_REQUEST_EVENTS = { "CONFIG_COMMIT_FAILED", "PLAYER_TALENT_UPDATE", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CHANGED" }
local TALENT_CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

local EVENT_HANDLERS = {}

EVENT_HANDLERS.PLAYER_ENTERING_WORLD = function(_, initialLogin, reloading)
    if initialLogin or reloading then
        -- Logging in or reloading is no entry: note where you are.
        CancelRequests()
        NoteCurrentPlace()
    else
        HandlePossibleInstanceEntry()
        ResumeRequests()
    end
    RequestRefresh()
end

EVENT_HANDLERS.ZONE_CHANGED_NEW_AREA = function()
    HandlePossibleInstanceEntry()
    ResumeRequests("availability")
    RequestRefresh()
end

EVENT_HANDLERS.CHALLENGE_MODE_START = function()
    CancelRequests()
end

-- Registered for the player only. It also fires without a spec change
-- (entering an arena, for one): only a new spec ID counts, so a spec event
-- that lands before the zone events of an entry never swallows the entry.
EVENT_HANDLERS.PLAYER_SPECIALIZATION_CHANGED = function()
    local specID = GetCurrentSpecID()
    if specID == lastSpecID then return end
    local known = lastSpecID ~= nil
    lastSpecID = specID
    if not known then return end
    CancelRequests()
    UI.selectedTalent = nil -- the picker lists only the current spec's loadouts
    local ctx = GetCurrentInstanceContext()
    if AutomationLive() and ReadDB().specSwap and ctx.inInstance then
        -- Re-run the swap for the new spec; it covers this place too.
        lastPlaceKey = BuildPlaceKey(ctx)
        QueueAutoCheck()
    end
    RequestRefresh()
end

-- Registered only while a talent load is in flight.
EVENT_HANDLERS.PLAYER_REGEN_DISABLED = function()
    HideSpecChangeWarning()
    local request = requests.talent
    if not (request and request.inFlight) or request.casting or request.callingLoad then return end
    if not request.commitCastGUID then
        -- Blizzard's queued load can refuse without a word; one that never
        -- started its commit cast by the time combat starts did not happen.
        Notify(request, EllesmereUI.Lf("Talent loadout %s did not load.", Bad(request.loadoutName)))
        FinishRequest(request)
    else
        CheckTalentCompletion(request, true)
    end
end

EVENT_HANDLERS.PLAYER_STOPPED_MOVING = function()
    ResumeRequests("availability")
end
EVENT_HANDLERS.PLAYER_UPDATE_RESTING = EVENT_HANDLERS.PLAYER_STOPPED_MOVING

EVENT_HANDLERS.ADDON_RESTRICTION_STATE_CHANGED = function(_, restriction, state)
    -- Only the lift of the restriction the talent swap waits on resumes it.
    -- The probe reads false during this dispatch, so the re-check runs next
    -- frame.
    local request = requests.talent
    if not request or issecretvalue(restriction) or issecretvalue(state) then return end
    if request.waitReason == "restricted" and state == Enum.AddOnRestrictionState.Inactive
        and restriction == Enum.AddOnRestrictionType[request.restriction] then
        ScheduleRequest(request)
    end
end

EVENT_HANDLERS.PLAYER_ALIVE = function()
    -- PLAYER_ALIVE also fires on release, when you are still a ghost.
    if not UnitIsDeadOrGhost("player") then ResumeRequests("alive") end
end
EVENT_HANDLERS.PLAYER_UNGHOST = EVENT_HANDLERS.PLAYER_ALIVE

EVENT_HANDLERS.CONFIG_COMMIT_FAILED = function(_, configID)
    TalentCommitFailed(requests.talent, configID)
end

local function OnTalentTreeEvent()
    local request = requests.talent
    if request and request.inFlight then ScheduleRequest(request, true) end
end
EVENT_HANDLERS.PLAYER_TALENT_UPDATE = OnTalentTreeEvent
EVENT_HANDLERS.TRAIT_NODE_CHANGED = OnTalentTreeEvent
EVENT_HANDLERS.TRAIT_TREE_CHANGED = OnTalentTreeEvent

-- Player casts: the talent commit cast, and the end of any cast an
-- availability wait (gear held by a cast) is waiting on.
local function OnCastEvent(event, unit, castGUID, spellID)
    TalentCastEvent(event, unit, castGUID, spellID)
    if event == "UNIT_SPELLCAST_STOP" then ResumeRequests("availability") end
end
for i = 1, #TALENT_CAST_EVENTS do EVENT_HANDLERS[TALENT_CAST_EVENTS[i]] = OnCastEvent end

EVENT_HANDLERS.EQUIPMENT_SWAP_FINISHED = function(_, _, setID)
    local request = requests.gear
    if not (request and request.verifying) or issecretvalue(setID) then return end
    -- Any finished swap settles the verify: ours, or another set's that took
    -- over (the check then reports what did not equip). Its time starts the
    -- verdict's short wait (VerifyEquippedSet).
    request.swapFinished = request.swapFinished or GetTime()
    ScheduleRequest(request, true)
end

-- Combat and resurrection waits have their own wake-up event.
local function OnGearChange()
    local request = requests.gear
    if request and (request.verifying or request.waitReason == "catalog" or request.waitReason == "availability") then
        ScheduleRequest(request)
    end
end
EVENT_HANDLERS.BAG_UPDATE_DELAYED = OnGearChange
EVENT_HANDLERS.PLAYER_EQUIPMENT_CHANGED = OnGearChange
EVENT_HANDLERS.EQUIPMENT_SETS_CHANGED = function()
    OnGearChange()
    RequestRefresh()
end

local function OnTalentCatalog(event, configID)
    local request = requests.talent
    if request then
        if event == "TRAIT_CONFIG_UPDATED" and request.inFlight then
            TalentCommitUpdated(request, configID)
        elseif event == "TRAIT_CONFIG_DELETED" and not issecretvalue(configID) and configID == request.configID then
            FinishRequest(request)
        elseif request.inFlight then
            ScheduleRequest(request, true)
        elseif request.waitReason == "catalog" or request.waitReason == "availability" then
            ScheduleRequest(request)
        end
    end
    RequestRefresh()
end
for i = 1, #TALENT_CATALOG_EVENTS do EVENT_HANDLERS[TALENT_CATALOG_EVENTS[i]] = OnTalentCatalog end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = EVENT_HANDLERS[event]
    if handler then handler(event, ...) end
end)

local registeredEvents = {}
local function SetEventState(event, wanted, playerOnly)
    wanted = wanted and true or false
    if (registeredEvents[event] or false) == wanted then return end
    registeredEvents[event] = wanted or nil
    if not wanted then
        eventFrame:UnregisterEvent(event)
    elseif playerOnly then
        eventFrame:RegisterUnitEvent(event, "player")
    else
        eventFrame:RegisterEvent(event)
    end
end

-- Each event is registered only for the phase that uses it.
UpdateRequestEvents = function()
    local gear, talent = requests.gear, requests.talent
    -- Context: live automation, a pending swap, or the open page. Coming back
    -- on, they start from where you are, so the next zone event compares
    -- against a current place.
    local context = AutomationLive() or gear or talent or pageShown
    if context and not registeredEvents.PLAYER_ENTERING_WORLD then NoteCurrentPlace() end
    SetEventState("PLAYER_ENTERING_WORLD", context)
    SetEventState("ZONE_CHANGED_NEW_AREA", context)
    SetEventState("CHALLENGE_MODE_START", context)
    SetEventState("PLAYER_SPECIALIZATION_CHANGED", context, true)
    -- Catalogs: a request on that channel, or the open page.
    SetEventState("EQUIPMENT_SETS_CHANGED", gear or pageShown)
    for i = 1, #TALENT_CATALOG_EVENTS do SetEventState(TALENT_CATALOG_EVENTS[i], talent or pageShown) end
    -- Gear: while a swap is verified, or waits on the catalog or availability.
    local gearWait = gear and (gear.verifying or gear.waitReason == "catalog" or gear.waitReason == "availability")
    SetEventState("EQUIPMENT_SWAP_FINISHED", gear and gear.verifying)
    SetEventState("BAG_UPDATE_DELAYED", gearWait)
    SetEventState("PLAYER_EQUIPMENT_CHANGED", gearWait)
    -- Talents: while a load is in flight.
    local inFlight = talent and talent.inFlight
    for i = 1, #TALENT_REQUEST_EVENTS do SetEventState(TALENT_REQUEST_EVENTS[i], inFlight) end
    SetEventState("PLAYER_REGEN_DISABLED", inFlight)
    -- Availability waits wake on movement, resting and the end of a cast.
    local availability = (gear and gear.waitReason == "availability") or (talent and talent.waitReason == "availability")
    for i = 1, #TALENT_CAST_EVENTS do
        local event = TALENT_CAST_EVENTS[i]
        SetEventState(event, inFlight or (availability and event == "UNIT_SPELLCAST_STOP"), true)
    end
    SetEventState("PLAYER_STOPPED_MOVING", availability)
    SetEventState("PLAYER_UPDATE_RESTING", availability)
    SetEventState("ADDON_RESTRICTION_STATE_CHANGED", talent and talent.waitReason == "restricted")
    local alive = (gear and gear.waitReason == "alive") or (talent and talent.waitReason == "alive")
    SetEventState("PLAYER_ALIVE", alive)
    SetEventState("PLAYER_UNGHOST", alive)
end

-- /elm opens the settings page, one frame later so the panel build stays out
-- of the chat edit box's execution.
local function OpenSettingsPage()
    if InCombatLockdown() then
        EllesmereUI.PrintError(EllesmereUI.L("Cannot open options during combat."))
        return
    end
    EllesmereUI:ShowModule(ADDON_NAME)
end
SLASH_EUILOADOUTMANAGER1 = "/elm"
SlashCmdList.EUILOADOUTMANAGER = function() C_Timer.After(0, OpenSettingsPage) end

-- -----------------------------------------------------------------------------
-- Module namespace: everything the options page drives
-- -----------------------------------------------------------------------------
ns.INSTANCE_TYPE_ORDER = INSTANCE_TYPE_ORDER

-- The settings as the page reads and writes them. Reading never creates the
-- saved table; a write does. Nested tables are read-only here: assignments
-- change through the actions below.
local DB_VIEW = setmetatable({}, {
    __index = function(_, key) return ReadDB()[key] end,
    __newindex = function(_, key, value) EnsureDB()[key] = value end,
})
function ns.DB() return DB_VIEW end

-- The page reports when it is on screen: the catalog and context events that
-- keep its rows live are registered only then, or for a pending swap.
function ns.SetPageShown(shown)
    shown = shown and true or false
    if pageShown == shown then return end
    pageShown = shown
    UpdateRequestEvents()
end

-- Selection + edit scope (the "Assign for" scope and the two pickers)
function ns.GetScope() return UI.assignScope end
function ns.SetScope(specID)
    UI.assignScope = specID
    assignVersion = assignVersion + 1
end
function ns.GetSelectedSet() return UI.selectedSet end
function ns.SetSelectedSet(name) UI.selectedSet = name end
function ns.GetSelectedTalent() return SelectedTalent() end
function ns.SetSelectedTalent(stored) UI.selectedTalent = stored end
function ns.TalentDisplayName(stored) return TalentDisplayName(stored) end
function ns.StoreTalentLoadout(loadout) return StoreTalentLoadout(loadout) end

-- Listings
function ns.GetSpecList() return GetSpecList() end
function ns.SpecName(specID) return SpecName(specID) end
function ns.GetCurrentSpecID() return GetCurrentSpecID() end
function ns.ListEquipmentSets() return ListEquipmentSetsDetailed() end
function ns.ListTalentLoadouts() return ListTalentLoadouts() end

-- Current context and what resolves for it. One context read per frame
-- serves every row of a page refresh (GetTime() is fixed within a frame).
local pageCtx, pageCtxStamp = {}, nil
function ns.GetContext()
    local now = GetTime()
    if pageCtxStamp ~= now then
        pageCtxStamp = now
        ReadContext(pageCtx)
    end
    return pageCtx
end
function ns.ResolveGear(ctx) return GetAssignedSetForContext(ctx or ns.GetContext()) end
function ns.ResolveTalent(ctx) return GetAssignedTalentForContext(ctx or ns.GetContext()) end

-- Reads for the settings page
function ns.ReadTables() return GetReadTables() end
function ns.ListInstanceAssignments() return ListInstanceAssignments() end
-- The key this instance's assignments are stored under (nil outside one),
-- and the name of the difficulty a per-difficulty assignment here covers.
function ns.AssignmentKey(ctx, perDifficulty)
    ctx = ctx or ns.GetContext()
    if not ctx.inInstance or not ctx.instanceID then return nil end
    if perDifficulty then return BuildDifficultyKey(ctx.instanceID, ctx.difficultyID) end
    return tostring(ctx.instanceID)
end
function ns.DifficultyName(ctx)
    ctx = ctx or ns.GetContext()
    return DifficultyName(AssignmentDifficulty(ctx.difficultyID))
end

-- Actions
function ns.CheckAndSwap() CheckAndSwap(true) end
function ns.EquipSelected()
    if KeystoneRunning() then return end -- nothing at all mid-key
    CancelRequests()
    local setName, talent = UI.selectedSet, SelectedTalent()
    if setName then TryEquipSet(BeginRequest("gear", setName, nil, true)) end
    if talent then
        TryLoadTalentLoadout(BeginRequest("talent", StoreTalentLoadout(NormalizeTalentStored(talent)), nil, true))
    end
end
function ns.AssignCurrent(perDifficulty)
    CancelRequests(true)
    local key = CurrentInstanceKey(perDifficulty)
    return key ~= nil and SaveSlot(key, false)
end
function ns.ClearCurrent(perDifficulty)
    CancelRequests(true)
    local key = CurrentInstanceKey(perDifficulty)
    return key ~= nil and ClearSlot(key, false)
end
function ns.ClearInstanceAssignment(key) CancelRequests(true); return ClearSlot(key, false) end
function ns.AssignType(key) CancelRequests(true); return SaveSlot(key, true) end
function ns.ClearType(key) CancelRequests(true); return ClearSlot(key, true) end
function ns.CopyScopeFrom(sourceID) CancelRequests(true); return CopyScopeFrom(sourceID) end

-- The master switch also decides which events are registered: route through here.
function ns.SetEnabled(value)
    CancelRequests()
    EnsureDB().enabled = value and true or false
    NoteCurrentPlace()
    UpdateRequestEvents()
    RequestRefresh()
end

function ns.SetChannelEnabled(kind, value)
    if kind ~= "gear" and kind ~= "talent" then return end
    local wasLive = AutomationLive()
    EnsureDB()[kind == "gear" and "gearEnabled" or "talentEnabled"] = value and true or false
    local request = requests[kind]
    if not value and request and not request.manual then FinishRequest(request) end
    -- Back from both channels off: start from where you are now.
    if not wasLive and AutomationLive() then NoteCurrentPlace() end
    UpdateRequestEvents()
    RequestRefresh()
end

function ns.SetQueueInCombat(value)
    EnsureDB().queueInCombat = value and true or false
    if not value then
        for _, kind in ipairs(REQUEST_KINDS) do
            local request = requests[kind]
            if request and request.waitReason == "combat" then FinishRequest(request) end
        end
    end
end

function ns.SetSpecWarning(value)
    EnsureDB().specWarning = value and true or false
    if not value then HideSpecChangeWarning() end
end
function ns.Verify() VerifyAssignments() end

-- Reset hook for the page's Reset button (onReset): the character's saved
-- table goes, and reads fall back to the defaults.
function ns.ResetAll()
    CancelRequests()
    EllesmereUILoadoutManagerDB = nil
    UI.selectedSet, UI.selectedTalent, UI.assignScope = nil, nil, nil
    assignVersion = assignVersion + 1
    NoteCurrentPlace()
    UpdateRequestEvents()
    RequestRefresh()
end

-- Saved variables are loaded here (the module's own ADDON_LOADED). A
-- character with automation on gets its events now; one that never changed
-- a setting keeps no saved table, since reading never creates it.
function LM:OnInitialize()
    UpdateRequestEvents()
end
