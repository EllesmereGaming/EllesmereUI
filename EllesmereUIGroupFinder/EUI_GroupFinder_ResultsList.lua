if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResultsList.lua - our own premade results list
--  blizzard's list stays alive underneath, faded out. we only read the
--  results and draw the groups that pass the filters, no gaps.
--  own selection + sign up button, nothing written to blizzard's panel
--  (that's what tainted it before). secret results: we step aside.
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
local GFNS = ns
local EUI = EllesmereUI

local DUNGEONS, RAIDS = 2, 3
local DELVES = GROUP_FINDER_CATEGORY_ID_DELVES or 121
local QUESTS, CUSTOM = 1, GROUP_FINDER_CUSTOM_CATEGORY or 6
local X_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
local CANCEL_H = 18  -- smallest cancel square
local GAP = 2
local Secret = EllesmereUI.IsSecret
local function Readable(t) return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t)) end
-- eui's group finder skin is on; off, our rows and buttons take blizzard's look (a reload swaps, like the skin)
local function Skinned() return ns.SkinOn and ns.SkinOn() or false end

-- display settings, in the profile (EllesmereUIGroupFinder.lua)
local function DB() return ns.OwnListDB() end
-- bumped by every display change: the rows lay out again
local styleGen = 0
function ns.OwnListOn() return ns.Enabled() end
function ns.OwnListRowHeight() return tonumber(DB().rowHeight) or 50 end
-- text sizes
local SIZE_DEFAULTS = { titleSize = 12, nameSize = 10, lineSize = 10, scoreSize = 10 }
function ns.OwnListSize(k) return tonumber(DB()[k]) or SIZE_DEFAULTS[k] end
function ns.SetOwnListSize(k, v)
    DB()[k] = v
    styleGen = styleGen + 1
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end
-- display settings
local DISPLAY_DEFAULTS = { iconShape = "circle", borderTexture = "solid", borderSize = 1, missingIcons = "blizzard",
    raidRoleIcons = "ellesmere",
    appsFirst = true, signupClicks = "double", visibility = "hidden",
    lineDelisted = false, lineAccepted = false, lineCancelled = false, lineDeclined = false, delistedOpacity = 50 }
-- signed up was part of accepted: until it's set, it follows accepted's switch and color
local FOLLOWS = { lineSigned = "lineAccepted", color_lineSigned = "color_lineAccepted" }
function ns.OwnListGet(k)
    local v = DB()[k]
    if v == nil and FOLLOWS[k] then return ns.OwnListGet(FOLLOWS[k]) end
    if v == nil then return DISPLAY_DEFAULTS[k] end
    return v
end
-- user's border color, else the style's
function ns.OwnListBorderColor()
    local bc = ns.OwnListGet("borderColor")
    if type(bc) == "table" then return bc.r or 1, bc.g or 1, bc.b or 1 end
    local btex = ns.OwnListGet("borderTexture") or "solid"
    if btex ~= "solid" and ns.OwnListGet("iconShape") == "square" then
        local c = EUI.GetBorderStyleSelectDefaults(btex)
        return c.r, c.g, c.b
    end
    if ns.ThemeBorder then return ns.ThemeBorder() end
    return 1, 1, 1
end
function ns.SetOwnListValue(k, v)
    DB()[k] = v
    styleGen = styleGen + 1
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end

-- dungeons & raids background: the skin asks for this whenever it paints the
-- window, and gets nothing while group finder is off
EUI._ShellLooks = EUI._ShellLooks or {}
EUI._ShellLooks.lfg = function()
    if not ns.Enabled() then return nil end
    local d = DB()
    return d.windowBgColor, d.windowBgOpacity
end
-- no list rebuild, the color picker fires every frame while dragging
function ns.SetWindowLook(k, v)
    DB()[k] = v
    if EUI._WSkinRefreshStyles then EUI._WSkinRefreshStyles() end
end

local SP, frame, body, rows, shown = nil, nil, nil, {}, {}
local scrollPx = 0
local active = false
local guard = false
local lastClickID, lastClickTime, clickCount = nil, 0, 0
local selected  -- ours, blizzard's is never touched
local Paint  -- defined further down
local AnySecret  -- same
local signBtn
-- result updates wait here for one flush on the next frame (a hidden frame)
local dirty, fullDirty, flusher = {}, false, nil
-- ticks the signed-up timers, shown only while a row in view has one
local ticker
-- clicks to sign up, per setting
local CLICKS_NEEDED = { single = 1, double = 2, triple = 3 }

-- delisted-then-relisted counts as fresh, so you can apply again
local function AppStatus(id)
    local _, status, pending = C_LFGList.GetApplicationInfo(id)
    if Secret(status) or Secret(pending) then return nil, nil end
    if status == "declined_delisted" then
        local info = C_LFGList.GetSearchResultInfo(id)
        local delisted = Readable(info) and info.isDelisted
        if delisted == false then status = "none" end
    end
    return status, pending
end

-- when each pending application went in. blizzard hands back the time left
-- (applications time out after 5 min), so a reload still counts from the start
local APP_TIMEOUT = 300
local appliedAt = {}
local function SignedUpAt(id)
    local _, status, pending, left = C_LFGList.GetApplicationInfo(id)
    if Secret(status) or Secret(pending) or Secret(left) or status ~= "applied" then
        appliedAt[id] = nil
        return nil
    end
    if not appliedAt[id] then
        local gone = type(left) == "number" and math.max(0, APP_TIMEOUT - left) or 0
        appliedAt[id] = GetTime() - gone
    end
    return appliedAt[id]
end
-- time left before the application times out, like blizzard's
local function TimeLeft(at)
    local s = math.max(0, APP_TIMEOUT - math.floor(GetTime() - at))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- a friend or guildmate in the group: blizzard's blue name (once per row paint: no table)
local function FriendColor(info)
    local bn, char, guild = info.numBNetFriends, info.numCharFriends, info.numGuildMates
    if Secret(bn) or Secret(char) or Secret(guild) then return nil end
    if (tonumber(bn) or 0) + (tonumber(char) or 0) + (tonumber(guild) or 0) > 0 and BATTLENET_FONT_COLOR then
        return BATTLENET_FONT_COLOR:GetRGB()
    end
end

-- blizzard's row check, plus the relisted case
local function Selectable(id)
    local status, pending = AppStatus(id)
    if status ~= "none" or pending then return false end
    local info = C_LFGList.GetSearchResultInfo(id)
    if not Readable(info) then return false end
    local delisted = info.isDelisted
    return not Secret(delisted) and not delisted
end

-- blizzard's sign up checks, read-only. returns ok, why not
local function SignUpState(id)
    local msg = LFGListUtil_GetActiveQueueMessage and LFGListUtil_GetActiveQueueMessage(true)
    if msg then return false, msg end
    if LFGListUtil_IsAppEmpowered and not LFGListUtil_IsAppEmpowered() then
        return false, LFG_LIST_APP_UNEMPOWERED
    end
    if IsInGroup(LE_PARTY_CATEGORY_HOME) and C_LFGList.IsCurrentlyApplying and C_LFGList.IsCurrentlyApplying() then
        return false, LFG_LIST_APP_CURRENTLY_APPLYING
    end
    local _, act = C_LFGList.GetNumApplications()
    local max = MAX_LFG_LIST_APPLICATIONS or 5
    if type(act) == "number" and act >= max then
        return false, LFG_LIST_HIT_MAX_APPLICATIONS and string.format(LFG_LIST_HIT_MAX_APPLICATIONS, max)
    end
    if GetNumGroupMembers(LE_PARTY_CATEGORY_HOME) > (MAX_PARTY_MEMBERS or 4) + 1 then return false, LFG_LIST_MAX_MEMBERS end
    local t, h, d = C_LFGList.GetAvailableRoles()
    if not (t or h or d) then return false, LFG_LIST_MUST_CHOOSE_SPEC end
    if GroupHasOfflineMember and GroupHasOfflineMember(LE_PARTY_CATEGORY_HOME) then return false, LFG_LIST_OFFLINE_MEMBER end
    if not id then return false, LFG_LIST_SELECT_A_SEARCH_RESULT end
    if not Selectable(id) then return false end
    return true
end

