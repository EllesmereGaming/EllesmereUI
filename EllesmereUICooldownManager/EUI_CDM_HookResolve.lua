if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookResolve.lua
--
--  Spell id resolution and the spell route map (which bar a cooldown id
--  belongs to).
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME = ns.ECME
local ResolveInfoSpellID = ns.ResolveInfoSpellID
local _ecmeFC = ns._ecmeFC

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
                if not ns.CdStateShifts(eff) then
                    local cas = ns.GetEffectiveCustomActiveState(sid)
                    if cas and cas.cdStateEffect then eff = cas.cdStateEffect end
                end
            end
            if ns.CdStateShifts(eff) then return true end
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
                -- This replaced any CD-state glow on the shared overlay: the memo
                -- follows the visual, and the glow is owed back when the active
                -- window ends (below). A Blackout keeps its own overlay.
                local bo = fd.blackoutOverlay
                if fd._cdStateGlowOn and not (bo and bo._glowActive) then
                    fd._cdStateGlowOn = false
                    fd._cdGlowOwed = true
                end
            end
        end
    elseif fd._activeGlowOn then
        if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
        fd._activeGlowOn = false
        -- A CD-state glow this replaced or held back lights now, not on the
        -- icon's next cooldown edge: a buff that outlasts its cooldown ends
        -- with no further cooldown push to re-run that decision.
        if fd._cdGlowOwed then ns.CdGlowKick(frame) end
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
-- "Replace with Buff" (per-spell cd/util setting): buff identity -> the cooldown
-- spellID whose slot the buff's viewer frame takes while the aura is active.
-- Spell-keyed map is variant-expanded on write; the cooldownID map serves
-- cd-claimed collided slots (numeric keys, so the collect pass never concats).
-- Read only while ns._cdmAnyBuffReplace is set. On ns: 200-local cap.
ns._buffReplaceTarget = {}
ns._buffReplaceTargetCd = {}
-- Bars holding at least one replacement: the viewer-alpha vote in
-- _CDMApplyVisibility reads it (a replacement frame stays parented to the
-- BuffIcon viewer, like a hosted buff, so its bar must keep that viewer lit).
ns._buffReplaceBars = {}
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
    wipe(ns._buffReplaceTarget)
    wipe(ns._buffReplaceTargetCd)
    wipe(ns._buffReplaceBars)
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
    -- Pass 3c: "Replace with Buff". A cd/util entry can name a tracked buff
    -- whose viewer frame takes the cooldown's slot while the aura is active.
    -- Divert the buff exactly like a hosted buff (same map, same variant
    -- expansion) and remember which cooldown it stands in for; the collect
    -- pass swaps the frames. Gated: a profile with no mapping skips the pass.
    if ns._cdmAnyBuffReplace then
        for _, bd in ipairs(p.cdmBars.bars) do
            if bd.enabled and not bd.isGhostBar
               and bd.barType ~= "buffs" and bd.barType ~= "custom_buff" then
                local sd = ns.GetBarSpellData(bd.key)
                local store = sd and sd.assignedSpells and ns.GetSpellSettingsStore(bd.key)
                if store then
                    -- One buff frame can stand in for ONE cooldown per bar; the
                    -- setter enforces it on write, this guards data that arrived
                    -- by copy (spec/RPT sync). First assigned entry wins.
                    local seenBuff
                    for _, sid in ipairs(sd.assignedSpells) do
                        if type(sid) == "number" and sid > 0 then
                            local ss = store[sid]
                            local buffSid = ss and rawget(ss, "replaceBuffID")
                            if type(buffSid) == "number" and buffSid > 0 then
                                local buffCd = rawget(ss, "replaceBuffCdID")
                                local ident = (type(buffCd) == "number" and buffCd > 0) and -buffCd or buffSid
                                seenBuff = seenBuff or {}
                                if not seenBuff[ident] then
                                    seenBuff[ident] = true
                                    ns._buffReplaceBars[bd.key] = true
                                    if ident < 0 then
                                        _divertedBuffCdIDs[buffCd] = bd.key
                                        ns._buffReplaceTargetCd[buffCd] = sid
                                    else
                                        StoreDirect(_divertedSpellsBuff, buffSid, bd.key)
                                        SVV(ns._buffReplaceTarget, buffSid, sid, false)
                                    end
                                end
                            end
                        end
                    end
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

I.ResolveCDIDToBar, I.ResolveFrameSpellID = ResolveCDIDToBar, ResolveFrameSpellID
I.ResolveSpellSettings = ResolveSpellSettings
I.IsRouteMapBuilt = function() return _routeMapBuilt end
I.broken = false
