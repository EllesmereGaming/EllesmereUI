local addon = EllesmereUIDamageMeter
local S = addon.S
if not S then return end
local LSM = LibStub('LibSharedMedia-3.0')

local floor = math.floor

local BACKDROP_FILL = { bgFile = 'Interface\\Buttons\\WHITE8x8' }
local MakeBorder = EllesmereUI.MakeBorder

local function FadeIn(frame, duration, fromAlpha, toAlpha)
    if UIFrameFadeIn then
        UIFrameFadeIn(frame, duration, fromAlpha, toAlpha)
    else
        frame:SetAlpha(toAlpha)
    end
end

local function FadeOut(frame, duration, fromAlpha, toAlpha)
    if UIFrameFadeOut then
        UIFrameFadeOut(frame, duration, fromAlpha, toAlpha)
    else
        frame:SetAlpha(toAlpha)
    end
end

local function BuildMenuDescription(rootDescription, items)
    for _, item in ipairs(items) do
        if item.isSeparator then
            rootDescription:CreateDivider()
        elseif item.hasArrow and item.menuList then
            local sub = rootDescription:CreateButton(item.text)
            BuildMenuDescription(sub, item.menuList)
        else
            rootDescription:CreateButton(item.text, item.func)
        end
    end
end

local function OpenMenuAnchored(menuItems, header)
    MenuUtil.CreateContextMenu(header, function(_, rootDescription)
        BuildMenuDescription(rootDescription, menuItems)
    end)
end

