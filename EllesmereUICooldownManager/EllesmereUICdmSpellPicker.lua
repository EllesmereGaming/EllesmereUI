if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmSpellPicker.lua
--  Interactive Preview Helpers (used by options spell picker): spell list
--  building, add/remove/swap/move/replace, and custom bar creation/removal.
-------------------------------------------------------------------------------
local _, ns = ...

-- Upvalue aliases (populated by EllesmereUICooldownManager.lua)
local ECME                   = ns.ECME
local barDataByKey           = ns.barDataByKey
local cdmBarFrames           = ns.cdmBarFrames
local cdmBarIcons            = ns.cdmBarIcons
local ResolveInfoSpellID     = ns.ResolveInfoSpellID
local ComputeTopRowStride    = ns.ComputeTopRowStride

-------------------------------------------------------------------------------
--  SpellVariant helpers
--  "variant family" = { spellID, base, override, override-of-base }. Treats
--  e.g. Heroism/Bloodlust override variants as one logical entry.
--  StoreVariantValue(target, spellID, value, preserveExisting, directSet):
--  writes value under every family key. preserveExisting applies to the EXACT
--  id only (first-write-wins); derived keys never overwrite an existing entry,
--  so one spell's expansion can't displace another's exact assignment.
--  directSet, if given, records the exact id separately from derived keys.
--  ResolveVariantValue(sourceMap, spellID): first non-nil sourceMap[k] across
--  the family, else nil. IsVariantOf(a, b): true if a and b share any member.
-------------------------------------------------------------------------------
-- Reject secret-tainted numbers before comparing: frame:GetSpellID() on active
-- viewer frames can return a secret, and `id > 0` on it taints us.
-- issecretvalue/type() read safely without touching the value.
local function _IsUsableSID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0 and id == math.floor(id)
end

local function _GetBase(sid)
    if not _IsUsableSID(sid) or not C_Spell or not C_Spell.GetBaseSpell then return nil end
    local b = C_Spell.GetBaseSpell(sid)
    if _IsUsableSID(b) and b ~= sid then return b end
    return nil
end

local function _GetOverride(sid)
    if not _IsUsableSID(sid) or not C_Spell or not C_Spell.GetOverrideSpell then return nil end
    local o = C_Spell.GetOverrideSpell(sid)
    if _IsUsableSID(o) and o ~= sid then return o end
    return nil
end

local function _StoreIfValid(target, id, value, preserveExisting)
    if not _IsUsableSID(id) then return end
    if preserveExisting and target[id] ~= nil then return end
    target[id] = value
end

-- Concrete case for directSet: Divine Toll and its override share cooldownID/
-- base, so without it the winner would depend on collection order and the
-- slot could change bars as the spell transforms. Derived keys fill gaps only.
local function StoreVariantValue(target, spellID, value, preserveExisting, directSet)
    if type(target) ~= "table" or not _IsUsableSID(spellID) then return end
    _StoreIfValid(target, spellID, value, preserveExisting)
    if type(directSet) == "table" then directSet[spellID] = value end
    _StoreIfValid(target, _GetOverride(spellID), value, true)
    local baseID = _GetBase(spellID)
    if baseID then
        _StoreIfValid(target, baseID, value, true)
        _StoreIfValid(target, _GetOverride(baseID), value, true)
    end
end

local function ResolveVariantValue(sourceMap, spellID)
    if type(sourceMap) ~= "table" or not _IsUsableSID(spellID) then return nil end
    local direct = sourceMap[spellID]
    if direct ~= nil then return direct end
    local baseID = _GetBase(spellID)
    if baseID then
        local v = sourceMap[baseID]
        if v ~= nil then return v end
    end
    local overrideID = _GetOverride(spellID)
    if overrideID then
        local v = sourceMap[overrideID]
        if v ~= nil then return v end
    end
    if baseID then
        local baseOverrideID = _GetOverride(baseID)
        if baseOverrideID then
            local v = sourceMap[baseOverrideID]
            if v ~= nil then return v end
        end
    end
    return nil
end

local function IsVariantOf(spellIDA, spellIDB)
    if not _IsUsableSID(spellIDA) or not _IsUsableSID(spellIDB) then return false end
    if spellIDA == spellIDB then return true end
    -- Some rotating viewer spells expose no reversible relationship through
    -- GetBaseSpell/GetOverrideSpell in one of their live states.  The hook
    -- layer persists the clean, spec-scoped pairing when the viewer does expose
    -- it; consult that ledger so moving/re-adding Sacred Weapon also removes a
    -- stale Holy Bulwark/base entry from the old bar or ghost list.
    if ns.IsLearnedVariantOf and ns.IsLearnedVariantOf(spellIDA, spellIDB) then
        return true
    end
    if _GetBase(spellIDA) == spellIDB or _GetBase(spellIDB) == spellIDA then return true end
    if _GetOverride(spellIDA) == spellIDB or _GetOverride(spellIDB) == spellIDA then return true end
    local baseA = _GetBase(spellIDA)
    local baseB = _GetBase(spellIDB)
    if baseA and baseB and baseA == baseB then return true end
    return false
end

ns.StoreVariantValue   = StoreVariantValue
ns.ResolveVariantValue = ResolveVariantValue
ns.IsVariantOf         = IsVariantOf

