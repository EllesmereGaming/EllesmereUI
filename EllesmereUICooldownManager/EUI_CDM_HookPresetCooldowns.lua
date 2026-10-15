if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookPresetCooldowns.lua
--
--  Dynamic potion display and the cooldown drain for EUI's own preset
--  frames (ProcessPresetCooldowns and its event lanes).
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME = ns.ECME
local barDataByKey = ns.barDataByKey
local _ecmeFC = ns._ecmeFC
local GetTime = GetTime

local FD, CdmChargeInfoFor, PresetKeepsColor = I.FD, I.CdmChargeInfoFor, I.PresetKeepsColor
local _pcActive, _presetFrames = I._pcActive, I._presetFrames
local ApplyItemQualityPip = I.ApplyItemQualityPip

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

-- Pact of Gluttony (386689) decides which stone the player conjures: with it only
-- Demonic Healthstones (224464), without it only Healthstones (5512). The other
-- stone's entry never shows, not even dimmed. Read by the reanchor pass; talent and
-- spell changes always queue one. On ns: 200-local cap.
function ns._HealthstoneHiddenByPact(itemID)
    if itemID ~= 5512 and itemID ~= 224464 then return false end
    local pact = C_SpellBook.IsSpellKnown(386689) == true
    if itemID == 5512 then return pact end
    return not pact
end

-- Count (charges included) of a non-pot item preset frame: the primary id, else the
-- sum of the family alts. Returns total and first owned id. On ns: 200-local cap.
function ns._ReadItemPresetCount(f)
    local total = C_Item.GetItemCount(f._presetItemID, false, true) or 0
    local owned = total > 0 and f._presetItemID or nil
    if total == 0 and IsPresetFamilyFrame(f) then
        for _, altID in ipairs(f._presetData.altItemIDs) do
            local c = C_Item.GetItemCount(altID, false, true) or 0
            total = total + c
            if not owned and c > 0 then owned = altID end
        end
    end
    return total, owned
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
                    -- Only for custom spells (not racials -- racials don't cost resources).
                    -- Out of Range Coloring (opt-in) outranks the dim; its answer
                    -- (f._rangeOut) is kept by events and only painted here.
                    if f._isCustomSpellFrame and f._tex then
                        ns.PaintCustomSpellTint(f, sid, onRealCD)
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
                    -- Count-on-edge: item counts move with bag contents
                    -- (BAG_UPDATE_DELAYED), a use-cast, or a charge-only
                    -- change (BAG_UPDATE_COOLDOWN recheck), all of which arm.
                    -- This content edge also re-points the single watched cd
                    -- id (f._itemCdSource): first owned id wins; while
                    -- nothing is owned the LAST owned id is kept (the shared
                    -- cd lives on the id that was just used).
                    f._countArm = false
                    local owned
                    total, owned = ns._ReadItemPresetCount(f)
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
            -- A stone the Pact of Gluttony rule hides is never injected, so its
            -- stale presence cache must not queue a reanchor on every bag edge.
            if bd and bd.hideItemsIfMissing
               and not ns._HealthstoneHiddenByPact(f._presetItemID) then
                local total
                if PotSwap.Ensure(f) then
                    -- Pot presets: present = the resolved chain owns anything
                    -- (partner family counts while the swap toggle is on).
                    total = f._displayCount or 0
                else
                    total = ns._ReadItemPresetCount(f)
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

-- Trailing flush for the loot-storm cap: a bag fire swallowed inside the
-- window re-arms on the first listener event past it, or at the window's end
-- when nothing else fires (a conjured stone's second bag fire lands inside
-- the window, and a quiet world would otherwise keep its count stale until
-- some unrelated event). On ns: 200-local cap.
ns._pcBagFlush = function()
    ns._pcBagPend = nil
    ns._pcBagNext = GetTime() + 0.5
    -- Bag contents changed: pot-preset display variants must re-resolve before
    -- the presence check, which reads the resolution.
    PotSwap.Bump()
    CheckItemPresenceForHide()
    -- Contents are the only thing that changes item counts, and a new stack can
    -- move the displayed cooldown source too: re-walk both. (Live set: hidden
    -- frames re-arm on their Show edge.)
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
ns._pcBagFlushTimerFn = function()
    ns._pcBagFlushQueued = nil
    if ns._pcBagPend then ns._pcBagFlush() end
end

_racialCdListener:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if ns._pcBagPend and GetTime() >= (ns._pcBagNext or 0) then
        ns._pcBagFlush()
    end
    -- Infrequent events: handle immediately and return
    if event == "BAG_UPDATE_DELAYED" then
        -- Loot-storm cap (probe-proven capture #12: mob-farming loot fires
        -- this in bursts, and each fire re-armed variant re-resolves + chain
        -- walks + bag-count scans -- the drain's dominant real cost). At
        -- most two re-arm cycles per second; a burst's trailing changes land
        -- on the head flush or the queued flush at the window's end.
        local nowB = GetTime()
        if nowB >= (ns._pcBagNext or 0) then
            ns._pcBagFlush()
        else
            -- Swallowed by the cap: flush on the first event after the
            -- window (see the head of this handler), or at its end at the
            -- latest -- one queued flush per window.
            ns._pcBagPend = true
            if not ns._pcBagFlushQueued then
                ns._pcBagFlushQueued = true
                C_Timer.After(ns._pcBagNext - nowB, ns._pcBagFlushTimerFn)
            end
        end
        return
    end
    if event == "BAG_UPDATE_COOLDOWN" then
        -- Charge-only item count changes (a used Healthstone charge, a Soulwell
        -- refill) move no bag contents, so no BAG_UPDATE fires; a used charge
        -- lands with this event, after the cast arm already read the old count.
        -- Re-read the shown non-pot item counts and arm only on a real change.
        -- A count crossing zero also re-runs the Hide Items if Missing check,
        -- which otherwise only bag-content edges drive.
        local hit, crossed
        for f in pairs(_pcActive) do
            if f._isItemPresetFrame and f._presetItemID and not f._displayItemID
               and f._cachedTotal and f._countArm == false then
                local old, n = f._cachedTotal, ns._ReadItemPresetCount(f)
                if n ~= old then
                    f._countArm = true
                    hit = true
                    if (n == 0) ~= (old == 0) then crossed = true end
                end
            end
        end
        if hit then
            _presetCdDirty = true
            _pcAllSettled = false
            -- Fast lane like a cast: the new count lands after the cast's own pass, inside the 1 Hz cap.
            ns._pcLast = 0
            if ns.ArmBuffTicker then ns.ArmBuffTicker() end
            if crossed then CheckItemPresenceForHide() end
        end
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
        -- nothing to report. The count recheck above stays ungated on purpose:
        -- it is the only charge-only count refresh and arms only on a change.
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

I._customAuraTimers, I._pendingCastIDs = _customAuraTimers, _pendingCastIDs
I.ApplyPresetGCDSwipe, I.PotSwap = ApplyPresetGCDSwipe, PotSwap
I.ProcessPresetCooldowns = ProcessPresetCooldowns
I.QueueCustomBuffUpdate = QueueCustomBuffUpdate
I.broken = false
