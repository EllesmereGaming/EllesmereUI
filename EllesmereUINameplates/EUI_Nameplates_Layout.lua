if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Layout.lua
--
--  Setting getters (offsets, sizes, scales, slots, borders, class power
--  options), the glow aliases, the dispel glow and aura slot positioning.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs, type = ipairs, type
local PP = EllesmereUI.PP
-- The core's table of the options page frame pool (EllesmereUI_PixelPerfect.lua
-- makes it, the options addon fills it): the builders the options preview shares
-- with the plates create through it, so a preview frame is handed back to the
-- preview's next build. A plate's parent is no pool host: a plain CreateFrame.
local Pool = EllesmereUI._Pool
local UnitIsPlayer = UnitIsPlayer
local GetTime = GetTime

local BAR_W, defaults = I.BAR_W, I.defaults

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

local function GetNameplateYOffset()
    return (p and p.nameplateYOffset) or defaults.nameplateYOffset
end
ns.GetNameplateYOffset = GetNameplateYOffset
local function GetStackSpacingScale()
    return (p and p.stackSpacingScale) or defaults.stackSpacingScale
end
ns.GetStackSpacingScale = GetStackSpacingScale
local function GetCastScale()
    return (p and p.castScale) or defaults.castScale
end
ns.GetCastScale = GetCastScale
local function GetTargetScale()
    return (p and p.targetScale) or defaults.targetScale
end
ns.GetTargetScale = GetTargetScale
local function GetHealthBarHeight()
    return (p and p.healthBarHeight) or defaults.healthBarHeight
end
ns.GetHealthBarHeight = GetHealthBarHeight
local function GetFriendlyHealthBarHeight()
    return (p and p.friendlyHealthBarHeight) or defaults.friendlyHealthBarHeight
end
ns.GetFriendlyHealthBarHeight = GetFriendlyHealthBarHeight
local function GetFriendlyHealthBarWidth()
    return (p and p.friendlyHealthBarWidth) or defaults.friendlyHealthBarWidth
end
ns.GetFriendlyHealthBarWidth = GetFriendlyHealthBarWidth
local function GetEnemyNameTextSize()
    -- Returns the font size of the top text slot (used for stacking gap calculations)
    return (p and p.textSlotTopSize) or defaults.textSlotTopSize or 10
end
ns.GetEnemyNameTextSize = GetEnemyNameTextSize
local function GetDebuffTextColor()
    local c = (p and p.debuffTimerColor) or defaults.debuffTimerColor
    return c.r, c.g, c.b, 1
end
ns.GetDebuffTextColor = GetDebuffTextColor

-- Nameplate glow styles (Pandemic, Dispel, Important Cast) in their saved
-- order: a view over the shared styles without Shape Glow (1 Pixel, 2 Action
-- Button, 3 Auto-Cast, 4 GCD, 5 Modern, 6 Classic). scale/previewScale are
-- nameplate preview-only fields layered over the shared entries.
ns.NP_GLOW_VIEW = EllesmereUI.Glows.MakeView({ 1, 2, 3, 5, 6, 7 }, {
    [2] = { scale = 1.36, previewScale = 1.28 },
    [4] = { scale = 1.47, previewScale = 1.47 },
    [5] = { scale = 1.34, previewScale = 1.34 },
    [6] = { scale = 1.47, previewScale = 1.47 },
})
local PANDEMIC_GLOW_STYLES = ns.NP_GLOW_VIEW.list
ns.PANDEMIC_GLOW_STYLES = PANDEMIC_GLOW_STYLES
-- Exposed cross-addon (e.g. CDM "Apply Pandemic Glow to all" sync) so styles translate by NAME,
-- never raw index: this list omits "Custom Shape Glow", so the same index differs per side.
if EllesmereUI then EllesmereUI.NameplatePandemicGlowStyles = PANDEMIC_GLOW_STYLES end

-- PANDEMIC_GLOW_STYLES index -> shared EllesmereUI.Glows.STYLES index.
ns.NP_TO_SHARED_GLOW = ns.NP_GLOW_VIEW.toShared

-- Pandemic Glow style of a nameplate profile. A style picked from 9.6 on is
-- pandemicGlowPick. Without one, the key from before 9.6 is read as a view:
-- its old default (Pixel, 1) and nil mean Blizzard Pandemic Border, any other
-- value is that pick (stored profiles and old profile strings can hold the old
-- default written out, and must keep the border). Cross-addon for the CDM
-- "Apply Pandemic Glow to all" sync.
local function PandemicStyleOf(np)
    local pick = np and np.pandemicGlowPick
    if type(pick) == "number" then return pick end
    local old = np and np.pandemicGlowStyle
    if type(old) ~= "number" or old == 1 then return EllesmereUI.Glows.PANDEMIC_BORDER end
    return old
end
EllesmereUI.NameplatePandemicStyle = PandemicStyleOf
local function GetPandemicGlowStyle()
    return PandemicStyleOf(p)
end
ns.GetPandemicGlowStyle = GetPandemicGlowStyle
local function GetPandemicGlowLines()
    return (p and p.pandemicGlowLines) or defaults.pandemicGlowLines
end
ns.GetPandemicGlowLines = GetPandemicGlowLines
local function GetPandemicGlowThickness()
    return (p and p.pandemicGlowThickness) or defaults.pandemicGlowThickness
end
ns.GetPandemicGlowThickness = GetPandemicGlowThickness
local function GetPandemicGlowSpeed()
    return (p and p.pandemicGlowSpeed) or defaults.pandemicGlowSpeed
end
ns.GetPandemicGlowSpeed = GetPandemicGlowSpeed
function ns.GetPandemicGlow()
    local v = p and p.pandemicGlow
    if v == nil then v = defaults.pandemicGlow end
    return v == true
end
-- Full render spec for the pandemic glow (live debuff glow and its preview).
-- An unset color mode is Custom: the swatch color this glow always drew.
-- Blizzard Pandemic Border (EllesmereUI.Glows.PANDEMIC_BORDER) sits outside
-- the view and is always drawn untinted.
function ns.GetPandemicGlowSpec(out)
    out = out or {}
    local idx = GetPandemicGlowStyle()
    if idx == EllesmereUI.Glows.PANDEMIC_BORDER then
        out.style = idx
        out.r, out.g, out.b = nil, nil, nil
    else
        out.style = ns.NP_TO_SHARED_GLOW[idx] or 1
        local c = (p and p.pandemicGlowColor) or defaults.pandemicGlowColor
        out.r, out.g, out.b = EllesmereUI.Glows.ResolveColor((p and p.pandemicGlowMode) or "custom", c.r, c.g, c.b)
    end
    out.lines = GetPandemicGlowLines()
    out.thickness = GetPandemicGlowThickness()
    out.speed = GetPandemicGlowSpeed()
    local bgc = (p and p.pandemicGlowBackgroundColor) or defaults.pandemicGlowBackgroundColor
    out.bg = (p and p.pandemicGlowBackground == true) or nil
    out.bgR, out.bgG, out.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
    return out
end

