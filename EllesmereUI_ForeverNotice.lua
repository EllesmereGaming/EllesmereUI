if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_ForeverNotice.lua
--
--  WoW Forever beta notice. The beta client (1.60.x) persists SavedVariables
--  only some of the time: a setting change can be gone at the next reload or
--  logout, so anything that reloads the UI (every Reload Now prompt, the
--  Style switcher) can reset the user, and the first-install picker and the
--  style picker are switched off there meanwhile (EllesmereUI.FOREVER_SV_BUG).
--  A warning-styled popup (the announcement layout in warning colours) says
--  so in plain words at login, until a write finally sticks: the seen stamp
--  is written on dismiss, so the day the client saves it the popup retires
--  itself. Nothing here runs on retail (EllesmereUI.IS_FOREVER is false).
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI or not EllesmereUI.IS_FOREVER then return end
-- TEMPORARY, WoW Forever only (EllesmereUI.FOREVER_SV_BUG): the whole notice
-- is about the settings bug and retires with the switch.
if not EllesmereUI.FOREVER_SV_BUG then return end
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder
-- Warm tan (#DEAD6B): a warning, not an alarm.
local WARN_R, WARN_G, WARN_B = 0.87, 0.68, 0.42

local function ShowForeverNotice()
    if not (PP and MakeBorder) then return end
    local FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local POPUP_W, POPUP_H = 520, 440
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    -- Dimmer: darker than the announcements, eats clicks, no close on outside
    -- click. TOOLTIP strata so the notice sits above the first-install picker
    -- when both land on one login.
    local dimmer = CreateFrame("Frame", "EUIForeverNoticeDimmer", UIParent)
    dimmer:SetFrameStrata("TOOLTIP")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScale(ppScale)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.6)

    local popup = CreateFrame("Frame", "EUIForeverNoticePopup", dimmer)
    popup:SetScale((EllesmereUI.PopupBump and EllesmereUI.PopupBump(1.15)) or 1.15)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PP.Size(popup, POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.085, 0.07, 0.05, 1)

    -- Warning frame: a 2px orange edge, then a soft inner glow band so the
    -- panel reads as a warning from across the room.
    local onePhys = 1 / (popup:GetEffectiveScale() or 1)
    local edgeW = onePhys * 2
    local function MakeEdge()
        local t = popup:CreateTexture(nil, "BORDER")
        t:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.95)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local spT = MakeEdge(); spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(edgeW)
    local spB = MakeEdge(); spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(edgeW)
    local spL = MakeEdge(); spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(edgeW)
    local spR = MakeEdge(); spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(edgeW)
    local glow = popup:CreateTexture(nil, "BORDER", nil, -1)
    glow:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
    glow:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    glow:SetHeight(70)
    glow:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.10)

    -- The stock alert icon: shipped on every client, no atlas to validate.
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    PP.Size(icon, 56, 56)
    PP.Point(icon, "TOP", popup, "TOP", 0, -17)

    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(WARN_R, WARN_G, WARN_B, 1)
    PP.Point(eyebrow, "TOP", icon, "BOTTOM", 0, -10)
    eyebrow:SetText("WOW FOREVER BETA")

    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("Your settings will not save")

    local body = popup:CreateFontString(nil, "OVERLAY")
    body:SetFont(FONT, 15, "")
    body:SetTextColor(1, 1, 1, 0.85)
    body:SetWidth(POPUP_W - 70)
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetSpacing(4)
    PP.Point(body, "TOP", title, "BOTTOM", 0, -14)
    body:SetText("Blizzard's WoW Forever beta client cannot reliably save addon settings right now.\n"
        .. "Anything that reloads your UI, including every Reload Now prompt, resets your "
        .. "EllesmereUI settings, so options that need a reload to apply, like the Style "
        .. "switcher, will not work until Blizzard fixes this.\n"
        .. "This is a Blizzard bug, not a lost profile. The first-install setup and the "
        .. "style picker stay off on WoW Forever until then.")

    -- Only while the snippet compiler is missing too: the modules that stand
    -- down because of it, in one line.
    if not EllesmereUI.SecureSnippetsOK() then
        local note = popup:CreateFontString(nil, "OVERLAY")
        note:SetFont(FONT, 12, "")
        note:SetTextColor(1, 1, 1, 0.5)
        note:SetWidth(POPUP_W - 70)
        note:SetJustifyH("CENTER")
        note:SetWordWrap(true)
        PP.Point(note, "BOTTOM", popup, "BOTTOM", 0, 86)
        note:SetText("The current client also has a bug that prevents some Action Bars functionality and switches off Raid Frames, Quickdraw and Raid Tools until Blizzard fixes it.")
    end

    local function Finish()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        -- Persists only once the client saves again, which is exactly when
        -- the notice should stop.
        EllesmereUIDB.foreverSvWarnSeen = true
        dimmer:Hide()
    end

    local btn = CreateFrame("Button", nil, popup)
    btn:SetFrameLevel(popup:GetFrameLevel() + 2)
    PP.Size(btn, 220, 40)
    PP.Point(btn, "BOTTOM", popup, "BOTTOM", 0, 30)
    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.16)
    local brd = MakeBorder(btn, WARN_R, WARN_G, WARN_B, 0.9, PP)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(FONT, 16, "")
    PP.Point(lbl, "CENTER", btn, "CENTER", 0, 0)
    lbl:SetTextColor(1, 1, 1, 0.95)
    lbl:SetText("I Understand")
    btn:SetScript("OnEnter", function()
        bbg:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.32)
        brd:SetColor(WARN_R, WARN_G, WARN_B, 1)
    end)
    btn:SetScript("OnLeave", function()
        bbg:SetColorTexture(WARN_R, WARN_G, WARN_B, 0.16)
        brd:SetColor(WARN_R, WARN_G, WARN_B, 0.9)
    end)
    btn:SetScript("OnClick", Finish)

    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Finish() end
    end)

    dimmer:Show()
end

EllesmereUI.ShowForeverNotice = ShowForeverNotice

-- Lands after the first-install picker's own 0.5s login delay so it sits on
-- top of it, never under it.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if EllesmereUIDB and EllesmereUIDB.foreverSvWarnSeen then return end
    C_Timer.After(0.8, function()
        if EllesmereUIDB and EllesmereUIDB.foreverSvWarnSeen then return end
        ShowForeverNotice()
    end)
end)
