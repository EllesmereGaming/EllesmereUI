if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Clock.lua
-- Clock block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local wipe             = wipe
local format           = string.format
local floor            = math.floor
local max              = math.max
local min              = math.min
local date             = date

local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf

-------------------------------------------------------------------------------
--  CLOCK
-------------------------------------------------------------------------------
ns.BlockFactories.clock = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED",
                    "MAIL_INBOX_UPDATE", "UPDATE_PENDING_MAIL",
                    "UPDATE_INSTANCE_INFO", "ENCOUNTER_END", "BOSS_KILL" }

    local infoTimer, infoIndex = 0, 1
    local lastTimeStr
    local infoItems = {}
    local needsResize = false
    local isMouseOver = false
    local _fitTimeBuf = { "" }

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    -- Fixed defaults (26 / 16 off CONTENT_BASE); bar Height never scales text.
    local function FontSizeClock()
        local d = D()
        if d.fontSizeClock then return d.fontSizeClock end
        return max(12, floor(CONTENT_BASE * 0.7333 + 0.5))
    end
    local function FontSizeInfo()
        local d = D()
        if d.fontSizeInfo then return d.fontSizeInfo end
        return max(9, floor(CONTENT_BASE * 0.53 + 0.5))
    end

    -- Untouched toggles follow the game's Time Manager CVars (same source the minimap clock reads) so both clocks agree; explicit toggle overrides.
    local function ClockUses()
        local d = D()
        local useLocal = d.localTime
        if useLocal == nil then useLocal = GetCVar("timeMgrUseLocalTime") == "1" end
        local use24 = d.twentyFour
        if use24 == nil then use24 = GetCVar("timeMgrUseMilitaryTime") == "1" end
        return useLocal, use24
    end

    -- Matches the minimap clock exactly: padded hour in 24-hour mode (01:04), unpadded hour + AM/PM in 12-hour mode (1:04 PM).
    local function FormatClock(h, m, use24)
        if use24 then return format("%02d:%02d", h, m) end
        local ampm = h >= 12 and "PM" or "AM"
        h = h % 12
        if h == 0 then h = 12 end
        return format("%d:%02d %s", h, m, ampm)
    end

    local function GetTimeString()
        local useLocal, use24 = ClockUses()
        local h, m
        if useLocal then
            h = tonumber(date("%H")); m = tonumber(date("%M"))
        else
            local gh, gm = GetGameTime()
            h = floor(gh); m = floor(gm)
        end
        return FormatClock(h, m, use24)
    end

    local function RebuildInfoItems()
        -- Empty by design (mail is an icon); rotation kept for future lines.
        wipe(infoItems)
        if infoIndex > #infoItems then infoIndex = 1 end
    end

    local clockTextFrame = CreateFrame("Button", nil, content)
    clockTextFrame:SetSize(100, 20)
    clockTextFrame:SetPoint("CENTER")
    clockTextFrame:EnableMouse(true)
    clockTextFrame:RegisterForClicks("AnyUp")

    local clockText = clockTextFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, clockText)
    clockText:SetPoint("CENTER")
    clockText:SetTextColor(1, 1, 1, 1)

    local eventText = clockTextFrame:CreateFontString(nil, "OVERLAY")
    eventText:SetPoint("CENTER", clockText, "TOP", 0, 6)
    eventText:Hide()

    -- Resting indicator: Blizzard's PlayerFrame rest flipbook, replicated verbatim from
    -- Blizzard_UnitFrame/PlayerFrame.xml. MUST use SetAtlas
    -- (raw SetTexture slices the sheet's padding into the FlipBook); renders 1.5x
    -- frame size centered (transparent margins); grid 6x7 = 42 frames, 1.5s
    -- REPEAT, setToFinalAlpha. No OnUpdate -- animates only while shown.
    local restFrame = CreateFrame("Frame", nil, content)
    restFrame:SetSize(16, 21)
    restFrame:Hide()
    local restIcon = restFrame:CreateTexture(nil, "OVERLAY")
    restIcon:SetDrawLayer("OVERLAY", 7)
    -- Nudged 5px up from center; desaturated so the gold art reads white.
    restIcon:SetPoint("CENTER", restFrame, "CENTER", 0, 5)
    restIcon:SetAtlas("UI-HUD-UnitFrame-Player-Rest-Flipbook")
    restIcon:SetDesaturated(true)
    restIcon:SetVertexColor(1, 1, 1, 1)
    do
        local anim = restFrame:CreateAnimationGroup()
        anim:SetLooping("REPEAT")
        if anim.SetToFinalAlpha then anim:SetToFinalAlpha(true) end
        local flip = anim:CreateAnimation("FlipBook")
        flip:SetTarget(restIcon)
        -- 80% of Blizzard's 1.5s pace (user-tuned).
        flip:SetDuration(1.875)
        flip:SetOrder(1)
        if flip.SetSmoothing then flip:SetSmoothing("NONE") end
        flip:SetFlipBookRows(7)
        flip:SetFlipBookColumns(6)
        flip:SetFlipBookFrames(42)
        flip:SetFlipBookFrameWidth(0)
        flip:SetFlipBookFrameHeight(0)
        restFrame:SetScript("OnShow", function() anim:Play() end)
        restFrame:SetScript("OnHide", function() anim:Stop() end)
    end

    -- Mail indicator: LEFT of the clock while mail waits, gated by showMail.
    local mailIcon = clockTextFrame:CreateTexture(nil, "OVERLAY")
    mailIcon:SetAtlas("Crosshair_mail_64")
    mailIcon:Hide()

    -- One color authority: text and resting icon move together (accent on hover).
    local function ApplyClockColor()
        local r, g, b
        if isMouseOver then
            r, g, b = ns.GetAccent()
        else
            r, g, b = BlockColorOf(blockCfg)
        end
        clockText:SetTextColor(r, g, b, 1)
        restIcon:SetVertexColor(r, g, b, 1)
    end

    function inst:Refresh()
        if InCombatLockdown() then
            -- Combat: text-only refresh (insecure FontStrings, so SetText/color
            -- /shown are safe); sizing+anchoring wait for PLAYER_REGEN_ENABLED
            -- via needsResize so the clock keeps ticking.
            needsResize = true
            clockText:SetText(GetTimeString())
            ApplyClockColor()
            -- Mail can arrive mid-fight; our own texture is combat-legal.
            local dCombat = D()
            mailIcon:SetShown(dCombat.showMail ~= false and HasNewMail())
            RebuildInfoItems()
            if #infoItems > 0 then
                eventText:SetText(infoItems[infoIndex] or "")
                local r, g, b = ns.GetAccent()
                eventText:SetTextColor(r, g, b, 1)
                eventText:Show()
            else
                eventText:Hide()
            end
            local dc = D()
            if dc.showResting ~= false and IsResting() then
                restFrame:Show()
            else
                restFrame:Hide()
            end
            return
        end

        local isSide = barCtx.IsVertical()
        local barCfg = BC()
        local clockSz = FontSizeClock()
        local infoSz  = FontSizeInfo()
        local timeText = GetTimeString()
        local barH = barCtx.GetThickness()

        -- No fit-to-slot: fixed size (base font x Text Scale x Content Scale).

        ns.SetFont(clockText, clockSz, barCfg)
        clockText:SetText(timeText)
        ApplyClockColor()

        ns.SetFont(eventText, infoSz, barCfg)
        RebuildInfoItems()
        if #infoItems > 0 then
            eventText:SetText(infoItems[infoIndex] or "")
            local r, g, b = ns.GetAccent()
            eventText:SetTextColor(r, g, b, 1)
            eventText:Show()
        else
            eventText:Hide()
        end

        local dc = D()
        if dc.showResting ~= false and IsResting() then
            restFrame:Show()
        else
            restFrame:Hide()
        end
        mailIcon:SetShown(dc.showMail ~= false and HasNewMail())

        local barAtTop = barCtx.IsBarAtTop()
        -- Square frame; texture draws 1.5x centered (art has transparent margins).
        local restW = floor(CONTENT_BASE * 0.5 + 0.5)
        local restH = restW
        restFrame:SetSize(restW, restH)
        restIcon:SetSize(floor(restW * 1.5 + 0.5), floor(restH * 1.5 + 0.5))
        restFrame:ClearAllPoints()
        local mailW = restW + 8
        mailIcon:SetSize(mailW, mailW)
        mailIcon:ClearAllPoints()

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)

            content:SetWidth(slotW)
            clockTextFrame:SetWidth(slotW)
            clockTextFrame:ClearAllPoints()
            clockTextFrame:SetPoint("CENTER", content, "CENTER", 0, 0)

            ns.SetWrappedText(clockText, innerW, "CENTER")
            clockText:ClearAllPoints()
            clockText:SetPoint("TOP", clockTextFrame, "TOP", 0, -4)

            local totalH = 8 + ns.SnapToPixelGrid(clockText:GetStringHeight())
            if eventText:IsShown() then
                ns.SetWrappedText(eventText, innerW, "CENTER")
                eventText:ClearAllPoints()
                eventText:SetPoint("TOP", clockText, "BOTTOM", 0, -4)
                totalH = totalH + 4 + ns.SnapToPixelGrid(eventText:GetStringHeight())
            end

            totalH = max(totalH, barH + 8)
            content:SetHeight(totalH)
            clockTextFrame:SetHeight(totalH)

            if restFrame:IsShown() then
                restFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -2)
            end
            if mailIcon:IsShown() then
                mailIcon:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -2)
            end
        else
            local slotW = HBudget(inst, 120)
            local restExtra = 0
            if restFrame:IsShown() then restExtra = restW + 4 end
            local mailExtra = 0
            if mailIcon:IsShown() then mailExtra = mailW + 8 end
            local textBudget = max(30, slotW - restExtra - mailExtra)
            ns.SetFont(clockText, clockSz, barCfg)
            clockText:SetText(timeText)
            if #infoItems > 0 then
                ns.SetFont(eventText, infoSz, barCfg)
                eventText:SetText(infoItems[infoIndex] or "")
            end

            ns.ResetInlineText(clockText, "CENTER")
            ns.ResetInlineText(eventText, "CENTER")

            local tw = ns.SnapToPixelGrid(clockText:GetStringWidth())
            local th = ns.SnapToPixelGrid(clockText:GetStringHeight())
            if th < 1 then th = 1 end

            content:SetSize(min(slotW, max(tw, 1) + restExtra + mailExtra), th)
            clockTextFrame:SetSize(min(slotW, max(tw, 1) + restExtra + mailExtra), th)
            clockTextFrame:ClearAllPoints()
            clockTextFrame:SetPoint("CENTER")

            clockText:ClearAllPoints()
            clockText:SetPoint("CENTER")

            eventText:ClearAllPoints()
            if barAtTop then
                eventText:SetPoint("CENTER", clockText, "BOTTOM", 0, -6)
            else
                eventText:SetPoint("CENTER", clockText, "TOP", 0, 6)
            end

            if restFrame:IsShown() then
                if barAtTop then
                    restFrame:SetPoint("TOPLEFT", clockText, "TOPRIGHT", 2, -12)
                else
                    restFrame:SetPoint("BOTTOMLEFT", clockText, "BOTTOMRIGHT", 2, 12)
                end
            end
            if mailIcon:IsShown() then
                mailIcon:SetPoint("RIGHT", clockText, "LEFT", -8, 0)
            end
        end
        MaybeRelayout(inst)
    end

    -- Heartbeat: full layout pass only when the rendered HH:MM changes.
    local function ClockTick()
        infoTimer = infoTimer + 1
        if #infoItems > 1 and infoTimer >= 5 then
            infoTimer = 0
            infoIndex = (infoIndex % #infoItems) + 1
            local r, g, b = ns.GetAccent()
            eventText:SetText(infoItems[infoIndex] or "")
            eventText:SetTextColor(r, g, b, 1)
        end
        local t = GetTimeString()
        if t ~= lastTimeStr then
            lastTimeStr = t
            inst:Refresh()
        end
    end

    local function ShortenDifficulty(diffName)
        if not diffName or diffName == "" then return "" end
        local lower = diffName:lower()
        if lower:find("mythic") then return "M"
        elseif lower:find("heroic") then return "H"
        elseif lower:find("looking for raid") or lower:find("raid finder") or lower:find("lfr") then return "LFR"
        elseif lower:find("normal") then return "N"
        elseif lower:find("timewalking") then return "TW"
        elseif lower:find("story") then return "Story"
        elseif lower:find("world") then return "W"
        elseif lower:find("delve") then return "DLV"
        end
        return diffName
    end

    local function ShowClockTooltip()
        if not isMouseOver then return end
        if RequestRaidInfo then RequestRaidInfo() end
        -- Tooltips are all-white by design (no accent tinting).
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(clockTextFrame)
        -- date()'s %A/%B come from the C runtime (English in every client), so use the localized calendar globals; FULLDATE carries locale field order.
        local today = C_DateAndTime.GetCurrentCalendarTime()
        ns.Tip_AddLine(format(FULLDATE, CALENDAR_WEEKDAY_NAMES[today.weekday],
            CALENDAR_FULLDATE_MONTH_NAMES[today.month], today.monthDay, today.year), 1, 1, 1)
        local gh, gm = GetGameTime()
        local _, tipUse24 = ClockUses()
        ns.Tip_AddDouble(L["SERVER_TIME"], FormatClock(floor(gh), floor(gm), tipUse24), 0.6, 0.6, 0.6, 1, 1, 1)

        local numInstances = 0
        if GetNumSavedInstances then numInstances = GetNumSavedInstances() end
        if numInstances > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["SAVED_INSTANCES"], 1, 0.82, 0)
            local d = D()
            local showDetails = (d.lockoutDetails == true)
            for i = 1, numInstances do
                local name, _, reset, _, locked, extended, _, _, _, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
                if locked or extended then
                    local displayName = name
                    if showDetails then
                        local total = tonumber(numEncounters) or 0
                        local progress = tonumber(encounterProgress) or 0
                        local diffShort = ShortenDifficulty(difficultyName)
                        if total > 0 and diffShort ~= "" then
                            displayName = format("%s (%s %d/%d)", name, diffShort, progress, total)
                        elseif total > 0 then
                            displayName = format("%s (%d/%d)", name, progress, total)
                        elseif diffShort ~= "" then
                            displayName = format("%s (%s)", name, diffShort)
                        end
                    end
                    ns.Tip_AddDouble(displayName, ns.FormatTimeLeft(reset), 1, 1, 1, 0.6, 0.6, 0.6)
                end
            end
        end
        ns.Tip_AddLine(" ")
        local dailyReset = 0
        if GetQuestResetTime then dailyReset = GetQuestResetTime() end
        if dailyReset > 0 then
            ns.Tip_AddDouble(L["DAILY_RESET"], ns.FormatTimeLeft(dailyReset), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        local weeklyReset = 0
        if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
            weeklyReset = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
        end
        if weeklyReset > 0 then
            ns.Tip_AddDouble(L["WEEKLY_RESET"], ns.FormatTimeLeft(weeklyReset), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        if HasNewMail() then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["YOU_HAVE_MAIL"], 1, 0.82, 0)
        end
        ns.Tip_AddLine(" ")
        local r, g, b = 1, 1, 1
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["TOGGLE_CALENDAR"], 1, 1, 1, r, g, b)
        ns.Tip_AddDouble(L["RIGHT_CLICK"], L["TOGGLE_CLOCK"], 1, 1, 1, r, g, b)
        ns.Tip_AddDouble(L["SHIFT_MIDDLE_CLICK"], L["RELOAD_UI"], 1, 1, 1, r, g, b)
        ns.Tip_Show()
    end

    inst.eventFrame = MakeEventFrame(inst, function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if needsResize then needsResize = false; self:Refresh() end
        elseif event == "ENCOUNTER_END" or event == "BOSS_KILL" then
            if RequestRaidInfo then RequestRaidInfo() end
        elseif event == "UPDATE_INSTANCE_INFO" then
            if isMouseOver then
                ShowClockTooltip()
            end
        else
            self:Refresh()
        end
    end)

    clockTextFrame:SetScript("OnEnter", function()
        isMouseOver = true
        ApplyClockColor()
        ShowClockTooltip()
    end)
    clockTextFrame:SetScript("OnLeave", function()
        isMouseOver = false
        ApplyClockColor()
        ns.Tip_Hide(clockTextFrame)
    end)
    clockTextFrame:SetScript("OnClick", function(_, button)
        if button == "MiddleButton" and IsShiftKeyDown() then
            -- Never reload mid-combat: it drops the player out of the fight.
            if InCombatLockdown() then return end
            EllesmereUI.RequestReload(EllesmereUI.L("Reload UI"), EllesmereUI.L("Reload the UI now?"))
        elseif button == "LeftButton" then
            if ToggleCalendar then ToggleCalendar() end
        elseif button == "RightButton" then
            if ToggleTimeManager then ToggleTimeManager()
            elseif GameTimeFrame then GameTimeFrame:Click() end
        end
    end)

    function inst:Enable()
        content:Show()
        needsResize = false
        infoTimer = 0
        lastTimeStr = nil
        RegisterInstEvents(self)
        ns.RegisterHeartbeat("clock:" .. self.key, ClockTick)
    end

    function inst:Disable()
        ns.UnregisterHeartbeat("clock:" .. self.key)
        UnregisterInstEvents(self)
        restFrame:Hide()
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            local barH = barCtx.GetThickness()
            local textH = clockText:GetStringHeight() or FontSizeClock()
            local infoH = 0
            if eventText:IsShown() then infoH = (eventText:GetStringHeight() or 0) + 4 end
            return max(8 + textH + infoH + 8, barH, 60)
        end
        local w = clockTextFrame:GetWidth() or 80
        local dc = D()
        if dc.showResting ~= false then
            w = w + floor(CONTENT_BASE * 0.5 + 0.5) + 4
        end
        if dc.showMail ~= false and HasNewMail() then
            w = w + floor(CONTENT_BASE * 0.5 + 0.5) + 8 + 8
        end
        return max(w, 60)
    end

    function inst:Destroy()
        self._dead = true
        content:Hide()
    end

    return inst
end
