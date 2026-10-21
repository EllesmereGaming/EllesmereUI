if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Config.lua
--
--  Grid sizing, the default bar configs, seeding and migration from the
--  legacy sources and the per-bar enable state.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local PAB, PAB_FxListView, PAB_FxSafeToForce = I.PAB, I.PAB_FxListView, I.PAB_FxSafeToForce
local PAB_FxWantsCategory, PabShapedSize = I.PAB_FxWantsCategory, I.PabShapedSize
local PabSnap, VisibleCandidateClasses = I.PabSnap, I.VisibleCandidateClasses
local VisibleTokenClasses = I.VisibleTokenClasses

-- Grid sizing. AK's flow layout only exposes a row WIDTH (pixels) to wrap on, no
-- native "max lines" cap, so a row cap is enforced indirectly by capping
-- maxFrameCount to rows*cols; the anchor frame's footprint is our own bounding-box
-- estimate from the same three numbers, not something AK reports back.
--
-- Settings: maxTotal (overall cap), iconsPerRow (columns), maxRows. Effective cap =
-- min(maxTotal, maxRows * iconsPerRow) -- e.g. maxTotal=10 on a 5x5 grid still shows
-- at most 10, using 2 rows. iconsPerRow/maxRows/maxTotal fallbacks are
-- isBuff-conditional (11x3=32 buffs, 8x2=16 debuffs), reached only when a bar doesn't
-- set these itself (the two default bars); every custom bar sets all three explicitly
-- (PAB_AddCustomBuffBar/DebuffBar, 8x1=8 for both).
--
-- width/height: N icons need (N-1) gaps, not N -- `cols * (iconSize + pad)` bakes in
-- one extra trailing pad, making the box a few px bigger than its icons. This sizes
-- the LIVE bar's parent frame and the preview box (RenderPreviewIcons/
-- PAB_BuildPreviewBox); the CENTER-anchor recompensation math assumes it's accurate.
-- Because an Icon Effects Size override renders one category's icons bigger via a
-- separate sized style variant (EnsurePabSizedStyle) without growing the frame, the
-- box is sized for the LARGEST icon that could ever appear. An exact footprint is
-- impossible ahead of time -- a FLOW layout mixing per-group icon sizes is
-- data-dependent -- so this follows the same static worst-case capacity reservation
-- spirit maxTotal/rows*cols already use.
local function MaxIconSizeFor(isBuff, cfg)
    local size = cfg.iconSize or 32
    if not isBuff and cfg.fxList then
        local list = PAB_FxListView(cfg.fxList)
        if list then
            for i = 1, #list do
                local sz = tonumber(list[i].size)
                if sz and sz > size then size = sz end
            end
        end
    end
    -- Snap to the physical pixel grid (same reasoning as ApplyGroupConfig's gap/rowGap
    -- snap): a raw iconSize also feeds the container's cross-axis extent math
    -- (ComputeGrid) at a non-pixel-perfect UIParent scale. Shape-expand applied last so
    -- the bar frame's footprint (ComputeGrid) always matches the buttons' real size.
    -- Second value: the unsnapped size, for ComputeGrid's design extent.
    local shaped = PabShapedSize(size, cfg.iconShape)
    return PabSnap(shaped), shaped
end

-- Engine-declared weapon-enchant slots (AuraContainerItemEnchantmentSlot:
-- main hand, off hand, ranged). Only the first two are reachable in current
-- retail content, but the engine declares all three, so anything reserving
-- space for them must tolerate three.
local ENCH_SLOT_COUNT = 3

