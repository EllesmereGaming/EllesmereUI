if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmTalentConditions.lua
--  Per-spell Talent Conditions for cooldown/utility icons: the icon shows only
--  while every condition on it holds ("talent X taken", "talent Y not taken").
--  A condition that fails drops the icon from the reanchor pass exactly like an
--  unlearned spell (ns.TalentCondFilterPass, called by CollectAndReanchor before
--  Phase 3): Phase 4 parks it and the icons after it close the gap.
--  Empty Slots store conditions under their unique marker in the same CD-family
--  store and check them during injection, after the Blizzard-frame filter.
--
--  Stored on the spell's own per-spell entry (spellSettingsCD[sid]):
--      talentConditions = { { nodeID = n, entryID = e, spellID = s, taken = bool }, ... }
--  entryID only for a choice node (which side must be picked); spellID is for
--  display only. Per spell ONLY, like Custom Icon: never written to the
--  Apply-to-Bar tiers, so every read is a rawget on the spell's own entry.
--
--  Cost: nothing until some saved spell has a condition. ns._cdmAnyTalentCond is
--  set once by RescanTalentCondFlag at setup, or by the options popup on first
--  use (monotonic, like the other per-spell gates). Once set, the reanchor asks
--  the filter per claimed cooldown frame; the answer comes from a node-state
--  cache filled lazily from C_Traits, one lookup per node. The cache is keyed by
--  the active config ID (changes on a spec swap only) and wiped by
--  ns.TalentCondInvalidate on every talent event (edits and loadout loads keep
--  the config ID). Talent edits already queue a full CDM rebuild, which re-runs
--  the filter, so no events of our own are registered.
-------------------------------------------------------------------------------
local _, ns = ...

local wipe = wipe
local tremove = table.remove

-- nodeID -> the node's committed entryID when taken (true if the client reports
-- a rank but no entry), false when not taken or not part of the active tree.
local _nodeState = {}
local _nodeStateConfig = nil

-- Talent edit landed (TRAIT_CONFIG_UPDATED and friends): forget every node.
function ns.TalentCondInvalidate()
    wipe(_nodeState)
    _nodeStateConfig = nil
end

local function NodeState(nodeID, configID)
    if configID ~= _nodeStateConfig then
        -- Spec swap: a different config, so every cached rank is stale.
        wipe(_nodeState)
        _nodeStateConfig = configID
    end
    local st = _nodeState[nodeID]
    if st == nil then
        st = false
        -- Guarded: a saved nodeID can outlive a talent-tree rework in a patch.
        -- Runs on a cache miss only (once per node per talent change).
        local ok, info
        if configID then ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID) end
        if ok and info then
            -- Committed state only: activeRank/activeEntry also count picks staged
            -- in the talent UI and never applied. A granted rank (activeRank above
            -- ranksPurchased) cannot be staged, so it counts as taken as well.
            local committed = info.entryIDsWithCommittedRanks
            if committed and #committed > 0 then
                st = committed[1]
            elseif (info.activeRank or 0) > (info.ranksPurchased or 0) then
                st = (info.activeEntry and info.activeEntry.entryID) or true
            end
        end
        _nodeState[nodeID] = st
    end
    return st
end

local function IsTaken(nodeID, entryID, configID)
    local st = NodeState(nodeID, configID)
    if st == false then return false end
    return entryID == nil or st == entryID
end

-- A node that is not in the active tree reads as not taken.
local function Hold(conds, configID)
    if type(conds) ~= "table" then return true end
    for i = 1, #conds do
        local c = conds[i]
        if type(c) == "table" and c.nodeID then
            if IsTaken(c.nodeID, c.entryID, configID) ~= (c.taken ~= false) then
                return false
            end
        end
    end
    return true
end

-- True when the node (or, for a choice node, that side of it) is taken right now.
function ns.TalentCondIsTaken(nodeID, entryID)
    return IsTaken(nodeID, entryID, C_ClassTalents.GetActiveConfigID())
end

-- True when every condition in the list holds (an empty or missing list holds).
function ns.TalentConditionsHold(conds)
    return Hold(conds, C_ClassTalents.GetActiveConfigID())
end

-- Empty Slots are injected after TalentCondFilterPass, with no spell resolver.
function ns.EmptySlotTalentConditionsHold(barKey, marker)
    if not ns._cdmAnyTalentCond then return true end
    local store = ns.GetSpellSettingsStore(barKey)
    local entry = store and store[marker]
    local conds = type(entry) == "table" and rawget(entry, "talentConditions")
    return not conds or ns.TalentConditionsHold(conds)
end

