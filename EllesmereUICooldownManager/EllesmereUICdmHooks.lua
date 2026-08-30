if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
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

ns._spellOrderDirty = true  -- start dirty so first reanchor builds caches

-- Per-frame decoration state (weak-keyed)
local hookFrameData = setmetatable({}, { __mode = "k" })
ns._hookFrameData = hookFrameData

-- Force active buff glows to re-apply on the next buff tick (<=0.1s): the tick
-- only (re)starts a glow when fd.buffGlowActive is false, so live option edits
-- (color, pixel Lines/Thickness/Speed) never reach an already-glowing icon.
-- Used by the custom aura preview while CDM Bars options are open.
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

-- Take a pandemic glow down when its icon hides. The buff tick only visits SHOWN
-- frames, so a glow lit at the moment the icon hides -- which is how every
-- pandemic ends, the aura runs out and Blizzard hides the buff icon -- can never
-- reach the tick's stop branch. The textures keep animating on the hidden overlay
-- and come back up WITH the icon on the buff's next application, flashing a
-- pandemic glow over a freshly cast aura until the next tick takes it down.
-- Blizzard's pandemic flag is dropped with it: ShowPandemicStateFrame is the only
-- thing that sets it and it stops being called once the item goes inactive, so a
-- stale true would just re-light the glow on the next tick. Hooked lazily from the
-- overlay build below, so a bar with no pandemic glow never pays for it.
--
-- Clearing the flag is not enough on its own when the aura ends EARLY (dispelled,
-- target lost, pool release) instead of running out. Blizzard computes the
-- pandemic window once, on the aura landing, and never clears it on the way out:
-- CheckSetPandemicAlertTriggerTime returns before touching pandemicStartTime /
-- pandemicEndTime once the aura is inactive. The item is still registered for the
-- viewer's OnUpdate and the viewer never stops running it (visibility of the ITEM
-- is not consulted), so a window whose aura is already gone keeps satisfying
-- IsInPandemicTime and re-sets the flag on the hidden icon a frame later. Re-apply
-- inside that leftover window and the tick lights a full pandemic glow over a
-- fresh aura, held until the DEAD aura's end time passes.
--
-- So the flag is also marked unusable from here until the item computes a new
-- window (ns._PandemicWindowSet). Only when the aura is really gone -- Blizzard
-- clears auraInstanceID before hiding the icon, while a bar merely being hidden
-- leaves it set -- so a visibility toggle mid-pandemic keeps its glow. The bias is
-- deliberate: a suppressed glow costs a tick, a wrong one is what was reported.
function ns._PandemicIconHide(self)
    local fd = hookFrameData[self]
    if fd then
        if fd.pandemicGlowActive then
            if fd.pandemicOverlay then ns.StopNativeGlow(fd.pandemicOverlay) end
            fd.pandemicGlowActive = false
        end
        -- auraInstanceID can be SECRET in instanced combat; comparing a
        -- secret against nil yields a secret boolean the `if` would error
        -- testing. A secret ID means the aura state is unknowable: take the
        -- conservative path (not stale), same bias as the visibility toggle.
        local aid = self.auraInstanceID
        if not (_G.issecretvalue and _G.issecretvalue(aid)) and aid == nil then
            fd._panStale = true
        end
    end
    if ns._pandemicState then ns._pandemicState[self] = nil end
end

-- Blizzard recomputed the pandemic window, so the flag describes the aura that is
-- on the icon NOW. Runs on every application that carries time over, well before
-- the window itself opens.
function ns._PandemicWindowSet(self)
    local fd = hookFrameData[self]
    if fd then fd._panStale = nil end
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
--  IsSpellUsable() can briefly report a resource-gated spell usable right after
--  login/reload, before power data settles. HasEnoughResources re-derives from
--  live UnitPower()/UnitPowerMax(). Callers AND it with IsSpellUsable so only
--  the resource portion gets a second opinion; CD/form/lockout gating is
--  unaffected. Declared early (Lua locals are visible only after declaration).
--  GetSpellPowerCost() allocates per call and cost changes only on talent/spec
--  swap: cache it, invalidate on PLAYER_SPECIALIZATION_CHANGED + PEW, so the
--  hot path (every UNIT_POWER_UPDATE) is a table lookup.
-------------------------------------------------------------------------------
local _spellPowerCostCache = {}

local function InvalidateSpellPowerCostCache()
    wipe(_spellPowerCostCache)
end
ns.InvalidateSpellPowerCostCache = InvalidateSpellPowerCostCache

do
    local _pccInvalidateFrame = ns.TakeShell()
    _pccInvalidateFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _pccInvalidateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _pccInvalidateFrame:SetScript("OnEvent", InvalidateSpellPowerCostCache)
end

local function HasEnoughResources(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return true end
    -- nil = not yet checked, false = no cost (always enough), table = cost list.
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
                -- Power can be SECRET in tainted combat: uncomparable, so default
                -- to castable rather than throw.
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

-- True once real UNIT_POWER_FREQUENT data arrives after PEW: at login
-- IsSpellUsable/GetSpellPowerCost can read stale/empty (0 cost = "enough"),
-- so glow decisions stay untrusted until then; listener re-fires QueueCDGlowUpdate.
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

-- The 4 viewer frames are created once per session and never replaced: cache
-- them instead of repeating _G lookups (10Hz aura ticker + CD Ready Glow update
-- both loop all 4 often).
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
    local displaySID = info and ResolveInfoSpellID(info)
    if not displaySID or displaySID <= 0 then
        -- New-category rows (racials cat 5/6, equip-slot items cat 7/8) are
        -- nil shells in BOTH the raw and merged data spaces (field-probed:
        -- racial rows carry only spellCategoryID, item rows only equipSlot,
        -- and linkedSpellIDs sits empty at rest) -- the resolved identity
        -- exists ONLY on the live frame. GetSpellID() reads SECRET while an
        -- aura is active: a plain read serves this paint and fills the memo
        -- at the head of this function for later secret windows; a secret
        -- read resolves nothing this pass (fail-open, the next inactive
        -- read heals).
        local live = frame.GetSpellID and frame:GetSpellID()
        if issecretvalue and issecretvalue(live) then live = nil end
        if type(live) == "number" and live > 0 then
            displaySID = live
        end
    end
    if not displaySID or displaySID <= 0 then return nil, nil end
    local baseSID = info and info.spellID
    if not baseSID or baseSID <= 0 then baseSID = displaySID end

    if not fc then fc = {}; _ecmeFC[frame] = fc end
    fc.resolvedSid = displaySID
    fc.baseSpellID = baseSID
    fc.overrideSid = info and info.overrideSpellID or nil
    fc.cachedCdID  = cdID
    fc.cachedAuraInstID = frame.auraInstanceID
    -- Native item rows identify by equipment slot (13/14 trinkets etc.);
    -- stashed for the slot-keyed settings/arbitration lane.
    fc.equipSlot = info and info.equipSlot or nil

    if info and info.linkedSpellIDs and #info.linkedSpellIDs > 0 then
        fc.linkedSpellIDs = info.linkedSpellIDs
        -- Learn buff-family variant aliases here, not at DecorateFrame time: only the two
        -- buff viewers host dual-tracked buff forms, and frame.viewerFrame (the raw
        -- Blizzard field) is already readable at this point, before fd._isBuffViewerFrame
        -- exists.
        if ns.LearnBuffVariantAlias
           and (frame.viewerFrame == _G.BuffIconCooldownViewer
                or frame.viewerFrame == _G.BuffBarCooldownViewer) then
            ns.LearnBuffVariantAlias(displaySID, info.linkedSpellIDs)
        end
    else
        fc.linkedSpellIDs = nil
    end

    return displaySID, baseSID
end
ns.ResolveFrameSpellID = ResolveFrameSpellID

-- Resolve the per-spell settings table for a CDM frame. Settings key by the
-- spell the user added (assignedSpells/spellSettings[id]); one logical spell can
-- report SEVERAL ids by talent state: sid2 = cooldownInfo base (can be UNRELATED,
-- e.g. Wither slot: base Immolate 348, displayed Wither 445468); canon =
-- GetCanonicalSpellIDForFrame (clean-read cached, survives secret state);
-- resolvedSid/baseSpellID = cached override/base ids. Match against the FULL
-- identity set: direct hit, linkedSpellIDs, then override resolution in BOTH
-- directions (assigned id may be the base whose live override is an identity id,
-- e.g. Corruption 172 -> Wither 445468, or vice versa).
local function ResolveSpellSettingsUncached(frame, sid2, sd2, barKey)
    if not sid2 then return nil end
    -- Bar identity: explicit barKey wins (nil-frame callers), else frame context.
    local fc0 = frame and _ecmeFC[frame]
    local bk = barKey or (fc0 and fc0.barKey)
    -- Bar tiers: barSettings ("Apply to Bar", per spec) chained to profile-level
    -- bd.barSpellSettings ("Apply to Bar (All Specs)"); nil when neither exists.
    local tier = ns.GetBarTierSettings and ns.GetBarTierSettings(sd2, bk)
    -- HOSTED-BUFF detection: buff frame (or inactive placeholder) on a CD/util
    -- bar, FRAME-based not flag-based (same spellID can also be this bar's CD
    -- entry and must keep CD-family resolution). hostedBuffSpellIDs nil = no host.
    -- All four signals are frame-scoped, and FC.isHostedBuff / viewerFrame are
    -- readable BEFORE the frame is decorated (the claim pass stamps the first;
    -- the second is the Blizzard field DecorateFrame later reads). A
    -- decoration-stamp-only test misses pre-decoration resolves SILENTLY: the
    -- family store below falls back to spellSettingsCD and applies a CD-era
    -- entry under the same id to the buff.
    local hostedFrame = false
    if frame and bk and sd2 and sd2.hostedBuffSpellIDs then
        local fdH = ns._hookFrameData and ns._hookFrameData[frame]
        if (fc0 and fc0.isHostedBuff)
           or (fdH and fdH._isBuffViewerFrame)
           or frame._isPlaceholderFrame
           or frame.viewerFrame == _G.BuffIconCooldownViewer
           or frame.viewerFrame == _G.BuffBarCooldownViewer then
            local bdH = ns.barDataByKey and ns.barDataByKey[bk]
            if bdH and bdH.barType ~= "buffs" and bdH.barType ~= "custom_buff" then
                hostedFrame = true
            end
        end
    end
    -- HOSTED BUFFS never inherit the host bar's Apply-to-Bar tier (shared keys:
    -- Duration Text, Border) -- own per-spell entry ONLY. Nil-frame callers fall
    -- back to the flag test (a nil-frame lookup for a hosted id is always buff).
    if tier and (hostedFrame
       or (not frame and sd2 and sd2.hostedBuffSpellIDs and sd2.hostedBuffSpellIDs[sid2])) then
        tier = nil
    end
    -- Per-spell entries live in the spec's FAMILY store (travel with the spell
    -- across bars), not the bar. A hosted buff reads the BUFF store keyed off the
    -- FRAME, so a cooldown icon of the same spellID here keeps the CD store.
    local settings = bk and ns.GetSpellSettingsStore
        and ns.GetSpellSettingsStore(hostedFrame and "buffs" or bk)
    if not settings or next(settings) == nil then return tier end

    local ChainSettings = ns.ChainSettings

    -- Per-cooldownID buff override: two buff-viewer slots can share one canonical
    -- spellID (e.g. Demonic Art vs Diabolic Ritual) yet configure independently
    -- via a "c"..cooldownID key; gated on BuffFamHasCdKey (cached bool), buff frames only.
    if frame then
        local fdC = ns._hookFrameData and ns._hookFrameData[frame]
        -- Buff frames AND inactive placeholders (Always Show/Keep in Same Place)
        -- share the viewer cooldownID and must resolve the same per-slot entry,
        -- else styling reverts when the placeholder shows; type(cdID)=="number"
        -- excludes preset placeholders (they nil the cooldownID).
        if (fdC and fdC._isBuffViewerFrame) or frame._isPlaceholderFrame then
            local cdID = frame.cooldownID
            if type(cdID) == "number" then
                if ns.BuffFamHasCdKey and ns.BuffFamHasCdKey(settings) then
                    local cd = settings["c" .. cdID]
                    if cd then ChainSettings(cd, tier); return cd end
                end
                -- Split-identity buffs (shared base spellID, per-form aura ids,
                -- e.g. Warp/Weft): the active frame's identity collapses to the
                -- shared base (GetSpellID reads secret), so a direct hit would
                -- differ from the placeholder's per-form id. Prefer the clean
                -- per-form id cached per cooldownID (equals sid2 for normal buffs;
                -- falls through to the shared key when no per-form entry exists).
                local cleanSid = ns._cdmCleanSidByCDID and ns._cdmCleanSidByCDID[cdID]
                if cleanSid and cleanSid ~= sid2 then
                    local sClean = settings[cleanSid]
                    if sClean then ChainSettings(sClean, tier); return sClean end
                end
            end
        end
    end

    -- Fast path: direct hit on the primary id returns before building the identity
    -- set/addId closure, keeping the hot SetSwipeColor path allocation-free. The
    -- chain re-assert self-heals: every resolve re-points __index at the CURRENT
    -- bar's tier, so bar/spec/profile swaps (and fresh logins, since metatables
    -- aren't serialized) never leave a stale link.
    local direct = settings[sid2]
    if direct then ChainSettings(direct, tier); return direct end

    local fc2 = fc0

    -- Frame's deduped identity-id set (sid2 + canonical + cached override/base +
    -- GetBaseSpell bridges) is combat-hot (table alloc + canonical resolve + 2
    -- GetBaseSpell calls per repaint per icon with no own entry) and pure
    -- frame-content data, so it's cached on the frame-cache entry keyed by every
    -- input it derives from (sid2/resolvedSid/baseSpellID); ResolveFrameSpellID's
    -- re-derivation on content/override flips naturally invalidates it -- zero new
    -- edges needed. Step 3's FindSpellOverrideByID stays LIVE by design: live
    -- overrides flip mid-combat with no content change, which only that step catches.
    local ids
    if fc2 and fc2.ssIds and fc2.ssIdsFor == sid2
       and fc2.ssIdsRS == fc2.resolvedSid and fc2.ssIdsBS == fc2.baseSpellID then
        ids = fc2.ssIds
    else
        ids = { sid2 }
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
        -- "Proc into a second ability" talent forms (e.g. DH Reap 1226019/1225826)
        -- share a GetBaseSpell base (344862) with the configured spell, but that's
        -- not the cooldownInfo base and FindSpellOverrideByID is unreliable (live
        -- override may differ from the displayed form); GetBaseSpell of the
        -- frame's ids is the stable bridge, so a setting stored under the base
        -- form resolves on the proc'd frame.
        if C_Spell and C_Spell.GetBaseSpell then
            addId(C_Spell.GetBaseSpell(sid2))
            if canon2 then addId(C_Spell.GetBaseSpell(canon2)) end
        end
        if fc2 then
            fc2.ssIds = ids
            fc2.ssIdsFor = sid2
            fc2.ssIdsRS = fc2.resolvedSid
            fc2.ssIdsBS = fc2.baseSpellID
        end
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
    --    full identity set. Non-positive identity ids (item presets, hosted /
    --    cd-claim markers) are never real spells: skip the spell API, whose
    --    int32 range check HARD-ERRORS on marker magnitudes.
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    if FindOvr and sd2 and sd2.assignedSpells then
        local idOvr = {}
        for i = 1, #ids do
            local id = ids[i]
            if type(id) == "number" and id > 0 then idOvr[i] = FindOvr(id) end
        end
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

-- Result memo over the resolver. Per-frame stamp keyed on ns._cdmResGen (bumped
-- by EVERY input edge: per-spell/tier create-delete, host flips, cdID-key gate
-- flip, clean-sid flips, SPELL_OVERRIDE_UPDATED, SPELLS_CHANGED, rebuilds) plus
-- the frame's content identity (sid2/resolvedSid/baseSpellID) plus the bar.
-- In-place mutation needs no bump (the memo returns the table writers edit).
-- The hit path still re-asserts the tier chain (two bars can share one family
-- entry) at one getmetatable+compare cost; nil-frame callers bypass the memo.
local function ResolveSpellSettings(frame, sid2, sd2, barKey)
    local fc0 = frame and _ecmeFC[frame]
    -- sd2 == false is the LAZY sentinel: the per-repaint hooks pass it instead of
    -- fetching the bar's spell data up front, so the store walk behind
    -- GetBarSpellData runs only on a memo miss (the hit path never needs it).
    if not fc0 or not sid2 then
        if sd2 == false then sd2 = (barKey and ns.GetBarSpellData) and ns.GetBarSpellData(barKey) or nil end
        return ResolveSpellSettingsUncached(frame, sid2, sd2, barKey)
    end
    local bk = barKey or fc0.barKey
    if fc0.ssRGen == ns._cdmResGen and fc0.ssRSid == sid2 and fc0.ssRBk == bk
       and fc0.ssRRS == fc0.resolvedSid and fc0.ssRBS == fc0.baseSpellID then
        local v = fc0.ssRVal
        if v == false then return nil end
        ns.ChainSettings(v, fc0.ssRTier)
        return v
    end
    if sd2 == false then sd2 = ns.GetBarSpellData and ns.GetBarSpellData(bk) end
    local res = ResolveSpellSettingsUncached(frame, sid2, sd2, barKey)
    fc0.ssRGen = ns._cdmResGen
    fc0.ssRSid = sid2
    fc0.ssRBk = bk
    fc0.ssRRS = fc0.resolvedSid
    fc0.ssRBS = fc0.baseSpellID
    if res == nil then
        fc0.ssRVal = false
        fc0.ssRTier = nil
    else
        fc0.ssRVal = res
        local mt = getmetatable(res)
        fc0.ssRTier = mt and mt.__index or nil
    end
    return res
end
ns.ResolveSpellSettings = ResolveSpellSettings

-- Effective swipe direction for a CDM frame: the frame-KIND baseline (buffs fill
-- up, cooldowns deplete) flipped by per-spell / preset "Reverse Swipe". Every
-- writer of the widget goes through this, so they all push the SAME value: the
-- decoration + claim re-asserts used to write the bare kind baseline, which
-- stomped the per-spell reverse on the next reanchor and left it off, because
-- only an icon-set CHANGE runs the appearance pass that re-applies it (preset
-- icons escaped that -- the Fake-Active engine re-asserts their direction on its
-- own updates, so the setting looked broken for regular spells only).
-- Gated on the session flag: returns the baseline with no lookups at all unless
-- someone has the toggle on. On ns, not a file local: this file sits at Lua's
-- 200-local cap.
function ns.EffectiveReverseSwipe(frame, barKey, kindBaseline)
    if not ns._cdmAnyReverseSwipe then return kindBaseline end
    local fc = frame and _ecmeFC[frame]
    local sid = fc and fc.spellID
    -- Bar identity: explicit key wins, else the frame context. Never resolve
    -- without one (the store lookup indexes by it).
    local bk = barKey or (fc and fc.barKey)
    if not (sid and bk and ns.GetBarSpellData) then return kindBaseline end
    -- Pass the key explicitly: the resolver picks the FAMILY store from the bar
    -- identity, and leaving it to be inferred resolves a hosted buff against the
    -- CD store.
    local ss = ResolveSpellSettings(frame, sid, ns.GetBarSpellData(bk), bk)
    local rev = ss and ss.reverseSwipe
    -- Preset / custom cd-utility spell setting (profile customActiveStates;
    -- trinket slots resolve item-over-slot via the effective view).
    if not rev and ns.GetEffectiveCustomActiveState then
        local cas = ns.GetEffectiveCustomActiveState(sid)
        rev = cas and cas.reverseSwipe
    end
    if rev then return not kindBaseline end
    return kindBaseline
end

-- True when any assigned entry on this CD/utility bar resolves to a Shift Icons
-- cooldown-state effect. Frame-less pass over assignedSpells, called at reanchor
-- and from options disabled-state (never per-frame). Advisory only: Pass B also
-- walks the live frame list, since spillover/alias-keyed settings are invisible
-- to a frame-less scan.
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

-- Apply the per-spell active-state OVERLAYS (glow + border). Touches only OUR
-- overlays (glowOverlay, borderFrame), never Blizzard's Cooldown swipe, so it is
-- safe from the swipe hook OR the Fake-Active ticker. Idempotent via
-- fd._activeGlowOn / fd._activeBorderOn so the two drivers cooperate.
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
            -- (Re)start on first activation OR style/colour change (live edits
            -- apply); a steady active window never restarts (would flicker).
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

    -- Active border color (per-spell): recolor while active, restore on falloff.
    -- SQUARE borders use SetBorderStyleColor (solid+textured, no-op on hidden).
    -- CUSTOM SHAPE borders ring a separate shapeBorder texture SetBorderStyleColor
    -- never touches, so recolor it directly and save/restore its vertex color
    -- (fake-active overlays seed FC with the underlying shapeBorder, so the lookup hits the real ring).
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
--  _divertedSpellsBuff/_divertedSpellsCD: variant-keyed maps of every spellID
--    claimed by a bar, split by viewer family so one spellID (Divine Shield 642:
--    cooldown in essential viewer AND buff in buff viewer) routes independently
--    (unsplit, the other family's pass clobbers the entry). Built by
--    RebuildSpellRouteMap, queried per-frame at reanchor by ResolveCDIDToBar.
--  _cdidRouteMap: memo cache cooldownID -> barKey, lazily filled by
--    ResolveCDIDToBar, wiped by RebuildSpellRouteMap. Safe as ONE map since a
--    cooldownID exists in only one viewer (family implicit in the key).
-------------------------------------------------------------------------------
local _cdidRouteMap = {}

local _divertedSpellsBuff = {}
local _divertedSpellsCD   = {}
-- cooldownID-level buff diversions: a collided buff (two viewer slots sharing one
-- canonical spellID) is tracked on a custom bar by cooldownID (cd-claim marker in
-- assignedSpells, ns.CdClaimMarker); checked BEFORE the sid map, so it outranks a pair claim.
local _divertedBuffCdIDs  = {}
--- Equipment-slot diversions, inventory slot -> barKey. Blizzard's own equipment
--- cooldown entry carries an equipSlot and NO spell of its own, so the slot is its
--- only routing key; a bar listing that slot (-13/-14 et al) claims the frame the
--- same way listing a spellID claims a spell. On ns, not a local: this file is at
--- the 200-local cap.
ns._divertedSlotCD = {}
-- EXACT assigned ids, split from the maps above (which also hold variant-family
-- derived keys). One cooldown slot can carry several family members on different
-- bars (Divine Toll/override Holy Bulwark share cooldownID 29342, base 375576);
-- consulted first so the slot follows the assigned bar instead of flipping on each transform.
local _divertedDirectBuff = {}
local _divertedDirectCD   = {}
-- Base ids claimed by an explicitly assigned VARIANT, keyed base -> bar. A transforming
-- slot names only its base plus the live form; the OTHER form is invisible (cooldownID
-- 29342 reports Divine Toll 375576, overrideSpellID alternates armaments, no
-- linkedSpellIDs) -- so with one armament assigned and the base repopulated elsewhere,
-- the exact-id lookup hit-or-missed by armament state and the icon changed bars on
-- every transform. The base IS stable across transforms, so recording it closes the
-- hole; consulted after exact ids and before the base's own entry. Written only when
-- the assigned id isn't the base, so ordinary spells never land here.
local _divertedVarBaseBuff = {}
local _divertedVarBaseCD   = {}
-- Learned variant -> base, deliberately NEVER wiped. It's static game data, but
-- the client only answers while that variant is live (Holy Bulwark live ->
-- GetBaseSpell(432459)=375576; Sacred Weapon live -> 432459: every identity API
-- is a fixed point on the form not currently active). Deriving fresh per rebuild
-- is right only half the time on these constantly-rebuilding transforms, so
-- learn while observable and keep forever (relationship never changes).
--
-- Learning it in-session still leaves one hole, which is what the store below
-- closes: a slot only ever names its base and the form live RIGHT NOW, so a
-- fresh login can never witness the pair for an assigned variant that is not
-- the live one. The claim is therefore missing from the very first build and
-- the base falls through to whatever a repopulate assigned, until a cast
-- transforms the slot and a later rebuild finally observes it. Persisting is
-- what lets a login start where the last session left off.
--
-- SCOPED PER SPEC, and that is load-bearing. GetBaseSpell takes a `spec`
-- argument documented as "overrides may vary by Spec", and we call it without
-- one, so every answer describes the CURRENT spec only. The links are not
-- always the tidy same-ability pair the armaments suggest, either: #842 saw
-- GetBaseSpell tie SV Kill Command to a different ability entirely. Seeding one
-- spec's answer into another would hand varMap a base that belongs to a
-- different family there, and ResolveCDIDToBar consults varBaseMap BEFORE
-- directMap[info.spellID], so a bogus pair would outrank that spell's own
-- explicit assignment. Keying by spec confines every pair to the state it was
-- measured in. Sharing across characters within one spec is fine: same spec,
-- same links.
--
-- Lives on the SV root beside _capturedOnce_CDM rather than in a profile
-- because it describes the game, not the user's settings. StripDefaults only
-- walks keys present in DEFAULTS, so a root key it does not know about survives
-- logout untouched -- which also means nothing else can ever clear it, hence
-- ns.ResetVariantBaseStore below.
local _variantBaseLearned = {}
local _variantBaseSpec = nil   -- spec key the live table was loaded for

local function _variantBaseSV()
    local db = ECME and ECME.db
    return db and db.sv or nil
end

-- Seeds the live table for the current spec, and reloads it when the spec
-- changes, since the previous spec's pairs do not describe the new one. Reads
-- WITHOUT creating; only _learnVariantBase creates, so the table appears the
-- first time a pair is actually observed. Bails without latching while the db
-- or the spec is not up yet, so a later rebuild retries.
local function _loadVariantBases()
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey then return end
    if _variantBaseSpec == specKey then return end
    local sv = _variantBaseSV()
    if not sv then return end
    wipe(_variantBaseLearned)
    _variantBaseSpec = specKey
    local root = sv._variantBase
    if type(root) == "table" then
        -- Pre-release test builds stored pairs flat, keyed by spellID, before
        -- spec scoping existed. Those answers cannot be attributed to a spec so
        -- they cannot be trusted; drop them rather than leave them orphaned.
        -- Clearing existing fields during pairs() is defined behaviour in Lua.
        for k in pairs(root) do
            if type(k) ~= "string" then root[k] = nil end
        end
    end
    local store = (type(root) == "table") and root[specKey] or nil
    if type(store) ~= "table" then return end
    for variant, base in pairs(store) do
        if type(variant) == "number" and type(base) == "number"
           and base > 0 and base ~= variant then
            _variantBaseLearned[variant] = base
        end
    end
end

-- Record a pair in the live table and the current spec's store. Callers gate
-- ids for secrecy before calling: a secret must never index a table, let alone
-- reach SavedVariables. The unchanged-pair early-out keeps the resolve path,
-- which relearns the live pairing on every call, from touching the store per
-- frame. Persists only once the spec is known, so a pair observed before that
-- still routes this session without being filed under the wrong spec.
local function _learnVariantBase(variant, base)
    if _variantBaseLearned[variant] == base then return end
    _variantBaseLearned[variant] = base
    if not _variantBaseSpec then return end
    local sv = _variantBaseSV()
    if not sv then return end
    local root = sv._variantBase
    if type(root) ~= "table" then
        root = {}
        sv._variantBase = root
    end
    local store = root[_variantBaseSpec]
    if type(store) ~= "table" then
        store = {}
        root[_variantBaseSpec] = store
    end
    store[variant] = base
end

-- Reset hook for the CDM's own reset path. Without it a pair learned wrong is
-- permanent: StripDefaults never walks this key and no profile operation
-- touches it, so there would be no way back short of editing SavedVariables.
function ns.ResetVariantBaseStore()
    wipe(_variantBaseLearned)
    _variantBaseSpec = nil
    local sv = _variantBaseSV()
    if sv then sv._variantBase = nil end
end

-- Equivalence check for the picker/list helpers: true when both ids reach the
-- same root through the learned variant -> base ledger. The live spell APIs
-- are blind to a rotating override's inactive form (Sacred Weapon/Holy
-- Bulwark), while the ledger keeps the pair. Called from FindVariantIndex
-- loops, so no per-call closure: the two root walks are inlined. The hop cap
-- guards a cyclic pair.
function ns.IsLearnedVariantOf(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then return false end
    if a <= 0 or b <= 0 then return false end
    _loadVariantBases()
    local hops = 0
    while hops < 8 do
        local nxt = _variantBaseLearned[a]
        if not nxt or nxt == a then break end
        a = nxt; hops = hops + 1
    end
    hops = 0
    while hops < 8 do
        local nxt = _variantBaseLearned[b]
        if not nxt or nxt == b then break end
        b = nxt; hops = hops + 1
    end
    return a == b
end
ns._divertedSpellsBuff = _divertedSpellsBuff
ns._divertedSpellsCD   = _divertedSpellsCD

-- Sentinel: true at the end of a successful RebuildSpellRouteMap. CollectAndReanchor's
-- safety net tests THIS, not _cdidRouteMap (lazy cache, intentionally empty post-build)
-- and not the diversion maps (legitimately empty for users with no diversions).
local _routeMapBuilt = false

--- Rebuild the diversion set. cdID->bar is computed lazily at reanchor by
--- ResolveCDIDToBar, which uses the frame's actual viewerFrame as default (NOT
--- GetCooldownViewerCategorySet, whose STATIC category can differ from where the
--- live viewer shows a spell after Edit Mode drag / per-spec layout). Default
--- bars contribute too: a spellID in cooldowns/utility assignedSpells means
--- "this default bar regardless of category", enabling cross-routing between
--- default bars (e.g. Lay on Hands, Essential viewer -> utility bar). Collision
--- priority (rare under the 1-spell-per-bar invariant): ghost bars (lowest) ->
--- custom buff -> custom CD/util -> default bars (highest), later passes
--- overwrite via preserveExisting=false. Family split: each bar writes
--- _divertedSpellsBuff or _divertedSpellsCD so buff/CD bars claiming the same
--- spellID (e.g. Divine Shield 642) never clobber each other.
function ns.RebuildSpellRouteMap()
    wipe(_cdidRouteMap)
    wipe(_divertedSpellsBuff)
    wipe(_divertedSpellsCD)
    wipe(_divertedDirectBuff)
    wipe(_divertedDirectCD)
    wipe(_divertedVarBaseBuff)
    wipe(_divertedVarBaseCD)
    wipe(_divertedBuffCdIDs)
    wipe(ns._divertedSlotCD)
    _routeMapBuilt = false

    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    -- Before any StoreDirect: the recall below is the only thing that can supply
    -- a base for an assigned variant that is not the live form, and this is the
    -- first build of the session.
    _loadVariantBases()

    local SVV = ns.StoreVariantValue
    if not SVV then return end

    local IsBuffFamily = ns.IsBarBuffFamily

    -- Record an exact assignment plus its base when the assigned id is a variant
    -- form; same overwrite semantics as the direct sets (later pass wins).
    -- Assigned ids come from stored config (plain numbers), so no secret gating here -- the resolve side gates.
    local GetBase = C_Spell and C_Spell.GetBaseSpell
    local function StoreDirect(targetMap, sid, barKey)
        local isBuff = (targetMap == _divertedSpellsBuff)
        SVV(targetMap, sid, barKey, false,
            isBuff and _divertedDirectBuff or _divertedDirectCD)
        -- Learn the base while the client will still say, else recall the last
        -- answer: without the recall the claim is written only on rebuilds that
        -- happen while this exact variant is live, and routing still flips.
        local base
        if GetBase then
            local ok, b = pcall(GetBase, sid)
            if ok and type(b) == "number" and b > 0 and b ~= sid then
                base = b
                _learnVariantBase(sid, b)
            end
        end
        base = base or _variantBaseLearned[sid]
        if base and base ~= sid then
            local varMap = isBuff and _divertedVarBaseBuff or _divertedVarBaseCD
            varMap[base] = barKey
        end
    end

    local function CollectDiversionsFor(bd, skipPositiveSet)
        local sd = ns.GetBarSpellData(bd.key)
        if not sd or not sd.assignedSpells then return end
        local targetMap = IsBuffFamily and IsBuffFamily(bd) and _divertedSpellsBuff or _divertedSpellsCD
        for _, sid in ipairs(sd.assignedSpells) do
            if type(sid) == "number" and sid > 0 then
                if not skipPositiveSet or not skipPositiveSet[sid] then
                    StoreDirect(targetMap, sid, bd.key)
                end
            else
                -- Equipment slot entry: routes Blizzard's own equipment cooldown
                -- for that slot, which has no spellID to key on. Same overwrite
                -- order as the sid maps above, so a custom bar outranks the
                -- default (pass 3) and a ghost bar hides it (pass 4).
                local slot = ns.SlotIDFromKey and ns.SlotIDFromKey(sid)
                if slot then ns._divertedSlotCD[slot] = bd.key end
            end
        end
    end

    -- Pass 1: custom buff bars + custom_buff (TBB) bars. TBB bars compete for
    -- the same buff icon spells, so their diversions land in
    -- _divertedSpellsBuff even though IsBarBuffFamily is false for custom_buff.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and ((bd.barType == "buffs" and bd.key ~= "buffs")
                or bd.barType == "custom_buff") then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        StoreDirect(_divertedSpellsBuff, sid, bd.key)
                    end
                end
            end
            -- cooldownID-level claims (collided buffs tracked by slot marker)
            local claims = sd and ns.CollectCdClaimSet(sd)
            if claims then
                for cdID in pairs(claims) do
                    _divertedBuffCdIDs[cdID] = bd.key
                end
            end
        end
    end
    -- Pass 2: default bars FIRST among the CD family; Pass 3 custom CD/util bars
    -- overwrite them so explicit custom-bar placement OUTRANKS the default
    -- (else a spell also in cooldowns.assignedSpells, materialized spillover
    -- both-state, renders on the default cooldowns bar).
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and (bd.key == "cooldowns" or bd.key == "utility" or bd.key == "buffs") then
            CollectDiversionsFor(bd)
        end
    end
    -- Pass 3: custom CD/utility bars overwrite the default diversions
    -- (deliberate custom-bar placement wins).
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.key ~= "cooldowns" and bd.key ~= "utility" and bd.key ~= "buffs"
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff" then
            CollectDiversionsFor(bd)
        end
    end
    -- Pass 3b: HOSTED BUFFS. A buff on a CD/utility bar (sd.hostedBuffSpellIDs)
    -- must ALSO divert in the BUFF-family map: the frame comes from the BuffIcon
    -- viewer, so ResolveCDIDToBar reads only _divertedSpellsBuff for it. After
    -- passes 1-2 so an explicit host outranks a stray buff-bar copy; the bar's
    -- Pass 3 CD diversion is untouched (separate family maps).
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff" then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.hostedBuffSpellIDs then
                -- Keyed off hostedBuffSpellIDs, not assignedSpells: the CD/util
                -- drop pass can transiently strip a buff from assignedSpells
                -- (buffs never appear in the Essential/Utility viewer) and the
                -- diversion must survive that. SVV expands variants so any live
                -- talent/override form resolves.
                for sid in pairs(sd.hostedBuffSpellIDs) do
                    if type(sid) == "number" and sid > 0 then
                        StoreDirect(_divertedSpellsBuff, sid, bd.key)
                    end
                end
            end
            -- Cd-claimed hosted buffs (collided slots hosted by cd-claim marker instead
            -- of the sid-keyed hostedBuffSpellIDs flag): claim the cooldownID in
            -- _divertedBuffCdIDs, same map/priority as Pass 1. ResolveCDIDToBar checks
            -- it before any sid map, so it works for any target bar type.
            local claims = sd and ns.CollectCdClaimSet(sd)
            if claims then
                for cdID in pairs(claims) do
                    _divertedBuffCdIDs[cdID] = bd.key
                end
            end
        end
    end
    -- Stale ghost ALIASES of a visible family: a rotating override can sit in
    -- the ghost under one form (Holy Bulwark 432459) while its base (375576)
    -- is visibly assigned -- the add path could not remove the ghost entry
    -- because the live APIs are blind to the inactive form. Close the visible
    -- CD keys over the learned variant/base ledger, then drop from that set
    -- every id that is EXACTLY assigned to a visible bar: what remains are
    -- pure aliases, and only those ghost entries are skipped below. Routing
    -- only -- the ghost entry itself is untouched.
    local ghostAliasSkip = {}
    for sid in pairs(_divertedSpellsCD) do ghostAliasSkip[sid] = true end
    local expanded
    repeat
        expanded = false
        for variant, base in pairs(_variantBaseLearned) do
            if ghostAliasSkip[variant] or ghostAliasSkip[base] then
                if not ghostAliasSkip[variant] then
                    ghostAliasSkip[variant] = true
                    expanded = true
                end
                if not ghostAliasSkip[base] then
                    ghostAliasSkip[base] = true
                    expanded = true
                end
            end
        end
    until not expanded
    for sid in pairs(_divertedDirectCD) do ghostAliasSkip[sid] = nil end

    -- Pass 4: ghost bars LAST = HIGHEST priority. A spell the user HID stays
    -- hidden even if the same id also sits on a visible bar ("both-state");
    -- ns.AddSpellToBar removes it from the ghost, so this never hides a
    -- deliberate placement. Only a ghost entry that is a pure ALIAS of a
    -- visible family (set above) is skipped.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and bd.isGhostBar then
            CollectDiversionsFor(bd, ghostAliasSkip)
        end
    end

    _routeMapBuilt = true
end

