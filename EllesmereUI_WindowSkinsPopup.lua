if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_WindowSkinsPopup.lua
--
--  One-time login popup that announces the new Blizzard Window Skinning feature
--  to EXISTING users (people who already had EllesmereUI installed before this
--  version) and lets them turn it off on the spot. "Disable" writes every
--  window's enable key false (EllesmereUI.DisableAllBlizzWindowSkins) and
--  reloads -- the reskins install at load, so a reload is required.
--
--  NEW users never see it. The new-vs-existing guarantee mirrors
--  EllesmereUI_PatchNotesPopup.lua: at the parent ADDON_LOADED, EllesmereUIDB
--  still reflects ONLY the previous session's data, because child addons have
--  not initialized their per-profile DBs yet this session. So a profile that
--  already carries `addons` data can only have come from a prior version =
--  an existing/upgrade user. A nil DB, or a DB with no prior addon data, is a
--  fresh install: we stamp it at login so it never fires later either.
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.windowSkinsIntroShown.
--  Defers behind the Raid Frames and Patch Notes intro popups if either is also
--  pending (a user upgrading across several versions at once), so the
--  announcements never stack on a single login.
--
--  RETIRED 2026-07-12: announcement has had its run; killed at the top so
--  users upgrading across versions are never shown several intro popups back
--  to back (only the newest announcement fires). Everything below is inert --
--  loader, art, and DB stamping all dead; windowSkinsIntroShown is no longer
--  written for anyone. Delete the guard below to revive the popup.
-------------------------------------------------------------------------------
do return end

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: the window-skin engine ships in the BlizzardSkin child, never in
-- a single-module standalone build, so the announcement is meaningless there.
-- Deriving this from the host addon name (the `...` vararg = real folder name)
-- is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local BLIZZ_SKIN_FOLDER = "EllesmereUIBlizzardSkin"

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN

-- The sidebar power button's red, reused on the Disable button hover.
local DISABLE_R, DISABLE_G, DISABLE_B = 0.824, 0.212, 0.212

