-------------------------------------------------------------------------------
--  EllesmereUIQoL_Keys.lua
--  /keys slash command: displays party keystone levels in a styled popup.
--  Uses LibKeystone (BigWigs/DBM) for keystone data exchange.
-------------------------------------------------------------------------------
local LibKeystone = LibStub and LibStub("LibKeystone", true)

local myRealm = (GetRealmName():gsub("%s", ""))
local partyKeys = {}  -- [playerName] = { dungeon = mapID, keyLevel = N, rating = N }

-- Dungeon mapID -> teleport spellID
-- mapIDs here match what C_ChallengeMode returns and what keystone links store.
-- Built dynamically from C_ChallengeMode.GetMapTable + spell lookup.
local MAP_TELEPORT_SPELLS = {}
do
    -- Spell IDs indexed by dungeon name (case-insensitive matching)
    local TELEPORT_BY_NAME = {
        ["magisters' terrace"]         = 1254572,
        ["терраса магистров"]          = 1254572,
        ["maisara caverns"]            = 1254559,
        ["пещеры майсара"]             = 1254559,
        ["nexus-point xenas"]          = 1254563,
        ["нексус-пойнт ксенас"]        = 1254563,
        ["нексус-поинт ксенас"]        = 1254563,
        ["windrunner spire"]           = 1254400,
        ["шпиль ветрокрылых"]          = 1254400,
        ["algeth'ar academy"]          = 393273,
        ["академия алгет'ар"]          = 393273,
        ["академия алгетар"]           = 393273,
        ["pit of saron"]               = 1254555,
        ["яма сарона"]                 = 1254555,
        ["seat of the triumvirate"]    = 1254551,
        ["престол триумвирата"]        = 1254551,
        ["skyreach"]                   = 159898,
        ["небесный путь"]              = 159898,
    }
    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local maps = C_ChallengeMode.GetMapTable()
        for _, mapID in ipairs(maps) do
            local name = C_ChallengeMode.GetMapUIInfo(mapID)
            if name then
                local spellID = TELEPORT_BY_NAME[name:lower()]
                if spellID then
                    MAP_TELEPORT_SPELLS[mapID] = spellID
                end
            end
        end
    end

    -- Clean resolver: dungeon display name -> teleport spellID. Returns a plain
    -- integer literal (never a secret value) or nil. Used by the LFG teleport
    -- prompt to map an accepted dungeon's name to its teleport spell without
    -- touching any secret LFG field. Strips a trailing parenthetical suffix.
    EllesmereUI.ResolveTeleportSpellByName = function(displayName)
        if type(displayName) ~= "string" then return nil end
        local n = displayName:lower():gsub("%s*%b()%s*$", "")
        return TELEPORT_BY_NAME[n]
    end
end
local guildKeys = {}  -- [playerName] = { dungeon = mapID, keyLevel = N, rating = N }

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


-------------------------------------------------------------------------------
--  Keystone read / request
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

