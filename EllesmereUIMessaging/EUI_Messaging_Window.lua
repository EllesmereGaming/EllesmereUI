if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  The whisper windows, in two layouts (setting: window.layout):
--
--    "list"     one window: the conversations listed down the left (the
--               EllesmereUI bags / history sidebar), the selected one on the
--               right
--    "windows"  a window per person, each titled with the person's name
--
--  Both are built from the same parts:
--    host     a window: backdrop, border, the Damage Meters-style title bar
--             (title + history / settings / close glyphs), the size grip
--    panel    one conversation: the friends-list style header (name,
--             character and level, status orb; zone below), the messages
--             with the chat's slim scroll thumb, the divider and the input
--             (Enter sends, Tab cycles conversations, Up/Down recall sent
--             messages, the character count while long)
--
--  Every color, size and font comes from the settings (Options.lua).
-------------------------------------------------------------------------------
local _, addonNS = ...
local ns = addonNS.Whispers

-- The title bar is the EllesmereUI Damage Meters header: 22px tall, its 22px
-- glyphs packed 20px apart from the right edge (the meter's -2 gap)
local TITLE_H = 22
local GLYPH = 22
local GLYPH_STEP = 20

-- WoW Forever (ns.Forever: the chat's Forever look): the Damage Meters'
-- Forever header (ns.FV_HDR, in the core). The band is taller than the
-- stock bar: its body holds the title and glyphs, the rod runs below.
local FV_HDR = ns.FV_HDR
local HasAtlas = ns.FvAtlas
local function FvHeader() return ns.Forever() and HasAtlas(FV_HDR.atlas) end
local function FvPlates() return ns.Forever() and HasAtlas(FV_HDR.plate) and HasAtlas(FV_HDR.plateHover) end
-- Classic WoW UI (ns.ClassicStyle: the chat's): the Damage Meters' Classic
-- window (ns.CLASSIC, in the core). Its header band sits inside the border's
-- bevel, so the bar starts below it and runs a little taller; the vanilla
-- button art is square, a touch smaller than a glyph, with a gap between.
local CLASSIC_TITLE_H, CLASSIC_BTN, CLASSIC_STEP = 28, 20, 23
local Classic = ns.ClassicStyle
-- The title bar's height (where the content starts), where its body starts
-- and how tall it is (where the title and glyphs centre), the glyph spacing
-- and the gap at the right edge
local function TitleH()
    if FvHeader() then return FV_HDR.height end
    if Classic() then return CLASSIC_TITLE_H end
    return TITLE_H
end
local function TitleTop() return Classic() and ns.CLASSIC.body or 0 end
local function TitleBodyH()
    if FvHeader() then return FV_HDR.height - FV_HDR.rail end
    if Classic() then return CLASSIC_TITLE_H - ns.CLASSIC.body end
    return TITLE_H
end
local function GlyphStep()
    if FvPlates() then return FV_HDR.step end
    if Classic() then return CLASSIC_STEP end
    return GLYPH_STEP
end
local function GlyphPad()
    if FvPlates() then return FV_HDR.pad end
    if Classic() then return ns.CLASSIC.inset end
    return 0
end
local PAD = 8
local ROW_H = 26
local ICON_ALPHA, ICON_HOVER_ALPHA = 0.4, 0.9
local GRIP_ALPHA, GRIP_HOVER_ALPHA = 0.4, 0.75   -- the EllesmereUI chat's grip
local THUMB_COLOR = { 1, 1, 1, 0.27 }

local function S() return ns.settings.window end
local function ListMode() return S().layout ~= "windows" end

local function OnePixel(region)
    local _, h = GetPhysicalScreenSize()
    local scale = region:GetEffectiveScale()
    if not h or h <= 0 or not scale or scale <= 0 then return 1 end
    return 768 / h / scale
end

local function Unpack(c, a)
    return c.r or 1, c.g or 1, c.b or 1, (a ~= nil and a) or c.a or 1
end

-- A color setting that may follow the accent instead
local function ColorOrAccent(useAccent, c)
    if useAccent then
        local r, g, b = ns.Accent()
        return r, g, b, c.a or 1
    end
    return Unpack(c)
end

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-------------------------------------------------------------------------------
--  Fonts (the EllesmereUI chat's: its global "chat" font, or a picked one)
-------------------------------------------------------------------------------
local function FontPath()
    local key = S().font
    local EUI = EllesmereUI
    if key and key ~= "__global" and EUI and EUI.ResolveFontName then
        local path = EUI.ResolveFontName(key)
        if path then return path end
    end
    return ns.Font()
end

local function FontFlags()
    local mode = S().outline
    if mode == "outline" then return "OUTLINE" end
    if mode == "thick" then return "THICKOUTLINE" end
    if mode == "none" then return "" end
    local EUI = EllesmereUI
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("chat")) or ""
end

local function SetFont(fs, size)
    if fs and fs.SetFont then fs:SetFont(FontPath(), size, FontFlags()) end
end

-- The title: the Damage Meters' header font (its module font and outline)
local function SetTitleFont(fs, size)
    if EllesmereUI.ApplyModuleFontFamily then
        EllesmereUI.ApplyModuleFontFamily(fs, nil, size, "damageMeters")
    else
        SetFont(fs, size)
    end
end

-------------------------------------------------------------------------------
--  Messages
-------------------------------------------------------------------------------
local CHAT_TYPES = {
    char = { [ns.IN] = "WHISPER", [ns.OUT] = "WHISPER_INFORM" },
    bn = { [ns.IN] = "BN_WHISPER", [ns.OUT] = "BN_WHISPER_INFORM" },
}

local function LineColor(convo, dir)
    if dir == ns.SYSTEM then return 1, 0.82, 0 end
    local s = S()
    if s.chatColors then
        local info = ChatTypeInfo and ChatTypeInfo[CHAT_TYPES[convo.kind][dir]]
        if info then return info.r, info.g, info.b end
    end
    return Unpack(dir == ns.IN and s.inColor or s.outColor)
end

local function NameText(convo, dir)
    if dir == ns.OUT then
        local _, classFile = UnitClass("player")
        local r, g, b = ns.ClassColor(classFile)
        local me = UnitName("player")
        return r and (Hex(r, g, b) .. me .. "|r") or me
    end
    local name = convo.display or "?"
    local r, g, b = ns.ClassColor(convo.class)
    local text = r and (Hex(r, g, b) .. name .. "|r") or name
    if convo.kind == "char" and convo.name then
        return "|Hplayer:" .. convo.name .. "|h" .. text .. "|h"
    end
    return text
end

local function Format(convo, line)
    local s = S()
    local stamp = ""
    if s.timestamps then
        stamp = "|cff808080" .. date(s.timestampFormat or "%H:%M ", line.t) .. "|r"
    end
    if line.d == ns.SYSTEM then return stamp .. line.text end
    return stamp .. NameText(convo, line.d) .. ": " .. line.text
end

-------------------------------------------------------------------------------
--  Header: who you are talking to, as the EllesmereUI friends list shows it
--
--    rony anzaoui (Noob Ra Lvl 16) [orb]     Battle.net name in Battle.net
--    Stormwind City                          blue, the character class
--                                            colored, the level dim; the
--  zone (or race and class, the presence text in other games, Offline) below.
--  The orb is the friends list's: green online, yellow AFK, red DND, grey
--  offline; character whispers show it while the person is on the friends
--  list. AFK / DND can be secret values, so every read of them is gated.
-------------------------------------------------------------------------------
local DIM = "|cff888888"
local BNET_BLUE = { r = 0.510, g = 0.773, b = 1.0 }

local function Clean(v)
    if v == nil or (ns.IsSecret(v)) then return nil end
    return v
end

local function ClassText(name, classFile)
    local r, g, b = ns.ClassColor(classFile)
    return r and (Hex(r, g, b) .. name .. "|r") or name
end

-- The character in brackets, friends-list style: "(Name Lvl 16)"
local function CharacterPart(name, classFile, level)
    local text = DIM .. "(|r" .. ClassText(name, classFile)
    if level and level > 0 then text = text .. " " .. DIM .. (LEVEL_ABBR or "Lvl") .. " " .. level .. "|r" end
    return text .. DIM .. ")|r"
end

-- Returns the header's name line, info line and status ("online" / "afk" /
-- "dnd" / "offline", or nil for no orb)
local function HeaderFor(convo)
    if convo.gm then
        return "|cff00ccff" .. (convo.display or "?") .. "|r", GM_CHAT or "Game Master", nil
    end

    if convo.kind == "bn" then
        local info = ns.BNInfo(convo.bnID)
        local blue = (FRIENDS_BNET_NAME_COLOR and FRIENDS_BNET_NAME_COLOR.r) and FRIENDS_BNET_NAME_COLOR or BNET_BLUE
        local nameLine = Hex(blue.r, blue.g, blue.b) .. (convo.display or "?") .. "|r"
        if not info then return nameLine, "Battle.net", nil end
        local game = info.gameAccountInfo
        if not (game and game.isOnline) then
            return nameLine, FRIENDS_LIST_OFFLINE or "Offline", "offline"
        end
        local status = "online"
        if Clean(info.isDND) or Clean(game.isGameBusy) then status = "dnd"
        elseif Clean(info.isAFK) or Clean(game.isGameAFK) then status = "afk" end
        local infoLine = game.richPresence
        if game.characterName and game.characterName ~= "" then
            nameLine = nameLine .. " " .. CharacterPart(game.characterName, ns.BNClassFile(info), game.characterLevel)
            infoLine = (game.areaName and game.areaName ~= "") and game.areaName or infoLine
        end
        return nameLine, infoLine or "", status
    end

    -- a character: the friends list knows level, zone and status of friends
    local name = convo.display or "?"
    local friend = C_FriendList and C_FriendList.GetFriendInfo and C_FriendList.GetFriendInfo(name)
    local level, infoLine, status
    if friend then
        if friend.connected then
            level = friend.level
            infoLine = friend.area
            status = (Clean(friend.dnd) and "dnd") or (Clean(friend.afk) and "afk") or "online"
        else
            status = "offline"
            infoLine = FRIENDS_LIST_OFFLINE or "Offline"
        end
        convo.class = convo.class or ns.ClassFileFromName(friend.className)
    end
    local nameLine = ClassText(name, convo.class)
    if level and level > 0 then nameLine = nameLine .. " " .. DIM .. (LEVEL_ABBR or "Lvl") .. " " .. level .. "|r" end
    if not infoLine or infoLine == "" then
        infoLine = ""
        if convo.guid and GetPlayerInfoByGUID then
            local ok, localizedClass, classFile, localizedRace = pcall(GetPlayerInfoByGUID, convo.guid)
            if ok and localizedClass then
                infoLine = (localizedRace and (localizedRace .. " ") or "") .. ClassText(localizedClass, classFile)
            end
        end
    end
    return nameLine, infoLine, status
end

local ORB_COLORS = {
    online = { 0.2, 1, 0.2, 1 }, afk = { 1, 0.8, 0, 1 }, dnd = { 1, 0.2, 0.2, 1 }, offline = { 0.4, 0.4, 0.4, 0.6 },
}

local function SetOrbArt(tex)
    if EllesmereUI.FriendsKit and EllesmereUI.FriendsKit.StatusOrbArt then
        EllesmereUI.FriendsKit.StatusOrbArt(tex)
    else
        tex:SetAtlas("lootroll-animreveal-a")
        tex:SetTexCoord(0, 1 / 6, 0, 0.5)
    end
end

-------------------------------------------------------------------------------
--  Context menu (a sidebar row, or a window's title)
-------------------------------------------------------------------------------
local function ShowContextMenu(owner, convo)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(convo.display or "")
        if convo.kind == "char" and convo.name then
            root:CreateButton(PARTY_INVITE or "Invite", function()
                C_PartyInfo.InviteUnit(ns.ShortName(convo.name))
            end)
            root:CreateButton(ADD_FRIEND or "Add Friend", function()
                if C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(ns.ShortName(convo.name)) end
            end)
            root:CreateButton(IGNORE or "Ignore", function()
                if C_FriendList and C_FriendList.AddIgnore then C_FriendList.AddIgnore(ns.ShortName(convo.name)) end
            end)
        end
        root:CreateButton("History", function() if ns.ShowHistory then ns.ShowHistory(convo.key) end end)
        root:CreateButton(CLOSE or "Close", function() ns.CloseConvo(convo) end)
    end)
end

-------------------------------------------------------------------------------
--  Panel: one conversation
-------------------------------------------------------------------------------
local panels = {}
local Panel = {}
Panel.__index = Panel

local function CycleConvo(step)
    local order = ns.order
    if #order < 2 or not ns.active then return end
    for i, convo in ipairs(order) do
        if convo == ns.active then
            ns.Select(order[(i - 1 + step) % #order + 1])
            return
        end
    end
end

local function BuildThumb(parent, smf)
    local track = CreateFrame("Frame", nil, parent)
    track:SetPoint("TOPRIGHT", smf, "TOPRIGHT", 8, 0)
    track:SetPoint("BOTTOMRIGHT", smf, "BOTTOMRIGHT", 8, 0)
    track:SetWidth(8)
    track:EnableMouse(true)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(unpack(ns.Forever() and ns.FV.thumb or THUMB_COLOR))
    thumb:SetWidth(4)

    -- As the EllesmereUI chat: the thumb shows only while scrolled back (or
    -- dragged), updated by the frame's scroll and refresh callbacks. The
    -- scroll range counts lines, not overflow.
    local dragging = false
    local function Update()
        local maxRange = smf:GetMaxScrollRange() or 0
        local offset = smf:GetScrollOffset() or 0
        if maxRange <= 0 or (offset <= 0 and not dragging) then thumb:Hide() return end
        local trackH = track:GetHeight() or 0
        local visible = smf:GetNumVisibleLines() or 1
        local thumbH = math.max(16, trackH * visible / (maxRange + visible))
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, (trackH - thumbH) * offset / maxRange)
        thumb:Show()
    end
    smf:SetOnScrollChangedCallback(Update)
    smf:AddOnDisplayRefreshedCallback(Update)
    -- (OnUpdate only while the thumb is dragged)
    local function Drag()
        local maxRange = smf:GetMaxScrollRange() or 0
        local bottom, trackH = track:GetBottom(), track:GetHeight()
        if maxRange > 0 and bottom and trackH and trackH > 0 then
            local _, cy = GetCursorPosition()
            local y = cy / track:GetEffectiveScale() - bottom
            smf:SetScrollOffset(math.floor(math.min(1, math.max(0, y / trackH)) * maxRange + 0.5))
        end
        Update()
    end
    track:SetScript("OnMouseDown", function()
        dragging = true
        track:SetScript("OnUpdate", Drag)
    end)
    track:SetScript("OnMouseUp", function()
        dragging = false
        track:SetScript("OnUpdate", nil)
        Update()
    end)
end

-- A panel fills `area` (a frame under the host's title bar)
local function CreatePanel(area)
    local p = setmetatable({ area = area }, Panel)

    -- The header band: opaque, with a hairline under it, as the EllesmereUI
    -- chat's combat log filter row (its height follows the font size)
    p.band = area:CreateTexture(nil, "BACKGROUND", nil, 1)
    p.band:SetPoint("TOPLEFT", area, "TOPLEFT")
    p.band:SetPoint("TOPRIGHT", area, "TOPRIGHT")
    p.bandLine = area:CreateTexture(nil, "ARTWORK", nil, 1)
    p.bandLine:SetPoint("TOPLEFT", p.band, "BOTTOMLEFT")
    p.bandLine:SetPoint("TOPRIGHT", p.band, "BOTTOMRIGHT")

    local details = area:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    details:SetPoint("TOPLEFT", area, "TOPLEFT", PAD + 2, -6)
    details:SetPoint("TOPRIGHT", area, "TOPRIGHT", -(PAD + 16), -6)
    details:SetJustifyH("LEFT")
    details:SetWordWrap(false)
    local info = area:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    info:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -3)
    info:SetPoint("TOPRIGHT", area, "TOPRIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    local orb = area:CreateTexture(nil, "OVERLAY", nil, 3)
    orb:SetSize(18, 18)
    SetOrbArt(orb)
    orb:Hide()
    p.details, p.info, p.orb = details, info, orb

    local input = CreateFrame("EditBox", nil, area)
    input:SetAutoFocus(false)
    input:SetMaxLetters(1023)
    input:SetHeight(22)
    input:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", PAD + 2, 4)
    input:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -72, 4)
    input:SetTextInsets(0, 0, 0, 0)
    input:SetAltArrowKeyMode(false)
    input:SetFontObject("ChatFontNormal")
    p.input = input

    local counter = area:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    counter:SetPoint("RIGHT", area, "BOTTOMRIGHT", -24, 15)
    counter:SetJustifyH("RIGHT")
    p.counter = counter

    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self)
        local convo = p.convo
        local text = self:GetText()
        if convo and ns.Send(convo, text) then
            convo.sent = convo.sent or {}
            table.insert(convo.sent, text)
            if #convo.sent > 20 then table.remove(convo.sent, 1) end
            convo.sentIndex = nil
            self:SetText("")
        end
    end)
    input:SetScript("OnTabPressed", function() if ListMode() then CycleConvo(IsShiftKeyDown() and -1 or 1) end end)
    input:SetScript("OnArrowPressed", function(self, key)
        local convo = p.convo
        local sent = convo and convo.sent
        if not sent or #sent == 0 or (key ~= "UP" and key ~= "DOWN") then return end
        local i = convo.sentIndex or (#sent + 1)
        i = (key == "UP") and math.max(1, i - 1) or math.min(#sent + 1, i + 1)
        convo.sentIndex = i
        self:SetText(sent[i] or "")
    end)
    input:SetScript("OnTextChanged", function(self)
        local n = #(self:GetText() or "")
        counter:SetText(n > 200 and (n .. "/255") or "")
        if n > 255 then counter:SetTextColor(1, 0.6, 0.2) else counter:SetTextColor(0.6, 0.6, 0.6) end
    end)
    input:SetScript("OnEditFocusGained", function() ns.MarkRead(p.convo) end)

    local smf = CreateFrame("ScrollingMessageFrame", nil, area)
    smf:SetPoint("TOPLEFT", area, "TOPLEFT", PAD + 2, -44)
    smf:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 46, 8)
    smf:SetFading(false)
    smf:SetMaxLines(500)
    smf:SetJustifyH("LEFT")
    if smf.SetIndentedWordWrap then smf:SetIndentedWordWrap(true) end
    smf:SetSpacing(2)
    smf:SetFontObject("ChatFontNormal")
    smf:SetHyperlinksEnabled(true)
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        ns.MarkRead(p.convo) -- scrolling through it is reading it
        if delta > 0 then
            if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
        else
            if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
        end
    end)
    smf:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then SetItemRef(link, text, button, self) end
    end)
    smf:SetScript("OnHyperlinkEnter", function(self, link)
        local kind = link and link:match("^(%a+):")
        if kind == "item" or kind == "spell" or kind == "achievement" or kind == "quest" then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            GameTooltip:Show()
        end
    end)
    smf:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    p.smf = smf

    -- the hairline above the input row, across the whole area
    local divider = area:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("BOTTOMLEFT", input, "TOPLEFT", -(PAD + 2), 3)
    divider:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 72, 3)
    p.divider = divider

    BuildThumb(area, smf)
    panels[#panels + 1] = p
    return p
end

function Panel:SetConvo(convo)
    self.convo = convo
    self:Render()
    self:UpdateDetails()
end

function Panel:Render()
    local smf = self.smf
    smf:Clear()
    local convo = self.convo
    if not convo then return end
    for _, line in ipairs(convo.lines) do
        smf:AddMessage(Format(convo, line), LineColor(convo, line.d))
    end
end

function Panel:AddLine(line)
    if self.convo then self.smf:AddMessage(Format(self.convo, line), LineColor(self.convo, line.d)) end
end

function Panel:UpdateDetails()
    local convo = self.convo
    if not convo then
        self.details:SetText("")
        self.info:SetText("")
        self.orb:Hide()
        if self.onHeader then self.onHeader() end
        return
    end
    local nameLine, infoLine, status = HeaderFor(convo)
    -- compact (a window per person): the name line and orb are the window's
    -- title; the band keeps only the location
    if self.compact then
        self.info:SetText(infoLine or "")
        if self.onHeader then self.onHeader() end
        return
    end
    self.details:SetText(nameLine)
    self.info:SetText(infoLine or "")
    local color = status and ORB_COLORS[status]
    if color then
        self.orb:SetVertexColor(unpack(color))
        self.orb:ClearAllPoints()
        -- right after the text, as the friends list seats it
        self.orb:SetPoint("LEFT", self.details, "LEFT", (self.details:GetStringWidth() or 0) - 2, 1)
        self.orb:Show()
    else
        self.orb:Hide()
    end
end

function Panel:ApplySettings()
    local s = S()
    local size = s.fontSize or 12
    SetFont(self.smf, size)
    SetFont(self.input, size)
    -- the name line a step up, the info line a step down (as the friends list)
    SetFont(self.details, size + 2)
    SetFont(self.info, math.max(8, size - 1))
    SetFont(self.counter, math.max(8, size - 2))
    self.details:SetTextColor(1, 1, 1)
    self.info:SetTextColor(0.6, 0.6, 0.6)
    self.input:SetHeight(size + 10)
    self.divider:SetHeight(OnePixel(self.area))
    self.divider:SetColorTexture(ColorOrAccent(s.dividerUseAccent, s.dividerColor))
    -- the header band holds the two header lines (compact: the location
    -- only); the messages start under it
    local bandH
    self.info:ClearAllPoints()
    if self.compact then
        self.details:Hide()
        self.orb:Hide()
        self.info:SetPoint("TOPLEFT", self.area, "TOPLEFT", PAD + 2, -6)
        self.info:SetPoint("TOPRIGHT", self.area, "TOPRIGHT", -PAD, -6)
        bandH = 6 + (size + 1) + 5
    else
        self.details:Show()
        self.info:SetPoint("TOPLEFT", self.details, "BOTTOMLEFT", 0, -3)
        self.info:SetPoint("TOPRIGHT", self.area, "TOPRIGHT", -PAD, 0)
        bandH = 6 + (size + 2) + 3 + (size + 1) + 6
    end
    self.band:SetHeight(bandH)
    self.band:SetColorTexture(Unpack(s.headerBandColor))
    self.bandLine:SetHeight(OnePixel(self.area))
    self.bandLine:SetColorTexture(ColorOrAccent(s.dividerUseAccent, s.dividerColor))
    self.smf:SetPoint("TOPLEFT", self.area, "TOPLEFT", PAD + 2, -(bandH + 6))
    self:Render()
    self:UpdateDetails()
end

-------------------------------------------------------------------------------
--  Host: a window with the title bar, glyphs, border and size grip
-------------------------------------------------------------------------------
local hosts = {}

-- The title bar glyphs are the Damage Meters' own header glyphs when the
-- meter is installed (its X and cog); history is this addon's clock. Each
-- carries the share of the button it is drawn at, so all come out the size
-- of the meter's (whose glyphs fill about half their image).
local DM_MEDIA = "Interface\\AddOns\\EllesmereUIDamageMeters\\Media\\"
local HAS_DM = C_AddOns.DoesAddOnExist("EllesmereUIDamageMeters")
local CLOCK = { ns.MEDIA .. "history.png", 0.68 }
local PIN = { ns.MEDIA .. "location.png", 0.66 }   -- the outline pin fills 81% of its image
local GLYPHS = HAS_DM and {
    close = { DM_MEDIA .. "dm_close.png", 1 },
    settings = { DM_MEDIA .. "dm_settings.png", 1 },
    history = CLOCK,
    pin = PIN,
} or {
    close = { ns.EUI_ICONS .. "eui-close.png", 0.62 },
    settings = { ns.EUI_ICONS .. "settings.png", 0.66 },
    history = CLOCK,
    pin = PIN,
}

-------------------------------------------------------------------------------
--  Map pin: the person's position as a map waypoint. The game reveals other
--  players' map positions only for group members (party or raid), and not
--  inside instances; for everyone else only the zone is known (the header
--  shows it). Battle.net friends are found by the character they play.
-------------------------------------------------------------------------------
local function GroupUnitFor(convo)
    if not convo or not IsInGroup() then return nil end
    local wantName, wantGUID
    if convo.kind == "bn" then
        local info = ns.BNInfo(convo.bnID)
        local game = info and info.gameAccountInfo
        if not (game and game.isOnline and game.characterName) then return nil end
        wantGUID = game.playerGuid
        wantName = game.characterName
    else
        wantGUID = convo.guid
        wantName = convo.display
    end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if wantGUID and guid and not ns.IsSecret(guid) and guid == wantGUID then return unit end
            local name = GetUnitName(unit, true)
            if wantName and name and not ns.IsSecret(name) and (name == wantName or Ambiguate(name, "none") == wantName) then
                return unit
            end
        end
    end
end

local function PinLocation(convo)
    if not convo then return end
    local unit = GroupUnitFor(convo)
    if not unit then
        ns.Print("a map pin works only for group members (their position is hidden otherwise).")
        return
    end
    local mapID = C_Map.GetBestMapForUnit(unit)
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, unit)
    if not position then
        ns.Print("their position isn't available here (instances hide it).")
        return
    end
    local x, y = position:GetXY()
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        ns.Print("a waypoint can't be placed on this map.")
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    local info = C_Map.GetMapInfo(mapID)
    ns.Print(("pinned %s on the map (%s %.1f, %.1f)."):format(convo.display or "?", info and info.name or "", x * 100, y * 100))
