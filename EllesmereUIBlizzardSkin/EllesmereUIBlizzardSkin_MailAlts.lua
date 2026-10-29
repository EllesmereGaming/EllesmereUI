if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI and EllesmereUI.IS_FOREVER then return end -- retail only: WoW Forever's mail window is its own build (gamepad navigation, surnames); the Mail card's ALT LIST section is not built there
-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_MailAlts.lua
--  The Mail card's Alt List (opt-in, EllesmereUIDB.mailAltList): beside the
--  Send Mail page, the player's other characters. Those of the same faction on
--  this realm or a connected one take any mail; the rest (another realm, the
--  other faction) take Warbound items only, which reach every character on the
--  account, and show dimmed. A click puts the name in the To: box; a right
--  click offers Ignore This Character and Remove Character.
--  The card also keeps Shown Characters (EllesmereUIDB.mailAltHidden, by
--  player GUID) and, in the toggle's cog, Sort By (mailAltListSort), Max
--  Characters Shown (mailAltListMax) and Minimum Level (mailAltListMinLevel).
--
--  The roster, EllesmereUIDB.mailAltRoster (by player GUID, which a rename
--  keeps), is written at every login and logout even while the list is off
--  (owner decision 2026-10-24): two small writes a session and nothing during
--  play, so every character played since is listed the first time the list is
--  turned on.
--
--  Zero taint: none of our code runs inside Blizzard's mail code.
--   - The panel is a child of SendMailFrame, and no frame of ours under it
--     carries an OnShow, OnHide or OnSizeChanged script, so it shows and hides
--     with the Send Mail page with nothing of ours inside Blizzard's Show or
--     Hide calls.
--   - Its placement follows two hooksecurefunc post-hooks, installed on the
--     first enable and returning at once while off: MailFrameTab_OnClick (the
--     tab switches, Reply's included) and InboxFrame_Update (which every close
--     of the letter window runs, from OpenMailFrame_OnHide).
--   - A click only calls SendMailNameEditBox:SetText. The box's OnTextChanged
--     runs in our execution, and for a name Blizzard's handler writes no Lua
--     state (AutoCompleteEditBox_OnTextChanged acts on typed text or an empty
--     box only; SendMailFrame_CanSend only enables the Send button). The tab is
--     never switched and keyboard focus never moved for the player: both run
--     Blizzard code that writes state its secure send and autocomplete paths
--     read later. For the same reason a click leaves Blizzard's name
--     suggestions open when the player had started typing (Tab or the arrows
--     can then pick one; a typed key or Escape refreshes or closes them).
--
--  The panel's look is latched at login with the mail window's own skin
--  (which applies at login, its style changes needing a reload): EllesmereUI
--  and Modern draw the window theme (eui <-> modern repaints live), Blizz
--  Default draws Blizzard's own DefaultPanelTemplate.
-------------------------------------------------------------------------------
local _, ns = ...
local WSkin = ns.WSkin
if not WSkin then return end

local EUI = EllesmereUI
local Theme = WSkin.Theme
local IsSecret, PlainString = EUI.IsSecret, EUI.PlainString
local wipe, sort = wipe, table.sort

