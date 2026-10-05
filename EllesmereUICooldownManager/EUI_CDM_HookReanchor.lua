if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookReanchor.lua
--
--  The entry pool, sorting and CollectAndReanchor.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME = ns.ECME
local barDataByKey = ns.barDataByKey
local cdmBarFrames = ns.cdmBarFrames
local cdmBarIcons = ns.cdmBarIcons
local _ecmeFC = ns._ecmeFC
local FC = ns.FC
local GetTime = GetTime

local hookFrameData, VIEWER_TO_BAR = I.hookFrameData, I.VIEWER_TO_BAR
local IsRouteMapBuilt, ResolveCDIDToBar = I.IsRouteMapBuilt, I.ResolveCDIDToBar
local ResolveFrameSpellID, ResolveSpellSettings = I.ResolveFrameSpellID, I.ResolveSpellSettings
local IsFrameIncluded, CategorizeFrame = I.IsFrameIncluded, I.CategorizeFrame
local DecorateFrame, _trinketFrames = I.DecorateFrame, I._trinketFrames
local _trinketItemCache, ApplySpellDesaturation = I._trinketItemCache, I.ApplySpellDesaturation
local GetOrCreateTrinketFrame = I.GetOrCreateTrinketFrame
local UpdateTrinketCooldown, UpdateTrinketFrame = I.UpdateTrinketCooldown, I.UpdateTrinketFrame
local _injectedCustomBuffFrames, _presetFrames = I._injectedCustomBuffFrames, I._presetFrames
local _RegisterPresetLive = I._RegisterPresetLive
local GetOrCreateCustomBuffFrame = I.GetOrCreateCustomBuffFrame
local GetOrCreateEmptySlotFrame = I.GetOrCreateEmptySlotFrame
local GetOrCreateItemPresetFrame = I.GetOrCreateItemPresetFrame
local GetOrCreatePlaceholderFrame = I.GetOrCreatePlaceholderFrame
local HideAllInjectedCustomBuffs = I.HideAllInjectedCustomBuffs
local HideAllPlaceholders = I.HideAllPlaceholders
local ResolvePlaceholderIconSID = I.ResolvePlaceholderIconSID
local _customAuraTimers, ApplyPresetGCDSwipe = I._customAuraTimers, I.ApplyPresetGCDSwipe
local PotSwap = I.PotSwap

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

