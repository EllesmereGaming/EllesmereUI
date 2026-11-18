if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Loadouts.lua  --  Loadout Manager
--  Equips an Equipment Manager gear set and loads a talent loadout as you
--  enter an activity. A loadout is a gear set, a talent loadout or both, and
--  the activities it applies to; each activity holds one loadout per spec.
--  Engine only: its tab on the AuraBuff Reminders page
--  (EUI_AuraBuffReminders_Loadouts_Options.lua) drives it through
--  ns.Loadouts. It runs on its own switch and shares nothing with the
--  reminders but the addon (it was a module of its own until 2026-11-17).
-------------------------------------------------------------------------------

local _, ns = ...
-- The addon whose page holds the tab, and the tab.
local ADDON_NAME = "EllesmereUIAuraBuffReminders"
local PAGE_NAME = "Loadout Manager"
local API = {}
ns.Loadouts = API

-- Both frames are born here, and both stay inert while the Loadout Manager is
-- off: the event frame registers events only for live automation, a pending
-- swap or the open tab, and the combat queue only while it holds a swap.
local CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))
local eventFrame = CreateFrame("Frame")
-- WoW Forever runs the talent channel on its dual spec (see "WoW Forever: dual spec").
local IS_FOREVER = EllesmereUI.IS_FOREVER and true or false

-- Chat colours follow the live EllesmereUI accent.
local function AC() return EllesmereUI.HexColor(EllesmereUI.GetAccentColor()) end
local ERR = EllesmereUI.COLOR_CODES.BAD
local function Hi(text) return AC() .. tostring(text) .. "|r" end
local function Bad(text) return ERR .. tostring(text) .. "|r" end
local NO_ENTRIES = {} -- read-only stand-in for a missing table in a loop

-- The GENERAL section's settings are account-wide (owner 2026-11-17), in
-- EllesmereUIDB.loadoutManager: read through Gen, written through SetGen.
local GENERAL_DEFAULTS = {
    -- Off until the user opts in; switching it on is what registers events.
    enabled = false,
    gearEnabled = true,
    talentEnabled = true,
    announce = true,
    queueInCombat = true,
    specSwap = true,     -- re-run swaps when your specialization changes inside an instance
    specWarning = true,  -- the DON'T MOVE panel while a talent loadout loads
    askBeforeSwap = false, -- a Yes / No prompt before every automatic swap (the Auto-Swap dropdown)
}

-- The Auto-Swap dropdown is a view over three of them: { gearEnabled,
-- talentEnabled, askBeforeSwap }. Ask Before Swap swaps both, after a Yes.
local SWAP_MODES = {
    ask    = { true, true, true },
    gear   = { true, false, false },
    talent = { false, true, false },
    both   = { true, true, false },
}

-- The activities a loadout applies to (owner 2026-11-17). Every place is one
-- activity at most (ActivityFor); a place that is none swaps nothing.
-- Retail: each of the season's Mythic+ dungeons on Mythic and in keys
-- ("d:<instanceID>"), this season's raids on Mythic and below it, every other
-- raid, each arena ("a:<instanceID>") and battleground ("b:<instanceID>") of
-- the Talent Reminders zone list, Timewalking, Delves and the open world. A
-- Normal or Heroic run of a season dungeon, the other dungeons and the
-- scenarios are none. WoW Forever: dungeons, raids, battlegrounds, the open
-- world and Riding (gear only: worn while mounted in the open world).
-- Labels are the tab's English text; L() translates them.
local ACTIVITY_LABELS = {
    raidm = "Raid (Mythic)", raidn = "Raid (Non-Mythic)", raidold = "Old Raids",
    tw = "Timewalking", delve = "Delves", pvp = "Battlegrounds",
    world = "Open World", dungeon = "Dungeons", raid = "Raids", riding = "Riding",
}
-- WoW Forever's activities in the tab's order (retail's tab lists its own
-- groups: the season's dungeons, the raids, the arenas and battlegrounds, then
-- the rest).
local ACTIVITY_ORDER = { "dungeon", "raid", "pvp", "world", "riding" }

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
-- The open Ask Before Swap prompt's handle (ShowConfirmPopup), if any.
local swapPrompt
local function CloseSwapPrompt()
    if not swapPrompt then return end
    local handle = swapPrompt
    swapPrompt = nil
    EllesmereUI:CloseConfirmPopup(handle)
end
-- True while the tab is on screen (API.SetPageShown).
local pageShown = false

-- The loadouts are this character's own, in the character roster's
-- "loadouts" field (EllesmereUI.CharData; never exported): { [bucket] = {
-- { gear = set name, talent = stored loadout, acts = { [activity] = true } },
-- ... } }. A bucket is a retail spec ID; WoW Forever's one bucket is 0 (its
-- talents are a spec group). Reading never creates the field.
local function Store(create) return EllesmereUI.CharData("loadouts", create) end

-- The account-wide GENERAL settings. Reading never creates the table; a
-- setting never changed reads its default.
local function Gen(key)
    local g = EllesmereUIDB and EllesmereUIDB.loadoutManager
    local v = g and g[key]
    if v == nil then return GENERAL_DEFAULTS[key] end
    return v
end
local function SetGen(key, value)
    local g = EllesmereUIDB.loadoutManager
    if type(g) ~= "table" then
        g = {}
        EllesmereUIDB.loadoutManager = g
    end
    g[key] = value
end

-- Automation can act: the Loadout Manager is on with at least one Auto-Swap channel.
local function AutomationLive()
    return (Gen("enabled") and (Gen("gearEnabled") or Gen("talentEnabled"))) and true or false
end

-- EllesmereUI's taint-safe print (it drops lines in raid and PvP combat and
-- during a running key).
local function Print(msg) EllesmereUI.Print(AC() .. EllesmereUI.L("Loadout Manager") .. ":|r", msg) end

local function Announce(msg)
    if Gen("announce") then Print(msg) end
end

-- Coalesce a burst of events into one refresh of the tab, and only while it
-- is on screen.
local refreshScheduled = false
local function FlushRefresh()
    refreshScheduled = false
    -- A value refresh repaints the page's live widgets; a forced rebuild
    -- would orphan any menu open on it.
    if API.OnStateChanged then API.OnStateChanged() end
end
local function RequestRefresh()
    if refreshScheduled or not pageShown then return end
    refreshScheduled = true
    C_Timer.After(0, FlushRefresh)
end

