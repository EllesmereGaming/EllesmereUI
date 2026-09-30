if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_VisibilityRules.lua
--  Visibility dropdown values, option lanes and the runtime checks modules
--  evaluate them with (the event dispatcher is EllesmereUI_Visibility.lua).
--  Loads right after EllesmereUI.lua; nothing here is read at load time.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
--  Shared Visibility System -- unified visibility dropdown values, checkbox dropdown items, and runtime checks used by CDM, Action Bars, Resource Bars, and Unit Frames.
-------------------------------------------------------------------------------

-- Dropdown 1: Visibility mode
EllesmereUI.VIS_VALUES = {
    never      = "Never",
    always     = "Always",
    mouseover  = "Mouseover",
    in_combat      = "In Combat",
    out_of_combat  = "Out of Combat",
    in_raid        = "In Raid Group",
    in_party   = "In Party",
    solo       = "Solo",
}
EllesmereUI.VIS_ORDER = { "never", "always", "mouseover", "in_combat", "out_of_combat", "---", "in_raid", "in_party", "solo" }

-- Action Bars variant: adds "When Dragonriding". The secure action bars (1-8, stance, pet)
-- express it as [advflyable,flying] in their state driver, which re-evaluates the flying
-- transition in real time. Lua-side modules catch the same transition via the gliding edge events registered in EllesmereUI_Visibility.lua (gated on EllesmereUI._hasGlidingEvent).
EllesmereUI.VIS_VALUES_AB = {
    never      = "Never",
    always     = "Always",
    mouseover  = "Mouseover",
    in_combat      = "In Combat",
    out_of_combat  = "Out of Combat",
    show_dragonriding = "When Dragonriding",
    show_not_dragonriding = "When Not Dragonriding",
    in_raid        = "In Raid Group",
    in_party   = "In Party",
    solo       = "Solo",
}
EllesmereUI.VIS_ORDER_AB = { "never", "always", "mouseover", "in_combat", "out_of_combat", "show_dragonriding", "show_not_dragonriding", "---", "in_raid", "in_party", "solo" }