end
ns.PinLocation = PinLocation

local function IconColor()
    if ns.Forever() then
        local t = FV_HDR.glyph
        return t[1], t[2], t[3]
    end
    local s = S()
    return ColorOrAccent(s.iconUseAccent, s.iconColor)
end

local function Glyph(host, glyph, offset, tooltip, onClick)
    local texture, scale = glyph[1], glyph[2]
    local plates = FvPlates()
    -- Classic WoW UI: the vanilla art for this button, when it has one
    local classicArt
    if Classic() then
        for key, g in pairs(GLYPHS) do
            if g == glyph then classicArt = ns.CLASSIC.art[key] break end
        end
    end
    local size = (plates and FV_HDR.btn) or (classicArt and CLASSIC_BTN) or GLYPH
    local button = CreateFrame("Button", nil, host)
    button:SetSize(size, size)
    button:SetPoint("RIGHT", host, "TOPRIGHT", -(offset + GlyphPad()), -(TitleTop() + TitleBodyH() / 2))
    button:SetFrameLevel(host:GetFrameLevel() + 5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    local plate
    if classicArt then
        -- vanilla art, untinted, inset by its scale; brightens on hover
        ns.ClassicArt(icon, classicArt)
        local k = classicArt.scale or 1
        icon:SetSize(size * k, size * k)
        icon:SetPoint("CENTER")
        button.classic = true
    elseif plates and glyph == GLYPHS.close and HasAtlas(FV_HDR.close) then
        -- Forever's red close button, as drawn (no plate, no tint)
        icon:SetAtlas(FV_HDR.close)
        icon:SetAllPoints()
        button.stock = true
    else
        if plates then
            plate = button:CreateTexture(nil, "BACKGROUND")
            plate:SetAllPoints()
            plate:SetAtlas(FV_HDR.plate)
            -- the glyph inside the plate's bevel
            size = size * 0.85
        end
        icon:SetSize(size * scale, size * scale)
        icon:SetPoint("CENTER")
        icon:SetTexture(texture)
        icon:SetDesaturated(true)
    end
    -- button.disabled (set by the owner): greyed out, no hover, no click, and
    -- button.disabledNote under the tooltip
    local function Paint(hover)
        if plate then plate:SetAtlas(hover and not button.disabled and FV_HDR.plateHover or FV_HDR.plate) end
        if button.stock then
            icon:SetVertexColor(1, 1, 1, hover and 1 or 0.9)
            return
        end
        if button.classic then
            local C = ns.CLASSIC
            if button.disabled then
                icon:SetDesaturated(true)
                icon:SetVertexColor(0.5, 0.5, 0.5, 0.5)
            else
                local k = hover and C.hover or C.idle
                icon:SetDesaturated(false)
                icon:SetVertexColor(k, k, k, 1)
            end
            return
        end
        if button.disabled then
            icon:SetVertexColor(0.5, 0.5, 0.5, plate and 0.35 or 0.15)
            return
        end
        local r, g, b = IconColor()
        local idle, hot = ICON_ALPHA, ICON_HOVER_ALPHA
        if ns.Forever() then idle, hot = FV_HDR.alpha, FV_HDR.hoverAlpha end
        icon:SetVertexColor(r, g, b, hover and hot or idle)
    end
    button.Paint = Paint
    button:SetScript("OnEnter", function(self)
        Paint(true)
        local text = tooltip
        if self.disabled and self.disabledNote then text = tooltip .. "\n" .. self.disabledNote end
        EllesmereUI.ShowWidgetTooltip(self, text)
    end)
    button:SetScript("OnLeave", function() Paint(false) EllesmereUI.HideWidgetTooltip() end)
    button:SetScript("OnClick", function(self, ...)
        if not self.disabled then onClick(self, ...) end
    end)
    Paint(false)
    host.glyphs[#host.glyphs + 1] = button
    return button
end

-- The EllesmereUI chat's size grip: its resize glyph in the corner, always
-- shown (faint), brighter under the mouse or while sizing; gone while locked
local function BuildGrip(host)
    local grip = CreateFrame("Button", nil, host)
    grip:SetSize(18, 18)
    -- (Classic WoW UI: inside the border's bevel)
    local gi = Classic() and ns.CLASSIC.inset or 1
    grip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -gi, gi)
    grip:SetFrameLevel(host:GetFrameLevel() + 10)
    local icon = grip:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ns.EUI_ICONS .. "resize_element.png")
    grip:SetAlpha(GRIP_ALPHA)
    grip:SetScript("OnEnter", function(self) self:SetAlpha(GRIP_HOVER_ALPHA) end)
    grip:SetScript("OnLeave", function(self) if not host.sizing then self:SetAlpha(GRIP_ALPHA) end end)
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or S().locked or host.noResize then return end
        host.sizing = true
        self:SetAlpha(GRIP_HOVER_ALPHA)
        host:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function(self)
        if not host.sizing then return end
        host:StopMovingOrSizing()
        host.sizing = false
        self:SetAlpha(self:IsMouseOver() and GRIP_HOVER_ALPHA or GRIP_ALPHA)
        host:SavePlace()
    end)
    host.grip = grip