local function ComputeGrid(isBuff, cfg)
    local iconSize, rawIconSize = MaxIconSizeFor(isBuff, cfg)
    local pad = cfg.padding or 5
    local rowGap = cfg.rowSpacing or 12
    local layoutPad = PabSnap(pad)
    local layoutRowGap = PabSnap(rowGap)
    local cols = math.max(1, cfg.iconsPerRow or (isBuff and 11 or 8))
    local rows = math.max(1, cfg.maxRows or (isBuff and 3 or 2))
    local configuredMax = cfg.maxTotal or (isBuff and 32 or 16)
    local effectiveMax = math.min(configuredMax, rows * cols)
    -- Actual rows needed for the effective cap, never more than the row limit
    local usedRows = math.min(rows, math.max(1, math.ceil(effectiveMax / cols)))
    -- How many weapon-enchant slots may be DECLARED on this bar. A grid under
    -- three cells declares only what it can hold (main hand first), so the
    -- cells can never spill out of it. This is not a budget: an inactive slot
    -- reserves nothing, only a cell that actually shows costs one (BuffAuraMax).
    local enchSlots = 0
    if isBuff and ns.PAB_EnchantsOn(cfg) then
        enchSlots = math.min(ENCH_SLOT_COUNT, effectiveMax)
    end
    -- `lineExtent` is the icons' own extent on the line axis (iconsPerRow
    -- icons of iconSize + gaps); `crossExtent` is the other axis (lines actually used).
    -- Horizontal growth: a "line" is a row, so lineExtent -> width. Vertical growth
    -- modes: a "line" is a column, so lineExtent -> height -- see
    -- CornerFor/BuildContainerSpec for the matching growthH/growthV swap.
    local lineExtent = cols * iconSize + (cols - 1) * layoutPad
    -- Wrap budget handed to the engine. At POSITIVE spacing the engine reserves a
    -- TRAILING elementSpacing after every element (not only between), so a full
    -- line needs cols * (icon + spacing) or the last icon of every row wraps --
    -- field-confirmed twice, most recently 2026-08-14 (11-per-row wrapped at 10
    -- without the trailing pad). At NEGATIVE spacing that same trailing reserve
    -- makes the final icon wrap EARLY, so the budget adds nothing there.
    -- lineExtent still sizes the bar's own frame either way, so the drag box
    -- measures the icons, not the phantom trailing gap.
    local rowWidth = math.max(iconSize, lineExtent) + math.max(0, layoutPad)
    local crossExtent = usedRows * iconSize + (usedRows - 1) * layoutRowGap
    local vertical = (cfg.growDirection == "UP" or cfg.growDirection == "DOWN" or cfg.growDirection == "CENTER_VERTICAL")
    local width = vertical and crossExtent or lineExtent
    local height = vertical and lineExtent or crossExtent
    -- Reference boxes for stored positions (see BarAnchorOffset): the design extent
    -- from the raw config numbers, identical at every resolution, and the legacy
    -- extent the pre-fix PP.Scale truncation produced at this resolution.
    local PP = EllesmereUI.PP
    local legacyIcon, legacyPad, legacyRowGap = PP.Scale(rawIconSize), PP.Scale(pad), PP.Scale(rowGap)
    local designLine = cols * rawIconSize + (cols - 1) * pad
    local designCross = usedRows * rawIconSize + (usedRows - 1) * rowGap
    local legacyLine = cols * legacyIcon + (cols - 1) * legacyPad
    local legacyCross = usedRows * legacyIcon + (usedRows - 1) * legacyRowGap
    return {
        -- The bar's WHOLE icon budget (Max Icons), weapon-enchant cells
        -- included -- BuffAuraMax takes the showing ones off it.
        effectiveMax = effectiveMax,
        enchSlots = enchSlots,
        rowWidth = rowWidth,
        width = width,
        height = height,
        designWidth = vertical and designCross or designLine,
        designHeight = vertical and designLine or designCross,
        legacyWidth = vertical and legacyCross or legacyLine,
        legacyHeight = vertical and legacyLine or legacyCross,
        rowGap = rowGap,
    }
end

-- Lazily creates and returns the default bars' per-polarity cfg sub-tables: same
-- shape as a custom bar object's shared+category fields, so
-- BuildStyle/ComputeGrid/ClassEnabled cannot tell the two apart.
local function DefaultBuffsCfg(s)
    s.defaultBuffs = s.defaultBuffs or {}
    return s.defaultBuffs
end
local function DefaultDebuffsCfg(s)
    s.defaultDebuffs = s.defaultDebuffs or {}
    return s.defaultDebuffs
end
ns.PAB_DefaultBuffsCfg = DefaultBuffsCfg
ns.PAB_DefaultDebuffsCfg = DefaultDebuffsCfg

