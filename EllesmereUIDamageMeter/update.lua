local addon = EllesmereUIDamageMeter
local S = addon and addon.S
if not S then return end
local LSM = LibStub('LibSharedMedia-3.0')

local floor = math.floor
local wipe = wipe
local format = format

local BACKDROP_FILL = { bgFile = 'Interface\\Buttons\\WHITE8x8' }

local GetClassColor = S.GetClassColor

function S.RefreshWindow(win)
    if not win or not win.frame or not win.header then return end
    if win.emptyText then win.emptyText:Hide() end

    local db = S.GetWinDB(win.index)

    if win.drillSource then
        local ds = win.drillSource
        local modeEntry = S.MODE_ORDER[win.modeIndex]
        local modeLabel = S.MODE_SHORT[modeEntry] or S.MODE_LABELS[modeEntry] or "?"
        local sessLabel = S.GetSessionLabel(win)

        local cr, cg, cb = GetClassColor(ds.class)
        local nameHex = cr and format("%02x%02x%02x", cr * 255, cg * 255, cb * 255) or "ffffff"
        win.header.modeText:SetText(format("|cff%s%s|r \226\128\148 %s", nameHex, ds.name, modeLabel))
        win.header.sessText:SetText(" (" .. sessLabel .. ")")
        S.ApplySessionHighlight(win, db)
        win.header.timer:Hide()

        local spells
        if S.testMode then
            local tdata = S.GetTestData(win)
            for _, td in ipairs(tdata) do
                if td.name == ds.name then spells = td.spells; break end
            end
        else
            local meterType  = S.ResolveMeterType(modeEntry)
            local sourceData = ds.guid and S.GetSessionSource(win, meterType, ds.guid)
            spells = sourceData and sourceData.combatSpells
        end

        if not spells or #spells == 0 then
            for i = 1, S.MAX_BARS do
                if win.bars[i] then win.bars[i].frame:Hide() end
            end
            return
        end

        local numVisible = S.ComputeNumVisible(win)
        local total = #spells
        win.scrollOffset = max(0, min(win.scrollOffset, max(0, total - numVisible)))

        local topVal, totalAmt = 0, 0
        for si = 1, total do
            local s = spells[si]
            local amt = s.totalAmount or s[2] or 0
            if not S.IsSecret(amt) then
                if amt > topVal then topVal = amt end
                totalAmt = totalAmt + amt
            end
        end
        if topVal == 0 then topVal = 1 end
        if totalAmt == 0 then totalAmt = 1 end

        local fgR, fgG, fgB = S.ClassOrColor(db, 'barClassColor', 'barColor', ds.class)
        local bgR, bgG, bgB, bgA = S.ClassOrColor(db, 'barBGClassColor', 'barBGColor', ds.class)
        local tR, tG, tB = S.ClassOrColor(db, 'textClassColor', 'textColor', ds.class)
        local vR, vG, vB = S.ClassOrColor(db, 'valueClassColor', 'valueColor', ds.class)

        for i = 1, S.MAX_BARS do
            local bar = win.bars[i]
            if not bar then break end
            local spIdx = win.scrollOffset + i
            local s = spells[spIdx]

            if i > numVisible or not s then
                bar.frame:Hide()
                bar.frame.drillSpellID = nil
            else
                bar.frame:Show()
                local rawSpellID = s.spellID or (type(s[1]) == "number" and s[1]) or nil
                local spellID   = (rawSpellID and not S.IsSecret(rawSpellID)) and rawSpellID or nil
                local spellName = (type(s[1]) == "string" and s[1]) or nil
                local amt       = s.totalAmount or s[2] or 0

                local iconID
                if spellID then
                    local cached = S.spellCache[spellID]
                    if cached then
                        spellName = cached.name or spellName
                        iconID = cached.icon
                    else
                        local ok, name = pcall(C_Spell.GetSpellName, spellID)
                        if ok and name then spellName = name end
                        local ok2, tex = pcall(C_Spell.GetSpellTexture, spellID)
                        if ok2 and tex then iconID = tex end
                        S.spellCache[spellID] = { name = spellName, icon = iconID }
                    end
                end
                if not spellName then spellName = "?" end

                bar.frame.drillSpellID = spellID
                bar.frame.sourceGUID   = nil
                bar.frame.testIndex    = nil

                if iconID then
                    bar.classIcon:SetTexture(iconID)
                    bar.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    bar.classIcon:Show()
                else
                    bar.classIcon:Hide()
                end

                if not bar._isDrill then
                    bar._isDrill = true
                    bar.rightText:ClearAllPoints()
                    bar.rightText:SetPoint("RIGHT", -64, 0)
                    bar.pctText:Show()
                    bar.leftText:ClearAllPoints()
                    if iconID then
                        bar.leftText:SetPoint("LEFT", bar.classIcon, "RIGHT", 2, 0)
                    else
                        bar.leftText:SetPoint("LEFT", 4, 0)
                    end
                    bar.leftText:SetPoint("RIGHT", bar.rightText, "LEFT", -4, 0)
                elseif iconID then
                    if bar._drillHasIcon ~= spellID then
                        bar.leftText:ClearAllPoints()
                        bar.leftText:SetPoint("LEFT", bar.classIcon, "RIGHT", 2, 0)
                        bar.leftText:SetPoint("RIGHT", bar.rightText, "LEFT", -4, 0)
                    end
                else
                    if bar._drillHasIcon then
                        bar.leftText:ClearAllPoints()
                        bar.leftText:SetPoint("LEFT", 4, 0)
                        bar.leftText:SetPoint("RIGHT", bar.rightText, "LEFT", -4, 0)
                    end
                end
                bar._drillHasIcon = iconID and spellID or nil

                bar.statusbar:SetStatusBarColor(fgR, fgG, fgB)
                bar.statusbar:SetMinMaxValues(0, topVal)
                bar.background:SetVertexColor(bgR, bgG, bgB, bgA)
                bar.leftText:SetText(spellName)
                bar.leftText:SetTextColor(tR, tG, tB)

                if S.IsSecret(amt) then
                    bar.statusbar:SetValue(0)
                    bar.rightText:SetText('?')
                    bar.pctText:SetText('')
                else
                    bar.statusbar:SetValue(amt)
                    bar.rightText:SetText(S.TruncateDecimals(AbbreviateNumbers(S.RoundIfPlain(amt))))
                    bar.pctText:SetText(totalAmt > 0 and format('%.1f%%', (amt / totalAmt) * 100) or '')
                end
                bar.rightText:SetTextColor(vR, vG, vB)
                bar.pctText:SetTextColor(vR * 0.7, vG * 0.7, vB * 0.7)
            end
        end
        return
    end

    if S.testMode then
        win.header.modeText:SetText("|cffff6600[Test Mode]|r")
        win.header.sessText:SetText("")
        win.header.timer:Hide()
        local tdata      = S.GetTestData(win)
        local numVisible = S.ComputeNumVisible(win)
        local maxVal     = tdata[1] and tdata[1].value or 1
        local total      = #tdata
        win.scrollOffset = max(0, min(win.scrollOffset, max(0, total - numVisible)))
        for i = 1, S.MAX_BARS do
            local bar = win.bars[i]
            if not bar then break end
            local srcIdx = win.scrollOffset + i
            local td     = tdata[srcIdx]
            if i > numVisible or not td then
                bar.frame:Hide()
            else
                bar.frame:Show()
                local fgR, fgG, fgB = S.ClassOrColor(db, 'barClassColor', 'barColor', td.class)
                bar.statusbar:SetStatusBarColor(fgR, fgG, fgB)
                bar.statusbar:SetMinMaxValues(0, maxVal)
                bar.statusbar:SetValue(td.value)
                local bgR, bgG, bgB, bgA = S.ClassOrColor(db, 'barBGClassColor', 'barBGColor', td.class)
                bar.background:SetVertexColor(bgR, bgG, bgB, bgA)
                local tR, tG, tB = S.ClassOrColor(db, 'textClassColor', 'textColor', td.class)
                if db.showRank then
                    local rr, rg, rb = S.ClassOrColor(db, 'rankClassColor', 'rankColor', td.class)
                    bar.leftText:SetText(format("|cff%02x%02x%02x%d.|r %s",
                        rr * 255, rg * 255, rb * 255, srcIdx, td.name))
                else
                    bar.leftText:SetText(td.name)
                end
                bar.leftText:SetTextColor(tR, tG, tB)
                local modeEntry = S.MODE_ORDER[win.modeIndex]
                if modeEntry == S.COMBINED_DAMAGE or modeEntry == S.COMBINED_HEALING then
                    S.FormatCombinedText(bar.rightText, td.value, td.value / 20)
                else
                    S.FormatValueText(bar.rightText, td.value)
                end
                local vR, vG, vB = S.ClassOrColor(db, 'valueClassColor', 'valueColor', td.class)
                bar.rightText:SetTextColor(vR, vG, vB)
                if bar._isDrill then S.ResetDrillBar(bar, db) end
                if bar.selfIndicator then bar.selfIndicator:Hide() end
                if db.showClassIcon then
                    S.ApplyClassIcon(bar.classIcon, db.classIconStyle, td.class)
                else
                    bar.classIcon:Hide()
                end
                bar.frame.sourceGUID   = nil
                bar.frame.sourceClass  = td.class
                bar.frame.sourceName   = td.name
                bar.frame.testIndex    = srcIdx
                bar.frame.drillSpellID = nil
            end
        end
        return
    end

    local modeEntry = S.MODE_ORDER[win.modeIndex]
    local meterType = S.ResolveMeterType(modeEntry)
    local modeLabel = S.MODE_SHORT[modeEntry] or S.MODE_LABELS[modeEntry] or "?"
    local sessLabel = S.GetSessionLabel(win)

    win.header.modeText:SetText(modeLabel)
    win.header.sessText:SetText(" \226\128\148 " .. sessLabel)
    S.ApplySessionHighlight(win, db)

    local session    = S.GetSession(win, meterType)

    if win.sessionType then
        local dur = C_DamageMeter.GetSessionDurationSeconds(win.sessionType)
        if dur and not S.IsSecret(dur) then
            local timerStr = format('%d:%02d', floor(dur / 60), floor(dur % 60))
            if session and session.totalAmount and not S.IsSecret(session.totalAmount) and session.totalAmount > 0 then
                timerStr = timerStr .. ' \194\183 ' .. S.TruncateDecimals(AbbreviateNumbers(S.RoundIfPlain(session.totalAmount)))
            end
            win.header.timer:SetText(timerStr)
        else
            win.header.timer:SetText('')
        end
    else
        win.header.timer:SetText('')
    end

    local sources    = session and session.combatSources
    local usePerSec  = (modeEntry == Enum.DamageMeterType.Dps or modeEntry == Enum.DamageMeterType.Hps)
    local useCombined = (modeEntry == S.COMBINED_DAMAGE or modeEntry == S.COMBINED_HEALING)
    local numVisible = S.ComputeNumVisible(win)
    local total      = sources and #sources or 0
    win.scrollOffset = max(0, min(win.scrollOffset, max(0, total - numVisible)))

    for i = 1, S.MAX_BARS do
        local bar = win.bars[i]
        if not bar then break end

        if i > numVisible then
            bar.frame:Hide()
        else
            local srcIdx = win.scrollOffset + i
            local src    = sources and sources[srcIdx]
            if src then
                bar.frame:Show()

                local guid = (not S.IsSecret(src.sourceGUID)) and src.sourceGUID or nil
                bar.frame.sourceGUID   = guid
                bar.frame.testIndex    = nil
                bar.frame.drillSpellID = nil

                local classFilename = src.classFilename
                if not classFilename and guid then classFilename = S.classCache[guid] end
                if guid and classFilename then S.classCache[guid] = classFilename end
                bar.frame.sourceClass = classFilename

                local fgR, fgG, fgB = S.ClassOrColor(db, 'barClassColor', 'barColor', classFilename)
                bar.statusbar:SetStatusBarColor(fgR, fgG, fgB)
                bar.statusbar:SetMinMaxValues(0, session.maxAmount or 1)
                bar.statusbar:SetValue(src.totalAmount or 0)

                local bgR, bgG, bgB, bgA = S.ClassOrColor(db, 'barBGClassColor', 'barBGColor', classFilename)
                bar.background:SetVertexColor(bgR, bgG, bgB, bgA)

                local isLocal = src.isLocalPlayer
                local specIcon = src.specIconID
                local plainName
                if isLocal then
                    local pg = UnitGUID('player')
                    plainName = (pg and S.nameCache[pg]) or UnitName('player') or '?'
                elseif guid and S.nameCache[guid] then
                    plainName = S.nameCache[guid]
                elseif specIcon and not S.specCollisions[specIcon] and S.specNameCache[specIcon] then
                    plainName = S.specNameCache[specIcon]
                elseif not S.IsSecret(src.name) and src.name and src.name ~= '' then
                    plainName = (strsplit('-', src.name))
                end
                if plainName and specIcon then
                    local existing = S.specNameCache[specIcon]
                    if existing and existing ~= plainName then
                        S.specCollisions[specIcon] = true
                    end
                    S.specNameCache[specIcon] = plainName
                end
                bar.frame.sourceName = plainName or '?'

                local tR, tG, tB = S.ClassOrColor(db, 'textClassColor', 'textColor', classFilename)
                if plainName then
                    if db.showRank then
                        local rr, rg, rb = S.ClassOrColor(db, 'rankClassColor', 'rankColor', classFilename)
                        bar.leftText:SetText(format('|cff%02x%02x%02x%d.|r %s',
                            rr * 255, rg * 255, rb * 255, srcIdx, plainName))
                    else
                        bar.leftText:SetText(plainName)
                    end
                elseif S.IsSecret(src.name) then
                    if db.showRank then
                        bar.leftText:SetFormattedText('%d. %s', srcIdx, src.name)
                    else
                        bar.leftText:SetFormattedText('%s', src.name)
                    end
                else
                    bar.leftText:SetText('?')
                end
                bar.leftText:SetTextColor(tR, tG, tB)

                if useCombined then
                    S.FormatCombinedText(bar.rightText, src.totalAmount, src.amountPerSecond)
                else
                    local rawValue = usePerSec and src.amountPerSecond or src.totalAmount
                    S.FormatValueText(bar.rightText, rawValue)
                end
                local vR, vG, vB = S.ClassOrColor(db, 'valueClassColor', 'valueColor', classFilename)
                bar.rightText:SetTextColor(vR, vG, vB)
                if bar._isDrill then S.ResetDrillBar(bar, db) end

                if db.showClassIcon then
                    S.ApplyClassIcon(bar.classIcon, db.classIconStyle, classFilename)
                else
                    bar.classIcon:Hide()
                end

                if isLocal and bar.selfIndicator then
                    bar.selfIndicator:Show()
                elseif bar.selfIndicator then
                    bar.selfIndicator:Hide()
                end
            else
                bar.frame:Hide()
                bar.frame.sourceGUID = nil
                bar.frame.sourceName = nil
            end
        end
    end

    if win.emptyText then
        if total == 0 then
            win.emptyText:Show()
        else
            win.emptyText:Hide()
        end
    end
