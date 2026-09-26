if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SpecOverridesPopup.lua
--
--  One-time login popup announcing the Settings Overrides system (spec
--  groups + conditional overrides) to EXISTING users (people who already had
--  EllesmereUI installed before this version). "Show Me" opens the user's
--  first loaded CORE module and pulses the overrides glyph on its toolbar.
--  Users with no core module loaded are skipped entirely (stamped silently).
--
--  NEW users never see it. The new-vs-existing guarantee mirrors
--  EllesmereUI_WindowSkinsPopup.lua: at the parent ADDON_LOADED, EllesmereUIDB
--  still reflects ONLY the previous session's data, because child addons have
--  not initialized their per-profile DBs yet this session. So a profile that
--  already carries `addons` data can only have come from a prior version =
--  an existing/upgrade user. A nil DB, or a DB with no prior addon data, is a
--  fresh install: we stamp it at login so it never fires later either.
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.specOverridesIntroShown.
--  Defers behind the Raid Frames, Patch Notes, and Window Skins intro popups
--  if any is also pending (a user upgrading across several versions at once),
--  so the announcements never stack on a single login.
--
--  RETIRED 2026-08-11: superseded by the 12.1 launch video announcement
--  (EllesmereUI_VideoGuides.lua, guide "midnight_121") -- only the newest
--  announcement fires, so users upgrading across versions are never shown
--  several intro popups back to back. Everything below is inert; the
--  Settings Overrides video itself stays reachable via the override glyph's
--  first-click guide. Delete the guard below to revive this popup.
-------------------------------------------------------------------------------
do return end

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: the override system ships in the parent but is pointless in a
-- single-module standalone build (no Profiles & Presets surface). Deriving
-- this from the host addon name (the `...` vararg) is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN

-- The override system's gold (editing-session accent), matching the golden
-- setting borders and the gold unlock-mode variant.
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0.30

-- Modern class-icon sprite (same sheet the override cards use) plus the
-- conditional-override icons (battleground = horde, dungeons).
local MODERN_SPRITE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\modern.tga"
local CLASS_COORDS = {
    WARRIOR={0,0.125,0,0.125}, DRUID={0.375,0.5,0,0.125},
    SHAMAN={0.125,0.25,0.125,0.25}, PRIEST={0.25,0.375,0.125,0.25},
    PALADIN={0,0.125,0.25,0.375}, DEATHKNIGHT={0.125,0.25,0.25,0.375},
}
local OVERRIDE_ICON_DIR = "Interface\\AddOns\\EllesmereUI\\media\\icons\\overrides\\"

-- "Show Me" lands on the user's first loaded CORE module (sidebar core
-- section order) -- that's where the overrides glyph lives and where the
-- system is actually used. Users with NO core addon loaded never see the
-- popup at all (nothing to demonstrate on).
local CORE_ADDONS = {
    "EllesmereUIActionBars", "EllesmereUINameplates", "EllesmereUIUnitFrames",
    "EllesmereUICooldownManager", "EllesmereUIResourceBars", "EllesmereUIRaidFrames",
}
local function FirstLoadedCoreModule()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return nil end
    for _, folder in ipairs(CORE_ADDONS) do
        if C_AddOns.IsAddOnLoaded(folder) then return folder end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Conflict-check handoff