-- Offensive dispel capability: the shared parent detector (AuraKit), which
-- asks what the PLAYER knows, never what an aura is, so it keeps working in
-- restricted content.
do
    local AKd = EllesmereUI.AuraKit
    -- Capability picks the buff row's candidate filter, so a change has to
    -- rebuild the containers, not merely repaint them.
    AKd.OnOffensiveDispelChange(function()
        if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
    end)

    -- canDispelMagic, canDispelEnrage. Consumed by the buff row to pick its
    -- candidate filter and by the glow gate.
    ns.GetOffensiveDispelTypes = function()
        return AKd.OffensiveDispelTypes()
    end

    ns.GetDispelGlow = function()
        return (p and p.dispelGlow) or defaults.dispelGlow
    end
    ns.GetDispelGlowStyle = function()
        -- The same view as the Pandemic Glow's: dispelGlowPick holds a style
        -- picked from 9.6 on; without one, the key from before 9.6 with its
        -- old default (Action Button Glow, 2) or nil means Blizzard Pandemic
        -- Border, and any other value is that pick.
        local raw = p and p.dispelGlowPick
        if raw == nil then
            raw = p and p.dispelGlowStyle
            if raw == nil or raw == 2 then return EllesmereUI.Glows.PANDEMIC_BORDER end
        end
        -- Out-of-range picks read (and render) as Action Button Glow; Blizzard
        -- Border and Blizzard Pandemic Border sit outside the view.
        if type(raw) == "number" and (raw == EllesmereUI.Glows.STEALABLE_BORDER
           or raw == EllesmereUI.Glows.PANDEMIC_BORDER
           or (raw >= 1 and raw <= #ns.NP_GLOW_VIEW.list)) then
            return raw
        end
        return 2
    end
    -- Per-type colors. The buff row is split into a Magic group and a
    -- non-Magic (enrage) group, so the type is a property of the GROUP and
    -- resolves once at style-build time -- no per-aura read, which is what
    -- made the old ColorMixin-per-aura version impossible under 12.1.
    local TYPE_COLOR = {
        magic  = { r = 0.2, g = 0.6, b = 1.0 },
        enrage = { r = 1.0, g = 0.2, b = 0.2 },
    }
    function ns.GetDispelGlowUseTypeColor()
        local v = p and p.dispelGlowUseTypeColor
        if v == nil then v = defaults.dispelGlowUseTypeColor end
        return v == true
    end
    -- dispelType is "magic", "enrage", or nil for the undifferentiated row.
    ns.GetDispelGlowColor = function(dispelType)
        if dispelType and ns.GetDispelGlowUseTypeColor() then
            local c = TYPE_COLOR[dispelType]
            if c then return c.r, c.g, c.b end
        end
        -- Never customized = "default": no tint request (nil), the suite's
        -- default look (gold). An explicit swatch pick is stored and honored.
        local c = p and p.dispelGlowColor
        local mode = (p and p.dispelGlowColorMode) or (c and "custom" or "default")
        return EllesmereUI.Glows.ResolveColor(mode, c and c.r, c and c.g, c and c.b)
    end
    -- Full render spec for the dispel glow (live purge glow and its preview).
    ns.GetDispelGlowSpec = function(dispelType, out)
        out = out or {}
        local idx = ns.GetDispelGlowStyle()
        -- Blizzard Border sits outside the view and keeps Blizzard's own art
        -- until a colour is picked (ns.GetDispelBorderColor); Blizzard
        -- Pandemic Border is always drawn untinted.
        if idx == EllesmereUI.Glows.STEALABLE_BORDER then
            out.style = idx
            out.r, out.g, out.b = ns.GetDispelBorderColor(dispelType)
        elseif idx == EllesmereUI.Glows.PANDEMIC_BORDER then
            out.style = idx
            out.r, out.g, out.b = nil, nil, nil
        else
            out.style = ns.NP_TO_SHARED_GLOW[idx] or 2
            out.r, out.g, out.b = ns.GetDispelGlowColor(dispelType)
        end
        out.lines = p and p.dispelGlowLines
        out.thickness = p and p.dispelGlowThickness
        out.speed = p and p.dispelGlowSpeed
        local bgc = p and p.dispelGlowBackgroundColor
        out.bg = (p and p.dispelGlowBackground == true) or nil
        out.bgR, out.bgG, out.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
        return out
    end
    -- Blizzard Border tint: the glow colour, except the untouched default gold
    -- (the profile merge fills the key, so it is compared, not nil-tested)
    -- keeps Blizzard's own stealable art. Per-type colours always tint.
    ns.GetDispelBorderColor = function(dispelType)
        local r, g, b = ns.GetDispelGlowColor(dispelType)
        if dispelType and ns.GetDispelGlowUseTypeColor() then return r, g, b end
        local d = defaults.dispelGlowColor
        if r == nil or (d and r == d.r and g == d.g and b == d.b) then return nil, nil, nil end
        return r, g, b
    end
end
local function GetCastBarHeight()
    return (p and p.castBarHeight) or defaults.castBarHeight
end
ns.GetCastBarHeight = GetCastBarHeight
local function GetFocusCastHeight()
    return (p and p.focusCastHeight) or defaults.focusCastHeight
end
ns.GetFocusCastHeight = GetFocusCastHeight
local function GetShowCastIcon()
    if p and p.showCastIcon ~= nil then return p.showCastIcon end
    return defaults.showCastIcon
end
ns.GetShowCastIcon = GetShowCastIcon
local function GetCastIconScale()
    return (p and p.castIconScale) or defaults.castIconScale
end
ns.GetCastIconScale = GetCastIconScale
-- "Make Icon Part of the Bar": bar shifts right and narrows by the icon width so the icon
-- (anchored to the bar's left edge) sits inside the footprint instead of hanging off it.
function ns.GetCastIconInWidth()
    if p and p.castbarIconInWidth ~= nil then return p.castbarIconInWidth end
    return defaults.castbarIconInWidth
end
-- "Icon on Right": place the cast spell icon on the right of the bars.
function ns.GetCastIconOnRight()
    if p and p.castIconOnRight ~= nil then return p.castIconOnRight end
    return defaults.castIconOnRight
end
-- "Full Sized": icon is a square the combined height of the health + cast bar,
-- flush from the top of the health bar to the bottom of the cast bar.
function ns.GetCastIconFullSize()
    if p and p.castIconFullSize ~= nil then return p.castIconFullSize end
    return defaults.castIconFullSize
end
local function GetHideEnemyNameWhileCasting()
    if p and p.hideEnemyNameWhileCasting ~= nil then return p.hideEnemyNameWhileCasting end
    return defaults.hideEnemyNameWhileCasting
end

-- Position + size the cast bar within `footprintW` per the icon-in-width setting. A full-size
-- icon spans the health band too (which the cast bar cannot reserve), so in-width applies only
-- at normal size. Left icon: shift bar right into the reserved gap; right icon: fix left edge,
-- narrow only the right. iconW = castH * icon scale (rendered size).
function ns.LayoutCastBar(plate, footprintW, castH)
    local iconW = 0
    local shiftX = 0
    local w = footprintW
    local classic = ns.NP_Classic()
    -- Cast Bar Y Offset: + up, - down; `or` fallback only fires when nil (0 is truthy in Lua).
    local offsetY = (p and p.castBarOffsetY) or defaults.castBarOffsetY
    if classic then
        -- Classic WoW UI: the vanilla cast border hangs under the health
        -- border with its icon plate under the health border's plain end,
        -- so the bar shifts right by the two plates' difference, keeps the
        -- footprint (widened by that difference when the bars' heights
        -- differ) and sits the stock gap lower; the icon rides in the plate.
        local drop
        shiftX, w, drop = ns.NP_ClassicCastLayout(footprintW, GetHealthBarHeight(), castH)
        offsetY = offsetY + drop
    elseif GetShowCastIcon() and ns.GetCastIconInWidth() and not ns.GetCastIconFullSize() then
        iconW = castH * (GetCastIconScale() or 1)
        if not ns.GetCastIconOnRight() then
            shiftX = iconW
        end
    end
    plate.cast:ClearAllPoints()
    plate.cast:SetSize(math.max(1, w - iconW), castH)
    -- Snap to whole physical pixels at the plate's own scale (nameplates have their own scale
    -- stack, not UIParent's) so the health-bottom/cast-top gap stays constant instead of
    -- oscillating +/-1px as the plate slides to fractional screen positions.
    if offsetY ~= 0 and PP then
        local plateES = plate:GetEffectiveScale()
        local onePx = (plateES and plateES > 0) and (PP.perfect / plateES) or (PP.mult or 1)
        offsetY = math.floor(offsetY / onePx + 0.5) * onePx
    end
    plate.cast:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", shiftX, offsetY)
    -- The cast bar's bottom edge below the health bar's: the bottom text slots
    -- drop by this while a cast shows (PlaceSlotText). Clamped at 0, so a cast
    -- bar raised above the health bar never lifts them.
    plate._castDrop = math.min(0, offsetY - castH)
    if ns._npBottomUsed and plate.AnchorBottomTexts and plate.cast:IsShown() then
        plate:AnchorBottomTexts()
    end
    if classic then ns.NP_ApplyClassicCastArt(plate, castH) end
end

-- Size + anchor the cast spell icon; always square. Normal: cast-bar height, hangs off the
-- bar's left (default) or right edge, top-aligned, scaled by Scale. Full: a (healthH + castH)
-- square anchored to a cast BOTTOM corner (top flush with health top) with scale forced to 1
-- to stay flush to both edges. Frame level fixed at creation (health+1), never touched here.
function ns.LayoutCastIcon(plate, castH)
    local icon = plate.castIconFrame
    local onRight = ns.GetCastIconOnRight()
    local xOff = (p and p.castIconOffsetX) or defaults.castIconOffsetX
    local yOff = (p and p.castIconOffsetY) or defaults.castIconOffsetY
    icon:ClearAllPoints()
    if ns.NP_Classic() then
        -- Classic WoW UI: the icon in the vanilla cast border's plate, a
        -- fixed square at the plate's centre (the border's middle sits half
        -- a sheet row under the bar's); the offsets still nudge it.
        local C = ns.NP_CLASSIC
        local ix, iy = ns.NP_ClassicIconOffset(castH)
        icon:SetScale(1)
        icon:SetSize(C.icon * castH, C.icon * castH)
        icon:SetPoint("CENTER", plate.cast, "LEFT", ix + xOff, iy + yOff)
        return
    end
    if ns.GetCastIconFullSize() then
        local side = GetHealthBarHeight() + castH
        icon:SetScale(1)
        -- Link the icon's three shared edges DIRECTLY to the bar edges (top=health top,
        -- bottom=cast bottom, inner side=bars' outer edge) instead of deriving from its own
        -- size: anchored to the same points the health/cast borders use, they pixel-snap
        -- together and shift as ONE unit instead of rounding independently. SetWidth keeps it
        -- square (height is fixed by the top/bottom anchors = side).
        icon:SetWidth(side)
        if onRight then
            icon:SetPoint("TOPLEFT", plate.health, "TOPRIGHT", xOff, yOff)
            icon:SetPoint("BOTTOMLEFT", plate.cast, "BOTTOMRIGHT", xOff, yOff)
        else
            icon:SetPoint("TOPRIGHT", plate.health, "TOPLEFT", xOff, yOff)
            icon:SetPoint("BOTTOMRIGHT", plate.cast, "BOTTOMLEFT", xOff, yOff)
        end
    else
        icon:SetScale(GetCastIconScale() or 1)
        icon:SetSize(castH, castH)
        if onRight then
            icon:SetPoint("TOPLEFT", plate.cast, "TOPRIGHT", xOff, yOff)
        else
            icon:SetPoint("TOPRIGHT", plate.cast, "TOPLEFT", xOff, yOff)
        end
    end
end

-- How far the cast icon protrudes past the bar edge, plus that side ("left"/"right"). The
-- target arrows and the side-slot elements step out by it (ns.NP_SideIconPush,
-- ns.NP_FullIconPush) so they never land under the icon. Returns
-- 0 for left/normal and in-width-tucked icons. Optional `plate` matters only for the full-size
-- icon (a cast-bar child rendered only during a cast): its reserve is gated on the cast bar
-- being shown; a settings-only query (no plate) assumes the space is reserved.
function ns.GetCastIconReserve(plate)
    if not GetShowCastIcon() then return 0, nil end
    -- Classic WoW UI seats the icon inside the cast border's own plate, which
    -- ns.NP_ClassicBarReserve already accounts for, so a stored Icon on Right
    -- or Full Sized reserves a gap nothing occupies there.
    if ns.NP_Classic() then return 0, nil end
    local onRight = ns.GetCastIconOnRight()
    local side = onRight and "right" or "left"
    if ns.GetCastIconFullSize() then
        -- Reserve the full-size icon's footprint only while visible (cast bar up), so side
        -- elements sit flush against the bar when idle instead of shoved out by a phantom gap.
        if plate and plate.cast and not plate.cast:IsShown() then
            return 0, side
        end
        return GetHealthBarHeight() + GetCastBarHeight(), side
    end
    if onRight and not ns.GetCastIconInWidth() then
        return GetCastBarHeight() * (GetCastIconScale() or 1), side
    end
    return 0, side
end

-- Whether an element beside the bars meets the full-size cast icon. The element spans y0..y1
-- above the health bar's bottom; the icon runs from the health bar's top (barH) down to the
-- cast bar's bottom (castBottom, from the health bar's bottom), both moved by its Y offset.
-- The options preview passes its own bar measures.
function ns.NP_MeetsFullIcon(y0, y1, barH, castBottom)
    local iy = (p and p.castIconOffsetY) or defaults.castIconOffsetY or 0
    return y0 < barH + iy and castBottom + iy < y1
end

-- The full-size cast icon's push on `side` for an element spanning y0..y1 above the health
-- bar's bottom: the icon's width while it shows there (a cast is up) and the two meet, else 0,
-- so an element its slot's Y offset moved clear of the icon stays put.
function ns.NP_FullIconPush(plate, side, y0, y1)
    if not ns.GetCastIconFullSize() then return 0 end
    local res, iconSide = ns.GetCastIconReserve(plate)
    if res <= 0 or iconSide ~= side then return 0 end
    if ns.NP_MeetsFullIcon(y0, y1, GetHealthBarHeight(), plate._castDrop or -GetCastBarHeight()) then
        return res
    end
    return 0
end

-- How far an icon in a side slot (raid marker, classification, faction; the target arrows
-- too) steps out on `side`. It centres on the bar plus y and is sz tall. The normal-size cast
-- icon's reserve always applies, the full-size icon's only where the two meet; plus Classic
-- WoW UI's border reach or WoW Forever's level box (ns.NP_ClassicSide).
function ns.NP_SideIconPush(plate, side, y, sz)
    local push
    if ns.GetCastIconFullSize() then
        local mid = GetHealthBarHeight() / 2 + y
        push = ns.NP_FullIconPush(plate, side, mid - sz / 2, mid + sz / 2)
    else
        local res, iconSide = ns.GetCastIconReserve(plate)
        push = (iconSide == side) and res or 0
    end
    return push + ns.NP_ClassicSide(side)
end
local function GetKickTickEnabled()
    if p and p.kickTickEnabled ~= nil then return p.kickTickEnabled end
    return true
end
ns.GetKickTickEnabled = GetKickTickEnabled
local function GetKickTickColor()
    local c = (p and p.kickTickColor) or defaults.kickTickColor
    return c.r, c.g, c.b
end
ns.GetKickTickColor = GetKickTickColor
-- Optional element ("debuffs", "buffs", "ccs") selects per-element spacing; no arg
-- falls back to the global auraSpacing. One function, not two locals (200-local cap).
local function GetAuraSpacing(element)
    if element == "debuffs" then
        return (p and p.debuffSpacing) or defaults.debuffSpacing
    elseif element == "buffs" then
        return (p and p.buffSpacing) or defaults.buffSpacing
    elseif element == "ccs" then
        return (p and p.ccSpacing) or defaults.ccSpacing
    end
    return (p and p.auraSpacing) or defaults.auraSpacing
end
ns.GetAuraSpacing = GetAuraSpacing
local function GetDebuffYOffset()
    return (p and p.debuffYOffset) or defaults.debuffYOffset
end
ns.GetDebuffYOffset = GetDebuffYOffset
local function GetSideAuraXOffset()
    return (p and p.sideAuraXOffset) or defaults.sideAuraXOffset
end
ns.GetSideAuraXOffset = GetSideAuraXOffset
local function GetRaidMarkerPos()
    return (p and p.raidMarkerPos) or defaults.raidMarkerPos
end
ns.GetRaidMarkerPos = GetRaidMarkerPos
local function GetRaidMarkerSize()
    local pos = (p and p.raidMarkerPos) or defaults.raidMarkerPos
    if pos == "none" then return defaults.raidMarkerSize or 24 end
    return (p and p[pos .. "SlotSize"]) or defaults[pos .. "SlotSize"] or 24
end
ns.GetRaidMarkerSize = GetRaidMarkerSize
local function GetRaidMarkerYOffset()
    return 0
end
ns.GetRaidMarkerYOffset = GetRaidMarkerYOffset
local function GetClassificationSlot()
    return (p and p.classificationSlot) or defaults.classificationSlot
end
ns.GetClassificationSlot = GetClassificationSlot
local function GetRareEliteIconSize()
    local pos = (p and p.classificationSlot) or defaults.classificationSlot
    if pos == "none" then return defaults.rareEliteIconSize or 20 end
    return (p and p[pos .. "SlotSize"]) or defaults[pos .. "SlotSize"] or 20
end
ns.GetRareEliteIconSize = GetRareEliteIconSize
-- Faction badge slot and size (same per-slot size as every Core Positions element).
-- With "Rare/Quest + Faction" the badge rides the classification slot.
function ns.NP_GetFactionSlot()
    if p and p.classificationIncludeFaction then return GetClassificationSlot() end
    return (p and p.factionSlot) or defaults.factionSlot
end
function ns.NP_GetFactionIconSize()
    local pos = ns.NP_GetFactionSlot()
    if pos == "none" then return 20 end
    return (p and p[pos .. "SlotSize"]) or defaults[pos .. "SlotSize"] or 20
end
function ns.NP_GetFactionStyle()
    return (p and p.factionStyle) or defaults.factionStyle
end
-- Which faction badge a unit gets: its faction ("Horde"/"Alliance", drawn with
-- EllesmereUI.SetFactionArt in the Icon Style) and whether to dim it, or nil for none.
-- Neutral units and unreadable (secret) values show nothing; an unreadable PvP flag
-- counts as flagged, so nothing is hidden or greyed on a guess. Faction NPCs count
-- unless Players Only is on. Art matches Blizzard's Forever target frame badge.
function ns.NP_FactionBadge(unit)
    if not unit or ns.NP_GetFactionSlot() == "none" then return nil end
    -- Both toggles default off, so an unset key reads the same as its default.
    if p and p.factionPlayersOnly then
        local isPlayer = UnitIsPlayer(unit)
        if issecretvalue(isPlayer) or not isPlayer then return nil end
    end
    local fac = UnitFactionGroup(unit)
    if issecretvalue(fac) or (fac ~= "Horde" and fac ~= "Alliance") then return nil end
    if p and p.factionOppositeOnly then
        local mine = UnitFactionGroup("player")
        if issecretvalue(mine) then return nil end
        -- Mercenary mode: the player fights for the other faction.
        if UnitIsMercenary("player") then
            if mine == "Horde" then mine = "Alliance" elseif mine == "Alliance" then mine = "Horde" end
        end
        if mine == fac then return nil end
    end
    local dim = false
    local pvpMode = (p and p.factionPvP) or defaults.factionPvP
    if pvpMode ~= "ignore" then
        local pvp = UnitIsPVP(unit)
        local unflagged = not issecretvalue(pvp) and not pvp
        if unflagged and pvpMode == "only" then return nil end
        dim = unflagged and pvpMode == "dim"
    end
    return fac, dim
end
local function GetNameYOffset()
    return (p and p.nameYOffset) or defaults.nameYOffset
end
ns.GetNameYOffset = GetNameYOffset
local textSlotKeys = { "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter",
    "textSlotBottomLeft", "textSlotBottomRight" }
ns.textSlotKeys = textSlotKeys
-- The slots that share the bar's line for the name-width estimate.
ns._npBarTextKeys = { "textSlotRight", "textSlotLeft", "textSlotCenter" }

local function GetTextSlot(slotKey)
    return (p and p[slotKey]) or defaults[slotKey]
end
ns.GetTextSlot = GetTextSlot

local function FindSlotForElement(element)
    for _, key in ipairs(textSlotKeys) do
        if GetTextSlot(key) == element then return key end
    end
    return nil
end
ns.FindSlotForElement = FindSlotForElement

-- The four combined health-text elements (percent + number, either order, "|" or "-"
-- separator). One set so every eligibility check treating them as one category stays in sync.
local COMBO_HEALTH_ELEMENTS = {
    healthPctNum     = true, healthNumPct     = true,
    healthPctNumDash = true, healthNumPctDash = true,
    healthNumMax     = true,  -- current / max number; no percent
}
local function IsComboHealthText(element)
    return COMBO_HEALTH_ELEMENTS[element] == true
end
ns.IsComboHealthText = IsComboHealthText

local function SetCombinedHealthText(fs, element, pctText, numText, maxText)
    if element == "healthNumMax" then
        fs:SetFormattedText("%s / %s", numText, maxText or "")
    elseif element == "healthPctNum" then
        fs:SetFormattedText("%s | %s", pctText, numText)
    elseif element == "healthNumPct" then
        fs:SetFormattedText("%s | %s", numText, pctText)
    elseif element == "healthPctNumDash" then
        fs:SetFormattedText("%s - %s", pctText, numText)
    elseif element == "healthNumPctDash" then
        fs:SetFormattedText("%s - %s", numText, pctText)
    else
        fs:SetText("")
    end
end
ns.SetCombinedHealthText = SetCombinedHealthText

-- Name-family text elements: display variants rendered by the plate's single name FontString
-- (enemy name and level+name combos). Exactly one may occupy a slot at a time (enforced by the
-- options-side slot assignment). STANDALONE level is deliberately NOT in the family: it renders
-- on its own FontString (plate.levelText, via health-text slot machinery) so name and level can
-- occupy different slots. do/end + ns funcs: no new locals (cap).
do
    local NAME_FAMILY = {
        enemyName = true, levelName = true, nameLevel = true,
    }
    -- Per slot: its Text Coloring key names (prebuilt, so reads build no strings) and
    -- the materialized Level | Name / Name | Level format strings (NP_RefreshSlotNameParts).
    local SK, PARTS = {}, {}
    local PLAIN = { ln = "%s | %s", nl = "%s | %s", diff = false }
    for i = 1, #textSlotKeys do
        local s = textSlotKeys[i]
        SK[s] = {
            mode = s .. "ColorMode", class = s .. "ClassColor", color = s .. "Color",
            nameOn = s .. "NameColorOn", name = s .. "NameColor",
            lvlOn = s .. "LevelColorOn", lvl = s .. "LevelColor", diff = s .. "LevelDiffOn",
        }
        PARTS[s] = { ln = PLAIN.ln, nl = PLAIN.nl, diff = false }
    end
    function ns.IsNameElement(element)
        return NAME_FAMILY[element] == true
    end
    -- Slot currently holding a name-family element (nil when none is slotted).
    -- db: a profile to read instead of the live one.
    function ns.FindNameSlot(db)
        db = db or p
        for _, key in ipairs(textSlotKeys) do
            if NAME_FAMILY[(db and db[key]) or defaults[key]] then return key end
        end
        return nil
    end
    -- A slot's Core Text Coloring mode: "custom" (the slot colour),
    -- "class" (Hostility / Class, painted per unit) or "level" (Level Difficulty, the
    -- unit's level difficulty colour; any text but Target of Target, which names
    -- another unit). An unset <slot>ColorMode is derived from keys read
    -- here and never written: levelDifficultyColor makes a standalone level "level";
    -- <slot>ClassColor, or enemyNameTextReactionColor on the first name slot, makes
    -- "class". The one place modes are derived. db: a profile to read instead of the
    -- live one.
    function ns.NP_SlotColorMode(slotKey, db)
        db = db or p or defaults
        local k = SK[slotKey]
        if not k then return "custom" end
        local el = db[slotKey] or defaults[slotKey]
        local m = db[k.mode]
        if m == "class" or m == "custom" then return m end
        if m == "level" then return (el ~= "targetOfTarget") and "level" or "custom" end
        if el == "level" and db.levelDifficultyColor == true then return "level" end
        if db[k.class] == true then return "class" end
        if db.enemyNameTextReactionColor == true and NAME_FAMILY[el]
            and ns.FindNameSlot(db) == slotKey then
            return "class"
        end
        return "custom"
    end
    -- Level | Name / Name | Level: the level part in the difficulty colour (applies
    -- while the slot's mode is not "level"). A custom level colour turns it off; unset
    -- follows levelDifficultyColor.
    function ns.NP_SlotLevelDiff(slotKey, db)
        db = db or p or defaults
        local k = SK[slotKey]
        if not k then return false end
        if db[k.lvlOn] == true then return false end
        local v = db[k.diff]
        if v ~= nil then return v == true end
        return db.levelDifficultyColor == true
    end
    -- A combo part's stored colour (part "name" or "level"), falling back to the slot
    -- colour; r, g, b. Whether it applies is <slot>NameColorOn / <slot>LevelColorOn.
    function ns.NP_SlotPartColor(slotKey, part, db)
        db = db or p or defaults
        local k = SK[slotKey]
        if not k then return 1, 1, 1 end
        local c = db[part == "level" and k.lvl or k.name] or db[k.color] or defaults[k.color]
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end
    -- Materializes every slot's combo format strings: a part with a custom colour is
    -- wrapped in its escape inside the format (the name stays a %s argument), and diff
    -- marks a level part drawn in the difficulty colour. Run by NP_RefreshSlotClassFlags.
    function ns.NP_RefreshSlotNameParts()
        local db = p or defaults
        for i = 1, #textSlotKeys do
            local s = textSlotKeys[i]
            local k, f = SK[s], PARTS[s]
            local nm, lv = "%s", "%s"
            if db[k.nameOn] == true then
                nm = EllesmereUI.HexColor(ns.NP_SlotPartColor(s, "name", db)) .. "%s|r"
            end
            if db[k.lvlOn] == true then
                lv = EllesmereUI.HexColor(ns.NP_SlotPartColor(s, "level", db)) .. "%s|r"
            end
            f.ln = lv .. " | " .. nm
            f.nl = nm .. " | " .. lv
            f.diff = ns.NP_SlotColorMode(s, db) ~= "level" and ns.NP_SlotLevelDiff(s, db)
        end
    end
    -- r, g, b for a readable level: the skull's colour below 0, else the difficulty
    -- colour (nil when attackability or the player's level is secret). "player" is the
    -- options preview's stand-in mob, ranked as attackable like a hostile mob.
    local function LevelRGB(unit, lvl)
        if lvl < 0 then return EllesmereUI.GetLevelDifficultyColor(-1) end
        return EllesmereUI.GetLevelColor(unit, lvl,
            unit == "player" or (p and p.levelDifficultyColorFriendly))
    end
    -- The unit's level difficulty colour, r, g, b; nil while its level cannot be read.
    function ns.NP_UnitLevelColor(unit)
        local lvl = UnitEffectiveLevel(unit)
        if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl)) then return nil end
        return LevelRGB(unit, lvl)
    end
    -- Display string for the unit's EFFECTIVE level (so scaling/Chromie time read as the game
    -- ranks them). "??" for skull-ranked (-1) or unreadable (secret) levels, matching default UI.
    -- color "diff" wraps it in the difficulty colour (an unreadable level stays a plain
    -- "??"); any other value returns it plain.
    function ns.GetUnitLevelText(unit, color)
        local lvl = UnitEffectiveLevel(unit)
        if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl)) then
            return "??"
        end
        local txt = lvl < 0 and "??" or tostring(lvl)
        if color == "diff" then return EllesmereUI.ColorText(txt, LevelRGB(unit, lvl)) end
        return txt
    end
    -- Write a name-family element's text into a FontString (shared by runtime update and
    -- options preview). name may be SECRET: only ever passed as a %s display arg, never inspected.
    -- slotKey (nil = FindNameSlot's) picks the combo's materialized part colours; the rest
    -- of the text keeps the font string's colour.
    function ns.SetNameElementText(fs, element, name, unit, slotKey)
        if element == "levelName" or element == "nameLevel" then
            local f = PARTS[slotKey or ns.FindNameSlot()] or PLAIN
            local lvl = ns.GetUnitLevelText(unit, f.diff and "diff")
            if element == "levelName" then
                fs:SetFormattedText(f.ln, lvl, name)
            else
                fs:SetFormattedText(f.nl, name, lvl)
            end
        elseif element == "level" then
            fs:SetFormattedText("%s", ns.GetUnitLevelText(unit))
        else
            fs:SetText(name)
        end
    end
    -- Name Format (text-slot cog): one word, initials or a Character Count;
    -- unset shows the name whole. Keys are prebuilt; the split and its cache
    -- live in EllesmereUI.ShortName.
    do
        local NAME_FORMAT_KEYS = {
            textSlotTop  = "textSlotTopNameFormat",  textSlotRight  = "textSlotRightNameFormat",
            textSlotLeft = "textSlotLeftNameFormat", textSlotCenter = "textSlotCenterNameFormat",
            textSlotBottomLeft  = "textSlotBottomLeftNameFormat",
            textSlotBottomRight = "textSlotBottomRightNameFormat",
        }
        local short = EllesmereUI.ShortName
        function ns.NP_FormatName(name, slotKey)
            local key = slotKey and NAME_FORMAT_KEYS[slotKey]
            local mode = key and p and p[key]
            if mode then return short(name, mode) end
            return name
        end
    end
end

-- Estimate pixel width of health text per element. Actual rendered widths are
-- unreadable (secret values), so use flat worst-case pixel assumptions.
local HEALTH_TEXT_PADDING = 10  -- safety margin in px
local healthTextWidths = {
    healthPercent       = 38,
    healthPercentNoSign = 38,
    healthNumber  = 38,
    healthPctNum  = 75,
    healthNumPct  = 75,
    healthPctNumDash = 75,
    healthNumPctDash = 75,
    healthNumMax  = 75,
    level = 24,   -- standalone level: "70" / "??"
    targetOfTarget = 60,
}
local function EstimateHealthTextWidth(element)
    return (healthTextWidths[element] or 0) + HEALTH_TEXT_PADDING
end
ns.EstimateHealthTextWidth = EstimateHealthTextWidth

-- Custom text (element "custom"): any slot may show one, each with its own template
-- (<slot>CustomFormat) on its own font string (plate[ns.NP_CustomFSKey[slot]]), parsed by
-- EllesmereUI.TextTags against this binding of the unit schema. Pieces take (unit, slotKey)
-- and hand values only to format setters: health, absorb and names may be secret. A nil unit
-- is the options preview (the schema samples). do/end + ns funcs: no new locals (cap).
do
    local TT, sf = EllesmereUI.TextTags, string.format
    local FS_KEY, FORMAT_KEY = {}, {}
    for i = 1, #textSlotKeys do
        local s = textSlotKeys[i]
        FS_KEY[s] = "custom" .. s:sub(9)  -- textSlotTop -> customTop
        FORMAT_KEY[s] = s .. "CustomFormat"
    end
    ns.NP_CustomFSKey = FS_KEY
    -- The unit's name as the name slot writes it (the slot's Name Format).
    local function Name(u, slotKey)
        local name = EllesmereUI.WithSurname(UnitName(u))
        if type(name) == "nil" then return "" end
        return ns.NP_FormatName(name, slotKey)
    end
    -- Tag modifiers shape the plain name. They do not also apply the slot's Name Format.
    local function Shaped(mode)
        return function(u)
            local name = EllesmereUI.WithSurname(UnitName(u))
            if type(name) == "nil" then return "" end
            return EllesmereUI.ShortName(name, mode)
        end
    end
    local function TargetShaped(mode)
        local piece = Shaped(mode)
        return function(u)
            local tu = ns._npToTUnits[u]
            if not tu then tu = u .. "target"; ns._npToTUnits[u] = tu end
            if not UnitExists(tu) then return "" end
            return piece(tu)
        end
    end
    local P = {
        ["hp"] = function(u)
            if UnitIsDeadOrGhost(u) then return EllesmereUI.L("DEAD") end
            return sf("%d", UnitHealth(u) or 0)
        end,
        ["hp:abr"] = function(u)
            if UnitIsDeadOrGhost(u) then return EllesmereUI.L("DEAD") end
            return ns.AbbreviateNumbers(UnitHealth(u) or 0)
        end,
        ["hp:max"] = function(u) return sf("%d", UnitHealthMax(u) or 0) end,
        ["hp:max:abr"] = function(u) return ns.AbbreviateNumbers(UnitHealthMax(u) or 0) end,
        ["hp:pct"] = function(u)
            if UnitIsDeadOrGhost(u) then return "0" end
            return sf("%d", UnitHealthPercent(u, true, CurveConstants.ScaleTo100) or 0)
        end,
        ["absorb"] = function(u) return C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(u) or 0) end,
        ["absorb:abr"] = function(u) return ns.AbbreviateNumbers(UnitGetTotalAbsorbs(u) or 0) end,
        ["name"] = Name,
        ["name:first"] = Shaped("first"), ["name:last"] = Shaped("last"), ["name:abbr"] = Shaped("abbr"),
        ["target"] = function(u, slotKey)
            local tu = ns._npToTUnits[u]
            if not tu then tu = u .. "target"; ns._npToTUnits[u] = tu end
            if not UnitExists(tu) then return "" end
            return Name(tu, slotKey)
        end,
        ["target:first"] = TargetShaped("first"), ["target:last"] = TargetShaped("last"),
        ["target:abbr"] = TargetShaped("abbr"),
        ["level"] = function(u) return ns.GetUnitLevelText(u) end,
    }
    local CAT = TT.Bind(TT.UNIT, P)
    ns.NP_TextTags = CAT
    -- Weak both ways: each value points back at its key (c.parsed), which a weak-key
    -- table alone would never let go of in Lua 5.1. Plates hold what they paint.
    local compiled = setmetatable({}, { __mode = "kv" })
    local args = {}
    -- A slot's parsed template (nil while empty). db: a profile to read instead of the live one.
    function ns.NP_CustomParse(slotKey, db)
        db = db or p
        return TT.Parse(CAT, db and db[FORMAT_KEY[slotKey]])
    end
    -- A slot's compiled template { fmt, n, reads, has, parsed, [i] = piece }, nil while
    -- empty. Built once per parse result.
    function ns.NP_CustomCompiled(slotKey, db)
        local parsed = ns.NP_CustomParse(slotKey, db)
        if not parsed then return nil end
        local c = compiled[parsed]
        if not c then
            local keys = parsed.keys
            c = { fmt = parsed.fmt, n = #keys, reads = parsed.reads, has = parsed.has, parsed = parsed }
            for i = 1, c.n do c[i] = P[keys[i]] end
            compiled[parsed] = c
        end
        return c
    end
    -- One SetFormattedText per paint; unit nil paints the schema samples.
    function ns.NP_PaintCustom(fs, c, unit, slotKey)
        if not unit then
            fs:SetText(TT.Preview(CAT, c.parsed))
            return
        end
        local n = c.n
        for i = 1, n do args[i] = c[i](unit, slotKey) end
        fs:SetFormattedText(c.fmt, unpack(args, 1, n))
        -- An empty Top text (no target, no shield) keeps its line: the top aura row
        -- and the range text anchor to it. GetText reads nil while empty.
        if slotKey == "textSlotTop" and not fs:GetText() then fs:SetText(" ") end
    end
    -- Estimated width of a slot's custom text, 0 while empty. db: as NP_CustomParse.
    function ns.NP_CustomWidth(slotKey, db)
        local parsed = ns.NP_CustomParse(slotKey, db)
        if not parsed then return 0 end
        return TT.EstimateWidth(CAT, parsed) + HEALTH_TEXT_PADDING
    end
    -- The bar width left to a name-like text in a bar slot: the bar minus the estimated
    -- widths of the other bar slots' texts (a name-family text at the schema's name width).
    -- db: a profile to read instead of the live one.
    function ns.NP_BarRestWidth(slotKey, db)
        db = db or p
        local w = ns.GetHealthBarWidth()
        local bar = ns._npBarTextKeys
        for i = 1, #bar do
            local key = bar[i]
            if key ~= slotKey then
                local el = (db and db[key]) or defaults[key]
                if el == "custom" then
                    w = w - ns.NP_CustomWidth(key, db)
                elseif ns.IsNameElement(el) then
                    w = w - (TT.UNIT.keys.name.width + HEALTH_TEXT_PADDING)
                elseif el ~= "none" then
                    w = w - EstimateHealthTextWidth(el)
                end
            end
        end
        return w
    end
