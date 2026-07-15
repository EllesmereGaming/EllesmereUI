-- EllesmereUIDataBars_Blocks.lua
-- Per-instance block factories for the DataBars multi-bar engine.
--
-- Contract (engine calls, see EllesmereUIDataBars.lua):
--   ns.BlockFactories[typeKey] = function(blockCfg, slot, content, barCtx) -> inst
--   inst:Refresh()        re-read settings + game state, update visuals,
--                         re-measure; requests re-layout when the measured
--                         auto extent changed
--   inst:Enable()         register events + heartbeat (idempotent)
--   inst:Disable()        unregister everything (safe to call twice)
--   inst:GetAutoLength()  content extent along the bar axis (px)
--   inst:Destroy()        full teardown; secure frames park OOC
--
-- All frames created here are OURS (CreateFrame by this file), so SetScript
-- and custom fields are allowed. The only Blizzard frames touched are the
-- micro menu containers (via a SecureHandlerStateTemplate hider) and the
-- Blizzard MicroButtons / ProfessionMicroButton (via secure attributes).

local ADDON_NAME, ns = ...
local L = ns.L
local MEDIA = ns.MEDIA

-- Upvalues
local _G                = _G
local CreateFrame       = CreateFrame
local UIParent          = UIParent
local InCombatLockdown  = InCombatLockdown
local C_Timer           = C_Timer
local GetTime           = GetTime
local pairs, ipairs     = pairs, ipairs
local type, select      = type, select
local pcall             = pcall
local rawget            = rawget
local wipe              = wipe
local format            = string.format
local tinsert, tremove  = table.insert, table.remove
local tconcat, tsort    = table.concat, table.sort
local floor             = math.floor
local max, min, abs     = math.max, math.min, math.abs
local mrandom           = math.random
local unpack            = unpack
local date              = date

-------------------------------------------------------------------------------
--  Shared per-instance scaffolding
-------------------------------------------------------------------------------
local function InstKey(barCtx, blockCfg)
    return "EDB" .. barCtx.id .. "_" .. blockCfg.id
end

local function MakeEventFrame(inst, handler)
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, ...) handler(inst, event, ...) end)
    return f
end

local function RegisterInstEvents(inst)
    if not (inst.eventFrame and inst.events) then return end
    for i = 1, #inst.events do
        pcall(inst.eventFrame.RegisterEvent, inst.eventFrame, inst.events[i])
    end
end

local function UnregisterInstEvents(inst)
    if inst.eventFrame then inst.eventFrame:UnregisterAllEvents() end
end

-- Content sizing baseline: fonts and icons derive from this CONSTANT, never
-- the live bar thickness -- the bar's Height setting only resizes the BAR
-- itself. Content size is controlled by Text Scale / Content Scale / the
-- per-block font settings. (30 = the default thickness the classic content
-- ratios were tuned against.)
local CONTENT_BASE = 30

-- Content scale of a block: content frames are SetScale'd as a group, so
-- fit budgets must convert slot pixels into the content's own coordinate
-- space (slot / scale).
local function ContentScaleOf(inst)
    local s = ((inst.cfg and inst.cfg.scale) or 100) / 100
    if s <= 0 then return 1 end
    return s
end

-- Horizontal text budget: every block fits into its solver-assigned slot
-- width (sizing is share-based for auto and fixed blocks alike).
local function HBudget(inst, fallback)
    local w = inst.slot and inst.slot:GetWidth()
    if w and w > 8 then return w / ContentScaleOf(inst) end
    return fallback
end

-- Vertical cross-axis width (bar thickness; falls back when the slot has
-- not been laid out yet).
local function VSlotW(inst)
    local w = inst.slot and inst.slot:GetWidth()
    if w and w > 2 then return w / ContentScaleOf(inst) end
    return inst.ctx.GetThickness()
end

-- Request a re-layout only when the measured auto extent actually changed
-- (breaks the Refresh -> layout -> Refresh feedback loop). Only auto-mode
-- bars size from content, and the fill block's px is the remainder -- its
-- own content never drives layout.
local function MaybeRelayout(inst)
    local b = inst.cfg
    local barCfg = inst.ctx and inst.ctx.cfg
    if not barCfg or ns.BarSizingMode(barCfg) ~= "auto" then return end
    if barCfg.fillBlockId == b.id then return end
    local w = 0
    if inst.GetAutoLength then w = inst:GetAutoLength() or 0 end
    if inst._lastAuto == nil or abs(w - inst._lastAuto) > 0.5 then
        inst._lastAuto = w
        inst.ctx.RequestLayout()
    end
end

-- Text-only X/Y offset (b.textXOff/b.textYOff): wraps a PRIMARY text
-- FontString's SetPoint so every anchor the factory ever gives it --
-- creation and every mode-dependent re-anchor alike -- carries the offset
-- read live from the cfg. Wrap ONLY texts anchored to non-text targets:
-- texts chained to a wrapped one (bagText -> goldText, eventText ->
-- clockText, cooldownText -> hearthText, infoText -> specText) follow it
-- through their anchor and would double-shift if wrapped too. These are
-- OUR FontStrings, so shadowing the method on the widget table is safe.
-- Offset changes re-render via ns.ReflowBlocks (factories re-anchor in
-- Refresh).
local function AttachTextOffset(inst, fs)
    if not fs or fs._edbTxo then return end
    fs._edbTxo = true
    local orig = fs.SetPoint
    fs.SetPoint = function(self, point, a2, a3, a4, a5)
        local c = inst.cfg
        local dx = (c and c.textXOff) or 0
        local dy = (c and c.textYOff) or 0
        if a2 == nil then
            return orig(self, point, dx, dy)
        end
        if type(a2) == "number" then
            return orig(self, point, a2 + dx, (a3 or 0) + dy)
        end
        return orig(self, point, a2, a3 or point, (a4 or 0) + dx, (a5 or 0) + dy)
    end
end

-- Per-block content color (options Color row: Custom/Class/Accent
-- swatches; default custom white). Colors the block's TEXT and
-- vertex-tints its ICONS; status-bar fills are unaffected, and
-- state-driven colors (hover accent, travel's cooldown red) still take
-- precedence at their sites.
local function BlockColorOf(b)
    if b.useClassColor then
        local _, classFile = UnitClass("player")
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then return cc.r, cc.g, cc.b end
    elseif b.useAccentColor then
        return ns.GetAccent()
    end
    local c = b.color
    if c then return c.r or 1, c.g or 1, c.b or 1 end
    return 1, 1, 1
end

-- Retire a secure frame: hide + reparent to the engine park frame, deferred
-- to out-of-combat when needed (alpha-hidden immediately in combat).
local function ParkSecureFrame(f, key)
    if not f then return end
    if InCombatLockdown() then
        f:SetAlpha(0)
        ns.DeferUntilOOC("edbkill:" .. key, function()
            f:Hide()
            f:SetParent(ns._park)
        end)
    else
        f:Hide()
        f:SetParent(ns._park)
    end
end

-------------------------------------------------------------------------------
--  CLOCK
-------------------------------------------------------------------------------
ns.BlockFactories.clock = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED",
                    "MAIL_INBOX_UPDATE", "UPDATE_PENDING_MAIL" }

    local infoTimer, infoIndex = 0, 1
    local lastTimeStr
    local infoItems = {}
    local needsResize = false
    local isMouseOver = false
    local _fitTimeBuf = { "" }

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    -- Fixed content defaults (26 / 16 off CONTENT_BASE): the bar's Height
    -- setting never scales the clock text.
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

    local function GetTimeString()
        local d = D()
        local h, m
        if d.localTime ~= false then
            h = tonumber(date("%H")); m = tonumber(date("%M"))
        else
            local gh, gm = GetGameTime()
            h = floor(gh); m = floor(gm)
        end
        if d.twentyFour == false then
            if h > 12 then h = h - 12 end
            if h == 0 then h = 12 end
            return format("%d:%02d", h, m)
        end
        return format("%02d:%02d", h, m)
    end

    local function RebuildInfoItems()
        -- (Mail left the rotating text: it is the mail ICON beside the
        -- clock now. The rotation machinery stays for future info lines.)
        wipe(infoItems)
        if infoIndex > #infoItems then infoIndex = 1 end
    end

    -- Frames
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

    -- Resting indicator: Blizzard's PlayerFrame rest flipbook, replicated
    -- verbatim from Blizzard_UnitFrame/PlayerFrame.xml. The texture MUST
    -- be set via the ATLAS (the sheet is a sub-rect of the file; a raw
    -- SetTexture makes the FlipBook slice the padding too), it renders
    -- 1.5x the frame size center-anchored (the art has transparent
    -- margins), and the grid is 6 columns x 7 rows, 42 frames, 1.5s
    -- REPEAT with setToFinalAlpha. No OnUpdate: the animation only runs
    -- while the frame is shown.
    local restFrame = CreateFrame("Frame", nil, content)
    restFrame:SetSize(16, 21)
    restFrame:Hide()
    local restIcon = restFrame:CreateTexture(nil, "OVERLAY")
    restIcon:SetDrawLayer("OVERLAY", 7)
    -- Nudged 5px up from the frame center (user-tuned), desaturated so the
    -- gold Blizzard art reads white.
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

    -- Mail indicator: shown LEFT of the clock while unread mail waits
    -- (replaced the old "You've got mail!" rotating text line). Gated by
    -- the same Mail Alert (showMail) setting.
    local mailIcon = clockTextFrame:CreateTexture(nil, "OVERLAY")
    mailIcon:SetAtlas("Crosshair_mail_64")
    mailIcon:Hide()

    -- One color authority for the clock: text and resting icon follow the
    -- block's color selection together (accent while hovered).
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
            -- Combat: text-only refresh -- every region here is an insecure
            -- FontString/frame, so SetText/colors/shown-state are safe. Only
            -- the sizing/anchoring below waits for PLAYER_REGEN_ENABLED via
            -- needsResize, so the time keeps ticking through long fights.
            needsResize = true
            clockText:SetText(GetTimeString())
            ApplyClockColor()
            -- Mail can arrive mid-fight; showing/hiding our own texture is
            -- combat-legal (geometry still waits for needsResize).
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

        -- No fit-to-slot: content renders at its fixed size (base font x
        -- Text Scale x Content Scale) regardless of the block's share.

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
        -- Square frame; the texture draws 1.5x the frame size, centered
        -- (Blizzard's 30-on-20 ratio -- the art has transparent margins).
        -- 0.5 ratio = 25% smaller than the original 0.66 (user-tuned).
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

    inst.eventFrame = MakeEventFrame(inst, function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if needsResize then needsResize = false; self:Refresh() end
        else
            self:Refresh()
        end
    end)

    clockTextFrame:SetScript("OnEnter", function()
        isMouseOver = true
        ApplyClockColor()
        -- Tooltips are all-white by design (no accent tinting).
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(clockTextFrame)
        ns.Tip_AddLine(date("%A %d %B %Y"), 1, 1, 1)
        local gh, gm = GetGameTime()
        ns.Tip_AddDouble(L["SERVER_TIME"], format("%02d:%02d", floor(gh), floor(gm)), 0.6, 0.6, 0.6, 1, 1, 1)

        local numInstances = 0
        if GetNumSavedInstances then numInstances = GetNumSavedInstances() end
        if numInstances > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["SAVED_INSTANCES"], 1, 0.82, 0)
            for i = 1, numInstances do
                local name, _, reset, _, locked, extended = GetSavedInstanceInfo(i)
                if locked or extended then
                    ns.Tip_AddDouble(name, ns.FormatTimeLeft(reset), 1, 1, 1, 0.6, 0.6, 0.6)
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
    end)
    clockTextFrame:SetScript("OnLeave", function()
        isMouseOver = false
        ApplyClockColor()
        ns.Tip_Hide(clockTextFrame)
    end)
    clockTextFrame:SetScript("OnClick", function(_, button)
        if button == "MiddleButton" and IsShiftKeyDown() then
            -- Never reload mid-combat: an accidental shift-middle during a
            -- pull would drop the player out of the fight.
            if InCombatLockdown() then return end
            ReloadUI()
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

-------------------------------------------------------------------------------
--  FPS + MS (separate block types built on one single-line stat renderer)
-------------------------------------------------------------------------------
-- Game-wide addon memory scan cache (fps tooltip; shared by design).
local sysMemTable = {}
local function sysMemSort(a, b) return a.mem > b.mem end
local sysLastMemScanTime = 0

local FPS_THRESHOLD, LAT_THRESHOLD = 60, 60
local function GetFPSColor(fps)
    local lb = FPS_THRESHOLD * 0.5
    local perc = 1
    if fps < FPS_THRESHOLD then perc = (fps - lb) / lb end
    return ns.SlowColorGradient(perc)
end
local function GetLatColor(lat)
    local perc = 1
    if lat > LAT_THRESHOLD then perc = 1 - (lat - LAT_THRESHOLD) / LAT_THRESHOLD end
    return ns.SlowColorGradient(perc)
end

-- Shared single-line stat block (icon + value text). opts:
--   hbPrefix   heartbeat key prefix
--   texture    icon file
--   interval   heartbeat SECONDS between samples (1 = every tick)
--   sample()   -> current value (number)
--   suffix()   -> display suffix string
--   tooltip(inst, skipScan)  owned-tooltip builder
--   click(inst, isOverFn)    optional OnClick factory
local function MakeStatBlock(blockCfg, slot, content, barCtx, opts)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local mouseOver = false
    local lastVal = -1
    local tickCount = 0
    local _fitBuf = { "" }

    local frame = CreateFrame("Button", nil, content)
    frame:SetSize(60, 20); frame:EnableMouse(true); frame:RegisterForClicks("AnyUp")
    -- Icon is optional: blocks without opts.texture are text-only.
    local icon
    if opts.texture then
        icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(opts.texture); icon:SetPoint("LEFT")
    end
    local text = frame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, text)
    text:SetPoint("LEFT")
    -- Hidden ruler: the block's width is reserved from a stable TEMPLATE,
    -- never the live string, so value changes cannot shift neighbors.
    local measureFS = frame:CreateFontString(nil, "OVERLAY")
    measureFS:Hide()

    -- Hover feedback is COLOR ONLY: never re-samples or re-renders the value.
    local function ApplyColors()
        local r, g, b
        if mouseOver then
            r, g, b = ns.GetAccent()
        else
            r, g, b = BlockColorOf(blockCfg)
        end
        text:SetTextColor(r, g, b, 1)
        if icon then icon:SetVertexColor(r, g, b, 1) end
    end

    function inst:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        -- 0.4333 ratio = 13px at the 30 base (stat blocks run 1px smaller
        -- than the standard 0.46 block text by user direction).
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local d = D()
        local gap = 3
        local isSide = barCtx.IsVertical()
        if lastVal < 0 then lastVal = opts.sample() end
        local str = lastVal .. opts.suffix()

        local iconSz = 0
        if icon and d.showIcon ~= false then
            iconSz = fontSize + (opts.iconExtra or 0)
        end

        -- No fit-to-slot: content renders at its fixed size (base font x
        -- Text Scale x Content Scale) regardless of the block's share.

        ns.SetFont(text, fontSize, barCfg)
        text:SetText(str)
        ApplyColors()

        if iconSz > 0 then
            icon:SetSize(iconSz, iconSz)
            icon:Show()
        elseif icon then
            icon:Hide()
        end

        if InCombatLockdown() then return end

        local lineH = max(fontSize + 4, iconSz)
        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(36, slotW - 8)
            frame:SetSize(innerW, lineH)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", content, "CENTER", 0, 0)
            if iconSz > 0 then
                icon:ClearAllPoints(); icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
                text:ClearAllPoints(); text:SetPoint("LEFT", icon, "RIGHT", gap, 0)
                ns.SetWrappedText(text, max(16, innerW - iconSz - gap - 2), "LEFT")
            else
                text:ClearAllPoints(); text:SetPoint("CENTER", frame, "CENTER", 0, 0)
                ns.SetWrappedText(text, innerW, "CENTER")
            end
            content:SetSize(slotW, max(lineH + 8, barH))
        else
            ns.ResetInlineText(text, "LEFT")
            local iconPad = 0
            if iconSz > 0 then
                iconPad = iconSz + gap
                icon:ClearAllPoints(); icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
            end
            text:ClearAllPoints()
            text:SetPoint("LEFT", frame, "LEFT", iconPad, 0)
            -- Reserve width from a template: every digit becomes "8" and
            -- the numeric part pads to at least 3 digits, so the width only
            -- moves on a digit-count crossing past 3 (e.g. 999ms -> 1000ms),
            -- never on ordinary value changes. Icon and number stay
            -- LEFT-anchored; the slack sits on the right.
            local digits = #tostring(lastVal)
            if digits < 3 then digits = 3 end
            ns.SetFont(measureFS, fontSize, barCfg)
            measureFS:SetText(string.rep("8", digits) .. opts.suffix())
            local w = iconPad + ns.SnapToPixelGrid(measureFS:GetStringWidth() or 30) + 2
            if w < 30 then w = 30 end
            frame:SetSize(w, barH)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", content, "CENTER", 0, 0)
            content:SetSize(w, barH)
        end
        MaybeRelayout(inst)
    end

    local function Tick()
        tickCount = tickCount + 1
        if tickCount < (opts.interval or 1) then return end
        tickCount = 0
        local v = opts.sample()
        if v == lastVal then return end
        lastVal = v
        inst:Refresh()
        if mouseOver then opts.tooltip(inst, true) end
    end

    frame:SetScript("OnEnter", function()
        mouseOver = true
        ApplyColors()
        opts.tooltip(inst, false)
    end)
    frame:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(content)
        ApplyColors()
    end)
    if opts.click then
        frame:SetScript("OnClick", opts.click(inst, function() return mouseOver end))
    end

    function inst:Enable()
        content:Show()
        lastVal = -1
        -- Sample on the very first tick regardless of interval.
        tickCount = (opts.interval or 1) - 1
        ns.RegisterHeartbeat(opts.hbPrefix .. ":" .. self.key, Tick)
    end

    function inst:Disable()
        ns.UnregisterHeartbeat(opts.hbPrefix .. ":" .. self.key)
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 40)
        end
        return max(content:GetWidth() or 70, 40)
    end

    function inst:Destroy()
        self._dead = true
        content:Hide()
    end

    return inst