--- Lazily resolve a cooldownID to a bar key (per-frame at reanchor).
--- _cdidRouteMap memoizes; on miss compute from the per-family diversion map or
--- fall back to viewerDefaultBar ("cooldowns"/"utility"/"buffs" = the viewer pool
--- the frame came from, user-visible ground truth, not the static category API),
--- which also selects the family map (buffs -> _divertedSpellsBuff, else CD).

-- Plain readable positive number, never inspecting a secret (type() and
-- issecretvalue read only the tags). Mirrors _IsUsableSID in the spell picker;
-- tells a real "no diversion" answer from a blind lookup with all-secret ids.
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
    local directMap = (viewerDefaultBar == "buffs") and _divertedDirectBuff or _divertedDirectCD
    local varBaseMap = (viewerDefaultBar == "buffs") and _divertedVarBaseBuff or _divertedVarBaseCD

    local info = gci(cdID)
    if not info then
        -- Info not ready (transient: login / spec swap). Return the fallback
        -- WITHOUT caching: _cdidRouteMap is wiped only by RebuildSpellRouteMap,
        -- so caching would pin a ghosted/custom spell to its default bar.
        return viewerDefaultBar
    end
    -- Free learning: a slot always reports its stable base alongside the live
    -- variant, so every resolve teaches one pairing. Covers a session starting
    -- with the assigned variant NOT live: the first transform makes it known.
    if CdidIDReadable(info.spellID) and CdidIDReadable(info.overrideSpellID)
       and info.overrideSpellID ~= info.spellID then
        _learnVariantBase(info.overrideSpellID, info.spellID)
    end

    -- Equipment-backed entry: the slot is the only identity it has, so it routes
    -- before every sid probe below (all of which would miss). Memoized like any
    -- other resolve; the slot map is rebuilt with the rest. CD/utility viewers
    -- ONLY: a BUFF-viewer equipment row is a tracked trinket PROC BUFF
    -- (category EquipSlotTracked), and the slot map is the CD-side preset
    -- lane -- routing buff rows through it captured proc buffs onto the
    -- trinket preset's bar, overriding their custom buff bar assignment
    -- (field report 2026-08-16: worked with the presets absent, captured with
    -- them present). Buff rows fall through to the sid probes instead: their
    -- raw linked list carries the proc sid even at rest.
    if viewerDefaultBar ~= "buffs" then
        if CdidIDReadable(info.equipSlot) then
            local slotBar = ns._divertedSlotCD[info.equipSlot]
            if slotBar then
                _cdidRouteMap[cdID] = slotBar
                return slotBar
            end
        elseif issecretvalue and issecretvalue(info.equipSlot) then
            -- Equipment row with its slot UNREADABLE (active in restricted
            -- content): the sid probes below see the active window's use-spell
            -- forms and can route -- and PIN via the cdID cache -- the row onto
            -- whatever bar happens to carry that form (the occasional
            -- custom->default "trinket jump", same field report). The slot is
            -- the one stable channel for these rows, so resolve transiently to
            -- the fallback, uncached, and let the next clean pass route by
            -- slot.
            return viewerDefaultBar
        end
    end

    local routedBar = nil
    do
        -- EXACT assignments first, override form before base: one slot can carry
        -- several variant-family members on different bars and only the exact ids
        -- say where each was wanted. The override wins because it's the form
        -- castable right now (e.g. "Holy Bulwark on utility" beats the
        -- repopulated base Divine Toll on cooldowns) -- otherwise the winner
        -- depended on collection order. The base comes LAST: it's typically
        -- present via repopulate while override/linked forms are player-chosen,
        -- so it must never outrank them (either mistake made the icon change bars
        -- on every transform). Every id is gated through CdidIDReadable: on an
        -- active viewer frame these can be SECRET, never index a table with one.
        if CdidIDReadable(info.overrideSpellID) then
            routedBar = directMap[info.overrideSpellID]
        end
        if not routedBar and info.linkedSpellIDs then
            for _, lid in ipairs(info.linkedSpellIDs) do
                if CdidIDReadable(lid) then
                    routedBar = directMap[lid]
                    if routedBar then break end
                end
            end
        end
        -- The variant this slot is NOT transformed into is invisible here (no
        -- linkedSpellIDs): findable only via its base, the one constant id.
        if not routedBar and CdidIDReadable(info.spellID) then
            routedBar = varBaseMap[info.spellID]
        end
        if not routedBar and CdidIDReadable(info.spellID) then
            routedBar = directMap[info.spellID]
        end
        -- No raw `> 0` / `~=` comparisons on info.spellID/overrideSpellID: on an
        -- active viewer frame these can be secret and comparing a secret taints
        -- execution. RVV gates its input through _IsUsableSID internally, so feed
        -- it the raw fields and let it reject anything unusable.
        if not routedBar then
            routedBar = RVV(divertMap, info.spellID)
        end
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
        -- No diversion found. Trust (and cache) that only if at least one id was
        -- readable: with every id secret (active viewer frame in combat) the
        -- lookup was blind and caching would pin the wrong bar until the next
        -- RebuildSpellRouteMap.
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
--  Maintained by the 0.1s buff ticker, NOT here: it walks viewer pools cheaply
--  and writes spellID->true for any frame whose Blizzard-set
--  wasSetFromAura/auraInstanceID indicates an active aura. Bar glows read
--  ns._tickBlizzActiveCache.
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

    -- Do NOT call SetHideCountdownNumbers here; SetCountdownFont controls CD text.
end

-------------------------------------------------------------------------------
--  Charge cooldown style
--  BASELINE: every charge spell draws the cooldown edge (spark) like the action
--  bars -- follows the icon shape's square/circular path at the shape's scale,
--  masked by the CDM shape system. Always on for charge spells, no setting.
--  PER-SPELL: "Hide Swipe (Charges)" also hides the radial swipe (edge only),
--  resolved only when in use (ns._cdmAnyChargeStyle) so others pay ~0.
-------------------------------------------------------------------------------
-- Game-indexed on purpose: the 12.1 edge channel renders game-indexed files
-- ONLY -- loose addon art (png/tga/blp) draws nothing, silently, with clean
-- state readbacks.
local CDM_EDGE_TEXTURE = "Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown"

-- NOTE (probed 2026-08-12): the Cooldown widget clips ALL edge drawing at
-- the frame's own rect -- scales past flush render identically, so the edge
-- can never reach a square's corners without enlarging the cooldown frame
-- itself. Do not re-attempt corner coverage via SetEdgeScale.

-- Thin wrapper: frame spell/bar identity -> ResolveSpellSettings, the same
-- Hero-talent-aware resolver the SetSwipeColor / cdState / desat hooks use, so
-- the charge "Hide Swipe" path resolves override spells identically.
function ns._ResolveCdmSS(frame)
    local fc2 = _ecmeFC[frame]
    local sid2 = fc2 and fc2.spellID
    local bk2 = fc2 and fc2.barKey
    if not sid2 or not bk2 then return nil end
    return ResolveSpellSettings(frame, sid2, false)
end

-- Draw the styled cooldown edge -- one texture for every edge lane: the
-- always-on charge recharge edge and the bar-wide Always Show Cooldown Edge
-- re-assert both land here. The shape system owns the mask + circular-edge
-- flag; this applies texture, color, scale and draw flag.
local function ApplyCdmEdge(cd, bk2)
    if not cd then return end
    local bd = barDataByKey and barDataByKey[bk2]
    local shape = (bd and bd.iconShape) or "none"
    -- SetEdgeScale is frame-relative so the edge tracks icon size: plain icons
    -- use the action bars' baseline size, custom shapes the per-shape scale.
    local scale
    if shape == "none" or shape == "cropped" then
        scale = 1.8
    else
        scale = (ns.CDM_SHAPE_EDGE_SCALES and ns.CDM_SHAPE_EDGE_SCALES[shape]) or 0.75
    end
    -- Color rides SetEdgeTexture: the documented signature is
    -- (texture, r, g, b, a) with the color args required.
    if cd.SetEdgeTexture then
        cd:SetEdgeTexture(CDM_EDGE_TEXTURE, 1, 1, 1, 1)
    end
    if cd.SetEdgeScale then cd:SetEdgeScale(scale) end
    if cd.SetDrawEdge then cd:SetDrawEdge(true) end
end

-- Live active-state read from Blizzard's swipe color (fd._wasActive is stale on
-- falloffs). Secret-safe: a secret red channel reads as not active. Lets charge
-- "Hide Swipe" keep the active-state colored swipe visible.
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

-- Blizzard resolves a cooldown item's spell through GetSpellID(), whose
-- precedence is aura > linkedSpellID > overrideTooltip > override > base
-- (CooldownViewerItemData.lua). When an aura ends without the item receiving the
-- UNIT_AURA removal, cooldownInfo.linkedSpellID keeps pointing at the aura, so
-- CheckCacheCooldownValuesFromSpellCooldown reads the cooldown from a spell that
-- HAS none: start/dur come back 0, IsExpired() answers true, and
-- RefreshSpellCooldownInfo takes its CooldownFrame_Clear branch on every refresh
-- -- no swipe, no countdown text -- while RefreshIconDesaturation leaves the icon
-- saturated. The ability is still on cooldown, so the icon reads as "never
-- pressed" until a target switch (OnNewTarget clears the link), a re-cast of the
-- base spell, or a cooldownID re-set. Blizzard's own repair for this,
-- RefreshLinkedSpell, is only called from OnCooldownIDSet, never from RefreshData.
--
-- How the link outlives the aura: ClearAuraInstanceInfo() drops the instance but
-- NOT the link, and the only path that drops both is OnUnitAuraRemovedEvent,
-- which is dispatched through auraInstanceIDToItemFramesMap and is therefore
-- missable. Any later RefreshData then clears the instance via RefreshAuraInstance
-- and leaves the link standing.
--
-- Detected with nil-compares and never-secret bools ONLY. In instanced combat
-- Cooldown:GetCooldownDuration answers a SECRET value, which is exactly why
-- ReAssertRealCooldown's "widget reads ~0" proof fails closed there -- i.e. in
-- the content where this is reported.
--
-- We repair OUR rendering only; Blizzard's item stays wrong, so its own alerts
-- and isOnActualCooldown keep answering against the linked spell.
--
-- Ordered cheapest-first: linkedSpellID is nil for nearly every icon, so the
-- common case costs two table lookups and no API call. Returns the STRUCTURAL
-- verdict only; callers add their own "is on a real cooldown" test.
local function CdmStaleLinkedSpell(frame)
    local info = frame and frame.cooldownInfo
    if info == nil or info.linkedSpellID == nil then return false end
    -- An aura that is actually being displayed owns the widget; never fight it.
    -- Covers the transient where UpdateLinkedSpell has set the link a moment
    -- before RefreshAuraInstance attaches the matching instance.
    if frame.auraInstanceID ~= nil or frame.wasSetFromAura then return false end
    return true
end

-- Charge info for a CDM frame, resolved the way BLIZZARD resolves it.
--
-- We were resolving the charge spell with C_SpellBook.FindSpellOverrideByID and
-- Blizzard resolves it from the CooldownViewer's OWN override record --
-- CooldownViewerItemDataMixin:GetSpellChargeInfo reads
-- `info.overrideSpellID or info.spellID`, deliberately, "to ensure that charges
-- work correctly for cooldown items that are actively cast, apply auras, and
-- have charges". Those are two different sources and they disagree in the field:
-- captured on a Mage, base Blink 1953 with FindSpellOverrideByID resolving to
-- Shimmer 212653, our read returned isActive=false (no recharge) while Blizzard's
-- own HasVisualDataSource_Charges was true (a recharge running with charges in
-- hand) on the very same frame in the very same call.
--
-- That disagreement is not cosmetic: chargeRecharging false is what lets the
-- Suppress GCD block alpha-0 a swipe, so with Suppress GCD on, an override
-- spell's recharge swipe gets blanked for the whole GCD every time another
-- ability is pressed -- the exact failure the charge carve-out exists to
-- prevent. Asking Blizzard removes the whole class rather than special-casing
-- Shimmer.
--
-- Falls back to the old resolution for frames without the accessor (preset,
-- custom-spell and item frames are ours, not CooldownViewer items), so those
-- keep exactly today's behaviour.
local function CdmChargeInfoFor(frame, sid)
    if frame and type(frame.GetSpellChargeInfo) == "function" then
        local ci = frame:GetSpellChargeInfo()
        if ci then return ci end
    end
    if not (sid and C_Spell and C_Spell.GetSpellCharges) then return nil end
    local effID = sid
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ovr = C_SpellBook.FindSpellOverrideByID(sid)
        if ovr and ovr > 0 and ovr ~= sid then effID = ovr end
    end
    return C_Spell.GetSpellCharges(effID) or C_Spell.GetSpellCharges(sid)
end
ns.CdmChargeInfoFor = CdmChargeInfoFor

-- Apply charge cooldown style. Returns true for charge spells (caller skips its
-- own swipe forcing). Edge always drawn; the swipe hides only with per-spell
-- Hide Swipe (resolved only while ns._cdmAnyChargeStyle). Caller MUST guard with
-- fd._isProcessingOverride so the SetDrawSwipe sibling hook cannot recurse.
-- Secret-safe: HasVisualDataSource_Charges is a clean bool, the ss flag is ours.
local function ApplyCdmChargeStyle(frame, cd)
    -- Icon art suppressed (Only Show Numbers / Charges/Stacks Only): nothing for
    -- a swipe/edge to decorate. Report "handled" so callers skip their own
    -- swipe/edge defaults. The reentry guard is SAVED and restored, never forced
    -- false: ReapplyChargeStyle
    -- sets it before calling us and clearing it would drop its guard.
    local fdOsn = hookFrameData[frame]
    if fdOsn and fdOsn._osnOn then
        local prevGuard = fdOsn._isProcessingOverride
        fdOsn._isProcessingOverride = true
        if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        fdOsn._isProcessingOverride = prevGuard
        return true
    end
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
            -- Hide Recharge Edge (per-spell): drop the edge ApplyCdmEdge just
            -- drew. Secret-safe: ss flag is ours, SetDrawEdge takes no secret.
            if ss2.hideRechargeEdge and cd.SetDrawEdge then
                cd:SetDrawEdge(false)
            end
            if ss2.chargeHideSwipe then
                -- Hide only the recharge swipe: the active-state overlay IS the
                -- colored swipe, so keep it while active.
                local showActive = ss2.activeSwipeMode ~= "none" and CdmFrameIsActive(frame)
                hide = not showActive
            end
        end
    end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(not hide) end
    return true
end

-- Immediately re-assert the charge style (Hide Recharge Edge + Hide Swipe) on one
-- icon instead of waiting for Blizzard's next cooldown re-push. Called from
-- RefreshCDMIconAppearance so toggling either setting (per-icon OR Apply to Bar)
-- updates a CURRENTLY recharging spell now. No-op on non-charge frames
-- (ApplyCdmChargeStyle self-skips); reentry-guarded so siblings cannot recurse.
function ns.ReapplyChargeStyle(frame)
    local fd = frame and hookFrameData[frame]
    local cd = fd and fd.cooldown
    if not cd or fd._isProcessingOverride then return end
    fd._isProcessingOverride = true
    ApplyCdmChargeStyle(frame, cd)
    fd._isProcessingOverride = false
end

-- Max Stacks Glow (per-spell): glow a charge spell at max charges. 1:1 with
-- Active State Glow but on its own overlay (the two never fight), driven by
-- charge state. ss2.maxStacksGlow is the STYLE, color is unified ss.glowColor.
-- atMax is a CLEAN bool from GetSpellCharges().isActive (recharge-active flag,
-- false only at max) -- never the secret currentCharges.
local function ApplyMaxStacksGlow(frame, fd, ss2, atMax)
    if not fd then return end
    local has = ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0
    if has and atMax then
        if not fd._maxStacksGlowOn then
            -- Lazy-create (unused feature adds no frame). Own overlay never
            -- fights the active glow (StartNativeGlow is per-overlay).
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

-- Driven by SPELL_UPDATE_CHARGES, NOT the cooldown-widget hooks: those fire when
-- a charge is SPENT but not when the last charge REFILLS to max. That event
-- fires on BOTH charge transitions and nothing else (far cheaper than
-- SPELL_UPDATE_COOLDOWN, every GCD) and isActive only flips with a charge-count
-- change, so one event catches both edges. The watch set holds only glow-enabled
-- icons; the event frame is created only once the feature is on (0 cost).
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
    -- atMax derives PURELY from charge data (maxCharges + recharge isActive),
    -- NEVER HasVisualDataSource_Charges: that is false while the icon draws a GCD
    -- swipe, dropping the glow whenever a charge tops off mid-GCD. maxCharges>1
    -- is itself the charge-spell test (nil/1 for non-charge -> atMax false).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local atMax = ci ~= nil and (ci.maxCharges or 0) > 1 and not ci.isActive
    ApplyMaxStacksGlow(frame, fd, ssw, atMax)
end

local function WatchMaxStacksFrame(frame, fd)
    ns._maxStacksWatch[frame] = fd
    if not ns._maxStacksEventFrame then
        local ef = ns.TakeShell()
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
-- charge spell (no swipe, so it never fires the swipe hook) still gets watched.
-- Early-outs on non-charge icons (cheap capability check, no settings lookup);
-- once watched SPELL_UPDATE_CHARGES keeps it current. Self-cleans when disabled.
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
--  Plays a sound the moment a spell becomes ready. Edge-detected with an arm
--  flag (armed only while NOT ready, played + disarmed on the ready edge), so it
--  never fires on login (already ready -> never armed), on a GCD end, or per
--  render tick. The expiry edge comes from Blizzard's TriggerAvailableAlert (see
--  HookCdReadyAvailableAlert): the client sends NO event when a cooldown runs
--  out. Cooldown/charge events drive arming/readiness/resets via the
--  WatchCdReadySoundIfEnabled set -- NEVER the SetDesaturated visual hook, which
--  fires at repaint moments unrelated to the real cooldown where GetSpellCooldown
--  can report a transient isActive=true/isOnGCD=false race that false-armed
--  spells never on cooldown during button spam; reading isActive+isOnGCD AT the
--  event (state settled) avoids that. Charge readiness = GetSpellCharges()
--  .isActive == false (at max, same signal Max Stacks Glow uses); non-charge
--  readiness = not (GetSpellCooldown().isActive and not isOnGCD). No
--  duration/magnitude math (secret in protected instances) -- clean bools only.
-------------------------------------------------------------------------------
ns._cdReadySoundWatch = ns._cdReadySoundWatch or setmetatable({}, { __mode = "k" })

-- Loading-screen / login-settle gate shared by every CDM notification sound (CD-ready,
-- buff gain/loss, preset buff gain). Zone changes, flights and login re-render icons
-- and re-fire aura/charge alerts while the cooldown/charge/aura APIs report transient
-- states across the boundary, false-firing edges on spells/buffs that were mid-cooldown
-- or still present. Cheap: one boolean + one timestamp compare, consulted only on a
-- sound edge (never per tick). Edges landing while suppressed are dropped silently.
do
    local loadingActive = true   -- suppressed until the first PLAYER_ENTERING_WORLD
    local settleUntil = 0
    local SETTLE_SECONDS = 2      -- brief window after a load for re-renders to settle

    function ns._cdmSoundSuppressed()
        return loadingActive or GetTime() < settleUntil
    end

    -- Full CDM rebuilds (spec/talent swaps, settings changes) re-render every
    -- icon while the cooldown/charge APIs are transient, so callers open the same
    -- settle window and the re-prime cannot false-arm a batch. Longest wins.
    function ns._cdmBumpSoundSettle(sec)
        local u = GetTime() + (sec or SETTLE_SECONDS)
        if u > settleUntil then settleUntil = u end
    end

    local gate = ns.TakeShell()
    gate:RegisterEvent("LOADING_SCREEN_ENABLED")
    gate:RegisterEvent("LOADING_SCREEN_DISABLED")
    gate:RegisterEvent("PLAYER_ENTERING_WORLD")
    gate:SetScript("OnEvent", function(_, event)
        if event == "LOADING_SCREEN_ENABLED" then
            loadingActive = true
        else
            -- World up: clear the flag, settle so the re-render cannot false-fire.
            loadingActive = false
            settleUntil = GetTime() + SETTLE_SECONDS
        end
    end)
end


-- Reject armed->ready spans shorter than this: a real cooldown arms the moment
-- the spell is used, so a sub-GCD arm can only be a transient misread (GCD tail
-- / charge race). Costs the sound on real cooldowns under ~1.6s (rare in CDM).
local CD_READY_MIN_ARM = 1.6

-- Both drivers (Blizzard's available alert and the event fallback) can land on
-- the same cooldown end a frame apart -- one shared throttle keeps that single.
local CD_READY_SOUND_GAP = 0.5

-- Is the spell READY now? Charge spells: only at MAX charges (recharge not
-- running). Non-charge: not on a real (non-GCD) cooldown. liveSid = resolved
-- override. strict: the GCD does NOT count as ready. ARMING wants the loose read
-- (a GCD must never arm a spell that was never on cooldown); FIRING must be
-- strict, because a CAST-TIME spell raises its cooldown only on cast SUCCESS and
-- until then GetSpellCooldown reports the GCD alone (isActive + isOnGCD) --
-- "ready" under the loose test, firing the armed sound at the moment of cast.
local function CdReadyIsReady(liveSid, strict)
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if ci ~= nil and (ci.maxCharges or 0) > 1 then
        return not ci.isActive
    end
    local cd = C_Spell.GetSpellCooldown(liveSid)
    if not cd then return true end
    if strict then
        -- Not ready while a REAL (non-GCD) cooldown runs. A filler GCD alone
        -- must NOT block the edge: the old "any active cooldown" strict test
        -- deferred the ready sound through continuous GCD spam until the
        -- player stopped casting entirely.
        if cd.isActive and not cd.isOnGCD then return false end
        -- The one GCD-only state that is NOT ready: this spell's own hard cast
        -- in flight (a cast-time spell raises its cooldown only on cast
        -- SUCCESS). Exact identity check; a secret cast id fails toward
        -- suppress -- the armed state survives and the next event retries.
        if UnitCastingInfo then
            local castSid = select(9, UnitCastingInfo("player"))
            if castSid and ((issecretvalue and issecretvalue(castSid)) or castSid == liveSid) then
                return false
            end
        end
        return true
    end
    return not (cd.isActive and not cd.isOnGCD)
end

-- Charge spells keep their own ready edge (refill to MAX, off
-- SPELL_UPDATE_CHARGES). Blizzard's available alert fires when the FIRST
-- charge returns -- a different edge -- so the alert driver skips them.
local function CdReadyIsChargeSpell(liveSid)
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    return ci ~= nil and (ci.maxCharges or 0) > 1
end

-- Single play point for both drivers: throttled, always disarms.
local function PlayCdReadySound(fd, key, liveSid, sid, bk, src)
    fd._cdReadyArmed = false
    local now = GetTime()
    local last = fd._cdReadySoundAt
    if last and (now - last) < CD_READY_SOUND_GAP then return end
    fd._cdReadySoundAt = now
    local path = ns.FOCUSKICK_SOUND_PATHS and ns.FOCUSKICK_SOUND_PATHS[key]
    if path then PlaySoundFile(path, "Master") end
end

-- Shared evaluator (SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES via the
-- WatchCdReadySoundIfEnabled set). Arms while not ready, plays + disarms on the
-- ready edge, deferred one frame and re-confirmed so a charge/GCD-tail race
-- cannot false-fire. Zero-cost on the feature flag. primeOnly: arm state only.
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
        -- Settle window: cooldown reads are transient, so gate the ARM (not just
        -- the fire) and clear stale arms. A spell genuinely on cooldown re-arms
        -- on the next SPELL_UPDATE_COOLDOWN after the window: no edge lost.
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
    elseif fd._cdReadyArmed and not primeOnly and CdReadyIsReady(liveSid, true) then
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
                if not CdReadyIsReady(livep, true) then return end  -- not ready (race/GCD) -> stay armed
                if ns._cdmSoundSuppressed() then fd._cdReadyArmed = false; return end  -- a load began mid-defer
                -- Sub-GCD arm span = transient misread, not a real cooldown ending.
                local armedAt = fd._cdReadyArmedAt
                if not armedAt or (GetTime() - armedAt) < CD_READY_MIN_ARM then
                    fd._cdReadyArmed = false
                    return
                end
                PlayCdReadySound(fd, kp, livep, sidp, bkp, "event")
            end)
        end
        fd._cdReadyPending:Show()
    end
end

-- PRIMARY driver for non-charge spells: Blizzard's "cooldown just became
-- available" edge. The client dispatches NO event on cooldown expiry;
-- TriggerAvailableAlert simulates the final SPELL_UPDATE_COOLDOWN from the
-- viewer's OnUpdate against the real endTime (riding SPELL_UPDATE_COOLDOWN alone
-- never sees the expiry). Post-hooking the alert is the same taint-safe idiom as
-- EnsureBuffSoundHook on TriggerAuraAppliedAlert: no secret duration read, lands
-- on the exact frame. Charge spells stay with the SPELL_UPDATE_CHARGES watcher:
-- this alert fires on the FIRST charge, but CDM readiness means back at MAX.
local _cdReadyAlertHooked = setmetatable({}, { __mode = "k" })
local function HookCdReadyAvailableAlert(frame, fd)
    if _cdReadyAlertHooked[frame] then return end
    if type(frame.TriggerAvailableAlert) ~= "function" then
        _cdReadyAlertHooked[frame] = true   -- own placeholder / injected frame: no alert
        return
    end
    _cdReadyAlertHooked[frame] = true
    hooksecurefunc(frame, "TriggerAvailableAlert", function(f)
        if not ns._cdmAnyCdReadySound then return end
        if fd._isProcessingOverride then return end
        local fca = _ecmeFC[f]
        local sida = fca and fca.spellID
        local bka = fca and fca.barKey
        if not sida or not bka then return end
        if bka == ns.FOCUSKICK_BAR_KEY then return end
        if bka:sub(1, 7) == "__ghost" then return end
        local ssa = ResolveSpellSettings(f, sida, ns.GetBarSpellData(bka))
        local keya = ssa and ssa.cdReadySoundKey
        if not keya or keya == "none" then return end
        if ns._cdmSoundSuppressed() then fd._cdReadyArmed = false; return end
        local livea = sida
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            livea = C_SpellBook.FindSpellOverrideByID(sida) or sida
        end
        if CdReadyIsChargeSpell(livea) then return end
        PlayCdReadySound(fd, keya, livea, sida, bka, "alert")
    end)
end

-- Register a spell with a CD-ready sound into the event-driven watch set,
-- evaluated on SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES (refill to max),
-- reading isActive/isOnGCD once state settles: covers arming, charge readiness
-- and cooldown RESETS. The expiry edge belongs to the available-alert hook above
-- (this pass backs it up between GCDs); there is NO SetDesaturated driver.
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
            local ef = ns.TakeShell()
            ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ef:RegisterEvent("SPELL_UPDATE_CHARGES")
            ef:SetScript("OnEvent", function()
                for f, d in pairs(ns._cdReadySoundWatch) do
                    EvalCdReadySound(f, d)
                end
            end)
            ns._cdReadySoundEventFrame = ef
        end
        HookCdReadyAvailableAlert(frame, fd)
        EvalCdReadySound(frame, fd, true)  -- prime the arm state only; never plays here
    elseif ns._cdReadySoundWatch[frame] then
        ns._cdReadySoundWatch[frame] = nil
    end
end

-------------------------------------------------------------------------------
--  Hide CD Text (Charges) -- per-spell (CD/utility bars only)
--  While a CHARGE spell has a usable charge in hand, hide the recharge countdown
--  numbers; they return once every charge is spent (0 charges == on a real
--  cooldown), so the full countdown shows when unavailable. "charges > 0"
--  derives from CLEAN GetSpellCooldown() flags: charge in hand <=> not
--  (isActive and not isOnGCD) -- isActive alone is wrong (true during the GCD
--  right after a cast even with a charge left). Charge-spell test:
--  GetSpellCharges().maxCharges > 1 (stable through the GCD), never
--  HasVisualDataSource_Charges (flips false during a GCD swipe); neither reads
--  the secret currentCharges. Driven by SPELL_UPDATE_CHARGES (same as Max Stacks
--  Glow), catching the topping-off edge the cooldown-widget hooks miss. Gated on
--  ns._cdmAnyChargeHideCdText (~0 cost when unused).
-------------------------------------------------------------------------------

-- Effective SetHideCountdownNumbers value: layers the per-spell "Hide CD Text
-- (Charges)" toggle on the caller's baseHide (numbers already hidden by the bar
-- / per-icon showCooldownText). Returns baseHide unchanged for anything that is
-- not an enabled charge spell, so callers can wrap unconditionally.
function ns.CdmShouldHideCountdown(frame, baseHide)
    -- Charges/Stacks Only (No Icon) hides the duration outright (the counter is the
    -- whole display). Checked AHEAD of the feature gate so it holds for every caller --
    -- the appearance pass, reanchor loop and SPELL_UPDATE_CHARGES watcher all route
    -- countdown writes through here, so no per-site force is needed. (Only Show Numbers
    -- never sets the flag: there the number IS the display.)
    local fdc = hookFrameData[frame]
    if fdc and fdc._osnHideText then return true end
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
    -- "charges > 0" <=> NOT on a real (non-GCD) cooldown; the isOnGCD term is
    -- required (isActive alone is true through every post-cast GCD). Both flags
    -- clean; the secret currentCharges is never read.
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
    local baseHide = not ns.CdmDurationTextOn(bd)
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    if not (ssw and ssw.chargeHideCdText) then
        -- Setting off: restore the bar's showCooldownText result and unwatch
        -- (per-icon showCooldownText exists only on buff bars, which never
        -- enable this charge toggle, so the bar value is right).
        ns._chargeCdTextWatch[frame] = nil
        -- Through the resolver, not raw: returns baseHide unchanged but still
        -- honours Charges/Stacks Only, so no duration flash on a no-icon bar.
        cd:SetHideCountdownNumbers(ns.CdmShouldHideCountdown(frame, baseHide))
        return
    end
    cd:SetHideCountdownNumbers(ns.CdmShouldHideCountdown(frame, baseHide))
end

local function WatchChargeCdTextFrame(frame, fd)
    ns._chargeCdTextWatch[frame] = fd
    if not ns._chargeCdTextEventFrame then
        local ef = ns.TakeShell()
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
-- spell at max (no recharge text, never fires the swipe hook) still gets watched
-- for the moment it dips below max. Early-outs on non-charge icons; once watched
-- SPELL_UPDATE_CHARGES keeps it current. Self-cleans when the setting is off.
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
--  "Hide Text at 0 Stacks" (bar-level, cd/utility bars): hide the charge counter
--  (frame.ChargeCount.Current) while a charge spell is genuinely OUT of charges
--  instead of showing a 0. The count IS the alpha: SetAlpha clamps to [0,1]
--  engine-side, so alpha := currentCharges hides at exactly 0 and shows at 1+
--  with no comparison, and SetAlpha accepts secret numbers (SecretArguments
--  AllowedWhenTainted), so the same write runs in and out of instanced combat
--  (secret count written through, memo dirtied, never stored/compared). The
--  clean-flag inference "real non-GCD cooldown = zero charges" is NOT universal
--  -- Roll-class wiring and talent-granted charges on cooldown spells like Feint
--  / Survival of the Fittest keep the main cooldown record active while charges
--  are banked -- so it's unused here; CdmShouldHideCountdown still uses it,
--  harmlessly showing the duration where it could hide it. Driven by the same
--  SPELL_UPDATE_CHARGES edge as the other charge features (lazy shell, self-
--  draining watch set, zero cost for non-users). Alpha not Hide: the engine
--  rewrites the counter's TEXT on charge changes but never its alpha.
-------------------------------------------------------------------------------
ns._zeroChargeTextWatch = ns._zeroChargeTextWatch or setmetatable({}, { __mode = "k" })

-- Paint-the-delta memo: SetAlpha only on a real change. The engine rewrites the
-- counter's TEXT but never its alpha, so the stamp stays truthful.
local function ZctSetAlpha(fd, fs, a)
    if fd._zctAlpha ~= a then
        fd._zctAlpha = a
        fs:SetAlpha(a)
    end
end

local function EvalZeroChargeTextFrame(frame, fd)
    local fs = frame.ChargeCount and frame.ChargeCount.Current
    local fcz = _ecmeFC[frame]
    local sidz = fcz and fcz.spellID
    local bkz = fcz and fcz.barKey
    if not fs or not sidz or not bkz then
        ns._zeroChargeTextWatch[frame] = nil
        if fs then ZctSetAlpha(fd, fs, 1) end
        return
    end
    -- Per-spell "Hide Charge Text" (cd-state menu): a STATIC hide riding this
    -- feature's alpha channel and memo, so the two can never fight over the
    -- counter. It outranks the zero-charge logic; charge events land here and
    -- simply keep the 0.
    local sss = ns._ResolveCdmSS and ns._ResolveCdmSS(frame)
    if sss and sss.hideChargeText then
        ZctSetAlpha(fd, fs, 0)
        return
    end
    local bd = barDataByKey and barDataByKey[bkz]
    if not (bd and bd.hideZeroChargeText) then
        ns._zeroChargeTextWatch[frame] = nil
        ZctSetAlpha(fd, fs, 1)
        return
    end
    local liveSid = sidz
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidz) or sidz
    end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if not (ci and (ci.maxCharges or 0) > 1) then
        -- Not a charge spell (talent changed since enrollment): restore and
        -- unwatch; the appearance pass re-enrolls if charge-ness returns, which
        -- keeps the per-event set charge-spells-only.
        ns._zeroChargeTextWatch[frame] = nil
        ZctSetAlpha(fd, fs, 1)
        return
    end
    -- Alpha := currentCharges (see header). Secret count: same write, memo dirtied.
    local cc = ci.currentCharges
    -- issecretvalue FIRST, and type() rather than == nil for the missing case.
    -- currentCharges is secret whenever cooldowns are restricted (combat,
    -- encounter, challenge mode, PvP match), and comparing a secret to nil is
    -- the exact operation this addon's own secret rules forbid. Ordering the
    -- nil "belt" ahead of the guard made the belt the hazard: a throw here
    -- aborts the eval with the alpha still 0, so the counter stays HIDDEN until
    -- the next SPELL_UPDATE_CHARGES -- which for a charge spell that just
    -- refilled is a whole recharge away. That is the reported "0 -> 1 hides the
    -- stack count temporarily". The throw also kills the pairs() loop in the
    -- event handler, so every other watched icon stops updating with it.
    if issecretvalue and issecretvalue(cc) then
        fd._zctAlpha = nil
        fs:SetAlpha(cc)
    elseif type(cc) ~= "number" then
        ZctSetAlpha(fd, fs, 1)
    else
        ZctSetAlpha(fd, fs, cc > 1 and 1 or cc)
    end
end

function ns.WatchZeroChargeTextIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcz = _ecmeFC[frame]
    local sidz = fcz and fcz.spellID
    local bkz = fcz and fcz.barKey
    -- Per-spell "Hide Charge Text": static, so this appearance-pass call is
    -- its whole driver -- no event watch needed. A frame the bar feature has
    -- watched keeps its enrollment; the eval's own short-circuit holds the 0.
    if sidz and bkz then
        local sss = ns._ResolveCdmSS and ns._ResolveCdmSS(frame)
        if sss and sss.hideChargeText then
            local fsh = frame.ChargeCount and frame.ChargeCount.Current
            if fsh then ZctSetAlpha(fd, fsh, 0) end
            return
        end
    end
    local bd = bkz and barDataByKey and barDataByKey[bkz]
    if bd and bd.hideZeroChargeText and sidz then
        -- Enroll CHARGE SPELLS ONLY: non-charge icons would be pure identity
        -- work per event. Talent swaps re-run this via the appearance pass; the
        -- eval self-unwatches the other direction.
        local liveSid = sidz
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            liveSid = C_SpellBook.FindSpellOverrideByID(sidz) or sidz
        end
        local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
        if not (ci and (ci.maxCharges or 0) > 1) then
            if ns._zeroChargeTextWatch[frame] then EvalZeroChargeTextFrame(frame, fd) end
            return
        end
        if not ns._zeroChargeTextEventFrame then
            local ef = ns.TakeShell()
            ef:RegisterEvent("SPELL_UPDATE_CHARGES")
            ef:SetScript("OnEvent", function()
                for f, d in pairs(ns._zeroChargeTextWatch) do
                    EvalZeroChargeTextFrame(f, d)
                end
            end)
            ns._zeroChargeTextEventFrame = ef
        end
        ns._zeroChargeTextWatch[frame] = fd
        EvalZeroChargeTextFrame(frame, fd)
    elseif ns._zeroChargeTextWatch[frame] then
        -- Setting off: the eval's off-branch unwatches + restores alpha.
        EvalZeroChargeTextFrame(frame, fd)
    else
        -- Hide Charge Text just turned off with no watch left to restore for
        -- it: put the counter back. Memoized, so a neither-feature icon pays
        -- one SetAlpha(1) ever.
        local fsr = frame.ChargeCount and frame.ChargeCount.Current
        if fsr then ZctSetAlpha(fd, fsr, 1) end
    end
end

