if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Styles.lua
--
--  Stock styles (Blizzard and Classic art), the Forever level box, Blizzard
--  cast art, bar textures and the absorb style.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, ipairs, type = pairs, ipairs, type
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack

local defaults = I.defaults

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-------------------------------------------------------------------------------
--  Stock styles (Global Settings > Style). Blizzard Style: the stock
--  nameplate atlases on our own plates -- bar fill + shadowed background,
--  target/focus selection ring, deselected overlay, and the stock cast bar
--  art (background, fills per cast kind, pip, interrupt shield). Classic WoW
--  UI: the flat vanilla plate -- the user's fill inside a fixed 1px black
--  edge on the health and cast bars, square full-art icons, the stock
--  dispel-type border on harmful auras; no ring, mask, panel or bevel. Every
--  EUI feature keeps working; the EUI borders and textures step aside.
--  Reload-gated per-profile flags, read only on build/restyle paths. Atlases
--  are validated once per session so a missing one leaves that piece on the
--  EUI look. ns fields (local cap).
-------------------------------------------------------------------------------
ns.NP_BLIZZ = {
    bar = "UI-HUD-CoolDownManager-Bar", barBg = "UI-HUD-CoolDownManager-Bar-BG",
    selected = "UI-HUD-Nameplates-Selected", deselected = "ui-hud-nameplates-deselected-overlay",
    castBg = "ui-castingbar-background", cast = "ui-castingbar-filling-standard",
    channel = "ui-castingbar-filling-channel", interrupted = "ui-castingbar-interrupted",
    castShieldFill = "ui-castingbar-uninterruptable", castPip = "ui-castingbar-pip",
    shield = "nameplates-InterruptShield",
    auraMask = "UI-HUD-CoolDownManager-Mask", auraRing = "UI-HUD-CoolDownManager-IconOverlay",
    -- WoW Forever variant only (atlases that client alone ships): its
    -- selection ring and the level box right of the bar.
    selYellow = "UI-HUD-CoolDownManager-Selected-yellow",
    lvlBg = "ui-hud-nameplates-levelindicator",
    lvlSel = "ui-hud-nameplates-levelindicator-rectangle-selected",
    lvlSkull = "ui-hud-nameplates-levelindicator-skull",
}
-- Classic WoW UI kit. debuffBorder: the stock debuff border for an untyped
-- debuff (the engine stamps the typed ones on the aura cells itself; our
-- hand-built icons wear this one). The rest is the vanilla nameplate border
-- art: a long window with a plate on one end (the level's on the health
-- border's right, the spell icon's on the cast border's left), drawn as
-- three pieces so the two plates keep their shape at any bar width while
-- the window between them stretches.
--
-- EVERY number below is in BAR-HEIGHT units: multiply by the bar's own
-- height. They come from measuring an in-game render of each file (the
-- copies the CDN serves differ from what the client draws, so the files
-- themselves cannot be trusted for this). The art's texcoords are its
-- opaque extent, `c1`/`c2` cut it at the window's two ends, `capL`/`capR`
-- are the pieces' widths and `reachL`/`reachR` how far the art reaches past
-- the bar. Each cap is a touch wider than its reach because the art's inner
-- rim overlaps the bar's edge, which is the vanilla look. Confirmed against
-- Blizzard's own Classic nameplate constants: the cast sheet's bar lands
-- exactly on their 20.75 / 3.5 insets in a 16-tall border.
ns.NP_CLASSIC = {
    debuffBorder = "ui-debuff-border-default-noicon",
    -- health reachL carries a +0.08 nudge over its measured 0.057: the plain
    -- end of the art is ROUNDED and our fill is a plain rectangle with no
    -- corner mask, so at the measured reach the fill's square top-left and
    -- bottom-left corners show past the curve. Pushing that end out covers
    -- them and still leaves the rim overlapping the bar's left edge. The
    -- plate end needs none of this: it is a filled box. (The cast sheet's
    -- plain end already reaches 0.26 and covers its own corners.)
    health = { file = "Interface\\Tooltips\\Nameplate-Border",
               l = 0.0049, r = 0.5261, t = 0.5065, b = 0.9610, c1 = 0.0195, c2 = 0.4137,
               capL = 0.187, capR = 1.440, reachL = 0.137, reachR = 1.310 },
    cast   = { file = "Interface\\Tooltips\\Nameplate-Border-Castbar",
               l = 0.0081, r = 0.9919, t = 0.5065, b = 0.9610, c1 = 0.1710, c2 = 0.9609,
               capL = 2.086, capR = 0.390, reachL = 1.956, reachR = 0.260 },
    spark = "Interface\\CastingBar\\UI-CastingBar-Spark",
    shield = "Interface\\CastingBar\\UI-CastingBar-Small-Shield",
    skull = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    top = 0.230, bottom = 0.229,  -- the art's reach above and below the bar
    gap = 0.35,                   -- clear space between the two borders
    plateOffL = 0.924,            -- the cast icon's centre, left of the cast bar's left edge
    plateOffR = 0.584,            -- the level's centre, right of the health bar's right edge
    icon = 1.4,                   -- the cast icon's side, seated in its plate
    -- The level and the boss icon while their sliders sit at 0 ("follow the
    -- bar"): three quarters of what the bar's height would give, which
    -- overfilled the plate. The Level Size and Elite Icon Size sliders
    -- override each of them.
    levelFont = 0.75, levelIcon = 1,
    sparkSize = 3.2, sparkY = -0.1,
    shieldL = 2.0, shieldT = 1.1, shieldR = 1.3, shieldB = 1.3,  -- the shield frame's reach past the cast bar
}
-- The cast icon's centre from the cast bar's LEFT, and the level's centre
-- from the health bar's RIGHT (both plates are centred on the bar's own
-- middle line).
function ns.NP_ClassicIconOffset(k)
    return -ns.NP_CLASSIC.plateOffL * k, 0
end
-- The level's and the elite icon's seat in the health border's plate: the
-- plate's own centre plus the user's own offsets. Their size scales with the
-- bar until the user sets one (0 = follow the bar).
function ns.NP_ClassicLevelOffset(k)
    return ns.NP_CLASSIC.plateOffR * k + ((p and p.classicLevelX) or 0), ((p and p.classicLevelY) or 0)
end
function ns.NP_ClassicSkullOffset(k)
    return ns.NP_CLASSIC.plateOffR * k + ((p and p.classicSkullX) or 0), ((p and p.classicSkullY) or 0)
end
function ns.NP_ClassicLevelSize(k)
    local v = p and p.classicLevelSize
    if v and v > 0 then return v end
    return math.max(6, ns.NP_CLASSIC.levelFont * k)
end
function ns.NP_ClassicSkullSize(k)
    local v = p and p.classicSkullSize
    if v and v > 0 then return v end
    return ns.NP_CLASSIC.levelIcon * k
end
-- The Classic WoW UI border's reach past the health bar's two ends, 0 on
-- every other style. The border is part of the bar as far as anything beside
-- it is concerned -- its level plate hangs well past the bar's right edge --
-- so the target arrows and every side-slot element clear this too. `k` =
-- the bar's height (nil = the enemy plates'; friendly plates pass theirs).
-- The WoW Forever variant's level box (right of the bar) is part of it the
-- same way, so its room comes back here too (ns.NP_Classic has just latched
-- the variant flag read here).
function ns.NP_ClassicBarReserve(k)
    if not ns.NP_Classic() then return 0, ns._npForever and ns.NP_ForeverSide() or 0 end
    local C = ns.NP_CLASSIC
    k = k or (ns.GetHealthBarHeight and ns.GetHealthBarHeight()) or 0
    return C.health.reachL * k, C.health.reachR * k
