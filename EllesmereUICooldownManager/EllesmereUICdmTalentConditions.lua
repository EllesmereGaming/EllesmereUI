if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmTalentConditions.lua
--  Per-spell Talent Conditions for cooldown/utility icons: the icon shows only
--  while every condition on it holds ("talent X taken", "talent Y not taken").
--  A condition that fails drops the icon from the reanchor pass exactly like an
--  unlearned spell (CollectAndReanchor, Phase 3 prologue): Phase 4 parks it and
--  the icons after it close the gap.
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
--  TalentConditionsHold per claimed cooldown frame; the answer comes from a
--  node-state cache filled lazily from C_Traits, one lookup per node, and
--  dropped when the active talent config changes (spec or loadout switch) or a
--  talent edit lands. Talent edits already queue a full CDM rebuild, which
--  re-runs the filter, so no events of our own are registered.
-------------------------------------------------------------------------------
local _, ns = ...

local wipe = wipe

-- nodeID -> the node's active entryID when taken (true if the client reports a
-- rank but no entry), false when not taken or not part of the active tree.
local _nodeState = {}
local _nodeStateConfig = nil

-- Talent edit landed (TRAIT_CONFIG_UPDATED and friends): forget every node.
function ns.TalentCondInvalidate()
    wipe(_nodeState)
    _nodeStateConfig = nil
end

local function NodeState(nodeID)
    local configID = C_ClassTalents.GetActiveConfigID()
    if configID ~= _nodeStateConfig then
        -- Spec or loadout switch: a different config, so every cached rank is stale.
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
        if ok and info and (info.activeRank or 0) > 0 then
            st = (info.activeEntry and info.activeEntry.entryID) or true
        end
        _nodeState[nodeID] = st
    end
    return st
end

-- True when the node (or, for a choice node, that side of it) is taken right now.
function ns.TalentCondIsTaken(nodeID, entryID)
    local st = NodeState(nodeID)
    if st == false then return false end
    return entryID == nil or st == entryID
end

-- True when every condition in the list holds (an empty or missing list holds).
-- A node that is not in the active tree reads as not taken.
function ns.TalentConditionsHold(conds)
    if type(conds) ~= "table" then return true end
    for i = 1, #conds do
        local c = conds[i]
        if type(c) == "table" and c.nodeID then
            if ns.TalentCondIsTaken(c.nodeID, c.entryID) ~= (c.taken ~= false) then
                return false
            end
        end
    end
    return true
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