-- -----------------------------------------------------------------------------
-- WoW Forever: dual spec
-- Forever has one specialization per class and no saved loadouts. Its dual
-- spec is two spec groups (the talent window's Primary and Secondary tabs),
-- switched with a cast by C_SpecializationInfo.SetActiveSpecGroup. There the
-- talent channel picks a spec group: each unlocked group is listed as a
-- "loadout" whose configID is the negative group index (stable, never a real
-- config), named after its tab and the tree holding the most points.
-- The character's loadouts are one bucket there (0), each loadout's talents a
-- spec group. The negative active group still stands for the spec where a
-- place's context is compared, so a group switch re-runs the swaps like a
-- spec change does on retail.
-- -----------------------------------------------------------------------------


local function SpecGroupCount()
    local ok, n = pcall(GetNumSpecGroups)
    return (ok and type(n) == "number" and n > 0) and n or 1
end

local function ActiveSpecGroup()
    local ok, group = pcall(C_SpecializationInfo.GetActiveSpecGroup)
    if ok and type(group) == "number" then return group end
end

-- The tree with the most points in a group's build ("Holy"), or nil. The trees
-- come from the shared WoW Forever reader, names only.
local function ReadTopTree(group)
    local configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group)
    if not configID then return nil end
    local _, _, trees = EllesmereUI.ForeverTalentTrees(configID, true)
    if not trees then return nil end
    local ids = {}
    for i = 1, #trees do ids[i] = trees[i].groupID end
    local spentBy = {}
    for _, g in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or NO_ENTRIES) do
        local c = g.currencyInfos and g.currencyInfos[1]
        spentBy[g.traitNodeGroupID] = c and c.spent or 0
    end
    local best, bestSpent = nil, 0
    for i = 1, #trees do
        local spent = spentBy[trees[i].groupID] or 0
        if spent > bestSpent then best, bestSpent = trees[i].name, spent end
    end
    return best
end
local function SpecGroupTopTree(group)
    local ok, name = pcall(ReadTopTree, group)
    return ok and name or nil
end

local function SpecGroupName(group)
    local tab = group == 1 and (DUAL_SPEC_PRIMARY or EllesmereUI.L("Primary")) or (DUAL_SPEC_SECONDARY or EllesmereUI.L("Secondary"))
    local tree = SpecGroupTopTree(group)
    return tree and (tab .. " (" .. tree .. ")") or tab
end

local function SpecGroupOf(loadout)
    local id = loadout and tonumber(loadout.configID)
    if id and id < 0 then return -id end
end

