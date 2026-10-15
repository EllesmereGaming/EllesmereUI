if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookCustomBuffs.lua
--
--  UpdateCustomBuffBars and the aura-tracked custom buffs.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME = ns.ECME
local barDataByKey = ns.barDataByKey
local cdmBarFrames = ns.cdmBarFrames
local cdmBarIcons = ns.cdmBarIcons
local _, _playerClass = UnitClass("player")
local GetTime = GetTime

local ResolveSpellSettings, DecorateFrame, _AC = I.ResolveSpellSettings, I.DecorateFrame, I._AC
local _presetFrames, _customAuraTimers = I._presetFrames, I._customAuraTimers
local _pendingCastIDs, QueueCustomBuffUpdate = I._pendingCastIDs, I.QueueCustomBuffUpdate

-------------------------------------------------------------------------------
--  UpdateCustomBuffBars
--  Custom Aura bars use UNIT_SPELLCAST_SUCCEEDED to detect usage,
--  then show icon with hardcoded duration (reverse cooldown swipe).
--  (_customAuraTimers is declared earlier so the buff-phase injection in
--  CollectAndReanchor can read the same live timers.)
-------------------------------------------------------------------------------

-- Per-icon "Audio on Buff Gain" for self-timed preset/custom buffs (potions,
-- Bloodlust/Heroism, Light's Potential, user-added custom buff IDs). These never
-- fire Blizzard's TriggerAuraAppliedAlert (they appear on a cast/edge for a
-- fixed window), so the regular-buff apply-edge hook can't reach them; play the
-- SAME stored key (ss.buffActiveSoundKey) here, off the cast edge that
-- (re)starts the icon's timer. No loss sound: the real aura is secret/other-cast,
-- so only the gain edge is knowable. The id comes straight from the bar's
-- assignedSpells (clean, never secret), so the lookup is a direct spellSettings
-- hit, no GetCanonicalSpellIDForFrame dance. Gated 0-cost on ns._cdmAnyBuffSound
-- (same flag RescanBuffSoundFlag sets from these spellSettings) and throttled.
local _presetGainSoundAt = {}
local _presetLossSoundAt = {}
local PRESET_GAIN_SOUND_GAP = 0.3
local function PlayPresetBuffGainSound(sd, barKey, sid, now)
    if not ns._cdmAnyBuffSound then return end
    -- Loading screen / login settle: cast/edge timers restart across a zone/login,
    -- which would false-fire the gain sound. Drop while suppressed.
    if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
    -- Family store direct hit + bar-tier fallback (no frame: id from assignedSpells).
    local ss = ResolveSpellSettings(nil, sid, sd, barKey)
    local key = ss and ss.buffActiveSoundKey
    if not key or key == "none" then return end
    local last = _presetGainSoundAt[sid]
    if last and (now - last) < PRESET_GAIN_SOUND_GAP then return end
    _presetGainSoundAt[sid] = now
    local paths = ns.FOCUSKICK_SOUND_PATHS
    local path = paths and paths[key]
    if path then PlaySoundFile(path, "Master") end
end
-- Loss counterpart to PlayPresetBuffGainSound for self-timed preset/custom buffs
-- (no real aura-removed alert): fired when the displayed timer runs out. Separate
-- throttle table so gain/loss never suppress each other.
local function PlayPresetBuffLossSound(sd, sid, now)
    if not ns._cdmAnyBuffSound then return end
    if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
    local ss = sd and sd.spellSettings and sd.spellSettings[sid]
    local key = ss and ss.buffLostSoundKey
    if not key or key == "none" then return end
    local last = _presetLossSoundAt[sid]
    if last and (now - last) < PRESET_GAIN_SOUND_GAP then return end
    _presetLossSoundAt[sid] = now
    local paths = ns.FOCUSKICK_SOUND_PATHS
    local path = paths and paths[key]
    if path then PlaySoundFile(path, "Master") end
end

-------------------------------------------------------------------------------
--  Aura-tracked custom buffs (12.1). ONE engine flow container per bar: the
--  engine owns everything secret-derived, Lua declares only the id set and
--  the style; why they cannot join the bar's icon row is on _AC above the
--  collect passes. ENTRIES WITH A STORED DURATION ARE LEGACY CAST-TIMER
--  CUSTOMS AND NEVER REACH HERE. Styling reads the bar's own settings; glows
--  and per-spell overrides do not reach these icons, with one exception:
--  per-spell Custom Icon. A spell carrying one is split out of the shared
--  group into a single-spell group of its own, so every button in that group
--  is known to hold that spell without Lua ever reading the (secret) aura, and
--  its style paints the fixed art (_AC.ApplyExtra). Bars with no Custom Icon
--  keep the single shared group, byte-for-byte.
-------------------------------------------------------------------------------

-- Appearance fingerprint: the settings a restyle can carry. Geometry the engine
-- flow owns (size, shape, spacing, growth, ids) rebuilds instead, in _AC.Build.
function _AC.StyleSig(bd)
    if not bd then return "" end
    return table.concat({
        bd.iconShape or "none", bd.iconZoom or 0.08,
        bd.borderSize or 1, bd.borderR or 0, bd.borderG or 0, bd.borderB or 0,
        bd.borderA or 1, bd.borderTexture or "solid", bd.borderThickness or "thin",
        bd.borderSizePx or "",
        bd.borderClassColor and 1 or 0, bd.borderBehind and 1 or 0,
        bd.borderTextureOffset or 0, bd.borderTextureOffsetY or 0,
        bd.borderTextureShiftX or 0, bd.borderTextureShiftY or 0,
        bd.bgR or 0.08, bd.bgG or 0.08, bd.bgB or 0.08, bd.bgA or 0.6,
        bd.swipeAlpha or 0.7, bd.onlyShowNumbers and 1 or 0,
        ns.CdmDurationTextOn(bd) and 1 or 0, bd.cooldownFontSize or 12,
        bd.cooldownTextPosition or "center",
        bd.cooldownTextR or 1, bd.cooldownTextG or 1, bd.cooldownTextB or 1,
        bd.cooldownTextX or 0, bd.cooldownTextY or 0,
        bd.showChargeStackText ~= false and 1 or 0, bd.stackCountSize or 11,
        bd.stackCountR or 1, bd.stackCountG or 1, bd.stackCountB or 1,
        bd.stackCountX or 0, bd.stackCountY or 0,
        bd.stackCountPosition or "bottomright",
        bd.showTooltip and 1 or 0, bd.barStrata or "MEDIUM",
        (bd.anchorTo == "mouse") and 1 or 0,
    }, "|")
