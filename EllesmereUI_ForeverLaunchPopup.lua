if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_ForeverLaunchPopup.lua
--
--  One-time login popup announcing EllesmereUI on WoW Forever (with the new
--  Blizzard Style as the second headline) to EXISTING users -- people who
--  already had EllesmereUI installed before this version. "Patch Notes" opens
--  the Patch Notes module; "Got It" just closes.
--
--  NEW users never see it. The new-vs-existing guarantee mirrors the earlier
--  announcement popups: at the parent ADDON_LOADED, EllesmereUIDB still
--  reflects ONLY the previous session's data, because child addons have not
--  initialized their per-profile DBs yet this session. So a profile that
--  already carries `addons` data can only have come from a prior version =
--  an existing/upgrade user. A nil DB, or a DB with no prior addon data, is a
--  fresh install: we stamp it at login so it never fires later either.
--
--  WoW Forever itself never shows it: that client is what the popup is
--  announcing, and its saved variables are not reliable during the beta.
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.foreverLaunchIntroShown.
--  Only the newest announcement stays live: the 12.1 launch video
--  announcement (EllesmereUI_VideoGuides.lua, "midnight_121") retired when
--  this shipped, so users upgrading across several versions never see two
--  intro popups back to back.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: a single-module standalone build has no Forever story and no
-- Patch Notes module to open. Deriving this from the host addon name (the
-- `...` vararg) is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder

-- The Forever theme's bronze (the accent the "EllesmereUI Forever" options
-- theme uses) carries the announcement; the Blizzard Style tag takes the
-- style picker's gold.
local BRONZE_R, BRONZE_G, BRONZE_B = 220 / 255, 167 / 255, 127 / 255
local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.80, 0.18

-- The header art: the EllesmereUI Forever logo. The file is 384x256 with the
-- lettering inside (12,64)-(377,210); the texcoords crop to that box so the
-- art sits on the well with no dead margin. 2.5:1 drawn at 250x100.
local LOGO_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-forever-logo.png"
local LOGO_L, LOGO_R, LOGO_T, LOGO_B = 12 / 384, 377 / 384, 64 / 256, 210 / 256
local LOGO_W, LOGO_H = 250, 100

