-- EUI_RaidFrames_DebuffManager.lua
-- 12.1 Debuff Manager runtime: the base-grid record union (phase 1) plus
-- user-added custom tiles (phases 3/4).
--
-- BASE GRID: replaces the single debuff filter preset with a UNION OF
-- CATEGORY RECORDS -- one container group per enabled filter checkbox,
-- negation-chained so an aura renders in exactly one record wherever that
-- is expressible:
--   Ownership order (owners first): cc > dispel > raid > raidcombat.
--   Token-backed records exclude higher-priority records via !TOKEN in
--   their (declaration-fixed) filter strings; typed-dispel mode has no
--   token, so the OTHER records exclude it via excludeDispelTypes (live
--   candidate filters).
--   Boolean-backed records (boss/role, priority) negate every enabled
--   token record: positive-only candidates cannot be negated, so token
--   records own their overlaps and boolean records fill in the rest.
--   Boolean x boolean overlap is accepted (cannot be expressed).
--
-- TILES: user-added indicators driven by the same categories.
--   "icons" tiles CLAIM categories: a claimed category's record moves from
--   the base container to the tile's own container (own anchor/size/cap),
--   while its negation/exclude contributions to the remaining records are
--   KEPT (negations read the EFFECTIVE enabled set = base checkboxes OR
--   claims), so an aura still renders in exactly one icon display.
--   Effect tiles (glow/square/healthcolor/bar) are ADDITIVE signals for a
--   single category -- they do not claim, may overlap the icon displays by
--   design, and are driven by one re-filterable slot each (slot filter
--   strings and candidates are live-settable; no variant churn).
--   Tile containers persist per button (engine frames are never freed);
--   disabled/removed tiles park hidden (a hidden container fully
--   unregisters its events -- the zero-cost state).
--
-- Base records render into the EXISTING per-button debuff container via the
-- existing style/anchor/reload machinery; legacy preset groups park at 0
-- while the manager is active. Every shared integration site lives in the
-- 12.1-gated containers file and this file self-gates: a 12.0 client never
-- executes any of this.
--
-- Settings live at profile root (ns.db.profile.dmDebuff), shared across
-- raid/party/extra modes; absent table = feature off = zero cost. All keys
-- are NEW and additive -- nothing legacy is read differently or written (a
-- nondestructive view over the existing debuff display keys for
-- size/spacing/cap/position). The legacy debuffFilter preset key is
-- untouched and resumes control whenever the manager is disabled.
--
-- This file also owns the BUFF MANAGER's effective-state accessors for the
-- coexistence rework (base grid and custom indicators render together; the
-- legacy either/or bmDisplayMode key is never written, only shimmed).

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

-- 12.1 ONLY: inert on a 12.0 client.
if not (EllesmereUI and EllesmereUI.IS_121) then return end

local AK -- EllesmereUI.AuraKit, resolved at first use

local TYPED_DEBUFFS = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }

local CORNERS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

-- Duration-bar frame-level bands, relative to the unit button (the BM bar
-- indicator's Frame Level modes 1:1).
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
-- Buff Manager effective-state accessors (coexistence shims).
-- The legacy bmDisplayMode key is consulted ONLY here, as the default for
-- profiles that predate the redesign; the new keys are written exclusively
-- by the redesigned options page. Base grid and custom indicators are
-- independently enabled and render together.
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
    -- The user-editable exclude list is retired (2026-07-23): the exclude
    -- set is internal now -- the hardcoded sated/always-hide presets are
    -- the only blacklistable debuffs (merged in BuildRecords). Stale
    -- dm.excludeSpellIDs / dm.excludeSeedV keys in saved profiles are
    -- inert orphans: never read, never written.
    local p = ns.db and ns.db.profile
    return p and p.dmDebuff
end

-- One-shot per-profile migration: maps the retired Auras-tab state onto the
-- manager so existing users' debuffs look as close as possible on first
-- 12.1 login. Runs only when the profile has NO dmDebuff table yet (a
-- profile that already interacted with the manager is never touched); a
-- brand-new profile maps nil/"all" preset to the defaults = harmless.
-- Display/style keys need no mapping -- the base grid reads the legacy
-- debuff keys directly (nondestructive view).
local function EnsureMigrated()
    local p = ns.db and ns.db.profile
    if not p or p.dmDebuff then return end
    local preset = p.debuffFilter
    local dm = { _fromPreset = preset or "default" }
    if preset == "raid" then
        dm.all = false
        dm.raid = true
        dm.raidcombat = true
    elseif preset == "dispellable" then
        dm.all = false
        dm.dispel = true
        dm.dispelMode = "you" -- live preset = the by-you token, 1:1
    elseif preset == "none" then
        -- The manager has no disable concept: "none" preset users map to
        -- an empty base grid (Show All and Crowd Control explicitly off).
        dm.all = false
        dm.cc = false
    end
    -- The dispellable-location split (retired) becomes a Dispellable icons
    -- tile at the old anchor. The legacy split included exactly the TYPED
    -- debuffs, so the tile rides the "typed" dispel flavor -- 1:1 parity.
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
end

function ns.DM_Active()
    -- ALWAYS ON: the manager IS the debuff system on 12.1 (the legacy
    -- preset display retired with the Auras tab; there is no disable --
    -- an empty grid is expressed through the filters themselves). Kept as
    -- a function: the containers delegation calls it, and it hosts the
    -- migration hook. Show All and Crowd Control default on for legacy
    -- default parity (preset "all" + cc glow row).
    EnsureMigrated()
    return true
end

-- Mirrors of the containers file's tiny per-button helpers (that file is at
-- its local cap; duplicating two 4-line lookups beats exporting them).
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

-- The category vocabulary. token = filter-string routing (negatable);
-- cand = candidate-boolean routing (positive-only, identity-gated).
local CATS = { "boss", "role", "priority", "cc", "raid", "raidcombat", "dispel" }