end

local function GetHealthBarWidth()
    local extra = (p and p.healthBarWidth) or defaults.healthBarWidth
    return BAR_W + extra
end
ns.GetHealthBarWidth = GetHealthBarWidth

-- Y offset for plate content relative to the nameplate frame. Always 0: the Blizzard nameplate
-- frame grows from its CENTER, not its base, so a taller SetNamePlateSize enlarges the hitbox
-- evenly above AND below the unit; anchoring content at the frame center needs no compensation.
local function GetHitboxYShift()
    return 0
end
ns.GetHitboxYShift = GetHitboxYShift
-- Slot-based size/offset getters. Key strings memoized per posKey (closed set of six literals,
-- lazy-filled) so these hot getters allocate nothing; VALUES still read live so profile swaps cannot stale.
ns._slotKeyMemo = ns._slotKeyMemo or {}
local function GetSlotKeys(posKey)
    local m = ns._slotKeyMemo[posKey]
    if not m then
        m = {
            size = posKey .. "SlotSize",
            x    = posKey .. "SlotXOffset",
            y    = posKey .. "SlotYOffset",
        }
        ns._slotKeyMemo[posKey] = m
    end
    return m
end
local function GetSlotSize(posKey)
    local m = GetSlotKeys(posKey)
    return (p and p[m.size]) or defaults[m.size] or 24
