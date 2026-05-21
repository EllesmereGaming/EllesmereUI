-------------------------------------------------------------------------------
--  EllesmereUIQoL_Keys.lua
--  /keys slash command: displays party keystone levels in a styled popup.
--  Supports two keystone comm protocols:
--    1) LibOpenRaid (Details, BigWigs): prefix "LRS_LOGGED", logged channel
--       Send: "K,level,mapID,challengeMapID,classID,rating,mythicPlusMapID,specID"
--       Request: "J"
--    2) LibKeystone (DBM): prefix "LibKS", unlogged channel
--       Send: "level,mapID,rating"
--       (no request message -- data is pushed on group join / key change)
-------------------------------------------------------------------------------
-- LibOpenRaid protocol
local LOR_PREFIX      = "LRS_LOGGED"
local LOR_DATA_TAG    = "K"
local LOR_REQUEST_TAG = "J"
-- LibKeystone (DBM) protocol
local LKS_PREFIX      = "LibKS"

local myRealm = (GetRealmName():gsub("%s", ""))
local partyKeys = {}  -- [playerName] = { dungeon = mapID, keyLevel = N, rating = N }
local guildKeys = {}  -- [playerName] = { dungeon = mapID, keyLevel = N, rating = N }
local deferredBroadcast = false
local deferredQuery     = false
local inChallenge       = false

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function PlayerName(unit)
    local name, realm = UnitFullName(unit or "player")
    if not name then return UnitName(unit or "player") or "Unknown" end
    if realm and realm ~= "" and realm ~= myRealm then return name .. "-" .. realm end
    return name
end

local function StripRealm(fullName)
    if not fullName then return "?" end
    if Ambiguate then return Ambiguate(fullName, "short") or fullName end
    return fullName:match("^([^%-]+)") or fullName
end

-- Resolve class color for a player name (checks group units, then guild roster)
local function GetClassColorForName(name)
    local short = StripRealm(name)
    -- Check group units
    local prefix, count
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then prefix, count = "party", GetNumGroupMembers() - 1
    else prefix, count = nil, 0 end
    if prefix then
        for i = 1, count do
            local unit = prefix .. i
            local uName = UnitName(unit)
            if uName and uName == short then
                local _, classFile = UnitClass(unit)
                if classFile then return RAID_CLASS_COLORS[classFile] end
            end
        end
    end
    -- Check player
    if UnitName("player") == short then
        local _, classFile = UnitClass("player")
        if classFile then return RAID_CLASS_COLORS[classFile] end
    end
    -- Check guild roster
    if IsInGuild() and GetNumGuildMembers then
        local total = GetNumGuildMembers()
        for i = 1, total do
            local gName, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
            if gName then
                local gShort = Ambiguate and Ambiguate(gName, "short") or gName:match("^([^%-]+)")
                if gShort == short and classFile then
                    return RAID_CLASS_COLORS[classFile]
                end
            end
        end
    end
    return nil
end

local function GetMyKeystone()
    if not C_MythicPlus then return 0, 0 end
    local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
    local lvl = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0
    return map, lvl
end

local function DungeonNameFromMap(mapID)
    if not mapID or mapID == 0 then return nil end
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        return (C_ChallengeMode.GetMapUIInfo(mapID))
    end
    return "Unknown"
end

local function IsInActiveMPlus()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive()
end

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

-------------------------------------------------------------------------------
--  Keystone read / send / request
-------------------------------------------------------------------------------
local function RecordOwnKey()
    local map, lvl = GetMyKeystone()
    local rating = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        if summary and summary.currentSeasonScore then rating = summary.currentSeasonScore end
    end
    local me = UnitName("player")
    local _, myClassFile = UnitClass("player")
    if me then partyKeys[me] = { dungeon = map, keyLevel = lvl, rating = rating, classFile = myClassFile } end
end

-- LibOpenRaid logged messages use a special encoding:
--   commas → semicolons (first occurrence only on receive, but send replaces first , with ;)
--   newlines → %
--   #commId appended at end
local lorCommCounter = 0
local function EncodeLOR(raw)
    lorCommCounter = lorCommCounter + 1
    -- Replace first comma with semicolon (LOR convention for logged channel)
    local encoded = raw:gsub(",", ";", 1)
    -- Append comm ID
    return encoded .. "#" .. lorCommCounter
