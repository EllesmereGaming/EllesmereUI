if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIChat_Forever.lua
--
--  The chat under WoW Forever (the Forever client's variant of Blizzard
--  Style, ns.ChatForever). Blizzard's chat frame art and input art are
--  stripped as on the EllesmereUI look, and the Forever bronze kit is drawn
--  on OUR frames only:
--    - the panel (CFD(cf).bg): a message frame and an input frame
--    - the ghost tabs (EllesmereUIChat_Tabs.lua): bronze tabs, warm while
--      selected
--    - the sidebar buttons: square bronze plates with tan glyphs (a kit for
--      EllesmereUIChat_SidebarStock.lua)
--  Every piece is framed by the bronze line of Forever's micro menu box
--  (EllesmereUI.ForeverBorder: that art cut hollow, at its own size) over our
--  own fill; the selected tab and a hovered plate add an additive copy that
--  warms the line toward copper. The variant latch asks for the art: a
--  client without it renders plain Blizzard Style.
--
--  At load this file only defines data and functions: nothing is built,
--  registered or hooked off the variant (every caller tests the latch).
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = _G.EllesmereUI
local ECHAT = ns.ECHAT
if not ECHAT or not EUI then return end
local CFD = EUI._chatCFD
local BORDER = EUI.FOREVER_BORDER

local FV = {
    lift   = { 1, 0.75, 0.45, 0.6 },   -- the additive copy: tint, alpha
    -- Panel geometry off the chat frame's rect (UI units): both frames' outer
    -- edges X past its sides (the text stands well clear of the line) and
    -- TOP above it (Blizzard's tab row stands there), the message frame
    -- MSG_B under the text, a GAP, then the input frame with IN_PAD round
    -- the edit box, whose sides sit EB_X past the text's (its chat-type
    -- header, 15 into the box, lands on the text column). The combat log's
    -- filter bar (CL_BAR tall, above its window) sits inside that window's
    -- frame.
    X = 20, TOP = 3, MSG_B = 11, GAP = 4, IN_PAD = 5, EB_X = 15, CL_BAR = 24,
    -- Each tab's line in from its ghost's sides and top by its outer
    -- shadow's reach, so the ghost's clip keeps that shadow.
    tabInset = BORDER.outer,
    tabX = 8,      -- the first docked tab's left edge in from the panel's
    gold  = { 1, 0.82, 0 },
    tan   = { 0.83, 0.71, 0.52 },
    thumb = { 0.72, 0.56, 0.36, 0.7 },
    plateFill = { 0.06, 0.06, 0.065, 0.92 },
    -- Tab bodies, bottom then top: selected (warm) and idle.
    tabSel  = { 0.17, 0.09, 0.035, 0.95, 0.12, 0.063, 0.024, 0.95 },
    tabIdle = { 0.08, 0.08, 0.085, 0.92, 0.10, 0.10, 0.105, 0.92 },
    -- The last fill ApplyBackground painted (panels built later take it).
    _fill = { r = 0.03, g = 0.045, b = 0.05, a = 0.65 },
}
ECHAT.FV = FV

-------------------------------------------------------------------------------
--  Framed box: the line and the body fill under it, on an art host of ours.
-------------------------------------------------------------------------------
local function NewBox(host)
    local box = { host = host }
    box.fill = host:CreateTexture(nil, "BACKGROUND")
    box.rim = EUI.ForeverBorder(host, "BORDER")
    return box
end

local function Seat(t, host, tp, x1, y1, x2, y2)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", host, tp, x1, y1)
    t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", x2, y2)
end

-- The line's outer edge on the host's sides (pulled in by inX), its top ty
-- off the host point tp (TOPLEFT or BOTTOMLEFT) and its bottom by above the
-- host's bottom; the fill from the line's inner edge.
local function SeatBox(box, host, tp, ty, by, inX)
    local f, x = BORDER.line, inX or 0
    local s = box.seat
    if not s then s = {}; box.seat = s end
    s[1], s[2], s[3], s[4], s[5] = tp, x, ty, -x, by
    EUI.ForeverBorderSeat(box.rim, host, tp, x, ty, -x, by)
    if box.lift then EUI.ForeverBorderSeat(box.lift, host, tp, x, ty, -x, by) end
    Seat(box.fill, host, tp, x + f, ty - f, -x - f, by + f)
