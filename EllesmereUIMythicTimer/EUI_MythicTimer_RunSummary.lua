if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_RunSummary.lua -- Run Summary (Mythic+ Tools): end-of-key
--  overview with one row per party member, plus a per character history of
--  finished runs (/ov). Nothing is registered or built until enabled.
--  Sources: C_ChallengeMode for the run and the local player's score delta,
--  C_DamageMeter for every per player combat number (no combat log in
--  Midnight), rating summaries sampled before and after for party score gain.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local db  -- Lite DB handle, handed over by ns.RS_OnEnable

local SV_NAME = "EllesmereUIMythicRunsDB"
local SCHEMA  = 1

local UNIT_TOKENS = { "player", "party1", "party2", "party3", "party4" }

local DM_TYPE     = Enum and Enum.DamageMeterType
local DM_SESSION  = Enum and Enum.DamageMeterSessionType
local SESSION_OVERALL = DM_SESSION and DM_SESSION.Overall

-- Interrupts and deaths arrive as totalAmount under their own meter type;
-- there is no count field on a combat source.
local METRICS = {
    { key = "damage",      dmType = DM_TYPE and DM_TYPE.DamageDone  },
    { key = "damageTaken", dmType = DM_TYPE and DM_TYPE.DamageTaken },
    { key = "interrupts",  dmType = DM_TYPE and DM_TYPE.Interrupts  },
    -- One source row per death, most recent first; a real death carries a
    -- deathRecapID and totalAmount is not a count, so rows are counted.
    { key = "deaths",      dmType = DM_TYPE and DM_TYPE.Deaths, countRows = true },
}

-- Declared up here rather than with the rest of the collector state: the meter
-- harvest below banks class and spec onto it and must see it as an upvalue.
local roster              -- [guid] = member record

local ShowWindow          -- assigned further down, once the panel is defined
local RefreshWindowIfOpen -- same
local ApplyPosition       -- same

--------------------------------------------------------------------------------
--  Small helpers
--------------------------------------------------------------------------------
local function Cfg()
    local p = db and db.profile
    return p and p.runSummary
end

local function Enabled()
    local c = Cfg()
    return c and c.enabled == true
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function PlainNumber(v)
    if type(v) == "number" and not IsSecret(v) then return v end
    return nil
end

local function PlainString(v)
    if type(v) == "string" and not IsSecret(v) and v ~= "" then return v end
    return nil
end

--------------------------------------------------------------------------------
--  Store: a per character SavedVariable, deliberately NOT the profile DB.
--  EUILite's logout StripDefaults pass and the profile export/import machinery
--  both treat profile data as settings, so run records do not belong there.
--  Same split as EllesmereUIChat's scrollback history.
--------------------------------------------------------------------------------
local function GetSV()
    local sv = _G[SV_NAME]
    if type(sv) ~= "table" then sv = {}; _G[SV_NAME] = sv end
    if type(sv.runs) ~= "table" then sv.runs = {} end
    -- Stamped only when absent. Writing it on every read would relabel older
    -- records as current and leave a future migration nothing to branch on.
    if sv.schema == nil then sv.schema = SCHEMA end
    return sv
end

local function HistorySize()
    local c = Cfg()
    local n = c and tonumber(c.historySize) or 20
    if n < 5 then n = 5 elseif n > 50 then n = 50 end
    return n
end

local function StoreRun(record)
    if type(record) ~= "table" then return end
    local sv = GetSV()
    table.insert(sv.runs, 1, record)
    local cap = HistorySize()
    for i = #sv.runs, cap + 1, -1 do
        sv.runs[i] = nil
    end
end

function ns.RS_GetRuns()
    return GetSV().runs
end

function ns.RS_ClearHistory()
    local sv = GetSV()
    wipe(sv.runs)
    if RefreshWindowIfOpen then RefreshWindowIfOpen() end
end

-- Season purge: drop records for dungeons that are no longer in the pool, the
-- same shape EMT:OnInitialize already uses for bestObjectiveSplits.
local function PurgeOldSeasons()
    local sv = _G[SV_NAME]
    if type(sv) ~= "table" or type(sv.runs) ~= "table" then return end
    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then return end
    local valid = {}
    for _, mapID in ipairs(maps) do valid[mapID] = true end
    for i = #sv.runs, 1, -1 do
        local rec = sv.runs[i]
        local mapID = rec and tonumber(rec.mapID)
        if not mapID or not valid[mapID] then
            table.remove(sv.runs, i)
        end
    end
end

--------------------------------------------------------------------------------
--  C_DamageMeter harvest. Every GetCombatSession* call is SecretWhenInCombat
--  and declassification lags regen, so every field is guarded and the caller
--  retries once. Overall totals are diffed against a baseline taken at key
--  start rather than trusted to be empty: EllesmereUIDamageMeters resets the
--  sessions on CHALLENGE_MODE_START and may simply not be loaded.
--------------------------------------------------------------------------------
local function MeterAvailableIsTrue()
    return C_DamageMeter.IsDamageMeterAvailable() == true
end

local function MeterReady()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return false end
    if SESSION_OVERALL == nil then return false end
    if not C_DamageMeter.IsDamageMeterAvailable then return true end
    -- The truthiness test runs inside the pcall so a raise cannot take the
    -- whole harvest with it.
    local ok, ready = pcall(MeterAvailableIsTrue)
    return ok and ready == true
end

local function WalkSources(session, totals, perSec, identityRoster, countRows)
    local n = 0
    for _, src in ipairs(session.combatSources) do
        n = n + 1
        local guid  = PlainString(src.sourceGUID)
        local total = PlainNumber(src.totalAmount)
        if countRows then
            local rid = PlainNumber(src.deathRecapID)
            if guid and rid and rid > 0 then totals[guid] = (totals[guid] or 0) + 1 end
        elseif guid and total then
            totals[guid] = total
            if perSec then perSec[guid] = PlainNumber(src.amountPerSecond) end
        end
        if identityRoster and guid and identityRoster[guid] then
            local rec = identityRoster[guid]
            rec.specIcon = rec.specIcon or PlainNumber(src.specIconID)
            rec.class    = rec.class or PlainString(src.classFilename)
        end
    end
    return n
end

-- Fills totals[guid] and, when perSec is given, perSec[guid]. Returns false if
-- the session could not be read at all, else true plus how many source rows
-- the session held (nil when the walk raised), so an empty session can be
-- told apart from rows that are still classified.
-- identityRoster, when given, also banks classFilename and specIconID onto it.
-- Both are NeverSecret, so they read even when the amounts beside them do not.
local function HarvestTotals(dmType, totals, perSec, identityRoster, countRows)
    if dmType == nil then return false end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, SESSION_OVERALL, dmType)
    if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then
        return false
    end
    -- The whole walk sits inside the pcall, not just the call that produced
    -- the session: type() answers "table" for a secret table too, so indexing
    -- one raises rather than reading nil.
    local walked, rows = pcall(WalkSources, session, totals, perSec, identityRoster, countRows)
    return true, walked and rows or nil
end

local function SessionDuration()
    if not (C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds) then return nil end
    if SESSION_OVERALL == nil then return nil end
    -- One argument only: the session type. There is no meter type parameter.
    local ok, dur = pcall(C_DamageMeter.GetSessionDurationSeconds, SESSION_OVERALL)
    if not ok then return nil end
    return PlainNumber(dur)
end