end
ns.GetSlotSize = GetSlotSize
local function GetSlotOffsets(posKey)
    local m = GetSlotKeys(posKey)
    local xOff = (p and p[m.x]) or defaults[m.x] or 0
    local yOff = (p and p[m.y]) or defaults[m.y] or 0
    return xOff, yOff
end
ns.GetSlotOffsets = GetSlotOffsets
local function GetDebuffIconSize()
    local slot = (p and p.debuffSlot) or defaults.debuffSlot
    if slot == "none" then return defaults.debuffIconSize or 26 end
    return GetSlotSize(slot)
end
ns.GetDebuffIconSize = GetDebuffIconSize
local function GetBuffIconSize()
    local slot = (p and p.buffSlot) or defaults.buffSlot
    if slot == "none" then return defaults.buffIconSize or 24 end
    return GetSlotSize(slot)
end
ns.GetBuffIconSize = GetBuffIconSize
local function GetCCIconSize()
    local slot = (p and p.ccSlot) or defaults.ccSlot
    if slot == "none" then return defaults.ccIconSize or 24 end
    return GetSlotSize(slot)
end
ns.GetCCIconSize = GetCCIconSize
-- Cropped aura icons (mirrors Unit Frames "Cropped Icons"). On: icon frame goes rectangular
-- (height = 80% of width), texture trimmed top/bottom so artwork is never squished; horizontal
-- zoom stays at the nameplate default (0.08). do/end + ns functions: no new main-chunk locals (cap).
do
    local AURA_CROP_HEIGHT = 0.80
    local AURA_ZOOM = 0.08
    -- Returns FALSE when uncropped, else the height FACTOR: 1 - 2*(cropPercent/100), so default
    -- 10% yields 0.80. Callers that only truth-test the result work unchanged.
    function ns.GetAuraCrop(element)
        local on, pct
        if element == "debuffs" then
            on = (p and p.debuffCropIcons) or defaults.debuffCropIcons
            pct = p and p.debuffCropPercent
        elseif element == "buffs" then
            on = (p and p.buffCropIcons) or defaults.buffCropIcons
            pct = p and p.buffCropPercent
        elseif element == "ccs" then
            on = (p and p.ccCropIcons) or defaults.ccCropIcons
            pct = p and p.ccCropPercent
        end
        if not on then return false end
        pct = tonumber(pct) or 10
        if pct < 5 then pct = 5 elseif pct > 25 then pct = 25 end
        return 1 - 2 * (pct / 100)
    end
    -- Frame height for an icon width: shorter when cropped, square when not. `cropped` is
    -- GetAuraCrop's result: a factor number, or plain true (falls back to AURA_CROP_HEIGHT).
    function ns.GetAuraCropHeight(cropped, w)
        if cropped then
            local factor = (type(cropped) == "number") and cropped or AURA_CROP_HEIGHT
            return math.floor(w * factor + 0.5)
        end
        return w
    end
    -- Texcoord trim. Cropped scales the vertical span to the rectangle's aspect
    -- so the texture keeps its proportions; uncropped is the original square zoom.
    function ns.SetAuraIconCrop(icon, cropped, w, h)
        if not icon then return end
        -- Stock styles draw the whole icon (zoom 0), as the engine cells do.
        local z = ns.NP_Blizz() and 0 or AURA_ZOOM
        if cropped and w and h and w > 0 then
            local uSpan = 1 - 2 * z
            local vSpan = uSpan * (h / w)
            local v0 = 0.5 - vSpan / 2
            icon:SetTexCoord(z, 1 - z, v0, 1 - v0)
        else
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
end
local function GetTargetGlowStyle()
    if p and p.targetGlowStyle then return p.targetGlowStyle end
    return defaults.targetGlowStyle
