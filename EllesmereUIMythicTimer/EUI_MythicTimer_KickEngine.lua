if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_KickEngine.lua
--  Kick Tracker (Mythic+ Tools): who in the group kicked what, and when each
--  member's interrupt comes back. The displays (nameplate icons, bars) read it;
--  it runs only while one of them is subscribed, and registers nothing before.
--
--  Who kicked: inside instanced combat no cast, aura or combat log line names
--  the kicker, but the game's own damage meter does keep an Interrupts count
--  per group member, and each member's row carries their class, spec icon and
--  whether it is you, never hidden. A landed kick changes that data in the
--  same frame the enemy's cast stops: a member's row appears (their first kick
--  of the fight), a row moves up past another, or a member's list of kicked
--  enemy spells grows (fetched by their group GUID, which stays readable). Your
--  own kicks are your own casts, which land a moment after they are cast. A
--  member kicking a spell they kicked before changes nothing visible (the
--  spell is in their list already, and the count on it is hidden), so the
--  engine keeps, per member, which spells their list is known to hold: a
--  member's first kick of a spell, paired with the one plate kicked then,
--  names the entry; an entry that landed unpaired (two kicks in one update, a
--  mob with no plate, a fight joined late) could be anything. A kick that
--  changes nothing is then the one member whose list holds the plate's spell.
--  Where the spell is hidden too (a key), such a kick cannot be a member's
--  first (their list would have grown), and the rows sit in count order, so a
--  member whose row sits right under a member known to be tied with them did
--  not kick either: their count would have passed and moved their row (the
--  engine bounds each hidden count by what it saw). Only those proofs name a
--  kicker; the engine never guesses.
--
--  Every other kick still reaches the displays, exactly: each update also
--  carries a gate packet, every member it named nobody for sure about with
--  their interrupt count before and after the update (hidden in combat). A
--  display hands both to a hidden status bar (the count before as its value,
--  the count after as its maximum), whose fill is whole while the count did
--  not move and short of whole once it rose; a clip hung from that fill's
--  edge shows the member's layer only while the fill is short. So the
--  member whose count rose, and only they, show the kick, with no value read
--  in Lua. Every update also hands the displays each member's count as read
--  (the counts event), so a display can take a member's count at the kick
--  it placed them for as a baseline and hide that kick's icon, the same way,
--  once their count has risen past it (KE.Count, KE.FightGen). A demon's
--  interrupts count under the demon (the meter keeps it as a source of its
--  own), so its warlock's count is read there.
--
--  Cooldowns: every member's interrupt and its cooldown come from
--  the parent's EllesmereUI.KickData, read for their class, spec and talents. Talents are read by
--  inspecting each member out of combat and outside a running key (a key
--  locks that data, and talents cannot change inside one), the spec also from
--  the meter's rows once their GUIDs are readable again. A kick the tracker
--  sees starts the kicker's modeled cooldown, yours from your own talents. Kicks that
--  stop nothing are known for you alone.
--
--  Secret discipline: the interrupter GUID and every meter amount are secret
--  in restricted content; they are only type-tested and handed to native
--  sinks, never compared, concatenated or keyed. Group GUIDs, classes, roles,
--  the rows' class, spec icon and local-player flags, and the breakdown list
--  lengths are plain, and those are all the engine reasons with.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local KD, MTWhere = EllesmereUI.KickData, ns.MTWhere
if not (KD and MTWhere) then return end

local KE = {}
ns.KickEngine = KE

local pairs, type, pcall, wipe, tostring, tonumber = pairs, type, pcall, wipe, tostring, tonumber
local GetTime = GetTime
local securecallfunction = securecallfunction

local Secret, PlainString = EllesmereUI.IsSecret, EllesmereUI.PlainString

local DM = C_DamageMeter
local INT = Enum.DamageMeterType and Enum.DamageMeterType.Interrupts
local DMG = Enum.DamageMeterType and Enum.DamageMeterType.DamageDone
local HEAL = Enum.DamageMeterType and Enum.DamageMeterType.HealingDone
local CUR = Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current
local ALL = Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall
local RT_COMBAT = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat
local RT_KEY = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.ChallengeMode
local RS_INACTIVE = Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
local INSPECT_CFG = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID or -1

local GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }
local PET_UNIT = { player = "pet", party1 = "partypet1", party2 = "partypet2", party3 = "partypet3", party4 = "partypet4" }
KE.GROUP_UNITS = GROUP_UNITS

-- Only nameplate tokens: a kick stops the same mob on every token that names
-- it, and a plate is the one the displays can use.
local NAMEPLATE_UNITS, NAMEPLATE_TOKENS = ns.NAMEPLATE_UNITS, ns.NAMEPLATE_TOKENS

local ELIM_SLACK     = 1.5   -- seconds a modeled cooldown may be off by before it rules a member out
local OWN_WINDOW     = 1.0   -- seconds after your kick cast within which a landed kick is yours
local PAIR_WINDOW    = 0.25  -- seconds a plate's cast stop and the meter's update may lie apart (seen: the same frame)
local INSPECT_WAIT   = 3     -- seconds for the inspect data to arrive
local INSPECT_RETRY  = 10    -- seconds before a member out of inspect range is tried again
local INSPECT_FRESH  = 60    -- seconds after which a member is inspected again (talent swaps before the key)