end

ns.BlockFactories.fps = function(blockCfg, slot, content, barCtx)
    local function FpsTooltip(inst, skipMemoryScan)
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(content)
        local fps = floor(GetFramerate())
        local fr2, fg2, fb2 = GetFPSColor(fps)
        ns.Tip_AddDouble(L["FPS"], fps .. ns.GetFPSSuffix(), 0.6, 0.6, 0.6, fr2, fg2, fb2)

        local now = GetTime()
        -- UpdateAddOnMemoryUsage() iterates every loaded addon and is a
        -- noticeable spike; amortise the rescan to once per 30s.
        if not skipMemoryScan and (now - sysLastMemScanTime) >= 30 then
            sysLastMemScanTime = now
            UpdateAddOnMemoryUsage()
            local count = 0
            for i = 1, C_AddOns.GetNumAddOns() do
                local _, name = C_AddOns.GetAddOnInfo(i)
                local mem = GetAddOnMemoryUsage(i)
                if mem > 0 then
                    count = count + 1
                    if not sysMemTable[count] then sysMemTable[count] = {} end
                    sysMemTable[count].name = name
                    sysMemTable[count].mem = mem
                end
            end
            for i = count + 1, #sysMemTable do sysMemTable[i] = nil end
            tsort(sysMemTable, sysMemSort)
        end

        if #sysMemTable > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["MEMORY_USAGE"], ar, ag, ab)
            ns.Tip_AddLine(" ")
            for i = 1, min(10, #sysMemTable) do
                local ms
                if sysMemTable[i].mem > 1024 then
                    ms = format("%.2f MB", sysMemTable[i].mem / 1024)
                else
                    ms = format("%.0f KB", sysMemTable[i].mem)
                end
                ns.Tip_AddDouble(sysMemTable[i].name, ms, 1, 1, 1, ar, ag, ab)
            end
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["SHIFT_LEFT_CLICK"], L["FORCE_GC"], 1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end

    return MakeStatBlock(blockCfg, slot, content, barCtx, {
        hbPrefix = "fps",
        interval = 3,
        sample   = function() return floor(GetFramerate()) end,
        suffix   = function() return ns.GetFPSSuffix() end,
        tooltip  = FpsTooltip,
        click    = function(inst, isOver)
            return function(_, button)
                if button ~= "LeftButton" then return end
                -- A full GC cycle stalls a frame; only force it when Shift
                -- is held so a casual click just prints the snapshot.
                if IsShiftKeyDown() then collectgarbage("collect") end
                local memKb = collectgarbage("count")
                local msg
                if memKb > 1024 then msg = format("%.2f MB", memKb / 1024) else msg = format("%.0f KB", memKb) end
                print("|cff0cd29fDataBars|r: Memory usage snapshot |cffffff00" .. msg .. "|r")
                if isOver() then FpsTooltip(inst, false) end
            end
        end,
    })
end

ns.BlockFactories.ms = function(blockCfg, slot, content, barCtx)
    local function MsTooltip()
        ns.Tip_Begin(content)
        local _, _, home, world = GetNetStats()
        home = floor(home); world = floor(world)
        local hr, hg, hb = GetLatColor(home)
        local wr, wg, wb = GetLatColor(world)
        ns.Tip_AddDouble(L["HOME"],  home .. ns.GetMSSuffix(), 0.6, 0.6, 0.6, hr, hg, hb)
        ns.Tip_AddDouble(L["WORLD"], world .. ns.GetMSSuffix(), 0.6, 0.6, 0.6, wr, wg, wb)
        ns.Tip_Show()
    end

    return MakeStatBlock(blockCfg, slot, content, barCtx, {
        hbPrefix = "ms",
        interval = 1,
        sample   = function()
            local d = blockCfg.settings or {}
            local _, _, home, world = GetNetStats()
            if d.useWorldLatency then return floor(world) end
            return floor(home)
        end,
        suffix   = function() return ns.GetMSSuffix() end,
        tooltip  = MsTooltip,
    })
end

ns.BlockFactories.durability = function(blockCfg, slot, content, barCtx)
    -- Same reading as the Chat sidebar's durability icon: the LOWEST
    -- percent across equipped slots 1-18.
    local function SampleDurability()
        local lowest = 100
        for slotId = 1, 18 do
            local cur, mx = GetInventoryItemDurability(slotId)
            if cur and mx and mx > 0 then
                local pct = cur / mx * 100
                if pct < lowest then lowest = pct end
            end
        end
        return floor(lowest)
    end

    local function DurabilityTooltip()
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(content)
        ns.Tip_AddDouble("Equipment Durability", SampleDurability() .. "%",
            0.6, 0.6, 0.6, ar, ag, ab)
        ns.Tip_Show()
    end

    return MakeStatBlock(blockCfg, slot, content, barCtx, {
        hbPrefix = "durability",
        -- Reuses the Chat sidebar's durability icon; its art reads small,
        -- so it draws 10px larger than the other stat icons.
        texture  = "Interface\\AddOns\\EllesmereUIChat\\media\\chat_durability.png",
        iconExtra = 10,
        interval = 2,
        sample   = SampleDurability,
        suffix   = function() return "%" end,
        tooltip  = DurabilityTooltip,
    })
end

-------------------------------------------------------------------------------
--  GOLD (engine-level session ledger + cross-character store)
-------------------------------------------------------------------------------
-- One PLAYER_MONEY ledger shared by every gold instance; instances render
-- from it and ctrl-right-click resets the shared session.
local goldLedger = { profit = 0, spent = 0, lastMoney = nil, tokenPrice = nil }
local goldInstances = {}
local goldEventFrame

local function GoldCharKey()
    return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
end

local function GoldStore()
    local profile = ns.GetProfile()
    if not profile then return {} end
    profile.characters = profile.characters or {}
    return profile.characters
end

local function GoldSaveCurrentMoney(money)
    local store = GoldStore()
    local _, class = UnitClass("player")
    store[GoldCharKey()] = { currentMoney = money, class = class, realm = GetRealmName(), name = UnitName("player") }
end

local function GoldLedgerUpdate()
    local money = GetMoney()
    if goldLedger.lastMoney then
        local diff = money - goldLedger.lastMoney
        if diff > 0 then goldLedger.profit = goldLedger.profit + diff
        elseif diff < 0 then goldLedger.spent = goldLedger.spent + (-diff) end
    end
    goldLedger.lastMoney = money
    GoldSaveCurrentMoney(money)
end

local function GoldOnEvent(_, event)
    if event == "TOKEN_MARKET_PRICE_UPDATED" then
        if C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice then
            goldLedger.tokenPrice = C_WowTokenPublic.GetCurrentMarketPrice()
        end
        return
    end
    -- BAG_UPDATE changes bag slots only, never money.
    if event ~= "BAG_UPDATE" then GoldLedgerUpdate() end
    for gi in pairs(goldInstances) do
        gi:QueueRefresh()
    end
end

local function UpdateGoldEvents()
    if next(goldInstances) then
        if not goldEventFrame then
            goldEventFrame = CreateFrame("Frame")
            goldEventFrame:SetScript("OnEvent", GoldOnEvent)
        end
        goldEventFrame:RegisterEvent("PLAYER_MONEY")
        goldEventFrame:RegisterEvent("BAG_UPDATE")
        goldEventFrame:RegisterEvent("TOKEN_MARKET_PRICE_UPDATED")
    elseif goldEventFrame then
        goldEventFrame:UnregisterAllEvents()
    end
end

local function GetFreeBagSlots()
    local free = 0
    for i = 0, 4 do
        local n = C_Container and C_Container.GetContainerNumFreeSlots(i)
        if n then free = free + n end
    end
    return free
end

ns.BlockFactories.gold = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)

    local GOLD_TEX = MEDIA .. "lootbag.png"
    local _goldFitBuf = { "", "" }
    local mouseOver = false

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local _sideLinesBuf = { "", "", "" }
    local _sideLineCount = 0
    local function GetMoneySideLines(amount, showSmall)
        amount = floor(abs(amount or 0))
        local gold   = floor(amount / 10000)
        local silver = floor((amount % 10000) / 100)
        local copper = amount % 100
        local gStr
        if BreakUpLargeNumbers then gStr = BreakUpLargeNumbers(gold) else gStr = tostring(gold) end
        _sideLinesBuf[1] = gStr .. L["GOLD_SUFFIX"]
        if showSmall ~= false then
            _sideLinesBuf[2] = silver .. L["SILVER_SUFFIX"]
            _sideLinesBuf[3] = copper .. L["COPPER_SUFFIX"]
            _sideLineCount = 3
        else
            _sideLinesBuf[2] = nil
            _sideLinesBuf[3] = nil
            _sideLineCount = 1
        end
        return _sideLinesBuf, _sideLineCount
    end

    local goldButton = CreateFrame("Button", nil, content)
    goldButton:SetSize(120, 20); goldButton:SetPoint("CENTER")
    goldButton:EnableMouse(true); goldButton:RegisterForClicks("AnyUp")

    local goldIcon = goldButton:CreateTexture(nil, "OVERLAY"); goldIcon:SetTexture(GOLD_TEX)
    local goldText = goldButton:CreateFontString(nil, "OVERLAY")
    local bagText  = goldButton:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, goldText)   -- bagText chains to goldText

    function inst:Refresh()
        local dg = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        -- 0.4333 ratio = 13px at the 30 base (matches the stat blocks).
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local iconSz = 0
        if dg.showIcons ~= false then iconSz = fontSize end
        local gap = 4
        local isSide = barCtx.IsVertical()

        ns.SetFont(goldText, fontSize, barCfg)
        ns.SetFont(bagText, fontSize, barCfg)

        local money = GetMoney()
        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local lines, lineCount = GetMoneySideLines(money, dg.showSmall == true)
            local startSize = min(fontSize, max(10, floor(CONTENT_BASE * 0.52 + 0.5)))
            local goldFontSize = startSize
            ns.SetFont(goldText, goldFontSize, barCfg)
            goldText:SetText(tconcat(lines, "\n", 1, lineCount))
            local r, g, b
            if mouseOver then r, g, b = ns.GetAccent() else r, g, b = BlockColorOf(blockCfg) end
            goldText:SetTextColor(r, g, b, 1)
        elseif mouseOver then
            goldText:SetText(ns.FormatMoneyPlain(money, dg.showSmall == true))
            local r, g, b = ns.GetAccent()
            goldText:SetTextColor(r, g, b, 1)
        else
            goldText:SetText(ns.FormatMoney(money, false, dg.showSmall == true))
            goldText:SetTextColor(BlockColorOf(blockCfg))
        end

        if dg.showBagSpace == true then
            bagText:SetText("(" .. GetFreeBagSlots() .. ")"); bagText:Show()
        else
            bagText:Hide()
        end

        local r, g, b
        if mouseOver then r, g, b = ns.GetAccent() else r, g, b = BlockColorOf(blockCfg) end
        bagText:SetTextColor(r, g, b, 1)

        if dg.showIcons ~= false and iconSz > 0 then
            goldIcon:SetSize(iconSz, iconSz)
            goldIcon:SetVertexColor(r, g, b, 1)
            goldIcon:Show()
        else
            goldIcon:Hide(); iconSz = 0
        end

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local totalH = 8

            if iconSz > 0 then
                goldIcon:ClearAllPoints()
                goldIcon:SetPoint("TOP", goldButton, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end

            ns.SetWrappedText(goldText, innerW, "CENTER")
            goldText:ClearAllPoints()
            if iconSz > 0 then
                goldText:SetPoint("TOP", goldIcon, "BOTTOM", 0, -2)
            else
                goldText:SetPoint("TOP", goldButton, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(goldText:GetStringHeight())

            if bagText:IsShown() then
                ns.SetWrappedText(bagText, innerW, "CENTER")
                bagText:ClearAllPoints()
                bagText:SetPoint("TOP", goldText, "BOTTOM", 0, -2)
                totalH = totalH + 2 + ns.SnapToPixelGrid(bagText:GetStringHeight())
            end

            totalH = max(totalH, barH)
            goldButton:SetSize(slotW, totalH)
            content:SetSize(slotW, totalH)
            goldButton:ClearAllPoints(); goldButton:SetPoint("CENTER", content, "CENTER", 0, 0)
        else
            local slotW = HBudget(inst, 100)
            -- Fit against BOTH money formats so font/icon size (and the frame
            -- width below) stay identical whether hovered or not; otherwise
            -- the element visibly resizes on mouseover.
            local plainText = ns.FormatMoneyPlain(money, dg.showSmall == true)
            local fancyText = ns.FormatMoney(money, false, dg.showSmall == true)
            local moneyText
            if mouseOver then moneyText = plainText else moneyText = fancyText end
            local bagTextValue = ""
            if dg.showBagSpace == true then bagTextValue = "(" .. GetFreeBagSlots() .. ")" end
            local bagPad = 8
            if bagTextValue ~= "" then bagPad = 26 end
            local textBudget = max(24, slotW - iconSz - bagPad)
            _goldFitBuf[1] = plainText; _goldFitBuf[2] = fancyText; _goldFitBuf[3] = bagTextValue
            local fitSize = fontSize
            ns.SetFont(goldText, fitSize, barCfg)
            ns.SetFont(bagText, fitSize, barCfg)
            goldText:SetText(moneyText)
            if bagTextValue ~= "" then bagText:SetText(bagTextValue) end
            ns.ResetInlineText(goldText, "LEFT")
            ns.ResetInlineText(bagText, "LEFT")
            iconSz = 0
            if dg.showIcons ~= false then iconSz = fitSize end
            goldIcon:SetSize(iconSz, iconSz)
            goldIcon:ClearAllPoints(); goldIcon:SetPoint("LEFT", goldButton, "LEFT", 0, 0)
            goldText:ClearAllPoints(); goldText:SetPoint("LEFT", goldButton, "LEFT", iconSz + gap, 0)
            local bagW = 0
            if dg.showBagSpace == true then bagW = (bagText:GetStringWidth() or 0) + 4 end
            bagText:ClearAllPoints(); bagText:SetPoint("LEFT", goldText, "RIGHT", 4, 0)

            -- Width from the wider format so the frame never grows on hover.
            local moneyW = goldText:GetStringWidth() or 0
            local measureFS = ns.MeasureFS()
            if measureFS then
                ns.SetFont(measureFS, fitSize, barCfg)
                local other
                if mouseOver then other = fancyText else other = plainText end
                measureFS:SetText(other)
                moneyW = max(moneyW, measureFS:GetStringWidth() or 0)
            end
            local textW = min(slotW, iconSz + gap + moneyW + bagW + 4)
            goldButton:SetSize(textW, barH)
            content:SetSize(textW, barH)
            goldButton:ClearAllPoints(); goldButton:SetPoint("CENTER", content, "CENTER", 0, 0)
        end
        MaybeRelayout(inst)
    end

    function inst:QueueRefresh()
        if self._refreshQueued then return end
        self._refreshQueued = true
        C_Timer.After(0, function()
            inst._refreshQueued = false
            if goldInstances[inst] then inst:Refresh() end
        end)
    end

    goldButton:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        -- Tooltip money lines honor the block's Show Silver and Copper toggle.
        local sm = D().showSmall == true
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(goldButton)
        ns.Tip_AddLine(L["GOLD"], ar, ag, ab)
        ns.Tip_AddLine(" ")
        ns.Tip_AddLine(L["SESSION"], 0.8, 0.8, 0.8)
        ns.Tip_AddDouble(L["EARNED"], ns.FormatMoney(goldLedger.profit, true, sm), 0.6, 0.6, 0.6, 0, 1, 0)
        ns.Tip_AddDouble(L["SPENT"],  ns.FormatMoney(goldLedger.spent,  true, sm), 0.6, 0.6, 0.6, 1, 0.3, 0.3)
        local net = goldLedger.profit - goldLedger.spent
        if net ~= 0 then
            local label
            if net > 0 then label = L["PROFIT"] else label = L["DEFICIT"] end
            local nr, ngr = 1, 0.3
            if net > 0 then nr, ngr = 0, 1 end
            ns.Tip_AddDouble(label, ns.FormatMoney(abs(net), true, sm), 0.6, 0.6, 0.6, nr, ngr, 0.3)
        end
        local store = GoldStore()
        local total, charList = 0, {}
        for _, cdata in pairs(store) do
            if cdata and cdata.currentMoney then
                tinsert(charList, cdata)
                total = total + cdata.currentMoney
            end
        end
        tsort(charList, function(a, b) return (a.currentMoney or 0) > (b.currentMoney or 0) end)
        if #charList > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(GetRealmName() or "?", 0.5, 0.78, 1)
            for _, char in ipairs(charList) do
                local cr, cg, cb = 1, 1, 1
                if char.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class] then
                    local cc = RAID_CLASS_COLORS[char.class]; cr, cg, cb = cc.r, cc.g, cc.b
                end
                local label = char.name or "?"
                if char.name == UnitName("player") then
                    label = label .. " |TInterface\\COMMON\\Indicator-Green:14|t"
                end
                ns.Tip_AddDouble(label, ns.FormatMoney(char.currentMoney, true, sm), cr, cg, cb, 1, 1, 1)
            end
        end
        local bankType = 2
        if Enum and Enum.BankType and Enum.BankType.Account then bankType = Enum.BankType.Account end
        if C_Bank and C_Bank.FetchDepositedMoney then
            local wbank = C_Bank.FetchDepositedMoney(bankType)
            if wbank and wbank > 0 then
                ns.Tip_AddLine(" ")
                ns.Tip_AddDouble(L["WARBANK"], ns.FormatMoney(wbank, true, sm), 0.6, 0.6, 0.6, 1, 1, 1)
                total = total + wbank
            end
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["TOTAL"], ns.FormatMoney(total, true, sm), ar, ag, ab, 1, 1, 1)
        if goldLedger.tokenPrice and goldLedger.tokenPrice > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddDouble(L["WOW_TOKEN"], ns.FormatMoney(goldLedger.tokenPrice, true, sm), 0, 0.8, 1, 1, 1, 1)
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"],       L["OPEN_BAGS"],       1, 1, 1, ar, ag, ab)
        ns.Tip_AddDouble(L["RIGHT_CLICK"],      L["OPEN_CURRENCIES"], 1, 1, 1, ar, ag, ab)
        ns.Tip_AddDouble(L["CTRL_RIGHT_CLICK"], L["RESET_SESSION"],   1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end)
    goldButton:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(goldButton)
        inst:Refresh()
    end)
    goldButton:SetScript("OnClick", function(_, button)
        if IsControlKeyDown() and button == "RightButton" then
            goldLedger.profit = 0; goldLedger.spent = 0
            inst:Refresh()
        elseif button == "RightButton" then
            if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
                C_CurrencyInfo.OpenCurrencyPanel()
            elseif ToggleCharacter then
                ToggleCharacter("TokenFrame")
            end
        elseif button == "LeftButton" then
            ToggleAllBags()
        end
    end)

    function inst:Enable()
        content:Show()
        if goldLedger.lastMoney == nil then
            goldLedger.lastMoney = GetMoney()
            goldLedger.profit = 0
            goldLedger.spent = 0
            GoldSaveCurrentMoney(goldLedger.lastMoney)
        end
        if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
            C_WowTokenPublic.UpdateMarketPrice()
        end
        goldInstances[self] = true
        UpdateGoldEvents()
    end

    function inst:Disable()
        goldInstances[self] = nil
        UpdateGoldEvents()
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            local barH = barCtx.GetThickness()
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            -- Mirror Refresh: no icon budget when Show Icons is off, else
            -- the segment measures taller than its rendered content.
            local iconTerm = 0
            local dg = blockCfg.settings
            if not dg or dg.showIcons ~= false then iconTerm = fontSize + 2 end
            local textH = goldText:GetStringHeight() or fontSize
            local bagH = 0
            if bagText:IsShown() then bagH = (bagText:GetStringHeight() or 0) + 2 end
            return max(8 + iconTerm + textH + bagH + 4, barH, 50)
        end
        return max(content:GetWidth() or 100, 40)
    end

    function inst:Destroy()
        self._dead = true
        goldInstances[self] = nil
        UpdateGoldEvents()
        content:Hide()
    end

    return inst
