if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIChat_SidebarStock.lua
--
--  The chat sidebar under the stock styles (Global Settings > Style):
--  Blizzard Style dresses it as Blizzard's own chat button column (the
--  ButtonFrame seat, a copy of its bordered backdrop in the window colour,
--  the chat button plates, the QuickJoin friends button, the voice plate, the
--  settings gear and the return-to-bottom arrow); Classic WoW UI dresses it
--  as the vanilla column (bevelled square buttons, the chat menu button, the
--  scroll-down button, no backdrop). Where Blizzard has no art for one of our
--  buttons (guild, copy, portals) our own glyph sits on the kit's button in
--  Blizzard's gold. Durability matches them (our glyph in gold on the kit's
--  button), tinted by the worst equipment alert.
--
--  Everything here dresses OUR sidebar and buttons (UIParent-parented frames
--  the chat module creates); no Blizzard frame is touched. Loaded after the
--  main chat file: at load it only builds static data tables. The main file
--  reads ECHAT.SB_KIT (nil on the EllesmereUI look, so each hook there costs
--  one nil test) and calls the helpers below.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = _G.EllesmereUI
local ECHAT = ns.ECHAT
if not ECHAT or not EUI then return end
local CFD = EUI._chatCFD
local issecretvalue = _G.issecretvalue

local MEDIA = "Interface\\AddOns\\EllesmereUIChat\\Media\\"
local HILIGHT = { file = "Interface\\Buttons\\UI-Common-MouseHilight" }
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

-- Our glyph drawn whole at 18x18 in gold (the ink fills 60-83% of the box,
-- about Blizzard's 15px icon atlas).
local function PNG(name)
    return { file = MEDIA .. name, w = 18, h = 18, gold = true }
end
-- A kit entry: the base button's fields, then the entry's own.
local function Entry(base, t)
    t = t or {}
    if base then for k, v in pairs(base) do if t[k] == nil then t[k] = v end end end
    return t
end

-- Button bases. w/h at scale 1; padT/padB = the art's transparent rows (the
-- visible gap between icons is measured art to art).
local PLATE = {   -- Blizzard's chat button plate (the voice button's)
    w = 27, h = 26, padT = 1, padB = 1,
    n = { atlas = "chatframe-button-up" }, p = { atlas = "chatframe-button-down" },
    hl = { atlas = "chatframe-button-highlight" }, hlBlend = "ADD", push = true,
}
local QJ = {      -- the QuickJoin friends button, count inside
    w = 32, h = 32, padT = 0, padB = 0, count = "inside",
    n = { atlas = "quickjoin-button-friendslist-up" }, p = { atlas = "quickjoin-button-friendslist-down" },
    hl = HILIGHT, hlBlend = "ADD",
}
local BEVEL = {   -- the vanilla square chat bevel (the gold square button, desaturated)
    w = 32, h = 32, padT = 3, padB = 3, inset = 0.4,
    n = { file = "Interface\\Buttons\\UI-SquareButton-Up", desat = true },
    p = { file = "Interface\\Buttons\\UI-SquareButton-Down", desat = true },
    hl = HILIGHT, hlBlend = "ADD", push = true,
}
local GEAR = {    -- the Damage Meter settings gear: the whole button is the art
    idle = "common-dropdown-a-button-settings-shadowless",
    over = "common-dropdown-a-button-settings-hover-shadowless",
    down = "common-dropdown-a-button-settings-pressed-shadowless",
    both = "common-dropdown-a-button-settings-pressedhover-shadowless",
}
local GEAR_PROBE = { atlas = GEAR.idle }

