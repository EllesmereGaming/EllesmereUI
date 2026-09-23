if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_StyleLaunchPopup.lua
--
--  One-time login popup announcing the looks (Blizzard Style and the new
--  Classic WoW UI beside the EllesmereUI look) to EXISTING users -- people who
--  already had EllesmereUI installed before this version. It shows the first-
--  install picker's three cards (EllesmereUI_StyleCards.lua) as display cards,
--  with no pick buttons: "Restyle My UI" goes to Global Settings > Style,
--  where the choice is made; "Got It" just closes.
--
--  NEW users never see it: a fresh install gets the style picker itself. The
--  new-vs-existing guarantee mirrors the earlier announcement popups: at the
--  parent ADDON_LOADED, EllesmereUIDB still reflects ONLY the previous
--  session's data, because child addons have not initialized their
--  per-profile DBs yet this session. So a profile that already carries
--  `addons` data can only have come from a prior version = an existing or
--  upgrade user. A nil DB, or a DB with no prior addon data, is a fresh
--  install: we stamp it at login so it never fires later either. Users who
--  met the first (two-look) picker still see it: Classic WoW UI is new to
--  them.
--
--  WoW Forever never shows it (login announcements stay off there, and its
--  saved variables are not reliable during the beta).
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.styleLaunchIntroShown.
--  Only the newest announcement stays live: the WoW Forever launch
--  announcement retired when this shipped, so users upgrading across several
--  versions never see two intro popups back to back.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: a single-module standalone build has no style picker story.
-- Deriving this from the host addon name (the `...` vararg) is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder

-------------------------------------------------------------------------------
--  Conflict-check handoff
--  For existing users the addon-conflict check auto-runs ~2s after load (gated
--  in EllesmereUI.lua on EllesmereUIDB.firstInstallPopupShown). We raise a
--  pending flag so that check defers while our popup is open, then trigger it
--  here on dismiss -- so the two popups never stack.
-------------------------------------------------------------------------------
local function ReleaseConflictCheck()
    EllesmereUI._styleLaunchIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowStyleLaunchPopup()
    if not (PP and MakeBorder and EllesmereUI.ELLESMERE_GREEN and EllesmereUI.BuildStyleCards) then
        ReleaseConflictCheck()
        return
    end
    local FONT = EllesmereUI._font or EllesmereUI.EXPRESSWAY
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    local EG = EllesmereUI.ELLESMERE_GREEN
    -- Vertical budget (top-down): eyebrow 26, title, two-line blurb to ~115,
    -- display cards 132-380, buttons 402-440, footnote at the foot.
    local CARDS_TOP = 132
    local POPUP_W = 700
    local POPUP_H = CARDS_TOP + (EllesmereUI.STYLE_CARD_DISPLAY_H or 248) + 22 + 82
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    -- Dimmer (eats clicks; no close on outside click)
    local dimmer = CreateFrame("Frame", "EUIStyleLaunchIntroDimmer", UIParent)
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
    local popup = CreateFrame("Frame", "EUIStyleLaunchIntroPopup", dimmer)
    popup:SetScale((EllesmereUI.PopupBump and EllesmereUI.PopupBump(1.15)) or 1.15)
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

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -26)
    eyebrow:SetText(EllesmereUI.L("NEW IN ELLESMEREUI"))

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText(EllesmereUI.L("Your UI, Restyled in Seconds"))

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 14, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 90)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -10)
    desc:SetText(EllesmereUI.L("Same setup, same EllesmereUI features, a new look: switch to Blizzard Style or the new Classic WoW UI in one click, and switch back any time."))

    -- The picker's three cards, display only (EllesmereUI_StyleCards.lua).
    EllesmereUI.BuildStyleCards(popup, -CARDS_TOP, { display = true })

    -- Stamp + close. openStyle=true opens Global Settings > Style.
    local function Finish(openStyle)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.styleLaunchIntroShown = true
        dimmer:Hide()
        ReleaseConflictCheck()
        if not openStyle then return end
        if InCombatLockdown() then
            if EllesmereUI.Print then
                EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat. The looks are under Global Settings > Style.")
            end
            return
        end
        if EllesmereUI.NavigateToElementSettings then
            -- Carries the options first-open split, so the page still lands
            -- when the panel builds next frame.
            EllesmereUI:NavigateToElementSettings("_EUIGlobal", "Style")
        end
    end

    -- Bordered button matching the EUI style (primary = accent, secondary =
    -- dim white that brightens on hover -- nothing destructive here).
    local BTN_W, BTN_H, BTN_GAP = 200, 38, 14
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

    -- Primary "Restyle My UI" on the left, secondary "Got It" on the
    -- right, centered as a pair around the popup's bottom center.
    local openBtn = MakeActionButton(EllesmereUI.L("Restyle My UI"), EG.r, EG.g, EG.b, false)
    PP.Point(openBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 44)
    openBtn:SetScript("OnClick", function() Finish(true) end)

    local gotBtn = MakeActionButton(EllesmereUI.L("Got It"), 1, 1, 1, true)
    PP.Point(gotBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 44)
    gotBtn:SetScript("OnClick", function() Finish(false) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 90)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText(EllesmereUI.L("Global Settings > Style sets the look for the whole UI or for each module."))

    -- Escape = Got It (non-destructive default). Consume Escape, propagate
    -- other keys so chat/UI shortcuts still work behind the dimmer.
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Finish(false) end
    end)

    dimmer:Show()