end

-- opts: name, title (text), onClose, onHistory, savePlace(host), place(host)
local function CreateHost(opts)
    local host = CreateFrame("Frame", opts.name, UIParent)
    host.glyphs = {}
    host:SetFrameStrata("MEDIUM")
    host:SetToplevel(true)
    host:SetClampedToScreen(true)
    host:SetMovable(true)
    host:SetResizable(true)
    host:SetResizeBounds(opts.minWidth or 260, 170)
    host:EnableMouse(true)
    host:Hide()
    if opts.name then tinsert(UISpecialFrames, opts.name) end -- Escape closes it

    host.bg = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    host.bg:SetAllPoints()
    host.header = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    -- Forever's header band, reaching under the frame's sides
    if ns.FvHeaderBand(host.header, host, TitleH()) then
        host.fvHeader = true
    else
        host.header:SetPoint("TOPLEFT")
        host.header:SetPoint("TOPRIGHT")
        host.header:SetHeight(TitleH())
    end
    host.border = {}
    for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local edge = host:CreateTexture(nil, "OVERLAY", nil, 7)
        edge:SetPoint(spec[1])
        edge:SetPoint(spec[2])
        host.border[#host.border + 1] = edge
    end
    -- WoW Forever: the chat's bronze frame in place of the 1px border
    host.fv = ns.ForeverFrame(host)

    -- the title bar: the drag handle, its title 6px in
    local bar = CreateFrame("Button", nil, host)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -TitleTop())
    bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -(GlyphStep() * 4 + 6 + GlyphPad()), -TitleTop())
    bar:SetHeight(TitleBodyH())
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("RightButtonUp")
    bar:SetScript("OnDragStart", function()
        if S().locked or host.noMove then return end
        host:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        host:SavePlace()
    end)
    bar:SetScript("OnClick", function(self)
        if opts.onTitleClick then opts.onTitleClick(self) end
    end)
    host.title = bar:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    host.title:SetPoint("LEFT", bar, "LEFT", 6, 0)
    host.title:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    host.title:SetJustifyH("LEFT")
    host.title:SetWordWrap(false)
    host.title:SetText(opts.title or "")

    Glyph(host, GLYPHS.close, 0, CLOSE or "Close", opts.onClose)
    local step = GlyphStep()
    Glyph(host, GLYPHS.settings, step, SETTINGS or "Settings", function() ns.OpenSettings() end)
    Glyph(host, GLYPHS.history, step * 2, "History", opts.onHistory)
    host.getConvo = opts.getConvo
    host.pin = Glyph(host, GLYPHS.pin, step * 3, "Pin their location on the map", function()
        PinLocation(host.getConvo and host.getConvo())
    end)
    BuildGrip(host)

    host.SavePlace = opts.savePlace
    host.unlockKey = opts.unlockKey
    hosts[#hosts + 1] = host
    return host
end

-- The pin glyph is live only while the person is a group member (the only
-- players whose map position the game reveals)
local function UpdatePin(host)
    local pin = host.pin
    if not pin then return end
    local convo = host.getConvo and host.getConvo()
    pin.disabled = (GroupUnitFor(convo) == nil)
    pin.disabledNote = convo and "Only for group members: the game reveals other players' positions only to their group."
        or "No conversation selected."
    pin.Paint(pin:IsMouseOver())
end

local function UpdatePins()
    for _, host in ipairs(hosts) do
        if host:IsShown() then UpdatePin(host) end
    end
end
ns.UpdatePins = UpdatePins

-- Unlock Mode links on a host with an unlock element (the list window):
-- anchored (another element places it) and size matched (another element
-- sets its width or height). Either way the window's own drag / size grip
-- would fight the link, so they are off while it holds.
local UNLOCK_KEY = "EMSG_Window"
local function UnlockHeld(host)
    local key, EUI = host.unlockKey, EllesmereUI
    if not (key and EUI) then return false, false end
    local anchored = (EUI.IsUnlockAnchored and EUI.IsUnlockAnchored(key))
        or (EUI.IsPointAnchored and EUI.IsPointAnchored(key)) or false
    local matched = (EUI.GetWidthMatchTarget and EUI.GetWidthMatchTarget(key))
        or (EUI.GetHeightMatchTarget and EUI.GetHeightMatchTarget(key))
    return anchored and true or false, matched and true or false
end

local function ApplyUnlockHeld(host)
    local s = S()
    local anchored, matched = UnlockHeld(host)
    host.noMove, host.noResize = anchored, matched
    host:SetMovable(not s.locked and not anchored)
    host:SetResizable(not matched)
    if host.grip then host.grip:SetShown(not s.locked and not matched) end
end

local function ApplyHostSettings(host)
    local s = S()
    -- Blizzard Style (the chat's): the Damage Meters' stock look, a
    -- borderless black body (the window colour's opacity kept) under the
    -- stock meter's header bar, a white title
    -- Classic WoW UI: the window colour on the tooltip tile inside the chat
    -- tab's border, a lighter band of it as the header (its opacity the
    -- header colour's)
    local blizz = ns.BlizzStyle()
    local classic = Classic()
    if not (blizz and ns.BlizzBody(host.bg, s.bgColor.a or 1))
        and not (classic and ns.ClassicBody(host.bg, Unpack(s.bgColor))) then
        host.bg:SetColorTexture(Unpack(s.bgColor))
    end
    if not host.fvHeader and not (blizz and ns.BlizzHeader(host.header))
        and not (classic and ns.ClassicHeader(host.header, host, TitleH(),
            s.bgColor.r or 0, s.bgColor.g or 0, s.bgColor.b or 0, s.headerColor.a or 1)) then
        host.header:SetColorTexture(Unpack(s.headerColor))
    end
    blizz = blizz or classic   -- both stock looks: no EUI border, a white title
    local br, bg, bb, ba = ColorOrAccent(s.borderUseAccent, s.borderColor)
    local px = OnePixel(host)
    for i, edge in ipairs(host.border) do
        edge:SetColorTexture(br, bg, bb, ba)
        if i <= 2 then edge:SetHeight(px) else edge:SetWidth(px) end
        edge:SetShown(s.border and not host.fv and not blizz)
    end
    SetTitleFont(host.title, s.titleFontSize or 11)
    if blizz then
        host.title:SetTextColor(1, 1, 1)
    elseif host.fv then
        local g = ns.FV.gold
        host.title:SetTextColor(g[1], g[2], g[3])   -- Forever's gold title
    else
        host.title:SetTextColor(ColorOrAccent(s.titleUseAccent, s.titleColor))
    end
    for _, glyph in ipairs(host.glyphs) do glyph.Paint(false) end
    UpdatePin(host)
    ApplyUnlockHeld(host)
end

-- the area under the title bar a panel fills
local function Area(host, leftAnchor)
    local area = CreateFrame("Frame", nil, host)
    if leftAnchor then
        area:SetPoint("TOPLEFT", leftAnchor, "TOPRIGHT")
    else
        area:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -TitleH())
    end
    area:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
    return area
end

-------------------------------------------------------------------------------
--  Layout "list": one window, the conversations down the left
-------------------------------------------------------------------------------
local main, mainPanel, sidebar, sidebarChild
local rows = {}

local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local function SetConvoIcon(tex, convo)
    local coords = convo.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[convo.class]
    if coords then
        tex:SetTexture(CLASS_SHEET)
        tex:SetTexCoord(unpack(coords))
    elseif convo.kind == "bn" then
        tex:SetTexture("Interface\\FriendsFrame\\Battlenet-Battleneticon")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        tex:SetTexture("Interface\\ChatFrame\\UI-ChatWhisperIcon")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- The open conversations, most recent first
local function SortedOpen()
    local list = {}
    for _, convo in ipairs(ns.order) do list[#list + 1] = convo end
    table.sort(list, function(a, b) return (a.lastTime or 0) > (b.lastTime or 0) end)
    return list
end

local function Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, sidebarChild)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    row.indicator = row:CreateTexture(nil, "OVERLAY")
    row.indicator:SetPoint("TOPLEFT")
    row.indicator:SetPoint("BOTTOMLEFT")
    row.indicator:SetWidth(OnePixel(row) * 2)
    row.bg = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.bg:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.label = row:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    row.count:SetJustifyH("RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0.06) end end)
    row:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0) end end)
    row:SetScript("OnClick", function(self, button)
        local convo = self.convo
        if not convo then return end
        if button == "RightButton" then
            ShowContextMenu(self, convo)
        elseif button == "MiddleButton" then
            ns.CloseConvo(convo)
        else
            ns.Select(convo)
        end
    end)
    rows[i] = row
    return row
end

local function RefreshSidebar()
    if not sidebarChild then return end
    local ar, ag, ab = ns.Accent()
    local size = S().tabFontSize or 11
    local list = SortedOpen()
    for i, convo in ipairs(list) do
        local row = Row(i)
        local isSelected = (convo == ns.active)
        row.convo = convo
        row.selected = isSelected
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", sidebarChild, "RIGHT")
        SetConvoIcon(row.icon, convo)
        row.icon:SetAlpha(isSelected and 1 or 0.75)
        SetFont(row.label, size)
        SetFont(row.count, size)
        row.label:SetText(convo.display or "?")
        local r, g, b = ns.ClassColor(convo.class)
        if convo.kind == "bn" and not r then
            local blue = (FRIENDS_BNET_NAME_COLOR and FRIENDS_BNET_NAME_COLOR.r) and FRIENDS_BNET_NAME_COLOR or BNET_BLUE
            r, g, b = blue.r, blue.g, blue.b
        end
        row.label:SetTextColor(r or 1, g or 1, b or 1, isSelected and 1 or 0.8)
        if convo.unread > 0 then
            row.count:SetText(convo.unread)
            row.count:SetTextColor(ar, ag, ab, 1)
            row.count:Show()
        else
            row.count:Hide()
        end
        if isSelected then
            row.indicator:SetColorTexture(ar, ag, ab, 1)
            row.indicator:Show()
            row.bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            row.indicator:Hide()
            row.bg:SetColorTexture(1, 1, 1, 0)
        end
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide(); rows[i].convo = nil end
    sidebarChild:SetHeight(math.max(1, #list * ROW_H))
end

-- Places the main window at its saved spot
local function PlaceMain()
    if not main then return end
    local s = S()
    main:ClearAllPoints()
    main:SetSize(s.width, s.height)
    if s.point then
        main:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    else
        main:SetPoint("LEFT", UIParent, "LEFT", 60, 60)
    end
end

local function BuildMain()
    if main then return end
    local s = S()
    main = CreateHost({
        name = "EllesmereUIMessagingFrame",
        title = "Message Center",
        unlockKey = UNLOCK_KEY,
        minWidth = 360,
        onClose = function() main:Hide() end,
        onHistory = function() if ns.ShowHistory then ns.ShowHistory(ns.active and ns.active.key) end end,
        getConvo = function() return ns.active end,
        savePlace = function(self)
            local point, _, relativePoint, x, y = self:GetPoint(1)
            local w = S()
            w.point = { point, relativePoint, x, y }
            w.width, w.height = self:GetSize()
        end,
    })
    PlaceMain()

    -- the sidebar (the bags' / history's): the open conversations
    sidebar = CreateFrame("Frame", nil, main)
    sidebar:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -TitleH())
    sidebar:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT")
    sidebar:SetWidth(s.sidebarWidth or 160)
    local sideBg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
    sideBg:SetAllPoints()
    sideBg:SetColorTexture(0, 0, 0, 0.25)
    local sep = sidebar:CreateTexture(nil, "ARTWORK")
    sep:SetWidth(OnePixel(sidebar))
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetColorTexture(0.15, 0.15, 0.15, 1)
    local scroll = CreateFrame("ScrollFrame", nil, sidebar)
    scroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 0)
    sidebarChild = CreateFrame("Frame", nil, scroll)
    sidebarChild:SetSize(s.sidebarWidth or 160, 1)
    scroll:SetScrollChild(sidebarChild)
    scroll:SetScript("OnSizeChanged", function(_, w) sidebarChild:SetWidth(w) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * ROW_H)))
    end)

    mainPanel = CreatePanel(Area(main, sidebar))
    -- (no mark-read on show: a window that pops open by itself leaves its
    -- whispers unread until you look; see ns.ShowWindow)
    main:SetScript("OnShow", function() RefreshSidebar() end)
