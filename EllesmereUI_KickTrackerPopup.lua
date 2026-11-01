if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_KickTrackerPopup.lua
--
--  One-time login popup announcing the Kick Tracker (Mythic+ Tools: each
--  player's interrupt on the enemy they kicked, with its cooldown, and a bar
--  per group member) to EXISTING retail users -- people who already had
--  EllesmereUI installed before this version. The tracker ships off: "Turn It
--  On" switches it on at once (no reload) and opens its settings tab, "Maybe
--  Later" just closes. With the tracker already on, the primary button opens
--  the settings tab instead. A read-only link box carries the website's
--  interactive spotlight, selected as the popup opens so Ctrl+C copies it (the
--  video guides' link well).
--
--  NEW users never see it. The new-vs-existing guarantee mirrors the earlier
--  announcement popups: at the parent ADDON_LOADED, EllesmereUIDB still
--  reflects ONLY the previous session's data, because child addons have not
--  initialized their per-profile DBs yet this session. So a profile that
--  already carries `addons` data can only have come from a prior version = an
--  existing or upgrade user. A nil DB, or a DB with no prior addon data, is a
--  fresh install: we stamp it at login so it never fires later either.
--
--  WoW Forever never shows it (Mythic+ Tools is retail only, and login
--  announcements stay off there). On retail it waits, unstamped, for a login
--  where Mythic+ Tools is loaded with its settings ready.
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.kickTrackerIntroShown.
--  Only the newest announcement stays live: the Group Finder announcement
--  (EllesmereUI_GroupFinderPopup.lua) retired when this shipped, so users
--  upgrading across several versions never see two intro popups back to back.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: a single-module standalone build has no Kick Tracker story.
-- Deriving this from the host addon name (the `...` vararg) is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local MT_FOLDER = "EllesmereUIMythicTimer"
local MT_PAGE = "Kick Tracker"
local SPOTLIGHT_URL = "https://ellesmereui.com/spotlight-kick-tracker"

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
    EllesmereUI._kickTrackerIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-- Mythic+ Tools' namespace and the Kick Tracker's settings while the module is
-- loaded with its profile ready (it publishes the namespace at its own load and
-- its settings at its initialize, both before PLAYER_LOGIN), else nil.
local function KickTracker()
    if not C_AddOns.IsAddOnLoaded(MT_FOLDER) then return nil end
    local mt = EllesmereUI._ModuleNS[MT_FOLDER]
    local db = _G._EMT_AceDB
    local cfg = db and db.profile and db.profile.kickTracker
    if type(mt) ~= "table" or type(mt.KT_Refresh) ~= "function" or type(cfg) ~= "table" then return nil end
    return mt, cfg
end

-------------------------------------------------------------------------------
--  Header art: three mini panels, one per thing the tracker shows. Left, the
--  bars: a row per member in their class color, one draining on cooldown with
--  its seconds. Center (taller, accent edge), an enemy nameplate mid-cast with
--  two kick icons beside it, one ready and one counting down. Right, a marked
--  mob already carrying the icon of the player whose focus marker it wears.
--  The panels share a midline, like the earlier announcements' art.
-------------------------------------------------------------------------------
local BAR_ROWS = {
    { 0.25, 0.78, 0.92, 70, false }, -- mage, ready
    { 0.77, 0.12, 0.23, 44, true },  -- death knight, on cooldown
    { 0.96, 0.55, 0.73, 70, false }, -- paladin, ready
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

    -- A kick icon: a square with a thin edge, accent while ready, and a small
    -- countdown block while on cooldown.
    local function KickIcon(card, size, point, rel, relPoint, x, y, ready, alpha)
        local a = alpha or 1
        local edge = Block(card, "ARTWORK", ready and EG.r or 1, ready and EG.g or 1, ready and EG.b or 1,
            (ready and 0.9 or 0.3) * a, size, size, point, rel, relPoint, x, y)
        local face = Block(card, "ARTWORK", 0.33, 0.24, 0.14, a, size - 2, size - 2, "CENTER", edge, "CENTER", 0, 0)
        face:SetDrawLayer("ARTWORK", 1)
        if not ready then
            local shade = Block(card, "ARTWORK", 0, 0, 0, 0.45 * a, size - 2, size - 2, "CENTER", edge, "CENTER", 0, 0)
            shade:SetDrawLayer("ARTWORK", 2)
            local num = Block(card, "OVERLAY", 1, 1, 1, 0.8 * a, 4, 6, "CENTER", edge, "CENTER", 0, 0)
            num:SetDrawLayer("OVERLAY", 1)
        end
        return edge
    end

    -- Left: the bars.
    local left = MiniPanel(-(MID_W / 2 + GAP + SIDE_W / 2), SIDE_W, SIDE_H, false)
    for i, row in ipairs(BAR_ROWS) do
        local y = -10 - (i - 1) * 14
        local icon = Block(left, "ARTWORK", 0.33, 0.24, 0.14, 1, 9, 9, "TOPLEFT", left, "TOPLEFT", 10, y)
        Block(left, "ARTWORK", 1, 1, 1, 0.10, 82, 9, "LEFT", icon, "RIGHT", 4, 0)
        Block(left, "ARTWORK", row[1], row[2], row[3], 0.85, row[4], 9, "LEFT", icon, "RIGHT", 4, 0)
        if row[5] then
            Block(left, "OVERLAY", 1, 1, 1, 0.75, 7, 4, "RIGHT", icon, "RIGHT", 4 + 82 - 4, 0)
        end
    end

    -- Center: the nameplate.
    local mid = MiniPanel(0, MID_W, MID_H, true)
    Block(mid, "ARTWORK", 1, 1, 1, 0.45, 50, 4, "TOP", mid, "TOP", -22, -13)
    local hp = Block(mid, "ARTWORK", 0.22, 0.06, 0.06, 1, 96, 11, "TOPLEFT", mid, "TOPLEFT", 12, -24)
    Block(mid, "ARTWORK", 0.86, 0.16, 0.16, 1, 78, 11, "TOPLEFT", hp, "TOPLEFT", 0, 0)
    local cast = Block(mid, "ARTWORK", 1, 1, 1, 0.12, 96, 5, "TOPLEFT", hp, "BOTTOMLEFT", 0, -4)
    Block(mid, "ARTWORK", 1, 0.78, 0.30, 0.9, 58, 5, "TOPLEFT", cast, "TOPLEFT", 0, 0)
    local first = KickIcon(mid, 17, "LEFT", hp, "RIGHT", 7, -3, true)
    KickIcon(mid, 17, "LEFT", first, "RIGHT", 4, 0, false)

    -- Right: the marked mob, pre-marked with its kicker's icon.
    local right = MiniPanel(MID_W / 2 + GAP + SIDE_W / 2, SIDE_W, SIDE_H, false)
    local mark = Block(right, "ARTWORK", 0.0, 0.44, 0.87, 1, 10, 10, "TOPLEFT", right, "TOPLEFT", 14, -10)
    Block(right, "OVERLAY", 1, 1, 1, 0.35, 10, 1, "TOPLEFT", mark, "TOPLEFT", 0, 0)
    Block(right, "ARTWORK", 1, 1, 1, 0.45, 38, 4, "LEFT", mark, "RIGHT", 6, 0)
    local hp2 = Block(right, "ARTWORK", 0.22, 0.06, 0.06, 1, 66, 9, "TOPLEFT", right, "TOPLEFT", 14, -28)
    Block(right, "ARTWORK", 0.86, 0.16, 0.16, 1, 66, 9, "TOPLEFT", hp2, "TOPLEFT", 0, 0)
    KickIcon(right, 15, "LEFT", hp2, "RIGHT", 7, 0, true, 0.75)
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowKickTrackerPopup()
    local mt, cfg = KickTracker()
    if not (mt and cfg and PP and MakeBorder and EllesmereUI.ELLESMERE_GREEN) then
        ReleaseConflictCheck()
        return
    end
    local FONT = EllesmereUI._font or EllesmereUI.EXPRESSWAY
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    local EG = EllesmereUI.ELLESMERE_GREEN
    local isOn = cfg.enabled == true
    local POPUP_W, BLOCK_W = 500, 400
    -- Dimmer eats clicks (no close on outside click). Escape = Maybe Later.
    -- The height is set once the text is laid out (see the end).
    local Finish
    local dimmer, popup = EllesmereUI.BuildPopupShell("EUIKickTrackerIntro", {
        w = POPUP_W, h = 480, bump = 1.15,
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
    title:SetText(EllesmereUI.L("Nameplate Kick Tracker"))

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 14, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 90)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -10)
    desc:SetText(EllesmereUI.L("Your group's interrupts on the enemy nameplates themselves: who kicked what, who is ready next and where the next kick should land. It keeps working inside Mythic+ keys."))

    -- Feature bullets, a left-aligned list in a block centered under the text
    local BULLETS = {
        EllesmereUI.L("An icon with its cooldown beside the enemy each player kicked"),
        EllesmereUI.L("Marked mobs show their kicker's icon before the first kick lands"),
        EllesmereUI.L("A bar per group member with their kick's cooldown, read from their talents"),
    }
    local block = CreateFrame("Frame", nil, popup)
    PP.Size(block, BLOCK_W, 10)
    PP.Point(block, "TOP", desc, "BOTTOM", 0, -18)
    local prev, bulletFS = nil, {}
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
        bulletFS[i] = bl
        prev = bl
    end

    -- Link well: a read-only edit box holding the spotlight page's address,
    -- selected whenever it has focus, so Ctrl+C is the whole job. Typing,
    -- pasting or cutting puts the address back and selects it again. Placed
    -- under the bullets once the popup shows (below).
    local WELL_W, WELL_H = 350, 34
    local urlWell = CreateFrame("Frame", nil, popup)
    urlWell:SetFrameLevel(popup:GetFrameLevel() + 2)
    PP.Size(urlWell, WELL_W, WELL_H)
    local wbg = urlWell:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    wbg:SetColorTexture(0.045, 0.035, 0.027, 1)
    MakeBorder(urlWell, 1, 1, 1, 0.22, PP)

    local hint = popup:CreateFontString(nil, "OVERLAY")
    hint:SetFont(FONT, 11, "")
    hint:SetTextColor(1, 1, 1, 0.45)
    hint:SetWidth(POPUP_W - 90)
    hint:SetJustifyH("CENTER")
    PP.Point(hint, "TOP", urlWell, "BOTTOM", 0, -8)
    hint:SetText(EllesmereUI.L("Ctrl+C copies the link to the interactive feature spotlight"))

    local eb = CreateFrame("EditBox", nil, urlWell)
    eb:SetAllPoints(urlWell)
    eb:SetMultiLine(false)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT, 13, "")
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(12, 12, 0, 0)
    eb:SetTextColor(0.55, 0.75, 1.0, 1)
    eb._readOnly = SPOTLIGHT_URL
    eb:SetText(SPOTLIGHT_URL)
    eb:SetScript("OnMouseUp", function(self)
        C_Timer.After(0, function() self:SetFocus(); self:HighlightText() end)
    end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnChar", function(self)
        self:SetText(self._readOnly); self:HighlightText()
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(self._readOnly); self:HighlightText() end
    end)
    eb:SetScript("OnEscapePressed", function() Finish(false) end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            hint:SetText(EllesmereUI.L("Link copied - paste it into your browser"))
            hint:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        end
    end)

    -- Stamp + close. act = the primary button: turn the tracker on (at once,
    -- no reload) and open its settings tab, or open the tab when it is on
    -- already.
    Finish = function(act)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.kickTrackerIntroShown = true
        eb:ClearFocus()
        dimmer:Hide()
        ReleaseConflictCheck()
        if not act then return end
        if not isOn then
            cfg.enabled = true
            mt.KT_Refresh()
        end
        if InCombatLockdown() then
            EllesmereUI.PrintError(EllesmereUI.L("Cannot open options during combat. The Kick Tracker is under Mythic+ Tools in /eui."))
            return
        end
        -- Carries the options first-open split, so the page still lands when
        -- the panel builds next frame.
        EllesmereUI:NavigateToElementSettings(MT_FOLDER, MT_PAGE)
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
    footnote:SetText(isOn and EllesmereUI.L("The Kick Tracker is under Mythic+ Tools in /eui.")
        or EllesmereUI.L("Turning it on takes effect immediately, no reload needed. The Kick Tracker is under Mythic+ Tools in /eui."))

    dimmer:Show()

    -- Height from the laid-out text: header art and eyebrow (112), eyebrow,
    -- title and description with their gaps, the bullets, the link well and
    -- its hint, then the buttons and footnote (82) under a 28px gap. A hidden
    -- or never-rendered font string reports its unwrapped height (field report
    -- 2026-10-23: a profile whose font wraps the description and the bullets
    -- put the well and the buttons over the text), so the layout runs once
    -- shown and again a frame later, when the strings have rendered.
    local function Layout()
        local blockH = 0
        for i = 1, #bulletFS do
            blockH = blockH + math.ceil(bulletFS[i]:GetStringHeight() or 14) + ((i > 1) and 10 or 0)
        end
        PP.Point(urlWell, "TOP", block, "TOP", 0, -blockH - 18)
        local textH = math.ceil(eyebrow:GetStringHeight() or 13) + 6 + math.ceil(title:GetStringHeight() or 26)
            + 10 + math.ceil(desc:GetStringHeight() or 36)
        local wellH = 18 + WELL_H + 8 + math.ceil(hint:GetStringHeight() or 11)
        PP.Size(popup, POPUP_W, 112 + textH + 18 + blockH + wellH + 28 + 82)
    end
    Layout()
    -- Selected from the start: the popup is modal, so the keyboard has nowhere
    -- else to be, and Ctrl+C copies the link without a click.
    C_Timer.After(0, function()
        if not dimmer:IsShown() then return end
        Layout()
        eb:SetFocus(); eb:HighlightText()
    end)
end

EllesmereUI.ShowKickTrackerIntroPopup = ShowKickTrackerPopup

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
    if EllesmereUIDB.kickTrackerIntroShown then
        return "done"
    end
    -- The style picker is due this login (the session after the module
    -- picker): still a fresh install.
    if EllesmereUIDB.styleChoicePending then
        EllesmereUIDB.kickTrackerIntroShown = true
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
    EllesmereUIDB.kickTrackerIntroShown = true
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
            EllesmereUI._kickTrackerIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" or EllesmereUI._firstInstallPending then
            -- Stamp brand-new users so the popup never fires in a later
            -- session. The picker's pending flag is the authority on "fresh",
            -- so a decision reached ahead of it still stands down here.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.kickTrackerIntroShown = true
            if EllesmereUI._kickTrackerIntroPending then ReleaseConflictCheck() end
            return
        end
        if _decision ~= "show" then return end
        local function TryShow()
            if EllesmereUIDB and EllesmereUIDB.kickTrackerIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Defer behind any older login announcement still pending or open
            -- (all retired today; the chain holds again if one is revived).
            if EllesmereUI._styleLaunchIntroPending or EllesmereUI._launchVideoIntroPending
               or EllesmereUI._groupFinderIntroPending then
                C_Timer.After(0.4, TryShow)
                return
            end
            -- Only while Mythic+ Tools is loaded with its settings ready;
            -- otherwise wait, unstamped, for a later login.
            if not KickTracker() then
                ReleaseConflictCheck()
                return
            end
            ShowKickTrackerPopup()
        end
        -- Shown once the loading screen is down: text built behind it is never
        -- laid out, so a popup shown 0.5 s after PLAYER_LOGIN on a login that
        -- outlasts that (a profile with more modules on) measured its lines
        -- unwrapped and drew the well and buttons over them (field report
        -- 2026-10-23). The 8 s fallback covers a client that never reports it.
        local function Go()
            if self._go == nil then return end
            self._go = nil
            self:UnregisterEvent("LOADING_SCREEN_DISABLED")
            C_Timer.After(0.5, TryShow)
        end
        self._go = Go
        self:RegisterEvent("LOADING_SCREEN_DISABLED")
        C_Timer.After(8, Go)
    elseif event == "LOADING_SCREEN_DISABLED" then
        if self._go then self._go() end
    end
end)

-------------------------------------------------------------------------------
--  Reset command: clears the one-time stamp so the announcement fires again
--  on the next /reload (testing aid, same as the earlier intro popups).
-------------------------------------------------------------------------------
SLASH_EUIKTINTRO1 = "/euiktintro"
SlashCmdList["EUIKTINTRO"] = function()
    if EllesmereUIDB then EllesmereUIDB.kickTrackerIntroShown = nil end
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r Kick Tracker announcement reset. It fires on your next /reload.")
end
