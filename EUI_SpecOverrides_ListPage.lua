if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_ListPage.lua
--
--  The management list page and Promote Override to Profile.
--  Reads the earlier Spec Overrides files through EUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
local I = EUI_NS._soInternals
-- EllesmereUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local ACCENT_B, ACCENT_G, ACCENT_R = I.ACCENT_B, I.ACCENT_G, I.ACCENT_R
local BlacklistedFKey, CurrentSpecID, DeepCopy = I.BlacklistedFKey, I.CurrentSpecID, I.DeepCopy
local EntryHolderGroup, EntryOwning = I.EntryHolderGroup, I.EntryOwning
local FKeyLoaded, GetGroups, GetStore, GOLD_B = I.FKeyLoaded, I.GetGroups, I.GetStore, I.GOLD_B
local GOLD_G, GOLD_R, GroupById = I.GOLD_G, I.GOLD_R, I.GroupById
local HasRegisteredDefault, L, MatchOwnedFKey = I.HasRegisteredDefault, I.L, I.MatchOwnedFKey
local NIL_SENT, ReadLive, RebuildFKeyIndex = I.NIL_SENT, I.ReadLive, I.RebuildFKeyIndex
local RunRefreshers, SpecInAnyGroup, SpecName = I.RunRefreshers, I.SpecInAnyGroup, I.SpecName
local SpecStrandedOnEntry, SplitFKey = I.SpecStrandedOnEntry, I.SplitFKey
local WriteLive, GetUnlockStore = I.WriteLive, I.GetUnlockStore
local WriteDefaultValues, GetBmStore = I.WriteDefaultValues, I.GetBmStore
local GetCondBmStore, GetCondDmStore = I.GetCondBmStore, I.GetCondDmStore
local GetDmStore, IsTBBChildKey, LayerSkipsKey = I.GetDmStore, I.IsTBBChildKey, I.LayerSkipsKey
local Cond, EXCLUDED_CONTEXTS, RequestGoldWalk = I.Cond, I.EXCLUDED_CONTEXTS, I.RequestGoldWalk
local EnterGroupEdit, BuildEntryCrumb = I.EnterGroupEdit, I.BuildEntryCrumb

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _editGroup = nil
I.editGroupSetters[#I.editGroupSetters + 1] = function(v) _editGroup = v end
local _activeSpec = nil
I.activeSpecSetters[#I.activeSpecSetters + 1] = function(v) _activeSpec = v end

-------------------------------------------------------------------------------
--  Management list page ("Spec Overrides" tab under Profiles & Presets).
--  Purely a list: per group, each captured setting with Go To / Remove.
-------------------------------------------------------------------------------
local function TitleCase(s)
    local out = s:gsub("(%a[%w']*)", function(w)
        return w:sub(1, 1):upper() .. w:sub(2):lower()
    end)
    return out
end

local function BuildListRow(parent, y, entry)
    -- Options page pool (EllesmereUI_FramePool.lua): on a pool host these rows
    -- are reset and dressed again by the next build (the list builders below).
    local CreateFrame = EllesmereUI._Pool.CreateFrame
    local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

    local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
    name:SetPoint("LEFT", row, "LEFT", 20, 0)
    name:SetText(L(entry.label or "?"))

    local crumb = EllesmereUI.MakeFont(row, 11, nil, 1, 1, 1, 0.3)
    crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
    -- Built from the entry's fields when it has a page, so a renamed module or
    -- tab label (or a client language switch) shows current names, not the
    -- baked crumb.
    local crumbText = entry.page and BuildEntryCrumb(entry.module, entry.element, entry.page, entry.section)
        or entry.crumb
    crumb:SetText(crumbText and TitleCase(crumbText) or "")

    local function MakeBtn(text, xOff, w)
        local b = CreateFrame("Button", nil, row)
        b:SetSize(w or 110, 22)
        b:SetPoint("RIGHT", row, "RIGHT", xOff, 0)
        EllesmereUI.SolidTex(b, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.22)
        local lbl = EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1, 0.8)
        lbl:SetPoint("CENTER")
        lbl:SetText(L(text))
        return b, brd
    end

    -- One row serves BOTH stores: entries created by an editing-as-conditional
    -- session live in the conditional store and remove from it.
    local isCondEntry
    do
        local cst = Cond.GetStore()
        if cst then
            for _, e in ipairs(cst) do
                if e == entry then isCondEntry = true; break end
            end
        end
    end
    -- A conditional entry whose fkey a SPEC override also owns never applies at
    -- runtime: Cond.WriteValues skips spec-owned fkeys outside an editing session
    -- (the forSession gate), so the value shows while the session is open and is
    -- dropped the moment it closes. The row otherwise reads as live while doing
    -- nothing, which is the whole reason this is hard to diagnose -- name the
    -- owner instead of leaving the eviction silent.
    if isCondEntry then
        local ownerEntry
        for fkey in pairs(entry.values and entry.values.default or {}) do
            ownerEntry = EntryOwning(fkey)
            if ownerEntry then break end
        end
        if ownerEntry then
            local og = GroupById(ownerEntry.group)
            local warn = EllesmereUI.MakeFont(row, 11, nil, 1, 0.45, 0.45, 0.85)
            warn:SetPoint("LEFT", crumb, "RIGHT", 10, 0)
            warn:SetText(string.format(L("held by '%s'"), (og and og.name) or "?"))
            local hit = CreateFrame("Frame", nil, row)
            hit:SetAllPoints(warn)
            hit:EnableMouse(true)
            hit:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self,
                    L("A spec override owns this setting, so this conditional value never applies outside an editing session. Remove the spec override to let it through."))
            end)
            hit:SetScript("OnLeave", function()
                EllesmereUI.HideWidgetTooltip()
            end)
        end
    end

    local rm, rmBrd = MakeBtn("Remove Override", -20, 116)
    rm:SetScript("OnEnter", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 0.35, 0.35, 0.8) end end)
    rm:SetScript("OnLeave", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 1, 1, 0.22) end end)
    rm:SetScript("OnClick", function()
        EllesmereUI:ShowConfirmPopup({
            title = isCondEntry and L("Remove Conditional Override") or L("Remove Spec Override"),
            message = string.format(L("Remove '%s'? The setting keeps its current live value."), entry.label or "?"),
            confirmText = L("Remove"),
            cancelText = L("Cancel"),
            onConfirm = function()
                local st = isCondEntry and Cond.GetStore() or GetStore()
                if st then
                    for i, e in ipairs(st) do
                        if e == entry then table.remove(st, i); break end
                    end
                end
                if isCondEntry then Cond.RebuildIndex() else RebuildFKeyIndex() end
                RequestGoldWalk()
                EllesmereUI:RefreshPage(true)
            end,
        })
    end)

    local go, goBrd = MakeBtn("Go to Setting", -144, 104)
    go:SetScript("OnEnter", function() if goBrd and goBrd.SetColor then goBrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8) end end)
    go:SetScript("OnLeave", function() if goBrd and goBrd.SetColor then goBrd:SetColor(1, 1, 1, 0.22) end end)
    go:SetScript("OnClick", function()
        local mod = entry.module
        if not mod then
            for fkey in pairs(entry.values and entry.values.default or {}) do
                mod = SplitFKey(fkey)
                break
            end
        end
        if mod and EllesmereUI:GetModuleTitle(mod) then
            EllesmereUI:SelectModule(mod)
            if entry.page and EllesmereUI.SelectPage then
                EllesmereUI:SelectPage(entry.page)
            end
        end
    end)

    return row, 38