end

-- The line's copper copy over it (the selected tab, a hovered plate), built
-- the first time it shows, on the line's seat.
local function ShowLift(box, shown)
    local lift = box.lift
    if not lift then
        if not shown then return end
        local l, s = FV.lift, box.seat
        lift = EUI.ForeverBorder(box.host, "ARTWORK", 0, true)
        EUI.ForeverBorderPaint(lift, l[1], l[2], l[3], l[4])
        EUI.ForeverBorderSeat(lift, box.host, s[1], s[2], s[3], s[4], s[5])
        box.lift = lift
    end
    EUI.ForeverBorderShown(lift, shown)
end

local function PaintFill(t, tex, r, g, b, a)
    if tex then
        t:SetTexture(tex)
        t:SetVertexColor(r, g, b, a)
    else
        t:SetVertexColor(1, 1, 1, 1)
        t:SetColorTexture(r, g, b, a)
    end
end

-------------------------------------------------------------------------------
--  Panel: the message frame round the text and the input frame round the
--  edit box, on one art host that covers our panel (never a Blizzard frame).
-------------------------------------------------------------------------------
-- How far the panel reaches under the chat frame's rect.
function ECHAT.FV_PanelDrop(inputH)
    return FV.MSG_B + FV.GAP + 2 * FV.IN_PAD + inputH
end

-- The edit box in the input frame: the same plain setters the EllesmereUI
-- look uses (every window, temporary ones included; no hooks here).
function ECHAT.FV_PlaceEditBox(cf, eb, inputH)
    local y = -(FV.MSG_B + FV.GAP + FV.IN_PAD)
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -FV.EB_X, y)
    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", FV.EB_X, y)
    eb:SetHeight(inputH)
end

