if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_RaidFrames_AuraContainers.lua
-- 12.1 aura containers for raid/party/extra unit buttons.
--
-- Buttons are always created OUT OF COMBAT (headers pre-create via startingIndex;
-- extra-frame builds are combat-gated); containers build at StyleButton time and
-- re-point on OnAttributeChanged("unit"). Visuals anchor to the health bar, sizes
-- come from live-scaled proxies (never raw db.profile), state lives in external FFD.

local _, ns = ...

local AK -- EllesmereUI.AuraKit, resolved at first use
local FALLBACK_FONT = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

-- Marks debuff rendering as container-owned; the legacy UpdateDebuffs body
-- early-returns on this flag (single gate covering all seven call sites).
ns.RFC_OwnsDebuffs = true
ns.RFC_OwnsDefensives = true
ns.RFC_OwnsDispel = true
ns.RFC_OwnsBM = true -- both BM display modes (custom slots/chains + simple grid group)

-- Legacy aura paths (defensives, dispel border, BuffManager) hard-error while auras
-- are secret and would abort shared handler chains, breaking migrated displays too --
-- so they skip silently under restriction. Cache is asymmetric (AK.AurasRestricted):
-- only the RESTRICTED answer caches per-frame; a stale "unrestricted" reruns into hard
-- errors, a stale "restricted" only skips one frame.
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

-- "raid" preset = union RAID|RAID_IN_COMBAT via negation-chained groups; presets
-- enable groups by COUNT, never swap containers (group set is fixed). "cc" declares
-- FIRST so it leads the row, carries the CC glow, and shows under any preset; every
-- other group negates CROWD_CONTROL so a CC aura never doubles. Lazy groups declare
-- ON DEMAND (combat-legal): each AddAuraGroup eagerly allocates a 10-button engine
-- batch (anti-fingerprint floor), so default users get 2 groups not 5. Groups are
-- add-only -- switching away zeroes counts live, never frees frames.
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

-- "Dispellable Debuff Location" (RETIRED, see DispLocActive) routed dispellable
-- debuffs to their own container via complementary dispel-type candidate filters
-- (engine-legal on friendly harmful auras, not identity-gated). Magic/Curse/Disease/
-- Poison/Bleed is the full harmful typed set (Enrage is buff-only).
local DISPLOC_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }

local function DispLocActive(s)
    -- Retired with the Auras tab (Dispellable now routes via a Debuff Manager tile).
    -- Constant false keeps every consumer (shell gating, config, shown state,
    -- candidate excludes, fingerprints) uniformly inert.
    return false
end

-- Button class is unknown at shell time (party stamps _isParty after StyleButton),
-- so query every settings source: an unneeded shell just ends up a cheap hidden
-- group-less container, but a MISSING shell can't be created in combat at all.
local function DispLocAnyActive()
    if ns._scaledProfile and DispLocActive(ns._scaledProfile) then return true end
    if ns._scaledPartyProxy and DispLocActive(ns._scaledPartyProxy) then return true end
    if ns._scaledExtraProxy and DispLocActive(ns._scaledExtraProxy) then return true end
    return false
end

-- Effective icon size at the split anchor (0 = match Debuff Size; scaled proxies
-- bake indicator scale into both keys, and 0 scales to 0, so the sentinel survives).
local function DispLocSize(s)
    local v = s.dispellableDebuffSize
    if v and v > 0 then return v end
    return s.debuffSize or 18
end

-- Groups the location container needs for the active preset (all on-demand, split
-- is opt-in); cc rides along so dispellable CC keeps its glow at the split anchor.
local function DispLocGroupWanted(s, key)
    local preset = s.debuffFilter or "all"
    if preset == "none" then return false end
    if key == "cc" then return true end
    if key == "all" then return preset == "all" end
    if key == "raid" or key == "raidcombat" then return preset == "raid" end
    return preset == "dispellable" -- key == "dispellable"
end

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

-- Debuff text: duration centered, stack bottom-right, via the shared icon-text font
-- pipeline. DM EFFECTS (style.fxList, per-filter blocks): category comes from d.dmCat
-- (stamped at group declare) or the cc style's ccGroup marker for cc-group buttons;
-- boss/role matches either check, FIRST match wins. A block may add an Icon Glow
-- (rides button visibility, remaps to FlipBook under restriction, params cached) and/or
-- a Border override (own PP host one level above the style border, so equal-or-larger
-- size covers it).
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

    -- Icon Glow (engine-hosted): StartEngineGlow renders Pixel as the genuine C-side
    -- dash march and remaps other driver styles to FlipBook -- identical in/out of secret.
    local Glows = EllesmereUI.Glows
    local gType = (e and e.glowType) or 0
    local gov = d.dmFxgHost
    if gType > 0 and Glows and Glows.StartEngineGlow then
        if not gov then
            gov = CreateFrame("Frame", nil, button)
            gov:SetAllPoints(button)
            -- Layer ladder: style border(+1) < fx border(+2) < glow(+3) < dispel
            -- ring(+4) < text(+5); dispel recolor must always win over borders/glows.
            -- stackCarrier matches AuraKit's ladder so text never drops onto the ring.
            local base = (d.borderHost and d.borderHost:GetFrameLevel())
                or (button:GetFrameLevel() + 1)
            gov:SetFrameLevel(base + 3)
            if d.stackCarrier then d.stackCarrier:SetFrameLevel(base + 5) end
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
            Glows.StartEngineGlow(gov, gType, sz, cr, cg, cb)
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
-- Exported for the DM record/group extraInits: the style applier runs BEFORE
-- extraInit at button creation (dmCat isn't stamped yet), so the stamping extraInit
-- re-arms effects inside the creation window -- the only context guaranteeing legal
-- subtree writes.
ns.RFC_ApplyDmFx = ApplyDmFx

local function ApplyRFDebuffText(button, d, style)
    -- Restyles hit every button, so expensive setters are change-guarded (SetFont
    -- costs real time even with identical values; mouse-motion is engine-wrapped).
    -- Font key = path|size, so an outline-only toggle slips through until the next
    -- size-touching reload (accepted).
    if button.SetMouseMotionEnabled then
        local motion = not style.noTooltips
        if d.rfMotion ~= motion then
            d.rfMotion = motion
            button:SetMouseMotionEnabled(motion)
        end
    end
    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or FALLBACK_FONT
    if d.duration then
        -- Always font the string even hidden: the engine SetText()s every registered
        -- duration string on display updates, and an unfonted FontString hard-errors.
        local fontKey = path .. "|" .. (style.durSize or 8)
        if d.rfDurFont ~= fontKey then
            d.rfDurFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.duration, path, style.durSize or 8, "raidFrames")
        end
        local c = style.durColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        -- Anchor change-guarded, stamp AFTER the calls: SetPoint against the button
        -- is policed under the 12.1 aura-secret restriction, so unchanged offsets must
        -- make zero button-touching calls to keep restyles live in-instance.
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
    -- DM Square grid tiles: flat color block covering the spell icon (swipe/border/
    -- texts render above as usual). Flag only exists on square tile styles = zero
    -- cost elsewhere.
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

-- Settings fingerprints. Every engine setter (group counts, candidate filters,
-- layouts, slot filter strings) costs real engine work even when unchanged
-- (candidate re-eval, parse-filter rebuilds) -- re-driving all of them per button on
-- unrelated changes froze the client in raids. Reload paths fingerprint what each
-- subsystem actually reads and skip calls whose inputs are unchanged.
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

-- sizeOverride: the dispellable-location styles reuse the whole debuff
-- style with only the physical size swapped (see DispLocSize).
local function BuildDebuffStyle(s, sizeOverride)
    local br, bg, bb = ColorParts(s.debuffBorderColor, 0, 0, 0)
    local size = sizeOverride or s.debuffSize or 18
    -- Engine dispel-border extras: ring thickness in PHYSICAL pixels + the user
    -- palette as the engine tint map (AuraKit registers both; helper resolved at
    -- call time, declared below). -1 = follow icon's own Border thickness, 0 = recolor off.
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
        -- 5-state tooltip mode: true/nil=hidden, false=shown, "combat"=hidden in
        -- combat, "cursor"=shown at cursor, "modifier"=shown only while the Use
        -- Modifier cog's key is held. Style-side, "modifier" renders as plain
        -- Shown; the gating is the DM file's tooltip eater -- a secure unit
        -- sub-button over the debuff band that takes the hover and hides while
        -- the key is held (button-surface writes are refused while auras are
        -- secret, so nothing here can gate at runtime). Raw key already in DebuffStyleFP.
        noTooltips = not (s.debuffHideTooltips == false
            or s.debuffHideTooltips == "combat" or s.debuffHideTooltips == "cursor"
            or s.debuffHideTooltips == "modifier"),
        tooltipCombatHide = s.debuffHideTooltips == "combat",
        tooltipAnchor = (s.debuffHideTooltips == "cursor") and "cursor" or nil,
        -- Base DM Effects (per-filter blocks); tile styles override this
        -- after the build with their own (or nil).
        fxList = (ns.DM_FxList and ns.DM_FxList()) or nil,
        applyExtra = ApplyRFDebuffText,
    }
end

-- Crowd-control group style: plain debuff style + a marker the DM per-filter Icon
-- Effects use to ID cc-group buttons (that group stamps no category via extraInit).
-- The dedicated CC Debuff Glow is RETIRED (DM Icon Effects glow supersedes it) --
-- old debuffCCGlow* keys are orphaned here.
local function BuildDebuffCCStyle(s, sizeOverride)
    local st = BuildDebuffStyle(s, sizeOverride)
    st.ccGroup = true
    return st
end
-- Shared with the Debuff Manager: custom tiles render with the debuff style at
-- their own size.
ns.RFC_BuildDebuffStyle = BuildDebuffStyle
-- CC flavor too: a per-filter Icon Effects Size moves crowd control onto a
-- sized record variant, which must keep the cc marker.
ns.RFC_BuildDebuffCCStyle = BuildDebuffCCStyle

-- Container anchoring mirrors DebuffGridPoint: the flow's start corner sits on the
-- same corner of the health bar; CENTER growth anchors the edge-midpoint there so
-- each row centers on it.
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

