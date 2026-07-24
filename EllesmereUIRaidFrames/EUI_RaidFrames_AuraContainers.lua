-- EUI_RaidFrames_AuraContainers.lua
-- 12.1 aura containers for raid/party/extra unit buttons. Step 1: debuff
-- icons (legacy UpdateDebuffs is gated off via ns.RFC_OwnsDebuffs).
--
-- Lifecycle facts this file relies on (verified): every unit button is
-- created OUT OF COMBAT (headers pre-create their full complement via the
-- startingIndex trick; extra-frame builds are combat-gated), so containers
-- are created at StyleButton time and re-pointed from the existing
-- OnAttributeChanged("unit") watch. All aura visuals anchor to the health
-- bar, sizes come from the live-scaled proxies (never raw db.profile), and
-- per-button state lives in the external FFD table (never on the button).

local _, ns = ...

-- 12.1 ONLY: on a 12.0 client this whole file is inert -- nothing below
-- (ownership flags, event frames, styles) may execute, or every legacy
-- raid-frame aura renderer goes dark with nothing replacing it.
if not (EllesmereUI and EllesmereUI.IS_121) then return end

local AK -- EllesmereUI.AuraKit, resolved at first use
local FALLBACK_FONT = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

-- Marks debuff rendering as container-owned; the legacy UpdateDebuffs body
-- early-returns on this flag (single gate covering all seven call sites).
ns.RFC_OwnsDebuffs = true
ns.RFC_OwnsDefensives = true
ns.RFC_OwnsDispel = true
ns.RFC_OwnsBM = true -- both BM display modes (custom slots/chains + simple grid group)

-- 12.1 redesign (Auras tab retired): the standalone defensives/externals
-- row no longer renders -- the Buff Manager owns those displays. The flag
-- keeps every def-container build/config site inert without deleting the
-- machinery (flip to nil to resurrect for comparison testing).
ns.RFC_DefensivesRetired = true

-- Migration scaffolding: the NOT-yet-migrated legacy aura paths (defensives,
-- dispel border, BuffManager) hard-error while auras are secret, and those
-- errors abort shared handler chains (unit assignment, full-update loops),
-- breaking even the migrated displays. Until each path migrates, they skip
-- silently under restrictions (they rendered nothing in combat anyway once
-- the errors hit). Probe result is cached per frame time.
-- Asymmetric cache (see AK.AurasRestricted): only the restricted answer
-- caches -- a stale "unrestricted" would let legacy paths run into
-- hard-erroring scans on restriction edges; a stale "restricted" just
-- skips them for one frame.
local restrictedStamp = -1
function ns.RFC_LegacyAuraGuard()
    local now = GetTime()
    if now == restrictedStamp then return true end
    if pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL") then
        return false
    end
    restrictedStamp = now
    return true
end

local SATED_DEBUFFS = {
    [57723] = true, [57724] = true, [80354] = true, [95809] = true,
    [160455] = true, [264689] = true, [390435] = true,
}
local ALWAYS_HIDE_DEBUFFS = { [1254550] = true, [308312] = true }
-- Shared with the Debuff Manager file (same exclude semantics there).
ns.RFC_SatedDebuffs = SATED_DEBUFFS
ns.RFC_AlwaysHideDebuffs = ALWAYS_HIDE_DEBUFFS

-- The "raid" preset is a union (RAID or RAID_IN_COMBAT), so the container
-- declares both as negation-chained groups; presets enable groups by count,
-- no container swapping needed (the group set is fixed across presets).
-- The "cc" group renders crowd-control debuffs (declared FIRST so they
-- lead the row) and carries the CC Debuff Glow via its style; the preset
-- groups negate CROWD_CONTROL so a CC aura never renders twice. Delta vs
-- legacy: CC debuffs now display under ANY active preset (legacy glowed
-- them only if the preset happened to include them).
-- Groups are declared ON DEMAND (field-verified combat-legal on existing
-- containers -- probe T1/T1b): every AddAuraGroup eagerly creates a
-- 10-button engine batch (a deliberate anti-fingerprinting floor), so a
-- preset's groups exist on a button only once that preset has actually
-- been used. Default-preset users carry 2 debuff groups instead of 5.
-- Groups are never removed (engine add-only; frames are never freed);
-- switching away zeroes counts live.
local DEBUFF_GROUPS = {
    { key = "cc",          filter = { "HARMFUL", "CROWD_CONTROL" } },
    { key = "all",         filter = { "HARMFUL", "!CROWD_CONTROL" } },
    { key = "raid",        filter = { "HARMFUL", "RAID", "!CROWD_CONTROL" }, lazy = true },
    { key = "raidcombat",  filter = { "HARMFUL", "RAID_IN_COMBAT", "!RAID", "!CROWD_CONTROL" }, lazy = true },
    { key = "dispellable", filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE", "!CROWD_CONTROL" }, lazy = true },
}
-- Which lazy debuff groups each filter preset needs declared.
local DEBUFF_PRESET_GROUPS = {
    raid = { "raid", "raidcombat" },
    dispellable = { "dispellable" },
}
local DEBUFF_GROUP_BY_KEY = {}
for i = 1, #DEBUFF_GROUPS do DEBUFF_GROUP_BY_KEY[DEBUFF_GROUPS[i].key] = DEBUFF_GROUPS[i] end

-- "Dispellable Debuff Location": routes dispellable debuffs to their own
-- container with its own anchor/growth/offsets/icon size (legacy split the
-- one icon pool by dispelName; containers split via complementary dispel-type
-- candidate filters, which are engine-legal on friendly harmful auras and
-- are NOT identity-gated). The main groups exclude every typed debuff while
-- the split is on; the location container includes exactly those, so an
-- aura renders in exactly one place. Legacy parity note: the legacy test was
-- dispelName ~= nil, and Magic/Curse/Disease/Poison/Bleed is precisely the
-- harmful typed set (Enrage exists on buffs only).
local DISPLOC_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }

local function DispLocActive(s)
    -- 12.1 redesign: the dispellable-location split retired with the Auras
    -- tab (route Dispellable to a Debuff Manager tile instead). Constant
    -- false keeps every consumer (shell gating, config, shown state,
    -- candidate excludes, fingerprints) uniformly inert.
    return false
end

-- Phase A cannot know a button's final class (party creation stamps
-- _isParty after StyleButton), so the shell gate asks every settings
-- source: a shell whose class turns out not to want the split finishes
-- into a hidden, group-less container (cheap); a missing shell cannot be
-- created in combat at all.
local function DispLocAnyActive()
    if ns._scaledProfile and DispLocActive(ns._scaledProfile) then return true end
    if ns._scaledPartyProxy and DispLocActive(ns._scaledPartyProxy) then return true end
    if ns._scaledExtraProxy and DispLocActive(ns._scaledExtraProxy) then return true end
    return false
end

-- Effective icon size at the split anchor (0 = match Debuff Size; scaled
-- proxies bake the indicator scale into both keys, and 0 scales to 0, so
-- the match sentinel survives scaling).
local function DispLocSize(s)
    local v = s.dispellableDebuffSize
    if v and v > 0 then return v end
    return s.debuffSize or 18
end

-- Which groups the location container needs for the active preset. All of
-- its groups are on-demand (the split itself is opt-in); cc rides along so
-- dispellable crowd-control debuffs keep the CC glow at the split anchor,
-- matching the legacy split.
local function DispLocGroupWanted(s, key)
    local preset = s.debuffFilter or "all"
    if preset == "none" then return false end
    if key == "cc" then return true end
    if key == "all" then return preset == "all" end
    if key == "raid" or key == "raidcombat" then return preset == "raid" end
    return preset == "dispellable" -- key == "dispellable"
end

-- Defensives: externals and self-defensives share one flow (two negation-
-- chained groups). Legacy showed at most 4 across both; per-group caps mean
-- up to 4 of each now (consistent with the suite-wide per-class-cap delta).
local DEF_GROUPS = {
    { key = "external", filter = { "HELPFUL", "EXTERNAL_DEFENSIVE" }, skey = "showExternals" },
    { key = "selfdef",  filter = { "HELPFUL", "BIG_DEFENSIVE", "!EXTERNAL_DEFENSIVE" }, skey = "showDefensives" },
    -- Freedom-style utility buffs are not flagged defensive in Blizzard's
    -- data (the legacy code force-included Freedom via the secret
    -- fingerprint); an include group is the sanctioned replacement --
    -- spellID filtering of HELPFUL auras on assistable units passes the
    -- engine identity gate. Shows any caster's. 1044 Blessing of Freedom,
    -- 116841 Tiger's Lust.
    { key = "freedom", filter = { "HELPFUL", "!EXTERNAL_DEFENSIVE", "!BIG_DEFENSIVE" }, skey = "showExternals", cap = 2,
      cand = { includeSpellIDs = { [1044] = true, [116841] = true } } },
}
local DEF_CAP = 4

local registry = {} -- array of buttons with containers (iterate for reload)
ns._rfcRegistry = registry -- DEBUG: /euidm dump reads this; remove with the slash

local function ProxyFor(d)
    if d._isParty then return ns._scaledPartyProxy end
    if d._isExtra then return ns._scaledExtraProxy end
    return ns._scaledProfile
end

local function StyleKeyFor(d)
    if d._isParty then return "rf:debuff:party" end
    if d._isExtra then return "rf:debuff:extra" end
    return "rf:debuff:raid"
end

-- Debuff text pass: duration text centered (cooldown-countdown style), stack
-- text bottom-right, both through the shared icon-text font pipeline.
-- DM EFFECTS: per-filter effect BLOCKS (style.fxList). Buttons know their
-- record category via d.dmCat (stamped at group declare); cc-group buttons
-- identify through the cc style's ccGroup marker (the legacy cc group has
-- no stamping extraInit). The combined boss/role record matches either
-- check; the FIRST matching block wins. Each block carries an optional
-- Icon Glow (overlay mechanics: child rides button visibility, driver
-- styles remap to FlipBook under restriction, params cached) and an
-- optional Border override (own PP border host one level over the style
-- border -- equal or larger size covers it).
local function DmFxBlockFor(list, cat)
    if not (list and cat) then return nil end
    for i = 1, #list do
        local f = list[i].filters
        if f and (f[cat] or (cat == "bossrole" and (f.boss or f.role))) then
            return list[i]
        end
    end
end

local function ApplyDmFx(button, d, style)
    local cat = d.dmCat
    if not cat and style.ccGroup then cat = "cc" end
    local e = style.fxList and DmFxBlockFor(style.fxList, cat) or nil

    -- Icon Glow
    local Glows = EllesmereUI.Glows
    local gType = (e and e.glowType) or 0
    if gType > 0 and Glows and Glows.RestrictionSafeStyle then
        gType = Glows.RestrictionSafeStyle(gType)
    end
    local gov = d.dmFxgHost
    if gType > 0 and Glows and Glows.StartGlow then
        if not gov then
            gov = CreateFrame("Frame", nil, button)
            gov:SetAllPoints(button)
            -- Above BOTH borders (style border strips at borderHost+1;
            -- the fx border override's container at +2), below the dispel
            -- ring and text -- the engine dispel recolor ALWAYS wins over
            -- borders and glows. Final order: border < fx border < glow <
            -- dispel ring < text. The carrier write matches AuraKit's
            -- ladder (ring +3, text +4) so this pass never drags the text
            -- back down onto the ring. (Creation-window calls; our frames.)
            local base = (d.borderHost and d.borderHost:GetFrameLevel())
                or (button:GetFrameLevel() + 1)
            gov:SetFrameLevel(base + 2)
            if d.stackCarrier then d.stackCarrier:SetFrameLevel(base + 4) end
            gov:EnableMouse(false)
            d.dmFxgHost = gov
        end
        gov:Show()
        local cr, cg, cb = e.glowR or 1.0, e.glowG or 0.776, e.glowB or 0.376
        if e.glowClassColor then
            local _, classFile = UnitClass("player")
            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
        local sz = style.width or 18
        if (not gov._euiGlowActive) or gov._fxStyle ~= gType or gov._fxW ~= sz
           or gov._fxCR ~= cr or gov._fxCG ~= cg or gov._fxCB ~= cb then
            Glows.StartGlow(gov, gType, sz, cr, cg, cb)
            gov._fxStyle, gov._fxW = gType, sz
            gov._fxCR, gov._fxCG, gov._fxCB = cr, cg, cb
        end
    elseif gov then
        if gov._euiGlowActive and Glows and Glows.StopGlow then Glows.StopGlow(gov) end
        gov:Hide()
    end

    -- Border override
    local PP = EllesmereUI.PP
    local bSize = (e and e.borderSize) or 0
    if bSize > 0 and PP then
        local host = d.dmFxBdr
        if not host then
            host = CreateFrame("Frame", nil, button)
            host:SetAllPoints(button)
            local base = (d.borderHost and d.borderHost:GetFrameLevel())
                or (button:GetFrameLevel() + 1)
            host:SetFrameLevel(base + 1)
            host:EnableMouse(false)
            PP.CreateBorder(host, 0, 0, 0, 1, 1)
            d.dmFxBdr = host
        end
        local bc = e.borderColor or { r = 0, g = 0, b = 0 }
        PP.UpdateBorder(host, bSize, bc.r or 0, bc.g or 0, bc.b or 0, 1)
        host:Show()
    elseif d.dmFxBdr then
        d.dmFxBdr:Hide()
    end
end
-- Exported for the DM record/group extraInits: the style applier runs
-- BEFORE extraInit at button creation, so the dmCat stamp is not yet set
-- there -- the stamping extraInit re-arms the effects inside the creation
-- window (the only context where subtree writes are guaranteed legal).
ns.RFC_ApplyDmFx = ApplyDmFx

local function ApplyRFDebuffText(button, d, style)
    -- Restyles hit every registered button, so the expensive setters are
    -- change-guarded: SetFont costs real time even with identical values,
    -- and mouse-motion is an engine-wrapped call. (Font key = path|size;
    -- a module font-outline toggle without a size change slips through
    -- until the next reload that touches size -- acceptable.)
    if button.SetMouseMotionEnabled then
        local motion = not style.noTooltips
        if d.rfMotion ~= motion then
            d.rfMotion = motion
            button:SetMouseMotionEnabled(motion)
        end
    end
    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or FALLBACK_FONT
    if d.duration then
        -- Always font the string, hidden or not: the engine SetText()s every
        -- registered duration string on display updates, and an unfonted
        -- FontString hard-errors inside that engine call.
        local fontKey = path .. "|" .. (style.durSize or 8)
        if d.rfDurFont ~= fontKey then
            d.rfDurFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.duration, path, style.durSize or 8, "raidFrames")
        end
        local c = style.durColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        -- Anchor change-guarded (stamp AFTER the calls): SetPoint with the
        -- button as the relative frame is policed by the 12.1 button access
        -- restriction while auras are secret; unchanged offsets must make
        -- zero button-involving calls so restyles stay live in-instance.
        local aKey = (style.durOffX or 0) .. "|" .. (style.durOffY or 0)
        if d.rfDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint("CENTER", button, "CENTER", style.durOffX or 0, style.durOffY or 0)
            d.rfDurAnchor = aKey
        end
        d.duration:SetShown(not style.hideDurationText)
    end
    if d.stack then
        d.stack:SetShown(style.showStacks ~= false)
        local fontKey = path .. "|" .. (style.stackSize or 8)
        if d.rfStackFont ~= fontKey then
            d.rfStackFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.stack, path, style.stackSize or 8, "raidFrames")
        end
        local c = style.stackColor
        d.stack:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        local sKey = (style.stackOffX or 0) .. "|" .. (style.stackOffY or 0)
        if d.rfStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", style.stackOffX or 0, style.stackOffY or 0)
            d.rfStackAnchor = sKey
        end
    end
    -- DM Effects: per-filter blocks (flag only on DM styles; the extra
    -- clauses tear existing visuals down when the blocks turn off).
    if style.fxList or d.dmFxgHost or d.dmFxBdr then
        ApplyDmFx(button, d, style)
    end
    -- DM Square grid tiles: a flat color block covering the spell icon
    -- (swipe/border/texts render above it as usual). Flag exists only on
    -- square tile styles = zero cost everywhere else.
    if style.squareColor then
        local tex = d.dmSqTex
        if not tex then
            tex = button:CreateTexture(nil, "ARTWORK", nil, 3)
            tex:SetAllPoints(button)
            d.dmSqTex = tex
        end
        local c = style.squareColor
        tex:SetColorTexture(c.r or 1, c.g or 0.35, c.b or 0.35, c.a or 1)
        tex:Show()
    elseif d.dmSqTex then
        d.dmSqTex:Hide()
    end
end

local function ColorParts(c, dr, dg, db)
    if not c then return dr, dg, db end
    return c.r or c[1] or dr, c.g or c[2] or dg, c.b or c[3] or db
end

