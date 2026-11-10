if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ApplicantList.lua - our own applicant list
--  blizzard's list stays alive underneath, faded out. we only read the
--  applicants and draw them with more columns, nothing written to blizzard's
--  panel. secret values: we step aside. without leader rights it's the same
--  list under our own "group forming" cover, no buttons.
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
local EUI = EllesmereUI

local GAP, ROLE_GAP = 2, 4
local BOX_RIGHT = 29  -- blizzard's list stops this far from the panel's right edge
local HOME = LE_PARTY_CATEGORY_HOME
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps" }
local BAD = EllesmereUI.COLOR_CODES.BAD

-- right to left from the buttons, the name takes what's left
local SPEC_COL = { key = "spec", title = EllesmereUI.L("Spec"), w = 26 }
local ROLE_COL = { key = "role", title = ROLE or "Role", w = 44 }
local ILVL_COL = { key = "ilvl", title = ITEM_LEVEL_ABBR or "iLvl", w = 34 }
local RATING_COL = { key = "rating", title = RATING or "Rating", w = 44 }
local KEY_COL = { key = "best", title = EllesmereUI.L("Key"), w = 36 }
local COLS_BASE = { SPEC_COL, ROLE_COL, ILVL_COL }
local COLS_KEYS = { SPEC_COL, ROLE_COL, ILVL_COL, RATING_COL, KEY_COL }
local COLS_PVP = { SPEC_COL, ROLE_COL, ILVL_COL, RATING_COL }

local Secret = EllesmereUI.IsSecret
local function Readable(t) return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t)) end

local AV, frame, head, body, thumb, empty, cover, raidRoles
local VisibleCols
local active, guard = false, false
local blocks, list = {}, {}
local cols, baseCols = COLS_BASE, COLS_BASE
local entryActivity
local empowered = false
local rowH, btnSize, btnRoom, iconPx = 36, 20, 50, 21
local layoutKey
local scrollPx = 0

-- the applicant list runs whenever the module does
function ns.ApplicantListOn() return ns.Enabled() end

-- where the rows read their applicants from: the game, or the settings
-- preview's samples while it paints (then put straight back)
local LIVE = {
    info = function(id) return C_LFGList.GetApplicantInfo(id) end,
    member = function(id, k) return C_LFGList.GetApplicantMemberInfo(id, k) end,
    best = function(id, k) return C_LFGList.GetApplicantBestDungeonScore(id, k) end,
    counts = function() return GetGroupMemberCountsForDisplay() end,
}
local src = LIVE

-------------------------------------------------------------------------------
--  reading
-------------------------------------------------------------------------------
-- +12, red when it wasn't timed
local function KeyText(s)
    if not Readable(s) then return "-" end
    local lvl, done = s.bestRunLevel, s.finishedSuccess
    if Secret(lvl) or Secret(done) or type(lvl) ~= "number" or lvl == 0 then return "-" end
    return (done and "" or BAD) .. "+" .. lvl .. (done and "" or "|r")
end

local function ActiveActivity()
    local entry = C_LFGList.GetActiveEntryInfo()
    local acts = Readable(entry) and entry.activityIDs
    local act = Readable(acts) and acts[1]
    if not act or Secret(act) then return nil end
    return act, C_LFGList.GetActivityInfoTable(act)
end

-- any applicant value hidden from us? hand back to blizzard's list.
-- status and member count never go secret, the rest can
local function AnySecret()
    local apps = C_LFGList.GetApplicants()
    if not apps then return false end
    if not Readable(apps) then return true end
    for _, id in ipairs(apps) do
        if Secret(id) then return true end
        local info = C_LFGList.GetApplicantInfo(id)
        if info then
            if not Readable(info) then return true end
            for k = 1, info.numMembers or 0 do
                local name, class, _, _, ilvl, _, tank, healer, damage, role, _, score, pvpIlvl, _, _, specID = C_LFGList.GetApplicantMemberInfo(id, k)
                if Secret(name) or Secret(class) or Secret(ilvl) or Secret(tank) or Secret(healer)
                    or Secret(damage) or Secret(role) or Secret(score) or Secret(pvpIlvl) or Secret(specID) then return true end
            end
        end
    end
    return false
end

-- these drop off the list
local DECLINED = { declined = true, declined_full = true, declined_delisted = true, invitedeclined = true }

-- blizzard's order: new ones at the bottom. a secret field keeps the order we got
local isNew, order = {}, {}  -- by applicant, refilled by every collect
local function ByOrder(a, b)
    if isNew[a] ~= isNew[b] then return isNew[b] end
    if order[a] ~= order[b] then return order[a] < order[b] end
    return a < b