end

function addon:RefreshMeter()
    for _, win in pairs(S.windows) do
        S.RefreshWindow(win)
    end
end

function addon:SetMeterTestMode(enabled)
    S.testMode           = enabled
    addon._meterTestMode = enabled
    addon:RefreshMeter()
end

local SetVis = EllesmereUI.SetElementVisibility

local function FadeMeterOut()
    for _, win in pairs(S.windows) do
        if win.window then SetVis(win.window, false) end
    end
    S.meterFadedOut = true
end

local function FadeMeterIn()
    for _, win in pairs(S.windows) do
        if win.window then SetVis(win.window, true) end
        local wdb = S.GetWinDB(win.index)
        if wdb and wdb.headerMouseover then
            if win.header then win.header:SetAlpha(0) end
            if win.headerBorder then win.headerBorder:SetAlpha(0) end
        end
    end
    S.meterFadedOut = false
end

local function CancelFlightFade()
    if S.flightFadeTimer then
        S.flightFadeTimer:Cancel()
        S.flightFadeTimer = nil
    end
end

function addon:UpdateMeterVisibility()
    local db = addon.db.profile
    local petBattle = db.hideInPetBattle and C_PetBattles and C_PetBattles.IsInBattle()
    local inFlight = not petBattle and db.hideInFlight and IsFlying()
    local shouldHide = petBattle or inFlight

    if shouldHide == S.meterHidden then return end
    S.meterHidden = shouldHide
    CancelFlightFade()

    if shouldHide then
        if inFlight then
            S.flightFadeTimer = C_Timer.NewTimer(0.5, FadeMeterOut)
            return
        end
        for _, win in pairs(S.windows) do
            if win.window then SetVis(win.window, false) end
        end
    else
        for _, win in pairs(S.windows) do
            if win.window then SetVis(win.window, true) end
            local wdb = S.GetWinDB(win.index)
            if wdb and wdb.headerMouseover then
                if win.header then win.header:SetAlpha(0) end
                if win.headerBorder then win.headerBorder:SetAlpha(0) end
            end
        end
        S.meterFadedOut = false
    end