-- Shared by AnchorDebuffContainer/AnchorDispLocContainer. CENTER growth pins
-- the container's top/bottom edge to match the position's OWN vertical side
-- (not wrap direction -- pinning by wrap put every CENTER-grown container's
-- edge on the bottom whenever Position was "top", since wrap defaults to "UP"
-- and isn't exposed on either options pane) so rows grow away from the
-- anchored edge; other growth directions anchor directly at the corner.
local function ResolveFlowAnchor(pos, corner, grow, wrap)
    if grow == "CENTER" then
        local edge = (pos:find("top", 1, true) and "TOP")
            or (pos:find("bottom", 1, true) and "BOTTOM")
            or ((wrap == "DOWN") and "TOP" or "BOTTOM")
        return edge, edge .. "LEFT", "RIGHT", (edge == "TOP") and "DOWN" or "UP"
    elseif grow == "UP" or grow == "DOWN" then
        -- Vertical primary growth renders as a single column per row-width;
        -- multi-column vertical fill order differs from legacy (row-major).
        return corner, corner, (wrap == "LEFT") and "LEFT" or "RIGHT", grow
    end
    return corner, corner, grow, wrap
end

-- The debuff row's pin: the flow's start point on the health frame plus the
-- cell geometry the row is laid out with. AnchorDebuffContainer pins the
-- container here (same math below); the Debuff Manager's tooltip-modifier
-- eaters pin to the same point with a settings-derived maximum footprint, so
-- their rect never derives from the container's content-driven (secret) size.
function ns.RFC_DebuffPin(s)
    local pos = s.debuffPosition or "bottomright"
    local corner = CORNERS[pos] or "BOTTOMRIGHT"
    local grow = s.debuffGrowDirection or "LEFT"
    local point = ResolveFlowAnchor(pos, corner, grow, s.debuffWrapDirection or "UP")
    return point, corner, s.debuffOffsetX or 0, s.debuffOffsetY or 0,
        s.debuffSize or 18, s.debuffSpacing or 1, s.debuffPerRow or 5,
        (grow == "UP" or grow == "DOWN")
end

local function AnchorDebuffContainer(container, health, s)
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, s) or health   -- Uniform Icon Anchoring
    -- Pin math mirrored by ns.RFC_DebuffPin above; keep the two in step.
    local pos = s.debuffPosition or "bottomright"
    local corner = CORNERS[pos] or "BOTTOMRIGHT"
    local grow = s.debuffGrowDirection or "LEFT"
    local wrap = s.debuffWrapDirection or "UP"
    local offX = s.debuffOffsetX or 0
    local offY = s.debuffOffsetY or 0

    local point, anchorPoint, gH, gV = ResolveFlowAnchor(pos, corner, grow, wrap)

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
        -- Vertical COLUMNS: lines are columns of perRow cells wrapping sideways
        -- (debuffWrapDirection maps the horizontal cross-axis above); below 2 a
        -- single column stands (elseif branch).
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

-- Dispellable-location anchoring: same flow math as the main debuff container,
-- but position/growth/offsets/size come from the "Dispellable Debuff Location"
-- settings (spacing/wrap/per-row stay shared with the debuff display).
local function AnchorDispLocContainer(container, health, s)
    health = ns.RF_AnchorHost and ns.RF_AnchorHost(health, s) or health   -- Uniform Icon Anchoring
    local pos = s.dispellableDebuffLocation or "bottomright"
    local corner = CORNERS[pos] or "BOTTOMRIGHT"
    local grow = s.dispellableDebuffGrowDirection or "RIGHT"
    local wrap = s.debuffWrapDirection or "UP"
    local offX = s.dispellableDebuffOffsetX or 0
    local offY = s.dispellableDebuffOffsetY or 0

    local point, anchorPoint, gH, gV = ResolveFlowAnchor(pos, corner, grow, wrap)

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

------------------------------------------------------------------------------
-- Dispel highlight -> per-type slots. One bare slot per dispel type decorates the
-- health bar (overlay texture, PP border, type icon) from the user palette, engine-
-- driven show/hide. Layer priority Magic > Curse > Disease > Poison > Bleed. The
-- animated clock border on debuff icons is not reproducible.
------------------------------------------------------------------------------

local DISPEL_SLOTS = {
    { key = "magic",   token = "Magic",   colorKey = "dispelColorMagic",   atlas = "RaidFrame-Icon-DebuffMagic",   fallback = { 0.349, 0.475, 1.0 },   level = 5 },
    { key = "curse",   token = "Curse",   colorKey = "dispelColorCurse",   atlas = "RaidFrame-Icon-DebuffCurse",   fallback = { 0.636, 0.0, 0.64 },    level = 4 },
    { key = "disease", token = "Disease", colorKey = "dispelColorDisease", atlas = "RaidFrame-Icon-DebuffDisease", fallback = { 0.671, 0.384, 0.098 }, level = 3 },
    { key = "poison",  token = "Poison",  colorKey = "dispelColorPoison",  atlas = "RaidFrame-Icon-DebuffPoison",  fallback = { 0.0, 0.706, 0.286 },   level = 2 },
    { key = "bleed",   token = "Bleed",   colorKey = "dispelColorBleed",   atlas = "RaidFrame-Icon-DebuffBleed",   fallback = { 0.75, 0.15, 0.15 },    level = 1 },
}

-- User dispel palette as a SetAuraBorder customDispelColorMap (engine tints our
-- debuff-icon ring with these; C-side validation reconstructs the color objects),
-- plus a fingerprint so palette edits re-register border options. Resolved via ns
-- at call time (BuildDebuffStyle declared above).
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

-- RAID_PLAYER_DISPELLABLE knows class and spec dispels only, so it never matches
-- Poison for a shaman whose poison removal is Poison Cleansing Totem (a talent).
-- That slot keeps the plain filter in only-dispellable mode; its include-Poison
-- candidate already narrows it to poison debuffs.
-- The capability is CACHED: IsPlayerSpell can lag both addon load and the trait
-- event that announces a change, so the shaman watcher on bmRegen (below)
-- re-checks on trait and spellbook events and forces a reload on a flip.
-- rfcTotemGen lets a button whose shells baked filters under the old value
-- reconcile at finalize.
local POISON_CLEANSING_TOTEM = 383013
local _, rfcPlayerClass = UnitClass("player")
local rfcTotemKnown = rfcPlayerClass == "SHAMAN"
    and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
local rfcTotemGen = 0

local function TokenBlindDispel(token)
    return token == "Poison" and rfcTotemKnown
end

local function DispelSlotFilter(s, token)
    if s.dispelShowAll == false and not TokenBlindDispel(token) then
        return { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }
    end
    return { "HARMFUL" }
end

local function DispelSlotFilters(s)
    local parts = {}
    for i = 1, #DISPEL_SLOTS do
        parts[i] = AK.Filter(unpack(DispelSlotFilter(s, DISPEL_SLOTS[i].token)))
    end
    return parts
end

local function DispelFilterFP(s)
    return table.concat(DispelSlotFilters(s), ";")
end

-- applyExtra for dispel slots. Per-button refs (health, slot definition) come from the
-- creation-time extraInit closure via dd; per-class settings from the shared style.
local function ApplyRFDispelSlot(button, dd, style)
    local health = dd.rfHealth
    local def = dd.rfSlotDef
    if not (style and health and def) then return end
    local PP = EllesmereUI.PP

    -- Change-guarded, stamped AFTER the call: SetFrameLevel on the slot button is
    -- denied while auras are secret (creation-window calls are legal); a restyle-time
    -- throw defers this key to the restriction-lift re-queue.
    -- health+1: below the absorb shield bars (health+3) so fill/full overlays
    -- never cover the shield, above the heal-absorb/heal-prediction fills
    -- (same level, ARTWORK 2). All slots share this level; the Magic > Curse
    -- > ... priority is encoded in the overlay's ARTWORK sublevel below.
    local lvl = health:GetFrameLevel() + 1
    if dd.lvl ~= lvl then
        button:SetFrameLevel(lvl)
        dd.lvl = lvl
    end

    local c = style.typeColors and style.typeColors[def.token]
    local r, g, b = c and c.r or 1, c and c.g or 1, c and c.b or 1
    -- Per-type alpha (0 = user opted this type out of the dispel visuals)
    local typeA = (c and c.a) or 1
    local alpha = (style.opacity or 100) / 100 * typeA

    -- Overlay texture (fill / full / gradient). Sublevel 2+def.level (3..7)
    -- gives higher-priority types the higher sublevel at the shared level.
    -- The fill mode's carrier is a plain texture ANCHORED to the health bar's
    -- fill texture: anchor-derived geometry is the one health-tracking route
    -- that stays legal on aura-slot subtrees (DenyTaintedAccessWhenAurasAreSecret
    -- refuses every tainted WRITE to slot-owned objects while auras are secret
    -- -- a value-fed StatusBar here threw 37x in the field, and OnShow/OnHide
    -- scripts on slot-children never dispatch).
    if not dd.overlay then
        dd.overlay = button:CreateTexture(nil, "ARTWORK", nil, 2 + def.level)
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
        -- Both corners come off the fill texture: a TOPLEFT-of-bar pair only tracks a
        -- left-to-right bar, so a vertical fill spanned the whole frame like "full".
        if fillTex then
            tex:SetAllPoints(fillTex)
        else
            tex:SetAllPoints(health)
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
        -- Above the aura band (unit button + 13, children to +5, cc-glow
        -- carrier +6): health sits at unit button + 2, so this lands the
        -- type icons at +21..+25 -- packing them onto the same corner as the
        -- debuff grid draws them ON TOP of the debuff icons, keeping the
        -- Magic > Curse > Disease > Poison > Bleed ordering, and staying
        -- under the raid marker band (LVL_MARKER 26).
        dd.iconHost:SetFrameLevel(health:GetFrameLevel() + 18 + def.level)
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

-- Fingerprints of exact settings each subsystem reads, per class ("rf:debuff:raid"/
-- party/extra -- proxy values differ per class; scaled proxies bake in scale, so
-- scale changes flip these too).
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
        -- them), so their config is part of this fingerprint.
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

-- Stores current fingerprints without restyling. Called at button setup (which just
-- built from these settings) -- otherwise the first post-login settings change would
-- re-drive every subsystem for the class.
local function PrimeClassFP(styleKey, s)
    local st = classFP[styleKey]
    if not st then st = {}; classFP[styleKey] = st end
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    st.debuffStyle = DebuffStyleFP(s, font)
    st.debuffCfg = DebuffCfgFP(s)
    st.dispLocStyle = DispLocStyleFP(s, font)
    st.dispLocCfg = DispLocCfgFP(s)
    st.dispelStyle = DispelStyleFP(s)
    st.dispelFilter = DispelFilterFP(s)
end

local function ApplyDebuffConfig(container, d, s)
    -- Debuff Manager (12.1 redesign): while active it owns every group on
    -- this container (legacy preset groups park at 0 inside it).
    if ns.DM_Active and ns.DM_Active() and ns.DM_ApplyDebuffConfig then
        ns.DM_ApplyDebuffConfig(container, d, s, StyleKeyFor(d))
        return
    end
    -- Legacy preset display is retired: Debuff Manager (default-ON) is the only
    -- renderer, so with it explicitly disabled the debuff row is EMPTY by design.
    -- Park every group (record variants and tile containers park via DM_ParkGroups).
    local declared = d.rfcDebuffGroups or {}
    for k in pairs(declared) do
        container:SetAuraGroupMaxFrameCount(k, 0)
    end
    if ns.DM_ParkGroups then ns.DM_ParkGroups(container, declared, d) end
end

