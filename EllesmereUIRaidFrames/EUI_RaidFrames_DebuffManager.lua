if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_RaidFrames_DebuffManager.lua
-- 12.1 Debuff Manager runtime: base-grid record union plus user-added tiles.
--
-- BASE GRID: one container group per enabled filter checkbox, negation-chained so an aura renders in exactly one
-- record wherever expressible. Priority order cc > dispel > raid > raidcombat: token records exclude higher-priority
-- ones via !TOKEN in declaration-fixed filter strings; typed-dispel has no token, excluded instead via
-- excludeDispelTypes (live candidates). Boolean records (boss/role, priority) negate every enabled token record
-- since positive-only candidates cannot be negated, so token records own their overlaps and boolean records fill in
-- the rest; boolean x boolean overlap is inexpressible and accepted.
--
-- TILES: an "icons" tile CLAIMS a category, moving its record into the tile's own container (own anchor/size/cap)
-- while negation/exclude contributions stay global (negations read the EFFECTIVE set = base checkboxes OR claims),
-- so an aura still renders exactly once. Effect tiles (glow/square/healthcolor/bar) are ADDITIVE single-category
-- signals: no claim, may overlap icon displays by design, one re-filterable slot each (live-settable, no variant
-- churn). Tile containers persist per button (frames never freed); disabled/removed tiles park hidden, and a
-- hidden container unregisters its events (zero cost).
--
-- Base records render into the EXISTING per-button debuff container via the existing style/anchor/reload
-- machinery (shared integration sites live in the containers file); legacy preset groups park at 0. Settings live
-- at ns.db.profile.dmDebuff (shared raid/party/extra, absent = off = zero cost), all keys NEW/additive as a
-- nondestructive view over the existing debuff display keys (size/spacing/cap/position); legacy debuffFilter is
-- untouched and resumes control if the manager is disabled.
--
-- Also owns BUFF MANAGER effective-state accessors (base grid + custom indicators render together; legacy
-- bmDisplayMode never written, only shimmed).

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

local AK -- EllesmereUI.AuraKit, resolved at first use

local TYPED_DEBUFFS = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }

local CORNERS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

-- Duration-bar frame levels relative to the unit button (BM bar Frame Level modes 1:1).
local BAR_FRAMELVL = {
    behindBorders = 7,   -- below the main border (+8)
    behindText    = 11,  -- below the name/health text carrier (+12)
    medium        = 13,  -- the aura band
    high          = 14,
    highest       = 15,
}

local function FlowDir(token)
    local FD = AnchorUtil.FlowDirection
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

-------------------------------------------------------------------------------
-- Buff Manager effective-state accessors (coexistence shims). Legacy bmDisplayMode is read ONLY here as the
-- default for older profiles; new keys are written only by the options page. Base grid and custom indicators enable independently and render together.
-------------------------------------------------------------------------------
function ns.BM_BaseActive()
    local p = ns.db and ns.db.profile
    if not p then return false end
    local v = p.bmBaseEnabled
    if v == nil then return p.bmDisplayMode == "simple" end
    return v == true
end

function ns.BM_CustomActive()
    local p = ns.db and ns.db.profile
    if not p then return false end
    local v = p.bmIndicatorsEnabled
    if v == nil then return (p.bmDisplayMode or "custom") == "custom" end
    return v == true
end

-------------------------------------------------------------------------------
-- Settings access
-------------------------------------------------------------------------------
local function DM()
    -- Exclude set is internal: only the hardcoded sated/always-hide presets are blacklistable (merged in
    -- BuildRecords). Saved dm.excludeSpellIDs / dm.excludeSeedV keys are inert orphans.
    local p = ns.db and ns.db.profile
    return p and p.dmDebuff
end

-- One-shot v2 filter-model upgrade per profile: checked categories now SUBTRACT from Show All instead of being
-- blocked by it. Old profiles carry add-mode category keys that Show All used to ignore; left alone they would
-- suddenly subtract content. Show All profiles reset every category key (nothing subtracted; cc nil = cc lead/glow group stays
-- on, see BuildRecords); add-mode profiles keep their selection with cc's old nil-means-on default materialized (nil now means unchecked everywhere).
local function EnsureFilterV2(dm)
    if dm.filtersV2 then return end
    dm.filtersV2 = true
    if dm.all ~= false then
        dm.boss, dm.role, dm.priority, dm.raid = nil, nil, nil, nil
        dm.raidcombat, dm.nonplayer, dm.dispel, dm.cc = nil, nil, nil, nil
    else
        dm.cc = (dm.cc ~= false) and true or nil
    end
end

