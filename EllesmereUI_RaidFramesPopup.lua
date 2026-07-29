-------------------------------------------------------------------------------
--  EllesmereUI_RaidFramesPopup.lua
--
--  One-time login popup that announces the Raid Frames module to EXISTING
--  users (people who already had EllesmereUI installed before this version) and
--  lets them disable it on the spot -- the same disable path as the sidebar
--  power button (C_AddOns.DisableAddOn + ReloadUI).
--
--  NEW users never see it. The new-vs-existing guarantee mirrors
--  EllesmereUI_FirstInstall.lua: at the parent ADDON_LOADED, EllesmereUIDB
--  still reflects ONLY the previous session's data, because child addons have
--  not initialized their per-profile DBs yet this session. So a profile that
--  already carries `addons` data can only have come from a prior version =
--  an existing/upgrade user. A nil DB, or a DB with no prior addon data, is a
--  fresh install: we stamp it at login so it never fires later either (this
--  also stops a brand-new user's SECOND login from looking "existing").
--
--  Fires once, at PLAYER_LOGIN. Guarded by EllesmereUIDB.raidFramesIntroShown.
--
--  RETIRED 2026-07-12: announcement has had its run; killed at the top so
--  users upgrading across versions are never shown several intro popups back
--  to back (only the newest announcement fires). Everything below is inert --
--  loader, art, and DB stamping all dead; raidFramesIntroShown is no longer
--  written for anyone. Delete the guard below to revive the popup.
-------------------------------------------------------------------------------
do return end

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: a single-module standalone build either IS Raid Frames or does
-- not ship it, so the announcement is meaningless there. Deriving this from the
-- host addon name (the `...` vararg = real folder name) is rename-immune.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local RF_FOLDER = "EllesmereUIRaidFrames"

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
    EllesmereUI._raidFramesIntroPending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-------------------------------------------------------------------------------
--  The popup
-------------------------------------------------------------------------------
local function ShowRaidFramesPopup()
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local EG = ELLESMERE_GREEN
    local POPUP_W, POPUP_H = 470, 366
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    -- Dimmer (eats clicks; no close on outside click)
    local dimmer = CreateFrame("Frame", "EUIRaidFramesIntroDimmer", UIParent)
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
    local popup = CreateFrame("Frame", "EUIRaidFramesIntroPopup", dimmer)
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
    -- popup's effective scale (after the 1.2x SetScale above) so each edge stays
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

    -- Decorative mini raid-frame grid (header visual) -- five little health bars
    local GRID_COLS = 5
    local CELL_W, CELL_H, CELL_GAP = 30, 22, 8
    local gridW = GRID_COLS * CELL_W + (GRID_COLS - 1) * CELL_GAP
    local cellColors = {
        { 0.20, 0.82, 0.33 }, { 0.25, 0.50, 0.90 }, { 0.64, 0.39, 0.93 },
        { 0.96, 0.78, 0.30 }, { 0.30, 0.78, 0.78 },
    }
    local cellFills = { 0.80, 0.60, 0.88, 0.52, 0.72 }
    local gridLeft = (POPUP_W - gridW) / 2
    for i = 1, GRID_COLS do
        local cell = CreateFrame("Frame", nil, popup)
        cell:SetFrameLevel(popup:GetFrameLevel() + 1)
        PP.Size(cell, CELL_W, CELL_H)
        PP.Point(cell, "TOPLEFT", popup, "TOPLEFT", gridLeft + (i - 1) * (CELL_W + CELL_GAP), -28)
        local cbg = cell:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.12, 0.13, 0.15, 1)
        local c = cellColors[i]
        local fill = cell:CreateTexture(nil, "ARTWORK")
        fill:SetColorTexture(c[1], c[2], c[3], 0.9)
        fill:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 1, 1)
        fill:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
        fill:SetHeight((CELL_H - 2) * cellFills[i])
        MakeBorder(cell, 1, 1, 1, 0.10, PP)
    end

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -64)
    eyebrow:SetText("NEW FEATURE")

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("Raid Frames")

    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 15, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 80)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
    desc:SetText("EllesmereUI Raid Frames are here! Clean, fully customizable, and built for performance.")

    -- Feature bullets
    local BULLETS = {
        "Custom buff tracking, layouts, colors and borders",
        "Dispel, defensive and private aura tracking",
        "Full mouseover cast binding suite",
        "Top of the line performance metrics",
    }
    local prev
    for i, text in ipairs(BULLETS) do
        local bl = popup:CreateFontString(nil, "OVERLAY")
        bl:SetFont(FONT, 14, "")
        bl:SetTextColor(1, 1, 1, 0.72)
        bl:SetJustifyH("LEFT")
        if i == 1 then
            PP.Point(bl, "TOPLEFT", popup, "TOPLEFT", 92, -178)
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

    -- Stamp + close. disable=true follows the exact sidebar power-button path.
    local function Finish(disable)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.raidFramesIntroShown = true
        if disable then
            if C_AddOns and C_AddOns.DisableAddOn then
                C_AddOns.DisableAddOn(RF_FOLDER)
            end
            ReloadUI()
            return
        end
        dimmer:Hide()
        ReleaseConflictCheck()
    end

    -- Bordered button matching the EUI style (primary = green, secondary = dim
    -- white that warms to the power-button red on hover).
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
            if secondary then
                lbl:SetTextColor(DISABLE_R, DISABLE_G, DISABLE_B, 1)
                brd:SetColor(DISABLE_R, DISABLE_G, DISABLE_B, 0.95)
            else
                lbl:SetTextColor(r, g, b, 1)
                brd:SetColor(r, g, b, 1)
            end
        end)
        btn:SetScript("OnLeave", function()
            lbl:SetTextColor(r, g, b, secondary and 0.55 or 0.9)
            brd:SetColor(r, g, b, secondary and 0.35 or 0.9)
        end)
        return btn
    end

    -- Primary "Keep" on the left, secondary "Disable" on the right, centered
    -- as a pair around the popup's bottom center.
    local keepBtn = MakeActionButton("Keep Raid Frames", EG.r, EG.g, EG.b, false)
    PP.Point(keepBtn, "BOTTOMRIGHT", popup, "BOTTOM", -BTN_GAP / 2, 40)
    keepBtn:SetScript("OnClick", function() Finish(false) end)

    local disBtn = MakeActionButton("Disable Raid Frames", 1, 1, 1, true)
    PP.Point(disBtn, "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, 40)
    disBtn:SetScript("OnClick", function() Finish(true) end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 80)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    footnote:SetText("Enable/disable any time via the options panel sidebar.")

    -- Escape = Keep (the non-destructive default). Consume Escape, propagate
    -- other keys so chat/UI shortcuts still work behind the dimmer.
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Finish(false) end
    end)

    dimmer:Show()
end

EllesmereUI.ShowRaidFramesIntroPopup = ShowRaidFramesPopup

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
    if EllesmereUIDB.raidFramesIntroShown then
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
    EllesmereUIDB.raidFramesIntroShown = true
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
            EllesmereUI._raidFramesIntroPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if _decision == "new" then
            -- Stamp brand-new users so the popup never fires in a later session.
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.raidFramesIntroShown = true
            return
        end
        if _decision ~= "show" then return end
        C_Timer.After(0.5, function()
            if EllesmereUIDB and EllesmereUIDB.raidFramesIntroShown then
                ReleaseConflictCheck()
                return
            end
            -- Only announce if Raid Frames is actually active for this user. If
            -- they already disabled it, stamp and hand off the conflict check.
            local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(RF_FOLDER)
            if not loaded then
                if EllesmereUIDB then EllesmereUIDB.raidFramesIntroShown = true end
                ReleaseConflictCheck()
                return
            end
            ShowRaidFramesPopup()
        end)
    end
end)