end
-- WoW Forever's level box: 28 wide and 5 right of the bar (Blizzard's own
-- nameplate constants), 5 taller than it; its target and focus border
-- colours. The box art is nine-sliced with a 1-unit shadow outside its rim,
-- so at 5 taller its rim spans the bar's own rim (at Blizzard's 3 it sits a
-- unit below the bar's top rim).
ns.NP_FOREVER_LVL = { w = 28, gap = 5, pad = 5, font = 10,
    target = { 1, 1, 1 }, focus = { 1, 0.49, 0.039 } }
-- Whether the plates carry the box: the variant, less the profile's Show
-- Level Box opt-out (foreverHideLevelBox; nil = shown).
function ns.NP_ForeverBoxOn()
    return ns.NP_Forever() and not (p and p.foreverHideLevelBox)
end
-- The room the box takes right of the bar (0 off the variant, and while the
-- box is off, so everything lays out as plain Blizzard Style).
function ns.NP_ForeverSide()
    if not ns.NP_ForeverBoxOn() then return 0 end
    local L = ns.NP_FOREVER_LVL
    return L.gap + L.w
end
-- One side of it ("left" | "right"), for the many places that gap a single
-- element off one edge of the bar.
function ns.NP_ClassicSide(side, k)
    local l, r = ns.NP_ClassicBarReserve(k)
    if side == "right" then return r end
    return l
end
-- The cast bar's layout under the health bar: its shift right, its width
-- over the footprint and its drop, so the two borders line up at their
-- outer edges (plate under plain end, plain end under plate) with a clear
-- gap between them. kh / kc are the two bars' heights.
function ns.NP_ClassicCastLayout(footprintW, kh, kc)
    local C = ns.NP_CLASSIC
    local lh, rh = C.health.reachL * kh, C.health.reachR * kh
    local lc, rc = C.cast.reachL * kc, C.cast.reachR * kc
    return lc - lh, footprintW + (lh + rh) - (lc + rc), -((C.bottom + C.gap) * kh + C.top * kc)
end
-- Three pieces of a sheet on `host` (its art cut at the window's two ends);
-- created once, seated by NP_SeatClassicBorder.
function ns.NP_ClassicBorderPieces(host, sheet)
    local p = { sheet = sheet }
    for i = 1, 3 do
        local t = host:CreateTexture(nil, "OVERLAY", nil, 0)
        t:SetTexture(sheet.file)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        p[i] = t
    end
    p[1]:SetTexCoord(sheet.l, sheet.c1, sheet.t, sheet.b)
    p[2]:SetTexCoord(sheet.c1, sheet.c2, sheet.t, sheet.b)
    p[3]:SetTexCoord(sheet.c2, sheet.r, sheet.t, sheet.b)
    return p
end
-- Seats the pieces round `bar` at k (the bar's height): both plates keep
-- the art's own proportion, the window stretches between them. Memoized;
-- every layout pass may call it.
function ns.NP_SeatClassicBorder(p, bar, k)
    if p._k == k and p._bar == bar then return end
    p._k, p._bar = k, bar
    local C = ns.NP_CLASSIC
    local sheet = p.sheet
    local l, r = sheet.reachL * k, sheet.reachR * k
    local t, b = C.top * k, C.bottom * k
    for i = 1, 3 do p[i]:ClearAllPoints() end
    p[1]:SetPoint("TOPLEFT", bar, "TOPLEFT", -l, t)
    p[1]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -l, -b)
    p[1]:SetWidth(sheet.capL * k)
    p[3]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", r, t)
    p[3]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", r, -b)
    p[3]:SetWidth(sheet.capR * k)
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT", 0, 0)
    p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT", 0, 0)
end
-- The vanilla health border round a plate's health bar (enemy and friendly
-- plates alike) and, where the plate has a text frame, the unit's level in
-- the border's plate. The pieces ride a host above the fill, the absorbs
-- and the class icon and under the texts; a height change re-seats them.
function ns.NP_ApplyClassicHealthArt(plate, h)
    local health = plate and plate.health
    if not health then return end
    local C = ns.NP_CLASSIC
    local host = plate._classicHealthHost
    if not host then
        host = CreateFrame("Frame", nil, health)
        host:SetAllPoints(health)
        host:EnableMouse(false)
        plate._classicHealthHost = host
        plate._classicHealthArt = ns.NP_ClassicBorderPieces(host, C.health)
    end
    host:SetFrameLevel(health:GetFrameLevel() + 6)
    local k = h or health:GetHeight()
    ns.NP_SeatClassicBorder(plate._classicHealthArt, health, k)
    -- The art carries a level plate, so it must never render empty: a plate
    -- with no text frame of its own (the friendly plates) gets a host here,
    -- one level above the border art.
    local tf = plate.healthTextFrame
    if not tf then
        tf = plate._classicLevelHost
        if not tf then
            tf = CreateFrame("Frame", nil, health)
            tf:SetAllPoints(health)
            tf:EnableMouse(false)
            plate._classicLevelHost = tf
        end
        tf:SetFrameLevel(host:GetFrameLevel() + 1)
    end
    local fs, sk = plate._classicLevel, plate._classicSkull
    if not fs then
        fs = tf:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("CENTER")
        plate._classicLevel = fs
        sk = tf:CreateTexture(nil, "OVERLAY")
        sk:SetTexture(C.skull)
        sk:Hide()
        plate._classicSkull = sk
    end
    -- The user's nameplate font, outline and shadow, like every other text
    -- on the plate (and it guarantees a font before any SetText).
    ns.SetFSFont(fs, ns.NP_ClassicLevelSize(k))
    local lx, ly = ns.NP_ClassicLevelOffset(k)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", health, "RIGHT", lx, ly)
    local sx, sy = ns.NP_ClassicSkullOffset(k)
    local ss = ns.NP_ClassicSkullSize(k)
    sk:ClearAllPoints()
    sk:SetSize(ss, ss)
    sk:SetPoint("CENTER", health, "RIGHT", sx, sy)
    ns.NP_UpdateClassicLevel(plate)