--------------------------------------------------------------------------------
--  Collector state
--------------------------------------------------------------------------------
local frame             -- built on first enable
local collecting        -- true between CHALLENGE_MODE_START and the panel showing
local rosterOrder       -- ordered guids
local baseTotals        -- [metricKey][guid] = total at key start
local baseDuration      -- Overall session duration at key start
local hasBaseline       -- false when the key start sample failed or was skipped
local inspectPending    -- guid of the outstanding NotifyInspect
-- Meter resets mid-key (another meter resetting after each pull, a Reset
-- button, Blizzard's auto-reset) would cut the Overall session short, so the
-- run banks what the meter gained at each checkpoint (a pull ended and the
-- combat restriction lifted) and folds it in on a reset:
--   bank[metric][guid] = gains banked before a reset, bankDur = their seconds,
--   snap[metric][guid] = Overall totals at the last checkpoint, snapDur = its
--   duration, unbanked = a pull began since that checkpoint, gaps = a reset
--   landed on unbanked gains (the run's numbers are short).
-- The finished run carries it on (lastRun.seg) while it waits for the meter.
local seg

-- Everything the finishing phase needs, captured when the key completes and
-- deliberately out of ResetCollector's reach. The key resets behind us on the
-- way out of the instance while the run is still waiting on the meter, on the
-- chest and on the late score push, so none of that may live in state the
-- reset wipes.
local lastRun           -- { record, rst, ord, base, baseDur, based, seg, awaitingMeter, lootArmed, settled }

-- Collecting-phase state only. The finished run lives in lastRun.
local function ResetCollector()
    collecting    = false
    roster        = {}
    rosterOrder   = {}
    baseTotals    = {}
    baseDuration  = nil
    hasBaseline   = false
    inspectPending = nil
    seg = { bank = {}, snap = {}, bankDur = 0, unbanked = false, gaps = false }
end
ResetCollector()

local function EnsureMember(guid)
    local rec = roster[guid]
    if not rec then
        rec = { guid = guid }
        roster[guid] = rec
        rosterOrder[#rosterOrder + 1] = guid
    end
    return rec
end

local function StillIs(rec)
    if not (rec and rec.unit and rec.guid) then return false end
    if not UnitExists(rec.unit) then return false end
    return PlainString(UnitGUID(rec.unit)) == rec.guid
end

-- Item link straight out of a chat line. Matching the hyperlink rather than the
-- sentence keeps this independent of client language.
local function LinkFromText(text)
    if type(text) ~= "string" or IsSecret(text) then return nil end
    return text:match("(|c%x+|Hitem:.-|h.-|h|r)") or text:match("(|Hitem:.-|h.-|h)")
end

-- Bonus roll loot is announced through CHAT_MSG_LOOT like the chest's, and only
-- the sentence tells them apart. The client's own localized strings become the
-- patterns, so this holds in every client language.
local IsBonusRollLine
do
    local BONUS_KEYS = {
        "LOOT_ITEM_BONUS_ROLL", "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
        "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
    }
    local patterns

    local function ToPattern(fmt)
        local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
        p = p:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
        return "^" .. p:gsub("\1", ".+"):gsub("\2", "%%d+")
    end

    function IsBonusRollLine(text)
        if type(text) ~= "string" or IsSecret(text) then return false end
        if not patterns then
            patterns = {}
            for _, key in ipairs(BONUS_KEYS) do
                local fmt = _G[key]
                if type(fmt) == "string" and fmt ~= "" then
                    patterns[#patterns + 1] = ToPattern(fmt)
                end
            end
        end
        for i = 1, #patterns do
            if text:find(patterns[i]) then return true end
        end
        return false
    end
end

local function IDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("|Hitem:(%d+)"))
end

-- Records a looted item against a roster member, found by GUID when we have one
-- and by short name otherwise. Never overwrites an item already recorded.
local ITEM_CLASS   = Enum and Enum.ItemClass
local ITEM_QUALITY = Enum and Enum.ItemQuality
local GetInstant = C_Item.GetItemInfoInstant

local ITEM_BIND   = Enum and Enum.ItemBind
local GetFullInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- A Warbound until Equipped item reports bindType OnEquip, so the predicate
-- has to run first: the bind type alone only catches the fully bound ones.
local function IsWarboundLoot(info)
    if not info then return false end
    if C_Item and C_Item.IsItemBindToAccountUntilEquip
        and C_Item.IsItemBindToAccountUntilEquip(info) == true then
        return true
    end
    if ITEM_BIND and GetFullInfo then
        local bind = PlainNumber(select(14, GetFullInfo(info)))
        if bind and (bind == ITEM_BIND.ToWoWAccount
            or bind == ITEM_BIND.ToBnetAccount
            or bind == ITEM_BIND.ToBnetAccountUntilEquipped) then
            return true
        end
    end
    return false
end

-- The column is for the chest's gear. Keystones, quest items, housing decor,
-- reagents and anything below epic arrive through the same loot channels and
-- are skipped. Quality is read from the link where there is one, since bonus
-- IDs can raise it; an item not yet cached reports no quality and is let
-- through on its equip slot alone.
local function IsExcludedLootID(id, link)
    if not id then return true end
    if id == 180653 then return true end
    if C_Item and C_Item.IsItemKeystoneByID and C_Item.IsItemKeystoneByID(id) == true then
        return true
    end
    if IsWarboundLoot(link or id) then return true end
    if GetInstant then
        local _, _, _, equipLoc, _, classID = GetInstant(id)
        classID = PlainNumber(classID)
        if ITEM_CLASS and (classID == ITEM_CLASS.Questitem or classID == ITEM_CLASS.Housing) then
            return true
        end
        equipLoc = PlainString(equipLoc)
        if not equipLoc or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return true end
    end
    if ITEM_QUALITY and C_Item and C_Item.GetItemQualityByID then
        local q = PlainNumber(C_Item.GetItemQualityByID(link or id))
        if q and q < ITEM_QUALITY.Epic then return true end
    end
    return false
end

local function IsExcludedLoot(link)
    if link:find("|Hkeystone:", 1, true) then return true end
    return IsExcludedLootID(IDFromLink(link), link)
end

local function RecordLoot(rst, ord, guid, name, link)
    if not (rst and ord and link) then return false end
    if IsExcludedLoot(link) then return false end
    local rec = guid and rst[guid]
    if not rec and name then
        local short = name:match("^([^%-]+)") or name
        for _, g in ipairs(ord) do
            local r = rst[g]
            if r and r.name and (r.name:match("^([^%-]+)") or r.name) == short then
                rec = r
                break
            end
        end
    end
    if not rec then return false end
    -- The chest reward is the item the column is for: a link gets in only when
    -- it is that same item, carrying the level and bonuses the ID has not got.
    if rec.lootChest then
        if rec.lootLink or IDFromLink(link) ~= rec.lootID then return false end
        rec.lootLink = link
        return true
    end
    if rec.lootLink then return false end
    rec.lootLink = link
    rec.lootID   = IDFromLink(link) or rec.lootID
    return true
end

local function ScoreFor(unit)
    if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then return nil end
    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    if not ok or type(summary) ~= "table" then return nil end
    return PlainNumber(summary.currentSeasonScore)
end

-- Walks Blizzard's own five token list. Fills anything still missing; never
-- overwrites a value already captured, so a member who leaves after completion
-- keeps the data collected while they were present.
local function ScanRoster(withStartScore)
    for _, unit in ipairs(UNIT_TOKENS) do
        if UnitExists(unit) then
            local guid = PlainString(UnitGUID(unit))
            if guid then
                local rec = EnsureMember(guid)
                rec.unit = unit
                rec.name = rec.name or PlainString(UnitName(unit))
                if not rec.class then
                    local _, classFile = UnitClass(unit)
                    rec.class = PlainString(classFile)
                end
                if UnitGroupRolesAssignedEnum then
                    rec.role = PlainNumber(UnitGroupRolesAssignedEnum(unit)) or rec.role
                end
                if withStartScore and rec.scoreStart == nil then
                    rec.scoreStart = ScoreFor(unit)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Inspect queue: item level and spec icon. GetInspectItemLevel reads whichever
--  player the client currently has cached, so exactly one inspect may be
--  outstanding at a time. The queue sweeps every few seconds during the key and
--  stops once everyone has both values. Taking the spec icon from here rather
--  than from the meter means it does not depend on the meter at all.
--------------------------------------------------------------------------------
local function OwnSpecIcon()
    local CSI = C_SpecializationInfo
    if not (CSI and CSI.GetSpecialization and CSI.GetSpecializationInfo) then return nil end
    local idx = CSI.GetSpecialization()
    if not idx then return nil end
    local _, _, _, icon = CSI.GetSpecializationInfo(idx)
    return PlainNumber(icon)
end

-- GetSpecializationInfoForSpecID is the documented name; the ByID global is
-- undocumented but still present and used elsewhere in the suite, so it stays
-- as the fallback.
local function SpecIconForSpecID(specID)
    if not specID or specID == 0 then return nil end
    local fn = GetSpecializationInfoForSpecID or GetSpecializationInfoByID
    if not fn then return nil end
    return PlainNumber(select(4, fn(specID)))
end

local function InspectSpecIcon(unit)
    local CSI = C_SpecializationInfo
    if not (CSI and CSI.GetInspectSpecialization) then return nil end
    return SpecIconForSpecID(PlainNumber(CSI.GetInspectSpecialization(unit)))
end

local function OwnItemLevel()
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        local v = PlainNumber(equipped)
        if v and v > 0 then return math.floor(v) end
    end
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local v = PlainNumber(C_PaperDollInfo.GetInspectItemLevel("player"))
        if v and v > 0 then return math.floor(v) end
    end
    return nil
end

local INSPECT_MAX_TRIES = 8

local function NeedsInspect(rec)
    return not rec.ilvl or not rec.specIcon
end

-- The roster being worked on: the live one during the key, then the finished
-- run's snapshot while it settles, when the group stands at the chest out of
-- combat and in range -- the best inspect window of the whole run.
local function InspectRoster()
    if collecting then return roster, rosterOrder end
    if lastRun and not lastRun.settled then return lastRun.rst, lastRun.ord end
    return nil
end

-- Event driven: INSPECT_READY chains to the next member; a pull ending, a
-- roster change or the loot window closing restarts it. Fewest attempts goes
-- first, so one player out of range cannot starve everyone behind them.
local function InspectSweep()
    local rst, ord = InspectRoster()
    if not rst then return end

    local missing = false
    for _, guid in ipairs(ord) do
        local rec = rst[guid]
        if rec then
            if rec.unit == "player" then
                rec.ilvl     = rec.ilvl or OwnItemLevel()
                rec.specIcon = rec.specIcon or OwnSpecIcon()
            end
            if NeedsInspect(rec) then missing = true end
        end
    end
    if not missing or inspectPending or InCombatLockdown()
        or (InspectFrame and InspectFrame:IsShown()) then
        return
    end

    local pick, fewest
    for _, guid in ipairs(ord) do
        local rec = rst[guid]
        local tries = rec and (rec.inspectTries or 0)
        if rec and rec.unit ~= "player" and NeedsInspect(rec)
            and tries < INSPECT_MAX_TRIES and StillIs(rec)
            and UnitIsVisible(rec.unit) and CanInspect(rec.unit)
            and (fewest == nil or tries < fewest) then
            pick, fewest = rec, tries
        end
    end
    if not pick then return end
    pick.inspectTries = fewest + 1
    inspectPending = pick.guid
    if ClearInspectPlayer then ClearInspectPlayer() end
    NotifyInspect(pick.unit)
end

-- Returns true when it filled something in.
local function OnInspectReady(guid)
    guid = PlainString(guid)
    if not guid then return false end
    if inspectPending == guid then inspectPending = nil end
    local rst = InspectRoster()
    local rec = rst and rst[guid]
    if not rec or not UnitTokenFromGUID then return false end
    local unit = PlainString(UnitTokenFromGUID(guid))
    if not unit or not UnitExists(unit) then return false end
    local changed = false
    if not rec.ilvl and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local val = PlainNumber(C_PaperDollInfo.GetInspectItemLevel(unit))
        if val and val > 0 then
            rec.ilvl = math.floor(val)
            changed = true
        end
    end
    if not rec.specIcon then
        rec.specIcon = InspectSpecIcon(unit)
        changed = changed or rec.specIcon ~= nil
    end
    return changed
end

--------------------------------------------------------------------------------
--  Run lifecycle
--------------------------------------------------------------------------------
-- While a Combat or ChallengeMode restriction is up, the meter's source rows
-- read classified (sourceGUID and totalAmount come back secret), so a harvest
-- banks nothing. Declassification lags the end of combat, which is exactly the
-- window CHALLENGE_MODE_COMPLETED lands in.
local RESTRICTION_KINDS = { "Combat", "ChallengeMode" }
local function RestrictionActive()
    local CRA = C_RestrictedActions
    if not (CRA and CRA.IsAddOnRestrictionActive and Enum.AddOnRestrictionType) then
        return false
    end
    for _, kind in ipairs(RESTRICTION_KINDS) do
        local t = Enum.AddOnRestrictionType[kind]
        if t ~= nil and CRA.IsAddOnRestrictionActive(t) == true then return true end
    end
    return false
end

-- The finished run is "settling" from completion until we leave the instance:
-- the meter may still be classified, party scores arrive late, and loot is
-- announced as the chest is opened. Leaving the instance ends it.
local function Settling()
    return lastRun ~= nil and not lastRun.settled
end

local function SetEvent(event, on)
    if on then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
end

-- Every registration derives from state here, so no path can leave an event
-- registered or dropped out of step. Loot has three sources, none complete:
-- the rewards payload (our own item), ENCOUNTER_LOOT_RECEIVED (docs say args
-- 5/6 are itemName/fileName; BossBannerToast binds playerName/className) and
-- CHAT_MSG_LOOT (looter GUID in arg 12). Bonus roll loot is dropped: from the
-- chat line for everyone, and from BONUS_ROLL_RESULT for our own roll.
local function SyncEvents()
    if not frame then return end
    local on       = Enabled() == true
    local settling = on and Settling()
    local waiting  = settling and lastRun.awaitingMeter == true
    SetEvent("CHALLENGE_MODE_START", on)
    SetEvent("CHALLENGE_MODE_COMPLETED", on)
    SetEvent("CHALLENGE_MODE_RESET", on)
    SetEvent("INSPECT_READY", on and (collecting or settling))
    SetEvent("GROUP_ROSTER_UPDATE", on and (collecting or settling))
    SetEvent("CHALLENGE_MODE_MEMBER_INFO_UPDATED", on and (collecting or settling))
    SetEvent("PLAYER_REGEN_ENABLED", on and (collecting or settling))
    -- While the key runs, and while the finished run still waits for the
    -- meter: the combat restriction's edges are the per-pull checkpoints, and
    -- a meter reset folds into the bank (see seg).
    local keyRunning = on and collecting and not lastRun
    SetEvent("ADDON_RESTRICTION_STATE_CHANGED", waiting or keyRunning)
    SetEvent("DAMAGE_METER_RESET", waiting or keyRunning)
    SetEvent("CHALLENGE_MODE_COMPLETED_REWARDS", settling)
    SetEvent("ENCOUNTER_LOOT_RECEIVED", settling)
    SetEvent("CHAT_MSG_LOOT", settling)
    SetEvent("BONUS_ROLL_RESULT", settling)
    SetEvent("LOOT_CLOSED", settling)
    SetEvent("PLAYER_ENTERING_WORLD", settling)
end

-- skipBaseline is for the recovery path at CHALLENGE_MODE_COMPLETED, where a
-- reload lost the key start. Sampling a baseline there would bank the finished
-- run's own totals and make every delta zero; with none, the deltas are the
-- Overall session, which is the closest honest answer available.
local function StartCollecting(skipBaseline)
    -- A new key supersedes anything the previous one was still waiting for.
    lastRun = nil
    ResetCollector()
    collecting = true
    ScanRoster(true)
    if not skipBaseline and MeterReady() then
        local allRead = true
        for _, m in ipairs(METRICS) do
            local t = {}
            if not HarvestTotals(m.dmType, t, nil, nil, m.countRows) then allRead = false end
            baseTotals[m.key] = t
        end
        -- Right after the reset at key start there is no session yet and the
        -- duration reads nil; that is an empty session, so it counts as zero.
        baseDuration = SessionDuration() or 0
        -- An unread baseline is not a zero baseline: without this flag a failed
        -- read silently turns into "the whole session counts as this run".
        hasBaseline = allRead
        -- The first checkpoint is the baseline itself, so a reset before the
        -- first pull (a meter clearing itself at key start) banks nothing.
        for _, m in ipairs(METRICS) do
            local s = {}
            for guid, v in pairs(baseTotals[m.key]) do s[guid] = v end
            seg.snap[m.key] = s
        end
        seg.snapDur = baseDuration
    end
    SyncEvents()
    InspectSweep()
end

-- Leaves the finish watch alone on purpose: the key resetting behind us is
-- normal on the way out of the instance, and the finished run is still waiting
-- for the meter to declassify. It holds its own roster snapshot, so the wipe
-- below cannot reach it.
local function StopCollecting()
    ResetCollector()
    SyncEvents()
end

-- Reads the four meter types, subtracts the key start baseline, adds what was
-- banked before any mid-key meter reset (see seg) and writes the numbers onto
-- the run's roster. Baseline and bank are passed in rather than read from the
-- live upvalues: retries land after the key has reset, which wipes them.
local scratchTotals, scratchPerSec = {}, {}

local function HarvestInto(record, rst, base, baseDur, based, sg)
    rst  = rst or roster
    base = base or baseTotals
    if baseDur == nil then baseDur = baseDuration end
    if based == nil then based = hasBaseline end
    sg = sg or seg
    if not MeterReady() then
        -- Must be recorded here too, or the panel shows empty combat columns
        -- with no word of why the meter had nothing to give.
        record.meterAvailable = false
        return false
    end

    local totals, perSec = scratchTotals, scratchPerSec
    local okAny = false
    local matched = 0
    local duration = SessionDuration()
    local deltaDuration
    -- Without a trustworthy key start sample the session duration covers
    -- everything since login, so it must not be used as the run's duration.
    -- amountPerSecond is Blizzard's own figure and is the honest fallback.
    if based and baseDur then
        local live = (duration and duration > baseDur) and (duration - baseDur) or 0
        local d = live + sg.bankDur
        if d > 0 then deltaDuration = d end
    end
    record.hasBaseline = based and true or false
    -- A mid-key meter reset cost a pull no checkpoint had banked.
    if sg.gaps then record.meterGaps = true end

    for _, m in ipairs(METRICS) do
        wipe(totals); wipe(perSec)
        local isDamage = (m.key == "damage")
        local read, rows = HarvestTotals(m.dmType, totals, isDamage and perSec or nil, isDamage and rst or nil, m.countRows)
        if read then
            okAny = true
            local b = base[m.key]
            local bk = sg.bank[m.key]
            -- Members with banked gains but no row since the reset still count.
            -- When the meter sits empty since a reset that landed after the last
            -- checkpoint, the bank IS the whole run, so it matches on its own.
            if bk then
                local complete = isDamage and rows == 0 and not sg.unbanked
                for guid, v in pairs(bk) do
                    local rec = rst[guid]
                    if rec and totals[guid] == nil then
                        rec[m.key] = v
                        if isDamage and deltaDuration and deltaDuration > 1 then
                            rec.dps = v / deltaDuration
                        end
                        if complete then matched = matched + 1 end
                    end
                end
            end
            for guid, total in pairs(totals) do
                local rec = rst[guid]
                if rec then
                    local delta = total - ((b and b[guid]) or 0)
                    if delta < 0 then delta = total end
                    delta = delta + ((bk and bk[guid]) or 0)
                    rec[m.key] = delta
                    if isDamage then
                        matched = matched + 1
                        if deltaDuration and deltaDuration > 1 then
                            rec.dps = delta / deltaDuration
                        else
                            rec.dps = perSec[guid]
                        end
                    end
                end
            end
        end
    end

    record.meterAvailable = okAny
    -- How many roster members actually came back with a damage figure. Zero
    -- with a readable session means the rows were still classified, which is
    -- what the retries below wait out.
    record._matched = matched
    return okAny
end

-- Whose reset state the meter events feed: the running key's, or the finished
-- run's while it still waits for the meter (a reset between the last pull and
-- the final read would otherwise take that pull with it). Only from a trusted
-- baseline; nothing once the run's numbers are in. Returns the seg, plus the
-- finished run when the seg is its.
local function ResetScope()
    local lr = lastRun
    if lr then
        if lr.awaitingMeter and lr.based then return lr.seg, lr end
    elseif collecting and hasBaseline then
        return seg
    end
end

-- A checkpoint: a pull ended and the combat restriction lifted, so the Overall
-- totals read plain. A row still classified keeps its last value, and the
-- pull only counts as banked once the damage rows came back readable (or the
-- meter is simply empty).
local function Checkpoint(sg)
    if not MeterReady() then return end
    local readable = false
    for _, m in ipairs(METRICS) do
        wipe(scratchTotals)
        local read, rows = HarvestTotals(m.dmType, scratchTotals, nil, nil, m.countRows)
        if read then
            local s = sg.snap[m.key]
            if not s then s = {}; sg.snap[m.key] = s end
            for guid, v in pairs(scratchTotals) do s[guid] = v end
            if m.key == "damage" and (rows == 0 or next(scratchTotals) ~= nil) then
                readable = true
            end
        end
    end
    local d = SessionDuration()
    if d then sg.snapDur = d end
    if readable then sg.unbanked = false end
end

-- The meter was reset: bank what it gained up to the last checkpoint and count
-- on from zero. A reset landing on a pull no checkpoint banked loses that
-- pull, which the panel then says instead of passing short numbers off as the
-- whole run. Returns the new baseline duration.
local function BankReset(base, sg, baseDur)
    if sg.unbanked then sg.gaps = true end
    for _, m in ipairs(METRICS) do
        local bank = sg.bank[m.key]
        if not bank then bank = {}; sg.bank[m.key] = bank end
        local snap, b = sg.snap[m.key], base[m.key]
        if snap then
            for guid, v in pairs(snap) do
                local gain = v - ((b and b[guid]) or 0)
                if gain > 0 then bank[guid] = (bank[guid] or 0) + gain end
            end
            wipe(snap)
        end
        if b then wipe(b) else base[m.key] = {} end
    end
    if sg.snapDur and baseDur and sg.snapDur > baseDur then
        sg.bankDur = sg.bankDur + (sg.snapDur - baseDur)
    end
    sg.snapDur = 0
    return 0
end

local function ApplyScores(record, rst, ord)
    rst, ord = rst or roster, ord or rosterOrder
    for _, guid in ipairs(ord) do
        local rec = rst[guid]
        if StillIs(rec) then
            local now = ScoreFor(rec.unit)
            if now then
                rec.score = now
                -- No API reports another player's delta for the run, so it is
                -- the score after the key minus the score sampled at its start.
                -- Without a baseline the cell stays empty rather than showing a
                -- wrong number.
                if rec.scoreStart then rec.scoreGain = now - rec.scoreStart end
            end
        end
    end
    -- The local player has a real server side delta; prefer it.
    if record.scoreOld and record.scoreNew then
        local ownGUID = PlainString(UnitGUID("player"))
        local own = ownGUID and rst[ownGUID]
        if own then
            own.score     = record.scoreNew
            own.scoreGain = record.scoreNew - record.scoreOld
        end
    end
end

-- Row order: one of the four sortable columns (a click on its header picks
-- it, a second click flips the direction), DPS descending by default, like a
-- damage meter -- role is not a key, tank and healer fall where their numbers
-- put them. Persisted per profile (runSummary.sortKey / sortAsc). Missing
-- values sort last either way; DPS falls back to total damage while the
-- meter has not settled. Every value was validated plain before it was
-- stored, so comparing cannot raise.
local SORT_KEYS = { dps = true, damageTaken = true, interrupts = true, deaths = true }
local sortKey, sortAsc = "dps", false   -- refreshed from the profile by SortMembers

local function SortState()
    local c = Cfg()
    local key = c and c.sortKey
    if not SORT_KEYS[key] then key = "dps" end
    return key, (c and c.sortAsc == true) or false
end

local function MemberOrder(a, b)
    local va, vb = a[sortKey], b[sortKey]
    if sortKey == "dps" then va = va or a.damage; vb = vb or b.damage end
    local ma, mb = va == nil, vb == nil
    if ma ~= mb then return mb end
    if not ma and va ~= vb then
        if sortAsc then return va < vb end
        return va > vb
    end
    return (a.name or "") < (b.name or "")
end

local function SortMembers(list)
    sortKey, sortAsc = SortState()
    table.sort(list, MemberOrder)
end

local MEMBER_FIELDS = {
    "guid", "name", "class", "role", "specIcon", "ilvl", "score", "scoreGain",
    "damage", "dps", "damageTaken", "interrupts", "deaths", "lootID", "lootLink",
}

-- Rebuilt on every settling event, so the member tables already stored on the
-- record are overwritten in place rather than allocated again.
local function BuildMembers(record, rst, ord)
    rst, ord = rst or roster, ord or rosterOrder
    local out = record.members
    if type(out) ~= "table" then out = {}; record.members = out end
    local n = 0
    for _, guid in ipairs(ord) do
        local rec = rst[guid]
        if rec and rec.name then
            n = n + 1
            local m = out[n]
            if type(m) ~= "table" then m = {}; out[n] = m end
            for _, f in ipairs(MEMBER_FIELDS) do m[f] = rec[f] end
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    SortMembers(out)
end

local function TryFinishHarvest()
    local lr = lastRun
    if not (lr and lr.awaitingMeter) then return end
    if RestrictionActive() then return end
    HarvestInto(lr.record, lr.rst, lr.base, lr.baseDur, lr.based, lr.seg)
    BuildMembers(lr.record, lr.rst, lr.ord)
    if RefreshWindowIfOpen then RefreshWindowIfOpen() end
    if (lr.record._matched or 0) > 0 then
        lr.awaitingMeter = false
        SyncEvents()
    end
end

-- Party members' rating is pushed by the server after the key and has no event
-- of its own, so it is re-read on the settling events that do fire.
local function RefreshScores()
    local lr = lastRun
    if not (lr and not lr.settled) then return end
    ApplyScores(lr.record, lr.rst, lr.ord)
    BuildMembers(lr.record, lr.rst, lr.ord)
    if RefreshWindowIfOpen then RefreshWindowIfOpen() end
end

local function FinishRun()
    local info = C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo
        and C_ChallengeMode.GetChallengeCompletionInfo()
    if type(info) ~= "table" then return end

    -- Capture the party tokens here and now: Blizzard's own completion banner
    -- does the same because members can leave immediately afterwards.
    ScanRoster(false)

    -- info.members is the server side roster and survives people leaving.
    if type(info.members) == "table" then
        for _, m in ipairs(info.members) do
            local guid = PlainString(m.memberGUID)
            if guid then
                local rec = EnsureMember(guid)
                rec.name = rec.name or PlainString(m.name)
                if not rec.class then
                    -- UnitClass takes a unit token, so it cannot answer for
                    -- someone who already left. GetPlayerInfoByGUID is the
                    -- GUID keyed equivalent.
                    if GetPlayerInfoByGUID then
                        rec.class = PlainString(select(2, GetPlayerInfoByGUID(guid)))
                    end
                    if not rec.class and UnitTokenFromGUID then
                        local u = PlainString(UnitTokenFromGUID(guid))
                        if u and UnitExists(u) then
                            rec.class = PlainString(select(2, UnitClass(u)))
                        end
                    end
                end
            end
        end
    end

    local mapID = PlainNumber(info.mapChallengeModeID)
    local mapName, _, timeLimit
    if mapID and C_ChallengeMode.GetMapUIInfo then
        mapName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    end
    local deaths, timeLost
    if C_ChallengeMode.GetDeathCount then
        deaths, timeLost = C_ChallengeMode.GetDeathCount()
    end

    local record = {
        mapID      = mapID,
        mapName    = PlainString(mapName),
        timeLimit  = PlainNumber(timeLimit),
        level      = PlainNumber(info.level),
        timeMS     = PlainNumber(info.time),          -- milliseconds
        onTime     = info.onTime == true,
        upgrades   = PlainNumber(info.keystoneUpgradeLevels) or 0,
        practice   = info.practiceRun == true,
        mapRecord  = info.isMapRecord == true,
        deaths     = PlainNumber(deaths) or 0,
        timeLost   = PlainNumber(timeLost) or 0,
        scoreOld   = PlainNumber(info.oldOverallDungeonScore),
        scoreNew   = PlainNumber(info.newOverallDungeonScore),
        finishedAt = time(),
    }

    local lr = {
        record = record, rst = roster, ord = rosterOrder,
        base = baseTotals, baseDur = baseDuration, based = hasBaseline,
        seg = seg,
        bonus = {},
    }
    lastRun = lr
    PurgeOldSeasons()
    HarvestInto(record, lr.rst, lr.base, lr.baseDur, lr.based, lr.seg)
    ApplyScores(record, lr.rst, lr.ord)
    BuildMembers(record, lr.rst, lr.ord)
    StoreRun(record)

    -- If the rows are still classified, the restriction lift, the next pull
    -- ending, the loot window closing or leaving the instance each retry.
    lr.awaitingMeter = (record._matched or 0) == 0
    SyncEvents()
end

local function ShowPending()
    local lr = lastRun
    if not lr then return end
    lr.lootArmed = false
    BuildMembers(lr.record, lr.rst, lr.ord)
    if ShowWindow then ShowWindow(lr.record) end
    -- The roster scan is done; the settling watch, inspects included, runs on.
    collecting = false
    SyncEvents()
    InspectSweep()
end

-- Leaving the instance closes the settling phase: one last attempt at the
-- meter and the scores, the panel if it never opened, then everything that was
-- only listening for this run is dropped.
local function EndSettling()
    local lr = lastRun
    if not (lr and not lr.settled) then return end
    TryFinishHarvest()
    RefreshScores()
    if lr.lootArmed then ShowPending() end
    lr.awaitingMeter = false
    lr.settled = true
    SyncEvents()
    if RefreshWindowIfOpen then RefreshWindowIfOpen() end
end

local function ArmLootWait()
    local lr = lastRun
    if not lr then return end
    local c = Cfg()
    if not (c and c.showAfterLoot) then
        ShowPending()
        return
    end
    -- Opens on the rewards payload or the loot window closing; if neither
    -- comes, leaving the instance opens it.
    lr.lootArmed = true
end

-- The item string alone: a chat link loses a |cn quality color in LinkFromText,
-- so the same item arrives as different link strings. Bonus IDs are kept, so
-- a chest drop and a bonus copy of the same item still differ.
local function LinkKey(link)
    return type(link) == "string" and link:match("|H(item:[^|]+)|h") or nil
end

-- Marks a link as bonus roll loot for the rest of the run and takes it back
-- from whoever it was already recorded against, since ENCOUNTER_LOOT_RECEIVED
-- may have delivered it before the chat line. True when a row changed.
local function ForgetBonusLoot(lr, link)
    local key = LinkKey(link)
    if not key then return false end
    lr.bonus[key] = true
    local changed = false
    for _, guid in ipairs(lr.ord) do
        local rec = lr.rst[guid]
        if rec and LinkKey(rec.lootLink) == key then
            rec.lootLink = nil
            -- The chest reward's ID stays when the bonus copy is the same item.
            if not rec.lootChest and rec.lootID == IDFromLink(link) then rec.lootID = nil end
            changed = true
        end
    end
    return changed
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local function OnEvent(_, event, ...)
    if event == "CHALLENGE_MODE_START" then
        StartCollecting()

    elseif event == "CHALLENGE_MODE_RESET" then
        StopCollecting()

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- lastRun is only set by FinishRun and only cleared when a new key
        -- starts, so its presence means this key was already recorded. Without
        -- this, a repeated delivery would store the run twice, the second time
        -- with no baseline and with every score sampled after the fact.
        if lastRun then return end
        if not collecting then
            -- Reloading mid key loses the key start; collect what is still
            -- readable rather than dropping the run entirely.
            StartCollecting(true)
        end
        FinishRun()
        ArmLootWait()

    elseif event == "CHALLENGE_MODE_COMPLETED_REWARDS" then
        -- rewards carry the LOCAL player's chest loot only; personal loot is
        -- never reported for anyone else.
        local lr = lastRun
        if lr then
            local rewards = select(5, ...)
            local ownGUID = PlainString(UnitGUID("player"))
            local own = ownGUID and lr.rst[ownGUID]
            if own and type(rewards) == "table" then
                for _, reward in ipairs(rewards) do
                    local id = PlainNumber(reward.rewardID)
                    if id and reward.isCurrency ~= true and not IsExcludedLootID(id) then
                        -- Kept as an ID: the item is often not in the client's
                        -- cache yet here, so icon and tooltip resolve from the
                        -- ID at render time. A link from one of the two loot
                        -- events below is preferred when it arrives.
                        if (own.lootID or IDFromLink(own.lootLink)) ~= id then
                            own.lootLink = nil
                        end
                        own.lootID    = id
                        own.lootChest = true
                        break
                    end
                end
            end
            BuildMembers(lr.record, lr.rst, lr.ord)
            if RefreshWindowIfOpen then RefreshWindowIfOpen() end
        end
        if lr and lr.lootArmed then ShowPending() end

    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        local lr = lastRun
        if lr then
            local link, who = PlainString((select(3, ...))), select(5, ...)
            if link and not lr.bonus[LinkKey(link)]
                and RecordLoot(lr.rst, lr.ord, nil, PlainString(who), link) then
                BuildMembers(lr.record, lr.rst, lr.ord)
                if RefreshWindowIfOpen then RefreshWindowIfOpen() end
            end
        end

    elseif event == "BONUS_ROLL_RESULT" then
        -- Our own roll only; nobody else's is reported this way.
        local lr = lastRun
        local rewardType, link = ...
        link = PlainString(link)
        if lr and link and PlainString(rewardType) == "item" and ForgetBonusLoot(lr, link) then
            BuildMembers(lr.record, lr.rst, lr.ord)
            if RefreshWindowIfOpen then RefreshWindowIfOpen() end
        end

    elseif event == "CHAT_MSG_LOOT" then
        local lr = lastRun
        if lr then
            local text, who, guid = select(1, ...), select(2, ...), select(12, ...)
            local link = LinkFromText(text)
            if link and IsBonusRollLine(text) then
                if ForgetBonusLoot(lr, link) then
                    BuildMembers(lr.record, lr.rst, lr.ord)
                    if RefreshWindowIfOpen then RefreshWindowIfOpen() end
                end
            elseif link and not lr.bonus[LinkKey(link)]
                and RecordLoot(lr.rst, lr.ord, PlainString(guid), PlainString(who), link) then
                BuildMembers(lr.record, lr.rst, lr.ord)
                if RefreshWindowIfOpen then RefreshWindowIfOpen() end
            end
        end

    elseif event == "LOOT_CLOSED" then
        if lastRun and lastRun.lootArmed then ShowPending() end
        TryFinishHarvest()
        RefreshScores()
        InspectSweep()

    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- The combat restriction's edges (see ResetScope): switching on means
        -- a pull began (its gains are unbanked until the next checkpoint);
        -- switching off is the checkpoint itself.
        local rtype, rstate = PlainNumber((select(1, ...))), PlainNumber((select(2, ...)))
        local R, S = Enum.AddOnRestrictionType, Enum.AddOnRestrictionState
        local sg = ResetScope()
        if sg and rtype and R and S and rtype == R.Combat then
            if rstate == S.Inactive then
                Checkpoint(sg)
            else
                sg.unbanked = true
            end
        end
        TryFinishHarvest()

    elseif event == "DAMAGE_METER_RESET" then
        local sg, lr = ResetScope()
        if lr then
            lr.baseDur = BankReset(lr.base, sg, lr.baseDur)
        elseif sg then
            baseDuration = BankReset(baseTotals, sg, baseDuration)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- A pull ended: an inspect still pending from before it was dropped,
        -- so free the slot and carry on.
        inspectPending = nil
        InspectSweep()
        TryFinishHarvest()

    elseif event == "PLAYER_ENTERING_WORLD" then
        EndSettling()

    elseif event == "INSPECT_READY" then
        if OnInspectReady((select(1, ...))) and lastRun and not lastRun.settled then
            BuildMembers(lastRun.record, lastRun.rst, lastRun.ord)
            if RefreshWindowIfOpen then RefreshWindowIfOpen() end
        end
        InspectSweep()

    elseif event == "CHALLENGE_MODE_MEMBER_INFO_UPDATED" or event == "GROUP_ROSTER_UPDATE" then
        if collecting then ScanRoster(true) end
        InspectSweep()
        RefreshScores()
    end
end

--------------------------------------------------------------------------------
--  Enable / disable. Nothing exists until the feature is switched on.
--------------------------------------------------------------------------------
-- Lets the options page repaint an open panel when a column or the scale
-- changes, without exposing the panel internals.
function ns.RS_Refresh()
    if RefreshWindowIfOpen then RefreshWindowIfOpen() end
end

function ns.RS_Apply()
    if Enabled() then
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", OnEvent)
        end
        SyncEvents()
        -- Enabling mid key still picks the run up from here on. Guarded on
        -- lastRun because IsChallengeModeActive stays true after completion
        -- until the key resets, and every options change calls back in here:
        -- without it, touching a setting inside the instance would restart the
        -- collector and discard the run that just finished.
        if not collecting and not lastRun
            and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive() then
            StartCollecting()
        end
        -- Unlock Mode entry intentionally not registered for now; the panel is
        -- moved by dragging its header. RegisterUnlock is kept for later.
    elseif frame then
        frame:UnregisterAllEvents()
        lastRun = nil
        StopCollecting()
    end
end

function ns.RS_OnEnable(database)
    db = database
    if not db then return end
    ns.RS_Apply()
end

--------------------------------------------------------------------------------
--  Panel. EllesmereUI.Widgets is deliberately not used: EllesmereUIOptions is
--  LoadOnDemand, so a widget call would force load the whole options addon at
--  the end of every key. Chrome mirrors Damage Meters' own window, and all
--  geometry goes through EllesmereUI.PP, the game grid, never PanelPP.
--------------------------------------------------------------------------------
local EUI    = EllesmereUI
local format = string.format
local floor  = math.floor

-- Sized for reading at a glance rather than as a compact HUD element; the
-- Panel Scale setting multiplies all of it on top of the player's UI scale.
local PAD        = 15
local HEAD_H     = 56
local COLHDR_H   = 22
local COL_GAP    = 15
local SUB_GAP    = 5
local ICON_SZ    = 20
-- Member-row text: user-set (runSummary.textSize, default 14); the row height
-- follows it. Title, subline and column headers keep their fixed sizes.
local DEFAULT_TEXT_SZ = 14
local FONT_SZ    = DEFAULT_TEXT_SZ   -- SetFS fallback only
local TITLE_SZ   = 17
local SUBLINE_SZ = 13
local COLHDR_SZ  = 12
local PICKER_SZ  = 12
local NAME_MIN   = 150
local PICKER_W   = 240
local PICKER_H   = 22
local CLOSE_W    = 14
local HEADER_GAP = 10
local CLOSE_ICON    = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
local FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local CLASS_ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

-- `sub` marks a column that carries a second, separately styled font string.
-- "inline" keeps it right after the primary's own text (item level after a
-- name); "column" parks it at a fixed offset so the primaries stay right
-- aligned under each other and the extras all start on the same x (score).
local COLUMNS = {
    { key = "spec",        header = "",           kind = "icon", minW = ICON_SZ, cfg = "showSpecIcons", gapAfter = SUB_GAP },
    { key = "name",        header = "Player",     kind = "text", justify = "LEFT",  minW = NAME_MIN, sub = "inline" },
    { key = "score",       header = "Score",      kind = "text", justify = "RIGHT", minW = 42, cfg = "colScore", sub = "column" },
    { key = "loot",        header = "Loot",       kind = "icon", minW = ICON_SZ, cfg = "colLoot" },
    { key = "dps",         header = "DPS",        kind = "text", justify = "RIGHT", minW = 52, cfg = "colDps" },
    { key = "damageTaken", header = "Taken",      kind = "text", justify = "RIGHT", minW = 52, cfg = "colDamageTaken" },
    { key = "interrupts",  header = "Interrupts", kind = "text", justify = "RIGHT", minW = 28, cfg = "colInterrupts" },
    { key = "deaths",      header = "Deaths",     kind = "text", justify = "RIGHT", minW = 28, cfg = "colDeaths" },
}

-- Secondary font strings: item level and score gain, two sizes below the row
-- text and unbolded (size resolved from the setting at stamp time).
local SUB_STYLE = {
    name  = { r = 0.55, g = 0.55, b = 0.55 },
    score = { r = 0.35, g = 0.95, b = 0.35 },
}

local win, rows, colHdr, titleFS, subFS, pickerBtn, pickerLbl
local visibleCols = {}
local currentRecord
local rowsTextSize   -- the size the member rows were last stamped with

local function TextSize()
    local c = Cfg()
    local v = c and tonumber(c.textSize) or DEFAULT_TEXT_SZ
    if v < 8 then v = 8 elseif v > 24 then v = 24 end
    return v
end

local function RowHeight(size)
    return size + 9
end

--------------------------------------------------------------------------------
--  Formatting
--------------------------------------------------------------------------------
-- flags = nil follows the module's font setting; pass "" for an unbolded run.
local function SetFS(fs, size, flags)
    local path    = (EUI.GetFontPath("mythicTimer")) or FONT_FALLBACK
    local outline = flags
    if outline == nil then
        outline = (EUI.GetFontOutlineFlag("mythicTimer")) or ""
    end
    fs:SetFont(path, size or FONT_SZ, outline)
end

local function Hex(r, g, b)
    return format("%02x%02x%02x", floor((r or 1) * 255), floor((g or 1) * 255), floor((b or 1) * 255))
end

-- Shared number engine: K/M/B, or thousand/wan/yi grouping on koKR/zhCN/zhTW.
local function Abbrev(v)
    if type(v) ~= "number" then return nil end
    return EllesmereUI.AbbreviateNumber(v)
end

local function Clock(seconds)
    if type(seconds) ~= "number" or seconds < 0 then seconds = 0 end
    local whole = floor(seconds)
    return format("%d:%02d", floor(whole / 60), whole % 60)
end

-- Indexing RAID_CLASS_COLORS with a secret token throws, so this is the guard
-- shape Damage Meters already uses on its own rows.
local function ClassHex(class)
    if class and not IsSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local cc = EUI.GetClassColor(class)
        if cc then return Hex(cc.r, cc.g, cc.b) end
    end
    return "ffffff"
end

local function ShortName(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^([^%-]+)") or name
end

local function ScoreText(m)
    if not m.score then return "-" end
    local hex = "ffffff"
    local col = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
        and C_ChallengeMode.GetDungeonScoreRarityColor(m.score)
    if type(col) == "table" and col.r then hex = Hex(col.r, col.g, col.b) end
    return format("|cff%s%d|r", hex, floor(m.score))
end

-- Zero and missing both read as a dash in the combat columns.
local function NonZero(v)
    if type(v) == "number" and floor(v) > 0 then return v end
    return nil
end

local function CellText(col, m, c)
    local k = col.key
    if k == "name" then return format("|cff%s%s|r", ClassHex(m.class), ShortName(m.name)) end
    if k == "score" then return ScoreText(m) end
    if k == "dps" then return Abbrev(NonZero(m.dps)) or "-" end
    if k == "damageTaken" then return Abbrev(NonZero(m.damageTaken)) or "-" end
    if k == "interrupts" then return NonZero(m.interrupts) and format("%d", floor(m.interrupts)) or "-" end
    if k == "deaths" then return NonZero(m.deaths) and format("%d", floor(m.deaths)) or "-" end
    return ""
end

local function SubText(col, m, c)
    if col.key == "name" then
        if c and c.colItemLevel ~= false and m.ilvl then return format("(%d)", m.ilvl) end
        return ""
    end
    if col.key == "score" then
        if m.scoreGain and m.scoreGain > 0 then return format("(+%d)", floor(m.scoreGain)) end
        return ""
    end
    return ""
end

-- date() without a leading "!" formats in the player's local time. Short
-- month and day with no year, 12-hour clock: "Sep 18, 6:02pm".
local function RunWhen(ts)
    if not ts then return "" end
    local h = tonumber(date("%H", ts)) or 0
    local ampm = (h >= 12) and "pm" or "am"
    h = h % 12
    if h == 0 then h = 12 end
    return format("%s %d, %d:%s%s", date("%b", ts), tonumber(date("%d", ts)) or 0, h, date("%M", ts), ampm)
end

local function RunLabel(rec)
    return format("+%d %s   %s", rec.level or 0, rec.mapName or "?", RunWhen(rec.finishedAt))
end

--------------------------------------------------------------------------------
--  Chrome
--------------------------------------------------------------------------------
local function SavePositionFromFrame()
    local c = Cfg()
    if not (c and win) then return end
    local point, _, relPoint, x, y = win:GetPoint(1)
    if not point then return end
    c.position = { point = point, relPoint = relPoint or point, x = x, y = y }
end

ApplyPosition = function()
    if not win then return end
    local c = Cfg()
    local pos = c and c.position
    win:ClearAllPoints()
    if pos and pos.point then
        local PP = EUI.PP
        local es = win:GetEffectiveScale() or 1
        local x, y = pos.x or 0, pos.y or 0
        if PP and PP.SnapForES then
            x, y = PP.SnapForES(x, es), PP.SnapForES(y, es)
        end
        win:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, x, y)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

-- Stamps the member-row font sizes: primary text at `size`, sub text two
-- below. Called at creation and again whenever the setting changes.
local function StampRowFonts(row, size)
    for key, fs in pairs(row.text) do
        SetFS(fs, size)
    end
    for _, sfs in pairs(row.sub) do
        SetFS(sfs, size - 2, "")
    end
    row:SetHeight(RowHeight(size))
end

local function MakeRow(parent, size)
    size = size or DEFAULT_TEXT_SZ
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(RowHeight(size))
    row.text, row.sub, row.icons = {}, {}, {}
    local px = (EUI.PP and EUI.PP.mult) or 1
    for _, col in ipairs(COLUMNS) do
        local fs = EUI.MakeFont(row, size, nil, 1, 1, 1, 1)
        SetFS(fs, size)
        fs:SetJustifyH(col.justify or (col.kind == "icon" and "CENTER" or "LEFT"))
        fs:SetWordWrap(false)
        row.text[col.key] = fs
        if col.kind == "icon" then
            local cell = CreateFrame("Frame", nil, row)
            cell:SetSize(ICON_SZ, ICON_SZ)
            cell.tex = cell:CreateTexture(nil, "ARTWORK")
            if col.key == "spec" or col.key == "loot" then
                -- Square icon on a black plate, inset by one physical pixel so
                -- the plate reads as a 1px border.
                cell.bg = cell:CreateTexture(nil, "BACKGROUND")
                cell.bg:SetAllPoints()
                cell.bg:SetColorTexture(0, 0, 0, 1)
                cell.tex:SetPoint("TOPLEFT", cell, "TOPLEFT", px, -px)
                cell.tex:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -px, px)
            else
                cell.tex:SetAllPoints()
            end
            row.icons[col.key] = cell
        else
            local style = col.sub and SUB_STYLE[col.key]
            if style then
                local sfs = EUI.MakeFont(row, size - 2, nil, style.r, style.g, style.b, 1)
                SetFS(sfs, size - 2, "")
                sfs:SetJustifyH("LEFT")
                sfs:SetWordWrap(false)
                row.sub[col.key] = sfs
            end
        end
    end
    return row