end

function addon:UpdateFlightTicker()
    local db = addon.db.profile
    if db.hideInFlight and not S.flightTicker then
        S.flightTicker = C_Timer.NewTicker(1.5, function() addon:UpdateMeterVisibility() end)
    elseif not db.hideInFlight and S.flightTicker then
        S.flightTicker:Cancel()
        S.flightTicker = nil
        addon:UpdateMeterVisibility()
    end
end

local function UpdateTimers()
    for _, win in pairs(S.windows) do
        if win.header and win.header.timer and win.sessionType and win.header.timer:IsShown() then
            local dur = C_DamageMeter.GetSessionDurationSeconds(win.sessionType)
            if dur and not S.IsSecret(dur) then
                win.header.timer:SetText(format('%d:%02d', floor(dur / 60), floor(dur % 60)))
            end
        end
    end
end

function addon:ResizeMeterWindow(index)
    S.ResizeStandalone(S.windows[index])
end

function addon:UpdateMeterLayout()
    if not next(S.windows) then return end

    for _, win in pairs(S.windows) do
        local db       = S.GetWinDB(win.index)
        local fontPath = S.ResolveFontPath(db.barFont)
        local flags    = S.FontFlags(db.barFontOutline)

        local resolveTex = EllesmereUI and EllesmereUI.ResolveTexturePath
        local fgTex = resolveTex and resolveTex(S.texTextures, db.barTexture, S.DEFAULT_TEX) or S.DEFAULT_TEX
        local bgTex = resolveTex and resolveTex(S.texTextures, db.barBGTexture, S.DEFAULT_TEX) or S.DEFAULT_TEX

        S.ApplyHeaderStyle(win, db)
        S.RespaceBarAnchors(win, db)
        for i = 1, S.MAX_BARS do
            local bar = win.bars[i]
            if bar then
                S.StyleBarTexts(bar, fontPath, db.barFontSize, flags)
                bar.statusbar:SetStatusBarTexture(fgTex)
                bar.background:SetTexture(bgTex)
                S.ApplyBarIconLayout(bar, db)
                S.ApplyBarBorder(bar, db)
            end
        end

        if win.frame then
            if db.showBackdrop then
                win.frame:SetBackdrop(BACKDROP_FILL)
                local bc = db.backdropColor
                if bc then
                    win.frame:SetBackdropColor(bc.r, bc.g, bc.b, bc.a)
                else
                    win.frame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                end
            else
                win.frame:SetBackdrop(nil)
            end
        end

        if win.headerBorder then
            if db.showHeaderBorder then
                win.headerBorder:Show()
            else
                win.headerBorder:Hide()
            end
        end

        if win.header and win.header.bg then
            if db.showHeaderBackdrop then
                win.header.bg:Show()
            else
                win.header.bg:Hide()
            end
        end

        if win.header then
            S.SetupHeaderMouseover(win)
            if db.headerMouseover then
                win.header:SetAlpha(0)
                if win.headerBorder then win.headerBorder:SetAlpha(0) end
            else
                win.header:SetAlpha(1)
                if win.headerBorder then win.headerBorder:SetAlpha(1) end
            end
        end

        S.ResizeStandalone(win)
    end

    addon:RefreshMeter()