-- Weapon enchants ride the default Buffs bar whenever one of its broad-content
-- modes (All Buffs or Has Duration) is on: oils and imbues are not auras, so
-- the catch-all group cannot admit them and the engine's item-enchantment
-- source stands in for it. No opt-in of their own -- the old "Weapon
-- Enchants" Filters row only existed while they had to be drawn by hand --
-- and custom buff bars never carry them.
function ns.PAB_EnchantsOn(cfg)
    if not cfg or (cfg.showAllBuffs == false and cfg.hasDuration ~= true) then return false end
    local s = PAB()
    return s ~= nil and s.defaultBuffs == cfg
end

-- Default Buffs bar display name. Returns the RAW English key: unlock mode
-- stores element labels untranslated (EUI_UnlockMode.lua's GetBarLabel hands
-- back elem.label verbatim), and the options page wraps the result in L()
-- itself. One definition for both callers.
function ns.PAB_DefaultBuffsName(cfg)
    return "Buffs"
end

-- One-time seed of the default Buffs/Debuffs bars' position/size/grid from Blizzard's
-- EditMode Buff/Debuff frame setup, so a first-time PAB user doesn't lose an
-- already-customized Blizzard layout. Guarded by s.pabEditModeSeeded, deliberately NOT
-- a nil-check on s.buffsPos/s.defaultBuffs: Buffs/Debuffs bars already exist for every
-- current user, so a nil-check would treat "never manually moved" as "brand new
-- profile" and silently reposition/resize existing bars.
--
-- Reads live BuffFrame/DebuffFrame state rather than C_EditMode.GetLayouts(): that
-- table is not reliably indexable by `activeLayout` (the pairs-key holding the active
-- layout's data did not match activeLayout's number, no other field to match on).
-- Blizzard has already resolved and applied the active layout onto these two frames by
-- the time addons run, so reading their live AuraContainer fields sidesteps the lookup.
--
-- Field mapping: AuraContainer.iconPadding -> padding (direct pixels).
-- AuraContainer.iconScale (observed 0.5-2.0, Blizzard's 50%-200% slider) -> iconSize =
-- round(32 * scale); assumes Blizzard's 100% matches PAB's 32px default (an
-- approximation, low risk, user can readjust). AuraContainer.iconStride -> iconsPerRow
-- (NOT maxTotal: "stride" = icons per row before wrapping, exact-matched against
-- Blizzard's IconLimitBuffFrame/DebuffFrame setting; no Blizzard equivalent for a true
-- total cap exists, so maxTotal stays unmigrated at PAB's own default).
-- AuraContainer.isHorizontal + .addIconsToRight/.addIconsToTop -> growDirection +
-- iconWrapDirection (the vertical-orientation branch is inferred from PAB's own
-- cross-axis convention, ToGrowthH/CornerFor above, NOT tested -- verification only
-- covered a horizontal Blizzard layout). frame:GetLeft()/GetTop() minus UIParent's own
-- -> buffsPos/debuffsPos, stored as a TOPLEFT-relative-to-UIParent offset --
-- deliberately NOT GetPoint()'s raw relativeTo, since PAB always anchors to UIParent
-- (ApplyBarPosition) while Blizzard's anchor can chain to an arbitrary frame (observed:
-- Buffs relativeTo="DebuffFrame"); absolute screen coordinates sidestep that chain.
local function SeedBarFromEditMode(frame, cfg, posKey, s, isBuff)
    if not (frame and frame.AuraContainer) then return end
    local ac = frame.AuraContainer

    local uiLeft, uiTop = UIParent:GetLeft(), UIParent:GetTop()
    local left, top = frame:GetLeft(), frame:GetTop()
    if uiLeft and uiTop and left and top then
        s[posKey] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = left - uiLeft, y = top - uiTop }
    end

    if ac.iconPadding then cfg.padding = ac.iconPadding end
    if ac.iconScale then cfg.iconSize = math.floor(32 * ac.iconScale + 0.5) end
    if ac.iconStride then
        cfg.iconsPerRow = ac.iconStride
        -- Keep the full icon cap reachable when the migrated row width is narrower
        -- than PAB's default (Blizzard stride=7 vs fallback iconsPerRow=11):
        -- ComputeGrid caps at min(maxTotal, maxRows*iconsPerRow) and maxTotal is NOT
        -- migrated, so maxRows must grow or a narrower stride silently shows fewer
        -- icons than the un-migrated default did. cap matches ComputeGrid's own
        -- isBuff-conditional maxTotal fallback (32/16) exactly.
        local cap = isBuff and 32 or 16
        cfg.maxRows = math.max(1, math.ceil(cap / ac.iconStride))
    end

    if ac.isHorizontal ~= nil then
        if ac.isHorizontal then
            cfg.growDirection = ac.addIconsToRight and "RIGHT" or "LEFT"
        else
            cfg.growDirection = ac.addIconsToTop and "UP" or "DOWN"
            cfg.iconWrapDirection = ac.addIconsToRight and "RIGHT" or "LEFT"
        end
    end
