if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_StyleCards.lua
--
--  The three look cards (EllesmereUI Style, Blizzard Style, Classic WoW UI),
--  each with a miniature of what the look means, shared by the first-install
--  style picker (EllesmereUI_StyleChoicePopup.lua) and the header of Global
--  Settings > Style (EUI_Style_Options.lua). The WoW Forever client adds a
--  fourth pick card, WoW Forever. Builds frames only when called.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.80, 0.18
local BRONZE_R, BRONZE_G, BRONZE_B = 0.86, 0.65, 0.42
local FOREVER_R, FOREVER_G, FOREVER_B = 0.47, 0.75, 0.95
-- The EllesmereUI card and its mock keep the stock #0CD29D teal (the
-- EllesmereUI theme preset) on every client, whatever accent colour the user
-- has picked.
local EUI_TEAL = EllesmereUI.THEME_PRESETS["EllesmereUI"]
local IS_FOREVER = EllesmereUI.IS_FOREVER == true
-- The vanilla frame sheet: the player frame samples it flipped (portrait on
-- the left); 193x77 of visible art at 1x.
local CLASSIC_FRAME = "Interface\\TargetingFrame\\UI-TargetingFrame"
local CLASSIC_EMPTY = "Interface\\Buttons\\UI-Quickslot"
local CLASSIC_FILL  = "Interface\\TargetingFrame\\UI-StatusBar"
local CLASSIC_CAP   = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf"

local CARD_W, CARD_H, CARD_GAP = 212, 296, 16
-- Display cards (announcements) have no button: the caption is the last row.
local DISPLAY_CARD_H = 248
local MOCK_W, MOCK_H = 186, 118
EllesmereUI.STYLE_CARD_H = CARD_H
EllesmereUI.STYLE_CARD_DISPLAY_H = DISPLAY_CARD_H
-- The row of pick cards (four on the WoW Forever client), for callers that
-- size a host round it; display cards stay three.
local PICK_CARDS = IS_FOREVER and 4 or 3
EllesmereUI.STYLE_CARDS_W = PICK_CARDS * CARD_W + (PICK_CARDS - 1) * CARD_GAP

local function AtlasOK(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false
end

-------------------------------------------------------------------------------
--  EllesmereUI mock: a flat unit frame (teal health, blue power, a name
--  line) over a row of square icons -- the look in miniature.
-------------------------------------------------------------------------------
local function DrawEUIMock(stage, PP, MakeBorder, teal)
    local frame = CreateFrame("Frame", nil, stage)
    frame:SetFrameLevel(stage:GetFrameLevel() + 1)
    PP.Size(frame, 150, 40)
    PP.Point(frame, "TOP", stage, "TOP", 0, -14)
    local fbg = frame:CreateTexture(nil, "BACKGROUND")
    fbg:SetAllPoints()
    fbg:SetColorTexture(0.103, 0.095, 0.088, 1)
    MakeBorder(frame, 0, 0, 0, 1, PP)
    local health = frame:CreateTexture(nil, "ARTWORK")
    health:SetColorTexture(teal.r, teal.g, teal.b, 0.9)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 1, -1)
    PP.Size(health, 130, 27)
    local hrest = frame:CreateTexture(nil, "ARTWORK")
    hrest:SetColorTexture(teal.r, teal.g, teal.b, 0.2)
    PP.Point(hrest, "TOPLEFT", health, "TOPRIGHT", 0, 0)
    PP.Point(hrest, "BOTTOMRIGHT", frame, "TOPRIGHT", -1, -28)
    local power = frame:CreateTexture(nil, "ARTWORK")
    power:SetColorTexture(0.25, 0.5, 0.9, 0.9)
    PP.Point(power, "TOPLEFT", frame, "TOPLEFT", 1, -29)
    PP.Size(power, 104, 10)
    local prest = frame:CreateTexture(nil, "ARTWORK")
    prest:SetColorTexture(0.25, 0.5, 0.9, 0.2)
    PP.Point(prest, "TOPLEFT", power, "TOPRIGHT", 0, 0)
    PP.Point(prest, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    local nameLine = frame:CreateTexture(nil, "OVERLAY")
    nameLine:SetColorTexture(1, 1, 1, 0.85)
    PP.Size(nameLine, 50, 5)
    PP.Point(nameLine, "TOPLEFT", frame, "TOPLEFT", 8, -11)
    local hpLine = frame:CreateTexture(nil, "OVERLAY")
    hpLine:SetColorTexture(1, 1, 1, 0.85)
    PP.Size(hpLine, 24, 5)
    PP.Point(hpLine, "TOPRIGHT", frame, "TOPRIGHT", -8, -11)

    local ICON, GAP, N = 24, 4, 5
    local rowW = N * ICON + (N - 1) * GAP
    for i = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        PP.Size(ic, ICON, ICON)
        PP.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (i - 1) * (ICON + GAP), -70)
        local ibg = ic:CreateTexture(nil, "BACKGROUND")
        ibg:SetAllPoints()
        ibg:SetColorTexture(0.16 + i * 0.03, 0.18, 0.2 + i * 0.02, 1)
        MakeBorder(ic, 0, 0, 0, 1, PP)
        if i == 2 then
            local keyLine = ic:CreateTexture(nil, "OVERLAY")
            keyLine:SetColorTexture(teal.r, teal.g, teal.b, 0.9)
            PP.Size(keyLine, ICON - 2, 2)
            PP.Point(keyLine, "BOTTOMLEFT", ic, "BOTTOMLEFT", 1, 1)
        end
    end