end

-------------------------------------------------------------------------------
--  Layout "windows": a window per person
-------------------------------------------------------------------------------
local personHosts = {}   -- convo -> host
local freeHosts = {}     -- hidden hosts for reuse
local hostCount = 0

-- The person's title bar: class icon, the name line as the friends list
-- writes it, the status orb, and the unread count
local TITLE_ICON = 14
local function BuildPersonTitle(host)
    local bar = host.title:GetParent()
    host.icon = bar:CreateTexture(nil, "OVERLAY")
    host.icon:SetSize(TITLE_ICON, TITLE_ICON)
    host.icon:SetPoint("LEFT", bar, "LEFT", 6, 0)
    host.title:ClearAllPoints()
    host.title:SetPoint("LEFT", host.icon, "RIGHT", 5, 0)
    host.title:SetPoint("RIGHT", bar, "RIGHT", -34, 0)
    host.orb = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    host.orb:SetSize(16, 16)
    SetOrbArt(host.orb)
    host.orb:Hide()
    host.badge = bar:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    host.badge:SetJustifyH("LEFT")
end

local function UpdatePersonTitle(host)
    local convo = host.convo
    if not convo then
        host.title:SetText("")
        host.badge:SetText("")
        host.icon:Hide()
        host.orb:Hide()
        return
    end
    local nameLine, _, status = HeaderFor(convo)
    SetConvoIcon(host.icon, convo)
    host.icon:Show()
    host.title:SetText(nameLine)
    local textW = host.title:GetStringWidth() or 0
    local boxW = host.title:GetWidth() or 0
    if boxW > 0 and boxW < textW then textW = boxW end
    local after = textW + 2
    local color = status and ORB_COLORS[status]
    if color then
        host.orb:SetVertexColor(unpack(color))
        host.orb:ClearAllPoints()
        host.orb:SetPoint("LEFT", host.title, "LEFT", textW - 2, 0)
        host.orb:Show()
        after = textW + 14
    else
        host.orb:Hide()
    end
    if convo.unread > 0 then
        local r, g, b = ns.Accent()
        SetTitleFont(host.badge, S().titleFontSize or 11)
        host.badge:SetTextColor(r, g, b)
        host.badge:SetText(convo.unread)
        host.badge:ClearAllPoints()
        host.badge:SetPoint("LEFT", host.title, "LEFT", after + 4, 0)
    else
        host.badge:SetText("")
    end