end

-- Row for one STRANDED per-spec value (see SpecStrandedOnEntry): shows the spec
-- and the setting it silently overrides, with a per-value Remove returning the
-- spec to the shared default. Removal is the only possible action -- no editing
-- session can reach them.
local function BuildStrandedRow(parent, y, entry, specID)
    local CreateFrame = EllesmereUI._Pool.CreateFrame
    local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

    local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
    name:SetPoint("LEFT", row, "LEFT", 20, 0)
    name:SetText(SpecName(specID))

    local owner = GroupById(entry.group)
    local crumb = EllesmereUI.MakeFont(row, 11, nil, 1, 1, 1, 0.3)
    crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
    crumb:SetText(string.format("%s  -  %s", L(entry.label or "?"),
        string.format(L("held by '%s'"), (owner and owner.name) or "?")))

    local rm = CreateFrame("Button", nil, row)
    rm:SetSize(116, 22)
    rm:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    EllesmereUI.SolidTex(rm, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local rmBrd = EllesmereUI.MakeBorder(rm, 1, 1, 1, 0.22)
    local rmLbl = EllesmereUI.MakeFont(rm, 11, nil, 1, 1, 1, 0.8)
    rmLbl:SetPoint("CENTER")
    rmLbl:SetText(L("Remove Override"))
    rm:SetScript("OnEnter", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 0.35, 0.35, 0.8) end end)
    rm:SetScript("OnLeave", function() if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 1, 1, 0.22) end end)
    rm:SetScript("OnClick", function()
        EllesmereUI:ShowConfirmPopup({
            title = L("Remove Stranded Override"),
            message = string.format(L("Remove the stranded '%s' override for %s? The spec returns to the shared default."),
                entry.label or "?", SpecName(specID)),
            confirmText = L("Remove"),
            cancelText = L("Cancel"),
            onConfirm = function()
                entry.values[specID] = nil
                EllesmereUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
                RequestGoldWalk()
                EllesmereUI:RefreshPage(true)
            end,
        })
    end)

    return row, 38
end