end

-------------------------------------------------------------------------------
--  Blizzard mock: the stock player frame art with its health and mana
--  fills, over four rounded stock button slots flanked by retail's gryphon
--  end caps. Every atlas is validated; a missing one falls back to a plain
--  gold-framed box (or leaves its cap out) so the card never shows a blank
--  stage. forever: the WoW Forever card's base (its own art, its caps drawn
--  by DrawForeverMock). Returns the unit frame.
-------------------------------------------------------------------------------
local function DrawBlizzMock(stage, PP, MakeBorder, _eg, _font, forever)
    local ART = "UI-HUD-UnitFrame-Player-PortraitOn"
    local HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
    local MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana"
    local SLOT = "UI-HUD-ActionBar-IconFrame-Slot"
    local frame = CreateFrame("Frame", nil, stage)
    frame:SetFrameLevel(stage:GetFrameLevel() + 1)
    if AtlasOK(ART) then
        -- The 198x71 art at 0.78, its bars placed from the stock geometry
        -- (the bars sit at 85/40 and 85/61 in the 232x100 box whose art
        -- is centred with 17 and 14.5 of transparent margin).
        local s = 0.78
        PP.Size(frame, 198 * s, 71 * s)
        PP.Point(frame, "TOP", stage, "TOP", 0, -8)
        local art = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        art:SetAllPoints()
        -- Plain Blizzard Style draws the retail art on WoW Forever too, as
        -- live (EllesmereUI.StockAtlas); the WoW Forever card keeps its own.
        if forever then art:SetAtlas(ART, false) else EllesmereUI.StockAtlas(art, ART, false) end
        if AtlasOK(HEALTH) then
            local h = frame:CreateTexture(nil, "ARTWORK", nil, 1)
            h:SetAtlas(HEALTH, false)
            PP.Size(h, 124 * s * 0.82, 20 * s)
            PP.Point(h, "TOPLEFT", frame, "TOPLEFT", (85 - 17) * s, -(40 - 14.5) * s)
        end
        if AtlasOK(MANA) then
            local m = frame:CreateTexture(nil, "ARTWORK", nil, 1)
            m:SetAtlas(MANA, false)
            PP.Size(m, 124 * s * 0.6, 10 * s)
            PP.Point(m, "TOPLEFT", frame, "TOPLEFT", (85 - 17) * s, -(61 - 14.5) * s)
        end
    else
        PP.Size(frame, 150, 40)
        PP.Point(frame, "TOP", stage, "TOP", 0, -14)
        local fbg = frame:CreateTexture(nil, "BACKGROUND")
        fbg:SetAllPoints()
        fbg:SetColorTexture(0.12, 0.10, 0.06, 1)
        MakeBorder(frame, GOLD_R, GOLD_G, GOLD_B, 0.8, PP)
        local health = frame:CreateTexture(nil, "ARTWORK")
        health:SetColorTexture(0.1, 0.75, 0.1, 0.9)
        PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 3, -3)
        PP.Size(health, 122, 20)
        local power = frame:CreateTexture(nil, "ARTWORK")
        power:SetColorTexture(0.1, 0.35, 0.9, 0.9)
        PP.Point(power, "TOPLEFT", frame, "TOPLEFT", 3, -25)
        PP.Size(power, 96, 12)
    end

    local ICON, GAP, N = 24, 4, 4
    local rowW = N * ICON + (N - 1) * GAP
    local slotOK = AtlasOK(SLOT)
    for i = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        PP.Size(ic, ICON, ICON)
        PP.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (i - 1) * (ICON + GAP), -76)
        local t = ic:CreateTexture(nil, "ARTWORK")
        if slotOK then
            if forever then t:SetAtlas(SLOT, false) else EllesmereUI.StockAtlas(t, SLOT, false) end
            PP.Point(t, "TOPLEFT", ic, "TOPLEFT", -3, 3)
            PP.Point(t, "BOTTOMRIGHT", ic, "BOTTOMRIGHT", 3, -3)
        else
            t:SetAllPoints()
            t:SetColorTexture(0.2, 0.17, 0.1, 1)
            MakeBorder(ic, GOLD_R, GOLD_G, GOLD_B, 0.6, PP)
        end
    end
    -- Blizzard Style: retail's gryphon end caps (retail art on every client,
    -- at the live caps' 104.5x98), bottoms a little below the slots.
    if not forever then
        local CAP_H, OVERLAP = 28, 3
        for side = 1, 2 do
            local name = (side == 1) and "ui-hud-actionbar-gryphon-left" or "ui-hud-actionbar-gryphon-right"
            if AtlasOK(name) then
                local cap = CreateFrame("Frame", nil, stage)
                cap:SetFrameLevel(stage:GetFrameLevel() + 2)
                PP.Size(cap, CAP_H * 104.5 / 98, CAP_H)
                if side == 1 then
                    PP.Point(cap, "BOTTOMRIGHT", stage, "TOP", -rowW / 2 + OVERLAP, -104)
                else
                    PP.Point(cap, "BOTTOMLEFT", stage, "TOP", rowW / 2 - OVERLAP, -104)
                end
                local t = cap:CreateTexture(nil, "ARTWORK")
                t:SetAllPoints()
                EllesmereUI.StockAtlas(t, name, false)
            end
        end
    end
    return frame, rowW
