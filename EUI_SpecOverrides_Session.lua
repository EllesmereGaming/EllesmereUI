if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_Session.lua
--
--  The auto-capture watcher, notified writes, the exit sweep and the
--  Editing-as sessions (spec group, Default view, conditional).
--  Reads the earlier Spec Overrides files through EUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
local I = EUI_NS._soInternals
-- EllesmereUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local BlacklistedFKey, CurrentSpecID, DBFor = I.BlacklistedFKey, I.CurrentSpecID, I.DBFor
local EDIT_B, EDIT_G, EDIT_R, EntryOwning = I.EDIT_B, I.EDIT_G, I.EDIT_R, I.EntryOwning
local FKeyLoaded, FOLDER_BLACKLIST, GetGroups = I.FKeyLoaded, I.FOLDER_BLACKLIST, I.GetGroups
local GetStore, HasRegisteredDefault, L = I.GetStore, I.HasRegisteredDefault, I.L
local LayerOwnedFKey, MatchOwnedFKey, NIL_SENT = I.LayerOwnedFKey, I.MatchOwnedFKey, I.NIL_SENT
local NumAllowedFKey, PS, PxCo, ReadLive = I.NumAllowedFKey, I.PS, I.PxCo, I.ReadLive
local RebuildFKeyIndex, RunRefreshers, SegKey = I.RebuildFKeyIndex, I.RunRefreshers, I.SegKey
local SnapValue, SplitFKey, WriteLive = I.SnapValue, I.SplitFKey, I.WriteLive
local HarvestDefaults, HarvestGroup = I.HarvestDefaults, I.HarvestGroup
local WriteDefaultValues, WriteGroupValues = I.WriteDefaultValues, I.WriteGroupValues
local WriteSpecValues, Cond, CurrentContext = I.WriteSpecValues, I.Cond, I.CurrentContext
local DiffProfiles, IsExcludedContext = I.DiffProfiles, I.IsExcludedContext
local RequestGoldWalk, SnapshotProfiles = I.RequestGoldWalk, I.SnapshotProfiles
local UpdateEditLocks, SetEditGroup = I.UpdateEditLocks, I.SetEditGroup
local SetDefaultView, SetEnterSnap = I.SetDefaultView, I.SetEnterSnap
local SetWatchResync, SetExitGroupEdit = I.SetWatchResync, I.SetExitGroupEdit
local SetSweepUncaptured = I.SetSweepUncaptured
local SetTeardownEditSession, SetPanelShown = I.SetTeardownEditSession, I.SetPanelShown
local SetEnterDefaultView = I.SetEnterDefaultView

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _editGroup = nil
I.editGroupSetters[#I.editGroupSetters + 1] = function(v) _editGroup = v end
local _defaultView = false
I.defaultViewSetters[#I.defaultViewSetters + 1] = function(v) _defaultView = v end
local _enterSnap = nil
I.enterSnapSetters[#I.enterSnapSetters + 1] = function(v) _enterSnap = v end
local _inTransition = false
I.inTransitionSetters[#I.inTransitionSetters + 1] = function(v) _inTransition = v end
local _activeSpec = nil
I.activeSpecSetters[#I.activeSpecSetters + 1] = function(v) _activeSpec = v end
local UpdateIndicator
I.updateIndicatorSetters[#I.updateIndicatorSetters + 1] = function(v) UpdateIndicator = v end

-- Forward declarations (assigned further down in this file)
local SweepUncaptured, EnsurePanelHideHook, SetEditStatus, ShowEditBanner
local HideEditBanner, ApplyEditOverlay, TeardownEditSession, PanelShown
local EnterDefaultView, ExitDefaultView, ExitGroupEdit, EnterGroupEdit
local _unlockRoundtrip = nil -- session to restore after an options-entered
                             -- unlock roundtrip: { kind = "spec"|"cond", id = groupId }

-------------------------------------------------------------------------------
--  Auto-capture watcher (runs while Editing-as is active)
-------------------------------------------------------------------------------
local _watchSnap = nil
local _watchTicker = nil
-- The slot the last edit is attributed to, as a SNAPSHOT of its region (the
-- slot's capture config, its section and its overridden tip) taken when the
-- slot was sampled or notified: a page rebuild that dresses that region for
-- another slot (the options page pool) can never re-point it. snap: the last
-- snapshot or nil; time: when it was taken; sample: the reused table the
-- mouse-focus sampler fills; Snap(region, into): fills a snapshot.
-- pend: the one snapshot the factory hands a write before its setter runs
-- (_SOAttribution) while it waits for the next frame's attribution, busy while
-- it does; held: where the attribution keeps the snapshot that won it.
local _lastAttr = { snap = nil, time = 0, sample = { _soSnap = true }, pend = { _soSnap = true },
    held = { _soSnap = true }, busy = false }
function _lastAttr.Snap(region, into)
    into.cfg = region._captureCfg
    local row = region._isOptionRow and region or region:GetParent()
    local hdr = row and row._sectionHeader
    into.section = hdr and hdr._sectionName or nil
    into.tip = region._specOvTip
    return into
end
local _watchResync = false   -- absorb the next tick's diff (page rebuild seeds)
I.watchResyncSetters[#I.watchResyncSetters + 1] = function(v) _watchResync = v end
local _sessionIgnored = {}   -- fkeys written on excluded pages this session
                             -- (never captured, and skipped by the exit sweep)

local function PrettyKey(fkey)
    local _, path = SplitFKey(fkey)
    local last = (path and path:match("([^\30]+)$")) or tostring(fkey)
    last = last:gsub("(%l)(%u)", "%1 %2")
    return (last:gsub("^%l", string.upper))
end

-- Tracks which options slot the user is interacting with. Popups (dropdown
-- menus, cog popups, color picker) keep the previous slot attribution;
-- anything outside the options UI clears it.
local function SampleAttribution()
    local foci = GetMouseFoci and GetMouseFoci()
    local f = foci and foci[1]
    if not f or f == WorldFrame then return end
    local inPanel, popup, region = false, false, nil
    local n = f
    while n do
        if n._captureCfg then region = n end
        if n._euiOptionsPopup or n == EllesmereUI._colorPickerPopup then popup = true end
        if n == _G.EllesmereUIFrame then inPanel = true end
        n = n:GetParent()
    end
    if region then
        _lastAttr.snap, _lastAttr.time = _lastAttr.Snap(region, _lastAttr.sample), GetTime()
    elseif popup then
        -- keep the previous attribution (edits flow through the popup)
        _lastAttr.time = GetTime()
    elseif not inPanel then
        _lastAttr.snap = nil   -- interacting with the world / other UI
    end
end

-- An override entry's crumb from its fields, each localized: module title, element,
-- the page's tab label, section; nil while the module is not registered. The list
-- rebuilds it live (BuildListRow); capture stores it for when the module is missing.
local function BuildEntryCrumb(module, element, page, section)
    local modTitle = module and EllesmereUI:GetModuleTitle(module)
    if not modTitle then return nil end
    local parts = { L(modTitle) }
    if element then parts[#parts + 1] = L(element) end
    if page then parts[#parts + 1] = L(EUI_NS.GetTabLabel(module, page)) end
    if section then parts[#parts + 1] = L(section) end
    return table.concat(parts, "  >  ")
end

local function AutoCapture(changes)
    -- Hidden search prebuild: selector setters and lazy page seeding write
    -- db.profile from a pass the user never sees -- never capture them.
    if EllesmereUI._prebuilding then return end
    -- Attribution required: without a known slot, absorb silently (background
    -- bookkeeping like drag positions must never become overrides). The 3-second
    -- window bounds this mouse-focus FALLBACK (the notified-write path attributes
    -- exactly); longer lets unrelated background writes (match propagation,
    -- combat-end refreshers) land under the last slot touched.
    local snap = _lastAttr.snap
    if not (snap and snap.cfg and (GetTime() - _lastAttr.time) < 3) then
        return
    end
    -- Excluded contexts (whole modules, pages, or single sections) never factor into
    -- spec overrides: absorb, and shield these paths from the exit sweep. Section is
    -- derived up front so section-scoped (nested-table) entries apply.
    local section = snap.section
    if IsExcludedContext(section) then
        for _, c in ipairs(changes) do
            _sessionIgnored[c.fkey] = true
        end
        return
    end
    local store = GetStore(true)
    if not store then return end

    -- Validate + collect
    local paths, skippedNum, skippedBlack, layerOwned = {}, false, nil, nil
    for _, c in ipairs(changes) do
        -- Blacklist before the numeric guard: an array-shaped blacklisted key
        -- (bm2 indicator sets) reported as a list-position problem reads as
        -- "buff sizes can never be overridden", which is not what happened.
        local layer = LayerOwnedFKey(c.fkey)
        if layer then
            layerOwned = layer
        elseif BlacklistedFKey(c.fkey) then
            skippedBlack = c.folder
        elseif c.num and not NumAllowedFKey(c.fkey) then
            skippedNum = true
        elseif MatchOwnedFKey(c.fkey) then
            -- Match-owned size keys are the match engine's territory: apply
            -- skips them and every bank preserves, so capturing one only
            -- creates a dead slot the harvests must tiptoe around.
            _sessionIgnored[c.fkey] = true
        else
            paths[#paths + 1] = c.fkey
        end
    end
    if #paths == 0 then
        if layerOwned then
            local state, text
            if layerOwned == "bm" then
                state = EllesmereUI.SpecOverrides_BmOverlayState()
                text = L("Buff Manager changes on this page apply only to this override.")
            else
                state = EllesmereUI.SpecOverrides_DmOverlayState()
                text = L("Debuff Manager changes on this page apply only to this override.")
            end
            -- No overlay = the fork IS live, so the edit landed in it. An overlay
            -- means the page was blocked and the write came from elsewhere.
            if not state then SetEditStatus(text, 1, 1, 0.6) end
        elseif skippedBlack then
            if skippedBlack == "EllesmereUICooldownManager" then
                SetEditStatus(L("Cooldown Manager has its own per-spec system and can't be overridden here."), 1, 0.55, 0.35)
            elseif FOLDER_BLACKLIST[skippedBlack] then
                SetEditStatus(L("This module is excluded from Spec Overrides."), 1, 0.55, 0.35)
            else
                -- Setting-level exclusion (SETTING_BLACKLIST hit).
                SetEditStatus(L("This setting can't be overridden."), 1, 0.55, 0.35)
            end
        elseif skippedNum then
            SetEditStatus(L("That setting is stored by list position and can't be safely overridden."), 1, 0.55, 0.35)
        end
        return
    end
    if #paths > 12 then return end   -- burst; not a slot edit

    local cfg = snap.cfg
    local slotLabel = tostring(cfg.text or "?")
    local module = EllesmereUI:GetActiveModule()
    local page = EllesmereUI:GetActivePage()
    local element = CurrentContext()

    -- Session routing: a conditional session banks into the CONDITIONAL store
    -- (own fkey index, group id space, per-GROUP value maps instead of
    -- per-spec). Everything else is identical.
    local condSession = Cond._edit
    local sStore = condSession and Cond.GetStore(true) or store
    local entry
    for _, e in ipairs(sStore or {}) do
        if e.slotLabel == slotLabel and e.module == module
           and (e.element or "") == (element or "")
           and (e.page or "") == (page or "")
           and (e.section or "") == (section or "") then
            entry = e
            break
        end
    end
    local isNew = false
    if not entry then
        isNew = true
        entry = {
            label = slotLabel,
            slotLabel = slotLabel,
            crumb = BuildEntryCrumb(module, element, page, section),
            module = module, page = page,
            element = element, section = section,
            group = condSession and condSession.id or (_editGroup and _editGroup.id or nil),
            values = { default = {} },
        }
        sStore[#sStore + 1] = entry
    end

    -- Record originals (pre-change snapshot values) as the shared default; conditional
    -- sessions also seed the group's map. Live values bank at session exit. The REAL
    -- spec's map is deliberately NOT seeded: the per-key default fallback in
    -- WriteSpecValues already restores the bystander spec at exit, and a stored copy
    -- would pin it at this old default forever once the default is later edited
    -- (permanent phantom override on an unassigned spec).
    for _, fkey in ipairs(paths) do
        if entry.values.default[fkey] == nil then
            local orig = SnapValue(_watchSnap, fkey)
            -- Spec-session capture of a cond-owned fkey: the snapshot may hold an
            -- APPLIED conditional's overlay value, not the shared baseline. Seed from
            -- the cond store's recorded default instead. (Inert in a cond session:
            -- captured fkeys there are never cond-owned.)
            local ce = Cond.EntryOwning(fkey)
            if ce then
                orig = ce.values.default[fkey]
                if orig == NIL_SENT then orig = nil end
            end
            if type(orig) == "table" then orig = nil end
            entry.values.default[fkey] = (orig == nil) and NIL_SENT or orig
            if condSession then
                local gm = entry.values[condSession.id]
                if not gm then gm = {}; entry.values[condSession.id] = gm end
                gm[fkey] = entry.values.default[fkey]
            end
        end
    end
    -- A border size key brings its exact-size companion along (see PxCo): a write
    -- of the legacy size alone must still own "<key>Px" from now on, unless
    -- another entry of this store already owns it. Seeded as the main loop seeds.
    for _, fkey in ipairs(paths) do
        local partner = PxCo.Partner(fkey)
        local other = partner and (condSession and Cond.EntryOwning(partner) or EntryOwning(partner))
        if partner and entry.values.default[partner] == nil and not (other and other ~= entry) then
            local orig = SnapValue(_watchSnap, partner)
            local ce = Cond.EntryOwning(partner)
            if ce then
                orig = ce.values.default[partner]
                if orig == NIL_SENT then orig = nil end
            end
            if type(orig) == "table" then orig = nil end
            entry.values.default[partner] = (orig == nil) and NIL_SENT or orig
            if condSession then
                local gm = entry.values[condSession.id]
                if not gm then gm = {}; entry.values[condSession.id] = gm end
                gm[partner] = entry.values.default[partner]
            end
        end
    end

    if condSession then Cond.RebuildIndex() else RebuildFKeyIndex() end
    RequestGoldWalk()
    if isNew then
        local sessName = condSession and condSession.name or (_editGroup and _editGroup.name) or "?"
        SetEditStatus(string.format(L("'%s' is now customized for %s."), slotLabel, sessName), 0.35, 1, 0.35)
    end
end

-- The table an fkey's leaf lives in, plus that leaf's key, or nil when the path does
-- not resolve (module not loaded, array entry deleted). Same walk ReadLive does.
local function OwnerOf(fkey)
    local folder, path = SplitFKey(fkey)
    local t = folder and DBFor(folder)
    if type(t) ~= "table" or not path then return nil end
    local segs = { strsplit(PS, path) }
    for i = 1, #segs - 1 do
        t = t[SegKey(t, segs[i])]
        if type(t) ~= "table" then return nil end
    end
    return t, SegKey(t, segs[#segs])
end

-- do ... end: the helper below is released at `end` instead of taking a
-- top-level slot. The global it wires up stays, as always.
do
-- Does any entry in `sStore` hold a VALUE (not just a recorded default) for `key` of
-- `store`? Attribution by table identity, the same rule ClearStoreKey uses.
local function StoreHoldsKey(sStore, store, key)
    for _, e in ipairs(sStore or {}) do
        local def = e.values and e.values.default
        if def then
            for fkey in pairs(def) do
                local owner, leaf = OwnerOf(fkey)
                if owner == store and leaf == key then
                    for mapKey, m in pairs(e.values) do
                        if mapKey ~= "default" and type(m) == "table" and m[fkey] ~= nil then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

--- True while SOME override -- spec or conditional -- still holds a value for `key` of
--- `store`. A control that writes its own marker key (the Visibility row's override)
--- asks before trusting a live one: removing an entry from the management list leaves
--- its applied value in place on purpose, and a profile exported while an override
--- applied carries the marker into every import that does not also take the overrides.
--- In both cases nothing owns the key any more and the element would stay pinned on it
--- with no path back.
function EllesmereUI.SpecOverrides_KeyIsOwned(store, key)
    if type(store) ~= "table" or type(key) ~= "string" then return false end
    return StoreHoldsKey(GetStore(), store, key)
        or StoreHoldsKey(Cond.GetStore(), store, key)
end
end

--- Drop what the CURRENT session captured for ONE key across the given settings TABLES
--- and put the recorded pre-override values back live. `stores` is an ARRAY so a control
--- writing one key to several tables (Resource Bars mirrors the Visibility row onto
--- health/primary/secondary) clears them in one pass: the finalization below re-snapshots
--- every module profile, far too expensive to repeat once per table. Attribution is by
--- TABLE IDENTITY: AutoCapture attributes an entry by slot label, the exit sweep mints
--- entries from the fkey alone with no slot fields, and only identity matches both
--- shapes. Returns true when something was cleared.
function EllesmereUI.SpecOverrides_ClearStoreKey(stores, key)
    if type(stores) ~= "table" or type(key) ~= "string" then return false end
    local condSession = Cond._edit
    if not (_editGroup or condSession) then return false end
    local sStore = condSession and Cond.GetStore() or GetStore()
    if not sStore then return false end

    -- The value maps this session owns. A conditional session keeps one map per GROUP;
    -- the spec side keeps one per SPEC and a group covers every member spec, which is
    -- also how HarvestGroup banks into all of them.
    local owned = {}
    if condSession then
        owned[1] = condSession.id
    else
        for _, specID in ipairs(_editGroup.specs or {}) do owned[#owned + 1] = specID end
    end

    local cleared = false
    for i = #sStore, 1, -1 do
        local e = sStore[i]
        local def = e.values and e.values.default
        -- One entry can hold the key for SEVERAL of the stores (a mirrored row banks all
        -- of them into the same slot), so every hit is collected rather than the first.
        local hits
        if def then
            for fkey in pairs(def) do
                local owner, leaf = OwnerOf(fkey)
                if leaf == key and owner ~= nil then
                    for si = 1, #stores do
                        if owner == stores[si] then
                            hits = hits or {}
                            hits[#hits + 1] = fkey
                            break
                        end
                    end
                end
            end
        end
        for h = 1, (hits and #hits or 0) do
            local hit = hits[h]
            -- Only the maps the EDITED session owns are cleared. One entry is shared by
            -- every group that customized the same slot (AutoCapture looks it up by slot,
            -- not by group, and adds a per-group value map), so wiping all of them would
            -- delete other groups' overrides along with this one.
            for _, mapKey in ipairs(owned) do
                local m = e.values[mapKey]
                if type(m) == "table" then m[hit] = nil end
            end
            -- The recorded default only goes once nobody holds a value for the key any
            -- more; until then the entry stays alive for the groups that still do.
            local stillHeld = false
            for mapKey, m in pairs(e.values) do
                if mapKey ~= "default" and type(m) == "table" and m[hit] ~= nil then
                    stillHeld = true
                    break
                end
            end
            local dv = def[hit]
            if dv == NIL_SENT then dv = nil end
            -- Same guard the apply sites use: a stored removal is never honored for a
            -- key the module registers a default for. Written either way: the session
            -- has to show the value it just gave up.
            if dv ~= nil or not HasRegisteredDefault(hit) then WriteLive(hit, dv) end
            if not stillHeld then def[hit] = nil end
            cleared = true
        end
        -- Hoisted out of the hits loop: removing inside it would delete a DIFFERENT entry
        -- on the second pass, index i no longer being this one.
        if hits and def and not next(def) then table.remove(sStore, i) end
    end

    if cleared then
        if condSession then Cond.RebuildIndex() else RebuildFKeyIndex() end
        -- The restore write is ours, not the user's: re-snapshot so neither the ticker
        -- nor the queued notified pass can diff it straight back into a capture.
        _watchSnap = SnapshotProfiles()
        SetWatchResync(true)
        RequestGoldWalk()
    end
    return cleared
end

local function WatchTick()
    if not _editGroup and not Cond._edit then return end
    SampleAttribution()
    local root = _G.EllesmereUIFrame
    if not (root and root:IsShown()) then return end
    -- Folded to the mini window: nothing on the panel can be edited, so skip the
    -- profile diff; the unfold re-baselines the snapshot (RegisterOnCollapse below).
    if EllesmereUI._panelCollapsed then return end
    -- Hidden search prebuild mid-session: its selector setters and lazy page
    -- seeding write db.profile; absorb the whole tick (resync) so those writes
    -- can never diff into captures.
    if EllesmereUI._prebuilding then
        _watchSnap = SnapshotProfiles()
        return
    end
    if not _watchSnap then
        _watchSnap = SnapshotProfiles()
        return
    end
    local diffs = DiffProfiles(_watchSnap)
    if #diffs == 0 then return end
    if not _watchResync then
        local newOnes = nil
        for _, c in ipairs(diffs) do
            if Cond._edit then
                -- Conditional session: spec-owned fkeys are editable here too
                -- (each store keeps its own value; the session shows
                -- conditional-over-default) but spec still wins at RUNTIME.
                -- Cond-owned fkeys bank at exit.
                if not Cond.EntryOwning(c.fkey) then
                    newOnes = newOnes or {}
                    newOnes[#newOnes + 1] = c
                end
            elseif not EntryOwning(c.fkey) then
                newOnes = newOnes or {}
                newOnes[#newOnes + 1] = c
            end
        end
        if newOnes then AutoCapture(newOnes) end
    end
    SetWatchResync(false)
    _watchSnap = SnapshotProfiles()
end

-- Unfolding from the mini window: absorb whatever changed the profiles while the
-- panel was folded (WatchTick skipped them), so the first widget edit after it
-- (ProcessNotifiedWrites diffs against the same snapshot) captures only itself.
EllesmereUI:RegisterOnCollapse(function(on)
    if not on and (_editGroup or Cond._edit) and _watchSnap then
        _watchSnap = SnapshotProfiles()
    end
end)

-- Page rebuilds lazily seed defaults into profiles; absorb those writes instead of
-- capturing them (fast-path refreshes don't rebuild rows and keep capture armed).
-- Also the panel-lifecycle bootstrap: page activity means the panel exists/opened,
-- so install the show/hide hooks and enter the Default view when idle.
local function OnPageRebuilt()
    SetWatchResync(true)
    RequestGoldWalk()
    if ApplyEditOverlay then ApplyEditOverlay() end   -- chrome-page suppression
    if EnsurePanelHideHook then EnsurePanelHideHook() end
    -- The toolbar button disables on excluded pages; re-evaluate per page.
    if EllesmereUI._specOvBtnPageState then EllesmereUI._specOvBtnPageState() end
    -- BM passive chrome follows page navigation: shows on the Buff Manager page
    -- with a live fork, clears when leaving it.
    if EllesmereUI.SpecOverrides_UpdateBmPassiveChrome then
        EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    end
    if not _editGroup and not _defaultView then
        C_Timer.After(0, function()
            -- _unlockRoundtrip: the post-unlock page restore rebuilds pages before the
            -- OnShow restore consumes the stash, so entering the Default view here
            -- would only churn (the session re-enter exits it a tick later).
            if not _editGroup and not _defaultView and not _unlockRoundtrip
               and _G.EllesmereUIFrame and _G.EllesmereUIFrame:IsShown()
               and EnterDefaultView then
                EnterDefaultView()
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Notified writes: the widget factory calls _NotifySettingWrite on EVERY widget
--  setValue. Primary capture path -- exact frame-based slot attribution, processed
--  next frame, immune to page-rebuild seed absorption (a forced refresh triggered
--  by the setter itself can never swallow the user's edit). The polling ticker is
--  only the fallback for writes outside the factory.
-------------------------------------------------------------------------------
local _pendingWrites, _pendingWriteQueued = nil, false

local function ProcessNotifiedWrites()
    _pendingWriteQueued = false
    local frames = _pendingWrites
    _pendingWrites = nil
    -- the queued snapshot is read below, before anything can take it again
    _lastAttr.busy = false
    if not (_editGroup or Cond._edit) or not _watchSnap then return end
    -- Prebuild writes are never user edits: absorb via resync (see WatchTick).
    if EllesmereUI._prebuilding then
        _watchSnap = SnapshotProfiles()
        return
    end
    -- Exact attribution from the notified frames (first that resolves wins). An
    -- entry is either a snapshot the notifier took (EllesmereUI._SOAttribution)
    -- or the frame itself, resolved here as it stands now.
    for _, f in ipairs(frames or {}) do
        if type(f) == "table" then
            if f._soSnap then
                if f.cfg then
                    local h = _lastAttr.held
                    h.cfg, h.section, h.tip = f.cfg, f.section, f.tip
                    _lastAttr.snap, _lastAttr.time = h, GetTime()
                    break
                end
            else
                local n, region = f, nil
                while n do
                    if n._captureCfg then region = n; break end
                    n = n:GetParent()
                end
                if region then
                    _lastAttr.snap, _lastAttr.time = _lastAttr.Snap(region, _lastAttr.held), GetTime()
                    break
                end
            end
        end
    end
    local diffs = DiffProfiles(_watchSnap)
    if #diffs == 0 then return end
    local newOnes
    for _, c in ipairs(diffs) do
        -- Ownership filter mirrors WatchTick's session branch: in a cond
        -- session cond-owned fkeys bank at exit (HarvestEdit); everything else
        -- captures immediately here.
        local owned
        if Cond._edit then
            owned = Cond.EntryOwning(c.fkey)
        else
            owned = EntryOwning(c.fkey)
        end
        if not owned then
            newOnes = newOnes or {}
            newOnes[#newOnes + 1] = c
        end
    end
    if newOnes then AutoCapture(newOnes) end
    _watchSnap = SnapshotProfiles()
end

-- One-time warning when a BASE edit (Default Editing Mode) lands on an OVERRIDDEN
-- slot: the change edits the shared default only, and a user who does not know the
-- system reads "my change didn't apply" on the specs the override covers. Same
-- video-guide popup as the glyph's first click with warning copy; FireOnce stamps
-- seen before showing (/euivideos resets). Reached only while the Default view is
-- live (store non-empty, panel open, no session), so users without overrides pay a
-- single boolean per write.
local _warnWatch   -- one-shot GLOBAL_MOUSE_UP frame: the guide never pops mid-drag
local function MaybeWarnDefaultEdit(frame, snap)
    local DEFAULT_EDIT_GUIDE = "override_default_edit"
    local VG = EllesmereUI.VideoGuides
    if not VG or VG.HasSeen(DEFAULT_EDIT_GUIDE) then return end
    -- Hidden search prebuild: selector setters run on pages the user never sees.
    if EllesmereUI._prebuilding then return end
    if _warnWatch and _warnWatch._pending then return end
    -- Only a slot the last gold walk marked as overridden qualifies (from the
    -- notifier's snapshot when it took one, else the frame as it stands now).
    if snap then
        if not snap.tip then return end
    else
        local n = frame
        while n do
            if n._captureCfg then break end
            n = n.GetParent and n:GetParent() or nil
        end
        if not (n and n._specOvTip) then return end
    end
    if not _warnWatch then
        _warnWatch = CreateFrame("Frame")
        _warnWatch:SetScript("OnEvent", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_UP")
            -- Next frame: the release itself (slider commit, picker close) settles first.
            C_Timer.After(0, function()
                self._pending = nil
                VG.FireOnce(DEFAULT_EDIT_GUIDE)
            end)
        end)
    end
    _warnWatch._pending = true
    if IsMouseButtonDown() then
        -- Sliders and color pickers notify on every drag step; a dimmer landing
        -- under a held button would swallow the release. Fire when it comes up.
        _warnWatch:RegisterEvent("GLOBAL_MOUSE_UP")
    else
        -- Deferred: the notify runs inside the widget setter, often mid-refresh.
        C_Timer.After(0, function()
            _warnWatch._pending = nil
            VG.FireOnce(DEFAULT_EDIT_GUIDE)
        end)
    end
end

--- The slot a widget write belongs to, as a snapshot taken NOW: { cfg = the
--- slot's capture config, section = its section name, tip = its overridden tip }.
--- A setter that rebuilds the page (options page pool: the same frames dressed
--- again for other slots) must not move the attribution, so the widget factory
--- takes it BEFORE calling the user setter and hands it to _NotifySettingWrite.
--- nil when nothing would read it (no editing session; the Default view once
--- its warning was seen) or when the frame belongs to no slot. Same parent walk
--- as the notified pass. In a session it fills ONE reused table: the first write
--- of a frame wins the next frame's attribution (ProcessNotifiedWrites), so the
--- writes after it, until that pass ran, take none (their frames are queued).
--- detached (optional): a table the caller owns, filled instead, in or out of a
--- session and leaving that one-per-frame rule alone, for a widget that writes
--- later for the slot it was opened from (the color picker takes one when it
--- opens and hands it to _NotifySettingWrite with each later write: it names
--- that slot even after a rebuild dressed the widget again for another one).
--- Returns detached (marked as a snapshot), or nil when no slot holds frame.
function EllesmereUI._SOAttribution(frame, detached)
    if type(frame) ~= "table" then return nil end
    local into = detached
    if into == nil then
        if _editGroup or Cond._edit then
            if _lastAttr.busy then return nil end
            into = _lastAttr.pend
        elseif _defaultView then
            -- read at once by MaybeWarnDefaultEdit, only until its guide was seen
            local VG = EllesmereUI.VideoGuides
            if not VG or VG.HasSeen("override_default_edit") then return nil end
        else
            return nil
        end
    end
    local n = frame
    while n do
        if n._captureCfg then
            if detached then
                detached._soSnap = true
            elseif into then
                _lastAttr.busy = true
            end
            return _lastAttr.Snap(n, into or { _soSnap = true })
        end
        n = n.GetParent and n:GetParent() or nil
    end
    return nil
end

--- Called by the widget factory whenever any options widget writes a value.
--- snap: the slot snapshot the factory took before the setter ran (optional;
--- a detached one stands alone, with no frame).
function EllesmereUI._NotifySettingWrite(frame, snap)
    -- Conditional sessions capture through this path too. Without them in the gate they
    -- fall back to watcher/exit-sweep capture only, losing edits whenever a setter's
    -- forced refresh raises the resync absorb before a tick can attribute them.
    if not (_editGroup or Cond._edit) then
        if _defaultView and (type(frame) == "table" or snap ~= nil) then MaybeWarnDefaultEdit(frame, snap) end
        return
    end
    _pendingWrites = _pendingWrites or {}
    _pendingWrites[#_pendingWrites + 1] = snap or frame or false
    if not _pendingWriteQueued then
        _pendingWriteQueued = true
        C_Timer.After(0, ProcessNotifiedWrites)
    end
end

-------------------------------------------------------------------------------
--  Exit-sweep safety net: anything that changed during the session and never
--  got captured (bespoke widgets, frame drags) must not leak into the real
--  spec. Sweeping it into the group lets the exit restore undo it live.
-------------------------------------------------------------------------------
SweepUncaptured = function(group)
    if not _enterSnap or not group then return end
    local store = GetStore(true)
    if not store then return end
    local added = false
    for _, c in ipairs(DiffProfiles(_enterSnap)) do
        -- MatchOwnedFKey: a match-owned size diff is the match engine's write,
        -- never a session edit; minting an entry from it hands the key to the
        -- harvest broadcast (proliferation vector).
        if not EntryOwning(c.fkey) and (not c.num or NumAllowedFKey(c.fkey)) and not BlacklistedFKey(c.fkey)
           and not MatchOwnedFKey(c.fkey)
           and not _sessionIgnored[c.fkey] then
            local orig = SnapValue(_enterSnap, c.fkey)
            -- Same guard as AutoCapture: a cond-owned fkey's snapshot may be
            -- an applied conditional's overlay; seed from the cond store's
            -- recorded default instead.
            local ce = Cond.EntryOwning(c.fkey)
            if ce then
                orig = ce.values.default[c.fkey]
                if orig == NIL_SENT then orig = nil end
            end
            if type(orig) == "table" then orig = nil end
            local entry = {
                label = PrettyKey(c.fkey),
                crumb = (EllesmereUI:GetModuleTitle(c.folder)) or c.folder,
                module = c.folder,
                group = group.id,
                values = { default = { [c.fkey] = (orig == nil) and NIL_SENT or orig } },
            }
            -- The real spec's map is deliberately not seeded (see AutoCapture).
            store[#store + 1] = entry
            added = true
        end
    end
    if added then
        RebuildFKeyIndex()
    end
end
SetSweepUncaptured(SweepUncaptured)

-------------------------------------------------------------------------------
--  Editing-as core
-------------------------------------------------------------------------------
local editBanner, editBannerText, editBannerStatus
local panelHideHooked = false

EnsurePanelHideHook = function()
    if panelHideHooked or not _G.EllesmereUIFrame then return end
    panelHideHooked = true
    _G.EllesmereUIFrame:HookScript("OnHide", function()
        -- Unlock-mode roundtrip: when the panel hides because Unlock Mode was opened
        -- FROM the options window, remember the active editing session so the
        -- auto-reopen restores the same override view. The session still tears down
        -- normally below (values bank safely; only the SELECTION is remembered). A
        -- hide with no session leaves any pending stash untouched -- the panel can
        -- flash shown/hidden while unlock force-closes.
        if EllesmereUI._unlockReturnModule ~= nil then
            if _editGroup then
                _unlockRoundtrip = { kind = "spec", id = _editGroup.id }
            elseif Cond._edit then
                _unlockRoundtrip = { kind = "cond", id = Cond._edit.id }
            end
        end
        if ExitGroupEdit then ExitGroupEdit() end
        if Cond.ExitEdit then Cond.ExitEdit() end
        if ExitDefaultView then ExitDefaultView() end
        if EllesmereUI._specOvCardsPopup then EllesmereUI._specOvCardsPopup:Hide() end
        if Cond._cardsPopup then Cond._cardsPopup:Hide() end
        -- Name/icon popups parent to UIParent and would survive the panel closing; their
        -- Create/Save buttons enter an edit session, and a session entered with the
        -- panel HIDDEN snapshots before the deferred page rebuild's lazy seeding, so the
        -- exit sweep adopts those seeds as phantom captures. Close them with the panel.
        if EllesmereUI._specOvNamePopup then EllesmereUI._specOvNamePopup:Hide() end
        if Cond._namePopup then Cond._namePopup:Hide() end
        -- The condition picker leads into the name popup and holds a key
        -- capture that must not stay up into combat: it closes too.
        if Cond._pickerPopup then Cond._pickerPopup:Hide() end
    end)
    -- Re-entering the panel returns to the Default Editing Mode view, or after
    -- an options-entered unlock roundtrip back to the session that was active
    -- when unlock hid the panel.
    _G.EllesmereUIFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if not (_G.EllesmereUIFrame and _G.EllesmereUIFrame:IsShown()) then return end
            local rt = _unlockRoundtrip
            if rt then
                -- One-shot: consumed only on a show that processes (the
                -- force-close flow can flash the panel shown->hidden).
                _unlockRoundtrip = nil
                if rt.kind == "spec" and EnterGroupEdit then
                    for _, g in ipairs(GetGroups() or {}) do
                        if g.id == rt.id then EnterGroupEdit(g); return end
                    end
                elseif rt.kind == "cond" and Cond.EnterEdit then
                    local cgroups = EllesmereUI.Conditions_GetGroups and EllesmereUI.Conditions_GetGroups()
                    for _, g in ipairs(cgroups or {}) do
                        if g.id == rt.id then Cond.EnterEdit(g); return end
                    end
                end
                -- Group vanished mid-roundtrip: fall through to Default view.
            end
            if EnterDefaultView then
                EnterDefaultView()
            end
        end)
    end)
end

local function EnsureEditBanner()
    if editBanner then return editBanner end
    -- The panel body, so the banner hides with the window when it collapses.
    local root = EllesmereUI._panelBody or UIParent
    editBanner = CreateFrame("Frame", nil, root)
    editBanner:SetSize(680, 44)
    -- Sits ON TOP of the visible panel: banner bottom flush with the window's
    -- top edge (the click area is the actual window; the outer frame includes
    -- the background art's shadow padding).
    editBanner:SetPoint("BOTTOM", _G.EllesmereUIClickArea or root, "TOP", 0, 0)
    editBanner:SetClampedToScreen(true)
    editBanner:SetFrameStrata("DIALOG")
    local bg = editBanner:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    local brd = editBanner:CreateTexture(nil, "BORDER")
    brd:SetPoint("BOTTOMLEFT"); brd:SetPoint("BOTTOMRIGHT")
    brd:SetHeight(1)
    brd:SetColorTexture(EDIT_R, EDIT_G, EDIT_B, 0.7)
    editBannerText = editBanner:CreateFontString(nil, "OVERLAY")
    editBannerText:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
    editBannerText:SetPoint("TOPLEFT", editBanner, "TOPLEFT", 16, -8)
    editBannerText:SetTextColor(EDIT_R, EDIT_G, EDIT_B, 1)
    editBannerStatus = editBanner:CreateFontString(nil, "OVERLAY")
    editBannerStatus:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
    editBannerStatus:SetPoint("BOTTOMLEFT", editBanner, "BOTTOMLEFT", 16, 7)
    editBannerStatus:SetTextColor(1, 1, 1, 0.6)
    local done = CreateFrame("Button", nil, editBanner)
    done:SetSize(74, 24)
    done:SetPoint("RIGHT", editBanner, "RIGHT", -12, 0)
    EllesmereUI.SolidTex(done, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local dbrd = EllesmereUI.MakeBorder(done, 1, 1, 1, 0.22)
    local dlbl = EllesmereUI.MakeFont(done, 11, nil, 1, 1, 1, 0.9)
    dlbl:SetPoint("CENTER")
    dlbl:SetText(L("Done"))
    done:SetScript("OnEnter", function() if dbrd and dbrd.SetColor then dbrd:SetColor(EDIT_R, EDIT_G, EDIT_B, 0.8) end end)
    done:SetScript("OnLeave", function() if dbrd and dbrd.SetColor then dbrd:SetColor(1, 1, 1, 0.22) end end)
    done:SetScript("OnClick", function()
        if _editGroup then ExitGroupEdit() end
        if Cond.ExitEdit then Cond.ExitEdit() end
    end)
    editBanner._done = done   -- passive chrome hides it (nothing to exit)
    return editBanner
end

SetEditStatus = function(text, r, g, b)
    if editBannerStatus then
        editBannerStatus:SetText(text or "")
        editBannerStatus:SetTextColor(r or 1, g or 1, b or 0.6)
    end
end

ShowEditBanner = function(group)
    EnsureEditBanner()
    if editBanner._done then editBanner._done:Show() end   -- passive mode hides it
    editBannerText:SetText(string.format(L("Editing as %s"), group.name or "?"))
    SetEditStatus(L("Any setting you change now applies only to this group's specs."), 1, 1, 0.6)
    editBanner:Show()
    -- Lock excluded modules on the sidebar for the session's duration.
    if EllesmereUI.RefreshSidebarOverrideLocks then EllesmereUI.RefreshSidebarOverrideLocks() end
end

HideEditBanner = function()
    if editBanner then editBanner:Hide() end
end

-- Background glow overlay shown while Editing-as. Aligned 1:1 with the options
-- panel background layers (both fill EllesmereUIFrame edge to edge), one frame
-- level above them and below all content frames.
local EDIT_GLOW_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\backgrounds\\eui-glow-override.png"
local editOverlay
local editOverlayTexture = EDIT_GLOW_TEXTURE

-- The glow suppresses itself on excluded contexts (chrome pages + Global
-- Settings General) and returns on normal module pages.
local _overlayWanted = false

ApplyEditOverlay = function()
    if not editOverlay then return end
    editOverlay:SetShown(_overlayWanted and not IsExcludedContext())
end

local function SetEditOverlayShown(shown)
    _overlayWanted = shown and true or false
    if shown and not editOverlay then
        local root = _G.EllesmereUIFrame
        if not root then return end
        editOverlay = CreateFrame("Frame", nil, EllesmereUI._panelBody)
        editOverlay:SetAllPoints(root)
        editOverlay:SetFrameLevel(root:GetFrameLevel() + 1)
        editOverlay:EnableMouse(false)
        local tex = editOverlay:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetTexture(editOverlayTexture)
        editOverlay._tex = tex
    end
    ApplyEditOverlay()
end

TeardownEditSession = function()
    if _watchTicker then _watchTicker:Cancel(); _watchTicker = nil end
    _watchSnap = nil
    SetEnterSnap(nil)
    _sessionIgnored = {}
    HideEditBanner()
    SetEditOverlayShown(false)
    UpdateIndicator()
    UpdateEditLocks()   -- release threshold/hands-off locks
    RequestGoldWalk()   -- clear conflict-red marks back to gold
    -- Unlock the sidebar (session over for either system).
    if EllesmereUI.RefreshSidebarOverrideLocks then EllesmereUI.RefreshSidebarOverrideLocks() end
end
SetTeardownEditSession(TeardownEditSession)

-- Passive override chrome: the Buff Manager page binds to the live fork even
-- WITHOUT an editing session (the prelude auto-activates it), so the session's
-- glow + banner must show there too. A real session owns the chrome outright;
-- this only fills the no-session case and cleans up after itself.
local _bmPassiveChrome = false

function EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    if _editGroup or Cond._edit then return end   -- real session owns chrome
    local kind = EllesmereUI.SpecOverrides_BmPageLockInfo() or nil
    local status = L("Buff Manager changes on this page apply only to this override.")
    local nameFn = EllesmereUI.SpecOverrides_BmActiveInfo
    if not kind then
        -- Same chrome serves the Debuff Manager page (one page is active at a
        -- time, so the two locks can never both report).
        kind = EllesmereUI.SpecOverrides_DmPageLockInfo() or nil
        if kind then
            status = L("Debuff Manager changes on this page apply only to this override.")
            nameFn = EllesmereUI.SpecOverrides_DmActiveInfo
        end
    end
    if kind then
        local name = (nameFn and nameFn()) or "?"
        EnsureEditBanner()
        editBannerText:SetText(string.format(L("Override Active: %s"), name))
        SetEditStatus(status, 1, 1, 0.6)
        if editBanner._done then editBanner._done:Hide() end   -- nothing to exit
        editBanner:Show()
        SetEditOverlayShown(true)
        _bmPassiveChrome = true
    elseif _bmPassiveChrome then
        _bmPassiveChrome = false
        HideEditBanner()
        SetEditOverlayShown(false)
        if editBanner and editBanner._done then editBanner._done:Show() end
    end
    -- The toolbar glyph's lock state tracks the same signal (fork created or
    -- deleted mid-page never goes through a page selection).
    if EllesmereUI._specOvBtnPageState then EllesmereUI._specOvBtnPageState() end
end

-------------------------------------------------------------------------------
--  Default Editing Mode view: while the options panel is open WITHOUT an
--  Editing-as session, the stored DEFAULT values swap into the live paths so
--  the panel always shows and edits the shared baseline, even when the current
--  spec belongs to an override group. Closing the panel (or entering
--  Editing-as) banks default edits and restores the spec's values.
-------------------------------------------------------------------------------
PanelShown = function()
    local root = _G.EllesmereUIFrame
    return root and root:IsShown() or false
end
SetPanelShown(PanelShown)

EnterDefaultView = function()
    if _defaultView or _editGroup or Cond._edit or _inTransition then return end
    local store = GetStore()
    if not store or #store == 0 then return end
    -- Bank the real spec's live edits first, then swap the defaults in.
    EllesmereUI.SpecOverrides_HarvestCurrent()
    SetDefaultView(true)
    local touched = WriteDefaultValues()
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild: default values may drive different page structure than
    -- the spec values they replaced.
    EllesmereUI:RefreshPage(true)
    UpdateIndicator()
end
SetEnterDefaultView(EnterDefaultView)

ExitDefaultView = function(restore)
    if not _defaultView then return end
    SetDefaultView(false)
    HarvestDefaults()
    if restore ~= false then
        local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
        if touched then RunRefreshers(touched) end
    end
    UpdateIndicator()
end

--- Steps OUT of the Default view for the duration of a CONDITIONAL flip, and back
--- in afterwards. Returns true when the view was actually suspended (caller must
--- then resume it).
---
--- Why not just refuse the flip: the Dark Mode condition's only inputs (the Colors
--- page's Dark Mode rows, Class Resource Bar aside) live INSIDE the options panel,
--- so its flips are ALWAYS raised with the view up, and only a zone change/roster
--- update/combat end/reload re-drives a deferred flip -- it can stay pending a
--- whole session. While pending, the outgoing conditional stays APPLIED and keeps
--- reporting itself as the applied group, so later banks file plain baseline
--- edits into its map until the flip converges and repaints the untouched
--- defaults over them.
---
--- Suspending mirrors how a SPEC transition uses this view (banks edits, restores
--- canonical live on the way out via OnSpecChanged/HarvestCurrent, SpecOverrides_
--- Apply's tail re-enters). Resuming AFTER the applied pointer advances is
--- load-bearing: EnterDefaultView harvests through HarvestCurrent, which resolves
--- the applied gid, so re-entering first would bank the INCOMING conditional's
--- live values into the OUTGOING group's maps.
function EllesmereUI.SpecOverrides_SuspendDefaultView()
    if not _defaultView then return false end
    ExitDefaultView()
    return true
end

function EllesmereUI.SpecOverrides_ResumeDefaultView()
    if PanelShown() then EnterDefaultView() end
end

--- noRecheck: this exit is a PREAMBLE inside another operation (entering a
--- different session, a membership/delete rewrite, opening unlock mode, a profile
--- apply) rather than the user finishing, so it must not have a conditional
--- transition wedged into it -- most sharply the unlock and profile paths, where
--- the transition's ApplyUnlock schedules its flush TWO FRAMES out and it would
--- land inside unlock mode's snapshot window, or after a profile swap refilled
--- the live tables. Mirror of Cond.ExitEdit's noRecheck.
ExitGroupEdit = function(noRecheck)
    if not _editGroup then return end
    WatchTick()   -- catch trailing edits from the last sub-tick window
    local g = _editGroup
    SetEditGroup(nil)
    SweepUncaptured(g)
    HarvestGroup(g)
    TeardownEditSession()
    local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild: restored values can change page STRUCTURE (sections
    -- shown/hidden by a visibility dropdown); the fast refresh only re-reads
    -- widget values and would leave stale structure on screen.
    EllesmereUI:RefreshPage(true)
    RequestGoldWalk()
    -- Back to Default Editing Mode: the open panel returns to the baseline.
    if PanelShown() then EnterDefaultView() end
    -- A condition flip raised mid-session was deferred (the handler bails while
    -- a session holds swapped values live); resolve it now, like ExitEdit.
    if not noRecheck and EllesmereUI.Conditions_Recheck then
        EllesmereUI.Conditions_Recheck()
    end
    -- WoW Forever: a group created or deleted while this session was open can
    -- move the spec the class acts as; the user finishing applies it (never a
    -- preamble exit).
    if EllesmereUI.IS_FOREVER and not noRecheck then EllesmereUI._SO_ForeverConverge() end
end
SetExitGroupEdit(ExitGroupEdit)

--- Force-closes every editing-as session (spec group, conditional, Default view).
--- Profile apply/import/switch call this BEFORE swapping stores: the exits bank and
--- restore against the OUTGOING profile, and the post-swap establish
--- (Conditions_MarkStale + Recheck) must never find a live session -- the
--- transition handler refuses under one, stranding the incoming profile
--- un-overlaid until the next zone change.
function EllesmereUI.SpecOverrides_CloseEditSessions()
    -- Unlock-open window: remember the active session so the post-unlock reopen
    -- restores it. Same stash the panel-hide hook takes, but OpenUnlockMode closes
    -- sessions BEFORE the panel hides (the value snapshot must be taken over
    -- canonical live data), so the hook finds no session and would lose the roundtrip.
    if EllesmereUI._unlockReturnModule ~= nil then
        if _editGroup then
            _unlockRoundtrip = { kind = "spec", id = _editGroup.id }
        elseif Cond._edit then
            _unlockRoundtrip = { kind = "cond", id = Cond._edit.id }
        end
    end
    if _editGroup and ExitGroupEdit then ExitGroupEdit(true) end
    -- noRecheck: every caller here drives its own choreography and must NOT have a
    -- conditional transition wedged into it. A deferred flip resolved from this exit
    -- would run ApplyUnlock, whose flush is scheduled TWO FRAMES out; on the profile
    -- apply/switch callers that lands AFTER the live tables are wiped and refilled,
    -- writing the OUTGOING profile's layer geometry into the INCOMING profile's
    -- module stores. Not stranding: the profile paths run Conditions_MarkStale +
    -- Recheck right after the swap, unlock open re-resolves on close, and
    -- PromoteGroupToProfile ends in a ReloadUI.
    if Cond._edit and Cond.ExitEdit then Cond.ExitEdit(nil, true) end
    if _defaultView and ExitDefaultView then ExitDefaultView() end
end

EnterGroupEdit = function(group, force)
    if _editGroup == group then return end
    if not group or not group.specs or #group.specs == 0 then return end
    -- BM page lock: while the Buff Manager page is bound to a live fork, only
    -- THAT group's session may open from the cards popup; any other context
    -- would edit settings the page is not displaying. force: the manager
    -- sidebar's override list switches directly (the page rebuild rebinds).
    do
        local lockKind, lockGid
        local lockLabel = "Buff Manager"
        if EllesmereUI.SpecOverrides_BmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_BmPageLockInfo()
        end
        if not lockKind and EllesmereUI.SpecOverrides_DmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_DmPageLockInfo()
            if lockKind then lockLabel = "Debuff Manager" end
        end
        if lockKind and not force and not (lockKind == "spec" and lockGid == group.id) then
            EllesmereUI:ShowConfirmPopup({
                title = string.format(L("%s Override Active"), L(lockLabel)),
                message = string.format(L("The active override's custom %s is bound to this page. Leave the %s tab to switch to another override."), L(lockLabel), L(lockLabel)),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    -- Preamble teardown, not the user finishing: no conditional recheck (a
    -- deferred flip resolves at the session end that really ends editing).
    if _editGroup then ExitGroupEdit(true) end
    if Cond.ExitEdit then Cond.ExitEdit(nil, true) end   -- sessions never coexist
    -- Leave the Default view (banks default edits, restores spec values), then
    -- bank the real spec's live edits and swap the group in.
    ExitDefaultView()
    EllesmereUI.SpecOverrides_HarvestCurrent()
    SetEditGroup(group)
    local touched = WriteGroupValues(group)
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild (structure may differ under the group's values); runs
    -- before the snapshot so lazy page seeding is absorbed.
    EllesmereUI:RefreshPage(true)
    _watchSnap = SnapshotProfiles()
    SetEnterSnap(_watchSnap)   -- session baseline for the exit sweep
    _sessionIgnored = {}
    _lastAttr.snap, _lastAttr.busy = nil, false
    _watchTicker = C_Timer.NewTicker(0.4, WatchTick)
    ShowEditBanner(group)
    SetEditOverlayShown(true)
    UpdateIndicator()
    UpdateEditLocks()
    RequestGoldWalk()
    EnsurePanelHideHook()
end

-------------------------------------------------------------------------------
--  Editing-as-CONDITIONAL: the same session machinery banking into the
--  conditional store. Mutually exclusive with editing-as-spec and the
--  Default view. Spec-owned fkeys are refused at capture time (spec wins).
-------------------------------------------------------------------------------

--- Banks live values into the edited group's maps. EVERY entry is examined, not just
--- the group's own: an fkey first overridden by another conditional lives in THAT
--- group's entry, and this session's edit to it must still bank here (entry.group is
--- card bookkeeping, not harvest ownership; the spec side harvests the whole store
--- the same way). Per fkey: live equal to the recorded default clears the group's
--- override, anything else banks; empty maps drop so cards only list entries the
--- group actually customizes.
function Cond.HarvestEdit(g)
    for _, entry in ipairs(Cond.GetStore() or {}) do
        if entry.values and entry.values.default then
            local map = entry.values[g.id]
            for fkey, dv in pairs(entry.values.default) do
                local live = ReadLive(fkey)
                -- Table-typed live: structure change, never bank (aliasing).
                -- FKeyLoaded: a disabled module reads nil, never bank that.
                -- MatchOwnedFKey: match-engine writes never bank (mirrors the
                -- spec-side Harvest); the held value stays as-is.
                if FKeyLoaded(fkey) and type(live) ~= "table"
                   and not MatchOwnedFKey(fkey) then
                    local defVal = dv; if defVal == NIL_SENT then defVal = nil end
                    if live == defVal then
                        -- Equal to the default: a REVERT only if this session
                        -- moved it there. An untouched key that merely compares
                        -- equal (the default was edited onto the group's value)
                        -- keeps its held value instead of dissolving.
                        local s = _enterSnap and SnapValue(_enterSnap, fkey)
                        if type(s) == "table" then s = nil end
                        if map and _enterSnap and s ~= live then
                            map[fkey] = nil
                        end
                    else
                        if not map then map = {}; entry.values[g.id] = map end
                        map[fkey] = (live == nil) and NIL_SENT or live
                    end
                end
            end
            if map and not next(map) then entry.values[g.id] = nil end
        end
    end
    Cond.PruneRedundant()
end

--- Exit sweep: uncaptured session diffs become new conditional entries
--- (mirror of SweepUncaptured with conditional ownership rules).
function Cond.SweepUncapturedEdit(g)
    if not _enterSnap or not g then return end
    local store = Cond.GetStore(true)
    if not store then return end
    local added = false
    for _, c in ipairs(DiffProfiles(_enterSnap)) do
        -- Spec ownership does NOT block cond capture (coexistence: each store
        -- keeps its own value; spec wins only at runtime). MatchOwnedFKey:
        -- never mint from a match engine write (see SweepUncaptured).
        if not Cond.EntryOwning(c.fkey)
           and (not c.num or NumAllowedFKey(c.fkey)) and not BlacklistedFKey(c.fkey)
           and not MatchOwnedFKey(c.fkey)
           and not _sessionIgnored[c.fkey] then
            local orig = SnapValue(_enterSnap, c.fkey)
            if type(orig) == "table" then orig = nil end
            local entry = {
                label = PrettyKey(c.fkey),
                crumb = (EllesmereUI:GetModuleTitle(c.folder)) or c.folder,
                module = c.folder,
                group = g.id,
                values = { default = { [c.fkey] = (orig == nil) and NIL_SENT or orig } },
            }
            store[#store + 1] = entry
            added = true
        end
    end
    if added then Cond.RebuildIndex() end
end

--- noRestore: a spec transition is taking over. Even then the SPEC layer is written
--- back first -- the session swapped shared defaults over the spec-owned fkeys, and
--- the transition's Harvest(oldSpec) must bank real spec values, never the
--- session's default baseline. noRecheck: the caller drives its own choreography
--- and must not have a conditional transition interleaved (see CloseEditSessions).
Cond.ExitEdit = function(noRestore, noRecheck)
    if not Cond._edit then return end
    WatchTick()   -- catch trailing edits from the last sub-tick window
    -- Release the Buff Manager session swap FIRST: banks the session's BM edits
    -- into the group's fork while live still holds them, then puts the runtime
    -- layer back (skipped on noRestore: the transition's ApplyBm does it).
    EllesmereUI.SpecOverrides_BmSessionRelease(noRestore and true or false)
    EllesmereUI.SpecOverrides_DmSessionRelease(noRestore and true or false)
    local g = Cond._edit
    Cond._edit = nil
    Cond.SweepUncapturedEdit(g)
    Cond.HarvestEdit(g)
    TeardownEditSession()
    local touched = WriteSpecValues(_activeSpec or CurrentSpecID())
    if not noRestore then
        -- Canonical live = spec values + the APPLIED conditional's overlay.
        local t2 = Cond.WriteValues(
            EllesmereUI.Conditions_AppliedGid and EllesmereUI.Conditions_AppliedGid() or nil)
        if t2 then
            touched = touched or {}
            for k in pairs(t2) do touched[k] = true end
        end
        if touched then RunRefreshers(touched) end
        -- FORCED rebuild: see ExitGroupEdit (stale structure otherwise).
        EllesmereUI:RefreshPage(true)
        RequestGoldWalk()
        if PanelShown() then EnterDefaultView() end
        -- A mid-session condition flip was deferred (the transition handler
        -- bails during edit sessions); resolve it now.
        if not noRecheck and EllesmereUI.Conditions_Recheck then
            EllesmereUI.Conditions_Recheck()
        end
        -- WoW Forever: a group created or deleted while this session was open
        -- can move the spec the class acts as; the user finishing applies it.
        -- Only with the panel shown: the panel-hide hook also ends this session
        -- when a Customize Unlock Mode click hides the panel, and unlock mode
        -- opens before an apply's layer flush lands.
        if EllesmereUI.IS_FOREVER and not noRecheck and PanelShown() then
            EllesmereUI._SO_ForeverConverge()
        end
    end
    -- noRestore: store writes only -- the transition applies + refreshes.
    if Cond.RefreshCards then Cond.RefreshCards() end
end

Cond.EnterEdit = function(g, force)
    if Cond._edit == g then return end
    if not g then return end
    -- BM page lock: while the Buff Manager page is bound to a live fork, only
    -- that fork's own conditional session may open; anything else would edit
    -- settings the page is not displaying. force: as in EnterGroupEdit.
    do
        local lockKind, lockGid
        local lockLabel = "Buff Manager"
        if EllesmereUI.SpecOverrides_BmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_BmPageLockInfo()
        end
        if not lockKind and EllesmereUI.SpecOverrides_DmPageLockInfo then
            lockKind, lockGid = EllesmereUI.SpecOverrides_DmPageLockInfo()
            if lockKind then lockLabel = "Debuff Manager" end
        end
        if lockKind and not force and not (lockKind == "cond" and lockGid == g.id) then
            EllesmereUI:ShowConfirmPopup({
                title = string.format(L("%s Override Active"), L(lockLabel)),
                message = string.format(L("The active override's custom %s is bound to this page. Leave the %s tab to switch to another override."), L(lockLabel), L(lockLabel)),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    -- Preamble teardown, not the user finishing: no conditional recheck (a
    -- deferred flip resolves at the session end that really ends editing).
    if Cond._edit then Cond.ExitEdit(nil, true) end
    if _editGroup then ExitGroupEdit(true) end
    -- The session's baseline is the SHARED DEFAULT view: a conditional layers on the
    -- defaults, so a fresh one must look exactly like "no overrides", never like the
    -- current spec's override view. Spec values only win at APPLY time; while editing a
    -- conditional the panel shows conditional-over-default.
    local touched
    if _defaultView then
        -- Panel already shows the defaults; bank its edits and keep them live
        -- (no spec restore) -- that IS our baseline.
        ExitDefaultView(false)
    else
        EllesmereUI.SpecOverrides_HarvestCurrent()
        touched = WriteDefaultValues()
    end
    Cond._edit = g
    local t2 = Cond.WriteValues(g.id, true)
    if t2 then
        touched = touched or {}
        for k in pairs(t2) do touched[k] = true end
    end
    if touched then RunRefreshers(touched) end
    -- FORCED rebuild (structure may differ under the conditional's values).
    EllesmereUI:RefreshPage(true)
    _watchSnap = SnapshotProfiles()
    SetEnterSnap(_watchSnap)
    _sessionIgnored = {}
    _lastAttr.snap, _lastAttr.busy = nil, false
    _watchTicker = C_Timer.NewTicker(0.4, WatchTick)
    ShowEditBanner(g)
    SetEditStatus(L("Any setting you change now applies only while this conditional is active."), 1, 1, 0.6)
    SetEditOverlayShown(true)
    UpdateIndicator()
    UpdateEditLocks()
    RequestGoldWalk()
    EnsurePanelHideHook()
end

I.EnsurePanelHideHook, I.EnterGroupEdit = EnsurePanelHideHook, EnterGroupEdit
I.BuildEntryCrumb = BuildEntryCrumb
I.ExitGroupEdit, I.OnPageRebuilt = ExitGroupEdit, OnPageRebuilt
I.broken = false