local DEFAULT_MAX, DEFAULT_MIN_LEVEL, DEFAULT_SORT = 10, 1, "recent"
local MAX_ROWS   = 20       -- the Max Characters Shown slider's top
local PANEL_W    = 170
local ROW_H      = 22
local ICON_SIZE  = 16
local LIST_PAD   = 4        -- above the first row and below the last
local EMPTY_PAD  = 10       -- around the empty-list note
local LIMITED_ALPHA = 0.55  -- a row that takes Warbound items only
-- The two looks' geometry: the title band's height, the list's side inset and
-- the gap to the window beside it (Blizzard's metal corners reach past their frame).
local EUI_TOP, EUI_INSET, EUI_GAP       = 25, 1, 4
local BLIZZ_TOP, BLIZZ_INSET, BLIZZ_GAP = 21, 8, 10
local EUI_CLASS_ICONS   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\modern.tga"
local BLIZZ_CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local SHELL_ART         = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"

local ev = CreateFrame("Frame")
local panel, title, emptyNote
local bgArt, bgShade, bgFlat      -- the EllesmereUI look's backdrop layers
local rows = {}
local dirty = true                -- the shown list needs a repaint
local hooked = false
local blizzLook                   -- latched at login: the mail window wears Blizzard's look
local topH, inset, gap
local placedTo, placedSide        -- the panel's current anchor
local connected                   -- this realm's connected realms, read once a session
local shown = {}                  -- player GUIDs in display order (reused)
local mailable = 0                -- characters this page could mail before the card's filters
local sortRoster                  -- the roster the comparators read during one sort
local menuGuid                    -- the row the right-click menu was opened on
local myGuid                      -- this character, read at login (never in its own list)
local paintedGen, paintedFaction  -- the class colour palette and faction the list was painted with
local MENU

-------------------------------------------------------------------------------
--  Settings and the roster
-------------------------------------------------------------------------------
local function Enabled()
    return EllesmereUIDB and EllesmereUIDB.mailAltList == true
end

local function Setting(key, default)
    local v = EllesmereUIDB and EllesmereUIDB[key]
    if v == nil then return default end
    return v
end

local function NumberSetting(key, default)
    local v = tonumber(Setting(key, default))
    return v and math.floor(v) or default
end

local function Roster()
    local db = EllesmereUIDB
    if type(db) ~= "table" then return nil end
    local r = db.mailAltRoster
    if type(r) ~= "table" then
        r = {}
        db.mailAltRoster = r
    end
    return r
end

local function Hidden()
    local h = EllesmereUIDB and EllesmereUIDB.mailAltHidden
    return type(h) == "table" and h or nil
end

-- This character as the roster keeps it. A read that comes back unknown keeps
-- the stored value (a level read before the character is in the world).
local function RecordPlayer()
    local guid = PlainString(UnitGUID("player"))
    if guid then myGuid = guid end
    local name = PlainString((UnitName("player")))
    local realm = PlainString(GetRealmName())
    local _, class = UnitClass("player")
    class = PlainString(class)
    if not (guid and name and realm and class) then return end
    -- The realm as mail addresses it ("Area52"): the normalized name.
    local realmKey = PlainString(GetNormalizedRealmName()) or (realm:gsub("[%s%-]", ""))
    local roster = Roster()
    if not roster then return end
    local e = roster[guid]
    if type(e) ~= "table" then
        e = {}
        roster[guid] = e
    end
    e.name, e.realm, e.realmKey, e.class = name, realm, realmKey, class
    local level = UnitLevel("player")
    if type(level) == "number" and not IsSecret(level) and level > 0 then e.level = level end
    local faction = PlainString((UnitFactionGroup("player")))
    if faction then e.faction = faction end
    e.seen = time()
    dirty = true
end

-- "Level 80 Mage, Horde": the hover line of a list row and of the Shown
-- Characters entries, in Blizzard's own strings.
local function Describe(e)
    local class = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.class]) or e.class or ""
    local text = e.level and UNIT_TYPE_LEVEL_TEMPLATE:format(e.level, class) or class
    local faction = e.faction and _G["FACTION_" .. e.faction:upper()]
    if faction then text = text .. ", " .. faction end
    return text
end

-------------------------------------------------------------------------------
--  Who the list shows: every other character, minus Shown Characters and
--  Minimum Level. Any mail reaches the same faction on this realm or a
--  connected one; Warbound items reach every character on the account.
-------------------------------------------------------------------------------
local function ConnectedRealms()
    if connected then return connected end
    local own = PlainString(GetNormalizedRealmName())
    local set = {}
    if own then set[own] = true end
    local list = C_AutoComplete.GetAutoCompleteRealms()
    if type(list) == "table" then
        for i = 1, #list do
            local r = PlainString(list[i])
            if r then set[r] = true end
        end
    end
    -- Kept once this realm is known: the set never changes in a session.
    if own then connected = set end
    return set
end

local function ByName(a, b)
    local ea, eb = sortRoster[a], sortRoster[b]
    if ea.name ~= eb.name then return strcmputf8i(ea.name, eb.name) < 0 end
    if ea.realmKey ~= eb.realmKey then return ea.realmKey < eb.realmKey end
    return a < b
end
local function ByLevel(a, b)
    local la, lb = sortRoster[a].level or 0, sortRoster[b].level or 0
    if la ~= lb then return la > lb end
    return ByName(a, b)
