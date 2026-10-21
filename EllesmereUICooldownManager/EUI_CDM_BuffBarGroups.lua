if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarGroups.lua
--
--  The frame table, the idle sleeper, bar groups (per spec and global), style
--  copy, style presets and the group reflow.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local SetECME, SetAssignDirty, SetReflowDirty = I.SetECME, I.SetAssignDirty, I.SetReflowDirty

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
I.ecmeSetters[#I.ecmeSetters + 1] = function(v) ECME = v end
-- True while any bar uses a Visibility mode/option, i.e. a state no tick-side aura or
-- cooldown edge can reveal. Gates the dispatcher wake below so profiles that never touch
-- Visibility keep the idle sleeper's original wake set.
local _anyVisCond = false
I.anyVisCondSetters[#I.anyVisCondSetters + 1] = function(v) _anyVisCond = v end

-------------------------------------------------------------------------------
--  Frame Table & State
-------------------------------------------------------------------------------
local tbbFrames  = {}
local tbbTickFrame
I.tickFrameSetters[#I.tickFrameSetters + 1] = function(v) tbbTickFrame = v end
local _tbbRebuildPending = false
I.rebuildPendingSetters[#I.rebuildPendingSetters + 1] = function(v) _tbbRebuildPending = v end

-- Group reflow gate: ReflowGroup's inputs are the visible member sequence plus the
-- group's grow direction and spacing. Bar frames dirty this from their OnShow/OnHide,
-- the group setting writers, rebuilds and wakes dirty it directly, and the tick
-- reflows only while it is set instead of re-walking every bar every 16 ms.
local function _MarkTBBReflowDirty() SetReflowDirty(true) end

-- TBB idle sleeper: UpdateTrackedBuffBarTimers counts consecutive dead ticks (no
-- active/fallback aura, self-timed window, running cooldown, or placeholder preview);
-- after ~0.5s it parks the tick frame (OnUpdate stops) and this frame listens for the
-- cheap edges that revive it. Lust from other players and the Time Spiral glow arm
-- outside these events, so their arm sites call Wake directly instead, and a Tracked
-- Bars viewer item going active wakes it through ns.WakeTBBTickIfParked (the item's
-- OnActiveStateChanged hook in EUI_CDM_HookViewers.lua).
local _tbbWake = CreateFrame("Frame")
_tbbWake._idleTicks = 0
-- Aura edge counts for the tick's fallback reads (a bar the viewer has not bound
-- reads the player's aura, else the target's): player aura events, and target
-- aura events plus target changes. A bar re-queries a half only after its count moved.
_tbbWake._fbPGen, _tbbWake._fbTGen = 0, 0
function _tbbWake.Sleep()
    if tbbTickFrame then tbbTickFrame:Hide() end
    -- NEVER register SPELL_UPDATE_COOLDOWN here: it fires steadily at idle and would defeat
    -- the sleep. A tracked cooldown can only START via a player cast (item/shapeshift
    -- included), covered by the cast event; a RUNNING cooldown keeps the tick awake by liveness.
    _tbbWake:RegisterUnitEvent("UNIT_AURA", "player")
    _tbbWake:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    _tbbWake:RegisterEvent("PLAYER_REGEN_DISABLED")
    -- A debuff the player left on a new target is live the moment it is selected, and
    -- none of the player-scoped edges above can see that. Probe before waking.
    _tbbWake:RegisterEvent("PLAYER_TARGET_CHANGED")
end
function _tbbWake.Wake()
    -- Tracking Bars off: no tick to revive, so nothing registers. BuildTrackedBuffBars
    -- sets _enabled before its own Wake.
    if not _tbbWake._enabled then return end
    _tbbWake:UnregisterAllEvents()
    -- Stay subscribed to the aura edge while AWAKE: pool composition changes only on a
    -- player aura event or a pool Acquire (hooked separately), retiring the assignment memo.
    -- The target's aura events only retire the fallback reads (OnEvent); Sleep's
    -- player-only registration drops them again.
    _tbbWake:RegisterUnitEvent("UNIT_AURA", "player", "target")
    _tbbWake._fbPGen, _tbbWake._fbTGen = _tbbWake._fbPGen + 1, _tbbWake._fbTGen + 1
    -- Target changes rebind which auras the viewer's frames carry, so the awake branch
    -- of OnEvent retires the assignment memo on this the same as any other non-aura edge.
    _tbbWake:RegisterEvent("PLAYER_TARGET_CHANGED")
    _tbbWake._idleTicks = 0
    SetAssignDirty(true)
    SetReflowDirty(true)
    if tbbTickFrame then tbbTickFrame:Show() end
end
-- UNIT_AURA fires steadily in group content and every false wake buys ~0.5s of full
-- ticking, so this probe answers "could any bar be live?" WITHOUT waking: an active
-- viewer frame, or a live player aura for a fallback-class config. Casts and combat
-- entry skip the probe (rare at idle; the legitimate start edges the probe can't see).
-- Cache names by configuration, retiring entries when their configuration is dropped.
_tbbWake._targetNames = setmetatable({}, { __mode = "k" })
function _tbbWake.GetTargetAura(cfg)
    if not UnitExists("target") then return nil end
    local names = _tbbWake._targetNames[cfg]
    if not names then
        names = {}
        _tbbWake._targetNames[cfg] = names
    end
    if names.spellID ~= cfg.spellID then
        names.spellID, names.name = cfg.spellID, nil
    end
    if names.baseSpellID ~= cfg.baseSpellID then
        names.baseSpellID, names.baseName = cfg.baseSpellID, nil
    end
    if not names.name then names.name = C_Spell.GetSpellName(cfg.spellID) end
    if not names.baseName and cfg.baseSpellID and cfg.baseSpellID > 0 then
        names.baseName = C_Spell.GetSpellName(cfg.baseSpellID)
    end
    -- Ownership is filtered by the engine; never inspect a secret sourceUnit.
    local filter = UnitIsFriend("player", "target") and "HELPFUL|PLAYER" or "HARMFUL|PLAYER"
    local aura = names.name and C_UnitAuras.GetAuraDataBySpellName("target", names.name, filter)
    if not aura and names.baseName and names.baseName ~= names.name then
        aura = C_UnitAuras.GetAuraDataBySpellName("target", names.baseName, filter)
    end
    return aura
end
function _tbbWake.Probe()
    if ns._tbbPlaceholderMode then return true end
    local viewer = _G["BuffBarCooldownViewer"]
    if viewer and viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            if frame.IsActive and frame:IsActive() then return true end
        end
    end
    if not (ECME and ECME.db) then return true end
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    if bars and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, cfg in ipairs(bars) do
            if cfg.enabled ~= false and not cfg.spellIDs and not cfg.popularKey
               and cfg.trackType ~= "cooldown"
               and cfg.spellID and cfg.spellID > 0 then
                if C_UnitAuras.GetPlayerAuraBySpellID(cfg.spellID)
                   or (cfg.baseSpellID and cfg.baseSpellID > 0
                       and C_UnitAuras.GetPlayerAuraBySpellID(cfg.baseSpellID))
                   or _tbbWake.GetTargetAura(cfg) then
                    return true
                end
            end
        end
    end
    return false
end
function _tbbWake.OnEvent(_, event, unit, updateInfo)
    -- Awake: this is the composition edge that retires the assignment memo. Mark and
    -- let the next tick re-pair; no probe, no state change. Pairing keys on frame
    -- identity only (pool membership, cooldown slot, aura spell variant), and an
    -- update-only payload (refresh / stack change on auras already bound) moves none
    -- of those, so only additions, removals, full updates, or an unreadable payload
    -- retire the memo -- the same secret guard as the buff ticker's UNIT_AURA writer:
    -- the table and each field can arrive secret in instanced content, and a secret
    -- can never be boolean-tested, so unreadable means assume churn.
    if tbbTickFrame and tbbTickFrame:IsShown() then
        if event == "UNIT_AURA" then
            if unit == "target" then
                -- No viewer frame moves on a target aura event (no target aura
                -- subscription retired the memo before): the fallback reads only.
                _tbbWake._fbTGen = _tbbWake._fbTGen + 1
                return
            end
            _tbbWake._fbPGen = _tbbWake._fbPGen + 1
        else
            _tbbWake._fbTGen = _tbbWake._fbTGen + 1
        end
        if event ~= "UNIT_AURA" or not updateInfo or issecretvalue(updateInfo) then
            SetAssignDirty(true)
        else
            local full    = updateInfo.isFullUpdate
            local removed = updateInfo.removedAuraInstanceIDs
            local added   = updateInfo.addedAuras
            if issecretvalue(full) or issecretvalue(removed) or issecretvalue(added)
               or full or removed or added then
                SetAssignDirty(true)
            end
        end
        return
    end
    if (event == "UNIT_AURA" or event == "PLAYER_TARGET_CHANGED")
       and not _tbbWake.Probe() then return end
    _tbbWake.Wake()
end
_tbbWake:SetScript("OnEvent", _tbbWake.OnEvent)
ns.WakeTBBTick = _tbbWake.Wake

function ns.WakeTBBTickIfParked(item)
    if _tbbWake._enabled and tbbTickFrame and not tbbTickFrame:IsShown()
       and (not item or item:IsActive()) then
        _tbbWake.Wake()
    end
end

-- The Visibility edges (mount, shapeshift, gliding, target, group, zone, combat) are exactly
-- the set the shared dispatcher already owns, so subscribe there instead of re-registering
-- them on the sleeper. Without this a parked tick never learns that a Visibility condition
-- flipped: a bar hidden while mounted stays hidden past the dismount until some unrelated
-- aura or cast happens to wake it, and the dragonriding modes never fire at all because
-- takeoff/landing is not in the sleeper's wake set.
if EllesmereUI.RegisterVisibilityUpdater then
    EllesmereUI.RegisterVisibilityUpdater(function()
        -- Only a parked tick needs the nudge; an awake one re-evaluates every frame anyway.
        if _anyVisCond then ns.WakeTBBTickIfParked() end
    end)
end

function ns.GetTBBFrame(idx) return tbbFrames[idx] end

-------------------------------------------------------------------------------
--  Bar grouping helpers (multi-group)
--  Membership: per-bar numeric cfg.groupId (0 = independent). Legacy bars carry only
--  the boolean cfg.grouped, read as a VIEW (true/default = group 1, false =
--  independent); writes set groupId and mirror the boolean for older-version export
--  compat. Groups chain in index order: the first ENABLED member is the anchor (owns
--  position/mover), later members chain to it sharing its width/height.
-------------------------------------------------------------------------------
function ns.TBBBarGroupID(cfg)
    if not cfg then return 0 end
    if cfg.groupId ~= nil then return cfg.groupId end
    return (cfg.grouped ~= false) and 1 or 0
end

function ns.TBBSetBarGroup(cfg, gid)
    if not cfg then return end
    gid = gid or 0
    cfg.groupId = gid
    -- Legacy mirror: older versions only know one group ("checked" bars).
    cfg.grouped = (gid ~= 0)
end

-- Sorted list of group ids currently used by at least one bar.
function ns.TBBGroupIDsInUse()
    local t = ns.GetTrackedBuffBars()
    local seen, list = {}, {}
    for _, c in ipairs(t.bars or {}) do
        local gid = ns.TBBBarGroupID(c)
        if gid ~= 0 and not seen[gid] then
            seen[gid] = true
            list[#list + 1] = gid
        end
    end
    table.sort(list)
    return list
end

-- Smallest positive group id not currently in use (fills holes left by dissolved groups so group names stay compact).
function ns.TBBNextGroupID()
    local t = ns.GetTrackedBuffBars()
    local used = {}
    for _, c in ipairs(t.bars or {}) do
        used[ns.TBBBarGroupID(c)] = true
    end
    local gid = 1
    while used[gid] do gid = gid + 1 end
    return gid
end

-- Per-group settings live in tbb.groups[tostring(gid)]. Group 1 VIEWS the legacy keys
-- (tbb.groupGrowDirection/groupSpacing) for zero-migration old-config compat; group-1
-- writes keep those keys synced for old-version imports. gid->string memo below avoids a
-- tostring allocation in the per-tick reflow.
local _gidKeys = setmetatable({}, { __index = function(t, gid)
    local s = tostring(gid); rawset(t, gid, s); return s
end })

local function TBBGroupStore(tbb, gid, create)
    if not tbb.groups then
        if not create then return nil end
        tbb.groups = {}
    end
    local k = _gidKeys[gid]
    local g = tbb.groups[k]
    if not g and create then g = {}; tbb.groups[k] = g end
    return g
end

-- Internal reads take the tbb table directly so the per-tick reflow does not re-resolve the active spec profile per group.
local function GroupGrowOf(tbb, gid)
    local g = TBBGroupStore(tbb, gid, false)
    if g and g.globalKey then
        -- Global group: shared value from the profile registry. A stale key (entry deleted) falls through to the local values.
        local e = ns.TBBGlobalGroup and ns.TBBGlobalGroup(g.globalKey)
        if e then return e.grow or "DOWN" end
    end
    if g and g.grow then return g.grow end
    if gid == 1 and tbb.groupGrowDirection then return tbb.groupGrowDirection end
    return "DOWN"
end

local function GroupSpacingOf(tbb, gid)
    local g = TBBGroupStore(tbb, gid, false)
    if g and g.globalKey then
        local e = ns.TBBGlobalGroup and ns.TBBGlobalGroup(g.globalKey)
        if e and e.spacing ~= nil then return e.spacing end
    end
    if g and g.spacing ~= nil then return g.spacing end
    if gid == 1 and tbb.groupSpacing ~= nil then return tbb.groupSpacing end
    return 2
end

function ns.TBBGroupGrow(gid)
    return GroupGrowOf(ns.GetTrackedBuffBars(), gid)
end

function ns.TBBSetGroupGrow(gid, v)
    local t = ns.GetTrackedBuffBars()
    local gkey = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
    if gkey then
        local e = ns.TBBGlobalGroup(gkey)
        if e then e.grow = v; SetReflowDirty(true) end
        return
    end
    TBBGroupStore(t, gid, true).grow = v
    if gid == 1 then t.groupGrowDirection = v end
    SetReflowDirty(true)
end

function ns.TBBGroupSpacing(gid)
    return GroupSpacingOf(ns.GetTrackedBuffBars(), gid)
end

function ns.TBBSetGroupSpacing(gid, v)
    local t = ns.GetTrackedBuffBars()
    local gkey = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
    if gkey then
        local e = ns.TBBGlobalGroup(gkey)
        if e then e.spacing = v; SetReflowDirty(true) end
        return
    end
    TBBGroupStore(t, gid, true).spacing = v
    if gid == 1 then t.groupSpacing = v end
    SetReflowDirty(true)
end

-- Clear a group's stored settings when its id is (re)claimed for a brand-new group, so a dissolved group's leftovers do not leak into it.
function ns.TBBResetGroupSettings(gid)
    local t = ns.GetTrackedBuffBars()
    if t.groups then t.groups[_gidKeys[gid]] = nil end
    SetReflowDirty(true)
end

-- Optional user-given group name (Group Settings input). Empty/absent = nil, callers fall back to the default "Group N" label.
function ns.TBBGroupName(gid)
    local t = ns.GetTrackedBuffBars()
    local g = TBBGroupStore(t, gid, false)
    if g and g.globalKey then
        local e = ns.TBBGlobalGroup and ns.TBBGlobalGroup(g.globalKey)
        if e and type(e.name) == "string" and e.name ~= "" then return e.name end
    end
    local n = g and g.name
    if type(n) == "string" and n ~= "" then return n end
    return nil
end

function ns.TBBSetGroupName(gid, name)
    local t = ns.GetTrackedBuffBars()
    local gkey = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
    if gkey then
        -- Shared name lives in the registry and is never blanked: movers and dropdown rows on other specs need a concrete label.
        local e = ns.TBBGlobalGroup(gkey)
        if e then
            if type(name) == "string" and name ~= "" then
                e.name = name
            end
        end
        return
    end
    if type(name) ~= "string" or name == "" then
        local g = TBBGroupStore(t, gid, false)
        if g then g.name = nil end
    else
        TBBGroupStore(t, gid, true).name = name
    end
end

-------------------------------------------------------------------------------
--  Global groups: a PROFILE-scoped registry shared by every spec. A per-spec group
--  opts in by stamping groups[gid].globalKey; its name/grow/spacing/position then
--  resolve through the registry entry (including the unlock mover, keyed stably as
--  "TBBG_<gkey>"), so every spec linked to the key shares one identity. Membership
--  stays per-spec: a spec with no bars on the key has no frames and a hidden mover.
--  Keys are monotonic and NEVER reused (reuse would resurrect stale unlock anchor
--  links). Zero migration: a group without a globalKey stamp is purely local.
-------------------------------------------------------------------------------
do
    local function TBBGlobalDB(create)
        if not (ECME and ECME.db) then SetECME(ns.ECME) end
        local p = ECME and ECME.db and ECME.db.profile
        if not p then return nil end
        if not p.tbbGlobalGroups and create then p.tbbGlobalGroups = {} end
        return p.tbbGlobalGroups, p
    end

    function ns.GetTBBGlobalGroups()
        return TBBGlobalDB(false)
    end

    function ns.TBBGlobalGroup(gkey)
        local reg = TBBGlobalDB(false)
        return reg and gkey and reg[gkey] or nil
    end

    -- The globalKey a per-spec group is linked to (nil = local group). A stale stamp whose registry entry was deleted reads as local.
    function ns.TBBGroupGlobalKey(gid)
        local g = TBBGroupStore(ns.GetTrackedBuffBars(), gid, false)
        local gkey = g and g.globalKey
        if gkey and ns.TBBGlobalGroup(gkey) then return gkey end
        return nil
    end

    -- Local gid linked to a global group on the ACTIVE spec (nil if none).
    function ns.TBBLocalGidForGlobal(gkey)
        local t = ns.GetTrackedBuffBars()
        if not t.groups then return nil end
        for k, g in pairs(t.groups) do
            if g.globalKey == gkey then return tonumber(k) end
        end
        return nil
    end

    -- Find-or-create the active spec's local group for a global group. The id must dodge
    -- BOTH gids used by bars and gids held by memberless global links (TBBNextGroupID only
    -- scans bars; reusing a linked gid here would wipe another global group's link).
    function ns.TBBEnsureLocalGroupForGlobal(gkey)
        if not ns.TBBGlobalGroup(gkey) then return nil end
        local gid = ns.TBBLocalGidForGlobal(gkey)
        if gid then return gid end
        local t = ns.GetTrackedBuffBars()
        local used = {}
        for _, c in ipairs(t.bars or {}) do
            used[ns.TBBBarGroupID(c)] = true
        end
        if t.groups then
            for k, g in pairs(t.groups) do
                if g.globalKey then
                    local kn = tonumber(k)
                    if kn then used[kn] = true end
                end
            end
        end
        gid = 1
        while used[gid] do gid = gid + 1 end
        ns.TBBResetGroupSettings(gid)
        TBBGroupStore(t, gid, true).globalKey = gkey
        return gid
    end

    -- Sorted registry keys (stable ordering for dropdown rows / movers).
    function ns.TBBGlobalGroupKeys()
        local reg = TBBGlobalDB(false)
        local list = {}
        if reg then
            for k in pairs(reg) do list[#list + 1] = k end
            table.sort(list, function(a, b)
                return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0)
            end)
        end
        return list
    end

    -- "Shift Elements If No Bars" (entry.shiftNoBar = "Up"/"Down", nil = None;
    -- entry.shiftNoBarExtraY tunes the magnitude). Stand-in frame for a global
    -- group on memberless specs, created ONLY while the option is set (None =
    -- byte-identical legacy behavior: nil getFrame, anchors dormant/fallback):
    -- a bare script-free frame holding the group's slot -- registry position,
    -- last-stamped anchor-bar size -- so anchored elements keep resolvable
    -- bounds and the shift has a magnitude when no member bar frame exists.
    -- Renders nothing and costs nothing (no events, no OnUpdate). Re-positioned
    -- every build; the IsUnlockAnchored guard leaves it alone when the anchor
    -- system owns the TBBG_ key (same guard as the bar placement below).
    local tbbStandins = {}
    function ns.TBBEnsureStandin(gk)
        local entry = ns.TBBGlobalGroup(gk)
        if not entry then return nil end
        local f = tbbStandins[gk]
        if not f then
            f = CreateFrame("Frame", nil, UIParent)
            tbbStandins[gk] = f
        end
        local PPl = EllesmereUI and EllesmereUI.PP
        local sn = PPl and PPl.Snap or function(v) return v end
        f:SetSize(sn(entry.width or 270), sn(entry.height or 24))
        -- SetPoint ONLY on an actual position change (signature-stamped): this
        -- runs from getFrame, and the unlock machinery hooksecurefuncs SetPoint
        -- on resolved frames -- an unconditional re-point per resolve fed the
        -- move-check timer a fresh SetPoint every frame, forever (audit-caught).
        -- getFrame must never mutate what it merely resolves.
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("TBBG_" .. gk)
        if anchored and f:GetLeft() then return f end
        local pos = entry.pos
        local sig
        if pos and pos.point then
            sig = pos.point .. "|" .. (pos.relPoint or pos.point) .. "|"
                .. (pos.x or 0) .. "|" .. (pos.y or 0)
        else
            sig = "default"
        end
        if f._posSig ~= sig then
            f._posSig = sig
            f:ClearAllPoints()
            if pos and pos.point then
                f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            else
                f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
            end
        end
        return f
    end
    -- Read-only lookup (no create): lets getFrame keep resolving a stand-in
    -- built earlier this session after the option flips to None, so the flip's
    -- cascade can land anchored children back at the true slot instead of
    -- stranding them shifted. A fresh session with the option off never creates
    -- one, preserving the legacy nil-frame behavior.
    function ns.TBBStandinFrame(gk)
        return tbbStandins[gk]
    end

    -- Whether ANY spec profile links this global key. A fully-orphaned entry
    -- (every spec detached; the registry keeps it for re-attachment) must stop
    -- shifting -- with no linked spec, no group settings page can reach the
    -- option to clear it (audit-caught). Bounded scan: specs x groups, only
    -- reached when the option is set and the ACTIVE spec is memberless.
    local function TBBGlobalLinkedAnywhere(gkey)
        local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
        if not sp then return false end
        for _, prof in pairs(sp) do
            local tbb = prof.trackedBuffBars
            local groups = tbb and tbb.groups
            if groups then
                for _, g in pairs(groups) do
                    if g.globalKey == gkey then return true end
                end
            end
        end
        return false
    end

    -- Direction the shift WOULD apply for one registry entry (ignores unlock
    -- state): 0 while the active spec has an enabled member bar (the real
    -- anchor frame covers the slot), the option is off, or no spec links the
    -- entry at all; else +1/-1.
    local function TBBShiftDirFor(entry, gk)
        local mode = entry and entry.shiftNoBar
        if mode ~= "Up" and mode ~= "Down" then return 0 end
        local gid = ns.TBBLocalGidForGlobal(gk)
        if gid and ns.TBBGroupAnchorIndex(gid) then return 0 end
        if not TBBGlobalLinkedAnywhere(gk) then return 0 end
        return (mode == "Up") and 1 or -1
    end
    ns.TBBShiftDirFor = TBBShiftDirFor

    -- Seeded into the shared shift-provider list (EUI_UnlockMode.lua dispatches
    -- EllesmereUI._GetAnchorTargetShiftDir over it; ResourceBars seeds the
    -- ERB_* keys the same way). Direct or-preserve push, NEVER an API call:
    -- registration must carry zero load-order coupling. Elements anchored to a
    -- shifting TBBG_ key move into the empty slot by the stand-in's height +
    -- Extra Y -- visual-only, never written to saved positions; 0 while unlock
    -- mode is active so movers capture true positions.
    EllesmereUI._anchorShiftProviders = EllesmereUI._anchorShiftProviders or {}
    table.insert(EllesmereUI._anchorShiftProviders, {
        dir = function(targetKey)
            if EllesmereUI._unlockActive then return 0 end
            if type(targetKey) ~= "string" or targetKey:sub(1, 5) ~= "TBBG_" then return 0 end
            local gk = targetKey:sub(6)
            local entry = ns.TBBGlobalGroup(gk)
            local dir = TBBShiftDirFor(entry, gk)
            if dir == 0 then return 0 end
            return dir, entry.shiftNoBarExtraY or 0
        end,
        wants = function()
            local reg = TBBGlobalDB(false)
            if not reg then return false end
            for gk, entry in pairs(reg) do
                if TBBShiftDirFor(entry, gk) ~= 0 then return true end
            end
            return false
        end,
        restore = function()
            if not EllesmereUI.PropagateAnchorChain then return end
            local reg = TBBGlobalDB(false)
            if not reg then return end
            for gk, entry in pairs(reg) do
                if TBBShiftDirFor(entry, gk) ~= 0 then
                    EllesmereUI.PropagateAnchorChain("TBBG_" .. gk)
                end
            end
        end,
    })

    -- Opt in: seed the registry from the group's current per-spec settings and anchor
    -- position. Detach: materialize shared values back into the per-spec store so nothing
    -- moves; the registry entry persists for other specs (full removal is TBBDeleteGlobalGroup).
    function ns.TBBSetGroupGlobal(gid, on)
        local t = ns.GetTrackedBuffBars()
        local g = TBBGroupStore(t, gid, true)
        if on then
            if g.globalKey and ns.TBBGlobalGroup(g.globalKey) then return end
            local reg, p = TBBGlobalDB(true)
            if not reg then return end
            local id = (p.tbbGlobalGroupNextId or 0) + 1
            p.tbbGlobalGroupNextId = id
            local gkey = "g" .. id
            local L = EllesmereUI and EllesmereUI.L
            local entry = {
                name    = ns.TBBGroupName(gid) or ((L and L("Group") or "Group") .. " " .. gid),
                grow    = GroupGrowOf(t, gid),
                spacing = GroupSpacingOf(t, gid),
            }
            local ai = ns.TBBGroupAnchorIndex(gid)
            local pos = ai and ns.GetTBBPositions()[tostring(ai)]
            if pos and pos.point then
                entry.pos = { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
            end
            reg[gkey] = entry
            g.globalKey = gkey
        else
            local gkey = g.globalKey
            g.globalKey = nil
            local entry = gkey and ns.TBBGlobalGroup(gkey)
            if entry then
                g.name = entry.name
                g.grow = entry.grow
                g.spacing = entry.spacing
                if gid == 1 then
                    t.groupGrowDirection = entry.grow
                    t.groupSpacing = entry.spacing
                end
                SetReflowDirty(true)
                if entry.pos then
                    local posDB = ns.GetTBBPositions()
                    for j, c in ipairs(t.bars or {}) do
                        if ns.TBBBarGroupID(c) == gid then
                            posDB[tostring(j)] = { point = entry.pos.point, relPoint = entry.pos.relPoint, x = entry.pos.x, y = entry.pos.y }
                        end
                    end
                end
            end
        end
    end

    -- Growth-edge extent: when an element anchors to the side of a tracking bar group
    -- that MATCHES the group's growth direction (TOP of an upward-growing group, LEFT
    -- of a leftward one), the anchor edge follows the outermost VISIBLE member instead
    -- of the static anchor bar, so it rides the stack as bars appear/fade. Every other
    -- side/target combo is untouched: the provider returns nil and the anchor system
    -- uses the frame's own bounds.
    local GROW_TO_SIDE = { UP = "TOP", DOWN = "BOTTOM", LEFT = "LEFT", RIGHT = "RIGHT" }

    -- Resolve an anchor target key to a group id IF the anchored side matches that group's growth direction (nil otherwise).
    function ns.TBBExtentGidForTarget(targetKey, side)
        if type(targetKey) ~= "string" or not side then return nil end
        local gid
        local gkey = targetKey:match("^TBBG_(.+)$")
        if gkey then
            gid = ns.TBBLocalGidForGlobal(gkey)
        else
            local idx = tonumber(targetKey:match("^TBB_(%d+)$"))
            if not idx then return nil end
            local t = ns.GetTrackedBuffBars()
            local c = t.bars and t.bars[idx]
            gid = c and ns.TBBBarGroupID(c) or 0
            if gid == 0 or idx ~= ns.TBBGroupAnchorIndex(gid) then return nil end
        end
        if not gid then return nil end
        local grow = (ns.TBBGroupGrow(gid) or "DOWN"):upper()
        if side ~= "POINT" and GROW_TO_SIDE[grow] ~= side then return nil end
        return gid
    end

    -- Anchor-system hook: outermost visible member edge in UIParent space, or nil to use
    -- the target frame's own bounds. Inert while unlock mode or the placeholder preview owns positions.
    function EllesmereUI._GetAnchorTargetExtent(targetKey, side)
        if EllesmereUI._unlockActive or ns._tbbPlaceholderMode then return nil end
        local gid = ns.TBBExtentGidForTarget(targetKey, side)
        if not gid then return nil end
        local t = ns.GetTrackedBuffBars()
        local uiS = UIParent:GetEffectiveScale()
        local best
        for i, c in ipairs(t.bars or {}) do
            if c.enabled ~= false and ns.TBBBarGroupID(c) == gid then
                local f = tbbFrames[i]
                if f and f:IsShown() and f:GetLeft() then
                    local fS = f:GetEffectiveScale() / uiS
                    local v
                    if side == "TOP" then
                        v = (f:GetTop() or 0) * fS
                    elseif side == "BOTTOM" then
                        v = (f:GetBottom() or 0) * fS
                    elseif side == "LEFT" then
                        v = (f:GetLeft() or 0) * fS
                    else
                        v = (f:GetRight() or 0) * fS
                    end
                    if not best then
                        best = v
                    elseif side == "TOP" or side == "RIGHT" then
                        if v > best then best = v end
                    elseif v < best then
                        best = v
                    end
                end
            end
        end
        return best
    end

    -- gid -> anchored unlock key needing extent updates. Memo invalidation: the unlock
    -- module bumps _anchorLinksStamp on link changes; RegisterTBBUnlockElements nils the
    -- memo on every build (grow/membership/spec changes).
    local function RebuildExtentWatch()
        local w = {}
        local anchors = EllesmereUIDB and EllesmereUIDB.unlockAnchors
        if anchors then
            for _, info in pairs(anchors) do
                if info.target then
                    local gid = ns.TBBExtentGidForTarget(info.target, info.mode == "POINT" and "POINT" or info.side)
                    if gid then w[gid] = info.target end
                end
                local fb = info.fallback
                if fb and fb.target then
                    local gid = ns.TBBExtentGidForTarget(fb.target, fb.side)
                    if gid then w[gid] = fb.target end
                end
            end
        end
        return w
    end

    local function TBBExtentWatchKey(gid)
        if not gid or gid == 0 then return nil end
        local stamp = EllesmereUI._anchorLinksStamp or 0
        local w = ns._tbbExtentWatch
        if not w or ns._tbbExtentWatchStamp ~= stamp then
            w = RebuildExtentWatch()
            ns._tbbExtentWatch = w
            ns._tbbExtentWatchStamp = stamp
        end
        return w[gid]
    end

    -- Called by the reflow only when a group's visible footprint actually changed
    -- (change-gated there, NOT per-tick). Queues batched anchor propagation for the unlock key.
    function ns._NotifyTBBExtentChanged(gid)
        local key = TBBExtentWatchKey(gid)
        if not key then return end
        if EllesmereUI.PropagateAnchorChain then
            EllesmereUI.PropagateAnchorChain(key, "all")
        end
    end

    -- Remove a global group everywhere: every spec's linked group detaches with the shared
    -- values materialized locally (bars keep their positions), then the registry entry is deleted.
    function ns.TBBDeleteGlobalGroup(gkey)
        local reg = TBBGlobalDB(false)
        local entry = reg and reg[gkey]
        if not entry then return end
        local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
        if sp then
            for _, prof in pairs(sp) do
                local tbb = prof.trackedBuffBars
                if tbb and tbb.groups then
                    for k, g in pairs(tbb.groups) do
                        if g.globalKey == gkey then
                            g.globalKey = nil
                            g.name = entry.name
                            g.grow = entry.grow
                            g.spacing = entry.spacing
                            if k == "1" then
                                tbb.groupGrowDirection = entry.grow
                                tbb.groupSpacing = entry.spacing
                            end
                            SetReflowDirty(true)
                            if entry.pos then
                                if not prof.tbbPositions then prof.tbbPositions = {} end
                                local kn = tonumber(k)
                                for j, c in ipairs(tbb.bars or {}) do
                                    if ns.TBBBarGroupID(c) == kn then
                                        prof.tbbPositions[tostring(j)] = { point = entry.pos.point, relPoint = entry.pos.relPoint, x = entry.pos.x, y = entry.pos.y }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        reg[gkey] = nil
        -- Retire the group's shift stand-in with it: a leftover frame would keep
        -- resolving through getFrame's session fallback and glue anchored
        -- elements to the deleted group's last position (audit-caught).
        local sf = tbbStandins[gkey]
        if sf then
            sf:Hide()
            tbbStandins[gkey] = nil
        end
    end
end

-- "Auto-Add New to This Group": the flagged group receives a bar for every spell newly
-- appearing in Blizzard's Tracked Bars section. At most ONE group holds the flag; enabling it clears the others.
function ns.TBBGroupAutoAdd(gid)
    local t = ns.GetTrackedBuffBars()
    local g = TBBGroupStore(t, gid, false)
    return g ~= nil and g.autoAdd == true
end

function ns.TBBSetGroupAutoAdd(gid, v)
    local t = ns.GetTrackedBuffBars()
    if v then
        if t.groups then
            for _, g in pairs(t.groups) do g.autoAdd = nil end
        end
        TBBGroupStore(t, gid, true).autoAdd = true
    else
        local g = TBBGroupStore(t, gid, false)
        if g then g.autoAdd = nil end
    end
end

-- The group flagged for auto-add (or nil). Smallest id wins if a stale table somehow carries more than one flag.
function ns.TBBAutoAddGroupID()
    local t = ns.GetTrackedBuffBars()
    if not t.groups then return nil end
    local best
    for k, g in pairs(t.groups) do
        if g.autoAdd == true then
            local gid = tonumber(k)
            if gid and (not best or gid < best) then best = gid end
        end
    end
    return best
end

-- Index of a group's anchor = its first enabled member (or nil if none). gid nil = group 1 (legacy callers).
function ns.TBBGroupAnchorIndex(gid)
    gid = gid or 1
    local t = ns.GetTrackedBuffBars()
    for i, c in ipairs(t.bars or {}) do
        if c.enabled ~= false and ns.TBBBarGroupID(c) == gid then return i end
    end
    return nil
end

-- Member count: with gid, counts that group's bars (regardless of enabled); without, counts bars in ANY group (drives options disabled gates).
function ns.TBBGroupedCount(gid)
    local t = ns.GetTrackedBuffBars()
    local n = 0
    for _, c in ipairs(t.bars or {}) do
        local g = ns.TBBBarGroupID(c)
        if (gid and g == gid) or (not gid and g ~= 0) then n = n + 1 end
    end
    return n
end

-- Groups are orientation-uniform (shared width/height only make sense if every member
-- reads dimensions the same way). The group's FIRST member defines the orientation; a
-- disagreeing member (preset on one bar, cross-spec copy, import) is coerced, swapping
-- its stored dims so on-screen proportions carry over. Runs every rebuild; the options
-- Vertical Orientation toggle flips the whole group explicitly so deliberate flips
-- never fight it.
function ns.EnforceTBBGroupOrientation(tbb)
    tbb = tbb or ns.GetTrackedBuffBars()
    local firstOrient = {}
    for _, cfg in ipairs(tbb.bars or {}) do
        local gid = ns.TBBBarGroupID(cfg)
        if gid ~= 0 then
            local want = firstOrient[gid]
            local mine = cfg.verticalOrientation and true or false
            if want == nil then
                firstOrient[gid] = mine
            elseif mine ~= want then
                cfg.width, cfg.height = (cfg.height or 24), (cfg.width or 270)
                cfg.verticalOrientation = want
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Style copy
--  A bar's "style" = every visual key EXCEPT tracked spell identity, enable state,
--  group membership, and stack-threshold/stack-based-fill keys (spell-specific;
--  matches AddTrackedBuffBar's reset set) -- a copied style must never carry
--  threshold numbers.
-------------------------------------------------------------------------------
local TBB_STYLE_KEYS = {
    "height", "width", "verticalOrientation", "reverseFill", "fillUp",
    "chargeHashLines", "chargeHashLineWidth",
    "chargeHashLineR", "chargeHashLineG", "chargeHashLineB", "chargeHashLineA",
    "chargeHashShade", "chargeHashShadeAlpha",
    "texture", "strata",
    "fillColorMode", "fillR", "fillG", "fillB", "fillA",
    "bgR", "bgG", "bgB", "bgA",
    "gradientEnabled", "gradientR", "gradientG", "gradientB", "gradientA", "gradientDir",
    "opacity", "hideWhenInactive", "onlyInCombat",
    -- Visibility rides along because the onlyInCombat toggle it replaced already did: a new
    -- bar inheriting a neighbour's style, or one joining a group, kept that gate before.
    "barVisibility", "visibilityModes", "visibilityMatch",
    -- The option lanes themselves are appended from the shared list below.
    "showTimer", "timerPosition", "timerSize", "timerX", "timerY",
    "timerTextR", "timerTextG", "timerTextB", "timerTextA",
    "timerDecimals", "timerDecimalThreshold",
    "showName", "namePosition", "nameSize", "nameX", "nameY",
    "nameTextR", "nameTextG", "nameTextB", "nameTextA",
    "showSpark",
    "iconDisplay", "iconSize", "iconX", "iconY", "iconBorderSize",
    "stacksPosition", "stacksSize", "stacksX", "stacksY",
    "stacksTextR", "stacksTextG", "stacksTextB", "stacksTextA",
    "borderSize", "borderSizePx", "borderTexture", "borderR", "borderG", "borderB",
    "borderTextureOffset", "borderTextureOffsetY",
    "borderTextureShiftX", "borderTextureShiftY", "borderBehind",
    "stockBorderScale",
    "pandemicGlow", "pandemicGlowStyle", "pandemicGlowColor", "pandemicGlowMode",
    "pandemicGlowLines", "pandemicGlowThickness", "pandemicGlowSpeed",
    "pandemicGlowBackground", "pandemicGlowBackgroundColor",
}
-- Appended rather than spelled out: a lane added to the shared list is copied with the
-- rest of the style instead of silently staying behind on the source bar.
if EllesmereUI.VIS_OPT_KEYS then
    for i = 1, #EllesmereUI.VIS_OPT_KEYS do
        TBB_STYLE_KEYS[#TBB_STYLE_KEYS + 1] = EllesmereUI.VIS_OPT_KEYS[i]
    end
end
ns.TBB_STYLE_KEYS = TBB_STYLE_KEYS

-- Copy src's visual style onto dst, key-exact (including nil) so both bars resolve defaults
-- identically. Table values (glow color) are deep-copied so the two never share a mutable table.
function ns.CopyTBBStyle(src, dst)
    if not src or not dst or src == dst then return end
    for _, k in ipairs(TBB_STYLE_KEYS) do
        local v = src[k]
        if type(v) == "table" then
            local copy = {}
            for tk, tv in pairs(v) do copy[tk] = tv end
            v = copy
        end
        dst[k] = v
    end
end

-- The bar whose style represents a group: its anchor, or (all members disabled) its first member.
function ns.TBBGroupStyleSource(gid)
    if not gid or gid == 0 then return nil end
    local t = ns.GetTrackedBuffBars()
    local ai = ns.TBBGroupAnchorIndex(gid)
    if ai then return t.bars[ai] end
    for _, c in ipairs(t.bars or {}) do
        if ns.TBBBarGroupID(c) == gid then return c end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Style presets (PROFILE-scoped: persist across specs, travel with profile
--  export). Entry = { name, style = {<TBB_STYLE_KEYS values>} }. A bar
--  remembers the preset last applied to it (cfg.stylePresetName) so new bars
--  can resolve a preset by association.
-------------------------------------------------------------------------------
function ns.GetTBBStylePresets()
    if not (ECME and ECME.db) then SetECME(ns.ECME) end
    local p = ECME and ECME.db and ECME.db.profile
    if not p then return nil end
    if not p.tbbStylePresets then p.tbbStylePresets = {} end
    -- Same icon-footprint fold as GetTrackedBuffBars: legacy presets stored the FILL size rather than the icon-inclusive total.
    if not p._tbbPresetIconTotal then
        for _, pr in ipairs(p.tbbStylePresets) do
            local s = pr.style
            if s and (s.iconDisplay or "none") ~= "none" then
                if s.verticalOrientation then
                    s.height = (s.height or 24) + (s.width or 270)
                else
                    s.width = (s.width or 270) + (s.height or 24)
                end
            end
        end
        p._tbbPresetIconTotal = true
    end
    return p.tbbStylePresets
end

function ns.FindTBBStylePreset(name)
    if not name or name == "" then return nil end
    local presets = ns.GetTBBStylePresets()
    if not presets then return nil end
    for _, pr in ipairs(presets) do
        if pr.name == name then return pr end
    end
    return nil
end

-- Save (or overwrite) a preset from a bar's current style, and associate the source bar with it.
function ns.SaveTBBStylePreset(name, srcCfg)
    if not name or name == "" or not srcCfg then return nil end
    local presets = ns.GetTBBStylePresets()
    if not presets then return nil end
    local style = {}
    ns.CopyTBBStyle(srcCfg, style)
    local pr = ns.FindTBBStylePreset(name)
    if pr then
        pr.style = style
    else
        pr = { name = name, style = style }
        presets[#presets + 1] = pr
    end
    srcCfg.stylePresetName = name
    return pr
end

function ns.ApplyTBBStylePresetToCfg(preset, cfg)
    if not preset or not preset.style or not cfg then return end
    ns.CopyTBBStyle(preset.style, cfg)
    cfg.stylePresetName = preset.name
end

-- Delete a saved preset. Bar associations (cfg.stylePresetName) are left in place and go inert: FindTBBStylePreset returns nil for a missing name.
function ns.DeleteTBBStylePreset(name)
    if not name or name == "" then return false end
    local presets = ns.GetTBBStylePresets()
    if not presets then return false end
    for i, pr in ipairs(presets) do
        if pr.name == name then
            table.remove(presets, i)
            local p = ECME and ECME.db and ECME.db.profile
            if p and p.tbbSelectedStylePreset == name then
                p.tbbSelectedStylePreset = nil
            end
            return true
        end
    end
    return false
end

-- Rename a preset, carrying bar associations (across every spec of the active profile) and the UI selection pointer with it.
function ns.RenameTBBStylePreset(oldName, newName)
    if not oldName or oldName == "" or not newName or newName == "" then return false end
    if oldName == newName or ns.FindTBBStylePreset(newName) then return false end
    local pr = ns.FindTBBStylePreset(oldName)
    if not pr then return false end
    pr.name = newName
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if sp then
        for _, prof in pairs(sp) do
            local bars = type(prof) == "table" and prof.trackedBuffBars
                and prof.trackedBuffBars.bars
            if bars then
                for _, c in ipairs(bars) do
                    if c.stylePresetName == oldName then c.stylePresetName = newName end
                end
            end
        end
    end
    local p = ECME and ECME.db and ECME.db.profile
    if p and p.tbbSelectedStylePreset == oldName then
        p.tbbSelectedStylePreset = newName
    end
    return true
end

-- New-bar resolution: the preset associated with a bar already in the target group (nil if none).
function ns.ResolveTBBGroupPreset(tbb, gid)
    if not gid or gid == 0 then return nil end
    for _, c in ipairs(tbb.bars or {}) do
        if ns.TBBBarGroupID(c) == gid then
            local pr = ns.FindTBBStylePreset(c.stylePresetName)
            if pr then return pr end
        end
    end
    return nil
end

-- New-bar fallback: a preset associated with any bar of this spec, else any saved preset (nil when none are saved).
function ns.ResolveTBBFallbackPreset(tbb)
    local presets = ns.GetTBBStylePresets()
    if not presets or #presets == 0 then return nil end
    for _, c in ipairs(tbb.bars or {}) do
        local pr = ns.FindTBBStylePreset(c.stylePresetName)
        if pr then return pr end
    end
    return presets[1]
end


-- Runtime reflow for grouped Tracking Bars: BuildTrackedBuffBars creates the static
-- group chain, but the tick decides which bars are visible, so only visible grouped
-- members are reflowed to leave no holes when a buff is inactive/hidden -- e.g. with
-- configured order Buff 1/2/3 and only 2/3 active, Buff 2 sits at the group anchor.
local _tbbReflowStates = {}   -- gid -> pooled per-group reflow state
local function GetReflowState(gid)
    local st = _tbbReflowStates[gid]
    if not st then
        st = { visible = {}, lastIdx = {}, lastCount = 0, lastGrow = nil, lastSpacing = nil }
        _tbbReflowStates[gid] = st
    end
    return st
end
local function ResetReflowStates()
    for _, st in pairs(_tbbReflowStates) do st.lastCount = -1 end
end
local _tbbReflowDone = {}     -- reused per-tick "group handled" set

local function ReflowGroup(tbb, gid, bars)
    local st = GetReflowState(gid)

    local anchorIdx
    for i, c in ipairs(bars) do
        if c.enabled ~= false and ns.TBBBarGroupID(c) == gid then anchorIdx = i; break end
    end
    if not anchorIdx then return end

    local growDir = (GroupGrowOf(tbb, gid) or "DOWN"):upper()
    local spacing = GroupSpacingOf(tbb, gid) or 2

    -- Collect this group's enabled + visible bars in saved hierarchy order. A bar with
    -- hideWhenInactive=false is visible so it keeps its slot (shows inactive bars). Entry
    -- tables are pooled and reused across ticks: zero allocation in this every-16ms path.
    local visible = st.visible
    local count = 0
    for i, cfg in ipairs(bars) do
        local f = tbbFrames[i]
        if cfg and cfg.enabled ~= false and ns.TBBBarGroupID(cfg) == gid
           and f and f._tbbReady and f:IsShown() then
            count = count + 1
            local e = visible[count]
            if not e then e = {}; visible[count] = e end
            e.idx = i; e.frame = f
        end
    end

    if count == 0 then
        -- Group fully collapsed: anchored elements fall back to the anchor bar's own (hidden but resolvable) bounds. Notify once.
        if st.lastCount ~= 0 and ns._NotifyTBBExtentChanged then
            ns._NotifyTBBExtentChanged(gid)
        end
        st.lastCount = 0
        return
    end

    -- Re-anchor only when the visible member sequence or the grow/spacing tuple changes. Compared element-wise so no string is allocated per tick.
    local lastIdx = st.lastIdx
    local changed = count ~= st.lastCount
        or growDir ~= st.lastGrow or spacing ~= st.lastSpacing
    if not changed then
        for n = 1, count do
            if visible[n].idx ~= lastIdx[n] then changed = true; break end
        end
    end
    if not changed then return end
    st.lastCount   = count
    st.lastGrow    = growDir
    st.lastSpacing = spacing
    for n = 1, count do lastIdx[n] = visible[n].idx end

    local first = visible[1].frame
    local anchorFrame = tbbFrames[anchorIdx]

    if anchorFrame and anchorFrame ~= first then
        -- Configured anchor buff is inactive/hidden: pin the first VISIBLE member onto the
        -- anchor frame's slot so it takes the group origin. The anchor frame keeps whatever
        -- position BuildTrackedBuffBars/the unlock system gave it (element anchoring included).
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    end
    -- else the first visible bar IS the anchor: NEVER touch its point. BuildTrackedBuffBars
    -- and the unlock system already position it and honor IsUnlockAnchored, so re-deriving
    -- from tbbPositions would clobber an element-anchored group (stale coord/screen center).

    local prev = first
    for n = 2, count do
        local f = visible[n].frame
        f:ClearAllPoints()
        if growDir == "DOWN" then
            f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        elseif growDir == "UP" then
            f:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
        elseif growDir == "RIGHT" then
            f:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        elseif growDir == "LEFT" then
            f:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
        else
            f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        end
        prev = f
    end

    -- Only reached when the visible sequence/grow/spacing actually changed: let elements anchored to the group's growth side re-read the moving edge.
    if ns._NotifyTBBExtentChanged then
        ns._NotifyTBBExtentChanged(gid)
    end
end

local function ReflowVisibleGroupedTBBars(tbb, bars)
    if not (tbb and bars and tbbFrames) then return end
    -- Never fight edit-preview (placeholder) or unlock-mode dragging: there BuildTrackedBuffBars and the unlock system own bar positions.
    if ns._tbbPlaceholderMode or EllesmereUI._unlockActive then return end
    -- Reflow each present group once; the done-set is reused across ticks so this pass allocates nothing.
    SetReflowDirty(false)
    wipe(_tbbReflowDone)
    for _, cfg in ipairs(bars) do
        local gid = ns.TBBBarGroupID(cfg)
        if gid ~= 0 and not _tbbReflowDone[gid] then
            _tbbReflowDone[gid] = true
            ReflowGroup(tbb, gid, bars)
        end
    end
end

-- Fan a width/height change from a grouped bar to every sibling in the SAME group:
-- write each sibling's LOGICAL cfg.width/cfg.height (NOT icon-inclusive total) and
-- resize its frame with its OWN icon math. Used by options sliders, unlock
-- drag-resize and size-MATCH; re-entrancy guarded so a sibling write cannot recurse.
local _tbbGroupSizing = false
function ns.PropagateTBBGroupSize(srcIdx, dim, value)
    if _tbbGroupSizing then return end
    local t = ns.GetTrackedBuffBars()
    local bars = t.bars
    if not bars then return end
    local src = bars[srcIdx]
    local srcGid = src and ns.TBBBarGroupID(src) or 0
    if srcGid == 0 then return end
    _tbbGroupSizing = true
    for i, c in ipairs(bars) do
        if i ~= srcIdx and ns.TBBBarGroupID(c) == srcGid then
            c[dim] = value
            local f = tbbFrames[i]
            if f then
                -- width/height are the total footprint (icon included), so the frame takes the value directly.
                if dim == "width" then f:SetWidth(value) else f:SetHeight(value) end
            end
        end
    end
    _tbbGroupSizing = false
end

function ns.IsTBBRebuildPending() return _tbbRebuildPending end

-- No-ops kept because options or the other CDM files may still reference them.
ns.RefreshTBBResolvedIDs = function() end
ns.RefreshBuffBarGating  = function() end

I._MarkTBBReflowDirty, I._tbbWake, I.GroupGrowOf = _MarkTBBReflowDirty, _tbbWake, GroupGrowOf
I.GroupSpacingOf, I.ReflowVisibleGroupedTBBars = GroupSpacingOf, ReflowVisibleGroupedTBBars
I.ResetReflowStates, I.tbbFrames = ResetReflowStates, tbbFrames
I.broken = false