local function QueryPartyKeys()
    if not LibKeystone then return end
    if IsInGroup() then LibKeystone.Request("PARTY") end
    LibKeystone.Request("GUILD")
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
    return (EUI and EUI.GetFontPath and EUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF"
end

local function ResolveOutline()
    return (EUI and EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("extras")) or ""
end

local function MakeLabel(parent, size, _, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local flags = ResolveOutline()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, flags == "") end
    fs:SetFont(ResolveFont(), size, flags)
    if r then fs:SetTextColor(r, g or 1, b or 1, a or 1) end
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

    -- Teleport button overlaying the dungeon name
    local tpBtn = CreateFrame("Button", nil, r, "InsecureActionButtonTemplate")
    tpBtn:SetPoint("TOPLEFT", r._dungeonFS, "TOPLEFT", 0, 0)
    tpBtn:SetPoint("BOTTOMLEFT", r._dungeonFS, "BOTTOMLEFT", 0, 0)
    tpBtn:SetWidth(130)
    tpBtn:SetFrameLevel(r:GetFrameLevel() + 5)
    tpBtn:RegisterForClicks("AnyUp", "AnyDown")
    tpBtn:SetAttribute("type", "spell")
    local EG = EllesmereUI.ELLESMERE_GREEN
    tpBtn:SetScript("OnEnter", function()
        local sid = tpBtn._spellID
        if not sid then return end
        local known = IsPlayerSpell(sid)
        if known then
            if EG then r._dungeonFS:SetTextColor(EG.r, EG.g, EG.b, 1) end
            local cdInfo = C_Spell.GetSpellCooldown(sid)
            if cdInfo and cdInfo.duration and cdInfo.duration > 0 then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(tpBtn, "Portal on Cooldown")
                end
            end
        end
    end)
    tpBtn:SetScript("OnLeave", function()
        r._dungeonFS:SetTextColor(0.7, 0.7, 0.7, 1)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    tpBtn:Hide()
    r._tpBtn = tpBtn

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
        -- Teleport button
        local spellID = e.mapID and MAP_TELEPORT_SPELLS[e.mapID]
        if spellID and r._tpBtn then
            r._tpBtn._spellID = spellID
            r._tpBtn:SetAttribute("spell", spellID)
            r._tpBtn:Show()
        elseif r._tpBtn then
            r._tpBtn._spellID = nil
            r._tpBtn:Hide()
        end
    else
        r._dungeonFS:SetText("No keystone"); r._dungeonFS:SetTextColor(0.5, 0.5, 0.5, 0.7)
        r._levelFS:SetText("")
        if r._tpBtn then r._tpBtn:Hide() end
    end
end

ShowKeystonePopup = function()
    RecordOwnKey()
    local p = BuildPopup()
    local body = p._body
    local contentW = POPUP_W - PAD * 2

    -- Collect party keys (only current group members)
    local currentMembers = {}
    currentMembers[PlayerName("player")] = true
    if IsInGroup() then
        local prefix = IsInRaid() and "raid" or "party"
        local count = GetNumGroupMembers()
        for i = 1, (IsInRaid() and count or count - 1) do
            local name = PlayerName(prefix .. i)
            if name then currentMembers[name] = true end
        end
    end
    local partyEntries = {}
    for name, info in pairs(partyKeys) do
        if currentMembers[name] or currentMembers[StripRealm(name)] then
            local dName = DungeonNameFromMap(info.dungeon)
            partyEntries[#partyEntries + 1] = { name = name, dungeonName = dName, lvl = info.keyLevel or 0, rating = info.rating or 0, classFile = info.classFile, mapID = info.dungeon }
        end
    end
    table.sort(partyEntries, function(a, b)
        if a.lvl ~= b.lvl then return a.lvl > b.lvl end
        return a.name < b.name
    end)

    -- Collect guild keys (exclude ourselves)
    local guildEntries = {}
    local myName = PlayerName("player")
    for name, info in pairs(guildKeys) do
        if name ~= myName and StripRealm(name) ~= StripRealm(myName) and (info.keyLevel or 0) > 0 then
            local dName = DungeonNameFromMap(info.dungeon)
            guildEntries[#guildEntries + 1] = { name = name, dungeonName = dName, lvl = info.keyLevel, rating = info.rating or 0, classFile = info.classFile, mapID = info.dungeon }
        end
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
--  LibKeystone callback
--  Receives keystone data from any player running BigWigs/DBM (or any addon
--  that embeds LibKeystone). No manual comm handling needed.
-------------------------------------------------------------------------------
local lksCallbackTable = {}
if LibKeystone then
    LibKeystone.Register(lksCallbackTable, function(keyLevel, keyMapID, playerRating, playerName, channel)
        if not playerName then return end
        local tbl = (channel == "GUILD") and guildKeys or partyKeys
        tbl[playerName] = { dungeon = keyMapID, keyLevel = keyLevel, rating = playerRating }
        RefreshPopupIfOpen()
    end)
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
do
    local cfg = EllesmereUIDB and EllesmereUIDB.keystonePopup
    local enabled = not cfg or cfg.enabled ~= false

    SLASH_EUIKEYS1 = "/keys"
    SLASH_EUIKEYS2 = "/ekeys"
    if enabled then
        SLASH_EUIKEYS3 = "/key"
    end

    SlashCmdList["EUIKEYS"] = function()
        if not enabled then return end
        RecordOwnKey()
        QueryPartyKeys()
        ShowKeystonePopup()
        C_Timer.After(1.0, ShowKeystonePopup)
    end
end
