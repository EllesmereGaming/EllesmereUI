-------------------------------------------------------------------------------
--  EllesmereUICdmHooks.lua  (v5 -- Mixin Hook Architecture)
--
--  CORE PRINCIPLE: Blizzard manages all cooldown/buff state.
--  We ONLY restyle (borders, shapes, fonts) and reposition (into our bars).
--
--  Hook strategy:
--    - OnCooldownIDSet on all 4 Blizzard CDM mixins -> QueueReanchor
--    - Pool Acquire on all viewers -> QueueReanchor
--    - Viewer Layout hooks -> QueueReanchor (catches frame removals)
--
--  Taint prevention:
--    - Never SetParent/SetScale/Hide/Show on Blizzard frames
--    - Never move Blizzard frames offscreen
--    - Never write custom keys to Blizzard frame tables
--    - All per-frame data in external weak-keyed tables
--    - Unclaimed frames: SetAlpha(0). Claimed: SetAlpha(1).
-------------------------------------------------------------------------------
local _, ns = ...

local ECME               = ns.ECME
local barDataByKey        = ns.barDataByKey
local cdmBarFrames        = ns.cdmBarFrames
local cdmBarIcons         = ns.cdmBarIcons
local MAIN_BAR_KEYS       = ns.MAIN_BAR_KEYS
local ResolveInfoSpellID  = ns.ResolveInfoSpellID
local GetCDMFont          = ns.GetCDMFont

local floor   = math.floor
local GetTime = GetTime
local _, _playerClass = UnitClass("player")
local _isDruid = (_playerClass == "DRUID")

-------------------------------------------------------------------------------
--  Memory Profiling (temporary)
-------------------------------------------------------------------------------
local _memProf = {}
local _memProfLast = 0
local function MemSnap(label)
    local kb = collectgarbage("count")
    if not _memProf[label] then _memProf[label] = { total = 0, calls = 0, peak = 0 } end
    _memProf[label]._pre = kb
end
local function MemDelta(label)
    local p = _memProf[label]
    if not p or not p._pre then return end
    local delta = collectgarbage("count") - p._pre
    p.total = p.total + delta
    p.calls = p.calls + 1
    if delta > p.peak then p.peak = delta end
    p._pre = nil
end
local function MemReport()
    local now = GetTime()
    if now - _memProfLast < 10 then return end
    _memProfLast = now
    local sorted = {}
    for k, v in pairs(_memProf) do
        sorted[#sorted + 1] = { name = k, total = v.total, calls = v.calls, peak = v.peak }
    end
    table.sort(sorted, function(a, b) return a.total > b.total end)
    -- print("|cff00ffff[CDM MEM]|r Top allocators (last 10s):")
    -- for i = 1, math.min(8, #sorted) do
    --     local e = sorted[i]
    --     print(string.format("  %s: %.1f KB total, %d calls, %.2f KB peak",
    --         e.name, e.total, e.calls, e.peak))
    -- end
    for k in pairs(_memProf) do _memProf[k] = { total = 0, calls = 0, peak = 0 } end
end
ns._MemSnap = MemSnap
ns._MemDelta = MemDelta

ns._spellOrderDirty = true  -- start dirty so first reanchor builds caches

-- Per-frame decoration state (weak-keyed)
local hookFrameData = setmetatable({}, { __mode = "k" })
ns._hookFrameData = hookFrameData

-- Force any currently-active buff glows to re-apply on the next buff tick
-- (<=0.1s). The buff tick only (re)starts a glow when fd.buffGlowActive is
-- false, so live option changes (Buff Glow color, or the pixel Lines/Thickness/
-- Speed) would otherwise never reach an already-glowing icon. Clearing the flag
-- lets the tick restart the glow with the current parameters -- used by the
-- permanently-shown custom aura preview while CDM Bars options are open.
function ns.RefreshBuffGlows()
    for _, icons in pairs(cdmBarIcons) do
        for fi = 1, #icons do
            local frame = icons[fi]
            local fd = frame and hookFrameData[frame]
            if fd and fd.buffGlowActive then
                fd.buffGlowActive = false
            end
        end
    end
end

-- External frame cache from main file
local _ecmeFC = ns._ecmeFC
local FC = ns.FC

local function FD(f)
    local d = hookFrameData[f]
    if not d then d = {}; hookFrameData[f] = d end
    return d
end
ns.FD = FD

-------------------------------------------------------------------------------
--  Resource verification for the CD Ready Glow.
--
--  C_Spell.IsSpellUsable() can briefly report a resource-gated spell as
--  usable right after login/reload (observed with Void Ray on Devourer
--  Demon Hunter) before Blizzard's internal power data has fully settled.
--  Rather than guess at a timing window, HasEnoughResources re-derives the
--  answer from live UnitPower()/UnitPowerMax() values, which are always
--  accurate -- including immediately after login. Callers AND this with
--  IsSpellUsable so cooldown/form/lockout gating is unaffected; only the
--  resource portion gets a deterministic second opinion.
--
--  Declared early in the file (before FD/ResolveSpellSettings usage further
--  down) since Lua locals are only visible after their textual declaration --
--  defining it later but using it earlier produced a nil-call error.
--
--  Optimization: GetSpellPowerCost() allocates a new Lua table on every call
--  and is a C-API call. A spell's power cost only changes on talent/spec swap,
--  not during combat, so the result is cached and invalidated on
--  PLAYER_SPECIALIZATION_CHANGED and PLAYER_ENTERING_WORLD. The hot path (every
--  UNIT_POWER_UPDATE) then does only a table lookup.
-------------------------------------------------------------------------------
local _spellPowerCostCache = {}

local function InvalidateSpellPowerCostCache()
    wipe(_spellPowerCostCache)
end
ns.InvalidateSpellPowerCostCache = InvalidateSpellPowerCostCache

do
    local _pccInvalidateFrame = CreateFrame("Frame")
    _pccInvalidateFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _pccInvalidateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _pccInvalidateFrame:SetScript("OnEvent", InvalidateSpellPowerCostCache)
end

local function HasEnoughResources(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return true end
    -- Cache lookup: sentinel nil = not yet checked, false = no cost
    -- (=> always enough), table = cached cost list.
    local cached = _spellPowerCostCache[spellID]
    if cached == nil then
        local costs = C_Spell.GetSpellPowerCost(spellID)
        if not costs or #costs == 0 then
            _spellPowerCostCache[spellID] = false  -- no resource gate
            return true
        end
        _spellPowerCostCache[spellID] = costs
        cached = costs
    elseif cached == false then
        return true  -- no resource gate, cached
    end
    for _, c in ipairs(cached) do
        local powerType = c.type
        if powerType then
            local cost = c.cost or 0
            if c.costPercent and c.costPercent > 0 then
                -- Power can be a SECRET number in tainted combat; can't compare it,
                -- so default to castable rather than throw.
                local maxP = UnitPowerMax("player", powerType)
                if issecretvalue and issecretvalue(maxP) then return true end
                cost = math.max(cost, (c.costPercent / 100) * maxP)
            end
            if cost > 0 then
                local cur = UnitPower("player", powerType)
                if issecretvalue and issecretvalue(cur) then return true end
                if cur < cost then return false end
            end
        end
    end
    return true
end
ns.HasEnoughResources = HasEnoughResources

-- True once we've received at least one genuine UNIT_POWER_FREQUENT for the
-- player since the last PLAYER_ENTERING_WORLD. Both C_Spell.IsSpellUsable()
-- and C_Spell.GetSpellPowerCost() can briefly return stale/empty data right
-- at login/reload (observed: GetSpellPowerCost reporting 0 cost for a 100-Fury
-- spell, making HasEnoughResources default to "enough" when it should not).
-- Rather than guess a delay, we simply don't trust resource-gated glow
-- decisions until the client has actually pushed us a real power value.
-- This is event-driven, not polled: setting it costs one boolean write, and
-- it naturally self-corrects via the already-registered UNIT_POWER_FREQUENT
-- listener below, which re-triggers QueueCDGlowUpdate on every change.
ns._cdGlowPowerConfirmed = true

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

-- Blizzard creates these 4 viewer frames once and never replaces the frame
-- object for the rest of the session, so a global-table lookup (_G[name])
-- is wasted work once we've found it -- cache the resolved frame reference.
-- Used from both the 10Hz active-aura ticker and the CD Ready Glow update,
-- both of which loop over all 4 viewers frequently.
local _viewerFrameCache = {}
local function GetViewerFrame(vi)
    local f = _viewerFrameCache[vi]
    if not f then
        f = _G[VIEWER_NAMES[vi]]
        if f then _viewerFrameCache[vi] = f end
    end
    return f
end

local VIEWER_TO_BAR = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}

-- Master guard: suspend ALL hook logic while Blizzard CDM settings is open.
-- Any interaction with frames during settings editing causes taint.
local function IsCDMSettingsOpen()
    return CooldownViewerSettings and CooldownViewerSettings:IsShown()
end

-------------------------------------------------------------------------------
--  Spell ID Resolution
-------------------------------------------------------------------------------
local function ResolveFrameSpellID(frame)
    local cdID = frame.cooldownID
    if not cdID and frame.cooldownInfo then
        cdID = frame.cooldownInfo.cooldownID
    end
    if not cdID or not C_CooldownViewer then return nil, nil end

    local fc = _ecmeFC[frame]
    if fc and fc.resolvedSid and fc.cachedCdID == cdID then
        local baseSID = fc.baseSpellID
        if baseSID and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local liveOvr = C_SpellBook.FindSpellOverrideByID(baseSID)
            if liveOvr and liveOvr ~= 0 and liveOvr ~= fc.overrideSid then
                fc.overrideSid = liveOvr
                fc.resolvedSid = liveOvr
            end
        end
        return fc.resolvedSid, fc.baseSpellID
    end

    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    if not info then return nil, nil end
    local displaySID = ResolveInfoSpellID(info)
    if not displaySID or displaySID <= 0 then return nil, nil end
    local baseSID = info.spellID
    if not baseSID or baseSID <= 0 then baseSID = displaySID end

    if not fc then fc = {}; _ecmeFC[frame] = fc end
    fc.resolvedSid = displaySID
    fc.baseSpellID = baseSID
    fc.overrideSid = info.overrideSpellID
    fc.cachedCdID  = cdID
    fc.cachedAuraInstID = frame.auraInstanceID

    if info.linkedSpellIDs and #info.linkedSpellIDs > 0 then
        fc.linkedSpellIDs = info.linkedSpellIDs
    else
        fc.linkedSpellIDs = nil
    end

    return displaySID, baseSID
end
ns.ResolveFrameSpellID = ResolveFrameSpellID

-- Resolve the per-spell settings table for a CDM frame. Settings are keyed by
-- the spell the user added (assignedSpells / spellSettings[id]). The live frame
-- can report SEVERAL different ids for the same logical spell, and which one
-- matches the stored key varies by talent state:
--   * sid2          -- ResolveFrameSpellID's cooldownInfo base. For some
--                      Hero-talent slots this is an UNRELATED spell (observed:
--                      a Hellcaller Wither slot whose cooldownInfo base is
--                      Immolate 348 while the displayed spell is Wither 445468).
--   * canon         -- GetCanonicalSpellIDForFrame: the displayed/castable id
--                      the picker keys settings by (GetSpellID-first, clean-read
--                      cached so it survives the active/secret state).
--   * resolvedSid   -- cached override/display id.
--   * baseSpellID   -- cached base id.
-- Match a stored key against the frame's FULL identity set, by direct hit,
-- linkedSpellIDs, and override resolution in BOTH directions (the assigned
-- spell may be the base whose active override is one of the identity ids -- e.g.
-- assigned Corruption 172, frame shows Wither 445468 = FindSpellOverrideByID(172)
-- -- or an identity id may be the base whose override is the assigned spell).
local function ResolveSpellSettings(frame, sid2, sd2, barKey)
    if not sid2 then return nil end
    -- Bar identity: explicit barKey wins (nil-frame callers like the preset
    -- gain-sound path), else the frame's decorated context.
    local fc0 = frame and _ecmeFC[frame]
    local bk = barKey or (fc0 and fc0.barKey)
    -- Bar tiers: barSettings ("Apply to Bar", per spec) chained to the
    -- profile-level bd.barSpellSettings ("Apply to Bar (All Specs)"). nil when
    -- neither exists -- the common case costs two table lookups.
    local tier = ns.GetBarTierSettings and ns.GetBarTierSettings(sd2, bk)
    -- HOSTED-BUFF frame detection: a real buff frame (or its inactive
    -- placeholder) rendered on a CD/util bar. FRAME-based, not flag-based --
    -- the same spellID can ALSO be this bar's cooldown entry, and that icon
    -- must keep the normal CD-family resolution. A buff frame only reaches a
    -- non-buff bar through an explicit host, so the frame identity is exact.
    -- Cheap: sd2.hostedBuffSpellIDs is nil on bars with no host.
    local hostedFrame = false
    if frame and bk and sd2 and sd2.hostedBuffSpellIDs then
        local fdH = ns._hookFrameData and ns._hookFrameData[frame]
        if (fdH and fdH._isBuffViewerFrame) or frame._isPlaceholderFrame then
            local bdH = ns.barDataByKey and ns.barDataByKey[bk]
            if bdH and bdH.barType ~= "buffs" and bdH.barType ~= "custom_buff" then
                hostedFrame = true
            end
        end
    end
    -- HOSTED BUFFS are fully removed from the Apply-to-Bar tier system: a buff on a
    -- CD/util bar must never inherit that bar's applied (cd/util) values -- notably
    -- for keys shared between families (Duration Text, Border). Resolve ONLY its own
    -- per-spell entry. Nil-frame callers fall back to the flag test (they have no
    -- frame identity, and a nil-frame lookup for a hosted id is always the buff).
    if tier and (hostedFrame
       or (not frame and sd2 and sd2.hostedBuffSpellIDs and sd2.hostedBuffSpellIDs[sid2])) then
        tier = nil
    end
    -- Per-spell entries live in the spec's FAMILY store (they travel with the
    -- spell across bars), not on the bar. A hosted buff reads the BUFF store --
    -- the same entry it had on the buffs bar -- keyed off the FRAME, so a
    -- cooldown icon of the same spellID on this bar keeps the CD store.
    local settings = bk and ns.GetSpellSettingsStore
        and ns.GetSpellSettingsStore(hostedFrame and "buffs" or bk)
    if not settings or next(settings) == nil then return tier end

    local ChainSettings = ns.ChainSettings

    -- Per-cooldownID buff override: two buff-viewer slots can share one
    -- canonical spellID (Diabolist Demonic Art vs Diabolic Ritual) but be
    -- configured independently under a "c"..cooldownID key. Gated so the hot
    -- path is untouched for every store WITHOUT such a key (BuffFamHasCdKey is
    -- a cheap store-identity-cached bool), and scoped to buff-viewer frames so
    -- no cooldown/utility icon ever pays the string build.
    if frame then
        local fdC = ns._hookFrameData and ns._hookFrameData[frame]
        -- Buff-viewer frames AND their inactive-buff placeholders (Always Show /
        -- Keep in Same Place) both carry the viewer cooldownID and must resolve
        -- the same per-slot entry, else a collided slot's styling would revert
        -- whenever the placeholder shows. type(cdID) == "number" still excludes
        -- preset placeholders, which nil the cooldownID.
        if (fdC and fdC._isBuffViewerFrame) or frame._isPlaceholderFrame then
            local cdID = frame.cooldownID
            if type(cdID) == "number" and ns.BuffFamHasCdKey and ns.BuffFamHasCdKey(settings) then
                local cd = settings["c" .. cdID]
                if cd then ChainSettings(cd, tier); return cd end
            end
        end
    end

    -- Fast path: direct hit on the primary id (the common, non-override case).
    -- Returns before building the identity set / addId closure below, so the hot
    -- SetSwipeColor path stays allocation-free for spells without an override.
    -- The chain re-assert is self-healing: every resolve re-points the entry's
    -- __index at the CURRENT bar's tier, so moves / spec swaps / profile swaps
    -- never leave a stale link (metatables are not serialized; this also
    -- restores them after a fresh login).
    local direct = settings[sid2]
    if direct then ChainSettings(direct, tier); return direct end

    local fc2 = fc0

    -- Build the frame's identity-id set (deduped).
    local ids = { sid2 }
    local function addId(id)
        if not id or id <= 0 then return end
        for i = 1, #ids do if ids[i] == id then return end end
        ids[#ids + 1] = id
    end
    local canon2 = frame and ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(frame)
    if canon2 then addId(canon2) end
    if fc2 then
        addId(fc2.resolvedSid)
        addId(fc2.baseSpellID)
    end
    -- Talent "proc into a second ability" forms (e.g. Demon Hunter Reap 1226019 /
    -- 1225826) share a GetBaseSpell base (344862) with the spell the user actually
    -- configured -- but that base is NOT the cooldownInfo base (which for these is
    -- the override id itself), and FindSpellOverrideByID is unreliable because the
    -- LIVE override may differ from the displayed form. GetBaseSpell of the frame's
    -- ids is the stable bridge, so a setting stored under the base form resolves on
    -- the proc'd/override frame.
    if C_Spell and C_Spell.GetBaseSpell then
        addId(C_Spell.GetBaseSpell(sid2))
        if canon2 then addId(C_Spell.GetBaseSpell(canon2)) end
    end

    -- 1. Direct hit on any identity id.
    for i = 1, #ids do
        local s = settings[ids[i]]
        if s then ChainSettings(s, tier); return s end
    end

    -- 2. linkedSpellIDs reported by the cooldown info.
    if fc2 and fc2.linkedSpellIDs then
        for _, lid in ipairs(fc2.linkedSpellIDs) do
            local s = settings[lid]
            if s then ChainSettings(s, tier); return s end
        end
    end

    -- 3. Override resolution across assignedSpells, both directions, against the
    --    full identity set.
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    if FindOvr and sd2 and sd2.assignedSpells then
        local idOvr = {}
        for i = 1, #ids do idOvr[i] = FindOvr(ids[i]) end
        for _, asid in ipairs(sd2.assignedSpells) do
            if asid and asid > 0 and settings[asid] then
                local asidOvr = FindOvr(asid)
                for i = 1, #ids do
                    if asidOvr == ids[i] or idOvr[i] == asid then
                        local s = settings[asid]
                        ChainSettings(s, tier)
                        return s
                    end
                end
            end
        end
    end

    -- No per-spell entry anywhere in the identity set: the bar tiers (if any)
    -- are the effective settings.
    return tier
end
ns.ResolveSpellSettings = ResolveSpellSettings

-- Bar-scoped scan: true when any assigned entry on this CD/utility bar
-- resolves to a Shift Icons cooldown-state effect. Frame-less and cheap
-- (one pass over assignedSpells); called at reanchor time and from the
-- options disabled-state, never per frame per update. Advisory only at
-- runtime: Pass B additionally walks the live frame list (spillover frames
-- and alias-keyed settings are invisible to a frame-less scan).
function ns.CdmBarHasShiftCdState(barKey)
    local sd = ns.GetBarSpellData(barKey)
    local list = sd and sd.assignedSpells
    if not list then return false end
    for _, sid in ipairs(list) do
        if sid and sid ~= 0 then
            local eff
            local hSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid)
            if hSid then
                -- Hosted buff: buff-family own entry only (hosted frames
                -- never inherit this bar's tier).
                local store = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs")
                local ssB = store and store[hSid]
                eff = ssB and ssB.cdStateEffect
            else
                if sid > 0 then
                    local ss = ResolveSpellSettings(nil, sid, sd, barKey)
                    eff = ss and ss.cdStateEffect
                end
                if eff ~= "hiddenOnCDShift" and eff ~= "hiddenReadyShift"
                   and ns.GetEffectiveCustomActiveState then
                    local cas = ns.GetEffectiveCustomActiveState(sid)
                    if cas and cas.cdStateEffect then eff = cas.cdStateEffect end
                end
            end
            if eff == "hiddenOnCDShift" or eff == "hiddenReadyShift" then
                return true
            end
        end
    end
    return false
end

-- Options-side accessor: the overflow layout bar a frame is diverted to this
-- session (nil when not diverted). The fc table is file-local.
function ns.CdmFrameOverflowBar(frame)
    local fc = frame and _ecmeFC[frame]
    return fc and fc._overflowLayoutBar or nil
end

-- Apply the per-spell active-state OVERLAYS (glow + border) for a given active
-- state. This is the context-independent slice of the SetSwipeColor active block:
-- it touches only OUR own overlays (glowOverlay, borderFrame), never Blizzard's
-- Cooldown swipe, so it is safe to call from the swipe hook OR from the isolated
-- Fake-Active engine's own ticker. Idempotent via fd._activeGlowOn /
-- fd._activeBorderOn, so the two drivers cooperate instead of fighting.
function ns.ApplyActiveOverlays(frame, fd, ss, isActive, bd)
    if not fd then return end

    -- Active glow (per-spell)
    local hasGlow = ss and ss.activeGlow and ss.activeGlow > 0
    if isActive and hasGlow then
        if fd.glowOverlay then
            -- Unified glow color takes priority
            local gr, gg, gb = ns.ResolveGlowColor(ss)
            if not gr then
                if ss.activeGlowClassColor then
                    local _, ct = UnitClass("player")
                    if ct then
                        local cc = RAID_CLASS_COLORS[ct]
                        if cc then gr, gg, gb = cc.r, cc.g, cc.b end
                    end
                elseif ss.activeGlowR ~= nil then
                    gr, gg, gb = ss.activeGlowR, ss.activeGlowG or 0.85, ss.activeGlowB or 0
                end
            end
            -- (Re)start on first activation OR when the style/colour changed, so a
            -- live colour edit takes effect. A steady active window with unchanged
            -- settings does NOT restart (which would flicker the glow each tick).
            if not fd._activeGlowOn or fd._activeGlowStyle ~= ss.activeGlow
               or fd._activeGlowR ~= gr or fd._activeGlowG ~= gg or fd._activeGlowB ~= gb then
                ns.StartNativeGlow(fd.glowOverlay, ss.activeGlow, gr, gg, gb)
                fd._activeGlowOn = true
                fd._activeGlowStyle = ss.activeGlow
                fd._activeGlowR, fd._activeGlowG, fd._activeGlowB = gr, gg, gb
            end
        end
    elseif fd._activeGlowOn then
        if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
        fd._activeGlowOn = false
    end

    -- Active border color (per-spell). Recolor the icon border while active;
    -- restore the configured color on falloff. A SQUARE border goes through
    -- SetBorderStyleColor (handles solid + textured, no-ops on a hidden border).
    -- A CUSTOM SHAPE draws its ring on a separate shapeBorder texture that
    -- SetBorderStyleColor never touches, so recolor that directly and save/restore
    -- its configured vertex color. (For the fake-active overlay, frame is the
    -- overlay frame whose FC is seeded with the underlying shapeBorder, so the
    -- same lookup hits the real, raised ring.)
    local ifc = ns._ecmeFC and ns._ecmeFC[frame]
    local shapeBorder = ifc and ifc.shapeApplied and ifc.shapeBorder
    if isActive and ss and ss.activeBorderEnabled then
        local abR = ss.activeBorderR or 1
        local abG = ss.activeBorderG or 0.776
        local abB = ss.activeBorderB or 0.376
        local abA = ss.activeBorderA or 1
        if shapeBorder then
            if not fd._sbColorSaved then
                fd._sbR, fd._sbG, fd._sbB, fd._sbA = shapeBorder:GetVertexColor()
                fd._sbColorSaved = true
            end
            shapeBorder:SetVertexColor(abR, abG, abB, abA)
        elseif fd.borderFrame and EllesmereUI.SetBorderStyleColor then
            EllesmereUI.SetBorderStyleColor(fd.borderFrame, abR, abG, abB, abA)
        end
        fd._activeBorderOn = true
    elseif fd._activeBorderOn then
        if shapeBorder and fd._sbColorSaved then
            shapeBorder:SetVertexColor(fd._sbR, fd._sbG, fd._sbB, fd._sbA)
            fd._sbColorSaved = false
        elseif fd.borderFrame and EllesmereUI.SetBorderStyleColor then
            EllesmereUI.SetBorderStyleColor(fd.borderFrame,
                (bd and bd.borderR) or 0, (bd and bd.borderG) or 0,
                (bd and bd.borderB) or 0, (bd and bd.borderA) or 1)
        end
        fd._activeBorderOn = false
    end
end

-------------------------------------------------------------------------------
--  Spell Routing State
--
--  _divertedSpellsBuff / _divertedSpellsCD:
--                   variant-keyed maps of every spell ID claimed by a bar.
--                   Split by viewer family so the same spellID (e.g. Divine
--                   Shield 642, which exists as both a cooldown in the
--                   essential viewer AND a buff in the buff viewer) can
--                   route independently per family. Without the split, a
--                   later pass writing the same spellID for a different
--                   family would clobber the earlier pass and the frame
--                   would fall through to its viewer default.
--                   Built once by RebuildSpellRouteMap from the bar list.
--                   Queried per-frame at reanchor time by ResolveCDIDToBar
--                   using the viewer's family.
--
--  _cdidRouteMap:   memoization cache, cooldownID -> barKey. Lazily
--                   populated by ResolveCDIDToBar on first lookup. Wiped
--                   by RebuildSpellRouteMap. Safe as a single map because
--                   a given cooldownID only exists in ONE viewer, so the
--                   buff-vs-CD family is already implicit in the key.
-------------------------------------------------------------------------------
local _cdidRouteMap = {}

local _divertedSpellsBuff = {}
local _divertedSpellsCD   = {}
-- cooldownID-level buff diversions: a collided buff (two viewer slots sharing
-- one canonical spellID, e.g. Diabolist Demonic Art vs Diabolic Ritual) is
-- tracked on a custom bar by its cooldownID (a cd-claim marker in
-- assignedSpells, see ns.CdClaimMarker), routing exactly one slot there.
-- Checked by ResolveCDIDToBar BEFORE the sid-level map so the cd-level claim
-- outranks a whole-pair sid claim.
local _divertedBuffCdIDs  = {}
ns._divertedSpellsBuff = _divertedSpellsBuff
ns._divertedSpellsCD   = _divertedSpellsCD

-- Sentinel: set true at the end of RebuildSpellRouteMap on a successful
-- build. CollectAndReanchor's safety net tests this (NOT _cdidRouteMap,
-- which is a lazy cache and intentionally empty post-build, NOT the
-- diversion maps, which can legitimately be empty for users with no
-- diversions).
local _routeMapBuilt = false

--- Rebuild the diversion set. The cdID->bar route is computed lazily at
--- reanchor time via ResolveCDIDToBar (below) which uses the FRAME's actual
--- viewerFrame as the source-of-truth default, not the static category API.
---
--- Why frame-driven default routing instead of category API:
---   Blizzard's GetCooldownViewerCategorySet returns the STATIC category
---   for a cooldownID. But Blizzard's actual CDM viewer can show a spell
---   in a different viewer than its static category (e.g. user dragged
---   Lay on Hands from Essential to Utility in Edit Mode, OR a per-spec
---   layout reassigns it). The viewer the FRAME is in is the user-visible
---   ground truth.
---
--- Default bars contribute to the diversion set: putting a spellID into
--- cooldowns.assignedSpells or utility.assignedSpells is how the user says
--- "this spell goes on this default bar regardless of viewer category."
--- This enables cross-routing between default bars (e.g. Lay on Hands in
--- Essential viewer routed to utility bar via utility.assignedSpells).
---
--- Priority for collisions (rare under the 1-spell-per-bar invariant):
---   ghost bars (lowest) -> custom buff -> custom CD/util -> default bars
---   (highest). Later passes overwrite earlier via preserveExisting=false.
---
--- Family split: each bar writes to either _divertedSpellsBuff (buff
--- family) or _divertedSpellsCD (non-buff family). This prevents a
--- buff-family bar and a CD-family bar from clobbering each other's
--- diversion entries when they both claim the same spellID (e.g. Divine
--- Shield, which has a cooldown frame AND a buff frame under the same
--- spellID 642).
function ns.RebuildSpellRouteMap()
    wipe(_cdidRouteMap)
    wipe(_divertedSpellsBuff)
    wipe(_divertedSpellsCD)
    wipe(_divertedBuffCdIDs)
    _routeMapBuilt = false

    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    local SVV = ns.StoreVariantValue
    if not SVV then return end

    local IsBuffFamily = ns.IsBarBuffFamily

    local function CollectDiversionsFor(bd)
        local sd = ns.GetBarSpellData(bd.key)
        if not sd or not sd.assignedSpells then return end
        local targetMap = IsBuffFamily and IsBuffFamily(bd) and _divertedSpellsBuff or _divertedSpellsCD
        for _, sid in ipairs(sd.assignedSpells) do
            if type(sid) == "number" and sid > 0 then
                SVV(targetMap, sid, bd.key, false)
            end
        end
    end

    -- Pass 1: custom buff bars (extra buff bars) + custom_buff (TBB) bars.
    -- TBB bars compete for the same buff icon spells, so their diversions
    -- must land in _divertedSpellsBuff even though IsBarBuffFamily returns
    -- false for custom_buff. We write directly to _divertedSpellsBuff here.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and ((bd.barType == "buffs" and bd.key ~= "buffs")
                or bd.barType == "custom_buff") then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        SVV(_divertedSpellsBuff, sid, bd.key, false)
                    end
                end
            end
            -- cooldownID-level claims (collided buffs tracked by slot, via
            -- a cd-claim marker in assignedSpells)
            local claims = sd and ns.CollectCdClaimSet(sd)
            if claims then
                for cdID in pairs(claims) do
                    _divertedBuffCdIDs[cdID] = bd.key
                end
            end
        end
    end
    -- Pass 2: default bars (cooldowns/utility/buffs) FIRST among the CD family.
    -- Custom CD/util bars (Pass 3) are processed AFTER and overwrite these, so an
    -- explicit custom-bar placement OUTRANKS the default bar. Without this, a spell
    -- that sits on a custom bar AND also lands in cooldowns.assignedSpells (e.g. a
    -- materialized spillover both-state) would render on the default cooldowns bar
    -- instead of the custom bar the user built for it.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and (bd.key == "cooldowns" or bd.key == "utility" or bd.key == "buffs") then
            CollectDiversionsFor(bd)
        end
    end
    -- Pass 3: custom CD/utility bars -- overwrite the default diversions so a spell
    -- the user deliberately placed on a custom bar wins over the default bar.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.key ~= "cooldowns" and bd.key ~= "utility" and bd.key ~= "buffs"
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff" then
            CollectDiversionsFor(bd)
        end
    end
    -- Pass 3b: HOSTED BUFFS. A buff placed on a CD/utility bar
    -- (sd.hostedBuffSpellIDs) must ALSO divert in the BUFF-family map to that
    -- CD/util bar -- a buff frame comes from the BuffIcon viewer, so
    -- ResolveCDIDToBar only reads _divertedSpellsBuff for it. Runs after the
    -- buff-bar passes (1-2) so an explicit host outranks a stray buff-bar copy of
    -- the same spell. (The bar's normal CD diversion in _divertedSpellsCD from
    -- Pass 3 is untouched; these are separate family maps.)
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff" then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.hostedBuffSpellIDs then
                -- Keyed off hostedBuffSpellIDs directly (not assignedSpells): the
                -- CD/util drop pass can transiently strip a buff from assignedSpells
                -- (a buff never appears in the Essential/Utility viewer), but the
                -- diversion must survive that so the buff still renders here. SVV
                -- expands variants so any live talent/override form resolves.
                for sid in pairs(sd.hostedBuffSpellIDs) do
                    if type(sid) == "number" and sid > 0 then
                        SVV(_divertedSpellsBuff, sid, bd.key, false)
                    end
                end
            end
            -- Cd-claimed hosted buffs (collided slots, e.g. Diabolist Demonic
            -- Art vs Diabolic Ritual, hosted via a cd-claim marker instead of
            -- the sid-keyed hostedBuffSpellIDs flag): claim the cooldownID
            -- directly in _divertedBuffCdIDs, same map + same priority the
            -- buff-family-bar cd-claims (Pass 1) use. ResolveCDIDToBar checks
            -- this map before any sid-level map, so it works regardless of
            -- target bar type.
            local claims = sd and ns.CollectCdClaimSet(sd)
            if claims then
                for cdID in pairs(claims) do
                    _divertedBuffCdIDs[cdID] = bd.key
                end
            end
        end
    end
    -- Pass 4: ghost bars LAST = HIGHEST priority. A spell the user HID stays
    -- hidden even if it's also on a visible bar (the "both-state"), so a hidden
    -- spell never reappears regardless of how it ended up in two bars. Adding a
    -- spell to a visible bar removes it from the ghost (ns.AddSpellToBar), so this
    -- never hides a spell you deliberately placed.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and bd.isGhostBar then
            CollectDiversionsFor(bd)
        end
    end

    _routeMapBuilt = true
end

--- Lazily resolve a cooldownID to a bar key. Called per-frame at reanchor
--- time. Uses _cdidRouteMap as a memoization cache; on cache miss, computes
--- the route from the per-family diversion map or falls back to
--- viewerDefaultBar (the bar that owns the viewer the frame came from).
--- Caches the result.
---
--- viewerDefaultBar is "cooldowns" / "utility" / "buffs" depending on which
--- viewer pool the frame was enumerated from -- this is the user-visible
--- ground truth, not the static category API. It also tells us which
--- family to consult (buffs -> _divertedSpellsBuff, otherwise CD).

-- Plain readable positive number, without ever inspecting a secret (type()
-- and issecretvalue read only the tags). Mirrors _IsUsableSID in
-- EllesmereUICdmSpellPicker.lua; used below to tell a real "no diversion"
-- answer apart from a blind lookup whose every id field was secret.
local function CdidIDReadable(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0
end

local function ResolveCDIDToBar(cdID, viewerDefaultBar)
    if not cdID then return viewerDefaultBar end
    local cached = _cdidRouteMap[cdID]
    if cached then return cached end

    -- cooldownID-level claim first (collided buffs tracked by slot). Needs no
    -- cooldownInfo read, so it also works while every sid field is secret.
    if viewerDefaultBar == "buffs" then
        local cdRoute = _divertedBuffCdIDs[cdID]
        if cdRoute then
            _cdidRouteMap[cdID] = cdRoute
            return cdRoute
        end
    end

    local RVV = ns.ResolveVariantValue
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not RVV or not gci then
        _cdidRouteMap[cdID] = viewerDefaultBar
        return viewerDefaultBar
    end

    local divertMap = (viewerDefaultBar == "buffs") and _divertedSpellsBuff or _divertedSpellsCD

    local info = gci(cdID)
    if not info then
        -- Cooldown info not ready yet (transient, e.g. during login / spec
        -- swaps). Return the spillover fallback WITHOUT writing the cache:
        -- _cdidRouteMap is only wiped by RebuildSpellRouteMap, so caching the
        -- fallback here would pin a ghosted/custom spell to its default bar
        -- until the next rebuild. Leaving it uncached lets a later pass (once
        -- info is ready) resolve the real bar.
        return viewerDefaultBar
    end
    local routedBar = nil
    do
        -- No raw `> 0` / `~=` comparisons on info.spellID/overrideSpellID here:
        -- on an active CDM viewer frame these can be secret numbers (per
        -- EllesmereUICdmSpellPicker.lua's _IsUsableSID comment), and comparing
        -- a secret value directly taints execution. RVV (ResolveVariantValue)
        -- already gates its input through _IsUsableSID internally, so just
        -- feed it the raw fields and let it reject anything unusable.
        routedBar = RVV(divertMap, info.spellID)
        if not routedBar then
            routedBar = RVV(divertMap, info.overrideSpellID)
        end
        if not routedBar and info.linkedSpellIDs then
            for _, lid in ipairs(info.linkedSpellIDs) do
                routedBar = RVV(divertMap, lid)
                if routedBar then break end
            end
        end
    end

    if not routedBar then
        -- No diversion found. Only trust (and cache) that answer if at least
        -- one id field was actually readable: with every id secret (active
        -- viewer frame in combat) the lookup above was blind, and caching the
        -- fallback would pin the wrong bar until the next RebuildSpellRouteMap
        -- -- the same reasoning as the uncached info-not-ready return above.
        local sawReadable = CdidIDReadable(info.spellID) or CdidIDReadable(info.overrideSpellID)
        if not sawReadable and info.linkedSpellIDs then
            for _, lid in ipairs(info.linkedSpellIDs) do
                if CdidIDReadable(lid) then sawReadable = true; break end
            end
        end
        if not sawReadable then
            return viewerDefaultBar
        end
    end

    routedBar = routedBar or viewerDefaultBar
    _cdidRouteMap[cdID] = routedBar
    return routedBar
end
ns.ResolveCDIDToBar = ResolveCDIDToBar
ns._cdidRouteMap = _cdidRouteMap

-------------------------------------------------------------------------------
--  Active aura cache (consumed by bar glow overlays)
--
--  Maintained by the 0.1s buff ticker, NOT here. The ticker walks viewer
--  pools cheaply and writes spellID->true for any frame whose Blizzard-set
--  wasSetFromAura/auraInstanceID indicates an active aura. Bar glows read
--  via ns._tickBlizzActiveCache.
-------------------------------------------------------------------------------
local _activeCache = {}
ns._tickBlizzActiveCache = _activeCache

-------------------------------------------------------------------------------
--  IsFrameIncluded
--  Include if shown OR has cooldownInfo (catches transitional frames).
-------------------------------------------------------------------------------
local function IsFrameIncluded(frame)
    if not frame then return false end
    return frame:IsShown() or (frame.cooldownInfo ~= nil)
end

-------------------------------------------------------------------------------
--  HideBlizzardDecorations
--  Strip Blizzard visual chrome from a CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function HideBlizzardDecorations(frame)
    local fc = FC(frame)
    if fc.blizzHidden then return end
    fc.blizzHidden = true

    local function alphaZero(child)
        if child then child:SetAlpha(0) end
    end
    alphaZero(frame.Border)
    if frame.SpellActivationAlert then
        frame.SpellActivationAlert:SetAlpha(0)
        frame.SpellActivationAlert:Hide()
    end
    alphaZero(frame.Shadow)
    alphaZero(frame.IconShadow)
    alphaZero(frame.DebuffBorder)
    alphaZero(frame.CooldownFlash)

    local iconWidget = frame.Icon
    local regions = { frame:GetRegions() }
    for ri = 1, #regions do
        local rgn = regions[ri]
        if rgn and rgn.IsObjectType and rgn:IsObjectType("MaskTexture") then
            pcall(function() rgn:SetTexture("Interface\\Buttons\\WHITE8X8") end)
        end
    end
    if frame.Cooldown then
        local cdRegions = { frame.Cooldown:GetRegions() }
        for ri = 1, #cdRegions do
            local rgn = cdRegions[ri]
            if rgn and rgn.IsObjectType and rgn:IsObjectType("MaskTexture") then
                pcall(function() rgn:SetTexture("Interface\\Buttons\\WHITE8X8") end)
            end
        end
    end

    local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
    local OVERLAY_FILE  = 6707800
    for ri = 1, #regions do
        local rgn = regions[ri]
        if rgn and rgn ~= iconWidget and rgn.IsObjectType and rgn:IsObjectType("Texture") then
            local atlas = rgn.GetAtlas and rgn:GetAtlas()
            local tex = rgn.GetTexture and rgn:GetTexture()
            if atlas == OVERLAY_ATLAS or tex == OVERLAY_FILE then
                rgn:SetAlpha(0)
                rgn:Hide()
            end
        end
    end

    -- Do NOT call SetHideCountdownNumbers. Use SetCountdownFont
    -- to control countdown text display instead of hiding numbers entirely.
end

-------------------------------------------------------------------------------
--  Charge cooldown style
--  BASELINE: every charge spell draws the cooldown edge (spark), mirroring the
--  action bars edge -- it follows the icon shape's square/circular path at the
--  shape's scale and is masked by the existing CDM shape system. Always on for
--  charge spells, no setting.
--  PER-SPELL: the "Hide Swipe (Charges)" toggle additionally hides the radial
--  swipe so a charge spell shows the edge only. Resolved only when in use
--  (ns._cdmAnyChargeStyle) so the swipe lookup costs ~0 for everyone else.
-------------------------------------------------------------------------------
local CDM_EDGE_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\edge.png"

-- Resolve the per-spell settings table for a CDM frame. Thin wrapper: looks up
-- the frame's spell/bar identity, then defers to ResolveSpellSettings -- the same
-- Hero-talent-aware resolver the SetSwipeColor / cdState / desat hooks use -- so
-- the charge "Hide Swipe" path resolves override spells identically.
function ns._ResolveCdmSS(frame)
    local fc2 = _ecmeFC[frame]
    local sid2 = fc2 and fc2.spellID
    local bk2 = fc2 and fc2.barKey
    if not sid2 or not bk2 then return nil end
    return ResolveSpellSettings(frame, sid2, ns.GetBarSpellData and ns.GetBarSpellData(bk2))
end

-- Draw the cooldown edge on a charge frame (baseline). The shape system already
-- owns the mask + circular-edge flag for custom shapes; we add the texture, gold
-- color, per-shape scale (square default), and the draw flag.
local function ApplyCdmEdge(cd, bk2)
    if not cd then return end
    local bd = barDataByKey and barDataByKey[bk2]
    local shape = (bd and bd.iconShape) or "none"
    -- SetEdgeScale is a frame-relative multiplier, so the edge tracks icon size
    -- automatically. Plain (non-shaped) icons use the action bars' baseline edge
    -- size; custom shapes use the per-shape scale (same values action bars use).
    local scale
    if shape == "none" or shape == "cropped" then
        scale = 2.1
    else
        scale = (ns.CDM_SHAPE_EDGE_SCALES and ns.CDM_SHAPE_EDGE_SCALES[shape]) or 0.75
    end
    if cd.SetEdgeTexture then cd:SetEdgeTexture(CDM_EDGE_TEXTURE) end
    if cd.SetEdgeColor then cd:SetEdgeColor(0.973, 0.839, 0.604, 1) end
    if cd.SetEdgeScale then cd:SetEdgeScale(scale) end
    if cd.SetDrawEdge then cd:SetDrawEdge(true) end
end

-- Live active-state read from Blizzard's swipe color (mirrors the SetSwipeColor
-- hook; fd._wasActive is stale on falloffs). Returns true while the spell is in
-- its active (buff-up) state. Secret-safe: a secret red channel reads as not
-- active. Used so charge "Hide Swipe" never hides the active-state colored swipe.
local function CdmFrameIsActive(frame)
    local swipeColor = frame and frame.cooldownSwipeColor
    if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
        local r = swipeColor:GetRGBA()
        if r and type(r) == "number" and not issecretvalue(r) then
            return r ~= 0
        end
    end
    return false
end

-- Apply charge cooldown style. Returns true for charge spells (caller then skips
-- its own swipe forcing). BASELINE edge is drawn for every charge spell; the
-- swipe is hidden only when the per-spell Hide Swipe toggle is set (resolved
-- only while ns._cdmAnyChargeStyle is on). Caller MUST guard with
-- fd._isProcessingOverride so the SetDrawSwipe sibling hook does not recurse.
-- Secret-safe: HasVisualDataSource_Charges is a clean bool, the ss flag is ours.
local function ApplyCdmChargeStyle(frame, cd)
    if type(frame.HasVisualDataSource_Charges) ~= "function"
       or not frame:HasVisualDataSource_Charges() then
        return false
    end
    local fc2 = _ecmeFC[frame]
    ApplyCdmEdge(cd, fc2 and fc2.barKey)
    local hide = false
    if ns._cdmAnyChargeStyle then
        local ss2 = ns._ResolveCdmSS(frame)
        if ss2 then
            -- Hide Recharge Edge (per-spell): drop the recharge edge line that
            -- ApplyCdmEdge just drew. Secret-safe: ss flag is ours, SetDrawEdge
            -- takes no secret.
            if ss2.hideRechargeEdge and cd.SetDrawEdge then
                cd:SetDrawEdge(false)
            end
            if ss2.chargeHideSwipe then
                -- Hide only the recharge swipe. The active-state overlay IS the
                -- (colored) swipe, so keep it drawn while the active state is
                -- showing (active AND not "hide active state").
                local showActive = ss2.activeSwipeMode ~= "none" and CdmFrameIsActive(frame)
                hide = not showActive
            end
        end
    end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(not hide) end
    return true
end

-- Immediately re-assert the charge style (Hide Recharge Edge + Hide Swipe) on one
-- icon, instead of waiting for Blizzard's next cooldown re-push to fire the
-- reactive SetDrawEdge / SetDrawSwipe hooks. Called from RefreshCDMIconAppearance
-- so toggling Hide Recharge Edge / Hide Swipe -- per-icon OR via Apply to Bar --
-- updates a CURRENTLY recharging charge spell right away rather than only on its
-- next recharge (the "it didn't apply to every icon" report). No-op for non-charge
-- frames (ApplyCdmChargeStyle self-skips) and reentry-guarded so the sibling hooks
-- do not recurse.
function ns.ReapplyChargeStyle(frame)
    local fd = frame and hookFrameData[frame]
    local cd = fd and fd.cooldown
    if not cd or fd._isProcessingOverride then return end
    fd._isProcessingOverride = true
    ApplyCdmChargeStyle(frame, cd)
    fd._isProcessingOverride = false
end

-- Max Stacks Glow (per-spell): glow a charge spell when it is at max charges.
-- 1:1 with Active State Glow but on its own overlay (so the two never fight) and
-- driven by charge state instead of the active swipe. ss2.maxStacksGlow is the
-- glow STYLE; the color is the unified ss.glowColor (same as every other glow).
-- atMax is a CLEAN bool the caller derives from C_Spell.GetSpellCharges().isActive
-- (recharge-active flag, false only at max) -- never the secret currentCharges.
local function ApplyMaxStacksGlow(frame, fd, ss2, atMax)
    if not fd then return end
    local has = ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0
    if has and atMax then
        if not fd._maxStacksGlowOn then
            -- Lazy-create the overlay only when the glow is first needed, so an
            -- unused feature adds no frame. Its own overlay means it never fights
            -- the active glow (StartNativeGlow stops glows on the passed overlay only).
            local mo = fd.maxStacksGlowOverlay
            if not mo and frame then
                mo = CreateFrame("Frame", nil, frame)
                mo:SetAllPoints(frame)
                mo:SetAlpha(0)
                mo:EnableMouse(false)
                fd.maxStacksGlowOverlay = mo
            end
            if mo then
                if frame then mo:SetFrameLevel(frame:GetFrameLevel() + 16) end
                local gr, gg, gb = ns.ResolveGlowColor(ss2)
                ns.StartNativeGlow(mo, ss2.maxStacksGlow, gr, gg, gb)
                fd._maxStacksGlowOn = true
            end
        end
    elseif fd._maxStacksGlowOn then
        if fd.maxStacksGlowOverlay then ns.StopNativeGlow(fd.maxStacksGlowOverlay) end
        fd._maxStacksGlowOn = false
    end
end

-- Max Stacks Glow is driven by SPELL_UPDATE_CHARGES, NOT the cooldown-widget hooks:
-- those fire when a charge is SPENT (swipe set) but not when the last charge REFILLS
-- to max (verified live). SPELL_UPDATE_CHARGES fires on BOTH charge transitions and
-- nothing else, so it is far cheaper than SPELL_UPDATE_COOLDOWN (which fires on every
-- GCD); isActive only ever flips together with a charge-count change, so this one
-- event catches both edges. The watch set holds only icons that have the glow enabled,
-- so each event iterates a tiny set, and the frame is created only once the feature is
-- turned on (0 cost otherwise).
ns._maxStacksWatch = ns._maxStacksWatch or setmetatable({}, { __mode = "k" })

-- Re-derive at-max from CLEAN charge state and (un)glow. Self-unwatches when the
-- per-icon setting is off or the frame lost its spell, so the set drains itself.
local function EvalMaxStacksFrame(frame, fd)
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not sidw or not bkw then
        ApplyMaxStacksGlow(frame, fd, nil, false)
        ns._maxStacksWatch[frame] = nil
        return
    end
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    if not (ssw and ssw.maxStacksGlow and ssw.maxStacksGlow > 0) then
        ApplyMaxStacksGlow(frame, fd, ssw, false)
        ns._maxStacksWatch[frame] = nil
        return
    end
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    -- atMax derives PURELY from charge data (maxCharges + the recharge isActive
    -- flag), NEVER from HasVisualDataSource_Charges: that returns false whenever the
    -- icon is drawing a GCD swipe instead of the recharge, which would wrongly drop
    -- the glow every time a charge tops off during the global cooldown. maxCharges>1
    -- is itself the charge-spell test (nil / 1 for non-charge spells -> atMax false).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local atMax = ci ~= nil and (ci.maxCharges or 0) > 1 and not ci.isActive
    ApplyMaxStacksGlow(frame, fd, ssw, atMax)
end

local function WatchMaxStacksFrame(frame, fd)
    ns._maxStacksWatch[frame] = fd
    if not ns._maxStacksEventFrame then
        local ef = CreateFrame("Frame")
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for f, d in pairs(ns._maxStacksWatch) do
                EvalMaxStacksFrame(f, d)
            end
        end)
        ns._maxStacksEventFrame = ef
    end
end

-- Called from RefreshCDMIconAppearance (login + settings changes) so an at-max
-- charge spell -- which never fires the swipe hook, having no swipe -- still gets
-- watched. Early-outs on non-charge icons (one cheap capability check, no settings
-- lookup), so the only icons that cost anything are charge spells. Once watched,
-- the single SPELL_UPDATE_CHARGES frame keeps them current. Also self-cleans an
-- icon whose setting was just turned off.
function ns.WatchMaxStacksIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then return end
    -- Charge-spell test via static charge data (stable). HasVisualDataSource_Charges
    -- flips false during a GCD swipe and would wrongly skip the spell here too.
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local isCharge = ci ~= nil and (ci.maxCharges or 0) > 1
    local ssw = isCharge and ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw)) or nil
    if ssw and ssw.maxStacksGlow and ssw.maxStacksGlow > 0 then
        ns._cdmAnyMaxStacksGlow = true
        WatchMaxStacksFrame(frame, fd)
        EvalMaxStacksFrame(frame, fd)
    elseif ns._maxStacksWatch[frame] then
        ns._maxStacksWatch[frame] = nil
        ApplyMaxStacksGlow(frame, fd, nil, false)
    end
end

-------------------------------------------------------------------------------
--  Audio Effect on CD Ready -- per-spell (CD/utility bars only)
--  Plays a sound the moment a spell becomes ready. Edge-detected with an arm flag
--  (armed only while NOT ready, played + disarmed on the ready edge), so it never
--  fires on login (already ready -> never armed), on a GCD ending (a GCD never
--  makes a spell "not ready" here), or per render tick.
--
--  Driven ENTIRELY by the authoritative cooldown/charge events
--  (SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES) via the WatchCdReadySoundIfEnabled
--  set -- NOT by the SetDesaturated visual hook. That hook fires at moments unrelated
--  to the real cooldown (rage/range/GCD repaint) where C_Spell.GetSpellCooldown can
--  report a transient isActive=true / isOnGCD=false GCD race; sampling there
--  false-armed non-charge spells that were never on cooldown (Odyn's Fury etc.),
--  firing at random while another button was spammed. Reading isActive+isOnGCD AT the
--  event (the moment state actually settled) is consistent -- this is exactly how
--  Ayije drives its ready glow. Charge readiness = GetSpellCharges().isActive == false
--  (at max, the clean signal Max Stacks Glow uses); non-charge readiness =
--  not (GetSpellCooldown().isActive and not isOnGCD). No duration/magnitude math
--  (those values are secret in protected instances) -- only the clean bool flags.
-------------------------------------------------------------------------------
ns._cdReadySoundWatch = ns._cdReadySoundWatch or setmetatable({}, { __mode = "k" })

-- Loading-screen / login-settle gate, shared by every CDM notification sound
-- (CD-ready, buff gain/loss, preset buff gain). Zone changes, flights, and login
-- re-render the CDM icons and re-fire aura/charge alerts while the cooldown,
-- charge, and aura APIs briefly report transient states across the boundary --
-- which false-fires the edges on spells/buffs that were mid-cooldown or still
-- present (heard as random sounds when just zoning/flying). Mirrors Ayije, which
-- gates every notification sound behind loginFinished + loadingScreenActive.
-- Cheap: one boolean + one timestamp compare, consulted only on a sound edge
-- (never per tick). Edges that land while suppressed are dropped silently.
do
    local loadingActive = true   -- suppressed until the first PLAYER_ENTERING_WORLD
    local settleUntil = 0
    local SETTLE_SECONDS = 2      -- brief window after a load for re-renders to settle

    function ns._cdmSoundSuppressed()
        return loadingActive or GetTime() < settleUntil
    end

    -- Full CDM rebuilds (spec/talent swaps, settings changes) re-render every
    -- icon while the cooldown/charge APIs are briefly transient, exactly like
    -- a zone boundary -- callers open the same settle window so the re-prime
    -- can't false-arm a batch of ready sounds. Longest window wins.
    function ns._cdmBumpSoundSettle(sec)
        local u = GetTime() + (sec or SETTLE_SECONDS)
        if u > settleUntil then settleUntil = u end
    end

    local gate = CreateFrame("Frame")
    gate:RegisterEvent("LOADING_SCREEN_ENABLED")
    gate:RegisterEvent("LOADING_SCREEN_DISABLED")
    gate:RegisterEvent("PLAYER_ENTERING_WORLD")
    gate:SetScript("OnEvent", function(_, event)
        if event == "LOADING_SCREEN_ENABLED" then
            loadingActive = true
        else
            -- World is up (LOADING_SCREEN_DISABLED / PLAYER_ENTERING_WORLD): clear
            -- the load flag and start a short settle so the post-load icon
            -- re-render can't false-fire the edge.
            loadingActive = false
            settleUntil = GetTime() + SETTLE_SECONDS
        end
    end)
end

-- Diagnostic: /cdmreadydbg toggles a one-line print at each CD-ready sound FIRE
-- (live spellID, name, base id, bar, charge state) so a "fires while spamming"
-- report can be traced to the exact spell and reason. Off by default; the print
-- is gated on the flag so it is zero cost unless toggled on.
ns._cdReadySoundDebug = false
SLASH_CDMREADYDBG1 = "/cdmreadydbg"
SlashCmdList.CDMREADYDBG = function()
    ns._cdReadySoundDebug = not ns._cdReadySoundDebug
    print("|cff0cd29f[CDReady]|r debug " .. (ns._cdReadySoundDebug and "ON" or "OFF"))
end

-- Reject armed->ready spans shorter than this: a real cooldown arms the moment
-- the spell is used, so a sub-GCD-length arm can only be a transient misread
-- (GCD tail / charge race). Costs the sound on real cooldowns under ~1.6s,
-- which CDM tracking barely has.
local CD_READY_MIN_ARM = 1.6

-- Is the spell READY right now? Charge spells: only at MAX charges (recharge not
-- running). Non-charge: not on a real (non-GCD) cooldown. liveSid = resolved override.
local function CdReadyIsReady(liveSid)
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if ci ~= nil and (ci.maxCharges or 0) > 1 then
        return not ci.isActive
    end
    local cd = C_Spell.GetSpellCooldown(liveSid)
    return not (cd and cd.isActive and not cd.isOnGCD)
end

-- Shared evaluator (driven by SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES via the
-- WatchCdReadySoundIfEnabled set). Arms while not ready, plays + disarms on the ready
-- edge. Deferred one frame and re-confirmed so a charge/GCD-tail race that momentarily
-- reads ready can't false-fire. Self-gates zero-cost on the feature flag.
-- primeOnly (the DecorateFrame prime): arm state only, never reaches the play path.
local function EvalCdReadySound(frame, fd, primeOnly)
    if not ns._cdmAnyCdReadySound then return end
    if not fd then return end
    if fd._isProcessingOverride then return end
    local fc2 = _ecmeFC[frame]
    local sid2 = fc2 and fc2.spellID
    local bk2 = fc2 and fc2.barKey
    if not sid2 or not bk2 then return end
    if bk2 == ns.FOCUSKICK_BAR_KEY then return end
    if bk2:sub(1, 7) == "__ghost" then return end
    local ss2 = ResolveSpellSettings(frame, sid2, ns.GetBarSpellData(bk2))
    local key = ss2 and ss2.cdReadySoundKey
    if not key or key == "none" then fd._cdReadyArmed = false; return end
    if ns._cdmSoundSuppressed() then
        -- Loading screen / login / rebuild settle: cooldown reads are transient
        -- across the boundary, so anything armed (or arming) now is suspect --
        -- gate the ARM, not just the fire, and clear stale arms. A spell
        -- genuinely on cooldown re-arms from its ongoing cooldown on the next
        -- SPELL_UPDATE_COOLDOWN after the window, so no real edge is lost.
        fd._cdReadyArmed = false
        return
    end
    local liveSid = sid2
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sid2) or sid2
    end
    if not CdReadyIsReady(liveSid) then
        -- On cooldown (or a charge spell below max): arm.
        if not fd._cdReadyArmed then fd._cdReadyArmedAt = GetTime() end
        fd._cdReadyArmed = true
        fd._cdReadyArmedSid = sid2
    elseif fd._cdReadyArmed and not primeOnly then
        if fd._cdReadyArmedSid ~= sid2 then
            -- Spell on this frame changed since arming (spec/talent swap); stale arm.
            fd._cdReadyArmed = false
            return
        end
        -- Became ready. Confirm one frame later (let the API settle) before playing.
        if not fd._cdReadyPending then
            fd._cdReadyPending = CreateFrame("Frame")
            fd._cdReadyPending:Hide()
            fd._cdReadyPending:SetScript("OnUpdate", function(self)
                self:Hide()
                if not fd._cdReadyArmed then return end
                local fcp = _ecmeFC[frame]
                local sidp = fcp and fcp.spellID
                local bkp = fcp and fcp.barKey
                if not sidp or not bkp then return end
                if fd._cdReadyArmedSid ~= sidp then fd._cdReadyArmed = false; return end
                local ssp = ResolveSpellSettings(frame, sidp, ns.GetBarSpellData(bkp))
                local kp = ssp and ssp.cdReadySoundKey
                if not kp or kp == "none" then fd._cdReadyArmed = false; return end
                local livep = sidp
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    livep = C_SpellBook.FindSpellOverrideByID(sidp) or sidp
                end
                if not CdReadyIsReady(livep) then return end  -- not ready (race) -> stay armed
                if ns._cdmSoundSuppressed() then fd._cdReadyArmed = false; return end  -- a load began mid-defer
                -- Sub-GCD arm span = transient misread, not a real cooldown ending.
                local armedAt = fd._cdReadyArmedAt
                if not armedAt or (GetTime() - armedAt) < CD_READY_MIN_ARM then
                    fd._cdReadyArmed = false
                    return
                end
                fd._cdReadyArmed = false
                if ns._cdReadySoundDebug then
                    local nm = (C_Spell.GetSpellName and C_Spell.GetSpellName(livep)) or "?"
                    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(livep)
                    print(string.format(
                        "|cff0cd29f[CDReady]|r FIRE live=%s '%s' base=%s bar=%s maxCharges=%s chargeRecharging=%s",
                        tostring(livep), tostring(nm), tostring(sidp), tostring(bkp),
                        ci and tostring(ci.maxCharges) or "-",
                        ci and tostring(ci.isActive) or "-"))
                end
                local path = ns.FOCUSKICK_SOUND_PATHS and ns.FOCUSKICK_SOUND_PATHS[kp]
                if path then PlaySoundFile(path, "Master") end
            end)
        end
        fd._cdReadyPending:Show()
    end
end

-- Register a spell that has a CD-ready sound into the event-driven watch set. The
-- set is evaluated on SPELL_UPDATE_COOLDOWN (non-charge CD end) and
-- SPELL_UPDATE_CHARGES (charge refill to max) -- the authoritative moments the state
-- actually settles, so isActive/isOnGCD read consistently (no GCD race). BOTH charge
-- and non-charge spells are watched here; there is no SetDesaturated driver anymore.
-- Called from DecorateFrame for every cd/utility icon.
function ns.WatchCdReadySoundIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then return end
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    if ssw and ssw.cdReadySoundKey and ssw.cdReadySoundKey ~= "none" then
        ns._cdmAnyCdReadySound = true
        ns._cdReadySoundWatch[frame] = fd
        if not ns._cdReadySoundEventFrame then
            local ef = CreateFrame("Frame")
            ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ef:RegisterEvent("SPELL_UPDATE_CHARGES")
            ef:SetScript("OnEvent", function()
                for f, d in pairs(ns._cdReadySoundWatch) do
                    EvalCdReadySound(f, d)
                end
            end)
            ns._cdReadySoundEventFrame = ef
        end
        EvalCdReadySound(frame, fd, true)  -- prime the arm state only; never plays here
    elseif ns._cdReadySoundWatch[frame] then
        ns._cdReadySoundWatch[frame] = nil
    end
end

-------------------------------------------------------------------------------
--  Hide CD Text (Charges) -- per-spell (CD/utility bars only)
--  When a CHARGE spell has at least one usable charge in hand, hide the recharge
--  countdown numbers (the timer ticking toward the NEXT charge). The numbers come
--  back the moment every charge is spent (0 charges == on a real cooldown) so the
--  user still sees the full cooldown countdown when the ability is unavailable.
--
--  "charges > 0" derives from the CLEAN GetSpellCooldown() flags: a charge is in
--  hand whenever the spell is NOT on a real (non-GCD) cooldown, i.e.
--  not (isActive and not isOnGCD). isActive alone is wrong -- it is true during the
--  global cooldown right after a cast even though a charge remains. The charge-spell
--  test uses GetSpellCharges().maxCharges > 1 (stable through the GCD) -- never
--  HasVisualDataSource_Charges, which flips false during a GCD swipe. Neither reads
--  the secret currentCharges.
--
--  Driven by SPELL_UPDATE_CHARGES, same as Max Stacks Glow: that event fires on
--  every charge transition (spend AND refill) and nothing else, so re-evaluation
--  is cheap and catches the topping-off edge the cooldown-widget hooks miss. All
--  gated behind ns._cdmAnyChargeHideCdText so the feature costs ~0 when unused.
-------------------------------------------------------------------------------

-- Returns the effective SetHideCountdownNumbers value for a CDM cooldown widget,
-- layering the per-spell "Hide CD Text (Charges)" toggle on top of the caller's
-- existing value (baseHide = "the numbers would already be hidden by the bar /
-- per-icon showCooldownText setting"). Returns baseHide unchanged for every frame
-- that is not an enabled charge spell, so callers wrap their current value with no
-- behaviour change for anyone not using the feature.
function ns.CdmShouldHideCountdown(frame, baseHide)
    if not ns._cdmAnyChargeHideCdText then return baseHide end
    if baseHide then return true end  -- already hidden by the bar/per-icon setting
    local ss = ns._ResolveCdmSS(frame)
    if not (ss and ss.chargeHideCdText) then return baseHide end
    local fc = _ecmeFC[frame]
    local sid = fc and fc.spellID
    if not sid then return baseHide end
    local liveSid = sid
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sid) or sid
    end
    -- Charge-spell test via static charge data (stable through the GCD).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if not (ci and (ci.maxCharges or 0) > 1) then return baseHide end
    -- "charges > 0"  <=>  NOT on a real (non-GCD) cooldown. A charge spell with a
    -- charge in hand reports GetSpellCooldown().isActive == false, OR true with
    -- isOnGCD during the global cooldown right after a cast (still have a charge);
    -- 0 charges == isActive true AND not on GCD. So gating on isActive alone wrongly
    -- shows the duration through every GCD -- the isOnGCD term is required. Both
    -- flags are clean; the secret currentCharges is never read.
    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(liveSid)
    if not cdInfo then return baseHide end
    local onRealCd = cdInfo.isActive and not cdInfo.isOnGCD
    if not onRealCd then return true end  -- at least one charge -> hide duration
    return baseHide
end

-- Only icons with the toggle enabled live in this set, so each SPELL_UPDATE_CHARGES
-- iterates a tiny table; the event frame is created lazily on first watch.
ns._chargeCdTextWatch = ns._chargeCdTextWatch or setmetatable({}, { __mode = "k" })

-- Re-apply the countdown-number visibility for one watched charge frame from the
-- current charge state. Self-unwatches when the setting is off or the frame lost
-- its spell, so the set drains itself (mirrors EvalMaxStacksFrame).
local function EvalChargeCdTextFrame(frame, fd)
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    local cd = (fd and fd.cooldown) or frame.Cooldown
    if not sidw or not bkw or not cd or not cd.SetHideCountdownNumbers then
        ns._chargeCdTextWatch[frame] = nil
        return
    end
    local bd = barDataByKey and barDataByKey[bkw]
    local baseHide = not (bd and bd.showCooldownText)
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    if not (ssw and ssw.chargeHideCdText) then
        -- Setting turned off: restore the bar's own showCooldownText result and
        -- stop watching. (A per-icon showCooldownText override only exists on buff
        -- bars, which never enable this charge toggle, so the bar value is right.)
        ns._chargeCdTextWatch[frame] = nil
        cd:SetHideCountdownNumbers(baseHide)
        return
    end
    cd:SetHideCountdownNumbers(ns.CdmShouldHideCountdown(frame, baseHide))
end

local function WatchChargeCdTextFrame(frame, fd)
    ns._chargeCdTextWatch[frame] = fd
    if not ns._chargeCdTextEventFrame then
        local ef = CreateFrame("Frame")
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for f, d in pairs(ns._chargeCdTextWatch) do
                EvalChargeCdTextFrame(f, d)
            end
        end)
        ns._chargeCdTextEventFrame = ef
    end
end

-- Called from RefreshCDMIconAppearance (login + settings changes) so a charge
-- spell sitting at max -- which shows no recharge text and never fires the swipe
-- hook -- still gets watched for the moment it first dips below max. Early-outs on
-- non-charge icons (one cheap capability check, no settings lookup). Once watched,
-- the single SPELL_UPDATE_CHARGES frame keeps it current. Also self-cleans an icon
-- whose setting was just turned off.
function ns.WatchChargeCdTextIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then return end
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local isCharge = ci ~= nil and (ci.maxCharges or 0) > 1
    local ssw = isCharge and ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw)) or nil
    if ssw and ssw.chargeHideCdText then
        ns._cdmAnyChargeHideCdText = true
        WatchChargeCdTextFrame(frame, fd)
        EvalChargeCdTextFrame(frame, fd)
    elseif ns._chargeCdTextWatch[frame] then
        ns._chargeCdTextWatch[frame] = nil
        EvalChargeCdTextFrame(frame, fd)
    end
end

-------------------------------------------------------------------------------
--  Swiftmend brightness: Blizzard dims the icon via SetVertexColor when
--  Efflorescence / HoTs drop. Hook the icon texture once to force bright.
--  Recursion guard only -- never compare incoming args (secret values).
--  Retried on EVERY DecorateFrame call (not just the first decoration):
--  spell-ID resolution can miss on the frame's very first pass (cooldownID
--  not yet assigned), and the decorated-flag early return used to make that
--  miss permanent. Non-Druids skip on the cached class check; already-hooked
--  frames skip on one flag read, so the retry is effectively free.
-------------------------------------------------------------------------------
local SWIFTMEND_SID = 18562
local _smHookedIcons = {}
local function SwiftmendEnabled()
    return not EllesmereUIDB or EllesmereUIDB.brightenSwiftmend ~= false
end
local function TryHookSwiftmend(frame, fd)
    if not _isDruid or fd._smVCHooked then return end
    local iconWidget = fd.tex
    if not iconWidget then return end
    local dispSID, baseSID = ResolveFrameSpellID(frame)
    if dispSID and issecretvalue(dispSID) then dispSID = nil end
    if baseSID and issecretvalue(baseSID) then baseSID = nil end
    if baseSID ~= SWIFTMEND_SID and dispSID ~= SWIFTMEND_SID then return end
    fd._smVCHooked = true
    _smHookedIcons[#_smHookedIcons + 1] = iconWidget
    local smGuard = false
    hooksecurefunc(iconWidget, "SetVertexColor", function()
        if smGuard then return end
        if not SwiftmendEnabled() then return end
        smGuard = true
        iconWidget:SetVertexColor(1, 1, 1)
        smGuard = false
    end)
    if SwiftmendEnabled() then iconWidget:SetVertexColor(1, 1, 1) end
end

-- Temporary diagnostic for the "keep Swiftmend bright" report: dumps every
-- CDM frame currently resolving to Swiftmend plus its hook state.
SLASH_CDMSMDBG1 = "/cdmsmdbg"
SlashCmdList.CDMSMDBG = function()
    local n, hookedN = 0, 0
    for frame, fd in pairs(hookFrameData) do
        local dispSID, baseSID = ResolveFrameSpellID(frame)
        if dispSID and issecretvalue(dispSID) then dispSID = nil end
        if baseSID and issecretvalue(baseSID) then baseSID = nil end
        if dispSID == SWIFTMEND_SID or baseSID == SWIFTMEND_SID then
            n = n + 1
            if fd._smVCHooked then hookedN = hookedN + 1 end
            local col = "?"
            local tex = fd.tex
            if tex and tex.GetVertexColor then
                local r, g, b = tex:GetVertexColor()
                if r and not issecretvalue(r) then
                    col = string.format("%.2f %.2f %.2f", r, g, b)
                end
            end
            print(("|cff0cd29f[SMDBG]|r sid=%s/%s hooked=%s vc=%s shown=%s"):format(
                tostring(dispSID), tostring(baseSID), tostring(fd._smVCHooked or false),
                col, tostring(frame:IsShown())))
        end
    end
    print(("|cff0cd29f[SMDBG]|r swiftmend frames=%d hooked=%d druid=%s enabled=%s"):format(
        n, hookedN, tostring(_isDruid), tostring(SwiftmendEnabled())))
end

-------------------------------------------------------------------------------
--  Per-spell Custom Icon
--  Stamp the configured replacement icon (a texture fileID) over whatever the
--  icon texture currently shows. Runs from DecorateFrame on every (re)claim
--  and from a per-frame RefreshSpellTexture post-hook (installed below on the
--  first gated visit), so the custom icon survives every Blizzard repaint AND
--  spell transforms: RefreshSpellTexture is the ONLY writer of a viewer
--  item's icon texture (every item type's RefreshData + SPELL_UPDATE_ICON),
--  and the settings resolver matches the stored key against the frame's full
--  identity set (canonical, base, linked, override in both directions).
--  Purely per-spell -- the key is never written to bar tiers, so the resolved
--  entry's own value is the only possible source. Gated on
--  ns._cdmAnyCustomIcon: one boolean for non-users, and no hooks are ever
--  installed unless a custom icon is actually saved.
--
--  Clear/restore: when the setting is removed, the last stamped frame
--  (fd._customIconOn) restores its real spell icon once, re-derived via
--  C_Spell.GetSpellTexture (base id; the API resolves live overrides
--  internally, and the next Blizzard RefreshData corrects any aura/link
--  nuance). NEVER call the frame's own RefreshSpellTexture for this --
--  running Blizzard mixin code from insecure context can write tainted
--  values into the frame's table.
-------------------------------------------------------------------------------
local function ApplyCustomIcon(frame, fd)
    if not ns._cdmAnyCustomIcon then return end
    fd = fd or hookFrameData[frame]
    local tex = fd and fd.tex
    if not tex then return end
    -- Per-frame re-assert hook, installed on the first gated visit (the
    -- DecorateFrame claim paths land here). Must hook the frame INSTANCE:
    -- the leaf mixins' functions are COPIED onto each item frame at frame
    -- creation, so a hooksecurefunc on the mixin table never fires for frames
    -- that already existed when it installed (observed: the custom icon
    -- reverted on every cast -- each SPELL_UPDATE_COOLDOWN RefreshData
    -- repainted the real icon with no re-assert). Same per-frame pattern as
    -- the SetDesaturated hooks in DecorateFrame. Injected/own frames have no
    -- RefreshSpellTexture method and skip the hook (nothing Blizzard-side
    -- repaints them; the claim-path stamps below are enough).
    if not fd._ciHooked and frame.RefreshSpellTexture then
        fd._ciHooked = true
        hooksecurefunc(frame, "RefreshSpellTexture", ApplyCustomIcon)
    end
    local ss = ns._ResolveCdmSS(frame)
    local ci = ss and ss.customIcon
    if type(ci) == "number" and ci > 0 then
        tex:SetTexture(ci)
        fd._customIconOn = true
    elseif fd._customIconOn then
        fd._customIconOn = nil
        local fc = _ecmeFC[frame]
        local sid = fc and (fc.resolvedSid or fc.spellID)
        if type(sid) == "number" and sid > 0 and C_Spell and C_Spell.GetSpellTexture then
            local real = C_Spell.GetSpellTexture(sid)
            if real then tex:SetTexture(real) end
        end
    end
end
ns.ApplyCustomIcon = ApplyCustomIcon

-------------------------------------------------------------------------------
--  Only Show Numbers (bar setting, buff-family bars)
--  Renders a buff icon as just its countdown number: icon texture, background,
--  square border, shape ring, Blizzard debuff border and the duration swipe
--  are all hidden; the Cooldown widget's engine countdown text is forced ON.
--  Applied from DecorateFrame on every (re)claim and re-asserted at the end of
--  RefreshCDMIconAppearance's per-icon pass (which re-applies borders/shapes
--  and would otherwise undo the hides). All hides are alpha/flag based -- the
--  regions stay live, so turning the bar setting off restores one-shot via
--  fd._osnOn (pooled frames moving to a bar without the setting restore the
--  same way) and the normal style passes re-assert everything else. Cost when
--  off: one field read per call.
-------------------------------------------------------------------------------
local function ApplyOnlyNumbers(frame, fd, barData)
    if not barData then return end
    fd = fd or hookFrameData[frame]
    if barData.onlyShowNumbers then
        local tex = (fd and fd.tex) or frame._tex
        if tex then tex:SetAlpha(0) end
        local bg = (fd and fd.bg) or frame._bg
        if bg then bg:SetAlpha(0) end
        if fd and fd.borderFrame then
            EllesmereUI.PP.HideBorder(fd.borderFrame)
            local bdFrame = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[fd.borderFrame]
            if bdFrame then bdFrame:Hide() end
        end
        local ifc = _ecmeFC[frame]
        if ifc and ifc.shapeBorder then ifc.shapeBorder:SetAlpha(0) end
        if frame.DebuffBorder then frame.DebuffBorder:SetAlpha(0) end
        local cd = (fd and fd.cooldown) or frame.Cooldown or frame._cooldown
        if cd then
            if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
        end
        if fd then fd._osnOn = true end
    elseif fd and fd._osnOn then
        fd._osnOn = nil
        local tex = fd.tex or frame._tex
        if tex then tex:SetAlpha(1) end
        local bg = fd.bg or frame._bg
        if bg then bg:SetAlpha(1) end
        local ifc = _ecmeFC[frame]
        if ifc and ifc.shapeBorder then ifc.shapeBorder:SetAlpha(1) end
        if frame.DebuffBorder then frame.DebuffBorder:SetAlpha(1) end
        local cd = fd.cooldown or frame.Cooldown or frame._cooldown
        if cd then
            if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not barData.showCooldownText) end
        end
        -- Square border / shape ring re-apply on the next style pass
        -- (DecorateFrame / RefreshCDMIconAppearance), both re-run by the
        -- option's BuildAllCDMBars.
    end
end
ns.ApplyOnlyNumbers = ApplyOnlyNumbers

-------------------------------------------------------------------------------
--  DecorateFrame
--  Add our visual overlays to a CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function DecorateFrame(frame, barData)
    local fd = hookFrameData[frame]
    if not fd then fd = {}; hookFrameData[frame] = fd end

    -- Border + background must track the CURRENT bar's settings on every
    -- call, not just the first: Blizzard recycles a shared pool of icon
    -- frames across bars/spells, so a physical frame already decorated
    -- under a different bar's (or an older) style must still pick up this
    -- bar's current settings whenever it's (re)claimed. For hooked default
    -- bars (Essential/Utility), this DecorateFrame call from
    -- CollectAndReanchor is the ONLY re-style path -- RefreshCDMIconAppearance,
    -- which otherwise keeps custom bars current, is skipped for those bars.
    -- Structural frame/texture creation stays one-time via the fd.borderFrame /
    -- fd.bg guards; only the styling calls below are unconditional. Frame
    -- levels are relative to the icon's own live level (not a value cached at
    -- first decoration) so a pooled frame reclaimed at a different base level
    -- stays correctly layered against its own border/glow/text overlays.
    local baseLvl = frame:GetFrameLevel()

    if not fd.bg then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        fd.bg = bg
    end
    fd.bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08,
        barData.bgB or 0.08, barData.bgA or 0.6)

    -- Custom-shape bars own their border: ApplyShapeToCDMIcon draws the ring
    -- on the shapeBorder texture and hides the square border. Re-applying the
    -- square style here would force it back on top of the shaped icon on every
    -- reanchor whose icon set did NOT change (no shape re-apply follows those
    -- passes), so keep it hidden instead. Newly (re)claimed frames always land
    -- in an iconsChanged refresh, which re-applies the shape with current
    -- settings. The active-state tint on shaped icons rides shapeBorder
    -- (ApplyActiveOverlays), never the square border, so both re-asserts below
    -- are square-only.
    local shapeKey = barData.iconShape
    if shapeKey and shapeKey ~= "none" and shapeKey ~= "cropped" then
        if fd.borderFrame then
            EllesmereUI.PP.HideBorder(fd.borderFrame)
            local bdFrame = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[fd.borderFrame]
            if bdFrame then bdFrame:Hide() end
        end
    else
        if not fd.borderFrame then
            local bf = CreateFrame("Frame", nil, frame)
            bf:SetAllPoints(frame)
            fd.borderFrame = bf
        end
        local brdR, brdG, brdB = barData.borderR or 0, barData.borderG or 0, barData.borderB or 0
        if barData.borderClassColor then
            local cc = _playerClass and RAID_CLASS_COLORS[_playerClass]
            if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end
        end
        local textureKey = barData.borderTexture or "solid"
        EllesmereUI.ApplyBorderStyle(fd.borderFrame,
            barData.borderSize or 1,
            brdR, brdG, brdB, barData.borderA or 1,
            textureKey, barData.borderTextureOffset, barData.borderTextureOffsetY,
            barData.borderTextureShiftX, barData.borderTextureShiftY,
            "cdm", barData.borderThickness or "thin", true)
        -- ApplyBorderStyle above always paints the bar's BASE color. If this
        -- spell's active-state tint is currently engaged (ns.ApplyActiveOverlays
        -- drives fd._activeBorderOn independently of DecorateFrame, via Blizzard's
        -- own SetSwipeColor callback), re-assert it immediately so a reanchor
        -- firing mid-proc doesn't flash the border back to its base color.
        if fd._activeBorderOn and EllesmereUI.SetBorderStyleColor then
            local fcA = _ecmeFC[frame]
            local sidA, bkA = fcA and fcA.spellID, fcA and fcA.barKey
            local ss = sidA and ResolveSpellSettings(frame, sidA, ns.GetBarSpellData(bkA))
            local abR = (ss and ss.activeBorderR) or 1
            local abG = (ss and ss.activeBorderG) or 0.776
            local abB = (ss and ss.activeBorderB) or 0.376
            local abA = (ss and ss.activeBorderA) or 1
            EllesmereUI.SetBorderStyleColor(fd.borderFrame, abR, abG, abB, abA)
        end
    end
    -- "Show Behind": +13 draws the border in front of the icon, level-1 behind it.
    if fd.borderFrame then
        fd.borderFrame:SetFrameLevel(barData.borderBehind and math.max(0, baseLvl - 1) or (baseLvl + 13))
    end
    if fd.glowOverlay then fd.glowOverlay:SetFrameLevel(baseLvl + 16) end
    if fd.textOverlay then fd.textOverlay:SetFrameLevel(baseLvl + 23) end

    if fd.decorated then
        -- Late retry (see TryHookSwiftmend's helper comment): the unconditional
        -- style block above already ran; only the one-time decoration below is
        -- skipped for already-decorated frames.
        TryHookSwiftmend(frame, fd)
        ApplyCustomIcon(frame, fd)
        ApplyOnlyNumbers(frame, fd, barData)
        return fd
    end
    fd.decorated = true

    -- A HOSTED buff's frame is a Blizzard buff-viewer frame reparented onto a
    -- CD/util bar. Its cooldown swipe is the AURA DURATION (Blizzard-driven), not a
    -- spell cooldown -- so the cd-style swipe hooks below (Suppress-GCD, active-state
    -- override, charge logic) must never touch it, or they'd blank the duration
    -- swipe on every GCD. viewerFrame is stable per pooled frame, so flag it once.
    fd._isBuffViewerFrame = (frame.viewerFrame == _G.BuffIconCooldownViewer
        or frame.viewerFrame == _G.BuffBarCooldownViewer) or nil

    local iconWidget = frame.Icon
    if iconWidget and not iconWidget.GetTexture then
        if iconWidget.Icon then iconWidget = iconWidget.Icon end
    end
    fd.tex = iconWidget
    fd.cooldown = frame.Cooldown

    -- Swiftmend brightness (druid only; also retried from the decorated
    -- early-return above in case resolution misses on this first pass).
    TryHookSwiftmend(frame, fd)

    -- First decoration: fd.tex just became available, so the per-spell Custom
    -- Icon (if any) can be stamped from here on. Later re-claims go through
    -- the fd.decorated early-return above.
    ApplyCustomIcon(frame, fd)
    ApplyOnlyNumbers(frame, fd, barData)

    HideBlizzardDecorations(frame)

    -- Per-icon Audio on Buff Gain/Loss: attach the buff gain+loss sound hooks here
    -- (one-time, before the frame is ever active) so the very first activation isn't
    -- missed. Buff-family frames only; EnsureBuffSoundHook self-guards on the presence
    -- of TriggerAuraAppliedAlert, so injected-custom / non-aura frames are no-ops.
    if (barData and (barData.barType == "buffs" or barData.key == "buffs"))
       and ns._cdmAnyBuffSound and ns.EnsureBuffSoundHook then
        ns.EnsureBuffSoundHook(frame)
    end

    -- Hook SetPoint: when Blizzard repositions this frame (via Layout,
    -- RefreshLayout, or internal updates), force it back to the stored
    -- CDM anchor position if Blizzard tries to reposition it.
    if not fd._setPointHooked then
        fd._setPointHooked = true
        hooksecurefunc(frame, "SetPoint", function(_, point, relativeTo)
            local anchor = fd._cdmAnchor
            if not anchor then
                -- Icon not yet claimed by our bar system. If Blizzard's layout
                -- is positioning it (post-acquire), re-blank it so it doesn't
                -- flash at the viewer's position before CollectAndReanchor claims it.
                if fd.decorated then
                    frame:SetAlpha(0)
                    -- Re-park CD/utility frames offscreen (buff pools stay
                    -- hands-off): alpha alone cannot keep an unclaimed frame
                    -- invisible -- the engine re-raises item alpha through
                    -- paths no SetAlpha hook can see (SetAlphaFromBoolean,
                    -- alpha animations) whenever cooldown/aura state changes
                    -- (e.g. druid form swaps). Position enforcement is immune
                    -- to every alpha path. A later re-claim SetPoints the
                    -- frame absolutely, so recovery is total.
                    -- TOPLEFT keyword deliberately matches LayoutCDMBar's claim
                    -- SetPoint (which does not ClearAllPoints): same-keyword
                    -- SetPoint REPLACES the park point; a different keyword
                    -- would accumulate as a second conflicting anchor.
                    if not fd._isBuffViewerFrame and not fd._parkGuard then
                        fd._parkGuard = true
                        frame:ClearAllPoints()
                        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
                        fd._parkGuard = nil
                    end
                end
                return
            end
            -- If relativeTo is already our bar container, this is our own
            -- SetPoint call from LayoutCDMBar. Don't intercept.
            if relativeTo == anchor[2] then return end
            -- Blizzard is trying to move us. Force back to CDM position.
            frame:ClearAllPoints()
            frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
        end)
    end


    -- Per-icon active state hooks installed lazily during CollectAndReanchor,
    -- ONLY for spells with custom active state settings.

    -- glowOverlay/textOverlay structural creation stays one-time; their frame
    -- levels are (re)applied unconditionally near the top of this function.
    if not fd.glowOverlay then
        local go = CreateFrame("Frame", nil, frame)
        go:SetAllPoints(frame)
        go:SetAlpha(0)
        go:EnableMouse(false)
        fd.glowOverlay = go
        go:SetFrameLevel(baseLvl + 16)
    end

    if not fd.textOverlay then
        local txo = CreateFrame("Frame", nil, frame)
        txo:SetAllPoints(frame)
        txo:EnableMouse(false)
        fd.textOverlay = txo
        txo:SetFrameLevel(baseLvl + 23)
    end

    if not fd.keybindText then
        local kt = fd.textOverlay:CreateFontString(nil, "OVERLAY")
        local kbScale = frame:GetScale() or 1
        if kbScale < 0.01 then kbScale = 1 end
        EllesmereUI.ApplyIconTextFont(kt, GetCDMFont(), (barData.keybindSize or 10) / kbScale, "cdm")
        kt:SetPoint("TOPLEFT", fd.textOverlay, "TOPLEFT",
            barData.keybindOffsetX or 2, barData.keybindOffsetY or -2)
        kt:SetJustifyH("LEFT")
        kt:SetTextColor(barData.keybindR or 1, barData.keybindG or 1,
            barData.keybindB or 1, barData.keybindA or 0.9)
        kt:Hide()
        fd.keybindText = kt
    end

    fd.tooltipShown = false

    -- Hook Blizzard's pandemic state callbacks (combat-safe).
    ns.HookPandemicState(frame)

    local fc = FC(frame)
    if not fc.tooltipHooked then
        fc.tooltipHooked = true
        frame:HookScript("OnEnter", function()
            local ffc = _ecmeFC[frame]
            local bd = ffc and ffc.barKey and barDataByKey[ffc.barKey]
            if bd and not bd.showTooltip then
                GameTooltip:Hide()
            end
        end)
    end

    fd.procGlowActive = false

    if fd.cooldown then
        fd.cooldown:SetDrawEdge(false)
        -- Swipe starts disabled. CollectAndReanchor enables it once the
        -- frame is claimed and positioned on a bar. This prevents a flash
        -- of black swipe at the Blizzard viewer's default position before
        -- our reanchor runs.
        fd.cooldown:SetDrawSwipe(false)
        fd.cooldown:SetDrawBling(false)
        fd._isProcessingOverride = true
        fd.cooldown:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
        fd._isProcessingOverride = false
        fd.cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
        -- Hook SetSwipeColor on EVERY CD/utility frame.
        -- Forces our swipe color (default black, or per-spell custom)
        -- so Blizzard's active state color flash never shows.
        -- Also hook SetDrawSwipe to keep swipe visible on charge spells.
        if not fd._swipeColorHooked then
            fd._swipeColorHooked = true
            local cd = fd.cooldown
            hooksecurefunc(cd, "SetSwipeColor", function()
                if fd._isProcessingOverride then return end
                -- Buff-viewer frame (buff bar or hosted on a CD/util bar): the swipe
                -- is the aura DURATION, so skip all cd-style logic (Suppress-GCD,
                -- active-state). Apply only the per-spell "Cooldown Swipe Color":
                -- Default = the bar's swipe colour (black), Class / Custom per settings.
                if fd._isBuffViewerFrame then
                    fd._isProcessingOverride = true
                    local fcB = _ecmeFC[frame]
                    local sidB = fcB and fcB.spellID
                    local bkB = fcB and fcB.barKey
                    local ssB = (sidB and bkB and ns.ResolveSpellSettings)
                        and ns.ResolveSpellSettings(frame, sidB, ns.GetBarSpellData(bkB), bkB) or nil
                    local sr, sg, sb
                    -- CURRENT bar's swipe alpha, not the decorate-time closure
                    -- barData: pooled frames decorate once, so the closure holds
                    -- whichever bar first decorated this frame.
                    local bdB = bkB and barDataByKey and barDataByKey[bkB]
                    local alpha = (bdB and bdB.swipeAlpha) or barData.swipeAlpha or 0.7
                    local mode = ssB and ssB.cdSwipeColor
                    if mode == "class" then
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS[ct]
                        if cc then sr, sg, sb = cc.r, cc.g, cc.b end
                    elseif mode == "custom" then
                        sr, sg, sb = ssB.cdSwipeColorR, ssB.cdSwipeColorG, ssB.cdSwipeColorB
                    elseif mode == "none" then
                        alpha = 0  -- fully hide the swipe (alpha 0, geometry still valid)
                    end
                    cd:SetSwipeColor(sr or 0, sg or 0, sb or 0, alpha)
                    fd._isProcessingOverride = false
                    return
                end
                fd._isProcessingOverride = true
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                -- Per-bar "Suppress GCD": force alpha 0 when the displayed
                -- cooldown is just a GCD. isOnGCD is a clean bool from
                -- C_Spell.GetSpellCooldown. Do NOT return early -- active
                -- state detection below must still run so overlays and
                -- duration timers work correctly during GCD.
                local bd2 = bk2 and barDataByKey and barDataByKey[bk2]
                local _gcdSuppressed = false
                -- Per-bar "Suppress GCD": alpha-0 the swipe while the displayed
                -- cooldown is just a GCD. Two cases must NEVER be suppressed:
                --   1. The Hide-Active override window is forcing the real recharge
                --      display (a GCD pushed by pressing another ability is moot).
                --   2. A charge spell with a recharge in flight (ANY charge count
                --      below max, including 0 charges). That swipe IS the recharge,
                --      never a GCD -- alpha-0'ing it blanks the recharge for the entire
                --      GCD whenever another ability is pressed. Charge recharges are
                --      shown as their own swipe, so the GCD on top is irrelevant.
                if bd2 and bd2.suppressGCD and sid2 and not fd._hideActiveOverriding
                   and C_Spell and C_Spell.GetSpellCooldown then
                    -- Charge-recharge guard. A charge spell that is mid-recharge --
                    -- INCLUDING at 0 charges -- is showing its recharge, never a GCD,
                    -- so its swipe must never be alpha-0'd. Derive that from the
                    -- STABLE charge data (maxCharges > 1 AND GetSpellCharges().isActive,
                    -- the pattern Max-Stacks / Hide-CD-Text already use) instead of
                    -- frame:HasVisualDataSource_Charges(): that getter flips FALSE while
                    -- a GCD swipe is layered on top -- the exact moment this hook runs --
                    -- so the old gate let a 0-charge recharge fall through and get
                    -- suppressed. Both fields are clean (maxCharges int, isActive bool;
                    -- the secret currentCharges is never read). Override ID resolved for
                    -- transform spells, mirroring the re-arm paths below.
                    local effID2 = sid2
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                        if ovr and ovr > 0 and ovr ~= sid2 then effID2 = ovr end
                    end
                    local chargeRecharging = false
                    if C_Spell.GetSpellCharges then
                        local ci = C_Spell.GetSpellCharges(effID2) or C_Spell.GetSpellCharges(sid2)
                        chargeRecharging = (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) or false
                    end
                    if not chargeRecharging then
                        -- The GCD read must use the override too: a transform's real
                        -- CD ticks on the override ID (e.g. Rushing Wind Kick over
                        -- Rising Sun Kick), and the base-ID query reads isOnGCD=true
                        -- through that whole CD, leaving the swipe suppressed for
                        -- its full duration.
                        local cdInfo = C_Spell.GetSpellCooldown(effID2) or C_Spell.GetSpellCooldown(sid2)
                        if cdInfo and cdInfo.isOnGCD then
                            cd:SetSwipeColor(0, 0, 0, 0)
                            _gcdSuppressed = true
                        end
                    end
                end
                -- Check per-spell settings
                local ss2
                if sid2 and bk2 then
                    ss2 = ResolveSpellSettings(frame, sid2, ns.GetBarSpellData(bk2))
                end
                -- Detect active state from swipe color
                local swipeColor = frame.cooldownSwipeColor
                local isActive = false
                if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                    local r = swipeColor:GetRGBA()
                    if r and type(r) == "number" and not issecretvalue(r) then
                        isActive = (r ~= 0)
                    end
                end

                -- Mark the per-session flag the moment any spell uses this setting,
                -- so the SetDesaturated/SetDesaturation hooks can early-out with a
                -- single check for everyone who never enables it. The swipe block
                -- runs for every icon on login, so this also covers /reload.
                if ss2 and ss2.desatNotActive then ns._cdmAnyDesatNotActive = true end
                -- Same one-shot gate for the per-spell charge Hide Swipe so the
                -- SetDrawSwipe hook can early-out for everyone who never enables
                -- it. Covers /reload (runs for every icon).
                if ss2 and (ss2.chargeHideSwipe or ss2.hideRechargeEdge) then ns._cdmAnyChargeStyle = true end
                if ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0 then ns._cdmAnyMaxStacksGlow = true end
                if ss2 and ss2.chargeHideCdText then ns._cdmAnyChargeHideCdText = true end
                if ss2 and ss2.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                if ss2 and ss2.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
                if ss2 and (tonumber(ss2.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end

                if ss2 and ss2.activeSwipeMode == "none" then
                    -- Hide Active State: force black swipe, track active flag.
                    -- CD model override is handled by the SetDesaturation hook
                    -- which fires on every Blizzard cooldown tick.
                    -- Suppress GCD for a hero-talent transform to a usable follow-up:
                    -- while a castable proc is shown (override present, not on its own
                    -- real CD) this icon has no real CD, so the hide-active black swipe
                    -- has no geometry and is invisible -- UNTIL another ability pushes a
                    -- GCD via SetCooldown, whose geometry the PERSISTENT black swipe
                    -- colour then sweeps as a visible bar (SetCooldown changes geometry,
                    -- not colour, so nothing re-hides it). Paint this swipe fully
                    -- transparent for exactly this case so the GCD never shows. Gated to
                    -- Suppress GCD ("ignore GCD") being on; normal hide-active spells and
                    -- transforms whose proc is on its own real CD keep the black swipe.
                    -- A charge proc mid-recharge is carved out (its swipe IS the recharge,
                    -- never a GCD) -- same as the suppress-GCD block above.
                    local hideActiveAlpha = barData.swipeAlpha or 0.7
                    if bd2 and bd2.suppressGCD and sid2
                       and C_SpellBook and C_SpellBook.FindSpellOverrideByID
                       and C_Spell and C_Spell.GetSpellCooldown then
                        local ovrID = C_SpellBook.FindSpellOverrideByID(sid2)
                        if ovrID and ovrID > 0 and ovrID ~= sid2 then
                            local chargeRecharging = false
                            if C_Spell.GetSpellCharges then
                                local ci = C_Spell.GetSpellCharges(ovrID) or C_Spell.GetSpellCharges(sid2)
                                chargeRecharging = (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) or false
                            end
                            local oc = C_Spell.GetSpellCooldown(ovrID)
                            if not chargeRecharging and oc and not (oc.isActive and not oc.isOnGCD) then
                                hideActiveAlpha = 0
                            end
                        end
                    end
                    if not _gcdSuppressed then
                        cd:SetSwipeColor(0, 0, 0, hideActiveAlpha)
                    end
                    if isActive then
                        fd._hideActiveOverriding = true
                        fd._wasActive = true
                    elseif fd._hideActiveOverriding then
                        fd._hideActiveOverriding = false
                        if cd.SetUseAuraDisplayTime then
                            cd:SetUseAuraDisplayTime(true)
                        end
                    end
                elseif isActive then
                    -- Active: apply swipe color (custom, class, or default #FFC660)
                    local cr, cg, cb, ca
                    if ss2 and ss2.activeSwipeClassColor then
                        local _, ct = UnitClass("player")
                        if ct then
                            local cc = RAID_CLASS_COLORS[ct]
                            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                        end
                    end
                    cr = cr or (ss2 and ss2.activeSwipeR) or 1
                    cg = cg or (ss2 and ss2.activeSwipeG) or 0.776
                    cb = cb or (ss2 and ss2.activeSwipeB) or 0.376
                    ca = (ss2 and ss2.activeSwipeA) or 0.7
                    cd:SetSwipeColor(cr, cg, cb, ca)
                    if fd.tex then fd.tex:SetDesaturated(false); fd._desatNA = nil end
                    fd._wasActive = true
                else
                    -- Not active: black swipe.
                    if not _gcdSuppressed then
                        cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
                    end
                    -- Desaturate When Not Active (per-spell). Symmetric: desaturate
                    -- while the setting is on, and RE-saturate when it's turned off --
                    -- but only for icons WE desaturated (fd._desatNA), so turning it off
                    -- never fights cdState / buff desaturation on other icons and doesn't
                    -- have to wait for the next cooldown event to un-grey.
                    if fd.tex then
                        if ss2 and ss2.desatNotActive then
                            fd.tex:SetDesaturated(true)
                            fd._desatNA = true
                        elseif fd._desatNA then
                            fd.tex:SetDesaturated(false)
                            fd._desatNA = nil
                        end
                    end
                    -- Transition: buff just ended, CD starting. Re-apply the
                    -- cooldown duration so the swipe shows immediately
                    -- (e.g. Invoke Niuzao). Only fires once per transition,
                    -- and only if the spell actually has an active cooldown.
                    if fd._wasActive then
                        fd._wasActive = false
                        if sid2 and cd.SetCooldownFromDurationObject and C_Spell.GetSpellCooldown then
                            local cdInfo = C_Spell.GetSpellCooldown(sid2)
                            if cdInfo and cdInfo.isActive then
                                local durObj = C_Spell.GetSpellCooldownDuration(sid2)
                                if durObj then
                                    cd:SetCooldownFromDurationObject(durObj)
                                    cd:SetDrawSwipe(true)
                                end
                            end
                        end
                    end
                end

                -- Charge "Hide Swipe" only suppresses the recharge swipe; the
                -- active-state colored swipe IS the active overlay, so keep it
                -- drawn while the active state is showing. Runs inside the
                -- override guard, so the SetDrawSwipe hook does not re-enter.
                if ns._cdmAnyChargeStyle and ss2 and ss2.chargeHideSwipe and cd.SetDrawSwipe
                   and type(frame.HasVisualDataSource_Charges) == "function"
                   and frame:HasVisualDataSource_Charges() then
                    cd:SetDrawSwipe(ss2.activeSwipeMode ~= "none" and isActive)
                end

                -- Active glow + active border (per-spell). Extracted so the
                -- isolated Fake-Active engine can drive the same overlays from
                -- its own ticker; shares fd._activeGlowOn / fd._activeBorderOn so
                -- the two paths cooperate. Touches only our overlays (never the
                -- Blizzard swipe), so it is safe from any call context.
                ns.ApplyActiveOverlays(frame, fd, ss2, isActive, bd2)

                -- Max Stacks Glow (per-spell): glow a multi-charge spell at max charges.
                -- "At max" = no recharge running, read from GetSpellCharges().isActive
                -- The secret currentCharges is never read. Consuming a charge fires this
                -- swipe hook; refilling to max fires Cooldown:Clear (handled below).
                if ns._cdmAnyMaxStacksGlow and ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0 then
                    -- Register for charge/cooldown events (the only thing that catches
                    -- refill-to-max) and eval now so a charge SPEND updates immediately.
                    WatchMaxStacksFrame(frame, fd)
                    EvalMaxStacksFrame(frame, fd)
                elseif fd._maxStacksGlowOn then
                    ApplyMaxStacksGlow(frame, fd, nil, false)  -- setting cleared -> off
                    ns._maxStacksWatch[frame] = nil
                end

                -- (Active border moved into ns.ApplyActiveOverlays above.)

                fd._isProcessingOverride = false
            end)
            hooksecurefunc(cd, "SetDrawSwipe", function(_, show)
                if fd._isProcessingOverride then return end
                -- Hosted buff: never toggle its duration swipe from our cd logic.
                if fd._isBuffViewerFrame then return end
                -- Charge spells get the baseline edge (+ per-spell Hide Swipe).
                -- ApplyCdmChargeStyle returns true and fully owns the swipe + edge
                -- only for charge spells, so non-charge frames fall through to the
                -- default force-true below.
                fd._isProcessingOverride = true
                local handled = ApplyCdmChargeStyle(frame, cd)
                fd._isProcessingOverride = false
                if handled then return end
                -- Per-spell Hide CD Swipe (non-charge): keep the swipe suppressed even
                -- when Blizzard re-pushes the cooldown. Gated so it costs nothing until
                -- someone enables it. Resolved from our own flags (secret-safe) in both
                -- stores -- per-bar spellSettings and preset customActiveStates.
                if ns._cdmAnyHideCDSwipe then
                    local ssH = ns._ResolveCdmSS(frame)
                    local hideSw = ssH and ssH.hideCDSwipe
                    if not hideSw and ns.GetEffectiveCustomActiveState then
                        local fcH = _ecmeFC[frame]
                        local sidH = fcH and fcH.spellID
                        if sidH then
                            local casH = ns.GetEffectiveCustomActiveState(sidH)
                            hideSw = casH and casH.hideCDSwipe
                        end
                    end
                    if hideSw then
                        if show then
                            fd._isProcessingOverride = true
                            cd:SetDrawSwipe(false)
                            fd._isProcessingOverride = false
                        end
                        return
                    end
                end
                if show then return end
                fd._isProcessingOverride = true
                cd:SetDrawSwipe(true)
                fd._isProcessingOverride = false
            end)
            -- Hide Recharge Edge enforcement. Blizzard re-enables the leading
            -- edge on every cooldown re-push -- notably while a cooldown-reduction
            -- effect repeatedly re-arms a charge recharge -- and the SetDrawSwipe
            -- hook above only catches re-pushes that ALSO toggle the swipe, so the
            -- edge flickers back on between them. Hook SetDrawEdge directly so a
            -- charge spell with Hide Recharge Edge on keeps the edge suppressed.
            -- Mirror of the SetDrawSwipe hook: clean getters + our own ss flag,
            -- guarded so ApplyCdmEdge's own SetDrawEdge(true) never recurses.
            if cd.SetDrawEdge then
                hooksecurefunc(cd, "SetDrawEdge", function(_, show)
                    if fd._isProcessingOverride then return end
                    if not show then return end
                    if type(frame.HasVisualDataSource_Charges) ~= "function"
                       or not frame:HasVisualDataSource_Charges() then return end
                    if not ns._cdmAnyChargeStyle then return end
                    local ss2 = ns._ResolveCdmSS(frame)
                    if not (ss2 and ss2.hideRechargeEdge) then return end
                    fd._isProcessingOverride = true
                    cd:SetDrawEdge(false)
                    fd._isProcessingOverride = false
                end)
            end
            -- Non-charge cooldown re-assert. Blizzard's CooldownViewer zeroes the
            -- cooldown widget for some spells partway through their REAL cooldown
            -- and never re-pushes it -- notably DH placement sigils (Flame / Misery
            -- / Silence), whose widget is cleared when the sigil activates (~1s in)
            -- even though GetSpellCooldown reports the full 30s cooldown still
            -- running, leaving the icon with no swipe for the rest of the CD.
            -- (Sigil of Spite is unaffected: its widget is never cleared early.)
            -- Charge spells are handled by the charge re-arm below; this covers the
            -- non-charge case. Gated tightly so it acts ONLY on the exact failure --
            -- widget cleared to ~0 while a genuine non-GCD cooldown is live -- and
            -- never fights a GCD swipe or aura-display time (both non-zero).
            local function ReAssertRealCooldown()
                if fd._isProcessingOverride then return end
                -- Always-Show placeholders deliberately keep their widget cleared
                -- (never arm a 0-duration swipe); never re-assert onto one.
                if fd._isBuffViewerFrame or frame._isPlaceholderFrame then return end
                -- Charge spells: owned by the charge re-arm path.
                if type(frame.HasVisualDataSource_Charges) == "function"
                   and frame:HasVisualDataSource_Charges() then return end
                if not (C_Spell and C_Spell.GetSpellCooldown
                        and C_Spell.GetSpellCooldownDuration) then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 then return end
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- Only re-assert for a genuine, non-GCD cooldown still running.
                -- isActive / isOnGCD are clean bools (read bare elsewhere).
                local cdInfo = C_Spell.GetSpellCooldown(effID) or C_Spell.GetSpellCooldown(sid2)
                if not (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) then return end
                -- Don't fight a widget that already shows a real cooldown, a GCD, or
                -- aura-display time -- act only when it is cleared to ~0. The secret
                -- check MUST run before any truthiness/comparison on the value (a
                -- secret errors on either); when the widget's duration is secret we
                -- cannot prove it was cleared, so fail closed and leave it alone
                -- (the sigil failure moment reads a clean 0, so the fix still runs).
                if cd.GetCooldownDuration then
                    local ok, curDur = pcall(cd.GetCooldownDuration, cd)
                    if not ok then return end
                    if issecretvalue and issecretvalue(curDur) then return end
                    if curDur and curDur > 100 then return end
                end
                local durObj = C_Spell.GetSpellCooldownDuration(effID)
                    or C_Spell.GetSpellCooldownDuration(sid2)
                if not durObj then return end
                fd._isProcessingOverride = true
                if cd.SetUseAuraDisplayTime then cd:SetUseAuraDisplayTime(false) end
                cd:SetCooldownFromDurationObject(durObj)
                -- Only the geometry was wiped -- Blizzard's clear leaves the draw-
                -- swipe flag on -- so re-arming the duration restores the visible
                -- swipe. Deliberately NOT forcing SetDrawSwipe(true): doing so under
                -- the _isProcessingOverride guard would bypass the per-spell "Hide
                -- CD Swipe" enforcement and make the swipe reappear against the
                -- user's setting.
                fd._isProcessingOverride = false
            end

            -- Charge-spell recharge swipe restore.
            -- The swipe is rendered from the widget's armed duration, NOT from
            -- the SetDrawSwipe flag (the flag only gates an existing swipe). When
            -- one charge of a multi-charge spell refills while another is still
            -- recharging, Blizzard's CooldownViewer calls Cooldown:Clear(), which
            -- wipes the armed duration. Our SetDrawSwipe(true) brute-force then
            -- has no geometry to draw, so the still-valid recharge swipe vanishes.
            -- Re-arm from the charge recharge duration so the swipe stays visible.
            -- Charge spells only; a non-charge frame routes to the re-assert above.
            hooksecurefunc(cd, "Clear", function()
                if fd._isProcessingOverride then return end
                -- HasVisualDataSource_Charges is a clean bool and exists only on
                -- Blizzard CooldownViewer item frames, so this also excludes our
                -- own custom (trinket/racial/item) frames and aura buff frames.
                local hasCharges = type(frame.HasVisualDataSource_Charges) == "function"
                    and frame:HasVisualDataSource_Charges()
                if not hasCharges then ReAssertRealCooldown(); return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 or not C_Spell or not C_Spell.GetSpellCooldown
                    or not C_Spell.GetSpellChargeDuration then
                    return
                end
                -- Resolve the override ID for transformed spells (mirror of the
                -- onDesatChange / cdState paths) BEFORE querying cooldown state,
                -- so charge-based replacements report against the live spell.
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- isActive / isOnGCD are clean bools from C_Spell.GetSpellCooldown
                -- (read bare elsewhere in this file). Only re-arm while the spell
                -- is genuinely still recharging AND not merely on GCD: a GCD-tail
                -- race can transiently report isActive with a degenerate charge
                -- duration, and arming a 0,0 cooldown would strobe the swipe. When
                -- all charges are back (isActive false) leave it cleared so the
                -- swipe correctly disappears.
                -- Max Stacks Glow: Clear fires on every charge refill (incl. reaching
                -- max). Re-eval from GetSpellCharges().isActive (clean; false only at
                -- max) so the glow turns on the moment the last charge returns.
                if ns._cdmAnyMaxStacksGlow then
                    local bkm = fc2 and fc2.barKey
                    local ssm = bkm and ResolveSpellSettings(frame, sid2, ns.GetBarSpellData(bkm)) or nil
                    if ssm and ssm.maxStacksGlow and ssm.maxStacksGlow > 0 then
                        WatchMaxStacksFrame(frame, fd)
                        EvalMaxStacksFrame(frame, fd)
                    end
                end
                local cdInfo = C_Spell.GetSpellCooldown(effID)
                local cdActive = cdInfo and cdInfo.isActive and not cdInfo.isOnGCD
                -- Charge-in-hand Hide-Active window: GetSpellCooldown().isActive is
                -- false while a castable charge remains, so the cd gate above never
                -- re-arms the recharge, and Blizzard's per-aura-refresh wipe leaves
                -- the swipe blank. Re-arm off the clean recharge flag instead, but
                -- ONLY inside our Hide-Active override so non-override charge spells
                -- keep Blizzard's native display untouched. Secret-safe: GetSpellCharges
                -- .isActive is a clean bool; currentCharges is never read.
                local chargeActive = fd._hideActiveOverriding and C_Spell.GetSpellCharges
                    and (C_Spell.GetSpellCharges(effID) or C_Spell.GetSpellCharges(sid2) or {}).isActive == true
                if not (cdActive or chargeActive) then return end
                -- Re-derive the charge recharge duration. The duration object is
                -- opaque and fed straight to the widget, never inspected, so it is
                -- secret-safe.
                local durObj = C_Spell.GetSpellChargeDuration(effID)
                if not durObj and effID ~= sid2 then
                    durObj = C_Spell.GetSpellChargeDuration(sid2)
                end
                if not durObj then return end
                fd._isProcessingOverride = true
                if cd.SetUseAuraDisplayTime then
                    cd:SetUseAuraDisplayTime(false)
                end
                cd:SetCooldownFromDurationObject(durObj)
                -- Baseline charge edge (+ per-spell Hide Swipe) on the re-arm.
                ApplyCdmChargeStyle(frame, cd)
                fd._isProcessingOverride = false
            end)
            -- During the Hide-Active window Blizzard re-pushes the cooldown widget
            -- for a charge-in-hand spell via SetCooldownFromDurationObject (the aura
            -- display) and toggles SetUseAuraDisplayTime -- NOT plain SetCooldown.
            -- Those pushes wipe the recharge we armed (the Clear/SetDesaturated hooks
            -- fire far too rarely to keep up). Re-assert the recharge on each of
            -- those two real drivers, gated to EXACTLY (charge frame + Hide-Active
            -- window + recharge running) so it is a no-op for everything else. The
            -- fd._isProcessingOverride guard blocks recursion from our own
            -- SetUseAuraDisplayTime / SetCooldownFromDurationObject writes below.
            local function ReArmChargeRecharge()
                if fd._isProcessingOverride then return end
                if not fd._hideActiveOverriding then return end
                local hasCharges = type(frame.HasVisualDataSource_Charges) == "function"
                    and frame:HasVisualDataSource_Charges()
                if not hasCharges then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 or not C_Spell or not C_Spell.GetSpellCharges
                    or not C_Spell.GetSpellChargeDuration then
                    return
                end
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- Only while a recharge is genuinely running. isActive is a clean
                -- bool; currentCharges (secret) is never read.
                local ci = C_Spell.GetSpellCharges(effID) or C_Spell.GetSpellCharges(sid2)
                if not (ci and ci.isActive == true) then return end
                local durObj = C_Spell.GetSpellChargeDuration(effID)
                if not durObj and effID ~= sid2 then
                    durObj = C_Spell.GetSpellChargeDuration(sid2)
                end
                if not durObj then return end
                fd._isProcessingOverride = true
                if cd.SetUseAuraDisplayTime then
                    cd:SetUseAuraDisplayTime(false)
                end
                cd:SetCooldownFromDurationObject(durObj)
                ApplyCdmChargeStyle(frame, cd)
                -- We have just re-armed the REAL recharge, so whatever is now
                -- displayed is the recharge -- never a GCD. Suppress-GCD's alpha-0
                -- swipe (set while isOnGCD, e.g. right after pressing ANOTHER
                -- ability) must not stick here or the recharge stays invisible
                -- until the active state ends. Restore the normal black
                -- hide-active swipe unconditionally; black where black is already
                -- correct is a no-op for the Suppress-GCD-off case.
                local bkSw = fc2 and fc2.barKey
                local bdSw = bkSw and barDataByKey and barDataByKey[bkSw]
                cd:SetSwipeColor(0, 0, 0, (bdSw and bdSw.swipeAlpha) or 0.7)
                fd._isProcessingOverride = false
            end
            if cd.SetCooldownFromDurationObject then
                hooksecurefunc(cd, "SetCooldownFromDurationObject", ReArmChargeRecharge)
                -- Also catch the placement-sigil case where Blizzard clears the
                -- widget via a zero-duration SetCooldownFromDurationObject rather
                -- than Clear(). ReAssertRealCooldown's own guard blocks recursion
                -- and its ~0 duration gate makes this a no-op for normal pushes.
                hooksecurefunc(cd, "SetCooldownFromDurationObject", ReAssertRealCooldown)
            end
            if cd.SetUseAuraDisplayTime then
                hooksecurefunc(cd, "SetUseAuraDisplayTime", ReArmChargeRecharge)
            end
            -- Pressing ANOTHER ability pushes the global cooldown onto this frame
            -- via SetCooldown (not the aura-display setters above), replacing the
            -- charge recharge geometry. In the Hide-Active window that wipes the
            -- real recharge we are showing -- it returns only when the active
            -- state ends. Re-arm on SetCooldown too so the recharge survives an
            -- off-GCD push. ReArmChargeRecharge fully gates itself (override window
            -- + charge frame + recharge running) and is re-entry guarded, so this
            -- is a no-op for every normal cooldown and outside the override window.
            if cd.SetCooldown then
                hooksecurefunc(cd, "SetCooldown", ReArmChargeRecharge)
            end
        end
        -- Hook SetDesaturated AND SetDesaturation on icon texture: Blizzard
        -- calls these on every cooldown tick. When we're overriding the CD
        -- model (hide active state), re-apply the actual CD duration here so
        -- Blizzard can't revert it between ticks.
        if fd.tex and not fd._desatOverrideHooked then
            fd._desatOverrideHooked = true
            local function onDesatChange()
                if fd._isProcessingOverride then return end
                if not fd._hideActiveOverriding then return end
                fd._isProcessingOverride = true
                local cdw = fd.cooldown
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if sid2 and cdw then
                    if cdw.SetUseAuraDisplayTime then
                        cdw:SetUseAuraDisplayTime(false)
                    end
                    if cdw.SetCooldownFromDurationObject then
                        -- Resolve effective spell ID: when a spell is
                        -- transformed (e.g. Judgment -> Hammer of Wrath
                        -- under Wings), Blizzard's charge/cooldown APIs
                        -- report against the override ID, not the base.
                        -- Query the override first and fall back to the
                        -- base ID so non-transformed spells still work.
                        local effID = sid2
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                            if ovr and ovr > 0 and ovr ~= sid2 then
                                effID = ovr
                            end
                        end
                        local hasCharges = type(frame.HasVisualDataSource_Charges) == "function"
                            and frame:HasVisualDataSource_Charges()
                        local durObj
                        if hasCharges and C_Spell.GetSpellChargeDuration then
                            durObj = C_Spell.GetSpellChargeDuration(effID)
                            if not durObj and effID ~= sid2 then
                                durObj = C_Spell.GetSpellChargeDuration(sid2)
                            end
                        end
                        if not durObj and C_Spell.GetSpellCooldownDuration then
                            durObj = C_Spell.GetSpellCooldownDuration(effID)
                            if not durObj and effID ~= sid2 then
                                -- Borrow the base spell's cooldown ONLY when the live
                                -- override is itself on a real CD (a cosmetic/behaviour
                                -- transform that shares the base cooldown -- the original
                                -- reason for this fallback). A hero-talent transform to a
                                -- CASTABLE follow-up (e.g. Bestial Wrath -> Wailing Arrow)
                                -- reports no real CD of its own, so it must NOT inherit the
                                -- base's remaining cooldown -- that painted the base CD
                                -- swipe over a usable proc and read as "on cooldown".
                                -- Leaving durObj nil takes the same no-swipe path as a proc
                                -- without a real CD. isActive/isOnGCD are clean bools.
                                -- Keep the original base-borrow whenever the override
                                -- is on a real CD OR its cooldown is unknown (oc nil) --
                                -- only a CONFIRMED-castable proc (oc present, not on a
                                -- real CD) suppresses the borrow. Mirrors the desat guard
                                -- below so the swipe and the saturation always agree.
                                local oc = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(effID)
                                if (not oc) or (oc.isActive and not oc.isOnGCD) then
                                    durObj = C_Spell.GetSpellCooldownDuration(sid2)
                                end
                            end
                        end
                        if durObj then
                            cdw:SetCooldownFromDurationObject(durObj)
                        end
                    end
                end
                -- Only desaturate if the spell is actually on cooldown.
                -- Spells procced without a real CD (e.g. Demonic Meta via
                -- Eye Beam) should stay saturated. Filter GCDs the same
                -- way the suppressGCD check above does.
                local cdInfo2 = sid2 and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid2)
                local onRealCD = cdInfo2 and cdInfo2.isActive and not cdInfo2.isOnGCD
                -- Charge spells report cooldown isActive while a recharge is in
                -- progress even when a castable charge remains, which would wrongly
                -- desaturate a still-usable icon. currentCharges is a SECRET value
                -- in this tainted hook (can't be compared), so use Blizzard's clean
                -- isOnActualCooldown flag instead -- false means at least one charge
                -- is usable, so stay saturated until the spell is genuinely out.
                if onRealCD and type(frame.HasVisualDataSource_Charges) == "function"
                   and frame:HasVisualDataSource_Charges() then
                    local actualCD = frame.isOnActualCooldown
                    if (not issecretvalue or not issecretvalue(actualCD)) and actualCD == false then
                        onRealCD = false
                    end
                end
                -- Hero-talent transform to a usable follow-up: while a live spell
                -- override is showing (e.g. Bestial Wrath -> Wailing Arrow, Trueshot
                -- -> Moonlight Chakram), the base cooldownID spell (sid2) is on its
                -- real CD but the displayed proc is castable, so the base check above
                -- desaturated it wrongly. Re-check the override's OWN cooldown and
                -- stay saturated when the proc is free. Same shape as the charge guard
                -- above: only ever CLEARS onRealCD, never sets it -- so every
                -- non-transform icon, and every transform whose proc is itself on a
                -- real CD (oc.isActive), is byte-identical. Clean bools only.
                if onRealCD and sid2 and C_SpellBook and C_SpellBook.FindSpellOverrideByID
                   and C_Spell and C_Spell.GetSpellCooldown then
                    local ovrID = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovrID and ovrID > 0 and ovrID ~= sid2 then
                        local oc = C_Spell.GetSpellCooldown(ovrID)
                        if oc and not (oc.isActive and not oc.isOnGCD) then
                            onRealCD = false
                        end
                    end
                end
                fd.tex:SetDesaturated(onRealCD or false)
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", onDesatChange)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", onDesatChange)
            end
        end
        -- Swipe direction baseline by FRAME kind, not just bar kind: a buff
        -- frame (or a hosted-buff placeholder) fills like a buff even when it
        -- renders on a CD/utility bar. Decoration is once-per-frame while
        -- Blizzard POOLS these frames across uses, so the kind is recorded in
        -- fd._revKind and the claim loops re-assert the direction whenever the
        -- kind changes -- a frame first decorated for the wrong bar family
        -- otherwise kept that direction for the whole session (buffs randomly
        -- rendering with a reversed swipe depending on pool history).
        local isBuff = (barData.barType == "buffs" or barData.key == "buffs"
            or barData.barType == "custom_buff"
            or fd._isBuffViewerFrame or frame._isPlaceholderFrame) and true or false
        fd.cooldown:SetReverse(isBuff)
        fd._revKind = isBuff

        -- NOTE: Clear IS hooked above (in the _swipeColorHooked block) to restore
        -- the recharge swipe on charge spells, and SetCooldown is hooked there too
        -- (-> ReArmChargeRecharge) so an off-GCD push from pressing another ability
        -- cannot wipe the recharge during the Hide-Active window. A hooksecurefunc
        -- post-hook does not taint the secure caller; taint would only stick if the
        -- hook BODY wrote a Blizzard frame field (e.g. isActive, allowAvailableAlert)
        -- or called Show/Hide/SetAlpha on a Blizzard frame. Neither hook does that:
        -- they read only clean getters (HasVisualDataSource_Charges,
        -- GetSpellCooldown().isActive, GetSpellCharges().isActive) and call pure
        -- cooldown-widget setters (SetUseAuraDisplayTime / SetCooldownFromDurationObject
        -- / SetDrawSwipe / SetSwipeColor), the same setters already used safely by the
        -- SetSwipeColor and SetDesaturated hooks. ReArmChargeRecharge also self-gates
        -- to the override window so SetCooldown is a no-op for normal cooldowns. All
        -- hook state lives on the external fd table, never on the Blizzard frame.

        -- Cooldown State Effect: separate additive hook on SetDesaturated.
        -- Blizzard calls SetDesaturated on every CD tick AND on CD end,
        -- making it the right event for both "on CD" and "off CD" transitions.
        -- This hook is independent from onDesatChange (hideActive) above.
        if fd.tex and not fd._cdStateHooked then
            fd._cdStateHooked = true
            hooksecurefunc(fd.tex, "SetDesaturated", function()
                if fd._isProcessingOverride then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                if not sid2 or not bk2 then return end
                if bk2:sub(1, 7) == "__ghost" then return end
                -- FocusKick icon alpha is owned by SetFocusKickAlpha only.
                if bk2 == ns.FOCUSKICK_BAR_KEY then return end
                -- Preset frames (trinket / racial / potion / custom spell) own their
                -- cd-state entirely through the Fake-Active engine, which reads the
                -- ITEM/racial cooldown. C_Spell.GetSpellCooldown can't read a negative
                -- item key, so this spell path always sees the item as ready and would
                -- re-light the shared glowOverlay every desat tick while it's on
                -- cooldown. Hand the frame off cleanly (clear any glow we owned).
                if ns.PresetHasCdState and ns.PresetHasCdState(frame) then
                    if fd._cdStateGlowOn then
                        if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                        fd._cdStateGlowOn = false
                        -- The Fake-Active path owns this overlay through its own
                        -- flag; clear it too so its next tick re-asserts the glow we
                        -- just stopped (otherwise it thinks the glow is still on and
                        -- never re-starts it, leaving a ready preset dark).
                        fd._presetCdGlowOn = false
                    end
                    return
                end
                local ss2 = ResolveSpellSettings(frame, sid2, ns.GetBarSpellData(bk2))
                local cse = ss2 and ss2.cdStateEffect
                -- Shift-Icons variants behave exactly like their base hidden
                -- mode plus a bar-relayout flag; normalize here so every
                -- comparison below stays unchanged.
                local cseShift = (cse == "hiddenOnCDShift" or cse == "hiddenReadyShift")
                if cse == "hiddenOnCDShift" then cse = "hiddenOnCD"
                elseif cse == "hiddenReadyShift" then cse = "hiddenReady" end
                if not cse then
                    if fd._cdStateGlowOn then
                        if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                        fd._cdStateGlowOn = false
                    end
                    -- A preset's cdState lives in customActiveStates (driven by the
                    -- Fake-Active engine), not per-bar spellSettings -- so don't clear
                    -- its hidden flag here or it flashes visible every desat tick.
                    if fc2 and fc2._cdStateHidden
                       and not (ns.PresetHasCdState and ns.PresetHasCdState(frame)) then
                        fc2._cdStateHidden = false
                    end
                    if fc2 and fc2._cdStateShiftHidden
                       and not (ns.PresetHasCdState and ns.PresetHasCdState(frame))
                       and ns.SetCdStateShiftHidden then
                        ns.SetCdStateShiftHidden(fc2, false)
                    end
                    return
                end
                -- Clear stale hidden state when switching to a non-hidden effect
                -- (lowerAlphaOnCD is alpha-owning like the hidden modes, so exclude it).
                if cse ~= "hiddenOnCD" and cse ~= "hiddenReady" and cse ~= "lowerAlphaOnCD" then
                    if fc2 and fc2._cdStateHidden then
                        fc2._cdStateHidden = false
                        local bd2 = barDataByKey and barDataByKey[bk2]
                        frame:SetAlpha(ns.IconShownAlpha(fc2, bd2))
                    end
                    -- (cse is already normalized, so Shift variants never land here.)
                    if fc2 and ns.SetCdStateShiftHidden then
                        ns.SetCdStateShiftHidden(fc2, false)
                    end
                end
                -- For hidden cdState modes, defer the evaluation by one
                -- frame. Blizzard's SetDesaturated fires inside the secure
                -- CDM chain where C_Spell.GetSpellCooldown can briefly
                -- disagree with Blizzard's own evaluation (charge spells
                -- report isActive while charges remain, GCD tail races).
                -- Deferring lets the API settle before we query it.
                if cse == "hiddenOnCD" or cse == "hiddenReady" or cse == "lowerAlphaOnCD" then
                    if not fd._cdStatePending then
                        fd._cdStatePending = CreateFrame("Frame")
                        fd._cdStatePending:Hide()
                    end
                    fd._cdStatePending.cse = cse
                    -- Captured at arm time (a setting, not volatile); only lowerAlphaOnCD reads it.
                    fd._cdStatePending.lowAlpha = (ss2 and ss2.cdStateLowerAlpha) or 0.5
                    -- Shift-Icons variant: the evaluator also maintains the
                    -- bar-relayout flag (cleared for the non-shift modes).
                    fd._cdStatePending.shift = cseShift
                    fd._cdStatePending:SetScript("OnUpdate", function(self)
                        self:Hide()
                        local fc3 = _ecmeFC[frame]
                        local sid3 = fc3 and fc3.spellID
                        local bk3 = fc3 and fc3.barKey
                        if not sid3 or not bk3 then return end
                        local liveSid = sid3
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            liveSid = C_SpellBook.FindSpellOverrideByID(sid3) or sid3
                        end
                        local cseInfo = C_Spell.GetSpellCooldown(liveSid)
                        local onCD = cseInfo and cseInfo.isActive and not cseInfo.isOnGCD
                        local myCse = self.cse
                        local bd3 = barDataByKey and barDataByKey[bk3]
                        local baseA = ns.IconShownAlpha(fc3, bd3)
                        if myCse == "lowerAlphaOnCD" then
                            -- Lowered (not hidden): reuse _cdStateHidden as the
                            -- "cd-state owns this alpha" flag so the opacity appliers
                            -- leave the lowered value in place, exactly like hiddenOnCD.
                            -- A visibility-hidden bar (baseA 0) stays at 0 in both states.
                            frame:SetAlpha(baseA == 0 and 0
                                or (onCD and (self.lowAlpha or 0.5) or baseA))
                            if fc3 then
                                fc3._cdStateHidden = onCD or false
                                if ns.SetCdStateShiftHidden then
                                    ns.SetCdStateShiftHidden(fc3, false)
                                end
                            end
                        else
                            local hide
                            if myCse == "hiddenOnCD" then
                                hide = onCD
                            else
                                hide = not onCD
                            end
                            frame:SetAlpha(hide and 0 or baseA)
                            if fc3 then
                                fc3._cdStateHidden = hide or false
                                if ns.SetCdStateShiftHidden then
                                    ns.SetCdStateShiftHidden(fc3, self.shift and hide or false)
                                end
                            end
                        end
                    end)
                    fd._cdStatePending:Show()
                    return
                end
                -- Query cooldown on the live override (e.g. Shimmer, not
                -- Blink) so charge-based replacements report correctly.
                local liveSid = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    liveSid = C_SpellBook.FindSpellOverrideByID(sid2) or sid2
                end
                local cseInfo = C_Spell.GetSpellCooldown(liveSid)
                local onCD = cseInfo and cseInfo.isActive and not cseInfo.isOnGCD
                if cse == "pixelGlowReady" or cse == "buttonGlowReady" then
                    -- Plain CD Ready Glow: cooldown state only, decided right
                    -- here -- no usability reads, no deferral, no events for
                    -- genuine Blizzard frames (Blizzard calls SetDesaturated on
                    -- them at every cd transition, re-firing this hook).
                    -- EUI's own custom frames (racials / trinkets / potions /
                    -- custom spells) instead drive desaturation via
                    -- SetDesaturation(float), which does NOT trigger this
                    -- SetDesaturated hook -- so on those the glow would never
                    -- re-evaluate and would stay lit through the whole cooldown.
                    -- Register just those for the event-driven cooldown watch
                    -- (its loop handles plain variants too); Blizzard frames keep
                    -- the zero-event path.
                    if (frame._isRacialFrame or frame._isTrinketFrame or frame._isPresetFrame
                        or frame._isItemPresetFrame or frame._isCustomSpellFrame)
                        and ns.CDGlowWatch then
                        ns.CDGlowWatch(frame)
                    end
                    -- Pool reassignment: glow state inherited from a previous
                    -- spell on this frame belongs to that spell -- reset now.
                    if fd._cdGlowBoundSid ~= sid2 then
                        fd._cdGlowBoundSid = sid2
                        if fd._cdStateGlowOn then
                            ns.StopNativeGlow(fd.glowOverlay)
                            fd._cdStateGlowOn = false
                        end
                    end
                    if not onCD then
                        if fd.glowOverlay and not fd._cdStateGlowOn then
                            local style = cse == "pixelGlowReady" and 1 or 3
                            local gr, gg, gb = ns.ResolveGlowColor(ss2)
                            ns.StartNativeGlow(fd.glowOverlay, style, gr or 1, gg or 1, gb or 1)
                            fd._cdStateGlowOn = true
                        end
                    elseif fd._cdStateGlowOn then
                        if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                        fd._cdStateGlowOn = false
                    end
                elseif cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable" then
                    -- Resource Aware CD Ready Glow: also requires the spell to
                    -- be castable (resources/form/lockout).
                    -- Pool reassignment reset, same as the plain variants.
                    if fd._cdGlowBoundSid ~= sid2 then
                        fd._cdGlowBoundSid = sid2
                        if fd._cdStateGlowOn then
                            ns.StopNativeGlow(fd.glowOverlay)
                            fd._cdStateGlowOn = false
                        end
                    end
                    -- Track this frame for the event-driven re-evaluation loop.
                    -- The loop's events stay unregistered until the first watch,
                    -- so the whole system is inert unless a Resource Aware glow
                    -- is actually configured somewhere.
                    if ns.CDGlowWatch then ns.CDGlowWatch(frame) end
                    -- Defer the actual decision by one frame, same as
                    -- hiddenOnCD/hiddenReady above: SetDesaturated fires inside
                    -- Blizzard's secure CDM chain where C_Spell.IsSpellUsable can
                    -- return stale values. The OnUpdate script is installed ONCE
                    -- per frame object -- this hook fires on every repaint
                    -- (range/resource tints), so the per-fire work must stay at
                    -- plain field writes, never closure creation.
                    local pending = fd._cdStateGlowPending
                    if not pending then
                        pending = CreateFrame("Frame")
                        pending:Hide()
                        fd._cdStateGlowPending = pending
                        pending:SetScript("OnUpdate", function(self)
                            self:Hide()
                            -- Re-read the cooldown now instead of trusting a value
                            -- sampled inside the secure chain a frame ago (GCD
                            -- transients misreport isActive there).
                            local ci = C_Spell.GetSpellCooldown(self.sid)
                            local pOnCD = ci and ci.isActive and not ci.isOnGCD
                            local isUsable
                            if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
                                -- Loading-screen settle window: IsSpellUsable is not
                                -- trustworthy yet. Glow from cooldown state alone
                                -- (pre-usability behavior); the queued post-settle
                                -- pass re-evaluates with real data.
                                isUsable = true
                            else
                                -- nil = API has no data for this spell -> treat as
                                -- not usable; a later event re-evaluates.
                                isUsable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(self.sid)
                            end
                            local shouldGlow = (not pOnCD) and (isUsable == true)
                            if shouldGlow then
                                if fd.glowOverlay and not fd._cdStateGlowOn then
                                    local style = self.cse == "pixelGlowReadyUsable" and 1 or 3
                                    local gr, gg, gb = ns.ResolveGlowColor(self.ss2)
                                    ns.StartNativeGlow(fd.glowOverlay, style, gr or 1, gg or 1, gb or 1)
                                    fd._cdStateGlowOn = true
                                end
                            elseif fd._cdStateGlowOn then
                                if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                                fd._cdStateGlowOn = false
                            end
                        end)
                    end
                    pending.cse = cse
                    pending.sid = liveSid
                    pending.ss2 = ss2
                    pending:Show()
                end
            end)
        end

        -- Desaturate When Not Active: additive hook on SetDesaturated AND
        -- SetDesaturation (Blizzard re-saturates ready icons via either, on CD-end
        -- and ticks). Re-applies our desaturation whenever the spell is NOT in its
        -- active state, read LIVE from the swipe color (fd._wasActive is stale --
        -- the swipe block doesn't re-run on some falloffs, e.g. DoT expiry). The
        -- secret arg is never read; the _isProcessingOverride guard bounds
        -- recursion and keeps it from fighting the swipe block's own SetDesaturated.
        --
        -- ZERO-COST WHEN UNUSED: the very first line is a single flag check, so
        -- for anyone who never enables the setting every hook fire returns
        -- immediately -- no frame/spell resolution runs. ns._cdmAnyDesatNotActive
        -- is flipped on only when a spell actually uses the setting (swipe block /
        -- options setValue).
        if fd.tex and not fd._desatNotActiveHooked then
            fd._desatNotActiveHooked = true
            local function _maintainDesat()
                if not ns._cdmAnyDesatNotActive then return end
                if fd._isProcessingOverride then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                if not sid2 or not bk2 then return end
                local ss2 = ResolveSpellSettings(frame, sid2, ns.GetBarSpellData(bk2))
                if not (ss2 and ss2.desatNotActive) then
                    -- Setting turned off: re-saturate if WE greyed this icon, so it
                    -- doesn't stay desaturated until the next cooldown event.
                    if fd._desatNA then
                        fd._isProcessingOverride = true
                        fd.tex:SetDesaturated(false)
                        fd._isProcessingOverride = false
                        fd._desatNA = nil
                    end
                    return
                end
                local isAct = false
                local sc = frame.cooldownSwipeColor
                if sc and type(sc) ~= "number" and sc.GetRGBA then
                    local r = sc:GetRGBA()
                    if type(r) == "number" and not issecretvalue(r) then isAct = (r ~= 0) end
                end
                if isAct then return end
                fd._isProcessingOverride = true
                fd.tex:SetDesaturated(true)
                fd._desatNA = true
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", _maintainDesat)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", _maintainDesat)
            end
        end

        -- Audio Effect on CD Ready (cd/utility per-icon) is driven purely by the
        -- authoritative SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_CHARGES events via
        -- WatchCdReadySoundIfEnabled (called from DecorateFrame) -- deliberately NOT
        -- off a SetDesaturated visual hook. That hook fires at repaint moments
        -- unrelated to the real cooldown and sampled a transient GCD race
        -- (isActive=true / isOnGCD=false) that false-fired the sound.
    end

    hookFrameData[frame] = fd
    return fd
end

-------------------------------------------------------------------------------
--  CategorizeFrame
-------------------------------------------------------------------------------
local function CategorizeFrame(frame, viewerBarKey)
    local displaySID, baseSID = ResolveFrameSpellID(frame)
    if not displaySID or displaySID <= 0 then return nil, nil, nil end

    -- Lazy route resolution: ResolveCDIDToBar handles cache lookup,
    -- diversion-set match, and viewer-default fallback (defaultBar =
    -- viewerBarKey, the viewer this frame came from). Always returns a
    -- valid bar key for any non-nil cdID.
    local cdID = frame.cooldownID
    local claimBarKey = ResolveCDIDToBar(cdID, viewerBarKey)
    if claimBarKey then
        local claimBD = barDataByKey[claimBarKey]
        local claimType = claimBD and claimBD.barType or claimBarKey
        local viewerIsBuff = (viewerBarKey == "buffs")
        local claimIsBuff  = (claimType == "buffs" or claimType == "custom_buff")
        -- Same family always routes. A BUFF viewer resolving to a CD/util bar is
        -- also honored: that only happens for an explicit HOSTED buff (the sole
        -- writer of a CD/util bar key into _divertedSpellsBuff is the hosted-buff
        -- pass in RebuildSpellRouteMap), so the buff's real frame reparents onto
        -- the CD/util bar just like on a buff bar. A CD viewer -> buff bar is still
        -- rejected (falls through) -- that direction is never wanted.
        if viewerIsBuff == claimIsBuff or viewerIsBuff then
            return claimBarKey, displaySID, baseSID
        end
        -- Type mismatch (CD viewer routing to a buff bar). Under the 1-spell-per-bar
        -- rule this can't happen via picker claims, but legacy data could trigger
        -- it. Fall through to the viewer's default bar so the frame still renders.
    end
    return viewerBarKey, displaySID, baseSID
end

-------------------------------------------------------------------------------
--  Trinket Frames
-------------------------------------------------------------------------------
local _trinketFrames = {}
ns._trinketFrames = _trinketFrames
local _trinketItemCache = { [13] = nil, [14] = nil }

local function GetOrCreateTrinketFrame(slotID)
    local f = _trinketFrames[slotID]
    if f then return f end

    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    f:Hide()
    f:EnableMouse(false)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.Icon = tex
    f._tex = tex

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:EnableMouse(false)
    if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
    if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
    -- On-use trinket cooldowns fire no event at natural expiry, so the CD-driven
    -- re-saturate (UpdateTrinketCooldown) would not run at the ready edge while
    -- the CD-ready glow lit up immediately -- same lag as the item preset frames.
    -- Re-run the trinket CD check at the expiry edge to clear the desaturation.
    cd:SetScript("OnCooldownDone", function()
        if ns.UpdateTrinketCooldown then ns.UpdateTrinketCooldown(slotID) end
    end)
    f.Cooldown = cd
    f._cooldown = cd

    f._isTrinketFrame = true
    f._trinketSlot = slotID
    f.cooldownID = nil
    f.cooldownInfo = nil
    f.layoutIndex = (slotID == 13 and 99990) or (slotID == 14 and 99991)
        or (99900 + slotID)
    f.auraInstanceID = nil
    f.cooldownDuration = 0

    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    f:SetScript("OnEnter", function(self)
        local ffc = _ecmeFC[self]
        local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
        if not bd2 or not bd2.showTooltip then return end
        -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin); a
        -- custom frame's explicit content population would otherwise re-show the
        -- tip after the global suppression hook hid it.
        if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
           and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        local itemID = GetInventoryItemID("player", self._trinketSlot)
        if itemID then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            -- Prefer the equipped item's link so the tooltip reflects the actual
            -- upgrade/bonus IDs (real item level + stats) rather than the base item.
            -- SetItemByID is only a fallback if no link is available.
            local link = GetInventoryItemLink("player", self._trinketSlot)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetItemByID(itemID)
            end
            -- Re-assert the cursor anchor after content is set (see helper notes):
            -- the item content-setter can drop the tip's cursor anchor, so without
            -- this it never appears while "Anchor to Cursor" is on. No-op otherwise.
            if EllesmereUI and EllesmereUI._repointTooltipAtCursor then
                EllesmereUI._repointTooltipAtCursor(GameTooltip)
            end
            GameTooltip:Show()
            -- This is our own already-equipped trinket, so the side-by-side
            -- comparison (shopping) tooltips are just noise -- hide them after the
            -- tip is shown. Done here rather than by toggling the alwaysCompareItems
            -- CVar: mutating a user setting on every combat-time hover is wasteful
            -- and leaks the "off" state if anything errors mid-build.
            if GameTooltip_HideShoppingTooltips then
                GameTooltip_HideShoppingTooltips(GameTooltip)
            end
        end
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    _trinketFrames[slotID] = f
    return f
end

local function UpdateTrinketFrame(slotID)
    local f = _trinketFrames[slotID]
    if not f then return end
    local itemID = GetInventoryItemID("player", slotID)
    _trinketItemCache[slotID] = itemID
    if not itemID then
        f:Hide()
        return
    end
    local icon = C_Item.GetItemIconByID(itemID)
    if icon and f._tex then f._tex:SetTexture(icon) end
    local _, spellID = C_Item.GetItemSpell(itemID)
    f._trinketSpellID = spellID
    if slotID ~= 13 and slotID ~= 14 then
        -- User-added equipment slot: the use effect usually comes from an
        -- ENCHANT (engineering tinkers like Nitro Boosts), which exists only
        -- on the equipped INSTANCE -- the base item has no use spell, so the
        -- trinket path's GetItemSpell/GetItemByID scan can never see it.
        -- Scan the instance tooltip for a localized "Use:" line instead.
        local hasUse = nil
        local tip = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
            and C_TooltipInfo.GetInventoryItem("player", slotID)
        if tip and tip.lines then
            hasUse = false
            local prefix = ITEM_SPELL_TRIGGER_ONUSE
            for _, tipLine in ipairs(tip.lines) do
                local lt = tipLine.leftText
                if lt and prefix and lt:sub(1, #prefix) == prefix then
                    hasUse = true
                    break
                end
            end
        end
        if spellID and spellID > 0 then
            -- Base item carries its own use spell (on-use gear).
            f._trinketIsOnUse = true
            f._slotScanPending = nil
        elseif hasUse == nil then
            -- Tooltip data not cached yet: keep the previous state and let
            -- the login/equip retry timers re-run the scan.
            f._slotScanPending = true
        else
            f._trinketIsOnUse = hasUse
            f._slotScanPending = nil
        end
        return
    end
    local isRealOnUse = false
    local scanConclusive = false
    if spellID and spellID > 0 then
        local locale = GetLocale()
        if locale == "enUS" or locale == "enGB" then
            local tipData = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
            if tipData and tipData.lines then
                scanConclusive = true
                for _, tipLine in ipairs(tipData.lines) do
                    local lt = tipLine.leftText
                    if lt and lt:find("Cooldown%)") then
                        local cdStr = lt:match("%((.+Cooldown)%)")
                        if cdStr then
                            local totalSec = 0
                            for num, unit in cdStr:gmatch("(%d+)%s*(%a+)") do
                                local n = tonumber(num)
                                if n then
                                    local u = unit:lower()
                                    if u == "min" then totalSec = totalSec + n * 60
                                    elseif u == "sec" then totalSec = totalSec + n
                                    elseif u == "hr" or u == "hour" then totalSec = totalSec + n * 3600
                                    end
                                end
                            end
                            if totalSec >= 10 then isRealOnUse = true end
                        end
                    end
                end
            end
        else
            isRealOnUse = true
            scanConclusive = true
        end
    else
        scanConclusive = (spellID == nil or spellID == 0)
    end
    if scanConclusive then
        f._trinketIsOnUse = isRealOnUse
    end
end
ns.UpdateTrinketFrame = UpdateTrinketFrame

local function UpdateTrinketCooldown(slotID)
    local f = _trinketFrames[slotID]
    if not f or not f._trinketIsOnUse then return false end
    local start, dur, enable = GetInventoryItemCooldown("player", slotID)
    if start and dur and dur > 1.5 and enable == 1 then
        f._cooldown:SetCooldown(start, dur)
        if f._tex then f._tex:SetDesaturated(true) end
        return true
    else
        f._cooldown:Clear()
        if f._tex then f._tex:SetDesaturated(false) end
        return false
    end
end
ns.UpdateTrinketCooldown = UpdateTrinketCooldown

local _trinketEventFrame = CreateFrame("Frame")
_trinketEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
_trinketEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_trinketEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- True when a slot frame's on-use detection needs another pass: trinkets whose
-- item has a spell the tooltip scan couldn't confirm yet, and user-added slots
-- whose instance tooltip wasn't cached (enchant/tinker lines).
local function SlotScanIncomplete(f)
    return (f._trinketSpellID and not f._trinketIsOnUse) or f._slotScanPending
end

_trinketEventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 13 or arg1 == 14 or _trinketFrames[arg1] then
            UpdateTrinketFrame(arg1)
            if ns.QueueReanchor then ns.QueueReanchor() end
            local f = _trinketFrames[arg1]
            if f and SlotScanIncomplete(f) then
                local slot = arg1
                C_Timer.After(1, function()
                    UpdateTrinketFrame(slot)
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateTrinketFrame(13)
        UpdateTrinketFrame(14)
        for slot in pairs(_trinketFrames) do
            if slot ~= 13 and slot ~= 14 then UpdateTrinketFrame(slot) end
        end
        -- Tooltip data may not be cached yet on login, causing on-use
        -- detection to fail. Retry only for slots whose scan is incomplete
        -- (tooltip wasn't ready).
        local needsRetry = false
        for _, f in pairs(_trinketFrames) do
            if SlotScanIncomplete(f) then needsRetry = true end
        end
        if needsRetry then
            C_Timer.After(2, function()
                for slot in pairs(_trinketFrames) do
                    UpdateTrinketFrame(slot)
                end
                if ns.QueueReanchor then ns.QueueReanchor() end
            end)
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        for slot, f in pairs(_trinketFrames) do
            if f._trinketIsOnUse then
                UpdateTrinketCooldown(slot)
            end
        end
    end
end)

-------------------------------------------------------------------------------
--  CD Ready Glow: event-driven usability re-evaluation
--
--  Frames whose resolved cdStateEffect is a Resource Aware ready-glow
--  (pixelGlowReadyUsable / buttonGlowReadyUsable) are registered in a
--  watched set (ns.CDGlowWatch, called from the decoration paths). While the
--  set is non-empty, SPELL_UPDATE_COOLDOWN + UNIT_POWER_FREQUENT (player)
--  drive a dirty flag; a hidden frame re-evaluates ONLY the watched frames on
--  the next OnUpdate, then hides again. While the set is empty, no events are
--  registered and nothing runs -- the whole system is zero-cost unless a
--  ready-glow effect is actually configured somewhere.
--
--  SPELL_UPDATE_USABLE alone is not reliable for all resource types (e.g.
--  Fury), so cooldown + power events stand in for it. UNIT_POWER_FREQUENT
--  (not UNIT_POWER_UPDATE) is needed so continuous regen (energy ticking up
--  toward a spell's cost) re-evaluates the glow without waiting for a
--  discrete spend/gain event; the dirty flag caps the work at once per frame.
--
--  During the loading-screen settle window (ns._cdmSoundSuppressed, shared
--  with the CDM sound system) API answers are not trustworthy: the flush
--  keeps current state and retries shortly, and the first post-window pass
--  is authoritative. That pass is what clears a glow that came up stale
--  across a /reload (started by a decoration path before usability could be
--  read).
-------------------------------------------------------------------------------
do
    local _cdGlowWatched = setmetatable({}, { __mode = "k" })  -- frame -> true
    local _cdGlowDirty = false
    local _cdGlowEventsOn = false
    local _cdGlowRetryPending = false

    local _cdGlowUpdateFrame = CreateFrame("Frame")
    _cdGlowUpdateFrame:Hide()
    local _cdGlowEventFrame = CreateFrame("Frame")

    local function SetGlowEventsRegistered(on)
        if on == _cdGlowEventsOn then return end
        _cdGlowEventsOn = on
        if on then
            _cdGlowEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            _cdGlowEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        else
            _cdGlowEventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
            _cdGlowEventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
        end
    end

    local function QueueCDGlowUpdate()
        if _cdGlowDirty then return end
        _cdGlowDirty = true
        _cdGlowUpdateFrame:Show()
    end

    -- Register a frame whose resolved cdStateEffect is a Resource Aware
    -- ready-glow. Called
    -- from the decoration paths (DecorateFrame's SetDesaturated hook and
    -- RefreshCDMIconAppearance). The flush below prunes entries whose effect
    -- or claim went away and unregisters the events once nothing is watched.
    function ns.CDGlowWatch(frame)
        if not _cdGlowWatched[frame] then
            _cdGlowWatched[frame] = true
            SetGlowEventsRegistered(true)
        end
    end

    _cdGlowUpdateFrame:SetScript("OnUpdate", function(self)
        self:Hide()
        _cdGlowDirty = false
        if not next(_cdGlowWatched) then
            SetGlowEventsRegistered(false)
            return
        end
        local hfd = ns._hookFrameData
        local efc = ns._ecmeFC
        local RSP = ns.ResolveSpellSettings
        if not hfd or not efc or not RSP then return end
        -- Settle window: keep current state, retry until the window ends;
        -- the first post-window pass is the authoritative one.
        if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
            if not _cdGlowRetryPending then
                _cdGlowRetryPending = true
                C_Timer.After(1, function()
                    _cdGlowRetryPending = false
                    QueueCDGlowUpdate()
                end)
            end
            return
        end
        for frame in pairs(_cdGlowWatched) do
            local fd = hfd[frame]
            local fc2 = efc[frame]
            local sid2 = fc2 and fc2.spellID
            local bk2 = fc2 and fc2.barKey
            local keep = false
            -- Preset frames are owned by the Fake-Active engine (see the guard in
            -- the SetDesaturated hook); never let the spell-cooldown path drive
            -- their glow. keep=false below stops any leftover glow and unwatches.
            if fd and fd.glowOverlay and sid2 and bk2
               and not (ns.PresetHasCdState and ns.PresetHasCdState(frame)) then
                local ss2 = RSP(frame, sid2, ns.GetBarSpellData(bk2))
                local cse2 = ss2 and ss2.cdStateEffect
                local plainGlow = cse2 == "pixelGlowReady" or cse2 == "buttonGlowReady"
                local usableGlow = cse2 == "pixelGlowReadyUsable" or cse2 == "buttonGlowReadyUsable"
                if plainGlow or usableGlow then
                    keep = true
                    -- Pool reassignment: glow state inherited from a previous
                    -- spell on this frame belongs to that spell -- reset now.
                    if fd._cdGlowBoundSid ~= sid2 then
                        fd._cdGlowBoundSid = sid2
                        if fd._cdStateGlowOn then
                            ns.StopNativeGlow(fd.glowOverlay)
                            fd._cdStateGlowOn = false
                        end
                    end
                    local liveSid = sid2
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        liveSid = C_SpellBook.FindSpellOverrideByID(sid2) or sid2
                    end
                    local ci = C_Spell.GetSpellCooldown(liveSid)
                    local onCD = ci and ci.isActive and not ci.isOnGCD
                    local shouldGlow
                    if onCD then
                        -- On cooldown always stops the glow -- a safety net
                        -- independent of the SetDesaturated hook, in case that
                        -- hook doesn't fire for a given transition (it never does
                        -- for EUI custom frames -- they use SetDesaturation).
                        shouldGlow = false
                    elseif usableGlow then
                        -- Resource Aware: also require castability (resources,
                        -- form, lockout). nil = no data yet -> not usable.
                        shouldGlow = (C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(liveSid)) == true
                    else
                        -- Plain: cooldown state only.
                        shouldGlow = true
                    end
                    if shouldGlow then
                        if not fd._cdStateGlowOn then
                            local style = (cse2 == "pixelGlowReady" or cse2 == "pixelGlowReadyUsable") and 1 or 3
                            local gr, gg, gb = ns.ResolveGlowColor(ss2)
                            ns.StartNativeGlow(fd.glowOverlay, style, gr or 1, gg or 1, gb or 1)
                            fd._cdStateGlowOn = true
                        end
                    elseif fd._cdStateGlowOn then
                        ns.StopNativeGlow(fd.glowOverlay)
                        fd._cdStateGlowOn = false
                    end
                end
            end
            if not keep then
                -- Effect removed, spell unassigned, or frame released back to
                -- the pool: stop any leftover glow and drop the watch. Events
                -- unregister once the set drains (checked below and on the
                -- next queued flush).
                _cdGlowWatched[frame] = nil
                if fd and fd._cdStateGlowOn then
                    if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                    fd._cdStateGlowOn = false
                end
            end
        end
        if not next(_cdGlowWatched) then
            SetGlowEventsRegistered(false)
        end
    end)

    -- One re-evaluation pass on the next frame. Called after rebuilds
    -- (FullCDMRebuild) and by the event listeners; no-ops instantly when
    -- nothing is watched.
    ns.QueueCDGlowResourceCheck = QueueCDGlowUpdate

    _cdGlowEventFrame:SetScript("OnEvent", function()
        QueueCDGlowUpdate()
    end)
end

-------------------------------------------------------------------------------
--  Desaturation curve for custom frames (taint-safe).
--  Step curve: 0 when no cooldown, 1 immediately when cooldown active.
--  EvaluateRemainingDuration on a DurationObject handles secret values
--  internally so we never compare secret numbers ourselves.
-------------------------------------------------------------------------------
local _desatCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    _desatCurve = C_CurveUtil.CreateCurve()
    _desatCurve:SetType(Enum.LuaCurveType.Step)
    _desatCurve:AddPoint(0, 0)
    _desatCurve:AddPoint(0.001, 1)
end

local function ApplySpellDesaturation(f, durObj)
    if not f._tex then return end
    if durObj and _desatCurve and durObj.EvaluateRemainingDuration then
        local val = durObj:EvaluateRemainingDuration(_desatCurve, 0)
        f._tex:SetDesaturation(val or 0)
    else
        f._tex:SetDesaturation(0)
    end
end

-------------------------------------------------------------------------------
--  Preset/Custom Frames
-------------------------------------------------------------------------------
local _presetFrames = {}
ns._presetFrames = _presetFrames

-------------------------------------------------------------------------------
--  Always Show Buffs placeholders
--  Our-owned icon frames that hold an INACTIVE tracked buff's slot so the buff
--  "always shows" (greyed) without editing Blizzard's Edit Mode layout. Mirrors
--  _presetFrames (a UIParent Frame + .Icon + .Cooldown) so the existing
--  DecorateFrame / LayoutCDMBar pipeline styles and positions them like any
--  real icon. Keyed barKey:ph:spellID. Never armed with a cooldown (no strobe).
-------------------------------------------------------------------------------
local _placeholderFrames = {}
ns._placeholderFrames = _placeholderFrames

-- Hide every placeholder. Called once at the start of each collect pass; the
-- pass then re-shows only the placeholders it injects, so a placeholder whose
-- buff went active, or whose bar was toggled off/disabled, ends up hidden.
local function HideAllPlaceholders()
    for _, f in pairs(_placeholderFrames) do
        if f:IsShown() then f:Hide() end
    end
end
ns.HideAllPlaceholders = HideAllPlaceholders

-- Injected custom/preset buff own-frames (buff-family bars). Tracked so the
-- collect pass can hide them all up front and re-show only the active ones,
-- exactly like placeholders -- the buff-phase cleanup loops only disable swipe
-- (correct for Blizzard pool frames, which must never be Hidden), so OUR frames
-- need their own hide pass or an inactive/expired/orphaned one would linger.
local _injectedCustomBuffFrames = setmetatable({}, { __mode = "k" })
local function HideAllInjectedCustomBuffs()
    for f in pairs(_injectedCustomBuffFrames) do
        if f:IsShown() then f:Hide() end
    end
end
ns.HideAllInjectedCustomBuffs = HideAllInjectedCustomBuffs

local function GetOrCreatePlaceholderFrame(barKey, spellID, iconID)
    local fkey = barKey .. ":ph:" .. spellID
    local f = _placeholderFrames[fkey]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(36, 36); f:Hide()
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.Icon = tex; f._tex = tex
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true); cd:EnableMouse(false)
        if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
        if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
        cd:Clear()  -- permanent placeholder: never arm a 0-duration swipe (strobe)
        f.Cooldown = cd; f._cooldown = cd
        f._isPlaceholderFrame = true
        f._phSpellID = spellID
        -- Never claimed/routed like a Blizzard frame; carries no live aura state.
        f.cooldownID = nil; f.cooldownInfo = nil
        f.auraInstanceID = nil; f.wasSetFromAura = nil
        f:SetScript("OnEnter", function(self)
            local ffc = _ecmeFC[self]
            local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
            if not bd2 or not bd2.showTooltip then return end
            if not self._phSpellID then return end
            -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin).
            if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
               and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetSpellByID(self._phSpellID)
            if EllesmereUI and EllesmereUI._repointTooltipAtCursor then
                EllesmereUI._repointTooltipAtCursor(GameTooltip)
            end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        _placeholderFrames[fkey] = f
    end
    if iconID then f._tex:SetTexture(iconID) end
    return f
end

-- Own-frame for a custom/preset buff (cast-timer driven) on a buff-family bar.
-- Created once per (barKey, spellID); reused across reanchors. Mirrors the frame
-- the legacy custom_buff renderer builds, but the buff-phase injection drives its
-- cooldown swipe and lets CollectAndReanchor slot it next to Blizzard buff frames.
-- OnCooldownDone queues a reanchor so the expired buff drops out of the layout.
local function GetOrCreateCustomBuffFrame(barKey, sid)
    local fkey = barKey .. ":custombuff:" .. sid
    local f = _presetFrames[fkey]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(36, 36); f:Hide()
        f:EnableMouse(false)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.Icon = tex; f._tex = tex
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
        cd:SetReverse(true)
        f.Cooldown = cd; f._cooldown = cd
        f._isCustomSpellFrame = true
        f._isCustomBuffFrame = true
        f.cooldownID = nil; f.cooldownInfo = nil
        cd:HookScript("OnCooldownDone", function()
            -- Re-lay-out the bar so the expired buff is removed. Also poke the
            -- legacy custom_buff updater (harmless for buff bars).
            if ns.QueueCustomBuffUpdate then C_Timer.After(0, ns.QueueCustomBuffUpdate) end
            if ns.QueueReanchor then C_Timer.After(0, ns.QueueReanchor) end
        end)
        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
        if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
        _presetFrames[fkey] = f
        _injectedCustomBuffFrames[f] = true
    end
    return f
end
ns.GetOrCreateCustomBuffFrame = GetOrCreateCustomBuffFrame

-- Own-frame for an item (icon + item cooldown + bag count), shared by the
-- CD/utility injection (Phase 3) and the buff-family injection. Created once per
-- (barKey, itemID). Uses the preset icon when known, else the live item icon for
-- arbitrary user-added IDs. Returns nil if the icon isn't loaded yet.
local function GetOrCreateItemPresetFrame(barKey, itemID)
    local fkey = barKey .. ":item:" .. itemID
    local f = _presetFrames[fkey]
    if f then return f end

    local itemPresets = ns.CDM_ITEM_PRESETS
    local preset
    if itemPresets then
        for _, pr in ipairs(itemPresets) do
            if pr.itemID == itemID then preset = pr; break end
            if pr.altItemIDs then
                for _, alt in ipairs(pr.altItemIDs) do
                    if alt == itemID then preset = pr; break end
                end
            end
        end
    end
    local icon = preset and preset.icon or C_Item.GetItemIconByID(itemID)
    if not icon then return nil end

    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36); f:Hide()
    -- Enable mouse motion (OnEnter/OnLeave) for tooltips but pass through clicks.
    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(); tex:SetTexture(icon)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.Icon = tex; f._tex = tex
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:EnableMouse(false)
    if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
    if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
    -- Item cooldowns fire no event when they naturally expire, so the
    -- desaturation pass (ProcessPresetCooldowns) would not re-run at the ready
    -- edge and the icon would stay greyed until some unrelated event marked the
    -- processor dirty. The CD-ready glow polls readiness continuously and lights
    -- up the instant the CD ends, so without this the pot glows while still
    -- desaturated. Poke the processor at the expiry edge so the next tick
    -- re-evaluates count/CD/lockout (a plain re-saturate would be wrong when the
    -- last charge was just used -- total==0 must keep it greyed).
    cd:SetScript("OnCooldownDone", function()
        if ns._MarkPresetCdDirty then ns._MarkPresetCdDirty() end
    end)
    f.Cooldown = cd; f._cooldown = cd
    f._isItemPresetFrame = true
    f._presetItemID = itemID; f._presetData = preset
    f.cooldownID = nil; f.cooldownInfo = nil
    f.layoutIndex = 99999
    local countFS = f:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyIconTextFont(countFS, GetCDMFont(), 11, "cdm")
    countFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
    f._itemCountText = countFS
    f:SetScript("OnEnter", function(self)
        if not self._presetItemID then return end
        local ffc = _ecmeFC[self]
        local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
        if not bd2 or not bd2.showTooltip then return end
        -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin).
        if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
           and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        -- Pot presets tooltip the resolved display variant (may be another
        -- rank / Fleeting / the swapped-in partner pot), not the primary.
        GameTooltip:SetItemByID(self._displayItemID or self._presetItemID)
        -- Re-assert the cursor anchor after content is set (item setters can drop
        -- it under "Anchor to Cursor", leaving the tip invisible). No-op otherwise.
        if EllesmereUI and EllesmereUI._repointTooltipAtCursor then
            EllesmereUI._repointTooltipAtCursor(GameTooltip)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    _presetFrames[fkey] = f
    return f
end
ns.GetOrCreateItemPresetFrame = GetOrCreateItemPresetFrame

-- ---------------------------------------------------------------------------
-- Dynamic potion display for the two combat-pot presets (Light's Potential /
-- Potion of Recklessness). The preset icon resolves to the best variant
-- actually in bags (preset.displayOrder, best first) and shows THAT variant's
-- icon, exact bag count, and tooltip -- 2 Fleeting pots show "2" even with 50
-- regular ones in the bank of another rank. With the profile-level "Swap
-- Light/Reckless Pots When Missing" toggle on, a preset whose own family is
-- fully out of bags resolves the partner family's chain instead. Identity is
-- untouched: the frame key, assigned-spell key, saved settings, and active
-- states all stay on the preset's primary item; only the DISPLAY resolves, so
-- a running cooldown swipe survives the icon swapping variants.
-- Re-resolution is generation-gated: bag events, the options toggle, and
-- profile changes bump/miss the gate; steady-state 10Hz ticks cost one compare.
local PotSwap = {}
do
    local byKey, byPrimary, chains

    function PotSwap.Enabled()
        local p = ECME and ECME.db and ECME.db.profile
        return (p and p.cdmBars and p.cdmBars.swapPotionsWhenMissing) == true
    end

    local function PresetByKey(key)
        if not byKey then
            byKey = {}
            for _, pr in ipairs(ns.CDM_ITEM_PRESETS or {}) do byKey[pr.key] = pr end
        end
        return byKey[key]
    end

    -- Preset for a pot's PRIMARY item id (nil for every non-pot preset).
    function PotSwap.ByPrimary(itemID)
        if not byPrimary then
            byPrimary = {}
            for _, pr in ipairs(ns.CDM_ITEM_PRESETS or {}) do
                if pr.displayOrder then byPrimary[pr.itemID] = pr end
            end
        end
        return byPrimary[itemID]
    end

    -- Ordered id list to walk for a preset: own displayOrder, with the partner
    -- family's appended while the swap toggle is on. Static data, built once
    -- per preset; the live toggle read just picks which cached list to return.
    function PotSwap.Chain(preset)
        if not chains then chains = {} end
        local c = chains[preset]
        if not c then
            c = { own = preset.displayOrder }
            local partner = preset.swapWith and PresetByKey(preset.swapWith)
            if partner and partner.displayOrder then
                local both = {}
                for i = 1, #preset.displayOrder do both[#both + 1] = preset.displayOrder[i] end
                for i = 1, #partner.displayOrder do both[#both + 1] = partner.displayOrder[i] end
                c.both = both
            end
            chains[preset] = c
        end
        return (c.both and PotSwap.Enabled()) and c.both or c.own
    end

    PotSwap.gen = 1
    function PotSwap.Bump() PotSwap.gen = PotSwap.gen + 1 end

    -- Resolve + stamp a pot-preset frame's display variant. Returns the display
    -- item id, or nil when the frame is not a resolving pot preset (every other
    -- item preset and user-added custom items -- their paths are untouched).
    -- The primary-id check matters: a user who manually adds one specific
    -- variant's item id gets that literal item, never the dynamic display.
    -- Nothing owned anywhere in the chain falls back to the primary item at
    -- count 0, so the icon keeps its slot (greyed) instead of vanishing.
    function PotSwap.Ensure(f)
        local preset = f._presetData
        if not (preset and preset.displayOrder and f._presetItemID == preset.itemID) then return nil end
        local en = PotSwap.Enabled()
        if f._potResolveGen == PotSwap.gen and f._potResolveSwap == en then
            return f._displayItemID
        end
        f._potResolveGen, f._potResolveSwap = PotSwap.gen, en
        local chain = PotSwap.Chain(preset)
        local id, count
        for i = 1, #chain do
            local c = C_Item.GetItemCount(chain[i], false, true) or 0
            if c > 0 then id, count = chain[i], c; break end
        end
        if not id then id, count = preset.itemID, 0 end
        f._displayCount = count
        if f._displayItemID ~= id then
            f._displayItemID = id
            local icon = (id == preset.itemID) and preset.icon
                or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
                or preset.icon
            if f._tex then f._tex:SetTexture(icon) end
        end
        return id
    end
end
-- FakeActive (cooldown-state poll + cast-trigger mapping) reads the swap-aware
-- chain for a pot preset's primary item id; nil for anything else.
ns.GetPresetPotChain = function(itemID)
    local pr = PotSwap.ByPrimary(itemID)
    return pr and PotSwap.Chain(pr) or nil
end
-- Options toggle: force every pot frame to re-resolve on the next pass.
ns._BumpPotResolveGen = PotSwap.Bump

-- Guard: after ENCOUNTER_END clears item-preset caches, subsequent events
-- fire before Blizzard has finished resetting potion CDs. Without this guard
-- the update loop re-caches stale cooldown data from C_Item.GetItemCooldown.
-- Uses a timestamp so the grace period works regardless of event ordering.
local _encounterResetUntil = 0

local _racialCdListener = CreateFrame("Frame")
_racialCdListener:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_racialCdListener:RegisterEvent("SPELL_UPDATE_CHARGES")
_racialCdListener:RegisterEvent("BAG_UPDATE_COOLDOWN")
_racialCdListener:RegisterEvent("BAG_UPDATE_DELAYED")
_racialCdListener:RegisterEvent("ENCOUNTER_END")
_racialCdListener:RegisterEvent("CHALLENGE_MODE_START")
_racialCdListener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_racialCdListener:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Combat lockout spellID -> itemID map (built once from presets)
local _combatLockoutSpells = {}
for _, preset in ipairs(ns.CDM_ITEM_PRESETS or {}) do
    if preset.combatLockout and preset.spellID then
        _combatLockoutSpells[preset.spellID] = preset.itemID
    end
end

-- Dirty flag: high-frequency events (SPELL_UPDATE_COOLDOWN, BAG_UPDATE_COOLDOWN)
-- just set this flag. The BuffTicker (10Hz) processes it, coalescing dozens of
-- per-GCD events into a single update pass.
local _presetCdDirty = false

-- The actual update work, called from BuffTicker at 10Hz max.
local function ProcessPresetCooldowns()
    _presetCdDirty = false
    local now = GetTime()
    for fkey, f in pairs(_presetFrames) do
        if f:IsShown() then
            if (f._isRacialFrame or f._isCustomSpellFrame) and not f._isCustomBuffFrame then
                -- Cache extracted spellID on the frame to avoid regex every tick
                local sid = f._cachedPresetSID
                if not sid then
                    local m = fkey:match(":(%d+)$")
                    sid = m and tonumber(m)
                    f._cachedPresetSID = sid
                end
                if sid then
                    local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
                    if durObj and f._cooldown and f._cooldown.SetCooldownFromDurationObject then
                        f._cooldown:SetCooldownFromDurationObject(durObj, true)
                    end
                    -- Skip desaturation when the spell is only on GCD
                    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
                    local onRealCD = cdInfo and cdInfo.isActive and not cdInfo.isOnGCD
                    if cdInfo and cdInfo.isOnGCD and not onRealCD then
                        if f._tex then f._tex:SetDesaturation(0) end
                    else
                        ApplySpellDesaturation(f, durObj)
                    end
                    -- Resource check: dim vertex color when not enough resources
                    -- Only for custom spells (not racials -- racials don't cost resources)
                    if f._isCustomSpellFrame and f._tex then
                        if not onRealCD then
                            local isUsable, notEnoughMana = C_Spell.IsSpellUsable(sid)
                            if notEnoughMana then
                                f._tex:SetVertexColor(0.5, 0.5, 1.0)
                            elseif not isUsable then
                                f._tex:SetVertexColor(0.4, 0.4, 0.4)
                            elseif f._lastVertexDim then
                                f._tex:SetVertexColor(1, 1, 1)
                            end
                            f._lastVertexDim = (not isUsable) or nil
                        elseif f._lastVertexDim then
                            f._tex:SetVertexColor(1, 1, 1)
                            f._lastVertexDim = nil
                        end
                    end
                    -- "Show Charges" (opt-in, CD/utility custom spells only):
                    -- Blizzard reports no charge frame for a manually-added spell,
                    -- so on request show its count -- the display charge count when
                    -- the spell actually has charges, else the cast/usable count.
                    -- Gated by ns._cdmAnyCustomForceCount + a lazy fontstring, so it
                    -- costs nothing unless a custom spell opts in. Rides this same
                    -- 10Hz-when-dirty pass -- no extra OnUpdate.
                    if ns._cdmAnyCustomForceCount and f._isCustomSpellFrame then
                        local fcF = _ecmeFC[f]
                        local bkF = fcF and fcF.barKey
                        local sdF = bkF and ns.GetBarSpellData and ns.GetBarSpellData(bkF)
                        local forceCount = sdF and sdF.customSpellForceCount and sdF.customSpellForceCount[sid]
                        if forceCount then
                            if not f._castCountText then
                                f._castCountText = f:CreateFontString(nil, "OVERLAY")
                                -- Match the bar's native stack/charge text
                                -- styling (font, size, color, anchor, X/Y
                                -- offset); RefreshCDMIconAppearance keeps it
                                -- in sync afterwards.
                                ns.StyleCustomChargeText(f, bkF)
                            end
                            local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
                            local n = (chargeInfo and C_Spell.GetSpellDisplayCount and C_Spell.GetSpellDisplayCount(sid))
                                or (C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(sid))
                            -- The count is a SECRET value in Midnight (cannot be read or
                            -- compared -- issecretvalue was making the old code bail), so
                            -- render it Blizzard's way: TruncateWhenZero turns it into a
                            -- display-safe string and drops it at zero, without reading
                            -- the value. pcall because it can throw; failure -> hide.
                            local ok, str
                            if C_StringUtil and C_StringUtil.TruncateWhenZero then
                                ok, str = pcall(C_StringUtil.TruncateWhenZero, n)
                            end
                            if ok and str then
                                f._castCountText:SetText(str)
                                if not f._castCountText:IsShown() then f._castCountText:Show() end
                            elseif f._castCountText:IsShown() then
                                f._castCountText:SetText("")
                                f._castCountText:Hide()
                            end
                        elseif f._castCountText and f._castCountText:IsShown() then
                            f._castCountText:SetText("")
                            f._castCountText:Hide()
                            f._lastCastCount = nil
                        end
                    end
                end
            elseif f._isItemPresetFrame and f._presetItemID and now >= _encounterResetUntil then
                -- Pot presets: re-resolve the display variant (generation-gated,
                -- one compare when nothing changed) and drive count/cooldown off
                -- the resolved chain. Every other item preset keeps the legacy
                -- primary-then-alts walk byte-identically.
                local dispID = PotSwap.Ensure(f)
                local itemID = dispID or f._presetItemID
                local potChain = dispID and PotSwap.Chain(f._presetData) or nil
                local getContainerCD = C_Container and C_Container.GetItemCooldown
                local start, dur
                if potChain then
                    -- Only the owned/used item id reports the shared potion
                    -- cooldown, so walk the full active chain (partner family
                    -- included while the swap toggle is on).
                    for i = 1, #potChain do
                        local cid = potChain[i]
                        if getContainerCD then start, dur = getContainerCD(cid) end
                        if not (start and dur and dur > 1.5) then start, dur = C_Item.GetItemCooldown(cid) end
                        if start and dur and dur > 1.5 then break end
                    end
                else
                    if getContainerCD then
                        start, dur = getContainerCD(itemID)
                    end
                    if not (start and dur and dur > 1.5) then
                        start, dur = C_Item.GetItemCooldown(itemID)
                    end
                    if not (start and dur and dur > 1.5) and f._presetData and f._presetData.altItemIDs then
                        for _, altID in ipairs(f._presetData.altItemIDs) do
                            if getContainerCD then start, dur = getContainerCD(altID) end
                            if not (start and dur and dur > 1.5) then start, dur = C_Item.GetItemCooldown(altID) end
                            if start and dur and dur > 1.5 then break end
                        end
                    end
                end
                if start and dur and dur > 1.5 then
                    f._cooldown:SetCooldown(start, dur)
                    f._cdStart = start; f._cdDur = dur
                elseif not (f._cdStart and f._cdDur and (now < f._cdStart + f._cdDur)) then
                    f._cooldown:Clear()
                    f._cdStart = nil; f._cdDur = nil
                end
                local itemOnCD = f._cdStart and f._cdDur and (now < f._cdStart + f._cdDur)
                local total
                if dispID then
                    -- Exact count of the resolved variant only -- never a sum
                    -- across ranks/families (2 Fleeting shows 2, even with 50
                    -- regular rank 1s in the bags).
                    total = f._displayCount or 0
                else
                    total = C_Item.GetItemCount(f._presetItemID, false, true) or 0
                    if total == 0 and f._presetData and f._presetData.altItemIDs then
                        for _, altID in ipairs(f._presetData.altItemIDs) do
                            total = total + (C_Item.GetItemCount(altID, false, true) or 0)
                        end
                    end
                end
                if f._itemCountText then
                    local fc = _ecmeFC[f]
                    local bk = fc and fc.barKey
                    local bd = bk and barDataByKey[bk]
                    local showIC = not bd or bd.showItemCount ~= false
                    local displayCount = showIC
                        and ((total > 1) and total
                        or (total == 1 and f._presetData and f._presetData.combatLockout) and total
                        or nil) or nil
                    if displayCount then
                        if f._lastItemCount ~= displayCount then
                            f._itemCountText:SetText(displayCount)
                            f._lastItemCount = displayCount
                        end
                        if not f._itemCountText:IsShown() then f._itemCountText:Show() end
                    elseif f._lastItemCount then
                        f._itemCountText:SetText("")
                        f._itemCountText:Hide()
                        f._lastItemCount = nil
                    end
                end
                local shouldDesat = (total == 0 or itemOnCD or f._inCombatLockout) and true or false
                if shouldDesat ~= f._lastDesat then
                    f._lastDesat = shouldDesat
                    if f._tex then f._tex:SetDesaturated(shouldDesat) end
                end
            end
        end
    end
    if QueueCustomBuffUpdate then QueueCustomBuffUpdate() end
end
ns._ProcessPresetCooldowns = ProcessPresetCooldowns
ns._isPresetCdDirty = function() return _presetCdDirty end
-- Setter so the inject path can request a preset desaturation re-evaluation. A
-- full rebuild wipes and re-injects preset frames with no cached desat state; if
-- no game event (bag/cooldown/combat) follows -- e.g. an in-panel sync/import --
-- ProcessPresetCooldowns would never run and an unowned item would stay saturated.
ns._MarkPresetCdDirty = function() _presetCdDirty = true end

-- TEMP DEBUG: /cdmcc -- dumps why the "Show Charges" custom-spell count is / is
-- not displaying. Remove once diagnosed.
SLASH_EUICDMCC1 = "/cdmcc"
SlashCmdList["EUICDMCC"] = function()
    local function p(...) print("|cff66ccff[EUICC]|r", ...) end
    local function safe(v)
        if issecretvalue and issecretvalue(v) then return "<secret>" end
        return tostring(v)
    end
    p("gate _cdmAnyCustomForceCount =", tostring(ns._cdmAnyCustomForceCount),
      "| dirty =", tostring(_presetCdDirty))
    p("APIs: GetSpellCharges=", tostring(C_Spell and C_Spell.GetSpellCharges ~= nil),
      "GetSpellDisplayCount=", tostring(C_Spell and C_Spell.GetSpellDisplayCount ~= nil),
      "GetSpellCastCount=", tostring(C_Spell and C_Spell.GetSpellCastCount ~= nil))
    local count = 0
    for fkey, f in pairs(_presetFrames) do
        if f._isCustomSpellFrame and not f._isCustomBuffFrame then
            count = count + 1
            local sid = f._cachedPresetSID
            if not sid then local m = fkey:match(":(%d+)$"); sid = m and tonumber(m) end
            local fc = _ecmeFC[f]
            local bk = fc and fc.barKey
            local sd = bk and ns.GetBarSpellData and ns.GetBarSpellData(bk)
            local flag = sd and sd.customSpellForceCount and sd.customSpellForceCount[sid]
            local ci = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
            local disp = sid and C_Spell.GetSpellDisplayCount and C_Spell.GetSpellDisplayCount(sid)
            local cast = sid and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(sid)
            p(string.format("[%s] %s | bk=%s shown=%s flag=%s",
                tostring(sid), tostring(sid and C_Spell.GetSpellName(sid)),
                tostring(bk), tostring(f:IsShown()), tostring(flag)))
            local nEff = (ci and disp) or cast
            local tok, tstr
            if C_StringUtil and C_StringUtil.TruncateWhenZero then
                tok, tstr = pcall(C_StringUtil.TruncateWhenZero, nEff)
            end
            p(string.format("   forceCountTbl=%s charges=%s displayCount=%s castCount=%s",
                tostring(sd and sd.customSpellForceCount ~= nil),
                tostring(ci ~= nil), safe(disp), safe(cast)))
            p(string.format("   TruncateWhenZero: ok=%s -> %s | text=%s textShown=%s",
                tostring(tok), safe(tstr),
                tostring(f._castCountText ~= nil),
                tostring(f._castCountText and f._castCountText:IsShown())))
        end
    end
    if count == 0 then p("NO custom spell frames present (add one to a CD/utility bar first)") end
end

-- "Hide Items if Missing": detect when a tracked consumable's bag presence
-- flips (acquired or fully used up) for any bar that opted in, and queue a
-- reanchor so the injection pass re-evaluates and shows/hides it. Cheap: only
-- iterates the handful of injected preset frames, and only counts items for
-- frames whose owning bar has the setting on.
local function CheckItemPresenceForHide()
    local changed = false
    for _, f in pairs(_presetFrames) do
        if f._isItemPresetFrame and f._presetItemID then
            local bd = f._ownerBarKey and barDataByKey[f._ownerBarKey]
            if bd and bd.hideItemsIfMissing then
                local total
                if PotSwap.Ensure(f) then
                    -- Pot presets: present = the resolved chain owns anything
                    -- (partner family counts while the swap toggle is on).
                    total = f._displayCount or 0
                else
                    total = C_Item.GetItemCount(f._presetItemID, false, true) or 0
                    if total == 0 and f._presetData and f._presetData.altItemIDs then
                        for _, altID in ipairs(f._presetData.altItemIDs) do
                            total = total + (C_Item.GetItemCount(altID, false, true) or 0)
                        end
                    end
                end
                if (total > 0) ~= f._hidePresenceCached then changed = true end
            end
        end
    end
    if changed and ns.QueueReanchor then ns.QueueReanchor() end
end

_racialCdListener:SetScript("OnEvent", function(_, event, unit, _, spellID)
    -- Infrequent events: handle immediately and return
    if event == "BAG_UPDATE_DELAYED" then
        -- Bag contents changed: pot-preset display variants must re-resolve
        -- (before the presence check below, which reads the resolution).
        PotSwap.Bump()
        CheckItemPresenceForHide()
        _presetCdDirty = true
        return
    end
    if event == "ENCOUNTER_END" or event == "CHALLENGE_MODE_START" then
        if event == "CHALLENGE_MODE_START" or select(2, GetInstanceInfo()) == "raid" then
            for _, f in pairs(_presetFrames) do
                if f._isItemPresetFrame then
                    f._cdStart = nil; f._cdDur = nil; f._inCombatLockout = nil
                    if f._cooldown then f._cooldown:Clear() end
                    if f._tex then f._tex:SetDesaturated(false) end
                    f._lastDesat = false
                end
            end
            _encounterResetUntil = GetTime() + 3
        end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
        local targetItemID = spellID and _combatLockoutSpells[spellID]
        if targetItemID and InCombatLockdown() then
            for _, f in pairs(_presetFrames) do
                if f._isItemPresetFrame and f._presetItemID == targetItemID then
                    f._inCombatLockout = true
                    if f._cooldown then f._cooldown:Clear() end
                    if f._tex then f._tex:SetDesaturated(true) end
                    f._lastDesat = true
                end
            end
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        for _, f in pairs(_presetFrames) do
            if f._isItemPresetFrame and f._inCombatLockout then
                f._inCombatLockout = nil
            end
        end
        _presetCdDirty = true  -- refresh desaturation on combat end
        return
    end
    -- High-frequency events: just set dirty flag for BuffTicker to process
    _presetCdDirty = true
end)

-- Custom aura bar cast detection
local _pendingCastIDs = {}
-- Cast-timer state for custom/preset buffs, keyed "barKey:spellID". Declared
-- here (before CollectAndReanchor) so the buff-phase own-frame injection can
-- read the live timer to decide which custom buffs to render.
local _customAuraTimers = {}
local _customBuffDirty = false
local _customBuffFrame = CreateFrame("Frame")
_customBuffFrame:Hide()
local CUSTOM_BUFF_THROTTLE = 0.05
local _lastCustomBuffTime = 0
_customBuffFrame:SetScript("OnUpdate", function(self)
    if not _customBuffDirty then self:Hide(); return end
    local now = GetTime()
    if now - _lastCustomBuffTime < CUSTOM_BUFF_THROTTLE then return end
    _customBuffDirty = false
    _lastCustomBuffTime = now
    if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
end)

local function QueueCustomBuffUpdate()
    _customBuffDirty = true
    _customBuffFrame:Show()
end
ns.QueueCustomBuffUpdate = QueueCustomBuffUpdate

-- Bloodlust on a Custom Auras (icon) bar reuses the potion-preset machinery:
-- the Sated-debuff rising edge (detected in CdmBuffBars) emulates a "cast" of
-- the lust buff, so the existing self-timed icon + reverse swipe renders it with
-- no duplicate display code. Both faction IDs are flagged so a profile shared
-- across factions still resolves (only the bar's own ID is actually tracked).
local LUST_PRESET_SPELLS = { [2825] = true, [32182] = true }
ns.IsLustPresetSpell = function(sid) return LUST_PRESET_SPELLS[sid] == true end

-- Called from the lust listener's rising edge: mark the lust buff as "just cast"
-- so UpdateCustomBuffBars starts its 40s self-timed icon. A no-op for any bar not
-- tracking it (the pending flag is wiped each pass).
function ns.SignalLustCast()
    _pendingCastIDs[2825]  = true
    _pendingCastIDs[32182] = true
    QueueCustomBuffUpdate()
end

-- True if any enabled Custom Auras (custom_buff) bar tracks the lust buff, so the
-- shared Sated listener stays armed even with no Tracking Bar lust bar present.
function ns.AnyCustomAuraLust()
    local p = ECME and ECME.db and ECME.db.profile
    if not (p and p.cdmBars and p.cdmBars.bars) then return false end
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and (bd.barType == "custom_buff" or bd.barType == "buffs") then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if LUST_PRESET_SPELLS[sid] then return true end
                end
            end
        end
    end
    return false
end

-- Time Spiral "Free Move" preset: same emulated-cast trick as Bloodlust. The
-- glow-armed rising edge (CdmBuffBars _ensureTimeSpiralListener) calls this to
-- mark spell 374968 as "just cast" so the existing self-timed-icon path renders
-- a 10s Custom Auras (icon) display. A no-op for any bar not tracking it.
function ns.SignalTimeSpiralCast()
    _pendingCastIDs[374968] = true
    QueueCustomBuffUpdate()
end

-- Called from the Time Spiral glow-HIDE edge (proc consumed): expire any active
-- 374968 Custom Auras (icon) window now so the icon disappears with the glow
-- instead of riding out the full 10s. Clears every "barKey:374968" timer (the
-- suffix uniquely identifies the spell on any bar), then queues a refresh:
-- custom_buff bars hide their own-frame on the update, buff bars drop the
-- injected frame on the reanchor.
function ns.SignalTimeSpiralEnd()
    local suffix = ":374968"
    local n = #suffix
    local any = false
    for k in pairs(_customAuraTimers) do
        if type(k) == "string" and k:sub(-n) == suffix then
            _customAuraTimers[k] = nil
            any = true
        end
    end
    if any then
        QueueCustomBuffUpdate()
        if ns.QueueReanchor then ns.QueueReanchor() end
    end
end

-- True if any enabled Custom Auras (custom_buff) / buff bar tracks Time Spiral,
-- so the shared glow listener stays armed even with no Tracking Bar present.
function ns.AnyCustomAuraTimeSpiral()
    local p = ECME and ECME.db and ECME.db.profile
    if not (p and p.cdmBars and p.cdmBars.bars) then return false end
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and (bd.barType == "custom_buff" or bd.barType == "buffs") then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if sid == 374968 then return true end
                end
            end
        end
    end
    return false
end

local _spellCastListener = CreateFrame("Frame")
_spellCastListener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_spellCastListener:SetScript("OnEvent", function(_, _, _, _, spellID)
    if spellID then
        _pendingCastIDs[spellID] = true
        QueueCustomBuffUpdate()
    end
end)

-------------------------------------------------------------------------------
--  Entry Pool + Sorting
-------------------------------------------------------------------------------
local _entryPool = {}
local _entryPoolSize = 0

local function AcquireEntry(frame, spellID, baseSpellID, layoutIndex)
    local e
    if _entryPoolSize > 0 then
        e = _entryPool[_entryPoolSize]
        _entryPool[_entryPoolSize] = nil
        _entryPoolSize = _entryPoolSize - 1
    else
        e = {}
    end
    e.frame = frame
    e.spellID = spellID
    e.baseSpellID = baseSpellID
    e.layoutIndex = layoutIndex
    return e
end

local function ReleaseEntries(list)
    for i = 1, #list do
        local e = list[i]
        if e then
            e.frame = nil
            _entryPoolSize = _entryPoolSize + 1
            _entryPool[_entryPoolSize] = e
        end
        list[i] = nil
    end
end

local _scratch_barLists  = {}   -- buff bars: barKey -> {entry, ...}
local _scratch_seenSpell = {}   -- buff bars: barKey -> {dedupKey -> true}
local _scratch_spellOrder = {}  -- CD/utility: spellID -> sort index
local _scratch_activeFrames = {}
local _scratch_usedFrames = {}
local _scratch_cdFrames = {}    -- CD/utility: barKey -> {frame, frame, ...}

local function _sortByLayoutIndex(a, b)
    return (a.layoutIndex or 0) < (b.layoutIndex or 0)
end
-- CD/utility sort: by sort order stored on the FC cache during collection.
-- Tiebreak by Blizzard's layoutIndex so frames with no user-defined order
-- (e.g. default bar with empty assignedSpells) render in Blizzard's natural
-- ordering instead of an unstable sort result.
local function _sortByCDOrder(a, b)
    local fcA = _ecmeFC[a]
    local fcB = _ecmeFC[b]
    local keyA = (fcA and fcA.sortOrder) or 99999
    local keyB = (fcB and fcB.sortOrder) or 99999
    if keyA ~= keyB then return keyA < keyB end
    local liA = a.layoutIndex or 99999
    local liB = b.layoutIndex or 99999
    return liA < liB
end
-- Buff sort: the buff path sorts ENTRY objects (not frames), so each entry
-- carries its own sortOrder, stamped from the bar's assignedSpells order during
-- Phase 2. Tiebreak by Blizzard layoutIndex so buffs the user hasn't ordered
-- keep their natural ordering.
local function _sortByBuffOrder(a, b)
    local keyA = a.sortOrder or 99999
    local keyB = b.sortOrder or 99999
    if keyA ~= keyB then return keyA < keyB end
    return (a.layoutIndex or 99999) < (b.layoutIndex or 99999)
end

-------------------------------------------------------------------------------
--  CollectAndReanchor  (THE CORE)
--
--  1. EnumerateActive on all viewers
--  2. Route each frame to the correct bar
--  3. Filter by assignedSpells, inject custom frames
--  4. Decorate, sort, assign to icon slots, layout
--  5. Alpha 0 for unclaimed, alpha 1 for claimed
-------------------------------------------------------------------------------
local reanchorDirty = false
local reanchorFrame = nil
local viewerHooksInstalled = false

local function CollectAndReanchor()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.enabled then return end

    if ns.RebuildCDMSpellCaches then ns.RebuildCDMSpellCaches() end

    -- Safety: if RebuildSpellRouteMap has never run successfully (API was
    -- unavailable during zone-in rebuild, e.g. fast arena transitions),
    -- attempt a fresh rebuild now. Test the build sentinel, NOT the
    -- diversion maps (which can legitimately be empty for users with no
    -- diversions) and NOT _cdidRouteMap (lazy cache, empty post-build).
    if not _routeMapBuilt and ns.RebuildSpellRouteMap then
        ns.RebuildSpellRouteMap()
    end

    wipe(_scratch_usedFrames)
    wipe(_scratch_activeFrames)
    local allActiveFrames = _scratch_activeFrames
    local usedFrames = _scratch_usedFrames

    -- Always Show Buffs: hide every placeholder up front; the routing path below
    -- re-shows only the placeholders it injects this pass, so stale ones (buff
    -- went active, bar toggled off/disabled, spec swap) end up hidden.
    HideAllPlaceholders()
    -- Same for injected custom/preset buff own-frames: hide all, then the buff
    -- phase re-shows only the ones whose cast-timer is currently active (or while
    -- the CDM options page is open). Without this an expired custom buff lingers.
    HideAllInjectedCustomBuffs()


    -- Buff bars: existing entry-based collection (unchanged)
    local barLists = _scratch_barLists
    local seenSpell = _scratch_seenSpell
    for k, list in pairs(barLists) do ReleaseEntries(list) end
    for k, sub in pairs(seenSpell) do wipe(sub) end

    -- CD/utility bars: simple frame lists keyed by barKey
    local cdFrames = _scratch_cdFrames
    for k, list in pairs(cdFrames) do wipe(list) end

    local _FindOverride = C_SpellBook and C_SpellBook.FindSpellOverrideByID

    ---------------------------------------------------------------------------
    --  PHASE 1: Enumerate all viewers, split into buff vs CD/utility paths
    ---------------------------------------------------------------------------
    for viewerName, defaultBarKey in pairs(VIEWER_TO_BAR) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
            local isBuff = (defaultBarKey == "buffs")
            for frame in viewer.itemFramePool:EnumerateActive() do
                if IsFrameIncluded(frame) then
                    allActiveFrames[frame] = true

                    if isBuff then
                        -------------------------------------------------------
                        --  BUFF PATH: CategorizeFrame + dedup
                        -------------------------------------------------------
                        local targetBar, displaySID, baseSID = CategorizeFrame(frame, defaultBarKey)
                        if targetBar and displaySID and displaySID > 0 then
                            local barSeen = seenSpell[targetBar]
                            if not barSeen then barSeen = {}; seenSpell[targetBar] = barSeen end
                            local dedupKey = frame.cooldownID
                            if dedupKey and not barSeen[dedupKey] then
                                if frame:IsShown() then
                                    -- Active buff: route Blizzard's real frame.
                                    local tbd = barDataByKey[targetBar]
                                    if tbd and tbd.barType ~= "buffs" and tbd.barType ~= "custom_buff" then
                                        -- HOSTED buff on a CD/util bar: push the real frame into the
                                        -- CD pipeline (cdFrames) so Phase 3 sorts it with cooldowns by
                                        -- assignedSpells position and draws its native swipe. FC.spellID
                                        -- is set here (the buff path doesn't otherwise); it then enters
                                        -- _globalClaimSet (built from cdFrames) so Phase 3 never injects
                                        -- a duplicate. Phase 4 still treats it hands-off (viewerFrame).
                                        if not cdFrames[targetBar] then cdFrames[targetBar] = {} end
                                        local cf = cdFrames[targetBar]
                                        cf[#cf + 1] = frame
                                        local fc = FC(frame)
                                        fc.barKey = targetBar
                                        fc.spellID = baseSID or displaySID
                                        -- Hosted buff: Phase 3 ranks it by its hosted
                                        -- MARKER slot, independent of the same spell's
                                        -- cooldown entry on this bar.
                                        fc.isHostedBuff = true
                                    else
                                        if not barLists[targetBar] then barLists[targetBar] = {} end
                                        barLists[targetBar][#barLists[targetBar] + 1] =
                                            AcquireEntry(frame, displaySID, baseSID or displaySID, frame.layoutIndex or 0)
                                    end
                                    barSeen[dedupKey] = true
                                else
                                    -- This buff is DISPLAYED in the viewer but currently OFF
                                    -- (Blizzard pools the frame but hides it). Use the frame's
                                    -- LIVE resolved spell (GetSpellID) for the icon/identity:
                                    -- cooldownInfo's override can point at a base spec spell with
                                    -- a generic icon (e.g. 137029 Holy Paladin) while GetSpellID is
                                    -- the real talent form the viewer shows (e.g. 432496 Holy
                                    -- Bulwark). GetSpellID can return a SECRET number on a live
                                    -- frame; type() reports "number" for a secret, so guard with
                                    -- issecretvalue BEFORE the <= 0 compare (an order the
                                    -- short-circuit relies on) and fall back to the clean
                                    -- cooldownInfo-resolved displaySID.
                                    local realSID = frame.GetSpellID and frame:GetSpellID()
                                    if type(realSID) ~= "number"
                                       or (issecretvalue and issecretvalue(realSID))
                                       or realSID <= 0 then
                                        realSID = displaySID
                                    elseif ns._cdmCleanSidByCDID and dedupKey then
                                        -- Inactive frame -> CLEAN GetSpellID. Prime the shared cache
                                        -- (keyed by cooldownID) so the custom-buff picker/preview
                                        -- can resolve this spell to its live form even later while
                                        -- the aura is ACTIVE (GetSpellID secret then). Done for ALL
                                        -- inactive buff frames, not just opted-in bars.
                                        ns._cdmCleanSidByCDID[dedupKey] = realSID
                                    end
                                    -- Always Show Buffs: draw OUR OWN placeholder icon for the
                                    -- inactive buff on the bar it routes to, when that bar has the
                                    -- toggle on. We never touch Blizzard's hidden frame, so nothing
                                    -- fights its hide state.
                                    local bd = barDataByKey[targetBar]
                                    -- Effective Always Show for THIS buff: a per-icon
                                    -- override (ss.alwaysShow "on"/"off") beats the bar
                                    -- toggle. Lookup only when per-icon settings exist
                                    -- on the bar (zero added cost otherwise).
                                    -- "Keep Buffs in Same Place" (bd.hidePlaceholderIcon)
                                    -- reuses the Always-Show placeholder path: treat it as
                                    -- Always-Show internally (the two are mutually exclusive
                                    -- in the options). The placeholders it injects are then
                                    -- rendered invisible by the alpha-0 opacity passes.
                                    -- A HOSTED buff on a CD/util bar (CategorizeFrame only sends a
                                    -- buff frame to a non-buff bar for an explicit host) is treated
                                    -- as a CD/util icon: it ALWAYS reserves its slot, and its
                                    -- placeholder routes through the CD pipeline (Phase 3), not barLists.
                                    local hostCD = bd and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
                                    local showInactive = bd and (bd.showInactiveBuffIcons or bd.hidePlaceholderIcon) and true or false
                                    if hostCD then showInactive = true end
                                    -- Hosted "Visibility When Missing" (per-spell, BUFF
                                    -- family store; hosted entries never chain to bar
                                    -- tiers, so this can never come from Apply-to-Bar).
                                    -- Resolved via the pooled placeholder frame: its
                                    -- _isPlaceholderFrame flag routes the resolver to
                                    -- the buff store even when the real frame was never
                                    -- decorated this session (buff not yet active).
                                    -- nil = default desaturated placeholder (unchanged);
                                    -- "hidden" = inject but render alpha-0 (slot stays
                                    -- reserved); "hiddenShift" = skip the injection so
                                    -- later icons close the gap (HideAllPlaceholders at
                                    -- the top of every collect already hid the pooled
                                    -- frame -- same outcome as Hidden on CD (Shift
                                    -- Icons) for cooldowns).
                                    local hostedMissingVis
                                    if hostCD then
                                        local phMV = GetOrCreatePlaceholderFrame(targetBar, realSID, nil)
                                        local ssMV = ns.ResolveSpellSettings(phMV, realSID, ns.GetBarSpellData(targetBar), targetBar)
                                        local mv = ssMV and ssMV.hostedMissingVis
                                        if mv == "hidden" or mv == "hiddenShift" then hostedMissingVis = mv end
                                    end
                                    -- Per-icon Always-Show override (on/off) applies only in
                                    -- Always-Show mode. "Keep Buffs in Same Place" reserves
                                    -- EVERY tracked buff's slot, so a per-icon "off" must not
                                    -- punch a gap -- skip the override entirely in that mode.
                                    -- (For non-users hidePlaceholderIcon is false, so this is
                                    -- byte-identical to the original `if bd then`.)
                                    if bd and not bd.hidePlaceholderIcon then
                                        local sdAS = ns.GetBarSpellData(targetBar)
                                        -- Shared resolver: matches the stored key
                                        -- against the frame's full identity set
                                        -- (incl. GetCanonicalSpellIDForFrame, the
                                        -- id the picker keys settings by).
                                        local ssAS = ns.ResolveSpellSettings(frame, realSID, sdAS, targetBar)
                                        if ssAS then
                                            if ssAS.alwaysShow == "on" then showInactive = true
                                            elseif ssAS.alwaysShow == "off" then showInactive = false end
                                        end
                                    end
                                    if bd and bd.enabled and (bd.barType == "buffs" or hostCD)
                                       and showInactive and hostedMissingVis ~= "hiddenShift"
                                       and targetBar ~= ns.FOCUSKICK_BAR_KEY
                                       and not ns._cdmSpecRebuildStale then
                                        -- Two displayed-but-inactive viewer items can resolve to the
                                        -- SAME live spell (split-form talents share one override
                                        -- target). They share one pooled placeholder frame, so guard
                                        -- against injecting that single frame twice (a second
                                        -- AcquireEntry reserves a phantom slot and over-sizes the
                                        -- bar). Dedup placeholders per bar by resolved spell.
                                        local phKey = "ph:" .. realSID
                                        if not barSeen[phKey] then
                                            barSeen[phKey] = true
                                            local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(realSID)
                                            local ph = GetOrCreatePlaceholderFrame(targetBar, realSID, icon)
                                            -- Per-spell missing-visibility mark (our own
                                            -- frame): "hidden" renders alpha-0 via the
                                            -- opacity passes while the slot stays
                                            -- reserved. nil for everyone else.
                                            ph._missingHidden = (hostedMissingVis == "hidden") or nil
                                            ph.layoutIndex = frame.layoutIndex or 0
                                            -- Carry the viewer slot's cooldownID so the
                                            -- drag-reorder sort can key this placeholder
                                            -- by the STABLE id (the canonical spellID
                                            -- drifts between ability/aura form across
                                            -- active<->inactive; cooldownID does not).
                                            ph.cooldownID = dedupKey
                                            ph:Show()
                                            -- realSID is the displayed/clean buff id (== the active
                                            -- frame's canonical id and the per-icon settings key the
                                            -- options menu writes), so the placeholder resolves the
                                            -- same per-icon settings as the live buff.
                                            if hostCD then
                                                -- Hosted-buff placeholder -> CD pipeline (Phase 3);
                                                -- FC.spellID lets Phase 3 slot it by assignedSpells
                                                -- (via the hosted MARKER rank, like the live frame).
                                                if not cdFrames[targetBar] then cdFrames[targetBar] = {} end
                                                local cf = cdFrames[targetBar]
                                                cf[#cf + 1] = ph
                                                local fc = FC(ph)
                                                fc.barKey = targetBar
                                                fc.spellID = realSID
                                                fc.isHostedBuff = true
                                            else
                                                if not barLists[targetBar] then barLists[targetBar] = {} end
                                                barLists[targetBar][#barLists[targetBar] + 1] =
                                                    AcquireEntry(ph, realSID, realSID, frame.layoutIndex or 0)
                                            end
                                        end
                                        barSeen[dedupKey] = true
                                    end
                                end
                            end
                        end
                    else
                        -------------------------------------------------------
                        --  CD/UTILITY PATH: lazy resolve via ResolveCDIDToBar
                        --  Default bar = the viewer this frame came from.
                        -------------------------------------------------------
                        local cdID = frame.cooldownID
                        local barKey = ResolveCDIDToBar(cdID, defaultBarKey)
                        if barKey then
                            local bd = barDataByKey[barKey]
                            if bd and bd.barType ~= "buffs" and not bd.isGhostBar then
                                local displaySID, baseSID = ResolveFrameSpellID(frame)
                                if displaySID and displaySID > 0 then
                                    if not cdFrames[barKey] then cdFrames[barKey] = {} end
                                    local frames = cdFrames[barKey]
                                    frames[#frames + 1] = frame
                                    local fc = FC(frame)
                                    fc.barKey = barKey
                                    fc.spellID = baseSID or displaySID
                                    fc.isHostedBuff = nil
                                end
                            end
                        end
                    end
                end
            end
        end
    end



    -- Inject custom/preset buff own-frames (cast-timer driven) into buff-family
    -- bars so they sort + lay out beside Blizzard buff frames. The buff tick
    -- (UpdateCustomBuffBars) owns cast detection + timer lifecycle; here we only
    -- read the live timer to decide which custom buffs render. Dormant unless a
    -- buff bar has custom spells (sd.spellDurations set) -- zero cost otherwise.
    do
        local nowTime = GetTime()
        local cdmPageOpen = ns._cdmBarsPageOpen or false
        for _, bd in ipairs(p.cdmBars.bars) do
            if bd.enabled and bd.barType == "buffs" then
                local injKey = bd.key
                local sdInj = ns.GetBarSpellData(injKey)
                local spellList = sdInj and sdInj.assignedSpells
                local durs = sdInj and sdInj.spellDurations
                if spellList and durs then
                    -- The bar reserves a slot for an INACTIVE preset when Always
                    -- Show Buffs or Keep Buffs in Same Place is on, exactly like an
                    -- inactive Blizzard buff.
                    local showInactive = bd.showInactiveBuffIcons or bd.hidePlaceholderIcon
                    for idx, sid in ipairs(spellList) do
                        if type(sid) == "number" and sid > 0 and (durs[sid] or 0) > 0 then
                            local timer = _customAuraTimers[injKey .. ":" .. sid]
                            local isActive = timer and (nowTime - timer.start) < timer.duration
                            -- Inactive slot-reservation wins over the options-page
                            -- preview so the icon looks the same with the panel open
                            -- or closed. Suppressed during the spec-switch stale window
                            -- (mirrors the Blizzard-buff placeholder guard) so a
                            -- reanchor off the not-yet-swapped profile can't flash
                            -- preset placeholders.
                            local injectPlaceholder = (not isActive) and showInactive
                                and not ns._cdmSpecRebuildStale
                            local injectCustom = isActive or (not showInactive and cdmPageOpen)
                            if injectCustom then
                                -- Active (live reverse swipe) or options-page preview
                                -- (cleared): our own custom frame.
                                local f = GetOrCreateCustomBuffFrame(injKey, sid)
                                if isActive then
                                    f._cooldown:SetCooldown(timer.start, timer.duration)
                                else
                                    f._cooldown:Clear()
                                end
                                -- Per-spell Threshold Text (buff bars): attach the
                                -- engine countdown formatter so the custom buff's
                                -- cast-timer countdown shows decimals / a color
                                -- change below its Threshold Seconds. Gated = zero
                                -- cost when unused; the apply helper only touches
                                -- widgets it manages. nil frame: the frame's CDM
                                -- context isn't set up yet here, and a custom buff
                                -- is an exact id (no variant), so the direct
                                -- family-store hit resolves without it (matches
                                -- PlayPresetBuffGainSound).
                                if ns._cdmAnyThresholdText and ns.ApplyThresholdFormatter then
                                    local ssB = ns.ResolveThresholdTextSettings
                                        and ns.ResolveThresholdTextSettings(nil, sid, sdInj, injKey)
                                    ns.ApplyThresholdFormatter(f._cooldown, ssB)
                                end
                                f:Show()
                                f.layoutIndex = 5000 + idx
                                local fc = FC(f)
                                fc.barKey = injKey
                                fc.spellID = sid
                                if not barLists[injKey] then barLists[injKey] = {} end
                                barLists[injKey][#barLists[injKey] + 1] =
                                    AcquireEntry(f, sid, sid, f.layoutIndex)
                            elseif injectPlaceholder then
                                -- A preset is our own buff, so this is the easy case:
                                -- inject a placeholder through the SAME path Blizzard
                                -- inactive buffs use. _isPlaceholderFrame makes the
                                -- existing opacity passes grey it (Always Show) or
                                -- alpha-0 it (Keep in Same Place) automatically. Keyed
                                -- "s"..sid by the sort -- the same key the active preset
                                -- frame uses -- so it holds its slot across proc/expire.
                                local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                                local ph = GetOrCreatePlaceholderFrame(injKey, sid, icon)
                                -- A preset is never a viewer-tracked spell, so it must
                                -- key by "s"..sid. Clear any cooldownID a shared pooled
                                -- frame might carry from the Blizzard Always-Show path so
                                -- the sort never mistakes it for "c"..cooldownID.
                                ph.cooldownID = nil
                                ph.layoutIndex = 5000 + idx
                                ph:Show()
                                local fc = FC(ph)
                                fc.barKey = injKey
                                fc.spellID = sid
                                if not barLists[injKey] then barLists[injKey] = {} end
                                barLists[injKey][#barLists[injKey] + 1] =
                                    AcquireEntry(ph, sid, sid, ph.layoutIndex)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Inject item own-frames into buff bars so items (e.g. food) can be tracked
    -- there too. Negative IDs (<= -100) in assignedSpells are item markers; the
    -- shared frame + ProcessPresetCooldowns key off _isItemPresetFrame rather than
    -- bar type, so cooldown/count work the same as on CD/utility bars. Tracked via
    -- HideAllInjectedCustomBuffs so removed items drop out on the next pass.
    -- Gated behind ns._cdmAnyCustomItem (set once from saved data / the picker) so
    -- this pass is skipped entirely for anyone who never adds a custom item.
    if ns._cdmAnyCustomItem then
        for _, bd in ipairs(p.cdmBars.bars) do
            if bd.enabled and bd.barType == "buffs" then
                local injKey = bd.key
                local sdInj = ns.GetBarSpellData(injKey)
                local spellList = sdInj and sdInj.assignedSpells
                if spellList then
                    for idx, sid in ipairs(spellList) do
                        -- Cd-claim markers (collided-buff slots) are also
                        -- <= -100; they are not items.
                        if type(sid) == "number" and sid <= -100
                           and not ns.CdClaimMarkerToCdID(sid) then
                            local itemID = -sid
                            local f = GetOrCreateItemPresetFrame(injKey, itemID)
                            if f then
                                _injectedCustomBuffFrames[f] = true
                                f._ownerBarKey = injKey
                                f.layoutIndex = 6000 + idx
                                -- Pot presets: resolve the display variant here too
                                -- (generation-gated, ~free when clean) so a rebuild
                                -- or profile change restamps the icon immediately.
                                local dispID = PotSwap.Ensure(f)
                                -- "Hide Items if Missing": mirror the CD/utility item
                                -- path. When the bar opts in and the item (plus alts)
                                -- isn't in bags, skip injection so it drops out of the
                                -- layout instead of showing. Setting _hidePresenceCached
                                -- is REQUIRED: CheckItemPresenceForHide compares
                                -- (total > 0) ~= f._hidePresenceCached, so a nil cache
                                -- would read as changed on every bag update and queue a
                                -- reanchor on every loot/sell/craft for the session.
                                local skipMissing = false
                                if bd.hideItemsIfMissing then
                                    local total
                                    if dispID then
                                        total = f._displayCount or 0
                                    else
                                        total = C_Item.GetItemCount(itemID, false, true) or 0
                                        if total == 0 and f._presetData and f._presetData.altItemIDs then
                                            for _, altID in ipairs(f._presetData.altItemIDs) do
                                                total = total + (C_Item.GetItemCount(altID, false, true) or 0)
                                            end
                                        end
                                    end
                                    f._hidePresenceCached = (total > 0)
                                    skipMissing = (total == 0)
                                else
                                    f._hidePresenceCached = nil
                                end
                                if skipMissing then
                                    f:Hide()
                                else
                                    if f._cdStart and f._cdDur and (GetTime() < f._cdStart + f._cdDur) then
                                        f._cooldown:SetCooldown(f._cdStart, f._cdDur)
                                    end
                                    if f._lastDesat ~= nil and f._tex then
                                        f._tex:SetDesaturated(f._lastDesat)
                                    elseif ns._MarkPresetCdDirty then
                                        -- Fresh frame (no cached desat yet): nudge the
                                        -- preset processor so the next BuffTicker pass
                                        -- computes its ownership/cooldown desaturation,
                                        -- else an in-panel sync/import leaves an unowned
                                        -- item saturated until /reload.
                                        ns._MarkPresetCdDirty()
                                    end
                                    f:Show()
                                    local fc = FC(f)
                                    fc.barKey = injKey
                                    fc.spellID = sid
                                    if not barLists[injKey] then barLists[injKey] = {} end
                                    barLists[injKey][#barLists[injKey] + 1] =
                                        AcquireEntry(f, sid, sid, f.layoutIndex)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local LayoutCDMBar = ns.LayoutCDMBar
    local RefreshCDMIconAppearance = ns.RefreshCDMIconAppearance
    local ApplyCDMTooltipState = ns.ApplyCDMTooltipState

    ---------------------------------------------------------------------------
    --  PHASE 2: Process BUFF bars (existing flow, plus injected custom frames)
    ---------------------------------------------------------------------------
    -- Composition-gated: reanchors fire constantly in combat as buffs come and
    -- go, but the tracked catalog only changes on rebuilds -- skip the full
    -- reconcile (viewer enumeration + sorts) unless something marked it dirty.
    if ns._cdmBuffOrderDirty and ns.ReconcileBuffDisplayOrder then
        ns._cdmBuffOrderDirty = nil
        ns.ReconcileBuffDisplayOrder()
    end
    for barKey, list in pairs(barLists) do
        local barData = barDataByKey[barKey]
        if barData and barData.enabled and barData.barType ~= "custom_buff" then
            local container = cdmBarFrames[barKey]
            if container then
                -- Placeholders for displayed-but-inactive buffs were injected as
                -- our-owned frames during the routing path above, so they sort
                -- and lay out alongside the live frames here.
                --
                -- Extra/custom buff bars honor the user's assignedSpells order
                -- (drag-reorder parity with CD/utility), keyed on the DISPLAYED /
                -- canonical id -- the same id the per-icon buff settings and the
                -- options preview key off, NOT fc.spellID (the cooldownInfo base,
                -- which is a shared ability id for some buffs). The default "buffs"
                -- bar (sparse viewer mirror) and FocusKick (nameplate-driven order)
                -- keep Blizzard's natural layoutIndex order until Stage 2.
                local useBuffOrder = (barKey ~= ns.FOCUSKICK_BAR_KEY)
                local isDefaultBuffs = (barKey == "buffs")
                local buffOrder
                if useBuffOrder then
                    if not ns._spellOrderDirty and container._cachedBuffOrder then
                        buffOrder = container._cachedBuffOrder
                    else
                        if not container._cachedBuffOrder then container._cachedBuffOrder = {} end
                        buffOrder = container._cachedBuffOrder
                        wipe(buffOrder)
                        local sdOrder = ns.GetBarSpellData(barKey)
                        if isDefaultBuffs then
                            -- The default "buffs" bar orders via a dedicated
                            -- buffDisplayOrder array (decoupled from assignedSpells,
                            -- which it shares with routing/custom injection), keyed
                            -- by STABLE ids: "c"..cooldownID for Blizzard buffs (incl.
                            -- placeholders, which now carry the viewer cooldownID) and
                            -- "s"..spellID for customs. A buff's canonical spellID
                            -- flips between ability/aura form across active<->inactive;
                            -- cooldownID does not, so the order survives buffs proccing.
                            local orderList = sdOrder and sdOrder.buffDisplayOrder
                            -- Ignore the pre-stable-key format (raw spellID numbers);
                            -- the options preview reconcile re-seeds it cleanly.
                            if orderList and type(orderList[1]) == "number" then orderList = nil end
                            if orderList then
                                for i = 1, #orderList do
                                    local key = orderList[i]
                                    if buffOrder[key] == nil then buffOrder[key] = i end
                                end
                            end
                        else
                            -- Extra buff bars order by assignedSpells (spellIDs),
                            -- matched transform-aware (sid + override + base).
                            local orderList = sdOrder and sdOrder.assignedSpells
                            if orderList then
                                local oidx = 0
                                for _, sid in ipairs(orderList) do
                                    -- Cd-claim marker (collided-buff slot): both
                                    -- runtime frames of a collided pair share one
                                    -- spellID, so order by the stable "c"..cooldownID
                                    -- key instead (matches ResolveBuffDisplaySortIndex's
                                    -- cooldownID-first lookup for these slots).
                                    local cdClaim = ns.CdClaimMarkerToCdID(sid)
                                    if cdClaim then
                                        oidx = oidx + 1
                                        local key = "c" .. cdClaim
                                        if not buffOrder[key] then buffOrder[key] = oidx end
                                    -- Negative IDs are custom-item markers: order them
                                    -- by their slot too (no override/base variants).
                                    elseif type(sid) == "number" and sid <= -100 then
                                        oidx = oidx + 1
                                        if not buffOrder[sid] then buffOrder[sid] = oidx end
                                    elseif type(sid) == "number" and sid > 0 then
                                        oidx = oidx + 1
                                        if not buffOrder[sid] then buffOrder[sid] = oidx end
                                        if _FindOverride then
                                            local ovr = _FindOverride(sid)
                                            if ovr and ovr > 0 and not buffOrder[ovr] then buffOrder[ovr] = oidx end
                                        end
                                        if C_Spell and C_Spell.GetBaseSpell then
                                            local base = C_Spell.GetBaseSpell(sid)
                                            if base and base > 0 and base ~= sid and not buffOrder[base] then
                                                buffOrder[base] = oidx
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if buffOrder and next(buffOrder) then
                    for _, entry in ipairs(list) do
                        local okey = ns.ResolveBuffDisplaySortIndex
                            and ns.ResolveBuffDisplaySortIndex(entry, buffOrder, isDefaultBuffs)
                        if not okey and isDefaultBuffs then
                            -- Transient spillover (Blizzard layoutIndex glitch / re-talent
                            -- gap): sort among misses by layoutIndex, not after every hit.
                            okey = 50000 + (entry.layoutIndex or 0)
                        end
                        entry.sortOrder = okey or 99999
                    end
                    table.sort(list, _sortByBuffOrder)
                else
                    table.sort(list, _sortByLayoutIndex)
                end

                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local count = 0

                -- Only Show Numbers forces the countdown text on for the whole
                -- bar regardless of the Cooldown Text toggle.
                local hideCD = not (barData.showCooldownText or barData.onlyShowNumbers)
                -- FocusKick icon alpha is owned exclusively by
                -- SetFocusKickAlpha; skip the per-icon alpha override here
                -- so CollectAndReanchor doesn't clobber the nameplate-driven
                -- visibility state with a stale _visHidden flag.
                local isFocusKickBar = (barKey == ns.FOCUSKICK_BAR_KEY)

                for _, entry in ipairs(list) do
                    count = count + 1
                    local frame = entry.frame
                    usedFrames[frame] = true
                    DecorateFrame(frame, barData)
                    FC(frame).barKey = barKey
                    FC(frame).spellID = entry.baseSpellID or entry.spellID
                    icons[count] = frame
                    -- Only Show/alpha frames Blizzard considers active.
                    -- Hidden frames are collected for data (assignedSpells)
                    -- but left visually untouched so we don't override
                    -- Blizzard's "hide when inactive" state machine.
                    if frame:IsShown() and not isFocusKickBar then
                        local barHidden = container and container._visHidden
                        local fcH = _ecmeFC[frame]
                        if not (fcH and fcH._cdStateHidden) then
                            -- Hide Icon: an Always-Show placeholder still reserves its
                            -- layout slot (it stays shown + decorated + positioned) but
                            -- renders fully invisible -- icon, border and background --
                            -- via frame alpha 0. The same check is mirrored in the two
                            -- other per-icon opacity passes (_CDMApplyVisibility and
                            -- ApplyBarOpacity) so none of them paint over it.
                            -- The off-by-default bar flag is tested FIRST so anyone not
                            -- using this feature short-circuits straight to the original
                            -- branch below (identical code, no added work).
                            if barData.hidePlaceholderIcon and frame._isPlaceholderFrame then
                                frame:SetAlpha(0)
                            else
                                frame:SetAlpha(barHidden and 0 or ns.EffectiveBarAlpha(barData))
                            end
                        end
                    end
                    -- Ensure stack/charge text stays above our border overlay.
                    -- Blizzard resets frame levels on pooled frames during zone
                    -- transitions; re-raise cheaply here every collect pass.
                    -- Use relative levels so cursor-anchored bars (level 9980+)
                    -- keep text above their icons.
                    local _txtLvl = frame:GetFrameLevel() + 23
                    if frame.Applications then pcall(frame.Applications.SetFrameLevel, frame.Applications, _txtLvl) end
                    if frame.ChargeCount then pcall(frame.ChargeCount.SetFrameLevel, frame.ChargeCount, _txtLvl) end
                    if frame.Cooldown then
                        if frame.Cooldown.SetDrawSwipe then
                            -- Only Show Numbers: the duration swipe is part of the
                            -- hidden icon art, so keep it off for the whole bar.
                            frame.Cooldown:SetDrawSwipe(not barData.onlyShowNumbers)
                        end
                        -- Everything claimed here renders as a buff: re-assert the
                        -- fill direction when the frame's recorded kind differs
                        -- (once-per-frame decoration + pooled frames can leave a
                        -- CD-direction stamp from a previous life on another bar).
                        -- Kind-gated so the per-spell Reverse Swipe pass, which
                        -- runs after, is never stomped on unchanged passes.
                        local efdR = hookFrameData[frame]
                        if efdR and efdR._revKind ~= true then
                            efdR._revKind = true
                            frame.Cooldown:SetReverse(true)
                        end
                        frame.Cooldown:SetHideCountdownNumbers(hideCD)
                    end
                end

                -- Mark this bar's frames as used BEFORE the excess-clear below,
                -- so the clear can tell a stale tail slot from a still-claimed
                -- frame.
                for _, entry in ipairs(list) do
                    if entry.frame and not usedFrames[entry.frame] then
                        usedFrames[entry.frame] = true
                    end
                end

                -- Clear excess buff icons (Blizzard owns lifecycle, only disable
                -- swipe). Skip frames still in the active set: when a buff
                -- expires, every icon after it shifts one slot left, so the old
                -- tail slot holds a frame that is STILL CLAIMED (old slot N+1 ==
                -- new slot N). Disabling its swipe blanked the aura swipe on a
                -- surviving buff -- and the SetDrawSwipe hook deliberately never
                -- force-restores buff frames, so it stayed blank until the next
                -- buff event. Mirrors the Phase 3 excess-clear guard.
                for i = count + 1, #icons do
                    local icon = icons[i]
                    if icon and not usedFrames[icon] then
                        local efd = hookFrameData[icon]
                        if efd then efd._cdmAnchor = nil end
                        if icon.Cooldown and icon.Cooldown.SetDrawSwipe then
                            icon.Cooldown:SetDrawSwipe(false)
                        end
                    end
                    icons[i] = nil
                end

                -- Conditional layout for buffs (existing iconsChanged detection)
                local prevCount = container._prevVisibleCount or 0
                local iconsChanged = count ~= prevCount
                if not iconsChanged and container._prevIconRefs then
                    for idx = 1, count do
                        if container._prevIconRefs[idx] ~= icons[idx] then
                            iconsChanged = true; break
                        end
                    end
                else
                    iconsChanged = true
                end
                if iconsChanged then
                    if RefreshCDMIconAppearance then RefreshCDMIconAppearance(barKey) end
                    if LayoutCDMBar then LayoutCDMBar(barKey) end
                    if ApplyCDMTooltipState then ApplyCDMTooltipState(barKey) end
                    if not container._prevIconRefs then container._prevIconRefs = {} end
                    for idx = 1, count do container._prevIconRefs[idx] = icons[idx] end
                    for idx = count + 1, #container._prevIconRefs do container._prevIconRefs[idx] = nil end
                else
                    -- Frames + order unchanged, but if the bar has per-icon overrides
                    -- a pool frame may have been reused for a different spell (same
                    -- ref) -- this pass just re-stamped fc.spellID, so re-apply icon
                    -- appearance (no re-layout) to re-resolve per-icon glow/text
                    -- against the fresh identity. Without this a per-icon glow stays
                    -- on the frame it was first stashed on until the next add/remove.
                    local sdRef = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
                    if RefreshCDMIconAppearance and ns.BarHasAnySpellSettings
                       and ns.BarHasAnySpellSettings(barKey, sdRef) then
                        RefreshCDMIconAppearance(barKey)
                    end
                end
                container._prevVisibleCount = count
            end
        end
    end

    -- Clean up empty buff bars
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and ns.IsBarBuffFamily(bd)
           and not bd.isGhostBar and not barLists[bd.key] then
            local icons = cdmBarIcons[bd.key]
            if icons then
                for i = 1, #icons do
                    -- Skip frames another bar claimed this pass (a buff moved off
                    -- this bar is still live elsewhere -- disabling its swipe here
                    -- would blank it there).
                    if icons[i] and not usedFrames[icons[i]] then
                        local efd = hookFrameData[icons[i]]
                        if efd then efd._cdmAnchor = nil end
                        if icons[i].Cooldown and icons[i].Cooldown.SetDrawSwipe then
                            icons[i].Cooldown:SetDrawSwipe(false)
                        end
                    end
                    icons[i] = nil
                end
            end
            local container = cdmBarFrames[bd.key]
            if container and (container._prevVisibleCount or 0) > 0 then
                container._prevVisibleCount = 0
                if LayoutCDMBar then LayoutCDMBar(bd.key) end
            end
        end
    end

    ---------------------------------------------------------------------------
    --  PHASE 3: Process CD/UTILITY bars (simplified flow)
    --  For each bar: inject custom frames, assign sort keys, sort, position.
    --  No allowSet, no entryBySpell, no dedup, no change detection.
    ---------------------------------------------------------------------------
    -- Ensure custom-frame-only CD/utility bars get processed
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
           and bd.key ~= "buffs" and not cdFrames[bd.key] then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells and #sd.assignedSpells > 0 then
                cdFrames[bd.key] = {}
            end
        end
    end

    -- Pre-build claim set for racial/custom spell checks: collect all
    -- spellIDs already claimed by Blizzard frames across all bars. This
    -- replaces the O(frames * FindSpellOverrideByID) inner loop with a
    -- set lookup.
    local _claimSet = _scratch_spellOrder  -- reuse scratch for claim set (wiped per bar below)
    local _globalClaimSet = {}
    for _, flist in pairs(cdFrames) do
        for _, f in ipairs(flist) do
            local fc = _ecmeFC[f]
            if fc then
                local fSid = fc.spellID
                if fSid then _globalClaimSet[fSid] = true end
                if fc.baseSpellID then _globalClaimSet[fc.baseSpellID] = true end
                if fc.linkedSpellIDs then
                    for _, lid in ipairs(fc.linkedSpellIDs) do
                        if lid and lid > 0 then _globalClaimSet[lid] = true end
                    end
                end
            end
        end
    end

    for barKey, frames in pairs(cdFrames) do
        local barData = barDataByKey[barKey]
        if barData and barData.enabled then
            local container = cdmBarFrames[barKey]
            if container then
                local sd = ns.GetBarSpellData(barKey)
                local spellList = sd and sd.assignedSpells

                -- Spell order map: cached per-bar, rebuilt only when spells
                -- change (spec swap, talent change, user edits). During
                -- combat rotation, the assigned list is static so the cache
                -- hit rate is ~100%.
                local spellOrder, hostedOrder
                if not ns._spellOrderDirty and container._cachedSpellOrder then
                    spellOrder = container._cachedSpellOrder
                    hostedOrder = container._cachedHostedOrder
                else
                    if not container._cachedSpellOrder then container._cachedSpellOrder = {} end
                    if not container._cachedHostedOrder then container._cachedHostedOrder = {} end
                    spellOrder = container._cachedSpellOrder
                    hostedOrder = container._cachedHostedOrder
                    wipe(spellOrder)
                    wipe(hostedOrder)
                    if spellList then
                        local idx = 0
                        for _, sid in ipairs(spellList) do
                            if sid and sid ~= 0 then
                                idx = idx + 1
                                -- Hosted-buff marker: rank the BUFF frame of the
                                -- decoded spell at this slot. Kept in its own map so
                                -- the same spell's cooldown entry ranks independently.
                                local hSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid)
                                if hSid then
                                    if not hostedOrder[hSid] then hostedOrder[hSid] = idx end
                                    if _FindOverride then
                                        local hOvr = _FindOverride(hSid)
                                        if hOvr and hOvr > 0 and hOvr ~= hSid and not hostedOrder[hOvr] then
                                            hostedOrder[hOvr] = idx
                                        end
                                    end
                                    if C_Spell and C_Spell.GetBaseSpell then
                                        local hBase = C_Spell.GetBaseSpell(hSid)
                                        if hBase and hBase > 0 and hBase ~= hSid and not hostedOrder[hBase] then
                                            hostedOrder[hBase] = idx
                                        end
                                    end
                                else
                                    if not spellOrder[sid] then spellOrder[sid] = idx end
                                    if _FindOverride then
                                        local ovr = _FindOverride(sid)
                                        if ovr and ovr > 0 and ovr ~= sid and not spellOrder[ovr] then
                                            spellOrder[ovr] = idx
                                        end
                                    end
                                    if C_Spell and C_Spell.GetBaseSpell then
                                        local base = C_Spell.GetBaseSpell(sid)
                                        if base and base > 0 and base ~= sid and not spellOrder[base] then
                                            spellOrder[base] = idx
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- Inject custom frames (trinkets, items, racials)
                if spellList then
                    -- Items already represented by an equipment-slot entry on
                    -- this bar. The slot frame renders whatever is equipped
                    -- there, so injecting the same item's preset frame too
                    -- would show one physical item twice -- classic case: a
                    -- legacy custom-item belt entry plus a slot entry appended
                    -- at the bar's end by an add or an RPT sync. The item
                    -- entry stays in the data and renders again the moment the
                    -- item is unequipped from that slot.
                    local slotEquippedItems
                    for _, sid in ipairs(spellList) do
                        local slot = sid and ns.SlotIDFromKey(sid)
                        if slot then
                            local eqItemID = GetInventoryItemID("player", slot)
                            if eqItemID then
                                slotEquippedItems = slotEquippedItems or {}
                                slotEquippedItems[eqItemID] = true
                            end
                        end
                    end
                    for _, sid in ipairs(spellList) do
                        if sid and ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid) then
                            -- Hosted-buff marker: the buff renders via the reparent
                            -- path (route map -> cdFrames), never as an injected
                            -- custom frame. Must be tested before the item-preset
                            -- branch (markers are also <= -100).
                        elseif sid and ns.SlotIDFromKey(sid) then
                            -- Equipment slot (trinkets -13/-14, user-added slots)
                            local slot = ns.SlotIDFromKey(sid)
                            local tf = _trinketFrames[slot]
                            if not tf then tf = GetOrCreateTrinketFrame(slot) end
                            UpdateTrinketFrame(slot)
                            -- Show Passive Trinkets covers the trinket slots only;
                            -- user-added slots auto-hide without a use effect.
                            local showPassive = (slot == 13 or slot == 14)
                                and barData and barData.showPassiveTrinkets
                            if _trinketItemCache[slot] and (tf._trinketIsOnUse or showPassive) then
                                UpdateTrinketCooldown(slot)
                                frames[#frames + 1] = tf
                                local fc = FC(tf)
                                fc.barKey = barKey; fc.spellID = sid
                            else
                                tf:Hide()
                            end
                        elseif sid and sid <= -100 then
                            -- Item preset (potions, healthstone, etc.) or a
                            -- user-added custom item ID. Frame creation (incl.
                            -- the live-icon fallback for arbitrary items) is
                            -- shared with the buff-family injection.
                            local itemID = -sid
                            -- Skip when a slot entry on this bar already shows
                            -- this exact item (see slotEquippedItems above);
                            -- the orphan sweep hides any frame from a previous
                            -- pass.
                            local f = not (slotEquippedItems and slotEquippedItems[itemID])
                                and GetOrCreateItemPresetFrame(barKey, itemID)
                            if f then
                                -- Remember the bar that owns this frame so bag
                                -- events can re-evaluate it even while hidden.
                                f._ownerBarKey = barKey
                                -- Pot presets: resolve the display variant here
                                -- too (generation-gated, ~free when clean) so a
                                -- rebuild or profile change restamps immediately.
                                local dispID = PotSwap.Ensure(f)
                                -- "Hide Items if Missing": when the bar opts in
                                -- and the item (plus its alts) isn't in bags,
                                -- skip injection entirely so it drops out of the
                                -- layout instead of showing dimmed. A bag update
                                -- queues a reanchor, so it reappears on acquire.
                                local skipMissing = false
                                if barData and barData.hideItemsIfMissing then
                                    local total
                                    if dispID then
                                        total = f._displayCount or 0
                                    else
                                        total = C_Item.GetItemCount(itemID, false, true) or 0
                                        if total == 0 and f._presetData and f._presetData.altItemIDs then
                                            for _, altID in ipairs(f._presetData.altItemIDs) do
                                                total = total + (C_Item.GetItemCount(altID, false, true) or 0)
                                            end
                                        end
                                    end
                                    f._hidePresenceCached = (total > 0)
                                    skipMissing = (total == 0)
                                else
                                    f._hidePresenceCached = nil
                                end
                                if skipMissing then
                                    f:Hide()
                                else
                                    -- CD state is maintained by ProcessPresetCooldowns
                                    -- at 10Hz. Here we just re-apply cached visuals
                                    -- (no API queries needed per reanchor).
                                    if f._cdStart and f._cdDur and (GetTime() < f._cdStart + f._cdDur) then
                                        f._cooldown:SetCooldown(f._cdStart, f._cdDur)
                                    end
                                    if f._lastDesat ~= nil and f._tex then
                                        f._tex:SetDesaturated(f._lastDesat)
                                    elseif ns._MarkPresetCdDirty then
                                        -- Fresh frame (no cached desat yet, e.g. after a full
                                        -- rebuild): its ownership/cooldown desaturation has not
                                        -- been computed. Flag the preset processor so the next
                                        -- BuffTicker pass evaluates it -- without this a rebuild
                                        -- not followed by a game event (an in-panel sync/import)
                                        -- leaves an unowned pot/healthstone saturated until /reload.
                                        ns._MarkPresetCdDirty()
                                    end
                                    frames[#frames + 1] = f
                                    local fc = FC(f)
                                    fc.barKey = barKey; fc.spellID = sid
                                end
                            end
                        elseif sid and sid > 0 then
                            -- Racial / custom spell (only if no Blizzard frame claimed it)
                            -- Uses pre-built _globalClaimSet (set of all spellIDs
                            -- on Blizzard frames). Still checks override/base of
                            -- the candidate spell (2 API calls per spell, not per frame).
                            local hasClaim = _globalClaimSet[sid] or false
                            if not hasClaim and _FindOverride then
                                local ovr = _FindOverride(sid)
                                if ovr and ovr > 0 and _globalClaimSet[ovr] then hasClaim = true end
                            end
                            if not hasClaim and C_Spell and C_Spell.GetBaseSpell then
                                local base = C_Spell.GetBaseSpell(sid)
                                if base and base > 0 and _globalClaimSet[base] then hasClaim = true end
                            end
                            if not hasClaim then
                                local isRacial = ns._myRacialsSet and ns._myRacialsSet[sid]
                                local isCustomSpell = sd and sd.customSpellIDs and sd.customSpellIDs[sid]
                                -- Phase 3 injects custom frames for spells that
                                -- are NOT in Blizzard's CDM category (user-added
                                -- racials, user-added customs). If a spell IS in
                                -- CDM, Blizzard's native frame is authoritative
                                -- and renders on its own bar; injecting here
                                -- would produce a ghost duplicate that the user
                                -- cannot remove from the live bar (the picker
                                -- only touches assignedSpells). Example: a
                                -- Dracthyr Evoker utility preset with Wing
                                -- Buffet in assignedSpells -- Blizzard already
                                -- tracks it in CDM, so we must not inject.
                                -- Only skip injection for racials that Blizzard
                                -- already tracks. User-added custom spells are
                                -- always injected: the user explicitly chose to
                                -- put that spell on this bar, even if Blizzard's
                                -- CDM has its own native frame for it elsewhere.
                                local isKnownInCDM = isRacial and ns.IsSpellKnownInCDM and ns.IsSpellKnownInCDM(sid)
                                if isKnownInCDM then
                                    -- Racial already in CDM; Blizzard's frame handles it.
                                elseif not isRacial and not isCustomSpell then
                                    -- Unknown spell, skip
                                else
                                    local fkey = barKey .. ":" .. (isRacial and "racial" or "custom") .. ":" .. sid
                                    local f = _presetFrames[fkey]
                                    if not f then
                                        f = CreateFrame("Frame", nil, UIParent)
                                        f:SetSize(36, 36); f:Hide()
                                        f:EnableMouse(true)
                                        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
                                        local tex = f:CreateTexture(nil, "ARTWORK")
                                        tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                        f.Icon = tex; f._tex = tex
                                        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                        cd:SetHideCountdownNumbers(true)
                                        cd:SetScript("OnCooldownDone", function()
                                            if f._tex then f._tex:SetDesaturation(0) end
                                        end)
                                        f.Cooldown = cd; f._cooldown = cd
                                        f._isRacialFrame = isRacial or nil
                                        f._isCustomSpellFrame = not isRacial or nil
                                        f.cooldownID = nil; f.cooldownInfo = nil
                                        f.layoutIndex = 99999
                                        f:EnableMouse(true)
                                        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
                                        f:SetScript("OnEnter", function(self)
                                            local ffc = _ecmeFC[self]
                                            local spid = ffc and ffc.spellID
                                            local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
                                            if not bd2 or not bd2.showTooltip then return end
                                            -- Honor the global "Show Tooltips" mode (Blizzard Skin).
                                            if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
                                               and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
                                            if spid and spid > 0 then
                                                GameTooltip_SetDefaultAnchor(GameTooltip, self)
                                                GameTooltip:SetSpellByID(spid)
                                                if EllesmereUI and EllesmereUI._repointTooltipAtCursor then
                                                    EllesmereUI._repointTooltipAtCursor(GameTooltip)
                                                end
                                                -- Explicit Show(): needed when "Anchor to Cursor"
                                                -- re-owns the tooltip to ANCHOR_NONE (see trinket).
                                                GameTooltip:Show()
                                            end
                                        end)
                                        f:SetScript("OnLeave", GameTooltip_Hide)
                                        _presetFrames[fkey] = f
                                    end
                                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                                    if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                                    if not f._cdSet or f._racialCdDirty then
                                        local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
                                        if durObj and f._cooldown.SetCooldownFromDurationObject then
                                            f._cooldown:SetCooldownFromDurationObject(durObj, true)
                                        end
                                        ApplySpellDesaturation(f, durObj)
                                        f._cdSet = true; f._racialCdDirty = false
                                    end
                                    frames[#frames + 1] = f
                                    local fc = FC(f)
                                    fc.barKey = barKey; fc.spellID = sid
                                end
                            end
                        end
                    end
                end

                -- Assign sort keys from spellOrder (transform-aware). A frame whose
                -- spell is in assignedSpells gets its integer slot index. A frame
                -- that is NOT (spillover -- e.g. a cooldown a talent swap just added
                -- that the user has never ordered) is marked here and positioned in
                -- the second pass below by Blizzard's native layoutIndex, ADJACENT to
                -- the assigned Blizzard spells around it, instead of being dumped at
                -- the end of the bar. This keeps a re-talented cooldown in its
                -- Blizzard CDM position rather than piling new spells after a
                -- trinket/racial slot.
                local hasSpill = false
                -- Identity probe shared by both member kinds. The first 4 probes
                -- key off fc.spellID = cooldownInfo.spellID (the base) and bridge
                -- base<->override. For some hero-talent slots that base is an
                -- UNRELATED spell to the DISPLAYED/castable form the picker
                -- actually stored (documented: a Wither slot whose cooldownInfo
                -- base is Immolate), so the frame's displayed identity -- the same
                -- GetCanonicalSpellIDForFrame id the add path wrote -- is matched
                -- too, and a placed cooldown finds its saved rank on return
                -- instead of being mistaken for a brand-new spillover.
                local function OrderKeyFor(frame, fc, sid, map)
                    if not map then return nil end
                    local key = sid and map[sid]
                    -- Check cached baseSpellID (stable across transforms)
                    if not key and fc and fc.baseSpellID then
                        key = map[fc.baseSpellID]
                    end
                    if not key and sid and sid > 0 and _FindOverride then
                        local ovr = _FindOverride(sid)
                        if ovr and ovr > 0 then key = map[ovr] end
                    end
                    if not key and sid and sid > 0 and C_Spell and C_Spell.GetBaseSpell then
                        local base = C_Spell.GetBaseSpell(sid)
                        if base and base > 0 and base ~= sid then key = map[base] end
                    end
                    if not key and fc and fc.resolvedSid then
                        key = map[fc.resolvedSid]
                    end
                    if not key and ns.GetCanonicalSpellIDForFrame then
                        local canon = ns.GetCanonicalSpellIDForFrame(frame)
                        if canon and canon > 0 then key = map[canon] end
                    end
                    if not key and fc and fc.linkedSpellIDs then
                        for _, lid in ipairs(fc.linkedSpellIDs) do
                            if lid and lid > 0 and map[lid] then key = map[lid]; break end
                        end
                    end
                    return key
                end
                for _, frame in ipairs(frames) do
                    local fc = _ecmeFC[frame]
                    local sid = fc and fc.spellID
                    local key
                    if fc and fc.isHostedBuff then
                        -- Hosted buff: rank by its MARKER slot. Legacy fallback to
                        -- the plain map covers hosted buffs stored before the
                        -- marker model (plain entry + flag) -- they keep rendering
                        -- at their old position until the options pass normalizes.
                        key = OrderKeyFor(frame, fc, sid, hostedOrder)
                        if not key then key = OrderKeyFor(frame, fc, sid, spellOrder) end
                    else
                        key = OrderKeyFor(frame, fc, sid, spellOrder)
                    end
                    if fc then
                        if key then
                            fc.sortOrder = key
                        else
                            fc.sortOrder = false  -- spillover marker, resolved below
                            hasSpill = true
                        end
                    end
                end

                -- Second pass (only when a spillover exists -- steady state skips
                -- this entirely). Give each spillover a fractional key that lands it
                -- between its neighbours by Blizzard layoutIndex.
                --
                -- Anchors are the present, assigned frames. A real viewer frame
                -- (cooldownID set) anchors at its OWN layoutIndex. A preset we inject
                -- (trinket/pot/racial -- cooldownID nil, no real layoutIndex) anchors
                -- at an INTERPOLATED layoutIndex derived from its nearest present
                -- Blizzard neighbour in slot order. Without the preset anchors the
                -- sort can't see them, so a re-talented cooldown the user parked to
                -- the LEFT of a preset could hop to its RIGHT (and vice versa). With
                -- them, the spillover lands on the correct side of the preset.
                if hasSpill then
                    -- Blizzard viewer anchors: real layoutIndex, keyed by slot index.
                    local blizzKeys, blizzLIs
                    for _, frame in ipairs(frames) do
                        local fc = _ecmeFC[frame]
                        local k = fc and fc.sortOrder
                        if type(k) == "number" and frame.cooldownID ~= nil then
                            blizzKeys = blizzKeys or {}; blizzLIs = blizzLIs or {}
                            blizzKeys[#blizzKeys + 1] = k
                            blizzLIs[#blizzKeys] = frame.layoutIndex or 0
                        end
                    end
                    -- Full anchor set = Blizzard anchors + preset anchors (interpolated
                    -- layoutIndex). minAnchorIdx (over ALL anchors) is where a spillover
                    -- that sorts before everything lands. Skipped entirely when the bar
                    -- has no present Blizzard spell to interpolate against (no anchors ->
                    -- spillovers fall to the tail by layoutIndex, as before).
                    local anchorKeys, anchorLIs, minAnchorIdx
                    if blizzKeys then
                        anchorKeys, anchorLIs = {}, {}
                        for i = 1, #blizzKeys do
                            anchorKeys[i] = blizzKeys[i]; anchorLIs[i] = blizzLIs[i]
                            if not minAnchorIdx or blizzKeys[i] < minAnchorIdx then
                                minAnchorIdx = blizzKeys[i]
                            end
                        end
                        for _, frame in ipairs(frames) do
                            local fc = _ecmeFC[frame]
                            local k = fc and fc.sortOrder
                            if type(k) == "number" and frame.cooldownID == nil then
                                -- Nearest present Blizzard anchor on each side (slot order).
                                local leftLI, leftSlot, rightLI, rightSlot
                                for i = 1, #blizzKeys do
                                    local bslot = blizzKeys[i]
                                    if bslot < k then
                                        if not leftSlot or bslot > leftSlot then leftSlot = bslot; leftLI = blizzLIs[i] end
                                    elseif bslot > k then
                                        if not rightSlot or bslot < rightSlot then rightSlot = bslot; rightLI = blizzLIs[i] end
                                    end
                                end
                                -- Ride just after the left neighbour (or just before the
                                -- right when there is none). 0.001*distance keeps it
                                -- inside the neighbour's integer-layoutIndex gap and
                                -- monotonic for multiple presets in the same gap.
                                local effLI
                                if leftLI then
                                    effLI = leftLI + 0.001 * (k - leftSlot)
                                elseif rightLI then
                                    effLI = rightLI - 0.001 * (rightSlot - k)
                                end
                                if effLI then
                                    anchorKeys[#anchorKeys + 1] = k
                                    anchorLIs[#anchorKeys] = effLI
                                    if not minAnchorIdx or k < minAnchorIdx then minAnchorIdx = k end
                                end
                            end
                        end
                    end
                    for _, frame in ipairs(frames) do
                        local fc = _ecmeFC[frame]
                        if fc and fc.sortOrder == false then
                            if anchorKeys and frame.cooldownID ~= nil then
                                local L = frame.layoutIndex or 0
                                local predIdx, predLI
                                for i = 1, #anchorKeys do
                                    local li = anchorLIs[i]
                                    if li < L and (not predLI or li > predLI) then
                                        predLI = li; predIdx = anchorKeys[i]
                                    end
                                end
                                -- Insert after the predecessor slot (or before the first
                                -- anchor when below all). (L+1)/1e6 < 1 keeps the
                                -- spillover strictly between its neighbouring integer
                                -- slots and never ties its predecessor.
                                local baseIdx = predIdx or ((minAnchorIdx or 1) - 1)
                                fc.sortOrder = baseIdx + ((L + 1) / 1e6)
                            else
                                fc.sortOrder = 99999
                            end
                        end
                    end
                end

                -- Sort by user-defined order
                table.sort(frames, _sortByCDOrder)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  PHASE 3b: Max Icons overflow diversion (session-only). The tail of an
    --  over-cap bar's sorted list moves to the target bar's render list for
    --  this pass. Identity (fc.barKey) stays on the source bar, so per-spell
    --  settings, menus and assignedSpells are untouched. Plan-then-apply from
    --  a pre-move snapshot: diverted frames never re-divert and a bar's cap
    --  counts only its native frames, independent of bar order.
    ---------------------------------------------------------------------------
    do
        local tagged = ns._cdmOverflowTagged
        if tagged then
            for f in pairs(tagged) do
                local fcT = _ecmeFC[f]
                if fcT then fcT._overflowLayoutBar = nil end
                tagged[f] = nil
            end
        end
        if ns._cdmAnyOverflowCfg then
            local moves  -- flat pairs: frame, targetKey, frame, targetKey, ...
            for _, bd in ipairs(p.cdmBars.bars) do
                local cap, tKey = bd.maxIcons, bd.overflowTarget
                -- Legacy profiles carry nil barType on default bars; resolve
                -- the family through the shared helper, never the raw field.
                local bdType = ns.GetBarType and ns.GetBarType(bd) or bd.barType
                if bd.enabled and cap and cap > 0 and tKey and tKey ~= bd.key
                   and not bd.isGhostBar and bd.key ~= ns.FOCUSKICK_BAR_KEY
                   and bdType ~= "buffs" and bdType ~= "custom_buff"
                   and bd.key ~= "buffs" then
                    local srcList = cdFrames[bd.key]
                    if srcList and #srcList > cap and cdmBarFrames[bd.key] then
                        local tbd = barDataByKey[tKey]
                        local tType = tbd and (ns.GetBarType and ns.GetBarType(tbd) or tbd.barType)
                        local tOK = tbd and tbd.enabled and not tbd.isGhostBar
                            and tKey ~= ns.FOCUSKICK_BAR_KEY
                            and tType ~= "buffs" and tType ~= "custom_buff"
                            and tKey ~= "buffs" and cdmBarFrames[tKey]
                        -- No-op rule: never divert while any member of this bar
                        -- has a Shift Icons cooldown-state effect (the shift
                        -- filter changes the effective count on a faster,
                        -- independent cadence than this pass). Two stages: the
                        -- frame-less assignedSpells scan, then a frame-scoped
                        -- walk of the live list -- spillover frames (not in
                        -- assignedSpells) and alias-keyed settings are only
                        -- visible to the same resolution the live shift driver
                        -- uses, so the check and the driver can never disagree.
                        local blocked = ns.CdmBarHasShiftCdState(bd.key)
                        if tOK and not blocked then
                            local sdS = ns.GetBarSpellData(bd.key)
                            for i = 1, #srcList do
                                local fcS = _ecmeFC[srcList[i]]
                                if fcS then
                                    if fcS._cdStateShiftHidden then blocked = true; break end
                                    local ssS = ResolveSpellSettings(srcList[i], fcS.spellID, sdS, bd.key)
                                    local effS = ssS and ssS.cdStateEffect
                                    if effS == "hiddenOnCDShift" or effS == "hiddenReadyShift" then
                                        blocked = true; break
                                    end
                                end
                            end
                        end
                        if tOK and not blocked then
                            if not moves then moves = {} end
                            for i = cap + 1, #srcList do
                                moves[#moves + 1] = srcList[i]
                                moves[#moves + 1] = tKey
                            end
                            for i = #srcList, cap + 1, -1 do srcList[i] = nil end
                        end
                    end
                end
            end
            if moves then
                if not ns._cdmOverflowTagged then
                    ns._cdmOverflowTagged = setmetatable({}, { __mode = "k" })
                end
                tagged = ns._cdmOverflowTagged
                for i = 1, #moves, 2 do
                    local f, tKey = moves[i], moves[i + 1]
                    local tl = cdFrames[tKey]
                    if not tl then tl = {}; cdFrames[tKey] = tl end
                    tl[#tl + 1] = f
                    local fcM = _ecmeFC[f]
                    if fcM then fcM._overflowLayoutBar = tKey end
                    tagged[f] = true
                end
            end
        end
    end

    for barKey, frames in pairs(cdFrames) do
        local barData = barDataByKey[barKey]
        if barData and barData.enabled then
            local container = cdmBarFrames[barKey]
            if container then
                -- Assign to icon slots, decorate, show
                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local barHidden = container._visHidden
                local isFKBar = (barKey == ns.FOCUSKICK_BAR_KEY)

                local hideCDText = not barData.showCooldownText
                for i, frame in ipairs(frames) do
                    usedFrames[frame] = true
                    DecorateFrame(frame, barData)
                    icons[i] = frame
                    if not isFKBar then
                    local fcH = _ecmeFC[frame]
                    -- Hosted "Visibility When Missing: Hidden": the placeholder
                    -- keeps its reserved layout slot but renders fully invisible.
                    -- The flag is nil for everyone else (original branch below
                    -- unchanged).
                    if frame._missingHidden and frame._isPlaceholderFrame then
                        frame:SetAlpha(0)
                    elseif not (fcH and fcH._cdStateHidden) then
                        frame:SetAlpha(barHidden and 0 or ns.EffectiveBarAlpha(barData))
                    end
                    end
                    frame:Show()
                    local _txtLvl2 = frame:GetFrameLevel() + 23
                    if frame.Applications then pcall(frame.Applications.SetFrameLevel, frame.Applications, _txtLvl2) end
                    if frame.ChargeCount then pcall(frame.ChargeCount.SetFrameLevel, frame.ChargeCount, _txtLvl2) end
                    if frame.Cooldown then
                        if frame.Cooldown.SetDrawSwipe then
                            frame.Cooldown:SetDrawSwipe(true)
                        end
                        -- Re-assert the swipe direction when the frame's recorded
                        -- kind differs: hosted buffs / placeholders fill like buffs,
                        -- everything else depletes. Once-per-frame decoration +
                        -- pooled frames can leave the other family's stamp from a
                        -- previous life. Kind-gated so the per-spell Reverse Swipe
                        -- pass (runs after) is never stomped on unchanged passes.
                        local fdRv = hookFrameData[frame]
                        local fcRv = _ecmeFC[frame]
                        local wantRev = ((fcRv and fcRv.isHostedBuff)
                            or (fdRv and fdRv._isBuffViewerFrame)
                            or frame._isPlaceholderFrame) and true or false
                        if fdRv and fdRv._revKind ~= wantRev then
                            fdRv._revKind = wantRev
                            frame.Cooldown:SetReverse(wantRev)
                        end
                        local hcd = hideCDText
                        if ns.CdmShouldHideCountdown then hcd = ns.CdmShouldHideCountdown(frame, hcd) end
                        frame.Cooldown:SetHideCountdownNumbers(hcd)
                    end
                    -- Reparent custom frames to our container (never to Blizzard viewers)
                    -- and force click-through. Something in the Decorate /
                    -- Show / SetParent / Cooldown path re-enables mouse on
                    -- these frames despite our creation-time EnableMouse(false),
                    -- so we re-disable them defensively here (mirroring the
                    -- custom aura bar pattern at ~L1792).
                    if frame._isRacialFrame or frame._isTrinketFrame
                       or frame._isPresetFrame or frame._isItemPresetFrame
                       or frame._isCustomSpellFrame then
                        if frame:GetParent() ~= container then
                            frame:SetParent(container)
                        end
                        -- Mouse motion (OnEnter/OnLeave) only while this bar's
                        -- tooltips are on -- a motion-enabled icon steals
                        -- mouseover focus from unit frames underneath (raid
                        -- frame hover highlight, [@mouseover] casts). Clicks
                        -- always pass through. Cursor-anchored bars stay fully
                        -- mouse-through: re-enabling mouse here would undo the
                        -- click-through set by SetFrameClickThrough.
                        local isCursorBar = container and container._mouseTrack
                        local bdHover = barDataByKey and barDataByKey[barKey]
                        if bdHover and bdHover.showTooltip and not isCursorBar then
                            frame:EnableMouse(true)
                            if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
                            if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
                        else
                            frame:EnableMouse(false)
                            if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                        end
                        if frame.Cooldown then
                            frame.Cooldown:EnableMouse(false)
                            if frame.Cooldown.SetMouseClickEnabled then
                                frame.Cooldown:SetMouseClickEnabled(false)
                            end
                            if frame.Cooldown.SetMouseMotionEnabled then
                                frame.Cooldown:SetMouseMotionEnabled(false)
                            end
                        end
                    end
                    -- Cursor-anchored bars must stay fully mouse-through on
                    -- EVERY icon, native viewer icons included -- the branch
                    -- above only re-asserts our own custom frames, but the
                    -- same Decorate/Show/SetParent/Cooldown path can re-enable
                    -- mouse on native icons. A mouse-enabled icon riding the
                    -- cursor intermittently kills [@mouseover] hovercast keys
                    -- while frame focus still looks correct.
                    if container and container._mouseTrack then
                        frame:EnableMouse(false)
                        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                        if frame.Cooldown then frame.Cooldown:EnableMouse(false) end
                    end
                    -- Active state hooks handled in DecorateFrame (SetSwipeColor
                    -- hook on every frame, forces our color always).
                end

                -- Clear excess icons. Skip frames still in the active set
                -- (a frame can shift from slot N+1 to slot N when an icon
                -- is removed, so old slot N+1 == new slot N).
                local newCount = #frames
                for i = newCount + 1, #icons do
                    if icons[i] and not usedFrames[icons[i]] then
                        local efd = hookFrameData[icons[i]]
                        if efd then efd._cdmAnchor = nil end
                        local isCustom = icons[i]._isRacialFrame or icons[i]._isTrinketFrame
                            or icons[i]._isPresetFrame or icons[i]._isItemPresetFrame
                            or icons[i]._isCustomSpellFrame
                        if isCustom then
                            icons[i]:ClearAllPoints()
                            icons[i]:Hide()
                        else
                            icons[i]:SetAlpha(0)
                        end
                        if icons[i].Cooldown and icons[i].Cooldown.SetDrawSwipe then
                            icons[i].Cooldown:SetDrawSwipe(false)
                        end
                    end
                    icons[i] = nil
                end

                -- Change detection (mirrors Phase 2 buff bars): skip the
                -- expensive Refresh/Layout/Tooltip calls when the icon set
                -- is identical to the previous reanchor. During rotation
                -- spam, OnCooldownIDSet fires per spell cast and queues a
                -- reanchor at the 0.2s throttle; the vast majority of those
                -- reanchors produce the exact same icon list and don't
                -- need the full layout pipeline re-run.
                local prevCount = container._prevVisibleCount or 0
                local iconsChanged = newCount ~= prevCount
                if not iconsChanged and container._prevIconRefs then
                    for idx = 1, newCount do
                        if container._prevIconRefs[idx] ~= icons[idx] then
                            iconsChanged = true; break
                        end
                    end
                else
                    iconsChanged = true
                end
                if iconsChanged then
                    RefreshCDMIconAppearance(barKey)
                    LayoutCDMBar(barKey)
                    ApplyCDMTooltipState(barKey)
                    if not container._prevIconRefs then container._prevIconRefs = {} end
                    for idx = 1, newCount do container._prevIconRefs[idx] = icons[idx] end
                    for idx = newCount + 1, #container._prevIconRefs do
                        container._prevIconRefs[idx] = nil
                    end
                end
                container._prevVisibleCount = newCount
            end
        end
    end

    -- Clean up empty CD/utility bars
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
           and bd.key ~= "buffs" and not cdFrames[bd.key] then
            local icons = cdmBarIcons[bd.key]
            if icons then
                for i = 1, #icons do
                    -- Skip frames another bar claimed this pass: a spell moved off
                    -- this (now empty) bar is still live elsewhere -- alpha-0 /
                    -- swipe-off here would blank it there.
                    if icons[i] and not usedFrames[icons[i]] then
                        local efd = hookFrameData[icons[i]]
                        if efd then efd._cdmAnchor = nil end
                        local isCustom2 = icons[i]._isRacialFrame or icons[i]._isTrinketFrame
                            or icons[i]._isPresetFrame or icons[i]._isItemPresetFrame
                            or icons[i]._isCustomSpellFrame
                        if isCustom2 then
                            icons[i]:ClearAllPoints()
                            icons[i]:Hide()
                        else
                            icons[i]:SetAlpha(0)
                        end
                        if icons[i].Cooldown and icons[i].Cooldown.SetDrawSwipe then
                            icons[i].Cooldown:SetDrawSwipe(false)
                        end
                    end
                    icons[i] = nil
                end
            end
            local container = cdmBarFrames[bd.key]
            if container and (container._prevVisibleCount or 0) > 0 then
                container._prevVisibleCount = 0
                LayoutCDMBar(bd.key)
            end
        end
    end

    ns._spellOrderDirty = false  -- spell order caches are now valid

    -- Re-apply proc glows for any active procs (picks up per-spell settings)
    if ns.ScanExistingProcGlows then ns.ScanExistingProcGlows() end

    ---------------------------------------------------------------------------
    --  PHASE 4: Global cleanup for unclaimed frames
    --  Also protect any frame currently in cdmBarIcons (may be from a
    --  previous reanchor cycle but still visually active on a bar) -- but ONLY
    --  for bars that still exist in the active profile. A profile swap that
    --  removes a bar leaves its old icons in cdmBarIcons (FullCDMRebuild does
    --  not wipe icon arrays here), and protecting those would shield a stale
    --  persistent _trinketFrames trinket (which, unlike _presetFrames racials,
    --  FullCDMRebuild never hides) from the unused-frame sweep below -- leaving
    --  it floating at its old position after its bar is gone.
    ---------------------------------------------------------------------------
    for bk, icons in pairs(cdmBarIcons) do
        if barDataByKey[bk] then
            for ii = 1, #icons do
                if icons[ii] then usedFrames[icons[ii]] = true end
            end
        end
    end
    local buffViewer = _G["BuffIconCooldownViewer"]
    local barViewer  = _G["BuffBarCooldownViewer"]
    for frame in pairs(allActiveFrames) do
        if usedFrames[frame] then
            -- Claimed: leave alone
        elseif frame._isRacialFrame or frame._isTrinketFrame
               or frame._isPresetFrame or frame._isItemPresetFrame
               or frame._isCustomSpellFrame then
            -- Custom frames: managed by their own systems
        else
            local efd = hookFrameData[frame]
            if efd then efd._cdmAnchor = nil end
            local vf = frame.viewerFrame
            if vf == barViewer then
                -- Bar viewer frame: skip entirely when using Blizzard tracked bars
                local pp = ECME.db and ECME.db.profile
                if pp and pp.cdmBars and pp.cdmBars.useBlizzardBuffBars then
                    -- Leave untouched so Blizzard's tracked bars work
                else
                    if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
                        frame.Cooldown:SetDrawSwipe(false)
                    end
                end
            elseif vf == buffViewer then
                -- Buff icon frame: only disable swipe, touch nothing else
                if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
                    frame.Cooldown:SetDrawSwipe(false)
                end
            else
                -- CD/utility frame: unclaimed (unrouted or ghost-bar routed).
                -- Alpha-hide AND park offscreen -- never Hide on Blizzard
                -- pool frames. Hiding a pool frame signals Blizzard that the
                -- pool is stale, which triggers a full viewer rebuild. Spells
                -- that continuously transform (e.g. Lightsmith Holy Armaments)
                -- cause Blizzard to rebuild every tick; if we Hide here, we
                -- amplify that into an infinite rebuild loop.
                --
                -- The park matters as much as the alpha: a frame that was
                -- claimed by the PREVIOUS spec still holds its points on that
                -- spec's bar (e.g. a druid-wide spell assigned on Resto but
                -- ghosted on Guardian), and the engine re-raises item alpha
                -- through paths no hook can see (SetAlphaFromBoolean, alpha
                -- animations) on cooldown/aura state changes such as form
                -- swaps -- resurrecting the icon pinned to the old bar. Parked
                -- offscreen (immediately re-pointed, so the rect stays valid),
                -- every alpha path is harmless. The SetPoint hook re-parks it
                -- if Blizzard's layout moves it while unclaimed; a re-claim
                -- SetPoints absolutely, so recovery is total.
                frame:SetAlpha(0)
                -- TOPLEFT keyword matches LayoutCDMBar's claim SetPoint (no
                -- ClearAllPoints there): same keyword = clean replacement.
                if efd then efd._parkGuard = true end
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
                if efd then efd._parkGuard = nil end
                if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
                    frame.Cooldown:SetDrawSwipe(false)
                end
            end
        end
    end

    -- Hide orphaned custom frames (trinkets, potions, racials, custom
    -- spells) that are no longer referenced by any bar. Custom frames are
    -- never added to allActiveFrames (that table only holds Blizzard viewer
    -- pool frames), so the main Phase 4 loop above cannot see them.
    --
    -- The common case this catches is a spec swap where the new spec has
    -- fewer custom items than the old spec. Phase 3's write loop overwrites
    -- cdmBarIcons[barKey][i] in place, silently losing the reference to the
    -- previous frame at that index without hiding it. The "clear excess"
    -- loop only handles trailing indices (i > #newFrames), so a custom
    -- frame that was at index 1 in the old list gets overwritten and leaks:
    -- it stays shown, still parented to the bar container, and its stale
    -- SetPoint anchor drifts with the container on the new spec's layout.
    --
    -- Trinket frames are the most obvious offender because _trinketFrames
    -- is persistent across spec swaps (unlike _presetFrames, which gets
    -- wiped in FullCDMRebuild). Preset frames are handled belt-and-
    -- suspenders here too: the spec-swap wipe hides them, but any other
    -- path that removes a preset from assignedSpells without going through
    -- FullCDMRebuild would leak without this sweep.
    --
    -- Custom BUFF frames (f._isCustomBuffFrame) are skipped: their
    -- lifecycle lives in UpdateCustomBuffBars on a separate ticker, and
    -- hiding them here would flicker against that ticker's next Show call.
    for _, tf in pairs(_trinketFrames) do
        if tf and not usedFrames[tf] then
            tf:ClearAllPoints()
            tf:Hide()
        end
    end
    for _, pf in pairs(_presetFrames) do
        if pf and not pf._isCustomBuffFrame and not usedFrames[pf] then
            pf:ClearAllPoints()
            pf:Hide()
        end
    end

    if not ns._initialReanchorDone then ns._initialReanchorDone = true end

    -- Per-spec migration: convert pre-refactor "assignedSpells as content
    -- filter" data into "ghost-bar diversion" data. Must run AFTER reanchor
    -- because it walks the live viewer pools, which only get populated by
    -- Blizzard's CDM after our init code runs. The first reanchor that
    -- completes for a spec is the earliest moment we can guarantee the
    -- pools have content.
    --
    -- Per-spec flag is checked inside the migration, so this call is a
    -- no-op for already-migrated specs. After a successful migration, we
    -- rebuild the route map (so the new ghost entries become diversions)
    -- and queue another reanchor (so the now-ghost-routed frames get
    -- moved out of the default bars).
    if ns.MigrateSpecToBarFilterModelV6 then
        local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
        local prof = sp and specKey and sp[specKey]
        local needsMigration = prof and not prof._barFilterModelV6
        if needsMigration then
            local added = ns.MigrateSpecToBarFilterModelV6()
            if added and added > 0 then
                if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                if ns.QueueReanchor then ns.QueueReanchor() end
            end
        end
        -- Automatic base-bar materialization (once per spec per session):
        -- untouched default-bar spells render through the frames-as-truth
        -- fallback without ever being recorded in assignedSpells, so export
        -- strings shipped incomplete stores and the import ghost pass hid
        -- exactly those spells on every recipient. Reseed from the live
        -- icons -- ONLY after the one-shot migration has stamped (a legacy
        -- un-migrated store must migrate first or old-model spillovers
        -- would materialize), never while an import's ghosting is pending
        -- (Reseed self-guards too), and buff-family bars excluded
        -- (cdUtilOnly: picker-authoritative). The session flag is wiped on
        -- talent/loadout changes so newly learned spells re-materialize.
        if ns.ReseedAssignedSpellsFromLiveIcons and prof
           and prof._barFilterModelV6 and not prof._importGhostMode then
            ns._reseededSpecsSession = ns._reseededSpecsSession or {}
            if not ns._reseededSpecsSession[specKey] then
                ns._reseededSpecsSession[specKey] = true
                ns.ReseedAssignedSpellsFromLiveIcons(true)
            end
        end
    end

    -- Per-spec one-shot: fold legacy dormantSpells back into assignedSpells
    -- at their saved slot index. Under the new "assignedSpells is pure user
    -- intent" model, dormant entries are restored so spells the old
    -- reconcile system evicted (pet abilities, choice-node talents) return
    -- to the user's chosen position. Rebuild the route map afterward so
    -- the revived entries become diversions.
    if ns.MergeDormantSpellsIntoAssigned then
        local specKey2 = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        local sp2 = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
        local prof2 = sp2 and specKey2 and sp2[specKey2]
        if prof2 and not prof2._dormantMerged then
            ns.MergeDormantSpellsIntoAssigned()
            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
            if ns.QueueReanchor then ns.QueueReanchor() end
        end
    end

    if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end

    -- Authoritative final layout pass. Set by CDMFinishSetup (login) and
    -- ProcessSpecChange (spec swap). Gated on ns._spellsReadyForApply so the
    -- pass only runs once Blizzard's viewer pools are guaranteed populated
    -- (same readiness signal ProcessSpecChange uses). On login the pending
    -- flag is set synchronously in CDMFinishSetup, but the first reanchor
    -- can fire BEFORE SPELLS_CHANGED arrives; without this gate the pass
    -- would consume the flag against half-populated data and never re-run,
    -- leaving width-matched children (e.g. power bar <- CDM cooldowns)
    -- locked to a stale target width. The SPELLS_CHANGED handler forces
    -- a QueueReanchor when it sees the pending flag still set, so the pass
    -- always fires exactly once with correct source widths.
    if ns._pendingApplyOnReanchor and ns._spellsReadyForApply then
        ns._pendingApplyOnReanchor = nil
        -- CDM is done populating icons; lift the rebuild gate so width
        -- matching can propagate against settled bar widths. Must happen
        -- BEFORE ApplyAllWidthHeightMatches so it isn't gated off.
        if EllesmereUI then EllesmereUI._cdmRebuilding = nil end
        -- Defer position/width corrections to next frame. These are purely
        -- visual positioning operations (width match, saved positions,
        -- anchor reapply) that cost ~25ms synchronously but are
        -- imperceptible if they settle 1 frame late.
        C_Timer.After(0, function()
            if EllesmereUI.ApplyAllWidthHeightMatches then
                EllesmereUI.ApplyAllWidthHeightMatches()
            end
            if EllesmereUI._applySavedPositions then
                EllesmereUI._applySavedPositions()
            end
            if EllesmereUI.ReapplyAllUnlockAnchorsForced then
                EllesmereUI.ReapplyAllUnlockAnchorsForced()
            end
            -- Arm the settle debounce so any further late resizes (the refresh
            -- ladder / trinket retries) get one more forced re-apply once they
            -- quiesce -- guarantees a first debounce window even if the initial
            -- build's resizes fired before the OnSizeChanged hook was installed.
            if EllesmereUI.ScheduleSettleReapply then
                EllesmereUI.ScheduleSettleReapply()
            end
        end)
    else
        -- Routine reanchor (icon churn, mob death, etc.) -- still clear
        -- the gate so subsequent layout calls don't get stuck.
        if EllesmereUI then EllesmereUI._cdmRebuilding = nil end
    end

    -- Refresh the options-panel preview (if open) so the content header
    -- reflects the icons we just populated. Without this, the preview
    -- shows empty on login/spec swap because it builds before the first
    -- queued CollectAndReanchor fires.
    if EllesmereUI and EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
        local pv = EllesmereUI._contentHeaderPreview
        if pv and pv.Update then pv:Update() end
    end
end
ns.CollectAndReanchor = CollectAndReanchor

-------------------------------------------------------------------------------
--  UpdateCustomBuffBars
--  Custom Aura bars use UNIT_SPELLCAST_SUCCEEDED to detect usage,
--  then show icon with hardcoded duration (reverse cooldown swipe).
--  (_customAuraTimers is declared earlier so the buff-phase injection in
--  CollectAndReanchor can read the same live timers.)
-------------------------------------------------------------------------------

-- Per-icon "Audio on Buff Gain" for self-timed preset/custom buffs (potions,
-- Bloodlust/Heroism, Light's Potential, user-added custom buff IDs). These never
-- fire Blizzard's TriggerAuraAppliedAlert -- they appear on a cast/edge for a
-- fixed window -- so the regular-buff apply-edge hook can't reach them. We play
-- the SAME stored key (ss.buffActiveSoundKey) here, off the cast edge that
-- (re)starts the icon's timer. No loss sound: the real aura is secret/other-cast,
-- so only the gain edge is knowable. The id comes straight from the bar's
-- assignedSpells (clean, never secret), so the lookup is a direct spellSettings
-- hit -- no GetCanonicalSpellIDForFrame dance. Gated 0-cost on ns._cdmAnyBuffSound
-- (the same flag RescanBuffSoundFlag sets from these very spellSettings) and
-- throttled so a refresh-cast a few frames apart can't double-fire.
local _presetGainSoundAt = {}
local _presetLossSoundAt = {}
local PRESET_GAIN_SOUND_GAP = 0.3
local function PlayPresetBuffGainSound(sd, barKey, sid, now)
    if not ns._cdmAnyBuffSound then return end
    -- Loading screen / login settle: cast/edge timers restart across a zone/login,
    -- which would false-fire the gain sound. Drop while suppressed.
    if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
    -- Family store direct hit + bar-tier fallback (no frame: id from assignedSpells).
    local ss = ResolveSpellSettings(nil, sid, sd, barKey)
    local key = ss and ss.buffActiveSoundKey
    if not key or key == "none" then return end
    local last = _presetGainSoundAt[sid]
    if last and (now - last) < PRESET_GAIN_SOUND_GAP then return end
    _presetGainSoundAt[sid] = now
    local paths = ns.FOCUSKICK_SOUND_PATHS
    local path = paths and paths[key]
    if path then PlaySoundFile(path, "Master") end
end
-- Loss counterpart to PlayPresetBuffGainSound for self-timed preset/custom buffs
-- (no real aura-removed alert): fired when the displayed timer runs out. Separate
-- throttle table so gain/loss never suppress each other.
local function PlayPresetBuffLossSound(sd, sid, now)
    if not ns._cdmAnyBuffSound then return end
    if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
    local ss = sd and sd.spellSettings and sd.spellSettings[sid]
    local key = ss and ss.buffLostSoundKey
    if not key or key == "none" then return end
    local last = _presetLossSoundAt[sid]
    if last and (now - last) < PRESET_GAIN_SOUND_GAP then return end
    _presetLossSoundAt[sid] = now
    local paths = ns.FOCUSKICK_SOUND_PATHS
    local path = paths and paths[key]
    if path then PlaySoundFile(path, "Master") end
end

local function UpdateCustomBuffBars()
    if not ECME then return end
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end
    local LayoutCDMBar = ns.LayoutCDMBar
    local RefreshCDMIconAppearance = ns.RefreshCDMIconAppearance
    local cdmPageOpen = ns._cdmBarsPageOpen or false
    local now = GetTime()

    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled and barData.barType == "custom_buff" then
            local barKey = barData.key
            local container = cdmBarFrames[barKey]
            if container then
                local sd = ns.GetBarSpellData(barKey)
                local spellList = sd and sd.assignedSpells or {}
                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local count = 0

                for _, sid in ipairs(spellList) do
                    if type(sid) == "number" and sid > 0 then
                        local duration = sd.spellDurations and sd.spellDurations[sid] or 0
                        if duration > 0 then
                            local timerKey = barKey .. ":" .. sid
                            local timer = _customAuraTimers[timerKey]

                            if _pendingCastIDs[sid] and duration > 0 then
                                _customAuraTimers[timerKey] = {
                                    start = now,
                                    duration = duration,
                                }
                                timer = _customAuraTimers[timerKey]
                                PlayPresetBuffGainSound(sd, barKey, sid, now)
                            end

                            -- Loss edge: displayed timer ran out -> fire once, drop it.
                            if timer and (now - timer.start) >= timer.duration then
                                PlayPresetBuffLossSound(sd, sid, now)
                                _customAuraTimers[timerKey] = nil
                                timer = nil
                            end

                            local isActive = timer and duration > 0
                                and (now - timer.start) < timer.duration

                            if isActive or cdmPageOpen then
                                local fkey = barKey .. ":custombuff:" .. sid
                                local f = _presetFrames[fkey]
                                if not f then
                                    f = CreateFrame("Frame", nil, UIParent)
                                    f:SetSize(36, 36); f:Hide()
                                    f:EnableMouse(false)
                                    local tex = f:CreateTexture(nil, "ARTWORK")
                                    tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                    f.Icon = tex; f._tex = tex
                                    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                    cd:SetHideCountdownNumbers(not barData.showCooldownText)
                                    cd:SetReverse(true)
                                    f.Cooldown = cd; f._cooldown = cd
                                    f._isCustomSpellFrame = true
                                    f._isCustomBuffFrame = true
                                    f.cooldownID = nil; f.cooldownInfo = nil
                                    f.layoutIndex = 99999
                                    _presetFrames[fkey] = f
                                    cd:HookScript("OnCooldownDone", function()
                                        C_Timer.After(0, QueueCustomBuffUpdate)
                                    end)
                                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                                    if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                                end
                                if isActive and timer then
                                    f._cooldown:SetCooldown(timer.start, timer.duration)
                                else
                                    f._cooldown:Clear()
                                end
                                DecorateFrame(f, barData); f:Show()
                                f:EnableMouse(false)
                                if f.Cooldown and f.Cooldown.SetDrawSwipe then
                                    -- Only Show Numbers hides the swipe with the icon art.
                                    f.Cooldown:SetDrawSwipe(not barData.onlyShowNumbers)
                                end
                                count = count + 1
                                icons[count] = f
                            else
                                local fkey = barKey .. ":custombuff:" .. sid
                                local f = _presetFrames[fkey]
                                if f then f:Hide() end
                                if timer and not isActive then
                                    _customAuraTimers[timerKey] = nil
                                end
                            end
                        end
                    end
                end

                for i = count + 1, #icons do
                    if icons[i] then icons[i]:Hide() end
                    icons[i] = nil
                end

                -- Custom aura bars are display-only, never clickable
                container:EnableMouse(false)
                if container.EnableMouseClicks then container:EnableMouseClicks(false) end
                if container.EnableMouseMotion then pcall(container.EnableMouseMotion, container, false) end

                local prevCount = container._prevVisibleCount or 0
                if count ~= prevCount then
                    if RefreshCDMIconAppearance then RefreshCDMIconAppearance(barKey) end
                    if LayoutCDMBar then LayoutCDMBar(barKey) end
                end
                container._prevVisibleCount = count
            end
        end
    end

    -- Buff-family bars: custom/preset buffs are injected + rendered by
    -- CollectAndReanchor's buff phase. Here we only run cast detection: when a
    -- pending cast matches a custom buff on a buff bar, (re)start its timer and
    -- queue a reanchor so the icon appears. Expiry is handled by the frame's
    -- OnCooldownDone hook (which also reanchors to drop the icon).
    local needBuffReanchor = false
    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled and barData.barType == "buffs" then
            local sd = ns.GetBarSpellData(barData.key)
            local spellList = sd and sd.assignedSpells
            local durs = sd and sd.spellDurations
            if spellList and durs then
                for _, sid in ipairs(spellList) do
                    if type(sid) == "number" and sid > 0 and (durs[sid] or 0) > 0 then
                        local tkey = barData.key .. ":" .. sid
                        if _pendingCastIDs[sid] then
                            _customAuraTimers[tkey] = {
                                start = now, duration = durs[sid],
                            }
                            needBuffReanchor = true
                            PlayPresetBuffGainSound(sd, barData.key, sid, now)
                        else
                            -- Loss edge: displayed window ran out -> fire once, drop timer.
                            local t = _customAuraTimers[tkey]
                            if t and (now - t.start) >= t.duration then
                                PlayPresetBuffLossSound(sd, sid, now)
                                _customAuraTimers[tkey] = nil
                                needBuffReanchor = true
                            end
                        end
                    end
                end
            end
        end
    end
    if needBuffReanchor and ns.QueueReanchor then ns.QueueReanchor() end

    wipe(_pendingCastIDs)
end
ns.UpdateCustomBuffBars = UpdateCustomBuffBars

function ns.UpdateCustomBuffAuraTracking() end

-------------------------------------------------------------------------------
--  Lightweight position re-snap: re-applies stored _cdmAnchor on all claimed
--  icons without re-enumerating viewers or re-categorizing frames.
--  Used by OnActiveStateChanged where Blizzard may move frames but the icon
--  list hasn't changed.
-------------------------------------------------------------------------------
local function ReapplyPositions()
    for barKey, icons in pairs(cdmBarIcons) do
        if icons then
            for i = 1, #icons do
                local frame = icons[i]
                if frame then
                    local fd = hookFrameData[frame]
                    local anchor = fd and fd._cdmAnchor
                    if anchor then
                        frame:ClearAllPoints()
                        frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Reanchor Queue
-------------------------------------------------------------------------------
local REANCHOR_THROTTLE = 0.2
local _lastReanchorTime = 0

local function QueueReanchor()
    -- Always queue, never drop. If a spec swap is in progress the
    -- ProcessReanchorQueue gate will hold the request until the flag
    -- clears, then the queued reanchor fires naturally.
    reanchorDirty = true
    if reanchorFrame then reanchorFrame:Show() end
end
ns.QueueReanchor = QueueReanchor

-- Cancel any pending queued reanchor. Used by FullCDMRebuild's spec swap
-- branch when it runs CollectAndReanchor directly -- without this, the
-- reanchor BuildAllCDMBars queued earlier in the same call would fire a
-- second time after the throttle expires.
local function ClearQueuedReanchor()
    reanchorDirty = false
end
ns.ClearQueuedReanchor = ClearQueuedReanchor

local function ProcessReanchorQueue(self)
    if not reanchorDirty then self:Hide(); return end
    local now = GetTime()
    if now - _lastReanchorTime < REANCHOR_THROTTLE then return end
    reanchorDirty = false
    _lastReanchorTime = now
    CollectAndReanchor()
    -- Reapply visibility: newly collected icons may be at alpha 0.
    if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
end

-------------------------------------------------------------------------------
--  Sync extra buff bars with Blizzard CDM viewer
--
--  Reanchor extra buff bars shortly after the Blizzard CDM settings panel
--  closes, once Blizzard has finished rebuilding its viewer pools.
--
--  HISTORY -- do NOT reintroduce frame-pool-based orphan pruning here.
--  This used to ALSO strip "orphan" spells from each extra buff bar: any
--  positive assignedSpells entry whose spellID wasn't found in the BuffIcon
--  pool (or, later, the CDM category set) was deleted. That caused data loss
--  on DUAL-TRACKED spells that carry more than one variant spell ID:
--    * Vengeance DH stores Metamorphosis on a custom buff bar as 191427, but
--      every live Vengeance frame reports 187827. 191427 is surfaced ONLY by
--      the buff frame's linkedSpellIDs, and ONLY while the buff is active.
--    * This sync runs ~0.3s after the panel closes, when Meta is down -- so
--      191427 matched neither the (empty) buff pool nor the category set, and
--      got deleted. Worse, deleting it destroyed the route-map diversion, so
--      re-tracking Meta spilled it onto the DEFAULT buffs bar.
--  No state-independent check (pool / category / IsPlayerSpell / variant
--  family) can recognize 191427 while Meta is inactive, so the prune is
--  unfixable for this class of spell. An untracked buff now simply lingers as
--  a harmless non-rendering preview entry (removable by hand) -- consistent
--  with how the CD/utility side already behaves.
-------------------------------------------------------------------------------
function ns.SyncExtraBuffBarsWithViewer()
    QueueReanchor()
end

-------------------------------------------------------------------------------
--  SetupViewerHooks (mixin hooks)
--
--  Hook strategy:
--    1. OnCooldownIDSet on all 4 Blizzard CDM mixins -> QueueReanchor
--    2. Pool Acquire on all viewers -> QueueReanchor
--    3. Viewer Layout -> QueueReanchor (catches frame removals)
--    4. Buff ticker (0.1s) for staleness + glow
-------------------------------------------------------------------------------
function ns.SetupViewerHooks()
    if viewerHooksInstalled then return end
    viewerHooksInstalled = true

    -- Reanchor queue frame
    reanchorFrame = CreateFrame("Frame")
    reanchorFrame:SetScript("OnUpdate", ProcessReanchorQueue)
    reanchorFrame:Hide()

    -- 1. Mixin hooks: detect spell changes on CDM frames.
    --    Reset frame spell cache so the next reanchor re-resolves the spellID
    --    (handles spell transforms like Avenging Crusader -> Crusader Strike).
    --
    --    CD/utility bars: spell set is locked during a session. Changes only
    --    happen via FullCDMRebuild (spec/talent/equip events). Real-time
    --    reanchors from OnCooldownIDSet are unnecessary and catastrophic when
    --    Blizzard continuously rebuilds pools (Lightsmith Holy Armaments).
    --    We still clear the FC cache so the NEXT rebuild re-resolves correctly.
    --
    --    Buff bars: buffs are dynamic (appear/disappear at runtime), so they
    --    still need real-time reanchors from OnCooldownIDSet.
    local function ResetFrameCache(frame)
        if frame then
            local fc = _ecmeFC[frame]
            if fc then
                fc.resolvedSid = nil
                fc.baseSpellID = nil
                fc.overrideSid = nil
                fc.cachedCdID = nil
            end
        end
    end
    -- Buff mixins: clear cache + reanchor (dynamic)
    if CooldownViewerBuffIconItemMixin and CooldownViewerBuffIconItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffIconItemMixin, "OnCooldownIDSet", function(frame)
            ResetFrameCache(frame)
            QueueReanchor()
        end)
    end
    if CooldownViewerBuffBarItemMixin and CooldownViewerBuffBarItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffBarItemMixin, "OnCooldownIDSet", function(frame)
            if ns.InvalidateTBBFrameCache then ns.InvalidateTBBFrameCache() end
            ResetFrameCache(frame)
            QueueReanchor()
        end)
    end
    -- CD/utility mixins: clear cache only (static set, rebuilt by FullCDMRebuild)
    if CooldownViewerEssentialItemMixin and CooldownViewerEssentialItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerEssentialItemMixin, "OnCooldownIDSet", ResetFrameCache)
    end
    if CooldownViewerUtilityItemMixin and CooldownViewerUtilityItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerUtilityItemMixin, "OnCooldownIDSet", ResetFrameCache)
    end

    -- (Per-spell Custom Icon re-assert is NOT hooked here: mixin-table hooks
    -- never fire for item frames created before install, because the mixin's
    -- functions are copied onto each frame instance at creation. The re-assert
    -- is a per-frame instance hook installed lazily by ApplyCustomIcon.)

    -- 2. Pool acquire hooks: detect new frames + install per-frame hooks
    -- Track which frames have been hooked (weak-keyed, no taint)
    local _activeStateHooked = setmetatable({}, { __mode = "k" })
    local _activeStateReanchorPending = false

    local function InstallBuffFrameHooks(viewer)
        if not viewer or not viewer.itemFramePool then return end
        -- Attach the buff gain/loss sound hook here -- at pool-acquire time, BEFORE
        -- Blizzard finishes setting the frame up and fires its first
        -- TriggerAuraAppliedAlert. Installing it lazily in DecorateFrame ran one step
        -- too late on a frame's FIRST activation, so the very first "buff gained" cue
        -- was missed (loss + later gains worked because the hook then persisted).
        -- EnsureBuffSoundHook self-guards (hooks once), gated 0-cost on the feature.
        local ensureSound = ns._cdmAnyBuffSound and ns.EnsureBuffSoundHook
        for frame in viewer.itemFramePool:EnumerateActive() do
            if ensureSound then ns.EnsureBuffSoundHook(frame) end
            if not _activeStateHooked[frame] then
                _activeStateHooked[frame] = true
                -- Hook OnActiveStateChanged: Blizzard calls this when a buff
                -- becomes active/inactive. Run a full reanchor so new/removed
                -- icons get collected and centered. Batched via C_Timer to
                -- collapse the spam (fires many times per frame).
                if frame.OnActiveStateChanged then
                    local _asDeferFrame = CreateFrame("Frame")
                    _asDeferFrame:Hide()
                    local _asDeferTicks = 0
                    _asDeferFrame:SetScript("OnUpdate", function(self)
                        _asDeferTicks = _asDeferTicks + 1
                        if _asDeferTicks < 2 then return end
                        self:Hide()
                        _activeStateReanchorPending = false
                        CollectAndReanchor()
                    end)
                    hooksecurefunc(frame, "OnActiveStateChanged", function()
                        ReapplyPositions()
                        if _activeStateReanchorPending then return end
                        _activeStateReanchorPending = true
                        _asDeferTicks = 0
                        _asDeferFrame:Show()
                    end)
                end
            end
        end
    end

    for vi, vName in ipairs(VIEWER_NAMES) do
        local v = _G[vName]
        if v and v.itemFramePool then
            local isBuff = (vi == 3 or vi == 4) -- BuffIcon or BuffBar
            local isBarViewer = (vi == 4) -- BuffBarCooldownViewer
            hooksecurefunc(v.itemFramePool, "Acquire", function()
                if isBuff then InstallBuffFrameHooks(v) end
                if isBarViewer and ns.InvalidateTBBFrameCache then
                    ns.InvalidateTBBFrameCache()
                end
                -- A new tracked-bar spell acquires a pool frame here: let the
                -- Tracking Bars auto-add pass pick it up (debounced, no-op
                -- unless a never-seen spell appeared).
                if isBarViewer and ns.QueueTBBAutoAdd then
                    ns.QueueTBBAutoAdd()
                end
                -- Only buff viewers need real-time reanchors on Acquire.
                -- CD/utility spell sets are static (rebuilt by FullCDMRebuild).
                if isBuff then QueueReanchor() end
            end)
            -- Hook existing frames too
            if isBuff then InstallBuffFrameHooks(v) end

            -- Intercept newly acquired frames the instant Blizzard creates
            -- them, before they render at the viewer's default position.
            -- Alpha 0 until our reanchor claims and positions them.
            -- The pool Acquire hook above already queues a reanchor.
            -- Skip during init: on /reload ALL frames are acquired at once
            -- and our reanchor hasn't run yet, so blanking them would hide
            -- all buffs until the first buff change.
            if v.OnAcquireItemFrame then
                hooksecurefunc(v, "OnAcquireItemFrame", function(_, itemFrame)
                    if not ns._initialReanchorDone then return end
                    -- Skip blanking bar viewer children when user wants Blizzard tracked bars
                    if isBarViewer then
                        local pp = ECME.db and ECME.db.profile
                        if pp and pp.cdmBars and pp.cdmBars.useBlizzardBuffBars then return end
                    end
                    -- CD/utility viewers: spell set is static (rebuilt only by
                    -- FullCDMRebuild on spec/talent/equip). Pool churn from
                    -- spell transforms (e.g. Monk Empty Barrel -> Keg Smash)
                    -- re-acquires frames but does NOT queue a reanchor, so
                    -- blanking here leaves icons invisible with nothing to
                    -- restore them. The SetPoint hook already handles
                    -- repositioning for these viewers.
                    if not isBuff then return end
                    if itemFrame then
                        -- Only blank frames we haven't seen before. During
                        -- pool churn (e.g. Lightsmith Holy Armaments transform
                        -- every tick), Blizzard releases and re-acquires ALL
                        -- frames. Blanking already-decorated frames causes
                        -- the entire bar to flicker alpha 0 -> barOpacity
                        -- every cycle. Previously-decorated frames keep their
                        -- current alpha; our SetPoint hook handles positioning.
                        local fd = hookFrameData[itemFrame]
                        if fd and fd.decorated then
                            -- Recycled frame: briefly hide at Blizzard's position
                            -- until CollectAndReanchor repositions it into our bar.
                            -- Without this, the frame flashes at the wrong spot
                            -- for 1 frame before snapping into place.
                            itemFrame:SetAlpha(0)
                            return
                        end
                        itemFrame:SetAlpha(0)
                        if itemFrame.Cooldown and itemFrame.Cooldown.SetDrawSwipe then
                            itemFrame.Cooldown:SetDrawSwipe(false)
                        end
                    end
                end)
            end
        end
    end

    -- 3. Viewer Layout hooks (Essential + Utility only).
    -- Buff viewers are dynamic and positioned per-frame by CollectAndReanchor;
    -- hooking Layout on them causes taint when Blizzard calls it internally.
    local SYNC_VIEWERS = {
        EssentialCooldownViewer = "cooldowns",
        UtilityCooldownViewer   = "utility",
    }
    for viewerName, barKey in pairs(SYNC_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer then
            -- No reanchor from RefreshLayout or Layout on CD/utility viewers.
            -- CD/utility spell sets are static -- rebuilt by FullCDMRebuild
            -- on spec/talent/equip events only. SetPoint hook on each icon
            -- handles positioning when Blizzard calls Layout.
            local function SyncViewerToBar()
                if InCombatLockdown() then return end
                local container = cdmBarFrames[barKey]
                if not container then return end
                viewer:ClearAllPoints()
                viewer:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
                viewer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            end
            hooksecurefunc(viewer, "Layout", SyncViewerToBar)
            hooksecurefunc(viewer, "SetPoint", function(_, _, relativeTo)
                if InCombatLockdown() then return end
                local container = cdmBarFrames[barKey]
                if relativeTo == container then return end
                SyncViewerToBar()
            end)
            SyncViewerToBar()
        end
    end

    -- 3b. Buff viewer RefreshLayout hooks: IMMEDIATE reanchor so buff
    -- icons appear at our positions instantly (no 0.2s flash). A minimal
    -- time guard collapses the spam when Blizzard rebuilds all pools
    -- every tick (Lightsmith Holy Armaments churn) without adding latency
    -- to real buff procs. 0.05s = one frame at 20 fps.
    local _lastDirectReanchor = 0
    local DIRECT_REANCHOR_GUARD = 0.05
    local function DirectBuffReanchor()
        local now = GetTime()
        if now - _lastDirectReanchor < DIRECT_REANCHOR_GUARD then return end
        _lastDirectReanchor = now
        CollectAndReanchor()
    end
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer and buffViewer.RefreshLayout then
        hooksecurefunc(buffViewer, "RefreshLayout", DirectBuffReanchor)
    end
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    if buffBarViewer and buffBarViewer.RefreshLayout then
        hooksecurefunc(buffBarViewer, "RefreshLayout", DirectBuffReanchor)
    end

    -- 4. CooldownViewerSettings show/hide: force reanchor.
    -- When CDM settings panel closes, Blizzard may re-layout its viewers.
    -- Queue a reanchor to re-sync our bar positions.  Also sync extra buff
    -- bars: spells removed from Blizzard CDM no longer produce viewer frames,
    -- so their assignedSpells entries become orphans stuck in the preview.
    if EventRegistry and EventRegistry.RegisterCallback then
        local cdmSettingsOwner = {}
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow",
            QueueReanchor, cdmSettingsOwner)
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
            C_Timer.After(0.1, QueueReanchor)
            -- Delay sync slightly longer so Blizzard finishes rebuilding pools
            C_Timer.After(0.3, function()
                ns.SyncExtraBuffBarsWithViewer()
            end)
        end, cdmSettingsOwner)
    end

    -- 4b. Delayed reanchor on load: catch frames created after initial setup.
    -- Some buff frames (e.g. Dread Plague) may not exist until Blizzard's
    -- viewer finishes its deferred layout pass. Also invalidate TBB cache
    -- so tracking bars re-scan for late-loading BuffBar viewer frames.
    local function DelayedFullRefresh()
        if ns.InvalidateTBBFrameCache then ns.InvalidateTBBFrameCache() end
        QueueReanchor()
    end
    C_Timer.After(1, DelayedFullRefresh)
    C_Timer.After(3, DelayedFullRefresh)
    C_Timer.After(6, DelayedFullRefresh)

    -- 5. Buff ticker: staleness check + buff/pandemic glow (0.1s)
    do
        local cdmBuffTickFrame = CreateFrame("Frame")
        local cdmBuffAccum = 0
        local _, _cachedClassToken = UnitClass("player")
        cdmBuffTickFrame:SetScript("OnUpdate", function(_, elapsed)
            cdmBuffAccum = cdmBuffAccum + elapsed
            if cdmBuffAccum < 0.1 then return end
            cdmBuffAccum = 0
            MemSnap("BuffTicker")
            local p = ECME and ECME.db and ECME.db.profile
            if not p or not p.cdmBars or not p.cdmBars.bars then return end
            local needsReanchor = false
            for _, bd in ipairs(p.cdmBars.bars) do
                if bd.enabled then
                    local isBuff = (bd.barType == "buffs" or bd.key == "buffs" or bd.barType == "custom_buff")
                    local buffGlowType = isBuff and (bd.buffGlowType or 0) or 0
                    local pandemicOn = bd.pandemicGlow
                    local icons = cdmBarIcons[bd.key]
                    if icons then
                        for fi = 1, #icons do
                            local frame = icons[fi]
                            if frame and frame:IsShown() then
                                local fc = _ecmeFC[frame]
                                local sid = fc and fc.resolvedSid
                                local fd = hookFrameData[frame]
                                -- A buff ICON (whether on a buffs bar, or a real Blizzard
                                -- buff frame hosted on a CD/util bar, or a placeholder for
                                -- an inactive hosted buff) gets the buff glow/desat logic
                                -- below regardless of the hosting bar's family.
                                local isBuffIcon = isBuff or (fd and fd._isBuffViewerFrame)
                                    or frame._isPlaceholderFrame or false

                                local isActiveBuff = (frame.wasSetFromAura == true
                                    or frame.auraInstanceID ~= nil)
                                -- Totems and other non-aura buff-viewer items never set
                                -- wasSetFromAura/auraInstanceID even while up, so the aura
                                -- check above misses them. But Blizzard only SHOWS a buff
                                -- frame while it is active (inactive buffs are hidden; our
                                -- Always-Show injects separate _isPlaceholderFrame frames,
                                -- and presets are our own _isCustomBuffFrame frames). We're
                                -- already inside `frame:IsShown()`, so any shown buff-bar
                                -- frame that is NOT a placeholder is active regardless of
                                -- aura props -- this is what catches totems and presets
                                -- (for both the glow and the desaturate-inactive logic).
                                if not isActiveBuff and isBuffIcon
                                   and not frame._isPlaceholderFrame then
                                    isActiveBuff = true
                                end

                                -- Desaturate inactive buff icons when Always
                                -- Show Buffs is on and Desaturate Off CD is
                                -- enabled. When Always Show Buffs is off,
                                -- desaturation is ignored (no inactive icons
                                -- should be visible anyway).
                                -- Placeholder icons (and any inactive buff) are
                                -- greyed when this bar's Always Show Buffs +
                                -- Desaturate Off CD are on. Per-bar now -- not a
                                -- global. Active real auras stay full color.
                                if isBuffIcon and bd.barType ~= "custom_buff" and fd and fd.tex then
                                    -- A shown, inactive buff icon is present only because
                                    -- Always Show Buffs resolved true for it (bar-level OR
                                    -- per-icon -> placeholder frame). Per-icon Desaturate
                                    -- Inactive (fd._desatOverride) beats the bar's
                                    -- Desaturate Off CD. Active auras stay full color.
                                    -- A HOSTED buff (on a CD/util bar) has no bar toggle, so
                                    -- it defaults ON (desaturate the inactive placeholder --
                                    -- the baked-in "cd ability" look), with no per-icon row.
                                    local desatOn = (bd.desaturateInactiveBuffs ~= false)
                                    if fd._desatOverride == "on" then desatOn = true
                                    elseif fd._desatOverride == "off" then desatOn = false end
                                    if (bd.showInactiveBuffIcons or frame._isPlaceholderFrame)
                                       and desatOn and not isActiveBuff then
                                        fd.tex:SetDesaturated(true)
                                    elseif fd.tex:IsDesaturated() then
                                        fd.tex:SetDesaturated(false)
                                    end
                                end

                                -- Buff glow shows on active buffs. isActiveBuff above
                                -- already counts shown totems and our preset/custom
                                -- own-frames as active, so this just reads it.
                                local glowActive = isActiveBuff
                                    or (bd.barType == "custom_buff" and frame:IsShown())
                                -- Effective Buff Glow = per-icon override (fd._bgT,
                                -- stashed by RefreshCDMIconAppearance) falling back to
                                -- the bar's Buff Glow. nil override => inherit; 0 => None.
                                local effGlowType = buffGlowType
                                if fd and fd._bgT ~= nil then effGlowType = fd._bgT end
                                if effGlowType > 0 and fd and glowActive then
                                    if not fd.buffGlowOverlay then
                                        local ov = CreateFrame("Frame", nil, frame)
                                        ov:SetAllPoints(frame)
                                        ov:EnableMouse(false)
                                        fd.buffGlowOverlay = ov
                                    end
                                    -- Keep the glow above Blizzard's cooldown swipe on
                                    -- every icon. Blizzard increments each viewer icon's
                                    -- base frame level by +1, so an absolute level lands
                                    -- BEHIND the swipe on later icons (and the swipe then
                                    -- clips the inner edge of the ring, making it look
                                    -- thinner). Track the icon's base level and re-apply
                                    -- each pass, matching the primary glowOverlay (+16).
                                    fd.buffGlowOverlay:SetFrameLevel(frame:GetFrameLevel() + 16)
                                    if not fd.buffGlowActive then
                                        local cr, cg, cb
                                        if bd.buffGlowMode == "custom" then
                                            cr, cg, cb = bd.buffGlowR, bd.buffGlowG, bd.buffGlowB
                                        end
                                        local classColor = bd.buffGlowMode == "class"
                                        if fd._bgColor == "class" then
                                            classColor = true
                                        elseif fd._bgColor == "custom" then
                                            classColor = false
                                            cr, cg, cb = fd._bgR or cr, fd._bgG or cg, fd._bgB or cb
                                        end
                                        if classColor then
                                            local cc = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                                            cr, cg, cb = cc.r, cc.g, cc.b
                                        end
                                        fd.buffGlowOverlay:SetAlpha(1)
                                        ns.StartNativeGlow(fd.buffGlowOverlay, effGlowType, cr, cg, cb, {
                                            N      = bd.buffGlowLines or 8,
                                            th     = bd.buffGlowThickness or 2,
                                            period = bd.buffGlowSpeed or 4,
                                            bg     = bd.buffGlowBackground and {
                                                r = bd.buffGlowBackgroundR or 0,
                                                g = bd.buffGlowBackgroundG or 0,
                                                b = bd.buffGlowBackgroundB or 0,
                                            } or nil,
                                        })
                                        fd.buffGlowActive = true
                                    end
                                elseif fd and fd.buffGlowActive and fd.buffGlowOverlay then
                                    ns.StopNativeGlow(fd.buffGlowOverlay)
                                    fd.buffGlowActive = false
                                end

                                -- Pandemic glow: Blizzard's ShowPandemicStateFrame
                                -- hook sets _pandemicState. User must configure
                                -- pandemic alerts in Blizzard CDM settings.
                                if pandemicOn and fd then
                                    local inPandemic = ns._pandemicState[frame]
                                    -- Blizzard Default (-1): skip custom glow,
                                    -- let Blizzard's native PandemicIcon show.
                                    local pStyle = bd.pandemicGlowStyle or 1
                                    if pStyle == -1 then inPandemic = false end
                                    if inPandemic then
                                        if not fd.pandemicOverlay then
                                            local ov = CreateFrame("Frame", nil, frame)
                                            ov:SetAllPoints(frame)
                                            ov:EnableMouse(false)
                                            fd.pandemicOverlay = ov
                                        end
                                        -- Same base-level tracking as the buff glow, one
                                        -- level higher so pandemic sits above buff glow.
                                        fd.pandemicOverlay:SetFrameLevel(frame:GetFrameLevel() + 17)
                                        if not fd.pandemicGlowActive then
                                            local c
                                            if bd.pandemicGlowMode == "class" then
                                                c = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                                            elseif bd.pandemicGlowMode == "custom" then
                                                c = bd.pandemicGlowColor
                                            end
                                            local style = bd.pandemicGlowStyle or 1
                                            local glowOpts = (style == 1) and {
                                                N      = bd.pandemicGlowLines or 8,
                                                th     = bd.pandemicGlowThickness or 2,
                                                period = bd.pandemicGlowSpeed or 4,
                                                bg     = bd.pandemicGlowBackground and {
                                                    r = (bd.pandemicGlowBackgroundColor and bd.pandemicGlowBackgroundColor.r) or 0,
                                                    g = (bd.pandemicGlowBackgroundColor and bd.pandemicGlowBackgroundColor.g) or 0,
                                                    b = (bd.pandemicGlowBackgroundColor and bd.pandemicGlowBackgroundColor.b) or 0,
                                                } or nil,
                                            } or nil
                                            fd.pandemicOverlay:SetAlpha(1)
                                            ns.StartNativeGlow(fd.pandemicOverlay, style, c and c.r, c and c.g, c and c.b, glowOpts)
                                            fd.pandemicGlowActive = true
                                        end
                                    elseif fd.pandemicGlowActive and fd.pandemicOverlay then
                                        ns.StopNativeGlow(fd.pandemicOverlay)
                                        fd.pandemicGlowActive = false
                                    end
                                end

                                -- Stale active glow cleanup: when a DoT
                                -- expires naturally, Blizzard may not call
                                -- SetSwipeColor until the next GCD. Check
                                -- the current swipe color and clear the glow
                                -- if the spell is no longer active.
                                if fd and fd._activeGlowOn then
                                    local swipeColor = frame.cooldownSwipeColor
                                    if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                                        local r = swipeColor:GetRGBA()
                                        -- Only clear if we can confirm r is a clean 0 (not active).
                                        -- If r is secret or unavailable, leave the glow alone.
                                        if r and type(r) == "number" and not issecretvalue(r) and r == 0 then
                                            if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                                            fd._activeGlowOn = false
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if needsReanchor then QueueReanchor() end
            -- Refresh aura active cache. This is the sole maintainer of
            -- _activeCache; bar glow overlays read from ns._tickBlizzActiveCache.
            -- Walk the live pools and mark any frame whose Blizzard-set
            -- wasSetFromAura/auraInstanceID indicates an active aura.
            -- Calls ResolveFrameSpellID (which has its own resolve cache)
            -- so BuffBarCooldownViewer frames -- which CollectAndReanchor
            -- never visits -- still get their fc populated for bar glow
            -- triggers on Tracked Bar spells (Divine Protection etc).
            do
                local ac = _activeCache
                wipe(ac)
                for vi = 1, 4 do
                    local vf = GetViewerFrame(vi)
                    -- BuffIcon (3) / BuffBar (4) viewers SHOW a frame only while its
                    -- buff/effect is active; the cooldown viewers (1,2) always show
                    -- their icons, so "shown" is meaningless there. So in the buff
                    -- viewers a shown, non-placeholder frame counts as active even
                    -- without aura props -- this catches totems and pet-summon
                    -- "buffs" (e.g. Mindbender) that Blizzard never gives an
                    -- auraInstanceID. Mirrors the buff-bar glow logic in BuffTicker.
                    local isBuffViewer = (vi >= 3)
                    if vf and vf.itemFramePool and vf.itemFramePool.EnumerateActive then
                        for frame in vf.itemFramePool:EnumerateActive() do
                            local active = frame.wasSetFromAura == true or frame.auraInstanceID ~= nil
                            if not active and isBuffViewer and frame:IsShown()
                               and not frame._isPlaceholderFrame then
                                active = true
                            end
                            if active then
                                local sid, baseSID = ResolveFrameSpellID(frame)
                                if sid and sid > 0 then
                                    ac[sid] = true
                                    if baseSID and baseSID > 0 then ac[baseSID] = true end
                                    local fc = _ecmeFC[frame]
                                    local linked = fc and fc.linkedSpellIDs
                                    if linked then
                                        for li = 1, #linked do
                                            local lsid = linked[li]
                                            if lsid and lsid > 0 then ac[lsid] = true end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if ns.UpdateOverlayVisuals then ns.UpdateOverlayVisuals() end
            end
            -- Process preset cooldowns (trinkets/items/racials) if any event
            -- dirtied the flag since the last tick. Coalesces dozens of per-GCD
            -- SPELL_UPDATE_COOLDOWN events into a single 10Hz update pass.
            if ns._isPresetCdDirty and ns._isPresetCdDirty() then
                ns._ProcessPresetCooldowns()
            end
            MemDelta("BuffTicker")
        end)
    end

    ns.SyncViewerToContainer = function() end

    -- CDM settings panel: reanchor when user finishes editing
    if CooldownViewerSettings then
        CooldownViewerSettings:HookScript("OnHide", function()
            C_Timer.After(0.3, QueueReanchor)
        end)
    end

    -- EUI options panel: reanchor on show/hide
    EllesmereUI:RegisterOnShow(function()
        C_Timer.After(0.1, function()
            QueueReanchor()
            UpdateCustomBuffBars()
        end)
    end)
    EllesmereUI:RegisterOnHide(function()
        C_Timer.After(0.1, function()
            QueueReanchor()
            UpdateCustomBuffBars()
        end)
    end)

    -- Edit Mode close: full rebuild to restore CDM after Blizzard repositioned viewers.
    -- FullCDMRebuild is combat-safe (only touches our own frames).
    do
        local emf = _G.EditModeManagerFrame
        if emf then
            hooksecurefunc(emf, "Hide", function()
                C_Timer.After(0.1, function()
                    if ns.FullCDMRebuild then ns.FullCDMRebuild("editmode_close") end
                end)
            end)
        end
    end

    -- Listen for EditMode layout updates: Blizzard resets viewer frame
    -- pools when applying a layout (happens on spec swap). Reanchor to
    -- recollect the new frames. No flag manipulation -- just reanchor.
    do
        local emEventFrame = CreateFrame("Frame")
        emEventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        emEventFrame:SetScript("OnEvent", function()
            QueueReanchor()
        end)
    end

    -- Lock EditMode for CDM frames (prevent user changes, avoid taint)
    ns.SetupEditModeLock()

    -- Initial reanchor
    C_Timer.After(0.2, function()
        QueueReanchor()
        UpdateCustomBuffBars()
    end)
end

function ns.IsViewerHooked()
    return viewerHooksInstalled
end

-------------------------------------------------------------------------------
--  EditMode Lock
--  Prevents users from changing CDM viewer settings via EditMode.
--  Hides the settings dialog, disables dragging, shows a lock notice.
-------------------------------------------------------------------------------
local _editModeLockInstalled = false
local _editModeLockNoticeShown = false

local function IsCooldownViewerSystemFrame(frame)
    local cooldownSystem = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
    return cooldownSystem and frame and frame.system == cooldownSystem
end

-- Skip locking the BuffBarCooldownViewer when the user has enabled
-- "Use Blizzard CDM Bars" -- they want to drag/configure that frame in
-- Edit Mode themselves. All other CDM viewers stay locked because EUI
-- manages their position via icon-level anchoring.
local function ShouldLockViewer(frame)
    if frame == _G["BuffBarCooldownViewer"] then
        local p = ECME and ECME.db and ECME.db.profile
        if p and p.cdmBars and p.cdmBars.useBlizzardBuffBars then
            return false
        end
    end
    return true
end

local function ShowEditModeLockNotice()
    if not _editModeLockNoticeShown then
        EllesmereUI.Print("|cff0cd29fEllesmereUI CDM:|r Cooldown Viewer settings are managed by EllesmereUI. Edit Mode changes are disabled.")
        _editModeLockNoticeShown = true
    end
end

local function LockCooldownViewerFrames()
    for _, vName in ipairs(VIEWER_NAMES) do
        local frame = _G[vName]
        if IsCooldownViewerSystemFrame(frame) and ShouldLockViewer(frame) then
            frame:SetMovable(false)
            local selection = frame.Selection
            if selection then
                selection:SetScript("OnDragStart", nil)
                selection:SetScript("OnDragStop", nil)
            end
        end
    end
end

function ns.SetupEditModeLock()
    if _editModeLockInstalled then return end

    local function TrySetup()
        local dialog = _G.EditModeSystemSettingsDialog
        if not (dialog and Enum and Enum.EditModeSystem) then
            return false
        end

        -- When EditMode tries to show the settings dialog for a CDM frame, hide it
        hooksecurefunc(dialog, "AttachToSystemFrame", function(dlg, systemFrame)
            if not IsCooldownViewerSystemFrame(systemFrame) then return end
            if not ShouldLockViewer(systemFrame) then return end
            dlg:Hide()
            ShowEditModeLockNotice()
        end)

        -- When a CDM frame is selected in EditMode, lock it
        for _, vName in ipairs(VIEWER_NAMES) do
            local frame = _G[vName]
            if IsCooldownViewerSystemFrame(frame) then
                hooksecurefunc(frame, "SelectSystem", function(sf)
                    if not ShouldLockViewer(sf) then return end
                    sf:SetMovable(false)
                    if dialog.attachedToSystem == sf then
                        dialog:Hide()
                    end
                    ShowEditModeLockNotice()
                end)

                hooksecurefunc(frame, "HighlightSystem", function() end)

                hooksecurefunc(frame, "ClearHighlight", function() end)
            end
        end

        _editModeLockInstalled = true
        LockCooldownViewerFrames()
        return true
    end

    if not TrySetup() then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", function()
            TrySetup()
        end)
    end
end

-- Swiftmend Brightness Fix (CDM): hooks install via TryHookSwiftmend during
-- DecorateFrame. The scan hook only re-brightens already-hooked icons so the
-- General Settings toggle takes effect immediately when switched on (the
-- SetVertexColor hook reads the toggle live for everything after that).
_G._ECDM_ScanSwiftmend = function()
    if not SwiftmendEnabled() then return end
    for i = 1, #_smHookedIcons do
        _smHookedIcons[i]:SetVertexColor(1, 1, 1)
    end
end

-------------------------------------------------------------------------------
--  Mirror Key Presses  (per-bar: barData.pressMirror -- set in CDM Bars > Extras)
--
--  Show the action-button "pushed down" look on a CDM bar icon whenever you
--  press that ability's keybind -- even while it's on cooldown. Hooks the
--  action-button key-down path (ActionButtonDown / MultiActionButtonDown),
--  which fires on the physical press regardless of cooldown or the cast-on-
--  key-down/up CVar. The pushed texture + colour are read live from the
--  EllesmereUI action bars settings, so the CDM press matches real buttons
--  (falling back to a border-cropped Blizzard depress texture if that module
--  isn't present). Per-frame data lives in an external weak-keyed table.
-------------------------------------------------------------------------------
do
    local AB_MEDIA      = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
    local AB_HIGHLIGHT  = { AB_MEDIA .. "highlight-2.png", AB_MEDIA .. "highlight-3.png", AB_MEDIA .. "highlight-4.png" }
    local DEPRESS_TEX   = "Interface\\Buttons\\UI-Quickslot-Depress"
    local DEPRESS_INSET = 0.14   -- crop the beveled border off the fallback texture
    local MIN_VISIBLE   = 0.05   -- floor so ultra-fast taps still show a press
    local MAX_HOLD      = 2.0    -- safety: never leave an icon stuck "pressed"

    local _pushOverlay = setmetatable({}, { __mode = "k" })  -- [icon] = overlay frame
    local _held  = {}   -- [buttonFrame] = { overlays = {..}, keys = {..}, t = GetTime() }
    local _heldN = 0
    local _poll  = CreateFrame("Frame")
    _poll:Hide()

    -- Read the action bars' pushed settings live so the CDM press matches them.
    local function GetABProfile()
        local L = EllesmereUI and EllesmereUI.Lite
        if not (L and L.GetAddon) then return nil end
        local ok, eab = pcall(L.GetAddon, "EllesmereUIActionBars", true)
        if ok and eab and eab.db then return eab.db.profile end
        return nil
    end

    -- Style tex to match the bars' pushed look. Returns false when pushed is set
    -- to "None" (so the CDM press mirrors that), "border" for border mode, true otherwise.
    local function StylePush(tex)
        local p = GetABProfile()
        if p then
            local pType = p.pushedTextureType or 2
            local c = p.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604 }
            local cr, cg, cb = c.r, c.g, c.b
            if p.pushedUseClassColor then
                local _, ct = UnitClass("player")
                if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
            end
            tex:SetTexCoord(0, 1, 0, 1)
            if p.useBlizzardStyle then
                tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", false)
                tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
                return true
            elseif pType == 6 then
                tex:SetAlpha(0); return false
            elseif pType == 5 then
                tex:SetAlpha(0)
                return "border", cr, cg, cb, p.pushedBorderSize or 4
            end
            tex:SetAlpha(1)
            if pType <= 3 then
                tex:SetAtlas(nil); tex:SetTexture(AB_HIGHLIGHT[pType] or AB_HIGHLIGHT[2]); tex:SetVertexColor(cr, cg, cb, 1)
            elseif pType == 4 then
                tex:SetColorTexture(cr, cg, cb, 0.35)
            end
            return true
        end
        -- Fallback: interior of the Blizzard depress texture (border cropped off).
        tex:SetAtlas(nil)
        tex:SetTexture(DEPRESS_TEX)
        tex:SetTexCoord(DEPRESS_INSET, 1 - DEPRESS_INSET, DEPRESS_INSET, 1 - DEPRESS_INSET)
        tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
        return true
    end

    local function EnsureBorderEdges(ov)
        if ov._borderEdges then return ov._borderEdges end
        local edges = {}
        for j = 1, 4 do
            local t = ov:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetColorTexture(1, 1, 1, 1)
            t:Hide()
            edges[j] = t
        end
        ov._borderEdges = edges
        return edges
    end

    local function ShowPush(icon)
        local ov = _pushOverlay[icon]
        if not ov then
            ov = CreateFrame("Frame", nil, icon)
            ov:SetFrameLevel(icon:GetFrameLevel() + 15)  -- above icon + cooldown swipe
            ov:Hide()
            local tex = ov:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(ov)
            ov._tex = tex
            _pushOverlay[icon] = ov
        end
        local result, cr, cg, cb, bsz = StylePush(ov._tex)
        if not result then ov:Hide(); return nil end
        local region = icon.Icon or icon
        ov:ClearAllPoints()
        ov:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
        ov:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
        if result == "border" then
            ov._tex:Hide()
            local edges = EnsureBorderEdges(ov)
            for j = 1, 4 do edges[j]:SetVertexColor(cr, cg, cb, 1) end
            edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", ov); edges[1]:SetPoint("TOPRIGHT", ov); edges[1]:SetHeight(bsz); edges[1]:Show()
            edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", ov); edges[2]:SetPoint("BOTTOMRIGHT", ov); edges[2]:SetHeight(bsz); edges[2]:Show()
            edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT"); edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT"); edges[3]:SetWidth(bsz); edges[3]:Show()
            edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT"); edges[4]:SetWidth(bsz); edges[4]:Show()
        else
            ov._tex:Show()
            if ov._borderEdges then for j = 1, 4 do ov._borderEdges[j]:Hide() end end
        end
        ov:Show()
        return ov
    end

    ---------------------------------------------------------------------------
    --  Spell matching (pressed button's spell vs. a CDM icon's spell)
    ---------------------------------------------------------------------------
    local GetOverrideSpell      = C_Spell and C_Spell.GetOverrideSpell
    local GetBaseSpell          = C_Spell and C_Spell.GetBaseSpell
    local FindSpellOverrideByID = C_SpellBook and C_SpellBook.FindSpellOverrideByID

    local function safeNum(fn, arg)
        if type(fn) ~= "function" then return nil end
        local ok, res = pcall(fn, arg)
        if ok and type(res) == "number" and res > 0 then return res end
    end

    local function SpellIdSet(id)
        local t = { [id] = true }
        local a = safeNum(GetOverrideSpell, id);      if a then t[a] = true end
        local b = safeNum(GetBaseSpell, id);          if b then t[b] = true end
        local c = safeNum(FindBaseSpellByID, id);     if c then t[c] = true end
        local d = safeNum(FindSpellOverrideByID, id); if d then t[d] = true end
        return t
    end

    local function IconMatches(pressedSet, iconSid)
        if pressedSet[iconSid] then return true end
        local a = safeNum(GetOverrideSpell, iconSid); if a and pressedSet[a] then return true end
        local b = safeNum(GetBaseSpell, iconSid);     if b and pressedSet[b] then return true end
        return false
    end

    local function IconSpellID(icon)
        local fc = _ecmeFC and _ecmeFC[icon]
        local sid = fc and fc.spellID
        if sid then return sid end
        local cdID = icon.cooldownID
        if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if info then return info.overrideSpellID or info.spellID end
        end
        return nil
    end

    ---------------------------------------------------------------------------
    --  Press / hold / release. Release is driven by polling IsKeyDown on the
    --  button's binding keys, floored by MIN_VISIBLE and capped by MAX_HOLD.
    ---------------------------------------------------------------------------
    local function ReleaseEntry(btn, entry)
        local ovs = entry.overlays
        for i = 1, #ovs do ovs[i]:Hide() end
        _held[btn] = nil
        _heldN = _heldN - 1
        if _heldN <= 0 then _heldN = 0; _poll:Hide() end
    end

    _poll:SetScript("OnUpdate", function()
        if _heldN == 0 then _poll:Hide(); return end
        local now = GetTime()
        for btn, entry in pairs(_held) do
            local elapsed = now - entry.t
            local done = false
            if elapsed >= MAX_HOLD then
                done = true
            elseif elapsed >= MIN_VISIBLE then
                local anyDown = false
                local keys = entry.keys
                if keys then
                    for i = 1, #keys do
                        if keys[i] and IsKeyDown(keys[i]) then anyDown = true; break end
                    end
                end
                if not anyDown then done = true end
            end
            if done then ReleaseEntry(btn, entry) end
        end
    end)

    -- Cached enable-flag so OnPress can gate in O(1) instead of looping every
    -- bar on each key press (the ActionButtonDown hook fires for all users).
    -- Recomputed only when the bar list is rebuilt (RefreshCdmPressMirrorFlag,
    -- called from the CDM bar-rebuild pass) or when the toggle changes.
    local _anyPressMirror = false
    local function RefreshCdmPressMirrorFlag()
        _anyPressMirror = false
        if not barDataByKey then return end
        for _, bd in pairs(barDataByKey) do
            -- Buff-family bars never mirror presses (auto-tracked auras, not
            -- keybind-pressed), so ignore a stale/imported pressMirror on them.
            if bd and bd.pressMirror and not ns.IsBarBuffFamily(bd) then _anyPressMirror = true; return end
        end
    end
    ns.RefreshCdmPressMirrorFlag = RefreshCdmPressMirrorFlag
    RefreshCdmPressMirrorFlag()

    local function SlotSpellID(slot)
        if not slot then return nil end
        if HasAction and not HasAction(slot) then return nil end
        -- NOTE (Midnight): GetActionInfo is documented as usable only in the
        -- secure restricted environment. This runs from an insecure post-hook,
        -- so a future build could hand back nil/secret here and silently no-op
        -- the press mirror. Revisit via a secure route if that ever regresses.
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "spell" then
            return id
        elseif actionType == "macro" then
            if subType == "spell" then
                return id
            elseif subType == "item" then
                return nil
            end
            local macroName = GetActionText(slot)
            local macroIndex = macroName and GetMacroIndexByName(macroName)
            if macroIndex and macroIndex > 0 then
                if GetMacroItem and GetMacroItem(macroIndex) then
                    return nil
                end
                return GetMacroSpell(macroIndex)
            end
        end
        return nil
    end

    -- Base key of a (possibly modified) binding, e.g. "SHIFT-1" -> "1".
    local function BaseKey(binding)
        return binding and binding:match("[^%-]+$") or nil
    end

    local function OnPress(btn, bindCmd)
        if not btn or not _anyPressMirror then return end
        local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
        local sid = SlotSpellID(slot)
        if not sid then return end

        local pressedSet = SpellIdSet(sid)
        local overlays
        if cdmBarIcons then
            for barKey, list in pairs(cdmBarIcons) do
                local bd = barDataByKey and barDataByKey[barKey]
                if bd and bd.pressMirror and not ns.IsBarBuffFamily(bd) then
                    for i = 1, #list do
                        local icon = list[i]
                        if icon and icon:IsShown() then
                            local isid = IconSpellID(icon)
                            if isid and IconMatches(pressedSet, isid) then
                                local ov = ShowPush(icon)
                                if ov then overlays = overlays or {}; overlays[#overlays + 1] = ov end
                            end
                        end
                    end
                end
            end
        end
        if not overlays then return end

        local keys
        if bindCmd then
            local k1, k2 = GetBindingKey(bindCmd)
            keys = { BaseKey(k1), BaseKey(k2) }
        end
        local entry = _held[btn]
        if entry then
            entry.overlays = overlays; entry.keys = keys; entry.t = GetTime()
        else
            _held[btn] = { overlays = overlays, keys = keys, t = GetTime() }
            _heldN = _heldN + 1
        end
        _poll:Show()
    end

    -- Public: clear active overlays (called from the CDM Bars > Extras toggle).
    function ns.ClearCdmPressPush()
        for _, entry in pairs(_held) do
            local ovs = entry.overlays
            for i = 1, #ovs do ovs[i]:Hide() end
        end
        wipe(_held); _heldN = 0; _poll:Hide()
        RefreshCdmPressMirrorFlag()
    end

    ---------------------------------------------------------------------------
    --  Hook the action-button key-down path (fires on press, even on cooldown)
    ---------------------------------------------------------------------------
    local MULTIBAR_BINDING = {
        MultiBarBottomLeft  = "MULTIACTIONBAR1BUTTON",
        MultiBarBottomRight = "MULTIACTIONBAR2BUTTON",
        MultiBarRight       = "MULTIACTIONBAR3BUTTON",
        MultiBarLeft        = "MULTIACTIONBAR4BUTTON",
        MultiBar5           = "MULTIACTIONBAR5BUTTON",
        MultiBar6           = "MULTIACTIONBAR6BUTTON",
        MultiBar7           = "MULTIACTIONBAR7BUTTON",
    }

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        if type(ActionButtonDown) == "function" then
            hooksecurefunc("ActionButtonDown", function(id)
                local btn = (GetActionButtonForID and GetActionButtonForID(id)) or _G["ActionButton" .. id]
                OnPress(btn, "ACTIONBUTTON" .. id)
            end)
        end
        if type(MultiActionButtonDown) == "function" then
            hooksecurefunc("MultiActionButtonDown", function(barName, id)
                local prefix = MULTIBAR_BINDING[barName]
                OnPress(_G[barName .. "Button" .. id], prefix and (prefix .. id) or nil)
            end)
        end
    end)
end
