if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_HealthAnimations.lua
--  Health Animations: a damage animation (the lost piece of health stays, then
--  shrinks, slides, falls, fades, is thrown off or breaks into chips) and a heal
--  animation (the gained piece shows in the heal color, then the bar color
--  slides over it or the heal color fades) on nameplate and raid or party
--  health bars. A feature of EllesmereUI.HealthBars: nothing is registered or
--  built for a place until its Damage Animation or Heal Animation is on.
--
--  Health and max health are secret values: no Lua math or compare touches
--  them, they only reach SetMinMaxValues / SetValue. A hit cannot be told from
--  a heal, so every change makes one "piece" that carries both looks, and clip
--  frames leave only the one that fits (the lost part sits between the live fill
--  edge and the "before" edge, the gained part between the "before" edge and the
--  live edge). Each piece owns two hidden StatusBars (after = new health, before
--  = old health) whose fill edges are the anchors. Motion runs on
--  AnimationGroups. The per-bar state lives in weak tables, never on a bar.
--
--  Drawing API: Reset(bar, cur, maxHP, keep) on a new unit or max health;
--  Change(bar, cur, style, smooth, overLvl, belowLvl, maxHP) on a real health
--  change; Sync(bar, cur) on any other paint; Hide(bar); MakeStyle(src, old,
--  defaults); Hit(bar, style, crit, mine) and Crit(bar, style) for a hit that
--  was a critical strike and/or the player's own (its piece takes the crit and
--  My Damage colors).
--  Settings: the active profile's healthAnimations table (see GetLook, PlaceOn).
--------------------------------------------------------------------------------
local EllesmereUI = EllesmereUI
local HB = EllesmereUI.HealthBars

local HTr = {}
EllesmereUI.HealthAnimations = HTr

local PP = EllesmereUI.PP
local random = math.random
local pairs, ipairs, type, tonumber, next = pairs, ipairs, type, tonumber, next
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local issecretvalue = issecretvalue or function() return false end

-- Per-bar state, keyed by the bar (weak: a bar is never collected anyway).
local STATE = setmetatable({}, { __mode = "k" })

local WHITE = "Interface\\Buttons\\WHITE8x8"
local POOL = 12          -- pieces per bar in turn; when full the next one is recycled
local SMOOTH_LIFE = 0.9  -- seconds a smooth-fill heal piece waits for the fill to arrive
local SCALE_END = 0.001  -- a Scale animation cannot end at exactly 0
local CRIT_WINDOW = 0.15 -- seconds a crit event and its health paint may be apart

-- Every frame below the base draws at the base's own level (a new child is
-- otherwise one level above its parent), so the whole animation sits at one
-- known level against the absorb overlays and the Health Ticks marks.
local function Flat(f)
    if f.SetUsingParentLevel then f:SetUsingParentLevel(true) end
    return f
end

-------------------------------------------------------------------------------
--  Settings: the active profile's healthAnimations table, sparse (a missing key
--  means the default). { plates = { [lookKey] = v }, frames = { [lookKey] = v },
--  places = { [placeId] = { dmg = true, heal = true } } }. "plates" is the look
--  of enemy and friendly nameplates, "frames" of raid and party frames.
-------------------------------------------------------------------------------
local function ActiveProfile()
    local db = EllesmereUIDB
    local profiles = db and db.profiles
    return profiles and profiles[db.activeProfile or "Default"]
end

-- The saved table; nil until the active profile exists. A read never writes
-- (create = true is for writers).
function EllesmereUI.GetHealthAnimationsDB(create)
    local active = ActiveProfile()
    if not active then return nil end
    if create and not active.healthAnimations then active.healthAnimations = {} end
    return active.healthAnimations
end
local GetDB = EllesmereUI.GetHealthAnimationsDB

-- Look keys and defaults. Sizes and distances are 1080p pixels.
local DEFAULTS_FRAMES = {
    healthTrailStyle = "shrink",   -- shrink, slide, fall, fade, chip, crumble
    healthTrailEase = "OUT",       -- NONE, IN, OUT, IN_OUT (chip: not used)
    healthTrailWait = 400,         -- ms
    healthTrailMove = 450,         -- ms
    healthTrailFall = 16,          -- pixels below the bar (fall, chip, crumble)
    healthTrailPop = 10,           -- chip: jump height
    healthTrailTilt = 35,          -- chip: degrees over the flight
    healthTrailDrift = 12,         -- chip: sideways
    healthTrailVary = true,        -- chip: each piece jumps, tilts and drifts 0.7 to 1.3 times as far
    healthTrailChipSize = 6,       -- crumble: chip side (1 to 4 rows)
    healthTrailChipCols = 16,      -- crumble: most chips across
    healthTrailSpread = 8,         -- crumble: sideways spread
    healthTrailSpin = 120,         -- crumble: most degrees a chip turns
    healthTrailStagger = 160,      -- crumble: ms, the latest a chip starts after the wait
    healthTrailColor = { r = 0.949, g = 0.757, b = 0.306 },
    healthTrailCrit = false,       -- a crit hit leaves a piece in the crit color
    healthTrailCritColor = { r = 1, g = 0.32, b = 0.18 },
    healthTrailMine = false,       -- enemy nameplates only: the player's own hits use their own colors
    healthTrailMineColor = { r = 0.35, g = 0.8, b = 1 },
    healthTrailMineCritColor = { r = 0.8, g = 0.45, b = 1 },
    healthTrailAlpha = 100,        -- percent
    healthTrailFlash = 0,          -- ms, 0 = off
    healthTrailGroup = true,
    healthTrailUnderAbsorbs = true, -- draw below the absorb, heal absorb and prediction overlays
    healthTrailHealStyle = "slide", -- slide, fade
    healthTrailHealEase = "OUT",
    healthTrailHealWait = 150,     -- ms
    healthTrailHealMove = 500,     -- ms
    healthTrailHealColor = { r = 0.3, g = 0.85, b = 0.35 },
    healthTrailHealAlpha = 100,    -- percent
}
local DEFAULTS_PLATES = CopyTable(DEFAULTS_FRAMES)
do
    local d = DEFAULTS_PLATES
    d.healthTrailStyle = "chip"
    d.healthTrailEase = "NONE"
    d.healthTrailWait = 150
    d.healthTrailMove = 700
    d.healthTrailFall = 149
    d.healthTrailPop = 23
    d.healthTrailFlash = 80
    d.healthTrailCrit = true
    d.healthTrailMine = true
end
HTr.DEFAULTS_FRAMES, HTr.DEFAULTS_PLATES = DEFAULTS_FRAMES, DEFAULTS_PLATES
local DEFAULTS = { frames = DEFAULTS_FRAMES, plates = DEFAULTS_PLATES }

