if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_Layers.lua
--
--  Layer harvest and apply, the Buff Manager forks with their session swap
--  and the Debuff Manager forks.
--  Reads the earlier Spec Overrides files through EUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
local I = EUI_NS._soInternals
-- EllesmereUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local CurrentSpecID, DeepCopy, GetGroups = I.CurrentSpecID, I.DeepCopy, I.GetGroups
local GetProfileRoot, GroupById, L = I.GetProfileRoot, I.GroupById, I.L
local RunRefreshers, ApplyValuesFor = I.RunRefreshers, I.ApplyValuesFor
local GetUnlockStore, OwnerGid = I.GetUnlockStore, I.OwnerGid

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _editGroup = nil
I.editGroupSetters[#I.editGroupSetters + 1] = function(v) _editGroup = v end
local _defaultView = false
I.defaultViewSetters[#I.defaultViewSetters + 1] = function(v) _defaultView = v end
local _inTransition = false
I.inTransitionSetters[#I.inTransitionSetters + 1] = function(v) _inTransition = v end
local _activeSpec = nil
I.activeSpecSetters[#I.activeSpecSetters + 1] = function(v) _activeSpec = v end
local ExitGroupEdit
I.exitGroupEditSetters[#I.exitGroupEditSetters + 1] = function(v) ExitGroupEdit = v end
local RefreshCardsPopup
I.refreshCardsSetters[#I.refreshCardsSetters + 1] = function(v) RefreshCardsPopup = v end

-------------------------------------------------------------------------------
--  Layer harvest / apply
--
--  A LAYER is the complete unlock layout, captured and applied WHOLESALE:
--    anchors / widthMatch / heightMatch   global unlock link tables, verbatim
--                                         (incl. offsets, growth-edge pins)
--    widthMatchExtra / heightMatchExtra   the matches' extra px, by child key
--    cdmPos / abPos                       raw saved-edge stores incl. the
--                                         tgt* follow baselines
--    cdmGrow / abGrow                     grow directions by bar key
--    elems[key] = {point,relPoint,x,y,w,h} generic registered elements via
--                                         their own loadPosition/getSize
--  No diffs, no per-aspect baselines, no size companions: whatever edited the live
--  layout during play (drags, sliders, value-override applies, match propagation,
--  offset upkeep, blesses), harvest-on-leave records the final live truth into the
--  owning layer and apply-on-enter reproduces it -- convergent by construction.
--  TBB_/TBBG_ keys are excluded (natively spec-scoped / globally shared).
-------------------------------------------------------------------------------

local function LiteProfile(folder)
    local a = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon(folder, true)
    return a and a.db and a.db.profile or nil
end

local function LayerSkipsKey(key)
    if type(key) ~= "string" then return true end
    if key:sub(1, 4) == "CDM_" or key:sub(1, 4) == "TBB_"
       or key:sub(1, 5) == "TBBG_" then
        return true
    end
    local abk = EllesmereUI._abBarKeys
    if abk and abk[key] then return true end
    -- One spot for every spec (MakeUnlockElement's noSpecLayout).
    local elems = EllesmereUI._unlockRegisteredElements
    local elem = elems and elems[key]
    return (elem and elem.noSpecLayout) and true or false
end

-- Tracking Bar CHILD-role link entries (key "TBB_<idx>") are per-spec data
-- owned by the CDM link buckets (SyncTBBUnlockLinks): layers never carry them
-- and never wipe them, or an apply would stamp one spec's links onto another
-- spec's bars. Entries where a TBB key is only the TARGET live under the
-- child's key and stay layer-managed like any other element.
local function IsTBBChildKey(key)
    return type(key) == "string" and key:find("^TBB_%d+$") ~= nil
end

-- carry / base: the layer the harvest banks into and the baseline. An element
-- whose size the current look fixes (sizeFixedByLook: Blizzard Style unit
-- frames) reports that look's size, not its own setting, so its size is taken
-- from carry, else base, else its own setting (getSettingSize): every entry
-- keeps a size, since the layer apply treats an entry as owning the key.
local function HarvestLayer(carry, base)
    local layer = {
        anchors     = DeepCopy(EllesmereUIDB and EllesmereUIDB.unlockAnchors or {}),
        widthMatch  = DeepCopy(EllesmereUIDB and EllesmereUIDB.unlockWidthMatch or {}),
        heightMatch = DeepCopy(EllesmereUIDB and EllesmereUIDB.unlockHeightMatch or {}),
        cdmGrow = {}, abGrow = {}, elems = {},
    }
    -- Strip TBB child-role entries: per-spec data, not layer data.
    local stripSets = { layer.anchors, layer.widthMatch, layer.heightMatch }
    for i = 1, 3 do
        local t, kill = stripSets[i], nil
        for k in pairs(t) do
            if IsTBBChildKey(k) then
                kill = kill or {}
                kill[#kill + 1] = k
            end
        end
        if kill then
            for _, k in ipairs(kill) do t[k] = nil end
        end
    end
    -- Match extras ride with the links: kept only beside a link this layer
    -- carries (so the TBB child entries stripped above drop out too).
    layer.widthMatchExtra, layer.heightMatchExtra = {}, {}
    local wx = EllesmereUIDB and EllesmereUIDB.unlockWidthMatchExtra
    if wx then
        for k, v in pairs(wx) do
            if layer.widthMatch[k] ~= nil then layer.widthMatchExtra[k] = v end
        end
    end
    local hx = EllesmereUIDB and EllesmereUIDB.unlockHeightMatchExtra
    if hx then
        for k, v in pairs(hx) do
            if layer.heightMatch[k] ~= nil then layer.heightMatchExtra[k] = v end
        end
    end
    local cdm = LiteProfile("EllesmereUICooldownManager")
    if cdm then
        layer.cdmPos = DeepCopy(cdm.cdmBarPositions or {})
        if cdm.cdmBars and cdm.cdmBars.bars then
            for _, bar in ipairs(cdm.cdmBars.bars) do
                if bar.key and bar.growDirection then
                    layer.cdmGrow[bar.key] = bar.growDirection
                end
            end
        end
    end
    local ab = LiteProfile("EllesmereUIActionBars")
    if ab then
        layer.abPos = DeepCopy(ab.barPositions or {})
        if ab.bars then
            for k, cfg in pairs(ab.bars) do
                if type(cfg) == "table" and cfg.growDirection then
                    layer.abGrow[k] = cfg.growDirection
                end
            end
        end
    end
    local elems = EllesmereUI._unlockRegisteredElements
    if elems then
        for key, elem in pairs(elems) do
            if not LayerSkipsKey(key) then
                local e
                -- Elements whose STORED position is not the visual one loadPosition
                -- reports (PlayerAuraBars' rounding-shifted bars) expose
                -- loadRawPosition/saveRawPosition: bank that flat table verbatim, so
                -- a layer harvested at one resolution stays valid at another and
                -- keeps the element's own position flags.
                if elem.loadRawPosition and elem.saveRawPosition then
                    local ok, p = pcall(elem.loadRawPosition, key)
                    if ok and type(p) == "table" and p.point then
                        e = {}
                        for k, v in pairs(p) do
                            if type(v) ~= "table" then e[k] = v end
                        end
                        e.relPoint = e.relPoint or e.point
                        e.rawPos = true
                    end
                elseif elem.loadPosition then
                    local ok, p = pcall(elem.loadPosition, key)
                    if ok and p and p.point then
                        e = { point = p.point, relPoint = p.relPoint or p.point,
                              x = p.x, y = p.y }
                    end
                end
                if elem.sizeFixedByLook then
                    local w, h
                    for i = 1, 2 do
                        local src = base
                        if i == 1 then src = carry end
                        local ce = src and src.elems and src.elems[key]
                        if ce and (ce.w or ce.h) then
                            w, h = ce.w, ce.h
                            break
                        end
                    end
                    if w == nil and h == nil and elem.getSettingSize then
                        local ok, sw, sh = pcall(elem.getSettingSize, key)
                        if ok then
                            if type(sw) == "number" and sw > 0 then w = sw end
                            if type(sh) == "number" and sh > 0 then h = sh end
                        end
                    end
                    if w or h then
                        e = e or {}
                        e.w, e.h = w, h
                    end
                elseif elem.getSize then
                    local ok, w, h = pcall(elem.getSize, key)
                    if ok then
                        if type(w) == "number" and w > 0 then e = e or {}; e.w = w end
                        if type(h) == "number" and h > 0 then e = e or {}; e.h = h end
                    end
                end
                if e then layer.elems[key] = e end
            end
        end
    end
    return layer
end

-- Generic-element writes are deferred to the flush: their savePosition/setWidth
-- closures are only re-registered AFTER profile-switch applies, and the flush
-- carries the combat gate. Raw CDM/AB stores go through the stable Lite db
-- objects, so they are always safe to write immediately.
local _unlockDeferredElemLayout = nil
-- Baseline geometry for elements the INCOMING layer has no elems entry for
-- ("missing means baseline, never keep outgoing residue"): stashed by ApplyLayer,
-- applied by the flush after the layer's own entries, consumed per-key so live
-- drift is never re-stomped. Without it a layer missing a key (late registration,
-- fork saved before the element existed) leaves the OUTGOING layer's geometry live
-- and the next harvest bakes that residue into the incoming layer permanently.
local _unlockDeferredElemFallback = nil

-- Anchored children's positions are OWNED by the anchor system: a layer/baseline
-- elem recorded for a currently-anchored key is derived bookkeeping (whatever
-- geometry the anchor produced at harvest time) and must NEVER be painted back
-- through savePosition -- doing so stomps freshly anchor-applied windows and
-- poisons their module-saved positions. Mirrors the ApplyCenterPosition
-- anchored-skip, applied at the flush's write sites.
local function UnlockElemAnchorOwned(key)
    local a = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    local info = a and a[key]
    return type(info) == "table" and info.target ~= nil
end
local _unlockSettleWanted = false
local _unlockFlushScheduled = false
local ScheduleUnlockFlush

-- Loose elem-geometry equality (position keywords exact, coordinates and
-- sizes within the flush's 0.5 write tolerance).
local function ElemNear(a, b)
    if not a or not b then return false end
    if (a.point or false) ~= (b.point or false) then return false end
    if (a.relPoint or a.point or false) ~= (b.relPoint or b.point or false) then return false end
    local function near(x, y)
        if x == nil and y == nil then return true end
        if type(x) ~= "number" or type(y) ~= "number" then return false end
        return math.abs(x - y) < 0.5
    end
    return near(a.x, b.x) and near(a.y, b.y) and near(a.w, b.w) and near(a.h, b.h)
end

-- Exact equality for RAW element positions (loadRawPosition): the element's own
-- stored fields, so a position flag it carries counts as a difference too. The
-- layer's own bookkeeping keys are not part of the position.
local RAW_POS_LAYER_KEYS = { w = true, h = true, rawPos = true, relPoint = true }
local function RawPosEqual(cur, e)
    if not cur then return false end
    if (cur.relPoint or cur.point) ~= (e.relPoint or e.point) then return false end
    for k, v in pairs(e) do
        if not RAW_POS_LAYER_KEYS[k] and cur[k] ~= v then return false end
    end
    for k, v in pairs(cur) do
        if not RAW_POS_LAYER_KEYS[k] and e[k] ~= v then return false end
    end
    return true
end

--- Writes a layer into the live stores. CRITICAL: the raw CDM/AB position tables
--- are mutated IN PLACE (wipe + refill) -- the owning addons keep mirror references
--- to these exact tables that only refresh on profile applies, so replacing the
--- table identity orphans them on same-profile spec swaps. baseline: the store's
--- baselineLayout when LAYER is a group/conditional fork (nil when applying the
--- baseline itself); every sub-store the layer is missing falls back to it
--- ("missing means baseline, never keep the outgoing layer's residue").
local function ApplyLayer(layer, baseline)
    if not layer then return end
    if EllesmereUIDB then
        local anchors = EllesmereUIDB.unlockAnchors
        if not anchors then anchors = {}; EllesmereUIDB.unlockAnchors = anchors end
        -- Fallback links belong to the child/target pair, not the spec: carry
        -- each over when the arriving layer keeps the same target. TBB child
        -- entries (per-spec, bucket-owned) ride the wipe whole, fallback
        -- included, and layer-borne ones are skipped on refill.
        local fallbacks, tbbKept
        for k, info in pairs(anchors) do
            if IsTBBChildKey(k) then
                tbbKept = tbbKept or {}
                tbbKept[k] = info
            elseif info.fallback then
                fallbacks = fallbacks or {}
                fallbacks[k] = { tgt = info.target, fb = info.fallback }
            end
        end
        wipe(anchors)
        for k, info in pairs(layer.anchors or {}) do
            if not IsTBBChildKey(k) then
                anchors[k] = DeepCopy(info)
                local f = fallbacks and fallbacks[k]
                if f and f.tgt == info.target then anchors[k].fallback = f.fb end
            end
        end
        if tbbKept then
            for k, info in pairs(tbbKept) do anchors[k] = info end
        end
        EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
        local wm = EllesmereUIDB.unlockWidthMatch
        if not wm then wm = {}; EllesmereUIDB.unlockWidthMatch = wm end
        local wmKept
        for k, v in pairs(wm) do
            if IsTBBChildKey(k) then
                wmKept = wmKept or {}
                wmKept[k] = v
            end
        end
        wipe(wm)
        for k, v in pairs(layer.widthMatch or {}) do
            if not IsTBBChildKey(k) then wm[k] = v end
        end
        if wmKept then
            for k, v in pairs(wmKept) do wm[k] = v end
        end
        local hm = EllesmereUIDB.unlockHeightMatch
        if not hm then hm = {}; EllesmereUIDB.unlockHeightMatch = hm end
        local hmKept
        for k, v in pairs(hm) do
            if IsTBBChildKey(k) then
                hmKept = hmKept or {}
                hmKept[k] = v
            end
        end
        wipe(hm)
        for k, v in pairs(layer.heightMatch or {}) do
            if not IsTBBChildKey(k) then hm[k] = v end
        end
        if hmKept then
            for k, v in pairs(hmKept) do hm[k] = v end
        end
        -- Match extras follow the links above, the same way for both axes: TBB
        -- child entries stay, the rest become the layer's (none when it has none).
        for pass = 1, 2 do
            local field, src = "unlockWidthMatchExtra", layer.widthMatchExtra
            if pass == 2 then field, src = "unlockHeightMatchExtra", layer.heightMatchExtra end
            local t = EllesmereUIDB[field]
            local kept
            if t then
                for k, v in pairs(t) do
                    if IsTBBChildKey(k) then
                        kept = kept or {}
                        kept[k] = v
                    end
                end
                wipe(t)
            end
            if type(src) == "table" then
                for k, v in pairs(src) do
                    if not IsTBBChildKey(k) then
                        if not t then t = {}; EllesmereUIDB[field] = t end
                        t[k] = v
                    end
                end
            end
            if kept then
                for k, v in pairs(kept) do t[k] = v end
            end
        end
    end
    local cdm = LiteProfile("EllesmereUICooldownManager")
    if cdm then
        -- A layer harvested while CDM was disabled has no cdmPos; restore the
        -- baseline's instead of leaving the outgoing layer's positions live
        -- (they would be harvested INTO this layer next).
        local pos = layer.cdmPos or (baseline and baseline.cdmPos)
        if pos then
            local t = cdm.cdmBarPositions
            if not t then t = {}; cdm.cdmBarPositions = t end
            wipe(t)
            for k, v in pairs(pos) do t[k] = DeepCopy(v) end
            -- Per-bar missing-means-baseline: a layer's cdmPos is a snapshot from its
            -- last harvest, so bars created AFTER it have no entry in older layers and
            -- fall to their DEFAULT (centered) placement at layout time ("CDM centered
            -- on this one spec"). Fill the gaps from the baseline (mirrors the grow-key
            -- rule below); the layer self-heals to full coverage at its next harvest.
            local bpos = baseline and baseline.cdmPos
            if bpos and bpos ~= pos then
                for k, v in pairs(bpos) do
                    if t[k] == nil then t[k] = DeepCopy(v) end
                end
            end
        end
        if cdm.cdmBars and cdm.cdmBars.bars then
            -- Grow keys follow missing-means-baseline too. A grow store is AUTHORITATIVE
            -- only when its layer was harvested with CDM loaded (cdmPos present <=>
            -- the harvest's cdm block ran); a layer that never saw CDM knows nothing
            -- about grows. Per bar: layer value, else baseline, else CLEAR (module
            -- default), so one fork's grow can't stick to every other layer.
            local lg = (layer.cdmPos ~= nil) and layer.cdmGrow or nil
            local bg = (baseline and baseline.cdmPos ~= nil) and baseline.cdmGrow or nil
            if lg or bg then
                for _, bar in ipairs(cdm.cdmBars.bars) do
                    if bar.key then
                        local gd
                        if lg then gd = lg[bar.key] end
                        if gd == nil and bg then gd = bg[bar.key] end
                        bar.growDirection = gd
                    end
                end
            end
        end
    end
    local ab = LiteProfile("EllesmereUIActionBars")
    if ab then
        local pos = layer.abPos or (baseline and baseline.abPos)
        if pos then
            local t = ab.barPositions
            if not t then t = {}; ab.barPositions = t end
            wipe(t)
            for k, v in pairs(pos) do t[k] = DeepCopy(v) end
            -- Per-bar missing-means-baseline, same as cdmPos above.
            local bpos = baseline and baseline.abPos
            if bpos and bpos ~= pos then
                for k, v in pairs(bpos) do
                    if t[k] == nil then t[k] = DeepCopy(v) end
                end
            end
        end
        if ab.bars then
            -- Same authority rule and per-bar fallback as cdmGrow.
            local lg = (layer.abPos ~= nil) and layer.abGrow or nil
            local bg = (baseline and baseline.abPos ~= nil) and baseline.abGrow or nil
            if lg or bg then
                for k, cfg in pairs(ab.bars) do
                    if type(cfg) == "table" then
                        local gd
                        if lg then gd = lg[k] end
                        if gd == nil and bg then gd = bg[k] end
                        cfg.growDirection = gd
                    end
                end
            end
        end
    end
    -- REPLACE the pending map, never merge: it always represents the ACTIVE layer's
    -- intended element state. Anything still unapplied from the previous layer was
    -- already banked back by the transition harvest (which overlays pending intent),
    -- and flushing it under the new layer would cross-contaminate.
    _unlockDeferredElemLayout = nil
    if layer.elems and next(layer.elems) then
        _unlockDeferredElemLayout = {}
        for key, e in pairs(layer.elems) do
            _unlockDeferredElemLayout[key] = DeepCopy(e)
        end
    end
    -- Missing means baseline: elements the incoming layer has no entry for restore
    -- their BASELINE geometry at flush time instead of keeping the outgoing layer's
    -- residue. Replaced wholesale with the pending map; entries consumed as they apply.
    _unlockDeferredElemFallback = nil
    if baseline and baseline ~= layer and baseline.elems then
        local fb
        for key, e in pairs(baseline.elems) do
            if not (layer.elems and layer.elems[key] ~= nil) and not LayerSkipsKey(key) then
                fb = fb or {}
                fb[key] = DeepCopy(e)
            end
        end
        _unlockDeferredElemFallback = fb
    end
end

-- ---- apply engine -----------------------------------------------------------

--- Swaps the live unlock layout to the given spec's layer (its owning group's layout,
--- or the baseline). Same-layer arrivals are a no-op: live drift (offset upkeep,
--- blesses) stays live and is banked by the transition harvests. NEVER harvests here
--- -- by apply time the value system has already written the NEW spec's data into
--- module configs, so a harvest here would bank it into the OLD layer (the
--- transition harvest in OnSpecChanged/HarvestCurrent runs while live is still old).
function EllesmereUI.SpecOverrides_ApplyUnlock(specID, force)
    local s = GetUnlockStore()
    if not s then return end
    specID = specID or _activeSpec or CurrentSpecID()
    if not specID then return end
    -- TIER 1: the spec's own group layer. When it exists, conditional layouts
    -- are ignored ENTIRELY for this spec.
    local want = OwnerGid(specID)
    local target
    if want then
        target = s.layouts[want]
    else
        -- TIER 2: the applied conditional group's layout (namespaced pointer
        -- "cond:<gid>" -- one pointer, one harvest target, one heal path).
        local cond = EllesmereUI._CondOv and EllesmereUI._CondOv.ResolveGid
            and EllesmereUI._CondOv.ResolveGid() or nil
        if cond then
            local cs = EllesmereUI._CondOv.GetUnlockStore()
            if cs and cs.layouts[cond] then
                want = "cond:" .. cond
                target = cs.layouts[cond]
            end
        end
    end
    if want == s.active and not force then
        -- Same-layer arrival: live drift stays live (never re-apply). BUT module
        -- POSITION stores can carry persisted gaps: a layer snapshot missing bars
        -- created after its last harvest leaves them entryless (default centered
        -- placement), and this early-out skips ApplyLayer every same-layer login, so
        -- the gap never heals without a layer transition. ADD-ONLY heal: fill missing
        -- bar keys from the live layer then the baseline; existing entries (live
        -- drift) are never touched, and the settle only runs if something was missing.
        local base = s.baselineLayout
        local function GapFill(prof, storeKey, layerPos, basePos)
            if not prof then return false end
            local t = prof[storeKey]
            if not t then t = {}; prof[storeKey] = t end
            local added = false
            if layerPos then
                for k, v in pairs(layerPos) do
                    if t[k] == nil then t[k] = DeepCopy(v); added = true end
                end
            end
            if basePos and basePos ~= layerPos then
                for k, v in pairs(basePos) do
                    if t[k] == nil then t[k] = DeepCopy(v); added = true end
                end
            end
            return added
        end
        local cdm = LiteProfile("EllesmereUICooldownManager")
        local ab = LiteProfile("EllesmereUIActionBars")
        local added = GapFill(cdm, "cdmBarPositions",
            target and target.cdmPos, base and base.cdmPos)
        if GapFill(ab, "barPositions",
            target and target.abPos, base and base.abPos) then added = true end
        if added then
            -- Same settle ApplyLayer uses: repositions bars from the now
            -- complete store (the flush self-defers in combat).
            _unlockSettleWanted = true
            ScheduleUnlockFlush()
        end
        return
    end
    -- TIER 3: baseline.
    if not target then target = s.baselineLayout end
    s.active = want
    if target then
        -- Forks fall back to the baseline for every sub-store they are
        -- missing (nil when the target IS the baseline).
        ApplyLayer(target, target ~= s.baselineLayout and s.baselineLayout or nil)
        _unlockSettleWanted = true
        ScheduleUnlockFlush()
    end
end

--- Banks the LIVE unlock layout into the layer it belongs to (the active group
--- layer, else the baseline). Runs at every transition boundary while live
--- still belongs to the outgoing state: spec change, profile
--- switch/export/logout, and unlock Save & Exit.
function EllesmereUI.SpecOverrides_HarvestUnlockLayout(userCommit)
    local s = GetUnlockStore()
    if not s then return end
    -- Zero-cost for non-users: nothing to bank into until a layer exists.
    local condStore = EllesmereUI._CondOv and EllesmereUI._CondOv.GetUnlockStore()
    if not s.active and not next(s.layouts) and not s.baselineLayout
       and not (condStore and next(condStore.layouts)) then return end
    -- Mid-establish (a profile apply whose Conditions establish was combat-deferred):
    -- live is MIXED -- baseline links restored over the incoming profile's
    -- layer-valued module data. Banking it anywhere (especially into baselineLayout
    -- via the reset active pointer) poisons the store; skip until the pending
    -- establish converges, then banks resume on the next boundary.
    if EllesmereUI.Conditions_EstablishPending and EllesmereUI.Conditions_EstablishPending() then
        return
    end
    -- Import window (see ImportProfile): from an imported profile's activation until
    -- the first apply of a LATER session, the store holds the exporter's layers
    -- verbatim while live geometry is mid-import residue (inherited link tables,
    -- unconverged anchors). Banking any boundary in that window (import-tail
    -- Conditions recheck, the reload's PLAYER_LOGOUT, first post-login spec
    -- transition) would wholesale-replace a pristine bucket with that residue.
    -- Fail-open like the guards above: skip; banks resume once the window closes.
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            if userCommit then
                -- Unlock Save & Exit: a user-committed layout is converged,
                -- live-authoritative state; close the window and bank it.
                prof._importEstablishPending = nil
            else
                return
            end
        end
    end
    -- Reset-pointer window (see SpecOverrides_UnlockResetActive): a profile activation
    -- cleared a live layer pointer while module elem positions still hold that layer's
    -- geometry. Banking before the forced converge lands would file the outgoing
    -- layer's positions into baselineLayout via the nil pointer. Fail-open like the
    -- import window, user-commit bypass included: a Save & Exit layout is
    -- live-authoritative by definition.
    if EllesmereUI._unlockResetConvergePending then
        if userCommit then
            EllesmereUI._unlockResetConvergePending = nil
        else
            return
        end
    end
    -- Default Editing Mode / editing-as session: live module sizes are the VIEW's
    -- swapped values, not the active layer's state (value writes resize bars); banking
    -- that geometry poisons the layer bucket. Fail-open: skip, next clean boundary
    -- banks. (_CondOv, not the Cond local: Cond lives in EUI_SpecOverrides_Conditional.lua.)
    if _defaultView or _editGroup
       or (EllesmereUI._CondOv and EllesmereUI._CondOv._edit) then return end
    -- Resolve the live layer's owning bucket: group layer (numeric active),
    -- conditional layer ("cond:<gid>" active), else baseline.
    local condGid = type(s.active) == "string" and tonumber(s.active:match("^cond:(%d+)$")) or nil
    local condBucket = condGid and condStore and condStore.layouts[condGid] or nil
    local prev
    if condGid then
        prev = condBucket or s.baselineLayout
    else
        prev = s.active and s.layouts[s.active] or s.baselineLayout
    end
    local snap = HarvestLayer(prev, s.baselineLayout)
    -- Deferred entries still awaiting their element are the layer's INTENDED state:
    -- live (the shared module store) hasn't caught up, so bank the intent, not the
    -- stale value. Pending BASELINE fallback entries are intent too -- without them a
    -- fast double-swap bakes the OUTGOING layer's still-live residue into this layer.
    if _unlockDeferredElemFallback then
        for key, e in pairs(_unlockDeferredElemFallback) do
            snap.elems[key] = DeepCopy(e)
        end
    end
    if _unlockDeferredElemLayout then
        for key, e in pairs(_unlockDeferredElemLayout) do
            snap.elems[key] = DeepCopy(e)
        end
    end
    -- Preserve entries for elements not currently registered (conditional /
    -- late registration: party+raid containers, CDM bars mid-rebuild).
    -- Absence from the registry means "unknown right now", never "deleted".
    if prev and prev.elems then
        local elems = EllesmereUI._unlockRegisteredElements
        for key, e in pairs(prev.elems) do
            if snap.elems[key] == nil and not (elems and elems[key]) then
                snap.elems[key] = DeepCopy(e)
            end
        end
    end
    -- Bake-in guard for GROUP/COND buckets: a key this layer never carried whose live
    -- geometry still MATCHES the baseline is baseline-FOLLOWING, not a layer edit, and
    -- banking it would freeze the baseline's value into the fork forever
    -- (late-registered elements, forks saved before an element existed). Keys that
    -- differ from the baseline are genuine edits and bank normally; the baseline
    -- bucket itself always banks everything.
    if prev and prev ~= s.baselineLayout and s.baselineLayout and s.baselineLayout.elems then
        local be = s.baselineLayout.elems
        local pe = prev.elems
        for key, e in pairs(snap.elems) do
            if (pe == nil or pe[key] == nil) and ElemNear(e, be[key]) then
                snap.elems[key] = nil
            end
        end
    end
    if condGid then
        if condBucket then
            condStore.layouts[condGid] = snap
        else
            s.baselineLayout = snap
            s.active = nil   -- heal: the condition layout was deleted
        end
    elseif s.active and s.layouts[s.active] then
        s.layouts[s.active] = snap
    else
        s.baselineLayout = snap
        s.active = nil   -- heal a dangling pointer (layout deleted elsewhere)
    end
end

--- Baseline link tables for profile unlockLayout snapshots: while a group layer
--- is LIVE the snapshot must come from the stored baseline, never the live
--- (group-valued) globals. Returns nil when live IS baseline. The 4th/5th
--- returns are the baseline's match extras (width, height), empty when none.
function EllesmereUI.SpecOverrides_UnlockBaselineLinks()
    local s = GetUnlockStore()
    if s and s.active and s.baselineLayout then
        return s.baselineLayout.anchors or {},
               s.baselineLayout.widthMatch or {},
               s.baselineLayout.heightMatch or {},
               s.baselineLayout.widthMatchExtra or {},
               s.baselineLayout.heightMatchExtra or {}
    end
    return nil
end

--- Resets the active pointer after a profile-level unlockLayout restore wrote
--- baseline links into the live globals (profile switch/import). The per-spec
--- overlay re-applies the correct layer right after, but only when the incoming
--- spec WANTS a layer: a baseline spec early-outs on want == active == nil while
--- module elem positions still hold the previous session's layer geometry (only
--- LINKS were restored), and the next harvest would bank that geometry into
--- baselineLayout via the freshly nil'd pointer. Clearing a LIVE pointer therefore
--- arms a runtime converge flag: layout banks stay suppressed until one forced
--- apply paints the pointer's truth (consumed in the Apply/ApplyValues tails
--- beside the import converge). Never arms for a pointer that was already nil.
function EllesmereUI.SpecOverrides_UnlockResetActive(profRoot)
    local s = profRoot and profRoot.specUnlockOverrides
    if not s then return end
    if s.active ~= nil then
        EllesmereUI._unlockResetConvergePending = true
    end
    s.active = nil
end

--- Completes a pending unlock-layer apply: performs deferred generic-element
--- writes (safe now that unlock re-registration has run), then runs one settle
--- so the screen reflects the swapped stores. Called from OnSpecSwitchComplete
--- (after CDM's spec rebuild) and from a two-frame fallback timer for paths
--- where that never fires.
function EllesmereUI.SpecOverrides_FlushUnlock()
    -- Combat defer: both halves reposition SECURE unit frames (savePosition closures
    -- re-anchor boss chains; the settle SetPoints unit buttons), blocked in lockdown as
    -- ADDON_ACTION_BLOCKED. Hold ALL pending state untouched and re-run once at
    -- PLAYER_REGEN_ENABLED (the settle is idempotent, only measures post-rebuild geometry).
    if InCombatLockdown() then
        _unlockFlushScheduled = true  -- keeps ScheduleUnlockFlush deduped
        EllesmereUI.CombatQueue.Defer("SpecOverridesFlushUnlock", function()
            if _unlockFlushScheduled then EllesmereUI.SpecOverrides_FlushUnlock() end
        end)
        return
    end
    _unlockFlushScheduled = false
    local pend = _unlockDeferredElemLayout
    _unlockDeferredElemLayout = nil
    local keep
    local wroteLayerSizes = false
    if pend then
        -- Sanctioned-write flag: several modules (Unit Frames, ABR) gate their
        -- setWidth/setHeight writes on unlock mode being active; the layer flush
        -- restores sizes OUTSIDE unlock mode and must pass those gates or the
        -- restore silently no-ops ("matched width bleeds to the default layout").
        EllesmereUI._unlockLayerApplying = true
        local elems = EllesmereUI._unlockRegisteredElements
        for key, e in pairs(pend) do
            local elem = elems and elems[key]
            if not elem then
                -- Conditional/late registration (party+raid containers, CDM
                -- bars mid-rebuild): hold the entry; RegisterUnlockElements
                -- pokes a re-flush the moment the element appears.
                keep = keep or {}
                keep[key] = e
            end
            -- A layer saved before its element took noSpecLayout keeps an
            -- entry nothing restores.
            if elem and not elem.noSpecLayout then
                -- Value-equal guards throughout: the arriving layer matches
                -- live for most elements; only real deltas write and settle.
                -- Anchor-owned keys never take elem positions (see
                -- UnlockElemAnchorOwned): the anchor is the authority.
                -- Raw-position elements take their stored table back verbatim,
                -- flags included (see the harvest).
                if e.rawPos and elem.saveRawPosition and not UnlockElemAnchorOwned(key) then
                    if not RawPosEqual(elem.loadRawPosition and elem.loadRawPosition(key), e) then
                        pcall(elem.saveRawPosition, key, e)
                        if elem.applyPosition then pcall(elem.applyPosition, key) end
                        _unlockSettleWanted = true
                    end
                elseif e.point and elem.savePosition and not UnlockElemAnchorOwned(key) then
                    local cur = elem.loadPosition and elem.loadPosition(key)
                    if not (cur and cur.point == e.point
                        and (cur.relPoint or cur.point) == (e.relPoint or e.point)
                        and cur.x == e.x and cur.y == e.y) then
                        pcall(elem.savePosition, key, e.point, e.relPoint or e.point, e.x, e.y)
                        -- Re-anchor through the element's OWN authority: noInitHook
                        -- elements (the RF raid container) are skipped by the settle's
                        -- saved-positions loop, so without this the DB gets the layer's
                        -- position but the frame stays where module init anchored it
                        -- from the PRE-flush value (login-only stale-layout visual).
                        if elem.applyPosition then pcall(elem.applyPosition, key) end
                        _unlockSettleWanted = true
                    end
                end
                -- A size the current look fixes (sizeFixedByLook) is never
                -- written: its setters refuse it under that look anyway.
                local curW, curH
                if elem.getSize then curW, curH = elem.getSize(key) end
                if e.w and elem.setWidth and not elem.sizeFixedByLook
                   and not (curW and math.abs(curW - e.w) < 0.5) then
                    pcall(elem.setWidth, key, e.w)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                if e.h and elem.setHeight and not elem.sizeFixedByLook
                   and not (curH and math.abs(curH - e.h) < 0.5) then
                    pcall(elem.setHeight, key, e.h)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
            end
        end
        EllesmereUI._unlockLayerApplying = nil
    end
    if keep then _unlockDeferredElemLayout = keep end
    -- Missing means baseline: elements the incoming layer carried no entry for
    -- restore their BASELINE geometry (stashed by ApplyLayer). The layer's own
    -- entries always win (pend/keep); each fallback entry is CONSUMED once applied
    -- so later flushes never stomp live drift, and still-unregistered elements are
    -- retained for the registration poke like kept pend entries.
    if _unlockDeferredElemFallback then
        local fb = _unlockDeferredElemFallback
        local elems = EllesmereUI._unlockRegisteredElements
        EllesmereUI._unlockLayerApplying = true
        for key, e in pairs(fb) do
            if (pend and pend[key] ~= nil) or (keep and keep[key] ~= nil) then
                fb[key] = nil   -- the layer owns this key
            elseif elems and elems[key] and elems[key].noSpecLayout then
                fb[key] = nil   -- no layer restores it (see the pend path)
            elseif elems and elems[key] then
                local elem = elems[key]
                -- Same anchor-owned skip as the pend path above.
                -- Same raw-position branch as the pend path above.
                if e.rawPos and elem.saveRawPosition and not UnlockElemAnchorOwned(key) then
                    if not RawPosEqual(elem.loadRawPosition and elem.loadRawPosition(key), e) then
                        pcall(elem.saveRawPosition, key, e)
                        if elem.applyPosition then pcall(elem.applyPosition, key) end
                        _unlockSettleWanted = true
                    end
                elseif e.point and elem.savePosition and not UnlockElemAnchorOwned(key) then
                    local cur = elem.loadPosition and elem.loadPosition(key)
                    if not (cur and cur.point == e.point
                        and (cur.relPoint or cur.point) == (e.relPoint or e.point)
                        and cur.x == e.x and cur.y == e.y) then
                        pcall(elem.savePosition, key, e.point, e.relPoint or e.point, e.x, e.y)
                        -- Same authority re-anchor as the pend path above
                        -- (the settle never moves noInitHook elements).
                        if elem.applyPosition then pcall(elem.applyPosition, key) end
                        _unlockSettleWanted = true
                    end
                end
                -- A size the current look fixes (sizeFixedByLook) is never
                -- written: its setters refuse it under that look anyway.
                local curW, curH
                if elem.getSize then curW, curH = elem.getSize(key) end
                if e.w and elem.setWidth and not elem.sizeFixedByLook
                   and not (curW and math.abs(curW - e.w) < 0.5) then
                    pcall(elem.setWidth, key, e.w)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                if e.h and elem.setHeight and not elem.sizeFixedByLook
                   and not (curH and math.abs(curH - e.h) < 0.5) then
                    pcall(elem.setHeight, key, e.h)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                fb[key] = nil   -- applied once; live drift owns it from here
            end
        end
        EllesmereUI._unlockLayerApplying = nil
        if not next(fb) then _unlockDeferredElemFallback = nil end
    end
    -- Element sizes live in MODULE settings (the same keys the value system
    -- captures), so a layer size stamp can overwrite a per-spec or Default view value
    -- applied before this deferred flush ran -- the flush runs last and would win,
    -- banking a value-overridden size into the shared baseline layer and stamping it
    -- onto specs that never had it. Re-run the value overlay so captured settings
    -- win (the layer's own store self-heals at its next harvest); runs BEFORE the
    -- settle so an active width/height match still owns matched sizes, and skips
    -- mid-transition (that apply is imminent).
    if wroteLayerSizes and not _inTransition then
        local touched = ApplyValuesFor(_activeSpec or CurrentSpecID())
        if EllesmereUI._CondOv then
            local t2 = EllesmereUI._CondOv.ApplyValues()
            if t2 then
                touched = touched or {}
                for k in pairs(t2) do touched[k] = true end
            end
        end
        if touched then RunRefreshers(touched) end
    end
    if not _unlockSettleWanted then return end
    -- Never fight an open unlock session; its own save/close flows settle.
    if EllesmereUI._unlockModeActive then return end
    _unlockSettleWanted = false
    if EllesmereUI.ApplyAllWidthHeightMatches then pcall(EllesmereUI.ApplyAllWidthHeightMatches) end
    if EllesmereUI._applySavedPositions then pcall(EllesmereUI._applySavedPositions) end
    if EllesmereUI.ResyncAnchorOffsets then pcall(EllesmereUI.ResyncAnchorOffsets) end
    if EllesmereUI.ReapplyAllUnlockAnchorsForced then
        EllesmereUI._reapplyForceEdgePreserve = true
        pcall(EllesmereUI.ReapplyAllUnlockAnchorsForced)
        EllesmereUI._reapplyForceEdgePreserve = false
    end
end

ScheduleUnlockFlush = function()
    if _unlockFlushScheduled then return end
    _unlockFlushScheduled = true
    -- Two frames: a profile-switch RefreshAllAddons finishes its child applies
    -- and unlock re-registration first. The CDM spec-rebuild path also flushes
    -- from OnSpecSwitchComplete; whichever runs first wins, the other no-ops.
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            if _unlockFlushScheduled then EllesmereUI.SpecOverrides_FlushUnlock() end
        end)
    end)
end

--- Re-flush poke from RegisterUnlockElements: deferred layer writes whose
--- elements were missing become applicable the moment they register. The
--- schedule is deduped, so a registration burst costs one flush.
function EllesmereUI.SpecOverrides_UnlockPokeFlush()
    if (_unlockDeferredElemLayout and next(_unlockDeferredElemLayout))
       or (_unlockDeferredElemFallback and next(_unlockDeferredElemFallback)) then
        ScheduleUnlockFlush()
    end
end

-- ---- layer management ---------------------------------------------------------

--- Deletes a group's custom unlock layout. When it is the ACTIVE layer, the
--- baseline layout is applied back to live.
function EllesmereUI.SpecOverrides_RemoveUnlockLayout(groupId)
    local s = GetUnlockStore()
    if not s or s.layouts[groupId] == nil then return false end
    s.layouts[groupId] = nil
    if s.active == groupId then
        s.active = nil
        if s.baselineLayout then
            ApplyLayer(s.baselineLayout)
            _unlockSettleWanted = true
            EllesmereUI.SpecOverrides_FlushUnlock()
        end
    end
    return true
end

-- ---- conditional unlock layouts (engine in EllesmereUI_Conditions.lua) -------

--- Deletes a conditional group's custom unlock layout; when live, the
--- baseline layout is applied back. Mirrors SpecOverrides_RemoveUnlockLayout.
function EllesmereUI.Conditions_RemoveUnlockLayout(condGid)
    local cs = EllesmereUI._CondOv and EllesmereUI._CondOv.GetUnlockStore()
    if not cs or cs.layouts[condGid] == nil then return false end
    cs.layouts[condGid] = nil
    local s = GetUnlockStore()
    if s and s.active == ("cond:" .. condGid) then
        s.active = nil
        if s.baselineLayout then
            ApplyLayer(s.baselineLayout)
            _unlockSettleWanted = true
            EllesmereUI.SpecOverrides_FlushUnlock()
        end
    end
    return true
end

-------------------------------------------------------------------------------
--  Buff Manager forks (Raid Frames "Buff Manager" tab): the unlock LAYER model
--  applied to the BM settings subtree. A BM LAYER is the complete subtree,
--  captured and applied WHOLESALE as deep copies:
--    indicators (bmIndicators), simple (bmSimple),
--    displayMode (bmDisplayMode, resolved), iconZoom (bmIconZoom, resolved).
--  Opt-in per override group via the full-page overlay on the BM tab during an
--  editing session. Harvest-on-leave / apply-on-enter at the SAME boundaries as
--  unlock layers; spec groups win over conditionals; establish transitions
--  apply without harvesting. Stores are profile-root siblings of the unlock
--  stores: specBmOverrides { layouts, baselineLayout, active } and
--  condBmOverrides { layouts }.
-------------------------------------------------------------------------------

local function GetBmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.specBmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.specBmOverrides = s
    end
    s.layouts = s.layouts or {}
    -- WoW Forever: the one-time buff clear of the fork stores, before anything
    -- banks into or applies from them ("fvBuffWipe" is its frozen mark,
    -- EllesmereUI_Migration.lua). A marked store costs one field read.
    local fv = EllesmereUI.FvBW
    if fv and s.fvBuffWipe == nil then fv.BmForks(prof) end
    return s
end

local function GetCondBmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.condBmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.condBmOverrides = s
    end
    s.layouts = s.layouts or {}
    -- WoW Forever: the one-time buff clear of the fork stores (see GetBmStore).
    local fv = EllesmereUI.FvBW
    if fv and s.fvBuffWipe == nil then fv.BmForks(prof) end
    return s
end

--- Deterministic BM owner for a spec (first group in creation order with a BM
--- layer containing the spec). Independent of unlock ownership: a group can
--- fork one system without the other.
local function BmOwnerGid(specID)
    if not specID then return nil end
    local s = GetBmStore()
    if not s or not next(s.layouts) then return nil end
    for _, g in ipairs(GetGroups() or {}) do
        if s.layouts[g.id] then
            for _, sid in ipairs(g.specs or {}) do
                if sid == specID then return g.id end
            end
        end
    end
    return nil
end

--- Builds a BM layer from the live RF profile. nil when RF's profile is absent
--- or never initialized -- never bank an empty layer over a stored one. The v2
--- payload (bm2 spec forks) rides the same layer; 12.1-born profiles may have
--- no legacy bmIndicators table at all, so either subtree qualifies the snap.
local function BmHarvestLayer()
    local rf = LiteProfile("EllesmereUIRaidFrames")
    if not rf then return nil end
    local fork = _G._ERF_BM2HarvestFork and _G._ERF_BM2HarvestFork() or nil
    if type(rf.bmIndicators) ~= "table" and not fork then return nil end
    return {
        indicators  = DeepCopy(rf.bmIndicators or {}),
        simple      = DeepCopy(rf.bmSimple or {}),
        displayMode = rf.bmDisplayMode or "custom",
        iconZoom    = rf.bmIconZoom or 0.08,
        bm2         = fork,
    }
end

--- Writes a BM layer into the live RF profile IN PLACE (wipe + refill: RF's
--- ns.db.profile IS this table and open BM pages capture subtable references)
--- and runs the BM-only refresh. Nothing here touches secure frames, so no
--- combat deferral is needed. noPageRefresh: skip the options-page repaint
--- (callers running DURING a page build repaint themselves; a nested
--- RefreshPage would rebuild inside a rebuild). Returns true only when the
--- paint actually LANDED -- callers gate pointer moves on it.
local function BmApplyLayer(layer, noPageRefresh)
    if not layer then return false end
    local rf = LiteProfile("EllesmereUIRaidFrames")
    if not rf then return false end
    local ind = rf.bmIndicators
    if type(ind) ~= "table" then ind = {}; rf.bmIndicators = ind end
    wipe(ind)
    for k, v in pairs(layer.indicators or {}) do ind[k] = DeepCopy(v) end
    local simple = rf.bmSimple
    if type(simple) ~= "table" then simple = {}; rf.bmSimple = simple end
    wipe(simple)
    for k, v in pairs(layer.simple or {}) do
        simple[k] = type(v) == "table" and DeepCopy(v) or v
    end
    rf.bmDisplayMode = layer.displayMode or "custom"
    rf.bmIconZoom = layer.iconZoom or 0.08
    -- v2 payload: applied through the BM2 bridge, which also converts
    -- legacy-only layers in place on first touch.
    if _G._ERF_BM2ApplyLayer then _G._ERF_BM2ApplyLayer(layer) end
    if _G._ERF_BMRefresh then _G._ERF_BMRefresh(noPageRefresh) end
    return true
end

--- Banks the LIVE Buff Manager into the layer it belongs to (active group
--- layer, conditional layer, else baseline). Runs at every transition boundary
--- while live still belongs to the outgoing state.
function EllesmereUI.SpecOverrides_HarvestBmLayout()
    local s = GetBmStore()
    if not s then return end
    -- Zero-cost for non-users: nothing to bank into until a fork exists.
    local cs = GetCondBmStore()
    if not s.active and not next(s.layouts) and not s.baselineLayout
       and not (cs and next(cs.layouts)) then return end
    -- Import window: same suppression as HarvestUnlockLayout (the BM forks
    -- arrived verbatim in the same import; live is residue).
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then return end
    end
    local snap = BmHarvestLayer()
    if not snap then return end
    -- Editing-as-conditional session swap: while a conditional's fork is
    -- session-applied (edited OUT of its real context), live belongs to THAT
    -- fork, never the runtime pointer's layer. Covers every transition boundary
    -- funneling through here (logout, export, profile switch) without touching
    -- the runtime pointer.
    local sessGid = EllesmereUI._bmSessionGid
    if sessGid then
        if cs and cs.layouts[sessGid] then
            cs.layouts[sessGid] = snap
        end
        return
    end
    local condGid = type(s.active) == "string" and tonumber(s.active:match("^cond:(%d+)$")) or nil
    if condGid then
        if cs and cs.layouts[condGid] then
            cs.layouts[condGid] = snap
        else
            -- Dangling pointer (layout deleted elsewhere): bank to baseline
            -- and heal, mirroring the unlock harvest.
            s.baselineLayout = snap
            s.active = nil
        end
    elseif s.active then
        if s.layouts[s.active] then
            s.layouts[s.active] = snap
        else
            s.baselineLayout = snap
            s.active = nil
        end
    else
        s.baselineLayout = snap
    end
end

--- WoW Forever: records the spec a live spec fork serves, the bucket the
--- Raid Frames Buff Manager (dm false) or Debuff Manager (dm true) renders
--- and edits: specID when want is a spec group's id and specID a retail spec
--- of the player's class, else nil. Returns the previous value. Runtime
--- only; callers gate on Forever.
function EllesmereUI._SO_SetForkSpec(dm, want, specID)
    local v = nil
    if type(want) == "number" and specID and EllesmereUI.IsPlayerSpec(specID)
       and EllesmereUI.RetailSpecName(specID) then
        v = specID
    end
    local prev
    if dm then
        prev = EllesmereUI.SpecOverrides_DmForkSpecID
        EllesmereUI.SpecOverrides_DmForkSpecID = v
        EllesmereUI._SO_DmForkSeeded = true
    else
        prev = EllesmereUI.SpecOverrides_BmForkSpecID
        EllesmereUI.SpecOverrides_BmForkSpecID = v
        EllesmereUI._SO_BmForkSeeded = true
    end
    return prev
end

--- WoW Forever: re-drives the aura containers after a fork spec moved with
--- no paint, and rebuilds the open manager page unless noPage (the caller is
--- a page build, or rebuilds the page itself).
function EllesmereUI._SO_ForkReDrive(dm, noPage)
    if _G._ERF_BMRefresh then _G._ERF_BMRefresh(dm or noPage) end
    if dm and not noPage and EllesmereUI:GetActiveModule() == "EllesmereUIRaidFrames"
       and EllesmereUI:GetActivePage() == "Debuff Manager" then
        EllesmereUI:RefreshPage(true)
    end
end

--- Swaps the live Buff Manager to the given spec's layer: the owner group's
--- fork, else the applied conditional's fork, else the baseline. Mirrors
--- SpecOverrides_ApplyUnlock (incl. the force flag for establish transitions);
--- NEVER harvests here.
function EllesmereUI.SpecOverrides_ApplyBm(specID, force, noPageRefresh)
    local s = GetBmStore()
    if not s then
        -- WoW Forever: no spec fork is live on a profile without the store.
        if EllesmereUI.IS_FOREVER then EllesmereUI._SO_SetForkSpec(false, nil) end
        return
    end
    -- Import window: NO apply may run between the store merge and the post-reload
    -- converge. Pre-reload the child Lite DBs still hold the OUTGOING profile's
    -- tables (the reload IS the switch), so a paint would "land" on the wrong
    -- profile while the pointer moves anyway, stranding imported fork content under
    -- the new pointer for the first harvest to bank over baselineLayout. The
    -- converge clears the flag before its forced apply, the first legal paint.
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            return
        end
    end
    specID = specID or _activeSpec or CurrentSpecID()
    if not specID then return end
    local want = BmOwnerGid(specID)
    local target
    if want then
        target = s.layouts[want]
    else
        local cond = EllesmereUI._CondOv and EllesmereUI._CondOv.ResolveGid
            and EllesmereUI._CondOv.ResolveGid() or nil
        if cond then
            local cs = GetCondBmStore()
            if cs and cs.layouts[cond] then
                want = "cond:" .. cond
                target = cs.layouts[cond]
            end
        end
    end
    -- WoW Forever: publish the spec the wanted layer serves before any paint
    -- (the paint's refresh reads it); with no paint, re-drive the frames and
    -- the open Buff Manager page when it moved. Put back below when the
    -- pointer does not move.
    local fvPrev
    if EllesmereUI.IS_FOREVER then
        EllesmereUI._SO_SeedForkSpec(false)
        fvPrev = EllesmereUI._SO_SetForkSpec(false, want, specID)
    end
    if want == s.active and not force then
        if EllesmereUI.IS_FOREVER and fvPrev ~= EllesmereUI.SpecOverrides_BmForkSpecID then
            EllesmereUI._SO_ForkReDrive(false, noPageRefresh)
        end
        return
    end
    if not target then target = s.baselineLayout end
    if target then
        -- The pointer advances ONLY when the paint lands. A silent no-op apply (RF
        -- store not ready, malformed layer) must never strand live content under the
        -- wrong pointer, or the next harvest banks it into the wrong layer (baseline
        -- overwritten by fork content). Failed applies retry naturally: want ~= active
        -- still holds at the next boundary.
        if BmApplyLayer(target, noPageRefresh) then
            s.active = want
        end
    elseif s.active == nil then
        -- Virgin store (no baseline banked yet): live IS the baseline, so the
        -- pointer may move without a paint.
        s.active = want
    else
        -- A layer is live but there is nothing to paint back (no
        -- baselineLayout): KEEP the old pointer so harvests keep banking live
        -- into the layer it actually holds.
    end
    -- WoW Forever: the pointer did not move, so the spec goes back to the
    -- one the live layer serves.
    if EllesmereUI.IS_FOREVER and s.active ~= want then
        EllesmereUI.SpecOverrides_BmForkSpecID = type(s.active) == "number" and fvPrev or nil
    end
end

-------------------------------------------------------------------------------
--  BM session swap: unlike unlock layouts (WYSIWYG against real frames), Buff
--  Manager settings need no real-context editing, so an editing-as-conditional
--  session may edit the group's fork ANYWHERE. The fork applies for the session via
--  a RUNTIME-ONLY flag (never persisted: a mid-session reload comes back on the
--  runtime pointer's layer, fail-safe); the session-aware branch in
--  SpecOverrides_HarvestBmLayout routes every mid-session bank into the fork. Spec
--  forks never need this: their member-spec gate guarantees the fork already IS
--  the runtime layer while editing is allowed.
-------------------------------------------------------------------------------

--- Applies the conditional's fork as the session-live BM layer. Idempotent.
local function BmSessionEngage(gid)
    if EllesmereUI._bmSessionGid == gid then return end
    local cs = GetCondBmStore()
    local layer = cs and cs.layouts[gid]
    if not layer then return end
    -- Flag only on a LANDED paint: a session flag over unswapped live banks
    -- the runtime layer's content into the fork at release.
    if BmApplyLayer(layer, true) then   -- callers run during a page build
        EllesmereUI._bmSessionGid = gid
    end
end

--- Banks the session's live edits into the fork and restores the runtime
--- layer. noApply: a transition is about to apply the runtime layer itself.
function EllesmereUI.SpecOverrides_BmSessionRelease(noApply)
    local gid = EllesmereUI._bmSessionGid
    if not gid then return end
    local cs = GetCondBmStore()
    if cs and cs.layouts[gid] then
        local snap = BmHarvestLayer()
        if snap then cs.layouts[gid] = snap end
    end
    EllesmereUI._bmSessionGid = nil
    if not noApply then
        EllesmereUI.SpecOverrides_ApplyBm(_activeSpec or CurrentSpecID(), true, true)
    end
end

--- Name of the override group whose Buff Manager fork is LIVE (session-applied
--- conditional first, then the runtime pointer), or nil when live is the
--- baseline. Drives the BM page's "Override Active" label.
function EllesmereUI.SpecOverrides_BmActiveInfo()
    local gid = EllesmereUI._bmSessionGid
    local isCond = gid ~= nil
    if not gid then
        local s = GetBmStore()
        local a = s and s.active
        if type(a) == "string" then
            gid = tonumber(a:match("^cond:(%d+)$"))
            isCond = true
        elseif type(a) == "number" then
            gid = a
        end
    end
    if not gid then return nil end
    local g
    if isCond then
        g = EllesmereUI.Conditions_GroupById and EllesmereUI.Conditions_GroupById(gid)
    else
        g = GroupById(gid)
    end
    return g and g.name or nil
end

--- kind ("spec"/"cond") + gid of the fork LIVE on the Buff Manager page, or nil
--- when not on that page / live is the baseline. The page is hard-bound to the
--- live fork (the prelude force-activates it), so every consumer (card locks,
--- session-entry blocks, passive chrome) keys off this.
function EllesmereUI.SpecOverrides_BmPageLockInfo()
    local mod = EllesmereUI:GetActiveModule()
    if mod ~= "EllesmereUIRaidFrames" then return nil end
    local page = EllesmereUI:GetActivePage()
    if page ~= "Buff Manager" then return nil end
    if EllesmereUI._bmSessionGid then return "cond", EllesmereUI._bmSessionGid end
    local s = GetBmStore()
    local a = s and s.active
    if type(a) == "number" then return "spec", a end
    if type(a) == "string" then
        local cg = tonumber(a:match("^cond:(%d+)$"))
        if cg then return "cond", cg end
    end
    return nil
end

--- True while the Buff Manager page is bound to a live fork (any kind).
function EllesmereUI.SpecOverrides_BmPageLocked()
    return EllesmereUI.SpecOverrides_BmPageLockInfo() ~= nil
end

--- Deletes a group's custom Buff Manager; when it is the ACTIVE layer the
--- baseline is applied back to live.
function EllesmereUI.SpecOverrides_RemoveBmLayout(groupId)
    local s = GetBmStore()
    if not s or s.layouts[groupId] == nil then return false end
    s.layouts[groupId] = nil
    if s.active == groupId then
        -- WoW Forever: the baseline serves no fork spec; cleared before the
        -- paint (its refresh reads it), put back when the paint fails.
        local fvPrev
        if EllesmereUI.IS_FOREVER then
            fvPrev = EllesmereUI._SO_SetForkSpec(false, nil)
        end
        -- Pointer moves only with a landed paint (or nothing to restore).
        if not s.baselineLayout or BmApplyLayer(s.baselineLayout) then
            s.active = nil
            -- Nothing painted: the frames move to the class's bucket.
            if fvPrev and not s.baselineLayout then EllesmereUI._SO_ForkReDrive(false) end
        elseif EllesmereUI.IS_FOREVER then
            EllesmereUI.SpecOverrides_BmForkSpecID = fvPrev
        end
    end
    return true
end

--- Conditional twin of SpecOverrides_RemoveBmLayout.
function EllesmereUI.Conditions_RemoveBmLayout(condGid)
    local cs = GetCondBmStore()
    if not cs or cs.layouts[condGid] == nil then return false end
    cs.layouts[condGid] = nil
    local s = GetBmStore()
    if s and s.active == ("cond:" .. condGid) then
        if not s.baselineLayout or BmApplyLayer(s.baselineLayout) then
            s.active = nil
        end
    end
    -- Deleted while session-applied (cards popup is reachable mid-session):
    -- drop the flag and put the runtime layer back, discarding the orphan.
    if EllesmereUI._bmSessionGid == condGid then
        EllesmereUI._bmSessionGid = nil
        EllesmereUI.SpecOverrides_ApplyBm(_activeSpec or CurrentSpecID(), true)
    end
    return true
end

--- Orphan-heal for a stored profile's BM pointer (import/restore path).
--- Deliberately NOT an unconditional reset: BM live data and pointer travel
--- together inside the profile blob (export harvests first), so a consistent
--- foreign pointer converges via the establish force-apply. Only a pointer at a
--- DELETED layout is healed -- nil-ing a consistent pointer makes the next
--- harvest bank fork data into the baseline.
function EllesmereUI.SpecOverrides_BmResetActive(profRoot)
    local s = profRoot and profRoot.specBmOverrides
    if not s or s.active == nil then return end
    local a = s.active
    if type(a) == "string" then
        local gid = tonumber(a:match("^cond:(%d+)$"))
        local cs = profRoot.condBmOverrides
        if not (gid and cs and type(cs.layouts) == "table" and cs.layouts[gid]) then
            s.active = nil
        end
    elseif not (type(s.layouts) == "table" and s.layouts[a]) then
        s.active = nil
    end
end

-------------------------------------------------------------------------------
--  Debuff Manager forks: the BM layer model applied to the RF dmDebuff subtree.
--  A DM LAYER is { dm = deep copy of the profile's dmDebuff table }. Same
--  boundaries and precedence (spec groups beat conditionals), independent
--  opt-in: a group can fork either manager without the other. Stores:
--  specDmOverrides { layouts, baselineLayout, active } and condDmOverrides
--  { layouts }. Live apply/harvest runs through the _ERF_DM* bridges exported
--  by the Debuff Manager file; every call is existence-guarded, so the feature
--  is inert when that file is absent.
-------------------------------------------------------------------------------

local function GetDmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.specDmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.specDmOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

local function GetCondDmStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.condDmOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.condDmOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

--- Deterministic DM owner for a spec (first group in creation order with a
--- DM layer containing the spec). Independent of BM/unlock ownership.
local function DmOwnerGid(specID)
    if not specID then return nil end
    local s = GetDmStore()
    if not s or not next(s.layouts) then return nil end
    for _, g in ipairs(GetGroups() or {}) do
        if s.layouts[g.id] then
            for _, sid in ipairs(g.specs or {}) do
                if sid == specID then return g.id end
            end
        end
    end
    return nil
end

--- Builds a DM layer from the live profile via the bridge. nil when the Debuff
--- Manager is unavailable -- never bank an empty layer over a stored one.
local function DmHarvestLayer()
    local dm = _G._ERF_DMHarvestFork and _G._ERF_DMHarvestFork() or nil
    if not dm then return nil end
    return { dm = dm }
end

--- Writes a DM layer into the live profile through the bridge (wipe + refill in
--- place) and runs the DM-only refresh. Returns true only when the paint landed
--- (pointer moves gate on it).
local function DmApplyLayer(layer, noPageRefresh)
    if not layer or not layer.dm then return false end
    if not _G._ERF_DMApplyLayer then return false end
    return _G._ERF_DMApplyLayer(layer.dm, noPageRefresh) and true or false
end

--- Banks the LIVE Debuff Manager into the layer it belongs to. Runs at every
--- transition boundary while live still belongs to the outgoing state (mirror
--- of SpecOverrides_HarvestBmLayout).
function EllesmereUI.SpecOverrides_HarvestDmLayout()
    local s = GetDmStore()
    if not s then return end
    local cs = GetCondDmStore()
    if not s.active and not next(s.layouts) and not s.baselineLayout
       and not (cs and next(cs.layouts)) then return end
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then return end
    end
    local snap = DmHarvestLayer()
    if not snap then return end
    local sessGid = EllesmereUI._dmSessionGid
    if sessGid then
        if cs and cs.layouts[sessGid] then
            cs.layouts[sessGid] = snap
        end
        return
    end
    local condGid = type(s.active) == "string" and tonumber(s.active:match("^cond:(%d+)$")) or nil
    if condGid then
        if cs and cs.layouts[condGid] then
            cs.layouts[condGid] = snap
        else
            s.baselineLayout = snap
            s.active = nil
        end
    elseif s.active then
        if s.layouts[s.active] then
            s.layouts[s.active] = snap
        else
            s.baselineLayout = snap
            s.active = nil
        end
    else
        s.baselineLayout = snap
    end
end

--- WoW Forever: publishes a fork spec from the saved pointer at its first
--- read or apply, once per manager (dm true: Debuff Manager) per session.
--- The pointer's fork is already live at login, so the frames build with
--- its bucket before the deferred login apply (and through a /reload in
--- combat, which defers that apply). Latched even when nothing publishes:
--- after it the value moves only through a path that re-drives the frames.
function EllesmereUI._SO_SeedForkSpec(dm)
    if dm then
        if EllesmereUI._SO_DmForkSeeded then return end
    elseif EllesmereUI._SO_BmForkSeeded then
        return
    end
    local want, cur, owner
    local prof = GetProfileRoot()
    if prof and not prof._importEstablishPending then
        local s
        if dm then s = GetDmStore() else s = GetBmStore() end
        want = s and s.active
    end
    if type(want) == "number" then
        cur = CurrentSpecID()
        if cur then
            if dm then owner = DmOwnerGid(cur) else owner = BmOwnerGid(cur) end
        end
    end
    EllesmereUI._SO_SetForkSpec(dm, owner == want and owner or nil, cur)
end

--- Swaps the live Debuff Manager to the given spec's layer (mirror of
--- SpecOverrides_ApplyBm). NEVER harvests here.
function EllesmereUI.SpecOverrides_ApplyDm(specID, force, noPageRefresh)
    local s = GetDmStore()
    if not s then
        -- WoW Forever: no spec fork is live on a profile without the store.
        if EllesmereUI.IS_FOREVER then EllesmereUI._SO_SetForkSpec(true, nil) end
        return
    end
    -- Import window: same suppression as SpecOverrides_ApplyBm (pre-reload
    -- paints land on the outgoing profile's tables).
    do
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            return
        end
    end
    specID = specID or _activeSpec or CurrentSpecID()
    if not specID then return end
    local want = DmOwnerGid(specID)
    local target
    if want then
        target = s.layouts[want]
    else
        local cond = EllesmereUI._CondOv and EllesmereUI._CondOv.ResolveGid
            and EllesmereUI._CondOv.ResolveGid() or nil
        if cond then
            local cs = GetCondDmStore()
            if cs and cs.layouts[cond] then
                want = "cond:" .. cond
                target = cs.layouts[cond]
            end
        end
    end
    -- WoW Forever: publish the spec the wanted layer serves (see the BM
    -- twin); with no paint, re-drive the frames and the open Debuff Manager
    -- page when it moved.
    local fvPrev
    if EllesmereUI.IS_FOREVER then
        EllesmereUI._SO_SeedForkSpec(true)
        fvPrev = EllesmereUI._SO_SetForkSpec(true, want, specID)
    end
    if want == s.active and not force then
        if EllesmereUI.IS_FOREVER and fvPrev ~= EllesmereUI.SpecOverrides_DmForkSpecID then
            EllesmereUI._SO_ForkReDrive(true, noPageRefresh)
        end
        return
    end
    if not target then target = s.baselineLayout end
    if target then
        -- Pointer advances ONLY when the paint lands (see the BM twin: a
        -- silent no-op apply must never strand live content under the wrong
        -- pointer, or the next harvest banks it into the wrong layer).
        if DmApplyLayer(target, noPageRefresh) then
            s.active = want
        end
    elseif s.active == nil then
        s.active = want
    end
    -- WoW Forever: the pointer did not move (see the BM twin).
    if EllesmereUI.IS_FOREVER and s.active ~= want then
        EllesmereUI.SpecOverrides_DmForkSpecID = type(s.active) == "number" and fvPrev or nil
    end
end

--- Applies the conditional's fork as the session-live DM layer (mirror of
--- BmSessionEngage; runtime-only flag, never persisted).
local function DmSessionEngage(gid)
    if EllesmereUI._dmSessionGid == gid then return end
    local cs = GetCondDmStore()
    local layer = cs and cs.layouts[gid]
    if not layer then return end
    if DmApplyLayer(layer, true) then   -- flag only on a landed paint
        EllesmereUI._dmSessionGid = gid
    end
end

--- Banks the session's live edits into the fork and restores the runtime
--- layer. noApply: a transition is about to apply the runtime layer itself.
function EllesmereUI.SpecOverrides_DmSessionRelease(noApply)
    local gid = EllesmereUI._dmSessionGid
    if not gid then return end
    local cs = GetCondDmStore()
    if cs and cs.layouts[gid] then
        local snap = DmHarvestLayer()
        if snap then cs.layouts[gid] = snap end
    end
    EllesmereUI._dmSessionGid = nil
    if not noApply then
        EllesmereUI.SpecOverrides_ApplyDm(_activeSpec or CurrentSpecID(), true, true)
    end
end

--- Name of the override group whose Debuff Manager fork is LIVE, or nil when
--- live is the baseline.
function EllesmereUI.SpecOverrides_DmActiveInfo()
    local gid = EllesmereUI._dmSessionGid
    local isCond = gid ~= nil
    if not gid then
        local s = GetDmStore()
        local a = s and s.active
        if type(a) == "string" then
            gid = tonumber(a:match("^cond:(%d+)$"))
            isCond = true
        elseif type(a) == "number" then
            gid = a
        end
    end
    if not gid then return nil end
    local g
    if isCond then
        g = EllesmereUI.Conditions_GroupById and EllesmereUI.Conditions_GroupById(gid)
    else
        g = GroupById(gid)
    end
    return g and g.name or nil
end

--- kind + gid of the fork LIVE on the Debuff Manager page, or nil when not
--- on that page / live is the baseline (mirror of BmPageLockInfo).
function EllesmereUI.SpecOverrides_DmPageLockInfo()
    local mod = EllesmereUI:GetActiveModule()
    if mod ~= "EllesmereUIRaidFrames" then return nil end
    local page = EllesmereUI:GetActivePage()
    if page ~= "Debuff Manager" then return nil end
    if EllesmereUI._dmSessionGid then return "cond", EllesmereUI._dmSessionGid end
    local s = GetDmStore()
    local a = s and s.active
    if type(a) == "number" then return "spec", a end
    if type(a) == "string" then
        local cg = tonumber(a:match("^cond:(%d+)$"))
        if cg then return "cond", cg end
    end
    return nil
end

--- True while the Debuff Manager page is bound to a live fork (any kind).
function EllesmereUI.SpecOverrides_DmPageLocked()
    return EllesmereUI.SpecOverrides_DmPageLockInfo() ~= nil
end

--- Deletes a group's custom Debuff Manager; when it is the ACTIVE layer the
--- baseline is applied back to live.
function EllesmereUI.SpecOverrides_RemoveDmLayout(groupId)
    local s = GetDmStore()
    if not s or s.layouts[groupId] == nil then return false end
    s.layouts[groupId] = nil
    if s.active == groupId then
        -- WoW Forever: the baseline serves no fork spec (see the BM twin).
        local fvPrev
        if EllesmereUI.IS_FOREVER then
            fvPrev = EllesmereUI._SO_SetForkSpec(true, nil)
        end
        if not s.baselineLayout or DmApplyLayer(s.baselineLayout) then
            s.active = nil
            -- Nothing painted: the frames and the open Debuff Manager page
            -- move to the class's bucket.
            if fvPrev and not s.baselineLayout then EllesmereUI._SO_ForkReDrive(true) end
        elseif EllesmereUI.IS_FOREVER then
            EllesmereUI.SpecOverrides_DmForkSpecID = fvPrev
        end
    end
    return true
end

--- Conditional twin of SpecOverrides_RemoveDmLayout.
function EllesmereUI.Conditions_RemoveDmLayout(condGid)
    local cs = GetCondDmStore()
    if not cs or cs.layouts[condGid] == nil then return false end
    cs.layouts[condGid] = nil
    local s = GetDmStore()
    if s and s.active == ("cond:" .. condGid) then
        if not s.baselineLayout or DmApplyLayer(s.baselineLayout) then
            s.active = nil
        end
    end
    if EllesmereUI._dmSessionGid == condGid then
        EllesmereUI._dmSessionGid = nil
        EllesmereUI.SpecOverrides_ApplyDm(_activeSpec or CurrentSpecID(), true)
    end
    return true
end

--- Orphan-heal for a stored profile's DM pointer (import/restore path);
--- same only-heal-dangling policy as SpecOverrides_BmResetActive.
function EllesmereUI.SpecOverrides_DmResetActive(profRoot)
    local s = profRoot and profRoot.specDmOverrides
    if not s or s.active == nil then return end
    local a = s.active
    if type(a) == "string" then
        local gid = tonumber(a:match("^cond:(%d+)$"))
        local cs = profRoot.condDmOverrides
        if not (gid and cs and type(cs.layouts) == "table" and cs.layouts[gid]) then
            s.active = nil
        end
    elseif not (type(s.layouts) == "table" and s.layouts[a]) then
        s.active = nil
    end
end

--- "Customize Unlock Mode" on a CONDITIONAL group card. Only valid while the group
--- is the ACTIVE conditional (WYSIWYG: author the dungeon layout in a dungeon --
--- mirror of "member spec required" for spec groups) and the current spec's own
--- group has NO layout (spec layers void conditionals entirely). First click forks
--- from live (= baseline, since no layer is applied) behind a confirm popup.
function EllesmereUI.Conditions_EnterUnlockForGroup(g)
    if type(g) == "number" then g = EllesmereUI.Conditions_GroupById(g) end
    if not g then return end
    -- Dark Mode groups are values-only: no unlock layer may ever exist for them
    -- (the card never builds the button; this is the belt guard).
    if g.conds and g.conds.darkmode then return end
    if EllesmereUI._unlockModeActive then return end
    local cur = CurrentSpecID()
    if OwnerGid(cur) then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("Your current spec has its own custom unlock mode, so conditional unlock modes never apply to it. Swap to a spec without one to customize this."),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    local activeG = EllesmereUI.Conditions_ActiveGroup and EllesmereUI.Conditions_ActiveGroup()
    if not activeG or activeG.id ~= g.id then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("This conditional is not active right now. Meet one of its conditions first (for example, enter the dungeon) so you can arrange the layout in its real context."),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    local cs = EllesmereUI._CondOv.GetUnlockStore(true)
    local s = GetUnlockStore(true)
    if not cs or not s then return end
    if cs.layouts[g.id] == nil then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("This will create a fully unique unlock mode for this conditional group. Changes made to your default unlock mode will no longer affect it."),
            confirmText = L("Create"),
            cancelText = L("Cancel"),
            onConfirm = function()
                if cs.layouts[g.id] ~= nil then return end
                -- Bank live into its current owner (the baseline: the guards
                -- above ensure no layer is applied), fork it, activate in place
                -- (live is byte-identical to the new layer).
                EllesmereUI.SpecOverrides_HarvestUnlockLayout()
                -- Virgin-store baseline seed: without it there is nothing to
                -- restore when the condition ends (see the spec fork twin in
                -- SpecOverrides_EnterUnlockForGroup).
                if not s.baselineLayout and not s.active then
                    s.baselineLayout = HarvestLayer()
                end
                cs.layouts[g.id] = HarvestLayer(s.baselineLayout)
                s.active = "cond:" .. g.id
                EllesmereUI.Conditions_EnterUnlockForGroup(g)
            end,
        })
        return
    end
    -- Layout exists but is not the live layer yet (fresh login before any
    -- flip): route through the engine so the layer applies first.
    if s.active ~= ("cond:" .. g.id) then
        if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
        if GetUnlockStore().active ~= ("cond:" .. g.id) then return end
    end
    if _editGroup then ExitGroupEdit(true) end
    local panel = EllesmereUI._mainFrame
    if panel and panel:IsShown() then panel:Hide() end
    C_Timer.After(0, function()
        if EllesmereUI._openUnlockMode then EllesmereUI._openUnlockMode() end
    end)
end

-- ---- special unlock entry ------------------------------------------------------

--- "Customize Unlock Mode" on a group card. Only valid when the current spec is
--- a member (unlock always shows the current spec's layout). The FIRST click is
--- the fork moment and asks for confirmation; afterwards it just opens unlock
--- mode, which edits the group's (active) layer.
function EllesmereUI.SpecOverrides_EnterUnlockForGroup(g)
    if type(g) == "number" then g = GroupById(g) end
    if not g then return end
    local cur = CurrentSpecID()
    local member = false
    for _, sid in ipairs(g.specs or {}) do
        if sid == cur then member = true; break end
    end
    if not member then return end
    if EllesmereUI._unlockModeActive then return end
    -- Exclusive layer ownership: when ANOTHER group's layout already provides this
    -- spec's unlock mode, refuse fork creation AND editing here. A fork born under a
    -- non-owner group can never apply to this spec; it sits dead until a group or
    -- layout deletion promotes it, replacing the spec's unlock mode with a stale layout.
    do
        local own = OwnerGid(cur)
        if own and own ~= g.id then
            local og = GroupById(own)
            EllesmereUI:ShowConfirmPopup({
                title = L("Customize Unlock Mode"),
                message = string.format(L("The override group '%s' already provides the custom unlock mode for your current spec. Customize it there, or remove this spec from that group."), (og and og.name) or "?"),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    local s = GetUnlockStore(true)
    if not s then return end
    if s.layouts[g.id] == nil then
        EllesmereUI:ShowConfirmPopup({
            title = L("Customize Unlock Mode"),
            message = L("This will create a fully unique unlock mode for this override group. Changes made to your default unlock mode will no longer affect these specs."),
            confirmText = L("Create"),
            cancelText = L("Cancel"),
            onConfirm = function()
                local s2 = GetUnlockStore(true)
                if not s2 or s2.layouts[g.id] ~= nil then return end
                -- Fork from the current live layout: bank live into its owner
                -- first (keeps that layer current).
                EllesmereUI.SpecOverrides_HarvestUnlockLayout()
                -- First-ever layer on a virgin store: capture the shared BASELINE from
                -- the pre-fork live layout (live IS the baseline when no layer is
                -- active). Without it, a non-member spec taking over has nothing to
                -- restore to: the fork's edits stick and the next harvest adopts them
                -- AS the default layout.
                if not s2.baselineLayout and not s2.active then
                    s2.baselineLayout = HarvestLayer()
                end
                -- Seed from the BASELINE whenever any OTHER layer is live (conditional
                -- or another spec group): harvesting live would seed the new fork with
                -- a layout its specs never owned. Live-harvest seeding is only correct
                -- when live IS the baseline -- a spec group voids conditionals
                -- entirely, so its layer must never be born from a dungeon/raid arrangement.
                local fromCond = type(s2.active) == "string"
                local fromOtherGroup = type(s2.active) == "number" and s2.active ~= g.id
                if (fromCond or fromOtherGroup) and s2.baselineLayout then
                    s2.layouts[g.id] = DeepCopy(s2.baselineLayout)
                else
                    s2.layouts[g.id] = HarvestLayer(s2.baselineLayout)
                end
                if OwnerGid(cur) == g.id then
                    s2.active = g.id
                    -- Baseline-seeded fork while another layer was showing:
                    -- that layer ceased to apply for this spec, so switch the
                    -- screen to the new (base-identical) layer now.
                    if fromCond or fromOtherGroup then
                        ApplyLayer(s2.layouts[g.id], s2.baselineLayout)
                        _unlockSettleWanted = true
                        EllesmereUI.SpecOverrides_FlushUnlock()
                    end
                end
                if RefreshCardsPopup then RefreshCardsPopup() end
                EllesmereUI.SpecOverrides_EnterUnlockForGroup(g)
            end,
        })
        return
    end
    -- Editing-as and unlock sessions never coexist. Banking the panel session
    -- first also restores canonical live values.
    if _editGroup then ExitGroupEdit(true) end
    local panel = EllesmereUI._mainFrame
    if panel and panel:IsShown() then panel:Hide() end
    C_Timer.After(0, function()
        if EllesmereUI._openUnlockMode then EllesmereUI._openUnlockMode() end
    end)
end

I.BmApplyLayer, I.BmHarvestLayer, I.BmOwnerGid = BmApplyLayer, BmHarvestLayer, BmOwnerGid
I.BmSessionEngage, I.DmApplyLayer = BmSessionEngage, DmApplyLayer
I.DmHarvestLayer, I.DmOwnerGid, I.DmSessionEngage = DmHarvestLayer, DmOwnerGid, DmSessionEngage
I.GetBmStore, I.GetCondBmStore, I.GetCondDmStore = GetBmStore, GetCondBmStore, GetCondDmStore
I.GetDmStore, I.IsTBBChildKey, I.LayerSkipsKey = GetDmStore, IsTBBChildKey, LayerSkipsKey
I.LiteProfile = LiteProfile
I.broken = false
