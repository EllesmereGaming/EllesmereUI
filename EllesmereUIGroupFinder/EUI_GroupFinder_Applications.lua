if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_Applications.lua: M+ applications bar in the rail, counts per
-- session, character and account.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[ADDON_NAME] then return end -- held back (EllesmereUIGroupFinder.lua)
local CM = EllesmereUI

local IsSecret, PlainString = EllesmereUI.IsSecret, EllesmereUI.PlainString
-- Realm the way UnitFullName returns it.
local function NormRealm(realm)
    realm = PlainString(realm)
    if not realm then return nil end
    realm = realm:gsub("[%s%-]", "")
    return realm ~= "" and realm or nil
end
local function MyRealm()
    return NormRealm(GetNormalizedRealmName and GetNormalizedRealmName()) or NormRealm(GetRealmName()) or "?"
end

local KEYS = { "applied", "accepted", "declined", "delisted", "cancelled", "invited" }
local SESSION_GAP = 300  -- relogging within 5 min keeps the session

local STATUS_KEY = {
    applied = "applied",
    declined = "declined", declined_full = "declined", timedout = "declined",
    declined_delisted = "delisted",
    cancelled = "cancelled",
    invited = "invited",
    inviteaccepted = "accepted",
}

-- Bar segments. Invites aren't shown, every invite counts as accepted.
local SEGMENTS = {
    { key = "accepted",  cfg = "showAccepted",  r = 0.35, g = 0.85, b = 0.40 },
    { key = "declined",  cfg = "showDeclined",  r = 0.95, g = 0.30, b = 0.30 },
    { key = "delisted",  cfg = "showDelisted",  r = 1.00, g = 0.60, b = 0.20 },
    { key = "cancelled", cfg = "showCancelled", r = 0.55, g = 0.55, b = 0.55 },
}
local SCOPES = { "session", "character", "account" }
local VALID_SCOPE = { session = true, character = true, account = true }

-- Tooltip labels and colour escapes, built on the first hover (the locale is
-- ready by then).
local tipText
local function TipText()
    if tipText then return tipText end
    tipText = {
        session   = EllesmereUI.L("Session"),
        character = EllesmereUI.L("Character"),
        account   = EllesmereUI.L("Account"),
        accepted  = EllesmereUI.L("Accepted"),
        declined  = EllesmereUI.L("Declined"),
        delisted  = EllesmereUI.L("Delisted"),
        cancelled = EllesmereUI.L("Cancelled"),
        scopeHex  = CM.HexColor(1, 0.82, 0.3),
        segHex    = {},
    }
    for i, seg in ipairs(SEGMENTS) do tipText.segHex[i] = CM.HexColor(seg.r, seg.g, seg.b) end
    return tipText
end

-- Built-in bar textures plus SharedMedia's, built on first use.
local barTextures, barTexNames, barTexOrder
function ns.BarTextureTables()
    if not barTextures then
        barTextures, barTexNames, barTexOrder = CM.BuildBarTextureTables()
        CM.AppendSharedMediaTextures(barTexNames, barTexOrder, nil, barTextures)
    end
    return barTextures, barTexNames, barTexOrder
end

local function Cfg() return ns.AppsCfg() end

local function Get(key, default)
    local c = Cfg()
    local v = c and c[key]
    if v == nil then return default end
    return v
end

local function On() return Get("enabled", false) == true end

-- The picked bar texture's file, or nil for a flat colour.
local function TexturePath()
    local key = Get("texture", "none")
    if key == "none" then return nil end
    return CM.ResolveTexturePath((ns.BarTextureTables()), key)
end

local function Blank()
    local t = {}
    for _, k in ipairs(KEYS) do t[k] = 0 end
    return t
end

local function Fill(t)
    for _, k in ipairs(KEYS) do t[k] = tonumber(t[k]) or 0 end
    return t
end

local myKey
local function Store()
    local a = ns.AppCountsStore()
    if type(a.account) ~= "table" then a.account = Blank() end
    if type(a.chars) ~= "table" then a.chars = {} end
    if type(a.session) ~= "table" then a.session = Blank() end
    return a
end

local function Counts(scope)
    local a = Store()
    if scope == "account" then return Fill(a.account) end
    if scope == "session" then return Fill(a.session) end
    if not myKey then return Blank() end
    a.chars[myKey] = Fill(a.chars[myKey] or Blank())
    return a.chars[myKey]
