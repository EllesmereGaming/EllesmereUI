if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Friends_Tiles_121.lua
--  EllesmereUI tile styling for the 12.1 Social UI friends list.
--
--  DECORATION ONLY. This file never creates a row, never writes element data,
--  and never mutates Blizzard's data provider. That restraint is the entire
--  design, and it is not stylistic caution -- it is the conclusion of a taint
--  bisect run against 12.1:
--
--    overlay off entirely .............................. whispers clean
--    our rows, every decoration disabled .............. whispers TAINTED
--    Blizzard's rows, only MoveNode re-parenting ...... whispers TAINTED
--
--  Any mutation of the friends list data taints the execution that Blizzard's
--  secure OnClick depends on; that reaches SetTellTarget, whose whisper target
--  is a secret value in 12.1, and BNet whispers stop opening. Styling was the
--  one thing the bisect cleared. So we style, and we touch nothing else.
--
--  Blizzard therefore owns: the ScrollBox, the provider, row creation, row
--  population, the click handler and the right-click menu. We own: paint.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local EG = EllesmereUI.ELLESMERE_GREEN

-- Style page choice for this module: "eui" | "blizzard" | "classic", read from
-- the real profile once and latched for the session (a profile switch prompts
-- for a reload instead). Both stock styles mean the same here -- there is no
-- vanilla version of this list -- so they keep Blizzard's own list and cards
-- and add only the EllesmereUI decoration (class icon, class-coloured name,
-- region mark). The main file's legacy-skin switch reads it too.
function ns.FR_Style()
    local v = ns._frStyle
    if v == nil then
        local db = _G._EFR_DB
        local p = db and db.profile and db.profile.friends
        if not p then return "eui" end
        v = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "eui"
        ns._frStyle = v
    end
    return v
end

-- External weak-keyed state. Never write custom keys onto a Blizzard frame.
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Tuning
-------------------------------------------------------------------------------
-- ROW HEIGHT IS BLIZZARD'S. DO NOT TRY TO CHANGE IT.
--
-- Their height is 70 (85 with larger text), from
-- FriendsListSocialCardMixin.GetActiveBaseHeight, captured by REFERENCE into the view's
-- extent registration at its OnLoad -- before this addon exists, so replacing the mixin
-- function afterwards cannot reach it. The only lever is overwriting that stored
-- registration, i.e. writing into view's own TemplateRegistrations table.
--
-- That write was TESTED and it TAINTS BNet whispers: the extent calculator is
-- read during layout, layout builds the rows, and a row built from an execution
-- that read our value carries taint into the secure OnClick and on into
-- SetTellTarget (whose whisper target is a secret value in 12.1). With the
-- write disabled and every other decoration below still active, whispers are
-- clean -- so decoration is fine and this one write was the whole problem.
--
-- CLOSED. Two separate in-game tests, both TAINTED:
--   1. reg.baseHeight = 46 AND reg.baseHeightCalculator = our closure
--   2. reg.baseHeightCalculator = nil, reg.baseHeight = 46  (plain number,
--      nothing of ours executing inside their layout pass)
-- Test 2 is the decisive one: Blizzard's own code merely READS a number out of
-- its own table, and that is still enough. So it is not about our code running
-- in their path -- reading any value an addon wrote taints the execution, and
-- that execution builds the rows whose secure OnClick opens the whisper menu.
--
-- 70 (85 at larger text) is therefore a hard floor. The only remaining lever on
-- density is the GAME's text-size setting: CalculateScaledHeight runs the base
-- through TextSizeManager:GetScaledValueWeighted with scaleWeight 0.6, so a
-- below-default text size genuinely scales the row under 70.
--
-- Permanently false. Do not re-attempt; both shapes are already disproven.
local TILE_FORCE_HEIGHT = false
local TILE_TARGET_H     = 46

-- Kill switch for all tile decoration. Proven taint-free, so this is only a
-- convenience for future bisects -- leave it true.
local TILE_PAINT = true

-- Left inset of the text block, derived rather than fixed: the class icon is a
-- square that spans the row height, so the text starts at rowHeight + a gutter.
-- Resolved per paint from the row's live height.
local TILE_TEXT_GAP  = 4
-- Three lines, each its own size: Battle.net name / character name + level / location.
local TILE_NAME_SIZE = 15
local TILE_CHAR_SIZE = 12
local TILE_INFO_SIZE = 12
local TILE_LINE_GAP  = -5
-- The row height is Blizzard's now (GetActiveBaseHeight = 70, or 85 in the
-- expanded text-size layout), and we cannot change it without touching their
-- view's extent calculator -- which is provider-adjacent, and provider contact
-- is what taints whispers. So the text block is anchored to the row's vertical
-- CENTRE rather than pinned to the top: it then sits correctly at any height
-- Blizzard picks. The block is centred per paint from its measured height (the
-- line count varies), so there is no fixed vertical offset any more.

local MODERN_BLIZZ_TEX = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"
local TEX_BASE         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local MB_L, MB_R, MB_T, MB_B = 0.25, 1, 0, 0.75

local TILE_ONLINE_MASK_TEX = TEX_BASE .. "gradient-lr.tga"
local TILE_ONLINE_BG_ALPHA = 0.25
local TILE_HOVER_MASK_TEX  = TEX_BASE .. "fade-right.tga"
local TILE_HOVER_ALPHA     = 0.2
-- Selection reuses the hover treatment and draws on its own layer ABOVE it, so
-- a selected row that is also hovered shows both and reads brighter.
local TILE_SEL_ALPHA       = 0.4

