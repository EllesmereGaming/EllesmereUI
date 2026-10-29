if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_TextPaint.lua
--
--  The texts of a raid frame (EUI_RaidFrames_TextKeys.lua) on live buttons: a
--  text plan per settings source, one FontString per text built on first need,
--  its font, anchor and colour, and one painter per kind. The event paths read
--  the plan and settings the button was last painted with (d._txP, d._txS).
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, setmetatable, type, CreateFrame = pairs, setmetatable, type, CreateFrame
local tostring, tconcat = tostring, table.concat
local UnitIsConnected, UnitIsDeadOrGhost = UnitIsConnected, UnitIsDeadOrGhost
local UnitClass, UnitPowerType, UnitPowerPercent = UnitClass, UnitPowerType, UnitPowerPercent
local UnitGetTotalHealAbsorbs, issecretvalue = UnitGetTotalHealAbsorbs, issecretvalue
local ApplyFont, GetPowerColor = I.ApplyFont, I.GetPowerColor
local GetSafeHealthPercent, ResolveDisplayName = I.GetSafeHealthPercent, I.ResolveDisplayName

local TEXTS = ns.RF_TEXTS
local NTEXTS = #TEXTS
local IS_POS = ns.RF_TEXT_POS_INDEX

-- Every text's setting keys under the names the painters read, built once.
local KEYS = {}
for i = 1, NTEXTS do
    local t = TEXTS[i]
    KEYS[i] = { X = t.x, Y = t.y, Size = t.size, ColorMode = t.cm, Color = t.col, CustomFormat = t.fmt,
        Above = t.above }
end

-- Per kind, as the old element FontStrings: width (a share of the frame width; the
-- name its own), word wrap, alpha and the colour a mode falls back to.
local KIND = {
    name   = { width = ns.RF_NAME_WIDTH_FRACTION, wrap = false, a = 1 },
    level  = { wrap = false, a = 1 },
    hp     = { width = 0.75, wrap = true, a = 0.9 },
    pp     = { width = 0.75, wrap = false, a = 0.9 },
    ha     = { width = 0.75, wrap = false, a = 0.9, r = 1, g = 0.3, b = 0.3 },
    custom = { width = 0.75, wrap = true, a = 0.9 },
}

local MODES = {
    hp = { percent = true, percentNoSign = true, number = true,
        numberPercent = true, percentNumber = true, missing = true },
    pp = { percent = true, percentNoSign = true, number = true,
        numberPercent = true, percentNumber = true },
    ha = { amount = true, short = true },
}

