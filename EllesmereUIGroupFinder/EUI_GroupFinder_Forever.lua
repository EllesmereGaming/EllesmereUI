if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Forever.lua: the group browser on WoW Forever. forever has
-- no sign ups, so this is a results list over blizzard's search: groups and
-- solo players, with whisper and invite.
-- blizzard's list stays underneath, faded out, and is never selected or
-- written to. we read its sorted results and draw our own rows.
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
if not EllesmereUI.IS_FOREVER then return end
local EUI = EllesmereUI

local GAP, PAD = 2, 6
local LIST_X, LIST_W, BTN_W = 3, 320, 158.5  -- retail's rows; the bottom buttons a top-row gap (3) apart
local GRAY = { 0.5, 0.5, 0.5 }

local BF, frame, body, thumb, hint
local thumbX = 1  -- the thumb's inset from the list's right edge
local rows, shown = {}, {}
local scrollPx = 0
local active, guard = false, false
local selected  -- ours, blizzard's selection is never touched
local whisperBtn, inviteBtn
local Paint
-- result updates wait for one flush on the next frame
local dirty, flusher = {}, nil

-------------------------------------------------------------------------------
--  display settings, the same profile keys retail's list uses
-------------------------------------------------------------------------------
local function DB() return ns.OwnListDB() end
local styleGen = 0  -- bumped by every display change: rows lay out again
local SIZES = { titleSize = 12, nameSize = 10, lineSize = 10 }
local LOOKS = { iconShape = "circle", roleIcons = "blizzard", borderTexture = "solid", borderSize = 1,
    missingIcons = "blizzard" }
local function Restyled()
    styleGen = styleGen + 1
    if Paint then Paint() end
    if ns.ForeverSquares then ns.ForeverSquares() end
    if ns.ForeverWhoPaint then ns.ForeverWhoPaint() end
end
function ns.OwnListSize(k) return tonumber(DB()[k]) or SIZES[k] end
function ns.SetOwnListSize(k, v) DB()[k] = v; Restyled() end
function ns.OwnListGet(k)
    local v = DB()[k]
    if v == nil then return LOOKS[k] end
    return v
end
function ns.SetOwnListValue(k, v) DB()[k] = v; Restyled() end
-- the user's border colour, else the style's, else the skin's grey
function ns.OwnListBorderColor()
    local bc = ns.OwnListGet("borderColor")
    if type(bc) == "table" then return bc.r or 1, bc.g or 1, bc.b or 1 end
    local btex = ns.OwnListGet("borderTexture") or "solid"
    if btex ~= "solid" and ns.OwnListGet("iconShape") == "square" and EUI.GetBorderStyleSelectDefaults then
        local c = EUI.GetBorderStyleSelectDefaults(btex)
        if c then return c.r, c.g, c.b end
    end
    local m = EUI._ModuleNS and EUI._ModuleNS.EllesmereUIBlizzardSkin
    local T = m and m.WSkin and m.WSkin.Theme
    if T and T.brdR then return T.brdR, T.brdG, T.brdB end
    return 0.25, 0.25, 0.25
end
function ns.OwnListRowHeight() return tonumber(DB().rowHeight) or 50 end
function ns.SetOwnListRowHeight(v) DB().rowHeight = v; Restyled() end
ns.Redecorate = Restyled
-- nil = the default
local function Shown(key)
    local v = ns.Cfg()[key]
    if v == nil then v = ns.DEFAULTS[key] end
    return v and true or false
end
-- 16px at 100%, 1px per 5%
local function IconSize(h)
    local pct = tonumber(ns.Cfg().iconSize) or ns.DEFAULTS.iconSize or 125
    return math.max(8, math.min(h - 4, 16 + math.floor((pct - 100) / 5 + 0.5)))
end

-- lfg reads are secret in chat messaging lockdown: a table we read only when
-- it and everything in it (one level down) can be read, else nil
do
    local Secret = EUI.IsSecret
    local function Readable(t)
        return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t))
    end
    local function Plain(t)
        if not Readable(t) then return nil end
        for _, v in pairs(t) do
            if Secret(v) or (type(v) == "table" and not Readable(v)) then return nil end
        end
        return t
    end
    -- any of blizzard's results we can't read: our list steps aside for blizzard's
    function ns.ForeverAnySecret()
        local res = BF and BF.results
        if type(res) ~= "table" or Secret(res) then return false end
        for _, id in ipairs(res) do
            if Secret(id) then return true end
            local raw = C_LFGList.GetSearchResultInfo(id)
            if raw ~= nil and not Plain(raw) then return true end
        end
        return false
    end
    -- your own listing, when there is one and it can be read
    function ns.ForeverMyEntry()
        local has = C_LFGList.HasActiveEntryInfo()
        if Secret(has) or not has then return nil end
        return Plain(C_LFGList.GetActiveEntryInfo())
    end
    function ns.ForeverMember(id, i)
        return Plain(C_LFGList.GetSearchResultPlayerInfo(id, i))
    end
    function ns.ForeverCounts(id)
        return Plain(C_LFGList.GetSearchResultMemberCounts(id))
    end
    ns.ForeverSecret, ns.ForeverPlain = Secret, Plain
end

local function Info(id)
    if not id or ns.ForeverSecret(id) then return nil end
    return ns.ForeverPlain(C_LFGList.GetSearchResultInfo(id))
end

local function Leader(id)
    if not (id and C_LFGList.GetSearchResultLeaderInfo) or ns.ForeverSecret(id) then return nil end
    return ns.ForeverPlain(C_LFGList.GetSearchResultLeaderInfo(id))
end

local function ClassRGB(file)
    local c = file and RAID_CLASS_COLORS[file]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

-- only solo listings take an invite, and only if you can invite
local function CanInvite(id)
    local info = Info(id)
    if not (info and info.numMembers == 1 and info.leaderName) or info.hasSelf or info.isDelisted then return false end
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- a player link in chat: clicking it is blizzard's own whisper, so nothing of ours touches the chat box
local function Whisper(id)
    local info = Info(id)
    local name = info and info.leaderName
    if not (name and DEFAULT_CHAT_FRAME) then return end
    name = EUI.BuildFullName(name) or name
    local link = "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
    DEFAULT_CHAT_FRAME:AddMessage(EUI.Lf("Click to whisper the group leader: %1$s", link), 1, 0.82, 0)
end

local function Invite(id)
    if not CanInvite(id) then return end
    C_PartyInfo.InviteUnit(Info(id).leaderName)
end

