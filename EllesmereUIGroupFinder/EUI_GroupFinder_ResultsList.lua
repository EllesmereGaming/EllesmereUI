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
local X_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
local CANCEL_H = 18  -- smallest cancel square
local GAP = 2
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Readable(t) return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t)) end

local function DB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local t = EllesmereUIDB.extraOwnList
    if type(t) ~= "table" then
        t = {}
        EllesmereUIDB.extraOwnList = t
    end
    return t
end
function ns.OwnListOn() return ns.Enabled() end
function ns.OwnListRowHeight() return tonumber(DB().rowHeight) or 50 end
-- text sizes
local SIZE_DEFAULTS = { titleSize = 12, nameSize = 10, lineSize = 10, scoreSize = 10 }
function ns.OwnListSize(k) return tonumber(DB()[k]) or SIZE_DEFAULTS[k] end
function ns.SetOwnListSize(k, v)
    DB()[k] = v
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end
-- display settings
local DISPLAY_DEFAULTS = { iconShape = "circle", borderTexture = "solid", borderSize = 1, missingIcons = "blizzard",
    appsFirst = true, signupClicks = "double", visibility = "hidden",
    lineDelisted = false, lineAccepted = false, lineCancelled = false, lineDeclined = false }
function ns.OwnListGet(k)
    local v = DB()[k]
    if v == nil then return DISPLAY_DEFAULTS[k] end
    return v
end
-- user's border color, else the style's
function ns.OwnListBorderColor()
    local bc = ns.OwnListGet("borderColor")
    if type(bc) == "table" then return bc.r or 1, bc.g or 1, bc.b or 1 end
    local btex = ns.OwnListGet("borderTexture") or "solid"
    if btex ~= "solid" and ns.OwnListGet("iconShape") == "square" and EUI.GetBorderStyleSelectDefaults then
        local c = EUI.GetBorderStyleSelectDefaults(btex)
        return c.r, c.g, c.b
    end
    if ns.ThemeBorder then return ns.ThemeBorder() end
    return 1, 1, 1
end
function ns.SetOwnListValue(k, v)
    DB()[k] = v
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end

-- dungeons & raids background: the skin asks for this whenever it paints the window
EUI._ShellLooks = EUI._ShellLooks or {}
EUI._ShellLooks.lfg = function() return DB().windowBgColor, DB().windowBgOpacity end
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
local refreshQueued = false
local signBtn

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
local function Elapsed(at)
    local s = math.max(0, math.floor(GetTime() - at))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
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
local function Collect()
    wipe(shown)
    wipe(dimmed)
    local dim = ns.OwnListGet("visibility") == "dimmed"
    local res = SP and SP.results
    if type(res) ~= "table" then return end
    local seen, isApp = {}, {}
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
            if isApp[id] or not GFNS.ExtraPasses or GFNS.ExtraPasses(id) then
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
        local down = by == "high" or by == "big"
        local val = {}
        for _, id in ipairs(shown) do
            local info = C_LFGList.GetSearchResultInfo(id)
            local v = Readable(info) and info[field]
            val[id] = (type(v) == "number" and not Secret(v)) and v or 0
        end
        table.sort(shown, function(a, b)
            if appsFirst and isApp[a] ~= isApp[b] then return isApp[a] == true end
            if val[a] ~= val[b] then
                if down then return val[a] > val[b] end
                return val[a] < val[b]
            end
            return Pos(a) < Pos(b)
        end)
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

function ns.OwnListMenu(anchor, id)
    if not EUI.ShowContextMenu then return end
    local info = C_LFGList.GetSearchResultInfo(id)
    if not Readable(info) then return end
    local leader = info.leaderName
    if Secret(leader) then leader = nil end
    local items = {
        { text = WHISPER_LEADER or "Whisper Leader", noLoc = true,
          isDisabled = function() return not leader end,
          desc = EllesmereUI.L("Prompts in chat to whisper the party leader."),
          tooltip = not leader and (LFG_LIST_MUST_SIGN_UP_TO_WHISPER or "Sign up to whisper the leader") or nil,
          onClick = function() WhisperLeader(leader) end },
        "---",
        { text = LFG_LIST_REPORT_GROUP_FOR or "Report Group", noLoc = true,
          onClick = function() LFGList_ReportListing(id, leader) end },
        { text = REPORT_GROUP_FINDER_ADVERTISEMENT or "Report Advertisement", noLoc = true,
          onClick = function() LFGList_ReportAdvertisement(id) end },
    }
    EUI.ShowContextMenu(anchor, items)