local EMPTY = {}
local INF = math.huge
local LEARN_TYPES = { DMG, HEAL, INT }
local LEARN_SESSIONS = { ALL, CUR }

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local roster = {}          -- unit -> member record (built once per slot, reset on a new GUID)
local subs = {}             -- key -> handlers { kick = fn, cooldown = fn, roster = fn }
local subCount = 0
local active = false
local evt                   -- event frame, built on the first activation
local ownT = -1             -- GetTime() of your last kick cast
local ownPending = false    -- that cast has not been matched to a landed kick yet
local stopped = {}          -- plate units whose cast was kicked this frame, waiting for the meter
local stoppedBy = {}        -- their interrupter values (secret or plain)
local stoppedSpell = {}     -- the spells those casts were (plain), false where hidden
local stoppedT = -1
local flushArmed = false
local rosterT = -1          -- GetTime() of the last roster sync (a roster storm syncs once per frame)
local rosterFlush = false   -- a sync is queued for the end of a roster storm
local specIconOf = {}       -- specID -> icon file ID (the meter's specIconID)
local specOfIcon = {}       -- class token -> { [icon] = specID }
local keyMemo = {}          -- class -> icon -> own -> the row key string, built once
local lastSession           -- the Interrupts session the rows were last read from
local spareKeys, spareN = {}, {}   -- the row buffers not holding the baseline
local spareA, spareG = {}, {}      -- the same for each member's gate source: its count (hidden in combat) and entry count
local readPrevA, readPrevG = {}, {} -- the update's counts before it (Attribute; read by BuildGate in that frame)
local gateList, gatePrev, gateCur, gatePlates = {}, {}, {}, {}   -- the gate packet (read at once by the displays)
local gateT = -1            -- the update the packet was built for
local countList = {}        -- the counts event's members (read at once by the displays)
local fightGen = 0          -- bumped whenever the counts restart (a new fight, a reset, a load); KE.FightGen
local lateArmed = false     -- a plate stop waits one frame for an update of its own (OnStop, LatePair)
local grew, left = {}, {}   -- Attribute's scratch
local growth = {}           -- Attribute's scratch: unit -> entries its list gained this update
local preNarrow = {}        -- Pick's scratch: the candidates before the cooldown narrowing
local rowIdx, rowAt, rowScratch = {}, {}, {}   -- TieNarrow's scratch: unit -> its one row's index (false: several), index -> unit

-- Attribution memory: the Current session's rows (keys "CLASS:icon", "*" for
-- you) in the engine's order, each member's breakdown entry count, what the
-- last meter update concluded (lastT) and from which row evidence (rowKey,
-- rowHow: a plate naming the kicked spell can settle an ambiguous answer
-- again), the one member whose list grew by one entry on it (learn: the
-- plate paired with it names that entry's spell) and when a plate event last
-- took it (pairedT: an attribution serves one frame's plates, or a later
-- frame's within PAIR_WINDOW while no frame has taken it).
-- `a` and `g`: each member's gate source (their demon's for a demon's
-- interrupt) as last read, its count and its entry count; `gated`: the last
-- update sent a gate packet a plate arriving later in its window can join.
local memo = { rows = {}, n = {}, a = {}, g = {}, frameT = -1, lastT = -1, pairedT = -1, who = nil, scratch = nil,
    how = nil, rowKey = nil, rowHow = nil, learn = nil, gated = false, grew = false }

local function NewMember(unit)
    local m = { unit = unit, lastSure = false }
    roster[unit] = m
    return m
end

local function Dispatch(name, ...)
    for _, h in pairs(subs) do
        local fn = h[name]
        if fn then securecallfunction(fn, ...) end
    end
end

--------------------------------------------------------------------------------
--  Specs
--------------------------------------------------------------------------------
-- The meter's rows name a spec by its icon; each class's specs map their icon
-- back to the spec ID (built once per class).
local function IconSpecs(classID, class)
    local t = specOfIcon[class]
    if t then return t end
    t = {}
    specOfIcon[class] = t
    local n = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for i = 1, n do
        local id, _, _, icon = GetSpecializationInfoForClassID(classID, i)
        if id and icon then
            t[icon] = id
            specIconOf[id] = icon
        end
    end
    return t
end

-- The icon the meter's rows show for a member's spec, from their class's
-- spec list.
local function IconOf(classID, class, specID)
    if not (classID and class and specID) then return nil end
    IconSpecs(classID, class)
    return specIconOf[specID]
end

--------------------------------------------------------------------------------
--  Cooldown model
--------------------------------------------------------------------------------
local function StartCd(m, start, dur)
    m.downAt, m.downFor, m.readyAt = start, dur, start + dur
    Dispatch("cooldown", m.unit, start, dur)
end

local function ClearCd(m)
    if not m.downAt then return end
    m.downAt, m.downFor, m.readyAt = nil, nil, nil
    Dispatch("cooldown", m.unit, nil, nil)
end

-- The member's interrupt and its cooldowns from what is known of them.
local function ResolveKick(m)
    local kick, cd, landed, minCd
    local spec = m.specID
    if m.class then
        if m.unit == "player" then
            -- Your own: the spellbook knows (a demon's interrupt included).
            kick = EllesmereUI.GetActiveKickSpell()
            if kick and not KD.INTERRUPTS[kick] then kick = KD.OwnCastKick(kick) end
            if not kick then kick, spec = KD.KickSpell(m.class, m.specID, m.role, m.talents, m.pet) end
        else
            kick, spec = KD.KickSpell(m.class, m.specID, m.role, m.talents, m.pet)
        end
        if kick then
            cd, landed = KD.Cooldown(kick, spec, m.talents)
            -- The shortest the landed cooldown could be, with every cooldown
            -- talent: what a member whose talents were never read is held to.
            local _, shortest = KD.Cooldown(kick, spec, KD.WATCHED_TALENTS)
            minCd = shortest
        end
    end
    local changed = (m.kick ~= (kick or false)) or (m.cd ~= cd) or (m.landedCd ~= landed) or (m.minCd ~= minCd)
    m.kick, m.cd, m.landedCd, m.minCd = kick or false, cd, landed, minCd
    return changed
end

--------------------------------------------------------------------------------
--  Roster
--------------------------------------------------------------------------------
local function UnitOfGUID(g)
    if type(g) ~= "string" or Secret(g) then return nil end
    for i = 1, #GROUP_UNITS do
        local m = roster[GROUP_UNITS[i]]
        if m and m.guid == g then return GROUP_UNITS[i] end
    end
    return nil
end

-- The demons with an interrupt, by creature ID (the pet's GUID names it on
-- every client; the family name the client gives is in its own language).
local DEMON_BY_NPC = { [417] = "Felhunter", [17252] = "Felguard", [58965] = "Wrathguard", [110397] = "Wrathguard" }

local function PetFamily(unit)
    local pet = PET_UNIT[unit]
    if not (pet and UnitExists(pet)) then return nil end
    local g = PlainString(UnitGUID(pet))
    local npc = g and tonumber(g:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if npc and DEMON_BY_NPC[npc] then return DEMON_BY_NPC[npc] end
    local ok, fam = pcall(UnitCreatureFamily, pet)
    if ok then return PlainString(fam) end
    return nil
end

local AskRead, RefreshPlayer

local function IsPlayerUnit(unit)
    local ok, v = pcall(UnitIsPlayer, unit)
    return ok and v == true
end

-- Reads every slot: a new GUID resets the record (and asks for an inspect),
-- an empty slot clears it. Role, pet and the kick are re-read every time.
local function SyncRoster()
    local now = GetTime()
    local changed = false
    for i = 1, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        local m = roster[unit] or NewMember(unit)
        -- Players only: a delve companion or a follower NPC in the slot is an
        -- empty slot (no row, no inspect).
        if UnitExists(unit) and (unit == "player" or IsPlayerUnit(unit)) then
            local guid = PlainString(UnitGUID(unit))
            if guid ~= m.guid then
                wipe(m)
                m.unit, m.guid, m.lastSure = unit, guid, false
                changed = true
                -- A new occupant is read whatever the slot's last read did.
                if guid and unit ~= "player" then AskRead(unit, true) end
            end
            -- A read that comes back hidden (UnitClass and the role are secret
            -- while a unit's identity is restricted) keeps the last plain
            -- value: the same occupant has the same class, and a new one wiped
            -- the record above.
            local _, class, classID = UnitClass(unit)
            class = PlainString(class)
            if class then
                m.class = class
                m.classID = (type(classID) == "number" and not Secret(classID)) and classID or m.classID
            end
            local ok, role = pcall(UnitGroupRolesAssigned, unit)
            role = ok and PlainString(role) or nil
            if role then m.role = role end
            if m.class == "WARLOCK" then m.pet = PetFamily(unit) end
            if m.class and m.classID then IconSpecs(m.classID, m.class) end
            if unit == "player" then
                if RefreshPlayer(m, true) then changed = true end
            elseif ResolveKick(m) then
                changed = true
            end
        elseif m.guid or m.class then
            wipe(m)
            m.unit, m.lastSure = unit, false
            changed = true
        end
    end
    if changed then Dispatch("roster", now) end
end

-- Your own spec and talents (IsPlayerSpell), read directly. Returns whether
-- the kick changed; dispatches unless the caller does (quiet).
RefreshPlayer = function(m, quiet)
    m = m or roster.player
    if not m then return false end
    local idx = C_SpecializationInfo.GetSpecialization()
    local id = idx and C_SpecializationInfo.GetSpecializationInfo(idx)
    m.specID = (type(id) == "number" and id > 0) and id or nil
    m.specIcon = IconOf(m.classID, m.class, m.specID)
    m.specSrc = "self"
    local t = m.talents or {}
    wipe(t)
    for sid in pairs(KD.WATCHED_TALENTS) do
        if IsPlayerSpell(sid) then t[sid] = true end
    end
    m.talents = t
    m.pet = PetFamily("player")
    local changed = ResolveKick(m)
    if changed and not quiet then Dispatch("roster", GetTime()) end
    return changed
end

--------------------------------------------------------------------------------
--  Inspect: one member at a time, out of combat and outside a running key,
--  with the game's own inspect window closed. Their spec and the talents the
--  data table watches are read from the inspect talent config.
--------------------------------------------------------------------------------
local readList = {}     -- unit list, in order
local readAsked = {}    -- unit -> true
local readingUnit, readingGuid   -- the request in flight
local readWait = false  -- a retry is scheduled

local function KeyActive()
    if not (RT_KEY and C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then return false end
    local ok, v = pcall(C_RestrictedActions.IsAddOnRestrictionActive, RT_KEY)
    return ok and v == true
end

-- Your own casts (OnOwnCast): yours, and your demon's when you are a warlock
-- (Spell Lock and Axe Toss are the demon's spells). Nobody else's: another
-- member's casts, their demon's included, never reach this client on a
-- dungeon map (field 2026-10-21: an unfiltered listener heard none), and
-- the meter credits their kicks through their row. Registered at Activate,
-- after the roster read gave your class; a hunter's pet is never listened to.
local function RegisterOwnCasts()
    local me = roster.player
    if me and me.class == "WARLOCK" then
        evt:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    else
        evt:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
end

-- For /euikt: the units whose casts are heard, the key state and each
-- member's class, spec icon and kick, one line.
function KE.Listening()
    local me = roster.player
    local units = (me and me.class == "WARLOCK") and "player pet" or "player"
    local members = {}
    for i = 1, #GROUP_UNITS do
        local m = roster[GROUP_UNITS[i]]
        if m and m.guid then
            members[#members + 1] = m.unit .. " " .. tostring(m.class) .. ":" .. tostring(m.specIcon) .. " " .. tostring(m.kick)
        end
    end
    return "casts heard: " .. units .. (KeyActive() and " (key)" or "")
        .. " | roster: " .. (#members > 0 and table.concat(members, ", ") or "empty")
end

-- Whether the player's own inspect window, or the talent view it opens, is up.
local function InspectWindowUp()
    local f = InspectFrame
    if f and f:IsShown() then return true end
    local ps = PlayerSpellsFrame
    return (ps and ps.IsInspecting and ps:IsInspecting()) and true or false
end

local function MayReadNow()
    if InCombatLockdown() or KeyActive() then return false end
    return not InspectWindowUp()
end

local function ReadTree()
    if not (C_Traits and C_Traits.HasValidInspectData and C_Traits.HasValidInspectData()) then return nil end
    local info = C_Traits.GetConfigInfo(INSPECT_CFG)
    local trees = info and info.treeIDs
    if type(trees) ~= "table" then return nil end
    local watched = KD.WATCHED_TALENTS
    local set = {}
    local any = false
    for t = 1, #trees do
        local nodes = C_Traits.GetTreeNodes(trees[t])
        if type(nodes) == "table" then
            for i = 1, #nodes do
                local ni = C_Traits.GetNodeInfo(INSPECT_CFG, nodes[i])
                local entry = ni and ni.activeEntry
                if entry and type(ni.activeRank) == "number" and ni.activeRank > 0 then
                    any = true
                    local ei = C_Traits.GetEntryInfo(INSPECT_CFG, entry.entryID)
                    local defID = ei and ei.definitionID
                    if defID then
                        local di = C_Traits.GetDefinitionInfo(defID)
                        local sid = di and di.spellID
                        if sid and watched[sid] then set[sid] = true end
                    end
                end
            end
        end
    end
    -- A tree with nothing active was not really read (data that arrived
    -- empty).
    if not any then return nil end
    return set
end

local ReadNext

local function ReadLater(delay)
    if readWait then return end
    readWait = true
    C_Timer.After(delay, function()
        readWait = false
        if active then ReadNext() end
    end)
end

local function DoneReading()
    readingUnit, readingGuid = nil, nil
    if evt then evt:UnregisterEvent("INSPECT_READY") end
    -- An inspect the player's own window opened meanwhile is theirs to keep.
    if ClearInspectPlayer and not InspectWindowUp() then pcall(ClearInspectPlayer) end
end

local function OnReadReady(guid)
    if not readingUnit or Secret(guid) or guid ~= readingGuid then return end
    local unit = readingUnit
    local m = roster[unit]
    if m and m.guid == guid then
        local get = C_SpecializationInfo.GetInspectSpecialization
        local ok, spec = pcall(get, unit)
        if ok and type(spec) == "number" and not Secret(spec) and spec > 0 then
            m.specID, m.specSrc = spec, "inspect"
            m.specIcon = IconOf(m.classID, m.class, spec)
        end
        local talents = ReadTree()
        if talents then
            m.talents = talents
            m.readAt = GetTime()
            m.readTries = nil
        end
        if ResolveKick(m) then Dispatch("roster", GetTime()) end
    end
    DoneReading()
    readAsked[unit] = nil
    ReadNext()
end

-- A member whose data never came goes to the back of the queue; after
-- INSPECT_TRIES the slot waits for the next stale check or a new occupant.
local INSPECT_TRIES = 3
local function ReadTimedOut(guid)
    if readingUnit and readingGuid == guid then
        local unit = readingUnit
        DoneReading()
        local m = roster[unit]
        local tries = ((m and m.readTries) or 0) + 1
        if m then m.readTries = tries end
        if tries < INSPECT_TRIES then
            readList[#readList + 1] = unit
        else
            readAsked[unit] = nil
        end
        ReadLater(INSPECT_RETRY)
    end
end

ReadNext = function()
    if not active or readingUnit or #readList == 0 then return end
    if not MayReadNow() then
        ReadLater(INSPECT_RETRY)
        return
    end
    for i = 1, #readList do
        local unit = readList[i]
        local m = roster[unit]
        local guid = m and m.guid
        if not (guid and UnitExists(unit) and UnitIsConnected(unit)) then
            table.remove(readList, i)
            readAsked[unit] = nil
            ReadNext()
            return
        end
        if CanInspect(unit) then
            table.remove(readList, i)
            readingUnit, readingGuid = unit, guid
            evt:RegisterEvent("INSPECT_READY")
            NotifyInspect(unit)
            C_Timer.After(INSPECT_WAIT, function() ReadTimedOut(guid) end)
            return
        end
    end
    -- Everyone queued is out of range: try again later.
    ReadLater(INSPECT_RETRY)
end

-- renew: a new occupant of the slot is read even where the last read of
-- that slot still counts as asked (one already queued is read in its turn).
AskRead = function(unit, renew)
    if unit == "player" then return end
    if readAsked[unit] then
        if not renew then return end
        for i = 1, #readList do
            if readList[i] == unit then return end
        end
    end
    readAsked[unit] = true
    readList[#readList + 1] = unit
    if active then ReadNext() end
end

-- Members whose talents were read a while ago are read again (a talent swap
-- before the key), while a key is not running.
local function ReReadStale()
    if KeyActive() then return end
    local now = GetTime()
    for i = 2, #GROUP_UNITS do
        local m = roster[GROUP_UNITS[i]]
        if m and m.guid and (not m.readAt or now - m.readAt >= INSPECT_FRESH) then
            AskRead(GROUP_UNITS[i])
        end
    end
end

--------------------------------------------------------------------------------
--  Meter reads
--------------------------------------------------------------------------------
-- The Current session's interrupt rows as keys in the engine's order, and each
-- member's breakdown entry count (the enemy spells they have kicked this
-- fight), fetched by their readable group GUID.
-- The key naming a row ("CLASS:icon", "*" for you): one string per
-- combination, built the first time it is seen.
local function RowKey(cls, icon, loc)
    -- An enemy's or a pet's row carries no class and no spec icon: "-" for
    -- each, since a nil cannot index the memo.
    local c = Secret(cls) and "?" or (cls == nil and "-" or tostring(cls))
    local ic = Secret(icon) and "?" or (icon == nil and "-" or icon)
    local own = (not Secret(loc) and loc == true) and true or false
    local byCls = keyMemo[c]
    if not byCls then byCls = {}; keyMemo[c] = byCls end
    local byIcon = byCls[ic]
    if not byIcon then byIcon = {}; byCls[ic] = byIcon end
    local k = byIcon[own]
    if not k then
        k = c .. ":" .. tostring(ic) .. (own and "*" or "")
        byIcon[own] = k
    end
    return k
end

-- The session's own ID, where it is readable.
local function SessionID(s)
    if type(s) ~= "table" or Secret(s) then return nil end
    local id = s.sessionID
    if type(id) == "number" and not Secret(id) then return id end
    return nil
end

-- One source's breakdown by its readable GUID: its entry count (plain) and
-- its interrupt count (hidden in combat; only ever handed on), or nil.
local function ReadSource(g)
    local ok, d = pcall(DM.GetCombatSessionSourceFromType, CUR, INT, g)
    if ok and type(d) == "table" and not Secret(d) then
        local sp = d.combatSpells
        if type(sp) == "table" and not Secret(sp) then return #sp, d.totalAmount end
    end
    return nil, nil
end

-- Whether a member's interrupt is their demon's (Spell Lock, Axe Toss), and
-- the demon's GUID where readable (a group member's pet is player-controlled,
-- so it is). The meter keeps a demon as a source of its own: the demon's
-- count is the one its kicks move.
local function DemonGUID(u, m)
    local k = m.kick and KD.INTERRUPTS[m.kick]
    if not (k and k.pet) then return false, nil end
    local pet = PET_UNIT[u]
    if not (pet and UnitExists(pet)) then return true, nil end
    return true, PlainString(UnitGUID(pet))
end

-- Fills the caller's tables and returns the first two with the session's ID:
-- the rows' keys, each member's entry count, and, for every member but you,
-- their gate source's count (amap) and entry count (gmap): their own, or
-- their demon's. A demon with no readable source of its own takes the one
-- row the meter keeps for a warlock with no spec icon, while one warlock in
-- the group has a demon's interrupt (that row then can be no one else's).
local function ReadRows(keys, nmap, amap, gmap)
    wipe(keys)
    wipe(nmap)
    wipe(amap)
    wipe(gmap)
    local sid
    local demonRows, demonRowAmt = 0, nil
    local ok, s = pcall(DM.GetCombatSessionFromType, CUR, INT)
    if ok and type(s) == "table" and not Secret(s) then
        sid = SessionID(s)
        local src = s.combatSources
        if type(src) == "table" and not Secret(src) then
            for i = 1, #src do
                local r = src[i]
                if type(r) == "table" and not Secret(r) then
                    local k = RowKey(r.classFilename, r.specIconID, r.isLocalPlayer)
                    keys[i] = k
                    if k == "WARLOCK:-" then
                        demonRows = demonRows + 1
                        demonRowAmt = r.totalAmount
                    end
                else
                    keys[i] = "?"
                end
            end
        end
    end
    local demonUnit, demons = nil, 0
    for i = 1, #GROUP_UNITS do
        local u = GROUP_UNITS[i]
        local m = roster[u]
        local g = m and m.guid
        if g then
            local n, amt = ReadSource(g)
            if n then nmap[u] = n end
            if i > 1 then
                local isDemon, pg = DemonGUID(u, m)
                if isDemon then
                    demons = demons + 1
                    local pn, pamt
                    if pg then pn, pamt = ReadSource(pg) end
                    if pn and pn > 0 then
                        gmap[u], amap[u] = pn, pamt
                    else
                        demonUnit = u
                    end
                elseif n then
                    gmap[u], amap[u] = n, amt
                end
            end
        end
    end
    if demonUnit and demons == 1 and demonRows == 1 and demonRowAmt ~= nil then
        -- A row exists only once its source interrupted: one entry at least.
        gmap[demonUnit], amap[demonUnit] = 1, demonRowAmt
    end
    return keys, nmap, sid
end

-- What each member's Interrupts list is known to hold, kept on the record:
-- `known` (enemy spell ID -> true) and `holes`, the entries whose spell the
-- engine never learned. Every read of the counts keeps them in step: an entry
-- that appeared is a hole until the plate paired with it names its spell, a
-- list that shrank restarted with a new fight, and a record read for the
-- first time holds nothing but holes. The record's interrupt count bounds
-- (`lo`, `hi`) start there too: nothing seen yet, and no ceiling while
-- entries the engine never saw land are already there (Bound keeps them).
local function SyncLists(nmap, prevN)
    for i = 1, #GROUP_UNITS do
        local u = GROUP_UNITS[i]
        local m = roster[u]
        if m then
            local n = nmap[u] or 0
            if not m.known then
                m.known, m.holes = {}, n
                m.lo, m.hi = 0, (n > 0) and INF or 0
            else
                local prev = prevN[u] or 0
                if n < prev then
                    wipe(m.known)
                    m.holes = n
                    m.lo, m.hi = 0, (n > 0) and INF or 0
                elseif n > prev then
                    m.holes = m.holes + (n - prev)
                end
            end
        end
    end
end

-- Forgets every list: the next read holds nothing but holes. The counts
-- restarted with them (a new fight), which the displays' count gates need to
-- know (KE.FightGen).
local function ResetLists()
    for _, m in pairs(roster) do m.known, m.holes = nil, nil end
    fightGen = fightGen + 1
end

-- A member whose count could not be read keeps the count last read, so a
-- failed read is neither a shrink nor, when it reads again, a growth (nor,
-- for the gate source, a rise the read before it would then miss).
local function CarryCounts(nmap, amap, gmap)
    for i = 1, #GROUP_UNITS do
        local u = GROUP_UNITS[i]
        if nmap[u] == nil then nmap[u] = memo.n[u] end
        if amap[u] == nil and gmap[u] == nil then
            amap[u], gmap[u] = memo.a[u], memo.g[u]
        end
    end
end

-- Whether a read shrank (fewer rows, or a member's count fell: a new fight)
-- and whether it rose (a row or a count more) against a baseline.
local function ListsMoved(keys, nmap, prevKeys, prevN)
    local shrank, rose = #keys < #prevKeys, #keys > #prevKeys
    for i = 1, #GROUP_UNITS do
        local u = GROUP_UNITS[i]
        local n, prev = nmap[u] or 0, prevN[u] or 0
        if n < prev then shrank = true elseif n > prev then rose = true end
    end
    return shrank, rose
end

-- A new baseline: the rows of a fight the engine has not read yet. The
-- current-session event also fires through combat, where the session's ID
-- is hidden, so whether this is still the session the baseline came from is
-- judged by the counts: one that fell is a new fight (the lists restarted
-- with it); one that rose is a kick whose own Interrupts update, in this
-- frame, reads it (adopted here, that kick would read as nothing new), so
-- the baseline stays. A reset or a load forces it and forgets the lists.
local function Rebase(force)
    local newSession = force
    if not force then
        if GetTime() == memo.frameT then return end
        local ok, s = pcall(DM.GetCombatSessionFromType, CUR, INT)
        local sid = ok and SessionID(s) or nil
        if sid ~= nil then
            if sid == lastSession then return end
            newSession = true
        end
    end
    local k, n, sid = ReadRows(spareKeys, spareN, spareA, spareG)
    local a, g = spareA, spareG
    CarryCounts(n, a, g)
    if not newSession then
        local shrank, rose = ListsMoved(k, n, memo.rows, memo.n)
        if rose and not shrank then
            return
        end
        newSession = shrank
    end
    if newSession then ResetLists() end
    SyncLists(n, memo.n)
    spareKeys, spareN, spareA, spareG = memo.rows, memo.n, memo.a, memo.g
    memo.rows, memo.n, memo.a, memo.g, lastSession = k, n, a, g, sid
    -- A new baseline: no gate packet is pending against the old one.
    memo.gated = false
end

-- Each member's spec icon from the meter's rows, where the GUIDs are readable
-- (out of restricted combat). An inspect's answer is never overwritten.
local function LearnSpecs()
    if InCombatLockdown() then return end
    local changed = false
    for t = 1, #LEARN_TYPES do
        for s = 1, #LEARN_SESSIONS do
            local ok, sess = pcall(DM.GetCombatSessionFromType, LEARN_SESSIONS[s], LEARN_TYPES[t])
            if ok and type(sess) == "table" and not Secret(sess) then
                local src = sess.combatSources
                if type(src) == "table" and not Secret(src) then
                    for i = 1, #src do
                        local r = src[i]
                        if type(r) == "table" and not Secret(r) then
                            local unit = UnitOfGUID(r.sourceGUID)
                            local icon = r.specIconID
                            local m = unit and roster[unit]
                            if m and unit ~= "player" and m.specSrc ~= "inspect" and type(icon) == "number" and not Secret(icon) then
                                local map = m.class and m.classID and IconSpecs(m.classID, m.class)
                                local spec = map and map[icon]
                                if m.specIcon ~= icon or m.specID ~= spec then
                                    m.specIcon, m.specID, m.specSrc = icon, spec, "meter"
                                    if ResolveKick(m) then changed = true end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if changed then Dispatch("roster", GetTime()) end
end

-- The members a row key ("CLASS:icon", "*" for you) can belong to: those of
-- the class who have an interrupt (a healer paladin has none, so a Ret's row
-- is never theirs) and whose spec, where known, the icon names. A row with no
-- icon ("CLASS:-": the meter knows no spec for its source, as it filed a
-- warlock's demon kicks in the field, 2026-10-21) names its member by class
-- alone, whatever spec an inspect gave them.
local function KeyUnits(key, out)
    wipe(out)
    if key:sub(-1) == "*" then
        out[1] = "player"
        return out
    end
    local cls, icon = key:match("^([^:]+):([^:%*]+)")
    icon = tonumber(icon)
    for i = 2, #GROUP_UNITS do
        local m = roster[GROUP_UNITS[i]]
        if m and m.guid and m.kick and m.class == cls and (icon == nil or m.specIcon == nil or m.specIcon == icon) then
            out[#out + 1] = GROUP_UNITS[i]
        end
    end
    return out
end

-- A row attributed to one member for sure names their spec by its icon: a
-- member not inspected yet (inside a key no inspect runs and the meter's
-- GUIDs stay hidden) learns it from their own row, and the displays switch
-- from their class icon to the spec's.
local function LearnRow(m, key, T)
    if not m or m.specSrc == "inspect" or m.specIcon ~= nil then return end
    local cls, icon = key:match("^([^:]+):([^:%*]+)")
    icon = tonumber(icon)
    if not icon or cls ~= m.class then return end
    local map = m.classID and IconSpecs(m.classID, m.class)
    m.specIcon, m.specID, m.specSrc = icon, map and map[icon] or nil, "row"
    ResolveKick(m)
    Dispatch("roster", T)
end

--------------------------------------------------------------------------------
--  Attribution
--------------------------------------------------------------------------------
local scratch = {}
local kept = {}

-- Every member but you who has an interrupt.
local function AllOthers(out)
    wipe(out)
    for i = 2, #GROUP_UNITS do
        local m = roster[GROUP_UNITS[i]]
        if m and m.guid and m.kick then out[#out + 1] = GROUP_UNITS[i] end
    end
    return out
end

-- The member's interrupt is still on cooldown from a kick that was theirs
-- for sure. A member whose talents were never read is held to the shortest
-- cooldown they could have (a cooldown talent the engine does not know of
-- lets them kick sooner than the plain cooldown says).
local function StillDown(m, T)
    local cd = m.talents and m.landedCd or m.minCd
    local last = m.lastSure and m.lastKick
    return (cd and last and T - last < cd - ELIM_SLACK) and true or false
end

-- The members of `list` whose modeled interrupt could be ready.
local function Eliminate(list, T)
    wipe(kept)
    for i = 1, #list do
        local m = roster[list[i]]
        if not (m and StillDown(m, T)) then kept[#kept + 1] = list[i] end
    end
    return kept
end

-- Narrows a candidate list by cooldown. Returns who (one left), how, and the
-- list while several are left.
local function Narrow(list, T, how)
    if #list > 1 then
        local left = Eliminate(list, T)
        if #left > 0 and #left < #list then
            wipe(list)
            for i = 1, #left do list[i] = left[i] end
            how = "cooldown"
        end
    end
    if #list == 1 then return list[1], how or "only", nil end
    if #list == 0 then return nil, "unknown", nil end
    return nil, "ambiguous", list
end

-- Interrupt counts the meter keeps hidden, bounded by what the engine saw
-- (lo..hi on the record; hi INF once a mass interrupt, or a read of entries
-- it never saw land, left the count unknowable). The meter's rows sit in
-- count order, so a member whose count passed the member above would have
-- moved: a kick that moved no row is not theirs while the two are known to
-- be tied. Bounds only ever loosen where the engine is unsure.
local function Loosen(list)
    for i = 1, #list do
        local m = roster[list[i]]
        if m and m.hi then m.hi = m.hi + 1 end
    end
end

-- A kick any member with entries may have landed, none of it visible.
local function LoosenAll()
    for i = 1, #GROUP_UNITS do
        local u = GROUP_UNITS[i]
        local m = roster[u]
        if m and m.hi and (memo.n[u] or 0) > 0 then m.hi = m.hi + 1 end
    end
end

-- The member landed `d` kicks for sure; `exact` while the count rose by no
-- more than that.
local function Count(m, d, exact)
    if not (m and m.lo) then return end
    m.lo = m.lo + d
    m.hi = exact and (m.hi + d) or INF
end

-- The members of `list` with entries: a kick that changed nothing cannot be
-- a member's first (their list would have grown).
local function Entered(list)
    local n = 0
    for i = 1, #list do
        if (memo.n[list[i]] or 0) > 0 then
            n = n + 1
            list[n] = list[i]
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- The one member with entries a row names, or nil: an enemy's or a hidden
-- row, or a key two such members share.
local function RowMember(key)
    local list = Entered(KeyUnits(key, rowScratch))
    return #list == 1 and list[1] or nil
end

-- The members of `list` whose unseen kick the meter's order allows: a
-- member whose row sits right under a member known to be tied with them is
-- out (their count would have passed the other's and moved their row). Only
-- rows that name one member, each named by one row, take part.
local function TieNarrow(list)
    wipe(rowIdx)
    wipe(rowAt)
    local rows = memo.rows
    for i = 1, #rows do
        local u = RowMember(rows[i])
        if u then
            if rowIdx[u] == nil then rowIdx[u] = i else rowIdx[u] = false end
            rowAt[i] = u
        end
    end
    local n = 0
    for i = 1, #list do
        local x = list[i]
        local keep = true
        local idx = rowIdx[x]
        if idx and idx > 1 then
            local a = rowAt[idx - 1]
            if a and rowIdx[a] == idx - 1 then
                local mx, ma = roster[x], roster[a]
                if mx and ma and mx.lo and ma.hi and ma.hi <= mx.lo then keep = false end
            end
        end
        if keep then
            n = n + 1
            list[n] = x
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- The members of `list` whose Interrupts list may hold `spell`: those known
-- to hold it, and those with entries the engine never learned (which could
-- be anything). A record never read may hold anything too.
local function MayHold(list, spell)
    local n = 0
    for i = 1, #list do
        local m = roster[list[i]]
        if m and (not m.known or m.holes > 0 or m.known[spell]) then
            n = n + 1
            list[n] = list[i]
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- Picks the kicker from a candidate list. With the kicked spell known, one
-- member whose list holds it for sure is the kicker (a repeat of a spell
-- they kicked before: the meter shows nothing new for it); with it hidden,
-- only members with entries could have kicked unseen, and `unseen` (the
-- kick moved no row) lets the meter's order rule out more. One left by
-- those deductions is the kicker; several are narrowed by cooldown.
local function Pick(list, T, spell, unseen)
    local before = #list
    if spell then
        MayHold(list, spell)
        if #list == 1 then
            local m = roster[list[1]]
            if m and m.known and m.known[spell] then return list[1], "repeat", nil end
        end
    else
        Entered(list)
    end
    if unseen then TieNarrow(list) end
    if #list == 1 and before > 1 then return list[1], "order", nil end
    wipe(preNarrow)
    for i = 1, #list do preNarrow[i] = list[i] end
    return Narrow(list, T, nil)
end

-- Your cast is unresolved and `T` lies within its window after it.
local function OwnPending(T)
    return ownPending and T >= ownT and T - ownT <= OWN_WINDOW
end

local function RecordKick(m, T, sure)
    m.lastKick, m.lastSure = T, sure
    if m.unit == "player" then
        ownPending = false
        -- Your cast started its plain cooldown: the landed one replaces it
        -- from the same start (Coldthirst, Light of the Sun).
        if m.downAt and m.landedCd and m.downFor ~= m.landedCd and T - m.downAt <= OWN_WINDOW then
            StartCd(m, m.downAt, m.landedCd)
        end
    elseif m.landedCd then
        StartCd(m, T, m.landedCd)
    end
end

-- The one member whose list grew by one entry on the last update, paired
-- with the one plate kicked in this batch: that entry is the plate's spell.
-- Not while your own cast is unresolved: it may be the kick that stopped
-- this plate, the entry another member's kick of a mob with no plate.
local function PairLearn()
    local u = memo.learn
    if not u then return end
    memo.learn = nil
    if #stopped ~= 1 or OwnPending(GetTime()) then return end
    local spell = stoppedSpell[1]
    local m = roster[u]
    if spell and m and m.known and m.holes > 0 then
        m.holes = m.holes - 1
        m.known[spell] = true
    end
end

-- The gate packet for update T: every member but you with an interrupt who
-- could have landed it (not still on cooldown from a kick that was theirs
-- for sure, which a sure kicker of this update is now too), with entries
-- before and after it (a member whose list grew is named by the list), and
-- their gate source's count before and after it, handed on as they are:
-- hidden in combat, never read here. Built in the update's own frame, from
-- the counts Attribute just read. Returns whether anyone is in it.
local function BuildGate(T)
    wipe(gateList)
    wipe(gatePrev)
    wipe(gateCur)
    gateT = T
    local pa, pg, ca, cg = readPrevA, readPrevG, memo.a, memo.g
    for i = 2, #GROUP_UNITS do
        local u = GROUP_UNITS[i]
        local m = roster[u]
        if m and m.guid and m.kick and not StillDown(m, T) then
            local before, after = pa[u], ca[u]
            if before ~= nil and after ~= nil and (pg[u] or 0) >= 1 and (cg[u] or 0) >= 1 then
                gateList[#gateList + 1] = u
                gatePrev[u], gateCur[u] = before, after
            end
        end
    end
    memo.gated = #gateList > 0
    return memo.gated
end

-- Sends the packet built for update T: with the plates stopped in its batch
-- when nobody was placed on them for sure, else for the bars alone; or, with
-- `platesOnly`, those plates joining the packet already sent (a plate whose
-- cast stopped after the meter's update, in its window).
local function SendGate(T, withPlates, platesOnly)
    if gateT ~= T or #gateList == 0 then return end
    wipe(gatePlates)
    if withPlates then
        for i = 1, #stopped do gatePlates[i] = stopped[i] end
    end
    if platesOnly and #gatePlates == 0 then return end
    Dispatch("gate", T, gateList, gatePrev, gateCur, gatePlates, platesOnly and true or false)
end

-- Reports the kick to the displays for each plate unit kicked this frame.
local function EmitStopped(T, who, list, how)
    for i = 1, #stopped do
        Dispatch("kick", stopped[i], who, list, stoppedBy[i], how, T)
    end
    wipe(stopped)
    wipe(stoppedBy)
    wipe(stoppedSpell)
    stoppedT = -1
end

-- Forward: Settle is defined below the pieces it settles with.
local Settle

-- Plate events the meter never answered within PAIR_WINDOW: their plates
-- show the hidden kicker only (your own unanswered cast does not claim them:
-- it may have missed, and your icon moved at the cast). A newer batch still
-- inside its window waits on.
local function FlushStopped()
    flushArmed = false
    if #stopped == 0 then return end
    local left = PAIR_WINDOW - (GetTime() - stoppedT)
    if left > 0.001 then
        flushArmed = true
        C_Timer.After(left, FlushStopped)
        return
    end
    EmitStopped(stoppedT, nil, nil, "unknown")
end

-- Settles who kicked from the evidence, best first: a member whose breakdown
-- grew, the member a new or moved row names, your own cast a moment ago, the
-- member whose list holds the kicked spell (where a plate named it), then
-- whoever is not on cooldown. grewBy: the entries the one grown list gained;
-- plates: the casts stopped in the batch paired with this. Returns who, how,
-- the list while several are left, and whether the answer is sure.
local function Decide(T, rowKey, rowHow, grew, grewBy, oneNew, spell, plates)
    local who, how, list
    if grew and #grew == 1 then
        who, how = grew[1], "breakdown"
        -- The row that moved is the kicker's, and so is the one row that
        -- appeared with their first kick: either names their spec.
        if rowKey and (rowHow == "reorder" or oneNew) then LearnRow(roster[who], rowKey, T) end
        -- The meter counts every interrupt, a grip of a caster included.
        -- Several entries or several casts stopped at once is a grip of a
        -- whole pack; one while the member's kick cannot be ready is a grip
        -- too (your own, a cast of yours the engine never saw). Neither is a
        -- kick: nothing is placed and no cooldown starts.
        local m = roster[who]
        if grewBy > 1 or plates > 1 then
            return nil, "mass", nil, false
        elseif who == "player" then
            if not OwnPending(T) then return nil, "grip", nil, false end
        elseif m and StillDown(m, T) then
            return nil, "grip", nil, false
        end
    elseif grew and #grew > 1 then
        -- Several lists grew at once: each of those members kicked (Settle
        -- records them all); which of them stopped this plate is narrowed
        -- among them alone.
        list = scratch
        wipe(list)
        for i = 1, #grew do list[i] = grew[i] end
    elseif rowKey then
        list = KeyUnits(rowKey, scratch)
        if #list == 1 then
            who, how, list = list[1], rowHow, nil
            LearnRow(roster[who], rowKey, T)
        elseif #list == 0 then
            list = nil
        end
    end
    if not who and not list then
        if OwnPending(T) then
            who, how = "player", "cast"
        else
            who, how, list = Pick(AllOthers(scratch), T, spell, true)
        end
    elseif list then
        who, how, list = Pick(list, T, spell, false)
        if who and how == "only" and rowHow then how = rowHow end
    end
    local sure = how == "cast" or how == "breakdown" or how == "new row" or how == "reorder" or how == "repeat"
        or how == "order"
    return who, how, list, sure
end

-- Keeps the count bounds in step with this update's verdict: a grown list
-- is that many kicks for sure (a mass interrupt or a grip: at least), a sure
-- kicker one more, an unsure one or an ambiguous list one more for each
-- member it could have been, and no answer at all one more for everyone.
local function Bound(who, how, list, grew)
    if grew and #grew > 0 then
        local exact = not (how == "mass" or how == "grip")
        for i = 1, #grew do
            local u = grew[i]
            Count(roster[u], growth[u] or 1, exact)
        end
    elseif who then
        if how == "only" or how == "cooldown" then
            Loosen(preNarrow)
        else
            Count(roster[who], 1, true)
        end
    elseif list then
        Loosen(list)
    else
        LoosenAll()
    end
end

-- Decides, records the kick and, with `emit`, tells the displays about the
-- plates waiting for it (the one plate kicked then names the spell).
Settle = function(T, rowKey, rowHow, grew, grewBy, emit, oneNew)
    local spell = emit and #stopped == 1 and stoppedSpell[1] or nil
    local who, how, list, sure = Decide(T, rowKey, rowHow, grew, grewBy, oneNew, spell, emit and #stopped or 0)
    Bound(who, how, list, grew)
    local several = grew and #grew > 1
    if several then
        -- Every member whose list grew kicked, whichever plate this was.
        for i = 1, #grew do
            local m = roster[grew[i]]
            if m then RecordKick(m, T, true) end
        end
    elseif who and sure then
        local m = roster[who]
        if m then RecordKick(m, T, true) end
    end
    -- Only a kicker named for sure is placed and timed; the gate packet shows
    -- any other answer exactly, by whose count rose, and any kick of another
    -- member this update hid. A grip (one, or a whole pack) is no kick: no
    -- packet. With several kickers named, which of them stopped this plate is
    -- not known: it gets nobody.
    local placed = (sure and not several) and who or nil
    memo.lastT, memo.who, memo.scratch, memo.how = T, placed, list, how
    memo.rowKey, memo.rowHow = rowKey, rowHow
    memo.grew = (grew and #grew > 0) and true or false
    memo.gated = false
    if how ~= "mass" and how ~= "grip" and BuildGate(T) then
        SendGate(T, emit and not placed and not several, false)
    end
    if emit then
        memo.pairedT = T
        PairLearn()
        EmitStopped(stoppedT, placed, list, how)
    end
end

-- The first Interrupts-typed meter update of a frame against the last one.
local function Attribute()
    local T = GetTime()
    if T == memo.frameT then return end
    memo.frameT = T
    local keys, nmap, sid = ReadRows(spareKeys, spareN, spareA, spareG)
    local amap, gmap = spareA, spareG
    CarryCounts(nmap, amap, gmap)
    local prevKeys, prevN, prevA, prevG = memo.rows, memo.n, memo.a, memo.g
    -- A count that fell: a new fight began without its session update, and
    -- the lists restarted with it.
    local shrank = ListsMoved(keys, nmap, prevKeys, prevN)
    memo.rows, memo.n, memo.a, memo.g, lastSession = keys, nmap, amap, gmap, sid
    spareKeys, spareN, spareA, spareG = prevKeys, prevN, prevA, prevG
    if shrank then
        prevKeys, prevN, prevA, prevG = EMPTY, EMPTY, EMPTY, EMPTY
        ResetLists()
    end
    -- The counts before this update, for its gate packet (BuildGate).
    readPrevA, readPrevG = prevA, prevG
    SyncLists(nmap, prevN)
    -- Every member's count as read now, for the displays' count gates: a
    -- member with entries (so their count is one at least), never you.
    -- Handed on as read, hidden in combat; read at once, never kept.
    wipe(countList)
    for i = 2, #GROUP_UNITS do
        local u = GROUP_UNITS[i]
        if (gmap[u] or 0) >= 1 and amap[u] ~= nil then countList[#countList + 1] = u end
    end
    if #countList > 0 then Dispatch("counts", T, countList, amap) end

    wipe(grew)
    wipe(growth)
    local grewBy = 0
    for u, n in pairs(nmap) do
        local d = n - (prevN[u] or 0)
        if d > 0 then
            grew[#grew + 1] = u
            growth[u] = d
            grewBy = d
        end
    end
    -- One member's list grew: by one entry, the plate paired with this
    -- update names its spell; by more, a grip of a pack.
    if #grew ~= 1 then grewBy = 0 end
    memo.learn = (grewBy == 1) and grew[1] or nil
    local rowKey, rowHow, newCount = nil, nil, 0
    if #keys > #prevKeys then
        wipe(left)
        for i = 1, #prevKeys do left[prevKeys[i]] = (left[prevKeys[i]] or 0) + 1 end
        for i = 1, #keys do
            local k = keys[i]
            if (left[k] or 0) > 0 then left[k] = left[k] - 1 else rowKey = k; newCount = newCount + 1 end
        end
        rowHow = "new row"
    elseif #keys == #prevKeys then
        for i = 1, #keys do
            if keys[i] ~= prevKeys[i] then rowKey, rowHow = keys[i], "reorder"; break end
        end
    end
    -- A row no member can own (an enemy that interrupted a player) is no
    -- evidence of a kick.
    if rowKey and #KeyUnits(rowKey, scratch) == 0 then rowKey, rowHow = nil, nil end
    -- Plates whose cast stopped just before (the same frame, as seen in the
    -- field, or within the window) take this update's answer.
    local landedHere = stoppedT >= 0 and T - stoppedT <= PAIR_WINDOW
    -- A refresh with nothing new and no kick seen says nothing to read (any
    -- member with entries may have landed it, or an enemy that interrupted
    -- a player); the gate packet shows whoever's count rose, and a plate
    -- event a moment later joins it (OnStop).
    if not rowKey and #grew == 0 and not OwnPending(T) and not landedHere then
        LoosenAll()
        memo.lastT, memo.who, memo.scratch, memo.how = T, nil, nil, "none"
        memo.rowKey, memo.rowHow, memo.grew = nil, nil, false
        if BuildGate(T) then SendGate(T, false, false) end
        return
    end
    Settle(T, rowKey, rowHow, grew, grewBy, landedHere, newCount == 1)
end

-- The batch of plates stopped at stoppedT takes the meter's update at T0 (the
-- same frame's, or an earlier frame's no batch took yet): the plates are
-- emitted with its answer, decided again with the batch where it lacked one.
local function PairWith(T0)
    local T = stoppedT
    -- Nobody was placed on an update no list grew in: decided again with
    -- the batch it lacked. An update with nothing to read always is (a
    -- plate first gives the batch's size; its spell, plain outside a key,
    -- can name the one member whose list holds it); any other only with
    -- that spell named, and not over an unresolved cast of yours.
    local named = #stopped == 1 and stoppedSpell[1] or nil
    local none = memo.how == "none"
    if not memo.who and not memo.grew and (none or (named and not OwnPending(T))) then
        local who, how, list, sure = Decide(T0, memo.rowKey, memo.rowHow, nil, 0, false, named, #stopped)
        if who and sure and how ~= "mass" and how ~= "grip" then
            local m = roster[who]
            if m then
                RecordKick(m, T0, true)
                Count(m, 1, true)
            end
            memo.who = who
        end
        memo.scratch, memo.how = list, how
    end
    memo.pairedT = T0
    PairLearn()
    -- Still nobody: the plate joins the update's gate packet.
    if not memo.who and memo.gated then SendGate(T0, true, true) end
    EmitStopped(stoppedT, memo.who, memo.scratch, memo.how)
end

-- A stop that found only an EARLIER frame's update, a frame later: a kick's
-- own update arrives in the frame of its cast stop (the field, every run),
-- so an update with no plate in its frame was a kick on a mob this client
-- has no plate for (a tank kicking off screen), and the next stop within the
-- window is most often another member's kick, whose own update lands in the
-- stop's frame, after the stop. That update takes the batch (Attribute's
-- landedHere) and this finds it gone; only when the frame brought none does
-- the earlier verdict serve the batch, as it always did.
local function LatePair()
    lateArmed = false
    if #stopped == 0 then return end
    local T0 = memo.lastT
    if T0 >= 0 and stoppedT - T0 <= PAIR_WINDOW and memo.pairedT ~= T0 then PairWith(T0) end
end

-- A plate's cast stopped. A hidden (or plain, non-empty) interrupter is a
-- kick; nil or "" is crowd control or a natural end. An enemy's spell is
-- plain; a hidden one is kept as unknown.
local function OnStop(unit, spell, by)
    if not NAMEPLATE_UNITS[unit] then return end
    if type(by) == "nil" then return end
    if not Secret(by) and (type(by) ~= "string" or by == "") then return end
    local T = GetTime()
    if stoppedT < 0 or T - stoppedT > PAIR_WINDOW then
        -- An older batch the meter never answered goes out first.
        if #stopped > 0 then EmitStopped(stoppedT, nil, nil, "unknown") end
        stoppedT = T
    end
    for i = 1, #stopped do
        if stopped[i] == unit then return end
    end
    stopped[#stopped + 1] = unit
    stoppedBy[#stopped] = by
    stoppedSpell[#stopped] = (type(spell) == "number" and not Secret(spell)) and spell or false
    -- The meter spoke first in this frame: its answer, now.
    if memo.lastT == T then
        PairWith(T)
        return
    end
    -- A recent update no frame has taken yet: next frame, unless this frame
    -- brings the batch an update of its own (LatePair). The flush below is
    -- the fallback either way.
    if memo.lastT >= 0 and T - memo.lastT <= PAIR_WINDOW and memo.pairedT ~= memo.lastT and not lateArmed then
        lateArmed = true
        C_Timer.After(0, LatePair)
    end
    if not flushArmed then
        flushArmed = true
        C_Timer.After(PAIR_WINDOW, FlushStopped)
    end
end

-- Your target's nameplate token, or nil: UnitIsUnit may compare "target"
-- with a plate token on any map; a hidden answer never counts as a match.
local function TargetPlate()
    if not UnitExists("target") then return nil end
    for i = 1, #NAMEPLATE_TOKENS do
        local token = NAMEPLATE_TOKENS[i]
        if UnitExists(token) then
            local ok, same = pcall(UnitIsUnit, "target", token)
            if ok and not Secret(same) and same == true then return token end
        end
    end
    return nil
end

-- Your own kick (or your demon's): the model starts now with the plain
-- cooldown; the landed kick a moment later may shorten it. Your icon goes to
-- your target's plate at once (a missed kick stops nothing, so nothing else
-- would ever report it).
local function OnOwnCast(spellID)
    if Secret(spellID) then return end
    local kick = KD.OwnCastKick(spellID)
    if not kick then return end
    local m = roster.player
    if not m then return end
    local T = GetTime()
    ownT, ownPending = T, true
    if m.kick ~= kick then
        m.kick = kick
        m.cd, m.landedCd = KD.Cooldown(kick, m.specID, m.talents)
    end
    if m.cd then StartCd(m, T, m.cd) end
    m.lastKick, m.lastSure = T, true
    local plate = TargetPlate()
    if plate then Dispatch("kick", plate, "player", nil, nil, "cast", T) end
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local LIVE_EVENTS = {
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    "GROUP_ROSTER_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "SPELLS_CHANGED",
    "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_REGEN_ENABLED", "CHALLENGE_MODE_START", -- guardrails-allow: combat-deferral by Ellesmere: the engine's combat-end edge (specs from the meter rows, stale talent re-reads, the next inspect), live only while a display subscribes and dropped at Deactivate; a recurring listener, not a one-shot deferral
    "PLAYER_ENTERING_WORLD",
}

local function OnEvent(_, event, a1, a2, a3, a4, a5)
    if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        if a1 == INT then Attribute() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnOwnCast(a3)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        OnStop(a1, a3, a4)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        OnStop(a1, a3, a5)
    elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        Rebase()
    elseif event == "DAMAGE_METER_RESET" then
        Rebase(true)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- A roster storm (a load, a group forming) syncs once per frame, and
        -- once more after it: the burst's last event carries its final state.
        local T = GetTime()
        if T ~= rosterT then
            rosterT = T
            SyncRoster()
            if not InCombatLockdown() then LearnSpecs() end
        elseif not rosterFlush then
            rosterFlush = true
            C_Timer.After(0, function()
                rosterFlush = false
                if not active then return end
                SyncRoster()
                if not InCombatLockdown() then LearnSpecs() end
            end)
        end
    elseif event == "UNIT_PET" then
        local m = roster[a1]
        if m and m.class == "WARLOCK" then
            m.pet = PetFamily(a1)
            if ResolveKick(m) then Dispatch("roster", GetTime()) end
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if a1 == "player" then
            RefreshPlayer()
        else
            local m = a1 and roster[a1]
            if m and m.guid then
                m.specID, m.specIcon, m.specSrc, m.talents, m.readAt = nil, nil, nil, nil, nil
                if ResolveKick(m) then Dispatch("roster", GetTime()) end
                AskRead(a1)
            end
        end
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "SPELLS_CHANGED" then
        RefreshPlayer()
    elseif event == "INSPECT_READY" then
        OnReadReady(a1)
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if a1 == RT_COMBAT and a2 == RS_INACTIVE then LearnSpecs() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        LearnSpecs()
        ReReadStale()
        ReadNext()
    elseif event == "CHALLENGE_MODE_START" then
        -- A last chance before the key locks the inspect data.
        ReReadStale()
        ReadNext()
    elseif event == "PLAYER_ENTERING_WORLD" then
        for _, m in pairs(roster) do ClearCd(m) end
        wipe(stopped)
        wipe(stoppedBy)
        wipe(stoppedSpell)
        stoppedT = -1
        ownPending = false
        memo.lastT, memo.pairedT, memo.who, memo.scratch, memo.how = -1, -1, nil, nil, nil
        memo.rowKey, memo.rowHow, memo.learn, memo.gated, memo.grew = nil, nil, nil, false, false
        gateT = -1
        Rebase(true)
        SyncRoster()
        ReReadStale()
    end
end

local function Activate()
    if active then return end
    active = true
    if not evt then
        evt = CreateFrame("Frame")
        evt:SetScript("OnEvent", OnEvent)
    end
    for i = 1, #LIVE_EVENTS do evt:RegisterEvent(LIVE_EVENTS[i]) end
    evt:RegisterUnitEvent("UNIT_PET", "player", "party1", "party2", "party3", "party4")
    memo.frameT = -1
    Rebase(true)
    SyncRoster()
    RegisterOwnCasts()
    if not InCombatLockdown() then LearnSpecs() end
    ReReadStale()
    ReadNext()
end

local function Deactivate()
    if not active then return end
    active = false
    evt:UnregisterAllEvents()
    if readingUnit then DoneReading() end
    wipe(readList)
    wipe(readAsked)
    wipe(stopped)
    wipe(stoppedBy)
    wipe(stoppedSpell)
    stoppedT = -1
    ownPending = false
    for _, m in pairs(roster) do
        m.downAt, m.downFor, m.readyAt = nil, nil, nil
    end
    wipe(gateList)
    wipe(gatePrev)
    wipe(gateCur)
    wipe(gatePlates)
    gateT, memo.gated = -1, false
end

--------------------------------------------------------------------------------
--  Public surface
--------------------------------------------------------------------------------
-- handlers: { kick = fn(plateUnit, kickerUnit|nil, candidates|nil, interrupter,
-- how, t), cooldown = fn(unit, start|nil, dur|nil), roster = fn(t),
-- gate = fn(t, units, before, after, plates, platesOnly) }. kick names a
-- kicker only when the engine is sure of them (and starts their cooldown);
-- gate is every update's exact answer for everyone else: `units` the members
-- who could have kicked at t, `before` / `after` their interrupt counts by
-- unit (hidden in combat: handed to a status bar as value and maximum, never
-- read), `plates` the plates kicked in that update nobody was placed on (or,
-- with platesOnly, plates joining the packet already sent for t). A display
-- shows member u's kick at t, with u's cooldown (KE.KickDuration) from t,
-- only where u's count rose. counts = fn(t, units, after) comes with every
-- update, before its kick or gate: `units` the members with entries (never
-- you), `after` their counts as read now, for the displays' own count gates
-- (a kick's icon hidden once its kicker's count rose past the count at that
-- kick). Every table is the engine's own scratch, read at once and never
-- kept. The first subscriber starts the engine, the last leaving stops it.
-- The content the tracker runs in at all: Mythic and Mythic+ dungeons and
-- arenas, as the Where buckets of EUI_MythicTimer_Where.lua name them. The
-- Where to Show filter offers these keys alone, and both displays ask Allowed
-- before going live, so elsewhere nothing subscribes and the engine sleeps.
KE.WHERE_LIST = { "dungeon_mythic", "arena" }

function KE.Allowed()
    local bucket = MTWhere.Bucket and MTWhere.Bucket()
    return bucket == "dungeon_mythic" or bucket == "arena"
end

function KE.Subscribe(key, handlers)
    if not subs[key] then subCount = subCount + 1 end
    subs[key] = handlers
    Activate()
end

function KE.Unsubscribe(key)
    if not subs[key] then return end
    subs[key] = nil
    subCount = subCount - 1
    if subCount <= 0 then
        subCount = 0
        Deactivate()
    end
end

function KE.IsActive()
    return active
end

-- A member record: unit, guid, class, specID, kick (spell ID, false for none,
-- nil unknown), cd, landedCd, minCd (the landed cooldown with every cooldown
-- talent), downAt, downFor, readyAt, what their Interrupts list holds (known,
-- holes) and the bounds on their hidden interrupt count (lo, hi). Read-only
-- by contract.
function KE.Member(unit)
    return roster[unit]
end

-- A member's interrupt count as the meter last read it (their gate source's:
-- their demon's for a demon's interrupt), hidden in combat and only ever to
-- be handed to a native sink, or nil while none was read. The displays' count
-- gates take it as a baseline at a sure kick and as the maximum at every
-- update (the counts event).
function KE.Count(unit)
    return memo.a[unit]
end

-- The fight the counts belong to: a plain number that moves whenever they
-- restart (a new fight, a reset, a load). A count taken in an older fight is
-- no baseline for this one.
function KE.FightGen()
    return fightGen
end

-- The cooldown a member is held to before they could kick again after a kick
-- the engine timed: their landed cooldown, or the shortest they could have
-- (every cooldown talent) while their talents were never read; nil while
-- their interrupt is not known. StillDown's own measure, less KE.ELIM_SLACK.
function KE.DownFor(unit)
    local m = roster[unit]
    if not (m and m.kick) then return nil end
    return m.talents and m.landedCd or m.minCd
end
KE.ELIM_SLACK = ELIM_SLACK

-- How long a member's interrupt is down after a kick the tracker saw land
-- (their landed cooldown: Coldthirst and Light of the Sun shorten only that),
-- or nil while their interrupt is not known.
function KE.KickDuration(unit)
    local m = roster[unit]
    if not (m and m.kick) then return nil end
    return m.landedCd or m.cd
end

-- The modeled cooldown of a member's interrupt: start, duration and end time,
-- nil while ready or unknown.
function KE.Cooldown(unit)
    local m = roster[unit]
    if not (m and m.downAt) then return nil end
    if m.readyAt <= GetTime() then return nil end
    return m.downAt, m.downFor, m.readyAt
end