-- The spec info call reports 0, not nil, for a slot with no specialization.
-- WoW Forever: the group switch the module last started ({ group, confirmed }),
-- until it lands or you change places. Its landing ends its own request (the
-- spec is part of a request's context), so the landing is matched here.
local ownSwitch = nil
local function GetCurrentSpecID()
    if IS_FOREVER then
        local group = ActiveSpecGroup()
        return group and -group or nil
    end
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then return nil end
    local specID = C_SpecializationInfo.GetSpecializationInfo(index)
    if specID and specID ~= 0 then return specID end
    return nil
end


-- -----------------------------------------------------------------------------
-- Specializations and buckets
-- A loadout belongs to the spec it was added on: its bucket is the spec ID on
-- retail (nil before the character has a spec), 0 on WoW Forever.
-- -----------------------------------------------------------------------------

local function BucketKey()
    if IS_FOREVER then return 0 end
    return GetCurrentSpecID()
end

-- A bucket's loadouts, read only (an empty stand-in for none).
local function BucketList(key)
    local store = key ~= nil and Store(false)
    local list = store and store[key]
    return type(list) == "table" and list or NO_ENTRIES
end

-- The spec list is fixed for the session: cache the first non-empty result
-- (it is empty until spec info loads).
local specListCache = nil
local function GetSpecList()
    if IS_FOREVER then
        -- Live: the second group unlocks mid-session and the names follow the build.
        local list = {}
        for group = 1, SpecGroupCount() do list[group] = { id = -group, name = SpecGroupName(group) } end
        return list
    end
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

-- The DON'T MOVE panel shown while a talent loadout loads.
local warningFrame = nil
HideSpecChangeWarning = function()
    if warningFrame then warningFrame:Hide() end
end

local function ShowSpecChangeWarning()
    if not Gen("specWarning") then return end
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

local function InstanceName(instanceID)
    local name = instanceID and GetRealZoneText(instanceID)
    if name and name ~= "" then return name end
    return EllesmereUI.Lf("Instance %s", tostring(instanceID))
end

-- An activity as the tab and the chat lines name it: a dungeon, arena or
-- battleground by its name (the game's, translated), the others by their label.
local function ActivityLabel(key)
    local id = type(key) == "string" and key:match("^[dab]:(%d+)$")
    if id then return InstanceName(tonumber(id)) end
    return EllesmereUI.L(ACTIVITY_LABELS[key] or tostring(key))
end

-- Fills ctx with where you are. GetCurrentInstanceContext reuses one table:
-- callers consume the result at once and never keep it.
local function ReadContext(ctx)
    local inInstance, instanceType = IsInInstance()
    local name, instanceType2, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    ctx.inInstance = inInstance
    ctx.instanceType = instanceType2 or instanceType or "none"
    ctx.name = name or EllesmereUI.L("Unknown")
    ctx.difficultyID = difficultyID
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
    if IS_FOREVER then return nil end -- a spec group switch is not a trait edit
    local ok, canEdit = pcall(C_ClassTalents.CanEditTalents)
    if not ok or canEdit == false then return "edit" end
end

-- Request lifecycle shared by gear and talents: a request is tied to its
-- context and to its Auto-Swap channel staying on.
RequestIsCurrent = function(request)
    if not request or requests[request.kind] ~= request then return false end
    if not (Gen("enabled") and Gen(request.kind == "gear" and "gearEnabled" or "talentEnabled")) then
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
    UpdateRequestEvents()
end

CancelRequests = function()
    autoCheckSerial = autoCheckSerial + 1
    CloseSwapPrompt()
    for _, kind in ipairs(REQUEST_KINDS) do
        local request = requests[kind]
        if request then FinishRequest(request) end
    end
end

local function BeginRequest(kind, value, reason)
    FinishRequest(requests[kind])
    local request = {
        kind = kind, value = value, reason = reason,
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
    -- The swap back out of the Riding set always waits: a dismount in combat
    -- would otherwise leave it on.
    if combat and not Gen("queueInCombat") and request.waitReason ~= "restricted" and not request.fromRiding then
        if not silent then
            if request.kind == "gear" then
                Announce(EllesmereUI.L("Gear swap skipped: you are in combat."))
            else
                Announce(EllesmereUI.L("Talent swap skipped: you are in combat."))
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
        Announce(message .. " " .. WaitSuffix(request))
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
    -- Already worn: nothing to do, nothing to wait for, nothing to say (most
    -- entries need no change).
    if isEquipped then
        FinishRequest(request)
        return
    end
    if InCombatLockdown() then
        DeferRequest(request, EllesmereUI.L("You are in combat."), true)
        return
    end
    if UnitIsDeadOrGhost("player") then
        DeferRequest(request, EllesmereUI.L("You are dead."), false, "alive", true)
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

    if IS_FOREVER then
        -- Spec groups in tab order, not by name.
        for group = 1, SpecGroupCount() do
            loadouts[#loadouts + 1] = { configID = -group, name = SpecGroupName(group), specID = specID }
        end
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
    return loadouts
end

local function GetTalentLoadoutInfoByID(configID)
    configID = tonumber(configID)
    if not configID then return nil end
    local specID = GetCurrentSpecID()
    if not specID then return nil end
    if IS_FOREVER then
        local group = -configID
        if group < 1 or group > SpecGroupCount() then return nil end
        return { configID = configID, name = SpecGroupName(group), specID = specID }
    end
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
    if not IS_FOREVER and stored.specID and currentSpec and tonumber(stored.specID) ~= tonumber(currentSpec) then return nil end

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
        -- A WoW Forever spec group belongs to no spec scope: any group's scope may assign it.
        specID = not IS_FOREVER and (loadout.specID or GetCurrentSpecID()) or nil,
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

-- A stored talent loadout is only usable by the spec it belongs to.
local function TalentMatchesSpec(stored, specID)
    if IS_FOREVER then return true end -- any spec group, from any group
    local sid = type(stored) == "table" and stored.specID or nil
    if not sid or not specID then return true end
    return tonumber(sid) == tonumber(specID)
end

-- Difficulty IDs that place a run in an activity. Timewalking keeps its
-- parent instance type and Delves report as scenarios, so both are told by
-- difficulty. A started key reports Mythic Keystone (8): the same activity as
-- the Mythic (23) you enter at, and swaps are locked mid-run anyway.
local MPLUS_DIFFICULTIES = { [8] = true, [23] = true }         -- Keystone, Mythic
local TIMEWALKING_DIFFICULTIES = { [24] = true, [33] = true } -- TW dungeon, TW raid
local DELVE_DIFFICULTIES = { [208] = true }                    -- Delves
local RAID_MYTHIC = 16

-- This season's raids, by instance ID: the Talent Reminders zone list, the
-- one place the season's raid is named (its SEASON UPDATE tag). Read on first
-- use; that file loads before this one.
local seasonRaids
local function SeasonRaid(instanceID)
    if not seasonRaids then
        seasonRaids = {}
        for _, z in ipairs(_G._EABR_TALENT_REMINDER_ZONES or NO_ENTRIES) do
            if z.type == "raid" and z.instanceID then seasonRaids[z.instanceID] = true end
        end
    end
    return seasonRaids[instanceID] == true
end

-- The arenas ("arena") and battlegrounds ("pvp") of the same list: each one's
-- instance ID, and the IDs another queue plays it under (alsoIDs), to its own.
-- A map the list does not hold keeps its own ID (no loadout can name it).
local pvpMapOf
local function PvpMap(kind, instanceID)
    if not pvpMapOf then
        pvpMapOf = { arena = {}, pvp = {} }
        for _, z in ipairs(_G._EABR_TALENT_REMINDER_ZONES or NO_ENTRIES) do
            local byID = pvpMapOf[z.type]
            if byID and z.instanceID then
                byID[z.instanceID] = z.instanceID
                for _, id in ipairs(z.alsoIDs or NO_ENTRIES) do byID[id] = z.instanceID end
            end
        end
    end
    return pvpMapOf[kind][instanceID] or instanceID
end

-- The activity a place is, or nil for none.
local function ActivityFor(ctx)
    if not ctx.inInstance then return "world" end
    local diff, kind = ctx.difficultyID, ctx.instanceType
    if IS_FOREVER then
        if kind == "party" then return "dungeon" end
        if kind == "raid" then return "raid" end
        if kind == "pvp" or kind == "arena" then return "pvp" end
        return nil
    end
    if diff and TIMEWALKING_DIFFICULTIES[diff] then return "tw" end
    if kind == "party" then
        if diff and MPLUS_DIFFICULTIES[diff] and ctx.instanceID then return "d:" .. ctx.instanceID end
        return nil
    end
    if kind == "raid" then
        if not ctx.instanceID then return nil end
        if SeasonRaid(ctx.instanceID) then return diff == RAID_MYTHIC and "raidm" or "raidn" end
        return "raidold"
    end
    if kind == "scenario" then return (diff and DELVE_DIFFICULTIES[diff]) and "delve" or nil end
    if (kind == "arena" or kind == "pvp") and ctx.instanceID then
        return (kind == "arena" and "a:" or "b:") .. PvpMap(kind, ctx.instanceID)
    end
    return nil
end

-- The loadout the current bucket holds for an activity, or nil.
local function LoadoutFor(act)
    if not act then return nil end
    local list = BucketList(BucketKey())
    for i = 1, #list do
        local lo = list[i]
        if type(lo.acts) == "table" and lo.acts[act] then return lo end
    end
end

-- What applies at a place: the value, "activity" and the activity's key, or
-- nil and why.
local function GetAssignedSetForContext(ctx)
    if ctx.inInstance and not ctx.instanceID then return nil, "missing-instance-id" end
    local act = ActivityFor(ctx)
    local lo = LoadoutFor(act)
    if lo and lo.gear then return lo.gear, "activity", act end
    return nil, "unassigned"
end

local function GetAssignedTalentForContext(ctx)
    if ctx.inInstance and not ctx.instanceID then return nil, "missing-instance-id" end
    local act = ActivityFor(ctx)
    local lo = LoadoutFor(act)
    if lo and lo.talent and TalentMatchesSpec(lo.talent, GetCurrentSpecID()) then return lo.talent, "activity", act end
    return nil, "unassigned"
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
    if IS_FOREVER then
        if ActiveSpecGroup() == request.group then
            CompleteTalentRequest(request)
        elseif final then
            FinishRequest(request)
        end
        return
    end
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
        Announce(EllesmereUI.Lf("Talent loadout %s did not fully apply.", Bad(request.loadoutName)))
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
    if unit ~= "player" then return end
    if not IS_FOREVER and spellID ~= Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID then return end
    if not RequestIsCurrent(request) or not request.inFlight then return end
    if IS_FOREVER then
        -- The spec switch cast has no known spell ID here: it is the first
        -- player cast to start once the switch was called (nothing else was
        -- casting then), and the rest of its events carry its GUID.
        if event == "UNIT_SPELLCAST_START" then
            if request.commitCastGUID then return end
        elseif not castGUID or castGUID ~= request.commitCastGUID then
            return
        end
    end
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
        if not quiet then Announce(EllesmereUI.L("Talent changes are locked once a PvP match starts. Talent swap skipped.")) end
        FinishRequest(request)
    elseif blocker == "combat" then
        DeferRequest(request, EllesmereUI.L("You are in combat."), true, nil, quiet)
    elseif blocker == "dead" then
        DeferRequest(request, EllesmereUI.L("You are dead."), false, "alive", true)
    elseif blocker == "edit" then
        DeferRequest(request, EllesmereUI.L("Talents cannot be changed here yet."), false, nil, quiet)
    else
        -- A restriction: resume when it lifts. An automatic swap waits out the
        -- Combat one (it outlasts lockdown by moments) and a PvP match
        -- clearing outside its arena or battleground without a word.
        request.restriction = blocker
        DeferRequest(request, RestrictionText(blocker), false, "restricted",
            quiet or blocker == "Combat" or blocker == "PvPMatch")
    end
end

-- WoW Forever: switch to the assigned spec group (see "WoW Forever: dual spec").
local function TryActivateSpecGroup(request)
    local blocker = TalentLoadBlocker()
    if blocker == "keystone" then FinishRequest(request) return end
    local stored = NormalizeTalentStored(request.value)
    local loadout = stored and GetTalentLoadoutFromStored(stored)
    local group = SpecGroupOf(loadout)
    if not group then
        Print(EllesmereUI.L("The assigned talent loadout was not found for your current specialization."))
        FinishRequest(request)
        return
    end
    request.configID, request.specID, request.loadoutName, request.group = loadout.configID, loadout.specID, loadout.name, group
    -- Already active: like a worn gear set, nothing to do or say.
    if ActiveSpecGroup() == group then
        FinishRequest(request)
        return
    end
    if blocker then
        HoldTalentRequest(request, blocker, false)
        return
    end
    -- The switch is a cast: it waits while you move (one that cannot start is
    -- never retried, and the next cast would be taken for it) and for any cast
    -- in progress to end. A restricted speed counts as standing still; the
    -- cast name can read secret: only its type is tested. The parentheses keep
    -- one value: with no cast, WoW Forever returns none at all and type() errors.
    local speed = GetUnitSpeed("player")
    if (not issecretvalue(speed) and (speed or 0) > 0)
        or type((UnitCastingInfo("player"))) ~= "nil" or type((UnitChannelInfo("player"))) ~= "nil" then
        DeferRequest(request, EllesmereUI.L("Talent swap held: you are moving or casting."), false, "availability")
        return
    end
    request.waitReason, request.restriction = nil, nil

    request.callingLoad, request.inFlight = true, true
    request.commitCastGUID, request.commitFailed, request.casting = nil, nil, nil
    request.commitCastSucceeded, request.commitSignal = nil, nil
    UpdateRequestEvents()
    ownSwitch = { group = group, confirmed = request.confirmed }
    local okCall = pcall(C_SpecializationInfo.SetActiveSpecGroup, group)
    request.callingLoad = nil
    if not RequestIsCurrent(request) then return end
    if not okCall or request.commitFailed then
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

TryLoadTalentLoadout = function(request)
    if not RequestIsCurrent(request) or request.inFlight then return end
    if IS_FOREVER then return TryActivateSpecGroup(request) end
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
        HoldTalentRequest(request, blocker, selected)
        return
    end
    if CommitCastRunning() then
        DeferRequest(request, EllesmereUI.L("Talent swap held: a talent change is in progress."), false, "availability")
        return
    end
    -- The load drops changes staged in the talent UI without the confirmation
    -- Blizzard's own loadout menu asks for, so an automatic swap waits, without
    -- a word while its loadout is selected (most likely in place already).
    if HasStagedTalentChanges(C_ClassTalents.GetActiveConfigID()) == true then
        DeferRequest(request, EllesmereUI.L("Talent swap held: you have unsaved talent changes."), false, "availability", selected)
        return
    end
    request.waitReason, request.restriction = nil, nil

    -- Already applied (selected, and its talents match the live build): like
    -- a worn gear set, nothing to load or say.
    request.talentSelection = nil
    if selected then
        request.talentSelection = GetTalentSelection(loadout.configID)
        if ActiveTalentsMatch(request) == true then
            FinishRequest(request)
            return
        end
    end

    if not HasUniqueLoadoutName(loadout) then
        Print(EllesmereUI.L("Talent swap skipped: another loadout has the same name. Rename one of them."))
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

-- Where a resolved loadout came from, for the swap's chat line: the
-- instance's name inside one, else the activity ("Open World", "Riding").
local function SourceLabel(ctx, source, key)
    if source == "dismount" then return EllesmereUI.L("dismounted") end
    if ctx.inInstance and ctx.name then return ctx.name end
    return ActivityLabel(key)
end

-- Whether equipping this set would change anything (reads the worn flag).
local function GearNeedsSwap(setName)
    if not setName then return false end
    local setID, _, isEquipped = GetSetInfoByName(strtrim(tostring(setName)))
    return not (setID and isEquipped)
end

-- Whether loading this talent loadout would change anything, so Ask Before
-- Swap never asks about talents already in place (logic of PR #2979 by
-- TzahalHPal). WoW Forever: the spec group. Retail: the applied tree against
-- the loadout's while nothing blocks reading it, else the selected loadout.
-- Anything unknown counts as a change: the prompt errs toward asking.
local function TalentNeedsSwap(stored)
    if not stored then return false end
    local loadout = GetTalentLoadoutFromStored(stored)
    if not loadout then return true end
    if IS_FOREVER then
        local group = SpecGroupOf(loadout)
        return group == nil or group ~= ActiveSpecGroup()
    end
    if TalentLoadBlocker() then
        return C_ClassTalents.GetLastSelectedSavedConfigID(loadout.specID) ~= loadout.configID
    end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if HasStagedTalentChanges(activeID) ~= false then return true end
    local target, active = GetTalentSelection(loadout.configID), GetTalentSelection(activeID)
    return not (target and active and target == active)
end

-- Ask Before Swap: a Yes / No prompt naming what would change. Yes runs
-- onYes (which checks you are still where you were asked); No, Escape or a
-- click outside skips the swap until the next one. A newer prompt, new
-- intent (CancelRequests) or the mode leaving Ask closes an open one without
-- an answer.
local function ShowSwapPrompt(where, setName, talentStored, onYes)
    CloseSwapPrompt()
    local lines = {}
    if setName then lines[#lines + 1] = EllesmereUI.Lf("Gear: %s", Hi(setName)) end
    if talentStored then
        lines[#lines + 1] = EllesmereUI.Lf("Talents: %s", Hi(TalentDisplayName(talentStored) or "?"))
    end
    local handle
    handle = EllesmereUI:ShowConfirmPopup({
        title       = "Loadout Manager",
        message     = EllesmereUI.Lf("Swap your loadout for %s?", where) .. "\n\n" .. table.concat(lines, "\n"),
        confirmText = "Yes",
        cancelText  = "No",
        onConfirm   = function()
            if swapPrompt ~= handle then return end
            swapPrompt = nil
            onYes()
        end,
        onCancel    = function()
            if swapPrompt ~= handle then return end
            swapPrompt = nil
            Announce(EllesmereUI.Lf("Swap skipped for %s.", where))
        end,
    })
    swapPrompt = handle
end

-- Riding (WoW Forever only): a gear set worn while mounted in the open world
-- (riding trinkets and the like). It outranks the Open World default for as long as you are
-- mounted; on dismount that default comes back, or with none assigned the set
-- that was worn when the Riding set went on.
local ridingOn, ridingReturn

-- The gear set of the loadout that holds Riding (gear only).
local function RidingSet()
    local list = BucketList(BucketKey())
    for i = 1, #list do
        local lo = list[i]
        if type(lo.acts) == "table" and lo.acts.riding and lo.gear then return lo.gear end
    end
end

-- The mount event is heard only while it can do something: the gear channel
-- on, and a loadout holding Riding (or its set worn, so a set deleted while
-- riding still comes off at the dismount).
local function RidingWatchWanted()
    if not IS_FOREVER then return false end
    if not (Gen("enabled") and Gen("gearEnabled")) then return false end
    return (ridingOn or RidingSet() ~= nil) and true or false
end

-- The Riding set, when it applies here and now. Notes the set it replaces.
local function RidingSetNow(ctx)
    if not IS_FOREVER or ctx.inInstance or not IsMounted() then return nil end
    local riding = RidingSet()
    if not riding then return nil end
    if not ridingOn and GearNeedsSwap(riding) then
        ridingReturn = nil
        local wanted = strtrim(tostring(riding)):lower()
        for _, setID in ipairs(GetEquipmentSetIDs() or NO_ENTRIES) do
            local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
            if name and isEquipped and name:lower() ~= wanted then ridingReturn = name break end
        end
    end
    ridingOn = true
    return riding
end

-- Mounting and dismounting move the gear channel only: a talent request in
-- flight is left alone.
local function OnMountChanged()
    if not (Gen("enabled") and Gen("gearEnabled")) or KeystoneRunning() then return end
    local ctx = GetCurrentInstanceContext()
    if ctx.inInstance then
        ridingOn, ridingReturn = nil, nil
        return
    end
    local setName, source, key = RidingSetNow(ctx), "activity", "riding"
    if not setName then
        if not ridingOn or IsMounted() then return end
        setName, source, key = GetAssignedSetForContext(ctx)
        if not setName then setName, source, key = ridingReturn, "dismount", nil end
        ridingOn, ridingReturn = nil, nil
        -- A Riding set cleared while riding: nothing left to hear.
        UpdateRequestEvents()
    end
    if setName and GearNeedsSwap(setName) then
        local fromRiding = not ridingOn
        local function Equip()
            local request = BeginRequest("gear", setName, SourceLabel(ctx, source, key))
            request.fromRiding = fromRiding
            TryEquipSet(request)
        end
        if not Gen("askBeforeSwap") then return Equip() end
        -- Ask Before Swap: Yes counts only while you are still mounted (or
        -- still not), outside an instance and no key has started.
        local mounted = IsMounted() and true or false
        ShowSwapPrompt(ActivityLabel(mounted and "riding" or "world"), setName, nil, function()
            if (IsMounted() and true or false) ~= mounted or KeystoneRunning() then return end
            if GetCurrentInstanceContext().inInstance then return end
            Equip()
        end)
    end
end

-- gearOnly: a recheck after a WoW Forever spec group switch. It applies the
-- new group's gear and never switches talents again (no ping-pong, and a
-- switch you made yourself is never undone). confirmed: Ask Before Swap's Yes
-- (or the Yes that started this spec group switch).
local CheckAndSwap
CheckAndSwap = function(gearOnly, confirmed)
    if not Gen("enabled") then return end
    if KeystoneRunning() then return end -- gear and talents are locked mid-key
    -- This check expresses new intent, including the absence of an assignment.
    -- Cancel an older request before resolving the new context.
    CancelRequests()

    local ctx = GetCurrentInstanceContext()
    local setName, gearSource, gearKey, talentStored, talentSource, talentKey
    if Gen("gearEnabled") then setName, gearSource, gearKey = GetAssignedSetForContext(ctx) end
    if Gen("talentEnabled") and not gearOnly then talentStored, talentSource, talentKey = GetAssignedTalentForContext(ctx) end
    -- WoW Forever: after a spec group switch, a loadout's gear follows only
    -- while its talents are that group (or it has none): a loadout of the other
    -- group waits for its own switch, so a group you picked yourself keeps its gear.
    if gearOnly and IS_FOREVER and setName then
        local stored = GetAssignedTalentForContext(ctx)
        local group = stored and SpecGroupOf(GetTalentLoadoutFromStored(stored))
        if group and group ~= ActiveSpecGroup() then setName = nil end
    end
    -- WoW Forever: a talent assignment that switches spec groups brings the
    -- target group's gear: no gear is equipped now, and the group change
    -- re-runs the check, gear only, once the switch lands.
    local gearAfterSwitch
    if IS_FOREVER and talentStored then
        local target = SpecGroupOf(GetTalentLoadoutFromStored(talentStored))
        gearAfterSwitch = target ~= nil and target ~= ActiveSpecGroup()
    end
    -- Mounted in the open world, the Riding set stands in for the place's gear.
    if Gen("gearEnabled") and not gearAfterSwitch then
        local riding = RidingSetNow(ctx)
        if riding then setName, gearSource, gearKey = riding, "activity", "riding" end
    end
    -- Nothing assigned here: silent (most places have nothing assigned).
    if not setName and not talentStored then return end

    -- Ask Before Swap: a swap that would change something waits for a Yes,
    -- wherever it happens.
    if not confirmed and Gen("askBeforeSwap") then
        local gearAsk = setName and not gearAfterSwitch and GearNeedsSwap(setName) and setName or nil
        local talentAsk = TalentNeedsSwap(talentStored) and talentStored or nil
        if gearAsk or talentAsk then
            local key = BuildAutoInstanceKey(ctx)
            local where = ctx.inInstance and ctx.name
                or ActivityLabel((setName and gearKey == "riding") and "riding" or "world")
            ShowSwapPrompt(where, gearAsk, talentAsk, function()
                -- Still where (and on the spec) you were asked.
                if key ~= BuildAutoInstanceKey(GetCurrentInstanceContext()) then return end
                CheckAndSwap(gearOnly, true)
            end)
            return
        end
    end

    if setName and not gearAfterSwitch then
        TryEquipSet(BeginRequest("gear", setName, SourceLabel(ctx, gearSource, gearKey)))
    end
    if talentStored then
        local request = BeginRequest("talent", StoreTalentLoadout(NormalizeTalentStored(talentStored)),
            SourceLabel(ctx, talentSource, talentKey))
        request.confirmed = confirmed
        TryLoadTalentLoadout(request)
    end
end

-- One automatic check per frame: the latest request wins, and CancelRequests
-- (which bumps the serial) drops one still queued.
-- opts (WoW Forever group switches): gearOnly, confirmed.
local autoCheckQueued, autoCheckQueuedSerial, autoCheckKey, autoCheckOpts = false, nil, nil, nil
local function RunAutoCheck()
    autoCheckQueued = false
    local opts = autoCheckOpts or NO_ENTRIES
    if autoCheckQueuedSerial ~= autoCheckSerial or not AutomationLive() then return end
    if autoCheckKey ~= BuildAutoInstanceKey(GetCurrentInstanceContext()) then return end
    CheckAndSwap(opts.gearOnly, opts.confirmed)
end

local function QueueAutoCheck(opts)
    autoCheckSerial = autoCheckSerial + 1
    autoCheckQueuedSerial = autoCheckSerial
    autoCheckOpts = opts
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
    ownSwitch = nil
    -- Switched off, nothing runs.
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

-- -----------------------------------------------------------------------------
-- Loadouts: what the tab adds and deletes, and what it shows as missing
-- -----------------------------------------------------------------------------

local function SameTalent(a, b)
    if a == nil or b == nil then return a == b end
    return tonumber(a.configID) == tonumber(b.configID) and a.name == b.name
end

-- Adds a loadout to the current bucket for the activities in acts (a set).
-- An activity holds one loadout per bucket: one another loadout held moves
-- here, and a loadout left with none goes. A loadout with the same gear and
-- talents takes the activities instead of a second one. Returns true, or
-- false and why: "empty" (no gear and no talents), "noacts", "ridinggear"
-- (Riding needs a gear set), "nospec" or "nochar" (the character's data is
-- not readable yet).
local function AddLoadout(gear, talent, acts)
    if gear == nil and talent == nil then return false, "empty" end
    if type(acts) ~= "table" or not next(acts) then return false, "noacts" end
    if acts.riding and not gear then return false, "ridinggear" end
    local key = BucketKey()
    if key == nil then return false, "nospec" end
    local store = Store(true)
    if not store then return false, "nochar" end
    local list = store[key]
    if type(list) ~= "table" then
        list = {}
        store[key] = list
    end
    for i = #list, 1, -1 do
        local held = list[i].acts
        if type(held) == "table" then
            for act in pairs(acts) do held[act] = nil end
        end
        if type(held) ~= "table" or not next(held) then table.remove(list, i) end
    end
    local target
    for i = 1, #list do
        if list[i].gear == gear and SameTalent(list[i].talent, talent) then target = list[i]; break end
    end
    if not target then
        target = { gear = gear, talent = talent, acts = {} }
        list[#list + 1] = target
    end
    for act in pairs(acts) do target.acts[act] = true end
    return true
end

-- Deletes one loadout of a bucket, or the whole bucket (index nil); a bucket
-- left empty goes.
local function DeleteLoadouts(key, index)
    local store = Store(false)
    local list = store and store[key]
    if type(list) ~= "table" then return false end
    if index then
        if not list[index] then return false end
        table.remove(list, index)
        if #list > 0 then return true end
    end
    store[key] = nil
    return true
end

-- A saved gear set the Equipment Manager no longer has; nil while its sets
-- are still loading.
local function GearMissing(name)
    if not name then return false end
    if not EquipmentCacheReady(true) then return nil end
    return not SetExists(name)
end

-- A saved talent loadout its spec no longer has; nil while that is unknown.
local function TalentMissing(stored)
    stored = NormalizeTalentStored(stored)
    if not stored then return false end
    local configID = tonumber(stored.configID)
    if IS_FOREVER then
        local group = configID and -configID
        return not (group and group >= 1 and group <= SpecGroupCount())
    end
    local specID = tonumber(stored.specID)
    if not specID then return nil end
    local ok, ids = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not ok or type(ids) ~= "table" or #ids == 0 then return nil end
    for i = 1, #ids do
        if ids[i] == configID then return false end
    end
    -- One renamed or made again under the same name still loads (by name).
    if specID == GetCurrentSpecID() and GetTalentLoadoutFromStored(stored) then return false end
    return true
end

-- -----------------------------------------------------------------------------
-- Events
-- -----------------------------------------------------------------------------

local TALENT_CATALOG_EVENTS = {
    "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_CREATED", "TRAIT_CONFIG_DELETED",
    "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "SELECTED_LOADOUT_CHANGED",
}
local TALENT_REQUEST_EVENTS = { "CONFIG_COMMIT_FAILED", "PLAYER_TALENT_UPDATE", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CHANGED" }
-- WoW Forever: the events a spec group switch fires, also watched while
-- automation is live (each stays on its own list above).
local FOREVER_GROUP_EVENTS = IS_FOREVER and { PLAYER_TALENT_UPDATE = true, ACTIVE_COMBAT_CONFIG_CHANGED = true } or {}
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
local function OnSpecChanged()
    local specID = GetCurrentSpecID()
    if specID == lastSpecID then return end
    local known = lastSpecID ~= nil
    lastSpecID = specID
    if not known then return end
    -- WoW Forever: the module's own group switch just landed.
    local own = IS_FOREVER and ownSwitch and ownSwitch.group == ActiveSpecGroup() and ownSwitch or nil
    ownSwitch = nil
    CancelRequests()
    local ctx = GetCurrentInstanceContext()
    if own then
        -- Its gear follows, without another switch.
        lastPlaceKey = BuildPlaceKey(ctx)
        QueueAutoCheck({ gearOnly = true, confirmed = own.confirmed })
    elseif AutomationLive() and Gen("specSwap") and (ctx.inInstance or IS_FOREVER) then
        -- Re-run the swap for the new spec; it covers this place too. On
        -- WoW Forever a group you switched to yourself is never switched
        -- back, and a loadout's gear follows only while it is that group's.
        lastPlaceKey = BuildPlaceKey(ctx)
        QueueAutoCheck(IS_FOREVER and { gearOnly = true } or nil)
    end
    RequestRefresh()
end
EVENT_HANDLERS.PLAYER_SPECIALIZATION_CHANGED = OnSpecChanged

-- Registered only while a talent load is in flight.
EVENT_HANDLERS.PLAYER_REGEN_DISABLED = function()
    HideSpecChangeWarning()
    local request = requests.talent
    if not (request and request.inFlight) or request.casting or request.callingLoad then return end
    if not request.commitCastGUID then
        -- Blizzard's queued load can refuse without a word; one that never
        -- started its commit cast by the time combat starts did not happen.
        Announce(EllesmereUI.Lf("Talent loadout %s did not load.", Bad(request.loadoutName)))
        FinishRequest(request)
    else
        CheckTalentCompletion(request, true)
    end
end

EVENT_HANDLERS.PLAYER_MOUNT_DISPLAY_CHANGED = OnMountChanged

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
-- WoW Forever: a spec group switch (ours or yours) is a spec change. It also
-- fires ACTIVE_COMBAT_CONFIG_CHANGED, handled with the catalog events.
if IS_FOREVER then
    local function OnForeverTalentEvent()
        OnTalentTreeEvent()
        OnSpecChanged()
    end
    EVENT_HANDLERS.PLAYER_TALENT_UPDATE = OnForeverTalentEvent
end

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
    if IS_FOREVER and event == "ACTIVE_COMBAT_CONFIG_CHANGED" then OnSpecChanged() end
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
    -- Context: live automation or a pending swap. Coming back on, they start
    -- from where you are, so the next zone event compares against a current
    -- place. The open page needs no zone event (it shows no place), only the
    -- spec: its talent list and its first card are your spec's.
    local context = AutomationLive() or gear or talent
    local specWatch = context or pageShown
    if context and not registeredEvents.PLAYER_ENTERING_WORLD then NoteCurrentPlace() end
    SetEventState("PLAYER_ENTERING_WORLD", context)
    SetEventState("ZONE_CHANGED_NEW_AREA", context)
    SetEventState("CHALLENGE_MODE_START", context)
    SetEventState("PLAYER_MOUNT_DISPLAY_CHANGED", RidingWatchWanted())
    SetEventState("PLAYER_SPECIALIZATION_CHANGED", specWatch, true)
    -- Catalogs: a request on that channel, or the open page.
    SetEventState("EQUIPMENT_SETS_CHANGED", gear or pageShown)
    for i = 1, #TALENT_CATALOG_EVENTS do
        local event = TALENT_CATALOG_EVENTS[i]
        SetEventState(event, talent or pageShown or (FOREVER_GROUP_EVENTS[event] and specWatch))
    end
    -- Gear: while a swap is verified, or waits on the catalog or availability.
    local gearWait = gear and (gear.verifying or gear.waitReason == "catalog" or gear.waitReason == "availability")
    SetEventState("EQUIPMENT_SWAP_FINISHED", gear and gear.verifying)
    SetEventState("BAG_UPDATE_DELAYED", gearWait)
    SetEventState("PLAYER_EQUIPMENT_CHANGED", gearWait)
    -- Talents: while a load is in flight.
    local inFlight = talent and talent.inFlight
    for i = 1, #TALENT_REQUEST_EVENTS do
        local event = TALENT_REQUEST_EVENTS[i]
        SetEventState(event, inFlight or (FOREVER_GROUP_EVENTS[event] and specWatch))
    end
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

-- /elm opens the tab, one frame later so the panel build stays out of the
-- chat edit box's execution; the tab is selected once the page is up.
local function OpenSettingsPage()
    if InCombatLockdown() then
        EllesmereUI.PrintError(EllesmereUI.L("Cannot open options during combat."))
        return
    end
    EllesmereUI:ShowModule(ADDON_NAME)
    C_Timer.After(0, function()
        if EllesmereUI:GetActiveModule() == ADDON_NAME and EllesmereUI:GetActivePage() ~= PAGE_NAME then
            EllesmereUI:SelectPage(PAGE_NAME)
        end
    end)
end
SLASH_EUILOADOUTMANAGER1 = "/elm"
SlashCmdList.EUILOADOUTMANAGER = function() C_Timer.After(0, OpenSettingsPage) end

-- -----------------------------------------------------------------------------
-- ns.Loadouts: everything the tab drives
-- -----------------------------------------------------------------------------

-- The GENERAL settings as the tab reads and writes them (account-wide).
local DB_VIEW = setmetatable({}, {
    __index = function(_, key) return Gen(key) end,
    __newindex = function(_, key, value) SetGen(key, value) end,
})
function API.DB() return DB_VIEW end

-- The tab reports when it is on screen: the catalog and spec events that
-- keep its pickers and cards live are registered only then, or for a pending swap.
function API.SetPageShown(shown)
    shown = shown and true or false
    if pageShown == shown then return end
    pageShown = shown
    UpdateRequestEvents()
end

-- Listings
function API.GetSpecList() return GetSpecList() end
function API.SpecName(specID) return SpecName(specID) end
function API.GetCurrentSpecID() return GetCurrentSpecID() end
function API.BucketKey() return BucketKey() end
function API.ListEquipmentSets() return ListEquipmentSetsDetailed() end
function API.ListTalentLoadouts() return ListTalentLoadouts() end
function API.StoreTalentLoadout(loadout) return StoreTalentLoadout(loadout) end
function API.TalentDisplayName(stored) return TalentDisplayName(stored) end
function API.ActivityLabel(key) return ActivityLabel(key) end
function API.ActivityOrder() return ACTIVITY_ORDER end
-- Every bucket's loadouts, read only: { [bucket] = { loadout, ... } }.
function API.Buckets()
    local store = Store(false)
    return type(store) == "table" and store or NO_ENTRIES
end
-- The current bucket's loadout holding an activity, or nil.
function API.HolderOf(act) return LoadoutFor(act) end
function API.GearMissing(name) return GearMissing(name) end
function API.TalentMissing(stored) return TalentMissing(stored) end

-- This season's Mythic+ dungeons, { id = instance ID, name } in name order,
-- from the game's own season list, kept once it answers; until then the
-- Talent Reminders zone list's dungeons stand in.
local seasonDungeons
function API.SeasonDungeons()
    if seasonDungeons then return seasonDungeons end
    local list, seen = {}, {}
    local ok, maps = pcall(C_ChallengeMode.GetMapTable)
    local fromGame = ok and type(maps) == "table" and #maps > 0
    if fromGame then
        for _, mapID in ipairs(maps) do
            local okInfo, _, _, _, _, _, instanceID = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
            if okInfo and type(instanceID) == "number" and not seen[instanceID] then
                seen[instanceID] = true
                list[#list + 1] = { id = instanceID, name = InstanceName(instanceID) }
            end
        end
    end
    if #list == 0 then
        fromGame = false
        for _, z in ipairs(_G._EABR_TALENT_REMINDER_ZONES or NO_ENTRIES) do
            if z.type == "dungeon" and z.instanceID and not seen[z.instanceID] then
                seen[z.instanceID] = true
                list[#list + 1] = { id = z.instanceID, name = InstanceName(z.instanceID) }
            end
        end
    end
    table.sort(list, ByNameLowerAsc)
    if fromGame then seasonDungeons = list end
    return list
end

-- The arenas (kind "arena") or battlegrounds ("pvp") of the Talent Reminders
-- zone list, { id = instance ID, name } in name order, by the game's names;
-- kept once every name has loaded.
local pvpMaps = {}
function API.PvpMaps(kind)
    if pvpMaps[kind] then return pvpMaps[kind] end
    local list, named = {}, true
    for _, z in ipairs(_G._EABR_TALENT_REMINDER_ZONES or NO_ENTRIES) do
        if z.type == kind and z.instanceID then
            local name = GetRealZoneText(z.instanceID)
            if not name or name == "" then named = false end
            list[#list + 1] = { id = z.instanceID, name = InstanceName(z.instanceID) }
        end
    end
    table.sort(list, ByNameLowerAsc)
    if named then pvpMaps[kind] = list end
    return list
end

-- The activity of where you are (nil for none), Talent Reminders' read of a
-- place too: one context read per frame (GetTime() is fixed within a frame).
local pageCtx, pageCtxStamp = {}, nil
function API.Activity()
    local now = GetTime()
    if pageCtxStamp ~= now then
        pageCtxStamp = now
        ReadContext(pageCtx)
    end
    return (not pageCtx.inInstance or pageCtx.instanceID) and ActivityFor(pageCtx) or nil
end

-- An edit is new intent: an automatic swap in flight ends, and a Riding
-- loadout added or deleted turns the mount event on or off.
local function Edited()
    CancelRequests()
    UpdateRequestEvents()
end
function API.AddLoadout(gear, talent, acts)
    local ok, why = AddLoadout(gear, talent, acts)
    if ok then Edited() end
    return ok, why
end
function API.DeleteLoadout(key, index)
    local ok = DeleteLoadouts(key, index)
    if ok then Edited() end
    return ok
end
function API.ClearBucket(key)
    local ok = DeleteLoadouts(key, nil)
    if ok then Edited() end
    return ok
end

-- The master switch also decides which events are registered: route through here.
function API.SetEnabled(value)
    CancelRequests()
    SetGen("enabled", value and true or false)
    NoteCurrentPlace()
    UpdateRequestEvents()
    RequestRefresh()
end

-- The Auto-Swap dropdown: "ask", "gear", "talent" or "both".
function API.GetSwapMode()
    if Gen("askBeforeSwap") then return "ask" end
    local gear, talent = Gen("gearEnabled"), Gen("talentEnabled")
    if gear and not talent then return "gear" end
    if talent and not gear then return "talent" end
    return "both"
end
function API.SetSwapMode(mode)
    local m = SWAP_MODES[mode]
    if not m then return end
    local wasLive = AutomationLive()
    SetGen("gearEnabled", m[1])
    SetGen("talentEnabled", m[2])
    SetGen("askBeforeSwap", m[3])
    -- A channel switched off ends its automatic request; leaving Ask closes
    -- an open prompt without swapping (the next swap runs on its own).
    for _, kind in ipairs(REQUEST_KINDS) do
        local request = requests[kind]
        if request and not Gen(kind == "gear" and "gearEnabled" or "talentEnabled") then
            FinishRequest(request)
        end
    end
    if not m[3] then CloseSwapPrompt() end
    if not wasLive and AutomationLive() then NoteCurrentPlace() end
    UpdateRequestEvents()
    RequestRefresh()
end

function API.SetQueueInCombat(value)
    SetGen("queueInCombat", value and true or false)
    if not value then
        for _, kind in ipairs(REQUEST_KINDS) do
            local request = requests[kind]
            if request and request.waitReason == "combat" then FinishRequest(request) end
        end
    end
end

function API.SetSpecWarning(value)
    SetGen("specWarning", value and true or false)
    if not value then HideSpecChangeWarning() end
end

-- The AuraBuff Reminders module reset: the account-wide GENERAL settings and
-- this character's loadouts go (other characters keep theirs).
function API.ResetAll()
    CancelRequests()
    EllesmereUIDB.loadoutManager = nil
    local guid = EllesmereUI.CharGUID()
    if guid then EllesmereUI.ForgetCharField(guid, "loadouts") end
    NoteCurrentPlace()
    UpdateRequestEvents()
    RequestRefresh()
end

-- At login, once the roster can be read: both Auto-Swap channels off (the old
-- checkbox dropdown allowed it) swapped nothing, and the dropdown has no such
-- choice, so it becomes the Loadout Manager off with both channels back,
-- which swaps nothing either. Then what live automation needs is registered.
local function Init()
    if Gen("gearEnabled") == false and Gen("talentEnabled") == false then
        SetGen("enabled", false)
        SetGen("gearEnabled", true)
        SetGen("talentEnabled", true)
    end
    UpdateRequestEvents()
end
EVENT_HANDLERS.PLAYER_LOGIN = function()
    SetEventState("PLAYER_LOGIN", false)
    Init()
end
if IsLoggedIn() then Init() else SetEventState("PLAYER_LOGIN", true) end