-- Fingerprint over every input the record/tile synthesis reads that is not
-- already part of the containers file's DebuffCfgFP (which appends this).
-- A missed key here = the corresponding option never live-applies.
-- Per-tile style keys are a VIEW over the base debuff style keys (nil =
-- inherit; ZERO migration): non-nil tile keys shadow their base key via a
-- proxy table, so both the style build AND the style fingerprint see the
-- effective values. Declared ABOVE the config fingerprint (which must
-- flip when overrides change -- EnsureTileStyle only runs behind it).
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

-- EFFECTS: per-filter effect blocks (fxList array). Each entry: a filters
-- set + optional Icon Glow (glowType/glowClassColor/glowR/G/B) + optional
-- Border override (borderSize/borderColor) + optional Size (icon size for
-- the matched categories; 0/nil = the base grid size). An entry is ACTIVE
-- when it has filters checked and at least one payload; the FIRST matching
-- block wins per button category. Declared ABOVE the config fingerprint
-- (callers).
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
-- One-time heal: the first Effects build stored a single fxGlow config.
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
-- Per-filter Size resolution for a record category: the FIRST matching
-- ACTIVE block wins the category outright (identical rule to the glow/
-- border applier's DmFxBlockFor -- one block owns a category, so a later
-- block's Size never reaches a category an earlier block matched). The
-- merged "bossrole" record matches either constituent, like the applier.
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

function ns.DM_CfgFP()
    EnsureMigrated() -- profile switches re-fingerprint before rendering
    local dm = DM() or {}
    FxHeal(dm)
    local prof = ns.db and ns.db.profile
    local parts = {
        "on",
        dm.all ~= false and 1 or 0, dm.boss and 1 or 0, dm.role and 1 or 0,
        dm.priority and 1 or 0, dm.cc ~= false and 1 or 0, dm.raid and 1 or 0,
        dm.raidcombat and 1 or 0, dm.dispel and 1 or 0,
        (dm.dispelMode == "typed") and "typed" or "you",
        FxListFP(dm.fxList), -- base effects force records
        -- The internal exclude set varies only with the retail lust-debuff
        -- opt-out (the hardcoded lists are load-constant).
        (not prof or prof.hideLustDebuff ~= false) and "lx1" or "lx0",
    }
    local tiles = dm.tiles
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
                    t.claim.dispel and 1 or 0 }, "") or "-",
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

-- Effective enabled flags: a category is "on" if the base checkbox shows it
-- OR an enabled icons tile claims it. Negations key off THESE (a claimed
-- category must still be excluded from every other record). Also resolves
-- claims: claims[cat] = tile table (first enabled claimer wins).
local function EffectiveState(dm)
    -- cc defaults ON (legacy parity: the CC glow row rendered under every
    -- active preset); every other category is opt-in.
    local eff = { boss = dm.boss, role = dm.role, priority = dm.priority,
        cc = dm.cc ~= false, raid = dm.raid, raidcombat = dm.raidcombat, dispel = dm.dispel }
    local claims = {}
    local tiles = dm.tiles
    if tiles then
        for i = 1, #tiles do
            local t = tiles[i]
            if t.enabled and (t.type == "icons" or t.type == "square") and t.claim then
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
    return eff, claims
end