end

-------------------------------------------------------------------------------
-- Card
-------------------------------------------------------------------------------
local card
local TITLE_SIZE = 12

local function Scope()
    local s = Get("scope", "character")
    return VALID_SCOPE[s] and s or "character"
end

-- Counts use the search box font (12 until it's set).
local function CountFont()
    local sb = _G.LFGListFrame and _G.LFGListFrame.SearchPanel and _G.LFGListFrame.SearchPanel.SearchBox
    local path, size
    if type(sb) == "table" and sb.GetFont then path, size = sb:GetFont() end
    if path and size and size > 0 then return path, size end
    return CM.GetFontPath(ADDON_NAME), 12
end

local tipLines = {}  -- reused per hover
local function ShowTip(self)
    local T = TipText()
    local n = 1
    tipLines[1] = EllesmereUI.L("M+ Applications")
    for _, scope in ipairs(SCOPES) do
        local c = Counts(scope)
        tipLines[n + 1] = " "
        tipLines[n + 2] = T.scopeHex .. T[scope] .. "|r  " .. EllesmereUI.Lf("%d applied", c.applied)
        n = n + 2
        for i, seg in ipairs(SEGMENTS) do
            n = n + 1
            tipLines[n] = "   " .. T.segHex[i] .. T[seg.key] .. "|r  " .. c[seg.key]
        end
    end
    for i = #tipLines, n + 1, -1 do tipLines[i] = nil end
    CM.ShowWidgetTooltip(self, table.concat(tipLines, "\n"), { anchor = "right", justify = "LEFT" })
end
local function HideTip() CM.HideWidgetTooltip() end

-- Where the search rows sit, in PVEFrame coordinates.
local function Place()
    local pve = _G.PVEFrame
    local inset = pve and pve.Inset
    if not (card and inset) then return end
    local r1, r2, size = -42, -57, 28
    if ns.Search_Rows then r1, r2, size = ns.Search_Rows() end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    local st, pt = sp and sp:GetTop(), pve:GetTop()
    local dy = (st and pt) and (st - pt) or 0
    local ref = _G.GroupFinderFrame and _G.GroupFinderFrame.groupButton1
    if type(ref) ~= "table" or not ref.GetLeft then ref = inset end
    local il, ir, pl = ref:GetLeft(), ref:GetRight(), pve:GetLeft()
    if not (il and ir and pl) then il, ir = inset:GetLeft(), inset:GetRight() end
    if not (il and ir and pl) then return end
    local pad = tonumber(ns.Cfg().padding) or 12
    local x1, x2 = il - pl + pad, ir - pl - pad
    card.box:ClearAllPoints()
    card.box:SetPoint("TOPLEFT", pve, "TOPLEFT", x1, dy + r2)
    card.box:SetPoint("TOPRIGHT", pve, "TOPLEFT", x2, dy + r2)
    card.box:SetHeight(size)
    card.title:ClearAllPoints()
    card.title:SetPoint("LEFT", pve, "TOPLEFT", x1, dy + r1)
end

local function Layout()
    if not card then return end
    local npath, nsize = CountFont()
    CM.ApplyModuleFont(card.title, nil, TITLE_SIZE, ADDON_NAME, "")
    -- The Premade Groups title, same size and colour as ours.
    local lbl = _G.LFGListFrame and _G.LFGListFrame.CategorySelection and _G.LFGListFrame.CategorySelection.Label
    if lbl and lbl.GetFont then
        local lpath, lsize, lflags = lbl:GetFont()
        if not card.lblSize then card.lblSize = lsize end
        if lpath then lbl:SetFont(lpath, TITLE_SIZE, lflags) end
        local r, g, b = lbl:GetTextColor()
        if r then card.title:SetTextColor(r, g, b, 1) end
    end
    local texPath = TexturePath()
    for i, seg in ipairs(SEGMENTS) do
        local t = card.segs[i]
        if texPath then
            t:SetTexture(texPath)
            t:SetVertexColor(seg.r, seg.g, seg.b, 1)
        else
            t:SetColorTexture(seg.r, seg.g, seg.b, 1)
            t:SetVertexColor(1, 1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
        end
        CM.ApplyModuleFont(card.nums[i], npath, nsize, ADDON_NAME, "OUTLINE")
    end
    CM.ApplyModuleFont(card.empty, npath, nsize, ADDON_NAME, "OUTLINE")
    Place()
end

local shares = {}  -- reused per paint
local function Refresh()
    if not (card and card:IsVisible()) then return end
    local c = Counts(Scope())
    -- Split the bar between the shown outcomes so it always fills.
    local total = 0
    for i, seg in ipairs(SEGMENTS) do
        local v = c[seg.key]
        shares[i] = Get(seg.cfg, true) and v or 0
        total = total + shares[i]
    end
    local bar = card.bar
    local w = bar:GetWidth() or 0
    local textured = TexturePath()
    local x = 0
    for i, seg in ipairs(SEGMENTS) do
        local tex, num = card.segs[i], card.nums[i]
        local sw = (total > 0) and (w * shares[i] / total) or 0
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
        tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
        tex:SetWidth(math.max(sw, 0.01))
        -- Each segment shows its slice of the texture so it reads as one bar.
        if textured and w > 0 then tex:SetTexCoord(x / w, (x + sw) / w, 0, 1) end
        tex:SetShown(sw >= 0.5)
        num:SetFormattedText("%d", c[seg.key])
        num:ClearAllPoints()
        num:SetPoint("CENTER", tex, "CENTER", 0, 0)
        num:SetShown(sw >= 0.5 and (num:GetStringWidth() or 0) + 4 <= sw)
        x = x + sw
    end
    card.empty:SetShown(total == 0)  -- nothing counted yet
end

local BuildCardInto
local function BuildCard()
    if card then return card end
    local ok, built = pcall(BuildCardInto)
    if ok and built then card = built end
    if not ok then geterrorhandler()(built) end
    return card
end

BuildCardInto = function()
    local host = _G.GroupFinderFrame
    local pve = _G.PVEFrame
    if not (host and pve and pve.Inset) then return nil end

    -- Build into a local first so a failure never leaves half a card.
    local card = CreateFrame("Frame", nil, host)
    card:SetAllPoints(host)
    card:SetFrameLevel(host:GetFrameLevel() + 5)

    card.title = card:CreateFontString(nil, "OVERLAY")
    CM.ApplyModuleFont(card.title, nil, 12, ADDON_NAME, "")
    card.title:SetTextColor(1, 0.82, 0, 1)
    card.title:SetText(EllesmereUI.L("M+ Applications"))

    local box = CreateFrame("Frame", nil, card)
    box:EnableMouse(true)
    box:SetScript("OnEnter", ShowTip)
    box:SetScript("OnLeave", HideTip)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)
    local S = ns.Skin()
    if S and S.AddBorder then
        S.AddBorder(box)
    else
        local r, g, b, a = ns.ThemeBorder()
        CM.MakeBorder(box, r, g, b, a)
    end
    card.box = box
    local px = CM.PP.mult
    local bar = CreateFrame("Frame", nil, box)
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", px, -px)
    bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -px, px)
    card.bar = bar
    card.segs, card.nums = {}, {}
    for i = 1, #SEGMENTS do
        card.segs[i] = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        local num = bar:CreateFontString(nil, "OVERLAY")
        CM.ApplyModuleFont(num, nil, 12, ADDON_NAME, "OUTLINE")
        num:SetTextColor(1, 1, 1, 1)
        num:SetJustifyH("CENTER")
        num:SetJustifyV("MIDDLE")
        card.nums[i] = num
    end
    card.empty = bar:CreateFontString(nil, "OVERLAY")
    CM.ApplyModuleFont(card.empty, nil, 12, ADDON_NAME, "OUTLINE")
    card.empty:SetTextColor(1, 1, 1, 0.6)
    card.empty:SetPoint("CENTER", bar, "CENTER", 0, 0)
    card.empty:SetText(EllesmereUI.L("N/A"))
    card.empty:Hide()
    bar:SetScript("OnSizeChanged", function() Refresh() end)
    return card