-------------------------------------------------------------------------------
--  CDM category-set constants (Midnight's 9-value CooldownViewerCategory).
--  CDM_ICON_CD_CATS: cooldown/utility icon categories (Essential, Utility,
--  SpecAgnosticEssential, EquipSlotEssential). CDM_BUFF_CATS: buff-family
--  categories (TrackedBuff, GroupBuff, SpecAgnosticTracked, EquipSlotTracked).
--  TrackedBar (3) is scoped separately by GetTrackedBarSpells and is a member
--  of neither set. Hidden pseudo-categories (HiddenActive/HiddenPassive,
--  negative values) are never members of either set. Numeric fallbacks let
--  these build even if the Enum table is ever unavailable at load.
-------------------------------------------------------------------------------
do
    local evc = Enum and Enum.CooldownViewerCategory
    ns.CDM_ICON_CD_CATS = {
        [(evc and evc.Essential)             or 0] = true,
        [(evc and evc.Utility)               or 1] = true,
        [(evc and evc.SpecAgnosticEssential) or 5] = true,
        [(evc and evc.EquipSlotEssential)    or 7] = true,
    }
    ns.CDM_BUFF_CATS = {
        [(evc and evc.TrackedBuff)         or 2] = true,
        [(evc and evc.GroupBuff)           or 4] = true,
        [(evc and evc.SpecAgnosticTracked) or 6] = true,
        [(evc and evc.EquipSlotTracked)    or 8] = true,
    }
end

-- Normalize a spell ID to its base (undo talent overrides), e.g. Voltaic
-- Blaze (470057) -> Flame Shock (188389). Resident home for what used to be
-- an options-file-local pair so every consumer (the keep/drop reconcile
-- pass, the picker, migration) shares one implementation and one secrecy
-- gate. Degrades to identity on any invalid/secret id or missing API so
-- callers can key tables on the result without a separate validity check.
function ns.NormalizeToBase(sid)
    if not _IsUsableSID(sid) or not C_Spell or not C_Spell.GetBaseSpell then return sid end
    local base = C_Spell.GetBaseSpell(sid)
    if _IsUsableSID(base) then return base end
    return sid
end

-- Resolve a base spell ID to its current live version (talent overrides),
-- e.g. Flame Shock (188389) -> Voltaic Blaze (470057) when talented. Uses
-- the spellbook override bridge (not this file's private _GetOverride, which
-- is C_Spell.GetOverrideSpell -- a different API with different semantics)
-- so catalog/live-icon membership tests agree with the rest of the resident code.
function ns.ResolveToLive(sid)
    if not _IsUsableSID(sid) or not C_SpellBook or not C_SpellBook.FindSpellOverrideByID then return sid end
    local ovr = C_SpellBook.FindSpellOverrideByID(sid)
    if _IsUsableSID(ovr) then return ovr end
    return sid
end

-------------------------------------------------------------------------------
--  Buff variant-alias ledger
--  A buff whose live cooldown-viewer report rotates among several spellIDs
--  (e.g. a dual-tracked or talent-swapped form) only exposes its OTHER forms
--  via linkedSpellIDs, and only while that exact instance is the one
--  currently active. This ledger records every id pairing ever observed
--  together on the active spec, persisted under the spec profile
--  (prof.buffVariantAliases, sibling of barSpells), so a later reconcile
--  pass can recognize the whole family as one entity even when only one
--  member is currently reporting.
--
--  Storage is a SET per id (ledger[a] = { [b] = true, ... }), not a single
--  scalar partner: an N-way family writes every pairwise edge from one
--  observation, and a scalar slot would let a later pair silently overwrite
--  an earlier one, disconnecting part of the family from closure expansion.
-------------------------------------------------------------------------------
local _buffAliasSeen = {}

-- Learns every pairwise edge among {displaySID} union linkedList that this session
-- hasn't already recorded. Ids are gated for secrecy/plausibility here so callers never
-- need to; the session-cache early-out (mirrors _learnVariantBase in
-- EllesmereUICdmHooks.lua) keeps repeat observations of an already-known pairing from
-- touching the profile table.
function ns.LearnBuffVariantAlias(displaySID, linkedList)
    if type(linkedList) ~= "table" or #linkedList == 0 then return end
    local ids
    if _IsUsableSID(displaySID) then ids = { displaySID } end
    for i = 1, #linkedList do
        local lid = linkedList[i]
        if _IsUsableSID(lid) then
            ids = ids or {}
            ids[#ids + 1] = lid
        end
    end
    if not ids or #ids < 2 then return end

    local ledger
    for i = 1, #ids do
        local a = ids[i]
        for j = i + 1, #ids do
            local b = ids[j]
            local seenA = _buffAliasSeen[a]
            if not (seenA and seenA[b]) then
                if not ledger then
                    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                    local prof = sp and sk and sp[sk]
                    if not prof then return end
                    if not prof.buffVariantAliases then prof.buffVariantAliases = {} end
                    ledger = prof.buffVariantAliases
                end
                ledger[a] = ledger[a] or {}
                ledger[a][b] = true
                ledger[b] = ledger[b] or {}
                ledger[b][a] = true
                _buffAliasSeen[a] = _buffAliasSeen[a] or {}
                _buffAliasSeen[a][b] = true
                _buffAliasSeen[b] = _buffAliasSeen[b] or {}
                _buffAliasSeen[b][a] = true
            end
        end
    end
end

-- Shared empty fallback; never mutated (only the writer above creates the real table).
local _EMPTY_ALIAS_LEDGER = {}

-- Active spec's learned buff-family ledger, or a shared empty table when no profile is
-- active yet or no pairing has ever been learned. Read-only: never creates the key.
function ns.GetBuffVariantAliases()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local prof = sp and sk and sp[sk]
    return (prof and prof.buffVariantAliases) or _EMPTY_ALIAS_LEDGER
end

-- Per-cooldownID cache of the last CLEAN frame:GetSpellID(). While a viewer
-- frame is ACTIVE, GetSpellID()/GetAuraSpellID() return secret values, so the
-- live talent form is unreadable and would degrade to the generic
-- cooldownInfo.spellID; reuse the clean value from the last INACTIVE read so
-- picker/preview agree regardless of aura state. Shared (ns) so reanchor can
-- prime it at login. Self-heals: any later clean read overwrites the entry.
ns._cdmCleanSidByCDID = ns._cdmCleanSidByCDID or {}
local _cleanSidByCDID = ns._cdmCleanSidByCDID

-- GetCanonicalSpellIDForFrame: preferred spell ID to STORE for a Blizzard CDM
-- viewer frame. Picker, migration, and runtime resolution all use this so
-- they agree on the ID for the same logical spell. Priority (first non-nil
-- wins): 1. frame:GetSpellID() -- most authoritative, the active variant
-- under transforms (e.g. Glacial Spike from Frostbolt), what the user can
-- actually cast, not the static info; 2. info.overrideSpellID; 3. info.spellID;
-- 4. base of (1) as fallback. (linkedSpellIDs is deliberately NOT a rung --
-- see the comment at the info branch.)
local function GetCanonicalSpellIDForFrame(frame)
    if not frame then return nil end

    local fnGetSpellID = frame.GetSpellID
    if type(fnGetSpellID) == "function" then
        local sid = fnGetSpellID(frame)
        if _IsUsableSID(sid) then
            -- Clean read: cache by cooldownID so a later secret read still resolves.
            local cdid = frame.cooldownID
            if type(cdid) == "number" then _cleanSidByCDID[cdid] = sid end
            return sid
        end
    end

    -- GetAuraSpellID(): buff frames expose the aura variant (Eclipse Solar
    -- vs Lunar); GetSpellID may not exist there.
    local fnGetAura = frame.GetAuraSpellID
    if type(fnGetAura) == "function" then
        local sid = fnGetAura(frame)
        if _IsUsableSID(sid) then
            -- Clean read: prime the cooldownID cache here too, so buff frames
            -- (no GetSpellID) still resolve while their aura is up.
            local cdid = frame.cooldownID
            if type(cdid) == "number" then _cleanSidByCDID[cdid] = sid end
            return sid
        end
    end

    -- Active-frame fallback: both getters returned secret/nil (aura is up).
    -- Reuse the clean GetSpellID cached while inactive, instead of degrading
    -- to the generic cooldownInfo.spellID below.
    local cdid = frame.cooldownID
    if type(cdid) == "number" then
        local cached = _cleanSidByCDID[cdid]
        if cached then return cached end
    end

    local info = frame.cooldownInfo
    if not info then
        local fnGetInfo = frame.GetCooldownInfo
        if type(fnGetInfo) == "function" then
            info = fnGetInfo(frame)
        end
    end

    if info then
        if _IsUsableSID(info.overrideSpellID) then return info.overrideSpellID end
        if _IsUsableSID(info.spellID) then return info.spellID end
        -- Deliberately NOT falling back to linkedSpellIDs[1] here: the frame's
        -- own info is the MERGED provider table (Blizzard caches
        -- GetCooldownInfoForID at SetCooldownID), where linked lists are
        -- group-shared and categories are folded to DISPLAY values -- it can
        -- tell neither frames nor native equip rows apart. The one legitimate
        -- linked-identity source is the RAW API block below.
    end

    -- Native tracked trinket buff rows (RAW equipSlot + category
    -- EquipSlotTracked): these carry no spellID at all at rest, and their RAW
    -- linked list is Blizzard's own designed identity channel for the row's
    -- tracked buff -- field-probed 2026-08-16 as per-row UNIQUE (buffSlot 1
    -- and 2 of one trinket carry different single-entry lists). The RAW
    -- GetCooldownViewerCooldownInfo table is the proven source: the frame's
    -- merged copy folds category to the display value (TrackedBuff) and
    -- cannot pass this gate. Resolved sid is cached by cooldownID like the
    -- clean GetSpellID path, so secret windows (proc active in combat) keep
    -- resolving from the memo. Reached only after every other rung failed
    -- (identity-less shells), so the extra C call is shell-only.
    if type(cdid) == "number" and C_CooldownViewer
       and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local raw = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdid)
        local eqTracked = Enum and Enum.CooldownViewerCategory
            and Enum.CooldownViewerCategory.EquipSlotTracked or 8
        if raw and raw.equipSlot and not (issecretvalue and issecretvalue(raw.equipSlot))
           and raw.category and not (issecretvalue and issecretvalue(raw.category))
           and raw.category == eqTracked then
            local linked = raw.linkedSpellIDs
            if type(linked) == "table" then
                local lid = linked[1]
                if _IsUsableSID(lid) then
                    _cleanSidByCDID[cdid] = lid
                    return lid
                end
            end
        end
    end

    -- Last resort: base of frame:GetSpellID()
    if type(fnGetSpellID) == "function" then
        local raw = fnGetSpellID(frame)
        if _IsUsableSID(raw) then
            local base = _GetBase(raw)
            if base then return base end
            return raw
        end
    end

    return nil
end
ns.GetCanonicalSpellIDForFrame = GetCanonicalSpellIDForFrame

-- EnumerateCDMViewerSpells: walks the CD/util viewer pools, returns canonical
-- spell entries in viewer-then-layoutIndex render order. Shared source of
-- truth for picker AND migration -- the same spells the route map sees.
local function EnumerateCDMViewerSpells(includeBuffViewer)
    local viewers
    if includeBuffViewer then
        viewers = { "BuffIconCooldownViewer" }
    else
        viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
    end

    local result = {}
    local seen = {}
    local viewerOrder = 0
    local entries = {}

    for _, vName in ipairs(viewers) do
        local viewer = _G[vName]
        if viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if frame:IsShown() or frame.cooldownInfo then
                    local sid = GetCanonicalSpellIDForFrame(frame)
                    -- Dedup identity: BUFF viewer can have two cooldownIDs share
                    -- one spellID (e.g. Diabolist: Demonic Art vs Diabolic
                    -- Ritual), so key on cooldownID there (sid-dedup would
                    -- wrongly merge them); CD/util viewers keep sid-dedup to
                    -- collapse a spell shown in two viewers. Non-colliding specs
                    -- are unaffected: a unique sid there implies a unique cooldownID.
                    local cd = frame.cooldownID
                    local dkey = (includeBuffViewer and type(cd) == "number")
                        and ("c" .. cd) or sid
                    if _IsUsableSID(sid) and dkey ~= nil and not seen[dkey] then
                        seen[dkey] = true
                        entries[#entries + 1] = {
                            sid          = sid,
                            cdID         = frame.cooldownID,
                            viewerName   = vName,
                            viewerOrder  = viewerOrder,
                            layoutIndex  = frame.layoutIndex or 0,
                        }
                    end
                end
            end
        end
        viewerOrder = viewerOrder + 10000
    end

    table.sort(entries, function(a, b)
        if a.viewerOrder ~= b.viewerOrder then return a.viewerOrder < b.viewerOrder end
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return a.sid < b.sid
    end)

    for i, e in ipairs(entries) do
        result[i] = e  -- preserve metadata for picker
    end
    return result
end
ns.EnumerateCDMViewerSpells = EnumerateCDMViewerSpells

-- Unified spell list helpers: ONE add path and ONE remove path for every CDM
-- bar's assignedSpells list (default/custom/ghost bars). Variant-aware via
-- IsVariantOf, so adding the same spell under a different variant ID is a
-- no-op. AddTrackedSpell/RemoveTrackedSpell delegate to these.

--- Find an entry's index in a spell list. Positive IDs (real spells) match by
--- variant family (re-adding any variant is a no-op); negative IDs (trinkets
--- <= -13/-14, item presets <= -100) match by exact equality -- variant
--- resolution doesn't apply to injection markers.
local function FindVariantIndex(spellList, spellID)
    if type(spellList) ~= "table" or type(spellID) ~= "number" or spellID == 0 then
        return nil
    end
    if spellID > 0 then
        for i = 1, #spellList do
            local existing = spellList[i]
            if _IsUsableSID(existing) and IsVariantOf(existing, spellID) then
                return i
            end
        end
    else
        for i = 1, #spellList do
            if spellList[i] == spellID then return i end
        end
    end
    return nil
end
ns.FindVariantIndexInList = FindVariantIndex

--- Add a spellID to a bar's assignedSpells list. Idempotent under variant
--- equivalence (no-op if any family member is present). True on add, else false.
function ns.AddSpellToBar(barKey, spellID)
    if not _IsUsableSID(spellID) then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    if FindVariantIndex(sd.assignedSpells, spellID) then return false end
    sd.assignedSpells[#sd.assignedSpells + 1] = spellID
    ns._spellOrderDirty = true
    -- Mutual exclusivity with the ghost bar: the route map gives the ghost
    -- highest priority, so a spell left in both stays hidden; un-hide it here.
    if barKey ~= ns.GHOST_CD_BAR_KEY and ns.RemoveSpellFromBar then
        ns.RemoveSpellFromBar(ns.GHOST_CD_BAR_KEY, spellID)
    end
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    -- FocusKick arms its proxies on bar CONTENT; nothing else re-runs that when
    -- content changes here, so an add must explicitly re-evaluate.
    if barKey == ns.FOCUSKICK_BAR_KEY and ns.RefreshFocusKickProxies then
        ns.RefreshFocusKickProxies("spell-added")
    end
    return true
end

--- Remove a spellID from a bar's assignedSpells list (variant-aware). Returns
--- the removed spellID (actual stored variant, may differ from queried) or nil.
function ns.RemoveSpellFromBar(barKey, spellID)
    -- Accepts positive (real spell) or negative (trinket/item preset) IDs;
    -- FindVariantIndex dispatches internally.
    if type(spellID) ~= "number" or spellID == 0 then return nil end
    local sd = ns.GetBarSpellData(barKey)
    if not sd or not sd.assignedSpells then return nil end
    local idx = FindVariantIndex(sd.assignedSpells, spellID)
    if not idx then return nil end
    local removed = table.remove(sd.assignedSpells, idx)
    ns._spellOrderDirty = true
    -- Clean up auxiliary per-spell metadata for the removed entry
    if sd.customSpellDurations then sd.customSpellDurations[removed] = nil end
    if sd.spellDurations       then sd.spellDurations[removed]       = nil end
    if sd.customSpellIDs       then sd.customSpellIDs[removed]       = nil end
    if sd.customSpellGroups then
        for variantID, primaryID in pairs(sd.customSpellGroups) do
            if primaryID == removed then sd.customSpellGroups[variantID] = nil end
        end
    end
    -- Default buffs bar: scrub the removed custom buff's stable order key. Absent keys
    -- are normally kept as gaps (talent-swap feature), but a user-removed custom buff
    -- never returns to fill its gap, and the orphans would desync the preview's
    -- rendered slots. Blizzard-tracked buffs key as "c"..cooldownID and are unaffected.
    if barKey == "buffs" and type(removed) == "number" and removed > 0
       and type(sd.buffDisplayOrder) == "table" then
        local t = sd.buffDisplayOrder
        local skey = "s" .. removed
        for i = #t, 1, -1 do
            if t[i] == skey then table.remove(t, i) end
        end
    end
    -- Hosted-buff bookkeeping: removing the MARKER (or a legacy plain entry that
    -- represents the buff: flag set, no marker in the list) un-hosts the buff --
    -- otherwise the orphaned flag makes the options self-heal re-append the
    -- spell here (spell reappears on two bars). A plain entry removed while a
    -- marker still exists is a cooldown-only removal; the hosted buff stays.
    local hostedSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(removed)
    if not hostedSid and removed and removed > 0
       and sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[removed]
       and not (ns.ListHasHostedMarker and ns.ListHasHostedMarker(sd.assignedSpells, removed)) then
        hostedSid = removed
    end
    if hostedSid and sd.hostedBuffSpellIDs then
        sd.hostedBuffSpellIDs[hostedSid] = nil
        -- Host flip changes resolution routing: retire memoized results.
        ns._cdmResGen = (ns._cdmResGen or 0) + 1
    end
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    -- Same as AddSpellToBar: emptying the kick bar must re-evaluate proxies
    -- (cast sound survives an empty bar if an explicit interrupt is set).
    if barKey == ns.FOCUSKICK_BAR_KEY and ns.RefreshFocusKickProxies then
        ns.RefreshFocusKickProxies("spell-removed")
    end
    -- Aura-tracked customs: re-sync the bar's engine strip so a removed
    -- custom stops rendering immediately (the strip's include filter is
    -- declaration-fixed -- without this it keeps matching the removed id
    -- until the next full rebuild). Signature-gated: a no-op for every
    -- other kind of removal.
    if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end
    return removed
end

-- EnumerateCDMSettingsCatalog: arrangement-aware, talent-independent tracked CD/utility
-- cooldown enumeration from the Blizzard CDM settings panel's data provider. Unlike
-- live viewer pools, includes untalented spells (never get a viewer frame); unlike the
-- static category API, respects arrangement (Not Displayed reads Hidden, skipped) and
-- returns the arranged order. READ-ONLY, pcall-guarded; nil if provider/method missing
-- (callers fall back to live-pool behavior). Returns { cdID, sid, category } array,
-- Essential + Utility only.
function ns.EnumerateCDMSettingsCatalog(wantSet)
    local evc = Enum and Enum.CooldownViewerCategory
    if not evc then return nil end
    -- Default (no arg): full CD/utility catalog via ns.CDM_ICON_CD_CATS
    -- (Essential, Utility, SpecAgnosticEssential, EquipSlotEssential). Buff
    -- (ns.CDM_BUFF_CATS) / tracked-bar (TrackedBar=3) callers pass an explicit
    -- { [catValue] = true } set so each bar type scopes its own catalog.
    if wantSet == nil then
        if evc.Essential == nil or evc.Utility == nil then return nil end
        wantSet = ns.CDM_ICON_CD_CATS
    end
    local settings = _G.CooldownViewerSettings
    if not settings or type(settings.GetDataProvider) ~= "function" then return nil end
    local okP, provider = pcall(settings.GetDataProvider, settings)
    if not okP or type(provider) ~= "table" then return nil end
    -- Read the already-built display table, never the getters that would
    -- build it (see ns.CDMGetProviderDisplayData, EllesmereUICooldownManager.lua).
    local ordered, infoByID = ns.CDMGetProviderDisplayData(provider)
    if not ordered then return nil end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return nil end

    local result = {}
    for _, cdID in ipairs(ordered) do
        local pInfo = _IsUsableSID(cdID) and infoByID[cdID]
        local category
        if type(pInfo) == "table" then category = pInfo.category end
        if category ~= nil and wantSet[category] then
            -- Same shape the migration and spell caches use. Prefer override
            -- only when the player actually has it -- CDM info can report a
            -- stale override after the talent providing it is gone.
            local info = gci(cdID)
            local sid
            if info then
                local ovr = info.overrideSpellID
                if ovr and ovr > 0 and IsPlayerSpell and IsPlayerSpell(ovr) then
                    sid = ovr
                else
                    sid = info.spellID
                end
            end
            if _IsUsableSID(sid) then
                result[#result + 1] = { cdID = cdID, sid = sid, category = category }
            end
        end
    end
    return result
end

--- Returns array of { cdID, spellID, name, icon, cdmCat, cdmCatGroup, onEUIBar, isKnown },
--- sorted by viewer order (Essential before Utility) then alpha.
--- Walks Blizzard's CDM viewer pools (live frames), NOT the static category
--- API -- the same source of truth the route map uses, so picker contents
--- always match what routes to bars at reanchor. For CD/utility bars,
--- untalented tracked spells (no live frame) are appended from the settings
--- catalog so whole layouts can be arranged without swapping talents.
function ns.GetCDMSpellsForBar(barKey, includeUntalented)
    -- ns.IsBarBuffFamily: forward reference, defined further down this file.
    local isBuffType = ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey) or false

    -- Variant-keyed lookup of spells already on THIS bar (for onEUIBar flag).
    local ourPool = {}
    local sd = ns.GetBarSpellData(barKey)
    if sd and sd.assignedSpells then
        for _, sid in ipairs(sd.assignedSpells) do
            if sid and sid ~= 0 then
                StoreVariantValue(ourPool, sid, true, false)
            end
        end
    end

    -- Picker only enumerates pool members, so every result is Blizzard-tracked.
    local entries = EnumerateCDMViewerSpells(isBuffType)

    local spells = {}
    for _, e in ipairs(entries) do
        local sid = e.sid
        local name = C_Spell.GetSpellName(sid)
        local tex  = C_Spell.GetSpellTexture(sid)
        if name then
            local isOnThisBar = (ResolveVariantValue(ourPool, sid) == true)
            spells[#spells + 1] = {
                cdID        = e.cdID,
                spellID     = sid,
                name        = name,
                icon        = tex,
                cdmCat      = e.viewerOrder,  -- preserve viewer grouping for sort
                cdmCatGroup = isBuffType and "buff" or "cooldown",
                onEUIBar    = isOnThisBar,
                isKnown     = true,  -- live viewer pool members are always learned
            }
        end
    end

    -- CD/utility bars: also list untalented spells and conditionally-pooled
    -- ones Blizzard currently hides, sourced from the settings catalog
    -- (respects Not Displayed). Buff pickers untouched.
    if not isBuffType and ns.EnumerateCDMSettingsCatalog then
        -- Explicit set (mirrors the function's own default) so this call
        -- stays correct even if that default is ever narrowed.
        local catalog = ns.EnumerateCDMSettingsCatalog(ns.CDM_ICON_CD_CATS)
        if catalog then
            local evc = Enum and Enum.CooldownViewerCategory
            local seenCd, seenSid = {}, {}
            for _, e in ipairs(entries) do
                if e.cdID ~= nil then seenCd[e.cdID] = true end
                StoreVariantValue(seenSid, e.sid, true, false)
            end
            for _, ce in ipairs(catalog) do
                if not seenCd[ce.cdID]
                   and not ResolveVariantValue(seenSid, ce.sid) then
                    local name = C_Spell.GetSpellName(ce.sid)
                    local tex  = C_Spell.GetSpellTexture(ce.sid)
                    if name then
                        local known = false
                        if IsPlayerSpell and IsPlayerSpell(ce.sid) then known = true end
                        spells[#spells + 1] = {
                            cdID        = ce.cdID,
                            spellID     = ce.sid,
                            name        = name,
                            icon        = tex,
                            -- Match live grouping so catalog spells sort beside learned peers.
                            cdmCat      = (evc and ce.category == evc.Utility) and 10000 or 0,
                            cdmCatGroup = "cooldown",
                            onEUIBar    = (ResolveVariantValue(ourPool, ce.sid) == true),
                            isKnown     = known,
                        }
                        StoreVariantValue(seenSid, ce.sid, true, false)
                    end
                end
            end
        end
    end

    -- Buff bars: also list untalented buff-family entries (TrackedBuff,
    -- GroupBuff, SpecAgnosticTracked, EquipSlotTracked). Picker-only, so
    -- BarGlows/other consumers stay live-only.
    if isBuffType and includeUntalented and ns.EnumerateCDMSettingsCatalog then
        local catalog = ns.EnumerateCDMSettingsCatalog(ns.CDM_BUFF_CATS)
        if catalog then
            local seenCd, seenSid = {}, {}
            for _, e in ipairs(entries) do
                if e.cdID ~= nil then seenCd[e.cdID] = true end
                StoreVariantValue(seenSid, e.sid, true, false)
            end
            for _, ce in ipairs(catalog) do
                if not seenCd[ce.cdID]
                   and not ResolveVariantValue(seenSid, ce.sid) then
                    local name = C_Spell.GetSpellName(ce.sid)
                    local tex  = C_Spell.GetSpellTexture(ce.sid)
                    if name then
                        local known = false
                        if IsPlayerSpell and IsPlayerSpell(ce.sid) then known = true end
                        spells[#spells + 1] = {
                            cdID        = ce.cdID,
                            spellID     = ce.sid,
                            name        = name,
                            icon        = tex,
                            cdmCat      = 0,  -- single buff viewer bucket
                            cdmCatGroup = "buff",
                            onEUIBar    = (ResolveVariantValue(ourPool, ce.sid) == true),
                            isKnown     = known,
                        }
                        StoreVariantValue(seenSid, ce.sid, true, false)
                    end
                end
            end
        end
    end

    -- Viewer order first (Essential before Utility), then alpha.
    table.sort(spells, function(a, b)
        if a.cdmCat ~= b.cdmCat then return (a.cdmCat or 0) < (b.cdmCat or 0) end
        return a.name < b.name
    end)

    return spells
end

-- (ns.GetTBBSpellPool removed -- TBB disabled pending rewrite)

--- Check if a cooldownID has a Blizzard CDM child (is "displayed")
function ns.IsSpellDisplayedInCDM(barKey, cdID)
    local BLIZZ_CDM_FRAMES = ns.BLIZZ_CDM_FRAMES
    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if not blizzName then return false end
    local blizzFrame = _G[blizzName]
    if not blizzFrame then return false end
    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child then
            local cid = child.cooldownID
            if not cid and child.cooldownInfo then
                cid = child.cooldownInfo.cooldownID
            end
            if cid == cdID then return true end
        end
    end
    return false
end

--- One-time per-spec pass serving two purposes with the same logic: (1) legacy
--- migration of pre-refactor "assignedSpells as content filter" on default
--- CD/utility bars into the "ghost-bar diversion" model, preserving the
--- user's visual state; (2) import-authoritative ghosting (_importGhostMode):
--- a fresh import starts the ghost EMPTY, so this ghosts every importer-
--- tracked spell except what the layout assigns to a visible bar, so an
--- unplaced tracked cooldown hides instead of spilling onto the default bar.
--- Both reduce to: ghost (tracked) MINUS (assigned to any visible bar) MINUS
--- (already ghosted), over Essential + Utility categories.
--- Per-spec lazy (category APIs are spec-dependent); runs once via
--- prof._barFilterModelV6. Skipped when default bars have no populated
--- assignedSpells (clean install) UNLESS _importGhostMode is set.
--- Buff bars are NOT migrated: the old buff path's viewerBarKey fallback
--- already showed everything from BuffIconCooldownViewer regardless of
--- assignedSpells. Ghost buff bar cleanup is handled by EnsureGhostBars.
function ns.MigrateSpecToBarFilterModelV6()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return end

    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end

    local prof = sp[specKey]
    if not prof or prof._barFilterModelV6 then return end
    -- Never consume import ghosting in the import session: this pass reads the LIVE
    -- Blizzard CDM tracked set, which an installer that rewrites Blizzard's own layout
    -- leaves unlaundered until a reload -- so return without stamping and retry next
    -- session. Fail-open: unplaced spells stay visible until then.
    if prof._importGhostMode and EllesmereUI and EllesmereUI._cdmImportGhostDeferred then
        return
    end
    if not prof.barSpells then prof._barFilterModelV6 = true; return end

    local p = ECME.db and ECME.db.profile
    local barList = p and p.cdmBars and p.cdmBars.bars
    if type(barList) ~= "table" then return end

    -- Step 1: orphan cleanup -- drop spell data for bars that no longer exist
    local liveBarKeys = {
        ["cooldowns"]    = true,
        ["utility"]      = true,
        ["buffs"]        = true,
        ["__ghost_cd"]   = true,
    }
    for _, bd in ipairs(barList) do
        if bd.key then liveBarKeys[bd.key] = true end
    end
    for barKey in pairs(prof.barSpells) do
        if not liveBarKeys[barKey] then
            prof.barSpells[barKey] = nil
        end
    end

    -- Skip if both default CD/util bars are empty: nothing to preserve.
    -- EXCEPTION: imported layouts (_importGhostMode) always run -- a
    -- custom-bar-only layout still needs unplaced tracked spells ghosted.
    local cdBs = prof.barSpells.cooldowns
    local utBs = prof.barSpells.utility
    local hasCDList = cdBs and cdBs.assignedSpells and #cdBs.assignedSpells > 0
    local hasUTList = utBs and utBs.assignedSpells and #utBs.assignedSpells > 0
    if not hasCDList and not hasUTList and not prof._importGhostMode then
        prof._barFilterModelV6 = true
        return
    end

    -- Bail if viewer pools aren't populated yet -- migration must use the
    -- same source of truth as the route map; retry next session if empty.
    local function HasPopulatedPool()
        for _, vName in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
            local v = _G[vName]
            if v and v.itemFramePool and v.itemFramePool.EnumerateActive then
                for _ in v.itemFramePool:EnumerateActive() do
                    return true
                end
            end
        end
        return false
    end
    if not HasPopulatedPool() then return end

    -- Step 2: build assignedSet from the LIVE bar list. Default bars
    -- (cooldowns/utility) contribute too -- their assignedSpells under the
    -- new model is "preferred order / explicit assignment" and stay visible.
    local assignedSet = {}
    for _, bd in ipairs(barList) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
           and bd.key ~= "buffs" then
            local bs = prof.barSpells[bd.key]
            if bs and bs.assignedSpells then
                for _, sid in ipairs(bs.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        StoreVariantValue(assignedSet, sid, true, false)
                    end
                end
            end
        end
    end

    local ghostBs = prof.barSpells.__ghost_cd
    if not ghostBs then
        ghostBs = {}
        prof.barSpells.__ghost_cd = ghostBs
    end
    if not ghostBs.assignedSpells then ghostBs.assignedSpells = {} end

    local existingGhost = {}
    for _, sid in ipairs(ghostBs.assignedSpells) do
        if type(sid) == "number" and sid > 0 then
            StoreVariantValue(existingGhost, sid, true, false)
        end
    end

    -- Union of every CD/util spell to migrate: (1) LIVE viewer pools, catching
    -- per-spec/Edit Mode placements differing from static category; (2)
    -- STATIC category API, catching spells Blizzard currently hides by
    -- combat/buff/target state (e.g. Beacon of Light: always Essential for
    -- Holy Pally, but only pooled when relevant). Either alone misses spells.
    local sidUnion = {}  -- sid -> true (deduped)

    local entries = EnumerateCDMViewerSpells(false)
    for _, e in ipairs(entries) do
        if _IsUsableSID(e.sid) then sidUnion[e.sid] = true end
    end

    local gcs = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local evc = Enum and Enum.CooldownViewerCategory
    if gcs and gci and evc then
        -- Full CD/utility category set so SpecAgnosticEssential/EquipSlotEssential
        -- entries become ghost/migration candidates alongside Essential/Utility.
        for cat in pairs(ns.CDM_ICON_CD_CATS) do
            local cdIDs = gcs(cat, true)
            if cdIDs then
                for _, cdID in ipairs(cdIDs) do
                    local info = gci(cdID)
                    if info then
                        local sid = info.overrideSpellID or info.spellID
                        if _IsUsableSID(sid) then sidUnion[sid] = true end
                    end
                end
            end
        end
    end

    -- Walk the union, ghost anything that isn't already assigned or ghosted.
    local addedCount = 0
    for sid in pairs(sidUnion) do
        local isAssigned = ResolveVariantValue(assignedSet, sid)
        local isGhosted  = ResolveVariantValue(existingGhost, sid)
        if not isAssigned and not isGhosted then
            ghostBs.assignedSpells[#ghostBs.assignedSpells + 1] = sid
            StoreVariantValue(existingGhost, sid, true, false)
            addedCount = addedCount + 1
        end
    end

    prof._barFilterModelV6 = true
    prof._importGhostMode = nil  -- import-authoritative ghosting done for this spec
    return addedCount
end

--- One-shot per-spec migration: merge pre-existing dormantSpells back into
--- assignedSpells at their stored slot. The old reconcile model evicted
--- "currently-unknown" spells (pet abilities, choice-node talents) into
--- dormantSpells to preserve position; the new model treats assignedSpells
--- as pure user intent, never mutated by known-ness, so dormant entries must
--- fold back at their saved positions. Wipes sd.dormantSpells afterward.
--- Flagged per-spec via prof._dormantMerged (runs once).
function ns.MergeDormantSpellsIntoAssigned()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return end

    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end

    local prof = sp[specKey]
    if not prof or prof._dormantMerged then return end
    if not prof.barSpells then prof._dormantMerged = true; return end

    for _barKey, bs in pairs(prof.barSpells) do
        if type(bs) == "table" and type(bs.dormantSpells) == "table" then
            if not bs.assignedSpells then bs.assignedSpells = {} end

            -- Collect dormant entries sorted by saved slot (lowest first)
            -- so earlier inserts don't shift later slots.
            local returning = {}
            for sid, slot in pairs(bs.dormantSpells) do
                if type(sid) == "number" and sid ~= 0 and type(slot) == "number" then
                    returning[#returning + 1] = { sid = sid, slot = slot }
                end
            end
            table.sort(returning, function(a, b) return a.slot < b.slot end)

            -- Build dedup set for the active list so we don't double-insert
            local activeSet = {}
            for _, sid in ipairs(bs.assignedSpells) do activeSet[sid] = true end

            for _, entry in ipairs(returning) do
                if not activeSet[entry.sid] then
                    local insertAt = entry.slot
                    if insertAt > #bs.assignedSpells + 1 then insertAt = #bs.assignedSpells + 1 end
                    if insertAt < 1 then insertAt = 1 end
                    table.insert(bs.assignedSpells, insertAt, entry.sid)
                    activeSet[entry.sid] = true
                end
            end

            bs.dormantSpells = nil
        end
    end

    prof._dormantMerged = true
end

--- Lazy-seed assignedSpells from the bar's currently rendered icons. Called
--- by reorder helpers (Swap/Move) on an empty-assignedSpells bar to capture
--- the visible order so the reorder has something to manipulate.
local function EnsureBarOrderSeeded(barKey, sd)
    if sd.assignedSpells and #sd.assignedSpells > 0 then return end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    local icons = cdmBarIcons and cdmBarIcons[barKey]
    if not icons then return end
    local fcCache = ns._ecmeFC
    -- Buff-family bars seed by the DISPLAYED/canonical id (what per-icon
    -- settings and preview key off), not fc.spellID (cooldownInfo base /
    -- shared ability id for buffs). CD/utility keep fc.spellID since icon
    -- IS the ability there, so the two ids coincide.
    local isBuff = ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey)
    for i = 1, #icons do
        local icon = icons[i]
        if icon then
            local fc = fcCache and fcCache[icon]
            local sid
            if isBuff then
                sid = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon))
                    or (fc and fc.spellID)
            else
                sid = fc and fc.spellID
            end
            if type(sid) == "number" and sid > 0 then
                -- A hosted buff seeds as its MARKER: the plain id would register
                -- the same spell's COOLDOWN form on this bar.
                if fc and fc.isHostedBuff and ns.HostedBuffMarker then
                    sd.assignedSpells[#sd.assignedSpells + 1] = ns.HostedBuffMarker(sid)
                else
                    sd.assignedSpells[#sd.assignedSpells + 1] = sid
                end
            end
        end
    end
end

--- Swap two tracked spell positions
function ns.SwapTrackedSpells(barKey, idx1, idx2)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    EnsureBarOrderSeeded(barKey, sd)
    local t = sd.assignedSpells
    if idx1 < 1 or idx2 < 1 then return false end
    local maxIdx = math.max(idx1, idx2)
    while #t < maxIdx do t[#t + 1] = 0 end
    t[idx1], t[idx2] = t[idx2], t[idx1]
    while #t > 0 and (t[#t] == 0 or t[#t] == nil) do t[#t] = nil end
    ns._spellOrderDirty = true
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Move a tracked spell from one position to another (insert, not swap)
function ns.MoveTrackedSpell(barKey, fromIdx, toIdx)
    if fromIdx == toIdx then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    EnsureBarOrderSeeded(barKey, sd)
    local t = sd.assignedSpells
    if fromIdx < 1 or fromIdx > #t then return false end
    if toIdx < 1 then toIdx = 1 end
    while #t < toIdx do t[#t + 1] = 0 end
    local val = table.remove(t, fromIdx)
    table.insert(t, toIdx, val)
    while #t > 0 and (t[#t] == 0 or t[#t] == nil) do t[#t] = nil end
    ns._spellOrderDirty = true
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Stable display-order key for a Blizzard-tracked buff (cooldownID) or custom.
local function BuffDisplayStableKey(sid, cdID)
    if type(cdID) == "number" then return "c" .. cdID end
    if type(sid) == "number" and sid > 0 then return "s" .. sid end
    return nil
end
ns.BuffDisplayStableKey = BuffDisplayStableKey

--- Spell ids associated with a stored buffDisplayOrder key ("c"..cdID / "s"..sid).
local function SpellIdsForBuffOrderKey(key)
    if type(key) ~= "string" then return nil end
    local pfx, num = string.sub(key, 1, 1), tonumber(string.sub(key, 2))
    if not num or num <= 0 then return nil end
    if pfx == "s" then return num end
    if pfx == "c" and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(num)
        if not info then return nil end
        if _IsUsableSID(info.overrideSpellID) then return info.overrideSpellID end
        if _IsUsableSID(info.spellID) then return info.spellID end
    end
    return nil
end

--- True when a live buff entry matches a stored buffDisplayOrder key, including
--- hero-talent / override variants (cooldownID can drift across talent swaps).
local function BuffOrderKeyMatchesEntry(key, sid, cdID, frame)
    if not key then return false end
    local stable = BuffDisplayStableKey(sid, cdID)
    if stable and stable == key then return true end
    local storedSid = SpellIdsForBuffOrderKey(key)
    if not storedSid then return false end
    if sid and IsVariantOf(storedSid, sid) then return true end
    if frame and ns.GetCanonicalSpellIDForFrame then
        local canon = ns.GetCanonicalSpellIDForFrame(frame)
        if canon and IsVariantOf(storedSid, canon) then return true end
    end
    if cdID and type(cdID) == "number" and ns._cdmCleanSidByCDID then
        local clean = ns._cdmCleanSidByCDID[cdID]
        if clean and IsVariantOf(storedSid, clean) then return true end
    end
    return false
end

--- Enumerate default-buffs-bar entries (viewer pool + this bar's customs/items),
--- minus spells diverted to other buff-family or hosted CD/utility bars.
function ns.CollectDefaultBuffTrackEntries()
    -- Variant-aware (base/override family), not a plain sid set: a claimed
    -- buff's stored id and the id this same viewer slot enumerates as later
    -- can legitimately differ (a talent-override swap, or a fresh clean-cache
    -- forcing GetCanonicalSpellIDForFrame down its cooldownInfo fallback --
    -- see the comment there). An exact-number set misses that drift and the
    -- claimed buff reappears here as a phantom duplicate of the other bar's
    -- entry. StoreVariantValue/ResolveVariantValue are the same mechanism
    -- RebuildSpellRouteMap and ns.GetCDMSpellsForBar already use to answer
    -- "is this the same buff" everywhere else in this file.
    local diverted = {}
    local divertedCd = {}  -- cooldownID-level diversions (collided-buff slots)
    local p = ECME and ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.bars then
        for _, otherBd in ipairs(p.cdmBars.bars) do
            if otherBd.enabled and otherBd.key ~= "buffs" then
                local otherSd = ns.GetBarSpellData(otherBd.key)
                if otherBd.barType == "buffs" or otherBd.barType == "custom_buff" then
                    if otherSd and otherSd.assignedSpells then
                        for _, sid in ipairs(otherSd.assignedSpells) do
                            if type(sid) == "number" and sid > 0 then
                                StoreVariantValue(diverted, sid, true, false)
                            end
                        end
                    end
                    local otherClaims = otherSd and ns.CollectCdClaimSet(otherSd)
                    if otherClaims then
                        for cdID in pairs(otherClaims) do divertedCd[cdID] = true end
                    end
                elseif otherSd and otherSd.hostedBuffSpellIDs then
                    for sid in pairs(otherSd.hostedBuffSpellIDs) do
                        if type(sid) == "number" and sid > 0 then
                            StoreVariantValue(diverted, sid, true, false)
                        end
                    end
                end
            end
        end
    end

    if ns.PruneEquipmentBuffRows then ns.PruneEquipmentBuffRows() end
    local out = {}
    local seen = {}
    local entries = ns.EnumerateCDMViewerSpells and ns.EnumerateCDMViewerSpells(true) or {}
    for _, e in ipairs(entries) do
        -- Dedup on the stable (cooldownID-derived) key, not e.sid: two viewer
        -- slots can share a spellID but are distinct cooldownIDs; keying on
        -- sid would re-merge what EnumerateCDMViewerSpells keeps separate.
        local key = BuffDisplayStableKey(e.sid, e.cdID)
        -- Native equipment ON-USE rows (equipSlot + category EquipSlotEssential)
        -- are preset-lane-only: never surface them as default-bar buff entries.
        -- Tracked trinket PROC BUFF rows (equipSlot + category EquipSlotTracked)
        -- are first-class buff citizens (user directive 2026-08-16): Blizzard's
        -- CDM lets users track a trinket's buff like any spell, and our buff
        -- bars must mirror that. Field-probed 2026-08-16: buffSlot=1 rides
        -- BOTH categories (and plain cat-2 rows), so CATEGORY is the only
        -- reliable discriminator.
        local eqInfo = e.cdID and C_CooldownViewer
            and C_CooldownViewer.GetCooldownViewerCooldownInfo
            and C_CooldownViewer.GetCooldownViewerCooldownInfo(e.cdID)
        local eqTracked = Enum and Enum.CooldownViewerCategory
            and Enum.CooldownViewerCategory.EquipSlotTracked or 8
        if e.sid and not (eqInfo and eqInfo.equipSlot and eqInfo.category ~= eqTracked)
           and not ResolveVariantValue(diverted, e.sid)
           and not (e.cdID and divertedCd[e.cdID])
           and key and not seen[key] then
            seen[key] = true
            out[#out + 1] = {
                key         = key,
                sid         = e.sid,
                cdID        = e.cdID,
                layoutIndex = e.layoutIndex or 0,
            }
        end
    end

    local sdSelf = ns.GetBarSpellData("buffs")
    if sdSelf and sdSelf.assignedSpells then
        local extra = 5000
        if sdSelf.spellDurations then
            for _, sid in ipairs(sdSelf.assignedSpells) do
                if type(sid) == "number" and sid > 0 and (sdSelf.spellDurations[sid] or 0) > 0 then
                    local key = BuffDisplayStableKey(sid, nil)
                    if key and not seen[key] then
                        seen[key] = true
                        out[#out + 1] = { key = key, sid = sid, cdID = nil, layoutIndex = extra }
                        extra = extra + 1
                    end
                end
            end
        end
        -- Aura-tracked customs (customSpellIDs tag, NO stored duration): same
        -- slot treatment as the legacy cast-timer customs above.
        if sdSelf.customSpellIDs then
            for _, sid in ipairs(sdSelf.assignedSpells) do
                if type(sid) == "number" and sid > 0 and sdSelf.customSpellIDs[sid]
                   and not (sdSelf.spellDurations and (sdSelf.spellDurations[sid] or 0) > 0) then
                    local key = BuffDisplayStableKey(sid, nil)
                    if key and not seen[key] then
                        seen[key] = true
                        out[#out + 1] = { key = key, sid = sid, cdID = nil, layoutIndex = extra }
                        extra = extra + 1
                    end
                end
            end
        end
        extra = 6000
        for _, sid in ipairs(sdSelf.assignedSpells) do
            if type(sid) == "number" and sid <= -100 then
                local key = BuffDisplayStableKey(sid, nil)
                if key and not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { key = key, sid = sid, cdID = nil, layoutIndex = extra }
                    extra = extra + 1
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return (a.key or "") < (b.key or "")
    end)
    return out
end

-- Same-spellID buff disambiguation (e.g. Diabolist: Demonic Art vs Diabolic Ritual):
-- Blizzard can report the SAME spellID on two DIFFERENT buff-viewer cooldownIDs,
-- colliding onto one spellID-keyed settings entry. A COLLIDED slot keys by
-- "c"..cooldownID instead, giving each its own entry -- non-collided buffs keep spellID
-- (survives talent swaps; cooldownID drifts). Collided slots trade that: session-stable
-- but may not follow a talent-loadout swap, unavoidable given the shared identity.

--- Set of canonical spellIDs that map to 2+ distinct buff-viewer cooldownIDs.
--- Cold path (settings popup); recomputed per call from the live viewer pool.
function ns.CollidedBuffSids()
    local counts, out = {}, {}
    local entries = ns.EnumerateCDMViewerSpells and ns.EnumerateCDMViewerSpells(true) or {}
    for _, e in ipairs(entries) do
        if e.sid and type(e.cdID) == "number" then
            counts[e.sid] = (counts[e.sid] or 0) + 1
        end
    end
    for sid, n in pairs(counts) do if n > 1 then out[sid] = true end end
    return out
end

function ns.IsCollidedBuffSid(sid)
    if type(sid) ~= "number" or sid <= 0 then return false end
    return ns.CollidedBuffSids()[sid] == true
end

-- Runtime hot-path gate: true only when the current spec's buffs store holds at least
-- one "c"..cooldownID key. Cached by store-table identity, so a spec/profile swap
-- (different store table) recomputes for free with no explicit invalidation hook.
local _cdKeyGate
function ns.BuffFamHasCdKey(store)
    -- Accept caller's store (runtime resolver already holds it) to skip a
    -- second spec/profile lookup per buff-frame resolve.
    store = store or (ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs"))
    if not store then return false end
    if _cdKeyGate and _cdKeyGate.store == store then return _cdKeyGate.has end
    local hit = false
    for k in pairs(store) do
        if type(k) == "string" and string.byte(k, 1) == 99 then hit = true; break end  -- 'c'
    end
    _cdKeyGate = { store = store, has = hit }
    return hit
end

--- Called when a "c"..cooldownID buff entry is first persisted, so the hot-path
--- gate flips on without waiting for the store-identity cache to expire.
function ns.MarkBuffFamHasCdKey()
    local store = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs")
    _cdKeyGate = { store = store, has = true }
    -- The cdID-key gate feeds resolution: retire memoized results.
    ns._cdmResGen = (ns._cdmResGen or 0) + 1
end

--- Reorder present keys to match Blizzard viewer order while absent keys (talent
--- gaps, untalented catalog entries) keep their stored slots.
local function SyncPresentBuffOrderToBlizzard(order, present, entries)
    if not order or #order == 0 or not entries or #entries == 0 then return order end
    local blizzRank = {}
    for i, e in ipairs(entries) do
        if blizzRank[e.key] == nil then blizzRank[e.key] = i end
    end
    local sortedPresent = {}
    for _, key in ipairs(order) do
        if present[key] then sortedPresent[#sortedPresent + 1] = key end
    end
    table.sort(sortedPresent, function(a, b)
        return (blizzRank[a] or 99999) < (blizzRank[b] or 99999)
    end)
    local pi = 1
    local synced = {}
    for _, key in ipairs(order) do
        if present[key] then
            synced[#synced + 1] = sortedPresent[pi]
            pi = pi + 1
        else
            synced[#synced + 1] = key
        end
    end
    return synced
end

--- Dirty flag gating the reconcile in the hot reanchor path: the tracked
--- CATALOG (viewer pool incl. inactive + diversions) only changes on rebuild/
--- repopulate, not on mere buff appear/disappear, so combat reanchors skip
--- the full enumeration/sort. Set true wherever composition can change
--- (FullCDMRebuild, RepopulateFromBlizzard); an unreconciled newcomer still
--- renders via the layoutIndex spillover fallback until the next rebuild.
--- Starts true for the login seed pass.
ns._cdmBuffOrderDirty = true

--- Keep stored buffDisplayOrder across talent/spec gaps, seed on first stable
--- pass, and insert newly-tracked buffs by Blizzard layoutIndex (not at tail).
function ns.ReconcileBuffDisplayOrder()
    if ns._cdmSpecRebuildStale then return end
    local sd = ns.GetBarSpellData("buffs")
    if not sd then return end

    local order = sd.buffDisplayOrder
    if order and type(order[1]) == "number" then
        sd.buffDisplayOrder = nil
        order = nil
    end

    local entries = ns.CollectDefaultBuffTrackEntries()
    if #entries == 0 then return end

    local present = {}
    for _, e in ipairs(entries) do
        if present[e.key] == nil then
            present[e.key] = { sid = e.sid, cdID = e.cdID, layoutIndex = e.layoutIndex or 0 }
        end
    end

    if not order or #order == 0 then
        local seeded = {}
        for _, e in ipairs(entries) do seeded[#seeded + 1] = e.key end
        sd.buffDisplayOrder = seeded
        ns._spellOrderDirty = true
        return
    end

    local newOrder, seen = {}, {}
    for _, key in ipairs(order) do
        if not seen[key] then
            seen[key] = true
            newOrder[#newOrder + 1] = key
        end
    end

    local newcomers = {}
    for _, e in ipairs(entries) do
        if not seen[e.key] then
            newcomers[#newcomers + 1] = e
        end
    end
    if #newcomers > 0 then
        table.sort(newcomers, function(a, b)
            if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
            return (a.key or "") < (b.key or "")
        end)
        local blizzRank = {}
        for i, e in ipairs(entries) do blizzRank[e.key] = i end
        for _, e in ipairs(newcomers) do
            local insertAt = #newOrder + 1
            for i, key in ipairs(newOrder) do
                local rank = blizzRank[key]
                if rank and rank > blizzRank[e.key] then
                    insertAt = i
                    break
                end
            end
            table.insert(newOrder, insertAt, e.key)
            seen[e.key] = true
        end
    end

    if not sd._buffDisplayOrderUserModified then
        newOrder = SyncPresentBuffOrderToBlizzard(newOrder, present, entries)
    end

    local changed = (#newOrder ~= #order)
    if not changed then
        for i = 1, #newOrder do
            if newOrder[i] ~= order[i] then changed = true; break end
        end
    end
    if changed then
        sd.buffDisplayOrder = newOrder
        ns._spellOrderDirty = true
    end
end

--- Resolve a buff bar entry's sort index from buffDisplayOrder (variant-aware).
function ns.ResolveBuffDisplaySortIndex(entry, buffOrder, isDefaultBuffs)
    if not buffOrder or not entry then return nil end
    if isDefaultBuffs then
        local cd = entry.frame and entry.frame.cooldownID
        local sid = entry.spellID
        -- Steady state: direct stable-key match, O(1) zero-alloc. The variant
        -- scan below allocates per miss (calls GetCooldownViewerCooldownInfo),
        -- so it's reserved for genuine talent-gap frames whose cooldownID drifted.
        local stable = BuffDisplayStableKey(sid, cd)
        local direct = stable and buffOrder[stable]
        if direct then return direct end
        for key, idx in pairs(buffOrder) do
            if BuffOrderKeyMatchesEntry(key, sid, cd, entry.frame) then return idx end
        end
        return nil
    end
    local ef = entry.frame
    -- Collided-buff slot (cd-claim marker, see ns.CdClaimMarker): both runtime
    -- frames of the pair share one spellID, so a spellID-keyed lookup can't
    -- tell them apart. Check cooldownID first (same stable-key convention as
    -- the isDefaultBuffs branch above).
    local cdKey = ef and ef.cooldownID and BuffDisplayStableKey(nil, ef.cooldownID)
    if cdKey and buffOrder[cdKey] then return buffOrder[cdKey] end
    local canon = ef and ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(ef)
    return (canon and buffOrder[canon])
        or (entry.spellID and buffOrder[entry.spellID])
        or (entry.baseSpellID and buffOrder[entry.baseSpellID])
end

--- Default buffs bar DISPLAY-ORDER reorder helpers. assignedSpells is shared
--- with routing + custom injection (RebuildSpellRouteMap Pass 4 diverts it at
--- highest priority), so it can't carry the full buff order without
--- clobbering diverted buffs. Order instead lives in buffDisplayOrder: an
--- array of STABLE keys ("c"..cooldownID for Blizzard buffs, "s"..spellID for
--- customs) that only sort/preview/drag read -- routing never touches it.
--- cooldownID (not spellID) is used because a buff's canonical id flips
--- between ability/aura form across active<->inactive.
--- KEY-BASED, not index-based: ABSENT keys keep their slot (talent-gapped
--- buffs reclaim position on return); preview renders only PRESENT keys, so a
--- slot index doesn't map 1:1 onto the array past any gap. Callers pass
--- rendered slots' stable keys (pf._buffSlotKeys), resolved live at call time.
local function BuffOrderIndexOf(t, key)
    for i = 1, #t do
        if t[i] == key then return i end
    end
    return nil
end

local function FinishBuffOrderWrite(sd)
    sd._buffDisplayOrderUserModified = true
    ns._spellOrderDirty = true
    local frame = cdmBarFrames["buffs"]
    if frame then frame._blizzCache = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
end

function ns.SwapBuffDisplayKeys(key1, key2)
    if not key1 or not key2 or key1 == key2 then return false end
    local sd = ns.GetBarSpellData("buffs")
    local t = sd and sd.buffDisplayOrder
    if not t then return false end
    local i1, i2 = BuffOrderIndexOf(t, key1), BuffOrderIndexOf(t, key2)
    if not i1 or not i2 then return false end
    t[i1], t[i2] = t[i2], t[i1]
    FinishBuffOrderWrite(sd)
    return true
end

--- Move dragKey so it renders immediately before beforeKey; nil beforeKey
--- appends after everything (drop past the last rendered slot).
function ns.MoveBuffDisplayKey(dragKey, beforeKey)
    if not dragKey or dragKey == beforeKey then return false end
    local sd = ns.GetBarSpellData("buffs")
    local t = sd and sd.buffDisplayOrder
    if not t then return false end
    local from = BuffOrderIndexOf(t, dragKey)
    if not from then return false end
    local val = table.remove(t, from)
    local to
    if beforeKey then to = BuffOrderIndexOf(t, beforeKey) end
    if not to then to = #t + 1 end
    table.insert(t, to, val)
    FinishBuffOrderWrite(sd)
    return true
end

--- Single source of truth for "what type is this bar" / "what family is it in".
--- The 3 default bars have barType stamped in DEFAULTS, but legacy installs
--- may have nil barType; both helpers fall back to key-based inference.
--- Accepts either a bar key (string) or a bar data table (.key/.barType).
local function ResolveBarType(bdOrKey)
    local bd, key
    if type(bdOrKey) == "table" then
        bd  = bdOrKey
        key = bd.key
    else
        key = bdOrKey
        bd  = barDataByKey[key]
    end

    if bd and bd.barType then return bd.barType end

    if key == "cooldowns" then return "cooldowns" end
    if key == "utility"   then return "utility"   end
    if key == "buffs"     then return "buffs"     end

    return nil
end
ns.GetBarType = ResolveBarType

--- True if a bar is in the "buff" family (default buffs bar or ghost buffs
--- bar; custom_buff is NOT a buff bar, it's a separate aura system). Used by
--- AddTrackedSpell's auto-move sweep, render path, route map, and picker
--- source selection. __ghost_cd is always non-buff family.
local function IsBarBuffFamily(bdOrKey)
    local bd, key
    if type(bdOrKey) == "table" then
        bd  = bdOrKey
        key = bd.key
    else
        key = bdOrKey
        bd  = barDataByKey[key]
    end

    if key == "__ghost_cd" then return false end

    local barType = ResolveBarType(bd or key)
    return barType == "buffs"
end
ns.IsBarBuffFamily = IsBarBuffFamily

-- Old local alias for backward compat within this file
local GetBarType = ResolveBarType

-- Centralized Spell Assignment Checks -- used by pickers, overlay system,
-- and options: (1) is a spell already on ANY bar (CDM + TBB)? (2) is a
-- spell tracked in the correct Blizzard CDM section for a bar type?

-- (SpellUsedOnAnyOtherBar deleted: unneeded for CD/util/buff custom bar
-- pickers since AddTrackedSpell auto-moves the spell from any other bar in
-- the same family -- adding is always a "claim it", never a "blocked" case.)

--- Same check for TBB (Tracking Bars vs other Tracking Bars only). trackType
--- scopes to one family: nil/"buff" = buff bars, "cooldown" = cooldown bars.
--- A different track type never blocks a pick (distinct, legitimate picks).
function ns.SpellUsedOnAnyOtherTBB(spellID, excludeIdx, trackType)
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if not tbb or not tbb.bars then return nil end
    for i, cfg in ipairs(tbb.bars) do
        if i ~= excludeIdx then
            if (cfg.trackType or "buff") ~= (trackType or "buff") then
                -- Different track type never blocks a pick.
            else
                if cfg.spellID and cfg.spellID == spellID then
                    return cfg.name or ("Tracking Bar " .. i)
                end
                if cfg.spellIDs then
                    for _, sid in ipairs(cfg.spellIDs) do
                        if sid == spellID then return cfg.name or ("Tracking Bar " .. i) end
                    end
                end
            end
        end
    end
    return nil
end

--- Check if a spell is tracked in the correct Blizzard CDM section for a bar
--- type (true = properly tracked, no popup/overlay needed): CD/utility bar
--- needs Essential/Utility viewer; buff bar needs BuffIcon viewer (not just
--- Tracked Bars); TBB needs BuffBar viewer (not just Tracked Buffs).
--- Cached lookup sets, rebuilt once per RebuildCDMSpellCaches() call instead
--- of full category scans per-frame.
local _knownSpellSet = {}    -- learned spells (cat, false)
local _allSpellSet = {}      -- all spells including unlearned (cat, true)
local _cdmSpellCacheDirty = true

function ns.MarkCDMSpellCacheDirty()
    _cdmSpellCacheDirty = true
end

local function RebuildCDMSpellCaches()
    if not _cdmSpellCacheDirty then return end
    _cdmSpellCacheDirty = false
    wipe(_knownSpellSet)
    wipe(_allSpellSet)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return end
    local gci = C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return end
    for cat = 0, 3 do
        local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)
        if knownIDs then
            for _, cdID in ipairs(knownIDs) do
                local info = gci(cdID)
                if info then
                    if info.spellID and info.spellID > 0 then
                        _knownSpellSet[info.spellID] = true
                    end
                    if info.overrideSpellID and info.overrideSpellID > 0 then
                        _knownSpellSet[info.overrideSpellID] = true
                    end
                    local sid = ns.ResolveInfoSpellID(info)
                    if sid and sid > 0 then _knownSpellSet[sid] = true end
                end
            end
        end
        local allIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if allIDs then
            for _, cdID in ipairs(allIDs) do
                local info = gci(cdID)
                if info then
                    if info.spellID and info.spellID > 0 then
                        _allSpellSet[info.spellID] = true
                    end
                    if info.overrideSpellID and info.overrideSpellID > 0 then
                        _allSpellSet[info.overrideSpellID] = true
                    end
                    local sid = ns.ResolveInfoSpellID(info)
                    if sid and sid > 0 then _allSpellSet[sid] = true end
                end
            end
        end
    end
end
ns.RebuildCDMSpellCaches = RebuildCDMSpellCaches

function ns.IsSpellKnownInCDM(spellID)
    if not spellID or spellID <= 0 then return false end
    RebuildCDMSpellCaches()
    return _knownSpellSet[spellID] == true
end

function ns.IsSpellInAnyCDMCategory(spellID)
    if not spellID or spellID <= 0 then return false end
    RebuildCDMSpellCaches()
    return _allSpellSet[spellID] == true
end

--- Add a preset group to a bar. custom_buff bars: adds ALL spell IDs as plain
--- entries (each gets its own C_UnitAuras check -- only the active variant
--- shows). Other bars: adds primary ID with duration/group metadata.
function ns.AddPresetToBar(barKey, preset)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    local spellList = sd.assignedSpells

    -- Buff-family bars use the same cast-timer custom-buff path as custom_buff
    -- (Auras) bars: store primary spellID + hardcoded duration; the buff
    -- phase injects an own-frame and the buff tick drives it.
    local bd = barDataByKey[barKey]
    local isCustomBuff = bd and (bd.barType == "custom_buff" or bd.barType == "buffs")

    if isCustomBuff then
        if preset.glowBased then
            -- Glow-based presets removed (Time Spiral etc.)
            return false
        else
            -- Check ALL preset members against existing spells so partial
            -- overlap is rejected (e.g. variant 701 already on bar blocks
            -- adding preset {700, 701, 702}).
            for _, sid in ipairs(preset.spellIDs) do
                for _, existing in ipairs(spellList) do
                    if existing == sid then return false, "exists" end
                end
            end
            local primaryID = preset.spellIDs[1]
            spellList[#spellList + 1] = primaryID
            if not sd.spellDurations then sd.spellDurations = {} end
            sd.spellDurations[primaryID] = preset.duration or 30
        end
    else
        -- Legacy: add primary ID with duration/group metadata
        local primaryID = preset.spellIDs[1]
        for _, existing in ipairs(spellList) do
            if existing == primaryID then return false, "exists" end
        end
        spellList[#spellList + 1] = primaryID
        if not sd.customSpellDurations then sd.customSpellDurations = {} end
        sd.customSpellDurations[primaryID] = preset.duration
        if not sd.customSpellGroups then sd.customSpellGroups = {} end
        for _, sid in ipairs(preset.spellIDs) do
            sd.customSpellGroups[sid] = primaryID
        end
    end

    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    return true
end

--- Is any member of this preset already on the bar? The inverse of the "exists"
--- guard above, so the picker greys exactly what an add would reject: a preset
--- with variant ids (the invisibility potions, the two faction lust ids) counts
--- as present no matter which member is stored.
function ns.IsPresetOnBar(barKey, preset)
    local sd = ns.GetBarSpellData(barKey)
    local spellList = sd and sd.assignedSpells
    if not spellList or type(preset.spellIDs) ~= "table" then return false end
    for _, sid in ipairs(preset.spellIDs) do
        for _, existing in ipairs(spellList) do
            if existing == sid then return true end
        end
    end
    return false
end

--- Add a tracked spell (spellID) to a bar. Picker-driven add: always treated
--- as "claim this spell for the target bar" -- auto-removed from EVERY other
--- bar in the same family (default + custom + matching ghost) first. One
--- spell, one home, always. Picker passes IDs from GetCanonicalSpellIDForFrame
--- (already in route-map/reanchor form; no override-to-base normalization
--- needed here).
function ns.AddTrackedSpell(barKey, id)
    -- Non-zero integer required. Positive = real spell; negative = injection
    -- marker Phase 3 of CollectAndReanchor uses for custom frames (trinkets
    -- at -13/-14, item presets at <= -100) -- both valid.
    if type(id) ~= "number" or id == 0 then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end

    -- Dedup against THIS bar: variant-aware for positive IDs; exact-match
    -- linear scan for negatives (FindVariantIndex bails on non-positives).
    if id > 0 then
        if FindVariantIndex(sd.assignedSpells, id) then return false end
    else
        for _, existing in ipairs(sd.assignedSpells) do
            if existing == id then return false end
        end
    end

    -- Auto-move from any other bar in the same family: a spell has ONE home
    -- at a time, so adding to bar X removes it from every other bar in the
    -- family (incl. ghost, so a hidden spell auto-restores when claimed
    -- elsewhere). Family = ns.IsBarBuffFamily; custom_buff bars are a
    -- separate system, never swept. Negative IDs sweep within whichever
    -- family the target bar belongs to (no positivity gate): trinkets stay
    -- on CD/util bars, custom items sweep only their own family.
    local targetBd = barDataByKey[barKey]
    local p = ECME.db.profile
    local targetIsBuff = IsBarBuffFamily(barKey)
    if p and p.cdmBars and p.cdmBars.bars then
        for _, b in ipairs(p.cdmBars.bars) do
            if b.key ~= barKey and b.barType ~= "custom_buff" then
                if IsBarBuffFamily(b) == targetIsBuff then
                    ns.RemoveSpellFromBar(b.key, id)
                end
            end
        end
    end

    -- Top-row insertion for multi-row bars.
    local curCount = #sd.assignedSpells
    local stride, _, topRowCount = ComputeTopRowStride(targetBd or {}, curCount)
    if stride < 1 then stride = 1 end
    local newCount = curCount + 1
    local newStride, _, newTopRow = ComputeTopRowStride(targetBd or {}, newCount)
    if newStride < 1 then newStride = 1 end
    if newStride == stride and newTopRow > topRowCount then
        table.insert(sd.assignedSpells, topRowCount + 1, id)
    else
        sd.assignedSpells[newCount] = id
    end
    ns._spellOrderDirty = true

    if sd.removedSpells then sd.removedSpells[id] = nil end

    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Track a single buff-viewer SLOT (cooldownID) on a buff-family bar.
--- Collision escape hatch: two viewer slots can share one spellID, making
--- AddTrackedSpell's variant dedup reject the second slot by sid. Claiming via
--- a cd-claim MARKER (ns.CdClaimMarker, distinct negative id per cooldownID)
--- sidesteps that while reusing AddTrackedSpell's plumbing unchanged, and
--- gives the claim a real assignedSpells index (drags/reorders/removes like
--- any entry). Collision-gated: non-collided buffs keep the sid path
--- (survives talent swaps). Never valid on the default "buffs" bar, which
--- enumerates the live viewer pool directly, never assignedSpells.
function ns.AddTrackedBuffByCdID(barKey, cdID)
    if type(cdID) ~= "number" or cdID <= 0 or barKey == "buffs" then return false end
    return ns.AddTrackedSpell(barKey, ns.CdClaimMarker(cdID))
end

function ns.RemoveTrackedBuffCdID(barKey, cdID)
    if type(cdID) ~= "number" then return false end
    -- RemoveSpellFromBar doesn't itself trigger route/reanchor; caller must.
    local removed = ns.RemoveSpellFromBar(barKey, ns.CdClaimMarker(cdID))
    if not removed then return false end
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Place a BUFF on a CD/utility bar. HOSTED: RebuildSpellRouteMap diverts its
--- real Blizzard buff-viewer frame onto this bar; reanchor reparents it into
--- the layout when active / a placeholder when inactive -- like the buffs bar,
--- just on CD/util. Blizzard's CDM stays the source of truth, so auras, DoTs,
--- totems and pet-summons all work with no detection code. NOT a custom
--- injected spell -- Phase 3 must never draw its own frame for it. Additive:
--- only our own data table is written (variant-keyed).
function ns.AddBuffToCDUtilBar(barKey, spellID)
    if type(spellID) ~= "number" or spellID <= 0 then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    -- Already hosted (marker entry, or legacy plain entry pre-marker model): no-op.
    if sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[spellID] and sd.assignedSpells
       and (ns.ListHasHostedMarker(sd.assignedSpells, spellID)
            or ns.FindVariantIndexInList(sd.assignedSpells, spellID)) then
        return true
    end
    -- Claim via the hosted MARKER, never the plain spellID (the COOLDOWN
    -- form's identity; one spell can be both cooldown and buff, same id).
    -- The marker gives the buff its own slot to coexist and reorder
    -- independently; AddTrackedSpell auto-moves it off other CD/util bars.
    ns.AddTrackedSpell(barKey, ns.HostedBuffMarker(spellID))
    -- Flag keyed by picked/canonical spellID so route-map/drop-pass/self-heal
    -- match it directly; the route map expands variants on write, so the
    -- LIVE frame resolves regardless of talent/override form.
    if not sd.hostedBuffSpellIDs then sd.hostedBuffSpellIDs = {} end
    sd.hostedBuffSpellIDs[spellID] = true
    -- Host flip changes resolution routing: retire memoized results.
    ns._cdmResGen = (ns._cdmResGen or 0) + 1
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Host a single collided-buff SLOT (cooldownID) on a CD/util bar. Same
--- collision escape hatch as ns.AddTrackedBuffByCdID: two viewer slots can
--- share one canonical spellID, so AddBuffToCDUtilBar's spellID-keyed
--- idempotency guard would treat the second slot as "already hosted" and
--- silently no-op it. Claiming by the cd-claim MARKER sidesteps that, reusing
--- AddTrackedSpell's plumbing unchanged. Collision-gated by the caller:
--- non-collided buffs keep AddBuffToCDUtilBar's sid path (survives talent
--- swaps).
function ns.AddHostedBuffByCdID(barKey, cdID)
    if type(cdID) ~= "number" or cdID <= 0 then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    -- Empty-table sentinel: ResolveSpellSettings' hostedFrame gate
    -- (EllesmereUICdmHooks.lua) short-circuits on this table being non-nil to
    -- skip pricier frame-flag checks. A cd-claimed hosted buff resolves its
    -- own "c"..cooldownID key independently -- only the table's existence matters.
    sd.hostedBuffSpellIDs = sd.hostedBuffSpellIDs or {}
    return ns.AddTrackedSpell(barKey, ns.CdClaimMarker(cdID))
end

function ns.RemoveHostedBuffByCdID(barKey, cdID)
    if type(cdID) ~= "number" then return false end
    -- RemoveSpellFromBar doesn't itself trigger route/reanchor; caller must.
    local removed = ns.RemoveSpellFromBar(barKey, ns.CdClaimMarker(cdID))
    if not removed then return false end
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Remove a tracked spell by index. Routes positive viewer spells to the
--- ghost CD bar so they stay in the routing system but are hidden.
--- Picker-driven remove path. Wraps RemoveSpellFromBar.
function ns.RemoveTrackedSpell(barKey, idx)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    local list = sd.assignedSpells
    if not list or idx < 1 or idx > #list then return false end
    local removedID = list[idx]
    table.remove(list, idx)
    ns._spellOrderDirty = true

    -- Hosted-buff removal? Entry is a MARKER, or a legacy plain entry
    -- representing the buff (flag set, no marker in list). A plain entry
    -- WITH a marker present is the same spell's COOLDOWN slot -- buff stays.
    local hostedSid = removedID and ns.HostedBuffMarkerToSpell(removedID)
    if not hostedSid and removedID and removedID > 0
       and sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[removedID]
       and not ns.ListHasHostedMarker(list, removedID) then
        hostedSid = removedID
    end
    if hostedSid then
        -- Un-host: clear the flag so the route map stops diverting here (buff
        -- returns to the buffs bar). Never ghost-route a hosted buff -- the
        -- ghost bar hides by spellID, hiding the COOLDOWN form everywhere too.
        if sd.hostedBuffSpellIDs then
            sd.hostedBuffSpellIDs[hostedSid] = nil
            -- Host flip changes resolution routing: retire memoized results.
            ns._cdmResGen = (ns._cdmResGen or 0) + 1
        end
    else
        -- Auxiliary metadata cleanup, mirroring RemoveSpellFromBar's side
        -- effects for symmetry with index-based removal.
        if removedID and sd.customSpellDurations then sd.customSpellDurations[removedID] = nil end
        if removedID and sd.spellDurations       then sd.spellDurations[removedID]       = nil end
        if removedID and sd.customSpellIDs       then sd.customSpellIDs[removedID]       = nil end
        if removedID and sd.customSpellGroups then
            for variantID, primaryID in pairs(sd.customSpellGroups) do
                if primaryID == removedID then sd.customSpellGroups[variantID] = nil end
            end
        end

        -- Route to the ghost CD bar so frames stay routed but hidden. Buff-family bars
        -- don't ghost (visibility managed by Blizzard's CDM settings); negative IDs and
        -- non-viewer spells (customs) skip ghost routing entirely.
        -- RACIALS GHOST like any viewer spell (changed 2026-08-13): 12.1's native
        -- racial tracking gives them a PERSISTENT live viewer frame, so a removed
        -- racial without a ghost is instantly re-added by the live-icon append on
        -- the next options refresh -- remove appeared to do nothing (field: dwarf
        -- Stoneform 20594 unremovable). The old skip was a pre-native fossil: back
        -- then no frame existed to re-add from, and removal alone stopped the
        -- injection lane. Customs still skip: those frames are OURS, not viewer pool.
        local isNonViewer = removedID and removedID > 0
            and (sd.customSpellIDs and sd.customSpellIDs[removedID])
        if removedID and removedID > 0 and not isNonViewer
           and not IsBarBuffFamily(barKey) then
            ns.AddSpellToBar(ns.GHOST_CD_BAR_KEY, removedID)
        end
    end

    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Replace a tracked spell at a given index with a new spellID
function ns.ReplaceTrackedSpell(barKey, idx, newID)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    local list = sd.assignedSpells
    if idx < 1 then return false end
    while #list < idx do list[#list + 1] = 0 end
    for i, existing in ipairs(list) do
        if existing == newID and i ~= idx then
            table.remove(list, i)
            if i < idx then idx = idx - 1 end
            break
        end
    end
    list[idx] = newID
    while #list > 0 and (list[#list] == 0 or list[#list] == nil) do list[#list] = nil end
    if sd.removedSpells then sd.removedSpells[newID] = nil end
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

function ns.AddCDMBar(barType, name, numRows)
    local BuildAllCDMBars = ns.BuildAllCDMBars
    local LayoutCDMBar = ns.LayoutCDMBar
    local RegisterCDMUnlockElements = ns.RegisterCDMUnlockElements
    local MAX_CUSTOM_BARS = ns.MAX_CUSTOM_BARS

    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    local customCount = 0
    for _, b in ipairs(bars) do
        if b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" and not b.isGhostBar then
            customCount = customCount + 1
        end
    end
    if customCount >= MAX_CUSTOM_BARS then return nil end
    barType = barType or "cooldowns"
    local typeLabel = barType == "cooldowns" and "Cooldowns"
                   or barType == "utility" and "Utility"
                   or barType == "buffs" and "Buffs"
                   or barType == "custom_buff" and "Auras"
                   or "Cooldowns"
    local typeCount = 0
    for _, b in ipairs(bars) do
        if b.barType == barType then typeCount = typeCount + 1 end
    end
    local key = "custom_" .. (#bars + 1) .. "_" .. GetTime()
    key = key:gsub("%.", "_")
    bars[#bars + 1] = {
        key = key, name = name or ("Custom " .. typeLabel .. " Bar " .. (typeCount + 1)),
        barType = barType,
        enabled = true, iconSize = 36, numRows = numRows or 1,
        spacing = 2,
        borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
        borderClassColor = false, borderThickness = "thin",
        bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
        iconZoom = 0.08, iconShape = "none",
        verticalOrientation = false, barBgEnabled = false,        barBgR = 0, barBgG = 0, barBgB = 0,
        showCooldownText = true, cooldownTextPosition = "center",
        showItemCount = true, cooldownFontSize = 12,
        showCharges = true, chargeFontSize = 11,
        desaturateOnCD = true, swipeAlpha = 0.7,
        activeStateAnim = "blizzard",
        anchorTo = "none", anchorPosition = "left",
        anchorOffsetX = 0, anchorOffsetY = 0,
        barVisibility = "always", housingHideEnabled = true,
        visHideHousing = true, visOnlyInstances = false,
        visHideMounted = false, visHideNoTarget = false, visHideNoEnemy = false,
        showStackCount = false, stackCountSize = 11,
        stackCountX = 0, stackCountY = 0,
        stackCountR = 1, stackCountG = 1, stackCountB = 1,
        -- Custom bars use a spell list instead of mirroring Blizzard
        outOfRangeOverlay = false,
        pandemicGlow = true,
        pandemicGlowStyle = -1,
        pandemicGlowLines = 8,
        pandemicGlowThickness = 2,
        pandemicGlowSpeed = 4,
    }
    local sd = ns.GetBarSpellData(key)
    if sd then sd.assignedSpells = {} end
    BuildAllCDMBars()
    LayoutCDMBar(key)
    if ns.QueueReanchor then ns.QueueReanchor() end
    RegisterCDMUnlockElements()
    return key
end

-- Remove a custom CDM bar (only custom bars, not the 3 defaults). Spells that were on
-- the deleted bar are migrated to the matching ghost bar for their family so they stay
-- hidden, instead of spilling back onto the default bar for their viewer category.
function ns.RemoveCDMBar(key)
    if key == "cooldowns" or key == "utility" or key == "buffs" then return false end
    local RegisterCDMUnlockElements = ns.RegisterCDMUnlockElements
    local p = ECME.db.profile
    for i, barData in ipairs(p.cdmBars.bars) do
        if barData.key == key then
            local frame = cdmBarFrames[key]
            if frame then EllesmereUI.SetElementVisibility(frame, false) end
            cdmBarFrames[key] = nil
            cdmBarIcons[key] = nil
            p.cdmBarPositions[key] = nil
            table.remove(p.cdmBars.bars, i)
            -- Max Icons overflow: clear targets pointing at the removed bar
            -- (runtime fail-safes on a dangling key; this is config hygiene).
            for _, b in ipairs(p.cdmBars.bars) do
                if b.overflowTarget == key then b.overflowTarget = nil end
            end
            -- Deletion shifts every later bar's array index, so captured
            -- override paths into cdmBars.bars would point at the WRONG bars.
            -- Drop them all (users re-capture) -- honest beats corrupt.
            if EllesmereUI.SpecOverrides_OnCDMBarsRestructured then
                EllesmereUI.SpecOverrides_OnCDMBarsRestructured()
            end

            -- Free all spells (don't ghost them): delete the bar's spell data
            -- from every spec of the ACTIVE profile only -- other profiles own
            -- independent stores and keep their copy (a copied profile's bar
            -- deletion must not wipe the origin's). Bar defs are per-profile
            -- but spec-independent, so clear all of THIS profile's specs.
            local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
            if sp then
                for _, specData in pairs(sp) do
                    if type(specData) == "table" and specData.barSpells and specData.barSpells[key] then
                        specData.barSpells[key] = nil
                    end
                end
            end

            if EllesmereUI and EllesmereUI.UnregisterUnlockElement then
                EllesmereUI:UnregisterUnlockElement("CDM_" .. key)
            end
            -- Re-register remaining bars to update linkedKeys
            RegisterCDMUnlockElements()
            -- Reanchor so frames re-route to the ghost bar (or wherever)
            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
            if ns.CollectAndReanchor then ns.CollectAndReanchor() end
            return true
        end
    end
    return false
end


-- Native equipment rows that the dual-lane era auto-added into buff bar
-- stores (12.1 EquipSlot* tracked-buff mirroring): pruned automatically.
-- POSITIVE identification only -- a stored sid drops solely when a live
-- viewer entry with that sid carries equipSlot; absence keeps the row
-- (zero-values law: an unequipped item resolves nothing and must not be
-- convicted). Runs OOC-cheap from the buff entry collector, so every
-- options open and reconcile pass self-heals the store.
function ns.PruneEquipmentBuffRows()
    local equip, any = {}, false
    -- Tracked trinket PROC BUFF rows (equipSlot + category EquipSlotTracked)
    -- are LEGITIMATE buff-bar content (user directive 2026-08-16) -- they must
    -- never be convicted, by EITHER source below. Positive identification
    -- only, same zero-values posture as the conviction sets: a live
    -- EquipSlotTracked viewer entry vouches for its sid (covers on-use
    -- trinkets whose use-spell IS the tracked proc aura -- source 2 would
    -- otherwise convict the legitimate row whenever the trinket is worn).
    -- CATEGORY is the discriminator, not buffSlot (field-probed 2026-08-16:
    -- buffSlot=1 rides the on-use cat-7 rows too).
    local exempt = {}
    local eqTracked = Enum and Enum.CooldownViewerCategory
        and Enum.CooldownViewerCategory.EquipSlotTracked or 8
    -- Viewer source: trusted only with CDM data loaded and a populated
    -- enumeration. These guards gate THIS source alone -- the equipped-item
    -- source below needs neither and must run regardless.
    local entries = ns._cdmDataLoaded and ns.EnumerateCDMViewerSpells
        and ns.EnumerateCDMViewerSpells(true) or nil
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if entries and entries[1] and gci then
        for _, e in ipairs(entries) do
            if e.sid and e.cdID then
                local info = gci(e.cdID)
                if info and info.equipSlot then
                    if info.category == eqTracked then
                        StoreVariantValue(exempt, e.sid, true, false)
                    else
                        StoreVariantValue(equip, e.sid, true, false)
                        any = true
                    end
                end
            end
        end
    end
    -- Second proof source, viewer-independent: an EQUIPPED item vouches for
    -- its own use-spell (GetItemSpell). Covers rows whose native viewer entry
    -- is gone (untracked in Blizzard's CDM) while the item is still worn.
    local gis = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if gis and GetInventoryItemID then
        for slot = 1, 19 do
            local itemID = GetInventoryItemID("player", slot)
            if itemID then
                local _, useSid = gis(itemID)
                if type(useSid) == "number" and useSid > 0 then
                    StoreVariantValue(equip, useSid, true, false)
                    any = true
                end
            end
        end
    end
    if not any then return end
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    if not bars then return end
    for _, bd in ipairs(bars) do
        -- Every bar type: dual-lane-era auto-adds landed item use-spells on
        -- cooldowns/utility bars too, not just buff bars. Only positive ids
        -- matching the proven equipment set drop -- markers and real spells
        -- cannot match.
        if bd.key ~= (ns.GHOST_CD_BAR_KEY or "__ghost_cd") then
            local sd = ns.GetBarSpellData(bd.key)
            local list = sd and sd.assignedSpells
            if list then
                local w = 1
                for i = 1, #list do
                    local sid = list[i]
                    -- User-typed custom spell ids are exempt: a deliberate
                    -- entry that happens to equal a worn item's use-spell
                    -- (tinkers, embellishments) must never be convicted.
                    -- Tracked proc-buff sids (buffSlot-vouched above) are
                    -- exempt from both conviction sources.
                    if not (type(sid) == "number" and sid > 0
                        and ResolveVariantValue(equip, sid)
                        and not ResolveVariantValue(exempt, sid)
                        and not (sd.customSpellIDs and sd.customSpellIDs[sid])) then
                        list[w] = sid
                        w = w + 1
                    end
                end
                for i = #list, w, -1 do list[i] = nil end
            end
        end
    end
end