end

-------------------------------------------------------------------------------
--  XPREP (XP / Reputation bar)
--  The measured auto extent for this type means "reasonable fixed content
--  size" (icon + 120px minimum bar); it is the type users will normally set
--  to pct mode, and the templates ship it pct.
-------------------------------------------------------------------------------
ns.BlockFactories.xprep = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_XP_UPDATE", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }

    local _dbFitBuf = { "" }
    local mode = "rep"

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local function UpdateMode()
        local d = D()
        if d.mode == "xp"  then mode = "xp";  return end
        if d.mode == "rep" then mode = "rep"; return end
        local atMax = IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()
        local xpOff = IsXPUserDisabled and IsXPUserDisabled()
        mode = "rep"
        if not atMax and not xpOff then mode = "xp" end
    end

    -- Compat: legacy GetWatchedFactionInfo vs C_Reputation.GetWatchedFactionData
    local LegacyGetWatchedFactionInfo = rawget(_G, "GetWatchedFactionInfo")
    local C_Rep = C_Reputation
    local function GetWatchedFactionInfoCompat()
        if LegacyGetWatchedFactionInfo then return LegacyGetWatchedFactionInfo() end
        if C_Rep and C_Rep.GetWatchedFactionData then
            local d = C_Rep.GetWatchedFactionData()
            if d then
                return d.name, d.reaction, d.currentReactionThreshold,
                       d.nextReactionThreshold, d.currentStanding, d.factionID
            end
        end
        return nil
    end

    local function GetProgressValues(cur, minV, maxV)
        if type(minV) ~= "number" then minV = 0 end
        if type(maxV) ~= "number" then maxV = minV + 1 end
        if type(cur)  ~= "number" then cur = minV end
        local pCur = cur - minV
        local pMax = maxV - minV
        if pMax <= 0 then
            local n = 1
            if pCur > 0 then n = pCur end
            return n, n, 100
        end
        return pCur, pMax, max(0, min(100, floor((pCur / pMax) * 100)))
    end

    local barButton = CreateFrame("Button", nil, content)
    barButton:SetAllPoints()
    barButton:EnableMouse(true)
    barButton:RegisterForClicks("AnyUp")
    barButton:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" and not InCombatLockdown() then
            local d = D()
            if mode == "xp" then d.mode = "rep" else d.mode = "xp" end
            inst:Refresh()
        end
    end)

    local nameText = content:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, nameText)
    local bar = CreateFrame("StatusBar", nil, content)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local barTrack = content:CreateTexture(nil, "BACKGROUND")
    local restBar = CreateFrame("StatusBar", nil, content)
    restBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    restBar:SetStatusBarColor(0.3, 0.3, 1, 0.5)
    restBar:Hide()

    -- Shared value/label computation. Returns nil when nothing to show.
    local function ComputeState()
        UpdateMode()
        if mode == "xp" then
            local atMax = IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()
            local curXP = 0
            local maxXP = 1
            if not atMax then
                curXP = UnitXP("player") or 0
                maxXP = UnitXPMax("player") or 1
            end
            if maxXP <= 0 then maxXP = 1 end
            local pct = floor((curXP / maxXP) * 100)
            local level = 0
            if UnitLevel then level = UnitLevel("player") end
            local label = pct .. "% to level " .. (level + 1)
            local ar, ag, ab = ns.GetAccent()
            local rested = 0
            if not atMax then rested = GetXPExhaustion() or 0 end
            return {
                label = label, minV = 0, maxV = maxXP, curV = curXP,
                r = ar, g = ag, b = ab, rested = rested, isXP = true,
            }
        end
        local name, reaction, minV, maxV, curV, factionID = GetWatchedFactionInfoCompat()
        if not name then return nil end
        -- Major Factions (renown progress)
        if factionID and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
            local mfd = C_MajorFactions.GetMajorFactionData(factionID)
            if mfd and type(mfd.renownLevelThreshold) == "number" and mfd.renownLevelThreshold > 0 then
                minV = 0; maxV = mfd.renownLevelThreshold; curV = mfd.renownReputationEarned or 0
            end
        end
        -- Normalise
        if type(minV) == "number" and type(maxV) == "number" and type(curV) == "number" then
            local nMax = maxV - minV
            local nCur = curV - minV
            if nMax > 0 then minV = 0; maxV = nMax; curV = nCur end
        end
        if type(minV) ~= "number" then minV = 0 end
        if type(maxV) ~= "number" then maxV = 1 end
        if type(curV) ~= "number" then curV = 0 end
        if maxV <= minV then maxV = minV + 1 end
        curV = max(minV, min(maxV, curV))
        local _, _, pct = GetProgressValues(curV, minV, maxV)
        local dname = name
        if #name > 20 then dname = name:sub(1, 20) .. "..." end
        local label = dname .. " " .. pct .. "%"
        local cr, cg, cb
        local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if color then cr, cg, cb = color.r, color.g, color.b
        else cr, cg, cb = ns.GetAccent() end
        return {
            label = label, minV = minV, maxV = maxV, curV = curV,
            r = cr, g = cg, b = cb, rested = 0,
        }
    end

    function inst:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local isSide = barCtx.IsVertical()
        local textHeight = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))

        local state = ComputeState()
        if not state then
            content:Hide()
            MaybeRelayout(inst)
            return
        end
        content:Show()
        -- Auto-size measure needs the XP-only bar extension (see below).
        inst._xpExtend = (state.isXP and 40) or 0

        -- Block color: label text (the progress bar itself keeps its own
        -- accent/faction color).
        do
            local br, bgr, bb = BlockColorOf(blockCfg)
            nameText:SetTextColor(br, bgr, bb, 1)
        end

        restBar:Hide()
        bar:SetStatusBarColor(state.r, state.g, state.b, 1)
        bar:SetMinMaxValues(state.minV, state.maxV)
        bar:SetValue(state.curV)
        if state.rested > 0 then
            restBar:SetMinMaxValues(state.minV, state.maxV)
            restBar:SetValue(min(state.curV + state.rested, state.maxV))
            restBar:Show()
        end

        if isSide then
            -- Vertical branch: stacked label above the bar.
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            _dbFitBuf[1] = state.label
            local fitSize = textHeight
            ns.SetFont(nameText, fitSize, barCfg)
            nameText:SetText(state.label)
            ns.SetWrappedText(nameText, innerW, "CENTER")
            nameText:ClearAllPoints()
            nameText:SetPoint("TOP", content, "TOP", 0, -3)
            local textH = ns.SnapToPixelGrid(nameText:GetStringHeight())
            local bH = 5
            barTrack:ClearAllPoints()
            barTrack:SetPoint("TOP", content, "TOP", 0, -(3 + textH + 3))
            barTrack:SetSize(innerW, bH)
            barTrack:SetColorTexture(1, 1, 1, 0.1)
            bar:ClearAllPoints()
            bar:SetSize(innerW, bH)
            bar:SetPoint("TOP", content, "TOP", 0, -(3 + textH + 3))
            restBar:ClearAllPoints(); restBar:SetAllPoints(bar)
            content:SetSize(slotW, max(3 + textH + 3 + bH + 3, 40))
        else
            local slotW = HBudget(inst, 300)
            slotW = max(slotW, 60)
            local bH = max(3, floor(CONTENT_BASE * 0.2 + 0.5))

            -- No icon: text on top, bar underneath, sharing the same left
            -- edge, with the stack centered in the bar height. The bar
            -- tracks the TEXT width.
            _dbFitBuf[1] = state.label
            local fitSize = textHeight
            ns.SetFont(nameText, fitSize, barCfg)
            ns.ResetInlineText(nameText, "LEFT")
            nameText:SetText(state.label)

            local textW = nameText:GetStringWidth() or 0
            local maxTextW = max(20, slotW)
            if textW > maxTextW then
                textW = maxTextW
                nameText:SetWidth(textW)
            end
            if textW < 20 then textW = 20 end
            if ns.SnapToPixelGrid then textW = ns.SnapToPixelGrid(textW) end

            -- XP mode only: the bar runs 40px past the text's right edge
            -- (rep and professions keep bar width = text width).
            local barW = textW
            if state.isXP then barW = min(textW + 40, maxTextW) end

            local textH = ns.SnapToPixelGrid(nameText:GetStringHeight() or textHeight)
            local stackH = textH + 2 + bH
            local pad = max(0, floor((barH - stackH) / 2 + 0.5))
            content:SetSize(min(slotW, barW), barH)
            nameText:ClearAllPoints()
            nameText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -pad)
            barTrack:ClearAllPoints()
            barTrack:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(pad + textH + 2))
            barTrack:SetSize(barW, bH)
            barTrack:SetColorTexture(1, 1, 1, 0.1)
            bar:ClearAllPoints(); bar:SetSize(barW, bH)
            bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(pad + textH + 2))
            restBar:ClearAllPoints(); restBar:SetAllPoints(bar)
        end
        MaybeRelayout(inst)
    end

    inst.eventFrame = MakeEventFrame(inst, function(self)
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        -- Nothing to render (rep mode with no watched faction, or below-max
        -- with no XP source): claim no bar length, so the solver never
        -- reserves a dead gap for an invisible block. The changed-extent
        -- relayout gate restores the width when content returns.
        if not content:IsShown() then return 0 end
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 40)
        end
        -- Auto size tracks the live text width (the bar matches it, plus
        -- the XP-only 40px bar extension). No icon term: the block is
        -- text + bar only.
        local tw = nameText:GetStringWidth() or 0
        if tw < 20 then tw = 120 end
        return tw + (self._xpExtend or 0)
    end

    function inst:Destroy()
        self._dead = true
        content:Hide()
    end

    return inst