-- Seats the input and records the panel insets (numeric placement off the
-- chat frame's rect, PositionChatPanel; the engine derives the text area).
function ECHAT.FV_SeatInput(cf, eb, inputH)
    if eb then ECHAT.FV_PlaceEditBox(cf, eb, inputH) end
    local d = CFD(cf)
    local ins = d._bgIns
    if not ins then ins = {}; d._bgIns = ins end
    ins.l, ins.r = -FV.X, FV.X
    ins.t = FV.TOP + ((cf == _G.ChatFrame2) and FV.CL_BAR or 0)
    ins.b = -ECHAT.FV_PanelDrop(inputH)
    ECHAT.FV_LayoutPanel(cf, inputH)
end

-- Both boxes off the panel's edges; re-seated only when the input height
-- changes.
function ECHAT.FV_LayoutPanel(cf, inputH)
    local d = CFD(cf)
    local host = d.fvHost
    if not host or d.fvInputH == inputH then return end
    d.fvInputH = inputH
    local inTall = inputH + 2 * FV.IN_PAD
    SeatBox(d.fvMsg, host, "TOPLEFT", 0, inTall + FV.GAP)
    SeatBox(d.fvIn, host, "BOTTOMLEFT", inTall, 0)
end

-- Built once per panel, at its creation. The host sits one level over the
-- panel, under our message frame (panel + 4).
function ECHAT.FV_BuildPanel(cf, bg, inputH)
    local d = CFD(cf)
    if d.fvHost then return end
    local host = CreateFrame("Frame", nil, bg)
    host:SetAllPoints(bg)
    d.fvHost = host
    d.fvMsg, d.fvIn = NewBox(host), NewBox(host)
    ECHAT.FV_LayoutPanel(cf, inputH)
    local p = FV._fill
    PaintFill(d.fvMsg.fill, p.tex, p.r, p.g, p.b, p.a)
    PaintFill(d.fvIn.fill, p.tex, p.r, p.g, p.b, p.a)
end

-- The chat background colour/texture (Chat page) fills both boxes.
function ECHAT.FV_PaintFills(tex, r, g, b, a)
    local p = FV._fill
    p.tex, p.r, p.g, p.b, p.a = tex, r, g, b, a
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        local d = cf and CFD(cf)
        if d and d.fvHost then
            PaintFill(d.fvMsg.fill, tex, r, g, b, a)
            PaintFill(d.fvIn.fill, tex, r, g, b, a)
        end
    end
end

-------------------------------------------------------------------------------
--  Tabs: each ghost wears a bronze tab whose bottom line and lower chamfers
--  run under the panel's top edge and are clipped away, so its sides meet
--  the message frame's line. Built once per ghost; repainted only when its
--  selected state flips.
-------------------------------------------------------------------------------
local tabCol   -- colour objects (selected bottom, top, idle bottom, top)
local function TabColours()
    local s, i = FV.tabSel, FV.tabIdle
    tabCol = {
        CreateColor(s[1], s[2], s[3], s[4]), CreateColor(s[5], s[6], s[7], s[8]),
        CreateColor(i[1], i[2], i[3], i[4]), CreateColor(i[5], i[6], i[7], i[8]),
    }
end

function ECHAT.FV_StyleGhost(g, isActive)
    local art = g._fvArt
    if not art then
        local clip = CreateFrame("Frame", nil, g)
        clip:SetAllPoints(g)
        clip:SetClipsChildren(true)
        art = CreateFrame("Frame", nil, clip)
        art:SetAllPoints(clip)
        -- Label and alert glow over the art (they are the ghost's regions).
        local top = CreateFrame("Frame", nil, g)
        top:SetAllPoints(g)
        g._fs:SetParent(top)
        g._glow:SetParent(top)
        -- The selected tab's line reads warmer than the panel's (the lift,
        -- shown only while selected).
        local box = NewBox(art)
        box.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        -- The bottom line sits the corners' reach under the ghost, so the
        -- clip takes it and both lower chamfers: the sides run straight
        -- down to the ghost's bottom edge.
        SeatBox(box, art, "TOPLEFT", -FV.tabInset, -BORDER.corner, FV.tabInset)
        g._fvClip, g._fvArt, g._fvTop, g._fvBox = clip, art, top, box
        g._bg:Hide()
        g._underline:Hide()
        g._sep:Hide()
        g._borderHost:Hide()
        if not tabCol then TabColours() end
    end
    -- Relative levels, re-asserted: docked ghosts change parent between
    -- passes (strip / scroll clip).
    local L = g:GetFrameLevel()
    if g._fvClip:GetFrameLevel() ~= L + 1 then g._fvClip:SetFrameLevel(L + 1) end
    if art:GetFrameLevel() ~= L + 2 then art:SetFrameLevel(L + 2) end
    if g._fvTop:GetFrameLevel() ~= L + 3 then g._fvTop:SetFrameLevel(L + 3) end
    if g._fvOn == isActive then return end
    g._fvOn = isActive
    local box = g._fvBox
    local v = isActive and 1 or 0.85
    EUI.ForeverBorderPaint(box.rim, v, v, v, 1, not isActive)
    ShowLift(box, isActive)
    if isActive then
        box.fill:SetGradient("VERTICAL", tabCol[1], tabCol[2])
    else
        box.fill:SetGradient("VERTICAL", tabCol[3], tabCol[4])
    end
end

-------------------------------------------------------------------------------
--  Sidebar plates: the square bronze button under a sidebar button's own
--  regions (glyph, count), its line warmed on hover. `on` false hides it
--  (the scroll button's chat seat wears plain art).
-------------------------------------------------------------------------------
local function PlateEnter(self)
    local p = self._fvPlate
    if p then ShowLift(p, true) end
end
local function PlateLeave(self)
    local p = self._fvPlate
    if p then ShowLift(p, false) end
end

function ECHAT.FV_Plate(btn, on)
    local p = btn._fvPlate
    if not p then
        if not on then return end
        local host = CreateFrame("Frame", nil, btn)
        host:SetAllPoints(btn)
        p = NewBox(host)
        local c = FV.plateFill
        p.fill:SetColorTexture(c[1], c[2], c[3], c[4])
        SeatBox(p, host, "TOPLEFT", 0, 0)
        btn._fvPlate = p
        btn:HookScript("OnEnter", PlateEnter)
        btn:HookScript("OnLeave", PlateLeave)
    end
    -- One level under the button (re-asserted: the scroll button changes
    -- level with its seat).
    local L = btn:GetFrameLevel()
    local want = L > 0 and L - 1 or 0
    if p.host:GetFrameLevel() ~= want then p.host:SetFrameLevel(want) end
    p.host:SetShown(on and true or false)
    return p
end

-------------------------------------------------------------------------------
--  Sidebar kit (read by ECHAT.SB_Latch under the variant): bronze plates,
--  Blizzard's glyphs where it has them and ours elsewhere, all in tan; the
--  column stands GAP clear of the panel's left edge (the same gap as
--  between the panel's two frames), level with its top.
--  Built on the Forever client only (the latch nil-guards the kit).
-------------------------------------------------------------------------------
local Entry = ECHAT.SB_Entry
if EUI.IS_FOREVER and Entry and ECHAT.SB_KITS then
    local MEDIA = "Interface\\AddOns\\EllesmereUIChat\\Media\\"
    local TAN = FV.tan
    -- Blizzard's atlas glyphs desaturate darker than our white PNG ink: a
    -- brighter tint (tan / 0.83) lands them on the same tan.
    local ATL_TINT = { 1, 0.86, 0.63 }
    local FSQ = { w = 34, h = 34, padT = 0, padB = 0, plate = true, push = true }
    local function A(atlas, w, h, y) return { atlas = atlas, w = w, h = h, y = y, tint = ATL_TINT } end
    local function P(name, y) return { file = MEDIA .. name, w = 18, h = 18, y = y } end
    local blizz = ECHAT.SB_KITS.blizzard
    ECHAT.SB_KITS.forever = {
        col = { dx = -FV.GAP, top = 0, bot = 0 }, colW = 34, gap = 8, voiceState = true, flash = "fade",
        tint = TAN, countColor = TAN, countY = 5,
        friends    = Entry(FSQ, { count = "inside", glyph = {
                        A("socialqueuing-icon-group", 20, 17, 5), P("chat_friends.png", 5) } }),
        guild      = Entry(FSQ, { count = "below", glyph = {
                        A("friends-icon-tab-guildmates", 17, 17), P("chat_guild.png") } }),
        durability = Entry(FSQ, { count = "inside", alert = true, glyph = { P("chat_durability.png", 5) },
                        alertColors = { [0] = { TAN[1], TAN[2], TAN[3], 1 },
                                        { 1, 0.5, 0.1, 1 }, { 0.93, 0.07, 0.07, 1 } } }),
        copy       = Entry(FSQ, { glyph = { P("chat_copy.png") } }),
        portals    = Entry(FSQ, { glyph = { P("chat_portal.png") } }),
        voice      = Entry(FSQ, { glyph = { A("chatframe-button-icon-voicechat", 20, 20) } }),
        settings   = Entry(FSQ, { glyph = { P("chat_settings.png") } }),
        language   = Entry(FSQ, { glyph = { P("chat_language.png") } }),
        scroll = {
            sidebar = { w = 34, h = 34, plate = true,
                        glyph = { A("minimal-scrollbar-arrow-returntobottom", 17, 15) },
                        flashArt = { atlas = "minimal-scrollbar-arrow-returntobottom" } },
            chat    = blizz and blizz.scroll and blizz.scroll.chat,
        },
    }
end