end

local function PlacePerson(host, convo)
    local s = S()
    local size = s.personSize
    host:SetSize(size and size[1] or 340, size and size[2] or 260)
    host:ClearAllPoints()
    local saved = s.personPoints and s.personPoints[convo.key]
    if saved then
        host:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        -- cascade new windows from the list window's spot
        local n = 0
        for _ in pairs(personHosts) do n = n + 1 end
        local base = s.point or { "LEFT", "LEFT", 60, 60 }
        host:SetPoint(base[1], UIParent, base[2], base[3] + 24 * n, base[4] - 24 * n)
    end
end

local function PersonHost(convo)
    local host = personHosts[convo]
    if host then return host end
    host = table.remove(freeHosts)
    if not host then
        hostCount = hostCount + 1
        host = CreateHost({
            name = "EllesmereUIMessagingWindow" .. hostCount,
            onClose = function() if host.convo then ns.CloseConvo(host.convo) end end,
            onHistory = function() if ns.ShowHistory and host.convo then ns.ShowHistory(host.convo.key) end end,
            onTitleClick = function(self) if host.convo then ShowContextMenu(self, host.convo) end end,
            getConvo = function() return host.convo end,
            savePlace = function(self)
                local w = S()
                local point, _, relativePoint, x, y = self:GetPoint(1)
                w.personPoints = w.personPoints or {}
                if self.convo then w.personPoints[self.convo.key] = { point, relativePoint, x, y } end
                w.personSize = { self:GetSize() }
            end,
        })
        BuildPersonTitle(host)
        host.panel = CreatePanel(Area(host))
        host.panel.compact = true
        host.panel.onHeader = function() UpdatePersonTitle(host) end
        host:HookScript("OnSizeChanged", function() UpdatePersonTitle(host) end)
        -- Escape (UISpecialFrames) only hides it; the conversation stays open
        ApplyHostSettings(host)
        host.panel:ApplySettings()
    end
    host.convo = convo
    personHosts[convo] = host
    PlacePerson(host, convo)
    host.panel:SetConvo(convo) -- (sets the title too)
    return host