end
local function Collect()
    wipe(list)
    wipe(isNew)
    wipe(order)
    local apps = C_LFGList.GetApplicants()
    if not Readable(apps) then return end
    local sortable = true
    for _, id in ipairs(apps) do
        local info = C_LFGList.GetApplicantInfo(id)
        if Readable(info) and not (DECLINED[info.applicationStatus] and not info.pendingApplicationStatus) then
            list[#list + 1] = id
            if Secret(info.isNew) or Secret(info.displayOrderID) then
                sortable = false
            else
                isNew[id] = info.isNew and true or false
                order[id] = info.displayOrderID or 0
            end
        end
    end
    if not sortable then return end
    table.sort(list, ByOrder)
end

-------------------------------------------------------------------------------
--  buttons
-------------------------------------------------------------------------------
local function DoInvite(id)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    C_LFGList.InviteApplicant(id)
end

local function Invite(self)
    local b = self:GetParent()
    local id = b.applicantID
    if not id or b.preview then return end
    -- going past 5 needs a raid: our own popup, blizzard's would carry our taint
    if not IsInRaid(HOME) and GetNumGroupMembers(HOME) + (b.numMembers or 1) + C_LFGList.GetNumInvitedApplicantMembers() > (MAX_PARTY_MEMBERS or 4) + 1 then
        EUI:ShowConfirmPopup({
            title = INVITE or "Invite",
            message = LFG_LIST_CONVERT_TO_RAID_WARNING or "Inviting this player will convert your party to a raid.",
            confirmText = INVITE or "Invite",
            onConfirm = function()
                C_PartyInfo.ConfirmConvertToRaid()
                DoInvite(id)
            end,
        })
        return
    end
    DoInvite(id)
end

local function Decline(self)
    local b = self:GetParent()
    local id = b.applicantID
    if not id or b.preview then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if b.appStatus == "applied" or b.appStatus == "invited" then
        C_LFGList.DeclineApplicant(id)
    else
        C_LFGList.RemoveApplicant(id)
    end
end

-- icon lives on a child frame, the skin's restrip fades direct textures
local function SquareButton(parent, atlas, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetMotionScriptsWhileDisabled(true)
    local skin = EUI._ModuleNS and EUI._ModuleNS.EllesmereUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(btn)
    else
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        EUI.MakeBorder(btn, 0.25, 0.25, 0.25, 1, EUI.PanelPP)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    local holder = CreateFrame("Frame", nil, btn)
    holder:SetAllPoints()
    holder:SetFrameLevel(btn:GetFrameLevel() + 2)
    btn.icon = holder:CreateTexture(nil, "OVERLAY")
    btn.icon:SetAtlas(atlas)
    btn.icon:SetPoint("CENTER")
    btn:SetScript("OnClick", onClick)
    -- the row stays lit while the mouse is on its buttons
    btn:SetScript("OnEnter", function(self)
        for _, l in ipairs(parent.lines) do l:LockHighlight() end
        if self.tip then EUI.ShowWidgetTooltip(self, self.tip) end
    end)
    btn:SetScript("OnLeave", function()
        for _, l in ipairs(parent.lines) do l:UnlockHighlight() end
        EUI.HideWidgetTooltip()
    end)
    return btn
end

local function SizeSquare(btn)
    btn:SetSize(btnSize, btnSize)
    local px = math.floor(btnSize * 0.42)
    btn.icon:SetSize(px, px)
end

-------------------------------------------------------------------------------
--  right-click menu + tooltip
-------------------------------------------------------------------------------
-- a player link in chat: clicking it is blizzard's own whisper
local function WhisperLink(name)
    local full = EUI.BuildFullName(name) or name
    if not (full and DEFAULT_CHAT_FRAME) then return end
    local link = "|Hplayer:" .. full .. "|h[" .. full .. "]|h"
    DEFAULT_CHAT_FRAME:AddMessage(EllesmereUI.Lf("Click to whisper the applicant: %1$s", link), 1, 0.82, 0)
end

local function LineMenu(line)
    local id = line:GetParent().applicantID
    if not id or line:GetParent().preview then return end
    local name = C_LFGList.GetApplicantMemberInfo(id, line.memberIdx)
    if Secret(name) then name = nil end
    -- both of these print the name in chat
    local hidden = ns.OwnListGet("streamerNames")
    -- names shown: blizzard's tagged menu, so other add-ons' entries (raider.io's
    -- copy link and so on) still show. names hidden: ours, they'd show the name
    if not hidden then
        MenuUtil.CreateContextMenu(line, function(_, root)
            root:SetTag("MENU_LFG_FRAME_MEMBER_APPLY")
            root:CreateTitle(name or "")
            local w = root:CreateButton(WHISPER or "Whisper", function() WhisperLink(name) end)
            root:CreateButton(LFG_LIST_REPORT_PLAYER or "Report Player", function() LFGList_ReportApplicant(id, name or "") end)
            local ig = root:CreateButton(IGNORE_PLAYER or "Ignore Player", function()
                C_FriendList.AddIgnore(name)
                C_LFGList.DeclineApplicant(id)
            end)
            if not name then
                w:SetEnabled(false)
                ig:SetEnabled(false)
            end
        end)
        return
    end
    EUI.ShowContextMenu(line, {
        { text = WHISPER or "Whisper", noLoc = true,
          isDisabled = function() return hidden or not name end,
          onClick = function() WhisperLink(name) end },
        { text = LFG_LIST_REPORT_PLAYER or "Report Player", noLoc = true,
          onClick = function() LFGList_ReportApplicant(id, name or "") end },
        { text = IGNORE_PLAYER or "Ignore Player", noLoc = true,
          isDisabled = function() return hidden or not name end,
          onClick = function()
              C_FriendList.AddIgnore(name)
              C_LFGList.DeclineApplicant(id)
          end },
    })
end

-- blizzard's would show what's hidden, this one only has what's still allowed
local function PrivateTooltip(line, id)
    local k = line.memberIdx
    local name, class, localClass, _, ilvl, _, _, _, _, _, _, score, pvpIlvl, _, _, specID = C_LFGList.GetApplicantMemberInfo(id, k)
    local cc = class and RAID_CLASS_COLORS[class]
    local r, g, b = 1, 1, 1
    if cc then r, g, b = cc.r, cc.g, cc.b end
    GameTooltip:SetOwner(line, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 105, 0)
    local shown = ns.OwnListGet("streamerNames") and localClass or name
    GameTooltip:SetText(shown or " ", r, g, b)
    if not ns.OwnListGet("streamerSpec") and type(specID) == "number" and specID > 0 then
        local specName = select(2, GetSpecializationInfoByID(specID))
        if specName then GameTooltip:AddLine(specName, 1, 1, 1) end
    end
    local gear = entryActivity and entryActivity.isPvpActivity and pvpIlvl or ilvl
    if type(gear) == "number" then
        GameTooltip:AddDoubleLine(ITEM_LEVEL_ABBR or "iLvl", math.floor(gear), 1, 0.82, 0, 1, 1, 1)
    end
    if not ns.OwnListGet("streamerRating") and baseCols == COLS_KEYS and type(score) == "number" then
        GameTooltip:AddDoubleLine(RATING or "Rating", score, 1, 0.82, 0, 1, 1, 1)
    end
    local info = C_LFGList.GetApplicantInfo(id)
    local comment = Readable(info) and info.comment
    if not ns.OwnListGet("streamerNote") and type(comment) == "string" and not Secret(comment) and comment ~= "" then
        GameTooltip:AddLine(" ")
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        GameTooltip:AddLine(string.format(LFG_LIST_COMMENT_FORMAT or "%s", comment), fc and fc.r or 0.6, fc and fc.g or 0.6, fc and fc.b or 0.6, true)
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  raider.io: its lines on the hover tooltip, and its full profile next to the
--  window while shift is held (its own side panel only follows blizzard's
--  rows). public api only, nothing happens without raider.io
-------------------------------------------------------------------------------
local rioApi, rioTip, rioWatch, rioLine
local function Rio()
    if rioApi == nil then rioApi = _G.RaiderIO or false end
    return rioApi and type(rioApi.ShowProfile) == "function" and rioApi or nil
end

-- the hovered applicant's name and realm, nil when hidden or unreadable
local function RioWho(line)
    if ns.OwnListGet("streamerNames") or ns.OwnListGet("streamerRating") then return end
    local id = line:GetParent().applicantID
    if not id or Secret(id) then return end
    local full, class = C_LFGList.GetApplicantMemberInfo(id, line.memberIdx)
    if type(full) ~= "string" or Secret(full) or full == "" then return end
    local name, realm = strsplit("-", full, 2)
    return name, realm or GetNormalizedRealmName(), not Secret(class) and class or nil
end

local function RioLines(line)
    local api = Rio()
    local name, realm = RioWho(line)
    if not (api and name and GameTooltip:IsOwned(line)) then return end
    local ok, altered = pcall(api.ShowProfile, GameTooltip, name, realm)
    if ok and altered then GameTooltip:Show() end
end

local function RioPanel()
    local api, name, realm, class = Rio(), nil, nil, nil
    if rioLine and rioLine:IsVisible() and IsShiftKeyDown() then name, realm, class = RioWho(rioLine) end
    if not (api and name) then
        if rioTip then rioTip:Hide() end
        return
    end
    rioTip = rioTip or CreateFrame("GameTooltip", "EllesmereUIGroupFinderRioTip", UIParent, "SharedTooltipTemplate")
    local anchor = PVEFrame or AV
    rioTip:SetOwner(anchor, "ANCHOR_NONE")
    rioTip:ClearAllPoints()
    rioTip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    local cc = class and EUI.GetClassColor(class)
    rioTip:SetText(name, cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1)
    local ok, altered = pcall(api.ShowProfile, rioTip, name, realm)
    if ok and altered then rioTip:Show() else rioTip:Hide() end
end

-- shift is only watched while an applicant is hovered
local function RioEnter(line)
    if not Rio() then return end
    rioLine = line
    if not rioWatch then
        rioWatch = CreateFrame("Frame")
        rioWatch:SetScript("OnEvent", RioPanel)
    end
    rioWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
    RioPanel()
end

local function RioLeave()
    rioLine = nil
    if rioWatch then rioWatch:UnregisterEvent("MODIFIER_STATE_CHANGED") end
    if rioTip then rioTip:Hide() end
end

local PvTip  -- the settings preview's tooltip (below)

-- blizzard's own applicant tooltip unless something's hidden
local function LineEnter(line)
    if line:GetParent().preview then return PvTip(line) end
    local id = line:GetParent().applicantID
    -- values can go secret between repaints, the next one hands over to blizzard's list
    if not (id and LFGListApplicantMember_OnEnter) or AnySecret() then return end
    if ns.OwnListGet("streamerNote") or ns.OwnListGet("streamerNames")
        or ns.OwnListGet("streamerRating") or ns.OwnListGet("streamerSpec") then
        PrivateTooltip(line, id)
    else
        pcall(LFGListApplicantMember_OnEnter, line)
    end
    RioLines(line)
    RioEnter(line)
end

local function LineLeave()
    GameTooltip_Hide()
    RioLeave()
end

-------------------------------------------------------------------------------
--  an applicant
-------------------------------------------------------------------------------
local function MakeLine(b, k)
    local l = CreateFrame("Button", nil, b)
    l:RegisterForClicks("RightButtonUp")
    l.memberIdx = k
    l.hl = l:CreateTexture(nil, "HIGHLIGHT")
    l.hl:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 0)
    l.hl:SetColorTexture(1, 1, 1, 0.06)
    l.leaver = l:CreateTexture(nil, "ARTWORK")
    l.leaver:SetAtlas("groupfinder-icon-leaver")
    l.leaver:SetSize(12, 12)
    l.friend = l:CreateTexture(nil, "ARTWORK")
    l.friend:SetAtlas("groupfinder-icon-friend")
    l.friend:SetSize(14, 14)
    l.name = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l.name:SetJustifyH("LEFT")
    l.name:SetWordWrap(false)
    l.bullet = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.bullet:SetText("\226\128\162")
    l.bullet:SetTextColor(0.6, 0.6, 0.6)
    l.region = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l.region:SetPoint("TOPLEFT", l.name, "BOTTOMLEFT", 0, -2)
    l.regionFlag = l:CreateTexture(nil, "ARTWORK")
    l.regionFlag:SetPoint("LEFT", l.region, "RIGHT", 4, 0)
    l.cells = {}
    for _, key in ipairs({ "ilvl", "rating", "best" }) do
        local fs = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        l.cells[key] = fs
    end
    -- spec icon, same looks as the results list's
    l.spec = l:CreateTexture(nil, "ARTWORK", nil, 2)
    l.specRing = l:CreateTexture(nil, "ARTWORK", nil, 1)
    l.specRing:Hide()
    local ringMask = l:CreateMaskTexture()
    ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ringMask:SetAllPoints(l.specRing)
    l.specRing:AddMaskTexture(ringMask)
    l.specMask = l:CreateMaskTexture()
    l.specMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    l.specMask:SetAllPoints(l.spec)
    l.specBorder = CreateFrame("Frame", nil, l)
    l.specBorder:SetAllPoints(l.spec)
    l.specBorder:EnableMouse(false)
    l.specBorder:Hide()
    -- own role buttons, the leader can switch an applicant's role
    l.roles = {}
    for i = 1, 3 do
        local rb = CreateFrame("Button", nil, l)
        rb.tex = rb:CreateTexture(nil, "ARTWORK")
        rb.tex:SetPoint("CENTER")
        -- colored tile behind it, border like the spec icon's
        rb.bg = rb:CreateTexture(nil, "BACKGROUND")
        rb.bg:SetAllPoints()
        rb.bg:Hide()
        rb.ring = rb:CreateTexture(nil, "BACKGROUND", nil, -1)
        local ringMask = rb:CreateMaskTexture()
        ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ringMask:SetAllPoints(rb.ring)
        rb.ring:AddMaskTexture(ringMask)
        rb.ring:Hide()
        rb.border = CreateFrame("Frame", nil, rb)
        rb.border:SetAllPoints()
        rb.border:EnableMouse(false)
        rb.border:Hide()
        rb.mask = rb:CreateMaskTexture()
        rb.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        rb.mask:SetAllPoints(rb.bg)
        rb:SetMotionScriptsWhileDisabled(true)
        rb:SetScript("OnClick", function(self)
            local parent = self:GetParent()
            local id = parent:GetParent().applicantID
            if id and self.role and not parent:GetParent().preview then
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                C_LFGList.SetApplicantMemberRole(id, parent.memberIdx, self.role)
            end
        end)
        rb:SetScript("OnEnter", function(self)
            local line = self:GetParent()
            line:LockHighlight()
            LineEnter(line)
        end)
        rb:SetScript("OnLeave", function(self)
            self:GetParent():UnlockHighlight()
            GameTooltip_Hide()
        end)
        l.roles[i] = rb
    end
    l:SetScript("OnClick", LineMenu)
    l:SetScript("OnEnter", LineEnter)
    l:SetScript("OnLeave", LineLeave)
    b.lines[k] = l
    return l
end

local function MakeBlock(i, parent, store)
    local b = CreateFrame("Frame", nil, parent or body)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.03)
    -- status underline
    b.under = b:CreateTexture(nil, "ARTWORK", nil, 7)
    b.under:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.under:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.under:SetHeight(2)
    b.under:Hide()
    b.lines = {}
    b.note = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.note:SetJustifyH("LEFT")
    b.note:SetWordWrap(true)
    -- the note's part of the row: same highlight, tooltip and menu
    b.noteHit = CreateFrame("Button", nil, b)
    b.noteHit:SetAllPoints(b.note)
    b.noteHit:RegisterForClicks("RightButtonUp")
    b.noteHit:SetScript("OnClick", function() LineMenu(b.lines[1]) end)
    b.noteHit:SetScript("OnEnter", function()
        for _, l in ipairs(b.lines) do l:LockHighlight() end
        LineEnter(b.lines[1])
    end)
    b.noteHit:SetScript("OnLeave", function()
        for _, l in ipairs(b.lines) do l:UnlockHighlight() end
        GameTooltip_Hide()
    end)
    b.decline = SquareButton(b, "groupfinder-icon-redx", Decline)
    b.invite = SquareButton(b, "groupfinder-icon-greencheckmark", Invite)
    b.invite:SetPoint("RIGHT", b.decline, "LEFT", -GAP, 0)
    b.decline.tip = DECLINE or "Decline"
    b.status = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.status:SetJustifyH("RIGHT")
    local into = store or blocks
    into[i] = b
    return b