end

-------------------------------------------------------------------------------
--  a row
-------------------------------------------------------------------------------
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
-- raid role colors
local RR_ROLES = { "TANK", "HEALER", "DAMAGER" }
local RR_COLORS = { TANK = { 0.16, 0.38, 0.78 }, HEALER = { 0.16, 0.62, 0.24 }, DAMAGER = { 0.72, 0.16, 0.16 } }
ns.RaidRoleColors = RR_COLORS
-- status text + colors
local G, R, Y = { 0.1, 1, 0.1 }, { 1, 0.25, 0.25 }, { 1, 0.82, 0 }
-- blizzard's strings have color codes baked in, strip them
local function Plain(t) return t and (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function St(text, fallback, c) return { Plain(text) or fallback, c[1], c[2], c[3] } end
local STATUS = {
    applied           = St(LFG_LIST_PENDING, "Pending", G),
    invited           = St(LFG_LIST_INVITED, "Invited", G),
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
local LINE_DELISTED  = { "lineDelisted", 0.6, 0.6, 0.6 }
local LINE_ACCEPTED  = { "lineAccepted", 0.1, 0.9, 0.1 }
local LINE_CANCELLED = { "lineCancelled", 1, 0.55, 0.1 }
local LINE_DECLINED  = { "lineDeclined", 1, 0.2, 0.2 }
local LINE_OF = {
    [STATUS.declined_delisted] = LINE_DELISTED,
    [STATUS.applied] = LINE_ACCEPTED, [STATUS.invited] = LINE_ACCEPTED, [STATUS.inviteaccepted] = LINE_ACCEPTED,
    [STATUS.cancelled] = LINE_CANCELLED,
    [STATUS.declined] = LINE_DECLINED, [STATUS.declined_full] = LINE_DECLINED, [STATUS.timedout] = LINE_DECLINED,
    [STATUS.invitedeclined] = LINE_DECLINED, [STATUS.failed] = LINE_DECLINED,
}

local function MakeRow(i)
    local r = CreateFrame("Button", nil, body)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetAllPoints()
    -- status underline
    r.under = r:CreateTexture(nil, "ARTWORK", nil, 7)
    r.under:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.under:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.under:SetHeight(2)
    r.under:Hide()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
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
    -- cancel button
    r.cancel = CreateFrame("Button", nil, r)
    r.cancel.bg = r.cancel:CreateTexture(nil, "BACKGROUND")
    r.cancel.bg:SetAllPoints()
    r.cancel.bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
    r.cancel.edge = EUI.MakeBorder(r.cancel, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
    r.cancel.tex = r.cancel:CreateTexture(nil, "OVERLAY")
    r.cancel.tex:SetTexture(X_TEX)
    r.cancel.tex:SetPoint("CENTER")
    r.cancel.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
    r.cancel:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 0.3, 0.3, 1)
        if self.edge and self.edge.SetColor then self.edge:SetColor(1, 0.3, 0.3, 1) end
        EUI.ShowWidgetTooltip(self, CANCEL_SIGN_UP or "Cancel Sign Up")
    end)
    r.cancel:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(0.8, 0.8, 0.8, 1)
        if self.edge and self.edge.SetColor then self.edge:SetColor(0.25, 0.25, 0.25, 1) end
        EUI.HideWidgetTooltip()
    end)
    r.cancel:SetScript("OnClick", function(self)
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
    -- raid role counts
    r.rr = {}
    for k = 1, 3 do
        local bg = r:CreateTexture(nil, "ARTWORK", nil, 1)
        local mask = r:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(bg)
        local t = r:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetPoint("CENTER", bg)
        local c = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c:SetJustifyH("CENTER")
        bg:Hide(); t:Hide(); c:Hide()
        r.rr[k] = { bg = bg, mask = mask, icon = t, count = c }
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
        local id = self.resultID
        if not id or not active then return end
        if button == "RightButton" then return ns.OwnListMenu(self, id) end
        local now = GetTime()
        if lastClickID == id and (now - lastClickTime) < 0.4 then clickCount = clickCount + 1 else clickCount = 1 end
        lastClickID, lastClickTime = id, now
        local need = ({ single = 1, double = 2, triple = 3 })[ns.OwnListGet("signupClicks")] or 2
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
        if not self.resultID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 25, 0)
        LFGListUtil_SetSearchEntryTooltip(GameTooltip, self.resultID)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