end

-------------------------------------------------------------------------------
--  WoW Forever mock (that client only, where every stock atlas already draws
--  its Forever art): the Blizzard mock with the round level badge on the
--  player frame and the gryphon end caps flanking a four-slot bar. A missing
--  atlas just leaves its piece out.
-------------------------------------------------------------------------------
local function DrawForeverMock(stage, PP, MakeBorder, EG, font)
    local frame, rowW = DrawBlizzMock(stage, PP, MakeBorder, EG, font, true)
    -- Level badge: Blizzard's Forever spot is BOTTOMLEFT 13,7 of the 232x100
    -- box, i.e. -4,-7.5 off the centred art, at the mock's 0.78.
    local BADGE = "UI-HUD-UnitFrame-SmallCircle"
    if AtlasOK(BADGE) then
        local bf = CreateFrame("Frame", nil, stage)
        bf:SetFrameLevel(stage:GetFrameLevel() + 2)
        PP.Size(bf, 24, 24)
        PP.Point(bf, "BOTTOMLEFT", frame, "BOTTOMLEFT", -3, -6)
        local disc = bf:CreateTexture(nil, "ARTWORK")
        disc:SetAllPoints()
        disc:SetAtlas(BADGE, false)
        local lvl = bf:CreateFontString(nil, "OVERLAY")
        lvl:SetFont(font, 10, "")
        lvl:SetTextColor(1, 1, 1, 1)
        PP.Point(lvl, "CENTER", bf, "CENTER", 0, 0)
        lvl:SetText("60")
    end
    -- Gryphon end caps at their own aspect, bottoms level with the slots,
    -- each overlapping the bar's end by a few pixels.
    local CAP_H, OVERLAP = 26, 8
    for side = 1, 2 do
        local name = (side == 1) and "ui-hud-actionbar-gryphon-left" or "ui-hud-actionbar-gryphon-right"
        local info = C_Texture.GetAtlasInfo(name)
        if info and info.width and info.height and info.height > 0 then
            local cap = CreateFrame("Frame", nil, stage)
            cap:SetFrameLevel(stage:GetFrameLevel() + 2)
            PP.Size(cap, CAP_H * info.width / info.height, CAP_H)
            if side == 1 then
                PP.Point(cap, "BOTTOMRIGHT", stage, "TOP", -rowW / 2 + OVERLAP, -102)
            else
                PP.Point(cap, "BOTTOMLEFT", stage, "TOP", rowW / 2 - OVERLAP, -102)
            end
            local t = cap:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetAtlas(name, false)
        end
    end