end

local ShowPicker  -- assigned below, once the record list is reachable

local function BuildWindow()
    if win then return win end
    local PP = EUI.PP

    win = CreateFrame("Frame", "EUIMythicRunSummaryFrame", UIParent)
    -- FULLSCREEN: above the options window (DIALOG), so Show Preview is not
    -- hidden behind it, and below FULLSCREEN_DIALOG, where the run picker menu,
    -- confirmation popups and Unlock Mode movers live.
    win:SetFrameStrata("FULLSCREEN")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:Hide()
    -- Escape closes it like every other EUI window (the shared proxy, never
    -- a direct UISpecialFrames insert).
    if EUI.RegisterEscapeClose then EUI.RegisterEscapeClose(win) end

    -- House window chrome (the /keys popup, Bags, the skinned Blizzard
    -- windows): the modern_blizz cover art under a black wash, a darker strip
    -- for the title bar, and the dark 1px PP border.
    win._bg = win:CreateTexture(nil, "BACKGROUND", nil, 0)
    win._bg:SetAllPoints()
    win._bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    win._bg:SetTexCoord(0.25, 1, 0, 0.75)
    win._bgOverlay = win:CreateTexture(nil, "BACKGROUND", nil, 1)
    win._bgOverlay:SetAllPoints()
    win._bgOverlay:SetColorTexture(0, 0, 0, 0.55)

    local header = CreateFrame("Frame", nil, win)
    header:SetFrameLevel(win:GetFrameLevel() + 5)
    header:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    header:SetHeight(HEAD_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        SavePositionFromFrame()
    end)
    win._header = header

    local hbg = EUI.SolidTex(header, "BACKGROUND", 0, 0, 0, 0.25)
    hbg:SetAllPoints()

    local px = (PP and PP.mult) or 1
    local sep = header:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(px)
    sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.10)

    titleFS = EUI.MakeFont(header, TITLE_SZ, nil, 1, 1, 1, 1)
    SetFS(titleFS, TITLE_SZ)
    titleFS:SetPoint("TOPLEFT", header, "TOPLEFT", PAD, -HEADER_GAP)
    titleFS:SetJustifyH("LEFT")

    subFS = EUI.MakeFont(header, SUBLINE_SZ, nil, 1, 1, 1, 0.8)
    SetFS(subFS, SUBLINE_SZ)
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -SUB_GAP)
    subFS:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(CLOSE_W, CLOSE_W)
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -PAD, -(HEADER_GAP + 2))
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture(CLOSE_ICON)
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
    close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() win:Hide() end)

    -- Run picker: the window-skin dropdown look every skinned Blizzard
    -- window's dropdowns carry (flat block, 1px grey border, hover wash, the
    -- small pointing arrow, white left-aligned label), with its menu hung
    -- below the button like the options dropdowns (ShowPicker).
    pickerBtn = CreateFrame("Button", nil, header)
    pickerBtn:SetSize(PICKER_W, PICKER_H)
    pickerBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -HEADER_GAP, (PICKER_H - CLOSE_W) / 2)
    local pfill = EUI.SolidTex(pickerBtn, "BACKGROUND", 0.08, 0.08, 0.08, 0.92)
    pfill:SetAllPoints()
    if PP and PP.CreateBorder then
        -- Border container demoted to the button's own level so the label,
        -- a higher draw layer, renders over the strips (the skin's rule).
        local pbrd = PP.CreateBorder(pickerBtn, 0.25, 0.25, 0.25, 1, 1, "BORDER", -7)
        if pbrd and pbrd.SetFrameLevel then pbrd:SetFrameLevel(pickerBtn:GetFrameLevel()) end
    end
    local phover = EUI.SolidTex(pickerBtn, "HIGHLIGHT", 1, 1, 1, 0.05)
    phover:SetAllPoints()
    local parrow = pickerBtn:CreateTexture(nil, "OVERLAY")
    parrow:SetAtlas("Azerite-PointingArrow")
    parrow:SetSize(14, 10)
    parrow:SetPoint("RIGHT", pickerBtn, "RIGHT", -6, 0)
    pickerLbl = EUI.MakeFont(pickerBtn, PICKER_SZ, nil, 1, 1, 1, 1)
    SetFS(pickerLbl, PICKER_SZ)
    -- Two-point anchored and non-wrapping: a long dungeon name truncates
    -- inside the button instead of running back over the title.
    pickerLbl:SetPoint("LEFT", pickerBtn, "LEFT", 8, 0)
    pickerLbl:SetPoint("RIGHT", parrow, "LEFT", -6, 0)
    pickerLbl:SetJustifyH("LEFT")
    pickerLbl:SetWordWrap(false)
    pickerBtn:SetScript("OnClick", function()
        if ShowPicker then ShowPicker(pickerBtn) end
    end)

    colHdr = MakeRow(win)
    colHdr:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -HEAD_H)
    colHdr:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -HEAD_H)
    colHdr:SetHeight(COLHDR_H)
    for _, col in ipairs(COLUMNS) do
        local fs = colHdr.text[col.key]
        if fs then
            SetFS(fs, COLHDR_SZ)
            fs:SetTextColor(1, 1, 1, 0.45)
        end
    end
    -- The header carries no icons, and the spec cell's black plate would show
    -- as an empty square if its frame were left visible.
    for _, cell in pairs(colHdr.icons) do cell:Hide() end

    -- Sortable column headers: a button over each cell (hit rect seated by
    -- PlaceInto each render). Click = sort by that column, click again = flip
    -- direction; stored on the profile. The active column is the bright
    -- header, nothing else marks it.
    colHdr.sortBtns = {}
    for _, col in ipairs(COLUMNS) do
        if SORT_KEYS[col.key] then
            local fs = colHdr.text[col.key]
            local btn = CreateFrame("Button", nil, colHdr)
            btn:SetFrameLevel(colHdr:GetFrameLevel() + 2)
            btn:SetScript("OnEnter", function()
                if fs and not btn.active then fs:SetTextColor(1, 1, 1, 0.8) end
            end)
            btn:SetScript("OnLeave", function()
                if fs and not btn.active then fs:SetTextColor(1, 1, 1, 0.45) end
            end)
            btn:SetScript("OnClick", function()
                local c = Cfg()
                if not c then return end
                local key, asc = SortState()
                if key == col.key then
                    c.sortAsc = not asc
                else
                    c.sortKey = col.key
                    c.sortAsc = false
                end
                RefreshWindowIfOpen()
            end)
            colHdr.sortBtns[col.key] = btn
        end
    end

    local hsep = win:CreateTexture(nil, "ARTWORK")
    hsep:SetHeight(px)
    hsep:SetPoint("TOPLEFT", colHdr, "BOTTOMLEFT", PAD, 0)
    hsep:SetPoint("TOPRIGHT", colHdr, "BOTTOMRIGHT", -PAD, 0)
    hsep:SetColorTexture(1, 1, 1, 0.10)

    rows = {}
    -- The border spans the whole frame, header included: it lives on its own
    -- host above the header (frame level + 5), or the header would draw over
    -- the top edge and only the body would look framed.
    if PP and PP.CreateBorder then
        local bh = CreateFrame("Frame", nil, win)
        bh:SetAllPoints()
        bh:SetFrameLevel(win:GetFrameLevel() + 10)
        PP.CreateBorder(bh, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
        win._borderHost = bh
    end
    return win
end

--------------------------------------------------------------------------------
--  Layout and render
--------------------------------------------------------------------------------
local function VisibleColumns()
    local c = Cfg() or {}
    wipe(visibleCols)
    for _, col in ipairs(COLUMNS) do
        if not col.cfg or c[col.cfg] ~= false then
            visibleCols[#visibleCols + 1] = col
        end
    end
    return visibleCols
end

local function MeasuredWidth(fs, fallback)
    if not fs then return fallback end
    local w = fs:GetStringWidth()
    if type(w) ~= "number" or IsSecret(w) then return fallback end
    -- Rounded up with a pixel spare: a font string sized to its exact
    -- fractional width truncates its own text to an ellipsis.
    if w > 0 then w = math.ceil(w) + 1 end
    return w
end

-- Spec icon where the meter reported one, class icon otherwise. Both are
-- cropped so the round frame baked into the art does not show inside the
-- square plate.
local function FillSpecCell(cell, m)
    local zoom = 0.08
    local id = m.specIcon
    if type(id) == "number" and id ~= 0 then
        cell.tex:SetTexture(id)
        cell.tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        cell:Show()
        return
    end
    local coords = m.class and not IsSecret(m.class)
        and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class]
    if coords then
        cell.tex:SetTexture(CLASS_ICON_TEX)
        local l, r, t, b = coords[1], coords[2], coords[3], coords[4]
        local dx, dy = (r - l) * zoom, (b - t) * zoom
        cell.tex:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
        cell:Show()
        return
    end
    cell:Hide()
end

-- Hoisted so a render does not build four closures per row; the cell carries
-- its item on _itemID and the handlers branch on that.
local function LootEnter(self)
    if self._link or self._itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- The link carries the item's actual level and bonuses; the bare ID is
        -- the fallback for the rewards payload, which has no link.
        if self._link then
            GameTooltip:SetHyperlink(self._link)
        else
            GameTooltip:SetItemByID(self._itemID)
        end
        GameTooltip:Show()
    elseif EUI.ShowWidgetTooltip then
        EUI.ShowWidgetTooltip(self, EllesmereUI.L("No loot recorded for this player in this run."))
    end
end

local function LootLeave(self)
    if self._link or self._itemID then
        GameTooltip:Hide()
    elseif EUI.HideWidgetTooltip then
        EUI.HideWidgetTooltip()
    end
end

local function FillLootCell(cell, m)
    cell:EnableMouse(true)
    cell:Show()
    cell._itemID = m.lootID
    cell._link   = m.lootLink
    if m.lootID or m.lootLink then
        local id = m.lootID or IDFromLink(m.lootLink)
        local icon = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
        cell.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        cell.tex:SetTexture(nil)
    end
    -- No plate without an item, or an empty cell would show a black square.
    if cell.bg then cell.bg:SetShown(m.lootID ~= nil or m.lootLink ~= nil) end
    cell:SetScript("OnEnter", LootEnter)
    cell:SetScript("OnLeave", LootLeave)
end

-- Places every visible column of one container (the column header row or a
-- member row) at the widths measured in the second pass, and hides the cells
-- of columns the user switched off.
local function PlaceInto(container, cols, widths, primW, subW)
    local x = PAD
    for idx, col in ipairs(cols) do
        local wt = widths[idx]
        local fs = container.text[col.key]
        local sfs = container.sub and container.sub[col.key]
        local icon = container.icons[col.key]
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", container, "LEFT", x + (wt - ICON_SZ) / 2, 0)
        end
        local sb = container.sortBtns and container.sortBtns[col.key]
        if sb then
            sb:ClearAllPoints()
            sb:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
            sb:SetPoint("BOTTOMRIGHT", container, "TOPLEFT", x + wt, -COLHDR_H)
            sb:Show()
        end
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", container, "LEFT", x, 0)
            if col.sub == "inline" then
                fs:SetWidth(wt)
                if sfs then
                    -- Anchored off this row's own text, so the item level sits
                    -- against the name instead of in a column of its own.
                    local own = MeasuredWidth(fs, 0)
                    sfs:ClearAllPoints()
                    sfs:SetPoint("LEFT", container, "LEFT", x + own + SUB_GAP, 0)
                    sfs:SetWidth(math.max(1, wt - own - SUB_GAP))
                    sfs:Show()
                end
            else
                fs:SetWidth(primW[idx])
                if sfs then
                    sfs:ClearAllPoints()
                    sfs:SetPoint("LEFT", container, "LEFT", x + primW[idx] + SUB_GAP, 0)
                    sfs:SetWidth(math.max(1, subW[idx]))
                    sfs:Show()
                end
            end
            fs:Show()
        end
        x = x + wt + (col.gapAfter or COL_GAP)
    end
    for _, col in ipairs(COLUMNS) do
        local shown = false
        for _, vc in ipairs(cols) do
            if vc.key == col.key then shown = true break end
        end
        if not shown then
            local fs = container.text[col.key]
            if fs then fs:Hide() end
            local sfs = container.sub and container.sub[col.key]
            if sfs then sfs:Hide() end
            local icon = container.icons[col.key]
            if icon then icon:Hide() end
            local sb = container.sortBtns and container.sortBtns[col.key]
            if sb then sb:Hide() end
        end
    end
end

local function RenderHeader(record)
    local lvlHex = "ffffff"
    local kcol = C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor
        and C_ChallengeMode.GetKeystoneLevelRarityColor(record.level or 0)
    if type(kcol) == "table" and kcol.r then lvlHex = Hex(kcol.r, kcol.g, kcol.b) end
    -- One string, keystone-rarity colour on the level only: "+12 The Rookery".
    titleFS:SetText(format("|cff%s+%d|r %s", lvlHex, record.level or 0, record.mapName or "?"))

    local timeHex = record.onTime and "40ff40" or "ff6060"
    local sub = format("|cff%s%s|r / %s", timeHex, Clock((record.timeMS or 0) / 1000),
        Clock(record.timeLimit or 0))
    -- Key upgrade levels read as the chest count: "(2 Chest)".
    if (record.upgrades or 0) > 0 then
        sub = sub .. "   " .. EllesmereUI.Lf("(%1$d Chest)", record.upgrades)
    elseif not record.onTime then
        sub = sub .. "   " .. EllesmereUI.L("Depleted")
    end
    -- Deaths and the time they cost share one muted run.
    local deaths = EllesmereUI.Lf("%1$d Deaths", record.deaths or 0)
    if (record.timeLost or 0) > 0 then
        deaths = deaths .. format(" (-%s)", Clock(record.timeLost))
    end
    sub = sub .. "   |cff808080" .. deaths .. "|r"
    -- One warning slot, most fundamental first.
    local warn
    if record.meterAvailable == false then
        warn = EllesmereUI.L("Blizzard damage meter is off")
    elseif (record._matched or 0) == 0 then
        warn = EllesmereUI.L("Combat data stayed restricted for this run")
    elseif record.meterGaps then
        warn = EllesmereUI.L("Damage meter was reset mid-run, some numbers are low")
    end
    if warn then sub = sub .. "   |cffff8040" .. warn .. "|r" end
    subFS:SetText(sub)

    if pickerLbl then pickerLbl:SetText(RunLabel(record)) end
end

local scratchWidths, scratchPrim, scratchSub = {}, {}, {}

local function Render(record)
    if not record or not win then return end
    local c = Cfg() or {}
    local members = record.members or {}
    local cols = VisibleColumns()
    -- Re-sorted on every render so a header click (or a stored run opened
    -- under a different sort) follows the current column and direction.
    SortMembers(members)

    RenderHeader(record)

    -- Row text size from the setting; a change re-stamps every pooled row's
    -- fonts and height, and the rows are re-seated below (their pitch moved).
    local textSize = TextSize()
    local rowH = RowHeight(textSize)
    local restamp = rowsTextSize ~= textSize
    rowsTextSize = textSize

    -- First pass: grow the row pool and give every cell its final text, so the
    -- widths measured below are the ones actually rendered.
    for i = 1, #members do
        if not rows[i] then
            rows[i] = MakeRow(win, textSize)
        elseif restamp then
            StampRowFonts(rows[i], textSize)
        end
        local y = -(HEAD_H + COLHDR_H + (i - 1) * rowH)
        rows[i]:ClearAllPoints()
        rows[i]:SetPoint("TOPLEFT", win, "TOPLEFT", 0, y)
        rows[i]:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, y)
        local row, m = rows[i], members[i]
        row:Show()
        for _, col in ipairs(COLUMNS) do
            local fs = row.text[col.key]
            if fs then
                fs:SetText(CellText(col, m, c))
                fs:SetTextColor(1, 1, 1, 1)
            end
            local sfs = row.sub[col.key]
            if sfs then sfs:SetText(SubText(col, m, c)) end
        end
        if row.icons.spec then FillSpecCell(row.icons.spec, m) end
        if row.icons.loot then FillLootCell(row.icons.loot, m) end
    end
    for i = #members + 1, #rows do rows[i]:Hide() end

    for _, col in ipairs(COLUMNS) do
        local fs = colHdr.text[col.key]
        if fs then fs:SetText(col.header ~= "" and EUI.L(col.header) or "") end
        local sfs = colHdr.sub[col.key]
        if sfs then sfs:SetText("") end
        -- Active sort column: bright header; the rest muted.
        local sb = colHdr.sortBtns and colHdr.sortBtns[col.key]
        if sb then
            local active = (col.key == sortKey)
            sb.active = active
            if fs then fs:SetTextColor(1, 1, 1, active and 1 or 0.45) end
        end
    end

    -- Second pass: measure, then place. A column holding only dashes collapses
    -- to its minimum width instead of reserving room it does not need.
    local widths, primW, subW, total = scratchWidths, scratchPrim, scratchSub, 0
    wipe(widths); wipe(primW); wipe(subW)
    for idx, col in ipairs(cols) do
        local wp, ws, wt = col.minW, 0, col.minW
        if col.kind == "icon" then
            wt = math.max(col.minW, MeasuredWidth(colHdr.text[col.key], 0))
            wp = wt
        elseif col.kind == "text" then
            wp = MeasuredWidth(colHdr.text[col.key], 0)
            for i = 1, #members do
                wp = math.max(wp, MeasuredWidth(rows[i].text[col.key], 0))
                if col.sub then ws = math.max(ws, MeasuredWidth(rows[i].sub[col.key], 0)) end
            end
            if col.sub == "inline" then
                -- The primary is sized per row here, so the column only has to
                -- fit the widest name plus its own extra.
                wt = math.max(col.minW, MeasuredWidth(colHdr.text[col.key], 0))
                for i = 1, #members do
                    local a = MeasuredWidth(rows[i].text[col.key], 0)
                    local b = MeasuredWidth(rows[i].sub[col.key], 0)
                    wt = math.max(wt, a + (b > 0 and (SUB_GAP + b) or 0))
                end
            else
                wp = math.max(wp, col.minW)
                wt = wp + (ws > 0 and (SUB_GAP + ws) or 0)
            end
        end
        primW[idx], subW[idx], widths[idx] = wp, ws, wt
        total = total + wt
    end
    for idx = 1, #cols - 1 do
        total = total + (cols[idx].gapAfter or COL_GAP)
    end
    total = total + PAD * 2

    PlaceInto(colHdr, cols, widths, primW, subW)
    for i = 1, #members do PlaceInto(rows[i], cols, widths, primW, subW) end

    -- The header is laid out independently of the table, so with enough columns
    -- switched off the picker and title would overrun a table-width frame.
    local headerMin = math.max(
        PAD + MeasuredWidth(titleFS, 0) + COL_GAP + PICKER_W + HEADER_GAP + CLOSE_W + PAD,
        PAD + MeasuredWidth(subFS, 0) + PAD)
    total = math.max(total, headerMin)

    local PP = EUI.PP
    local height = HEAD_H + COLHDR_H + #members * rowH + PAD
    -- Scale first: PP.Size snaps against the frame's current effective scale,
    -- so changing the scale afterwards would throw that snap away.
    local scale = tonumber(c.scale) or 1
    if scale < 0.5 then scale = 0.5 elseif scale > 2 then scale = 2 end
    win:SetScale(scale)
    if PP and PP.Size then PP.Size(win, total, height) else win:SetSize(total, height) end