local OFFLINE_ICON         = "Interface\\AddOns\\EllesmereUIFriends\\Media\\offline.png"
local FACTION_TEX_ALLIANCE = "Interface\\AddOns\\EllesmereUIFriends\\Media\\alliance.png"
local FACTION_TEX_HORDE    = "Interface\\AddOns\\EllesmereUIFriends\\Media\\horde.png"
local FACTION_TEX_NEUTRAL  = "Interface\\AddOns\\EllesmereUIFriends\\Media\\neutral.png"

local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({ "modern", "dark", "light", "clean" }) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
local CLASS_SPRITE_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

local MINI_DISPLAY = {
    namerica = "North America", samerica = "South America",
    australia = "Australia", europe = "Europe",
    russia = "Russia", korea = "Korea",
    taiwan = "Taiwan", china = "China",
}

local _orbFile, _orbL, _orbR, _orbT, _orbB
do
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
    if info and info.file then
        _orbFile = info.file
        local aL, aR = info.leftTexCoord or 0, info.rightTexCoord or 1
        local aT, aB = info.topTexCoord or 0, info.bottomTexCoord or 1
        _orbL, _orbR, _orbT, _orbB = aL, aL + (aR - aL) / 6, aT, aT + (aB - aT) / 2
    end
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function FriendsDB()
    local db = _G._EFR_DB
    return db and db.profile and db.profile.friends
end

local function Enabled()
    local f = FriendsDB()
    return f ~= nil and f.enabled ~= false
end

local function FontPath()
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends")) or STANDARD_TEXT_FONT
end

local classFileByLocalName = {}
local function BuildClassNameLookup()
    if next(classFileByLocalName) then return end
    if LOCALIZED_CLASS_NAMES_MALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE) do classFileByLocalName[name] = token end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do classFileByLocalName[name] = token end
    end
end

