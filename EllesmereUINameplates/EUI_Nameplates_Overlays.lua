if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Overlays.lua
--
--  Lazily built overlays (glow, low health, near aggro, highlight, arrows,
--  focus), the threat percent text, the threat gap, hover and target overlay.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, type = pairs, type
local PP = EllesmereUI.PP
local UnitIsUnit = UnitIsUnit
local UnitClass = UnitClass
local _, PLAYER_CLASS = UnitClass("player")

local defaults, GetFont, GetNPOutline = I.defaults, I.GetFont, I.GetNPOutline
local HP_BAR_SLOTS, SetFSFont = I.HP_BAR_SLOTS, I.SetFSFont
local GetHealthBarWidth = I.GetHealthBarWidth

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-------------------------------------------------------------------------------
--  Lazy-creation helpers for target-only/focus-only UI objects: needed on 1 plate at a time,
--  so building them on every pooled plate wastes memory. Each Ensure* is idempotent.
-------------------------------------------------------------------------------
local GLOW_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\background.png"
local GLOW_MARGIN = 0.48
local GLOW_CORNER = 12
local GLOW_EXTEND = 6

local function EnsureGlow(plate)
    if plate.glow then return end
    plate.glowFrame = CreateFrame("Frame", nil, plate)
    plate.glowFrame:SetFrameStrata("BACKGROUND")
    plate.glowFrame:SetFrameLevel(1)
    plate.glowFrame:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    plate.glowFrame:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    -- Glow tint/opacity come from the target "Glow Color" setting; textures are collected so ApplyTarget can recolor them live.
    plate.glowTextures = {}
    local gc = ns.GetTargetGlowColor()
    local ga = ns.GetTargetGlowAlpha()
    local function MkTex()
        local t = plate.glowFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW_TEX)
        t:SetVertexColor(gc.r, gc.g, gc.b, ga)
        t:SetBlendMode("ADD")
        plate.glowTextures[#plate.glowTextures + 1] = t
        return t
    end
    plate.glowTL = MkTex(); plate.glowTL:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowTL:SetPoint("TOPLEFT"); plate.glowTL:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowTR = MkTex(); plate.glowTR:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowTR:SetPoint("TOPRIGHT"); plate.glowTR:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    plate.glowBL = MkTex(); plate.glowBL:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowBL:SetPoint("BOTTOMLEFT"); plate.glowBL:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowBR = MkTex(); plate.glowBR:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowBR:SetPoint("BOTTOMRIGHT"); plate.glowBR:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    plate.glowTop = MkTex(); plate.glowTop:SetHeight(GLOW_CORNER); plate.glowTop:SetPoint("TOPLEFT", plate.glowTL, "TOPRIGHT"); plate.glowTop:SetPoint("TOPRIGHT", plate.glowTR, "TOPLEFT"); plate.glowTop:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowBottom = MkTex(); plate.glowBottom:SetHeight(GLOW_CORNER); plate.glowBottom:SetPoint("BOTTOMLEFT", plate.glowBL, "BOTTOMRIGHT"); plate.glowBottom:SetPoint("BOTTOMRIGHT", plate.glowBR, "BOTTOMLEFT"); plate.glowBottom:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowLeft = MkTex(); plate.glowLeft:SetWidth(GLOW_CORNER); plate.glowLeft:SetPoint("TOPLEFT", plate.glowTL, "BOTTOMLEFT"); plate.glowLeft:SetPoint("BOTTOMLEFT", plate.glowBL, "TOPLEFT"); plate.glowLeft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glowRight = MkTex(); plate.glowRight:SetWidth(GLOW_CORNER); plate.glowRight:SetPoint("TOPRIGHT", plate.glowTR, "BOTTOMRIGHT"); plate.glowRight:SetPoint("BOTTOMRIGHT", plate.glowBR, "TOPRIGHT"); plate.glowRight:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    -- Center fill: covers the gap between top/bottom edges inside the health bar
    plate.glowCenter = MkTex(); plate.glowCenter:SetPoint("TOPLEFT", plate.glowLeft, "TOPRIGHT"); plate.glowCenter:SetPoint("BOTTOMRIGHT", plate.glowRight, "BOTTOMLEFT"); plate.glowCenter:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glow = plate.glowFrame
    plate.glowFrame:Hide()
end

-- Execute Pulse Glow (Extras, default off): red glow around the health bar pulsing while the
-- unit is inside the PLAYER'S execute window (health fraction below which their spec's execute
-- becomes usable; per-spec, talent-adjusted, table below). A no-execute spec disables the
-- feature outright: no frame/texture/animation/per-update work. Secret-value design: the
-- below-threshold gate is a C_CurveUtil color curve evaluated C-side by UnitHealthPercent,
-- feeding SetVertexColor (accepts secret components) directly, so Lua never branches on health.
-- The pulse is a looping C-side Alpha animation (no Lua ticks), so it renders identically inside
-- and outside restricted (secret) combat. Frame alpha (pulse) and texture vertex alpha (gate)
-- are separate channels that multiply, so they never fight. Cache lives in a do-block (no
-- main-chunk local slots, near-cap file).
do
    -- Execute windows by SPEC ID: requires = gate spell ids (none = no execute at all);
    -- base = health fraction once gated; talents = ids that RAISE the window (any one enough);
    -- talentPct = the raised fraction. A spec absent from this table has no execute; inert.
    -- Keyed by id, never by localized name.
    local EXEC = {
        [252] = { base = 0.35 },  -- Death Knight: Unholy only
        -- Hunter: Marksmanship always; Beast Mastery needs its gate talent; Survival has none.
        [253] = { requires = { 466930 }, base = 0.20 },
        [254] = { base = 0.20 },
        [63]  = { base = 0.30 },  -- Mage: Fire only
        -- Monk/Rogue: DISABLED (entries removed, both absent from EXEC_CLASSES below). To
        -- restore: Monk gate 322113/base 0.15 all specs; Rogue (Assassination) gate 381798/base 0.35.
        -- Priest: all three specs.
        [256] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        [257] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        [258] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        -- Warlock: Affliction (Drain Soul gate) and Destruction (Shadowburn gate); Demonology none.
        [265] = { requires = { 388667 }, base = 0.20 },
        [267] = { requires = { 17877 }, base = 0.20 },
        -- Warrior: all three specs; either talent raises the window.
        [71]  = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        [72]  = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        [73]  = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        -- No entries for Demon Hunter, Druid, Evoker, Paladin or Shaman.
    }
    -- Classes with at least one execute spec; everyone else never registers the watcher (threshold
    -- stays nil all session, every entry point early-outs on one upvalue read). Must stay in step
    -- with EXEC -- a class listed here with no specs there registers a watcher for nothing.
    local EXEC_CLASSES = {
        DEATHKNIGHT = true, HUNTER = true, MAGE = true,
        PRIEST = true, WARLOCK = true, WARRIOR = true,
        -- MONK = true,
        -- ROGUE = true,
    }

    local threshold = nil     -- current execute fraction; nil = no execute
    local lowCurve, curveAt   -- cached curve + the threshold it was built for

    local function AnyKnown(ids)
        local sb = C_SpellBook
        if not (sb and sb.IsSpellKnown) then return false end
        for i = 1, #ids do
            if sb.IsSpellKnown(ids[i]) then return true end
        end
        return false
    end

    local function Resolve()
        local specID = EllesmereUI._specID
        if (not specID or specID == 0) and EllesmereUI._RefreshSpecID then
            EllesmereUI._RefreshSpecID()
            specID = EllesmereUI._specID
        end
        local def = specID and EXEC[specID]
        if not def then return nil end
        -- Gate first: an unmet requirement means no execute exists at all.
        if def.requires and not AnyKnown(def.requires) then return nil end
        local pct = def.base
        if def.talents and AnyKnown(def.talents) then
            if not pct or def.talentPct > pct then pct = def.talentPct end
        end
        return pct
    end

    --- The player's current execute-window fraction, or nil when this spec
    --- and talent build has no execute (feature fully disabled).
    function ns.GetExecuteThreshold()
        return threshold
    end

    function ns.GetLowHpGlowCurve()
        local t = threshold
        if not t then return nil end
        if lowCurve and curveAt == t then return lowCurve end
        if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent) then return nil end
        local curve = C_CurveUtil.CreateColorCurve()
        local EPSILON = 0.0001
        -- At or below the execute threshold -> red; above -> BLACK, which contributes
        -- nothing under the glow textures' ADD blend, so the glow disappears. Alpha
        -- stays 1 at every point and only RGB varies: curve alpha interpolation is
        -- deliberately never relied on. Rebuilt only when the threshold itself changes.
        curve:AddPoint(0.0, CreateColor(1, 0, 0, 1))
        curve:AddPoint(t, CreateColor(1, 0, 0, 1))
        curve:AddPoint(t + EPSILON, CreateColor(0, 0, 0, 1))
        curve:AddPoint(1.0, CreateColor(0, 0, 0, 1))
        lowCurve, curveAt = curve, t
        return curve
    end

    -- Spec + talent watcher, built ONLY for a class that can have an execute. Talents cannot
    -- change in combat, so these events cost nothing at runtime.
    do
        local _, cls = UnitClass("player")
        if EXEC_CLASSES[cls] then
            local watcher = CreateFrame("Frame")
            watcher:RegisterEvent("PLAYER_LOGIN")
            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
            watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
            watcher:SetScript("OnEvent", function()
                local new = Resolve()
                if new == threshold then return end
                threshold = new
                lowCurve, curveAt = nil, nil
                -- Re-apply per plate: the gate creates/tears down the whole effect, so
                -- gaining/losing an execute flips the glow with no settings change.
                if ns.plates and ns.ApplyLowHpGlow then
                    for _, plate in pairs(ns.plates) do
                        ns.ApplyLowHpGlow(plate)
                    end
                end
            end)
        end
    end