end

local function BuildLORPayload()
    local map, lvl = GetMyKeystone()
    local rating = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        if summary and summary.currentSeasonScore then rating = summary.currentSeasonScore end
    end
    local _, classID = UnitClassBase("player")
    local specID = GetSpecializationInfo and GetSpecializationInfo(GetSpecialization() or 1) or 0
    local raw = LOR_DATA_TAG .. "," .. lvl .. "," .. map .. "," .. map .. "," .. (classID or 0) .. "," .. rating .. "," .. map .. "," .. (specID or 0)
    return EncodeLOR(raw), string.format("%d,%d,%d", lvl, map, rating)
end

local function GetGroupChannel()
    if GetNumGroupMembers() <= 1 then return nil end
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then return "RAID" end
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then return "PARTY" end
    -- Instance group (LFG/LFR) -- use INSTANCE_CHAT
    if IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return nil
end

local function BroadcastOwnKey()
    if IsInCombat() or inChallenge then deferredBroadcast = true; return end
    local lorPayload, lksPayload = BuildLORPayload()
    local ch = GetGroupChannel()
    if ch then
        C_ChatInfo.SendAddonMessageLogged(LOR_PREFIX, lorPayload, ch)
        C_ChatInfo.SendAddonMessage(LKS_PREFIX, lksPayload, ch)
    end
    if IsInGuild() then
        C_ChatInfo.SendAddonMessageLogged(LOR_PREFIX, lorPayload, "GUILD")
        C_ChatInfo.SendAddonMessage(LKS_PREFIX, lksPayload, "GUILD")
    end
end

local function QueryPartyKeys()
    if IsInCombat() or inChallenge then deferredQuery = true; return end
    local ch = GetGroupChannel()
    if ch then
        C_ChatInfo.SendAddonMessageLogged(LOR_PREFIX, EncodeLOR(LOR_REQUEST_TAG), ch)
        C_ChatInfo.SendAddonMessage(LKS_PREFIX, "R", ch)
    end
    if IsInGuild() then
        C_ChatInfo.SendAddonMessageLogged(LOR_PREFIX, EncodeLOR(LOR_REQUEST_TAG), "GUILD")
        C_ChatInfo.SendAddonMessage(LKS_PREFIX, "R", "GUILD")
    end
end

-------------------------------------------------------------------------------
--  Popup UI
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local PP = EUI and EUI.PP
local POPUP_W  = 330
local ROW_H    = 20
local ROW_GAP  = 4
local TITLE_H  = 27
local PAD      = 10
local HDR_H    = 18  -- section header height ("Party", "Guild")
local HDR_GAP  = 1   -- gap after section header
local SEC_GAP  = 20  -- gap before Guild section
local MAX_CONTENT_H = 300

local popup, rowFrames
local ShowKeystonePopup  -- forward declaration