local function CollectAndReanchor()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.enabled then return end

    if ns.RebuildCDMSpellCaches then ns.RebuildCDMSpellCaches() end

    -- Safety: if RebuildSpellRouteMap has never run successfully (API was
    -- unavailable during zone-in rebuild, e.g. fast arena transitions),
    -- attempt a fresh rebuild now. Test the build sentinel, NOT the
    -- diversion maps (which can legitimately be empty for users with no
    -- diversions) and NOT _cdidRouteMap (lazy cache, empty post-build).
    if not IsRouteMapBuilt() and ns.RebuildSpellRouteMap then
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

    -- "Replace with Buff": per-bar set of cooldown ids whose slot an active buff
    -- frame took this pass (read by the compaction after Phase 1). Per-bar
    -- tables are wiped, never recreated. Untouched for profiles without a mapping.
    if ns._cdmAnyBuffReplace then
        local rb = ns._replacedByBar
        if rb then
            for _, t in pairs(rb) do wipe(t) end
        else
            ns._replacedByBar = {}
        end
    end

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
                            -- "Replace with Buff": the cooldown this buff stands in for on
                            -- the bar it routes to, or nil. Table reads only, and only
                            -- when a mapping exists anywhere (nil for everyone else).
                            local repSID
                            if ns._cdmAnyBuffReplace then
                                repSID = (dedupKey and ns._buffReplaceTargetCd[dedupKey])
                                    or ns._buffReplaceTarget[displaySID]
                                    or (baseSID and ns._buffReplaceTarget[baseSID]) or nil
                            end
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
                                        if repSID then
                                            -- Replacement: takes the COOLDOWN's identity, so Phase 3
                                            -- ranks it in that slot and the claim set covers the
                                            -- cooldown; the cooldown's own frame is dropped from this
                                            -- pass by the compaction after Phase 1.
                                            fc.spellID = repSID
                                            fc.isHostedBuff = nil
                                            fc.replacesCd = repSID
                                            local rb = ns._replacedByBar[targetBar]
                                            if not rb then rb = {}; ns._replacedByBar[targetBar] = rb end
                                            rb[repSID] = true
                                        else
                                            fc.spellID = baseSID or displaySID
                                            fc.replacesCd = nil
                                            -- Hosted buff: Phase 3 ranks it by its hosted
                                            -- MARKER slot, independent of the same spell's
                                            -- cooldown entry on this bar.
                                            fc.isHostedBuff = true
                                        end
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
                                    -- A replacement buff never reserves a slot of its own: while it
                                    -- is missing, the cooldown it stands in for owns the slot.
                                    if hostCD and not repSID then showInactive = true end
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
                                    if hostCD and not repSID then
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
                                    if repSID then showInactive = false end
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
                           and not ns.CdClaimMarkerToCdID(sid)
                           and not ns._HealthstoneHiddenByPact(-sid) then
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
                                        total = ns._ReadItemPresetCount(f)
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

    -- "Replace with Buff": an active replacement frame and the cooldown it stands
    -- in for share one slot identity, so drop the cooldown's own frame from this
    -- pass. It takes the unclaimed park in Phase 4 and returns on the reanchor
    -- the buff frame's own OnActiveStateChanged already queues at falloff.
    if ns._cdmAnyBuffReplace and ns._replacedByBar then
        for bk, targets in pairs(ns._replacedByBar) do
            local frames = next(targets) and cdFrames[bk]
            if frames then
                for i = #frames, 1, -1 do
                    local fc = _ecmeFC[frames[i]]
                    if fc and not fc.replacesCd and fc.spellID then
                        local hit = targets[fc.spellID]
                            or (fc.baseSpellID and targets[fc.baseSpellID])
                        if not hit then
                            for t in pairs(targets) do
                                if ns.IsVariantOf(fc.spellID, t) then hit = true; break end
                            end
                        end
                        if hit then table.remove(frames, i) end
                    end
                end
            end
        end
    end

    -- Talent Conditions: a cooldown whose per-spell conditions do not hold this pass is
    -- dropped like an unlearned spell (EllesmereUICdmTalentConditions.lua). A replacement
    -- buff follows its cooldown's conditions. Session-gated: skipped entirely until some
    -- spell has a condition.
    if ns._cdmAnyTalentCond then ns.TalentCondFilterPass(cdFrames) end

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
                        elseif sid and ns.IsEmptySlotMarker(sid) then
                            -- Empty Slot: pure grid spacer, no live state to
                            -- push. Must be tested before the item-preset
                            -- branch: it is also <= -100.
                            local f = GetOrCreateEmptySlotFrame(sid)
                            frames[#frames + 1] = f
                            local fc = FC(f)
                            fc.barKey = barKey; fc.spellID = sid
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
                                and not ns._HealthstoneHiddenByPact(itemID)
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
                                        total = ns._ReadItemPresetCount(f)
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
                                -- Keep saved placement, but do not inject an unlearned talent.
                                if isCustomSpell then
                                    isCustomSpell = ns.IsSpellInPlayerBook(sid, false)
                                        or C_SpellBook.IsSpellKnownOrInSpellBook(sid, Enum.SpellBookSpellBank.Pet, false)
                                end
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
                                        tex:SetAllPoints(); ns.CdmOwnIconCrop(tex)
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
                                    local effS = ns.GetSpellCdStateEffect(srcList[i], ssS)
                                    if effS == "hiddenOnCDShift" or effS == "hiddenReadyShift"
                                       or effS == "hiddenUnusableShift" then
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
                        local hcd = ns.CdmDurationHideFor(frame, barKey, hideCDText)
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
    if ns.RefreshStaleCDMKeybinds then ns.RefreshStaleCDMKeybinds() end
end
ns.CollectAndReanchor = CollectAndReanchor

I.CollectAndReanchor = CollectAndReanchor
I.broken = false
