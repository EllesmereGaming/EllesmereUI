-------------------------------------------------------------------------------
--  EllesmereUI_PTRManagersPopup.lua
--
--  One-time login popup announcing the new filter-based Buff Manager and
--  Debuff Manager (the 12.1 buff/debuff filtering system) to PTR testers.
--  "Show Me" opens Raid Frames options on the Buff Manager page.
--
--  PTR ONLY: gated on a 12.1 client AND IsTestBuild(), so it never fires on
--  retail -- including after 12.1 launches there. If we want a retail launch
--  announcement later, lift the IsTestBuild gate and rework the copy (the
--  eyebrow says PTR). Scheduled for deletion in the at-launch cleanup pass.
--
--  Unlike the retired retail intro popups, this shows to EVERYONE on the PTR
--  (no existing-vs-new-user split): every PTR user is a tester and the
--  managers replaced the old Buff Manager and Auras pages wholesale, so
--  fresh installs need the tour just as much as upgraders.
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.ptrManagersIntroShown
--  (PTR SavedVariables are separate from retail, so the stamp never travels).
--  Defers behind the first-install wizard and every older intro popup so
--  announcements never stack on a single login. Reset: /euimanagersintro.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- PTR gate: 12.1 client AND a test build. IsTestBuild is false on live
-- retail clients, so this file is fully inert there even after 12.1 ships.
if not (EllesmereUI.IS_121 and IsTestBuild and IsTestBuild()) then return end

-- Suite-only: the managers ship in the RaidFrames child; a single-module
-- standalone build has no announcement surface. Deriving this from the host
-- addon name (the `...` vararg = real folder name) is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local RF_FOLDER = "EllesmereUIRaidFrames"

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN

-------------------------------------------------------------------------------
--  Conflict-check handoff
--  The addon-conflict check auto-runs ~2s after load (gated in EllesmereUI.lua
--  on EllesmereUIDB.firstInstallPopupShown and the intro pending flags). We
--  raise a pending flag so that check defers while our popup is open, then
--  trigger it here on dismiss -- so the two popups never stack.
-------------------------------------------------------------------------------
local function ReleaseConflictCheck()
    EllesmereUI._ptrManagersIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowPTRManagersPopup()
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local EG = ELLESMERE_GREEN
    local POPUP_W, POPUP_H = 470, 384
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    -- Dimmer (eats clicks; no close on outside click)
    local dimmer = CreateFrame("Frame", "EUIPTRManagersIntroDimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScale(ppScale)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.35)

    -- Panel
    local popup = CreateFrame("Frame", "EUIPTRManagersIntroPopup", dimmer)
    popup:SetScale(ppScale * 1.15)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PP.Size(popup, POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    -- 1 physical-pixel white border (alpha 0.15), scale-derived so each edge
    -- stays exactly one physical pixel. Four edge textures, snap disabled.
    local onePhys = 1 / (popup:GetEffectiveScale() or 1)
    local BRD_A = 0.15
    local function MakeEdge()
        local t = popup:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, BRD_A)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local spT = MakeEdge(); spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(onePhys)
    local spB = MakeEdge(); spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(onePhys)
    local spL = MakeEdge(); spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(onePhys)
    local spR = MakeEdge(); spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(onePhys)

    -- Decorative header visual: two mini raid-frame cards, one per manager.
    -- Each card = filter chips up top (the "categories" read), a health bar
    -- with a missing-health notch, and aura icon squares. Left card = Buff
    -- Manager (green accent, corner indicator run riding the frame's top-left
    -- corner). Right card = Debuff Manager (red accent, centered base-grid
    -- icons in dispel-type colors, with a glow ring on the CC debuff).
    local CARD_W, CARD_H, CARD_GAP = 158, 56, 18
    local MIDLINE = -54
    local cards = {
        {
            label = "BUFF MANAGER",
            accent = { EG.r, EG.g, EG.b },
            chips = { { EG.r, EG.g, EG.b }, { 0.25, 0.78, 0.78 }, { 1, 0.82, 0.30 } },
            icons = { { 0.35, 0.85, 0.45 }, { 0.25, 0.80, 0.80 }, { 1, 0.82, 0.30 } },
            corner = true,
        },
        {
            label = "DEBUFF MANAGER",
            accent = { 0.85, 0.30, 0.30 },
            chips = { { 1, 0.82, 0.30 }, { 0.85, 0.25, 0.25 }, { 0.25, 0.55, 0.95 } },
            icons = { { 0.25, 0.55, 0.95 }, { 0.60, 0.25, 0.95 }, { 0.85, 0.30, 0.30, glow = true } },
            corner = false,
        },
    }
    for i, cd in ipairs(cards) do
        local card = CreateFrame("Frame", nil, popup)
        card:SetFrameLevel(popup:GetFrameLevel() + 1)
        PP.Size(card, CARD_W, CARD_H)
        PP.Point(card, "CENTER", popup, "TOP",
            (i - 1.5) * (CARD_W + CARD_GAP), MIDLINE)
        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.12, 0.13, 0.15, 1)

        -- Filter chip row, centered near the top.
        for k, c in ipairs(cd.chips) do
            local chip = card:CreateTexture(nil, "ARTWORK")
            chip:SetColorTexture(c[1], c[2], c[3], 0.80)
            PP.Size(chip, 16, 5)
            PP.Point(chip, "TOP", card, "TOP", (k - 2) * 21, -9)
        end

        -- Mini health bar: dark track with a green fill and a missing-health
        -- notch on the right, selling the "raid frame".
        local BAR_W, BAR_H = CARD_W - 20, 13
        local track = card:CreateTexture(nil, "BORDER")
        track:SetColorTexture(0.085, 0.095, 0.105, 1)
        PP.Size(track, BAR_W, BAR_H)
        PP.Point(track, "TOPLEFT", card, "TOPLEFT", 10, -26)
        local fill = card:CreateTexture(nil, "BORDER", nil, 1)
        fill:SetColorTexture(0.21, 0.46, 0.32, 1)
        PP.Size(fill, BAR_W * 0.78, BAR_H)
        PP.Point(fill, "TOPLEFT", track, "TOPLEFT", 0, 0)

        -- Aura icon squares: 1px dark backing behind each for a border read;
        -- the glow-flagged icon gets a red halo backing instead (frame-glow
        -- and CC-glow hint).
        local ICON = 11
        for k, c in ipairs(cd.icons) do
            local backing = card:CreateTexture(nil, "ARTWORK", nil, -1)
            local tex = card:CreateTexture(nil, "ARTWORK")
            tex:SetColorTexture(c[1], c[2], c[3], 1)
            PP.Size(tex, ICON, ICON)
            if cd.corner then
                -- Corner indicator run riding the frame's top-left corner.
                PP.Point(tex, "CENTER", track, "TOPLEFT", 9 + (k - 1) * (ICON + 3), 1)
            else
                -- Base grid, centered on the frame.
                PP.Point(tex, "CENTER", track, "CENTER", (k - 2) * (ICON + 3), 0)
            end
            if c.glow then
                backing:SetColorTexture(0.95, 0.30, 0.25, 0.85)
                PP.Size(backing, ICON + 4, ICON + 4)
            else
                backing:SetColorTexture(0.05, 0.05, 0.06, 0.9)
                PP.Size(backing, ICON + 2, ICON + 2)
            end
            PP.Point(backing, "CENTER", tex, "CENTER", 0, 0)
        end

        -- Card label, small and dim (the two-system read at a glance).
        local lbl = card:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT, 10, "")
        local a = cd.accent
        lbl:SetTextColor(a[1], a[2], a[3], 0.75)
        PP.Point(lbl, "BOTTOM", card, "BOTTOM", 0, 5)
        lbl:SetText(cd.label)

        MakeBorder(card, a[1], a[2], a[3], 0.45, PP)
    end

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -104)
    eyebrow:SetText("NEW ON THE 12.1 PTR")

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 25, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("Buff & Debuff Managers")

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 15, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 80)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
    desc:SetText("Raid frame buffs and debuffs are rebuilt for Midnight's new aura engine. Track whole spell categories with filters, then give each one its own display.")

    -- Feature bullets
    local BULLETS = {
        "Filters: Defensives, Raid CDs, Healing Buffs and more",
        "Debuff categories: Important, CC, Dispellable, Boss",
        "Style each filter: icon rows, glows, bars, health color",
    }
    local prev
    for i, text in ipairs(BULLETS) do
        local bl = popup:CreateFontString(nil, "OVERLAY")
        bl:SetFont(FONT, 14, "")
        bl:SetTextColor(1, 1, 1, 0.72)
        bl:SetJustifyH("LEFT")
        if i == 1 then
            PP.Point(bl, "TOPLEFT", popup, "TOPLEFT", 72, -218)
        else
            PP.Point(bl, "TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
        end
        bl:SetText(text)
        local dot = popup:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(EG.r, EG.g, EG.b, 1)
        PP.Size(dot, 5, 5)
        PP.Point(dot, "RIGHT", bl, "LEFT", -10, 0)
        prev = bl
    end

    -- Stamp + close. showMe=true opens Raid Frames options on the Buff
    -- Manager page (the Debuff Manager page sits right beside it).
    local function Finish(showMe)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.ptrManagersIntroShown = true
        dimmer:Hide()
        ReleaseConflictCheck()
        if not showMe then return end
        if EllesmereUI.NavigateToElementSettings then
            EllesmereUI:NavigateToElementSettings(RF_FOLDER, "Buff Manager")
        elseif EllesmereUI.SelectModule then
            EllesmereUI:Show()
            EllesmereUI:SelectModule(RF_FOLDER)
        end
    end

    -- Bordered button matching the EUI style (primary = green, secondary =
    -- dim white that brightens on hover -- nothing destructive here).
    local BTN_W, BTN_H, BTN_GAP = 184, 38, 14
    local function MakeActionButton(text, r, g, b, secondary)
        local btn = CreateFrame("Button", nil, popup)
        btn:SetFrameLevel(popup:GetFrameLevel() + 2)
        PP.Size(btn, BTN_W, BTN_H)
        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
        local brd = MakeBorder(btn, r, g, b, secondary and 0.35 or 0.9, PP)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT, 15, "")
        PP.Point(lbl, "CENTER", btn, "CENTER", 0, 0)
        lbl:SetTextColor(r, g, b, secondary and 0.55 or 0.9)
        lbl:SetText(text)
        btn:SetScript("OnEnter", function()
            lbl:SetTextColor(r, g, b, 1)
            brd:SetColor(r, g, b, secondary and 0.8 or 1)
        end)
        btn:SetScript("OnLeave", function()
            lbl:SetTextColor(r, g, b, secondary and 0.55 or 0.9)
            brd:SetColor(r, g, b, secondary and 0.35 or 0.9)
        end)
        return btn
    end

    -- Primary "Show Me" on the left, secondary "Got It" on the right,
    -- centered as a pair around the popup's bottom center.
    local showBtn = MakeActionButton("Show Me", EG.r, EG.g, EG.b, false)
    PP.Point(showBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 40)
    showBtn:SetScript("OnClick", function() Finish(true) end)

    local gotBtn = MakeActionButton("Got It", 1, 1, 1, true)
    PP.Point(gotBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 40)
    gotBtn:SetScript("OnClick", function() Finish(false) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 80)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText("Find them in Raid Frames: Buff Manager & Debuff Manager.")

    -- Escape = Got It (non-destructive default). Consume Escape, propagate
    -- other keys so chat/UI shortcuts still work behind the dimmer.
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Finish(false) end
    end)

    dimmer:Show()