local function ResolveFont()
    return (EUI and EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
end

local function ResolveOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""
end

local function MakeLabel(parent, size, _, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local flags = ResolveOutline()
    fs:SetFont(ResolveFont(), size, flags)
    if r then fs:SetTextColor(r, g or 1, b or 1, a or 1) end
    if flags == "" then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
    return fs
end

local function MakeSolid(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetColorTexture(r, g, b, a)
    return t
end

local function BuildPopup()
    if popup then return popup end
    rowFrames = {}

    popup = CreateFrame("Frame", "EUIKeysPopup", UIParent)
    popup:SetSize(POPUP_W, 100)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(s) s:StartMoving() end)
    popup:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

    local bg = popup:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    bg:SetTexCoord(0.25, 1, 0, 0.75)
    local overlay = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlay:SetAllPoints()
    overlay:SetColorTexture(0, 0, 0, 0.55)

    if PP and PP.CreateBorder then PP.CreateBorder(popup, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end

    local hdrBg = MakeSolid(popup, "BORDER", 0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1); hdrBg:SetPoint("TOPRIGHT", -1, 0); hdrBg:SetHeight(TITLE_H)

    local title = MakeLabel(popup, 11, "OUTLINE", 1, 1, 1, 1)
    title:SetPoint("TOPLEFT", PAD, -8); title:SetText("EllesmereUI Keystones")

    local ICON_SZ = 14
    local ICON_ALPHA = 0.5

    local xBtn = CreateFrame("Button", nil, popup)
    xBtn:SetSize(ICON_SZ, ICON_SZ)
    xBtn:SetPoint("RIGHT", hdrBg, "RIGHT", -8, 0)
    local xTex = xBtn:CreateTexture(nil, "ARTWORK")
    xTex:SetAllPoints()
    xTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    xTex:SetAlpha(ICON_ALPHA)
    xBtn:SetScript("OnEnter", function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave", function() xTex:SetAlpha(ICON_ALPHA) end)
    xBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Refresh button
    local refBtn = CreateFrame("Button", nil, popup)
    refBtn:SetSize(ICON_SZ, ICON_SZ)
    refBtn:SetPoint("RIGHT", xBtn, "LEFT", -6, 0)
    local refTex = refBtn:CreateTexture(nil, "ARTWORK")
    refTex:SetAllPoints()
    refTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\unlock-reset.png")
    refTex:SetAlpha(ICON_ALPHA)
    refBtn:SetScript("OnEnter", function()
        refTex:SetAlpha(1)
        if EUI and EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(refBtn, "Refresh Data") end
    end)
    refBtn:SetScript("OnLeave", function()
        refTex:SetAlpha(ICON_ALPHA)
        if EUI and EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    local refLocked = false
    refBtn:SetScript("OnClick", function()
        if refLocked then return end
        refLocked = true
        refBtn:EnableMouse(false)
        refTex:SetAlpha(0.15)
        RecordOwnKey()
        if IsInGroup() then QueryPartyKeys() end
        ShowKeystonePopup()
        if IsInGroup() then C_Timer.After(1.0, ShowKeystonePopup) end
        C_Timer.After(2, function()
            refLocked = false
            refBtn:EnableMouse(true)
            refTex:SetAlpha(ICON_ALPHA)
        end)
    end)

    if EUI and EUI.RegisterEscapeClose then EUI.RegisterEscapeClose(popup) end

    -- Scroll frame for content
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", PAD, -(TITLE_H + 8))
    sf:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local child = self:GetScrollChild()
        local maxS = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 20)))
    end)
    popup._body = CreateFrame("Frame", nil, sf)
    popup._body:SetWidth(POPUP_W - PAD * 2)
    popup._body:SetHeight(1)
    sf:SetScrollChild(popup._body)
    popup._sf = sf

    -- Apply saved scale
    local cfg = EllesmereUIDB and EllesmereUIDB.keystonePopup
    popup:SetScale(cfg and cfg.scale or 1.05)

    popup:Hide()
    return popup
end

local function AcquireRow(i)
    if rowFrames[i] then return rowFrames[i] end
    local p = BuildPopup()
    local r = CreateFrame("Frame", nil, p._body)
    r:SetHeight(ROW_H)

    if i % 2 == 0 then
        local alt = MakeSolid(r, "BACKGROUND", 0, 0, 0, 0.15)
        alt:SetAllPoints()
    end

    r._nameFS = MakeLabel(r, 11, nil, 1, 1, 1, 0.85)
    r._nameFS:SetPoint("LEFT", 2, 0); r._nameFS:SetWidth(80); r._nameFS:SetJustifyH("LEFT")
    r._nameFS:SetWordWrap(false)

    r._ratingFS = MakeLabel(r, 10, nil, 0.6, 0.6, 0.6, 1)
    r._ratingFS:SetPoint("LEFT", r._nameFS, "RIGHT", 4, 0); r._ratingFS:SetWidth(40); r._ratingFS:SetJustifyH("LEFT")

    r._dungeonFS = MakeLabel(r, 11, nil, 0.7, 0.7, 0.7, 1)
    r._dungeonFS:SetPoint("LEFT", r._ratingFS, "RIGHT", 4, 0); r._dungeonFS:SetWidth(130); r._dungeonFS:SetJustifyH("LEFT")
    r._dungeonFS:SetWordWrap(false)

    r._levelFS = MakeLabel(r, 11, "OUTLINE", 1, 1, 1, 1)
    r._levelFS:SetPoint("RIGHT", -2, 0); r._levelFS:SetJustifyH("RIGHT")

    local sep = r:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.10)
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(sep) end
    sep:SetHeight((PP and PP.mult) or 1)
    local gapMid = -math.floor(ROW_GAP / 2)
    sep:SetPoint("BOTTOMLEFT", 0, gapMid); sep:SetPoint("BOTTOMRIGHT", 0, gapMid)

    rowFrames[i] = r
    return r
