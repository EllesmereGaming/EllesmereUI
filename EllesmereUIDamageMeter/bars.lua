local addon = EllesmereUIDamageMeter
local S = addon.S
if not S then return end

local floor = math.floor

local MakeBorder = EllesmereUI.MakeBorder

local GetClassColor = S.GetClassColor

function S.CreateBar(parent)
    local bar = {}

    bar.frame = CreateFrame("Frame", nil, parent)

    bar.background = bar.frame:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.background:SetTexture(S.DEFAULT_TEX)
    bar.background:SetVertexColor(0.15, 0.15, 0.15, 0.35)

    bar.statusbar = CreateFrame("StatusBar", nil, bar.frame)
    bar.statusbar:SetAllPoints()
    bar.statusbar:SetStatusBarTexture(S.DEFAULT_TEX)
    bar.statusbar:SetMinMaxValues(0, 1)
    bar.statusbar:SetValue(0)
    bar.statusbar.smoothing = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil

    bar.classIcon = bar.statusbar:CreateTexture(nil, "OVERLAY")
    bar.classIcon:SetTexture(S.CLASS_ICONS)
    bar.classIcon:SetSize(16, 16)
    bar.classIcon:SetPoint("LEFT", 1, 0)
    bar.classIcon:Hide()

    bar.pctText = bar.statusbar:CreateFontString(nil, "OVERLAY")
    bar.pctText:SetPoint("RIGHT", -4, 0)
    bar.pctText:SetJustifyH("RIGHT")
    bar.pctText:SetWordWrap(false)
    bar.pctText:SetShadowOffset(1, -1)
    bar.pctText:Hide()

    bar.rightText = bar.statusbar:CreateFontString(nil, "OVERLAY")
    bar.rightText:SetPoint("RIGHT", -4, 0)
    bar.rightText:SetJustifyH("RIGHT")
    bar.rightText:SetWordWrap(false)
    bar.rightText:SetShadowOffset(1, -1)

    bar.leftText = bar.statusbar:CreateFontString(nil, "OVERLAY")
    bar.leftText:SetPoint("LEFT", 4, 0)
    bar.leftText:SetPoint("RIGHT", bar.rightText, "LEFT", -4, 0)
    bar.leftText:SetJustifyH("LEFT")
    bar.leftText:SetWordWrap(false)
    bar.leftText:SetShadowOffset(1, -1)

    bar.border = MakeBorder(bar.frame, 0, 0, 0, 1)
    bar.border._frame:SetFrameLevel(bar.statusbar:GetFrameLevel() + 2)
    bar.border._frame:Hide()

    bar.textFrame = CreateFrame("Frame", nil, bar.frame)
    bar.textFrame:SetAllPoints()
    bar.textFrame:SetFrameLevel(bar.border._frame:GetFrameLevel() + 1)

    bar.leftText:SetParent(bar.textFrame)
    bar.rightText:SetParent(bar.textFrame)
    bar.pctText:SetParent(bar.textFrame)

    bar.highlight = bar.statusbar:CreateTexture(nil, "ARTWORK")
    bar.highlight:SetAllPoints()
    bar.highlight:SetColorTexture(1, 1, 1, 0.1)
    bar.highlight:Hide()

    bar.selfIndicator = bar.frame:CreateTexture(nil, "ARTWORK")
    bar.selfIndicator:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", 0, 0)
    bar.selfIndicator:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, 0)
    bar.selfIndicator:SetWidth(2)
    bar.selfIndicator:SetColorTexture(1, 1, 1, 0.6)
    bar.selfIndicator:Hide()

    bar.frame:EnableMouse(true)
    bar.frame:Hide()
    return bar
end

function S.ApplyBarIconLayout(bar, db)
    local iconSize = max(8, (db.barHeight or 18) - 2)
    bar.classIcon:SetSize(iconSize, iconSize)
    bar.leftText:ClearAllPoints()
    if db.showClassIcon then
        bar.leftText:SetPoint("LEFT", bar.classIcon, "RIGHT", 2, 0)
    else
        bar.leftText:SetPoint("LEFT", 4, 0)
    end
    bar.leftText:SetPoint("RIGHT", bar.rightText, "LEFT", -4, 0)
end

function S.ApplyBarBorder(bar, db)
    if db.barBorderEnabled then
        bar.border._frame:Show()
    else
        bar.border._frame:Hide()
    end
end

function S.ComputeNumVisible(win)
    local db    = S.GetWinDB(win.index)
    local barHt = max(1, db.barHeight or 18)

    if not win.window then return 1 end
    local availH = win.window:GetHeight() - S.HEADER_HEIGHT

    if not availH or availH < 1 then return 1 end
    local spacing = max(0, db.barSpacing or 1)
    return max(1, floor(availH / (barHt + spacing)))
end