-- Config for the dispellable-location container: same preset/cap/exclude semantics
-- as the main debuff config, but every group carries includeDispelTypes plus the
-- split's own element size. Groups are on-demand; an undeclared-but-needed group
-- queues its declaration on the combat-legal live lane and re-applies.
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

------------------------------------------------------------------------------
-- BuffManager custom mode -> slots: one slot per tracked spell at a FIXED chain
-- position (no compaction). Icon slots use standard regions; square/bar/effect
-- slots are bare buttons whose extraInit builds custom regions directly. Effects:
-- healthcolor tints the health-fill overlay, bgcolor tints the bar background,
-- border draws the full style set around the unit button (sweep renders fully lit,
-- no ticker under secrecy). framealpha and missing/allPresent/anyMissing show-when
-- are NOT reproducible -- and the obvious workaround is FORBIDDEN BY THE ENGINE:
-- OnShow/OnHide hooks on slot buttons (visibility-edge counting) make the engine's
-- own secret-driven SetShown throw "Cannot be called with secrets due to existing
-- script handlers", failing the whole container build under secrecy (field,
-- 2026-08-14). Never install visibility scripts on engine aura buttons. Effect
-- indicators render presence-driven only; simple mode stays on the legacy renderer.
------------------------------------------------------------------------------

local BM_FRAMELVL = { behindBorders = 7, behindText = 11, medium = 13, high = 14, highest = 15 }
local BM_FRAMELVL_TEXT = 18

local function BmScaleFor(d)
    if d._isParty then return ns._partyBmScale or 1 end
    if d._isExtra then return ns._xfBmScale or 1 end
    return ns._bmScale or 1
end

local function BmIndicators()
    -- Buff Manager v2 (spell -> filter -> indicator): the adapter returns legacy-
    -- shaped indicators with resolved spell unions, gated on the activation flag so
    -- dormant v2 leaves the legacy system untouched.
    if ns.BM2_Enabled and ns.BM2_SpecIndicators then
        return ns.BM2_SpecIndicators()
    end
    if not (ns.BM_GetSpecIndicators and ns.db) then return nil, nil, "custom" end
    local specKey = ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey()
    -- Base grid and custom indicators are INDEPENDENT subsystems -- this function
    -- serves only the custom side (nil inds parks the chains/slots); base grid
    -- resolves via BM_BaseActive/BM_SimpleSpecKey at its own sites. Legacy either/or
    -- bmDisplayMode key is read only inside the effective accessors, never written.
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
    -- v2 curated alternates (same buff under talent/rank ids): resolution keeps ONE
    -- entry per buff family, so the family's alt ids must all match the primary's slot.
    if ns.BM2_PresetAlts then
        local alts = ns.BM2_PresetAlts[spellID]
        if alts then
            for i = 1, #alts do map[alts[i]] = true end
        end
    end
    return map
end

-- Own-only is per-INDICATOR (per-spell overrides are retired; legacy ownOnlySpells
-- data collapses via the v2 read-heal). Legacy nil still reads own-only (pre-v2 default).
local function BmEffOwnOnly(ind)
    if ind.ownOnly ~= nil then return ind.ownOnly end
    return true
end

-- Square per-spell color: options swatches write ind.spellColors[spellID] (legacy
-- ind.color is only a fallback). With nil spellID (shared chain-group style), colors
-- are uniform by construction (BmChainMode forces per-spell slots when they differ),
-- so the first spell's resolved entry is representative.
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

-- Chain rendering mode for icon/square indicators. "g" = one flow GROUP: active
-- auras compact into first positions like the legacy renderer (engine sort order
-- within the chain -- documented delta vs legacy list order). "s" = fixed per-spell
-- slots (required when per-spell overrides -- size offsets, mixed own-only, mixed
-- square colors -- make a shared group impossible; those keep reserved positions).
-- "-" = not a chain kind.
local function BmChainMode(ind)
    if ind.type ~= "icon" and ind.type ~= "square" then return "-" end
    if ind.type == "square" and ind.spellColors then
        -- Mixed per-spell colors: a shared group can't know which spell an engine
        -- button holds, so each spell needs its own slot (only remaining slot-mode
        -- trigger; per-icon size offsets and per-spell own-only are retired).
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
    return "g"
end

-- Own-only state feeds slot filter strings and the chain group's filter,
-- so it is part of the swap signature.
local function BmOwnSig(ind)
    return tostring(ind.ownOnly ~= false)
end