-------------------------------------------------------------------------------
--  Conflict-check handoff
--  For existing users the addon-conflict check auto-runs ~2s after load (gated
--  in EllesmereUI.lua on EllesmereUIDB.firstInstallPopupShown). We raise a
--  pending flag so that check defers while our popup is open, then trigger it
--  here on dismiss -- so the two popups never stack.
-------------------------------------------------------------------------------
local function ReleaseConflictCheck()
    EllesmereUI._windowSkinsIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowWindowSkinsPopup()
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local EG = ELLESMERE_GREEN
    local POPUP_W, POPUP_H = 470, 384
    -- Dimmer eats clicks (no close on outside click). Escape = Keep Enabled.
    local Finish
    local dimmer, popup = EllesmereUI.BuildPopupShell("EUIWindowSkinsIntro", {
        w = POPUP_W, h = POPUP_H, bump = 1.15,
        onEscape = function() Finish(false) end,
    })

    -- Decorative header visual: three mini Blizzard "windows", each with a
    -- colored title bar (green/blue/purple, hinting the recolorable theme) and
    -- stand-in body lines. The center window is scaled up with a resize grip in
    -- its corner, hinting the Shifter scaling. Centered on a shared midline so
    -- the taller center window reads as "scaled".
    local CARD_W, CARD_H, CARD_GAP = 124, 52, 14
    local MIDLINE = -52   -- header band vertical center, below the popup top
    local titleColors = {
        { EG.r, EG.g, EG.b },
        { 0.25, 0.50, 0.90 },
        { 0.64, 0.39, 0.93 },
    }
    for i = 1, 3 do
        local isCenter = (i == 2)
        local w = CARD_W
        local h = isCenter and (CARD_H + 10) or CARD_H
        local card = CreateFrame("Frame", nil, popup)
        card:SetFrameLevel(popup:GetFrameLevel() + 1)
        PP.Size(card, w, h)
        PP.Point(card, "CENTER", popup, "TOP", (i - 2) * (CARD_W + CARD_GAP), MIDLINE)
        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.12, 0.13, 0.15, 1)

        -- Window title bar (colored, full width inset 1px so the border reads
        -- around it), with a small close-dot at its right to sell the "window".
        local c = titleColors[i]
        local bar = card:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(c[1], c[2], c[3], isCenter and 0.95 or 0.75)
        bar:SetHeight(8)
        PP.Point(bar, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(bar, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        if bar.SetSnapToPixelGrid then bar:SetSnapToPixelGrid(false); bar:SetTexelSnappingBias(0) end
        local dot = card:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(0, 0, 0, 0.4)
        PP.Size(dot, 4, 4)
        PP.Point(dot, "RIGHT", bar, "RIGHT", -3, 0)

        -- Stand-in body lines: brighter title line then dimmer body lines. The
        -- taller center window gets a third line.
        local l1 = card:CreateTexture(nil, "ARTWORK")
        l1:SetColorTexture(1, 1, 1, isCenter and 0.42 or 0.32)
        PP.Size(l1, w - 26, 5)
        PP.Point(l1, "TOPLEFT", card, "TOPLEFT", 13, -18)
        local l2 = card:CreateTexture(nil, "ARTWORK")
        l2:SetColorTexture(1, 1, 1, 0.18)
        PP.Size(l2, w - 46, 5)
        PP.Point(l2, "TOPLEFT", l1, "BOTTOMLEFT", 0, -7)
        if isCenter then
            local l3 = card:CreateTexture(nil, "ARTWORK")
            l3:SetColorTexture(1, 1, 1, 0.14)
            PP.Size(l3, w - 66, 5)
            PP.Point(l3, "TOPLEFT", l2, "BOTTOMLEFT", 0, -7)
            -- Resize grip in the bottom-right corner (Shifter scaling hint).
            local grip = card:CreateTexture(nil, "OVERLAY")
            grip:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
            PP.Size(grip, 5, 5)
            PP.Point(grip, "BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        end
        MakeBorder(card, 1, 1, 1, isCenter and 0.16 or 0.10, PP)
    end

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -104)
    eyebrow:SetText("NEW FEATURE")

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 25, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("Blizzard Window Skinning")

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 15, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 80)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
    desc:SetText("Blizzard's windows now match the EllesmereUI theme with a WoW 2.0 Dark Theme, from the Dungeon Journal to the Auction House and beyond.")

    -- Feature bullets
    local BULLETS = {
        "Every major Blizzard window themed to match EUI",
        "Recolor the theme to any color and opacity you like",
        "Scale any window larger or smaller with Shifter",
    }
    local prev
    for i, text in ipairs(BULLETS) do
        local bl = popup:CreateFontString(nil, "OVERLAY")
        bl:SetFont(FONT, 14, "")
        bl:SetTextColor(1, 1, 1, 0.72)
        bl:SetJustifyH("LEFT")
        if i == 1 then
            PP.Point(bl, "TOPLEFT", popup, "TOPLEFT", 92, -218)
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

    -- Stamp + close. disable=true turns off every window reskin and reloads
    -- (the reskins install at load, so the change needs a fresh UI).
    Finish = function(disable)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.windowSkinsIntroShown = true
        if disable then
            if EllesmereUI.DisableAllBlizzWindowSkins then
                EllesmereUI.DisableAllBlizzWindowSkins()
            end
            EllesmereUI.RequestReload()
            -- On the Forever client the reload waits on its popup: close the
            -- announcement and clear its pending flag so the popups queued
            -- behind it stop waiting. Retail is already reloading.
            dimmer:Hide()
            EllesmereUI._windowSkinsIntroPending = nil
            return
        end
        dimmer:Hide()
        ReleaseConflictCheck()
    end

    -- Primary "Keep Enabled" on the left, secondary "Disable" (warms to the
    -- power-button red on hover) on the right, centered as a pair.
    local BTN_W, BTN_GAP = 184, 14
    local keepBtn = EllesmereUI.MakeActionButton(popup, FONT, "Keep Enabled", EG.r, EG.g, EG.b, { w = BTN_W })
    PP.Point(keepBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 40)
    keepBtn:SetScript("OnClick", function() Finish(false) end)

    local disBtn = EllesmereUI.MakeActionButton(popup, FONT, "Disable", 1, 1, 1,
        { w = BTN_W, secondary = true, hoverRGB = { DISABLE_R, DISABLE_G, DISABLE_B } })
    PP.Point(disBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 40)
    disBtn:SetScript("OnClick", function() Finish(true) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 80)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText("Style each window your own way.")

    dimmer:Show()
end

EllesmereUI.ShowWindowSkinsIntroPopup = ShowWindowSkinsPopup

-------------------------------------------------------------------------------
--  Trigger: existing users only, once, at login
--
--  Decision is captured at the parent ADDON_LOADED, while EllesmereUIDB still
--  holds only the previous session's data:
--    "show" -> existing/upgrade user (a profile already carries addon data)
--    "new"  -> fresh install (nil DB, or DB with no prior addon data); stamp
--              at login so it never fires later
--    "done" -> already shown before
-------------------------------------------------------------------------------
local _decision

local function ComputeDecision()
    if not EllesmereUIDB then
        -- No SavedVariables at all -> brand-new first session.
        return "new"
    end
    if EllesmereUIDB.windowSkinsIntroShown then
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
    EllesmereUIDB.windowSkinsIntroShown = true
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
            EllesmereUI._windowSkinsIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" then
            -- Stamp brand-new users so the popup never fires in a later session.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.windowSkinsIntroShown = true
            return
        end
        if _decision ~= "show" then return end
        local function TryShow()
            if EllesmereUIDB and EllesmereUIDB.windowSkinsIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Defer behind the Raid Frames and Patch Notes intro popups if
            -- either is still pending or open, so the announcements never stack
            -- on a single login.
            if EllesmereUI._raidFramesIntroPending or EllesmereUI._patchNotesIntroPending then
                C_Timer.After(0.4, TryShow)
                return
            end
            -- Only announce if the window-skin engine is actually active for
            -- this user. If they disabled the BlizzardSkin addon entirely, the
            -- feature is already off -- stamp and hand off the conflict check.
            local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(BLIZZ_SKIN_FOLDER)
            if not loaded or not EllesmereUI.DisableAllBlizzWindowSkins then
                if EllesmereUIDB then EllesmereUIDB.windowSkinsIntroShown = true end
                ReleaseConflictCheck()
                return
            end
            ShowWindowSkinsPopup()
        end
        C_Timer.After(0.5, TryShow)
    end
end)
