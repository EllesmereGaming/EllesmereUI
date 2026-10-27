if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_GroupFinderPopup.lua
--
--  One-time login popup announcing the Group Finder module (Premade Groups
--  filters, group listings with specs and leader ratings, the M+ applications
--  bar) to EXISTING retail users --
--  people who already had EllesmereUI installed before this version. The module
--  ships off: "Turn It On" saves its account-wide switch and reloads (its hooks
--  install at load), "Maybe Later" just closes. With the module already on, the
--  primary button opens its settings page instead.
--
--  NEW users never see it. The new-vs-existing guarantee mirrors the earlier
--  announcement popups: at the parent ADDON_LOADED, EllesmereUIDB still
--  reflects ONLY the previous session's data, because child addons have not
--  initialized their per-profile DBs yet this session. So a profile that
--  already carries `addons` data can only have come from a prior version = an
--  existing or upgrade user. A nil DB, or a DB with no prior addon data, is a
--  fresh install: we stamp it at login so it never fires later either.
--
--  WoW Forever never shows it (the module is retail only, and login
--  announcements stay off there). On retail it waits, unstamped, for a login
--  where the module is loaded and free to turn on (Group Finder's ns.Blocked:
--  another premade groups filter that hooks the same panel is loaded).
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.groupFinderIntroShown.
--  Only the newest announcement stays live: the looks announcement
--  (EllesmereUI_StyleLaunchPopup.lua) retired when this shipped, so users
--  upgrading across several versions never see two intro popups back to back.
--
--  RETIRED 2026-10-23: superseded by the Kick Tracker announcement
--  (EllesmereUI_KickTrackerPopup.lua); killed at the top so only the newest
--  announcement fires. Everything below is inert -- loader, popup, reset
--  command and DB stamping all dead; groupFinderIntroShown is no longer
--  written for anyone. Delete the guard below to revive the popup.
-------------------------------------------------------------------------------
do return end

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: a single-module standalone build has no Group Finder story.
-- Deriving this from the host addon name (the `...` vararg) is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local GF_FOLDER = "EllesmereUIGroupFinder"
local GF_PAGE = "Premade Search"

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
    EllesmereUI._groupFinderIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-- Group Finder's namespace while the module is loaded (it publishes it at its
-- own load, before PLAYER_LOGIN), else nil.
local function GroupFinderNS()
    if not C_AddOns.IsAddOnLoaded(GF_FOLDER) then return nil end
    local gf = EllesmereUI._ModuleNS[GF_FOLDER]
    if type(gf) ~= "table" or type(gf.SetEnabled) ~= "function" then return nil end
    return gf
end

-------------------------------------------------------------------------------
--  Header art: three mini panels, one per thing the module adds. Left, the
--  filter menu with two picks ticked; center (taller, accent edge), the group
--  list: each row a leader rating, a name line and five spec dots in class
--  colors, the middle row faded as a group that misses the filters; right, the
--  M+ applications bar in the module's own colors (accepted, declined,
--  delisted, cancelled). The panels share a midline, like the earlier
--  announcements' art.
-------------------------------------------------------------------------------
local CLASS_DOTS = {
    { 0.96, 0.55, 0.73 }, { 0.25, 0.78, 0.92 }, { 1.00, 0.96, 0.41 }, { 0.67, 0.83, 0.45 },
    { 0.53, 0.53, 0.93 }, { 0.77, 0.12, 0.23 }, { 1.00, 0.49, 0.04 }, { 0.00, 0.44, 0.87 },
    { 0.20, 0.58, 0.50 }, { 1.00, 1.00, 1.00 },
}
local ROW_DOTS = { { 1, 2, 3, 4, 5 }, { 6, 7, 8, 9, 10 }, { 7, 8, 10, 3, 6 } }
local ROW_RATING = { { 1.00, 0.50, 0.00 }, { 0.64, 0.21, 0.93 }, { 0.00, 0.44, 0.87 } }
local APP_SEGS = {
    { 0.35, 0.85, 0.40, 36 }, { 0.95, 0.30, 0.30, 22 }, { 1.00, 0.60, 0.20, 14 }, { 0.55, 0.55, 0.55, 12 },
}