-- Settings fingerprints. Every engine setter (group counts, candidate
-- filters, layouts, slot filter strings) is a dirty mark that costs real
-- engine work (candidate re-evaluation, parse-filter rebuilds) even when
-- the value is unchanged -- re-driving all of them on every button for
-- every unrelated settings change froze the client in raids. Reload paths
-- therefore fingerprint the exact settings each subsystem reads and skip
-- engine calls whose inputs did not change.
local function FP(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do
        local v = select(i, ...)
        -- Numbers round to 2 decimals: scaled sizes carry float noise that
        -- would otherwise flip fingerprints on every pass.
        if type(v) == "number" then
            t[i] = string.format("%.2f", v)
        else
            t[i] = tostring(v)
        end
    end
    return table.concat(t, "|")
end

local function CK(c)
    local r, g, b = ColorParts(c, 0, 0, 0)
    return string.format("%.3f,%.3f,%.3f", r, g, b)
end

local function BuildDefStyle(s)
    local br, bg, bb = ColorParts(s.defBorderColor, 0, 0, 0)
    local size = s.defSize or 22
    return {
        width = size,
        height = size,
        iconCrop = true,
        iconZoom = s.defIconZoom or 0.08,
        border = (s.defBorderSize or 1) > 0 and { br, bg, bb, 1, size = s.defBorderSize or 1 } or nil,
        cooldownReverse = true,
        hideSwipe = (s.defShowSwipe == false),
        noDefaultFonts = true,
        hideDurationText = not s.defShowDurText,
        durSize = s.defDurTextSize,
        durColor = s.defDurTextColor,
        durOffX = s.defDurTextOffsetX,
        durOffY = s.defDurTextOffsetY,
        showStacks = false, -- legacy defensive icons have no stack text
        noTooltips = true,  -- legacy defensive icons are mouse-transparent
        applyExtra = ApplyRFDebuffText,
    }
end

-- sizeOverride: the dispellable-location styles reuse the whole debuff
-- style with only the physical size swapped (see DispLocSize).
local function BuildDebuffStyle(s, sizeOverride)
    local br, bg, bb = ColorParts(s.debuffBorderColor, 0, 0, 0)
    local size = sizeOverride or s.debuffSize or 18
    -- Engine dispel-border extras: the ring's thickness in PHYSICAL pixels
    -- (Dispels section cog) and the user dispel palette as the engine's
    -- tint map (AuraKit registers both; helper is declared below, resolved
    -- at call time). -1 = follow the icon's own Border thickness (tile
    -- styles resolve their override through the style view passed in);
    -- 0 disables the recolor (AuraKit's registration gate).
    local dpx = s.dispelIconBorderSize or 2
    if dpx == -1 then dpx = s.debuffBorderSize or 1 end
    local dcMap, dcFP
    if ns.RFC_DispelBorderColorMap then dcMap, dcFP = ns.RFC_DispelBorderColorMap(s) end
    return {
        width = size,
        height = size,
        iconCrop = true,
        iconZoom = s.debuffIconZoom or 0.08,
        border = (s.debuffBorderSize or 1) > 0 and { br, bg, bb, 1, size = s.debuffBorderSize or 1 } or nil,
        -- Dispellable debuffs get the engine dispel-type border over the
        -- static one (dispelName is secret in 12.1; see AuraKit).
        dispelBorder = true,
        dispelBorderPx = dpx,
        dispelColorMap = dcMap,
        dispelColorFP = dcFP,
        cooldownReverse = true,
        hideSwipe = (s.debuffShowSwipe == false),
        noDefaultFonts = true,
        hideDurationText = not s.debuffShowDurText,
        durSize = s.debuffDurTextSize,
        durColor = s.debuffDurTextColor,
        durOffX = s.debuffDurTextOffsetX,
        durOffY = s.debuffDurTextOffsetY,
        showStacks = s.debuffShowStacks ~= false,
        stackSize = s.debuffStacksTextSize,
        stackColor = s.debuffStacksTextColor,
        stackOffX = s.debuffStacksOffsetX,
        stackOffY = s.debuffStacksOffsetY,
        noTooltips = s.debuffHideTooltips ~= false,
        -- Base DM Effects (per-filter blocks); tile styles override this
        -- after the build with their own (or nil).
        fxList = (ns.DM_FxList and ns.DM_FxList()) or nil,
        applyExtra = ApplyRFDebuffText,
    }
end

-- Crowd-control group style: the plain debuff style plus a marker the DM
-- per-filter Icon Effects use to identify cc-group buttons (the legacy cc
-- group declares no category-stamping extraInit). The dedicated CC Debuff
-- Glow is RETIRED on 12.1: the Debuff Manager's per-filter Icon Effects
-- glow supersedes it (glow any category, user-configured), so the old
-- debuffCCGlow* keys are orphaned here (the frozen 12.0 path keeps them).
local function BuildDebuffCCStyle(s, sizeOverride)
    local st = BuildDebuffStyle(s, sizeOverride)
    st.ccGroup = true
    return st
end
-- Shared with the Debuff Manager file: custom tiles render with the debuff
-- style at their own size (same derivation the dispellable split uses).
ns.RFC_BuildDebuffStyle = BuildDebuffStyle
-- CC flavor too: a per-filter Icon Effects Size moves crowd control onto a
-- sized record variant, which must keep the CC glow style fields.
ns.RFC_BuildDebuffCCStyle = BuildDebuffCCStyle

-- Container anchoring that mirrors DebuffGridPoint: the flow's start corner
-- sits on the same corner of the health bar; CENTER growth anchors the
-- container's edge-midpoint AT that corner so each row centers on it.
local CORNERS = {
    topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT",
    left = "LEFT", center = "CENTER", right = "RIGHT",
    bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT",
}

local function FlowDir(token)
    local FD = AnchorUtil.FlowDirection
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

local function AnchorDebuffContainer(container, health, s)
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, s) or health   -- Uniform Icon Anchoring
    local corner = CORNERS[s.debuffPosition or "bottomright"] or "BOTTOMRIGHT"
    local grow = s.debuffGrowDirection or "LEFT"
    local wrap = s.debuffWrapDirection or "UP"
    local offX = s.debuffOffsetX or 0
    local offY = s.debuffOffsetY or 0

    local point, anchorPoint, gH, gV
    if grow == "CENTER" then
        -- Rows center on the anchor corner: pin the container's horizontal
        -- midpoint (top or bottom edge, matching wrap direction) at it.
        point = (wrap == "DOWN") and "TOP" or "BOTTOM"
        anchorPoint = (wrap == "DOWN") and "TOPLEFT" or "BOTTOMLEFT"
        gH, gV = "RIGHT", wrap
    elseif grow == "UP" or grow == "DOWN" then
        -- Vertical primary growth renders as a single column per row-width;
        -- multi-column vertical fill order differs from legacy (row-major).
        point = corner
        anchorPoint = corner
        gH, gV = (wrap == "LEFT") and "LEFT" or "RIGHT", grow
    else
        point = corner
        anchorPoint = corner
        gH, gV = grow, wrap
    end

    container:ClearAllPoints()
    container:SetPoint(point, health, corner, offX, offY)
    AK.SetContainerAnchor(container, anchorPoint)
    AK.SetContainerGrowth(container, FlowDir(gH), FlowDir(gV))

    local size = s.debuffSize or 18
    local spacing = s.debuffSpacing or 1
    local perRow = s.debuffPerRow or 5
    local vertical = (grow == "UP" or grow == "DOWN")
    local rowWidth = nil
    if vertical and perRow and perRow >= 2 then
        -- Vertical COLUMNS (12.1 flow axis): lines are columns of perRow
        -- cells wrapping sideways -- debuffWrapDirection already maps to
        -- the horizontal cross-axis in the growth math above. Below 2 the
        -- legacy single column stands.
        AK.SetContainerAxis(container, true)
        rowWidth = perRow * size + (perRow - 1) * spacing + 0.4
    elseif vertical then
        AK.SetContainerAxis(container, false)
        rowWidth = size + 0.4 -- one column; rows advance vertically
    else
        AK.SetContainerAxis(container, false)
        if perRow and perRow >= 2 then
            rowWidth = perRow * size + (perRow - 1) * spacing + 0.4
        end
    end
    AK.SetContainerRowWidth(container, rowWidth)
end

-- Dispellable-location container anchoring: the same flow math as the main
-- debuff container, but position/growth/offsets/icon size come from the
-- "Dispellable Debuff Location" settings (spacing/wrap/per-row stay shared
-- with the debuff display, matching the legacy split).
local function AnchorDispLocContainer(container, health, s)
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, s) or health   -- Uniform Icon Anchoring
    local corner = CORNERS[s.dispellableDebuffLocation] or "BOTTOMRIGHT"
    local grow = s.dispellableDebuffGrowDirection or "RIGHT"
    local wrap = s.debuffWrapDirection or "UP"
    local offX = s.dispellableDebuffOffsetX or 0
    local offY = s.dispellableDebuffOffsetY or 0

    local point, anchorPoint, gH, gV
    if grow == "CENTER" then
        point = (wrap == "DOWN") and "TOP" or "BOTTOM"
        anchorPoint = (wrap == "DOWN") and "TOPLEFT" or "BOTTOMLEFT"
        gH, gV = "RIGHT", wrap
    elseif grow == "UP" or grow == "DOWN" then
        point = corner
        anchorPoint = corner
        gH, gV = (wrap == "LEFT") and "LEFT" or "RIGHT", grow
    else
        point = corner
        anchorPoint = corner
        gH, gV = grow, wrap
    end

    container:ClearAllPoints()
    container:SetPoint(point, health, corner, offX, offY)
    AK.SetContainerAnchor(container, anchorPoint)
    AK.SetContainerGrowth(container, FlowDir(gH), FlowDir(gV))

    local size = DispLocSize(s)
    local spacing = s.debuffSpacing or 1
    local perRow = s.debuffPerRow or 5
    local vertical = (grow == "UP" or grow == "DOWN")
    local rowWidth = nil
    if vertical then
        rowWidth = size + 0.4
    elseif perRow and perRow >= 2 then
        rowWidth = perRow * size + (perRow - 1) * spacing + 0.4
    end
    AK.SetContainerRowWidth(container, rowWidth)
end

-- Defensives anchoring mirrors the legacy AnchorDefensives: the chain starts
-- pinned at the health-bar corner named by defPosition and extends in
-- defGrowDirection; CENTER growth centers the row on that point.
local function AnchorDefContainer(container, health, s)
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, s) or health   -- Uniform Icon Anchoring
    local corner = CORNERS[s.defPosition or "center"] or "CENTER"
    local grow = s.defGrowDirection or "CENTER"
    local offX = s.defOffsetX or 0
    local offY = s.defOffsetY or 0

    container:ClearAllPoints()
    if grow == "CENTER" then
        container:SetPoint("CENTER", health, corner, offX, offY)
        AK.SetContainerAnchor(container, "TOPLEFT")
        AK.SetContainerGrowth(container, FlowDir("RIGHT"), FlowDir("DOWN"))
    else
        container:SetPoint(corner, health, corner, offX, offY)
        AK.SetContainerAnchor(container, corner)
        local gV = (grow == "UP" or grow == "DOWN") and grow or "DOWN"
        local gH = (grow == "LEFT" or grow == "RIGHT") and grow or "RIGHT"
        AK.SetContainerGrowth(container, FlowDir(gH), FlowDir(gV))
    end

    local size = s.defSize or 22
    local vertical = (grow == "UP" or grow == "DOWN")
    AK.SetContainerRowWidth(container, vertical and (size + 0.4) or nil)
end

local function ApplyDefConfig(container, s, d)
    -- 12.1 redesign: defensives row retired (see RFC_DefensivesRetired) --
    -- the container is never built, and any stale one stays parked.
    if ns.RFC_DefensivesRetired then
        if container then container:SetShown(false) end
        return
    end
    local size = s.defSize or 22
    local spacing = s.defSpacing or 1
    local layout = {
        elementWidth = size, elementHeight = size,
        elementSpacing = spacing, lineSpacing = spacing,
    }
    -- Defensive groups are declared on demand: only toggled-on roles exist
    -- (10-button batch each). A toggle enabled later declares its group on
    -- the combat-legal live lane and re-applies.
    local declared = (d and d.rfcDefGroups) or {}
    if d and d.rfcDefGroups then
        local missing = false
        for i = 1, #DEF_GROUPS do
            local g = DEF_GROUPS[i]
            if s[g.skey] ~= false and not declared[g.key] then missing = true end
        end
        if missing and not d.rfcDefEnsure then
            d.rfcDefEnsure = true
            AK.QueueLiveBuildJob(function()
                d.rfcDefEnsure = nil
                local c2 = d.rfcDefs
                if not c2 then return end
                local s2 = ProxyFor(d)
                if not s2 then return end
                local defStyleKey = StyleKeyFor(d):gsub("debuff", "def")
                for i = 1, #DEF_GROUPS do
                    local g = DEF_GROUPS[i]
                    if s2[g.skey] ~= false and not d.rfcDefGroups[g.key] then
                        AK.AddGroupToContainer(c2, { key = g.key, filter = g.filter,
                            maxFrameCount = 0, style = defStyleKey })
                        d.rfcDefGroups[g.key] = true
                    end
                end
                ApplyDefConfig(c2, s2, d)
            end, "rf:def-ensure")
        end
    end
    for i = 1, #DEF_GROUPS do
        local g = DEF_GROUPS[i]
        if declared[g.key] then
            local shown = s[g.skey] ~= false
            -- Candidate-dependent groups stay off for non-assistable units
            -- (identity gate would ignore their include lists; see the
            -- assist-gate block below).
            if g.cand and d and d.rfcAssist == false then shown = false end
            container:SetAuraGroupMaxFrameCount(g.key, shown and (g.cap or DEF_CAP) or 0)
            container:SetAuraGroupCandidateFilters(g.key, g.cand)
            container:SetAuraGroupLayout(g.key, layout)
        end
    end
end

------------------------------------------------------------------------------
-- Dispel highlight -> per-type slots (step 3). One bare slot per dispel
-- type; each decorates the health bar (overlay texture, PP border, type
-- icon) from the user palette, engine-driven show/hide. Layer priority
-- Magic > Curse > Disease > Poison > Bleed. The legacy alpha-curve trick
-- (show every type icon, curve the right one visible) is obsolete: a slot
-- IS one type. The animated clock border on debuff icons is not
-- reproducible (documented delta).
------------------------------------------------------------------------------

local DISPEL_SLOTS = {
    { key = "magic",   token = "Magic",   colorKey = "dispelColorMagic",   atlas = "RaidFrame-Icon-DebuffMagic",   fallback = { 0.349, 0.475, 1.0 },   level = 5 },
    { key = "curse",   token = "Curse",   colorKey = "dispelColorCurse",   atlas = "RaidFrame-Icon-DebuffCurse",   fallback = { 0.636, 0.0, 0.64 },    level = 4 },
    { key = "disease", token = "Disease", colorKey = "dispelColorDisease", atlas = "RaidFrame-Icon-DebuffDisease", fallback = { 0.671, 0.384, 0.098 }, level = 3 },
    { key = "poison",  token = "Poison",  colorKey = "dispelColorPoison",  atlas = "RaidFrame-Icon-DebuffPoison",  fallback = { 0.0, 0.706, 0.286 },   level = 2 },
    { key = "bleed",   token = "Bleed",   colorKey = "dispelColorBleed",   atlas = "RaidFrame-Icon-DebuffBleed",   fallback = { 0.75, 0.15, 0.15 },    level = 1 },
}