-------------------------------------------------------------------------------
--  Conflict-check handoff
--  For existing users the addon-conflict check auto-runs ~2s after load (gated
--  in EllesmereUI.lua on EllesmereUIDB.firstInstallPopupShown). We raise a
--  pending flag so that check defers while our popup is open, then trigger it
--  here on dismiss -- so the two popups never stack.
-------------------------------------------------------------------------------
local function ReleaseConflictCheck()
    EllesmereUI._foreverLaunchIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowForeverLaunchPopup()
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    -- Vertical budget (top-down): art well 118, eyebrow/title/blurb to ~245,
    -- three bullets 252-314, divider 334, ALSO NEW 346, Blizzard Style row
    -- 368, its two-line blurb to ~430, buttons 458-496, footnote at the foot.
    local POPUP_W, POPUP_H = 470, 540
    local ART_H = 118
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    -- Dimmer (eats clicks; no close on outside click)
    local dimmer = CreateFrame("Frame", "EUIForeverLaunchIntroDimmer", UIParent)
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
    local popup = CreateFrame("Frame", "EUIForeverLaunchIntroPopup", dimmer)
    popup:SetScale(EllesmereUI.PopupBump(1.15))
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

    -- Header: a darker art well flush to the top edge with the Forever logo
    -- centred on it and a bronze rule where the well meets the body (the
    -- launch-announcement band). No glow: a flat tinted texture cannot fade,
    -- it only reads as a box behind the lettering.
    local well = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    well:SetColorTexture(0.045, 0.055, 0.07, 1)
    PP.Point(well, "TOPLEFT", popup, "TOPLEFT", 0, 0)
    PP.Point(well, "TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    well:SetHeight(ART_H)

    local logo = popup:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO_PATH)
    logo:SetTexCoord(LOGO_L, LOGO_R, LOGO_T, LOGO_B)
    PP.Size(logo, LOGO_W, LOGO_H)
    PP.Point(logo, "CENTER", popup, "TOP", 0, -ART_H / 2)

    local rule = popup:CreateTexture(nil, "BACKGROUND", nil, 3)
    rule:SetColorTexture(BRONZE_R, BRONZE_G, BRONZE_B, 0.9)
    PP.Point(rule, "TOPLEFT", popup, "TOPLEFT", 0, -ART_H)
    PP.Point(rule, "TOPRIGHT", popup, "TOPRIGHT", 0, -ART_H)
    rule:SetHeight(1)

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(BRONZE_R, BRONZE_G, BRONZE_B, 0.95)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -(ART_H + 18))
    eyebrow:SetText(EllesmereUI.L("NOW ON WOW FOREVER"))

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 25, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText(EllesmereUI.L("EllesmereUI Forever"))

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 15, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 80)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
    desc:SetText(EllesmereUI.L("The full suite now runs on WoW Forever, crafted with a clean base layout for your first login."))

    -- Feature bullets
    local BULLETS = {
        EllesmereUI.L("Everything from retail, ported to WoW Forever"),
        EllesmereUI.L("One EllesmereUI: the same install runs on either game"),
        EllesmereUI.L("Export and import your profiles between the two clients"),
    }
    local prev
    for i, text in ipairs(BULLETS) do
        local bl = popup:CreateFontString(nil, "OVERLAY")
        bl:SetFont(FONT, 14, "")
        bl:SetTextColor(1, 1, 1, 0.72)
        bl:SetJustifyH("LEFT")
        if i == 1 then
            PP.Point(bl, "TOPLEFT", popup, "TOPLEFT", 72, -(ART_H + 132))
        else
            PP.Point(bl, "TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
        end
        bl:SetText(text)
        local dot = popup:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(BRONZE_R, BRONZE_G, BRONZE_B, 1)
        PP.Size(dot, 5, 5)
        PP.Point(dot, "RIGHT", bl, "LEFT", -10, 0)
        prev = bl
    end

    -- Second headline: Blizzard Style, kept smaller so Forever stays the
    -- story. A hairline divider, "ALSO NEW" in the picker's gold, the name
    -- with its BLIZZARD ART tag, two lines of copy. Every piece is placed from
    -- the popup's own centre line at a fixed offset: the name + tag pair is
    -- centred as a pair, so nothing below may chain off the (left-shifted)
    -- name or it would centre on the wrong point and spill past the edges.
    local DIV_Y, ALSO_Y, STYLE_Y, STYLE_DESC_Y = 334, 346, 368, 396
    local divider = popup:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.10)
    PP.Point(divider, "TOPLEFT", popup, "TOPLEFT", 50, -DIV_Y)
    PP.Point(divider, "TOPRIGHT", popup, "TOPRIGHT", -50, -DIV_Y)
    divider:SetHeight(1)

    local also = popup:CreateFontString(nil, "OVERLAY")
    also:SetFont(FONT, 12, "")
    also:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.9)
    PP.Point(also, "TOP", popup, "TOP", 0, -ALSO_Y)
    also:SetText(EllesmereUI.L("ALSO NEW"))

    local styleTitle = popup:CreateFontString(nil, "OVERLAY")
    styleTitle:SetFont(FONT, 18, "")
    styleTitle:SetTextColor(1, 1, 1, 1)
    styleTitle:SetText(EllesmereUI.L("Blizzard Style"))
    local tag = CreateFrame("Frame", nil, popup)
    tag:SetFrameLevel(popup:GetFrameLevel() + 1)
    local tagLbl = tag:CreateFontString(nil, "OVERLAY")
    tagLbl:SetFont(FONT, 10, "")
    tagLbl:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.9)
    tagLbl:SetText(EllesmereUI.L("BLIZZARD ART"))
    PP.Size(tag, tagLbl:GetStringWidth() + 16, 18)
    PP.Point(tagLbl, "CENTER", tag, "CENTER", 0, 0)
    local tagBg = tag:CreateTexture(nil, "BACKGROUND")
    tagBg:SetAllPoints()
    tagBg:SetColorTexture(0.05, 0.06, 0.08, 0.95)
    MakeBorder(tag, GOLD_R, GOLD_G, GOLD_B, 0.8, PP)
    -- Name + tag centred as a pair: the name's centre sits left of the popup
    -- centre by half the tag (plus gap), the tag hangs off the name's right.
    local TAG_GAP = 10
    PP.Point(styleTitle, "TOP", popup, "TOP", -(tag:GetWidth() + TAG_GAP) / 2, -STYLE_Y)
    PP.Point(tag, "LEFT", styleTitle, "RIGHT", TAG_GAP, 0)

    local styleDesc = popup:CreateFontString(nil, "OVERLAY")
    styleDesc:SetFont(FONT, 13, "")
    styleDesc:SetTextColor(1, 1, 1, 0.5)
    styleDesc:SetWidth(POPUP_W - 80)
    styleDesc:SetJustifyH("CENTER")
    styleDesc:SetWordWrap(true)
    PP.Point(styleDesc, "TOP", popup, "TOP", 0, -STYLE_DESC_Y)
    styleDesc:SetText(EllesmereUI.L("Keep every EllesmereUI feature and setting, with Blizzard's own art. Pick the look per module in Global Settings -> Style."))

    -- Stamp + close. patchNotes=true opens the Patch Notes module.
    local function Finish(patchNotes)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.foreverLaunchIntroShown = true
        dimmer:Hide()
        ReleaseConflictCheck()
        if not patchNotes then return end
        if EllesmereUI.ShowModule then
            -- ShowModule, not Show + SelectModule: it carries the first-open
            -- split, so the module still lands when the panel builds next frame.
            EllesmereUI:ShowModule("_EUIPatchNotes")
        end
    end

    -- Bordered button matching the EUI style (primary = bronze, secondary =
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

    -- Primary "Patch Notes" on the left, secondary "Got It" on the right,
    -- centered as a pair around the popup's bottom center.
    local notesBtn = MakeActionButton(EllesmereUI.L("Patch Notes"), BRONZE_R, BRONZE_G, BRONZE_B, false)
    PP.Point(notesBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 40)
    notesBtn:SetScript("OnClick", function() Finish(true) end)

    local gotBtn = MakeActionButton(EllesmereUI.L("Got It"), 1, 1, 1, true)
    PP.Point(gotBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 40)
    gotBtn:SetScript("OnClick", function() Finish(false) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 80)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText(EllesmereUI.L("On WoW Forever the same install sets itself up on first login."))

    -- Escape = Got It (non-destructive default). Consume Escape, propagate
    -- other keys so chat/UI shortcuts still work behind the dimmer.
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Finish(false) end
    end)

    dimmer:Show()