-- Builds ALL active records with their routing. Each record: key, tokens
-- (declaration-fixed filter parts), cand (fresh candidate table), gated
-- (candidate-boolean record), tile (hosting tile table or nil = base).
-- Also returns the crowd-control candidate table (the base drives the
-- legacy "cc" group -- fixed filter, carries the CC glow style -- whenever
-- cc is UNCLAIMED; a claimed cc renders in its tile with the tile style,
-- and the CC glow stays a base-group property).
local function BuildRecords(s, dm)
    local eff, claims = EffectiveState(dm)
    -- EFFECTS routing: per-filter icon effects (fxGlow today) need their
    -- categories to exist as SEPARATE base records even under Show All --
    -- like claims, but rendering in the base container -- so the effect
    -- can target exactly those buttons (stamped d.dmCat). Token categories
    -- negate out of the all-record; boolean categories duplicate (the same
    -- accepted limitation as claims).
    local fxCats = {}
    do
        local fl = dm.fxList
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
    local ccOn = eff.cc and true or false
    local allOn = dm.all ~= false -- Show All defaults ON (legacy "all" preset parity)

    -- Dispellable has exactly two flavors (the "by anyone" mode was cut):
    -- "you" = the RAID_PLAYER_DISPELLABLE token; "typed" = anything with a
    -- dispel type (candidate include map -- not tokenizable, so dedup
    -- against other records rides excludeDispelTypes instead of a !token).
    local dispelOn = eff.dispel and true or false
    local dispelMode = (dm.dispelMode == "typed") and "typed" or "you"
    local dispelToken = (dispelOn and dispelMode == "you") and "RAID_PLAYER_DISPELLABLE" or nil
    -- The typed exclude only applies while the typed dispel record is
    -- actually BUILT (claimed, or base without Show All) -- otherwise
    -- Show All would exclude typed debuffs nothing re-adds.
    local typedMap = dispelOn and dispelMode == "typed"
        and ((claims.dispel or fxCats.dispel or not (dm.all ~= false)) and true or false)

    -- Internal exclude set (user editing retired): the hardcoded sated
    -- list -- honoring the retail Show Lust Debuff opt-out -- plus the
    -- always-hide pair. 68824's never-secret identity-gate exemption makes
    -- these excludes real on friendly units for never-secret spells; a
    -- secret-flagged entry is accepted but inert (the engine drops it
    -- silently).
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
        return cf
    end

    -- The cc group/record owns dispellable crowd control: its candidates
    -- must NOT carry the typed exclude (with both, a magic stun would
    -- vanish from both records).
    local ccCand = { excludeSpellIDs = ex }

    local recs = {}

    local function Neg(toks, negCC, negDispel, negRaid)
        if negCC and ccOn then toks[#toks + 1] = "!CROWD_CONTROL" end
        if negDispel and dispelToken then toks[#toks + 1] = "!" .. dispelToken end
        if negRaid and eff.raid then toks[#toks + 1] = "!RAID" end
        return toks
    end

    -- Show All short-circuits the BASE union (every other base record would
    -- be a pure duplicate in one visually-uniform row) but tiles still
    -- render their claims; the all-record negates claimed TOKEN categories
    -- so those stay single-rendered (boolean claims duplicate -- accepted,
    -- positive-only candidates cannot be negated).
    if allOn then
        local toks = { "HARMFUL" }
        Neg(toks, true,
            (claims.dispel or fxCats.dispel) and true or false,
            (claims.raid or fxCats.raid) and true or false)
        if claims.raidcombat or fxCats.raidcombat then toks[#toks + 1] = "!RAID_IN_COMBAT" end
        recs[#recs + 1] = { key = "all", tokens = toks, cand = Cand(false) }
    end

    -- Claimed crowd control: the base normally rides the legacy cc group,
    -- but a claiming tile hosts cc as a normal record (fresh candidate
    -- table -- NEVER the typed exclude, see ccCand above; tile style, the
    -- CC glow stays a base-group property).
    if eff.cc and claims.cc then
        recs[#recs + 1] = { key = "cc", tokens = { "HARMFUL", "CROWD_CONTROL" },
            cand = { excludeSpellIDs = ex }, tile = claims.cc }
    end

    -- Sized base crowd control: an Icon Effects Size on cc cannot resize
    -- the fixed legacy "cc" group's buttons (group->style binding is fixed
    -- at declare), so cc becomes a base record variant instead; its style
    -- carries the CC-glow flavor so the glow survives the move. The apply
    -- pass parks the legacy group while this record exists.
    if eff.cc and not claims.cc and FxSizeFor(dm.fxList, "cc") then
        recs[#recs + 1] = { key = "cc", tokens = { "HARMFUL", "CROWD_CONTROL" },
            cand = { excludeSpellIDs = ex } }
    end

    -- Category records (skipped in the base when Show All covers them;
    -- always built for their claiming tile).
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
        if eff.raidcombat then toks[#toks + 1] = "!RAID_IN_COMBAT" end
        return toks
    end
    -- Boss/role merge into one record only when they route to the SAME
    -- place; split claims build separate records.
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

    -- Per-filter Icon Effects Size: stamp each record with its owner list's
    -- resolved size (base records read the base blocks, tile-hosted records
    -- read their tile's -- the same list the applier matches against).
    for i = 1, #recs do
        local r = recs[i]
        r.fxSize = FxSizeFor(r.tile and r.tile.fxList or dm.fxList, r.key)
    end

    return recs, ccCand, claims, Cand, fxCats
end

-- Group keys embed the normalized filter string: filter strings are
-- declaration-fixed, so an option change that alters a record's negation
-- set declares a NEW variant group and parks the old one at 0 (add-only
-- engine, leak-free parking; boolean records share token sets, hence the
-- record-key prefix keeps them distinct).
local function GroupKey(AKL, r)
    -- "|sz" marks a SIZED record (group->style binding is fixed at declare,
    -- so gaining/losing a Size swaps the variant). The size VALUE is
    -- deliberately not in the key: the sized style key is stable per
    -- category and its content rebuilds on size edits -- a slider drag
    -- restyles existing buttons instead of minting an engine batch per step.
    return "dm_" .. r.key .. "|" .. AKL.Filter(unpack(r.tokens))
        .. (r.fxSize and "|sz" or "")
end

-- Effect-tile category resolution: one live-settable slot per tile.
local function EffectFilterFor(dm, cat)
    if cat == "cc" then return { "HARMFUL", "CROWD_CONTROL" }, nil, false end
    if cat == "raid" then return { "HARMFUL", "RAID" }, nil, false end
    if cat == "raidcombat" then return { "HARMFUL", "RAID_IN_COMBAT" }, nil, false end
    if cat == "dispel" then
        -- Follows the base dispel flavor: by-you token, or the typed
        -- include map ("by anyone" was cut from the design).
        if dm.dispelMode == "typed" then
            return { "HARMFUL" }, { includeDispelTypes = TYPED_DEBUFFS }, false
        end
        return { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }, nil, false
    end
    if cat == "boss" then return { "HARMFUL" }, { isBossAura = true }, true end
    if cat == "role" then return { "HARMFUL" }, { isRoleAura = true }, true end
    -- "priority" (default)
    return { "HARMFUL" }, { isPriorityAura = true }, true
end

-------------------------------------------------------------------------------
-- Tile containers (per button, persistent, parked when unused)
-------------------------------------------------------------------------------

-- Per-slot-button refs for the effect appliers (weak keys: engine buttons
-- are pooled frames we must never write properties onto).
local fxRefs = setmetatable({}, { __mode = "k" })

-- DEBUG (/euidm dump; remove with the slash): per-slot-button applier
-- breadcrumbs -- proves whether FxApply ever ran and what the gate saw.
local fxDbg = setmetatable({}, { __mode = "k" })

-- Effect visuals: ALL created in the slot's extraInit -- the ONLY window
-- where insecure calls on the engine button are legal (the engine denies
-- reads AND writes everywhere else, permanently, and the restyler's pcall
-- swallows the denial silently -- create-in-the-applier builds nothing,
-- ever). The applier (FxApply) only parameterizes frames we own. Children
-- hang off the slot button (visibility rides the aura match) and anchor
-- OUTWARD to our clean frames (unit button / health) -- the dispel-overlay
-- precedent, and the BmEffectInit doctrine.
-- Hide every effect visual on one slot button (filter-gated slots and
-- teardown paths share it).
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

-- Creation-window builder: one kind-specific visual set per effect slot,
-- parked hidden until the applier arms it. Runs inside extraInit (which
-- runs inside a CreateFrameBatch -- an error here kills the whole slot
-- declaration, hence the pcall-degraded engine binding).
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
        -- BM healthcolor parity via an owned wrapper: level-tied WITH the
        -- health frame (not above it) so the tint sorts against health's
        -- own regions by ARTWORK sublevel -- above the fill (0), below the
        -- heal absorb/prediction bars (+1) and the shield bars (+3) -- and
        -- anchored to the FILL texture so it covers only the filled
        -- portion. The wrapper is ours, so the level tie stays legal.
        local f = CreateFrame("Frame", nil, button)
        local fill = health.GetStatusBarTexture and health:GetStatusBarTexture()
        f:SetAllPoints(fill or health)
        f:SetFrameLevel(health:GetFrameLevel())
        local tex = f:CreateTexture(nil, "ARTWORK", nil, 2)
        tex:SetAllPoints(f)
        f:Hide()
        dd.dmFxHcFrame = f
        dd.dmFxHc = tex
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
        -- Engine duration binding: the engine drives the fill from the
        -- aura's duration object. Button call -- legal only HERE.
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
        -- Color mode (trio swatch): default = the untinted proc gold,
        -- class = the player's class color, custom = fx.r/g/b.
        local cr, cg, cb = fx.r or 1, fx.g or 0.78, fx.b or 0.38
        local mode = fx.glowMode or "default"
        if mode == "class" then
            local _, classFile = UnitClass("player")
            local ccc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if ccc then cr, cg, cb = ccc.r, ccc.g, ccc.b end
        elseif mode == "default" then
            cr, cg, cb = 1.0, 0.788, 0.137
        end
        -- Size from the unit frame's REAL rect (refs.host is our frame,
        -- outside the forbidden subtree -- reads are legal; this arming
        -- pass runs in the creation window).
        local gw = refs.host:GetWidth() or 0
        local gh = refs.host:GetHeight() or 0
        if gw < 1 then gw = 24 end
        if gh < 1 then gh = gw end
        -- One style only: the animation-driven pixel march (driver-ticked
        -- glows freeze on the forbidden slot subtree; this runs C-side
        -- forever).
        if Glows.StartAnimatedAnts then
            Glows.StartAnimatedAnts(host, fx.glowLines or 8, fx.glowThickness or 2,
                fx.glowSpeed or 4, cr, cg, cb, gw, gh)
        end

    elseif fx.kind == "healthcolor" then
        local f = dd.dmFxHcFrame
        local tex = dd.dmFxHc
        if not (f and tex) then return end -- created in extraInit
        -- Level tie is set at creation; NO re-check here -- reads on the
        -- slot-button subtree (our frames included) are denied outside the
        -- creation window and would kill this whole branch.
        tex:SetColorTexture(fx.r or 1, fx.g or 0.2, fx.b or 0.2, fx.a or 0.5)
        f:Show()

    elseif fx.kind == "square" then
        local gf = dd.dmFxGeoF
        if not gf then return end -- created in extraInit
        local w = fx.w or 10
        local h = fx.h or 10
        local sig = table.concat({ tostring(w), tostring(h), tostring(fx.corner),
            tostring(fx.offX), tostring(fx.offY) }, ",")
        if dd.dmFxGeo ~= sig then
            -- Geometry rides OUR frame (always-legal calls); the sig cache
            -- just keeps repeat applies cheap.
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
        -- BM_PlaceBar 1:1: width/height are FILL-axis sliders; the Full
        -- toggles follow the fill axis too, so they swap screen edges when
        -- the bar is vertical. Geometry rides OUR StatusBar (always-legal
        -- calls); the sig cache keeps repeat applies cheap.
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
            -- Frame Level band relative to the unit button (our frame; this
            -- arming pass runs in the creation window where the read is
            -- legal).
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
    -- DEBUG breadcrumb (remove with the slash)
    local dbg = fxDbg[button]
    if not dbg then dbg = {}; fxDbg[button] = dbg end
    dbg.n = (dbg.n or 0) + 1
    dbg.kind = fx and fx.kind
    dbg.cat = dd.dmCat
    dbg.gate = not not (dd.dmCat and fx and fx.filters and fx.filters[dd.dmCat])
    dbg.dd = dd
    if ns.DM_DEBUG then
        print(("|cff0cd2a0DMfx|r cat=%s kind=%s refs=%s gate=%s"):format(
            tostring(dd.dmCat), tostring(fx and fx.kind), tostring(refs ~= nil),
            tostring(dbg.gate)))
    end
    if not (refs and fx) then return end

    -- Per-filter gating: an effect tile declares one slot per EVER-checked
    -- category (add-only engine); slots whose category is currently
    -- unchecked render nothing.
    -- DEBUG: both paths pcall-wrapped with the error RECORDED (the restyler
    -- swallows applier errors silently -- dbg.err is how we see them).
    local ok, err
    if not dbg.gate then
        ok, err = pcall(FxHideAll, dd)
    else
        ok, err = pcall(FxApplyInner, button, dd, refs, fx)
    end
    dbg.ok = ok
    dbg.err = (not ok) and tostring(err) or nil
end

-- Icon-tile flow anchoring (corner-pinned chain, CENTER growth centers the
-- row on the anchor point -- the defensives-row math with tile settings).
local function AnchorTileContainer(container, health, s, t)
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, s) or health
    local corner = CORNERS[t.position or "top"] or "TOP"
    local grow = t.growDirection or "CENTER"
    local offX = t.offsetX or 0
    local offY = t.offsetY or 0

    AK = AK or EllesmereUI.AuraKit
    -- Grid wrap (12.1): Icons Per Row >= 2 wraps lines away from the
    -- anchored edge (simple-grid convention; lowercase position tokens
    -- here); vertical growth flips the flow axis so lines are columns.
    -- Below 2 = the legacy single run, corner pick untouched.
    local per = tonumber(t.iconsPerRow) or 0
    local pl = t.position or "top"
    local wrapUp = pl:find("bottom", 1, true) ~= nil
    local wrapLeft = pl:find("right", 1, true) ~= nil
    container:ClearAllPoints()
    if grow == "CENTER" then
        container:SetPoint("CENTER", health, corner, offX, offY)
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

-- Ensures the per-class style for one tile exists and is current. Icon
-- tiles reuse the debuff style at the tile's size; effect tiles get a bare
-- noRegions style whose applyExtra renders the effect from style.fx.
-- szOv/szCat: a per-filter Icon Effects Size hosts the sized record on its
-- own STABLE per-category style variant of the tile style (content rebuilds
-- on size edits; the group variant only swaps at the sized/unsized edge).
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
        local sv = TileStyleView(s, t)
        v = ((ns.RFC_DebuffStyleFP and ns.RFC_DebuffStyleFP(sv, font)) or "")
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
                -- Square grid: a flat color block covers the spell icon
                -- (rendered by the shared debuff applier).
                sty.squareColor = t.color or { r = 1, g = 0.35, b = 0.35, a = 1 }
            end
            -- Per-tile Effects override the base-injected fx (explicitly,
            -- including nil -- a tile without its own blocks must not
            -- inherit the base pane's).
            sty.fxList = FxListView(t.fxList)
            AK.styles[key] = sty
            AK.RestyleSoon(key)
        end
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
            table.concat(cl, "+"),
        }, "|")
        if st.style ~= v then
            st.style = v
            AK.styles[key] = {
                noRegions = true,
                applyExtra = FxApply,
                fx = {
                    kind = t.type,
                    -- Checked-filter set: the applier's per-slot gate (live
                    -- table reference; the FP above rebuilds on changes).
                    filters = t.claim or {},
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
                    -- Health color rides a dedicated Opacity setting (the
                    -- swatch has no alpha strip there, matching BM).
                    a = (t.type == "healthcolor")
                        and ((t.opacity or 45) / 100) or c.a,
                },
            }
            AK.RestyleSoon(key)
        end
    end
    return key
end

-- Sized BASE-record styles: an Icon Effects block with a Size renders its
-- categories at that size. Buttons take their physical size from the style
-- at creation, so each sized category gets its own STABLE style key --
-- content rebuilds when the size or the underlying debuff style changes;
-- the group variant only swaps at the sized/unsized edge (GroupKey "|sz").
-- "cc" builds the CC-glow style flavor so sized crowd control keeps its
-- glow. Registry entries let the containers file refresh these alongside
-- its own base-style rebuilds (DM_RefreshSizedStyles below).
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

-- Called by the containers file whenever it rebuilds a class's base debuff
-- styles on a style-fingerprint change: a pure style edit (border color,
-- text font...) does not flip the config fingerprint, so the apply pass --
-- and with it EnsureBaseSizeStyle -- may not run; the sized siblings must
-- refresh at the same site the base styles do or they render stale.
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
end

-- Ensures one tile's container exists for this button (queued: container
-- shells are combat-illegal -- probe T3 zombie). Effect tiles declare their
-- single slot at build; icon tiles get record groups declared by the apply
-- pass (combat-legal adds on existing containers).
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
        local dm2 = DM()
        local t2
        if dm2 and dm2.tiles then
            for i = 1, #dm2.tiles do
                if dm2.tiles[i].id == tileId then t2 = dm2.tiles[i] break end
            end
        end
        if not t2 then return end
        local s2 = SettingsFor(d)
        if not s2 then return end
        local styleKey = EnsureTileStyle(d, s2, t2)
        local container = AK.CreateContainerShell(button, {
            point = { "CENTER", health, "CENTER" },
        })
        -- Level bands (live parity): grid and bar tiles render in the aura
        -- band (button + LVL_AURA = 13, above every border and the text
        -- band, exactly like legacy aura icons). Healthcolor slots re-tie
        -- their own level to the health frame in the applier (BM parity:
        -- the tint sorts against health's regions by ARTWORK sublevel), so
        -- their container level is only a pre-apply default; glow hosts
        -- level themselves absolutely (+15) likewise. Containers default
        -- far LOWER than all of this, which put tile icons underneath
        -- borders and text.
        if t2.type == "healthcolor" then
            container:SetFrameLevel(button:GetFrameLevel() + 6)
        else
            container:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA or 13))
        end
        if t2.type ~= "icons" and t2.type ~= "square" then
            -- One slot PER checked filter category (the Filters checkbox
            -- dropdown); later checks add slots on the live lane, and the
            -- applier's filter gate silences slots for unchecked ones.
            local host = button
            local hp = health
            local tGroups = d.dmTileGroups
            if not tGroups then tGroups = {}; d.dmTileGroups = tGroups end
            local tDecl = tGroups[tileId]
            if not tDecl then tDecl = {}; tGroups[tileId] = tDecl end
            local tileKind = t2.type
            for cat, on in pairs(t2.claim or {}) do
                if on then
                    local catKey = cat
                    local filter, cand = EffectFilterFor(dm2, catKey)
                    AK.AddSlotToContainer(container, {
                        key = "fx_" .. catKey,
                        filter = filter,
                        candidateFilters = cand,
                        style = styleKey,
                        extraInit = function(slotButton, d2, style)
                            -- Category stamp (the applier's filter gate) +
                            -- refs for the effect applier (weak map, never
                            -- frame properties) + ALL visual frames + the
                            -- ARMING pass -- this is the only window where
                            -- subtree calls are legal, and the initializer
                            -- runs applyExtra BEFORE this callback (refs
                            -- were nil there, so it bailed).
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
        -- Re-drive this button's manager config so the fresh container gets
        -- its groups/counts/anchor (per-button; the pass is cheap).
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
    -- Default-ON: a fresh profile has no dmDebuff table yet; the empty
    -- table reads as the defaults (Show All + Crowd Control on).
    local dm = DM() or {}
    local declared = d.rfcDebuffGroups
    if not (AK and declared) then return end

    local cap = s.debuffCap or 3
    local size = s.debuffSize or 18
    local layout = {
        elementWidth = size, elementHeight = size,
        elementSpacing = s.debuffSpacing or 1, lineSpacing = s.debuffSpacing or 1,
    }

    local recs, ccCand, claims, _, fxCats = BuildRecords(s, dm)

    -- Partition records: base container vs per-tile containers.
    local wantedBase, missingBase = {}, false
    local baseSizedCC = false -- sized cc record replaces the legacy cc group
    local tileRecs = {} -- [tileId] = array of records
    for i = 1, #recs do
        local r = recs[i]
        r.gkey = GroupKey(AK, r)
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

    -- Park everything the base does not want (legacy preset groups + stale
    -- record variants). Setters are dirty marks; this runs only when the
    -- debuff fingerprint actually changed.
    for k in pairs(declared) do
        if k ~= "cc" and not wantedBase[k] then
            container:SetAuraGroupMaxFrameCount(k, 0)
        end
    end

    -- Crowd Control rides the existing cc group (CC glow style intact)
    -- whenever it is enabled and UNCLAIMED; a claiming tile hosts it as a
    -- normal record instead (tile style; the glow stays base-only).
    if declared.cc then
        -- A sized base cc record (Icon Effects Size on cc) supplants the
        -- legacy group: park it or every CC debuff renders twice.
        local ccBase = ((dm.cc ~= false) or (fxCats and fxCats.cc)) and not claims.cc
            and not baseSizedCC
        container:SetAuraGroupMaxFrameCount("cc", ccBase and cap or 0)
        container:SetAuraGroupCandidateFilters("cc", ccCand)
        container:SetAuraGroupLayout("cc", layout)
    end

    local assist = d.rfcAssist ~= false
    local gatedKeys

    -- Base records.
    for gkey, r in pairs(wantedBase) do
        if declared[gkey] then
            local n = cap
            if r.gated then
                gatedKeys = gatedKeys or {}
                gatedKeys[#gatedKeys + 1] = gkey
                if not assist then n = 0 end
            end
            container:SetAuraGroupMaxFrameCount(gkey, n)
            container:SetAuraGroupCandidateFilters(gkey, r.cand)
            if r.fxSize then
                -- Sized record: keep the stable per-category style fresh
                -- (size edits rebuild its content -> existing buttons
                -- restyle) and feed the flow math the same size.
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

    -- Missing base record variants: declare on the combat-legal live lane,
    -- then re-apply (mirrors the containers file's preset-ensure pattern).
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
                        -- Stamp the record category on every button (per-
                        -- filter EFFECTS match against it) and arm the
                        -- ICON EFFECTS in the creation window -- the style
                        -- applier ran BEFORE this stamp at init and found
                        -- no category.
                        local catKey = r.key
                        -- Sized records bind their per-category sized style
                        -- (buttons take the physical size at creation).
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

    -- Tiles. Stash the host ref the deferred tile builds need (the base
    -- debuff container is parented to the unit button on every build path).
    d.dmHost = d.dmHost or (container.GetParent and container:GetParent())
    local dmTiles = dm.tiles
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
                        -- One live-settable slot PER CHECKED category. Slot
                        -- filters/candidates are live (the setter gets the
                        -- NORMALIZED string; candidates get an explicit
                        -- empty table, never nil -- NP field lesson).
                        -- Newly-checked categories without a declared slot
                        -- add on the combat-legal live lane below.
                        local missingCats = false
                        for cat, on in pairs(t.claim or {}) do
                            if on then
                                local skey = "fx_" .. cat
                                local filter, cand, catGated = EffectFilterFor(dm, cat)
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
                                    local t2
                                    if dm2.tiles then
                                        for ti2 = 1, #dm2.tiles do
                                            if dm2.tiles[ti2].id == tileId then t2 = dm2.tiles[ti2] break end
                                        end
                                    end
                                    local host = d.dmHost
                                    local hp = d.rfcHealth
                                    if not (t2 and host and hp) then return end
                                    local styleKey2 = EnsureTileStyle(d, s2, t2)
                                    local tileKind = t2.type
                                    for cat, on in pairs(t2.claim or {}) do
                                        local skey = "fx_" .. cat
                                        if on and not decl2[skey] then
                                            local catKey = cat
                                            local filter, cand = EffectFilterFor(dm2, catKey)
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
                        -- Record groups on the tile container (variant keys,
                        -- additive declares, park stale variants).
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
                        for gkey, r in pairs(tWanted) do
                            if tDecl[gkey] then
                                local n = tCap
                                if r.gated then
                                    gatedContent = true
                                    if not assist then n = 0 end
                                end
                                tc:SetAuraGroupMaxFrameCount(gkey, n)
                                tc:SetAuraGroupCandidateFilters(gkey, r.cand)
                                if r.fxSize then
                                    -- Sized record: keep its per-category
                                    -- tile style variant fresh + matching
                                    -- flow math (see the base loop).
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
                        if tMissing then
                            -- Combat-legal group adds on the existing tile
                            -- container; keyed ensure per tile.
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
                                                    -- Sized records bind the per-category
                                                    -- sized variant of the tile style.
                                                    style = r.fxSize
                                                        and EnsureTileStyle(d, s2, r.tile, r.fxSize, r.key)
                                                        or EnsureTileStyle(d, s2, r.tile),
                                                    extraInit = function(btn2, d2, style)
                                                        if d2 then d2.dmCat = catKey end
                                                        -- Arm ICON EFFECTS in the creation
                                                        -- window (see the base-record site).
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
                        AnchorTileContainer(tc, d.rfcHealth, s, t)
                    end

                    if gatedContent then
                        gatedTiles = gatedTiles or {}
                        gatedTiles[#gatedTiles + 1] = t.id
                        tc:SetShown(assist)
                    else
                        tc:Show()
                    end
                    -- Same-unit re-sets are a full engine re-registration
                    -- (the RF roster-reprocess storm lesson) -- stamp on our
                    -- own container frame and only re-point on change.
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
        for id, c in pairs(live) do
            if not present[id] then c:Hide() end
        end
    end
    d.dmGatedTiles = gatedTiles
end

-- Legacy-config tail hook: when the manager is INACTIVE the legacy
-- ApplyDebuffConfig only drives its own preset groups, so record variants
-- and tile containers from a just-disabled manager would keep rendering.
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

-- Unit re-assignment hook (called from RFC_OnUnitAssigned's unit-change
-- branch): tile containers must re-point like every other per-button
-- container -- the engine does not re-parse on unit change alone.
function ns.DM_OnUnitAssigned(d, unit)
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

-- Assist-state hook (called from ApplyAssistGate on actual state changes):
-- identity-gated records and tiles flip; everything else is assist-blind,
-- matching the token-only behavior of the legacy debuff row.
function ns.DM_OnAssistChanged(d)
    if not ns.DM_Active() then return end
    local assist = d.rfcAssist ~= false
    local keys = d.dmGatedKeys
    local container = d.rfcDebuffs
    if keys and container then
        local n = assist and (d.dmCap or 3) or 0
        for i = 1, #keys do
            container:SetAuraGroupMaxFrameCount(keys[i], n)
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
function ns.DM_Tiles()
    local dm = DM()
    if not dm then return nil end
    if not dm.tiles then dm.tiles = {} end
    -- Read-heal: squares were EFFECT tiles (single cat + width/height)
    -- before becoming grid tiles; expand the old shape once.
    for i = 1, #dm.tiles do
        local t = dm.tiles[i]
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
        -- Effect tiles moved from a single category (t.cat) to the checkbox
        -- filter set; expand the old shape once.
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
    return dm.tiles
end

function ns.DM_AddTile(tileType)
    local p = ns.db and ns.db.profile
    if not p then return nil end
    local dm = p.dmDebuff
    if not dm then dm = {}; p.dmDebuff = dm end
    if not dm.tiles then dm.tiles = {} end
    local id = (dm.nextTileId or 1)
    dm.nextTileId = id + 1
    local t = { id = id, enabled = true, type = tileType or "icons" }
    if t.type == "icons" or t.type == "square" then
        -- Grid tiles (Icon / Square): identical shape; squares add the
        -- block color the flat squares render with.
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
        -- Effect tiles: filters arrive via the checkbox dropdown (or the
        -- Add New popup's picks); none checked = the effect renders nothing.
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
    dm.tiles[#dm.tiles + 1] = t
    return t
end

function ns.DM_DeleteTile(id)
    local dm = DM()
    if not (dm and dm.tiles) then return end
    for i = #dm.tiles, 1, -1 do
        if dm.tiles[i].id == id then table.remove(dm.tiles, i) end
    end
end

-- TEMPORARY dev toggle until the redesigned options pages are the primary
-- path everywhere -- REMOVE before release. /euidm
-- <all|boss|role|priority|cc|raid|raidcombat|dispel> toggles a filter;
-- /euidm status (or bare /euidm) prints the current state.
SLASH_EUIDM1 = "/euidm"
SlashCmdList.EUIDM = function(msg)
    local p = ns.db and ns.db.profile
    if not p then return end
    local dm = p.dmDebuff
    if not dm then dm = {}; p.dmDebuff = dm end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S*)%s*(%S*)$")
    if cmd == "" then
        -- No disable concept: bare /euidm reports state.
        cmd = "status"
    end
    if cmd == "status" then
        local parts = {}
        for _, k in ipairs({ "all", "boss", "role", "priority", "cc", "raid", "raidcombat", "dispel" }) do
            local v = dm[k]
            if k == "all" or k == "cc" then v = v ~= false end
            parts[#parts + 1] = k .. "=" .. tostring(v or false)
        end
        parts[#parts + 1] = "tiles=" .. tostring(dm.tiles and #dm.tiles or 0)
        print("|cff0cd2a0EUI|r DM " .. table.concat(parts, " "))
        return
    elseif cmd == "debug" then
        ns.DM_DEBUG = not ns.DM_DEBUG
        print("|cff0cd2a0EUI|r DM applier debug prints: " .. (ns.DM_DEBUG and "ON" or "OFF"))
        return
    elseif cmd == "kick" then
        -- Manual engine re-parse on every tile container: if effects appear
        -- after a kick, the containers match fine but never receive aura
        -- updates (event registration); if not, the match itself fails.
        local reg = ns._rfcRegistry
        if not reg then print("|cff0cd2a0EUI|r DM kick: no registry") return end
        local n = 0
        for i = 1, #reg do
            local d2 = ns.GetFFD and ns.GetFFD(reg[i])
            if d2 and d2.dmTiles then
                for _, c in pairs(d2.dmTiles) do
                    if pcall(c.UpdateAllAuras, c) then n = n + 1 end
                end
            end
        end
        print("|cff0cd2a0EUI|r DM kick: UpdateAllAuras on " .. n .. " tile containers")
        return
    elseif cmd == "dump" then
        -- Declaration-path diagnostic: records, routing, live containers,
        -- declared slot/group keys, pending jobs -- for one unit's button.
        AK = AK or EllesmereUI.AuraKit
        local reg = ns._rfcRegistry
        if not (AK and reg and #reg > 0) then
            print("|cff0cd2a0EUI|r DM dump: no live buttons")
            return
        end
        local want = (arg ~= "" and arg) or "player"
        local btn
        for i = 1, #reg do
            local b = reg[i]
            local u = (b.GetAttribute and b:GetAttribute("unit")) or b.unit
            if u and UnitIsUnit(u, want) then btn = b break end
        end
        btn = btn or reg[1]
        local d = ns.GetFFD and ns.GetFFD(btn)
        if not d then print("|cff0cd2a0EUI|r DM dump: no frame data") return end
        local dm2 = DM() or {}
        local s2 = SettingsFor(d)
        print(("|cff0cd2a0EUI|r DM dump unit=%s active=%s all=%s mode=%s base=%s"):format(
            tostring((btn.GetAttribute and btn:GetAttribute("unit")) or "?"),
            tostring(ns.DM_Active and ns.DM_Active() or false),
            tostring(dm2.all ~= false),
            (dm2.dispelMode == "typed") and "typed" or "you",
            tostring(d.rfcDebuffs ~= nil)))
        if not s2 then print("  no settings proxy") return end
        local recs, _, _, _, fxCats2 = BuildRecords(s2, dm2)
        for i = 1, #recs do
            local r = recs[i]
            local declared
            if r.tile then
                local decl = d.dmTileGroups and d.dmTileGroups[r.tile.id]
                declared = decl and decl[GroupKey(AK, r)] and true or false
            else
                declared = d.rfcDebuffGroups and d.rfcDebuffGroups[GroupKey(AK, r)] and true or false
            end
            print(("  rec %s -> %s [%s] declared=%s"):format(r.key,
                r.tile and ("tile#" .. r.tile.id) or "base",
                table.concat(r.tokens, ", "), tostring(declared)))
        end
        local fxc = {}
        for k in pairs(fxCats2 or {}) do fxc[#fxc + 1] = k end
        if #fxc > 0 then print("  fxCats: " .. table.concat(fxc, ",")) end
        -- Engine-materialized button census for one container (child frames
        -- + how many are currently shown -- proves whether the slot filter
        -- ever matched an aura). Shown reads pcall-wrapped: restricted aura
        -- buttons may deny reads.
        local function Census(c)
            if not c then return "-" end
            local kids, shown, denied = 0, 0, 0
            local n = (c.GetNumChildren and c:GetNumChildren()) or 0
            for ci = 1, n do
                local ch = select(ci, c:GetChildren())
                if ch then
                    kids = kids + 1
                    local ok, sh = pcall(ch.IsShown, ch)
                    if not ok then denied = denied + 1
                    elseif sh then shown = shown + 1 end
                end
            end
            return kids .. "/" .. shown .. (denied > 0 and ("/denied" .. denied) or "")
        end
        print("  base buttons total/shown: " .. Census(d.rfcDebuffs))
        if dm2.tiles then
            for i = 1, #dm2.tiles do
                local t = dm2.tiles[i]
                local cats = {}
                for c, on in pairs(t.claim or {}) do if on then cats[#cats + 1] = c end end
                local decl = d.dmTileGroups and d.dmTileGroups[t.id]
                local dkeys = {}
                if decl then for k in pairs(decl) do dkeys[#dkeys + 1] = tostring(k) end end
                local live = d.dmTiles and d.dmTiles[t.id]
                print(("  tile#%d %s en=%s claim={%s} live=%s decl={%s} btns=%s"):format(
                    t.id, tostring(t.type), tostring(t.enabled ~= false),
                    table.concat(cats, ","), tostring(live ~= nil),
                    table.concat(dkeys, ","), Census(live)))
                if live then
                    local cs, csh = pcall(live.IsShown, live)
                    print(("    container shown=%s unit=%s lvl=%s"):format(
                        cs and tostring(csh) or "DENIED", tostring(live._dmUnit),
                        tostring(live:GetFrameLevel())))
                    local n = (live.GetNumChildren and live:GetNumChildren()) or 0
                    for ci = 1, n do
                        local ch = select(ci, live:GetChildren())
                        if ch then
                            local ok, sh = pcall(ch.IsShown, ch)
                            local ow, w = pcall(ch.GetWidth, ch)
                            local oh, h = pcall(ch.GetHeight, ch)
                            local dbg = fxDbg[ch]
                            -- Our own visual frames read fine even when the
                            -- engine button denies reads: IsShown=true with
                            -- IsVisible=false = a hidden ancestor (the slot
                            -- button itself).
                            local vis = ""
                            local ddt = dbg and dbg.dd
                            if ddt then
                                local function V(name, f)
                                    if f then
                                        local oks, shs = pcall(f.IsShown, f)
                                        local okv, vv = pcall(f.IsVisible, f)
                                        vis = vis .. (" %s=%s/%s"):format(name,
                                            oks and tostring(shs) or "?",
                                            okv and tostring(vv) or "?")
                                    end
                                end
                                V("glow", ddt.dmFxGlow); V("hc", ddt.dmFxHc)
                                V("bar", ddt.dmFxBar); V("sq", ddt.dmFxSq)
                            end
                            print(("    btn%d shown=%s size=%sx%s refs=%s fx=%s%s"):format(ci,
                                ok and tostring(sh) or "DENIED",
                                ow and ("%.0f"):format(w or 0) or "?",
                                oh and ("%.0f"):format(h or 0) or "?",
                                tostring(fxRefs[ch] ~= nil),
                                dbg and ("n=" .. tostring(dbg.n) .. " cat=" .. tostring(dbg.cat)
                                    .. " kind=" .. tostring(dbg.kind)
                                    .. " gate=" .. tostring(dbg.gate)
                                    .. " ok=" .. tostring(dbg.ok)
                                    .. (dbg.err and (" err=" .. dbg.err) or ""))
                                    or "never-ran", vis))
                        end
                    end
                end
            end
        end
        if dm2.fxList then
            for i = 1, #dm2.fxList do
                local e = dm2.fxList[i]
                local cats = {}
                for c, on in pairs(e.filters or {}) do if on then cats[#cats + 1] = c end end
                print(("  fxblock#%d {%s} glow=%s bdr=%s active=%s"):format(i,
                    table.concat(cats, ","), tostring(e.glowType), tostring(e.borderSize),
                    tostring(FxEntryActive(e) and true or false)))
            end
        end
        local pend = d.dmTilePend
        if pend then
            local pk = {}
            for k in pairs(pend) do pk[#pk + 1] = tostring(k) end
            if #pk > 0 then print("  pending: " .. table.concat(pk, ",")) end
        end
        return
    elseif cmd == "all" or cmd == "boss" or cmd == "role"
        or cmd == "priority" or cmd == "cc" or cmd == "raid"
        or cmd == "raidcombat" or cmd == "dispel" then
        if cmd == "all" or cmd == "cc" then
            dm[cmd] = dm[cmd] == false -- default-ON keys: nil reads as on
        else
            dm[cmd] = not dm[cmd]
        end
        print("|cff0cd2a0EUI|r DM " .. cmd .. ": " .. (dm[cmd] and "ON" or "OFF"))
    else
        print("|cff0cd2a0EUI|r usage: /euidm [all|boss|role|priority|cc|raid|raidcombat|dispel|status|dump|debug]")
        return
    end
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end


