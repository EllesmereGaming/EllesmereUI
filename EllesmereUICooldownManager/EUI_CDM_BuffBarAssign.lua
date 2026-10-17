if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarAssign.lua
--
--  Pairing of the Blizzard viewer frames with the bar configs, the buff
--  gain/loss sounds and auto-add.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local pcall = pcall

local AddTrackedBuffBarCore, SetECME = I.AddTrackedBuffBarCore, I.SetECME
local SetAssignDirty = I.SetAssignDirty

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
I.ecmeSetters[#I.ecmeSetters + 1] = function(v) ECME = v end
-- Assignment memo gate: cfg->frame pairing changes only on viewer pool composition
-- edges (aura events, pool Acquire, rebuilds, spec/cache invalidation); the tick
-- reuses the last pairing until dirtied. Starts dirty so the first tick always pairs.
local _tbbAssignDirty = true
I.assignDirtySetters[#I.assignDirtySetters + 1] = function(v) _tbbAssignDirty = v end
local _tbbAssignedFor

-------------------------------------------------------------------------------
--  CDM Child Lookup
--  Iterates the BuffBarCooldownViewer pool directly (tiny, 3-5 frames).
--  Matches by cooldownID first (cached on cfg), then by spell ID variants from
--  cooldownInfo. No external caches, no stale data in combat.
-------------------------------------------------------------------------------
-- cfg -> base-spell id seen once, awaiting a confirming second pass before the
-- permanent cfg.baseSpellID write (a pool frame mid-reuse can echo another
-- slot's ids for one pass). Separate table: frame-adjacent state must never
-- ride the config into SavedVariables.
local _tbbBaseCapturePending = {}

local function MatchesSID(info, sid)
    -- cooldownInfo id fields can read SECRET in restricted content, and a
    -- secret on either side of == hard-errors: every compare is gated. sid is
    -- the caller's cfg-side id (plain by contract).
    local isSec = issecretvalue
    if not (isSec and isSec(info.overrideSpellID)) and info.overrideSpellID == sid then return true end
    if not (isSec and isSec(info.spellID)) and info.spellID == sid then return true end
    if info.linkedSpellIDs then
        for _, lid in ipairs(info.linkedSpellIDs) do
            if not (isSec and isSec(lid)) and lid == sid then return true end
        end
    end
    return false
end

local function MatchFrameToConfig(frame, cfg)
    -- Cooldown-tracking bars are self-driven and never bind a viewer frame.
    if cfg.trackType == "cooldown" then return false end
    local cdID = frame.cooldownID
    if not cdID then return false end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return false end
    local info = gci(cdID)
    if not info then return false end
    -- Self-healing base capture for hero-talent override spells. A bar saved
    -- for the OVERRIDE form, matched while talented, sees the override in
    -- info.overrideSpellID and the BASE form in info.spellID. Record the base
    -- on the config so the bar keeps matching once the talent is removed:
    -- cooldownInfo carries the override id ONLY while talented, so without the
    -- stored base the bar goes dark when untalented (the cast becomes the base
    -- spell). Also backfills bars saved without a pick-time baseSpellID.
    local isSec = issecretvalue
    if cfg.spellID and cfg.spellID > 0 and not cfg.baseSpellID
       and not (isSec and isSec(info.overrideSpellID))
       and not (isSec and isSec(info.spellID))
       and info.overrideSpellID == cfg.spellID
       and info.spellID and info.spellID > 0 and info.spellID ~= cfg.spellID then
        -- Two matching reads on separate passes before committing: the write is
        -- permanent (SavedVariables), so a single transient echo from a frame
        -- mid-reuse must never corrupt the config's identity.
        if _tbbBaseCapturePending[cfg] == info.spellID then
            cfg.baseSpellID = info.spellID
            _tbbBaseCapturePending[cfg] = nil
        else
            _tbbBaseCapturePending[cfg] = info.spellID
        end
    end
    -- Fast path: match via cooldownInfo struct fields.
    if cfg.spellIDs then
        for _, sid in ipairs(cfg.spellIDs) do
            if MatchesSID(info, sid) then return true end
        end
    elseif cfg.spellID and cfg.spellID > 0 then
        if MatchesSID(info, cfg.spellID) then return true end
        -- Talent-override fallback: a bar saved for the override form also tracks its base, so it keeps showing after the talent is removed.
        if cfg.baseSpellID and cfg.baseSpellID > 0 and MatchesSID(info, cfg.baseSpellID) then
            return true
        end
    else
        return false
    end
    -- Fallback: the frame's canonical spell ID. Buff bar frames expose the actual aura
    -- variant via GetAuraSpellID, which may not appear in the cooldownInfo struct (e.g. Eclipse Solar/Lunar).
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    if GetCanonical then
        local frameSID = GetCanonical(frame)
        if frameSID then
            if cfg.spellIDs then
                for _, sid in ipairs(cfg.spellIDs) do
                    if frameSID == sid then return true end
                end
            elseif cfg.spellID and cfg.spellID > 0 then
                if frameSID == cfg.spellID then return true end
                if cfg.baseSpellID and frameSID == cfg.baseSpellID then return true end
            end
        end
    end
    return false
end

local _findChildGeneration = 0
-- Frame cache lives in its own table, NEVER on the config (which is in SavedVariables): frame refs must not leak into serialization.
local _findChildCache = {}

-- Sticky cfg->frame bindings for the one-to-one assignment pass below (cfg table -> last
-- paired Blizzard frame). Separate table for the same serialization reason; dropped on cache invalidation.
local _tbbStickyFrame = {}
-- cooldownID each sticky frame carried when bound: the secret-trust branch can
-- only trust a binding while the pooled frame still serves the same cooldown
-- slot (Blizzard reuses frame objects fast in combat). cooldownID stays a
-- plain readable number in secret windows (the clean-sid cache keys on it).
local _tbbStickyCdID = {}

function ns.InvalidateTBBFrameCache()
    _findChildGeneration = _findChildGeneration + 1
    wipe(_findChildCache)
    wipe(_tbbStickyFrame)
    wipe(_tbbStickyCdID)
    wipe(_tbbBaseCapturePending)
    -- Every structural edge funnels here (pool Acquire, spec swap, rebuilds), so the assignment memo retires with the caches.
    SetAssignDirty(true)
end

local function FindChild(cfg)
    -- Fast path: cached result from a previous match (hit or miss).
    local cached = _findChildCache[cfg]
    if cached and cached.gen == _findChildGeneration then
        if cached.frame and cached.frame.cooldownID == cached.cdID then
            return cached.frame
        end
    end
    -- Full scan: iterate BuffBarCooldownViewer pool (TBB's own viewer).
    local entry = { gen = _findChildGeneration, frame = nil, cdID = nil }
    _findChildCache[cfg] = entry
    local viewer = _G["BuffBarCooldownViewer"]
    if viewer and viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            if MatchFrameToConfig(frame, cfg) then
                entry.frame = frame
                entry.cdID = frame.cooldownID
                return frame
            end
        end
    end
    return nil
end
ns.FindTBBChild = FindChild

-------------------------------------------------------------------------------
--  AssignFramesToConfigs
--
--  Pairs each tracked-bar config to AT MOST ONE BuffBarCooldownViewer frame,
--  consuming every frame once so two configs can never mirror the same frame.
--  Required for multi-variant spells like Eclipse: Solar and Lunar share one
--  cooldownInfo (linkedSpellIDs lists both), so per-config FindChild() greedily
--  binds BOTH to whichever frame enumerates first ("Lunar twice, Solar never", and
--  the mirror case). Frame-driven matches the icon viewer: decorate one display per
--  Blizzard child rather than matching a stored spell back to an ambiguous frame.
--
--  Three passes, each only over still-unconsumed frames:
--    1. Sticky   -- reuse last tick's binding. Frame OBJECT identity never goes secret,
--       so a pairing locked out of combat survives GetAuraSpellID turning secret
--       mid-fight; revalidated against a clean read when one exists (self-heals a
--       recycled pool frame), trusted blindly while secret.
--    2. Exact    -- per-frame canonical id == the config's spell (clean reads pair
--       frameSolar->cfgSolar, frameLunar->cfgLunar); locks the sticky binding for future ticks.
--    3. Fallback -- cooldownInfo/linkedSpellIDs struct match for configs still unpaired
--       (combat, no prior sticky binding); consumption still guarantees no two configs land on the same frame.
--
--  Returns a cfg->frame map (a REUSED module table; copy it to retain it).
-------------------------------------------------------------------------------
local _tbbAssignment   = {}
local _tbbFrameScratch = {}
local _tbbConsumed     = {}
local _tbbFrameSID     = {}  -- frame -> canonical spell id, computed once per call
local _tbbFrameMember  = {}  -- frame -> live linked-family member, computed once per call

local function CfgWantsSID(cfg, sid)
    -- Cooldown-tracking bars NEVER match buff-viewer frames or buff coverage.
    if cfg.trackType == "cooldown" then return false end
    if not sid then return false end
    -- Tick paths feed raw aura/struct ids (icon, coverage): a secret survives
    -- the nil check and hard-errors on ==. Narrow matcher: secret = not
    -- provably ours.
    if issecretvalue and issecretvalue(sid) then return false end
    if cfg.spellIDs then
        for _, s in ipairs(cfg.spellIDs) do if s == sid then return true end end
        return false
    end
    if cfg.spellID and cfg.spellID > 0 then
        if sid == cfg.spellID then return true end
        if cfg.baseSpellID and cfg.baseSpellID > 0 and sid == cfg.baseSpellID then return true end
    end
    return false
end

local function FrameIsActive(frames, target)
    for i = 1, #frames do if frames[i] == target then return true end end
    return false
end

-- Name FAMILY of a display name: the part before the first colon, lowered
-- ("Diabolic Ritual: Overlord" -> "diabolic ritual"; a name without a colon
-- is its own family). Disambiguates collided viewer slots whose aura names
-- share a canonical spellID but not a prefix. nil for empty/unreadable.
local function TbbNameFamily(name)
    if type(name) ~= "string" or name == "" then return nil end
    local i = name:find(":", 1, true)
    -- zhCN/zhTW labels separate variants with the fullwidth colon (U+FF1A;
    -- decimal byte escapes -- Lua 5.1 has no hex escapes).
    local j = name:find("\239\188\154", 1, true)
    if j and (not i or j < i) then i = j end
    local fam = i and name:sub(1, i - 1) or name
    fam = fam:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if fam == "" then return nil end
    return fam
end

-- Live aura name family of a pool frame; nil when no clean aura read exists
-- (secret in restricted content, no bound instance) -- callers fall back to
-- first-match. Aura reads are the ONLY name source: never the frame's label.
local function TbbFrameNameFamily(frame)
    local iid = frame.auraInstanceID
    if not iid or (issecretvalue and issecretvalue(iid)) then return nil end
    local unit = frame.auraDataUnit
    if not unit then return nil end
    local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, iid)
    if not ok or not ad then return nil end
    local nm = ad.name
    if nm == nil or (issecretvalue and issecretvalue(nm)) then return nil end
    return TbbNameFamily(nm)
end

-- Which member of a LINKED FAMILY a buff slot is mirroring right now. Blizzard
-- binds ONE cooldownID to whichever of its linkedSpellIDs is on the player and
-- publishes the answer as cooldownInfo.linkedSpellID, maintained on the aura
-- edges (CooldownViewerItemMixin:NeedsAddedAuraUpdate / OnUnitAuraRemovedEvent),
-- so Roll the Bones cycles a single slot through every outcome and the hint
-- follows. Needed because GetSpellID()/GetAuraSpellID() read secret while the
-- slot is active, leaving the canonical resolver to answer from the clean-read
-- memo keyed on cooldownID, which still names the member that was up at the last
-- CLEAN read: the previous outcome keeps the frame and mirrors the new outcome's
-- timer while the new outcome draws a second bar off the per-spell aura fallback.
local function TbbLinkedMemberSID(frame)
    local info = frame.cooldownInfo
    if not info then
        local fnGetInfo = frame.GetCooldownInfo
        if type(fnGetInfo) ~= "function" then return nil end
        info = fnGetInfo(frame)
    end
    local linked = info and info.linkedSpellIDs
    if type(linked) ~= "table" or #linked < 2 then return nil end
    -- Set from the added aura's spellId, so it can be secret in restricted content.
    local sid = info.linkedSpellID
    if type(sid) ~= "number" or (issecretvalue and issecretvalue(sid)) then return nil end
    return sid
end

-- Per-config name families for label/binding compatibility: cfg.name (the
-- picker's display name) plus the resolved spellID/baseSpellID names.
-- Weak-keyed memo; every input is re-checked on hit so options edits
-- self-invalidate, and entries with unloaded spell data retry until resolved
-- (same class as the deferred name fill).
local _tbbCfgFamilies = setmetatable({}, { __mode = "k" })

local function TbbCfgFamilies(cfg)
    local e = _tbbCfgFamilies[cfg]
    if e and not e.retry and e.nm == cfg.name and e.sid == cfg.spellID
       and e.bsid == cfg.baseSpellID then
        return e
    end
    if not e then e = {}; _tbbCfgFamilies[cfg] = e end
    e.nm, e.sid, e.bsid = cfg.name, cfg.spellID, cfg.baseSpellID
    e.retry = nil
    e.f1 = TbbNameFamily(cfg.name)
    e.f2, e.f3 = nil, nil
    if cfg.spellID and cfg.spellID > 0 then
        local si = C_Spell.GetSpellInfo(cfg.spellID)
        if si and si.name then e.f2 = TbbNameFamily(si.name) else e.retry = true end
    end
    if cfg.baseSpellID and cfg.baseSpellID > 0 then
        local si = C_Spell.GetSpellInfo(cfg.baseSpellID)
        if si and si.name then e.f3 = TbbNameFamily(si.name) else e.retry = true end
    end
    return e
end

-- Two families are compatible when equal or one extends the other ("eclipse"
-- vs "eclipse (solar)") -- variant naming keeps the base name as a prefix,
-- while different abilities ("spirit walk" vs "spirit wolf") never do.
local function TbbFamiliesCompatible(a, b)
    if not a or not b then return false end
    if a == b then return true end
    return a:find(b, 1, true) == 1 or b:find(a, 1, true) == 1
end

-- fam vs ANY of the config's known families. openOnUnknown decides the
-- verdict when either side is unknowable (the label gate fails OPEN to
-- today's behavior; variant evidence fails CLOSED).
local function TbbCfgFamilyMatch(cfg, fam, openOnUnknown)
    local e = TbbCfgFamilies(cfg)
    local f1, f2, f3 = e.f1, e.f2, e.f3
    if fam == nil or not (f1 or f2 or f3) then return openOnUnknown end
    return TbbFamiliesCompatible(fam, f1) or TbbFamiliesCompatible(fam, f2)
        or TbbFamiliesCompatible(fam, f3)
end

-- cooldownID -> definite "variant-labeled slot" verdict, session-long (cdIDs
-- are stable per session; verdicts only come from fully readable inputs). A
-- slot is variant-labeled when its linked forms resolve to MORE THAN ONE
-- distinct display string (Diabolist ritual trios, Eclipse Solar/Lunar) --
-- the only case where a SECRET label can say something the config name
-- cannot. Field 2026-08: a hidden pool frame can render another slot's text
-- persistently after re-acquire, so unproven slots never paint secret labels.
local _tbbVariantSlot = {}

local function TbbSlotVariantLabeled(bar, cdID)
    if type(cdID) ~= "number" or (issecretvalue and issecretvalue(cdID)) then
        return false
    end
    local known = _tbbVariantSlot[cdID]
    if known ~= nil then return known end
    -- In combat one indefinite probe is pinned per binding (secret linked ids
    -- would otherwise re-derive at 60Hz); out of combat retries until the
    -- verdict is definite (spell data load is the only wait).
    if bar._varProbeCd == cdID and InCombatLockdown() then
        return bar._varProbeVal or false
    end
    local verdict, complete = false, false
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info then
            local isSec = issecretvalue
            local lids = info.linkedSpellIDs
            if not lids or #lids == 0 then
                -- No linked forms at all: definitively single-labeled.
                _tbbVariantSlot[cdID] = false
                return false
            end
            complete = true
            local baseNm
            local bsid = info.spellID
            if bsid and not (isSec and isSec(bsid)) then
                local si = C_Spell.GetSpellInfo(bsid)
                local nm = si and si.name
                if nm and not (isSec and isSec(nm)) then baseNm = nm:lower() end
            end
            if not baseNm then complete = false end
            local firstNm
            for k = 1, #lids do
                local lid = lids[k]
                local nm
                if type(lid) == "number" and not (isSec and isSec(lid)) then
                    local si = C_Spell.GetSpellInfo(lid)
                    nm = si and si.name
                    if nm and (isSec and isSec(nm)) then nm = nil end
                end
                if not nm then
                    complete = false
                else
                    nm = nm:lower()
                    if baseNm and nm ~= baseNm then verdict = true; break end
                    if firstNm == nil then
                        firstNm = nm
                    elseif nm ~= firstNm then
                        verdict = true; break
                    end
                end
            end
        end
    end
    if verdict or complete then
        _tbbVariantSlot[cdID] = verdict
    else
        bar._varProbeCd, bar._varProbeVal = cdID, verdict
    end
    return verdict
end

-- Pass-3 candidate veto: a fuzzy struct match (linked-group membership) can
-- be a mechanically different neighbor -- Blizzard links Spirit Walk into the
-- Spirit Wolf slot's group, and with Spirit Walk's own frame inactive the
-- neighbor is the UNIQUE match (field 2026-08). A READABLE live aura name
-- that is family-incompatible with the config rejects the candidate;
-- secret/unreadable fails open so variant slots stay bindable in combat.
local function TbbFuzzyNameOK(cfg, frame)
    local fam = TbbFrameNameFamily(frame)
    if not fam then return true end
    return TbbCfgFamilyMatch(cfg, fam, true)
end

local function AssignFramesToConfigs(bars)
    local assignment = _tbbAssignment
    -- Memo: pairing moves only on composition edges (player aura events, pool
    -- Acquire, cache invalidation, rebuilds -- all set the dirty flag), so the
    -- ~60Hz tick reuses the last map instead of re-enumerating the pool and
    -- re-resolving canonical ids every frame. Bars-table identity check is the
    -- belt for spec swaps that replace the table without hitting an invalidation site.
    if not _tbbAssignDirty and _tbbAssignedFor == bars then
        return assignment
    end
    SetAssignDirty(false)
    _tbbAssignedFor = bars
    wipe(assignment)
    if not bars then return assignment end

    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or not viewer.itemFramePool then return assignment end

    -- Snapshot the active pool once (EnumerateActive consumes the enumeration) and
    -- resolve each frame's canonical spell id ONCE -- otherwise the passes below
    -- re-query it O(configs x frames) per tick, each call pcalling live frame APIs.
    -- Caching also gives every pass a consistent within-tick view of frame identity.
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    local frames = _tbbFrameScratch
    wipe(frames)
    wipe(_tbbFrameSID)
    wipe(_tbbFrameMember)
    for frame in viewer.itemFramePool:EnumerateActive() do
        frames[#frames + 1] = frame
        _tbbFrameSID[frame] = GetCanonical and GetCanonical(frame) or nil
        if frame.IsActive and frame:IsActive() then
            _tbbFrameMember[frame] = TbbLinkedMemberSID(frame)
        end
    end

    -- The family hint overrides the canonical memo only where (1) some enabled
    -- bar actually WANTS the member: a single bar tracking the family under
    -- its base/shared id must keep its per-slot memo, or the flip releases a
    -- working binding for nothing (claim-style gate; also keeps shared-id
    -- configs like Diabolist's on their memos if a variant stamp ever reads
    -- clean), and (2) it is UNIQUE among the active slots: collided slots each
    -- list the whole family (Eclipse Solar and Lunar, both up), so an added
    -- aura stamps the same member on BOTH and only their per-slot memos still
    -- tell them apart.
    for i = 1, #frames do
        local m = _tbbFrameMember[frames[i]]
        if m then
            local wanted = false
            for _, c in ipairs(bars) do
                if CfgWantsSID(c, m) then wanted = true; break end
            end
            local unique = wanted
            if unique then
                for j = 1, #frames do
                    if j ~= i and _tbbFrameMember[frames[j]] == m then unique = false; break end
                end
            end
            if unique then _tbbFrameSID[frames[i]] = m end
        end
    end

    local consumed = _tbbConsumed
    wipe(consumed)

    -- Pass 1: sticky.
    for _, cfg in ipairs(bars) do
        local bound = _tbbStickyFrame[cfg]
        -- A bar converted to cooldown tracking must release its old viewer-frame binding
        -- immediately: the secret-trust branch below never calls CfgWantsSID, so otherwise it would keep consuming the frame.
        if bound and cfg.trackType == "cooldown" then
            _tbbStickyFrame[cfg] = nil
            bound = nil
        end
        if bound and not consumed[bound] and FrameIsActive(frames, bound) then
            local sid = _tbbFrameSID[bound]
            if sid then
                -- Clean read available: keep only if still the right variant AND
                -- (collided slots) still the right name family -- a crossed
                -- pairing must release here or pass 2 can never re-pair it.
                local keep = CfgWantsSID(cfg, sid)
                if keep then
                    local want = TbbNameFamily(cfg.name)
                    if want then
                        local fam = TbbFrameNameFamily(bound)
                        if fam and fam ~= want then keep = false end
                    end
                end
                if keep then
                    assignment[cfg]      = bound
                    consumed[bound]      = true
                    _tbbStickyCdID[cfg]  = bound.cooldownID
                else
                    _tbbStickyFrame[cfg] = nil
                    _tbbStickyCdID[cfg]  = nil
                end
            elseif bound.cooldownID == _tbbStickyCdID[cfg] then
                -- Secret/combat, but the frame still serves the cooldown slot it
                -- was bound under: trust the binding locked in earlier.
                assignment[cfg] = bound
                consumed[bound] = true
            else
                -- Same frame object, different cooldown slot (pool reused it
                -- mid-secret-window) -- a stale binding here is exactly the
                -- wrong-name/wrong-icon report; drop it rather than guess.
                _tbbStickyFrame[cfg] = nil
                _tbbStickyCdID[cfg]  = nil
            end
        end
    end

    -- Pass 2: exact per-frame identity. COLLIDED slots (two viewer slots
    -- sharing one canonical spellID -- Diabolist Demonic Art vs Diabolic
    -- Ritual, where Blizzard hands the Art slot the Ritual's id) fit two
    -- configs identically by sid, and a first-match pairing crosses them
    -- ("Diabolic Ritual" bar bound to the Art frame, faithfully naming
    -- Overlord). Tie-break by NAME FAMILY: the config keeps the picker's
    -- display name and the two slots' aura names differ by prefix, so among
    -- sid-matching frames the one whose live aura name shares the config
    -- name's prefix wins; unique matches take the fast path unchanged.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            local pick
            local want = TbbNameFamily(cfg.name)
            for i = 1, #frames do
                local frame = frames[i]
                if not consumed[frame] then
                    local sid = _tbbFrameSID[frame]
                    if sid and CfgWantsSID(cfg, sid) then
                        if not want then pick = frame; break end
                        local fam = TbbFrameNameFamily(frame)
                        if fam == want then pick = frame; break end
                        -- Family unreadable/other: remember the first, keep looking
                        -- for a frame that actually names this config's family.
                        if not pick then pick = frame end
                    end
                end
            end
            if pick then
                assignment[cfg]      = pick
                consumed[pick]       = true
                _tbbStickyFrame[cfg] = pick
                _tbbStickyCdID[cfg]  = pick.cooldownID
            end
        end
    end

    -- Pass 3: cooldownInfo/linkedSpellIDs struct fallback. NEVER sticky a fuzzy
    -- match: let a later clean read re-pair it exactly in pass 2. Binds only
    -- when the match is unique BOTH ways (one frame fits this cfg, and no other
    -- unassigned cfg fits that frame) -- shared linkedSpellIDs data makes fuzzy
    -- matches ambiguous, and a guessed pairing is worse than a blank bar.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            local candidate, matches = nil, 0
            for i = 1, #frames do
                local frame = frames[i]
                if not consumed[frame] and MatchFrameToConfig(frame, cfg)
                   and TbbFuzzyNameOK(cfg, frame) then
                    matches = matches + 1
                    candidate = frame
                end
            end
            if matches == 1 then
                local cfgMatches = 0
                for _, other in ipairs(bars) do
                    if not assignment[other] and MatchFrameToConfig(candidate, other)
                       and TbbFuzzyNameOK(other, candidate) then
                        cfgMatches = cfgMatches + 1
                    end
                end
                if cfgMatches == 1 then
                    assignment[cfg]     = candidate
                    consumed[candidate] = true
                end
            end
        end
    end

    return assignment
end
ns.AssignTBBFramesToConfigs = AssignFramesToConfigs

-------------------------------------------------------------------------------
--  Audio on Buff Gain / Loss for Tracking Bars
--
--  Same two keys as the CDM buff icons (buffActiveSoundKey / buffLostSoundKey,
--  nil = silent), stored per bar config, and the same pipeline. Blizzard-tracked
--  bars need no hook of their own: InstallBuffFrameHooks already puts the
--  apply/remove alert hooks on both buff viewers' frames, and RecordBuffEdge
--  asks ns.FindTBBSoundKey (ahead of the Buffs bar tiers for a Tracked Bars
--  frame, after them for a buff icon frame). The self-timed presets have no
--  Blizzard alert, so their timer edges call ns.TBBPresetSoundEdge. Bars that
--  track a cooldown never cue. Everything here is on ns. Gated 0-cost on
--  ns._tbbAnyBuffSound, the tracking-bar half of ns._cdmAnyBuffSound.
-------------------------------------------------------------------------------

-- Sound key for the tracking bar that owns this Blizzard frame / spell id.
-- The current pairing names the exact bar (Eclipse-style shared slots), but
-- only while it still fits the frame: the pool reuses frame objects across
-- cooldown slots, and a relayout while the tick sleeps leaves the pairing
-- stale. An id match covers a frame the pairing has not seen yet (its first
-- activation). Presets cue from their own windows, never from an alert.
-- Returns the key; false when the owning bar has a sound on its other edge
-- only (this edge is its own silence, so no Buffs bar sound may stand in);
-- nil when no bar has a say.
function ns.FindTBBSoundKey(frame, sid, field)
    if not (ECME and ECME.db) then SetECME(ns.ECME) end
    local p = ECME and ECME.db and ECME.db.profile
    if not p or (p.cdmBars and p.cdmBars.useBlizzardBuffBars) then return nil end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    if not bars then return nil end
    local cfg
    if frame and _tbbAssignedFor == bars then
        for c, f in pairs(_tbbAssignment) do
            if f == frame then
                if c.enabled ~= false and not c.popularKey and c.trackType ~= "cooldown" then
                    local sc = _tbbStickyCdID[c]
                    if (sc ~= nil and frame.cooldownID == sc) or CfgWantsSID(c, sid)
                       or MatchFrameToConfig(frame, c) then
                        cfg = c
                    end
                end
                break
            end
        end
    end
    if not cfg then
        for _, c in ipairs(bars) do
            if c.enabled ~= false and not c.popularKey and CfgWantsSID(c, sid) then
                cfg = c; break
            end
        end
    end
    if not cfg then return nil end
    local key = cfg[field]
    if key and key ~= "none" then return key end
    local g, l = cfg.buffActiveSoundKey, cfg.buffLostSoundKey
    if (g and g ~= "none") or (l and l ~= "none") then return false end
    return nil
end

-- Any tracking bar in any spec of this profile with a gain or loss sound
-- (feeds ns.RescanBuffSoundFlag). Cooldown-tracking bars never cue.
function ns.TBBAnyBuffSound()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return false end
    for _, prof in pairs(sp) do
        local tbb = type(prof) == "table" and prof.trackedBuffBars
        if type(tbb) == "table" and type(tbb.bars) == "table" then
            for _, c in ipairs(tbb.bars) do
                if c.trackType ~= "cooldown" then
                    local g, l = c.buffActiveSoundKey, c.buffLostSoundKey
                    if (g and g ~= "none") or (l and l ~= "none") then return true end
                end
            end
        end
    end
    return false
end

-- Tracking-bar sound enable (a bar's sound set in options, or the rescan
-- finding one): flips both gates live and hooks the buff viewer frames already
-- out of their pools, since pool Acquire only hooks while the gate is on. Both
-- viewers: a bar's spell can live in either one.
function ns.EnsureTBBSoundHooks()
    ns._cdmAnyBuffSound = true
    ns._tbbAnyBuffSound = true
    local hook = ns.EnsureBuffSoundHook
    if not hook then return end
    local viewer = _G.BuffBarCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if pool then
        for frame in pool:EnumerateActive() do hook(frame) end
    end
    viewer = _G.BuffIconCooldownViewer
    pool = viewer and viewer.itemFramePool
    if pool then
        for frame in pool:EnumerateActive() do hook(frame) end
    end
end

-- [popularKey] = GetTime() a latched preset window ends at (loss still to cue).
ns._tbbPresetLoss = {}

-- Self-timed preset edge. The gain comes from the event that (re)starts the
-- window (Sated rise, Time Spiral glow, potion cast), so a refresh cues again,
-- and latches the loss at the window's end (expiry) while a bar of that preset
-- has a loss sound. The tracking-bar tick fires the latch ahead of its
-- visibility gates, so a bar parked at that moment still cues; a consumed
-- Time Spiral cues from its glow hide, which clears the latch. One cue per
-- edge: the throttle id is per preset, so with two bars of one preset only
-- the first bar with a sound plays.
function ns.TBBPresetSoundEdge(popularKey, gainEdge, expiry)
    if not ns._tbbAnyBuffSound or not popularKey then return end
    local latch = ns._tbbPresetLoss
    -- Clear only a present entry: the tick calls in here while walking the latch table.
    if latch[popularKey] then latch[popularKey] = nil end
    if not (ECME and ECME.db) then SetECME(ns.ECME) end
    local p = ECME and ECME.db and ECME.db.profile
    if not p or (p.cdmBars and p.cdmBars.useBlizzardBuffBars) then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    if not bars then return end
    local field = gainEdge and "buffActiveSoundKey" or "buffLostSoundKey"
    for _, cfg in ipairs(bars) do
        if cfg.enabled ~= false and cfg.popularKey == popularKey
           and cfg.trackType ~= "cooldown" then
            local key = cfg[field]
            if key and key ~= "none" then ns.PlayBuffSoundEdge(key, "tbb:" .. popularKey, gainEdge) end
            local lost = cfg.buffLostSoundKey
            if gainEdge and expiry and lost and lost ~= "none" then latch[popularKey] = expiry end
        end
    end
end

--- Frame-based check: is a spellID present in BuffBarCooldownViewer? Iterates the tiny pool
--- (~3-5 frames), matching via MatchesSID across all fields (overrideSpellID, spellID, linkedSpellIDs).
function ns.IsSpellInBuffBarViewer(spellID)
    if not spellID or spellID <= 0 then return false end
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or not viewer.itemFramePool then return false end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return false end
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    for frame in viewer.itemFramePool:EnumerateActive() do
        local cdID = frame.cooldownID
        if cdID then
            local info = gci(cdID)
            if info and MatchesSID(info, spellID) then
                return true
            end
            -- Fallback: check frame's canonical spell ID (aura variants).
            if GetCanonical then
                local frameSID = GetCanonical(frame)
                if frameSID == spellID then return true end
            end
        end
    end
    return false
end

--- Enumerate all spells in BuffBarCooldownViewer ("Tracked Bars") as {spellID, cdID, name,
--- icon} sorted by layoutIndex then name. Source of truth for the TBB spell picker: TBB IS
--- our display of these bars, so the picker enumerates THIS pool, never the Tracked Buffs icon viewer.
function ns.GetTrackedBarSpells(includeUntalented)
    local result = {}
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    local seen = {}

    -- Display name plus subtext (e.g. "Solar", "Lunar") to disambiguate spells sharing a base name like Eclipse.
    local function ResolveName(sid)
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
        if name and C_Spell.GetSpellSubtext then
            local sub = C_Spell.GetSpellSubtext(sid)
            if sub and sub ~= "" then name = name .. " (" .. sub .. ")" end
        end
        return name
    end

    local viewer = _G["BuffBarCooldownViewer"]
    if viewer and viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            if frame:IsShown() or frame.cooldownInfo then
                local sid = GetCanonical and GetCanonical(frame)
                if sid and sid > 0 and not seen[sid] then
                    seen[sid] = true
                    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                    result[#result + 1] = {
                        spellID     = sid,
                        cdID        = frame.cooldownID,
                        name        = ResolveName(sid) or ("Spell " .. sid),
                        icon        = icon,
                        layoutIndex = frame.layoutIndex or 0,
                        -- Live pool members are always learned; catalog entries appended below may not be.
                        isKnown     = true,
                    }
                end
            end
        end
    end

    -- Tracked-but-untalented bar spells have no live BuffBar frame, so pull them from the
    -- settings catalog (TrackedBar category). Picker-only (includeUntalented); auto-add and
    -- section checks stay live-only. Provider down/names missing -> nothing appended. Dedup
    -- by canonical sid, same as the live-pool dedup above.
    if includeUntalented and ns.EnumerateCDMSettingsCatalog then
        local evc = Enum and Enum.CooldownViewerCategory
        local barCat = evc and (evc.TrackedBar or 3)
        local catalog = barCat and ns.EnumerateCDMSettingsCatalog({ [barCat] = true })
        if catalog then
            local extra = 0
            for _, ce in ipairs(catalog) do
                if ce.sid and ce.sid > 0 and not seen[ce.sid] then
                    seen[ce.sid] = true
                    local nm = ResolveName(ce.sid)
                    if nm then
                        local known = (IsPlayerSpell and IsPlayerSpell(ce.sid)) and true or false
                        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ce.sid)
                        extra = extra + 1
                        result[#result + 1] = {
                            spellID     = ce.sid,
                            cdID        = ce.cdID,
                            name        = nm,
                            icon        = icon,
                            -- No live frame -> no layoutIndex; sort after live entries, keeping catalog order among themselves.
                            layoutIndex = 100000 + extra,
                            isKnown     = known,
                        }
                    end
                end
            end
        end
    end

    table.sort(result, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return (a.name or "") < (b.name or "")
    end)
    return result
end

-------------------------------------------------------------------------------
--  Auto-add: opt-in per group ("Auto-Add New to This Group"). While a group holds
--  the flag, any spell newly appearing in Blizzard's Tracked Bars section gets a
--  bar in that group; turning the flag ON populates a bar for every currently
--  tracked spell. Deleted bars stay deleted -- their spells remain in the
--  tbb.autoSeen ledger; only the populate-on-enable pass ignores it ("give me everything").
-------------------------------------------------------------------------------
local function SpellCoveredByBars(bars, sp)
    -- Variant/override coverage: a bar saved for one form covers the whole linked set
    -- (base/override/aura variants share a cooldownInfo), so an Eclipse Solar bar is not
    -- duplicated when Lunar's frame appears under a talent-swapped id.
    local info
    if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        info = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
    end
    for _, cfg in ipairs(bars) do
        if CfgWantsSID(cfg, sp.spellID) then return true end
        if info then
            if CfgWantsSID(cfg, info.spellID) then return true end
            if CfgWantsSID(cfg, info.overrideSpellID) then return true end
            if info.linkedSpellIDs then
                for _, lid in ipairs(info.linkedSpellIDs) do
                    if CfgWantsSID(cfg, lid) then return true end
                end
            end
        end
    end
    return false
end

-- Shared guards for both auto-add passes. Returns the tbb table, or nil when the pass must not run right now.
local function AutoAddReady()
    if not (ECME and ECME.db) then SetECME(ns.ECME) end
    if not (ECME and ECME.db) then return nil end
    local p = ECME.db.profile
    if p.cdmBars and p.cdmBars.useBlizzardBuffBars then return nil end
    if InCombatLockdown() then return nil end
    return ns.GetTrackedBuffBars()
end

-- Worker: create a bar in `gid` for every tracked spell not covered by an existing bar.
-- `ignoreSeen` = full populate (enable pass); otherwise only never-seen spells count, so deleted bars stay deleted.
local function AutoAddTrackedToGroup(tbb, gid, ignoreSeen)
    local tracked = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells() or {}
    -- An empty list also means "viewer not populated yet" (login order): nothing to act on either way.
    if #tracked == 0 then return 0 end
    -- Postpone while any pool frame's spell identity is unresolved (login spell-data races):
    -- acting on a partial list could later mis-read a long-tracked spell as "new".
    do
        local viewer = _G["BuffBarCooldownViewer"]
        local GetCanonical = ns.GetCanonicalSpellIDForFrame
        if viewer and viewer.itemFramePool and GetCanonical then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if (frame:IsShown() or frame.cooldownInfo) and not GetCanonical(frame) then
                    return 0
                end
            end
        end
    end
    tbb.autoSeen = tbb.autoSeen or {}
    local added = 0
    for _, sp in ipairs(tracked) do
        if ignoreSeen or not tbb.autoSeen[sp.spellID] then
            tbb.autoSeen[sp.spellID] = true
            if not SpellCoveredByBars(tbb.bars, sp) then
                local idx = AddTrackedBuffBarCore(tbb, gid)
                local nb = tbb.bars[idx]
                nb.spellID = sp.spellID
                nb.name = sp.name
                -- Base-form capture for talent-override spells (same as the picker): keeps the bar matching once the talent is removed.
                if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
                    if info and info.spellID and info.spellID > 0 and info.spellID ~= sp.spellID then
                        nb.baseSpellID = info.spellID
                    end
                end
                added = added + 1
            end
        end
    end
    return added
end

-- Incremental pass: bars for spells newly appearing in the Tracked Bars section, routed to
-- the flagged group. Returns bars added (configs only; callers rebuild); no-op unless a group opted in.
function ns.EnsureTBBAutoBars()
    local tbb = AutoAddReady()
    if not tbb then return 0 end
    local gid = ns.TBBAutoAddGroupID()
    if not gid then return 0 end
    return AutoAddTrackedToGroup(tbb, gid, false)
end

-- Full populate for the moment "Auto-Add New to This Group" is switched ON: one bar per tracked spell not already covered somewhere, ledger ignored.
function ns.PopulateTBBAutoAddGroup(gid)
    if not gid or gid == 0 then return 0 end
    local tbb = AutoAddReady()
    if not tbb then return 0 end
    return AutoAddTrackedToGroup(tbb, gid, true)
end

-- Debounced entry point for the buff-bar viewer pool hooks: a spell dragged into Blizzard's
-- Tracked Bars section acquires a new pool frame and lands here. Combat acquires are skipped
-- (tracked-set edits happen out of combat; mid-fight acquires are just known auras activating).
local _tbbAutoAddQueued = false
function ns.QueueTBBAutoAdd()
    if _tbbAutoAddQueued then return end
    if InCombatLockdown() then return end
    _tbbAutoAddQueued = true
    C_Timer.After(1.0, function()
        _tbbAutoAddQueued = false
        if ns.EnsureTBBAutoBars() > 0 then
            ns.BuildTrackedBuffBars()
            if ns.OnTBBBarsAutoAdded then ns.OnTBBBarsAutoAdded() end
        end
    end)
end

I._tbbAssignment, I._tbbStickyCdID = _tbbAssignment, _tbbStickyCdID
I.AssignFramesToConfigs, I.CfgWantsSID = AssignFramesToConfigs, CfgWantsSID
I.MatchesSID, I.TbbCfgFamilyMatch = MatchesSID, TbbCfgFamilyMatch
I.TbbNameFamily, I.TbbSlotVariantLabeled = TbbNameFamily, TbbSlotVariantLabeled
I.broken = false
