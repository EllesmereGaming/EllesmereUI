if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PartyTargets.lua
--
--  Party Targets: a secure target button beside each party frame.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local max          = math.max
local ipairs       = ipairs
local wipe         = wipe
local UnitName              = UnitName
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local IsInRaid              = IsInRaid
local InCombatLockdown      = InCombatLockdown
local C_Timer               = C_Timer
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame

local ApplyFont, PixelSnap = I.ApplyFont, I.PixelSnap
local ResolveHealthTexture = I.ResolveHealthTexture
local GetClassicHealthCurve = I.GetClassicHealthCurve
local GetSafeHealthPercent = I.GetSafeHealthPercent

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
-- Party Targets (opt-in, Party-only)
--
-- Secure buttons attached to party-header children and (Include Own Target
-- with Show Self First / Last) the self button. Their unit resolves as the
-- owner's current target at click time, so no protected unit mutation is
-- needed in combat.
-- Placement: the Position setting (unset: beside stacked frames, below
-- horizontal ones) plus its offsets. Across the stack (left/right of stacked
-- frames, above/below horizontal ones) the frames move off the Party Frames
-- kit's outside auras and follow the Beside Owner pets on that side, as the
-- pets do, and the groups attached beside the party frames (Friendly Boss,
-- the pet header) reserve the reach through ns.PT_Reserve. Along the stack
-- the chosen side is kept exactly and the party frames' pitch opens by the
-- frames' room (ns.PT_AlongPitch), so they sit between two party frames.
-- Look: a health bar on the Friendly Boss visuals (the stock edge under a
-- stock style) with the party texture, name font and border, and their own
-- Fill Color and Background.
-- Updates: a party member's target has no unit events, so one hidden 0.5 s
-- ticker reads the values while such a frame shows, and re-checks a mob's
-- tap and reaction (its colour); your own target is evented. Names and
-- colours otherwise repaint on target changes, unit re-assignments, roster
-- edges and settings pushes only.
-------------------------------------------------------------------------------
ns._partyTargetFrames = ns._partyTargetFrames or {}
ns._ptEnabled = false
ns._ptDesired = false
ns._ptInclDesired = false