-- One-shot lane split (per profile, after EnsureFilterV2): the base Filters
-- dropdown became two-lane (show/hide), so the single mode-dependent selection
-- splits into dm[cat] (SHOW lane) and dm.neg[cat] (HIDE lane). Show All
-- profiles' checked categories were subtracting -- move them to the hide lane
-- so record synthesis is bit-identical (incl. cc: checked-under-All meant "park
-- the cc group"); add-mode selections already mean SHOW and stay put.
local function EnsureFilterLanes(dm)
    if dm.lanesV1 then return end
    dm.lanesV1 = true
    if dm.all ~= false then
        local neg
        local function Move(cat)
            if dm[cat] == true then
                neg = neg or {}
                neg[cat] = true
                dm[cat] = nil
            end
        end
        Move("boss"); Move("role"); Move("priority"); Move("cc")
        Move("raid"); Move("raidcombat"); Move("dispel"); Move("nonplayer")
        if neg then dm.neg = neg end
    end
end

-- One-shot: maps the retired Auras-tab preset onto the manager, runs ONLY
-- while the profile has no dmDebuff yet (a brand-new profile maps nil/"all" preset to the defaults, harmless). No
-- display/style key mapping needed; the base grid reads legacy debuff keys directly (nondestructive view).
local function EnsureMigrated()
    local p = ns.db and ns.db.profile
    if not p then return end
    if p.dmDebuff then
        EnsureFilterV2(p.dmDebuff)
        EnsureFilterLanes(p.dmDebuff)
        return
    end
    local preset = p.debuffFilter
    local dm = { _fromPreset = preset or "default" }
    if preset == "raid" then
        dm.all = false
        dm.raid = true
        dm.raidcombat = true
    elseif preset == "dispellable" then
        dm.all = false
        dm.dispel = true
        dm.dispelMode = "you" -- the by-you token, 1:1 with the preset
    elseif preset == "none" then
        -- No disable concept: "none" = empty base grid (Show All + CC off).
        dm.all = false
        dm.cc = false
    end
    -- The retired dispellable-location split becomes a Dispellable icons tile at the old anchor, riding the
    -- "typed" dispel flavor (it covered exactly the TYPED debuffs, 1:1 parity).
    if preset ~= "none" and (p.dispellableDebuffLocation or "same") ~= "same" then
        local size = p.dispellableDebuffSize
        if not size or size <= 0 then size = p.debuffSize or 18 end
        dm.dispelMode = "typed"
        dm.tiles = { {
            id = 1, enabled = true, type = "icons",
            claim = { dispel = true },
            position = p.dispellableDebuffLocation,
            growDirection = p.dispellableDebuffGrowDirection or "CENTER",
            offsetX = p.dispellableDebuffOffsetX or 0,
            offsetY = p.dispellableDebuffOffsetY or 0,
            size = size,
            spacing = p.debuffSpacing or 1,
            cap = p.debuffCap or 3,
        } }
        dm.nextTileId = 2
    end
    p.dmDebuff = dm
    EnsureFilterV2(dm)
    EnsureFilterLanes(dm)
end

function ns.DM_Active()
    -- ALWAYS ON: the manager IS the 12.1 debuff system, no disable (an empty grid is expressed via filters); kept
    -- as a function for the containers delegation and as the migration hook. Show All + cc default on for legacy parity.
    EnsureMigrated()
    return true
end

-- Mirrors the containers file's tiny per-button helpers (that file is at its local cap; duplicating two 4-line lookups beats exporting them).
local function SettingsFor(d)
    if d._isParty then return ns._scaledPartyProxy end
    if d._isExtra then return ns._scaledExtraProxy end
    return ns._scaledProfile
end

local function ClassToken(d)
    if d._isParty then return "party" end
    if d._isExtra then return "extra" end
    return "raid"
end

local function StyleKeyFor(d)
    return "rf:debuff:" .. ClassToken(d)
end

-- The category vocabulary. token = filter-string routing (negatable); cand = candidate-boolean routing (positive-only, identity-gated).
local CATS = { "boss", "role", "priority", "cc", "raid", "raidcombat", "dispel", "nonplayer" }

-- A tile hosts a catch-all record when All Debuffs is checked, or when Has
-- Duration (an AND-modifier) is checked with no claimed categories -- checked
-- alone it acts as the timed catch-all, mirroring the base dropdown.
local function TileCatchAllOn(t)
    if t.all == true then return true end
    if t.hasDuration ~= true then return false end
    if t.claim then
        for _, v in pairs(t.claim) do
            if v then return false end
        end
    end
    return true
end

-- Fingerprint inputs the record/tile synthesis reads beyond the containers file's DebuffCfgFP (which appends this);
-- a missed key = that option never live-applies. Per-tile style keys VIEW the base debuff style keys (nil = inherit,
-- ZERO migration) via a proxy table shadowing non-nil tile keys, so the style build and its fingerprint both see
-- effective values. Declared ABOVE the config fingerprint, which must flip when overrides change (EnsureTileStyle only runs behind it).
local TILE_STYLE_KEYS = {
    iconZoom = "debuffIconZoom",
    borderSize = "debuffBorderSize", borderColor = "debuffBorderColor",
    showSwipe = "debuffShowSwipe", showDurText = "debuffShowDurText",
    durTextColor = "debuffDurTextColor", durTextSize = "debuffDurTextSize",
    durTextOffsetX = "debuffDurTextOffsetX", durTextOffsetY = "debuffDurTextOffsetY",
    showStacks = "debuffShowStacks", stacksTextColor = "debuffStacksTextColor",
    stacksTextSize = "debuffStacksTextSize",
    stacksOffsetX = "debuffStacksOffsetX", stacksOffsetY = "debuffStacksOffsetY",
    hideTooltips = "debuffHideTooltips",
}
local function TileStyleView(s, t)
    local o
    for tk, bk in pairs(TILE_STYLE_KEYS) do
        if t[tk] ~= nil then
            if not o then o = {} end
            o[bk] = t[tk]
        end
    end
    if not o then return s end
    return setmetatable(o, { __index = s })
end
-- Sorted fingerprint of one tile's style overrides (part of DM_CfgFP).
local function TileStyleFP(t)
    local o = {}
    for tk in pairs(TILE_STYLE_KEYS) do
        local tv = t[tk]
        if tv ~= nil then
            if type(tv) == "table" then
                o[#o + 1] = tk .. "=" .. string.format("%.2f,%.2f,%.2f",
                    tv.r or 0, tv.g or 0, tv.b or 0)
            else
                o[#o + 1] = tk .. "=" .. tostring(tv)
            end
        end
    end
    if #o == 0 then return "-" end
    table.sort(o)
    return table.concat(o, ";")
end

-- EFFECTS: per-filter blocks (fxList). Each entry: a filters set + optional
-- Icon Glow (glowType/glowClassColor/glowR/G/B), Border override (borderSize/
-- borderColor), and Size for matched categories (0/nil = base grid size).
-- ACTIVE = filters checked and at least one payload; FIRST matching block
-- wins per button category. Declared ABOVE the config fingerprint (its caller).
local function FxEntryActive(e)
    return e.filters ~= nil and next(e.filters) ~= nil
        and (((e.glowType or 0) > 0) or ((e.borderSize or 0) > 0)
            or ((tonumber(e.size) or 0) > 0))
end
local function FxListView(list)
    if not list then return nil end
    local out
    for i = 1, #list do
        if FxEntryActive(list[i]) then
            out = out or {}
            out[#out + 1] = list[i]
        end
    end
    return out
end
local function FxListFP(list)
    if not list or #list == 0 then return "fx0" end
    local parts = {}
    for i = 1, #list do
        local e = list[i]
        local keys = {}
        if e.filters then
            for k, on in pairs(e.filters) do if on then keys[#keys + 1] = k end end
            table.sort(keys)
        end
        local bc = e.borderColor or {}
        parts[#parts + 1] = table.concat({
            table.concat(keys, "+"),
            tostring(e.glowType or 0), e.glowClassColor and "cc" or "-",
            string.format("%.2f,%.2f,%.2f", e.glowR or 1, e.glowG or 0.776, e.glowB or 0.376),
            tostring(e.borderSize or 0),
            string.format("%.2f,%.2f,%.2f", bc.r or 0, bc.g or 0, bc.b or 0),
            tostring(e.size or 0),
        }, "|")
    end
    return "fx:" .. table.concat(parts, ";")
end
-- One-time heal: fold a legacy single fxGlow config into fxList.
local function FxHeal(owner)
    local fg = owner and owner.fxGlow
    if fg then
        owner.fxList = owner.fxList or {}
        owner.fxList[#owner.fxList + 1] = {
            filters = fg.filters or {},
            glowType = fg.type, glowClassColor = fg.classColor,
            glowR = fg.r, glowG = fg.g, glowB = fg.b,
        }
        owner.fxGlow = nil
    end
end
-- Per-filter Size for a record category: FIRST matching ACTIVE block owns the
-- category outright (same rule as the glow/border applier's DmFxBlockFor, so
-- a later block's Size never reaches an already-matched category). Merged
-- "bossrole" record matches either constituent, like the applier.
local function FxSizeFor(list, cat)
    if not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if FxEntryActive(e) then
            local f = e.filters
            if f and (f[cat] or (cat == "bossrole" and (f.boss or f.role))) then
                local sz = tonumber(e.size)
                if sz and sz > 0 then return sz end
                return nil
            end
        end
    end
end

-- Base fx accessors for the containers file (base debuff style build + FP).
function ns.DM_FxList()
    local dm = DM()
    if dm then FxHeal(dm) end
    return FxListView(dm and dm.fxList)
end
function ns.DM_FxFP()
    local dm = DM()
    if dm then FxHeal(dm) end
    return FxListFP(dm and dm.fxList)
end

-------------------------------------------------------------------------------
-- Debuff tooltip modifier ("Shown on Modifier" mode + the Use Modifier cog,
-- p.debuffTooltipModifier: none | shift | control | alt). Style-side the
-- mode renders as plain Shown (native engine tooltips, no button writes);
-- the gating is a MOTION EATER per debuff container: a frame WE own, laid
-- over the container above the engine buttons, motion-only (EnableMouse
-- false, clicks pass through untouched) and CONSUMING motion. While the
-- eater is shown, hover never reaches the aura buttons and no tooltip
-- appears (the eater forwards OnEnter/OnLeave to the unit button, so the
-- frame's own hover behaviour is untouched); holding the configured key hides it. Show/Hide on our own frames
-- stays legal while auras are secret, so this behaves identically under
-- /euidev, in instanced combat and in the open world -- unlike
-- button-surface writes (SetMouseMotionEnabled), which the engine refuses
-- under secrecy (field-confirmed 2026-08-24; the tooltip frame itself,
-- AuraButtonTooltip, is forbidden + hideFromGlobalEnv, so no alpha/hook
-- lever exists there either). The eater IS a unit button: a named
-- SecureUnitButton sub-button of the unit button (useparent-unit), so
-- targeting, the unit menu, mouseover and click-cast bindings all work on
-- the band natively; the click-cast header wraps its enter/leave (secure,
-- combat-legal) and runs the peek: the hovered eater hides itself while the
-- modifier is held, so hover falls through to the aura button beneath, and
-- re-shows on release -- one macro-conditional check per key edge and no
-- work at all for an unhovered press (see EUI_RaidFrames_ClickCast.lua,
-- tooltip-modifier eaters). Creation, geometry and parking are out-of-combat
-- writes on a protected frame; an in-combat need latches d.rfcBmPending and
-- the regen reload re-runs the ensure. "none" and the other modes cost
-- nothing: eaters park hidden and the header driver is released.
-------------------------------------------------------------------------------
function ns.DM_TipMod()
    local p = ns.db and ns.db.profile
    local m = p and p.debuffTooltipModifier
    if m == "shift" or m == "control" or m == "alt" then return m end
    return "none"
end

-- All live eaters (eater frame -> true), weak-keyed so eaters of released
-- unit buttons drop out with their hosts. Per-container handles live on the
-- unit button's own data table (d.tipModEaters, keyed "base" / tile id).
local tipModEaters = setmetatable({}, { __mode = "k" })

-- Park one eater: hide it and drop the header's peek/hover references to it.
-- Protected frame, so this is an out-of-combat write; callers latch the regen
-- reload otherwise.
local function ParkEater(e)
    e._euiActive = false
    e:Hide()
    if ns.CC_ReleaseTipEater then ns.CC_ReleaseTipEater(e) end
end

-- Is any debuff display actually in the "Shown on Modifier" mode? Base row
-- plus enabled icon tiles' overrides (nil override inherits the base).
local function TipModeInUse()
    local p = ns.db and ns.db.profile
    if not p then return false end
    if p.debuffHideTooltips == "modifier" then return true end
    local dm = DM()
    local tiles = dm and dm.tiles
    if tiles then
        for i = 1, #tiles do
            local t = tiles[i]
            if t.enabled ~= false and t.hideTooltips == "modifier" then return true end
        end
    end
    return false
end

-- Arm state + the header's peek key. The ensure pass calls this on every
-- containers reload, so login, setting edits and profile switches all land
-- here; RF fully disabled never reloads. A stored key is a no-op outside the
-- "modifier" mode: every eater parks and the header driver is released.
-- Header and eater writes are out-of-combat; in combat the calling button
-- latches the regen reload, which re-enters here.
local tipModArmed = false
-- Key last pushed to the click-cast header; starts DISARMED so a profile
-- without the feature never touches the header at all (zero cost while off).
local tipModKeyApplied = false

-- Feature wanted at all: a key is set AND some debuff display is in the
-- "modifier" mode. The apply pass gates every footprint/ensure write on this.
function ns.DM_TipModWanted()
    return ns.DM_TipMod() ~= "none" and TipModeInUse()
end

function ns.DM_TipModSync(d)
    local key = ns.DM_TipMod()
    local want = key ~= "none" and TipModeInUse()
    local wantKey = want and key or false
    if want == tipModArmed and wantKey == tipModKeyApplied then return end
    if InCombatLockdown() then
        if d then d.rfcBmPending = true end
        return
    end
    tipModArmed = want
    if wantKey ~= tipModKeyApplied then
        tipModKeyApplied = wantKey
        if ns.CC_SetTipModKey then ns.CC_SetTipModKey(wantKey or nil) end
    end
    if not want then
        for eater in pairs(tipModEaters) do
            if eater._euiActive then ParkEater(eater) end
        end
    end
end

-- Icon-tile pin: the point on the health frame the tile's flow starts from.
-- Shared by AnchorTileContainer (the container) and the tooltip eater below,
-- so the two can never drift apart.
local function TilePin(t)
    local pl = t.position or "top"
    local corner = CORNERS[pl] or "TOP"
    local point = corner
    if (t.growDirection or "CENTER") == "CENTER" then
        -- Center only the growth axis on the position point; the vertical
        -- seat stays flush with the anchored edge (see AnchorTileContainer).
        point = pl:find("top", 1, true) and "TOP"
            or (pl:find("bottom", 1, true) and "BOTTOM" or "CENTER")
    end
    return point, corner, t.offsetX or 0, t.offsetY or 0
end

-- Maximum footprint of a flow display: n cells of `cell` px with `spacing`
-- between them, wrapped every `per` cells (per < 2 = one unbounded line),
-- lines stacked across; `vertical` flips the line axis (columns). Width, height.
local function TipFootprint(n, cell, spacing, per, vertical)
    if not n or n < 1 then return 0, 0 end
    local lineCells, lines = n, 1
    if per and per >= 2 then
        if n > per then lineCells = per end
        lines = math.ceil(n / per)
    end
    local along = lineCells * cell + (lineCells - 1) * spacing
    local across = lines * cell + (lines - 1) * spacing
    if vertical then return across, along end
    return along, across
end

-- One eater per gated container; after creation only Show/Hide and, on a
-- geometry change, one re-pin ever touch it. Host = the unit button (our
-- frame). The rect is OURS end to end: pinned to the health frame at the
-- container's own pin and sized to the display's maximum footprint from
-- settings (declared caps x largest cell), never anchored to the engine
-- container -- the engine sizes that one from secret aura content, and a rect
-- container -- the engine lays the icons out around the container's anchor
-- and never resizes the container frame itself (it stays at its 1x1
-- provisional size; probed live 2026-08-25), so a frame anchored to the
-- container's corners is a 1x1 frame nobody can hover (the first field
-- builds: "tooltip always shows").
-- Motion is CONSUMED: SetPropagateMouseMotion(true) is pass-through -- it
-- un-blocks everything beneath, aura buttons included (probed live with a
-- working eater: focus stack = eater + unit button, tooltip still showed).
-- The unit frame's own hover is restored by FORWARDING: the eater's
-- OnEnter/OnLeave call the unit button's handlers with the button as self,
-- so highlight and unit tooltip behave as in every other tooltip mode.
-- Mouseover resolves through the unit button's subtree exactly as it does
-- for the aura buttons themselves.
-- CLICKS pass through: a motion-only frame is still the mouse focus, and a
-- click delivered to a focus frame with clicks disabled is dropped, nothing
-- beneath sees it (field: "clicks dead over the debuff band"). Propagating
-- clicks is the pass-through we want here -- the aura buttons beneath are
-- click-disabled (AuraKit, raid-frame styles), so the click lands on the
-- unit button exactly as it did before the eater existed.
local function ForwardEnter(self)
    local h = self:GetParent()
    local f = h and h:GetScript("OnEnter")
    if f then f(h) end
end
local function ForwardLeave(self)
    local h = self:GetParent()
    local f = h and h:GetScript("OnLeave")
    if f then f(h) end
end

-- Every write below lands on a PROTECTED frame (creation, geometry, level,
-- show/hide), so the whole apply is out-of-combat: when something actually
-- needs to change in combat the button latches d.rfcBmPending and the regen
-- reload re-runs this ensure. An unchanged eater costs a few compares and
-- never touches the frame.
local tipEaterCount = 0
local function EnsureEater(d, slot, host, container, active, pinHost, point, corner, offX, offY, w, h)
    local map = d.tipModEaters
    local e = map and map[slot]
    if not active or not pinHost then
        if e and e._euiActive then
            if InCombatLockdown() then d.rfcBmPending = true; return end
            ParkEater(e)
        end
        return
    end
    local lvl = (container:GetFrameLevel() or 1) + 30
    local geoChanged = not e or e._euiPin ~= point or e._euiCorner ~= corner
        or e._euiOX ~= offX or e._euiOY ~= offY or e._euiHost ~= pinHost
        or e._euiW ~= w or e._euiH ~= h
    local lvlChanged = not e or e._euiLvl ~= lvl
    local armChanged = not e or not e._euiActive
    if not (geoChanged or lvlChanged or armChanged) then
        e._euiContainer = container
        return
    end
    if InCombatLockdown() then d.rfcBmPending = true; return end
    if not e then
        -- Named: click-cast's frame keybinds route by frame name. Unit from
        -- the parent (useparent-unit) for the action path; the header's enter
        -- wrap also stamps a real "unit" for the engine's mouseover.
        tipEaterCount = tipEaterCount + 1
        e = CreateFrame("Button", "EUIRFTipEater" .. tipEaterCount, host, "SecureUnitButtonTemplate")
        e:RegisterForClicks("AnyUp")
        e:SetAttribute("useparent-unit", true)
        e:SetAttribute("eui_tipeater", true)
        -- Native clicks mirror the unit button: left = target, right = the
        -- secure unit menu. Click-cast re-writes these when it is enabled.
        e:SetAttribute("type1", "target")
        e:SetAttribute("*type1", "target")
        if EllesmereUI.AttachSecureUnitMenu then EllesmereUI.AttachSecureUnitMenu(e) end
        -- HookScript, not SetScript: the click-cast header wraps these same
        -- script slots securely, and a hook never displaces a wrap. The Lua
        -- side forwards the unit button's own hover (highlight, unit tooltip).
        e:HookScript("OnEnter", ForwardEnter)
        e:HookScript("OnLeave", ForwardLeave)
        e._euiD = d
        if not map then map = {}; d.tipModEaters = map end
        map[slot] = e
        tipModEaters[e] = true
        if ns.CC_RegisterTipEater then ns.CC_RegisterTipEater(e) end
    end
    e._euiContainer = container
    if lvlChanged then
        e._euiLvl = lvl
        e:SetFrameLevel(lvl)
    end
    if geoChanged then
        e._euiPin, e._euiCorner, e._euiOX, e._euiOY = point, corner, offX, offY
        e._euiHost, e._euiW, e._euiH = pinHost, w, h
        e:ClearAllPoints()
        e:SetPoint(point, pinHost, corner, offX, offY)
        e:SetSize(w, h)
    end
    if armChanged then
        e._euiActive = true
        e:Show()
    end
end

-- Per-unit ensure, called from the containers reload loop and from the tail
-- of every DM_ApplyDebuffConfig (fresh footprint inputs; tile containers
-- built on the deferred lanes re-enter through that apply): base container
-- plus every icon tile whose effective tooltip mode (own override, else the
-- base mode) is "modifier". Cheap when the feature is off -- a few reads and
-- existing eaters just park hidden.
function ns.DM_TipModEnsure(button, d, s)
    ns.DM_TipModSync(d)
    -- Off (no key, or no display in the mode): the sync above parked any
    -- eaters on the flip, so there is nothing per button to do -- zero cost.
    if not tipModArmed then return end
    local baseMode = s and s.debuffHideTooltips
    local health = d.rfcHealth
    local pinHost = health and ((ns.RF_AnchorHost and ns.RF_AnchorHost(health, s)) or health)
    local geo = d.dmTipGeo
    if d.rfcDebuffs then
        local active = baseMode == "modifier"
        local point, corner, offX, offY, w, h
        if active and pinHost and ns.RFC_DebuffPin then
            local size, spacing, per, vertical
            point, corner, offX, offY, size, spacing, per, vertical = ns.RFC_DebuffPin(s)
            local g = geo and geo.base
            w, h = TipFootprint((g and g.n) or (s.debuffCap or 3), (g and g.cell) or size,
                spacing, per, vertical)
        end
        EnsureEater(d, "base", button, d.rfcDebuffs, active and point ~= nil,
            pinHost, point, corner, offX, offY, w, h)
    end
    local hosts = d.dmTiles
    if hosts then
        local dm = DM()
        local list = dm and dm.tiles
        if list then
            for i = 1, #list do
                local t = list[i]
                local c = hosts[t.id]
                if c and t.type == "icons" then
                    local eff = t.hideTooltips
                    if eff == nil then eff = baseMode end
                    local active = t.enabled ~= false and eff == "modifier"
                    local point, corner, offX, offY, w, h
                    if active and pinHost then
                        point, corner, offX, offY = TilePin(t)
                        local grow = t.growDirection or "CENTER"
                        local g = geo and geo.tiles and geo.tiles[t.id]
                        w, h = TipFootprint((g and g.n) or (t.cap or s.debuffCap or 3),
                            (g and g.cell) or (t.size or 18), t.spacing or 1,
                            tonumber(t.iconsPerRow) or 0, (grow == "UP" or grow == "DOWN"))
                    end
                    EnsureEater(d, t.id, button, c, active and point ~= nil,
                        pinHost, point, corner, offX, offY, w, h)
                end
            end
        end
    end
end

-- Base Icons view for the CURRENT spec. The base grid lives in All Specs
-- like any indicator there, so a concrete spec can switch it off for itself
-- (ns.DM_SetBaseDisabled): every base-owned input (mode, lanes, duration
-- modifier, base effects) then reads this empty view and no base record is
-- built -- tiles, claims and the shared dispel flavor (always read off the
-- profile table) are untouched. Read-only by construction.
local BASE_OFF_VIEW = { all = false }
local function BaseView(dm)
    if ns.DM_CurrentSpecBaseOff and ns.DM_CurrentSpecBaseOff() then return BASE_OFF_VIEW end
    return dm
end

function ns.DM_CfgFP()
    EnsureMigrated() -- profile switches re-fingerprint before rendering
    local dm = DM() or {}
    FxHeal(dm)
    local bv = BaseView(dm)
    local prof = ns.db and ns.db.profile
    local neg = bv.neg
    local parts = {
        "on",
        bv.all ~= false and 1 or 0, bv.hasDuration == true and 1 or 0,
        bv.boss and 1 or 0, bv.role and 1 or 0,
        bv.priority and 1 or 0, bv.cc == true and 1 or 0, bv.raid and 1 or 0,
        bv.raidcombat and 1 or 0, bv.dispel and 1 or 0,
        bv.nonplayer and 1 or 0,
        -- Hide lane (dm.neg): subtracts in both modes, so every entry is a
        -- record-shape input.
        neg and table.concat({
            neg.boss and 1 or 0, neg.role and 1 or 0, neg.priority and 1 or 0,
            neg.cc and 1 or 0, neg.raid and 1 or 0, neg.raidcombat and 1 or 0,
            neg.dispel and 1 or 0, neg.nonplayer and 1 or 0 }, "") or "-",
        (dm.dispelMode == "typed") and "typed" or "you",
        FxListFP(bv.fxList), -- base effects force records
        -- Exclude set varies only with the lust-debuff opt-out (hardcoded lists are load-constant).
        (not prof or prof.hideLustDebuff ~= false) and "lx1" or "lx0",
    }
    -- Fingerprint the ACTIVE union: spec swaps, bucket edits and per-spec
    -- disables all land here, so the containers re-apply exactly when the
    -- rendered tile set changes (edits to buckets other specs own don't).
    local tiles = ns.DM_ActiveTiles()
    if tiles then
        for i = 1, #tiles do
            local t = tiles[i]
            parts[#parts + 1] = table.concat({
                "t", tostring(t.id), t.enabled and 1 or 0, tostring(t.type),
                tostring(t.cat), tostring(t.position), tostring(t.growDirection),
                tostring(t.offsetX), tostring(t.offsetY), tostring(t.size),
                tostring(t.spacing), tostring(t.cap), tostring(t.iconsPerRow),
                tostring(t.width), tostring(t.height),
                t.color and string.format("%.2f,%.2f,%.2f,%.2f",
                    t.color.r or 1, t.color.g or 1, t.color.b or 1, t.color.a or 1) or "-",
                tostring(t.glowType), tostring(t.glowLines), tostring(t.glowThickness),
                tostring(t.glowSpeed), tostring(t.glowColorMode), tostring(t.opacity),
                tostring(t.orientation), tostring(t.reverseFill),
                tostring(t.barFullWidth), tostring(t.barFullHeight),
                tostring(t.barColorOpacity), tostring(t.barBgOpacity),
                tostring(t.frameLevel),
                t.barBgColor and string.format("%.2f,%.2f,%.2f",
                    t.barBgColor.r or 0, t.barBgColor.g or 0, t.barBgColor.b or 0) or "-",
                t.claim and table.concat({
                    t.claim.boss and 1 or 0, t.claim.role and 1 or 0,
                    t.claim.priority and 1 or 0, t.claim.cc and 1 or 0,
                    t.claim.raid and 1 or 0, t.claim.raidcombat and 1 or 0,
                    t.claim.dispel and 1 or 0,
                    t.claim.nonplayer and 1 or 0 }, "") or "-",
                -- Tile hide lane + catch-all + duration modifier: all record-shape inputs.
                t.neg and table.concat({
                    t.neg.boss and 1 or 0, t.neg.role and 1 or 0,
                    t.neg.priority and 1 or 0, t.neg.cc and 1 or 0,
                    t.neg.raid and 1 or 0, t.neg.raidcombat and 1 or 0,
                    t.neg.dispel and 1 or 0, t.neg.nonplayer and 1 or 0 }, "") or "-",
                t.all == true and 1 or 0, t.hasDuration == true and 1 or 0,
                TileStyleFP(t),
                FxListFP(t.fxList),
            }, ",")
        end
    end
    return table.concat(parts, ":")
end

-------------------------------------------------------------------------------
-- Record synthesis
-------------------------------------------------------------------------------

-- Effective enabled flags: a category is "on" if its base checkbox is set OR
-- an enabled icons tile claims it; negations key off THESE (a claimed
-- category must still be excluded from every other record). Also resolves
-- claims[cat] = tile table (first enabled claimer wins).
local function EffectiveState(dm)
    -- Every category key is an explicit checkbox (true/nil); cc's base-grid default-on lives in the apply pass's Show All branch, not here.
    -- Show-lane checkboxes are DORMANT while Show All is on (the dropdown dims the
    -- lane and lanes persist across mode flips): a dormant pick must not leak into
    -- the eff-driven negation gates (dispelToken/!RAID/!RAID_IN_COMBAT would strip
    -- content from other records with no record of its own re-adding it). Claims
    -- and fx routing below still force categories on in both modes. Has Duration
    -- is an AND-modifier, never a mode: it does not touch the show lane.
    local eff
    if dm.all ~= false then
        eff = { cc = false }
    else
        eff = { boss = dm.boss, role = dm.role, priority = dm.priority,
            cc = dm.cc == true, raid = dm.raid, raidcombat = dm.raidcombat, dispel = dm.dispel,
            nonplayer = dm.nonplayer }
    end
    local claims = {}
    -- First enabled grid tile in catch-all state (TileCatchAllOn: All Debuffs
    -- checked, or Has Duration alone): it hosts a tile catch-all record, with
    -- the tile's hide lane and duration modifier folded in by BuildRecords.
    local claimsAll = nil
    -- The ACTIVE union (all-specs + group buckets + own spec, per-spec
    -- disables applied): claims follow whatever the current spec renders.
    local tiles = ns.DM_ActiveTiles()
    if tiles then
        for i = 1, #tiles do
            local t = tiles[i]
            if t.enabled and (t.type == "icons" or t.type == "square") then
                if not claimsAll and TileCatchAllOn(t) then claimsAll = t end
                if t.claim then
                    for c = 1, #CATS do
                        local cat = CATS[c]
                        if t.claim[cat] and not claims[cat] then
                            claims[cat] = t
                            eff[cat] = true
                        end
                    end
                end
            end
        end
    end
    return eff, claims, claimsAll
end

-- Builds ALL active records. Each: key, tokens (declaration-fixed filter
-- parts), cand (fresh candidate table), gated (candidate-boolean record),
-- tile (hosting tile table or nil = base). Also returns the cc candidate
-- table: while cc is UNCLAIMED the base drives the legacy "cc" group (fixed
-- filter, CC glow style); a claimed cc renders in its tile with the tile
-- style, and the CC glow stays a base-group property.
local function BuildRecords(s, dm)
    -- Base-owned inputs read the current spec's base view (empty when the
    -- spec switched the All Specs base grid off); dm keeps the shared flavor.
    local bv = BaseView(dm)
    local eff, claims, claimsAll = EffectiveState(bv)
    -- EFFECTS routing: per-filter icon effects need their categories as
    -- SEPARATE base records even under Show All (like claims, but rendering in
    -- the base container) so the effect can target exactly those buttons
    -- (stamped d.dmCat). Token categories negate out of the all-record;
    -- boolean categories duplicate (accepted, same limitation as claims).
    local fxCats = {}
    do
        local fl = bv.fxList
        if fl then
            for i = 1, #fl do
                local e = fl[i]
                if FxEntryActive(e) then
                    for cat, on in pairs(e.filters) do
                        if on then
                            fxCats[cat] = true
                            eff[cat] = true
                        end
                    end
                end
            end
        end
    end
    local allOn = bv.all ~= false -- Show All defaults ON (legacy "all" preset parity)
    -- Has Duration is an AND-MODIFIER (user directive 2026-08-16): it rides
    -- every base-owned record via the duration fold at the bottom. The base
    -- catch-all record joins when Show All is on, or when Has Duration is
    -- checked with no show-lane picks (checked alone = every timed debuff).
    local durOn = bv.hasDuration == true
    local anyShow = bv.boss == true or bv.role == true or bv.priority == true
        or bv.cc == true or bv.raid == true or bv.raidcombat == true
        or bv.dispel == true or bv.nonplayer == true
    local durAlone = durOn and not allOn and not anyShow
    -- HIDE lane (dm.neg): subtracts in BOTH modes. Token categories negate off
    -- every lower-ranked record (ownership rank cc > dispel > raid > raidcombat
    -- holds for subtraction too -- a higher-ranked shown category keeps its
    -- overlap, same doctrine as cc owning dispellable CC), typed dispels ride
    -- excludeDispelTypes, boolean categories use false-valued candidate booleans
    -- (nonplayer via the complementary TRUE).
    local neg = bv.neg
    local function NegHas(cat) return neg ~= nil and neg[cat] == true end
    local sub = allOn and {
        boss = NegHas("boss"), role = NegHas("role"),
        priority = NegHas("priority"), raid = NegHas("raid"),
        raidcombat = NegHas("raidcombat"), dispel = NegHas("dispel"),
        nonplayer = NegHas("nonplayer"),
    } or nil
    -- Non-cc records always exclude CROWD_CONTROL under Show All (cc group
    -- renders CC while on, and a subtracted cc -- parked by the apply pass --
    -- must stay hidden everywhere), when cc is effectively on, and when the
    -- hide lane subtracts cc in add mode.
    local ccOn = allOn or (eff.cc and true or false) or NegHas("cc")

    -- Two dispel flavors: "you" = RAID_PLAYER_DISPELLABLE token; "typed" = any dispel
    -- type (candidate include map, not tokenizable, dedup rides excludeDispelTypes instead of a !token).
    -- dispelActive covers the hide lane too: a hidden dispel category emits no
    -- record but its !token / typed exclude must still reach the others.
    local dispelOn = eff.dispel and true or false
    local dispelActive = dispelOn or NegHas("dispel")
    local dispelMode = (dm.dispelMode == "typed") and "typed" or "you"
    local dispelToken = (dispelActive and dispelMode == "you") and "RAID_PLAYER_DISPELLABLE" or nil
    -- Typed exclude applies only while the typed dispel record is really BUILT (claimed, or base without Show All)
    -- or the category is hidden, else Show All excludes debuffs nothing re-adds.
    local typedMap = dispelActive and dispelMode == "typed"
        and ((claims.dispel or fxCats.dispel or not allOn or NegHas("dispel")) and true or false)

    -- Internal exclude set: hardcoded sated list (honoring Show Lust Debuff
    -- opt-out) plus the always-hide pair. 68824's never-secret identity-gate
    -- exemption makes these real on friendly units for never-secret spells; a
    -- secret-flagged entry is accepted but inert (engine drops it silently).
    local ex = {}
    if ns.RFC_AlwaysHideDebuffs then
        for id in pairs(ns.RFC_AlwaysHideDebuffs) do ex[id] = true end
    end
    local prof = ns.db and ns.db.profile
    if (not prof or prof.hideLustDebuff ~= false) and ns.RFC_SatedDebuffs then
        for id in pairs(ns.RFC_SatedDebuffs) do ex[id] = true end
    end

    local function Cand(important, extra)
        local cf = extra or {}
        cf.excludeSpellIDs = ex
        if typedMap and not cf.includeDispelTypes then
            cf.excludeDispelTypes = TYPED_DEBUFFS
        end
        -- Add-mode hide lane, boolean categories: false-valued candidate booleans
        -- ride every positive record (never overriding a record's own positive
        -- boolean; the merged bossrole record skips both constituents). Under
        -- Show All the all-record's explicit sub block owns this instead, so
        -- legacy record shapes stay byte-identical.
        if neg and not allOn then
            if neg.boss and cf.isBossAura == nil and cf.isBossOrRoleAura == nil then cf.isBossAura = false end
            if neg.role and cf.isRoleAura == nil and cf.isBossOrRoleAura == nil then cf.isRoleAura = false end
            if neg.priority and cf.isPriorityAura == nil then cf.isPriorityAura = false end
            if neg.nonplayer and cf.isFromPlayerOrPlayerPet == nil then cf.isFromPlayerOrPlayerPet = true end
        end
        return cf
    end

    -- The cc group/record owns dispellable crowd control: its candidates must
    -- NOT carry the typed exclude (a magic stun would vanish from both).
    local ccCand = { excludeSpellIDs = ex }

    local recs = {}

    local function Neg(toks, negCC, negDispel, negRaid)
        if negCC and ccOn then toks[#toks + 1] = "!CROWD_CONTROL" end
        if negDispel and dispelToken then toks[#toks + 1] = "!" .. dispelToken end
        if negRaid and (eff.raid or NegHas("raid")) then toks[#toks + 1] = "!RAID" end
        return toks
    end

    -- Show All (or Has Duration alone) short-circuits the BASE union (other base records would be pure duplicates
    -- in one row) but tiles still render their claims; the catch-all record negates claimed TOKEN categories to
    -- stay single-rendered (boolean claims duplicate: cannot be negated). The NegHas terms are byte-identical
    -- under Show All (sub mirrors NegHas) and carry the hide lane when durAlone builds this with sub nil.
    if allOn or durAlone then
        local toks = { "HARMFUL" }
        Neg(toks, true,
            ((sub and sub.dispel) or claims.dispel or fxCats.dispel or NegHas("dispel")) and true or false,
            ((sub and sub.raid) or claims.raid or fxCats.raid or NegHas("raid")) and true or false)
        if (sub and sub.raidcombat) or claims.raidcombat or fxCats.raidcombat or NegHas("raidcombat") then toks[#toks + 1] = "!RAID_IN_COMBAT" end
        local cf = Cand(false)
        -- Subtracted boolean categories (see `sub`); fx-routed keeps its forced base record (effect wins over
        -- subtraction, same accepted edge as duplicating boolean claims). Under durAlone (add mode) Cand's own
        -- hide-lane branch already applied these.
        if sub then
            if sub.boss then cf.isBossAura = false end
            if sub.role then cf.isRoleAura = false end
            if sub.priority then cf.isPriorityAura = false end
            if sub.nonplayer then cf.isFromPlayerOrPlayerPet = true end
        end
        recs[#recs + 1] = { key = "all", tokens = toks, cand = cf }
    end

    -- Claimed crowd control: base normally rides the legacy cc group, but a claiming tile hosts cc as a normal
    -- record (fresh candidate table, NEVER the typed exclude -- see ccCand; tile style, CC glow stays base-only).
    if eff.cc and claims.cc then
        recs[#recs + 1] = { key = "cc", tokens = { "HARMFUL", "CROWD_CONTROL" },
            cand = { excludeSpellIDs = ex }, tile = claims.cc }
    end

    -- Sized base crowd control: Icon Effects Size cannot resize the legacy "cc" group (group->style binding fixed
    -- at declare), so cc becomes a base record variant carrying the CC-glow style; apply pass parks the legacy group while this record exists.
    if eff.cc and not claims.cc and FxSizeFor(bv.fxList, "cc") then
        recs[#recs + 1] = { key = "cc", tokens = { "HARMFUL", "CROWD_CONTROL" },
            cand = { excludeSpellIDs = ex } }
    end

    -- Category records: skipped in base when Show All covers them, always built for a claiming tile.
    if dispelOn and (claims.dispel or fxCats.dispel or not allOn) then
        local toks = { "HARMFUL" }
        if dispelToken then toks[#toks + 1] = dispelToken end
        Neg(toks, true, false, false)
        local cf
        if typedMap then
            cf = Cand(false, { includeDispelTypes = TYPED_DEBUFFS })
        else
            cf = Cand(false)
        end
        recs[#recs + 1] = { key = "dispel", tokens = toks, cand = cf, tile = claims.dispel }
    end
    if eff.raid and (claims.raid or fxCats.raid or not allOn) then
        recs[#recs + 1] = { key = "raid",
            tokens = Neg({ "HARMFUL", "RAID" }, true, true, false),
            cand = Cand(false), tile = claims.raid }
    end
    if eff.raidcombat and (claims.raidcombat or fxCats.raidcombat or not allOn) then
        local toks = Neg({ "HARMFUL", "RAID_IN_COMBAT" }, true, true, true)
        recs[#recs + 1] = { key = "raidcombat", tokens = toks,
            cand = Cand(false), tile = claims.raidcombat }
    end

    local function BoolTokens()
        local toks = Neg({ "HARMFUL" }, true, true, true)
        if eff.raidcombat or NegHas("raidcombat") then toks[#toks + 1] = "!RAID_IN_COMBAT" end
        return toks
    end
    -- Boss/role merge into one record only when they route to the SAME place; split claims build separate records.
    local bossTile, roleTile = claims.boss, claims.role
    local bossOn = eff.boss and (bossTile or fxCats.boss or not allOn)
    local roleOn = eff.role and (roleTile or fxCats.role or not allOn)
    if bossOn and roleOn and bossTile == roleTile then
        recs[#recs + 1] = { key = "bossrole", tokens = BoolTokens(),
            cand = Cand(true, { isBossOrRoleAura = true }), gated = true, tile = bossTile }
    else
        if bossOn then
            recs[#recs + 1] = { key = "boss", tokens = BoolTokens(),
                cand = Cand(true, { isBossAura = true }), gated = true, tile = bossTile }
        end
        if roleOn then
            recs[#recs + 1] = { key = "role", tokens = BoolTokens(),
                cand = Cand(true, { isRoleAura = true }), gated = true, tile = roleTile }
        end
    end
    if eff.priority and (claims.priority or fxCats.priority or not allOn) then
        recs[#recs + 1] = { key = "priority", tokens = BoolTokens(),
            cand = Cand(true, { isPriorityAura = true }), gated = true, tile = claims.priority }
    end

    -- Non-Player Auras: boolean record (isFromPlayerOrPlayerPet = false -- debuffs not caused by ANY player or
    -- player pet, engine-evaluated; a !PLAYER token would exclude only YOUR casts, never other players' Sated/Forbearance noise). Full
    -- token negation set keeps token categories owning their overlaps; overlap with boolean records accepted like
    -- boolean x boolean. Pure subset of the all-record under Show All, so the base skips it there; a
    -- claiming tile or a per-filter effect still forces it (same routing as the other boolean categories).
    if eff.nonplayer and (claims.nonplayer or fxCats.nonplayer or not allOn) then
        recs[#recs + 1] = { key = "nonplayer", tokens = BoolTokens(),
            cand = Cand(false, { isFromPlayerOrPlayerPet = false }), tile = claims.nonplayer }
    end

    -- Tile-hosted catch-all: the first enabled grid tile in catch-all state
    -- (All Debuffs checked, or Has Duration alone -- the duration fold below
    -- narrows it) renders its own broad record. Independent of the base record
    -- on purpose: negating "everything" out of the base would empty it, so
    -- overlap with a broad base is accepted (a deliberate user config, same
    -- doctrine as duplicated boolean claims). BoolTokens negates token
    -- categories rendered or hidden elsewhere so categorized content stays
    -- single-rendered.
    if claimsAll then
        local cf = Cand(false)
        if sub then
            if sub.boss then cf.isBossAura = false end
            if sub.role then cf.isRoleAura = false end
            if sub.priority then cf.isPriorityAura = false end
            if sub.nonplayer then cf.isFromPlayerOrPlayerPet = true end
        end
        recs[#recs + 1] = { key = "all", tokens = BoolTokens(),
            cand = cf, tile = claimsAll }
    end

    -- Dead-corpse catch-all: ONE indicator showing Non-Player Auras drops ALL its
    -- filters while its unit is dead and shows every debuff instead (persist-through-
    -- death NPC debuffs matter for res decisions). Compiled as an extra token-only
    -- record (HARMFUL + hygiene excludes; token-only on purpose -- candidate flags
    -- don't stream on dead units) parked at 0; the apply pass wires the death-edge
    -- swap (park the indicator's normal records, unpark this). Qualifier = first
    -- enabled ICONS tile whose show lane includes nonplayer, else the base grid's
    -- nonplayer checkbox; suppressed entirely when a literal All Debuffs indicator
    -- exists (base Show All or a grid tile's All bit) -- everything already shows.
    do
        local deadTile, deadBlocked
        if allOn then deadBlocked = true end
        local dtiles = ns.DM_ActiveTiles()
        if dtiles then
            for i = 1, #dtiles do
                local t = dtiles[i]
                if t.enabled and (t.type == "icons" or t.type == "square") and t.all == true then
                    deadBlocked = true
                end
                if not deadTile and t.enabled and t.type == "icons" and t.claim and t.claim.nonplayer then
                    deadTile = t
                end
            end
        end
        if not deadBlocked and (deadTile or bv.nonplayer == true) then
            recs[#recs + 1] = { key = "npdead", tokens = { "HARMFUL" },
                cand = { excludeSpellIDs = ex }, deadOnly = true, tile = deadTile }
        end
    end

    -- Tile HIDE lanes: a hosting tile's hide lane folds into every record it
    -- hosts, additive to the base lane (which already rode Cand/sub above).
    -- Token categories negate via tokens, typed dispels via the exclude map,
    -- boolean categories via false-valued candidate booleans -- always
    -- deferring to a record's own positive filter (own-category hides are
    -- UI-locked; the key checks here are the engine-side guard). The cc
    -- record takes NO folds at all (base parity: ccCand bypasses Cand, so the
    -- base hide lane never touches cc content either -- cc owns its overlaps,
    -- and a magic stun must never vanish from both cc and dispel).
    local function HasTok(toks, tok)
        for i = 1, #toks do if toks[i] == tok then return true end end
        return false
    end
    for i = 1, #recs do
        local r = recs[i]
        local tn = r.tile and r.tile.neg
        -- npdead ignores ALL filters by definition: no hide-lane folds, no duration cap.
        if tn and r.key ~= "cc" and r.key ~= "npdead" then
            local toks, cf, key = r.tokens, r.cand, r.key
            if tn.cc == true and not HasTok(toks, "!CROWD_CONTROL") then
                toks[#toks + 1] = "!CROWD_CONTROL"
            end
            if tn.dispel == true and key ~= "dispel" then
                if dispelMode == "typed" then
                    if not cf.includeDispelTypes then cf.excludeDispelTypes = TYPED_DEBUFFS end
                elseif not HasTok(toks, "!RAID_PLAYER_DISPELLABLE") then
                    toks[#toks + 1] = "!RAID_PLAYER_DISPELLABLE"
                end
            end
            if tn.raid == true and key ~= "raid" and not HasTok(toks, "!RAID") then
                toks[#toks + 1] = "!RAID"
            end
            if tn.raidcombat == true and key ~= "raidcombat" and not HasTok(toks, "!RAID_IN_COMBAT") then
                toks[#toks + 1] = "!RAID_IN_COMBAT"
            end
            if tn.boss == true and cf.isBossAura == nil and cf.isBossOrRoleAura == nil then cf.isBossAura = false end
            if tn.role == true and cf.isRoleAura == nil and cf.isBossOrRoleAura == nil then cf.isRoleAura = false end
            if tn.priority == true and cf.isPriorityAura == nil then cf.isPriorityAura = false end
            if tn.nonplayer == true and key ~= "nonplayer" and cf.isFromPlayerOrPlayerPet == nil then
                cf.isFromPlayerOrPlayerPet = true
            end
        end
    end

    -- Has Duration fold: the owner surface's modifier ANDs the native duration
    -- gate onto every record it owns (base records read dm, tile-hosted read
    -- their tile). maxDuration rejects duration == 0 (permanents) and anything
    -- above the cap, so math.huge keeps every timed debuff and drops only
    -- permanents. cc records are exempt like every other fold: the legacy cc
    -- group's candidates are declaration-fixed (no live retake), so the base
    -- cc surfaces could never honor a flip -- crowd control always shows.
    -- Also stamp each record with its owner list's resolved Size (base reads
    -- base blocks, tile-hosted reads its tile's).
    for i = 1, #recs do
        local r = recs[i]
        local owner = r.tile or bv
        if owner.hasDuration == true and r.key ~= "cc" and r.key ~= "npdead" then
            r.cand.maxDuration = math.huge
        end
        r.fxSize = FxSizeFor(r.tile and r.tile.fxList or bv.fxList, r.key)
    end

    return recs, ccCand, claims, Cand, fxCats
end

-- Order-independent fingerprint of a candidate-filter table. Candidate payloads are DECLARATION-FIXED
-- (SetAuraGroupCandidateFilters on a live group does not retake), so a payload change must land in the group key
-- and declare a fresh variant. Number-keyed sets (spell ids) fingerprint as count:sum; string-keyed sets (dispel names) join outright.
local function CandFP(cf)
    if not cf then return "-" end
    local keys = {}
    for k in pairs(cf) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = cf[k]
        if type(v) == "table" then
            local first = next(v)
            if type(first) == "number" then
                local n, sum = 0, 0
                for id in pairs(v) do
                    n = n + 1
                    sum = (sum + id) % 2147483647
                end
                parts[#parts + 1] = k .. "=" .. n .. ":" .. sum
            else
                local names = {}
                for name in pairs(v) do names[#names + 1] = tostring(name) end
                table.sort(names)
                parts[#parts + 1] = k .. "=" .. table.concat(names, "+")
            end
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    return table.concat(parts, ",")
end

-- Group keys embed the normalized filter string AND the candidate fingerprint (both declaration-fixed), so any
-- change to a record's negation set or candidate payload (subtracted boolean categories, typed-dispel exclude, lust
-- exclude set) declares a NEW variant group and parks the old at 0 (add-only engine, leak-free). Boolean records
-- share token sets, so the record-key prefix keeps them distinct.
local function GroupKey(AKL, r)
    -- "|sz" marks a SIZED record (group->style binding fixed at declare, so gaining/losing a Size swaps the
    -- variant); size VALUE excluded on purpose since the sized style key is stable per category and its content
    -- rebuilds on edits, so a slider drag restyles buttons instead of minting an engine batch per step.
    return "dm_" .. r.key .. "|" .. AKL.Filter(unpack(r.tokens))
        .. (r.fxSize and "|sz" or "") .. "|" .. CandFP(r.cand)
end

-- Effect-tile category resolution: one live-settable slot per tile.
local function EffectFilterFor(dm, cat)
    if cat == "cc" then return { "HARMFUL", "CROWD_CONTROL" }, nil, false end
    if cat == "raid" then return { "HARMFUL", "RAID" }, nil, false end
    if cat == "raidcombat" then return { "HARMFUL", "RAID_IN_COMBAT" }, nil, false end
    if cat == "dispel" then
        -- Follows the base dispel flavor: by-you token or typed include map.
        if dm.dispelMode == "typed" then
            return { "HARMFUL" }, { includeDispelTypes = TYPED_DEBUFFS }, false
        end
        return { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }, nil, false
    end
    if cat == "boss" then return { "HARMFUL" }, { isBossAura = true }, true end
    if cat == "role" then return { "HARMFUL" }, { isRoleAura = true }, true end
    if cat == "nonplayer" then return { "HARMFUL" }, { isFromPlayerOrPlayerPet = false }, false end
    -- Catch-all pseudo-category (TileCatchAllOn tiles; the duration modifier folds in via EffectFilterForTile).
    if cat == "all" then return { "HARMFUL" }, nil, false end
    -- "priority" (default)
    return { "HARMFUL" }, { isPriorityAura = true }, true
end

-- Effect-slot resolution with the tile's HIDE lane and Has Duration modifier
-- folded in (same doctrine as record synthesis: tokens for token categories,
-- the typed exclude map for typed dispels, false-valued candidate booleans for
-- the rest, maxDuration for the modifier; a slot's own category defers, and
-- the cc slot takes no folds at all -- cc owns its overlaps, base parity with
-- ccCand bypassing Cand).
local function EffectFilterForTile(dm, t, cat)
    local toks, cf, gated = EffectFilterFor(dm, cat)
    if t and t.hasDuration == true and cat ~= "cc" then
        cf = cf or {}
        if cf.maxDuration == nil then cf.maxDuration = math.huge end
    end
    local tn = t and t.neg
    if tn and cat ~= "cc" then
        if tn.cc == true then toks[#toks + 1] = "!CROWD_CONTROL" end
        if tn.dispel == true and cat ~= "dispel" then
            if dm.dispelMode == "typed" then
                cf = cf or {}
                if not cf.includeDispelTypes then cf.excludeDispelTypes = TYPED_DEBUFFS end
            else
                toks[#toks + 1] = "!RAID_PLAYER_DISPELLABLE"
            end
        end
        if tn.raid == true and cat ~= "raid" then toks[#toks + 1] = "!RAID" end
        if tn.raidcombat == true and cat ~= "raidcombat" then toks[#toks + 1] = "!RAID_IN_COMBAT" end
        if tn.boss == true and cat ~= "boss" then
            cf = cf or {}
            if cf.isBossAura == nil then cf.isBossAura = false end
        end
        if tn.role == true and cat ~= "role" then
            cf = cf or {}
            if cf.isRoleAura == nil then cf.isRoleAura = false end
        end
        if tn.priority == true and cat ~= "priority" then
            cf = cf or {}
            if cf.isPriorityAura == nil then cf.isPriorityAura = false end
        end
        if tn.nonplayer == true and cat ~= "nonplayer" then
            cf = cf or {}
            if cf.isFromPlayerOrPlayerPet == nil then cf.isFromPlayerOrPlayerPet = true end
        end
    end
    return toks, cf, gated
end

-- Effect-tile category set: claimed categories plus the "all" pseudo-category
-- while the tile is in catch-all state (nil when the tile targets nothing).
local function EffectCatSet(t)
    local set
    if t.claim then
        for cat, on in pairs(t.claim) do
            if on then
                set = set or {}
                set[cat] = true
            end
        end
    end
    if TileCatchAllOn(t) then
        set = set or {}
        set.all = true
    end
    return set
end

-------------------------------------------------------------------------------
-- Tile containers (per button, persistent, parked when unused)
-------------------------------------------------------------------------------

-- Per-slot-button refs for the effect appliers (weak keys: engine buttons are pooled frames, never write properties onto them).
local fxRefs = setmetatable({}, { __mode = "k" })

-- Effect visuals: ALL created in the slot's extraInit, the ONLY window where insecure calls on the engine button
-- are legal (elsewhere the engine permanently denies reads/writes and the restyler's pcall swallows the denial
-- silently, so creating in the applier builds nothing, ever). FxApply only parameterizes frames we own. Children
-- hang off the slot button (visibility rides the aura match) and anchor OUTWARD to our clean frames (unit button /
-- health), the dispel-overlay/BmEffectInit precedent. FxHideAll hides every effect visual on one slot button
-- (shared by filter-gated slots and teardown paths).
local function FxHideAll(dd)
    local Glows = EllesmereUI.Glows
    if dd.dmFxGlow then
        if dd.dmFxGlow._euiGlowActive and Glows and Glows.StopGlow then
            Glows.StopGlow(dd.dmFxGlow)
        end
        dd.dmFxGlow:Hide()
    end
    if dd.dmFxHcFrame then dd.dmFxHcFrame:Hide() end
    if dd.dmFxGeoF then dd.dmFxGeoF:Hide() end
end

-- Creation-window builder: one kind-specific visual set per effect slot, parked hidden until the applier arms it.
-- Runs in extraInit inside a CreateFrameBatch: an error here kills the whole slot declaration, hence the pcall-degraded engine binding.
local function FxCreateVisuals(button, dd, kind, hostBtn, health)
    if not dd then return end
    if kind == "glow" then
        local g = CreateFrame("Frame", nil, button)
        g:SetAllPoints(hostBtn)
        g:SetFrameLevel((hostBtn:GetFrameLevel() or 1) + 15)
        g:EnableMouse(false)
        g:Hide()
        dd.dmFxGlow = g
    elseif kind == "healthcolor" then
        -- BM healthcolor parity via an owned wrapper: level-tied WITH (not above) the health frame so the tint
        -- sorts against health's ARTWORK sublevels (above fill=0, below heal absorb/prediction=+1, shields=+3);
        -- anchored to the FILL texture so it covers only the filled portion. Wrapper is ours, so the level tie stays legal.
        local f = CreateFrame("Frame", nil, button)
        local fill = health.GetStatusBarTexture and health:GetStatusBarTexture()
        f:SetAllPoints(fill or health)
        f:SetFrameLevel(health:GetFrameLevel())
        local tex = f:CreateTexture(nil, "ARTWORK", nil, 2)
        tex:SetAllPoints(f)
        f:Hide()
        dd.dmFxHcFrame = f
        dd.dmFxHc = tex
        ns.RF_RegisterBarTint(health, tex, f, "dm")
    elseif kind == "square" then
        local f = CreateFrame("Frame", nil, button)
        f:SetPoint("CENTER", health, "CENTER")
        f:SetSize(10, 10)
        local tex = f:CreateTexture(nil, "ARTWORK", nil, 1)
        tex:SetAllPoints(f)
        f:Hide()
        dd.dmFxGeoF = f
        dd.dmFxSq = tex
    elseif kind == "bar" then
        local sb = CreateFrame("StatusBar", nil, button)
        sb:SetPoint("CENTER", health, "CENTER")
        sb:SetSize(10, 10)
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(1)
        local bg = sb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(sb)
        sb:Hide()
        dd.dmFxGeoF = sb
        dd.dmFxBar = sb
        dd.dmFxBarBg = bg
        -- Engine drives the fill from the aura's duration object; button call legal only HERE.
        local ok = pcall(button.SetDurationBar, button, sb, {})
        if not ok then pcall(button.SetDurationBar, button, sb) end
    end
end

local function FxApplyInner(button, dd, refs, fx)
    if fx.kind == "glow" then
        local Glows = EllesmereUI.Glows
        local host = dd.dmFxGlow
        if not (Glows and host) then return end -- created in extraInit
        host:Show()
        -- Color mode: default = proc gold, class = player class, custom = fx.r/g/b.
        local cr, cg, cb = fx.r or 1, fx.g or 0.78, fx.b or 0.38
        local mode = fx.glowMode or "default"
        if mode == "class" then
            local _, classFile = UnitClass("player")
            local ccc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if ccc then cr, cg, cb = ccc.r, ccc.g, ccc.b end
        elseif mode == "default" then
            cr, cg, cb = 1.0, 0.788, 0.137
        end
        -- Size from the unit frame's REAL rect (refs.host is ours, outside the forbidden subtree, so the read is legal here).
        local gw = refs.host:GetWidth() or 0
        local gh = refs.host:GetHeight() or 0
        if gw < 1 then gw = 24 end
        if gh < 1 then gh = gw end
        -- One style only: the animation-driven pixel march (driver-ticked glows freeze on the forbidden slot subtree; this runs C-side).
        if Glows.StartAnimatedAnts then
            Glows.StartAnimatedAnts(host, fx.glowLines or 8, fx.glowThickness or 2,
                fx.glowSpeed or 4, cr, cg, cb, gw, gh)
        end

    elseif fx.kind == "healthcolor" then
        local f = dd.dmFxHcFrame
        local tex = dd.dmFxHc
        if not (f and tex) then return end -- created in extraInit
        -- Level tie set at creation; NO re-check here -- subtree reads (ours included) are denied outside the creation window and would kill this branch.
        -- The bar itself is OURS and outside that subtree, so the tint can read its
        -- fill texture here and keep the health bar's shading instead of flattening it.
        ns.RF_TintOverBarFill(tex, refs.health, fx.r or 1, fx.g or 0.2, fx.b or 0.2, fx.a or 0.5)
        f:Show()

    elseif fx.kind == "square" then
        local gf = dd.dmFxGeoF
        if not gf then return end -- created in extraInit
        local w = fx.w or 10
        local h = fx.h or 10
        local sig = table.concat({ tostring(w), tostring(h), tostring(fx.corner),
            tostring(fx.offX), tostring(fx.offY) }, ",")
        if dd.dmFxGeo ~= sig then
            -- Geometry rides OUR frame (always-legal calls); the sig cache keeps repeat applies cheap.
            gf:SetSize(w, h)
            gf:ClearAllPoints()
            gf:SetPoint(fx.corner or "CENTER", refs.health, fx.corner or "CENTER",
                fx.offX or 0, fx.offY or 0)
            dd.dmFxGeo = sig
        end
        local tex = dd.dmFxSq
        if tex then tex:SetColorTexture(fx.r or 1, fx.g or 1, fx.b or 1, fx.a or 1) end
        gf:Show()

    elseif fx.kind == "bar" then
        local gf = dd.dmFxGeoF
        if not gf then return end -- created in extraInit
        -- BM_PlaceBar 1:1: width/height are FILL-axis sliders and Full toggles follow the fill axis, swapping
        -- screen edges when vertical. Geometry rides OUR StatusBar; sig cache keeps repeat applies cheap.
        local w = fx.w or 30
        local h = fx.h or 4
        local isVert = fx.orient == "VERTICAL"
        local sig = table.concat({ tostring(w), tostring(h), tostring(fx.corner),
            tostring(fx.offX), tostring(fx.offY), tostring(fx.orient),
            tostring(fx.fullW), tostring(fx.fullH), tostring(fx.lvl) }, ",")
        if dd.dmFxGeo ~= sig then
            local health = refs.health
            gf:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
            gf:ClearAllPoints()
            local fullW, fullH
            if isVert then
                fullW, fullH = fx.fullH, fx.fullW
            else
                fullW, fullH = fx.fullW, fx.fullH
            end
            local pos = fx.corner or "BOTTOM"
            if fullW and fullH then
                gf:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                gf:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            elseif fullW then
                local vEdge = (pos:find("BOTTOM", 1, true) and "BOTTOM")
                    or (pos:find("TOP", 1, true) and "TOP") or ""
                local oy = fx.offY or 0
                gf:SetPoint(vEdge .. "LEFT", health, vEdge .. "LEFT", 0, oy)
                gf:SetPoint(vEdge .. "RIGHT", health, vEdge .. "RIGHT", 0, oy)
                gf:SetHeight(isVert and w or h)
            elseif fullH then
                local hEdge = (pos:find("RIGHT", 1, true) and "RIGHT")
                    or (pos:find("LEFT", 1, true) and "LEFT") or ""
                local ox = fx.offX or 0
                gf:SetPoint("TOP" .. hEdge, health, "TOP" .. hEdge, ox, 0)
                gf:SetPoint("BOTTOM" .. hEdge, health, "BOTTOM" .. hEdge, ox, 0)
                gf:SetWidth(isVert and h or w)
            else
                if isVert then gf:SetSize(h, w) else gf:SetSize(w, h) end
                gf:SetPoint(pos, health, pos, fx.offX or 0, fx.offY or 0)
            end
            -- Frame Level band relative to the unit button (our frame; the read is legal in the creation window).
            gf:SetFrameLevel((refs.host:GetFrameLevel() or 1) + (fx.lvl or 7))
            dd.dmFxGeo = sig
        end
        gf:SetReverseFill(fx.reverseFill or false)
        gf:SetStatusBarColor(fx.r or 0.25, fx.g or 0.8, fx.b or 0.45,
            (fx.colorOp or 100) / 100)
        if dd.dmFxBarBg then
            dd.dmFxBarBg:SetColorTexture(fx.bgR or 0, fx.bgG or 0, fx.bgB or 0,
                (fx.bgOp or 50) / 100)
        end
        gf:Show()
    end
end

local function FxApply(button, dd, style)
    local refs = fxRefs[button]
    local fx = style.fx
    if not (refs and fx) then return end

    -- Per-filter gating: an effect tile declares one slot per EVER-checked category
    -- (add-only engine -- a slot cannot be un-declared), so a slot whose category is
    -- currently UNCHECKED must render nothing. dd.dmCat is stamped at slot creation
    -- and fx.filters is the live checked set, so the two together are the gate. The
    -- catch-all pseudo-slot ("all") gates on the live tile's current catch-all
    -- state instead (never a claim key).
    -- Both paths stay pcall-wrapped: this runs inside the engine's CreateFrameBatch,
    -- where an uncaught error aborts the whole batch and the slot never appears.
    if dd and fx.filters and (fx.filters[dd.dmCat]
        or (dd.dmCat == "all" and fx.tile and TileCatchAllOn(fx.tile))) then
        pcall(FxApplyInner, button, dd, refs, fx)
    else
        pcall(FxHideAll, dd)
    end
end

-- Icon-tile flow anchoring: corner-pinned chain, CENTER growth centers the
-- row on the anchor point's X (based on the defensives-row math, with tile
-- settings and the vertical seat kept flush with the anchored edge).
local function AnchorTileContainer(container, health, s, t)
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, s) or health
    -- Pin shared with the tooltip-modifier eater (TilePin): point = corner for
    -- directional growth, the flush edge midpoint for CENTER growth.
    local point, corner, offX, offY = TilePin(t)
    local grow = t.growDirection or "CENTER"

    AK = AK or EllesmereUI.AuraKit
    -- Grid wrap: Icons Per Row >= 2 wraps lines away from the anchored edge (simple-grid convention, lowercase
    -- position tokens here); vertical growth flips the flow axis so lines become columns. Below 2 =
    -- single run, corner pick untouched.
    local per = tonumber(t.iconsPerRow) or 0
    local pl = t.position or "top"
    local wrapUp = pl:find("bottom", 1, true) ~= nil
    local wrapLeft = pl:find("right", 1, true) ~= nil
    container:ClearAllPoints()
    if grow == "CENTER" then
        -- Center ONLY the growth (horizontal) axis on the position point; the
        -- vertical component sits flush with the anchored edge exactly like
        -- the directional branch below. (A full CENTER pin -- the raw
        -- defensives-row math -- straddled top/bottom edges by half an icon.)
        container:SetPoint(point, health, corner, offX, offY)
        local gV = (per >= 2 and wrapUp) and "UP" or "DOWN"
        AK.SetContainerAnchor(container, (gV == "UP") and "BOTTOMLEFT" or "TOPLEFT")
        AK.SetContainerGrowth(container, FlowDir("RIGHT"), FlowDir(gV))
    else
        container:SetPoint(corner, health, corner, offX, offY)
        local gV = (grow == "UP" or grow == "DOWN") and grow or "DOWN"
        local gH = (grow == "LEFT" or grow == "RIGHT") and grow or "RIGHT"
        if per >= 2 then
            if grow == "UP" or grow == "DOWN" then
                gH = wrapLeft and "LEFT" or "RIGHT"
            else
                gV = wrapUp and "UP" or "DOWN"
            end
            AK.SetContainerAnchor(container,
                ((gV == "UP") and "BOTTOM" or "TOP") .. ((gH == "LEFT") and "RIGHT" or "LEFT"))
        else
            AK.SetContainerAnchor(container, corner)
        end
        AK.SetContainerGrowth(container, FlowDir(gH), FlowDir(gV))
    end

    local size = t.size or 18
    local spacing = t.spacing or 1
    local vertical = (grow == "UP" or grow == "DOWN")
    if per >= 2 then
        AK.SetContainerAxis(container, vertical)
        AK.SetContainerRowWidth(container, per * size + (per - 1) * spacing + 0.4)
    else
        AK.SetContainerAxis(container, false)
        AK.SetContainerRowWidth(container, vertical and (size + 0.4) or nil)
    end
end

-- Per-class tile fingerprints (style/geometry), keyed class .. ":" .. id.
local dmTileFP = {}

-- Ensures one tile's per-class style exists and is current: icon tiles reuse the debuff style at tile size; effect
-- tiles get a bare noRegions style whose applyExtra renders style.fx. szOv/szCat: an Icon Effects Size hosts the
-- sized record on its own STABLE per-category variant (content rebuilds on size edits, group variant swaps only at sized/unsized).
-- Grid-tile style core, shared by EnsureTileStyle and DM_RefreshSizedStyles: tile styles VIEW the base debuff
-- style keys, so a pure base-style edit must re-derive them here too or they render stale (same as sized siblings).
local function RefreshTileGridStyle(key, st, s, t, szOv, font)
    local sv = TileStyleView(s, t)
    local v = ((ns.RFC_DebuffStyleFP and ns.RFC_DebuffStyleFP(sv, font)) or "")
        .. "|" .. tostring(szOv or t.size or 18)
        .. "|" .. FxListFP(t.fxList)
    if t.type == "square" then
        local c = t.color or {}
        v = v .. "|sq" .. string.format("%.2f,%.2f,%.2f,%.2f",
            c.r or 1, c.g or 0.35, c.b or 0.35, c.a or 1)
    end
    if st.style ~= v and ns.RFC_BuildDebuffStyle then
        st.style = v
        local sty = ns.RFC_BuildDebuffStyle(sv, szOv or t.size or 18)
        if t.type == "square" then
            -- Square grid: flat color block over the icon (shared applier).
            sty.squareColor = t.color or { r = 1, g = 0.35, b = 0.35, a = 1 }
        end
        -- Per-tile Effects override the base-injected fx explicitly, including nil: a tile without blocks must not inherit the base.
        sty.fxList = FxListView(t.fxList)
        AK.styles[key] = sty
        AK.RestyleSoon(key)
    end
end

local function EnsureTileStyle(d, s, t, szOv, szCat)
    local cls = ClassToken(d)
    local key
    local isGrid = (t.type == "icons" or t.type == "square")
    if isGrid then
        key = "rf:dmt:" .. cls .. ":" .. tostring(t.id)
        if szOv then key = key .. ":sz:" .. tostring(szCat) end
    else
        key = "rf:dmfx:" .. cls .. ":" .. tostring(t.id)
    end
    local st = dmTileFP[key]
    if not st then st = {}; dmTileFP[key] = st end

    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    local v
    if isGrid then
        -- Rebuild handles for DM_RefreshSizedStyles (base-style edits re-derive this key without an apply pass).
        st.cls, st.tid, st.szOv, st.grid = cls, t.id, szOv, true
        RefreshTileGridStyle(key, st, s, t, szOv, font)
    else
        local c = t.color or {}
        local bgc = t.barBgColor or {}
        local cl = {}
        if t.claim then
            for k2, on in pairs(t.claim) do if on then cl[#cl + 1] = k2 end end
            table.sort(cl)
        end
        v = table.concat({ tostring(t.type), tostring(t.glowType), tostring(t.glowLines),
            tostring(t.glowThickness), tostring(t.glowSpeed), tostring(t.glowColorMode),
            tostring(t.opacity), tostring(t.size),
            tostring(t.width), tostring(t.height), tostring(t.position),
            tostring(t.offsetX), tostring(t.offsetY),
            tostring(t.orientation), tostring(t.reverseFill),
            tostring(t.barFullWidth), tostring(t.barFullHeight),
            tostring(t.barColorOpacity), tostring(t.barBgOpacity),
            tostring(t.frameLevel),
            string.format("%.2f,%.2f,%.2f,%.2f", c.r or 1, c.g or 1, c.b or 1, c.a or 1),
            string.format("%.2f,%.2f,%.2f", bgc.r or 0, bgc.g or 0, bgc.b or 0),
            table.concat(cl, "+"), tostring(t.all), tostring(t.hasDuration),
        }, "|")
        if st.style ~= v then
            st.style = v
            AK.styles[key] = {
                noRegions = true,
                applyExtra = FxApply,
                fx = {
                    kind = t.type,
                    -- Checked-filter set: the applier's per-slot gate (live table reference; the FP above rebuilds on changes).
                    filters = t.claim or {},
                    -- Live tile reference: the catch-all pseudo-slot's gate (see FxApply).
                    tile = t,
                    glowType = t.glowType or 1, glowLines = t.glowLines,
                    glowThickness = t.glowThickness, glowSpeed = t.glowSpeed,
                    glowMode = t.glowColorMode,
                    size = t.size,
                    w = t.width or 10, h = t.height or 10,
                    corner = CORNERS[t.position or "center"] or "CENTER",
                    offX = t.offsetX, offY = t.offsetY,
                    orient = t.orientation, reverseFill = t.reverseFill,
                    fullW = t.barFullWidth, fullH = t.barFullHeight,
                    colorOp = t.barColorOpacity, bgOp = t.barBgOpacity,
                    bgR = bgc.r, bgG = bgc.g, bgB = bgc.b,
                    lvl = BAR_FRAMELVL[t.frameLevel or "behindBorders"],
                    r = c.r, g = c.g, b = c.b,
                    -- Health color rides a dedicated Opacity setting (the swatch has no alpha strip there, matching BM).
                    a = (t.type == "healthcolor")
                        and ((t.opacity or 45) / 100) or c.a,
                },
            }
            AK.RestyleSoon(key)
        end
    end
    return key
end

-- Sized BASE-record styles: an Icon Effects block with a Size renders its categories at that size. Buttons take
-- physical size from the style at creation, so each sized category gets its own STABLE style key: content rebuilds
-- on size/base-style changes, group variant swaps only at the sized/unsized edge (GroupKey "|sz"). "cc" builds the
-- CC-glow flavor so sized crowd control keeps its glow; registry entries let the containers file refresh these on its own rebuilds (DM_RefreshSizedStyles).
local dmSizeFP = {}
local function EnsureBaseSizeStyle(d, s, cat, size)
    local cls = ClassToken(d)
    local key = "rf:dmsz:" .. cls .. ":" .. tostring(cat)
    local st = dmSizeFP[key]
    if not st then st = { cls = cls, cat = cat }; dmSizeFP[key] = st end
    st.size = size
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    local v = ((ns.RFC_DebuffStyleFP and ns.RFC_DebuffStyleFP(s, font)) or "")
        .. "|" .. tostring(size)
    if st.style ~= v and ns.RFC_BuildDebuffStyle then
        st.style = v
        local sty
        if cat == "cc" and ns.RFC_BuildDebuffCCStyle then
            sty = ns.RFC_BuildDebuffCCStyle(s, size)
        else
            sty = ns.RFC_BuildDebuffStyle(s, size)
        end
        AK.styles[key] = sty
        AK.RestyleSoon(key)
    end
    return key
end

-- Called by the containers file when it rebuilds a class's base debuff styles on a style-fingerprint change: a pure
-- style edit (border color, font) does not flip the config fingerprint (so the apply pass/EnsureBaseSizeStyle may not run) -- sized siblings must refresh here or render stale.
function ns.DM_RefreshSizedStyles(baseStyleKey, s)
    AK = AK or EllesmereUI.AuraKit
    if not AK then return end
    local cls = baseStyleKey:match("^rf:debuff:(.+)$")
    if not cls then return end
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    for key, st in pairs(dmSizeFP) do
        if st.cls == cls and st.style and st.size then
            local v = ((ns.RFC_DebuffStyleFP and ns.RFC_DebuffStyleFP(s, font)) or "")
                .. "|" .. tostring(st.size)
            if st.style ~= v and ns.RFC_BuildDebuffStyle then
                st.style = v
                local sty
                if st.cat == "cc" and ns.RFC_BuildDebuffCCStyle then
                    sty = ns.RFC_BuildDebuffCCStyle(s, st.size)
                else
                    sty = ns.RFC_BuildDebuffStyle(s, st.size)
                end
                AK.styles[key] = sty
                AK.RestyleSoon(key)
            end
        end
    end
    -- Grid tiles view the same base style keys; refresh them on this edge too.
    local act = ns.DM_ActiveTiles and ns.DM_ActiveTiles()
    if act then
        local byId = {}
        for i = 1, #act do byId[act[i].id] = act[i] end
        for key, st in pairs(dmTileFP) do
            if st.grid and st.cls == cls then
                local t = byId[st.tid]
                if t then RefreshTileGridStyle(key, st, s, t, st.szOv, font) end
            end
        end
    end
end

-- Ensures one tile's container exists for this button (queued: container shells are combat-illegal). Effect tiles
-- declare their single slot at build; icon tiles get record groups from the apply pass (combat-legal adds on existing containers).
local function EnsureTileContainer(d, t)
    local tiles = d.dmTiles
    if not tiles then tiles = {}; d.dmTiles = tiles end
    if tiles[t.id] then return tiles[t.id] end
    local pend = d.dmTilePend
    if not pend then pend = {}; d.dmTilePend = pend end
    if pend[t.id] then return nil end
    pend[t.id] = true
    local tileId = t.id
    AK.QueueBuildJob(function()
        d.dmTilePend[tileId] = nil
        if d.dmTiles[tileId] then return end
        if not ns.DM_Active() then return end
        local button = d.dmHost
        local health = d.rfcHealth
        local unit = d.rfcUnit
        if not (button and health) then return end
        -- Re-resolve from the ACTIVE union: a tile that left it between
        -- queue and run (delete, spec swap, per-spec disable) builds nothing.
        local act = ns.DM_ActiveTiles()
        local t2
        if act then
            for i = 1, #act do
                if act[i].id == tileId then t2 = act[i] break end
            end
        end
        if not t2 then return end
        local s2 = SettingsFor(d)
        if not s2 then return end
        -- EffectFilterFor below reads dm (dispelMode); the active-union
        -- re-resolve above no longer carries it.
        local dm2 = DM() or {}
        local styleKey = EnsureTileStyle(d, s2, t2)
        local container = AK.CreateContainerShell(button, {
            point = { "CENTER", health, "CENTER" },
        })
        -- Level bands: grid and bar tiles render in the aura band (button + LVL_AURA = 13, above borders/text like
        -- legacy aura icons). Healthcolor slots re-tie to the health frame in the applier and glow hosts level
        -- themselves (+15), so this is only a pre-apply default (container defaults are far lower, which would put tile icons under borders/text).
        if t2.type == "healthcolor" then
            container:SetFrameLevel(button:GetFrameLevel() + 6)
        else
            container:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA or 13))
        end
        if t2.type ~= "icons" and t2.type ~= "square" then
            -- One slot PER checked filter category; later checks add slots on the live lane, gate silences unchecked ones.
            local host = button
            local hp = health
            local tGroups = d.dmTileGroups
            if not tGroups then tGroups = {}; d.dmTileGroups = tGroups end
            local tDecl = tGroups[tileId]
            if not tDecl then tDecl = {}; tGroups[tileId] = tDecl end
            local tileKind = t2.type
            local cs = EffectCatSet(t2)
            if cs then
                for cat in pairs(cs) do
                    local catKey = cat
                    local filter, cand = EffectFilterForTile(dm2, t2, catKey)
                    AK.AddSlotToContainer(container, {
                        key = "fx_" .. catKey,
                        filter = filter,
                        candidateFilters = cand,
                        style = styleKey,
                        extraInit = function(slotButton, d2, style)
                            -- Stamp category (applier filter gate) + refs (weak map, NEVER frame properties) +
                            -- create/arm visuals: the only window subtree calls are legal (earlier applyExtra call with refs nil bailed).
                            if d2 then d2.dmCat = catKey end
                            fxRefs[slotButton] = { host = host, health = hp }
                            slotButton:SetPoint("CENTER", hp, "CENTER")
                            slotButton:SetMouseMotionEnabled(false)
                            FxCreateVisuals(slotButton, d2, tileKind, host, hp)
                            if style then FxApply(slotButton, d2, style) end
                        end,
                    })
                    tDecl["fx_" .. catKey] = AK.Filter(unpack(filter))
                end
            end
        end
        AK.FinishContainer(container, unit or "none")
        container._dmUnit = unit
        d.dmTiles[tileId] = container
        -- Re-drive this button's config so the fresh container gets its groups/counts/anchor (per-button, cheap).
        local c2 = d.rfcDebuffs
        if c2 then
            ns.DM_ApplyDebuffConfig(c2, d, s2, StyleKeyFor(d))
        end
    end, "rf:dm-tile")
    return nil
end

-------------------------------------------------------------------------------
-- The apply pass (owns the whole debuff-container config while active)
-------------------------------------------------------------------------------
function ns.DM_ApplyDebuffConfig(container, d, s, styleKey)
    AK = AK or EllesmereUI.AuraKit
    -- Default-ON: no dmDebuff table yet = the defaults (Show All + cc on).
    local dm = DM() or {}
    local declared = d.rfcDebuffGroups
    if not (AK and declared) then return end

    local cap = s.debuffCap or 3
    local size = s.debuffSize or 18
    local layout = {
        elementWidth = size, elementHeight = size,
        elementSpacing = s.debuffSpacing or 1, lineSpacing = s.debuffSpacing or 1,
    }
    -- Tooltip-modifier eaters: every footprint sum, stash and ensure below
    -- is gated on the feature being wanted, so the plain apply pays nothing.
    local tipOn = ns.DM_TipModWanted and ns.DM_TipModWanted() or false

    local recs, ccCand, claims, _, fxCats = BuildRecords(s, dm)

    -- Dead-corpse swap state rebuilds fresh every apply; a config that lost its
    -- npdead record sheds the swap here (the stale variant parks below).
    d.dmDeadSwap = nil
    local deadRec, ccParkCount

    -- Partition records: base container vs per-tile containers.
    local wantedBase, missingBase = {}, false
    local baseSizedCC = false -- sized cc record replaces the legacy cc group
    local tileRecs = {} -- [tileId] = array of records
    for i = 1, #recs do
        local r = recs[i]
        r.gkey = GroupKey(AK, r)
        if r.deadOnly then deadRec = r end
        if r.tile then
            local id = r.tile.id
            local list = tileRecs[id]
            if not list then list = {}; tileRecs[id] = list end
            list[#list + 1] = r
        else
            if r.key == "cc" then baseSizedCC = true end
            wantedBase[r.gkey] = r
            if not declared[r.gkey] then missingBase = true end
        end
    end

    -- Park everything the base does not want (legacy preset groups, stale record variants); setters are dirty marks, runs only on an FP change.
    for k in pairs(declared) do
        if k ~= "cc" and not wantedBase[k] then
            container:SetAuraGroupMaxFrameCount(k, 0)
        end
    end

    -- Crowd Control rides the existing cc group (CC glow intact) while enabled and UNCLAIMED; a claiming tile
    -- hosts it as a normal record instead (tile style, glow stays base-only).
    if declared.cc then
        -- A sized base cc record supplants the legacy group: park it or CC debuffs render twice. Under Show All
        -- the cc lead/glow group is on unless Crowd Control rides the hide lane (dm.neg.cc = subtracted); in add
        -- mode it is on exactly when the show lane checks it; fx routing forces it either way. Has Duration never
        -- flips this: cc surfaces are exempt from the duration fold (declaration-fixed candidates).
        local bv = BaseView(dm)
        local allOn = bv.all ~= false
        local ccHidden = bv.neg ~= nil and bv.neg.cc == true
        local ccPicked = (allOn and not ccHidden) or (not allOn and bv.cc == true)
        local ccBase = (ccPicked or (fxCats and fxCats.cc)) and not claims.cc
            and not baseSizedCC
        ccParkCount = ccBase and cap or 0
        container:SetAuraGroupMaxFrameCount("cc", ccParkCount)
        container:SetAuraGroupCandidateFilters("cc", ccCand)
        container:SetAuraGroupLayout("cc", layout)
    end

    local assist = d.rfcAssist ~= false
    local gatedKeys

    -- Tooltip-eater footprint inputs (Shown on Modifier): the base row's
    -- maximum icon count = cap per DECLARED group, cc included, regardless of
    -- gating or death parking (both flip live without a re-apply), and the
    -- largest cell (sized records).
    local tipN, tipCell = (declared.cc and cap) or 0, size

    -- Base records.
    for gkey, r in pairs(wantedBase) do
        if declared[gkey] then
            if tipOn then
                tipN = tipN + cap
                if r.fxSize and r.fxSize > tipCell then tipCell = r.fxSize end
            end
            local n = cap
            if r.gated then
                gatedKeys = gatedKeys or {}
                gatedKeys[#gatedKeys + 1] = gkey
                if not assist then n = 0 end
            end
            if r.deadOnly then n = 0 end -- parked until the death edge unparks it
            container:SetAuraGroupMaxFrameCount(gkey, n)
            container:SetAuraGroupCandidateFilters(gkey, r.cand)
            if r.fxSize then
                -- Sized record: keep the stable per-category style fresh (size edits restyle existing buttons) + same size in the flow math.
                EnsureBaseSizeStyle(d, s, r.key, r.fxSize)
                container:SetAuraGroupLayout(gkey, {
                    elementWidth = r.fxSize, elementHeight = r.fxSize,
                    elementSpacing = s.debuffSpacing or 1,
                    lineSpacing = s.debuffSpacing or 1,
                })
            else
                container:SetAuraGroupLayout(gkey, layout)
            end
        end
    end
    d.dmGatedKeys = gatedKeys
    d.dmCap = cap
    if tipOn then
        local geo = d.dmTipGeo
        if not geo then geo = { tiles = {} }; d.dmTipGeo = geo end
        local gb = geo.base
        if not gb then gb = {}; geo.base = gb end
        gb.n, gb.cell = tipN, tipCell
    end

    -- Base-hosted dead swap: park set = every normal base record (legacy cc group
    -- included) with its restore count; the death edge zeroes them and unparks npdead.
    if deadRec and not deadRec.tile and declared[deadRec.gkey] then
        local park = {}
        for gkey, r in pairs(wantedBase) do
            if declared[gkey] and not r.deadOnly then
                park[gkey] = (r.gated and not assist) and 0 or cap
            end
        end
        if declared.cc then park.cc = ccParkCount end
        d.dmDeadSwap = { show = deadRec.gkey, cap = cap, park = park }
    end

    -- Missing base record variants: declare on the combat-legal live lane, then re-apply (mirrors the containers file's preset-ensure pattern).
    if missingBase and not d.dmEnsure then
        d.dmEnsure = true
        AK.QueueLiveBuildJob(function()
            d.dmEnsure = nil
            local c2 = d.rfcDebuffs
            local declared2 = d.rfcDebuffGroups
            if not (c2 and declared2 and ns.DM_Active()) then return end
            local s2 = SettingsFor(d)
            local dm2 = DM() or {}
            if not s2 then return end
            local recs2 = BuildRecords(s2, dm2)
            for i = 1, #recs2 do
                local r = recs2[i]
                if not r.tile then
                    local gkey = GroupKey(AK, r)
                    if not declared2[gkey] then
                        -- Stamp category (per-filter EFFECTS match on it) and arm ICON EFFECTS in the creation
                        -- window (style applier ran before this stamp and found none).
                        local catKey = r.key
                        -- Sized records bind their per-category sized style (buttons take physical size at creation).
                        local sk = r.fxSize
                            and EnsureBaseSizeStyle(d, s2, r.key, r.fxSize)
                            or StyleKeyFor(d)
                        AK.AddGroupToContainer(c2, { key = gkey, filter = r.tokens,
                            maxFrameCount = 0, style = sk,
                            extraInit = function(btn2, d2, style)
                                if d2 then d2.dmCat = catKey end
                                if style and ns.RFC_ApplyDmFx then
                                    ns.RFC_ApplyDmFx(btn2, d2, style)
                                end
                            end })
                        declared2[gkey] = true
                    end
                end
            end
            ns.DM_ApplyDebuffConfig(c2, d, s2, StyleKeyFor(d))
        end, "rf:dm-ensure")
    end

    -- Tiles. Stash the host ref the deferred tile builds need (the base debuff container is parented to the unit button on every build path).
    d.dmHost = d.dmHost or (container.GetParent and container:GetParent())
    -- The ACTIVE union: tiles from buckets the current spec doesn't render
    -- (spec swaps, per-spec disables) fall out of `present` below and park
    -- their containers exactly like a deleted tile.
    local dmTiles = ns.DM_ActiveTiles()
    local live = d.dmTiles
    local gatedTiles
    if dmTiles then
        for i = 1, #dmTiles do
            local t = dmTiles[i]
            local recsFor = tileRecs[t.id]
            local isEffect = t.type ~= "icons" and t.type ~= "square"
            local active = t.enabled and (isEffect or (recsFor and #recsFor > 0))
            if active then
                local tc = EnsureTileContainer(d, t)
                if tc then
                    local tStyleKey = EnsureTileStyle(d, s, t)
                    local tGroups = d.dmTileGroups
                    if not tGroups then tGroups = {}; d.dmTileGroups = tGroups end
                    local tDecl = tGroups[t.id]
                    if not tDecl then tDecl = {}; tGroups[t.id] = tDecl end
                    local gatedContent = false

                    if isEffect then
                        -- One live-settable slot PER CHECKED category: filter setter takes the NORMALIZED string,
                        -- candidates an explicit empty table (NEVER nil -- NP field lesson); newly-checked categories without a slot add on the combat-legal live lane below.
                        local missingCats = false
                        local cs = EffectCatSet(t)
                        if cs then
                            for cat in pairs(cs) do
                                local skey = "fx_" .. cat
                                local filter, cand, catGated = EffectFilterForTile(dm, t, cat)
                                if tDecl[skey] then
                                    local fsig = AK.Filter(unpack(filter))
                                    if tDecl[skey] ~= fsig then
                                        tc:SetAuraSlotFilterString(skey, fsig)
                                        tDecl[skey] = fsig
                                    end
                                    tc:SetAuraSlotCandidateFilters(skey, cand or {})
                                else
                                    missingCats = true
                                end
                                if catGated then gatedContent = true end
                            end
                        end
                        if missingCats then
                            local pendKey = "fx" .. tostring(t.id)
                            local pend = d.dmTilePend
                            if not pend then pend = {}; d.dmTilePend = pend end
                            if not pend[pendKey] then
                                pend[pendKey] = true
                                local tileId = t.id
                                AK.QueueLiveBuildJob(function()
                                    d.dmTilePend[pendKey] = nil
                                    local tc2 = d.dmTiles and d.dmTiles[tileId]
                                    local decl2 = d.dmTileGroups and d.dmTileGroups[tileId]
                                    if not (tc2 and decl2 and ns.DM_Active()) then return end
                                    local s2 = SettingsFor(d)
                                    local dm2 = DM() or {}
                                    if not s2 then return end
                                    -- Active-union re-resolve (delete/spec
                                    -- swap/per-spec disable between queue and
                                    -- run = skip).
                                    local act = ns.DM_ActiveTiles()
                                    local t2
                                    if act then
                                        for ti2 = 1, #act do
                                            if act[ti2].id == tileId then t2 = act[ti2] break end
                                        end
                                    end
                                    local host = d.dmHost
                                    local hp = d.rfcHealth
                                    if not (t2 and host and hp) then return end
                                    local styleKey2 = EnsureTileStyle(d, s2, t2)
                                    local tileKind = t2.type
                                    local cs2 = EffectCatSet(t2)
                                    for cat in pairs(cs2 or {}) do
                                        local skey = "fx_" .. cat
                                        if not decl2[skey] then
                                            local catKey = cat
                                            local filter, cand = EffectFilterForTile(dm2, t2, catKey)
                                            AK.AddSlotToContainer(tc2, {
                                                key = skey,
                                                filter = filter,
                                                candidateFilters = cand,
                                                style = styleKey2,
                                                extraInit = function(slotButton, d2, style)
                                                    if d2 then d2.dmCat = catKey end
                                                    fxRefs[slotButton] = { host = host, health = hp }
                                                    slotButton:SetPoint("CENTER", hp, "CENTER")
                                                    slotButton:SetMouseMotionEnabled(false)
                                                    FxCreateVisuals(slotButton, d2, tileKind, host, hp)
                                                    if style then FxApply(slotButton, d2, style) end
                                                end,
                                            })
                                            decl2[skey] = AK.Filter(unpack(filter))
                                        end
                                    end
                                    local c2 = d.rfcDebuffs
                                    if c2 then ns.DM_ApplyDebuffConfig(c2, d, s2, StyleKeyFor(d)) end
                                end, "rf:dm-fx-slots")
                            end
                        end
                    else
                        -- Record groups on the tile container (variant keys, additive declares, park stale variants).
                        local tWanted = {}
                        local tMissing = false
                        for ri = 1, #recsFor do
                            local r = recsFor[ri]
                            tWanted[r.gkey] = r
                            if not tDecl[r.gkey] then tMissing = true end
                        end
                        for k in pairs(tDecl) do
                            if tWanted[k] == nil and k ~= "fxFilter" then
                                tc:SetAuraGroupMaxFrameCount(k, 0)
                            end
                        end
                        local tCap = t.cap or cap
                        local tSize = t.size or 18
                        local tLayout = {
                            elementWidth = tSize, elementHeight = tSize,
                            elementSpacing = t.spacing or 1, lineSpacing = t.spacing or 1,
                        }
                        -- Tooltip-eater footprint inputs for this tile (see the base site).
                        local tN, tCell = 0, tSize
                        for gkey, r in pairs(tWanted) do
                            if tDecl[gkey] then
                                if tipOn then
                                    tN = tN + tCap
                                    if r.fxSize and r.fxSize > tCell then tCell = r.fxSize end
                                end
                                local n = tCap
                                if r.gated then
                                    gatedContent = true
                                    if not assist then n = 0 end
                                end
                                if r.deadOnly then n = 0 end -- parked until the death edge unparks it
                                tc:SetAuraGroupMaxFrameCount(gkey, n)
                                tc:SetAuraGroupCandidateFilters(gkey, r.cand)
                                if r.fxSize then
                                    -- Sized record: per-category tile style variant fresh + matching flow math.
                                    EnsureTileStyle(d, s, t, r.fxSize, r.key)
                                    tc:SetAuraGroupLayout(gkey, {
                                        elementWidth = r.fxSize, elementHeight = r.fxSize,
                                        elementSpacing = t.spacing or 1,
                                        lineSpacing = t.spacing or 1,
                                    })
                                else
                                    tc:SetAuraGroupLayout(gkey, tLayout)
                                end
                            end
                        end
                        if tipOn then
                            local geo = d.dmTipGeo
                            if not geo then geo = { tiles = {} }; d.dmTipGeo = geo end
                            local gt = geo.tiles[t.id]
                            if not gt then gt = {}; geo.tiles[t.id] = gt end
                            gt.n, gt.cell = tN, tCell
                        end
                        if tMissing then
                            -- Combat-legal group adds on the existing tile container; keyed ensure per tile.
                            local pendKey = "g" .. tostring(t.id)
                            local pend = d.dmTilePend
                            if not pend then pend = {}; d.dmTilePend = pend end
                            if not pend[pendKey] then
                                pend[pendKey] = true
                                local tileId = t.id
                                AK.QueueLiveBuildJob(function()
                                    d.dmTilePend[pendKey] = nil
                                    local tc2 = d.dmTiles and d.dmTiles[tileId]
                                    local decl2 = d.dmTileGroups and d.dmTileGroups[tileId]
                                    if not (tc2 and decl2 and ns.DM_Active()) then return end
                                    local s2 = SettingsFor(d)
                                    local dm2 = DM() or {}
                                    if not s2 then return end
                                    local recs2 = BuildRecords(s2, dm2)
                                    for ri = 1, #recs2 do
                                        local r = recs2[ri]
                                        if r.tile and r.tile.id == tileId then
                                            local gkey = GroupKey(AK, r)
                                            if not decl2[gkey] then
                                                local catKey = r.key
                                                AK.AddGroupToContainer(tc2, {
                                                    key = gkey, filter = r.tokens,
                                                    maxFrameCount = 0,
                                                    -- Sized records bind the per-category sized tile-style variant.
                                                    style = r.fxSize
                                                        and EnsureTileStyle(d, s2, r.tile, r.fxSize, r.key)
                                                        or EnsureTileStyle(d, s2, r.tile),
                                                    extraInit = function(btn2, d2, style)
                                                        if d2 then d2.dmCat = catKey end
                                                        -- Arm ICON EFFECTS in the creation window (see the base-record site).
                                                        if style and ns.RFC_ApplyDmFx then
                                                            ns.RFC_ApplyDmFx(btn2, d2, style)
                                                        end
                                                    end })
                                                decl2[gkey] = true
                                            end
                                        end
                                    end
                                    local c2 = d.rfcDebuffs
                                    if c2 then ns.DM_ApplyDebuffConfig(c2, d, s2, StyleKeyFor(d)) end
                                end, "rf:dm-tile-groups")
                            end
                        end
                        -- Tile-hosted dead swap: park set = the tile's normal records with restore counts.
                        if deadRec and deadRec.tile == t and tDecl[deadRec.gkey] then
                            local park = {}
                            for gkey, r in pairs(tWanted) do
                                if tDecl[gkey] and not r.deadOnly then
                                    park[gkey] = (r.gated and not assist) and 0 or tCap
                                end
                            end
                            d.dmDeadSwap = { show = deadRec.gkey, cap = tCap, park = park, tileId = t.id }
                        end
                        AnchorTileContainer(tc, d.rfcHealth, s, t)
                    end

                    if gatedContent then
                        gatedTiles = gatedTiles or {}
                        gatedTiles[#gatedTiles + 1] = t.id
                        tc:SetShown(assist)
                    else
                        tc:Show()
                    end
                    -- Same-unit re-sets are a full engine re-registration (the RF roster-reprocess storm lesson), so stamp on our own container frame and re-point on change.
                    if d.rfcUnit and tc._dmUnit ~= d.rfcUnit then
                        tc:SetUnit(d.rfcUnit)
                        tc:UpdateAllAuras()
                        tc._dmUnit = d.rfcUnit
                    end
                end
            elseif live and live[t.id] then
                live[t.id]:Hide()
            end
        end
    end
    -- Stale containers from deleted tiles (or another profile) park hidden.
    if live then
        local present = {}
        if dmTiles then
            for i = 1, #dmTiles do present[dmTiles[i].id] = true end
        end
        local stale = false
        for id, c in pairs(live) do
            if not present[id] then c:Hide(); stale = true end
        end
        -- A parked container keeps its slot buttons, so any healthcolor overlay it
        -- built stays registered on the health bar and every later layout pass
        -- walks it. Nothing releases these, so without this they accumulate for
        -- the session. Live tiles re-register on their next paint.
        if stale and d.rfcHealth then ns.RF_ClearBarTints(d.rfcHealth, "dm") end
    end
    d.dmGatedTiles = gatedTiles

    -- Sync the dead swap to the unit's actual state: the count loops above wrote
    -- alive-shape counts, so a corpse existing at apply time (config change while
    -- someone is dead) must swap now -- no later event is guaranteed on a corpse.
    d.dmDead = nil
    if d.dmDeadSwap and d.rfcUnit then ns.DM_DeadEdge(d, d.rfcUnit) end

    -- Tooltip-modifier eaters: footprint inputs above are fresh, and tile
    -- containers built on the deferred lanes re-enter through this apply.
    -- Off: nothing runs here (the containers reload's ensure parks on a flip).
    if tipOn and ns.DM_TipModEnsure and d.dmHost then ns.DM_TipModEnsure(d.dmHost, d, s) end
end

-- Death-edge hook (from the UNIT_HEALTH repaint path, unit assignment, and the
-- apply tail). Change-gated on d.dmDead; d.dmDeadSwap is nil for every button
-- unless a config qualifies, so the hot-path cost is one field read. Count flips
-- re-render engine-side without an UpdateAllAuras (the assist gate's proven channel).
function ns.DM_DeadEdge(d, unit)
    local swap = d.dmDeadSwap
    if not swap or not unit then return end
    local dead = UnitIsDeadOrGhost(unit) and true or false
    if d.dmDead == dead then return end
    d.dmDead = dead
    local c = swap.tileId and (d.dmTiles and d.dmTiles[swap.tileId]) or d.rfcDebuffs
    if not c then return end
    if dead then
        for k in pairs(swap.park) do c:SetAuraGroupMaxFrameCount(k, 0) end
        c:SetAuraGroupMaxFrameCount(swap.show, swap.cap)
    else
        for k, n in pairs(swap.park) do c:SetAuraGroupMaxFrameCount(k, n) end
        c:SetAuraGroupMaxFrameCount(swap.show, 0)
    end
end

-- Legacy-config tail hook: while INACTIVE the legacy ApplyDebuffConfig drives only its own preset groups, so a
-- just-disabled manager's record variants and tile containers would otherwise keep rendering.
function ns.DM_ParkGroups(container, declared, d)
    for k in pairs(declared) do
        if k:sub(1, 3) == "dm_" then
            container:SetAuraGroupMaxFrameCount(k, 0)
        end
    end
    if d and d.dmTiles then
        for _, c in pairs(d.dmTiles) do c:Hide() end
    end
end

-- Unit re-assignment hook (from RFC_OnUnitAssigned's unit-change branch): tile containers must re-point like every
-- per-button container; the engine does not re-parse on unit change alone.
function ns.DM_OnUnitAssigned(d, unit)
    -- New unit, unknown dead state: force the dead swap to re-evaluate.
    if d.dmDeadSwap then
        d.dmDead = nil
        ns.DM_DeadEdge(d, unit)
    end
    local tiles = d.dmTiles
    if not tiles then return end
    for _, c in pairs(tiles) do
        if c._dmUnit ~= unit then
            c:SetUnit(unit)
            c:UpdateAllAuras()
            c._dmUnit = unit
        end
    end
end

-- Assist-state hook (from ApplyAssistGate on real state changes): identity-gated records and tiles flip; everything
-- else is assist-blind, like the token-only legacy debuff row.
function ns.DM_OnAssistChanged(d)
    if not ns.DM_Active() then return end
    local assist = d.rfcAssist ~= false
    local keys = d.dmGatedKeys
    local container = d.rfcDebuffs
    if keys and container then
        local n = assist and (d.dmCap or 3) or 0
        -- Base-hosted dead swap: while the unit is dead its parked records must stay
        -- at 0, but their restore counts track the assist state for the revive flip.
        local swap = d.dmDeadSwap
        local swapBase = swap and not swap.tileId and swap.park or nil
        for i = 1, #keys do
            local k = keys[i]
            if swapBase and swapBase[k] then
                swapBase[k] = n
                if not d.dmDead then container:SetAuraGroupMaxFrameCount(k, n) end
            else
                container:SetAuraGroupMaxFrameCount(k, n)
            end
        end
    end
    local tiles = d.dmGatedTiles
    if tiles and d.dmTiles then
        for i = 1, #tiles do
            local c = d.dmTiles[tiles[i]]
            if c then c:SetShown(assist) end
        end
    end
end

-------------------------------------------------------------------------------
-- Tile list editing API (consumed by the options page)
-------------------------------------------------------------------------------
-- Read-heals shared by every bucket: expand the old single-cat + width/
-- height square shape, effect single-cat, fx single-config and healthcolor
-- alpha once. Legacy shapes only ever existed in the all-specs array, but
-- healing everywhere is idempotent and keeps one path.
local function HealTiles(arr)
    for i = 1, #arr do
        local t = arr[i]
        if t.type == "square" and not t.claim then
            t.claim = {}
            if t.cat then t.claim[t.cat] = true; t.cat = nil end
            local sz = t.width or t.height
            if sz and sz > 0 then t.size = sz end
            t.width, t.height = nil, nil
            t.growDirection = t.growDirection or "CENTER"
            t.spacing = t.spacing or 1
            t.cap = t.cap or 3
        end
        -- Effect tiles moved from a single t.cat to the filter set; expand once.
        if (t.type == "glow" or t.type == "healthcolor" or t.type == "bar")
            and not t.claim then
            t.claim = {}
            if t.cat then t.claim[t.cat] = true; t.cat = nil end
        end
        -- Effects single-config -> block list (one-time).
        FxHeal(t)
        -- Health color: stored swatch alpha -> the Opacity setting (one-time).
        if t.type == "healthcolor" and t.opacity == nil and t.color and t.color.a then
            t.opacity = math.floor((t.color.a * 100) + 0.5)
        end
    end
end

-- The ALL-SPECS bucket: the legacy dm.tiles array, IN PLACE (zero
-- migration; profiles opened by older builds keep rendering it).
function ns.DM_Tiles()
    local dm = DM()
    if not dm then return nil end
    if not dm.tiles then dm.tiles = {} end
    HealTiles(dm.tiles)
    return dm.tiles
end

-------------------------------------------------------------------------------
-- Editing-spec buckets. dm.tiles IS "allspecs"; every other bucket lives
-- under dm.specTiles[key] = { tiles, inhDis, baseOff }, key = "nonhealer"/"tanks"/
-- "dps"/"healers" (group buckets) or "spec<ID>" (a concrete spec -- healer
-- specs included; the Debuff Manager has no healer-key legacy). Tile ids
-- stay globally unique across buckets (one shared dm.nextTileId), so
-- per-spec disables key on the bare tile id. Absent specTiles = feature
-- unused = the active union degenerates to the legacy array.
-------------------------------------------------------------------------------
local function SpecBucket(dm, key, create)
    local st = dm.specTiles
    if not st then
        if not create then return nil end
        st = {}; dm.specTiles = st
    end
    local b = st[key]
    if not b then
        if not create then return nil end
        b = { tiles = {}, inhDis = {} }
        st[key] = b
    end
    if not b.tiles then b.tiles = {} end
    if not b.inhDis then b.inhDis = {} end
    return b
end

-- Bucket tile array for an EDITED view ("allspecs"/nil = the legacy array).
function ns.DM_BucketTiles(key, create)
    if not key or key == "allspecs" then return ns.DM_Tiles() end
    local dm = DM()
    if not dm then return nil end
    local b = SpecBucket(dm, key, create)
    if not b then return nil end
    HealTiles(b.tiles)
    return b.tiles
end

-- Per-spec disable of a GROUP bucket's tile, stored on the viewing spec's
-- concrete "spec<ID>" bucket (ids are global, so the bare id suffices).
function ns.DM_InhDisabled(concreteKey, id)
    local dm = DM()
    local b = dm and SpecBucket(dm, concreteKey, false)
    return (b and b.inhDis[id]) and true or false
end

function ns.DM_SetInhDisabled(concreteKey, id, disabled)
    local dm = DM()
    if not (dm and concreteKey and id) then return end
    local b = SpecBucket(dm, concreteKey, true)
    b.inhDis[id] = disabled and true or nil
end

-- Per-spec disable of the Base Icons grid (the All Specs base, inherited by
-- every concrete spec like an All Specs tile): b.baseOff on the viewing
-- spec's bucket, beside the tile disables.
function ns.DM_BaseDisabled(concreteKey)
    local dm = DM()
    local b = dm and SpecBucket(dm, concreteKey, false)
    return (b and b.baseOff) and true or false
end

function ns.DM_SetBaseDisabled(concreteKey, disabled)
    local dm = DM()
    if not (dm and concreteKey) then return end
    local b = SpecBucket(dm, concreteKey, true)
    b.baseOff = disabled and true or nil
end

-- Runtime read for the player's CURRENT spec (record synthesis + FP). No
-- specTiles = buckets never used = zero cost.
function ns.DM_CurrentSpecBaseOff()
    local dm = DM()
    local st = dm and dm.specTiles
    if not st then return false end
    local idx = GetSpecialization and GetSpecialization()
    local sid = idx and GetSpecializationInfo and GetSpecializationInfo(idx) or nil
    local b = sid and st["spec" .. sid] or nil
    return (b and b.baseOff) and true or false
end

-- The ACTIVE union: every tile the CURRENT spec renders, in bucket order
-- (allspecs, nonhealer, role group, own spec); group tiles the spec has
-- per-spec disabled drop out here. Returns a FRESH array per call -- the
-- apply pass iterates one while nested BuildRecords/EffectiveState calls
-- build another, so a reused scratch would be wiped under the iterator.
-- Config-pass frequency only (never per-frame), so the allocation is fine.
-- The tile TABLES inside are the stable store tables. Role/tracked
-- resolution rides the Buff Manager helpers (same ns, resolved at call
-- time).
function ns.DM_ActiveTiles()
    -- Read dm.tiles WITHOUT materializing it (DM_Tiles creates the array;
    -- this runs on the runtime config path and must not write an empty
    -- table into every tile-less profile's SavedVariables).
    local dm = DM()
    if not dm then return nil end
    local base = dm.tiles
    if base then HealTiles(base) end
    local out = {}
    local st = dm.specTiles
    local sid
    do
        local idx = GetSpecialization and GetSpecialization()
        sid = idx and GetSpecializationInfo and GetSpecializationInfo(idx) or nil
    end
    local con = st and sid and st["spec" .. sid] or nil
    local dis = con and con.inhDis or nil
    if base then
        for i = 1, #base do
            local t = base[i]
            if not (dis and dis[t.id]) then out[#out + 1] = t end
        end
    end
    if st and sid then
        local function AddBucket(key, filtered)
            local b = st[key]
            local tl = b and b.tiles
            if not tl then return end
            HealTiles(tl)
            for i = 1, #tl do
                local t = tl[i]
                if not (filtered and dis and dis[t.id]) then out[#out + 1] = t end
            end
        end
        if not (ns.BM_SpecKeyForSpecID and ns.BM_SpecKeyForSpecID(sid)) then
            AddBucket("nonhealer", true)
        end
        local roleKey = ns.BM_RoleBucketForSpecID and ns.BM_RoleBucketForSpecID(sid)
        if roleKey then AddBucket(roleKey, true) end
        AddBucket("spec" .. sid, false)
    end
    return out
end

function ns.DM_AddTile(tileType, bucketKey)
    local p = ns.db and ns.db.profile
    if not p then return nil end
    local dm = p.dmDebuff
    if not dm then dm = {}; p.dmDebuff = dm end
    if not dm.tiles then dm.tiles = {} end
    local id = (dm.nextTileId or 1)
    -- Counter heal: ids must stay GLOBALLY unique across every bucket
    -- (per-spec disables key on the bare id), so a reset/hand-edited
    -- counter re-bases above every existing tile before allocating.
    do
        local maxId = 0
        for i = 1, #dm.tiles do
            local tid = tonumber(dm.tiles[i].id) or 0
            if tid > maxId then maxId = tid end
        end
        if dm.specTiles then
            for _, b in pairs(dm.specTiles) do
                local tl = b.tiles
                if tl then
                    for i = 1, #tl do
                        local tid = tonumber(tl[i].id) or 0
                        if tid > maxId then maxId = tid end
                    end
                end
            end
        end
        if id <= maxId then id = maxId + 1 end
    end
    dm.nextTileId = id + 1
    local t = { id = id, enabled = true, type = tileType or "icons" }
    if t.type == "icons" or t.type == "square" then
        -- Grid tiles (Icon / Square): identical shape; squares add a color.
        t.claim = {}
        t.position = "top"
        t.growDirection = "CENTER"
        t.size = 18
        t.spacing = 1
        t.cap = 3
        if t.type == "square" then
            t.color = { r = 1, g = 0.35, b = 0.35, a = 1 }
        end
    else
        -- Effect tiles: filters come from the checkbox dropdown or the Add New popup's picks; none checked = nothing.
        t.claim = {}
        if t.type == "bar" then
            t.position = "bottom"; t.width = 60; t.height = 5
            t.orientation = "HORIZONTAL"
            t.color = { r = 0.25, g = 0.8, b = 0.45 }
            t.barColorOpacity = 100
            t.barBgColor = { r = 0, g = 0, b = 0 }
            t.barBgOpacity = 50
            t.frameLevel = "behindBorders"
        elseif t.type == "healthcolor" then
            t.color = { r = 1, g = 0.25, b = 0.25 }
            t.opacity = 45
        else -- glow
            t.glowType = 1
            t.color = { r = 1, g = 0.78, b = 0.38, a = 1 }
        end
    end
    -- The edited bucket owns the new tile; ids come from the ONE shared
    -- counter above regardless of bucket.
    local target = dm.tiles
    if bucketKey and bucketKey ~= "allspecs" then
        target = SpecBucket(dm, bucketKey, true).tiles
    end
    target[#target + 1] = t
    return t
end

-- Deep-copies a tile into another bucket (the right-click "Add To" menu):
-- full settings clone under a fresh GLOBAL id; the source is untouched.
-- DM_AddTile owns bucket creation + the healed id allocation; its default
-- fields are then replaced wholesale by the clone (id kept).
function ns.DM_CopyTile(src, bucketKey)
    if not src then return nil end
    local t = ns.DM_AddTile(src.type, bucketKey)
    if not t then return nil end
    local keep = t.id
    local function Copy(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, v2 in pairs(v) do o[k] = Copy(v2) end
        return o
    end
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(src) do t[k] = Copy(v) end
    t.id = keep
    return t
end

function ns.DM_DeleteTile(id)
    local dm = DM()
    if not dm then return end
    if dm.tiles then
        for i = #dm.tiles, 1, -1 do
            if dm.tiles[i].id == id then table.remove(dm.tiles, i) end
        end
    end
    local st = dm.specTiles
    if st then
        for _, b in pairs(st) do
            local tl = b.tiles
            if tl then
                for i = #tl, 1, -1 do
                    if tl[i].id == id then table.remove(tl, i) end
                end
            end
            -- Sweep the per-spec disable keys everywhere: ids are global and
            -- never reused, so a deleted tile's key can only leak.
            if b.inhDis then b.inhDis[id] = nil end
        end
    end
end




-------------------------------------------------------------------------------
-- Override-layer bridge (SpecOverrides DM layers): a fork is a wholesale deep copy of the profile's dmDebuff table.
-- Both hooks run EnsureMigrated first, so the one-shot preset mapping always precedes any fork traffic.
-------------------------------------------------------------------------------

local function DmLayerCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DmLayerCopy(x) end
    return t
end

-- Snapshot of the live Debuff Manager config for layer harvests.
function _G._ERF_DMHarvestFork()
    local p = ns.db and ns.db.profile
    if not p then return nil end
    EnsureMigrated()
    local dm = p.dmDebuff
    if type(dm) ~= "table" then return nil end
    return DmLayerCopy(dm)
end

-- Applies a SpecOverrides DM layer into the live profile (wipe + refill in place: open manager pages capture
-- subtable refs) and re-drives the container runtime (DM_CfgFP flips on content change).
function _G._ERF_DMApplyLayer(dm, noPageRefresh)
    if type(dm) ~= "table" then return false end
    local p = ns.db and ns.db.profile
    if not p then return false end
    EnsureMigrated()
    local live = p.dmDebuff
    if type(live) ~= "table" then live = {}; p.dmDebuff = live end
    wipe(live)
    for k, v in pairs(dm) do live[k] = DmLayerCopy(v) end
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
    if not noPageRefresh and ns._dmRoot and EllesmereUI and EllesmereUI.RefreshPage then
        EllesmereUI:RefreshPage(true)
    end
    return true
end