end
-- The level in the health border's plate: the effective level in its
-- difficulty colour, the skull for a boss, "??" for a level the client keeps
-- secret. Every unit read is treated as possibly secret.
function ns.NP_UpdateClassicLevel(plate)
    local fs, sk = plate._classicLevel, plate._classicSkull
    if not fs then return end
    local unit = plate.unit
    if not unit or not UnitExists(unit) then fs:Hide(); sk:Hide(); return end
    local lvl = UnitEffectiveLevel(unit)
    local secret = issecretvalue and issecretvalue(lvl)
    if not secret and type(lvl) == "number" and lvl < 0 then
        fs:Hide(); sk:Show()
        return
    end
    sk:Hide()
    fs:SetText(ns.GetUnitLevelText(unit))
    -- The stock yellow, and the difficulty colour only where difficulty means
    -- something: a unit you cannot attack is never colour-ranked.
    local r, g, b = 1, 0.82, 0
    local canAttack = UnitCanAttack("player", unit)
    if issecretvalue and issecretvalue(canAttack) then canAttack = false end
    if canAttack and not secret and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer then
        local diff = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit)
        if not (issecretvalue and issecretvalue(diff)) and GetDifficultyColor then
            local color = GetDifficultyColor(diff)
            if color then r, g, b = color.r, color.g, color.b end
        end
    end
    fs:SetTextColor(r, g, b, 1)
    fs:Show()
end
-- The vanilla cast border round a plate's cast bar, with the spell icon
-- lifted above it into its plate, the vanilla spark on the fill's edge and
-- the vanilla shield frame round the bar for an uninterruptible cast. The
-- pieces ride a host above the fill and the background; LayoutCastBar calls
-- this on every re-layout (memo in the seat, the per-height work behind
-- its own memo).
function ns.NP_ApplyClassicCastArt(plate, castH)
    local cast = plate and plate.cast
    if not cast then return end
    local C = ns.NP_CLASSIC
    local k = castH or cast:GetHeight()
    local host = plate._classicCastHost
    if not host then
        host = CreateFrame("Frame", nil, cast)
        host:SetAllPoints(cast)
        host:EnableMouse(false)
        plate._classicCastHost = host
        plate._classicCastArt = ns.NP_ClassicBorderPieces(host, C.cast)
    end
    host:SetFrameLevel(cast:GetFrameLevel() + 2)
    ns.NP_SeatClassicBorder(plate._classicCastArt, cast, k)
    -- The pool builds the cast bar BEFORE its icon frame, spark, shield and
    -- seam line, and lays the bar out in between, so the first pass through
    -- here has none of them. Stamping the memo then would claim this height
    -- as done and the art below would never be applied to any of them: wait
    -- until they all exist.
    if not (plate.castIconFrame and plate.castSpark and plate.castShield and plate.castShieldFrame and plate.castLeftBorder) then return end
    if plate._classicCastK == k then return end
    plate._classicCastK = k
    -- Above the border art AND above the health bar, as the pool intended:
    -- the cast bar is a plain child of the plate, so the host's own level
    -- alone would drop the icon below the health bar rather than lift it.
    plate.castIconFrame:SetFrameLevel(math.max(host:GetFrameLevel() + 1, plate.health:GetFrameLevel() + 1))
    ns.NP_ClassicSpark(plate, k)
    plate.castShield:SetTexture(C.shield)
    plate.castShieldFrame:ClearAllPoints()
    plate.castShieldFrame:SetPoint("TOPLEFT", cast, "TOPLEFT", -C.shieldL * k, C.shieldT * k)
    plate.castShieldFrame:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", C.shieldR * k, -C.shieldB * k)
    plate.castLeftBorder:Hide()
end
-- The vanilla spark: a square on the fill's leading edge, not a bar-tall
-- sliver. Every caller that sizes the spark for the EUI look routes here
-- under Classic WoW UI instead, so none of them can squash it back.
function ns.NP_ClassicSpark(plate, k)
    local cast, spark = plate and plate.cast, plate and plate.castSpark
    if not (cast and spark) then return end
    local C = ns.NP_CLASSIC
    spark:SetTexture(C.spark)
    spark:SetSize(C.sparkSize * k, C.sparkSize * k)
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, C.sparkY * k)
end
-- One chokepoint for "size the spark to this cast height": the square under
-- Classic WoW UI, the bar-tall sliver otherwise.
function ns.NP_SetSparkHeight(plate, castH)
    if ns.NP_Classic() then ns.NP_ClassicSpark(plate, castH); return end
    if plate and plate.castSpark then plate.castSpark:SetHeight(castH) end
end
ns._npAtlasMemo = {}
-- The style this module RENDERS this session -- "eui" | "blizzard" |
-- "classic" -- read from the profile once (first call with a profile present)
-- and latched: a live profile switch never flips the look under the one-time
-- art setup; the profile system prompts for a reload instead. Both flags set
-- resolves as classic.
function ns.NP_Style()
    local v = ns._npStyle
    if v == nil then
        if not p then return "eui" end
        v = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "eui"
        ns._npStyle = v
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one.
        ns._npForever = v == "blizzard" and EllesmereUI.IS_FOREVER == true
            and p.useForeverStyle == true
    end
    return v
end
-- Stock-art mode: true for both stock styles (the geometry, gating and
-- chrome they share -- zoom 0 icons, no EUI icon borders, no custom border).
function ns.NP_Blizz() return ns.NP_Style() ~= "eui" end
function ns.NP_Classic() return ns.NP_Style() == "classic" end
-- WoW Forever variant: NP_Style() still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces. False off Forever.
function ns.NP_Forever()
    if ns._npStyle == nil then ns.NP_Style() end
    return ns._npForever == true
end
-- Stock kit frame art on a plain Texture (never a mask or a status bar
-- fill): the retail art on every client (EllesmereUI.StockAtlas), the
-- client's own under the WoW Forever variant. Each texture is painted once
-- per session.
function ns.NP_StockAtlas(tex, name)
    if ns.NP_Forever() then return tex:SetAtlas(name) end
    return EllesmereUI.StockAtlas(tex, name)
