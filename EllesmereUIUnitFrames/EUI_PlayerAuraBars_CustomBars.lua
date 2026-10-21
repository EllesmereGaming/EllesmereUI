if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_CustomBars.lua
--
--  The custom bar engine: state, position, unlock registration and
--  the reload of one bar or of all of them.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local BuffBarChain, PAB, BuffCandidateExtras = I.BuffBarChain, I.PAB, I.BuffCandidateExtras
local BuildStyle, DebuffCandidateExtras = I.BuildStyle, I.DebuffCandidateExtras
local ResolveSortDirection, ResolveSortMethod = I.ResolveSortDirection, I.ResolveSortMethod
local ApplyGroupConfig, BuildGroupLayout = I.ApplyGroupConfig, I.BuildGroupLayout
local DebuffChainFor, MergeCandidateFilters = I.DebuffChainFor, I.MergeCandidateFilters
local RetireContainer, ComputeGrid = I.RetireContainer, I.ComputeGrid
local ApplyContainerAnchorAndGrowth = I.ApplyContainerAnchorAndGrowth
local BarAnchorOffset, BuildContainerSpec = I.BarAnchorOffset, I.BuildContainerSpec
local DeferRestrictedApply, MapElementSettings = I.DeferRestrictedApply, I.MapElementSettings
local MoverStorePos, QueuePABRegenApply = I.MoverStorePos, I.QueuePABRegenApply
local RebaseBarPositionToCenter = I.RebaseBarPositionToCenter
local SetParentShownSafe, SnapBarPos = I.SetParentShownSafe, I.SnapBarPos
local SyncCancelCVar, SetAK = I.SyncCancelCVar, I.SetAK
local SetReloadAllCustomBars = I.SetReloadAllCustomBars

