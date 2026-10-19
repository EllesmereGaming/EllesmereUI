if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_Harvest.lua
--
--  Harvest and apply (save-on-leave, apply-on-enter) and the unlock layout
--  overrides.
--  Reads the earlier Spec Overrides files through EUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
local I = EUI_NS._soInternals
-- EllesmereUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local BlacklistedFKey, ConflictSpec = I.BlacklistedFKey, I.ConflictSpec
local CurrentSpecID, DeepCopy, EntryOwning = I.CurrentSpecID, I.DeepCopy, I.EntryOwning
local FKeyLoaded, FS, GetGroups = I.FKeyLoaded, I.FS, I.GetGroups
local GetProfileRoot, GetStore, GOLD_B = I.GetProfileRoot, I.GetStore, I.GOLD_B
local GOLD_G, GOLD_R, GroupById = I.GOLD_G, I.GOLD_R, I.GroupById
local HasRegisteredDefault, L, MatchOwnedFKey = I.HasRegisteredDefault, I.L, I.MatchOwnedFKey
local NIL_SENT, PS, PxCo, ReadLive = I.NIL_SENT, I.PS, I.PxCo, I.ReadLive
local RebuildFKeyIndex, RunRefreshers = I.RebuildFKeyIndex, I.RunRefreshers
local SnapValue, SpecInAnyGroup, SplitFKey = I.SnapValue, I.SpecInAnyGroup, I.SplitFKey
local WriteLive, SetEditGroup, SetDefaultView = I.WriteLive, I.SetEditGroup, I.SetDefaultView
local SetInTransition, SetActiveSpec = I.SetInTransition, I.SetActiveSpec

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _editGroup = nil
I.editGroupSetters[#I.editGroupSetters + 1] = function(v) _editGroup = v end
local _defaultView = false   -- panel open in Default Editing Mode: live holds
                             -- the stored DEFAULT values for captured paths
I.defaultViewSetters[#I.defaultViewSetters + 1] = function(v) _defaultView = v end
local _enterSnap = nil       -- profiles snapshot from session start (set by editing-as
                             -- enter flows; baseline for exit-sweep + HarvestGroup revert detection)
I.enterSnapSetters[#I.enterSnapSetters + 1] = function(v) _enterSnap = v end
local RequestGoldWalk
I.goldWalkSetters[#I.goldWalkSetters + 1] = function(v) RequestGoldWalk = v end
local SweepUncaptured
I.sweepSetters[#I.sweepSetters + 1] = function(v) SweepUncaptured = v end
local TeardownEditSession
I.teardownSetters[#I.teardownSetters + 1] = function(v) TeardownEditSession = v end
local PanelShown
I.panelShownSetters[#I.panelShownSetters + 1] = function(v) PanelShown = v end
local EnterDefaultView
I.enterDefaultViewSetters[#I.enterDefaultViewSetters + 1] = function(v) EnterDefaultView = v end
local UpdateIndicator
I.updateIndicatorSetters[#I.updateIndicatorSetters + 1] = function(v) UpdateIndicator = v end
local RefreshCardsPopup
I.refreshCardsSetters[#I.refreshCardsSetters + 1] = function(v) RefreshCardsPopup = v end

-------------------------------------------------------------------------------
--  Harvest / Apply  (save-on-leave, apply-on-enter)
-------------------------------------------------------------------------------
local _inTransition = false   -- suppresses HarvestCurrent between leave & apply
I.inTransitionSetters[#I.inTransitionSetters + 1] = function(v) _inTransition = v end
local _activeSpec = nil       -- spec whose values currently sit in the live db
                              -- (ignoring a temporary Editing-as swap)
I.activeSpecSetters[#I.activeSpecSetters + 1] = function(v) _activeSpec = v end

-- Reads the live value of every captured path into a map.
local function HarvestMap()
    local store = GetStore()
    if not store or #store == 0 then return nil end
    local maps = {}
    for i, entry in ipairs(store) do
        local m = {}
        for fkey in pairs(entry.values.default) do
            if not FKeyLoaded(fkey) then
                -- Disabled child addon: keep the recorded default so the equality
                -- branch retains each spec's stored value instead of banking NIL_SENT over it.
                m[fkey] = entry.values.default[fkey]
            else
                local v = ReadLive(fkey)
                if v == nil then
                    m[fkey] = NIL_SENT
                elseif type(v) == "table" then
                    m[fkey] = entry.values.default[fkey]   -- structure changed; keep default
                else
                    m[fkey] = v
                end
            end
        end
        maps[i] = m
    end
    return maps
end

-- REVERT SEMANTICS shared by the spec-side banks: a value the USER moved back onto
-- the entry's recorded default is a REVERT ("set back to default = no longer an
-- override") and clears instead of storing. CRITICAL: bare equality is NOT proof of
-- a revert -- the default is movable (Default Editing Mode edits rewrite it), and
-- once edited ONTO a group's value every held override compares equal; clearing on
-- equality alone would dissolve overrides one harvest at a time as the next default
-- edit drags them along. HarvestGroup treats equality as a revert ONLY when the
-- session actually changed the value (live differs from the session-start snapshot);
-- Harvest has no session context and never clears a held key on equality alone.
local function Harvest(specID)
    if not specID then return end
    local store = GetStore()
    local maps = HarvestMap()
    if not maps then return end
    -- Per-spec adoption is for GROUP MEMBERS only: an ungrouped spec's live data
    -- mirrors the shared defaults (panel edits go through the Default view), so any
    -- diff here is a foreign write (unlock layer size stamp, deleted-group leftover,
    -- out-of-panel edit) that would plant a permanent self-renewing phantom override.
    -- Ungrouped specs keep their existing stored maps (legacy pre-group data).
    if not SpecInAnyGroup(specID) then return end
    for i, entry in ipairs(store) do
        local m = maps[i]
        local prev = entry.values[specID]
        local has = false
        for fkey, dv in pairs(entry.values.default) do
            if MatchOwnedFKey(fkey) then
                -- Match-owned size keys: live is the match engine's write, never a user
                -- edit; Apply skips them so live permanently diverges from stored.
                -- Banking it would adopt the matched width into every spec map it
                -- touches (store-wide homogenization) -- retain stored verbatim.
                if prev then m[fkey] = prev[fkey] else m[fkey] = nil end
            elseif m[fkey] == dv then
                -- Equal to default is never a revert outside a session (the default
                -- may have moved onto the override); retain the stored value. No
                -- and/or chain: a stored boolean false must survive retention.
                if prev then m[fkey] = prev[fkey] else m[fkey] = nil end
            end
            if m[fkey] ~= nil then has = true end
        end
        entry.values[specID] = has and m or nil
    end
end

-- Garbage-collects fkeys no group map holds a value for (their harvests all
-- diff-cleared as reverts), and entries left with no fkeys. NEVER judges by equality
-- against the default: the default is movable (Default view edits rewrite it), and
-- equality-pruning against a moved default deletes intentional overrides.
local function PruneRedundantValues()
    local store = GetStore()
    if not store then return end
    local changed = false
    for i = #store, 1, -1 do
        local e = store[i]
        local def = e.values and e.values.default
        if def then
            for fkey in pairs(def) do
                local held = false
                for k, m in pairs(e.values) do
                    if k ~= "default" and type(m) == "table" and m[fkey] ~= nil then
                        held = true
                        break
                    end
                end
                if not held then
                    -- An exact-size companion stays while its size key does (PxCo).
                    local base = fkey:sub(-2) == "Px" and fkey:sub(1, -3) or nil
                    if base and def[base] ~= nil and PxCo.Partner(base) == fkey then held = true end
                end
                if not held then
                    -- GC only when live actually matches the recorded default: a cleared
                    -- holder whose repaint has not landed (spec-nil login window,
                    -- deferred heal apply) still has the override LIVE, and dropping the
                    -- default would orphan it permanently. Blacklisted paths are never
                    -- applied and GC freely; an unloaded module can't be verified and is kept.
                    local canGC = BlacklistedFKey(fkey)
                    if not canGC and FKeyLoaded(fkey) then
                        local dv = def[fkey]
                        if dv == NIL_SENT then dv = nil end
                        local cur = ReadLive(fkey)
                        if type(dv) == "table" or type(cur) == "table" or cur == dv then
                            canGC = true
                        end
                    end
                    if canGC then
                        def[fkey] = nil
                        changed = true
                    end
                end
            end
            if not next(def) then
                table.remove(store, i)
                changed = true
            end
        end
    end
    if changed then
        RebuildFKeyIndex()
        RequestGoldWalk()
    end
end

-- Banks live values into EVERY member spec of a group. Entries owned by a CONFLICTING
-- group (shared specs) are skipped entirely -- those slots are blocked in the UI and
-- the other group's values must survive untouched. Revert detection: a live value
-- equal to the recorded default clears the members' override ONLY when this session
-- moved it there (live differs from the session-start snapshot); merely comparing
-- equal without having moved it retains each member's stored value instead.
local function HarvestGroup(group)
    if not group then return end
    local store = GetStore()
    local maps = HarvestMap()
    if not maps then return end
    for i, entry in ipairs(store) do
        if not ConflictSpec(entry, group) then
            local m = maps[i]
            local preserve
            for fkey, dv in pairs(entry.values.default) do
                if MatchOwnedFKey(fkey) then
                    -- Match-owned size keys never bank FROM live (see Harvest): the
                    -- broadcast below would stamp the match engine's write onto EVERY
                    -- member at once. Route through preserve so each member keeps its own value.
                    preserve = preserve or {}
                    preserve[fkey] = true
                    m[fkey] = nil
                elseif m[fkey] == dv then
                    local s = _enterSnap and SnapValue(_enterSnap, fkey)
                    if type(s) == "table" then s = nil end
                    s = (s == nil) and NIL_SENT or s
                    if not _enterSnap or s == m[fkey] then
                        -- Untouched this session: not a revert. Each member
                        -- keeps its own stored value below.
                        preserve = preserve or {}
                        preserve[fkey] = true
                    end
                    m[fkey] = nil
                end
            end
            for _, specID in ipairs(group.specs or {}) do
                local prev = entry.values[specID]
                local out = next(m) ~= nil and DeepCopy(m) or nil
                if preserve and prev then
                    for fkey in pairs(preserve) do
                        local pv = prev[fkey]
                        if pv ~= nil then
                            out = out or {}
                            out[fkey] = (type(pv) == "table") and DeepCopy(pv) or pv
                        end
                    end
                end
                entry.values[specID] = out
            end
        end
    end
    PruneRedundantValues()
end

-- Pairs every captured size key with its exact-size companion, run before an
-- apply or a default bank walks a store (cond = the conditional store). A size
-- key whose companion no entry records (an entry from before the companion
-- existed) adopts the live baseline exact size into its default map -- a store
-- write only on a profile that has one. Once a default holds a real exact size,
-- every override map holding its own legacy size gets NIL_SENT for the
-- companion, so that spec or condition draws its own size, not the baseline's.
-- Defined here, after the locals it reads.
function PxCo.Pair(store, cond)
    if not store then return end
    local CO = EllesmereUI._CondOv
    local changed = false
    for _, entry in ipairs(store) do
        local def = entry.values and entry.values.default
        if def then
            local adopt
            for fkey in pairs(def) do
                local p = PxCo.Partner(fkey)
                if p and def[p] == nil and FKeyLoaded(p) and not EntryOwning(p)
                   and not (CO and CO.EntryOwning and CO.EntryOwning(p)) then
                    local cur = ReadLive(p)
                    if cur ~= nil and type(cur) ~= "table" then
                        adopt = adopt or {}
                        adopt[p] = cur
                    end
                end
            end
            if adopt then
                for p, v in pairs(adopt) do def[p] = v end
                changed = true
            end
            for fkey in pairs(def) do
                local p = PxCo.Partner(fkey)
                local pv = p and def[p]
                if type(pv) == "string" and pv ~= NIL_SENT then
                    for k, m in pairs(entry.values) do
                        if k ~= "default" and type(m) == "table"
                           and m[fkey] ~= nil and m[p] == nil then
                            m[p] = NIL_SENT
                            changed = true
                        end
                    end
                end
            end
        end
    end
    if changed then
        if cond then CO.RebuildIndex() else RebuildFKeyIndex() end
        RequestGoldWalk()
    end
end

-- Raw writer: puts the given spec's stored values into the live profile
-- tables. Returns the set of folders whose values actually changed, or nil.
local function WriteSpecValues(specID)
    local store = GetStore()
    if not store or #store == 0 or not specID then return nil end
    PxCo.Pair(store)
    local touched = nil
    for _, entry in ipairs(store) do
        local m = entry.values[specID] or entry.values.default
        for fkey, def in pairs(entry.values.default) do
            -- Apply-side folder blacklist: legacy entries can carry paths into
            -- hands-off addons (CDM runs its own per-spec system; a stale write
            -- re-injects frozen spell data and its unmapped folder forces a full
            -- RefreshAllAddons mid-play). Match-owned keys: the match engine owns
            -- them while a link exists, so stored is a stale copy.
            if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey) then
                local v = m[fkey]
                if v == nil then v = def end
                if v == NIL_SENT then v = nil end
                -- Key-removal markers are honored ONLY for keys with no registered
                -- default: on defaults-backed keys the marker is harvest residue (see
                -- HasRegisteredDefault) and writing nil strips a key consumers read
                -- raw. Skip; live keeps the merged default and the next harvest self-heals.
                local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
                local cur = ReadLive(fkey)
                -- Table values are never written or compared: a stored table
                -- reference NEVER equals live -> phantom "write" plus a full
                -- module refresh on every apply.
                if not nilPoison and type(v) ~= "table" and type(cur) ~= "table" and cur ~= v then
                    if WriteLive(fkey, v) then
                        local folder = SplitFKey(fkey)
                        if folder then
                            touched = touched or {}
                            touched[folder] = true
                        end
                    end
                end
            end
        end
    end
    return touched
end

-- Group variant: seeds from the group's first member spec.
local function WriteGroupValues(group)
    local seed = group and group.specs and group.specs[1]
    if not seed then return nil end
    return WriteSpecValues(seed)
end

-- Default variant: writes the stored DEFAULT values (what specs outside any
-- group use). Powers the panel's Default Editing Mode view.
local function WriteDefaultValues()
    local store = GetStore()
    if not store or #store == 0 then return nil end
    local touched = nil
    for _, entry in ipairs(store) do
        for fkey, def in pairs(entry.values.default) do
            -- Same apply-side blacklist + match-ownership skip as WriteSpecValues.
            if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey) then
                local v = def
                if v == NIL_SENT then v = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues,
                -- plus its table guards: a stored table reference never
                -- equals live, so comparing/writing one registers a phantom
                -- change and forces a full module refresh on every apply.
                local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
                local cur = ReadLive(fkey)
                if not nilPoison and type(v) ~= "table" and type(cur) ~= "table" and cur ~= v then
                    if WriteLive(fkey, v) then
                        local folder = SplitFKey(fkey)
                        if folder then
                            touched = touched or {}
                            touched[folder] = true
                        end
                    end
                end
            end
        end
    end
    return touched
end

-- Banks live values into the entries' DEFAULT maps (Default Editing Mode
-- edits are edits to the shared baseline).
local function HarvestDefaults()
    local store = GetStore()
    -- A Default view edit to an exact size an entry does not record yet is a
    -- baseline edit: pair it first so it banks.
    PxCo.Pair(store)
    local maps = HarvestMap()
    if not maps then return end
    for i, entry in ipairs(store) do
        -- Match-owned size keys never bank FROM live: live holds whatever the
        -- match engine last wrote (it re-pulls and persists on every target
        -- resize, including the Default view's own value writes), never a user
        -- default edit. Keep the recorded default verbatim.
        local m = maps[i]
        local prev = entry.values.default
        for fkey in pairs(m) do
            if MatchOwnedFKey(fkey) then
                if prev ~= nil then m[fkey] = prev[fkey] else m[fkey] = nil end
            end
        end
        entry.values.default = m
    end
    PruneRedundantValues()
end

local function ApplyValuesFor(specID)
    SetInTransition(false)
    if specID then SetActiveSpec(specID) end
    -- While Editing-as (or the Default view) holds swapped values live, generic
    -- re-applies (e.g. a fallback RefreshAllAddons) must preserve the swap.
    if _editGroup then
        return WriteGroupValues(_editGroup)
    end
    if EllesmereUI._CondOv and EllesmereUI._CondOv._edit then
        -- Editing-as-conditional view: shared defaults with the session group's
        -- values overlaid (forSession: they show even over spec-owned fkeys).
        -- Falling through to WriteSpecValues repaints spec values into the open
        -- session and the exit bank records them as the conditional's edits.
        local touched = WriteDefaultValues()
        local t2 = EllesmereUI._CondOv.WriteValues(EllesmereUI._CondOv._edit.id, true)
        if t2 then
            touched = touched or {}
            for k in pairs(t2) do touched[k] = true end
        end
        return touched
    end
    if _defaultView then
        return WriteDefaultValues()
    end
    return WriteSpecValues(specID)
end

--- Values-only apply, called at the TOP of EllesmereUI.RefreshAllAddons so
--- every profile swap / import picks the current spec's overrides up through
--- the full refresh that follows. No refresh of its own.
function EllesmereUI.SpecOverrides_ApplyValues(specID)
    -- WoW Forever: re-resolve the spec the class acts as against the groups
    -- of the profile now active (a profile swap or import can move it).
    if EllesmereUI.IS_FOREVER then specID = CurrentSpecID() or specID end
    ApplyValuesFor(specID or _activeSpec or CurrentSpecID())
    -- Unlock layout overrides ride the same hook: stores must hold the current
    -- spec's effective layout before every module refresh that follows. Always
    -- keyed to the REAL spec -- editing-as swaps option values, never layout.
    if EllesmereUI.SpecOverrides_ApplyUnlock then
        EllesmereUI.SpecOverrides_ApplyUnlock(specID or _activeSpec or CurrentSpecID())
    end
    if EllesmereUI.SpecOverrides_ApplyBm then
        EllesmereUI.SpecOverrides_ApplyBm(specID or _activeSpec or CurrentSpecID())
    end
    if EllesmereUI.SpecOverrides_ApplyDm then
        EllesmereUI.SpecOverrides_ApplyDm(specID or _activeSpec or CurrentSpecID())
    end
    -- Conditional value overlay rides last (spec values always win their
    -- own fkeys; the two sets are disjoint by the ownership gate).
    if EllesmereUI._CondOv then EllesmereUI._CondOv.ApplyValues() end
    -- Close the import window (see ImportProfile): this is the first apply on a
    -- session OTHER than the importing one (its runtime flag died at the ReloadUI).
    -- Converge live to the imported store's layer truth exactly once: the exported
    -- blob carries whatever layer was LIVE on the exporter at export time
    -- (SnapshotAllAddons copies stores verbatim), and nothing on the normal login
    -- path re-applies the recipient spec's layer over it (import-tail ApplyLayer's
    -- flush died at the ReloadUI; the plain login apply early-outs on
    -- want == s.active). Forced apply resolves the spec's fork, else the exporter's
    -- true baselineLayout; FlushUnlock's equality guards no-op once blob and bucket
    -- agree, and its pend overlay keeps post-clear boundary banks intent-true until
    -- the flush lands. Clear-first so an apply error can never wedge the window shut.
    if not EllesmereUI._importGuardArmedNow then
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            -- Resolve the spec BEFORE closing the window: a spec-less apply must leave
            -- the flag set (bounded stuck-window, next apply retries) rather than burn
            -- the one-shot converge with nothing to converge to. pcall so a converge
            -- error can't abort the caller's module fan-out (RefreshAllAddons runs
            -- ApplyValues as its first statement).
            local sid = specID or _activeSpec or CurrentSpecID()
            if sid then
                prof._importEstablishPending = nil
                -- One converge serves both windows: the forced apply below
                -- also satisfies a pending reset-pointer converge.
                EllesmereUI._unlockResetConvergePending = nil
                if EllesmereUI.SpecOverrides_ApplyUnlock then
                    pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyBm then
                    pcall(EllesmereUI.SpecOverrides_ApplyBm, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyDm then
                    pcall(EllesmereUI.SpecOverrides_ApplyDm, sid, true)
                end
            end
        end
    end
    -- Reset-pointer converge (see SpecOverrides_UnlockResetActive): a profile
    -- activation restored baseline links and cleared a live layer pointer, but
    -- module elem positions still hold that layer's geometry. A baseline-spec
    -- login early-outs on want == active == nil, leaving the desync for the next
    -- harvest to bank into baselineLayout; one forced apply paints the pointer's
    -- truth instead. Same contract as the import converge (spec resolved before
    -- clearing, clear-first, pcall'd). No ApplyBm -- the BM pointer is never
    -- reset, so it is never lied about.
    if EllesmereUI._unlockResetConvergePending then
        local sid = specID or _activeSpec or CurrentSpecID()
        if sid then
            EllesmereUI._unlockResetConvergePending = nil
            if EllesmereUI.SpecOverrides_ApplyUnlock then
                pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
            end
        end
    end
end

--- Full apply: values + targeted refresh of the touched addons.
--- deferLogin: first-login call -- waits two frames so child addon OnEnable and
--- deferred registrations complete first (mirrors the profile switcher).
function EllesmereUI.SpecOverrides_Apply(specID, deferLogin)
    if deferLogin then
        C_Timer.After(0, function()
            C_Timer.After(0, function() EllesmereUI.SpecOverrides_Apply(specID) end)
        end)
        return
    end
    -- WoW Forever: every caller means "the current spec"; the client's own
    -- spec ID never keys a group, so resolve the spec the class acts as.
    if specID and EllesmereUI.IS_FOREVER then specID = CurrentSpecID() or specID end
    local touched = ApplyValuesFor(specID)
    if touched then RunRefreshers(touched) end
    -- Unlock layout overrides: a same-profile spec change never runs RefreshAllAddons,
    -- so this is its only unlock apply; on the profile-switch path ApplyValues already
    -- ran it and this repeat is a value-equal no-op.
    if EllesmereUI.SpecOverrides_ApplyUnlock then
        EllesmereUI.SpecOverrides_ApplyUnlock(specID)
    end
    if EllesmereUI.SpecOverrides_ApplyBm then
        EllesmereUI.SpecOverrides_ApplyBm(specID)
    end
    if EllesmereUI.SpecOverrides_ApplyDm then
        EllesmereUI.SpecOverrides_ApplyDm(specID)
    end
    if UpdateIndicator then UpdateIndicator() end   -- passive owner may change
    -- Spec changed with the cards popup open: rebuild so each group's unlock
    -- icon reflects the new spec's membership (the click handler re-checks
    -- membership regardless).
    if RefreshCardsPopup then RefreshCardsPopup() end
    -- Spec changed with the panel open: return it to the Default view.
    if PanelShown and PanelShown() and not _editGroup and not _defaultView
       and EnterDefaultView then
        EnterDefaultView()
    end
    -- Conditional overrides re-arm after every spec transition: the engine
    -- bails while the value system is mid-swap; this is its retry point.
    if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
    -- Import-window close + one-shot layer converge; contract identical to the
    -- copy in SpecOverrides_ApplyValues above.
    if not EllesmereUI._importGuardArmedNow then
        local prof = GetProfileRoot()
        if prof and prof._importEstablishPending then
            local sid = specID or _activeSpec or CurrentSpecID()
            if sid then
                prof._importEstablishPending = nil
                -- One converge serves both windows: the forced apply below
                -- also satisfies a pending reset-pointer converge.
                EllesmereUI._unlockResetConvergePending = nil
                if EllesmereUI.SpecOverrides_ApplyUnlock then
                    pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyBm then
                    pcall(EllesmereUI.SpecOverrides_ApplyBm, sid, true)
                end
                if EllesmereUI.SpecOverrides_ApplyDm then
                    pcall(EllesmereUI.SpecOverrides_ApplyDm, sid, true)
                end
            end
        end
    end
    -- Reset-pointer converge; same contract as the copy above.
    if EllesmereUI._unlockResetConvergePending then
        local sid = specID or _activeSpec or CurrentSpecID()
        if sid then
            EllesmereUI._unlockResetConvergePending = nil
            if EllesmereUI.SpecOverrides_ApplyUnlock then
                pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
            end
        end
    end
end

--- Spec transition entry point, called by the profile system's spec handler
--- BEFORE any spec-profile switch.
function EllesmereUI.SpecOverrides_OnSpecChanged(oldSpecID, newSpecID)
    -- WoW Forever: the outgoing spec is the one whose values are live, the
    -- incoming one the spec the class acts as.
    if EllesmereUI.IS_FOREVER then
        if oldSpecID then oldSpecID = _activeSpec end
        if newSpecID then newSpecID = CurrentSpecID() or newSpecID end
    end
    -- Unlock layout: bank live into the outgoing layer FIRST, while live still
    -- belongs to the old state (the new spec's values/refreshers have not run
    -- yet). The per-spec layer apply rides ApplyUnlock later.
    if EllesmereUI.SpecOverrides_HarvestUnlockLayout then
        EllesmereUI.SpecOverrides_HarvestUnlockLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestBmLayout then
        EllesmereUI.SpecOverrides_HarvestBmLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestDmLayout then
        EllesmereUI.SpecOverrides_HarvestDmLayout()
    end
    -- An editing-as-conditional session banks and ends here; the transition
    -- re-establishes canonical live itself (noRestore).
    if EllesmereUI._CondOv and EllesmereUI._CondOv.ExitEdit then
        EllesmereUI._CondOv.ExitEdit(true)
    end
    if _editGroup then
        -- Bank unsaved Editing-as changes (plus a sweep of uncaptured writes)
        -- to the group's members. Live holds group values, so the outgoing
        -- spec must NOT be harvested from it.
        local g = _editGroup
        SetEditGroup(nil)
        if SweepUncaptured then SweepUncaptured(g) end
        HarvestGroup(g)
        if TeardownEditSession then TeardownEditSession() end
    elseif _defaultView then
        -- Live holds the DEFAULT values; bank them there. The outgoing spec's
        -- own values were banked when the view was entered.
        SetDefaultView(false)
        HarvestDefaults()
        if UpdateIndicator then UpdateIndicator() end
    elseif oldSpecID and oldSpecID ~= newSpecID then
        Harvest(oldSpecID)
    end
    SetActiveSpec(newSpecID)
    SetInTransition(true)
end

-- WoW Forever: creating or deleting a group can move the spec the class acts
-- as (CurrentSpecID) while _activeSpec still names the spec whose values are
-- live. Runs the transition a spec change runs, once: OnSpecChanged banks
-- what is live (the unlock, Buff Manager and Debuff Manager layers, then the
-- Default view or the outgoing spec), then the new spec applies. Stands down
-- while an editing session holds its own values live (its exit converges)
-- and while a spec transition is mid-flight (its apply resolves the new
-- spec). Retail never calls this.
function EllesmereUI._SO_ForeverConverge()
    local r = CurrentSpecID()
    if not r or r == _activeSpec or _inTransition then return end
    if _editGroup or (EllesmereUI._CondOv and EllesmereUI._CondOv._edit) then return end
    EllesmereUI.SpecOverrides_OnSpecChanged(_activeSpec, r)
    EllesmereUI.SpecOverrides_Apply(r)
end

--- Harvest the live values of the spec currently in the live db. Called on
--- logout and before manual profile switches/imports/exports so normal
--- options-page edits are never lost. An active Editing-as session is banked
--- to its group and ended, and canonical live data restored (the caller is
--- about to snapshot or switch).
function EllesmereUI.SpecOverrides_HarvestCurrent()
    if _inTransition then return end
    -- Unlock layout: bank live into its current layer (callers are about to
    -- snapshot or swap stores).
    if EllesmereUI.SpecOverrides_HarvestUnlockLayout then
        EllesmereUI.SpecOverrides_HarvestUnlockLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestBmLayout then
        EllesmereUI.SpecOverrides_HarvestBmLayout()
    end
    if EllesmereUI.SpecOverrides_HarvestDmLayout then
        EllesmereUI.SpecOverrides_HarvestDmLayout()
    end
    -- An editing-as-conditional session: bank it and end it. ExitEdit restores
    -- canonical live, but with the panel shown its tail re-enters the Default view,
    -- which banks the real spec's values and swaps the DEFAULTS live -- harvesting the
    -- spec from that state diff-clears its entire map (every value equals its default).
    -- Fall through to the _defaultView branch below. noRecheck: shared banking plumbing
    -- (logout, export, profile switch), never "the user finished editing". A
    -- conditional transition resolved here would run ApplyUnlock, whose flush is two
    -- frames out -- at LOGOUT it never lands, leaving the advanced active pointer to
    -- early-out the next login's apply with module position stores still on the OLD
    -- layer. Values still bank (Cond.HarvestEdit inside); only the flip waits.
    if EllesmereUI._CondOv and EllesmereUI._CondOv._edit then
        EllesmereUI._CondOv.ExitEdit(nil, true)
        if not _defaultView then
            -- WoW Forever banks only a spec an apply made live.
            Harvest(_activeSpec or ((not EllesmereUI.IS_FOREVER) and CurrentSpecID() or nil))
            return
        end
    end
    -- Conditional values bank ONLY over canonical live data: in the session
    -- branches below this runs AFTER WriteSpecValues restores the real values.
    -- Banking while a session's swapped values sit live rebanks view-state
    -- values into the cond defaults (default poisoning).
    local function BankCond()
        if EllesmereUI._CondOv then
            EllesmereUI._CondOv.Harvest(EllesmereUI.Conditions_AppliedGid
                and EllesmereUI.Conditions_AppliedGid() or nil)
        end
    end
    if _editGroup then
        local g = _editGroup
        SetEditGroup(nil)
        if SweepUncaptured then SweepUncaptured(g) end
        HarvestGroup(g)
        if TeardownEditSession then TeardownEditSession() end
        local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
        if touched then RunRefreshers(touched) end
        BankCond()
        return
    end
    if _defaultView then
        -- Bank default-view edits, then restore the real spec's values so the
        -- caller (export/switch/logout) sees canonical live data.
        SetDefaultView(false)
        HarvestDefaults()
        if UpdateIndicator then UpdateIndicator() end
        local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
        if touched then RunRefreshers(touched) end
        BankCond()
        return
    end
    BankCond()
    -- WoW Forever banks only a spec an apply made live: before the first
    -- apply no resolved spec owns the live values.
    Harvest(_activeSpec or ((not EllesmereUI.IS_FOREVER) and CurrentSpecID() or nil))
end

-------------------------------------------------------------------------------
--  Unlock Layout Overrides
--  Per-GROUP overrides for unlock-mode layout aspects: element position (pos),
--  anchor link (anchor), grow direction (grow), width match (wm), height match (hm).
--  Stored OUTSIDE the fkey entries system: anchors and matches live in GLOBAL
--  EllesmereUIDB tables the Lite registry can't address, and unlock values bank
--  one-per-group, not one-per-spec.
--
--  Legacy per-aspect shape (still reachable from old import strings):
--    profile.specUnlockOverrides = {
--        groups   = { [groupId] = { [elementKey] = {
--                        pos    = saved-position entry (incl. tgt* follow
--                                 baselines for CDM/AB grow bars) | NIL_SENT,
--                        anchor = { target, side, offsetX, offsetY } | NIL_SENT,
--                        grow   = direction string | NIL_SENT,
--                        wm     = targetKey | NIL_SENT,
--                        hm     = targetKey | NIL_SENT } } },
--        baseline = { [elementKey] = same aspect shapes },
--        applied  = { [elementKey] = groupId },
--    }
--  baseline shadows the SHARED value of every overridden aspect and is the restore
--  source for a non-member spec / a removed override. applied is PERSISTED: after a
--  /reload the live globals still hold the previous spec's override values, so the
--  map lets the next apply restore exactly the overlaid elements -- never the whole
--  baseline bucket, which would clobber live drift (anchor-offset upkeep) on every
--  RefreshAllAddons. The CURRENT shape is the layer model: see GetUnlockStore.
-------------------------------------------------------------------------------

EllesmereUI.SPECOV_NIL = NIL_SENT
EllesmereUI._SPECOV_GOLD = { GOLD_R, GOLD_G, GOLD_B }

local function GetUnlockStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.specUnlockOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.specUnlockOverrides = s
    end
    -- Layer model: layouts[gid] = a COMPLETE unlock-layout fork for that group;
    -- baselineLayout = the shared layout, stored whenever a group layer is
    -- live; active = which layer the LIVE stores currently hold (nil =
    -- baseline).
    s.layouts = s.layouts or {}
    return s
end

--- True when any override entry -- spec or conditional -- holds this setting
--- (a module folder plus its path segments from the module's profile root),
--- or a table above it. A caller that writes settings outside a tracked
--- widget (the Style page's per-style slots and first-visit defaults) leaves
--- such a setting alone, so the override keeps winning (an applied
--- conditional's value would otherwise be banked over at logout). Read-only.
function EllesmereUI.SpecOverrides_IsCaptured(folder, ...)
    local fkey = folder .. FS .. table.concat({ ... }, PS)
    local C = EllesmereUI._CondOv
    for pass = 1, 2 do
        local store
        if pass == 1 then store = GetStore()
        elseif C and C.GetStore then store = C.GetStore() end
        if store then
            for _, e in ipairs(store) do
                local vals = e.values
                if type(vals) == "table" then
                    for _, map in pairs(vals) do
                        if type(map) == "table" then
                            for k in pairs(map) do
                                if k == fkey or (#k < #fkey and fkey:sub(1, #k + 1) == k .. PS) then return true end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

--- Which overrides hold any of these settings: keys are top-level keys of
--- the module's profile root (no table sits above one, so IsCaptured's match
--- is the key itself). An array of { kind = "spec", id = specID } and
--- { kind = "cond", id = condition group id }, each once; empty when none
--- does. One pass over both stores. Read-only, for options pages that tell
--- apart where an override applies.
function EllesmereUI.SpecOverrides_CapturedBy(folder, keys)
    local want = {}
    for i = 1, #keys do want[folder .. FS .. keys[i]] = true end
    local C = EllesmereUI._CondOv
    local out, seen = {}, { spec = {}, cond = {} }
    for pass = 1, 2 do
        local store, kind
        if pass == 1 then store, kind = GetStore(), "spec"
        elseif C and C.GetStore then store, kind = C.GetStore(), "cond" end
        if store then
            local seenKind = seen[kind]
            for _, e in ipairs(store) do
                local vals = e.values
                if type(vals) == "table" then
                    for id, map in pairs(vals) do
                        if type(id) == "number" and type(map) == "table" and not seenKind[id] then
                            for k in pairs(map) do
                                if want[k] then
                                    seenKind[id] = true
                                    out[#out + 1] = { kind = kind, id = id }
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

function EllesmereUI.SpecOverrides_GroupById(gid)
    return GroupById(gid)
end

--- READ-ONLY view-state probe: true ONLY while the panel's Default Editing
--- Mode swap is live. Editing-as sessions (spec group or conditional)
--- deliberately preview their OWN swapped values, so the RF effective overlay
--- must stay OFF there ("click an override" keeps previewing that override).
--- Only the Default view needs panel-closed effective resolution.
--- (_CondOv, not the Cond local: Cond is declared in EUI_SpecOverrides_Conditional.lua.)
function EllesmereUI.SpecOverrides_ViewActive()
    if _editGroup then return false end
    local C = EllesmereUI._CondOv
    if C and C._edit then return false end
    return _defaultView and true or false
end

--- READ-ONLY: the CUSTOM unlock-layer fork of the override session being edited
--- (editing-as group or conditional); nil when no session is open or the
--- session's group has no custom unlock mode. Second return is the shared
--- baselineLayout for per-element fallback. Lets the RF real preview mirror the
--- session's unlock positions (recorded layer elems; anchored containers use
--- their recorded bookkeeping coordinates).
function EllesmereUI.SpecOverrides_EditSessionUnlockLayer()
    local s = GetUnlockStore()
    if _editGroup then
        local layer = s and s.layouts and s.layouts[_editGroup.id]
        if layer then return layer, s.baselineLayout end
        return nil
    end
    local C = EllesmereUI._CondOv
    local e = C and C._edit
    if e and e.id then
        local cs = C.GetUnlockStore and C.GetUnlockStore()
        local layer = cs and cs.layouts and cs.layouts[e.id]
        if layer then return layer, s and s.baselineLayout or nil end
    end
    return nil
end

--- READ-ONLY: display name of the override session being edited (editing-as
--- group or conditional), nil when none. Drives the preview chrome while a
--- session's own values are on screen.
function EllesmereUI.SpecOverrides_EditSessionName()
    if _editGroup then return _editGroup.name or _editGroup.label end
    local C = EllesmereUI._CondOv
    local e = C and C._edit
    if e and e.id and EllesmereUI.Conditions_GroupById then
        local cg = EllesmereUI.Conditions_GroupById(e.id)
        return cg and (cg.name or cg.label)
    end
    return nil
end

--- READ-ONLY: the override session being edited as kind ("spec" | "cond")
--- plus its group id, nil when none (EditSessionName's source).
function EllesmereUI.SpecOverrides_EditSessionInfo()
    if _editGroup then return "spec", _editGroup.id end
    local C = EllesmereUI._CondOv
    local e = C and C._edit
    if e and e.id then return "cond", e.id end
    return nil
end

--- READ-ONLY owning group for a spec's VALUES: first group in creation order
--- containing the spec. Unlock-layout ownership (OwnerGid) is a different,
--- layout-carrying rule -- never use it for values.
function EllesmereUI.SpecOverrides_OwningGroupFor(specID)
    if not specID then return nil end
    for _, g in ipairs(GetGroups() or {}) do
        for _, sid in ipairs(g.specs or {}) do
            if sid == specID then return g end
        end
    end
    return nil
end

--- READ-ONLY effective-value resolver for ONE folder: what the value system
--- WOULD hold live for the current REAL spec with the panel closed. Mirrors
--- WriteSpecValues' ladder (values[spec] or default per fkey, blacklist/
--- match-owned skipped, table values never resolved) with Cond.WriteValues'
--- RUNTIME overlay on top (the applied conditional's values for fkeys the spec
--- store does not own -- spec always wins). NIL_SENT stays ENCODED in the
--- returned map (decode against EllesmereUI.SPECOV_NIL); like the writers it is
--- decoded conceptually BEFORE the table-type skip, so sentinel deletions
--- always resolve. Returns (flatMap fkey->value or nil, specSrc, condSrc).
--- ZERO writes, no store creation, safe from any module at any time.
function EllesmereUI.SpecOverrides_PeekEffectiveValues(folder)
    if not folder then return nil end
    local specID = CurrentSpecID()
    local out, specSrc, condSrc
    local store = GetStore()
    if store and specID then
        for _, entry in ipairs(store) do
            local m = entry.values[specID] or entry.values.default
            for fkey, def in pairs(entry.values.default) do
                if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
                   and SplitFKey(fkey) == folder then
                    local v = m[fkey]
                    if v == nil then v = def end
                    if v == NIL_SENT or type(v) ~= "table" then
                        out = out or {}
                        out[fkey] = v
                        if not specSrc and m ~= entry.values.default
                           and m[fkey] ~= nil then
                            local g = EllesmereUI.SpecOverrides_OwningGroupFor(specID)
                            specSrc = (g and (g.name or g.label))
                                or L("Spec Override")
                        end
                    end
                end
            end
        end
    end
    local C = EllesmereUI._CondOv
    if C and C.GetStore then
        local cstore = C.GetStore()
        if cstore and #cstore > 0 then
            local gid = EllesmereUI.Conditions_AppliedGid
                and EllesmereUI.Conditions_AppliedGid() or nil
            for _, entry in ipairs(cstore) do
                local map = gid and entry.values[gid] or nil
                for fkey, def in pairs(entry.values.default) do
                    if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
                       and not EntryOwning(fkey) and SplitFKey(fkey) == folder then
                        local v = def
                        local fromCond = false
                        if map and map[fkey] ~= nil then
                            v = map[fkey]
                            fromCond = true
                        end
                        if v == NIL_SENT or type(v) ~= "table" then
                            out = out or {}
                            out[fkey] = v
                            if fromCond and not condSrc then
                                local cg = EllesmereUI.Conditions_GroupById
                                    and EllesmereUI.Conditions_GroupById(gid)
                                condSrc = cg and (cg.name or cg.label)
                            end
                        end
                    end
                end
            end
        end
    end
    return out, specSrc, condSrc
end

--- Active layer gid; nil = the baseline layout is live.
function EllesmereUI.SpecOverrides_UnlockActive()
    local s = GetUnlockStore()
    return s and s.active or nil
end

--- Deterministic owner layer for a spec: the FIRST group in creation order that
--- contains specID and HAS a layout. Specs in no such group use the baseline.
local function OwnerGid(specID)
    if not specID then return nil end
    local s = GetUnlockStore()
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

--- READ-ONLY: the RESOLVED effective unlock-layer fork for the current REAL
--- spec -- the owner group's fork, else the applied conditional's fork, else
--- nil (baseline effective: live positioning is already correct). Mirrors
--- SpecOverrides_ApplyUnlock's want resolution WITHOUT reading s.active: the
--- live pointer lags membership and panel-open unlock-mode edits, and the RF
--- real preview must show the layer that WOULD apply at the next boundary.
--- Second return is baselineLayout for per-element fallback.
function EllesmereUI.SpecOverrides_EffectiveUnlockLayer()
    local s = GetUnlockStore()
    if not s then return nil end
    local specID = CurrentSpecID()
    if not specID then return nil end
    local want = OwnerGid(specID)
    if want and s.layouts and s.layouts[want] then
        return s.layouts[want], s.baselineLayout
    end
    local C = EllesmereUI._CondOv
    local cond = C and C.ResolveGid and C.ResolveGid() or nil
    if cond then
        local cs = C.GetUnlockStore and C.GetUnlockStore()
        local layer = cs and cs.layouts and cs.layouts[cond]
        if layer then return layer, s.baselineLayout end
    end
    return nil
end

I.ApplyValuesFor, I.GetUnlockStore = ApplyValuesFor, GetUnlockStore
I.HarvestDefaults, I.HarvestGroup, I.OwnerGid = HarvestDefaults, HarvestGroup, OwnerGid
I.PruneRedundantValues, I.WriteDefaultValues = PruneRedundantValues, WriteDefaultValues
I.WriteGroupValues, I.WriteSpecValues = WriteGroupValues, WriteSpecValues
I.broken = false