end

function ns.EnsureLowHpGlow(plate)
    if plate.lowHpGlowFrame then return end
    local f = CreateFrame("Frame", nil, plate)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    f:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    f:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    plate.lowHpGlowFrame = f
    local texs = {}
    plate.lowHpGlowTextures = texs
    local function MkTex()
        local t = f:CreateTexture(nil, "BACKGROUND")
        -- Dedicated art (not the shared target-glow texture) so brightness can be tuned without touching the target glow.
        t:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\execute-glow.png")
        t:SetVertexColor(0, 0, 0, 1)  -- black = invisible under ADD blend until the first health eval
        t:SetBlendMode("ADD")
        texs[#texs + 1] = t
        return t
    end
    -- Same 9-slice layout as the target glow (EnsureGlow) so the two effects share one visual language.
    local tl = MkTex(); tl:SetSize(GLOW_CORNER, GLOW_CORNER); tl:SetPoint("TOPLEFT"); tl:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    local tr = MkTex(); tr:SetSize(GLOW_CORNER, GLOW_CORNER); tr:SetPoint("TOPRIGHT"); tr:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    local bl = MkTex(); bl:SetSize(GLOW_CORNER, GLOW_CORNER); bl:SetPoint("BOTTOMLEFT"); bl:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local br = MkTex(); br:SetSize(GLOW_CORNER, GLOW_CORNER); br:SetPoint("BOTTOMRIGHT"); br:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    local top = MkTex(); top:SetHeight(GLOW_CORNER); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT"); top:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    local bot = MkTex(); bot:SetHeight(GLOW_CORNER); bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT"); bot:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local lft = MkTex(); lft:SetWidth(GLOW_CORNER); lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT"); lft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local rgt = MkTex(); rgt:SetWidth(GLOW_CORNER); rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT"); rgt:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local ctr = MkTex(); ctr:SetPoint("TOPLEFT", lft, "TOPRIGHT"); ctr:SetPoint("BOTTOMRIGHT", rgt, "BOTTOMLEFT"); ctr:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    -- Pulse: C-side alpha loop on the frame; only advances while shown.
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.55)
    a:SetSmoothing("IN_OUT")
    plate.lowHpGlowPulse = ag