end

-- text, color, the results list's underline setting
local STATUS = {
    invited        = { LFG_LIST_APP_INVITED or "Invited", 0.1, 0.9, 0.1, "lineAccepted" },
    inviteaccepted = { LFG_LIST_APP_INVITE_ACCEPTED or "Invite Accepted", 0.1, 0.9, 0.1, "lineAccepted" },
    invitedeclined = { LFG_LIST_APP_INVITE_DECLINED or "Invite Declined", 1, 0.2, 0.2, "lineDeclined" },
    failed         = { LFG_LIST_APP_CANCELLED or "Cancelled", 1, 0.55, 0.1, "lineCancelled" },
    cancelled      = { LFG_LIST_APP_CANCELLED or "Cancelled", 1, 0.55, 0.1, "lineCancelled" },
    declined       = { LFG_LIST_APP_DECLINED or "Declined", 1, 0.2, 0.2, "lineDeclined" },
    declined_full  = { LFG_LIST_APP_DECLINED or "Declined", 1, 0.2, 0.2, "lineDeclined" },
    declined_delisted = { LFG_LIST_APP_DECLINED or "Declined", 0.6, 0.6, 0.6, "lineDelisted" },
    timedout       = { LFG_LIST_APP_TIMED_OUT or "Timed Out", 1, 0.2, 0.2, "lineDeclined" },
}
local GONE = { failed = true, cancelled = true, declined = true, declined_full = true, declined_delisted = true,
    invitedeclined = true, timedout = true, inviteaccepted = true }

-- same place the header puts each column
local function PlaceCells(l)
    local x = 0
    -- only the columns in play show, streamer mode can drop some
    for _, fs in pairs(l.cells) do fs:Hide() end
    for c = #cols, 1, -1 do
        local col = cols[c]
        x = x - col.w
        local fs = l.cells[col.key]
        if fs then
            fs:Show()
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", l, "RIGHT", x, 0)
            fs:SetWidth(col.w)
        elseif col == ROLE_COL then
            l.roleX = x
        elseif col == SPEC_COL then
            l.specX = x
        end
    end
    l.name:ClearAllPoints()
    l.nameRight = x
end

local function FontSize(fs, size)
    local ok, path, _, flags = pcall(fs.GetFont, fs)
    if ok and path then fs:SetFont(path, size, flags or "") end
end