ECHAT.SB_KITS = {
    blizzard = {
        col = { dx = 1, top = -7, bot = 10 }, gap = 4, backdrop = true, voiceState = true, flash = "fade",
        friends    = Entry(QJ),
        guild      = Entry(PLATE, { count = "below", glyph = {
                        { atlas = "friends-icon-tab-guildmates", w = 17, h = 17 }, PNG("chat_guild.png") } }),
        durability = Entry(PLATE, { count = "below", alert = true, glyph = { PNG("chat_durability.png") } }),
        copy       = Entry(PLATE, { glyph = { PNG("chat_copy.png") } }),
        portals    = Entry(PLATE, { glyph = { PNG("chat_portal.png") } }),
        voice      = Entry(PLATE, { glyph = { { atlas = "chatframe-button-icon-voicechat", w = 15, h = 15 } } }),
        settings   = { w = 27, h = 27, padT = 1, padB = 1, gear = true,
                       alt = Entry(PLATE, { glyph = { PNG("chat_settings.png") } }) },
        scroll = {
            sidebar = { w = 32, h = 32,
                        n = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" },
                        p = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down" },
                        hl = HILIGHT, hlBlend = "ADD",
                        flashArt = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" } },
            chat    = { w = 17, h = 15,
                        n = { atlas = "minimal-scrollbar-arrow-returntobottom" },
                        p = { atlas = "minimal-scrollbar-arrow-returntobottom-down" },
                        hl = { atlas = "minimal-scrollbar-arrow-returntobottom-over" },
                        flashArt = { atlas = "minimal-scrollbar-arrow-returntobottom" } },
        },
    },
    classic = {
        col = { dx = 1, top = -4, bot = 4 }, gap = 4, flash = "blink",
        friends    = Entry(QJ),
        guild      = Entry(BEVEL, { count = "below", glyph = { PNG("chat_guild.png") } }),
        durability = Entry(BEVEL, { count = "below", alert = true, glyph = { PNG("chat_durability.png") } }),
        copy       = Entry(BEVEL, { glyph = {
                        { file = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", probe = true,
                          tc = { 0.125, 0.875, 0.0625, 0.9375 }, w = 12, h = 14 },
                        PNG("chat_copy.png") } }),
        portals    = Entry(BEVEL, { glyph = { PNG("chat_portal.png") } }),
        voice      = Entry(BEVEL, { glyph = {
                        { file = "Interface\\Common\\VoiceChat-Speaker",
                          tc = { 0, 0.59375, 0.15625, 0.90625 }, w = 11, h = 14 } } }),
        settings   = { w = 32, h = 32, padT = 3, padB = 3,
                       n = { file = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up" },
                       p = { file = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Down" },
                       hl = HILIGHT, hlBlend = "ADD" },
        scroll = {
            sidebar = { w = 32, h = 32,
                        n = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up", probe = true,
                              alt = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" } },
                        p = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Down", probe = true,
                              alt = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down" } },
                        hl = HILIGHT, hlBlend = "ADD",
                        flashArt = { file = "Interface\\ChatFrame\\UI-ChatIcon-BlinkHilight", probe = true,
                                     alt = HILIGHT } },
        },
    },
}
ECHAT.SB_KITS.classic.scroll.chat = Entry(ECHAT.SB_KITS.classic.scroll.sidebar, { w = 24, h = 24 })

-- Worst equipment alert -> durability glyph tint: the kits' gold while all is
-- fine (full opacity, so it never reads as disabled), then orange (damaged)
-- and red (broken); Blizzard's damaged yellow is nearly the gold. An entry's
-- own alertColors would override it.
ECHAT.SB_ALERT = { [0] = { GOLD_R, GOLD_G, GOLD_B, 1 }, { 1, 0.5, 0.1, 1 }, { 0.93, 0.07, 0.07, 1 } }
ECHAT.SB_REF = {
    friends = "friendsBtn", guild = "guildBtn", durability = "durabilityBtn", copy = "copyBtn",
    portals = "portalBtn", voice = "voiceBtn", settings = "settingsBtn",
}
ECHAT._sbBdMemo = {}

-- The stock kit for this session (the style is latched before the sidebar
-- is built). The two hot hooks the main file tests stay nil on the
-- EllesmereUI look.
function ECHAT.SB_Latch()
    local kit = ns.ChatStock and ns.ChatStock() and ECHAT.SB_KITS[ns.ChatStyle()] or nil
    ECHAT.SB_KIT = kit
    ECHAT.SB_SyncBackdrop = (kit and kit.backdrop) and ECHAT._SB_SyncBackdropImpl or nil
    ECHAT.SB_FlashSync = kit and ECHAT._SB_FlashSyncImpl or nil
end

-- Art present in this client (memoised on our own data table, once per
-- session): atlases through GetAtlasInfo, probed files through their id.
function ECHAT.SB_ArtOK(e)
    if not e then return false end
    if e._ok == nil then
        if e.atlas then
            e._ok = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(e.atlas)) and true or false
        elseif e.probe then
            local f = _G.GetFileIDFromPath
            e._ok = (f and f(e.file)) and true or false
        else
            e._ok = true
        end
    end
    return e._ok
end
local function Pick(e)
    while e and not ECHAT.SB_ArtOK(e) do e = e.alt end
    return e
end
local function SetStateArt(btn, which, e, blend)
    if not e then return end
    if which == "Highlight" then
        if e.atlas then
            if blend then btn:SetHighlightAtlas(e.atlas, blend) else btn:SetHighlightAtlas(e.atlas) end
        else
            btn:SetHighlightTexture(e.file, blend)
        end
        return
    end
    if e.atlas then
        btn["Set" .. which .. "Atlas"](btn, e.atlas)
    else
        btn["Set" .. which .. "Texture"](btn, e.file)
        local t = btn["Get" .. which .. "Texture"](btn)
        if t and e.desat then t:SetDesaturated(true) end
    end
end

-- Default sidebar width: Blizzard's 29px column (30 = the slider minimum),
-- following Icon Size; 40 on the EllesmereUI look.
function ECHAT.SidebarWidthDefault()
    if not ECHAT.SB_KIT then return 40 end
    return math.max(30, math.floor(29 * (ECHAT.DB().sidebarIconScale or 1) + 0.5))
end

-- The sidebar on the kit's column seat: Blizzard's ButtonFrame rect (its
-- right edge 1px inside our panel, which sits 4px outside the chat
-- background), mirrored for Show Sidebar on Right; Separate Sidebar adds its
-- gap.
function ECHAT.SB_Place(sb, bg, cfg)
    local c = ECHAT.SB_KIT.col
    local gap = (cfg.sidebarSeparate == true) and (cfg.sidebarSeparateSpacing or 8) or 0
    if cfg.sidebarRight then
        sb:SetPoint("TOPLEFT", bg, "TOPRIGHT", -c.dx + gap, c.top)
        sb:SetPoint("BOTTOMLEFT", bg, "BOTTOMRIGHT", -c.dx + gap, c.bot)
    else
        sb:SetPoint("TOPRIGHT", bg, "TOPLEFT", c.dx - gap, c.top)
        sb:SetPoint("BOTTOMRIGHT", bg, "BOTTOMLEFT", c.dx - gap, c.bot)
    end
end

-- Blizzard Style: a copy of the chat window's bordered backdrop (the
-- FloatingBorderedFrame template Blizzard hangs on its ButtonFrame) on a
-- child of our sidebar, under the buttons, in the window colour.
local BD = "Interface\\ChatFrame\\"
function ECHAT.SB_BuildBackdrop(sidebar, d)
    local bd = CreateFrame("Frame", nil, sidebar)
    bd:SetAllPoints()
    bd:SetFrameLevel(sidebar:GetFrameLevel())
    bd:EnableMouse(false)
    local fill = bd:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", sidebar, "TOPLEFT", -2, 3)
    fill:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 2, -6)
    local function Corner(point, x, y, l, r, t, b)
        local c = bd:CreateTexture(nil, "BORDER")
        c:SetTexture(BD .. "UI-ChatFrame-BorderCorner")
        c:SetSize(8, 8)
        c:SetPoint(point, fill, point, x, y)
        c:SetTexCoord(l, r, t, b)
        return c
    end
    local tl = Corner("TOPLEFT", -4, 4, 0, 1, 0, 1)
    local bl = Corner("BOTTOMLEFT", -4, -4, 0, 1, 1, 0)
    local tr = Corner("TOPRIGHT", 4, 4, 1, 0, 0, 1)
    local br = Corner("BOTTOMRIGHT", 4, -4, 1, 0, 1, 0)
    local left = bd:CreateTexture(nil, "BORDER")
    left:SetTexture(BD .. "UI-ChatFrame-BorderLeft", nil, "REPEAT")
    left:SetVertTile(true)
    left:SetWidth(16)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    local right = bd:CreateTexture(nil, "BORDER")
    right:SetTexture(BD .. "UI-ChatFrame-BorderLeft", nil, "REPEAT")
    right:SetVertTile(true)
    right:SetWidth(16)
    right:SetTexCoord(1, 0, 0, 1)
    right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local bottom = bd:CreateTexture(nil, "BORDER")
    bottom:SetTexture(BD .. "UI-ChatFrame-BorderTop", "REPEAT")
    bottom:SetHorizTile(true)
    bottom:SetHeight(16)
    bottom:SetTexCoord(0, 1, 1, 0)
    bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local top = bd:CreateTexture(nil, "BORDER")
    top:SetTexture(BD .. "UI-ChatFrame-BorderTop", "REPEAT")
    top:SetHorizTile(true)
    top:SetHeight(16)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    d.sbBackdrop, d.sbFill = bd, fill
    d.sbRims = { tl, bl, tr, br, left, right, bottom, top }
    if ECHAT.SB_SyncBackdrop then ECHAT.SB_SyncBackdrop(true) end