end

-------------------------------------------------------------------------------
--  Classic mock: the vanilla player frame sheet (193x77 of art, sampled
--  flipped so the portrait sits on the left) with its health and mana
--  bars at the vanilla spots and the level in its ring, over four vanilla
--  empty slots flanked by the vanilla gryphon end caps. Plain files, so
--  nothing needs validating.
-------------------------------------------------------------------------------
local function DrawClassicMock(stage, PP, _mb, _eg, font)
    local s = 0.78
    local frame = CreateFrame("Frame", nil, stage)
    frame:SetFrameLevel(stage:GetFrameLevel() + 1)
    PP.Size(frame, 193 * s, 77 * s)
    PP.Point(frame, "TOP", stage, "TOP", 0, -6)
    -- Bars under the art: the art's tracks are transparent windows. Box
    -- coordinates (232x100) minus the art's centring offset (19.5, 11.5).
    local health = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    health:SetTexture(CLASSIC_FILL)
    health:SetVertexColor(0.0, 0.8, 0.0)
    PP.Size(health, 119 * s * 0.82, 12 * s)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", (90 - 19.5) * s, -(45 - 11.5) * s)
    local hrest = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    hrest:SetColorTexture(0, 0, 0, 0.5)
    PP.Point(hrest, "TOPLEFT", health, "TOPRIGHT", 0, 0)
    PP.Size(hrest, 119 * s * 0.18, 12 * s)
    local mana = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    mana:SetTexture(CLASSIC_FILL)
    mana:SetVertexColor(0.0, 0.0, 1.0)
    PP.Size(mana, 119 * s * 0.6, 12 * s)
    PP.Point(mana, "TOPLEFT", frame, "TOPLEFT", (90 - 19.5) * s, -(56 - 11.5) * s)
    local mrest = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    mrest:SetColorTexture(0, 0, 0, 0.5)
    PP.Point(mrest, "TOPLEFT", mana, "TOPRIGHT", 0, 0)
    PP.Size(mrest, 119 * s * 0.4, 12 * s)
    local art = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    art:SetTexture(CLASSIC_FRAME)
    art:SetTexCoord(0.85546875, 0.1015625, 0.0625, 0.6640625)
    art:SetAllPoints(frame)
    -- Level in the ring by the portrait: vanilla's PlayerLevelText sits CENTER
    -- at BOTTOMLEFT 35.25,30 of the 232x100 box.
    local lvl = frame:CreateFontString(nil, "OVERLAY")
    lvl:SetFont(font, 9, "")
    lvl:SetTextColor(1, 0.82, 0, 1)
    PP.Point(lvl, "CENTER", frame, "TOPLEFT", (35.25 - 19.5) * s, -(70 - 11.5) * s)
    lvl:SetText("60")

    local ICON, GAP, N = 24, 4, 4
    local rowW = N * ICON + (N - 1) * GAP
    for i = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        PP.Size(ic, ICON, ICON)
        PP.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (i - 1) * (ICON + GAP), -76)
        -- The vanilla empty slot: 66/36 of the button, a pixel low.
        local slot = ic:CreateTexture(nil, "ARTWORK")
        slot:SetTexture(CLASSIC_EMPTY)
        PP.Size(slot, ICON * 66 / 36, ICON * 66 / 36)
        PP.Point(slot, "CENTER", ic, "CENTER", 0, -ICON / 36)
    end
    -- Vanilla's gryphon end caps (one file, the right one mirrored), bottoms a
    -- little below the slots, each overlapping the bar's end.
    local CAP, OVERLAP = 36, 8
    for side = 1, 2 do
        local cap = CreateFrame("Frame", nil, stage)
        cap:SetFrameLevel(stage:GetFrameLevel() + 2)
        PP.Size(cap, CAP, CAP)
        if side == 1 then
            PP.Point(cap, "BOTTOMRIGHT", stage, "TOP", -rowW / 2 + OVERLAP, -102)
        else
            PP.Point(cap, "BOTTOMLEFT", stage, "TOP", rowW / 2 - OVERLAP, -102)
        end
        local t = cap:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(CLASSIC_CAP)
        if side == 2 then t:SetTexCoord(1, 0, 0, 1) end
    end