end

-- Only shown on the Dungeons search, the only category it counts.
local function InDungeonSearch()
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    return sp and sp:IsShown() and sp.categoryID == (GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2) or false
end

-- The status event is registered only while the bar is on.
local ev
local function SyncCountEvent()
    if not ev then return end
    if On() then
        ev:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    else
        ev:UnregisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    end
end

local function Apply()
    if not ns.Enabled() then return end
    SyncCountEvent()
    local on = On()
    local want = on and InDungeonSearch()
    if want then BuildCard() end
    if card then
        card:SetShown(want)
        if want then
            Layout()
        elseif not on and card.lblSize then
            -- Off: title back to its own size.
            local lbl = _G.LFGListFrame and _G.LFGListFrame.CategorySelection and _G.LFGListFrame.CategorySelection.Label
            local lpath, _, lflags = lbl and lbl:GetFont()
            if lpath then lbl:SetFont(lpath, card.lblSize, lflags) end
        end
    end
    Refresh()
end
ns.ApplyApplications = Apply

-------------------------------------------------------------------------------
-- Counting
-------------------------------------------------------------------------------
local isMythicPlus = {}  -- resultID -> is a Mythic+ group
local function LookUpMythicPlus(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if type(info) ~= "table" or IsSecret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    local acts = info.activityIDs
    local aid = (type(acts) == "table" and not IsSecret(acts)) and acts[1] or info.activityID
    if type(aid) ~= "number" or IsSecret(aid) then return nil end
    local ai = C_LFGList.GetActivityInfoTable(aid)
    if type(ai) ~= "table" or IsSecret(ai) or (canaccesstable and not canaccesstable(ai)) then return nil end
    local mp = ai.isMythicPlusActivity
    if IsSecret(mp) then return nil end
    return mp == true
end

local function Count(status, oldStatus, resultID)
    local key = STATUS_KEY[status]
    if type(resultID) ~= "number" or IsSecret(resultID) then return end
    if status == "applied" then
        if oldStatus == "applied" then return end
        isMythicPlus[resultID] = LookUpMythicPlus(resultID)
    elseif isMythicPlus[resultID] == nil then
        isMythicPlus[resultID] = LookUpMythicPlus(resultID)
    end
    local counted = isMythicPlus[resultID]
    if status ~= "applied" and status ~= "invited" then isMythicPlus[resultID] = nil end
    if not key or status == oldStatus or counted ~= true then return end
    local a = Store()
    local t = Fill(a.account); t[key] = t[key] + 1
    t = Fill(a.session); t[key] = t[key] + 1
    t = Counts("character"); t[key] = t[key] + 1
    Refresh()
end

function ns.ResetApplications(scope)
    if not ns.Enabled() then return end
    local a = Store()
    if scope == "account" then
        a.account = Blank()
    elseif scope == "session" then
        a.session = Blank()
    elseif myKey then
        a.chars[myKey] = Blank()
    end
    Refresh()
end

local hooked = false
local function HookPVE()
    local pve = _G.PVEFrame
    if hooked or not pve then return end
    hooked = true
    -- Next frame, after the skin lays the window out.
    pve:HookScript("OnShow", function() C_Timer.After(0, Apply) end)
    if pve:IsShown() then C_Timer.After(0, Apply) end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    if sp then
        sp:HookScript("OnShow", function() C_Timer.After(0, Apply) end)
        sp:HookScript("OnHide", Apply)
    end
end

function ns.Apps_Enable()
    local name, realm = UnitFullName("player")
    name = PlainString(name)
    if name then myKey = name .. "-" .. (PlainString(realm) or MyRealm()) end
    local a = Store()
    if time() - (tonumber(a.session.t) or 0) > SESSION_GAP then a.session = Blank() end
    -- Follow the search rows when they resize.
    if ns.Search_Layout then hooksecurefunc(ns, "Search_Layout", Apply) end
    ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGOUT")
    ev:SetScript("OnEvent", function(self, event, ...)
        if event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            -- Live check: a profile swap can turn the bar off before the next Apply.
            if On() then
                local id, status, oldStatus = ...
                Count(PlainString(status), PlainString(oldStatus), id)
            end
        elseif event == "ADDON_LOADED" then
            if (...) == "Blizzard_GroupFinder" then
                HookPVE()
                self:UnregisterEvent("ADDON_LOADED")
            end
        elseif event == "PLAYER_LOGOUT" then
            Store().session.t = time()
        end
    end)
    HookPVE()
    if not hooked then ev:RegisterEvent("ADDON_LOADED") end
    SyncCountEvent()
end