end

-- The backdrop in the SELECTED window's stored colour and opacity (what
-- Blizzard paints its own column in); memoised, a secret read skips.
function ECHAT._SB_SyncBackdropImpl(force)
    local cf1 = _G.ChatFrame1
    local d = cf1 and CFD(cf1)
    local fill = d and d.sbFill
    if not fill then return end
    -- Hidden (Hide Sidebar Background): nothing to paint; showing it again
    -- forces a sync.
    if not force and not d.sbBackdrop:IsShown() then return end
    local id = 1
    local sel = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local cc = Constants and Constants.ChatFrameConstants
    local sid = sel and sel.GetID and sel:GetID()
    if sid and sid >= 1 and sid <= ((cc and cc.MaxChatWindows) or 10) then id = sid end
    if not GetChatWindowInfo then return end
    local _, _, r, g, b, a = GetChatWindowInfo(id)
    if type(a) ~= "number" or (issecretvalue and (issecretvalue(r) or issecretvalue(a))) then return end
    local m = ECHAT._sbBdMemo
    if not force and m[1] == r and m[2] == g and m[3] == b and m[4] == a then return end
    m[1], m[2], m[3], m[4] = r, g, b, a
    fill:SetColorTexture(r, g, b, a)
    local rims = d.sbRims
    for i = 1, #rims do rims[i]:SetVertexColor(r, g, b, a) end