end
function ns.NP_AtlasOK(name)
    local memo = ns._npAtlasMemo
    local v = memo[name]
    if v == nil then
        v = (name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
        memo[name] = v
    end
    return v
end
-- Inner shadow on the health bar: the stock fill art bakes this bevel in,
-- and under the style the fill is the user's own texture, so it is drawn
-- here: four regions of the bar at OVERLAY -3 (above the fill, under the
-- hash line, the overlays and the ring), created once, re-sized per pass.
ns._npShadeClear  = CreateColor(0, 0, 0, 0)
ns._npShadeTop    = CreateColor(0, 0, 0, 0.55)
ns._npShadeBottom = CreateColor(0, 0, 0, 0.30)
ns._npShadeEnd    = CreateColor(0, 0, 0, 0.35)
function ns.NP_BlizzBarShadow(bar, h, mask)
    local sh = bar._blizzShadow
    if not sh then
        sh = {}
        bar._blizzShadow = sh
        for i = 1, 4 do
            local tex = bar:CreateTexture(nil, "OVERLAY", nil, -3)
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
            sh[i] = tex
        end
        -- VERTICAL runs bottom -> top, HORIZONTAL left -> right.
        sh[1]:SetGradient("VERTICAL", ns._npShadeClear, ns._npShadeTop)
        sh[2]:SetGradient("VERTICAL", ns._npShadeBottom, ns._npShadeClear)
        sh[3]:SetGradient("HORIZONTAL", ns._npShadeEnd, ns._npShadeClear)
        sh[4]:SetGradient("HORIZONTAL", ns._npShadeClear, ns._npShadeEnd)
    end
    h = h or bar:GetHeight() or 10
    -- The strips hang off the bar's edges, so only the height sizes them:
    -- one compare per plate show once laid out (plates show constantly).
    if sh._h ~= h then
        sh._h = h
        local top, bottom, ends = math.max(2, math.floor(h * 0.2)), math.max(1, math.floor(h * 0.1)), math.max(2, math.floor(h * 0.15))
        sh[1]:ClearAllPoints(); sh[1]:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0); sh[1]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0); sh[1]:SetHeight(top)
        sh[2]:ClearAllPoints(); sh[2]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0); sh[2]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0); sh[2]:SetHeight(bottom)
        sh[3]:ClearAllPoints(); sh[3]:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0); sh[3]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0); sh[3]:SetWidth(ends)
        sh[4]:ClearAllPoints(); sh[4]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0); sh[4]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0); sh[4]:SetWidth(ends)
        for i = 1, 4 do sh[i]:Show() end
    end
    -- Bar-shape mask, seated once per mask object.
    if mask and sh._mask ~= mask then
        for i = 1, 4 do
            if sh._mask then pcall(sh[i].RemoveMaskTexture, sh[i], sh._mask) end
            sh[i]:AddMaskTexture(mask)
        end
        sh._mask = mask
    end
end
-- Health bar: the stock shadowed background hugging the bar the way the
-- stock plate anchors it, plus the bar's inner shadow. The fill keeps the
-- user's own Bar Texture (the stock fill art is pre-coloured and darkened
-- every colour rule), so colours, textures and opacity render as on the
-- EUI look.
function ns.NP_ApplyBlizzBarArt(plate)
    local health = plate.health
    local B = ns.NP_BLIZZ
    local bg = plate.healthBG
    if bg and not plate._blizzBarBg and ns.NP_AtlasOK(B.barBg) then
        plate._blizzBarBg = true
        bg:SetAtlas(B.barBg)
        bg:SetVertexColor(1, 1, 1, 1)
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 3)
        bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 6, -6)
    end
    -- The stock fill art's own footprint (rounded, soft-edged, inside the
    -- background's rim) as a mask over the bar for the fill, the highlights
    -- and the shadow: the user's texture sits inside the rim exactly as the
    -- stock fill does instead of painting over it. Seated per texture object
    -- (a status bar texture path swap mints a new fill object).
    local mask = plate._blizzBarMask
    if not mask and ns.NP_AtlasOK(B.bar) then
        mask = health:CreateMaskTexture()
        mask:SetAtlas(B.bar)
        mask:SetAllPoints(health)
        plate._blizzBarMask = mask
    end
    if mask then
        local fill = health:GetStatusBarTexture()
        if fill and plate._blizzMaskedFill ~= fill then
            pcall(fill.RemoveMaskTexture, fill, mask)
            fill:AddMaskTexture(mask)
            plate._blizzMaskedFill = fill
        end
        if plate.highlight and not plate._blizzMaskedHover then
            plate.highlight:AddMaskTexture(mask)
            plate._blizzMaskedHover = true
        end
        if plate.targetHighlight and not plate._blizzMaskedTarget then
            plate.targetHighlight:AddMaskTexture(mask)
            plate._blizzMaskedTarget = true
        end
    end
    ns.NP_BlizzBarShadow(health, nil, mask)
end
-- Hand-built aura icons (the cast-lockout icon, the options preview mocks):
-- the stock nameplate aura item look -- the rounded mask over the icon art
-- and the ring overlay hung 6px by 5px past a 25px item, scaled to the
-- frame. Our own frames, so the state lives on them: one-time structure,
-- size-memoized ring geometry. The engine cells get the same look through
-- AuraKit's blizzRoundArt lane (EUI_Nameplates_AuraContainers BuildNPStyle).
function ns.NP_ApplyBlizzIconArt(frame, icon, w, h)
    if not (frame and icon) then return end
    local B = ns.NP_BLIZZ
    if not (ns.NP_AtlasOK(B.auraMask) and ns.NP_AtlasOK(B.auraRing)) then return end
    local ring = frame._blizzIconRing
    if not ring then
        local mask = frame:CreateMaskTexture()
        mask:SetAtlas(B.auraMask)
        mask:SetAllPoints(frame)
        icon:AddMaskTexture(mask)
        frame._blizzIconMask = mask
        ring = frame:CreateTexture(nil, "OVERLAY", nil, 5)
        ns.NP_StockAtlas(ring, B.auraRing)
        ring:SetSnapToPixelGrid(false)
        ring:SetTexelSnappingBias(0)
        frame._blizzIconRing = ring
    end
    w = w or frame:GetWidth()
    h = h or frame:GetHeight()
    if frame._blizzIconW ~= w or frame._blizzIconH ~= h then
        frame._blizzIconW, frame._blizzIconH = w, h
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", frame, "TOPLEFT", -w * 0.24, h * 0.2)
        ring:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", w * 0.24, -h * 0.2)
    end