end

function addon:InitDamageMeter()
    if not addon.db or not addon.db.profile.enabled then return end

    SetCVar('damageMeterEnabled', 0)

    C_Timer.After(0, function()
        local db = addon.db.profile

        local win1 = S.NewWindowState(1, db.modeIndex)
        S.windows[1] = win1
        S.CreateMeterFrame(win1)

        if not win1.frame then return end

        local function OnTDMEvent(_, event)
            if event == 'PET_BATTLE_OPENING_START' or event == 'PET_BATTLE_CLOSE' then
                addon:UpdateMeterVisibility()
                return
            elseif event == 'PLAYER_REGEN_DISABLED' then
                for _, w in pairs(S.windows) do
                    S.ExitDrillDown(w)
                end
                return
            elseif event == 'PLAYER_REGEN_ENABLED' then
                S.ScanRoster()
                addon:RefreshMeter()
                return
            elseif event == 'GROUP_ROSTER_UPDATE' then
                S.ScanRoster()
                return
            elseif event == 'PLAYER_ENTERING_WORLD' then
                wipe(S.nameCache)
                wipe(S.classCache)
                wipe(S.specNameCache)
                wipe(S.specCollisions)
                wipe(S.sessionLabelCache)
                S.ScanRoster()
                for _, w in pairs(S.windows) do
                    S.ResetWindowState(w)
                end
                if addon.db.profile.autoResetOnComplete then
                    local _, instanceType = IsInInstance()
                    if instanceType == 'party' or instanceType == 'raid' or instanceType == 'scenario' then
                        C_DamageMeter.ResetAllCombatSessions()
                    end
                end
                addon:RefreshMeter()
            elseif event == 'DAMAGE_METER_RESET' then
                wipe(S.sessionLabelCache)
                wipe(S.nameCache)
                wipe(S.classCache)
                wipe(S.specNameCache)
                wipe(S.specCollisions)
                for _, w in pairs(S.windows) do
                    S.ResetWindowState(w)
                end
                addon:RefreshMeter()
            else
                wipe(S.sessionLabelCache)
                addon:RefreshMeter()
            end
        end

        S.ScanRoster()
        addon:RegisterEvent('DAMAGE_METER_COMBAT_SESSION_UPDATED', OnTDMEvent)
        addon:RegisterEvent('DAMAGE_METER_CURRENT_SESSION_UPDATED', OnTDMEvent)
        addon:RegisterEvent('DAMAGE_METER_RESET', OnTDMEvent)
        addon:RegisterEvent('PLAYER_ENTERING_WORLD', OnTDMEvent)
        addon:RegisterEvent('PLAYER_REGEN_DISABLED', OnTDMEvent)
        addon:RegisterEvent('PLAYER_REGEN_ENABLED', OnTDMEvent)
        addon:RegisterEvent('GROUP_ROSTER_UPDATE', OnTDMEvent)
        addon:RegisterEvent('PET_BATTLE_OPENING_START', OnTDMEvent)
        addon:RegisterEvent('PET_BATTLE_CLOSE', OnTDMEvent)
        if not S.timerTicker then
            S.timerTicker = C_Timer.NewTicker(0.5, UpdateTimers)
        end

        addon:UpdateFlightTicker()
        addon:RefreshMeter()
    end)