-------------------------------------------------------------------------------
--  Cooldown State Effect -- charge-aware readiness for Hidden (CD Ready)
--  For a CHARGE spell "CD Ready" must mean AT MAX CHARGES, not "a charge in
--  hand": GetSpellCooldown().isActive is false with a charge left, so a plain
--  read calls a recharging spell "ready" and the icon vanishes mid-recharge --
--  exactly the countdown this mode exists to watch. Read the recharge flag
--  instead (GetSpellCharges().isActive: true from the first spent charge until
--  the last refills, the clean Max Stacks Glow signal); maxCharges > 1 is the
--  charge-spell test (stable through the GCD, unlike HasVisualDataSource_Charges);
--  non-charge spells keep the caller's cooldown read. Secret currentCharges
--  never read. Per-spell "+ Stay Hidden While Charges Remain"
--  (ss.chargeHideUntilSpent) opts back into "hidden only once fully spent".
--  Deliberately NOT used by other cd-state effects: those answer "can I press
--  this?" (Hidden/Lower Alpha On CD suppress the uncastable, ready-glows
--  highlight the castable) and a charge spell down one stack IS castable --
--  Hidden (CD Ready) is the only mode tracking the countdown.
-------------------------------------------------------------------------------
function ns.CdmCdStateReady(liveSid, onCD, hideUntilSpent)
    if hideUntilSpent then return not onCD end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if ci and (ci.maxCharges or 0) > 1 then return not ci.isActive end
    return not onCD
end

-- Deferred cd-state evaluator for the hide / lower-alpha modes, shared by the
-- SetDesaturated hook (every cooldown transition) and the charge watch below.
-- Deferred one frame because SetDesaturated fires inside Blizzard's secure CDM
-- chain where GetSpellCooldown can briefly disagree with Blizzard's own
-- evaluation (charge spells report isActive with charges left, GCD tail races).
-- The OnUpdate script is installed ONCE per frame object: the hook fires per
-- repaint, so per-arm work stays plain field writes, never closure creation.
local function ArmCdStateEval(frame, fd, cse, cseShift, lowAlpha, hideUntilSpent)
    local pending = fd._cdStatePending
    if not pending then
        pending = CreateFrame("Frame")
        pending:Hide()
        fd._cdStatePending = pending
        pending:SetScript("OnUpdate", function(self)
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
                -- Lowered (not hidden): reuse _cdStateHidden as the "cd-state
                -- owns this alpha" flag so the opacity appliers leave the lowered
                -- value alone. A visibility-hidden bar (baseA 0) stays 0 either way.
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
                    -- Hidden (CD Ready): on a charge spell "ready" is max
                    -- charges, so the icon keeps tracking the recharge.
                    hide = ns.CdmCdStateReady(liveSid, onCD, self.hideUntilSpent)
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
    end
    -- All captured at arm time (settings, not volatile state); only
    -- lowerAlphaOnCD reads lowAlpha, only the CD-Ready modes read hideUntilSpent.
    pending.cse = cse
    pending.lowAlpha = lowAlpha
    pending.shift = cseShift
    pending.hideUntilSpent = hideUntilSpent
    pending:Show()
end

-------------------------------------------------------------------------------
--  Hidden (CD Ready) on charge spells: refill-edge coverage
--  The mode's SetDesaturated driver fires when a charge is SPENT but NOT when
--  the last charge REFILLS to max -- the gap SPELL_UPDATE_CHARGES closes (both
--  charge transitions, nothing else, far cheaper than SPELL_UPDATE_COOLDOWN).
--  Without it a topped-off charge spell stays visible forever: at max charges
--  nothing repaints the icon. Only icons running the mode on a charge spell
--  enter the set, and it self-drains (eval unwatches dead effects/spells).
-------------------------------------------------------------------------------
ns._cdStateChargeWatch = ns._cdStateChargeWatch or setmetatable({}, { __mode = "k" })

local function EvalCdStateChargeFrame(frame, fd)
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not sidw or not bkw then
        ns._cdStateChargeWatch[frame] = nil
        return
    end
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    local csew = ssw and ssw.cdStateEffect
    if csew ~= "hiddenReady" and csew ~= "hiddenReadyShift" then
        -- Effect changed or cleared: the desat hook owns every other mode.
        ns._cdStateChargeWatch[frame] = nil
        return
    end
    ArmCdStateEval(frame, fd, "hiddenReady", csew == "hiddenReadyShift",
        nil, ssw.chargeHideUntilSpent)
end

-- Register an icon whose resolved effect is Hidden (CD Ready) (callers check)
-- when its spell has charges; non-charge spells never enter the set, their real
-- CD-end edge fires the desat hook. Called from that hook (on spell rebinding)
-- and RefreshCDMIconAppearance.
function ns.WatchCdStateChargeIfEnabled(frame)
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    if not sidw then return end
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    -- Charge-spell test via static charge data (stable through the GCD).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if not (ci and (ci.maxCharges or 0) > 1) then
        ns._cdStateChargeWatch[frame] = nil
        return
    end
    ns._cdStateChargeWatch[frame] = fd
    if not ns._cdStateChargeEventFrame then
        local ef = ns.TakeShell()
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for f, d in pairs(ns._cdStateChargeWatch) do
                EvalCdStateChargeFrame(f, d)
            end
        end)
        ns._cdStateChargeEventFrame = ef
    end
end

-------------------------------------------------------------------------------
--  Swiftmend brightness: Blizzard dims the icon via SetVertexColor when
--  Efflorescence / HoTs drop. Hook the icon texture once to force bright.
--  Recursion guard only -- never compare incoming args (secret values).
--  Retried on EVERY DecorateFrame call: spell-ID resolution can miss on a
--  frame's first pass (cooldownID not yet assigned) and a decorated-flag early
--  return would make that permanent. Free: non-Druids skip on the cached class
--  check, hooked frames on one flag read.
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


-------------------------------------------------------------------------------
--  Per-spell Custom Icon
--  Stamp the configured replacement icon (texture fileID) over the icon texture,
--  from DecorateFrame on every (re)claim and from a per-frame
--  RefreshSpellTexture post-hook (installed on first gated visit), so it
--  survives every Blizzard repaint AND spell transforms: RefreshSpellTexture is
--  the ONLY writer of a viewer item's icon texture (every item type's
--  RefreshData + SPELL_UPDATE_ICON), and the settings resolver matches the
--  stored key against the frame's full identity set. Purely per-spell, never
--  written to bar tiers. Gated on ns._cdmAnyCustomIcon (one boolean, no hooks
--  installed for non-users). Clear/restore: when the setting is removed the last
--  stamped frame (fd._customIconOn) restores its real icon once via
--  C_Spell.GetSpellTexture (base id; API resolves live overrides, next
--  RefreshData corrects aura/link nuance). NEVER call the frame's own
--  RefreshSpellTexture for this -- running Blizzard mixin code from insecure
--  context can write tainted values into the frame's table.
-------------------------------------------------------------------------------
local function ApplyCustomIcon(frame, fd)
    if not ns._cdmAnyCustomIcon then return end
    fd = fd or hookFrameData[frame]
    local tex = fd and fd.tex
    if not tex then return end
    -- Per-frame re-assert hook. Must hook the frame INSTANCE: leaf-mixin functions are
    -- COPIED onto each item frame at creation, so a hooksecurefunc on the mixin table
    -- never fires for frames that predate the install (the custom icon then reverts on
    -- every cast, RefreshData repainting the real icon). Same per-frame pattern as the
    -- SetDesaturated hooks. Injected/own frames have no RefreshSpellTexture and skip it
    -- (nothing Blizzard-side repaints them; the claim-path stamps suffice).
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
        -- Restore ONLY with a resolvable identity: a nil sid means the identity
        -- cache is transiently empty (bar-rebuild mid-login), not that the user
        -- cleared the setting, so keep the flag armed for the next pass.
        local fc = _ecmeFC[frame]
        local sid = fc and (fc.resolvedSid or fc.spellID)
        if type(sid) == "number" and not (issecretvalue and issecretvalue(sid))
           and sid > 0 and C_Spell and C_Spell.GetSpellTexture then
            fd._customIconOn = nil
            local real = C_Spell.GetSpellTexture(sid)
            if real then tex:SetTexture(real) end
        end
    end
end
ns.ApplyCustomIcon = ApplyCustomIcon