end

function ns.ApplyLowHpGlow(plate)
    -- Two hard gates: setting on AND spec/talents have an execute window. Failing either,
    -- nothing is created; the health-update eval short-circuits on a nil texture list.
    if not (p and p.lowHpGlow == true) or not ns.GetExecuteThreshold() then
        if plate.lowHpGlowFrame then
            plate.lowHpGlowPulse:Stop()
            plate.lowHpGlowFrame:Hide()
        end
        -- Own flag mirrors the frame's shown state (this function is its only
        -- toggler) so the per-tick health paint reads a field, not IsShown().
        plate._lowHpGlowOn = nil
        return
    end
    ns.EnsureLowHpGlow(plate)
    plate.lowHpGlowFrame:Show()
    plate._lowHpGlowOn = true
    if not plate.lowHpGlowPulse:IsPlaying() then plate.lowHpGlowPulse:Play() end
end

-- Near-aggro glow (Non-Tank Threat cog): the execute glow's exact 9-slice
-- visual -- same art, extend, corner geometry, ADD blend -- at STATIC
-- full-alpha red: no pulse animation and no health curve. Visibility alone is
-- the signal, driven from UpdateHealthColor's own Near Aggro color decision
-- (clean threat booleans, so it behaves identically in and out of restriction).
function ns.EnsureNearAggroGlow(plate)
    if plate.naGlowFrame then return end
    local f = CreateFrame("Frame", nil, plate)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    f:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    f:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    f:Hide()
    plate.naGlowFrame = f
    local function MkTex()
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\execute-glow.png")
        t:SetVertexColor(1, 0, 0, 1)  -- static execute red, full alpha
        t:SetBlendMode("ADD")
        return t
    end
    local tl = MkTex(); tl:SetSize(GLOW_CORNER, GLOW_CORNER); tl:SetPoint("TOPLEFT"); tl:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    local tr = MkTex(); tr:SetSize(GLOW_CORNER, GLOW_CORNER); tr:SetPoint("TOPRIGHT"); tr:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    local bl = MkTex(); bl:SetSize(GLOW_CORNER, GLOW_CORNER); bl:SetPoint("BOTTOMLEFT"); bl:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local br = MkTex(); br:SetSize(GLOW_CORNER, GLOW_CORNER); br:SetPoint("BOTTOMRIGHT"); br:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    local top = MkTex(); top:SetHeight(GLOW_CORNER); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT"); top:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    local bot = MkTex(); bot:SetHeight(GLOW_CORNER); bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT"); bot:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local lft = MkTex(); lft:SetWidth(GLOW_CORNER); lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT"); lft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local rgt = MkTex(); rgt:SetWidth(GLOW_CORNER); rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT"); rgt:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local ctr = MkTex(); ctr:SetPoint("TOPLEFT", lft, "TOPRIGHT"); ctr:SetPoint("BOTTOMRIGHT", rgt, "BOTTOMLEFT"); ctr:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
end

-- Highlight target style: translucent wash across the target's health bar. Lazy (only the
-- target ever shows it), kept SEPARATE from plate.highlight (mouseover) so the two never fight.
local function EnsureTargetHighlight(plate)
    if plate.targetHighlight then return end
    -- Blizzard Style: under the stock selection ring and deselected overlay
    -- (OVERLAY 4/5), still above the fill; the EUI and classic looks keep it on top.
    local t = plate.health:CreateTexture(nil, "OVERLAY", nil, ns.NP_Style() == "blizzard" and 0 or 5)
    t:SetAllPoints(plate.health)
    local c = ns.GetTargetHighlightColor()
    t:SetColorTexture(c.r, c.g, c.b, ns.GetTargetHighlightAlpha())
    t:Hide()
    plate.targetHighlight = t
    -- Blizzard Style: inside the stock bar shape like the fill.
    if plate._blizzBarMask then
        t:AddMaskTexture(plate._blizzBarMask)
        plate._blizzMaskedTarget = true
    end
    ns.NP_ApplyRounding(plate, "health")
end

-- Target arrow styles: key -> { l=left texture, r=right texture, w=drawn width at height 16
-- (scale 1), label }. All source art is 66px tall; w = round(nativeWidth * 11/36): 36->11,
-- 72->22, 90->28. Height always 16. Shared by enemy/friendly plates + options.
ns.TARGET_ARROW_DIR = "Interface\\AddOns\\EllesmereUINameplates\\Media\\Arrows\\"
ns.TARGET_ARROW_STYLES = {
    simple    = { l = "arrow_left",      r = "arrow_right",      w = 11, label = "Simple Arrows" },
    double    = { l = "arrow_leftx2",    r = "arrow_rightx2",    w = 22, label = "Double Arrows" },
    barbed    = { l = "barbed-left",     r = "barbed-right",     w = 28, label = "Barbed" },
    bracket   = { l = "bracket-left",    r = "bracket-right",    w = 22, label = "Bracket" },
    celestial = { l = "celestial-left",  r = "celestial-right",  w = 28, label = "Celestial" },
    classic   = { l = "classic-left",    r = "classic-right",    w = 22, label = "Classic" },
    crystal   = { l = "crystal-left",    r = "crystal-right",    w = 22, label = "Crystal" },
    curved    = { l = "curved-left",     r = "curved-right",     w = 22, label = "Curved" },
    demon     = { l = "demon-left",      r = "demon-right",      w = 28, label = "Demon" },
    diamond   = { l = "diamond-left",    r = "diamond-right",    w = 28, label = "Diamond" },
    feathered = { l = "feathered-left",  r = "feathered-right",  w = 22, label = "Feathered" },
    halo      = { l = "halo-left",       r = "halo-right",       w = 22, label = "Halo" },
    holyspear = { l = "holy-spear-left", r = "holy-spear-right", w = 28, label = "Holy Spear" },
    rune      = { l = "rune-left",       r = "rune-right",       w = 22, label = "Rune" },
    split     = { l = "split-left",      r = "split-right",      w = 22, label = "Split" },
    winged    = { l = "winged-left",     r = "winged-right",     w = 28, label = "Winged" },
}
ns.TARGET_ARROW_ORDER = {
    "simple", "double", "winged", "feathered", "split", "celestial", "rune", "demon",
    "halo", "curved", "barbed", "holyspear", "bracket", "diamond", "crystal", "classic",
}