local function GetClassFile(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not gi then return nil end
    if gi.classID and gi.classID > 0 then
        local _, classFile = GetClassInfo(gi.classID)
        if classFile then return classFile end
    end
    if gi.className then
        BuildClassNameLookup()
        return classFileByLocalName[gi.className]
    end
    return nil
end

local function IsSameProjectOnline(gi)
    if not (gi and gi.isOnline) then return false end
    if gi.clientProgram ~= BNET_CLIENT_WOW then return false end
    return gi.wowProjectID == WOW_PROJECT_ID or gi.wowProjectID == nil
end

local function TileState(accountInfo)
    local gi = accountInfo and accountInfo.gameAccountInfo
    if not (gi and gi.isOnline) then return "offline" end
    return IsSameProjectOnline(gi) and "retail" or "other_game"
end

-- Legacy ||EUI:Group|| tags are stripped from any note we display.
local EUI_NOTE_TAG, EUI_NOTE_END = "||EUI:", "||"
local function StripNoteTag(note)
    if not note or note == "" then return note end
    local s = note:find(EUI_NOTE_TAG, 1, true)
    if not s then return note end
    local e = note:find(EUI_NOTE_END, s + #EUI_NOTE_TAG, true)
    if not e then return note end
    local clean = note:sub(1, s - 1)
    return (clean:match("^(.-)%s*$")) or clean
end

-------------------------------------------------------------------------------
--  One-time structure per pooled card
-------------------------------------------------------------------------------
local function SkinStructure(card)
    local d = GetFFD(card)
    if d.skinned then return d end
    d.skinned = true

    d.tileBg = card:CreateTexture(nil, "BACKGROUND", nil, 2)
    d.tileBg:SetAllPoints()
    d.tileBg:SetColorTexture(0, 0, 0, 0.10)

    d.onlineBg = card:CreateTexture(nil, "BACKGROUND", nil, 3)
    d.onlineBg:SetTexture(MODERN_BLIZZ_TEX)
    d.onlineBg:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.onlineBg:SetAllPoints()
    d.onlineBg:SetAlpha(TILE_ONLINE_BG_ALPHA)
    d.onlineBg:Hide()
    d.onlineMask = card:CreateMaskTexture()
    d.onlineMask:SetTexture(TILE_ONLINE_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.onlineMask:SetAllPoints(d.onlineBg)
    d.onlineBg:AddMaskTexture(d.onlineMask)

    d.factionBg = card:CreateTexture(nil, "BACKGROUND", nil, 4)

    d.hoverBar = card:CreateTexture(nil, "ARTWORK", nil, -7)
    d.hoverBar:SetAllPoints()
    d.hoverBar:SetTexture(MODERN_BLIZZ_TEX)
    d.hoverBar:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.hoverBar:SetAlpha(TILE_HOVER_ALPHA)
    d.hoverBar:Hide()
    d.hoverMask = card:CreateMaskTexture()
    d.hoverMask:SetTexture(TILE_HOVER_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.hoverMask:SetAllPoints(d.hoverBar)
    d.hoverBar:AddMaskTexture(d.hoverMask)

    d.hoverFill = card:CreateTexture(nil, "ARTWORK", nil, -8)
    d.hoverFill:SetAllPoints()
    d.hoverFill:SetColorTexture(1, 1, 1, 0.02)
    d.hoverFill:SetBlendMode("ADD")
    d.hoverFill:Hide()

    card:HookScript("OnEnter", function() d.hoverBar:Show(); d.hoverFill:Show() end)
    card:HookScript("OnLeave", function() d.hoverBar:Hide(); d.hoverFill:Hide() end)

    -- Selection: same look as hover, own sublevels (-5/-6) so it sits above the
    -- hover pair (-7/-8) rather than replacing it. Its own mask texture, since
    -- AddMaskTexture is additive and sharing one would stack on the hover bar.
    d.selBar = card:CreateTexture(nil, "ARTWORK", nil, -5)
    d.selBar:SetAllPoints()
    d.selBar:SetTexture(MODERN_BLIZZ_TEX)
    d.selBar:SetTexCoord(MB_L, MB_R, MB_T, MB_B)
    d.selBar:SetAlpha(TILE_SEL_ALPHA)
    d.selBar:Hide()
    d.selMask = card:CreateMaskTexture()
    d.selMask:SetTexture(TILE_HOVER_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.selMask:SetAllPoints(d.selBar)
    d.selBar:AddMaskTexture(d.selMask)

    d.selFill = card:CreateTexture(nil, "ARTWORK", nil, -6)
    d.selFill:SetAllPoints()
    d.selFill:SetColorTexture(1, 1, 1, 0.02)
    d.selFill:SetBlendMode("ADD")
    d.selFill:Hide()

    d.classIcon = card:CreateTexture(nil, "ARTWORK", nil, 2)

    d.name = card:CreateFontString(nil, "OVERLAY")
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.name, true) end
    d.name:SetFont(FontPath(), TILE_NAME_SIZE, "")
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    -- Horizontal inset is re-resolved per paint in PaintCard (it follows the
    -- row height); this is just the initial placement.
    d.name:SetPoint("TOPLEFT", card, "TOPLEFT", TILE_TARGET_H + TILE_TEXT_GAP, 0)

    -- Character name + level, its own line under the Battle.net name.
    d.charLine = card:CreateFontString(nil, "OVERLAY")
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.charLine, true) end
    d.charLine:SetFont(FontPath(), TILE_CHAR_SIZE, "")
    d.charLine:SetJustifyH("LEFT")
    d.charLine:SetWordWrap(false)
    d.charLine:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, TILE_LINE_GAP)

    d.info = card:CreateFontString(nil, "OVERLAY")
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(d.info, true) end
    d.info:SetFont(FontPath(), TILE_INFO_SIZE, "")
    d.info:SetJustifyH("LEFT")
    d.info:SetWordWrap(false)
    -- Anchored per paint: it follows charLine when there is one, otherwise the
    -- name directly, so offline friends do not leave a hole.

    d.orb = card:CreateTexture(nil, "OVERLAY", nil, 3)
    d.orb:SetSize(18, 18)
    if _orbFile then
        d.orb:SetTexture(_orbFile)
        d.orb:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
    else
        d.orb:SetAtlas("lootroll-animreveal-a")
        d.orb:SetTexCoord(0, 1 / 6, 0, 0.5)
    end

    return d
end

-- Blizzard repopulates its card art on every recycle, so this runs per paint.
local function SuppressBlizzardArt(card)
    if card.Background then card.Background:Hide(); card.Background:SetAlpha(0) end
    local hl = card.GetHighlightTexture and card:GetHighlightTexture()
    if hl then hl:SetAlpha(0); hl:SetVertexColor(0, 0, 0, 0) end
    for _, key in ipairs({ "FriendName", "Name", "Level", "Class", "Location" }) do
        local fs = card[key]
        if fs then fs:Hide(); fs:SetAlpha(0) end
    end
    if card.PresenceHolder then card.PresenceHolder:Hide(); card.PresenceHolder:SetAlpha(0) end
    if card.StateDisplay then card.StateDisplay:Hide(); card.StateDisplay:SetAlpha(0) end
    if card.GameIconHolder then card.GameIconHolder:Hide() end
end

-------------------------------------------------------------------------------
--  Per-paint passes
-------------------------------------------------------------------------------
local ClassColorCode = _G._EFR_ClassColorCode

-- Line 1: the Battle.net account name on its own.
local function BuildName(accountInfo)
    if FriendsListUtil and FriendsListUtil.BuildFriendNameDisplayText then
        return FriendsListUtil.BuildFriendNameDisplayText(accountInfo)
    end
    return accountInfo.accountName or ""
end

-- The colour Blizzard uses for the location line, so the level suffix can match
-- it rather than the character name.
local function LocationColor(accountInfo)
    local gi = accountInfo.gameAccountInfo
    local online = gi ~= nil and gi.isOnline
    if online then return FRIENDS_GRAY_COLOR or NORMAL_FONT_COLOR end
    return DARKGRAY_COLOR or GRAY_FONT_COLOR
end

-- Line 2: character name (class-coloured) plus the level, the level tinted to
-- match the location line below it. Empty when the friend is not on a character
-- in this project, which collapses the row to two lines.
local function BuildCharLine(accountInfo)
    local gi = accountInfo.gameAccountInfo
    local charName = gi and gi.characterName
    if not (IsSameProjectOnline(gi) and charName and charName ~= "") then return "" end

    local shown = charName
    local p = FriendsDB()
    if p and p.classColorNames then
        local code = ClassColorCode(GetClassFile(accountInfo) or "")
        if code then shown = code .. charName .. "|r" end
    end

    local lvl = gi.characterLevel
    if lvl then
        local levelText
        if SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT then
            levelText = format(SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT, lvl)
        else
            levelText = EllesmereUI.Lf("(Level %d)", lvl)
        end
        local c = LocationColor(accountInfo)
        if c and c.WrapTextInColorCode then
            levelText = c:WrapTextInColorCode(levelText)
        end
        shown = shown .. " " .. levelText
    end
    return shown
end

local function BuildInfo(accountInfo)
    local text = ""
    if FriendsListUtil and FriendsListUtil.BuildLocationDisplayText then
        text = FriendsListUtil.BuildLocationDisplayText(accountInfo) or ""
    end
    if text == "" then
        local gi = accountInfo.gameAccountInfo
        local cp = gi and gi.clientProgram
        if gi and gi.isOnline and (cp == "App" or cp == "BSAp") then
            local loc = GetLocale()
            text = (loc == "enUS" or loc == "enGB") and "In App" or "Battle.Net"
        end
    end
    local note = StripNoteTag(accountInfo.note)
    if note and note ~= "" then
        if text ~= "" then
            text = text .. "  |cff888888|  " .. note .. "|r"
        else
            text = "|cff888888" .. note .. "|r"
        end
    end
    return text
end

-- The chosen Class Icon Theme's art for one class on `icon`. Shared by the
-- EllesmereUI tile and the stock-style decoration.
local function SetClassIconTex(icon, style, classFile)
    if style == "blizzard" then
        icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then icon:SetTexCoord(unpack(coords)) end
    else
        local coords = CLASS_SPRITE_COORDS[classFile]
        if coords then
            icon:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
    end
end

local function UpdateClassIcon(card, d, accountInfo)
    local p = FriendsDB()
    if not (p and p.showClassIcons ~= false) then d.classIcon:Hide(); return end

    local h = (card:GetHeight() or 0) - 4
    if h <= 0 then d.classIcon:Hide(); return end

    local icon, state = d.classIcon, TileState(accountInfo)
    icon:ClearAllPoints()

    if state == "retail" then
        local inset = math.floor(h * 0.025 + 0.5)
        icon:SetPoint("LEFT", card, "LEFT", 4, 0)
        icon:SetPoint("TOP", card, "TOP", 0, -(2 + inset))
        icon:SetPoint("BOTTOM", card, "BOTTOM", 0, 2 + inset)
        local iconH = h - inset * 2
        if iconH > 0 then icon:SetWidth(iconH) end

        local classFile = GetClassFile(accountInfo)
        if not classFile then icon:Hide(); return end

        SetClassIconTex(icon, p.iconStyle or "modern", classFile)
        icon:SetDesaturated(false)
        icon:SetAlpha(1)
    else
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", card, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        if state == "other_game" then
            local src = card.GameIconHolder and card.GameIconHolder.Icon
            local tex = src and src:GetTexture()
            if tex then icon:SetTexture(tex); icon:SetTexCoord(0, 1, 0, 1) end
            icon:SetAlpha(1)
        else
            icon:SetTexture(OFFLINE_ICON)
            icon:SetTexCoord(0, 1, 0, 1)
            icon:SetAlpha(0.5)
        end
        icon:SetDesaturated(false)
    end
    icon:Show()
end

local function UpdateFaction(card, d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isRetail = IsSameProjectOnline(gi)
    local p = FriendsDB()
    local show = not p or p.factionBanners ~= false

    local path = FACTION_TEX_NEUTRAL
    if show and isRetail and gi.factionName == "Alliance" then
        path = FACTION_TEX_ALLIANCE
    elseif show and isRetail and gi.factionName == "Horde" then
        path = FACTION_TEX_HORDE
    end

    local tex = d.factionBg
    tex:SetTexture(path)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
    tex:SetAlpha(0.2)
    tex:Show()
end

local function UpdateOrb(d, accountInfo)
    local gi = accountInfo.gameAccountInfo
    local isOnline = gi and gi.isOnline

    -- AFK/DND can arrive as secret values; never branch on them directly.
    local _isv = issecretvalue
    local rawAFK, rawDND = accountInfo.isAFK, accountInfo.isDND
    local isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
    local isDND = (not _isv or not _isv(rawDND)) and rawDND or false

    local orb = d.orb
    orb:ClearAllPoints()
    orb:SetPoint("TOPLEFT", d.name, "TOPLEFT", (d.name:GetStringWidth() or 0) - 1, 2)

    if isOnline then
        if isDND then orb:SetVertexColor(1, 0.2, 0.2, 1)
        elseif isAFK then orb:SetVertexColor(1, 0.8, 0, 1)
        else orb:SetVertexColor(0.2, 1, 0.2, 1) end
    else
        orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    end
    orb:Show()
end

-- Stock styles: a plain region mark (no mouse, so the row keeps every click
-- and hover; Blizzard's own tooltip already names a friend's region) in the
-- free corner above the 12.1 card's party button, or in the legacy row's
-- empty left gutter under its status icon (clear of the name, the favourite
-- star, the info line and the logo).
local STOCK_REGION_SIZE = 14
local function UpdateStockRegion(card, d, accountInfo)
    local p = FriendsDB()
    local gi = accountInfo and accountInfo.gameAccountInfo
    -- Same-region friends never carry a mark: skip the realm lookup for them.
    if (p and p.showRegionIcons == false) or not gi or gi.isInCurrentRegion == true then
        if d.regionMark then d.regionMark:Hide() end
        return
    end
    local myFull = EllesmereUI.GetMyFullRegion and EllesmereUI.GetMyFullRegion()
    local mini = EllesmereUI.GetFriendMiniRegion and EllesmereUI.GetFriendMiniRegion(gi)
    local full = mini and EllesmereUI.GetFullRegion and EllesmereUI.GetFullRegion(mini)
    if not (mini and full and full ~= myFull) then
        if d.regionMark then d.regionMark:Hide() end
        return
    end
    local mark = d.regionMark
    if not mark then
        mark = card:CreateTexture(nil, "OVERLAY", nil, 7)
        mark:SetSize(STOCK_REGION_SIZE, STOCK_REGION_SIZE)
        if card.PartyButton then
            mark:SetPoint("BOTTOM", card.PartyButton, "TOP", 0, 1)
        elseif card.status and card.gameIcon then
            mark:SetSize(12, 12)
            mark:SetPoint("TOP", card.status, "BOTTOM", 0, -1)
        else
            mark:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -3)
        end
        d.regionMark = mark
    end
    if d.regionMini ~= mini then
        d.regionMini = mini
        mark:SetTexture(EllesmereUI.GetRegionIcon and EllesmereUI.GetRegionIcon(mini))
        mark:SetTexCoord(0, 1, 0, 1)
    end
    mark:Show()
end

local function UpdateRegion(card, d, accountInfo)
    local p = FriendsDB()
    if p and p.showRegionIcons == false then
        if d.regionBtn then d.regionBtn:Hide() end
        return
    end

    local myFull = EllesmereUI.GetMyFullRegion and EllesmereUI.GetMyFullRegion()
    local mini
    if accountInfo.gameAccountInfo and EllesmereUI.GetFriendMiniRegion then
        mini = EllesmereUI.GetFriendMiniRegion(accountInfo.gameAccountInfo)
    end
    local full = mini and EllesmereUI.GetFullRegion and EllesmereUI.GetFullRegion(mini)
    if not (mini and full and full ~= myFull) then
        if d.regionBtn then d.regionBtn:Hide() end
        return
    end

    if not d.regionBtn then
        local rb = CreateFrame("Button", nil, card)
        rb:SetFrameLevel(card:GetFrameLevel() + 5)
        rb._tex = rb:CreateTexture(nil, "OVERLAY", nil, 7)
        rb._tex:SetAllPoints()
        rb._tex:SetAlpha(0.25)
        rb:SetScript("OnEnter", function(self)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, self._regionLabel or "")
            end
        end)
        rb:SetScript("OnLeave", function()
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        local iconH = math.floor((card:GetHeight() or 40) * 0.8)
        rb:SetSize(iconH, iconH)
        if card.PartyButton then
            rb:SetPoint("RIGHT", card.PartyButton, "LEFT", -2, 0)
        else
            rb:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        end
        d.regionBtn = rb
    end

    local rb = d.regionBtn
    if rb._lastMini ~= mini then
        rb._lastMini = mini
        rb._tex:SetTexture(EllesmereUI.GetRegionIcon and EllesmereUI.GetRegionIcon(mini))
        rb._tex:SetTexCoord(0, 1, 0, 1)
        rb._regionLabel = MINI_DISPLAY[mini] or mini
    end
    rb:Show()
end

-------------------------------------------------------------------------------
--  Paint
-------------------------------------------------------------------------------
local function PaintCard(card)
    if not TILE_PAINT then return end
    if not Enabled() then return end

    local ed = card.elementData
    local accountInfo = ed and ed.accountInfo
    if not accountInfo then return end

    local d = SkinStructure(card)
    SuppressBlizzardArt(card)

    local charText = BuildCharLine(accountInfo)
    local hasChar  = charText ~= ""

    d.name:SetText(BuildName(accountInfo))
    d.charLine:SetText(charText)
    d.charLine:SetShown(hasChar)
    d.info:SetText(BuildInfo(accountInfo))

    -- Every string arrives pre-wrapped in Blizzard colour codes, so the
    -- FontStrings stay white or they would tint the markup.
    d.name:SetTextColor(1, 1, 1, 1)
    d.charLine:SetTextColor(1, 1, 1, 1)
    d.info:SetTextColor(1, 1, 1, 1)

    -- The location follows whichever line is above it, so a friend with no
    -- character does not leave a gap.
    d.info:ClearAllPoints()
    d.info:SetPoint("TOPLEFT", hasChar and d.charLine or d.name, "BOTTOMLEFT", 0, TILE_LINE_GAP)

    -- Centre the block vertically. Its height depends on the line count, so it
    -- is measured rather than assumed -- Blizzard's row is 70 and the block is
    -- far shorter, and a fixed offset would sit wrong on two-line rows.
    local rowH = card:GetHeight()
    if rowH and rowH > 0 then
        local gap   = -TILE_LINE_GAP
        local block = TILE_NAME_SIZE + gap + TILE_INFO_SIZE
        if hasChar then block = block + TILE_CHAR_SIZE + gap end
        d.name:ClearAllPoints()
        d.name:SetPoint("TOPLEFT", card, "TOPLEFT",
                        rowH + TILE_TEXT_GAP, -math.max(0, (rowH - block) / 2))
    end

    UpdateClassIcon(card, d, accountInfo)
    d.onlineBg:SetShown(accountInfo.gameAccountInfo ~= nil
                        and accountInfo.gameAccountInfo.isOnline == true)
    UpdateFaction(card, d, accountInfo)
    UpdateOrb(d, accountInfo)
    UpdateRegion(card, d, accountInfo)

    d.hoverBar:Hide()
    d.hoverFill:Hide()

    -- Blizzard calls SetSelected during its own Initialize, i.e. BEFORE this
    -- paint runs and before the structure above exists. The hook stashes the
    -- state in FFD; this applies it once the textures are there.
    local sel = d.selected == true
    d.selBar:SetShown(sel)
    d.selFill:SetShown(sel)
end

-------------------------------------------------------------------------------
--  Stock styles (Blizzard Style / Classic WoW UI): Blizzard's own card, laid
--  out and drawn by Blizzard, with the EllesmereUI additions in its native
--  slots only. No Blizzard region is moved or re-texted; the same write
--  classes as the tile path (our regions on the card, SetAlpha on Blizzard's
--  regions), so the decoration-only rule above still holds.
--    class icon  -> over Blizzard's 20px game-icon slot (same-project friends)
--    class name  -> our string over Blizzard's character name (Class Color Names)
--    region mark -> the free corner above the party button (Show Region Icons)
-------------------------------------------------------------------------------
local function DecorateStockCard(card)
    if not Enabled() then return end
    local ed = card.elementData
    local accountInfo = ed and ed.accountInfo
    if not accountInfo then return end

    local d = GetFFD(card)
    local p = FriendsDB()
    local gi = accountInfo.gameAccountInfo
    local classFile
    if IsSameProjectOnline(gi) then
        classFile = (gi.classFilename ~= "" and gi.classFilename) or GetClassFile(accountInfo)
    end

    -- Class icon: a region of the holder, so it follows Blizzard's own show and
    -- hide of the slot (hidden for offline friends and while the RAF summon
    -- button takes the slot). Blizzard re-sets its Icon's alpha whenever it
    -- shows the holder, so the logo needs no restore when ours stands down.
    local holder = card.GameIconHolder
    if holder then
        local icon = d.stockClassIcon
        -- Only a class the icon theme has art for takes the slot; any other
        -- token (a special game-mode class) keeps Blizzard's own logo.
        local style = (p and p.iconStyle) or "modern"
        local hasArt = classFile and not (p and p.showClassIcons == false)
            and ((style == "blizzard" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile])
                or (style ~= "blizzard" and CLASS_SPRITE_COORDS[classFile]))
        if hasArt then
            if not icon then
                icon = holder:CreateTexture(nil, "OVERLAY")
                icon:SetAllPoints(holder)
                d.stockClassIcon = icon
            end
            if d.stockIconClass ~= classFile or d.stockIconStyle ~= style then
                d.stockIconClass, d.stockIconStyle = classFile, style
                SetClassIconTex(icon, style, classFile)
            end
            icon:Show()
            if holder.Icon then holder.Icon:SetAlpha(0); d.stockLogoOff = true end
        else
            if icon then icon:Hide() end
            -- A pooled card whose last friend wore our icon gets the logo back
            -- (Blizzard restores it only when it re-shows the holder).
            if d.stockLogoOff and holder.Icon then holder.Icon:SetAlpha(1) end
            d.stockLogoOff = nil
        end
    end

    -- Class-coloured character name: our string over Blizzard's (same font
    -- object and rect, so its truncation still holds). Blizzard never resets
    -- the name's alpha itself, so it is restored here whenever ours stands down.
    local name = card.Name
    if name then
        local ov = d.stockName
        local code = classFile and p and p.classColorNames and name:IsShown() and ClassColorCode(classFile)
        if code then
            if not ov then
                ov = card:CreateFontString(nil, "OVERLAY")
                local fo = name:GetFontObject()
                if fo then ov:SetFontObject(fo) else ov:SetFont(name:GetFont()) end
                ov:SetAllPoints(name)
                ov:SetJustifyH("LEFT")
                ov:SetJustifyV("MIDDLE")
                ov:SetWordWrap(false)
                d.stockName = ov
            end
            local charName = (FriendsListUtil and FriendsListUtil.GetFormattedCharacterName
                and FriendsListUtil.GetFormattedCharacterName(accountInfo)) or gi.characterName or ""
            ov:SetText(code .. charName .. "|r")
            ov:Show()
            name:SetAlpha(0)
            d.stockNameHidden = true
        else
            if ov then ov:Hide() end
            if d.stockNameHidden then
                name:SetAlpha(1)
                d.stockNameHidden = nil
            end
        end
    end

    UpdateStockRegion(card, d, accountInfo)