end

local function ReleasePerson(convo)
    local host = personHosts[convo]
    if not host then return end
    host:Hide()
    host.convo = nil
    host.panel.convo = nil
    personHosts[convo] = nil
    table.insert(freeHosts, host)
end

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local function ApplySettings()
    for _, host in ipairs(hosts) do ApplyHostSettings(host) end
    for _, panel in ipairs(panels) do panel:ApplySettings() end
    if sidebar then
        sidebar:SetWidth(S().sidebarWidth or 160)
        RefreshSidebar()
    end
    for _, host in pairs(personHosts) do UpdatePersonTitle(host) end
end

-- Switching layouts: what was on screen moves over
local lastLayout
local function ApplyLayout()
    local layout = S().layout
    if lastLayout == nil then lastLayout = layout return end
    if layout == lastLayout then return end
    local wasShown = ns.WindowShown()
    local current = ns.active
    lastLayout = layout
    if main then main:Hide() end
    for convo in pairs(personHosts) do ReleasePerson(convo) end
    if wasShown then ns.ShowWindow(current or ns.order[1], false, true) end
end

ns.On("Ready", function() lastLayout = S().layout end)
ns.On("SettingsChanged", function()
    ApplyLayout()
    ApplySettings()
end)

-------------------------------------------------------------------------------
--  Public
-------------------------------------------------------------------------------
function ns.WindowShown()
    if main and main:IsShown() then return true end
    for _, host in pairs(personHosts) do
        if host:IsShown() then return true end
    end
    return false