-- CDM variant (no mouseover -- CDM bars don't support mouseover visibility)
EllesmereUI.VIS_VALUES_CDM = {
    never          = "Never",
    always         = "Always",
    in_combat      = "In Combat",
    out_of_combat  = "Out of Combat",
    in_raid        = "In Raid Group",
    in_party       = "In Party",
    solo           = "Solo",
}
EllesmereUI.VIS_ORDER_CDM = { "never", "always", "in_combat", "out_of_combat", "---", "in_raid", "in_party", "solo" }

-- Checkbox dropdown 2: Visibility Options (keys match DB fields). Every entry is
-- evaluated by CheckVisibilityOptions below, so any module using that evaluator
-- may offer the whole list; the skyriding edge (PLAYER_CAN_GLIDE_CHANGED /
-- PLAYER_IS_GLIDING_CHANGED) is registered by the dispatcher and by every
-- self-evaluating module already.
EllesmereUI.VIS_OPT_ITEMS = {
    { key = "visOnlyInstances",    label = "Only Show in Instances" },
    { key = "visHideHousing",      label = "Hide in Housing" },
    { key = "visOnlyHousing",      label = "Only Show in Housing",
      tooltip = "This element will only show while you are inside a house or plot" },
    { key = "visHideMounted",      label = "Hide when Mounted" },
    { key = "visHideDragonriding", label = "Hide when Skyriding Mounted",
      tooltip = "Hides this element while you are on a skyriding (glide-capable) mount, where Blizzard shows its vigor HUD." },
    { key = "visOnlyMounted",      label = "Only Show when Mounted",
      tooltip = "This element will only show while you are mounted" },
    { key = "visHideNoTarget",     label = "Hide without Target",
      tooltip = "*Blizzard's auto targeting (soft target) setting can cause brief flickering when your actual target dies but a soft-target is still active." },
    { key = "visHideNoEnemy",      label = "Hide without Enemy Target",
      tooltip = "This bar will only show if you have an enemy targeted" },
}

-- Every visibility-option DB field, including the counter-lane keys that have
-- no row in the legacy VIS_OPT_ITEMS list above (they exist only as Hide/Show lanes
-- in the unified Visibility row, EllesmereUI.VIS_ROW_ITEMS). Sync copies and equality
-- checks iterate THIS list so a lane set through the unified row is never dropped by
-- a module still building the legacy pair of dropdowns.
EllesmereUI.VIS_OPT_KEYS = {
    "visOnlyInstances", "visHideInstances",
    "visOnlyDungeons", "visHideDungeons",
    "visHideHousing", "visOnlyHousing",
    "visHideMounted", "visOnlyMounted",
    "visHideDragonriding", "visOnlySkyriding",
    "visHideNoTarget", "visHideWithTarget",
    "visHideNoEnemy", "visHideWithEnemy",
    "visOnlyResting", "visHideResting",
    "visOnlyVehicle", "visHideVehicle",
    "visOnlyPartyMode", "visHidePartyMode",
}

-- Cache player class once at load time (never changes).
local _, _playerClass = UnitClass("player")

-- Druid mount-like form spell IDs. Travel Form applies a player aura with spell ID 783
-- regardless of the active ground/swim/fly subform, so an aura lookup is the most reliable cross-patch detection.
local DRUID_MOUNT_FORM_SPELLS = {
    783,    -- Travel Form
    1066,   -- Aquatic Form
    33943,  -- Flight Form
    40120,  -- Swift Flight Form
    165962, -- Flight Form (variant)
    210053, -- Mount Form (variant)
}

-- Instanced-content probe shared by the Instances axis' veto chain and its per-axis
-- "any" match verdict. A garrison reports a difficulty but is not instanced content
-- for this axis, which is why the difficulty test alone is not enough.
function EllesmereUI.IsInInstancedContent()
    local _, iType = GetInstanceInfo()
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return false
    end
    return iType == "party" or iType == "raid" or iType == "scenario"
        or iType == "arena" or iType == "pvp"
end

-- Dungeons axis probe: five-player dungeons only, Mythic+ included. Delves report as
-- scenarios, so a Dungeons lane leaves them alone where the Instances lane does not.
function EllesmereUI.IsInDungeon()
    local _, iType = GetInstanceInfo()
    if iType ~= "party" then return false end
    return not (C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap())
end

-- Runtime check: returns true if the element should be HIDDEN by visibility options.
-- `opts` is the settings table containing the vis option booleans.
function EllesmereUI.IsPlayerMountedLike()
    -- Fast path for regular mounts.
    if IsMounted and IsMounted() then return true end

    -- Only druids have mount-like shapeshift forms.
    if _playerClass ~= "DRUID" then return false end

    -- Engine form category first: ground Travel and Mount Form report 3, Aquatic 4, Flight 27.
    -- Spell-agnostic, so it keeps working when the form aura's spell ID drifts across patches
    -- (Flight Form stopped matching the aura list below); no collision with combat forms (Cat 1, Bear 5, Moonkin 31).
    if GetShapeshiftFormID then
        local formID = GetShapeshiftFormID()
        if formID == 3 or formID == 4 or formID == 27 then
            return true
        end
    end

    -- Aura fallback: the Travel Form buff is present on the player
    -- whenever the druid is shifted, regardless of ground/swim/fly subform.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for i = 1, #DRUID_MOUNT_FORM_SPELLS do
            if C_UnitAuras.GetPlayerAuraBySpellID(DRUID_MOUNT_FORM_SPELLS[i]) then
                return true
            end
        end
    end

    return false
end

-- canGlide is already scoped to being on a glide-capable mount or form, so it
-- needs no mount-shaped prefilter. IsPlayerMountedLike used to gate this and
-- hard-returns false off DRUID, which silently excluded the non-druid flight
-- forms (Dracthyr Soar, Haranir) from "Hide when Skyriding Mounted". Deliberately
-- no IsFlying() term: unlike the show/hide visibility MODES, this option fires
-- on the ground too, as soon as the skyriding bar is available.
function EllesmereUI.IsPlayerSkyriding()
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local _, canGlide = C_PlayerInfo.GetGlidingInfo()
        return canGlide == true
    end
    return false
end

-- Non-macro visibility subset: the options that CAN'T be expressed in a secure [macro] condition
-- and must be evaluated in Lua. Used by secure action bar frames that delegate the macro-expressible options (target/combat/group) to their state-visibility driver and only need Lua handling for these three.
-- skipMountAxis: the caller's secure state driver already carries [mounted]/[nomounted]
-- clauses that self-update inside combat. Evaluating the mount axis here too would let
-- Lua clobber the driver with a literal "hide" that cannot re-evaluate until combat ends
-- (see BuildVisibilityString in EllesmereUIActionBars.lua). Such callers pass true and
-- keep their own narrower mount check for the shapeshift forms [mounted] cannot see.
function EllesmereUI.CheckVisibilityOptionsNonMacro(opts, skipMountAxis)
    if not opts then return false end
    if EllesmereUI.VisOverrideValue and EllesmereUI.VisOverrideValue(opts) then return false end

    -- Any match: only the SHOW lanes are disjuncts, owned by EvalVisibilityExtended (or
    -- the secure driver build path). The HIDE lanes stay vetoes in every match mode, so
    -- they run here too -- see EllesmereUI.VisOptionHideVeto.
    -- No live caller: every Action Bars site gates on visibilityMatch ~= "any", and
    -- CheckVisibilityOptions settles Any before calling in. Kept anyway, because removing
    -- it would drop an Any store into the All veto chain, where SHOW lanes read as vetoes.
    -- Divergence on purpose: the All chain flags only the skyriding lanes "mountaxis",
    -- this one every combatFlip lane. combatFlip is the honest test, a bare "hide" from
    -- any of them being a constant no driver can re-evaluate in combat, so widen the All
    -- chain to match if this ever gains a caller; do not narrow this one.
    if opts.visibilityMatch == "any" then
        local fired, combatFlip = EllesmereUI.VisOptionHideVeto(opts, "nonMacro", nil, skipMountAxis)
        if not fired then return false end
        return combatFlip and "mountaxis" or true
    end

    -- Instances axis: Only Show in Instances / Hide in Instances share one probe.
    if opts.visOnlyInstances or opts.visHideInstances then
        local inInstance = EllesmereUI.IsInInstancedContent()
        if opts.visOnlyInstances and not inInstance then return true end
        if opts.visHideInstances and inInstance then return true end
    end

    -- Dungeons axis: Only Show in Dungeons / Hide in Dungeons share one probe.
    if opts.visOnlyDungeons or opts.visHideDungeons then
        local inDungeon = EllesmereUI.IsInDungeon()
        if opts.visOnlyDungeons and not inDungeon then return true end
        if opts.visHideDungeons and inDungeon then return true end
    end

    -- Hide in Housing
    if opts.visHideHousing then
        if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
            return true
        end
    end

    -- Only Show in Housing (inverse of the above; same probe, same edges)
    if opts.visOnlyHousing then
        if not (C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot()) then
            return true
        end
    end

    if not skipMountAxis then
        -- Hide when Mounted (includes druid travel/flight/aquatic forms)
        if opts.visHideMounted then
            if EllesmereUI.IsPlayerMountedLike() then return true end
        end

        -- Only Show when Mounted (inverse; druid mount-like forms count as mounted
        -- here too -- secure action bars carry a [nomounted] clause instead, which
        -- cannot see forms, see BuildVisibilityString)
        if opts.visOnlyMounted then
            if not (EllesmereUI.IsPlayerMountedLike()) then return true end
        end
    end

    -- Skyriding-mount axis (glide capability, ground included -- NOT the airborne
    -- show_dragonriding / show_not_dragonriding mode pair, which additionally
    -- requires IsFlying; see EllesmereUI.IsAirborneSkyriding). No secure macro token
    -- expresses "ground included", so this stays Lua-only for every caller; it returns
    -- the truthy marker "mountaxis" so a secure-driver caller can bake a combat escape
    -- hatch into what it writes (a bare "hide" cannot re-evaluate once combat starts).
    if opts.visHideDragonriding then
        if EllesmereUI.IsPlayerSkyriding() then return "mountaxis" end
    end

    if opts.visOnlySkyriding then
        if not (EllesmereUI.IsPlayerSkyriding()) then return "mountaxis" end
    end

    -- Resting axis: Only Show while Resting / Hide while Resting share one probe.
    if opts.visOnlyResting or opts.visHideResting then
        local resting = IsResting() and true or false
        if opts.visOnlyResting and not resting then return true end
        if opts.visHideResting and resting then return true end
    end

    -- Vehicle axis: Only Show in Vehicle / Hide in Vehicle share one probe.
    if opts.visOnlyVehicle or opts.visHideVehicle then
        local inVehicle = UnitInVehicle("player") and true or false
        if opts.visOnlyVehicle and not inVehicle then return true end
        if opts.visHideVehicle and inVehicle then return true end
    end

    -- Party Mode axis: Only Show during Party Mode / Hide during Party Mode.
    -- A plain true (not "mountaxis") on purpose: Party Mode can start or stop
    -- inside combat (Bloodlust, the celebration timer), where a secure driver
    -- cannot be rewritten. A constant hide HOLDS the pre-combat state through
    -- the fight and catches up on combat end (EllesmereUI.FireVisEdge re-fires
    -- then); the "[nocombat] hide" escape hatch would instead pop a "Hide during
    -- Party Mode" bar back on screen the moment combat starts.
    if opts.visOnlyPartyMode or opts.visHidePartyMode then
        local party = EllesmereUI.IsPartyModeActive()
        if opts.visOnlyPartyMode and not party then return true end
        if opts.visHidePartyMode and party then return true end
    end

    return false
end

function EllesmereUI.CheckVisibilityOptions(opts)
    if not opts then return false end
    -- An override replaces the whole Visibility configuration, option lanes included:
    -- "Always" set on an override means always, whatever the shared value hides.
    if EllesmereUI.VisOverrideValue and EllesmereUI.VisOverrideValue(opts) then return false end

    -- Any match: only the SHOW lanes are disjuncts; the HIDE lanes veto here as they do
    -- under All (EllesmereUI.VisOptionHideVeto), which is what makes "Hide when X" mean
    -- hide for every Lua consumer regardless of the match mode.
    if opts.visibilityMatch == "any" then
        return EllesmereUI.VisOptionHideVeto(opts) and true or false
    end

    -- Instances / housing / mounted (shared with secure-frame fast path).
    if EllesmereUI.CheckVisibilityOptionsNonMacro(opts) then return true end

    -- Target axis
    if opts.visHideNoTarget then
        if not UnitExists("target") then return true end
    end
    if opts.visHideWithTarget then
        if UnitExists("target") then return true end
    end

    -- Enemy-target axis
    if opts.visHideNoEnemy then
        if not (UnitExists("target") and UnitCanAttack("player", "target")) then return true end
    end
    if opts.visHideWithEnemy then
        if UnitExists("target") and UnitCanAttack("player", "target") then return true end
    end

    return false
end

-- Party Mode visibility axis ---------------------------------------------------
-- Party Mode has no game event, so it brings its own edge: EllesmereUI_PartyMode.lua
-- calls FireVisEdge after every start/stop (options page, keybind, random timer,
-- Bloodlust, celebration end). Each module that evaluates visibility on its own
-- event frame registers its refresh here once; dispatcher-driven modules (Minimap,
-- Friends, Chat, Damage Meters, Quest Tracker) are covered by RequestVisibilityUpdate.
-- An edge that lands in combat re-fires once on PLAYER_REGEN_ENABLED, because secure
-- consumers (Action Bars) cannot rewrite their drivers until then.
function EllesmereUI.IsPartyModeActive()
    return (EllesmereUIDB and EllesmereUIDB.partyMode) and true or false
end
do
    local callbacks = {}
    local pending = false
    function EllesmereUI.RegisterVisEdge(fn)
        if type(fn) == "function" then callbacks[#callbacks + 1] = fn end
    end
    local function Run()
        pending = false
        if EllesmereUI.RequestVisibilityUpdate then EllesmereUI.RequestVisibilityUpdate() end
        for i = 1, #callbacks do callbacks[i]() end
    end
    function EllesmereUI.FireVisEdge()
        if InCombatLockdown() then
            EllesmereUI.CombatQueue.Defer("FireVisEdge", EllesmereUI.FireVisEdge)
        end
        -- Coalesced and deferred one frame: a clean execution context, and a
        -- toggle that stops and restarts in one frame costs one pass.
        if pending then return end
        pending = true
        C_Timer.After(0, Run)
    end
end

-- Option-lane axes: one axis per condition (Show lane, Hide lane, probe() = holds now),
-- read by the "any" match for per-axis verdicts; the "all" veto chain above is untouched.
-- luaOnly = no macro conditional exists, so the secure driver resolves the axis in Lua.
-- combatFlip = the probe can change INSIDE combat, where a secure driver cannot be
-- rewritten, so a hide verdict from this axis must not compile to a bare dead "hide".
EllesmereUI.VIS_OPT_AXES = {
    { show = "visOnlyInstances", hide = "visHideInstances", luaOnly = true,
      probe = function() return EllesmereUI.IsInInstancedContent() end },
    { show = "visOnlyDungeons", hide = "visHideDungeons", luaOnly = true,
      probe = function() return EllesmereUI.IsInDungeon() end },
    { show = "visOnlyHousing", hide = "visHideHousing", luaOnly = true,
      probe = function()
          return (C_Housing and C_Housing.IsInsideHouseOrPlot
              and C_Housing.IsInsideHouseOrPlot()) and true or false
      end },
    { show = "visOnlyMounted", hide = "visHideMounted", combatFlip = true,
      probe = function() return EllesmereUI.IsPlayerMountedLike() end },
    { show = "visOnlySkyriding", hide = "visHideDragonriding", luaOnly = true, combatFlip = true,
      probe = function() return EllesmereUI.IsPlayerSkyriding() end },
    { show = "visOnlyResting", hide = "visHideResting", luaOnly = true,
      probe = function() return IsResting() and true or false end },
    { show = "visOnlyVehicle", hide = "visHideVehicle", luaOnly = true, combatFlip = true,
      probe = function() return UnitInVehicle("player") and true or false end },
    -- Not combatFlip, deliberately: see the Party Mode axis in
    -- CheckVisibilityOptionsNonMacro -- a secure bar holds its pre-combat state
    -- and catches up when combat ends, instead of popping back mid-fight.
    { show = "visOnlyPartyMode", hide = "visHidePartyMode", luaOnly = true,
      probe = function() return EllesmereUI.IsPartyModeActive() end },
    -- needsEdge: [exists]/[harm] re-evaluate on soft-target changes that
    -- UnitExists("target") ignores; a consumer without those edges resolves the axis in Lua.
    { show = "visHideNoTarget", hide = "visHideWithTarget", needsEdge = "softTarget",
      probe = function() return UnitExists("target") and true or false end },
    { show = "visHideNoEnemy", hide = "visHideWithEnemy", needsEdge = "softTarget",
      probe = function()
          return (UnitExists("target") and UnitCanAttack("player", "target")) and true or false
      end },
}

-- Whether this axis has to be resolved in Lua for a consumer with these edges.
-- `edges` is the set of event edges the consumer actually watches, e.g.
-- { softTarget = true } for Action Bars, which owns that machinery.
function EllesmereUI.VisAxisIsLuaOnly(ax, edges)
    if ax.luaOnly then return true end
    return ax.needsEdge ~= nil and not (edges and edges[ax.needsEdge])
end

-- Hide-lane veto, evaluated in EVERY match mode: Match Mode governs how the SHOW side
-- combines, a checked Hide lane always hides. As a disjunct it instead passed whenever
-- its condition was FALSE, so one Hide lane out-voted every Show condition.
-- filter/edges follow TallyVisibilityOptionAxes below, plus "nonMacro" for the subset
-- CheckVisibilityOptionsNonMacro owns; skipMount serves its skipMountAxis contract.
-- Both lanes checked at once counts as unconstrained here, same as in that tally.
-- Second return: the firing axis is combatFlip, so a secure-driver caller must bake a
-- combat escape hatch instead of writing a bare "hide".
function EllesmereUI.VisOptionHideVeto(opts, filter, edges, skipMount)
    if not opts then return false end
    if EllesmereUI.VisOverrideValue and EllesmereUI.VisOverrideValue(opts) then return false end
    local axes = EllesmereUI.VIS_OPT_AXES
    for i = 1, #axes do
        local ax = axes[i]
        local skip
        if filter == "nonMacro" then
            skip = ax.needsEdge == "softTarget"
        elseif filter then
            local luaOnly = EllesmereUI.VisAxisIsLuaOnly(ax, edges)
            skip = (filter == "luaOnly" and not luaOnly) or (filter == "driver" and luaOnly)
        end
        if skipMount and ax.hide == "visHideMounted" then skip = true end
        if not skip and opts[ax.hide] and not opts[ax.show] and ax.probe() then
            return true, ax.combatFlip or false
        end
    end
    return false
end

-- Per-axis tally for the "any" match. filter: nil counts every axis, "luaOnly" only
-- the ones this consumer must resolve in Lua, "driver" only the ones it can compile.
-- Returns how many axes are constrained and how many of those currently match.
-- SHOW lanes only: a Hide lane is a veto (VisOptionHideVeto), never a disjunct.
function EllesmereUI.TallyVisibilityOptionAxes(opts, filter, edges)
    local constrained, passed = 0, 0
    if not opts then return constrained, passed end
    if EllesmereUI.VisOverrideValue and EllesmereUI.VisOverrideValue(opts) then
        return constrained, passed
    end
    local axes = EllesmereUI.VIS_OPT_AXES
    for i = 1, #axes do
        local ax = axes[i]
        local luaOnly = EllesmereUI.VisAxisIsLuaOnly(ax, edges)
        local skip = (filter == "luaOnly" and not luaOnly)
                  or (filter == "driver" and luaOnly)
        if not skip then
            -- Both lanes at once is the contradiction the row already prevents on
            -- click; count it as unconstrained rather than as an axis that can never
            -- match, so a hand-edited store cannot lock an Any selection to hidden.
            if opts[ax.show] and not opts[ax.hide] then
                constrained = constrained + 1
                if ax.probe() then passed = passed + 1 end
            end
        end
    end
    return constrained, passed
end

-- Runtime check: returns true if the element should be SHOWN based on the visibility mode
-- dropdown value. `mode` is the dropdown string; `state` is a table: { inCombat, inRaid, inParty }.
function EllesmereUI.CheckVisibilityMode(mode, state)
    if mode == "disabled" then return false end
    if mode == "never" then return false end
    if mode == "in_combat" then return state.inCombat end
    if mode == "out_of_combat" then return not state.inCombat end
    if mode == "in_raid" then return state.inRaid end
    if mode == "in_party" then return state.inParty end
    if mode == "solo" then return not state.inRaid and not state.inParty end
    if mode == "show_dragonriding" then
        -- Mirrors the secure-macro [advflyable,flying] driver: show only while airborne and
        -- glide-capable (skyriding mounts and flight forms alike). The shared predicate lives in
        -- EllesmereUI_Visibility.lua and is also used by the multi-select visibility engine.
        return (EllesmereUI.IsAirborneSkyriding and EllesmereUI.IsAirborneSkyriding()) or false
    end
    if mode == "show_not_dragonriding" then
        -- Exact inverse of show_dragonriding: show whenever NOT airborne and
        -- glide-capable (skyriding mounts and flight forms alike).
        return not (EllesmereUI.IsAirborneSkyriding and EllesmereUI.IsAirborneSkyriding())
    end
    -- "always" and "mouseover" both return true (mouseover handled separately)
    return true
end