end

-- Section header pool
local secHeaders = {}
local function AcquireSecHeader(i)
    if secHeaders[i] then return secHeaders[i] end
    local p = BuildPopup()
    local h = CreateFrame("Frame", nil, p._body)
    h:SetHeight(HDR_H)
    h._label = MakeLabel(h, 10, "OUTLINE", 1, 1, 1, 0.56)
    h._label:SetPoint("LEFT", 0, 0)
    h._label:SetJustifyH("LEFT")
    secHeaders[i] = h
    return h
end

local function GetTextSize()
    local cfg = EllesmereUIDB and EllesmereUIDB.keystonePopup
    return cfg and cfg.textSize or 11
end

local function ApplyRowFontSize(r)
    local sz = GetTextSize()
    local font = ResolveFont()
    local flags = ResolveOutline()
    r._nameFS:SetFont(font, sz, flags)
    r._ratingFS:SetFont(font, sz - 1, flags)
    r._dungeonFS:SetFont(font, sz, flags)
    r._levelFS:SetFont(font, sz, flags)
end

local function PopulateRow(r, e)
    ApplyRowFontSize(r)
    r._nameFS:SetText(StripRealm(e.name)); r._nameFS:SetWidth(80)
    local cc = GetClassColorForName(e.name)
    if not cc and e.classFile then cc = RAID_CLASS_COLORS[e.classFile] end
    if cc then r._nameFS:SetTextColor(cc.r, cc.g, cc.b, 1)
    else r._nameFS:SetTextColor(1, 1, 1, 0.85) end
    r._ratingFS:SetText(e.rating and e.rating > 0 and tostring(e.rating) or "")
    if e.dungeonName then
        r._dungeonFS:SetText(e.dungeonName)
        r._dungeonFS:SetTextColor(0.7, 0.7, 0.7, 1)
        r._levelFS:SetText("+" .. e.lvl)
        if e.lvl >= 12 then      r._levelFS:SetTextColor(1, 0.5, 0, 1)
        elseif e.lvl >= 10 then   r._levelFS:SetTextColor(0.63, 0.2, 0.93, 1)
        elseif e.lvl >= 7 then    r._levelFS:SetTextColor(0, 0.44, 0.87, 1)
        elseif e.lvl >= 4 then    r._levelFS:SetTextColor(0.12, 1, 0, 1)
        else                      r._levelFS:SetTextColor(1, 1, 1, 1) end
    else
        r._dungeonFS:SetText("No keystone"); r._dungeonFS:SetTextColor(0.5, 0.5, 0.5, 0.7)
        r._levelFS:SetText("")
    end
end