-- Resolve a profile to its arrow style table. targetArrowStyle is the current key; legacy profiles fall back to targetArrowDouble (then Simple).
function ns.ResolveTargetArrowStyle(prof)
    local key = prof and (prof.targetArrowStyle or (prof.targetArrowDouble and "double")) or nil
    return ns.TARGET_ARROW_STYLES[key] or ns.TARGET_ARROW_STYLES.simple
end

-- Target arrow tint: the player's class color when targetArrowClassColor is on, else the custom targetArrowColor (default white).
function ns.GetTargetArrowColor(prof)
    if prof and prof.targetArrowClassColor then
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[PLAYER_CLASS]
        if cc then return cc.r, cc.g, cc.b end
        return 1, 1, 1
    end
    local c = prof and prof.targetArrowColor
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function EnsureArrows(plate)
    if plate.leftArrow then return end
    local st = ns.ResolveTargetArrowStyle(p)
    local sc = (p and p.targetArrowScale) or 1.0
    local aw, ah = math.floor(st.w * sc + 0.5), math.floor(16 * sc + 0.5)
    -- Regions OF the health bar (the plate subtree is aspect-restricted and unmeasurable). NO
    -- creation anchors: single-point + size rects render DISPLACED inside the restricted tree,
    -- so the only sanctioned form is the fully-anchored TOP+BOTTOM scheme from
    -- PositionArrowsOutsideAuras (runs on every target apply, after Show()). An unanchored
    -- hidden texture has no rect and draws nothing, so the creation state is safe. Rendering
    -- outside the bar rect is fine (health SetClipsChildren(false)).
    local arrowParent = plate.health
        -- Aura containers carry UntrustedLayoutScriptExecution once they hold a group, and only
        -- aspect-bearing objects may anchor to them. Aspects cannot be gained later
        -- (SetParent/SetPoint inheritance is blocked), so arrows must be BORN inside a template
        -- holder to inherit its aspect; the containers file then anchors them to the side aura
        -- containers. Clients without the template keep the plain parent (no aspect needed).
        local ok, holder = pcall(CreateFrame, "Frame", nil, plate.health,
            "DisableUntrustedLayoutScriptsTemplate")
        if ok and holder then
            holder:SetAllPoints(plate.health)
            holder:SetFrameLevel(plate.health:GetFrameLevel())
            plate.arrowHost = holder
            arrowParent = holder
        end
    plate.leftArrow = arrowParent:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.l .. ".png")
    plate.rightArrow = arrowParent:CreateTexture(nil, "OVERLAY")
    plate.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.r .. ".png")
    PP.Size(plate.leftArrow, aw, ah)
    plate.leftArrow:Hide()
    PP.Size(plate.rightArrow, aw, ah)
    plate.rightArrow:Hide()
end

-- Target/Focus overlay textures: stripe overlays live in the nameplates Media folder (resolved
-- by name); everything else resolves through the shared health-bar lookup (EUI + SharedMedia).
ns.OVERLAY_STRIPE_KEYS = {
    ["striped-v2"] = true, ["striped-wide-v2"] = true, ["stripes-medium"] = true,
    ["stripes-small-close"] = true, ["stripes-small-spread"] = true, ["striped-tiny"] = true,
}
function ns.ResolveOverlayTexPath(key)
    if not key or key == "none" then return nil end
    if ns.OVERLAY_STRIPE_KEYS[key] then
        return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
    end
    if EllesmereUI.ResolveTexturePath then
        return EllesmereUI.ResolveTexturePath(ns.healthBarTextures, key, "Interface\\Buttons\\WHITE8x8")
    end
    return nil
end

-- Both overlays span the full bar width (anchored LEFT+RIGHT to the health bar) so the pattern
-- covers the whole bar and follows Health Bar Width changes. Fill and bg share identical
-- geometry so a stripe's diagonal stays continuous across the fill/background split; clip
-- frames window the filled vs empty portions. Stripes additionally CROP via texcoord to the
-- bar's share of the pattern's native 200px span (constant density up to 200 wide, wider bars
-- stretch the full pattern). Width comes from settings, never from measuring the plate subtree
-- (restricted regions forbid reads there).
local STRIPE_NATIVE_W = 200
local function ApplyOverlayGeometry(fillT, bgT, health, isStripe)
    fillT:ClearAllPoints(); bgT:ClearAllPoints()
    fillT:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    fillT:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    fillT:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    bgT:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    bgT:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    bgT:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    local u = 1
    if isStripe then
        u = GetHealthBarWidth() / STRIPE_NATIVE_W
        if u > 1 then u = 1 end
    end
    fillT:SetTexCoord(0, u, 0, 1)
    bgT:SetTexCoord(0, u, 0, 1)
end

-- Alpha for the empty (background) portion of an overlay. The "Full alpha on empty part of
-- bar" toggle matches the filled portion's opacity; else dimmed to 30% so fill reads as "more filled".
local function OverlayBgAlpha(fullFlag, fillAlpha)
    if fullFlag then return fillAlpha end
    return fillAlpha * 0.3
end