end

function addon:OnEnable()
    self:InitDamageMeter()
end

function addon:ReportMeter(channel, count, winIndex)
    count = count or 5
    winIndex = winIndex or 1
    local win = S.windows[winIndex]
    if not win then return end

    local modeEntry = S.MODE_ORDER[win.modeIndex]
    local meterType = S.ResolveMeterType(modeEntry)
    local modeLabel = S.MODE_LABELS[modeEntry] or "?"
    local sessLabel = S.GetSessionLabel(win)
    local session   = S.GetSession(win, meterType)
    local sources   = session and session.combatSources

    if not sources or #sources == 0 then
        print("|cff0cd39cEUI DM:|r No data to report.")
        return
    end

    if not channel then
        if IsInRaid() then
            channel = 'RAID'
        elseif IsInGroup() then
            channel = 'PARTY'
        else
            channel = 'SAY'
        end
    end

    local usePerSec = (modeEntry == Enum.DamageMeterType.Dps or modeEntry == Enum.DamageMeterType.Hps)
    SendChatMessage(format("EUI DM: %s — %s", modeLabel, sessLabel), channel)
    for i = 1, min(count, #sources) do
        local src = sources[i]
        local name = '?'
        local guid = (not S.IsSecret(src.sourceGUID)) and src.sourceGUID or nil
        if src.isLocalPlayer then
            name = UnitName('player') or '?'
        elseif guid and S.nameCache[guid] then
            name = S.nameCache[guid]
        elseif not S.IsSecret(src.name) and src.name then
            name = (strsplit('-', src.name))
        end
        local val = usePerSec and src.amountPerSecond or src.totalAmount
        local valStr = val and S.TruncateDecimals(AbbreviateNumbers(S.RoundIfPlain(val))) or '0'
        SendChatMessage(format("  %d. %s — %s", i, name, valStr), channel)
    end
end

SLASH_EUIDM1 = '/euidm'
SlashCmdList['EUIDM'] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == 'toggle' then
        for _, win in pairs(S.windows) do
            if win.window then
                if win.window:IsShown() then
                    win.window:Hide()
                else
                    win.window:Show()
                end
            end
        end
    elseif cmd == 'test' then
        addon:SetMeterTestMode(not S.testMode)
    elseif cmd == 'reset' then
        C_DamageMeter.ResetAllCombatSessions()
        addon:RefreshMeter()
    elseif cmd:match('^report') then
        local channel = cmd:match('^report%s+(%a+)')
        if channel then channel = channel:upper() end
        addon:ReportMeter(channel)
    else
        print("|cff0cd39cEUI DM|r commands:")
        print("  /euidm toggle — show/hide")
        print("  /euidm test — toggle test mode")
        print("  /euidm reset — reset sessions")
        print("  /euidm report [channel] — report top 5")
    end
end