-------------------------------------------------------------------------------
--  Icon-art suppression (two bar settings, one machine)
--    buff-family bars: "Only Show Numbers"            -> barData.onlyShowNumbers
--    cd/utility bars:  "Charges/Stacks Only (No Icon)" -> barData.chargesOnly
--  Both hide icon texture, background, square border, shape ring, Blizzard
--  debuff border, swipe and recharge edge; they differ only in the countdown:
--  Only Show Numbers leaves it to the normal Duration Text settings (bar toggle
--  + per-icon overrides; off = stacks-only), Charges/Stacks Only forces it OFF.
--  Swipe, edge and countdown have writers that re-assert between our passes, so
--  each is gated at its own choke point: the SetDrawSwipe hook and
--  ApplyCdmChargeStyle (owner of ApplyCdmEdge) read _osnOn; the resolver every
--  countdown writer funnels through, ns.CdmShouldHideCountdown, reads
--  _osnHideText. Every hide is REGION-level, never frame alpha: frame.ChargeCount
--  / frame.Applications are siblings of the icon (on container-Icon frames the
--  stack text is at Icon.Applications), so frame:SetAlpha(0)/Icon:SetAlpha(0)
--  would take the counters with it; fd.tex is already resolved to the leaf
--  texture by DecorateFrame's GetTexture descent. Applied from DecorateFrame on
--  every (re)claim and re-asserted at the end of RefreshCDMIconAppearance's
--  per-icon pass (which re-applies borders/shapes and would otherwise undo the
--  hides). Hides are alpha/shown/flag based with regions staying live, so
--  turning the setting off restores one-shot via fd._osnOn (pooled frames
--  moving to a bar without the setting restore the same way); normal style
--  passes re-assert the rest. Cost when off: one field read per call.
-------------------------------------------------------------------------------
local function ApplyOnlyNumbers(frame, fd, barData)
    if not barData then return end
    fd = fd or hookFrameData[frame]
    local osn = barData.onlyShowNumbers
    if osn or barData.chargesOnly then
        -- Set BEFORE the swipe/edge writes: the per-frame SetDrawSwipe/
        -- SetDrawEdge hooks force defaults for non-charge frames and read _osnOn
        -- to stand down (buff frames early-out on _isBuffViewerFrame and never
        -- reach that hook, which is why cd/utility needed the gate).
        -- _osnHideText tells ns.CdmShouldHideCountdown the duration is
        -- suppressed; every countdown writer resolves through it.
        if fd then
            fd._osnOn = true
            fd._osnHideText = (not osn) or nil
        end
        local tex = (fd and fd.tex) or frame._tex
        if tex then
            tex:SetAlpha(0)
            -- Hide() too, load-bearing on cd/utility: Texture SetAlpha and
            -- SetVertexColor share ONE alpha slot on this client, and the
            -- resource-dim pass writes a 3-arg SetVertexColor on injected
            -- custom-spell icons, resetting alpha to 1 and popping the art back.
            -- Shown-state is an independent channel no colour writer can touch,
            -- and nothing in the addon Shows an icon texture.
            tex:Hide()
        end
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
            -- No icon means no recharge edge either.
            if cd.SetDrawEdge then cd:SetDrawEdge(false) end
            -- Charges/Stacks Only forces the countdown OFF. The buff variant does
            -- NOT touch it: the duration follows the normal Duration Text
            -- settings, applied by the appearance pass before this re-hide tail.
            if (not osn) and cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        end
    elseif fd and fd._osnOn then
        fd._osnOn = nil
        fd._osnHideText = nil
        local tex = fd.tex or frame._tex
        if tex then tex:SetAlpha(1); tex:Show() end
        local bg = fd.bg or frame._bg
        if bg then bg:SetAlpha(1) end
        local ifc = _ecmeFC[frame]
        if ifc and ifc.shapeBorder then ifc.shapeBorder:SetAlpha(1) end
        if frame.DebuffBorder then frame.DebuffBorder:SetAlpha(1) end
        local cd = fd.cooldown or frame.Cooldown or frame._cooldown
        if cd then
            if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not ns.CdmDurationTextOn(barData)) end
        end
        -- Square border / shape ring re-apply on the next style pass
        -- (DecorateFrame / RefreshCDMIconAppearance via BuildAllCDMBars).
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

    -- Border + background track the CURRENT bar's settings on EVERY call, not just the
    -- first: Blizzard recycles one icon-frame pool across bars/spells, so a frame
    -- decorated under another bar's style must pick this bar's up on every (re)claim.
    -- For hooked default bars (Essential/Utility) this is the ONLY re-style path
    -- (RefreshCDMIconAppearance is skipped for them); structural creation stays
    -- one-time via the fd.borderFrame/fd.bg guards, only styling is unconditional.
    -- Frame levels are relative to the icon's LIVE level (never cached at first
    -- decoration) so a reclaimed pooled frame stays correctly layered.
    local baseLvl = frame:GetFrameLevel()

    if not fd.bg then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        fd.bg = bg
    end
    fd.bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08,
        barData.bgB or 0.08, barData.bgA or 0.6)

    -- Show Cooldown Edge: stamped per (re)claim so the cooldown hooks read one
    -- flag instead of chasing frame -> bar -> settings on every push. Toggling
    -- rebuilds bars, so the stamp always tracks the live setting; on the
    -- on -> off transition drop a mid-sweep edge now instead of waiting for
    -- Blizzard's next cooldown push.
    local edgeOn = barData.showCooldownEdge or nil
    if fd._edgeFeatureOn and not edgeOn and fd.cooldown and fd.cooldown.SetDrawEdge then
        fd._isProcessingOverride = true
        fd.cooldown:SetDrawEdge(false)
        fd._isProcessingOverride = false
        fd._edgeApplied = nil
    end
    fd._edgeFeatureOn = edgeOn

    -- Custom-shape bars own their border: ApplyShapeToCDMIcon draws the ring on
    -- shapeBorder and hides the square border. Re-applying the square style here
    -- would force it back on unchanged reanchors (no shape re-apply follows those),
    -- so keep it hidden -- newly (re)claimed frames land in an iconsChanged refresh
    -- that re-applies the shape. Active-state tint on shaped icons rides
    -- shapeBorder, never the square border, so both re-asserts below are square-only.
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
        -- ApplyBorderStyle always paints the bar's BASE color, so re-assert the
        -- active-state tint if engaged (fd._activeBorderOn, set by
        -- ApplyActiveOverlays off Blizzard's SetSwipeColor) or a reanchor mid-proc flashes it back to base.
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
        -- Late retry: the style block already ran; skip one-time decoration.
        TryHookSwiftmend(frame, fd)
        ApplyCustomIcon(frame, fd)
        ApplyOnlyNumbers(frame, fd, barData)
        return fd
    end
    fd.decorated = true

    -- A HOSTED buff frame is a Blizzard buff-viewer frame on a CD/util bar: its
    -- swipe is the AURA DURATION, so the cd-style swipe hooks below (Suppress-GCD,
    -- active-state override, charge logic) must NEVER touch it or they blank the
    -- duration swipe every GCD. viewerFrame is stable per pooled frame: flag once.
    fd._isBuffViewerFrame = (frame.viewerFrame == _G.BuffIconCooldownViewer
        or frame.viewerFrame == _G.BuffBarCooldownViewer) or nil

    local iconWidget = frame.Icon
    if iconWidget and not iconWidget.GetTexture then
        if iconWidget.Icon then iconWidget = iconWidget.Icon end
    end
    fd.tex = iconWidget
    fd.cooldown = frame.Cooldown

    -- Swiftmend brightness (druid only; retried from the decorated early-return).
    TryHookSwiftmend(frame, fd)

    -- First decoration: fd.tex is now available, so Custom Icon can stamp.
    ApplyCustomIcon(frame, fd)
    ApplyOnlyNumbers(frame, fd, barData)

    HideBlizzardDecorations(frame)

    -- Per-icon Audio on Buff Gain/Loss: hook one-time here, before the frame is ever
    -- active, so the first activation is not missed. Buff-family only;
    -- EnsureBuffSoundHook self-guards on TriggerAuraAppliedAlert presence, so
    -- injected-custom/non-aura frames are no-ops.
    if (barData and (barData.barType == "buffs" or barData.key == "buffs"))
       and ns._cdmAnyBuffSound and ns.EnsureBuffSoundHook then
        ns.EnsureBuffSoundHook(frame)
    end

    -- Hook SetPoint: when Blizzard repositions this frame (Layout,
    -- RefreshLayout, internal updates), force it back to the stored CDM anchor.
    if not fd._setPointHooked then
        fd._setPointHooked = true
        hooksecurefunc(frame, "SetPoint", function(_, point, relativeTo)
            local anchor = fd._cdmAnchor
            if not anchor then
                -- Not yet claimed by our bar system: re-blank so it does not flash at
                -- the viewer's position before CollectAndReanchor claims it.
                if fd.decorated then
                    frame:SetAlpha(0)
                    -- Re-park CD/utility frames offscreen (buff pools stay hands-off):
                    -- alpha alone cannot keep an unclaimed frame invisible -- the
                    -- engine re-raises item alpha through paths no SetAlpha hook can
                    -- see (SetAlphaFromBoolean, alpha animations) on cooldown/aura
                    -- changes (druid form swaps). Position enforcement is immune to
                    -- every alpha path, and a later re-claim SetPoints absolutely. The
                    -- TOPLEFT keyword MUST match LayoutCDMBar's claim SetPoint (which
                    -- does not ClearAllPoints): same-keyword SetPoint REPLACES the park
                    -- point, a different one accumulates a conflicting anchor.
                    if not fd._isBuffViewerFrame and not fd._parkGuard then
                        fd._parkGuard = true
                        frame:ClearAllPoints()
                        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
                        fd._parkGuard = nil
                    end
                end
                return
            end
            -- relativeTo == our bar container: our own LayoutCDMBar SetPoint.
            if relativeTo == anchor[2] then return end
            -- Blizzard is trying to move us. Force back to CDM position.
            frame:ClearAllPoints()
            frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
        end)
    end


    -- Per-icon active state hooks installed lazily during CollectAndReanchor,
    -- ONLY for spells with custom active state settings.

    -- Overlay creation is one-time; frame levels re-applied at the top.
    if not fd.glowOverlay then
        local go = CreateFrame("Frame", nil, frame)
        go:SetAllPoints(frame)
        go:SetAlpha(0)
        go:EnableMouse(false)
        fd.glowOverlay = go
        go:SetFrameLevel(baseLvl + 16)
    end

    -- Re-arm the buff ticker's active-glow "nothing configured" latch: this
    -- function re-runs on rebuilds/settings changes (exactly when the cached
    -- answer can change), so a newly enabled glow is picked up next pass.
    fd._activeGlowNoCfg = nil

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

    -- Pandemic hooks deliberately NOT installed here: they install lazily from
    -- the buff tick, per icon, only when the bar uses a custom pandemic style
    -- (zero cost unless enabled; closures are CDM-billed via file-scope bodies).

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
        -- Swipe starts disabled; CollectAndReanchor enables it once claimed and
        -- positioned, so no black-swipe flash at the viewer's default position.
        fd.cooldown:SetDrawSwipe(false)
        fd.cooldown:SetDrawBling(false)
        fd._isProcessingOverride = true
        fd.cooldown:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
        fd._isProcessingOverride = false
        -- High-res flat white, never WHITE8x8: the wedge cut's anti-aliasing comes
        -- from texel filtering, so an 8px texture rasterizes the boundary jagged at
        -- any angle. Own asset over the game's viewer swipe for sharp corners (the
        -- stock file bakes in corner rounding that mismatches our squared icons).
        fd.cooldown:SetSwipeTexture("Interface\\AddOns\\EllesmereUI\\media\\white-square.png")
        -- Hook SetSwipeColor on EVERY CD/utility frame: forces our swipe color
        -- (black, or per-spell custom) so Blizzard's active-state color flash
        -- never shows. SetDrawSwipe hooked too, to keep charge swipes visible.
        if not fd._swipeColorHooked then
            fd._swipeColorHooked = true
            local cd = fd.cooldown
            hooksecurefunc(cd, "SetSwipeColor", function()
                if fd._isProcessingOverride then return end
                -- Buff-viewer frame (buff bar or hosted) or our own preset/custom
                -- buff frame (cast-timer driven): the swipe is the aura DURATION,
                -- so skip all cd-style logic (Suppress-GCD, active-state) and
                -- apply only per-spell "Cooldown Swipe Color" (Default = bar's
                -- swipe colour/black, Class/Custom per settings).
                if fd._isBuffViewerFrame or frame._isCustomBuffFrame then
                    fd._isProcessingOverride = true
                    local fcB = _ecmeFC[frame]
                    local sidB = fcB and fcB.spellID
                    local bkB = fcB and fcB.barKey
                    local ssB = (sidB and bkB and ns.ResolveSpellSettings)
                        and ns.ResolveSpellSettings(frame, sidB, false, bkB) or nil
                    local sr, sg, sb
                    -- CURRENT bar's swipe alpha, not the decorate-time closure
                    -- barData: pooled frames decorate once, so it holds whichever
                    -- bar first decorated this frame.
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
                local bd2 = bk2 and barDataByKey and barDataByKey[bk2]
                -- Resolved BEFORE the Suppress GCD block: the per-spell
                -- suppressGCD flag joins the bar toggle there (pure hoist --
                -- this resolve always ran once per hook pass, just later).
                local ss2
                if sid2 and bk2 then
                    ss2 = ResolveSpellSettings(frame, sid2, false)
                end
                local _gcdSuppressed = false
                -- Recharge duration of a charge spell whose recharge is running
                -- out underneath a GCD; see ns.GCDTailAlpha at the swipe writes.
                local _gcdChargeTail
                -- Per-bar "Suppress GCD": alpha-0 the swipe while the displayed
                -- cooldown is just a GCD (isOnGCD is a clean bool). Do NOT return
                -- early -- active-state detection below must still run so overlays
                -- and duration timers work during a GCD. Two cases must NEVER be
                -- suppressed: (1) the Hide-Active override window forcing the real
                -- recharge display (a GCD from another ability is moot); (2) a
                -- charge spell with a recharge in flight (ANY count below max,
                -- incl. 0) -- that swipe IS the recharge, and alpha-0'ing it blanks
                -- the recharge for a whole GCD whenever another ability is pressed.
                -- The Hide-Active exclusion applies to whole-swipe suppression
                -- ONLY, not the charge tail: _hideActiveOverriding follows the
                -- active read, which flaps for charge spells.
                -- Per-spell "Suppress GCD" ORs into the bar toggle: with the
                -- bar toggle ON the per-spell flag is a natural no-op.
                if ((bd2 and bd2.suppressGCD) or (ss2 and ss2.suppressGCD)) and sid2
                   and C_Spell and C_Spell.GetSpellCooldown then
                    -- Charge-recharge guard: mid-recharge (INCLUDING 0 charges)
                    -- shows the recharge, never a GCD, so never alpha-0 it.
                    -- Derived from STABLE charge data (maxCharges > 1 AND
                    -- GetSpellCharges().isActive), NOT
                    -- HasVisualDataSource_Charges, which flips FALSE while a GCD
                    -- swipe is layered on top -- the exact moment this hook runs
                    -- -- letting a 0-charge recharge get suppressed. Both fields
                    -- clean; secret currentCharges never read. Override ID
                    -- resolved for transform spells.
                    local effID2 = sid2
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                        if ovr and ovr > 0 and ovr ~= sid2 then effID2 = ovr end
                    end
                    -- Resolved through Blizzard's own accessor: see CdmChargeInfoFor.
                    -- This value decides whether the swipe may be alpha-0'd, and a
                    -- wrong "not recharging" here blanks a live recharge for a whole
                    -- GCD on every override spell.
                    local chargeRecharging = false
                    do
                        local ci = CdmChargeInfoFor(frame, sid2)
                        chargeRecharging = (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) or false
                    end
                    -- The GCD read must use the override too: a transform's real
                    -- CD ticks on the override ID, and the base-ID query reads
                    -- isOnGCD=true through that whole CD, suppressing the swipe
                    -- for its full duration.
                    local cdInfo = C_Spell.GetSpellCooldown(effID2) or C_Spell.GetSpellCooldown(sid2)
                    if cdInfo and cdInfo.isOnGCD then
                        if not chargeRecharging then
                            if not fd._hideActiveOverriding then
                                cd:SetSwipeColor(0, 0, 0, 0)
                                _gcdSuppressed = true
                            end
                        elseif C_Spell.GetSpellChargeDuration then
                            -- Recharge in flight, but its LAST GCD-length slice
                            -- is drawn by the GCD. Hand the recharge duration to
                            -- the swipe writes below, which alpha-0 that slice
                            -- only; earlier keeps the recharge swipe (case 2).
                            _gcdChargeTail = C_Spell.GetSpellChargeDuration(effID2)
                                or C_Spell.GetSpellChargeDuration(sid2)
                        end
                    end
                end
                -- Publish the tail decision for ReArmChargeRecharge. That runs from
                -- the SetCooldown hooks, which fire for EVERY icon on every push,
                -- so it must decide whether it cares without paying for a spell
                -- lookup. This flag is exactly the state it needs -- a charge
                -- recharge running underneath a GCD -- and it is already computed
                -- here from clean bools. Blizzard's refresh calls SetSwipeColor
                -- before CooldownFrame_Set, so it is fresh when the re-arm reads it.
                fd._gcdChargeTailArmed = _gcdChargeTail ~= nil
                -- Active state detected from the swipe color.
                local swipeColor = frame.cooldownSwipeColor
                local isActive = false
                if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                    local r = swipeColor:GetRGBA()
                    if r and type(r) == "number" and not issecretvalue(r) then
                        isActive = (r ~= 0)
                    end
                end

                -- Flip the per-session gates the moment any spell uses these
                -- settings, so the SetDesaturated/SetDrawSwipe hooks early-out on
                -- one check for everyone else. Runs for every icon on login.
                if ss2 and ss2.desatNotActive then ns._cdmAnyDesatNotActive = true end
                if ss2 and ss2.noDesatOnCD then ns._cdmAnyNoDesatOnCD = true end
                if ss2 and (ss2.chargeHideSwipe or ss2.hideRechargeEdge) then ns._cdmAnyChargeStyle = true end
                if ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0 then ns._cdmAnyMaxStacksGlow = true end
                if ss2 and ss2.activeGlow and ss2.activeGlow > 0 then ns._cdmAnyActiveGlow = true end
                if ss2 and ss2.chargeHideCdText then ns._cdmAnyChargeHideCdText = true end
                if ss2 and ss2.hideChargeText then ns._cdmAnyHideChargeText = true end
                if ss2 and ss2.suppressGCD then ns._cdmAnySuppressGcd = true end
                if ss2 and ss2.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                if ss2 and ss2.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
                if ss2 and (tonumber(ss2.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end

                if ss2 and ss2.activeSwipeMode == "none" then
                    -- Hide Active State: force black swipe, track active flag (CD
                    -- model override belongs to the SetDesaturation hook, which fires
                    -- on every Blizzard cooldown tick). Suppress GCD for a hero-talent
                    -- transform to a usable follow-up: while a castable proc shows
                    -- (override present, not on its own real CD) this icon has no real
                    -- CD, so the black swipe has no geometry -- until another ability
                    -- pushes a GCD via SetCooldown, whose geometry the PERSISTENT
                    -- black colour sweeps as a visible bar (SetCooldown changes
                    -- geometry, not colour, so nothing re-hides it). Paint fully
                    -- transparent for exactly that case, and also for a plain
                    -- hide-active spell whose swipe color never zeroes out
                    -- (e.g. Prismatic Barrier), which pins fd._hideActiveOverriding
                    -- and otherwise leaks a bare GCD once charges max out. Gated
                    -- on Suppress GCD; a spell genuinely on its own real CD keeps
                    -- the black swipe, and a charge proc mid-recharge is carved
                    -- out (its swipe IS the recharge).
                    local hideActiveAlpha = barData.swipeAlpha or 0.7
                    if ((bd2 and bd2.suppressGCD) or (ss2 and ss2.suppressGCD)) and sid2
                       and C_SpellBook and C_SpellBook.FindSpellOverrideByID
                       and C_Spell and C_Spell.GetSpellCooldown then
                        local chargeRecharging = false
                        do
                            local ci = CdmChargeInfoFor(frame, sid2)
                            chargeRecharging = (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) or false
                        end
                        if not chargeRecharging then
                            local ovrID = C_SpellBook.FindSpellOverrideByID(sid2)
                            local checkID = (ovrID and ovrID > 0 and ovrID ~= sid2) and ovrID or sid2
                            local oc = C_Spell.GetSpellCooldown(checkID)
                            if oc and not (oc.isActive and not oc.isOnGCD) then
                                hideActiveAlpha = 0
                            end
                        end
                    end
                    if not _gcdSuppressed then
                        cd:SetSwipeColor(0, 0, 0, ns.GCDTailAlpha(_gcdChargeTail, hideActiveAlpha))
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
                    -- Active: swipe color (custom, class, or default #FFC660).
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
                        cd:SetSwipeColor(0, 0, 0, ns.GCDTailAlpha(_gcdChargeTail, barData.swipeAlpha or 0.7))
                    end
                    -- Desaturate When Not Active (per-spell). Symmetric, but
                    -- re-saturates only icons WE desaturated (fd._desatNA), so
                    -- turning it off never fights cdState/buff desaturation and
                    -- un-greys without waiting for the next cooldown event.
                    if fd.tex then
                        if ss2 and ss2.desatNotActive then
                            fd.tex:SetDesaturated(true)
                            fd._desatNA = true
                        elseif fd._desatNA then
                            fd.tex:SetDesaturated(false)
                            fd._desatNA = nil
                        end
                    end
                    -- Buff ended, CD starting: re-apply the cooldown duration so
                    -- the swipe shows immediately. Once per transition, only when
                    -- the spell actually has an active cooldown.
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

                -- Charge "Hide Swipe" suppresses only the recharge swipe: the
                -- active-state colored swipe IS the active overlay, so keep it
                -- while active. Inside the override guard, so no re-entry.
                if ns._cdmAnyChargeStyle and ss2 and ss2.chargeHideSwipe and cd.SetDrawSwipe
                   and type(frame.HasVisualDataSource_Charges) == "function"
                   and frame:HasVisualDataSource_Charges() then
                    cd:SetDrawSwipe(ss2.activeSwipeMode ~= "none" and isActive)
                end

                -- Active glow + border (per-spell). Extracted so the Fake-Active
                -- engine can drive the same overlays from its own ticker, sharing
                -- fd._activeGlowOn / fd._activeBorderOn. Touches only our
                -- overlays, never the Blizzard swipe: safe from any context.
                ns.ApplyActiveOverlays(frame, fd, ss2, isActive, bd2)

                -- Max Stacks Glow: "at max" = no recharge running
                -- (GetSpellCharges().isActive; secret currentCharges never read).
                -- Consuming a charge fires this swipe hook, refilling to max
                -- fires Cooldown:Clear. Register for charge events (the only
                -- catch for refill-to-max) and eval now so a SPEND is immediate.
                if ns._cdmAnyMaxStacksGlow and ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0 then
                    WatchMaxStacksFrame(frame, fd)
                    EvalMaxStacksFrame(frame, fd)
                elseif fd._maxStacksGlowOn then
                    ApplyMaxStacksGlow(frame, fd, nil, false)  -- setting cleared -> off
                    ns._maxStacksWatch[frame] = nil
                end

                fd._gcdSwipeSuppressed = _gcdSuppressed
                fd._isProcessingOverride = false
            end)
            hooksecurefunc(cd, "SetDrawSwipe", function(_, show)
                if fd._isProcessingOverride then return end
                -- Hosted buff: never toggle its duration swipe from our cd logic.
                if fd._isBuffViewerFrame then return end
                -- Charges/Stacks Only (No Icon): art is hidden, so a swipe would
                -- draw a dark pie over empty space on every re-push. Suppress
                -- instead of the force-true below, ahead of the charge-style call
                -- (with no icon there is nothing for an edge to decorate).
                if fd._osnOn then
                    if show then
                        fd._isProcessingOverride = true
                        cd:SetDrawSwipe(false)
                        fd._isProcessingOverride = false
                    end
                    return
                end
                -- Charge spells get the baseline edge (+ per-spell Hide Swipe):
                -- ApplyCdmChargeStyle returns true and owns swipe + edge for
                -- them; non-charge frames fall to the force-true below.
                fd._isProcessingOverride = true
                local handled = ApplyCdmChargeStyle(frame, cd)
                -- Bar-wide Show Cooldown Edge (non-charge frames; charge frames
                -- get their edge from ApplyCdmChargeStyle). GCD suppression
                -- drops an edge we applied, tracked so the disabled/default
                -- path never issues a redundant SetDrawEdge.
                if not handled and fd._edgeFeatureOn and cd.SetDrawEdge then
                    if not fd._gcdSwipeSuppressed then
                        local fcEdge = _ecmeFC[frame]
                        ApplyCdmEdge(cd, fcEdge and fcEdge.barKey)
                        fd._edgeApplied = true
                    elseif fd._edgeApplied then
                        cd:SetDrawEdge(false)
                        fd._edgeApplied = nil
                    end
                end
                fd._isProcessingOverride = false
                if handled then return end
                -- Per-spell Hide CD Swipe (non-charge): keep the swipe suppressed
                -- across Blizzard re-pushes. Gated (costs nothing until enabled),
                -- resolved from our own flags (secret-safe) in BOTH stores:
                -- per-bar spellSettings and preset customActiveStates.
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
            -- Cooldown edge enforcement. Re-assert the bar-wide Blizzard edge, or
            -- per-spell Hide Recharge Edge, across Blizzard cooldown re-pushes.
            if cd.SetDrawEdge then
                hooksecurefunc(cd, "SetDrawEdge", function(_, show)
                    if fd._isProcessingOverride then return end
                    -- Edge-off pushes only matter to the bar-wide edge re-assert
                    -- (every other branch below acts on show=true alone), so the
                    -- disabled/default path keeps its zero-cost early-out.
                    if not show and not fd._edgeFeatureOn then return end
                    if fd._isBuffViewerFrame then return end
                    -- No icon art: no recharge edge, charge or not. Blizzard
                    -- re-enables it on every re-push, so this must be in the hook.
                    if fd._osnOn then
                        if show then
                            fd._isProcessingOverride = true
                            cd:SetDrawEdge(false)
                            fd._isProcessingOverride = false
                        end
                        return
                    end
                    local hasChargeSource = type(frame.HasVisualDataSource_Charges) == "function"
                        and frame:HasVisualDataSource_Charges()
                    if hasChargeSource and ns._cdmAnyChargeStyle then
                        local ss2 = ns._ResolveCdmSS(frame)
                        if ss2 and ss2.hideRechargeEdge then
                            if show then
                                fd._isProcessingOverride = true
                                cd:SetDrawEdge(false)
                                fd._isProcessingOverride = false
                            end
                            return
                        end
                    end
                    -- Bar-wide Show Cooldown Edge: re-assert across Blizzard's
                    -- own edge-off pushes (stock disables it on every non-charge
                    -- cooldown update).
                    if fd._edgeFeatureOn and not fd._gcdSwipeSuppressed then
                        local fcEdge = _ecmeFC[frame]
                        fd._isProcessingOverride = true
                        ApplyCdmEdge(cd, fcEdge and fcEdge.barKey)
                        fd._isProcessingOverride = false
                        fd._edgeApplied = true
                    end
                end)
            end
            -- Non-charge cooldown re-assert. Blizzard's CooldownViewer zeroes the
            -- widget for some spells partway through their REAL cooldown and never
            -- re-pushes -- e.g. DH placement sigils (Flame/Misery/Silence, not Spite)
            -- clear when the sigil activates (~1s in) while GetSpellCooldown still
            -- reports the full 30s, leaving no swipe for the rest of the CD. Charge
            -- spells use the charge re-arm below. Gated tightly to that exact failure
            -- (widget cleared to ~0 while a genuine non-GCD cooldown is live), so it never fights a GCD swipe or aura-display time (both non-zero).
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
                -- Act only when the widget is cleared to ~0 (never fight a real
                -- cooldown, GCD, or aura-display time). The secret check MUST
                -- precede any truthiness/comparison (a secret errors on either);
                -- a secret duration cannot prove "cleared", so fail closed (the
                -- sigil failure moment reads a clean 0, so the fix still runs).
                --
                -- SECOND PROOF, needed because the fail-closed above is permanent in
                -- instanced combat (the duration reads secret there, so this function
                -- could never act -- see CdmStaleLinkedSpell). A stale linked spell
                -- means Blizzard clears this widget on EVERY refresh, so there is
                -- nothing to fight and no duration read is required to know it.
                --
                -- These free reads run BEFORE the spell queries below: every Clear on
                -- every non-charge icon lands here, and the cooldown query allocates a
                -- table per call, so the common exits (secret duration in instanced
                -- combat, a widget still carrying a real swipe) must cost no query.
                local staleLink = CdmStaleLinkedSpell(frame)
                if not staleLink and cd.GetCooldownDuration then
                    local ok, curDur = pcall(cd.GetCooldownDuration, cd)
                    if not ok then return end
                    if issecretvalue and issecretvalue(curDur) then return end
                    if curDur and curDur > 100 then return end
                end
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- Only re-assert for a genuine, non-GCD cooldown still running.
                -- isActive / isOnGCD are clean bools (read bare elsewhere).
                local cdInfo = C_Spell.GetSpellCooldown(effID) or C_Spell.GetSpellCooldown(sid2)
                if not (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) then return end
                local durObj = C_Spell.GetSpellCooldownDuration(effID)
                    or C_Spell.GetSpellCooldownDuration(sid2)
                if not durObj then return end
                fd._isProcessingOverride = true
                if cd.SetUseAuraDisplayTime then cd:SetUseAuraDisplayTime(false) end
                cd:SetCooldownFromDurationObject(durObj)
                if staleLink then
                    -- Blizzard's expired branch never calls SetSwipeColor, so the
                    -- widget still carries whatever colour was painted last. For an
                    -- aura-tracking icon that is the ACTIVE colour from the aura
                    -- window, and it then renders over the cooldown we just armed --
                    -- field-seen as "the swipe was still yellow". Repaint the resting
                    -- cooldown colour, the same black the SetSwipeColor hook's
                    -- not-active branch uses (the per-spell Cooldown Swipe Color only
                    -- applies to buff-viewer frames, which never reach here).
                    -- This also releases a Suppress-GCD alpha-0 that can be stuck for
                    -- the same reason -- what we just armed is a real cooldown, never
                    -- a GCD. Mirrors ReArmChargeRecharge, which repaints for exactly
                    -- this reason on the charge path.
                    -- Gated to the stale case on purpose: the placement-sigil case
                    -- reaches here with a colour Blizzard has kept current, so it is
                    -- left alone. Bar data is resolved LIVE rather than from the
                    -- decorate-time closure, since pooled frames decorate once.
                    local bkS = fc2.barKey
                    local bdS = bkS and barDataByKey and barDataByKey[bkS]
                    cd:SetSwipeColor(0, 0, 0, (bdS and bdS.swipeAlpha) or 0.7)
                end
                -- Only geometry was wiped (Blizzard's clear leaves draw-swipe on),
                -- so re-arming the duration restores the swipe. Deliberately NOT
                -- forcing SetDrawSwipe(true): under the override guard that would
                -- bypass per-spell "Hide CD Swipe".
                fd._isProcessingOverride = false
            end

            -- Charge-spell recharge swipe restore. The swipe renders from the
            -- widget's armed duration, NOT the SetDrawSwipe flag (which only
            -- gates an existing swipe). When one charge refills while another
            -- still recharges Blizzard calls Cooldown:Clear(), wiping the armed
            -- duration, so SetDrawSwipe(true) has no geometry and the valid
            -- recharge swipe vanishes: re-arm from the charge recharge duration.
            -- Charge spells only; non-charge frames route to the re-assert above.
            hooksecurefunc(cd, "Clear", function()
                if fd._isProcessingOverride then return end
                -- HasVisualDataSource_Charges is a clean bool present only on
                -- Blizzard CooldownViewer item frames, so this also excludes our
                -- custom (trinket/racial/item) and aura buff frames.
                local hasCharges = type(frame.HasVisualDataSource_Charges) == "function"
                    and frame:HasVisualDataSource_Charges()
                if not hasCharges then ReAssertRealCooldown(); return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 or not C_Spell or not C_Spell.GetSpellCooldown
                    or not C_Spell.GetSpellChargeDuration then
                    return
                end
                -- Resolve the override ID for transformed spells BEFORE querying
                -- cooldown state, so replacements report against the live spell.
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- isActive / isOnGCD are clean bools. Only re-arm while genuinely
                -- recharging AND not merely on GCD: a GCD-tail race can report
                -- isActive with a degenerate charge duration, and arming a 0,0
                -- cooldown strobes the swipe. All charges back (isActive false):
                -- leave cleared so the swipe correctly disappears.
                -- Max Stacks Glow: Clear fires on every charge refill (incl. to
                -- max), so re-eval from GetSpellCharges().isActive (clean, false
                -- only at max) and the glow lights as the last charge returns.
                if ns._cdmAnyMaxStacksGlow then
                    local bkm = fc2 and fc2.barKey
                    local ssm = bkm and ResolveSpellSettings(frame, sid2, false) or nil
                    if ssm and ssm.maxStacksGlow and ssm.maxStacksGlow > 0 then
                        WatchMaxStacksFrame(frame, fd)
                        EvalMaxStacksFrame(frame, fd)
                    end
                end
                local cdInfo = C_Spell.GetSpellCooldown(effID)
                local cdActive = cdInfo and cdInfo.isActive and not cdInfo.isOnGCD
                -- Charge-in-hand Hide-Active window: GetSpellCooldown().isActive
                -- is false while a castable charge remains, so the cd gate above
                -- never re-arms and Blizzard's per-aura-refresh wipe leaves the
                -- swipe blank. Re-arm off the clean recharge flag instead, ONLY
                -- inside our Hide-Active override so non-override charge spells
                -- keep Blizzard's native display. currentCharges never read.
                local chargeActive = fd._hideActiveOverriding
                    and (CdmChargeInfoFor(frame, sid2) or {}).isActive == true
                if not (cdActive or chargeActive) then return end
                -- Re-derive the recharge duration. The duration object is opaque,
                -- fed straight to the widget and never inspected: secret-safe.
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
            -- During the Hide-Active window Blizzard re-pushes the widget for a
            -- charge-in-hand spell via SetCooldownFromDurationObject (aura
            -- display) and SetUseAuraDisplayTime -- NOT plain SetCooldown -- and
            -- those pushes wipe the recharge we armed (Clear/SetDesaturated fire
            -- far too rarely to keep up). Re-assert on those two real drivers,
            -- gated to EXACTLY (charge frame + Hide-Active window + recharge
            -- running) = no-op otherwise; _isProcessingOverride blocks recursion.
            local function ReArmChargeRecharge()
                if fd._isProcessingOverride then return end
                -- Two field reads and nothing else. This runs from the SetCooldown
                -- / SetCooldownFromDurationObject / SetUseAuraDisplayTime hooks, so
                -- it fires for EVERY icon on EVERY cooldown push -- every GCD the
                -- player triggers. Neither entry can be live without one of these
                -- set, so bail before touching the frame or any API.
                if not (fd._hideActiveOverriding or fd._gcdChargeTailArmed) then
                    return
                end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 or not C_Spell or not C_Spell.GetSpellCharges
                    or not C_Spell.GetSpellChargeDuration then
                    return
                end
                -- Hosted buff / custom buff frames are excluded here for the same
                -- reason the SetSwipeColor and Clear hooks exclude them: their
                -- cooldown widget is showing an AURA, and arming a spell recharge
                -- over it would overwrite the duration they exist to display.
                if fd._isBuffViewerFrame or frame._isCustomBuffFrame then return end
                -- Split from the value: "false" and "the frame has no such method"
                -- are different states, and entry B needs the first. Preset, racial,
                -- custom-spell and trinket frames are ours rather than CooldownViewer
                -- items and have no data source at all, which the sibling Clear hook
                -- relies on as an exclusion -- treating that as "at zero charges"
                -- would let them into a branch written for viewer items.
                local isViewerItem = type(frame.HasVisualDataSource_Charges) == "function"
                local hasCharges = isViewerItem and frame:HasVisualDataSource_Charges()
                -- ENTRY A (original): the Hide-Active override window, where
                -- Blizzard's aura pushes wipe the recharge we armed.
                local entryA = (fd._hideActiveOverriding and hasCharges) or false
                -- ENTRY B: the GCD has taken the icon over at the TAIL of a
                -- recharge. Measured in game: once the remaining recharge falls
                -- below one GCD length, Blizzard re-points the widget at the GCD
                -- (SetCooldown fires, GetSpellCooldown().isOnGCD flips true), and
                -- HasVisualDataSource_Charges is false throughout because the
                -- player is at ZERO charges -- so entry A cannot fire. Suppress
                -- GCD then does its job and alpha-0s that swipe, and the last
                -- second of the recharge goes blank, snapping back only when the
                -- charge lands. That is the reported "0 -> 1 breaks the cooldown
                -- swipe", and hiding was never the right answer: the recharge is
                -- still running and is what the player is watching. Re-arm the
                -- real recharge so the swipe keeps showing the truth.
                --
                -- fd._gcdChargeTailArmed is the SetSwipeColor hook's own verdict on
                -- that state, published one call earlier in the same refresh, so
                -- this path re-derives nothing.
                --
                -- Suppress GCD is re-checked here rather than trusted from the
                -- latch. Blizzard's expired branch skips SetSwipeColor entirely and
                -- frames are pooled, so the latch can survive into a frame or a bar
                -- it was not set for; requiring the setting again bounds a stale
                -- latch to "re-arm a charge spell that is genuinely recharging",
                -- which is the intended action anyway.
                local entryB = false
                if not entryA and isViewerItem and not hasCharges
                   and fd._gcdChargeTailArmed == true then
                    local bkB = fc2.barKey
                    local bdB = bkB and barDataByKey and barDataByKey[bkB]
                    entryB = (bdB and bdB.suppressGCD and true) or false
                    -- Per-spell Suppress GCD: same re-check contract as the bar
                    -- toggle. Session-gated so unused installs never resolve.
                    if not entryB and ns._cdmAnySuppressGcd then
                        local ssB = ns._ResolveCdmSS and ns._ResolveCdmSS(frame)
                        entryB = (ssB and ssB.suppressGCD and true) or false
                    end
                end
                if not (entryA or entryB) then return end
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- Charge spell with a recharge genuinely running. maxCharges > 1 is
                -- the charge-spell test every other carve-out in this file uses --
                -- a 1-charge spell reports charge data too, and re-arming one that
                -- Suppress GCD had just alpha-0'd would repaint it at full alpha in
                -- the same refresh. Both fields are clean; the secret
                -- currentCharges is never read.
                local ci = CdmChargeInfoFor(frame, sid2)
                if not (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) then
                    return
                end
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
                -- No-op on the entry-B path by construction: ApplyCdmChargeStyle
                -- bails unless HasVisualDataSource_Charges is true, and entry B
                -- requires it false. That is correct rather than an oversight --
                -- Hide Swipe (Charges) and Hide Recharge Edge already do not apply
                -- while the widget is off the charge source, so the tail now
                -- matches the rest of the zero-charge window instead of differing
                -- from it. Entry A still needs the call.
                ApplyCdmChargeStyle(frame, cd)
                -- We have just re-armed the REAL recharge, so whatever is now
                -- displayed is the recharge -- never a GCD. Suppress-GCD's alpha-0
                -- swipe (set while isOnGCD, e.g. right after pressing ANOTHER
                -- ability) must not stick here or the recharge stays invisible.
                --
                -- Black is only unconditionally right on the entry-A path, which by
                -- definition runs inside the Hide-Active window. Entry B can reach
                -- an icon whose active state paints a COLOURED swipe, and this write
                -- sits under _isProcessingOverride so the SetSwipeColor hook cannot
                -- put that colour back -- hence the active check. When the icon is
                -- active, leaving the colour alone is correct: the next refresh
                -- repaints it, and the geometry we just armed is what mattered.
                local bkA = fc2.barKey
                local bdA = bkA and barDataByKey and barDataByKey[bkA]
                if entryA or not CdmFrameIsActive(frame) then
                    cd:SetSwipeColor(0, 0, 0, (bdA and bdA.swipeAlpha) or 0.7)
                end
                fd._isProcessingOverride = false
            end
            if cd.SetCooldownFromDurationObject then
                hooksecurefunc(cd, "SetCooldownFromDurationObject", ReArmChargeRecharge)
                -- Also catch the placement-sigil case where Blizzard clears the
                -- widget via a zero-duration SetCooldownFromDurationObject rather
                -- than Clear(). The guard blocks recursion and the ~0 duration
                -- gate makes this a no-op for normal pushes.
                hooksecurefunc(cd, "SetCooldownFromDurationObject", ReAssertRealCooldown)
            end
            if cd.SetUseAuraDisplayTime then
                hooksecurefunc(cd, "SetUseAuraDisplayTime", ReArmChargeRecharge)
            end
            -- Pressing ANOTHER ability pushes the GCD onto this frame via
            -- SetCooldown (not the aura-display setters), replacing the charge
            -- recharge geometry -- in the Hide-Active window that wipes the real
            -- recharge until the active state ends, so re-arm on SetCooldown too.
            -- ReArmChargeRecharge fully self-gates and is re-entry guarded: a
            -- no-op for normal cooldowns and outside the override window.
            if cd.SetCooldown then
                hooksecurefunc(cd, "SetCooldown", ReArmChargeRecharge)
            end
        end
        -- Hook SetDesaturated AND SetDesaturation on the icon texture (Blizzard
        -- calls these every cooldown tick): while overriding the CD model (hide
        -- active state), re-apply the real CD duration so it cannot revert.
        if fd.tex and not fd._desatOverrideHooked then
            fd._desatOverrideHooked = true
            local function onDesatChange()
                if fd._isProcessingOverride then return end
                -- Two owners of this path now. The Hide-Active override is the
                -- original one. The second is the stale-linked-spell state, where
                -- Blizzard re-clears the widget AND re-saturates the icon on every
                -- refresh -- so the repair has to ride the same per-tick driver to
                -- survive, and the body below already does exactly the right thing
                -- for it: it re-arms the cooldown from OUR spell id and then sets
                -- the desaturation from that same id's real cooldown state.
                -- Cheap-first: the flag is one lookup, the helper two more.
                if not (fd._hideActiveOverriding or CdmStaleLinkedSpell(frame)) then return end
                fd._isProcessingOverride = true
                local cdw = fd.cooldown
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if sid2 and cdw then
                    if cdw.SetUseAuraDisplayTime then
                        cdw:SetUseAuraDisplayTime(false)
                    end
                    if cdw.SetCooldownFromDurationObject then
                        -- Effective spell ID: for transforms the charge/cooldown
                        -- APIs report against the override ID, not the base.
                        -- Query override first, fall back to base.
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
                                -- override is itself on a real CD (a cosmetic transform
                                -- sharing the base cooldown -- the fallback's purpose)
                                -- OR its cooldown is unknown (oc nil). A hero-talent
                                -- transform to a CASTABLE follow-up reports no real CD
                                -- and must NOT inherit the base's remaining cooldown
                                -- (that painted the base CD swipe over a usable proc);
                                -- leaving durObj nil takes the same no-swipe path as a
                                -- proc without a real CD. Only a CONFIRMED- castable
                                -- proc suppresses the borrow. Mirrors the desat guard
                                -- below so swipe and saturation agree. isActive/isOnGCD
                                -- are clean bools.
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
                -- Desaturate only if actually on cooldown; procs without a real
                -- CD stay saturated. Filter GCDs like the suppressGCD check. Ask
                -- the EFFECTIVE spell, override first: a transform's real cooldown
                -- ticks on the OVERRIDE id while the base reports none (measured:
                -- base isActive=false, override isActive=true isOnGCD=false), so a
                -- base-only read verdicts "not on cooldown" and never greys. Fall
                -- back to the base ONLY when the override query returns nothing
                -- (unknown), never on a clean "not active" -- that is the
                -- castable-proc case and must win.
                local effID2 = sid2
                if sid2 and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID2 = ovr end
                end
                local cdInfo2 = effID2 and C_Spell.GetSpellCooldown
                    and (C_Spell.GetSpellCooldown(effID2)
                        or (effID2 ~= sid2 and C_Spell.GetSpellCooldown(sid2)) or nil)
                local onRealCD = cdInfo2 and cdInfo2.isActive and not cdInfo2.isOnGCD
                -- Charge spells report cooldown isActive mid-recharge even with a
                -- castable charge left, which would wrongly desaturate a usable
                -- icon. currentCharges is SECRET in this tainted hook, so the
                -- usable-charge verdict has to come from somewhere else -- see
                -- the guard below.
                -- The charge-SPELL test is static charge data, NOT the
                -- HasVisualDataSource_Charges flag: that one is documented three
                -- times in this file as answering "is this icon drawing its recharge
                -- right now", which is false at full charges and during a GCD, so
                -- gating the whole branch on it made it dead code. maxCharges is
                -- stable and clean; the secret currentCharges is never read.
                -- Resolve it through Blizzard's own accessor rather than a base-ID
                -- read: CdmChargeInfoFor documents the two disagreeing on override
                -- spells (captured on Blink 1953 -> Shimmer 212653), where a base
                -- read reports the charge-less base, so this test came back false
                -- and the guard never ran on a 2-charge ability. The swipe guard
                -- already resolves charges this way and the two verdicts must agree.
                local chargeCI = CdmChargeInfoFor(frame, sid2)
                local maxCh = chargeCI and chargeCI.maxCharges
                local isChargeSpell = type(maxCh) == "number"
                    and not (issecretvalue and issecretvalue(maxCh))
                    and maxCh > 1
                local outOfCharges
                if onRealCD and isChargeSpell then
                    -- Preferred signal: Blizzard's own charge visual-data-source
                    -- flag. isOnActualCooldown below is derived from the cooldown
                    -- startTime + duration, both SECRET inside instanced content,
                    -- so it comes back unreadable from this tainted hook the
                    -- moment a key starts -- the guard then set nothing and a
                    -- banked charge desaturated. Fresh login looked fine because
                    -- nothing was secret yet. wasSetFromCharges is a plain literal
                    -- assigned inside an untainted branch, so it survives that,
                    -- and RefreshData clears it and CacheCooldownValues re-sets it
                    -- immediately before the SetDesaturated call this hooks, so it
                    -- is never stale here.
                    -- Only TRUE is informative: Blizzard sets it for
                    -- "cooldownStartTime > 0 and currentCharges > 0", so false is
                    -- equally what a full-charge icon and an aura-driven one
                    -- report -- those keep falling through to the read below, which
                    -- is why this cannot re-break greying at zero charges.
                    -- Read the field, falling back to the getter: a past field
                    -- dump on a 12.0 client reported the getter as nil on these
                    -- frames while isOnActualCooldown beside it read fine, so
                    -- take whichever of the two this client actually carries.
                    local fromCharges = frame.wasSetFromCharges
                    if type(fromCharges) ~= "boolean"
                        and type(frame.HasVisualDataSource_Charges) == "function" then
                        fromCharges = frame:HasVisualDataSource_Charges()
                    end
                    if type(fromCharges) == "boolean"
                        and not (issecretvalue and issecretvalue(fromCharges))
                        and fromCharges then
                        outOfCharges = false
                    end
                    if type(outOfCharges) ~= "boolean" then
                        local actualCD = frame.isOnActualCooldown
                        if not issecretvalue or not issecretvalue(actualCD) then
                            if actualCD == false then
                                outOfCharges = false
                            elseif actualCD == true then
                                outOfCharges = true
                            end
                        end
                    end
                end
                if outOfCharges == false then
                    onRealCD = false
                end
                -- No clear-only transform guard here: asking the override first
                -- already answers the castable-proc case. Such a guard can turn
                -- greying off but never on, so an icon whose cooldown lives on
                -- the override could never grey -- do not reintroduce one.
                fd.tex:SetDesaturated(onRealCD or false)
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", onDesatChange)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", onDesatChange)
            end
        end
        -- Swipe direction baseline by FRAME kind, not just bar kind: a buff frame
        -- (or hosted-buff placeholder) fills like a buff even on a CD/utility bar.
        -- Decoration is once-per-frame while Blizzard POOLS frames, so record the
        -- kind in fd._revKind and let the claim loops re-assert on kind change,
        -- else a frame decorated for the wrong family keeps that direction all
        -- session (buffs randomly reversed by pool history).
        local isBuff = (barData.barType == "buffs" or barData.key == "buffs"
            or barData.barType == "custom_buff"
            or fd._isBuffViewerFrame or frame._isPlaceholderFrame) and true or false
        -- Per-spell Reverse Swipe flips the baseline (see EffectiveReverseSwipe):
        -- writing the bare kind here undid the setting on every reanchor.
        local revEff = ns.EffectiveReverseSwipe(frame, barData.key, isBuff)
        fd.cooldown:SetReverse(revEff)
        fd._revKind = revEff

        -- Clear IS hooked above (_swipeColorHooked block) to restore the recharge swipe
        -- on charge spells, and SetCooldown too (ReArmChargeRecharge) so an off-GCD
        -- push cannot wipe the recharge in the Hide-Active window. A hooksecurefunc
        -- post-hook does not taint the secure caller; taint would stick only if the
        -- hook BODY wrote a Blizzard frame field (isActive, allowAvailableAlert) or
        -- called Show/Hide/SetAlpha on a Blizzard frame. Neither does: they read clean
        -- getters and call pure cooldown-widget setters (SetUseAuraDisplayTime /
        -- SetCooldownFromDurationObject / SetDrawSwipe / SetSwipeColor), and all hook
        -- state lives on the external fd table, never on the Blizzard frame.

        -- Cooldown State Effect: separate additive SetDesaturated hook.
        -- Blizzard calls it on every CD tick AND on CD end -- the right event
        -- for both transitions. Independent from onDesatChange (hideActive).
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
                -- Preset frames (trinket/racial/potion/custom spell) own their cd-state
                -- through the Fake-Active engine, which reads the ITEM/racial cooldown.
                -- GetSpellCooldown cannot read a negative item key, so this spell path
                -- always sees the item as ready and would re-light the shared
                -- glowOverlay every desat tick while on cooldown. Hand off cleanly
                -- (clear any glow we owned).
                if ns.PresetHasCdState and ns.PresetHasCdState(frame) then
                    if fd._cdStateGlowOn then
                        if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                        fd._cdStateGlowOn = false
                        -- The Fake-Active path tracks this overlay via its own
                        -- flag; clear it too so its next tick re-asserts the
                        -- glow we just stopped (else it thinks the glow is
                        -- still on and a ready preset stays dark).
                        fd._presetCdGlowOn = false
                    end
                    return
                end
                local ss2 = ResolveSpellSettings(frame, sid2, false)
                local cse = ss2 and ss2.cdStateEffect
                -- Shift-Icons variants = base hidden mode + a bar-relayout
                -- flag; normalize here so every comparison below is unchanged.
                local cseShift = (cse == "hiddenOnCDShift" or cse == "hiddenReadyShift")
                if cse == "hiddenOnCDShift" then cse = "hiddenOnCD"
                elseif cse == "hiddenReadyShift" then cse = "hiddenReady" end
                if not cse then
                    if fd._cdStateGlowOn then
                        if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                        fd._cdStateGlowOn = false
                    end
                    -- A preset's cdState lives in customActiveStates (Fake-Active
                    -- engine), not per-bar spellSettings -- clearing its hidden flag
                    -- here would flash it visible every desat tick. Those frames
                    -- already returned through the PresetHasCdState hand-off above,
                    -- so no re-check is needed on this path.
                    if fc2 and fc2._cdStateHidden then
                        fc2._cdStateHidden = false
                    end
                    if fc2 and fc2._cdStateShiftHidden and ns.SetCdStateShiftHidden then
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
                -- Hidden / lower-alpha modes: hand off to the shared deferred
                -- evaluator (ArmCdStateEval -- see its comment for the
                -- one-frame wait). cse is normalized, so Shift variants arrive
                -- as their base mode plus cseShift.
                if cse == "hiddenOnCD" or cse == "hiddenReady" or cse == "lowerAlphaOnCD" then
                    ArmCdStateEval(frame, fd, cse, cseShift,
                        (ss2 and ss2.cdStateLowerAlpha) or 0.5,
                        ss2 and ss2.chargeHideUntilSpent)
                    -- Hidden (CD Ready) on a charge spell also needs the refill-to-max
                    -- edge, which this hook never fires. Registered once per spell
                    -- binding (a pooled frame can be handed a different spell), so
                    -- steady-state cost is one field compare per repaint.
                    if cse == "hiddenReady" and fd._cdStateChargeBoundSid ~= sid2 then
                        fd._cdStateChargeBoundSid = sid2
                        ns.WatchCdStateChargeIfEnabled(frame)
                    end
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
                    -- Plain CD Ready Glow: cooldown state only, decided right here
                    -- -- no usability reads, no deferral, no events for genuine
                    -- Blizzard frames (Blizzard calls SetDesaturated on them at
                    -- every cd transition, re-firing this hook). EUI's own custom
                    -- frames (racials / trinkets / potions / custom spells) instead
                    -- drive desaturation via SetDesaturation(float), which does NOT
                    -- trigger this SetDesaturated hook -- so on those the glow would
                    -- never re-evaluate and would stay lit through the whole
                    -- cooldown. Register just those for the event-driven cooldown
                    -- watch (its loop handles plain variants too); Blizzard frames
                    -- keep the zero-event path.
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
                        -- procGlowActive gate: the proc glow shares this
                        -- overlay and has priority -- never start over it
                        -- (ShowProcGlow clears the memo, so this is the
                        -- explicit gate that replaces the old accidental one).
                        if fd.glowOverlay and not fd._cdStateGlowOn
                            and not fd.procGlowActive then
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
                                -- procGlowActive: proc owns the shared
                                -- overlay -- never start over a live proc.
                                if fd.glowOverlay and not fd._cdStateGlowOn
                                    and not fd.procGlowActive then
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
        -- and ticks). Re-applies desaturation whenever the spell is NOT in its
        -- active state, read LIVE from the swipe color (fd._wasActive is stale on
        -- some falloffs, e.g. DoT expiry); secret arg never read, guarded against
        -- fighting the swipe block's own SetDesaturated. ZERO-COST WHEN UNUSED: the
        -- first line is a flag check (ns._cdmAnyDesatNotActive, set only when a
        -- spell actually uses the setting), so disabled users pay nothing.
        if fd.tex and not fd._desatNotActiveHooked then
            fd._desatNotActiveHooked = true
            local function _maintainDesat()
                if not ns._cdmAnyDesatNotActive then return end
                if fd._isProcessingOverride then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                if not sid2 or not bk2 then return end
                local ss2 = ResolveSpellSettings(frame, sid2, false)
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

        -- Keep Colored (On CD): additive hook on SetDesaturated/SetDesaturation,
        -- mirror of the block above. Desaturating on cooldown is BLIZZARD's own
        -- behaviour (greys the icon every CD tick), so suppressing it means
        -- re-saturating right after each call rather than skipping our own.
        -- Deliberately does NOT clear fd._desatNA: Desaturate When Not Active is the
        -- more specific setting and wins when both are on (bail below); this one
        -- only removes the implicit cooldown grey. Zero-cost when unused (same shape as above).
        if fd.tex and not fd._noDesatOnCDHooked then
            fd._noDesatOnCDHooked = true
            local function _keepColored()
                if not ns._cdmAnyNoDesatOnCD then return end
                if fd._isProcessingOverride then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                if not sid2 or not bk2 then return end
                local ss2 = ResolveSpellSettings(frame, sid2, false)
                if not (ss2 and ss2.noDesatOnCD) then return end
                if ss2.desatNotActive then return end
                fd._isProcessingOverride = true
                fd.tex:SetDesaturated(false)
                if fd.tex.SetDesaturation then fd.tex:SetDesaturation(0) end
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", _keepColored)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", _keepColored)
            end
        end

        -- Audio Effect on CD Ready (cd/utility per-icon) is driven purely by the
        -- authoritative SPELL_UPDATE_COOLDOWN/SPELL_UPDATE_CHARGES events via
        -- WatchCdReadySoundIfEnabled (called from DecorateFrame), deliberately NOT
        -- off a SetDesaturated visual hook: that hook fires at repaint moments
        -- unrelated to the real cooldown and sampled a transient GCD race
        -- (isActive=true/isOnGCD=false) that false-fired the sound.
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
local _trinketEventFrame = CreateFrame("Frame")

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
    -- Decoration is the settings/content edge: drop the cooldown push memo
    -- (UpdateTrinketCooldown) so the next event re-pushes and re-derives
    -- the desaturation against fresh settings.
    f._cdMemoStart, f._cdMemoDur = nil, nil
    local itemID = GetInventoryItemID("player", slotID)
    _trinketItemCache[slotID] = itemID
    if not itemID then
        f._slotScanPending = nil
        f:Hide()
        return
    end
    -- Item data not in the client cache yet (cold cache at login): GetItemSpell
    -- reads nil for an on-use item, which the passive test below would take as
    -- conclusive and nothing would ever re-scan. Keep the previous state,
    -- request the load and let ITEM_DATA_LOAD_RESULT re-run the scan.
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        f._slotScanPending = true
        C_Item.RequestLoadItemDataByID(itemID)
        _trinketEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        return
    end
    f._slotScanPending = nil
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
            -- The "Use: ... (X Min Cooldown)" line is the use spell's
            -- DESCRIPTION, loaded separately from the item data: on a cold
            -- spell cache the tooltip omits the line entirely and the scan
            -- would read an on-use trinket as passive. Blizzard's signal is an
            -- empty description until SPELL_TEXT_UPDATE fires for the spell
            -- (nil when the spell record itself is not loaded yet).
            local desc = C_Spell.GetSpellDescription(spellID)
            local descLoaded = desc ~= nil and desc ~= ""
            if not descLoaded then
                f._slotScanPending = true
                if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
                _trinketEventFrame:RegisterEvent("SPELL_TEXT_UPDATE")
                _trinketEventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
                return
            end
            local tipData = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
            if tipData and tipData.lines then
                -- Conclusive only once the tooltip actually carries the Use
                -- line (GetItemSpell only reports on-use spells, so the line
                -- always arrives once the spell text is in); until then the
                -- text is still loading and SPELL_TEXT_UPDATE re-runs us.
                local usePrefix = ITEM_SPELL_TRIGGER_ONUSE
                for _, tipLine in ipairs(tipData.lines) do
                    local lt = tipLine.leftText
                    if lt and usePrefix and lt:sub(1, #usePrefix) == usePrefix then
                        scanConclusive = true
                    end
                    if lt and lt:find("Cooldown%)") then
                        local cdStr = lt:match("%((.+Cooldown)%)")
                        if cdStr then
                            -- Tooltip data carries raw grammar tokens
                            -- ("2 |4Min:Min; Cooldown"); reduce to the
                            -- singular so the unit parse sees "2 Min".
                            cdStr = cdStr:gsub("|4(%a+):[^;]*;", "%1")
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
                if not scanConclusive then
                    f._slotScanPending = true
                    if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
                    _trinketEventFrame:RegisterEvent("SPELL_TEXT_UPDATE")
                    _trinketEventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
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

-- Keep Colored (On CD) for PRESET frames (trinket slots, racials, potions and
-- user-injected custom spells). Those never run Blizzard's cooldown desaturation
-- -- the Fake-Active engine greys them itself (UpdateTrinketCooldown below and
-- ApplySpellDesaturation further down), so there's no SetDesaturated call for the
-- per-spell hook in DecorateFrame to ride; they read the setting from their own
-- cas entry instead, at the two points where they'd grey the icon. Zero-cost
-- when unused: the session gate is checked first (flipped by AddUserRule during the Fake-Active rebuild, so it survives /reload).
local function PresetKeepsColor(f)
    if not ns._cdmAnyNoDesatOnCD then return false end
    local fc = f and _ecmeFC[f]
    local sid = fc and fc.spellID
    if not sid or not ns.GetEffectiveCustomActiveState then return false end
    local cas = ns.GetEffectiveCustomActiveState(sid)
    return (cas and cas.noDesatOnCD) and true or false
end
ns.PresetKeepsColor = PresetKeepsColor

local function UpdateTrinketCooldown(slotID)
    local f = _trinketFrames[slotID]
    if not f or not f._trinketIsOnUse then return false end
    local start, dur, enable = GetInventoryItemCooldown("player", slotID)
    if start and dur and dur > 1.5 and enable == 1 then
        -- Push-on-edge: SPELL_UPDATE_COOLDOWN fires 10-17/sec in combat and
        -- re-pushed the SAME schedule every time. start/dur are plain for
        -- player inventory (compared unguarded here since forever); a
        -- modified cooldown changes them and re-pushes. The memo clears at
        -- decoration (UpdateTrinketFrame), so settings changes re-derive.
        if f._cdMemoStart ~= start or f._cdMemoDur ~= dur then
            f._cdMemoStart, f._cdMemoDur = start, dur
            f._cooldown:SetCooldown(start, dur)
            if f._tex then f._tex:SetDesaturated(not PresetKeepsColor(f)) end
        end
        return true
    else
        -- false = "cleared" marker, distinct from nil = "unknown" (fresh
        -- decoration): unknown must always paint the clear once.
        if f._cdMemoStart ~= false then
            f._cdMemoStart, f._cdMemoDur = false, false
            f._cooldown:Clear()
            if f._tex then f._tex:SetDesaturated(false) end
        end
        return false
    end
end
ns.UpdateTrinketCooldown = UpdateTrinketCooldown

_trinketEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
_trinketEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_trinketEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- True when a slot frame's on-use detection needs another pass: trinkets whose
-- item has a spell the tooltip scan couldn't confirm yet, and user-added slots
-- whose instance tooltip wasn't cached (enchant/tinker lines).
local function SlotScanIncomplete(f)
    return (f._trinketSpellID and not f._trinketIsOnUse) or f._slotScanPending
end

_trinketEventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ITEM_DATA_LOAD_RESULT" or event == "SPELL_DATA_LOAD_RESULT"
       or event == "SPELL_TEXT_UPDATE" then
        -- Registered only while a slot scan waits on the item or use-spell
        -- data; a failed load just drops the pending flag (previous state
        -- stands). Item loads match on the cached item id, spell loads and
        -- description arrivals on the frame's use spell.
        local byItem = event == "ITEM_DATA_LOAD_RESULT"
        local ok = arg2
        if event == "SPELL_TEXT_UPDATE" then ok = true end
        local pending = false
        for slot, f in pairs(_trinketFrames) do
            if f._slotScanPending then
                local key
                if byItem then key = _trinketItemCache[slot] else key = f._trinketSpellID end
                if key == arg1 then
                    if ok then
                        UpdateTrinketFrame(slot)
                    else
                        f._slotScanPending = nil
                    end
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end
            end
            if f._slotScanPending then pending = true end
        end
        if not pending then
            _trinketEventFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
            _trinketEventFrame:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
            _trinketEventFrame:UnregisterEvent("SPELL_TEXT_UPDATE")
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
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
        -- Tooltip data may not be cached yet on login, causing on-use detection to
        -- fail. Retry only for slots whose scan is incomplete (tooltip wasn't ready).
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
--  (pixelGlowReadyUsable/buttonGlowReadyUsable) are registered in a watched set
--  (ns.CDGlowWatch, called from the decoration paths). While non-empty,
--  SPELL_UPDATE_COOLDOWN + UNIT_POWER_FREQUENT (player) drive a dirty flag; a
--  hidden frame re-evaluates ONLY the watched frames on the next OnUpdate, then
--  hides again. While empty, no events are registered -- zero-cost unless a
--  ready-glow effect is actually configured. SPELL_UPDATE_USABLE alone is not
--  reliable for all resource types (e.g. Fury), so cooldown + power events stand
--  in; UNIT_POWER_FREQUENT (not UPDATE) is needed so continuous regen (energy
--  ticking toward a spell's cost) re-evaluates without waiting for a discrete
--  spend/gain event, the dirty flag capping work at once per frame. During the
--  loading-screen settle window (ns._cdmSoundSuppressed, shared with the CDM
--  sound system) API answers aren't trustworthy: the flush keeps current state
--  and retries shortly, and the first post-window pass is authoritative --
--  clearing a glow that came up stale across a /reload.
-------------------------------------------------------------------------------
do
    local _cdGlowWatched = setmetatable({}, { __mode = "k" })  -- frame -> true
    local _cdGlowDirty = false
    local _cdGlowEventsOn = false
    local _cdGlowRetryPending = false

    local _cdGlowUpdateFrame = ns.TakeShell()
    _cdGlowUpdateFrame:Hide()
    local _cdGlowEventFrame = ns.TakeShell()

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

    -- Register a frame whose resolved cdStateEffect is a Resource Aware ready-glow.
    -- Called from the decoration paths (DecorateFrame's SetDesaturated hook and
    -- RefreshCDMIconAppearance). The flush below prunes entries whose effect or claim
    -- went away and unregisters the events once nothing is watched.
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
                        -- procGlowActive: proc owns the shared overlay --
                        -- never start over a live proc; StopProcGlow queues
                        -- this flush again once the proc ends.
                        if not fd._cdStateGlowOn and not fd.procGlowActive then
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
                -- Effect removed, spell unassigned, or frame released back to the pool:
                -- stop any leftover glow and drop the watch. Events unregister once the
                -- set drains (checked below and on the next queued flush).
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

    -- One re-evaluation pass on the next frame. Called after rebuilds (FullCDMRebuild)
    -- and by the event listeners; no-ops instantly when nothing is watched.
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
-- Tail of a charge recharge, for "Suppress GCD". A recharge with less time left than
-- the running GCD is no longer what the swipe draws (the GCD outlasts it and takes
-- the frame over), so it must be suppressed like any other GCD. The remaining time is
-- secret and cannot be compared in Lua, so the threshold is applied engine-side via a
-- Step curve: below the GCD yields alpha 0, at/above yields the bar's normal alpha.
-- The result may itself be SECRET; never compare it. SetSwipeColor is
-- AllowedWhenTainted so it goes straight in. GCD length comes from UnitSpellHaste,
-- also secret in instanced combat: issecretvalue-first, falling back to 0 (unhasted
-- 1.5s GCD), which errs toward suppressing the tail slightly early on hasted players.
local _gcdTailCurves = {}
function ns.GCDTailAlpha(durObj, normalAlpha)
    normalAlpha = normalAlpha or 0
    if not (durObj and durObj.EvaluateRemainingDuration
            and C_CurveUtil and C_CurveUtil.CreateCurve
            and Enum and Enum.LuaCurveType) then
        return normalAlpha
    end
    local haste = (UnitSpellHaste and UnitSpellHaste("player")) or 0
    if (issecretvalue and issecretvalue(haste)) or type(haste) ~= "number" then
        haste = 0
    end
    local len = 1.5 / (1 + haste / 100)
    if len < 0.75 then len = 0.75 end          -- engine floor
    len = math.floor(len * 100 + 0.5) / 100    -- bound the curve cache
    local key = len .. ":" .. normalAlpha
    local curve = _gcdTailCurves[key]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 0)                -- recharge ends first: the swipe is the GCD
        curve:AddPoint(len, normalAlpha)    -- recharge outlasts it: leave it visible
        _gcdTailCurves[key] = curve
    end
    return durObj:EvaluateRemainingDuration(curve, normalAlpha)
end

local _desatCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    _desatCurve = C_CurveUtil.CreateCurve()
    _desatCurve:SetType(Enum.LuaCurveType.Step)
    _desatCurve:AddPoint(0, 0)
    _desatCurve:AddPoint(0.001, 1)
end

local function ApplySpellDesaturation(f, durObj)
    if not f._tex then return end
    -- Out-of-band write: drop the drain's edge-gate memo so its next tick
    -- re-derives instead of trusting a value this call may have changed.
    f._lastDesatVal = nil
    if PresetKeepsColor(f) then f._tex:SetDesaturation(0); return end
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

-- Aura-tracked custom buffs: the WHOLE subsystem lives in one table (_AC)
-- because this file rides the Lua 5.1 200-local cap. bars: barKey ->
-- { holder, container, sids, sig, queued, bdRef, hookedBar }.
--
-- FINAL SHAPE (field-settled 2026-08-08): customs render in ONE engine flow
-- container per bar -- PURE ENGINE, zero Lua per aura event. Under 12.1
-- secrecy (M+/raid combat -- the normal state for our users) Lua can NEVER
-- know whether these auras are active (RequiresNonSecretAura: "protected
-- APIs will return no values"), so customs can never join the bar's own
-- icon row: in-bar mixing needs a Lua-known count. Both workarounds were
-- field-rejected (reserved grey slots push real buffs off center;
-- tail-injection reads off center on centered bars). The engine, however,
-- sizes and CENTERS its own content under full secrecy, so the container
-- hangs off the bar GROWTH-AWARE: directional bars get a tail flowing off
-- the growth edge (reads as the bar simply extending), CENTER bars get a
-- centered strip below/above (the only centered shape physics allows).
-- Actives compact engine-side; when none are up it renders nothing.
--
-- The container lives on a UIParent-anchored holder: engine aura buttons
-- are FORBIDDEN objects, and any anchor path from the bar to them
-- restriction-locks the bar's own geometry (field-proven: the bar stopped
-- re-centering). The holder follows the bar via SetPoint/OnSizeChanged/
-- OnShow/OnHide post-hooks on our own bar frame, coalesced one frame.
local _AC = { bars = {}, syncPending = {} }

-- Position a bar's holder from its CURRENT rect + growth settings. The
-- container point (set at build) mirrors these anchors so the engine flows
-- away from the bar / centers under it.
function _AC.Anchor(barKey, rec)
    local barFrame = cdmBarFrames[barKey]
    local holder = rec and rec.holder
    if not (barFrame and holder) then return end
    holder:SetShown(barFrame:IsShown())
    holder:ClearAllPoints()
    local ok, bl, bb, bw, bh = pcall(barFrame.GetRect, barFrame)
    if not (ok and bl) then
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -10000, -10000)
        return
    end
    local bd = rec.bdRef
    local gap = (bd and bd.spacing) or 2
    local grow = (bd and bd.growDirection) or "CENTER"
    local cx, cy = bl + bw / 2, bb + bh / 2
    -- END-OF-BAR TAIL for every growth mode (user-directed): customs flow
    -- off the bar's end -- left-grow bars extend left, everything else
    -- extends right; vertical bars extend past their up/down end.
    --
    -- EMPTY BAR (live content width 0, published by LayoutCDMBar -- the
    -- bar's own rect is deliberately stale then): the tail BECOMES the bar.
    -- CENTER-grow bars center the strip ON the bar's position (container
    -- point flips to CENTER so the engine centers it); directional bars
    -- seat it at the FIXED growth edge -- exactly where the first real
    -- buff would render.
    local empty = (barFrame._acLiveW ~= nil and barFrame._acLiveW <= 0.5)
    local wantPt = (empty and grow == "CENTER") and "CENTER" or rec.pt
    if rec.container and wantPt and rec.curPt ~= wantPt then
        rec.curPt = wantPt
        rec.container:ClearAllPoints()
        rec.container:SetPoint(wantPt)
    end
    if bd and bd.verticalOrientation then
        if grow == "UP" then
            holder:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, empty and bb or (bb + bh + gap))
        elseif empty and grow == "CENTER" then
            holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        else
            holder:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, empty and (bb + bh) or (bb - gap))
        end
    elseif grow == "LEFT" then
        holder:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", empty and (bl + bw) or (bl - gap), cy)
    elseif empty and grow == "CENTER" then
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    else
        holder:SetPoint("LEFT", UIParent, "BOTTOMLEFT", empty and bl or (bl + bw + gap), cy)
    end
end

-- LayoutCDMBar pokes the tail on EVERY pass (empty path included): count
-- transitions can land on identical geometry (no size/point events), and
-- the empty<->occupied mode flip must never be missed.
function ns._AuraCustomPoke(barKey)
    if _AC.bars[barKey] then _AC.MarkSync(barKey) end
end

-- Coalesced holder re-anchoring, driven by the bar-frame hooks.
_AC.frame = CreateFrame("Frame")
_AC.frame:Hide()
_AC.frame:SetScript("OnUpdate", function(self)
    self:Hide()
    for barKey in pairs(_AC.syncPending) do
        _AC.syncPending[barKey] = nil
        _AC.Anchor(barKey, _AC.bars[barKey])
    end
end)

function _AC.MarkSync(barKey)
    if _AC.syncPending[barKey] then return end
    _AC.syncPending[barKey] = true
    _AC.frame:Show()
end

-- LIVE SET for the preset drain: only the frames ProcessPresetCooldowns and the hot
-- listener loops actually work on (SHOWN racial/custom-spell/item preset frames;
-- custom-BUFF frames are excluded, never register here). _presetFrames above is the
-- permanent identity/reuse map and MUST NEVER BE PRUNED: a pruned key would make the
-- create-only sites build a NEW frame object on the next inject and leak the old one
-- (WoW frames are unreclaimable) -- it grows with every distinct config touched in a
-- session, so the drain iterates this LIVE set instead (reuse-map growth costs
-- nothing). OnShow/OnHide track the frame's own shown flag, matching the old
-- IsShown() gate exactly (alpha/parent-only hiding behaves identically).
local _pcActive = {}
local function _RegisterPresetLive(f, fkey)
    f._pfKey = fkey
    f:HookScript("OnShow", function(self)
        _pcActive[self] = true
        -- Show is a state edge (events may have fired while hidden):
        -- re-read and re-push everything on the next pass.
        self._cdPushArm = true
        if self._isItemPresetFrame then
            self._itemWalkArm = true
            self._countArm = true
        end
        if ns._MarkPresetCdDirty then ns._MarkPresetCdDirty() end
    end)
    f:HookScript("OnHide", function(self)
        _pcActive[self] = nil
    end)
    if f:IsShown() then _pcActive[f] = true end
end

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

-- Spellbook name -> first known castable id with that name. A tracked-buff slot
-- holds AURA ids, and an aura carries no link back to the spell that applies it
-- (every identity API is a fixed point on it), while the CASTABLE side is where
-- the talent override lives; an aura and its caster share a name, so the book is
-- the only available bridge. Built on first use, dropped on talent change (the
-- override it feeds is talent-dependent). An EMPTY result is treated as "not
-- built yet" rather than cached: the first placeholder can resolve before the
-- spellbook populates at login, and caching that would strand the bridge until
-- the next talent change (a real character always has spells, so empty only
-- means too early). A pcall failure IS cached, since a missing API won't start working.
local _bookByName
local function EnsureBookNameMap()
    if not _bookByName then
        local built = {}
        local ok = pcall(function()
            local nLines = C_SpellBook.GetNumSpellBookSkillLines()
            for i = 1, (nLines or 0) do
                local li = C_SpellBook.GetSpellBookSkillLineInfo(i)
                if li and li.itemIndexOffset and li.numSpellBookItems then
                    for j = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                        local it = C_SpellBook.GetSpellBookItemInfo(j, Enum.SpellBookSpellBank.Player)
                        local bsid = it and it.spellID
                        if bsid then
                            local nm = C_Spell.GetSpellName(bsid)
                            if nm and built[nm] == nil then built[nm] = bsid end
                        end
                    end
                end
            end
        end)
        if not ok then
            _bookByName = {}
        elseif next(built) then
            _bookByName = built
        else
            return built  -- too early; retry on the next call
        end
    end
    return _bookByName
end
local function BookIDForName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return EnsureBookNameMap()[name]
end
ns.WipeCdmBookNameCache = function() _bookByName = nil end
ns.CdmBookIDForName = BookIDForName
ns.CdmBookNameCount = function()
    local n = 0
    for _ in pairs(EnsureBookNameMap()) do n = n + 1 end
    return n
end

-- Resolve the spell whose ICON an inactive placeholder should paint. An ACTIVE
-- buff frame renders the live aura, so a talent that REPLACES a spell shows the
-- replacement (e.g. Hellcaller: Wither); an INACTIVE frame has no aura to read
-- and falls back to cooldownInfo, which still names the pre-talent spell, so the
-- same icon changes art as the aura comes and goes. Two ways a replacement can
-- show up, tried in order: (1) something in the slot's identity set (resolved
-- id, cooldownInfo's base, override or linked ids) is itself overridden --
-- covers CASTABLE-keyed slots; (2) nothing is overridden, the normal state for a
-- tracked-buff slot, since it holds AURA ids and an aura carries no override
-- even when a talent replaces the spell behind it (e.g. Destruction's Immolate
-- slot resolves to aura 157736, reports overrideSpellID == spellID, and merely
-- LISTS Wither's aura 445474 as a link) -- fall back to the spellbook, matching
-- by name. Returns sid untouched when neither applies (every spec without a
-- replacing talent). Callers use the result for ART ONLY: identity, pooling and settings resolution stay keyed on the original id.
local function ResolvePlaceholderIconSID(sid, cdID)
    local FO = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    if not FO or type(sid) ~= "number" or sid <= 0 then return sid end
    if issecretvalue and issecretvalue(sid) then return sid end

    local function TryID(id)
        if type(id) ~= "number" or id <= 0 then return nil end
        if issecretvalue and issecretvalue(id) then return nil end
        local o = FO(id)
        if type(o) == "number" and o > 0 and o ~= id then return o end
        return nil
    end

    local hit = TryID(sid)
    if hit then return hit end

    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local info = (cdID ~= nil and gci) and gci(cdID) or nil
    if info then
        hit = TryID(info.spellID) or TryID(info.overrideSpellID)
        if hit then return hit end
        if info.linkedSpellIDs then
            for _, lid in ipairs(info.linkedSpellIDs) do
                hit = TryID(lid)
                if hit then return hit end
            end
        end
    end

    -- Nothing in the slot is overridden, the normal state for a tracked-buff slot
    -- (it holds aura ids, and auras carry no override even when a talent replaces
    -- the spell behind them, e.g. Hellcaller's Immolate slot reports
    -- overrideSpellID == spellID and merely LISTS Wither's aura as a link).
    -- Bridge to the castable by name and take ITS live override, where the
    -- replacement actually shows up. One spellbook scan per talent change; no-op without a replacing talent.
    local NameOf = C_Spell and C_Spell.GetSpellName
    local nm = NameOf and NameOf(sid)
    local castable = BookIDForName(nm)
    if castable then
        local o = FO(castable)
        if type(o) == "number" and o > 0 and o ~= castable then return o end
    end

    -- The spellbook lists the REPLACEMENT rather than the base, so a replaced
    -- spell's name can be absent from it entirely and the lookup above finds
    -- nothing to follow; the test then inverts: when a LINKED variant's name is
    -- in the book and this slot's own name is not, the linked form is what the
    -- player actually casts (requiring the slot's name to be absent keeps this
    -- from firing while both forms are available). Return the BOOK id, not the
    -- linked id: a linked id is the variant's AURA (Wither's DoT 445474) while
    -- the book id is the CASTABLE the player actually has (Wither 445468), and
    -- the two carry different art (returning an aura here painted a flicker
    -- across a hero-talent swap, since the castable branch above returns a castable too).
    if info and info.linkedSpellIDs and not castable then
        for _, lid in ipairs(info.linkedSpellIDs) do
            if type(lid) == "number" and lid > 0
               and not (issecretvalue and issecretvalue(lid)) then
                local book = BookIDForName(NameOf and NameOf(lid))
                if book then return book end
            end
        end
    end
    return sid
end
ns.ResolvePlaceholderIconSID = ResolvePlaceholderIconSID

-- identKey: optional pooling identity, defaulting to spellID. Buff
-- placeholders pass one so two viewer slots that collide on spellID do not
-- share a single pooled frame (see the collision note at the call site).
local function GetOrCreatePlaceholderFrame(barKey, spellID, iconID, identKey)
    local fkey = barKey .. ":ph:" .. tostring(identKey or spellID)
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
            -- A placeholder that renders at alpha 0 has nothing under the
            -- cursor to describe: "Keep Buffs in Same Place"
            -- (bd2.hidePlaceholderIcon) and hosted "Visibility When Missing:
            -- Hidden" (_missingHidden) both reserve the slot invisibly, so the
            -- buff is NOT active and its tooltip must stay down. Same pair of
            -- flags the three opacity passes test before forcing alpha 0.
            if bd2.hidePlaceholderIcon or self._missingHidden then return end
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
    -- Re-assert on reuse: a pooled frame outlives a talent swap, so the id it
    -- was created with can name the pre-talent spell (its tooltip would still
    -- read Immolate on a Hellcaller Wither slot).
    f._phSpellID = spellID
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
        local iconSID = ns.LustPresetIconSpellID and ns.LustPresetIconSpellID(sid) or sid
        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconSID)
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
    -- desaturation pass (ProcessPresetCooldowns) wouldn't re-run at the ready
    -- edge and the icon would stay greyed until some unrelated event marked it
    -- dirty (the CD-ready glow polls continuously and lights up instantly, so
    -- without this the pot glows while still desaturated). Poke the processor at
    -- the expiry edge so the next tick re-evaluates count/CD/lockout (a plain
    -- re-saturate would be wrong when the last charge was just used -- total==0 must keep it greyed).
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
    _RegisterPresetLive(f, fkey)
    return f
end
ns.GetOrCreateItemPresetFrame = GetOrCreateItemPresetFrame

-- Crafted-quality pip for item frames -- the action bars' Show Rank Icon, for
-- CDM. Those read C_ActionBar.GetProfessionQualityInfo, which needs an action
-- slot; an item frame has only an item id, so this asks the item-side call that
-- returns the same CraftingQualityInfo struct, and takes iconInventory off it
-- exactly as the action bars do. Blizzard's own callers pass a LINK rather than
-- a bare id (and the action bar work recorded bare-id reads coming back nil), so
-- prefer the link and keep the id as the fallback.
-- Per bar and off by default: nothing here is created or called until a bar
-- turns it on. The resolved atlas is memoised per item so the steady state is
-- one compare; it re-reads when the icon changes which item it is showing,
-- which for a pot preset is the point (the pip follows the rank resolved).
-- The memo is deliberately TRI-STATE. An item whose data the client has not
-- cached yet answers nil, and that is the state on the pass right after login,
-- so caching it as "no quality" would leave the pip permanently missing on
-- exactly the items it is for: nil = unresolved, retry next pass (item data is
-- requested here, so the retry has something to find); false = resolved, this
-- item has no crafted quality, stop asking.
local _cdmQualityAtlas = {}
local function CdmQualityAtlasFor(q)
    local hit = _cdmQualityAtlas[q]
    if hit ~= nil then return hit or nil end
    local probe = C_Texture and C_Texture.GetAtlasInfo
    local names = {
        "Professions-Icon-Quality-Tier" .. q .. "-Inv-Small",
        "Professions-Icon-Quality-Tier" .. q .. "-Small",
        "Professions-Icon-Quality-Tier" .. q,
    }
    for i = 1, #names do
        if probe and probe(names[i]) then
            _cdmQualityAtlas[q] = names[i]
            return names[i]
        end
    end
    _cdmQualityAtlas[q] = false
    return nil
end

local function ApplyItemQualityPip(f, itemID, on)
    if not on then
        if f._qualityHolder then f._qualityHolder:Hide() end
        f._qualityItemID, f._qualityAtlas = nil, nil
        return
    end
    if not itemID then return end
    -- Resolved already for this exact item (false = resolved as "no quality").
    if f._qualityItemID == itemID and f._qualityAtlas ~= nil then return end

    local atlas
    local ts = C_TradeSkillUI
    local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID))
    if not link and C_Item and C_Item.RequestLoadItemDataByID then
        -- Not cached yet. Ask for it and leave the memo unresolved so the next
        -- pass retries rather than baking in the miss.
        C_Item.RequestLoadItemDataByID(itemID)
    end
    -- Blizzard's own item buttons (SetItemCraftingQualityOverlay in
    -- ItemButtonTemplate) ask REAGENT quality first and only then CRAFTED, and
    -- that order is the whole fix: a live probe on this bar had the crafted
    -- calls answering nil for every potion on it -- ranked consumables carry a
    -- reagent quality, not a crafted one. Both return the same
    -- CraftingQualityInfo, so iconInventory comes off whichever answers.
    if ts and ts.GetItemReagentQualityInfo then
        local ok, info = pcall(ts.GetItemReagentQualityInfo, link or itemID)
        atlas = ok and info and info.iconInventory or nil
    end
    if not atlas and ts and ts.GetItemCraftedQualityInfo then
        local ok, info = pcall(ts.GetItemCraftedQualityInfo, link or itemID)
        atlas = ok and info and info.iconInventory or nil
    end
    if not atlas and ts and ts.GetItemCraftedQualityByItemInfo then
        -- Same fallback shape the action bars keep: a bare quality number,
        -- mapped through the probe.
        local ok, q = pcall(ts.GetItemCraftedQualityByItemInfo, link or itemID)
        if ok and type(q) == "number" and q >= 1 and q <= 5 then
            atlas = CdmQualityAtlasFor(q)
        end
    end
    if not atlas then
        if f._qualityHolder then f._qualityHolder:Hide() end
        -- Only settle on "no quality" once the item is actually known.
        if link then f._qualityItemID, f._qualityAtlas = itemID, false end
        return
    end
    f._qualityItemID, f._qualityAtlas = itemID, atlas

    local holder = f._qualityHolder
    if not holder then
        -- Own holder frame rather than a texture on f: the item frame's
        -- Cooldown is a CHILD frame, and a child draws above every texture of
        -- its parent whatever the draw layer, so a pip parented to f sits under
        -- the swipe. This is why the item count text is reparented to a text
        -- overlay too, and what the action bars' rank icon does.
        holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel((f:GetFrameLevel() or 1) + 18)
        holder:EnableMouse(false)
        f._qualityHolder = holder
        f._qualityTex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    local tex = f._qualityTex
    -- Unknown atlas reads as no pip, never as an error.
    if not pcall(tex.SetAtlas, tex, atlas, true) then
        f._qualityAtlas = false
        holder:Hide()
        return
    end
    -- Same proportion the action bars use (Blizzard centers the overlay 14,-14
    -- from the TOPLEFT of a 45px button), scaled to whatever size the bar runs.
    local sc = (f:GetWidth() or 36) / 36
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", holder, "TOPLEFT", 11 * sc, -11 * sc)
    tex:SetScale(sc)
    tex:Show()
    holder:Show()