end

-- Pressed glyph: Blizzard's (-1,-2) at 0.75 (vanilla -Down art moves the
-- glyph the same way). Shared functions on our buttons, no closures.
function ECHAT.SB_GlyphDown(self, button)
    if button and button ~= "LeftButton" then return end
    local ic = self._icon
    if ic and self._sbGlyph then
        self._sbPushed = true
        ic:ClearAllPoints(); ic:SetPoint("CENTER", self, "CENTER", -1, -2); ic:SetAlpha(0.75)
    end
end
-- Also on OnHide (a press can end off the button): only a pressed glyph has
-- anything to put back.
function ECHAT.SB_GlyphUp(self)
    if not self._sbPushed then return end
    self._sbPushed = nil
    local ic = self._icon
    if ic and self._sbGlyph then
        ic:ClearAllPoints(); ic:SetPoint("CENTER", self, "CENTER", 0, 0); ic:SetAlpha(1)
    end
end
-- The gear's states follow Blizzard's own order (pressed-hover, hover,
-- pressed, idle).
function ECHAT.SB_GearPaint(self)
    local ic = self._icon
    if not ic then return end
    local a = (self._sbDown and self._sbOver and GEAR.both) or (self._sbOver and GEAR.over)
        or (self._sbDown and GEAR.down) or GEAR.idle
    if self._sbGearArt ~= a then self._sbGearArt = a; ic:SetAtlas(a) end
