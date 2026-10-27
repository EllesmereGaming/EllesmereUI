if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Bars.lua
--
--  The default Buffs and Debuffs bars: their state, the restricted-apply
--  deferral, growth and position, CreateBars, the unlock registration,
--  RestyleBars and ApplyLiveConfig.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local BuffBarChain, PAB, PabSnap = I.BuffBarChain, I.PAB, I.PabSnap
local BuffCandidateExtras, BuildStyle = I.BuffCandidateExtras, I.BuildStyle
local DebuffCandidateExtras = I.DebuffCandidateExtras
local ResolveSortDirection, ResolveSortMethod = I.ResolveSortDirection, I.ResolveSortMethod
local STYLE_BUFFS, STYLE_DEBUFFS = I.STYLE_BUFFS, I.STYLE_DEBUFFS
local ApplyGroupConfig, BuildGroupLayout = I.ApplyGroupConfig, I.BuildGroupLayout
local DebuffChainFor, MergeCandidateFilters = I.DebuffChainFor, I.MergeCandidateFilters
local RetireContainer, ComputeGrid = I.RetireContainer, I.ComputeGrid
local DefaultBuffsCfg, DefaultDebuffsCfg = I.DefaultBuffsCfg, I.DefaultDebuffsCfg
local EnsureBarEnable, EnsureDebuffFilterV2 = I.EnsureBarEnable, I.EnsureDebuffFilterV2
local EnsureExtDefCustomBar, EnsureFilterLanes = I.EnsureExtDefCustomBar, I.EnsureFilterLanes
local SeedDefaultBuffsDebuffsFromLegacySources = I.SeedDefaultBuffsDebuffsFromLegacySources
local SetAK, SetBuffsParent, SetDebuffsParent = I.SetAK, I.SetBuffsParent, I.SetDebuffsParent
local SetBuffsSlotSig, SetBuffsContainer = I.SetBuffsSlotSig, I.SetBuffsContainer
local SetDebuffsContainer = I.SetDebuffsContainer