do
local EUI = ns.EllesmereUI
-- Layout state (the last applied size, side, gaps and offsets: the layout's delta gate and the
-- reserve's source), the colour settings the paint reads (cached by the restyle), the listeners,
-- and the owner bookkeeping: owner token -> "<token>target", header button -> its target frame.
local PT = { tgtOf = {}, frameOf = setmetatable({}, { __mode = "k" }), tgtEv = {}, tgtWant = {}, acc = 0,
             DEF_FILL = { r = 37/255, g = 193/255, b = 29/255 } }
-- The shared style inputs plus the target frames' own ten (PT_FpExtra).
PT.FP_N = ns._PF.STYLE_N + 10

-- Owner unit -> its target frame, for UNIT_TARGET. Frames showing your own target stay out: they
-- read "target" and follow PLAYER_TARGET_CHANGED.
local PT_BY_UNIT = {}

-- The settings the target frames are styled from: the party ones, as the Beside Owner pets.
local function PT_Source()
    return ns._scaledPartyProxy
end

-- "party1" -> "party1target", built once per token.
local function PT_TargetOf(u)
    local t = PT.tgtOf[u]
    if not t then
        t = u .. "target"
        PT.tgtOf[u] = t
    end
    return t
end

-- Your raid token while the party frames run on raid units (arena, Small Raid), else nil.
local function PT_Me()
    if not IsInRaid() then return nil end
    local idx = UnitInRaid("player")
    if issecretvalue(idx) or not idx then return nil end
    return "raid" .. idx
end

-- The unit a frame reads, from its owner's current unit: your own target reads "target" (the token
-- your target's events carry), anyone else's "<owner>target". Keeps PT_BY_UNIT current. Returns
-- true when the frame's owner changed.
local function PT_Classify(frame)
    local ou, own
    if frame == PT.selfFrame then
        own = true
    else
        ou = frame._ptOwner:GetAttribute("unit")
        own = ou ~= nil and (ou == "player" or ou == PT.me)
    end
    local key = (not own) and ou or nil
    local old = frame._ptOwnerUnit
    local changed = old ~= key or frame._ptOwn ~= own
    if old ~= key then
        if old and PT_BY_UNIT[old] == frame then PT_BY_UNIT[old] = nil end
        if key then PT_BY_UNIT[key] = frame end
        frame._ptOwnerUnit = key
    end
    frame._ptOwn = own
    frame._ptUnit = (own and "target") or (ou and PT_TargetOf(ou)) or nil
    return changed
end

-- Class colour for players and party AI (the custom one where a restricted token still allows it),
-- grey for a tapped mob, the reaction colour for other NPCs. Returns ok, r, g, b; r/g/b may be
-- SECRET on the restricted path: only ever handed to a setter, never compared. A mob's tap and
-- reaction (neither secret) are kept on frame, for the ticker's re-check.
local function PT_ClassRGB(u, frame)
    if UnitIsPlayer(u) or (UnitInPartyIsAI and UnitInPartyIsAI(u)) then
        local _, ct = UnitClass(u)
        if issecretvalue(ct) then
            local ok, r, g, b = EUI.GetClassColorForRestrictedUnit(u, ct)
            if ok then return true, r, g, b end
            local c = C_ClassColor.GetClassColor(ct)
            if c then return true, c.r, c.g, c.b end
            return false
        end
        local cc = ct and EUI.GetClassColor(ct)
        if cc then return true, cc.r, cc.g, cc.b end
        return false
    end
    local tap = UnitIsTapDenied(u)
    local re = UnitReaction(u, "player")
    if issecretvalue(re) then re = nil end
    if frame then frame._ptNpc, frame._ptTap, frame._ptRe = true, tap, re end
    if tap then return true, 0.6, 0.6, 0.6 end
    local c = re and FACTION_BAR_COLORS[re]
    if c then return true, c.r, c.g, c.b end
    return false
end

-- The Classic gradient at the unit's current health (the engine evaluates the curve, secret-safe).
local function PT_PaintClassic(health, u)
    local c = UnitHealthPercent(u, true, GetClassicHealthCurve())
    if c and c.GetRGB then health:SetStatusBarColor(c:GetRGB()) end
end

-- Identity paint: name, fill and background colours, and the value, which jumps (a new unit). Runs
-- on target, unit and settings edges only. Names and colours can be secret: setters only.
local function PT_Paint(frame)
    local u = frame._ptUnit
    -- Set again below only for a mob whose colour reads its tap and reaction.
    frame._ptNpc = nil
    if not (u and UnitExists(u)) then return end
    frame._nameText:SetText(UnitName(u))
    local health, bg, mode = frame._health, frame._bg, PT.mode
    local fillTex = health:GetStatusBarTexture()
    if mode == "dark" then
        local r, g, b, a = EUI.GetDarkModeFill()
        health:SetStatusBarColor(r, g, b, 1)
        if fillTex then fillTex:SetAlpha(a) end
        bg:SetColorTexture(EUI.GetDarkModeBg())
    else
        if fillTex then fillTex:SetAlpha(1) end
        local ok, r, g, b = false
        if (mode ~= "classic" and mode ~= "custom") or PT.bgClass then ok, r, g, b = PT_ClassRGB(u, frame) end
        if mode == "classic" then
            PT_PaintClassic(health, u)
        elseif mode == "custom" then
            health:SetStatusBarColor(PT.fr, PT.fg, PT.fb, 1)
        elseif ok then
            health:SetStatusBarColor(r, g, b, 1)
        else
            health:SetStatusBarColor(0.5, 0.5, 0.5, 1)
        end
        if ok and PT.bgClass then
            bg:SetColorTexture(r, g, b, PT.bgA)
        else
            bg:SetColorTexture(PT.br, PT.bgg, PT.bb, PT.bgA)
        end
    end
    health:SetValue(GetSafeHealthPercent(u))
end

-- Value paint (the ticker and your target's health events), smoothed per Smooth Bars; the Classic
-- gradient follows the value.
local function PT_PaintValue(frame, u)
    local health = frame._health
    local smooth = PT.smooth
    if smooth then
        health:SetValue(GetSafeHealthPercent(u), smooth)
    else
        health:SetValue(GetSafeHealthPercent(u))
    end
    if PT.mode == "classic" then PT_PaintClassic(health, u) end
end

-- Every target frame on screen, in full (settings pushes: a restyle, Dark Mode and class colours
-- through ERF:UpdateAllFrames, roster edges). Nothing while off.
ns._PT_RepaintVisible = function()
    if not ns._ptEnabled then return end
    for _, frame in ipairs(ns._partyTargetFrames) do
        if frame:IsVisible() then PT_Paint(frame) end
    end
end

-- The frames on screen drive every per-unit listener. Polled frames (a party member's target):
-- UNIT_TARGET on their owners' units only (listener k covers frames 2k-1 and 2k, so a frame
-- showing or hiding re-registers its own listener alone; a target appearing shows its frame
-- through the unit watch), and the ticker while one shows. Own frames (your target): your target's
-- events while one shows with Include Own Target on. Nameplates and every other unit stay out.
-- except: a frame on its way off screen.
local function PT_Recount(except)
    local want, poll, own = PT.tgtWant, 0, 0
    wipe(want)
    if ns._ptEnabled then
        for i, f in ipairs(ns._partyTargetFrames) do
            if f ~= except and f:IsVisible() then
                if f._ptOwn then
                    own = own + 1
                elseif f._ptOwnerUnit then
                    poll = poll + 1
                    want[i] = f._ptOwnerUnit
                end
            end
        end
    end
    for k = 1, #PT.tgtEv do
        local ev = PT.tgtEv[k]
        local u1, u2 = want[2 * k - 1], want[2 * k]
        if ev.ptU1 ~= u1 or ev.ptU2 ~= u2 then
            ev.ptU1, ev.ptU2 = u1, u2
            ev:UnregisterEvent("UNIT_TARGET")
            if u1 and u2 then
                ev:RegisterUnitEvent("UNIT_TARGET", u1, u2)
            elseif u1 or u2 then
                ev:RegisterUnitEvent("UNIT_TARGET", u1 or u2)
            end
        end
    end
    local tk = PT.ticker
    if tk then
        if poll > 0 then
            if not tk:IsShown() then
                PT.acc = 0
                tk:Show()
            end
        elseif tk:IsShown() then
            tk:Hide()
        end
    end
    local ownOn = (own > 0 and PT.include) and true or false
    local ev = PT.ownFrame
    if ev and PT.ownEv ~= ownOn then
        PT.ownEv = ownOn
        if ownOn then
            ev:RegisterEvent("PLAYER_TARGET_CHANGED")
            ev:RegisterUnitEvent("UNIT_HEALTH", "target")
            ev:RegisterUnitEvent("UNIT_MAXHEALTH", "target")
            ev:RegisterUnitEvent("UNIT_FACTION", "target")
        else
            ev:UnregisterAllEvents()
        end
    end
end

-- The ticker (hidden while idle): every 0.5 s, the values of the polled frames on screen. A mob's
-- colour follows its tap and reaction, which raise no events on these units: a change repaints.
local function PT_Tick(_, elapsed)
    local acc = PT.acc + elapsed
    if acc < 0.5 then
        PT.acc = acc
        return
    end
    PT.acc = 0
    for _, f in ipairs(ns._partyTargetFrames) do
        local u = f._ptUnit
        if u and not f._ptOwn and f:IsVisible() and UnitExists(u) then
            PT_PaintValue(f, u)
            if f._ptNpc then
                local re = UnitReaction(u, "player")
                if issecretvalue(re) then re = nil end
                if UnitIsTapDenied(u) ~= f._ptTap or re ~= f._ptRe then PT_Paint(f) end
            end
        end
    end
end

-- Your target: a new target (or a faction change) repaints in full, its health events the value.
local function PT_OnOwnEvent(_, event)
    local full = event == "PLAYER_TARGET_CHANGED" or event == "UNIT_FACTION"
    for _, f in ipairs(ns._partyTargetFrames) do
        if f._ptOwn and f:IsVisible() then
            if full then
                PT_Paint(f)
            elseif UnitExists("target") then
                PT_PaintValue(f, "target")
            end
        end
    end
end

-- Include Own Target off: the header frame showing you drops its target frame's unit. Written here
-- out of combat by the rule the party frames' unit snippet applies in combat (PF.OWNER_SNIPPET).
local function PT_SeedAttrs()
    local noself = (ns._ptEnabled and not PT.include) and true or nil
    local me = PT.me
    for _, frame in ipairs(ns._partyTargetFrames) do
        if frame ~= PT.selfFrame then
            if frame:GetAttribute("pt-noself") ~= noself then frame:SetAttribute("pt-noself", noself) end
            if frame:GetAttribute("pt-me") ~= me then frame:SetAttribute("pt-me", me) end
            local u = frame._ptOwner:GetAttribute("unit")
            local show = not (noself and u ~= nil and (u == "player" or u == me))
            if frame:GetAttribute("useparent-unit") ~= show then frame:SetAttribute("useparent-unit", show) end
        end
    end
end

-- Full refresh (roster, zoning, the enable edge): your raid token, every frame's unit, the
-- listeners, and a repaint of the frames on screen (a token can pass to another member). The
-- attribute seed is a secure write: in combat it waits for the combat-end flush.
ns._PT_RefreshAll = function()
    if not ns._ptEnabled then return end
    PT.me = PT_Me()
    for _, frame in ipairs(ns._partyTargetFrames) do PT_Classify(frame) end
    if InCombatLockdown() then
        ns._ptSelfDirty = true
    else
        PT_SeedAttrs()
    end
    PT_Recount()
    ns._PT_RepaintVisible()
end

-- Roster and zoning storms: one refresh on the next frame, after the header re-assigned its buttons.
-- Nothing while the party frames are hidden (a raid): their show edge refreshes once instead
-- (ns._UpdatePartyVisibility).
PT.Flush = function()
    PT.flushQueued = nil
    ns._PT_RefreshAll()
end

local function PT_OnEvent(_, event, unit)
    if event == "UNIT_TARGET" then
        local frame = PT_BY_UNIT[unit]
        if frame and frame:IsVisible() then PT_Paint(frame) end
    elseif ns._partyFramesVisible and not PT.flushQueued then
        PT.flushQueued = true
        C_Timer.After(0, PT.Flush)
    end
end

-- The side (top/bottom read as above/below), the extra clearance there, and whether it runs across
-- the stack. Across, the side resolves through the Party Frames kit, as the Beside Owner pets
-- resolve theirs; along the stack it is kept as chosen, above stacked kit frames past the buff
-- lines the kit keeps in the party spacing there (RF_PartyDims). auto: the side an unset Position
-- takes, whatever is stored.
local function PT_Side(s, auto)
    local pos = (not auto and s.partyTargetPosition) or (s.partyHorizontal and "bottom" or "right")
    local side = (pos == "top" and "above") or (pos == "bottom" and "below") or (pos == "left" and "left") or "right"
    local vert = side == "above" or side == "below"
    local extra = 0
    if (vert and not s.partyHorizontal) or (not vert and s.partyHorizontal) then
        if side == "above" and ns.RF_PartyKit() then
            local _, _, cs = ns.RF_PartyDims(s)
            extra = cs - (s.partyKitSpacing or ns.RF_KIT_SPACING)
            if extra < 0 then extra = 0 end
        end
        return side, extra, false
    end
    if ns.RF_PartyKit() then
        local before = side == "left" or side == "above"
        before, extra = ns.RF_KitAttach(s, before)
        if s.partyHorizontal then
            side = before and "above" or "below"
        else
            side = before and "left" or "right"
        end
    end
    return side, extra, true
end

-- The gap to the frame: the party frames' spacing (under the kit its frame gap, without the buff
-- lines RF_PartyDims adds above stacked frames).
local function PT_Gap(s)
    if ns.RF_PartyKit() then return s.partyKitSpacing or ns.RF_KIT_SPACING end
    local _, _, sp = ns.RF_PartyDims(s)
    return sp
end

-- The reach of target frames laid out as st (the live layout state PT, or a preview spec) past the
-- party frames on the side a group attaches to (horizontal: the party frames' orientation; before:
-- left, or above horizontal frames), offsets included. Across the stack: their room there, past
-- the kit's clearance (the caller adds it) and any Beside Owner pets. Along the stack:
-- how far they overhang the party frame's edge (a Width or Height past the frame's, an offset).
local function PT_ReserveOf(st, horizontal, before)
    local side, r = st.side, 0
    if st.across then
        if horizontal then
            if before and side == "above" then
                r = st.h + st.gap + st.y
            elseif not before and side == "below" then
                r = st.h + st.gap - st.y
            end
        elseif before and side == "left" then
            r = st.w + st.gap - st.x
        elseif not before and side == "right" then
            r = st.w + st.gap + st.x
        end
    elseif horizontal then
        r = (st.h - st.ph) / 2 + (before and st.y or -st.y)
    else
        r = (st.w - st.pw) / 2 + (before and -st.x or st.x)
    end
    return r > 0 and PixelSnap(r) or 0