function S.SetupScrollWheel(win)
    win.frame:EnableMouseWheel(true)
    win.frame:SetScript('OnMouseWheel', function(_, delta)
        local total
        if win.drillSource then
            total = S.GetDrillSpellCount(win)
        elseif S.testMode then
            total = #S.GetTestData(win)
        else
            local meterType = S.ResolveMeterType(S.MODE_ORDER[win.modeIndex])
            local session   = S.GetSession(win, meterType)
            total = (session and session.combatSources and #session.combatSources) or 0
        end
        local numVis = S.ComputeNumVisible(win)
        local maxOff = max(0, total - numVis)
        win.scrollOffset = max(0, min(maxOff, win.scrollOffset - delta))
        S.RefreshWindow(win)
    end)
end

function S.FadeHeaderIn(win)
    local db = S.GetWinDB(win.index)
    if not db.headerMouseover then return end
    if win.header then FadeIn(win.header, 0.2, win.header:GetAlpha(), 1) end
    if win.headerBorder then FadeIn(win.headerBorder, 0.2, win.headerBorder:GetAlpha(), 1) end
end

function S.FadeHeaderOut(win)
    local db = S.GetWinDB(win.index)
    if not db.headerMouseover then return end
    if win.header then FadeOut(win.header, 0.2, win.header:GetAlpha(), 0) end
    if win.headerBorder then FadeOut(win.headerBorder, 0.2, win.headerBorder:GetAlpha(), 0) end
end

function S.SetupHeaderMouseover(win)
    if win._headerMouseoverHooked then return end
    win._headerMouseoverHooked = true

    local function OnEnter() S.FadeHeaderIn(win) end
    local function OnLeave() S.FadeHeaderOut(win) end

    if win.header then
        win.header:HookScript('OnEnter', OnEnter)
        win.header:HookScript('OnLeave', OnLeave)
        for _, child in pairs({ win.header.modeArea, win.header.sessArea, win.header.reset }) do
            if child then
                child:HookScript('OnEnter', OnEnter)
                child:HookScript('OnLeave', OnLeave)
            end
        end
    end
end

function S.ApplyHeaderStyle(win, db)
    local header = win.header
    if not header then return end

    local fontPath = S.ResolveFontPath(db.headerFont)
    local flags    = S.FontFlags(db.headerFontOutline)

    local hc = db.headerBGColor
    if db.showHeaderBackdrop then
        header.bg:SetVertexColor(hc.r, hc.g, hc.b, hc.a)
    else
        header.bg:SetVertexColor(0, 0, 0, 0)
    end

    local tc = db.headerFontColor
    S.ApplyFont(header.modeText, fontPath, db.headerFontSize + 1, flags)
    header.modeText:SetTextColor(tc.r, tc.g, tc.b)

    S.ApplyFont(header.sessText, fontPath, db.headerFontSize + 1, flags)
    header.sessText:SetTextColor(tc.r, tc.g, tc.b)

    S.ApplyFont(header.timer, fontPath, db.headerFontSize, flags)
    header.timer:SetTextColor(tc.r, tc.g, tc.b, 0.7)
    header.timer:ClearAllPoints()
    if db.showTimer then
        header.timer:SetPoint('RIGHT', header.reset, 'LEFT', -4, 0)
        header.timer:Show()
    else
        header.timer:Hide()
    end
end

function S.MakeModeEntry(win, mtype)
    local idx
    for i, mt in ipairs(S.MODE_ORDER) do
        if mt == mtype then idx = i; break end
    end
    if not idx then return nil end

    local label = S.MODE_LABELS[mtype] or '?'
    return {
        text         = (idx == win.modeIndex) and ('|cffffd100' .. label .. '|r') or label,
        notCheckable = true,
        func         = function()
            win.modeIndex    = idx
            win.drillSource  = nil
            win.scrollOffset = 0
            local wdb = S.GetWinDB(win.index)
            wdb.modeIndex = idx
            S.RefreshWindow(win)
        end,
    }
end

function S.BuildModeMenu(win)
    local dmg = {
        S.MakeModeEntry(win, Enum.DamageMeterType.DamageDone),
        S.MakeModeEntry(win, Enum.DamageMeterType.Dps),
        S.MakeModeEntry(win, S.COMBINED_DAMAGE),
        S.MakeModeEntry(win, Enum.DamageMeterType.DamageTaken),
        S.MakeModeEntry(win, Enum.DamageMeterType.AvoidableDamageTaken),
    }
    if Enum.DamageMeterType.EnemyDamageTaken then
        dmg[#dmg + 1] = S.MakeModeEntry(win, Enum.DamageMeterType.EnemyDamageTaken)
    end

    local heal = {
        S.MakeModeEntry(win, Enum.DamageMeterType.HealingDone),
        S.MakeModeEntry(win, Enum.DamageMeterType.Hps),
        S.MakeModeEntry(win, S.COMBINED_HEALING),
        S.MakeModeEntry(win, Enum.DamageMeterType.Absorbs),
    }

    local actions = {
        S.MakeModeEntry(win, Enum.DamageMeterType.Interrupts),
        S.MakeModeEntry(win, Enum.DamageMeterType.Dispels),
    }
    if Enum.DamageMeterType.Deaths then
        actions[#actions + 1] = S.MakeModeEntry(win, Enum.DamageMeterType.Deaths)
    end

    return {
        { text = 'Damage',  notCheckable = true, hasArrow = true, menuList = dmg },
        { text = 'Healing', notCheckable = true, hasArrow = true, menuList = heal },
        { text = 'Actions', notCheckable = true, hasArrow = true, menuList = actions },
    }
end

function S.BuildSessionMenu(win)
    local menu = {}

    -- Encounter sessions (oldest at top, newest at bottom)
    if C_DamageMeter.GetAvailableCombatSessions then
        local sessions = C_DamageMeter.GetAvailableCombatSessions()
        if sessions and #sessions > 0 then
            for _, sess in ipairs(sessions) do
                local sid = sess.sessionId or sess.combatSessionId or sess.id or sess.sessionID
                local label = sess.name or 'Encounter'
                local dur = sess.durationSeconds or sess.duration
                if dur and not S.IsSecret(dur) then
                    label = label .. format(' [%d:%02d]', floor(dur / 60), floor(dur % 60))
                end
                menu[#menu + 1] = {
                    text = (win.sessionId == sid) and ('|cffffd100' .. label .. '|r') or label,
                    notCheckable = true,
                    func = function()
                        win.sessionId    = sid
                        win.sessionType  = nil
                        win.scrollOffset = 0
                        win.drillSource  = nil
                        S.RefreshWindow(win)
                    end,
                }
            end
            menu[#menu + 1] = { isSeparator = true }
        end
    end

    -- Current / Overall
    menu[#menu + 1] = {
        text = (win.sessionId == nil and win.sessionType == Enum.DamageMeterSessionType.Current)
            and '|cffffd100Current Segment|r' or 'Current Segment',
        notCheckable = true,
        func = function()
            win.sessionId    = nil
            win.sessionType  = Enum.DamageMeterSessionType.Current
            win.scrollOffset = 0
            win.drillSource  = nil
            S.RefreshWindow(win)
        end,
    }

    menu[#menu + 1] = {
        text = (win.sessionId == nil and win.sessionType == Enum.DamageMeterSessionType.Overall)
            and '|cffffd100Overall|r' or 'Overall',
        notCheckable = true,
        func = function()
            win.sessionId    = nil
            win.sessionType  = Enum.DamageMeterSessionType.Overall
            win.scrollOffset = 0
            win.drillSource  = nil
            S.RefreshWindow(win)
        end,
    }

    return menu
end

function S.ToggleSession(win)
    win.sessionId = nil
    if win.sessionType == Enum.DamageMeterSessionType.Current then
        win.sessionType = Enum.DamageMeterSessionType.Overall
    else
        win.sessionType = Enum.DamageMeterSessionType.Current
    end
    win.scrollOffset = 0
    win.drillSource  = nil
    S.RefreshWindow(win)
end

function S.SetupHeaderContent(win, db)
    local header = win.header

    header.bg = header:CreateTexture(nil, 'BACKGROUND')
    header.bg:SetAllPoints()
    header.bg:SetTexture(S.DEFAULT_TEX)

    header.modeText = header:CreateFontString(nil, 'OVERLAY')
    header.modeText:SetPoint('LEFT', 4, 0)
    header.modeText:SetShadowOffset(1, -1)

    header.sessText = header:CreateFontString(nil, 'OVERLAY')
    header.sessText:SetPoint('LEFT', header.modeText, 'RIGHT', 0, 0)
    header.sessText:SetShadowOffset(1, -1)

    header.reset = CreateFrame('Button', nil, header)
    header.reset:SetSize(16, 16)
    header.reset:SetPoint('RIGHT', -4, 0)
    header.reset.text = header.reset:CreateFontString(nil, 'OVERLAY')
    header.reset.text:SetAllPoints()
    header.reset.text:SetFont(STANDARD_TEXT_FONT, 14, 'OUTLINE')
    header.reset.text:SetText('x')
    header.reset.text:SetTextColor(0.8, 0.2, 0.2)
    header.reset:SetScript('OnClick', function(_, btn)
        if btn == 'LeftButton' then
            StaticPopup_Show('EUIDM_RESET')
        end
    end)
    header.reset:HookScript('OnEnter', function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:AddLine('Reset Meter', 1, 0.3, 0.3)
        GameTooltip:AddLine('Clears all session data.', 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    header.reset:HookScript('OnLeave', GameTooltip_Hide)

    header.timer = header:CreateFontString(nil, 'OVERLAY')
    header.timer:SetShadowOffset(1, -1)

    S.ApplyHeaderStyle(win, db)

    header.modeArea = CreateFrame('Frame', nil, header)
    header.modeArea:SetPoint('TOPLEFT',     header.modeText, 'TOPLEFT',     0, 0)
    header.modeArea:SetPoint('BOTTOMRIGHT', header.modeText, 'BOTTOMRIGHT', 0, 0)
    header.modeArea:EnableMouse(true)
    header.modeArea:SetScript('OnMouseUp', function(_, button)
        if button == 'LeftButton' then
            if win.drillSource then
                S.ExitDrillDown(win)
            else
                OpenMenuAnchored(S.BuildModeMenu(win), header)
            end
        elseif button == 'RightButton' then
            S.ToggleSession(win)
        end
    end)
    header.modeArea:SetScript('OnEnter', function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        if win.drillSource then
            GameTooltip:AddLine('|cffffd100Left-click:|r return to overview', 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine('|cffffd100Left-click:|r choose display mode', 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine('|cffffd100Right-click:|r toggle Current / Overall', 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    header.modeArea:SetScript('OnLeave', GameTooltip_Hide)

    header.sessArea = CreateFrame('Frame', nil, header)
    header.sessArea:SetPoint('TOPLEFT',     header.sessText, 'TOPLEFT',     0, 0)
    header.sessArea:SetPoint('BOTTOMRIGHT', header.sessText, 'BOTTOMRIGHT', 0, 0)
    header.sessArea:EnableMouse(true)
    header.sessArea:SetScript('OnMouseUp', function(_, button)
        if button == 'LeftButton' then
            OpenMenuAnchored(S.BuildSessionMenu(win), header)
        elseif button == 'RightButton' then
            S.ToggleSession(win)
        end
    end)
    header.sessArea:SetScript('OnEnter', function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:AddLine('|cffffd100Left-click:|r choose encounter', 0.7, 0.7, 0.7)
        GameTooltip:AddLine('|cffffd100Right-click:|r toggle Current / Overall', 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    header.sessArea:SetScript('OnLeave', GameTooltip_Hide)
end

function S.SetupWindowContent(win, db, parent)
    local winName = 'EUIDMMeter' .. (win.index or 1)
    local hdrName = 'EUIDMMeterHeader' .. (win.index or 1)

    win.header = CreateFrame('Frame', hdrName, parent)
    win.header:SetPoint('TOPLEFT',  win.window, 'TOPLEFT',  0, 0)
    win.header:SetPoint('TOPRIGHT', win.window, 'TOPRIGHT', 0, 0)
    win.header:SetHeight(S.HEADER_HEIGHT)
    win.header:SetFrameLevel(win.window:GetFrameLevel() + 1)

    win.headerBorderObj = MakeBorder(win.header, 0, 0, 0, 1)
    win.headerBorder = win.headerBorderObj._frame
    if not db.showHeaderBorder then
        win.headerBorder:Hide()
    end
    win.header:EnableMouse(true)

    S.SetupHeaderContent(win, db)

    win.frame = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
    win.frame:SetFrameStrata('MEDIUM')
    win.frame:SetClipsChildren(true)
    win.frame:SetPoint('TOPLEFT',     win.window, 'TOPLEFT',     0, -S.HEADER_HEIGHT)
    win.frame:SetPoint('BOTTOMRIGHT', win.window, 'BOTTOMRIGHT', 0,  0)

    win.emptyText = win.frame:CreateFontString(nil, 'OVERLAY')
    win.emptyText:SetPoint('CENTER', win.frame, 'CENTER', 0, 0)
    local emptyFont = S.ResolveFontPath(db.barFont)
    S.ApplyFont(win.emptyText, emptyFont, db.barFontSize, S.FontFlags(db.barFontOutline))
    win.emptyText:SetTextColor(0.5, 0.5, 0.5, 0.6)
    win.emptyText:SetText('No data')
    win.emptyText:Hide()

    win.frameBorderObj = MakeBorder(win.frame, 0, 0, 0, 1)
    if db.showBackdrop then
        win.frame:SetBackdrop(BACKDROP_FILL)
        local bc = db.backdropColor
        if bc then
            win.frame:SetBackdropColor(bc.r, bc.g, bc.b, bc.a)
        else
            win.frame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        end
    end

    if not db.showHeaderBackdrop and win.header.bg then
        win.header.bg:Hide()
    end

    local fontPath = S.ResolveFontPath(db.barFont)
    local flags    = S.FontFlags(db.barFontOutline)

    for j = 1, S.MAX_BARS do
        local bar = S.CreateBar(win.frame)
        S.StyleBarTexts(bar, fontPath, db.barFontSize, flags)
        S.ApplyBarIconLayout(bar, db)
        S.ApplyBarBorder(bar, db)

        local sp = max(0, db.barSpacing or 1)
        local borderAdj = (db.barBorderEnabled and sp == 0) and 1 or 0
        if j == 1 then
            bar.frame:SetPoint('TOPLEFT',  win.frame, 'TOPLEFT',  0, 0)
            bar.frame:SetPoint('TOPRIGHT', win.frame, 'TOPRIGHT', 0, 0)
        else
            bar.frame:SetPoint('TOPLEFT',  win.bars[j-1].frame, 'BOTTOMLEFT',  0, -sp + borderAdj)
            bar.frame:SetPoint('TOPRIGHT', win.bars[j-1].frame, 'BOTTOMRIGHT', 0, -sp + borderAdj)
        end
        win.bars[j] = bar
        S.SetupBarInteraction(bar, win)
    end

    S.SetupScrollWheel(win)

    S.SetupHeaderMouseover(win)
    if db.headerMouseover then
        win.header:SetAlpha(0)
        if win.headerBorder then win.headerBorder:SetAlpha(0) end
    end
end

function S.CreateMeterFrame(win)
    local db = S.GetWinDB(win.index)

    local w, h = db.standaloneWidth, db.standaloneHeight

    local window = CreateFrame('Frame', 'EUIDMMeter' .. (win.index or 1), UIParent, 'BackdropTemplate')
    window:SetSize(w, h)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag('LeftButton')
    window:SetScript('OnDragStart', window.StartMoving)
    window:SetScript('OnDragStop', function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        local point, _, relPoint, x, y = self:GetPoint(1)
        addon.db.profile.position = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    window:SetClampedToScreen(true)
    window:SetFrameStrata('BACKGROUND')
    window:SetFrameLevel(300)

    local pos = addon.db.profile.position
    if pos then
        window:SetPoint(pos.point or 'CENTER', UIParent, pos.relPoint or 'CENTER', pos.x or 0, pos.y or 0)
    else
        window:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
    end

    win.window = window

    S.SetupWindowContent(win, db, window)
    S.ResizeStandalone(win)

    if EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement then
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key       = 'EUIDM_Window',
                label     = 'Damage Meter',
                group     = 'Damage Meter',
                order     = 500,
                getFrame  = function() return window end,
                getSize   = function() return window:GetSize() end,
                setWidth  = function(_, w)
                    addon.db.profile.standaloneWidth = math.max(math.floor(w + 0.5), 120)
                    addon:ResizeMeterWindow(1)
                end,
                setHeight = function(_, h)
                    addon.db.profile.standaloneHeight = math.max(math.floor(h + 0.5), 80)
                    addon:ResizeMeterWindow(1)
                end,
                savePos = function(_, point, relPoint, x, y)
                    addon.db.profile.position = { point = point, relPoint = relPoint, x = x, y = y }
                end,
                loadPos = function()
                    return addon.db.profile.position
                end,
                clearPos = function()
                    addon.db.profile.position = nil
                end,
                applyPos = function()
                    local p = addon.db.profile.position
                    if p then
                        window:ClearAllPoints()
                        window:SetPoint(p.point or 'CENTER', UIParent, p.relPoint or 'CENTER', p.x or 0, p.y or 0)
                    end
                end,
            }),
        })
    end
end

function S.RespaceBarAnchors(win, db)
    local sp = max(0, db.barSpacing or 1)
    local borderAdj = (db.barBorderEnabled and sp == 0) and 1 or 0
    for i = 1, S.MAX_BARS do
        local bar = win.bars[i]
        if not bar then break end
        bar.frame:ClearAllPoints()
        if i == 1 then
            bar.frame:SetPoint('TOPLEFT',  win.frame, 'TOPLEFT',  0, 0)
            bar.frame:SetPoint('TOPRIGHT', win.frame, 'TOPRIGHT', 0, 0)
        else
            bar.frame:SetPoint('TOPLEFT',  win.bars[i-1].frame, 'BOTTOMLEFT',  0, -sp + borderAdj)
            bar.frame:SetPoint('TOPRIGHT', win.bars[i-1].frame, 'BOTTOMRIGHT', 0, -sp + borderAdj)
        end
    end
end