end

-- Countdown formatter for custom auras. Blizzard's own cooldown countdown --
-- what every other icon on the bar draws -- FLOORS the remaining time, so it
-- reads "0" through the last second; AuraKit's shared formatter rounds up and
-- read one higher beside it. Floor every unit to match. Built once (immutable,
-- shared by every bar); nil leaves AuraKit's formatter in place.
function _AC.DurationFormatter()
    if _AC.durFmtTried then return _AC.durFmt end
    _AC.durFmtTried = true
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Down = Enum.NumericRuleFormatRounding.Down
    local f = C_StringUtil.CreateNumericRuleFormatter()
    -- Thresholds sit ON each unit boundary: a floored value never crosses one,
    -- so none of the "just above the boundary" offsets the up-rounding
    -- formatters need apply here.
    local ok = pcall(f.SetBreakpoints, f, {
        { threshold = 0,     format = "%d",  step = 1, rounding = Down },
        { threshold = 60,    format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600,  format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
        { threshold = 86400, format = "%dd", step = 1, rounding = Down, components = { { div = 86400 } } },
    })
    if not ok then return nil end
    _AC.durFmt = f
    return f
end

-- Round to the nearest whole physical pixel -- the formula LayoutCDMBar uses for
-- the bar's own icons. PP.Scale (what the other AuraKit consumers use) truncates
-- instead, and lands a pixel short of the icon sitting next to this one.
function _AC.SnapPx(v)
    local onePx = EllesmereUI.PP and EllesmereUI.PP.mult
    if not onePx or onePx <= 0 then return v end
    return math.floor(v / onePx + 0.5) * onePx
end

-- The style a bar's custom auras render with. Read from the SAME bar settings
-- the bar's own icons use (RefreshCDMIconAppearance / ApplyShapeToCDMIcon) so a
-- custom aura and a Blizzard buff beside it look identical. AuraKit owns size,
-- crop, swipe and border; style.cdm carries what _AC.ApplyExtra draws on our own
-- regions (background, custom shape, text). PER-SPELL settings cannot reach here:
-- one engine group renders every custom aura on the bar and, while auras are
-- secret, Lua cannot tell which button holds which aura. The lone exception is
-- fixedIcon (a Custom Icon fileID), which only a single-spell group's style carries.
function _AC.BuildStyle(bd, fixedIcon)
    -- Snapped to the physical pixel grid, as LayoutCDMBar does for the bar's own
    -- icons: an unsnapped button renders a fraction off its neighbors at
    -- non-integral UI scales.
    local rawSZ = (bd and bd.iconSize) or 36
    local SZ = _AC.SnapPx(rawSZ)
    local zoom = (bd and bd.iconZoom) or 0.08
    local shape = (bd and bd.iconShape) or "none"
    -- Stock styles: full art, the style's ring instead of a border, no EUI
    -- shape (see the blizz block in _AC.ApplyExtra); Blizzard Style rounds
    -- the art with the viewer mask, Classic WoW UI keeps it square.
    local blizz = ns.CdmBlizzIcons()
    local classic = ns.CdmClassicIcons()
    if blizz then zoom = 0; shape = "none" end
    local customShape = (shape ~= "none" and shape ~= "cropped")
    local onlyNumbers = (bd and bd.onlyShowNumbers) and true or false
    local brdSize = (bd and bd.borderSize) or 1
    local brdR, brdG, brdB = (bd and bd.borderR) or 0, (bd and bd.borderG) or 0, (bd and bd.borderB) or 0
    if bd and bd.borderClassColor then
        local cc = _playerClass and RAID_CLASS_COLORS[_playerClass]
        if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end
    end
    local brdA = (bd and bd.borderA) or 1
    local cdFont = (EllesmereUI.GetFontPath("cdm"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

    -- Icon rect. A shaped icon samples OUTSIDE its texture to fill the mask, so
    -- the coords come from the shape's inset, not the bar's zoom -- same math as
    -- ApplyShapeToCDMIcon. Carried on the style (not written in ApplyExtra)
    -- because AuraKit re-applies texture coords on every restyle pass.
    local texCoord
    local SH = ns.CDM_SHAPES
    if shape == "cropped" then
        local trim = ns.CdmCropTrim(bd)
        texCoord = { zoom, 1 - zoom, zoom + trim, 1 - zoom - trim }
    elseif customShape and SH and SH.masks[shape] then
        local visRatio = (128 - 2 * (SH.insets[shape] or 17)) / 128
        local grow = ((1 / visRatio) - 1) * 0.5
        texCoord = { -grow, 1 + grow, -grow, 1 + grow }
    end

    -- Square border only where the bar's own icons draw one: a custom shape
    -- rings itself (_AC.ApplyExtra), Only Show Numbers strips the art entirely.
    local border
    if brdSize > 0 and not customShape and not onlyNumbers and not blizz then
        local brdTex = (bd and bd.borderTexture) or "solid"
        border = {
            brdR, brdG, brdB, brdA, size = brdSize,
            texture = brdTex,
            behind = (bd and bd.borderBehind) or nil,
            offsetX = bd and bd.borderTextureOffset, offsetY = bd and bd.borderTextureOffsetY,
            shiftX = bd and bd.borderTextureShiftX, shiftY = bd and bd.borderTextureShiftY,
            addonKey = "cdm", sizeKey = (bd and bd.borderThickness) or "thin",
            -- Exact size (borderSizePx); nil = the legacy step, as the bar's own icons.
            edgePx = EllesmereUI.BorderPx(bd and bd.borderSizePx, brdSize, brdTex),
        }
    end

    return {
        width = SZ,
        height = (shape == "cropped")
            and _AC.SnapPx(math.floor(rawSZ * ns.CdmCropFactor(bd) + 0.5)) or SZ,
        iconCrop = true, iconZoom = zoom,
        texCoord = texCoord,
        cooldownReverse = true,
        hideSwipe = onlyNumbers or nil,
        hideDurationText = (not ns.CdmDurationTextOn(bd)) or nil,
        durationFormatter = _AC.DurationFormatter(),
        -- Own text pipeline: the house icon-text rules (font, outline, slug) come
        -- from ApplyIconTextFont in _AC.ApplyExtra, exactly as the bar's icons do.
        noDefaultFonts = true,
        -- Tooltips follow the bar's Show Tooltip, except on a cursor-anchored
        -- bar: its icons stay mouse-through there, like the bar's own icons
        -- (a motion-enabled icon riding the cursor breaks [@mouseover] casts).
        noTooltips = (not (bd and bd.showTooltip) or (bd and bd.anchorTo == "mouse")) or nil,
        border = border,
        applyExtra = _AC.ApplyExtra,
        cdm = {
            font = cdFont, size = SZ, zoom = zoom,
            fixedIcon = fixedIcon,
            blizz = blizz or nil, classic = classic or nil,
            shape = shape, customShape = customShape,
            brdSize = brdSize, brdR = brdR, brdG = brdG, brdB = brdB, brdA = brdA,
            onlyNumbers = onlyNumbers,
            bgR = (bd and bd.bgR) or 0.08, bgG = (bd and bd.bgG) or 0.08,
            bgB = (bd and bd.bgB) or 0.08, bgA = (bd and bd.bgA) or 0.6,
            swipeAlpha = (bd and bd.swipeAlpha) or 0.7,
            durSize = (bd and bd.cooldownFontSize) or 12,
            durPos = (bd and bd.cooldownTextPosition) or "center",
            durX = (bd and bd.cooldownTextX) or 0, durY = (bd and bd.cooldownTextY) or 0,
            durR = (bd and bd.cooldownTextR) or 1, durG = (bd and bd.cooldownTextG) or 1,
            durB = (bd and bd.cooldownTextB) or 1,
            stackOn = (bd and bd.showChargeStackText) ~= false,
            stackSize = (bd and bd.stackCountSize) or 11,
            stackPos = (bd and bd.stackCountPosition) or "bottomright",
            stackX = (bd and bd.stackCountX) or 0, stackY = (bd and bd.stackCountY) or 0,
            stackR = (bd and bd.stackCountR) or 1, stackG = (bd and bd.stackCountG) or 1,
            stackB = (bd and bd.stackCountB) or 1,
        },
    }
end

-- Regions the CDM look needs that AuraKit does not build. Runs in the button's
-- creation window -- the only place a region may be parented to an engine aura
-- button. Everything here is ours, so _AC.ApplyExtra can write it under secrecy.
function _AC.InitExtra(button, d)
    d.cdmBg = button:CreateTexture(nil, "BACKGROUND")
    d.cdmBg:SetAllPoints(button)
    d.cdmMask = button:CreateMaskTexture()
    d.cdmMask:SetAllPoints(button)
    d.cdmMask:Hide()
    -- Shape ring draws over the swipe, below the dispel ring and text carrier.
    -- Levelled off the cooldown (always the button's own level) rather than the
    -- border host, whose level a "Show Behind" border drops below the button.
    d.cdmRingHost = CreateFrame("Frame", nil, button)
    d.cdmRingHost:SetAllPoints(button)
    d.cdmRingHost:EnableMouse(false)
    d.cdmRingHost:SetFrameLevel(d.cooldown:GetFrameLevel() + 2)
    d.cdmRing = d.cdmRingHost:CreateTexture(nil, "OVERLAY", nil, 6)
    d.cdmRing:SetAllPoints(d.cdmRingHost)
    d.cdmRing:SetSnapToPixelGrid(false)
    d.cdmRing:SetTexelSnappingBias(0)
    d.cdmRing:Hide()
    local AK = EllesmereUI.AuraKit
    local style = AK and d.styleKey and AK.styles[d.styleKey]
    -- Custom Icon art gets a texture of its own instead of a SetTexture on d.icon:
    -- the engine re-stamps the aura's art onto its registered icon on every update,
    -- so ApplyExtra hides d.icon and this takes its place. Anchored to d.icon so it
    -- follows every shape/zoom re-point without anchoring anything under secrecy.
    -- Creation time is enough: whether a spell has a Custom Icon is part of the
    -- structural signature, so a group's style never gains or loses fixedIcon
    -- without a rebuild. Only its value changes in place, and ApplyExtra re-reads it.
    if style and style.cdm and style.cdm.fixedIcon and d.icon then
        d.cdmFixedIcon = button:CreateTexture(nil, "ARTWORK", nil, 1)
        d.cdmFixedIcon:SetAllPoints(d.icon)
    end
    -- Stock style regions: the ring overlay (on the ring host, above the
    -- swipe) and, under Blizzard Style, the viewer's rounded mask (Classic
    -- WoW UI icons are square). Whether a style is on is a reload-gated
    -- profile flag, so it is fixed for the button's whole life.
    if style and style.cdm and style.cdm.blizz then
        if not style.cdm.classic then
            d.cdmBlizzMask = button:CreateMaskTexture()
            d.cdmBlizzMask:SetAtlas(ns.CDM_BLIZZ_MASK)
            d.cdmBlizzMask:SetAllPoints(button)
        end
        d.cdmBlizzOverlay = d.cdmRingHost:CreateTexture(nil, "OVERLAY", nil, 5)
        if style.cdm.classic then
            d.cdmBlizzOverlay:SetTexture(ns.CDM_CLASSIC_RING)
        else
            ns.CdmStockAtlas(d.cdmBlizzOverlay, ns.CDM_BLIZZ_OVERLAY)
        end
        d.cdmBlizzOverlay:SetSnapToPixelGrid(false)
        d.cdmBlizzOverlay:SetTexelSnappingBias(0)
    end
    -- AuraKit runs applyExtra BEFORE this creation hook, so the pass that draws
    -- these regions has to run once more now that they exist.
    if style then _AC.ApplyExtra(button, d, style) end
end

-- Re-seat a mask reference. AddMaskTexture is additive, so the drop always
-- runs first or a re-apply stacks the same mask twice.
function _AC.SetMask(region, mask, want)
    if not region then return end
    pcall(region.RemoveMaskTexture, region, mask)
    if want then pcall(region.AddMaskTexture, region, mask) end
end

-- Background, custom shape and text, on our own regions. Anchors use
-- d.borderHost (created SetAllPoints(button) in the creation window) rather than
-- the button: a SetPoint whose relative frame is the button is denied while
-- auras are secret, which is exactly when a settings change must still land.
function _AC.ApplyExtra(button, d, style)
    local c = style.cdm
    if not c then return end
    local PP = EllesmereUI.PP

    -- Only Show Numbers strips the art down to the countdown. Shown-state as
    -- well as alpha, the same pair ApplyOnlyNumbers uses on the bar's own icons:
    -- a texture's alpha and its vertex color share one slot on this client.
    -- A Custom Icon group hides the engine's art the same way and shows its own
    -- texture (d.cdmFixedIcon, see InitExtra) in its place.
    local fixed = c.fixedIcon and d.cdmFixedIcon
    local artOn = not c.onlyNumbers
    local engineArtOn = artOn and not fixed
    if d.icon then
        d.icon:SetAlpha(engineArtOn and 1 or 0)
        d.icon:SetShown(engineArtOn)
        -- Cropped samples a heavy vertical slice, and a snapped image edge can
        -- round to a different physical pixel than the unsnapped swipe (the 1px
        -- split ApplyShapeToCDMIcon disables snapping for). Restored otherwise.
        if d.icon.SetSnapToPixelGrid then
            d.icon:SetSnapToPixelGrid(c.shape ~= "cropped")
        end
        if c.shape == "cropped" and d.icon.SetTexelSnappingBias then
            d.icon:SetTexelSnappingBias(0)
        end
    end
    if fixed then
        fixed:SetTexture(c.fixedIcon)
        -- The crop AuraKit's ApplyStyleToRegions gives d.icon from this same style.
        local tc = style.texCoord
        if tc then
            fixed:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        elseif style.iconCrop then
            local z = style.iconZoom or 0.07
            fixed:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            fixed:SetTexCoord(0, 1, 0, 1)
        end
        if fixed.SetSnapToPixelGrid then
            fixed:SetSnapToPixelGrid(c.shape ~= "cropped")
        end
        if c.shape == "cropped" and fixed.SetTexelSnappingBias then
            fixed:SetTexelSnappingBias(0)
        end
        fixed:SetAlpha(artOn and 1 or 0)
        fixed:SetShown(artOn)
    end
    if d.cdmBg then
        -- Blizzard Style has no EUI background (hidden once below, never
        -- shown here first).
        if c.onlyNumbers or c.blizz then
            d.cdmBg:Hide()
        else
            d.cdmBg:SetColorTexture(c.bgR, c.bgG, c.bgB, c.bgA)
            d.cdmBg:Show()
        end
    end
    if d.cooldown then d.cooldown:SetSwipeColor(0, 0, 0, c.swipeAlpha) end

    -- Custom shape: mask on icon/background/swipe plus the shape's own ring,
    -- mirroring ApplyShapeToCDMIcon so both renderers land on the same geometry.
    local SH = ns.CDM_SHAPES
    local mask, ring = d.cdmMask, d.cdmRing
    local maskPath = (c.customShape and SH and not c.onlyNumbers) and SH.masks[c.shape] or nil
    local shapeKey = maskPath
        and (c.shape .. "|" .. c.zoom .. "|" .. c.brdSize .. "|" .. c.size) or ""
    if d.cdmShapeKey ~= shapeKey and mask then
        if maskPath then
            mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:Show()
            _AC.SetMask(d.icon, mask, true)
            _AC.SetMask(d.cdmFixedIcon, mask, true)
            _AC.SetMask(d.cdmBg, mask, true)
            _AC.SetMask(d.cooldown, mask, true)
            local exp = SH.iconExpand + (SH.iconExpandOffsets[c.shape] or 0)
                + ((c.zoom - (SH.zoomDefaults[c.shape] or 0.06)) * 200)
            if exp < 0 then exp = 0 end
            local half = exp / 2
            if d.icon then
                d.icon:ClearAllPoints()
                PP.Point(d.icon, "TOPLEFT", d.borderHost, "TOPLEFT", -half, half)
                PP.Point(d.icon, "BOTTOMRIGHT", d.borderHost, "BOTTOMRIGHT", half, -half)
            end
            mask:ClearAllPoints()
            if c.brdSize >= 1 then
                PP.Point(mask, "TOPLEFT", d.borderHost, "TOPLEFT", 1, -1)
                PP.Point(mask, "BOTTOMRIGHT", d.borderHost, "BOTTOMRIGHT", -1, 1)
            else
                mask:SetAllPoints(d.borderHost)
            end
            if d.cooldown then
                pcall(d.cooldown.SetSwipeTexture, d.cooldown, maskPath)
                if d.cooldown.SetUseCircularEdge then
                    pcall(d.cooldown.SetUseCircularEdge, d.cooldown,
                        c.shape ~= "square" and c.shape ~= "csquare")
                end
                if d.cooldown.SetEdgeScale then
                    pcall(d.cooldown.SetEdgeScale, d.cooldown, SH.edgeScales[c.shape] or 0.60)
                end
            end
        else
            _AC.SetMask(d.icon, mask)
            _AC.SetMask(d.cdmFixedIcon, mask)
            _AC.SetMask(d.cdmBg, mask)
            _AC.SetMask(d.cooldown, mask)
            mask:SetTexture(nil); mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001); mask:Hide()
            if d.icon then
                d.icon:ClearAllPoints()
                d.icon:SetAllPoints(d.borderHost)
            end
            if d.cooldown then
                pcall(d.cooldown.SetSwipeTexture, d.cooldown, "Interface\\AddOns\\EllesmereUI\\media\\white-square.png")
                if d.cooldown.SetUseCircularEdge then
                    pcall(d.cooldown.SetUseCircularEdge, d.cooldown, false)
                end
            end
        end
        d.cdmShapeKey = shapeKey
    end
    -- Ring color follows the border color on every pass, so a color-only change
    -- lands without re-running the geometry above. Border Size 0 drops the ring,
    -- as it does on the bar's own shaped icons.
    if ring then
        local ringPath = (maskPath and c.brdSize > 0) and SH.borders[c.shape] or nil
        if ringPath then
            ring:SetTexture(ringPath)
            ring:SetVertexColor(c.brdR, c.brdG, c.brdB, c.brdA)
            ring:Show()
        else
            ring:Hide()
        end
    end

    -- Stock styles: ring overlay sized to the button (the same geometry as
    -- the bar's own icons) and no EUI background; Blizzard Style also seats
    -- the rounded viewer mask on the art and the viewer's rounded swipe
    -- (Classic WoW UI keeps the square art and swipe). Anchored to
    -- d.borderHost like the shape geometry above (button-relative points are
    -- denied under secrecy). Geometry is memoized on the button size.
    if c.blizz and d.cdmBlizzOverlay then
        if d.cdmBg then d.cdmBg:Hide() end
        local bKey = "blizz|" .. c.size
        if d.cdmBlizzKey ~= bKey then
            d.cdmBlizzKey = bKey
            local ov = d.cdmBlizzOverlay
            if c.classic then
                ns.CdmPlaceClassicRing(ov, d.borderHost, c.size, c.size)
            else
                _AC.SetMask(d.icon, d.cdmBlizzMask, true)
                _AC.SetMask(d.cdmFixedIcon, d.cdmBlizzMask, true)
                ov:ClearAllPoints()
                PP.Point(ov, "TOPLEFT", d.borderHost, "TOPLEFT", -c.size * ns.CDM_BLIZZ_RING_X, c.size * ns.CDM_BLIZZ_RING_Y)
                PP.Point(ov, "BOTTOMRIGHT", d.borderHost, "BOTTOMRIGHT", c.size * ns.CDM_BLIZZ_RING_X, -c.size * ns.CDM_BLIZZ_RING_Y)
                if d.cooldown then pcall(d.cooldown.SetSwipeTexture, d.cooldown, ns.CDM_BLIZZ_SWIPE) end
            end
        end
        d.cdmBlizzOverlay:SetShown(artOn)
    end

    if d.duration then
        local fKey = c.font .. "|" .. c.durSize
        if d.cdmDurFont ~= fKey then
            d.cdmDurFont = fKey
            EllesmereUI.ApplyIconTextFont(d.duration, c.font, c.durSize, "cdm")
        end
        local aKey = c.durPos .. "|" .. c.durX .. "|" .. c.durY
        if d.cdmDurAnchor ~= aKey then
            d.cdmDurAnchor = aKey
            ns.AnchorCooldownText(d.duration, d.borderHost, c.durPos, c.durX, c.durY)
        end
        d.duration:SetTextColor(c.durR, c.durG, c.durB)
    end

    if d.stack then
        local fKey = c.font .. "|" .. c.stackSize
        if d.cdmStackFont ~= fKey then
            d.cdmStackFont = fKey
            EllesmereUI.ApplyIconTextFont(d.stack, c.font, c.stackSize, "cdm")
        end
        local aKey = c.stackPos .. "|" .. c.stackX .. "|" .. c.stackY
        if d.cdmStackAnchor ~= aKey then
            d.cdmStackAnchor = aKey
            local pt, y = ns.CdmStackAnchorPoint(c.stackPos, c.stackY)
            d.stack:ClearAllPoints()
            d.stack:SetPoint(pt, d.borderHost, pt, c.stackX, y)
        end
        d.stack:SetTextColor(c.stackR, c.stackG, c.stackB)
        -- Alpha, not Hide: the engine re-shows this font string whenever the
        -- slot's application count refreshes.
        d.stack:SetAlpha(c.stackOn and 1 or 0)
    end
end

-- Add every id form the live aura can carry (typed + override + base) to map.
function _AC.AddSpellForms(map, sid)
    map[sid] = true
    local ovr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
        and C_SpellBook.FindSpellOverrideByID(sid)
    if ovr and ovr > 0 then map[ovr] = true end
    local base = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(sid)
    if base and base > 0 then map[base] = true end
    return map
end

function _AC.FixedIconStyleKey(barKey, sid)
    return "cdm:aurabuff:" .. barKey .. ":ci:" .. sid
end

-- A new fileID for a spell that already has its own group is appearance, not
-- structure: restyle that group in place. A rebuild would abandon the old
-- container, whose engine-created group buttons can never be freed
-- (AK.ReleaseContainer), so re-picking an icon must not cost one.
function _AC.SyncFixedIcons(rec, bd, cis)
    local styles = rec.ciStyles
    if not (styles and cis) then return end
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.styles) then return end
    for sid, ci in pairs(cis) do
        local key = _AC.FixedIconStyleKey(bd.key, sid)
        local cur = styles[key]
        if cur and cur ~= ci then
            styles[key] = ci
            AK.styles[key] = _AC.BuildStyle(bd, ci)
            if AK.RestyleSoon then AK.RestyleSoon(key) end
        end
    end
end

-- cis: optional sid -> Custom Icon fileID for the entries that carry one.
function _AC.Build(rec, barKey, bd, sids, sig, cis)
    local AK = EllesmereUI.AuraKit
    local barFrame = cdmBarFrames[barKey]
    -- Bar not built yet (login race): bail WITHOUT stamping the signature;
    -- the next tracking sync re-queues the build.
    if not (AK and AK.CreateContainerShell and AK.AddGroupToContainer and barFrame) then return end
    local styleKey = "cdm:aurabuff:" .. barKey
    AK.styles[styleKey] = _AC.BuildStyle(bd)
    rec.styleSig = _AC.StyleSig(bd)
    -- Retire the previous generation properly (the holder is reused).
    if rec.container and AK.ReleaseContainer then AK.ReleaseContainer(rec.container) end
    local holder = rec.holder
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(1, 1)
        holder:EnableMouse(false)
        rec.holder = holder
    end
    holder:SetFrameStrata((bd and bd.barStrata) or "MEDIUM")
    holder:Show()
    -- ONE flow group carrying every id form the live aura can carry (typed
    -- + override + base): the engine compacts actives and renders nothing
    -- when none are up. A spell with a Custom Icon gets a single-spell group
    -- instead, flowing after the shared one. Its forms are struck from the
    -- shared map, so an id it shares with a plain entry (the add-time variant
    -- dedup rules that out, but overrides move with talents) renders once.
    local includeMap, nShared = {}, 0
    local ciGroups, claimed
    for i = 1, #sids do
        local sid = sids[i]
        local ci = cis and cis[sid]
        if ci then
            local forms = _AC.AddSpellForms({}, sid)
            claimed = claimed or {}
            for id in pairs(forms) do claimed[id] = true end
            ciGroups = ciGroups or {}
            ciGroups[#ciGroups + 1] = { sid = sid, ci = ci, forms = forms }
        else
            nShared = nShared + 1
            _AC.AddSpellForms(includeMap, sid)
        end
    end
    if claimed then
        for id in pairs(claimed) do includeMap[id] = nil end
    end
    local vertical = (bd and bd.verticalOrientation) and true or false
    local gap = (bd and bd.spacing) or 2
    local grow = (bd and bd.growDirection) or "CENTER"
    -- Container point mirrors _AC.Anchor's holder placement: the tail
    -- always flows AWAY from the bar's end (end-of-bar for all growths).
    local pt
    if vertical then
        pt = (grow == "UP") and "BOTTOM" or "TOP"
    elseif grow == "LEFT" then
        pt = "RIGHT"
    else
        pt = "LEFT"
    end
    local container = AK.CreateContainerShell(holder, { point = { pt } })
    rec.pt = pt
    rec.curPt = pt
    if AK.SetContainerAxis then AK.SetContainerAxis(container, vertical) end
    -- Group keys in flow order. The shared group is skipped when nothing is left
    -- in its map: an EMPTY includeSpellIDs would not narrow the HELPFUL filter.
    local groupKeys = {}
    if nShared > 0 and next(includeMap) then
        AK.AddGroupToContainer(container, {
            key = "spells",
            filter = { "HELPFUL" },
            style = styleKey,
            extraInit = _AC.InitExtra,
            maxFrameCount = nShared,
            -- Helpful spellID includes on the player pass the identity gate
            -- regardless of the spell's secrecy flag.
            candidateFilters = { includeSpellIDs = includeMap },
        })
        groupKeys[#groupKeys + 1] = "spells"
    end
    -- Custom Icon groups: one style per spell, since the fixed art is the one
    -- thing that differs from the shared style. Kept on rec.ciStyles so a restyle
    -- (RefreshAuraCustomStyle) reaches them too. Cost: every AddAuraGroup mints
    -- a 10-button engine batch that is never released, so each split spell is
    -- ten more buttons per container build -- which is why a file-id change
    -- restyles in place (SyncFixedIcons) instead of rebuilding.
    local ciStyles
    if ciGroups then
        ciStyles = {}
        for i = 1, #ciGroups do
            local g = ciGroups[i]
            local ciStyleKey = _AC.FixedIconStyleKey(barKey, g.sid)
            AK.styles[ciStyleKey] = _AC.BuildStyle(bd, g.ci)
            ciStyles[ciStyleKey] = g.ci
            local gKey = "ci:" .. g.sid
            AK.AddGroupToContainer(container, {
                key = gKey,
                filter = { "HELPFUL" },
                style = ciStyleKey,
                extraInit = _AC.InitExtra,
                maxFrameCount = 1,
                candidateFilters = { includeSpellIDs = g.forms },
            })
            groupKeys[#groupKeys + 1] = gKey
        end
    end
    -- Drop the styles of Custom Icon groups this build no longer has. Their old
    -- buttons stay registered under the key (group buttons are never released),
    -- and AuraKit skips a key with no style, so nothing restyles them again.
    if rec.ciStyles then
        for oldKey in pairs(rec.ciStyles) do
            if not (ciStyles and ciStyles[oldKey]) then AK.styles[oldKey] = nil end
        end
    end
    rec.ciStyles = ciStyles
    if container.SetAuraGroupLayout then
        -- elementWidth/Height feed the engine's flow math (the style sizes the
        -- button itself). Without them the flow spaces icons at the engine
        -- default, so any bar not at that size overlaps or gaps -- and a cropped
        -- bar, whose buttons are shorter (ns.CdmCropFactor), is off on both axes. Every group
        -- shares one layout: their styles differ only in the fixed art.
        local st = AK.styles[styleKey]
        local gapPx = _AC.SnapPx(gap)
        local layout = {
            elementWidth = st and st.width, elementHeight = st and st.height,
            elementSpacing = gapPx, lineSpacing = gapPx,
            groupSpacing = gapPx, groupLineSpacing = gapPx,
        }
        for i = 1, #groupKeys do
            container:SetAuraGroupLayout(groupKeys[i], layout)
        end
    end
    AK.FinishContainer(container, "player")
    rec.container = container
    rec.sig, rec.sids = sig, sids
    rec.bdRef = bd
    -- Follow the bar's rect from OUR frame's own change signals (post-hook
    -- + scripts): the holder re-derives its position one coalesced frame
    -- after any bar move/resize/visibility change.
    if rec.hookedBar ~= barFrame then
        rec.hookedBar = barFrame
        local function poke() _AC.MarkSync(barKey) end
        hooksecurefunc(barFrame, "SetPoint", poke)
        barFrame:HookScript("OnSizeChanged", poke)
        barFrame:HookScript("OnShow", poke)
        barFrame:HookScript("OnHide", poke)
    end
    _AC.Anchor(barKey, rec)
end


local function UpdateCustomBuffBars()
    if not ECME then return end
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end
    local LayoutCDMBar = ns.LayoutCDMBar
    local RefreshCDMIconAppearance = ns.RefreshCDMIconAppearance
    local cdmPageOpen = ns._cdmBarsPageOpen or false
    local now = GetTime()

    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled and barData.barType == "custom_buff" then
            local barKey = barData.key
            local container = cdmBarFrames[barKey]
            if container then
                local sd = ns.GetBarSpellData(barKey)
                local spellList = sd and sd.assignedSpells or {}
                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local count = 0

                for _, sid in ipairs(spellList) do
                    if type(sid) == "number" and sid > 0 then
                        local duration = sd.spellDurations and sd.spellDurations[sid] or 0
                        if duration > 0 then
                            local timerKey = barKey .. ":" .. sid
                            local timer = _customAuraTimers[timerKey]

                            if _pendingCastIDs[sid] and duration > 0 then
                                _customAuraTimers[timerKey] = {
                                    start = now,
                                    duration = duration,
                                }
                                timer = _customAuraTimers[timerKey]
                                PlayPresetBuffGainSound(sd, barKey, sid, now)
                            end

                            -- Loss edge: displayed timer ran out -> fire once, drop it.
                            if timer and (now - timer.start) >= timer.duration then
                                PlayPresetBuffLossSound(sd, sid, now)
                                _customAuraTimers[timerKey] = nil
                                timer = nil
                            end

                            local isActive = timer and duration > 0
                                and (now - timer.start) < timer.duration

                            if isActive or cdmPageOpen then
                                local fkey = barKey .. ":custombuff:" .. sid
                                local f = _presetFrames[fkey]
                                if not f then
                                    f = CreateFrame("Frame", nil, UIParent)
                                    f:SetSize(36, 36); f:Hide()
                                    f:EnableMouse(false)
                                    local tex = f:CreateTexture(nil, "ARTWORK")
                                    tex:SetAllPoints(); ns.CdmOwnIconCrop(tex)
                                    f.Icon = tex; f._tex = tex
                                    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                    cd:SetHideCountdownNumbers(not ns.CdmDurationTextOn(barData))
                                    cd:SetReverse(true)
                                    f.Cooldown = cd; f._cooldown = cd
                                    f._isCustomSpellFrame = true
                                    f._isCustomBuffFrame = true
                                    f.cooldownID = nil; f.cooldownInfo = nil
                                    f.layoutIndex = 99999
                                    _presetFrames[fkey] = f
                                    cd:HookScript("OnCooldownDone", function()
                                        C_Timer.After(0, QueueCustomBuffUpdate)
                                    end)
                                    local iconSID = ns.LustPresetIconSpellID
                                        and ns.LustPresetIconSpellID(sid) or sid
                                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconSID)
                                    if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                                end
                                if isActive and timer then
                                    f._cooldown:SetCooldown(timer.start, timer.duration)
                                else
                                    f._cooldown:Clear()
                                end
                                DecorateFrame(f, barData); f:Show()
                                -- A frame (re)shown while its bar is visibility-hidden must not
                                -- come back at its last alpha: only listed icons get the hide
                                -- pass, and this one may have been unlisted (inactive) then.
                                f:SetAlpha(container._visHidden and 0
                                    or ((ns.EffectiveBarAlpha and ns.EffectiveBarAlpha(barData)) or 1))
                                f:EnableMouse(false)
                                if f.Cooldown and f.Cooldown.SetDrawSwipe then
                                    -- Only Show Numbers hides the swipe with the icon art.
                                    f.Cooldown:SetDrawSwipe(not barData.onlyShowNumbers)
                                end
                                count = count + 1
                                icons[count] = f
                            else
                                local fkey = barKey .. ":custombuff:" .. sid
                                local f = _presetFrames[fkey]
                                if f then f:Hide() end
                                if timer and not isActive then
                                    _customAuraTimers[timerKey] = nil
                                end
                            end
                        end
                    end
                end

                for i = count + 1, #icons do
                    if icons[i] then icons[i]:Hide() end
                    icons[i] = nil
                end

                -- Custom aura bars are display-only, never clickable
                container:EnableMouse(false)
                if container.EnableMouseClicks then container:EnableMouseClicks(false) end
                if container.EnableMouseMotion then pcall(container.EnableMouseMotion, container, false) end

                local prevCount = container._prevVisibleCount or 0
                if count ~= prevCount then
                    if RefreshCDMIconAppearance then RefreshCDMIconAppearance(barKey) end
                    if LayoutCDMBar then LayoutCDMBar(barKey) end
                end
                container._prevVisibleCount = count
            end
        end
    end

    -- Buff-family bars: custom/preset buffs are injected + rendered by
    -- CollectAndReanchor's buff phase. Here we only run cast detection: when a
    -- pending cast matches a custom buff on a buff bar, (re)start its timer and
    -- queue a reanchor so the icon appears. Expiry is handled by the frame's
    -- OnCooldownDone hook (which also reanchors to drop the icon).
    local needBuffReanchor = false
    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled and barData.barType == "buffs" then
            local sd = ns.GetBarSpellData(barData.key)
            local spellList = sd and sd.assignedSpells
            local durs = sd and sd.spellDurations
            if spellList and durs then
                for _, sid in ipairs(spellList) do
                    if type(sid) == "number" and sid > 0 and (durs[sid] or 0) > 0 then
                        local tkey = barData.key .. ":" .. sid
                        if _pendingCastIDs[sid] then
                            _customAuraTimers[tkey] = {
                                start = now, duration = durs[sid],
                            }
                            needBuffReanchor = true
                            PlayPresetBuffGainSound(sd, barData.key, sid, now)
                        else
                            -- Loss edge: displayed window ran out -> fire once, drop timer.
                            local t = _customAuraTimers[tkey]
                            if t and (now - t.start) >= t.duration then
                                PlayPresetBuffLossSound(sd, sid, now)
                                _customAuraTimers[tkey] = nil
                                needBuffReanchor = true
                            end
                        end
                    end
                end
            end
        end
    end
    if needBuffReanchor and ns.QueueReanchor then ns.QueueReanchor() end

    wipe(_pendingCastIDs)
end
ns.UpdateCustomBuffBars = UpdateCustomBuffBars

-- Sync pass for aura-tracked custom buffs, run from the rebuild tails and
-- the picker add flows. Collects each bar's no-duration custom ids, and
-- (re)builds that bar's engine tail container ONLY when the signature --
-- the id list plus the baked styling inputs -- changes. Containers for
-- bars that no longer have aura customs are hidden (dormant, zero cost).
function ns.UpdateCustomBuffAuraTracking()
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    local seen = {}
    if bars then
        for _, bd in ipairs(bars) do
            if bd.enabled and (bd.barType == "custom_buff" or bd.barType == "buffs") then
                local sd = ns.GetBarSpellData and ns.GetBarSpellData(bd.key)
                local list = sd and sd.assignedSpells
                local tags = sd and sd.customSpellIDs
                if list and tags then
                    local durs = sd.spellDurations
                    local sids
                    for _, sid in ipairs(list) do
                        if type(sid) == "number" and sid > 0 and tags[sid]
                           and (not durs or (durs[sid] or 0) <= 0) then
                            sids = sids or {}
                            sids[#sids + 1] = sid
                        end
                    end
                    if sids then
                        seen[bd.key] = true
                        -- Which spells carry a per-spell Custom Icon is structural:
                        -- each gets a group of its own. The fileID itself is not --
                        -- it restyles in place (_AC.SyncFixedIcons). Resolved only
                        -- once anyone has set one (monotonic gate); everyone else
                        -- keeps the exact signature they had and pays nothing for it.
                        local cis, ciSig
                        if ns._cdmAnyCustomIcon then
                            for i = 1, #sids do
                                local sid = sids[i]
                                local ss = ResolveSpellSettings(nil, sid, sd, bd.key)
                                local ci = ss and ss.customIcon
                                if type(ci) == "number" and ci > 0 then
                                    cis = cis or {}
                                    cis[sid] = ci
                                    ciSig = (ciSig or "|ci") .. ":" .. sid
                                end
                            end
                        end
                        -- Structural only: the id list plus the geometry the
                        -- engine flow owns. Everything else is appearance and
                        -- rides ns.RefreshAuraCustomStyle without a rebuild.
                        local sig = table.concat(sids, ":")
                            .. "|" .. tostring(bd.iconSize or 36)
                            .. "|" .. tostring(bd.iconShape or "none")
                            .. "|" .. tostring(bd.growDirection or "CENTER")
                            .. "|" .. (bd.verticalOrientation and 1 or 0)
                            .. "|" .. tostring(bd.spacing or 2)
                            -- Adjust Crop changes the button height the flow lays out, so it
                            -- is geometry. Appended only while cropped: every other bar keeps
                            -- its exact signature.
                            .. ((bd.iconShape == "cropped") and ("|crop" .. ns.CdmCropPercent(bd)) or "")
                            .. (ciSig or "")
                        local rec = _AC.bars[bd.key]
                        if not rec then rec = {}; _AC.bars[bd.key] = rec end
                        rec.bdRef = bd
                        if rec.sig ~= sig and not rec.queued then
                            local AK = EllesmereUI.AuraKit
                            if AK and AK.QueueBuildJob then
                                rec.queued = true
                                local barKey, bdRef, sidsRef, sigRef, cisRef = bd.key, bd, sids, sig, cis
                                AK.QueueBuildJob(function()
                                    rec.queued = nil
                                    _AC.Build(rec, barKey, bdRef, sidsRef, sigRef, cisRef)
                                    -- The job captured the id list as it was when
                                    -- it was queued. A change that landed while it
                                    -- was in flight (two adds in a row) is not in
                                    -- what it just built, and stamping rec.sig hides
                                    -- it from every later compare -- so re-sync once
                                    -- here instead of losing the spell until a reload.
                                    if rec.resync then
                                        rec.resync = nil
                                        ns.UpdateCustomBuffAuraTracking()
                                    end
                                end, "cdm:aurabuff-shell")
                            end
                        elseif rec.queued and rec.sig ~= sig then
                            rec.resync = true
                        else
                            _AC.SyncFixedIcons(rec, bd, cis)
                            ns.RefreshAuraCustomStyle(bd.key)
                        end
                    end
                end
            end
        end
    end
    for barKey, rec in pairs(_AC.bars) do
        if not seen[barKey] and rec.sids then
            -- Bar lost its aura customs: hide the holder, release the
            -- engine container, forget the build.
            if rec.holder then rec.holder:Hide() end
            local AK = EllesmereUI.AuraKit
            if rec.container and AK and AK.ReleaseContainer then
                AK.ReleaseContainer(rec.container)
            end
            rec.container = nil
            rec.sig = nil
            rec.sids = nil
            rec.styleSig = nil
            if rec.ciStyles and AK and AK.styles then
                for oldKey in pairs(rec.ciStyles) do AK.styles[oldKey] = nil end
            end
            rec.ciStyles = nil
        end
    end
end

-- Re-apply a bar's appearance to its custom-aura icons. Called from every CDM
-- restyle path, so an options change lands on them the same frame it lands on
-- the bar's own icons instead of waiting for a reload or a spec swap. Free for
-- bars with no custom auras (one table lookup) and a no-op when nothing the
-- style reads has changed.
function ns.RefreshAuraCustomStyle(barKey)
    local rec = barKey and _AC.bars[barKey]
    if not (rec and rec.container) then return end
    local bd = barDataByKey[barKey]
    if not bd then return end
    rec.bdRef = bd
    local sig = _AC.StyleSig(bd)
    if rec.styleSig == sig then return end
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.styles) then return end
    if rec.holder then rec.holder:SetFrameStrata(bd.barStrata or "MEDIUM") end
    local styleKey = "cdm:aurabuff:" .. barKey
    AK.styles[styleKey] = _AC.BuildStyle(bd)
    if AK.RestyleSoon then AK.RestyleSoon(styleKey) end
    -- Custom Icon groups carry the same appearance under their own style keys.
    if rec.ciStyles then
        for ciStyleKey, ci in pairs(rec.ciStyles) do
            AK.styles[ciStyleKey] = _AC.BuildStyle(bd, ci)
            if AK.RestyleSoon then AK.RestyleSoon(ciStyleKey) end
        end
    end
    -- Stamped only once the style is actually installed: recording a style that
    -- never applied would make every later call with the same settings early-out.
    rec.styleSig = sig
end

I.UpdateCustomBuffBars = UpdateCustomBuffBars
I.broken = false