local function EnsureFocusOverlay(plate)
    if plate.focusClipFill then return end
    local overlayAlpha = (p and p.focusOverlayAlpha) or defaults.focusOverlayAlpha
    local overlayColor = (p and p.focusOverlayColor) or defaults.focusOverlayColor
    local STRIPE_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\striped-v2.png"
    local fillTex = plate.health:GetStatusBarTexture()
    plate.focusClipFill = CreateFrame("Frame", nil, plate.health)
    plate.focusClipFill:SetClipsChildren(true)
    -- Vertical bounds come from the health bar itself so the overlay never pixel-snaps 1px short; only the RIGHT edge tracks the fill.
    plate.focusClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.focusClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.focusClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.focusOverlayFill = plate.focusClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Full bar height/width (anchored LEFT+RIGHT to health bar) so the diagonal pattern stays continuous across the split and snaps with the clip's edges.
    plate.focusOverlayFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusOverlayFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.focusOverlayFill:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.focusOverlayFill:SetTexture(STRIPE_TEX)
    plate.focusOverlayFill:SetAlpha(overlayAlpha)
    plate.focusOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.focusClipFill:Hide()
    plate.focusClipBg = CreateFrame("Frame", nil, plate.health)
    plate.focusClipBg:SetClipsChildren(true)
    plate.focusClipBg:SetPoint("TOPRIGHT", plate.health, "TOPRIGHT", 0, 0)
    plate.focusClipBg:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.focusClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    plate.focusClipBg:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.focusOverlayBg = plate.focusClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.focusOverlayBg:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusOverlayBg:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.focusOverlayBg:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.focusOverlayBg:SetTexture(STRIPE_TEX)
    plate.focusOverlayBg:SetAlpha(OverlayBgAlpha(p and p.focusOverlayFullBgAlpha, overlayAlpha))
    plate.focusOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(plate.focusOverlayFill, plate.focusOverlayBg, plate.health, true)
    plate.focusClipBg:Hide()
    -- Rounded corners: the new overlay joins the rounded body
    if plate._npRounded then ns.NP_ApplyRounding(plate, "health") end
end