end
-- Hand-built harmful aura icons under Classic WoW UI (the cast-lockout icon,
-- the options preview mocks): the stock debuff border hung a sixth of the
-- icon past each edge, as the engine draws it round the aura cells, over the
-- square full-art icon. The border sits on a child frame two levels above
-- its host so it draws over the host's cooldown swipe (a child Cooldown
-- renders above every region of its parent). Our own frames, so the state
-- lives on them: one-time structure, size-memoized geometry. The engine
-- cells get theirs through AuraKit's blizzBorder lane
-- (EUI_Nameplates_AuraContainers BuildNPStyle).
function ns.NP_ApplyClassicIconArt(frame, w, h)
    if not frame then return end
    local atlas = ns.NP_CLASSIC.debuffBorder
    if not ns.NP_AtlasOK(atlas) then return end
    local host = frame._classicIconHost
    local border = frame._classicIconBorder
    if not border then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        host:EnableMouse(false)
        border = host:CreateTexture(nil, "OVERLAY", nil, 5)
        border:SetAtlas(atlas)
        border:SetSnapToPixelGrid(false)
        border:SetTexelSnappingBias(0)
        frame._classicIconHost = host
        frame._classicIconBorder = border
    end
    -- Re-asserted each pass: the host follows any relevel of its frame.
    host:SetFrameLevel(frame:GetFrameLevel() + 2)
    w = w or frame:GetWidth()
    h = h or frame:GetHeight()
    if frame._classicIconW ~= w or frame._classicIconH ~= h then
        frame._classicIconW, frame._classicIconH = w, h
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", -w / 6, h / 6)
        border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", w / 6, -h / 6)
    end
end
-- Target / focus selection ring and the deselected overlay every other plate
-- carries. Called from the target/focus change paths (never per tick);
-- isTarget is passed by callers that already resolved it.
function ns.NP_ApplyBlizzSelection(plate, isTarget)
    local health = plate and plate.health
    if not health or not plate.unit then return end
    local B = ns.NP_BLIZZ
    local sel, desel = plate._blizzSelected, plate._blizzDeselected
    if not sel then
        local fv = ns.NP_Forever() and ns.NP_AtlasOK(B.selYellow)
        if not ((fv or ns.NP_AtlasOK(B.selected)) and ns.NP_AtlasOK(B.deselected)) then return end
        local bg = plate.healthBG or health
        sel = health:CreateTexture(nil, "OVERLAY", nil, 5)
        if fv then
            -- WoW Forever's ring: a thin yellow outline hung off the
            -- background art's corners, as that client's own plates.
            sel:SetAtlas(B.selYellow)
            sel:SetPoint("TOPLEFT", bg, "TOPLEFT", -3, 2)
            sel:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 2)
        else
            sel:SetAtlas(B.selected)
            sel:SetPoint("TOPLEFT", bg, "TOPLEFT", -1, 1)
            sel:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -3, 3)
        end
        sel:Hide()
        plate._blizzSelected = sel
        desel = health:CreateTexture(nil, "OVERLAY", nil, 4)
        desel:SetAtlas(B.deselected)
        desel:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 1)
        desel:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, -1)
        plate._blizzDeselected = desel
    end
    if isTarget == nil then isTarget = UnitIsUnit(plate.unit, "target") end
    local isFocus = not isTarget and UnitIsUnit(plate.unit, "focus")
    -- State memo: a plate show with the same selection state repaints nothing.
    local state = (isTarget and "target") or (isFocus and "focus") or false
    if plate._blizzSelState == state then return end
    plate._blizzSelState = state
    -- WoW Forever: the level box's own border follows the same state.
    if plate._fvLevelBox then ns.NP_ForeverLevelSel(plate) end
    if isTarget or isFocus then
        local c
        if isTarget then c = NAMEPLATE_BORDER_TARGET_COLOR else c = NAMEPLATE_BORDER_FOCUS_TARGET_COLOR end
        if c and c.r then
            sel:SetVertexColor(c.r, c.g, c.b)
        elseif isTarget then
            sel:SetVertexColor(1, 1, 1)
        else
            sel:SetVertexColor(1, 0.8, 0)
        end
        sel:Show()
        desel:Hide()
    else
        sel:Hide()
        desel:Show()
    end
end

-------------------------------------------------------------------------------
--  WoW Forever variant of Blizzard Style (the Forever client only, latched by
--  ns.NP_Forever): the level box right of the health bar, as that client's
--  own plates draw it -- a bronze-rimmed box with the unit's level in its
--  difficulty colour, a skull for a boss, and a border while the unit is your
--  target or focus. Built only under the variant; every call site tests the
--  latch or the box, so the other looks never create or touch it.
-------------------------------------------------------------------------------
-- The level's font size: Blizzard's 10, smaller only in a box too short for it.
function ns.NP_ForeverLevelFont(boxH)
    return math.min(ns.NP_FOREVER_LVL.font, math.max(6, math.floor(boxH * 0.625 + 0.5)))
end
-- The box's frame on a health bar (one of our own frames): the rim, the
-- level text (no font yet: the caller sets one before any SetText), the
-- hidden skull and the hidden selection border (nil when the client lacks
-- its atlas). nil when the client lacks the box art. Shared with the options
-- preview; the caller sizes it.
function ns.NP_BuildForeverLevelBox(health)
    local B, L = ns.NP_BLIZZ, ns.NP_FOREVER_LVL
    if not ns.NP_AtlasOK(B.lvlBg) then return nil end
    local box = CreateFrame("Frame", nil, health)
    box:EnableMouse(false)
    box:SetFrameLevel(health:GetFrameLevel() + 6)
    box:SetPoint("LEFT", health, "RIGHT", L.gap, 0)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas(B.lvlBg)
    bg:SetAllPoints(box)
    local fs = box:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("CENTER")
    fs:SetPoint("CENTER", box, "CENTER", 0, 0)
    box._fs = fs
    local sk = box:CreateTexture(nil, "OVERLAY")
    if ns.NP_AtlasOK(B.lvlSkull) then sk:SetAtlas(B.lvlSkull) end
    sk:SetPoint("CENTER", box, "CENTER", 0, 0)
    sk:Hide()
    box._skull = sk
    if ns.NP_AtlasOK(B.lvlSel) then
        -- Where the stock plate hangs it (4 past a box 2 shorter), level with
        -- the bar's own selection ring.
        local sel = box:CreateTexture(nil, "OVERLAY", nil, 1)
        sel:SetAtlas(B.lvlSel)
        sel:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 3)
        sel:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -3)
        sel:Hide()
        box._sel = sel
    end
    return box
