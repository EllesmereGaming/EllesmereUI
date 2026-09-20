if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_StyleChoicePopup.lua
--
--  First-install style picker. On the login AFTER the module picker's reload
--  (EllesmereUI_FirstInstall.lua stamps EllesmereUIDB.styleChoicePending in
--  its close path) one popup offers the two looks side by side, each with a
--  mock of what it means: the EllesmereUI style (the default; closes the
--  popup) or the Blizzard style (every loaded module's Style flag set at once
--  through the Style page's registry, then a reload). Once per install; an
--  existing user never sees it, since only the picker writes the stamp.
--  Global Settings > Style keeps every choice reversible per module.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN
local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.80, 0.18

local function AtlasOK(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false
end

local function Stamp()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.styleChoicePending = nil
    EllesmereUIDB.styleChoiceShown = true
end

-- Blizzard: the flags ride the Style page's own registry (LoadOnDemand
-- options), so one code path owns what "all modules" means; then the reload
-- every style change needs.
local function ChooseBlizzard()
    Stamp()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("EllesmereUIOptions")
    end
    local BS = EllesmereUI.BlizzStyle
    if BS and BS.ApplyAll then
        BS.ApplyAll(true)
        ReloadUI()
        return
    end
    if EllesmereUI.Print then
        EllesmereUI.Print("|cff00ff98EllesmereUI:|r Blizzard Style can be switched on under Global Settings > Style.")
    end
end

local function ShowStyleChoicePopup()
    if not (PP and MakeBorder and ELLESMERE_GREEN) then return end
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local EG = ELLESMERE_GREEN
    local POPUP_W, POPUP_H = 660, 470
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    local dimmer = CreateFrame("Frame", "EUIStyleChoiceDimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScale(ppScale)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.45)

    local popup = CreateFrame("Frame", "EUIStyleChoicePopup", dimmer)
    popup:SetScale((EllesmereUI.PopupBump and EllesmereUI.PopupBump(1.15)) or 1.15)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PP.Size(popup, POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    local onePhys = 1 / (popup:GetEffectiveScale() or 1)
    local function MakeEdge()
        local t = popup:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, 0.15)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local spT = MakeEdge(); spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(onePhys)
    local spB = MakeEdge(); spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(onePhys)
    local spL = MakeEdge(); spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(onePhys)
    local spR = MakeEdge(); spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(onePhys)

    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -26)
    eyebrow:SetText("CHOOSE YOUR LOOK")

    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("How should EllesmereUI look?")

    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 14, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 90)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -10)
    desc:SetText("Every feature works the same either way. Change your mind any time under Global Settings > Style.")

    ---------------------------------------------------------------------------
    --  Two cards. Each is one click target: the whole card and its button
    --  pick that style. Hover lights the card in its own colour.
    ---------------------------------------------------------------------------
    local CARD_W, CARD_H, CARD_GAP = 284, 284, 22
    local MOCK_W, MOCK_H = 232, 118

    local function MakeCard(side, accentR, accentG, accentB, cardTitle, tag, caption, btnText, onPick)
        local card = CreateFrame("Button", nil, popup)
        card:SetFrameLevel(popup:GetFrameLevel() + 1)
        PP.Size(card, CARD_W, CARD_H)
        if side == "left" then
            PP.Point(card, "TOPRIGHT", popup, "TOP", -CARD_GAP / 2, -128)
        else
            PP.Point(card, "TOPLEFT", popup, "TOP", CARD_GAP / 2, -128)
        end
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
        ct:SetFont(FONT, 19, "")
        ct:SetTextColor(accentR, accentG, accentB, 1)
        PP.Point(ct, "TOP", card, "TOP", 0, -16)
        ct:SetText(cardTitle)

        -- Small tag under the title (DEFAULT / BLIZZARD ART).
        local tagFS = card:CreateFontString(nil, "OVERLAY")
        tagFS:SetFont(FONT, 11, "")
        tagFS:SetTextColor(accentR, accentG, accentB, 0.7)
        PP.Point(tagFS, "TOP", ct, "BOTTOM", 0, -3)
        tagFS:SetText(tag)

        -- Mock area: a dark stage the style mock is drawn on.
        local stage = CreateFrame("Frame", nil, card)
        stage:SetFrameLevel(card:GetFrameLevel() + 1)
        PP.Size(stage, MOCK_W, MOCK_H)
        PP.Point(stage, "TOP", tagFS, "BOTTOM", 0, -12)
        local sbg = stage:CreateTexture(nil, "BACKGROUND")
        sbg:SetAllPoints()
        sbg:SetColorTexture(0.04, 0.05, 0.06, 1)
        MakeBorder(stage, 1, 1, 1, 0.08, PP)

        local cap = card:CreateFontString(nil, "OVERLAY")
        cap:SetFont(FONT, 13, "")
        cap:SetTextColor(1, 1, 1, 0.7)
        cap:SetWidth(CARD_W - 32)
        cap:SetJustifyH("CENTER")
        cap:SetWordWrap(true)
        PP.Point(cap, "TOP", stage, "BOTTOM", 0, -12)
        cap:SetText(caption)

        local btn = CreateFrame("Button", nil, card)
        btn:SetFrameLevel(card:GetFrameLevel() + 2)
        PP.Size(btn, CARD_W - 40, 36)
        PP.Point(btn, "BOTTOM", card, "BOTTOM", 0, 14)
        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(accentR, accentG, accentB, 0.12)
        local bbrd = MakeBorder(btn, accentR, accentG, accentB, 0.8, PP)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT, 15, "")
        PP.Point(lbl, "CENTER", btn, "CENTER", 0, 0)
        lbl:SetTextColor(1, 1, 1, 0.95)
        lbl:SetText(btnText)

        local function Lit(on)
            if on then
                brd:SetColor(accentR, accentG, accentB, 0.9)
                bbg:SetColorTexture(accentR, accentG, accentB, 0.28)
                bbrd:SetColor(accentR, accentG, accentB, 1)
            else
                brd:SetColor(1, 1, 1, 0.14)
                bbg:SetColorTexture(accentR, accentG, accentB, 0.12)
                bbrd:SetColor(accentR, accentG, accentB, 0.8)
            end
        end
        card:SetScript("OnEnter", function() Lit(true) end)
        card:SetScript("OnLeave", function() Lit(false) end)
        card:SetScript("OnClick", onPick)
        btn:SetScript("OnEnter", function() Lit(true) end)
        btn:SetScript("OnLeave", function() Lit(false) end)
        btn:SetScript("OnClick", onPick)
        return card, stage
    end

    ---------------------------------------------------------------------------
    --  EllesmereUI mock: a flat unit frame (teal health, blue power, a name
    --  line) over a row of square icons -- the look in miniature.
    ---------------------------------------------------------------------------
    local function DrawEUIMock(stage)
        local frame = CreateFrame("Frame", nil, stage)
        frame:SetFrameLevel(stage:GetFrameLevel() + 1)
        PP.Size(frame, 172, 44)
        PP.Point(frame, "TOP", stage, "TOP", 0, -14)
        local fbg = frame:CreateTexture(nil, "BACKGROUND")
        fbg:SetAllPoints()
        fbg:SetColorTexture(0.075, 0.113, 0.141, 1)
        MakeBorder(frame, 0, 0, 0, 1, PP)
        local health = frame:CreateTexture(nil, "ARTWORK")
        health:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
        PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 1, -1)
        PP.Size(health, 150, 30)
        local hrest = frame:CreateTexture(nil, "ARTWORK")
        hrest:SetColorTexture(EG.r, EG.g, EG.b, 0.2)
        PP.Point(hrest, "TOPLEFT", health, "TOPRIGHT", 0, 0)
        PP.Point(hrest, "BOTTOMRIGHT", frame, "TOPRIGHT", -1, -31)
        local power = frame:CreateTexture(nil, "ARTWORK")
        power:SetColorTexture(0.25, 0.5, 0.9, 0.9)
        PP.Point(power, "TOPLEFT", frame, "TOPLEFT", 1, -32)
        PP.Size(power, 120, 11)
        local prest = frame:CreateTexture(nil, "ARTWORK")
        prest:SetColorTexture(0.25, 0.5, 0.9, 0.2)
        PP.Point(prest, "TOPLEFT", power, "TOPRIGHT", 0, 0)
        PP.Point(prest, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        local nameLine = frame:CreateTexture(nil, "OVERLAY")
        nameLine:SetColorTexture(1, 1, 1, 0.85)
        PP.Size(nameLine, 58, 5)
        PP.Point(nameLine, "TOPLEFT", frame, "TOPLEFT", 8, -13)
        local hpLine = frame:CreateTexture(nil, "OVERLAY")
        hpLine:SetColorTexture(1, 1, 1, 0.85)
        PP.Size(hpLine, 28, 5)
        PP.Point(hpLine, "TOPRIGHT", frame, "TOPRIGHT", -8, -13)

        local ICON, GAP, N = 26, 4, 5
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

    ---------------------------------------------------------------------------
    --  Blizzard mock: the stock player frame art with its health and mana
    --  fills, over a row of the rounded stock button slots. Every atlas is
    --  validated; a missing one falls back to a plain gold-framed box so the
    --  card never shows a blank stage.
    ---------------------------------------------------------------------------
    local function DrawBlizzMock(stage)
        local ART = "UI-HUD-UnitFrame-Player-PortraitOn"
        local HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
        local MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana"
        local SLOT = "UI-HUD-ActionBar-IconFrame-Slot"
        local frame = CreateFrame("Frame", nil, stage)
        frame:SetFrameLevel(stage:GetFrameLevel() + 1)
        if AtlasOK(ART) then
            -- The 198x71 art at 0.9, its bars placed from the stock geometry
            -- (the bars sit at 85/40 and 85/61 in the 232x100 box whose art
            -- is centred with 17 and 14.5 of transparent margin).
            local s = 0.9
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
            PP.Size(frame, 172, 44)
            PP.Point(frame, "TOP", stage, "TOP", 0, -14)
            local fbg = frame:CreateTexture(nil, "BACKGROUND")
            fbg:SetAllPoints()
            fbg:SetColorTexture(0.12, 0.10, 0.06, 1)
            MakeBorder(frame, GOLD_R, GOLD_G, GOLD_B, 0.8, PP)
            local health = frame:CreateTexture(nil, "ARTWORK")
            health:SetColorTexture(0.1, 0.75, 0.1, 0.9)
            PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 3, -3)
            PP.Size(health, 140, 22)
            local power = frame:CreateTexture(nil, "ARTWORK")
            power:SetColorTexture(0.1, 0.35, 0.9, 0.9)
            PP.Point(power, "TOPLEFT", frame, "TOPLEFT", 3, -28)
            PP.Size(power, 110, 13)
        end

        local ICON, GAP, N = 26, 4, 5
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

    local function ChooseEUI()
        Stamp()
        dimmer:Hide()
    end

    local _, euiStage = MakeCard("left", EG.r, EG.g, EG.b, "EllesmereUI Style", "DEFAULT",
        "Flat, clean and modern. The look EllesmereUI was designed around.",
        "Use EllesmereUI Style", ChooseEUI)
    DrawEUIMock(euiStage)

    local _, blizzStage = MakeCard("right", GOLD_R, GOLD_G, GOLD_B, "Blizzard Style", "BLIZZARD ART",
        "Blizzard's own frame and button art, with every EllesmereUI feature kept.",
        "Use Blizzard Style", ChooseBlizzard)
    DrawBlizzMock(blizzStage)

    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 90)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 14)
    footnote:SetText("Blizzard Style reloads the UI once to apply. Each module can be switched separately later.")

    -- Escape = the EllesmereUI look (the non-destructive default).
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then ChooseEUI() end
    end)

    dimmer:Show()