end

-- The player is in the conversation: its input has the cursor
function ns.IsReading(convo)
    if not convo then return false end
    for _, panel in ipairs(panels) do
        if panel.convo == convo and panel.area:IsVisible() and panel.input:HasFocus() then return true end
    end
    return false
end

function ns.WindowShowsConvo(convo)
    if ListMode() then
        return main ~= nil and main:IsShown() and ns.active == convo
    end
    local host = personHosts[convo]
    return host ~= nil and host:IsShown()
end

-- The open conversation's input, for the integrations (Intercept.lua)
function ns.InputFor(convo)
    if ListMode() then
        return mainPanel and mainPanel.convo == convo and mainPanel.input or nil
    end
    local host = personHosts[convo]
    return host and host.panel.input
end

function ns.IsOwnInput(editBox)
    for _, panel in ipairs(panels) do
        if panel.input == editBox then return true end
    end
    return false
end

function ns.Select(convo)
    if not convo then return end
    if not convo.open then ns.OpenConvo(convo, false) end
    ns.active = convo
    if ListMode() then
        BuildMain()
        ns.MarkRead(convo)
        mainPanel:SetConvo(convo)
        RefreshSidebar()
        UpdatePins()
    else
        ns.ShowWindow(convo)
    end
end

-- Shows the whisper window(s); with a conversation, opens it. In the list
-- layout it is selected unless the player is typing in another one (that one
-- then just gets its unread count). `focus` puts the cursor in its input.
-- `auto`: the window pops open for an incoming whisper; its unread count
-- stays until the player looks (types, selects, opens it themselves).
function ns.ShowWindow(convo, focus, auto)
    if ListMode() then
        BuildMain()
        local wasShown = main:IsShown()
        if convo then
            if not convo.open then ns.OpenConvo(convo, false) end
            if not wasShown or not ns.active or focus or not mainPanel.input:HasFocus() then
                ns.active = convo
                if not auto then ns.MarkRead(convo) end
                mainPanel:SetConvo(convo)
            end
        elseif not ns.active then
            ns.active = SortedOpen()[1]
            mainPanel:SetConvo(ns.active)
        end
        if not wasShown then
            ApplyHostSettings(main)
            mainPanel:ApplySettings()
        end
        main:Show()
        RefreshSidebar()
        UpdatePins()
        if focus then mainPanel.input:SetFocus() end
        return
    end
    -- one window per person
    if not convo then
        for _, c in ipairs(ns.order) do ns.ShowWindow(c, nil, auto) end
        return
    end
    if not convo.open then ns.OpenConvo(convo, false) end
    ns.active = convo
    local host = PersonHost(convo)
    host:Show()
    host:Raise()
    UpdatePin(host)
    if not auto then ns.MarkRead(convo) end
    if focus then host.panel.input:SetFocus() end