end

-- Migrates the retired Styled Player Auras module (db.profile.playerAuras). That
-- module never controlled position/size/grid (Blizzard drove layout via Edit Mode),
-- so nothing here duplicates SeedBarFromEditMode above; it DID apply border/font
-- styling as ONE shared flat cfg table, not split per polarity. Gated on the old
-- module's own `enabled` flag: only migrate if it was actually on. Field mapping:
-- borderSize/borderR/G/B/A -> same field name on BOTH buffCfg and debuffCfg (one
-- shared old value, not two). showText -> durationShow, both bars (same nil/true =
-- shown). textSize -> BOTH durationTextSize AND stackTextSize on both bars: the old
-- SkinAuraButton sized duration AND stack-count font strings from cfg.textSize, NOT
-- the duration-only/stack-only split the old External Defensives module uses.
-- noBorderDebuffs -> debuffCfg.borderSize = 0 (debuffs-only override, applied after
-- the shared borderSize above). Border texture/offset/layer fields now map directly;
-- durationFormat remains unsupported. Old buffIconZoom/debuffIconZoom are skipped --
-- PAB has its own per-bar iconZoom.
local function MigratePlayerAuraStyle(buffCfg, debuffCfg)
    local old = ns.db and ns.db.profile and ns.db.profile.playerAuras
    if not (old and old.enabled) then return end

    for _, cfg in ipairs({ buffCfg, debuffCfg }) do
        if old.borderSize then cfg.borderSize = old.borderSize end
        if old.borderR then cfg.borderR = old.borderR end
        if old.borderG then cfg.borderG = old.borderG end
        if old.borderB then cfg.borderB = old.borderB end
        if old.borderA then cfg.borderA = old.borderA end
        if old.borderTexture then cfg.borderTexture = old.borderTexture end
        if old.borderTextureOffset ~= nil then cfg.borderTextureOffset = old.borderTextureOffset end
        if old.borderTextureOffsetY ~= nil then cfg.borderTextureOffsetY = old.borderTextureOffsetY end
        if old.borderTextureShiftX ~= nil then cfg.borderTextureShiftX = old.borderTextureShiftX end
        if old.borderTextureShiftY ~= nil then cfg.borderTextureShiftY = old.borderTextureShiftY end
        if old.borderBehind ~= nil then cfg.borderBehind = old.borderBehind end
        if old.showText ~= nil then cfg.durationShow = old.showText end
        if old.textSize then
            cfg.durationTextSize = old.textSize
            cfg.stackTextSize = old.textSize
        end
    end

    if old.noBorderDebuffs then
        debuffCfg.borderSize = 0
    end
end

-- One-shot filter-model upgrade (v2, per profile): debuff bars moved to the unified
-- All Debuffs + filters dropdown, where checked classes SUBTRACT while Show All is on.
-- Stale add-mode selections that Show All used to bypass would suddenly subtract
-- content -- clear them once on every Show All debuff bar; add-mode bars keep theirs.
local function EnsureDebuffFilterV2(s)
    if s.pabDebuffFiltersV2 then return end
    s.pabDebuffFiltersV2 = true
    local d = s.defaultDebuffs
    if d and d.showAllDebuffs ~= false then d.classFilters = nil end
    if s.customDebuffBars then
        for i = 1, #s.customDebuffBars do
            local bar = s.customDebuffBars[i]
            if bar.showAllDebuffs ~= false then bar.classFilters = nil end
        end
    end
end