-- Prunes entries whose owning group no longer exists. Entries with no group at
-- all (legacy captures) are kept.
local function PruneOrphanEntries()
    local store = GetStore()
    if not store then return false end
    local removed = false
    local touched
    -- Restore an entry's recorded defaults live before dropping it as an ORPHAN: the
    -- dead group's values may be the ones currently applied, and with the entry gone
    -- nothing would ever write the default back (residue becomes the permanent
    -- baseline). Loaded, non-blacklisted scalar paths only; excluded-context drops
    -- deliberately keep live as-is (those settings left the system).
    local function RestoreEntryDefaults(e)
        if not (e.values and e.values.default) then return end
        for fkey, def in pairs(e.values.default) do
            if not BlacklistedFKey(fkey) and FKeyLoaded(fkey) then
                local v = def
                if v == NIL_SENT then v = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues.
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
    for i = #store, 1, -1 do
        local e = store[i]
        local drop = false
        if e.group ~= nil and not GroupById(e.group) then
            -- Dangling creator id: retag to a surviving holder like the delete
            -- flow does; drop (with live restore) only when no group holds
            -- values on the entry.
            local holder = EntryHolderGroup(e)
            if holder then
                e.group = holder.id
                removed = true
            else
                RestoreEntryDefaults(e)
                drop = true
            end
        end
        -- Entries captured in contexts later excluded from the system (module-,
        -- page-, or section-scoped) drop wholesale so they stop applying and
        -- vanish from the management list.
        if not drop and e.module then
            local ex = EXCLUDED_CONTEXTS[e.module]
            if ex == true then
                drop = true
            elseif type(ex) == "table" and e.page then
                local pex = ex[e.page]
                if pex == true then
                    drop = true
                elseif type(pex) == "table" and e.section and pex[e.section] then
                    drop = true
                end
            end
        end
        -- Strip paths into blacklisted folders: legacy entries can carry
        -- Cooldown Manager paths, and applying those re-injects frozen per-spec
        -- spell data (cross-spec spells flashing on bars). An entry left with
        -- no paths is dropped entirely.
        if not drop and e.values and e.values.default then
            local stripped = false
            for fkey in pairs(e.values.default) do
                if BlacklistedFKey(fkey) then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then m[fkey] = nil end
                    end
                    stripped = true
                end
            end
            if stripped then
                removed = true
                if not next(e.values.default) then drop = true end
            end
        end
        if drop then
            table.remove(store, i)
            removed = true
        end
    end
    -- Self-heal: on group-created entries, per-spec value maps for specs in NO group
    -- are phantoms (leftovers from membership edits / group deletes). They silently
    -- pin the spec off the defaults and are invisible in the management list (buckets
    -- show creator + member deviations only). Legacy pre-group entries (group == nil)
    -- keep their per-spec values: that is their model.
    local healed = false
    for _, e in ipairs(store) do
        if e.group ~= nil and e.values then
            for k in pairs(e.values) do
                if type(k) == "number" and not SpecInAnyGroup(k) then
                    e.values[k] = nil
                    healed = true
                end
            end
        end
    end
    if healed then
        removed = true
        -- Put the healed specs' live data back on the shared defaults. DEFERRED one
        -- frame: this runs from PLAYER_LOGIN and from inside the list-page build,
        -- where a synchronous Apply fires module refreshers (and can re-enter a page
        -- rebuild) mid-build. Safe to defer: PruneRedundantValues' live-guard refuses
        -- to GC a recorded default while live still differs, so nothing is lost.
        C_Timer.After(0, function()
            EllesmereUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
        end)
    end
    if touched then RunRefreshers(touched) end
    if removed then
        RebuildFKeyIndex()
        RequestGoldWalk()
    end
    return removed
end