-- User dispel palette as a SetAuraBorder customDispelColorMap (the engine
-- tints our debuff-icon ring with THESE colors; C-side option validation
-- reconstructs the color objects) plus a fingerprint string so a palette
-- edit re-registers the border options. Resolved via ns at call time --
-- BuildDebuffStyle is declared above this table.
function ns.RFC_DispelBorderColorMap(s)
    local map, fp = {}, {}
    for i = 1, #DISPEL_SLOTS do
        local def = DISPEL_SLOTS[i]
        local c = s[def.colorKey]
        local r = (c and c.r) or def.fallback[1]
        local g = (c and c.g) or def.fallback[2]
        local b = (c and c.b) or def.fallback[3]
        map[def.token] = CreateColor(r, g, b, 1)
        fp[#fp + 1] = string.format("%.3f,%.3f,%.3f", r, g, b)
    end
    return map, table.concat(fp, ";")
end
local GRADIENT_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga"
local GRADIENT_SHARP_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"

local function DispelSlotFilter(s)
    if s.dispelShowAll == false then
        return { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }
    end
    return { "HARMFUL" }
end

-- applyExtra for dispel slots. Per-button refs (health, slot definition)
-- come from the creation-time extraInit closure via dd; per-class settings
-- from the shared style.
local function ApplyRFDispelSlot(button, dd, style)
    local health = dd.rfHealth
    local def = dd.rfSlotDef
    if not (style and health and def) then return end
    local PP = EllesmereUI.PP

    -- Change-guarded, stamped AFTER the call: SetFrameLevel on the slot
    -- button is denied while auras are secret (12.1 access restriction);
    -- creation-window calls are legal, restyle-time denials throw so the
    -- worker defers this key to the restriction-lift re-queue.
    local lvl = health:GetFrameLevel() + 1 + def.level
    if dd.lvl ~= lvl then
        button:SetFrameLevel(lvl)
        dd.lvl = lvl
    end

    local c = style.typeColors and style.typeColors[def.token]
    local r, g, b = c and c.r or 1, c and c.g or 1, c and c.b or 1
    -- Per-type alpha (0 = user opted this type out of the dispel visuals)
    local typeA = (c and c.a) or 1
    local alpha = (style.opacity or 100) / 100 * typeA

    -- Overlay texture (fill / full / gradient), legacy ARTWORK sublevel 3.
    if not dd.overlay then
        dd.overlay = button:CreateTexture(nil, "ARTWORK", nil, 3)
    end
    local tex = dd.overlay
    tex:ClearAllPoints()
    if style.mode == "none" then
        tex:Hide()
    elseif style.mode == "gradient" or style.mode == "gradient_sharp" then
        tex:Show()
        tex:SetAllPoints(health)
        tex:SetTexture(style.mode == "gradient_sharp" and GRADIENT_SHARP_TEXTURE or GRADIENT_TEXTURE)
        tex:SetVertexColor(r, g, b, alpha)
    elseif style.mode == "full" then
        tex:Show()
        tex:SetAllPoints(health)
        tex:SetColorTexture(r, g, b, alpha)
        tex:SetVertexColor(1, 1, 1, 1)
    else -- "fill"
        tex:Show()
        local fillTex = health.GetStatusBarTexture and health:GetStatusBarTexture()
        tex:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        if fillTex then
            tex:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
        else
            tex:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        end
        tex:SetColorTexture(r, g, b, alpha)
        tex:SetVertexColor(1, 1, 1, 1)
    end

    -- Type-colored border around the health bar.
    if (style.borderSize or 0) > 0 and PP then
        if not dd.borderHost then
            dd.borderHost = CreateFrame("Frame", nil, button)
            dd.borderHost:SetAllPoints(health)
        end
        dd.borderHost:SetFrameLevel(health:GetFrameLevel() + 6 + def.level)
        if dd.borderMade then
            PP.UpdateBorder(dd.borderHost, style.borderSize, r, g, b, typeA)
        else
            PP.CreateBorder(dd.borderHost, r, g, b, typeA, style.borderSize, "OVERLAY", 7)
            dd.borderMade = true
        end
        dd.borderHost:Show()
    elseif dd.borderHost then
        dd.borderHost:Hide()
    end

    -- Dispel type icon.
    if style.showIcon then
        if not dd.iconHost then
            dd.iconHost = CreateFrame("Frame", nil, button)
            dd.icon = dd.iconHost:CreateTexture(nil, "ARTWORK")
            dd.icon:SetAllPoints(dd.iconHost)
        end
        dd.iconHost:SetFrameLevel(health:GetFrameLevel() + 12 + def.level)
        dd.icon:SetAtlas(def.atlas)
        local size = style.iconSize or 16
        dd.iconHost:SetSize(size, size)
        local corner = CORNERS[style.iconPos or "right"] or "RIGHT"
        -- Uniform Icon Anchoring: the type icon is positional (unlike the
        -- overlay/border above, which decorate the bar itself).
        local iconAnchor = (style.uniformAnchors and health._euiUniformRef) or health
        dd.iconHost:ClearAllPoints()
        dd.iconHost:SetPoint(corner, iconAnchor, corner, style.iconOffX or 0, style.iconOffY or 0)
        dd.iconHost:Show()
    elseif dd.iconHost then
        dd.iconHost:Hide()
    end
end

local function BuildDispelStyle(s)
    local typeColors = {}
    for i = 1, #DISPEL_SLOTS do
        local def = DISPEL_SLOTS[i]
        local c = s[def.colorKey]
        typeColors[def.token] = {
            r = c and c.r or def.fallback[1],
            g = c and c.g or def.fallback[2],
            b = c and c.b or def.fallback[3],
            a = (c and c.a) or 1,
        }
    end
    return {
        width = 1, height = 1,
        noRegions = true,
        mode = s.dispelOverlay or "fill",
        opacity = s.dispelOverlayOpacity or 100,
        borderSize = s.dispelBorderSize or 0,
        showIcon = s.showDispelIcons == true,
        iconSize = s.dispelIconSize or 16,
        iconPos = s.dispelIconPosition or "right",
        iconOffX = s.dispelIconOffsetX or 0,
        iconOffY = s.dispelIconOffsetY or 0,
        uniformAnchors = s.powerUniformAnchors == true,
        typeColors = typeColors,
        applyExtra = ApplyRFDispelSlot,
    }
end

local function DispelVisible(s)
    return (s.dispelOverlay or "fill") ~= "none"
        or (s.dispelBorderSize or 0) > 0
        or s.showDispelIcons == true
end

-- Fingerprints of the exact settings each subsystem reads, per class
-- ("rf:debuff:raid"/party/extra -- proxy values differ per class, and the
-- scaled proxies bake scale in, so scale changes flip these too).
local classFP = {}

local function DebuffStyleFP(s, font)
    return FP(font, s.debuffSize, s.debuffIconZoom, s.debuffBorderSize, CK(s.debuffBorderColor),
        s.debuffShowSwipe, s.debuffShowDurText, s.debuffDurTextSize, CK(s.debuffDurTextColor),
        s.debuffDurTextOffsetX, s.debuffDurTextOffsetY, s.debuffShowStacks, s.debuffStacksTextSize,
        CK(s.debuffStacksTextColor), s.debuffStacksOffsetX, s.debuffStacksOffsetY, s.debuffHideTooltips,
        -- Dispel icon ring: thickness + the user palette the engine tints with.
        s.dispelIconBorderSize, CK(s.dispelColorMagic), CK(s.dispelColorCurse),
        CK(s.dispelColorDisease), CK(s.dispelColorPoison), CK(s.dispelColorBleed),
        -- Base DM Effects ride the debuff style (BuildDebuffStyle injects
        -- them), so their config is part of this fingerprint. (The old
        -- debuffCCGlow* keys left with the retired CC Debuff Glow.)
        (ns.DM_FxFP and ns.DM_FxFP()) or "")
end
-- Shared with the Debuff Manager file: tile styles derive from the debuff
-- style, so their restyle fingerprints must include this exact value.
ns.RFC_DebuffStyleFP = DebuffStyleFP

local function DebuffCfgFP(s)
    -- DispLocActive: the split toggles excludeDispelTypes on the MAIN groups'
    -- candidate filters, so flipping it must re-drive the main config too.
    return FP(s.debuffPosition, s.debuffGrowDirection, s.debuffWrapDirection, s.debuffOffsetX,
        s.debuffOffsetY, s.debuffSize, s.debuffSpacing, s.debuffPerRow, s.debuffFilter,
        s.debuffCap, s.hideLustDebuff, DispLocActive(s), s.powerUniformAnchors,
        (ns.DM_CfgFP and ns.DM_CfgFP()) or "")
end

local function DispLocStyleFP(s, font)
    -- The split styles are the debuff styles with only the size swapped.
    return FP(DebuffStyleFP(s, font), DispLocSize(s), DispLocActive(s))
end

local function DispLocCfgFP(s)
    return FP(DispLocActive(s), s.dispellableDebuffLocation, s.dispellableDebuffGrowDirection,
        s.dispellableDebuffOffsetX, s.dispellableDebuffOffsetY, DispLocSize(s),
        s.debuffSpacing, s.debuffPerRow, s.debuffWrapDirection, s.debuffFilter,
        s.debuffCap, s.hideLustDebuff, s.powerUniformAnchors)
end

local function DefStyleFP(s, font)
    return FP(font, s.defSize, s.defIconZoom, s.defBorderSize, CK(s.defBorderColor), s.defShowSwipe,
        s.defShowDurText, s.defDurTextSize, CK(s.defDurTextColor), s.defDurTextOffsetX, s.defDurTextOffsetY)
end

local function DefCfgFP(s)
    return FP(s.defPosition, s.defGrowDirection, s.defOffsetX, s.defOffsetY, s.defSize, s.defSpacing,
        s.showExternals, s.showDefensives, s.powerUniformAnchors)
end

-- Color key + per-type alpha (the dispel swatches carry an opt-out alpha).
local function CKA(c)
    return CK(c) .. "," .. tostring((c and c.a) or 1)
end

local function DispelStyleFP(s)
    return FP(s.dispelOverlay, s.dispelOverlayOpacity, s.dispelBorderSize, s.showDispelIcons,
        s.dispelIconSize, s.dispelIconPosition, s.dispelIconOffsetX, s.dispelIconOffsetY,
        CKA(s.dispelColorMagic), CKA(s.dispelColorCurse), CKA(s.dispelColorDisease),
        CKA(s.dispelColorPoison), CKA(s.dispelColorBleed), s.powerUniformAnchors)
end

-- Stores the current fingerprints without restyling. Called at button
-- setup, which just built/applied everything from these same settings --
-- otherwise the first settings change after login re-drove every subsystem
-- for the class (a one-time full storm).
local function PrimeClassFP(styleKey, s)
    local st = classFP[styleKey]
    if not st then st = {}; classFP[styleKey] = st end
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    st.debuffStyle = DebuffStyleFP(s, font)
    st.debuffCfg = DebuffCfgFP(s)
    st.dispLocStyle = DispLocStyleFP(s, font)
    st.dispLocCfg = DispLocCfgFP(s)
    st.defStyle = DefStyleFP(s, font)
    st.defCfg = DefCfgFP(s)
    st.dispelStyle = DispelStyleFP(s)
    st.dispelFilter = AK.Filter(unpack(DispelSlotFilter(s)))
end

local function ApplyDebuffConfig(container, d, s)
    -- Debuff Manager (12.1 redesign): while active it owns every group on
    -- this container (legacy preset groups park at 0 inside it).
    if ns.DM_Active and ns.DM_Active() and ns.DM_ApplyDebuffConfig then
        ns.DM_ApplyDebuffConfig(container, d, s, StyleKeyFor(d))
        return
    end
    -- 12.1 redesign: the legacy preset display retired with the Auras tab.
    -- The Debuff Manager (default-ON) is the only debuff renderer; with it
    -- explicitly disabled the debuff row is EMPTY by design. Park every
    -- group (record variants and tile containers park via DM_ParkGroups).
    local declared = d.rfcDebuffGroups or {}
    for k in pairs(declared) do
        container:SetAuraGroupMaxFrameCount(k, 0)
    end
    if ns.DM_ParkGroups then ns.DM_ParkGroups(container, declared, d) end
end

-- Config for the dispellable-location container: same preset/cap/exclude
-- semantics as the main debuff config, but every group carries the
-- includeDispelTypes candidate filter and the split's own element size.
-- All groups are on-demand (feature and preset both opt-in); a preset
-- needing an undeclared group queues its declaration on the combat-legal
-- live lane and re-applies, mirroring ApplyDebuffConfig.
local function ApplyDispLocConfig(container, d, s)
    local active = DispLocActive(s)
    local cap = 0
    if active and (s.debuffFilter or "all") ~= "none" then cap = s.debuffCap or 3 end

    local ex = {}
    for id in pairs(ALWAYS_HIDE_DEBUFFS) do ex[id] = true end
    if s.hideLustDebuff ~= false then
        for id in pairs(SATED_DEBUFFS) do ex[id] = true end
    end
    local cand = { excludeSpellIDs = ex, includeDispelTypes = DISPLOC_TYPES }

    local size = DispLocSize(s)
    local layout = {
        elementWidth = size, elementHeight = size,
        elementSpacing = s.debuffSpacing or 1, lineSpacing = s.debuffSpacing or 1,
    }

    local declared = d.rfcDispLocGroups or {}
    if active then
        local missing = false
        for i = 1, #DEBUFF_GROUPS do
            local g = DEBUFF_GROUPS[i]
            if DispLocGroupWanted(s, g.key) and not declared[g.key] then missing = true end
        end
        if missing and not d.rfcDispLocEnsure then
            d.rfcDispLocEnsure = true
            AK.QueueLiveBuildJob(function()
                d.rfcDispLocEnsure = nil
                local c2 = d.rfcDispLoc
                if not c2 then return end
                local s2 = ProxyFor(d)
                if not s2 or not DispLocActive(s2) then return end
                local styleKey = StyleKeyFor(d)
                local dlStyleKey = styleKey:gsub("debuff", "disploc")
                local dlCCStyleKey = styleKey:gsub("debuff", "disploccc")
                AK.styles[dlStyleKey] = AK.styles[dlStyleKey] or BuildDebuffStyle(s2, DispLocSize(s2))
                AK.styles[dlCCStyleKey] = AK.styles[dlCCStyleKey] or BuildDebuffCCStyle(s2, DispLocSize(s2))
                for i = 1, #DEBUFF_GROUPS do
                    local g = DEBUFF_GROUPS[i]
                    if DispLocGroupWanted(s2, g.key) and not d.rfcDispLocGroups[g.key] then
                        AK.AddGroupToContainer(c2, { key = g.key, filter = g.filter,
                            maxFrameCount = 0,
                            style = (g.key == "cc") and dlCCStyleKey or dlStyleKey })
                        d.rfcDispLocGroups[g.key] = true
                    end
                end
                ApplyDispLocConfig(c2, d, s2)
            end, "rf:disploc-ensure")
        end
    end

    for i = 1, #DEBUFF_GROUPS do
        local g = DEBUFF_GROUPS[i]
        if declared[g.key] then
            container:SetAuraGroupMaxFrameCount(g.key, DispLocGroupWanted(s, g.key) and cap or 0)
            container:SetAuraGroupCandidateFilters(g.key, cand)
            container:SetAuraGroupLayout(g.key, layout)
        end
    end
end

-- The 12.1 ping-receiver strip workaround lived here until build 68914
-- fixed SendUnitPing upstream (PingManager securecopys the receiver info
-- at the secure boundary); the main file's hover-ping recipe now works on
-- the PTR exactly as on retail.

------------------------------------------------------------------------------
-- BuffManager custom mode -> slots (step 4a). Each indicator becomes one
-- slot per tracked spell (fixed chain positions; legacy compacted visible
-- icons -- documented delta). icon slots use the standard region set;
-- square/bar/effect slots are bare buttons whose extraInit builds custom
-- regions and registers them with the engine setters directly. Effects:
-- healthcolor recolors an overlay on the health bar, border draws around
-- the button; framealpha and the missing/allPresent/anyMissing show-when
-- modes are not reproducible (documented losses). Simple mode stays on the
-- legacy renderer for now (step 4b).
------------------------------------------------------------------------------

local BM_FRAMELVL = { behindBorders = 7, behindText = 11, medium = 13, high = 14, highest = 15 }
local BM_FRAMELVL_TEXT = 18

local function BmScaleFor(d)
    if d._isParty then return ns._partyBmScale or 1 end
    if d._isExtra then return ns._xfBmScale or 1 end
    return ns._bmScale or 1
end

local function BmIndicators()
    -- Buff Manager v2 (spell -> filter -> indicator): the adapter returns
    -- legacy-shaped indicators with resolved spell unions. Gated on the
    -- activation flag -- dormant v2 leaves the legacy system untouched.
    if ns.BM2_Enabled and ns.BM2_SpecIndicators then
        return ns.BM2_SpecIndicators()
    end
    if not (ns.BM_GetSpecIndicators and ns.db) then return nil, nil, "custom" end
    local specKey = ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey()
    -- Coexistence (manager redesign): the base grid and the custom
    -- indicators are INDEPENDENT subsystems -- this function serves only
    -- the custom side (nil inds parks the chains/slots). The base grid
    -- resolves through BM_BaseActive/BM_SimpleSpecKey at its own sites.
    -- The legacy either/or bmDisplayMode key is consulted only inside the
    -- effective accessors (shim defaults; the key itself is never written).
    local mode = "custom"
    if ns.BM_CustomActive and not ns.BM_CustomActive() then
        return nil, specKey, mode
    end
    if not specKey then
        -- Untracked spec: indicators flagged Show Own on All Specs still
        -- render from the class-fallback spec's config.
        local fbKey = ns.BM_ClassFallbackSpecKey and ns.BM_ClassFallbackSpecKey()
        local all = fbKey and ns.BM_GetSpecIndicators(ns.db, fbKey)
        if all then
            local flagged
            for _, ind in ipairs(all) do
                if ind.showOwnAllSpecs then
                    flagged = flagged or {}
                    flagged[#flagged + 1] = ind
                end
            end
            if flagged then return flagged, fbKey, mode end
        end
        return nil, nil, "custom"
    end
    return ns.BM_GetSpecIndicators(ns.db, specKey), specKey, mode
end

local function BmIncludeMap(spellID)
    local map = { [spellID] = true }
    if ns.BM_PrimaryByAlt then
        for alt, prim in pairs(ns.BM_PrimaryByAlt) do
            if prim == spellID then map[alt] = true end
        end
    end
    -- v2 curated alternates (same buff under talent/rank ids): resolution
    -- keeps ONE entry per buff family, so the family's alt ids must all
    -- match the primary's slot here.
    if ns.BM2_PresetAlts then
        local alts = ns.BM2_PresetAlts[spellID]
        if alts then
            for i = 1, #alts do map[alts[i]] = true end
        end
    end
    return map
end

local function BmEffOwnOnly(ind, spellID)
    local o = ind.ownOnlySpells and ind.ownOnlySpells[spellID]
    if o ~= nil then return o end
    if ind.ownOnly ~= nil then return ind.ownOnly end
    return true
end

-- Square per-spell color: the options swatches write ind.spellColors[spellID]
-- (the legacy single ind.color is only a fallback). With a nil spellID
-- (shared chain-group style) the resolved colors are uniform by construction
-- (BmChainMode forces per-spell slots when they differ), so the first
-- spell's resolved entry is representative.
local function BmSquareColor(ind, spellID)
    local sc = ind.spellColors
    if sc then
        if spellID then
            return sc[spellID] or ind.color
        end
        for k = 1, #(ind.spells or {}) do
            local c = sc[ind.spells[k]]
            if c then return c end
        end
    end
    return ind.color
end

-- Chain rendering mode for icon/square indicators. "g" = one flow GROUP:
-- active auras compact into the first positions like the legacy renderer
-- (engine sort order within the chain -- documented delta vs legacy list
-- order). "s" = fixed per-spell slots, required when per-spell overrides
-- (size offsets, mixed own-only, mixed square colors) make one shared group
-- impossible; those keep reserved positions. "-" = not a chain kind.
local function BmChainMode(ind)
    if ind.type ~= "icon" and ind.type ~= "square" then return "-" end
    if ind.sizeOffsets then
        for _, v in pairs(ind.sizeOffsets) do
            if v and v ~= 0 then return "s" end
        end
    end
    if ind.type == "square" and ind.spellColors then
        -- Mixed per-spell colors: a shared group cannot know which spell an
        -- engine button holds, so each spell needs its own styled slot.
        local first
        for k = 1, #(ind.spells or {}) do
            local ck = CK(ind.spellColors[ind.spells[k]] or ind.color)
            if not first then
                first = ck
            elseif ck ~= first then
                return "s"
            end
        end
    end
    if ind.ownOnlySpells then
        local base = true
        if ind.ownOnly ~= nil then base = ind.ownOnly end
        for _, v in pairs(ind.ownOnlySpells) do
            if v ~= base then return "s" end
        end
    end
    return "g"
end

-- Own-only state feeds candidateFilters, which are fixed per slot, so it is
-- part of the swap signature (sorted for determinism).
local function BmOwnSig(ind)
    local parts = { tostring(ind.ownOnly ~= false) }
    local os = ind.ownOnlySpells
    if os then
        local keys = {}
        for id in pairs(os) do keys[#keys + 1] = id end
        table.sort(keys)
        for j = 1, #keys do parts[#parts + 1] = keys[j] .. "=" .. tostring(os[keys[j]]) end
    end
    return table.concat(parts, ",")
end

-- Structural only: SLOT own-only state is NOT part of the signature -- it
-- maps to slot filter strings, which update live (a swap for an own-only
-- toggle cost a full container rebuild on every button). CHAIN groups bake
-- own-only into their declaration-fixed group filter string, so their
-- (uniform) own state IS structural and swaps.
local function BmSignature(inds, specKey, mode)
    -- Spec-scoped sentinel: the simple grid's container exists only for
    -- tracked specs, so a spec change must swap even in simple mode.
    if mode == "simple" or not inds then return "simple:" .. tostring(specKey) end
    local parts = { specKey or "?" }
    for i = 1, #inds do
        local ind = inds[i]
        -- Truthy enabled on purpose: matches the legacy lookup gate.
        -- framealpha and border indicators are deliberately treated as
        -- disabled (removed in 12.1 unless APIs land; options carry the
        -- removal notice overlays).
        if ind.enabled and ind.type ~= "framealpha" and ind.type ~= "border" then
            local cmode = BmChainMode(ind) -- group<->slots transition is structural
            local ownTag = ""
            if cmode == "g" then
                ownTag = BmEffOwnOnly(ind, (ind.spells and ind.spells[1]) or 0) and ":o" or ":a"
            end
            -- The all-specs flag is structural: it changes which spells
            -- survive the borrow filter in BuildBmSlots, so flipping it must
            -- swap the container.
            parts[#parts + 1] = tostring(ind.id or ("x" .. i)) .. ":" .. (ind.type or "icon")
                .. ":" .. table.concat(ind.spells or {}, "-")
                .. ":" .. tostring(ind.showWhen or "present")
                .. ":" .. cmode .. ownTag
                .. (ind.showOwnAllSpecs and ":s" or "")
        end
    end
    return table.concat(parts, "|")
end

-- Candidate filters for one slot: chain slots pass their spellID, effect
-- slots pass the indicator's (borrow-filtered) spell list. Own-only is NOT
-- expressed here: the isFromPlayerOrPlayerPet candidate boolean matches
-- auras cast by ANY player (field-verified: same-spec allies' buffs passed
-- it), so own-cast filtering rides the PLAYER filter token instead.
local function BuildBmCand(ind, spells, spellID)
    local include
    if spellID then
        include = BmIncludeMap(spellID)
    else
        include = {}
        for k = 1, #(spells or {}) do
            for id in pairs(BmIncludeMap(spells[k])) do include[id] = true end
        end
    end
    return { includeSpellIDs = include }
end

-- Filter tokens for one slot/chain group: PLAYER (strictly the local
-- player's casts) when the indicator is own-only for this spell. Chains
-- are own-only-uniform by construction (mixed own-only forces slot mode).
local function BuildBmFilter(ind, spellID, spells)
    if BmEffOwnOnly(ind, spellID or (spells and spells[1]) or 0) then
        return { "HELPFUL", "PLAYER" }
    end
    return { "HELPFUL" }
end

local function BmColor(c, dr, dg, db2)
    if not c then return dr, dg, db2 end
    return c.r or c[1] or dr, c.g or c[2] or dg, c.b or c[3] or db2
end

-- Cached per config: unchanged settings return the SAME curve object, so
-- the restyle pass can skip the duration-text re-registration.
local bmCurveCache = {}
local function BmThresholdCurve(ind)
    if not (ind.thresholdEnabled and C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    local tr, tg, tb = BmColor(ind.thresholdColor, 1, 0.25, 0.25)
    local nr, ng, nb = BmColor(ind.durationTextColor, 1, 1, 1)
    local hash = string.format("%d|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f",
        ind.threshold or 3, tr, tg, tb, nr, ng, nb)
    local curve = bmCurveCache[hash]
    if curve then return curve end
    curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(tr, tg, tb))
    curve:AddPoint(ind.threshold or 3, CreateColor(nr, ng, nb))
    bmCurveCache[hash] = curve
    return curve
end

-- Base frame level = the unit button's (slot -> container -> unit button).
local function BmBaseLevel(button)
    local container = button:GetParent()
    local unitButton = container and container:GetParent()
    if unitButton then return unitButton:GetFrameLevel() end
    return 2
end

-- The color curve binds at SetDurationText registration, so a changed
-- threshold config needs a re-registration on restyle. bmRegistered is set
-- AFTER the initial registration, keeping this pass inert during init
-- (applyExtra runs before it). Curves are cached: unchanged settings yield
-- the same object and skip the rebind entirely. 68914 fixed the engine's
-- one-arg SetTextColorCurve consumer, so the curve is live for the first
-- time (new schema: textColor = { curve, property }).
local function BmRebindDurationCurve(button, dd, style)
    if dd.duration and dd.bmRegistered and style.durationColorCurve ~= dd.bmCurve then
        local durationOpts = AK.BuildDurationTextOpts(AK.GetDurationFormatter(),
            style.durationColorCurve)
        local ok, full = AK.SetDurationTextSafe(button, dd.duration, durationOpts)
        -- Stamp only when the requested option set actually landed: a denied
        -- or degraded registration (restriction, or the curve half rejected)
        -- must leave the curve unstamped so the restriction-lift retry or
        -- the next restyle re-runs it.
        if ok and (full or not style.durationColorCurve) then
            dd.bmCurve = style.durationColorCurve
        end
    end
end

-- Display-level Icon Glow (v2 DISPLAY section): a PERMANENT glow on every
-- visible icon of the group -- not threshold-gated. Same mechanics as the
-- CC debuff glow overlay: our child frame rides the button's visibility,
-- driver-based styles remap to their FlipBook equivalents so restricted
-- content animates identically, and params are cached on the overlay (our
-- frame, custom fields allowed) so a steady glow never resets on restyles.
local function ApplyBmIconGlow(button, dd, style)
    local Glows = EllesmereUI.Glows
    if not Glows then return end
    local gType = style.bmGlowType or 0
    if gType > 0 and Glows.RestrictionSafeStyle then
        gType = Glows.RestrictionSafeStyle(gType)
    end
    if gType > 0 and Glows.StartGlow then
        local gov = dd.bmGlow
        if not gov then
            gov = CreateFrame("Frame", nil, button)
            gov:SetAllPoints(button)
            -- Just above the border, below the duration/stack text.
            if dd.stackCarrier then
                gov:SetFrameLevel(dd.stackCarrier:GetFrameLevel() - 1)
            else
                gov:SetFrameLevel(button:GetFrameLevel() + 1)
            end
            gov:EnableMouse(false)
            dd.bmGlow = gov
        end
        local cr, cg, cb = style.bmGlowR or 1.0, style.bmGlowG or 0.776, style.bmGlowB or 0.376
        if style.bmGlowClassColor then
            local _, classFile = UnitClass("player")
            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
        local sz = style.width or 18
        if (not gov._euiGlowActive) or gov._bmStyle ~= gType or gov._bmW ~= sz
           or gov._bmCR ~= cr or gov._bmCG ~= cg or gov._bmCB ~= cb then
            Glows.StartGlow(gov, gType, sz, cr, cg, cb)
            gov._bmStyle, gov._bmW = gType, sz
            gov._bmCR, gov._bmCG, gov._bmCB = cr, cg, cb
        end
    elseif dd.bmGlow and dd.bmGlow._euiGlowActive and Glows.StopGlow then
        Glows.StopGlow(dd.bmGlow)
    end
end

-- applyExtra for icon slots: shared text pass + opacity + BM frame levels.
-- hideIcon = legacy text-only mode: icon, swipe and border hidden (via the
-- style flags), duration text and stacks unaffected.
local function ApplyBmIconExtra(button, dd, style)
    ApplyRFDebuffText(button, dd, style)
    if dd.icon then dd.icon:SetShown(not style.hideIcon) end
    -- Button-object calls are denied while auras are secret (12.1 access
    -- restriction): the base level is read ONCE inside the creation window
    -- and cached, and alpha/level writes are change-guarded with the stamp
    -- written AFTER the call (a denied write throws; the worker defers the
    -- key to the restriction-lift re-queue).
    local alpha = style.alpha or 1
    if dd.bmAlpha ~= alpha then
        button:SetAlpha(alpha)
        dd.bmAlpha = alpha
    end
    local base = dd.bmBase
    if not base then
        base = BmBaseLevel(button)
        dd.bmBase = base
    end
    local lvl = base + (style.levelOffset or 13)
    if dd.bmLvl ~= lvl then
        button:SetFrameLevel(lvl)
        dd.bmLvl = lvl
    end
    if dd.cooldown then dd.cooldown:SetFrameLevel(lvl + 1) end
    if dd.borderHost then dd.borderHost:SetFrameLevel(lvl + 1) end
    if dd.stackCarrier then dd.stackCarrier:SetFrameLevel(base + BM_FRAMELVL_TEXT) end
    BmRebindDurationCurve(button, dd, style)
    ApplyBmIconGlow(button, dd, style)
end

-- Buff/HoT tooltip gate (profile-root "Hide Buff Tooltips" toggle, default
-- hidden). Engine aura buttons render their own tooltip when mouse motion is
-- on -- and unlike the legacy path it shows the real aura even while secret.
-- Mirrors the legacy pools' BM_SetTipTarget gating; effect slots (healthcolor/
-- border) stay motion-off always since they overlay the health bar.
local function BmTipsOff()
    local p = ns.db and ns.db.profile
    return not p or p.buffHideTooltips ~= false
end

local function BuildBmIconStyle(ind, iscale, size)
    local br, bg, bb = BmColor(ind.indBorderColor, 0, 0, 0)
    local hideIcon = ind.hideIcon == true
    return {
        width = size,
        height = size,
        iconCrop = true,
        iconZoom = 0.08,
        hideIcon = hideIcon,
        border = (not hideIcon and (ind.indBorderSize or 1) > 0)
            and { br, bg, bb, 1, size = ind.indBorderSize or 1 } or nil,
        cooldownReverse = true,
        hideSwipe = hideIcon or (ind.showDuration == false),
        noDefaultFonts = true,
        hideDurationText = not ind.showDurationText,
        durSize = ind.durationTextSize,
        durColor = ind.durationTextColor,
        durOffX = ind.durationTextOffsetX,
        durOffY = ind.durationTextOffsetY,
        durationColorCurve = BmThresholdCurve(ind),
        showStacks = ind.showStacks ~= false,
        stackSize = ind.stacksTextSize,
        stackColor = ind.stacksTextColor,
        stackOffX = ind.stacksOffsetX or -1,
        stackOffY = ind.stacksOffsetY or 2,
        alpha = (ind.iconOpacity or 100) / 100,
        levelOffset = BM_FRAMELVL[ind.frameLevel or "medium"] or 13,
        noTooltips = BmTipsOff(),
        bmGlowType = ind.displayGlowType or 0,
        bmGlowClassColor = ind.displayGlowClassColor,
        bmGlowR = ind.displayGlowR,
        bmGlowG = ind.displayGlowG,
        bmGlowB = ind.displayGlowB,
        applyExtra = ApplyBmIconExtra,
    }
end

-- PP border on a bare-slot host with create-once semantics, so border size
-- can toggle from 0 without a container swap.
local function BmUpdateBorder(dd, host, size, r, g, b, a)
    local PP = EllesmereUI.PP
    if not (PP and host) then return end
    if (size or 0) > 0 then
        if dd.bmBorderMade then
            PP.UpdateBorder(host, size, r, g, b, a)
        else
            PP.CreateBorder(host, r, g, b, a, size, "OVERLAY", 7)
            dd.bmBorderMade = true
        end
        host:Show()
    else
        host:Hide()
    end
end

-- Bare-slot styling passes. These run at init (guarded: regions may not
-- exist yet on the first ApplyStyleToRegions call) and on every Restyle,
-- so square/bar/effect settings live-update like everything else. Each
-- style table carries its indicator ref as style.ind.
local function BmApplySquare(button, dd, style)
    if not dd.tex then return end
    local ind = style.ind
    local r, g, b = BmColor(style.sqColor, 12 / 255, 210 / 255, 157 / 255)
    dd.tex:SetColorTexture(r, g, b, 1)
    if dd.cooldown then dd.cooldown:SetShown(ind.showDuration ~= false) end
    local br, bg2, bb = BmColor(ind.indBorderColor, 0, 0, 0)
    BmUpdateBorder(dd, dd.borderHost, ind.indBorderSize or 1, br, bg2, bb, 1)
    ApplyRFDebuffText(button, dd, style)
    -- Cached base + change-guarded level: see ApplyBmIconExtra.
    local base = dd.bmBase
    if not base then
        base = BmBaseLevel(button)
        dd.bmBase = base
    end
    local lvl = base + (BM_FRAMELVL[ind.frameLevel or "medium"] or 13)
    if dd.bmLvl ~= lvl then
        button:SetFrameLevel(lvl)
        dd.bmLvl = lvl
    end
    if dd.stackCarrier then dd.stackCarrier:SetFrameLevel(base + BM_FRAMELVL_TEXT) end
    BmRebindDurationCurve(button, dd, style)
end

local function BmApplyBar(button, dd, style)
    if not dd.bar then return end
    -- Bars have no ApplyRFDebuffText pass, so the tooltip motion gate is
    -- applied here (same change-guard as the shared applier).
    if button.SetMouseMotionEnabled then
        local motion = not style.noTooltips
        if dd.rfMotion ~= motion then
            dd.rfMotion = motion
            button:SetMouseMotionEnabled(motion)
        end
    end
    local ind = style.ind
    local r, g, b = BmColor(ind.color, 12 / 255, 210 / 255, 157 / 255)
    dd.bar:GetStatusBarTexture():SetVertexColor(r, g, b, (ind.barColorOpacity or 100) / 100)
    dd.bar:SetReverseFill(ind.reverseFill == true)
    local bgr, bgg, bgb = BmColor(ind.barBgColor, 0, 0, 0)
    dd.barBg:SetColorTexture(bgr, bgg, bgb, (ind.barBgOpacity or 50) / 100)
    -- Cached base + change-guarded level: see ApplyBmIconExtra.
    local base = dd.bmBase
    if not base then
        base = BmBaseLevel(button)
        dd.bmBase = base
    end
    local lvl = base + (BM_FRAMELVL[ind.frameLevel or "behindBorders"] or 7)
    if dd.bmLvl ~= lvl then
        button:SetFrameLevel(lvl)
        dd.bmLvl = lvl
    end
end

local function BmApplyEffect(button, dd, style)
    local ind = style.ind
    if ind.type == "healthcolor" then
        if dd.tex then
            local r, g, b = BmColor(ind.color, 0, 1, 0)
            dd.tex:SetColorTexture(r, g, b, (ind.opacity or 100) / 100)
        end
    elseif ind.type == "border" then
        local r, g, b = BmColor(ind.color, 0.05, 0.82, 0.62)
        BmUpdateBorder(dd, dd.borderHost, ind.borderWidth or 2, r, g, b, (ind.borderOpacity or 100) / 100)
    end
end

-- Bare-slot extraInits: region creation only (once per slot button); all
-- styling flows through the apply passes above. Squares/bars start
-- mouse-transparent and the apply passes re-drive motion per the buff
-- tooltip setting; effect slots stay transparent always (they overlay the
-- health bar / unit button).
local function BmSquareInit(button, dd, style, ind, health)
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    dd.tex = button:CreateTexture(nil, "ARTWORK")
    dd.tex:SetAllPoints(button)

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)
    dd.cooldown = cd
    button:SetDurationCooldown(cd)

    dd.borderHost = CreateFrame("Frame", nil, button)
    dd.borderHost:SetAllPoints(button)
    dd.borderHost:SetFrameLevel(button:GetFrameLevel() + 1)

    -- Duration/stack text, same carrier arrangement as the standard icon
    -- regions (above the swipe). Fonts MUST be applied before the engine
    -- registrations below (style-before-register contract).
    dd.stackCarrier = CreateFrame("Frame", nil, button)
    dd.stackCarrier:SetAllPoints(button)
    dd.stackCarrier:SetFrameLevel(cd:GetFrameLevel() + 1)
    dd.stack = dd.stackCarrier:CreateFontString(nil, "OVERLAY")
    dd.duration = dd.stackCarrier:CreateFontString(nil, "OVERLAY")

    BmApplySquare(button, dd, style)

    button:SetApplicationCount(dd.stack, {})
    local durationOpts = AK.BuildDurationTextOpts(AK.GetDurationFormatter(),
        style.durationColorCurve)
    local _, full = AK.SetDurationTextSafe(button, dd.duration, durationOpts)
    dd.bmRegistered = true
    -- Creation-window registration is always legal; the curve stamp still
    -- follows the full-success rule so a rejected curve half re-binds on
    -- the next restyle instead of being skipped as current.
    if full or not style.durationColorCurve then
        dd.bmCurve = style.durationColorCurve
    end
end

local function BmBarInit(button, dd, style, ind, health)
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    dd.bar = bar
    dd.barBg = bar:CreateTexture(nil, "BACKGROUND")
    dd.barBg:SetAllPoints(bar)

    local opts = {}
    if Enum.StatusBarInterpolation then opts.interpolation = Enum.StatusBarInterpolation.Immediate end
    if Enum.StatusBarTimerDirection then opts.direction = Enum.StatusBarTimerDirection.RemainingTime end
    button:SetDurationBar(bar, opts)

    BmApplyBar(button, dd, style)
end

local function BmEffectInit(button, dd, style, ind, health)
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    if ind.type == "healthcolor" then
        -- Level-tied with the health frame (NOT +1): the legacy overlay was a
        -- texture on the health frame itself, so the tint must sort against
        -- health's own regions by ARTWORK sublevel (above the fill at 0)
        -- while staying BELOW the heal absorb / heal prediction bars at
        -- health +1 and the shield bars at +3. At +1 this button tied the
        -- heal absorb bar on strata+level+layer+sublevel, so paint order
        -- fell to creation order and the tint blended on top of an opaque
        -- heal absorb. Anchored to the fill texture so it only covers the
        -- filled portion, not the empty/missing health area.
        button:SetFrameLevel(health:GetFrameLevel())
        dd.tex = button:CreateTexture(nil, "ARTWORK", nil, 2)
        local fillTex = health.GetStatusBarTexture and health:GetStatusBarTexture()
        if fillTex then
            dd.tex:SetAllPoints(fillTex)
        else
            dd.tex:SetAllPoints(health)
        end
    elseif ind.type == "border" then
        local unitButton = button:GetParent() and button:GetParent():GetParent()
        if unitButton then
            button:SetFrameLevel(unitButton:GetFrameLevel() + 11)
            dd.borderHost = CreateFrame("Frame", nil, button)
            dd.borderHost:SetAllPoints(unitButton)
            dd.borderHost:SetFrameLevel(button:GetFrameLevel())
        end
    end
    BmApplyEffect(button, dd, style)
end

-- Style factory per indicator kind; size only matters for icon/square,
-- spellID only for square (per-spell color; nil for shared chain styles).
local function BuildBmStyleFor(kind, ind, iscale, size, spellID)
    if kind == "icon" then
        return BuildBmIconStyle(ind, iscale, size)
    end
    if kind == "square" then
        return {
            width = size,
            height = size,
            noRegions = true,
            ind = ind,
            sqColor = BmSquareColor(ind, spellID),
            noDefaultFonts = true,
            hideSwipe = (ind.showDuration == false),
            hideDurationText = not ind.showDurationText,
            durSize = ind.durationTextSize,
            durColor = ind.durationTextColor,
            durOffX = ind.durationTextOffsetX,
            durOffY = ind.durationTextOffsetY,
            durationColorCurve = BmThresholdCurve(ind),
            showStacks = ind.showStacks ~= false,
            stackSize = ind.stacksTextSize,
            stackColor = ind.stacksTextColor,
            stackOffX = ind.stacksOffsetX or -1,
            stackOffY = ind.stacksOffsetY or 2,
            noTooltips = BmTipsOff(),
            applyExtra = BmApplySquare,
        }
    end
    if kind == "bar" then
        return { width = 1, height = 1, noRegions = true, ind = ind,
            noTooltips = BmTipsOff(), applyExtra = BmApplyBar }
    end
    return { width = 1, height = 1, noRegions = true, ind = ind, applyExtra = BmApplyEffect }
end

-- Geometry for ONE slot button. Split out of AnchorBmSlots so every slot's
-- extraInit can anchor its own button inside the creation window -- the
-- only place button SetSize/SetPoint is legal while auras are secret under
-- the 12.1 access restriction (BM builds run mid-instance: joiners,
-- in-key reloads). AnchorBmSlots re-runs it OOC on geometry changes.
local function BmAnchorOneSlot(f, m, health, hugBar, iscale)
    local ind = m.ind
    if m.kind == "icon" or m.kind == "square" then
        local size = m.size
        local step = size + (ind.spacing or 0) * iscale
        local cursor = (m.k - 1) * step
        local grow = ind.growDirection or "RIGHT"
        if grow == "CENTER" then cursor = cursor - ((m.count - 1) * step) / 2 end
        local gx, gy = 0, 0
        if grow == "LEFT" then gx = -cursor
        elseif grow == "DOWN" then gy = -cursor
        elseif grow == "UP" then gy = cursor
        else gx = cursor end
        local pos = ind.position or "TOPLEFT"
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint(pos, health, pos, (ind.offsetX or 0) * iscale + gx, (ind.offsetY or 0) * iscale + gy)
    elseif m.kind == "bar" then
        -- Mirrors the legacy BM_PlaceBar rules onto the slot button.
        local w = (ind.barWidth or 30) * iscale
        local h = (ind.barHeight or 4) * iscale
        local isVert = (ind.orientation or "HORIZONTAL") == "VERTICAL"
        local fullW, fullH
        if isVert then fullW, fullH = ind.barFullHeight, ind.barFullWidth
        else fullW, fullH = ind.barFullWidth, ind.barFullHeight end
        f:ClearAllPoints()
        if fullW and fullH then
            f:SetAllPoints(hugBar)
        elseif fullW then
            local pos = ind.position or "TOPLEFT"
            local vEdge = (pos:find("BOTTOM", 1, true) and "BOTTOM") or (pos:find("TOP", 1, true) and "TOP") or ""
            local oy = (ind.offsetY or 0) * iscale
            f:SetPoint(vEdge .. "LEFT", health, vEdge .. "LEFT", 0, oy)
            f:SetPoint(vEdge .. "RIGHT", health, vEdge .. "RIGHT", 0, oy)
            f:SetHeight(isVert and w or h)
        elseif fullH then
            local pos = ind.position or "TOPLEFT"
            local hEdge = (pos:find("RIGHT", 1, true) and "RIGHT") or (pos:find("LEFT", 1, true) and "LEFT") or ""
            local ox = (ind.offsetX or 0) * iscale
            f:SetPoint("TOP" .. hEdge, hugBar, "TOP" .. hEdge, ox, 0)
            f:SetPoint("BOTTOM" .. hEdge, hugBar, "BOTTOM" .. hEdge, ox, 0)
            f:SetWidth(isVert and h or w)
        else
            if isVert then f:SetSize(h, w) else f:SetSize(w, h) end
            f:SetPoint(ind.position or "TOPLEFT", health, ind.position or "TOPLEFT",
                (ind.offsetX or 0) * iscale, (ind.offsetY or 0) * iscale)
        end
    else
        -- Effect slots just need to exist somewhere; their regions
        -- anchor to the health bar / unit button themselves.
        f:SetSize(1, 1)
        f:ClearAllPoints()
        f:SetPoint("CENTER", health, "CENTER")
    end
end

-- Builds the slot spec list for the current indicator set, plus the list
-- of group-mode chain indicators (rendered as compacting flow containers).
-- Borrow specs (Enh/Ele/Prot/Ret) only get slots for the spells they can
-- cast, mirroring the legacy lookup restriction; positions renumber over
-- the usable list.
local function BuildBmSlots(inds, d, health, iscale, styleBase)
    local slots, meta, chains = {}, {}, {}
    -- Borrow-spec castability filtering is a LEGACY healer-tracking notion:
    -- v2 groups deliberately include other classes' spells (externals/raid
    -- CDs, any caster), so the filter would gut them on borrow specs.
    local borrow
    if not ns.BM2_Enabled and ns.BM_BorrowSpellFilter then
        borrow = ns.BM_BorrowSpellFilter()
    end
    for i = 1, #inds do
        local ind = inds[i]
        if ind.enabled and ind.type ~= "framealpha"
            and (ind.type == "icon" or ind.type == "square" or ind.type == "bar"
                 or ((ind.showWhen or "present") == "present")) then
            local spells = {}
            for k = 1, #(ind.spells or {}) do
                local sid = ind.spells[k]
                if not borrow or ind.showOwnAllSpecs or borrow[sid] then
                    spells[#spells + 1] = sid
                end
            end
            local kind = ind.type or "icon"
            if (kind == "icon" or kind == "square") and BmChainMode(ind) == "g" then
                if #spells > 0 then
                    chains[#chains + 1] = { ind = ind, spells = spells, idx = i }
                end
            elseif kind == "icon" or kind == "square" or kind == "bar" then
                for k = 1, #spells do
                    local spellID = spells[k]
                    local size = ((ind.size or 18) + ((ind.sizeOffsets and ind.sizeOffsets[spellID]) or 0)) * iscale
                    local slotKey = "bm" .. tostring(ind.id or ("x" .. i)) .. "_" .. k
                    local styleKey = styleBase .. ":" .. tostring(ind.id or ("x" .. i)) .. ":" .. k
                    -- Meta entry built FIRST so the extraInit closures below
                    -- can self-anchor with it inside the creation window
                    -- (post-creation slot SetPoint/SetSize is denied while
                    -- auras are secret -- 12.1 access restriction).
                    local mm = { key = slotKey, styleKey = styleKey, ind = ind, k = k, count = #spells,
                        kind = kind, size = size, spellID = spellID }
                    local entry = {
                        key = slotKey,
                        filter = BuildBmFilter(ind, spellID),
                        candidateFilters = BuildBmCand(ind, nil, spellID),
                        style = styleKey,
                    }
                    AK.styles[styleKey] = BuildBmStyleFor(kind, ind, iscale, size, spellID)
                    if kind == "icon" then
                        entry.extraInit = function(btn, dd, st)
                            dd.bmRegistered = true
                            dd.bmCurve = st.durationColorCurve
                            local h = ns.RF_AnchorHost and ns.RF_AnchorHost(health, ProxyFor(d)) or health
                            BmAnchorOneSlot(btn, mm, h, h and (h._euiHealth or h), iscale)
                        end
                    elseif kind == "square" then
                        entry.extraInit = function(btn, dd, st)
                            BmSquareInit(btn, dd, st, ind, health)
                            local h = ns.RF_AnchorHost and ns.RF_AnchorHost(health, ProxyFor(d)) or health
                            BmAnchorOneSlot(btn, mm, h, h and (h._euiHealth or h), iscale)
                        end
                    elseif kind == "bar" then
                        entry.extraInit = function(btn, dd, st)
                            BmBarInit(btn, dd, st, ind, health)
                            local h = ns.RF_AnchorHost and ns.RF_AnchorHost(health, ProxyFor(d)) or health
                            BmAnchorOneSlot(btn, mm, h, h and (h._euiHealth or h), iscale)
                        end
                    end
                    slots[#slots + 1] = entry
                    meta[#meta + 1] = mm
                end
            elseif kind == "healthcolor" then -- border: removed in 12.1 (see BmSignature)
                local slotKey = "bm" .. tostring(ind.id or ("x" .. i)) .. "_fx"
                local styleKey = styleBase .. ":" .. tostring(ind.id or ("x" .. i)) .. ":fx"
                AK.styles[styleKey] = BuildBmStyleFor(kind, ind, iscale, 1)
                local mm = { key = slotKey, styleKey = styleKey, ind = ind, kind = kind, spells = spells }
                slots[#slots + 1] = {
                    key = slotKey,
                    filter = BuildBmFilter(ind, nil, spells),
                    candidateFilters = BuildBmCand(ind, spells),
                    style = styleKey,
                    extraInit = function(btn, dd, st)
                        BmEffectInit(btn, dd, st, ind, health)
                        -- Self-park in the creation window (see icon branch).
                        local h = ns.RF_AnchorHost and ns.RF_AnchorHost(health, ProxyFor(d)) or health
                        BmAnchorOneSlot(btn, mm, h, h and (h._euiHealth or h), iscale)
                    end,
                }
                meta[#meta + 1] = mm
            end
        end
    end
    return slots, meta, chains
end

-- Anchors a chain container so its flow starts at the indicator position
-- and compacts along the grow direction. Legacy parity rule: the FIRST
-- icon's `pos` corner sits exactly on the same corner of the health bar
-- (icons render INSIDE the frame at that corner) and the chain grows
-- outward from there. The flow's start corner therefore gets offset by one
-- element dimension on any axis where it disagrees with the position point
-- (half a dimension on that point's centered axes). CENTER growth keeps
-- the run centered on the position point, with the vertical edge staying
-- flush like legacy.
local function AnchorBmChainContainer(container, health, ind, iscale, spellCount)
    if not container then return end
    local pos = ind.position or "TOPLEFT"
    local grow = ind.growDirection or "RIGHT"
    local size = (ind.size or 18) * iscale
    local ox = (ind.offsetX or 0) * iscale
    local oy = (ind.offsetY or 0) * iscale

    local posL = pos:find("LEFT", 1, true) ~= nil
    local posR = pos:find("RIGHT", 1, true) ~= nil
    local posT = pos:find("TOP", 1, true) ~= nil
    local posB = pos:find("BOTTOM", 1, true) ~= nil

    local per = tonumber(ind.iconsPerRow) or 0

    container:ClearAllPoints()
    local gH, gV
    if grow == "CENTER" then
        local point = (posT and "TOP") or (posB and "BOTTOM") or "CENTER"
        container:SetPoint(point, health, pos, ox, oy)
        -- Wrapped rows stack away from the anchored edge (simple-grid
        -- convention); the flow origin corner follows the stack direction.
        gH = "RIGHT"
        gV = (per > 0 and posB) and "UP" or "DOWN"
        AK.SetContainerAnchor(container, (gV == "UP") and "BOTTOMLEFT" or "TOPLEFT")
    else
        gH = (grow == "LEFT") and "LEFT" or "RIGHT"
        gV = (grow == "UP") and "UP" or "DOWN"
        -- Wrap away from the anchored edge (simple-grid convention): the
        -- cross-axis component only renders once wrapping is on, and the
        -- unwrapped derivation above is the legacy single-run behavior.
        if per > 0 then
            if grow == "LEFT" or grow == "RIGHT" then
                gV = posB and "UP" or "DOWN"
            else
                gH = posR and "LEFT" or "RIGHT"
            end
        end
        -- Flow origin corner = the corner both growth directions point away
        -- from; identical to the old fixed pick for every unwrapped combo.
        local corner = ((gV == "UP") and "BOTTOM" or "TOP")
            .. ((gH == "LEFT") and "RIGHT" or "LEFT")
        local dx, dy = 0, 0
        if corner:find("LEFT", 1, true) then
            if posR then dx = -size elseif not posL then dx = -size / 2 end
        else
            if posL then dx = size elseif not posR then dx = size / 2 end
        end
        if corner:find("TOP", 1, true) then
            if posB then dy = size elseif not posT then dy = size / 2 end
        else
            if posT then dy = -size elseif not posB then dy = -size / 2 end
        end
        container:SetPoint(corner, health, pos, ox + dx, oy + dy)
        AK.SetContainerAnchor(container, corner)
    end
    AK.SetContainerGrowth(container, FlowDir(gH), FlowDir(gV))
    local spacing = (ind.spacing or 0) * iscale
    local vertical = (grow == "UP" or grow == "DOWN")
    -- Grid wrap (12.1 feature -- live indicators were always linear runs):
    -- Icons Per Row > 0 caps each line at n cells; vertical orientations
    -- flip the flow axis so lines are COLUMNS (n tall, wrapping sideways).
    -- 0/nil = one unbounded line, the exact pre-grid behavior (explicit
    -- axis reset keeps pooled containers clean across retargets).
    if per > 0 then
        AK.SetContainerAxis(container, vertical)
        AK.SetContainerRowWidth(container, per * size + (per - 1) * spacing + 0.4)
    else
        AK.SetContainerAxis(container, false)
        AK.SetContainerRowWidth(container, vertical and (size + 0.4) or nil)
    end

    -- Element size/spacing feed the FLOW math (button SetSize is only the
    -- physical size), so geometry changes must re-drive the group layout.
    container:SetAuraGroupLayout("chain", {
        elementWidth = size, elementHeight = size,
        elementSpacing = spacing, lineSpacing = spacing,
    })

    -- Max Icons (12.1 feature): cap the chain group below its spell count.
    -- Runs here so both the acquire path and the geometry pass re-drive it
    -- live (the setter is dirty-mark cheap on unchanged values).
    if spellCount and spellCount > 0 then
        local cap = spellCount
        local maxI = tonumber(ind.maxIcons) or 0
        if maxI > 0 and maxI < cap then cap = maxI end
        container:SetAuraGroupMaxFrameCount("chain", cap)
    end
end

-- Per-styleKey fingerprint of the visual fields each BM style/apply pass
-- reads; restyles run only when one actually changed (styles are shared
-- per class, so the first button's check covers the rest). Primed at
-- container creation so swaps don't trigger a follow-up restyle storm.
local bmStyleFP = {}

-- Per-class fingerprint of own-only state; changes re-drive slot candidate
-- filters live (slots support that) instead of swapping containers.
local bmOwnFP = {}

local function BmVisualKey(kind, ind, size, font, spellID)
    -- BmTipsOff joins every interactive kind's key so the "Hide Buff
    -- Tooltips" toggle restyles (the fingerprint guards skip otherwise).
    if kind == "icon" then
        return FP(font, size, ind.iconOpacity, ind.hideIcon, ind.indBorderSize, CK(ind.indBorderColor),
            ind.showDuration, ind.showDurationText, ind.durationTextSize, CK(ind.durationTextColor),
            ind.durationTextOffsetX, ind.durationTextOffsetY, ind.thresholdEnabled, ind.threshold,
            CK(ind.thresholdColor), ind.showStacks, ind.stacksTextSize, CK(ind.stacksTextColor),
            ind.stacksOffsetX, ind.stacksOffsetY, ind.frameLevel, BmTipsOff())
    end
    if kind == "square" then
        return FP(font, size, CK(BmSquareColor(ind, spellID)), ind.showDuration, ind.indBorderSize,
            CK(ind.indBorderColor), ind.frameLevel, ind.showDurationText, ind.durationTextSize,
            CK(ind.durationTextColor), ind.durationTextOffsetX, ind.durationTextOffsetY,
            ind.thresholdEnabled, ind.threshold, CK(ind.thresholdColor), ind.showStacks,
            ind.stacksTextSize, CK(ind.stacksTextColor), ind.stacksOffsetX, ind.stacksOffsetY, BmTipsOff())
    end
    if kind == "bar" then
        return FP(CK(ind.color), ind.barColorOpacity, ind.reverseFill,
            CK(ind.barBgColor), ind.barBgOpacity, ind.frameLevel, BmTipsOff())
    end
    return FP(ind.type, CK(ind.color), ind.opacity, ind.borderWidth, ind.borderOpacity)
end

local function BmOwnKey(meta)
    local t = {}
    for i = 1, #meta do t[i] = BmOwnSig(meta[i].ind) end
    return table.concat(t, ";")
end

-- Geometry fingerprint over every input AnchorBmSlots reads. Slot-button
-- SetSize/SetPoint are engine-wrapped calls, so the anchor pass only
-- re-runs when a position/size input actually changed.
local function BmGeoFP(meta, iscale, s)
    -- powerUniformAnchors joins the geometry key: flipping it re-drives the
    -- slot anchor pass (AnchorBmSlots swaps its anchor host on it).
    local t = { tostring(iscale), tostring(s and s.powerUniformAnchors or false) }
    for i = 1, #meta do
        local m = meta[i]
        local ind = m.ind
        t[#t + 1] = FP(m.key, m.size, m.count, ind.spacing, ind.growDirection, ind.position,
            ind.offsetX, ind.offsetY, ind.barWidth, ind.barHeight, ind.barFullWidth,
            ind.barFullHeight, ind.orientation, ind.iconsPerRow, ind.maxIcons)
    end
    return table.concat(t, ";")
end

-- Anchors icon/square chain slots, chain containers, and bar/effect slots.
local function AnchorBmSlots(d, health, iscale)
    local frames = d.rfcBmFrames
    local meta = d.rfcBmMeta
    if not meta then return end
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, ProxyFor(d)) or health   -- Uniform Icon Anchoring
    -- Full Width/Height bar pins span the health bar itself; resolve back to
    -- the real bar when the swap above returned the full-height reference.
    local hugBar = health and (health._euiHealth or health)
    -- Slot-button geometry is denied while auras are secret (12.1 access
    -- restriction). Chain CONTAINERS are our frames and always re-anchor;
    -- slot buttons skip and the pass reports it, so the caller leaves its
    -- geometry fingerprint unstamped and the restriction-lift sweep
    -- re-enters. (Fresh builds are unaffected: every slot self-anchors in
    -- its extraInit, so a skipped build-time pass loses nothing.)
    local restricted = AK.AurasRestricted()
    local skipped = false
    for i = 1, #meta do
        local m = meta[i]
        if m.isChain then
            AnchorBmChainContainer(d.rfcBmChain and d.rfcBmChain[m.chainKey], health, m.ind, iscale,
                m.count or (m.ind.spells and #m.ind.spells))
        end
        local f = (not m.isChain) and frames and frames[m.key] or nil
        if f then
            if restricted then
                skipped = true
            else
                BmAnchorOneSlot(f, m, health, hugBar, iscale)
            end
        end
    end
    return skipped
end

------------------------------------------------------------------------------
-- Simple Setup grid (step 4b): the active spec's whole tracked-buff
-- whitelist as ONE flow group per button. Own casts only (the legacy scan
-- accepted any caster while auras were readable but was own-only under
-- secrecy via fingerprints; own-only is the intended behavior). Deltas:
-- vertical growth renders a single column (the flow wraps by row width
-- only, so Icons Per Row is horizontal-mode); within-grid order is the
-- engine sort, not scan order.
------------------------------------------------------------------------------

local bmSimpleFP = {}

local function BmSimpleSettings()
    return ns.db and ns.db.profile and ns.db.profile.bmSimple
end

local function BmSimpleCand()
    local wl = ns.BM_SimpleTrackedSpellIDs and ns.BM_SimpleTrackedSpellIDs() or {}
    -- Own-cast restriction is the PLAYER token on the group filter (the
    -- isFromPlayerOrPlayerPet boolean matches ANY player's casts).
    return { includeSpellIDs = wl }
end

local function BmSimpleCandFP(bs)
    local wl = ns.BM_SimpleTrackedSpellIDs and ns.BM_SimpleTrackedSpellIDs() or {}
    local t = {}
    for id in pairs(wl) do t[#t + 1] = id end
    table.sort(t)
    return table.concat(t, ",") .. "|" .. tostring(bs.maxBuffs or 8)
end

local function BmSimpleStyleFP(bs, font, iscale)
    return FP(font, iscale, bs.size, bs.iconZoom, bs.borderSize, CK(bs.borderColor), bs.showSwipe,
        bs.showDurText, bs.durTextSize, CK(bs.durTextColor), bs.durTextOffsetX, bs.durTextOffsetY,
        BmTipsOff())
end

local function BmSimpleGeoFP(bs, iscale, s)
    -- s = class proxy; powerUniformAnchors flips re-drive the anchor pass.
    return FP(iscale, bs.position, bs.growDirection, bs.size, bs.spacing, bs.iconsPerRow,
        bs.offsetX, bs.offsetY, s and s.powerUniformAnchors)
end

local function ApplyBmSimpleExtra(button, dd, style)
    ApplyRFDebuffText(button, dd, style)
    -- Cached base + change-guarded level: see ApplyBmIconExtra.
    local base = dd.bmBase
    if not base then
        base = BmBaseLevel(button)
        dd.bmBase = base
    end
    local lvl = base + 13
    if dd.bmLvl ~= lvl then
        button:SetFrameLevel(lvl)
        dd.bmLvl = lvl
    end
    if dd.cooldown then dd.cooldown:SetFrameLevel(base + 14) end
    if dd.borderHost then dd.borderHost:SetFrameLevel(base + 14) end
    if dd.stackCarrier then dd.stackCarrier:SetFrameLevel(base + BM_FRAMELVL_TEXT) end
end

local function BuildBmSimpleStyle(bs, iscale)
    local br, bg, bb = ColorParts(bs.borderColor, 0, 0, 0)
    local size = (bs.size or 18) * iscale
    return {
        width = size,
        height = size,
        iconCrop = true,
        iconZoom = bs.iconZoom or 0.08,
        border = (bs.borderSize or 1) > 0 and { br, bg, bb, 1, size = bs.borderSize or 1 } or nil,
        cooldownReverse = true,
        hideSwipe = (bs.showSwipe == false),
        noDefaultFonts = true,
        hideDurationText = not bs.showDurText,
        durSize = bs.durTextSize,
        durColor = bs.durTextColor,
        durOffX = bs.durTextOffsetX,
        durOffY = bs.durTextOffsetY,
        showStacks = false, -- the legacy grid has no stack text
        noTooltips = BmTipsOff(),
        applyExtra = ApplyBmSimpleExtra,
    }
end

-- Mirrors the legacy AnchorSimpleGrid: the grid's start corner pinned at
-- the same corner of the health bar, rows wrap after Icons Per Row and
-- stack away from the anchored edge; CENTER growth centers rows on the
-- anchor point.
local function AnchorBmSimpleContainer(container, health, bs, iscale, d)
    if not container then return end
    -- Uniform Icon Anchoring: bs is the bmSimple sub-table, so the toggle is
    -- read from the button's class proxy.
    if d and ns.RF_AnchorHost then health = ns.RF_AnchorHost(health, ProxyFor(d)) end
    local pos = bs.position or "topright"
    local corner = CORNERS[pos] or "TOPRIGHT"
    local grow = bs.growDirection or "LEFT"
    local size = (bs.size or 18) * iscale
    local spacing = (bs.spacing or 1) * iscale
    local perRow = bs.iconsPerRow or 4
    local ox = (bs.offsetX or 0) * iscale
    local oy = (bs.offsetY or 0) * iscale

    local horizontal = (grow ~= "UP" and grow ~= "DOWN")
    local bottomish = (pos == "bottomleft" or pos == "bottom" or pos == "bottomright")
    local rightish = (pos == "topright" or pos == "right" or pos == "bottomright")
    local vEdge = bottomish and "BOTTOM" or "TOP"
    local gV = bottomish and "UP" or "DOWN"

    container:ClearAllPoints()
    local anchorPoint, gH
    if not horizontal then
        gH = rightish and "LEFT" or "RIGHT" -- moot in a single column
        gV = grow
        anchorPoint = (grow == "UP" and "BOTTOM" or "TOP") .. (rightish and "RIGHT" or "LEFT")
        container:SetPoint(anchorPoint, health, corner, ox, oy)
    elseif grow == "CENTER" then
        gH = "RIGHT"
        anchorPoint = vEdge .. "LEFT"
        container:SetPoint(vEdge, health, corner, ox, oy)
    else
        gH = grow
        anchorPoint = vEdge .. ((grow == "LEFT") and "RIGHT" or "LEFT")
        container:SetPoint(anchorPoint, health, corner, ox, oy)
    end
    AK.SetContainerAnchor(container, anchorPoint)
    AK.SetContainerGrowth(container, FlowDir(gH), FlowDir(gV))

    local rowWidth
    if not horizontal then
        rowWidth = size + 0.4
    elseif perRow and perRow >= 2 then
        rowWidth = perRow * size + (perRow - 1) * spacing + 0.4
    end
    AK.SetContainerRowWidth(container, rowWidth)

    container:SetAuraGroupLayout("simple", {
        elementWidth = size, elementHeight = size,
        elementSpacing = spacing, lineSpacing = spacing,
    })
end

local function CreateBmSimpleContainer(button, health, d, unit, specKey)
    local bs = BmSimpleSettings() or {}
    local iscale = BmScaleFor(d)
    -- PERSISTENT container (engine frames are never freed; recreating per
    -- spec leaked a batch per spec). One un-scoped style key; spec swaps
    -- retarget the whitelist candidate live on the same frames.
    local styleKey = StyleKeyFor(d):gsub("debuff", "bmsimple")
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    AK.styles[styleKey] = BuildBmSimpleStyle(bs, iscale)

    if d.rfcBmSimple then
        local c = d.rfcBmSimple
        c:SetUnit(unit)
        c:SetAuraGroupMaxFrameCount("simple", bs.maxBuffs or 8)
        c:SetAuraGroupCandidateFilters("simple", BmSimpleCand())
        AK.RestyleSoon(styleKey)
        AnchorBmSimpleContainer(c, health, bs, iscale, d)
        c:SetShown(bs.showBuffs and true or false)
        local st = bmSimpleFP[styleKey]
        if not st then st = {}; bmSimpleFP[styleKey] = st end
        st.style = BmSimpleStyleFP(bs, font, iscale)
        st.cand = BmSimpleCandFP(bs)
        st.geo = BmSimpleGeoFP(bs, iscale, ProxyFor(d))
        return
    end

    local size = (bs.size or 18) * iscale
    local spacing = (bs.spacing or 1) * iscale
    -- Early-window shell when available (group add + finish are combat-
    -- legal); fresh creation only as the OOC fallback.
    local shell = d.rfcBmSimpleShell
    d.rfcBmSimpleShell = nil
    if shell then
        AK.AddGroupToContainer(shell, {
            key = "simple",
            filter = { "HELPFUL", "PLAYER" },
            maxFrameCount = bs.maxBuffs or 8,
            candidateFilters = BmSimpleCand(),
            sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
            style = styleKey,
            extraInit = function(btn, dd) dd.bmRegistered = true end,
            layout = {
                elementWidth = size, elementHeight = size,
                elementSpacing = spacing, lineSpacing = spacing,
            },
        })
        AK.FinishContainer(shell, unit)
        d.rfcBmSimple = shell
        AnchorBmSimpleContainer(shell, health, bs, iscale, d)
        shell:SetShown(bs.showBuffs and true or false)
        local st = bmSimpleFP[styleKey]
        if not st then st = {}; bmSimpleFP[styleKey] = st end
        st.style = BmSimpleStyleFP(bs, font, iscale)
        st.cand = BmSimpleCandFP(bs)
        st.geo = BmSimpleGeoFP(bs, iscale, ProxyFor(d))
        return
    end
    local c = AK.CreateContainer(button, unit, {
        point = { "CENTER", health, "CENTER" }, -- re-anchored below
        groups = {{
            key = "simple",
            filter = { "HELPFUL", "PLAYER" },
            maxFrameCount = bs.maxBuffs or 8,
            candidateFilters = BmSimpleCand(),
            sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
            style = styleKey,
            extraInit = function(btn, dd) dd.bmRegistered = true end,
            layout = {
                elementWidth = size, elementHeight = size,
                elementSpacing = spacing, lineSpacing = spacing,
            },
        }},
    })
    d.rfcBmSimple = c
    AnchorBmSimpleContainer(c, health, bs, iscale, d)
    c:SetShown(bs.showBuffs and true or false)

    local st = bmSimpleFP[styleKey]
    if not st then st = {}; bmSimpleFP[styleKey] = st end
    st.style = BmSimpleStyleFP(bs, font, iscale)
    st.cand = BmSimpleCandFP(bs)
    st.geo = BmSimpleGeoFP(bs, iscale, ProxyFor(d))
end

local function ReloadBmSimple(button, d, cls)
    local bs = BmSimpleSettings()
    if not bs then return end
    -- Coexistence: the base grid resolves its own state -- effective
    -- base-enabled (shim over the legacy mode key) plus its own spec key.
    local baseOn = (ns.BM_BaseActive and ns.BM_BaseActive()) or false
    local simpleKey = (ns.BM_SimpleSpecKey and ns.BM_SimpleSpecKey())
        or (ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey())
    local c = d.rfcBmSimple
    if not c then
        -- Enabled mid-session with no container: build on the queue
        -- (creation is combat-legal since 68914).
        if baseOn and simpleKey and bs.showBuffs and not d.rfcBmSimplePend then
            d.rfcBmSimplePend = true
            AK.QueueBuildJob(function()
                d.rfcBmSimplePend = nil
                if d.rfcBmSimple then return end
                if not (ns.BM_BaseActive and ns.BM_BaseActive()) then return end
                local sk = (ns.BM_SimpleSpecKey and ns.BM_SimpleSpecKey())
                    or (ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey())
                if not (sk and d.rfcHealth and d.rfcUnit) then return end
                CreateBmSimpleContainer(button, d.rfcHealth, d, d.rfcUnit, sk)
                -- Per-button visibility re-drive (same pattern as the
                -- rebuild path): clears the readable cache so SetShown and
                -- the secret range alpha re-apply to the fresh container.
                d.rfcAssist = nil
                if ns.RFC_ApplyAssistGate then
                    ns.RFC_ApplyAssistGate(button, d, d.rfcUnit)
                end
            end, "rf:bmsimple-ensure")
        end
        return
    end
    -- Untracked specs have no whitelist; an empty include-map's semantics
    -- are unverified, so the grid simply hides there.
    c:SetShown(d.rfcAssist ~= false and baseOn and simpleKey ~= nil
        and (bs.showBuffs and true or false))

    if not cls.simpleChecked then
        cls.simpleChecked = true
        cls.simpleKey = StyleKeyFor(d):gsub("debuff", "bmsimple")
        local st = bmSimpleFP[cls.simpleKey]
        if not st then st = {}; bmSimpleFP[cls.simpleKey] = st end
        local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
        local v = BmSimpleStyleFP(bs, font, cls.iscale)
        if st.style ~= v then
            st.style = v
            AK.styles[cls.simpleKey] = BuildBmSimpleStyle(bs, cls.iscale)
            AK.RestyleSoon(cls.simpleKey)
        end
        -- The whitelist is spec-resolved, so a spec change must re-drive
        -- the candidates even with unchanged settings (the old container
        -- REBUILD on spec change went away with the coexistence rework).
        v = BmSimpleCandFP(bs) .. "|" .. tostring(simpleKey)
        if st.cand ~= v then st.cand = v; cls.simpleCandDirty = true end
        v = BmSimpleGeoFP(bs, cls.iscale, ProxyFor(d))
        if st.geo ~= v then st.geo = v; cls.simpleGeoDirty = true end
    end
    if cls.simpleCandDirty then
        c:SetAuraGroupMaxFrameCount("simple", bs.maxBuffs or 8)
        c:SetAuraGroupCandidateFilters("simple", BmSimpleCand())
    end
    if cls.simpleGeoDirty then
        AnchorBmSimpleContainer(c, d.rfcHealth, bs, cls.iscale, d)
    end
end

-- Chain container POOL: engine frames are never freed, so releasing and
-- recreating a chain container on every structural edit permanently
-- leaked its 10-button batch (and spec swaps leaked one set per spec).
-- Pool entries persist for the session, keyed by kind + own-variant
-- (filter strings are declaration-fixed, so own-only needs its own
-- variant) + ordinal; a "swap" now retargets them live (candidate
-- filters, count, layout, anchor, style) -- no frame creation, no leak.
-- Unused entries park at count 0, hidden.
local bmPoolReloadPending = false
local function BmPoolReloadSoon()
    if bmPoolReloadPending then return end
    bmPoolReloadPending = true
    C_Timer.After(0.05, function()
        bmPoolReloadPending = false
        if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
    end)
end

-- Acquire (or lazily create) the pool entry for one chain indicator and
-- retarget it. Returns the container, or nil while its shell is still
-- pending on the OOC build queue (container shells cannot be created in
-- combat -- probe T3 zombie).
local function BmAcquireChain(button, d, health, ind, spells, iscale, counters)
    local pool = d.rfcBmPool
    if not pool then pool = {}; d.rfcBmPool = pool end
    local kind = ind.type or "icon"
    local own = BmEffOwnOnly(ind, spells[1] or 0)
    local ck = kind .. (own and ":o" or ":a")
    local n = (counters[ck] or 0) + 1
    counters[ck] = n
    local poolKey = ck .. n
    local styleKey = StyleKeyFor(d):gsub("debuff", "bmpool") .. ":" .. poolKey
    local size = (ind.size or 18) * iscale

    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    local vk = BmVisualKey(kind, ind, size, font)
    if bmStyleFP[styleKey] ~= vk then
        bmStyleFP[styleKey] = vk
        AK.styles[styleKey] = BuildBmStyleFor(kind, ind, iscale, size)
        AK.RestyleSoon(styleKey)
    end

    local function ChainExtraInit()
        if kind == "square" then
            return function(btn, dd, st) BmSquareInit(btn, dd, st, nil, nil) end
        end
        return function(btn, dd, st)
            dd.bmRegistered = true
            dd.bmCurve = st.durationColorCurve
        end
    end

    local entry = pool[poolKey]
    if entry == nil then
        -- Bare early-window shells are variant-agnostic (no group yet):
        -- claim one and complete it right here -- group add + finish are
        -- combat-legal, so chains bind even mid-combat after a reload.
        local shell = d.rfcBmShellPool and table.remove(d.rfcBmShellPool)
        if shell then
            local filter
            if own then filter = { "HELPFUL", "PLAYER" } else filter = { "HELPFUL" } end
            AK.AddGroupToContainer(shell, {
                key = "chain", filter = filter, maxFrameCount = 0,
                sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
                style = styleKey, extraInit = ChainExtraInit(),
            })
            AK.FinishContainer(shell, button:GetAttribute("unit") or "player")
            entry = { container = shell }
            pool[poolKey] = entry
        else
            pool[poolKey] = "pending"
            local filter
            if own then filter = { "HELPFUL", "PLAYER" } else filter = { "HELPFUL" } end
            AK.QueueBuildJob(function()
                local cc = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
                AK.AddGroupToContainer(cc, {
                    key = "chain", filter = filter, maxFrameCount = 0,
                    sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
                    style = styleKey, extraInit = ChainExtraInit(),
                })
                AK.FinishContainer(cc, button:GetAttribute("unit") or "player")
                pool[poolKey] = { container = cc }
                BmPoolReloadSoon() -- rebind the buttons waiting on this shell
            end, "rf:bmpool-shell")
            return nil, styleKey
        end
    elseif entry == "pending" then
        return nil, styleKey
    end

    local cc = entry.container
    entry.parked = nil
    cc:SetUnit(button:GetAttribute("unit") or "player")
    cc:SetAuraGroupCandidateFilters("chain", BuildBmCand(ind, spells))
    AnchorBmChainContainer(cc, ns.RF_AnchorHost and ns.RF_AnchorHost(health, ProxyFor(d)) or health, ind, iscale, #spells)
    cc:SetShown(d.rfcAssist ~= false)
    return cc, styleKey
end

-- Parks every pool entry not re-bound by the current pass (count 0 +
-- hidden; the parked flag keeps repeat parks free).
local function BmParkUnbound(d, counters)
    local pool = d.rfcBmPool
    if not pool then return end
    for pk, entry in pairs(pool) do
        if type(entry) == "table" then
            local prefix, idx = pk:match("^(.-)(%d+)$")
            local bound = prefix and idx and counters and counters[prefix]
                and tonumber(idx) <= counters[prefix]
            if not bound and not entry.parked then
                entry.parked = true
                entry.container:SetAuraGroupMaxFrameCount("chain", 0)
                entry.container:SetShown(false)
            end
        end
    end
end

local function CreateBmContainer(button, health, d, unit)
    local inds, specKey, mode = BmIndicators()
    local sig = BmSignature(inds, specKey, mode)
    -- Base grid: independent of the custom side (coexistence). Built here
    -- when active; mid-session enables build via ReloadBmSimple's ensure.
    local simpleKey = (ns.BM_SimpleSpecKey and ns.BM_SimpleSpecKey()) or specKey
    if ns.BM_BaseActive and ns.BM_BaseActive() and simpleKey then
        CreateBmSimpleContainer(button, health, d, unit, simpleKey)
    elseif d.rfcBmSimple then
        d.rfcBmSimple:SetShown(false)
    end
    if not inds then
        d.rfcBmSig = sig
        BmParkUnbound(d, nil) -- custom-side chain pool parks
        return
    end

    local iscale = BmScaleFor(d)
    local styleBase = StyleKeyFor(d):gsub("debuff", "bm")
    local slots, meta, chains = BuildBmSlots(inds, d, health, iscale, styleBase)

    if #slots > 0 then
        -- Early-window shell when available (slot adds + finish are
        -- combat-legal); fresh creation only as the OOC fallback.
        local container = d.rfcBmSlotsShell
        d.rfcBmSlotsShell = nil
        local frames
        if container then
            frames = {}
            for i = 1, #slots do
                frames[slots[i].key] = AK.AddSlotToContainer(container, slots[i])
            end
            AK.FinishContainer(container, unit)
        else
            container, frames = AK.CreateContainer(button, unit, {
                point = { "CENTER", health, "CENTER" },
                slots = slots,
            })
        end
        d.rfcBm = container
        d.rfcBmFrames = frames
    end

    -- Group-mode chains render through the persistent per-button POOL:
    -- acquired entries are retargeted live (no creation, no leak); a chain
    -- whose shell is still building on the OOC queue binds on the deferred
    -- pool reload (sig stays nil so that reload re-enters here).
    local counters = {}
    local pendingChains = false
    local chainContainers = nil
    for ci = 1, #chains do
        local ch = chains[ci]
        local ind = ch.ind
        local chainKey = tostring(ind.id or ("x" .. ch.idx))
        local size = (ind.size or 18) * iscale
        local cc, poolStyleKey = BmAcquireChain(button, d, health, ind, ch.spells, iscale, counters)
        if cc then
            chainContainers = chainContainers or {}
            chainContainers[chainKey] = cc
            meta[#meta + 1] = { key = "chain_" .. chainKey, styleKey = poolStyleKey, ind = ind,
                kind = ind.type, isChain = true, chainKey = chainKey, size = size,
                count = #ch.spells, spells = ch.spells }
        else
            pendingChains = true
        end
    end
    d.rfcBmChain = chainContainers
    BmParkUnbound(d, counters)

    d.rfcBmMeta = meta
    d.rfcBmSig = sig
    -- Chains whose pool shells are still building bind later through
    -- BmRebindPendingChains (chains-only; never re-churns the slots
    -- container), driven by the deferred pool reload.
    d.rfcBmChainsPending = pendingChains or nil
    AnchorBmSlots(d, health, iscale)
    d.rfcBmGeo = BmGeoFP(meta, iscale, ProxyFor(d))

    -- Prime the fingerprint caches with what was just built, so the next
    -- reload after a swap/login compares equal instead of storming.
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    for i = 1, #meta do
        local m = meta[i]
        if m.styleKey then
            bmStyleFP[m.styleKey] = BmVisualKey(m.kind, m.ind, m.size, font, m.spellID)
        end
    end
    bmOwnFP[StyleKeyFor(d)] = BmOwnKey(meta)
end

-- Chains-only rebind for pool shells that finished building after the
-- main pass. Rebuilds the chain view/meta tail; never touches the slots
-- container. Runs from ReloadBm when d.rfcBmChainsPending is set.
local function BmRebindPendingChains(button, d, cls)
    if not d.rfcBmChainsPending then return end
    if not cls.inds or not d.rfcHealth then return end
    local health = d.rfcHealth
    local iscale = cls.iscale
    -- Legacy-only castability filter (see BuildBmSlots).
    local borrow
    if not ns.BM2_Enabled and ns.BM_BorrowSpellFilter then
        borrow = ns.BM_BorrowSpellFilter()
    end
    local counters = {}
    local meta = {}
    local old = d.rfcBmMeta or {}
    for i = 1, #old do
        if not old[i].isChain then meta[#meta + 1] = old[i] end
    end
    local chainContainers = nil
    local pending = false
    for i = 1, #cls.inds do
        local ind = cls.inds[i]
        if ind.enabled and (ind.type == "icon" or ind.type == "square")
            and BmChainMode(ind) == "g" then
            local spells = {}
            for k = 1, #(ind.spells or {}) do
                local sid = ind.spells[k]
                if not borrow or ind.showOwnAllSpecs or borrow[sid] then
                    spells[#spells + 1] = sid
                end
            end
            if #spells > 0 then
                local chainKey = tostring(ind.id or ("x" .. i))
                local size = (ind.size or 18) * iscale
                local cc, poolStyleKey = BmAcquireChain(button, d, health, ind, spells, iscale, counters)
                if cc then
                    chainContainers = chainContainers or {}
                    chainContainers[chainKey] = cc
                    meta[#meta + 1] = { key = "chain_" .. chainKey, styleKey = poolStyleKey,
                        ind = ind, kind = ind.type, isChain = true, chainKey = chainKey,
                        size = size, count = #spells, spells = spells }
                else
                    pending = true
                end
            end
        end
    end
    d.rfcBmChain = chainContainers
    BmParkUnbound(d, counters)
    d.rfcBmMeta = meta
    d.rfcBmChainsPending = pending or nil
    -- Newly-bound chains default to full alpha; re-drive the trust gate so
    -- the secret range alpha and SetShown state apply immediately instead
    -- of waiting for the next assist sweep.
    if chainContainers then
        d.rfcAssist = nil
        if ns.RFC_ApplyAssistGate then
            ns.RFC_ApplyAssistGate(button, d, button:GetAttribute("unit"))
        end
    end
end

local function BmRefreshSizes(meta, iscale)
    for i = 1, #meta do
        local m = meta[i]
        if m.kind == "icon" or m.kind == "square" then
            m.size = ((m.ind.size or 18)
                + ((m.spellID and m.ind.sizeOffsets and m.ind.sizeOffsets[m.spellID]) or 0)) * iscale
        end
    end
end

-- Signature/visual/geometry fingerprints are identical for every button of
-- a class, so they compute ONCE per class per reload (a per-button pass
-- rebuilt the same strings 40x in raids). The cls table is cached by the
-- caller for the duration of one RFC_ReloadAll pass.
local function BmClassPass(d)
    local cls = {}
    cls.inds, cls.specKey, cls.mode = BmIndicators()
    cls.sig = BmSignature(cls.inds, cls.specKey, cls.mode)
    cls.iscale = BmScaleFor(d)
    cls.styleKey = StyleKeyFor(d)
    return cls
end

-- Style checks run against the first container-carrying button's metas;
-- AK.Restyle reaches every registered button of the style either way.
-- Own-only changes flag a live candidate-filter re-drive (per button,
-- below) rather than a container swap.
local function BmCheckStyles(cls, meta)
    cls.stylesChecked = true
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    for i = 1, #meta do
        local m = meta[i]
        if m.styleKey then
            local vk = BmVisualKey(m.kind, m.ind, m.size, font, m.spellID)
            if bmStyleFP[m.styleKey] ~= vk then
                bmStyleFP[m.styleKey] = vk
                AK.styles[m.styleKey] = BuildBmStyleFor(m.kind, m.ind, cls.iscale, m.size, m.spellID)
                AK.RestyleSoon(m.styleKey)
            end
        end
    end
    local ownKey = BmOwnKey(meta)
    if bmOwnFP[cls.styleKey] ~= ownKey then
        bmOwnFP[cls.styleKey] = ownKey
        cls.ownDirty = true
    end
end

local function ReloadBm(button, d, s, cls)
    if cls.sig ~= d.rfcBmSig then
        if InCombatLockdown() then
            d.rfcBmPending = true
            return
        end
        -- Release the SLOTS container only (deregisters its buttons from
        -- the restyle registry). The chain POOL and the simple container
        -- persist forever: engine frames are never freed, so releasing
        -- them leaked their batches on every structural edit -- the
        -- rebuild retargets them live instead.
        if d.rfcBm then AK.ReleaseContainer(d.rfcBm) end
        d.rfcBm, d.rfcBmFrames, d.rfcBmMeta, d.rfcBmChain = nil, nil, nil, nil
        d.rfcBmSig = nil
        -- Rebuild through the shared scheduler; the job reads live settings
        -- at run time, so rapid consecutive changes converge.
        AK.QueueBuildJob(function()
            -- Already rebuilt by a peer job: sig restored, OR the slots
            -- container exists (sig may legitimately still be nil while
            -- pool shells are pending -- rebuilding again would orphan it).
            if d.rfcBm or d.rfcBmSig ~= nil then return end
            if InCombatLockdown() then d.rfcBmPending = true; return end
            local unit = button:GetAttribute("unit") or "player"
            CreateBmContainer(button, d.rfcHealth, d, unit)
            -- Fresh/retargeted containers may default shown at alpha 1;
            -- clear the readable state cache and re-drive the trust gate so
            -- SetShown and the secret range alpha re-apply immediately.
            d.rfcAssist = nil
            if ns.RFC_ApplyAssistGate then ns.RFC_ApplyAssistGate(button, d, unit) end
        end, "rf:bm-rebuild")
        return
    end

    -- Coexistence: the base grid reloads on every pass regardless of the
    -- custom side (it self-resolves enabled/spec state and no-ops cheaply).
    ReloadBmSimple(button, d, cls)

    BmRebindPendingChains(button, d, cls)

    if (d.rfcBm or d.rfcBmChain) and cls.inds then
        if not cls.stylesChecked then
            BmRefreshSizes(d.rfcBmMeta, cls.iscale)
            BmCheckStyles(cls, d.rfcBmMeta)
            cls.geo = BmGeoFP(d.rfcBmMeta, cls.iscale, ProxyFor(d))
        end
        if d.rfcBmGeo ~= cls.geo then
            BmRefreshSizes(d.rfcBmMeta, cls.iscale)
            local skippedSlots = AnchorBmSlots(d, d.rfcHealth, cls.iscale)
            if skippedSlots then
                -- Slot geometry denied while auras are secret: fingerprint
                -- stays unstamped so the restriction-lift sweep re-runs it.
                ns._rfcLiftDirty = true
            else
                d.rfcBmGeo = cls.geo
            end
        end
        if cls.ownDirty then
            for i = 1, #d.rfcBmMeta do
                local m = d.rfcBmMeta[i]
                -- Chain groups carry own-only in their declaration-fixed
                -- group filter string; changing it re-keys BmSignature and
                -- swaps, so only true slots re-drive live here.
                if not m.isChain and d.rfcBm then
                    d.rfcBm:SetAuraSlotFilterString(m.key,
                        AK.Filter(unpack(BuildBmFilter(m.ind, m.spellID, m.spells))))
                end
            end
        end
    end
end

-- TWO-PHASE construction (login profiler verdict: a solo login built the
-- FULL group set for 86 buttons -- 85 of them empty -- at ~7ms per group
-- declaration = ~5.5s of work; shells cost ~0.26ms each).
-- PHASE A (every styled button): container SHELLS only, plus the dispel
-- slots (batch-1, cheap) -- the one thing combat cannot create (probe T3),
-- so mid-combat joiners always find them ready. ~2.5ms per button.
-- PHASE B (only buttons that HOLD a unit; triggered by assignment): group
-- declarations, BM, finish/config. Group jobs ride the combat-legal live
-- lane when triggered mid-combat (shells exist from phase A), so a
-- mid-fight raid joiner gets debuffs/defensives immediately; BM needs
-- container creation and completes at regen for that one case.
-- SYNCHRONOUS shell construction, run directly from StyleButton. This is
-- the early-load-window trick the suite already uses for element
-- positioning: at frame-construction time -- even on an in-combat /reload
-- -- combat state has not re-engaged yet, so container creation is safe
-- and real (field-verified: lockdown reads false while setup runs).
-- Shells are the cheap part (~2.5ms per button, behind the loading
-- screen); the expensive group/BM work stays on the worker queue.
local function CreateButtonShells(button, health, d)
    -- Debuffs: adopt the header-born container when present (secure-side
    -- birth; also covers buttons the header grows mid-combat), else build.
    if not (d.rfcDebuffShell or d.rfcDebuffs) then
        local c = button.AuraContainer
        if not c then
            c = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
        end
        -- Legacy aura icons live at button + LVL_AURA (13), above the
        -- health-bar decorations (dispel overlay, shields) and text; the
        -- containers default far lower. Children keep relative levels.
        c:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA or 13))
        d.rfcDebuffShell = c
        d.rfcDebuffGroups = {}
    end

    -- Dispellable-location container: strictly opt-in, so the shell only
    -- exists while the split is enabled somewhere (zero cost otherwise;
    -- DispLocAnyActive because the class flags may not be stamped yet).
    -- Enabling the split mid-session builds it through the OOC lane in
    -- RFC_ReloadAll.
    if not (d.rfcDispLocShell or d.rfcDispLoc) and DispLocAnyActive() then
        local c = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
        c:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA or 13))
        d.rfcDispLocShell = c
        d.rfcDispLocGroups = {}
    end

    if not ns.RFC_DefensivesRetired and not (d.rfcDefShell or d.rfcDefs) then
        local c = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
        c:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA or 13))
        d.rfcDefShell = c
        d.rfcDefGroups = {}
    end

    if not (d.rfcDispelShell or d.rfcDispel) then
        local s = ProxyFor(d)
        if s then
            local dispelStyleKey = StyleKeyFor(d):gsub("debuff", "dispel")
            AK.styles[dispelStyleKey] = AK.styles[dispelStyleKey] or BuildDispelStyle(s)
            local c = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
            local dispelFilter = DispelSlotFilter(s)
            for i = 1, #DISPEL_SLOTS do
                local def = DISPEL_SLOTS[i]
                AK.AddSlotToContainer(c, {
                    key = def.key,
                    filter = dispelFilter,
                    candidateFilters = { includeDispelTypes = { [def.token] = true } },
                    style = dispelStyleKey,
                    extraInit = function(slotButton, dd)
                        dd.rfHealth = health
                        dd.rfSlotDef = def
                        -- Anchor inside the creation window: SetPoint on the
                        -- returned slot button is denied while auras are
                        -- secret (12.1 button access restriction), and shell
                        -- setup runs on in-instance reloads.
                        slotButton:SetPoint("CENTER", health, "CENTER")
                        ApplyRFDispelSlot(slotButton, dd, AK.styles[dispelStyleKey])
                    end,
                })
            end
            -- NO unit yet: an unbound shell registers no events and parses
            -- nothing. The finish job binds the real unit.
            d.rfcDispelShell = c
        end
    end

    -- BuffManager shells, same early-window rule: the slots container, the
    -- simple-grid container, and a bare pool shell per current-spec chain
    -- indicator. With frames pre-born, ALL remaining BM work (slot adds,
    -- group declarations, finishes, retargets) is combat-legal -- BM binds
    -- mid-combat after an in-combat /reload instead of waiting for regen.
    if not d.rfcBmSlotsShell and not d.rfcBm then
        d.rfcBmSlotsShell = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
    end
    if not d.rfcBmSimpleShell and not d.rfcBmSimple then
        d.rfcBmSimpleShell = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
    end
    if not d.rfcBmShellPool then
        d.rfcBmShellPool = {}
        local inds = BmIndicators()
        if inds then
            for i = 1, #inds do
                local ind = inds[i]
                if ind.enabled and (ind.type == "icon" or ind.type == "square")
                    and BmChainMode(ind) == "g" then
                    d.rfcBmShellPool[#d.rfcBmShellPool + 1] =
                        AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
                end
            end
        end
    end
end

-- Debuff phase: group declarations + finish. Combat-runnable (no oocOnly
-- mark) -- the shells exist synchronously from StyleButton, and group
-- declaration on an existing container is combat-legal (probe T1/T1b).
--
-- CLASS AT JOB TIME, NOT QUEUE TIME: the party SELF button carries its
-- unit attribute before StyleButton runs, but party creation stamps
-- d._isParty only after StyleButton returns -- so this phase queues while
-- the button still reads as raid class (the same StyleButton-before-flags
-- contract the legacy Anchor* closures document via LiveS). Build jobs run
-- a frame later at the earliest, after the flags, so every job below
-- resolves StyleKeyFor/ProxyFor itself; capturing them at queue time gave
-- the party self frame raid-classed aura containers.
local function QueueDebuffPhase(button, health, d)
    if not ProxyFor(d) then return end
    for i = 1, #DEBUFF_GROUPS do
        local g = DEBUFF_GROUPS[i]
        AK.QueueBuildJob(function()
            local c = d.rfcDebuffShell
            if not c or d.rfcDebuffGroups[g.key] then return end
            local sNow = ProxyFor(d)
            if not sNow then return end
            -- 12.1 redesign: the Debuff Manager owns the debuff row; only
            -- the cc group (its Crowd Control record + glow carrier) is
            -- still declared here. The retired preset groups would be
            -- permanent parse consumers even parked at 0.
            if g.key ~= "cc" then return end
            if g.lazy then
                local need = DEBUFF_PRESET_GROUPS[sNow.debuffFilter or "all"]
                local wanted = false
                if need then
                    for k = 1, #need do
                        if need[k] == g.key then wanted = true end
                    end
                end
                if not wanted then return end
            end
            local styleKey = StyleKeyFor(d)
            local ccStyleKey = styleKey:gsub("debuff", "debuffcc")
            -- Prime here too: setup-time priming used the queue-time class,
            -- so a job-resolved class may not have style tables yet.
            AK.styles[styleKey] = AK.styles[styleKey] or BuildDebuffStyle(sNow)
            AK.styles[ccStyleKey] = AK.styles[ccStyleKey] or BuildDebuffCCStyle(sNow)
            AK.AddGroupToContainer(c, { key = g.key, filter = g.filter, maxFrameCount = 0,
                style = (g.key == "cc") and ccStyleKey or styleKey })
            d.rfcDebuffGroups[g.key] = true
        end, "rf:debuff-group")
    end
    AK.QueueBuildJob(function()
        local c = d.rfcDebuffShell
        if not c then return end
        d.rfcDebuffShell = nil
        local unit = button:GetAttribute("unit") or "player"
        AK.FinishContainer(c, unit)
        d.rfcHealth = health
        d.rfcDebuffs = c
        d.rfcUnit = unit
        local sNow = ProxyFor(d)
        if sNow then
            AnchorDebuffContainer(c, health, sNow)
            ApplyDebuffConfig(c, d, sNow)
        end
    end, "rf:debuff-finish")
end

-- Dispellable-location phase: mirrors QueueDebuffPhase for the split
-- container. Only queued when its shell exists (the split is opt-in);
-- every group is on-demand via DispLocGroupWanted. Class resolves at JOB
-- time for the same party-self-button reason as QueueDebuffPhase.
local function QueueDispLocPhase(button, health, d)
    if not ProxyFor(d) then return end
    for i = 1, #DEBUFF_GROUPS do
        local g = DEBUFF_GROUPS[i]
        AK.QueueBuildJob(function()
            local c = d.rfcDispLocShell
            if not c or d.rfcDispLocGroups[g.key] then return end
            local sNow = ProxyFor(d)
            if not sNow or not DispLocActive(sNow) or not DispLocGroupWanted(sNow, g.key) then return end
            local styleKey = StyleKeyFor(d)
            local dlStyleKey = styleKey:gsub("debuff", "disploc")
            local dlCCStyleKey = styleKey:gsub("debuff", "disploccc")
            AK.styles[dlStyleKey] = AK.styles[dlStyleKey] or BuildDebuffStyle(sNow, DispLocSize(sNow))
            AK.styles[dlCCStyleKey] = AK.styles[dlCCStyleKey] or BuildDebuffCCStyle(sNow, DispLocSize(sNow))
            AK.AddGroupToContainer(c, { key = g.key, filter = g.filter, maxFrameCount = 0,
                style = (g.key == "cc") and dlCCStyleKey or dlStyleKey })
            d.rfcDispLocGroups[g.key] = true
        end, "rf:disploc-group")
    end
    AK.QueueBuildJob(function()
        local c = d.rfcDispLocShell
        if not c then return end
        d.rfcDispLocShell = nil
        local unit = button:GetAttribute("unit") or "player"
        AK.FinishContainer(c, unit)
        d.rfcDispLoc = c
        local sNow = ProxyFor(d)
        if sNow then
            AnchorDispLocContainer(c, health, sNow)
            ApplyDispLocConfig(c, d, sNow)
            c:SetShown(DispLocActive(sNow))
        end
    end, "rf:disploc-finish")
end

local function QueueButtonGroups(button, health, d)
    local s = ProxyFor(d)
    if not s then d.rfcGroupsPending = nil; return end

    -- No style keys captured here: every job resolves its class at run
    -- time (see the QueueDebuffPhase note on the party self button).

    QueueDebuffPhase(button, health, d)
    if d.rfcDispLocShell then
        QueueDispLocPhase(button, health, d)
    end

    if not ns.RFC_DefensivesRetired then
    for i = 1, #DEF_GROUPS do
        local g = DEF_GROUPS[i]
        AK.QueueBuildJob(function()
            local c = d.rfcDefShell
            if not c or d.rfcDefGroups[g.key] then return end
            local sNow = ProxyFor(d)
            if not sNow or sNow[g.skey] == false then return end
            local defStyleKey = StyleKeyFor(d):gsub("debuff", "def")
            AK.styles[defStyleKey] = AK.styles[defStyleKey] or BuildDefStyle(sNow)
            AK.AddGroupToContainer(c, { key = g.key, filter = g.filter, maxFrameCount = 0, style = defStyleKey })
            d.rfcDefGroups[g.key] = true
        end, "rf:def-group")
    end
    AK.QueueBuildJob(function()
        local c = d.rfcDefShell
        if not c then return end
        d.rfcDefShell = nil
        local unit = button:GetAttribute("unit") or "player"
        AK.FinishContainer(c, unit)
        d.rfcDefs = c
        d.rfcUnit = unit
        local sNow = ProxyFor(d) or s
        AnchorDefContainer(c, health, sNow)
        ApplyDefConfig(c, sNow, d)
    end, "rf:def-finish")
    end -- RFC_DefensivesRetired

    AK.QueueBuildJob(function()
        local c = d.rfcDispelShell
        if not c then return end
        d.rfcDispelShell = nil
        local unit = button:GetAttribute("unit") or "player"
        AK.FinishContainer(c, unit)
        d.rfcDispel = c
        local sNow = ProxyFor(d)
        c:SetShown(DispelVisible(sNow or s))
        d.rfcUnit = unit
    end, "rf:dispel-finish")

    -- BuffManager + finalize: consumes the early-window BM shells (slot
    -- adds, group declarations, finishes -- all combat-legal), so it runs
    -- mid-combat too. Only pool GROWTH beyond the pre-born shells falls
    -- back to a queued shell job inside BmAcquireChain.
    AK.QueueBuildJob(function()
        d.rfcPending = nil
        d.rfcGroupsPending = nil
        local unit = button:GetAttribute("unit") or "player"
        CreateBmContainer(button, health, d, unit)
        d.rfcUnit = unit
        -- Everything above was configured from current settings; prime the
        -- class fingerprints so the first reload doesn't re-drive it all.
        -- Class resolved here, not at queue time (party self button).
        PrimeClassFP(StyleKeyFor(d), ProxyFor(d) or s)
        -- Clear any state cached while this button was mid-build (unit
        -- assignments run the gate against partial containers): the fresh
        -- containers must get a full SetShown/range-alpha pass.
        d.rfcAssist = nil
        -- (ns indirection: the gate is defined below this function.)
        ns.RFC_ApplyAssistGate(button, d, unit)
        registry[#registry + 1] = button
    end, "rf:bm+finalize")
end
ns.RFC_QueueButtonGroups = QueueButtonGroups -- for the unit-assignment watch

-- Called from StyleButton's tail for every decorated unit button (raid,
-- party, self, extra). Phase A (shells) for everyone; phase B only when
-- the button already holds a unit -- the assignment watch triggers it for
-- later arrivals, so empty raid/party/extra buttons cost shells only.
function ns.RFC_SetupButton(button, health, d)
    AK = AK or EllesmereUI.AuraKit
    if not AK or not AK.QueueBuildJob or d.rfcDebuffs or d.rfcPending then return end
    d.rfcPending = true

    local s = ProxyFor(d)
    if s then
        local styleKey = StyleKeyFor(d)
        AK.styles[styleKey] = AK.styles[styleKey] or BuildDebuffStyle(s)
        local ccStyleKey = styleKey:gsub("debuff", "debuffcc")
        AK.styles[ccStyleKey] = AK.styles[ccStyleKey] or BuildDebuffCCStyle(s)
        local defStyleKey = styleKey:gsub("debuff", "def")
        AK.styles[defStyleKey] = AK.styles[defStyleKey] or BuildDefStyle(s)
        local dispelStyleKey = styleKey:gsub("debuff", "dispel")
        AK.styles[dispelStyleKey] = AK.styles[dispelStyleKey] or BuildDispelStyle(s)
    end

    d.rfcHealthRef = health

    -- Shells synchronously, HERE, in the early load window (see
    -- CreateButtonShells): the one moment container creation is safe on
    -- every reload path, combat reloads included.
    CreateButtonShells(button, health, d)

    local unit = button:GetAttribute("unit")
    if unit and UnitExists(unit) then
        d.rfcGroupsPending = true
        QueueButtonGroups(button, health, d)
    end
end

-- Cross-faction (or otherwise non-assistable) group members: the engine
-- SILENTLY SKIPS spell-ID candidate filters for helpful auras on units the
-- identity gate classes as non-assistable (open-world cross-faction
-- members are the common case). Include-list displays would degrade to
-- "any buff" -- so displays whose selection depends on candidates hide
-- for such units (they cannot be dispelled or meaningfully tracked
-- anyway). Token-only groups (debuffs, externals, defensives, CC) are
-- unaffected and stay on.
-- Positive-trust probe. The engine's filter-flag degradation is NOT
-- directly queryable, and the old three-check proxy (assist + visible +
-- not-phased) still PASSED for degraded units -- a dead/released ghost
-- near the group is "visible", carries no phase reason, and can be
-- assisted (resurrection), yet the engine skips its include-list
-- candidate filters and the freedom/BM groups leaked "any buff"
-- displays. Flipped to require-everything: the gate only opens when
-- every positively checkable trust signal holds -- connected, alive,
-- assistable, visible, not phased, AND in the 40yd group range (dead or
-- released members fail alive/range; distant and phased members fail
-- range/visibility; none of them can be dispelled or meaningfully
-- tracked anyway). The local player's own flags never degrade, so the
-- self button stays exempt. Under teardown states the identity APIs can
-- return SECRET booleans; any secret in the chain errors inside the
-- pcall and reads as fail-closed.
local function AssistProbe(unit)
    if UnitIsUnit(unit, "player") then return true end
    if not (UnitIsConnected(unit)
        and not UnitIsDeadOrGhost(unit)
        and UnitCanAssist("player", unit)
        and UnitIsVisible(unit)
        and not UnitPhaseReason(unit)) then
        return false
    end
    -- Range is DISQUALIFYING-only: it closes the gate solely when the API
    -- positively reports out-of-range. Requiring a positive in-range answer
    -- hid every display whenever the check was unavailable (checkedRange
    -- false/nil states, API differences) -- field-reported as "all BM
    -- tracking gone". When range cannot be checked, the five positive
    -- checks above decide; secret returns skip the check the same way.
    local inRange, checkedRange = UnitInRange(unit)
    if not (issecretvalue and (issecretvalue(inRange) or issecretvalue(checkedRange))) then
        if checkedRange and not inRange then return false end
    end
    return true
end

-- Secret-safe range gating. UnitInRange returns a SECRET boolean in
-- restricted content (the button range fade already handles the same fact
-- with SetAlphaFromBoolean), so Lua can never DECIDE on range there --
-- requiring a readable positive hid every display, and skipping the check
-- when secret let degraded (released/phased/far) units leak "any buff"
-- renders. The engine sink decides instead: candidate-dependent containers
-- slave their alpha to the range boolean, so a unit the engine cannot
-- vouch for renders invisible no matter what the readable gate believes.
-- Re-driven on every gate pass: the boolean may be secret, so no readable
-- same-state cache can guard it.
local function SetRangeAlpha(f, v)
    if not f then return end
    if f.SetAlphaFromBoolean then
        pcall(f.SetAlphaFromBoolean, f, v, 1, 0)
    elseif not (issecretvalue and issecretvalue(v)) then
        f:SetAlpha(v and 1 or 0)
    end
end

-- Self is exempt (UnitInRange never reports the player in range); any
-- secret in the identity chain errors inside the caller's pcall and reads
-- as out-of-range (fail-closed). Returns UnitInRange's first value, which
-- may be a SECRET -- callers must only pass it to secret sinks.
local function RangeProbe(unit)
    if UnitIsUnit(unit, "player") then return true end
    return (UnitInRange(unit))
end

local function ApplyRangeAlpha(d, unit)
    local ok, v = pcall(RangeProbe, unit)
    if not ok then v = false end
    SetRangeAlpha(d.rfcDefs, v)
    SetRangeAlpha(d.rfcDispel, v)
    SetRangeAlpha(d.rfcBm, v)
    SetRangeAlpha(d.rfcBmSimple, v)
    if d.rfcBmChain then
        for _, cc in pairs(d.rfcBmChain) do SetRangeAlpha(cc, v) end
    end
end

local function ApplyAssistGate(button, d, unit)
    -- The range-alpha pass rides EVERY evaluation, before the readable
    -- same-state early-out below (a secret range flip is invisible to it).
    if unit then ApplyRangeAlpha(d, unit) end
    -- Faction AND phase: the engine's identity gate degrades for members
    -- who are cross-faction (open world) OR phased/far away (their filter
    -- flags have not streamed; UnitPhaseReason is the eye-icon signal for
    -- exactly that state). While degraded, filter results are untrustworthy
    -- for the unit, so filtered helpful displays hide wholesale.
    local assist = false
    if unit then
        local ok, res = pcall(AssistProbe, unit)
        if ok and res then assist = true end
    end
    -- Same state as last applied: every write below is assist-driven, so
    -- re-applying is redundant (settings changes re-drive via the reload
    -- paths). Keeps the event-sweep watchers near-free.
    if d.rfcAssist == assist then return end
    d.rfcAssist = assist
    local s = ProxyFor(d)
    if d.rfcDefs and s then
        -- Whole container: the leak was observed at the defensives anchor,
        -- so token groups hide for degraded units too (defense in depth on
        -- top of the per-group candidate counts).
        d.rfcDefs:SetShown(assist)
        for i = 1, #DEF_GROUPS do
            local g = DEF_GROUPS[i]
            -- Setters on undeclared (lazily-built) groups error.
            if g.cand and d.rfcDefGroups and d.rfcDefGroups[g.key] then
                local shown = assist and s[g.skey] ~= false
                d.rfcDefs:SetAuraGroupMaxFrameCount(g.key, shown and (g.cap or DEF_CAP) or 0)
            end
        end
    end
    if d.rfcDispel and s then
        d.rfcDispel:SetShown(assist and DispelVisible(s))
    end
    if d.rfcBm then d.rfcBm:SetShown(assist) end
    if d.rfcBmChain then
        for _, cc in pairs(d.rfcBmChain) do cc:SetShown(assist) end
    end
    if d.rfcBmSimple then
        -- The simple container PERSISTS, so the gate must be state-aware:
        -- coexistence resolves through the effective base-enabled accessor
        -- (shim over the legacy mode key), never the mode key directly.
        local bs = BmSimpleSettings()
        local baseOn = (ns.BM_BaseActive and ns.BM_BaseActive()) or false
        -- Same option-aware key the grid tracks with (Show Own on All Specs).
        local specKey = (ns.BM_SimpleSpecKey and ns.BM_SimpleSpecKey())
            or (ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey())
        d.rfcBmSimple:SetShown(assist and baseOn and specKey ~= nil
            and (bs and bs.showBuffs) and true or false)
    end
    -- Debuff Manager: its identity-gated (candidate-boolean) records hide
    -- for untrusted units; token records stay on like the legacy row.
    if ns.DM_OnAssistChanged then ns.DM_OnAssistChanged(d) end
end
ns.RFC_ApplyAssistGate = ApplyAssistGate

-- Called from the OnAttributeChanged("unit") watch when the secure header
-- (re)assigns a button. SetUnit re-registers events; the explicit refresh
-- covers assignments where the new unit's auras produce no UNIT_AURA edge.
function ns.RFC_OnUnitAssigned(button, d, unit)
    -- Two-phase: a button receiving its FIRST unit triggers phase B (group
    -- declarations + BM + finish) -- empty buttons only ever carry the
    -- phase-A shells. Mid-combat first assignments (raid joiners) work:
    -- group jobs ride the live lane against the pre-built shells.
    if not d.rfcDebuffs and not d.rfcGroupsPending then
        if d.rfcHealthRef then
            d.rfcGroupsPending = true
            QueueButtonGroups(button, d.rfcHealthRef, d)
        end
        return
    end
    -- The secure header re-sets the SAME unit attribute on every roster
    -- re-process (the OnAttributeChanged watch fires either way). The
    -- containers keep their unit across that, and UNIT_AURA drives their
    -- content, so a same-unit re-assignment has nothing to re-drive --
    -- skipping it avoids a full engine reparse of every group and slot on
    -- every container of every button (the raid-wide UpdateAllAuras storm)
    -- each time the header re-processes. Assist state can still flip
    -- without a unit change; its same-state early-out keeps that call
    -- near-free.
    if d.rfcUnit == unit then
        ApplyAssistGate(button, d, unit)
        return
    end
    d.rfcUnit = unit
    if d.rfcDebuffs then
        d.rfcDebuffs:SetUnit(unit)
        d.rfcDebuffs:UpdateAllAuras()
    end
    if d.rfcDispLoc then
        d.rfcDispLoc:SetUnit(unit)
        d.rfcDispLoc:UpdateAllAuras()
    end
    if d.rfcDefs then
        d.rfcDefs:SetUnit(unit)
        d.rfcDefs:UpdateAllAuras()
    end
    if d.rfcDispel then
        d.rfcDispel:SetUnit(unit)
        d.rfcDispel:UpdateAllAuras()
    end
    if d.rfcBm then
        d.rfcBm:SetUnit(unit)
        d.rfcBm:UpdateAllAuras()
    end
    if d.rfcBmChain then
        for _, cc in pairs(d.rfcBmChain) do
            cc:SetUnit(unit)
            cc:UpdateAllAuras()
        end
    end
    if d.rfcBmSimple then
        d.rfcBmSimple:SetUnit(unit)
        d.rfcBmSimple:UpdateAllAuras()
    end
    -- Debuff Manager tile containers re-point with everything else.
    if ns.DM_OnUnitAssigned then ns.DM_OnUnitAssigned(d, unit) end
    ApplyAssistGate(button, d, unit)
end

-- Compares fingerprints for one class, restyles what changed (once per
-- class -- styles are shared), and returns which per-button config blocks
-- need re-driving. Empty flags = the reload touches nothing container-side.
local function ComputeClassFlags(styleKey, s)
    local st = classFP[styleKey]
    if not st then st = {}; classFP[styleKey] = st end
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    local flags = {}

    local v = DebuffStyleFP(s, font)
    if st.debuffStyle ~= v then
        st.debuffStyle = v
        AK.styles[styleKey] = BuildDebuffStyle(s)
        AK.RestyleSoon(styleKey)
        local ccStyleKey = styleKey:gsub("debuff", "debuffcc")
        AK.styles[ccStyleKey] = BuildDebuffCCStyle(s)
        AK.RestyleSoon(ccStyleKey)
        -- DM per-filter sized styles derive from these; a pure style edit
        -- does not flip the config fingerprint, so refresh them here.
        if ns.DM_RefreshSizedStyles then ns.DM_RefreshSizedStyles(styleKey, s) end
    end
    v = DebuffCfgFP(s)
    if st.debuffCfg ~= v then st.debuffCfg = v; flags.debuffCfg = true end

    v = DispLocStyleFP(s, font)
    if st.dispLocStyle ~= v then
        st.dispLocStyle = v
        local dlStyleKey = styleKey:gsub("debuff", "disploc")
        -- Only rebuild once the split has ever materialized styles for this
        -- class -- keeps the feature literally zero-cost while unused.
        if DispLocActive(s) or AK.styles[dlStyleKey] then
            AK.styles[dlStyleKey] = BuildDebuffStyle(s, DispLocSize(s))
            AK.RestyleSoon(dlStyleKey)
            local dlCCStyleKey = styleKey:gsub("debuff", "disploccc")
            AK.styles[dlCCStyleKey] = BuildDebuffCCStyle(s, DispLocSize(s))
            AK.RestyleSoon(dlCCStyleKey)
        end
    end
    v = DispLocCfgFP(s)
    if st.dispLocCfg ~= v then st.dispLocCfg = v; flags.dispLocCfg = true end

    v = DefStyleFP(s, font)
    if st.defStyle ~= v then
        st.defStyle = v
        local defStyleKey = styleKey:gsub("debuff", "def")
        AK.styles[defStyleKey] = BuildDefStyle(s)
        AK.RestyleSoon(defStyleKey)
    end
    v = DefCfgFP(s)
    if st.defCfg ~= v then st.defCfg = v; flags.defCfg = true end

    v = DispelStyleFP(s)
    if st.dispelStyle ~= v then
        st.dispelStyle = v
        local dispelStyleKey = styleKey:gsub("debuff", "dispel")
        AK.styles[dispelStyleKey] = BuildDispelStyle(s)
        AK.RestyleSoon(dispelStyleKey)
    end
    local dispelFilter = AK.Filter(unpack(DispelSlotFilter(s)))
    if st.dispelFilter ~= dispelFilter then
        st.dispelFilter = dispelFilter
        flags.dispelFilter = dispelFilter
    end

    return flags
end

-- Called directly from the tail of ReloadFrames (and the party mirror path
-- feeds the same registry). Fingerprint-guarded: engine config re-drives
-- only for subsystems whose settings actually changed, so unrelated raid
-- settings cost near-zero here.
-- Restriction-lift reconciliation: passes that skipped under aura secrecy
-- left their fingerprints unstamped; one FP-guarded ReloadAll at lift
-- re-drives exactly the skipped work (unchanged subsystems compare equal
-- and cost nothing). Dirty-flag guarded so idle lift events cost one test.
-- NOTE: the file-scope AK local is assigned lazily at entry points and is
-- still nil at load time -- resolve AuraKit directly here (parent addon is
-- a hard dependency, so it exists by child load).
do
    local AKL = EllesmereUI and EllesmereUI.AuraKit
    if AKL and AKL.OnRestrictionLift then
        AKL.OnRestrictionLift(function()
            if ns._rfcLiftDirty then
                ns._rfcLiftDirty = nil
                if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
            end
        end)
    end
end

function ns.RFC_ReloadAll()
    AK = AK or EllesmereUI.AuraKit
    if not AK then return end

    local dirty, clsCache = {}, {}

    for i = 1, #registry do
        local button = registry[i]
        local d = ns.GetFFD and ns.GetFFD(button)
        local container = d and d.rfcDebuffs
        if container then
            local s = ProxyFor(d)
            if s then
                local styleKey = StyleKeyFor(d)
                local flags = dirty[styleKey]
                if not flags then
                    flags = ComputeClassFlags(styleKey, s)
                    dirty[styleKey] = flags
                end
                if flags.debuffCfg then
                    AnchorDebuffContainer(container, d.rfcHealth, s)
                    ApplyDebuffConfig(container, d, s)
                end
                if flags.dispLocCfg then
                    local c2 = d.rfcDispLoc
                    if c2 then
                        AnchorDispLocContainer(c2, d.rfcHealth, s)
                        ApplyDispLocConfig(c2, d, s)
                        c2:SetShown(DispLocActive(s))
                    elseif DispLocActive(s) and not d.rfcDispLocShell and not d.rfcDispLocBuild then
                        -- Split enabled mid-session: containers cannot be
                        -- created in combat, so the shell build rides the OOC
                        -- lane; groups + finish then follow the normal phase.
                        d.rfcDispLocBuild = true
                        AK.QueueBuildJob(function()
                            d.rfcDispLocBuild = nil
                            if d.rfcDispLoc or d.rfcDispLocShell then return end
                            local s2 = ProxyFor(d)
                            if not s2 or not DispLocActive(s2) then return end
                            local health = d.rfcHealth or d.rfcHealthRef
                            if not health then return end
                            local c = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
                            c:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA or 13))
                            d.rfcDispLocShell = c
                            d.rfcDispLocGroups = {}
                            QueueDispLocPhase(button, health, d)
                        end, "rf:disploc-shell") -- creation combat-legal since 68914
                    end
                end
                if d.rfcDefs and flags.defCfg then
                    AnchorDefContainer(d.rfcDefs, d.rfcHealth, s)
                    ApplyDefConfig(d.rfcDefs, s, d)
                end
                if d.rfcDispel then
                    if flags.dispelFilter then
                        for j = 1, #DISPEL_SLOTS do
                            d.rfcDispel:SetAuraSlotFilterString(DISPEL_SLOTS[j].key, flags.dispelFilter)
                        end
                    end
                    d.rfcDispel:SetShown(d.rfcAssist ~= false and DispelVisible(s))
                end
                local cls = clsCache[styleKey]
                if not cls then
                    cls = BmClassPass(d)
                    clsCache[styleKey] = cls
                end
                ReloadBm(button, d, s, cls)
            end
        end
    end
end

-- Full assist-gate sweep over every live button. Per-unit matching is
-- unsafe (UnitIsUnit can return a SECRET boolean during group teardown),
-- and the gate's same-state early-out makes a sweep near-free.
local function AssistSweep()
    for i = 1, #registry do
        local button = registry[i]
        local d = ns.GetFFD and ns.GetFFD(button)
        if d and d.rfcDebuffs then
            local unit = button:GetAttribute("unit")
            if unit then ApplyAssistGate(button, d, unit) end
        end
    end
end

-- Indicator-set changes (spec swap, add/remove spell, mode toggle) need a
-- container swap, which is deferred to out-of-combat. Spec changes swap the
-- whole indicator set, so they re-drive the reload directly (the signature
-- check makes a no-change reload cheap).
local bmRegen = CreateFrame("Frame")
bmRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
bmRegen:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
bmRegen:RegisterEvent("PLAYER_ENTERING_WORLD")
bmRegen:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == "player" and not InCombatLockdown() then ns.RFC_ReloadAll() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Assistability can flip on zone transitions without a unit
        -- re-assignment (cross-faction members become assistable inside
        -- instances); re-evaluate the gate for every live button.
        AssistSweep()
        return
    end
    local any = false
    for i = 1, #registry do
        local d = ns.GetFFD and ns.GetFFD(registry[i])
        if d and d.rfcBmPending then
            d.rfcBmPending = nil
            any = true
        end
    end
    if any then ns.RFC_ReloadAll() end
end)

-- Event-driven gate re-evaluation (no polling): UNIT_PHASE fires exactly
-- when a member's phase/distance relationship to us changes (the eye-icon
-- transitions), UNIT_CONNECTION on connect state, UNIT_IN_RANGE_UPDATE on
-- the range boundary, GROUP_ROSTER_UPDATE on membership churn.
local assistWatch = CreateFrame("Frame")
assistWatch:RegisterEvent("UNIT_PHASE")
assistWatch:RegisterEvent("UNIT_CONNECTION")
assistWatch:RegisterEvent("UNIT_IN_RANGE_UPDATE")
assistWatch:RegisterEvent("GROUP_ROSTER_UPDATE")
-- Death/release/resurrection transitions (the alive requirement of the
-- probe) signal through UNIT_FLAGS; it is chatty in combat, but the
-- coalescer below reduces any burst to one deferred sweep.
assistWatch:RegisterEvent("UNIT_FLAGS")
-- Coalesced: UNIT_IN_RANGE_UPDATE fires continuously in a moving raid
-- (every member crossing the range boundary), and each sweep probes three
-- identity APIs per button. One deferred sweep per burst covers every
-- trigger that landed inside the window; the gate is a display-trust
-- gate, so a quarter-second of latency is invisible.
local assistSweepPending = false
local function AssistSweepDrain()
    assistSweepPending = false
    AssistSweep()
end
assistWatch:SetScript("OnEvent", function()
    if assistSweepPending then return end
    assistSweepPending = true
    C_Timer.After(0.25, AssistSweepDrain)
end)