end

EllesmereUI.ShowPTRManagersIntroPopup = ShowPTRManagersPopup

-------------------------------------------------------------------------------
--  Trigger: every PTR user, once, at login
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if EllesmereUIDB and EllesmereUIDB.ptrManagersIntroShown then return end
    -- Hold the auto conflict check until our popup is dismissed.
    EllesmereUI._ptrManagersIntroPending = true
    local function TryShow()
        if EllesmereUIDB and EllesmereUIDB.ptrManagersIntroShown then
            ReleaseConflictCheck()
            return
        end
        -- Defer behind the first-install wizard and every older intro popup
        -- if any is still pending or open, so announcements never stack on a
        -- single login.
        if EllesmereUI._firstInstallPending
           or EllesmereUI._raidFramesIntroPending
           or EllesmereUI._patchNotesIntroPending
           or EllesmereUI._windowSkinsIntroPending
           or EllesmereUI._specOvIntroPending then
            C_Timer.After(0.4, TryShow)
            return
        end
        -- Only announce if the Raid Frames module is actually loaded -- the
        -- managers live there. Otherwise stamp silently and hand off.
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(RF_FOLDER)
        if not loaded then
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.ptrManagersIntroShown = true
            ReleaseConflictCheck()
            return
        end
        ShowPTRManagersPopup()
    end
    C_Timer.After(0.5, TryShow)
end)

-------------------------------------------------------------------------------
--  Reset command: clears the one-time stamp so the announcement fires again
--  on the next /reload (handy for previewing copy and art changes).
-------------------------------------------------------------------------------
SLASH_EUIMANAGERSINTRO1 = "/euimanagersintro"
SlashCmdList["EUIMANAGERSINTRO"] = function()
    if EllesmereUIDB then
        EllesmereUIDB.ptrManagersIntroShown = nil
    end
    print("|cff00ff98EllesmereUI:|r Managers intro reset. The announcement popup fires on your next /reload.")
end