-- Structural only: SLOT own-only state is NOT part of the signature -- it maps to
-- slot filter strings, which update live (a swap here would rebuild the container on
-- every own-only toggle). CHAIN groups bake own-only into their declaration-fixed
-- filter string, so their uniform state IS structural and swaps.
local function BmSignature(inds, specKey, mode)
    -- Spec-scoped sentinel: the simple grid's container exists only for
    -- tracked specs, so a spec change must swap even in simple mode.
    if mode == "simple" or not inds then return "simple:" .. tostring(specKey) end
    local parts = { specKey or "?" }
    for i = 1, #inds do
        local ind = inds[i]
        -- Truthy enabled on purpose (matches legacy lookup gate). framealpha
        -- indicators are deliberately treated as disabled -- fading needs per-aura
        -- presence, secret in combat; options carry the removal notice.
        if ind.enabled and ind.type ~= "framealpha" then
            local cmode = BmChainMode(ind) -- group<->slots transition is structural
            local ownTag = ""
            if cmode == "g" then
                ownTag = BmEffOwnOnly(ind) and ":o" or ":a"
            end
            -- The all-specs flag is structural: it changes which spells survive the
            -- borrow filter in BuildBmSlots, so flipping it must swap the container.
            parts[#parts + 1] = tostring(ind.id or ("x" .. i)) .. ":" .. (ind.type or "icon")
                .. ":" .. table.concat(ind.spells or {}, "-")
                .. ":" .. tostring(ind.showWhen or "present")
                .. ":" .. cmode .. ownTag
                .. (ind.showOwnAllSpecs and ":s" or "")
                -- Custom Order is structural: it decides the per-spell group
                -- segmentation AND which candidate map each group carries, so
                -- both the flag and the arrangement must swap/retarget.
                .. ((cmode == "g" and ind.customOrder) and (":ord" .. table.concat(ind.spellOrder or {}, "-")) or "")
                -- Anchor To is structural: the composition decides how many
                -- groups each pool container declares.
                .. ":@" .. tostring(ind.anchorTo or "")
        end
    end
    return table.concat(parts, "|")
end

-- Candidate filters for one slot: chain slots pass their spellID, effect slots pass
-- the indicator's borrow-filtered spell list. Own-only is NOT expressed here: the
-- isFromPlayerOrPlayerPet candidate boolean matches auras cast by ANY player
-- (verified: same-spec allies' buffs pass it), so own-cast filtering rides the
-- PLAYER filter token instead.
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
-- player's casts) when the indicator is own-only.
local function BuildBmFilter(ind)
    if BmEffOwnOnly(ind) then
        return { "HELPFUL", "PLAYER" }
    end
    return { "HELPFUL" }
end

-- Custom Order (per-indicator opt-in): splits a chain member's single union
-- group into ORDERED segments -- one per-spell group per arranged spell
-- (capped: every group is an eager 10-button engine batch) plus one residual
-- union group for anything unarranged/beyond the cap. The engine's flow
-- layout collapses empty groups, so the run stays gapless while inactive
-- ordered spells simply skip -- exact arranged order without reserved slots.
-- Returns nil for the default single-group behavior (flag off, nothing
-- arranged resolves, or a single spell).
local BM_ORDER_CAP = 10
local function BmSegments(ind, spells)
    if not ind.customOrder or #spells <= 1 then return nil end
    local present = {}
    for k = 1, #spells do present[spells[k]] = true end
    local ordered, seen = {}, {}
    local so = ind.spellOrder
    if so then
        for k = 1, #so do
            local sid = so[k]
            if present[sid] and not seen[sid] and #ordered < BM_ORDER_CAP then
                seen[sid] = true
                ordered[#ordered + 1] = sid
            end
        end
    end
    if #ordered == 0 then return nil end
    local segs = {}
    for k = 1, #ordered do
        segs[#segs + 1] = { spellID = ordered[k], count = 1 }
    end
    local residual
    for k = 1, #spells do
        if not seen[spells[k]] then
            residual = residual or {}
            residual[#residual + 1] = spells[k]
        end
    end
    if residual then
        segs[#segs + 1] = { spells = residual, count = #residual }
    end
    return segs
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

-- Color curve binds at SetDurationText registration, so a changed threshold needs
-- re-registration on restyle. bmRegistered is set AFTER initial registration (keeps
-- this pass inert during init, since applyExtra runs before it). Curves are cached,
-- so unchanged settings yield the same object and skip the rebind. Schema:
-- textColor = { curve, property }.
local function BmRebindDurationCurve(button, dd, style)
    if dd.duration and dd.bmRegistered and style.durationColorCurve ~= dd.bmCurve then
        local durationOpts = AK.BuildDurationTextOpts(AK.GetDurationFormatter(),
            style.durationColorCurve)
        local ok, full = AK.SetDurationTextSafe(button, dd.duration, durationOpts)
        -- Stamp only when the requested set actually landed: a denied or degraded
        -- registration must leave the curve unstamped so a retry/next restyle reruns it.
        if ok and (full or not style.durationColorCurve) then
            dd.bmCurve = style.durationColorCurve
        end
    end
end

-- Display-level Icon Glow (v2 DISPLAY section): a PERMANENT glow on every visible
-- icon of the group, not threshold-gated. Child frame rides button visibility;
-- StartEngineGlow renders Pixel as the genuine C-side dash march and routes other
-- driver styles to FlipBook so restricted content animates identically; params
-- cache on the overlay (our frame) so a steady glow never resets on restyles.
local function ApplyBmIconGlow(button, dd, style)
    local Glows = EllesmereUI.Glows
    if not Glows then return end
    local gType = style.bmGlowType or 0
    if gType > 0 and Glows.StartEngineGlow then
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
            Glows.StartEngineGlow(gov, gType, sz, cr, cg, cb)
            gov._bmStyle, gov._bmW = gType, sz
            gov._bmCR, gov._bmCG, gov._bmCB = cr, cg, cb
        end
    elseif dd.bmGlow and dd.bmGlow._euiGlowActive and Glows.StopGlow then
        Glows.StopGlow(dd.bmGlow)
    end
end

-- applyExtra for icon slots: shared text pass + opacity + BM frame levels.
-- hideIcon = legacy text-only mode (icon/swipe/border hidden via style flags;
-- duration text and stacks unaffected).
local function ApplyBmIconExtra(button, dd, style)
    ApplyRFDebuffText(button, dd, style)
    -- "Hide Icons" gate: like the hidden swipe (see AuraKit's style pass), a
    -- one-shot SetShown is undone by aura content churn -- the engine's display
    -- update re-shows the registered icon texture when the slot's aura data
    -- refreshes. Same two-layer defense reading a LIVE flag (a hook cannot
    -- uninstall): Show post-hook re-hides, alpha 0 covers engine paths that
    -- re-show outside the hooked Lua method. Hook installs lazily on first hide.
    if dd.icon then
        dd.bmHideIcon = style.hideIcon == true
        dd.icon:SetShown(not dd.bmHideIcon)
        if dd.bmHideIcon and not dd.bmIconHooked then
            dd.bmIconHooked = true
            local icon = dd.icon
            hooksecurefunc(icon, "Show", function()
                if dd.bmHideIcon then icon:Hide() end
            end)
        end
        local iconA = dd.bmHideIcon and 0 or 1
        if dd.bmIconAlpha ~= iconA then
            dd.icon:SetAlpha(iconA)
            dd.bmIconAlpha = iconA
        end
    end
    -- Button-object calls are denied while auras are secret: base level is read ONCE
    -- inside the creation window and cached; alpha/level writes are change-guarded
    -- with the stamp written AFTER the call (a denied write throws, deferring the key
    -- to the restriction-lift re-queue).
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

-- Buff/HoT tooltip gate (profile-root "Hide Buff Tooltips", default hidden). Engine
-- aura buttons render their own tooltip when mouse motion is on, showing the real
-- aura even while secret; effect slots (healthcolor/border) stay motion-off always
-- (they overlay the health bar). 4-state mode: true/nil=hidden, false=shown,
-- "combat"=hidden in combat, "cursor"=shown at cursor.
local function BmTipMode()
    local p = ns.db and ns.db.profile
    local v = p and p.buffHideTooltips
    if v == nil then v = true end
    return v
end

local function BmTipsOff()
    local v = BmTipMode()
    return not (v == false or v == "combat" or v == "cursor")
end

local function BuildBmIconStyle(ind, iscale, size)
    local br, bg, bb = BmColor(ind.indBorderColor, 0, 0, 0)
    local hideIcon = ind.hideIcon == true
    return {
        width = size,
        height = size,
        iconCrop = true,
        iconZoom = (ns.db and ns.db.profile and ns.db.profile.bmIconZoom) or 0.08,
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
        tooltipCombatHide = BmTipMode() == "combat",
        tooltipAnchor = (BmTipMode() == "cursor") and "cursor" or nil,
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

-- Bare-slot styling passes run at init (guarded: regions may not exist yet on the
-- first ApplyStyleToRegions call) and on every Restyle, so square/bar/effect settings
-- live-update like everything else. Each style table carries its indicator as style.ind.
local function BmApplySquare(button, dd, style)
    if not dd.tex then return end
    local ind = style.ind
    local r, g, b = BmColor(style.sqColor, 12 / 255, 210 / 255, 157 / 255)
    dd.tex:SetColorTexture(r, g, b, 1)
    -- Same hidden-swipe gate as AuraKit's style pass (engine SetCooldown re-shows
    -- a hidden swipe on aura churn; SetDrawSwipe is the persistent style knob
    -- that survives it), needed here too because square cooldowns are created
    -- AFTER the bare-mode style pass runs -- creation would otherwise ship
    -- ungated. Shares the akHideSwipe stamp so the two drivers never fight.
    if dd.cooldown then
        local hideSwipe = ind.showDuration == false
        dd.cooldown:SetShown(not hideSwipe)
        if dd.akHideSwipe ~= hideSwipe then
            dd.akHideSwipe = hideSwipe
            if dd.cooldown.SetDrawSwipe then dd.cooldown:SetDrawSwipe(not hideSwipe) end
        end
    end
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
    -- Fill AXIS, mirroring what the preview has always done in BM_PlaceBar.
    -- Change-guarded like the frame-level write below: SetOrientation resets the
    -- bar's fill, so calling it on every restyle would visibly stutter a running
    -- bar. Orientation has to be in BmVisualKey for this to run at all -- it
    -- otherwise lives only in the geometry fingerprint, which drives the anchor
    -- pass and never reaches here.
    local isVert = (ind.orientation or "HORIZONTAL") == "VERTICAL"
    if dd.bmBarVert ~= isVert then
        dd.bmBarVert = isVert
        dd.bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    end
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
    if ind.type == "healthcolor" or ind.type == "bgcolor" then
        if dd.tex then
            local r, g, b = BmColor(ind.color, 0, 1, 0)
            local a = (ind.opacity or 100) / 100
            -- healthcolor rides the fill and borrows its texture; bgcolor covers
            -- the bar's background, which is a flat color fill, so it stays flat.
            if ind.type == "healthcolor" then
                ns.RF_TintOverBarFill(dd.tex, dd.bmHealthBar, r, g, b, a)
            else
                dd.tex:SetColorTexture(r, g, b, a)
            end
        end
    elseif ind.type == "border" then
        -- Full legacy renderer (solid/dashed/textured/sweep) on the border host --
        -- our frame, legal on every restyle. Sweep renders fully lit (no aura-driven
        -- ticker under secrecy); dashed uses the C-side animated ants (w/h from the
        -- unit frame's own rect -- the forbidden host is never measured).
        if dd.borderHost and ns.BM_ApplyEffectBorder then
            local r, g, b = BmColor(ind.color, 0.05, 0.82, 0.62)
            local host = dd.bmFxHost
            local w, h
            if host then w, h = host:GetWidth(), host:GetHeight() end
            ns.BM_ApplyEffectBorder(dd.borderHost, ind, r, g, b,
                (ind.borderOpacity or 100) / 100, w, h)
            dd.borderHost:Show()
        end
    end
end

-- Bare-slot extraInits: region creation only (once per slot button); styling flows
-- through the apply passes above. Squares/bars start mouse-transparent and the apply
-- pass re-drives motion per the buff tooltip setting; effect slots stay transparent
-- always (they overlay the health bar/unit button).
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

    -- Duration/stack text, same carrier arrangement as standard icon regions (above
    -- the swipe). Fonts MUST be applied before the engine registrations below.
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
    -- Creation-window registration is always legal; the curve stamp still follows the
    -- full-success rule so a rejected curve half re-binds next restyle, not skipped.
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

    -- Fill AXIS. A StatusBar defaults to HORIZONTAL, so a vertical bar rendered
    -- tall and narrow (BmAnchorOneSlot) while still draining sideways until this
    -- landed. Set BEFORE the engine registration below in case the axis is
    -- snapshotted there; BmApplyBar re-drives it for live toggles.
    local initVert = ((style.ind and style.ind.orientation) or "HORIZONTAL") == "VERTICAL"
    bar:SetOrientation(initVert and "VERTICAL" or "HORIZONTAL")
    dd.bmBarVert = initVert

    local opts = {}
    if Enum.StatusBarInterpolation then opts.interpolation = Enum.StatusBarInterpolation.Immediate end
    if Enum.StatusBarTimerDirection then opts.direction = Enum.StatusBarTimerDirection.RemainingTime end
    button:SetDurationBar(bar, opts)

    BmApplyBar(button, dd, style)
end

local function BmEffectInit(button, dd, style, ind, health)
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    if ind.type == "healthcolor" then
        -- Level-tied with the health frame (NOT +1): sort against health's own ARTWORK
        -- sublevels (above fill at 0), staying BELOW heal absorb/prediction (health +1)
        -- and shield bars (+3). At +1 this tied heal absorb on strata+level+layer+
        -- sublevel, so paint order fell to creation order and the tint blended over an
        -- opaque heal absorb. Anchored to the fill texture so only the filled portion
        -- tints, not empty/missing health.
        button:SetFrameLevel(health:GetFrameLevel())
        dd.bmHealthBar = health  -- apply pass borrows this bar's fill texture
        dd.tex = button:CreateTexture(nil, "ARTWORK", nil, 2)
        local fillTex = health.GetStatusBarTexture and health:GetStatusBarTexture()
        if fillTex then
            dd.tex:SetAllPoints(fillTex)
        else
            dd.tex:SetAllPoints(health)
        end
        ns.RF_RegisterBarTint(health, dd.tex, nil, "bm")
    elseif ind.type == "bgcolor" then
        -- Background Color: whole health area, ARTWORK -2 = below fill (sublevel 0)
        -- and healthcolor tint (+2), above the bar's own backdrop -- reads as bg.
        button:SetFrameLevel(health:GetFrameLevel())
        dd.tex = button:CreateTexture(nil, "ARTWORK", nil, -2)
        dd.tex:SetAllPoints(health)
    elseif ind.type == "border" then
        local unitButton = button:GetParent() and button:GetParent():GetParent()
        if unitButton then
            -- Slot button sits AT the unit button's level: legacy renderer
            -- (BM_ApplyEffectBorder) levels the host at parent+11 (static)/+14
            -- (sweep) -- exact live parity.
            button:SetFrameLevel(unitButton:GetFrameLevel())
            dd.borderHost = CreateFrame("Frame", nil, button)
            dd.borderHost:SetAllPoints(unitButton)
            -- OUR secure unit button, outside the forbidden subtree: apply pass reads
            -- its rect for the dashed-style animated ants (border host is unmeasurable
            -- outside this window).
            dd.bmFxHost = unitButton
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
            bmGlowType = ind.displayGlowType or 0,
            bmGlowClassColor = ind.displayGlowClassColor,
            bmGlowR = ind.displayGlowR,
            bmGlowG = ind.displayGlowG,
            bmGlowB = ind.displayGlowB,
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
            tooltipCombatHide = BmTipMode() == "combat",
            tooltipAnchor = (BmTipMode() == "cursor") and "cursor" or nil,
            -- Squares share the display-level Icon Glow (same overlay child
            -- mechanism; the control sits on the shared icon/square pane).
            applyExtra = function(b, d2, st)
                BmApplySquare(b, d2, st)
                ApplyBmIconGlow(b, d2, st)
            end,
        }
    end
    if kind == "bar" then
        return { width = 1, height = 1, noRegions = true, ind = ind,
            noTooltips = BmTipsOff(),
            tooltipCombatHide = BmTipMode() == "combat",
            tooltipAnchor = (BmTipMode() == "cursor") and "cursor" or nil,
            applyExtra = BmApplyBar }
    end
    return { width = 1, height = 1, noRegions = true, ind = ind, applyExtra = BmApplyEffect }
end

-- Geometry for ONE slot button, split out of AnchorBmSlots so each slot's extraInit
-- can self-anchor inside the creation window -- the only place SetSize/SetPoint is
-- legal while auras are secret (12.1 access restriction; BM builds run mid-instance:
-- joiners, in-key reloads). AnchorBmSlots re-runs it OOC on geometry changes.
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

-- Builds the slot spec list for the current indicator set plus the group-mode chain
-- indicators (rendered as compacting flow containers). Borrow specs (Enh/Ele/Prot/Ret)
-- only get slots for spells they can cast, mirroring the legacy lookup restriction;
-- positions renumber over the usable list.
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
        if ind.enabled and ind.type ~= "framealpha" then
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
                    local size = (ind.size or 18) * iscale
                    local slotKey = "bm" .. tostring(ind.id or ("x" .. i)) .. "_" .. k
                    local styleKey = styleBase .. ":" .. tostring(ind.id or ("x" .. i)) .. ":" .. k
                    -- Meta entry built FIRST so extraInit closures below can self-
                    -- anchor inside the creation window (post-creation SetPoint/
                    -- SetSize is denied while auras are secret -- 12.1 restriction).
                    local mm = { key = slotKey, styleKey = styleKey, ind = ind, k = k, count = #spells,
                        kind = kind, size = size, spellID = spellID }
                    local entry = {
                        key = slotKey,
                        filter = BuildBmFilter(ind),
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
            elseif kind == "healthcolor" or kind == "bgcolor" or kind == "border" then -- effect slots
                -- showWhen is deliberately IGNORED here: only "When Any Present"
                -- is reproducible on 12.1 (see the header note -- the counting
                -- workaround is engine-forbidden), and the pre-heal behavior of
                -- skipping the slot for other stored modes rendered NOTHING
                -- silently (field report). A stale "allPresent"/"missing" config
                -- now renders presence-driven; the options pane offers only the
                -- supported mode.
                local slotKey = "bm" .. tostring(ind.id or ("x" .. i)) .. "_fx"
                local styleKey = styleBase .. ":" .. tostring(ind.id or ("x" .. i)) .. ":fx"
                AK.styles[styleKey] = BuildBmStyleFor(kind, ind, iscale, 1)
                local mm = { key = slotKey, styleKey = styleKey, ind = ind, kind = kind, spells = spells }
                slots[#slots + 1] = {
                    key = slotKey,
                    filter = BuildBmFilter(ind),
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
    -- Anchor To (icon->icon/square->square): an anchored indicator's group renders
    -- INSIDE its target's container, continuing that run. Declaration-time composition
    -- only -- group count matches unanchored (one per indicator); attached indicators
    -- just lose their own container. Broken links (missing, disabled, type-mismatch,
    -- slot-mode targets, cycles) fall back to the indicator's own position.
    do
        local byId = {}
        for i = 1, #chains do
            local id = chains[i].ind.id
            if id ~= nil then byId[id] = chains[i] end
        end
        local function ResolveRoot(ch)
            local seen = { [ch] = true }
            local cur = ch
            while true do
                local tid = cur.ind.anchorTo
                if tid == nil then return cur end
                local nxt = byId[tid]
                if not nxt or seen[nxt]
                    or (nxt.ind.type or "icon") ~= (ch.ind.type or "icon") then
                    return nil
                end
                seen[nxt] = true
                cur = nxt
            end
        end
        local roots, attach, anyAnchor = {}, {}, false
        for i = 1, #chains do
            local ch = chains[i]
            local root = ch.ind.anchorTo and ResolveRoot(ch) or ch
            if root == nil or root == ch then
                roots[#roots + 1] = ch
            else
                anyAnchor = true
                local a = attach[root]
                if not a then a = {}; attach[root] = a end
                a[#a + 1] = ch
            end
        end
        if anyAnchor then
            for i = 1, #roots do
                local a = attach[roots[i]]
                if a then
                    table.sort(a, function(x, y) return (x.ind.id or 0) < (y.ind.id or 0) end)
                    roots[i].members = a
                end
            end
            chains = roots
        end
    end
    return slots, meta, chains
end

-- Anchors a chain container so its flow starts at the indicator position and compacts
-- along the grow direction. Rule: the FIRST icon's `pos` corner sits exactly on the
-- same corner of the health bar (icons render INSIDE the frame there), and the chain
-- grows outward -- so the flow's start corner offsets by one element dimension on any
-- axis disagreeing with the position point (half a dimension on centered axes).
-- CENTER growth keeps the run centered on the position point, vertical edge flush.
-- members = array of { ind, count }; members[1] is the ROOT driving position/growth/
-- wrap. Attached members (Anchor To) each contribute one flow group with their own
-- element size and Max Icons cap.
local function AnchorBmChainContainer(container, health, members, iscale)
    if not container then return end
    local ind = members[1].ind
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
        -- Wrap away from the anchored edge (simple-grid convention): cross-axis
        -- component only applies once wrapping is on; unwrapped = legacy single-run.
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
    -- Grid wrap (12.1 feature -- live indicators were always linear runs): Icons Per
    -- Row > 0 caps each line at n cells; vertical orientations flip the flow axis so
    -- lines are COLUMNS (n tall, wrapping sideways). 0/nil = one unbounded line (exact
    -- pre-grid behavior; explicit axis reset keeps pooled containers clean across retargets).
    if per > 0 then
        AK.SetContainerAxis(container, vertical)
        AK.SetContainerRowWidth(container, per * size + (per - 1) * spacing + 0.4)
    else
        AK.SetContainerAxis(container, false)
        AK.SetContainerRowWidth(container, vertical and (size + 0.4) or nil)
    end

    -- Element size/spacing feed the FLOW math (button SetSize is only physical size),
    -- so geometry changes re-drive group layouts. One layout per group (a Custom
    -- Order member contributes one group per SEGMENT -- see BmSegments; entries then
    -- carry memberIndex/segIndex, plain arrays behave as one segment per member):
    -- anchored members keep their own element size; layoutIndex pins flow order (root
    -- first) so lazily re-declared groups never reorder. Inter-group gap matches the
    -- root's icon spacing so the seam reads as one continuous run.
    local budgets = {}
    for j = 1, #members do
        local mm = members[j]
        local gk = (j == 1) and "chain" or ("chain" .. j)
        local msize = (mm.ind.size or 18) * iscale
        local mi = mm.memberIndex or j
        -- Anchored members: Offset X/Y projects onto the run as the gap between
        -- their group and the previous one (only per-group positional lever a shared
        -- flow offers; cross-axis has no engine expression). Sign follows flow
        -- direction, so positive always pushes the member further along the run.
        -- Applies only at a MEMBER boundary; a member's own later segments keep the
        -- plain icon spacing so its run stays continuous.
        local mGap = spacing
        if j > 1 and (mm.segIndex or 1) <= 1 and mi > 1 then
            local off
            if vertical then
                off = (mm.ind.offsetY or 0)
                if gV == "DOWN" then off = -off end
            else
                off = (mm.ind.offsetX or 0)
                if gH == "LEFT" then off = -off end
            end
            -- Negative values pull the member back along the run (overlap
            -- is legitimate -- parity with what a free offset could do).
            mGap = spacing + off * iscale
        end
        container:SetAuraGroupLayout(gk, {
            elementWidth = msize, elementHeight = msize,
            elementSpacing = spacing, lineSpacing = spacing,
            groupSpacing = mGap,
            layoutIndex = j,
        })
        -- Max Icons: cap each member's groups below its own spell count.
        -- Runs here so both the acquire path and the geometry pass re-drive
        -- it live (the setter is dirty-mark cheap on unchanged values).
        -- Segmented members spend ONE member-wide budget along the arranged
        -- order, so Max Icons means "first N configured" there (which groups
        -- are ACTIVE is secret in combat -- a live first-N-active cap is
        -- inexpressible); trailing segments zero out.
        local cap = mm.count or 0
        if cap > 0 then
            local maxI = tonumber(mm.ind.maxIcons) or 0
            if maxI > 0 then
                local rem = budgets[mi]
                if rem == nil then rem = maxI end
                if cap > rem then cap = rem end
                budgets[mi] = rem - cap
            end
            container:SetAuraGroupMaxFrameCount(gk, cap)
        end
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
        return FP(font, size, (ns.db and ns.db.profile and ns.db.profile.bmIconZoom) or 0.08,
            ind.iconOpacity, ind.hideIcon, ind.indBorderSize, CK(ind.indBorderColor),
            ind.showDuration, ind.showDurationText, ind.durationTextSize, CK(ind.durationTextColor),
            ind.durationTextOffsetX, ind.durationTextOffsetY, ind.thresholdEnabled, ind.threshold,
            CK(ind.thresholdColor), ind.showStacks, ind.stacksTextSize, CK(ind.stacksTextColor),
            ind.stacksOffsetX, ind.stacksOffsetY, ind.frameLevel, tostring(BmTipMode()),
            ind.displayGlowType, ind.displayGlowClassColor,
            ind.displayGlowR, ind.displayGlowG, ind.displayGlowB)
    end
    if kind == "square" then
        return FP(font, size, CK(BmSquareColor(ind, spellID)), ind.showDuration, ind.indBorderSize,
            CK(ind.indBorderColor), ind.frameLevel, ind.showDurationText, ind.durationTextSize,
            CK(ind.durationTextColor), ind.durationTextOffsetX, ind.durationTextOffsetY,
            ind.thresholdEnabled, ind.threshold, CK(ind.thresholdColor), ind.showStacks,
            ind.stacksTextSize, CK(ind.stacksTextColor), ind.stacksOffsetX, ind.stacksOffsetY, tostring(BmTipMode()),
            ind.displayGlowType, ind.displayGlowClassColor,
            ind.displayGlowR, ind.displayGlowG, ind.displayGlowB)
    end
    if kind == "bar" then
        -- orientation is the one geometry field that is ALSO a visual: it swaps
        -- the bar's screen axis (BmGeoFP, anchor pass) and its fill axis
        -- (BmApplyBar). The other bar geometry stays out on purpose.
        return FP(CK(ind.color), ind.barColorOpacity, ind.reverseFill, ind.orientation,
            CK(ind.barBgColor), ind.barBgOpacity, ind.frameLevel, tostring(BmTipMode()))
    end
    return FP(ind.type, CK(ind.color), ind.opacity, ind.borderWidth, ind.borderOpacity,
        ind.borderStyle, ind.borderDashCount)
end

local function BmOwnKey(meta)
    local t = {}
    for i = 1, #meta do t[i] = BmOwnSig(meta[i].ind) end
    return table.concat(t, ";")
end

-- Geometry fingerprint over every input AnchorBmSlots reads: slot-button SetSize/
-- SetPoint are engine-wrapped calls, so the anchor pass only reruns on actual changes.
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
    -- Slot-button geometry is denied while auras are secret (12.1 restriction). Chain
    -- CONTAINERS are our frames and always re-anchor; slot buttons skip and report it,
    -- so the caller leaves its geometry fingerprint unstamped for the restriction-lift
    -- sweep to re-enter (fresh builds are unaffected -- every slot self-anchors in its
    -- extraInit).
    local restricted = AK.AurasRestricted()
    local skipped = false
    for i = 1, #meta do
        local m = meta[i]
        -- Anchored member metas share their root's container; the root's
        -- meta carries the member list and anchors once for the set.
        if m.isChain and not m.anchored then
            AnchorBmChainContainer(d.rfcBmChain and d.rfcBmChain[m.chainKey], health,
                m.members or { { ind = m.ind, count = m.count or (m.ind.spells and #m.ind.spells) } },
                iscale)
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
-- Simple Setup grid: active spec's whole tracked-buff whitelist as ONE flow group per
-- button, own casts only. Vertical growth is a single column (wraps by row width, so
-- Icons Per Row is horizontal-mode); within-grid order is engine sort, not scan order.
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
        tostring(BmTipMode()))
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
        tooltipCombatHide = BmTipMode() == "combat",
        tooltipAnchor = (BmTipMode() == "cursor") and "cursor" or nil,
        applyExtra = ApplyBmSimpleExtra,
    }
end

-- Mirrors the legacy AnchorSimpleGrid: the grid's start corner pinned at the same
-- corner of the health bar, rows wrap after Icons Per Row and stack away from the
-- anchored edge; CENTER growth centers rows on the anchor point.
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
                -- Per-button visibility re-drive (same pattern as the rebuild path):
                -- clears the readable cache so SetShown/secret range alpha re-apply.
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
        -- Whitelist is spec-resolved, so a spec change must re-drive candidates even
        -- with unchanged settings (container REBUILD-on-spec-change is retired).
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

-- Chain container POOL: engine frames are never freed, so recreating a chain
-- container on every structural edit permanently leaked its 10-button batch (spec
-- swaps leaked one set per spec). Pool entries persist for the session, keyed by
-- kind + own-variant (own-only needs its own variant since filter strings are
-- declaration-fixed) + ordinal; a "swap" retargets live (candidates, count, layout,
-- anchor, style) with no creation, no leak. Unused entries park at count 0, hidden.
local bmPoolReloadPending = false
local function BmPoolReloadSoon()
    if bmPoolReloadPending then return end
    bmPoolReloadPending = true
    C_Timer.After(0.05, function()
        bmPoolReloadPending = false
        if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
    end)
end

-- Acquire (or lazily create) the pool entry for one chain SET -- a root chain plus
-- any Anchor To members riding its container as continuation groups -- and retarget
-- it live. Returns the container plus per-member styleKey list, or nil while the
-- shell is still pending on the OOC build queue (shells cannot be created in combat).
local function BmAcquireChain(button, d, health, ch, iscale, counters)
    local pool = d.rfcBmPool
    if not pool then pool = {}; d.rfcBmPool = pool end
    local ind = ch.ind
    local kind = ind.type or "icon"
    -- Member list: root first, then the attached chains (already sorted).
    local members = { ch }
    if ch.members then
        for j = 1, #ch.members do members[#members + 1] = ch.members[j] end
    end
    local ownPat = {}
    for j = 1, #members do
        ownPat[j] = BmEffOwnOnly(members[j].ind) and "o" or "a"
    end
    -- Custom Order: per-member segmentation (nil = single union group).
    local segsBy, anySegs = {}, false
    for j = 1, #members do
        local segs = BmSegments(members[j].ind, members[j].spells)
        if segs then segsBy[j] = segs; anySegs = true end
    end
    local totalGroups = 0
    for j = 1, #members do
        totalGroups = totalGroups + (segsBy[j] and #segsBy[j] or 1)
    end
    local ck = kind .. ":" .. table.concat(ownPat)
    if anySegs then
        -- Segment shape joins the pool key (group sets are add-only, so a
        -- differently-segmented chain needs its own container). The trailing
        -- colon keeps BmParkUnbound's trailing-digit split unambiguous.
        local sc = {}
        for j = 1, #members do sc[j] = tostring(segsBy[j] and #segsBy[j] or 1) end
        ck = ck .. ":" .. table.concat(sc, "-") .. ":"
    end
    local n = (counters[ck] or 0) + 1
    counters[ck] = n
    local poolKey = ck .. n
    local styleBase = StyleKeyFor(d):gsub("debuff", "bmpool") .. ":" .. poolKey

    -- Per-member styles (each group carries its own size/text styling).
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("raidFrames")) or ""
    local styleKeys = {}
    for j = 1, #members do
        local mInd = members[j].ind
        local sk = (j == 1) and styleBase or (styleBase .. ":" .. j)
        styleKeys[j] = sk
        local msize = (mInd.size or 18) * iscale
        local vk = BmVisualKey(kind, mInd, msize, font)
        if bmStyleFP[sk] ~= vk then
            bmStyleFP[sk] = vk
            AK.styles[sk] = BuildBmStyleFor(kind, mInd, iscale, msize)
            AK.RestyleSoon(sk)
        end
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
    -- Group keys number SEQUENTIALLY across members' segments ("chain",
    -- "chain2", ...); a member without Custom Order contributes exactly one
    -- group, so the default shape is byte-identical to the pre-segment code.
    local function DeclareGroups(cc)
        local g = 0
        for j = 1, #members do
            local filter
            if ownPat[j] == "o" then filter = { "HELPFUL", "PLAYER" } else filter = { "HELPFUL" } end
            for _ = 1, (segsBy[j] and #segsBy[j] or 1) do
                g = g + 1
                AK.AddGroupToContainer(cc, {
                    key = (g == 1) and "chain" or ("chain" .. g),
                    filter = filter, maxFrameCount = 0,
                    sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
                    style = styleKeys[j], extraInit = ChainExtraInit(),
                    layout = { layoutIndex = g },
                })
            end
        end
    end

    local entry = pool[poolKey]
    if entry == nil then
        -- Bare early-window shells are variant-agnostic (no group yet):
        -- claim one and complete it right here -- group add + finish are
        -- combat-legal, so chains bind even mid-combat after a reload.
        local shell = d.rfcBmShellPool and table.remove(d.rfcBmShellPool)
        if shell then
            DeclareGroups(shell)
            AK.FinishContainer(shell, button:GetAttribute("unit") or "player")
            entry = { container = shell, groups = totalGroups }
            pool[poolKey] = entry
        else
            pool[poolKey] = "pending"
            AK.QueueBuildJob(function()
                local cc = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
                DeclareGroups(cc)
                AK.FinishContainer(cc, button:GetAttribute("unit") or "player")
                pool[poolKey] = { container = cc, groups = totalGroups }
                BmPoolReloadSoon() -- rebind the buttons waiting on this shell
            end, "rf:bmpool-shell")
            return nil, styleKeys
        end
    elseif entry == "pending" then
        return nil, styleKeys
    end

    local cc = entry.container
    entry.parked = nil
    cc:SetUnit(button:GetAttribute("unit") or "player")
    -- anchorMembers is per-GROUP (one entry per segment); memberIndex/segIndex
    -- let the anchor pass tell member boundaries from intra-member segments.
    local anchorMembers = {}
    local g = 0
    for j = 1, #members do
        local mInd, mSpells = members[j].ind, members[j].spells
        local segs = segsBy[j]
        for si = 1, (segs and #segs or 1) do
            g = g + 1
            local gk = (g == 1) and "chain" or ("chain" .. g)
            local seg = segs and segs[si]
            if seg and seg.spellID then
                cc:SetAuraGroupCandidateFilters(gk, BuildBmCand(mInd, nil, seg.spellID))
            else
                cc:SetAuraGroupCandidateFilters(gk, BuildBmCand(mInd, (seg and seg.spells) or mSpells))
            end
            anchorMembers[g] = { ind = mInd, count = (seg and seg.count) or #mSpells,
                memberIndex = j, segIndex = si }
        end
    end
    AnchorBmChainContainer(cc, ns.RF_AnchorHost and ns.RF_AnchorHost(health, ProxyFor(d)) or health,
        anchorMembers, iscale)
    cc:SetShown(d.rfcAssist ~= false)
    return cc, styleKeys, anchorMembers
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
                for j = 1, (entry.groups or 1) do
                    entry.container:SetAuraGroupMaxFrameCount(
                        (j == 1) and "chain" or ("chain" .. j), 0)
                end
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

    -- Group-mode chains render through the persistent per-button POOL: acquired
    -- entries retarget live (no creation, no leak); a chain whose shell is still
    -- building binds on the deferred pool reload (sig stays nil so it re-enters here).
    local counters = {}
    local pendingChains = false
    local chainContainers = nil
    for ci = 1, #chains do
        local ch = chains[ci]
        local ind = ch.ind
        local chainKey = tostring(ind.id or ("x" .. ch.idx))
        local size = (ind.size or 18) * iscale
        local cc, styleKeys, anchorMembers = BmAcquireChain(button, d, health, ch, iscale, counters)
        if cc then
            chainContainers = chainContainers or {}
            chainContainers[chainKey] = cc
            -- Root meta carries the member list (the geometry pass anchors
            -- the container once for the whole set); each Anchor To member
            -- gets its own meta entry for style/candidate re-drives.
            meta[#meta + 1] = { key = "chain_" .. chainKey, styleKey = styleKeys[1], ind = ind,
                kind = ind.type, isChain = true, chainKey = chainKey, groupKey = "chain",
                size = size, count = #ch.spells, spells = ch.spells,
                members = anchorMembers }
            if ch.members then
                for j = 1, #ch.members do
                    local mch = ch.members[j]
                    meta[#meta + 1] = { key = "chain_" .. chainKey .. "_m" .. j,
                        styleKey = styleKeys[j + 1], ind = mch.ind, kind = mch.ind.type,
                        isChain = true, anchored = true, chainKey = chainKey,
                        groupKey = "chain" .. (j + 1),
                        size = (mch.ind.size or 18) * iscale,
                        count = #mch.spells, spells = mch.spells }
                end
            end
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
    local counters = {}
    local meta = {}
    local old = d.rfcBmMeta or {}
    for i = 1, #old do
        if not old[i].isChain then meta[#meta + 1] = old[i] end
    end
    -- Chain collection + Anchor To composition are BuildBmSlots' job;
    -- re-running it here only re-derives spec tables (slot/style writes
    -- are idempotent -- no containers are touched by the call itself).
    local styleBase = StyleKeyFor(d):gsub("debuff", "bm")
    local _, _, chains = BuildBmSlots(cls.inds, d, health, iscale, styleBase)
    local chainContainers = nil
    local pending = false
    for ci = 1, #chains do
        local ch = chains[ci]
        local ind = ch.ind
        if #ch.spells > 0 then
            local chainKey = tostring(ind.id or ("x" .. ch.idx))
            local size = (ind.size or 18) * iscale
            local cc, styleKeys, anchorMembers = BmAcquireChain(button, d, health, ch, iscale, counters)
            if cc then
                chainContainers = chainContainers or {}
                chainContainers[chainKey] = cc
                meta[#meta + 1] = { key = "chain_" .. chainKey, styleKey = styleKeys[1],
                    ind = ind, kind = ind.type, isChain = true, chainKey = chainKey,
                    groupKey = "chain", size = size, count = #ch.spells, spells = ch.spells,
                    members = anchorMembers }
                if ch.members then
                    for j = 1, #ch.members do
                        local mch = ch.members[j]
                        meta[#meta + 1] = { key = "chain_" .. chainKey .. "_m" .. j,
                            styleKey = styleKeys[j + 1], ind = mch.ind, kind = mch.ind.type,
                            isChain = true, anchored = true, chainKey = chainKey,
                            groupKey = "chain" .. (j + 1),
                            size = (mch.ind.size or 18) * iscale,
                            count = #mch.spells, spells = mch.spells }
                    end
                end
            else
                pending = true
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
            m.size = (m.ind.size or 18) * iscale
        end
    end
end

-- Signature/visual/geometry fingerprints are identical for every button of a class,
-- so they compute ONCE per class per reload (a per-button pass rebuilt the same
-- strings 40x in raids). The cls table is cached by the caller for one RFC_ReloadAll pass.
local function BmClassPass(d)
    local cls = {}
    cls.inds, cls.specKey, cls.mode = BmIndicators()
    cls.sig = BmSignature(cls.inds, cls.specKey, cls.mode)
    cls.iscale = BmScaleFor(d)
    cls.styleKey = StyleKeyFor(d)
    return cls
end

-- Style checks run against the first container-carrying button's metas; AK.Restyle
-- reaches every registered button of the style either way. Own-only changes flag a live
-- candidate-filter re-drive (per button, below) rather than a container swap.
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
        -- Release the SLOTS container only (deregisters its buttons from the restyle
        -- registry). Chain POOL and simple container persist forever -- engine frames
        -- are never freed, so releasing them leaked batches on every structural edit;
        -- the rebuild retargets them live instead.
        if d.rfcBm then AK.ReleaseContainer(d.rfcBm) end
        d.rfcBm, d.rfcBmFrames, d.rfcBmMeta, d.rfcBmChain = nil, nil, nil, nil
        d.rfcBmSig = nil
        -- Those slot buttons own this bar's Health Bar Color overlays, and engine
        -- frames are never freed (see above), so their registry entries would pile
        -- up one set per rebuild and every later layout pass would walk the dead
        -- ones. The registry is pure cache: the next paint re-adds what is live.
        ns.RF_ClearBarTints(d.rfcHealth, "bm")
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
                        AK.Filter(unpack(BuildBmFilter(m.ind))))
                end
            end
        end
    end
end

-- TWO-PHASE construction (a solo login otherwise built the FULL group set for 86
-- buttons, 85 empty, at ~7ms/declaration = ~5.5s; shells cost ~0.26ms each). PHASE A
-- (every styled button):
-- container SHELLS + dispel slots -- the one thing combat cannot create, so mid-combat
-- joiners always find them ready (~2.5ms/button). PHASE B (buttons that HOLD a unit,
-- triggered by assignment): group declarations, BM, finish/config -- rides the
-- combat-legal live lane since shells exist from phase A, so a mid-fight joiner gets
-- debuffs/defensives immediately (BM needs container creation, completes at regen).
-- Shells build SYNCHRONOUSLY from StyleButton: combat has not re-engaged yet even on
-- an in-combat /reload (lockdown reads false), so creation is safe there; expensive
-- group/BM work stays on the worker queue.
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

    -- Dispellable-location container: strictly opt-in -- shell only exists while the
    -- split is enabled somewhere (DispLocAnyActive, since class flags may not be
    -- stamped yet); zero cost otherwise. Enabling mid-session builds via the OOC lane.
    if not (d.rfcDispLocShell or d.rfcDispLoc) and DispLocAnyActive() then
        local c = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
        c:SetFrameLevel(button:GetFrameLevel() + (ns.LVL_AURA or 13))
        d.rfcDispLocShell = c
        d.rfcDispLocGroups = {}
    end

    if not (d.rfcDispelShell or d.rfcDispel) then
        local s = ProxyFor(d)
        if s then
            local dispelStyleKey = StyleKeyFor(d):gsub("debuff", "dispel")
            AK.styles[dispelStyleKey] = AK.styles[dispelStyleKey] or BuildDispelStyle(s)
            local c = AK.CreateContainerShell(button, { point = { "CENTER", health, "CENTER" } })
            for i = 1, #DISPEL_SLOTS do
                local def = DISPEL_SLOTS[i]
                AK.AddSlotToContainer(c, {
                    key = def.key,
                    filter = DispelSlotFilter(s, def.token),
                    candidateFilters = { includeDispelTypes = { [def.token] = true } },
                    style = dispelStyleKey,
                    extraInit = function(slotButton, dd)
                        dd.rfHealth = health
                        dd.rfSlotDef = def
                        -- Anchor inside the creation window: SetPoint on the returned
                        -- slot button is denied while auras are secret (12.1 access
                        -- restriction); shell setup runs on in-instance reloads.
                        slotButton:SetPoint("CENTER", health, "CENTER")
                        ApplyRFDispelSlot(slotButton, dd, AK.styles[dispelStyleKey])
                    end,
                })
            end
            -- NO unit yet: an unbound shell registers no events and parses
            -- nothing. The finish job binds the real unit.
            d.rfcDispelShell = c
            d.rfcTotemGen = rfcTotemGen
        end
    end

    -- BuffManager shells, same early-window rule: slots container, simple-grid
    -- container, and a bare pool shell per current-spec chain indicator. With frames
    -- pre-born, ALL remaining BM work (slot adds, declarations, finishes, retargets)
    -- is combat-legal -- BM binds mid-combat after an in-combat /reload, not regen.
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

-- Debuff phase: group declarations + finish (combat-runnable -- shells exist
-- synchronously from StyleButton, and group declaration on an existing container is
-- combat-legal).
--
-- CLASS AT JOB TIME, NOT QUEUE TIME: the party SELF button carries its unit attribute
-- before StyleButton runs, but party creation stamps d._isParty only after StyleButton
-- returns -- so this phase queues while the button still reads as raid class. Jobs run
-- at least a frame later, so each resolves StyleKeyFor/ProxyFor itself; capturing them
-- at queue time gave the party self frame raid-classed containers.
local function QueueDebuffPhase(button, health, d)
    if not ProxyFor(d) then return end
    for i = 1, #DEBUFF_GROUPS do
        local g = DEBUFF_GROUPS[i]
        AK.QueueBuildJob(function()
            local c = d.rfcDebuffShell
            if not c or d.rfcDebuffGroups[g.key] then return end
            local sNow = ProxyFor(d)
            if not sNow then return end
            -- 12.1 redesign: Debuff Manager owns the debuff row; only the cc group
            -- (its Crowd Control record + glow carrier) is still declared here --
            -- retired preset groups would be permanent parse consumers even parked at 0.
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

    -- BuffManager + finalize: consumes the early-window BM shells (slot adds, group
    -- declarations, finishes -- all combat-legal), so it runs mid-combat too. Only pool
    -- GROWTH beyond the pre-born shells falls back to a queued shell job in BmAcquireChain.
    AK.QueueBuildJob(function()
        d.rfcPending = nil
        d.rfcGroupsPending = nil
        local unit = button:GetAttribute("unit") or "player"
        CreateBmContainer(button, health, d, unit)
        d.rfcUnit = unit
        -- Shells baked the dispel filters from rfcTotemKnown at build time; if a
        -- totem flip landed mid-build, re-apply the current filters before the
        -- fingerprint below is primed as current (which would otherwise latch the
        -- stale filters as already-applied).
        if d.rfcDispel and d.rfcTotemGen ~= rfcTotemGen then
            local parts = DispelSlotFilters(ProxyFor(d) or s)
            for i = 1, #DISPEL_SLOTS do
                d.rfcDispel:SetAuraSlotFilterString(DISPEL_SLOTS[i].key, parts[i])
            end
        end
        d.rfcTotemGen = nil
        -- Everything above was configured from current settings; prime the class
        -- fingerprints so the first reload doesn't re-drive it all (class resolved
        -- here, not at queue time -- party self button).
        PrimeClassFP(StyleKeyFor(d), ProxyFor(d) or s)
        -- Clear state cached while this button was mid-build (unit assignments run
        -- the gate against partial containers): fresh containers need a full
        -- SetShown/range-alpha pass.
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
        local dispelStyleKey = styleKey:gsub("debuff", "dispel")
        AK.styles[dispelStyleKey] = AK.styles[dispelStyleKey] or BuildDispelStyle(s)
    end

    d.rfcHealthRef = health

    -- Shells synchronously, HERE, in the early load window (see CreateButtonShells):
    -- the one moment container creation is safe on every reload path, combat included.
    CreateButtonShells(button, health, d)

    local unit = button:GetAttribute("unit")
    if unit and UnitExists(unit) then
        d.rfcGroupsPending = true
        QueueButtonGroups(button, health, d)
    end
end

-- Cross-faction (or otherwise non-assistable) group members: the engine SILENTLY
-- SKIPS spell-ID candidate filters for helpful auras on non-assistable units, so
-- include-list displays would degrade to "any buff" -- they hide for such units
-- instead (token-only groups -- debuffs, externals, defensives, CC -- are unaffected).
-- Degradation is NOT directly queryable; assist+visible+not-phased still PASSED for
-- degraded units (a released ghost near the group is visible, unphased, assistable
-- via resurrection, yet leaked "any buff"). Hence: connected, alive, assistable,
-- visible, not phased. RANGE is deliberately NOT a disqualifier: aura data streams
-- fine for members merely out of 40yd spell range, and gating on it made buff
-- displays and health-color effects vanish for out-of-range party members (the
-- unit frame's own oorAlpha fade already dims the containers -- they are children
-- of the button). Local player's own flags never degrade EXCEPT in a vehicle:
-- boarding one makes the player unit non-assistable, the engine skips the
-- spell-ID filters, and every include-list container on the player's own frame
-- degrades to "any buff" (field-confirmed: reliable on every vehicle entry).
-- Outside a vehicle self stays exempt from the full probe.
-- Identity APIs can return SECRET booleans under teardown; any secret errors
-- inside the pcall and reads fail-closed.
local function AssistProbe(unit)
    if UnitIsUnit(unit, "player") then
        -- UsingVehicle over InVehicle: it is also true during the boarding and
        -- exiting TRANSITIONS, and the filters already degrade while boarding
        -- (field: a second of "any buff" before the seated state landed).
        local probe = UnitUsingVehicle or UnitInVehicle
        if probe("player") then return false end
        -- Cinematics fire UNIT_FACTION for every unit and briefly make even
        -- the LOCAL PLAYER non-assistable (authors-channel consensus
        -- 2026-08-13) -- the engine drops spell-ID filters for self exactly
        -- like the vehicle case. A CLEANLY-false self-assist hides the
        -- filtered displays for the transition; unreadable answers stay
        -- fail-open (the historical self-exemption).
        local okSelf, canSelf = pcall(UnitCanAssist, "player", "player")
        if okSelf and not (issecretvalue and issecretvalue(canSelf)) and canSelf == false then
            return false
        end
        return true
    end
    if not (UnitIsConnected(unit)
        and not UnitIsDeadOrGhost(unit)
        and UnitCanAssist("player", unit)
        and UnitIsVisible(unit)
        and not UnitPhaseReason(unit)) then
        return false
    end
    return true
end

-- NOTE: the range alpha-slaving lane (containers hard-hidden at alpha 0 for
-- out-of-range units via SetAlphaFromBoolean on the range boolean) was REMOVED
-- 2026-08-12: it made buffs and health-color effects vanish for members merely
-- out of 40yd spell range, while aura data still streams for them. The
-- containers are children of the unit button and inherit its oorAlpha range
-- fade, which is the wanted presentation. Do not re-add a range hide here
-- without fresh evidence of out-of-range filter degradation on the live client.

local function ApplyAssistGate(button, d, unit)
    -- Faction AND phase: the engine's identity gate degrades for members who are
    -- cross-faction (open world) or phased/far away (filter flags haven't streamed;
    -- UnitPhaseReason is the eye-icon signal for that state). While degraded, filter
    -- results are untrustworthy, so filtered helpful displays hide wholesale.
    local assist = false
    if unit then
        local ok, res = pcall(AssistProbe, unit)
        if ok and res then assist = true end
    end
    -- Same state as last applied: every write below is assist-driven, so re-applying
    -- is redundant (settings changes re-drive via reload paths); keeps event-sweep
    -- watchers near-free.
    if d.rfcAssist == assist then return end
    -- Explicit-false only: the login initialization is nil->true and must NOT
    -- take the regain refresh below (a full-group UpdateAllAuras storm on the
    -- login hot path -- the normal build owns first content).
    local wasDenied = d.rfcAssist == false
    d.rfcAssist = assist
    local s = ProxyFor(d)
    if d.rfcDispel and s then
        d.rfcDispel:SetShown(assist and DispelVisible(s))
    end
    if d.rfcBm then d.rfcBm:SetShown(assist) end
    if d.rfcBmChain then
        for _, cc in pairs(d.rfcBmChain) do cc:SetShown(assist) end
    end
    if d.rfcBmSimple then
        -- Simple container PERSISTS, so the gate must be state-aware: coexistence
        -- resolves via the effective base-enabled accessor (shim over the legacy
        -- mode key), never the mode key directly.
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
    -- Regain refresh: content parsed during the degraded window is WRONG
    -- ("any buff"), and no aura edge is guaranteed to follow the transition
    -- back (cinematic end, vehicle exit) -- the display would show stale
    -- degraded content until the unit's next real aura change. Force one
    -- reparse of the filtered containers on the explicit false->true flip
    -- (wasDenied: never the login nil->true initialization). Bounded: runs
    -- only on actual transitions, so a cinematic end costs one pass across
    -- the group and a vehicle exit one button.
    if assist and wasDenied then
        if d.rfcDispel then d.rfcDispel:UpdateAllAuras() end
        if d.rfcBm then d.rfcBm:UpdateAllAuras() end
        if d.rfcBmChain then
            for _, cc in pairs(d.rfcBmChain) do cc:UpdateAllAuras() end
        end
        if d.rfcBmSimple then d.rfcBmSimple:UpdateAllAuras() end
    end
end
ns.RFC_ApplyAssistGate = ApplyAssistGate

-- Called from the OnAttributeChanged("unit") watch when the secure header
-- (re)assigns a button. SetUnit re-registers events; the explicit refresh
-- covers assignments where the new unit's auras produce no UNIT_AURA edge.
function ns.RFC_OnUnitAssigned(button, d, unit)
    -- Two-phase: a button receiving its FIRST unit triggers phase B (group
    -- declarations + BM + finish) -- empty buttons only ever carry phase-A shells.
    -- Mid-combat first assignments (raid joiners) work: group jobs ride the live lane
    -- against the pre-built shells.
    if not d.rfcDebuffs and not d.rfcGroupsPending then
        if d.rfcHealthRef then
            d.rfcGroupsPending = true
            QueueButtonGroups(button, d.rfcHealthRef, d)
        end
        return
    end
    -- The secure header re-sets the SAME unit attribute on every roster re-process.
    -- Containers keep their unit across that and UNIT_AURA drives their content, so a
    -- same-unit re-assignment has nothing to re-drive -- skipping it avoids a raid-wide
    -- UpdateAllAuras storm (full engine reparse of every group/slot on every button).
    -- Assist state can still flip without a unit change; its same-state early-out
    -- keeps that call near-free.
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

    v = DispelStyleFP(s)
    if st.dispelStyle ~= v then
        st.dispelStyle = v
        local dispelStyleKey = styleKey:gsub("debuff", "dispel")
        AK.styles[dispelStyleKey] = BuildDispelStyle(s)
        AK.RestyleSoon(dispelStyleKey)
    end
    local parts = DispelSlotFilters(s)
    local dispelFilter = table.concat(parts, ";")
    if st.dispelFilter ~= dispelFilter then
        st.dispelFilter = dispelFilter
        flags.dispelFilter = parts
    end

    return flags
end

-- Called from the tail of ReloadFrames (party mirror path feeds the same registry).
-- Fingerprint-guarded, so unrelated raid settings cost near-zero. Restriction-lift
-- reconciliation: passes that skipped under aura secrecy left fingerprints unstamped,
-- so one FP-guarded ReloadAll at lift re-drives exactly that work (dirty-flag guarded,
-- so idle lift events cost one test). AK is resolved directly here, not via the
-- lazily-assigned file-scope local (still nil at load time) -- the parent addon is a
-- hard dependency and exists by child load.
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
                -- "Shown on Modifier" motion eaters (frames we own; the DM
                -- file builds/flips them -- see its tooltip-modifier section).
                if ns.DM_TipModEnsure then ns.DM_TipModEnsure(button, d, s) end
                if flags.dispLocCfg then
                    local c2 = d.rfcDispLoc
                    if c2 then
                        AnchorDispLocContainer(c2, d.rfcHealth, s)
                        ApplyDispLocConfig(c2, d, s)
                        c2:SetShown(DispLocActive(s))
                    elseif DispLocActive(s) and not d.rfcDispLocShell and not d.rfcDispLocBuild then
                        -- Split enabled mid-session: containers can't be created in
                        -- combat, so the shell build rides the OOC lane; groups+finish
                        -- follow the normal phase.
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
                if d.rfcDispel then
                    if flags.dispelFilter then
                        for j = 1, #DISPEL_SLOTS do
                            d.rfcDispel:SetAuraSlotFilterString(DISPEL_SLOTS[j].key,
                                flags.dispelFilter[j])
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

-- Indicator-set changes (spec swap, add/remove spell, mode toggle) need a container
-- swap, deferred to out-of-combat. Spec changes swap the whole indicator set, so they
-- re-drive the reload directly (the signature check makes a no-change reload cheap).
local bmRegen = CreateFrame("Frame")
bmRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
bmRegen:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
bmRegen:RegisterEvent("PLAYER_ENTERING_WORLD")
-- The poison dispel-slot filter depends on Poison Cleansing Totem being talented
-- (see DispelSlotFilter). Talent edits fire no spec event, and IsPlayerSpell can
-- lag the trait event itself (the spellbook grant lands with SPELLS_CHANGED), so
-- shamans re-check on both; the reload runs only on an actual flip, and a flip
-- seen in combat latches for the regen branch below.
local function RecheckTotem()
    local known = rfcPlayerClass == "SHAMAN"
        and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
    if known == rfcTotemKnown then ns._rfcTotemDirty = nil; return end
    if InCombatLockdown() then ns._rfcTotemDirty = true; return end
    ns._rfcTotemDirty = nil
    rfcTotemKnown = known
    rfcTotemGen = rfcTotemGen + 1
    -- Stale by construction now: force the next compare to re-apply the slot
    -- filters instead of trusting a fingerprint stamped under the old value.
    for _, st in pairs(classFP) do st.dispelFilter = nil end
    ns.RFC_ReloadAll()
end
if rfcPlayerClass == "SHAMAN" then
    bmRegen:RegisterEvent("TRAIT_CONFIG_UPDATED")
    bmRegen:RegisterEvent("SPELLS_CHANGED")
end
bmRegen:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == "player" and not InCombatLockdown() then ns.RFC_ReloadAll() end
        return
    end
    if event == "TRAIT_CONFIG_UPDATED" or event == "SPELLS_CHANGED" then
        RecheckTotem()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Assistability can flip on zone transitions without a unit
        -- re-assignment (cross-faction members become assistable inside
        -- instances); re-evaluate the gate for every live button.
        AssistSweep()
        return
    end
    if ns._rfcTotemDirty then RecheckTotem() end
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
-- Vehicle occupancy flips assistability for the occupant (the one state where
-- even the local player's own flags degrade -- see AssistProbe). ENTERING as
-- well as ENTERED: degradation starts with the boarding transition.
assistWatch:RegisterEvent("UNIT_ENTERING_VEHICLE")
assistWatch:RegisterEvent("UNIT_ENTERED_VEHICLE")
assistWatch:RegisterEvent("UNIT_EXITED_VEHICLE")
-- Cinematics (in-world cutscenes included) fire UNIT_FACTION for EVERY unit
-- at start and end while assistability flips -- and UNIT_FLAGS does NOT fire
-- for that transition, so without this edge the gate misses it entirely
-- (authors-channel etrace, 2026-08-13). The coalescer below flattens the
-- all-units burst into one sweep. CINEMATIC_STOP joins it for the
-- addon-cancelled skip path (same trigger set as the PAB and UF player
-- lanes); its faction restore usually fires UNIT_FACTION too, this just
-- closes any ordering gap.
assistWatch:RegisterEvent("UNIT_FACTION")
assistWatch:RegisterEvent("CINEMATIC_STOP")
-- Death/release/resurrection transitions (the alive requirement of the probe)
-- signal through UNIT_FLAGS; chatty in combat, but the coalescer below reduces any
-- burst to one deferred sweep.
assistWatch:RegisterEvent("UNIT_FLAGS")
-- Coalesced: UNIT_IN_RANGE_UPDATE fires continuously in a moving raid (every member
-- crossing the range boundary), and each sweep probes three identity APIs per button.
-- One deferred sweep per burst covers every trigger in the window; a quarter-second
-- of latency is invisible on a display-trust gate.
local assistSweepPending = false
local function AssistSweepDrain()
    assistSweepPending = false
    AssistSweep()
end
assistWatch:SetScript("OnEvent", function(_, event)
    -- Vehicle and cinematic-skip edges sweep IMMEDIATELY: they are rare (no
    -- storm to coalesce) and the quarter-second defer reads as a visible
    -- flash of degraded "any buff" content on the player's own frame.
    if event == "UNIT_ENTERING_VEHICLE"
        or event == "UNIT_ENTERED_VEHICLE"
        or event == "UNIT_EXITED_VEHICLE"
        or event == "CINEMATIC_STOP" then
        AssistSweep()
        return
    end
    if assistSweepPending then return end
    assistSweepPending = true
    C_Timer.After(0.25, AssistSweepDrain)
end)
