if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Reconcile.lua
--
--  First login capture, reseeding, drops, the hidden-channel reader and buff
--  families.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local ALL_RACIAL_SPELLS, ECME, _myRacialsSet = I.ALL_RACIAL_SPELLS, I.ECME, I._myRacialsSet
local GHOST_CD_BAR_KEY, MAIN_BAR_KEYS = I.GHOST_CD_BAR_KEY, I.MAIN_BAR_KEYS
local SaveCurrentSpecProfile, barDataByKey = I.SaveCurrentSpecProfile, I.barDataByKey
local CaptureCDMPositions = I.CaptureCDMPositions

-------------------------------------------------------------------------------
--  CDM Bar: First Login Capture
-------------------------------------------------------------------------------
local function CDMFirstLoginCapture()
    local p = ECME.db.profile
    local captured = CaptureCDMPositions()

    for _, barData in ipairs(p.cdmBars.bars) do
        local cap = captured[barData.key]
        if cap then
            -- Icon size: visual size from child icon (base width * child scale).
            if cap.iconSize then
                barData.iconSize = cap.iconSize
            end
            -- Spacing (icon padding from Edit Mode setting)
            if cap.spacing then
                barData.spacing = cap.spacing
            end
            -- Rows (counted from distinct Y positions of visible icons)
            if cap.numRows then
                barData.numRows = cap.numRows
            end
            if cap.isHorizontal ~= nil then
                if not cap.isHorizontal then barData.growDirection = "DOWN" end
                barData.verticalOrientation = not cap.isHorizontal
            end
            -- Position: no scale division needed (scale is always 1)
            if cap.point then
                p.cdmBarPositions[barData.key] = {
                    point = cap.point, relPoint = cap.relPoint,
                    x = cap.x, y = cap.y,
                }
            end
        end
    end

    ECME.db.sv._capturedOnce_CDM = true
end