-- icon when we know the spec, else the class like the results list
local function PaintSpec(l, class, specID, grey)
    local t, ring, bf = l.spec, l.specRing, l.specBorder
    ring:Hide()
    bf:Hide()
    if l.specMasked then
        t:RemoveMaskTexture(l.specMask)
        l.specMasked = nil
    end
    if grey or ns.OwnListGet("streamerSpec") then
        t:Hide()
        return
    end
    t:SetSize(iconPx, iconPx)
    t:ClearAllPoints()
    t:SetPoint("CENTER", l, "RIGHT", l.specX + SPEC_COL.w / 2, 0)
    t:SetTexCoord(0, 1, 0, 1)
    local square = ns.OwnListGet("iconShape") == "square"
    local icon = type(specID) == "number" and specID > 0 and select(4, GetSpecializationInfoByID(specID))
    if icon then
        t:SetTexture(icon)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif square then
        local cc = class and C_ClassColor and C_ClassColor.GetClassColor(class)
        if cc then t:SetColorTexture(cc.r * 0.75, cc.g * 0.75, cc.b * 0.75, 1) else t:SetColorTexture(0.3, 0.3, 0.3, 1) end
    elseif class then
        t:SetAtlas("groupfinder-icon-class-color-" .. class)
    else
        t:SetColorTexture(0.3, 0.3, 0.3, 1)
    end
    local bpx = tonumber(ns.OwnListGet("borderSize")) or 0
    local br, bg, bb = ns.OwnListBorderColor()
    if square then
        if bpx > 0 and EUI.ApplyBorderStyle then
            local btex = ns.OwnListGet("borderTexture") or "solid"
            local bkey = btex .. ":" .. bpx .. ":" .. br .. ":" .. bg .. ":" .. bb
            if bf._key ~= bkey then
                bf._key = bkey
                EUI.ApplyBorderStyle(bf, bpx, br, bg, bb, 1, btex)
            end
            bf:Show()
        end
    elseif icon then
        t:AddMaskTexture(l.specMask)
        l.specMasked = true
        if bpx > 0 then
            ring:ClearAllPoints()
            ring:SetPoint("TOPLEFT", t, "TOPLEFT", -bpx, bpx)
            ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", bpx, -bpx)
            ring:SetColorTexture(br, bg, bb, 1)
            ring:Show()
        end
    end
    t:Show()
end

-- the results list's colored role tile
local function PaintRole(rb, role, class)
    rb.bg:Show()
    -- the applicant's class color when asked, else the role's
    if class and not Secret(class) and ns.OwnListGet("roleClassColors") then
        local cc = EUI.GetClassColor(class)
        rb.bg:SetColorTexture(cc.r, cc.g, cc.b, 1)
    else
        local c = ns.RaidRoleColors[role]
        rb.bg:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local round = ns.OwnListGet("iconShape") ~= "square"
    if round and not rb.masked then
        rb.bg:AddMaskTexture(rb.mask)
        rb.masked = true
    elseif not round and rb.masked then
        rb.bg:RemoveMaskTexture(rb.mask)
        rb.masked = nil
    end
    local tex = ns.OwnListGet("missingIcons") == "ellesmere" and ns.RoleIconTex and ns.RoleIconTex(role)
    if tex then rb.tex:SetTexture(tex) else rb.tex:SetAtlas(ROLE_ATLAS[role]) end
    local gsz = math.floor(iconPx * 0.7 + 0.5)
    rb.tex:SetSize(gsz, gsz)
    local bpx = tonumber(ns.OwnListGet("borderSize")) or 0
    local br, bg, bb = ns.OwnListBorderColor()
    rb.ring:Hide()
    rb.border:Hide()
    if bpx <= 0 then return end
    if round then
        rb.ring:ClearAllPoints()
        rb.ring:SetPoint("TOPLEFT", rb.bg, "TOPLEFT", -bpx, bpx)
        rb.ring:SetPoint("BOTTOMRIGHT", rb.bg, "BOTTOMRIGHT", bpx, -bpx)
        rb.ring:SetColorTexture(br, bg, bb, 1)
        rb.ring:Show()
    elseif EUI.ApplyBorderStyle then
        local btex = ns.OwnListGet("borderTexture") or "solid"
        local bkey = btex .. ":" .. bpx .. ":" .. br .. ":" .. bg .. ":" .. bb
        if rb.border._key ~= bkey then
            rb.border._key = bkey
            EUI.ApplyBorderStyle(rb.border, bpx, br, bg, bb, 1, btex)
        end
        rb.border:Show()
    end
end

-- a mark before the name, after the one placed before it (l.markPrev)
local function After(l, tex, shown, x)
    tex:SetShown(shown)
    if not shown then return end
    local anchor = l.markPrev
    tex:ClearAllPoints()
    tex:SetPoint("LEFT", anchor, anchor == l and "LEFT" or "RIGHT", anchor == l and x or 1, 0)
    l.markPrev = tex
end