end
ns.GetTargetGlowStyle = GetTargetGlowStyle
-- Multi-toggle target glow model (EllesmereUI / Border Color / Highlight). Live conversion, NO
-- migration: each toggle returns its own stored key when set, else derives from targetGlowStyle
-- (stays in defaults so the fallback source is always present). Mapping: ellesmereui ->
-- EllesmereUI; vibrant -> EllesmereUI + Border Color; none -> nothing. On ns (local budget).
function ns.GetTargetGlowEllesmereUI()
    if p and p.targetGlowEllesmereUI ~= nil then return p.targetGlowEllesmereUI end
    local style = (p and p.targetGlowStyle) or defaults.targetGlowStyle
    return style == "ellesmereui" or style == "vibrant"
end
function ns.GetTargetGlowBorderColor()
    if p and p.targetGlowBorderColor ~= nil then return p.targetGlowBorderColor end
    local style = (p and p.targetGlowStyle) or defaults.targetGlowStyle
    return style == "vibrant"
end
function ns.GetTargetGlowHighlight()
    if p and p.targetGlowHighlight ~= nil then return p.targetGlowHighlight end
    return false  -- no legacy equivalent
end
function ns.GetTargetGlowBorderSize()
    if p and p.targetGlowBorderSize ~= nil then return p.targetGlowBorderSize end
    return false  -- no legacy equivalent
end
-- nil until the effect's first enable snapshots the user's current border size (options side);
-- nil = applies nothing (fail-safe for imported partial profiles).
function ns.GetTargetBorderSizeValue()
    local v = p and p.targetBorderSizeValue
    return v
end
function ns.GetTargetBorderColor()
    return (p and p.targetBorderColor) or defaults.targetBorderColor
end
function ns.GetTargetGlowColor()
    return (p and p.targetGlowColor) or defaults.targetGlowColor
end
function ns.GetTargetGlowAlpha()
    local a = p and p.targetGlowAlpha
    if a == nil then return defaults.targetGlowAlpha end
    return a
end
function ns.GetTargetHighlightColor()
    return (p and p.targetHighlightColor) or defaults.targetHighlightColor
end
function ns.GetTargetHighlightAlpha()
    local a = p and p.targetHighlightAlpha
    if a == nil then return defaults.targetHighlightAlpha end
    return a
end
-- Hover Effect (mirrors the Target Effect model, user-directed 2026-08-16).
-- Highlight is the ONLY default-on channel and reuses the legacy
-- hoverColor/hoverAlpha keys as its color/opacity, so every existing AND new
-- profile renders EXACTLY the old flat hover highlight (including the alpha
-- 0 = invisible case) until other channels are opted in. New-channel colors
-- start from the target effect's defaults.
function ns.GetHoverGlowEllesmereUI() return (p and p.hoverGlowEllesmereUI) == true end
function ns.GetHoverGlowBorderColor() return (p and p.hoverGlowBorderColor) == true end
function ns.GetHoverGlowHighlight()
    if p and p.hoverGlowHighlight ~= nil then return p.hoverGlowHighlight == true end
    return true
end
function ns.GetHoverGlowBorderSize() return (p and p.hoverGlowBorderSize) == true end
-- nil until the effect's first enable snapshots the user's current border
-- size (options side); nil = applies nothing.
function ns.GetHoverBorderSizeValue() return p and p.hoverBorderSizeValue end
function ns.GetHoverBorderColor()
    return (p and p.hoverBorderColor) or defaults.targetBorderColor
end
function ns.GetHoverGlowColor()
    return (p and p.hoverGlowColor) or defaults.targetGlowColor
end
function ns.GetHoverGlowAlpha()
    local a = p and p.hoverGlowAlpha
    if a == nil then return defaults.targetGlowAlpha end
    return a
end
local function GetShowTargetGlow()
    return ns.GetTargetGlowEllesmereUI() or ns.GetTargetGlowBorderColor() or ns.GetTargetGlowHighlight()
end
ns.GetShowTargetGlow = GetShowTargetGlow
local function GetShowClassPower()
    if p and p.showClassPower ~= nil then return p.showClassPower end
    return defaults.showClassPower