end

function ns.ToggleWindow()
    local unread = ns.LatestUnread()
    -- open with something unread (it popped up by itself): go to that first
    if ns.WindowShown() and unread then
        ns.ShowWindow(unread)
    elseif ns.WindowShown() then
        ns.HideWindow()
    else
        ns.ShowWindow(ns.LatestUnread() or ns.active or ns.order[1])
    end
end

function ns.HideWindow()
    if main then main:Hide() end
    for _, host in pairs(personHosts) do host:Hide() end
end

-------------------------------------------------------------------------------
--  Events from the core
-------------------------------------------------------------------------------
-- (fired by the core's popup for an incoming whisper)
ns.On("ShowWindow", function(convo) ns.ShowWindow(convo, false, true) end)

ns.On("ConvoOpened", function(convo, select)
    if select then ns.Select(convo) else RefreshSidebar() end
end)

ns.On("ConvoClosed", function(convo)
    ReleasePerson(convo)
    if mainPanel and mainPanel.convo == convo then
        local nextConvo = SortedOpen()[1]
        ns.active = nextConvo
        mainPanel:SetConvo(nextConvo)
        if not nextConvo and main then main:Hide() end
    end
    RefreshSidebar()
    UpdatePins()
end)

ns.On("LineAdded", function(convo, line)
    if mainPanel and mainPanel.convo == convo then
        mainPanel:AddLine(line)
        if convo.kind == "bn" or not convo.guid then mainPanel:UpdateDetails() end
    end
    local host = personHosts[convo]
    if host then
        host.panel:AddLine(line)
        if convo.kind == "bn" or not convo.guid then host.panel:UpdateDetails() end
    end
    RefreshSidebar()
end)

ns.On("UnreadChanged", function()
    RefreshSidebar()
    for _, host in pairs(personHosts) do UpdatePersonTitle(host) end
end)

ns.On("HistoryChanged", function()
    for _, panel in ipairs(panels) do panel:Render() end
end)

-- Shift-click links (items, spells, achievements) into whichever of our
-- inputs has focus
do
    local function InsertLink(link)
        if type(link) ~= "string" then return end
        for _, panel in ipairs(panels) do
            if panel.input:HasFocus() then panel.input:Insert(link) return end
        end
    end
    hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink)
end

-- The headers follow friend status, zone and level changes (one refresh per
-- burst of friend events, only while something shows)
do
    local watcher = CreateFrame("Frame")
    local pending = false
    -- (group changes also switch the map pin glyph on and off)
    for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
                             "BN_FRIEND_ACCOUNT_OFFLINE", "GROUP_ROSTER_UPDATE" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function()
        if pending or not ns.WindowShown() then return end
        pending = true
        C_Timer.After(0.25, function()
            pending = false
            for _, panel in ipairs(panels) do
                if panel.convo and panel.area:IsVisible() then panel:UpdateDetails() end
            end
            RefreshSidebar()
            UpdatePins()
        end)
    end)
end

-------------------------------------------------------------------------------
--  Unlock Mode (EllesmereUI's edit mode): the whisper window is an element of
--  the Chat group. Moving it there moves the list window; in the per-person
--  layout it is where new windows open (they cascade from its spot). While
--  Unlock Mode is open the list window shows (empty if nothing is open) so
--  it can be placed, and hides again when Unlock Mode closes. Positions use
--  the window's own saved spot (window.point: point, relativePoint, x, y on
--  UIParent), so a drag of the title bar and a mover drag are one setting.
-------------------------------------------------------------------------------
do
    local MIN_W, MIN_H = 360, 170
    local previewShown = false

    local function Snap(v)
        local PP = EllesmereUI and EllesmereUI.PP
        if PP and PP.Snap then return PP.Snap(v) end
        return math.floor(v + 0.5)
    end

    local function RegisterUnlock()
        local EUI = EllesmereUI
        if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end
        EUI:RegisterUnlockElements({
            EUI.MakeUnlockElement({
                key   = UNLOCK_KEY,
                label = "Message Center",
                group = "Chat",
                order = 610,
                getFrame = function()
                    BuildMain()
                    return main
                end,
                getSize = function()
                    if main then return main:GetWidth(), main:GetHeight() end
                    local s = S()
                    return s.width or 520, s.height or 320
                end,
                isHidden = function() return not (ns.settings and ns.settings.enabled) end,
                setWidth = function(_, w)
                    BuildMain()
                    w = Snap(math.max(MIN_W, w or MIN_W))
                    main:SetWidth(w)
                    S().width = w
                end,
                setHeight = function(_, h)
                    BuildMain()
                    h = Snap(math.max(MIN_H, h or MIN_H))
                    main:SetHeight(h)
                    S().height = h
                end,
                savePos = function(_, point, relPoint, x, y)
                    S().point = { point, relPoint or point, x, y }
                    if not EUI._unlockActive then PlaceMain() end
                end,
                loadPos = function()
                    local p = S().point
                    if not p then return nil end
                    return { point = p[1], relPoint = p[2], x = p[3], y = p[4] }
                end,
                clearPos = function() S().point = nil end,
                applyPos = function() PlaceMain() end,
            }),
        }, "EllesmereUIMessaging")

        EUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            if active then
                -- show the list window to place it (the per-person layout
                -- keeps its windows: the mover stands for where they open)
                if ListMode() and not (main and main:IsShown()) then
                    ns.ShowWindow(nil)
                    previewShown = true
                end
            elseif previewShown then
                previewShown = false
                if main then main:Hide() end
            end
            -- anchor / size match links are made and broken in Unlock Mode:
            -- the window's own drag and size grip follow them at both edges
            if main then ApplyUnlockHeld(main) end
        end)
    end

    ns.On("Ready", RegisterUnlock)
end