end
function ECHAT.SB_GearEnter(self) self._sbOver = true; ECHAT.SB_GearPaint(self) end
function ECHAT.SB_GearLeave(self) self._sbOver = nil; ECHAT.SB_GearPaint(self) end
function ECHAT.SB_GearDown(self, button)
    if button and button ~= "LeftButton" then return end
    self._sbDown = true; ECHAT.SB_GearPaint(self)
end
function ECHAT.SB_GearUp(self) self._sbDown = nil; ECHAT.SB_GearPaint(self) end

-- Dress one of our sidebar buttons with the kit's entry for `key`.
function ECHAT.SB_Dress(btn, key)
    local kit = ECHAT.SB_KIT
    local e = kit and kit[key]
    if not e then return end
    if e.gear and not ECHAT.SB_ArtOK(GEAR_PROBE) then e = e.alt end
    btn._sbEntry = e
    btn._sbKey = key
    btn._sbTailInside = (e.count == "inside") or nil
    local icon = btn._icon
    if e.gear then
        icon:SetDrawLayer("ARTWORK")
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1, 1)
        ECHAT.SB_GearPaint(btn)
        btn:HookScript("OnEnter", ECHAT.SB_GearEnter)
        btn:HookScript("OnLeave", ECHAT.SB_GearLeave)
        btn:HookScript("OnMouseDown", ECHAT.SB_GearDown)
        btn:HookScript("OnMouseUp", ECHAT.SB_GearUp)
        btn:HookScript("OnHide", ECHAT.SB_GearUp)
        return
    end
    SetStateArt(btn, "Normal", Pick(e.n))
    SetStateArt(btn, "Pushed", Pick(e.p))
    SetStateArt(btn, "Highlight", Pick(e.hl), e.hlBlend)
    if e.inset then
        local t = btn:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(0, 0, 0, e.inset)
        btn._sbInset = t
    end
    local g
    if e.glyph then
        for i = 1, #e.glyph do
            if ECHAT.SB_ArtOK(e.glyph[i]) then g = e.glyph[i]; break end
        end
    end
    if g then
        icon:SetDrawLayer("OVERLAY")
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetDesaturated(false)
        if g.atlas then
            icon:SetAtlas(g.atlas)
        else
            icon:SetTexture(g.file)
            local tc = g.tc
            if tc then icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) else icon:SetTexCoord(0, 1, 0, 1) end
        end
        if g.gold then icon:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1) else icon:SetVertexColor(1, 1, 1, 1) end
        btn._sbGW, btn._sbGH = g.w, g.h
        icon:Show()
        if e.push then
            btn._sbGlyph = true
            btn:HookScript("OnMouseDown", ECHAT.SB_GlyphDown)
            btn:HookScript("OnMouseUp", ECHAT.SB_GlyphUp)
            btn:HookScript("OnHide", ECHAT.SB_GlyphUp)
        end
    else
        icon:Hide()
    end
end