local function SetSize(fs, size)
    local ok, path, _, flags = pcall(fs.GetFont, fs)
    if ok and path then fs:SetFont(path, size, flags or "") end
end

local function IconSize(h)
    -- 16px at 100%, 1px per 5%
    local c = GFNS.Cfg and GFNS.Cfg()
    local pct = tonumber(c and c.iconSize) or (GFNS.DEFAULTS and GFNS.DEFAULTS.iconSize) or 125
    return math.max(8, math.min(h - 4, 16 + math.floor((pct - 100) / 5 + 0.5)))
end

ns.OwnListIconSize = IconSize

local function Layout(r, h)
    local pad = 6
    local tS, nS, lS = ns.OwnListSize("titleSize"), ns.OwnListSize("nameSize"), ns.OwnListSize("lineSize")
    SetSize(r.name, tS)
    SetSize(r.act, nS)
    for _, fs in ipairs({ r.sep1, r.style, r.sep2, r.tag, r.sep3, r.timer }) do SetSize(fs, lS) end
    -- title always fits, then the dungeon, then line three
    local room = h - 4
    local lines = { tS + 2 }
    if room >= tS + nS + 6 then lines[2] = nS + 2 end
    local gc = GFNS.Cfg and GFNS.Cfg()
    local third = not (gc and gc.extraShowPlaystyle == false)
        or (gc and gc.extraRegionTags ~= false and ns.RegionList() ~= nil)
    if lines[2] and third and room >= tS + nS + lS + 10 then lines[3] = lS + 2 end
    local total = 0
    for _, lh in ipairs(lines) do total = total + lh end
    total = total + (#lines - 1) * 2
    local y = math.floor((h - total) / 2)
    r.lineY = {}
    for i, lh in ipairs(lines) do
        r.lineY[i] = y
        y = y + lh + 2
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
    r.cancel.tex:SetSize(math.floor(cs * 0.45 + 0.5), math.floor(cs * 0.45 + 0.5))
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
        t:SetPoint("RIGHT", r, "RIGHT", x, 0)
        x = x - isz - gap
    end
    r.score:ClearAllPoints()
    r.score:SetPoint("RIGHT", r, "RIGHT", x - 4, 0)
    r.status:ClearAllPoints()
    r.status:SetPoint("RIGHT", r.score, "LEFT", -8, 0)
    r.name:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
    r.act:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
end

-- line three: playstyle | region | time since you signed up
local function LineThree(r, id, info)
    for _, p in ipairs({ r.sep1, r.style, r.sep2, r.tag, r.flag, r.sep3, r.timer }) do p:Hide() end
    r.signedAt = nil
    if (r.lines or 0) < 3 then return end
    local style = ""
    local ps = info.generalPlaystyle
    local gc = GFNS.Cfg and GFNS.Cfg()
    if not (gc and gc.extraShowPlaystyle == false) and type(ps) == "number" and not Secret(ps) then
        style = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. ps] or ""
    end
    local tag, tr, tg, tb, flag
    if ns.RegionTagOf then tag, tr, tg, tb, flag = ns.RegionTagOf(id) end
    local prev
    local function Put(p, gap)
        p:ClearAllPoints()
        if prev then p:SetPoint("LEFT", prev, "RIGHT", gap, 0)
        else p:SetPoint("TOPLEFT", r, "TOPLEFT", r.textX or r.pad, -r.lineY[3]) end
        p:Show()
        prev = p
    end
    if style ~= "" then
        r.style:SetText(style)
        Put(r.style)
    end
    if tag then
        if prev then Put(r.sep2, 4) end
        r.tag:SetText(tag)
        r.tag:SetTextColor(tr, tg, tb, 1)
        Put(r.tag, 4)
        if flag then
            local fh = math.max(8, ns.OwnListSize("lineSize"))
            r.flag:SetSize(math.floor(fh * 4 / 3 + 0.5), fh)
            r.flag:SetTexture(flag)
            Put(r.flag, 4)
        end
    end
    local at = SignedUpAt(id)
    if at then
        if prev then Put(r.sep3, 4) end
        r.timer:SetText(Elapsed(at))
        Put(r.timer, 4)
        r.signedAt = at
    end