-- One-shot lane split (per profile): the filter dropdowns became two-lane (show/hide),
-- so the single mode-dependent selection splits into cfg.filters/classFilters (SHOW)
-- and cfg.negFilters/negClassFilters (HIDE). A broad-mode bar's checked entries were
-- subtracting -- move them to the hide lane so rendering is bit-identical; add-mode
-- selections already mean SHOW and stay put. Runs after EnsureDebuffFilterV2.
local function EnsureFilterLanes(s)
    if s.pabFilterLanesV1 then return end
    s.pabFilterLanesV1 = true
    local function SplitBuff(bar)
        if not bar then return end
        if (bar.showAllBuffs ~= false or bar.hasDuration == true)
            and bar.filters and next(bar.filters) then
            bar.negFilters = bar.filters
            bar.filters = nil
        end
    end
    local function SplitDebuff(bar)
        if not bar then return end
        if bar.showAllDebuffs ~= false and bar.classFilters and next(bar.classFilters) then
            bar.negClassFilters = bar.classFilters
            bar.classFilters = nil
        end
    end
    SplitBuff(s.defaultBuffs)
    if s.customBuffBars then
        for i = 1, #s.customBuffBars do SplitBuff(s.customBuffBars[i]) end
    end
    SplitDebuff(s.defaultDebuffs)
    if s.customDebuffBars then
        for i = 1, #s.customDebuffBars do SplitDebuff(s.customDebuffBars[i]) end
    end
end
ns.PAB_EnsureFilterLanes = EnsureFilterLanes

-- Content-source tests for the no-empty-selection rule: a bar always keeps at
-- least one content source (a broad mode, a Show-lane filter, an Extra
-- Spell). The hide lane is not a content source, and weapon enchants ride the
-- broad modes (ns.PAB_EnchantsOn) rather than counting as one. Shared by the
-- enable migration below and the options dropdowns' guards.
local function BuffBarHasContent(bar, isDefault)
    if bar.showAllBuffs ~= false or bar.hasDuration == true then return true end
    if bar.filters and next(bar.filters) then return true end
    if bar.spells and #bar.spells > 0 then return true end
    return false
end
-- Debuff content besides the All Debuffs mode: Show-lane classes, or an Icon
-- Effects block forcing a safe class on ("as if that Base Filter were on" --
-- the chain builders' fx wrapper renders those categories even in add mode, so
-- an fx-only bar is NOT empty).
local function DebuffBarOtherContent(bar)
    if bar.classFilters and next(bar.classFilters) then return true end
    if bar.fxList then
        local function AnyForced(list)
            if not list then return false end
            for i = 1, #list do
                local class = list[i]
                if PAB_FxSafeToForce(class) and PAB_FxWantsCategory(bar.fxList, class.key) then
                    return true
                end
            end
            return false
        end
        if AnyForced(VisibleTokenClasses()) or AnyForced(VisibleCandidateClasses()) then
            return true
        end
    end
    return false
end
local function DebuffBarHasContent(bar)
    if bar.showAllDebuffs ~= false or bar.hasDuration == true then return true end
    return DebuffBarOtherContent(bar)
end
ns.PAB_BuffBarHasContent = BuffBarHasContent
ns.PAB_DebuffBarOtherContent = DebuffBarOtherContent
ns.PAB_DebuffBarHasContent = DebuffBarHasContent