--- Generic fork-management row (name + gold crumb + Delete behind a confirm
--- popup). opts: crumb, title, message ('%s' = group name), removeFn. Defaults
--- describe the unlock-layout fork.
local function BuildUnlockLayoutRow(parent, y, g, opts)
    opts = opts or {}
    local crumbText = opts.crumb or "Custom Unlock Mode"
    local titleText = opts.title or "Delete Custom Unlock Mode"
    local msgText = opts.message
        or "Delete the custom unlock mode for '%s'? Its specs return to your default unlock mode layout."
    local removeFn = opts.removeFn or EllesmereUI.SpecOverrides_RemoveUnlockLayout

    local CreateFrame = EllesmereUI._Pool.CreateFrame
    local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

    local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
    name:SetPoint("LEFT", row, "LEFT", 20, 0)
    name:SetText(g.name or "?")

    local crumb = EllesmereUI.MakeFont(row, 11, nil, GOLD_R, GOLD_G, GOLD_B, 0.75)
    crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
    crumb:SetText(L(crumbText))

    local b = CreateFrame("Button", nil, row)
    b:SetSize(116, 22)
    b:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    EllesmereUI.SolidTex(b, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.22)
    local lbl = EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1, 0.8)
    lbl:SetPoint("CENTER")
    lbl:SetText(L("Delete"))
    b:SetScript("OnEnter", function() if brd and brd.SetColor then brd:SetColor(1, 0.35, 0.35, 0.8) end end)
    b:SetScript("OnLeave", function() if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end end)
    b:SetScript("OnClick", function()
        EllesmereUI:ShowConfirmPopup({
            title = L(titleText),
            message = string.format(L(msgText), g.name or "?"),
            confirmText = L("Delete"),
            cancelText = L("Cancel"),
            onConfirm = function()
                if removeFn then removeFn(g.id) end
                EllesmereUI:RefreshPage(true)
            end,
        })
    end)

    -- Edit: opens the fork's OWN editing session, then jumps to its manager page.
    -- The session is load-bearing: the manager page prelude engages the fork only
    -- while a session is open, and Cond.ExitEdit is the sole release path, so the
    -- swap is never engaged directly here.
    if opts.editKind and opts.editPage then
        local e = CreateFrame("Button", nil, row)
        e:SetSize(116, 22)
        e:SetPoint("RIGHT", b, "LEFT", -8, 0)
        EllesmereUI.SolidTex(e, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local ebrd = EllesmereUI.MakeBorder(e, 1, 1, 1, 0.22)
        local elbl = EllesmereUI.MakeFont(e, 11, nil, 1, 1, 1, 0.8)
        elbl:SetPoint("CENTER")
        elbl:SetText(L("Edit"))
        e:SetScript("OnEnter", function() if ebrd and ebrd.SetColor then ebrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8) end end)
        e:SetScript("OnLeave", function() if ebrd and ebrd.SetColor then ebrd:SetColor(1, 1, 1, 0.22) end end)
        e:SetScript("OnClick", function()
            -- Raid Frames must be registered to navigate to (same gate as the
            -- entry rows' Go to Setting).
            if not (EllesmereUI:GetModuleTitle("EllesmereUIRaidFrames")) then return end
            -- Both entry points refuse (own popup) when another fork holds the
            -- manager page; only navigate once the session actually opened.
            if opts.editKind == "cond" then
                if not Cond.EnterEdit then return end
                Cond.EnterEdit(g)
                if Cond._edit ~= g then return end
            else
                if not EnterGroupEdit then return end
                EnterGroupEdit(g)
                if _editGroup ~= g then return end
            end
            EllesmereUI:SelectModule("EllesmereUIRaidFrames")
            EllesmereUI:SelectPage(opts.editPage)
        end)
    end

    return row, 38
end

--- Row presets for the Buff Manager forks (spec + conditional variants).
local BM_ROW_SPEC = {
    crumb = "Custom Buff Manager",
    title = "Delete Custom Buff Manager",
    message = "Delete the custom Buff Manager for '%s'? Its specs return to your default Buff Manager.",
    removeFn = function(gid) EllesmereUI.SpecOverrides_RemoveBmLayout(gid) end,
    editKind = "spec", editPage = "Buff Manager",
}
local BM_ROW_COND = {
    crumb = "Custom Buff Manager",
    title = "Delete Custom Buff Manager",
    message = "Delete the custom Buff Manager for '%s'? Its conditions return to your default Buff Manager.",
    removeFn = function(gid) EllesmereUI.Conditions_RemoveBmLayout(gid) end,
    editKind = "cond", editPage = "Buff Manager",
}

--- Row presets for the Debuff Manager forks (spec + conditional variants).
local DM_ROW_SPEC = {
    crumb = "Custom Debuff Manager",
    title = "Delete Custom Debuff Manager",
    message = "Delete the custom Debuff Manager for '%s'? Its specs return to your default Debuff Manager.",
    removeFn = function(gid) EllesmereUI.SpecOverrides_RemoveDmLayout(gid) end,
    editKind = "spec", editPage = "Debuff Manager",
}
local DM_ROW_COND = {
    crumb = "Custom Debuff Manager",
    title = "Delete Custom Debuff Manager",
    message = "Delete the custom Debuff Manager for '%s'? Its conditions return to your default Debuff Manager.",
    removeFn = function(gid) EllesmereUI.Conditions_RemoveDmLayout(gid) end,
    editKind = "cond", editPage = "Debuff Manager",
}

-------------------------------------------------------------------------------
--  Promote Override to Profile (one-shot rescue)
--
--  Makes the selected spec group's stored state the profile's own: captured values
--  become the shared defaults, its unlock mode and Buff Manager forks (where
--  present) become the baseline layouts, then EVERY spec override group on the
--  profile is deleted. For profiles accidentally built entirely inside an override
--  group. Purely additive: only existing writers repaint live, and the end state is
--  indistinguishable from a profile that never had spec overrides. Conditional
--  overrides are untouched and ride the new baseline.
-------------------------------------------------------------------------------
local _promoteSelGid = nil   -- list-page dropdown selection (runtime only)

local function PromoteGroupToProfile(g)
    if not g or not g.specs or #g.specs == 0 then return end
    -- Combat re-check (the typed-confirm popup can sit open while combat starts): the
    -- tail must flush secure-frame repositioning synchronously before the reload, which
    -- lockdown blocks. Nothing is written yet, so refusing here is a clean abort.
    if InCombatLockdown() then
        EllesmereUI:ShowConfirmPopup({
            title = L("In Combat"),
            message = L("Promoting an override reloads the UI and cannot run in combat. Leave combat and try again."),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    -- The reload is asked for first in the click (RequestReload); the client
    -- reloads only once this function has finished, so every step below lands.
    EllesmereUI.RequestReload()
    -- Bank any open session and leave the Default view so the stores hold the
    -- freshest edits and live holds canonical spec values.
    EllesmereUI.SpecOverrides_CloseEditSessions()

    -- 1) VALUES: the group's stored values become the recorded defaults.
    --    Resolution mirrors WriteGroupValues (first member spec's map, per-fkey
    --    fallback to the current default), so the promoted baseline is exactly
    --    what "editing as" the group shows.
    local store = GetStore()
    local seed = g.specs[1]
    if store then
        for _, entry in ipairs(store) do
            local def = entry.values and entry.values.default
            local m = entry.values and entry.values[seed]
            if def and m then
                for fkey in pairs(def) do
                    local v = m[fkey]
                    -- Blacklisted paths never apply; match-owned size keys belong to
                    -- the match engine (the layer promote below carries the real
                    -- geometry). NIL_SENT markers promote as-is: the default writer
                    -- decodes them behind its own nil-poison guard.
                    if v ~= nil and type(v) ~= "table"
                       and not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey) then
                        def[fkey] = v
                    end
                end
            end
        end
    end
    -- Write the promoted defaults live while the entries still exist (the store
    -- is wiped below and nothing could repaint them afterwards). Writes are
    -- value-equal no-ops for specs already on the group's values.
    WriteDefaultValues()

    -- 2) UNLOCK LAYOUT: the group's fork becomes the baseline, resolved as
    --    ApplyLayer resolves a live fork: links wholesale, position stores with
    --    per-key baseline gap-fill, grow keys under the authority rule, elems
    --    overlaid onto the baseline's. All copies -- the new baseline shares no
    --    tables with the wiped fork buckets.
    local s = GetUnlockStore()
    if s then
        local layer = s.layouts and s.layouts[g.id]
        local base = s.baselineLayout
        if layer then
            local nb = { anchors = {}, widthMatch = {}, heightMatch = {},
                         cdmGrow = {}, abGrow = {}, elems = {} }
            for k, v in pairs(layer.anchors or {}) do
                if not IsTBBChildKey(k) then nb.anchors[k] = DeepCopy(v) end
            end
            for k, v in pairs(layer.widthMatch or {}) do
                if not IsTBBChildKey(k) then nb.widthMatch[k] = v end
            end
            for k, v in pairs(layer.heightMatch or {}) do
                if not IsTBBChildKey(k) then nb.heightMatch[k] = v end
            end
            -- Match extras ride with the links (a fork without them promotes none).
            nb.widthMatchExtra, nb.heightMatchExtra = {}, {}
            for k, v in pairs(layer.widthMatchExtra or {}) do
                if not IsTBBChildKey(k) then nb.widthMatchExtra[k] = v end
            end
            for k, v in pairs(layer.heightMatchExtra or {}) do
                if not IsTBBChildKey(k) then nb.heightMatchExtra[k] = v end
            end
            local function MergePos(lp, bp)
                local out = lp and DeepCopy(lp) or (bp and DeepCopy(bp) or nil)
                if lp and bp then
                    for k, v in pairs(bp) do
                        if out[k] == nil then out[k] = DeepCopy(v) end
                    end
                end
                return out
            end
            nb.cdmPos = MergePos(layer.cdmPos, base and base.cdmPos)
            nb.abPos = MergePos(layer.abPos, base and base.abPos)
            -- A grow store is authoritative only when its layer was harvested
            -- with the owning module loaded (pos store present); effective =
            -- layer's grow, else the baseline's.
            local function MergeGrow(out, lAuth, lg, bAuth, bg)
                if bAuth and bg then
                    for k, v in pairs(bg) do out[k] = v end
                end
                if lAuth and lg then
                    for k, v in pairs(lg) do out[k] = v end
                end
            end
            MergeGrow(nb.cdmGrow, layer.cdmPos ~= nil, layer.cdmGrow,
                      base and base.cdmPos ~= nil, base and base.cdmGrow)
            MergeGrow(nb.abGrow, layer.abPos ~= nil, layer.abGrow,
                      base and base.abPos ~= nil, base and base.abGrow)
            if base and base.elems then
                for k, e in pairs(base.elems) do
                    if not LayerSkipsKey(k) then nb.elems[k] = DeepCopy(e) end
                end
            end
            for k, e in pairs(layer.elems or {}) do
                if not LayerSkipsKey(k) then nb.elems[k] = DeepCopy(e) end
            end
            s.baselineLayout = nb
        end
        wipe(s.layouts)
        s.active = nil
    end

    -- 3) BUFF MANAGER: BM layers are complete wholesale subtrees; the fork
    --    (when present) becomes the baseline verbatim.
    local bs = GetBmStore()
    if bs then
        local bl = bs.layouts and bs.layouts[g.id]
        if bl then bs.baselineLayout = DeepCopy(bl) end
        wipe(bs.layouts)
        bs.active = nil
    end

    -- 3b) DEBUFF MANAGER: same wholesale promote as the BM store.
    local ds = GetDmStore()
    if ds then
        local dl = ds.layouts and ds.layouts[g.id]
        if dl then ds.baselineLayout = DeepCopy(dl) end
        wipe(ds.layouts)
        ds.active = nil
    end

    -- 4) DELETE the spec override system: every group and entry. The promoted
    --    values are already live and the promoted layouts are the baselines,
    --    so from here the profile simply IS the override.
    local groups = GetGroups()
    if groups then wipe(groups) end
    if store then wipe(store) end
    RebuildFKeyIndex()

    -- 5) CONVERGE live onto the new baselines, forced: with the groups gone the
    --    resolver wants the baseline (or a live conditional fork over it), and
    --    the same-layer early-out would skip the repaint for a spec that was
    --    NOT on the promoted fork. Where live already matches, writes are
    --    value-equal and the flush's equality guards no-op. pcall like the
    --    import converge: an error must not strand the cleanup half-done.
    local sid = CurrentSpecID()
    if sid then
        pcall(EllesmereUI.SpecOverrides_ApplyUnlock, sid, true)
        pcall(EllesmereUI.SpecOverrides_ApplyBm, sid, true)
        pcall(EllesmereUI.SpecOverrides_ApplyDm, sid, true)
    end
    -- 6) FLUSH before the reload asked for at the top. The converge's element
    --    writes are DEFERRED (FlushUnlock) and reloading inside that window
    --    strands them: the logout bank keeps the intent in the bucket, but the
    --    post-reload login early-outs on the nil active pointer and never
    --    paints it back into module DBs. Flush synchronously (out of combat by
    --    the gate above); the reload then rebuilds every runtime cache, ticker
    --    and session structure clean.
    pcall(EllesmereUI.SpecOverrides_FlushUnlock)