--  For existing users the addon-conflict check auto-runs ~2s after load (gated
--  in EllesmereUI.lua on EllesmereUIDB.firstInstallPopupShown). We raise a
--  pending flag so that check defers while our popup is open, then trigger it
--  here on dismiss -- so the two popups never stack.
-------------------------------------------------------------------------------
local function ReleaseConflictCheck()
    EllesmereUI._specOvIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowSpecOverridesPopup()
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local EG = ELLESMERE_GREEN
    local POPUP_W, POPUP_H = 470, 384
    -- Dimmer eats clicks (no close on outside click). Escape = Got It.
    local Finish
    local dimmer, popup = EllesmereUI.BuildPopupShell("EUISpecOvIntro", {
        w = POPUP_W, h = POPUP_H, bump = 1.15,
        onEscape = function() Finish(false) end,
    })

    -- Decorative header visual: two mini override-group cards, mimicking the
    -- overrides dropdown. Left = a SPEC group (tank class glyphs) glowing
    -- GOLD (the editing accent); right = a CONDITIONAL group (battleground +
    -- dungeon icons) sitting idle. Both systems in one glance.
    local CARD_W, CARD_H, CARD_GAP = 158, 56, 18
    local MIDLINE = -54
    local groups = {
        { classes = { "WARRIOR", "PALADIN", "DEATHKNIGHT" }, gold = true },
        { icons = { "override-horde.png", "override-dungeons.png" }, gold = false },
    }
    for i, g in ipairs(groups) do
        local card = CreateFrame("Frame", nil, popup)
        card:SetFrameLevel(popup:GetFrameLevel() + 1)
        PP.Size(card, CARD_W, CARD_H)
        PP.Point(card, "CENTER", popup, "TOP",
            (i - 1.5) * (CARD_W + CARD_GAP), MIDLINE)
        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.12, 0.13, 0.15, 1)

        -- Icon row, centered: class glyphs (spec card) or conditional icons.
        local ICON = 24
        local list = g.classes or g.icons
        local n = #list
        local rowW = n * ICON + (n - 1) * 8
        for k, entry in ipairs(list) do
            local tex = card:CreateTexture(nil, "ARTWORK")
            PP.Size(tex, ICON, ICON)
            PP.Point(tex, "LEFT", card, "LEFT",
                (CARD_W - rowW) / 2 + (k - 1) * (ICON + 8), 6)
            if g.classes then
                tex:SetTexture(MODERN_SPRITE)
                local c = CLASS_COORDS[entry]
                if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
            else
                tex:SetTexture(OVERRIDE_ICON_DIR .. entry)
            end
            if not g.gold then tex:SetAlpha(0.65) end
        end

        -- Stand-in name line under the icons; the gold card's line carries
        -- the accent (the "currently editing" read).
        local line = card:CreateTexture(nil, "ARTWORK")
        if g.gold then
            line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.75)
        else
            line:SetColorTexture(1, 1, 1, 0.20)
        end
        PP.Size(line, 64, 4)
        PP.Point(line, "BOTTOM", card, "BOTTOM", 0, 7)

        if g.gold then
            MakeBorder(card, GOLD_R, GOLD_G, GOLD_B, 0.85, PP)
        else
            MakeBorder(card, 1, 1, 1, 0.10, PP)
        end
    end

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -104)
    eyebrow:SetText("NEW SYSTEM")

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 25, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("Settings Overrides")

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 15, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 80)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
    desc:SetText("Override any setting for a group of specs, or for the content you're in. Everything else keeps your normal profile settings.")

    -- Feature bullets
    local BULLETS = {
        "Spec groups: Edit once, apply to every spec in the group",
        "Conditionals: Keybind, Dungeon, Raid, Arena, BG, Solo",
        "Custom Unlock Mode layouts and Buff Managers per group",
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

    -- Stamp + close. showMe=true opens the user's first loaded CORE module
    -- (the overrides glyph lives on its toolbar) and pulses that glyph so
    -- the entry point is unmissable on arrival.
    Finish = function(showMe)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.specOverridesIntroShown = true
        dimmer:Hide()
        ReleaseConflictCheck()
        if not showMe then return end
        local target = FirstLoadedCoreModule()
        if target and EllesmereUI.ShowModule then
            -- ShowModule, not Show + SelectModule: it carries the first-open
            -- split, so the module still lands when the panel builds next frame.
            EllesmereUI:ShowModule(target)
            -- Next frame: the toolbar glyph exists once the panel has built.
            C_Timer.After(0, function()
                if EllesmereUI.SpecOverrides_PulseButton then
                    EllesmereUI.SpecOverrides_PulseButton()
                end
            end)
        elseif EllesmereUI.NavigateToElementSettings then
            -- No core module loaded (race with the show-gate): fall back to
            -- the management tab.
            EllesmereUI:NavigateToElementSettings("_EUIProfiles", "Overrides")
        end
    end

    -- Primary "Show Me" on the left, secondary "Got It" on the right,
    -- centered as a pair around the popup's bottom center.
    local BTN_W, BTN_GAP = 184, 14
    local showBtn = EllesmereUI.MakeActionButton(popup, FONT, "Show Me", EG.r, EG.g, EG.b, { w = BTN_W })
    PP.Point(showBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 40)
    showBtn:SetScript("OnClick", function() Finish(true) end)

    local gotBtn = EllesmereUI.MakeActionButton(popup, FONT, "Got It", 1, 1, 1, { w = BTN_W, secondary = true, hoverA = 0.8 })
    PP.Point(gotBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 40)
    gotBtn:SetScript("OnClick", function() Finish(false) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 80)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText("Find it anytime: the class glyph beside the module search bar.")

    dimmer:Show()
end

EllesmereUI.ShowSpecOverridesIntroPopup = ShowSpecOverridesPopup

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
    if EllesmereUIDB.specOverridesIntroShown then
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
    EllesmereUIDB.specOverridesIntroShown = true
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
            EllesmereUI._specOvIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" then
            -- Stamp brand-new users so the popup never fires in a later session.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.specOverridesIntroShown = true
            return
        end
        if _decision ~= "show" then return end
        local function TryShow()
            if EllesmereUIDB and EllesmereUIDB.specOverridesIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Defer behind the older intro popups if any is still pending or
            -- open, so announcements never stack on a single login.
            if EllesmereUI._raidFramesIntroPending
               or EllesmereUI._patchNotesIntroPending
               or EllesmereUI._windowSkinsIntroPending then
                C_Timer.After(0.4, TryShow)
                return
            end
            -- Only announce if the override system is actually present AND
            -- the user runs at least one core module (no core addons = no
            -- surface to demonstrate the system on; skip them entirely).
            if not EllesmereUI.SpecOverrides_ToggleCardsPopup
               or not FirstLoadedCoreModule() then
                if EllesmereUIDB then EllesmereUIDB.specOverridesIntroShown = true end
                ReleaseConflictCheck()
                return
            end
            ShowSpecOverridesPopup()
        end
        C_Timer.After(0.5, TryShow)
    end
end)

-------------------------------------------------------------------------------
--  Reset command: clears the one-time stamps for BOTH override onboarding
--  surfaces so each fires again through its natural trigger -- the login
--  announcement on the next /reload, and the Settings Overrides video guide
--  on the next click of the overrides toolbar glyph.
-------------------------------------------------------------------------------
SLASH_EUIOVERRIDESINTRO1 = "/euioverridesintro"
SlashCmdList["EUIOVERRIDESINTRO"] = function()
    if EllesmereUIDB then
        EllesmereUIDB.specOverridesIntroShown = nil
        if EllesmereUIDB.videoGuidesSeen then
            EllesmereUIDB.videoGuidesSeen.settings_overrides = nil
        end
    end
    print("|cff00ff98EllesmereUI:|r Overrides intro reset. The announcement popup fires on your next /reload; the video guide fires on your next click of the overrides glyph.")
end