end

--------------------------------------------------------------------------------
--  Show, refresh, run picker
--------------------------------------------------------------------------------
ShowWindow = function(record)
    if not record then return end
    BuildWindow()
    currentRecord = record
    Render(record)
    ApplyPosition()
    win:Show()
end

RefreshWindowIfOpen = function()
    if win and win:IsShown() and currentRecord then Render(currentRecord) end
end

ShowPicker = function(anchor)
    local runs = ns.RS_GetRuns()
    local items = {}
    for i = 1, #runs do
        local rec = runs[i]
        items[#items + 1] = { text = RunLabel(rec), onClick = function() ShowWindow(rec) end }
    end
    if #items == 0 then
        items[1] = { text = EllesmereUI.L("No runs recorded yet"), isDisabled = function() return true end }
    end
    -- Hung below the picker, at least its width: a dropdown, not a cursor menu.
    EUI.ShowContextMenu(anchor, items, { below = true, minWidth = PICKER_W })
end

-- Opens the n-th most recent run (1 = newest).
function ns.RS_Show(index)
    local i = math.floor(tonumber(index) or 1)
    if i < 1 then i = 1 end
    local rec = ns.RS_GetRuns()[i]
    if not rec then
        EUI.PrintError(EllesmereUI.L("No runs recorded yet"))
        return
    end
    ShowWindow(rec)
end

-- Preview: a synthetic run so the panel can be checked without going into a
-- key. Built on demand and never written to the history. Row 3 deliberately
-- carries no score gain, which is what a member without a start baseline
-- looks like.
local PREVIEW_CLASSES = { "PALADIN", "PRIEST", "ROGUE", "DRUID", "MAGE" }
-- Protection, Holy, Assassination, Balance, Frost. Resolved through the
-- global when it exists; otherwise nil and the class icon fallback shows.
local PREVIEW_SPEC_IDS = { 66, 257, 259, 102, 64 }
local function PREVIEW_SPEC_ICON(i)
    return SpecIconForSpecID(PREVIEW_SPEC_IDS[i])
end
function ns.RS_ShowPreview()
    local R = Enum and Enum.LFGRole
    local members = {}
    for i = 1, 5 do
        members[i] = {
            name        = "Preview " .. i,
            class       = PREVIEW_CLASSES[i],
            role        = R and ((i == 1 and R.Tank) or (i == 2 and R.Healer) or R.Damage),
            specIcon    = PREVIEW_SPEC_ICON(i),
            ilvl        = 668 + i * 3,
            score       = 2950 + i * 90,
            scoreGain   = (i ~= 3) and (6 + i * 3) or nil,
            damage      = 30000000 + i * 8000000,
            dps         = 21000 + i * 6000,
            damageTaken = 9200000 - i * 1200000,
            interrupts  = 5 - i,
            deaths      = i % 2,
        }
    end
    -- Same order the live panel gets from BuildMembers.
    SortMembers(members)
    -- Resolve the dungeon name from its ID so the preview is localized by the
    -- client. Out of season the API returns nothing and the English name shows;
    -- it is not a translator key, so it is not wrapped in L().
    local mapName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo
        and C_ChallengeMode.GetMapUIInfo(2648)
    ShowWindow({
        mapID     = 2648,
        mapName   = PlainString(mapName) or "The Rookery",
        level     = 12,
        timeMS    = 1380000,
        timeLimit = 1920,
        onTime    = true,
        upgrades  = 2,
        deaths    = 3,
        timeLost  = 15,
        meterAvailable = true,
        _matched   = #members,
        finishedAt = time(),
        members   = members,
    })
end

--------------------------------------------------------------------------------
--  Slash command
--------------------------------------------------------------------------------
SLASH_EUIMPLUS1 = "/ov"
SLASH_EUIMPLUS2 = "/euimplus"
SlashCmdList.EUIMPLUS = function(msg)
    if not Enabled() then
        EUI.PrintError(EllesmereUI.L("Run Summary is disabled in Mythic+ Tools."))
        return
    end
    local lower = msg and msg:lower() or ""
    if lower:find("preview", 1, true) then
        ns.RS_ShowPreview()
        return
    end
    ns.RS_Show(msg and tonumber(msg:match("%d+")))
end