end

-------------------------------------------------------------------------------
--  TRAVEL (Hearthstone + M+ teleports; SECURE hearth button)
-------------------------------------------------------------------------------
-- Static hearthstone pool (all expansions) shared by every instance.
local HEARTHSTONE_IDS = {
    -- Midnight
    263933, 265100, 263489,
    -- The War Within
    257736, 246565, 245970, 228940, 212337, 209035, 208704, 210455,
    -- Dragonflight
    236687, 235016, 200630, 193588,
    -- Shadowlands
    190196, 190237, 188952, 184353, 182773, 180290, 183716, 172179,
    -- Seasonal / Holiday
    163045, 162973, 165669, 165670, 165802, 166746, 166747,
    -- Legacy / Misc
    6948, 64488, 28585, 93672, 142542, 142298, 168907, 54452, 556,
}

-- Hearthstones share one cooldown, so polling a single owned one suffices.
-- Engine-level cache: the underlying cooldown is shared game-wide.
local travelPrimaryHearthId

local function TravelIsUsable(id)
    if not id then return false end
    if PlayerHasToy(id) then return true end
    if IsPlayerSpell(id) then return true end
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id) or 0) > 0
end

local function TravelGetRemainingCooldown(id, isSpell)
    local startTime, duration
    if isSpell then
        local info = C_Spell.GetSpellCooldown(id)
        if info then startTime, duration = info.startTime, info.duration end
    else
        if C_Item and C_Item.GetItemCooldown then
            startTime, duration = C_Item.GetItemCooldown(id)
        elseif C_Container and C_Container.GetItemCooldown then
            startTime, duration = C_Container.GetItemCooldown(id)
        end
    end
    if type(startTime) == "number" and type(duration) == "number" and duration > 0 then
        return max(0, startTime + duration - GetTime())
    end
    return 0
end

local _hearthList = {}
local _hearthListCount = 0
local function TravelGetAvailableHearthstones()
    _hearthListCount = 0
    for _, id in ipairs(HEARTHSTONE_IDS) do
        if TravelIsUsable(id) then
            _hearthListCount = _hearthListCount + 1
            _hearthList[_hearthListCount] = id
        end
    end
    for i = _hearthListCount + 1, #_hearthList do _hearthList[i] = nil end
    return _hearthList
end

local function TravelBuildMacro(id)
    if PlayerHasToy(id) then return "/use item:" .. id end
    if IsPlayerSpell(id) then
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name then return "/cast " .. info.name end
    end
    return "/use item:" .. id
end