-------------------------------------------------------------------------------
--  Text plans: built per settings source on first use after a settings write
--  (ns.RF_TextPlanDirty from _RefreshProxyModes). p.all: the shown texts in
--  TEXTS order, p[kind]: those of one kind, p.bySlot[i] by text index,
--  p.reads: the value classes any Custom text reads, p.tick: the health tick
--  has work, p.wantLevel: UNIT_LEVEL is needed, p.nameAttach: the level
--  format in front of the name (the Top Name Bar's too, name shown or not).
-------------------------------------------------------------------------------
local gen, plans = 1, setmetatable({}, { __mode = "k" })

function ns.RF_TextPlanDirty()
    gen = gen + 1
end

-- A text's position and mode as the plan uses them; nil = not shown. s: the
-- settings (anything indexable), lvlPos: its level position or the client default.
-- Shared with the Text Display tiles, so a tile shows exactly what the frames draw.
local function Shown(t, s, lvlPos)
    local kind = t.kind
    if kind == "level" then
        if IS_POS[lvlPos] then return lvlPos end
        return
    end
    local pos = s[t.pos] or "center"
    if pos == "none" then return end
    if kind == "name" then return pos end
    if kind == "custom" then
        -- No template, nothing to draw.
        local f = s[t.fmt]
        if type(f) == "string" and f ~= "" then return pos end
        return
    end
    local mode = s[t.mode]
    if MODES[kind][mode] then return pos, mode end
end
ns.RF_TextShown = Shown

local function Build(s)
    local p = { gen = gen, all = {}, bySlot = {} }
    local lvlPos = s.levelTextPosition or ns.RF_LEVEL_DEFAULT
    p.nameAttach = ns.RF_LEVEL_ATTACH[lvlPos]
    p.wantLevel = (lvlPos ~= "none") or nil
    for i = 1, NTEXTS do
        local t = TEXTS[i]
        local pos, mode = Shown(t, s, lvlPos)
        if pos then
            local k = KEYS[i]
            local kind = t.kind
            local e = { i = i, k = k, pos = pos, kind = kind, mode = mode, prop = KIND[kind],
                attach = (kind == "name") and p.nameAttach or nil }
            if kind == "custom" then
                local cc = ns.RF_CustomCompile(s[k.CustomFormat])
                e.reads = cc and cc.reads or nil
                if e.reads then
                    local r = p.reads or {}
                    p.reads = r
                    for cls in pairs(e.reads) do r[cls] = true end
                end
            end
            local l = p[kind]
            if not l then l = {}; p[kind] = l end
            l[#l + 1] = e
            p.all[#p.all + 1] = e
            p.bySlot[i] = e
        end
    end
    p.tick = (p.hp or p.ha or p.pp or (p.reads and p.reads.hp)) and true or nil
    return p
end

-- What a plan is built from: the level position and every text's position,
-- mode and template. A settings write that leaves them unchanged keeps the
-- plan, so the buttons skip a relayout (the reload paths re-anchor offsets and
-- sizes themselves).
local SIG_KEYS = { "levelTextPosition" }
for i = 1, NTEXTS do
    local t = TEXTS[i]
    if t.kind ~= "level" then SIG_KEYS[#SIG_KEYS + 1] = t.pos end
    if t.mode then SIG_KEYS[#SIG_KEYS + 1] = t.mode end
    if t.fmt then SIG_KEYS[#SIG_KEYS + 1] = t.fmt end
end
ns.RF_TEXT_SIG_KEYS = SIG_KEYS
local sigParts = {}
local function Sig(s)
    for i = 1, #SIG_KEYS do sigParts[i] = tostring(s[SIG_KEYS[i]]) end
    return tconcat(sigParts, "\31")
end

function ns.RF_TextPlan(s)
    local p = plans[s]
    if not p or p.gen ~= gen then
        local sig = Sig(s)
        if p and p.sig == sig then
            p.gen = gen
        else
            p = Build(s)
            p.sig = sig
            plans[s] = p
        end
    end
    return p
end
local Plan = ns.RF_TextPlan

-- True while the raid, party or extra-frames view wants what: "level" (UNIT_LEVEL)
-- or a value class some Custom text reads. Settings-time only: the event syncs.
local VIEWS = { "_scaledProfile", "_scaledPartyProxy", "_scaledExtraProxy" }
function ns.RF_TextWanted(what)
    for i = 1, #VIEWS do
        local s = ns[VIEWS[i]]
        if s then
            local p = Plan(s)
            if (what == "level" and p.wantLevel) or (p.reads and p.reads[what]) then return true end
        end
    end
    return false
end

-- The level format in front of the name, nil without one: the Top Name Bar follows it.
function ns.RF_TextNameAttach(s)
    return Plan(s).nameAttach
end

-------------------------------------------------------------------------------
--  Layout and colour
-------------------------------------------------------------------------------
local function Dead(unit)
    return UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit)
end

-- A text's colour for its colour mode; pr, pg, pb: the unit's power colour when the
-- caller has it. Unknown or unreadable falls back to the content's colour.
local function TextColor(e, unit, s, pr, pg, pb)
    local mode, P = s[e.k.ColorMode], e.prop
    if mode == "accent" then
        local r, g, b = ns.EllesmereUI.ResolveActiveAccent()
        if r then return r, g, b end
    elseif mode == "class" then
        local _, tok = UnitClass(unit)
        if tok and not issecretvalue(tok) then
            local cc = ns.EllesmereUI.GetClassColor(tok)
            if cc then return cc.r, cc.g, cc.b end
        end
    elseif mode == "power" then
        if pr then return pr, pg, pb end
        return GetPowerColor(unit)
    else -- "custom"
        local c = s[e.k.Color]
        if c then return c.r, c.g, c.b end
    end
    return P.r or 1, P.g or 1, P.b or 1
end

-- Stamped on the FontString (ours) so a repaint with the same colour sets nothing.
local function Tint(fs, e, unit, s, pr, pg, pb)
    local r, g, b = TextColor(e, unit, s, pr, pg, pb)
    if fs._r ~= r or fs._g ~= g or fs._b ~= b then
        fs._r, fs._g, fs._b = r, g, b
        fs:SetTextColor(r, g, b, e.prop.a)
    end
end

-- Show Above Icons per text: the carrier sits where the name's setting puts it (the
-- reload passes level it); a text set the other way goes on a second carrier at the
-- other level (live buttons build it with the first; previews here, on first need).
-- Boss and pet frames have no aura band.
local function CarrierOf(d, s, e)
    local main = d.textCarrier
    if d._txFB then return main end
    local base = s.nameTextAboveIcons and true or false
    local v = s[e.k.Above]
    if v == nil then v = base end
    if (v and true or false) == base then return main end
    local owner = main:GetParent()
    local alt = d._txAlt
    if not alt then
        alt = CreateFrame("Frame", nil, owner)
        alt:SetAllPoints(main)
        d._txAlt = alt
    end
    local lvl = owner:GetFrameLevel() + (v and (ns.LVL_AURA + 6) or ns.LVL_TEXT)
    if alt:GetFrameLevel() ~= lvl then alt:SetFrameLevel(lvl) end
    return alt
end

-- Font, wrap and anchor of one shown text. The name sits on the decoration host (the
-- Party Frames kit: its stock name spot) and hides under the Top Name Bar; the others
-- sit on the bar host. Power Text shows only while the power bar does (d._pwtOn).
-- Boss and pet frames (d._txFB) bring their own host (d._txHost) and width (d._txW),
-- never wrap and have no Top Name Bar. Preview frames keep their bar as d._health.
local function Place(d, s, e, fs)
    local k, P, g, fb = e.k, e.prop, d.kitG, d._txFB
    local health = d.health or d._health
    local x, y = s[k.X] or 0, s[k.Y] or 0
    local fw = d._txW or s.frameWidth or 72
    local carrier = CarrierOf(d, s, e)
    if fs._cr ~= carrier then fs:SetParent(carrier); fs._cr = carrier end
    ApplyFont(fs, s[k.Size] or 10)
    fs:SetWordWrap(P.wrap and not fb)
    fs._r = nil
    if e.kind == "name" and g then
        fs:SetWidth(g.name.w)
        fs:SetHeight(0)
        ns.RF_KitSpot(g.name, fs, d.kitOwner, x, y)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV(g.name.jv)
        local txt = fs:GetText()
        fs:SetText(""); fs:SetText(txt or "")
    elseif e.kind == "name" then
        if s.topNameBarEnabled and not fb then fs:Hide(); return end
        ns.AnchorRFText(fs, d._txHost or ns.RF_AnchorHost(health, s), e.pos, x, y, fw * P.width)
    else
        local w = P.width and (g and g.health.w or fw * P.width)
        if not w then fs:SetWidth(0) end
        ns.AnchorRFText(fs, d._txHost or ns.RF_BarHost(health, s), e.pos, x, y, w)
    end
    fs:SetShown(e.kind ~= "pp" or d._pwtOn == true)
end

-- Boss and pet frames show no level and have no power bar.
local FB_SKIP = { level = true, pp = true }

-- Builds (on first need), fonts, anchors and shows the texts of s's plan on a
-- live button and hides the others. Re-run by every reload and kit pass; the paints
-- run it themselves when the plan changed since (ns._RFTextReady).
function ns.RF_TextLayout(d, s)
    local p = Plan(s)
    local pool = d._tx
    if not pool then pool = {}; d._tx = pool end
    local fb = d._txFB
    for i = 1, NTEXTS do
        local e, fs = p.bySlot[i], pool[i]
        if e and fb and FB_SKIP[e.kind] then e = nil end
        if e then
            if not fs then
                fs = d.textCarrier:CreateFontString(nil, "OVERLAY")
                fs._cr = d.textCarrier
                pool[i] = fs
            end
            Place(d, s, e, fs)
        elseif fs then
            fs:Hide()
        end
    end
    d._txL, d._txP, d._txS = p, p, s
end

-- The name's width on the resize paths that know the bar width better than
-- s.frameWidth (extra frames, party drags); the kit keeps its stock width.
function ns.RF_TextNameWidth(d, w)
    local l = d._txL and d._txL.name
    if not l or d.kitG then return end
    for j = 1, #l do d._tx[l[j].i]:SetWidth(w * l[j].prop.width) end
end

-- Fonts only, for the live resize drags that rescale sizes without a layout pass.
function ns.RF_TextFonts(d, s)
    local p = d._txL
    if not p then return end
    local all, pool = p.all, d._tx
    for j = 1, #all do ApplyFont(pool[all[j].i], s[all[j].k.Size] or 10) end
end

-- Stamps the button's plan and settings for the event paths; lays out first when
-- the plan changed. Returns the plan.
local function Ready(d, s)
    local p = Plan(s)
    if d._txL ~= p then ns.RF_TextLayout(d, s) end
    d._txP, d._txS = p, s
    return p
end
ns._RFTextReady = Ready

-------------------------------------------------------------------------------
--  Painters. Values only reach a format setter (secret-safe). Health, Power and
--  Heal Absorb Text blank while dead or offline (the status text names it); the
--  name, the level and Custom stay (Custom's tags name the status).
-------------------------------------------------------------------------------
local function PaintName(fs, e, unit, s, fb)
    if e.attach and not fb then
        ns._RFNameWithLevel(fs, ResolveDisplayName(unit, true, s), unit, e.attach)
    else
        fs:SetText(ResolveDisplayName(unit, true, s))
    end
end

local function PaintHealAbsorb(fs, e, unit, s, gone)
    if gone then fs:SetText(""); return end
    ns.FormatHealAbsorbInto(fs, (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0, e.mode)
    Tint(fs, e, unit, s)
end

-- d._txArgs[i]: the values text i was last painted with on this button. A repaint for
-- value classes a / b reads only the tags reading them (a health tick never resolves
-- the name again); a full paint (a nil) reads every tag.
local function PaintCustom(fs, e, unit, s, d, a, b)
    local all = d._txArgs
    if not all then all = {}; d._txArgs = all end
    local args = all[e.i]
    if not args then args = {}; all[e.i] = args end
    ns.RF_CustomTextInto(fs, s[e.k.CustomFormat], unit, s, nil, args, a, b)
end

-- The full paint's share: every text but Power Text (the power paint owns it).
function ns.RF_TextFull(d, s, unit)
    local p = Ready(d, s)
    local all, pool, fb = p.all, d._tx, d._txFB
    local gone = Dead(unit)
    local pct = p.hp and not gone and GetSafeHealthPercent(unit)
    for j = 1, #all do
        local e = all[j]
        local kind, fs = e.kind, pool[e.i]
        if kind == "name" then
            PaintName(fs, e, unit, s, fb)
            Tint(fs, e, unit, s)
        elseif kind == "level" then
            if not fb then
                ns._RFLevelInto(fs, unit)
                Tint(fs, e, unit, s)
            end
        elseif kind == "custom" then
            PaintCustom(fs, e, unit, s, d)
            Tint(fs, e, unit, s)
        elseif kind == "hp" then
            if gone then
                fs:SetText("")
            else
                ns.RF_HealthTextInto(fs, e.mode, pct, unit)
                Tint(fs, e, unit, s)
            end
        elseif kind == "ha" then
            PaintHealAbsorb(fs, e, unit, s, gone)
        end
    end
end

-- Name and Level texts and the Custom texts' names and levels (nickname changes,
-- UNIT_LEVEL).
function ns.RF_TextNames(d, unit)
    local p = d._txP
    if not p then return end
    local s, pool, fb = d._txS, d._tx, d._txFB
    local l = p.name
    if l then
        for j = 1, #l do
            local e = l[j]
            PaintName(pool[e.i], e, unit, s, fb)
            Tint(pool[e.i], e, unit, s)
        end
    end
    l = not fb and p.level
    if l then
        for j = 1, #l do ns._RFLevelInto(pool[l[j].i], unit) end
    end
    if p.reads and p.reads.id then ns.RF_TextRepaintCustom(d, unit, "id") end
end

-- Heal Absorb Texts (the absorb-only event path).
function ns.RF_TextHealAbsorb(d, unit)
    local p = d._txP
    local l = p and p.ha
    if not l then return end
    local s, pool, gone = d._txS, d._tx, Dead(unit)
    for j = 1, #l do PaintHealAbsorb(pool[l[j].i], l[j], unit, s, gone) end
end

-- The Custom texts reading value class a or b (the event paths that move only those).
function ns.RF_TextRepaintCustom(d, unit, a, b)
    local p = d._txP
    local r = p and p.reads
    if not (r and (r[a] or (b and r[b]))) then return end
    local s, pool, l = d._txS, d._tx, p.custom
    for j = 1, #l do
        local e = l[j]
        local er = e.reads
        if er and (er[a] or (b and er[b])) then PaintCustom(pool[e.i], e, unit, s, d, a, b) end
    end
end
local RepaintCustom = ns.RF_TextRepaintCustom

-------------------------------------------------------------------------------
--  Power Text: shown only while the button's power bar shows (d._pwtOn). The
--  full power paint shows it ahead of the identity edge that colours it; the
--  value rides every power value push; dead/offline blanks it on the edge the
--  health tick sees (d._pwtGone, cleared by the full power paint).
-------------------------------------------------------------------------------
function ns.RF_TextPowerShow(d, s)
    local l = Ready(d, s).pp
    if not l then d._pwtOn = nil; return end
    d._pwtOn, d._pwtGone = true, nil
    local pool = d._tx
    for j = 1, #l do pool[l[j].i]:Show() end
end

function ns.RF_TextPowerHide(d)
    if not d._pwtOn then return end
    d._pwtOn = nil
    local l = d._txP and d._txP.pp
    if not l then return end
    local pool = d._tx
    for j = 1, #l do pool[l[j].i]:Hide() end
end

-- A power value push. full: the full power paint, whose tail paints the Custom texts.
function ns.RF_TextPower(d, unit, ppct, pType, full)
    local p = d._txP
    if not p then return end
    local l = d._pwtOn and p.pp
    if l then
        local pool = d._tx
        for j = 1, #l do ns.RF_PowerTextInto(pool[l[j].i], l[j].mode, ppct, unit, pType) end
    end
    if not full and p.reads and p.reads.pp then RepaintCustom(d, unit, "pp") end
end

-- Power Text colour on the identity edge; pr, pg, pb: the unit's power colour.
function ns.RF_TextPowerColor(d, unit, s, pr, pg, pb)
    local l = d._pwtOn and d._txP and d._txP.pp
    if not l then return end
    local pool = d._tx
    for j = 1, #l do Tint(pool[l[j].i], l[j], unit, s, pr, pg, pb) end
end

local function PowerLife(d, l, unit, gone)
    if d._pwtGone == gone then return end
    d._pwtGone = gone
    local pool = d._tx
    if gone then
        for j = 1, #l do pool[l[j].i]:SetText("") end
        return
    end
    local pType = d._pwType or UnitPowerType(unit) or 0
    local ppct = UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100)
    for j = 1, #l do ns.RF_PowerTextInto(pool[l[j].i], l[j].mode, ppct, unit, pType) end
end

-- The health tick's share (callers gate on d._txP.tick): Health and Heal Absorb
-- Text, Power Text's dead/offline edge, and the Custom texts reading health.
-- allCustom: every Custom text (boss and pet frames, which have no other text events).
function ns.RF_TextHealth(d, unit, pct, gone, allCustom)
    local p = d._txP
    local s, pool = d._txS, d._tx
    local l = p.hp
    if l then
        for j = 1, #l do
            local e = l[j]
            local fs = pool[e.i]
            if gone then
                fs:SetText("")
            else
                ns.RF_HealthTextInto(fs, e.mode, pct, unit)
                Tint(fs, e, unit, s)
            end
        end
    end
    l = p.ha
    if l then
        for j = 1, #l do PaintHealAbsorb(pool[l[j].i], l[j], unit, s, gone) end
    end
    l = d._pwtOn and p.pp
    if l then PowerLife(d, l, unit, gone) end
    l = allCustom and p.custom
    if l then
        for j = 1, #l do PaintCustom(pool[l[j].i], l[j], unit, s, d) end
    elseif p.reads and p.reads.hp then
        RepaintCustom(d, unit, "hp")
    end
end

-------------------------------------------------------------------------------
--  Previews: no unit, made-up values in pv (hpPct, hpPer, ppPct, ppPer, ha:
--  the heal absorb amount, name: as the name text shows it, dead, offline,
--  power: the power bar shows, class and pToken: the sample member's class
--  and power type for the colours). The same layout and rules as live.
-------------------------------------------------------------------------------
local function PvPaint(fs, e, s, pv, fb)
    local kind = e.kind
    if kind == "name" then
        if e.attach and not fb then
            fs:SetFormattedText(e.attach[1], ns._RFPreviewLevel(), pv.name or "")
        else
            fs:SetText(pv.name or "")
        end
    elseif kind == "level" then
        fs:SetFormattedText("%d", ns._RFPreviewLevel())
    elseif kind == "custom" then
        ns.RF_CustomTextInto(fs, s[e.k.CustomFormat], nil, s, pv)
    elseif pv.dead or pv.offline then
        fs:SetText("")
        return
    elseif kind == "hp" then
        ns.RF_HealthTextInto(fs, e.mode, pv.hpPct or 100, nil, pv.hpPer or 1)
    elseif kind == "pp" then
        ns.RF_PowerTextInto(fs, e.mode, pv.ppPct or 100, nil, nil, pv.ppPer or 1)
    else -- "ha"
        ns.FormatHealAbsorbInto(fs, pv.ha or 0, e.mode)
    end
    local P = e.prop
    local r, g, b = ns.RF_PreviewTextColor(s[e.k.ColorMode], s[e.k.Color], pv.class,
        P.r or 1, P.g or 1, P.b or 1, pv.pToken)
    fs:SetTextColor(r, g, b, P.a)
end

-- Lays out and paints every shown text of a preview frame (d: the frame or a state with
-- textCarrier, _health and, for a replica, _txW). Keeps pv for the animated previews.
function ns.RF_TextPreview(d, s, pv)
    d._pwtOn = pv.power or nil
    ns.RF_TextLayout(d, s)
    local all, pool, fb = d._txL.all, d._tx, d._txFB
    for j = 1, #all do
        local e = all[j]
        if not (fb and FB_SKIP[e.kind]) then PvPaint(pool[e.i], e, s, pv, fb) end
    end
    d._txPv = pv
end

-- An animated preview's step after it moved pv: the texts following health ("hp") or
-- power ("pp"), Custom texts reading it included.
function ns.RF_TextPreviewTick(d, what)
    local p, pv = d._txL, d._txPv
    if not (p and pv) then return end
    local all, pool, s, fb = p.all, d._tx, d._txS, d._txFB
    for j = 1, #all do
        local e = all[j]
        local kind = e.kind
        if (kind == what or (kind == "custom" and e.reads and e.reads[what]))
            and not (fb and FB_SKIP[kind]) then
            PvPaint(pool[e.i], e, s, pv, fb)
        end
    end
end

-- The text inputs the boss/pet styler reads, written from t[n + 1] for the pet frames'
-- restyle fingerprint: the plan's signature (positions, modes, templates), then each
-- text's offsets and size. ns.RF_TEXT_STYLE_N values; returns the last index written.
ns.RF_TEXT_STYLE_N = 1 + 3 * NTEXTS
function ns.RF_TextStyleInputs(t, n, s)
    n = n + 1
    t[n] = Plan(s).sig
    for i = 1, NTEXTS do
        local k = KEYS[i]
        t[n + 1], t[n + 2], t[n + 3] = s[k.X], s[k.Y], s[k.Size]
        n = n + 3
    end
    return n
end

I.broken = false
