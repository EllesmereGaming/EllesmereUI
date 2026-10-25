if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_Where.lua
--  Where to Show (Mythic+ Tools): the content bucket and combat state that
--  every Mythic+ Tools feature with a Where to Show filter reads, and the one
--  location/combat watcher those features share (ns.MTWhere).
--
--  Zero cost while unused: the watcher frame is built on the first feature's
--  subscribe and registers nothing before it, and unregisters everything once
--  the last one leaves. Each feature walks its own key set, so a bucket its filter does not
--  offer never hides it.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local MTWhere = {}
ns.MTWhere = MTWhere

-- The nameplate unit tokens, as the ordered list and the set, for every
-- feature that walks or recognizes plates (this file loads first).
local NAMEPLATE_TOKENS, NAMEPLATE_UNITS = {}, {}
for i = 1, 40 do
    local token = "nameplate" .. i
    NAMEPLATE_TOKENS[i] = token
    NAMEPLATE_UNITS[token] = true
end
ns.NAMEPLATE_TOKENS, ns.NAMEPLATE_UNITS = NAMEPLATE_TOKENS, NAMEPLATE_UNITS

-- Every location bucket Bucket() can answer. A feature's filter offers all of
-- them or a subset (NewKeySet).
MTWhere.LOCATION_KEYS = {
    "open_world", "raid_mythic", "raid_heroic", "raid_normal_lfr",
    "dungeon_mythic", "dungeon_nonmythic", "timewalking", "delve", "lair",
    "scenario", "arena", "battleground",
}

-- A feature's location keys: the list its filter walks plus a lookup set.
-- Built once per feature at file load.
function MTWhere.NewKeySet(list)
    local set = {}
    for i = 1, #list do set[list[i]] = true end
    return { list = list, set = set }
end

--------------------------------------------------------------------------------
--  Content bucket
--------------------------------------------------------------------------------
local function Bucket()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return "dungeon_mythic"
    end
    -- Housing plots report as "scenario"; they belong to the open world.
    if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
        return "open_world"
    end
    local _, iType, diffID, _, _, _, _, _, _, _, hasWorldTier = GetInstanceInfo()
    diffID = tonumber(diffID) or 0
    -- Lairs carry the World Tier flag instead of a difficulty id the branches
    -- below know; the instance gate keeps the flag from ever reclassifying
    -- the open world, whatever else it may be set on.
    if hasWorldTier == true and iType ~= "none" then return "lair" end
    if iType == "party" then
        if diffID == 23 or diffID == 8 then return "dungeon_mythic" end
        if diffID == 2 or diffID == 1 or diffID == 205 then return "dungeon_nonmythic" end
        if diffID == 24 then return "timewalking" end
    elseif iType == "raid" then
        if diffID == 16 or diffID == 233 then return "raid_mythic" end
        if diffID == 15 or diffID == 6 then return "raid_heroic" end
        if diffID == 14 or diffID == 3 or diffID == 4 or diffID == 5
            or diffID == 17 or diffID == 7 then return "raid_normal_lfr" end
        if diffID == 33 then return "timewalking" end
    elseif iType == "scenario" then
        if diffID == 208 then return "delve" end
        return "scenario"
    elseif iType == "arena" then
        return "arena"
    elseif iType == "pvp" then
        return "battleground"
    end
    if IsInInstance and not IsInInstance() then return "open_world" end
    return nil -- unmapped content -- always shows, matching AuraBuffReminders
end
MTWhere.Bucket = Bucket

--------------------------------------------------------------------------------
--  Combat state is TRACKED from PLAYER_REGEN_DISABLED / _ENABLED instead of
--  sampled inside the gate: a live lockdown read is the one input here that
--  can answer differently (or as a secret) inside restricted instanced combat,
--  and a wrong answer at that moment leaves a feature switched off for the
--  whole fight. The edges are exact everywhere, so the seed only has to cover
--  login/zoning and the moment the watcher arms.
--------------------------------------------------------------------------------
local inCombat = false

local function ReadCombatFlag()
    if not InCombatLockdown then return false end
    local ok, v = pcall(InCombatLockdown)
    if not ok then return false end
    if issecretvalue then
        local sok, secret = pcall(issecretvalue, v)
        if sok and secret then return false end
    end
    return v and true or false