function S.ResizeStandalone(win)
    if not win or not win.window or not win.frame then return end

    local db = S.GetWinDB(win.index)
    local w, h = db.standaloneWidth, db.standaloneHeight
    win.window:SetSize(w, h)

    if win.window.mover then
        win.window.mover:SetSize(w, h)
    end

    local barHt = max(1, db.barHeight or 18)
    for i = 1, S.MAX_BARS do
        if win.bars[i] then win.bars[i].frame:SetHeight(barHt) end
    end
end

function S.EnterDrillDown(win, guid, name, classFilename)
    win.drillSource = { guid = guid, name = name, class = classFilename }
    win.scrollOffset = 0
    S.RefreshWindow(win)
end

function S.ExitDrillDown(win)
    if not win.drillSource then return end
    win.drillSource = nil
    win.scrollOffset = 0
    S.RefreshWindow(win)
end

function S.GetDrillSpellCount(win)
    local ds = win.drillSource
    if not ds then return 0 end

    if S.testMode then
        local tdata = S.GetTestData(win)
        for _, td in ipairs(tdata) do
            if td.name == ds.name then return td.spells and #td.spells or 0 end
        end
        return 0
    end

    local meterType  = S.ResolveMeterType(S.MODE_ORDER[win.modeIndex])
    local sourceData = ds.guid and S.GetSessionSource(win, meterType, ds.guid)
    return (sourceData and sourceData.combatSpells) and #sourceData.combatSpells or 0
end

function S.SetupBarInteraction(bar, win)
    bar.frame:SetScript("OnEnter", function(self)
        if EllesmereUI._unlockActive then return end
        bar.highlight:Show()
        if win.drillSource then
            if self.drillSpellID then
                GameTooltip_SetDefaultAnchor(GameTooltip, self)
                GameTooltip:SetSpellByID(self.drillSpellID)
                GameTooltip:Show()
            end
            return
        end

        local unitShown = false
        local guid = self.sourceGUID
        if guid then
            local unit = S.FindUnitByGUID(guid)
            if unit then
                GameTooltip_SetDefaultAnchor(GameTooltip, self)
                GameTooltip:SetUnit(unit)
                unitShown = true
            end
        end
        if not unitShown then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            if self.sourceName then
                local cls = self.sourceClass
                if not cls then cls = guid and S.classCache[guid] end
                if not cls and self.testIndex then
                    local td = S.GetTestData(win)[self.testIndex]
                    if td then cls = td.class end
                end
                local cr, cg, cb = GetClassColor(cls)
                GameTooltip:AddLine(self.sourceName, cr, cg, cb)
            end
        end
        GameTooltip:AddLine("Click for spell breakdown", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    bar.frame:SetScript("OnLeave", function()
        bar.highlight:Hide()
        GameTooltip_Hide()
    end)

    bar.frame:SetScript("OnMouseUp", function(self, button)
        if win.drillSource then
            if button == "RightButton" then
                S.ExitDrillDown(win)
            end
            return
        end

        if button == "LeftButton" then
            GameTooltip:Hide()
            if S.testMode and self.testIndex then
                local td = S.GetTestData(win)[self.testIndex]
                if td then
                    S.EnterDrillDown(win, nil, td.name, td.class)
                end
                return
            end
            if self.sourceGUID and self.sourceName then
                local class = S.classCache[self.sourceGUID]
                S.EnterDrillDown(win, self.sourceGUID, self.sourceName, class)
            end
        elseif button == "RightButton" then
            GameTooltip:Hide()
            local addon = EllesmereUIDamageMeter
            if addon and addon.ReportMeter then
                MenuUtil.CreateContextMenu(self, function(_, rootDescription)
                    rootDescription:CreateTitle("Report Meter")
                    local channels = { {"Party", "PARTY"}, {"Raid", "RAID"}, {"Say", "SAY"}, {"Guild", "GUILD"} }
                    for _, ch in ipairs(channels) do
                        rootDescription:CreateButton(ch[1], function()
                            addon:ReportMeter(ch[2])
                        end)
                    end
                end)
            end
        end
    end)
end

function S.ApplySessionHighlight(win, db)
    if win.sessionId then
        win.header.sessText:SetTextColor(1, 0.3, 0.3)
    else
        win.header.sessText:SetTextColor(db.headerFontColor.r, db.headerFontColor.g, db.headerFontColor.b)
    end
end

function S.ResetDrillBar(bar, db)
    bar._isDrill = nil
    bar._drillHasIcon = nil
    bar.pctText:Hide()
    bar.rightText:ClearAllPoints()
    bar.rightText:SetPoint("RIGHT", -4, 0)
    local style = db.classIconStyle or 'fabled'
    if style == 'fabled' or not style then
        bar.classIcon:SetTexture(S.CLASS_ICONS)
    end
    S.ApplyBarIconLayout(bar, db)
end

function S.ResetWindowState(win)
    win.scrollOffset = 0
    win.drillSource  = nil
    win.sessionId    = nil
    win.sessionType  = Enum.DamageMeterSessionType.Current
end