-------------------------------------------------------------------------------
--  Reanchor filter. Drops every CD/utility frame whose conditions fail this pass
--  and records it per bar, so the reseeds still count the spell as present: it
--  keeps its preview slot and its conditions stay reachable. The records are
--  reused tables, wiped per pass and read-only for callers.
-------------------------------------------------------------------------------
local _ecmeFC = ns._ecmeFC
local _hookFrameData = ns._hookFrameData
local _hiddenSets = {}     -- barKey -> { [spellID] = true }
local _hiddenFrames = {}   -- barKey -> { frame, ... }
local _anyHidden = false
local _empty = {}

-- Spells the filter dropped from this bar in the last pass (shared empty table when none).
function ns.TalentCondHiddenSet(barKey)
    return (barKey and _hiddenSets[barKey]) or _empty
end

-- The dropped frames themselves, same lifetime (shared empty list when none).
function ns.TalentCondHiddenFrames(barKey)
    return (barKey and _hiddenFrames[barKey]) or _empty
end

-- cdFrames: CollectAndReanchor's per-bar frame lists (edited in place). Called only
-- while ns._cdmAnyTalentCond is set, which never clears in a session, so every
-- claimed frame passes through here and a stale tcHidden tag always gets cleared.
function ns.TalentCondFilterPass(cdFrames)
    if _anyHidden then
        for _, s in pairs(_hiddenSets) do wipe(s) end
        for _, l in pairs(_hiddenFrames) do wipe(l) end
        _anyHidden = false
    end
    local configID   -- read once, on the first frame that carries conditions (false = none)
    for bk, frames in pairs(cdFrames) do
        for i = #frames, 1, -1 do
            local frame = frames[i]
            local fc = _ecmeFC[frame]
            if fc then
                local conds
                local cdSid = fc.replacesCd
                if cdSid then
                    -- Replace-with-Buff frame: follows its cooldown's own CD-family
                    -- entry. The resolver would read the buff store for this
                    -- buff-viewer frame on any bar that has ever hosted a buff.
                    local store = ns.GetSpellSettingsStore(bk)
                    local e = store and store[cdSid]
                    conds = type(e) == "table" and rawget(e, "talentConditions") or nil
                elseif not fc.isHostedBuff then
                    -- Hosted buffs are buff-family and never carry the setting.
                    local sid = fc.spellID
                    if sid and sid > 0 then
                        local ss = ns.ResolveSpellSettings(frame, sid, false, bk)
                        conds = ss and rawget(ss, "talentConditions")
                    end
                end
                local hide = false
                if conds then
                    if configID == nil then configID = C_ClassTalents.GetActiveConfigID() or false end
                    hide = not Hold(conds, configID or nil)
                end
                if hide then
                    tremove(frames, i)
                    local sid = fc.spellID
                    if sid then
                        local set = _hiddenSets[bk]
                        if not set then
                            set = {}
                            _hiddenSets[bk] = set
                            _hiddenFrames[bk] = {}
                        end
                        set[sid] = true
                        local list = _hiddenFrames[bk]
                        list[#list + 1] = frame
                        _anyHidden = true
                    end
                    -- A hidden icon stays silent: out of the CD Ready Sound watch and
                    -- disarmed; the tag (our FC entry, never the frame) also mutes the
                    -- available-alert hook until a pass lets the frame back in.
                    fc.tcHidden = true
                    ns._cdReadySoundWatch[frame] = nil
                    local fd = _hookFrameData[frame]
                    if fd then fd._cdReadyArmed = false end
                    if cdSid then
                        -- Buff-viewer frame: Phase 4 leaves these hands-off, so blank it
                        -- here or it stays at its old slot over the collapsed bar. The
                        -- SetPoint hook keeps it blank while unclaimed; a re-claim
                        -- restores alpha and anchor.
                        if fd then fd._cdmAnchor = nil end
                        frame:SetAlpha(0)
                        -- Alpha does not stop hit-testing: drop the tooltip motion the bar
                        -- gave it, or it keeps catching hover and [@mouseover] over that
                        -- slot. Every pass (Blizzard's re-acquire turns it back on); a
                        -- re-claim re-applies the bar's tooltip setting. Mouse calls are
                        -- blocked in combat, where it keeps its motion until the next pass.
                        if frame.EnableMouseMotion and not InCombatLockdown() then
                            frame:EnableMouseMotion(false)
                        end
                    end
                elseif fc.tcHidden then
                    fc.tcHidden = nil
                end
            end
        end
    end
end

-- Talent Conditions gate: set ns._cdmAnyTalentCond once if any saved spell (any spec)
-- has a condition. Skips the reanchor filter for non-users. Same monotonic, scanned-once
-- contract as the other per-spell gates; talentConditions is never written to bar tiers.
function ns.RescanTalentCondFlag()
    if ns._cdmAnyTalentCond or ns._talentCondFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._talentCondFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        local conds = rawget(ss, "talentConditions")
        if type(conds) == "table" and #conds > 0 then
            ns._cdmAnyTalentCond = true
            return true
        end
    end)
end