end

-------------------------------------------------------------------------------
--  EllesmereUI.BuildStyleCards(parent, topY, opts) -> handles
--
--  Three cards in a row (four pick cards on the WoW Forever client,
--  EllesmereUI.STYLE_CARDS_W wide), centred on parent's centre line, their
--  tops topY below parent's TOP. Each card is one click target: the whole
--  card and its button pick that style, and hover lights the card in its own
--  colour. opts:
--    onPick(styleKey)  called on a pick ("eui" | "blizzard" | "classic",
--                      or "forever" on the WoW Forever client)
--    buttonText        a string for every card, or a table keyed by style
--    display           true: announcement cards -- no button, no click or
--                      hover, DISPLAY_CARD_H tall (onPick/buttonText unused)
--    defaultKey        the pick card tagged DEFAULT (nil or "eui" = the
--                      EllesmereUI card); the order stays, EllesmereUI first
--    inUseAlpha        the card's opacity while it is IN USE (1); its
--                      badge stays whole
--    badgeSize         the IN USE badge's font size (11)
--  Returns a table keyed by style; handle:SetState(inUse, pickable, label)
--  keeps a card lit with an IN USE badge, and dims its button (picks then do
--  nothing) with an optional label while it has nothing to apply.
-------------------------------------------------------------------------------
function EllesmereUI.BuildStyleCards(parent, topY, opts)
    local PP = EllesmereUI.PanelPP
    local MakeBorder = EllesmereUI.MakeBorder
    if not (PP and MakeBorder) then return nil end
    local L = EllesmereUI.L or function(s) return s end
    -- The options font once it has loaded, else the locale-aware core font
    -- (the picker runs before the options addon loads).
    local FONT = EllesmereUI._font or EllesmereUI.EXPRESSWAY
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    opts = opts or {}

    local DEFS = {
        { key = "eui", r = EUI_TEAL.r, g = EUI_TEAL.g, b = EUI_TEAL.b, title = "EllesmereUI Style", tag = "DEFAULT",
          caption = "Flat, clean and modern. The look EllesmereUI was designed around.",
          draw = DrawEUIMock },
        { key = "blizzard", r = GOLD_R, g = GOLD_G, b = GOLD_B, title = "Blizzard Style", tag = "BLIZZARD ART",
          caption = "Blizzard's own frame and button art, with EllesmereUI's features.",
          draw = DrawBlizzMock },
        { key = "classic", r = BRONZE_R, g = BRONZE_G, b = BRONZE_B, title = "Classic WoW UI", tag = "VANILLA ART",
          caption = "The original frames, rings and slots where the game has them, with EllesmereUI's features.",
          draw = DrawClassicMock },
    }

    local display = opts.display == true
    local inUseAlpha = opts.inUseAlpha or 1
    -- WoW Forever: its own pick card on that client, second in the row (the
    -- announcement cards never show there).
    if IS_FOREVER and not display then
        table.insert(DEFS, 2, { key = "forever", r = FOREVER_R, g = FOREVER_G, b = FOREVER_B,
          title = "WoW Forever", tag = "FOREVER ART",
          caption = "Forever's bronze frames, gryphons and round badges, with EllesmereUI's features.",
          draw = DrawForeverMock })
    end
    -- Another default look: its card takes the DEFAULT tag where it stands,
    -- so the EllesmereUI card still leads the row.
    local dk = opts.defaultKey
    if dk and dk ~= "eui" and not display then
        for i = 2, #DEFS do
            if DEFS[i].key == dk then
                DEFS[1].tag = "FLAT & MODERN"
                DEFS[i].tag = "DEFAULT"
                break
            end
        end
    end
    local mid = (#DEFS + 1) / 2
    local handles = {}
    for index, def in ipairs(DEFS) do
        local accentR, accentG, accentB = def.r, def.g, def.b
        local card = CreateFrame(display and "Frame" or "Button", nil, parent)
        card:SetFrameLevel(parent:GetFrameLevel() + 1)
        PP.Size(card, CARD_W, display and DISPLAY_CARD_H or CARD_H)
        PP.Point(card, "TOP", parent, "TOP", (index - mid) * (CARD_W + CARD_GAP), topY)
        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.103, 0.095, 0.088, 1)
        local brd = MakeBorder(card, 1, 1, 1, 0.14, PP)

        -- Accent band along the top edge: the colour is the first indicator.
        local band = card:CreateTexture(nil, "ARTWORK")
        band:SetColorTexture(accentR, accentG, accentB, 0.9)
        band:SetHeight(3)
        PP.Point(band, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(band, "TOPRIGHT", card, "TOPRIGHT", -1, -1)

        local ct = card:CreateFontString(nil, "OVERLAY")
        ct:SetFont(FONT, 17, "")
        ct:SetTextColor(accentR, accentG, accentB, 1)
        PP.Point(ct, "TOP", card, "TOP", 0, -16)
        ct:SetText(L(def.title))

        -- Small tag under the title (DEFAULT / BLIZZARD ART).
        local tagFS = card:CreateFontString(nil, "OVERLAY")
        tagFS:SetFont(FONT, 11, "")
        tagFS:SetTextColor(accentR, accentG, accentB, 0.7)
        PP.Point(tagFS, "TOP", ct, "BOTTOM", 0, -3)
        tagFS:SetText(L(def.tag))

        -- IN USE badge just above the card (clear of the centred title),
        -- shown by SetState. Drawn on the parent, so the card's IN USE
        -- alpha leaves it whole.
        local badge = parent:CreateFontString(nil, "OVERLAY")
        badge:SetFont(FONT, opts.badgeSize or 11, "")
        badge:SetTextColor(accentR, accentG, accentB, 1)
        PP.Point(badge, "BOTTOM", card, "TOP", 0, 6)
        badge:SetText(L("IN USE"))
        badge:Hide()

        -- Mock area: a dark stage the style mock is drawn on.
        local stage = CreateFrame("Frame", nil, card)
        stage:SetFrameLevel(card:GetFrameLevel() + 1)
        PP.Size(stage, MOCK_W, MOCK_H)
        PP.Point(stage, "TOP", tagFS, "BOTTOM", 0, -12)
        local sbg = stage:CreateTexture(nil, "BACKGROUND")
        sbg:SetAllPoints()
        sbg:SetColorTexture(0.051, 0.040, 0.030, 1)
        MakeBorder(stage, 1, 1, 1, 0.08, PP)
        def.draw(stage, PP, MakeBorder, EUI_TEAL, FONT)

        local cap = card:CreateFontString(nil, "OVERLAY")
        cap:SetFont(FONT, 12, "")
        cap:SetTextColor(1, 1, 1, 0.7)
        cap:SetWidth(CARD_W - 28)
        cap:SetJustifyH("CENTER")
        cap:SetWordWrap(true)
        -- Three lines fit between the stage and the button; a longer wrap
        -- (wider fallback font) is cut rather than run into the button.
        if cap.SetMaxLines then cap:SetMaxLines(3) end
        PP.Point(cap, "TOP", stage, "BOTTOM", 0, -10)
        cap:SetText(L(def.caption))

        if display then
            -- Announcement card: nothing to press, only an IN USE state.
            handles[def.key] = {
                card = card,
                SetState = function(_, isInUse)
                    local on = isInUse and true or false
                    badge:SetShown(on)
                    card:SetAlpha(on and inUseAlpha or 1)
                    if on then
                        brd:SetColor(accentR, accentG, accentB, 0.9)
                    else
                        brd:SetColor(1, 1, 1, 0.14)
                    end
                end,
            }
        else
            local btn = CreateFrame("Button", nil, card)
            btn:SetFrameLevel(card:GetFrameLevel() + 2)
            PP.Size(btn, CARD_W - 32, 34)
            PP.Point(btn, "BOTTOM", card, "BOTTOM", 0, 14)
            local bbg = btn:CreateTexture(nil, "BACKGROUND")
            bbg:SetAllPoints()
            local bbrd = MakeBorder(btn, accentR, accentG, accentB, 0.8, PP)
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT, 14, "")
            PP.Point(lbl, "CENTER", btn, "CENTER", 0, 0)
            local bt = opts.buttonText
            local btnText = (type(bt) == "table" and bt[def.key]) or (type(bt) == "string" and bt) or ""
            lbl:SetText(L(btnText))

            local inUse, pickable, hovered = false, true, false
            local function Paint()
                local lit = inUse or (hovered and pickable)
                if lit then
                    brd:SetColor(accentR, accentG, accentB, 0.9)
                else
                    brd:SetColor(1, 1, 1, 0.14)
                end
                if not pickable then
                    bbg:SetColorTexture(accentR, accentG, accentB, 0.06)
                    bbrd:SetColor(accentR, accentG, accentB, 0.35)
                    lbl:SetTextColor(1, 1, 1, 0.45)
                elseif hovered then
                    bbg:SetColorTexture(accentR, accentG, accentB, 0.28)
                    bbrd:SetColor(accentR, accentG, accentB, 1)
                    lbl:SetTextColor(1, 1, 1, 0.95)
                else
                    bbg:SetColorTexture(accentR, accentG, accentB, 0.12)
                    bbrd:SetColor(accentR, accentG, accentB, 0.8)
                    lbl:SetTextColor(1, 1, 1, 0.95)
                end
            end
            local function Enter() hovered = true; Paint() end
            local function Leave() hovered = false; Paint() end
            local function Pick()
                if pickable and opts.onPick then opts.onPick(def.key) end
            end
            card:SetScript("OnEnter", Enter)
            card:SetScript("OnLeave", Leave)
            card:SetScript("OnClick", Pick)
            btn:SetScript("OnEnter", Enter)
            btn:SetScript("OnLeave", Leave)
            btn:SetScript("OnClick", Pick)
            Paint()

            handles[def.key] = {
                card = card,
                SetState = function(_, isInUse, canPick, label)
                    inUse, pickable = isInUse and true or false, canPick ~= false
                    badge:SetShown(inUse)
                    card:SetAlpha(inUse and inUseAlpha or 1)
                    lbl:SetText(L(label or btnText))
                    Paint()
                end,
            }
        end
    end
    return handles
end
