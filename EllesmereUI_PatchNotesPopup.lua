-------------------------------------------------------------------------------
--  EllesmereUI_PatchNotesPopup.lua
--
--  One-time login popup that announces the new Patch Notes section to EXISTING
--  users (people who already had EllesmereUI installed before this version) so
--  they know to check it after updating. Offers a "View Patch Notes" button that
--  opens the options panel straight to the Patch Notes page.
--
--  NEW users never see it. The new-vs-existing guarantee mirrors
--  EllesmereUI_RaidFramesPopup.lua: at the parent ADDON_LOADED, EllesmereUIDB
--  still reflects ONLY the previous session's data, because child addons have
--  not initialized their per-profile DBs yet this session. So a profile that
--  already carries `addons` data can only have come from a prior version =
--  an existing/upgrade user. A nil DB, or a DB with no prior addon data, is a
--  fresh install: we stamp it at login so it never fires later either.
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.patchNotesIntroShown.
--  Defers behind the Raid Frames intro popup if that one is also pending (rare:
--  a user upgrading from pre-Raid-Frames straight to this build), so the two
--  never stack.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: the Patch Notes page is never registered in single-module
-- standalone builds, so the announcement is meaningless there. Deriving this
-- from the host addon name (the `...` vararg = real folder name) is
-- rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN

-------------------------------------------------------------------------------
--  Conflict-check handoff
--  For existing users the addon-conflict check auto-runs ~2s after load (gated
--  in EllesmereUI.lua on EllesmereUIDB.firstInstallPopupShown). We raise a
--  pending flag so that check defers while our popup is open, then trigger it
--  here on dismiss -- so the two popups never stack.
-------------------------------------------------------------------------------
local function ReleaseConflictCheck()
    EllesmereUI._patchNotesIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowPatchNotesPopup()
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local EG = ELLESMERE_GREEN
    local POPUP_W, POPUP_H = 470, 372
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    -- Dimmer (eats clicks; no close on outside click)
    local dimmer = CreateFrame("Frame", "EUIPatchNotesIntroDimmer", UIParent)
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
    local popup = CreateFrame("Frame", "EUIPatchNotesIntroPopup", dimmer)
    popup:SetScale(ppScale * 1.15)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PP.Size(popup, POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    -- 1 physical-pixel white border (alpha 0.15). Thickness is derived from the
    -- popup's effective scale (after the 1.15x SetScale above) so each edge stays
    -- exactly one physical pixel on screen. Four edge textures, snap disabled.
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

    -- Decorative mini patch-note cards (header visual) -- two little hero cards
    -- with a green top accent and stand-in text lines, previewing the real page.
    local CARD_W, CARD_H, CARD_GAP = 168, 52, 16
    local cardsW = 2 * CARD_W + CARD_GAP
    local cardsLeft = (POPUP_W - cardsW) / 2
    for i = 1, 2 do
        local card = CreateFrame("Frame", nil, popup)
        card:SetFrameLevel(popup:GetFrameLevel() + 1)
        PP.Size(card, CARD_W, CARD_H)
        PP.Point(card, "TOPLEFT", popup, "TOPLEFT", cardsLeft + (i - 1) * (CARD_W + CARD_GAP), -26)
        local cbg = card:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.12, 0.13, 0.15, 1)
        -- 2px green top accent, matching the real hero cards
        local accent = card:CreateTexture(nil, "ARTWORK")
        accent:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
        accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        accent:SetHeight(2)
        -- Title line (wider, brighter) then two dimmer body lines.
        local t1 = card:CreateTexture(nil, "ARTWORK")
        t1:SetColorTexture(1, 1, 1, 0.55)
        PP.Size(t1, CARD_W - 28, 6)
        PP.Point(t1, "TOPLEFT", card, "TOPLEFT", 14, -16)
        local t2 = card:CreateTexture(nil, "ARTWORK")
        t2:SetColorTexture(1, 1, 1, 0.22)
        PP.Size(t2, CARD_W - 56, 5)
        PP.Point(t2, "TOPLEFT", t1, "BOTTOMLEFT", 0, -9)
        local t3 = card:CreateTexture(nil, "ARTWORK")
        t3:SetColorTexture(1, 1, 1, 0.16)
        PP.Size(t3, CARD_W - 82, 5)
        PP.Point(t3, "TOPLEFT", t2, "BOTTOMLEFT", 0, -6)
        MakeBorder(card, 1, 1, 1, 0.10, PP)
    end

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -98)
    eyebrow:SetText("NEW")

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("Patch Notes")

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 15, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 80)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
    desc:SetText("Never miss an update again. The new Patch Notes section breaks down what's new each release, with quick links straight to every new setting.")

    -- Feature bullets
    local BULLETS = {
        "See the highlights from every new update",
        "Jump straight to any new setting in one click",
        "Catch up on anything you may have missed",
    }
    local prev
    for i, text in ipairs(BULLETS) do
        local bl = popup:CreateFontString(nil, "OVERLAY")
        bl:SetFont(FONT, 14, "")
        bl:SetTextColor(1, 1, 1, 0.72)
        bl:SetJustifyH("LEFT")
        if i == 1 then
            PP.Point(bl, "TOPLEFT", popup, "TOPLEFT", 92, -210)
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

    -- Stamp + close. view=true opens the options panel to the Patch Notes page.
    local function Finish(view)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.patchNotesIntroShown = true
        dimmer:Hide()
        ReleaseConflictCheck()
        if view then
            if InCombatLockdown() then
                EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat. Use /eui to view Patch Notes.")
                return
            end
            -- Patch Notes is its own sidebar module now (_EUIPatchNotes), not a
            -- page under Global Settings. Select that module directly so the
            -- sidebar highlights Patch Notes (mirrors the sidebar button OnClick).
            if EllesmereUI.SelectModule then
                EllesmereUI:Show()
                EllesmereUI:SelectModule("_EUIPatchNotes")
            end
        end
    end

    -- Bordered button matching the EUI style (primary = green, secondary = dim
    -- white that brightens on hover).
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
            brd:SetColor(r, g, b, secondary and 0.6 or 1)
        end)
        btn:SetScript("OnLeave", function()
            lbl:SetTextColor(r, g, b, secondary and 0.55 or 0.9)
            brd:SetColor(r, g, b, secondary and 0.35 or 0.9)
        end)
        return btn
    end

    -- Primary "View Patch Notes" on the left, secondary "Maybe Later" on the
    -- right, centered as a pair around the popup's bottom center.
    local viewBtn = MakeActionButton("View Patch Notes", EG.r, EG.g, EG.b, false)
    PP.Point(viewBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 40)
    viewBtn:SetScript("OnClick", function() Finish(true) end)

    local laterBtn = MakeActionButton("Maybe Later", 1, 1, 1, true)
    PP.Point(laterBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 40)
    laterBtn:SetScript("OnClick", function() Finish(false) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 80)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText("Open it anytime from the EUI Options Sidebar.")

    -- Escape = Maybe Later (the non-committal default). Consume Escape, propagate
    -- other keys so chat/UI shortcuts still work behind the dimmer.
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Finish(false) end
    end)

    dimmer:Show()
end

EllesmereUI.ShowPatchNotesIntroPopup = ShowPatchNotesPopup

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
    if EllesmereUIDB.patchNotesIntroShown then
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
    EllesmereUIDB.patchNotesIntroShown = true
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
            EllesmereUI._patchNotesIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" then
            -- Stamp brand-new users so the popup never fires in a later session.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.patchNotesIntroShown = true
            return
        end
        if _decision ~= "show" then return end
        local function TryShow()
            if EllesmereUIDB and EllesmereUIDB.patchNotesIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Defer behind the Raid Frames intro popup if it is still pending or
            -- open, so the two announcements never stack on a single login.
            if EllesmereUI._raidFramesIntroPending then
                C_Timer.After(0.4, TryShow)
                return
            end
            ShowPatchNotesPopup()
        end
        C_Timer.After(0.5, TryShow)
    end
end)