local function FillLine(l, id, k, grey, noTouch)
    local name, class, localClass, _, ilvl, _, tank, healer, damage, assigned, relation, score, pvpIlvl, _, _, specID, leaver = src.member(id, k)
    PlaceCells(l)
    PaintSpec(l, class, specID, grey)
    -- the applicant's name: a font family (ns.OwnListNameFont), never FontSize
    ns.OwnListNameFont(l.name, ns.OwnListSize("titleSize"))
    for _, fs in pairs(l.cells) do FontSize(fs, ns.OwnListSize("scoreSize")) end
    -- leaver, friend, name
    local x = k > 1 and 18 or 6
    l.markPrev = l
    After(l, l.leaver, not Secret(leaver) and leaver, x)
    After(l, l.friend, not Secret(relation) and relation, x)
    local anchor = l.markPrev
    -- region under the name when the row has the height for it
    local tag, tr, tg, tb, flag
    if not grey and ns.RegionTagOfName then tag, tr, tg, tb, flag = ns.RegionTagOfName(name) end
    local lineSize = ns.OwnListSize("lineSize")
    if tag and rowH < ns.OwnListSize("titleSize") + lineSize + 6 then tag = nil end
    local nameY = tag and math.ceil((lineSize + 2) / 2) or 0
    l.name:SetPoint("LEFT", anchor, anchor == l and "LEFT" or "RIGHT", anchor == l and x or 2, nameY)
    l.name:SetPoint("RIGHT", l, "RIGHT", l.nameRight - 2, nameY)
    if ns.OwnListGet("streamerNames") then
        l.name:SetText(localClass or "")
    else
        l.name:SetText(name and Ambiguate(name, "short") or "")
    end
    -- a group's other members hang off the leader's row
    l.bullet:SetShown(k > 1 and not grey)
    l.bullet:ClearAllPoints()
    l.bullet:SetPoint("LEFT", l, "LEFT", 9, nameY)
    l.region:SetShown(tag ~= nil)
    l.regionFlag:SetShown(tag ~= nil and flag ~= nil)
    if tag then
        FontSize(l.region, lineSize)
        l.region:SetText(tag)
        l.region:SetTextColor(tr, tg, tb, 1)
        if flag then
            local fh = math.max(8, lineSize)
            l.regionFlag:SetSize(math.floor(fh * 4 / 3 + 0.5), fh)
            l.regionFlag:SetTexture(flag)
        end
    end
    local cc = class and RAID_CLASS_COLORS[class]
    if grey or not cc then l.name:SetTextColor(0.6, 0.6, 0.6) else l.name:SetTextColor(cc.r, cc.g, cc.b) end

    -- the roles they picked, the one they're down for lit up
    local picked = l.picked
    if not picked then
        picked = {}
        l.picked = picked
    end
    wipe(picked)
    if tank then picked[#picked + 1] = "TANK" end
    if healer then picked[#picked + 1] = "HEALER" end
    if damage then picked[#picked + 1] = "DAMAGER" end
    for i = 1, 3 do
        local rb, role = l.roles[i], picked[i]
        rb:SetShown(role ~= nil and not grey)
        rb.role = role
        if role then
            PaintRole(rb, role, class)
            rb:SetAlpha(role == assigned and 1 or 0.3)
            rb:SetEnabled(not noTouch and role ~= assigned)
            rb:ClearAllPoints()
            -- centered under the column title
            rb:SetSize(iconPx, iconPx)
            local step = iconPx + ROLE_GAP
            rb:SetPoint("LEFT", l, "RIGHT", l.roleX + (ROLE_COL.w - #picked * step + ROLE_GAP) / 2 + (i - 1) * step, 0)
        end
    end

    local info = entryActivity
    for _, fs in pairs(l.cells) do fs:SetText(""); fs:SetTextColor(1, 1, 1) end
    if grey then return end
    local c = l.cells
    if info and info.isPvpActivity and type(pvpIlvl) == "number" then
        c.ilvl:SetText(math.floor(pvpIlvl))
    elseif type(ilvl) == "number" then
        c.ilvl:SetText(math.floor(ilvl))
    end
    if baseCols == COLS_KEYS then
        if type(score) == "number" then
            local r, g, b = 1, 1, 1
            if ns.GFRatingColor then r, g, b = ns.GFRatingColor(score) end
            c.rating:SetText(score)
            c.rating:SetTextColor(r, g, b)
        else
            c.rating:SetText("-")
        end
        c.best:SetText(KeyText(src.best(id, k)))
    elseif baseCols == COLS_PVP then
        local act = ActiveActivity()
        local pvp = act and C_LFGList.GetApplicantPvpRatingInfoForListing(id, k, act)
        local rating = Readable(pvp) and pvp.rating
        c.rating:SetText((rating and not Secret(rating)) and rating or "-")
    end
end

local function FillBlock(b, id, numAllowed, current, numInvited)
    local info = src.info(id)
    if not Readable(info) then
        b.applicantID = nil
        b:Hide()
        return 0
    end
    local n = info.numMembers or 1
    local status, pending = info.applicationStatus, info.pendingApplicationStatus
    b.applicantID, b.numMembers, b.appStatus = id, n, status
    local grey = not pending and GONE[status] or false
    for k = 1, n do
        local l = b.lines[k] or MakeLine(b, k)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(k - 1) * rowH)
        l:SetPoint("TOPRIGHT", b, "TOPRIGHT", -btnRoom, -(k - 1) * rowH)
        -- the highlight runs on under the buttons
        l.hl:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", btnRoom, 0)
        l:SetHeight(rowH)
        FillLine(l, id, k, grey, not empowered or status == "invited")
        l:Show()
    end
    for k = n + 1, #b.lines do b.lines[k]:Hide() end
    -- the applicant's note, the block only grows when there is one
    local comment, noteH = info.comment, 0
    local hasNote = not grey and not ns.OwnListGet("streamerNote")
        and type(comment) == "string" and not Secret(comment) and comment ~= ""
    b.note:SetShown(hasNote)
    b.noteHit:SetShown(hasNote)
    if hasNote then
        ns.OwnListNameFont(b.note, ns.OwnListSize("lineSize"))
        b.note:ClearAllPoints()
        b.note:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -n * rowH)
        b.note:SetWidth(math.max(40, (body:GetWidth() or 200) - btnRoom - 8))
        b.note:SetText(string.format(LFG_LIST_COMMENT_FORMAT or "%s", comment))
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        if fc then b.note:SetTextColor(fc.r, fc.g, fc.b) else b.note:SetTextColor(0.6, 0.6, 0.6) end
        noteH = math.ceil(b.note:GetStringHeight() or 12) + 6
    end
    local last = b.lines[n]
    if last then last.hl:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", btnRoom, -noteH) end
    SizeSquare(b.invite)
    SizeSquare(b.decline)
    -- buttons and status stay on the top row, whatever hangs below it
    b.decline:ClearAllPoints()
    b.decline:SetPoint("RIGHT", b, "TOPRIGHT", -3, -rowH / 2)
    b.invite:SetShown(empowered and not pending and status == "applied")
    b.decline:SetShown(empowered and not pending and status ~= "invited")
    -- blizzard's fullness check
    local tip
    if n + current > numAllowed then tip = LFG_LIST_GROUP_TOO_FULL
    elseif n + current + numInvited > numAllowed then tip = LFG_LIST_INVITED_APP_FILLS_GROUP end
    b.invite:SetEnabled(not tip)
    b.invite.icon:SetDesaturated(tip ~= nil)
    b.invite.tip = tip or INVITE or "Invite"
    -- a status replaces the columns once they're out of play
    local st = STATUS[status]
    b.status:ClearAllPoints()
    if b.decline:IsShown() then
        b.status:SetPoint("RIGHT", b.decline, "LEFT", -6, 0)
    else
        b.status:SetPoint("RIGHT", b, "TOPRIGHT", -6, -rowH / 2)
    end
    b.status:SetShown(st ~= nil)
    if st then
        b.status:SetText(st[1])
        b.status:SetTextColor(st[2], st[3], st[4])
    end
    -- same underline and fade as a results row
    if st and ns.OwnListGet(st[5]) ~= false then
        b.under:SetColorTexture(st[2], st[3], st[4], 0.9)
        b.under:Show()
    else
        b.under:Hide()
    end
    b:SetAlpha(grey and 0.5 or 1)
    return rowH * n + noteH
end

-------------------------------------------------------------------------------
--  the list
-------------------------------------------------------------------------------
local function Position()
    if not active then return end
    local height = body:GetHeight() or 0
    local total = 0
    for i = 1, #list do total = total + blocks[i].h + GAP end
    total = math.max(0, total - GAP)
    local maxPx = math.max(0, total - height)
    scrollPx = math.max(0, math.min(scrollPx, maxPx))
    local y = -scrollPx
    for i = 1, #list do
        local b = blocks[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
        b:SetHeight(b.h)
        b:SetShown(b.applicantID ~= nil and y + b.h > 0 and y < height)
        y = y + b.h + GAP
    end
    if maxPx > 0 then
        local th = math.max(16, height * height / total)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(height - th) * (scrollPx / maxPx))
        thumb:Show()
    else
        thumb:Hide()
    end
end

-- same left edge, right edge and scrollbar spot as the results list
local function LayoutFrame()
    local c = ns.Cfg and ns.Cfg()
    local pad = tonumber(c and c.padding) or 12
    local sp = LFGListFrame.SearchPanel
    local barW = sp and sp.ScrollBar and sp.ScrollBar:GetWidth() or 8
    -- rows stop short of the bottom buttons
    local boxB, avB = AV.ScrollBox:GetBottom(), AV:GetBottom()
    local bottomY = (boxB and avB) and math.max(0, (ns.BOTTOM_Y or 8) + (AV.EditButton:GetHeight() or 22) + 4 - (boxB - avB)) or 0
    local key = pad .. ":" .. barW .. ":" .. btnRoom .. ":" .. bottomY
    if key == layoutKey then return end
    layoutKey = key
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", AV.ScrollBox, "TOPLEFT", pad, 0)
    frame:SetPoint("BOTTOMRIGHT", AV.ScrollBox, "BOTTOMRIGHT", BOX_RIGHT - pad / 2 + barW / 2, bottomY)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", AV.ScrollBox, "BOTTOMRIGHT", BOX_RIGHT - pad, bottomY)
    head:ClearAllPoints()
    head:SetPoint("BOTTOMLEFT", body, "TOPLEFT", 0, 3)
    head:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -btnRoom, 3)
end

-- the group's role counts at the top, drawn like a raid row in the results list
local function PaintRaidRoles()
    local want = entryActivity and Enum.LFGListDisplayType and entryActivity.displayType == Enum.LFGListDisplayType.RoleCount
    local data = want and src.counts()
    want = want and Readable(data)
    raidRoles:SetShown(want and true or false)
    if not want then return end
    local isz = ns.OwnListIconSize(ns.OwnListRowHeight())
    local round = ns.OwnListGet("iconShape") ~= "square"
    local ell = ns.OwnListGet("missingIcons") == "ellesmere"
    local fsz = ns.OwnListSize("scoreSize")
    local x = 0
    for k = 3, 1, -1 do
        local p, role = raidRoles.parts[k], ROLES[k]
        local num = data[role]
        if type(num) == "number" and not Secret(num) then
            local c = ns.RaidRoleColors[role]
            p.bg:SetColorTexture(c[1], c[2], c[3], 1)
            if round and not p.masked then
                p.bg:AddMaskTexture(p.mask)
                p.masked = true
            elseif not round and p.masked then
                p.bg:RemoveMaskTexture(p.mask)
                p.masked = nil
            end
            p.bg:SetSize(isz, isz)
            p.bg:ClearAllPoints()
            p.bg:SetPoint("RIGHT", raidRoles, "RIGHT", x, 0)
            p.bg:Show()
            local tex = ell and ns.RoleIconTex and ns.RoleIconTex(role)
            if tex then p.icon:SetTexture(tex) else p.icon:SetAtlas(ROLE_ATLAS[role]) end
            local gsz = math.floor(isz * 0.7 + 0.5)
            p.icon:SetSize(gsz, gsz)
            p.icon:Show()
            FontSize(p.count, fsz)
            p.count:SetText(num)
            p.count:Show()
            x = x - math.max(isz, math.ceil(p.count:GetStringWidth() or 8)) - 6
        else
            p.bg:Hide()
            p.icon:Hide()
            p.count:Hide()
        end
    end
end

-- a title's width, so narrow columns never cut it off
local ruler
local function TitleWidth(title)
    if not ruler then
        ruler = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ruler:SetAlpha(0)
    end
    ruler:SetText(title)
    return math.ceil(ruler:GetStringWidth() or 24) + 4
end

-- the most roles any applicant in the list picked
local function MostRoles(ids)
    local most = 1
    for _, id in ipairs(ids) do
        local info = src.info(id)
        if Readable(info) and (info.pendingApplicationStatus or not GONE[info.applicationStatus]) then
            for k = 1, info.numMembers or 1 do
                local _, _, _, _, _, _, tank, healer, damage = src.member(id, k)
                most = math.max(most, (tank and 1 or 0) + (healer and 1 or 0) + (damage and 1 or 0))
            end
        end
    end
    return most
end

local function PaintHeader()
    for _, fs in ipairs(head.titles) do fs:Hide() end
    local x, used = 0, 0
    for c = #cols, 1, -1 do
        local col = cols[c]
        x = x - col.w
        used = used + 1
        local fs = head.titles[used]
        if not fs then
            fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetJustifyH("CENTER")
            fs:SetWordWrap(false)
            head.titles[used] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", head, "RIGHT", x, 0)
        fs:SetWidth(col.w)
        fs:SetText(col.title)
        fs:Show()
    end
end

-- the listing's columns minus what streamer mode hides
local visibleCols = {}
VisibleCols = function(base, out)
    local noSpec, noRating = ns.OwnListGet("streamerSpec"), ns.OwnListGet("streamerRating")
    if not (noSpec or noRating) then return base end
    out = out or visibleCols
    wipe(out)
    for _, col in ipairs(base) do
        if not ((noSpec and col == SPEC_COL) or (noRating and col == RATING_COL)) then
            out[#out + 1] = col
        end
    end
    return out
end

local function Paint()
    if not active then return end
    empowered = LFGListUtil_IsEntryEmpowered() and true or false
    cover:SetShown(not empowered)
    rowH = tonumber(ns.OwnListGet("applicantRowHeight")) or 36
    btnSize = math.max(18, math.min(rowH - 8, 24))
    btnRoom = btnSize * 2 + GAP + 8
    iconPx = ns.OwnListIconSize(rowH)
    Collect()
    -- role is only as wide as the applicants need, the name takes the rest
    local most = MostRoles(list)
    SPEC_COL.w = math.max(TitleWidth(SPEC_COL.title), iconPx) + 6
    ROLE_COL.w = math.max(TitleWidth(ROLE_COL.title), iconPx * most + ROLE_GAP * (most - 1)) + 6
    LayoutFrame()
    local act, ai = ActiveActivity()
    entryActivity = act and ai or nil
    if entryActivity and entryActivity.isMythicPlusActivity then baseCols = COLS_KEYS
    elseif entryActivity and entryActivity.isRatedPvpActivity then baseCols = COLS_PVP
    else baseCols = COLS_BASE end
    cols = VisibleCols(baseCols)
    PaintHeader()
    PaintRaidRoles()
    local numAllowed = entryActivity and entryActivity.maxNumPlayers or 0
    if numAllowed == 0 then numAllowed = MAX_RAID_MEMBERS or 40 end
    local current = GetNumGroupMembers(HOME)
    local numInvited = C_LFGList.GetNumInvitedApplicantMembers()
    for i, id in ipairs(list) do
        local b = blocks[i] or MakeBlock(i)
        b.h = FillBlock(b, id, numAllowed, current, numInvited)
    end
    for i = #list + 1, #blocks do
        blocks[i].applicantID = nil
        blocks[i]:Hide()
    end
    empty:SetShown(#list == 0)
    Position()
end

local function HoldHidden(f, a)
    if guard or not active or a == 0 then return end
    guard = true
    f:SetAlpha(0)
    guard = false
end

local function Faded()
    return { AV.ScrollBox, AV.ScrollBar, AV.NameColumnHeader, AV.RoleColumnHeader, AV.ItemLevelColumnHeader, AV.RatingColumnHeader, AV.UnempoweredCover,
        AV.DataDisplay and AV.DataDisplay.RoleCount }
end

-- the raid role counts: a circle and a number per role
local function MakeRaidRoles(parent)
    local rr = CreateFrame("Frame", nil, parent)
    rr:SetSize(1, 1)
    rr.parts = {}
    for k = 1, 3 do
        local bg = rr:CreateTexture(nil, "ARTWORK", nil, 1)
        local mask = rr:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(bg)
        local icon = rr:CreateTexture(nil, "ARTWORK", nil, 3)
        icon:SetPoint("CENTER", bg)
        local count = rr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetJustifyH("CENTER")
        count:SetPoint("BOTTOM", bg, "TOP", 0, 1)
        rr.parts[k] = { bg = bg, mask = mask, icon = icon, count = count }
    end
    return rr
end

local function Build()
    frame = CreateFrame("Frame", nil, AV)
    frame:SetFrameLevel(AV.ScrollBox:GetFrameLevel() + 10)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    local function Wheel(_, delta)
        scrollPx = scrollPx - delta * (rowH + GAP)
        Position()
    end
    frame:SetScript("OnMouseWheel", Wheel)
    -- blizzard's hidden rows get no clicks in the strip left of ours
    local shield = CreateFrame("Frame", nil, frame)
    shield:SetPoint("TOPLEFT", AV.ScrollBox, "TOPLEFT", 0, 0)
    shield:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
    shield:EnableMouse(true)
    shield:EnableMouseWheel(true)
    shield:SetScript("OnMouseWheel", Wheel)
    frame:SetScript("OnSizeChanged", Position)
    frame:Hide()
    body = CreateFrame("Frame", nil, frame)
    body:SetClipsChildren(true)
    empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", frame, "TOP", 0, -20)
    empty:SetText(LFG_LIST_NO_APPLICANTS or "No applicants")
    thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.3)
    -- blizzard's cover would sit under our rows, so ours goes on top of them
    cover = CreateFrame("Frame", nil, frame)
    cover:SetAllPoints(body)
    cover:SetFrameLevel(frame:GetFrameLevel() + 20)
    cover:EnableMouse(true)
    cover:EnableMouseWheel(true)
    cover:SetScript("OnMouseWheel", Wheel)
    local tint = cover:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints()
    tint:SetColorTexture(0.035, 0.071, 0.118, 0.5)
    local forming = cover:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    forming:SetPoint("CENTER", cover, "CENTER", 0, 20)
    forming:SetText(LFG_LIST_GROUP_FORMING or "Your group is currently forming.")
    cover:Hide()
    -- our column titles over blizzard's
    head = CreateFrame("Frame", nil, AV)
    head:SetHeight(24)
    head:SetFrameLevel(AV.ScrollBox:GetFrameLevel() + 10)
    head:EnableMouse(true)
    head:Hide()
    head.titles = {}
    local nameTitle = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameTitle:SetPoint("LEFT", head, "LEFT", 6, 0)
    nameTitle:SetText(NAME or "Name")
    -- sits where blizzard's counts were, their tooltip still works underneath
    raidRoles = MakeRaidRoles(head)
    raidRoles:SetPoint("RIGHT", AV.DataDisplay and AV.DataDisplay.RoleCount or AV.DataDisplay or AV, "RIGHT", 0, 0)
    for _, f in ipairs(Faded()) do hooksecurefunc(f, "SetAlpha", HoldHidden) end
end

-- ours only with readable applicants
local function Wanted()
    return ns.ApplicantListOn() and AV:IsVisible() and not AnySecret()
end

local function SetActive(now)
    if now == active then return end
    if now and not frame then Build() end
    active = now
    if not frame then return end
    local a = active and 0 or 1
    guard = true
    for _, f in ipairs(Faded()) do f:SetAlpha(a) end
    guard = false
    frame:SetShown(active)
    head:SetShown(active)
    if not active then
        GameTooltip_Hide()
        RioLeave()
    end
end

-- a black bar over blizzard's text, the mouse stops there so its tooltip can't show either
local censor = {}
local function CensorBar(key, fs, on, maxW, h)
    local bar = censor[key]
    if not bar then
        if not on then return end
        bar = CreateFrame("Frame", nil, AV)
        bar:SetFrameLevel(AV:GetFrameLevel() + 30)
        bar:EnableMouse(true)
        local tex = bar:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetColorTexture(0, 0, 0, 1)
        censor[key] = bar
    end
    bar:SetShown(on and true or false)
    if not on then return end
    local w = math.max(40, math.min(fs:GetStringWidth() or maxW, maxW))
    bar:ClearAllPoints()
    bar:SetPoint("LEFT", fs, "LEFT", -2, 0)
    bar:SetSize(w + 4, h)
end

local function PaintCensor()
    local on = ns.ApplicantListOn()
    if AV.EntryName then
        CensorBar("title", AV.EntryName, on and ns.OwnListGet("streamerTitle"), 290, 20)
    end
    local desc = AV.DescriptionFrame
    if desc and desc.Text then
        CensorBar("dungeon", desc.Text, on and ns.OwnListGet("streamerDungeon"), 310, 16)
    end
end

-- events only while the list is on and the viewer's up
local watch, watching
local EVENTS = { "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_APPLICANT_UPDATED", "LFG_LIST_ACTIVE_ENTRY_UPDATE",
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_DISABLED",
    "ADDON_RESTRICTION_STATE_CHANGED" }

local function SyncEvents()
    local want = (ns.ApplicantListOn() and watch:IsVisible()) and true or false
    if want == watching then return end
    watching = want
    if want then
        for _, e in ipairs(EVENTS) do watch:RegisterEvent(e) end
    else
        watch:UnregisterAllEvents()
    end
end

function ns.ApplicantListRefresh()
    if not AV then return end
    SyncEvents()
    PaintCensor()
    SetActive(Wanted() and true or false)
    Paint()
    if ns.LayoutViewer then ns.LayoutViewer() end
end

-- display settings repaint us too
local baseRefresh = ns.OwnListRefresh
ns.OwnListRefresh = function()
    baseRefresh()
    ns.ApplicantListRefresh()
end

-- applicant events gather here: one refresh on the next frame, from a frame
-- hidden again until the next event
local refresher
local function Queue()
    if not refresher then
        refresher = CreateFrame("Frame")
        refresher:Hide()
        refresher:SetScript("OnUpdate", function(self)
            self:Hide()
            ns.ApplicantListRefresh()
        end)
    end
    refresher:Show()
end

if ns.WhenGroupFinder then
    ns.WhenGroupFinder(function()
        AV = LFGListFrame and LFGListFrame.ApplicationViewer
        if not (AV and AV.ScrollBox and AV.Inset) then
            AV = nil
            return
        end
        -- a child of the viewer shows and hides with it, no hooks on blizzard's frame
        watch = CreateFrame("Frame", nil, AV)
        watch:SetScript("OnShow", function()
            SyncEvents()
            if watching then Queue() end
        end)
        watch:SetScript("OnHide", function()
            SyncEvents()
            SetActive(false)
        end)
        watch:SetScript("OnEvent", function(_, event)
            -- combat can lift with no event of ours, look again once it's over
            if event == "PLAYER_REGEN_DISABLED" then ns.CombatQueue.Defer("applicantList", Queue) end
            Queue()
        end)
        if watch:IsVisible() then watch:GetScript("OnShow")(watch) end
    end)
end

-------------------------------------------------------------------------------
--  settings preview: sample applicants drawn by the list's own rows, for a
--  key or a raid listing. the list's state is set aside while it paints
-------------------------------------------------------------------------------
local DT = Enum.LFGListDisplayType
local PV_ACT = {
    dungeon = { isMythicPlusActivity = true, maxNumPlayers = 5, displayType = DT and DT.RoleEnumerate },
    raid = { maxNumPlayers = 30, displayType = DT and DT.RoleCount },
}
-- members: class, spec, roles picked (T/H/D), the role they're down for,
-- item level over yours, rating, best key, timed, and a fixed name (the easter eggs)
local PV_APPS = {
    dungeon = {
        { note = EllesmereUI.L("Timed it last week, happy to lead"), members = { { "MONK", 268, "T", "TANK", 6, 3120, 12, true } } },
        { members = { { "WARRIOR", 72, "D", "DAMAGER", 3, 2890, 11, true, ns.PreviewBlockjob },
            { "PALADIN", 65, "H", "HEALER", 4, 2950, 11, true, ns.PreviewElle } } },
        { members = { { "MAGE", 63, "D", "DAMAGER", -2, 2610, 10, false } } },
        { status = "invited", members = { { "PRIEST", 257, "HD", "HEALER", 1, 2780, 11, true, ns.PreviewLuella } } },
        { note = EllesmereUI.L("Can tank or dps"), members = { { "DEMONHUNTER", 581, "TD", "TANK", 2, 3010, 12, false } } },
    },
    raid = {
        { members = { { "DRUID", 104, "T", "TANK", 3 } } },
        { note = EllesmereUI.L("Have the tier set, need the trinket"), members = { { "SHAMAN", 264, "HD", "HEALER", 1 } } },
        { members = { { "HUNTER", 254, "D", "DAMAGER", 4 }, { "ROGUE", 260, "D", "DAMAGER", 2 } } },
        { members = { { "PALADIN", 65, "H", "HEALER", 2, nil, nil, nil, ns.PreviewElle } } },
        { status = "invited", members = { { "EVOKER", 1467, "HD", "DAMAGER", 0 } } },
        { members = { { "DEATHKNIGHT", 250, "TD", "DAMAGER", 5 } } },
    },
}
local PV_COUNTS = { TANK = 2, HEALER = 4, DAMAGER = 11 }
local apv = { blocks = {}, scroll = 0, ids = {}, data = {} }

-- names: the suite's preview roster (EllesmereUI.PREVIEW_ROSTER), one of the
-- member's class first
local function PvNames(kind)
    local roster = ns.PreviewRoster or EllesmereUI.PREVIEW_ROSTER
    local used, start = {}, kind == "raid" and 7 or 0
    local function Take(cls)
        for pass = 1, 2 do
            for i = 0, #roster - 1 do
                local k = (start + i) % #roster + 1
                local e = roster[k]
                if not used[k] and (pass == 2 or e.class == cls) then
                    used[k] = true
                    return e.name
                end
            end
        end
        return "Applicant"
    end
    local base = select(2, GetAverageItemLevel()) or 0
    local ids, data = apv.ids, apv.data
    wipe(ids)
    wipe(data)
    for i, a in ipairs(PV_APPS[kind]) do
        local id = kind .. i
        local m = {}
        for k, d in ipairs(a.members) do
            m[k] = { name = d[9] or Take(d[1]), class = d[1], spec = d[2], roles = d[3], assigned = d[4],
                ilvl = math.max(1, base + d[5]), score = d[6], best = d[7] and { bestRunLevel = d[7], finishedSuccess = d[8] } }
        end
        ids[#ids + 1] = id
        data[id] = { info = { applicationStatus = a.status or "applied", numMembers = #m, isNew = false, displayOrderID = i,
            comment = a.note or "" }, members = m }
    end
end

local PREVIEW = {
    info = function(id) return apv.data[id] and apv.data[id].info end,
    member = function(id, k)
        local m = apv.data[id] and apv.data[id].members[k]
        if not m then return nil end
        local localClass = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class] or m.class
        return m.name, m.class, localClass, 80, m.ilvl, 0, m.roles:find("T") ~= nil, m.roles:find("H") ~= nil,
            m.roles:find("D") ~= nil, m.assigned, nil, m.score, m.ilvl, nil, nil, m.spec, false
    end,
    best = function(id, k)
        local m = apv.data[id] and apv.data[id].members[k]
        return m and m.best
    end,
    counts = function() return PV_COUNTS end,
}

-- what the settings allow: name or class, spec, item level, rating, the note
PvTip = function(line)
    local id = line:GetParent().applicantID
    local name, class, localClass, _, ilvl, _, _, _, _, _, _, score, _, _, _, specID = PREVIEW.member(id, line.memberIdx)
    if not name then return end
    local cc = EUI.GetClassColor(class)
    GameTooltip:SetOwner(line, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 105, 0)
    GameTooltip:SetText(ns.OwnListGet("streamerNames") and localClass or name, cc.r, cc.g, cc.b)
    local specName = not ns.OwnListGet("streamerSpec") and select(2, GetSpecializationInfoByID(specID))
    GameTooltip:AddLine(specName and (specName .. " " .. localClass) or localClass, 1, 1, 1)
    GameTooltip:AddDoubleLine(ITEM_LEVEL_ABBR or "iLvl", math.floor(ilvl), 1, 0.82, 0, 1, 1, 1)
    if score and not ns.OwnListGet("streamerRating") then
        GameTooltip:AddDoubleLine(RATING or "Rating", score, 1, 0.82, 0, 1, 1, 1)
    end
    local comment = PREVIEW.info(id).comment
    if comment ~= "" and line.memberIdx == 1 and not ns.OwnListGet("streamerNote") then
        GameTooltip:AddLine(" ")
        local fc = LFG_LIST_COMMENT_FONT_COLOR
        GameTooltip:AddLine(string.format(LFG_LIST_COMMENT_FORMAT or "%s", comment), fc and fc.r or 0.6, fc and fc.g or 0.6, fc and fc.b or 0.6, true)
    end
    GameTooltip:Show()
end

local function PvPosition()
    local h = apv.body:GetHeight() or 0
    local total = -GAP
    for i = 1, #apv.ids do total = total + apv.blocks[i].h + GAP end
    apv.maxScroll = math.max(0, total - h)
    apv.scroll = math.max(0, math.min(apv.scroll, apv.maxScroll))
    local y = -apv.scroll
    for i = 1, #apv.ids do
        local b = apv.blocks[i]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", apv.body, "TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", apv.body, "TOPRIGHT", 0, -y)
        b:SetHeight(b.h)
        b:SetShown(y + b.h > 0 and y < h)
        y = y + b.h + GAP
    end
    local th = apv.thumb
    if apv.maxScroll > 0 then
        local tH = math.max(12, h * h / total)
        th:SetHeight(tH)
        th:ClearAllPoints()
        th:SetPoint("TOPRIGHT", apv.body, "TOPRIGHT", 0, -(h - tH) * (apv.scroll / apv.maxScroll))
        th:Show()
    else
        th:Hide()
    end
end

local function PvBuild(host)
    local f = CreateFrame("Frame", nil, host)
    f:SetAllPoints(host)
    apv.frame = f
    apv.head = CreateFrame("Frame", nil, f)
    apv.head.titles = {}
    local nameTitle = apv.head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameTitle:SetPoint("LEFT", apv.head, "LEFT", 6, 0)
    nameTitle:SetText(NAME or "Name")
    apv.raidRoles = MakeRaidRoles(apv.head)
    apv.body = CreateFrame("Frame", nil, f)
    apv.body:SetClipsChildren(true)
    apv.body:EnableMouseWheel(true)
    apv.body:SetScript("OnMouseWheel", function(_, delta)
        local was = apv.scroll
        local step = math.floor((rowH + GAP) * 0.3 + 0.5)
        apv.scroll = math.max(0, math.min(was - delta * step, apv.maxScroll or 0))
        if apv.scroll ~= was then
            PvPosition()
            GameTooltip_Hide()
        end
    end)
    apv.thumb = apv.body:CreateTexture(nil, "OVERLAY", nil, 7)
    apv.thumb:SetWidth(2)
    apv.thumb:SetColorTexture(1, 1, 1, 0.25)
end

-- the list's own state, kept while the preview paints
local kept = {}
local function Keep()
    kept[1], kept[2], kept[3], kept[4] = src, head, body, raidRoles
    kept[5], kept[6], kept[7], kept[8] = rowH, btnSize, btnRoom, iconPx
    kept[9], kept[10], kept[11], kept[12] = entryActivity, baseCols, cols, empowered
    kept[13], kept[14] = SPEC_COL.w, ROLE_COL.w
end
local function PutBack()
    src, head, body, raidRoles = kept[1], kept[2], kept[3], kept[4]
    rowH, btnSize, btnRoom, iconPx = kept[5], kept[6], kept[7], kept[8]
    entryActivity, baseCols, cols, empowered = kept[9], kept[10], kept[11], kept[12]
    SPEC_COL.w, ROLE_COL.w = kept[13], kept[14]
end

local pvCols = {}
local function PvPaint(kind, w, h)
    PvNames(kind)
    src, head, body, raidRoles = PREVIEW, apv.head, apv.body, apv.raidRoles
    rowH = tonumber(ns.OwnListGet("applicantRowHeight")) or 36
    btnSize = math.max(18, math.min(rowH - 8, 24))
    btnRoom = btnSize * 2 + GAP + 8
    iconPx = ns.OwnListIconSize(rowH)
    empowered = true
    local most = MostRoles(apv.ids)
    SPEC_COL.w = math.max(TitleWidth(SPEC_COL.title), iconPx) + 6
    ROLE_COL.w = math.max(TitleWidth(ROLE_COL.title), iconPx * most + ROLE_GAP * (most - 1)) + 6
    entryActivity = PV_ACT[kind]
    baseCols = kind == "dungeon" and COLS_KEYS or COLS_BASE
    cols = VisibleCols(baseCols, pvCols)
    -- a raid's header is tall enough for the counts' numbers over their circles
    local headH = 24
    if kind == "raid" then headH = math.max(24, ns.OwnListIconSize(ns.OwnListRowHeight()) + 2 * ns.OwnListSize("scoreSize") + 6) end
    apv.head:ClearAllPoints()
    apv.head:SetPoint("TOPLEFT", apv.frame, "TOPLEFT", 0, 0)
    apv.head:SetSize(w - btnRoom, headH)
    apv.body:ClearAllPoints()
    apv.body:SetPoint("TOPLEFT", apv.frame, "TOPLEFT", 0, -headH)
    apv.body:SetSize(w, math.max(1, h - headH))
    PaintHeader()
    -- the counts sit left of the column titles
    local colsW = 0
    for _, col in ipairs(cols) do colsW = colsW + col.w end
    apv.raidRoles:ClearAllPoints()
    apv.raidRoles:SetPoint("RIGHT", apv.head, "RIGHT", -colsW - 8, 0)
    PaintRaidRoles()
    local max = entryActivity.maxNumPlayers
    for i, id in ipairs(apv.ids) do
        local b = apv.blocks[i] or MakeBlock(i, apv.body, apv.blocks)
        b.preview = true
        b.h = FillBlock(b, id, max, 1, 0)
    end
    for i = #apv.ids + 1, #apv.blocks do
        apv.blocks[i].applicantID = nil
        apv.blocks[i]:Hide()
    end
end

-- draws the sample applicants for a key ("dungeon") or a raid into host,
-- w by h; kind nil hides them
function ns.ApplicantPreviewPaint(host, kind, w, h)
    if not kind then
        if apv.frame then apv.frame:Hide() end
        return
    end
    if not apv.frame then PvBuild(host) end
    if apv.kind ~= kind then apv.kind, apv.scroll = kind, 0 end
    apv.frame:Show()
    Keep()
    local ok, err = pcall(PvPaint, kind, w, h)
    PutBack()
    if not ok then geterrorhandler()(err) end
    PvPosition()
end
