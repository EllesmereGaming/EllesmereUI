if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  EUI_QoL_StatPicker.lua
--  WoW Forever: the Choose Stats window of the Secondary Stats cog. One
--  column per stat group of EllesmereUIQoL_ForeverStats.lua, All / None per
--  group, Check All / Uncheck All and Done. A click writes at once and the
--  block repaints live. Like the cog popups it dims nothing: it closes on a
--  click outside it, on Escape and with the options panel.
-------------------------------------------------------------------------------
local qns = EllesmereUI._ModuleNS["EllesmereUIQoL"]
if not qns then return end  -- module disabled: no options page

local NUM_COLS, COL_W, COL_GAP = 3, 200, 18
local PAD, CONTENT_TOP = 24, 92
local HEADER_H, ITEM_H = 26, 24
local GRP_GAP, BOTTOM_H = 16, 66

local function IsShown(key)
    local hidden = EllesmereUI.QoLExtrasGet("secondaryStatsHidden")
    return not (type(hidden) == "table" and hidden[key])
end

-- One write and one repaint for any number of stats.
local function SetShown(stats, show)
    local old = EllesmereUI.QoLExtrasGet("secondaryStatsHidden")
    local hidden = {}
    if type(old) == "table" then
        for k, v in pairs(old) do hidden[k] = v end
    end
    for _, s in ipairs(stats) do hidden[s.key] = not show end
    EllesmereUI.QoLExtrasSet("secondaryStatsHidden", hidden)
    EllesmereUI._applySecondaryStats()
end

local panel
local checks = {}   -- one repaint function per stat row

local function RefreshAll()
    for _, apply in ipairs(checks) do apply() end
end

-- A text-only link (All / None / Check All) that brightens on hover.
local function Link(text, onClick)
    local b = CreateFrame("Button", nil, panel)
    local fs = EllesmereUI.MakeFont(b, 12, "", 1, 1, 1, 0.5)
    fs:SetText(text)
    fs:SetPoint("CENTER")
    b:SetSize(fs:GetStringWidth() + 6, 16)
    b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1, 0.9) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1, 0.5) end)
    b:SetScript("OnClick", function()
        onClick()
        RefreshAll()
    end)
    return b
end