-- One-shot (per profile), HISTORICAL: written when the phase-2 no-empty rule
-- held (dropdown guards kept one content source alive). Those guards are gone
-- (2026-08-15): empty selections are legal again and the options page warns
-- loudly instead (red dropdown + bubble, AttachEmptyFilterWarn). The mapping
-- below still runs once for pre-phase-2 profiles: a LEGACY bar with no
-- content source rendered nothing, so it becomes All + disabled -- the same
-- nothing on screen, with sensible content on re-enable. Post-stamp empties
-- created through the dropdown are left exactly as the user set them. Runs
-- after EnsureFilterLanes (lanes must be split before emptiness is judged;
-- a broad-mode bar is never empty either way).
local function EnsureBarEnable(s)
    EnsureFilterLanes(s)
    -- One-shot: the "Weapon Enchants" opt-in is gone (the cells follow the
    -- broad-content modes, ns.PAB_EnchantsOn). An enchants-only bar had its
    -- grid pinned to 3x1x3 with the user's own grid stashed: put that back
    -- and turn All Buffs on, so the enchants it showed keep showing.
    if not s.pabEnchantsAutoV1 then
        s.pabEnchantsAutoV1 = true
        local d = s.defaultBuffs
        if d then
            local saved = d.enchGridSaved
            if saved then
                d.iconsPerRow, d.maxRows, d.maxTotal = saved.iconsPerRow, saved.maxRows, saved.maxTotal
                d.enchGridSaved = nil
                d.showAllBuffs = nil
            end
            d.showWeaponEnchants = nil
        end
    end
    if s.pabBarEnableV1 then return end
    s.pabBarEnableV1 = true
    local function MapBuff(bar, isDefault)
        if not bar then return end
        if bar.enabled ~= false and not BuffBarHasContent(bar, isDefault) then
            bar.showAllBuffs = nil -- All Buffs back on (nil = on)
            bar.enabled = false
        end
    end
    local function MapDebuff(bar)
        if not bar then return end
        if bar.enabled ~= false and not DebuffBarHasContent(bar) then
            bar.showAllDebuffs = nil
            bar.enabled = false
        end
    end
    MapBuff(s.defaultBuffs, true)
    if s.customBuffBars then
        for i = 1, #s.customBuffBars do MapBuff(s.customBuffBars[i], false) end
    end
    MapDebuff(s.defaultDebuffs)
    if s.customDebuffBars then
        for i = 1, #s.customDebuffBars do MapDebuff(s.customDebuffBars[i]) end
    end
end
ns.PAB_EnsureBarEnable = EnsureBarEnable

local function SeedDefaultBuffsDebuffsFromLegacySources(s)
    if s.pabEditModeSeeded then return end
    s.pabEditModeSeeded = true -- set first: never retry even if a read below errors/fails partway
    local buffCfg, debuffCfg = DefaultBuffsCfg(s), DefaultDebuffsCfg(s)
    SeedBarFromEditMode(BuffFrame, buffCfg, "buffsPos", s, true)
    SeedBarFromEditMode(DebuffFrame, debuffCfg, "debuffsPos", s, false)
    MigratePlayerAuraStyle(buffCfg, debuffCfg)
end