end
-- Builds the box once per plate, then sizes it to the bar's height `h` (nil
-- = the bar's own) and paints the plate's unit. Runs from the plate's border
-- pass and size changes. With Show Level Box off, a built box is parked
-- (hidden, off the field every box path tests) for a switch back.
function ns.NP_ApplyForeverLevelBox(plate, h)
    local health = plate and plate.health
    if not health then return end
    local box = plate._fvLevelBox
    if p and p.foreverHideLevelBox then
        if box then
            box:Hide()
            plate._fvLevelBox, plate._fvLevelBoxSpare = nil, box
        end
        return
    end
    local L = ns.NP_FOREVER_LVL
    if not box then
        box = plate._fvLevelBoxSpare or ns.NP_BuildForeverLevelBox(health)
        if not box then return end
        plate._fvLevelBox, plate._fvLevelBoxSpare = box, nil
        -- The selection state may already be set on this plate.
        ns.NP_ForeverLevelSel(plate)
    end
    box:SetFrameLevel(health:GetFrameLevel() + 6)
    local bh = (h or health:GetHeight()) + L.pad
    if box._h ~= bh then
        box._h = bh
        box:SetSize(L.w, bh)
        -- The stock skull size (the bar's height + 3).
        box._skull:SetSize(bh - 2, bh - 2)
    end
    -- The user's nameplate font and outline, like every other plate text
    -- (and it guarantees a font before any SetText).
    ns.SetFSFont(box._fs, ns.NP_ForeverLevelFont(bh))
    ns.NP_UpdateForeverLevel(plate)
end
-- The unit's level in the box: its difficulty colour against yours when you
-- can attack it, else the non-attackable gold; the skull for a level the
-- client hides (a boss). No box on a game object. Every unit read is treated
-- as possibly secret: a secret level is shown as it comes, in the gold.
function ns.NP_UpdateForeverLevel(plate)
    local box = plate._fvLevelBox
    if not box then return end
    local unit = plate.unit
    if not unit or not UnitExists(unit) then box:Hide(); return end
    local off = UnitIsGameObject(unit)
    if issecretvalue and issecretvalue(off) then off = false end
    if off then box:Hide(); return end
    local fs, sk = box._fs, box._skull
    local lvl = UnitEffectiveLevel(unit)
    local secret = issecretvalue and issecretvalue(lvl)
    if not secret and (type(lvl) ~= "number" or lvl <= 0) then
        fs:Hide()
        sk:Show()
    else
        sk:Hide()
        local r, g, b
        if not secret then r, g, b = EllesmereUI.GetLevelColor(unit, lvl) end
        if not r then r, g, b = 1, 0.82, 0 end
        fs:SetText(lvl)
        fs:SetTextColor(r, g, b, 1)
        fs:Show()
    end
    box:Show()
end
-- The box's border for the plate's selection state (the one
-- ns.NP_ApplyBlizzSelection memoizes): white for the target, orange for the
-- focus, hidden otherwise.
function ns.NP_ForeverLevelSel(plate)
    local box = plate._fvLevelBox
    local sel = box and box._sel
    if not sel then return end
    local state, L = plate._blizzSelState, ns.NP_FOREVER_LVL
    local c = (state == "target" and L.target) or (state == "focus" and L.focus) or nil
    if c then
        sel:SetVertexColor(c[1], c[2], c[3])
        sel:Show()
    else
        sel:Hide()
    end
end
-- Every enemy plate's box, for a change in the player's own level or
-- faction (only attackable units are colour-ranked, and the friendly plates
-- never carry one).
function ns.NP_ForeverSweepLevels()
    for _, pl in pairs(ns.plates) do
        if pl._fvLevelBox then ns.NP_UpdateForeverLevel(pl) end
    end
end
-- Level edges the plates' own events do not carry: a unit's level and the
-- player's own (every difficulty colour moves with it); a unit's faction
-- rides the shared faction dispatch. Its frame is born in this main chunk,
-- so the events bill to this module, and is armed only while the variant's
-- box shows: enable arms it, and every full settings refresh re-checks it
-- (Show Level Box is per profile). Returns true when the state flipped.
if EllesmereUI.IS_FOREVER == true then ns._npFvLevelEv = CreateFrame("Frame") end
function ns.NP_ForeverWatchLevels()
    local f = ns._npFvLevelEv
    if not f then return false end
    local on = ns.NP_ForeverBoxOn()
    if on == (ns._npFvLevelArmed == true) then return false end
    ns._npFvLevelArmed = on
    if not on then
        f:UnregisterAllEvents()
        return true
    end
    f:RegisterEvent("UNIT_LEVEL")
    f:RegisterEvent("PLAYER_LEVEL_CHANGED")
    if f:GetScript("OnEvent") then return true end
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_LEVEL_CHANGED" then
            ns.NP_ForeverSweepLevels()
            return
        end
        -- The player's own UNIT_LEVEL arrives with PLAYER_LEVEL_CHANGED
        -- (one sweep for the pair).
        if not unit or unit == "player" then return end
        local pl = ns.plates[unit] or (ns.friendlyPlates and ns.friendlyPlates[unit])
        if pl and pl._fvLevelBox then ns.NP_UpdateForeverLevel(pl) end
    end)
    return true
end
-- Cast fill per cast kind ("cast" | "channel" | "interrupted"); one field test
-- when the style is off, memoized per plate.
function ns.NP_SetBlizzCastFill(plate, kind)
    if not plate._blizzCastArt then return end
    kind = kind or "cast"
    if plate._blizzCastKind == kind then return end
    local atlas = ns.NP_BLIZZ[kind]
    if not ns.NP_AtlasOK(atlas) then return end
    plate._blizzCastKind = kind
    plate.cast:GetStatusBarTexture():SetAtlas(atlas)