local AK -- EllesmereUI.AuraKit, resolved at first use (see SetAK)
I.AKSetters[#I.AKSetters + 1] = function(v) AK = v end
local PAB_MaybeRefreshPreview
I.previewRefreshSetters[#I.previewRefreshSetters + 1] = function(v) PAB_MaybeRefreshPreview = v end

-- Assigned at the end of this file and handed to the earlier files
-- (SetReloadAllCustomBars).
local ReloadAllCustomBars

-------------------------------------------------------------------------------
--  Custom bars -- engine wiring
--
--  Debuffs: one dedicated container per bar (own parent frame, own
--  AK.RequestContainer), groups declared through the SAME BuildChain/ApplyGroupConfig
--  path the default bars use, fed the bar itself as cfg (shares
--  DefaultBuffsCfg/DefaultDebuffsCfg's field shape).
--
--  Buffs: SpellID-based by design -- no class-token checkboxes, selection is
--  filters/direct spells only. Each bar's container holds ONE GROUP for its resolved
--  spell set (candidateFilters.includeSpellIDs, map shape {[id]=true}). NOT one
--  AK.AddAuraSlot per spellID: AK's flow layout only positions GROUP content, so
--  slots never get a real anchor (GetPoint(1) nil) and never render, even
--  unrestricted (see CreateBars). Flows through the SAME ComputeGrid/
--  BuildContainerSpec grid as every other bar. Unlike RaidFrames' Buff Manager (where
--  custom-spell content shares a container with structurally-stable groups, so only a
--  dedicated sub-container is released on a spell-list change), a custom buff bar's
--  container holds nothing else, so releasing and rebuilding the WHOLE container is
--  safe: no other shared group can lose frames.
--
--  bar.filters is resolved via ns.PAB_ResolveSpells, folded into the signature
--  alongside bar.spells, same as the default Buffs bar. bar.ownOnlySpells stays
--  UNCONSULTED -- own-only tracking is not implemented.
-------------------------------------------------------------------------------

local customBuffParents, customBuffContainers, customBuffSig, customBuffDeclared = {}, {}, {}, {}
local customDebuffParents, customDebuffContainers, customDebuffDeclared = {}, {}, {}

-- Which unlock-mode keys are currently registered for custom bars, so RegisterPABCustomUnlock
-- can retire keys for bars deleted since the last call.
local pabRegisteredCustomBuffKeys, pabRegisteredCustomDebuffKeys

local function CustomBuffStyleKey(barId) return "playerAuraBars_customBuff_" .. barId end
local function CustomDebuffStyleKey(barId) return "playerAuraBars_customDebuff_" .. barId end

-- Default anchor for a bar with no saved position yet: the SAME fixed spot (screen
-- center, slight upward offset) for every bar, deliberately not staggered by barId.
-- Only read as a fallback when bar.pos is absent, so a dragged bar keeps its saved
-- position and every untouched bar starts here.
local function DefaultCustomPos(barId)
    return { point = "CENTER", relPoint = "CENTER", x = 0, y = 80 }
end

-- Applies bar.pos (or the default) to a custom bar's parent frame. Same SetPoint
-- logic as ApplyBarPosition, kept separate only because custom bars key off bar.pos
-- on the bar object, not a fixed s[BarPositionKey] slot. Same anchored rule too.
local function ApplyCustomBarPosition(parent, bar, barId, isBuff, grid)
    local unlockKey = (isBuff and "PAB_CustomBuff_" or "PAB_CustomDebuff_") .. barId
    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
    if anchored and parent:GetNumPoints() > 0 and EllesmereUI.ReapplyOwnAnchor then
        EllesmereUI.ReapplyOwnAnchor(unlockKey)
        return
    end
    local pos = bar.pos or DefaultCustomPos(barId)
    local x, y = BarAnchorOffset(parent, bar, grid or ComputeGrid(isBuff, bar), pos)
    parent:ClearAllPoints()
    x, y = SnapBarPos(parent, pos.point, pos.relPoint or pos.point, x, y)
    parent:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, x, y)
    if bar.growDirection == "CENTER_HORIZONTAL" or bar.growDirection == "CENTER_VERTICAL" then
        local centeredPos = RebaseBarPositionToCenter(parent, pos)
        if bar.pos or centeredPos ~= pos then bar.pos = centeredPos end
    end
    if anchored and EllesmereUI.ReapplyOwnAnchor then EllesmereUI.ReapplyOwnAnchor(unlockKey) end
end

local function CustomBuffSpellSignature(spells)
    return table.concat(spells, ",")
end

-- Unlock-mode registration for custom bars: per-element schema from
-- RegisterPABUnlock, "dynamic list" shape from EUI_CDM_BuffBarUnlock.lua's
-- ns.RegisterTBBUnlockElements -- rebuild the FULL element list (every persisted
-- custom buff + debuff bar) and re-register it on every call rather than diffing
-- adds/removes. Cheap at PAB's bar counts, and a freshly-added bar just appears next
-- call with no separate registration path.
--
-- Unlike TBB (index-keyed, where deleting a mid-list bar reshuffles every higher key
-- and its links), PAB custom bars carry a permanent NextBarId that is never reused or
-- renumbered, so TBB's "never unregister, just hide" caution does not apply: a deleted
-- bar's key is retired for good and calling UnregisterUnlockElement is correct, not
-- lossy. Still noResize/noAnchorTarget for the same reason as the default bars.
local function RegisterPABCustomUnlock()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement

    local prevBuffKeys, prevDebuffKeys = pabRegisteredCustomBuffKeys, pabRegisteredCustomDebuffKeys
    pabRegisteredCustomBuffKeys, pabRegisteredCustomDebuffKeys = {}, {}

    local function MakeCustomBarElement(barId, bar, order, isBuff, parents)
        local key = (isBuff and "PAB_CustomBuff_" or "PAB_CustomDebuff_") .. barId
        MapElementSettings(key, isBuff and "buff" or "debuff", barId)
        return key, MK({
            key = key,
            label = "PAB: " .. (bar.name or (isBuff and "Buff Bar" or "Debuff Bar")),
            group = "Player Aura Bars",
            order = order,
            noResize = true,
            noAnchorTarget = true,
            isHidden = function()
                local b, bk
                if isBuff then b, bk = ns.PAB_GetCustomBuffBar(barId)
                else b, bk = ns.PAB_GetCustomDebuffBar(barId) end
                -- Bucket-scoped bars drop their mover on specs they do not
                -- render for (or were per-spec disabled on).
                return not (b and ns.PAB_BarActive(b, bk))
            end,
            getFrame = function() return parents[barId] end,
            getSize = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                if not b then return 32, 32 end
                local grid = ComputeGrid(isBuff, b)
                return grid.width, grid.height
            end,
            -- Visual <-> stored conversion, as in RegisterPABUnlock's MakeBarElement.
            savePos = function(_, point, relPoint, x, y)
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                if not b then return end
                b.pos = MoverStorePos(parents[barId], b, ComputeGrid(isBuff, b), b.pos, point, relPoint, x, y)
            end,
            loadPos = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                local pos = b and b.pos
                if not pos then return nil end
                local x, y = BarAnchorOffset(parents[barId], b, ComputeGrid(isBuff, b), pos)
                return { point = pos.point, relPoint = pos.relPoint, x = x, y = y }
            end,
            -- Raw stored position for spec-override layers, as in MakeBarElement.
            loadRawPosition = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                local pos = b and b.pos
                if not pos then return nil end
                return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y,
                    design = pos.design }
            end,
            saveRawPosition = function(_, p)
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                if not (b and p and p.point) then return end
                b.pos = { point = p.point, relPoint = p.relPoint or p.point,
                    x = p.x, y = p.y, design = p.design }
            end,
            clearPos = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                if b then b.pos = nil end
            end,
            applyPos = function()
                local b = isBuff and ns.PAB_GetCustomBuffBar(barId) or ns.PAB_GetCustomDebuffBar(barId)
                local parent = parents[barId]
                if b and parent then ApplyCustomBarPosition(parent, b, barId, isBuff) end
            end,
        })
    end

    local elements = {}
    local buffList = ns.PAB_CustomBuffBars()
    if buffList then
        for i = 1, #buffList do
            local bar = buffList[i]
            local key, el = MakeCustomBarElement(bar.id, bar, 702, true, customBuffParents)
            elements[#elements + 1] = el
            pabRegisteredCustomBuffKeys[key] = true
        end
    end
    local debuffList = ns.PAB_CustomDebuffBars()
    if debuffList then
        for i = 1, #debuffList do
            local bar = debuffList[i]
            local key, el = MakeCustomBarElement(bar.id, bar, 703, false, customDebuffParents)
            elements[#elements + 1] = el
            pabRegisteredCustomDebuffKeys[key] = true
        end
    end
    -- Editing-spec bucket bars register too (every bucket -- isHidden drops
    -- the mover on specs a bar doesn't render for).
    do
        local s = PAB()
        local st = s and s.pabSpecBars
        if st then
            for _, b in pairs(st) do
                local bl = b.buffBars
                if bl then
                    for i = 1, #bl do
                        local bar = bl[i]
                        local key, el = MakeCustomBarElement(bar.id, bar, 702, true, customBuffParents)
                        elements[#elements + 1] = el
                        pabRegisteredCustomBuffKeys[key] = true
                    end
                end
                local dl = b.debuffBars
                if dl then
                    for i = 1, #dl do
                        local bar = dl[i]
                        local key, el = MakeCustomBarElement(bar.id, bar, 703, false, customDebuffParents)
                        elements[#elements + 1] = el
                        pabRegisteredCustomDebuffKeys[key] = true
                    end
                end
            end
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")
    end

    -- Retire keys for bars deleted since the last call -- safe here (unlike TBB)
    -- because PAB custom-bar ids are permanent, see doc comment above. The
    -- element-options map entry is retired with the mover; a leftover entry would
    -- be harmless (no mover, no cog) but the id is gone for good either way.
    local elemMap = EllesmereUI._ELEMENT_SETTINGS_MAP
    if prevBuffKeys then
        for key in pairs(prevBuffKeys) do
            if not pabRegisteredCustomBuffKeys[key] then
                EllesmereUI:UnregisterUnlockElement(key)
                if elemMap then elemMap[key] = nil end
            end
        end
    end
    if prevDebuffKeys then
        for key in pairs(prevDebuffKeys) do
            if not pabRegisteredCustomDebuffKeys[key] then
                EllesmereUI:UnregisterUnlockElement(key)
                if elemMap then elemMap[key] = nil end
            end
        end
    end
end
ns.PAB_RegisterCustomUnlock = RegisterPABCustomUnlock

-- Public hook for the Options UI: (re)builds one custom buff bar's engine state to
-- match its current DB entry. Safe after ANY change to that bar (spell add/remove, any
-- cfg field, enable toggle, delete): it diffs the spell signature itself and only pays
-- for a container rebuild when the spell list actually changed, while style/grid/anchor
-- are cheap to re-apply every time. One combined call (vs the default bars'
-- RestyleBars/ApplyLiveConfig split) keeps the Options UI's call sites simple.
--
-- Wrapped below so unlock-mode registration stays in sync on every exit path (deleted,
-- disabled, spell-list-unchanged, full rebuild) without repeating
-- RegisterPABCustomUnlock() at each early return.
local function ReloadCustomBuffBarImpl(barId)
    if not AK then SetAK(EllesmereUI and EllesmereUI.AuraKit) end
    if not AK then return end
    local bar, barBucket = ns.PAB_GetCustomBuffBar(barId)
    if not bar then
        -- Deleted: release the container (frees its slot-button tracking; engine
        -- frames themselves are never destroyed) and hide the now-orphaned parent.
        if customBuffContainers[barId] then RetireContainer(customBuffContainers[barId], customBuffDeclared[barId]) end
        if customBuffParents[barId] then customBuffParents[barId]:Hide() end
        customBuffContainers[barId], customBuffParents[barId], customBuffSig[barId], customBuffDeclared[barId] = nil, nil, nil, nil
        return
    end
    if DeferRestrictedApply("custom-buff-" .. barId,
        function() ns.PAB_ReloadCustomBuffBar(barId) end,
        customBuffContainers[barId], bar.growDirection) then return end

    local styleKey = CustomBuffStyleKey(barId)
    AK.styles[styleKey] = BuildStyle(true, bar)
    -- Counterpart to RestyleBars' AK.RestyleSoon for the default bars. REQUIRED:
    -- writing AK.styles[styleKey] alone only affects buttons created after this point
    -- (MakeInitializer runs once per button), so a style-only edit on a bar whose
    -- buttons already exist (the "spell list unchanged" path below) would keep
    -- rendering the OLD style until the container was rebuilt for an unrelated reason.
    -- RestyleSoon re-runs ApplyStyleToRegions against every already-live button
    -- under that key.
    AK.RestyleSoon(styleKey)
    SyncCancelCVar()

    local grid = ComputeGrid(true, bar)
    local parent = customBuffParents[barId]
    local fresh = false
    if not parent then
        parent = CreateFrame("Frame", "EllesmereUIPlayerAuraBars_CustomBuff" .. barId, UIParent)
        customBuffParents[barId] = parent
        parent:SetSize(grid.width, grid.height)
        fresh = true
    end
    -- Same anchor-ancestor rule as ApplyLiveConfig: an EXISTING parent has the engine
    -- container anchored to it, so its position/size writes are blocked in lockdown --
    -- skip them and reconcile with one full reload at the regen edge (position deltas
    -- are not tracked per bar, so the queue is unconditional on the skip). A parent
    -- created THIS pass has no container anchored yet and stays fully writable. The
    -- config re-drive below still runs -- that is what the in-combat recovery needs.
    local geomLocked = not fresh and InCombatLockdown()
    if geomLocked then
        QueuePABRegenApply("custom-buff-" .. barId, function() ns.PAB_ReloadCustomBuffBar(barId) end)
    else
        ApplyCustomBarPosition(parent, bar, barId, true, grid)
    end
    -- Effective render verdict: the bar's own toggle AND its editing-spec
    -- bucket's applicability to the current spec AND this spec's per-spec
    -- disable of group bars. Inactive parks exactly like disabled.
    local barActive = ns.PAB_BarActive(bar, barBucket)
    SetParentShownSafe("custom-buff-" .. barId, parent, barActive,
        function() ns.PAB_ReloadCustomBuffBar(barId) end)
    if not barActive then return end

    if not geomLocked then
        parent:SetSize(grid.width, grid.height)
    end

    local spells = ns.PAB_ResolveSpells(bar)
    local sig = CustomBuffSpellSignature(spells)
    -- Show All Buffs works on custom buff bars too: mirrors the default Buffs bar's
    -- catch-all group (BuildChain zero-classes, "all" key) via the same
    -- ApplyGroupConfig path custom debuff bars use for their category chain --
    -- ApplyGroupConfig is generic over any {key,tokens} chain.
    local allChain = BuffBarChain(bar)

    if customBuffContainers[barId] then
        -- Style/grid-only change (icon size, padding, grow direction, ...): container
        -- exists and the spell list is unchanged, so just re-apply the live
        -- anchor/growth/rowWidth, the same fields ApplyLiveConfig live-updates for
        -- the default bars.
        local container = customBuffContainers[barId]
        ApplyContainerAnchorAndGrowth(container, parent, bar, grid)

        if customBuffSig[barId] == sig then
            -- Spell list unchanged: still refresh the spells group's
            -- maxFrameCount/layout in case the grid changed, and re-apply the
            -- catch-all chain (ApplyGroupConfig is idempotent and self-zeroes it
            -- when Show All Buffs is off).
            if #spells > 0 then
                local livePad = bar.padding or 5
                EllesmereUI.AuraKit.SetGroupCap(container, "spells", grid.effectiveMax)
                container:SetAuraGroupLayout("spells", BuildGroupLayout(bar, livePad, grid.rowGap))
                local liveIncludeMap = {}
                for i = 1, #spells do liveIncludeMap[spells[i]] = true end
                container:SetAuraGroupCandidateFilters("spells",
                    MergeCandidateFilters({ includeSpellIDs = liveIncludeMap }, BuffCandidateExtras(bar)))
                local sortMethod, sortDirection = ResolveSortMethod(bar), ResolveSortDirection(bar)
                if sortMethod ~= nil and sortDirection ~= nil then
                    container:SetAuraGroupSortMethod("spells", sortMethod, sortDirection)
                end
            end
            customBuffDeclared[barId] = customBuffDeclared[barId] or {}
            ApplyGroupConfig(container, allChain, customBuffDeclared[barId], styleKey, grid.effectiveMax, bar.padding or 5, grid.rowGap, bar, BuffCandidateExtras(bar))
            return -- nothing structural to rebuild
        end
        RetireContainer(container, customBuffDeclared[barId]) -- safe: dedicated container, nothing else on it
        customBuffContainers[barId] = nil
    end

    local _, spec = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5
    AK.RequestContainer(parent, "player", spec, function(container)
        customBuffContainers[barId] = container
        ApplyContainerAnchorAndGrowth(container, parent, bar, grid)
        customBuffSig[barId] = sig
        customBuffDeclared[barId] = {}
        ApplyGroupConfig(container, allChain, customBuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar, BuffCandidateExtras(bar))
        if #spells > 0 then
            local includeMap = {}
            for i = 1, #spells do includeMap[spells[i]] = true end
            AK.AddGroupToContainer(container, {
                key = "spells",
                filter = { "HELPFUL" },
                style = styleKey,
                maxFrameCount = grid.effectiveMax,
                candidateFilters = MergeCandidateFilters({ includeSpellIDs = includeMap }, BuffCandidateExtras(bar)),
                sortMethod = ResolveSortMethod(bar),
                sortDirection = ResolveSortDirection(bar),
                layout = BuildGroupLayout(bar, pad, grid.rowGap),
            })
        end
    end)
end

function ns.PAB_ReloadCustomBuffBar(barId)
    ReloadCustomBuffBarImpl(barId)
    RegisterPABCustomUnlock()
    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview("buff", barId) end
end

-- Public hook for the Options UI: (re)builds one custom debuff bar's engine state to
-- match its current DB entry. Groups are additive and never released (see
-- ApplyGroupConfig) -- a class toggle, grid change, or style edit just re-runs this on
-- the same container. Wrapped for the same reason as PAB_ReloadCustomBuffBar: unlock-
-- mode registration stays in sync on every exit path.
local function ReloadCustomDebuffBarImpl(barId)
    if not AK then SetAK(EllesmereUI and EllesmereUI.AuraKit) end
    if not AK then return end
    local bar, barBucket = ns.PAB_GetCustomDebuffBar(barId)
    if not bar then
        if customDebuffContainers[barId] then RetireContainer(customDebuffContainers[barId], customDebuffDeclared[barId]) end
        if customDebuffParents[barId] then customDebuffParents[barId]:Hide() end
        -- Bar IDs are never reused, so this entry is never looked up again.
        customDebuffParents[barId], customDebuffContainers[barId], customDebuffDeclared[barId] = nil, nil, nil
        return
    end
    if DeferRestrictedApply("custom-debuff-" .. barId,
        function() ns.PAB_ReloadCustomDebuffBar(barId) end,
        customDebuffContainers[barId], bar.growDirection) then return end

    local styleKey = CustomDebuffStyleKey(barId)
    AK.styles[styleKey] = BuildStyle(false, bar)
    -- Required for the same reason as ReloadCustomBuffBarImpl above.
    AK.RestyleSoon(styleKey)

    local grid = ComputeGrid(false, bar)
    local parent = customDebuffParents[barId]
    local fresh = false
    if not parent then
        parent = CreateFrame("Frame", "EllesmereUIPlayerAuraBars_CustomDebuff" .. barId, UIParent)
        customDebuffParents[barId] = parent
        parent:SetSize(grid.width, grid.height)
        fresh = true
    end
    -- Same lockdown rule as the custom buff reload above (anchor-ancestor geometry
    -- block; full-reload reconcile at regen; fresh parents stay writable).
    local geomLocked = not fresh and InCombatLockdown()
    if geomLocked then
        QueuePABRegenApply("custom-debuff-" .. barId, function() ns.PAB_ReloadCustomDebuffBar(barId) end)
    else
        ApplyCustomBarPosition(parent, bar, barId, false, grid)
    end
    -- Same effective-render verdict as the custom buff reload above.
    local barActive = ns.PAB_BarActive(bar, barBucket)
    SetParentShownSafe("custom-debuff-" .. barId, parent, barActive,
        function() ns.PAB_ReloadCustomDebuffBar(barId) end)
    if not barActive then return end

    if not geomLocked then
        parent:SetSize(grid.width, grid.height)
    end

    local chain = DebuffChainFor(bar)
    local _, spec = BuildContainerSpec(parent, bar, grid)
    local pad = bar.padding or 5

    if not customDebuffContainers[barId] then
        AK.RequestContainer(parent, "player", spec, function(container)
            customDebuffContainers[barId] = container
            ApplyContainerAnchorAndGrowth(container, parent, bar, grid)
            customDebuffDeclared[barId] = {}
            ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar, DebuffCandidateExtras(bar))
        end)
    else
        local container = customDebuffContainers[barId]
        ApplyContainerAnchorAndGrowth(container, parent, bar, grid)
        ApplyGroupConfig(container, chain, customDebuffDeclared[barId], styleKey, grid.effectiveMax, pad, grid.rowGap, bar, DebuffCandidateExtras(bar))
    end
end

function ns.PAB_ReloadCustomDebuffBar(barId)
    ReloadCustomDebuffBarImpl(barId)
    RegisterPABCustomUnlock()
    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview("debuff", barId) end
end

-- Rebuilds every persisted custom bar's engine state. Called once from CreateBars
-- alongside the default bars, and safe to call again any time (profile switch, spec
-- change): both reload functions above are idempotent no-ops when nothing changed.
-- Iterates the legacy arrays AND every editing-spec bucket -- each per-bar reload
-- resolves its own effective verdict, so bars from now-inactive buckets park their
-- frames exactly like disabled ones.
local function ReloadAllCustomBarsImpl()
    local presentBuff, presentDebuff = {}, {}
    local buffList = ns.PAB_CustomBuffBars()
    if buffList then
        for i = 1, #buffList do
            presentBuff[buffList[i].id] = true
            ns.PAB_ReloadCustomBuffBar(buffList[i].id)
        end
    end
    local debuffList = ns.PAB_CustomDebuffBars()
    if debuffList then
        for i = 1, #debuffList do
            presentDebuff[debuffList[i].id] = true
            ns.PAB_ReloadCustomDebuffBar(debuffList[i].id)
        end
    end
    local s = PAB()
    local st = s and s.pabSpecBars
    if st then
        for _, b in pairs(st) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do
                    presentBuff[bl[i].id] = true
                    ns.PAB_ReloadCustomBuffBar(bl[i].id)
                end
            end
            local dl = b.debuffBars
            if dl then
                for i = 1, #dl do
                    presentDebuff[dl[i].id] = true
                    ns.PAB_ReloadCustomDebuffBar(dl[i].id)
                end
            end
        end
    end
    -- STALE SWEEP (field bug: a bar from the PREVIOUS profile stayed on
    -- screen after a profile swap): addon-side parents/containers are keyed
    -- by bar id and outlive the profile table. Any id the CURRENT profile no
    -- longer carries takes the per-bar reload's deleted-bar branch, which
    -- retires the container, hides the parent and clears the bookkeeping.
    -- (Lua 5.1: clearing the CURRENT key during pairs() is legal; the
    -- deleted-bar branch nils exactly the iterated id.)
    for barId in pairs(customBuffParents) do
        if not presentBuff[barId] then ns.PAB_ReloadCustomBuffBar(barId) end
    end
    for barId in pairs(customDebuffParents) do
        if not presentDebuff[barId] then ns.PAB_ReloadCustomDebuffBar(barId) end
    end
end
ReloadAllCustomBars = ReloadAllCustomBarsImpl
SetReloadAllCustomBars(ReloadAllCustomBars)
ns.PAB_ReloadAllCustomBars = ReloadAllCustomBarsImpl

I.customBuffContainers, I.customBuffParents = customBuffContainers, customBuffParents
I.customDebuffContainers, I.customDebuffParents = customDebuffContainers, customDebuffParents
I.RegisterPABCustomUnlock = RegisterPABCustomUnlock
I.ReloadAllCustomBars = ReloadAllCustomBars
I.broken = false