ns.FOCUS_LETTER_ANCHORS = {
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    BOTTOM = true,
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

function ns.GetFocusLetterAnchor(db)
    local anchor = (db and db.focusLetterAnchor) or defaults.focusLetterAnchor
    return ns.FOCUS_LETTER_ANCHORS[anchor] and anchor or defaults.focusLetterAnchor
end

function ns.EnsureFocusLetter(plate)
    if plate.focusLetter then return end
    plate.focusLetter = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    plate.focusLetter:SetJustifyH("CENTER")
    plate.focusLetter:SetJustifyV("MIDDLE")
    plate.focusLetter:Hide()
end

function ns.ApplyFocusLetter(plate, unit, db)
    if db.focusLetterEnabled == true and UnitIsUnit(unit, "focus") then
        ns.EnsureFocusLetter(plate)
        local size = db.focusLetterSize or defaults.focusLetterSize
        local anchor = ns.GetFocusLetterAnchor(db)
        local x = db.focusLetterX or defaults.focusLetterX
        local y = db.focusLetterY or defaults.focusLetterY
        local font = GetFont()
        local outline = GetNPOutline()
        if not plate._focusLetterShown
            or plate._focusLetterSize ~= size
            or plate._focusLetterAnchor ~= anchor
            or plate._focusLetterX ~= x
            or plate._focusLetterY ~= y
            or plate._focusLetterFont ~= font
            or plate._focusLetterOutline ~= outline then
            plate._focusLetterShown = true
            plate._focusLetterSize = size
            plate._focusLetterAnchor = anchor
            plate._focusLetterX = x
            plate._focusLetterY = y
            plate._focusLetterFont = font
            plate._focusLetterOutline = outline
            SetFSFont(plate.focusLetter, size, outline)
            plate.focusLetter:SetText("F")
            plate.focusLetter:ClearAllPoints()
            plate.focusLetter:SetPoint(anchor, plate.health, anchor, x, y)
            plate.focusLetter:SetTextColor(1, 1, 1, 1)
        end
        plate.focusLetter:Show()
    elseif plate.focusLetter then
        plate._focusLetterShown = nil
        plate.focusLetter:Hide()
    end
end

-------------------------------------------------------------------------------
--  Threat % text (WoW Forever only). ns._npTptOn = Forever and the profile
--  toggle, re-derived at login, by RefreshAllSettings and by RefreshThreatPct
--  (every setter of a threatPct key calls it), so UpdateHealthColor pays one
--  field read while it is off. The font string is made on first paint.
--  ns._npTgapOn is the Threat Gap mode on top of it (NP_PaintThreatGap).
-------------------------------------------------------------------------------
ns._npTptOn = false
ns._npTgapOn = false

function ns.NP_RefreshThreatPctFlag()
    ns._npTptOn = EllesmereUI.IS_FOREVER == true and p ~= nil and p.threatPctEnabled == true
    ns._npTgapOn = ns._npTptOn and p.threatPctMode == "gap"
end

function ns.EnsureThreatPctText(plate)
    if plate.threatPctText then return end
    plate.threatPctText = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    plate.threatPctText:SetWordWrap(false)
    plate.threatPctText:Hide()
end

function ns.ApplyThreatPctPos(plate)
    ns.EnsureThreatPctText(plate)
    local db = p or defaults
    local posKey = db.threatPctPosition or defaults.threatPctPosition
    local slot = HP_BAR_SLOTS[(posKey == "RIGHT" and 1) or (posKey == "LEFT" and 2) or 3]
    local size = db.threatPctSize or defaults.threatPctSize
    local xOff = db.threatPctXOffset or defaults.threatPctXOffset
    local yOff = db.threatPctYOffset or defaults.threatPctYOffset
    local font = GetFont()
    local outline = GetNPOutline()
    if plate._tptPos ~= posKey or plate._tptSize ~= size
        or plate._tptX ~= xOff or plate._tptY ~= yOff
        or plate._tptFont ~= font or plate._tptOutline ~= outline then
        plate._tptPos = posKey
        plate._tptSize = size
        plate._tptX = xOff
        plate._tptY = yOff
        plate._tptFont = font
        plate._tptOutline = outline
        SetFSFont(plate.threatPctText, size, outline)
        plate.threatPctText:ClearAllPoints()
        if slot.anchor == "CENTER" then
            plate.threatPctText:SetPoint("CENTER", plate.health, "CENTER", xOff, yOff)
        else
            PP.Point(plate.threatPctText, slot.anchor, plate.health, slot.point, slot.xOff + xOff, yOff)
        end
        plate.threatPctText:SetJustifyH(slot.anchor)
    end
end

-- Percent and status are secret for nameplate units: the percent goes
-- straight to PaintThreatPct, never compared or stored. In Threat Gap mode
-- the target's plate is painted once per frame by the gap flush (gapNow),
-- the gap standing in for the percent while its values read plainly.
function ns.NP_UpdateThreatPct(plate, unit, gapNow)
    if ns._npTgapOn and plate._isTarget and not gapNow then
        ns.NP_RequestThreatGap(plate)
        return
    end
    local show = false
    if ns._npTptOn then
        local isTanking, status, pct = UnitDetailedThreatSituation("player", unit)
        if type(pct) == "number" then
            ns.ApplyThreatPctPos(plate)
            if not (ns._npTgapOn and plate._isTarget and ns.NP_PaintThreatGap(plate.threatPctText)) then
                EllesmereUI.PaintThreatPct(plate.threatPctText, pct, status, isTanking, p.threatPctColorByThreat)
            end
            show = true
        end
    end
    if show ~= (plate._tptShown or false) then
        plate._tptShown = show or nil
        plate.threatPctText:SetShown(show)
    end
end

-------------------------------------------------------------------------------
--  Threat Gap (WoW Forever): the target's plate shows the flat threat between
--  you and the name you are measured against. Nameplate tokens read threat
--  values as secrets, so this reads through "target". Holding aggro: against
--  the next name on the table (group members and pets; your whole threat when
--  you are alone on it). Not holding it: against the holder, read directly when
--  they are in your group (the last holder's token is tried first, so a steady
--  fight costs one query), else from your percent of their threat. The colour
--  says who leads in raw threat. Returns false when a value reads secret, so
--  the caller paints the percent instead. The scan covers the group's own
--  tokens only, and the target plate's repaints run once per frame.
-------------------------------------------------------------------------------
do
    local RAID, PARTY = {}, { "pet" }
    for i = 1, 40 do RAID[#RAID + 1] = "raid" .. i; RAID[#RAID + 1] = "raidpet" .. i end
    for i = 1, 4 do PARTY[#PARTY + 1] = "party" .. i; PARTY[#PARTY + 1] = "partypet" .. i end
    local holderTok  -- the group token that last held aggro on the target
    local flush, pending  -- the once-per-frame repaint (built on first use) and its plate

    -- A frame's threat events collapse into one repaint after them: a hidden
    -- frame shown by the request, its OnUpdate hiding it before the paint.
    function ns.NP_RequestThreatGap(plate)
        pending = plate
        if not flush then
            flush = CreateFrame("Frame")
            flush:SetScript("OnUpdate", function(self)
                self:Hide()
                local pl = pending
                pending = nil
                if pl and pl.unit and pl._isTarget then ns.NP_UpdateThreatPct(pl, pl.unit, true) end
            end)
        end
        flush:Show()
    end

    function ns.NP_PaintThreatGap(fs)
        local isTanking, _, _, rawPct, raw = UnitDetailedThreatSituation("player", "target")
        if issecretvalue(isTanking) or issecretvalue(rawPct) or issecretvalue(raw)
           or type(raw) ~= "number" then
            return false
        end
        local inRaid = IsInRaid()
        local list = inRaid and RAID or PARTY
        -- The group's own tokens: raidN + raidpetN, or pet + partyN + partypetN.
        local n = GetNumGroupMembers()
        local last = inRaid and 2 * n or 1 + 2 * (n > 0 and n - 1 or 0)
        if last > #list then last = #list end
        local other
        if isTanking then
            other = 0
            for i = 1, last do
                local u = list[i]
                if UnitExists(u) then
                    local me = UnitIsUnit(u, "player")
                    if issecretvalue(me) then return false end
                    if not me then
                        local _, _, _, _, r = UnitDetailedThreatSituation(u, "target")
                        if issecretvalue(r) then return false end
                        if r and r > other then other = r end
                    end
                end
            end
        else
            if holderTok then
                local t, _, _, _, r = UnitDetailedThreatSituation(holderTok, "target")
                if issecretvalue(t) or issecretvalue(r) then return false end
                if t then other = r end
            end
            if not other then
                holderTok = nil
                for i = 1, last do
                    local u = list[i]
                    if UnitExists(u) then
                        local t, _, _, _, r = UnitDetailedThreatSituation(u, "target")
                        if issecretvalue(t) or issecretvalue(r) then return false end
                        if t then
                            holderTok, other = u, r
                            break
                        end
                    end
                end
            end
            if not other then
                if type(rawPct) ~= "number" or rawPct <= 0 then return false end
                other = raw * 100 / rawPct
            end
        end
        local gap = raw - other
        local ahead = gap >= 0
        if not ahead then gap = -gap end
        local db = p or defaults
        EllesmereUI.PaintThreatGap(fs, ns.AbbreviateNumbers(math.floor(gap + 0.5)), ahead,
            db.threatPctColorByThreat, db.threatGapAheadColor or defaults.threatGapAheadColor,
            db.threatGapBehindColor or defaults.threatGapBehindColor)
        return true
    end
end

-- Options setters of every threatPct key: the flag, then layout and paint on
-- the live plates only (the layout memo compares every layout input).
function ns.RefreshThreatPct()
    ns.NP_RefreshThreatPctFlag()
    for _, plate in pairs(ns.plates) do
        if plate.unit and (ns._npTptOn or plate._tptShown) then
            ns.NP_UpdateThreatPct(plate, plate.unit)
        end
    end
end

ns.EnsureHoverOverlay = function(plate)
    if plate.hoverClipFill then return end
    local overlayAlpha = (p and p.hoverAlpha) or defaults.hoverAlpha
    local overlayColor = (p and p.hoverColor) or defaults.hoverColor
    local STRIPE_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\striped-v2.png"
    local fillTex = plate.health:GetStatusBarTexture()
    plate.hoverClipFill = CreateFrame("Frame", nil, plate.health)
    plate.hoverClipFill:SetClipsChildren(true)
    plate.hoverClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.hoverClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.hoverClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.hoverClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.hoverOverlayFill = plate.hoverClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.hoverOverlayFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.hoverOverlayFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.hoverOverlayFill:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.hoverOverlayFill:SetTexture(STRIPE_TEX)
    plate.hoverOverlayFill:SetAlpha(overlayAlpha)
    plate.hoverOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.hoverClipFill:Hide()
    plate.hoverClipBg = CreateFrame("Frame", nil, plate.health)
    plate.hoverClipBg:SetClipsChildren(true)
    plate.hoverClipBg:SetPoint("TOPRIGHT", plate.health, "TOPRIGHT", 0, 0)
    plate.hoverClipBg:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.hoverClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    plate.hoverClipBg:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.hoverOverlayBg = plate.hoverClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.hoverOverlayBg:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.hoverOverlayBg:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.hoverOverlayBg:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.hoverOverlayBg:SetTexture(STRIPE_TEX)
    plate.hoverOverlayBg:SetAlpha(OverlayBgAlpha(p and p.hoverOverlayFullBgAlpha, overlayAlpha))
    plate.hoverOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(plate.hoverOverlayFill, plate.hoverOverlayBg, plate.health, true)
    plate.hoverClipBg:Hide()
    -- Rounded corners: the new overlay joins the rounded body
    if plate._npRounded then ns.NP_ApplyRounding(plate, "health") end
end

ns.EnsureTargetOverlay = function(plate)
    if plate.targetClipFill then return end
    local overlayAlpha = (p and p.targetOverlayAlpha) or defaults.targetOverlayAlpha
    local overlayColor = (p and p.targetOverlayColor) or defaults.targetOverlayColor
    local STRIPE_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\striped-v2.png"
    local fillTex = plate.health:GetStatusBarTexture()
    plate.targetClipFill = CreateFrame("Frame", nil, plate.health)
    plate.targetClipFill:SetClipsChildren(true)
    -- Vertical bounds come from the health bar itself so the overlay never pixel-snaps 1px short; only the RIGHT edge tracks the fill.
    plate.targetClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.targetClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.targetClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.targetClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.targetOverlayFill = plate.targetClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Full bar height/width (anchored LEFT+RIGHT to health bar) so the diagonal pattern stays continuous across the split and snaps with the clip's edges.
    plate.targetOverlayFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.targetOverlayFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.targetOverlayFill:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.targetOverlayFill:SetTexture(STRIPE_TEX)
    plate.targetOverlayFill:SetAlpha(overlayAlpha)
    plate.targetOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.targetClipFill:Hide()
    plate.targetClipBg = CreateFrame("Frame", nil, plate.health)
    plate.targetClipBg:SetClipsChildren(true)
    plate.targetClipBg:SetPoint("TOPRIGHT", plate.health, "TOPRIGHT", 0, 0)
    plate.targetClipBg:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.targetClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    plate.targetClipBg:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.targetOverlayBg = plate.targetClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.targetOverlayBg:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.targetOverlayBg:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.targetOverlayBg:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.targetOverlayBg:SetTexture(STRIPE_TEX)
    plate.targetOverlayBg:SetAlpha(OverlayBgAlpha(p and p.targetOverlayFullBgAlpha, overlayAlpha))
    plate.targetOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(plate.targetOverlayFill, plate.targetOverlayBg, plate.health, true)
    plate.targetClipBg:Hide()
    -- Rounded corners: the new overlay joins the rounded body
    if plate._npRounded then ns.NP_ApplyRounding(plate, "health") end
end

-------------------------------------------------------------------------------
--  Color Casting Enemies: two tints over the health fill (the bar's own texture in each
--  color), Interruptible drawn above Uninterruptible so it wins once both were seen. The
--  plate remembers each kind as an alpha, folded C-side from the cast's interruptible flag
--  (SECRET in restricted combat): only ever passed to SetAlpha, never read in Lua.
-------------------------------------------------------------------------------
local CAST_INT_KEYS = { Normal = "castingIntNormal", Elite = "castingIntElite",
    MiniBoss = "castingIntMiniBoss", Boss = "castingIntBoss" }
local CAST_UNINT_KEYS = { Normal = "castingUnintNormal", Elite = "castingUnintElite",
    MiniBoss = "castingUnintMiniBoss", Boss = "castingUnintBoss" }

local function LayoutCastTint(t, fill, path)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    t:SetTexture(path)
end

-- Anchors and texture follow the fill, which a health texture swap replaces.
function ns.NP_LayoutCastTints(plate)
    local fill = plate.health:GetStatusBarTexture()
    local key = (p and p.healthBarTexture) or defaults.healthBarTexture
    local path = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, key, "Interface\\Buttons\\WHITE8x8")
    LayoutCastTint(plate.castTintUnint, fill, path)
    LayoutCastTint(plate.castTintInt, fill, path)
end

-- Bumped on settings changes (RefreshAllSettings, the options' RefreshAllPlates): each plate
-- repaints its tint colors once when its gen is stale.
local castTintGen = 0
function ns.NP_CastTintsDirty() castTintGen = castTintGen + 1 end

local function EnsureCastTints(plate)
    if plate.castTintInt then return end
    local health = plate.health
    plate.castTintUnint = health:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.castTintInt = health:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.castTintUnint:AddMaskTexture(plate._absorbMask)
    plate.castTintInt:AddMaskTexture(plate._absorbMask)
    plate.castTintUnint:Hide()
    plate.castTintInt:Hide()
    plate._castIntOn, plate._castUnintOn = false, false
    ns.NP_LayoutCastTints(plate)
    if plate._blizzBarMask then ns.NP_ApplyBlizzBarArt(plate) end
    if plate._npRounded then ns.NP_ApplyRounding(plate, "health") end
end

local function TierOn(keys, tier)
    local v = p and p[keys[tier]]
    if v == nil then v = defaults[keys[tier]] end
    return v == true
end

-- tier: the mob type GetReactionColor marked (ns._reactionCastTier), nil to hide. lit: the unit
-- is plainly in combat (ns._reactionCastLit); else the colors darken like the bar's own
-- (Modify Out of Combat). fold: UpdateHealthColor folded the bar to Off-Tank Aggro (the answer
-- is SECRET); the tints take the same fold. Runs on every health color pass, so each setter
-- is change-checked, except while folded (secret colors, like the bar's own).
function ns.NP_ApplyCastTints(plate, tier, lit, fold)
    if tier == nil and not (p and p.castingEnemyColors) then
        -- Turned off: the plate forgets its casts, so its color passes stop calling here.
        plate._castSeen, plate._castIntA, plate._castUnintA = nil, nil, nil
    end
    local intOn = tier ~= nil and TierOn(CAST_INT_KEYS, tier)
    local unintOn = tier ~= nil and TierOn(CAST_UNINT_KEYS, tier)
    local ti, tu = plate.castTintInt, plate.castTintUnint
    if intOn or unintOn then
        if not ti then
            EnsureCastTints(plate)
            ti, tu = plate.castTintInt, plate.castTintUnint
            ti:SetAlpha(plate._castIntA or 0)
            tu:SetAlpha(plate._castUnintA or 0)
        end
        -- Folded: only the shown tints, each recomputed every pass (secret, uncached).
        -- A hidden one keeps a stale color; the gen reset below repaints it on the next
        -- plain pass.
        local folded = false
        if fold then
            local MaybeDarken = I.MaybeDarken
            local otc = I._C("offTankAggro")
            local ok = true
            if intOn then
                local c = (p and p.castingIntColor) or defaults.castingIntColor
                local r, g, b = MaybeDarken(c.r, c.g, c.b, lit)
                local okI
                okI, r, g, b = ns.ComputeOffTankFold(plate.unit, r, g, b, otc.r, otc.g, otc.b)
                if okI then ti:SetVertexColor(r, g, b) else ok = false end
            end
            if ok and unintOn then
                local c = (p and p.castingUnintColor) or defaults.castingUnintColor
                local r, g, b = MaybeDarken(c.r, c.g, c.b, lit)
                local okU
                okU, r, g, b = ns.ComputeOffTankFold(plate.unit, r, g, b, otc.r, otc.g, otc.b)
                if okU then tu:SetVertexColor(r, g, b) else ok = false end
            end
            -- Never cached: the next plain pass always repaints.
            plate._castTintGen = nil
            folded = ok
        end
        if not folded and (plate._castTintGen ~= castTintGen or plate._castTintLit ~= lit) then
            plate._castTintGen, plate._castTintLit = castTintGen, lit
            local MaybeDarken = I.MaybeDarken
            local ic = (p and p.castingIntColor) or defaults.castingIntColor
            local uc = (p and p.castingUnintColor) or defaults.castingUnintColor
            ti:SetVertexColor(MaybeDarken(ic.r, ic.g, ic.b, lit))
            tu:SetVertexColor(MaybeDarken(uc.r, uc.g, uc.b, lit))
        end
    elseif not ti then
        return
    end
    if plate._castIntOn ~= intOn then plate._castIntOn = intOn; ti:SetShown(intOn) end
    if plate._castUnintOn ~= unintOn then plate._castUnintOn = unintOn; tu:SetShown(unintOn) end
end

-- A cast's start or interruptible flip (kickProtected: true = cannot be interrupted, maybe
-- SECRET). Each kind's alpha turns 1 once seen and stays 1 while the mob holds the plate;
-- the alphas change only here.
function ns.NP_NoteCastKind(plate, kickProtected)
    local eval = C_CurveUtil.EvaluateColorValueFromBoolean
    -- _castSeen: nil = not checked yet, false = a player (never tinted), true = noted.
    local seen = plate._castSeen
    if seen == false then return end
    local first = seen == nil
    if first then
        -- Never players (an enemy player's class color stays); checked once per unit.
        if UnitIsPlayer(plate.unit) then plate._castSeen = false; return end
        plate._castSeen = true
        plate._castIntA, plate._castUnintA = 0, 0
    end
    plate._castIntA = eval(kickProtected, plate._castIntA, 1)
    plate._castUnintA = eval(kickProtected, 1, plate._castUnintA)
    if plate.castTintInt then
        plate.castTintInt:SetAlpha(plate._castIntA)
        plate.castTintUnint:SetAlpha(plate._castUnintA)
    end
    if first then plate:UpdateHealthColor() end
end

-- The plate's unit left (ClearUnit) or changed (the token swap): forget its casts.
function ns.NP_ResetCastKind(plate)
    plate._castSeen, plate._castIntA, plate._castUnintA = nil, nil, nil
    ns.NP_ApplyCastTints(plate, nil)
end

I.ApplyOverlayGeometry, I.EnsureArrows = ApplyOverlayGeometry, EnsureArrows
I.EnsureFocusOverlay, I.EnsureGlow = EnsureFocusOverlay, EnsureGlow
I.EnsureTargetHighlight, I.OverlayBgAlpha = EnsureTargetHighlight, OverlayBgAlpha
I.broken = false
