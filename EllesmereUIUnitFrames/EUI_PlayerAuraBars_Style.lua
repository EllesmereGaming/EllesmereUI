if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Style.lua
--
--  Sort settings, the style tables, BuildStyle, the dispel colors and the
--  candidate extras of both polarities.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local PAB_ApplyDmFx, PAB_FxListView = I.PAB_ApplyDmFx, I.PAB_FxListView
local PabShapeActive, PabShapeBorderSize = I.PabShapeActive, I.PabShapeBorderSize
local PabShapedSize, PabSnap = I.PabShapedSize, I.PabSnap

-------------------------------------------------------------------------------
--  Container spec construction
--
--  style.noRegions is NOT set: AK.MakeInitializer creates the standard
--  icon/cooldown/text regions and styling only layers on top.
-------------------------------------------------------------------------------

local STYLE_BUFFS = "playerAuraBars_buffs"
local STYLE_DEBUFFS = "playerAuraBars_debuffs"

-- Style field names verified against AK's ApplyStyleToRegions (EllesmereUI_AuraKit.lua).
--
-- Settings schema (db.profile.playerAuraBars): default bars (s.defaultBuffs/
-- s.defaultDebuffs) and every custom bar object share ONE cfg shape (no migration
-- from any older schema, deliberate). BuildStyle/ComputeGrid/ClassEnabled take
-- (isBuff, cfg) and don't care which table it came from.
--
-- Shared by every bar: iconSize (button width==height); durationShow/stackShow
-- (independent show/hide); durationTextSize/durationPosition("TOP"/"BOTTOM"/...)/
-- durationOffsetX/Y; durationColorR/G/B (optional, nil=white AK default);
-- stackTextSize/stackPosition/stackOffsetX/Y; stackColorR/G/B (same nil=white rule).
-- Buff/debuff bars additionally: iconZoom (default 0.07, AK's fallback);
-- borderSize/borderR/G/B/A (base border color, per-dispel-type override is separate);
-- borderTexture ("solid" or a built-in/LibSharedMedia key), optional
-- borderTextureOffset/OffsetY/ShiftX/ShiftY, and borderBehind;
-- padding (single scalar -> all 4 sides); rowSpacing (optional row gap: feeds
-- lineSpacing/groupLineSpacing only, nil falls back to `padding`; elementSpacing,
-- icon-to-icon within a row AND across a group seam, stays tied to `padding`
-- while groupSpacing is held at 0, see BuildGroupLayout); maxTotal
-- (overall icon cap, weapon-enchant cells included while that row is on);
-- iconsPerRow (row width in columns); maxRows (row cap; with
-- iconsPerRow also bounds maxTotal, see ComputeGrid()); growDirection ("LEFT"/"RIGHT"/
-- "CENTER_HORIZONTAL"/"CENTER_VERTICAL"/"UP"/"DOWN", default LEFT).
-- Buff bars (default AND custom, one model): filters ([filterId]=true, shared PAB
-- Filters registry); spells ({spellID,...}, direct/"Extra Spells"); showAllBuffs
-- (default bar ONLY, custom buff bars never read it; defaults true, else an
-- unconfigured bar shows nothing -- adds an additive catch-all GROUP alongside the
-- spells group, matching Blizzard's player BuffFrame; UI toggle "Show All Buffs",
-- mirrors Show All Debuffs). classFilters has NO effect on buff bars -- BuildChain is
-- used only via the always-catch-all showAllBuffs group, never per-class.
-- Debuff bars (default AND custom): classFilters ([classSkey]=true); showAllDebuffs
-- (bypasses classFilters unless explicitly false; defaults TRUE, nil==on, mirroring
-- showAllBuffs); dispelColorMagic/Curse/Disease/Poison/Bleed (optional Color-like
-- {r,g,b}, falls back to the Raid Frames palette).
--
-- Duration format: AK.GetDurationFormatter(showSecondsUnit) serves two cached
-- variants -- bare seconds under 60 (the suite default) or unit-suffixed
-- ("10s") via the per-bar "Show S for Seconds" cog (style.durationShowSeconds);
-- both keep Xm/Xh/Xd above the minute. No other format variants ("colon" etc.):
-- those would mean new AuraKit breakpoint schemas (shared with Raid Frames).
-- DISPEL_SLOTS below is a local copy of EUI_RaidFrames_AuraContainers.lua's: ns is
-- per-addon-private, so tokens/fallback colors are duplicated on purpose for suite-wide
-- consistency -- a RaidFrames palette change must be mirrored here by hand, no shared source.
local DISPEL_SLOTS = {
    { token = "Magic",   colorKey = "dispelColorMagic",   fallback = { 0.349, 0.475, 1.0 } },
    { token = "Curse",   colorKey = "dispelColorCurse",   fallback = { 0.636, 0.0, 0.64 } },
    { token = "Disease", colorKey = "dispelColorDisease", fallback = { 0.671, 0.384, 0.098 } },
    { token = "Poison",  colorKey = "dispelColorPoison",  fallback = { 0.0, 0.706, 0.286 } },
    { token = "Bleed",   colorKey = "dispelColorBleed",   fallback = { 0.75, 0.15, 0.15 } },
}

-- Dispel-type indicator icon: preview-only atlas/point maps. The LIVE icon is
-- engine-rendered (AK's one-hot dispel-texture channel, style.dispelTypeIcon);
-- these exist so the options preview can paint the same art from the fake
-- entries' plain dispel tokens.
local PV_DISPEL_ICON_ATLAS = {
    Magic   = "RaidFrame-Icon-DebuffMagic",
    Curse   = "RaidFrame-Icon-DebuffCurse",
    Disease = "RaidFrame-Icon-DebuffDisease",
    Poison  = "RaidFrame-Icon-DebuffPoison",
    Bleed   = "RaidFrame-Icon-DebuffBleed",
}
local PV_DISPEL_ICON_POINTS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

-- Same shape as RaidFrames' ns.RFC_DispelBorderColorMap: a customDispelColorMap
-- (dispelName -> Color) for AK's engine-driven border, plus a fingerprint so a
-- palette edit re-registers the border options (style.dispelColorFP).
local function BuildDispelColorMap(cfg)
    local map, fp = {}, {}
    for i = 1, #DISPEL_SLOTS do
        local def = DISPEL_SLOTS[i]
        local c = cfg[def.colorKey]
        local r = (c and c.r) or def.fallback[1]
        local g = (c and c.g) or def.fallback[2]
        local b = (c and c.b) or def.fallback[3]
        map[def.token] = CreateColor(r, g, b, 1)
        fp[#fp + 1] = string.format("%.3f,%.3f,%.3f", r, g, b)
    end
    return map, table.concat(fp, ";")
end

-- Anchor-point mirror for placing duration text OUTSIDE the icon: the text's OWN
-- point is the opposite corner/edge of the icon's anchor, so "TOP" anchors the
-- text's BOTTOM edge to the icon's TOP edge (text sits above).
local OPPOSITE_POINT = {
    TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
    TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT",
    BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT",
    CENTER = "CENTER",
}

local function SetTexturePixelSnap(texture, enabled)
    if not (texture and texture.SetSnapToPixelGrid) then return end
    texture:SetSnapToPixelGrid(enabled)
    texture:SetTexelSnappingBias(0)
end

-- Secondary text-styling pass: AK calls style.applyExtra as (button, d, style), where
-- d.duration/d.stack are the FontStrings AK's own initializer creates. Adds what AK has
-- no native field for: duration/stack text color and independent stack-text show/hide
-- (AK's hideDurationText covers duration hide only, no native stack equivalent).
local function PAB_ApplyExtraText(button, d, style)
    -- Own text pipeline (style.noDefaultFonts): fonts ride the user's global/per-module
    -- Unit Frames font and the house icon-text outline rules, resolved once per style
    -- rebuild into style.fontPath/fontFlag (see BuildStyle). Font/anchor writes are
    -- change-guarded (stamp AFTER the calls): SetPoint with the button as relative frame
    -- is policed by the 12.1 button access restriction while auras are secret, so
    -- unchanged values must make zero button-involving calls for restyles to stay live
    -- in-instance.
    local path = style.fontPath or STANDARD_TEXT_FONT
    local flag = style.fontFlag or "OUTLINE"
    if d.duration then
        local fKey = path .. "|" .. (style.durationFontSize or 11) .. "|" .. flag
        if d.pabDurFont ~= fKey then
            d.pabDurFont = fKey
            -- Prime the shadow FontObject before SetFont; Drop Shadow mode (empty
            -- flag) keeps the text legible instead of flat.
            EllesmereUI.PrimeFontShadow(d.duration, flag == "")
            d.duration:SetFont(path, style.durationFontSize or 11, flag)
        end
        local dp = style.durationPoint or "CENTER"
        local drp = style.durationRelPoint or "CENTER"
        local aKey = dp .. "|" .. drp .. "|" .. (style.durationX or 0) .. "|" .. (style.durationY or 0)
        if d.pabDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint(dp, button, drp, style.durationX or 0, style.durationY or 0)
            d.pabDurAnchor = aKey
        end
        local c = style.durationColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        -- "Show S for Seconds" rebind: duration opts land once at creation;
        -- re-register when the style's formatter choice changed. The nil
        -- gate skips the creation-time applyExtra pass (the creation block
        -- registers and stamps right after). Stamp-after-success, the
        -- BmRebindDurationCurve rule: a denied registration under the
        -- secret-aura button restriction must leave the stamp unchanged so
        -- the next restyle retries.
        local wantFmt = (style.durationShowSeconds and "s" or "b") .. tostring(style.durationPrecisionThreshold or 0)
        if d.durationFmtS ~= nil and d.durationFmtS ~= wantFmt then
            local AK = EllesmereUI.AuraKit
            local durationOpts = AK.BuildDurationTextOpts(
                AK.GetDurationFormatter(style.durationShowSeconds, style.durationPrecisionThreshold),
                style.durationColorCurve, style.durationUpdateInterval)
            local ok, full = AK.SetDurationTextSafe(button, d.duration, durationOpts)
            if ok and (full or not style.durationColorCurve) then
                d.durationFmtS = wantFmt
            end
        end
    end
    if d.stack then
        local fKey = path .. "|" .. (style.stackFontSize or 11) .. "|" .. flag
        if d.pabStackFont ~= fKey then
            d.pabStackFont = fKey
            EllesmereUI.PrimeFontShadow(d.stack, flag == "")
            d.stack:SetFont(path, style.stackFontSize or 11, flag)
        end
        local sp = style.stackPoint or "BOTTOMRIGHT"
        local sKey = sp .. "|" .. (style.stackX or 0) .. "|" .. (style.stackY or 0)
        if d.pabStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint(sp, button, sp, style.stackX or 0, style.stackY or 0)
            d.pabStackAnchor = sKey
        end
        d.stack:SetShown(style.showStacks ~= false)
        local c = style.stackColor
        d.stack:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end

    -- Duration swipe visibility. style.hideSwipe only runs through AK's
    -- ApplyStyleToRegions (SetShown), firing at button CREATION and on explicit
    -- Restyle passes -- NOT on ordinary aura content churn. The engine calls
    -- Cooldown:SetCooldown on d.cooldown whenever that slot's aura data refreshes,
    -- and that native API implicitly re-Shows the frame, silently undoing
    -- SetShown(false). Two extra layers while "Show Duration Swipe" is OFF, both
    -- reading the LIVE flag (d.pabHideSwipe) because a hook cannot uninstall:
    --   1) a Show post-hook that immediately re-hides (hooksecurefunc runs AFTER
    --      Blizzard's call completes; installed once per button),
    --   2) frame alpha 0 -- Show()/Hide() never touch alpha, so it survives internal
    --      engine paths that re-show the frame outside the hooked Lua method
    --      (post-instance-change re-shows do this).
    if d.cooldown then
        d.pabHideSwipe = style.hideSwipe == true
        -- Install lazily on the first apply that actually hides the swipe. The
        -- hook reads the live flag, so a later toggle back on still works, and a
        -- user who never turns the setting off never gets a closure or a secure
        -- hook on this cooldown's Show at all.
        if d.pabHideSwipe and not d._pabSwipeHooked then
            d._pabSwipeHooked = true
            hooksecurefunc(d.cooldown, "Show", function()
                if d.pabHideSwipe then d.cooldown:Hide() end
            end)
        end
        local a = d.pabHideSwipe and 0 or 1
        if d.pabSwipeAlpha ~= a then
            d.pabSwipeAlpha = a
            d.cooldown:SetAlpha(a)
        end
    end

    -- Icon Effects Per-Filter (debuffs only): flag-gated so buff buttons, which never
    -- carry style.fxList or fx overlay frames, pay zero cost.
    if style.fxList or d.pabFxGlow or d.pabFxBdr then
        PAB_ApplyDmFx(button, d, style)
    end

    -- Centered runs can have an odd content width/height, whose CENTER anchor is a
    -- half pixel. Let textures use Blizzard's normal pixel snapping so
    -- icon art cannot bleed over PP's one-pixel border. Edge-growing bars keep EUI's
    -- usual unsnapped rendering.
    d.pabCenteredSnap = style.centeredGrowth == true
    -- Lazy install on the first centered apply: bars that never use centered
    -- growth never pay the closure. Once installed the hook reads the live
    -- flag, so switching back to edge growth costs one boolean per SetTexture.
    if d.pabCenteredSnap and d.icon and not d.pabIconSnapHooked then
        d.pabIconSnapHooked = true
        hooksecurefunc(d.icon, "SetTexture", function(texture)
            if d.pabCenteredSnap then SetTexturePixelSnap(texture, true) end
        end)
    end
    SetTexturePixelSnap(d.icon, d.pabCenteredSnap)
    local border = d.borderHost and EllesmereUI.PP.GetBorders(d.borderHost)
    if border then
        SetTexturePixelSnap(border._top, d.pabCenteredSnap)
        SetTexturePixelSnap(border._bottom, d.pabCenteredSnap)
        SetTexturePixelSnap(border._left, d.pabCenteredSnap)
        SetTexturePixelSnap(border._right, d.pabCenteredSnap)
    end
    -- Textured borders use the secret-safe eight-slice renderer rather than PP.
    -- Keep its edge art on the same centered-growth snapping policy.
    if d._secretBorderEdges then
        for _, tex in pairs(d._secretBorderEdges) do
            SetTexturePixelSnap(tex, d.pabCenteredSnap)
        end
    end
end

-- Icon-text outline flag for duration/stack text. Default follows the house icon-text
-- rule: crisp "OUTLINE, SLUG" unless Unit Frames is unchecked in Global Settings'
-- "Outline Icon Text", then the global/per-module choice. A per-bar Font Outline pick
-- overrides that; every branch stays slug-gated centrally via "Never Show Slug".
local function ResolveFontFlag(mode)
    if mode == "none" then return "" end
    if mode == "outline" then
        return (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE"
    end
    if mode == "thick" then
        return (EllesmereUI.SlugFlag("THICKOUTLINE, SLUG")) or "THICKOUTLINE"
    end
    return (EllesmereUI.GetIconTextOutlineFlag("unitFrames")) or "OUTLINE"
end

local function BuildStyle(isBuff, cfg)
    local iconZoom = cfg.iconZoom
    -- Blizzard Style: zoom 0 -- the stock buff frame draws the whole icon,
    -- and the icon art's own dark edge is the border a stock buff shows.
    if ns.PAB_Blizz() then iconZoom = 0 end
    local borderSize = cfg.borderSize or 1
    local borderR = cfg.borderR or 0
    local borderG = cfg.borderG or 0
    local borderB = cfg.borderB or 0
    local borderA = cfg.borderA or 1

    -- size 0 = no border; no separate "Hide Border" toggle.
    local border
    -- The exact solid size (the borderSizePx companion) when one is set: the
    -- dispel ring strips follow it the way they follow borderSize, so the base
    -- ring and the dispel ring stay one width.
    local solidPx
    if borderSize > 0 then
        border = { borderR, borderG, borderB, borderA, size = borderSize }
        -- Texture fields ride only on a textured pick: a border table with a
        -- texture key sends AuraKit down its explicit-size eight-slice lane,
        -- and Solid must keep the plain PP path it always had.
        local texture = cfg.borderTexture
        if texture and texture ~= "" and texture ~= "solid" then
            local textureSize = cfg.borderTextureSizeOverride or borderSize
            border.texture = texture
            border.textureSize = textureSize
            border.offsetX = cfg.borderTextureOffset
            border.offsetY = cfg.borderTextureOffsetY
            border.shiftX = cfg.borderTextureShiftX
            border.shiftY = cfg.borderTextureShiftY
            border.behind = cfg.borderBehind == true
            border.addonKey = "unitframes"
            border.sizeKey = textureSize
            border.edgeScale = cfg.borderTextureScaleOverride
            -- Exact edge in pixels (EllesmereUI.BorderPx over the borderSizePx
            -- companion; nil = the legacy EDGE_MAP step). The preview resolves it
            -- against the raw step itself (borderPxOverride) since its borderSize
            -- is scale-compensated and could never pair.
            border.edgePx = cfg.borderPxOverride
                or EllesmereUI.BorderPx(cfg.borderSizePx, textureSize, texture)
        else
            solidPx = cfg.borderPxOverride
                or EllesmereUI.BorderPx(cfg.borderSizePx, borderSize, texture)
            border.edgePx = solidPx
        end
    end
    -- Blizzard Style: no EUI ring on any bar -- buffs go borderless like the
    -- stock buff frame, debuffs take the engine-stamped stock border below.
    if ns.PAB_Blizz() then border = nil end

    -- Positions may arrive mixed-case ("Bottom") rather than the uppercase anchor
    -- constants SetPoint expects; normalized here so a mismatched-case default or
    -- Options write cannot silently mis-anchor or error.
    local durSide = string.upper(cfg.durationPosition or "CENTER")
    local stackSide = string.upper(cfg.stackPosition or "BOTTOMRIGHT")

    -- Snapped to the physical pixel grid (like MaxIconSizeFor and ApplyGroupConfig's
    -- gap snap) so the rendered size agrees with the container's cross-axis extent
    -- math at any UIParent scale.
    local iconSize = PabSnap(PabShapedSize(cfg.iconSize or 32, cfg.iconShape))

    -- Negative Spacing / Row Spacing overlap neighbouring icons; AuraKit shrinks
    -- each mouse area by half the overlap so the icon being left cannot hide the
    -- tooltip of the one entered (see hitInsetX in EllesmereUI_AuraKit.lua).
    -- Same defaults and snap as ComputeGrid. In vertical growth the icon-to-icon
    -- gap runs along Y and the row gap along X.
    local gapOverlap = math.max(0, -PabSnap(cfg.padding or 5))
    local rowOverlap = math.max(0, -PabSnap(cfg.rowSpacing or 12))
    local vertical = cfg.growDirection == "UP" or cfg.growDirection == "DOWN"
        or cfg.growDirection == "CENTER_VERTICAL"

    local style = {
        width = iconSize,
        height = iconSize,
        hitInsetX = (vertical and rowOverlap or gapOverlap) / 2,
        hitInsetY = (vertical and gapOverlap or rowOverlap) / 2,
        centeredGrowth = cfg.growDirection == "CENTER_HORIZONTAL" or cfg.growDirection == "CENTER_VERTICAL",
        iconCrop = true,
        iconZoom = iconZoom or 0.055,

        -- Reverse Swipe cog (Show Duration Swipe toggle), default on. AK's
        -- ApplyStyleToRegions passes this straight to SetReverse.
        cooldownReverse = (cfg.reverseSwipe ~= false),
        -- Duration swipe: the darkening radial overlay CooldownFrameTemplate draws as
        -- remaining time shrinks, distinct from the duration NUMBER text
        -- (hideDurationText), independently controllable. Per-bar "Show Duration
        -- Swipe" toggle, default on; PAB_ApplyExtraText's swipe block handles the
        -- engine re-show problem.
        hideSwipe = (cfg.showSwipe == false),

        -- Right-click to cancel, mirroring Blizzard's player BuffFrame. PAB is always
        -- the player unit, so only the isBuff half of the sibling module's condition
        -- applies (debuffs are never player-cancelable). Routes to the engine's
        -- AuraButtonMixin:SetCancelAuraButtons -- Blizzard's own secure click-to-cancel,
        -- not a hand-rolled macro/attribute setup. Per-bar "Right-Click to
        -- Cancel" toggle, default on; OFF makes the bar CLICK-through -- the
        -- nil here routes AK to SetMouseClickEnabled(false), so every click
        -- passes straight to the world. Hover is deliberately untouched:
        -- click and motion are separate mouse channels, so tooltips keep
        -- following Show Tooltips below either way.
        -- UP phase, matching Blizzard's own AuraButtonMixin ("LeftButtonUp",
        -- "RightButtonUp"). Known limitation, field-reported 2026-08-12: for some
        -- players the right-button PRESS falls through to WorldFrame, which starts
        -- camera mouselook and captures the mouse, so the matching ButtonUp ends the
        -- mouselook instead of reaching the button and the buff survives. Blizzard's
        -- legacy icons consume that press; the engine's intrinsic AuraButton denies
        -- tainted (addon) code the input aspects that would do the same
        -- (Blizzard_AuraButton.xml: ForbiddenAspect AlwaysPropagateInput /
        -- ScriptedInput), and no API re-grants a denied aspect. "RightButtonDown"
        -- works around it but was rejected deliberately: a right-click-drag starting
        -- on an icon would then cancel that buff on press. Do not "fix" this by
        -- registering BOTH phases either -- Blizzard's CanCancelAuraOnClick matches
        -- any registered token, so OnClick fires twice and the engine may have
        -- re-assigned this button's aura instance in between, cancelling a DIFFERENT
        -- aura on the up edge.
        cancelButtons = (isBuff and cfg.rightClickCancel ~= false) and "RightButtonUp" or nil,

        hideDurationText = cfg.durationShow == false,
        -- "Show S for Seconds" (Duration cog, default off): sub-minute
        -- readings keep their unit ("10s"); selects AK's s-variant duration
        -- formatter at creation, PAB_ApplyExtraText rebinds live.
        durationShowSeconds = cfg.durationShowSeconds == true,
        durationPrecisionThreshold = tonumber(cfg.durationPrecisionThreshold),
        -- Show Tooltips (per-bar, default on): AK's noTooltips path kills
        -- hover on this style's buttons; the flip-back handles re-enables.
        noTooltips = (cfg.showTooltips == false) or nil,
        durationFontSize = cfg.durationTextSize or 11,
        durationPoint = OPPOSITE_POINT[durSide] or "TOP",
        durationRelPoint = durSide,
        durationX = cfg.durationOffsetX or 0,
        durationY = cfg.durationOffsetY or 0,
        durationColor = cfg.durationColorR and
            { r = cfg.durationColorR, g = cfg.durationColorG, b = cfg.durationColorB } or nil,

        stackFontSize = cfg.stackTextSize or 11,
        stackPoint = stackSide,
        stackX = cfg.stackOffsetX or 0,
        stackY = cfg.stackOffsetY or 0,
        showStacks = cfg.stackShow ~= false,
        stackColor = cfg.stackColorR and
            { r = cfg.stackColorR, g = cfg.stackColorG, b = cfg.stackColorB } or nil,

        -- Own text pipeline: AK's default font/anchor block is skipped; PAB_ApplyExtraText
        -- does it via the house icon-text rules. Font path and outline flag resolve once
        -- per style rebuild (settings-apply frequency), never per applyExtra call.
        noDefaultFonts = true,
        fontPath = (EllesmereUI.GetFontPath("unitFrames")) or STANDARD_TEXT_FONT,
        fontFlag = ResolveFontFlag(cfg.fontOutline),

        applyExtra = PAB_ApplyExtraText,

        border = border,
        -- Weapon enchant buttons mirror this style: the stock purple ring.
        blizzEnchant = ns.PAB_Blizz() or nil,
    }

    -- Custom icon shape (Square/Circle/Hexagon/etc, same media set as Action Bars
    -- and Unit Frames' detached portraits). ns.PORTRAIT_MASKS/BORDERS/MASK_INSETS are
    -- exposed by EUI_UnitFrames_Portrait.lua (same addon/ns); AuraKit itself lives in a
    -- separate TOC and never touches ns, so resolved paths travel through style.*.
    local shape = cfg.iconShape
    if PabShapeActive(shape) then
        style.iconShape       = shape
        style.shapeMaskPath   = ns.PORTRAIT_MASKS and ns.PORTRAIT_MASKS[shape]
        style.shapeBorderPath = ns.PORTRAIT_BORDERS and ns.PORTRAIT_BORDERS[shape]
        style.shapeInsetPx    = ns.MASK_INSETS and ns.MASK_INSETS[shape]
        style.shapeBorderSize = cfg.shapeBorderSizeOverride or PabShapeBorderSize(borderSize)
    end

    -- Engine dispel-type border, debuffs only (buffs have no dispel type). AK's gate
    -- (ApplyStyleToRegions) only activates it when `border` above is ALSO non-nil, so
    -- borderSize = 0 disables dispel-type coloring too, not just the static ring --
    -- engine behavior, not a choice made here. borderSize (or the exact solid size
    -- above) drives BOTH ring widths; a distinct dispel-ring width would need its
    -- own setting split back out.
    if not isBuff then
        if ns.PAB_Blizz() then
            -- Blizzard Style: the engine stamps Blizzard's own per-dispel-type
            -- debuff border art (red for untyped) -- no ring size, no palette.
            style.dispelBorder = true
            style.blizzBorder = true
        else
            local dcMap, dcFP = BuildDispelColorMap(cfg)
            style.dispelBorder = true
            style.dispelBorderPx = solidPx or borderSize
            style.dispelColorMap = dcMap
            style.dispelColorFP = dcFP
            -- Textured Dispel Ring (per bar, opt-in): AuraKit draws the ring in
            -- this bar's border art on the geometry its border lane draws that
            -- border with (style.border), tinted by the engine from the palette
            -- above. Solid, shaped or size-0 bars keep the strips/shape ring.
            if cfg.borderDispelTextured == true and border and border.texture then
                style.dispelBorderTexture = border.texture
            end
        end

        -- Dispel-type indicator icon (AK's one-hot engine channel; default off).
        -- Independent of borderSize: the icon renders with or without a ring.
        local dip = cfg.dispelIconPosition
        if dip and dip ~= "none" then
            style.dispelTypeIcon = {
                pos = dip,
                -- Scaled like iconSize (button-geometry class); offsets stay raw
                -- like durationX (fine-tune class).
                size = PabSnap(cfg.dispelIconSize or 16),
                offX = cfg.dispelIconOffsetX or 0,
                offY = cfg.dispelIconOffsetY or 0,
            }
        end

        -- Icon Effects Per-Filter: debuffs only (buffs never get style.fxList, so
        -- PAB_ApplyDmFx's gate in PAB_ApplyExtraText stays a cheap no-op).
        style.fxList = PAB_FxListView(cfg.fxList)
    end

    return style
end

-- ApplyGroupConfig (EUI_PlayerAuraBars_Groups.lua) declares/updates every group in `chain` on an existing
-- container. Groups are ADDITIVE and the container is NEVER torn down and rebuilt:
-- ReleaseContainer()+RequestContainer() permanently leaks a 10-button engine batch per
-- group per swap (WoW never frees frames). A class toggle (or grid/padding/growth
-- change) just calls it again on the SAME container.
--
-- A group's filter string is fixed at declaration (AuraContainer has no group filter
-- setter), so an already-declared class keeps its original negation-chain tokens even
-- if an earlier-priority class is toggled later -- a known, accepted limitation shared
-- with the sibling module. Only matters when a re-order changes an ALREADY-DECLARED
-- class's negation set; toggling the SAME class on/off is always correct, since only
-- its maxFrameCount changes.
--
-- Sort resolution uses the native enum globals: AuraContainerSortMethod = {Default=0,
-- BigDefensive=1, UnitFrameDebuff=2, ImportantOnly=3, Expiration=4, ExpirationOnly=5,
-- Name=6, NameOnly=7, AuraInstanceIDOnly=8}, AuraContainerSortDirection = {Normal=0,
-- Reverse=1}. Default=0 and Normal=0 are valid values, not "unset" -- compare against
-- nil, never truthiness.
--
-- The dropdown's "Expiration"/"Name" resolve to the native *Only variants: the plain
-- Expiration/Name comparators rank player-cast/canApplyAura FIRST and only then the
-- named criterion, so a bar sorted "by Expiration" came out as two separately sorted
-- runs (e.g. 1h 58m 57m ... then 11h 54m 6m). The saved value keeps the dropdown key.
local function ResolveSortMethod(cfg)
    local key = cfg.sortMethod or "Default"
    if not AuraContainerSortMethod then return nil end
    local native = (key == "Expiration" and "ExpirationOnly") or (key == "Name" and "NameOnly") or nil
    return (native and AuraContainerSortMethod[native]) or AuraContainerSortMethod[key]
end
local function ResolveSortDirection(cfg)
    local key = (cfg.sortDirection == "Reverse") and "Reverse" or "Normal"
    return AuraContainerSortDirection and AuraContainerSortDirection[key]
end

-- "Has Duration" (Assigned Buffs filter), buffs only: native
-- `candidateFilters.maxDuration`. Blizzard's check excludes an aura when
-- `duration > maxDuration or duration == 0` (max-duration filters implicitly always
-- filter out permanent auras), so a `math.huge` cap never trips the `>` half and this
-- ONLY excludes permanent (duration=0) buffs, whatever a timed buff's duration is.
local function BuffCandidateExtras(cfg)
    local out
    if cfg and cfg.hasDuration then
        out = { maxDuration = math.huge }
    end
    -- Blacklist (Edit Blacklist in the Filters dropdown): applied exactly while the
    -- dropdown offers it (All Buffs or Has Duration on) and rides every buff group via
    -- this extras merge -- catch-all AND spells group -- so a blacklisted spell never
    -- displays. Fresh table per call: merged maps must never alias saved vars.
    if cfg and cfg.blacklist and next(cfg.blacklist)
        and (cfg.showAllBuffs ~= false or cfg.hasDuration == true) then
        out = out or {}
        local ex = {}
        for id in pairs(cfg.blacklist) do ex[id] = true end
        out.excludeSpellIDs = ex
    end
    return out
end

-- Debuff-side twin of BuffCandidateExtras: "Has Duration" narrows every debuff
-- group (class groups AND the catch-all, via the same extras merge) to
-- duration-carrying debuffs with the native maxDuration check. math.huge never
-- trips the `>` half, so this excludes exactly the permanent (duration = 0)
-- debuffs. The inverse ("permanents only") is NOT expressible -- maxDuration is
-- the engine's only duration filter (Blizzard_AuraContainerUtil), so Has
-- Duration exists as a show-side AND-modifier only, never a hide-lane entry.
local function DebuffCandidateExtras(cfg)
    if not cfg then return nil end
    -- Max Duration (seconds) is the same gate with a real cap and implies Has
    -- Duration; nil = Unlimited = no extras at all (the candidate fingerprint
    -- sees the cap value, so edits re-declare like any payload change).
    local cap = cfg.maxDurSec or (cfg.hasDuration and math.huge) or nil
    local out
    if cap then
        out = { maxDuration = cap }
    end
    -- Hide Exhaustion (the Filters dropdown, off by default): the Bloodlust
    -- lockouts leave every group of the bar. They are never-secret, so the
    -- exclude works on the player. Fresh table: merged maps never alias the set.
    local sated = cfg.hideExhaustion == true and ns.UF_SatedDebuffs
    if sated then
        out = out or {}
        local ex = {}
        for id in pairs(sated) do ex[id] = true end
        out.excludeSpellIDs = ex
    end
    return out
end

-- Has Duration is an AND-MODIFIER (user directive 2026-08-16), not a broad
-- mode: it rides every chain link via DebuffCandidateExtras, so with class
-- filters checked it narrows exactly those. The catch-all only joins when
-- nothing narrower is selected -- All Debuffs on, or Has Duration checked with
-- no class filters picked (alone = every timed debuff).
local function DebuffCatchAllOn(cfg)
    if cfg.showAllDebuffs ~= false then return true end
    if cfg.hasDuration ~= true then return false end
    local cf = cfg.classFilters
    if cf then
        for _, v in pairs(cf) do
            if v == true then return false end
        end
    end
    return true
end

I.BuffCandidateExtras, I.BuildDispelColorMap = BuffCandidateExtras, BuildDispelColorMap
I.BuildStyle, I.DebuffCandidateExtras = BuildStyle, DebuffCandidateExtras
I.DebuffCatchAllOn, I.PV_DISPEL_ICON_ATLAS = DebuffCatchAllOn, PV_DISPEL_ICON_ATLAS
I.PV_DISPEL_ICON_POINTS, I.ResolveSortDirection = PV_DISPEL_ICON_POINTS, ResolveSortDirection
I.ResolveSortMethod, I.STYLE_BUFFS = ResolveSortMethod, STYLE_BUFFS
I.STYLE_DEBUFFS = STYLE_DEBUFFS
I.broken = false