end

--- Page builder for the "Spec Overrides" tab (called from the Profiles &
--- Presets module registration).
function EllesmereUI.SpecOverrides_BuildListPage(parent, startY)
    local CreateFrame = EllesmereUI._Pool.CreateFrame
    local W = EllesmereUI.Widgets
    local y = startY
    -- Skip during a hidden search pre-build: the page is only indexed for its
    -- static labels, and pruning mutates saved profile data -- not something a
    -- read-only indexing pass may do as a side effect.
    if not EllesmereUI._prebuilding then PruneOrphanEntries() end
    local store = GetStore()
    local groups = GetGroups() or {}
    local us = GetUnlockStore()
    local layoutGroups
    if us then
        for _, g in ipairs(groups) do
            if us.layouts[g.id] ~= nil then
                layoutGroups = layoutGroups or {}
                layoutGroups[#layoutGroups + 1] = g
            end
        end
    end
    local bs = GetBmStore()
    local bmGroups
    if bs then
        for _, g in ipairs(groups) do
            if bs.layouts[g.id] ~= nil then
                bmGroups = bmGroups or {}
                bmGroups[#bmGroups + 1] = g
            end
        end
    end
    local dds = GetDmStore()
    local dmGroups
    if dds then
        for _, g in ipairs(groups) do
            if dds.layouts[g.id] ~= nil then
                dmGroups = dmGroups or {}
                dmGroups[#dmGroups + 1] = g
            end
        end
    end

    if (not store or #store == 0) and not layoutGroups and not bmGroups and not dmGroups then
        local _, h = W:SectionHeader(parent, L("Spec Overrides"), y);  y = y - h
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = CreateFrame("Frame", nil, parent)
        hint:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 80)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
        local fs = EllesmereUI.MakeFont(hint, 13, nil, 1, 1, 1, 0.5)
        fs:SetPoint("TOPLEFT", hint, "TOPLEFT", 20, -10)
        fs:SetWidth(hint:GetWidth() - 40)
        fs:SetJustifyH("LEFT")
        fs:SetText(L("No spec overrides yet. Click the spec glyph next to the module search bar, select or create a spec group, and any setting you change while editing as that group is saved here."))
        y = y - 90
        return -y + 40
    end

    -- TOP section: custom unlock modes (one whole-layout fork per group).
    if layoutGroups then
        local _, hh = W:SectionHeader(parent, "Custom Unlock Modes", y);  y = y - hh
        for _, g in ipairs(layoutGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g)
            y = y - rh
        end
    end

    -- Custom Buff Manager forks (Raid Frames Buff Manager tab).
    if bmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Buff Managers", y);  y = y - hh
        for _, g in ipairs(bmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, BM_ROW_SPEC)
            y = y - rh
        end
    end

    -- Custom Debuff Manager forks (Raid Frames Debuff Manager tab).
    if dmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Debuff Managers", y);  y = y - hh
        for _, g in ipairs(dmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, DM_ROW_SPEC)
            y = y - rh
        end
    end

    -- Bucket entries under EVERY group that customizes them: a slot is ONE
    -- shared entry across groups (a second group's edits bank into the first
    -- group's entry), so an entry lists under its creating group AND under any
    -- group whose member specs store a value differing from the entry's shared
    -- default. Derived live -- no stored ownership metadata.
    local function GroupCustomizes(entry, g)
        if entry.group == g.id then return true end
        local def = entry.values and entry.values.default
        if not def then return false end
        for _, sid in ipairs(g.specs or {}) do
            local m = entry.values[sid]
            if m then
                for fkey, dv in pairs(def) do
                    if m[fkey] ~= nil and m[fkey] ~= dv then return true end
                end
            end
        end
        return false
    end
    local byGroup, ungrouped = {}, {}
    for _, entry in ipairs(store or {}) do
        local listed = false
        for _, g in ipairs(groups) do
            if GroupCustomizes(entry, g) then
                byGroup[g.id] = byGroup[g.id] or {}
                table.insert(byGroup[g.id], entry)
                listed = true
            end
        end
        if not listed then ungrouped[#ungrouped + 1] = entry end
    end

    for _, g in ipairs(groups) do
        local list = byGroup[g.id]
        if list and #list > 0 then
            local _, hh = W:SectionHeader(parent, g.name or "?", y);  y = y - hh
            for _, entry in ipairs(list) do
                local _, rh = BuildListRow(parent, y, entry)
                y = y - rh
            end
        end
    end
    if #ungrouped > 0 then
        local _, hh = W:SectionHeader(parent, "Ungrouped", y);  y = y - hh
        for _, entry in ipairs(ungrouped) do
            local _, rh = BuildListRow(parent, y, entry)
            y = y - rh
        end
    end

    -- STRANDED values: per-spec overrides no editing session can reach (see
    -- SpecStrandedOnEntry). They apply at every boundary but are invisible in
    -- the group buckets above, so each gets a row with a per-value Remove.
    local stranded
    for _, entry in ipairs(store or {}) do
        if entry.values then
            for k in pairs(entry.values) do
                if type(k) == "number" and SpecStrandedOnEntry(entry, k) then
                    stranded = stranded or {}
                    stranded[#stranded + 1] = { entry = entry, spec = k }
                end
            end
        end
    end
    if stranded then
        table.sort(stranded, function(a, b) return a.spec < b.spec end)
        local _, hh = W:SectionHeader(parent, "Stranded Overrides", y);  y = y - hh
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = EllesmereUI.MakeFont(parent, 11, nil, 1, 1, 1, 0.45)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD + 20, y)
        hint:SetWidth(parent:GetWidth() - CONTENT_PAD * 2 - 40)
        hint:SetJustifyH("LEFT")
        hint:SetText(L("These specs hold override values that no group's editing mode can reach anymore (left behind by membership changes). They still apply. Remove one to return that spec to the shared default."))
        y = y - 34
        for _, s in ipairs(stranded) do
            local _, rh = BuildStrandedRow(parent, y, s.entry, s.spec)
            y = y - rh
        end
    end

    -- DANGER ZONE: one-shot "this override IS my profile" rescue. Rendered only
    -- while a group exists to promote.
    if #groups > 0 then
        y = y - 14
        local _, hh = W:SectionHeader(parent, "Promote Override to Profile", y);  y = y - hh
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = EllesmereUI.MakeFont(parent, 11, nil, 1, 1, 1, 0.45)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD + 20, y)
        hint:SetWidth(parent:GetWidth() - CONTENT_PAD * 2 - 40)
        hint:SetJustifyH("LEFT")
        hint:SetText(L("Rescue tool for a profile built inside an override: the selected group's settings and layouts become this profile's own baseline, then ALL spec override groups are deleted. Conditional overrides are not affected."))
        y = y - 44
        local ddValues, ddOrder = {}, {}
        for _, gg in ipairs(groups) do
            ddValues[gg.id] = gg.name or ("Group " .. gg.id)
            ddOrder[#ddOrder + 1] = gg.id
        end
        if not _promoteSelGid or not GroupById(_promoteSelGid) then
            _promoteSelGid = groups[1].id
        end
        local _, dh = W:WideDropdown(parent, "Override to Promote", y, ddValues,
            function() return _promoteSelGid end,
            function(v) _promoteSelGid = v end,
            ddOrder, 300)
        y = y - dh
        y = y - 6
        local BTN_W, BTN_H = 300, 38
        local lerp = EllesmereUI.lerp
        local DARK_BG = EllesmereUI.DARK_BG
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", parent, "TOP", 0, y)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        btn:SetAlpha(0.85)
        local brd = EllesmereUI.MakeBorder(btn, 0.8, 0.2, 0.2, 0.5, EllesmereUI.PanelPP)
        local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bg:SetAllPoints()
        local lbl = EllesmereUI.MakeFont(btn, 13, nil, 0.9, 0.3, 0.3)
        lbl:SetAlpha(0.7)
        lbl:SetPoint("CENTER")
        lbl:SetText(L("Promote Override & Delete ALL Overrides"))
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                lbl:SetTextColor(lerp(0.9, 1, t), lerp(0.3, 0.35, t), lerp(0.3, 0.35, t), lerp(0.7, 1, t))
                brd:SetColor(0.8, 0.2, 0.2, lerp(0.5, 0.8, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        end
        btn:SetScript("OnClick", function()
            local pg = GroupById(_promoteSelGid)
            if not pg then return end
            -- The promote ends in a synchronous flush + ReloadUI, neither
            -- of which belongs in combat lockdown.
            if InCombatLockdown() then
                EllesmereUI:ShowConfirmPopup({
                    title = L("In Combat"),
                    message = L("Promoting an override reloads the UI and cannot run in combat. Leave combat and try again."),
                    confirmText = L("OK"),
                    hideCancel = true,
                })
                return
            end
            -- Modules with captured overrides must be loaded: promoted
            -- values for an unloaded module cannot be written live, and the
            -- store they lived in is deleted at the end -- silent loss.
            local missingSet, missingList
            for _, entry in ipairs(GetStore() or {}) do
                for fkey in pairs(entry.values and entry.values.default or {}) do
                    if not BlacklistedFKey(fkey) and not FKeyLoaded(fkey) then
                        local folder = SplitFKey(fkey)
                        if folder and not (missingSet and missingSet[folder]) then
                            missingSet = missingSet or {}
                            missingSet[folder] = true
                            missingList = missingList or {}
                            missingList[#missingList + 1] = folder:gsub("^EllesmereUI", "")
                        end
                    end
                end
            end
            if missingList then
                EllesmereUI:ShowConfirmPopup({
                    title = L("Enable Modules First"),
                    message = string.format(L("Captured overrides reference disabled modules (%s). Enable them and reload before promoting, or those settings would be lost."), table.concat(missingList, ", ")),
                    confirmText = L("OK"),
                    hideCancel = true,
                })
                return
            end
            EllesmereUI:ShowConfirmPopup({
                title = L("Promote Override to Profile"),
                message = string.format(L("This permanently overwrites this profile's settings with the override '%s': its captured settings and its custom Unlock Mode and Buff Manager layouts (where present) become the profile's own baseline for every spec. ALL spec override groups on this profile are then deleted and the UI reloads. Conditional overrides are not affected."), pg.name or "?"),
                disclaimer = L("This cannot be undone. Consider exporting this profile as a backup first."),
                typeToConfirm = "Confirm",
                confirmText = L("Promote & Reload"),
                cancelText = L("Cancel"),
                onConfirm = function() PromoteGroupToProfile(pg) end,
            })
        end)
        y = y - BTN_H - 10
    end

    return -y + 40
end

--- Page builder for the "Conditional Overrides" tab (mirror of the spec tab).
function EllesmereUI.Conditions_BuildListPage(parent, startY)
    local CreateFrame = EllesmereUI._Pool.CreateFrame
    local W = EllesmereUI.Widgets
    local y = startY
    Cond.PruneEntries()
    local store = Cond.GetStore()
    local groups = EllesmereUI.Conditions_GetGroups() or {}
    local cs = Cond.GetUnlockStore()

    local layoutGroups
    if cs then
        for _, g in ipairs(groups) do
            if cs.layouts[g.id] ~= nil then
                layoutGroups = layoutGroups or {}
                layoutGroups[#layoutGroups + 1] = g
            end
        end
    end
    local cbs = GetCondBmStore()
    local bmGroups
    if cbs then
        for _, g in ipairs(groups) do
            if cbs.layouts[g.id] ~= nil then
                bmGroups = bmGroups or {}
                bmGroups[#bmGroups + 1] = g
            end
        end
    end
    local cds = GetCondDmStore()
    local dmGroups
    if cds then
        for _, g in ipairs(groups) do
            if cds.layouts[g.id] ~= nil then
                dmGroups = dmGroups or {}
                dmGroups[#dmGroups + 1] = g
            end
        end
    end

    if (not store or #store == 0) and not layoutGroups and not bmGroups and not dmGroups and #groups == 0 then
        local _, h = W:SectionHeader(parent, L("Conditional Overrides"), y);  y = y - h
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
        local hint = CreateFrame("Frame", nil, parent)
        hint:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 80)
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
        local fs = EllesmereUI.MakeFont(hint, 13, nil, 1, 1, 1, 0.5)
        fs:SetPoint("TOPLEFT", hint, "TOPLEFT", 20, -10)
        fs:SetWidth(hint:GetWidth() - 40)
        fs:SetJustifyH("LEFT")
        fs:SetText(L("No conditional overrides yet. Click the Conditional Overrides button next to the module search bar and create a conditional group (Dungeon, Raid, Keybind...). Spec overrides always take precedence over conditionals."))
        y = y - 90
        return -y + 40
    end

    -- TOP section: custom unlock modes (one whole-layout fork per group).
    if layoutGroups then
        local _, hh = W:SectionHeader(parent, "Custom Unlock Modes", y);  y = y - hh
        for _, g in ipairs(layoutGroups) do
            local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 40
            local row = CreateFrame("Frame", nil, parent)
            row:SetSize(parent:GetWidth() - CONTENT_PAD * 2, 36)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
            local name = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1, 0.9)
            name:SetPoint("LEFT", row, "LEFT", 20, 0)
            name:SetText(g.name or "?")
            local crumb = EllesmereUI.MakeFont(row, 11, nil, GOLD_R, GOLD_G, GOLD_B, 0.75)
            crumb:SetPoint("LEFT", name, "RIGHT", 10, 0)
            crumb:SetText(L("Custom Unlock Mode"))
            local b = CreateFrame("Button", nil, row)
            b:SetSize(116, 22)
            b:SetPoint("RIGHT", row, "RIGHT", -20, 0)
            EllesmereUI.SolidTex(b, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.22)
            local lbl = EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1, 0.8)
            lbl:SetPoint("CENTER")
            lbl:SetText(L("Delete"))
            b:SetScript("OnEnter", function() if brd and brd.SetColor then brd:SetColor(1, 0.35, 0.35, 0.8) end end)
            b:SetScript("OnLeave", function() if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end end)
            local gid = g.id
            local gname = g.name or "?"
            b:SetScript("OnClick", function()
                EllesmereUI:ShowConfirmPopup({
                    title = L("Delete Custom Unlock Mode"),
                    message = string.format(
                        L("Delete the custom unlock mode for '%s'? Its conditions return to your default unlock mode layout."),
                        gname),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        EllesmereUI.Conditions_RemoveUnlockLayout(gid)
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end)
            y = y - 38
        end
    end

    -- Custom Buff Manager forks (Raid Frames Buff Manager tab).
    if bmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Buff Managers", y);  y = y - hh
        for _, g in ipairs(bmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, BM_ROW_COND)
            y = y - rh
        end
    end

    -- Custom Debuff Manager forks (Raid Frames Debuff Manager tab).
    if dmGroups then
        local _, hh = W:SectionHeader(parent, "Custom Debuff Managers", y);  y = y - hh
        for _, g in ipairs(dmGroups) do
            local _, rh = BuildUnlockLayoutRow(parent, y, g, DM_ROW_COND)
            y = y - rh
        end
    end

    -- Captured value entries bucketed under EVERY conditional group that
    -- customizes them (creator, plus any group whose stored map differs from
    -- the entry's shared default -- same shared-slot rule as the spec list).
    for _, g in ipairs(groups) do
        local list = {}
        for _, entry in ipairs(store or {}) do
            local owns = entry.group == g.id
            if not owns and entry.values and entry.values.default then
                local m = entry.values[g.id]
                if m then
                    for fkey, dv in pairs(entry.values.default) do
                        if m[fkey] ~= nil and m[fkey] ~= dv then owns = true; break end
                    end
                end
            end
            if owns then list[#list + 1] = entry end
        end
        if #list > 0 then
            local _, hh = W:SectionHeader(parent, g.name or "?", y);  y = y - hh
            for _, entry in ipairs(list) do
                local _, rh = BuildListRow(parent, y, entry)
                y = y - rh
            end
        end
    end

    return -y + 40
end

I.PruneOrphanEntries = PruneOrphanEntries
I.broken = false