local function BuildHeaderArt(popup, EG)
    local MIDLINE = -56
    local SIDE_W, SIDE_H, MID_W, MID_H, GAP = 118, 56, 158, 70, 14

    local function MiniPanel(x, w, h, accent)
        local card = CreateFrame("Frame", nil, popup)
        card:SetFrameLevel(popup:GetFrameLevel() + 1)
        PP.Size(card, w, h)
        PP.Point(card, "CENTER", popup, "TOP", x, MIDLINE)
        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.121, 0.113, 0.106, 1)
        if accent then
            local edge = card:CreateTexture(nil, "ARTWORK", nil, 7)
            edge:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
            PP.Point(edge, "TOPLEFT", card, "TOPLEFT", 1, -1)
            PP.Point(edge, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
            edge:SetHeight(2)
        end
        MakeBorder(card, 1, 1, 1, accent and 0.16 or 0.10, PP)
        return card
    end

    local function Block(card, layer, r, g, b, a, w, h, point, rel, relPoint, x, y)
        local t = card:CreateTexture(nil, layer)
        t:SetColorTexture(r, g, b, a)
        PP.Size(t, w, h)
        PP.Point(t, point, rel, relPoint, x, y)
        return t
    end

    -- Left: the filter menu.
    local left = MiniPanel(-(MID_W / 2 + GAP + SIDE_W / 2), SIDE_W, SIDE_H, false)
    for i = 1, 3 do
        local on = i ~= 3
        local box
        if on then
            box = Block(left, "ARTWORK", EG.r, EG.g, EG.b, 0.9, 7, 7, "TOPLEFT", left, "TOPLEFT", 12, -12 - (i - 1) * 14)
        else
            box = Block(left, "ARTWORK", 1, 1, 1, 0.22, 7, 7, "TOPLEFT", left, "TOPLEFT", 12, -12 - (i - 1) * 14)
        end
        Block(left, "ARTWORK", 1, 1, 1, on and 0.34 or 0.16, SIDE_W - 44 - (i - 1) * 12, 4, "LEFT", box, "RIGHT", 8, 0)
    end

    -- Center: the group list.
    local mid = MiniPanel(0, MID_W, MID_H, true)
    for row = 1, 3 do
        local y = -14 - (row - 1) * 17
        local fade = (row == 2) and 0.25 or 1
        local rc = ROW_RATING[row]
        local chip = Block(mid, "ARTWORK", rc[1], rc[2], rc[3], 0.85 * fade, 14, 7, "TOPLEFT", mid, "TOPLEFT", 10, y)
        Block(mid, "ARTWORK", 1, 1, 1, 0.36 * fade, (row == 3) and 40 or 52, 4, "LEFT", chip, "RIGHT", 7, 0)
        for d = 1, 5 do
            local c = CLASS_DOTS[ROW_DOTS[row][d]]
            Block(mid, "OVERLAY", c[1], c[2], c[3], 0.95 * fade, 6, 6, "TOPRIGHT", mid, "TOPRIGHT", -10 - (5 - d) * 9, y)
        end
    end

    -- Right: the M+ applications bar.
    local right = MiniPanel(MID_W / 2 + GAP + SIDE_W / 2, SIDE_W, SIDE_H, false)
    local x = 12
    for i = 1, #APP_SEGS do
        local s = APP_SEGS[i]
        Block(right, "ARTWORK", s[1], s[2], s[3], 0.9, s[4], 9, "TOPLEFT", right, "TOPLEFT", x, -14)
        x = x + s[4] + 2
    end
    Block(right, "ARTWORK", 1, 1, 1, 0.30, 70, 4, "TOPLEFT", right, "TOPLEFT", 12, -32)
    Block(right, "ARTWORK", 1, 1, 1, 0.16, 48, 4, "TOPLEFT", right, "TOPLEFT", 12, -42)
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowGroupFinderPopup()
    local gf = GroupFinderNS()
    if not (gf and PP and MakeBorder and EllesmereUI.ELLESMERE_GREEN) then
        ReleaseConflictCheck()
        return
    end
    local FONT = EllesmereUI._font or EllesmereUI.EXPRESSWAY
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    local EG = EllesmereUI.ELLESMERE_GREEN
    local isOn = gf.Enabled() == true
    local POPUP_W, BLOCK_W = 500, 400
    -- Dimmer eats clicks (no close on outside click). Escape = Maybe Later.
    -- The height is set once the text is laid out (see the end).
    local Finish
    local dimmer, popup = EllesmereUI.BuildPopupShell("EUIGroupFinderIntro", {
        w = POPUP_W, h = 420, bump = 1.15,
        onEscape = function() Finish(false) end,
    })

    BuildHeaderArt(popup, EG)

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -112)
    eyebrow:SetText(EllesmereUI.L("NEW IN ELLESMEREUI"))

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText(EllesmereUI.L("Group Finder"))

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 14, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 90)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -10)
    desc:SetText(EllesmereUI.L("A better group finder: narrow the list down to the groups you want and see who is in each one, right in the Dungeons & Raids window."))

    -- Feature bullets, a left-aligned list in a block centered under the text
    local BULLETS = {
        EllesmereUI.L("Filter groups by dungeon, delve, raid boss, role and rating"),
        EllesmereUI.L("See each group's specs and leader rating at a glance"),
        EllesmereUI.L("Count your Mythic+ applications and how they ended"),
    }
    local block = CreateFrame("Frame", nil, popup)
    PP.Size(block, BLOCK_W, 10)
    PP.Point(block, "TOP", desc, "BOTTOM", 0, -18)
    local prev, blockH = nil, 0
    for i, text in ipairs(BULLETS) do
        local bl = popup:CreateFontString(nil, "OVERLAY")
        bl:SetFont(FONT, 14, "")
        bl:SetTextColor(1, 1, 1, 0.72)
        bl:SetJustifyH("LEFT")
        bl:SetWidth(BLOCK_W - 16)
        bl:SetWordWrap(true)
        if i == 1 then
            PP.Point(bl, "TOPLEFT", block, "TOPLEFT", 16, 0)
        else
            PP.Point(bl, "TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
        end
        bl:SetText(text)
        local dot = popup:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(EG.r, EG.g, EG.b, 1)
        PP.Size(dot, 5, 5)
        PP.Point(dot, "TOPRIGHT", bl, "TOPLEFT", -10, -5)
        blockH = blockH + math.ceil(bl:GetStringHeight() or 14) + ((i > 1) and 10 or 0)
        prev = bl
    end

    -- Stamp + close. act = the primary button: turn the module on (the reload
    -- first, then the switch as its pre-reload work), or open its settings
    -- when it is on already.
    Finish = function(act)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.groupFinderIntroShown = true
        if act and not isOn then
            EllesmereUI.RequestReload(nil, nil, function() gf.SetEnabled(true) end)
            return
        end
        dimmer:Hide()
        ReleaseConflictCheck()
        if not act then return end
        if InCombatLockdown() then
            EllesmereUI.PrintError(EllesmereUI.L("Cannot open options during combat. Group Finder is under UI Reskin Addons in /eui."))
            return
        end
        -- Carries the options first-open split, so the page still lands when
        -- the panel builds next frame.
        EllesmereUI:NavigateToElementSettings(GF_FOLDER, GF_PAGE)
    end

    -- Primary on the left, secondary on the right, centered as a pair around
    -- the popup's bottom center.
    local BTN_W, BTN_GAP = 190, 14
    local mainBtn = EllesmereUI.MakeActionButton(popup, FONT, isOn and EllesmereUI.L("Open Settings") or EllesmereUI.L("Turn It On"),
        EG.r, EG.g, EG.b, { w = BTN_W })
    PP.Point(mainBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 44)
    mainBtn:SetScript("OnClick", function() Finish(true) end)

    local laterBtn = EllesmereUI.MakeActionButton(popup, FONT, isOn and EllesmereUI.L("Got It") or EllesmereUI.L("Maybe Later"),
        1, 1, 1, { w = BTN_W, secondary = true, hoverA = 0.8 })
    PP.Point(laterBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 44)
    laterBtn:SetScript("OnClick", function() Finish(false) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 90)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText(isOn and EllesmereUI.L("Group Finder is under UI Reskin Addons in /eui.")
        or EllesmereUI.L("Turning it on reloads your UI. Group Finder is under UI Reskin Addons in /eui."))

    -- Height from the laid-out text: header art and eyebrow (112), eyebrow,
    -- title and description with their gaps, the bullets, then the buttons and
    -- footnote (82) under a 28px gap. A translation that wraps more grows it.
    local textH = math.ceil(eyebrow:GetStringHeight() or 13) + 6 + math.ceil(title:GetStringHeight() or 26)
        + 10 + math.ceil(desc:GetStringHeight() or 36)
    PP.Size(popup, POPUP_W, 112 + textH + 18 + blockH + 28 + 82)

    dimmer:Show()
end

EllesmereUI.ShowGroupFinderIntroPopup = ShowGroupFinderPopup

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
    if EllesmereUIDB.groupFinderIntroShown then
        return "done"
    end
    -- The style picker is due this login (the session after the module
    -- picker): still a fresh install.
    if EllesmereUIDB.styleChoicePending then
        EllesmereUIDB.groupFinderIntroShown = true
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
    EllesmereUIDB.groupFinderIntroShown = true
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
            EllesmereUI._groupFinderIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" or EllesmereUI._firstInstallPending then
            -- Stamp brand-new users so the popup never fires in a later
            -- session. The picker's pending flag is the authority on "fresh",
            -- so a decision reached ahead of it still stands down here.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.groupFinderIntroShown = true
            if EllesmereUI._groupFinderIntroPending then ReleaseConflictCheck() end
            return
        end
        if _decision ~= "show" then return end
        local function TryShow()
            if EllesmereUIDB and EllesmereUIDB.groupFinderIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Defer behind any older login announcement still pending or open
            -- (all retired today; the chain holds again if one is revived).
            if EllesmereUI._styleLaunchIntroPending or EllesmereUI._launchVideoIntroPending then
                C_Timer.After(0.4, TryShow)
                return
            end
            -- Only while the module is loaded and free to turn on; otherwise
            -- wait, unstamped, for a later login.
            local gf = GroupFinderNS()
            if not gf or gf.Blocked() then
                ReleaseConflictCheck()
                return
            end
            ShowGroupFinderPopup()
        end
        C_Timer.After(0.5, TryShow)
    end
end)

-------------------------------------------------------------------------------
--  Reset command: clears the one-time stamp so the announcement fires again
--  on the next /reload (testing aid, same as the earlier intro popups).
-------------------------------------------------------------------------------
SLASH_EUIGFINTRO1 = "/euigfintro"
SlashCmdList["EUIGFINTRO"] = function()
    if EllesmereUIDB then EllesmereUIDB.groupFinderIntroShown = nil end
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r Group Finder announcement reset. It fires on your next /reload.")
end
