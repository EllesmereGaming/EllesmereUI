-- EllesmereUI_ClientGate.lua
-- Pre-12.1 client failsafe. MUST stay the FIRST file in the parent TOC.
--
-- This build targets WoW Midnight (12.1+) exclusively. If it ever loads on an
-- older client, running normally would be destructive: the migration pass
-- would rewrite settings into shapes the pre-12.1 addon cannot read, and the
-- DB layer would seed/transform tables against APIs that do not exist there.
-- The next logout would then persist that damage into the WTF files.
--
-- The failsafe: on a pre-12.1 client this file sets EUI_CLIENT_BLOCKED, and
-- line 1 of EVERY suite file returns immediately when that flag is set. No
-- DB is created, no migration runs, no SavedVariables global is ever read or
-- written -- WoW loads each WTF file into its global and writes the same
-- untouched table back at logout, a lossless round trip. The only thing that
-- runs is the popup below telling the user to go back to the pre-12.1
-- release. Reverting restores the addon with settings exactly as they were.
--
-- Fail-open by design: if the interface number cannot be read as a number,
-- the suite runs normally -- the failsafe must never break a healthy client.
-- On 12.1+ this file is a single comparison and exits; no globals, no frames.

local iface = select(4, GetBuildInfo())
if not (type(iface) == "number" and iface < 120100) then return end

EUI_CLIENT_BLOCKED = true

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    local p = CreateFrame("Frame", "EUIClientGatePopup", UIParent)
    p:SetSize(480, 170)
    p:SetPoint("CENTER", 0, 140)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)

    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.055, 0.06, 0.07, 0.97)

    -- 1px accent border (no dependencies -- the shared border kit is gated).
    local function Edge(point1, point2, w, h)
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.05, 0.82, 0.62, 0.9)
        t:SetPoint(point1)
        t:SetPoint(point2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("EllesmereUI")
    title:SetTextColor(0.05, 0.82, 0.62)

    local body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOP", title, "BOTTOM", 0, -12)
    body:SetWidth(430)
    body:SetJustifyH("CENTER")
    body:SetText("This version of EllesmereUI is built for the Midnight 12.1 patch and has been disabled on this game version.|n|nYour saved settings are safe and untouched. Please install the previous EllesmereUI release until 12.1 launches.")

    local btn = CreateFrame("Button", nil, p)
    btn:SetSize(110, 26)
    btn:SetPoint("BOTTOM", 0, 14)
    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.05, 0.82, 0.62, 0.85)
    local bl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bl:SetPoint("CENTER")
    bl:SetText("Okay")
    bl:SetTextColor(0, 0, 0)
    btn:SetScript("OnEnter", function() bbg:SetColorTexture(0.05, 0.82, 0.62, 1) end)
    btn:SetScript("OnLeave", function() bbg:SetColorTexture(0.05, 0.82, 0.62, 0.85) end)
    btn:SetScript("OnClick", function() p:Hide() end)

    tinsert(UISpecialFrames, "EUIClientGatePopup")
end)