local function Build()
    local groups = qns.FvStats.groups
    local EG = EllesmereUI.ELLESMERE_GREEN

    -- Groups wrap NUM_COLS to a line; each line is as tall as its longest group.
    local lineTop, y = {}, CONTENT_TOP
    for first = 1, #groups, NUM_COLS do
        local n = 0
        for gi = first, math.min(first + NUM_COLS - 1, #groups) do
            n = math.max(n, #groups[gi].stats)
        end
        lineTop[#lineTop + 1] = y
        y = y + HEADER_H + n * ITEM_H + GRP_GAP
    end

    panel = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
    panel:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the options panel and its popups
    panel:SetSize(PAD * 2 + NUM_COLS * COL_W + (NUM_COLS - 1) * COL_GAP, y - GRP_GAP + BOTTOM_H)
    panel:SetScale(EllesmereUI.GetPopupScale())
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    local pf = EllesmereUI._popupFrames
    pf[#pf + 1] = { popup = panel }
    EllesmereUI.PadHint(panel, "nodepass")

    EllesmereUI.SolidTex(panel, "BACKGROUND", 0.077, 0.068, 0.058, 1):SetAllPoints()
    EllesmereUI.MakeBorder(panel, 1, 1, 1, 0.15, EllesmereUI.PanelPP)

    local title = EllesmereUI.MakeFont(panel, 18, "", 1, 1, 1)
    title:SetPoint("TOP", panel, "TOP", 0, -20)
    title:SetText(EllesmereUI.L("Stats to Show"))
    local sub = EllesmereUI.MakeFont(panel, 12, "", 1, 1, 1, 0.45)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetText(EllesmereUI.L("Checked stats show in the on-screen block."))

    local all = {}
    for _, g in ipairs(groups) do
        for _, s in ipairs(g.stats) do all[#all + 1] = s end
    end
    local checkAll = Link(EllesmereUI.L("Check All"), function() SetShown(all, true) end)
    checkAll:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -62)
    local sep = EllesmereUI.SolidTex(panel, "OVERLAY", 1, 1, 1, 0.18)
    sep:SetSize(1, 12)
    sep:SetPoint("LEFT", checkAll, "RIGHT", 10, 0)
    local uncheckAll = Link(EllesmereUI.L("Uncheck All"), function() SetShown(all, false) end)
    uncheckAll:SetPoint("LEFT", checkAll, "RIGHT", 20, 0)

    for gi, g in ipairs(groups) do
        local colX = PAD + ((gi - 1) % NUM_COLS) * (COL_W + COL_GAP)
        local grpY = -lineTop[math.floor((gi - 1) / NUM_COLS) + 1]

        local hdr = EllesmereUI.MakeFont(panel, 13, "", EG.r, EG.g, EG.b)
        hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", colX, grpY)
        hdr:SetText(EllesmereUI.L(g.title))
        local none = Link(EllesmereUI.L("None"), function() SetShown(g.stats, false) end)
        none:SetPoint("TOPRIGHT", panel, "TOPLEFT", colX + COL_W, grpY - 2)
        local allLink = Link(EllesmereUI.L("All"), function() SetShown(g.stats, true) end)
        allLink:SetPoint("RIGHT", none, "LEFT", -8, 0)
        local underline = EllesmereUI.SolidTex(panel, "ARTWORK", EG.r, EG.g, EG.b, 0.35)
        underline:SetSize(COL_W, 1)
        underline:SetPoint("TOPLEFT", panel, "TOPLEFT", colX, grpY - HEADER_H + 8)

        for j, s in ipairs(g.stats) do
            local row = CreateFrame("Button", nil, panel)
            row:SetSize(COL_W, ITEM_H)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", colX, grpY - HEADER_H - (j - 1) * ITEM_H)
            local box, _, _, applyVisual = EllesmereUI.BuildCheckboxControl(row, row:GetFrameLevel() + 1)
            box:ClearAllPoints()
            box:SetPoint("LEFT", row, "LEFT", 0, 0)
            local lbl = EllesmereUI.MakeFont(row, 12, "", 0.85, 0.85, 0.85)
            lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
            lbl:SetText(EllesmereUI.L(s.label))
            local function Apply() applyVisual(IsShown(s.key), row:IsMouseOver()) end
            checks[#checks + 1] = Apply
            local one = { s }
            row:SetScript("OnClick", function()
                SetShown(one, not IsShown(s.key))
                Apply()
            end)
            row:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1); Apply() end)
            row:SetScript("OnLeave", function() lbl:SetTextColor(0.85, 0.85, 0.85, 1); Apply() end)
        end
    end

    local done = EllesmereUI.MakeActionButton(panel, EllesmereUI.EXPRESSWAY,
        EllesmereUI.L("Done"), EG.r, EG.g, EG.b, { w = 200 })
    done:SetPoint("BOTTOM", panel, "BOTTOM", 0, 16)
    done:SetScript("OnClick", function() panel:Hide() end)

    -- Closes on a click anywhere else: a global mouse-down listener held only
    -- while shown. Clicks fire on mouse up, so the press that opened it has
    -- already passed.
    panel:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    panel:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    panel:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() then self:Hide() end
    end)
    panel:EnableKeyboard(true)
    panel:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then self:Hide() end
    end)
    EllesmereUI._mainFrame:HookScript("OnHide", function() panel:Hide() end)
    EllesmereUI.TrackOverlay(panel)
end

function EllesmereUI._ShowStatPicker(anchor)
    if not panel then Build() end
    panel:ClearAllPoints()
    panel:SetPoint("TOP", anchor, "BOTTOM", 0, -5)
    RefreshAll()
    panel:Show()
    panel:Raise()
end