end

-- ---------------------------------------------------------------------------
-- Dynamic potion display for every pot preset carrying a displayOrder (Light's
-- Potential, Potion of Recklessness, health). The preset icon resolves to the best
-- variant actually in bags (preset.displayOrder, best first) and shows THAT variant's
-- icon, exact bag count, and tooltip -- 2 Fleeting pots show "2" even with 50 regular
-- ones in the bank of another rank. With the profile-level "Swap Combat Potions
-- When Missing" toggle on, a preset whose own family is fully out of bags resolves the
-- partner families' chains instead. Identity is untouched (frame key, assigned-spell key,
-- saved settings and active states all stay on the preset's primary item; only the
-- DISPLAY resolves, so a running swipe survives the icon swapping variants).
-- Re-resolution is generation-gated: bag events, the options toggle, and profile
-- changes bump/miss the gate; steady-state 10Hz ticks cost one compare.
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
    -- families' appended IN swapWith ORDER while the swap toggle is on (list of
    -- keys; a plain string still works). Static data, built once per preset;
    -- the live toggle read just picks which cached list to return.
    function PotSwap.Chain(preset)
        if not chains then chains = {} end
        local c = chains[preset]
        if not c then
            c = { own = preset.displayOrder }
            local sw = preset.swapWith
            if sw then
                local keys = (type(sw) == "table") and sw or { sw }
                local both
                for k = 1, #keys do
                    local partner = PresetByKey(keys[k])
                    if partner and partner.displayOrder then
                        if not both then
                            both = {}
                            for i = 1, #preset.displayOrder do both[#both + 1] = preset.displayOrder[i] end
                        end
                        for i = 1, #partner.displayOrder do both[#both + 1] = partner.displayOrder[i] end
                    end
                end
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
            -- preset.icon is PICKER-ONLY art (the current-tier pot): every resolved
            -- variant, the primary included, paints its own item art so the icon
            -- always matches the counted/tooltipped variant.
            local icon = (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
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

-- True when this frame IS the preset rather than one specific variant of it.
-- The picker only ever stores -(preset.itemID), so a frame sitting on an ALT id
-- can only have come from the user typing that exact item id into Custom Item
-- ID -- they asked for that rank, not for the family.
-- Frames still carry _presetData either way: the preset icon and the keybind
-- fallback (which deliberately answers across ranks) want it. Only the
-- family-wide reads below are primary-only -- summing the family's bag counts
-- made a hand-added rank-2 pot report its rank-1 siblings as its own count,
-- point _itemCdSource at a sibling's cooldown and, with Hide Items if Missing
-- on, stay on the bar while the user owned none of it. Two such entries then
-- showed the same count off the same art (ranks share an icon), which reads as
-- one pot tracked twice. Mirrors PotSwap.Ensure's own primary check.
local function IsPresetFamilyFrame(f)
    local pd = f and f._presetData
    return (pd and pd.altItemIDs and f._presetItemID == pd.itemID) and true or false
end

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
-- Usability edges for the custom-spell resource tint (UniqueEvent:
-- client-coalesced to at most one fire per frame).
_racialCdListener:RegisterEvent("SPELL_UPDATE_USABLE")
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

-------------------------------------------------------------------------------
--  Per-bar "Suppress GCD" for EUI's OWN preset frames.
--
--  The setting is implemented as a hooksecurefunc on the cooldown's
--  SetSwipeColor (see DecorateFrame), which reaches BLIZZARD-owned CDM icons
--  only: Blizzard repaints their swipe colour as the cooldown state changes, so
--  the hook gets a chance to alpha-0 it. Preset frames (racials and user-added
--  custom spells) are painted by US -- swipe colour is written once at decorate
--  time and only GEOMETRY is driven afterwards -- so the hook never fires for
--  them and the GCD swipe stayed full alpha while the rest of the bar
--  suppressed it. EVERY place that drives a preset frame's SPELL cooldown must
--  call this right after pushing the geometry. ITEM-backed preset frames
--  (trinket slots, potion/item presets) deliberately do NOT route through here:
--  they drop the GCD out of the GEOMETRY with a dur > 1.5 test before
--  SetCooldown, so there's no GCD swipe to hide. cdInfo and barKey are optional
--  (callers that already hold them pass them in rather than paying for the
--  lookup twice); barKey must be passed by callers running BEFORE the frame's
--  cache entry is stamped.
-------------------------------------------------------------------------------
local function ApplyPresetGCDSwipe(f, sid, cdInfo, barKey)
    local cdF = f and f._cooldown
    if not (sid and cdF and cdF.SetSwipeColor) then return end
    if not barKey then
        local fc = _ecmeFC[f]
        barKey = fc and fc.barKey
    end
    local bd = barKey and barDataByKey[barKey]
    -- Per-spell Suppress GCD ORs into the bar toggle (bar ON = per-spell
    -- no-op); session-gated so unused installs never pay the resolve.
    local suppress = (bd and bd.suppressGCD) or false
    if not suppress and ns._cdmAnySuppressGcd then
        local ss = ns._ResolveCdmSS and ns._ResolveCdmSS(f)
        suppress = (ss and ss.suppressGCD) or false
    end
    local hide = false
    if suppress then
        if cdInfo == nil and C_Spell and C_Spell.GetSpellCooldown then
            cdInfo = C_Spell.GetSpellCooldown(sid)
        end
        if cdInfo and cdInfo.isOnGCD then
            -- Same charge carve-out as the hook: a charge spell mid-recharge is
            -- showing its RECHARGE, never a GCD, and alpha-0'ing that would
            -- blank the recharge for a whole GCD every time another ability is
            -- pressed. Read it from the stable charge data (maxCharges +
            -- isActive), never the secret currentCharges.
            -- Resolved through CdmChargeInfoFor so this copy cannot drift from
            -- the hook's answer; preset frames are ours rather than
            -- CooldownViewer items, so it falls back to the spellbook
            -- resolution for them.
            local ci = CdmChargeInfoFor(f, sid)
            hide = not (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true)
        end
    end
    -- Re-assert while suppressed rather than only on the rising edge: an
    -- appearance refresh repaints the swipe from bar data and would otherwise
    -- un-hide it until the next state change. The restore arm fires on the
    -- falling edge alone, so a frame we never suppressed keeps its own paint
    -- and nothing else is fought for ownership of the colour.
    local fd = FD(f)
    if hide then
        f._gcdSwipeHidden = true
        fd._isProcessingOverride = true
        cdF:SetSwipeColor(0, 0, 0, 0)
        fd._isProcessingOverride = false
    elseif f._gcdSwipeHidden then
        f._gcdSwipeHidden = nil
        fd._isProcessingOverride = true
        cdF:SetSwipeColor(0, 0, 0, (bd and bd.swipeAlpha) or 0.7)
        fd._isProcessingOverride = false
    end
end
ns.ApplyPresetGCDSwipe = ApplyPresetGCDSwipe

-- Dirty flag: high-frequency events (SPELL_UPDATE_COOLDOWN, BAG_UPDATE_COOLDOWN)
-- just set this flag; the BuffTicker (10Hz) processes it, coalescing dozens of
-- per-GCD events into a single update pass.
local _presetCdDirty = false
-- True when the last drain pass found every preset frame settled (no running
-- cooldown/desaturation/resource dim/shown charge text). While settled,
-- high-frequency noise events (SPELL_UPDATE_COOLDOWN fires steadily even at
-- idle) no longer arm the drain -- every settled->unsettled transition arrives
-- through the fast lanes (player cast, bag update, combat edges).
local _pcAllSettled = false

-- The actual update work, called from BuffTicker at 10Hz max.
local function ProcessPresetCooldowns()
    _presetCdDirty = false
    local anyUnsettled = false
    local now = GetTime()
    -- 5s full sweep: reads every spell-preset frame regardless of arms --
    -- the self-heal net for any missed arm edge (worst staleness = 5s,
    -- once). Between sweeps, ready un-armed frames are skipped entirely.
    local fullSweep
    if now >= (ns._pcFullNext or 0) then
        fullSweep = true
        ns._pcFullNext = now + 5
    end
    -- Iterate the LIVE set (shown drain-relevant frames only), not the
    -- session-cumulative _presetFrames reuse map -- see _RegisterPresetLive. The
    -- IsShown() belt is redundant by construction but costs one call per LIVE frame.
    for f in pairs(_pcActive) do
        if f:IsShown() then
            if (f._isRacialFrame or f._isCustomSpellFrame) and not f._isCustomBuffFrame then
                -- Cache extracted spellID on the frame to avoid regex every tick
                local sid = f._cachedPresetSID
                if not sid then
                    local m = f._pfKey and f._pfKey:match(":(%d+)$")
                    sid = m and tonumber(m)
                    f._cachedPresetSID = sid
                end
                -- Read-skip: a READY frame with no pending arm cannot have
                -- changed state -- every start edge arms it (cast/named/wave lanes
                -- set _cdPushArm, usability edges set _cdEvalArm), and the 5s sweep
                -- heals anything missed. Running frames (_lastOnRealCD ~= false,
                -- incl. never-read nil) and dimmed frames keep polling as the
                -- eventless ready-edge belt. A visible charge text no longer
                -- holds the frame in the poll: its count only moves on edges
                -- that arm (a cast unsettles the drain and its named events arm
                -- the exact frame; a charge regen completing while settled
                -- wakes via the listener's settled-state charge lane).
                if sid and (fullSweep or f._cdPushArm or f._cdEvalArm
                   or f._lastOnRealCD ~= false or f._lastVertexDim) then
                    local textArm = (fullSweep or f._cdPushArm or f._cdEvalArm) and true or nil
                    f._cdEvalArm = nil
                    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
                    local onRealCD = (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) and true or false
                    -- Push-on-edge: the swipe widget animates itself once armed,
                    -- so the duration object is re-pushed only when an event
                    -- lane armed it (cast, named/wave cooldown event, rebuild).
                    -- Belt: a state flip the lanes missed re-arms on this tick
                    -- (the old unconditional push had the same 10Hz latency).
                    if f._lastOnRealCD ~= onRealCD then
                        f._lastOnRealCD = onRealCD
                        f._cdPushArm = true
                        textArm = true
                    end
                    if f._cdPushArm then
                        f._cdPushArm = false
                        local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
                        if durObj and f._cooldown and f._cooldown.SetCooldownFromDurationObject then
                            f._cooldown:SetCooldownFromDurationObject(durObj, true)
                        end
                    end
                    if onRealCD then anyUnsettled = true end
                    -- Binary desat from the SAME readable bools this pass already
                    -- holds: the desat curve is a STEP (0->0, 0.001->1), so it
                    -- reduces to (onRealCD and 1 or 0). GCD-only stays saturated,
                    -- keep-color presets stay at 0, write is edge-gated;
                    -- ApplySpellDesaturation nils the memo on out-of-band writes (frame create/dirty path).
                    local desat = (onRealCD and not PresetKeepsColor(f)) and 1 or 0
                    if f._tex and f._lastDesatVal ~= desat then
                        f._lastDesatVal = desat
                        f._tex:SetDesaturation(desat)
                    end
                    -- Suppress GCD: this pass drives the geometry, so it also owns
                    -- hiding the swipe when that geometry is only a GCD.
                    ApplyPresetGCDSwipe(f, sid, cdInfo)
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
                    if f._lastVertexDim then anyUnsettled = true end
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
                            -- Render only on ARMED passes: the count moves only
                            -- on edges that arm (gate comment above). An armed
                            -- pass re-reads; an unarmed pass keeps the text --
                            -- and no longer blocks the drain from settling.
                            if textArm then
                                if not f._castCountText then
                                    f._castCountText = f:CreateFontString(nil, "OVERLAY")
                                    -- Match the bar's native stack/charge text styling
                                    -- (font, size, color, anchor, X/Y offset);
                                    -- RefreshCDMIconAppearance keeps it in sync afterwards.
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
                            end
                        elseif f._castCountText and f._castCountText:IsShown() then
                            f._castCountText:SetText("")
                            f._castCountText:Hide()
                            f._lastCastCount = nil
                        end
                    end
                end
            elseif f._isItemPresetFrame and f._presetItemID and now >= _encounterResetUntil
               -- Item read-skip (probe-proven capture #12: the item branch was the
               -- drain's entire remaining cost): a READY, un-armed, un-desaturated item
               -- frame cannot change state -- loot/bag edges arm it, lockout/desat keep
               -- it polling, an on-cd frame polls for its own expiry edge, and the 5s
               -- sweep heals anything missed.
               and (fullSweep or f._itemWalkArm ~= false or f._countArm ~= false
                    or f._inCombatLockout or f._lastDesat
                    or (f._cdStart and f._cdDur and now < f._cdStart + f._cdDur)) then
                -- Pot presets: re-resolve the display variant (generation-gated,
                -- one compare when nothing changed) and drive count/cooldown off
                -- the resolved chain. Every other item preset keeps the legacy
                -- primary-then-alts walk byte-identically.
                local dispID = PotSwap.Ensure(f)
                -- A variant flip moves the cooldown source: force a re-walk.
                if dispID ~= f._lastDispID then
                    f._lastDispID = dispID
                    f._itemWalkArm = true
                end
                -- Walk-on-edge: item cooldowns only move on BAG_UPDATE_COOLDOWN
                -- / cast / bag-content / encounter-reset edges, all of which arm
                -- the walk. Between edges the cached start/dur drives itemOnCD
                -- and the armed widget completes on its own (nil arm = first
                -- pass for this frame, walk once).
                if f._itemWalkArm ~= false then
                    f._itemWalkArm = false
                    local getContainerCD = C_Container and C_Container.GetItemCooldown
                    local start, dur
                    -- SINGLE-ID cooldown probe (user-directed model, the reference
                    -- watcher's shape): ownership picks ONE active id, re-pointed ONLY
                    -- on bag-CONTENT edges (PotSwap's resolver for pots, the count walk
                    -- below for the rest); cooldown events probe exactly that id. The
                    -- shared potion cd reports on every OWNED id, and after drinking
                    -- the LAST of a rank it lives on the id just used -- so the
                    -- last-OWNED id is remembered as the cd source while nothing is
                    -- owned. Cast-driven item-GCD noise (BAG_UPDATE_COOLDOWN fires per
                    -- ability press) now costs 1-2 calls instead of a dozen bag scans.
                    local probeID
                    if dispID then
                        if (f._displayCount or 0) > 0 then
                            f._lastOwnedDispID = dispID
                            probeID = dispID
                        else
                            probeID = f._lastOwnedDispID or dispID
                        end
                    else
                        probeID = f._itemCdSource or f._presetItemID
                    end
                    if getContainerCD then start, dur = getContainerCD(probeID) end
                    if not (start and dur and dur > 1.5) then start, dur = C_Item.GetItemCooldown(probeID) end
                    -- One-time seed per frame object: post-/reload a residual
                    -- cd can live on an id we have no memory of (used before
                    -- the reload, nothing owned now) -- find and remember it.
                    if not f._cdSeeded then
                        f._cdSeeded = true
                        if not (start and dur and dur > 1.5) then
                            local list = dispID and PotSwap.Chain(f._presetData)
                                or (f._presetData and f._presetData.altItemIDs)
                            if list then
                                for i = 1, #list do
                                    local cid = list[i]
                                    if cid ~= probeID then
                                        if getContainerCD then start, dur = getContainerCD(cid) end
                                        if not (start and dur and dur > 1.5) then start, dur = C_Item.GetItemCooldown(cid) end
                                        if start and dur and dur > 1.5 then
                                            if dispID then f._lastOwnedDispID = cid
                                            else f._itemCdSource = cid end
                                            break
                                        end
                                    end
                                end
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
                end
                local itemOnCD = f._cdStart and f._cdDur and (now < f._cdStart + f._cdDur)
                if itemOnCD or f._inCombatLockout then anyUnsettled = true end
                local total
                if dispID then
                    -- Exact count of the resolved variant only -- never a sum
                    -- across ranks/families (2 Fleeting shows 2, even with 50
                    -- regular rank 1s in the bags).
                    total = f._displayCount or 0
                    -- Consume the arm here too: resolving pots count via PotSwap
                    -- (_displayCount), so without this the read-skip gate saw pots as
                    -- count-armed FOREVER and never skipped them (probe capture #12).
                    f._countArm = false
                elseif f._countArm ~= false then
                    -- Count-on-edge: item counts only move with bag contents
                    -- (BAG_UPDATE_DELAYED) or a use-cast, both of which arm.
                    -- This content edge also re-points the single watched cd
                    -- id (f._itemCdSource): first owned id wins; while
                    -- nothing is owned the LAST owned id is kept (the shared
                    -- cd lives on the id that was just used).
                    f._countArm = false
                    total = C_Item.GetItemCount(f._presetItemID, false, true) or 0
                    local owned = total > 0 and f._presetItemID or nil
                    if total == 0 and IsPresetFamilyFrame(f) then
                        for _, altID in ipairs(f._presetData.altItemIDs) do
                            local c = C_Item.GetItemCount(altID, false, true) or 0
                            total = total + c
                            if not owned and c > 0 then owned = altID end
                        end
                    end
                    if owned then f._itemCdSource = owned end
                    f._cachedTotal = total
                else
                    total = f._cachedTotal or 0
                end
                if f._itemCountText then
                    local fc = _ecmeFC[f]
                    local bk = fc and fc.barKey
                    local bd = bk and barDataByKey[bk]
                    local showIC = not bd or bd.showItemCount ~= false
                    -- Show Item Count "Out of Combat" mode: this update path
                    -- force-Shows on count changes, so it must respect the
                    -- combat gate or it would re-show the text mid-combat.
                    if showIC and bd and bd.itemCountOOC and InCombatLockdown() then
                        showIC = false
                    end
                    -- Count shows for ANY owned stack, including the last
                    -- one; it hides only at 0 (where the desaturation below
                    -- already reads as "none left").
                    local displayCount = showIC and (total > 0) and total or nil
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
                do
                    -- Quality pip follows the variant actually being SHOWN: a pot
                    -- preset resolves its icon across ranks, so keying this on the
                    -- primary would label the icon with a rank it is not drawing.
                    local fc2 = _ecmeFC[f]
                    local bk2 = fc2 and fc2.barKey
                    local bd2 = bk2 and barDataByKey[bk2]
                    ApplyItemQualityPip(f, f._displayItemID or f._presetItemID,
                        bd2 and bd2.showItemQuality == true)
                end
                local shouldDesat = (total == 0 or itemOnCD or f._inCombatLockout) and true or false
                if shouldDesat ~= f._lastDesat then
                    f._lastDesat = shouldDesat
                    if f._tex then f._tex:SetDesaturated(shouldDesat) end
                end
            end
        end
    end
    _pcAllSettled = not anyUnsettled
    if QueueCustomBuffUpdate then QueueCustomBuffUpdate() end
end
ns._ProcessPresetCooldowns = ProcessPresetCooldowns
ns._isPresetCdDirty = function() return _presetCdDirty end
-- Setter so the inject path can request a preset desaturation re-evaluation. A
-- full rebuild wipes and re-injects preset frames with no cached desat state; if
-- no game event (bag/cooldown/combat) follows -- e.g. an in-panel sync/import --
-- ProcessPresetCooldowns would never run and an unowned item would stay saturated.
ns._MarkPresetCdDirty = function()
    _presetCdDirty = true
    _pcAllSettled = false
    if ns.ArmBuffTicker then ns.ArmBuffTicker() end
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
                    if total == 0 and IsPresetFamilyFrame(f) then
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

-- Readable plain number: payload ids can in principle be secret in combat;
-- comparing a secret throws, so an unreadable id is treated as absent.
local function _PlainNum(v)
    return type(v) == "number" and (not canaccessvalue or canaccessvalue(v))
end

_racialCdListener:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    -- Trailing flush for the loot-storm cap: a bag fire swallowed inside the
    -- window re-arms on the first event past it (combat noise makes that
    -- near-immediate; quiet worlds land on the next bag event or the sweep).
    if ns._pcBagPend and GetTime() >= (ns._pcBagNext or 0) then
        ns._pcBagPend = nil
        ns._pcBagNext = GetTime() + 0.5
        PotSwap.Bump()
        CheckItemPresenceForHide()
        for f in pairs(_pcActive) do
            if f._isItemPresetFrame then
                f._itemWalkArm = true
                f._countArm = true
            end
        end
        _presetCdDirty = true
        _pcAllSettled = false
        if ns.ArmBuffTicker then ns.ArmBuffTicker() end
    end
    -- Infrequent events: handle immediately and return
    if event == "BAG_UPDATE_DELAYED" then
        -- Loot-storm cap (probe-proven capture #12: mob-farming loot fires
        -- this in bursts, and each fire re-armed variant re-resolves + chain
        -- walks + bag-count scans -- the drain's dominant real cost). At
        -- most two re-arm cycles per second; a burst's trailing changes land
        -- on the next capped fire, the head flush, or the 5s sweep.
        local nowB = GetTime()
        if nowB >= (ns._pcBagNext or 0) then
            ns._pcBagNext = nowB + 0.5
            -- Bag contents changed: pot-preset display variants must re-resolve (before
            -- the presence check below, which reads the resolution).
            PotSwap.Bump()
            CheckItemPresenceForHide()
            -- Contents are the only thing that changes item counts, and a
            -- new stack can move the displayed cooldown source too: re-walk
            -- both. (Live set: hidden frames re-arm on their Show edge.)
            for f in pairs(_pcActive) do
                if f._isItemPresetFrame then
                    f._itemWalkArm = true
                    f._countArm = true
                end
            end
            _presetCdDirty = true
            _pcAllSettled = false
            if ns.ArmBuffTicker then ns.ArmBuffTicker() end
        else
            -- Swallowed by the cap: flush on the first event after the
            -- window (see the head of this handler).
            ns._pcBagPend = true
        end
        return
    end
    if event == "BAG_UPDATE_COOLDOWN" then
        -- THE item-cooldown edge: fires when any item cooldown starts, ends
        -- early or is modified. Re-walk the item chains on the next pass;
        -- between these edges the cached start/dur drives the display.
        -- (Live set: hidden frames re-arm on their Show edge.)
        -- SETTLED-GATED (measured 2026-08-16: this event fires ~0.7 Hz
        -- ambiently at idle with nothing cooling, and was the drain's -- and
        -- the buff ticker's -- dominant wake source): with every preset
        -- settled there is no running item cd to end or modify, and an item
        -- cd can only START via edges that own UNGATED lanes (player cast,
        -- bag content, equipment, encounter reset), so ambient chatter has
        -- nothing to report.
        if not _pcAllSettled then
            for f in pairs(_pcActive) do
                if f._isItemPresetFrame then f._itemWalkArm = true end
            end
            _presetCdDirty = true
            if ns.ArmBuffTicker then ns.ArmBuffTicker() end
        end
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
                    f._itemWalkArm = true
                end
            end
            _encounterResetUntil = GetTime() + 3
            _pcAllSettled = false
        end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
        local spellID = a3
        -- Fast lane: a player cast is the moment a preset cooldown can START, so it
        -- arms the drain AND resets its rate cap -- the swipe appears on the next tick.
        -- Pure SPELL_UPDATE_COOLDOWN noise (the catch-all below) coasts on the 1 Hz
        -- slow lane instead. Item presets re-walk (combat pots show instantly, ahead
        -- of BAG_UPDATE_COOLDOWN). Spell presets are deliberately NOT armed here:
        -- pushes exclude the GCD by construction (duration fetch passes ignoreGCD),
        -- so a cast pushes nothing visible on a ready frame, and the cast's OWN
        -- cooldown start arrives as a named SPELL_UPDATE_COOLDOWN in the same
        -- cascade, which the catch-all's payload discrimination arms precisely.
        for f in pairs(_pcActive) do
            if f._isItemPresetFrame then
                f._itemWalkArm = true
                f._countArm = true
            end
        end
        _presetCdDirty = true
        _pcAllSettled = false
        ns._pcLast = 0
        if ns.ArmBuffTicker then ns.ArmBuffTicker() end
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
            if f._isItemPresetFrame then
                if f._inCombatLockout then f._inCombatLockout = nil end
                f._itemWalkArm = true
            end
        end
        _presetCdDirty = true  -- refresh desaturation on combat end
        _pcAllSettled = false
        if ns.ArmBuffTicker then ns.ArmBuffTicker() end
        return
    end
    if event == "SPELL_UPDATE_USABLE" then
        -- Resource-tint edge: arm a READ of the custom-spell frames so the usability
        -- tint reacts without keeping ready frames in the poll. Same settled gate as
        -- the catch-all (today's contract: no drain work while settled), plus a 0.2s
        -- arm cap so usability churn can never re-arm passes beyond ~5/s.
        if not _pcAllSettled then
            local nowU = GetTime()
            if nowU >= (ns._pcUsableNext or 0) then
                ns._pcUsableNext = nowU + 0.2
                for f in pairs(_pcActive) do
                    if f._isCustomSpellFrame then f._cdEvalArm = true end
                end
                _presetCdDirty = true
                if ns.ArmBuffTicker then ns.ArmBuffTicker() end
            end
        end
        return
    end
    -- High-frequency events: arm the drain ONLY while something is in flight.
    -- When the last pass found every preset frame settled, this noise
    -- (SPELL_UPDATE_COOLDOWN/CHARGES fire steadily even at idle) would only
    -- schedule identical repaints -- every real settled->unsettled transition
    -- comes through the fast lanes above.
    if not _pcAllSettled then
        if event == "SPELL_UPDATE_COOLDOWN" then
            -- Payload discrimination (verified on both clients): a NAMED event
            -- re-arms the duration-object push only for the matching spell presets
            -- (id or base id -- CDR on a transform ticks the override, whose base id
            -- matches the tracked spell). A nil or unreadable id is a wave ("all
            -- cooldowns should be updated") and re-arms every spell preset. Frames
            -- with no extracted id yet arm conservatively.
            local sid, base = a1, a2
            local named = _PlainNum(sid)
            local baseOk = named and _PlainNum(base)
            for f in pairs(_pcActive) do
                if not f._isItemPresetFrame then
                    local fsid = f._cachedPresetSID
                    if not named or not fsid or fsid == sid
                       or (baseOk and fsid == base) then
                        f._cdPushArm = true
                    end
                end
            end
        elseif event == "SPELL_UPDATE_CHARGES" then
            -- Same discrimination for charge movement (charge customs).
            local sid = a1
            local named = _PlainNum(sid)
            for f in pairs(_pcActive) do
                if not f._isItemPresetFrame then
                    local fsid = f._cachedPresetSID
                    if not named or not fsid or fsid == sid then
                        f._cdPushArm = true
                    end
                end
            end
        end
        _presetCdDirty = true
        if ns.ArmBuffTicker then ns.ArmBuffTicker() end
    elseif event == "SPELL_UPDATE_CHARGES" and ns._cdmAnyCustomForceCount then
        -- Settled-state charge wake, shown charge texts ONLY: a charge regen
        -- completing is the one count edge that arrives with no cast and no
        -- unsettled state (a SPEND always rides a cast, which unsettles and
        -- lets the named lane above arm precisely). Named ids wake just the
        -- matching text; unreadable ids (instanced secrecy) wake every shown
        -- text, capped at one arm per 0.2s so charge chatter can never hold
        -- the settled drain awake.
        local nowC = GetTime()
        if nowC >= (ns._pcChargeNext or 0) then
            local sid = a1
            local named = _PlainNum(sid)
            local hit
            for f in pairs(_pcActive) do
                if f._isCustomSpellFrame and f._castCountText
                   and f._castCountText:IsShown()
                   and (not named or not f._cachedPresetSID
                        or f._cachedPresetSID == sid) then
                    f._cdEvalArm = true
                    hit = true
                end
            end
            if hit then
                ns._pcChargeNext = nowC + 0.2
                _presetCdDirty = true
                if ns.ArmBuffTicker then ns.ArmBuffTicker() end
            end
        end
    end
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
-- shared lust-buff listener stays armed even with no Tracking Bar lust bar present.
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
-- CD/utility frames that routed to one of our bars but whose spell could not be
-- resolved this pass (see the collect loop). "Unknown", NOT "rejected": the
-- Phase 4 sweep must leave these alone rather than park them offscreen.
local _scratch_unresolved = {}

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
-- Buff sort: the buff path sorts ENTRY objects (not frames), so each entry carries its
-- own sortOrder, stamped from the bar's assignedSpells order during Phase 2. Tiebreak
-- by Blizzard layoutIndex so buffs the user hasn't ordered keep their natural ordering.
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
    wipe(_scratch_unresolved)
    local allActiveFrames = _scratch_activeFrames
    local usedFrames = _scratch_usedFrames
    local unresolvedFrames = _scratch_unresolved

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
                                        -- Show When Missing (per-icon Always Show = "missing"):
                                        -- the ACTIVE buff renders hidden. The frame stays routed
                                        -- (decorations/lifecycle unchanged) but the layout drops
                                        -- it -- later icons close the gap -- and the opacity
                                        -- passes leave its alpha alone. OWN flag, deliberately
                                        -- NOT _cdStateHidden: the appearance-refresh stale
                                        -- cleanup clears that one on frames with no armed
                                        -- cd-state effect, which would ping-pong a relayout
                                        -- every refresh. Skipped under Keep Buffs in Same Place
                                        -- (every slot reserved; the options row is disabled
                                        -- there too).
                                        local missingMode = false
                                        if tbd and not tbd.hidePlaceholderIcon then
                                            local sdMV = ns.GetBarSpellData(targetBar)
                                            local ssMV = ns.ResolveSpellSettings(frame, displaySID, sdMV, targetBar)
                                            missingMode = (ssMV and ssMV.alwaysShow == "missing") and true or false
                                        end
                                        local fcMV = FC(frame)
                                        if missingMode then
                                            fcMV._missingActiveHidden = true
                                            frame:SetAlpha(0)
                                        elseif fcMV._missingActiveHidden then
                                            fcMV._missingActiveHidden = nil
                                        end
                                    end
                                    barSeen[dedupKey] = true
                                else
                                    -- This buff is DISPLAYED in the viewer but currently OFF
                                    -- (Blizzard pools the frame but hides it). Use the frame's
                                    -- LIVE resolved spell (GetSpellID) for icon/identity:
                                    -- cooldownInfo's override can point at a base spec spell with a
                                    -- generic icon (e.g. 137029 Holy Paladin) while GetSpellID is the
                                    -- real talent form the viewer shows (e.g. 432496 Holy Bulwark).
                                    -- GetSpellID can return SECRET on a live frame; type() reports
                                    -- "number" for a secret, so guard issecretvalue BEFORE the <= 0
                                    -- compare (order the short-circuit relies on), falling back to
                                    -- the clean cooldownInfo-resolved displaySID.
                                    local realSID = frame.GetSpellID and frame:GetSpellID()
                                    if type(realSID) ~= "number"
                                       or (issecretvalue and issecretvalue(realSID))
                                       or realSID <= 0 then
                                        -- Secret/unavailable read (instanced combat):
                                        -- prefer the clean per-form id cached from
                                        -- earlier unrestricted reads. Falling straight
                                        -- to displaySID collapses split-identity twins
                                        -- (Starweaver) onto the shared base spell: both
                                        -- placeholders get one icon AND one pooled
                                        -- frame key, so a slot vanishes in combat.
                                        realSID = (ns._cdmCleanSidByCDID and dedupKey
                                            and ns._cdmCleanSidByCDID[dedupKey])
                                            or displaySID
                                    elseif ns._cdmCleanSidByCDID and dedupKey then
                                        -- Inactive frame -> CLEAN GetSpellID. Prime the shared cache
                                        -- (keyed by cooldownID) so the custom-buff picker/preview
                                        -- can resolve this spell to its live form even later while
                                        -- the aura is ACTIVE (GetSpellID secret then). Done for ALL
                                        -- inactive buff frames, not just opted-in bars.
                                        -- Value-gated resGen bump: a clean-sid FLIP (form/talent
                                        -- change) alters buff resolution; steady re-primes do not.
                                        if ns._cdmCleanSidByCDID[dedupKey] ~= realSID then
                                            ns._cdmCleanSidByCDID[dedupKey] = realSID
                                            ns._cdmResGen = ns._cdmResGen + 1
                                        end
                                    end
                                    -- Always Show Buffs: draw OUR OWN placeholder icon for the
                                    -- inactive buff on the bar it routes to, when that bar has the
                                    -- toggle on. We never touch Blizzard's hidden frame, so nothing
                                    -- fights its hide state.
                                    local bd = barDataByKey[targetBar]
                                    -- Placeholder identity. Two viewer slots on one bar can
                                    -- resolve to the SAME realSID: for split-form talents that's
                                    -- correct (one live spell, one icon) and the dedup below must
                                    -- collapse them, but it's ALSO what a viewer-level COLLISION
                                    -- looks like (e.g. Blizzard hands the Demonic Art slot Diabolic
                                    -- Ritual's id, so unlike split-identity twins the clean-read
                                    -- cache above can't separate them either -- both reads return
                                    -- the same id). Keyed on realSID alone the second slot would be
                                    -- skipped and share the first's pooled frame, so the pair renders
                                    -- two icons while active and one while missing, with the bar's
                                    -- icon count swinging as buffs come and go. cooldownID is
                                    -- distinct per viewer slot (why the enumeration dedup moved onto
                                    -- it) -- the same identity rule arrives here: the FIRST claimer
                                    -- keeps the plain realSID key (non-colliding specs stay
                                    -- byte-identical), and only a later slot with a DIFFERENT cooldownID takes an id of its own instead of vanishing.
                                    local phIdent = realSID
                                    do
                                        local claimKey = "phsid:" .. tostring(realSID)
                                        local firstCD = barSeen[claimKey]
                                        if firstCD == nil then
                                            barSeen[claimKey] = dedupKey or true
                                        elseif dedupKey and firstCD ~= dedupKey then
                                            phIdent = "c" .. tostring(dedupKey)
                                        end
                                    end
                                    -- Effective Always Show for THIS buff: a per-icon override
                                    -- (ss.alwaysShow "on"/"off") beats the bar toggle, looked up
                                    -- only when per-icon settings exist on the bar (zero added
                                    -- cost otherwise). "Keep Buffs in Same Place"
                                    -- (bd.hidePlaceholderIcon) reuses the Always-Show placeholder
                                    -- path internally (mutually exclusive in the options); those
                                    -- placeholders are then rendered invisible by the alpha-0
                                    -- opacity passes. A HOSTED buff on a CD/util bar (CategorizeFrame
                                    -- only sends a buff frame to a non-buff bar for an explicit host)
                                    -- is treated as a CD/util icon: it ALWAYS reserves its slot, and
                                    -- its placeholder routes through the CD pipeline (Phase 3), not barLists.
                                    local hostCD = bd and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
                                    local showInactive = bd and (bd.showInactiveBuffIcons or bd.hidePlaceholderIcon) and true or false
                                    if hostCD then showInactive = true end
                                    -- Hosted "Visibility When Missing" (per-spell, BUFF family
                                    -- store; hosted entries never chain to bar tiers, so this can
                                    -- never come from Apply-to-Bar). Resolved via the pooled
                                    -- placeholder frame: its _isPlaceholderFrame flag routes the
                                    -- resolver to the buff store even when the real frame was
                                    -- never decorated this session (buff not yet active). nil =
                                    -- default desaturated placeholder (unchanged); "hidden" =
                                    -- inject but render alpha-0 (slot stays reserved);
                                    -- "hiddenShift" = skip the injection so later icons close the
                                    -- gap (HideAllPlaceholders at the top of every collect already
                                    -- hid the pooled frame -- same outcome as Hidden on CD (Shift Icons) for cooldowns).
                                    local hostedMissingVis
                                    if hostCD then
                                        local phMV = GetOrCreatePlaceholderFrame(targetBar, realSID, nil, phIdent)
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
                                            elseif ssAS.alwaysShow == "off" then showInactive = false
                                            -- Show When Missing: the missing state IS the
                                            -- placeholder state, so it forces injection like "on"
                                            -- (the active-state hide lives in the shown branch).
                                            elseif ssAS.alwaysShow == "missing" then showInactive = true end
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
                                        local phKey = "ph:" .. tostring(phIdent)
                                        if not barSeen[phKey] then
                                            barSeen[phKey] = true
                                            -- Paint the form the ACTIVE frame would show, so a
                                            -- replacing talent (Hellcaller's Wither) does not
                                            -- flip art as the aura comes and goes. Pooling and
                                            -- dedup stay keyed on realSID/phIdent.
                                            local dispSID = ResolvePlaceholderIconSID(realSID, dedupKey)
                                            local _GetTex = C_Spell and C_Spell.GetSpellTexture
                                            local icon = _GetTex and _GetTex(dispSID)
                                            if not icon and _GetTex and dispSID ~= realSID then
                                                icon = _GetTex(realSID)
                                            end
                                            local ph = GetOrCreatePlaceholderFrame(targetBar, dispSID, icon, phIdent)
                                            -- Per-spell missing-visibility mark (our own
                                            -- frame): "hidden" renders alpha-0 via the
                                            -- opacity passes while the slot stays
                                            -- reserved. nil for everyone else.
                                            ph._missingHidden = (hostedMissingVis == "hidden") or nil
                                            -- Mirror the viewer slot's position, and
                                            -- mirror "it has none" too: 0 is below every
                                            -- real layoutIndex, so a placeholder standing
                                            -- in for a not-yet-laid-out buff read as the
                                            -- left-most icon on the bar.
                                            ph.layoutIndex = frame.layoutIndex
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
                                -- STICKY equipment pin, BEFORE any spell resolution:
                                -- a worn on-use item's frame resolves its use-spell
                                -- after first use and would flip from the inert band
                                -- into a managed claim (then intake mirrors it and
                                -- the prune churns it back out). equipSlot identifies
                                -- the row by cdID alone, so the pin wins permanently.
                                local eqInfo = cdID and C_CooldownViewer
                                    and C_CooldownViewer.GetCooldownViewerCooldownInfo
                                    and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                                -- Consumable categories pin inert too (field-probed
                                -- 2026-08-14: potions/healthstones = 4/30), EXCEPT
                                -- 1711 = the racial category, the one category-row
                                -- class that must stay managed (settings/Remove/
                                -- routing). Unknown future categories fail safe:
                                -- inert render, unmanaged.
                                if eqInfo and (eqInfo.equipSlot
                                    or (eqInfo.spellCategoryID and eqInfo.spellCategoryID ~= 1711)) then
                                    if not cdFrames[barKey] then cdFrames[barKey] = {} end
                                    local frames = cdFrames[barKey]
                                    frames[#frames + 1] = frame
                                    local fc = FC(frame)
                                    fc.barKey = barKey
                                    fc.spellID = -(1000000000 + cdID)
                                    fc.isHostedBuff = nil
                                else
                                local displaySID, baseSID = ResolveFrameSpellID(frame)
                                if displaySID and displaySID > 0 then
                                    if not cdFrames[barKey] then cdFrames[barKey] = {} end
                                    local frames = cdFrames[barKey]
                                    frames[#frames + 1] = frame
                                    local fc = FC(frame)
                                    fc.barKey = barKey
                                    fc.spellID = baseSID or displaySID
                                    fc.isHostedBuff = nil
                                else
                                    -- Blizzard CDM "Items" (12.1): a category-driven
                                    -- entry (combat potions etc., category set 5/7)
                                    -- carries NO spell identity of its own -- only
                                    -- spellCategoryID, resolvable solely through the
                                    -- last-used source (secret-prone, empty until a
                                    -- first use). Claim it under the STABLE cd-claim
                                    -- marker so it routes/positions like any icon
                                    -- (Blizzard paints the frame's own art/cooldown);
                                    -- the identity never flips post-use. Unreachable
                                    -- for every pre-Items frame: those either resolve
                                    -- a spell or lack spellCategoryID entirely.
                                    local catInfo = cdID and C_CooldownViewer
                                        and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                                    -- Equipment-backed entries (equipSlot present) ride
                                    -- the INERT band alongside category shells: they
                                    -- render exactly as Blizzard tracks them -- art,
                                    -- cooldown and lifetime are all Blizzard's -- but
                                    -- carry NO manageable identity, so they never enter
                                    -- stores, settings, ordering or sync (the intake
                                    -- prune erases any mirror). The preset item lane is
                                    -- the MANAGED lane; a user tracking both sees both
                                    -- icons and removes whichever they prefer. Never
                                    -- re-key items onto slot ids: the managed-native
                                    -- arbitration that required was the 8.8.7 dupe bug.
                                    if catInfo and (catInfo.spellCategoryID or catInfo.equipSlot) then
                                        if not cdFrames[barKey] then cdFrames[barKey] = {} end
                                        local frames = cdFrames[barKey]
                                        frames[#frames + 1] = frame
                                        local fc = FC(frame)
                                        fc.barKey = barKey
                                        -- Identity band -(1000000000+cdID): unique
                                        -- per cooldownID, INERT by construction --
                                        -- int32-safe, so any spell API receiving it
                                        -- returns nothing instead of range-erroring
                                        -- (the cd-claim marker band exceeds int32
                                        -- and detonated in FindSpellOverrideByID),
                                        -- and outside every other marker band
                                        -- (item presets are small negatives, hosted
                                        -- markers start at -2000000000).
                                        fc.spellID = -(1000000000 + cdID)
                                        fc.isHostedBuff = nil
                                    else
                                        -- Routed to one of our bars, but the spell
                                        -- would not resolve: GetCooldownViewerCooldownInfo
                                        -- returns nil for a cooldownID while Blizzard is
                                        -- mid-rebuild (zone-in, PvP talents activating,
                                        -- a spec swap that just wiped the resolve memos).
                                        -- This frame is OURS and merely unidentified, so
                                        -- Phase 4 must not treat it like a deliberately
                                        -- unrouted one and park it at -10000 -- that is
                                        -- what empties the bars until a reload, since
                                        -- nothing re-collects afterwards.
                                        unresolvedFrames[frame] = true
                                    end
                                end
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
                                -- Per-spell Threshold Text (buff bars): attach the engine
                                -- countdown formatter so the custom buff's cast-timer countdown
                                -- shows decimals/a color change below its Threshold Seconds.
                                -- Gated (zero cost when unused); apply helper only touches
                                -- widgets it manages. nil frame: CDM context isn't set up yet
                                -- here, and a custom buff is an exact id (no variant), so the
                                -- direct family-store hit resolves without it (matches PlayPresetBuffGainSound).
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
                                        if total == 0 and IsPresetFamilyFrame(f) then
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

                -- Duration text follows the bar's Cooldown Text toggle even
                -- under Only Show Numbers (hide duration = stacks only).
                local hideCD = not ns.CdmDurationTextOn(barData)
                -- FocusKick icon alpha is owned exclusively by
                -- SetFocusKickAlpha; skip the per-icon alpha override here
                -- so CollectAndReanchor doesn't clobber the nameplate-driven
                -- visibility state with a stale _visHidden flag.
                local isFocusKickBar = (barKey == ns.FOCUSKICK_BAR_KEY)

                for _, entry in ipairs(list) do
                    count = count + 1
                    local frame = entry.frame
                    usedFrames[frame] = true
                    -- FC identity BEFORE DecorateFrame: the decorate path resolves
                    -- per-spell settings (custom icon, active border) through
                    -- fc.spellID. The bar-rebuild icon-state reset nils fc.spellID, so
                    -- decorating first left the LAST login reanchor with no identity:
                    -- the custom icon failed to resolve, its restore branch disarmed,
                    -- and the real icon stood until the next aura-driven reanchor.
                    local efc = FC(frame)
                    efc.barKey = barKey
                    efc.spellID = entry.baseSpellID or entry.spellID
                    DecorateFrame(frame, barData)
                    icons[count] = frame
                    -- Only Show/alpha frames Blizzard considers active.
                    -- Hidden frames are collected for data (assignedSpells)
                    -- but left visually untouched so we don't override
                    -- Blizzard's "hide when inactive" state machine.
                    -- Our own (unprotected) placeholder frames own their mouse state
                    -- here, at the point they are injected: a freshly pooled one is
                    -- born mouse-enabled and may never see a visibility pass before
                    -- the cursor reaches it. Same rule ApplyCDMTooltipState uses, plus
                    -- the alpha-0 exclusion, so flipping "Keep Buffs in Same Place"
                    -- back off restores capture on the next collect instead of latching.
                    if frame._isPlaceholderFrame and frame.EnableMouseMotion then
                        frame:EnableMouseMotion((barData.showTooltip
                            and not (container and container._mouseTrack)
                            and not ns.IsPlaceholderRenderHidden(frame, barData)) and true or false)
                    end
                    if frame:IsShown() and not isFocusKickBar then
                        local barHidden = container and container._visHidden
                        local fcH = _ecmeFC[frame]
                        if not (fcH and (fcH._cdStateHidden or fcH._missingActiveHidden)) then
                            -- Hide Icon: an Always-Show placeholder still reserves its
                            -- layout slot (it stays shown + decorated + positioned) but
                            -- renders fully invisible -- icon, border and background --
                            -- via frame alpha 0. The same check is mirrored in the two
                            -- other per-icon opacity passes (_CDMApplyVisibility and
                            -- ApplyBarOpacity) so none of them paint over it.
                            if ns.IsPlaceholderRenderHidden(frame, barData) then
                                frame:SetAlpha(0)
                            else
                                frame:SetAlpha(barHidden and 0 or ns.EffectiveBarAlpha(barData))
                            end
                        end
                    end
                    -- Ensure stack/charge text stays above our border overlay. Blizzard
                    -- resets frame levels on pooled frames during zone transitions;
                    -- re-raise cheaply here every collect pass. Use relative levels so
                    -- cursor-anchored bars (level 9980+) keep text above their icons.
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
                        -- Kind-gated so unchanged passes touch nothing; the value
                        -- is the EFFECTIVE direction (kind baseline flipped by
                        -- per-spell Reverse Swipe), never the bare kind, or this
                        -- re-assert undoes the setting.
                        local efdR = hookFrameData[frame]
                        local revB = ns.EffectiveReverseSwipe(frame, barKey, true)
                        if efdR and efdR._revKind ~= revB then
                            efdR._revKind = revB
                            frame.Cooldown:SetReverse(revB)
                        end
                        frame.Cooldown:SetHideCountdownNumbers(hideCD)
                    end
                end

                -- Mark this bar's frames as used BEFORE the excess-clear below, so the
                -- clear can tell a stale tail slot from a still-claimed frame.
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

    -- Pre-build claim set for racial/custom spell checks: collect all spellIDs already
    -- claimed by Blizzard frames across all bars. This replaces the O(frames *
    -- FindSpellOverrideByID) inner loop with a set lookup.
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

                -- Spell order map: cached per-bar, rebuilt only when spells change
                -- (spec swap, talent change, user edits). During combat rotation, the
                -- assigned list is static so the cache hit rate is ~100%. hasCdKeys:
                -- this bar holds at least one cd-claim slot, so the sort probe below
                -- must check cooldownID. Cached alongside the maps -- the cache-hit
                -- path never re-walks the list.
                local spellOrder, hostedOrder, hasCdKeys
                if not ns._spellOrderDirty and container._cachedSpellOrder then
                    spellOrder = container._cachedSpellOrder
                    hostedOrder = container._cachedHostedOrder
                    hasCdKeys = container._cachedSpellOrderCdKeys
                else
                    if not container._cachedSpellOrder then container._cachedSpellOrder = {} end
                    if not container._cachedHostedOrder then container._cachedHostedOrder = {} end
                    spellOrder = container._cachedSpellOrder
                    hostedOrder = container._cachedHostedOrder
                    hasCdKeys = false
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
                                    -- Cd-claim marker (collided-buff slot hosted on
                                    -- this CD/util bar, -(CD_CLAIM_MARKER_BASE+cdID)):
                                    -- rank it by the stable "c"..cooldownID key, the
                                    -- same convention the buff-family order loop and
                                    -- ResolveBuffDisplaySortIndex use. Keying by the
                                    -- marker value matched no frame, so the slot fell
                                    -- through to spillover and sorted by Blizzard
                                    -- layoutIndex -- reordering it did nothing.
                                    local cdClaim = ns.CdClaimMarkerToCdID and ns.CdClaimMarkerToCdID(sid)
                                    if cdClaim then
                                        local ckey = "c" .. cdClaim
                                        if not spellOrder[ckey] then spellOrder[ckey] = idx end
                                        hasCdKeys = true
                                    else
                                        if not spellOrder[sid] then spellOrder[sid] = idx end
                                        -- Resolve override/base forms only for a REAL
                                        -- spellID. sid can still be an item/slot marker
                                        -- here (negative): FindSpellOverrideByID errors
                                        -- outright on an out-of-range id, and a marker
                                        -- has no override/base anyway. Same sid>0 guard
                                        -- the sibling order loops use; this branch was
                                        -- missed once already, which threw every
                                        -- RefreshLayout and broke CDM.
                                        if sid > 0 then
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
                    end
                    container._cachedSpellOrderCdKeys = hasCdKeys
                end

                -- Inject custom frames (trinkets, items, racials)
                if spellList then
                    -- Items already represented by an equipment-slot entry on this bar.
                    -- The slot frame renders whatever is equipped there, so injecting
                    -- the same item's preset frame too would show one physical item
                    -- twice -- classic case: a legacy custom-item belt entry plus a
                    -- slot entry appended at the bar's end by an add or an RPT sync.
                    -- The item entry stays in the data and renders again the moment the
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
                        if sid and ((ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid))
                                 or (ns.CdClaimMarkerToCdID and ns.CdClaimMarkerToCdID(sid))) then
                            -- Hosted-buff OR cd-claim (collided-buff slot) marker: the
                            -- buff renders via the reparent/diversion path (route map ->
                            -- cdFrames), never as an injected custom frame. Must be tested
                            -- before the item-preset branch: both marker kinds are also
                            -- <= -100, so -sid would otherwise be taken as an itemID and
                            -- fed to GetItemCooldown, which errors outside int32 range
                            -- (cd-claim markers are -(CD_CLAIM_MARKER_BASE + cooldownID)).
                        elseif sid and ns.SlotIDFromKey(sid) and _globalClaimSet[sid] then
                            -- Native-first, injection-fallback (the racial rule
                            -- below, applied to equipment): Blizzard's own cooldown
                            -- for this slot is live and claimed under this same slot
                            -- key, so it renders the slot and our frame stands down.
                            -- One physical trinket, one icon.
                            local tfN = _trinketFrames[ns.SlotIDFromKey(sid)]
                            if tfN then tfN:Hide() end
                        elseif sid and ns.SlotIDFromKey(sid) then
                            -- Equipment slot (trinkets -13/-14, user-added slots)
                            local slot = ns.SlotIDFromKey(sid)
                            local tf = _trinketFrames[slot]
                            if not tf then tf = GetOrCreateTrinketFrame(slot) end
                            -- Re-decorate (icon, use spell, tooltip scan) only when the
                            -- equipped item changed or an earlier scan was inconclusive;
                            -- a plain re-anchor keeps the decoration and only drops the
                            -- cooldown push memo so the next event re-derives desaturation.
                            local itemID = GetInventoryItemID("player", slot)
                            if itemID ~= _trinketItemCache[slot]
                               or (itemID and tf._trinketIsOnUse == nil) or tf._slotScanPending then
                                UpdateTrinketFrame(slot)
                            else
                                tf._cdMemoStart, tf._cdMemoDur = nil, nil
                            end
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
                            -- Skip when a slot entry on this bar already shows this
                            -- exact item (see slotEquippedItems above); the orphan
                            -- sweep hides any frame from a previous pass.
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
                                        if total == 0 and IsPresetFamilyFrame(f) then
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
                                -- FRAMES AS TRUTH (native-first, injection-fallback): a racial
                                -- with a LIVE Blizzard frame anywhere is a regular native
                                -- cooldown -- hasClaim above already skipped it, and the route
                                -- map delivers it to whichever bar lists it. Reaching here
                                -- means NO live frame exists (untracked in Blizzard's CDM, or
                                -- a client without native racial tracking), so our custom
                                -- frame is the only way the racial renders at all. The old
                                -- gate here keyed on IsSpellKnownInCDM, which reads the
                                -- category set -- its second arg is allowUnlearned (docs), so
                                -- "known" means LEARNED, not tracked: a racial the user
                                -- untracked in Blizzard's CDM stayed "known", skipped
                                -- injection, and vanished from every bar (field report).
                                -- Login timing: viewer data can load after our first build
                                -- (hasClaim transiently false -> we inject); the
                                -- COOLDOWN_VIEWER_DATA_LOADED rebuild re-evaluates and the
                                -- reanchor sweep hides the then-stale injected frame.
                                if not isRacial and not isCustomSpell then
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
                                        _RegisterPresetLive(f, fkey)
                                    end
                                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                                    if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                                    if not f._cdSet or f._racialCdDirty then
                                        local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
                                        if durObj and f._cooldown.SetCooldownFromDurationObject then
                                            f._cooldown:SetCooldownFromDurationObject(durObj, true)
                                        end
                                        ApplySpellDesaturation(f, durObj)
                                        -- This push can land mid-GCD (a bar rebuild
                                        -- while a GCD is running), so it owns the
                                        -- swipe the same way the 10Hz pass does.
                                        -- barKey is passed explicitly: the frame's
                                        -- cache entry is only stamped further down.
                                        ApplyPresetGCDSwipe(f, sid, nil, barKey)
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
                -- spell is in assignedSpells gets its integer slot index; a frame that
                -- is NOT (spillover, e.g. a cooldown a talent swap just added that the
                -- user has never ordered) is marked here and positioned in the second
                -- pass below by Blizzard's native layoutIndex, ADJACENT to the assigned
                -- Blizzard spells around it instead of dumped at the bar's end -- this
                -- keeps a re-talented cooldown in its CDM position rather than piling
                -- new spells after a trinket/racial slot.
                local hasSpill = false
                -- Identity probe shared by both member kinds. The first 4 probes key
                -- off fc.spellID = cooldownInfo.spellID (the base) and bridge
                -- base<->override. For some hero-talent slots that base is an
                -- UNRELATED spell to the DISPLAYED/castable form the picker actually
                -- stored (e.g. a Wither slot whose cooldownInfo base is Immolate), so
                -- the frame's displayed identity (the same GetCanonicalSpellIDForFrame
                -- id the add path wrote) is matched too, so a placed cooldown finds its
                -- saved rank instead of being mistaken for a brand-new spillover.
                local function OrderKeyFor(frame, fc, sid, map)
                    if not map then return nil end
                    -- Cd-claimed collided-buff slot: both frames of the pair share
                    -- one spellID, so every probe below would match the same rank
                    -- (or none). cooldownID is unique per slot -- check it first,
                    -- same stable-key convention as ResolveBuffDisplaySortIndex.
                    -- Skipped outright (no concat) on bars holding no claim.
                    if hasCdKeys then
                        local cd = frame and frame.cooldownID
                        if type(cd) == "number" then
                            local ckey = map["c" .. cd]
                            if ckey then return ckey end
                        end
                    end
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
                            -- Remember where this frame last sorted before the
                            -- marker overwrites it. The interpolation below needs
                            -- a fallback that holds position rather than guessing
                            -- when Blizzard has not laid the viewer out yet. Stamp
                            -- the cooldownID it belonged to: viewer frames are
                            -- POOLED, so the same frame hosts a different spell
                            -- after a preset switch and "where this frame sat"
                            -- would otherwise hand the new spell the old one's slot.
                            if type(fc.sortOrder) == "number" then
                                fc.lastSortOrder = fc.sortOrder
                                fc.lastSortOrderCdID = frame.cooldownID
                            end
                            fc.sortOrder = false  -- spillover marker, resolved below
                            hasSpill = true
                        end
                    end
                end

                -- Second pass (only when a spillover exists -- steady state skips this
                -- entirely). Give each spillover a fractional key that lands it between
                -- its neighbours by Blizzard layoutIndex. Anchors are the present,
                -- assigned frames: a real viewer frame anchors at its OWN layoutIndex;
                -- a frame we inject (trinket/pot/racial, or a hosted-buff placeholder --
                -- no layoutIndex of its own in this viewer's space) anchors at an
                -- INTERPOLATED layoutIndex derived from its nearest present Blizzard
                -- neighbour in slot order.
                -- Without preset anchors the sort can't see them, so a re-talented
                -- cooldown parked to the LEFT of a preset could hop to its RIGHT (and
                -- vice versa); with them, the spillover lands on the correct side.
                if hasSpill then
                    -- Blizzard viewer anchors: real layoutIndex, keyed by slot index,
                    -- GROUPED BY SOURCE VIEWER. layoutIndex numbers a frame inside one
                    -- viewer's pool, so indices from two viewers share a scale only by
                    -- accident. A mixed bar (a hosted buff off the buff viewer sitting
                    -- among cooldowns off the essential viewer) compared them anyway,
                    -- and whichever way that comparison fell decided where an unplaced
                    -- spell landed -- including in front of everything.
                    local blizzKeys, blizzLIs
                    for _, frame in ipairs(frames) do
                        local fc = _ecmeFC[frame]
                        local k = fc and fc.sortOrder
                        -- layoutIndex must be REAL to anchor anything. It used to
                        -- fall back to 0, which is below every true layoutIndex, so
                        -- an anchor that had not been laid out yet became a valid
                        -- predecessor for every spillover -- and during a full
                        -- relayout, when they all collapse to 0, the interpolation
                        -- degenerates to "after whichever anchor came first". An
                        -- anchor we cannot place is not an anchor; dropping it just
                        -- narrows the anchor set, and an empty set already has a
                        -- defined meaning (spillovers fall to the tail). A frame with
                        -- no viewer of its own (our injected placeholders, which carry
                        -- the viewer slot's cooldownID) is dropped for the same reason:
                        -- its layoutIndex is borrowed from another index space.
                        if type(k) == "number" and frame.cooldownID ~= nil
                           and frame.layoutIndex and frame.viewerFrame then
                            blizzKeys = blizzKeys or {}; blizzLIs = blizzLIs or {}
                            local vKeys = blizzKeys[frame.viewerFrame]
                            if not vKeys then
                                vKeys = {}
                                blizzKeys[frame.viewerFrame] = vKeys
                                blizzLIs[frame.viewerFrame] = {}
                            end
                            vKeys[#vKeys + 1] = k
                            blizzLIs[frame.viewerFrame][#vKeys] = frame.layoutIndex
                        end
                    end
                    -- Full anchor set = Blizzard anchors + preset anchors (interpolated
                    -- layoutIndex), built once PER VIEWER: a preset we inject has no
                    -- layoutIndex of its own, so it can only be placed inside the index
                    -- space it is being measured against. minAnchorIdx (over that
                    -- viewer's anchors) is where a spillover that sorts before
                    -- everything lands. Skipped entirely when the bar has no present
                    -- Blizzard spell to interpolate against (no anchors -> spillovers
                    -- fall to the tail by layoutIndex, as before).
                    local anchorKeys, anchorLIs, minAnchorIdx
                    if blizzKeys then
                        anchorKeys, anchorLIs, minAnchorIdx = {}, {}, {}
                        for viewer, bKeys in pairs(blizzKeys) do
                            local bLIs = blizzLIs[viewer]
                            local aKeys, aLIs = {}, {}
                            anchorKeys[viewer] = aKeys; anchorLIs[viewer] = aLIs
                            for i = 1, #bKeys do
                                aKeys[i] = bKeys[i]; aLIs[i] = bLIs[i]
                                if not minAnchorIdx[viewer] or bKeys[i] < minAnchorIdx[viewer] then
                                    minAnchorIdx[viewer] = bKeys[i]
                                end
                            end
                            for _, frame in ipairs(frames) do
                                local fc = _ecmeFC[frame]
                                local k = fc and fc.sortOrder
                                -- Ours, not the viewer's: trinkets, pots and racials
                                -- (no cooldownID) and hosted-buff placeholders (which
                                -- carry one). Neither owns a layoutIndex in THIS
                                -- viewer's space, so both are interpolated into it.
                                if type(k) == "number" and not frame.viewerFrame then
                                    -- Nearest present Blizzard anchor on each side (slot order).
                                    local leftLI, leftSlot, rightLI, rightSlot
                                    for i = 1, #bKeys do
                                        local bslot = bKeys[i]
                                        if bslot < k then
                                            if not leftSlot or bslot > leftSlot then leftSlot = bslot; leftLI = bLIs[i] end
                                        elseif bslot > k then
                                            if not rightSlot or bslot < rightSlot then rightSlot = bslot; rightLI = bLIs[i] end
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
                                        aKeys[#aKeys + 1] = k
                                        aLIs[#aKeys] = effLI
                                        if not minAnchorIdx[viewer] or k < minAnchorIdx[viewer] then
                                            minAnchorIdx[viewer] = k
                                        end
                                    end
                                end
                            end
                        end
                    end
                    for _, frame in ipairs(frames) do
                        local fc = _ecmeFC[frame]
                        if fc and fc.sortOrder == false then
                            -- Only this frame's OWN viewer can measure it.
                            local aKeys = anchorKeys and frame.viewerFrame
                                          and anchorKeys[frame.viewerFrame]
                            if aKeys and frame.cooldownID ~= nil
                               and frame.layoutIndex then
                                local aLIs = anchorLIs[frame.viewerFrame]
                                local L = frame.layoutIndex
                                local predIdx, predLI
                                for i = 1, #aKeys do
                                    local li = aLIs[i]
                                    if li < L and (not predLI or li > predLI) then
                                        predLI = li; predIdx = aKeys[i]
                                    end
                                end
                                -- Insert after the predecessor slot (or before the first
                                -- anchor when below all). (L+1)/1e6 < 1 keeps the
                                -- spillover strictly between its neighbouring integer
                                -- slots and never ties its predecessor.
                                local baseIdx = predIdx
                                    or ((minAnchorIdx[frame.viewerFrame] or 1) - 1)
                                fc.sortOrder = baseIdx + ((L + 1) / 1e6)
                            elseif frame.cooldownID ~= nil and not frame.layoutIndex then
                                -- Blizzard has not assigned this frame a layout
                                -- position yet: it re-lays the viewer out on a
                                -- preset switch, an addon update and at login,
                                -- which is exactly when this was reported.
                                -- `layoutIndex or 0` used to stand in here, and 0
                                -- is below every real layoutIndex, so the frame
                                -- landed before every anchor -- a tracked spell
                                -- silently jumping to FIRST place while
                                -- Blizzard's own order was never wrong.
                                -- Hold the last known position instead; the next
                                -- pass, once the layout exists, places it properly.
                                -- Only while the frame still hosts the SAME
                                -- cooldown: a preset switch re-seats the pool, and
                                -- the held position belongs to the spell that sat
                                -- here before, not to this one.
                                local held = (fc.lastSortOrderCdID == frame.cooldownID)
                                             and fc.lastSortOrder or nil
                                fc.sortOrder = held or 99999
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
                        -- No-op rule: never divert while any member of this bar has a
                        -- Shift Icons cooldown-state effect (the shift filter changes
                        -- the effective count on a faster, independent cadence than
                        -- this pass). Two stages: the frame-less assignedSpells scan,
                        -- then a frame-scoped walk of the live list -- spillover frames
                        -- (not in assignedSpells) and alias-keyed settings are only
                        -- visible to the same resolution the live shift driver uses, so
                        -- the check and the driver can never disagree.
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

                local hideCDText = not ns.CdmDurationTextOn(barData)
                for i, frame in ipairs(frames) do
                    usedFrames[frame] = true
                    DecorateFrame(frame, barData)
                    icons[i] = frame
                    if not isFKBar then
                    local fcH = _ecmeFC[frame]
                    -- Hosted "Visibility When Missing: Hidden": the placeholder keeps
                    -- its reserved layout slot but renders fully invisible. The flag is
                    -- nil for everyone else (original branch below unchanged).
                    if frame._missingHidden and frame._isPlaceholderFrame then
                        frame:SetAlpha(0)
                    elseif not (fcH and (fcH._cdStateHidden or fcH._missingActiveHidden)) then
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
                        -- previous life. Kind-gated so unchanged passes touch
                        -- nothing; the value is the EFFECTIVE direction (kind
                        -- baseline flipped by per-spell Reverse Swipe), never the
                        -- bare kind, or this re-assert undoes the setting.
                        local fdRv = hookFrameData[frame]
                        local fcRv = _ecmeFC[frame]
                        local wantRev = ((fcRv and fcRv.isHostedBuff)
                            or (fdRv and fdRv._isBuffViewerFrame)
                            or frame._isPlaceholderFrame) and true or false
                        wantRev = ns.EffectiveReverseSwipe(frame, barKey, wantRev)
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

                -- Change detection (mirrors Phase 2 buff bars): skip the expensive
                -- Refresh/Layout/Tooltip calls when the icon set is identical to the
                -- previous reanchor. During rotation spam, OnCooldownIDSet fires per
                -- spell cast and queues a reanchor at the 0.2s throttle; the vast
                -- majority of those reanchors produce the exact same icon list and
                -- don't need the full layout pipeline re-run.
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
    --  Also protect any frame currently in cdmBarIcons (may be from a previous
    --  reanchor cycle but still visually active) -- but ONLY for bars still in
    --  the active profile. A profile swap removing a bar leaves its old icons in
    --  cdmBarIcons (FullCDMRebuild doesn't wipe icon arrays here), and protecting
    --  those would shield a stale persistent _trinketFrames trinket (which,
    --  unlike _presetFrames racials, FullCDMRebuild never hides) from the
    --  unused-frame sweep below, leaving it floating after its bar is gone.
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
    -- Only protect NEVER-CLAIMED unresolved frames while the retry budget below
    -- still has passes left. Once it is spent, a frame that has never been ours
    -- and still will not resolve is no longer plausibly transient (a stale pool
    -- entry with a dead cooldownID), and parking it is right again -- otherwise
    -- it would sit at Blizzard's own Edit Mode position forever, which is the
    -- "CDM looks scrambled" face of this bug rather than the "CDM is empty" one.
    local protectUnresolved = (ns._cdmUnresolvedRetries or 0) < 3
    for frame in pairs(allActiveFrames) do
        if usedFrames[frame] then
            -- Claimed: leave alone
        elseif unresolvedFrames[frame]
               and (protectUnresolved
                    or (_ecmeFC[frame] and _ecmeFC[frame].barKey)) then
            -- Unknown, not rejected: identification failed this pass, so we
            -- have no basis to park it. Leave it exactly as it is and let the
            -- re-collect scheduled at the end of this function claim it once
            -- the cooldown-viewer API answers again.
            --
            -- fc.barKey means we HAVE claimed this frame before, and that
            -- exemption never expires. ScheduleTalentRebuild wipes resolvedSid
            -- and cachedCdID but deliberately not barKey, so it survives the
            -- exact rebuild that strips the resolve memos -- which is the zone
            -- transition where the API answers nil for longer than any fixed
            -- retry budget can cover. A frame that was on a bar a moment ago
            -- and is momentarily unidentifiable is transient by definition, and
            -- parking it is what turns a working CDM blank. Note this cannot
            -- strand a genuinely retired frame: one whose spell was unassigned
            -- or ghosted RESOLVES fine and simply routes nowhere, so it never
            -- reaches this branch at all.
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
                -- Alpha-hide AND park offscreen -- never Hide on Blizzard pool frames.
                -- Hiding a pool frame signals Blizzard that the pool is stale, which
                -- triggers a full viewer rebuild. Spells that continuously transform
                -- (e.g. Lightsmith Holy Armaments) cause Blizzard to rebuild every
                -- tick; if we Hide here, we amplify that into an infinite rebuild loop.
                --
                -- The park matters as much as the alpha: a frame that was claimed by
                -- the PREVIOUS spec still holds its points on that spec's bar (e.g. a
                -- druid-wide spell assigned on Resto but ghosted on Guardian), and the
                -- engine re-raises item alpha through paths no hook can see
                -- (SetAlphaFromBoolean, alpha animations) on cooldown/aura state
                -- changes such as form swaps -- resurrecting the icon pinned to the old
                -- bar. Parked offscreen (immediately re-pointed, so the rect stays
                -- valid), every alpha path is harmless. The SetPoint hook re-parks it
                -- if Blizzard's layout moves it while unclaimed; a re-claim SetPoints
                -- absolutely, so recovery is total.
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

    -- Hide orphaned custom frames (trinkets, potions, racials, custom spells) no longer
    -- referenced by any bar. Custom frames are never added to allActiveFrames (that
    -- table only holds Blizzard viewer pool frames), so the main Phase 4 loop above
    -- can't see them. The common case: a spec swap where the new spec has fewer custom
    -- items than the old. Phase 3's write loop overwrites cdmBarIcons[barKey][i] in
    -- place, silently losing the reference to the previous frame at that index without
    -- hiding it -- the "clear excess" loop only handles trailing indices (i >
    -- #newFrames), so a custom frame at index 1 in the old list gets overwritten and
    -- leaks (stays shown, still parented to the bar container, its stale SetPoint
    -- anchor drifting with the container on the new layout). Trinket frames are the
    -- most obvious offender since _trinketFrames is persistent across spec swaps
    -- (unlike _presetFrames, wiped in FullCDMRebuild); preset frames get the same
    -- belt-and-suspenders sweep for any other removal path that skips
    -- FullCDMRebuild. Custom BUFF frames (f._isCustomBuffFrame) are skipped:
    -- their lifecycle lives in UpdateCustomBuffBars on a separate ticker, and
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

    -- Per-spec migration: convert pre-refactor "assignedSpells as content filter"
    -- data into "ghost-bar diversion" data. Must run AFTER reanchor because it
    -- walks the live viewer pools, populated by Blizzard's CDM only after our
    -- init code runs -- the first completed reanchor for a spec is the earliest
    -- moment the pools are guaranteed to have content. Per-spec flag inside the
    -- migration makes this call a no-op for already-migrated specs; after a
    -- successful migration, rebuild the route map (new ghost entries become
    -- diversions) and queue another reanchor (now-ghost-routed frames move out of the default bars).
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
        -- Automatic base-bar materialization (once per spec+layout per session):
        -- untouched default-bar spells render through the frames-as-truth fallback
        -- without ever being recorded in assignedSpells, so export strings shipped
        -- incomplete stores and the import ghost pass hid exactly those spells on
        -- every recipient. Reseed from the live icons -- ONLY after the one-shot
        -- migration has stamped (a legacy un-migrated store must migrate first or
        -- old-model spillovers would materialize), never while an import's
        -- ghosting is pending (Reseed self-guards too), and buff-family bars
        -- excluded (cdUtilOnly: picker-authoritative). The session flag is wiped
        -- on talent/loadout changes so newly learned spells re-materialize,
        -- and on Blizzard settings-panel close (in-place layout edits). Keyed
        -- by spec + active Blizzard layout id: a spell tracked only on a
        -- layout switched to later in the session must still get its pass.
        if ns.ReseedAssignedSpellsFromLiveIcons and prof
           and prof._barFilterModelV6 and not prof._importGhostMode then
            ns._reseededSpecsSession = ns._reseededSpecsSession or {}
            local layoutID = ns.GetActiveCDMLayoutID and ns.GetActiveCDMLayoutID()
            local reseedKey = specKey .. "|" .. tostring(layoutID or "?")
            if not ns._reseededSpecsSession[reseedKey] then
                ns._reseededSpecsSession[reseedKey] = true
                ns.ReseedAssignedSpellsFromLiveIcons(true)
                -- NO drop pass here, EVER (field data loss, 8.8.7 -> fixed
                -- 8.8.8): this tail runs synchronously inside the spec-swap
                -- rebuild with the store key already flipped to the incoming
                -- spec while the viewer pools and settings catalog still
                -- serve the OUTGOING spec -- every stored spell unshown in
                -- the old spec convicts as owned+unshown+uncatalogued and is
                -- DELETED (custom buff bar rows unrecoverably: no reseed
                -- lane re-adds them). Removal sync runs ONLY from settled
                -- states: Blizzard's settings-close hook and our options
                -- paths. Reseed itself stays -- it is add-only.
            end
        end
    end

    -- Per-spec one-shot: fold legacy dormantSpells back into assignedSpells at their
    -- saved slot index. Under the new "assignedSpells is pure user intent" model,
    -- dormant entries are restored so spells the old reconcile system evicted (pet
    -- abilities, choice-node talents) return to the user's chosen position. Rebuild the
    -- route map afterward so the revived entries become diversions.
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
    -- ProcessSpecChange (spec swap). Gated on ns._spellsReadyForApply so it only
    -- runs once Blizzard's viewer pools are guaranteed populated (same readiness
    -- signal ProcessSpecChange uses): on login the pending flag is set
    -- synchronously in CDMFinishSetup, but the first reanchor can fire BEFORE
    -- SPELLS_CHANGED arrives, and without this gate the pass would consume the
    -- flag against half-populated data and never re-run, leaving width-matched
    -- children (e.g. power bar <- CDM cooldowns) locked to a stale target width.
    -- The SPELLS_CHANGED handler forces a QueueReanchor when it sees the pending
    -- flag still set, so the pass always fires exactly once with correct widths.
    if ns._pendingApplyOnReanchor and ns._spellsReadyForApply then
        ns._pendingApplyOnReanchor = nil
        -- CDM is done populating icons; lift the rebuild gate so width
        -- matching can propagate against settled bar widths. Must happen
        -- BEFORE ApplyAllWidthHeightMatches so it isn't gated off.
        if EllesmereUI then EllesmereUI._cdmRebuilding = nil end
        -- Defer position/width corrections to next frame. These are purely visual
        -- positioning operations (width match, saved positions, anchor reapply) that
        -- cost ~25ms synchronously but are imperceptible if they settle 1 frame late.
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

    -- Refresh the options-panel preview (if open) so the content header reflects the
    -- icons we just populated. Without this, the preview shows empty on login/spec swap
    -- because it builds before the first queued CollectAndReanchor fires.
    if EllesmereUI and EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
        local pv = EllesmereUI._contentHeaderPreview
        if pv and pv.Update then pv:Update() end
    end
    -- Frames we could not identify this pass were skipped by the Phase 4 sweep
    -- and are still sitting wherever Blizzard left them. Re-collect shortly so
    -- they claim as soon as the cooldown-viewer API answers again -- this is
    -- what makes the recovery timing-independent instead of racing a fixed
    -- delay against the loading screen. Bounded and self-resetting: a clean
    -- pass restores the budget, and an id that never resolves falls back to the
    -- park path above once the budget is spent, so this can never spin.
    if next(unresolvedFrames) then
        local tries = ns._cdmUnresolvedRetries or 0
        if tries < 3 and not ns._cdmUnresolvedPending then
            ns._cdmUnresolvedRetries = tries + 1
            ns._cdmUnresolvedPending = true
            -- Backoff 0.5s / 1.5s / 2.5s: covers a loading-screen settle
            -- without a poll, since each retry is one queued reanchor.
            C_Timer.After(0.5 + tries, function()
                ns._cdmUnresolvedPending = nil
                if ns.QueueReanchor then ns.QueueReanchor() end
            end)
        end
    elseif ns._cdmUnresolvedRetries then
        ns._cdmUnresolvedRetries = 0
    end

    -- Claims just settled: retire the proc-alert child map so the next alert
    -- rebuilds it against the fresh claim set.
    if ns._cdmClaimGen then ns._cdmClaimGen = ns._cdmClaimGen + 1 end
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
-- fire Blizzard's TriggerAuraAppliedAlert (they appear on a cast/edge for a
-- fixed window), so the regular-buff apply-edge hook can't reach them; play the
-- SAME stored key (ss.buffActiveSoundKey) here, off the cast edge that
-- (re)starts the icon's timer. No loss sound: the real aura is secret/other-cast,
-- so only the gain edge is knowable. The id comes straight from the bar's
-- assignedSpells (clean, never secret), so the lookup is a direct spellSettings
-- hit, no GetCanonicalSpellIDForFrame dance. Gated 0-cost on ns._cdmAnyBuffSound
-- (same flag RescanBuffSoundFlag sets from these spellSettings) and throttled.
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

-------------------------------------------------------------------------------
--  Aura-tracked custom buffs (12.1). ONE engine flow container per bar: the
--  engine owns everything secret-derived, Lua declares only the id set and
--  the style; why they cannot join the bar's icon row is on _AC above the
--  collect passes. ENTRIES WITH A STORED DURATION ARE LEGACY CAST-TIMER
--  CUSTOMS AND NEVER REACH HERE. Styling reads the bar's own settings; glows
--  and per-spell overrides do not reach these icons.
-------------------------------------------------------------------------------

-- Appearance fingerprint: the settings a restyle can carry. Geometry the engine
-- flow owns (size, shape, spacing, growth, ids) rebuilds instead, in _AC.Build.
function _AC.StyleSig(bd)
    if not bd then return "" end
    return table.concat({
        bd.iconShape or "none", bd.iconZoom or 0.08,
        bd.borderSize or 1, bd.borderR or 0, bd.borderG or 0, bd.borderB or 0,
        bd.borderA or 1, bd.borderTexture or "solid", bd.borderThickness or "thin",
        bd.borderClassColor and 1 or 0, bd.borderBehind and 1 or 0,
        bd.borderTextureOffset or 0, bd.borderTextureOffsetY or 0,
        bd.borderTextureShiftX or 0, bd.borderTextureShiftY or 0,
        bd.bgR or 0.08, bd.bgG or 0.08, bd.bgB or 0.08, bd.bgA or 0.6,
        bd.swipeAlpha or 0.7, bd.onlyShowNumbers and 1 or 0,
        ns.CdmDurationTextOn(bd) and 1 or 0, bd.cooldownFontSize or 12,
        bd.cooldownTextPosition or "center",
        bd.cooldownTextR or 1, bd.cooldownTextG or 1, bd.cooldownTextB or 1,
        bd.cooldownTextX or 0, bd.cooldownTextY or 0,
        bd.showChargeStackText ~= false and 1 or 0, bd.stackCountSize or 11,
        bd.stackCountR or 1, bd.stackCountG or 1, bd.stackCountB or 1,
        bd.stackCountX or 0, bd.stackCountY or 0,
        bd.stackCountPosition or "bottomright",
        bd.showTooltip and 1 or 0, bd.barStrata or "MEDIUM",
    }, "|")
end

-- Countdown formatter for custom auras. Blizzard's own cooldown countdown --
-- what every other icon on the bar draws -- FLOORS the remaining time, so it
-- reads "0" through the last second; AuraKit's shared formatter rounds up and
-- read one higher beside it. Floor every unit to match. Built once (immutable,
-- shared by every bar); nil leaves AuraKit's formatter in place.
function _AC.DurationFormatter()
    if _AC.durFmtTried then return _AC.durFmt end
    _AC.durFmtTried = true
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Down = Enum.NumericRuleFormatRounding.Down
    local f = C_StringUtil.CreateNumericRuleFormatter()
    -- Thresholds sit ON each unit boundary: a floored value never crosses one,
    -- so none of the "just above the boundary" offsets the up-rounding
    -- formatters need apply here.
    local ok = pcall(f.SetBreakpoints, f, {
        { threshold = 0,     format = "%d",  step = 1, rounding = Down },
        { threshold = 60,    format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600,  format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
        { threshold = 86400, format = "%dd", step = 1, rounding = Down, components = { { div = 86400 } } },
    })
    if not ok then return nil end
    _AC.durFmt = f
    return f
end

-- Round to the nearest whole physical pixel -- the formula LayoutCDMBar uses for
-- the bar's own icons. PP.Scale (what the other AuraKit consumers use) truncates
-- instead, and lands a pixel short of the icon sitting next to this one.
function _AC.SnapPx(v)
    local onePx = EllesmereUI.PP and EllesmereUI.PP.mult
    if not onePx or onePx <= 0 then return v end
    return math.floor(v / onePx + 0.5) * onePx
end

-- The style a bar's custom auras render with. Read from the SAME bar settings
-- the bar's own icons use (RefreshCDMIconAppearance / ApplyShapeToCDMIcon) so a
-- custom aura and a Blizzard buff beside it look identical. AuraKit owns size,
-- crop, swipe and border; style.cdm carries what _AC.ApplyExtra draws on our own
-- regions (background, custom shape, text). PER-SPELL settings cannot reach here:
-- one engine group renders every custom aura on the bar and, while auras are
-- secret, Lua cannot tell which button holds which aura.
function _AC.BuildStyle(bd)
    -- Snapped to the physical pixel grid, as LayoutCDMBar does for the bar's own
    -- icons: an unsnapped button renders a fraction off its neighbors at
    -- non-integral UI scales.
    local rawSZ = (bd and bd.iconSize) or 36
    local SZ = _AC.SnapPx(rawSZ)
    local zoom = (bd and bd.iconZoom) or 0.08
    local shape = (bd and bd.iconShape) or "none"
    local customShape = (shape ~= "none" and shape ~= "cropped")
    local onlyNumbers = (bd and bd.onlyShowNumbers) and true or false
    local brdSize = (bd and bd.borderSize) or 1
    local brdR, brdG, brdB = (bd and bd.borderR) or 0, (bd and bd.borderG) or 0, (bd and bd.borderB) or 0
    if bd and bd.borderClassColor then
        local cc = _playerClass and RAID_CLASS_COLORS[_playerClass]
        if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end
    end
    local brdA = (bd and bd.borderA) or 1
    local cdFont = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

    -- Icon rect. A shaped icon samples OUTSIDE its texture to fill the mask, so
    -- the coords come from the shape's inset, not the bar's zoom -- same math as
    -- ApplyShapeToCDMIcon. Carried on the style (not written in ApplyExtra)
    -- because AuraKit re-applies texture coords on every restyle pass.
    local texCoord
    local SH = ns.CDM_SHAPES
    if shape == "cropped" then
        texCoord = { zoom, 1 - zoom, zoom + 0.10, 1 - zoom - 0.10 }
    elseif customShape and SH and SH.masks[shape] then
        local visRatio = (128 - 2 * (SH.insets[shape] or 17)) / 128
        local grow = ((1 / visRatio) - 1) * 0.5
        texCoord = { -grow, 1 + grow, -grow, 1 + grow }
    end

    -- Square border only where the bar's own icons draw one: a custom shape
    -- rings itself (_AC.ApplyExtra), Only Show Numbers strips the art entirely.
    local border
    if brdSize > 0 and not customShape and not onlyNumbers then
        border = {
            brdR, brdG, brdB, brdA, size = brdSize,
            texture = (bd and bd.borderTexture) or "solid",
            behind = (bd and bd.borderBehind) or nil,
            offsetX = bd and bd.borderTextureOffset, offsetY = bd and bd.borderTextureOffsetY,
            shiftX = bd and bd.borderTextureShiftX, shiftY = bd and bd.borderTextureShiftY,
            addonKey = "cdm", sizeKey = (bd and bd.borderThickness) or "thin",
        }
    end

    return {
        width = SZ,
        height = (shape == "cropped")
            and _AC.SnapPx(math.floor(rawSZ * 0.80 + 0.5)) or SZ,
        iconCrop = true, iconZoom = zoom,
        texCoord = texCoord,
        cooldownReverse = true,
        hideSwipe = onlyNumbers or nil,
        hideDurationText = (not ns.CdmDurationTextOn(bd)) or nil,
        durationFormatter = _AC.DurationFormatter(),
        -- Own text pipeline: the house icon-text rules (font, outline, slug) come
        -- from ApplyIconTextFont in _AC.ApplyExtra, exactly as the bar's icons do.
        noDefaultFonts = true,
        noTooltips = (bd and bd.showTooltip) and nil or true,
        border = border,
        applyExtra = _AC.ApplyExtra,
        cdm = {
            font = cdFont, size = SZ, zoom = zoom,
            shape = shape, customShape = customShape,
            brdSize = brdSize, brdR = brdR, brdG = brdG, brdB = brdB, brdA = brdA,
            onlyNumbers = onlyNumbers,
            bgR = (bd and bd.bgR) or 0.08, bgG = (bd and bd.bgG) or 0.08,
            bgB = (bd and bd.bgB) or 0.08, bgA = (bd and bd.bgA) or 0.6,
            swipeAlpha = (bd and bd.swipeAlpha) or 0.7,
            durSize = (bd and bd.cooldownFontSize) or 12,
            durPos = (bd and bd.cooldownTextPosition) or "center",
            durX = (bd and bd.cooldownTextX) or 0, durY = (bd and bd.cooldownTextY) or 0,
            durR = (bd and bd.cooldownTextR) or 1, durG = (bd and bd.cooldownTextG) or 1,
            durB = (bd and bd.cooldownTextB) or 1,
            stackOn = (bd and bd.showChargeStackText) ~= false,
            stackSize = (bd and bd.stackCountSize) or 11,
            stackPos = (bd and bd.stackCountPosition) or "bottomright",
            stackX = (bd and bd.stackCountX) or 0, stackY = (bd and bd.stackCountY) or 0,
            stackR = (bd and bd.stackCountR) or 1, stackG = (bd and bd.stackCountG) or 1,
            stackB = (bd and bd.stackCountB) or 1,
        },
    }
end

-- Regions the CDM look needs that AuraKit does not build. Runs in the button's
-- creation window -- the only place a region may be parented to an engine aura
-- button. Everything here is ours, so _AC.ApplyExtra can write it under secrecy.
function _AC.InitExtra(button, d)
    d.cdmBg = button:CreateTexture(nil, "BACKGROUND")
    d.cdmBg:SetAllPoints(button)
    d.cdmMask = button:CreateMaskTexture()
    d.cdmMask:SetAllPoints(button)
    d.cdmMask:Hide()
    -- Shape ring draws over the swipe, below the dispel ring and text carrier.
    -- Levelled off the cooldown (always the button's own level) rather than the
    -- border host, whose level a "Show Behind" border drops below the button.
    d.cdmRingHost = CreateFrame("Frame", nil, button)
    d.cdmRingHost:SetAllPoints(button)
    d.cdmRingHost:EnableMouse(false)
    d.cdmRingHost:SetFrameLevel(d.cooldown:GetFrameLevel() + 2)
    d.cdmRing = d.cdmRingHost:CreateTexture(nil, "OVERLAY", nil, 6)
    d.cdmRing:SetAllPoints(d.cdmRingHost)
    d.cdmRing:SetSnapToPixelGrid(false)
    d.cdmRing:SetTexelSnappingBias(0)
    d.cdmRing:Hide()
    -- AuraKit runs applyExtra BEFORE this creation hook, so the pass that draws
    -- these regions has to run once more now that they exist.
    local AK = EllesmereUI.AuraKit
    local style = AK and d.styleKey and AK.styles[d.styleKey]
    if style then _AC.ApplyExtra(button, d, style) end
end

-- Re-seat a mask reference. AddMaskTexture is additive, so the drop always
-- runs first or a re-apply stacks the same mask twice.
function _AC.SetMask(region, mask, want)
    if not region then return end
    pcall(region.RemoveMaskTexture, region, mask)
    if want then pcall(region.AddMaskTexture, region, mask) end
end

-- Background, custom shape and text, on our own regions. Anchors use
-- d.borderHost (created SetAllPoints(button) in the creation window) rather than
-- the button: a SetPoint whose relative frame is the button is denied while
-- auras are secret, which is exactly when a settings change must still land.
function _AC.ApplyExtra(button, d, style)
    local c = style.cdm
    if not c then return end
    local PP = EllesmereUI.PP

    -- Only Show Numbers strips the art down to the countdown. Shown-state as
    -- well as alpha, the same pair ApplyOnlyNumbers uses on the bar's own icons:
    -- a texture's alpha and its vertex color share one slot on this client.
    if d.icon then
        d.icon:SetAlpha(c.onlyNumbers and 0 or 1)
        d.icon:SetShown(not c.onlyNumbers)
        -- Cropped samples a heavy vertical slice, and a snapped image edge can
        -- round to a different physical pixel than the unsnapped swipe (the 1px
        -- split ApplyShapeToCDMIcon disables snapping for). Restored otherwise.
        if d.icon.SetSnapToPixelGrid then
            d.icon:SetSnapToPixelGrid(c.shape ~= "cropped")
        end
        if c.shape == "cropped" and d.icon.SetTexelSnappingBias then
            d.icon:SetTexelSnappingBias(0)
        end
    end
    if d.cdmBg then
        if c.onlyNumbers then
            d.cdmBg:Hide()
        else
            d.cdmBg:SetColorTexture(c.bgR, c.bgG, c.bgB, c.bgA)
            d.cdmBg:Show()
        end
    end
    if d.cooldown then d.cooldown:SetSwipeColor(0, 0, 0, c.swipeAlpha) end

    -- Custom shape: mask on icon/background/swipe plus the shape's own ring,
    -- mirroring ApplyShapeToCDMIcon so both renderers land on the same geometry.
    local SH = ns.CDM_SHAPES
    local mask, ring = d.cdmMask, d.cdmRing
    local maskPath = (c.customShape and SH and not c.onlyNumbers) and SH.masks[c.shape] or nil
    local shapeKey = maskPath
        and (c.shape .. "|" .. c.zoom .. "|" .. c.brdSize .. "|" .. c.size) or ""
    if d.cdmShapeKey ~= shapeKey and mask then
        if maskPath then
            mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:Show()
            _AC.SetMask(d.icon, mask, true)
            _AC.SetMask(d.cdmBg, mask, true)
            _AC.SetMask(d.cooldown, mask, true)
            local exp = SH.iconExpand + (SH.iconExpandOffsets[c.shape] or 0)
                + ((c.zoom - (SH.zoomDefaults[c.shape] or 0.06)) * 200)
            if exp < 0 then exp = 0 end
            local half = exp / 2
            if d.icon then
                d.icon:ClearAllPoints()
                PP.Point(d.icon, "TOPLEFT", d.borderHost, "TOPLEFT", -half, half)
                PP.Point(d.icon, "BOTTOMRIGHT", d.borderHost, "BOTTOMRIGHT", half, -half)
            end
            mask:ClearAllPoints()
            if c.brdSize >= 1 then
                PP.Point(mask, "TOPLEFT", d.borderHost, "TOPLEFT", 1, -1)
                PP.Point(mask, "BOTTOMRIGHT", d.borderHost, "BOTTOMRIGHT", -1, 1)
            else
                mask:SetAllPoints(d.borderHost)
            end
            if d.cooldown then
                pcall(d.cooldown.SetSwipeTexture, d.cooldown, maskPath)
                if d.cooldown.SetUseCircularEdge then
                    pcall(d.cooldown.SetUseCircularEdge, d.cooldown,
                        c.shape ~= "square" and c.shape ~= "csquare")
                end
                if d.cooldown.SetEdgeScale then
                    pcall(d.cooldown.SetEdgeScale, d.cooldown, SH.edgeScales[c.shape] or 0.60)
                end
            end
        else
            _AC.SetMask(d.icon, mask)
            _AC.SetMask(d.cdmBg, mask)
            _AC.SetMask(d.cooldown, mask)
            mask:SetTexture(nil); mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001); mask:Hide()
            if d.icon then
                d.icon:ClearAllPoints()
                d.icon:SetAllPoints(d.borderHost)
            end
            if d.cooldown then
                pcall(d.cooldown.SetSwipeTexture, d.cooldown, "Interface\\AddOns\\EllesmereUI\\media\\white-square.png")
                if d.cooldown.SetUseCircularEdge then
                    pcall(d.cooldown.SetUseCircularEdge, d.cooldown, false)
                end
            end
        end
        d.cdmShapeKey = shapeKey
    end
    -- Ring color follows the border color on every pass, so a color-only change
    -- lands without re-running the geometry above. Border Size 0 drops the ring,
    -- as it does on the bar's own shaped icons.
    if ring then
        local ringPath = (maskPath and c.brdSize > 0) and SH.borders[c.shape] or nil
        if ringPath then
            ring:SetTexture(ringPath)
            ring:SetVertexColor(c.brdR, c.brdG, c.brdB, c.brdA)
            ring:Show()
        else
            ring:Hide()
        end
    end

    if d.duration then
        local fKey = c.font .. "|" .. c.durSize
        if d.cdmDurFont ~= fKey then
            d.cdmDurFont = fKey
            EllesmereUI.ApplyIconTextFont(d.duration, c.font, c.durSize, "cdm")
        end
        local aKey = c.durPos .. "|" .. c.durX .. "|" .. c.durY
        if d.cdmDurAnchor ~= aKey then
            d.cdmDurAnchor = aKey
            ns.AnchorCooldownText(d.duration, d.borderHost, c.durPos, c.durX, c.durY)
        end
        d.duration:SetTextColor(c.durR, c.durG, c.durB)
    end

    if d.stack then
        local fKey = c.font .. "|" .. c.stackSize
        if d.cdmStackFont ~= fKey then
            d.cdmStackFont = fKey
            EllesmereUI.ApplyIconTextFont(d.stack, c.font, c.stackSize, "cdm")
        end
        local aKey = c.stackPos .. "|" .. c.stackX .. "|" .. c.stackY
        if d.cdmStackAnchor ~= aKey then
            d.cdmStackAnchor = aKey
            local pt, y = ns.CdmStackAnchorPoint(c.stackPos, c.stackY)
            d.stack:ClearAllPoints()
            d.stack:SetPoint(pt, d.borderHost, pt, c.stackX, y)
        end
        d.stack:SetTextColor(c.stackR, c.stackG, c.stackB)
        -- Alpha, not Hide: the engine re-shows this font string whenever the
        -- slot's application count refreshes.
        d.stack:SetAlpha(c.stackOn and 1 or 0)
    end
end

function _AC.Build(rec, barKey, bd, sids, sig)
    local AK = EllesmereUI.AuraKit
    local barFrame = cdmBarFrames[barKey]
    -- Bar not built yet (login race): bail WITHOUT stamping the signature;
    -- the next tracking sync re-queues the build.
    if not (AK and AK.CreateContainerShell and AK.AddGroupToContainer and barFrame) then return end
    local styleKey = "cdm:aurabuff:" .. barKey
    AK.styles[styleKey] = _AC.BuildStyle(bd)
    rec.styleSig = _AC.StyleSig(bd)
    -- Retire the previous generation properly (the holder is reused).
    if rec.container and AK.ReleaseContainer then AK.ReleaseContainer(rec.container) end
    local holder = rec.holder
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(1, 1)
        holder:EnableMouse(false)
        rec.holder = holder
    end
    holder:SetFrameStrata((bd and bd.barStrata) or "MEDIUM")
    holder:Show()
    -- ONE flow group carrying every id form the live aura can carry (typed
    -- + override + base): the engine compacts actives and renders nothing
    -- when none are up.
    local includeMap = {}
    for i = 1, #sids do
        local sid = sids[i]
        includeMap[sid] = true
        local ovr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
            and C_SpellBook.FindSpellOverrideByID(sid)
        if ovr and ovr > 0 then includeMap[ovr] = true end
        local base = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(sid)
        if base and base > 0 then includeMap[base] = true end
    end
    local vertical = (bd and bd.verticalOrientation) and true or false
    local gap = (bd and bd.spacing) or 2
    local grow = (bd and bd.growDirection) or "CENTER"
    -- Container point mirrors _AC.Anchor's holder placement: the tail
    -- always flows AWAY from the bar's end (end-of-bar for all growths).
    local pt
    if vertical then
        pt = (grow == "UP") and "BOTTOM" or "TOP"
    elseif grow == "LEFT" then
        pt = "RIGHT"
    else
        pt = "LEFT"
    end
    local container = AK.CreateContainerShell(holder, { point = { pt } })
    rec.pt = pt
    rec.curPt = pt
    if AK.SetContainerAxis then AK.SetContainerAxis(container, vertical) end
    AK.AddGroupToContainer(container, {
        key = "spells",
        filter = { "HELPFUL" },
        style = styleKey,
        extraInit = _AC.InitExtra,
        maxFrameCount = #sids,
        -- Helpful spellID includes on the player pass the identity gate
        -- regardless of the spell's secrecy flag.
        candidateFilters = { includeSpellIDs = includeMap },
    })
    if container.SetAuraGroupLayout then
        -- elementWidth/Height feed the engine's flow math (the style sizes the
        -- button itself). Without them the flow spaces icons at the engine
        -- default, so any bar not at that size overlaps or gaps -- and a cropped
        -- bar, whose buttons are 0.80 tall, is off on both axes.
        local st = AK.styles[styleKey]
        local gapPx = _AC.SnapPx(gap)
        container:SetAuraGroupLayout("spells", {
            elementWidth = st and st.width, elementHeight = st and st.height,
            elementSpacing = gapPx, lineSpacing = gapPx,
            groupSpacing = gapPx, groupLineSpacing = gapPx,
        })
    end
    AK.FinishContainer(container, "player")
    rec.container = container
    rec.sig, rec.sids = sig, sids
    rec.bdRef = bd
    -- Follow the bar's rect from OUR frame's own change signals (post-hook
    -- + scripts): the holder re-derives its position one coalesced frame
    -- after any bar move/resize/visibility change.
    if rec.hookedBar ~= barFrame then
        rec.hookedBar = barFrame
        local function poke() _AC.MarkSync(barKey) end
        hooksecurefunc(barFrame, "SetPoint", poke)
        barFrame:HookScript("OnSizeChanged", poke)
        barFrame:HookScript("OnShow", poke)
        barFrame:HookScript("OnHide", poke)
    end
    _AC.Anchor(barKey, rec)
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
                                    cd:SetHideCountdownNumbers(not ns.CdmDurationTextOn(barData))
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
                                    local iconSID = ns.LustPresetIconSpellID
                                        and ns.LustPresetIconSpellID(sid) or sid
                                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconSID)
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

-- Sync pass for aura-tracked custom buffs, run from the rebuild tails and
-- the picker add flows. Collects each bar's no-duration custom ids, and
-- (re)builds that bar's engine tail container ONLY when the signature --
-- the id list plus the baked styling inputs -- changes. Containers for
-- bars that no longer have aura customs are hidden (dormant, zero cost).
function ns.UpdateCustomBuffAuraTracking()
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    local seen = {}
    if bars then
        for _, bd in ipairs(bars) do
            if bd.enabled and (bd.barType == "custom_buff" or bd.barType == "buffs") then
                local sd = ns.GetBarSpellData and ns.GetBarSpellData(bd.key)
                local list = sd and sd.assignedSpells
                local tags = sd and sd.customSpellIDs
                if list and tags then
                    local durs = sd.spellDurations
                    local sids
                    for _, sid in ipairs(list) do
                        if type(sid) == "number" and sid > 0 and tags[sid]
                           and (not durs or (durs[sid] or 0) <= 0) then
                            sids = sids or {}
                            sids[#sids + 1] = sid
                        end
                    end
                    if sids then
                        seen[bd.key] = true
                        -- Structural only: the id list plus the geometry the
                        -- engine flow owns. Everything else is appearance and
                        -- rides ns.RefreshAuraCustomStyle without a rebuild.
                        local sig = table.concat(sids, ":")
                            .. "|" .. tostring(bd.iconSize or 36)
                            .. "|" .. tostring(bd.iconShape or "none")
                            .. "|" .. tostring(bd.growDirection or "CENTER")
                            .. "|" .. (bd.verticalOrientation and 1 or 0)
                            .. "|" .. tostring(bd.spacing or 2)
                        local rec = _AC.bars[bd.key]
                        if not rec then rec = {}; _AC.bars[bd.key] = rec end
                        rec.bdRef = bd
                        if rec.sig ~= sig and not rec.queued then
                            local AK = EllesmereUI.AuraKit
                            if AK and AK.QueueBuildJob then
                                rec.queued = true
                                local barKey, bdRef, sidsRef, sigRef = bd.key, bd, sids, sig
                                AK.QueueBuildJob(function()
                                    rec.queued = nil
                                    _AC.Build(rec, barKey, bdRef, sidsRef, sigRef)
                                    -- The job captured the id list as it was when
                                    -- it was queued. A change that landed while it
                                    -- was in flight (two adds in a row) is not in
                                    -- what it just built, and stamping rec.sig hides
                                    -- it from every later compare -- so re-sync once
                                    -- here instead of losing the spell until a reload.
                                    if rec.resync then
                                        rec.resync = nil
                                        ns.UpdateCustomBuffAuraTracking()
                                    end
                                end, "cdm:aurabuff-shell")
                            end
                        elseif rec.queued and rec.sig ~= sig then
                            rec.resync = true
                        else
                            ns.RefreshAuraCustomStyle(bd.key)
                        end
                    end
                end
            end
        end
    end
    for barKey, rec in pairs(_AC.bars) do
        if not seen[barKey] and rec.sids then
            -- Bar lost its aura customs: hide the holder, release the
            -- engine container, forget the build.
            if rec.holder then rec.holder:Hide() end
            local AK = EllesmereUI.AuraKit
            if rec.container and AK and AK.ReleaseContainer then
                AK.ReleaseContainer(rec.container)
            end
            rec.container = nil
            rec.sig = nil
            rec.sids = nil
            rec.styleSig = nil
        end
    end
end

-- Re-apply a bar's appearance to its custom-aura icons. Called from every CDM
-- restyle path, so an options change lands on them the same frame it lands on
-- the bar's own icons instead of waiting for a reload or a spec swap. Free for
-- bars with no custom auras (one table lookup) and a no-op when nothing the
-- style reads has changed.
function ns.RefreshAuraCustomStyle(barKey)
    local rec = barKey and _AC.bars[barKey]
    if not (rec and rec.container) then return end
    local bd = barDataByKey[barKey]
    if not bd then return end
    rec.bdRef = bd
    local sig = _AC.StyleSig(bd)
    if rec.styleSig == sig then return end
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.styles) then return end
    if rec.holder then rec.holder:SetFrameStrata(bd.barStrata or "MEDIUM") end
    local styleKey = "cdm:aurabuff:" .. barKey
    AK.styles[styleKey] = _AC.BuildStyle(bd)
    if AK.RestyleSoon then AK.RestyleSoon(styleKey) end
    -- Stamped only once the style is actually installed: recording a style that
    -- never applied would make every later call with the same settings early-out.
    rec.styleSig = sig
end

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

-- Cancel any pending queued reanchor. Used by FullCDMRebuild's spec swap branch when it
-- runs CollectAndReanchor directly -- without this, the reanchor BuildAllCDMBars queued
-- earlier in the same call would fire a second time after the throttle expires.
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
--  Buff-family removal happens ONLY inside ns.ReconcileAssignedSpellDrops's
--  buff-family branch, gated on the persisted variant-alias ledger: a
--  candidate id drops only once every learned-family member is absent from
--  the buff-category catalog present-set AND not currently displayed. This
--  function never prunes. Do NOT reintroduce frame-pool-based orphan pruning
--  here (stripping any positive assignedSpells entry whose spellID isn't
--  found in the BuffIcon pool/CDM category set): DUAL-TRACKED spells
--  carrying more than one variant spell ID cause data loss. E.g. Vengeance
--  DH stores Metamorphosis as 191427, but every live Vengeance frame reports
--  187827 -- 191427 surfaces ONLY via the buff frame's linkedSpellIDs, and
--  ONLY while the buff is active, so a presence-only prune running here
--  (~0.3s after the panel closes, when Meta is typically down) would match
--  neither the pool nor the category set and delete it -- which also
--  destroys the route-map diversion, spilling re-tracked Meta onto the
--  DEFAULT buffs bar. The ledger-gated pass survives this case once the
--  191427<->187827 pairing has been learned, by keeping the whole family
--  alive while any member (e.g. 187827) is present; a family never learned
--  on this spec remains a harmless non-rendering preview entry (removable
--  by hand), consistent with the CD/utility side.
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
    reanchorFrame = ns.TakeShell()
    reanchorFrame:SetScript("OnUpdate", ProcessReanchorQueue)
    reanchorFrame:Hide()

    -- 1. Mixin hooks: detect spell changes on CDM frames. Reset frame spell
    --    cache so the next reanchor re-resolves the spellID (handles transforms
    --    like Avenging Crusader -> Crusader Strike). CD/utility bars: spell set
    --    is locked during a session (changes only via FullCDMRebuild on
    --    spec/talent/equip events) -- real-time reanchors from OnCooldownIDSet
    --    are unnecessary and catastrophic when Blizzard continuously rebuilds
    --    pools (e.g. Lightsmith Holy Armaments), so we only clear the FC cache
    --    for the next rebuild. Buff bars ARE dynamic (appear/disappear at
    --    runtime), so they still need real-time OnCooldownIDSet reanchors.
    local function ResetFrameCache(frame)
        -- Content churn: re-arm the buff ticker's dirty + pool gates.
        ns._acGen = (ns._acGen or 0) + 1
        ns._btDirty = true
        if ns.ArmBuffTicker then ns.ArmBuffTicker() end
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
            ns._acGen = (ns._acGen or 0) + 1
            ns._btDirty = true
            if ns.ArmBuffTicker then ns.ArmBuffTicker() end
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
                -- Use the throttled queue here, not a direct call, so bursts
                -- of state changes can't stack up multiple full reanchors.
                if frame.OnActiveStateChanged then
                    local _asDeferFrame = CreateFrame("Frame")
                    _asDeferFrame:Hide()
                    local _asDeferTicks = 0
                    _asDeferFrame:SetScript("OnUpdate", function(self)
                        _asDeferTicks = _asDeferTicks + 1
                        if _asDeferTicks < 2 then return end
                        self:Hide()
                        _activeStateReanchorPending = false
                        QueueReanchor()
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
                ns._acGen = (ns._acGen or 0) + 1
                ns._btDirty = true
                if ns.ArmBuffTicker then ns.ArmBuffTicker() end
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

            -- Intercept newly acquired frames the instant Blizzard creates them, before
            -- they render at the viewer's default position. Alpha 0 until our reanchor
            -- claims and positions them. The pool Acquire hook above already queues a
            -- reanchor. Skip during init: on /reload ALL frames are acquired at once
            -- and our reanchor hasn't run yet, so blanking them would hide all buffs
            -- until the first buff change.
            if v.OnAcquireItemFrame then
                hooksecurefunc(v, "OnAcquireItemFrame", function(_, itemFrame)
                    if not ns._initialReanchorDone then return end
                    -- Skip blanking bar viewer children when user wants Blizzard tracked bars
                    if isBarViewer then
                        local pp = ECME.db and ECME.db.profile
                        if pp and pp.cdmBars and pp.cdmBars.useBlizzardBuffBars then return end
                    end
                    -- CD/utility viewers: spell set is static (rebuilt only by
                    -- FullCDMRebuild on spec/talent/equip). Pool churn from spell
                    -- transforms (e.g. Monk Empty Barrel -> Keg Smash) re-acquires
                    -- frames but does NOT queue a reanchor, so blanking here leaves
                    -- icons invisible with nothing to restore them. The SetPoint hook
                    -- already handles repositioning for these viewers.
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
            -- In-place edits to the ACTIVE Blizzard layout (spell added to the
            -- layout you are already on) do not change its layout id, so the
            -- spec+layout auto-reseed gate would never re-materialize them.
            -- Wipe the session table here, on panel close (edits happen with the
            -- panel open; the reanchor queued below re-runs the add-only
            -- reseed). NOT on CooldownViewerSettings.OnDataChanged: Blizzard
            -- also fires that from RefreshFromExternalUpdate on SPELLS_CHANGED
            -- / PLAYER_EQUIPMENT_CHANGED / PvP talent updates, which would
            -- re-run a full reseed pass on every form swap or gear change.
            if ns._reseededSpecsSession then wipe(ns._reseededSpecsSession) end
            C_Timer.After(0.1, QueueReanchor)
            -- Delay sync slightly longer so Blizzard finishes rebuilding pools
            C_Timer.After(0.3, function()
                ns.SyncExtraBuffBarsWithViewer()
            end)
            -- Reconcile keep/drop after Blizzard's layout writes settle and
            -- our own sync/reanchor above have run, so the pass sees the
            -- post-close viewer state rather than a mid-close transient.
            C_Timer.After(0.4, function()
                if ns.RequestCDMDropPass then ns.RequestCDMDropPass("settings") end
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
        local cdmBuffTickFrame = ns.TakeShell()
        local _, _cachedClassToken = UnitClass("player")
        -- 10 Hz anim ticker: the C engine fires the body at cadence and
        -- sleeps between fires, replacing a per-frame OnUpdate whose
        -- accumulator check ran at frame rate (~200x/sec) just to gate this
        -- 10 Hz job -- the dispatch-floor disease the ERB rebuild removed.
        -- Body and cadence unchanged; fn returns true to keep looping.
        local _btBody = function()
            -- Dirty-gated (timed: the full body ran 0.26ms per fire at 10 Hz
            -- = nearly all of CDM's combat CPU). The body runs ONLY when a
            -- dirty edge fired -- player aura/totem flip, viewer pool churn,
            -- pandemic edge, preset-cooldown dirt. There is no staleness
            -- net: after ~1s of settled fires the ticker STOPS ITSELF and
            -- every dirty writer re-arms it via ns.ArmBuffTicker. A stale
            -- glow/desat is a missing edge to register, never to sweep for.
            local _btNow = GetTime()
            -- Park integrity lives on event edges now (ns._parkEdges in the
            -- main file + the QueueRepark hooksecurefuncs) -- no patrol here.
            if not ns._btDirty then
                -- Preset cooldowns drain independently on clean fires, capped at 1 Hz:
                -- the dirty flag re-arms ~22x/sec from the racial/ trinket catch-alls,
                -- so an uncapped drain runs at full tick cadence. Casts bypass the cap
                -- (the racial listener's fast lane zeroes ns._pcLast), and swipes are
                -- engine-animated once pushed, so the slow lane is imperceptible.
                if _presetCdDirty and _btNow - (ns._pcLast or 0) >= 1 then
                    ns._pcLast = _btNow
                    ProcessPresetCooldowns()
                end
                if _presetCdDirty then
                    ns._btCleanFires = 0
                elseif (ns._btCleanFires or 0) < 10 then
                    ns._btCleanFires = (ns._btCleanFires or 0) + 1
                else
                    -- Settled for ~1s (no dirty edge, presets drained): stop
                    -- the ticker outright. Zero fires until the next edge.
                    ns._btCleanFires = 0
                    return false
                end
                return true
            end
            ns._btCleanFires = 0
            ns._btDirty = nil
            local p = ECME and ECME.db and ECME.db.profile
            if not p or not p.cdmBars or not p.cdmBars.bars then return true end
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

                                -- Desaturate inactive buff icons when Always Show
                                -- Buffs is on and Desaturate Off CD is enabled. When
                                -- Always Show Buffs is off, desaturation is ignored
                                -- (no inactive icons should be visible anyway).
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

                                -- Pandemic glow: Blizzard's ShowPandemicStateFrame hook sets
                                -- _pandemicState (user configures pandemic alerts in Blizzard
                                -- CDM settings). Only the START side is gated on the setting;
                                -- the STOP side below must stay reachable with the setting OFF,
                                -- or a glow already running when the user disables it never
                                -- takes down (stuck lit until the aura lapses, re-lapses, since
                                -- only that finally makes the stop branch reachable). The buff glow directly above already has this shape.
                                local inPandemic = false
                                if fd then
                                    -- Blizzard Default (-1) is the ONLY config that
                                    -- needs no hook: Blizzard's native PandemicIcon
                                    -- does the whole job, so that config still costs
                                    -- zero. EVERY other config needs the hook --
                                    -- custom styles (>0) to REPLACE the icon, and
                                    -- None (pandemicGlow off) to SUPPRESS it.
                                    --
                                    -- Installing was gated on `pandemicOn`, so None got no
                                    -- hook at all and _PandemicShow (which hides Blizzard's
                                    -- icon) never ran, letting Blizzard's PandemicIcon render
                                    -- unopposed with no way to turn the option off -- same shape
                                    -- as the stop-branch bug: code that acts when a setting is
                                    -- OFF must not sit behind a gate requiring it ON. For custom
                                    -- styles the hooks still install lazily HERE on first need;
                                    -- this tick runs on a CDM shell, so install-time work bills
                                    -- CooldownManager too. nil is NOT the same as false here: a
                                    -- never-configured bar has pandemicGlow == nil and must keep
                                    -- behaving as Blizzard Default (the three built-in bars never
                                    -- seed the key, while every seeding template ships true +
                                    -- style -1) -- only an EXPLICIT false (user picks None)
                                    -- suppresses, so this fix can't silently strip the pandemic icon from anyone who never touched it.
                                    local pStyle = bd.pandemicGlowStyle or 1
                                    local custom = pandemicOn and pStyle ~= -1
                                    local isNone = (bd.pandemicGlow == false)
                                    if custom or isNone then
                                        if ns._pandemicHooked and not ns._pandemicHooked[frame]
                                           and ns.HookPandemicState then
                                            ns.HookPandemicState(frame)
                                        end
                                    end
                                    if custom then
                                        -- Not while the flag is describing an aura
                                        -- that already ended (ns._PandemicIconHide).
                                        inPandemic = not fd._panStale
                                            and ns._pandemicState and ns._pandemicState[frame]
                                    elseif isNone then
                                        -- The hook only fires on the NEXT
                                        -- ShowPandemicStateFrame, so an icon already
                                        -- lit when the user picked None would stay up
                                        -- until the aura lapsed. Take it down here
                                        -- too; Hide is idempotent and this only runs
                                        -- for bars actually set to None.
                                        local pi = frame.PandemicIcon
                                        if pi and pi:IsShown() then pi:Hide() end
                                    end
                                end
                                if inPandemic and fd then
                                    if not fd.pandemicOverlay then
                                        local ov = CreateFrame("Frame", nil, frame)
                                        ov:SetAllPoints(frame)
                                        ov:EnableMouse(false)
                                        fd.pandemicOverlay = ov
                                        -- Once per frame, and only for icons that
                                        -- actually glow: the stop edge the tick
                                        -- cannot see, and the window edge that
                                        -- says the flag is current again (see
                                        -- ns._PandemicIconHide).
                                        frame:HookScript("OnHide", ns._PandemicIconHide)
                                        if frame.SetPandemicAlertTriggerTime then
                                            hooksecurefunc(frame, "SetPandemicAlertTriggerTime",
                                                ns._PandemicWindowSet)
                                        end
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
                                elseif fd and fd.pandemicGlowActive and fd.pandemicOverlay then
                                    ns.StopNativeGlow(fd.pandemicOverlay)
                                    fd.pandemicGlowActive = false
                                end

                                -- Active State Glow integrity, BOTH edges. The glow is
                                -- normally driven as a side effect of Blizzard calling
                                -- Cooldown:SetSwipeColor, and Blizzard skips that call
                                -- on either aura edge (a DoT expiring naturally pushes
                                -- no swipe until the next GCD; an aura landing outside
                                -- a cooldown refresh pushes none at all). The rise edge
                                -- additionally breaks when another owner of the shared
                                -- glowOverlay -- the CD-state glow or proc glow --
                                -- stops the texture without clearing fd._activeGlowOn:
                                -- the hook's idempotence check then believes the glow
                                -- is still running and never restarts it, leaving the
                                -- icon dark for the rest of the session. Re-assert from
                                -- the same swipe colour the hook reads so both edges
                                -- self-heal within a tick.
                                if fd and not fd._isBuffViewerFrame
                                   and (fd._activeGlowOn or ns._cdmAnyActiveGlow) then
                                    local swipeColor = frame.cooldownSwipeColor
                                    local r
                                    if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                                        r = swipeColor:GetRGBA()
                                        -- Secret or unavailable reads as "no
                                        -- data" -- neither edge acts on it.
                                        if type(r) ~= "number" or issecretvalue(r) then r = nil end
                                    end
                                    if r == 0 then
                                        -- Clean 0: not active. Clear a glow we own.
                                        -- Also re-arm the no-config latch below so
                                        -- the next activation re-checks settings.
                                        fd._activeGlowNoCfg = nil
                                        if fd._activeGlowOn then
                                            if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                                            fd._activeGlowOn = false
                                        end
                                    elseif r and ns._cdmAnyActiveGlow
                                       and not fd._activeGlowNoCfg
                                       and not (fd._activeGlowOn and fd.glowOverlay
                                                and fd.glowOverlay._glowActive) then
                                        -- Active, but no glow is actually running
                                        -- on the overlay. Drop any orphaned flag
                                        -- so ApplyActiveOverlays really restarts,
                                        -- then let it re-resolve style + colour.
                                        fd._activeGlowOn = false
                                        local ssA = ns._ResolveCdmSS(frame)
                                        if ssA and (tonumber(ssA.activeGlow) or 0) > 0 then
                                            ns.ApplyActiveOverlays(frame, fd, ssA, true, bd)
                                        else
                                            -- No active glow configured for THIS
                                            -- icon, so the resolve can only answer
                                            -- "no" again for the rest of this
                                            -- active window. Latch it off.
                                            --
                                            -- ns._cdmAnyActiveGlow is a GLOBAL gate
                                            -- -- one spell anywhere with a glow arms
                                            -- it for every frame -- so without this
                                            -- every active icon in the profile pays a
                                            -- full settings resolve on every pass
                                            -- purely to rediscover it has nothing to
                                            -- do. Icons that DO have a glow never reach
                                            -- here, so the repair this pass exists for
                                            -- is untouched. Re-armed on the falloff
                                            -- edge above and by DecorateFrame, so a
                                            -- newly enabled glow is picked up without
                                            -- waiting for the aura to drop.
                                            fd._activeGlowNoCfg = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if needsReanchor then QueueReanchor() end
            -- Refresh aura active cache. This is the sole maintainer of _activeCache;
            -- bar glow overlays read from ns._tickBlizzActiveCache. Walk the live
            -- pools and mark any frame whose Blizzard-set
            -- wasSetFromAura/auraInstanceID indicates an active aura. Calls
            -- ResolveFrameSpellID (which has its own resolve cache) so
            -- BuffBarCooldownViewer frames -- which CollectAndReanchor never visits --
            -- still get their fc populated for bar glow triggers on Tracked Bar spells
            -- (Divine Protection etc). Pool-generation gate: aura ticks dirty the BODY
            -- but do not reshuffle viewer pools, so the four-pool enumeration below
            -- only reruns after actual pool churn (Acquire/Release/OnCooldownIDSet
            -- bump the generation) or on a 1s staleness net.
            if ns._acGen ~= ns._acSeenGen or _btNow - (ns._acLastFull or 0) >= 1 then
                ns._acSeenGen = ns._acGen
                ns._acLastFull = _btNow
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
            end -- pool-generation gate
            -- Process preset cooldowns (trinkets/items/racials) if any event
            -- dirtied the flag since the last tick. Coalesces dozens of per-GCD
            -- SPELL_UPDATE_COOLDOWN events into a single 10Hz update pass.
            if ns._isPresetCdDirty and ns._isPresetCdDirty()
               and _btNow - (ns._pcLast or 0) >= 1 then
                -- Same 1 Hz slow lane as the clean-fire drain (casts reset
                -- the cap in the racial listener's fast lane).
                ns._pcLast = _btNow
                ns._ProcessPresetCooldowns()
            end
            return true
        end
        -- Dirty sources with dedicated events: aura and totem flips change buff/glow
        -- state without pool churn. Frame is CDM-born, so the handler bills
        -- CooldownManager. Aura REMOVALS also release buff-viewer pool frames with no
        -- Acquire, so they bump the pool generation (the precise fade signal) with no
        -- Release hook -- a Release hook was tried and reverted: its closures were born
        -- under parent dispatch, billing the parent per fade, and mass release/reacquire
        -- churn re-armed the rebuild every tick. The ticker is created LAZILY on the
        -- first event ON PURPOSE: the animation group (OnLoop entry object) bills the
        -- addon whose execution context CREATED it, and this setup function runs under
        -- the parent's lifecycle dispatch, so creating it here would bill the entire
        -- 10Hz body to the PARENT. The first event on this CDM-born frame is a
        -- CooldownManager context, so the group is born correctly billed.
        local _btTicker
        cdmBuffTickFrame:RegisterUnitEvent("UNIT_AURA", "player")
        cdmBuffTickFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
        cdmBuffTickFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        cdmBuffTickFrame:SetScript("OnEvent", function(_, event, _, updateInfo)
            ns._btDirty = true
            -- Gen bump on anything that can CHANGE which auras are active: additions
            -- (a glow must LIGHT), plus anything that can release a pool frame --
            -- removals/full updates, totem drops/despawns, world entry. Additions
            -- matter because a spell tracked in a COOLDOWN viewer keeps its frame
            -- acquired permanently, so Blizzard merely sets wasSetFromAura/
            -- auraInstanceID on the frame that's already there -- no Acquire, no
            -- generation bump, so lighting a Bar Glow (e.g. Killing Machine ->
            -- Obliterate) would fall through to the 1s staleness net below, up to a
            -- second late and missed entirely if the proc was consumed inside that
            -- window. Only UNIT_AURA carries an updateInfo table in this slot --
            -- PLAYER_ENTERING_WORLD's second arg is the isReconnect BOOLEAN (true on
            -- /reload), so the payload must never be indexed for the other events.
            if event ~= "UNIT_AURA" then
                ns._acGen = (ns._acGen or 0) + 1
            elseif updateInfo then
                -- SECRET-SAFE: the payload TABLE and each of its fields can all arrive
                -- secret in instanced content, and a secret can never be boolean-tested
                -- in Lua (a hard error, not a falsy read). So: guard the table before
                -- indexing it, bind fields to locals (reading a secret is always
                -- legal), then issecretvalue-gate every test. When unreadable, assume
                -- churn -- one extra pool rebuild costs far less than a cache still
                -- holding released frames. Same guard shape as the lust listener in CdmBuffBars.
                if issecretvalue(updateInfo) then
                    ns._acGen = (ns._acGen or 0) + 1
                else
                    local full    = updateInfo.isFullUpdate
                    local removed = updateInfo.removedAuraInstanceIDs
                    local added   = updateInfo.addedAuras
                    if issecretvalue(full) or issecretvalue(removed)
                       or issecretvalue(added)
                       or full or removed or added then
                        ns._acGen = (ns._acGen or 0) + 1
                    end
                end
            end
            if not _btTicker then
                _btTicker = EllesmereUI.Tick.NewAnimTicker(cdmBuffTickFrame, _btBody, 0.1)
            end
            _btTicker.Start()
        end)
        -- Re-arm for every dirty writer. The body self-stops when settled; Start() on a
        -- playing ticker is one IsPlaying check, so arming stays indiscriminate.
        -- Creation is EXCLUSIVELY the OnEvent above's job (guaranteed CDM execution
        -- context -- see the attribution note), so a pre-first-event arm is a no-op;
        -- PLAYER_ENTERING_WORLD always creates it at login.
        ns.ArmBuffTicker = function()
            if _btTicker then _btTicker.Start() end
        end
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
        local emEventFrame = ns.TakeShell()
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

-- Skip locking the BuffBarCooldownViewer when the user has enabled "Use Blizzard CDM
-- Bars" -- they want to drag/configure that frame in Edit Mode themselves. All other
-- CDM viewers stay locked because EUI manages their position via icon-level anchoring.
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
--  press that ability's keybind, even while on cooldown. Hooks the
--  action-button key-down path (ActionButtonDown/MultiActionButtonDown), which
--  fires on the physical press regardless of cooldown or the cast-on-key-
--  down/up CVar. Pushed texture + colour are read live from the EllesmereUI
--  action bars settings, so the CDM press matches real buttons (falling back
--  to a border-cropped Blizzard depress texture if that module isn't present).
--  On a custom-shape bar the press is masked to the shape, so a hexagon icon
--  flashes a hexagon rather than the full square it sits in.
--  Per-frame data lives in an external weak-keyed table.
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
    local _poll  = ns.TakeShell()
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

    -- Custom shape of a CDM icon (hexagon/circle/...), or nil for a square one.
    -- A square press drawn over a shaped icon spills past the shape, so the
    -- overlay has to follow it. We reuse the icon's own shapeMask -- masking is
    -- screen-space and the overlay covers the same rect -- exactly like the
    -- fake-active overlay does (ns.ApplyShapeToOverlay). none/cropped return
    -- nil: their icon art fills the frame rect, so a square press is correct.
    local function IconShape(icon)
        local ifc = _ecmeFC and _ecmeFC[icon]
        if not (ifc and ifc.shapeApplied and ifc.shapeMask) then return nil end
        local shape = ifc.shapeName
        if not shape or shape == "none" or shape == "cropped" then return nil end
        return shape, ifc.shapeMask
    end

    -- Ring art for "border" pushed mode on a shaped icon: four straight edges
    -- around a hexagon leave the corners hanging in space, so press-flash the
    -- shape's own border texture instead. Its thickness is baked into the art,
    -- so the bars' pushed border size doesn't apply -- colour still does.
    local function EnsureShapeRing(ov)
        if ov._shapeRing then return ov._shapeRing end
        local t = ov:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        t:Hide()
        ov._shapeRing = t
        return t
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
        -- Re-sync the shape mask on every press: the shape can change or be
        -- cleared between presses, and a cleared shapeMask is emptied + hidden
        -- rather than destroyed -- left attached it would blank the overlay.
        -- A shape swap keeps the same mask object (re-textured), so it stays.
        local shape, mask = IconShape(icon)
        if ov._shapeMask and ov._shapeMask ~= mask then
            pcall(ov._tex.RemoveMaskTexture, ov._tex, ov._shapeMask)
            ov._shapeMask = nil
        end
        if mask and not ov._shapeMask then
            pcall(ov._tex.AddMaskTexture, ov._tex, mask)
            ov._shapeMask = mask
        end
        local result, cr, cg, cb, bsz = StylePush(ov._tex)
        if not result then ov:Hide(); return nil end
        -- Shaped icons expand their icon texture past the frame (and expand the
        -- texcoords to match), so anchor to the frame itself -- the rect the
        -- shapeMask covers -- rather than to the oversized texture.
        local region = (shape and icon) or icon.Icon or icon
        ov:ClearAllPoints()
        ov:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
        ov:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
        local ringTex = shape and ns.CDM_SHAPE_BORDERS and ns.CDM_SHAPE_BORDERS[shape]
        if result == "border" and ringTex then
            ov._tex:Hide()
            if ov._borderEdges then for j = 1, 4 do ov._borderEdges[j]:Hide() end end
            local ring = EnsureShapeRing(ov)
            ring:SetTexture(ringTex)
            ring:SetVertexColor(cr, cg, cb, 1)
            ring:ClearAllPoints(); ring:SetAllPoints(ov)
            ring:Show()
        elseif result == "border" then
            ov._tex:Hide()
            if ov._shapeRing then ov._shapeRing:Hide() end
            local edges = EnsureBorderEdges(ov)
            for j = 1, 4 do edges[j]:SetVertexColor(cr, cg, cb, 1) end
            edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", ov); edges[1]:SetPoint("TOPRIGHT", ov); edges[1]:SetHeight(bsz); edges[1]:Show()
            edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", ov); edges[2]:SetPoint("BOTTOMRIGHT", ov); edges[2]:SetHeight(bsz); edges[2]:Show()
            edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT"); edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT"); edges[3]:SetWidth(bsz); edges[3]:Show()
            edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT"); edges[4]:SetWidth(bsz); edges[4]:Show()
        else
            ov._tex:Show()
            if ov._borderEdges then for j = 1, 4 do ov._borderEdges[j]:Hide() end end
            if ov._shapeRing then ov._shapeRing:Hide() end
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

    -- Reverse lookup: the primary itemID of the item preset that owns a given
    -- alt/current-tier itemID (e.g. Concentrated Health Potion 271884 ->
    -- 241304). Bar icons for these presets always key off the fixed primary
    -- id (see silvermoon_health's itemID/altItemIDs split), but a press can
    -- report any owned tier's itemID, so OnPress needs to resolve it back.
    local _presetPrimaryByAltID
    local function PresetPrimaryItemID(itemID)
        if not _presetPrimaryByAltID then
            _presetPrimaryByAltID = {}
            for _, pr in ipairs(ns.CDM_ITEM_PRESETS or {}) do
                if pr.altItemIDs then
                    for _, alt in ipairs(pr.altItemIDs) do
                        _presetPrimaryByAltID[alt] = pr.itemID
                    end
                end
            end
        end
        return _presetPrimaryByAltID[itemID]
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
        elseif actionType == "item" then
            -- On-use trinkets/potions/healthstones placed directly on the
            -- action bar: hand back the itemID as a second return. Bar icons
            -- for these track by NEGATIVE identity (-itemID for item presets,
            -- -invSlot for "whatever's equipped in slot X" -- see
            -- ns.INV_SLOT_NAMES / the <= -100 item-preset branch above), not a
            -- resolved spellID, so the caller builds the matching keys itself.
            return nil, id
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
        local sid, itemID = SlotSpellID(slot)
        if not sid and not itemID then return end

        local pressedSet = sid and SpellIdSet(sid) or {}
        if itemID then
            -- Item-preset icons (potions, healthstones, custom item ids) key
            -- off -itemID; equipment-slot icons (trinkets -13/-14, or any
            -- user-added slot) key off -invSlot for whatever's equipped there.
            -- Match both, plus the item's own on-use spell for the rarer case
            -- of it being tracked as a plain Custom Spell entry instead.
            pressedSet[-itemID] = true
            local primaryItemID = PresetPrimaryItemID(itemID)
            if primaryItemID then pressedSet[-primaryItemID] = true end
            for invSlot in pairs(ns.INV_SLOT_NAMES) do
                if GetInventoryItemID("player", invSlot) == itemID then
                    pressedSet[-invSlot] = true
                end
            end
            local _, useSpellID = C_Item.GetItemSpell(itemID)
            if useSpellID then
                for k in pairs(SpellIdSet(useSpellID)) do pressedSet[k] = true end
            end
        end
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

    -- Click-routed keybinds (Bars 9/10, empower spells, custom paging) go
    -- through the button via SetOverrideBindingClick and never fire the native
    -- commands hooked below; the EAB PostClick hook publishes them here.
    -- PostClick runs after Blizzard's click handler returns, downstream of its
    -- protected item-use calls -- same taint posture as the native hooks.
    _G._EUI_OnActionButtonPress = function(btn, down, bindCmd)
        -- Down edge only: buttons register both edges, and in key-up mode the
        -- key is already released by the up click.
        if not down or not btn or not bindCmd or not _anyPressMirror then return end
        -- Keyboard evidence (a real mouse click must not mirror): a held
        -- binding key proves keyboard, but wheel binds are never IsKeyDown, so
        -- the cursor-rect test covers those. Only miss: a wheel bind pressed
        -- while the cursor rests on its own button.
        local k1, k2 = GetBindingKey(bindCmd)
        local b1, b2 = BaseKey(k1), BaseKey(k2)
        local keyHeld = (b1 and IsKeyDown(b1)) or (b2 and IsKeyDown(b2))
        if not keyHeld and btn.IsUnderMouse and btn:IsUnderMouse() then return end
        OnPress(btn, bindCmd)
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

    local ev = ns.TakeShell()
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