end
-- Cast bar: stock background, fills, pip and shield; the uninterruptible
-- overlay becomes the stock grey fill art (still shown through the same
-- SetAlphaFromBoolean gate).
function ns.NP_ApplyBlizzCastArt(plate)
    local cast = plate.cast
    local B = ns.NP_BLIZZ
    -- The fill object and the overlay art are seated once per plate (nothing
    -- else touches them under the style); every later show only follows the
    -- cast kind, memoized in NP_SetBlizzCastFill.
    if not plate._blizzCastArt then
        cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        plate._blizzCastArt = true
        plate._blizzCastKind = nil
        if plate.castBarOverlay then
            plate.castBarOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
            if ns.NP_AtlasOK(B.castShieldFill) then
                -- Bar textures (this fill and the background below) take
                -- the retail art under Blizzard Style, WoW Forever included.
                EllesmereUI.StockAtlas(plate.castBarOverlay, B.castShieldFill)
                -- The overlay is the grey fill art: the cast path paints it white.
                plate._blizzShieldFill = true
            end
        end
    end
    ns.NP_SetBlizzCastFill(plate, plate.isCasting and plate._blizzCastLastKind or "cast")
    if plate._blizzCastChrome then return end
    plate._blizzCastChrome = true
    if plate.castBG and ns.NP_AtlasOK(B.castBg) then
        EllesmereUI.StockAtlas(plate.castBG, B.castBg)
        plate.castBG:SetVertexColor(1, 1, 1, 1)
        plate.castBG:ClearAllPoints()
        plate.castBG:SetPoint("TOPLEFT", cast, "TOPLEFT", 1, 0)
        plate.castBG:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -1, 0)
    end
    if plate.castSpark and ns.NP_AtlasOK(B.castPip) then
        plate.castSpark:SetAtlas(B.castPip)
        plate.castSpark:SetWidth(4)
    end
    if plate.castShield and ns.NP_AtlasOK(B.shield) then plate.castShield:SetAtlas(B.shield) end
    if plate.castLeftBorder then plate.castLeftBorder:Hide() end
    if plate.castIcon then plate.castIcon:SetTexCoord(0, 1, 0, 1) end
end

-- Health bar texture overlay tables (stored on ns to avoid local count pressure)
ns.healthBarTextures, ns.healthBarTextureNames, ns.healthBarTextureOrder =
    EllesmereUI.BuildBarTextureTables(true)
-- Extra entry, second in the list: the game's own bar fill, pointed at
-- directly so it needs no SharedMedia registration. Same file the meters'
-- "Blizzard" uses, which also means the shared appender drops the library's
-- identical entry instead of listing a second "Blizzard" further down. A
-- plain file path, so every consumer resolves it through ResolveTexturePath
-- with no special case. Both stock styles seed it.
-- (The client's own Classic nameplate draws UI-TargetingFrame-BarFill here
-- instead; swapping this one constant is all that would take.)
ns.NP_BLIZZ_BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
ns.healthBarTextures["blizzard"] = ns.NP_BLIZZ_BAR_TEX
ns.healthBarTextureNames["blizzard"] = "Blizzard"
table.insert(ns.healthBarTextureOrder, 2, "blizzard")
-- The one-time stock-style seed on the profile `p`: that fill on the health
-- and cast bars, once per profile. The dropdowns stay the user's afterwards.
-- Run by the Style page the moment either stock style is switched on, and at
-- enable for a profile that arrived already switched (an import, an older
-- build).
-- The keys the Style page keeps per style for this module (its SLOT_KEYS).
ns._npStyleSlotKeys = { "healthBarTexture", "castBarTexture",
    "castBgColor", "castBgAlpha", "castBarUninterruptible" }
-- The one-time Classic WoW UI cast seed: the vanilla plate's half-black
-- window behind the fill and a light grey for an uninterruptible cast, so
-- the grey fill reads against its background (the EllesmereUI look's dark
-- background and mid grey are nearly one tone on the classic bar fill).
-- Once per profile; the controls stay the user's afterwards.
ns._npClassicCastKeys = { "castBgColor", "castBgAlpha", "castBarUninterruptible" }
function ns.NP_SeedClassic(prof)
    if not prof or prof.classicCastSeeded then return end
    prof.classicCastSeeded = true
    prof.castBgColor = { r = 0, g = 0, b = 0 }
    prof.castBgAlpha = 0.5
    prof.castBarUninterruptible = { r = 0.7, g = 0.7, b = 0.7 }
end
function ns.NP_SeedStock(prof)
    if not prof or prof.stockBarTextureSeeded then return end
    prof.stockBarTextureSeeded = true
    prof.healthBarTexture = "blizzard"
    prof.castBarTexture = "blizzard"
end
-- The one-time WoW Forever seed: the level box shows the level, so the Left
-- Text slot's Forever default ("level") steps aside instead of showing it a
-- second time. Once per profile; a level the user put anywhere else stays,
-- and the slot is the user's afterwards. The Style page keeps the key in a
-- Forever-only slot (p._foreverStyleSlots): the other looks' value is banked
-- on the way into the variant and comes back on the way out.
function ns.NP_SeedForever(prof)
    if not prof or prof.foreverLevelSlotSeeded then return end
    prof.foreverLevelSlotSeeded = true
    local v = prof.textSlotLeft
    if v == nil then v = defaults.textSlotLeft end
    if v == "level" then prof.textSlotLeft = "none" end
end

local function NoTintFlag(db, key)
    local v = db and db[key]
    if v == nil then v = defaults[key] end
    return v
end

local function ApplyHealthBarTexture(plate)
    local health = plate.health
    if not health then return end
    local texKey = (p and p.healthBarTexture) or defaults.healthBarTexture or "none"
    local path   = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    health:SetStatusBarTexture(path)
    -- A path swap mints a new fill object: the shield anchors follow it.
    if plate.absorb and plate._absFill ~= health:GetStatusBarTexture() then
        ns.NP_LayoutAbsorbBars(plate, health, plate._absEdge)
    end
    -- Blizzard Style: the user's fill under the stock background art, plus
    -- the bar's inner shadow (re-sized here on every appearance pass). The
    -- classic plate is the bare fill inside its 1px edge (the border path).
    if ns.NP_Style() == "blizzard" then ns.NP_ApplyBlizzBarArt(plate) end
end
ns.ApplyHealthBarTexture = ApplyHealthBarTexture

-- Cast bar texture: mirrors ApplyHealthBarTexture with the same texture set (EUI built-ins +
-- SharedMedia, appended into ns.healthBarTextures at options-build time). On ns (local cap).
function ns.ApplyCastBarTexture(plate)
    local cast = plate.cast
    if not cast then return end
    -- Blizzard Style: the stock cast bar art replaces the texture. The classic
    -- cast bar is the user's texture inside its 1px edge (ApplyCastBorder).
    if ns.NP_Style() == "blizzard" then ns.NP_ApplyBlizzCastArt(plate); return end
    local texKey = (p and p.castBarTexture) or defaults.castBarTexture or "none"
    local path   = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    cast:SetStatusBarTexture(path)
    -- The uninterruptible overlay is a flat WHITE8x8 (grey tint via SetAlphaFromBoolean) that
    -- would hide the fill texture; give it the same texture so the pattern shows through. The
    -- per-cast grey SetVertexColor is re-applied on every cast start, so this is safe.
    if plate.castBarOverlay then
        plate.castBarOverlay:SetTexture(path)
    end
end