end

EllesmereUI.ShowForeverLaunchIntroPopup = ShowForeverLaunchPopup

-------------------------------------------------------------------------------
--  Trigger: existing users only, once, at login
--
--  Decision is captured at the parent ADDON_LOADED, while EllesmereUIDB still
--  holds only the previous session's data:
--    "show" -> existing/upgrade user (a profile already carries addon data)
--    "new"  -> fresh install (nil DB, or DB with no prior addon data), or the
--              WoW Forever client; stamp at login so it never fires later
--    "done" -> already shown before
-------------------------------------------------------------------------------
local _decision

local function ComputeDecision()
    -- WoW Forever is the subject of the announcement, not its audience; a
    -- session the first-install picker owns is a fresh install whatever the
    -- profile store holds (the picker's loader runs first and seeds data).
    if EllesmereUI.IS_FOREVER or EllesmereUI._firstInstallPending then return "new" end
    if not EllesmereUIDB then
        -- No SavedVariables at all -> brand-new first session.
        return "new"
    end
    if EllesmereUIDB.foreverLaunchIntroShown then
        return "done"
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
    EllesmereUIDB.foreverLaunchIntroShown = true
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
            EllesmereUI._foreverLaunchIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" or EllesmereUI._firstInstallPending then
            -- Stamp brand-new users so the popup never fires in a later
            -- session. The picker's pending flag is the authority on "fresh",
            -- so a decision reached ahead of it still stands down here.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.foreverLaunchIntroShown = true
            if EllesmereUI._foreverLaunchIntroPending then ReleaseConflictCheck() end
            return
        end
        if _decision ~= "show" then return end
        local function TryShow()
            if EllesmereUIDB and EllesmereUIDB.foreverLaunchIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Defer behind any other login announcement still pending or
            -- open, so announcements never stack on a single login.
            if EllesmereUI._launchVideoIntroPending then
                C_Timer.After(0.4, TryShow)
                return
            end
            ShowForeverLaunchPopup()
        end
        C_Timer.After(0.5, TryShow)
    end
end)

-------------------------------------------------------------------------------
--  Reset command: clears the one-time stamp so the announcement fires again
--  on the next /reload (testing aid, same as the earlier intro popups).
-------------------------------------------------------------------------------
SLASH_EUIFOREVERINTRO1 = "/euiforeverintro"
SlashCmdList["EUIFOREVERINTRO"] = function()
    if EllesmereUIDB then EllesmereUIDB.foreverLaunchIntroShown = nil end
    print("|cff00ff98EllesmereUI:|r Forever launch announcement reset. It fires on your next /reload.")
end