end

-- None until the frames are laid out (PT.w is cleared for a full layout). pets: the Beside Owner
-- pets' room on that side, for a caller that clears them too: across the stack the target frames
-- sit past them, along it level with them, so there the farther reach counts.
function ns.PT_Reserve(horizontal, before, pets)
    pets = pets or 0
    if not (ns._ptEnabled and PT.w) then return pets end
    local r = PT_ReserveOf(PT, horizontal, before)
    if PT.across then return r + pets end
    return (r > pets) and r or pets
end

-- The Position the frames actually take (the options dropdown's value): under the Party Frames kit
-- a side across the stack can move off the kit's buff run. auto: the one an unset setting takes
-- (beside stacked frames, below horizontal ones, then that kit move); the dropdown stores a pick
-- of it as unset, so the default keeps following the orientation and the frame style.
function ns.PT_ShownSide(auto)
    local side = PT_Side(db.profile, auto)
    return (side == "above" and "top") or (side == "below" and "bottom") or side
end

-- The room target frames along the stack (Top/Bottom beside stacked frames, Left/Right beside
-- horizontal ones) add to the party frames' pitch, so they sit between two frames: their length
-- on the stacking axis plus the gap past them. From the settings, so every slot placer agrees
-- whichever runs first. on: the enable state to read (the live one unless given; previews pass
-- the setting).
function ns.PT_AlongPitch(s, on)
    if on == nil then on = ns._ptEnabled end
    if not on then return 0 end
    local _, _, across = PT_Side(s)
    if across then return 0 end
    return PixelSnap(s.partyHorizontal and (s.partyTargetWidth or 70) or (s.partyTargetHeight or 33))
        + PixelSnap(PT_Gap(s))
end

-- One target frame on its side of owner o: off from the owner's edge, then the offsets.
local function PT_Place(frame, o, side, off, x, y)
    frame:ClearAllPoints()
    if side == "left" then
        frame:SetPoint("RIGHT", o, "LEFT", x - off, y)
    elseif side == "below" then
        frame:SetPoint("TOP", o, "BOTTOM", x, y - off)
    elseif side == "above" then
        frame:SetPoint("BOTTOM", o, "TOP", x, y + off)
    else
        frame:SetPoint("LEFT", o, "RIGHT", x + off, y)
    end
end

-- The reserve changed: re-anchor the groups that can attach beside the party frames (a Show in
-- Dungeons boss group, the pet header). Both only move when their spot changed. OOC only.
local function PT_NotifyReserve()
    local FB = ns._FB
    local fs = FB.Settings()
    if FB.built and fs and fs.showInDungeons == true then FB.Anchor() end
    ns.PF_ReAnchor()
end

-- Size and placement, delta-gated: every party layout pass (ns.PF_PartyRelayout, which the kit
-- clearance edge reaches through ns.FB_ReAnchor), every Beside Owner pet change (ns._PF's
-- NotifyReserve) and the Width, Height, Position and offset settings run it. The size is absolute
-- (never the kit's Frame Scale). A combat call is marked for the combat-end flush (ns.PF_Flush).
ns._PT_Layout = function()
    if not ns._ptEnabled then return end
    if InCombatLockdown() then
        ns._ptLayoutDirty = true
        return
    end
    ns._ptLayoutDirty = nil
    local s = db.profile
    -- The party frames' pitch holds the frames along the stack: a change there re-lays the party
    -- frames first, and their pass ends back here.
    if ns._partyHeader and ns.PT_AlongPitch(s) ~= (ns._ptPitchApplied or 0) then
        ns._LayoutPartyFrames()
        return
    end
    local w = PixelSnap(s.partyTargetWidth or 70)
    local h = PixelSnap(s.partyTargetHeight or 33)
    local x = PixelSnap(s.partyTargetOffsetX or 0)
    local y = PixelSnap(s.partyTargetOffsetY or 0)
    local pw, ph = ns.RF_PartyDims(s)
    pw, ph = PixelSnap(pw), PixelSnap(ph)
    local horiz = s.partyHorizontal and true or false
    local gap = PixelSnap(PT_Gap(s))
    local side, extra, across = PT_Side(s)
    local off = gap + PixelSnap(extra)
    -- Beside Owner pets on this side of the stack: after them (their gap already clears the kit).
    local pf = ns._PF
    if across and pf.ownerActive and pf.ownerSideCur == side then
        off = pf.ownerGap + ((side == "above" or side == "below") and pf.ownerH or pf.ownerW) + gap
    end
    local resized = w ~= PT.w or h ~= PT.h
    -- The reserve's inputs (PT_ReserveOf): beside stacked frames the width and X offset, beside
    -- horizontal ones the height and Y offset, and along the stack the party frame's size too. A
    -- full layout (PT.w cleared) re-pins the attached groups, which read none meanwhile.
    local reserve = PT.w == nil or side ~= PT.side or across ~= PT.across or gap ~= PT.gap
        or horiz ~= PT.horiz
    if not reserve then
        if horiz then
            reserve = h ~= PT.h or y ~= PT.y or (not across and ph ~= PT.ph)
        else
            reserve = w ~= PT.w or x ~= PT.x or (not across and pw ~= PT.pw)
        end
    end
    PT.pw, PT.ph, PT.horiz = pw, ph, horiz
    if not (reserve or resized) and off == PT.off and x == PT.x and y == PT.y then return end
    PT.w, PT.h, PT.side, PT.gap, PT.off, PT.across, PT.x, PT.y = w, h, side, gap, off, across, x, y
    local sizeVisuals = ns._FB.SizeVisuals
    for _, frame in ipairs(ns._partyTargetFrames) do
        if resized then
            frame:SetSize(w, h)
            sizeVisuals(frame, w, h)
            frame._nameText:SetWidth(max(1, w - 6))
        end
        PT_Place(frame, frame._ptOwner, side, off, x, y)
    end
    if reserve then PT_NotifyReserve() end
end

-- The target frames' own style inputs after the shared ones: Fill Color and its custom colour,
-- Background (class or custom colour, darkness) and Smooth Bars.
local function PT_FpExtra(t)
    local p, n = db.profile, ns._PF.STYLE_N
    local fc = p.partyTargetCustomFillColor or PT.DEF_FILL
    local bc = p.partyTargetCustomBgColor or ns._PF.DEFAULT_BG
    t[n + 1], t[n + 2], t[n + 3], t[n + 4] = p.partyTargetHealthColorMode, fc.r, fc.g, fc.b
    t[n + 5], t[n + 6], t[n + 7], t[n + 8] = p.partyTargetBgClassColored, bc.r, bc.g, bc.b
    t[n + 9], t[n + 10] = p.partyTargetBgDarkness, PT_Source().smoothBars
end

-- Texture, name font and border from the party settings (the stock edge under a stock style), and
-- the colour settings the paint reads, fingerprinted together: a reload or setting that changed
-- none of them touches nothing; one that did repaints the frames on screen, restyling them only
-- when a shared input changed (a colour setting alone re-reads the colours). A change made while
-- off lands on the enable edge. Combat-legal: nothing here touches the secure buttons.
ns._PT_Restyle = function()
    if not ns._ptEnabled then return end
    local s = PT_Source()
    local texPath = ResolveHealthTexture(s)
    local changed, at = ns._PF.StyleChanged("pt", s, texPath, PT_FpExtra, PT.FP_N)
    if not changed then return end
    local p = db.profile
    local fc = p.partyTargetCustomFillColor or PT.DEF_FILL
    local bc = p.partyTargetCustomBgColor or ns._PF.DEFAULT_BG
    PT.mode = p.partyTargetHealthColorMode or "class"
    PT.fr, PT.fg, PT.fb = fc.r, fc.g, fc.b
    PT.bgClass = p.partyTargetBgClassColored and true or nil
    PT.br, PT.bgg, PT.bb = bc.r, bc.g, bc.b
    PT.bgA = (p.partyTargetBgDarkness or 50) / 100
    local interp = Enum.StatusBarInterpolation
    PT.smooth = (s.smoothBars and interp and interp.ExponentialEaseOut) or nil
    -- 0: nothing styled yet (new frames); up to STYLE_N: a shared input changed.
    if at <= ns._PF.STYLE_N then
        local nameSize = s.nameSize or 10
        local styleBorder = ns._FB.StyleBorder
        for _, frame in ipairs(ns._partyTargetFrames) do
            local health, bg = frame._health, frame._bg
            health:SetStatusBarTexture(texPath)
            local tex = health:GetStatusBarTexture()
            bg:ClearAllPoints()
            if tex then
                tex:SetHorizTile(false)
                -- The background covers the missing health only, off the fill's far edge.
                bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
                bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            else
                bg:SetAllPoints(health)
            end
            ApplyFont(frame._nameText, nameSize)
            styleBorder(frame)
        end
    end
    ns._PT_RepaintVisible()
end

-- Hover border, as the pets and the boss group.
local function PT_Enter(self)
    ns._FB.hov[self] = true
    ns._FB.ApplyBorderColor(self)
end
local function PT_Leave(self)
    ns._FB.hov[self] = nil
    ns._FB.ApplyBorderColor(self)
end

-- A frame coming on screen (its unit appeared, or its party frame showed): its unit re-read and a
-- full paint. Going off screen: the listeners follow.
local function PT_OnShow(self)
    if not ns._ptEnabled then return end
    PT_Classify(self)
    PT_Paint(self)
    PT_Recount()
end
local function PT_OnHide(self)
    PT_Recount(self)
end

-- The party header re-assigned an owner's unit (in combat too): its target frame follows at once.
-- The same unit set again (every header pass) returns after the compare.
local function PT_OwnerAttr(owner, name)
    if name ~= "unit" or not ns._ptEnabled then return end
    local frame = PT.frameOf[owner]
    if frame and PT_Classify(frame) and frame:IsVisible() then
        PT_Paint(frame)
        PT_Recount()
    end
end

-- Real-frame previews hide the real frames by alpha; while they do, a mouse blocker on each target
-- frame (they sit outside the party frames' blocker) keeps the invisible buttons from taking
-- clicks. Our frames, so Hide() is combat-legal; each blocker hides with its target frame.
ns._PT_SetPreviewBlock = function(on)
    PT.pvBlockOn = on or nil
    for _, frame in ipairs(ns._partyTargetFrames) do
        local blk = frame._ptBlock
        if on and ns._ptEnabled then
            if not blk then
                blk = CreateFrame("Frame", nil, frame)
                blk:SetAllPoints(frame)
                blk:EnableMouse(true)
                frame._ptBlock = blk
            end
            blk:SetFrameLevel(frame:GetFrameLevel() + 50)
            blk:Show()
        elseif blk then
            blk:Hide()
        end
    end
end

-- The enable/disable edges, a new frame and a frame strata change while blocked: re-seat the
-- blockers.
ns._PT_RefreshPreviewBlock = function()
    if PT.pvBlockOn then ns._PT_SetPreviewBlock(true) end
end

local function PT_Build(owner, globalName)
    local frame = CreateFrame("Button", globalName, owner, "SecureUnitButtonTemplate")
    frame:SetAttribute("useparent-unit", true)
    frame:SetAttribute("unitsuffix", "target")
    frame:SetAttribute("*type1", "target")
    frame:RegisterForClicks("AnyUp")
    frame:Hide()

    -- Background, health bar, texts and border frame (the stock edge under a stock style). The
    -- font comes with the next restyle, before the frame can show. Name only: no health texts.
    local FB = ns._FB
    FB.BuildVisuals(frame)
    local name = frame._nameText
    name:SetPoint("CENTER", frame._health, "CENTER", 0, 0)
    name:SetJustifyH("CENTER")
    name:SetJustifyV("MIDDLE")
    name:SetTextColor(1, 1, 1, 1)
    frame._healthText:Hide()
    frame._healAbsorbText:Hide()

    frame._ptOwner = owner
    FB.src[frame] = PT_Source
    frame:HookScript("OnShow", PT_OnShow)
    frame:HookScript("OnHide", PT_OnHide)
    frame:HookScript("OnEnter", PT_Enter)
    frame:HookScript("OnLeave", PT_Leave)
    -- Header buttons: the unit snippet reaches the frame through a frame ref, and a unit
    -- re-assignment re-reads it (a lookup table, never a key on the header's button).
    if owner ~= ns._partySelfButton then
        PT.frameOf[owner] = frame
        SecureHandlerSetFrameRef(owner, "ptframe", frame)
        owner:HookScript("OnAttributeChanged", PT_OwnerAttr)
    end
    table.insert(ns._partyTargetFrames, frame)
    return frame
end

-- The self button's frame (Show Self First / Last: its unit is "player", so it shows your target;
-- it hides with the self button while that is unused), built the first time Include Own Target is
-- on. True when built now. OOC only.
local function PT_EnsureSelf()
    if PT.selfFrame or not ns._partySelfButton then return false end
    PT.selfFrame = PT_Build(ns._partySelfButton, "ERFPartyTargetSelf")
    -- New frames take the next restyle in full.
    ns._PF.fp.pt = nil
    return true
end

-- One per party header button, built on the first enable. OOC only.
ns._PT_Create = function()
    if not ns._ptCreated and ns._partyHeader then
        ns._ptCreated = true
        for i = 1, 5 do
            local owner = ns._partyHeader[i]
            if owner then PT_Build(owner, "ERFPartyTarget" .. i) end
        end
        ns._PF.fp.pt = nil
    end
    if ns._ptInclDesired then PT_EnsureSelf() end
end

-- Include Own Target, applied: the self button's frame (built on first use) watched only while on,
-- the attributes and unit snippet that gate the header frame showing you, and your target's
-- listeners. Secure writes: out of combat; a combat call waits for the combat-end flush.
local function PT_ApplyInclude()
    if InCombatLockdown() then
        ns._ptSelfDirty = true
        return
    end
    ns._ptSelfDirty = nil
    local inc = (ns._ptEnabled and ns._ptInclDesired) and true or nil
    PT.include = inc
    if inc and PT_EnsureSelf() then
        -- Sized, placed and styled before it can show.
        PT.w = nil
        ns._PT_Layout()
        ns._PT_Restyle()
        ns._PT_RefreshPreviewBlock()
    end
    local sf = PT.selfFrame
    if sf and PT.selfWatched ~= inc then
        PT.selfWatched = inc
        if inc then
            PT_Classify(sf)
            RegisterUnitWatch(sf)
        else
            UnregisterUnitWatch(sf)
            sf:Hide()
        end
    end
    ns._ptNoSelf = (ns._ptEnabled and not inc) and true or nil
    PT_SeedAttrs()
    ns.PF_SyncUnitSnippet()
    PT_Recount()
end

-- The combat-end flush (ns.PF_Flush) of a deferred include edge or attribute seed.
ns._PT_SyncSelf = function()
    ns._ptSelfDirty = nil
    if ns._ptEnabled then PT_ApplyInclude() end
end

ns._PT_Apply = function()
    if ns._ptDesired == ns._ptEnabled then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("PT_Apply", ns._PT_Apply)
        return
    end
    if ns._ptDesired then
        ns._PT_Create()
        -- The listeners, made once: roster and zoning, UNIT_TARGET (three, two units each), your
        -- target's events, and the hidden value ticker.
        if not ns._ptEventFrame then
            local f = ns.TakeShell()
            f:SetScript("OnEvent", PT_OnEvent)
            ns._ptEventFrame = f
            for k = 1, 3 do
                f = ns.TakeShell()
                f:SetScript("OnEvent", PT_OnEvent)
                PT.tgtEv[k] = f
            end
            f = ns.TakeShell()
            f:SetScript("OnEvent", PT_OnOwnEvent)
            PT.ownFrame = f
            f = ns.TakeShell()
            f:Hide()
            f:SetScript("OnUpdate", PT_Tick)
            PT.ticker = f
        end
        local events = ns._ptEventFrame
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        ns._ptEnabled = true
        PT.include = ns._ptInclDesired or nil
        -- A full layout (the attached groups gain the reserve), a style check and the units, then
        -- the frames come up: the attributes gating yours are set before the watches.
        PT.w = nil
        ns._PT_Layout()
        ns._PT_Restyle()
        ns._PT_RefreshAll()
        PT_ApplyInclude()
        for _, frame in ipairs(ns._partyTargetFrames) do
            if frame ~= PT.selfFrame then RegisterUnitWatch(frame) end
        end
    else
        ns._ptEnabled = false
        ns._ptEventFrame:UnregisterAllEvents()
        for _, frame in ipairs(ns._partyTargetFrames) do
            UnregisterUnitWatch(frame)
            frame:Hide()
        end
        PT.include, PT.selfWatched, ns._ptNoSelf = nil, nil, nil
        ns._ptLayoutDirty, ns._ptSelfDirty = nil, nil
        -- Every listener and the ticker off; the gate attributes cleared, so a unit snippet kept for
        -- the pets leaves the target frames alone.
        PT_Recount()
        PT_SeedAttrs()
        ns.PF_SyncUnitSnippet()
        -- The party frames close the pitch the frames held along the stack, and the attached
        -- groups take the room back.
        if (ns._ptPitchApplied or 0) ~= 0 then ns._LayoutPartyFrames() end
        PT_NotifyReserve()
    end
    ns._PT_RefreshPreviewBlock()
end

ns.PT_SetEnabled = function(on)
    ns._ptDesired = on and true or false
    ns._PT_Apply()
end

-- Include Own Target (options, profile swaps): applied now while on, else on the enable edge.
ns.PT_SetIncludeSelf = function(on)
    ns._ptInclDesired = on and true or false
    if ns._ptEnabled then PT_ApplyInclude() end
end

-- A Fill Color or Background setting changed (the options): the fingerprint-gated restyle, which
-- repaints the frames on screen when anything it reads changed. Nothing while off.
ns.PT_Refresh = function()
    if ns._ptEnabled then ns._PT_Restyle() end
end

-- Options preview: a made-up target beside each party preview frame while Party Targets is on, on
-- the real frames' visuals and with their size, side, offsets and colours. Plain frames, built the
-- first time a preview shows them; ns.PT_PreviewSpec measures them and the room they need.
PT.pv, PT.pvSpec = {}, {}
PT.PV = {
    { name = "Gnoll Brute", hp = 72, re = 2 },
    { name = "Kobold Miner", hp = 100, re = 4 },
    { name = "Defias Thug", hp = 38, re = 2 },
    { name = "Murloc Raider", hp = 85, re = 2 },
    { name = "Bristleback Boar", hp = 55, re = 4 },
}

-- The preview's target layout, or nil while Party Targets is off: as the real frames take it
-- (after the Beside Owner pets on their side: petSpec, the pets' preview spec), plus how far a
-- frame reaches past its party frame's edges (pads). s: the preview's view; pw, ph: its party
-- frame size. One reused table.
function ns.PT_PreviewSpec(s, pw, ph, petSpec)
    if s.partyShowTargets ~= true then return nil end
    local t = PT.pvSpec
    local w, h = PixelSnap(s.partyTargetWidth or 70), PixelSnap(s.partyTargetHeight or 33)
    local x, y = PixelSnap(s.partyTargetOffsetX or 0), PixelSnap(s.partyTargetOffsetY or 0)
    local gap = PixelSnap(PT_Gap(s))
    local side, extra, across = PT_Side(s)
    local off = gap + PixelSnap(extra)
    if across and petSpec and petSpec.owner and petSpec.side == side then
        off = petSpec.gap + ((side == "above" or side == "below") and petSpec.h or petSpec.w) + gap
    end
    t.w, t.h, t.x, t.y, t.gap, t.off, t.side, t.across, t.pw, t.ph = w, h, x, y, gap, off, side, across, pw, ph
    -- The frame's box from its party frame's centre.
    local l, b
    if side == "left" then
        l, b = x - off - pw / 2 - w, y - h / 2
    elseif side == "right" then
        l, b = x + off + pw / 2, y - h / 2
    elseif side == "below" then
        l, b = x - w / 2, y - off - ph / 2 - h
    else
        l, b = x - w / 2, y + off + ph / 2
    end
    t.padL, t.padR = max(0, -pw / 2 - l), max(0, l + w - pw / 2)
    t.padB, t.padT = max(0, -ph / 2 - b), max(0, b + h - ph / 2)
    return t
end

-- The room a preview spec takes beside the preview's party frames (the pets beside them), as
-- ns.PT_Reserve gives the real frames'.
function ns.PT_PreviewReserve(spec, horizontal, before)
    return spec and PT_ReserveOf(spec, horizontal, before) or 0
end

-- Preview target i at the spec's size: styled from the party settings, painted from the view s
-- (made-up mobs: Class Color reads their reaction).
local function PT_PvFrame(i, parent, s, spec)
    local FB = ns._FB
    local f = PT.pv[i]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        FB.BuildVisuals(f)
        FB.src[f] = PT_Source
        local name = f._nameText
        name:SetPoint("CENTER", f._health, "CENTER", 0, 0)
        name:SetJustifyH("CENTER")
        name:SetJustifyV("MIDDLE")
        name:SetTextColor(1, 1, 1, 1)
        f._healthText:Hide()
        f._healAbsorbText:Hide()
        PT.pv[i] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    f:SetFrameStrata(parent == UIParent and "HIGH" or parent:GetFrameStrata())
    local w, h = spec.w, spec.h
    f:SetSize(w, h)
    FB.SizeVisuals(f, w, h)
    local st = PT_Source()
    local health, bg, name = f._health, f._bg, f._nameText
    health:SetStatusBarTexture(ResolveHealthTexture(st))
    local tex = health:GetStatusBarTexture()
    bg:ClearAllPoints()
    if tex then
        tex:SetHorizTile(false)
        bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    else
        bg:SetAllPoints(health)
    end
    ApplyFont(name, st.nameSize or 10)
    name:SetWidth(max(1, w - 6))
    FB.StyleBorder(f)
    local mock = PT.PV[i]
    health:SetMinMaxValues(0, 100)
    health:SetValue(mock.hp)
    name:SetText(mock.name)
    local mode = s.partyTargetHealthColorMode or "class"
    if mode == "dark" then
        local r, g, b, a = EUI.GetDarkModeFill()
        health:SetStatusBarColor(r, g, b, 1)
        if tex then tex:SetAlpha(a) end
        bg:SetColorTexture(EUI.GetDarkModeBg())
    else
        if tex then tex:SetAlpha(1) end
        local rc = FACTION_BAR_COLORS[mock.re]
        if mode == "classic" then
            local p = mock.hp / 100
            health:SetStatusBarColor(p < 0.5 and 1 or (1 - (p - 0.5) * 2), p > 0.5 and 1 or (p * 2), 0, 1)
        elseif mode == "custom" then
            local c = s.partyTargetCustomFillColor or PT.DEF_FILL
            health:SetStatusBarColor(c.r, c.g, c.b, 1)
        else
            health:SetStatusBarColor(rc.r, rc.g, rc.b, 1)
        end
        local a = (s.partyTargetBgDarkness or 50) / 100
        if s.partyTargetBgClassColored then
            bg:SetColorTexture(rc.r, rc.g, rc.b, a)
        else
            local c = s.partyTargetCustomBgColor or ns._PF.DEFAULT_BG
            bg:SetColorTexture(c.r, c.g, c.b, a)
        end
    end
    f:Show()
    return f
end

-- The preview targets beside the party preview frames on screen, parented to parent (skip: your
-- own frame's index, without Include Own Target), or none without a spec.
function ns.PT_ShowPreview(spec, s, parent, skip)
    local n = 0
    if spec then
        for i = 1, 5 do
            local o = ns._partyPvFrames[i]
            if o and o:IsShown() and i ~= skip then
                n = n + 1
                PT_Place(PT_PvFrame(n, parent, s, spec), o, spec.side, spec.off, spec.x, spec.y)
            end
        end
    end
    for i = n + 1, #PT.pv do PT.pv[i]:Hide() end
end

function ns.PT_HidePreview()
    for _, f in ipairs(PT.pv) do f:Hide() end
end
end -- Party Targets scope block

I.broken = false