function ns.ApplyAbsorbStyle(plate)
    local style = (p and p.absorbStyle) or defaults.absorbStyle
    -- blizzard/striped/clean live in NP_ABSORB_STYLE_TEX; the stripe keys
    -- (shared with the Focus Texture dropdown) resolve via ResolveOverlayTexPath.
    local tex   = ns.NP_ABSORB_STYLE_TEX[style] or ns.ResolveOverlayTexPath(style) or ns.NP_ABSORB_STYLE_TEX.blizzard
    -- Opacity applies to every style. absorbAlpha (0-100) is the single source of truth
    -- once set (slider touched or style picked); until then, per-style defaults.
    local alpha = p and p.absorbAlpha
    if alpha then
        alpha = alpha / 100
    elseif style == "clean" then
        alpha = ((p and p.absorbCleanAlpha) or defaults.absorbCleanAlpha or 30) / 100
    else
        alpha = ns.NP_ABSORB_STYLE_ALPHA[style] or 0.8
    end
    -- Tint applies to every style EXCEPT Blizzard, which keeps its own coloring.
    local r, g, b = 1, 1, 1
    if style ~= "blizzard" then
        local c = (p and p.absorbColor) or defaults.absorbColor
        -- Per-component default: a partial colour table would throw downstream.
        if c then r, g, b = c.r or 1, c.g or 1, c.b or 1 end
    end
    local mask = plate._absorbMask
    for _, bar in ipairs({ plate.absorb, plate.absorbForward }) do
        if bar then
            bar:SetStatusBarTexture(tex)
            bar:SetStatusBarColor(r, g, b, alpha)
            local fill = bar:GetStatusBarTexture()
            if fill then
                fill:SetDrawLayer("ARTWORK", 1)
                if mask then fill:AddMaskTexture(mask) end
            end
        end
    end
    local mode = (p and p.absorbEdgeMode) or defaults.absorbEdgeMode
    if plate._absEdge ~= mode or plate._absFill ~= plate.health:GetStatusBarTexture() then
        ns.NP_LayoutAbsorbBars(plate, plate.health, mode)
        -- A shield already up repaints in its new placement (the forward
        -- bar's visibility is decided by the paint).
        if plate.unit and plate.MarkHealthDirty and not plate._absorbHidden then
            plate._absorbEdge = true
            plate:MarkHealthDirty()
        end
    end
end

-- Shield absorbs, drawn like the unit frames' and secret-safe: both bars take
-- the raw absorb over 0..maxHealth and two clip frames do the split visually,
-- so no Lua math ever touches a (possibly secret) absorb amount, and the
-- health bar keeps its own range (the shield never squeezes it).
--   _absMissClip: health fill edge -> bar's right end (the empty health).
--   _absCurClip:  bar's left end -> health fill edge (the filled health), or
--                 the whole bar in the edge placements.
--   absorbForward: in the missing clip, overlay placements only:
--     overlay        = fills right from the health edge, so it shows
--                      min(absorb, missing)
--     overlayReverse = fills right from the bar's left end, so it shows only
--                      what exceeds current health, past the health edge
--   absorb: in the filled clip, placed per absorbEdgeMode:
--     overlay        = fills left from the bar's right end; the clip shows
--                      only what exceeds empty health, over the health fill
--     overlayReverse = fills left from the health edge, over current health
--     right / left   = the whole shield from that end of the bar
-- Overlay Reverse thus draws the shield back over health, and a shield
-- larger than current health spans from the bar's left end instead of
-- losing its excess.
-- Shared with the options preview (owner is any table holding the bars).
function ns.NP_BuildAbsorbBars(owner, health, mask)
    local lvl = health:GetFrameLevel() + 1
    local curClip = CreateFrame("Frame", nil, health)
    curClip:SetClipsChildren(true)
    curClip:SetFrameLevel(lvl)
    local missClip = CreateFrame("Frame", nil, health)
    missClip:SetClipsChildren(true)
    missClip:SetFrameLevel(lvl)
    local fw = CreateFrame("StatusBar", nil, missClip)
    fw:SetReverseFill(false)
    local ab = CreateFrame("StatusBar", nil, curClip)
    for _, bar in ipairs({ ab, fw }) do
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local fill = bar:GetStatusBarTexture()
        if fill and mask then fill:AddMaskTexture(mask) end
        bar:SetFrameLevel(lvl)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
    end
    -- The clips carry the visibility (the bars inside stay shown): hidden,
    -- their fill-edge anchors cost nothing on a plate with no shield.
    curClip:Hide()
    missClip:Hide()
    owner._absCurClip, owner._absMissClip = curClip, missClip
    owner.absorb, owner.absorbForward = ab, fw
end

-- Seats every anchor for a placement. Anchors ride the health fill object,
-- and a health texture path swap mints a new one, so this also re-runs
-- whenever the fill changes (stamped _absFill). Never per paint.
function ns.NP_LayoutAbsorbBars(owner, health, mode)
    local fillTex = health:GetStatusBarTexture()
    local curClip, missClip = owner._absCurClip, owner._absMissClip
    local ab, fw = owner.absorb, owner.absorbForward
    local fromLeft = mode == "overlayReverse"
    missClip:ClearAllPoints()
    -- 1px into the fill seals the seam behind a forward bar that starts at
    -- the health edge; one from the bar's left end would double that pixel
    -- over the main bar.
    missClip:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", fromLeft and 0 or -1, 0)
    missClip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    fw:ClearAllPoints()
    if fromLeft then
        fw:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        fw:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    else
        fw:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        fw:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    end
    curClip:ClearAllPoints()
    ab:ClearAllPoints()
    if mode == "right" or mode == "left" then
        curClip:SetAllPoints(health)
    else
        curClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        curClip:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    end
    if mode == "left" then
        ab:SetReverseFill(false)
        ab:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        ab:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    elseif mode == "overlayReverse" then
        ab:SetReverseFill(true)
        ab:SetPoint("TOPRIGHT", fillTex, "TOPRIGHT", 0, 0)
        ab:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    else
        ab:SetReverseFill(true)
        ab:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
        ab:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    end
    owner._absFwOn = mode == "overlay" or fromLeft
    if not owner._absFwOn then missClip:Hide() end
    owner._absEdge, owner._absFill = mode, fillTex
end

-- Both bars span the health bar so their textures render at bar scale.
function ns.NP_SizeAbsorbBars(owner, w, h)
    owner.absorb:SetSize(w, h)
    owner.absorbForward:SetSize(w, h)
end

function ns.ApplyAbsorbStyleAll()
    -- Pooled plates pick the change up at their next spawn.
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        ns.ApplyAbsorbStyle(plate)
    end
end

I.ApplyHealthBarTexture, I.NoTintFlag = ApplyHealthBarTexture, NoTintFlag
I.broken = false