-- Scroll-to-bottom button: the art the stock UI shows in that seat, plus the
-- scrolled-back flash (a copy of the art, ADD, animated only while the
-- selected window is scrolled back). Re-run on every seat change.
function ECHAT.SB_DressScroll(btn, seat)
    local kit = ECHAT.SB_KIT
    local e = kit and kit.scroll and kit.scroll[seat]
    if not e then return end
    btn._sbEntry = e
    if btn._icon then btn._icon:Hide() end
    SetStateArt(btn, "Normal", Pick(e.n))
    SetStateArt(btn, "Pushed", Pick(e.p))
    SetStateArt(btn, "Highlight", Pick(e.hl), e.hlBlend)
    local fl = btn._sbFlash
    if not fl then
        fl = btn:CreateTexture(nil, "OVERLAY")
        fl:SetAllPoints(btn)
        fl:SetAlpha(0)
        fl:Hide()
        local ag = fl:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local function Step(order, from, to, dur)
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetOrder(order)
        end
        if kit.flash == "blink" then
            -- Vanilla: hard on for half a second, off for half a second.
            Step(1, 1, 1, 0.5); Step(2, 0, 0, 0.5)
        else
            -- Retail: 0.1s in, 0.5s held, 0.1s out, 0.5s off.
            Step(1, 0, 1, 0.1); Step(2, 1, 1, 0.5); Step(3, 1, 0, 0.1); Step(4, 0, 0, 0.5)
        end
        btn._sbFlash, btn._sbFlashAG = fl, ag
    end
    local fa = Pick(e.flashArt)
    if fa then
        if fa.atlas then fl:SetAtlas(fa.atlas) else fl:SetTexture(fa.file) end
        fl:SetBlendMode("ADD")
    end
end

-- A count under its button, or inside it (the QuickJoin plate), in the
-- Fonts-page chat font with the house shadow. Always a region of its own
-- button, which sits above the Blizzard Style backdrop (a region of the
-- sidebar itself would share the backdrop's frame level and can draw under
-- its fill).
function ECHAT.SB_MakeCount(btn, sidebar, key)
    local e = btn._sbEntry
    local inside = e and e.count == "inside"
    local fs = btn:CreateFontString(nil, "OVERLAY")
    if EUI.PrimeFontShadow then EUI.PrimeFontShadow(fs, true) end
    fs:SetFont(ECHAT.GetFont(), 10, "")
    fs:SetTextColor(1, 1, 1, 1)
    if inside then
        fs:SetPoint("BOTTOM", btn, "BOTTOM", 0, 4)
    else
        -- Right under the VISIBLE art: the button's transparent bottom rows
        -- come off (re-anchored with Icon Size in SB_ApplyScale).
        fs:SetPoint("TOP", btn, "BOTTOM", 0, (e and e.padB) or 0)
    end
    fs._sbInside = inside or nil
    return fs
end

-- Sizes, pads and free-move heights from the kit and Icon Size (constants,
-- never a geometry read). The build call (force) only stamps; a slider change
-- re-runs the chain (through the width pass when the width follows Icon Size).
local COUNT_REF = { "friendsCount", "guildCount", "durabilityPct" }
local COUNT_OWNER = { friendsCount = "friendsBtn", guildCount = "guildBtn", durabilityPct = "durabilityBtn" }
function ECHAT.SB_ApplyScale(d, s, force)
    -- Memo inputs: the scale and the count font (a profile swap can change
    -- the font alone).
    local font = ECHAT.GetFont()
    local rescaled = d._sbScale ~= s
    if not force and not rescaled and d._sbFont == font then return end
    d._sbScale, d._sbFont = s, font
    for _, ref in pairs(ECHAT.SB_REF) do
        local btn = d[ref]
        local e = btn and btn._sbEntry
        if e then
            btn:SetSize(e.w * s, e.h * s)
            btn._freeMoveH = e.h * s
            btn._sbPadT = (e.padT or 0) * s
            btn._sbPadB = (e.padB or 0) * s
            if btn._sbGW and btn._icon then btn._icon:SetSize(btn._sbGW * s, btn._sbGH * s) end
            local ins = btn._sbInset
            if ins then
                ins:ClearAllPoints()
                ins:SetPoint("TOPLEFT", btn, "TOPLEFT", 5 * s, -6 * s)
                ins:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6 * s, 6 * s)
            end
        end
    end
    local fsz = math.max(7, 10 * s)
    for i = 1, #COUNT_REF do
        local fs = d[COUNT_REF[i]]
        if fs then
            if EUI.PrimeFontShadow then EUI.PrimeFontShadow(fs, true) end
            fs:SetFont(font, fsz, "")
            fs._freeMoveH = fsz
            local owner = d[COUNT_OWNER[COUNT_REF[i]]]
            if owner then
                fs:ClearAllPoints()
                if fs._sbInside then
                    fs:SetPoint("BOTTOM", owner, "BOTTOM", 0, 4 * s)
                else
                    fs:SetPoint("TOP", owner, "BOTTOM", 0, owner._sbPadB or 0)
                end
            end
        end
    end
    local sbtn = d.scrollBtn
    local se = sbtn and sbtn._sbEntry
    if se then
        sbtn:SetSize(se.w * s, se.h * s)
        sbtn._freeMoveH = se.h * s
    end
    -- A font-only change re-fonts the counts and stops; a new scale re-runs
    -- the chain once (the width pass already reaches ApplySidebarIcons).
    if force or not rescaled then return end
    if ECHAT.DB().sidebarWidth == nil and ECHAT.ApplySidebarWidth then
        ECHAT.ApplySidebarWidth()
    elseif ECHAT.ApplySidebarIcons then
        ECHAT.ApplySidebarIcons()
    end