end

EllesmereUI.ShowStyleLaunchIntroPopup = ShowStyleLaunchPopup

-------------------------------------------------------------------------------
--  Trigger: existing users only, once, at login
--
--  Decision is captured at the parent ADDON_LOADED, while EllesmereUIDB still
--  holds only the previous session's data:
--    "show" -> existing/upgrade user (a profile already carries addon data)
--    "new"  -> fresh install (nil DB, or DB with no prior addon data, or the
--              session the style picker itself is due), or the WoW Forever
--              client; stamp at login so it never fires later
--    "done" -> already shown before
-------------------------------------------------------------------------------
local _decision

local function ComputeDecision()
    -- A session the first-install picker owns is a fresh install whatever the
    -- profile store holds (the picker's loader runs first and seeds data).
    if EllesmereUI.IS_FOREVER or EllesmereUI._firstInstallPending then return "new" end
    if not EllesmereUIDB then
        -- No SavedVariables at all -> brand-new first session.
        return "new"
    end
    if EllesmereUIDB.styleLaunchIntroShown then
        return "done"
    end
    -- The style picker is due this login (the session after the module
    -- picker): that popup already offers every look.
    if EllesmereUIDB.styleChoicePending then
        EllesmereUIDB.styleLaunchIntroShown = true
        return "new"
    end
    local profiles = EllesmereUIDB.profiles
    if type(profiles) == "table" then
        for _, prof in pairs(profiles) do
            if type(prof) == "table" and type(prof.addons) == "table" and next(prof.addons) then
                -- Data from a previous session = existing/upgrade user.
                return "show"
            end
        end
    end
    -- DB exists but carries no prior addon data -> treat as fresh, stamp now.
    EllesmereUIDB.styleLaunchIntroShown = true
    return "new"
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= "EllesmereUI" then return end
        self:UnregisterEvent("ADDON_LOADED")
        _decision = ComputeDecision()
        if _decision == "show" then
            -- Hold the auto conflict check until our popup is dismissed.
            EllesmereUI._styleLaunchIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" or EllesmereUI._firstInstallPending then
            -- Stamp brand-new users so the popup never fires in a later
            -- session. The picker's pending flag is the authority on "fresh",
            -- so a decision reached ahead of it still stands down here.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.styleLaunchIntroShown = true
            if EllesmereUI._styleLaunchIntroPending then ReleaseConflictCheck() end
            return
        end
        if _decision ~= "show" then return end
        local function TryShow()
            if EllesmereUIDB and EllesmereUIDB.styleLaunchIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Defer behind any other login announcement still pending or
            -- open, so announcements never stack on a single login.
            if EllesmereUI._launchVideoIntroPending then
                C_Timer.After(0.4, TryShow)
                return
            end
            ShowStyleLaunchPopup()
        end
        C_Timer.After(0.5, TryShow)
    end
end)

-------------------------------------------------------------------------------
--  Reset command: clears the one-time stamp so the announcement fires again
--  on the next /reload (testing aid, same as the earlier intro popups).
-------------------------------------------------------------------------------
SLASH_EUISTYLEINTRO1 = "/euistyleintro"
SlashCmdList["EUISTYLEINTRO"] = function()
    if EllesmereUIDB then EllesmereUIDB.styleLaunchIntroShown = nil end
    print("|cff00ff98EllesmereUI:|r Style announcement reset. It fires on your next /reload.")
end