end

EllesmereUI.ShowStyleChoicePopup = ShowStyleChoicePopup

-------------------------------------------------------------------------------
--  Trigger: the login after the module picker's reload, once. Defers behind
--  the intro announcements the way the other popups do, so nothing stacks.
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- TEMPORARY, WoW Forever only (EllesmereUI.FOREVER_SV_BUG): the style
    -- choice needs a reload to apply, and a reload wipes settings on the beta
    -- client, so the picker stays off there until Blizzard fixes it.
    if EllesmereUI.FOREVER_SV_BUG then return end
    if not (EllesmereUIDB and EllesmereUIDB.styleChoicePending) then return end
    -- The picker itself is still due this session: it reloads, and its
    -- close path re-arms the stamp for the login after.
    if EllesmereUI._firstInstallPending then return end
    -- A registered external installer owns the first-run experience.
    if EllesmereUI._externalInstaller then Stamp() return end
    local tries = 0
    local function TryShow()
        if not (EllesmereUIDB and EllesmereUIDB.styleChoicePending) then return end
        tries = tries + 1
        if tries < 25 and (EllesmereUI._raidFramesIntroPending or EllesmereUI._patchNotesIntroPending
            or EllesmereUI._windowSkinsIntroPending) then
            C_Timer.After(0.4, TryShow)
            return
        end
        ShowStyleChoicePopup()
    end
    C_Timer.After(0.8, TryShow)
end)