-- the activity line, worded like blizzard's row: your matching activities first
local function ActivityText(info)
    if info.hasSelf then return LFG_SELF_LISTING or "" end
    local acts = info.activityIDs or {}
    local mine = ns.ForeverMyEntry()
    local match = {}
    if mine and mine.activityIDs then
        for _, a in ipairs(mine.activityIDs) do
            if tContains(acts, a) then match[#match + 1] = a end
        end
    end
    local list = #match > 0 and match or acts
    if #list == 1 then
        local ai = C_LFGList.GetActivityInfoTable(list[1])
        return ai and LFGUtil_GetActivityInfoName and LFGUtil_GetActivityInfoName(ai) or (ai and ai.fullName) or ""
    end
    local fmt = #match > 0 and LFGBROWSE_ACTIVITY_MATCHING_COUNT or LFGBROWSE_ACTIVITY_COUNT
    return fmt and string.format(fmt, #list) or ""
end

local function SyncButtons()
    if not whisperBtn then return end
    local info = Info(selected)
    whisperBtn:SetEnabled(info ~= nil and not info.hasSelf and info.leaderName ~= nil)
    inviteBtn:SetEnabled(CanInvite(selected))
end

-------------------------------------------------------------------------------
--  right-click menu and tooltip
-------------------------------------------------------------------------------
local function Menu(anchor, id)
    local info = Info(id)
    if not info then return end
    local leader = info.leaderName
    EUI.ShowContextMenu(anchor, {
        { text = SEND_MESSAGE or "Send Message", noLoc = true,
          isDisabled = function() return not leader or info.hasSelf end,
          onClick = function() Whisper(id) end },
        { text = GROUP_INVITE or "Group Invite", noLoc = true,
          isDisabled = function() return not CanInvite(id) end,
          onClick = function() Invite(id) end },
        "---",
        { text = LFG_LIST_REPORT_GROUP_FOR or "Report Group", noLoc = true,
          onClick = function() LFGBrowseUtil_ReportListing(id, leader) end },
        { text = REPORT_GROUP_FINDER_ADVERTISEMENT or "Report Advertisement", noLoc = true,
          onClick = function() LFGBrowseUtil_ReportAdvertisement(id, leader) end },
    })
end

local ROLE_TEXT = { TANK = TANK, HEALER = HEALER, DAMAGER = DAMAGER }

-- one line per member: name, level and role, zone on the right
local function MemberLine(m)
    local r, g, b = ClassRGB(m.classFilename)
    local left = (m.name or "?") .. "  |cffaaaaaa" .. (LEVEL_ABBR or "Lvl") .. " " .. (m.level or "?")
    local role = ROLE_TEXT[m.assignedRole]
    if role then left = left .. " " .. role end
    GameTooltip:AddDoubleLine(left .. "|r", m.areaName or "", r, g, b, 0.6, 0.6, 0.6)
end

local function ShowTip(row)
    local id = row.resultID
    local info = Info(id)
    if not info then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT", 25, 0)
    GameTooltip:AddLine(ActivityText(info), 1, 0.82, 0, true)
    if info.comment and info.comment ~= "" then
        GameTooltip:AddLine(info.comment, 0.9, 0.9, 0.9, true)
    end
    GameTooltip:AddLine(" ")
    local n = info.numMembers or 0
    if n > 1 then
        local c = ns.ForeverCounts(id)
        if c and LFG_LIST_TOOLTIP_MEMBERS then
            GameTooltip:AddLine(string.format(LFG_LIST_TOOLTIP_MEMBERS, n, c.TANK or 0, c.HEALER or 0, c.DAMAGER or 0), 1, 1, 1)
        end
    end
    if not Shown("classTooltip") then
        if info.isDelisted then
            GameTooltip:AddLine(LFG_LIST_ENTRY_DELISTED or "Delisted", 1, 0.25, 0.25, true)
        end
        GameTooltip:Show()
        return
    end
    -- leader first, then the rest
    local leaderShown
    for i = 1, math.min(n, 40) do
        local m = ns.ForeverMember(id, i)
        if m and m.isLeader then MemberLine(m); leaderShown = true; break end
    end
    for i = 1, math.min(n, 40) do
        local m = ns.ForeverMember(id, i)
        if m and m.name and not (m.isLeader and leaderShown) then MemberLine(m) end
    end
    if info.isDelisted then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(LFG_LIST_ENTRY_DELISTED or "Delisted", 1, 0.25, 0.25, true)
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  a row: leader, level and zone on top, the activity under it, roles right
-------------------------------------------------------------------------------
-- blizzard's class icon (its own atlas table is local to its file)
local function ClassAtlas(file) return file and ("groupfinder-icon-class-" .. file:lower()) end

-- the role icons: blizzard's class circles and role marks, or ours, like
-- retail's rows: class-coloured circles with a border ring
local ICON_GAP = 4
-- a circle filling its square (the portrait mask's circle sits inside it), if
-- this client has it
local MASK = "Interface\\Masks\\CircleMaskScalable"
if not (GetFileIDFromPath and GetFileIDFromPath(MASK)) then MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" end
local ROLE_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps" }
local LARGE_ATLAS = { TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps" }
local ELL_ROLE = { TANK = "Interface\\AddOns\\EllesmereUIRaidFrames\\media\\tank.png",
    HEALER = "Interface\\AddOns\\EllesmereUIRaidFrames\\media\\healer.png",
    DAMAGER = "Interface\\AddOns\\EllesmereUIRaidFrames\\media\\dps.png" }
local ROLE_RGB = { TANK = { 0.16, 0.38, 0.78 }, HEALER = { 0.16, 0.62, 0.24 }, DAMAGER = { 0.72, 0.16, 0.16 } }
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local CROWN = "groupfinder-icon-leader"
local EMPTY_ATLAS = "groupfinder-icon-emptyslot"

local hasAtlas = {}
local function HasAtlas(a)
    if not a then return false end
    local v = hasAtlas[a]
    if v == nil then
        v = C_Texture.GetAtlasInfo(a) ~= nil
        hasAtlas[a] = v
    end
    return v
end

-- a role's mark: blizzard's atlas, ellesmere's art if this client lacks it
local function RoleMark(role)
    if HasAtlas(ROLE_ATLAS[role]) then return ROLE_ATLAS[role] end
    return ELL_ROLE[role]
end

local function MakeRow(i)
    local r = CreateFrame("Button", nil, body)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetAllPoints()
    r.sel:Hide()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.class = r:CreateTexture(nil, "ARTWORK")
    r.class:SetSize(18, 18)
    r.class:SetPoint("LEFT", r, "LEFT", PAD, 0)
    -- right side: up to five circles, placed in Fill
    r.slots = {}
    for k = 1, 5 do
        local bg = r:CreateTexture(nil, "ARTWORK", nil, 1)
        local m = r:CreateMaskTexture()
        m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(bg)
        local icon = r:CreateTexture(nil, "ARTWORK", nil, 3)
        icon:SetPoint("CENTER", bg)
        local count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetPoint("RIGHT", bg, "LEFT", -2, 0)
        local crown = r:CreateTexture(nil, "OVERLAY")
        crown:SetPoint("BOTTOM", bg, "TOP", 0, 1)
        local ring = r:CreateTexture(nil, "ARTWORK", nil, 0)
        local rm = r:CreateMaskTexture()
        rm:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        rm:SetAllPoints(ring)
        ring:AddMaskTexture(rm)
        local edge = CreateFrame("Frame", nil, r)
        edge:SetAllPoints(bg)
        edge:EnableMouse(false)
        bg:Hide(); icon:Hide(); count:Hide(); crown:Hide(); ring:Hide(); edge:Hide()
        r.slots[k] = { bg = bg, mask = m, icon = icon, count = count, crown = crown, ring = ring, edge = edge }
    end
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.level = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.level:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.zone = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.zone:SetJustifyH("LEFT")
    r.zone:SetWordWrap(false)
    r.act = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.act:SetJustifyH("LEFT")
    r.act:SetWordWrap(false)
    r:SetScript("OnClick", function(self, button)
        local id = self.resultID
        if not (id and active) then return end
        if button == "RightButton" then return Menu(self, id) end
        local info = Info(id)
        -- the rows blizzard won't select either: delisted and your own listing
        if not info or info.isDelisted or info.hasSelf then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        selected = (selected ~= id) and id or nil
        Paint()
    end)
    r:SetScript("OnEnter", ShowTip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

local soloPick, members = {}, {}

-- other players' names take the client's font family (cyrillic, korean, chinese)
local famFace, famFlags = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local function NameFont(fs, size)
    local face = famFace[fs]
    if not face then
        local ok, path, _, flags = pcall(fs.GetFont, fs)
        if not (ok and path) then return end
        face = path
        famFace[fs], famFlags[fs] = path, flags or ""
    end
    EUI.SetFontFamily(fs, face, size, famFlags[fs], true)
end
local function TextSize(fs, size)
    local path, _, flags = fs:GetFont()
    if path then fs:SetFont(path, size, flags or "") end
end

-- a row's look: only again for a new height or a display change
local function Layout(r, h)
    if r.layH == h and r.layGen == styleGen then return end
    r.layH, r.layGen = h, styleGen
    NameFont(r.name, ns.OwnListSize("titleSize"))
    TextSize(r.level, ns.OwnListSize("lineSize"))
    TextSize(r.zone, ns.OwnListSize("lineSize"))
    TextSize(r.act, ns.OwnListSize("nameSize"))
    local isz = IconSize(h)
    r.isz = isz
    local ours = ns.OwnListGet("roleIcons") == "ellesmere"
    local round = not ours or ns.OwnListGet("iconShape") ~= "square"
    local px = ours and round and (tonumber(ns.OwnListGet("borderSize")) or 0) or 0
    -- a ring sits inside the square, so ring and all match blizzard's icon
    r.inset = px
    r.bsz = math.max(6, isz - 2 * px)
    r.glyph = math.floor(r.bsz * 0.7 + 0.5)
    r.class:SetSize(isz, isz)
    -- only our circles are masked: blizzard's class circles keep their gold edge
    local masked = ours and round
    for k = 1, 5 do
        local p = r.slots[k]
        p.bg:SetSize(r.bsz, r.bsz)
        p.crown:SetSize(math.floor(isz * 0.6 + 0.5), math.floor(isz * 0.45 + 0.5))
        if masked and not p.masked then p.bg:AddMaskTexture(p.mask); p.masked = true
        elseif not masked and p.masked then p.bg:RemoveMaskTexture(p.mask); p.masked = nil end
    end
    -- the text stops where the widest circle row (five members or raid counts) starts
    local edge = -(PAD + 5 * (isz + ICON_GAP) + 14)
    local x = PAD + isz + 6
    r.textW = LIST_W - x + edge
    -- name always fits, then the dungeon, then the zone, centred as a block
    local tS, nS, lS = ns.OwnListSize("titleSize"), ns.OwnListSize("nameSize"), ns.OwnListSize("lineSize")
    local room = h - 4
    local two = room >= tS + nS + 6
    local three = two and room >= tS + nS + lS + 10
    local total = tS + 2 + (two and nS + 4 or 0) + (three and lS + 4 or 0)
    local y = math.floor((h - total) / 2)
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", x, -y)
    y = y + tS + 4
    r.act:ClearAllPoints()
    r.act:SetPoint("TOPLEFT", r, "TOPLEFT", x, -y)
    r.act:SetPoint("RIGHT", r, "RIGHT", edge, 0)
    r.act:SetShown(two)
    y = y + nS + 4
    r.zone:ClearAllPoints()
    r.zone:SetPoint("TOPLEFT", r, "TOPLEFT", x, -y)
    r.zone:SetPoint("RIGHT", r, "RIGHT", edge, 0)
    r.zone:SetShown(three)
end

-- the biggest group any of its activities takes; nil if unknown
local function Cap(info)
    local cap
    for _, a in ipairs(info.activityIDs or {}) do
        local ai = C_LFGList.GetActivityInfoTable(a)
        local m = ai and ai.maxNumPlayers
        if type(m) == "number" and m > 0 then cap = math.max(cap or 0, m) end
    end
    return cap
end

-- this paint's look, read once a row
local look = {}
local function ReadLook()
    look.blizz = ns.OwnListGet("roleIcons") ~= "ellesmere"
    look.round = look.blizz or ns.OwnListGet("iconShape") ~= "square"
    look.px = look.blizz and 0 or (tonumber(ns.OwnListGet("borderSize")) or 0)
    look.tex = ns.OwnListGet("borderTexture") or "solid"
    look.r, look.g, look.b = ns.OwnListBorderColor()
    look.key = look.tex .. ":" .. look.px .. ":" .. look.r .. ":" .. look.g .. ":" .. look.b
    look.missing = ns.OwnListGet("missingIcons") or "blizzard"
    local cat = BF and BF.CategoryDropdown
    local catID = cat and cat.GetValue and cat:GetValue()
    if catID ~= (GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2) then look.missing = "none" end
end

-- our circles' border: a ring when round, the border style when square
local function Edge(p)
    if look.px <= 0 then return end
    if look.round then
        p.ring:ClearAllPoints()
        p.ring:SetPoint("TOPLEFT", p.bg, "TOPLEFT", -look.px, look.px)
        p.ring:SetPoint("BOTTOMRIGHT", p.bg, "BOTTOMRIGHT", look.px, -look.px)
        p.ring:SetColorTexture(look.r, look.g, look.b, 1)
        p.ring:Show()
    else
        if p.edge._key ~= look.key then
            p.edge._key = look.key
            EUI.ApplyBorderStyle(p.edge, look.px, look.r, look.g, look.b, 1, look.tex)
        end
        p.edge:Show()
    end
end

-- one slot, right to left from x; returns the next x. bg is a colour, an
-- atlas or nil (the mark alone). mark is an atlas or a file; big draws it at
-- the slot's size; faint is "grey" (desaturated) or "dim" for open roles
local function Slot(r, k, x, bg, mark, big, faint, num, off, lead)
    local p = r.slots[k]
    p.bg:ClearAllPoints()
    p.bg:SetPoint("RIGHT", r, "RIGHT", x - (r.inset or 0), 0)
    if type(bg) == "table" then
        local m = off and 0.35 or 1
        p.bg:SetDesaturated(false)
        p.bg:SetColorTexture(bg[1] * m, bg[2] * m, bg[3] * m, 1)
        p.bg:Show()
        Edge(p)
    elseif bg then
        p.bg:SetAtlas(bg)
        p.bg:SetDesaturated(off)
        p.bg:Show()
    end
    if mark then
        if mark:find("\\", 1, true) then p.icon:SetTexture(mark) else p.icon:SetAtlas(mark) end
        local size = big and r.isz or r.glyph
        p.icon:SetSize(size, size)
        p.icon:SetDesaturated(off or faint == "grey")
        p.icon:SetAlpha((faint and 0.6) or (off and 0.5) or 1)
        p.icon:Show()
    end
    if lead and HasAtlas(CROWN) then
        p.crown:SetAtlas(CROWN)
        p.crown:SetDesaturated(off)
        p.crown:Show()
    end
    x = x - r.isz - ICON_GAP
    if num then
        p.count:SetText(num)
        p.count:SetTextColor(off and 0.5 or 1, off and 0.5 or 1, off and 0.5 or 1)
        p.count:Show()
        x = x - math.ceil(p.count:GetStringWidth()) - 6
    end
    return x
end

local EMPTY = { 0.18, 0.18, 0.18 }
local RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local function ByRole(a, b) return (RANK[a.assignedRole] or 4) < (RANK[b.assignedRole] or 4) end

-- the class colour a shade darker, so the role mark reads on it
local classFill = {}
local function ClassFill(file)
    local c = classFill[file or ""]
    if c then return c end
    local cc = file and RAID_CLASS_COLORS[file]
    if not cc then return EMPTY end
    c = { cc.r * 0.75, cc.g * 0.75, cc.b * 0.75 }
    classFill[file] = c
    return c
end

-- the roles a five-player group still needs, tank first
local REMAIN = { TANK = "TANK_REMAINING", HEALER = "HEALER_REMAINING", DAMAGER = "DAMAGER_REMAINING" }
local FIVE = { TANK = 1, HEALER = 1, DAMAGER = 3 }
local needs = {}
local function Needs(id, cap)
    wipe(needs)
    if cap ~= 5 or look.missing == "none" then return needs end
    local c = ns.ForeverCounts(id)
    if not c then return needs end
    for _, role in ipairs(ROLE_ORDER) do
        local left = c[REMAIN[role]]
        if type(left) ~= "number" then left = math.max(0, FIVE[role] - (tonumber(c[role]) or 0)) end
        for _ = 1, left do needs[#needs + 1] = role end
    end
    return needs
end

-- an open spot: the missing role's mark, else an empty circle
local function Open(r, k, x, need, off)
    if need and look.missing == "blizzard" and HasAtlas(ROLE_ATLAS[need]) then
        return Slot(r, k, x, nil, ROLE_ATLAS[need], false, "grey", nil, off)
    elseif need and look.missing == "ellesmere" then
        return Slot(r, k, x, nil, ELL_ROLE[need], false, "dim", nil, off)
    elseif look.blizz and HasAtlas(EMPTY_ATLAS) then
        return Slot(r, k, x, EMPTY_ATLAS, nil, false, nil, nil, off)
    end
    return Slot(r, k, x, EMPTY, nil, false, nil, nil, off)
end

-- a role on its own: blizzard's mark, or our role-coloured circle
local function Role(r, k, x, role, num, off, atlas)
    if look.blizz and HasAtlas(atlas) then return Slot(r, k, x, nil, atlas, true, nil, num, off) end
    return Slot(r, k, x, ROLE_RGB[role], RoleMark(role), false, nil, num, off)
end

-- solo: the roles they'll play. up to five: a circle a member, then the open
-- spots. bigger groups: each role's count, as retail's raid rows
local function Roles(r, id, info, leader, off)
    for k = 1, 5 do
        local p = r.slots[k]
        p.bg:Hide(); p.icon:Hide(); p.count:Hide(); p.crown:Hide(); p.ring:Hide(); p.edge:Hide()
    end
    ReadLook()
    local n = info.numMembers or 0
    local x = -PAD
    if n <= 1 then
        local want = leader and leader.lfgRoles
        wipe(soloPick)
        if want then
            if want.dps then soloPick[#soloPick + 1] = "DAMAGER" end
            if want.healer then soloPick[#soloPick + 1] = "HEALER" end
            if want.tank then soloPick[#soloPick + 1] = "TANK" end
        end
        -- one role in a five-player activity: drawn as a group of one, the
        -- open spots after it with the roles a group still needs
        if #soloPick == 1 and (Cap(info) or 5) == 5 then
            local mine = soloPick[1]
            wipe(needs)
            if look.missing ~= "none" then
                for _, role in ipairs(ROLE_ORDER) do
                    for _ = 1, FIVE[role] - (role == mine and 1 or 0) do needs[#needs + 1] = role end
                end
            end
            local k = 1
            for j = 4, 1, -1 do
                x = Open(r, k, x, needs[j], off)
                k = k + 1
            end
            Role(r, k, x, mine, nil, off, LARGE_ATLAS[mine])
            return
        end
        for k, role in ipairs(soloPick) do x = Role(r, k, x, role, nil, off, LARGE_ATLAS[role]) end
        return
    end
    -- no cap on the activity (quests): a party of five, its open spots empty circles
    local cap = Cap(info) or math.max(5, n)
    if cap > 5 or n > 5 then
        local c = ns.ForeverCounts(id) or {}
        for k = 3, 1, -1 do
            local role = ROLE_ORDER[k]
            x = Role(r, 4 - k, x, role, c[role] or 0, off, LARGE_ATLAS[role])
        end
        return
    end
    -- tanks, healers, dps from the left, open spots on the right
    wipe(members)
    for i = 1, n do
        local m = ns.ForeverMember(id, i)
        if m then members[#members + 1] = m end
    end
    table.sort(members, ByRole)
    local open = math.max(cap, #members) - #members
    local need = Needs(id, cap)
    local k = 1
    for j = open, 1, -1 do
        x = Open(r, k, x, need[j], off)
        k = k + 1
    end
    local crown = Shown("leaderCrown")
    for i = #members, 1, -1 do
        local m = members[i]
        local role = m.assignedRole
        local mark = ROLE_ATLAS[role] and RoleMark(role)
        -- blizzard's own rows: a member is their role's gold-ringed icon
        if look.blizz and HasAtlas(LARGE_ATLAS[role]) then
            x = Slot(r, k, x, nil, LARGE_ATLAS[role], true, nil, nil, off, crown and m.isLeader)
        else
            x = Slot(r, k, x, ClassFill(m.classFilename), mark, false, nil, nil, off, crown and m.isLeader)
        end
        k = k + 1
    end
end

local function Fill(r, id)
    r.resultID = id
    local info = Info(id)
    if not info then r:Hide() return end
    local leader = Leader(id)
    local off = info.isDelisted
    r.name:SetText(info.leaderName or "")
    if off then r.name:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
    else r.name:SetTextColor(ClassRGB(leader and leader.classFilename)) end
    local lvl = leader and leader.level
    r.level:SetText(lvl and ((LEVEL_ABBR or "Lvl") .. " " .. lvl) or "")
    r.zone:SetText(leader and leader.areaName or "")
    local lw = (lvl and r.level:GetStringWidth() + 6) or 0
    local room = math.max(20, (r.textW or 150) - lw)
    r.name:SetWidth(math.min(math.ceil(r.name:GetUnboundedStringWidth()) + 1, room))
    local act = ActivityText(info)
    if off then act = act .. "  |cffff2020" .. EUI.L("Delisted") .. "|r" end
    r.act:SetText(act)
    if off then r.act:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
    elseif info.hasSelf then r.act:SetTextColor(0.1, 1, 0.1)
    else r.act:SetTextColor(0.9, 0.9, 0.9) end
    local n = info.numMembers or 0
    local classAtlas = n <= 1 and leader and ClassAtlas(leader.classFilename)
    if not HasAtlas(classAtlas) then classAtlas = "groupfinder-icon-friend" end
    r.class:SetAtlas(classAtlas, false)
    r.class:SetDesaturated(off)
    Roles(r, id, info, leader, off)
    if selected == id then
        local a = EUI.ELLESMERE_GREEN
        r.sel:SetColorTexture(a and a.r or 0.05, a and a.g or 0.82, a and a.b or 0.62, 0.18)
        r.sel:Show()
    else
        r.sel:Hide()
    end
    r:Show()
end

-------------------------------------------------------------------------------
--  dungeon picks: our own filter over blizzard's results, like retail's
--  dungeon squares. blizzard's activity dropdown is never touched
-------------------------------------------------------------------------------
local DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local NONE = {}

-- the activities a category offers at your level (dungeons by default), as
-- blizzard filters them. its own helper caches a cvar read: a first read from
-- us taints its search
local function Available(cat)
    cat = cat or DUNGEONS
    local acts = C_LFGList.GetAvailableActivities(cat) or {}
    if GetCVarBool("disableSuggestedLevelActivityFilter") then return acts end
    local lvl = UnitLevel("player")
    local entry = ns.ForeverMyEntry()
    local keep = {}
    for _, id in ipairs(acts) do
        local ai = C_LFGList.GetActivityInfoTable(id)
        local listed = entry and entry.activityIDs and tContains(entry.activityIDs, id)
        local lo, hi = ai and ai.minLevelSuggestion or 0, ai and ai.maxLevelSuggestion or 0
        if listed or not ((lo > 0 and lo > lvl) or (hi > 0 and hi < lvl)) then keep[#keep + 1] = id end
    end
    return keep
end

local function Category()
    local cat = BF and BF.CategoryDropdown
    return (cat and cat.GetValue and cat:GetValue()) or 0
end

-- picks that still count (nil = none: everything shows)
local live = {}
local function LivePicks()
    if Category() ~= DUNGEONS then return ns.ForeverActPicks and ns.ForeverActPicks() end
    local p = ns.Cfg().foreverDungeons
    if type(p) ~= "table" then return nil end
    wipe(live)
    local any
    for _, id in ipairs(Available()) do
        if p[id] then live[id] = true; any = true end
    end
    return any and live or nil
end

local function Passes(id, want)
    local info = Info(id)
    if not info then return false end
    if info.hasSelf then return true end
    for _, a in ipairs(info.activityIDs or NONE) do
        if want[a] then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  the list
-------------------------------------------------------------------------------
-- blizzard's results in blizzard's order; nothing while a search runs
local function Collect()
    wipe(shown)
    -- no category yet: a hint to pick one instead of everything
    local none = Category() == 0
    if hint then hint:SetShown(none) end
    if BF.NoResultsFound then BF.NoResultsFound:SetAlpha(none and 0 or 1) end
    if none then return end
    local res = BF.results
    if BF.searching or type(res) ~= "table" or ns.ForeverSecret(res) then return end
    local want = LivePicks()
    for i = 1, #res do
        local id = res[i]
        if not want or Passes(id, want) then shown[#shown + 1] = id end
    end
    if selected and not tContains(shown, selected) then selected = nil end
end

function Paint()
    if not (frame and active) then return end
    local height = body:GetHeight() or 0
    local rowH = ns.OwnListRowHeight()
    local per = rowH + GAP
    local maxPx = math.max(0, #shown * per - GAP - height)
    scrollPx = math.max(0, math.min(scrollPx, maxPx))
    local first = math.floor(scrollPx / per)
    local slots = math.ceil(height / per) + 1
    for i = 1, slots do
        local r = rows[i] or MakeRow(i)
        local idx = first + i
        local id = shown[idx]
        local y = (idx - 1) * per - scrollPx
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
        r:SetHeight(rowH)
        if id and y < height then Layout(r, rowH); Fill(r, id) else r.resultID = nil; r:Hide() end
    end
    for i = slots + 1, #rows do rows[i]:Hide() end
    if maxPx > 0 then
        local th = math.max(16, height * height / (maxPx + height))
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -thumbX, -(height - th) * (scrollPx / maxPx))
        thumb:Show()
    else
        thumb:Hide()
    end
    SyncButtons()
end

-- keep blizzard's list and buttons hidden while ours show
local function HoldHidden(f, a)
    if guard or not active or a == 0 then return end
    guard = true
    f:SetAlpha(0)
    guard = false
end

-- the frame after result updates: each changed group repaints its own row
local function Flush()
    flusher:Hide()
    -- a result went secret: blizzard's list until they read again
    if active and ns.ForeverAnySecret() then wipe(dirty); ns.ForeverRefresh() return end
    if active then
        for id in pairs(dirty) do
            for i = 1, #rows do
                local r = rows[i]
                if r.resultID == id and r:IsShown() then Fill(r, id) end
            end
        end
        SyncButtons()
    end
    wipe(dirty)
end

-- our button over one of blizzard's, skinned like the rest
local function Cover(blizz, label, onClick)
    local b = CreateFrame("Button", nil, BF)
    b:SetAllPoints(blizz)
    b:SetFrameLevel(blizz:GetFrameLevel() + 5)
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    b:SetText(label)
    local skin = EUI._ModuleNS and EUI._ModuleNS.EllesmereUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(b)
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        EUI.MakeBorder(b, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    b:SetScript("OnClick", function() onClick(selected) end)
    b:Hide()
    hooksecurefunc(blizz, "SetAlpha", HoldHidden)
    return b
end

-------------------------------------------------------------------------------
--  top and bottom rows laid out like retail's: the two dropdowns and the
--  refresh box on top, back / sign up sized buttons at the bottom, all as
--  wide as retail's rows
-------------------------------------------------------------------------------
local ROW1_H, ROW_GAP, DD_W = 24, 3, 110  -- retail's filters button: height, gap, width
local ACT_W = 140  -- "filter by activity" fits (the who list's filter)
local SLOT_W = 105  -- the browse row's activity slot: directions, or an activity filter
local topY, bottomY  -- blizzard's own offsets, read before the first move

local dressed
local function WSkin()
    local s = EUI._ModuleNS and EUI._ModuleNS.EllesmereUIBlizzardSkin
    return s and s.WSkin
end

-- a skinned box behind the refresh button; its glyph stays on top and it
-- still takes the click
local function RefreshBox(rb)
    local S = WSkin()
    if not (S and S.Button) then return end
    local box = CreateFrame("Button", nil, rb:GetParent())
    box:EnableMouse(false)
    box:SetAllPoints(rb)
    box:SetFrameLevel(math.max(0, rb:GetFrameLevel() - 1))
    box:SetText(" ")
    S.Button(box)
    rb:HookScript("OnEnter", function() box:LockHighlight() end)
    rb:HookScript("OnLeave", function() box:UnlockHighlight() end)
end

-- search again rests 2 seconds after each search (6 after the server refuses
-- one), as retail's does: a dark sweep, a dim glyph, and a cover over the
-- button that only shows the reason
local CD_SEARCH, CD_FAILED = 2, 6
local cdUntil, cdFrame, cdCover = 0, nil, nil
-- the glyph we dim: the skin's own (it hides blizzard's), else blizzard's
local cdGlyph
local function Glyph(rb)
    if cdGlyph ~= nil then return cdGlyph or nil end
    cdGlyph = false
    for _, r in ipairs({ rb:GetRegions() }) do
        if r ~= rb.Icon and r:IsObjectType("Texture") and r:GetAtlas() == "UI-RefreshButton" then cdGlyph = r end
    end
    if not cdGlyph and rb.Icon then cdGlyph = rb.Icon end
    return cdGlyph or nil
end
local function PaintCooldown()
    local rb = _G.LFGBrowseFrameRefreshButton
    local on = GetTime() < cdUntil
    if cdCover then cdCover:SetShown(on) end
    local g = rb and Glyph(rb)
    if g and g:GetAlpha() > 0 then g:SetAlpha(on and 0.3 or 1) end
end
local function StartCooldown(sec)
    local now = GetTime()
    if now + sec <= cdUntil then return end
    cdUntil = now + sec
    if cdFrame then cdFrame:SetCooldown(now, sec) end
    PaintCooldown()
    C_Timer.After(sec, PaintCooldown)
end
local function RefreshCooldown(rb)
    local px = (EUI.PP and EUI.PP.mult) or 1
    cdFrame = CreateFrame("Cooldown", nil, BF, "CooldownFrameTemplate")
    cdFrame:SetPoint("TOPLEFT", rb, "TOPLEFT", px, -px)
    cdFrame:SetPoint("BOTTOMRIGHT", rb, "BOTTOMRIGHT", -px, px)
    cdFrame:SetFrameLevel(rb:GetFrameLevel() + 3)
    if cdFrame.SetDrawEdge then cdFrame:SetDrawEdge(false) end
    if cdFrame.SetHideCountdownNumbers then cdFrame:SetHideCountdownNumbers(true) end
    if cdFrame.SetSwipeColor then cdFrame:SetSwipeColor(0, 0, 0, 0.65) end
    cdCover = CreateFrame("Button", nil, BF)
    cdCover:SetAllPoints(rb)
    cdCover:SetFrameLevel(rb:GetFrameLevel() + 8)
    cdCover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(LFG_LIST_SEARCH_AGAIN or "Search Again", 1, 1, 1)
        GameTooltip:AddLine(EUI.Lf("Limited to every %d seconds to prevent lock-out", CD_SEARCH), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    cdCover:SetScript("OnLeave", GameTooltip_Hide)
    cdCover:Hide()
    if LFGBrowse_DoSearch then
        hooksecurefunc("LFGBrowse_DoSearch", function() if active then StartCooldown(CD_SEARCH) end end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    ev:SetScript("OnEvent", function() if active then StartCooldown(CD_FAILED) end end)
end

-- blizzard's options cog (show all level ranges, and what other addons add to
-- its menu) as a square like refresh, wearing ellesmere's cog: its own button, its own menu
local function DressOptionsCog()
    local opt = BF.OptionsButton
    if not opt then return end
    RefreshBox(opt)
    local ic = opt.Icon
    if ic then
        ic:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\cogs-3.png")
        ic:SetTexCoord(0, 1, 0, 1)
        ic:ClearAllPoints()
        ic:SetPoint("CENTER")
        ic:SetSize(15, 15)
    end
end

-- titles leave room for blizzard's portrait on the left: the same on both sides
local CenterTitle
do
    local titleY = setmetatable({}, { __mode = "k" })  -- title container: the y we last placed it at
    function CenterTitle(fr)
        local tc = fr and fr.TitleContainer
        if not (tc and tc.GetPoint) then return end
        local _, _, _, _, y = tc:GetPoint(1)
        y = y or -1
        if titleY[tc] == y and tc:GetNumPoints() == 2 then return end
        tc:ClearAllPoints()
        tc:SetPoint("TOPLEFT", fr, "TOPLEFT", 24, y)
        tc:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -24, y)
        titleY[tc] = y
    end
end

local function Center()
    local f, sb = _G.LFGParentFrame, BF.ScrollBox
    local fl, sl = f and f:GetLeft(), sb and sb:GetLeft()
    if not (fl and sl) then return end
    local margin = sl + LIST_X - fl
    if margin <= 0 then return end
    local w = margin * 2 + LIST_W
    if math.abs((f:GetWidth() or 0) - w) > 0.5 then f:SetWidth(w) end
    if frame then
        frame:SetWidth(LIST_W + margin)
        thumbX = math.max(1, math.floor(margin / 2 - 1.5 + 0.5))
    end
    for _, fr in ipairs({ BF, _G.LFGListingFrame, _G.LFGWhoListFrame }) do CenterTitle(fr) end
    -- list self's divider (a flat 454px bar) as wide as the window
    local dv = _G.LFGListingFrame and _G.LFGListingFrame.DividerFrame
    if dv then
        dv:SetSize(11, w)
        if dv.Divider then dv.Divider:SetSize(11, w) end
    end
end

local function Rows()
    -- skipped in combat: laid out once it ends, or the row keeps blizzard's places
    if InCombatLockdown() then
        if EUI.CombatQueue then
            EUI.CombatQueue.Defer("GroupFinderForeverRows", function() if active then Rows() end end)
        end
        return
    end
    Center()
    local cat = _G.LFGBrowseFrameCategoryDropdown
    local act = _G.LFGBrowseFrameActivityDropdown
    local rb = _G.LFGBrowseFrameRefreshButton
    local send, invite = BF.SendMessageButton, BF.GroupInviteButton
    local sb = BF.ScrollBox
    local t, b = BF:GetTop(), BF:GetBottom()
    if not (t and b) then return end
    if cat and act and rb then
        topY = topY or (t - cat:GetTop())
        -- retail's row: the category where the search box is, filling the
        -- room left of the activity dropdown (the filters button) and refresh
        rb:ClearAllPoints()
        rb:SetPoint("TOP", BF, "TOP", 0, -topY)
        rb:SetPoint("RIGHT", sb, "LEFT", LIST_X + LIST_W, 0)
        rb:SetSize(ROW1_H, ROW1_H)
        local opt = BF.OptionsButton
        local right = rb
        if opt then
            opt:ClearAllPoints()
            opt:SetPoint("TOPRIGHT", rb, "TOPLEFT", -ROW_GAP, 0)
            opt:SetSize(ROW1_H, ROW1_H)
            right = opt
        end
        -- one dropdown in the activity slot: blizzard's while it holds picks (your
        -- listing sets them), else directions on dungeons, else ours. blizzard's
        -- is never hidden (its show would run its menu from our code): it only
        -- gives up the mouse and its face
        local dung = Category() == DUNGEONS
        local mine, dirs = ns.foreverActs, ns.foreverDirs
        local picks = act.selectedValues
        local theirs = type(picks) == "table" and #picks > 0
        local slot = (theirs and act) or (dung and dirs) or (not dung and (mine or act)) or nil
        for _, dd in ipairs({ act, mine, dirs }) do
            if dd then
                dd:ClearAllPoints()
                dd:SetPoint("TOPRIGHT", right, "TOPLEFT", -ROW_GAP, 0)
                dd:SetSize(SLOT_W, ROW1_H)
            end
        end
        ns.ForeverPresent(act, slot == act)
        if mine then
            mine:SetShown(slot == mine)
            if mine:IsShown() and not mine:IsMenuOpen() then mine:GenerateMenu() end
        end
        if dirs then dirs:SetShown(slot == dirs) end
        -- our settings cog leads the row (placed by Row2)
        cat:ClearAllPoints()
        cat:SetPoint("TOP", BF, "TOP", 0, -topY)
        cat:SetPoint("LEFT", sb, "LEFT", LIST_X + ROW1_H + ROW_GAP, 0)
        local catW = LIST_W - (ROW1_H + ROW_GAP) * (opt and 3 or 2)
        if slot then catW = catW - SLOT_W - ROW_GAP end
        cat:SetSize(math.max(DD_W, catW), ROW1_H)
    end
    if send and invite then
        bottomY = bottomY or (send:GetBottom() - b)
        send:ClearAllPoints()
        send:SetPoint("BOTTOM", BF, "BOTTOM", 0, bottomY)
        send:SetPoint("LEFT", sb, "LEFT", LIST_X, 0)
        send:SetWidth(BTN_W)
        invite:ClearAllPoints()
        invite:SetPoint("BOTTOMLEFT", send, "BOTTOMRIGHT", LIST_W - BTN_W * 2, 0)
        invite:SetWidth(BTN_W)
    end
end

-------------------------------------------------------------------------------
--  our own faces over the two dropdowns, like retail's settings cog. blizzard's
--  button stays on top at alpha 0 and takes every click, so its menu opens as
--  ever; the face only copies its text and state, never writes to it
-------------------------------------------------------------------------------
local faces = {}
ns.foreverAside = {}  -- blizzard dropdown: kept shown but out of the row
function ns.ForeverPresent(dd, on)
    ns.foreverAside[dd] = not on or nil
    dd:EnableMouse(on)
    dd:EnableMouseWheel(on)
    local f = faces[dd]
    if f then f:SetShown(on and dd:IsShown()) end
end

-- the face's text a size under the bottom buttons', as retail's filters button
local dropFont
local function DropFont()
    if dropFont then return dropFont end
    dropFont = CreateFont("EUIGroupFinderForeverDropFont")
    local src = BF.SendMessageButton and BF.SendMessageButton:GetFontString()
    local path, size, flags
    if src then path, size, flags = src:GetFont() end
    if path then dropFont:SetFont(path, math.max(8, size - 1), flags or "")
    else dropFont:CopyFontObject(GameFontHighlightSmall) end
    return dropFont
end

local function PaintFace(dd)
    local f = faces[dd]
    if not f then return end
    local on = dd:IsEnabled()
    local lit = on and (f.hover or (dd.IsMenuOpen and dd:IsMenuOpen()))
    local text = dd.Text and dd.Text:GetText() or ""
    if text == LFGBROWSE_ACTIVITY_HEADER_DEFAULT then text = EUI.L("Activity Filter") end
    f.label:SetText(text)
    -- blizzard keeps the activity dropdown off until a category's picked
    local c = on and 1 or 0.5
    f.label:SetTextColor(c, c, c)
    f.arrow:SetAlpha((not on and 0.4) or (lit and 1) or 0.8)
    if lit then f:LockHighlight() else f:UnlockHighlight() end
    f:SetEnabled(on)
end

-- the skin's arrow (or blizzard's), copied: atlas and turn
local function CopyArrow(dd, t)
    for _, src in ipairs({ dd, _G.LFGBrowseFrameCategoryDropdown }) do
        for _, r in ipairs({ src:GetRegions() }) do
            local a = r:IsObjectType("Texture") and r:GetAtlas()
            if a and a:lower():find("arrow") then
                t:SetAtlas(a)
                t:SetRotation(r:GetRotation() or 0)
                return
            end
        end
    end
    t:Hide()
end

local function Face(dd)
    local f = CreateFrame("Button", nil, dd:GetParent() or BF)
    f:SetAllPoints(dd)
    f:SetFrameLevel(math.max(0, dd:GetFrameLevel() - 1))
    f:EnableMouse(false)  -- blizzard's button over it takes the clicks
    f:SetText(" ")
    local S = WSkin()
    if S and S.Button then
        S.Button(f)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        EUI.MakeBorder(f, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
        local hl = f:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    -- text and arrow on a child, clear of the skin's restrip
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 2)
    f.arrow = top:CreateTexture(nil, "OVERLAY")
    CopyArrow(dd, f.arrow)
    f.arrow:SetDesaturated(true)
    f.arrow:SetVertexColor(1, 1, 1)
    f.arrow:SetSize(11, 8)
    f.arrow:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.label = top:CreateFontString(nil, "OVERLAY")
    f.label:SetFontObject(DropFont())
    f.label:SetJustifyH("LEFT")
    f.label:SetWordWrap(false)
    f.label:SetPoint("LEFT", f, "LEFT", 8, 0)
    f.label:SetPoint("RIGHT", f.arrow, "LEFT", -4, 0)
    faces[dd] = f

    -- blizzard's button stays invisible
    dd:SetAlpha(0)
    hooksecurefunc(dd, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
    local function Paint() PaintFace(dd) end
    f:SetShown(dd:IsShown() and not ns.foreverAside[dd])
    dd:HookScript("OnShow", function() f:SetShown(not ns.foreverAside[dd]); Paint() end)
    dd:HookScript("OnHide", function() f:Hide() end)
    dd:HookScript("OnEnter", function() f.hover = true; Paint() end)
    dd:HookScript("OnLeave", function() f.hover = false; Paint() end)
    dd:HookScript("OnEnable", Paint)
    dd:HookScript("OnDisable", Paint)
    hooksecurefunc(dd, "SetEnabled", Paint)
    if dd.OnMenuOpened then hooksecurefunc(dd, "OnMenuOpened", Paint) end
    -- blizzard clears its open state after this call: look again next frame
    if dd.OnMenuClosed then hooksecurefunc(dd, "OnMenuClosed", function() C_Timer.After(0, Paint) end) end
    if dd.Text then hooksecurefunc(dd.Text, "SetText", Paint) end
    Paint()
end

-- blizzard sizes its dropdowns again when it fills them: ours win
local sizing
local function HoldHeight(dd)
    if sizing or InCombatLockdown() or dd:GetHeight() == ROW1_H then return end
    sizing = true
    dd:SetHeight(ROW1_H)
    sizing = false
end

local function DressRows()
    local dirs = ns.ForeverDirections and ns.ForeverDirections()
    local acts = ns.ForeverActivities and ns.ForeverActivities()
    for _, dd in pairs({ _G.LFGBrowseFrameCategoryDropdown, _G.LFGBrowseFrameActivityDropdown, dirs, acts }) do
        if dd then
            Face(dd)
            hooksecurefunc(dd, "SetHeight", HoldHeight)
            hooksecurefunc(dd, "SetSize", HoldHeight)
        end
    end
    if _G.LFGBrowseFrameRefreshButton then
        RefreshBox(_G.LFGBrowseFrameRefreshButton)
        RefreshCooldown(_G.LFGBrowseFrameRefreshButton)
        DressOptionsCog()
    end
    BF:HookScript("OnSizeChanged", Rows)
    local act = _G.LFGBrowseFrameActivityDropdown
    if act and act.UpdateHeader then
        local function Again()
            C_Timer.After(0, function()
                if active and not (act.IsMenuOpen and act:IsMenuOpen()) then Rows() end
            end)
        end
        hooksecurefunc(act, "UpdateHeader", Again)
        if act.OnMenuClosed then hooksecurefunc(act, "OnMenuClosed", Again) end
    end
end

-- the who list's top bar as the browser's: the search box where the category sits,
-- the filter where the activity filter sits, search where refresh sits. its list
-- drawn like the browser's: blizzard's stays underneath, faded and never written
-- to; our rows read the who results in blizzard's order
do
    local whoDressed, holding
    local WHO_BOTTOM, WHO_GAP = 48, 9  -- blizzard's list bottom; room under the top bar
    local whoF, wf, wbody, wthumb
    local wrows = {}
    local wscroll = 0
    local wguard, won = false, false

    -- the filter keeps the activity filter's size (blizzard fits it to its text)
    local function HoldFilter(fd)
        if holding or InCombatLockdown() then return end
        if math.abs(fd:GetWidth() - ACT_W) < 0.5 and math.abs(fd:GetHeight() - ROW1_H) < 0.5 then return end
        holding = true
        fd:SetSize(ACT_W, ROW1_H)
        holding = false
    end

    local function Me(name)
        return name ~= nil and Ambiguate(name, "none") == UnitName("player")
    end
    local function CanAsk(name)
        if not name or Me(name) or UnitInParty(name) or UnitInRaid(name) then return false end
        return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
    -- a player link in chat: clicking it is blizzard's own whisper
    local function WhoWhisper(name)
        if not (name and DEFAULT_CHAT_FRAME) then return end
        local link = "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
        DEFAULT_CHAT_FRAME:AddMessage(EUI.Lf("Click to whisper %1$s", link), 1, 0.82, 0)
    end
    local function WhoInvite(name)
        if CanAsk(name) then C_PartyInfo.InviteUnit(name) end
    end

    local function WhoTip(row)
        local w = row.info
        if not w then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT", 25, 0)
        GameTooltip:AddLine(w.fullName or "?", ClassRGB(w.filename))
        GameTooltip:AddLine(("%s %s  %s %s"):format(LEVEL_ABBR or "Lvl", w.level or "?", w.raceStr or "", w.classStr or ""), 1, 1, 1)
        if w.fullGuildName and w.fullGuildName ~= "" then GameTooltip:AddLine("<" .. w.fullGuildName .. ">", 0.6, 0.6, 0.6) end
        if w.area and w.area ~= "" then GameTooltip:AddLine(w.area, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end

    local function WhoMenu(anchor, name)
        EUI.ShowContextMenu(anchor, {
            { text = WHISPER or "Whisper", noLoc = true,
              isDisabled = function() return Me(name) end,
              onClick = function() WhoWhisper(name) end },
            { text = INVITE or "Invite", noLoc = true,
              isDisabled = function() return not CanAsk(name) end,
              onClick = function() WhoInvite(name) end },
        })
    end

    -- the row's invite: a skinned square, blizzard's invite glyph in white
    local function InviteButton(r)
        local b = CreateFrame("Button", nil, r)
        b:SetText(" ")
        local S = WSkin()
        if S and S.Button then
            S.Button(b)
        else
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
            EUI.MakeBorder(b, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)
        end
        -- the glyph on a child, clear of the skin's restrip
        local top = CreateFrame("Frame", nil, b)
        top:SetAllPoints()
        top:SetFrameLevel(b:GetFrameLevel() + 2)
        b.glyph = top:CreateTexture(nil, "OVERLAY")
        b.glyph:SetAtlas("friends-icon-friendsInGroup")
        b.glyph:SetDesaturated(true)
        b.glyph:SetPoint("CENTER")
        b:SetScript("OnClick", function(self) WhoInvite(self:GetParent().who) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(INVITE or "Invite", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        return b
    end

    local function WhoRow(i)
        local r = CreateFrame("Button", nil, wbody)
        r:RegisterForClicks("RightButtonUp")
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0.03)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.06)
        r.class = r:CreateTexture(nil, "ARTWORK")
        r.class:SetPoint("LEFT", r, "LEFT", PAD, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.level = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.level:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
        r.act = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.act:SetJustifyH("LEFT")
        r.act:SetWordWrap(false)
        r.zone = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.zone:SetJustifyH("LEFT")
        r.zone:SetWordWrap(false)
        r.invite = InviteButton(r)
        r:SetScript("OnClick", function(self) if self.who then WhoMenu(self, self.who) end end)
        r:SetScript("OnEnter", WhoTip)
        r:SetScript("OnLeave", GameTooltip_Hide)
        wrows[i] = r
        return r
    end

    -- the browser row's layout: name and level, race and class, zone; invite on the right
    local function WhoLayout(r, h)
        if r.layH == h and r.layGen == styleGen then return end
        r.layH, r.layGen = h, styleGen
        local tS, nS, lS = ns.OwnListSize("titleSize"), ns.OwnListSize("nameSize"), ns.OwnListSize("lineSize")
        NameFont(r.name, tS)
        TextSize(r.level, lS)
        TextSize(r.zone, lS)
        TextSize(r.act, nS)
        local isz = IconSize(h)
        r.class:SetSize(isz, isz)
        local bs = math.max(12, math.min(ROW1_H, h - 8))
        r.invite:SetSize(bs, bs)
        r.invite:ClearAllPoints()
        r.invite:SetPoint("RIGHT", r, "RIGHT", -PAD, 0)
        local g = math.floor(bs * 0.66 + 0.5)
        r.invite.glyph:SetSize(g, g)
        local edge = -(PAD + bs + 8)
        local x = PAD + isz + 6
        r.textW = LIST_W - x + edge
        local room = h - 4
        local two = room >= tS + nS + 6
        local three = two and room >= tS + nS + lS + 10
        local total = tS + 2 + (two and nS + 4 or 0) + (three and lS + 4 or 0)
        local y = math.floor((h - total) / 2)
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", x, -y)
        y = y + tS + 4
        r.act:ClearAllPoints()
        r.act:SetPoint("TOPLEFT", r, "TOPLEFT", x, -y)
        r.act:SetPoint("RIGHT", r, "RIGHT", edge, 0)
        r.act:SetShown(two)
        y = y + nS + 4
        r.zone:ClearAllPoints()
        r.zone:SetPoint("TOPLEFT", r, "TOPLEFT", x, -y)
        r.zone:SetPoint("RIGHT", r, "RIGHT", edge, 0)
        r.zone:SetShown(three)
    end

    local function WhoFill(r, w)
        r.info, r.who = w, w.fullName
        r.name:SetText(w.fullName or "")
        r.name:SetTextColor(ClassRGB(w.filename))
        r.level:SetText(w.level and ((LEVEL_ABBR or "Lvl") .. " " .. w.level) or "")
        local lw = w.level and (r.level:GetStringWidth() + 6) or 0
        local room = math.max(20, (r.textW or 150) - lw)
        r.name:SetWidth(math.min(math.ceil(r.name:GetUnboundedStringWidth()) + 1, room))
        local line = strtrim((w.raceStr or "") .. " " .. (w.classStr or ""))
        if w.fullGuildName and w.fullGuildName ~= "" then
            line = line .. "  |cff999999<" .. w.fullGuildName .. ">|r"
        end
        r.act:SetText(line)
        r.act:SetTextColor(0.9, 0.9, 0.9)
        r.zone:SetText(w.area or "")
        local a = ClassAtlas(w.filename)
        if not HasAtlas(a) then a = "groupfinder-icon-friend" end
        r.class:SetAtlas(a, false)
        local can = CanAsk(w.fullName)
        r.invite:SetEnabled(can)
        r.invite.glyph:SetAlpha(can and 0.9 or 0.3)
        r:Show()
    end

    local function WhoPaint()
        if not (wf and won) then return end
        local height = wbody:GetHeight() or 0
        local rowH = ns.OwnListRowHeight()
        local per = rowH + GAP
        local n = C_FriendList.GetNumWhoResults() or 0
        local maxPx = math.max(0, n * per - GAP - height)
        wscroll = math.max(0, math.min(wscroll, maxPx))
        local first = math.floor(wscroll / per)
        local slots = math.ceil(height / per) + 1
        for i = 1, slots do
            local r = wrows[i] or WhoRow(i)
            local idx = first + i
            local y = (idx - 1) * per - wscroll
            local w = idx <= n and y < height and C_FriendList.GetWhoInfo(idx)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", wbody, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", wbody, "TOPRIGHT", 0, -y)
            r:SetHeight(rowH)
            if type(w) == "table" then WhoLayout(r, rowH); WhoFill(r, w)
            else r.info, r.who = nil, nil; r:Hide() end
        end
        for i = slots + 1, #wrows do wrows[i]:Hide() end
        if maxPx > 0 then
            local th = math.max(16, height * height / (maxPx + height))
            wthumb:SetHeight(th)
            wthumb:ClearAllPoints()
            wthumb:SetPoint("TOPRIGHT", wf, "TOPRIGHT", -thumbX, -(height - th) * (wscroll / maxPx))
            wthumb:Show()
        else
            wthumb:Hide()
        end
    end
    ns.ForeverWhoPaint = WhoPaint

    -- keep blizzard's list hidden while ours shows
    local function WhoHold(f, a)
        if wguard or not won or a == 0 then return end
        wguard = true
        f:SetAlpha(0)
        wguard = false
    end

    local function WhoOn(on)
        if not wf then return end
        if on ~= won then
            won = on
            local a = on and 0 or 1
            wguard = true
            whoF.ScrollBox:SetAlpha(a)
            if whoF.ScrollBar then whoF.ScrollBar:SetAlpha(a) end
            wguard = false
            wf:SetShown(on)
            if on then
                wf:RegisterEvent("WHO_LIST_UPDATE")
                wf:RegisterEvent("GROUP_ROSTER_UPDATE")
                wscroll = 0
            else
                wf:UnregisterAllEvents()
            end
        end
        if on then WhoPaint() end
    end

    local function WhoBuild(who)
        whoF = who
        wf = CreateFrame("Frame", nil, who)
        wf:SetFrameLevel(who.ScrollBox:GetFrameLevel() + 10)
        wf:EnableMouse(true)  -- blizzard's faded rows never get clicks
        wf:EnableMouseWheel(true)
        wf:SetScript("OnMouseWheel", function(_, delta)
            wscroll = wscroll - delta * (ns.OwnListRowHeight() + GAP) * 2
            WhoPaint()
        end)
        wf:SetScript("OnSizeChanged", WhoPaint)
        wf:SetScript("OnEvent", function(_, event)
            if event == "WHO_LIST_UPDATE" then wscroll = 0 end
            WhoPaint()
        end)
        wf:Hide()
        wbody = CreateFrame("Frame", nil, wf)
        wbody:SetPoint("TOPLEFT", wf, "TOPLEFT", 0, 0)
        wbody:SetPoint("BOTTOMLEFT", wf, "BOTTOMLEFT", 0, 0)
        wbody:SetWidth(LIST_W)
        wbody:SetClipsChildren(true)
        wthumb = wf:CreateTexture(nil, "OVERLAY")
        wthumb:SetWidth(3)
        wthumb:SetColorTexture(1, 1, 1, 0.3)
        hooksecurefunc(who.ScrollBox, "SetAlpha", WhoHold)
        if who.ScrollBar then hooksecurefunc(who.ScrollBar, "SetAlpha", WhoHold) end
        -- blizzard's glowing lines over and under the list, as on the browser
        for _, t in ipairs({ who.BarTop, who.BarMiddle }) do
            if t then
                t:SetAlpha(0)
                hooksecurefunc(t, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
            end
        end
        -- blizzard's list refilled or sorted: ours reads the new order
        if who.ScrollBox.SetDataProvider then hooksecurefunc(who.ScrollBox, "SetDataProvider", function() WhoPaint() end) end
        if C_FriendList.SortWho then hooksecurefunc(C_FriendList, "SortWho", function() WhoPaint() end) end
        who:HookScript("OnHide", function() WhoOn(false) end)
        who:HookScript("OnSizeChanged", function() if who:IsVisible() then ns.ForeverWho() end end)
    end

    -- search rests after each who, as refresh does on the browser: a dark sweep,
    -- a dim glyph, and a cover over the button that only shows the reason
    local wcdUntil, wcd, wcover = 0, nil, nil
    local function WhoPaintCooldown(go)
        local on = GetTime() < wcdUntil
        if wcover then wcover:SetShown(on) end
        if go.Icon then go.Icon:SetAlpha(on and 0.3 or 1) end
    end
    local function WhoCooldown(go)
        local px = (EUI.PP and EUI.PP.mult) or 1
        wcd = CreateFrame("Cooldown", nil, go:GetParent(), "CooldownFrameTemplate")
        wcd:SetPoint("TOPLEFT", go, "TOPLEFT", px, -px)
        wcd:SetPoint("BOTTOMRIGHT", go, "BOTTOMRIGHT", -px, px)
        wcd:SetFrameLevel(go:GetFrameLevel() + 3)
        if wcd.SetDrawEdge then wcd:SetDrawEdge(false) end
        if wcd.SetHideCountdownNumbers then wcd:SetHideCountdownNumbers(true) end
        if wcd.SetSwipeColor then wcd:SetSwipeColor(0, 0, 0, 0.65) end
        wcover = CreateFrame("Button", nil, go:GetParent())
        wcover:SetAllPoints(go)
        wcover:SetFrameLevel(go:GetFrameLevel() + 8)
        wcover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(SEARCH or "Search", 1, 1, 1)
            GameTooltip:AddLine(EUI.Lf("Limited to every %d seconds to prevent lock-out", CD_SEARCH), 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        wcover:SetScript("OnLeave", GameTooltip_Hide)
        wcover:Hide()
        -- every who (the button, enter in the box, /who) starts it
        if C_FriendList.SendWho then
            hooksecurefunc(C_FriendList, "SendWho", function()
                if not ns.Enabled() then return end
                local now = GetTime()
                if now + CD_SEARCH <= wcdUntil then return end
                wcdUntil = now + CD_SEARCH
                wcd:SetCooldown(now, CD_SEARCH)
                WhoPaintCooldown(go)
                C_Timer.After(CD_SEARCH, function() WhoPaintCooldown(go) end)
            end)
        end
    end

    function ns.ForeverWho()
        local who = _G.LFGWhoListFrame
        local eb, go, fd = who and who.EditBox, who and who.WhoSearch, who and who.FilterDropdown
        local sb = BF and BF.ScrollBox
        if not (eb and go and fd and sb and who.ScrollBox) then return end
        if not ns.Enabled() then WhoOn(false); return end
        if InCombatLockdown() then
            if EUI.CombatQueue then EUI.CombatQueue.Defer("GroupFinderForeverWho", ns.ForeverWho) end
            return
        end
        if not whoDressed then
            whoDressed = true
            Face(fd)
            for _, m in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do hooksecurefunc(fd, m, HoldFilter) end
            -- blizzard's square art goes: the skin's box under it, the glyph white
            -- at the refresh glyph's size and shade
            for _, t in ipairs({ go:GetNormalTexture(), go:GetPushedTexture(), go:GetHighlightTexture() }) do
                t:SetAlpha(0)
            end
            local ic = go.Icon
            if ic then
                ic:SetDesaturated(true)
                ic:SetVertexColor(1, 1, 1, 0.9)
                ic:SetSize(16, 16)
                ic:ClearAllPoints()
                ic:SetPoint("CENTER", go, "CENTER", 0, 0)
                go:HookScript("OnEnter", function() ic:SetVertexColor(1, 1, 1, 1) end)
                go:HookScript("OnLeave", function() ic:SetVertexColor(1, 1, 1, 0.9) end)
            end
            RefreshBox(go)
            WhoCooldown(go)
            WhoBuild(who)
        end
        local y = -(topY or 43)
        go:ClearAllPoints()
        go:SetPoint("TOP", who, "TOP", 0, y)
        go:SetPoint("RIGHT", sb, "LEFT", LIST_X + LIST_W, 0)
        go:SetSize(ROW1_H, ROW1_H)
        fd:ClearAllPoints()
        fd:SetPoint("TOPRIGHT", go, "TOPLEFT", -ROW_GAP, 0)
        fd:SetSize(ACT_W, ROW1_H)
        eb:ClearAllPoints()
        eb:SetPoint("TOP", who, "TOP", 0, y)
        eb:SetPoint("LEFT", sb, "LEFT", LIST_X, 0)
        -- from the list's edge, not the filter: nothing it does moves the box
        eb:SetPoint("RIGHT", sb, "LEFT", LIST_X + LIST_W - ROW1_H - ACT_W - ROW_GAP * 2, 0)
        eb:SetHeight(ROW1_H)
        -- the list: under the top bar, down to where blizzard's ends
        wf:ClearAllPoints()
        wf:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -WHO_GAP)
        wf:SetWidth(LIST_W + 7)
        wf:SetHeight(math.max(40, (who:GetHeight() or 0) + y - ROW1_H - WHO_GAP - WHO_BOTTOM))
        WhoOn(who:IsVisible())
    end
end

-------------------------------------------------------------------------------
--  the settings cog at the start of row 1, and on dungeons row 2: one
--  sideways-scrolling line of every dungeon across the list's width. the ones
--  blizzard leaves out at your level are greyed and can't be picked
-------------------------------------------------------------------------------
local SQ, ARROW_W, GLYPH = 28, 14, 0.78
local LIST_GAP = 9  -- room under the dungeon row
local ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local row2, cog, strip
local dungeons = {}
local PaintStrip

local function Tip(owner, title, ...)
    local text = title
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then text = text .. "\n|cffb3b3b3" .. line .. "|r" end
    end
    EUI.ShowWidgetTooltip(owner, text)
end
local function Untip() EUI.HideWidgetTooltip() end

local function ThemeBorder()
    local S = WSkin()
    local T = S and S.Theme
    if T and T.brdR then return T.brdR, T.brdG, T.brdB, T.brdA end
    return 0.25, 0.25, 0.25, 1
end

local function Skinned(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetText(" ")
    local S = WSkin()
    if S and S.Button then
        S.Button(b)
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        EUI.MakeBorder(b, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    -- our art on a child, above the border and clear of the skin's restrip
    b.top = CreateFrame("Frame", nil, b)
    b.top:SetAllPoints()
    b.top:SetFrameLevel(b:GetFrameLevel() + 3)
    b.top:EnableMouse(false)
    return b
end

-- short names for the old dungeons, else the initials
-- by the lowercased name, "the " dropped; a wing by "base:wing"
local Short
do
    local SHORT = {
        ["ragefire chasm"] = "RFC", ["wailing caverns"] = "WC", ["deadmines"] = "DM",
        ["shadowfang keep"] = "SFK", ["blackfathom deeps"] = "BFD",
        ["stockade"] = "SWS", ["stockades"] = "SWS", ["stormwind stockade"] = "SWS", ["stormwind stockades"] = "SWS",
        ["ruins of lordaeron"] = "RoL",
        ["gnomeregan"] = "GNO", ["razorfen kraul"] = "RFK", ["razorfen downs"] = "RFD",
        ["uldaman"] = "UDM", ["zul'farrak"] = "ZF", ["maraudon"] = "MAR",
        ["sunken temple"] = "ST", ["temple of atal'hakkar"] = "ST", ["blackrock depths"] = "BRD",
        ["lower blackrock spire"] = "LBRS", ["upper blackrock spire"] = "UBRS",
        ["scholomance"] = "SCH", ["stratholme"] = "Strat",
        ["scarlet monastery:graveyard"] = "SM:G", ["scarlet monastery:library"] = "SM:L",
        ["scarlet monastery:armory"] = "SM:A", ["scarlet monastery:cathedral"] = "SM:C",
        graveyard = "SM:G", library = "SM:L", armory = "SM:A", cathedral = "SM:C",
        ["dire maul:east"] = "DM:E", ["dire maul:north"] = "DM:N", ["dire maul:west"] = "DM:W",
        ["dire maul east"] = "DM:E", ["dire maul north"] = "DM:N", ["dire maul west"] = "DM:W",
        ["stratholme:service gate"] = "S:SG", ["stratholme:service entrance"] = "S:SG", ["stratholme:undead"] = "S:SG",
        ["stratholme:main gate"] = "S:MG", ["stratholme:live"] = "S:MG",
        ["stratholme service gate"] = "S:SG", ["stratholme main gate"] = "S:MG",
        -- forever's own dungeons
        ["hall of thanes"] = "HoT", ["city of dalaran"] = "CoD", ["drowned city"] = "TDC",
        ["krol'dok stronghold"] = "KSH", ["blackmaw hold"] = "BMH", ["shaper's terrace"] = "TST",
        ["excavation site: wetlands"] = "ESW", ["alcaz prison"] = "AP",
    }
    local SMALL = { of = true, the = true, ["and"] = true }
    local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"

    function Short(name)
        name = name or ""
        local base, wing = name:match("^(.-)%s*%((.-)%)%s*$")
        if base and base ~= "" then
            local hit = SHORT[base:lower():gsub("^the ", "") .. ":" .. wing:lower()]
            if hit then return hit end
        end
        name = name:gsub("%s*%b()", "")
        local key = name:lower():gsub("^the ", "")
        if SHORT[key] then return SHORT[key] end
        -- "scarlet monastery - library", "dire maul - east"
        local base, part = name:match("^(.-)%s*[%-:]%s+(.+)$")
        if base and base ~= "" then
            local b = base:lower():gsub("^the ", "")
            return SHORT[b .. ":" .. part:lower()] or SHORT[part:lower()]
                or (Short(base) .. (part:match(UTF8) or ""):upper())
        end
        local out = {}
        for w in name:gmatch("%S+") do
            if not SMALL[w:lower()] then out[#out + 1] = (w:match(UTF8) or ""):upper() end
        end
        if #out > 1 then return table.concat(out) end
        -- one word: its first four letters
        local head, n = {}, 0
        for c in name:gmatch(UTF8) do
            n = n + 1
            if n > 4 then break end
            head[n] = c
        end
        return table.concat(head)
    end
end

-- a dungeon's code by its activity (wings sharing one map), else by its instance
-- map: the same in every language. Short() of the name for any other
local Code
do
    local CODE_BY_ACT = {
        [805] = "SM:G", [827] = "SM:A", [828] = "SM:C", [829] = "SM:L",
        [813] = "DM:E", [814] = "DM:W", [815] = "DM:N",
        [812] = "LBRS", [837] = "UBRS", [816] = "S:MG", [1603] = "S:SG",
    }
    local CODE_BY_MAP = {
        [389] = "RFC", [43] = "WC", [36] = "DM", [33] = "SFK", [48] = "BFD", [34] = "SWS", [90] = "GNO",
        [47] = "RFK", [189] = "SM", [129] = "RFD", [70] = "UDM", [209] = "ZF", [349] = "MAR", [109] = "ST",
        [230] = "BRD", [229] = "LBRS", [429] = "DM:N", [289] = "SCH", [329] = "Strat",
        -- forever's own
        [3065] = "HoT", [2959] = "CoD", [2999] = "RoL", [2998] = "ESW", [2994] = "AP",
        [2970] = "TDC", [3039] = "KSH", [2974] = "BMH", [3001] = "TST",
    }
    function Code(d)
        return CODE_BY_ACT[d.id] or (d.map and CODE_BY_MAP[d.map]) or Short(d.name)
    end
end

-- blizzard's own lfg dungeon art, by instance map. nil when the client doesn't have the file
local LFG_ICONS = "Interface\\LFGFrame\\LFGIcon-"
local ICON_BY_MAP = {
    [389] = "RagefireChasm", [43] = "WailingCaverns", [36] = "Deadmines", [33] = "ShadowfangKeep",
    [48] = "BlackfathomDeeps", [34] = "StormwindStockades", [90] = "Gnomeregan", [47] = "RazorfenKraul",
    [189] = "ScarletMonastery", [129] = "RazorfenDowns", [70] = "Uldaman", [209] = "ZulFarak",
    [349] = "Maraudon", [109] = "SunkenTemple", [230] = "BlackrockDepths", [229] = "BlackrockSpire",
    [429] = "DireMaul", [289] = "Scholomance", [329] = "Stratholme",
    -- forever's own, should the client have art for them
    [3065] = "HallofThanes", [2959] = "CityofDalaran", [2999] = "RuinsofLordaeron",
    [2998] = "ExcavationSiteWetlands", [2994] = "AlcazPrison", [2970] = "DrownedCity",
    [3039] = "KroldokStronghold", [2974] = "BlackmawHold", [3001] = "ShapersTerrace",
}
-- the journal's button art is wide: its middle square
local JOURNAL_CROP = { 0.156, 0.527, 0, 0.742 }
local function JournalArt(mapID)
    if not (mapID and EJ_GetInstanceForMap and EJ_GetInstanceInfo) then return nil end
    local inst = EJ_GetInstanceForMap(mapID)
    if not inst or inst == 0 then return nil end
    local _, _, _, button = EJ_GetInstanceInfo(inst)
    if button and button ~= 0 and button ~= "" then return button end
    return nil
end

-- the zone a dungeon sits in, by its instance map: that zone's icon
local ZoneArt
do
    local ZONE_ART = "Interface\\Icons\\Achievement_Zone_"
    local ZONE_OF = {
        [3065] = "DunMorogh",             -- hall of thanes
        [2998] = "Wetlands_01",           -- excavation site: wetlands
        [2959] = "AlteracMountains_01",   -- city of dalaran
        [2994] = "DustwallowMarsh",       -- alcaz prison
        [2970] = "Stranglethorn_01",      -- the drowned city
        -- krol'dok stronghold: riverglades has no icon of its own, river and marsh country instead
        [3039] = { "Riverglades", "Zangarmarsh", "SwampSorrows_01", "Wetlands_01" },
        [2974] = "Azshara_01",            -- blackmaw hold
        [3001] = "UnGoroCrater_01",       -- the shaper's terrace
    }
    function ZoneArt(mapID)
        local z = mapID and ZONE_OF[mapID]
        if not z then return nil end
        for _, zone in ipairs(type(z) == "table" and z or { z }) do
            local path = ZONE_ART .. zone
            if not GetFileIDFromPath or GetFileIDFromPath(path) then return path end
        end
        return nil
    end
end

local icons = {}  -- activity id -> { art, crop }, or false
local function DungeonIcon(id, ai)
    local c = icons[id]
    if c ~= nil then
        if c then return c[1], c[2] end
        return nil
    end
    local key = ai.mapID and ICON_BY_MAP[ai.mapID]
    local path = key and (LFG_ICONS .. key) or nil
    if path and GetFileIDFromPath and not GetFileIDFromPath(path) then path = nil end
    local crop
    if not path then
        path = JournalArt(ai.mapID)
        crop = path and JOURNAL_CROP
    end
    if not path then path = ZoneArt(ai.mapID) end
    icons[id] = path and { path, crop } or false
    return path, crop
end

-- every dungeon in blizzard's list, low levels first
local function Dungeons()
    wipe(dungeons)
    if Category() ~= DUNGEONS then return dungeons end
    local ok = {}
    for _, id in ipairs(Available()) do ok[id] = true end
    local all = C_LFGList.GetAvailableActivities and C_LFGList.GetAvailableActivities(DUNGEONS) or NONE
    for i, id in ipairs(all) do
        local ai = C_LFGList.GetActivityInfoTable(id)
        if ai then
            dungeons[#dungeons + 1] = { id = id, i = i, map = ai.mapID, name = ai.fullName or ai.shortName or "?",
                ok = ok[id] == true, lo = ai.minLevelSuggestion or 0, hi = ai.maxLevelSuggestion or 0,
                icon = nil, crop = nil }
            local d = dungeons[#dungeons]
            d.icon, d.crop = DungeonIcon(id, ai)
        end
    end
    table.sort(dungeons, function(a, b)
        if a.lo ~= b.lo then return a.lo < b.lo end
        return a.i < b.i
    end)
    return dungeons
end

local function SquareEnter(self)
    local d = self.dungeon
    if not d then return end
    local lv
    if d.lo > 0 then
        lv = (LEVEL or "Level") .. " " .. d.lo
        if d.hi > d.lo then lv = lv .. "-" .. d.hi end
    end
    Tip(self, d.name, lv, d.ok and EUI.L("Click to toggle") or nil)
end

local function Toggle(self)
    local d = self.dungeon
    if not (d and d.ok) then return end
    local c = ns.Cfg()
    if type(c.foreverDungeons) ~= "table" then c.foreverDungeons = {} end
    local p = c.foreverDungeons
    p[d.id] = (not p[d.id]) or nil
    -- all picked is the same as none
    local all = true
    for _, id in ipairs(Available()) do
        if not p[id] then all = false; break end
    end
    if all then wipe(p) end
    scrollPx = 0
    Collect()
    Paint()
    PaintStrip()
    SquareEnter(self)
end

local function MakeSquare()
    local b = Skinned(strip.clip, SQ, SQ)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    local px = (EUI.PP and EUI.PP.mult) or 1
    b.icon = b.top:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", px, -px)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -px, px)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = b.top:CreateFontString(nil, "OVERLAY")
    b.label:SetPoint("CENTER", b, "CENTER", 1, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("MIDDLE")
    b.label:SetWordWrap(false)
    b:SetScript("OnEnter", SquareEnter)
    b:SetScript("OnLeave", Untip)
    b:SetScript("OnClick", Toggle)
    return b
end

-- the label as big as fits
local function LabelSize(sq, size)
    if sq.size == size then return end
    sq.size = size
    EUI.ApplyModuleFont(sq.label, nil, size, FOLDER, "OUTLINE")
end

-- every shown name at one size, the largest the widest of them fits at
local labelKey
local function SizeLabels(named)
    local texts = {}
    for _, sq in ipairs(named) do texts[#texts + 1] = sq.text end
    local key = table.concat(texts, "|")
    if key == labelKey then return end
    labelKey = key
    local size = math.max(8, math.floor(SQ * 0.36))
    while true do
        local widest = 0
        for _, sq in ipairs(named) do
            LabelSize(sq, size)
            widest = math.max(widest, sq.label:GetUnboundedStringWidth() or 0)
        end
        if size <= 8 or widest <= SQ - 4 then break end
        size = size - 1
    end
    -- two sizes up from there, all the same
    for _, sq in ipairs(named) do LabelSize(sq, size + 2) end
end

local function Label(sq, text)
    -- the font first: text on a fontstring with no font errors
    if not sq.size then LabelSize(sq, math.max(8, math.floor(SQ * 0.36))) end
    if sq.text ~= text then
        sq.label:SetText(text)
        sq.text = text
    end
end

-- whole squares only, and only those fully in view
local function PlaceStrip()
    local per = SQ + ROW_GAP
    local full = math.max(1, math.floor((strip.clipW + ROW_GAP) / per))
    local maxOff = math.max(0, #dungeons - full)
    strip.offset = math.max(0, math.min(strip.offset, maxOff))
    -- the room left after the whole squares, split both sides
    local lead = math.floor(math.max(0, strip.clipW - (math.min(full, #dungeons) * per - ROW_GAP)) / 2)
    for i, sq in ipairs(strip.squares) do
        if dungeons[i] then
            local x = lead + (i - 1 - strip.offset) * per
            sq:ClearAllPoints()
            sq:SetPoint("LEFT", strip.clip, "LEFT", x, 0)
            sq:SetShown(x >= 0 and x + SQ <= strip.clipW + 0.5)
        else
            sq:Hide()
        end
    end
    for _, a in ipairs({ { strip.left, strip.offset > 0 }, { strip.right, strip.offset < maxOff } }) do
        local b, on = a[1], a[2]
        b.live = on
        b:EnableMouse(on)
        b.tex:SetAlpha(on and 0.8 or 0.2)
    end
end

local function Scroll(step)
    strip.offset = strip.offset + step
    PlaceStrip()
    PaintStrip()
end

local function Arrow(file, step)
    local b = CreateFrame("Button", nil, row2)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetTexture(ICONS .. file)
    b.tex:SetSize(16, 16)
    b.tex:SetPoint("CENTER")
    b:SetScript("OnClick", function() Scroll(step) end)
    b:SetScript("OnEnter", function(self) if self.live then self.tex:SetAlpha(1) end end)
    b:SetScript("OnLeave", function(self) self.tex:SetAlpha(self.live and 0.8 or 0.2) end)
    return b
end

-- picked: white border; with picks the rest go dim; out of level: grey, no clicks
PaintStrip = function()
    if not strip then return end
    local want = LivePicks()
    for _, sq in ipairs(strip.squares) do
        local d = sq.dungeon
        if d and sq:IsShown() then
            local on = want ~= nil and want[d.id] == true
            local bright = d.ok and (not want or on)
            sq:SetEnabled(d.ok)
            sq.icon:SetDesaturated(not bright)
            sq.icon:SetAlpha(bright and 1 or (d.ok and 0.45 or 0.3))
            if not d.ok then
                sq.label:SetTextColor(0.5, 0.5, 0.5)
                sq.label:SetAlpha(0.6)
                sq:SetAlpha(0.5)
            else
                sq.label:SetTextColor(1, 1, 1)
                sq.label:SetAlpha(bright and 1 or 0.45)
                sq:SetAlpha(1)
            end
            if on then EUI.PanelPP.SetBorderColor(sq, 1, 1, 1, 1)
            else EUI.PanelPP.SetBorderColor(sq, ThemeBorder()) end
        end
    end
end

local labelled = {}
local function LayoutStrip()
    local list = Dungeons()
    if #list == 0 then
        strip.clip:Hide(); strip.left:Hide(); strip.right:Hide()
        for _, sq in ipairs(strip.squares) do sq.dungeon = nil; sq:Hide() end
        return
    end
    local per = SQ + ROW_GAP
    local room = LIST_W
    local fits = #list * per - ROW_GAP <= room
    strip.clip:ClearAllPoints()
    strip.left:ClearAllPoints()
    strip.right:ClearAllPoints()
    if fits then
        strip.left:Hide(); strip.right:Hide()
        strip.clipW = #list * per - ROW_GAP
        strip.clip:SetPoint("LEFT", row2, "LEFT", 0, 0)
    else
        strip.clipW = room - 2 * (ARROW_W + ROW_GAP)
        strip.left:SetSize(ARROW_W, SQ)
        strip.right:SetSize(ARROW_W, SQ)
        strip.left:SetPoint("LEFT", row2, "LEFT", 0, 0)
        strip.right:SetPoint("RIGHT", row2, "RIGHT", 0, 0)
        strip.left:Show(); strip.right:Show()
        strip.clip:SetPoint("LEFT", strip.left, "RIGHT", ROW_GAP, 0)
    end
    strip.clip:SetSize(strip.clipW, SQ)
    strip.clip:Show()
    for i, d in ipairs(list) do
        local sq = strip.squares[i]
        if not sq then sq = MakeSquare(); strip.squares[i] = sq end
        sq.dungeon = d
        sq.icon:SetTexture(d.icon)
        local c = d.crop
        if c then sq.icon:SetTexCoord(c[1], c[2], c[3], c[4])
        else sq.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        sq.icon:SetShown(d.icon ~= nil)
        -- the name when it's on, or when there's no art to show
        local named = Shown("dungeonAbbr") or not d.icon
        if named then
            Label(sq, Code(d))
            labelled[#labelled + 1] = sq
        end
        sq.label:SetShown(named)
    end
    SizeLabels(labelled)
    wipe(labelled)
    for i = #list + 1, #strip.squares do strip.squares[i].dungeon = nil end
    PlaceStrip()
end

local function MakeRow2()
    row2 = CreateFrame("Frame", nil, frame)
    row2:SetSize(LIST_W, SQ)
    cog = Skinned(frame, ROW1_H, ROW1_H)
    cog.glyph = cog.top:CreateTexture(nil, "OVERLAY")
    cog.glyph:SetTexture(EUI.COGS_ICON)
    cog.glyph:SetSize(math.floor(ROW1_H * 0.6), math.floor(ROW1_H * 0.6))
    cog.glyph:SetDesaturated(true)
    cog.glyph:SetVertexColor(GLYPH, GLYPH, GLYPH)
    cog.glyph:SetPoint("CENTER")
    cog.glyph:SetAlpha(0.8)
    cog:SetScript("OnEnter", function(self)
        self.glyph:SetAlpha(1)
        Tip(self, EUI.L("Group Filters Settings"))
    end)
    cog:SetScript("OnLeave", function(self)
        self.glyph:SetAlpha(0.8)
        Untip()
    end)
    cog:SetScript("OnClick", function()
        Untip()
        if InCombatLockdown() then
            EUI.PrintError(EUI.L("Cannot open options during combat."))
            return
        end
        EUI:ShowModule(FOLDER)
    end)
    strip = { offset = 0, squares = {}, clipW = 0 }
    strip.clip = CreateFrame("Frame", nil, row2)
    strip.clip:SetClipsChildren(true)
    strip.clip:EnableMouseWheel(true)
    strip.clip:SetScript("OnMouseWheel", function(_, delta) Scroll(delta > 0 and -1 or 1) end)
    strip.left = Arrow("eui-arrow-left.png", -1)
    strip.right = Arrow("eui-arrow-right.png", 1)
    -- the list's top is set by Row2
    local sb = BF.ScrollBox
    frame:ClearAllPoints()
    if BF.SendMessageButton then
        frame:SetPoint("BOTTOMLEFT", BF.SendMessageButton, "TOPLEFT", 0, LIST_GAP)
    else
        frame:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", LIST_X, 0)
    end
end

-- the settings page's dungeon names toggle
function ns.ForeverSquares()
    if not (strip and active) then return end
    LayoutStrip()
    PaintStrip()
end

-- under row 1, blizzard's offset if it hasn't been read yet
local function Row2()
    if not row2 then MakeRow2() end
    row2:ClearAllPoints()
    row2:SetPoint("TOP", BF, "TOP", 0, -((topY or 43) + ROW1_H + ROW_GAP))
    row2:SetPoint("LEFT", BF.ScrollBox, "LEFT", LIST_X, 0)
    cog:ClearAllPoints()
    cog:SetPoint("TOP", BF, "TOP", 0, -(topY or 43))
    cog:SetPoint("LEFT", BF.ScrollBox, "LEFT", LIST_X, 0)
    -- the list under the dungeon row, or row 1 when there's none
    local dung = Category() == DUNGEONS
    row2:SetShown(dung)
    frame:SetPoint("TOPLEFT", row2, dung and "BOTTOMLEFT" or "TOPLEFT", 0, dung and -LIST_GAP or -(LIST_GAP - ROW_GAP))
    LayoutStrip()
    PaintStrip()
end

-------------------------------------------------------------------------------
--  directions: on dungeons, where the activity filter sits, every dungeon by
--  level band. a click prints the entrance's map pin link in chat, as /way
--  does, and a click on that has blizzard place the pin: nothing here sets a
--  waypoint or tracks one
-------------------------------------------------------------------------------
do
    -- by Code(): zone uiMapID, x, y. the classic ones from wowhead's forever dungeon
    -- guide; forever's own are where that guide places them
    local SM, BRM, DMAUL = { 1420, 83.5, 32.0 }, { 1427, 35.2, 84.2 }, { 1444, 58.9, 41.5 }
    local ENTRANCES = {
        RFC = { 1454, 52.0, 49.0 }, WC = { 1413, 45.5, 35.5 }, DM = { 1436, 42.4, 70.4 },
        SFK = { 1421, 42.6, 66.6 }, BFD = { 1440, 13.4, 12.8 }, SWS = { 1453, 41.0, 57.0 },
        GNO = { 1426, 30.5, 36.3 }, RFK = { 1413, 42.6, 88.5 }, RFD = { 1413, 50.0, 92.0 },
        SM = SM, ["SM:G"] = SM, ["SM:L"] = SM, ["SM:A"] = SM, ["SM:C"] = SM,
        UDM = { 1418, 42.6, 10.8 }, ZF = { 1446, 39.5, 21.3 }, MAR = { 1443, 29.5, 57.8 },
        ST = { 1435, 69.6, 53.2 },
        -- blackrock mountain, from the searing gorge
        BRD = BRM, LBRS = BRM, UBRS = BRM,
        ["DM:N"] = DMAUL, ["DM:E"] = DMAUL, ["DM:W"] = DMAUL,
        SCH = { 1422, 69.8, 76.0 },
        Strat = { 1423, 30.9, 15.2 }, ["S:MG"] = { 1423, 30.9, 15.2 }, ["S:SG"] = { 1423, 48.3, 21.8 },
        -- forever's own
        HoT = { 1455, 43.0, 51.0 }, RoL = { 1420, 63.1, 67.5 }, CoD = { 1416, 8.8, 59.6 },
        ESW = { 1437, 47.8, 56.2 }, AP = { 1445, 75.3, 14.1 }, TDC = { 1434, 21.4, 27.9 },
        KSH = { 16591, 37.5, 37.2 }, BMH = { 1447, 38.4, 32.6 }, TST = { 1449, 48.1, 6.1 },
    }
    -- how to find each way in, by the same codes. english here, through L() when drawn
    local TIPS = {
        RFC = "In Orgrimmar, inside the Cleft of Shadow.",
        WC = "In the Barrens, southwest of the Crossroads, in the hills above the oasis.",
        DM = "In Westfall, inside a building in Moonbrook: follow the mine down to the portal.",
        SFK = "In Silverpine Forest, on the hill above Pyrewood Village.",
        SWS = "In Stormwind City, beneath the canal district.",
        BFD = "In Ashenvale, along the Zoram Strand on the northwest coast.",
        GNO = "In western Dun Morogh, northwest of Kharanos.",
        RFK = "In the southern Barrens, at the edge of Thousand Needles.",
        RFD = "In the southern Barrens, past Razorfen Kraul, at the edge of Thousand Needles.",
        SM = "In northeast Tirisfal Glades. Each wing has its own door in the monastery's courtyard.",
        UDM = "In the northern Badlands.",
        ZF = "In northwest Tanaris, inside the walled troll city.",
        MAR = "In western Desolace: go down into the canyon and through either cave to the portal inside.",
        ST = "In the Swamp of Sorrows, the sunken temple in the Pool of Hakkar.",
        BRD = "Inside Blackrock Mountain: take the chains down to the lowest level.",
        LBRS = "Inside Blackrock Mountain: take the chains up to the highest level.",
        SCH = "In the Western Plaguelands, beneath Caer Darrow, the island in Darrowmere Lake.",
        ["DM:N"] = "In Feralas, the ruins of Dire Maul. Each wing has its own door; West and North need the Crescent Key.",
        ["S:MG"] = "In the far north of the Eastern Plaguelands: the main gate, the living side.",
        ["S:SG"] = "In the far north of the Eastern Plaguelands, east of the main gate: the service gate, the undead side. It needs the Key to the City, or a way through from the living side.",
        HoT = "Beneath the city of Ironforge.",
        RoL = "In Tirisfal Glades, above the Undercity.",
        CoD = "In the Alterac Mountains, in the city of Dalaran.",
        ESW = "In the Wetlands, on top of Whelgar's Excavation Site.",
        TDC = "Off the coast of Stranglethorn Vale: the entrance is underwater.",
        KSH = "In the hills of the Riverglades, on the east coast of the Eastern Kingdoms.",
        AP = "On Alcaz Island, in the far northeast of Dustwallow Marsh.",
        BMH = "In northern Azshara, behind the Furbolg Gates.",
        TST = "In the hills of Un'Goro Crater, near Marshal's Refuge.",
    }
    for _, k in ipairs({ "SM:G", "SM:L", "SM:A", "SM:C" }) do TIPS[k] = TIPS.SM end
    TIPS["DM:E"], TIPS["DM:W"] = TIPS["DM:N"], TIPS["DM:N"]
    TIPS.UBRS = TIPS.LBRS
    TIPS.Strat = TIPS["S:MG"]
    local TIP_FONT, TIP_W = 9, LIST_W - 44  -- the tip's size, and its width (inside the menu's padding and bar)

    local BANDS = { { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 60 } }
    local DIRECTIONS_H = 280  -- the menu's height before it scrolls
    local ROW_PAD, TIP_SPACING = 6, 3  -- room under each row; between a tip's lines
    local LINE_H = 16  -- each of the name and /way lines
    local DIR_ROW_FONT = 10
    ns.foreverDirBands = {}
    ns.foreverDirsOff = {}  -- names with no entrance (drawn grey)
    for i, b in ipairs(BANDS) do
        b.label = ("%s %d-%d"):format(EUI.L("Levels"), b[1], b[2])
        ns.foreverDirBands[i] = b.label
    end

    local function Entrance(d)
        local e = ENTRANCES[Code(d)]
        local map = e and e[1]
        if map and C_Map.CanSetUserWaypointOnMap(map) then return map, e[2], e[3] end
    end

    local function Way(map, x, y)
        local info = C_Map.GetMapInfo(map)
        return ("/way %s %.1f %.1f"):format(info and info.name or ("#" .. map), x, y)
    end

    -- the link C_Map.GetUserWaypointHyperlink builds: x, y in 0..100 travel as 0..10000
    local hinted
    local function Print(name, map, x, y)
        local CC = EUI.COLOR_CODES
        local link = ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(map,
            math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5), MAP_PIN_HYPERLINK or "Map Pin")
        EUI.Print(CC.BRAND .. "EllesmereUI:|r " .. link .. " " .. CC.WHITE .. name .. "|r "
            .. CC.DIM .. ("%.1f, %.1f"):format(x, y) .. "|r")
        if not hinted then
            hinted = true
            EUI.Print(CC.BRAND .. "EllesmereUI:|r " .. CC.DIM
                .. EUI.L("Click a link to place the pin, then click the pin on the map to track it.") .. "|r")
        end
    end

    -- a line printed in combat taints chat history: it waits for the end of combat
    local function Pick(d)
        local map, x, y = Entrance(d)
        if not map then return end
        local name = d.name
        local function Go() Print(name, map, x, y) end
        if InCombatLockdown() and EUI.CombatQueue then
            EUI.CombatQueue.Defer("GroupFinderDirections", Go)
        else
            Go()
        end
    end

    local function InBand(lo, b)
        if b[1] == BANDS[1][1] and lo < b[1] then return true end
        if b[2] == BANDS[#BANDS][2] and lo > b[2] then return true end
        return lo >= b[1] and lo <= b[2]
    end

    -- our own menu on our own button: its rows, the /way text on the right
    -- the frame that clips a row (the scroll box), else the row: its lines end inside it
    local function VisibleEdge(row)
        local p = row:GetParent()
        for _ = 1, 5 do
            if not p then break end
            if p.DoesClipChildren and p:DoesClipChildren() then return p end
            p = p:GetParent()
        end
        return row
    end

    -- a row's hover border (four lines), shown from the row's own enter/leave
    local borders = setmetatable({}, { __mode = "k" })
    local function Hover(button)
        -- blizzard's highlight stays (its enter/leave show it) but draws nothing
        if button.highlight then button.highlight:SetColorTexture(0, 0, 0, 0) end
        local edge = VisibleEdge(button)
        local t = {}
        for i = 1, 4 do
            local line = button:AttachTexture()
            line:SetColorTexture(0.35, 0.35, 0.35, 1)
            line:Hide()
            t[i] = line
        end
        t[1]:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        t[1]:SetPoint("TOPRIGHT", edge, "TOPRIGHT", -2, 0)
        t[1]:SetHeight(1)
        t[2]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        t[2]:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -2, 0)
        t[2]:SetHeight(1)
        t[3]:SetPoint("TOPLEFT", t[1], "TOPLEFT")
        t[3]:SetPoint("BOTTOMLEFT", t[2], "BOTTOMLEFT")
        t[3]:SetWidth(1)
        t[4]:SetPoint("TOPRIGHT", t[1], "TOPRIGHT")
        t[4]:SetPoint("BOTTOMRIGHT", t[2], "BOTTOMRIGHT")
        t[4]:SetWidth(1)
        borders[button] = t
        if button:IsMouseMotionFocus() then for _, l in ipairs(t) do l:Show() end end
    end
    local function ShowBorder(button, on)
        for _, l in ipairs(borders[button] or {}) do l:SetShown(on) end
    end

    local function Fill(_, root)
        root:SetTag("MENU_EUI_GROUPFINDER_DIRECTIONS")
        wipe(ns.foreverDirsOff)
        root:SetScrollMode(DIRECTIONS_H)
        root:SetMinimumWidth(LIST_W)
        local list = Dungeons()
        for _, b in ipairs(BANDS) do
            local titled
            for _, d in ipairs(list) do
                if InBand(d.lo or 0, b) then
                    if not titled then
                        titled = true
                        -- set as each row's drawn: the scroll list redraws rows as it scrolls
                        root:CreateTitle(b.label):AddInitializer(function(frame)
                            -- a divider under the title, as the activity filter's
                            local line = frame:AttachTexture()
                            line:SetColorTexture(1, 1, 1, 0.12)
                            line:SetHeight(1)
                            line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 2)
                            line:SetPoint("BOTTOMRIGHT", VisibleEdge(frame), "BOTTOMRIGHT", -6, 0)
                            local _, size = DropFont():GetFont()
                            if ns.ForeverMenuFont then ns.ForeverMenuFont(frame.fontString, math.floor((size or 12) + 0.5)) end
                            frame.fontString:SetTextColor(0.55, 0.55, 0.55, 1)
                            return 24 + frame.fontString:GetUnboundedStringWidth(), 20 + ROW_PAD
                        end)
                    end
                    local map, x, y = Entrance(d)
                    local way = map and Way(map, x, y)
                    local tip = TIPS[Code(d)]
                    tip = tip and EUI.L(tip)
                    local row = root:CreateButton(d.name, function() Pick(d) end)
                    row:SetOnEnter(function(button) ShowBorder(button, true) end)
                    row:SetOnLeave(function(button) ShowBorder(button, false) end)
                    row:AddInitializer(function(button)
                        local Font = ns.ForeverMenuFont
                        local name = button.fontString
                        if Font then Font(name, DIR_ROW_FONT) end
                        if map then name:SetTextColor(1, 0.82, 0, 1) end
                        name:ClearAllPoints()
                        name:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -2)
                        name:SetHeight(LINE_H)
                        local w, h = 24 + name:GetUnboundedStringWidth(), 2 + LINE_H
                        local fs
                        if way then
                            fs = button:AttachFontString()
                            fs:SetFontObject(GameFontDisableSmall)
                            if Font then Font(fs, DIR_ROW_FONT) end
                            fs:SetTextColor(0.3, 0.3, 0.3, 1)
                            fs:SetHeight(LINE_H)
                            fs:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -h)
                            fs:SetJustifyH("LEFT")
                            fs:SetText(way)
                            w = math.max(w, 24 + fs:GetUnboundedStringWidth())
                            h = h + LINE_H
                        end
                        if tip then
                            -- the second line: how to find it, small and dim, wrapped
                            local fs = button:AttachFontString()
                            fs:SetFontObject(GameFontDisableSmall)
                            if Font then Font(fs, TIP_FONT) end
                            fs:SetTextColor(0.6, 0.6, 0.6, 1)
                            fs:SetJustifyH("LEFT")
                            fs:SetJustifyV("TOP")
                            fs:SetWordWrap(true)
                            fs:SetNonSpaceWrap(false)
                            if fs.SetMaxLines then fs:SetMaxLines(0) end
                            fs:SetSpacing(TIP_SPACING)
                            fs:SetWidth(TIP_W)
                            fs:SetText(tip)
                            fs:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -(h + 2))
                            -- the wrapped height can read as one line before layout: at least
                            -- what the text's length needs, less a little per line for word breaks
                            local _, size = fs:GetFont()
                            local lineH = (size or TIP_FONT) + TIP_SPACING + 1
                            local lines = math.ceil((fs:GetUnboundedStringWidth() or 0) / (TIP_W * 0.88))
                            local th = math.max(math.ceil(fs:GetStringHeight() or 0), lines * lineH)
                            fs:SetHeight(th)
                            h = h + 2 + th
                        end
                        h = h + ROW_PAD
                        Hover(button)
                        return w, h
                    end)
                    if not map then
                        row:SetEnabled(false)  -- no entrance yet
                        ns.foreverDirsOff[d.name] = true
                    end
                end
            end
        end
    end

    function ns.ForeverDirections()
        if ns.foreverDirs then return ns.foreverDirs end
        local dd = CreateFrame("DropdownButton", nil, BF, "WowStyle1DropdownTemplate")
        dd:SetDefaultText(EUI.L("Directions"))
        dd:SetupMenu(Fill)
        dd:Hide()
        ns.foreverDirs = dd
        return dd
    end
end

-------------------------------------------------------------------------------
--  the activity filter as one list, each activity group (a continent) a title.
--  ours, like the dungeon picks: it filters our list and never touches
--  blizzard's dropdown, which is hidden with its picks left empty
-------------------------------------------------------------------------------
do
    local ACTS_H = 280  -- the menu's height before it scrolls
    local picks, pickCat = {}, nil

    -- picks only last for the category they were made in
    local function Picks()
        local c = Category()
        if c ~= pickCat then wipe(picks); pickCat = c end
        return picks
    end
    function ns.ForeverActPicks()
        local p = Picks()
        return next(p) and p or nil
    end

    local function Name(id)
        local ai = C_LFGList.GetActivityInfoTable(id)
        return ai and (LFGUtil_GetActivityInfoName and LFGUtil_GetActivityInfoName(ai) or ai.fullName) or ""
    end

    local function IsOn(id) return Picks()[id] == true end
    local function Toggle(id)
        local p = Picks()
        p[id] = (not p[id]) or nil
        scrollPx = 0
        Collect()
        Paint()
        if ns.foreverRestyleSoon then ns.foreverRestyleSoon() end
    end

    -- each drawn row hands its menu to the restyle
    local function Adopt(frame)
        if ns.ForeverAdoptMenu then ns.ForeverAdoptMenu(frame) end
    end

    local function Fill(_, root)
        root:SetTag("MENU_EUI_GROUPFINDER_ACTIVITIES")
        root:SetScrollMode(ACTS_H)
        local cat = Category()
        local acts = cat > 0 and Available(cat) or {}
        if #acts == 0 then
            root:CreateTitle(EUI.L("Select a category"))
            return
        end
        local byGroup = LFGUtil_OrganizeActivitiesByActivityGroup(acts)
        local groups = GetKeysArray(byGroup)
        LFGUtil_SortActivityGroupIDs(groups)
        for _, g in ipairs(groups) do
            local title = g ~= 0 and C_LFGList.GetActivityGroupInfo(g)
            if title then root:CreateTitle(title):AddInitializer(Adopt) end
            local list = {}
            for _, id in pairs(byGroup[g]) do list[#list + 1] = id end
            table.sort(list, function(a, b) return Name(a) < Name(b) end)
            for _, id in ipairs(list) do
                root:CreateCheckbox(Name(id), IsOn, Toggle, id):AddInitializer(Adopt)
            end
        end
    end

    function ns.ForeverActivities()
        if ns.foreverActs then return ns.foreverActs end
        local dd = CreateFrame("DropdownButton", nil, BF, "WowStyle1DropdownTemplate")
        dd:SetDefaultText(EUI.L("Activity Filter"))
        dd:SetSelectionText(function()
            local n, one = 0, nil
            for id in pairs(Picks()) do n = n + 1; one = id end
            if n == 0 then return EUI.L("Activity Filter") end
            if n == 1 then return Name(one) end
            return LFGBROWSE_ACTIVITY_HEADER and LFGBROWSE_ACTIVITY_HEADER:format(n) or tostring(n)
        end)
        dd:SetupMenu(Fill)
        dd:Hide()
        ns.foreverActs = dd
        local function Sync() dd:SetEnabled(Category() > 0) end
        if BF.CategoryDropdown and BF.CategoryDropdown.SetValue then
            hooksecurefunc(BF.CategoryDropdown, "SetValue", Sync)
        end
        Sync()
        return dd
    end
end

-------------------------------------------------------------------------------
--  the category and activity menus restyled like retail's filters menu:
--  square boxes filled with the accent, the activity groups as grey titles.
--  blizzard builds the menus and handles every click; we only recolour what
--  it already drew, from our own timer once it's done (never inside its menu
--  code: that taints it). blizzard redraws the rows on every tick, so each
--  tick restyles them again. off under the gamepad interface style, as the
--  skin's menus are.
-------------------------------------------------------------------------------
local HookMenus
do
    local MENU_FONT, BOX = 9, 12  -- retail's filters menu: 9pt, 12px boxes
    local menus = {}  -- menu frames open from our two dropdowns
    local groupNames = {}

    -- our dropdowns: the browser's two and its options cog, the listing tab's playstyle and voice chat
    local function Drops()
        local av = _G.LFGListingFrameActivityView
        local t = {}
        for _, dd in pairs({ _G.LFGBrowseFrameCategoryDropdown, _G.LFGBrowseFrameActivityDropdown,
                BF and BF.OptionsButton, av and av.PlayStyleDropdown, av and av.VoiceChatDropdown,
                ns.foreverDirs, ns.foreverActs }) do
            t[#t + 1] = dd
        end
        return t
    end
    -- open, or (over = true) under the cursor
    local function OurMenuOpen(over)
        for _, dd in ipairs(Drops()) do
            if over then
                if dd:IsVisible() and dd:IsMouseOver() then return true end
            elseif dd.IsMenuOpen and dd:IsMenuOpen() then
                return true
            end
        end
        return false
    end

    -- the activity groups' names in the picked category, read from blizzard's api
    local function GroupNames()
        wipe(groupNames)
        -- the directions menu's titles are its level bands
        local dirs = ns.foreverDirs
        ns.foreverDirsOpen = dirs and dirs:IsMenuOpen() or false
        if ns.foreverDirsOpen then
            for _, t in ipairs(ns.foreverDirBands) do groupNames[t] = true end
            return
        end
        -- only the activity menu has group titles (the category menu's rows can share their names)
        local actDD, mine = _G.LFGBrowseFrameActivityDropdown, ns.foreverActs
        if not ((actDD and actDD.IsMenuOpen and actDD:IsMenuOpen()) or (mine and mine:IsMenuOpen())) then return end
        local cat = _G.LFGBrowseFrameCategoryDropdown
        local catID = cat and cat.GetValue and cat:GetValue()
        if not (catID and catID > 0) then return end
        for _, id in ipairs(Available(catID)) do
            local ai = C_LFGList.GetActivityInfoTable(id)
            local g = ai and ai.groupFinderActivityGroupID
            local name = g and g > 0 and C_LFGList.GetActivityGroupInfo(g)
            if name then groupNames[name] = true end
        end
    end

    -- blizzard's menu text refuses SetFont but takes a font object (and resets it
    -- on reuse): one per size, in the module's font with a drop shadow
    local menuFonts, menuFontN = {}, 0
    local function MenuFont(fs, size)
        local path = EUI.GetFontPath(FOLDER)
        local key = path .. size
        local f = menuFonts[key]
        if not f then
            menuFontN = menuFontN + 1
            f = CreateFont("EUIGroupFinderForeverMenuFont" .. menuFontN)
            f:SetFont(path, size, "")
            f:SetShadowColor(0, 0, 0, 1)
            f:SetShadowOffset(1, -1)
            menuFonts[key] = f
        end
        fs:SetFontObject(f)
    end
    ns.ForeverMenuFont = function(fs, size) MenuFont(fs, size or MENU_FONT) end

    -- our boxes and dividers drawn over a menu's rows (blizzard's rows have only two
    -- textures: no room for a border). kept per menu, hidden with every restyle
    local decos = setmetatable({}, { __mode = "k" })
    local mine = setmetatable({}, { __mode = "k" })  -- our deco frames
    local function HideDecos(m)
        local d = decos[m]
        if not d then return end
        for _, t in ipairs(d.cleared) do t:SetAlpha(1) end
        wipe(d.cleared)
        if d.bg then d.bg:Hide() end
        for _, b in ipairs(d.boxes) do b:Hide() end
        for _, l in ipairs(d.lines) do l:Hide() end
        d.nb, d.nl = 0, 0
        if d.thumb then d.thumb:Hide() end
        if d.bar then d.bar:SetAlpha(1); d.bar = nil end
    end
    local function Decos(m)
        local d = decos[m]
        if not d then
            d = { boxes = {}, lines = {}, cleared = {}, nb = 0, nl = 0 }
            decos[m] = d
        end
        return d
    end
    local function BoxDeco(m)
        local d = Decos(m)
        d.nb = d.nb + 1
        local b = d.boxes[d.nb]
        if not b then
            b = CreateFrame("Frame", nil, m)
            mine[b] = true
            b:EnableMouse(false)
            b:SetSize(BOX, BOX)
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.12, 0.12, 0.12, 1)
            b.ring = EUI.MakeBorder(b, 0.25, 0.25, 0.25, 0.6, EUI.PanelPP)
            b.fill = b:CreateTexture(nil, "ARTWORK")
            b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
            b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
            d.boxes[d.nb] = b
        end
        return b
    end
    -- (blizzard's menu frames refuse CreateTexture: lines and fill sit on frames of ours)
    local function LineDeco(m)
        local d = Decos(m)
        d.nl = d.nl + 1
        local l = d.lines[d.nl]
        if not l then
            local f = CreateFrame("Frame", nil, m)
            mine[f] = true
            f:EnableMouse(false)
            l = f:CreateTexture(nil, "OVERLAY")
            l:SetAllPoints(f)
            l:SetColorTexture(1, 1, 1, 0.10)
            l = f
            d.lines[d.nl] = l
        end
        l:SetFrameLevel(m:GetFrameLevel() + 1)
        local es = m:GetEffectiveScale()
        l:SetHeight(((EUI.PP and EUI.PP.perfect) or 1) / ((es and es > 0) and es or 1))
        return l
    end

    -- a scrolling menu's rows start further in than a plain menu's: the plain
    -- menus' boxes are moved in to match (read from the first scrolling menu seen)
    local BoxInset
    do
        local scrollInset
        function BoxInset(row, m)
            local rl, ml = row:GetLeft(), m:GetLeft()
            if not (rl and ml) then return 0 end
            local inset = rl - ml
            local sb = m.ScrollBox
            if sb and sb:IsShown() then
                scrollInset = scrollInset or inset
                return 0
            end
            return math.max(0, (scrollInset or (inset + 4)) - inset)
        end
    end

    -- blizzard's divider (a tooltip divider texture, dark line on top): ours, one pixel
    local function StyleDivider(row, m)
        local d = Decos(m)
        for _, r in ipairs({ row:GetRegions() }) do
            if r:IsObjectType("Texture") and r:IsShown() and r:GetAlpha() > 0 then
                r:SetAlpha(0)
                d.cleared[#d.cleared + 1] = r
            end
        end
        local l = LineDeco(m)
        l:ClearAllPoints()
        l:SetPoint("LEFT", row, "LEFT", 2, 0)
        l:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        l:Show()
    end

    local function StyleRow(row, m)
        local fs = row.fontString
        if not (fs and fs.GetText) then return end
        local box, tick = row.leftTexture1, row.leftTexture2
        local text = fs:GetText() or ""
        if groupNames[text] then
            -- a section title: no box, text at the row's left
            if box then box:SetAlpha(0) end
            if tick then tick:SetAlpha(0) end
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", 1, 0)
            if ns.foreverDirsOpen then
                fs:SetTextColor(0.55, 0.55, 0.55, 1)
                return
            end
            -- the activity groups: yellow, a divider under each
            MenuFont(fs, MENU_FONT)
            fs:SetTextColor(1, 0.82, 0, 1)
            local l = LineDeco(m)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 2, 0)
            l:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", -2, 0)
            l:Show()
            return
        end
        if LFG_SELF_LISTING and text == LFG_SELF_LISTING then
            if box then box:SetAlpha(0) end
            if tick then tick:SetAlpha(0) end
            MenuFont(fs, MENU_FONT)
            fs:SetTextColor(1, 1, 1, 1)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", 1, 0)
            local l = LineDeco(m)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 2, 0)
            l:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", -2, 0)
            l:Show()
            return
        end
        if not box and not ns.foreverDirsOpen then
            -- a plain button elsewhere (a submenu's, as choose languages): the ticked rows' text
            MenuFont(fs, MENU_FONT)
            fs:SetTextColor(EUI.TEXT_DIM_R or 0.75, EUI.TEXT_DIM_G or 0.75, EUI.TEXT_DIM_B or 0.75, EUI.TEXT_DIM_A or 1)
            return
        end
        if not box then
            -- a plain button (directions): our font, yellow, grey while it can't be clicked
            MenuFont(fs, 10)
            if ns.foreverDirsOff[text] then
                fs:SetTextColor(0.4, 0.4, 0.4, 1)
            else
                fs:SetTextColor(1, 0.82, 0, 1)
            end
            return
        end
        -- blizzard's box and tick stay (they hold the layout and the ticked
        -- state), clear; ours is drawn over them: bordered, the accent filling it
        local on = tick and tick:IsShown() or false
        box:SetAlpha(0)
        box:SetSize(BOX, BOX)
        box:ClearAllPoints()
        box:SetPoint("LEFT", row, "LEFT", BoxInset(row, m), 0)
        if tick then tick:SetAlpha(0) end
        local b = BoxDeco(m)
        b:SetFrameLevel(row:GetFrameLevel() + 2)
        b:ClearAllPoints()
        b:SetAllPoints(box)
        local a = EUI.ELLESMERE_GREEN
        b.fill:SetColorTexture(a.r, a.g, a.b, 1)
        b.fill:SetShown(on)
        if on then b.ring:SetColor(a.r, a.g, a.b, 0.8) else b.ring:SetColor(0.25, 0.25, 0.25, 0.6) end
        b:Show()
        -- the single-group menu indents its activities; retail's rows don't
        local trimmed = text:gsub("^%s+", "")
        if trimmed ~= text then fs:SetText(trimmed) end
        MenuFont(fs, MENU_FONT)
        fs:SetTextColor(EUI.TEXT_DIM_R or 0.75, EUI.TEXT_DIM_G or 0.75, EUI.TEXT_DIM_B or 0.75, EUI.TEXT_DIM_A or 1)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", box, "RIGHT", 7, 0)
    end

    -- the rows are the menu's children, or (when it scrolls) inside the scroll box's row frames
    local function StyleChildren(parent, m)
        if not parent then return end
        for _, c in ipairs({ parent:GetChildren() }) do
            if c.fontString then
                if c:IsShown() then StyleRow(c, m) end
            elseif mine[c] or c == m.ScrollBox or c == m.ScrollBar then
                -- ours, or the scroll parts (their rows are styled from the scroll target)
            elseif c:IsShown() and c:GetNumChildren() == 0 and c:GetNumRegions() > 0 then
                StyleDivider(c, m)
            elseif c:IsShown() then
                local row = c:GetChildren()
                if row and row.fontString and row:IsShown() then StyleRow(row, m) end
            end
        end
    end
    -- retail's menu fill: the skin's window colour, near opaque
    local function MenuFill(m)
        local d = Decos(m)
        if not d.bg then
            d.bg = CreateFrame("Frame", nil, m)
            mine[d.bg] = true
            d.bg:EnableMouse(false)
            d.bg:SetAllPoints(m)
            d.bg.tex = d.bg:CreateTexture(nil, "BACKGROUND")
            d.bg.tex:SetAllPoints(d.bg)
        end
        d.bg:SetFrameLevel(m:GetFrameLevel())
        local S = WSkin()
        local T = S and S.Theme
        if T and T.bgR then d.bg.tex:SetColorTexture(T.bgR, T.bgG, T.bgB, 0.98)
        else d.bg.tex:SetColorTexture(0.08, 0.08, 0.08, 0.98) end
        d.bg:Show()
    end

    -- blizzard sizes a menu to its parent (the ui); retail's filters menu sits in
    -- the group finder window and takes its scale: ours do too. blizzard sets the
    -- scale again each time it hands the frame out, so nothing carries over
    local function MenuScale(m)
        local own = m:GetScale()
        local es = m:GetEffectiveScale()
        local want = BF and BF:GetEffectiveScale()
        if not (own and own > 0 and es and es > 0 and want and want > 0) then return end
        local k = want / (es / own)
        if math.abs(k - own) > 0.001 then m:SetScale(k) end
    end

    -- the menu a row gap (the top row's) clear of its dropdown. once each time
    -- blizzard places it
    local nudged = setmetatable({}, { __mode = "k" })
    local function MenuNudge(m)
        local point, rel, relPoint, x, y = m:GetPoint(1)
        if not (point and y) then return end
        if not tContains(Drops(), rel) then return end  -- submenus stay on their rows
        local rb = _G.LFGBrowseFrameRefreshButton
        local cat = _G.LFGBrowseFrameCategoryDropdown
        if rel == ns.foreverDirs and rb and cat then
            -- directions: the list's width, under the row and inside the window
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", cat, "BOTTOMLEFT", 0, -ROW_GAP)
            m:SetPoint("TOPRIGHT", rb, "BOTTOMRIGHT", 0, -ROW_GAP)
            return
        end
        local done = nudged[m]
        if done and math.abs(done - y) < 0.05 then return end
        local dy = -ROW_GAP
        if point:find("BOTTOM") then dy = -dy end  -- opened upwards: up off it
        y = y + dy
        m:SetPoint(point, rel, relPoint, x, y)
        nudged[m] = select(5, m:GetPoint(1)) or y
    end

    -- blizzard pads the menu's bottom more than its top: the bottom down to
    -- the top's. menus hanging down from our dropdown, not scrolling ones
    local function MenuTrim(m)
        local point = m:GetPoint(1)
        if not (point and point:find("TOP")) then return end
        if m.ScrollBox and m.ScrollBox:IsShown() then return end
        local mt, mb = m:GetTop(), m:GetBottom()
        if not (mt and mb) then return end
        local top, bottom
        for _, c in ipairs({ m:GetChildren() }) do
            if c.fontString and c:IsShown() then
                local t, b = c:GetTop(), c:GetBottom()
                if t and b then
                    top = math.max(top or t, t)
                    bottom = math.min(bottom or b, b)
                end
            end
        end
        if not (top and bottom) then return end
        local extra = (bottom - mb) - (mt - top)
        if extra > 1 then m:SetHeight(m:GetHeight() - extra) end
    end

    local function StyleMenu(m)
        if not m or m:IsForbidden() or not m:IsShown() then return end
        HideDecos(m)
        MenuScale(m)
        MenuNudge(m)
        MenuFill(m)
        StyleChildren(m, m)
        local st = m.ScrollBox and m.ScrollBox.GetScrollTarget and m.ScrollBox:GetScrollTarget()
        StyleChildren(st, m)
        MenuTrim(m)
        local d = Decos(m)
        local sb, bar = m.ScrollBox, m.ScrollBar
        if sb and bar and sb:IsShown() and sb.GetScrollPercentage then
            bar:SetAlpha(0)
            d.bar = bar
            if not d.thumb then
                d.thumb = CreateFrame("Frame", nil, m)
                mine[d.thumb] = true
                d.thumb:EnableMouse(false)
                d.thumb:SetWidth(3)
                local t = d.thumb:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints()
                t:SetColorTexture(1, 1, 1, 0.3)
            end
            d.thumb:SetFrameLevel(m:GetFrameLevel() + 5)
            local h = sb:GetHeight() or 0
            local vis = sb.GetVisibleExtentPercentage and sb:GetVisibleExtentPercentage() or 1
            if h > 0 and vis < 1 then
                local th = math.max(16, h * vis)
                d.thumb:SetHeight(th)
                d.thumb:ClearAllPoints()
                d.thumb:SetPoint("TOPLEFT", sb, "TOPRIGHT", math.floor((bar:GetWidth() or 8) / 2 - 1.5 + 0.5),
                    -(h - th) * (sb:GetScrollPercentage() or 0))
                d.thumb:Show()
            end
        end
        if m.ScrollBox and not d.scrollHooked then
            d.scrollHooked = true
            hooksecurefunc(m.ScrollBox, "Update", function()
                if OurMenuOpen() and ns.foreverRestyle then C_Timer.After(0, ns.foreverRestyle) end
            end)
        end
    end

    local function Restyle()
        if not OurMenuOpen() then
            -- blizzard reuses menu frames: never leave one clear or dressed
            for _, m in ipairs(menus) do m:SetAlpha(1); HideDecos(m) end
            wipe(menus)
            return
        end
        GroupNames()
        for i = #menus, 1, -1 do
            local m = menus[i]
            if m:IsShown() then StyleMenu(m); m:SetAlpha(1) else table.remove(menus, i) end
        end
    end
    ns.foreverRestyle = Restyle  -- for the scroll hook, set up above it

    -- blizzard's look shows for one frame before ours: the menu stays clear until restyled
    local function Veil(m)
        if m and not m:IsForbidden() then m:SetAlpha(0) end
    end

    local armed
    local function Soon()
        if armed then return end
        armed = true
        for _, m in ipairs(menus) do Veil(m) end
        C_Timer.After(0, function() armed = false; Restyle() end)
    end
    ns.foreverRestyleSoon = Soon

    local function MenuStyleOn()
        return ns.Enabled()
    end

    -- the menu frame a row sits in (its parent, or up past the scroll box)
    local function MenuOf(row)
        local p = row:GetParent()
        for _ = 1, 4 do
            if not p then return nil end
            if p.ScrollBox then return p end
            p = p:GetParent()
        end
    end
    local adopting
    function ns.ForeverAdoptMenu(row)
        if adopting or not MenuStyleOn() then return end
        adopting = true
        C_Timer.After(0, function()
            adopting = false
            local m = MenuOf(row)
            if not m or m:IsForbidden() then return end
            if not tContains(menus, m) then menus[#menus + 1] = m end
            Restyle()
        end)
    end

    function HookMenus()
        -- a closed menu leaves nothing of ours behind (each dropdown once, as it appears)
        local done = ns.foreverMenusHooked or {}
        for _, dd in ipairs(Drops()) do
            if dd.OnMenuClosed and not done[dd] then
                done[dd] = true
                hooksecurefunc(dd, "OnMenuClosed", function() C_Timer.After(0, Restyle) end)
            end
        end
        if ns.foreverMenusHooked then return end
        ns.foreverMenusHooked = done
        -- a menu (or one of its submenus) was drawn: note it, style it next frame
        local function OnGenerate(m)
            if not MenuStyleOn() then return end
            -- the dropdown may not count as open yet while its first menu draws: the cursor on it does
            local ours = OurMenuOpen() or OurMenuOpen(true)
            if not ours then HideDecos(m) return end  -- other menus never flicker
            Veil(m)
            C_Timer.After(0, function()
                if not OurMenuOpen() then m:SetAlpha(1); HideDecos(m) return end
                if not tContains(menus, m) then menus[#menus + 1] = m end
                Restyle()
            end)
        end
        for _, mixin in ipairs({ _G.MenuStyle1Mixin, _G.MenuStyle2Mixin }) do
            if mixin and type(mixin.Generate) == "function" then hooksecurefunc(mixin, "Generate", OnGenerate) end
        end
        -- a tick redraws the rows: style them again once blizzard's done
        local act = _G.LFGBrowseFrameActivityDropdown
        if act then
            if act.ValueToggleSelected then hooksecurefunc(act, "ValueToggleSelected", Soon) end
            if act.SetAllValuesForActivityGroup then hooksecurefunc(act, "SetAllValuesForActivityGroup", Soon) end
        end
    end
end

-------------------------------------------------------------------------------
--  the list self tab like the browser: its two dropdowns get our faces, the
--  comment box and bottom buttons the list's width, the glowing lines go and
--  blizzard's show all level ranges checkbox wears a cog box. blizzard's
--  controls stay on top, clear, and take every click
-------------------------------------------------------------------------------
local DressListing
do
    local LEVEL_ON = { r = 0.25, g = 0.85, b = 0.35 }  -- fixed: the accent may be grey

    local function HoldClear(t)
        t:SetAlpha(0)
        hooksecurefunc(t, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
    end

    local function LevelCog(av)
        local box = av.LevelRangesCheckbox
        local cb = box and box.Checkbox
        if not cb then return end
        if box.Text then HoldClear(box.Text) end
        HoldClear(cb)
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", av, "TOPLEFT", LIST_X + LIST_W - ROW1_H, -10)
        cb:SetSize(ROW1_H, ROW1_H)
        local b = CreateFrame("Button", nil, av)
        b:SetAllPoints(cb)
        b:SetFrameLevel(math.max(0, cb:GetFrameLevel() - 1))
        b:EnableMouse(false)
        b:SetText(" ")
        local S = WSkin()
        if S and S.Button then
            S.Button(b)
        else
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
            EUI.MakeBorder(b, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
        end
        local top = CreateFrame("Frame", nil, b)
        top:SetAllPoints()
        top:SetFrameLevel(b:GetFrameLevel() + 3)
        top:EnableMouse(false)
        -- our border over the skin's, green while on
        b.ring = EUI.MakeBorder(top, 1, 1, 1, 0, EUI.PanelPP)
        b.glyph = top:CreateTexture(nil, "OVERLAY")
        b.glyph:SetTexture(ICONS .. "cogs-3.png")
        b.glyph:SetSize(17, 17)
        b.glyph:SetPoint("CENTER")
        local function Paint()
            local on = cb:GetChecked() and true or false
            local g = LEVEL_ON
            if on then b.glyph:SetVertexColor(g.r, g.g, g.b) else b.glyph:SetVertexColor(0.78, 0.78, 0.78) end
            b.glyph:SetAlpha((on or b.hover) and 1 or 0.8)
            b.ring:SetColor(g.r, g.g, g.b, on and 1 or 0)
            if b.hover then b:LockHighlight() else b:UnlockHighlight() end
        end
        local function Tip()
            GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
            GameTooltip:SetText(LFG_LIST_IGNORE_SUGGESTED_LEVEL or "Show All Level Ranges", 1, 1, 1)
            GameTooltip:AddLine(EUI.L("Off: only dungeons for your level are listed and searched."), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(EUI.L("On: every dungeon is listed and searched, whatever your level."), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
        cb:HookScript("OnEnter", function() b.hover = true; Paint(); Tip() end)
        cb:HookScript("OnLeave", function() b.hover = nil; Paint(); GameTooltip:Hide() end)
        cb:HookScript("OnClick", Paint)
        cb:HookScript("OnShow", Paint)
        hooksecurefunc(cb, "SetChecked", Paint)
        Paint()
    end

    -- voice chat as a square by playstyle: blizzard's dropdown stays the button,
    -- clear, over our box, so its menu and the mode it posts stay blizzard's
    local GF_ICONS = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\"
    local function VoiceIcon(av, lf)
        local vc = av.VoiceChatDropdown
        if not vc then return end
        if av.VoiceChatLabel then HoldClear(av.VoiceChatLabel) end
        HoldClear(vc)
        vc:ClearAllPoints()
        vc:SetPoint("TOPLEFT", av, "TOPLEFT", LIST_X + LIST_W - ROW1_H * 2 - ROW_GAP, -10)
        vc:SetSize(ROW1_H, ROW1_H)
        local b = CreateFrame("Button", nil, av)
        b:SetAllPoints(vc)
        b:SetFrameLevel(math.max(0, vc:GetFrameLevel() - 1))
        b:EnableMouse(false)
        b:SetText(" ")
        local S = WSkin()
        if S and S.Button then
            S.Button(b)
        else
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
            EUI.MakeBorder(b, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
        end
        local top = CreateFrame("Frame", nil, b)
        top:SetAllPoints()
        top:SetFrameLevel(b:GetFrameLevel() + 3)
        top:EnableMouse(false)
        local glyph = top:CreateTexture(nil, "OVERLAY")
        glyph:SetSize(16, 16)
        glyph:SetPoint("CENTER")
        local hover
        local function Paint()
            local none = Enum.LFGEntryVoiceMode and Enum.LFGEntryVoiceMode.None
            local on = lf.voiceMode ~= nil and lf.voiceMode ~= none
            glyph:SetTexture(GF_ICONS .. (on and "eui-soundon.png" or "eui-soundoff.png"))
            glyph:SetVertexColor(on and 1 or 0.78, on and 1 or 0.78, on and 1 or 0.78)
            glyph:SetAlpha((on or hover) and 1 or 0.8)
            if hover then b:LockHighlight() else b:UnlockHighlight() end
        end
        vc:HookScript("OnEnter", function()
            hover = true; Paint()
            GameTooltip:SetOwner(vc, "ANCHOR_RIGHT")
            local label = av.VoiceChatLabel and av.VoiceChatLabel:GetText()
            GameTooltip:SetText(label and label:gsub(":%s*$", "") or VOICE_CHAT or "Voice Chat", 1, 1, 1)
            local mode = vc.Text and vc.Text:GetText()
            if mode and mode ~= "" then GameTooltip:AddLine(mode, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        vc:HookScript("OnLeave", function() hover = nil; Paint(); GameTooltip:Hide() end)
        -- the box goes where blizzard's dropdown goes
        vc:HookScript("OnShow", function() b:Show(); Paint() end)
        vc:HookScript("OnHide", function() b:Hide() end)
        b:SetShown(vc:IsShown())
        -- every pick and every reset of the mode ends in blizzard's selection update
        if vc.UpdateSelections then hooksecurefunc(vc, "UpdateSelections", Paint) end
        Paint()
    end

    local listingDressed
    function DressListing()
        if listingDressed or not ns.Enabled() then return end
        if InCombatLockdown() then
            if EUI.CombatQueue then EUI.CombatQueue.Defer("GroupFinderForeverListing", DressListing) end
            return
        end
        local lf = _G.LFGListingFrame
        local av = lf and lf.ActivityView
        if not av then return end
        listingDressed = true
        -- playstyle across the row, voice chat and the level ranges cog at its end
        local ps = av.PlayStyleDropdown
        if ps then
            ps:ClearAllPoints()
            ps:SetPoint("TOPLEFT", av, "TOPLEFT", LIST_X, -10)
            ps:SetSize(LIST_W - (ROW1_H + ROW_GAP) * 2, ROW1_H)
            Face(ps)
        end
        LevelCog(av)
        VoiceIcon(av, lf)
        -- the glowing lines over and under the dungeon list
        for _, t in ipairs({ av.BarTop, av.BarMiddle }) do
            if t then HoldClear(t) end
        end
        -- the comment box as wide as the list (blizzard only moves it); the
        -- skin's box sits 6px outside it, so the text is that far in
        local cmt = av.Comment
        if cmt then
            cmt:SetWidth(LIST_W - 12)
            if cmt.EditBox then cmt.EditBox:SetWidth(LIST_W - 12 - 18) end
        end
        -- back and list self as wide as the browser's two
        local back, post = lf.BackButton, lf.PostButton
        if back and post then
            back:ClearAllPoints()
            back:SetPoint("BOTTOM", lf, "BOTTOM", 0, 16)
            back:SetPoint("LEFT", av, "LEFT", LIST_X, 0)
            back:SetWidth(BTN_W)
            post:ClearAllPoints()
            post:SetPoint("BOTTOMLEFT", back, "BOTTOMRIGHT", LIST_W - BTN_W * 2, 0)
            post:SetWidth(BTN_W)
        end
        -- the comment box down to the buttons, the list's gap (less the skin's
        -- 5px box edge) above them. blizzard places it again on each show; the
        -- comment-only view (centred, taller) stays blizzard's
        if cmt and back then
            local function CommentDown()
                if av.commentRequired or InCombatLockdown() then return end
                local bt, ab = back:GetTop(), av:GetBottom()
                if not (bt and ab) then return end
                -- blizzard's top: 19 up, the voice row's 36, its own 47
                local top = 19 + (av.VoiceChatDropdown and 36 or 0) + 47
                cmt:ClearAllPoints()
                cmt:SetPoint("TOP", av, "BOTTOM", 0, top)
                cmt:SetPoint("BOTTOM", av, "BOTTOM", 0, bt - ab + LIST_GAP + 5)
            end
            av:HookScript("OnShow", CommentDown)
            if av:IsVisible() then CommentDown() end
        end
        HookMenus()
    end
end

-------------------------------------------------------------------------------
--  the window narrowed to the list with a margin each side. the list self tab's
--  category buttons and role picks and the who tab's search box shrink to fit.
--  with the module only (turning it off reloads)
-------------------------------------------------------------------------------
local MARGIN = 10  -- blizzard's list starts 7px in, ours 3 more
local WIN_W = MARGIN + LIST_W + 7 + MARGIN
local ROLE_SCALE = 0.85

-- the category buttons scaled to the narrower view and made taller: the picture
-- cropped to the button's shape instead of stretching
local FitCategories
do
    local TALL = 1.3
    local base = setmetatable({}, { __mode = "k" })    -- button: its own height, its picture's
    -- picture: its coords as blizzard set them (an atlas texture reads coords within the atlas)
    local coords = setmetatable({}, { __mode = "k" })
    local native = setmetatable({}, { __mode = "k" })  -- button: its picture's shape as blizzard draws it
    local want = setmetatable({}, { __mode = "k" })    -- button: the height we gave it

    local set = setmetatable({}, { __mode = "k" })     -- picture: the coords our crop last set

    -- the taller picture keeps blizzard's look: its sides cropped, centred.
    -- coords still showing our own crop (an atlas set again unchanged) aren't blizzard's
    local function Grab(ic)
        local ulx, uly, _, lly, urx = ic:GetTexCoord()
        local o = set[ic]
        if o and math.abs(o[1] - ulx) < 1e-4 and math.abs(o[2] - urx) < 1e-4
            and math.abs(o[3] - uly) < 1e-4 and math.abs(o[4] - lly) < 1e-4 then return end
        coords[ic] = { ulx, urx, uly, lly }
    end

    local ICON_INSET = 13  -- the picture's 8px top and 5px bottom inset

    -- the picture's height from the height we gave the button: read back right
    -- after setting it, the old height can come out and the crop with it
    local function Crop(b, bh)
        local ic, bb = b.Icon, base[b]
        local w = ic and ic:GetWidth() or 0
        -- the picture's shape from the cover's height, which never changes; measured only without one
        local na = (bb and bb.ih > 0 and w / bb.ih) or native[b]
        local c = ic and na and coords[ic]
        bh = bh or want[b]
        local h = bh and (bh - ICON_INSET) or (ic and ic:GetHeight()) or 0
        if not (c and w > 0 and h > 0) then return end
        local cut = (c[2] - c[1]) * (1 - math.min(1, (w / h) / na)) / 2
        local l, r = c[1] + cut, c[2] - cut
        ic:SetTexCoord(l, r, c[3], c[4])
        set[ic] = { l, r, c[3], c[4] }
    end

    local function Apply(b)
        local h = want[b]
        if h and math.abs((b:GetHeight() or 0) - h) > 0.5 then b:SetHeight(h) end
        Crop(b)
    end

    -- blizzard's layout has just sized the button to its art: the picture's shape, then ours
    local function AfterLayout(b)
        local ic = b.Icon
        local w, h = ic and ic:GetWidth() or 0, ic and ic:GetHeight() or 0
        if w > 0 and h > 1 then native[b] = w / h end
        -- a button blizzard made on this open had no width when we fitted: fit them now
        if not want[b] then FitCategories(b:GetParent()) return end
        Apply(b)
    end

    -- sized from the cover's atlas: the first button can be measured before blizzard lays it out
    local function Setup(b)
        local h = b.Cover and b.Cover:GetHeight()
        if not (h and h > ICON_INSET + 1) then return nil end
        local ic = b.Icon
        local bb = { h = h, ih = h - ICON_INSET }
        base[b] = bb
        -- already laid out by blizzard (its height is the cover's): the picture's shape now
        local iw, ih = ic and ic:GetWidth() or 0, ic and ic:GetHeight() or 0
        if iw > 0 and ih > 1 and math.abs((b:GetHeight() or 0) - h) < 1 then native[b] = iw / ih end
        -- blizzard's art stays where it is: the layout measures the button's width from it
        -- a hover border of ours around the picture
        local edge = CreateFrame("Frame", nil, b)
        edge:SetAllPoints(ic or b)
        edge:SetFrameLevel(b:GetFrameLevel() + 3)
        edge:EnableMouse(false)
        local a = EUI.ELLESMERE_GREEN
        EUI.MakeBorder(edge, a.r, a.g, a.b, 0.9, EUI.PanelPP)
        edge:Hide()
        b:HookScript("OnEnter", function() edge:Show() end)
        b:HookScript("OnLeave", function() edge:Hide() end)
        b:HookScript("OnHide", function() edge:Hide() end)
        if ic then
            Grab(ic)
            -- blizzard sets the atlas again each refresh: its coords, then our crop again
            hooksecurefunc(ic, "SetAtlas", function(self) Grab(self); Crop(b) end)
        end
        -- blizzard's layout sizes the button back to its art on show
        if b.Layout then hooksecurefunc(b, "Layout", AfterLayout) end
        -- whatever sizes it (blizzard, us, a late layout), the crop follows the size it ends at
        b:HookScript("OnSizeChanged", function(self, _, h) Crop(self, h) end)
        return bb
    end

    function FitCategories(view)
        local w = view and view.CategoryButtons and view:GetWidth()
        if not (w and w > 0) or InCombatLockdown() then return end
        local n = 0
        for _, b in ipairs(view.CategoryButtons) do
            if b:IsShown() then n = n + 1 end
        end
        -- each button's share of the view, under the first's 8px and the 4px gaps
        local room = n > 0 and ((view:GetHeight() or 0) - 8) / n - 4 or 0
        for _, b in ipairs(view.CategoryButtons) do
            local bw = b:GetWidth()
            local bb = base[b] or Setup(b)
            if bb and bw and bw > 0 then
                local sc = math.min(1, (w - 8) / bw)
                b:SetScale(sc)
                want[b] = math.max(bb.h, math.min(bb.h * TALL, room / sc))
                Apply(b)
            end
        end
    end
end

local function Narrow()
    local f = _G.LFGParentFrame
    if not f then return end
    f:SetWidth(WIN_W)
    local lf = _G.LFGListingFrame
    if lf then
        -- the three roles a little smaller, moved left of the new player button
        local solo, group = lf.SoloRoleButtons, lf.GroupRoleButtons
        if solo then
            solo:SetScale(ROLE_SCALE)
            solo:ClearAllPoints()
            solo:SetPoint("TOPLEFT", lf, "TOPLEFT", 14 / ROLE_SCALE, -46 / ROLE_SCALE)
        end
        if group then
            group:ClearAllPoints()
            group:SetPoint("TOPLEFT", lf, "TOPLEFT", 20, -41)
        end
        local view = lf.CategoryView
        if view then
            FitCategories(view)
            view:HookScript("OnShow", FitCategories)
        end
        if LFGListingCategorySelection_UpdateCategoryButtons then
            hooksecurefunc("LFGListingCategorySelection_UpdateCategoryButtons", FitCategories)
        end
    end
end

local function Build()
    if frame then return end
    BF = _G.LFGBrowseFrame
    if not (BF and BF.ScrollBox) then return end
    local sb = BF.ScrollBox
    frame = CreateFrame("Frame", nil, BF)
    -- retail's list: rows LIST_W wide, the thumb in the 7px past them
    frame:SetPoint("TOPLEFT", sb, "TOPLEFT", LIST_X, 0)
    frame:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", LIST_X, 0)
    frame:SetWidth(LIST_W + 7)
    frame:SetFrameLevel(sb:GetFrameLevel() + 10)
    frame:EnableMouse(true)  -- blizzard's faded rows never get clicks
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        scrollPx = scrollPx - delta * (ns.OwnListRowHeight() + GAP) * 2
        Paint()
    end)
    frame:SetScript("OnSizeChanged", function() Paint() end)
    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    body:SetWidth(LIST_W)
    body:SetClipsChildren(true)
    hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("TOP", body, "TOP", 0, -40)
    hint:SetWidth(LIST_W - 40)
    hint:SetText(EUI.L("Select a category"))
    hint:Hide()
    thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.3)
    if BF.SendMessageButton and BF.GroupInviteButton then
        whisperBtn = Cover(BF.SendMessageButton, SEND_MESSAGE or "Send Message", Whisper)
        inviteBtn = Cover(BF.GroupInviteButton, GROUP_INVITE or "Group Invite", Invite)
    end
    hooksecurefunc(sb, "SetAlpha", HoldHidden)
    -- blizzard's glowing lines over and under the list
    for _, t in ipairs({ BF.BarTop, BF.BarMiddle }) do
        if t then
            t:SetAlpha(0)
            hooksecurefunc(t, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
        end
    end
    if BF.ScrollBar then hooksecurefunc(BF.ScrollBar, "SetAlpha", HoldHidden) end
    -- blizzard's list rebuilt: a search came back, a filter changed, the window opened
    hooksecurefunc(BF, "UpdateResults", function() ns.ForeverRefresh() end)
    BF:HookScript("OnHide", function() ns.ForeverRefresh() end)
    flusher = CreateFrame("Frame")
    flusher:Hide()
    flusher:SetScript("OnUpdate", Flush)
    frame:SetScript("OnEvent", function(_, event, id)
        if event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
            if type(id) == "number" then dirty[id] = true end
            flusher:Show()
        else
            SyncButtons()
        end
    end)
end

-- ours while the browse tab shows and every result can be read; blizzard's otherwise
function ns.ForeverRefresh()
    if not frame then return end
    local now = ns.Enabled() and BF:IsVisible() and not ns.ForeverAnySecret()
    if now ~= active then
        active = now
        local a = active and 0 or 1
        guard = true
        BF.ScrollBox:SetAlpha(a)
        if BF.ScrollBar then BF.ScrollBar:SetAlpha(a) end
        if whisperBtn then
            BF.SendMessageButton:SetAlpha(a)
            BF.GroupInviteButton:SetAlpha(a)
        end
        guard = false
        frame:SetShown(active)
        if whisperBtn then
            whisperBtn:SetShown(active)
            inviteBtn:SetShown(active)
        end
        if active then
            frame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
            frame:RegisterEvent("GROUP_ROSTER_UPDATE")
        else
            frame:UnregisterAllEvents()
            if BF.NoResultsFound then BF.NoResultsFound:SetAlpha(1) end
            wipe(dirty)
            flusher:Hide()
            selected = nil
        end
    end
    if active then
        -- after the skin has dressed the window, so its arrow is there
        if not dressed then dressed = true; DressRows(); HookMenus(); DressListing() end
        Rows()
        Row2()
        Collect()
        Paint()
    end
end

-- runs once blizzard_groupfinder_vanillastyle has loaded
function ns.Forever_OnEnable()
    Build()
    if frame then Narrow() end
    local lf = _G.LFGListingFrame
    if lf then
        lf:HookScript("OnShow", function() C_Timer.After(0, DressListing) end)
        if lf:IsVisible() then C_Timer.After(0, DressListing) end
    end
    local who = _G.LFGWhoListFrame
    if who then
        who:HookScript("OnShow", function() ns.ForeverWho() end)
        if who:IsVisible() then ns.ForeverWho() end
    end
    ns.ForeverRefresh()
end