local KEYS = {}
for k in pairs(DEFAULTS_FRAMES) do KEYS[#KEYS + 1] = k end
table.sort(KEYS)
HTr.KEYS = KEYS

-- healthTrailKept: the options page keeps each style's own values there when
-- the style changes. It has no default.
local function ValidKey(key)
    return DEFAULTS_FRAMES[key] ~= nil or key == "healthTrailKept"
end

local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = CopyValue(x) end
    return c
end

-- The look a place uses: "plates" for nameplates, "frames" for raid and party.
function HTr.SetOf(place)
    local def = HB.PLACE[place]
    return (def and def.group == "plates") and "plates" or "frames"
end

-- The saved value of a look key, else its default. Never write to a color it
-- returns: it can be the default table.
function HTr.GetLook(set, key)
    local db = GetDB()
    local saved = db and db[set]
    local v
    if type(saved) == "table" then v = saved[key] end
    if v == nil then
        local d = DEFAULTS[set]
        v = d and d[key]
    end
    return v
end

local function WriteLook(db, set, key, value)
    local t = db[set]
    if not t then
        t = {}
        db[set] = t
    end
    t[key] = CopyValue(value)
end

function HTr.SetLook(set, key, value)
    if not DEFAULTS[set] or not ValidKey(key) then return end
    local db = GetDB(true)
    if not db then return end
    WriteLook(db, set, key, value)
    HB.QueueRefresh()
end

-- tbl: { [lookKey] = value }, written together (one refresh).
function HTr.SetLookMany(set, tbl)
    if not DEFAULTS[set] or type(tbl) ~= "table" then return end
    local db = GetDB(true)
    if not db then return end
    for k, v in pairs(tbl) do
        if ValidKey(k) then WriteLook(db, set, k, v) end
    end
    HB.QueueRefresh()
end

-- Every key of the look back to its default.
function HTr.ResetLook(set)
    if not DEFAULTS[set] then return end
    local db = GetDB()
    if db and db[set] then db[set] = nil end
    HB.QueueRefresh()
end

-- kind: "dmg" (Damage Animation) or "heal" (Heal Animation). Default off.
function HTr.PlaceOn(place, kind)
    local db = GetDB()
    local places = db and db.places
    local p = type(places) == "table" and places[place] or nil
    return type(p) == "table" and p[kind] == true
end

function HTr.SetPlace(place, kind, on)
    local def = HB.PLACE[place]
    if not (def and def.anim) or (kind ~= "dmg" and kind ~= "heal") then return end
    local db = GetDB(true)
    if not db then return end
    local places = db.places
    if not places then
        places = {}
        db.places = places
    end
    local p = places[place]
    if on then
        if not p then
            p = {}
            places[place] = p
        end
        p[kind] = true
    elseif p then
        p[kind] = nil
        if next(p) == nil then places[place] = nil end
    end
    HB.QueueRefresh()
end

local D_STYLES = { shrink = true, slide = true, fall = true, fade = true, chip = true, crumble = true }
local H_STYLES = { slide = true, fade = true }
local EASES = { NONE = true, IN = true, OUT = true, IN_OUT = true }

local function Num(v, d)
    return tonumber(v) or d
end

-- Reads the healthTrail* keys of a look (src: a table or a view with the place's
-- healthTrail and healthTrailHeal switches). Returns old when nothing changed,
-- so a caller restyles and resets only on a real change. defaults: the look's
-- default table, for a value that is missing or invalid.
function HTr.MakeStyle(src, old, defaults)
    local D = defaults or DEFAULTS_FRAMES
    local c = src.healthTrailColor or D.healthTrailColor
    local cc = src.healthTrailCritColor or D.healthTrailCritColor
    local mc = src.healthTrailMineColor or D.healthTrailMineColor
    local mcc = src.healthTrailMineCritColor or D.healthTrailMineCritColor
    local hc = src.healthTrailHealColor or D.healthTrailHealColor
    local dStyle = src.healthTrailStyle
    if not D_STYLES[dStyle] then dStyle = D.healthTrailStyle end
    local dEase = src.healthTrailEase
    if not EASES[dEase] then dEase = D.healthTrailEase end
    local hStyle = src.healthTrailHealStyle
    if not H_STYLES[hStyle] then hStyle = D.healthTrailHealStyle end
    local hEase = src.healthTrailHealEase
    if not EASES[hEase] then hEase = D.healthTrailHealEase end
    local n = {
        dmgOn = src.healthTrail and true or false,
        healOn = src.healthTrailHeal and true or false,
        dStyle = dStyle,
        dEase = dEase,
        dWait = math.max(0, Num(src.healthTrailWait, D.healthTrailWait)) / 1000,
        dMove = math.max(50, Num(src.healthTrailMove, D.healthTrailMove)) / 1000,
        fall = math.max(0, Num(src.healthTrailFall, D.healthTrailFall)),
        pop = math.max(0, Num(src.healthTrailPop, D.healthTrailPop)),
        tilt = Num(src.healthTrailTilt, D.healthTrailTilt),
        drift = Num(src.healthTrailDrift, D.healthTrailDrift),
        vary = src.healthTrailVary ~= false,
        chipSize = math.max(1, Num(src.healthTrailChipSize, D.healthTrailChipSize)),
        chipCols = math.max(1, math.floor(Num(src.healthTrailChipCols, D.healthTrailChipCols))),
        spread = math.max(0, Num(src.healthTrailSpread, D.healthTrailSpread)),
        spin = Num(src.healthTrailSpin, D.healthTrailSpin),
        stagger = math.max(0, Num(src.healthTrailStagger, D.healthTrailStagger)) / 1000,
        r = c.r or D.healthTrailColor.r,
        g = c.g or D.healthTrailColor.g,
        b = c.b or D.healthTrailColor.b,
        critOn = (src.healthTrail and src.healthTrailCrit) and true or false,
        cr = cc.r or D.healthTrailCritColor.r,
        cg = cc.g or D.healthTrailCritColor.g,
        cb = cc.b or D.healthTrailCritColor.b,
        mineOn = (src.healthTrail and src.healthTrailMine) and true or false,
        mr = mc.r or D.healthTrailMineColor.r,
        mg = mc.g or D.healthTrailMineColor.g,
        mb = mc.b or D.healthTrailMineColor.b,
        mcr = mcc.r or D.healthTrailMineCritColor.r,
        mcg = mcc.g or D.healthTrailMineCritColor.g,
        mcb = mcc.b or D.healthTrailMineCritColor.b,
        alpha = Num(src.healthTrailAlpha, D.healthTrailAlpha) / 100,
        flash = math.max(0, Num(src.healthTrailFlash, D.healthTrailFlash)) / 1000,
        group = src.healthTrailGroup ~= false,
        under = src.healthTrailUnderAbsorbs ~= false,
        hStyle = hStyle,
        hEase = hEase,
        hWait = math.max(0, Num(src.healthTrailHealWait, D.healthTrailHealWait)) / 1000,
        hMove = math.max(50, Num(src.healthTrailHealMove, D.healthTrailHealMove)) / 1000,
        hr = hc.r or D.healthTrailHealColor.r,
        hg = hc.g or D.healthTrailHealColor.g,
        hb = hc.b or D.healthTrailHealColor.b,
        ha = Num(src.healthTrailHealAlpha, D.healthTrailHealAlpha) / 100,
    }
    if old then
        local same = true
        for k, v in pairs(n) do
            if old[k] ~= v then same = false; break end
        end
        if same then return old end
    end
    return n
end

-------------------------------------------------------------------------------
--  Frames
-------------------------------------------------------------------------------
-- An invisible StatusBar over the health bar: its fill edge is the anchor.
local function HiddenBar(parent, bar)
    local sb = Flat(CreateFrame("StatusBar", nil, parent))
    sb:SetAllPoints(bar)
    sb:SetStatusBarTexture(WHITE)
    sb:SetStatusBarColor(0, 0, 0, 0)
    return sb
end

local function ClipFrame(parent)
    local f = Flat(CreateFrame("Frame", nil, parent))
    f:SetClipsChildren(true)
    return f
end

-- A finished group reverts its region to the start state, so the owner (a clip
-- frame, a frame or a texture) is hidden when the group ends. A recycled piece
-- carries a new gen, which mutes a late finish of its old run. g._chain(p), when
-- set, starts the next stage (Chip Off and Crumble: the piece leaves its place
-- at the end of the wait).
local function GroupDone(g)
    local p = g._p
    if p.gen ~= g._gen then return end
    g._hide:Hide()
    local nx = g._chain
    if nx then nx(p) end
end

local function NewGroup(owner, p, hide, kind)
    local g = owner:CreateAnimationGroup()
    local a = g:CreateAnimation(kind)
    g._p, g._hide = p, hide
    g:SetScript("OnFinished", GroupDone)
    return g, a
end

local function Run(g)
    g._gen = g._p.gen
    g:Play()
end

local function Timing(a, wait, move, ease)
    a:SetStartDelay(wait)
    a:SetDuration(move)
    a:SetSmoothing(ease)
end

-- A damage look: a clip (bar left .. before edge, inside a shared clip), the
-- piece frame with its color texture and white flash, and one group per motion.
-- A piece has one look inside the bar (p.dIn, in the shared live-edge clip
-- under the base) and, for a style that moves the piece below the bar, a twin
-- below it (p.dOut, in the shared below-the-bar clip under t.out). The twin
-- runs the same motions at the same time, so the two read as one piece; it
-- draws on OVERLAY 6 (flash OVERLAY 7) at the caller's below level, in front of
-- the bar's border art, which a flattened plate (SetFlattensRenderLayers) orders
-- by draw layer and a raid button by frame level.
local function NewDamageLook(holder, p, layer, sub, flashSub)
    local clip = ClipFrame(holder)
    local f = Flat(CreateFrame("Frame", nil, clip))
    local tex = f:CreateTexture(nil, layer, nil, sub)
    tex:SetAllPoints(f)
    local flash = f:CreateTexture(nil, "OVERLAY", nil, flashSub)
    flash:SetAllPoints(f)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:Hide()
    local L = { clip = clip, f = f, tex = tex, flash = flash }
    local a
    L.scaleG, a = NewGroup(f, p, clip, "Scale")
    a:SetOrigin("LEFT", 0, 0)
    a:SetScaleFrom(1, 1)
    a:SetScaleTo(SCALE_END, 1)
    L.scale = a
    L.moveG, a = NewGroup(f, p, clip, "Translation")
    L.move = a
    L.alphaG, a = NewGroup(f, p, clip, "Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    L.alpha = a
    L.flashG, a = NewGroup(flash, p, flash, "Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetSmoothing("NONE")
    L.flashA = a
    clip:Hide()
    return L
end

local LOOK_GROUPS = { "scaleG", "moveG", "alphaG", "flashG" }

local function StopLook(L)
    for i = 1, #LOOK_GROUPS do L[LOOK_GROUPS[i]]:Stop() end
    L.clip:Hide()
    L.flash:Hide()
    L.g1, L.g2 = nil, nil
end

-- A look's motion groups start over (the Group Pieces option).
local function RestartLook(L)
    L.g1:Stop()
    L.g1:Play()
    if L.g2 then
        L.g2:Stop()
        L.g2:Play()
    end
end

-- Chip Off and Crumble: during the wait the piece sits in its place as the
-- look inside the bar (under the border, as the other styles); at the end of
-- the wait that look goes and the piece leaves its place in front of the
-- border art (under t.out). A Rotation needs a texture, so these groups run on
-- the textures.

-- Chip Off: the whole piece (after edge .. before edge, not clipped, so the jump
-- above the bar shows) jumps up, falls below the bar, tilts and moves sideways.
local function NewFly(t, p)
    local f = Flat(CreateFrame("Frame", nil, t.out))
    local tex = f:CreateTexture(nil, "OVERLAY", nil, 6)
    tex:SetPoint("TOPLEFT", p.afterTex, "TOPRIGHT")
    tex:SetPoint("BOTTOMRIGHT", p.beforeTex, "BOTTOMRIGHT")
    local F = { f = f, tex = tex }
    F.g, F.up = NewGroup(tex, p, f, "Translation")
    F.up:SetSmoothing("OUT")
    local g = F.g
    F.down = g:CreateAnimation("Translation")
    F.down:SetSmoothing("IN")
    F.side = g:CreateAnimation("Translation")
    F.side:SetSmoothing("NONE")
    F.spin = g:CreateAnimation("Rotation")
    F.spin:SetOrigin("CENTER", 0, 0)
    F.spin:SetSmoothing("NONE")
    F.fade = g:CreateAnimation("Alpha")
    F.fade:SetFromAlpha(1)
    F.fade:SetToAlpha(0)
    F.fade:SetSmoothing("NONE")
    f:Hide()
    return F
end

-- Crumble: one square chip with its own drop, drift, spin and fade.
local function NewChip(C, p)
    local tex = C.f:CreateTexture(nil, "OVERLAY", nil, 6)
    local ch = { tex = tex }
    ch.g, ch.move = NewGroup(tex, p, tex, "Translation")
    ch.spin = ch.g:CreateAnimation("Rotation")
    ch.spin:SetOrigin("CENTER", 0, 0)
    ch.fade = ch.g:CreateAnimation("Alpha")
    ch.fade:SetFromAlpha(1)
    ch.fade:SetToAlpha(0)
    ch.fade:SetSmoothing("IN")
    tex:Hide()
    return ch
end

-- Crumble: a clip (after edge .. before edge, down below the bar) inside the
-- shared below-the-bar clip, the chips (made when first needed), and the chunk:
-- the whole piece in a clip that ends where the chip grid starts, so a piece
-- wider than the grid drops its left part in one.
local CHUNK_LEFT = 20000  -- the chunk clip's left end: far left of any bar

local function NewCrumble(t, p)
    local clip = ClipFrame(t.oClip)
    local f = Flat(CreateFrame("Frame", nil, clip))
    local cclip = ClipFrame(clip)
    local cf = Flat(CreateFrame("Frame", nil, cclip))
    local chunk = cf:CreateTexture(nil, "OVERLAY", nil, 6)
    chunk:SetPoint("TOPLEFT", p.afterTex, "TOPRIGHT")
    chunk:SetPoint("BOTTOMRIGHT", p.beforeTex, "BOTTOMRIGHT")
    local C = { clip = clip, f = f, cclip = cclip, chunk = chunk, chips = {}, n = 0 }
    C.chunkG, C.chunkMove = NewGroup(chunk, p, chunk, "Translation")
    C.chunkFade = C.chunkG:CreateAnimation("Alpha")
    C.chunkFade:SetFromAlpha(1)
    C.chunkFade:SetToAlpha(0)
    clip:Hide()
    return C
end

local function StopCrumble(C)
    C.chunkG:Stop()
    local chips = C.chips
    for i = 1, C.n do chips[i].g:Stop() end
    C.clip:Hide()
end

-- Heal look (no smooth fill): clip (before edge .. bar right, inside the
-- shared bar left .. live edge clip) around a texture in the heal color.
local function EnsureHeal(t, p)
    if p.hClip then return end
    local clip = ClipFrame(t.hClip)
    local f = Flat(CreateFrame("Frame", nil, clip))
    -- Above the bar's own fill, which this covers.
    local tex = f:CreateTexture(nil, "OVERLAY", nil, 6)
    tex:SetAllPoints(f)
    p.hClip, p.hF, p.hTex = clip, f, tex
    local a
    p.hScaleG, a = NewGroup(f, p, clip, "Scale")
    a:SetOrigin("RIGHT", 0, 0)
    a:SetScaleFrom(1, 1)
    a:SetScaleTo(SCALE_END, 1)
    p.hScale = a
    p.hAlphaG, a = NewGroup(f, p, clip, "Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    p.hAlpha = a
    clip:Hide()
end

-- Heal look with smooth fill: the part right of the live edge up to the new
-- value, drawn as a StatusBar in the bar's own texture and the heal color.
-- No motion of its own (the fill slides over it); an alpha group retires it.
local function EnsureSmooth(t, p, bar)
    if p.sClip then return end
    local clip = ClipFrame(t.dClip)
    local sb = Flat(CreateFrame("StatusBar", nil, clip))
    sb:SetAllPoints(bar)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(1)
    p.sClip, p.sBar = clip, sb
    local a
    p.sG, a = NewGroup(clip, p, clip, "Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(1)
    a:SetDuration(SMOOTH_LIFE)
    clip:Hide()
end

-- Runs fn(...); an error is shown once (the error handler), never raised.
-- Returns true when fn ran to its end.
local guardShown = false
local function Guard(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not guardShown then
        guardShown = true
        geterrorhandler()(err)
    end
    return ok
end

-- True when the game forbids measuring this region now (GetPoint, GetWidth
-- and the like), as for a region anchored to a protected nameplate.
-- Tried, not asked: IsAnchoringRestricted's answer can be secret, and EUI's
-- plate bars measure fine while it says so. So: true when measuring r now
-- raises an error (anchored to a restricted region) or gives a secret value
-- (a secret layout).
local function Restricted(r)
    if not r then return true end
    local ok1, s = pcall(r.GetEffectiveScale, r)
    local ok2, w = pcall(r.GetWidth, r)
    local ok3, h = pcall(r.GetHeight, r)
    if not (ok1 and ok2 and ok3) then return true end
    if issecretvalue(s) or issecretvalue(w) or issecretvalue(h) then return true end
    return false
end

local GROUPS = { "hScaleG", "hAlphaG", "sG" }

-- Stops every look of a piece.
local function StopLooks(p)
    if p.dIn then StopLook(p.dIn) end
    if p.dOut then StopLook(p.dOut) end
    if p.dFly then
        p.dFly.g:Stop()
        p.dFly.f:Hide()
    end
    if p.dCrumb then StopCrumble(p.dCrumb) end
    for i = 1, #GROUPS do
        local g = p[GROUPS[i]]
        if g then g:Stop() end
    end
    if p.hClip then p.hClip:Hide() end
    if p.sClip then p.sClip:Hide() end
    p.hG, p.dOutOn, p.dFlyOn, p.dCrumbOn = nil, nil, nil, nil
end

local function StopPiece(p)
    StopLooks(p)
end

local function StopAll(t)
    local ps = t.pieces
    for i = 1, #ps do StopPiece(ps[i]) end
end

-- The next piece in turn; when all POOL pieces are used the oldest is recycled.
local function TakePiece(t, bar)
    local ps = t.pieces
    local n = #ps
    local i = t.cursor
    if i > n and n >= POOL then i = 1 end
    t.cursor = i + 1
    local p = ps[i]
    if p then
        StopPiece(p)
    else
        p = { after = HiddenBar(t.base, bar), before = HiddenBar(t.base, bar), gen = 0 }
        p.afterTex = p.after:GetStatusBarTexture()
        p.beforeTex = p.before:GetStatusBarTexture()
        ps[i] = p
    end
    p.gen = p.gen + 1
    return p
end

-------------------------------------------------------------------------------
--  Arming a piece (anchors, colors and timings are set per change, so a settings
--  edit needs no restyle pass)
-------------------------------------------------------------------------------
-- Color and draw layer of a damage piece from p.mine / p.crit (the crit color only
-- while Crit Color is on, the mine colors only while My Damage is on). Inside the
-- bar a special piece sits on the lowest overlay sublevel and a normal one on
-- ARTWORK 7; the white flash (OVERLAY 0) stays above both. The below-the-bar twin
-- keeps its own layer (OVERLAY 6) and takes the same color. Set on every arm and
-- recolor, because pieces are pooled.
local function PaintDamage(p, st)
    local crit, mine = p.crit and st.critOn, p.mine and st.mineOn
    local r, g, b
    if mine and crit then
        r, g, b = st.mcr, st.mcg, st.mcb
    elseif mine then
        r, g, b = st.mr, st.mg, st.mb
    elseif crit then
        r, g, b = st.cr, st.cg, st.cb
    else
        r, g, b = st.r, st.g, st.b
    end
    local tex = p.dIn.tex
    if mine or crit then
        tex:SetDrawLayer("OVERLAY", -8)
    else
        tex:SetDrawLayer("ARTWORK", 7)
    end
    local a = st.alpha
    tex:SetColorTexture(r, g, b, a)
    if p.dOut then p.dOut.tex:SetColorTexture(r, g, b, a) end
    if p.dFlyOn then p.dFly.tex:SetColorTexture(r, g, b, a) end
    if p.dCrumbOn then
        local C = p.dCrumb
        C.chunk:SetColorTexture(r, g, b, a)
        local chips = C.chips
        for i = 1, C.n do chips[i].tex:SetColorTexture(r, g, b, a) end
    end
end

-- Crumble's chip grid: rows = the bar height / Chip Size, rounded, 1 to 4;
-- side = the bar height / rows (base units, plain numbers).
local function CrumbleGrid(t, st)
    local h = t.barH
    local rows = math.floor(h / (st.chipSize * t.mul) + 0.5)
    if rows < 1 then rows = 1 elseif rows > 4 then rows = 4 end
    return h / rows, rows
end

-- How far below the bar a damage style draws (0: it stays inside). Chip Off
-- draws with no clip, so it has no distance here.
local function BelowPx(t, st)
    local s = st.dStyle
    if s == "fall" then return st.fall * t.mul end
    if s == "crumble" then
        local side = CrumbleGrid(t, st)
        return st.fall * t.mul * 1.3 + side + 2 * t.mul
    end
    return 0
end

local CUT = 0.01  -- seconds: how fast the inside look goes at the end of the wait

-- Starts a look's motion for the damage style (and its flash). belowPx: the
-- style's distance below the bar. chain(p): Chip Off and Crumble, the stage that
-- starts when this look goes at the end of the wait.
local function Motion(t, L, st, belowPx, chain)
    local wait, move, ease = st.dWait, st.dMove, st.dEase
    local s = st.dStyle
    L.alphaG._chain = nil
    if chain then
        Timing(L.alpha, wait, CUT, "NONE")
        L.alphaG._chain = chain
        L.g1, L.g2 = L.alphaG, nil
    elseif s == "shrink" then
        Timing(L.scale, wait, move, ease)
        L.g1, L.g2 = L.scaleG, nil
    elseif s == "slide" then
        L.move:SetOffset(-t.barPx, 0)
        Timing(L.move, wait, move, ease)
        L.g1, L.g2 = L.moveG, nil
    elseif s == "fall" then
        L.move:SetOffset(0, -belowPx)
        Timing(L.move, wait, move, ease)
        Timing(L.alpha, wait, move, ease)
        L.g1, L.g2 = L.moveG, L.alphaG
    else
        Timing(L.alpha, wait, move, ease)
        L.g1, L.g2 = L.alphaG, nil
    end
    L.clip:Show()
    Run(L.g1)
    if L.g2 then Run(L.g2) end
    if st.flash > 0 then
        L.flashA:SetDuration(st.flash)
        L.flash:Show()
        Run(L.flashG)
    end
end

-- Places a look: its clip spans top .. the before edge (down to belowPx under the
-- bar's bottom), the piece spans left .. the before edge over the bar's height.
local function PlaceLook(L, top, topPoint, left, before, belowPx)
    L.clip:ClearAllPoints()
    L.clip:SetPoint("TOPLEFT", top, topPoint)
    L.clip:SetPoint("BOTTOMRIGHT", before, "BOTTOMRIGHT", 0, -belowPx)
    L.f:ClearAllPoints()
    L.f:SetPoint("TOPLEFT", left, "TOPRIGHT")
    L.f:SetPoint("BOTTOMRIGHT", before, "BOTTOMRIGHT")
end

-- Chip Off: the throw, as an arc. With u = time / move, the height is
-- y(u) = s^2 u^2 - 2 sqrt(pop) s u (down is +), s = sqrt(pop) + sqrt(pop + fall):
-- it peaks (-pop) at u0 = sqrt(pop) / s and ends at +fall. So the rise is an up
-- Translation for u0 * move (OUT: it slows to the peak) and the fall a down one
-- for the rest (IN: it speeds up). Tilt and sideways run over the whole move,
-- the fade over its last 40%. Vary scales pop, tilt and sideways by 0.7 to 1.3.
local MIN_DUR = 0.001

local function ArmFly(t, p, st)
    local F = p.dFly
    if not F then
        F = NewFly(t, p)
        p.dFly = F
    end
    local k1, k2, k3 = 1, 1, 1
    if st.vary then
        k1, k2, k3 = 0.7 + 0.6 * random(), 0.7 + 0.6 * random(), 0.7 + 0.6 * random()
    end
    local mul, move = t.mul, st.dMove
    local pop, fall = st.pop * k1 * mul, st.fall * mul
    local rp = math.sqrt(pop)
    local s = rp + math.sqrt(pop + fall)
    local rise = (s > 0) and (rp / s) * move or 0
    F.up:SetOffset(0, pop)
    F.up:SetStartDelay(0)
    F.up:SetDuration(math.max(rise, MIN_DUR))
    F.down:SetOffset(0, -(pop + fall))
    F.down:SetStartDelay(rise)
    F.down:SetDuration(math.max(move - rise, MIN_DUR))
    F.side:SetOffset(st.drift * k3 * mul, 0)
    F.side:SetDuration(move)
    -- A positive Rotation turns left; the tuner's tilt turns right.
    F.spin:SetDegrees(-st.tilt * k2)
    F.spin:SetDuration(move)
    F.fade:SetStartDelay(move * 0.6)
    F.fade:SetDuration(move * 0.4)
    F.f:Hide()
    p.dFlyOn = true
end

local function StartFly(p)
    local F = p.dFly
    F.f:Show()
    Run(F.g)
end

-- Crumble: chips in a fixed grid from the before edge leftward (plain offsets:
-- the piece's width is secret), each with its own random start (up to Stagger
-- after the wait), drop (0.7 to 1.3 times Fall Distance), drift and spin. The
-- chunk (the part left of the grid) starts after the full Stagger.
local function ArmCrumble(t, bar, p, st, belowPx)
    local C = p.dCrumb
    if not C then
        C = NewCrumble(t, p)
        p.dCrumb = C
    end
    local side, rows = CrumbleGrid(t, st)
    local cols = st.chipCols
    local n = cols * rows
    local mul, move, ease = t.mul, st.dMove, st.dEase
    local fall, spread, spin, stagger = st.fall * mul, st.spread * mul, st.spin, st.stagger
    C.clip:ClearAllPoints()
    C.clip:SetPoint("TOPLEFT", p.afterTex, "TOPRIGHT")
    C.clip:SetPoint("BOTTOMRIGHT", p.beforeTex, "BOTTOMRIGHT", 0, -belowPx)
    C.clip:Hide()
    C.cclip:ClearAllPoints()
    C.cclip:SetPoint("TOPLEFT", bar, "TOPLEFT", -CHUNK_LEFT, 0)
    C.cclip:SetPoint("BOTTOMRIGHT", p.beforeTex, "BOTTOMRIGHT", -cols * side, -belowPx)
    C.chunkMove:SetOffset(0, -fall)
    Timing(C.chunkMove, stagger, move, ease)
    Timing(C.chunkFade, stagger, move, ease)
    C.chunk:Show()
    local chips = C.chips
    for i = 1, n do
        local ch = chips[i]
        if not ch then
            ch = NewChip(C, p)
            chips[i] = ch
        end
        if ch.side ~= side or ch.rows ~= rows then
            local c, r = math.floor((i - 1) / rows), (i - 1) % rows
            local tex = ch.tex
            tex:ClearAllPoints()
            tex:SetSize(side, side)
            tex:SetPoint("TOPRIGHT", p.beforeTex, "TOPRIGHT", -c * side, -r * side)
            ch.side, ch.rows = side, rows
        end
        local d = random() * stagger
        ch.move:SetOffset((random() * 2 - 1) * spread, -fall * (0.7 + 0.6 * random()))
        Timing(ch.move, d, move, ease)
        ch.spin:SetDegrees((random() * 2 - 1) * spin)
        Timing(ch.spin, d, move, ease)
        ch.fade:SetStartDelay(d)
        ch.fade:SetDuration(move)
        ch.tex:Show()
    end
    for i = n + 1, C.n do chips[i].tex:Hide() end
    C.n = n
    p.dCrumbOn = true
end

local function StartCrumble(p)
    local C = p.dCrumb
    C.clip:Show()
    local chips = C.chips
    for i = 1, C.n do Run(chips[i].g) end
    Run(C.chunkG)
end

-- belowPx: from BelowPx. twin: the fall twin draws the part below the bar
-- (Change set up t.out and t.oClip). inBelow: how far the look inside the bar
-- reaches down itself (Fall Off without a twin: under the border art).
-- Chip Off and Crumble also need t.out (and Crumble t.oClip).
local function ArmDamage(t, bar, p, st, now, crit, mine, belowPx, twin, inBelow)
    if not p.dIn then p.dIn = NewDamageLook(t.dClip, p, "ARTWORK", 7, 0) end
    if twin and not p.dOut then p.dOut = NewDamageLook(t.oClip, p, "OVERLAY", 6, 7) end
    local s = st.dStyle
    local left = s == "shrink" and t.live or p.afterTex
    PlaceLook(p.dIn, bar, "TOPLEFT", left, p.beforeTex, inBelow)
    if twin then PlaceLook(p.dOut, bar, "BOTTOMLEFT", left, p.beforeTex, belowPx) end
    p.crit, p.mine, p.dOutOn = crit, mine, twin
    local chain
    if s == "chip" then
        ArmFly(t, p, st)
        chain = StartFly
    elseif s == "crumble" then
        ArmCrumble(t, bar, p, st, belowPx)
        chain = StartCrumble
    end
    PaintDamage(p, st)
    p.dT0 = now
    Motion(t, p.dIn, st, belowPx, chain)
    if twin then Motion(t, p.dOut, st, belowPx) end
end

local function ArmHeal(t, bar, p, st, now)
    EnsureHeal(t, p)
    local clip, f = p.hClip, p.hF
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", p.beforeTex, "TOPRIGHT")
    clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", p.beforeTex, "TOPRIGHT")
    f:SetPoint("BOTTOMRIGHT", st.hStyle == "slide" and t.live or p.afterTex, "BOTTOMRIGHT")
    p.hTex:SetColorTexture(st.hr, st.hg, st.hb, st.ha)
    clip:Show()
    p.hT0 = now
    if st.hStyle == "slide" then
        Timing(p.hScale, st.hWait, st.hMove, st.hEase)
        p.hG = p.hScaleG
        Run(p.hScaleG)
    else
        Timing(p.hAlpha, st.hWait, st.hMove, st.hEase)
        p.hG = p.hAlphaG
        Run(p.hAlphaG)
    end
end

local function ArmSmooth(t, bar, p, st)
    EnsureSmooth(t, p, bar)
    local clip, sb = p.sClip, p.sBar
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", bar, "TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", p.afterTex, "BOTTOMRIGHT")
    local live = t.live
    local file = live:GetTexture()
    if p.sFile ~= file then
        p.sFile = file
        sb:SetStatusBarTexture(file or WHITE)
        sb:GetStatusBarTexture():SetDrawLayer("ARTWORK", 7)
    end
    -- The heal color; the bar's own alpha goes straight through (it may be secret).
    sb:SetStatusBarColor(st.hr, st.hg, st.hb, st.ha)
    sb:GetStatusBarTexture():SetAlpha(live:GetAlpha())
    clip:Show()
    Run(p.sG)
end

-- Group Pieces option: a piece still in its start delay starts over, so the
-- pieces of a burst move together. Flashes are left alone.
local function Regroup(t, st, now)
    local ps = t.pieces
    for i = 1, #ps do
        local p = ps[i]
        local L = p.dIn
        if L and L.g1 and now - p.dT0 < st.dWait then
            p.dT0 = now
            RestartLook(L)
            if p.dOutOn and p.dOut.g1 then RestartLook(p.dOut) end
        end
        if p.hG and now - p.hT0 < st.hWait then
            p.hT0 = now
            p.hG:Stop()
            p.hG:Play()
        end
    end
end

-------------------------------------------------------------------------------
--  API
-------------------------------------------------------------------------------
-- A new unit, or a new max health: forget the old health, drop every piece.
-- cur and maxHP may be secret; they are only stored. keep: the same unit
-- stays on the bar (a new max health): only the health is new, and what
-- shows now finishes.
function HTr.Reset(bar, cur, maxHP, keep)
    local t = STATE[bar]
    if not t then
        local tall = PP and PP.physicalHeight or 1080
        t = { pieces = {}, cursor = 1, mul = math.max(1, math.floor(tall / 1080 + 0.5)) }
        STATE[bar] = t
    end
    t.last, t.max, t.seeded = cur, maxHP, true
    if keep then return end
    t.newest, t.critT, t.mineT = nil, nil, nil
    StopAll(t)
end

-- Any paint that is not a real health change (a full repaint, a max change on a
-- percent bar): the next piece starts from this value. cur may be secret.
function HTr.Sync(bar, cur)
    local t = STATE[bar]
    if t and t.seeded then t.last = cur end
end

function HTr.Hide(bar)
    local t = STATE[bar]
    if not t then return end
    StopAll(t)
    if t.out then t.out:Hide() end
    if t.base then t.base:Hide() end
    t.seeded = false
    t.newest, t.critT, t.mineT = nil, nil, nil
end

-- A hit on this bar's unit that was a crit (UNIT_COMBAT, event WOUND, flagText
-- CRITICAL; the amount is secret and never read) and/or the player's own (nameplates:
-- the player's threat rose). A flag only counts while its setting is on (critOn,
-- mineOn). The event and the health paint arrive in either order: when the newest
-- piece was armed just now, it gains the flag and is repainted; otherwise the flag's
-- time is remembered and the next Change consumes it.
function HTr.Hit(bar, style, crit, mine)
    local t = STATE[bar]
    if not t or not t.seeded or not style then return end
    crit = crit and style.critOn and true or false
    mine = mine and style.mineOn and true or false
    if not (crit or mine) then return end
    local now = GetTime()
    local p = t.newest
    if p and p.dIn and p.dT0 and now - p.dT0 <= CRIT_WINDOW
        and ((crit and not p.crit) or (mine and not p.mine)) then
        p.crit = (p.crit or crit) and true or false
        p.mine = (p.mine or mine) and true or false
        PaintDamage(p, style)
        return
    end
    if crit then t.critT = now end
    if mine then t.mineT = now end
end

function HTr.Crit(bar, style)
    HTr.Hit(bar, style, true, false)
end

local function EnsureBase(t, bar)
    if t.base then return end
    local base = CreateFrame("Frame", nil, bar)
    base:SetAllPoints(bar)
    -- One base unit = one physical pixel.
    base:SetIgnoreParentScale(true)
    t.base = base
end

-- The holder of the below-the-bar twins (built on the first piece that leaves
-- the bar): the same size and scale as the base, its own frame level.
local function EnsureOut(t, bar)
    if t.out then return end
    local out = CreateFrame("Frame", nil, bar)
    out:SetAllPoints(bar)
    out:SetIgnoreParentScale(true)
    t.out = out
    t.oClip = ClipFrame(out)
end

-- The bar's width and height in base units (physical pixels).
local function MeasureBar(t, bar, base)
    local bscale = bar:GetEffectiveScale() / base:GetEffectiveScale()
    t.barPx = bar:GetWidth() * bscale
    t.barH = bar:GetHeight() * bscale
end

-- A real health change: cur is the new health. style: from MakeStyle. smooth:
-- the bar's fill eases by itself (raid frames), so the heal look is the part
-- between the live edge and the new value. overLvl: frame levels above the bar
-- for the "over the absorbs" setting (above the caller's absorb overlays, below
-- its Health Ticks marks); "under" draws at the bar's own level (SetUsingParentLevel),
-- below every absorb overlay frame (children at bar level + 1 or more) and above
-- the bar's own fill texture. Without that API, under falls back to the bar level.
-- belowLvl: frame levels above the bar for the part of a piece that leaves the
-- bar (Fall Off, Chip Off, Crumble), above the caller's border art. nil: Fall
-- Off keeps that part in the look inside the bar, under the border; Chip Off
-- and Crumble use overLvl + 1.
-- An optional 7th argument is the bar's max for this paint (may be secret, so it is
-- only counted with select, never tested), so the pieces always share the bar's scale.
function HTr.Change(bar, cur, style, smooth, overLvl, belowLvl, ...)
    local t = STATE[bar]
    if not t or not t.seeded then return end
    if select("#", ...) > 0 then t.max = (...) end
    local last = t.last
    t.last = cur
    if not style then return end
    local dmg, heal = style.dmgOn, style.healOn
    if not (dmg or heal) then return end
    local live = bar:GetStatusBarTexture()
    if not live then return end
    -- A restricted bar cannot be measured: no new piece on it. t.last is kept,
    -- so the next change on a free bar starts from this health.
    if Restricted(bar) then return end
    EnsureBase(t, bar)
    local base = t.base
    local scale = PP and PP.perfect or 1
    if t.scale ~= scale then
        base:SetScale(scale)
        t.scale = scale
    end
    local flat = (style.under and base.SetUsingParentLevel) and true or false
    if t.flat ~= flat then
        t.flat, t.lvl = flat, nil
        if base.SetUsingParentLevel then base:SetUsingParentLevel(flat) end
    end
    if not flat then
        local lvl = bar:GetFrameLevel() + (style.under and 0 or (overLvl or 2))
        if t.lvl ~= lvl then
            base:SetFrameLevel(lvl)
            t.lvl = lvl
        end
    end
    base:Show()
    t.live = live
    if not Guard(MeasureBar, t, bar, base) then return end
    local useHeal = heal and not smooth
    local useSmooth = heal and smooth
    local s = dmg and style.dStyle or nil
    local belowPx = dmg and BelowPx(t, style) or 0
    -- In front of the border art (t.out): the Fall Off twin (only with a below
    -- level; without one Fall Off stays under the border), a Chip Off flight and
    -- Crumble's chips.
    local twin = (s == "fall" and belowPx > 0 and belowLvl) and true or false
    local useOut = twin or s == "chip" or s == "crumble"
    local inBelow = (s == "fall" and not twin) and belowPx or 0
    -- Shared clips: the damage look (and the smooth heal look) show right of the
    -- live edge, the heal look left of it. The twins below the bar and the
    -- chips also stay right of the live edge, so every part of a piece has the
    -- same width.
    if dmg or useSmooth then
        if not t.dClip then t.dClip = ClipFrame(base) end
        t.dClip:ClearAllPoints()
        t.dClip:SetPoint("TOPLEFT", live, "TOPRIGHT")
        t.dClip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -inBelow)
        t.dClip:Show()
    end
    if useOut then
        EnsureOut(t, bar)
        local out = t.out
        if t.oScale ~= scale then
            out:SetScale(scale)
            t.oScale = scale
        end
        local lvl = bar:GetFrameLevel() + (belowLvl or ((overLvl or 2) + 1))
        if t.oLvl ~= lvl then
            out:SetFrameLevel(lvl)
            t.oLvl = lvl
        end
        out:Show()
        local oc = t.oClip
        oc:ClearAllPoints()
        oc:SetPoint("TOPLEFT", live, "TOPRIGHT")
        oc:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -belowPx)
    end
    if useHeal then
        if not t.hClip then t.hClip = ClipFrame(base) end
        t.hClip:ClearAllPoints()
        t.hClip:SetPoint("TOPLEFT", bar, "TOPLEFT")
        t.hClip:SetPoint("BOTTOMRIGHT", live, "BOTTOMRIGHT")
        t.hClip:Show()
    end
    local now = GetTime()
    if style.group then Regroup(t, style, now) end
    local p = TakePiece(t, bar)
    t.newest = p
    local crit, mine = false, false
    local ct, mt = t.critT, t.mineT
    if ct then
        t.critT = nil
        crit = (dmg and style.critOn and now - ct <= CRIT_WINDOW) and true or false
    end
    if mt then
        t.mineT = nil
        mine = (dmg and style.mineOn and now - mt <= CRIT_WINDOW) and true or false
    end
    local mx = t.max
    p.after:SetMinMaxValues(0, mx)
    p.after:SetValue(cur)
    p.before:SetMinMaxValues(0, mx)
    p.before:SetValue(last)
    if dmg then ArmDamage(t, bar, p, style, now, crit, mine, belowPx, twin, inBelow) end
    if useHeal then
        ArmHeal(t, bar, p, style, now)
    elseif useSmooth then
        ArmSmooth(t, bar, p, style)
    end
end

-------------------------------------------------------------------------------
--  The bar feature (EllesmereUI.HealthBars): which places draw, their styles,
--  and the crit and My Damage color events. Nothing is registered while no
--  place has a Damage Animation or Heal Animation on.
-------------------------------------------------------------------------------
-- Frame levels above the bar: the part of a piece over the bar, and the part
-- that leaves it (Fall Off, Chip Off, Crumble), in front of the border art.
-- Plates draw by layer first (SetFlattensRenderLayers): the style art is OVERLAY
-- 5 at most and the twin OVERLAY 6; its frames sit at health + 6 and + 7, so + 8
-- also wins by level. Raid and party: health at button + 2, border at button + 8
-- / + 9, raised to + 10 / + 11 on hover, target or aggro, so health + 10.
local LVL = { enemy = 2, friendly = 2, raid = 4, party = 4 }
local BELOW = { enemy = 8, friendly = 8, raid = 10, party = 10 }

local CFG = {}                                   -- CFG[place] = { on, lvl, below, style, view }
local ST = setmetatable({}, { __mode = "k" })    -- ST[bar] = { style, unit, guid, thr }
local critOn, mineOn = false, false

local function RF()
    local reg = EllesmereUI._ModuleNS
    return type(reg) == "table" and reg.EllesmereUIRaidFrames or nil
end

-- A raid view's fill is smooth while its settings (party, extra frames or the
-- raid view) have Smooth Bars on: the heal look follows it.
function HTr.ViewSmooth(party, extra)
    local rf = RF()
    if not rf then return false end
    local s
    if party then
        s = rf._scaledPartyProxy
    elseif extra then
        s = rf._scaledExtraProxy
    else
        s = rf._scaledProfile
    end
    if not s then
        s = rf.db and rf.db.profile
    end
    return (s and s.smoothBars) and true or false
end

local function RaidSmooth(e)
    local d = e.ffd
    if not d then return false end
    return HTr.ViewSmooth(d._isParty, d._isExtra)
end

-- The player's threat on a unit; nil while it is secret or missing.
local function ReadThreat(unit)
    local _, _, _, _, v = UnitDetailedThreatSituation("player", unit)
    if v == nil or issecretvalue(v) then return nil end
    return v
end

local ev = CreateFrame("Frame")
local H = {}

local function SyncEvents()
    if critOn or mineOn then
        ev:RegisterEvent("UNIT_COMBAT")
    else
        ev:UnregisterEvent("UNIT_COMBAT")
    end
    if mineOn then
        ev:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    else
        ev:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
    end
end

-- MakeStyle reads a place's switches and its look through one view: the look's
-- values (saved, else default) behind the place's own switches.
local function LookIndex(set)
    return function(_, key) return HTr.GetLook(set, key) end
end
local INDEX = { plates = LookIndex("plates"), frames = LookIndex("frames") }

local feature = {}

function feature.Resolve()
    critOn, mineOn = false, false
    for _, def in ipairs(HB.PLACES) do
        if def.anim then
            local id = def.id
            local c = CFG[id]
            if not c then
                c = { view = {} }
                CFG[id] = c
            end
            local dmg, heal = HTr.PlaceOn(id, "dmg"), HTr.PlaceOn(id, "heal")
            c.on = (dmg or heal) and true or false
            if c.on then
                local set = HTr.SetOf(id)
                c.lvl = LVL[id] or 4
                c.below = BELOW[id]
                local view = c.view
                view.healthTrail = dmg
                view.healthTrailHeal = heal
                -- My Damage Colors works on enemy nameplates only.
                view.healthTrailMine = (def.mine and HTr.GetLook(set, "healthTrailMine") == true) or false
                if not getmetatable(view) then setmetatable(view, { __index = INDEX[set] }) end
                c.style = HTr.MakeStyle(view, c.style, DEFAULTS[set])
                if c.style.critOn then critOn = true end
                if c.style.mineOn then mineOn = true end
            end
        end
    end
    SyncEvents()
end

function feature.Wants(place)
    local c = CFG[place]
    return c and c.on or false
end

function feature.Apply(bar, e, force)
    local c = CFG[e.place]
    local st = ST[bar]
    if not st then
        st = {}
        ST[bar] = st
    end
    if force or st.style ~= c.style then
        local unit = e.unit
        -- The same unit again (a new max health, a forced rescan): what shows
        -- finishes. A plate token keeps its unit until the plate is removed
        -- (Clear drops st); another token counts as the same by its GUID (a
        -- secret GUID never does).
        local g = UnitGUID(unit)
        if issecretvalue(g) then g = nil end
        local keep = st.style == c.style and st.unit == unit
            and (e.kind == "plate" or (g ~= nil and st.guid == g))
        HTr.Reset(bar, UnitHealth(unit), UnitHealthMax(unit), keep)
        st.unit, st.guid = unit, g
        st.style = c.style
        if c.style.mineOn then st.thr = ReadThreat(unit) else st.thr = nil end
    end
end

function feature.Clear(bar)
    if ST[bar] then
        HTr.Hide(bar)
        ST[bar] = nil
    end
end

function feature.Health(unit, set)
    local cur, mx
    for bar, e in pairs(set) do
        local st = ST[bar]
        if st then
            if not cur then cur, mx = UnitHealth(unit), UnitHealthMax(unit) end
            local smooth = (e.kind == "raid") and RaidSmooth(e) or false
            local c = CFG[e.place]
            HTr.Change(bar, cur, st.style, smooth, c.lvl, c.below, mx)
        end
    end
end

HB.AddFeature(feature)

-- The amount is secret and is never read: a crit is the WOUND action with the
-- CRITICAL flag text. A hit is "mine" when the player's threat on this unit
-- rose (enemy plates only; a guess: heals add threat too). A secret or missing
-- threat value means unknown, so not mine.
function H.UNIT_COMBAT(unit, action, flagText)
    if issecretvalue(action) or issecretvalue(flagText) then return end
    if action ~= "WOUND" then return end
    local set = HB.byUnit[unit]
    if not set then return end
    local crit = (flagText == "CRITICAL")
    for bar in pairs(set) do
        local st = ST[bar]
        local s = st and st.style
        if s and (s.critOn or s.mineOn) then
            local mine = false
            if s.mineOn then
                local v = ReadThreat(unit)
                if v then
                    mine = v > (st.thr or 0)
                    st.thr = v
                end
            end
            if crit or mine then HTr.Hit(bar, s, crit, mine) end
        end
    end
end

-- A rise in the player's threat is the player's own action, so a hit just
-- painted (or one about to be) counts as mine; a fall is only stored.
function H.UNIT_THREAT_LIST_UPDATE(unit)
    local set = HB.byUnit[unit]
    if not set then return end
    for bar in pairs(set) do
        local st = ST[bar]
        local s = st and st.style
        if s and s.mineOn then
            local v = ReadThreat(unit)
            if v then
                local last = st.thr or 0
                st.thr = v
                if v > last then HTr.Hit(bar, s, false, true) end
            end
        end
    end
end

ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    local h = H[event]
    if h then h(a1, a2, a3) end
end)