end

function MTWhere.InCombat()
    return inCombat
end

--------------------------------------------------------------------------------
--  Positive filter: nothing selected = no filter (shows everywhere). Selected
--  location buckets limit WHERE, the two combat entries limit WHEN, and the
--  two groups AND together. Unmapped content, and a bucket the caller's key
--  set does not offer, never hide.
--------------------------------------------------------------------------------
function MTWhere.Shows(whereToShow, keySet)
    if not whereToShow or not next(whereToShow) then return true end
    local wantIn  = whereToShow.in_combat == true
    local wantOut = whereToShow.out_of_combat == true
    if wantIn ~= wantOut then
        if inCombat ~= wantIn then return false end
    end
    local keys = keySet.list
    local anyLoc = false
    for i = 1, #keys do
        if whereToShow[keys[i]] == true then anyLoc = true; break end
    end
    if not anyLoc then return true end
    local bucket = Bucket()
    if not bucket or not keySet.set[bucket] then return true end
    return whereToShow[bucket] == true
end

--------------------------------------------------------------------------------
--  Shared watcher: one frame for every subscribed feature, registered only
--  while at least one subscriber exists. Each zone/combat edge updates the
--  combat flag first, then calls every subscriber with the event name.
--------------------------------------------------------------------------------
local WHERE_EVENTS = {
    "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET", "PLAYER_DIFFICULTY_CHANGED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local subFns   = {}  -- [i] = subscriber fn
local subKeys  = {}  -- [i] = key of subFns[i]
local subIndex = {}  -- key -> i

-- Backward walk: a subscriber that unsubscribes itself from inside its
-- callback swaps the last entry, already called, into its own slot. Each
-- call goes through securecallfunction, so an error in one feature is
-- reported and the others still see the edge.
local securecallfunction = securecallfunction
local function Dispatch(event)
    for i = #subFns, 1, -1 do
        local fn = subFns[i]
        if fn then securecallfunction(fn, event) end
    end
end

-- GetInstanceInfo() can still report the PREVIOUS zone on the first frame
-- after a loading screen, which resolves the wrong content bucket and leaves
-- a feature deactivated in a zone its filter actually allows (same read
-- hazard AuraBuffReminders defers 0.5s for). Re-check once the client has
-- settled: every subscriber is called once more with "RECHECK", and its sync
-- only flips the feature when the answer actually changed.
local recheckPending = false
local function Recheck()
    recheckPending = false
    Dispatch("RECHECK")
end

local whereEvt  -- the watcher frame; built on the first subscribe

local function OnWhereEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombat = ReadCombatFlag()
    end
    Dispatch(event)
    if event == "PLAYER_ENTERING_WORLD" and not recheckPending then
        recheckPending = true
        C_Timer.After(0.5, Recheck)
    end
end

-- Subscribing an existing key replaces its fn. The first subscriber builds
-- the watcher if needed, arms it and seeds the combat flag; the regen edges
-- keep it exact from there.
function MTWhere.Subscribe(key, fn)
    if not fn then
        MTWhere.Unsubscribe(key)
        return
    end
    local i = subIndex[key]
    if i then
        subFns[i] = fn
        return
    end
    i = #subFns + 1
    subFns[i] = fn
    subKeys[i] = key
    subIndex[key] = i
    if i == 1 then
        if not whereEvt then
            whereEvt = CreateFrame("Frame")
            whereEvt:SetScript("OnEvent", OnWhereEvent)
        end
        inCombat = ReadCombatFlag()
        for j = 1, #WHERE_EVENTS do whereEvt:RegisterEvent(WHERE_EVENTS[j]) end
    end
end

-- The last subscriber leaving unregisters the watcher.
function MTWhere.Unsubscribe(key)
    local i = subIndex[key]
    if not i then return end
    local n = #subFns
    subFns[i], subKeys[i] = subFns[n], subKeys[n]
    subIndex[subKeys[i]] = i
    subFns[n], subKeys[n] = nil, nil
    subIndex[key] = nil
    if n == 1 then whereEvt:UnregisterAllEvents() end
end