end

-------------------------------------------------------------------------------
--  Stock styles on the legacy friends window (FriendsFrame, the one Blizzard
--  shows while the Social UI is switched off server-side): the same three
--  additions on Blizzard's own rows, again in native slots, again decoration
--  only (our regions on the row, SetAlpha on Blizzard's).
--    class icon  -> over Blizzard's 24px game logo (same-project friends; an
--                   online character friend's logo slot is empty and takes it)
--    class name  -> our string over Blizzard's name, built from the same
--                   pieces Blizzard uses, the character part class-coloured
--    region mark -> under the status icon (Show Region Icons)
--  Runs from a post-hook on Blizzard's row update, after it has filled the
--  row. A row updated while the list is hidden (or skipped by an options pass
--  while hidden) is marked stale and caught up when the list shows.
-------------------------------------------------------------------------------
-- restore: an options-driven pass, where no Blizzard row update ran first to
-- put its logo alpha back.
local function DecorateStockRow(button, restore)
    local bt = button.buttonType
    local isBNet = bt ~= nil and bt == FRIENDS_BUTTON_TYPE_BNET
    local isWoW  = bt ~= nil and bt == FRIENDS_BUTTON_TYPE_WOW
    if not (isBNet or isWoW) or not button.id then return end
    local d = GetFFD(button)
    d.legacy = true
    if not button:IsVisible() then d.stale = true; return end
    d.stale = nil
    if not Enabled() then return end

    -- Every decoration off: stand down whatever is still painted and read no
    -- friend data at all.
    local p = FriendsDB()
    if p and p.showClassIcons == false and not p.classColorNames and p.showRegionIcons == false then
        if d.stockClassIcon then d.stockClassIcon:Hide() end
        if d.stockLogoOff and restore and button.gameIcon then button.gameIcon:SetAlpha(1) end
        d.stockLogoOff = nil
        if d.stockName then d.stockName:Hide() end
        if d.stockNameHidden and button.name then button.name:SetAlpha(1) end
        d.stockNameHidden = nil
        if d.regionMark then d.regionMark:Hide() end
        return
    end

    local accountInfo, gi, info, classFile
    if isBNet then
        accountInfo = C_BattleNet.GetFriendAccountInfo(button.id)
        gi = accountInfo and accountInfo.gameAccountInfo
        if IsSameProjectOnline(gi) then
            classFile = (gi.classFilename ~= "" and gi.classFilename) or GetClassFile(accountInfo)
        end
    else
        info = C_FriendList.GetFriendInfoByIndex(button.id)
        if info and info.connected and info.className then
            BuildClassNameLookup()
            classFile = classFileByLocalName[info.className]
        end
    end

    -- Class icon over the logo's rect. A Battle.net friend's slot is Blizzard's
    -- to show or hide (offline, or the summon button in it), so ours follows
    -- the logo's shown state; Blizzard re-sets the logo's alpha on every row
    -- update, so only an options pass has to give it back.
    local logo = button.gameIcon
    if logo then
        local icon = d.stockClassIcon
        local style = (p and p.iconStyle) or "modern"
        local hasArt = (isWoW or logo:IsShown()) and classFile
            and not (p and p.showClassIcons == false)
            and ((style == "blizzard" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile])
                or (style ~= "blizzard" and CLASS_SPRITE_COORDS[classFile]))
        if hasArt then
            if not icon then
                icon = button:CreateTexture(nil, "OVERLAY")
                icon:SetAllPoints(logo)
                d.stockClassIcon = icon
            end
            if d.stockIconClass ~= classFile or d.stockIconStyle ~= style then
                d.stockIconClass, d.stockIconStyle = classFile, style
                SetClassIconTex(icon, style, classFile)
            end
            icon:Show()
            if isBNet then logo:SetAlpha(0); d.stockLogoOff = true end
        else
            if icon then icon:Hide() end
            if d.stockLogoOff and restore then logo:SetAlpha(1) end
            d.stockLogoOff = nil
        end
    end

    -- Class-coloured name: our string over Blizzard's (same font object and
    -- rect, Blizzard's own colour as the base), so the favourite star Blizzard
    -- anchors at the end of its name still lines up. Blizzard never resets
    -- the name's alpha itself, so it is restored whenever ours stands down.
    -- A friend Blizzard greys out as unable to group keeps its grey.
    local name = button.name
    if name then
        local code = classFile and p and p.classColorNames and ClassColorCode(classFile)
        if code and isBNet and CanCooperateWithGameAccount
            and not CanCooperateWithGameAccount(accountInfo) then
            code = nil
        end
        local text
        if code and isBNet then
            local acct = FriendsFrame_GetBNetAccountNameAndStatus
                and FriendsFrame_GetBNetAccountNameAndStatus(accountInfo, true)
            local char = gi.characterName
            if char and char ~= "" and FriendsFrame_GetFormattedCharacterName then
                char = FriendsFrame_GetFormattedCharacterName(char, nil, gi.clientProgram, gi.timerunningSeasonID)
            end
            if acct and char and char ~= "" then
                text = acct .. " " .. code .. "(" .. char .. ")|r"
            end
        elseif code and info and info.name and info.level and FRIENDS_LEVEL_TEMPLATE then
            text = code .. info.name .. "|r, " .. format(FRIENDS_LEVEL_TEMPLATE, info.level, info.className)
        end
        local ov = d.stockName
        if text then
            if not ov then
                ov = button:CreateFontString(nil, "OVERLAY")
                local fo = name:GetFontObject()
                if fo then ov:SetFontObject(fo) else ov:SetFont(name:GetFont()) end
                ov:SetAllPoints(name)
                ov:SetJustifyH(name:GetJustifyH())
                ov:SetJustifyV(name:GetJustifyV())
                ov:SetWordWrap(name:CanWordWrap())
                d.stockName = ov
            end
            -- Colour only: a region's alpha and its colour alpha are one
            -- channel on this client, and Blizzard's name sits at our alpha 0
            -- from the last pass (its 3-arg SetTextColor keeps it), so a full
            -- copy would hand ours alpha 0 from the second update on.
            local r, g, b = name:GetTextColor()
            ov:SetTextColor(r, g, b, 1)
            ov:SetText(text)
            ov:Show()
            name:SetAlpha(0)
            d.stockNameHidden = true
        else
            if ov then ov:Hide() end
            if d.stockNameHidden then
                name:SetAlpha(1)
                d.stockNameHidden = nil
            end
        end
    end

    UpdateStockRegion(button, d, accountInfo)