end

local function Fill(r, id)
    r.resultID = id
    local info = C_LFGList.GetSearchResultInfo(id)
    if not Readable(info) then r:Hide() return end
    -- protected text, straight to the font string
    r.name:SetText(info.name)
    local acts = info.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    local ai = act and not Secret(act) and C_LFGList.GetActivityInfoTable(act)
    if not Readable(ai) then ai = nil end
    -- colored group names
    local nr, ng, nb
    if ns.GFNameColor then nr, ng, nb = ns.GFNameColor(id, info, ai) end  -- "and" would drop g and b
    if nr then r.name:SetTextColor(nr, ng, nb) else r.name:SetTextColor(1, 0.82, 0) end
    r.act:SetText(ai and ai.fullName or "")
    -- signed up: the cancel square sits left of the text, which moves over for it
    local appStatus = AppStatus(id)
    local canCancel = appStatus == "applied"
    local x0 = r.pad or 6
    r.cancel:ClearAllPoints()
    if canCancel then
        r.cancel:SetPoint("LEFT", r, "LEFT", x0, 0)
        x0 = x0 + (r.cancelSize or CANCEL_H) + 6
    end
    r.cancel:SetShown(canCancel)
    r.textX = x0
    if r.act:IsShown() then
        r.act:SetPoint("TOPLEFT", r, "TOPLEFT", x0, -(r.lineY and r.lineY[2] or 0))
    end
    local short = (r.lines or 0) < 2 and ai and ns.GFShortName(ai.fullName)
    if short and short ~= "" then
        local ok, path, size, flags = pcall(r.name.GetFont, r.name)
        if ok and path then r.short:SetFont(path, size, flags or "") end
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
    LineThree(r, id, info)
    local Opt = ns.GFOpt or function() return true end
    local score = info.leaderOverallDungeonScore
    if Opt("leaderRating") and type(score) == "number" and not Secret(score) and score > 0 then
        -- raider.io or game colors
        local cr, cg, cb = 1, 1, 1
        if ns.GFRatingColor then cr, cg, cb = ns.GFRatingColor(score) end
        r.score:SetText(score)
        r.score:SetTextColor(cr, cg, cb)
    else
        r.score:SetText("")
    end
    local st = appStatus and STATUS[appStatus]
    local delisted = info.isDelisted
    if not Secret(delisted) and delisted then st = STATUS.declined_delisted end  -- secret check first
    if st then
        r.status:SetText(st[1])
        -- same color as the underline
        local c = LINE_OF[st] or st
        r.status:SetTextColor(c[2], c[3], c[4], 1)
    else
        r.status:SetText("")
    end
    -- underline per status
    local line = st and LINE_OF[st]
    if line and ns.OwnListGet(line[1]) ~= false then
        r.under:SetColorTexture(line[2], line[3], line[4], 0.9)
        r.under:Show()
    else
        r.under:Hide()
    end
    -- row art
    local art = ns.RowArtFor and ns.RowArtFor(id)
    if art and ns.ROW_ART then
        local w = r:GetWidth() or 0
        r.art:SetTexture(art)
        r.art:SetTexCoord(unpack(ns.ROW_ART.crop))
        r.art:ClearAllPoints()
        r.art:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
        r.art:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
        r.art:SetWidth(math.max(1, math.floor(w * ns.ROW_ART.share)))
        r.art:Show()
    else
        r.art:Hide()
    end
    -- members, tanks first
    local members = {}
    local n = info.numMembers
    if type(n) == "number" and not Secret(n) then
        for k = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(id, k)
            if Readable(p) and p.classFilename and not Secret(p.classFilename) then
                local spec = p.specName
                if Secret(spec) then spec = nil end
                local lead = p.isLeader
                if Secret(lead) then lead = nil end
                local role = p.assignedRole
                if Secret(role) then role = nil end
                members[#members + 1] = { cls = p.classFilename, role = role, spec = spec, lead = lead, k = k }
            end
        end
    end
    table.sort(members, function(a, b)
        local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
        if ra ~= rb then return ra < rb end
        return a.k < b.k
    end)
    local cap = ai and ai.maxNumPlayers or 5
    -- open roles for the empty slots
    local needs = {}
    if ns.OwnListGet("missingIcons") ~= "none" and cap == 5 then
        local counts = C_LFGList.GetSearchResultMemberCounts(id)
        if Readable(counts) then
            for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
                local left = counts[role .. "_REMAINING"]
                if type(left) == "number" and not Secret(left) then
                    for _ = 1, left do needs[#needs + 1] = role end
                end
            end
        end
    end
    local NEED_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal",
        DAMAGER = "groupfinder-icon-role-micro-dps" }
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
    elseif btex ~= "solid" and square and EUI.GetBorderStyleSelectDefaults then
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
        role:SetDesaturated(false)
        role:SetAlpha(1)
        bf:Hide()
        if t._masked then t:RemoveMaskTexture(r.masks[k]); t._masked = nil end
        t:SetTexCoord(0, 1, 0, 1)
        t:SetDesaturated(false)
        if cap > 5 then
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
                    if bf._key ~= bkey and EUI.ApplyBorderStyle then
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
    local counts = cap > 5 and C_LFGList.GetSearchResultMemberCounts(id)
    if not Readable(counts) then counts = nil end
    local ellIcons = ns.OwnListGet("missingIcons") == "ellesmere"
    local x = -(r.pad or 6)
    local isz = r.icons[1]:GetWidth() or 16
    local fsz = ns.OwnListSize("scoreSize")
    local round = ns.OwnListGet("iconShape") ~= "square"
    for k = 3, 1, -1 do
        local p = r.rr[k]
        local role = RR_ROLES[k]
        local num = counts and counts[role]
        if counts and type(num) == "number" and not Secret(num) then
            -- icon centered, count above
            local c = RR_COLORS[role]
            p.bg:SetColorTexture(c[1], c[2], c[3], 1)
            if round and not p.masked then p.bg:AddMaskTexture(p.mask); p.masked = true
            elseif not round and p.masked then p.bg:RemoveMaskTexture(p.mask); p.masked = nil end
            p.bg:SetSize(isz, isz)
            p.bg:ClearAllPoints()
            p.bg:SetPoint("RIGHT", r, "RIGHT", x, 0)
            p.bg:Show()
            local tex = ellIcons and ns.RoleIconTex and ns.RoleIconTex(role)
            if tex then p.icon:SetTexture(tex) else p.icon:SetAtlas(NEED_ATLAS[role]) end
            local gsz = math.floor(isz * 0.7 + 0.5)
            p.icon:SetSize(gsz, gsz)
            p.icon:Show()
            SetSize(p.count, fsz)
            p.count:SetText(num)
            p.count:ClearAllPoints()
            p.count:SetPoint("BOTTOM", p.bg, "TOP", 0, 1)
            p.count:Show()
            x = x - math.max(isz, math.ceil(p.count:GetStringWidth() or 8)) - 6
        else
            p.bg:Hide(); p.icon:Hide(); p.count:Hide()
        end
    end
    if counts then
        r.score:ClearAllPoints()
        r.score:SetPoint("RIGHT", r, "RIGHT", x - 6, 0)
    end
    local ar, ag, ab = Accent()
    r.sel:SetColorTexture(ar, ag, ab, selected == id and 0.18 or 0)
    if dimmed[id] then r:SetAlpha(0.35)
    else r:SetAlpha((st and st ~= STATUS.applied and st ~= STATUS.invited) and 0.5 or 1) end
    r:Show()
end

-------------------------------------------------------------------------------
--  the list
-------------------------------------------------------------------------------
local empty, thumb

function Paint()  -- forward-declared up top
    if not (frame and active) then return end
    local h = ns.OwnListRowHeight()
    local height = body:GetHeight() or 0
    local per = h + GAP
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
        r:SetHeight(h)
        if id and y < height then
            Layout(r, h)
            Fill(r, id)
        else
            r.resultID = nil
            r:Hide()
        end
    end
    for i = slots + 1, #rows do rows[i]:Hide() end
    PaintSignBtn()
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

local function Build()
    if frame then return end
    SP = LFGListFrame and LFGListFrame.SearchPanel
    if not (SP and SP.ScrollBox) then return end
    frame = CreateFrame("Frame", nil, SP)
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
        signBtn = CreateFrame("Button", nil, SP)
        signBtn:SetAllPoints(sb)
        signBtn:SetFrameLevel(sb:GetFrameLevel() + 5)
        signBtn:SetNormalFontObject("GameFontNormal")
        signBtn:SetHighlightFontObject("GameFontHighlight")
        signBtn:SetDisabledFontObject("GameFontDisable")
        signBtn:SetText(SIGN_UP or "Sign Up")
        signBtn:SetMotionScriptsWhileDisabled(true)
        local skin = EUI._ModuleNS and EUI._ModuleNS.EllesmereUIBlizzardSkin
        local S = skin and skin.WSkin
        if S and S.Button then
            S.Button(signBtn)
        else
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
    -- sign up timers tick once a second, just their text
    local tick = 0
    frame:SetScript("OnUpdate", function(_, dt)
        tick = tick + dt
        if tick < 1 then return end
        tick = 0
        for _, r in ipairs(rows) do
            if r.signedAt and r:IsShown() then r.timer:SetText(Elapsed(r.signedAt)) end
        end
    end)
    frame:SetScript("OnEvent", function(_, event)
        if event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            -- results can go secret mid-list, recheck once per frame
            if not refreshQueued then
                refreshQueued = true
                C_Timer.After(0, function() refreshQueued = false; ns.OwnListRefresh() end)
            end
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
        if Secret(id) then return true end
        local info = C_LFGList.GetSearchResultInfo(id)
        if info and (not Readable(info) or Secret(info.activityIDs) or Secret(info.isDelisted)) then return true end
    end
    return false
end

-- ours only on dungeon / raid / delve searches with readable results
function ns.OwnListRefresh()
    local want = ns.OwnListOn()
    if want and not frame then Build() end
    if not frame then return end
    local cat = SP.categoryID
    local secret = (GFNS.ExtraResultsSecret and GFNS.ExtraResultsSecret()) or AnySecret()
    local now = want and SP:IsVisible() and (cat == DUNGEONS or cat == RAIDS or cat == DELVES) and not secret
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
        end
    end
    if active then
        Collect()
        Paint()
    end
end

-- settings reset: these live outside the profile
function ns.ResetOwnList()
    wipe(DB())
    ns.OwnListRefresh()
end

function ns.SetOwnListRowHeight(v)
    DB().rowHeight = v
    if active then Paint() end
end

-- filters or display changed
GFNS.ExtraRefilter = function() if active or ns.OwnListOn() then ns.OwnListRefresh() end end
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
            sp:HookScript("OnShow", function() if ns.OwnListOn() then ns.OwnListRefresh() end end)
        end
    end)
end