local function TravelPickHearthstone(randomize)
    local list = TravelGetAvailableHearthstones()
    if #list == 0 then return nil end
    if randomize then return list[mrandom(#list)] end
    for _, id in ipairs(list) do if id == 6948 then return id end end
    return list[1]
end

local function TravelGetPrimaryCooldown()
    if not (travelPrimaryHearthId and TravelIsUsable(travelPrimaryHearthId)) then
        travelPrimaryHearthId = nil
    end
    if not travelPrimaryHearthId then
        travelPrimaryHearthId = TravelPickHearthstone(false)
    end
    if not travelPrimaryHearthId then return 0 end
    return TravelGetRemainingCooldown(travelPrimaryHearthId, false)
end

local function TravelResolveMythicId(idOrTable)
    if type(idOrTable) == "table" then
        for _, id in ipairs(idOrTable) do if IsPlayerSpell(id) then return id end end
        return nil
    end
    if IsPlayerSpell(idOrTable) then return idOrTable end
    return nil
end

-- Season M+ teleports from the shared season list (one update per season).
local SEASON_TELEPORTS = {}
for _, e in ipairs(EllesmereUI.SEASON_PORTALS) do
    local ids = e.spellID
    if e.altSpellIDs then
        ids = { e.spellID }
        for _, a in ipairs(e.altSpellIDs) do ids[#ids + 1] = a end
    end
    SEASON_TELEPORTS[#SEASON_TELEPORTS + 1] = { spellIds = ids, dungeonId = e.dungeonID }
end

ns.BlockFactories.travel = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD" }

    local HEARTH_TEX = MEDIA .. "hearthstone.png"
    local _trvFitBuf1 = { "" }
    local _trvFitBuf2 = { "" }
    local tooltipTimer = 0
    local mouseOver = false

    -- Pre-allocated tooltip line buffers (avoid per-show garbage)
    local _mythicLinesBuf = {}
    for i = 1, #SEASON_TELEPORTS do _mythicLinesBuf[i] = { name = "", cd = 0 } end
    local _mythicLineCount = 0

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local built = false
    local hearthButton, hearthIcon, hearthText, cooldownText
    local placeholder

    local function RefreshTravelTooltip()
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(hearthButton)
        ns.Tip_AddLine("|cFFFFFFFF[|r" .. L["TRAVEL_COOLDOWNS"] .. "|cFFFFFFFF]|r", ar, ag, ab)
        ns.Tip_AddLine(" ")
        local cd2 = TravelGetPrimaryCooldown()
        local cdStr = ns.FormatCooldown(cd2)
        if not cdStr then cdStr = L["READY"] end
        local ready = cd2 <= 0
        local rr, rg = 1, 0
        if ready then rr, rg = 0, 1 end
        ns.Tip_AddDouble(L["HEARTHSTONE"] .. " |cffffffff(" .. (GetBindLocation() or "?") .. ")|r",
                         cdStr, ar, ag, ab, rr, rg, 0)

        _mythicLineCount = 0
        for _, entry in ipairs(SEASON_TELEPORTS) do
            local spellId = TravelResolveMythicId(entry.spellIds)
            if spellId then
                local dName = nil
                if entry.dungeonId and GetLFGDungeonInfo then dName = GetLFGDungeonInfo(entry.dungeonId) end
                local spInfo = C_Spell.GetSpellInfo(spellId)
                local name2 = dName
                if not name2 and spInfo then name2 = spInfo.name end
                if not name2 then name2 = tostring(spellId) end
                _mythicLineCount = _mythicLineCount + 1
                _mythicLinesBuf[_mythicLineCount].name = name2
                _mythicLinesBuf[_mythicLineCount].cd   = TravelGetRemainingCooldown(spellId, true)
            end
        end
        if _mythicLineCount > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["MYTHIC_TELEPORTS"], ar, ag, ab)
            -- Insertion sort on active entries only (max ~8)
            for i = 2, _mythicLineCount do
                local j = i
                while j > 1 and _mythicLinesBuf[j].name < _mythicLinesBuf[j - 1].name do
                    _mythicLinesBuf[j].name, _mythicLinesBuf[j - 1].name = _mythicLinesBuf[j - 1].name, _mythicLinesBuf[j].name
                    _mythicLinesBuf[j].cd,   _mythicLinesBuf[j - 1].cd   = _mythicLinesBuf[j - 1].cd,   _mythicLinesBuf[j].cd
                    j = j - 1
                end
            end
            for i = 1, _mythicLineCount do
                local e = _mythicLinesBuf[i]
                local cs = ns.FormatCooldown(e.cd)
                if not cs then cs = L["READY"] end
                local er, eg = 1, 0
                if e.cd <= 0 then er, eg = 0, 1 end
                ns.Tip_AddDouble(e.name, cs, 0.8, 0.8, 0.8, er, eg, 0)
            end
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["USE_HEARTHSTONE"], 1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end

    local function Build()
        if built then return end
        built = true
        if placeholder then placeholder:Hide() end

        hearthButton = CreateFrame("Button", "EllesmereUIDataBarsHearth_" .. inst.key, content, "SecureActionButtonTemplate")
        -- AnyUp only + useOnKeyDown=false: registering both Up and Down lets
        -- the ActionButtonUseKeyDown CVar fire the macro twice (the second
        -- /use cancels the hearth cast the first one started).
        hearthButton:SetAllPoints()
        hearthButton:EnableMouse(true)
        hearthButton:RegisterForClicks("AnyUp")
        hearthButton:SetAttribute("useOnKeyDown", false)
        hearthButton:SetAttribute("type", "macro")
        hearthButton:SetAttribute("macrotext", "")

        hearthIcon   = hearthButton:CreateTexture(nil, "OVERLAY"); hearthIcon:SetTexture(HEARTH_TEX)
        hearthText   = hearthButton:CreateFontString(nil, "OVERLAY")
        cooldownText = hearthButton:CreateFontString(nil, "OVERLAY"); cooldownText:Hide()
        AttachTextOffset(inst, hearthText)   -- cooldownText chains to hearthText

        local function SeedMacro()
            if InCombatLockdown() then return end
            local dt = D()
            local id = TravelPickHearthstone(dt.randomizeHs)
            if id then hearthButton:SetAttribute("macrotext", TravelBuildMacro(id)) end
        end

        -- Reseed on every PreClick (out of combat only) so the button always
        -- fires the currently owned / random hearthstone without a protected
        -- call from OnClick. SetScript is fine: WE created this button.
        hearthButton:SetScript("PreClick", function()
            if InCombatLockdown() then return end
            SeedMacro()
        end)

        hearthButton:SetScript("OnEnter", function()
            mouseOver = true
            tooltipTimer = 0
            inst:Refresh()
            RefreshTravelTooltip()
        end)
        hearthButton:SetScript("OnLeave", function()
            mouseOver = false
            tooltipTimer = 0
            ns.Tip_Hide(hearthButton)
            inst:Refresh()
        end)

        -- Seed macrotext shortly after build so a first-combat click works.
        C_Timer.After(1, SeedMacro)
    end

    -- Combat-deferred construction: dimmed non-interactive icon until OOC.
    if InCombatLockdown() then
        placeholder = content:CreateTexture(nil, "OVERLAY")
        placeholder:SetTexture(HEARTH_TEX)
        placeholder:SetVertexColor(0.6, 0.6, 0.6, 0.6)
        placeholder:SetSize(16, 16)
        placeholder:SetPoint("CENTER")
        ns.DeferUntilOOC("edbbuild:" .. inst.key, function()
            if inst._dead then return end
            Build()
            inst:Refresh()
        end)
    else
        Build()
    end

    function inst:Refresh()
        if not built then return end
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local cooldownFont = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local location = GetBindLocation() or "?"
        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            _trvFitBuf1[1] = location
            _trvFitBuf2[1] = "00:00:00"
        end

        ns.SetFont(hearthText, fontSize, barCfg)
        ns.SetFont(cooldownText, cooldownFont, barCfg)

        hearthText:SetText(location)

        local cd = TravelGetPrimaryCooldown()
        if cd > 0 then
            local ar, ag, ab = ns.GetAccent()
            local cdStr = ns.FormatCooldown(cd)
            if not cdStr then cdStr = L["READY"] end
            cooldownText:SetText(cdStr)
            cooldownText:SetTextColor(ar, ag, ab, 1)
            cooldownText:Show()
        else
            cooldownText:Hide()
        end

        if mouseOver then
            local ar, ag, ab = ns.GetAccent()
            hearthText:SetTextColor(ar, ag, ab, 1); hearthIcon:SetVertexColor(ar, ag, ab, 1)
        elseif cd > 0 then
            hearthText:SetTextColor(1, 0.3, 0.3, 1); hearthIcon:SetVertexColor(1, 0.3, 0.3, 1)
        else
            local br, bgr, bb = BlockColorOf(blockCfg)
            hearthText:SetTextColor(br, bgr, bb, 1); hearthIcon:SetVertexColor(br, bgr, bb, 1)
        end

        if InCombatLockdown() then return end

        local iconSz, gap = fontSize, 4
        if isSide then
            iconSz = min(iconSz, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
        end
        hearthIcon:ClearAllPoints()
        hearthIcon:SetSize(iconSz, iconSz)

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local totalH = 8 + iconSz + 2

            content:SetWidth(slotW)
            hearthButton:SetWidth(slotW)
            hearthIcon:SetPoint("TOP", hearthButton, "TOP", 0, -4)

            ns.SetWrappedText(hearthText, innerW, "CENTER")
            hearthText:ClearAllPoints()
            hearthText:SetPoint("TOP", hearthIcon, "BOTTOM", 0, -2)
            totalH = totalH + ns.SnapToPixelGrid(hearthText:GetStringHeight())

            if cooldownText:IsShown() then
                ns.SetWrappedText(cooldownText, innerW, "CENTER")
                cooldownText:ClearAllPoints()
                cooldownText:SetPoint("TOP", hearthText, "BOTTOM", 0, -2)
                totalH = totalH + 2 + ns.SnapToPixelGrid(cooldownText:GetStringHeight())
            end

            totalH = max(totalH, barH)
            content:SetHeight(totalH)
            hearthButton:SetHeight(totalH)
        else
            local slotW = HBudget(inst, 120)
            local textBudget = max(30, slotW - iconSz - gap - 8)
            _trvFitBuf1[1] = location
            _trvFitBuf2[1] = cooldownText:GetText() or "00:00:00"
            ns.SetFont(hearthText, fontSize, barCfg)
            ns.SetFont(cooldownText, cooldownFont, barCfg)
            hearthText:SetText(location)
            iconSz = min(fontSize, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            hearthIcon:SetSize(iconSz, iconSz)
            ns.ResetInlineText(hearthText, "LEFT")
            ns.ResetInlineText(cooldownText, "CENTER")
            local tw = ns.SnapToPixelGrid(hearthText:GetStringWidth())
            local totalW = min(slotW, iconSz + gap + tw + 4)
            content:SetSize(totalW, barH)
            hearthButton:SetSize(totalW, barH)
            hearthIcon:SetPoint("LEFT", hearthButton, "LEFT", 0, 0)
            hearthText:ClearAllPoints(); hearthText:SetPoint("LEFT", hearthButton, "LEFT", iconSz + gap, 0)
            cooldownText:ClearAllPoints(); cooldownText:SetPoint("CENTER", hearthText, "TOP", 0, 4)
        end
        MaybeRelayout(inst)
    end

    -- 1s heartbeat: the cooldown text needs 1s resolution; the open tooltip
    -- refreshes every 5s while hovered.
    local function TravelTick()
        tooltipTimer = tooltipTimer + 1
        inst:Refresh()
        if built and mouseOver and ns.Tip_IsOwned(hearthButton) and tooltipTimer >= 5 then
            tooltipTimer = 0
            RefreshTravelTooltip()
        end
    end

    inst.eventFrame = MakeEventFrame(inst, function(self)
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        tooltipTimer = 0
        RegisterInstEvents(self)
        ns.RegisterHeartbeat("travel:" .. self.key, TravelTick)
    end

    function inst:Disable()
        ns.UnregisterHeartbeat("travel:" .. self.key)
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if not built then return 40 end
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            local iconSz = fontSize
            local textH = hearthText:GetStringHeight() or fontSize
            local cdH = 0
            if cooldownText:IsShown() then cdH = (cooldownText:GetStringHeight() or 0) + 4 end
            return max(8 + iconSz + 2 + textH + cdH + 4, barH, 50)
        end
        return max(content:GetWidth() or 120, 40)
    end

    function inst:Destroy()
        self._dead = true
        if hearthButton then
            ParkSecureFrame(hearthButton, self.key .. "_hearth")
        end
        content:Hide()
    end

    return inst
end

-------------------------------------------------------------------------------
--  SPEC (specialisation, loot-spec, loadout popups)
-------------------------------------------------------------------------------
-- Loadout-name freshness: the "last selected loadout" pointer the spec
-- block displays is written AFTER the talent-commit events fire (both
-- TRAIT_CONFIG_UPDATED and SPELLS_CHANGED race it and read the OLD name).
-- So hook the WRITE itself: Blizzard's talent UI and every loadout addon
-- funnel through UpdateLastSelectedSavedConfigID. Combat skips (the
-- registered PLAYER_REGEN_ENABLED refresh catches up).
local specInstances = {}
local specPointerHooked = false
local function HookLoadoutPointer()
    if specPointerHooked then return end
    if not (C_ClassTalents and C_ClassTalents.UpdateLastSelectedSavedConfigID
            and hooksecurefunc) then return end
    specPointerHooked = true
    hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", function()
        if InCombatLockdown() then return end
        for i = 1, #specInstances do
            local si = specInstances[i]
            if not si._dead and si.Refresh then si:Refresh() end
        end
    end)
end

ns.BlockFactories.spec = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    specInstances[#specInstances + 1] = inst
    HookLoadoutPointer()
    inst.events = { "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LOOT_SPEC_UPDATED",
                    -- TRAIT_CONFIG_UPDATED fires BEFORE the last-selected
                    -- loadout pointer moves, so the name read there is
                    -- stale; SPELLS_CHANGED fires once the swap has really
                    -- applied (same signal the CDM keys its talent-swap
                    -- rebuilds off) and re-reads the settled name.
                    "TRAIT_CONFIG_UPDATED", "SPELLS_CHANGED",
                    "PLAYER_ENTERING_WORLD",
                    -- OnEvent skips refresh in combat; catch up once it ends
                    -- (loot spec can change mid-combat).
                    "PLAYER_REGEN_ENABLED" }

    local SPEC_MEDIA = MEDIA .. "spec\\"
    local _specFitBuf1 = { "" }
    local _specFitBuf2 = { "" }
    -- One PNG per spec in media\spec\, named <class>-<spec>.png and listed
    -- here in SPEC INDEX order per class token (GetSpecializationInfo order
    -- is fixed), so no spec-ID table is needed -- new specs just append.
    local SPEC_ICON_FILES = {
        WARRIOR     = { "warrior-arms", "warrior-fury", "warrior-prot" },
        PALADIN     = { "paladin-holy", "paladin-prot", "paladin-ret" },
        HUNTER      = { "hunter-beastmaster", "hunter-marksman", "hunter-survival" },
        ROGUE       = { "rogue-assasin", "rogue-outlaw", "rogue-sub" },
        PRIEST      = { "priest-disc", "priest-holy", "priest-shadow" },
        DEATHKNIGHT = { "dk-blood", "dk-frost", "dk-unholy" },
        SHAMAN      = { "shaman-ele", "shaman-enhance", "shaman-resto" },
        MAGE        = { "mage-arcane", "mage-fire", "mage-frost" },
        WARLOCK     = { "warlock-aff", "warlock-demo", "warlock-destro" },
        MONK        = { "monk-brew", "monk-mw", "monk-ww" },
        DRUID       = { "druid-balance", "druid-feral", "druid-bear", "druid-resto" },
        DEMONHUNTER = { "dh-havoc", "dh-vengeance", "dh-devourer" },
        EVOKER      = { "evoker-dev", "evoker-pres", "evoker-aug" },
    }
    local POPUP_FONT_SIZE = 12

    local specCache, numSpecs = {}, 0
    local currentSpecIdx, currentLootSpecID = nil, 0
    local mouseOver = false

    -- Per-instance popup pools (lazy). Two spec blocks never fight over the
    -- same popup frames.
    local specPool, lootPool, loadoutPool

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local function BuildSpecCache()
        specCache = {}; numSpecs = GetNumSpecializations() or 0
        for i = 1, numSpecs do
            local id, name, _, icon, role = GetSpecializationInfo(i)
            if id then specCache[i] = { id = id, name = name, icon = icon, role = role } end
        end
    end

    local function UpdateCurrentSpec()
        currentSpecIdx    = GetSpecialization()
        currentLootSpecID = GetLootSpecialization() or 0
    end

    local function GetCurrentLoadoutName()
        if not (C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID) then return nil end
        local specId = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
        if not specId then return nil end
        local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        if not configID then return nil end
        local info = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        if info then return info.name end
        return nil
    end

    local function GetLootSpecName()
        if currentLootSpecID == 0 then
            if currentSpecIdx and specCache[currentSpecIdx] then
                return specCache[currentSpecIdx].name
            end
            return nil
        end
        local _, name
        if GetSpecializationInfoByID then _, name = GetSpecializationInfoByID(currentLootSpecID) end
        return name
    end

    local function GetBarDisplayText()
        local d = D()
        local text
        if d.showLoadout ~= false then text = GetCurrentLoadoutName() end
        if not text then
            if currentSpecIdx and specCache[currentSpecIdx] then
                text = specCache[currentSpecIdx].name
            end
        end
        if not text then text = "" end
        -- Opt-in only (default off): never force-capitalize.
        if d.useUppercase == true then return text:upper() end
        return text
    end

    local specButton = CreateFrame("Button", nil, content)
    specButton:SetAllPoints()
    specButton:EnableMouse(true)
    specButton:RegisterForClicks("AnyUp")

    local specIcon = content:CreateTexture(nil, "OVERLAY"); specIcon:SetSize(16, 16)
    local specText = content:CreateFontString(nil, "OVERLAY")
    local infoText = content:CreateFontString(nil, "OVERLAY"); infoText:Hide()
    AttachTextOffset(inst, specText)   -- infoText chains to specText

    -- Generic popup builder (shared across the three popups of THIS instance)
    local function BuildPopup(pool, parent, title, entries, onClickEntry, noCatcher)
        if not pool then return nil end
        pool:ReleaseAll()
        local popup = pool._popup
        if not popup then
            popup = ns.CreatePopupFrame(parent)
            pool._popup = popup
        end
        popup._wbNoCatcher = noCatcher and true or nil
        popup._wbOnHide = function()
            pool:ReleaseAll()
            if pool._onHide then pool._onHide() end
        end
        popup:Show()

        local ar, ag, ab = ns.GetAccent()
        local fontSize = POPUP_FONT_SIZE
        local iconSz = fontSize + 2
        local PAD, LINE = 6, 18

        if not popup._title then
            popup._title = popup:CreateFontString(nil, "OVERLAY")
            popup._title:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -PAD)
        end
        ns.SetFont(popup._title, fontSize)
        popup._title:SetText(title); popup._title:SetTextColor(1, 1, 1, 1)

        local maxW = popup._title:GetStringWidth()
        local yOff = PAD + LINE + PAD

        for _, entry in ipairs(entries) do
            local btn = pool:Acquire()
            btn:SetParent(popup)
            btn:SetHeight(iconSz)
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -yOff)
            btn:EnableMouse(true); btn:RegisterForClicks("AnyUp")

            if not btn._icon then btn._icon = btn:CreateTexture(nil, "OVERLAY") end
            btn._icon:SetSize(iconSz, iconSz)
            btn._icon:ClearAllPoints()
            btn._icon:SetPoint("LEFT")

            if not btn._label then btn._label = btn:CreateFontString(nil, "OVERLAY") end
            btn._label:ClearAllPoints()
            btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 4, 0)
            btn:Show()
            ns.SetFont(btn._label, fontSize)
            btn._label:SetText(entry.name)
            btn._label:Show()
            if entry.icon then
                btn._icon:SetTexture(entry.icon)
                btn._icon:SetTexCoord(4 / 64, 60 / 64, 4 / 64, 60 / 64)
                btn._icon:Show()
            else
                btn._icon:Hide()
            end

            if entry.isActive then btn._label:SetTextColor(ar, ag, ab, 1)
            else btn._label:SetTextColor(1, 1, 1, 1) end

            btn:SetScript("OnEnter", function() btn._label:SetTextColor(ar, ag, ab, 1) end)
            btn:SetScript("OnLeave", function()
                if entry.isActive then btn._label:SetTextColor(ar, ag, ab, 1)
                else btn._label:SetTextColor(1, 1, 1, 1) end
            end)
            btn:SetScript("OnClick", function(_, mb)
                if mb == "LeftButton" and not InCombatLockdown() then
                    onClickEntry(entry)
                    popup:Hide()
                end
            end)

            local iconExtra = 0
            if btn._icon:IsShown() then iconExtra = iconSz + 4 end
            local bw = iconExtra + btn._label:GetStringWidth()
            if bw > maxW then maxW = bw end
            btn:SetWidth(bw)
            yOff = yOff + iconSz + 6
        end
        -- Trim the last row's trailing gap so the bottom padding stays PAD.
        if #entries > 0 then yOff = yOff - 4 end

        popup:SetSize(maxW + PAD * 2, yOff + PAD)
        popup:ClearAllPoints()
        if barCtx.IsVertical() then
            -- Bar on the right half of the screen: popup opens to the left.
            local cx = parent:GetCenter()
            if cx and cx > UIParent:GetWidth() / 2 then
                popup:SetPoint("RIGHT", parent, "LEFT", -4, 0)
            else
                popup:SetPoint("LEFT", parent, "RIGHT", 4, 0)
            end
        else
            if barCtx.IsBarAtTop() then
                popup:SetPoint("TOP", parent, "BOTTOM", 0, -4)
            else
                popup:SetPoint("BOTTOM", parent, "TOP", 0, 4)
            end
        end
        popup:SetClampedToScreen(true)
        if popup._wbClickCatcher then
            popup._wbClickCatcher:ClearAllPoints()
            popup._wbClickCatcher:SetAllPoints(UIParent)
        end
        return popup
    end

    local function ToggleSpecPopup()
        if specPool and specPool._popup and specPool._popup:IsShown() then
            specPool._popup:Hide(); return
        end
        if not specPool then specPool = ns.CreateFramePool("Button", UIParent) end
        local entries = {}
        for i = 1, numSpecs do
            local info = specCache[i]
            if info then
                entries[#entries + 1] = { name = info.name, icon = info.icon, isActive = (i == currentSpecIdx), specIndex = i }
            end
        end
        BuildPopup(specPool, specButton, L["CHANGE_SPEC"], entries, function(e)
            C_SpecializationInfo.SetSpecialization(e.specIndex)
        end, true)
    end

    local function ToggleLootSpecPopup()
        if lootPool and lootPool._popup and lootPool._popup:IsShown() then
            lootPool._popup:Hide(); return
        end
        if not lootPool then lootPool = ns.CreateFramePool("Button", UIParent) end
        local activeIcon = nil
        if currentSpecIdx and specCache[currentSpecIdx] then activeIcon = specCache[currentSpecIdx].icon end
        local entries = { {
            name = L["CURRENT_SPEC"],
            icon = activeIcon,
            isActive = currentLootSpecID == 0,
            specIndex = 0,
        } }
        for i = 1, numSpecs do
            local info = specCache[i]
            if info then
                entries[#entries + 1] = { name = info.name, icon = info.icon, isActive = (info.id == currentLootSpecID), specIndex = i }
            end
        end
        BuildPopup(lootPool, specButton, L["CHANGE_LOOT_SPEC"], entries, function(e)
            local id = 0
            if e.specIndex > 0 then id = select(1, GetSpecializationInfo(e.specIndex)) or 0 end
            SetLootSpecialization(id)
        end)
    end

    local function ToggleLoadoutPopup()
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then
            loadoutPool._popup:Hide(); return
        end
        if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID and C_Traits and C_Traits.GetConfigInfo) then return end
        if not loadoutPool then loadoutPool = ns.CreateFramePool("Button", UIParent) end

        local specId = nil
        if currentSpecIdx and specCache[currentSpecIdx] then specId = specCache[currentSpecIdx].id end
        if not specId then return end
        local activeConfigID = nil
        if C_ClassTalents.GetLastSelectedSavedConfigID then
            activeConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        end
        local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specId)
        local entries = {}
        for _, cid in ipairs(configIDs) do
            local info = C_Traits.GetConfigInfo(cid)
            if info and info.name then
                entries[#entries + 1] = { name = info.name, isActive = (cid == activeConfigID), configID = cid }
            end
        end
        BuildPopup(loadoutPool, specButton, L["CHANGE_LOADOUT"], entries, function(e)
            C_ClassTalents.LoadConfig(e.configID, true)
            C_ClassTalents.UpdateLastSelectedSavedConfigID(specId, e.configID)
            inst:Refresh()
        end)
    end

    local function HideAllPopups()
        if specPool    and specPool._popup    and specPool._popup:IsShown()    then specPool._popup:Hide()    end
        if lootPool    and lootPool._popup    and lootPool._popup:IsShown()    then lootPool._popup:Hide()    end
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then loadoutPool._popup:Hide() end
    end

    function inst:Refresh()
        if InCombatLockdown() then return end
        UpdateCurrentSpec()
        local d = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        -- Loot spec rides smaller than the main label (11px at the 30 base).
        local infoSz   = max(8, floor(CONTENT_BASE * 0.36 + 0.5))
        local gap = 4
        local ar, ag, ab = ns.GetAccent()
        local isSide = barCtx.IsVertical()
        local specLabel = GetBarDisplayText()

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            _specFitBuf1[1] = specLabel
            local lootNameForFit = GetLootSpecName()
            if lootNameForFit then
                if d.useUppercase ~= false then
                    _specFitBuf2[1] = lootNameForFit:upper()
                else
                    _specFitBuf2[1] = lootNameForFit
                end
            end
        end
        local iconSz = fontSize + 8

        ns.SetFont(specText, fontSize, barCfg); ns.SetFont(infoText, infoSz, barCfg)
        specText:SetText(specLabel)

        if currentSpecIdx then
            local _, classId = UnitClass("player")
            local files = classId and SPEC_ICON_FILES[classId]
            local file = files and files[currentSpecIdx]
            if file then
                specIcon:SetTexture(SPEC_MEDIA .. file .. ".png")
                specIcon:SetTexCoord(0, 1, 0, 1)
            end
        end

        if mouseOver then
            specText:SetTextColor(ar, ag, ab, 1); specIcon:SetVertexColor(ar, ag, ab, 1)
        else
            local br, bgr, bb = BlockColorOf(blockCfg)
            specText:SetTextColor(br, bgr, bb, 1); specIcon:SetVertexColor(br, bgr, bb, 1)
        end

        local lootName = GetLootSpecName()
        local activeSpecName = nil
        if currentSpecIdx and specCache[currentSpecIdx] then activeSpecName = specCache[currentSpecIdx].name end
        if lootName and lootName ~= activeSpecName then
            if d.useUppercase ~= false then
                infoText:SetText("(" .. lootName:upper() .. ")")
            else
                infoText:SetText("(" .. lootName .. ")")
            end
            infoText:SetTextColor(1, 1, 1, 0.8); infoText:Show()
        else
            infoText:Hide()
        end

        if isSide then
            iconSz = min(iconSz, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
        end
        specIcon:SetSize(iconSz, iconSz)

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local totalH = 8 + iconSz + 2

            specIcon:ClearAllPoints()
            specIcon:SetPoint("TOP", content, "TOP", 0, -4)

            ns.SetWrappedText(specText, innerW, "CENTER")
            specText:ClearAllPoints()
            specText:SetPoint("TOP", specIcon, "BOTTOM", 0, -2)
            totalH = totalH + ns.SnapToPixelGrid(specText:GetStringHeight())

            if infoText:IsShown() then
                ns.SetWrappedText(infoText, innerW, "CENTER")
                infoText:ClearAllPoints()
                infoText:SetPoint("TOP", specText, "BOTTOM", 0, -2)
                totalH = totalH + 2 + ns.SnapToPixelGrid(infoText:GetStringHeight())
            end

            totalH = max(totalH, barH)
            content:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 120)
            local textBudget = max(30, slotW - iconSz - gap - 8)
            _specFitBuf1[1] = specLabel
            ns.SetFont(specText, fontSize, barCfg)
            specText:SetText(specLabel)
            if infoText:IsShown() then
                local infoLabel = infoText:GetText() or ""
                _specFitBuf2[1] = infoLabel
                ns.SetFont(infoText, infoSz, barCfg)
            end
            iconSz = min(fontSize + 8, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            specIcon:SetSize(iconSz, iconSz)
            ns.ResetInlineText(specText, "LEFT")
            ns.ResetInlineText(infoText, "LEFT")
            local tw = ns.SnapToPixelGrid(specText:GetStringWidth())
            -- Loot spec sits INLINE to the right of the spec/loadout label
            -- (below it on vertical bars); the content width includes it so
            -- Auto Sized bars reserve the full extent.
            local iw = 0
            if infoText:IsShown() then
                iw = ns.SnapToPixelGrid(infoText:GetStringWidth() or 0)
            end
            local infoPad = 0
            if iw > 0 then infoPad = gap + iw end
            local totalW = min(slotW, iconSz + gap + tw + infoPad + 4)
            specIcon:ClearAllPoints(); specIcon:SetPoint("LEFT", content, "LEFT", 0, 0)
            specText:ClearAllPoints(); specText:SetPoint("LEFT", content, "LEFT", iconSz + gap, 0)
            infoText:ClearAllPoints(); infoText:SetPoint("LEFT", specText, "RIGHT", gap, 0)
            content:SetSize(totalW, barH)
        end
        specButton:ClearAllPoints(); specButton:SetAllPoints(content)
        MaybeRelayout(inst)
    end

    -- The spec popup opens on hover and closes only once the cursor is over
    -- neither the block nor the popup. Both rects are padded 8px so the 4px
    -- anchor gap between bar and popup never counts as "outside" mid-travel.
    local hoverWatch = CreateFrame("Frame")
    hoverWatch:Hide()
    hoverWatch:SetScript("OnUpdate", function(self)
        local popup = specPool and specPool._popup
        if not (popup and popup:IsShown()) then self:Hide(); return end
        if specButton:IsMouseOver(8, -8, -8, 8) or popup:IsMouseOver(8, -8, -8, 8) then return end
        popup:Hide()
        self:Hide()
    end)

    specButton:SetScript("OnEnter", function()
        mouseOver = true; inst:Refresh()
        if InCombatLockdown() then return end
        -- Never stomp a click-opened popup (loot spec / loadout).
        if lootPool and lootPool._popup and lootPool._popup:IsShown() then return end
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then return end
        if not (specPool and specPool._popup and specPool._popup:IsShown()) then
            ToggleSpecPopup()
        end
        hoverWatch:Show()
    end)
    specButton:SetScript("OnLeave", function() mouseOver = false; inst:Refresh() end)
    specButton:SetScript("OnClick", function(_, button)
        if InCombatLockdown() then return end
        if button == "LeftButton" then
            if IsControlKeyDown() then
                if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then loadoutPool._popup:Hide(); return end
                HideAllPopups(); ToggleLoadoutPopup()
            elseif IsShiftKeyDown() then
                HideAllPopups()
                if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then PlayerSpellsUtil.ToggleClassTalentFrame()
                elseif ToggleTalentFrame then ToggleTalentFrame() end
            end
        elseif button == "RightButton" then
            if lootPool and lootPool._popup and lootPool._popup:IsShown() then lootPool._popup:Hide(); return end
            HideAllPopups(); ToggleLootSpecPopup()
        end
    end)

    inst.eventFrame = MakeEventFrame(inst, function(self)
        if not InCombatLockdown() then self:Refresh() end
    end)

    function inst:Enable()
        content:Show()
        BuildSpecCache()
        UpdateCurrentSpec()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        HideAllPopups()
        content:Hide()
    end

    function inst:GetAutoLength()
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            local iconSz = min(fontSize + 8, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            local textH = specText:GetStringHeight() or fontSize
            local infoH = 0
            if infoText:IsShown() then infoH = (infoText:GetStringHeight() or 0) + 2 end
            return max(8 + iconSz + 2 + textH + infoH + 4, barH, 60)
        end
        return max(content:GetWidth() or 120, 40)
    end

    function inst:Destroy()
        self._dead = true
        HideAllPopups()
        content:Hide()
    end

    return inst
end

-------------------------------------------------------------------------------
--  PROFESSION (SECURE right-click passthrough to ProfessionMicroButton)
-------------------------------------------------------------------------------
-- Skill-line ID -> icon file in media\profession\ (one PNG per profession;
-- filenames follow the art set's own stems, e.g. "blacksmith"/"engineer").
local profIcons = {
    [164] = "prof-blacksmith",   [165] = "prof-leatherworking", [171] = "prof-alchemy",
    [182] = "prof-herbalism",    [186] = "prof-mining",         [202] = "prof-engineer",
    [333] = "prof-enchanting",   [755] = "prof-jewelcrafting",  [773] = "prof-inscription",
    [197] = "prof-tailoring",    [393] = "prof-skinning",       [185] = "prof-cooking",
    [356] = "prof-fishing",
}

-- Shared builder for both profession blocks. secondary = false shows the
-- two primary professions (right-click = profession book); secondary =
-- true shows Cooking + Fishing (right-click = Basic Campfire, a secure
-- spell cast).
local CAMPFIRE_SPELL = 818   -- Basic Campfire
local function MakeProfessionBlock(blockCfg, slot, content, barCtx, secondary)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "TRADE_SKILL_DETAILS_UPDATE", "SPELLS_CHANGED" }

    local MEDIA_PROF = MEDIA .. "profession\\"
    local prof1, prof2 = {}, {}

    local function BC() return barCtx.cfg end

    local built = false
    local prof1Frame, prof1Icon, prof1Text, prof1Bar, prof1BarBg
    local prof2Frame, prof2Icon, prof2Text, prof2Bar, prof2BarBg

    local function UpdateProfValues()
        local p1, p2
        if secondary then
            local _, _, _, fishing, cooking = GetProfessions()
            p1, p2 = cooking, fishing
        else
            p1, p2 = GetProfessions()
        end
        prof1 = {}; prof2 = {}
        if p1 then
            local name, icon, rank, maxRank, _, _, id = GetProfessionInfo(p1)
            name = name or ""
            prof1 = { idx = p1, name = name, nameUpper = name:upper(), icon = icon, rank = rank or 0, maxRank = maxRank or 0, id = id }
        end
        if p2 then
            local name, icon, rank, maxRank, _, _, id = GetProfessionInfo(p2)
            name = name or ""
            prof2 = { idx = p2, name = name, nameUpper = name:upper(), icon = icon, rank = rank or 0, maxRank = maxRank or 0, id = id }
        end
    end

    local function StyleProfFrame(profData, profFrame, profIcon, profText, profBar, profBarBg)
        if not profData or not profData.idx then profFrame:Hide(); return end
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local iconSize = fontSize + 8
        local isSide = barCtx.IsVertical()

        local iconTex = profData.icon
        if profIcons[profData.id] then
            iconTex = MEDIA_PROF .. profIcons[profData.id] .. ".png"
        end
        profIcon:SetTexture(iconTex); profIcon:SetSize(iconSize, iconSize); profIcon:Show()
        local pbr, pbg, pbb = BlockColorOf(blockCfg)
        profIcon:SetVertexColor(pbr, pbg, pbb, 1)

        -- Font derives from CONTENT_BASE like every other block: the bar
        -- Height setting must never resize content.
        ns.SetFont(profText, fontSize, barCfg)
        profText:SetTextColor(pbr, pbg, pbb, 1); profText:SetText(profData.name or "")

        if isSide then
            local frameW = VSlotW(inst)
            local innerW = max(30, frameW - 8)
            local totalH = 8 + iconSize + 2

            profIcon:ClearAllPoints()
            profIcon:SetPoint("TOP", profFrame, "TOP", 0, -4)

            ns.SetWrappedText(profText, innerW, "CENTER")
            profText:ClearAllPoints()
            profText:SetPoint("TOP", profIcon, "BOTTOM", 0, -2)
            totalH = totalH + ns.SnapToPixelGrid(profText:GetStringHeight())

            if profData.rank ~= profData.maxRank then
                local ar, ag, ab = ns.GetAccent()
                local bH = 4
                profBar:Show()
                profBar:SetMinMaxValues(1, profData.maxRank); profBar:SetValue(profData.rank)
                profBar:SetStatusBarColor(ar, ag, ab, 1); profBarBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
                profBar:SetSize(innerW, bH)
                profBar:ClearAllPoints()
                profBar:SetPoint("TOP", profText, "BOTTOM", 0, -3)
                totalH = totalH + 3 + bH
            else
                profBar:Hide()
            end

            profFrame:SetSize(frameW, max(totalH, barH))
            profFrame:Show()
        else
            ns.ResetInlineText(profText, "LEFT")
            profIcon:ClearAllPoints(); profIcon:SetPoint("LEFT", profFrame, "LEFT", 0, 0)

            if profData.rank == profData.maxRank then
                profBar:Hide()
                profText:ClearAllPoints(); profText:SetPoint("LEFT", profIcon, "RIGHT", 5, 0)
            else
                profBar:Show()
                profText:ClearAllPoints(); profText:SetPoint("TOPLEFT", profIcon, "TOPRIGHT", 5, 0)
                local ar, ag, ab = ns.GetAccent()
                profBar:SetMinMaxValues(1, profData.maxRank); profBar:SetValue(profData.rank)
                profBar:SetStatusBarColor(ar, ag, ab, 1); profBarBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
                -- Icon left; text top-right; bar bottom-right -- the bar
                -- shares the text's left edge and tracks the TEXT width,
                -- bottom-aligned to the icon (same recipe as xprep).
                local textW = max(profText:GetStringWidth(), 20)
                local bH = max(3, iconSize - fontSize - 2)
                profBar:SetSize(textW, bH)
                profBar:ClearAllPoints()
                profBar:SetPoint("BOTTOMLEFT", profIcon, "BOTTOMRIGHT", 5, 0)
            end
            local textW = max(profText:GetStringWidth(), 20)
            profFrame:SetSize(iconSize + textW + 5, barH); profFrame:Show()
        end
    end

    local function OpenProf(prof)
        if not prof or not prof.id or InCombatLockdown() then return end
        local currInfo = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        if currInfo and currInfo.professionID == prof.id and _G.ProfessionsFrame and _G.ProfessionsFrame:IsShown() then
            C_TradeSkillUI.CloseTradeSkill()
        elseif prof.id then
            C_TradeSkillUI.OpenTradeSkill(prof.id)
        end
    end

    local function Build()
        if built then return end
        built = true

        local function MakeProfFrame(name)
            local f = CreateFrame("Button", name, content, "SecureActionButtonTemplate")
            f:SetSize(1, barCtx.GetThickness()); f:EnableMouse(true); f:RegisterForClicks("AnyUp")
            f:SetAttribute("useOnKeyDown", false)
            if secondary then
                -- Right-click = Basic Campfire, cast securely.
                f:SetAttribute("*type2", "spell")
                f:SetAttribute("*spell2", CAMPFIRE_SPELL)
            elseif _G.ProfessionMicroButton then
                f:SetAttribute("*type2", "click")
                f:SetAttribute("*clickbutton2", _G.ProfessionMicroButton)
            end
            local icon = f:CreateTexture(nil, "OVERLAY")
            local text = f:CreateFontString(nil, "OVERLAY")
            local bar  = CreateFrame("StatusBar", nil, f); bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local bg   = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
            return f, icon, text, bar, bg
        end

        prof1Frame, prof1Icon, prof1Text, prof1Bar, prof1BarBg = MakeProfFrame("EllesmereUIDataBarsProf1_" .. inst.key)
        prof2Frame, prof2Icon, prof2Text, prof2Bar, prof2BarBg = MakeProfFrame("EllesmereUIDataBarsProf2_" .. inst.key)
        AttachTextOffset(inst, prof1Text)
        AttachTextOffset(inst, prof2Text)

        local frames = { prof1Frame, prof2Frame }
        for i = 1, 2 do
            local frame = frames[i]
            local isFirst = (i == 1)
            -- HookScript, NOT SetScript: SetScript("OnClick") would overwrite
            -- SecureActionButton_OnClick and kill the secure *clickbutton2
            -- passthrough to ProfessionMicroButton (right-click).
            frame:HookScript("OnClick", function(_, button)
                if button == "LeftButton" then
                    if isFirst then OpenProf(prof1) else OpenProf(prof2) end
                end
            end)
            frame:SetScript("OnEnter", function(f)
                local txt, ic = prof2Text, prof2Icon
                if isFirst then txt, ic = prof1Text, prof1Icon end
                local ar, ag, ab = ns.GetAccent()
                txt:SetTextColor(ar, ag, ab, 1)
                if ic then ic:SetVertexColor(ar, ag, ab, 1) end
                ns.Tip_Begin(f)
                local title
                if secondary then
                    title = SECONDARY_SKILLS or "Secondary Professions"
                else
                    title = TRADE_SKILLS or "Professions"
                end
                ns.Tip_AddLine(title, 1, 1, 1)
                ns.Tip_AddLine(" ")
                local function AddLine(p)
                    if not p or not p.name then return end
                    ns.Tip_AddDouble(p.name, "|cffFFFFFF" .. p.rank .. "|r / " .. p.maxRank, 1, 1, 1, 1, 1, 1)
                end
                if prof1.idx then AddLine(prof1) end
                if prof2.idx then AddLine(prof2) end
                ns.Tip_AddLine(" ")
                local rightLabel = L["OPEN_PROFESSION_BOOK"]
                if secondary then rightLabel = L["START_CAMPFIRE"] end
                ns.Tip_AddDouble(L["LEFT_CLICK"],  L["OPEN_PROFESSION"], 1, 1, 1, 1, 1, 1)
                ns.Tip_AddDouble(L["RIGHT_CLICK"], rightLabel,           1, 1, 1, 1, 1, 1)
                ns.Tip_Show()
            end)
            frame:SetScript("OnLeave", function(f)
                local txt, ic = prof2Text, prof2Icon
                if isFirst then txt, ic = prof1Text, prof1Icon end
                local br, bgr, bb = BlockColorOf(blockCfg)
                txt:SetTextColor(br, bgr, bb, 1)
                if ic then ic:SetVertexColor(br, bgr, bb, 1) end
                ns.Tip_Hide(f)
            end)
        end
    end

    if InCombatLockdown() then
        ns.DeferUntilOOC("edbbuild:" .. inst.key, function()
            if inst._dead then return end
            Build()
            inst:Refresh()
        end)
    else
        Build()
    end

    function inst:Refresh()
        if not built or InCombatLockdown() then return end
        UpdateProfValues()
        local barH, gap = barCtx.GetThickness(), 5
        local isSide = barCtx.IsVertical()

        StyleProfFrame(prof1, prof1Frame, prof1Icon, prof1Text, prof1Bar, prof1BarBg)
        StyleProfFrame(prof2, prof2Frame, prof2Icon, prof2Text, prof2Bar, prof2BarBg)

        if isSide then
            local slotW = VSlotW(inst)
            local totalH = 0
            if prof1.idx and prof1Frame:IsShown() then
                prof1Frame:ClearAllPoints()
                prof1Frame:SetPoint("TOP", content, "TOP", 0, 0)
                totalH = totalH + prof1Frame:GetHeight()
            end
            if prof2.idx and prof2Frame:IsShown() then
                prof2Frame:ClearAllPoints()
                if prof1.idx and prof1Frame:IsShown() then
                    prof2Frame:SetPoint("TOP", prof1Frame, "BOTTOM", 0, -4)
                    totalH = totalH + 4
                else
                    prof2Frame:SetPoint("TOP", content, "TOP", 0, 0)
                end
                totalH = totalH + prof2Frame:GetHeight()
            end
            content:SetSize(slotW, max(totalH, 1))
        else
            content:SetHeight(barH)
            if prof1.idx and prof1Frame:IsShown() then
                prof1Frame:ClearAllPoints(); prof1Frame:SetPoint("LEFT", content, "LEFT", 0, 0)
            end
            if prof2.idx and prof2Frame:IsShown() then
                prof2Frame:ClearAllPoints()
                if prof1.idx and prof1Frame:IsShown() then
                    prof2Frame:SetPoint("LEFT", prof1Frame, "RIGHT", gap, 0)
                else
                    prof2Frame:SetPoint("LEFT", content, "LEFT", 0, 0)
                end
            end

            local totalW = 0
            if prof1.idx and prof1Frame:IsShown() then totalW = totalW + prof1Frame:GetWidth() end
            if prof2.idx and prof2Frame:IsShown() then totalW = totalW + gap + prof2Frame:GetWidth() end
            content:SetWidth(max(totalW, 1))
        end
        if not prof1.idx and not prof2.idx then content:Hide() else content:Show() end
        MaybeRelayout(inst)
    end

    inst.eventFrame = MakeEventFrame(inst, function(self)
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if not built then return 40 end
        if barCtx.IsVertical() then
            local barH = barCtx.GetThickness()
            local p1H, p2H = 0, 0
            if prof1Frame and prof1Frame:IsShown() then p1H = prof1Frame:GetHeight() or 0 end
            if prof2Frame and prof2Frame:IsShown() then p2H = prof2Frame:GetHeight() or 0 end
            local gap = 0
            if p1H > 0 and p2H > 0 then gap = 5 end
            return max(p1H + gap + p2H, barH, 50)
        end
        return max(content:GetWidth() or 80, 30)
    end

    function inst:Destroy()
        self._dead = true
        if prof1Frame then ParkSecureFrame(prof1Frame, self.key .. "_prof1") end
        if prof2Frame then ParkSecureFrame(prof2Frame, self.key .. "_prof2") end
        content:Hide()
    end

    return inst
end

ns.BlockFactories.profession = function(blockCfg, slot, content, barCtx)
    return MakeProfessionBlock(blockCfg, slot, content, barCtx, false)
end

ns.BlockFactories.profession2 = function(blockCfg, slot, content, barCtx)
    return MakeProfessionBlock(blockCfg, slot, content, barCtx, true)
end

-------------------------------------------------------------------------------
--  MICROMENU (SECURE; three verbatim mechanisms)
--    1. Secure click-passthrough buttons (*clickbutton1 -> Blizzard button)
--    2. Combat lockout via RegisterStateDriver _onstate-combatlock snippet
--       (never addon-Lua EnableMouse/SetAlpha on these frames post-creation)
--    3. Blizzard micro menu hider via SecureHandlerStateTemplate _onstate-vis
--       (never :Hide() on MicroMenuContainer from insecure code)
-------------------------------------------------------------------------------
local MM_SPACING = 2
local MM_MEDIA = MEDIA .. "micromenu\\"

-- Button key -> icon file in media\micromenu\ (one PNG per button; the
-- filenames are the art set's own naming, incl. the "acheivements"
-- spelling -- must match the files on disk exactly).
local MM_ICON_FILE = {
    menu    = "menu-options",
    guild   = "menu-guild",
    social  = "menu-friends",
    char    = "menu-character",
    spell   = "menu-spellbook",
    ach     = "menu-acheivements",
    quest   = "menu-quests",
    lfg     = "menu-group",
    pvp     = "menu-pvp",
    housing = "menu-housing",
    journal = "menu-adventure",
    pet     = "menu-collections",
    shop    = "menu-shop",
    help    = "menu-cs",
}

local mmButtonDefs = {
    { key = 'menu',    binding = 'TOGGLEGAMEMENU',    label = MAINMENU_BUTTON,                  special = true },
    { key = 'guild',   binding = 'TOGGLEGUILD',       label = GUILD,                            info = true },
    { key = 'social',  binding = 'TOGGLESOCIAL',      label = SOCIAL_LABEL or SOCIAL_BUTTON,    info = true },
    { key = 'char',    binding = 'TOGGLECHARACTER0',  label = CHARACTER_BUTTON },
    -- Single combined button: PlayerSpellsMicroButton opens the merged
    -- Spec / Talents / Spellbook (and professions) frame.
    { key = 'spell',   binding = 'TOGGLESPELLBOOK',   label = 'Spec / Talents / Spellbook', special = true },
    { key = 'ach',     binding = 'TOGGLEACHIEVEMENT', label = ACHIEVEMENTS },
    { key = 'quest',   binding = 'TOGGLEQUESTLOG',    label = QUEST_LOG },
    { key = 'lfg',     binding = 'TOGGLEGROUPFINDER', label = DUNGEONS_BUTTON },
    { key = 'pvp',     binding = 'TOGGLECHARACTER4',  label = PLAYER_V_PLAYER or PVP_OPTIONS or 'PvP', special = true },
    { key = 'housing', binding = 'TOGGLEHOUSINGDASHBOARD', label = HOUSING_MICRO_BUTTON or 'Housing' },
    { key = 'journal', binding = 'TOGGLEENCOUNTERJOURNAL', label = ADVENTURE_JOURNAL,            special = true },
    { key = 'pet',     binding = 'TOGGLECOLLECTIONS', label = COLLECTIONS },
    { key = 'shop',    binding = false,               label = BLIZZARD_STORE },
    { key = 'help',    binding = false,               label = HELP_BUTTON },
}
local mmButtonOrder = {}
local mmButtonDefsByKey = {}
for _, def in ipairs(mmButtonDefs) do
    mmButtonOrder[#mmButtonOrder + 1] = def.key
    mmButtonDefsByKey[def.key] = def
end

-- String names for Blizzard MicroButtons, resolved via _G at creation time.
-- Spellbook/talents/journal MUST be opened via a secure click on the
-- Blizzard micro button: opening them from addon Lua taints the frame's
-- execution and SetCooldown then rejects secret values (12.x) inside
-- Blizzard_SpellBookItem. Candidate lists: first existing global wins.
local MM_MICRO_BUTTON_NAMES = {
    guild   = "GuildMicroButton",
    social  = "QuickJoinToastButton",
    char    = "CharacterMicroButton",
    spell   = { "PlayerSpellsMicroButton", "SpellbookMicroButton" },
    journal = { "EJMicroButton" },
    ach     = "AchievementMicroButton",
    quest   = "QuestLogMicroButton",
    lfg     = "LFDMicroButton",
    housing = "HousingMicroButton",
    pet     = "CollectionsMicroButton",
    shop    = "StoreMicroButton",
    help    = "HelpMicroButton",
}

-- Plain-button click handlers (no Blizzard secure backing). Shared table:
-- they close over no instance state.
local mmClickFunctions = {}
mmClickFunctions.menu = function(_, button)
    if button == "LeftButton" then
        if not InCombatLockdown() then ToggleFrame(GameMenuFrame) end
    elseif button == "RightButton" then
        if IsShiftKeyDown() then C_UI.Reload()
        elseif not InCombatLockdown() then ToggleFrame(AddonList) end
    end
end
local function MMBlockedInCombat(button)
    return button ~= "LeftButton" or InCombatLockdown()
end
mmClickFunctions.spell = function(_, button)
    if MMBlockedInCombat(button) then return end
    if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
        PlayerSpellsUtil.ToggleSpellBookFrame()
    elseif _G.SpellBookFrame then ToggleFrame(_G.SpellBookFrame) end
end
mmClickFunctions.pvp = function(_, button)
    if MMBlockedInCombat(button) then return end
    if _G.TogglePVPUI then
        _G.TogglePVPUI()
    elseif _G.PVEFrame and _G.PVEFrame:IsShown() then
        -- Behave as a toggle: close when already on the PvP tab, otherwise
        -- switch to it.
        if PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(_G.PVEFrame) == 2 then
            HideUIPanel(_G.PVEFrame)
        elseif PanelTemplates_SetTab then
            PanelTemplates_SetTab(_G.PVEFrame, 2)
        else
            HideUIPanel(_G.PVEFrame)
        end
    elseif _G.LFDMicroButton and _G.LFDMicroButton.Click then
        _G.LFDMicroButton:Click()
        C_Timer.After(0, function()
            if _G.PVEFrame and _G.PVEFrame:IsShown() and PanelTemplates_SetTab then
                PanelTemplates_SetTab(_G.PVEFrame, 2)
            end
        end)
    end
end
mmClickFunctions.journal = function(_, button)
    if MMBlockedInCombat(button) then return end
    -- Go through Blizzard's toggle so the frame is placed by the UI panel
    -- system; ej:Show() directly would bypass ShowUIPanel.
    if _G.ToggleEncounterJournal then
        _G.ToggleEncounterJournal()
    else
        if _G.EncounterJournal_LoadUI then _G.EncounterJournal_LoadUI() end
        local ej = _G.EncounterJournal
        if ej then
            if ej:IsShown() then HideUIPanel(ej) else ShowUIPanel(ej) end
        end
    end
end

-- Blizzard micro menu hider. Calling frame:Hide() from addon Lua on Edit
-- Mode managed frames (MicroMenuContainer) writes taint into the managed
-- frame system; the next ActionBarController_UpdateAll (e.g. vehicle exit)
-- is then blocked. The hider's _onstate-vis runs inside the secure context.
local mmHiders = {}
local function MMGetHider(frame)
    local hider = mmHiders[frame]
    if hider then return hider end
    if InCombatLockdown() then return nil end
    hider = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
    hider:SetFrameRef("target", frame)
    hider:SetAttribute("_onstate-vis", [[
        local target = self:GetFrameRef('target')
        if newstate == 'hide' then target:Hide() else target:Show() end
    ]])
    mmHiders[frame] = hider
    return hider
end

-- Union semantics (DECIDED): Blizzard's micro menu is hidden iff ANY
-- micromenu block on an enabled, non-deleted bar has
-- settings.disableBlizzardMicroMenu. Recomputed on every micromenu
-- Refresh/Destroy and every bar enable/disable/delete (engine calls this
-- from AfterBarStateChange).
local mmLastApplied = nil  -- last driver state pushed ("hide"/"show"); nil = never touched
function ns.RefreshMicroMenuHider()
    local hide = false
    local profile = ns.GetProfile()
    if profile then
        local bars = profile.bars
        for i = 1, #bars do
            local bar = bars[i]
            if bar.enabled ~= false and bar.visibility ~= "never" then
                for j = 1, #bar.blocks do
                    local b = bar.blocks[j]
                    if b.type == "micromenu" and b.settings and b.settings.disableBlizzardMicroMenu then
                        hide = true
                    end
                end
            end
        end
    end
    -- Never touch Blizzard's micro menu until a block has actually opted in:
    -- with nothing ever applied, a "show" result needs no restore, so bars
    -- without micromenu blocks never create hiders on the managed frames.
    if not hide and mmLastApplied == nil then return end
    -- Steady-state guard: re-registering the same driver re-runs the secure
    -- snippet (and re-Shows the target) for no reason. Only push changes.
    local want = hide and "hide" or "show"
    if want == mmLastApplied then return end
    mmLastApplied = want
    ns.DeferUntilOOC("edb_mm_blizz", function()
        -- Build the target list without array holes (any of these globals
        -- may be absent on a given client).
        local targets = {}
        if _G.MicroMenuContainer then targets[#targets + 1] = _G.MicroMenuContainer end
        if _G.MainMenuBarMicroButtons then targets[#targets + 1] = _G.MainMenuBarMicroButtons end
        if _G.MicroButtonAndBagsBar then targets[#targets + 1] = _G.MicroButtonAndBagsBar end
        for i = 1, #targets do
            local hider = MMGetHider(targets[i])
            if hider then
                UnregisterStateDriver(hider, "vis")
                RegisterStateDriver(hider, "vis", want)
            end
        end
    end)
end

ns.BlockFactories.micromenu = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = {
        "GUILD_ROSTER_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
        "FRIENDLIST_UPDATE",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
    }

    -- Per-instance button sets (unique global names per instance).
    local frames = {}
    local icons = {}
    local textFS = {}
    local bgTexture = {}
    local lastRosterRequest = 0

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local function GetIconSize()
        -- Fixed content size: the bar's Height setting never scales the
        -- icons (Content Scale does).
        return max(16, floor(CONTENT_BASE * 0.82 + 0.5))
    end

    local function SocialFontSize()
        -- 0.3667 ratio = 11px at the 30px base (user-tuned: 16 -> 12 ->
        -- 9 -> 11).
        return max(7, floor(CONTENT_BASE * 0.3667 + 0.5))
    end

    local function ShowButtonTooltip(name)
        if name == 'social' or name == 'guild' then return end
        local frame = frames[name]; if not frame then return end
        local def = mmButtonDefsByKey[name]; if not def then return end
        local r, g, b = 1, 1, 1
        ns.Tip_Begin(frame)
        local title = '|cFFFFFFFF' .. (def.label or name) .. '|r'
        if def.binding then
            local k1, k2 = GetBindingKey(def.binding)
            local keys = {}
            if k1 and k1 ~= '' then keys[#keys + 1] = GetBindingText(k1) end
            if k2 and k2 ~= '' then keys[#keys + 1] = GetBindingText(k2) end
            if #keys > 0 then
                title = title .. ' |cFFFFD200(' .. tconcat(keys, ' / ') .. ')|r'
            end
        end
        ns.Tip_AddLine(title, r, g, b)

        if name == 'ach' then
            local pts = 0
            if GetTotalAchievementPoints then pts = GetTotalAchievementPoints() or 0 end
            local hexAccent = format('%02x%02x%02x', floor(r * 255), floor(g * 255), floor(b * 255))
            ns.Tip_AddLine(" ")
            ns.Tip_AddDouble('|cFFFFFFFF' .. L["ACH_POINTS"] .. '|r', '|cFF' .. hexAccent .. pts .. '|r', 1, 1, 1, r, g, b)
        end

        if name == 'journal' then
            local hexAccent = format('%02x%02x%02x', floor(r * 255), floor(g * 255), floor(b * 255))
            ns.Tip_AddLine(" ")
            local delveRank, delveMax = 0, '?'
            if C_DelvesUI and C_DelvesUI.GetDelvesFactionForSeason
               and C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
                local fid = C_DelvesUI.GetDelvesFactionForSeason()
                if fid then
                    delveRank = C_MajorFactions.GetCurrentRenownLevel(fid) or 0
                    if C_MajorFactions.GetRenownLevels then
                        local levels = C_MajorFactions.GetRenownLevels(fid)
                        if type(levels) == 'table' and #levels > 0 then
                            delveMax = tostring(#levels)
                        end
                    end
                end
            end
            ns.Tip_AddDouble('|cFFFFFFFF' .. L["DELVE_JOURNEY"] .. '|r',
                '|cFF' .. hexAccent .. delveRank .. '|r |cFFAAAAAA/ ' .. delveMax .. '|r', 1, 1, 1, r, g, b)
            local companionLvl = 0
            if C_DelvesUI and C_DelvesUI.GetFactionForCompanion and C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                local cfid = C_DelvesUI.GetFactionForCompanion()
                if cfid then
                    local fi = C_GossipInfo.GetFriendshipReputation(cfid)
                    if fi and fi.reaction then
                        companionLvl = tonumber(fi.reaction:match("%d+")) or 0
                    end
                end
            end
            ns.Tip_AddDouble('|cFFFFFFFF' .. L["COMPANION_LEVEL"] .. '|r',
                '|cFF' .. hexAccent .. companionLvl .. '|r', 1, 1, 1, r, g, b)
        end

        ns.Tip_Show()
    end

    -- Per-button hover/click wiring. Runs once per frame, at creation time.
    local function SetupButtonScripts(name, frame)
        local isSecure = frame:GetAttribute("*clickbutton1") ~= nil
        if not isSecure then
            -- Plain button (special actions with no Blizzard micro button:
            -- menu, pvp; plus spell/journal on clients missing the global).
            -- Safe to call EnableMouse and SetScript freely.
            frame:EnableMouse(true)
            frame:RegisterForClicks("AnyUp")
            local fn = mmClickFunctions[name]
            if fn then
                frame:SetScript("OnClick", fn)
            else
                frame:SetScript("OnClick", function() end)
            end
        else
            -- Secure button: RegisterForClicks is permitted before combat;
            -- SetScript("OnClick") is not.
            frame:RegisterForClicks("AnyUp")
        end

        -- OnEnter / OnLeave are never protected, safe on all button types.
        frame:SetScript("OnEnter", function()
            if InCombatLockdown() then return end
            local r, g, b = ns.GetAccent()
            if icons[name] then
                icons[name]:SetVertexColor(r, g, b, 1)
            end
            -- The counter text (guild/social) follows its button's hover.
            if textFS[name] then
                textFS[name]:SetTextColor(r, g, b, 1)
            end
            ShowButtonTooltip(name)
        end)
        frame:SetScript("OnLeave", function()
            local br, bgr, bb = BlockColorOf(blockCfg)
            if icons[name] then icons[name]:SetVertexColor(br, bgr, bb, 1) end
            if textFS[name] then textFS[name]:SetTextColor(br, bgr, bb, 1) end
            ns.Tip_Hide(frame)
        end)
    end

    -- Create one button frame (idempotent). Returns nil in combat: secure
    -- frame creation/attribute setup must wait for PLAYER_REGEN_ENABLED.
    local function EnsureButtonFrame(def)
        local key = def.key
        if frames[key] then return frames[key] end
        if InCombatLockdown() then return nil end
        local microBtnName = MM_MICRO_BUTTON_NAMES[key]
        local microRef
        if type(microBtnName) == "table" then
            for _, n in ipairs(microBtnName) do
                microRef = _G[n]
                if microRef then break end
            end
        elseif microBtnName then
            microRef = _G[microBtnName]
        end
        if key == 'housing' and not microRef then
            -- Skip housing if the Blizzard micro button does not exist.
            return nil
        end
        local frame
        local gname = "EWB_MM_" .. inst.key .. "_" .. key
        if microRef then
            -- Taint-safe: pass clicks through to the Blizzard MicroButton.
            frame = CreateFrame("Button", gname, content,
                "SecureActionButtonTemplate,SecureHandlerStateTemplate")
            frame:SetAttribute("*clickbutton1", microRef)
            -- Without this, the ActionButtonUseKeyDown CVar makes the secure
            -- handler act on key-down only, discarding our "AnyUp" clicks.
            frame:SetAttribute("useOnKeyDown", false)
            frame:SetAttribute("*type1", "click")
            frame:EnableMouse(true)
            frame:RegisterForClicks("AnyUp")
            -- Disable in combat from within the secure environment (no
            -- addon-Lua EnableMouse calls on this frame ever again).
            RegisterStateDriver(frame, "combatlock", "[combat] combat; nocombat")
            frame:SetAttribute("_onstate-combatlock", [[
                if newstate == 'combat' then
                    self:SetAttribute('*type1', nil)
                    self:EnableMouse(false)
                else
                    self:SetAttribute('*type1', 'click')
                    self:EnableMouse(true)
                end
            ]])
        else
            -- Plain button for special actions with no secure backing.
            frame = CreateFrame("Button", gname, content)
            frame:EnableMouse(true)
        end
        frames[key] = frame
        if def.info then
            textFS[key]    = frame:CreateFontString(nil, "OVERLAY")
            bgTexture[key] = frame:CreateTexture(nil, "OVERLAY")
            AttachTextOffset(inst, textFS[key])
        end
        icons[key] = frame:CreateTexture(nil, "OVERLAY")
        icons[key]:SetTexture(MM_MEDIA .. (MM_ICON_FILE[key] or key) .. ".png")
        SetupButtonScripts(key, frame)
        return frame
    end

    -- Materialise buttons for every enabled key. Tolerates a nil/partial
    -- set in combat; the REGEN_ENABLED event retries.
    local function CreateFramesInner()
        local mm = D()
        for _, def in ipairs(mmButtonDefs) do
            if mm[def.key] then EnsureButtonFrame(def) end
        end
    end

    local function ApplyCombatState()
        local hideForCombat = InCombatLockdown()
        if hideForCombat then content:Hide() else content:Show() end
        -- Only toggle EnableMouse on plain (non-secure) buttons; secure
        -- buttons manage their own mouse state via _onstate-combatlock.
        for _, frame in pairs(frames) do
            if frame and not frame:GetAttribute("*clickbutton1") then
                frame:EnableMouse(not hideForCombat)
            end
        end
    end

    local function UpdateGuildText()
        local mm = D()
        if not textFS.guild or not mm.guild or mm.hideSocialText then return end
        if not IsInGuild() then
            textFS.guild:Hide()
            return
        end
        -- Throttled: GuildRoster() itself fires GUILD_ROSTER_UPDATE, which
        -- re-enters this function; unthrottled that is a request loop.
        local now = GetTime()
        if not InCombatLockdown() and (now - lastRosterRequest) >= 15 then
            lastRosterRequest = now
            C_GuildInfo.GuildRoster()
        end
        local _, online = GetNumGuildMembers()
        ns.SetFont(textFS.guild, SocialFontSize(), BC())
        -- Keep the hover tint if a roster event repaints mid-hover.
        if frames.guild and frames.guild:IsMouseOver() then
            local ar, ag, ab = ns.GetAccent()
            textFS.guild:SetTextColor(ar, ag, ab, 1)
        else
            textFS.guild:SetTextColor(BlockColorOf(blockCfg))
        end
        textFS.guild:SetText(online)
        -- Plain button-center anchor: the block's Text Position offsets are
        -- the ONE positioning input (the wrapper injects them here).
        textFS.guild:SetPoint('CENTER', frames.guild, 'CENTER', 0, 0)
        if bgTexture.guild then
            bgTexture.guild:SetPoint('CENTER', textFS.guild)
            bgTexture.guild:SetColorTexture(0.04, 0.04, 0.04, 0.85)
            bgTexture.guild:Show()
        end
        textFS.guild:Show()
    end

    local function UpdateFriendText()
        local mm = D()
        if mm.hideSocialText or not mm.social or not textFS.social then return end
        local _, bnOnline = BNGetNumFriends()
        local total = (bnOnline or 0) + C_FriendList.GetNumOnlineFriends()
        ns.SetFont(textFS.social, SocialFontSize(), BC())
        -- Keep the hover tint if a roster event repaints mid-hover.
        if frames.social and frames.social:IsMouseOver() then
            local ar, ag, ab = ns.GetAccent()
            textFS.social:SetTextColor(ar, ag, ab, 1)
        else
            textFS.social:SetTextColor(BlockColorOf(blockCfg))
        end
        textFS.social:SetText(total)
        -- Plain button-center anchor (see the guild counter note).
        textFS.social:SetPoint('CENTER', frames.social, 'CENTER', 0, 0)
        if bgTexture.social then
            bgTexture.social:SetPoint('CENTER', textFS.social)
            bgTexture.social:SetColorTexture(0.04, 0.04, 0.04, 0.85)
        end
    end

    function inst:Refresh()
        ns.RefreshMicroMenuHider()
        ApplyCombatState()
        if not content:IsShown() then return end
        if InCombatLockdown() then return end

        local mm = D()
        -- Materialise any buttons enabled after creation (options toggle).
        CreateFramesInner()
        if not next(frames) then return end
        local ICON_SIZE = GetIconSize()
        local isVertical = barCtx.IsVertical()
        local totalWidth, totalHeight, prev = 0, 0, nil
        for _, key in ipairs(mmButtonOrder) do
            local frame = frames[key]
            -- Hide buttons toggled off after creation; lay out enabled ones.
            if frame and not mm[key] then
                frame:Hide()
                frame = nil
            end
            if frame then
                frame:Show()
                frame:SetSize(ICON_SIZE, ICON_SIZE)
                if icons[key] then
                    icons[key]:ClearAllPoints()
                    icons[key]:SetPoint("CENTER")
                    -- The drawn image sits 6px smaller than the button (the
                    -- click target and layout keep ICON_SIZE). Uniform for
                    -- the whole set: the old housing 84% special case was
                    -- compensation for the previous art and is gone.
                    local iconSize = max(8, ICON_SIZE - 6)
                    icons[key]:SetSize(iconSize, iconSize)
                    icons[key]:SetVertexColor(BlockColorOf(blockCfg))
                end
                frame:ClearAllPoints()
                local spacing = mm.iconSpacing or MM_SPACING
                if prev and prev == frames.menu then spacing = mm.mainMenuSpacing or 4 end
                if not prev then
                    if isVertical then frame:SetPoint("TOP", content, "TOP", 0, 0)
                    else               frame:SetPoint("LEFT", content, "LEFT", 0, 0) end
                else
                    if isVertical then frame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
                    else               frame:SetPoint("LEFT", prev, "RIGHT", spacing, 0) end
                end
                local prevSpacing = 0
                if prev then prevSpacing = spacing end
                if isVertical then
                    totalHeight = totalHeight + ICON_SIZE + prevSpacing
                    totalWidth  = max(totalWidth, ICON_SIZE)
                else
                    totalWidth  = totalWidth + ICON_SIZE + prevSpacing
                    totalHeight = max(totalHeight, ICON_SIZE)
                end
                prev = frame
            end
        end

        content:SetSize(max(totalWidth, 1), max(totalHeight, 1))

        if mm.hideSocialText then
            for _, fs in pairs(textFS) do fs:Hide() end
        else
            UpdateFriendText(); UpdateGuildText()
        end
        MaybeRelayout(inst)
    end

    inst.eventFrame = MakeEventFrame(inst, function(self, event)
        if event == 'GUILD_ROSTER_UPDATE' then
            UpdateGuildText()
        elseif event == 'BN_FRIEND_ACCOUNT_ONLINE'
            or event == 'BN_FRIEND_ACCOUNT_OFFLINE'
            or event == 'FRIENDLIST_UPDATE' then
            UpdateFriendText()
        else
            -- REGEN x2 / PLAYER_ENTERING_WORLD: retry deferred button
            -- creation and re-apply the combat state.
            ApplyCombatState()
            self:Refresh()
        end
    end)

    CreateFramesInner()

    function inst:Enable()
        content:Show()
        RegisterInstEvents(self)
        ns.RefreshMicroMenuHider()
        ApplyCombatState()
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        local mm = D()
        local ICON_SIZE = GetIconSize()
        local count = 0
        for _, key in ipairs(mmButtonOrder) do
            if frames[key] and mm[key] then count = count + 1 end
        end
        if count == 0 then return 50 end
        local spacing = mm.iconSpacing or 2
        return max(count * ICON_SIZE + (count - 1) * spacing, 50)
    end

    function inst:Destroy()
        self._dead = true
        for key, frame in pairs(frames) do
            ParkSecureFrame(frame, self.key .. "_" .. key)
        end
        content:Hide()
        -- The union recomputes without this instance's bar/block cfg (the
        -- engine removes the cfg before calling Destroy).
        ns.RefreshMicroMenuHider()
    end

    return inst
end

-------------------------------------------------------------------------------
--  CURRENCY (searchable-picker driven; icon + amount + owned tooltip)
-------------------------------------------------------------------------------
ns.BlockFactories.currency = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "CURRENCY_DISPLAY_UPDATE" }

    local mouseOver = false
    local _curFitBuf = { "" }

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local icon = button:CreateTexture(nil, "OVERLAY")
    local amountText = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, amountText)

    local function GetInfo()
        local s = D()
        if not s.currencyId then return nil end
        if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
        local info = C_CurrencyInfo.GetCurrencyInfo(s.currencyId)
        if info and info.discovered ~= false then return info end
        return nil
    end

    function inst:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = 4

        local info = GetInfo()
        local text
        if not s.currencyId then
            text = L["SELECT_CURRENCY"]
        elseif info then
            if BreakUpLargeNumbers then
                text = BreakUpLargeNumbers(info.quantity or 0)
            else
                text = tostring(info.quantity or 0)
            end
        else
            text = "-"
        end

        local iconSz = 0
        if s.showIcon ~= false and info and info.iconFileID then
            iconSz = fontSize + 2
            icon:SetTexture(info.iconFileID)
            icon:SetTexCoord(5 / 64, 59 / 64, 5 / 64, 59 / 64)
            icon:Show()
        else
            icon:Hide()
        end

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            _curFitBuf[1] = text
            ns.SetFont(amountText, fontSize, barCfg)
            amountText:SetText(text)
            local totalH = 8
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("TOP", button, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            ns.SetWrappedText(amountText, innerW, "CENTER")
            amountText:ClearAllPoints()
            if iconSz > 0 then
                amountText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                amountText:SetPoint("TOP", button, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(amountText:GetStringHeight()) + 4
            totalH = max(totalH, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 120)
            local textBudget = max(20, slotW - iconSz - gap - 8)
            _curFitBuf[1] = text
            ns.SetFont(amountText, fontSize, barCfg)
            ns.ResetInlineText(amountText, "LEFT")
            amountText:SetText(text)
            if iconSz > 0 then
                iconSz = fontSize + 2
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", button, "LEFT", 0, 0)
            end
            amountText:ClearAllPoints()
            local xOff = 0
            if iconSz > 0 then xOff = iconSz + gap end
            amountText:SetPoint("LEFT", button, "LEFT", xOff, 0)
            local tw = ns.SnapToPixelGrid(amountText:GetStringWidth())
            local totalW = min(slotW, iconSz + (iconSz > 0 and gap or 0) + tw + 4)
            content:SetSize(max(totalW, 10), barH)
            button:SetSize(max(totalW, 10), barH)
        end

        local cbr, cbg, cbb = BlockColorOf(blockCfg)
        icon:SetVertexColor(cbr, cbg, cbb, 1)
        if not s.currencyId then
            amountText:SetTextColor(0.55, 0.55, 0.55, 1)
        elseif mouseOver then
            local ar, ag, ab = ns.GetAccent()
            amountText:SetTextColor(ar, ag, ab, 1)
        else
            amountText:SetTextColor(cbr, cbg, cbb, 1)
        end
        MaybeRelayout(inst)
    end

    -- Manual tooltip composition (the owned tooltip has no SetCurrencyByID).
    local function ShowCurrencyTooltip()
        local s = D()
        if not s.currencyId then return end
        local info = nil
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            info = C_CurrencyInfo.GetCurrencyInfo(s.currencyId)
        end
        if not info then return end
        ns.Tip_Begin(button)
        local qr, qg, qb = 1, 1, 1
        if info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality] then
            local qc = ITEM_QUALITY_COLORS[info.quality]
            qr, qg, qb = qc.r, qc.g, qc.b
        end
        ns.Tip_AddLine(info.name or "?", qr, qg, qb)
        if info.description and info.description ~= "" then
            ns.Tip_AddLine(" ")
            ns.Tip_AddWrappedLine(info.description, 280, 0.8, 0.8, 0.8)
        end
        ns.Tip_AddLine(" ")
        local qty
        if BreakUpLargeNumbers then qty = BreakUpLargeNumbers(info.quantity or 0) else qty = tostring(info.quantity or 0) end
        if info.maxQuantity and info.maxQuantity > 0 then
            local maxQty
            if BreakUpLargeNumbers then maxQty = BreakUpLargeNumbers(info.maxQuantity) else maxQty = tostring(info.maxQuantity) end
            ns.Tip_AddDouble(L["TOTAL"], qty .. " / " .. maxQty, 0.6, 0.6, 0.6, 1, 1, 1)
        else
            ns.Tip_AddDouble(L["TOTAL"], qty, 0.6, 0.6, 0.6, 1, 1, 1)
        end
        ns.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        ShowCurrencyTooltip()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(button)
        inst:Refresh()
    end)
    button:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" then
            if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
                C_CurrencyInfo.OpenCurrencyPanel()
            elseif ToggleCharacter then
                ToggleCharacter("TokenFrame")
            end
        end
    end)

    inst.eventFrame = MakeEventFrame(inst, function(self)
        self:Refresh()
    end)

    function inst:Enable()
        content:Show()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        content:Hide()
    end

    return inst
end

-------------------------------------------------------------------------------
--  SPACER (transparent block; the slot's optional bg tint still applies)
-------------------------------------------------------------------------------
ns.BlockFactories.spacer = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    function inst:Refresh() end
    function inst:Enable() end
    function inst:Disable() end
    function inst:Destroy() self._dead = true end
    function inst:GetAutoLength() return 0 end
    return inst
end
