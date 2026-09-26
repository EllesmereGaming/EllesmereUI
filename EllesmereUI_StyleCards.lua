if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_StyleCards.lua
--
--  The three look cards (EllesmereUI Style, Blizzard Style, Classic WoW UI),
--  each with a miniature of what the look means, shared by the first-install
--  style picker (EllesmereUI_StyleChoicePopup.lua) and the header of Global
--  Settings > Style (EUI_Style_Options.lua). Builds frames only when called.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.80, 0.18
local BRONZE_R, BRONZE_G, BRONZE_B = 0.86, 0.65, 0.42
-- The vanilla frame sheet: the player frame samples it flipped (portrait on
-- the left); 193x77 of visible art at 1x.
local CLASSIC_FRAME = "Interface\\TargetingFrame\\UI-TargetingFrame"
local CLASSIC_SLOT  = "Interface\\Buttons\\UI-Quickslot2"
local CLASSIC_FILL  = "Interface\\TargetingFrame\\UI-StatusBar"
local CLASSIC_DISC  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga"

local CARD_W, CARD_H, CARD_GAP = 212, 296, 16
-- Display cards (announcements) have no button: the caption is the last row.
local DISPLAY_CARD_H = 248
local MOCK_W, MOCK_H = 186, 118
EllesmereUI.STYLE_CARD_H = CARD_H
EllesmereUI.STYLE_CARD_DISPLAY_H = DISPLAY_CARD_H

local function AtlasOK(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false
end

-------------------------------------------------------------------------------
--  EllesmereUI mock: a flat unit frame (teal health, blue power, a name
--  line) over a row of square icons -- the look in miniature.
-------------------------------------------------------------------------------
local function DrawEUIMock(stage, PP, MakeBorder, EG)
    local frame = CreateFrame("Frame", nil, stage)
    frame:SetFrameLevel(stage:GetFrameLevel() + 1)
    PP.Size(frame, 150, 40)
    PP.Point(frame, "TOP", stage, "TOP", 0, -14)
    local fbg = frame:CreateTexture(nil, "BACKGROUND")
    fbg:SetAllPoints()
    fbg:SetColorTexture(0.075, 0.113, 0.141, 1)
    MakeBorder(frame, 0, 0, 0, 1, PP)
    local health = frame:CreateTexture(nil, "ARTWORK")
    health:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 1, -1)
    PP.Size(health, 130, 27)
    local hrest = frame:CreateTexture(nil, "ARTWORK")
    hrest:SetColorTexture(EG.r, EG.g, EG.b, 0.2)
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
            keyLine:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
            PP.Size(keyLine, ICON - 2, 2)
            PP.Point(keyLine, "BOTTOMLEFT", ic, "BOTTOMLEFT", 1, 1)
        end
    end
end

-------------------------------------------------------------------------------
--  Blizzard mock: the stock player frame art with its health and mana
--  fills, over a row of the rounded stock button slots. Every atlas is
--  validated; a missing one falls back to a plain gold-framed box so the
--  card never shows a blank stage.
-------------------------------------------------------------------------------
local function DrawBlizzMock(stage, PP, MakeBorder)
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
        art:SetAtlas(ART, false)
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

    local ICON, GAP, N = 24, 4, 5
    local rowW = N * ICON + (N - 1) * GAP
    local slotOK = AtlasOK(SLOT)
    for i = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        PP.Size(ic, ICON, ICON)
        PP.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (i - 1) * (ICON + GAP), -76)
        local t = ic:CreateTexture(nil, "ARTWORK")
        if slotOK then
            t:SetAtlas(SLOT, false)
            PP.Point(t, "TOPLEFT", ic, "TOPLEFT", -3, 3)
            PP.Point(t, "BOTTOMRIGHT", ic, "BOTTOMRIGHT", 3, -3)
        else
            t:SetAllPoints()
            t:SetColorTexture(0.2, 0.17, 0.1, 1)
            MakeBorder(ic, GOLD_R, GOLD_G, GOLD_B, 0.6, PP)
        end
    end
end