end

-- The list shows: catch up the rows Blizzard updated, or an options pass
-- skipped, while it was hidden (the latter with that pass's logo restore).
local function CatchUpStaleRows()
    for frame, d in pairs(FFD) do
        if d.stale then
            local restore = d.staleRestore
            d.staleRestore = nil
            DecorateStockRow(frame, restore)
        end
    end
end

-------------------------------------------------------------------------------
--  Hook
--
--  Post-hook on the card mixin, installed at PLAYER_LOGIN -- before the friends
--  list is first shown and therefore before any card frame exists, so every
--  pooled card copies the hooked Initialize when Mixin() runs at creation.
--
--  This is the ONLY contact point with Blizzard's list (under the stock
--  styles, plus the same kind of post-hook on the legacy window's row update
--  and that list's OnShow). We do not touch the ScrollBox, the provider, or
--  any element data.
-------------------------------------------------------------------------------
-- Shrink the row. The extent previewer caches per template, so we overwrite the
-- stored calculator and drop the cache; the next Refresh recalculates at our
-- height. Guarded by a file-local flag rather than a marker on Blizzard's
-- table, so we add no key of our own to it.
local heightApplied = false
local function ApplyCompactRowHeight()
    if not TILE_FORCE_HEIGHT or heightApplied then return end
    local view = SocialUIFrame and SocialUIFrame.FriendsList
    local regs = view and view.TemplateRegistrations
    local reg  = regs and regs["FriendsListSocialCardTemplate"]
    if not reg then return end

    heightApplied = true
    -- Plain number ONLY. Deliberately clearing their calculator rather than
    -- replacing it: CalculateTemplateExtent falls back to registrationInfo
    -- .baseHeight when there is no calculator, so nothing of ours executes
    -- inside their layout pass. Blizzard's own code simply reads a number.
    reg.baseHeightCalculator = nil
    reg.baseHeight = TILE_TARGET_H
    if view.ClearTemplateExtentCache then view:ClearTemplateExtentCache() end
end

-- The decorator the Initialize hook runs this session, chosen once from the
-- style latch (pooled cards therefore never mix treatments).
local activeDecorator

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if ns.FR_Style() ~= "eui" then
        -- Stock styles decorate whichever window Blizzard shows (the switch
        -- is server-side and can flip mid-session). Blizzard keeps its own
        -- selection highlight, so the SetSelected hook below is not needed.
        activeDecorator = DecorateStockCard
        if FriendsListSocialCardMixin then
            hooksecurefunc(FriendsListSocialCardMixin, "Initialize", function(card)
                DecorateStockCard(card)
            end)
        end
        if FriendsFrame_UpdateFriendButton then
            hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
                -- Blizzard has just re-set its logo alpha itself.
                local d = FFD[button]
                if d then d.staleRestore = nil end
                DecorateStockRow(button)
            end)
            if FriendsListFrame then
                FriendsListFrame:HookScript("OnShow", CatchUpStaleRows)
            end
        end
        return
    end
    if not FriendsListSocialCardMixin then return end
    activeDecorator = PaintCard
    hooksecurefunc(FriendsListSocialCardMixin, "Initialize", function(card)
        PaintCard(card)
    end)

    -- Selection state comes from Blizzard's own selection behaviour, which
    -- routes through SetSelected on the card. Post-hooking it means we never
    -- read the provider or the selection behaviour ourselves.
    hooksecurefunc(FriendsListSocialCardMixin, "SetSelected", function(card, selected)
        local d = GetFFD(card)
        d.selected = selected and true or false
        if d.selBar then
            d.selBar:SetShown(d.selected)
            d.selFill:SetShown(d.selected)
        end
    end)

    ApplyCompactRowHeight()