--- Re-seed assignedSpells from live cdmBarIcons. Appends any positive spell IDs present on the
--- live bars but missing from assignedSpells. Called after CollectAndReanchor so the preview stays in sync with what the player actually sees on their CDM bars.
function ns.ReseedAssignedSpellsFromLiveIcons(cdUtilOnly)
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    -- Both-state guards (mirror EnsureAssignedSpells). This appends live-icon spells back into
    -- assignedSpells; without these it could re-materialize a spell that is currently HIDDEN
    -- (ghosted) or already OWNED by another bar, recreating a both-state. The sole caller
    -- (RepopulateFromBlizzard) pre-wipes the ghost and Blizzard-sourced assignments, so these are normally no-ops -- but they keep Reseed safe regardless of caller or ordering.
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local aprof = sp and sk and sp[sk]
    -- Skip entirely while an imported layout is pending its first-load ghosting: its tracked
    -- spells spill onto default bars until the migration ghosts them, and materializing those spills would defeat the import-authoritative hide.
    if aprof and aprof._importGhostMode then return end

    -- Unlike every other assignedSpells mutation site (the picker's add/remove/move calls,
    -- BuildAllCDMBars), this one never marked the cached render-order map (spellOrder,
    -- EUI_CDM_HookReanchor.lua) dirty -- so a spell this pass just materialized had no key in the
    -- STALE cache, fell through every OrderKeyFor match probe, and rendered via the raw
    -- layoutIndex spillover fallback (the same imprecise path #1211/#1420 already fixed once)
    -- instead of the position it was just given. Field-confirmed: Cobra Shot's assignedSpells
    -- entry was correct and it still rendered first. Set once, only when something actually inserted.
    local didInsert = false

    -- Spell -> owning bar (variant-aware), built once. A live icon whose stored owner is a DIFFERENT bar is a transient spillover we must not materialize.
    local ownerOf
    -- One-racial-total invariant (see NormalizeRacialAssignments): while ANY
    -- racial-family entry is placed on any bar, the racial slot is spoken for.
    -- Materializing a second racial slot here (a live racial icon transiting a
    -- default bar during the login route-not-ready window) creates the
    -- dual-state the normalize dedupe then resolves -- which historically
    -- deleted the user's custom placement.
    local anyRacialOwned = false
    if aprof and aprof.barSpells and ns.StoreVariantValue then
        for k, bsd in pairs(aprof.barSpells) do
            if k ~= GHOST_CD_BAR_KEY
               and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                for _, csid in ipairs(bsd.assignedSpells) do
                    if type(csid) == "number" and csid > 0 then
                        ownerOf = ownerOf or {}
                        ns.StoreVariantValue(ownerOf, csid, k, false)
                        if ALL_RACIAL_SPELLS[csid] then anyRacialOwned = true end
                    end
                end
            end
        end
    end

    local ghostSd = ns.GetBarSpellData and ns.GetBarSpellData(GHOST_CD_BAR_KEY)
    local ghostList = ghostSd and ghostSd.assignedSpells
    local FindVar = ns.FindVariantIndexInList

    -- Cd-claimed collided-buff slots (cd-claim markers in assignedSpells, see ns.CdClaimMarker)
    -- are tracked by COOLDOWN ID, not by the shared spellID. Materializing such an icon's shared
    -- spellID here would, at the next route rebuild, drag the UNCLAIMED twin onto the claiming bar
    -- too -- defeating the claim's one-slot-only contract. Built once; stays nil (guard inert, zero cost) unless a collided claim exists anywhere.
    local claimedCd
    if aprof and aprof.barSpells then
        for _, bsd in pairs(aprof.barSpells) do
            local bsdClaims = type(bsd) == "table" and ns.CollectCdClaimSet(bsd)
            if bsdClaims then
                for cdID in pairs(bsdClaims) do
                    claimedCd = claimedCd or {}
                    claimedCd[cdID] = true
                end
            end
        end
    end

    for _, barData in ipairs(p.cdmBars.bars) do
        -- cdUtilOnly (the automatic reseed path): buff-family bars are picker-authoritative --
        -- materializing live buff icons would reintroduce the secret-ID drift duplicate-slot bug
        -- the options materializer's skip exists to prevent. The manual Repopulate flow passes nothing and keeps its full sweep.
        if not barData.isGhostBar
           and barData.key ~= "buffs"
           and (barData.barType == "cooldowns" or barData.barType == "utility"
                or (barData.barType == "buffs" and not cdUtilOnly)
                or MAIN_BAR_KEYS[barData.key]) then
            local sd = ns.GetBarSpellData(barData.key)
            local icons = ns.cdmBarIcons and ns.cdmBarIcons[barData.key]
            -- Talent Conditions: the frames the reanchor filter dropped from this bar are
            -- present, only hidden. They walk after the live icons, so a hidden spell keeps
            -- (or regains) its slot and its conditions stay reachable from the preview.
            local tcHidden = ns._cdmAnyTalentCond and ns.TalentCondHiddenFrames(barData.key)
            local nLive = 0
            if icons then while icons[nLive + 1] do nLive = nLive + 1 end end
            local nWalk = nLive + (tcHidden and #tcHidden or 0)
            if sd and (icons or nWalk > 0) then
                if not sd.assignedSpells then sd.assignedSpells = {} end
                -- Insert each missing spell right after its left neighbour in the live icon order
                -- (already Blizzard-layout order from CollectAndReanchor) instead of appending, so
                -- the seeded list matches what the player sees and a re-talented cooldown returns
                -- to its slot, not the tail. Presence is VARIANT-AWARE and the cursor is a
                -- POSITION, not an id: an exact-match set misses a stored entry when the live icon
                -- reports a different variant form (fc.spellID can be the talent override, e.g.
                -- Mongoose Bite 259387, while the slot holds the base Raptor Strike 186270 the
                -- options normalize pass wrote). Each reload then re-inserts the live form at
                -- Blizzard's position and the next normalize dedupes in its favor -- permanently snapping the user's saved order back to Blizzard order. A by-value cursor lookup fails the same way and dumps inserts at slot 1.
                local insertPos = nil
                for walk = 1, nWalk do
                    local icon
                    if walk <= nLive then
                        icon = icons[walk]
                    else
                        icon = tcHidden[walk - nLive]
                        -- A hidden frame has no on-screen neighbour, so place it beside its
                        -- live neighbours in Blizzard's layout: after the nearest same-viewer
                        -- icon below its layoutIndex, else before the nearest one above, else
                        -- after the last live slot (the cursor as it stands).
                        local L, vf = icon.layoutIndex, icon.viewerFrame
                        if L and vf and FindVar then
                            local predLI, predAt, succLI, succAt
                            for j = 1, nLive do
                                local ic = icons[j]
                                local li = ic.viewerFrame == vf and ic.layoutIndex
                                local fcJ = li and ns._ecmeFC[ic]
                                local at = fcJ and fcJ.spellID and FindVar(sd.assignedSpells, fcJ.spellID)
                                if at then
                                    if li < L then
                                        if not predLI or li > predLI then predLI, predAt = li, at end
                                    elseif not succLI or li < succLI then
                                        succLI, succAt = li, at
                                    end
                                end
                            end
                            if predAt then
                                insertPos = predAt
                            elseif succAt then
                                insertPos = succAt - 1
                            end
                        end
                    end
                    local fc = ns._ecmeFC and ns._ecmeFC[icon]
                    local sid = fc and fc.spellID
                    -- Skip hosted-buff frames and their placeholders: their bar membership is the
                    -- hosted MARKER entry, and their positive spellID would materialize the same
                    -- spell's COOLDOWN form. But DO advance the cursor over their marker: on a mixed
                    -- bar a spell re-inserted after a buff must land after the buff's marker, not squeezed back next to the previous CD spell.
                    local fdRS = ns._hookFrameData and ns._hookFrameData[icon]
                    if (fc and fc.isHostedBuff) or icon._isPlaceholderFrame
                       or (fdRS and fdRS._isBuffViewerFrame) then
                        local hSid = fc and fc.spellID
                        if type(hSid) == "number" and hSid > 0
                           and ns.HostedBuffMarkerToSpell
                           and not (fc and fc._overflowLayoutBar) then
                            for i = 1, #sd.assignedSpells do
                                local dec = ns.HostedBuffMarkerToSpell(sd.assignedSpells[i])
                                if dec and (dec == hSid
                                    or (ns.IsVariantOf and ns.IsVariantOf(dec, hSid))) then
                                    -- Forward-only: never drag the cursor backward.
                                    if not insertPos or i > insertPos then insertPos = i end
                                    break
                                end
                            end
                        end
                        sid = nil
                    end
                    -- Skip overflow-diverted icons: they render on this bar only for the session but belong to their source bar's assignedSpells (mirrors the EnsureAssignedSpells skip).
                    if sid and fc and fc._overflowLayoutBar then
                        sid = nil
                    end
                    -- Skip cd-claimed collided-buff icons: their membership is the cooldownID claim, never a spellID slot (mirrors the hosted-buff membership rule above).
                    if sid and claimedCd and icon.cooldownID
                       and claimedCd[icon.cooldownID] then
                        sid = nil
                    end
                    if type(sid) == "number" and sid ~= 0 then
                        -- FindVar handles negatives by exact scan internally, and variant matching is a strict superset of exact equality for stored positives -- no exact fallback needed.
                        local at = FindVar and FindVar(sd.assignedSpells, sid)
                        if at then
                            -- Already has a slot (any variant form, or a custom trinket/item marker): advance the cursor so the next NEW spell lands after it, matching on-screen order.
                            insertPos = at
                        elseif sid > 0 then
                            -- Never materialize a hidden (ghosted) spell, or a spell a DIFFERENT bar already owns (variant-aware).
                            local owner = ownerOf and ns.ResolveVariantValue
                                          and ns.ResolveVariantValue(ownerOf, sid)
                            local ghosted = ghostList and FindVar and FindVar(ghostList, sid)
                            -- Racial-family guard: never mint a second racial slot
                            -- while one is placed anywhere (anyRacialOwned above).
                            local racialBlocked = anyRacialOwned and ALL_RACIAL_SPELLS[sid]
                            if not ghosted and not racialBlocked and not (owner and owner ~= barData.key) then
                                -- Store the BASE form, matching what the options normalize pass writes -- otherwise this pass persists the talent-override form and the two writers diverge (exports could ship either).
                                -- Only trust that substitution when Blizzard's OWN cooldownInfo already
                                -- recorded a base/display split for THIS icon (fc.baseSpellID ~= fc.resolvedSid,
                                -- e.g. a Wither slot whose base is Immolate). GetBaseSpell can also tie
                                -- together spells with no override relationship at all -- field-confirmed
                                -- for Cobra Shot -> Arcane Shot, and #842 saw the same API do it to SV Kill
                                -- Command -- and substituting on that spurious tie stores an id the live
                                -- spell never actually shares a slot with, orphaning it as a permanent spillover.
                                local nsid = sid
                                if C_Spell and C_Spell.GetBaseSpell
                                   and fc.baseSpellID and fc.resolvedSid
                                   and fc.baseSpellID ~= fc.resolvedSid then
                                    local b = C_Spell.GetBaseSpell(sid)
                                    if b and b > 0 then nsid = b end
                                end
                                local pos = insertPos and (insertPos + 1) or 1
                                table.insert(sd.assignedSpells, pos, nsid)
                                insertPos = pos
                                didInsert = true
                            end
                        end
                    end
                end
            end
        end
    end
    if didInsert then ns._spellOrderDirty = true end
end

-- Parent-facing bridge for the automatic/export-time reconcile: cd and utility bars only
-- (buff-family excluded -- picker-authoritative). The export path nil-checks this, so a disabled CDM child is a clean no-op.
EllesmereUI.CDMReconcileActiveSpecSpells = function()
    ns.ReseedAssignedSpellsFromLiveIcons(true)
    -- Export serializes immediately after this bridge: erase any item rows
    -- the reseed just mirrored so exports can never ship them.
    if ns.PruneEquipmentBuffRows then ns.PruneEquipmentBuffRows() end
end

-- Shared after-combat waiter for the automatic keep/drop pass below, via the
-- module combat queue rather than the module's big shared event handler
-- further down this file -- that frame's registration set is static and
-- must not churn. The queue holds PLAYER_REGEN_ENABLED only while something
-- is pending, so an idle session carries zero event traffic from this path.
local ArmCDMDropRegenWaiter
do
    local function DropPassAfterCombat()
        ns._cdmDropPending = false
        if ns.RequestCDMDropPass then ns.RequestCDMDropPass("regen") end
    end
    ArmCDMDropRegenWaiter = function()
        ns._cdmDropPending = true
        ns.CombatQueue.Defer("CDMDropPass", DropPassAfterCombat)
    end
end

--- ns.ReconcileAssignedSpellDrops(barKey): single resident implementation of
--- the 3-way keep/drop pass (formerly inline in the options panel's
--- EnsureAssignedSpells). Interactive options edits call this directly;
--- the automatic triggers (once-per-spec reseed, settings close) arrive
--- through ns.RequestCDMDropPass below. Every guard fails OPEN to keep-all:
--- no profile, no migration, mid-import, data not yet loaded, provider
--- unreachable, or combat all return the bar's spell data unchanged rather
--- than risk dropping a legitimately-owned entry.
function ns.ReconcileAssignedSpellDrops(barKey)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return sd end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local aprof = sp and sk and sp[sk]
    if not aprof or not aprof._barFilterModelV6 then return sd end
    -- aprof._importGhostMode is the options panel's "importPending" (same
    -- field, EUI_CooldownManager_Options.lua ~6367-6373): a mid-import pass
    -- would mark spilled tracked spells "assigned" and permanently defeat
    -- import-authoritative ghosting, so the whole pass no-ops instead.
    if aprof._importGhostMode then return sd end
    if not ns._cdmDataLoaded then return sd end

    -- GHOST BAR EXEMPTION (field 2026-08-13, hunter Scare Beast classified
    -- keep=false in a reconcile dry-run): the ghost store holds spells the user DELIBERATELY removed --
    -- not-shown by definition, often uncatalogued -- and dropping a ghost entry
    -- erases the removal decision, so the spell re-materializes onto the visible
    -- bar. The classification ladder must never see this pseudo-bar.
    if barKey == GHOST_CD_BAR_KEY then return sd end
    local bd = barDataByKey[barKey]
    if ns.IsBarBuffFamily and ns.IsBarBuffFamily(bd or barKey) then
        -- Buff-family drop needs the persisted variant-alias ledger so a
        -- dual-tracked spell's currently-absent half never sinks its present
        -- half; ns.ReconcileBuffFamilyDrops (further down in this file)
        -- is the single implementation, gated on that ledger. Fails open to
        -- the unmodified sd if the ledger-gated pass isn't available.
        return (ns.ReconcileBuffFamilyDrops and ns.ReconcileBuffFamilyDrops(barKey)) or sd
    end
    local bt = bd and bd.barType
    if not (bt == "cooldowns" or bt == "utility") then return sd end

    if InCombatLockdown() then
        ArmCDMDropRegenWaiter()
        return sd
    end

    if not sd.assignedSpells or #sd.assignedSpells == 0 then return sd end
    if not ns.EnumerateCDMViewerSpells then return sd end

    local NormalizeToBase = ns.NormalizeToBase
    local ResolveToLive   = ns.ResolveToLive

    local displayed
    for _, e in ipairs(ns.EnumerateCDMViewerSpells(false)) do
        local sid = e.sid
        if type(sid) == "number" and sid > 0 then
            displayed = displayed or {}
            displayed[sid] = true
            displayed[NormalizeToBase(sid)] = true
            local ov = ResolveToLive(sid)
            if ov then displayed[ov] = true end
        end
    end
    if not (displayed and next(displayed)) then return sd end

    -- Blizzard's tracked-cooldown catalog (talent-independent, arrangement-
    -- aware, and category-0/1/5/7-aware once the picker's category-set
    -- constants land) is the source untalented spells were materialized
    -- from; lets the keep test below also drop an untalented spell the user
    -- removed from tracking, invisible to `displayed` since untalented
    -- spells never get a live frame. nil provider -> untalented entries kept.
    local catalogSet
    if ns.EnumerateCDMSettingsCatalog then
        local cat = ns.EnumerateCDMSettingsCatalog(ns.CDM_ICON_CD_CATS)
        if cat then
            catalogSet = {}
            local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            local function AddCatalogVariant(v)
                if type(v) == "number"
                   and not (issecretvalue and issecretvalue(v))
                   and v > 0 then
                    catalogSet[v] = true
                end
            end
            -- Per-category live-set lookup for the hidden/removed check below
            -- (ns.CDMEntryHiddenOrRemoved), built once per category the first
            -- time it's seen this pass and reused for every entry in it --
            -- never refetched per id. Cats 0/1 hidden entries already read as
            -- HiddenActive/HiddenPassive and never reach this loop (excluded
            -- by EnumerateCDMSettingsCatalog's own wantSet test); self-mapping
            -- cats 5/7 keep their category when hidden/removed, so THEY need
            -- this extra check to stop a removed entry holding rank forever.
            local liveSetByCat = {}
            for _, ce in ipairs(cat) do
                local info = gci and ce.cdID and gci(ce.cdID)
                local skip = false
                if ns.CDMEntryHiddenOrRemoved then
                    local lsl = liveSetByCat[ce.category]
                    if lsl == nil and ns.CDMBuildLiveCategorySetLookup then
                        lsl = ns.CDMBuildLiveCategorySetLookup(ce.category) or false
                        liveSetByCat[ce.category] = lsl
                    end
                    local verdict = ns.CDMEntryHiddenOrRemoved(ce.cdID, nil, info, lsl)
                    if verdict == "hidden" or verdict == "removed" then skip = true end
                end
                if not skip then
                    local s = ce.sid
                    if type(s) == "number" and s > 0 then
                        catalogSet[s] = true
                        catalogSet[NormalizeToBase(s)] = true
                        local ov = ResolveToLive(s)
                        if ov then catalogSet[ov] = true end
                    end
                    -- Also index every id the entry itself links (spellID/
                    -- overrideSpellID/linkedSpellIDs): a stored BASE id only
                    -- matches the catalog through the entry's own linked set
                    -- once the override talent is dropped and the spellbook
                    -- link goes with it.
                    if info then
                        AddCatalogVariant(info.spellID)
                        AddCatalogVariant(info.overrideSpellID)
                        if info.linkedSpellIDs then
                            for _, lid in ipairs(info.linkedSpellIDs) do
                                AddCatalogVariant(lid)
                            end
                        end
                    end
                end
            end
        end
    end

    local custom  = sd.customSpellIDs
    local racials = _myRacialsSet
    local cdurs   = sd.customSpellDurations
    local sdurs   = sd.spellDurations
    local groups  = sd.customSpellGroups
    local hosted  = sd.hostedBuffSpellIDs
    -- Marker-present set: a hosted buff's PLAIN entry (its cooldown form)
    -- must not borrow the hosted exemption below once its own MARKER entry
    -- exists -- untracking the cooldown should drop it like any other
    -- cooldown while the hosted buff stays.
    local hostedMarkerFor
    if hosted then
        for _, mid in ipairs(sd.assignedSpells) do
            local mSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(mid)
            if mSid then
                hostedMarkerFor = hostedMarkerFor or {}
                hostedMarkerFor[mSid] = true
            end
        end
    end

    -- WoW Forever's full catalogue set, built on first need (see below).
    local foreverListed
    local writeIdx = 1
    for readIdx = 1, #sd.assignedSpells do
        local id = sd.assignedSpells[readIdx]
        local keep = true
        -- A HOSTED buff is a real buff (never in the Essential/Utility
        -- viewer), so the "owned but not displayed -> drop" test below
        -- would wrongly delete it; always keep, like a custom spell ID/racial.
        if type(id) == "number" and id > 0
           and not (custom and custom[id])
           and not (racials and racials[id])
           and not (cdurs and cdurs[id])
           and not (sdurs and sdurs[id])
           and not (groups and groups[id])
           and not (hosted and hosted[id]
                    and not (hostedMarkerFor and hostedMarkerFor[id])) then
            -- Plain Blizzard cooldown. Keep if still displayed OR if the
            -- player no longer HAS the spell (talented out): a talented-out
            -- cooldown must hold its rank so it returns to the SAME slot
            -- when re-talented. Only a spell still OWNED but removed from
            -- Blizzard's CDM tracking (gone from the catalog too) is
            -- genuinely user-cleared -> drop.
            local shown = displayed[id] or displayed[NormalizeToBase(id)]
                          or displayed[ResolveToLive(id)]
            -- IsPlayerSpell is guarded (nil in some contexts): if
            -- unavailable, `have` is falsy so the spell is treated as
            -- untalented (kept unless the catalog says otherwise).
            local have = IsPlayerSpell and (IsPlayerSpell(id)
                         or IsPlayerSpell(NormalizeToBase(id))
                         or IsPlayerSpell(ResolveToLive(id)))
            if shown then
                keep = true
            elseif catalogSet
                   and (catalogSet[id] or catalogSet[NormalizeToBase(id)]
                        or catalogSet[ResolveToLive(id)]) then
                -- Still tracked in Blizzard's catalog, just not displayed:
                -- untalented, conditionally pooled, or a BASE id whose
                -- tracked cooldown is a talent override the player dropped.
                -- Hold rank.
                keep = true
            elseif have then
                -- Owned but no longer tracked: the user cleared it from
                -- Blizzard's CDM tracking -> drop.
                keep = false
            elseif catalogSet and not EllesmereUI.IS_FOREVER then
                -- Untalented: it only reached the preview by being
                -- materialized from the settings catalog, so it must also
                -- LEAVE when removed from tracking -> drop.
                keep = false
            elseif catalogSet then
                -- WoW Forever: the same, but only for an id its catalogue
                -- lists (Not Displayed included). An id it does not list is
                -- a spell this client cannot see (a retail layout's), so it
                -- holds its place instead.
                if foreverListed == nil then
                    foreverListed = ns.CDMForeverListedSet() or false
                end
                keep = not (foreverListed and (foreverListed[id]
                    or foreverListed[NormalizeToBase(id)]
                    or foreverListed[ResolveToLive(id)]))
            else
                -- Untalented with no catalog signal (provider down): hold
                -- rank as the safe fallback so a transient gap never wipes
                -- an untalented assignment.
                keep = true
            end
        end
        if keep then
            sd.assignedSpells[writeIdx] = id
            writeIdx = writeIdx + 1
        end
    end
    for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end

    -- Normalize the hosted-buff representation: a hosted buff owns a MARKER
    -- entry; a plain entry of the same id means the COOLDOWN form. Resolve
    -- each flagged id here, where displayed/catalog sets can tell the forms apart.
    if sd.hostedBuffSpellIDs and ns.HostedBuffMarker then
        local list = sd.assignedSpells
        local ghostSd = ns.GetBarSpellData and ns.GetBarSpellData(GHOST_CD_BAR_KEY)
        local ghostList = ghostSd and ghostSd.assignedSpells
        local FindVar = ns.FindVariantIndexInList
        -- Plain entries claimed by OTHER visible bars (variant-aware): if
        -- the cooldown form lives elsewhere, a plain entry here is a
        -- resurrected artifact of the old shared-id model.
        local claimed
        do
            local bsAll = aprof.barSpells
            if bsAll and ns.StoreVariantValue then
                for k, bsd in pairs(bsAll) do
                    if k ~= barKey and k ~= GHOST_CD_BAR_KEY
                       and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                        for _, sid in ipairs(bsd.assignedSpells) do
                            if type(sid) == "number" and sid > 0 then
                                claimed = claimed or {}
                                ns.StoreVariantValue(claimed, sid, true, false)
                            end
                        end
                    end
                end
            end
        end
        for hsid in pairs(sd.hostedBuffSpellIDs) do
            if type(hsid) == "number" and hsid > 0 then
                local marker = ns.HostedBuffMarker(hsid)
                local markerIdx, plainIdx
                for i = 1, #list do
                    local v = list[i]
                    if v == marker then markerIdx = i
                    elseif v == hsid then plainIdx = i end
                end
                if plainIdx then
                    local isCdForm = (displayed[hsid]
                        or displayed[NormalizeToBase(hsid)]
                        or displayed[ResolveToLive(hsid)]
                        or (catalogSet and (catalogSet[hsid]
                            or catalogSet[NormalizeToBase(hsid)]
                            or catalogSet[ResolveToLive(hsid)]))) and true or false
                    if isCdForm and ghostList and FindVar and FindVar(ghostList, hsid) then
                        isCdForm = false
                    end
                    if isCdForm and claimed and ns.ResolveVariantValue
                       and ns.ResolveVariantValue(claimed, hsid) then
                        isCdForm = false
                    end
                    if markerIdx then
                        if not isCdForm then
                            table.remove(list, plainIdx)
                            ns._spellOrderDirty = true
                        end
                    elseif isCdForm then
                        table.insert(list, plainIdx + 1, marker)
                        ns._spellOrderDirty = true
                    else
                        list[plainIdx] = marker
                        ns._spellOrderDirty = true
                    end
                end
            end
        end
    end

    return sd
end

--- ns.RequestCDMDropPass(reason): fan-out entry point for the AUTOMATIC
--- triggers (once-per-spec reseed, settings close). Bails immediately while
--- the module/spec isn't ready to reconcile (zero cost while disabled);
--- coalesces concurrent requests behind the single pending flag; defers out
--- of combat via the shared regen waiter above. Interactive options edits
--- bypass this and call ns.ReconcileAssignedSpellDrops directly.
function ns.RequestCDMDropPass(reason)
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local aprof = sp and sk and sp[sk]
    if not aprof or not aprof._barFilterModelV6 then return end

    if ns._cdmDropPending then return end -- already scheduled, coalesce

    if InCombatLockdown() then
        ArmCDMDropRegenWaiter()
        return
    end

    -- Every reconcilable bar, not just the two default keys: custom CD/utility
    -- bars carry the same barTypes, and buff-family bars route internally to the
    -- ledger-gated pass (vouched-only, safe to automate). The ghost store is
    -- exempted inside the pass; skipped here too to spare the call.
    for barKey, bd in pairs(barDataByKey) do
        if barKey ~= GHOST_CD_BAR_KEY then
            local bt = bd and bd.barType
            if bt == "cooldowns" or bt == "utility"
               or (ns.IsBarBuffFamily and ns.IsBarBuffFamily(bd or barKey)) then
                ns.ReconcileAssignedSpellDrops(barKey)
            end
        end
    end
    -- Items are preset-lane-only: whatever intake lane just ran (reseed,
    -- spillover, materializer) may have mirrored a native equipment entry
    -- into a store -- the same pass class erases it, so item rows can never
    -- persist. Tracking an item in Blizzard's CDM becomes a store no-op.
    if ns.PruneEquipmentBuffRows then ns.PruneEquipmentBuffRows() end
end

-------------------------------------------------------------------------------
--  Midnight hidden-channel reader (categories 0-8)
--  Blizzard folds both default-hide and user-hide into `category` for cats
--  0-3 (HiddenActive/HiddenPassive), but cats 5-8 self-map onto their OWN
--  category when hidden -- there is no separate isHidden field for them, so a
--  plain category read can never reveal a 5-8 hide; membership in the live
--  category set and isKnown carry that signal instead. GroupBuff (cat 4) is a
--  third, separate system: hidden spellIDs live in a flat array on the active
--  layout. Every provider read here is pcall-degraded: a down/errored read
--  always classifies as visible, so the drop pass this feeds never over-drops
--  on a bad read.
-------------------------------------------------------------------------------

-- Reject secret-tainted/non-positive numbers before they key a table or get compared.
local function _IsUsableSID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0 and id == math.floor(id)
end

-- Reads the ALREADY-BUILT display table, never the provider getters: those run
-- CheckBuildDisplayData, which rebuilds Blizzard's shared tables (and writes the
-- active layout) on OUR stack whenever the provider is dirty -- the HUD viewer
-- drops its OnDataChanged rebuild while hidden, so a post-match read used to
-- taint the viewer until reload. A dirty provider returns nil (not the previous
-- build): callers treat nil as "not ready" and fall back to keep-all/live-pool.
function ns.CDMGetProviderDisplayData(provider)
    if type(provider) ~= "table" or type(provider.GetDisplayData) ~= "function" then
        return nil, nil
    end
    if type(provider.IsDirty) == "function" then
        local okD, dirty = pcall(provider.IsDirty, provider)
        if not okD or dirty then return nil, nil end
    end
    local ok, displayData = pcall(provider.GetDisplayData, provider)
    if not ok or type(displayData) ~= "table" then return nil, nil end
    local ordered = displayData.orderedCooldownIDs
    local infoByID = displayData.cooldownInfoByID
    if type(ordered) ~= "table" or type(infoByID) ~= "table" then return nil, nil end
    return ordered, infoByID
end

-- Active BLIZZARD CDM layout id (the user's "preset"), not to be confused with
-- ns.GetActiveLayoutName (EUI's own account-wide spell-layout system). Used to
-- scope the automatic-reseed session gate by layout as well as spec: a spell
-- only tracked on a preset the user switches to LATER in the session was
-- invisible at the first reseed and must still get its own materialize pass.
function ns.GetActiveCDMLayoutID()
    if not (CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager) then return nil end
    local okLM, layoutManager = pcall(CooldownViewerSettings.GetLayoutManager, CooldownViewerSettings)
    if not okLM or not layoutManager or not layoutManager.GetActiveLayoutID then return nil end
    local okID, layoutID = pcall(layoutManager.GetActiveLayoutID, layoutManager)
    if not okID then return nil end
    return layoutID
end

-- GroupBuff (category 4) hidden check: getter-only on the layout manager, never
-- WriteHiddenGroupBuffsToLayout. No active layout yet (fresh install, never
-- customized) is not "nothing hidden" evidence -- treated as unreachable and kept
-- visible, same as every other fail-open path in this file.
function ns.CDMIsGroupBuffSpellHidden(spellID)
    if not _IsUsableSID(spellID) then return false end
    if not (CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager) then return false end
    local okLM, layoutManager = pcall(CooldownViewerSettings.GetLayoutManager, CooldownViewerSettings)
    if not okLM or not layoutManager then return false end
    local accessOnly = (Enum and Enum.CDMLayoutMode and Enum.CDMLayoutMode.AccessOnly) or false
    local okLayout, layout = pcall(layoutManager.GetActiveLayout, layoutManager, accessOnly)
    if not okLayout or not layout then return false end
    local okList, hiddenList = pcall(CooldownManagerLayout_GetHiddenGroupBuffs, layout)
    if not okList or type(hiddenList) ~= "table" then return false end
    for i = 1, #hiddenList do
        if hiddenList[i] == spellID then return true end
    end
    return false
end

-- Per-category "still a live member of this category" lookup for the cats-5-8 removal
-- signal below. allowUnlearned=true so this is the category's full membership universe,
-- not narrowed to currently-known spells (isKnown is a separate, independent signal in
-- CDMEntryHiddenOrRemoved). Build ONCE per category per pass and reuse for every id in
-- it -- never per id (mirrors Blizzard's own tInvert-on-GetCooldownViewerCategorySet
-- idiom). Returns nil (never an empty table) on failure so a caller checking
-- lookup[id] can tell "couldn't build" from "confirmed empty" -- collapsing the two
-- would make a dead provider read as "everything in this category is gone".
function ns.CDMBuildLiveCategorySetLookup(category)
    if type(category) ~= "number" then return nil end
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then return nil end
    local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
    if not ok or type(ids) ~= "table" then return nil end
    local lookup = {}
    for i = 1, #ids do
        local id = ids[i]
        if _IsUsableSID(id) then lookup[id] = true end
    end
    return lookup
end

-- Classifies one cooldownID against the hidden channel. Returns "hidden", "removed", or
-- nil (visible/keep -- also the result for any missing latch/provider/category match).
-- mergedInfo/rawInfo may be pre-fetched by the caller to batch a scan; liveSetLookup is
-- this id's category lookup from CDMBuildLiveCategorySetLookup above.
function ns.CDMEntryHiddenOrRemoved(cdID, mergedInfo, rawInfo, liveSetLookup)
    if not _IsUsableSID(cdID) then return nil end
    if not ns._cdmDataLoaded then return nil end -- pre-load reads see only static defaults

    local evc = Enum and Enum.CooldownViewerCategory
    local hiddenActive = evc and evc.HiddenActive or -1
    local hiddenPassive = evc and evc.HiddenPassive or -2

    if mergedInfo == nil then
        local provider = CooldownViewerSettings and CooldownViewerSettings.GetDataProvider
                          and CooldownViewerSettings:GetDataProvider()
        if provider then
            local _, infoByID = ns.CDMGetProviderDisplayData(provider)
            if infoByID then mergedInfo = infoByID[cdID] end
        end
    end

    -- Cats 0-3: default-hide and user-hide both fold into `category` -- complete on their
    -- own. A 5-8 entry that took the rare two-hop drag into Hidden also lands here.
    if mergedInfo and (mergedInfo.category == hiddenActive or mergedInfo.category == hiddenPassive) then
        return "hidden"
    end

    local cat = mergedInfo and mergedInfo.category
    local groupBuff = evc and evc.GroupBuff or 4
    local spec5 = evc and evc.SpecAgnosticEssential or 5
    local spec6 = evc and evc.SpecAgnosticTracked or 6
    local equip7 = evc and evc.EquipSlotEssential or 7
    local equip8 = evc and evc.EquipSlotTracked or 8

    -- Only cats 4-8 need the raw (unreconciled) struct below; a mergedInfo hit already
    -- resolved to 0-3 is fully answered (visible) without another provider call.
    if cat == nil or cat == groupBuff or cat == spec5 or cat == spec6 or cat == equip7 or cat == equip8 then
        if rawInfo == nil and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
            if ok then rawInfo = info end
        end
        if cat == nil then cat = rawInfo and rawInfo.category end
    end

    if type(cat) ~= "number" then return nil end -- nothing to classify against: keep

    if cat == groupBuff then
        local sid = (mergedInfo and mergedInfo.spellID) or (rawInfo and rawInfo.spellID)
        if ns.CDMIsGroupBuffSpellHidden(sid) then return "hidden" end
        return nil
    end

    if cat ~= spec5 and cat ~= spec6 and cat ~= equip7 and cat ~= equip8 then
        return nil -- cats 0-3 already resolved above; nothing further indicates hidden/removed
    end
    if rawInfo == nil then return nil end -- provider down: keep

    -- HideByDefault must NOT convict here. Blizzard's own provider proves the
    -- flag is a DEFAULT DISPOSITION, not live state: their CheckBuildDisplayData
    -- remaps HideByDefault entries into the Hidden pseudo-categories for cats
    -- 0-3, but for the self-mapping cats the remap is a deliberate no-op -- a
    -- user-tracked entry KEEPS the flag forever (the un-hide lives elsewhere in
    -- the layout). Convicting on it dropped every default-hidden-but-tracked
    -- SpecAgnostic entry on the first automatic pass (field 2026-08-13: shaman
    -- Gust of Wind). Until a proven per-entry user-hidden read exists for cats
    -- 5-8, the flag contributes nothing: keep. Worst case a genuinely hidden
    -- 5-8 entry lingers until manual removal -- the pre-fix status quo, and
    -- the correct failure direction.

    -- An EMPTY lookup must never judge: GetCooldownViewerCategorySet can return
    -- an empty table for a category it does not serve, indistinguishable from a
    -- real "no members" -- and treating that as removal dropped EVERY
    -- SpecAgnostic entry on the first automatic pass (field 2026-08-13: shaman
    -- Gust of Wind vanished from store/preview/picker while the live bar kept
    -- rendering via frames-as-truth). Same zero-values disease as
    -- GetPlayerAuraBySpellID: an API answering "nothing" for what it cannot
    -- see. Only a POPULATED live set may testify that this id fell out of it.
    if liveSetLookup and next(liveSetLookup) and liveSetLookup[cdID] == nil then
        return "removed" -- dropped out of the category's live set (unequipped/spec lost)
    end

    if rawInfo.isKnown == false then
        return "removed" -- cats 5-8 ONLY; 0-3 rank-holding depends on unknown-but-cataloged survival
    end

    return nil
end

-- WoW Forever: every spell id Forever's Cooldown Manager catalogue lists, in
-- any category, shown or Not Displayed, with base and live forms. A stored id
-- outside it is a spell this client cannot see (a retail-only spell a retail
-- layout carried in): the drop passes keep it and the options preview gives
-- it no slot. nil off Forever or while the catalogue is not readable (callers
-- then keep everything). Read-only, drop-pass and options time only.
function ns.CDMForeverListedSet()
    if not EllesmereUI.IS_FOREVER then return nil end
    local settings = _G.CooldownViewerSettings
    if not settings or type(settings.GetDataProvider) ~= "function" then return nil end
    local okP, provider = pcall(settings.GetDataProvider, settings)
    if not okP or type(provider) ~= "table" then return nil end
    local ordered = ns.CDMGetProviderDisplayData(provider)
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not (ordered and gci) then return nil end
    local NormalizeToBase, ResolveToLive = ns.NormalizeToBase, ns.ResolveToLive
    local set = {}
    local function Add(v)
        if _IsUsableSID(v) then
            set[v] = true
            set[NormalizeToBase(v)] = true
            set[ResolveToLive(v)] = true
        end
    end
    for _, cdID in ipairs(ordered) do
        local info = _IsUsableSID(cdID) and gci(cdID)
        if info then
            Add(info.spellID)
            Add(info.overrideSpellID)
            if type(info.linkedSpellIDs) == "table" then
                for _, lid in ipairs(info.linkedSpellIDs) do Add(lid) end
            end
        end
    end
    if not next(set) then return nil end
    return set
end

-------------------------------------------------------------------------------
--  Buff-family assigned-spell reconcile
--
--  Drops a stored buff-family id only once every member of its LEARNED variant-
--  alias family (ns.GetBuffVariantAliases / ns.LearnBuffVariantAlias, populated
--  from linkedSpellIDs while each form is live) is absent from the current
--  buff-category catalog AND not displayed. UN-LEARNED ids are VOUCHED-ONLY
--  exempt: the ledger must know the id before absence may convict (never-
--  learned = keep unconditionally, the June-ban tradeoff).
--  This is what makes a dual-tracked spell (one stored id, a different id on
--  every live frame) survivable once the pairing has been observed even a
--  single time on this spec -- see the ban comment on
--  ns.SyncExtraBuffBarsWithViewer (EUI_CDM_HookViewers.lua) for why a
--  presence-only prune is unsafe without it. Reuses `_IsUsableSID` from the
--  hidden-channel reader above (single file-scope copy) and the shared
--  `ArmCDMDropRegenWaiter` from ns.ReconcileAssignedSpellDrops's block
--  (single resident implementation, RS3) rather than redefining either.
-------------------------------------------------------------------------------

-- Buff-family present-set: every non-hidden, non-removed spellID/overrideSpellID/
-- linkedSpellIDs member currently catalogued under TrackedBuff/TrackedBar/GroupBuff,
-- plus SpecAgnosticTracked/EquipSlotTracked as a safety superset (membership there can
-- only widen KEEP, never enable a new DROP), plus every live displayed buff-icon
-- spellID. READ-only against the settings provider; nil (provider unhealthy, caller
-- keeps all) if the provider/category APIs are unreachable or no entry is found.
local function BuildBuffFamilyPresentSet()
    local settings = _G.CooldownViewerSettings
    if not settings or type(settings.GetDataProvider) ~= "function" then return nil end
    local okP, provider = pcall(settings.GetDataProvider, settings)
    if not okP or type(provider) ~= "table" then return nil end
    -- Read the already-built display table, never the getters that would
    -- build it (see ns.CDMGetProviderDisplayData).
    local ordered, infoByID = ns.CDMGetProviderDisplayData(provider)
    if not ordered then return nil end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return nil end
    local evc = Enum and Enum.CooldownViewerCategory
    if not evc then return nil end

    local wantCats = {
        [evc.TrackedBuff or 2] = true, [evc.TrackedBar or 3] = true,
        [evc.GroupBuff or 4] = true, [evc.SpecAgnosticTracked or 6] = true,
        [evc.EquipSlotTracked or 8] = true,
    }

    -- Per-category live set: built once per category and reused for every id in that
    -- category, via the shared hidden-channel builder (pcall-safe, id-gated) so this
    -- present-set can never drift from the drop pass's own category reads.
    local liveSetByCat = {}
    if ns.CDMBuildLiveCategorySetLookup then
        for cat in pairs(wantCats) do
            liveSetByCat[cat] = ns.CDMBuildLiveCategorySetLookup(cat)
        end
    end

    local present, sawEntry = {}, false
    for _, cdID in ipairs(ordered) do
        local mergedInfo = _IsUsableSID(cdID) and infoByID[cdID]
        local category = type(mergedInfo) == "table" and mergedInfo.category
        if category ~= nil and wantCats[category] then
            sawEntry = true
            local rawInfo = gci(cdID)
            -- "hidden"/"removed" entries contribute nothing (absent-or-hidden = absent).
            -- A nil verdict (visible, or the hidden-channel reader not yet available)
            -- means included -- this can only ever widen the present-set, never shrink it.
            local verdict = ns.CDMEntryHiddenOrRemoved
                and ns.CDMEntryHiddenOrRemoved(cdID, mergedInfo, rawInfo, liveSetByCat[category])
            if verdict == nil and rawInfo then
                if _IsUsableSID(rawInfo.spellID) then present[rawInfo.spellID] = true end
                if _IsUsableSID(rawInfo.overrideSpellID) then present[rawInfo.overrideSpellID] = true end
                if type(rawInfo.linkedSpellIDs) == "table" then
                    for _, lsid in ipairs(rawInfo.linkedSpellIDs) do
                        if _IsUsableSID(lsid) then present[lsid] = true end
                    end
                end
            end
        end
    end
    if not sawEntry then return nil end

    -- Union live displayed buff-icon frame ids: shown always means keep, regardless of
    -- catalog/hidden-channel state.
    if ns.EnumerateCDMViewerSpells then
        for _, e in ipairs(ns.EnumerateCDMViewerSpells(true)) do
            if _IsUsableSID(e.sid) then present[e.sid] = true end
        end
    end
    return present
end

-- Entry point for the buff-family branch of the assigned-spell reconcile. Self-contained
-- (own guards, own health gate) so it stays correct regardless of caller. Reached today via
-- ns.ReconcileAssignedSpellDrops's buff-family branch (RS3, above), which any caller passing
-- a buff-family barKey exercises -- including the interactive options call sites. Extending
-- the automatic scheduler (ns.RequestCDMDropPass) to also iterate buff-family bar keys on
-- the reseed/settings-close/regen edges is a natural follow-up, not required for this
-- function to be reachable.
function ns.ReconcileBuffFamilyDrops(barKey)
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return nil end
    if not (ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey)) then return nil end
    local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
    if not sd or not sd.assignedSpells or #sd.assignedSpells == 0 then return sd end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local prof = sp and sk and sp[sk]
    if not prof or not prof._barFilterModelV6 or prof._importGhostMode then return sd end
    -- Data-loaded latch: unset until VARIABLES_LOADED + PLAYER_ENTERING_WORLD +
    -- COOLDOWN_VIEWER_DATA_LOADED have all fired, so this never drops against static
    -- defaults before persisted hide/recategorize overrides are merged in.
    if not ns._cdmDataLoaded then return sd end
    if InCombatLockdown() then
        -- Shared regen waiter (defined with ns.ReconcileAssignedSpellDrops /
        -- ns.RequestCDMDropPass, RS3/RS4 above): queues the after-combat entry
        -- that clears ns._cdmDropPending and re-requests a pass. Bare-setting
        -- the flag without arming the waiter would permanently disable every future
        -- automatic pass this session (cd/utility included) since nothing would ever clear it.
        ArmCDMDropRegenWaiter()
        return sd
    end

    local present = BuildBuffFamilyPresentSet()
    if not present then return sd end -- provider unhealthy: fail open, keep everything

    local ledger = prof.buffVariantAliases
    local custom  = sd.customSpellIDs
    local racials = ns._myRacialsSet
    local cdurs   = sd.customSpellDurations
    local sdurs   = sd.spellDurations
    local groups  = sd.customSpellGroups
    local hosted  = sd.hostedBuffSpellIDs

    local dropped = false
    -- WoW Forever's full catalogue set, built on first need (see below).
    local foreverListed
    local writeIdx = 1
    for readIdx = 1, #sd.assignedSpells do
        local id = sd.assignedSpells[readIdx]
        local keep = true
        if type(id) == "number" and id > 0
           and not (custom and custom[id])
           and not (racials and racials[id])
           and not (cdurs and cdurs[id])
           and not (sdurs and sdurs[id])
           and not (groups and groups[id])
           and not (hosted and hosted[id]) then
            -- Ledger closure: BFS over the persisted adjacency sets, seeded with the
            -- stored id AND its base/override forms (a stored base id whose live form
            -- was the one observed must still find its family).
            local seedBase = ns.NormalizeToBase and ns.NormalizeToBase(id) or id
            local seedLive = ns.ResolveToLive and ns.ResolveToLive(id) or id
            local ledgerClosure = { [id] = true, [seedBase] = true, [seedLive] = true }
            -- VOUCHED-ONLY (the June dual-tracked ban, reaffirmed 2026-08-13): the
            -- ledger must be able to TESTIFY about this id before absence may convict.
            -- A never-learned id (single-form buffs never enter the ledger; dual-
            -- tracked families before their first live observation) is KEPT
            -- unconditionally -- it lingers as a removable preview entry, the
            -- accepted June tradeoff. Family-of-one drop semantics silently
            -- resurrected the Vengeance Meta data-loss class and are FORBIDDEN.
            local vouched = false
            if ledger and (ledger[id] or ledger[seedBase] or ledger[seedLive]) then
                vouched = true
            end
            if ledger then
                local frontier, n = {}, 0
                for s0 in pairs(ledgerClosure) do n = n + 1; frontier[n] = s0 end
                while n > 0 do
                    local nf, nn = nil, 0
                    for i = 1, n do
                        local partners = ledger[frontier[i]]
                        if partners then
                            for partner in pairs(partners) do
                                if _IsUsableSID(partner) and not ledgerClosure[partner] then
                                    ledgerClosure[partner] = true
                                    nn = nn + 1
                                    nf = nf or {}
                                    nf[nn] = partner
                                end
                            end
                        end
                    end
                    frontier, n = nf, nn
                end
            end
            -- Union every closure member's base/override variants (StoreVariantValue-
            -- style expansion) so a talent swap on any family member still resolves.
            local family = {}
            for member in pairs(ledgerClosure) do
                if ns.StoreVariantValue then
                    ns.StoreVariantValue(family, member, true, false)
                else
                    family[member] = true
                end
            end
            local anyPresent = false
            for member in pairs(family) do
                if present[member] then anyPresent = true; break end
            end
            -- WoW Forever: a family its catalogue does not list at all (Not
            -- Displayed included) is a buff this client cannot see (a retail
            -- layout's): it holds its place instead.
            local unseen = false
            if vouched and not anyPresent and EllesmereUI.IS_FOREVER then
                if foreverListed == nil then
                    foreverListed = ns.CDMForeverListedSet() or false
                end
                unseen = true
                if foreverListed then
                    for member in pairs(family) do
                        if foreverListed[member] then unseen = false; break end
                    end
                end
            end
            if vouched and not anyPresent and not unseen then
                keep = false
                dropped = true
            end
        end
        if keep then
            sd.assignedSpells[writeIdx] = id
            writeIdx = writeIdx + 1
        end
    end
    for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end
    if dropped then ns._spellOrderDirty = true end
    return sd
end

--- Repopulate all main bars from Blizzard CDM for the current spec.
--- Wipes ONLY Blizzard-sourced entries (positive spell IDs that the CDM
--- viewer owns) from assignedSpells/removedSpells, then rebuilds route
--- maps and reanchors. Preserves user-added entries:
---   * Negative IDs (trinket slots -13/-14, item presets <= -100)
---   * Custom spell IDs (entries in sd.customSpellIDs)
---   * Racial spells (entries in _myRacialsSet)
function ns.RepopulateFromBlizzard()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end

    -- A spell ID is "user-added" (preserved across repopulate) if it's a negative preset marker, a custom spell ID added via the picker, or a racial belonging to this character.
    local function IsUserAdded(sd, id)
        if type(id) ~= "number" or id == 0 then return false end
        if id < 0 then return true end
        if sd.customSpellIDs and sd.customSpellIDs[id] then return true end
        if _myRacialsSet and _myRacialsSet[id] then return true end
        -- A positive id carrying a stored duration is one of OUR injected preset/custom buffs
        -- (Bloodlust/Heroism, potions, Time Spiral, custom buff IDs). Blizzard-tracked buffs are
        -- never written into assignedSpells with a duration, so this can only be a user-added entry -- preserve it. Presets predate the customSpellIDs flag, so the flag alone is not enough.
        if sd.spellDurations and (sd.spellDurations[id] or 0) > 0 then return true end
        return false
    end

    -- Filter a list in place: keep only entries IsUserAdded returns true for.
    local function FilterListPreservingUserAdded(sd, list)
        if type(list) ~= "table" then return end
        local writeIdx = 1
        for readIdx = 1, #list do
            local id = list[readIdx]
            if IsUserAdded(sd, id) then
                list[writeIdx] = id
                writeIdx = writeIdx + 1
            end
        end
        for i = writeIdx, #list do list[i] = nil end
    end

    -- Filter a set in place (keys = spell IDs): drop keys that aren't user-added.
    local function FilterSetPreservingUserAdded(sd, set)
        if type(set) ~= "table" then return end
        for id in pairs(set) do
            if not IsUserAdded(sd, id) then set[id] = nil end
        end
    end

    -- Filter Blizzard entries off all CD/utility bars (main + custom). Skip ghost, custom_buff,
    -- and default buff bar. The default buff bar (key == "buffs") has no assignedSpells to filter -- Blizzard's viewer is the authority. Extra buff bars ARE filtered for user assignments.
    for _, barData in ipairs(p.cdmBars.bars) do
        if not barData.isGhostBar
           and barData.key ~= "buffs"
           and (barData.barType == "cooldowns" or barData.barType == "utility"
                or barData.barType == "buffs"
                or MAIN_BAR_KEYS[barData.key]) then
            local sd = ns.GetBarSpellData(barData.key)
            if sd then
                FilterListPreservingUserAdded(sd, sd.assignedSpells)
                FilterSetPreservingUserAdded(sd, sd.removedSpells)
                -- spellSettings is per-spell config (font color, etc.) -- preserve entirely so user-added customs keep their styling.
            end
        end
    end

    -- Ghost bars hold Blizzard-owned spells the user explicitly hid. Filter the same way so user-added presets that may have been routed here (rare edge case) are preserved.
    local ghostSD = ns.GetBarSpellData(GHOST_CD_BAR_KEY)
    if ghostSD then
        FilterListPreservingUserAdded(ghostSD, ghostSD.assignedSpells)
        FilterSetPreservingUserAdded(ghostSD, ghostSD.removedSpells)
    end
    -- Ghost buff bar removed: buff visibility managed by Blizzard CDM.

    local buffSD = ns.GetBarSpellData("buffs")
    if buffSD then
        buffSD.buffDisplayOrder = nil
        buffSD._buffDisplayOrderUserModified = nil
    end
    ns._spellOrderDirty = true
    ns._cdmBuffOrderDirty = true  -- re-seed from Blizzard order on next reanchor

    -- Under the diversion-set model, "repopulate from Blizzard" is just "wipe diversions and let the route map's spillover show everything from the viewer" -- the wipes above are all that is needed.

    ns.FullCDMRebuild("repopulate")
    if ns.CollectAndReanchor then ns.CollectAndReanchor() end

    ns.ReseedAssignedSpellsFromLiveIcons()

    C_Timer.After(1, function()
        local sk = ns.GetActiveSpecKey()
        if sk and sk ~= "0" then
            SaveCurrentSpecProfile()
        end
    end)
end

I.CDMFirstLoginCapture = CDMFirstLoginCapture
I.broken = false