end

-- Durability doll tint from the worst equipment alert (0 fine, 1 damaged,
-- 2 broken); paints on change only.
function ECHAT.SB_DurabilityAlert(btn)
    if not (btn and btn._icon and GetInventoryAlertStatus) then return end
    local worst = 0
    for i = 1, 11 do
        local st = GetInventoryAlertStatus(i)
        if type(st) == "number" and not (issecretvalue and issecretvalue(st)) and st > worst then worst = st end
    end
    if worst > 2 then worst = 2 end
    if btn._sbAlert == worst then return end
    btn._sbAlert = worst
    local e = btn._sbEntry
    local c = ((e and e.alertColors) or ECHAT.SB_ALERT)[worst]
    btn._icon:SetVertexColor(c[1], c[2], c[3], c[4])
end

-- Blizzard Style voice button: the headset while a voice channel is active,
-- the voice-chat icon otherwise (Blizzard's own two events).
function ECHAT.SB_PaintVoice()
    local btn = ECHAT._sbVoiceBtn
    if not (btn and btn._icon and btn._sbGW) then return end
    local on = C_VoiceChat and C_VoiceChat.GetActiveChannelID and C_VoiceChat.GetActiveChannelID() ~= nil or false
    if btn._sbVoiceOn == on then return end
    btn._sbVoiceOn = on
    btn._icon:SetAtlas(on and "chatframe-button-icon-headset" or "chatframe-button-icon-voicechat")
end
function ECHAT.SB_WatchVoice(btn)
    ECHAT._sbVoiceBtn = btn
    if not ECHAT._sbVoiceEvents then
        local f = CreateFrame("Frame")
        f:RegisterEvent("VOICE_CHAT_CHANNEL_ACTIVATED")
        f:RegisterEvent("VOICE_CHAT_CHANNEL_DEACTIVATED")
        f:SetScript("OnEvent", ECHAT.SB_PaintVoice)
        ECHAT._sbVoiceEvents = f
    end
    ECHAT.SB_PaintVoice()
end

-- The scroll button flashes while the selected window is scrolled back:
-- started and stopped on the engine's own scrollbar edges and on a selection
-- change, the animation itself runs in C.
function ECHAT._SB_FlashSyncImpl()
    local cf1 = _G.ChatFrame1
    local d = cf1 and CFD(cf1)
    local btn = d and d.scrollBtn
    local fl, ag = btn and btn._sbFlash, btn and btn._sbFlashAG
    if not (fl and ag) then return end
    local sel = (GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)) or cf1
    local on = (ECHAT.EngineIsScrolled and ECHAT.EngineIsScrolled(sel)) and true or false
    if btn._sbFlashing == on then return end
    btn._sbFlashing = on
    if on then fl:Show(); ag:Play() else ag:Stop(); fl:SetAlpha(0); fl:Hide() end
end