end
ns.GetShowClassPower = GetShowClassPower
-- On ns, not file locals (Lua's 200-local limit); callers use ns.GetClassPower*().
ns.GetClassPowerPos = function()
    return (p and p.classPowerPos) or defaults.classPowerPos
end
ns.GetClassPowerYOffset = function()
    return (p and p.classPowerYOffset) or defaults.classPowerYOffset
end
ns.GetClassPowerXOffset = function()
    return (p and p.classPowerXOffset) or defaults.classPowerXOffset
end
ns.GetClassPowerScale = function()
    return (p and p.classPowerScale) or defaults.classPowerScale
end
ns.GetClassPowerGap = function()
    return (p and p.classPowerGap) or defaults.classPowerGap
end
local function GetClassPowerClassColors()
    if p and p.classPowerClassColors ~= nil then return p.classPowerClassColors end
    return defaults.classPowerClassColors
end
ns.GetClassPowerClassColors = GetClassPowerClassColors
local function GetClassPowerCustomColor()
    local c = (p and p.classPowerCustomColor) or defaults.classPowerCustomColor
    return c
end
ns.GetClassPowerCustomColor = GetClassPowerCustomColor
ns.GetClassPowerBgColor = function()
    local c = (p and p.classPowerBgColor) or defaults.classPowerBgColor
    return c
end
ns.GetClassPowerEmptyColor = function()
    local c = (p and p.classPowerEmptyColor) or defaults.classPowerEmptyColor
    return c
end
-- On ns, not file locals (Lua's 200 main-chunk local limit).
function ns.GetClassPowerShape()
    return (p and p.classPowerShape) or defaults.classPowerShape
end
function ns.GetClassPowerBorder()
    local v = p and p.classPowerBorder
    if v == nil then return defaults.classPowerBorder end
    return v
end
function ns.GetClassPowerBorderColor()
    return (p and p.classPowerBorderColor) or defaults.classPowerBorderColor
end
function ns.GetClassPowerBorderSize()
    return (p and p.classPowerBorderSize) or defaults.classPowerBorderSize
end
local function IsBorderEnabled()
    -- The stock styles carry their own art instead of an EUI border: the
    -- stock background art (Blizzard Style), the vanilla border sheets
    -- (Classic WoW UI, ns.NP_ApplyClassicHealthArt).
    if ns.NP_Blizz() then return false end
    local v = p and p.showBorder
    if v == nil then return defaults.showBorder end
    return v
end
ns.IsBorderEnabled = IsBorderEnabled
-- Per-icon 1px borders (cast / buff / debuff / CC). nil = border shown
-- (old profiles without the key keep their borders). Setting a hide key
-- to true hides the border; false shows it.
function ns.GetIconBorderEnabled(kind)
    -- Stock styles: the stock cast icon has no border, and the aura items
    -- carry the rounded ring overlay (Blizzard) or the stock dispel-type
    -- border (classic) instead of a 1px border.
    if ns.NP_Blizz() then return false end
    local key
    if kind == "cast" then
        key = "hideCastIconBorder"
    elseif kind == "debuffs" then
        key = "hideDebuffIconBorder"
    elseif kind == "buffs" then
        key = "hideBuffIconBorder"
    else
        key = "hideCCIconBorder"
    end
    local v = p and p[key]
    if v == nil then
        v = defaults[key]
        if v == nil then return true end  -- no default at all: border shown
    end
    return not v
end
function ns.ApplyFrameIconBorder(frame, enabled, adjustIconInset)
    local PP = EllesmereUI and EllesmereUI.PP
    if not (frame and PP and PP.GetBorders and PP.GetBorders(frame)) then return end
    if enabled then
        if PP.ShowBorder then PP.ShowBorder(frame) end
    elseif PP.HideBorder then
        PP.HideBorder(frame)
    end
    -- Aura slots keep a 1px icon inset for the border; borderless fills the
    -- icon to the edge so no bare rim shows (matches the options preview).
    -- OPT-IN: the cast icon (inset 0 by design, border draws on top) and the
    -- lockout icon own their geometry and must not be re-anchored here.
    if adjustIconInset and frame.icon then
        local px = enabled and 1 or 0
        frame.icon:ClearAllPoints()
        PP.Point(frame.icon, "TOPLEFT", frame, "TOPLEFT", px, -px)
        PP.Point(frame.icon, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
    end
end
function ns.NP_CanShowCastIconSeparator(db)
    if not db or db.castbarIconInWidth ~= true or db.showCastIcon == false
        or db.castIconFullSize == true or ns.NP_Blizz() then return false end
    local tex = db.customBorderTexture or defaults.customBorderTexture
    return (db.customBorderSize or defaults.customBorderSize) > 0
        and (tex == "solid" or tex == "" or EllesmereUI.GetBorderCompanion(tex, "sepV") ~= nil)
end

-- Shared by live plates and the preview; the cast bar owns this lazy divider. It
-- does not follow the target or threat tint, so the border-colour passes that land
-- here (every threat repaint) change nothing: only a moved style input restyles it.
function ns.NP_ApplyCastIconSeparator(cast, icon, db, customOn, strata)
    local seam = cast._iconSeam
    if not (db and db.castIconSeparator == true and customOn and ns.NP_CanShowCastIconSeparator(db)) then
        if seam and seam:IsShown() then
            seam:Hide()
            EllesmereUI.RegisterPxReapply(seam, nil)
        end
        return
    end
    if not seam then
        seam = Pool.CreateFrame("Frame", nil, cast)
        seam:SetAllPoints(cast)
        seam:EnableMouse(false)
        seam._tex = seam:CreateTexture(nil, "OVERLAY", nil, 7)
        cast._iconSeam = seam
    end
    local st = strata or cast:GetFrameStrata()
    local lvl = icon:GetFrameLevel() + 5
    local key = db.customBorderTexture or defaults.customBorderTexture
    local size = db.customBorderSize or defaults.customBorderSize
    local px = EllesmereUI.BorderPx(db.customBorderSizePx, size, key)
    local right = db.castIconOnRight == true
    local c = db.customBorderColor or defaults.customBorderColor
    local a = db.customBorderAlpha or defaults.customBorderAlpha
    -- Restyle inputs: shown state, strata, level (a strata change resets it), texture,
    -- size step, exact px, side, the scale its width snaps to, and its colour.
    if seam:IsShown() and seam:GetFrameStrata() == st and seam:GetFrameLevel() == lvl
        and seam._key == key and seam._size == size and seam._px == px and seam._right == right
        and seam._es == seam:GetEffectiveScale()
        and seam._r == c.r and seam._g == c.g and seam._b == c.b and seam._a == a then
        return
    end
    seam:SetFrameStrata(st)
    seam:SetFrameLevel(lvl)
    seam._key, seam._size, seam._px, seam._right = key, size, px, right
    seam._r, seam._g, seam._b, seam._a = c.r, c.g, c.b, a
    seam._tex:SetVertexColor(c.r, c.g, c.b, a)
    ns.NP_LayoutCastIconSeparator(seam)
    seam:Show()
    EllesmereUI.RegisterPxReapply(seam, strata and ns.NP_LayoutCastIconSeparator or nil)
end

function ns.NP_LayoutCastIconSeparator(seam)
    local t, es = seam._tex, seam:GetEffectiveScale()
    seam._es = es
    if EllesmereUI.GetBorderCompanion(seam._key, "sepV") then
        EllesmereUI.PlaceBorderDividerV(t, seam, seam._right, false, seam._key, seam._size, seam._px, es)
        return
    end
    local onePixel = es > 0 and PP.perfect / es or PP.mult
    t:SetColorTexture(1, 1, 1, 1)
    t:SetTexCoord(0, 1, 0, 1)
    t:ClearAllPoints()
    local top = seam._right and "TOPRIGHT" or "TOPLEFT"
    local bottom = seam._right and "BOTTOMRIGHT" or "BOTTOMLEFT"
    t:SetPoint(top, seam, top, 0, 0)
    t:SetPoint(bottom, seam, bottom, 0, 0)
    t:SetWidth(math.max(1, math.floor((seam._px or seam._size) + 0.5)) * onePixel)
    t:Show()
end

-- Every write of the cast spell icon's border goes through here. Custom Border on
-- Spell Icon (castIconCustomBorder, Border = Custom): the icon wears the plate's custom
-- border in place of its 1px edge. The border is our own frame, a child of the cast bar
-- laid over the icon rather than a child of the icon, whose Scale would multiply an
-- exact pixel size; so it rides Casts In Front of Nameplates with the bar but does not
-- hide with the icon, and turns off through ApplyBorderStyle(frame, 0) so the UI scale
-- re-apply cannot bring it back. MEDIUM strata lifts it out of the plate's flattened
-- layer above the icon art (the lift's strata while the cast bar is lifted). Style
-- inputs restyle only when one moved; a colour change (Use Target Border Color on the
-- target) is a plain tint. Off, this is the 1px edge call plus the opt-in gates.
function ns.ApplyCastIconBorder(plate)
    local icon = plate and plate.castIconFrame
    if not icon then return end
    if (p and p.castIconSeparator) or plate.cast._iconSeam then
        ns.NP_ApplyCastIconSeparator(plate.cast, icon, p, ns.IsCustomBorderEnabled(),
            plate._castOverlayLifted and plate.cast:GetFrameStrata() or "MEDIUM")
    end
    local bf = plate._castIconBorder
    if not (p and p.castIconCustomBorder and ns.IsCustomBorderEnabled()
            and not ns.GetCastIconInWidth()
            and GetShowCastIcon() and ns.GetIconBorderEnabled("cast")) then
        if bf and bf:IsShown() then
            EllesmereUI.ApplyBorderStyle(bf, 0)
            bf:Hide()
        end
        ns.ApplyFrameIconBorder(icon, ns.GetIconBorderEnabled("cast"))
        return
    end
    ns.ApplyFrameIconBorder(icon, false)
    if not bf then
        bf = CreateFrame("Frame", nil, plate.cast)
        bf:SetAllPoints(icon)
        bf:EnableMouse(false)
        plate._castIconBorder = bf
    end
    local tex = p.customBorderTexture or defaults.customBorderTexture
    local sz = p.customBorderSize or defaults.customBorderSize
    local px = EllesmereUI.BorderPx(p.customBorderSizePx, sz, tex)
    local r, g, b, a
    if p.castIconTargetBorder and plate._isTarget and ns.GetTargetGlowBorderColor() then
        local c = ns.GetTargetBorderColor()
        r, g, b, a = c.r, c.g, c.b, 1
    else
        local c = p.customBorderColor or defaults.customBorderColor
        r, g, b, a = c.r, c.g, c.b, p.customBorderAlpha or defaults.customBorderAlpha or 1
    end
    local strata = plate._castOverlayLifted and plate.cast:GetFrameStrata() or "MEDIUM"
    local lvl = icon:GetFrameLevel() + 3
    local offX, offY = p.customBorderOffset, p.customBorderOffsetY
    local shX, shY = p.customBorderShiftX, p.customBorderShiftY
    -- Restyle inputs: shown state, strata, level (a strata change resets it), texture,
    -- size step, exact px, both offsets and both shifts. Anything else is colour.
    if not bf:IsShown() or bf:GetFrameStrata() ~= strata or bf:GetFrameLevel() ~= lvl
        or bf._sTex ~= tex or bf._sSz ~= sz or bf._sPx ~= px
        or bf._sOX ~= offX or bf._sOY ~= offY or bf._sSX ~= shX or bf._sSY ~= shY then
        bf:SetFrameStrata(strata)
        bf:SetFrameLevel(lvl)
        EllesmereUI.ApplyBorderStyle(bf, sz, r, g, b, a, tex, offX, offY, shX, shY, "nameplates", sz, nil, px)
        if PP.GetBorders(bf) then PP.CreateBorder(bf, nil, nil, nil, nil, nil, nil, nil, true) end
        bf._sTex, bf._sSz, bf._sPx = tex, sz, px
        bf._sOX, bf._sOY, bf._sSX, bf._sSY = offX, offY, shX, shY
    else
        EllesmereUI.SetBorderStyleColor(bf, r, g, b, a)
    end
end
local function GetBorderColor()
    -- Classic WoW UI: the plate's edge is always black.
    if ns.NP_Classic() then return 0, 0, 0 end
    local c = (p and p.borderColor) or defaults.borderColor
    return c.r, c.g, c.b
end
ns.GetBorderColor = GetBorderColor
-- Health border size: the classic plate's fixed 1px edge, else the profile's
-- Border Size. Friendly plates mirror it.
function ns.NP_BorderSize()
    if ns.NP_Classic() then return 1 end
    return (p and p.borderSize) or defaults.borderSize
end
-- Cast bar border colour: black under Classic WoW UI, else the profile's.
function ns.NP_CastBorderColor()
    if ns.NP_Classic() then return 0, 0, 0 end
    local c = (p and p.castBorderColor) or defaults.castBorderColor
    return c.r, c.g, c.b
end
-- "Wrap Border Around Castbar". The cast-visibility hook reads this on every
-- cast show/hide, so it must stay a trivial table lookup.
function ns.GetWrapBorderCastbar()
    local v = p and p.wrapBorderCastbar
    if v == nil then return defaults.wrapBorderCastbar end
    return v
end
local function GetAuraSlots()
    local ds = (p and p.debuffSlot) or defaults.debuffSlot
    local bs = (p and p.buffSlot)   or defaults.buffSlot
    local cs = (p and p.ccSlot)     or defaults.ccSlot
    return ds, bs, cs
end
ns.GetAuraSlots = GetAuraSlots

-- Raise Strata: per-slot Core Positions toggle. On, the element in that slot is bumped
-- MEDIUM -> HIGH so it renders above the rest of the plate. On ns (local budget).
function ns.GetSlotRaiseStrata(posKey)
    if not posKey or posKey == "none" then return false end
    local key = posKey .. "SlotRaiseStrata"
    if p and p[key] ~= nil then return p[key] end
    return defaults[key] or false
end

-- Apply each slot's Raise Strata setting to its element frame. Frames otherwise share MEDIUM
-- strata; HIGH lifts that element above the flattened text/aura/indicator tiers, and its
-- children inherit it. The aura containers apply their own (AnchorNPContainer).
function ns.ApplySlotStrata(plate)
    if not plate then return end
    local function StrataFor(slot)
        return ns.GetSlotRaiseStrata(slot) and "HIGH" or "MEDIUM"
    end
    if plate.raidFrame then
        plate.raidFrame:SetFrameStrata(StrataFor(GetRaidMarkerPos()))
    end
    if plate.classFrame then
        plate.classFrame:SetFrameStrata(StrataFor(GetClassificationSlot()))
    end
    if plate.factionFrame then
        plate.factionFrame:SetFrameStrata(StrataFor(ns.NP_GetFactionSlot()))
    end
end

-- Pandemic glow engine: procedural ants, button glow, autocast shine, FlipBook. do...end keeps
-- internal locals out of the main chunk's 200-local budget; externally-needed items stored on ns.
do
-------------------------------------------------------------------------------
--  Glow engines from shared EllesmereUI_Glows.lua; aliases for the wrapper below.
-------------------------------------------------------------------------------
local _G_Glows = EllesmereUI.Glows
local StartProceduralAnts = _G_Glows.StartProceduralAnts
local StopProceduralAnts  = _G_Glows.StopProceduralAnts
local StartButtonGlow     = _G_Glows.StartButtonGlow
local StopButtonGlow      = _G_Glows.StopButtonGlow
local StartAutoCastShine  = _G_Glows.StartAutoCastShine
local StopAutoCastShine   = _G_Glows.StopAutoCastShine
local StartGlow           = _G_Glows.StartGlow
local StopAllGlows        = _G_Glows.StopAllGlows
ns.StartProceduralAnts = StartProceduralAnts
ns.StopProceduralAnts  = StopProceduralAnts
ns.StartButtonGlow     = StartButtonGlow
ns.StopButtonGlow      = StopButtonGlow
ns.StartAutoCastShine  = StartAutoCastShine
ns.StopAutoCastShine   = StopAutoCastShine
ns.StartGlow           = StartGlow
ns.StopAllGlows        = StopAllGlows

-------------------------------------------------------------------------------
--  Dispellable buff glow: highlights enemy buffs the player can purge/soothe
-------------------------------------------------------------------------------
local function StopDispelGlow(slot)
    local dg = slot.dispelGlow
    if not dg or not dg.active then return end
    dg.active = false
    _G_Glows.StopAllGlows(dg.wrapper)
    dg.wrapper:Hide()
end

-- Draws the preview glow's last request (dg.sz, dg.h, dg.type). Same spec and
-- engine path as the live purge glow, so the preview is the live look.
local function DrawDispelGlow(dg)
    ns.GetDispelGlowSpec(dg.type, dg.spec)
    _G_Glows.StartSpecGlow(dg.wrapper, dg.spec, dg.sz, dg.h, "engine", _G_Glows.PANEL_EXTRA)
end

-- Preview only: the live nameplate glow runs through EllesmereUI.Glows on the
-- engine buttons. dispelType is "magic" / "enrage" / nil. slotH: the icon
-- height (cropped icons). The glow draws only while the preview is visible:
-- hidden (options closed, another page, a build made hidden) it stops, so its
-- animations cost nothing, and it draws again when it shows (unchanged,
-- StartSpecGlow returns at once).
local function StartDispelGlow(slot, slotSize, dispelType, slotH)
    local dg = slot.dispelGlow
    if not dg then
        local wrapper = Pool.CreateFrame("Frame", nil, slot)
        wrapper:SetAllPoints()
        -- Under the duration text (its frame sits at slot + 2), as the live
        -- glow host sits under the text carrier.
        wrapper:SetFrameLevel(slot:GetFrameLevel() + 1)
        wrapper:Show()
        dg = { wrapper = wrapper, active = false, spec = {} }
        slot.dispelGlow = dg
        wrapper:SetScript("OnShow", function()
            if dg.active then DrawDispelGlow(dg) end
        end)
        wrapper:SetScript("OnHide", function(self)
            if dg.active then _G_Glows.StopAllGlows(self) end
        end)
    end
    local sz = slotSize or 26
    dg.sz, dg.h, dg.type = sz, slotH or sz, dispelType
    dg.active = true
    local wrapper = dg.wrapper
    if not wrapper:IsShown() then
        -- Its OnShow draws, now or once the preview shows.
        wrapper:Show()
    elseif wrapper:IsVisible() then
        DrawDispelGlow(dg)
    end
    -- Always opaque. Visibility used to ride a per-aura dispel-type curve's
    -- alpha; dispellability is now decided by which aura GROUP the button
    -- belongs to, and this path only ever draws the options preview.
    wrapper:SetAlpha(1)
end

ns.StopDispelGlow = StopDispelGlow
ns.StartDispelGlow = StartDispelGlow
end -- do (glow engine)

-- Forward declaration (assigned in EUI_Nameplates_ClassPower.lua, see SetClassPowerTopPush)
local GetClassPowerTopPush

-- XY offset for an aura slot key ("debuffSlot", "raidMarker", "classification").
local auraSlotToDBKey = {
    debuffSlot     = "debuffSlot",
    buffSlot       = "buffSlot",
    ccSlot         = "ccSlot",
    classification = "classificationSlot",
    raidMarker     = "raidMarkerPos",
    faction        = "factionSlot",
}
local function GetAuraSlotOffsets(slotKey)
    local dbKey = auraSlotToDBKey[slotKey]
    if not dbKey then return 0, 0 end
    local pos = (p and p[dbKey]) or defaults[dbKey]
    if not pos or pos == "none" then return 0, 0 end
    return GetSlotOffsets(pos)
end
-- 12.1 aura containers read layout inputs through these.
ns.GetAuraSlotOffsets = GetAuraSlotOffsets
function ns.NP_GetProfile() return p end
function ns.NP_GetDefaults() return defaults end
function ns.NP_ClassPowerTopPush(plate)
    if GetClassPowerTopPush then return GetClassPowerTopPush(plate) or 0 end
    return 0
end

-- Get XY offset for a text slot key (e.g. "textSlotTop")
local function GetTextSlotOffsets(slotKey)
    local xOff = (p and p[slotKey .. "XOffset"]) or 0
    local yOff = (p and p[slotKey .. "YOffset"]) or 0
    return xOff, yOff
end

-- Get font size for a text slot key (e.g. "textSlotTop")
local function GetTextSlotSize(slotKey)
    return (p and p[slotKey .. "Size"]) or defaults[slotKey .. "Size"] or 10
end
ns.GetTextSlotSize = GetTextSlotSize

-- Get color for a text slot key (e.g. "textSlotTop")
local function GetTextSlotColor(slotKey)
    local c = (p and p[slotKey .. "Color"]) or defaults[slotKey .. "Color"]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Per-slot host frame for a Core Text Position, honoring the slot's Strata
-- option. MEDIUM (the default) keeps today's shared text tier: the top slot
-- owns topTextFrame outright (its strata is applied directly), the other
-- slots share healthTextFrame. A non-default strata on a non-top slot gets
-- a lazily-created host so the four slots layer independently; hosts carry
-- only font strings (no child frames), so SetFrameStrata propagation is not
-- a concern -- except the name raid marker frame and debuff coloring's Color
-- Name copies, whose callers re-assert their strata and levels after parenting.
ns.SlotTextHost = function(self, slotKey, strata)
    if slotKey == "textSlotTop" then
        local f = self.topTextFrame
        f:SetFrameStrata(strata)
        return f
    end
    if strata == "MEDIUM" then return self.healthTextFrame end
    local hosts = self._slotTextHosts
    if not hosts then hosts = {}; self._slotTextHosts = hosts end
    local f = hosts[slotKey]
    if not f then
        f = CreateFrame("Frame", nil, self)
        f:SetAllPoints(self.health)
        f:SetFrameLevel(900)
        hosts[slotKey] = f
    end
    f:SetFrameStrata(strata)
    return f
end

ns.DEFAULT_CAST_LOCKOUT_DURATION = 4
ns.CAST_LOCKOUT_ICON = "Interface\\Icons\\Ability_Kick"

function ns.ShowCastLockoutAsCrowdControl()
    if p and p.showCastLockoutAsCrowdControl ~= nil then return p.showCastLockoutAsCrowdControl end
    return defaults.showCastLockoutAsCrowdControl
end

function ns.GetActiveCastLockout(plate)
    local lockout = plate._castLockout
    if not lockout then return nil end
    if not ns.ShowCastLockoutAsCrowdControl() or lockout.expires <= GetTime() then
        plate._castLockout = nil
        return nil
    end
    return lockout
end

-- How far one side-slot icon pushes a target arrow out: 0 unless it meets the arrow's span (the
-- icon centres on the bar plus y and is sz tall, the arrow ah tall), else its outer edge, past
-- its own cast icon push (as its Update* placed it) and its slot's X offset.
local function ArrowSideReach(plate, side, y, sz, xOff, ah)
    if math.abs(y) >= (sz + ah) / 2 then return 0 end
    local reach = GetSideAuraXOffset() + ns.NP_SideIconPush(plate, side, y, sz) + sz
    if side == "left" then return reach - xOff end
    return reach + xOff
end

-- Side guests: elements another module parks beside the bars (the Kick Tracker's icons). A
-- guest provider answers (plate, side, a0, a1) with the outermost frame it has on that side of
-- the plate whose vertical span meets a0..a1 (the arrows' span, above the bar's bottom) and
-- that frame's centre height over the bar's centre in plate units, or nil. The arrows hug it
-- as they hug a side aura row, and ahead of one: the two cannot be measured against each other.
ns.NP_SideGuests = {}
function ns.NP_AddSideGuest(fn)
    local list = ns.NP_SideGuests
    for i = 1, #list do
        if list[i] == fn then return end
    end
    list[#list + 1] = fn
end

-- Restricted-tree rendering: inside the aspect-restricted nameplate subtree, SINGLE-POINT +
-- SetSize regions render displaced from their anchor, while rects fully defined by anchors
-- (fill, bg, hash line) render exactly. So an arrow pins TOP+BOTTOM to two corners (hash-line
-- pattern): edges resolve engine-side, offsets stay small numbers, nothing here reads geometry
-- ("Can't measure restricted regions"); the symmetric pair keeps the centring exact under
-- pixel-mult rounding. A side guest the arrow meets is hugged at the middle of its outer edge,
-- both points on it, half the arrow up and down (less the guest's own height over the bar's
-- centre), so the arrow stays the bar's and exactly its own height. A side aura row the arrow
-- meets is hugged at its engine-sized outer edge (aura counts are secret): rows are
-- BOTTOM-anchored at the bar's bottom plus their slot's Y offset and grow outward, so the row's
-- bottom outer corner is the one point whose two axes are both truthful, and the arrow centres
-- on the bar from there. A row the full-size cast icon did not push out (it misses the icon)
-- leaves the arrow to clear the icon too, one icon width further out. Otherwise the arrow's
-- inner edge sits `extent` + 8 past the bar's edge.
local function PlaceArrow(plate, arrow, side, extent, aw, ah)
    local barH = GetHealthBarHeight()
    local a0, a1 = (barH - ah) / 2, (barH + ah) / 2
    local x = 8 + aw / 2
    local guests = ns.NP_SideGuests
    local guest, gy
    for i = 1, #guests do
        guest, gy = guests[i](plate, side, a0, a1)
        if guest then break end
    end
    local row, ry, rh
    if not guest and ns.NPC_SideRow then row, ry, rh = ns.NPC_SideRow(plate, side, a0, a1) end
    arrow:ClearAllPoints()
    if guest then
        local edge = (side == "left") and "LEFT" or "RIGHT"
        if side == "left" then x = -x end
        gy = gy or 0
        PP.Point(arrow, "TOP", guest, edge, x, ah / 2 - gy)
        PP.Point(arrow, "BOTTOM", guest, edge, x, -ah / 2 - gy)
    elseif row and ry < a1 and a0 < ry + rh then
        local icon = ns.NP_FullIconPush(plate, side, a0, a1)
        if icon > 0 and ns.NP_FullIconPush(plate, side, ry, ry + rh) == 0 then x = x + icon end
        local cy = barH / 2 - ry
        local corner = (side == "left") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        if side == "left" then x = -x end
        PP.Point(arrow, "TOP", row, corner, x, cy + ah / 2)
        PP.Point(arrow, "BOTTOM", row, corner, x, cy - ah / 2)
    else
        local dy = (ah - barH) / 2
        x = x + extent
        if side == "left" then
            PP.Point(arrow, "TOP", plate.health, "TOPLEFT", -x, dy)
            PP.Point(arrow, "BOTTOM", plate.health, "BOTTOMLEFT", -x, -dy)
        else
            PP.Point(arrow, "TOP", plate.health, "TOPRIGHT", x, dy)
            PP.Point(arrow, "BOTTOM", plate.health, "BOTTOMRIGHT", x, -dy)
        end
    end
    PP.Width(arrow, aw)
end

-- Position target arrows outside the side elements they meet: the cast icon, the side-slot
-- icons (raid marker, classification, faction) and a side aura row. An element its slot's Y
-- offset moved clear of the arrows (above or below them) is passed over.
local function PositionArrowsOutsideAuras(plate)
    if not plate.leftArrow then return end
    if not plate.leftArrow:IsShown() then return end
    local st = ns.ResolveTargetArrowStyle(p)
    local sc = (p and p.targetArrowScale) or 1.0
    local aw = math.floor(((st and st.w) or 16) * sc + 0.5)
    local ah = math.floor(16 * sc + 0.5)
    -- The cast icon (and Classic WoW UI's border), measured on the arrows' own span.
    local leftExtent = ns.NP_SideIconPush(plate, "left", 0, ah)
    local rightExtent = ns.NP_SideIconPush(plate, "right", 0, ah)
    local rmPos = GetRaidMarkerPos()
    if (rmPos == "left" or rmPos == "right") and plate.raidFrame and plate.raidFrame:IsShown() then
        local rx, ry = GetAuraSlotOffsets("raidMarker")
        local r = ArrowSideReach(plate, rmPos, ry, GetRaidMarkerSize(), rx, ah)
        if rmPos == "left" then leftExtent = math.max(leftExtent, r) else rightExtent = math.max(rightExtent, r) end
    end
    local clSlot = GetClassificationSlot()
    if (clSlot == "left" or clSlot == "right") and plate.classFrame and plate.classFrame:IsShown() then
        local cx, cy = GetAuraSlotOffsets("classification")
        local r = ArrowSideReach(plate, clSlot, cy, GetRareEliteIconSize(), cx, ah)
        if clSlot == "left" then leftExtent = math.max(leftExtent, r) else rightExtent = math.max(rightExtent, r) end
    end
    -- The faction badge (its own, or Rare/Quest + Faction, stacked higher behind a showing
    -- Rare/Quest icon as UpdateFaction places it).
    local fcSlot = ns.NP_GetFactionSlot()
    if (fcSlot == "left" or fcSlot == "right") and plate.factionFrame and plate.factionFrame:IsShown() then
        local fx, fy = GetSlotOffsets(fcSlot)
        if p and p.classificationIncludeFaction and plate.classFrame:IsShown() then
            fy = fy + math.floor(GetRareEliteIconSize() * 0.6 + 0.5)
        end
        local r = ArrowSideReach(plate, fcSlot, fy, ns.NP_GetFactionIconSize(), fx, ah)
        if fcSlot == "left" then leftExtent = math.max(leftExtent, r) else rightExtent = math.max(rightExtent, r) end
    end
    PlaceArrow(plate, plate.leftArrow, "left", leftExtent, aw, ah)
    PlaceArrow(plate, plate.rightArrow, "right", rightExtent, aw, ah)
end
ns.PositionArrowsOutsideAuras = PositionArrowsOutsideAuras

I.EstimateHealthTextWidth, I.GetAuraSlotOffsets = EstimateHealthTextWidth, GetAuraSlotOffsets
I.GetBorderColor = GetBorderColor
I.GetCastBarHeight, I.GetCastScale = GetCastBarHeight, GetCastScale
I.GetClassificationSlot = GetClassificationSlot
I.GetClassPowerClassColors = GetClassPowerClassColors
I.GetClassPowerCustomColor = GetClassPowerCustomColor
I.GetDebuffYOffset = GetDebuffYOffset
I.GetEnemyNameTextSize, I.GetFocusCastHeight = GetEnemyNameTextSize, GetFocusCastHeight
I.GetHealthBarHeight, I.GetHealthBarWidth = GetHealthBarHeight, GetHealthBarWidth
I.GetHideEnemyNameWhileCasting = GetHideEnemyNameWhileCasting
I.GetHitboxYShift, I.GetKickTickColor = GetHitboxYShift, GetKickTickColor
I.GetKickTickEnabled, I.GetNameplateYOffset = GetKickTickEnabled, GetNameplateYOffset
I.GetNameYOffset, I.GetRaidMarkerPos = GetNameYOffset, GetRaidMarkerPos
I.GetRaidMarkerSize, I.GetRareEliteIconSize = GetRaidMarkerSize, GetRareEliteIconSize
I.GetShowCastIcon, I.GetShowClassPower = GetShowCastIcon, GetShowClassPower
I.GetSideAuraXOffset, I.GetSlotOffsets = GetSideAuraXOffset, GetSlotOffsets
I.GetStackSpacingScale, I.GetTargetScale = GetStackSpacingScale, GetTargetScale
I.GetTextSlot, I.GetTextSlotColor = GetTextSlot, GetTextSlotColor
I.GetTextSlotOffsets, I.GetTextSlotSize = GetTextSlotOffsets, GetTextSlotSize
I.IsBorderEnabled, I.IsComboHealthText = IsBorderEnabled, IsComboHealthText
I.PANDEMIC_GLOW_STYLES = PANDEMIC_GLOW_STYLES
I.PositionArrowsOutsideAuras = PositionArrowsOutsideAuras
I.SetCombinedHealthText = SetCombinedHealthText
I.SetClassPowerTopPush = function(f) GetClassPowerTopPush = f end
I.broken = false