end)

-- Options-driven repaint that never goes through Blizzard's view: re-run this
-- session's decorator on every card or legacy row we have decorated that is on
-- screen now, from the data Blizzard already gave it. (view:Refresh
-- regenerates the data provider from our execution -- the whisper-taint class
-- above.)
_G._EFR_RedecorateTiles = function()
    local fn = activeDecorator
    if not fn then return end
    for frame, d in pairs(FFD) do
        if d.legacy then
            -- A row kept shown under a hidden list (another Friends sub-tab)
            -- is caught up when the list shows; a released row is
            -- re-initialised by Blizzard when the pool reuses it.
            if frame:IsVisible() then
                DecorateStockRow(frame, true)
            elseif frame:IsShown() then
                d.stale, d.staleRestore = true, true
            end
        elseif frame.IsVisible and frame:IsVisible() and frame.elementData then
            fn(frame)
        end
    end
end

_G._EFR_RepaintTiles = function()
    -- Options-driven refresh: ask Blizzard to redraw, which re-runs Initialize
    -- on every visible card and therefore our paint with it.
    local view = SocialUIFrame and SocialUIFrame.FriendsList
    if view and view.Refresh and view:IsShown() then
        view:Refresh(ScrollBoxConstants.RetainScrollPosition)
    end
end