ShowKeystonePopup = function()
    RecordOwnKey()
    local p = BuildPopup()
    local body = p._body
    local contentW = POPUP_W - PAD * 2

    -- Collect party keys
    local partyEntries = {}
    for name, info in pairs(partyKeys) do
        local dName = DungeonNameFromMap(info.dungeon)
        partyEntries[#partyEntries + 1] = { name = name, dungeonName = dName, lvl = info.keyLevel or 0, rating = info.rating or 0, classFile = info.classFile }
    end
    table.sort(partyEntries, function(a, b)
        if a.lvl ~= b.lvl then return a.lvl > b.lvl end
        return a.name < b.name
    end)

    -- Collect guild keys
    local guildEntries = {}
    for name, info in pairs(guildKeys) do
        local dName = DungeonNameFromMap(info.dungeon)
        guildEntries[#guildEntries + 1] = { name = name, dungeonName = dName, lvl = info.keyLevel or 0, rating = info.rating or 0, classFile = info.classFile }
    end
    table.sort(guildEntries, function(a, b)
        if a.lvl ~= b.lvl then return a.lvl > b.lvl end
        return a.name < b.name
    end)

    -- Hide all pooled frames
    for i = 1, #rowFrames do rowFrames[i]:Hide() end
    for i = 1, #secHeaders do secHeaders[i]:Hide() end

    local curY = 0
    local rowIdx = 0
    local hdrIdx = 0

    -- Party section
    hdrIdx = hdrIdx + 1
    local partyHdr = AcquireSecHeader(hdrIdx)
    partyHdr._label:SetText("PARTY")
    partyHdr:ClearAllPoints()
    partyHdr:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
    partyHdr:SetWidth(contentW)
    partyHdr:Show()
    curY = curY - HDR_H - HDR_GAP

    if #partyEntries == 0 then
        rowIdx = rowIdx + 1
        local r = AcquireRow(rowIdx)
        r._nameFS:SetText("No keystones found"); r._nameFS:SetWidth(contentW)
        r._nameFS:SetTextColor(0.5, 0.5, 0.5, 0.7)
        r._ratingFS:SetText(""); r._dungeonFS:SetText(""); r._levelFS:SetText("")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
        r:Show()
        curY = curY - ROW_H
    else
        for _, e in ipairs(partyEntries) do
            rowIdx = rowIdx + 1
            local r = AcquireRow(rowIdx)
            PopulateRow(r, e)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
            r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
            r:Show()
            curY = curY - (ROW_H + ROW_GAP)
        end
        curY = curY + ROW_GAP -- remove trailing gap
    end

    -- Guild section
    curY = curY - SEC_GAP
    hdrIdx = hdrIdx + 1
    local guildHdr = AcquireSecHeader(hdrIdx)
    guildHdr._label:SetText("GUILD")
    guildHdr:ClearAllPoints()
    guildHdr:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
    guildHdr:SetWidth(contentW)
    guildHdr:Show()
    curY = curY - HDR_H - HDR_GAP

    if #guildEntries == 0 then
        rowIdx = rowIdx + 1
        local r = AcquireRow(rowIdx)
        r._nameFS:SetText("Waiting for data..."); r._nameFS:SetWidth(contentW)
        r._nameFS:SetTextColor(0.5, 0.5, 0.5, 0.5)
        r._ratingFS:SetText(""); r._dungeonFS:SetText(""); r._levelFS:SetText("")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
        r:Show()
        curY = curY - ROW_H
    else
        for _, e in ipairs(guildEntries) do
            rowIdx = rowIdx + 1
            local r = AcquireRow(rowIdx)
            PopulateRow(r, e)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
            r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
            r:Show()
            curY = curY - (ROW_H + ROW_GAP)
        end
        curY = curY + ROW_GAP
    end

    -- Set scroll child height
    local totalH = math.abs(curY)
    body:SetHeight(totalH)

    -- Size popup: content capped at MAX_CONTENT_H, scrollable beyond that
    local visH = math.min(totalH, MAX_CONTENT_H)
    p:SetHeight(TITLE_H + 8 + visH + PAD)

    p:Show()
end

local function RefreshPopupIfOpen()
    if popup and popup:IsShown() then ShowKeystonePopup() end
end
_G._EUI_RefreshKeystonePopup = RefreshPopupIfOpen

-------------------------------------------------------------------------------
--  Events
--  Prefix registration must happen at file scope, but the event frame only
--  starts listening once /keys has been opened at least once so we don't
--  broadcast addon messages on every login/reload for users who never use it.
-------------------------------------------------------------------------------
local evFrame = CreateFrame("Frame")
C_ChatInfo.RegisterAddonMessagePrefix(LOR_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(LKS_PREFIX)

local eventsRegistered = false
local function RegisterKeyEvents()
    if eventsRegistered then return end
    eventsRegistered = true
    evFrame:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
    evFrame:RegisterEvent("CHAT_MSG_ADDON")
    evFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    evFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    evFrame:RegisterEvent("CHALLENGE_MODE_START")
    evFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
end

local function NormalizeSender(sender)
    if not sender then return nil end
    local base, realm = sender:match("^([^%-]+)%-?(.*)$")
    if realm == "" or realm == myRealm then return base end
    return sender
end

evFrame:SetScript("OnEvent", function(_, ev, ...)
    -- LibOpenRaid protocol (Details, BigWigs): logged channel
    if ev == "CHAT_MSG_ADDON_LOGGED" then
        local prefix, body, channel, sender = ...
        if prefix ~= LOR_PREFIX or inChallenge then return end
        local decoded = body:gsub("%%", "\n")
        decoded = decoded:gsub(";", ",", 1)
        decoded = decoded:gsub("#([^#]+)$", "")
        local tag = decoded:sub(1, 1)
        if tag == LOR_REQUEST_TAG then
            BroadcastOwnKey()
        elseif tag == LOR_DATA_TAG then
            -- Format: K,level,mapID,challengeMapID,classID,rating,mythicPlusMapID,specID
            local tokens = { strsplit(",", decoded) }
            local lvl = tonumber(tokens[2]) or 0
            local map = tonumber(tokens[3]) or 0
            local cid = tonumber(tokens[5])
            local rtg = tonumber(tokens[6]) or 0
            -- Convert numeric classID to classFile for RAID_CLASS_COLORS
            local classFile
            if cid and cid > 0 then
                local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo(cid)
                if info then classFile = info.classFile end
            end
            sender = NormalizeSender(sender)
            if sender then
                local tbl = (channel == "GUILD") and guildKeys or partyKeys
                tbl[sender] = { dungeon = map, keyLevel = lvl, rating = rtg, classFile = classFile }
                RefreshPopupIfOpen()
            end
        end
    -- LibKeystone protocol (DBM): unlogged channel
    elseif ev == "CHAT_MSG_ADDON" then
        local prefix, body, channel, sender = ...
        if prefix ~= LKS_PREFIX or inChallenge then return end
        local tokens = { strsplit(",", body) }
        local lvl = tonumber(tokens[1]) or 0
        local map = tonumber(tokens[2]) or 0
        local rtg = tonumber(tokens[3]) or 0
        sender = NormalizeSender(sender)
        if sender then
            local tbl = (channel == "GUILD") and guildKeys or partyKeys
            tbl[sender] = { dungeon = map, keyLevel = lvl, rating = rtg }
            RefreshPopupIfOpen()
        end
    elseif ev == "CHALLENGE_MODE_START" then
        inChallenge = true
    elseif ev == "CHALLENGE_MODE_COMPLETED" then
        inChallenge = false
    elseif ev == "PLAYER_REGEN_ENABLED" then
        if deferredBroadcast then deferredBroadcast = false; BroadcastOwnKey() end
        if deferredQuery then deferredQuery = false; QueryPartyKeys() end
    elseif ev == "GROUP_ROSTER_UPDATE" then
        inChallenge = IsInActiveMPlus()
        RecordOwnKey()
        if IsInGroup() and not inChallenge and not IsInCombat() then
            C_Timer.After(0.5 + math.random() * 0.3, function()
                if IsInGroup() and not inChallenge and not IsInCombat() then
                    BroadcastOwnKey()
                    QueryPartyKeys()
                end
            end)
        end
        RefreshPopupIfOpen()
    elseif ev == "BAG_UPDATE_DELAYED" then
        local me = UnitName("player")
        local map, lvl = GetMyKeystone()
        local cur = partyKeys[me]
        if not cur or cur.dungeon ~= map or cur.keyLevel ~= lvl then
            RecordOwnKey()
            if IsInGroup() and not inChallenge then BroadcastOwnKey() end
            RefreshPopupIfOpen()
        end
    end
end)

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
SLASH_EUIKEYS1 = "/keys"
SLASH_EUIKEYS2 = "/key"
SLASH_EUIKEYS3 = "/ekeys"
SlashCmdList["EUIKEYS"] = function()
    local cfg = EllesmereUIDB and EllesmereUIDB.keystonePopup
    if cfg and cfg.enabled == false then
        EllesmereUI.Print("|cff0cd29d[EllesmereUI]|r Keystone popup is disabled. Enable it in QoL > Keys & Logs.")
        return
    end
    RegisterKeyEvents()
    RecordOwnKey()
    if IsInGroup() then
        QueryPartyKeys()
        ShowKeystonePopup()
        C_Timer.After(1.0, ShowKeystonePopup)
    else
        ShowKeystonePopup()
    end
end