-- opens blizzard's sign up dialog directly
local function SignUp(id)
    if not (id and SignUpState(id)) then return end
    local dlg = LFGListApplicationDialog
    if not (LFGListApplicationDialog_Show and dlg) then return end
    LFGListApplicationDialog_Show(dlg, id)
    -- quick signup: auto confirm unless shift (if the core helper
    -- already did it, the dialog's gone)
    if EllesmereUIDB and EllesmereUIDB.quickSignup and not IsShiftKeyDown()
        and dlg:IsShown() and dlg.SignUpButton and dlg.SignUpButton:IsEnabled() then
        dlg.SignUpButton:Click()
    end
end

local function PaintSignBtn()
    if not signBtn then return end
    local ok, why = SignUpState(selected)
    signBtn:SetEnabled(ok)
    signBtn.why = (not ok) and why or nil
end
-- first-seen order, so applied groups can stay put
local posOf, nextPos = {}, 0
local function Pos(id)
    if not posOf[id] then nextPos = nextPos + 1; posOf[id] = nextPos end
    return posOf[id]
end
local function ByPos(a, b) return Pos(a) < Pos(b) end

local function Accent()
    local a = EUI.ELLESMERE_GREEN
    if a then return a.r, a.g, a.b end
    return 0.05, 0.82, 0.62
end

-------------------------------------------------------------------------------
--  which groups show
-------------------------------------------------------------------------------
-- dimmed mode keeps filtered groups, faded
local dimmed = {}
-- kept from the last collect: applications, each listed group's filter pass
-- (a result update is checked against it) and the sort's values
local seen, isApp, passOf, sortVal = {}, {}, {}, {}
local noteOf, tops = {}, {}  -- shown groups with a note, each shown row's top

-- the group's note when notes are on and it has one
local function NoteText(info)
    if not ns.OwnListGet("groupNotes") or not Readable(info) then return nil end
    local c = info.comment
    if type(c) ~= "string" or Secret(c) or c == "" then return nil end
    return c
end
-- the note's line under the row
local function NoteHeight() return ns.OwnListSize("lineSize") + 4 end
local sortDown, sortAppsFirst = false, true
local function BySortVal(a, b)
    if sortAppsFirst and isApp[a] ~= isApp[b] then return isApp[a] == true end
    local va, vb = sortVal[a], sortVal[b]
    if va ~= vb then
        if sortDown then return va > vb end
        return va < vb
    end
    return Pos(a) < Pos(b)
end
local function Collect()
    wipe(shown)
    wipe(dimmed)
    wipe(seen)
    wipe(isApp)
    wipe(passOf)
    local dim = ns.OwnListGet("visibility") == "dimmed"
    local res = SP and SP.results
    if type(res) ~= "table" then return end
    local appsFirst = ns.OwnListGet("appsFirst") ~= false
    for _, id in ipairs(res) do if not Secret(id) then Pos(id) end end
    local apps = C_LFGList.GetApplications() or {}
    for _, id in ipairs(apps) do
        if not Secret(id) then isApp[id] = true end
    end
    if appsFirst then
        for _, id in ipairs(apps) do
            if not Secret(id) and not seen[id] then
                seen[id] = true
                shown[#shown + 1] = id
            end
        end
    end
    for _, id in ipairs(res) do
        if not Secret(id) and not seen[id] then
            seen[id] = true
            local pass = (isApp[id] or not GFNS.ExtraPasses or GFNS.ExtraPasses(id)) and true or false
            passOf[id] = pass
            if pass then
                shown[#shown + 1] = id
            elseif dim then
                dimmed[id] = true
                shown[#shown + 1] = id
            end
        end
    end
    if not appsFirst then
        -- old applications, then back in original order
        for _, id in ipairs(apps) do
            if not Secret(id) and not seen[id] then
                seen[id] = true
                shown[#shown + 1] = id
            end
        end
        table.sort(shown, ByPos)
    end
    -- sort by score or size, applications stay on top
    local gc = GFNS.Cfg and GFNS.Cfg()
    local by = gc and gc.extraSortBy
    local field = (by == "high" or by == "low") and "leaderOverallDungeonScore"
        or (by == "big" or by == "small") and "numMembers"
    if field then
        sortDown, sortAppsFirst = by == "high" or by == "big", appsFirst
        wipe(sortVal)
        for _, id in ipairs(shown) do
            local info = C_LFGList.GetSearchResultInfo(id)
            local v = Readable(info) and info[field]
            sortVal[id] = (type(v) == "number" and not Secret(v)) and v or 0
        end
        table.sort(shown, BySortVal)
    end
    wipe(noteOf)
    if ns.OwnListGet("groupNotes") then
        for _, id in ipairs(shown) do
            if NoteText(C_LFGList.GetSearchResultInfo(id)) then noteOf[id] = true end
        end
    end
end

-------------------------------------------------------------------------------
--  right-click menu
-------------------------------------------------------------------------------
-- a player link in chat: clicking it is blizzard's own whisper, so nothing of ours
-- touches the chat box (opening it from here taints the chat type)
local function WhisperLeader(leader)
    local name = EUI.BuildFullName(leader) or leader
    local frame = DEFAULT_CHAT_FRAME
    if not (name and frame) then return end
    local link = "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
    frame:AddMessage(EllesmereUI.Lf("Click to whisper the group leader: %1$s", link), 1, 0.82, 0)
end

-- blizzard's menu under blizzard's tag, so other add-ons' entries (raider.io's
-- copy link and so on) still show. the owner is our row, which has resultID
-- like blizzard's does
local function TaggedMenu(anchor, id, info, leader)
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:SetTag("MENU_LFG_FRAME_SEARCH_ENTRY")
        -- a hidden flag is never tested: the title shows the name, as the row does
        local censored = info.censored
        if Secret(censored) then censored = nil end
        root:CreateTitle(censored and CENSORED_LFG_GROUP_NAME or info.name or "")
        local w = root:CreateButton(WHISPER_LEADER or "Whisper Leader", function() WhisperLeader(leader) end)
        if leader then
            w:SetTooltip(function(tip)
                GameTooltip_AddNormalLine(tip, EllesmereUI.L("Prompts in chat to whisper the party leader."))
            end)
        else
            w:SetEnabled(false)
            w:SetTooltip(function(tip)
                GameTooltip_SetTitle(tip, WHISPER or "Whisper")
                GameTooltip_AddNormalLine(tip, LFG_LIST_MUST_SIGN_UP_TO_WHISPER or "Sign up to whisper the leader")
            end)
        end
        root:CreateButton(LFG_LIST_REPORT_GROUP_FOR or "Report Group", function() LFGList_ReportListing(id, leader) end)
        root:CreateButton(REPORT_GROUP_FINDER_ADVERTISEMENT or "Report Advertisement",
            function() LFGList_ReportAdvertisement(id) end)
    end)
end

function ns.OwnListMenu(anchor, id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not Readable(info) then return end
    local leader = info.leaderName
    if Secret(leader) then leader = nil end
    TaggedMenu(anchor, id, info, leader)
end

-------------------------------------------------------------------------------
--  a row
-------------------------------------------------------------------------------
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
-- members, tanks first
local function ByRole(a, b)
    local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
    if ra ~= rb then return ra < rb end
    return a.k < b.k
end
-- raid role colors
local RR_ROLES = { "TANK", "HEALER", "DAMAGER" }
local RR_COLORS = { TANK = { 0.16, 0.38, 0.78 }, HEALER = { 0.16, 0.62, 0.24 }, DAMAGER = { 0.72, 0.16, 0.16 } }
ns.RaidRoleColors = RR_COLORS
local NEED_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps" }
-- blizzard's raid role circles, gold ring included
local BLIZZ_RR_ATLAS = { TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps" }
local BLIZZ_RR_SCALE = 1.22  -- art size over its visible ring
-- a delisted group's text colour: the delisted row highlight colour, set on each paint
local DR, DG, DB = 0x5B / 255, 0x5B / 255, 0x5B / 255
local REMAINING = { TANK = "TANK_REMAINING", HEALER = "HEALER_REMAINING", DAMAGER = "DAMAGER_REMAINING" }
local PERSON_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-person.png"
local PLAYERS_COLOR = { 0.4, 0.4, 0.42 }
-- a count circle's border, the same as the member icons get (ring when round,
-- border style when square)
local function CircleEdge(p, round, px, cr, cg, cb, tex, key)
    p.ring:Hide()
    p.edge:Hide()
    if px <= 0 then return end
    if round then
        p.ring:ClearAllPoints()
        p.ring:SetPoint("TOPLEFT", p.bg, "TOPLEFT", -px, px)
        p.ring:SetPoint("BOTTOMRIGHT", p.bg, "BOTTOMRIGHT", px, -px)
        p.ring:SetColorTexture(cr, cg, cb, 1)
        p.ring:Show()
    else
        if p.edge._key ~= key then
            p.edge._key = key
            EUI.ApplyBorderStyle(p.edge, px, cr, cg, cb, 1, tex)
        end
        p.edge:Show()
    end
end
-- the right side follows the activity's display type, as blizzard's rows do:
-- member icons, role counts, a player count, or nothing
local function MemberMode(ai, cap)
    local DT = Enum.LFGListDisplayType
    local dt = ai and ai.displayType
    if DT and type(dt) == "number" and not Secret(dt) then
        if dt == DT.RoleEnumerate or dt == DT.ClassEnumerate then return cap <= 5 and "icons" or "counts" end
        if dt == DT.RoleCount then return "counts" end
        if dt == DT.PlayerCount then return "players" end
        -- HideAll, and a type blizzard's rows do not draw (its newer Comment): nothing
        return nil
    end
    return cap > 5 and "counts" or "icons"
end
-- status text + colors
local G, R, Y = { 0.1, 1, 0.1 }, { 1, 0.25, 0.25 }, { 1, 0.82, 0 }
-- blizzard's strings have color codes baked in, strip them
local function Plain(t) return t and (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- blizzard has no delisted or failed string (its list shows Declined / Cancelled), so the fallback
-- goes through L
local function St(text, fallback, c) return { Plain(text) or EllesmereUI.L(fallback), c[1], c[2], c[3] } end
local STATUS = {
    applied           = St(LFG_LIST_PENDING, "Pending", G),
    invited           = St(LFG_LIST_APP_INVITED, "Invited", G),
    inviteaccepted    = St(LFG_LIST_APP_INVITE_ACCEPTED, "Invite Accepted", G),
    invitedeclined    = St(LFG_LIST_APP_INVITE_DECLINED, "Invite Declined", R),
    declined          = St(LFG_LIST_APP_DECLINED, "Declined", R),
    declined_full     = St(LFG_LIST_APP_FULL, "Full", R),
    declined_delisted = St(LFG_LIST_APP_DELISTED, "Delisted", R),
    timedout          = St(LFG_LIST_APP_TIMED_OUT, "Timed Out", R),
    cancelled         = St(LFG_LIST_APP_CANCELLED, "Cancelled", Y),
    failed            = St(LFG_LIST_APP_FAILED, "Failed", R),
}
-- underline setting + color per status
-- each status: its switch, its own color and the key of the user's color
local LINE_DELISTED  = { "lineDelisted", 0x5B / 255, 0x5B / 255, 0x5B / 255, "color_lineDelisted" }
local LINE_SIGNED    = { "lineSigned", 0.1, 0.9, 0.1, "color_lineSigned" }
local LINE_ACCEPTED  = { "lineAccepted", 0.1, 0.9, 0.1, "color_lineAccepted" }
local LINE_CANCELLED = { "lineCancelled", 1, 0.55, 0.1, "color_lineCancelled" }
local LINE_DECLINED  = { "lineDeclined", 1, 0.2, 0.2, "color_lineDeclined" }
-- by switch, for the settings page's color pickers
ns.STATUS_LINES = { lineDelisted = LINE_DELISTED, lineSigned = LINE_SIGNED, lineAccepted = LINE_ACCEPTED,
    lineCancelled = LINE_CANCELLED, lineDeclined = LINE_DECLINED }
-- a status's color: the user's, else its own
local function StatusColor(line)
    local c = ns.OwnListGet(line[5])
    if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end
    return line[2], line[3], line[4]
end
local LINE_OF = {
    [STATUS.declined_delisted] = LINE_DELISTED,
    [STATUS.applied] = LINE_SIGNED, [STATUS.invited] = LINE_ACCEPTED, [STATUS.inviteaccepted] = LINE_ACCEPTED,
    [STATUS.cancelled] = LINE_CANCELLED,
    [STATUS.declined] = LINE_DECLINED, [STATUS.declined_full] = LINE_DECLINED, [STATUS.timedout] = LINE_DECLINED,
    [STATUS.invitedeclined] = LINE_DECLINED, [STATUS.failed] = LINE_DECLINED,
}

-- parent: the settings preview's, else the list's (only the list's go in rows)
local function MakeRow(i, parent)
    local r = CreateFrame("Button", nil, parent or body)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local stock = not Skinned()
    r.stock = stock
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, stock and 0.04 or 0.03)
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetAllPoints()
    if stock then
        r.sel:SetAtlas("groupfinder-highlightbar-yellow")
        r.sel:SetBlendMode("ADD")
        r.sel:Hide()
    end
    -- status underline
    r.under = r:CreateTexture(nil, "ARTWORK", nil, 7)
    r.under:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.under:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.under:SetHeight(2)
    r.under:Hide()
    -- status highlight across the row, under the selection
    r.stat = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.stat:SetAllPoints()
    r.stat:Hide()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    if stock then
        r.hl:SetAtlas("groupfinder-highlightbar-blue")
        r.hl:SetBlendMode("ADD")
    else
        r.hl:SetColorTexture(1, 1, 1, 0.06)
    end
    -- the row without its note: icons and counts centre on it
    r.mid = r:CreateTexture(nil, "BACKGROUND")
    r.mid:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.mid:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    -- the group's note, one line under the row
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.note:SetJustifyH("LEFT")
    r.note:SetWordWrap(false)
    r.note:SetMaxLines(1)
    r.note:Hide()
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.act = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.act:SetJustifyH("LEFT")
    r.act:SetWordWrap(false)
    -- short dungeon name before the title
    r.short = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.short:Hide()
    -- line three bits
    r.sep1 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sep1:SetText("||")
    r.style = r:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    r.sep2 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sep2:SetText("||")
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.flag = r:CreateTexture(nil, "OVERLAY")
    r.flag:SetSize(13, 10)
    r.sep3 = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sep3:SetText("||")
    r.timer = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- kept for every paint of this row: line three's parts, the sized ones,
    -- the line layout, the members and the open roles
    r.line3 = { r.sep1, r.style, r.sep2, r.tag, r.flag, r.sep3, r.timer }
    r.lineFS = { r.sep1, r.style, r.sep2, r.tag, r.sep3, r.timer }
    r.lineH, r.lineY = {}, {}
    r.members, r.mpool, r.needs = {}, {}, {}
    -- cancel button
    if stock then
        -- blizzard's red x button
        r.cancel = CreateFrame("Button", nil, r, "UIMenuButtonStretchTemplate")
        r.cancel.tex = r.cancel:CreateTexture(nil, "ARTWORK")
        r.cancel.tex:SetAtlas("groupfinder-icon-redx")
        r.cancel.tex:SetPoint("CENTER")
        r.cancel:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        -- the template's highlight is inset and cropped; the whole glow, on the whole button
        local hl = r.cancel:GetHighlightTexture()
        if hl then
            hl:ClearAllPoints()
            hl:SetAllPoints()
            hl:SetTexCoord(0, 1, 0, 1)
        end
    else
        r.cancel = CreateFrame("Button", nil, r)
        r.cancel.bg = r.cancel:CreateTexture(nil, "BACKGROUND")
        r.cancel.bg:SetAllPoints()
        r.cancel.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        r.cancel.edge = EUI.MakeBorder(r.cancel, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
        r.cancel.tex = r.cancel:CreateTexture(nil, "OVERLAY")
        r.cancel.tex:SetTexture(X_TEX)
        r.cancel.tex:SetPoint("CENTER")
        r.cancel.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
    end
    r.cancel:SetScript("OnEnter", function(self)
        if not stock then
            self.tex:SetVertexColor(1, 0.3, 0.3, 1)
            if self.edge and self.edge.SetColor then self.edge:SetColor(1, 0.3, 0.3, 1) end
        end
        EUI.ShowWidgetTooltip(self, CANCEL_SIGN_UP or "Cancel Sign Up")
    end)
    r.cancel:SetScript("OnLeave", function(self)
        if not stock then
            self.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
            if self.edge and self.edge.SetColor then self.edge:SetColor(0.25, 0.25, 0.25, 1) end
        end
        EUI.HideWidgetTooltip()
    end)
    r.cancel:SetScript("OnClick", function(self)
        if self:GetParent().preview then return end
        local id = self:GetParent().resultID
        if id and not Secret(id) then C_LFGList.CancelApplication(id) end
    end)
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.status:SetJustifyH("RIGHT")
    r.score = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.score:SetJustifyH("RIGHT")
    r.icons, r.crowns, r.rings, r.roles = {}, {}, {}, {}
    for k = 1, 5 do
        local t = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.icons[k] = t
        -- ring behind round spec icons
        local ring = r:CreateTexture(nil, "ARTWORK", nil, 1)
        ring:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
        ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
        ring:Hide()
        r.rings[k] = ring
        local m1 = r:CreateMaskTexture()
        m1:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m1:SetAllPoints(ring)
        ring:AddMaskTexture(m1)
        local m2 = r:CreateMaskTexture()
        m2:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m2:SetAllPoints(t)
        r.masks = r.masks or {}
        r.masks[k] = m2
        -- role mark on top
        local role = r:CreateTexture(nil, "ARTWORK", nil, 3)
        role:SetPoint("CENTER", t)
        role:Hide()
        r.roles[k] = role
        -- holds the square border
        local bf = CreateFrame("Frame", nil, r)
        bf:SetAllPoints(t)
        bf:EnableMouse(false)
        bf:Hide()
        r.borders = r.borders or {}
        r.borders[k] = bf
        -- leader crown
        local c = r:CreateTexture(nil, "OVERLAY")
        c:SetAtlas("groupfinder-icon-leader")
        c:SetPoint("BOTTOM", t, "TOP", 0, 2)
        c:Hide()
        r.crowns[k] = c
    end
    -- raid role counts, and a 4th circle for a player count
    r.rr = {}
    for k = 1, 4 do
        local bg = r:CreateTexture(nil, "ARTWORK", nil, 1)
        local mask = r:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(bg)
        local t = r:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetPoint("CENTER", bg)
        local c = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c:SetJustifyH("CENTER")
        -- the member icons' borders: a ring behind round ones, a border frame on square ones
        local ring = r:CreateTexture(nil, "ARTWORK", nil, 0)
        local rm = r:CreateMaskTexture()
        rm:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        rm:SetAllPoints(ring)
        ring:AddMaskTexture(rm)
        local edge = CreateFrame("Frame", nil, r)
        edge:SetAllPoints(bg)
        edge:EnableMouse(false)
        bg:Hide(); t:Hide(); c:Hide(); ring:Hide(); edge:Hide()
        r.rr[k] = { bg = bg, mask = mask, icon = t, count = c, ring = ring, edge = edge }
    end
    -- row art
    r.art = r:CreateTexture(nil, "BACKGROUND", nil, 7)
    if ns.ROW_ART then
        r.art:SetAlpha(ns.ROW_ART.alpha)
        local m = r:CreateMaskTexture()
        m:SetTexture(ns.ROW_ART.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(r.art)
        r.art:AddMaskTexture(m)
    end
    r.art:Hide()
    r:SetScript("OnClick", function(self, button)
        if self.preview then return end
        local id = self.resultID
        if not id or not active then return end
        if button == "RightButton" then return ns.OwnListMenu(self, id) end
        local now = GetTime()
        if lastClickID == id and (now - lastClickTime) < 0.4 then clickCount = clickCount + 1 else clickCount = 1 end
        lastClickID, lastClickTime = id, now
        local need = CLICKS_NEEDED[ns.OwnListGet("signupClicks")] or 2
        local signup = EllesmereUIDB and EllesmereUIDB.quickSignup and clickCount >= need
        -- at the app limit, cancel the oldest
        if ns.GFCancelOldest then ns.GFCancelOldest(id) end
        -- same check blizzard's row click does
        if not Selectable(id) then return end
        if selected ~= id then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            selected = id
            Paint()
        end
        if signup and SignUpState(id) then
            lastClickID, clickCount = nil, 0
            SignUp(id)
        end
    end)
    r:SetScript("OnEnter", function(self)
        if self.preview then
            if ns.OwnListPreviewTip then ns.OwnListPreviewTip(self) end
            return
        end
        if not self.resultID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 25, 0)
        LFGListUtil_SetSearchEntryTooltip(GameTooltip, self.resultID)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    if i then rows[i] = r end
    return r
end

local function SetSize(fs, size)
    local ok, path, _, flags = pcall(fs.GetFont, fs)
    if ok and path then fs:SetFont(path, size, flags or "") end
end

-- a count circle's number: above it, or on it (its symbol hidden) when the row
-- is too short for a line above. the width its slot takes
local function PlaceCount(p, num, isz, fsz, inside)
    -- on the circle the number shrinks to fit inside it
    SetSize(p.count, inside and math.min(fsz, math.max(6, math.floor(isz * 0.7 + 0.5))) or fsz)
    p.count:SetText(num)
    p.count:ClearAllPoints()
    -- a box even on both sides of the circle, the text centred in it
    if inside then
        p.icon:Hide()
        p.count:SetPoint("LEFT", p.bg, "LEFT", -isz, 0)
        p.count:SetPoint("RIGHT", p.bg, "RIGHT", isz, 0)
    else
        p.icon:Show()
        p.count:SetPoint("BOTTOMLEFT", p.bg, "TOPLEFT", -isz, 1)
        p.count:SetPoint("BOTTOMRIGHT", p.bg, "TOPRIGHT", isz, 1)
    end
    p.count:Show()
    if inside then return isz end
    return math.max(isz, math.ceil(p.count:GetStringWidth() or 8))
end

-- Texts that show other players' writing (group titles here, applicant names
-- and notes in the applicant list) take a font family: Cyrillic, Korean and
-- Chinese letters draw in the client's own faces. Face and outline are the
-- string's template's, read once before its first switch and kept here (a
-- string on a family is never read back); the templates' drop shadow rides the
-- family. Every font write to such a string goes through here.
local famFace, famFlags = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
function ns.OwnListNameFont(fs, size)
    local face = famFace[fs]
    if not face then
        local ok, path, _, flags = pcall(fs.GetFont, fs)
        if not (ok and path) then return end
        face = path
        famFace[fs], famFlags[fs] = path, flags or ""
    end
    EUI.SetFontFamily(fs, face, size, famFlags[fs], true)
end

local function IconSize(h)
    -- 16px at 100%, 1px per 5%
    local c = GFNS.Cfg and GFNS.Cfg()
    local pct = tonumber(c and c.iconSize) or (GFNS.DEFAULTS and GFNS.DEFAULTS.iconSize) or 125
    return math.max(8, math.min(h - 4, 16 + math.floor((pct - 100) / 5 + 0.5)))
end

ns.OwnListIconSize = IconSize

-- a row's layout: again only for a new row height or a display change (styleGen)
local function Layout(r, h)
    if r.layH == h and r.layGen == styleGen then return end
    r.layH, r.layGen = h, styleGen
    r.mid:SetHeight(h)
    local pad = 6
    local tS, nS, lS = ns.OwnListSize("titleSize"), ns.OwnListSize("nameSize"), ns.OwnListSize("lineSize")
    ns.OwnListNameFont(r.name, tS)
    SetSize(r.act, nS)
    local sized = r.lineFS
    for i = 1, #sized do SetSize(sized[i], lS) end
    ns.OwnListNameFont(r.note, lS)
    -- title always fits, then the dungeon, then line three
    local room = h - 4
    local lines = r.lineH
    wipe(lines)
    lines[1] = tS + 2
    if room >= tS + nS + 6 then lines[2] = nS + 2 end
    local gc = GFNS.Cfg and GFNS.Cfg()
    local third = not (gc and gc.extraShowPlaystyle == false)
        or (gc and gc.extraRegionTags ~= false and ns.RegionList() ~= nil)
    if lines[2] and third and room >= tS + nS + lS + 10 then lines[3] = lS + 2 end
    local total = 0
    for i = 1, #lines do total = total + lines[i] end
    total = total + (#lines - 1) * 2
    local y = math.floor((h - total) / 2)
    local lineY = r.lineY
    wipe(lineY)
    for i = 1, #lines do
        lineY[i] = y
        y = y + lines[i] + 2
    end
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", pad, -r.lineY[1])
    r.act:ClearAllPoints()
    if lines[2] then
        r.act:SetPoint("TOPLEFT", r, "TOPLEFT", pad, -r.lineY[2])
        r.act:Show()
    else
        r.act:Hide()
    end
    r.lines = #lines
    r.pad = pad

    local isz = IconSize(h)
    local bpx = tonumber(ns.OwnListGet("borderSize")) or 0
    local gap = 2 + ((ns.OwnListGet("iconShape") ~= "square") and bpx * 2 or 0)  -- room for rings
    local cw = math.max(8, math.floor(isz * 0.6 + 0.5))
    -- cancel square left of the text, about two lines tall (placed in fill)
    local cs = math.max(CANCEL_H, math.min(h - 8, tS + nS + 6))
    r.cancel:SetSize(cs, cs)
    local xs = math.floor(cs * (r.stock and 0.6 or 0.45) + 0.5)
    r.cancel.tex:SetSize(xs, xs)
    r.cancelSize = cs
    r.cancel:SetFrameLevel(r:GetFrameLevel() + 5)
    SetSize(r.score, ns.OwnListSize("scoreSize"))
    local x = -pad - ((ns.OwnListGet("iconShape") ~= "square") and bpx or 0)
    for k = 5, 1, -1 do
        local t = r.icons[k]
        t:SetSize(isz, isz)
        r.roles[k]:SetSize(math.floor(isz * 0.7 + 0.5), math.floor(isz * 0.7 + 0.5))
        r.crowns[k]:SetSize(cw, math.floor(cw * 0.6 + 0.5))
        t:ClearAllPoints()
        t:SetPoint("RIGHT", r.mid, "RIGHT", x, 0)
        x = x - isz - gap
    end
    r.scoreX = x - 4  -- a raid's role counts move the score; the next group puts it back
    r.scoreRaid = nil
    r.score:ClearAllPoints()
    r.score:SetPoint("RIGHT", r.mid, "RIGHT", r.scoreX, 0)
    r.status:ClearAllPoints()
    r.status:SetPoint("RIGHT", r.score, "LEFT", -8, 0)
    r.name:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
    r.act:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
end

-- line three's next part, after the one placed before it (r.l3prev)
local function Put(r, p, gap)
    p:ClearAllPoints()
    local prev = r.l3prev
    if prev then p:SetPoint("LEFT", prev, "RIGHT", gap or 0, 0)
    else p:SetPoint("TOPLEFT", r, "TOPLEFT", r.textX or r.pad, -r.lineY[3]) end
    p:Show()
    r.l3prev = p
end

-- where a row reads its group from: the game's results, or the settings
-- preview's sample groups
local LIVE = {
    info = function(id) return C_LFGList.GetSearchResultInfo(id) end,
    activity = function(act) return C_LFGList.GetActivityInfoTable(act) end,
    player = function(id, k) return C_LFGList.GetSearchResultPlayerInfo(id, k) end,
    counts = function(id) return C_LFGList.GetSearchResultMemberCounts(id) end,
    appStatus = AppStatus,
    signedAt = SignedUpAt,
    nameColor = function(id, info, ai) if ns.GFNameColor then return ns.GFNameColor(id, info, ai) end end,
    region = function(id) if ns.RegionTagOf then return ns.RegionTagOf(id) end end,
    art = function(id) return ns.RowArtFor and ns.RowArtFor(id) end,
}

-- line three: playstyle | region | time since you signed up
-- a font string in the delisted grey, or back to the colour it was made with
local function Grey(fs, gone)
    if not fs.baseColor then fs.baseColor = { fs:GetTextColor() } end
    if gone then fs:SetTextColor(DR, DG, DB)
    else local c = fs.baseColor; fs:SetTextColor(c[1], c[2], c[3], c[4]) end
end

local function LineThree(r, id, info, src)
    local parts = r.line3
    for i = 1, #parts do parts[i]:Hide() end
    local gone = r.gone
    Grey(r.sep1, gone); Grey(r.style, gone); Grey(r.sep2, gone); Grey(r.sep3, gone); Grey(r.timer, gone)
    r.flag:SetDesaturated(gone)
    r.signedAt = nil
    r.l3prev = nil
    if (r.lines or 0) < 3 then return end
    local style = ""
    local ps = info.generalPlaystyle
    local gc = GFNS.Cfg and GFNS.Cfg()
    if not (gc and gc.extraShowPlaystyle == false) and type(ps) == "number" and not Secret(ps) then
        style = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. ps] or ""
    end
    local tag, tr, tg, tb, flag
    tag, tr, tg, tb, flag = src.region(id)
    if style ~= "" then
        r.style:SetText(style)
        Put(r, r.style)
    end
    if tag then
        if r.l3prev then Put(r, r.sep2, 4) end
        r.tag:SetText(tag)
        if gone then r.tag:SetTextColor(DR, DG, DB) else r.tag:SetTextColor(tr, tg, tb, 1) end
        Put(r, r.tag, 4)
        if flag then
            local fh = math.max(8, ns.OwnListSize("lineSize"))
            r.flag:SetSize(math.floor(fh * 4 / 3 + 0.5), fh)
            r.flag:SetTexture(flag)
            Put(r, r.flag, 4)
        end
    end
    local at = src.signedAt(id)
    if at then
        if r.l3prev then Put(r, r.sep3, 4) end
        r.timer:SetText(TimeLeft(at))
        Put(r, r.timer, 4)
        r.signedAt = at
    end
end

local function Fill(r, id, src)
    src = src or LIVE
    r.resultID = id
    local info = src.info(id)
    if not Readable(info) then r:Hide() return end
    -- delisted: greyed like blizzard's, not faded
    local gone = info.isDelisted
    gone = not Secret(gone) and gone and true or false
    r.gone = gone
    if gone then DR, DG, DB = StatusColor(LINE_DELISTED) end
    -- protected text, straight to the font string
    r.name:SetText(info.name)
    local acts = info.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    local ai = act and not Secret(act) and src.activity(act)
    if not Readable(ai) then ai = nil end
    -- colored group names
    local nr, ng, nb
    nr, ng, nb = src.nameColor(id, info, ai)  -- "and" would drop g and b
    if not nr then nr, ng, nb = FriendColor(info) end
    if gone then r.name:SetTextColor(DR, DG, DB)
    elseif nr then r.name:SetTextColor(nr, ng, nb) else r.name:SetTextColor(1, 0.82, 0) end
    r.act:SetText(ai and ai.fullName or "")
    Grey(r.act, gone)
    -- the note, only where the list left room for it (protected text, straight to the font string)
    local note = r.noteRoom and NoteText(info)
    if note then
        r.note:ClearAllPoints()
        r.note:SetPoint("TOPLEFT", r.mid, "BOTTOMLEFT", r.pad or 6, 0)
        r.note:SetPoint("TOPRIGHT", r.mid, "BOTTOMRIGHT", -(r.pad or 6), 0)
        r.note:SetText(string.format(LFG_LIST_COMMENT_FORMAT or "%s", note))
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        if fc then r.note:SetTextColor(fc.r, fc.g, fc.b) else r.note:SetTextColor(0.6, 0.6, 0.6) end
    end
    r.note:SetShown(note and true or false)
    -- signed up: the cancel square sits left of the text, which moves over for it
    local appStatus = src.appStatus(id)
    local canCancel = appStatus == "applied"
    local x0 = r.pad or 6
    r.cancel:ClearAllPoints()
    if canCancel then
        r.cancel:SetPoint("LEFT", r.mid, "LEFT", x0, 0)
        x0 = x0 + (r.cancelSize or CANCEL_H) + 6
    end
    r.cancel:SetShown(canCancel)
    r.textX = x0
    if r.act:IsShown() then
        r.act:SetPoint("TOPLEFT", r, "TOPLEFT", x0, -(r.lineY and r.lineY[2] or 0))
    end
    local short = (r.lines or 0) < 2 and ai and ns.GFShortName(ai.fullName)
    if short and short ~= "" then
        -- the title's face, size and outline (the title is on a family, so they
        -- come from what it was given, never read back from it)
        local path = famFace[r.name]
        if path then r.short:SetFont(path, ns.OwnListSize("titleSize"), famFlags[r.name]) end
        r.short:SetTextColor(r.act:GetTextColor())
        r.short:SetText(short)
        r.short:ClearAllPoints()
        r.short:SetPoint("TOPLEFT", r, "TOPLEFT", x0, -(r.lineY and r.lineY[1] or 0))
        r.short:Show()
        r.name:SetPoint("TOPLEFT", r.short, "TOPRIGHT", 4, 0)
    else
        r.short:Hide()
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", x0, -(r.lineY and r.lineY[1] or 0))
    end
    LineThree(r, id, info, src)
    local Opt = ns.GFOpt or function() return true end
    local score = info.leaderOverallDungeonScore
    if Opt("leaderRating") and type(score) == "number" and not Secret(score) and score > 0 then
        -- raider.io or game colors
        local cr, cg, cb = 1, 1, 1
        if ns.GFRatingColor then cr, cg, cb = ns.GFRatingColor(score) end
        r.score:SetText(score)
        if r.gone then r.score:SetTextColor(DR, DG, DB) else r.score:SetTextColor(cr, cg, cb) end
    else
        r.score:SetText("")
    end
    local st = appStatus and STATUS[appStatus]
    local delisted = info.isDelisted
    if not Secret(delisted) and delisted then st = STATUS.declined_delisted end  -- secret check first
    if st then
        r.status:SetText(st[1])
        -- same color as the row highlight
        local sl = LINE_OF[st]
        if sl then r.status:SetTextColor(StatusColor(sl)) else r.status:SetTextColor(st[2], st[3], st[4], 1) end
    else
        r.status:SetText("")
    end
    -- row highlight: an underline, or the whole row tinted
    local line = st and LINE_OF[st]
    local on = line and ns.OwnListGet(line[1]) ~= false or false
    local style = ns.OwnListGet("statusStyle")
    if style == "none" then on = false end  -- the status text keeps its colour
    local rowFx = on and style == "row" or false
    if on then
        local lr, lg, lb = StatusColor(line)
        -- solid, so it reads the same over any window background (the preview's is darker)
        if rowFx then r.stat:SetColorTexture(lr * 0.15 + 0.045, lg * 0.15 + 0.045, lb * 0.15 + 0.045, 1)
        else r.under:SetColorTexture(lr, lg, lb, 0.9) end
    end
    r.under:SetShown(on and not rowFx)
    r.stat:SetShown(rowFx)
    -- row art
    local art = src.art(id)
    if art and ns.ROW_ART then
        local w = r:GetWidth() or 0
        r.art:SetTexture(art)
        r.art:SetTexCoord(unpack(ns.ROW_ART.crop))
        r.art:ClearAllPoints()
        r.art:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
        r.art:SetPoint("BOTTOMLEFT", r.mid, "BOTTOMLEFT", 0, 0)
        r.art:SetWidth(math.max(1, math.floor(w * ns.ROW_ART.share)))
        r.art:Show()
    else
        r.art:Hide()
    end
    -- members, tanks first (the row's own tables, refilled)
    local members, pool = r.members, r.mpool
    wipe(members)
    local n = info.numMembers
    if type(n) == "number" and not Secret(n) then
        for k = 1, n do
            local p = src.player(id, k)
            if Readable(p) and p.classFilename and not Secret(p.classFilename) then
                local spec = p.specName
                if Secret(spec) then spec = nil end
                local lead = p.isLeader
                if Secret(lead) then lead = nil end
                local role = p.assignedRole
                if Secret(role) then role = nil end
                local e = pool[#members + 1]
                if not e then
                    e = {}
                    pool[#members + 1] = e
                end
                e.cls, e.role, e.spec, e.lead, e.k = p.classFilename, role, spec, lead, k
                members[#members + 1] = e
            end
        end
    end
    table.sort(members, ByRole)
    local cap = ai and ai.maxNumPlayers or 5
    local mode = MemberMode(ai, cap)
    -- open roles for the empty slots
    local needs = r.needs
    wipe(needs)
    if ns.OwnListGet("missingIcons") ~= "none" and mode == "icons" and cap == 5 then
        local counts = src.counts(id)
        if Readable(counts) then
            for i = 1, #RR_ROLES do
                local role = RR_ROLES[i]
                local left = counts[REMAINING[role]]
                if type(left) == "number" and not Secret(left) then
                    for _ = 1, left do needs[#needs + 1] = role end
                end
            end
        end
    end
    local specOn = Opt("specIcons")
    -- the crown goes with the activity line when the row's too short for it
    local crownOn = Opt("leaderCrown") and (r.lines or 0) >= 2
    local square = ns.OwnListGet("iconShape") == "square"
    local bpx = tonumber(ns.OwnListGet("borderSize")) or 0
    local btex = ns.OwnListGet("borderTexture") or "solid"
    local br, bg, bb = 1, 1, 1
    local bc = ns.OwnListGet("borderColor")
    if type(bc) == "table" then
        br, bg, bb = bc.r or 1, bc.g or 1, bc.b or 1
    elseif btex ~= "solid" and square then
        local c = EUI.GetBorderStyleSelectDefaults(btex)
        br, bg, bb = c.r, c.g, c.b
    elseif ns.ThemeBorder then
        br, bg, bb = ns.ThemeBorder()
    end
    local bkey = btex .. ":" .. bpx .. ":" .. br .. ":" .. bg .. ":" .. bb
    local blizzMissing = ns.OwnListGet("missingIcons") ~= "ellesmere"
    local nextNeed = 1
    for k = 1, 5 do
        local t, m, role, bf = r.icons[k], members[k], r.roles[k], r.borders[k]
        r.crowns[k]:Hide()
        r.rings[k]:Hide()
        role:Hide()
        role:SetDesaturated(gone)
        role:SetAlpha(1)
        bf:Hide()
        if t._masked then t:RemoveMaskTexture(r.masks[k]); t._masked = nil end
        t:SetTexCoord(0, 1, 0, 1)
        t:SetDesaturated(gone)
        r.crowns[k]:SetDesaturated(gone)
        if mode ~= "icons" then
            t:Hide()
        elseif m then
            local icon = specOn and m.spec and ns.GFSpecIcon and ns.GFSpecIcon(m.cls, m.spec)
            if icon then
                t:SetTexture(icon)
                t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif square then
                -- square: class color tile
                local cc = C_ClassColor and C_ClassColor.GetClassColor(m.cls)
                if cc then t:SetColorTexture(cc.r * 0.75, cc.g * 0.75, cc.b * 0.75, 1) else t:SetColorTexture(0.3, 0.3, 0.3, 1) end
            else
                -- the game's class circle
                t:SetAtlas("groupfinder-icon-class-color-" .. m.cls)
            end
            if not icon and NEED_ATLAS[m.role] then
                role:SetAtlas(NEED_ATLAS[m.role])
                role:Show()
            end
            if square then
                if bpx > 0 then
                    if bf._key ~= bkey then
                        bf._key = bkey
                        EUI.ApplyBorderStyle(bf, bpx, br, bg, bb, 1, btex)
                    end
                    bf:Show()
                end
            elseif icon then
                -- round spec icon + ring
                t:AddMaskTexture(r.masks[k]); t._masked = true
                if bpx > 0 then
                    local ring = r.rings[k]
                    ring:ClearAllPoints()
                    ring:SetPoint("TOPLEFT", t, "TOPLEFT", -bpx, bpx)
                    ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", bpx, -bpx)
                    ring:SetColorTexture(br, bg, bb, 1)
                    ring:Show()
                end
            end
            t:SetAlpha(1)
            t:Show()
            if crownOn and m.lead then r.crowns[k]:Show() end
        elseif k <= cap then
            local need = needs[nextNeed]
            nextNeed = nextNeed + 1
            local needTex = need and not blizzMissing and ns.RoleIconTex and ns.RoleIconTex(need)
            if need and blizzMissing then
                -- blizzard style: small grey mark
                t:Hide()
                role:SetAtlas(NEED_ATLAS[need])
                role:SetDesaturated(true)
                role:SetAlpha(0.6)
                role:Show()
            elseif needTex then
                -- small, like blizzard's
                t:Hide()
                role:SetTexture(needTex)
                role:SetAlpha(0.6)
                role:Show()
            else
                t:SetAtlas("groupfinder-icon-emptyslot")
                t:SetAlpha(blizzMissing and 1 or 0.5)
                t:Show()
            end
        else
            t:Hide()
        end
    end
    -- raid role counts, rating to their left
    local counts = mode == "counts" and src.counts(id)
    if not Readable(counts) then counts = nil end
    local blizzRR = ns.OwnListGet("raidRoleIcons") == "blizzard"
    local round = ns.OwnListGet("iconShape") ~= "square"
    -- round rings sit outside the circle, so the first one steps in like the member icons
    local x = -(r.pad or 6) - (round and bpx or 0)
    local isz = r.icons[1]:GetWidth() or 16
    local fsz = ns.OwnListSize("scoreSize")
    -- a number above a centred circle needs its height on top: else it goes on the circle
    local inside = (r.layH or isz) < isz + 2 * (fsz + 1)
    for k = 3, 1, -1 do
        local p = r.rr[k]
        local role = RR_ROLES[k]
        local num = counts and counts[role]
        if counts and type(num) == "number" and not Secret(num) then
            -- icon centered, count above
            local edge = 0
            if blizzRR then
                -- blizzard's circle as one texture, no mask or border of ours
                if p.masked then p.bg:RemoveMaskTexture(p.mask); p.masked = nil end
                p.bg:SetAtlas(BLIZZ_RR_ATLAS[role])
                p.icon:SetTexture(nil)
                p.ring:Hide(); p.edge:Hide()
            else
                local c = RR_COLORS[role]
                p.bg:SetColorTexture(c[1], c[2], c[3], 1)
                if round and not p.masked then p.bg:AddMaskTexture(p.mask); p.masked = true
                elseif not round and p.masked then p.bg:RemoveMaskTexture(p.mask); p.masked = nil end
                CircleEdge(p, round, bpx, br, bg, bb, btex, bkey)
                p.icon:SetAtlas(NEED_ATLAS[role])
                local gsz = math.floor(isz * 0.7 + 0.5)
                p.icon:SetSize(gsz, gsz)
                edge = round and bpx * 2 or 0
            end
            p.bg:SetDesaturated(gone)
            p.icon:SetDesaturated(gone)
            p.bg:ClearAllPoints()
            if blizzRR then
                -- the art has a clear margin round its ring: grow it till the ring matches ours, same centre
                edge = round and bpx * 2 or 0
                local sz = math.floor((isz + edge) * BLIZZ_RR_SCALE + 0.5) - 2
                p.bg:SetSize(sz, sz)
                p.bg:SetPoint("CENTER", r.mid, "RIGHT", x - isz / 2, 0)
            else
                p.bg:SetSize(isz, isz)
                p.bg:SetPoint("RIGHT", r.mid, "RIGHT", x, 0)
            end
            p.bg:Show()
            x = x - PlaceCount(p, num, isz, fsz, inside) - 6 - edge
            if blizzRR and not inside then
                -- the number on the ring's top, not the art's
                p.count:ClearAllPoints()
                p.count:SetPoint("BOTTOMLEFT", p.bg, "CENTER", -isz * 1.5, isz / 2 + 1)
                p.count:SetPoint("BOTTOMRIGHT", p.bg, "CENTER", isz * 1.5, isz / 2 + 1)
            end
        else
            p.bg:Hide(); p.icon:Hide(); p.count:Hide(); p.ring:Hide(); p.edge:Hide()
        end
    end
    -- player count: a grey circle with a person, the number above, like the role counts
    local players = mode == "players" and n
    local pc = r.rr[4]
    if type(players) == "number" and not Secret(players) then
        pc.bg:SetColorTexture(PLAYERS_COLOR[1], PLAYERS_COLOR[2], PLAYERS_COLOR[3], 1)
        pc.bg:SetDesaturated(gone)
        pc.icon:SetDesaturated(gone)
        if round and not pc.masked then pc.bg:AddMaskTexture(pc.mask); pc.masked = true
        elseif not round and pc.masked then pc.bg:RemoveMaskTexture(pc.mask); pc.masked = nil end
        pc.bg:SetSize(isz, isz)
        pc.bg:ClearAllPoints()
        pc.bg:SetPoint("RIGHT", r.mid, "RIGHT", x, 0)
        pc.bg:Show()
        CircleEdge(pc, round, bpx, br, bg, bb, btex, bkey)
        local gsz = math.floor(isz * 0.7 + 0.5)
        pc.icon:SetTexture(PERSON_TEX)
        pc.icon:SetSize(gsz, gsz)
        x = x - PlaceCount(pc, players, isz, fsz, inside) - 6 - (round and bpx * 2 or 0)
    else
        players = nil
        pc.bg:Hide(); pc.icon:Hide(); pc.count:Hide(); pc.ring:Hide(); pc.edge:Hide()
    end
    if counts or players then
        r.score:ClearAllPoints()
        r.score:SetPoint("RIGHT", r.mid, "RIGHT", x - 6, 0)
        r.scoreRaid = true
    elseif r.scoreRaid then
        -- the slot showed a raid before: the score goes back beside the icons
        r.scoreRaid = nil
        r.score:ClearAllPoints()
        r.score:SetPoint("RIGHT", r.mid, "RIGHT", r.scoreX or -6, 0)
    end
    if r.stock then
        r.sel:SetShown(selected == id)
    else
        local ar, ag, ab = Accent()
        r.sel:SetColorTexture(ar, ag, ab, selected == id and 0.18 or 0)
    end
    if dimmed[id] then r:SetAlpha(0.35)
    elseif gone then r:SetAlpha((tonumber(ns.OwnListGet("delistedOpacity")) or 50) / 100)  -- the delisted opacity setting
    else r:SetAlpha((st and st ~= STATUS.applied and st ~= STATUS.invited) and 0.5 or 1) end
    r:Show()
end

-------------------------------------------------------------------------------
--  settings preview: sample groups drawn by the list's own rows
-------------------------------------------------------------------------------
local PV_W, PV_PAD, PV_MARGIN = 330, 8, 10  -- about the list's row width
local PV_SCALE = 1  -- times the list's own size: 1 draws the rows as the dungeons & raids window does
local PV_STEP = 0.3  -- a wheel tick, in rows
local PV_DD_W, PV_DD_GAP = 170, 12  -- the preview picker, right of it
local PV_TITLES = { groups = EllesmereUI.L("Group Finder Preview"), dungeon = EllesmereUI.L("Applicant Preview"),
    raid = EllesmereUI.L("Applicant Preview") }
local PV_TITLE = 22  -- the "Group Finder Preview" strip
-- the rows' window keeps one height (two rows at the default height): taller
-- rows get cut off at its bottom, as in the list, and the page never moves.
-- more groups show as rows get shorter
local PV_VIEW_H = 2 * 50 + GAP
-- ellesmere's own holy paladin in every preview, and two friends' characters
local PV_ELLE, PV_LUELLA, PV_BLOCKJOB = "Ellesm\195\169re", "Luella", "Blockjob"
ns.PreviewElle, ns.PreviewLuella, ns.PreviewBlockjob = PV_ELLE, PV_LUELLA, PV_BLOCKJOB
-- the sample groups. dungeon = index in this season's list, else a raid of that
-- difficulty; specs = members, leader first (made-up names in the tooltip)
local PV = {
    pv1 = { name = EllesmereUI.L("Weekly key, chill run"), dungeon = 1, style = 2, score = 2780, age = 420, new = true,
        note = EllesmereUI.L("Know the route, have fun"),
        specs = { { 73, true }, { 64 }, { 260 }, { 102 } } },
    pv2 = { name = EllesmereUI.L("Heroic raid, need healers"), raid = PLAYER_DIFFICULTY2 or "Heroic", style = 3, score = 1950,
        age = 1260, applied = true,
        specs = { { 66, true }, { 268 }, { 65, false, PV_ELLE }, { 105 }, { 264 }, { 71 }, { 72, false, PV_BLOCKJOB }, { 251 }, { 252 }, { 253 },
            { 254 }, { 62 }, { 63 }, { 258 }, { 262 }, { 577 }, { 1467 } },
        open = { TANK = 0, HEALER = 3, DAMAGER = 3 } },
    pv3 = { name = EllesmereUI.L("Push for the timer, bring lust"), dungeon = 2, style = 3, score = 3120, age = 300,
        note = EllesmereUI.L("Timing it, voice optional"),
        specs = { { 250, true }, { 264 }, { 72, false, PV_BLOCKJOB } } },
    pv4 = { name = EllesmereUI.L("Need a tank, fast and clean"), dungeon = 3, style = 2, score = 2450, age = 640,
        specs = { { 270, true }, { 70 }, { 253 }, { 1467 } } },
    pv5 = { name = EllesmereUI.L("Normal clear, all welcome"), raid = PLAYER_DIFFICULTY1 or "Normal", style = 1, score = 1420,
        age = 900,
        specs = { { 73, true }, { 257, false, PV_LUELLA }, { 264 }, { 71 }, { 254 }, { 62 }, { 259 }, { 102 }, { 577 } },
        open = { TANK = 1, HEALER = 1, DAMAGER = 4 } },
    pv6 = { name = EllesmereUI.L("Learning the route, be patient"), dungeon = 4, style = 1, score = 1850, age = 180,
        specs = { { 104, true }, { 257, false, PV_LUELLA }, { 265 }, { 63 } } },
}
local PV_IDS = { "pv1", "pv2", "pv3", "pv4", "pv5", "pv6" }
local PV_ACT = {}  -- activity id -> group id
for i, id in ipairs(PV_IDS) do PV[id].act = i; PV_ACT[i] = id end
local pv = { dungeons = {} }

-- one of this season's dungeons, for the name and the row art. its keystone
-- activity gives the name the list shows ("... (Mythic Keystone)")
local function PvDungeon(i)
    if pv.dungeons[i] then return pv.dungeons[i] end
    local CMode = C_ChallengeMode
    local maps = CMode and CMode.GetMapTable and CMode.GetMapTable()
    local name, mapID
    local map = maps and (maps[i] or maps[1])
    if map then
        local n, _, _, _, _, mid = CMode.GetMapUIInfo(map)
        name, mapID = n, mid
    end
    -- names can be missing right after login, so it asks again next paint
    if not name then return { full = EllesmereUI.L("Dungeon") } end
    local full
    local acts = mapID and C_LFGList.GetAvailableActivities and C_LFGList.GetAvailableActivities(DUNGEONS)
    for _, act in ipairs(Readable(acts) and acts or {}) do
        local ai = not Secret(act) and C_LFGList.GetActivityInfoTable(act)
        if Readable(ai) and ai.isMythicPlusActivity and ai.mapID == mapID and type(ai.fullName) == "string" then
            full = ai.fullName
            break
        end
    end
    pv.dungeons[i] = { full = full or (name .. " (" .. EllesmereUI.L("Mythic Keystone") .. ")"), mapID = mapID }
    return pv.dungeons[i]
end

-- members by role, and what a five-player group still needs
local function PvCounts(g)
    if g.counts then return g.counts end
    local n = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, s in ipairs(g.specs) do
        local _, _, _, _, role = GetSpecializationInfoByID(s[1])
        if n[role] then n[role] = n[role] + 1 end
    end
    local open = g.open or { TANK = math.max(0, 1 - n.TANK), HEALER = math.max(0, 1 - n.HEALER),
        DAMAGER = math.max(0, 3 - n.DAMAGER) }
    g.counts = { TANK = n.TANK, HEALER = n.HEALER, DAMAGER = n.DAMAGER,
        TANK_REMAINING = open.TANK, HEALER_REMAINING = open.HEALER, DAMAGER_REMAINING = open.DAMAGER }
    return g.counts
end

local PREVIEW = {
    info = function(id)
        local g = PV[id]
        return { name = g.name, comment = g.note or "", activityIDs = { g.act }, generalPlaystyle = g.style,
            leaderOverallDungeonScore = g.score, numMembers = #g.specs, isDelisted = false }
    end,
    activity = function(act)
        local g = PV[PV_ACT[act]]
        local DT = Enum.LFGListDisplayType
        if g.dungeon then
            local d = PvDungeon(g.dungeon)
            return { fullName = d.full, maxNumPlayers = 5, displayType = DT and DT.RoleEnumerate, mapID = d.mapID }
        end
        return { fullName = (RAID or "Raid") .. " (" .. g.raid .. ")", maxNumPlayers = 30, displayType = DT and DT.RoleCount }
    end,
    player = function(id, k)
        local s = PV[id].specs[k]
        if not s then return nil end
        local _, spec, _, _, role, cls = GetSpecializationInfoByID(s[1])
        return { classFilename = cls, specName = spec, assignedRole = role, isLeader = s[2] or false }
    end,
    counts = function(id) return PvCounts(PV[id]) end,
    appStatus = function(id) return PV[id].applied and "applied" or "none" end,
    signedAt = function(id) if PV[id].applied then return GetTime() - 95 end end,
    -- the first group reads as new
    nameColor = function(id)
        if PV[id].new and GFNS.Cfg and GFNS.Cfg().nameColors == true then return 0.3, 1, 0.3 end
    end,
    -- your own realm's tag
    region = function() if ns.RegionTagOfName then return ns.RegionTagOfName(UnitName("player")) end end,
    art = function(id)
        local g = PV[id]
        local d = g.dungeon and PvDungeon(g.dungeon)
        return d and d.mapID and ns.RowArtForMap and ns.RowArtForMap(d.mapID)
    end,
}

-- lays the rows out and fills them; the header height for it
local function PvFit()
    local f, view = pv.frame, pv.view
    local hdr = f:GetParent()
    local h = ns.OwnListRowHeight()
    local mode = pv.mode or "groups"
    pv.title:SetText(PV_TITLES[mode])
    -- applicants: the applicant list draws its samples in the same window
    local apps = mode ~= "groups" and ns.ApplicantPreviewPaint ~= nil
    view:SetShown(not apps)
    pv.appHost:SetShown(apps)
    pv.appHost:SetSize(PV_W, PV_VIEW_H)
    if ns.ApplicantPreviewPaint then ns.ApplicantPreviewPaint(pv.appHost, apps and mode or nil, PV_W, PV_VIEW_H) end
    -- a fixed width: the list's own only settles once group finder opens
    local rw = PV_W
    local nH = NoteHeight()
    -- the heights first: the scroll stops at the last group
    local total = -GAP
    for i, id in ipairs(PV_IDS) do
        local r = pv.rows[i]
        r.noteRoom = NoteText(PREVIEW.info(id)) and true or nil
        r.pvH = h + (r.noteRoom and nH or 0)
        total = total + r.pvH + GAP
    end
    pv.maxScroll = math.max(0, total - PV_VIEW_H)
    pv.scroll = math.max(0, math.min(pv.scroll or 0, pv.maxScroll))
    local y = -pv.scroll
    for i, id in ipairs(PV_IDS) do
        local r = pv.rows[i]
        local rh = r.pvH
        -- rows outside the window aren't drawn at all
        if y + rh > 0 and y < PV_VIEW_H then
            r:SetSize(rw, rh)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -y)
            r.layH = nil  -- every paint lays out again
            Layout(r, h)
            Fill(r, id, PREVIEW)
            r:Show()
        else
            r.resultID = nil
            r:Hide()
        end
        y = y + rh + GAP
    end
    view:SetSize(rw, PV_VIEW_H)
    -- scroll thumb
    local th = pv.thumb
    if pv.maxScroll > 0 then
        local tH = math.max(12, PV_VIEW_H * PV_VIEW_H / (total > 0 and total or 1))
        th:SetHeight(tH)
        th:ClearAllPoints()
        th:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -(PV_VIEW_H - tH) * (pv.scroll / pv.maxScroll))
        th:Show()
    else
        th:Hide()
    end
    local fw, fh = rw + PV_PAD * 2, PV_PAD + PV_TITLE + PV_VIEW_H + PV_PAD
    f:SetSize(fw, fh)
    -- the list's own size (the ui's scale, not the panel's), grown or shrunk
    -- with the settings window's scale, and shrunk only if the panel is narrower
    local hw = hdr:GetWidth() or 0
    -- room for the picker on both sides, so the preview stays centered
    local avail = (hw > 0 and hw or pv.hdrW or 600) - PV_MARGIN * 2 - (pv.dd and (PV_DD_W + PV_DD_GAP) * 2 or 0)
    local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1
    local s = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale() * PV_SCALE * userScale
    if fw * s > avail then s = avail / fw end
    f:SetScale(s)
    f:ClearAllPoints()
    f:SetPoint("CENTER", hdr, "CENTER", 0, 0)
    return math.ceil(fh * s) + PV_MARGIN * 2
end

-- the tooltips' names: the suite's preview roster (EllesmereUI.PREVIEW_ROSTER,
-- shared with the raid & party frames preview). members take a name of their
-- own class first
local PV_ROSTER = EllesmereUI.PREVIEW_ROSTER

ns.PreviewRoster = PV_ROSTER  -- the applicant preview's names too

local function PvPlayers(id)
    local list, used = {}, {}
    local start = (PV[id].act - 1) * 3  -- groups lead with different names
    local function Take(cls)
        for pass = 1, 2 do
            for i = 0, #PV_ROSTER - 1 do
                local k = (start + i) % #PV_ROSTER + 1
                local e = PV_ROSTER[k]
                if not used[k] and (pass == 2 or e.class == cls) then
                    used[k] = true
                    return e.name
                end
            end
        end
    end
    for _, s in ipairs(PV[id].specs) do
        local _, spec, _, _, role, cls, className = GetSpecializationInfoByID(s[1])
        if cls then
            list[#list + 1] = { assignedRole = role, classFilename = cls, className = className,
                specName = spec, isLeader = s[2] or false, name = s[3] or Take(cls) }
        end
    end
    return list
end

-- a group tooltip from the sample data, its member lines as the list adds them
function ns.OwnListPreviewTip(r)
    local id = r.resultID
    if not id then return end
    local info = PREVIEW.info(id)
    local ai = PREVIEW.activity(info.activityIDs[1])
    local DT = Enum.LFGListDisplayType
    local enumerate = DT and ai.displayType == DT.RoleEnumerate
    local players = PvPlayers(id)
    local tip = GameTooltip
    tip:SetOwner(r, "ANCHOR_RIGHT", 25, 0)
    tip:SetText(info.name, 1, 1, 1, 1, true)
    tip:AddLine(ai.fullName)
    local ps = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. info.generalPlaystyle]
    if ps then tip:AddLine(ps, 0.6, 0.6, 0.6) end
    if info.comment ~= "" then
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        tip:AddLine(string.format(LFG_LIST_COMMENT_FORMAT or "%s", info.comment), fc and fc.r or 0.6, fc and fc.g or 0.6, fc and fc.b or 0.6, true)
    end
    tip:AddLine(" ")
    local leader = players[1] and players[1].name
    if leader then tip:AddLine(string.format(LFG_LIST_TOOLTIP_LEADER or "Leader: %s", leader)) end
    local score = info.leaderOverallDungeonScore
    local col = C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    local scoreText = col and col:WrapTextInColorCode(score) or tostring(score)
    tip:AddLine(string.format(DUNGEON_SCORE_LEADER or "Leader's Mythic+ Rating: %s", scoreText))
    tip:AddLine(string.format(LFG_LIST_TOOLTIP_AGE or "Created %s ago", SecondsToTime(PV[id].age)))
    tip:AddLine(" ")
    if enumerate then
        local roleName = { TANK = TANK, HEALER = HEALER, DAMAGER = DAMAGER }
        for _, p in ipairs(players) do
            local cc = RAID_CLASS_COLORS[p.classFilename] or NORMAL_FONT_COLOR
            tip:AddLine(string.format(LFG_LIST_TOOLTIP_CLASS_ROLE or "%s - %s", p.className, roleName[p.assignedRole] or ""),
                cc.r, cc.g, cc.b)
        end
    else
        local n = PREVIEW.counts(id)
        tip:AddLine(string.format(LFG_LIST_TOOLTIP_MEMBERS or "Members: %d (%d/%d/%d)",
            info.numMembers, n.TANK, n.HEALER, n.DAMAGER))
    end
    if GFNS.Cfg().classTooltip ~= false and ns.GFTooltipMembers then
        ns.GFTooltipMembers(tip, players, enumerate)
    end
    tip:Show()
end

-- the settings page's content header
function ns.OwnListPreviewBuild(hdr, hdrW)
    local f = pv.frame
    if not f then
        f = CreateFrame("Frame", nil, hdr)
        pv.frame = f
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
        EUI.MakeBorder(f, 0.2, 0.2, 0.2, 1, EUI.PanelPP)
        -- a title like the raid frames' overlay preview
        local title = EUI.MakeFont(f, 13, nil, 1, 1, 1, 0.9)
        title:SetPoint("TOP", f, "TOP", 0, -7)
        pv.title = title
        -- the rows' window: what doesn't fit is cut off
        local view = CreateFrame("Frame", nil, f)
        view:SetPoint("TOPLEFT", f, "TOPLEFT", PV_PAD, -(PV_PAD + PV_TITLE))
        view:SetClipsChildren(true)
        pv.view = view
        -- the wheel scrolls part of a row at a time: the window holds only two
        view:EnableMouseWheel(true)
        view:SetScript("OnMouseWheel", function(_, delta)
            local was = pv.scroll or 0
            local step = math.floor((ns.OwnListRowHeight() + GAP) * PV_STEP + 0.5)
            pv.scroll = math.max(0, math.min(was - delta * step, pv.maxScroll or 0))
            if pv.scroll ~= was then
                PvFit()
                -- the hovered row changed under the mouse
                if GameTooltip:IsShown() and GameTooltip:GetOwner() and GameTooltip:GetOwner().preview then GameTooltip:Hide() end
            end
        end)
        pv.thumb = view:CreateTexture(nil, "OVERLAY", nil, 7)
        pv.thumb:SetWidth(2)
        pv.thumb:SetColorTexture(1, 1, 1, 0.25)
        pv.thumb:Hide()
        -- the applicant samples' window, in the same spot
        pv.appHost = CreateFrame("Frame", nil, f)
        pv.appHost:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
        pv.appHost:SetClipsChildren(true)
        pv.appHost:Hide()
        -- groups or applicants, picked right of the preview (the settings page
        -- builds this header, so the options widgets are loaded)
        local dd = EUI.BuildDropdownControl(hdr, PV_DD_W, hdr:GetFrameLevel() + 3,
            { groups = "Groups", dungeon = "Dungeon Applicants", raid = "Raid Applicants" },
            { "groups", "dungeon", "raid" },
            function() return pv.mode or "groups" end,
            function(v)
                pv.mode = v
                GameTooltip_Hide()
                ns.OwnListPreviewPaint()
            end)
        dd:SetPoint("LEFT", f, "RIGHT", PV_DD_GAP, 0)
        pv.dd = dd
        pv.rows = {}
        for i = 1, #PV_IDS do
            local r = MakeRow(nil, view)
            r.preview = true
            pv.rows[i] = r
        end
        -- the settings window's scale changed: size it again
        if not EUI._onScaleChanged then EUI._onScaleChanged = {} end
        EUI._onScaleChanged[#EUI._onScaleChanged + 1] = ns.OwnListPreviewPaint
    else
        f:SetParent(hdr)
        if pv.dd then pv.dd:SetParent(hdr) end
    end
    -- a rebuilt page detaches it first, which can leave it under the window's
    -- drag area, and that would take the hover
    f:SetFrameLevel(hdr:GetFrameLevel() + 2)
    if pv.dd then
        pv.dd:SetFrameLevel(hdr:GetFrameLevel() + 3)
        pv.dd:Show()
    end
    pv.hdrW = hdrW
    f:Show()
    pv.h = PvFit()
    return pv.h
end

-- a display setting changed: draw again (the height only moves with the ui scale)
function ns.OwnListPreviewPaint()
    local f = pv.frame
    if not (f and f:IsVisible()) then return end
    local h = PvFit()
    if h ~= pv.h then
        pv.h = h
        EUI:SetContentHeaderHeightSilent(h)
    end
end

-------------------------------------------------------------------------------
--  the list
-------------------------------------------------------------------------------
local empty, thumb

-- the timers tick only while a row in view shows one
local function SyncTicker()
    if not ticker then return end
    local any = false
    if active then
        for i = 1, #rows do
            local r = rows[i]
            if r.signedAt and r:IsShown() then
                any = true
                break
            end
        end
    end
    ticker:SetShown(any)
end

function Paint()  -- forward-declared up top
    if not (frame and active) then return end
    local h = ns.OwnListRowHeight()
    local height = body:GetHeight() or 0
    -- a group with a note is a line taller
    local nH = NoteHeight()
    local total = 0
    wipe(tops)
    for i = 1, #shown do
        tops[i] = total
        total = total + h + (noteOf[shown[i]] and nH or 0) + GAP
    end
    local maxPx = math.max(0, total - GAP - height)
    scrollPx = math.max(0, math.min(scrollPx, maxPx))
    local first = 1
    while tops[first + 1] and tops[first + 1] <= scrollPx do first = first + 1 end
    local used = 0
    for idx = first, #shown do
        local y = tops[idx] - scrollPx
        if y >= height then break end
        used = used + 1
        local r = rows[used] or MakeRow(used)
        local id = shown[idx]
        r.noteRoom = noteOf[id]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
        r:SetHeight(h + (r.noteRoom and nH or 0))
        Layout(r, h)
        Fill(r, id)
    end
    for i = used + 1, #rows do
        rows[i].resultID = nil
        rows[i]:Hide()
    end
    PaintSignBtn()
    SyncTicker()
    -- scroll thumb
    if maxPx > 0 then
        local share = height / (maxPx + height)
        local th = math.max(16, height * share)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(height - th) * (scrollPx / maxPx))
        thumb:Show()
    else
        thumb:Hide()
    end
    if SP.searching then
        empty:SetText("")  -- blizzard's spinner covers it
    elseif #shown == 0 then
        local total = type(SP.results) == "table" and #SP.results or 0
        empty:SetText(total > 0 and EllesmereUI.Lf("%1$d groups found, none match your filters", total) or EllesmereUI.L("No groups found"))
    else
        empty:SetText("")
    end
end

-- keep blizzard's list hidden while ours shows
local function HoldHidden(f, a)
    if guard or not active or a == 0 then return end
    guard = true
    f:SetAlpha(0)
    guard = false
end

-- a hidden sign up status (keys, encounters): our rows couldn't tell if a group can be picked
local function AppSecret(id)
    local _, status, pending = C_LFGList.GetApplicationInfo(id)
    return Secret(status) or Secret(pending)
end

-- one result's secrecy, as AnySecret reads the whole list
local function ResultSecret(id)
    if Secret(id) or AppSecret(id) then return true end
    local info = C_LFGList.GetSearchResultInfo(id)
    return info ~= nil and (not Readable(info) or Secret(info.activityIDs) or Secret(info.isDelisted))
end

local function RowFor(id)
    for i = 1, #rows do
        local r = rows[i]
        if r.resultID == id and r:IsShown() then return r end
    end
end

-- the frame after result updates: each changed group repaints its own row.
-- The whole list collects again only when it has to: a group gone secret, one
-- whose filter pass changed, a sort that follows score or size, or a refresh
-- that was asked for
local function Flush()
    flusher:Hide()
    if not active then
        wipe(dirty)
        fullDirty = false
        return
    end
    local full = fullDirty
    fullDirty = false
    if not full then
        local gc = GFNS.Cfg and GFNS.Cfg()
        local by = gc and gc.extraSortBy
        full = by == "high" or by == "low" or by == "big" or by == "small"
    end
    if not full then
        local notesOn = ns.OwnListGet("groupNotes")
        for id in pairs(dirty) do
            if ResultSecret(id) then
                full = true
                break
            end
            local was = passOf[id]
            -- a group outside the last collect is not on our list
            if was ~= nil and not isApp[id] then
                local pass = (not GFNS.ExtraPasses or GFNS.ExtraPasses(id)) and true or false
                if pass ~= was then
                    full = true
                    break
                end
            end
            -- a listed group's note came or went: its row is a line taller or shorter
            if notesOn and (isApp[id] or was == true or dimmed[id])
               and (NoteText(C_LFGList.GetSearchResultInfo(id)) ~= nil) ~= (noteOf[id] == true) then
                full = true
                break
            end
        end
    end
    if full then
        wipe(dirty)
        ns.OwnListRefresh()
        return
    end
    for id in pairs(dirty) do
        local r = RowFor(id)
        if r then Fill(r, id) end
    end
    wipe(dirty)
    PaintSignBtn()
    SyncTicker()
end

local function Build()
    if frame then return end
    SP = LFGListFrame and LFGListFrame.SearchPanel
    if not (SP and SP.ScrollBox) then return end
    frame = CreateFrame("Frame", nil, SP)
    -- shown only while active: a first visit to quests or custom never turns it
    -- on, and a shown empty frame there took every click and scroll
    frame:Hide()
    if LFGListSearchPanel_DoSearch then
        hooksecurefunc("LFGListSearchPanel_DoSearch", function() wipe(posOf); nextPos = 0; selected = nil end)
    end
    frame:SetPoint("TOPLEFT", SP.ScrollBox, "TOPLEFT", 3, 0)
    frame:SetPoint("BOTTOMRIGHT", SP.ScrollBar or SP.ScrollBox, "BOTTOMRIGHT", 0, 0)
    frame:SetFrameLevel(SP.ScrollBox:GetFrameLevel() + 10)
    frame:EnableMouse(true)  -- blizzard's hidden rows never get clicks
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        scrollPx = scrollPx - delta * (ns.OwnListRowHeight() + GAP)
        Paint()
    end)
    frame:SetScript("OnSizeChanged", Paint)
    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", SP.ScrollBox, "BOTTOMRIGHT", -3, 0)
    body:SetClipsChildren(true)
    empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", frame, "TOP", 0, -30)
    thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.3)
    -- our sign up button over blizzard's
    local sb = SP.SignUpButton
    if sb then
        local stock = not Skinned()
        signBtn = CreateFrame("Button", nil, SP, stock and "UIPanelButtonTemplate" or nil)
        signBtn:SetAllPoints(sb)
        signBtn:SetFrameLevel(sb:GetFrameLevel() + 5)
        signBtn:SetNormalFontObject("GameFontNormal")
        signBtn:SetHighlightFontObject("GameFontHighlight")
        signBtn:SetDisabledFontObject("GameFontDisable")
        signBtn:SetText(SIGN_UP or "Sign Up")
        signBtn:SetMotionScriptsWhileDisabled(true)
        local skin = EUI._ModuleNS and EUI._ModuleNS.EllesmereUIBlizzardSkin
        local S = skin and skin.WSkin
        -- stock keeps the template's art
        if not stock and S and S.Button then
            S.Button(signBtn)
        elseif not stock then
            local bg = signBtn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
            EUI.MakeBorder(signBtn, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
            local hl = signBtn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)
        end
        signBtn:SetScript("OnClick", function() SignUp(selected) end)
        signBtn:SetScript("OnEnter", function(self)
            if not self.why then return end
            EUI.ShowWidgetTooltip(self, self.why)
        end)
        signBtn:SetScript("OnLeave", EUI.HideWidgetTooltip)
        signBtn:Hide()
        hooksecurefunc(sb, "SetAlpha", HoldHidden)
    end
    hooksecurefunc(SP.ScrollBox, "SetAlpha", HoldHidden)
    if SP.ScrollBar then hooksecurefunc(SP.ScrollBar, "SetAlpha", HoldHidden) end
    if SP.SearchingSpinner then hooksecurefunc(SP.SearchingSpinner, "SetAlpha", HoldHidden) end
    hooksecurefunc("LFGListSearchPanel_UpdateResults", function(panel)
        if panel == SP then ns.OwnListRefresh() end
    end)
    -- sign up timers tick once a second, just their text, on a frame shown
    -- only while a row in view has one (SyncTicker)
    ticker = CreateFrame("Frame", nil, frame)
    ticker:Hide()
    local tick = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        tick = tick + dt
        if tick < 1 then return end
        tick = 0
        for i = 1, #rows do
            local r = rows[i]
            if r.signedAt and r:IsShown() then r.timer:SetText(TimeLeft(r.signedAt)) end
        end
    end)
    -- result updates gather here and flush once, on the next frame
    flusher = CreateFrame("Frame")
    flusher:Hide()
    flusher:SetScript("OnUpdate", Flush)
    frame:SetScript("OnEvent", function(_, event, id)
        if event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
            -- one group changed; a result can also go secret mid-list
            if type(id) == "number" and not Secret(id) then dirty[id] = true else fullDirty = true end
            flusher:Show()
        elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            -- applications reorder the list (applied groups on top)
            fullDirty = true
            flusher:Show()
        else
            PaintSignBtn()
        end
    end)
end

-- any result secret? hand back to blizzard's list
function AnySecret()
    local res = SP and SP.results
    if type(res) ~= "table" then return false end
    for _, id in ipairs(res) do
        if Secret(id) or AppSecret(id) then return true end
        local info = C_LFGList.GetSearchResultInfo(id)
        if info and (not Readable(info) or Secret(info.activityIDs) or Secret(info.isDelisted)) then return true end
    end
    return false
end

-- the categories our list covers
local OURS = { [DUNGEONS] = true, [RAIDS] = true, [DELVES] = true, [QUESTS] = true, [CUSTOM] = true }

-- ours on those searches with readable results
function ns.OwnListRefresh()
    ns.OwnListPreviewPaint()
    local want = ns.OwnListOn()
    if want and not frame then Build() end
    if not frame then return end
    local cat = SP.categoryID
    -- the results are walked for secrecy only where our list could show
    local now = (want and SP:IsVisible() and OURS[cat]
        and not ((GFNS.ExtraResultsSecret and GFNS.ExtraResultsSecret()) or AnySecret())) and true or false
    if now ~= active then
        active = now
        local a = active and 0 or 1
        guard = true
        SP.ScrollBox:SetAlpha(a)
        if SP.ScrollBar then SP.ScrollBar:SetAlpha(a) end
        if SP.SearchingSpinner then SP.SearchingSpinner:SetAlpha(a) end  -- its "searching..." sat over our rows
        if signBtn then SP.SignUpButton:SetAlpha(a) end
        guard = false
        frame:SetShown(active)
        if signBtn then signBtn:SetShown(active) end
        if active then
            frame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
            frame:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
            -- keep the sign up button current
            frame:RegisterEvent("GROUP_ROSTER_UPDATE")
            frame:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
            frame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
            frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        else
            frame:UnregisterAllEvents()
            wipe(dirty)
            fullDirty = false
            flusher:Hide()
            -- blizzard's rows were left alone while ours covered them: their look again
            if ns.RedecorateRows then ns.RedecorateRows() end
        end
    end
    if active then
        -- stay over blizzard's faded list and button: if something raises them,
        -- the mouse would go to rows nobody can see
        local lv = SP.ScrollBox:GetFrameLevel() + 10
        if frame:GetFrameLevel() < lv then frame:SetFrameLevel(lv) end
        if signBtn then
            lv = SP.SignUpButton:GetFrameLevel() + 5
            if signBtn:GetFrameLevel() < lv then signBtn:SetFrameLevel(lv) end
        end
        Collect()
        Paint()
    end
end

-- our list covers blizzard's (search.lua leaves blizzard's hidden rows alone meanwhile)
function ns.OwnListActive() return active end

-- settings reset
function ns.ResetOwnList()
    wipe(DB())
    styleGen = styleGen + 1
    ns.OwnListRefresh()
end

function ns.SetOwnListRowHeight(v)
    DB().rowHeight = v
    ns.OwnListPreviewPaint()
    if active then Paint() end
end

-- filters or display changed: the rows lay out again
GFNS.ExtraRefilter = function()
    styleGen = styleGen + 1
    if active or ns.OwnListOn() then ns.OwnListRefresh() end
end
GFNS.ExtraRedecorate = GFNS.ExtraRefilter

-- menus open: dim ours too
local prevDim = GFNS.ExtraOnDim
GFNS.ExtraOnDim = function(on)
    if prevDim then prevDim(on) end
    if frame then frame:SetAlpha(on and 0.35 or 1) end
end

if ns.WhenGroupFinder then
    ns.WhenGroupFinder(function()
        local sp = LFGListFrame and LFGListFrame.SearchPanel
        if sp then
            sp:HookScript("OnShow", function()
                -- a profile switched while the window was closed brings its own sizes
                styleGen = styleGen + 1
                if ns.OwnListOn() then ns.OwnListRefresh() end
            end)
        end
    end)
end