local AK -- EllesmereUI.AuraKit, resolved at first use (see SetAK)
I.AKSetters[#I.AKSetters + 1] = function(v) AK = v end

local buffsContainer, debuffsContainer
I.buffsContainerSetters[#I.buffsContainerSetters + 1] = function(v) buffsContainer = v end
I.debuffsContainerSetters[#I.debuffsContainerSetters + 1] = function(v) debuffsContainer = v end
local buffsParent, debuffsParent
I.buffsParentSetters[#I.buffsParentSetters + 1] = function(v) buffsParent = v end
I.debuffsParentSetters[#I.debuffsParentSetters + 1] = function(v) debuffsParent = v end
-- Per-container, per-polarity registry of every group key ever declared (see
-- ApplyGroupConfig): reset only when a container is (re-)created, never on a live
-- settings change.
local declared = { buffs = {}, debuffs = {} } -- buffs: only the "Show All Buffs" catch-all key ("all"); debuffs: every class-token chain key
local lastSize = { buffs = nil, debuffs = nil } -- {w=,h=} last-applied grid size, for fixed-edge compensation (see ApplyLiveConfig)
local buffsSlotSig -- signature of the default Buffs bar's last-applied resolved spell list (ns.PAB_ResolveSpells), mirrors customBuffSig[barId] for the per-bar slots model
I.buffsSlotSigSetters[#I.buffsSlotSigSetters + 1] = function(v) buffsSlotSig = v end
local RegisterPABUnlock -- forward-declared; defined after CreateBars, called from it
local SyncCancelCVar -- forward-declared; defined after RestyleBars, called from CreateBars/RestyleBars/ReloadCustomBuffBarImpl
local pabSuppressed = false -- vehicle ride OR degraded-filter window: SetParentShownSafe dims the parents instead of hiding them (see ApplyVehicleHidden)
I.pabSuppressedSetters[#I.pabSuppressedSetters + 1] = function(v) pabSuppressed = v end
-- Last label the Buffs mover was registered under, so ApplyLiveConfig can
-- re-register on a name change without doing it on every slider drag.
local lastUnlockBuffLabel
local ReloadAllCustomBars -- forward-declared; assigned by EUI_PlayerAuraBars_CustomBars.lua (SetReloadAllCustomBars), called from CreateBars
I.reloadAllSetters[#I.reloadAllSetters + 1] = function(v) ReloadAllCustomBars = v end
local PAB_MaybeRefreshPreview -- forward-declared; assigned by EUI_PlayerAuraBars_Preview.lua (SetMaybeRefreshPreview), called from every live-apply function so an open bar-detail preview box tracks slider drags without those functions knowing it exists
I.previewRefreshSetters[#I.previewRefreshSetters + 1] = function(v) PAB_MaybeRefreshPreview = v end

-- Last-applied growDirection per live container (weak keys); written by
-- ApplyContainerAnchorAndGrowth, read by the restricted-apply gate below.
local containerDirections = setmetatable({}, { __mode = "k" })

local restrictedApplies = {}
local restrictionHooked = false
-- Defers ONLY the direction-change reconfigure (Hide/SetUnit/UpdateAllAuras +
-- resize) to the restriction lift. Ordinary container-level re-drives are
-- restriction-legal (they ran mid-combat for weeks pre-centered-growth), and
-- the cinematic/faction/vehicle recovery lane DEPENDS on them running inside
-- instanced combat -- a blanket defer would leave restored bars showing
-- degraded content until the combat edge.
local function DeferRestrictedApply(key, fn, container, dir)
    local applied = container and containerDirections[container]
    if not (applied and applied ~= (dir or "LEFT")) then return false end
    if not AK then SetAK(EllesmereUI and EllesmereUI.AuraKit) end
    if not (AK and AK.AurasRestricted and AK.AurasRestricted()) then return false end
    restrictedApplies[key] = fn
    if not restrictionHooked then
        restrictionHooked = true
        AK.OnRestrictionLift(function()
            if not next(restrictedApplies) then return end
            local pending = restrictedApplies
            restrictedApplies = {}
            for _, apply in pairs(pending) do apply() end
        end)
    end
    return true
end

-- One-shot OOC reconciler for parent-geometry passes skipped inside lockdown. Every
-- bar parent has the engine aura container ANCHORED to it, which makes the PARENT's
-- own SetSize/ClearAllPoints/SetPoint ADDON_ACTION_BLOCKED in combat (a protected
-- anchor-dependent poisons its anchor ancestor's geometry) -- while the cinematic/
-- faction/vehicle recovery lane legitimately re-drives config mid-combat. Keyed and
-- coalesced through the addon's shared ns.CombatQueue.
local function QueuePABRegenApply(key, fn)
    ns.CombatQueue.Defer("PAB:" .. key, fn)
end

-- Combat-safe Show/Hide for a bar PARENT. The engine aura container is a
-- CHILD of the parent, so the parent's own Show/Hide is ADDON_ACTION_BLOCKED
-- in lockdown exactly like its SetSize/SetPoint (field report: the
-- cinematic/faction recovery lane re-asserting the default bars mid-combat).
-- No call at all when the state already matches; in combat the visual verdict
-- lands through alpha (never protected) and the real Show/Hide is replayed at
-- regen via `recompute`, which re-derives the verdict at that time.
-- Suppression (pabSuppressed) rides on alpha OUT of combat too, never on the
-- shown state: it lifts on transitions that routinely land mid-combat, and a
-- real Hide taken while suppressed cannot be undone until the next regen edge.
-- Field report (Kings' Rest, Entomb): the tomb is a vehicle and being inside it
-- drops the player's combat, so the ride's hide replayed for real at that regen
-- and the exit's show was blocked -- the bars stayed gone for the whole boss
-- pulled afterwards.
local function SetParentShownSafe(key, parent, want, recompute)
    want = want and true or false
    local locked = InCombatLockdown()
    local shown = parent:IsShown()
    if issecretvalue and issecretvalue(shown) then shown = nil end
    local alpha = (pabSuppressed or (locked and not want)) and 0 or 1
    if parent:GetAlpha() ~= alpha then parent:SetAlpha(alpha) end
    if shown == want then return end
    if locked then
        QueuePABRegenApply("shown:" .. key, recompute)
        return
    end
    parent:SetShown(want)
end

-- Default-bar enable toggle (cfg.enabled, nil = enabled): the parent hides
-- exactly like a disabled custom bar's. Vehicle suppression still wins while
-- active -- SetParentShownSafe keeps it on alpha, so this pass carries the
-- enable verdict without un-suppressing anything (a bar built mid-ride used to
-- come up at full alpha here).
local function ApplyDefaultBarShown(isBuff)
    local s = PAB()
    if not s then return end
    local parent
    if isBuff then parent = buffsParent else parent = debuffsParent end
    if not parent then return end
    local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
    -- Master enable + Use Blizzard Buffs both stand the defaults down (the
    -- recovery lane can reach this while disabled-awaiting-reload).
    SetParentShownSafe(isBuff and "default-buffs" or "default-debuffs", parent,
        s.enabled == true and cfg.enabled ~= false and s.useBlizzardBuffs ~= true,
        function() ApplyDefaultBarShown(isBuff) end)
end

-- Grow direction. AK.ApplyContainerLayout only applies growth when BOTH growthH and
-- growthV are set. Values are AnchorUtil.FlowDirection members, NOT strings
-- (Blizzard_SharedXMLBase/AnchorUtil.lua: Left=-1, Right=1, Up=1, Down=-1); our
-- settings store uppercase direction strings, matching EUI_UnlockMode.lua's dropdown
-- `val` convention.
--
-- CRITICAL: AnchorUtil.ApplyFlowLayout positions every element via
-- `layout:GetAnchorPoint()` (layout.anchorPoint, a THIRD independent field defaulting
-- to "TOPLEFT"), NOT our outer spec.point. Elements are placed relative to that
-- internal anchor with offsets increasing in the growthH direction, so leaving
-- anchorPoint at default while growthH changes puts the first icon on the wrong side
-- and lets icons drift outside the mover box. Derive ONE corner from the direction and
-- use it for BOTH the outer frame anchor and the internal flow anchorPoint, so the
-- fixed corner and the flow's start corner are the same physical point:
--   growDirection RIGHT -> fixed/start corner TOPLEFT (icons extend right)
--   growDirection LEFT  -> fixed/start corner TOPRIGHT (icons extend left)
--
-- Vertical growth (Up/Down): the flow's PRIMARY axis becomes vertical (icons fill
-- up/down first) and growthH instead carries the CROSS axis -- which side additional
-- columns wrap to, from cfg.iconWrapDirection ("LEFT"/"RIGHT", default LEFT). Mirrors
-- EUI_RaidFrames_AuraContainers.lua's AnchorDebuffContainer (grow==UP/DOWN: gH = wrap,
-- gV = grow), except PAB has no separate wrap dropdown. Horizontal growth keeps
-- growthH as the primary axis and growthV hardcoded Down (rows wrap downward).
local function ToGrowthH(dirStr, wrapStr)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if dirStr == "CENTER_VERTICAL" then return FlowDir.Right end
    if dirStr == "UP" or dirStr == "DOWN" then
        return wrapStr == "RIGHT" and FlowDir.Right or FlowDir.Left
    end
    return (dirStr == "RIGHT" or dirStr == "CENTER_HORIZONTAL") and FlowDir.Right or FlowDir.Left
end
-- Gated on the GROWTH direction, never on the wrap value itself (same shape as
-- ToGrowthH above). iconWrapDirection is one shared field whose Up/Down values are
-- only offered for LEFT/RIGHT growth, so a value left behind by a growth-direction
-- change must stay inert everywhere else: reading it unconditionally flipped
-- CENTER_VERTICAL's columns to grow Up out of its fixed "TOP" anchor, and stacked
-- CENTER_HORIZONTAL's rows upward, from a setting whose cog those modes never show.
local function ToGrowthV(dirStr, wrapStr)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if dirStr == "UP" then return FlowDir.Up end
    if dirStr == "DOWN" then return FlowDir.Down end
    if dirStr == "LEFT" or dirStr == "RIGHT" then
        return wrapStr == "UP" and FlowDir.Up or FlowDir.Down
    end
    return FlowDir.Down -- centered growth: rows always wrap downward
end
-- Corner = the flow's fixed start point = (opposite of growthV side) + (opposite of
-- growthH side), same rule horizontal or vertical (LEFT/RIGHT: growthV is always Down
-- -> TOP component; growthH Right/Left -> LEFT/RIGHT component).
local function CornerFor(dirStr, wrapStr)
    if dirStr == "CENTER_VERTICAL" then return "TOP" end
    if dirStr == "UP" or dirStr == "DOWN" then
        local vSide = (dirStr == "UP") and "BOTTOM" or "TOP"
        local hSide = (wrapStr == "RIGHT") and "LEFT" or "RIGHT"
        return vSide .. hSide
    end
    if dirStr == "LEFT" or dirStr == "RIGHT" then
        local vSide = (wrapStr == "UP") and "BOTTOM" or "TOP"
        local hSide = (dirStr == "RIGHT") and "LEFT" or "RIGHT"
        return vSide .. hSide
    end
    return (dirStr == "CENTER_HORIZONTAL") and "TOPLEFT" or "TOPRIGHT"
end

-- Shared by every container, default and custom alike: builds the AK.RequestContainer
-- spec's point+layout from a bar cfg's growDirection and a precomputed grid
-- (ComputeGrid), so default and custom bars can never drift in how they read
-- growDirection/rowWidth. Also returns the corner (callers need it for the
-- container's own SetPoint against its parent) and `vertical` (AK.SetContainerAxis is
-- a separate call from AK.ApplyContainerLayout -- axis is not part of the layout table).
local function BuildContainerSpec(parent, cfg, grid)
    local dir = cfg.growDirection or "LEFT"
    local wrap = cfg.iconWrapDirection or "LEFT"
    local vertical = (dir == "UP" or dir == "DOWN" or dir == "CENTER_VERTICAL")
    local layoutAnchor = dir == "CENTER_HORIZONTAL" and "LEFT" or CornerFor(dir, wrap)
    local containerAnchor = (dir == "CENTER_HORIZONTAL" or dir == "CENTER_VERTICAL") and "CENTER" or layoutAnchor
    return containerAnchor, {
        point = { containerAnchor, parent, containerAnchor, 0, 0 },
        layout = {
            anchorPoint = layoutAnchor,
            padding = { 0, 0, 0, 0 },
            rowWidth = grid.rowWidth,
            growthH = ToGrowthH(dir, wrap),
            growthV = ToGrowthV(dir, wrap),
        },
    }, vertical
end

-- Re-applies container anchor/axis/growth/padding/rowWidth for an already-created
-- container against `parent`'s current grid. Shared by ApplyLiveConfig and the
-- existing-container branches of ReloadCustomBuffBarImpl/ReloadCustomDebuffBarImpl so
-- the three cannot drift. The outer frame anchor is a plain SetPoint (not AK-managed),
-- so it is live-settable like any other frame anchor.
local function ApplyContainerAnchorAndGrowth(container, parent, cfg, grid)
    local containerAnchor, spec, vertical = BuildContainerSpec(parent, cfg, grid)
    local direction = cfg.growDirection or "LEFT"
    local directionChanged = containerDirections[container] and containerDirections[container] ~= direction
    containerDirections[container] = direction
    if directionChanged then container:Hide() end

    local size = PabSnap(cfg.iconSize or 32)
    container:ClearAllPoints()
    container:SetSize(size, size)
    container:SetPoint(containerAnchor, parent, containerAnchor, 0, 0)
    AK.SetContainerAnchor(container, spec.layout.anchorPoint)
    AK.SetContainerAxis(container, vertical)
    if spec.layout.growthH then
        AK.SetContainerGrowth(container, spec.layout.growthH, spec.layout.growthV)
    end
    AK.SetContainerPadding(container, 0, 0, 0, 0)
    AK.SetContainerRowWidth(container, grid.rowWidth)

    if directionChanged then
        container:SetUnit("player")
        container:UpdateAllAuras()
        container:Show()
    end
end

-- Default anchor when no saved position exists yet. Independent per bar (bars must be
-- individually movable): the two just get separate default offsets so they don't
-- overlap before either has been dragged.
local DEFAULT_POS = {
    buffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -200 },
    debuffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -260 },
}

local function BarPositionKey(isBuff)
    return isBuff and "buffsPos" or "debuffsPos"
end

-- Snaps a saved (x, y) to the physical pixel grid before SetPoint, matching
-- EUI_UnitFrames_Layout.lua's ApplyFramePosition. An unsnapped coordinate is only
-- wrong at a non-pixel-perfect UIParent scale (1 coord unit == 1 physical pixel at
-- PP.PixelBestSize()). CENTER/CENTER anchors need SnapCenterForDim -- its odd-
-- dimension handling keeps both edges on whole pixels, while plain SnapForES would
-- round the center itself and push edges onto half pixels; every other anchor point
-- uses SnapForES.
local function SnapBarPos(frame, point, relPoint, x, y, w, h)
    if not (x and y) then return x, y end
    local PP = EllesmereUI.PP
    local es = frame:GetEffectiveScale()
    local isCenterAnchor = (point == "CENTER" or point == nil)
        and (relPoint == "CENTER" or relPoint == nil)
    -- w/h replace the frame's own size when given (legacy positions, BarAnchorOffset).
    if isCenterAnchor then
        return PP.SnapCenterForDim(x, w or frame:GetWidth() or 0, es),
            PP.SnapCenterForDim(y, h or frame:GetHeight() or 0, es)
    end
    return PP.SnapForES(x, es), PP.SnapForES(y, es)
end

-- Pixel-rounding compensation. A stored position places a reference frame (see
-- BarAnchorOffset); the live frame is the snapped grid, slightly larger or smaller.
-- Returns the SetPoint offset that keeps the growth origin (the parent corner the
-- container is pinned to, the center for centered growth) where the reference frame
-- puts it, for a frame anchored at `point`. dw/dh are (reference - snapped) at apply
-- time; ApplyLiveConfig also passes a reference size change to move a stored center
-- with its origin.
local OriginShift
do
    local FRAC_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5,
        BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
    local FRAC_Y = { BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0, LEFT = 0.5, CENTER = 0.5,
        RIGHT = 0.5, TOPLEFT = 1, TOP = 1, TOPRIGHT = 1 }
    function OriginShift(cfg, point, dw, dh)
        local dir = cfg.growDirection or "LEFT"
        local origin = (dir == "CENTER_HORIZONTAL" or dir == "CENTER_VERTICAL") and "CENTER"
            or CornerFor(dir, cfg.iconWrapDirection or "LEFT")
        point = point or "CENTER"
        return (FRAC_X[origin] - (FRAC_X[point] or 0.5)) * dw,
            (FRAC_Y[origin] - (FRAC_Y[point] or 0.5)) * dh
    end
end

-- Pre-snap SetPoint offsets for a stored bar position. A position saved by an
-- unlock-mode move since the rounding fix (pos.design) refers to the design frame.
-- Any other position, defaults included, keeps the placement it had before the fix:
-- its growth origin stays where the truncated legacy frame, snapped as before, put
-- it at this resolution, until the bar is moved.
local function BarAnchorOffset(frame, cfg, grid, pos)
    local x, y = pos.x, pos.y
    if not (x and y) then return x, y end
    local rw, rh = grid.designWidth, grid.designHeight
    if not pos.design then
        rw, rh = grid.legacyWidth, grid.legacyHeight
        x, y = SnapBarPos(frame or UIParent, pos.point, pos.relPoint or pos.point, x, y, rw, rh)
    end
    local dx, dy = OriginShift(cfg, pos.point, rw - grid.width, rh - grid.height)
    return x + dx, y + dy
end

-- Unlock-mode savePos: x/y is the VISUAL position the mover hands over, `cur` the
-- stored one. An unchanged position (a discard or an untouched commit writes back
-- what loadPos returned) keeps `cur` as it is, so a legacy position only converts
-- on a real move. Anything else is stored as a design position.
local function MoverStorePos(frame, cfg, grid, cur, point, relPoint, x, y)
    relPoint = relPoint or point
    if not (x and y) then return { point = point, relPoint = relPoint, x = x, y = y } end
    if cur and cur.point == point and (cur.relPoint or cur.point) == relPoint then
        local cx, cy = BarAnchorOffset(frame, cfg, grid, cur)
        if cx and cy and math.abs(x - cx) < 0.001 and math.abs(y - cy) < 0.001 then return cur end
    end
    local dx, dy = OriginShift(cfg, point, grid.designWidth - grid.width, grid.designHeight - grid.height)
    return { point = point, relPoint = relPoint, x = x - dx, y = y - dy, design = true }
end

-- Centered growth needs a position whose meaning does not change with the mover's
-- configured grid size. Rebase any edge-anchored saved position to CENTER/CENTER at
-- the frame's current visual center before resizing it.
local function RebaseBarPositionToCenter(frame, pos)
    if pos and pos.point == "CENTER" and (pos.relPoint or pos.point) == "CENTER" then return pos end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return pos end
    local x, y = cx - ux, cy - uy
    local sx, sy = SnapBarPos(frame, "CENTER", "CENTER", x, y)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
    -- design: centered growth has no rounding shift at CENTER, so the measured
    -- center already is the design center (BarAnchorOffset).
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y, design = true }
end

-- Applies the saved position (if any) or the default to the given parent frame.
-- Shared between initial creation and the unlock-mode applyPos callback so the two
-- never drift into different SetPoint logic. `grid` is optional (computed when nil).
-- An unlock-anchored bar belongs to the anchor: the stored position is only a
-- snapshot of where the anchor put it at the last Save & Exit, stale once the
-- target moves (a player frame riding a CDM whose width varies per spec or
-- character), and nothing re-anchors a fixed-size bar afterwards. The stored
-- position still seeds a parent with no point yet; the anchor then places it.
local function ApplyBarPosition(parent, isBuff, grid)
    local unlockKey = isBuff and "PAB_Buffs" or "PAB_Debuffs"
    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
    if anchored and parent:GetNumPoints() > 0 and EllesmereUI.ReapplyOwnAnchor then
        EllesmereUI.ReapplyOwnAnchor(unlockKey)
        return
    end
    local s = PAB()
    local posKey = BarPositionKey(isBuff)
    local pos = s and s[posKey]
    local def = isBuff and DEFAULT_POS.buffs or DEFAULT_POS.debuffs
    local cfg = s and (isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s))
    local p = (pos and pos.point) and pos or def
    local x, y = p.x, p.y
    if cfg then x, y = BarAnchorOffset(parent, cfg, grid or ComputeGrid(isBuff, cfg), p) end
    parent:ClearAllPoints()
    x, y = SnapBarPos(parent, p.point, p.relPoint or p.point, x, y)
    parent:SetPoint(p.point, UIParent, p.relPoint or p.point, x, y)
    if cfg and (cfg.growDirection == "CENTER_HORIZONTAL" or cfg.growDirection == "CENTER_VERTICAL") then
        s[posKey] = RebaseBarPositionToCenter(parent, pos)
    end
    if anchored and EllesmereUI.ReapplyOwnAnchor then EllesmereUI.ReapplyOwnAnchor(unlockKey) end
end

-- Blizzard's player BuffFrame/DebuffFrame are superseded by this module: hide them so
-- auras aren't shown twice. House pattern for "Blizzard keeps re-showing this": Hide()
-- once, then hooksecurefunc(Show) to immediately re-hide whenever Blizzard's code calls
-- Show() again. hooksecurefunc runs AFTER Blizzard's secure call completes, not from
-- inside it, so nothing is tainted. Neither frame is protected/secure, so plain Hide()
-- is safe with no lockdown concern.
local blizzardAurasHidden = false
-- True while PAB owns the buff/debuff display (the natives must stay
-- hidden): master-enabled and not in Use Blizzard Buffs mode. The re-hide
-- hooks below read this LIVE, so Disable All and Use Blizzard Buffs can
-- hand the display back without a reload.
local function PabOwnsNativeAuras()
    local s = PAB()
    return (s and s.enabled == true and s.useBlizzardBuffs ~= true) and true or false
end

local function HideBlizzardPlayerAuras()
    if blizzardAurasHidden then return end
    blizzardAurasHidden = true
    if BuffFrame then
        BuffFrame:Hide()
        hooksecurefunc(BuffFrame, "Show", function()
            if PabOwnsNativeAuras() then BuffFrame:Hide() end
        end)
    end
    if DebuffFrame then
        DebuffFrame:Hide()
        hooksecurefunc(DebuffFrame, "Show", function()
            if PabOwnsNativeAuras() then DebuffFrame:Hide() end
        end)
    end
end

-- Hands the native display back mid-session (Disable All / Use Blizzard
-- Buffs ON): the hooks above release once PabOwnsNativeAuras() is false, so
-- an explicit Show restores Blizzard's frames without a reload. No-op if
-- the natives were never hidden this session.
local function ShowBlizzardPlayerAuras()
    if not blizzardAurasHidden then return end
    if PabOwnsNativeAuras() then return end
    if BuffFrame then BuffFrame:Show() end
    if DebuffFrame then DebuffFrame:Show() end
end

-- Re-asserts native visibility for the CURRENT profile/mode (profile swaps
-- cross enable/useBlizzard modes in both directions): hide when PAB owns
-- the display -- the first hide installs the hooks, later ones re-assert
-- past the latch -- show when it does not.
local function SyncNativeAuras()
    if PabOwnsNativeAuras() then
        if blizzardAurasHidden then
            if BuffFrame then BuffFrame:Hide() end
            if DebuffFrame then DebuffFrame:Hide() end
        else
            HideBlizzardPlayerAuras()
        end
    else
        ShowBlizzardPlayerAuras()
    end
end

-- Weapon enchants are not auras, so only the engine's own item-enchantment
-- source renders them (see AK.AddItemEnchantmentsToContainer): a LEADING
-- layout group on the Buffs container, flowed ahead of the aura run in every
-- grow direction and in combat. They ride the bar's broad-content modes
-- (ns.PAB_EnchantsOn: All Buffs or Has Duration on the default Buffs bar),
-- with no opt-in of their own.
local function BuildEnchantSpec(cfg, pad, rowGap, maxSlots)
    local layout = BuildGroupLayout(cfg, pad, rowGap)
    local placement = CustomAuraContainerItemEnchantmentPlacement
    if placement then layout.placement = placement.BeforeAuraGroups end
    local sortMethods = AuraContainerItemEnchantmentSortMethod
    local sortDirs = AuraContainerSortDirection
    return {
        style = STYLE_BUFFS,
        -- Marks the cell as a weapon enchant for the style pass (Blizzard
        -- Style draws the stock temp-enchant ring on those only).
        extraInit = AK.EnchantCellInit,
        layout = layout,
        hidePermanent = true,
        maxSlots = maxSlots,
        -- REVERSE keeps MAIN HAND adjacent to the aura run: the engine puts
        -- the group's first element at the leading edge, and Slot order is
        -- main hand, off hand, ranged.
        sortMethod = sortMethods and sortMethods.Slot,
        sortDirection = sortDirs and sortDirs.Reverse,
    }
end

-- Declares them on `container` (idempotent) and re-applies their layout, so
-- a live padding/icon-size change follows. Turning the row OFF is served by
-- the content signature below instead: the engine has no addon-facing
-- unregister, so the container has to be rebuilt for that.
-- Wrapped in do...end so only the two helpers used below stay chunk-level
-- locals.
local BuffAuraMax, SyncEnchantEvents
do
    -- Inventory slots behind AuraContainerItemEnchantmentSlot, in the same order.
    local ENCH_INV_SLOTS = { INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17, INVSLOT_RANGED or 18 }

    -- Weapon enchants showing right now. Only duration-bearing ones render
    -- (hidePermanent in BuildEnchantSpec), so an empty or permanently enchanted
    -- slot costs nothing. Equipment state, not aura data: these returns carry no
    -- secret flags, in restricted combat either.
    local function ActiveEnchantCount(slots)
        local api = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
        if not api then return 0 end
        local n = 0
        for i = 1, math.min(slots or 0, #ENCH_INV_SLOTS) do
            local info = api(ENCH_INV_SLOTS[i])
            if info and info.hasExpirationTime then n = n + 1 end
        end
        return n
    end

    -- Aura cap for the Buffs bar: "Max Icons" is the whole bar's budget, so the
    -- cells actually showing come off it and the rendered total stays at the
    -- configured number. Nothing is reserved for a slot that is not enchanted.
    function BuffAuraMax(grid)
        local slots = grid.enchSlots or 0
        if slots <= 0 then return grid.effectiveMax end
        local n = ActiveEnchantCount(slots)
        -- WoW Forever: its imbue cells come off the budget too (nil elsewhere).
        if ns.PAB_FvImbueCount then n = n + ns.PAB_FvImbueCount() end
        return math.max(0, grid.effectiveMax - n)
    end

    -- The budget moves with the enchants, so an applied or expired oil re-applies
    -- it. Registered ONLY while the row is on, and the count is change-guarded:
    -- WEAPON_ENCHANT_CHANGED also fires for charge ticks, which leave the cell
    -- count alone.
    local enchEventFrame, lastEnchCount
    function SyncEnchantEvents(want)
        if want then
            if not enchEventFrame then
                enchEventFrame = CreateFrame("Frame")
                enchEventFrame:SetScript("OnEvent", function()
                    local n = ActiveEnchantCount(#ENCH_INV_SLOTS)
                    if n == lastEnchCount then return end
                    lastEnchCount = n
                    if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(true) end
                end)
            end
            lastEnchCount = ActiveEnchantCount(#ENCH_INV_SLOTS)
            enchEventFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
            enchEventFrame:RegisterEvent("WEAPON_SLOT_CHANGED")
        elseif enchEventFrame then
            enchEventFrame:UnregisterAllEvents()
            lastEnchCount = nil
        end
        -- WoW Forever: its imbue cells follow the row on and off (nil elsewhere).
        if ns.PAB_FvImbueSync then ns.PAB_FvImbueSync(want) end
    end
end

local function ApplyEnchants(container, cfg, pad, grid)
    local on = ns.PAB_EnchantsOn(cfg)
    SyncEnchantEvents(on)
    if not (on and container and grid) then return end
    if (grid.enchSlots or 0) <= 0 then return end
    AK.AddItemEnchantmentsToContainer(container,
        BuildEnchantSpec(cfg, pad, grid.rowGap, grid.enchSlots))
    -- WoW Forever: imbues are an enchant type the engine cells never see there,
    -- drawn by EUI_UnitFrames_ForeverImbues.lua (nil on every other client).
    if ns.PAB_FvImbueLayout then
        ns.PAB_FvImbueLayout(container, buffsParent, cfg, grid,
            BuildGroupLayout(cfg, pad, grid.rowGap), (BuildContainerSpec(buffsParent, cfg, grid)))
    end
end

-- Buffs content signature: the resolved spell set PLUS the number of declared
-- weapon-enchant slots. A group's candidateFilters are fixed at declaration
-- and an item enchantment cannot be undeclared at all, so a change in either
-- releases the container and builds a fresh one -- including a grid shrunk
-- below three cells, which declares fewer slots than before.
local function BuffsContentSig(cfg, spells, enchSlots)
    enchSlots = ns.PAB_EnchantsOn(cfg) and (enchSlots or 0) or 0
    return table.concat(spells, ",") .. (enchSlots > 0 and ("|e" .. enchSlots) or "")
end

local function CreateBars()
    if not AK then SetAK(EllesmereUI and EllesmereUI.AuraKit) end
    if not AK then return end -- 12.1 gated at file top; defensive only

    local s = PAB()
    if not s then return end -- ns.db not ready yet; SetupOptionsPanel calls back once it is

    -- Master enable, default OFF: nothing below runs while disabled -- Blizzard's
    -- BuffFrame/DebuffFrame stay untouched, no containers, no unlock elements, options
    -- page shows an activation overlay. One-shot seed: the retired Styled Player Auras
    -- module's enable toggle carries over, so its users come up enabled.
    if not s.pabEnableSeeded then
        s.pabEnableSeeded = true
        if s.enabled == nil then
            local old = ns.db and ns.db.profile and ns.db.profile.playerAuras
            if old and old.enabled == true then s.enabled = true end
        end
    end
    if s.enabled ~= true then return end

    -- Enablement is confirmed from here down: arm the cinematic/faction/
    -- vehicle recovery lane (EUI_PlayerAuraBars_Lifecycle.lua; every file has
    -- loaded by the time anything calls CreateBars). Idempotent.
    ns.PAB_ArmRecovery()

    -- Must run before DefaultBuffsCfg/DefaultDebuffsCfg are first called, so seeded
    -- values are what their first lazy-create populates. One-time-ever seed, not a
    -- re-appliable migration (see SeedDefaultBuffsDebuffsFromLegacySources).
    SeedDefaultBuffsDebuffsFromLegacySources(s)
    EnsureDebuffFilterV2(s)
    EnsureFilterLanes(s)
    EnsureBarEnable(s)

    -- Must run before buffCfg/custom-bar spell resolution below: the curated presets
    -- are otherwise only imported when the options page opens, so a bar referencing a
    -- not-yet-imported preset filter would resolve an incomplete spell set at login,
    -- cache it as its signature, and never re-resolve until something else forces a
    -- signature change.
    if ns.PAB_ImportBM2Filters then ns.PAB_ImportBM2Filters() end

    -- After the import: the External Defensives seed references the imported
    -- "Externals" preset filter by id.
    EnsureExtDefCustomBar(s)

    -- Use Blizzard Buffs: PAB stands down for the DEFAULT bars only --
    -- Blizzard's native BuffFrame/DebuffFrame stay untouched and the default
    -- bars never build; custom bars (editing-spec buckets included) still
    -- run in full. Default-bar unlock elements drop via their isHidden.
    if s.useBlizzardBuffs == true then
        RegisterPABUnlock()
        ReloadAllCustomBars()
        SyncCancelCVar()
        return
    end

    HideBlizzardPlayerAuras()

    local buffCfg, debuffCfg = DefaultBuffsCfg(s), DefaultDebuffsCfg(s)

    AK.styles[STYLE_BUFFS] = BuildStyle(true, buffCfg)
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, debuffCfg)

    local buffGrid = ComputeGrid(true, buffCfg)
    local debuffGrid = ComputeGrid(false, debuffCfg)

    if not buffsParent then SetBuffsParent(CreateFrame("Frame", "EllesmereUIPlayerAuraBars_Buffs", UIParent)) end
    buffsParent:SetSize(buffGrid.width, buffGrid.height)
    ApplyBarPosition(buffsParent, true, buffGrid)
    lastSize.buffs = { w = buffGrid.width, h = buffGrid.height, dw = buffGrid.designWidth,
        dh = buffGrid.designHeight, lw = buffGrid.legacyWidth, lh = buffGrid.legacyHeight,
        gd = buffCfg.growDirection, wd = buffCfg.iconWrapDirection }

    if not debuffsParent then SetDebuffsParent(CreateFrame("Frame", "EllesmereUIPlayerAuraBars_Debuffs", UIParent)) end
    debuffsParent:SetSize(debuffGrid.width, debuffGrid.height)
    ApplyBarPosition(debuffsParent, false, debuffGrid)
    lastSize.debuffs = { w = debuffGrid.width, h = debuffGrid.height, dw = debuffGrid.designWidth,
        dh = debuffGrid.designHeight, lw = debuffGrid.legacyWidth, lh = debuffGrid.legacyHeight,
        gd = debuffCfg.growDirection, wd = debuffCfg.iconWrapDirection }

    -- Enable toggles (cfg.enabled, nil = enabled): containers and groups still
    -- build below so a live re-enable needs no reload; a disabled bar just
    -- hides its parent (custom-bar pattern).
    ApplyDefaultBarShown(true)
    ApplyDefaultBarShown(false)

    local debuffChain = DebuffChainFor(debuffCfg)

    -- Single scalar padding, feeding ONLY ApplyGroupConfig's per-group
    -- elementSpacing/lineSpacing/groupSpacing/groupLineSpacing (gap BETWEEN icons).
    -- Must NOT also feed the container's outer edge inset (spec.layout.padding /
    -- AK.SetContainerPadding) -- a DIFFERENT concept (container frame edge to first
    -- icon); tying them pushes the whole grid away from its fixed corner as padding
    -- grows. Outer inset is fixed at 0.
    local buffPad = buffCfg.padding or 5
    local debuffPad = debuffCfg.padding or 5

    local _, buffSpec = BuildContainerSpec(buffsParent, buffCfg, buffGrid)
    local _, debuffSpec = BuildContainerSpec(debuffsParent, debuffCfg, debuffGrid)

    -- Groups are declared additively right after creation (not via spec.groups) so
    -- the same ApplyGroupConfig path handles both initial creation and every later
    -- live settings change.
    --
    -- Buffs: the Filters/Extra-Spells selection and the "Show All Buffs" catch-all
    -- coexist additively on the same container -- both are independent GROUPS,
    -- nothing in AK's model makes them mutually exclusive. The catch-all uses the same
    -- zero-classes-enabled chain as Debuffs' "all" group (just { base }); buffs have no
    -- per-class filtering UI, so it's all-or-nothing, gated only by showAllBuffs.
    -- Defaults ON, else an unconfigured bar shows nothing; ON matches Blizzard's
    -- player BuffFrame (HELPFUL, no category restriction).
    --
    -- The spell selection must be ONE GROUP whose candidateFilters.includeSpellIDs is
    -- the resolved spell-ID set (map shape {[id]=true}, every includeSpellIDs consumer
    -- in the codebase uses a map, never an array). NOT one AK.AddAuraSlot per spellID:
    -- AK's flow layout only positions GROUP content, never slot content -- slots must
    -- self-anchor via extraInit (both other AddAuraSlot consumers,
    -- EUI_RaidFrames_AuraContainers.lua and EUI_ResourceBars_EbonMight121.lua, manually
    -- SetPoint their button). With slots, buttons report shown=true at the right size
    -- but GetPoint(1) returns nil and nothing renders. PAB needs a flowing multi-icon
    -- grid of a DYNAMIC spell set, which slots can't do without reimplementing flow
    -- placement by hand. A group's candidateFilters is fixed at declaration, so a
    -- spell-list change still requires releasing and recreating the container -- hence
    -- the sig-diffing.
    local buffAllChain = BuffBarChain(buffCfg)
    local buffSpells = ns.PAB_ResolveSpells(buffCfg)
    SetBuffsSlotSig(BuffsContentSig(buffCfg, buffSpells, buffGrid.enchSlots))
    -- This runs more than once per session (master re-enable, Use Blizzard
    -- Buffs off, a profile swap whose content signature moved), and a container
    -- can never be destroyed: retire the previous pair first or the orphans stay
    -- shown on the same parent and every aura -- and every enchant cell -- renders
    -- twice.
    RetireContainer(buffsContainer, declared.buffs)
    RetireContainer(debuffsContainer, declared.debuffs)
    AK.RequestContainer(buffsParent, "player", buffSpec, function(container)
        SetBuffsContainer(container)
        ApplyContainerAnchorAndGrowth(container, buffsParent, buffCfg, buffGrid)
        ApplyEnchants(container, buffCfg, buffPad, buffGrid)
        declared.buffs = {}
        ApplyGroupConfig(container, buffAllChain, declared.buffs, STYLE_BUFFS, BuffAuraMax(buffGrid), buffPad, buffGrid.rowGap, buffCfg, BuffCandidateExtras(buffCfg))
        if #buffSpells > 0 then
            local includeMap = {}
            for i = 1, #buffSpells do includeMap[buffSpells[i]] = true end
            AK.AddGroupToContainer(container, {
                key = "spells",
                filter = { "HELPFUL" },
                style = STYLE_BUFFS,
                maxFrameCount = BuffAuraMax(buffGrid),
                candidateFilters = MergeCandidateFilters({ includeSpellIDs = includeMap }, BuffCandidateExtras(buffCfg)),
                sortMethod = ResolveSortMethod(buffCfg),
                sortDirection = ResolveSortDirection(buffCfg),
                layout = BuildGroupLayout(buffCfg, buffPad, buffGrid.rowGap),
            })
            declared.buffs.spells = true
        end
    end)
    AK.RequestContainer(debuffsParent, "player", debuffSpec, function(container)
        SetDebuffsContainer(container)
        ApplyContainerAnchorAndGrowth(container, debuffsParent, debuffCfg, debuffGrid)
        declared.debuffs = {}
        ApplyGroupConfig(container, debuffChain, declared.debuffs, STYLE_DEBUFFS, debuffGrid.effectiveMax, debuffPad, debuffGrid.rowGap, debuffCfg, DebuffCandidateExtras(debuffCfg))
    end)
    RegisterPABUnlock()
    ReloadAllCustomBars()
    SyncCancelCVar()
end

-- Unlock mode's cog menu only offers "Element Options" for keys in
-- EllesmereUI._ELEMENT_SETTINGS_MAP; a module adds its own dynamic keys there the
-- way EllesmereUIDataBars.lua does, so EUI_UnlockMode.lua's static map needs no
-- PAB branch. barId nil = one of the two built-in bars.
--
-- No sectionName/highlightText: NavigateToElementSettings scans the page
-- wrapper's DIRECT children for section headers, and PABMP_BuildPage builds past
-- `parent` into its own root on the shared scroll frame, so nothing is scannable.
local function MapElementSettings(key, kind, barId)
    if not EllesmereUI then return end
    EllesmereUI._ELEMENT_SETTINGS_MAP = EllesmereUI._ELEMENT_SETTINGS_MAP or {}
    EllesmereUI._ELEMENT_SETTINGS_MAP[key] = {
        module = "EllesmereUIUnitFrames",
        page = "Player Aura Bars",
        preSelectFn = function()
            if not EllesmereUI._setPABSelection then return end
            if not barId then
                EllesmereUI._setPABSelection(kind, "default")
                return
            end
            -- Owning bucket resolved at click time, not baked in at registration:
            -- the tile's "Add To" menu can move a bar to another editing-spec
            -- bucket long after its key was mapped.
            local bar, bucket
            if kind == "buff" then bar, bucket = ns.PAB_GetCustomBuffBar(barId)
            else bar, bucket = ns.PAB_GetCustomDebuffBar(barId) end
            if bar then EllesmereUI._setPABSelection(kind, barId, bucket) end
        end,
    }
end

-- Unlock-mode registration, patterned on Damage Meters' ns.RegisterDMUnlock
-- (EUI_DamageMeters_State.lua) and MakeSATimerUnlockElement (EUI_DamageMeters_Timer.lua)
-- (observed EUI.MakeUnlockElement field
-- usage, not a verified schema). Both bars use noResize (AuraKit sizes the container
-- from the active aura count, nothing to drag-resize) and noAnchorTarget (a
-- dynamically-resizing frame is a bad anchor target for other elements).
function RegisterPABUnlock()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement

    local function MakeBarElement(key, label, order, isBuff, getParent)
        return MK({
            key = key,
            label = label,
            group = "Player Aura Bars",
            order = order,
            noResize = true,
            noAnchorTarget = true,
            -- Enable toggle: a disabled default bar keeps no mover (custom-bar
            -- parity). Master-disabled and Use Blizzard Buffs stand the
            -- defaults down entirely, mover included.
            isHidden = function()
                local s = PAB()
                if not s or s.enabled ~= true or s.useBlizzardBuffs == true then return true end
                local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
                return cfg.enabled == false
            end,
            getFrame = function() return getParent() end,
            -- Deliberately NOT container:GetWidth()/GetHeight(): AuraContainer geometry
            -- is a Secret Value while tainted (throws in EUI_UnlockMode.lua comparing a
            -- secret baseW). noResize is set anyway, so only a public number for the
            -- mover's label is needed.
            getSize = function()
                local s = PAB()
                if not s then return 32, 32 end
                local grid = ComputeGrid(isBuff, isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s))
                return grid.width, grid.height
            end,
            -- The mover works in VISUAL positions (the snapped live frame): loadPos
            -- converts the stored one (BarAnchorOffset), savePos goes back through
            -- MoverStorePos, which leaves an unchanged position untouched.
            savePos = function(_, point, relPoint, x, y)
                local s = PAB()
                if not s then return end
                local posKey = BarPositionKey(isBuff)
                local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
                s[posKey] = MoverStorePos(getParent(), cfg, ComputeGrid(isBuff, cfg), s[posKey], point, relPoint, x, y)
            end,
            loadPos = function()
                local s = PAB()
                local pos = s and s[BarPositionKey(isBuff)]
                if not pos then return nil end
                local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
                local x, y = BarAnchorOffset(getParent(), cfg, ComputeGrid(isBuff, cfg), pos)
                return { point = pos.point, relPoint = pos.relPoint, x = x, y = y }
            end,
            -- Spec-override unlock layers bank and restore the STORED table through
            -- these, not the visual position loadPos returns: a layer harvested at
            -- one resolution stays valid at another and keeps the design flag.
            loadRawPosition = function()
                local s = PAB()
                local pos = s and s[BarPositionKey(isBuff)]
                if not pos then return nil end
                return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y,
                    design = pos.design }
            end,
            saveRawPosition = function(_, p)
                local s = PAB()
                if not (s and p and p.point) then return end
                s[BarPositionKey(isBuff)] = { point = p.point, relPoint = p.relPoint or p.point,
                    x = p.x, y = p.y, design = p.design }
            end,
            clearPos = function()
                local s = PAB()
                if s then s[BarPositionKey(isBuff)] = nil end
            end,
            applyPos = function()
                local parent = getParent()
                if parent then ApplyBarPosition(parent, isBuff) end
            end,
        })
    end

    -- Buffs mover carries the bar's display name (see ns.PAB_DefaultBuffsName).
    -- Baked in at registration -- EUI_UnlockMode.lua's GetBarLabel returns the
    -- stored string -- which is why ApplyLiveConfig re-registers when the name
    -- changes.
    local s = PAB()
    local buffLabel = ns.PAB_DefaultBuffsName(s and DefaultBuffsCfg(s) or nil)
    lastUnlockBuffLabel = buffLabel

    local elements = {
        MakeBarElement("PAB_Buffs", buffLabel, 700, true, function() return buffsParent end),
        MakeBarElement("PAB_Debuffs", "Debuffs", 701, false, function() return debuffsParent end),
    }
    MapElementSettings("PAB_Buffs", "buff")
    MapElementSettings("PAB_Debuffs", "debuff")
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")
    -- Registration alone only updates the element table; a mover already built
    -- this session keeps the label CreateMover baked into its FontString. No-op
    -- before the first unlock session, so it is safe on the CreateBars path too.
    if EllesmereUI.RefreshUnlockElementLabel then
        EllesmereUI.RefreshUnlockElementLabel("PAB_Buffs")
    end
end
-- Exported for the default-bar enable toggles: re-registering re-runs unlock
-- mode's Sync, which re-reads isHidden and drops a disabled bar's mover
-- mid-session instead of waiting for the next natural Sync.
ns.PAB_RegisterUnlock = function() RegisterPABUnlock() end

-- Public hook for the Options UI: rebuild both style tables and re-decorate every
-- existing button. Purely a re-skin -- does NOT touch groups, filters, container
-- layout, or parent frame size. Call for style-only fields (colors, fonts, border,
-- dispel colors, cooldown/stack text, icon zoom). iconSize also needs ApplyLiveConfig
-- for both polarities, since it affects grid geometry.
local function RestyleBars()
    local s = PAB()
    if not (AK and s) then return end
    AK.styles[STYLE_BUFFS] = BuildStyle(true, DefaultBuffsCfg(s))
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, DefaultDebuffsCfg(s))
    AK.RestyleSoon(STYLE_BUFFS)
    AK.RestyleSoon(STYLE_DEBUFFS)
    SyncCancelCVar()
end
ns.PAB_Restyle = RestyleBars

-- CursorFreelookStartDelta is the fraction of the screen the cursor must move before a
-- held mouse button counts as camera freelook instead of a click; Blizzard's own
-- shipped default is 0.001 (verified against the client's cvar list, not assumed). At
-- 0 -- the most aggressive setting, zero movement required -- ANY right-click on an
-- aura icon is claimed for freelook before the release reaches our button, silently
-- eating the "Right-Click to Cancel" click (field-reported 2026-08-12, twice
-- independently). Players land on 0 via third-party "camera feel" addons/macros (a
-- dedicated community addon, CursorDeltaFix, does exactly this:
-- SetCVar("CursorFreelookStartDelta", 0)) or a manual /console tweak, not from
-- anything EllesmereUI does.
--
-- Repair only, never a nudge above Blizzard's default: we only ever touch this CVar
-- when it is caught sitting at the pathological 0, restoring it to Blizzard's own
-- 0.001 -- never raised past that, and never touched at all if it's anywhere else
-- (including a deliberately-tuned non-zero, non-default value). Conditional on some
-- right-click-cancelable buff surface actually being live, so a player who never uses
-- the feature never has this CVar touched by EllesmereUI at all.
local CANCEL_CVAR = "CursorFreelookStartDelta"
local CANCEL_CVAR_BROKEN = 0
local CANCEL_CVAR_DEFAULT = "0.001"

--- True while some right-click-cancelable player buff display is live: the default
--- Buffs bar (rightClickCancel defaults ON), any enabled custom buff bar with its own
--- toggle ON, or the classic Unit Frames player-buffs display (EUI_UnitFrames_
--- AuraContainers.lua's cancelButtons is unconditional whenever unit=="player" and
--- isBuff, gated only on the element being shown at all).
local function AnyRightClickCancelActive(s)
    -- Use Blizzard Buffs: the NATIVE BuffFrame owns the display and its
    -- right-click cancel breaks on the same CVar -- always repair.
    if s.useBlizzardBuffs == true then return true end
    local dbc = DefaultBuffsCfg(s)
    if dbc.enabled ~= false and dbc.rightClickCancel ~= false then return true end
    local customBuffBars = s.customBuffBars
    if customBuffBars then
        for i = 1, #customBuffBars do
            local bar = customBuffBars[i]
            if bar.enabled ~= false and bar.rightClickCancel ~= false then return true end
        end
    end
    -- Editing-spec bucket buff bars count too (enable-toggle test only,
    -- matching the legacy loop: the CVar repair may run while the spec is
    -- mid-change, so err on the permissive side).
    if s.pabSpecBars then
        for _, b in pairs(s.pabSpecBars) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do
                    local bar = bl[i]
                    if bar.enabled ~= false and bar.rightClickCancel ~= false then return true end
                end
            end
        end
    end
    local db = ns.db
    local playerCfg = db and db.profile and db.profile.player
    if playerCfg and playerCfg.showBuffs ~= false then return true end
    return false
end

function SyncCancelCVar()
    local s = PAB()
    if not s or s.enabled ~= true then return end
    if not AnyRightClickCancelActive(s) then return end
    if InCombatLockdown() then return end
    if tonumber(GetCVar(CANCEL_CVAR)) == CANCEL_CVAR_BROKEN then
        -- A repair to Blizzard's default, which Uninstall EUI must not undo:
        -- plain SetCVar, not EllesmereUI.SetCVar.
        SetCVar(CANCEL_CVAR, CANCEL_CVAR_DEFAULT)
    end
end

-- Public hook for the Options UI: live counterpart to RestyleBars for everything
-- spec-level (class toggles, grid: iconsPerRow/maxRows/padding/maxBuffs-or-Debuffs,
-- grow direction). Applies to ONE polarity's container; callers touching a shared
-- field (iconSize) call it for both. No-op before the container exists
-- (SetupOptionsPanel calls CreateBars() once ns.db is ready).
local function ApplyLiveConfig(isBuff)
    local s = PAB()
    if not (AK and s) then return end
    if DeferRestrictedApply(isBuff and "default-buffs" or "default-debuffs",
        function() ApplyLiveConfig(isBuff) end,
        isBuff and buffsContainer or debuffsContainer,
        (isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)).growDirection) then return end
    local container = isBuff and buffsContainer or debuffsContainer
    local parent = isBuff and buffsParent or debuffsParent
    if not container or not parent then return end

    local cfg = isBuff and DefaultBuffsCfg(s) or DefaultDebuffsCfg(s)
    -- Enable toggle: a disabled bar hides its parent and skips every live
    -- apply below (geometry, enchant layout, group work) -- re-enabling runs
    -- the full pass. Same shape as the custom bars' early return. Use
    -- Blizzard Buffs and the MASTER disable stand the default bars down the
    -- same way. Weapon enchants ride the container, so they stand down with
    -- the bar's parent -- nothing extra to tear down here.
    ApplyDefaultBarShown(isBuff)
    if s.enabled ~= true or cfg.enabled == false or s.useBlizzardBuffs == true then
        if isBuff then SyncEnchantEvents(false) end
        return
    end
    local grid = ComputeGrid(isBuff, cfg)
    local sizeKey = isBuff and "buffs" or "debuffs"
    local prev = lastSize[sizeKey]

    -- Edge-growing containers use a fixed parent corner, so move a CENTER-saved parent
    -- by half the size delta to keep that corner fixed. Centered growth deliberately
    -- skips this: the parent center is its fixed anchor. Uses lastSize rather than live
    -- geometry so rapid slider updates cannot read a stale prior size.
    local posKey = BarPositionKey(isBuff)
    local pos = s[posKey]
    local centered = cfg.growDirection == "CENTER_HORIZONTAL" or cfg.growDirection == "CENTER_VERTICAL"
    -- The engine aura container anchored to `parent` makes the PARENT's own geometry
    -- protected in combat (anchor-ancestor rule): the SetSize/ClearAllPoints/SetPoint
    -- below are ADDON_ACTION_BLOCKED inside lockdown -- and the cinematic/faction/
    -- vehicle recovery lane runs this function in instanced combat BY DESIGN (see
    -- DeferRestrictedApply). A recovery re-drive carries an UNCHANGED grid, so
    -- skipping the geometry cluster drops nothing there; a genuinely changed grid
    -- (options edited mid-combat) or a still-pending centered rebase reconciles once
    -- at the regen edge. lastSize stays untouched on the skip so the deferred pass
    -- still sees the real last-applied size (the fixed-corner compensation needs it),
    -- and the stored pos is not mutated for a resize that never landed.
    if InCombatLockdown() then
        local sizeChanged = not (prev and prev.w == grid.width and prev.h == grid.height
            and prev.dw == grid.designWidth and prev.dh == grid.designHeight
            and prev.gd == cfg.growDirection and prev.wd == cfg.iconWrapDirection)
        local rebasePending = centered
            and not (pos and pos.point == "CENTER" and (pos.relPoint or pos.point) == "CENTER")
        if sizeChanged or rebasePending then
            QueuePABRegenApply(sizeKey, function() ApplyLiveConfig(isBuff) end)
        end
    else
        if centered then
            pos = RebaseBarPositionToCenter(parent, pos)
            s[posKey] = pos
        end
        local resized = not centered and prev
            and (prev.w ~= grid.width or prev.h ~= grid.height
                or prev.dw ~= grid.designWidth or prev.dh ~= grid.designHeight)
        if resized and pos and pos.point == "CENTER" then
            -- The stored center belongs to its reference frame (design or legacy, see
            -- BarAnchorOffset), so it moves by that frame's delta, toward whichever
            -- side the growth origin is on.
            local dx, dy
            if pos.design then
                dx, dy = OriginShift(cfg, pos.point, prev.dw - grid.designWidth, prev.dh - grid.designHeight)
            else
                dx, dy = OriginShift(cfg, pos.point, prev.lw - grid.legacyWidth, prev.lh - grid.legacyHeight)
            end
            pos.x = pos.x + dx
            pos.y = pos.y + dy
        end
        local turned = prev and (prev.gd ~= cfg.growDirection or prev.wd ~= cfg.iconWrapDirection)
        lastSize[sizeKey] = { w = grid.width, h = grid.height, dw = grid.designWidth,
            dh = grid.designHeight, lw = grid.legacyWidth, lh = grid.legacyHeight,
            gd = cfg.growDirection, wd = cfg.iconWrapDirection }
        parent:SetSize(grid.width, grid.height)
        -- Re-seated AFTER SetSize so SnapBarPos snaps against the new size and the
        -- rounding shift follows the new grid, or the new origin after a grow/wrap
        -- direction change. The STORED pos keeps the raw accumulation. Never for an
        -- unlock-anchored bar: the anchor owns its placement and re-applies itself on
        -- a size change.
        local anchored = EllesmereUI.IsUnlockAnchored
            and EllesmereUI.IsUnlockAnchored(isBuff and "PAB_Buffs" or "PAB_Debuffs")
        if (resized or turned) and not anchored then ApplyBarPosition(parent, isBuff, grid) end
    end

    local pad = cfg.padding or 5
    ApplyContainerAnchorAndGrowth(container, parent, cfg, grid)

    if isBuff then
        -- Unlock mode bakes the mover's label at registration, so a Filters
        -- change would leave the old name on it until the next CreateBars.
        -- Re-register only when the name actually changed -- this function runs
        -- on every slider drag.
        local label = ns.PAB_DefaultBuffsName(cfg)
        if label ~= lastUnlockBuffLabel and RegisterPABUnlock then
            RegisterPABUnlock()
        end
    end

    if isBuff then
        local spells = ns.PAB_ResolveSpells(cfg)
        local sig = BuffsContentSig(cfg, spells, grid.enchSlots)
        local allChain = BuffBarChain(cfg)
        if sig ~= buffsSlotSig then
            -- Safe to fully release+rebuild: the default Buffs container holds only the
            -- catch-all group + the spells group, nothing else shares it. The new
            -- container's anchor/growth/rowWidth come from `spec` below -- the live
            -- SetContainerAnchor/etc calls above ran against the OLD container and are
            -- harmless overhead. A group's candidateFilters is fixed at declaration, so a
            -- spell-list change requires this release+rebuild -- and so does the
            -- weapon-enchant row, which the engine cannot undeclare at all.
            RetireContainer(container, declared.buffs)
            local _, spec = BuildContainerSpec(parent, cfg, grid)
            AK.RequestContainer(parent, "player", spec, function(newContainer)
                SetBuffsContainer(newContainer)
                ApplyContainerAnchorAndGrowth(newContainer, parent, cfg, grid)
                ApplyEnchants(newContainer, cfg, pad, grid)
                declared.buffs = {}
                ApplyGroupConfig(newContainer, allChain, declared.buffs, STYLE_BUFFS, BuffAuraMax(grid), pad, grid.rowGap, cfg, BuffCandidateExtras(cfg))
                if #spells > 0 then
                    local includeMap = {}
                    for i = 1, #spells do includeMap[spells[i]] = true end
                    AK.AddGroupToContainer(newContainer, {
                        key = "spells",
                        filter = { "HELPFUL" },
                        style = STYLE_BUFFS,
                        maxFrameCount = BuffAuraMax(grid),
                        candidateFilters = MergeCandidateFilters({ includeSpellIDs = includeMap }, BuffCandidateExtras(cfg)),
                        sortMethod = ResolveSortMethod(cfg),
                        sortDirection = ResolveSortDirection(cfg),
                        layout = BuildGroupLayout(cfg, pad, grid.rowGap),
                    })
                    declared.buffs.spells = true
                end
            end)
            SetBuffsSlotSig(sig)
        else
            -- Spell list unchanged: only Show All Buffs and/or grid (icon size,
            -- padding, ...) may have changed. ApplyGroupConfig is idempotent and self-
            -- zeroes the catch-all when `allChain` is empty, so one call covers on and
            -- off. The spells group isn't part of that chain path, so its
            -- maxFrameCount/layout/sort are refreshed here directly.
            --
            -- The enchant layout rides this branch (not the pass above): on the
            -- rebuild path the container here is the one about to be retired,
            -- and declaring three engine frames on it would leak them.
            ApplyEnchants(container, cfg, pad, grid)
            ApplyGroupConfig(container, allChain, declared.buffs, STYLE_BUFFS, BuffAuraMax(grid), pad, grid.rowGap, cfg, BuffCandidateExtras(cfg))
            if declared.buffs.spells then
                EllesmereUI.AuraKit.SetGroupCap(container, "spells", BuffAuraMax(grid))
                container:SetAuraGroupLayout("spells", BuildGroupLayout(cfg, pad, grid.rowGap))
                local liveIncludeMap = {}
                for i = 1, #spells do liveIncludeMap[spells[i]] = true end
                container:SetAuraGroupCandidateFilters("spells",
                    MergeCandidateFilters({ includeSpellIDs = liveIncludeMap }, BuffCandidateExtras(cfg)))
                local sortMethod, sortDirection = ResolveSortMethod(cfg), ResolveSortDirection(cfg)
                if sortMethod ~= nil and sortDirection ~= nil then
                    container:SetAuraGroupSortMethod("spells", sortMethod, sortDirection)
                end
            end
        end
    else
        local chain = DebuffChainFor(cfg)
        ApplyGroupConfig(container, chain, declared.debuffs, STYLE_DEBUFFS, grid.effectiveMax, pad, grid.rowGap, cfg, DebuffCandidateExtras(cfg))
    end

    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview(isBuff and "buff" or "debuff", "default") end
end
ns.PAB_ApplyLiveConfig = ApplyLiveConfig
-- Bridge for EllesmereUF:GetGrowDirectionForBar/SetGrowDirectionForBar, kept here
-- rather than in EUI_UnitFrames_Lifecycle.lua so the settings-field names stay defined
-- in one place.
--
-- Also handles custom-bar keys ("PAB_CustomBuff_<id>"/"PAB_CustomDebuff_<id>", the
-- unlock-mode keys RegisterPABCustomUnlock registers in EUI_PlayerAuraBars_CustomBars.lua): EUI_UnlockMode.lua's Grow
-- dropdown dispatches here for ANY barKey prefixed "PAB_", so without these branches it
-- silently no-ops on custom bars. Calls ns.PAB_ReloadCustomBuffBar/DebuffBar rather than
-- BuildContainerSpec/SetContainerGrowth directly, since the spell/class signature is
-- unchanged and those already re-apply corner + growth cheaply.
function ns.PAB_GetGrowDirection(barKey)
    local s = PAB()
    if not s then return "LEFT" end
    if barKey == "PAB_Buffs" then return DefaultBuffsCfg(s).growDirection or "LEFT" end
    if barKey == "PAB_Debuffs" then return DefaultDebuffsCfg(s).growDirection or "LEFT" end
    local buffId = barKey:match("^PAB_CustomBuff_(%d+)$")
    if buffId then
        local bar = ns.PAB_GetCustomBuffBar(tonumber(buffId))
        return bar and (bar.growDirection or "LEFT") or "LEFT"
    end
    local debuffId = barKey:match("^PAB_CustomDebuff_(%d+)$")
    if debuffId then
        local bar = ns.PAB_GetCustomDebuffBar(tonumber(debuffId))
        return bar and (bar.growDirection or "LEFT") or "LEFT"
    end
    return "LEFT"
end

function ns.PAB_SetGrowDirection(barKey, dir)
    local s = PAB()
    if not s then return end
    if barKey == "PAB_Buffs" then
        DefaultBuffsCfg(s).growDirection = dir
        RestyleBars()
        ApplyLiveConfig(true)
        return
    elseif barKey == "PAB_Debuffs" then
        DefaultDebuffsCfg(s).growDirection = dir
        RestyleBars()
        ApplyLiveConfig(false)
        return
    end
    local buffId = barKey:match("^PAB_CustomBuff_(%d+)$")
    if buffId then
        local bar = ns.PAB_GetCustomBuffBar(tonumber(buffId))
        if bar then
            bar.growDirection = dir
            ns.PAB_ReloadCustomBuffBar(bar.id)
        end
        return
    end
    local debuffId = barKey:match("^PAB_CustomDebuff_(%d+)$")
    if debuffId then
        local bar = ns.PAB_GetCustomDebuffBar(tonumber(debuffId))
        if bar then
            bar.growDirection = dir
            ns.PAB_ReloadCustomDebuffBar(bar.id)
        end
        return
    end
end

I.ApplyContainerAnchorAndGrowth = ApplyContainerAnchorAndGrowth
I.ApplyDefaultBarShown, I.ApplyLiveConfig = ApplyDefaultBarShown, ApplyLiveConfig
I.BarAnchorOffset, I.BuffsContentSig = BarAnchorOffset, BuffsContentSig
I.BuildContainerSpec, I.CornerFor, I.CreateBars = BuildContainerSpec, CornerFor, CreateBars
I.DeferRestrictedApply, I.MapElementSettings = DeferRestrictedApply, MapElementSettings
I.MoverStorePos, I.QueuePABRegenApply = MoverStorePos, QueuePABRegenApply
I.RebaseBarPositionToCenter, I.RegisterPABUnlock = RebaseBarPositionToCenter, RegisterPABUnlock
I.SetParentShownSafe, I.ShowBlizzardPlayerAuras = SetParentShownSafe, ShowBlizzardPlayerAuras
I.SnapBarPos, I.SyncCancelCVar = SnapBarPos, SyncCancelCVar
I.SyncEnchantEvents, I.SyncNativeAuras = SyncEnchantEvents, SyncNativeAuras
I.broken = false