-------------------------------------------------------------------------------
--  Classic mock: the vanilla player frame sheet (193x77 of art, sampled
--  flipped so the portrait sits on the left) with its health and mana
--  bars at the vanilla spots, over a row of the vanilla square slots with
--  their gold ring. Plain files, so nothing needs validating.
-------------------------------------------------------------------------------
local function DrawClassicMock(stage, PP)
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
    -- Portrait disc where the ring opens (64x64 at 24,-16 in the box).
    local disc = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    disc:SetColorTexture(0.18, 0.16, 0.13, 1)
    PP.Size(disc, 58 * s, 58 * s)
    PP.Point(disc, "TOPLEFT", frame, "TOPLEFT", (27 - 19.5) * s, -(19 - 11.5) * s)
    local discMask = frame:CreateMaskTexture()
    discMask:SetTexture(CLASSIC_DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    discMask:SetAllPoints(disc)
    disc:AddMaskTexture(discMask)
    local art = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    art:SetTexture(CLASSIC_FRAME)
    art:SetTexCoord(0.85546875, 0.1015625, 0.0625, 0.6640625)
    art:SetAllPoints(frame)
    local nameLine = frame:CreateTexture(nil, "OVERLAY")
    nameLine:SetColorTexture(1, 0.82, 0, 0.9)
    PP.Size(nameLine, 44 * s, 4)
    PP.Point(nameLine, "TOPLEFT", frame, "TOPLEFT", (92 - 19.5) * s, -(31 - 11.5) * s)

    local ICON, GAP, N = 24, 4, 5
    local rowW = N * ICON + (N - 1) * GAP
    for i = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        PP.Size(ic, ICON, ICON)
        PP.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (i - 1) * (ICON + GAP), -76)
        local ibg = ic:CreateTexture(nil, "BACKGROUND")
        ibg:SetAllPoints()
        ibg:SetColorTexture(0.16 + i * 0.03, 0.14, 0.1 + i * 0.02, 1)
        -- The vanilla slot ring: 66/36 of the button, a pixel low.
        local ring = ic:CreateTexture(nil, "ARTWORK")
        ring:SetTexture(CLASSIC_SLOT)
        PP.Size(ring, ICON * 66 / 36, ICON * 66 / 36)
        PP.Point(ring, "CENTER", ic, "CENTER", 0, -ICON / 36)
    end
end

-------------------------------------------------------------------------------
--  EllesmereUI.BuildStyleCards(parent, topY, opts) -> handles
--
--  Three cards in a row, the middle one on parent's centre line, their tops
--  topY below parent's TOP. Each card is one click target: the whole card
--  and its button pick that style, and hover lights the card in its own
--  colour. opts:
--    onPick(styleKey)  called on a pick ("eui" | "blizzard" | "classic")
--    buttonText        a string for every card, or a table keyed by style
--    display           true: announcement cards -- no button, no click or
--                      hover, DISPLAY_CARD_H tall (onPick/buttonText unused)
--  Returns a table keyed by style; handle:SetState(inUse, pickable, label)
--  keeps a card lit with an IN USE badge, and dims its button (picks then do
--  nothing) with an optional label while it has nothing to apply.
-------------------------------------------------------------------------------
function EllesmereUI.BuildStyleCards(parent, topY, opts)
    local PP = EllesmereUI.PanelPP
    local MakeBorder = EllesmereUI.MakeBorder
    local EG = EllesmereUI.ELLESMERE_GREEN
    if not (PP and MakeBorder and EG) then return nil end
    local L = EllesmereUI.L or function(s) return s end
    -- The options font once it has loaded, else the locale-aware core font
    -- (the picker runs before the options addon loads).
    local FONT = EllesmereUI._font or EllesmereUI.EXPRESSWAY
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    opts = opts or {}

    local DEFS = {
        { key = "eui", r = EG.r, g = EG.g, b = EG.b, title = "EllesmereUI Style", tag = "DEFAULT",
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
    local handles = {}
    for index, def in ipairs(DEFS) do
        local accentR, accentG, accentB = def.r, def.g, def.b
        local card = CreateFrame(display and "Frame" or "Button", nil, parent)
        card:SetFrameLevel(parent:GetFrameLevel() + 1)
        PP.Size(card, CARD_W, display and DISPLAY_CARD_H or CARD_H)
        PP.Point(card, "TOP", parent, "TOP", (index - 2) * (CARD_W + CARD_GAP), topY)
        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.09, 0.11, 0.13, 1)
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
        -- shown by SetState.
        local badge = card:CreateFontString(nil, "OVERLAY")
        badge:SetFont(FONT, 11, "")
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
        sbg:SetColorTexture(0.04, 0.05, 0.06, 1)
        MakeBorder(stage, 1, 1, 1, 0.08, PP)
        def.draw(stage, PP, MakeBorder, EG)

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
                    lbl:SetText(L(label or btnText))
                    Paint()
                end,
            }
        end
    end
    return handles
end
