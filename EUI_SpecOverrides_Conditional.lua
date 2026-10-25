if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_SpecOverrides_Conditional.lua
--
--  The Conditional Overrides integration (engine in
--  EllesmereUI_Conditions.lua), the profile-import store merge and the
--  default re-baseline.
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
local DeepCopy, EntryOwning, FKeyLoaded = I.DeepCopy, I.EntryOwning, I.FKeyLoaded
local GetGroups, GetProfileRoot, GetStore = I.GetGroups, I.GetProfileRoot, I.GetStore
local HasRegisteredDefault, L, MatchOwnedFKey = I.HasRegisteredDefault, I.L, I.MatchOwnedFKey
local NIL_SENT, PROFILES_MODULE, PxCo = I.NIL_SENT, I.PROFILES_MODULE, I.PxCo
local ReadLive, RebuildFKeyIndex = I.ReadLive, I.RebuildFKeyIndex
local RunRefreshers, SplitFKey, WriteLive = I.RunRefreshers, I.SplitFKey, I.WriteLive
local BmApplyLayer, BmHarvestLayer, BmOwnerGid = I.BmApplyLayer, I.BmHarvestLayer, I.BmOwnerGid
local BmSessionEngage, DmApplyLayer = I.BmSessionEngage, I.DmApplyLayer
local DmHarvestLayer, DmOwnerGid = I.DmHarvestLayer, I.DmOwnerGid
local DmSessionEngage, GetBmStore = I.DmSessionEngage, I.GetBmStore
local GetCondBmStore, GetCondDmStore = I.GetCondBmStore, I.GetCondDmStore
local GetDmStore, LiteProfile = I.GetDmStore, I.LiteProfile

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of EllesmereUI_SpecOverrides.lua).
local _editGroup = nil
I.editGroupSetters[#I.editGroupSetters + 1] = function(v) _editGroup = v end
local _defaultView = false
I.defaultViewSetters[#I.defaultViewSetters + 1] = function(v) _defaultView = v end
local _inTransition = false
I.inTransitionSetters[#I.inTransitionSetters + 1] = function(v) _inTransition = v end
local RequestGoldWalk
I.goldWalkSetters[#I.goldWalkSetters + 1] = function(v) RequestGoldWalk = v end

-------------------------------------------------------------------------------
--  CONDITIONAL OVERRIDES integration (engine in EllesmereUI_Conditions.lua). Same
--  machine as spec overrides keyed by conditional GROUP instead of spec: entries
--  carry values = { default = {fkey=v}, [gid] = {fkey=v} }; "no condition active"
--  plays the role of a non-member spec (defaults write). PRECEDENCE: a SPEC-owned
--  fkey (EntryOwning) is off-limits, checked at every conditional write, so
--  later-created spec overrides evict conditional claims silently. Unlock layouts
--  ride the layer engine via the namespaced active pointer ("cond:"..gid); a spec
--  whose group has a layout ignores conditional layouts entirely (first branch of
--  layer resolution). Functions live in one table (file local budget).
-------------------------------------------------------------------------------
-- Contexts excluded from BOTH override systems: no glow overlay, no auto-capture,
-- no slot marks, entries pruned. true = whole module; table = specific pages;
-- nested table = specific sections of a page. (Declared here so both systems bind it.)
local EXCLUDED_CONTEXTS = {
    [PROFILES_MODULE] = true,                  -- Profiles & Presets (incl. list tab)
    ["_EUIPatchNotes"] = true,                 -- Patch Notes
    ["_EUILegends"] = true,                    -- EUI Legends
    ["_EUIGlobal"] = true,                     -- Global Settings (whole module)
    -- (Global Settings -> Colors stays eligible)
    -- Blacklisted modules (see FOLDER_BLACKLIST): their pages are fully
    -- outside the system, so the editing-as overlay/absorb covers them too.
    ["EllesmereUIBlizzardSkin"]      = true,
    ["EllesmereUIDamageMeters"]      = true,
    ["EllesmereUIMythicTimer"]       = true,
    ["EllesmereUIQuestTracker"]      = true,
    ["EllesmereUIFriends"]           = true,
    ["EllesmereUIBags"]              = true,
    ["EllesmereUIQoL"]               = true,   -- whole module
    ["EllesmereUIAuraBuffReminders"] = true,
    ["EllesmereUIForeverEssentials"] = true,
    ["EllesmereUIQuickdraw"]         = true,
    ["EllesmereUILoadoutManager"]    = true,
    ["EllesmereUIGroupFinder"]       = true,
    ["EllesmereUISimpleLootCouncil"] = true,
    -- CDM: module eligible (bar settings override); these two tabs are
    -- spell/spec-coupled systems with their own per-spec storage.
    ["EllesmereUICooldownManager"] = {
        ["Bar Glows"] = true,
        ["Tracking Bars"] = true,
    },
    -- Raid Frames: HoverCast bindings live in the account-global clickCast
    -- store (never per-profile), so overrides can't apply to them.
    ["EllesmereUIRaidFrames"] = {
        ["HoverCast"] = true,
    },
    -- Unit Frames: Player Aura Bars is a bar-CRUD system (custom bar lists,
    -- shared filter registry, structural per-bar tables), not per-spec slot
    -- values; the whole tab stays outside overrides.
    ["EllesmereUIUnitFrames"] = {
        ["Player Aura Bars"] = true,
    },
}

local Cond = {}
EllesmereUI._CondOv = Cond

-- Condition icon art (media\icons\overrides). battleground uses the horde crest
-- art; the toolbar button rests on the dungeons icon.
Cond.ICON_DIR = "Interface\\AddOns\\EllesmereUI\\media\\icons\\overrides\\"
Cond.ICONS = {
    keybind      = "override-keybinds.png",
    dungeon      = "override-dungeons.png",
    raid         = "override-raid.png",
    arena        = "override-arena.png",
    battleground = "override-horde.png",
    solo         = "override-solo.png",
}

--- True while EITHER override editing session (spec or conditional) is live.
function EllesmereUI.SpecOverrides_EditSessionActive()
    return (_editGroup ~= nil) or (Cond._edit ~= nil)
end

--- Overlay policy for the Raid Frames Buff Manager page, evaluated at page build.
--- nil = no overlay (Default view / no session, or the edited group's fork is live
--- and editable WYSIWYG). Otherwise:
---   { mode = "activate"|"info", kind = "spec"|"cond", gid, text, sub }
--- "info" blocks the whole page: edits there would land in whatever layer is live
--- and bank to the WRONG owner at the next harvest.
function EllesmereUI.SpecOverrides_BmOverlayState()
    local g, kind
    if _editGroup then
        g, kind = _editGroup, "spec"
    elseif Cond._edit then
        g, kind = Cond._edit, "cond"
    else
        return nil
    end
    local cur = CurrentSpecID()
    local s = GetBmStore()
    local liveKey, forked, eligible, text, sub
    if kind == "spec" then
        liveKey = g.id
        forked = (s and s.layouts[g.id] ~= nil) or false
        local member = false
        for _, sid in ipairs(g.specs or {}) do
            if sid == cur then member = true; break end
        end
        local owner = BmOwnerGid(cur)
        eligible = member and (owner == nil or owner == g.id)
        if not member then
            text = L("This group's custom Buff Manager can only be activated or edited while playing one of its specs.")
        elseif not eligible then
            text = L("Another override group already provides the custom Buff Manager for your current spec.")
        end
    else
        liveKey = "cond:" .. g.id
        local cs = GetCondBmStore()
        forked = (cs and cs.layouts[g.id] ~= nil) or false
        -- No real-context requirement: unlike unlock layouts these are plain
        -- settings and the session swap (BmSessionEngage) makes the fork live
        -- anywhere. Only the spec-wins precedence gate remains.
        local specOwner = BmOwnerGid(cur) ~= nil
        eligible = not specOwner
        if specOwner then
            text = L("Your current spec has its own custom Buff Manager, so conditional Buff Managers never apply to it.")
        end
    end
    if forked and eligible then
        -- PURE query: report a stale live pointer (fresh login ordering) via the second
        -- return; BmPagePrelude performs the heal/session engage. A session-applied
        -- fork IS the live layer even though the runtime pointer does not say so.
        local liveNow = EllesmereUI._bmSessionGid
            and ("cond:" .. EllesmereUI._bmSessionGid) or (s and s.active)
        return nil, liveNow ~= liveKey
    end
    if not eligible then
        return { mode = "info", kind = kind, gid = g.id, text = text, sub = sub }
    end
    return {
        mode = "activate", kind = kind, gid = g.id,
        text = kind == "spec"
            and L("This will create a fully unique Buff Manager for this override group. Changes made to your default Buff Manager will no longer affect these specs.")
            or L("This will create a fully unique Buff Manager for this conditional group. Changes made to your default Buff Manager will no longer affect it."),
    }
end

--- Starting points offered by the create popup, in menu order: the main
--- (baseline) Buff Manager, every other override that already has its own
--- Buff Manager, then the two presets. Returns values, order for a dropdown.
--- Keys: "main" | "spec:<gid>" | "cond:<gid>" | "default" | "empty".
function EllesmereUI.SpecOverrides_BmSeedSources(kind, gid)
    local values, order = {}, {}
    local function Add(key, label) values[key] = label; order[#order + 1] = key end
    Add("main", L("Copy from main Buff Manager"))
    local s = GetBmStore()
    if s and s.layouts then
        for _, g in ipairs(GetGroups() or {}) do
            if s.layouts[g.id] ~= nil and not (kind == "spec" and g.id == gid) then
                Add("spec:" .. g.id, EllesmereUI.Lf("Copy from %1$s Buff Manager", g.name or "?"))
            end
        end
    end
    local cs = GetCondBmStore()
    if cs and cs.layouts and EllesmereUI.Conditions_GetGroups then
        for _, g in ipairs(EllesmereUI.Conditions_GetGroups() or {}) do
            if cs.layouts[g.id] ~= nil and not (kind == "cond" and g.id == gid) then
                Add("cond:" .. g.id, EllesmereUI.Lf("Copy from %1$s Buff Manager", g.name or "?"))
            end
        end
    end
    Add("default", L("Default Preset"))
    Add("empty", L("Empty Preset"))
    return values, order
end

--- READ-ONLY: the override groups with their own Buff Manager (kind "bm") or
--- Debuff Manager ("dm"): spec group ids, then condition group ids, each list
--- in creation order.
function EllesmereUI.SpecOverrides_ManagerForkOwners(kind)
    local s, cs
    if kind == "dm" then
        s, cs = GetDmStore(), GetCondDmStore()
    else
        s, cs = GetBmStore(), GetCondBmStore()
    end
    local spec, cond = {}, {}
    if s and s.layouts then
        for _, g in ipairs(GetGroups() or {}) do
            if s.layouts[g.id] ~= nil then spec[#spec + 1] = g.id end
        end
    end
    if cs and cs.layouts then
        for _, g in ipairs(EllesmereUI.Conditions_GetGroups() or {}) do
            if cs.layouts[g.id] ~= nil then cond[#cond + 1] = g.id end
        end
    end
    return spec, cond
end


--- Page-build entry point for the RF Buff Manager page: call FIRST, before any
--- content builds. Heals a stale live layer (so the page renders the edited
--- group's fork; the heal skips the page repaint because THIS build is the
--- repaint) and returns the overlay state (nil = no overlay).
function EllesmereUI.SpecOverrides_BmPagePrelude()
    -- Outside any session: ensure the runtime layer the page is about to edit is
    -- actually LIVE. A spec owning a BM fork gets it auto-activated here; a stale
    -- pointer (login ordering, interrupted session) heals instead of letting the
    -- page edit an off-screen layer ("changing settings does nothing" with no error).
    if not _editGroup and not Cond._edit then
        EllesmereUI.SpecOverrides_ApplyBm(CurrentSpecID(), false, true)
    end
    -- Editing-as-conditional with an existing fork that is not the runtime layer
    -- (condition not met right now): engage the session swap so the page and
    -- on-screen frames show the fork being edited. Spec-wins gate still blocks
    -- when a spec owner exists.
    if Cond._edit then
        local cs = GetCondBmStore()
        if cs and cs.layouts[Cond._edit.id]
           and EllesmereUI._bmSessionGid ~= Cond._edit.id
           and not BmOwnerGid(CurrentSpecID()) then
            local s = GetBmStore()
            if not (s and s.active == ("cond:" .. Cond._edit.id)) then
                BmSessionEngage(Cond._edit.id)
            end
        end
    end
    local state, needHeal = EllesmereUI.SpecOverrides_BmOverlayState()
    if needHeal then
        EllesmereUI.SpecOverrides_ApplyBm(CurrentSpecID(), true, true)
    end
    -- Re-evaluate passive chrome on EVERY BM page build: fork deletion,
    -- activation, and heals all rebuild this page without a SelectPage.
    if EllesmereUI.SpecOverrides_UpdateBmPassiveChrome then
        EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    end
    return state
end

--- Creates the edited group's BM fork (the overlay's create popup). Re-validates
--- every gate (race guard), banks live into its current owner, then seeds from
--- `source` (SpecOverrides_BmSeedSources key; nil/"main" = the main Buff
--- Manager): spec forks born while a conditional BM layer is live seed from the
--- BASELINE (spec layers void conditionals -- never fork a dungeon state);
--- otherwise from live. Other overrides and the two presets seed a fresh layer,
--- which must then be PAINTED when the new fork becomes the live one (the main
--- copy is already what is on screen).
function EllesmereUI.SpecOverrides_ActivateBm(kind, gid, source)
    local state = EllesmereUI.SpecOverrides_BmOverlayState()
    if not state or state.mode ~= "activate" or state.kind ~= kind
       or state.gid ~= gid then return end
    -- Source key -> fresh layer table; nil = "main" (seeded below as before).
    local function SeedLayerFor(src)
        if not src or src == "main" then return nil end
        if src == "default" or src == "empty" then
            local rf = LiteProfile("EllesmereUIRaidFrames")
            return {
                indicators  = {},
                simple      = {},
                displayMode = "custom",
                iconZoom    = (rf and rf.bmIconZoom) or 0.08,
                bm2         = _G._ERF_BM2PresetFork and _G._ERF_BM2PresetFork(src)
                    or { specs = {}, seeded = {} },
            }
        end
        local sgid = tonumber(src:match("^spec:(%d+)$"))
        if sgid then
            local s = GetBmStore()
            local layer = s and s.layouts and s.layouts[sgid]
            return layer and DeepCopy(layer) or nil
        end
        local cgid = tonumber(src:match("^cond:(%d+)$"))
        if cgid then
            local cs = GetCondBmStore()
            local layer = cs and cs.layouts and cs.layouts[cgid]
            return layer and DeepCopy(layer) or nil
        end
        return nil
    end
    local seeded = SeedLayerFor(source)
    local cur = CurrentSpecID()
    EllesmereUI.SpecOverrides_HarvestBmLayout()
    -- Virgin-store baseline seed: the first-ever BM layer must capture the
    -- shared baseline from the pre-fork live state (live IS the baseline when
    -- no layer is active), or leaving the fork later has nothing to restore and
    -- the next harvest adopts the fork's edits as the default Buff Manager.
    do
        local s = GetBmStore(true)
        if s and not s.baselineLayout and not s.active then
            s.baselineLayout = BmHarvestLayer()
        end
    end
    if kind == "spec" then
        local s = GetBmStore(true)
        if not s or s.layouts[gid] ~= nil then return end
        local fromCond = type(s.active) == "string"
        -- Live differs from the new layer when it was seeded from anything but
        -- the main copy of what is on screen -> paint on activation.
        local needPaint = seeded ~= nil or fromCond
        if seeded then
            s.layouts[gid] = seeded
        elseif fromCond and s.baselineLayout then
            s.layouts[gid] = DeepCopy(s.baselineLayout)
        else
            local snap = BmHarvestLayer()
            if not snap then return end
            s.layouts[gid] = snap
        end
        if BmOwnerGid(cur) == gid then
            s.active = gid
            -- WoW Forever: the new fork serves the current spec's bucket;
            -- published before the paint below, or re-driven with no paint
            -- (RefreshPage below rebuilds the page).
            if EllesmereUI.IS_FOREVER then
                local fvPrev = EllesmereUI._SO_SetForkSpec(false, gid, cur)
                if not needPaint and fvPrev ~= EllesmereUI.SpecOverrides_BmForkSpecID then
                    EllesmereUI._SO_ForkReDrive(false, true)
                end
            end
            -- Baseline-seeded fork while a conditional was live (the
            -- conditional ceased to exist for this spec), or a preset/other-
            -- override seed: swap the screen to the new layer. RefreshPage
            -- below is the repaint.
            if needPaint then BmApplyLayer(s.layouts[gid], true) end
        end
    else
        local cs = GetCondBmStore(true)
        if not cs or cs.layouts[gid] ~= nil then return end
        local s = GetBmStore(true)
        -- Seed from the BASELINE when any layer is live (another conditional
        -- applied right now); live IS the baseline only when nothing is.
        local snap = seeded
        if not snap then
            if s and s.active and s.baselineLayout then
                snap = DeepCopy(s.baselineLayout)
            else
                snap = BmHarvestLayer()
                if not snap then return end
            end
        end
        cs.layouts[gid] = snap
        local ag = EllesmereUI.Conditions_ActiveGroup and EllesmereUI.Conditions_ActiveGroup()
        if ag and ag.id == gid then
            -- In-context creation: the fork is the runtime layer from here. A
            -- non-main seed differs from what is on screen -> paint it.
            if s then s.active = "cond:" .. gid end
            if seeded then BmApplyLayer(snap, true) end
        else
            -- Out-of-context creation: session-scoped apply only. The runtime
            -- pointer must never point at a layer whose condition is not met.
            BmSessionEngage(gid)
        end
    end
    EllesmereUI:RefreshPage(true)
end

--- Overlay policy for the Debuff Manager page (mirror of BmOverlayState;
--- same eligibility rules and returns).
function EllesmereUI.SpecOverrides_DmOverlayState()
    local g, kind
    if _editGroup then
        g, kind = _editGroup, "spec"
    elseif Cond._edit then
        g, kind = Cond._edit, "cond"
    else
        return nil
    end
    local cur = CurrentSpecID()
    local s = GetDmStore()
    local liveKey, forked, eligible, text, sub
    if kind == "spec" then
        liveKey = g.id
        forked = (s and s.layouts[g.id] ~= nil) or false
        local member = false
        for _, sid in ipairs(g.specs or {}) do
            if sid == cur then member = true; break end
        end
        local owner = DmOwnerGid(cur)
        eligible = member and (owner == nil or owner == g.id)
        if not member then
            text = L("This group's custom Debuff Manager can only be activated or edited while playing one of its specs.")
        elseif not eligible then
            text = L("Another override group already provides the custom Debuff Manager for your current spec.")
        end
    else
        liveKey = "cond:" .. g.id
        local cs = GetCondDmStore()
        forked = (cs and cs.layouts[g.id] ~= nil) or false
        local specOwner = DmOwnerGid(cur) ~= nil
        eligible = not specOwner
        if specOwner then
            text = L("Your current spec has its own custom Debuff Manager, so conditional Debuff Managers never apply to it.")
        end
    end
    if forked and eligible then
        local liveNow = EllesmereUI._dmSessionGid
            and ("cond:" .. EllesmereUI._dmSessionGid) or (s and s.active)
        return nil, liveNow ~= liveKey
    end
    if not eligible then
        return { mode = "info", kind = kind, gid = g.id, text = text, sub = sub }
    end
    return {
        mode = "activate", kind = kind, gid = g.id,
        text = kind == "spec"
            and L("This will create a fully unique Debuff Manager for this override group. Your current Debuff Manager settings are copied as its starting point, and changes made to your default Debuff Manager will no longer affect these specs.")
            or L("This will create a fully unique Debuff Manager for this conditional group. Your current Debuff Manager settings are copied as its starting point, and changes made to your default Debuff Manager will no longer affect it."),
    }
end

--- Page-build entry point for the Debuff Manager page (mirror of
--- BmPagePrelude): call FIRST, before any content builds.
function EllesmereUI.SpecOverrides_DmPagePrelude()
    if not _editGroup and not Cond._edit then
        EllesmereUI.SpecOverrides_ApplyDm(CurrentSpecID(), false, true)
    end
    if Cond._edit then
        local cs = GetCondDmStore()
        if cs and cs.layouts[Cond._edit.id]
           and EllesmereUI._dmSessionGid ~= Cond._edit.id
           and not DmOwnerGid(CurrentSpecID()) then
            local s = GetDmStore()
            if not (s and s.active == ("cond:" .. Cond._edit.id)) then
                DmSessionEngage(Cond._edit.id)
            end
        end
    end
    local state, needHeal = EllesmereUI.SpecOverrides_DmOverlayState()
    if needHeal then
        EllesmereUI.SpecOverrides_ApplyDm(CurrentSpecID(), true, true)
    end
    if EllesmereUI.SpecOverrides_UpdateBmPassiveChrome then
        EllesmereUI.SpecOverrides_UpdateBmPassiveChrome()
    end
    return state
end

--- Creates the edited group's DM fork (mirror of SpecOverrides_ActivateBm,
--- including the virgin-store baseline seed and conditional seeding rules).
function EllesmereUI.SpecOverrides_ActivateDm(kind, gid)
    local state = EllesmereUI.SpecOverrides_DmOverlayState()
    if not state or state.mode ~= "activate" or state.kind ~= kind
       or state.gid ~= gid then return end
    local cur = CurrentSpecID()
    EllesmereUI.SpecOverrides_HarvestDmLayout()
    do
        local s = GetDmStore(true)
        if s and not s.baselineLayout and not s.active then
            s.baselineLayout = DmHarvestLayer()
        end
    end
    if kind == "spec" then
        local s = GetDmStore(true)
        if not s or s.layouts[gid] ~= nil then return end
        local fromCond = type(s.active) == "string"
        if fromCond and s.baselineLayout then
            s.layouts[gid] = DeepCopy(s.baselineLayout)
        else
            local snap = DmHarvestLayer()
            if not snap then return end
            s.layouts[gid] = snap
        end
        if DmOwnerGid(cur) == gid then
            s.active = gid
            -- WoW Forever: the new fork serves the current spec's bucket
            -- (see SpecOverrides_ActivateBm).
            if EllesmereUI.IS_FOREVER then
                local fvPrev = EllesmereUI._SO_SetForkSpec(true, gid, cur)
                if not fromCond and fvPrev ~= EllesmereUI.SpecOverrides_DmForkSpecID then
                    EllesmereUI._SO_ForkReDrive(true, true)
                end
            end
            if fromCond then DmApplyLayer(s.layouts[gid], true) end
        end
    else
        local cs = GetCondDmStore(true)
        if not cs or cs.layouts[gid] ~= nil then return end
        local s = GetDmStore(true)
        local snap
        if s and s.active and s.baselineLayout then
            snap = DeepCopy(s.baselineLayout)
        else
            snap = DmHarvestLayer()
            if not snap then return end
        end
        cs.layouts[gid] = snap
        local ag = EllesmereUI.Conditions_ActiveGroup and EllesmereUI.Conditions_ActiveGroup()
        if ag and ag.id == gid then
            if s then s.active = "cond:" .. gid end
        else
            DmSessionEngage(gid)
        end
    end
    EllesmereUI:RefreshPage(true)
end

--- True for module folders excluded wholesale from the override systems (drives
--- the sidebar lock during an editing session). Includes the management
--- surfaces (Profiles & Presets, Patch Notes, Global Settings): they lock like
--- every other excluded module. Plugin pages ("plugin:" keys) are never part of
--- the override systems, so they are always excluded.
-- Block-scoped: keeps ns out of the main chunk's locals (Lua 5.1 allows ~200).
do
    local _, ns = ...
    ns = ns.__euiCoreNS or ns  -- standalone builds: the core's own table (EllesmereUI.lua)

    function EllesmereUI.SpecOverrides_ModuleExcluded(folder)
        return (type(folder) == "string" and EXCLUDED_CONTEXTS[folder] == true)
            or ns.IsPluginKey(folder)
    end

    --- True when a module page is excluded (page-scoped entry, or the whole
    --- module). Drives the page-tab lock while a session is active.
    function EllesmereUI.SpecOverrides_PageExcluded(module, page)
        if ns.IsPluginKey(module) then return true end
        local ex = module and EXCLUDED_CONTEXTS[module]
        if ex == true then return true end
        if type(ex) == "table" and page then return ex[page] == true end
        return false
    end
end

function Cond.GetStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    if not prof.condOverrides then
        if not create then return nil end
        prof.condOverrides = {}
    end
    return prof.condOverrides
end

function Cond.GetUnlockStore(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    local s = prof.condUnlockOverrides
    if not s then
        if not create then return nil end
        s = {}
        prof.condUnlockOverrides = s
    end
    s.layouts = s.layouts or {}
    return s
end

-- fkey -> entry index over the conditional store (parallel to _fkeyIndex,
-- never merged into it: EntryOwning stays spec-only by definition).
Cond._fkeyIndex = nil
function Cond.RebuildIndex()
    Cond._fkeyIndex = {}
    for _, e in ipairs(Cond.GetStore() or {}) do
        if e.values and e.values.default then
            for fkey in pairs(e.values.default) do
                Cond._fkeyIndex[fkey] = e
            end
        end
    end
end
function Cond.EntryOwning(fkey)
    if not Cond._fkeyIndex then Cond.RebuildIndex() end
    return Cond._fkeyIndex[fkey]
end

--- Writes the effective conditional values for the given active group (nil = no
--- condition: defaults). Mirrors WriteSpecValues plus the spec-wins gate.
--- forSession: painting an EDITING session's view (conditional-over-default),
--- where the conditional's own values must show even for fkeys the SPEC store
--- also tracks. Runtime applies (transitions, overlays, restores) omit it --
--- spec overrides always win at apply time.
function Cond.WriteValues(gid, forSession)
    local store = Cond.GetStore()
    if not store or #store == 0 then return nil end
    PxCo.Pair(store, true)
    local touched = nil
    for _, entry in ipairs(store) do
        local map = gid and entry.values[gid] or nil
        for fkey, def in pairs(entry.values.default) do
            if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
               and (forSession or not EntryOwning(fkey)) then
                local v = def
                if map and map[fkey] ~= nil then v = map[fkey] end
                if v == NIL_SENT then v = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues.
                local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
                local cur = ReadLive(fkey)
                -- Table values are never written or compared: a stored table
                -- reference NEVER equals live, so it would register a "write"
                -- and force a full module refresh on EVERY transition.
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

--- Writes an entry's recorded DEFAULT values back to live. Called right BEFORE a
--- conditional entry is removed: a conditional's values sit in live for as long as
--- its condition holds, including while the options panel is open (the Default
--- Editing Mode swap covers the SPEC store only), so dropping the entry without
--- this would silently turn the override's values into the profile's own
--- settings. The spec delete flow needs no equivalent (live already holds the
--- shared defaults there); its one path that CAN hit this, the orphan drop in
--- PruneOrphanEntries, carries the same restore. Guards mirror Cond.WriteValues
--- exactly, so this only writes keys the conditional overlay could have written
--- (blacklisted/match-owned/SPEC-owned/unloaded-module skipped; NIL_SENT on a
--- defaults-backed key is harvest residue, not a real removal).
--- touched: folder-set accumulator; the caller refreshes once.
function Cond.RestoreEntryDefaults(entry, touched)
    local def = entry.values and entry.values.default
    if not def then return end
    for fkey, dv in pairs(def) do
        if not BlacklistedFKey(fkey) and not MatchOwnedFKey(fkey)
           and not EntryOwning(fkey) and FKeyLoaded(fkey) then
            local v = dv; if v == NIL_SENT then v = nil end
            local nilPoison = (v == nil) and HasRegisteredDefault(fkey)
            local cur = ReadLive(fkey)
            if not nilPoison and type(v) ~= "table" and type(cur) ~= "table"
               and cur ~= v then
                if WriteLive(fkey, v) then
                    local folder = SplitFKey(fkey)
                    if folder then touched[folder] = true end
                end
            end
        end
    end
end

--- Garbage-collects conditional fkeys no group map holds a value for (the
--- diff-semantics harvests clear reverts at bank time), and entries left empty.
--- NEVER judges by equality against the default: the default is movable, and
--- equality-pruning against a moved/poisoned default silently deletes
--- intentional override values.
function Cond.PruneRedundant()
    local store = Cond.GetStore()
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
                    def[fkey] = nil
                    changed = true
                end
            end
            if not next(def) then
                table.remove(store, i)
                changed = true
            end
        end
    end
    if changed then
        Cond.RebuildIndex()
        RequestGoldWalk()
    end
end

--- Banks live values into the given group's maps (nil = the default maps) for
--- every fkey the conditional store tracks. Mirrors the spec Harvest. Group
--- maps use diff semantics (bank when live differs from the recorded default,
--- clear when it matches) so a transition harvest never seeds default-equal
--- junk maps onto entries the group never customized; the default maps
--- themselves always track live verbatim.
function Cond.Harvest(gid)
    local store = Cond.GetStore()
    if not store or #store == 0 then return end
    -- Defaults may only rebank over CANONICAL live data: while any editing session or
    -- the Default view holds swapped values, banking poisons the recorded defaults.
    -- (HarvestCurrent orders its call after the canonical restore; this is the belt
    -- for any other caller.)
    local sessionLive = _defaultView or _editGroup or Cond._edit
    -- SPEC-OWNED fkeys are never harvested in either direction: while the spec store
    -- tracks an fkey, live reflects SPEC values (runtime applies skip it), so banking
    -- live here would poison the conditional's default/group maps with spec-scoped
    -- values; Cond values stay dormant until the spec override is removed. TABLE-typed
    -- live values are never banked either (structure change; mirror of HarvestMap --
    -- would alias store to profile).
    for _, entry in ipairs(store) do
        if gid then
            local map = entry.values[gid]
            for fkey, dv in pairs(entry.values.default) do
                -- FKeyLoaded: a disabled module reads nil for every path, which would
                -- poison the maps with deletion markers. MatchOwnedFKey: match-engine
                -- writes never bank (mirrors spec-side Harvest; Cond.WriteValues skips
                -- these at apply time).
                if not EntryOwning(fkey) and FKeyLoaded(fkey)
                   and not MatchOwnedFKey(fkey) then
                    local live = ReadLive(fkey)
                    if type(live) ~= "table" then
                        local defVal = dv; if defVal == NIL_SENT then defVal = nil end
                        if live == defVal then
                            -- Equality is NOT proof of a revert outside an edit session
                            -- (the default may have been edited onto the group's
                            -- value): retain the held value. Real reverts clear in
                            -- Cond.HarvestEdit, which has the session snapshot to prove them.
                        else
                            if not map then map = {}; entry.values[gid] = map end
                            map[fkey] = (live == nil) and NIL_SENT or live
                        end
                    end
                end
            end
            if map and not next(map) then entry.values[gid] = nil end
        elseif not sessionLive then
            local map = entry.values.default
            for fkey in pairs(map) do
                if not EntryOwning(fkey) and FKeyLoaded(fkey)
                   and not MatchOwnedFKey(fkey) then
                    local live = ReadLive(fkey)
                    if type(live) ~= "table" then
                        map[fkey] = live == nil and NIL_SENT or live
                    end
                end
            end
        end
    end
    Cond.PruneRedundant()
end

--- Values-only overlay for profile-apply paths (RefreshAllAddons): re-paints
--- the applied conditional group's values after spec values. While an
--- editing-as-conditional session holds swapped values live, generic re-applies
--- must preserve the session's view instead.
function Cond.ApplyValues()
    local gid
    if Cond._edit then
        gid = Cond._edit.id
    else
        gid = EllesmereUI.Conditions_AppliedGid and EllesmereUI.Conditions_AppliedGid()
    end
    -- forSession while a session is open: without it the spec-wins gate skips
    -- spec-owned fkeys and the session view is never repainted over whatever a
    -- generic re-apply just wrote there. Returns the touched folder set so
    -- callers outside RefreshAllAddons (the FlushUnlock value overlay) can
    -- refresh what actually changed.
    return Cond.WriteValues(gid, Cond._edit ~= nil)
end

-------------------------------------------------------------------------------
--  Profile-import store merge + default re-baseline
-------------------------------------------------------------------------------

--- RETIRED, no callers: ImportProfile uses ALL-OR-NOTHING override semantics (take
--- the exporter's complete override system or keep the recipient's; see the Include
--- Overrides controls). Reference only -- do NOT re-wire: the partition/union/remap
--- machinery here is the bug surface that redesign deliberately eliminated.
--- Merged PER-MODULE into a deep copy of the CURRENT profile: overrides ride with
--- their addon and fully replace every imported module; non-imported modules keep
--- the recipient's untouched.
---   * value entries (spec + cond): partitioned by each fkey's addon FOLDER. Imported
---     folders: recipient entries shed those fkeys (entry dropped when emptied),
---     incoming entries come in verbatim. Non-imported: recipient survives, incoming
---     discarded. Defaults are consistent by construction (one exporter); the
---     ApplyProfileData re-bank (SpecOverrides_RebaselineDefaults) covers strings
---     exported while an override was applied.
---   * groups: recipient groups untouched; incoming groups come along ONLY when
---     something surviving the partition references them, so a subset import can't
---     fill the dropdown with do-nothing groups. Ids re-number on collision with
---     every reference remapped (entry group fields, per-gid value maps, fork
---     layout keys, active pointers).
---   * unlock layout forks: whole-layout snapshots spanning ALL modules, so they
---     can't ride per-module. Full import: recipient's dropped, incoming's taken
---     when carried. Partial/subset (incoming.partialImport, stamped by the import
---     dialog on deselection AND by ExportProfile on subset exports) and
---     incoming.layoutExcluded ("Include layout" OFF at either end): recipient's
---     KEPT, incoming's never taken -- stripped-nil must never read as "exporter
---     had none, wipe yours".
---   * Buff Manager forks: Raid Frames data, so per-module -- replaced (or cleared)
---     when RF is imported, kept when it is not.
function EllesmereUI.SpecOverrides_MergeImportedStores(merged, incoming)
    local function maxNumericId(groups)
        local m = 0
        for _, g in ipairs(groups or {}) do
            if type(g.id) == "number" and g.id > m then m = g.id end
        end
        return m
    end

    -- Equivalence comparators: importing your OWN export must collapse each incoming
    -- group onto the recipient's original instead of appending a re-numbered twin
    -- (else the original survives as a dead card while the twin holds the values).
    local function sameSpecGroup(a, b)
        if (a.name or "") ~= (b.name or "") then return false end
        local as, bs = a.specs or {}, b.specs or {}
        if #as ~= #bs then return false end
        local set = {}
        for _, id in ipairs(as) do set[id] = true end
        for _, id in ipairs(bs) do
            if not set[id] then return false end
        end
        return true
    end
    local function sameCondGroup(a, b)
        if (a.name or "") ~= (b.name or "") then return false end
        if (a.key or "") ~= (b.key or "") then return false end
        local ac, bc = a.conds or {}, b.conds or {}
        for k in pairs(ac) do if not bc[k] then return false end end
        for k in pairs(bc) do if not ac[k] then return false end end
        return true
    end

    -- Union group lists; returns (unioned, remap oldIncomingId -> newId). An
    -- incoming group EQUIVALENT to an existing one (per `same`) adopts the
    -- existing group's id (remapped) and pushes its icon (incoming priority);
    -- only genuinely new groups append, re-numbered on id collision.
    local function unionGroups(existing, incomingGroups, same)
        local remap = {}
        if type(incomingGroups) ~= "table" then return existing, remap end
        local out, used = {}, {}
        for _, g in ipairs(existing or {}) do
            out[#out + 1] = g
            if type(g.id) == "number" then used[g.id] = true end
        end
        local nextId = maxNumericId(existing)
        local incMax = maxNumericId(incomingGroups)
        if incMax > nextId then nextId = incMax end
        -- Each existing group may be matched by ONE incoming group per union: users can
        -- hold two groups with identical name+specs/conds, and both twins matching the
        -- same target would collide their remapped gid references (pairs-order data
        -- loss in cond value maps / fork keys). Claimed-once collapses twin pairs onto
        -- their own originals; an unmatched extra falls through to the append path.
        local claimed = {}
        for _, g in ipairs(incomingGroups) do
            local match
            if same then
                for _, eg in ipairs(existing or {}) do
                    if not claimed[eg] and same(eg, g) then match = eg; break end
                end
            end
            if match then
                claimed[match] = true
                if g.id ~= match.id then remap[g.id] = match.id end
                -- Type guard: a corrupt/hand-edited string with a non-table
                -- icon must not abort the whole import inside DeepCopy.
                if type(g.icon) == "table" then match.icon = DeepCopy(g.icon) end
            else
                local ng = DeepCopy(g)
                if type(ng.id) == "number" and used[ng.id] then
                    nextId = nextId + 1
                    remap[g.id] = nextId
                    ng.id = nextId
                end
                if type(ng.id) == "number" then used[ng.id] = true end
                out[#out + 1] = ng
            end
        end
        return out, remap, nextId
    end

    -- Imported-folder set: the per-module partition key for value entries.
    local importedFolders = {}
    if type(incoming.addons) == "table" then
        for folder in pairs(incoming.addons) do importedFolders[folder] = true end
    end
    -- Stamped by the import dialog when any module checkbox was deselected.
    local partial = incoming.partialImport == true

    -- Per-module entry partition: strip fkeys of the given polarity from an entry
    -- list. keepImported=false keeps only NON-imported-folder fkeys (recipient side,
    -- filtered in place -- merged is already a deep copy); true keeps only
    -- imported-folder fkeys (incoming side, deep-copied). Entries emptied by the
    -- strip are dropped. Partition is per-FKEY (via SplitFKey), not per
    -- entry.module: the fkey's folder decides which addon a setting rides with.
    local function partitionEntries(entries, keepImported)
        local out = {}
        for _, e in ipairs(entries or {}) do
            local ne = keepImported and DeepCopy(e) or e
            local def = ne.values and ne.values.default
            if def then
                for fkey in pairs(def) do
                    local folder = SplitFKey(fkey)
                    local isImported = folder and importedFolders[folder] or false
                    if isImported ~= keepImported then
                        def[fkey] = nil
                        for k, m in pairs(ne.values) do
                            if k ~= "default" and type(m) == "table" then m[fkey] = nil end
                        end
                    end
                end
                if next(def) ~= nil then out[#out + 1] = ne end
            end
        end
        return out
    end

    -- Re-keys a cond entry's per-gid value maps after the group union.
    local function remapEntryValues(e, remap)
        if not next(remap) or type(e.values) ~= "table" then return end
        local nv = {}
        for k, m in pairs(e.values) do
            if k ~= "default" and remap[k] then nv[remap[k]] = m else nv[k] = m end
        end
        e.values = nv
    end

    local function remapKeys(map, remap)
        if type(map) ~= "table" or not next(remap) then return map end
        local out = {}
        for k, v in pairs(map) do out[remap[k] or k] = v end
        return out
    end

    local function remapActive(active, sRemap, cRemap)
        if type(active) == "number" then return sRemap[active] or active end
        if type(active) == "string" then
            local cg = tonumber(active:match("^cond:(%d+)$"))
            if cg and cRemap[cg] then return "cond:" .. cRemap[cg] end
        end
        return active
    end

    -- Partition both stores' entries per module: recipient keeps only
    -- non-imported folders, incoming contributes only imported folders. Runs
    -- even when the string carries no entries (an imported module with no
    -- incoming overrides clears the recipient's for it -- replaced wholesale).
    local keptSpec = partitionEntries(merged.specOverrides, false)
    local incSpec  = partitionEntries(incoming.specOverrides, true)
    local keptCond = partitionEntries(merged.condOverrides, false)
    local incCond  = partitionEntries(incoming.condOverrides, true)

    -- Only incoming GROUPS that still carry something come along: taken when a
    -- SURVIVING incoming entry references it, or an incoming fork passing its gate
    -- below does -- a subset import of one module must not populate the dropdown with
    -- the exporter's unrelated groups as dead cards. Recipient groups are never touched.
    local rfImported = importedFolders["EllesmereUIRaidFrames"] and true or false
    -- layoutExcluded (stamped by ExportProfile / the import dialog when
    -- "Include layout" is OFF): layout was deliberately excluded, so the fork
    -- stores must be KEPT from the base copy -- taking the branch below with
    -- nil incoming tables would wipe the recipient's group layouts.
    local takeUnlockForks = not partial and incoming.layoutExcluded ~= true
    local specNeeded, condNeeded = {}, {}
    for _, e in ipairs(incSpec) do
        if e.group ~= nil then specNeeded[e.group] = true end
    end
    for _, e in ipairs(incCond) do
        if e.group ~= nil then condNeeded[e.group] = true end
        if type(e.values) == "table" then
            for k in pairs(e.values) do
                if k ~= "default" then condNeeded[k] = true end
            end
        end
    end
    -- Forks reference groups via layout keys and active pointers (a spec
    -- store's active can point at a COND group via "cond:N").
    local function noteForkGids(store, needed, condNeededToo)
        if type(store) ~= "table" then return end
        for gid in pairs(store.layouts or {}) do needed[gid] = true end
        for gid in pairs(store.groups or {}) do needed[gid] = true end   -- legacy shape
        local a = store.active
        if type(a) == "number" then needed[a] = true end
        if condNeededToo and type(a) == "string" then
            local cg = tonumber(a:match("^cond:(%d+)$"))
            if cg then condNeededToo[cg] = true end
        end
    end
    if takeUnlockForks then
        noteForkGids(incoming.specUnlockOverrides, specNeeded, condNeeded)
        noteForkGids(incoming.condUnlockOverrides, condNeeded)
    end
    if rfImported then
        noteForkGids(incoming.specBmOverrides, specNeeded, condNeeded)
        noteForkGids(incoming.condBmOverrides, condNeeded)
        noteForkGids(incoming.specDmOverrides, specNeeded, condNeeded)
        noteForkGids(incoming.condDmOverrides, condNeeded)
    end

    local function filterGroups(groups, needed)
        local out = {}
        for _, g in ipairs(groups or {}) do
            if g.id ~= nil and needed[g.id] then out[#out + 1] = g end
        end
        return out
    end

    -- Group unions (referenced incoming groups only) + id remaps.
    local specRemap, condRemap = {}, {}
    if incoming.specOverrideGroups then
        local wanted = filterGroups(incoming.specOverrideGroups, specNeeded)
        if #wanted > 0 then
            local unioned, remap, nextId = unionGroups(merged.specOverrideGroups, wanted, sameSpecGroup)
            merged.specOverrideGroups = unioned
            specRemap = remap
            merged.specOverrideNextId = math.max(
                merged.specOverrideNextId or 0, incoming.specOverrideNextId or 0, nextId or 0)
        end
    end
    if incoming.condOverrideGroups then
        local wanted = filterGroups(incoming.condOverrideGroups, condNeeded)
        if #wanted > 0 then
            local unioned, remap = unionGroups(merged.condOverrideGroups, wanted, sameCondGroup)
            merged.condOverrideGroups = unioned
            condRemap = remap
        end
    end

    -- Apply the remaps to the surviving incoming entries, then concatenate
    -- with the recipient's kept entries.
    for _, e in ipairs(incSpec) do
        if e.group and specRemap[e.group] then e.group = specRemap[e.group] end
        keptSpec[#keptSpec + 1] = e
    end
    for _, e in ipairs(incCond) do
        if e.group and condRemap[e.group] then e.group = condRemap[e.group] end
        remapEntryValues(e, condRemap)
        keptCond[#keptCond + 1] = e
    end
    merged.specOverrides = keptSpec
    merged.condOverrides = keptCond

    -- Unlock layout forks: cross-module whole-layout snapshots. Full import:
    -- drop kept, take incoming (remapped; old-format strings may carry the
    -- legacy {groups, baseline, applied} shape, remapped too). Partial import:
    -- keep the recipient's, never take incoming.
    if takeUnlockForks then
        if incoming.specUnlockOverrides then
            local t = DeepCopy(incoming.specUnlockOverrides)
            t.layouts = remapKeys(t.layouts, specRemap)
            t.groups  = remapKeys(t.groups, specRemap)
            if type(t.applied) == "table" and next(specRemap) then
                for el, gid in pairs(t.applied) do t.applied[el] = specRemap[gid] or gid end
            end
            t.active = remapActive(t.active, specRemap, condRemap)
            merged.specUnlockOverrides = t
        else
            merged.specUnlockOverrides = nil
        end
        if incoming.condUnlockOverrides then
            local t = DeepCopy(incoming.condUnlockOverrides)
            t.layouts = remapKeys(t.layouts, condRemap)
            merged.condUnlockOverrides = t
        else
            merged.condUnlockOverrides = nil
        end
    end

    -- Buff Manager forks: Raid Frames data, so per-module rule -- full
    -- replacement when RF is imported, untouched when not.
    if importedFolders["EllesmereUIRaidFrames"] then
        if incoming.specBmOverrides then
            local t = DeepCopy(incoming.specBmOverrides)
            t.layouts = remapKeys(t.layouts, specRemap)
            t.active = remapActive(t.active, specRemap, condRemap)
            merged.specBmOverrides = t
        else
            merged.specBmOverrides = nil
        end
        if incoming.condBmOverrides then
            local t = DeepCopy(incoming.condBmOverrides)
            t.layouts = remapKeys(t.layouts, condRemap)
            merged.condBmOverrides = t
        else
            merged.condBmOverrides = nil
        end
        if incoming.specDmOverrides then
            local t = DeepCopy(incoming.specDmOverrides)
            t.layouts = remapKeys(t.layouts, specRemap)
            t.active = remapActive(t.active, specRemap, condRemap)
            merged.specDmOverrides = t
        else
            merged.specDmOverrides = nil
        end
        if incoming.condDmOverrides then
            local t = DeepCopy(incoming.condDmOverrides)
            t.layouts = remapKeys(t.layouts, condRemap)
            merged.condDmOverrides = t
        else
            merged.condDmOverrides = nil
        end
    end

    -- NO post-import default re-bank. Imported entries carry the exporter's recorded
    -- values.default, consistent with the imported addon blobs by construction
    -- (per-folder partition above). A RebaselineDefaults follow-up here would
    -- overwrite those defaults with the imported LIVE blob -- the exporter's CURRENT
    -- SPEC's override values, not defaults -- destroying the true defaults and
    -- bleeding one spec's values into every unassigned spec. RebaselineDefaults stays
    -- defined but must NEVER be wired back into the import flow.
end

--- Rewrites override entry DEFAULT maps (both stores) from the live profile, then
--- rebuilds both fkey indexes. Runs once right after a profile import lands: kept
--- entries' defaults were captured against the PREVIOUS profile, and restoring
--- those stale values when an override deactivates would permanently overwrite the
--- imported profile's own settings. Per-spec/per-group values are absolute and
--- untouched. MUST run before the overlays re-apply (SpecOverrides_ApplyValues),
--- while live still holds the pure imported values. folderSet limits the re-bank
--- to the given addon folders (partial imports: kept folders' profile tables can
--- hold ACTIVE override values, which must never be banked as defaults); nil = all.
function EllesmereUI.SpecOverrides_RebaselineDefaults(folderSet)
    -- Never re-bank while an editing view holds swapped values live (the import
    -- flow closes sessions first; this guards any other caller).
    if _editGroup or _defaultView or Cond._edit then return end
    local function Rebank(store)
        for _, entry in ipairs(store or {}) do
            local def = entry.values and entry.values.default
            if def then
                for fkey in pairs(def) do
                    local folder = SplitFKey(fkey)
                    -- Folder filter + loaded-module guard: an unloaded child
                    -- addon has no Lite DB, so ReadLive returns nil for EVERY
                    -- fkey and nil-poisons the whole default map.
                    if folder and (not folderSet or folderSet[folder]) and DBFor(folder) then
                        local live = ReadLive(fkey)
                        -- Table values are never banked (aliasing/reference-
                        -- compare policy); keep the stored default.
                        if type(live) ~= "table" then
                            def[fkey] = (live == nil) and NIL_SENT or live
                        end
                    end
                end
            end
        end
    end
    Rebank(GetStore())
    Rebank(Cond.GetStore())
    RebuildFKeyIndex()
    Cond.RebuildIndex()
end

--- Prune: strip blacklisted folders, spec-owned fkeys (spec-wins eviction),
--- excluded-context entries, and maps for deleted groups; drop empty entries.
function Cond.PruneEntries()
    local store = Cond.GetStore()
    if not store then return end
    local removed = false
    for i = #store, 1, -1 do
        local e = store[i]
        local drop = false
        if e.module then
            local ex = EXCLUDED_CONTEXTS[e.module]
            if ex == true then drop = true
            elseif type(ex) == "table" and e.page then
                local pex = ex[e.page]
                if pex == true then drop = true
                elseif type(pex) == "table" and e.section and pex[e.section] then drop = true end
            end
        end
        if not drop and e.group ~= nil
           and not (EllesmereUI.Conditions_GroupById and EllesmereUI.Conditions_GroupById(e.group)) then
            drop = true
        end
        if not drop and e.values and e.values.default then
            -- Blacklisted paths strip; SPEC-OWNED fkeys are deliberately KEPT (dormant):
            -- spec wins at runtime, but the conditional's value must survive so it
            -- resumes if the spec override is removed -- stripping here would
            -- permanently destroy it the moment the setting gains a spec override.
            for fkey in pairs(e.values.default) do
                if BlacklistedFKey(fkey) then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then m[fkey] = nil end
                    end
                    removed = true
                end
            end
            if not next(e.values.default) then drop = true end
        end
        if drop then
            table.remove(store, i)
            removed = true
        end
    end
    if removed then Cond.RebuildIndex() end
end

--- The engine's transition handler: harvest the outgoing group, overlay the
--- incoming one, swap unlock layers, refresh. Returns false when the value
--- system is mid-swap (spec transition / edit sessions); the engine retries on
--- its next signal (the spec Apply tail calls Conditions_Recheck).
local _condBusy = false   -- re-entrancy latch (see below)

-- _defaultView is deliberately NOT a refusal reason: the engine steps OUT of the
-- Default view for the duration of a real flip (Conditions_Recheck ->
-- SpecOverrides_SuspendDefaultView) and back in once the applied pointer has
-- advanced, so live is canonical here as on every other boundary. Refusing instead
-- would strand the flip whenever the panel is open -- for the Dark Mode condition
-- that is ALWAYS (its only inputs are options widgets).
function EllesmereUI.SpecOverrides_CondTransition(oldGid, newGid, establish)
    if _inTransition or _editGroup or Cond._edit then return false end
    -- NON-RE-ENTRANT: the refresh fan-out below can reach RefreshAllAddons
    -- (unmapped-folder fallback, module internals), whose tail calls
    -- Conditions_MarkStale + Recheck; re-entering mid-flight rewrites values
    -- against a stale applied pointer and recurses until the client watchdog kills
    -- the frame. Refuse; the engine flags the flip pending and the next signal (or
    -- the establish flag) converges it.
    if _condBusy then return false end
    _condBusy = true
    -- Values: bank the outgoing state, write the incoming one. An ESTABLISH transition
    -- (post profile-apply) has no outgoing owner: live is the incoming store's raw data
    -- (possibly the EXPORTER's overlaid state), so banking it corrupts the new
    -- profile's default maps and baseline layer. Apply only; never harvest.
    if not establish then
        Cond.Harvest(oldGid)
    end
    -- Unlock/BM layout: bank live into whichever layer is live now, BEFORE the
    -- incoming conditional's values are written -- value writes mutate module
    -- settings (sizes) that a later harvest would bank into the OUTGOING layer's
    -- elems. Re-resolution uses the NEW applied gid, passed explicitly (the engine
    -- updates its pointer only after this handler succeeds).
    if not establish and EllesmereUI.SpecOverrides_HarvestUnlockLayout then
        EllesmereUI.SpecOverrides_HarvestUnlockLayout()
    end
    if not establish and EllesmereUI.SpecOverrides_HarvestBmLayout then
        EllesmereUI.SpecOverrides_HarvestBmLayout()
    end
    if not establish and EllesmereUI.SpecOverrides_HarvestDmLayout then
        EllesmereUI.SpecOverrides_HarvestDmLayout()
    end
    local touched = Cond.WriteValues(newGid)
    if EllesmereUI.SpecOverrides_ApplyUnlock then
        Cond._resolveOverride = newGid or false   -- false = explicit none
        -- Forced on establish: the incoming raw stores may hold the layer that
        -- was live at export/save time while the imported active pointer was
        -- reset, and a nil==nil early-out would strand them.
        EllesmereUI.SpecOverrides_ApplyUnlock(CurrentSpecID(), establish)
        EllesmereUI.SpecOverrides_ApplyBm(CurrentSpecID(), establish)
        EllesmereUI.SpecOverrides_ApplyDm(CurrentSpecID(), establish)
        Cond._resolveOverride = nil
    end
    if touched then RunRefreshers(touched) end
    -- Condition applied/removed with the panel open: the labeled "Override
    -- Active" slot overlays must follow immediately.
    RequestGoldWalk()
    _condBusy = false
    return true
end

--- The conditional gid unlock layer resolution should use: during a condition
--- transition the engine's applied pointer is still the OLD one, so the handler
--- passes the target explicitly via _resolveOverride.
function Cond.ResolveGid()
    local ov = Cond._resolveOverride
    if ov ~= nil then
        return ov or nil
    end
    return EllesmereUI.Conditions_AppliedGid and EllesmereUI.Conditions_AppliedGid() or nil
end

I.Cond, I.EXCLUDED_CONTEXTS = Cond, EXCLUDED_CONTEXTS
I.broken = false