end
local function ByRecent(a, b)
    local sa, sb = sortRoster[a].seen or 0, sortRoster[b].seen or 0
    if sa ~= sb then return sa > sb end
    return ByName(a, b)
end
local SORTS = { recent = ByRecent, level = ByLevel, name = ByName }

local function Collect()
    wipe(shown)
    mailable = 0
    local roster = Roster()
    local faction = PlainString((UnitFactionGroup("player")))
    paintedFaction = faction
    -- A character without a faction yet has no mail.
    if not roster or not faction or faction == "Neutral" then return end
    local me = myGuid or PlainString(UnitGUID("player"))
    local hidden = Hidden()
    local minLevel = NumberSetting("mailAltListMinLevel", DEFAULT_MIN_LEVEL)
    for guid, e in pairs(roster) do
        if guid ~= me and type(e) == "table" and type(e.name) == "string" and e.realmKey then
            mailable = mailable + 1
            if not (hidden and hidden[guid]) and (e.level or 0) >= minLevel then
                shown[#shown + 1] = guid
            end
        end
    end
    sortRoster = roster
    sort(shown, SORTS[Setting("mailAltListSort", DEFAULT_SORT)] or ByRecent)
    sortRoster = nil
    for i = #shown, Clamp(NumberSetting("mailAltListMax", DEFAULT_MAX), 1, MAX_ROWS) + 1, -1 do shown[i] = nil end
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local Paint, Place

local function RowEnter(self)
    local roster = Roster()
    local e = self._guid and roster and roster[self._guid]
    if type(e) ~= "table" then return end
    local c = EUI.GetClassColor(e.class)
    local head = e.name
    if self._foreign then head = head .. " - " .. (e.realm or e.realmKey) end
    local text = EUI.HexColor(c.r, c.g, c.b) .. head .. "|r\n" .. Describe(e)
    if self._limited then
        text = text .. "\n" .. EllesmereUI.L("Only Warbound items can be mailed to this character.")
    end
    EUI.ShowWidgetTooltip(self, text .. "\n" .. EUI.COLOR_CODES.DIM
        .. EllesmereUI.L("Click to mail, right-click for options.") .. "|r",
        { anchor = "right", justify = "LEFT" })
end

local function RowLeave()
    EUI.HideWidgetTooltip()
end

local function RowClick(self, button)
    if not self._guid then return end
    if button == "RightButton" then
        menuGuid = self._guid
        EUI.ShowContextMenu(self, MENU)
        return
    end
    local box = SendMailNameEditBox
    if box and self._target then box:SetText(self._target) end
end

local function NewRow(i)
    local r = CreateFrame("Button", nil, panel)
    r._mailAltRow = true
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if blizzLook then
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        hl:SetBlendMode("ADD")
        hl:SetVertexColor(0.196, 0.388, 0.8)
    else
        hl:SetColorTexture(1, 1, 1, 0.08)
    end
    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    local lvl = r:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontDisableSmall" or nil)
    local name = r:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontHighlightSmall" or nil)
    if not blizzLook then
        WSkin.Font(lvl, 0.6, 0.6, 0.6, 11)
        WSkin.Font(name, nil, nil, nil, 12)
    end
    lvl:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    lvl:SetJustifyH("RIGHT")
    name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    name:SetPoint("RIGHT", lvl, "LEFT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    r._icon, r._name, r._lvl = icon, name, lvl
    r:SetScript("OnClick", RowClick)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", RowLeave)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -(topH + LIST_PAD + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, -(topH + LIST_PAD + (i - 1) * ROW_H))
    rows[i] = r
    return r
end

local function DressIcon(tex, class)
    local coords
    if blizzLook then
        coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then tex:SetTexture(BLIZZ_CLASS_ICONS) end
    else
        coords = EUI.CLASS_ICON_SPRITE_COORDS[class]
        if coords then tex:SetTexture(EUI_CLASS_ICONS) end
    end
    if coords then
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tex:Show()
    else
        tex:Hide()
    end
end

-- A repaint under a resting cursor: the row now there shows its own tooltip.
local function ReplayHover()
    local foci = GetMouseFoci()
    for i = 1, #foci do
        local f = foci[i]
        if f and f._mailAltRow and f:IsVisible() then
            RowEnter(f)
            return
        end
    end
end

-------------------------------------------------------------------------------
--  The panel
-------------------------------------------------------------------------------
local function PaintBackdrop()
    if blizzLook or not panel then return end
    local modern = WSkin.GetStyle("mail") == "modern"
    bgArt:SetAlpha(modern and 0 or 1)
    bgShade:SetAlpha(modern and 0 or 1)
    if modern then
        bgFlat:SetColorTexture(WSkin.GetModernBG())
    else
        bgFlat:SetColorTexture(0, 0, 0, 0)
    end
end

local function Build()
    if not Theme.fontPath then WSkin.ResolveTheme() end
    -- Named: a frame of ours the window skin's art sweeps leave alone.
    if blizzLook then
        topH, inset, gap = BLIZZ_TOP, BLIZZ_INSET, BLIZZ_GAP
        panel = CreateFrame("Frame", "EllesmereUIMailAltList", SendMailFrame, "DefaultPanelTemplate")
        panel:SetTitleOffsets(6, -6)
        title = panel:GetTitleText()
    else
        topH, inset, gap = EUI_TOP, EUI_INSET, EUI_GAP
        panel = CreateFrame("Frame", "EllesmereUIMailAltList", SendMailFrame)
        -- The mail window's own shell layers: the atlas under a black wash
        -- (EllesmereUI), or the one Modern colour. Built here rather than through
        -- WSkin.Shell, which hooks OnSizeChanged: no script of ours may sit in
        -- SendMailFrame's subtree.
        bgArt = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
        bgArt:SetTexture(SHELL_ART)
        bgArt:SetAllPoints()
        bgShade = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
        bgShade:SetColorTexture(0, 0, 0, 0.62)
        bgShade:SetAllPoints()
        bgFlat = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
        bgFlat:SetAllPoints()
        local band = panel:CreateTexture(nil, "BACKGROUND", nil, -5)
        band:SetColorTexture(0, 0, 0, 0.5)
        band:SetPoint("TOPLEFT")
        band:SetPoint("TOPRIGHT")
        band:SetHeight(topH)
        WSkin.AddBorder(panel)
        title = panel:CreateFontString(nil, "OVERLAY")
        WSkin.Font(title, 1, 1, 1, 12)
        title:SetPoint("CENTER", band, "CENTER", 0, 0)
        PaintBackdrop()
        WSkin.OnStylesChanged(PaintBackdrop)
    end
    title:SetText(EllesmereUI.L("Alts"))
    panel:SetWidth(PANEL_W)
    panel:SetClampedToScreen(true)
    -- It hangs outside the window: a click on its empty parts stays off the world.
    panel:EnableMouse(true)
    emptyNote = panel:CreateFontString(nil, "OVERLAY", blizzLook and "GameFontDisableSmall" or nil)
    if not blizzLook then WSkin.Font(emptyNote, 0.6, 0.6, 0.6, 11) end
    -- Its own width, never one from anchors: the note is measured before the
    -- panel is first placed, and a width taken from unplaced anchors measures
    -- the text as one unwrapped line (a panel too short, the note cut off).
    emptyNote:SetWidth(PANEL_W - EMPTY_PAD * 2)
    emptyNote:SetPoint("TOP", panel, "TOP", 0, -(topH + EMPTY_PAD))
    emptyNote:SetJustifyH("CENTER")
    emptyNote:SetSpacing(2)
end

Paint = function()
    dirty = false
    paintedGen = EUI._dmGen
    Collect()
    local roster = Roster()
    local own = PlainString(GetNormalizedRealmName())
    local realms = ConnectedRealms()
    local n = #shown
    for i = 1, n do
        local guid = shown[i]
        local e = roster[guid]
        local r = rows[i] or NewRow(i)
        local foreign = e.realmKey ~= own
        -- Any mail reaches the same faction on this realm or a connected one;
        -- the rest take Warbound items only and show dimmed.
        local limited = e.faction ~= paintedFaction or not realms[e.realmKey]
        r._guid, r._foreign, r._limited = guid, foreign, limited
        -- Mail addresses another realm's character as "Name-Realm".
        r._target = foreign and (e.name .. "-" .. e.realmKey) or e.name
        DressIcon(r._icon, e.class)
        local c = EUI.GetClassColor(e.class)
        r._name:SetText(foreign and (e.name .. FOREIGN_SERVER_LABEL) or e.name)
        r._name:SetTextColor(c.r, c.g, c.b)
        r._lvl:SetText(e.level or "")
        r:SetAlpha(limited and LIMITED_ALPHA or 1)
        r:Show()
    end
    local owner = EUI._WidgetTooltipOwner()
    for i = n + 1, #rows do
        local r = rows[i]
        if owner == r then EUI.HideWidgetTooltip(true) end
        r:Hide()
        r._guid, r._target, r._limited = nil, nil, nil
    end
    local h
    if n > 0 then
        emptyNote:Hide()
        h = topH + LIST_PAD * 2 + n * ROW_H
    else
        emptyNote:SetText(mailable == 0
            and EllesmereUI.L("Log into your other characters to list them here.")
            or EllesmereUI.L("Your other characters are hidden by Shown Characters or Minimum Level."))
        emptyNote:Show()
        h = topH + EMPTY_PAD * 2 + math.ceil(emptyNote:GetStringHeight())
    end
    if blizzLook then h = h + 2 end   -- the frame's bottom edge
    panel:SetHeight(h)
    if bgArt then WSkin.CoverFit(bgArt, PANEL_W, h) end
    if owner then ReplayHover() end
end

local function ScreenRect(f)
    local s = f:GetEffectiveScale()
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) or IsSecret(l) or IsSecret(r) or IsSecret(t) or IsSecret(b) then return nil end
    return l * s, r * s, t * s, b * s
end

local function Anchor(to, side)
    if placedTo == to and placedSide == side then return end
    placedTo, placedSide = to, side
    panel:ClearAllPoints()
    if side == "left" then
        panel:SetPoint("TOPRIGHT", to, "TOPLEFT", -gap, 0)
    else
        panel:SetPoint("TOPLEFT", to, "TOPRIGHT", gap, 0)
    end
end

-- Beside the mail window; past an open letter it would cover; on the window's
-- left when the screen has no room on its right.
Place = function()
    local mf, letter = MailFrame, OpenMailFrame
    local to, side = mf, "right"
    local ml, mr, mt = ScreenRect(mf)
    if mr then
        local s = panel:GetEffectiveScale()
        local w, h, g = PANEL_W * s, panel:GetHeight() * s, gap * s
        local left = mr + g
        if letter and letter:IsShown() then
            local ll, lr, lt, lb = ScreenRect(letter)
            if ll and left < lr and left + w > ll and mt - h < lt and mt > lb then
                to, left = letter, lr + g
            end
        end
        local screen = UIParent:GetRight() * UIParent:GetEffectiveScale()
        if left + w > screen and ml - g - w >= 0 then
            to, side = mf, "left"
        end
    end
    Anchor(to, side)
end

-- Shown before the paint: a font string measures its height only while visible.
-- Repainted when the list changed, a class colour was edited since (the colour
-- palette's generation) or this character has picked its faction since.
local function ShowPanel()
    if not panel then Build() end
    panel:Show()
    if dirty or paintedGen ~= EUI._dmGen or paintedFaction ~= PlainString((UnitFactionGroup("player"))) then
        Paint()
    end
    Place()
end

-- A change from the right-click menu: the list, and the open options page's
-- Shown Characters summary.
local function Changed()
    dirty = true
    if panel and panel:IsVisible() then
        Paint()
        Place()
    end
    if EUI:IsShown() then EUI:RefreshPage() end
end

local function SetShown(guid, on)
    if not EllesmereUIDB then return end
    local h = EllesmereUIDB.mailAltHidden
    if on then
        if type(h) == "table" then
            h[guid] = nil
            if not next(h) then EllesmereUIDB.mailAltHidden = nil end
        end
    else
        if type(h) ~= "table" then
            h = {}
            EllesmereUIDB.mailAltHidden = h
        end
        h[guid] = true
    end
    dirty = true
end

MENU = {
    { text = "Ignore This Character",
      tooltip = "Hides it until ticked again in Shown Characters.",
      onClick = function()
          if menuGuid then SetShown(menuGuid, false); Changed() end
      end },
    { text = "Remove Character",
      tooltip = "Forgets a deleted or moved character.",
      onClick = function()
          local roster = Roster()
          local guid = menuGuid
          local e = guid and roster and roster[guid]
          if type(e) ~= "table" then return end
          -- Asked first: a misclick would drop a rarely played alt until it next logs in.
          EUI:ShowConfirmPopup({
              title       = "Remove Character",
              message     = EllesmereUI.Lf("Remove %s from the Alt List? It comes back when you next log into it.", e.name),
              confirmText = "Remove",
              cancelText  = "Cancel",
              onConfirm   = function()
                  roster[guid] = nil
                  local h = Hidden()
                  if h and h[guid] then SetShown(guid, true) end
                  Changed()
              end,
          })
      end },
}

-------------------------------------------------------------------------------
--  Hooks: tab switches and the letter window
-------------------------------------------------------------------------------
local function OnTab()
    if not Enabled() or not SendMailFrame:IsVisible() then return end
    ShowPanel()
end

local function OnInboxUpdate()
    if panel and panel:IsVisible() and Enabled() then Place() end
end

local function HookMail()
    if hooked or type(_G.MailFrameTab_OnClick) ~= "function" or type(_G.InboxFrame_Update) ~= "function" then return end
    hooked = true
    hooksecurefunc("MailFrameTab_OnClick", OnTab)
    hooksecurefunc("InboxFrame_Update", OnInboxUpdate)
end

local function Install()
    if hooked then return end
    if C_AddOns.IsAddOnLoaded("Blizzard_MailFrame") then
        HookMail()
    else
        ev:RegisterEvent("ADDON_LOADED")
    end
end

-------------------------------------------------------------------------------
--  The Mail card's options (EUI_BlizzardSkin_Options.lua)
-------------------------------------------------------------------------------
ns.MailAlts = {
    DEFAULT_MAX = DEFAULT_MAX, DEFAULT_MIN_LEVEL = DEFAULT_MIN_LEVEL,
    DEFAULT_SORT = DEFAULT_SORT, MAX_ROWS = MAX_ROWS,
    Describe = Describe,
}

-- A setting changed: the hooks on the first enable, the open Send Mail page
-- repainted, the panel put away when turned off.
function ns.MailAlts.Refresh()
    dirty = true
    if Enabled() then
        Install()
        -- Visible, not shown: SendMailFrame keeps its shown flag while the
        -- mailbox is closed, and the panel paints only where it can measure.
        if hooked and SendMailFrame:IsVisible() then ShowPanel() end
    elseif panel then
        panel:Hide()
        local owner = EUI.ContextMenuOwner()
        if owner and owner._mailAltRow then EUI.CloseContextMenu() end
    end
end

-- Every recorded character, for Shown Characters: by realm (this one first),
-- then by name. A fresh list per call (the menu builds on open).
function ns.MailAlts.Entries()
    local out = {}
    local roster = Roster()
    if not roster then return out end
    for guid, e in pairs(roster) do
        if type(e) == "table" and type(e.name) == "string" then
            out[#out + 1] = { guid = guid, name = e.name, realm = e.realm or e.realmKey or "",
                class = e.class, level = e.level, faction = e.faction }
        end
    end
    local own = GetRealmName()
    sort(out, function(a, b)
        if a.realm ~= b.realm then
            if a.realm == own then return true end
            if b.realm == own then return false end
            return strcmputf8i(a.realm, b.realm) < 0
        end
        if a.name ~= b.name then return strcmputf8i(a.name, b.name) < 0 end
        return a.guid < b.guid
    end)
    return out
end

function ns.MailAlts.IsShown(guid)
    local h = Hidden()
    return not (h and h[guid])
end

function ns.MailAlts.SetShown(guid, on)
    SetShown(guid, on)
    if panel and panel:IsVisible() then
        Paint()
        Place()
    end
end

-------------------------------------------------------------------------------
--  Boot: the roster at login and logout; the hooks once the list is on
-------------------------------------------------------------------------------
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        blizzLook = WSkin.GetStyle("mail") == "off"
        RecordPlayer()
        if Enabled() then Install() end
    elseif event == "PLAYER_LOGOUT" then
        RecordPlayer()
    elseif arg1 == "Blizzard_MailFrame" then
        self:UnregisterEvent("ADDON_LOADED")
        HookMail()
    end
end)
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