-- One-shot: the External Defensives bar is a normal custom buff bar carrying the
-- imported "Externals" preset filter (curated external-defensive spell list;
-- PAB_ImportBM2Filters must have run already -- see CreateBars' call order), so it
-- needs zero bespoke machinery. Seeded once per profile, disabled by default like the
-- built-in it replaced. Sources, newest first: the retired built-in bar's saved cfg
-- (s.defaultExternalDefensives), else the pre-PAB standalone module's table
-- (growDirection was lowercase there; showText -> durationShow; textSize styled the
-- stack/application-count text -> stackTextSize), else plain disabled defaults. The
-- retired position slots (s.extDefPos / the legacy module's unlockPos) become the
-- bar's own pos.
local function EnsureExtDefCustomBar(s)
    if s.pabExtDefSeeded == 2 then return end
    local extId
    do
        local list = ns.PAB_Filters and ns.PAB_Filters()
        if list then
            for i = 1, #list do
                if list[i].preset and list[i].name == "Externals" then
                    extId = list[i].id
                    break
                end
            end
        end
    end
    -- v1 of this seed gave the bar a bespoke extDefFilter pseudo-filter (since
    -- removed); convert those bars in place to the preset filter.
    if s.pabExtDefSeeded then
        s.pabExtDefSeeded = 2
        local bars = s.customBuffBars
        if bars and extId then
            for i = 1, #bars do
                local b = bars[i]
                if b.extDefFilter then
                    b.extDefFilter = nil
                    b.showAllBuffs = false
                    b.filters = { [extId] = true }
                end
            end
        end
        return
    end
    s.pabExtDefSeeded = 2
    local src = s.defaultExternalDefensives
    local legacy = ns.db and ns.db.profile and ns.db.profile.externalDefensives
    local from = src or legacy
    s.nextBarId = (s.nextBarId or 1)
    local bar = {
        id = s.nextBarId,
        name = "External Defensives",
        enabled = false,
        showAllBuffs = false,
        filters = extId and { [extId] = true } or {},
        spells = {}, ownOnlySpells = {},
        growDirection = "LEFT",
        iconsPerRow = 4, maxRows = 1, maxTotal = 4,
        durationPosition = "CENTER",
    }
    s.nextBarId = s.nextBarId + 1
    if from then
        if from.enabled ~= nil then bar.enabled = from.enabled == true end
        if from.iconSize then bar.iconSize = from.iconSize end
        if from.growDirection then bar.growDirection = string.upper(from.growDirection) end
        if from.durationShow ~= nil then bar.durationShow = from.durationShow
        elseif from.showText ~= nil then bar.durationShow = from.showText end
        if from.stackTextSize then bar.stackTextSize = from.stackTextSize
        elseif from.textSize then bar.stackTextSize = from.textSize end
        if from.durationPosition then bar.durationPosition = from.durationPosition end
        if from.durationTextSize then bar.durationTextSize = from.durationTextSize end
        if from.durationOffsetX then bar.durationOffsetX = from.durationOffsetX end
        if from.durationOffsetY then bar.durationOffsetY = from.durationOffsetY end
        if from.durationColorR then bar.durationColorR, bar.durationColorG, bar.durationColorB = from.durationColorR, from.durationColorG, from.durationColorB end
        if from.stackShow ~= nil then bar.stackShow = from.stackShow end
        if from.stackPosition then bar.stackPosition = from.stackPosition end
        if from.stackOffsetX then bar.stackOffsetX = from.stackOffsetX end
        if from.stackOffsetY then bar.stackOffsetY = from.stackOffsetY end
        if from.stackColorR then bar.stackColorR, bar.stackColorG, bar.stackColorB = from.stackColorR, from.stackColorG, from.stackColorB end
        if from.iconsPerRow then bar.iconsPerRow = from.iconsPerRow end
        if from.maxRows then bar.maxRows = from.maxRows end
        if from.maxTotal then bar.maxTotal = from.maxTotal end
        if from.padding then bar.padding = from.padding end
        if from.rowSpacing then bar.rowSpacing = from.rowSpacing end
        if from.iconZoom then bar.iconZoom = from.iconZoom end
        if from.showSwipe ~= nil then bar.showSwipe = from.showSwipe end
        if from.reverseSwipe ~= nil then bar.reverseSwipe = from.reverseSwipe end
        if from.fontOutline then bar.fontOutline = from.fontOutline end
        if from.sortMethod then bar.sortMethod = from.sortMethod end
        if from.sortDirection then bar.sortDirection = from.sortDirection end
        if from.borderSize then bar.borderSize = from.borderSize end
        if from.borderR then bar.borderR, bar.borderG, bar.borderB, bar.borderA = from.borderR, from.borderG, from.borderB, from.borderA end
        if from.borderTexture then bar.borderTexture = from.borderTexture end
        if from.borderTextureOffset ~= nil then bar.borderTextureOffset = from.borderTextureOffset end
        if from.borderTextureOffsetY ~= nil then bar.borderTextureOffsetY = from.borderTextureOffsetY end
        if from.borderTextureShiftX ~= nil then bar.borderTextureShiftX = from.borderTextureShiftX end
        if from.borderTextureShiftY ~= nil then bar.borderTextureShiftY = from.borderTextureShiftY end
        if from.borderBehind ~= nil then bar.borderBehind = from.borderBehind end
    end
    local pos = s.extDefPos or (legacy and legacy.unlockPos)
    if pos and pos.point then
        bar.pos = { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
    end
    s.customBuffBars = s.customBuffBars or {}
    s.customBuffBars[#s.customBuffBars + 1] = bar
    -- Retire the built-in bar's storage for good.
    s.defaultExternalDefensives = nil
    s.extDefPos = nil
end

I.BuffBarHasContent, I.ComputeGrid = BuffBarHasContent, ComputeGrid
I.DefaultBuffsCfg, I.DefaultDebuffsCfg = DefaultBuffsCfg, DefaultDebuffsCfg
I.EnsureBarEnable, I.EnsureDebuffFilterV2 = EnsureBarEnable, EnsureDebuffFilterV2
I.EnsureExtDefCustomBar, I.EnsureFilterLanes = EnsureExtDefCustomBar, EnsureFilterLanes
I.SeedDefaultBuffsDebuffsFromLegacySources = SeedDefaultBuffsDebuffsFromLegacySources
I.broken = false
