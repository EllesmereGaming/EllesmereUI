if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Stats.lua
-- FPS, latency, durability and combat block factories.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer          = C_Timer
local GetTime          = GetTime
local format           = string.format
local tsort            = table.sort
local floor            = math.floor
local max              = math.max
local min              = math.min

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local IconColorOf          = K.IconColorOf

-------------------------------------------------------------------------------
--  FPS + MS (separate block types built on one single-line stat renderer)
-------------------------------------------------------------------------------
-- Game-wide addon memory scan cache (fps tooltip; shared by design).
local sysMemTable = {}
local function sysMemSort(a, b) return a.mem > b.mem end
local sysLastMemScanTime = 0

local FPS_THRESHOLD = 60
local function GetFPSColor(fps)
    local lb = FPS_THRESHOLD * 0.5
    local perc = 1
    if fps < FPS_THRESHOLD then perc = (fps - lb) / lb end
    return ns.SlowColorGradient(perc)
end

-- Latency quality in three bands (green/yellow/red = good/fair/poor); colors are the client's own font-color globals so they match the UI (plain fallbacks if absent). Thresholds in ms.
local LAT_GOOD, LAT_FAIR = 100, 250
local function BandColor(fontColor, dr, dg, db)
    if fontColor and fontColor.GetRGB then return fontColor:GetRGB() end
    return dr, dg, db
end
local function GetLatColor(lat)
    if lat <= LAT_GOOD then return BandColor(GREEN_FONT_COLOR,  0.1, 1.0, 0.1) end
    if lat <= LAT_FAIR then return BandColor(YELLOW_FONT_COLOR, 1.0, 0.82, 0.0) end
    return BandColor(RED_FONT_COLOR, 1.0, 0.1, 0.1)
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
    -- Icon is optional: blocks without opts.hasIcon are text-only.
    local icon
    if opts.hasIcon then
        icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("LEFT")
    end
    local text = frame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, text)
    text:SetPoint("LEFT")
    -- Hidden ruler: the block's width is reserved from a stable TEMPLATE, never the live string, so value changes cannot shift neighbors.
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
        if icon then
            if mouseOver then
                icon:SetVertexColor(r, g, b, 1)
            else
                local ir, ig, ib = IconColorOf(blockCfg)
                icon:SetVertexColor(ir, ig, ib, 1)
            end
        end
    end

    function inst:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        -- 0.4333 = 13px at the 30 base (1px under the standard 0.46 block text).
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local d = D()
        local gap = ICON_GAP
        local isSide = barCtx.IsVertical()
        if lastVal < 0 then lastVal = opts.sample() end
        local str = lastVal .. opts.suffix()

        local iconSz = 0
        if icon then
            K.SetBlockIcon(icon, blockCfg)
        end
        if icon and d.showIcon ~= false then
            iconSz = fontSize + (opts.iconExtra or 0)
        end

        -- No fit-to-slot: fixed size (base font x Text Scale x Content Scale).

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
            -- Template width: digits become "8" padded to >=3, so width only
            -- moves on a digit-count crossing (999ms->1000ms), never on ordinary
            -- changes. Icon/number stay LEFT-anchored; slack sits on the right.
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

    -- Evented stat blocks (opts.events) never touch the heartbeat: the game
    -- names the exact edges their value changes on, so the block samples only
    -- there and costs nothing between them. Time-driven blocks (fps/ms) keep
    -- the shared 1s ticker.
    local function ForceTick()
        tickCount = (opts.interval or 1) - 1
        Tick()
    end

    -- Lets a tooltip resync the bar text with what it just sampled.
    function inst:ForceSample()
        ForceTick()
    end

    -- A sample taken right when an event fires can catch the source before
    -- it's populated. Resample once more after a short delay to catch that.
    -- One outstanding retry at a time: event bursts (durability drops hit
    -- many items per damage wave) would otherwise queue a timer closure each.
    local retryPending = false
    local function ForceTickChecked()
        ForceTick()
        if opts.retryDelay and not retryPending then
            retryPending = true
            C_Timer.After(opts.retryDelay, function()
                retryPending = false
                if not inst._dead then ForceTick() end
            end)
        end
    end

    -- Same-frame event bursts (a damage wave fires the durability AND alert
    -- events per slot) collapse to ONE sample after the frame settles.
    local flushPending = false
    local function FlushEventSample()
        flushPending = false
        if not inst._dead then ForceTickChecked() end
    end
    local function OnEventSample()
        if flushPending then return end
        flushPending = true
        C_Timer.After(0, FlushEventSample)
    end

    function inst:Enable()
        content:Show()
        lastVal = -1
        -- Sample on the very first tick regardless of interval.
        tickCount = (opts.interval or 1) - 1
        if opts.events then
            if not self.eventFrame then
                self.events = opts.events
                self.eventFrame = MakeEventFrame(self, OnEventSample)
            end
            RegisterInstEvents(self)
            ForceTickChecked()
        else
            ns.RegisterHeartbeat(opts.hbPrefix .. ":" .. self.key, Tick)
        end
    end

    function inst:Disable()
        UnregisterInstEvents(self)
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
        UnregisterInstEvents(self)
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
        -- UpdateAddOnMemoryUsage() iterates every loaded addon and is a noticeable spike; amortise the rescan to once per 30s.
        -- Skipped entirely in combat: on a busy pull that spike can push the
        -- hovered tooltip's whole script past the "script ran too long" watchdog
        -- (field report: Murder Row, adds casting Felfire Orb). The data is
        -- already tolerated at up to 30s stale, so holding it longer is not a
        -- new behaviour; the next out-of-combat hover rescans normally.
        if not skipMemoryScan and not InCombatLockdown() and (now - sysLastMemScanTime) >= 30 then
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
                -- A full GC cycle stalls a frame; only force it when Shift is held so a casual click just prints the snapshot.
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

-- LATENCY. Own factory, not MakeStatBlock: shows one OR two links (home/world/both), each
-- with its own house/globe icon, which the single-icon stat helper cannot do. Bar keeps the
-- block color; green/yellow/red criticality is tooltip-only (GetLatColor).

-- home | world | both. Falls back to the useWorldLatency boolean. Shared by the block and its options row, which must agree on what "selected" means.
function ns.LatencyMode(s)
    if s.latencyMode then return s.latencyMode end
    if s.useWorldLatency then return "world" end
    return "home"
end

ns.BlockFactories.ms = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)

    local mouseOver = false
    local lastSig                    -- skip the relayout when nothing changed

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local button = CreateFrame("Button", nil, content)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    -- Two reusable segments (icon + value); the second stays hidden unless the block is in "both" mode.
    local seg = {}
    for i = 1, 2 do
        local s = { icon = button:CreateTexture(nil, "OVERLAY"), text = button:CreateFontString(nil, "OVERLAY") }
        AttachTextOffset(inst, s.text)
        seg[i] = s
    end

    local function MsTooltip()
        ns.Tip_Begin(content)
        local inKB, outKB, home, world = GetNetStats()
        home = floor(home); world = floor(world)
        -- The tooltip is the full quality read: the colours the bar does not carry, plus bandwidth that is on no bar at all.
        local hr, hg, hb = GetLatColor(home)
        local wr, wg, wb = GetLatColor(world)
        local ms = ns.GetMSSuffix()
        ns.Tip_AddDouble(L["HOME"],  home  .. ms, 0.6, 0.6, 0.6, hr, hg, hb)
        ns.Tip_AddDouble(L["WORLD"], world .. ms, 0.6, 0.6, 0.6, wr, wg, wb)
        local kb = " " .. L["KB_PER_SEC"]
        ns.Tip_AddDouble(L["DOWNLOAD"], format("%.1f", inKB or 0) .. kb, 0.6, 0.6, 0.6, 1, 1, 1)
        ns.Tip_AddDouble(L["UPLOAD"],   format("%.1f", outKB or 0) .. kb, 0.6, 0.6, 0.6, 1, 1, 1)
        ns.Tip_Show()
    end

    function inst:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local showIcon = D().showIcon == true
        local m = ns.LatencyMode(D())
        local links
        if m == "both" then links = { "home", "world" }
        elseif m == "world" then links = { "world" }
        else links = { "home" } end
        local n = #links
        local iconSz = showIcon and (fontSize + 2) or 0

        local _, _, home, world = GetNetStats()
        local vals = { home = floor(home), world = floor(world) }
        local suffix = ns.GetMSSuffix()

        local tr, tg, tb, ir, ig, ib
        if mouseOver then
            tr, tg, tb = ns.GetAccent(); ir, ig, ib = tr, tg, tb
        else
            tr, tg, tb = BlockColorOf(blockCfg); ir, ig, ib = IconColorOf(blockCfg)
        end

        -- Fill each segment; every value carries the unit ("45ms  92ms"), so a lone number never reads as unitless in "both" mode.
        for i = 1, 2 do
            local s, link = seg[i], links[i]
            if link then
                ns.SetFont(s.text, fontSize, barCfg)
                ns.ResetInlineText(s.text, "LEFT")
                s.text:SetText(vals[link] .. suffix)
                s.text:SetTextColor(tr, tg, tb, 1)
                s.text:Show()
                if showIcon then
                    K.SetBlockIcon(s.icon, blockCfg, link)
                    s.icon:SetVertexColor(ir, ig, ib, 1)
                    s.icon:SetSize(iconSz, iconSz)
                    s.icon:Show()
                else
                    s.icon:Hide()
                end
            else
                s.text:Hide(); s.icon:Hide()
            end
        end

        local lineH = max(fontSize + 4, iconSz)
        if isSide then
            -- Stack the links, each a centred "icon value" line.
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            local y = -4
            for i = 1, n do
                local s = seg[i]
                local tw = ns.SnapToPixelGrid(s.text:GetStringWidth())
                local grpW = (showIcon and (iconSz + ICON_GAP) or 0) + tw
                local x0 = max(0, floor((innerW - grpW) / 2))
                s.icon:ClearAllPoints(); s.text:ClearAllPoints()
                if showIcon then
                    s.icon:SetPoint("TOPLEFT", button, "TOPLEFT", x0, y - floor((lineH - iconSz) / 2))
                    s.text:SetPoint("LEFT", s.icon, "RIGHT", ICON_GAP, 0)
                else
                    s.text:SetPoint("TOPLEFT", button, "TOPLEFT", x0, y)
                end
                y = y - lineH - 2
            end
            local totalH = max(-y + 2, barH)
            content:SetSize(slotW, totalH); button:SetSize(slotW, totalH)
        else
            local x, segGap = 0, 8
            for i = 1, n do
                local s = seg[i]
                s.icon:ClearAllPoints(); s.text:ClearAllPoints()
                if showIcon then
                    s.icon:SetPoint("LEFT", button, "LEFT", x, 0)
                    x = x + iconSz + ICON_GAP
                end
                s.text:SetPoint("LEFT", button, "LEFT", x, 0)
                x = x + ns.SnapToPixelGrid(s.text:GetStringWidth())
                if i < n then x = x + segGap end
            end
            local totalW = max(x + 4, 10)
            content:SetSize(totalW, barH); button:SetSize(totalW, barH)
        end
        button:ClearAllPoints(); button:SetPoint("CENTER", content, "CENTER", 0, 0)
        MaybeRelayout(inst)
    end

    -- Latency only moves every ~30s (GetNetStats is cached), so re-lay-out only when the shown value, mode or icon state actually changes.
    local function Tick()
        local _, _, home, world = GetNetStats()
        local sig = ns.LatencyMode(D()) .. (D().showIcon and "I" or "") .. floor(home) .. "/" .. floor(world)
        if sig == lastSig then return end
        lastSig = sig
        inst:Refresh()
    end

    button:SetScript("OnEnter", function() mouseOver = true; inst:Refresh(); MsTooltip() end)
    button:SetScript("OnLeave", function() mouseOver = false; ns.Tip_Hide(content); inst:Refresh() end)

    function inst:Enable()
        content:Show()
        lastSig = nil
        ns.RegisterHeartbeat("ms:" .. self.key, Tick)
    end
    function inst:Disable()
        ns.UnregisterHeartbeat("ms:" .. self.key)
        content:Hide()
    end
    function inst:GetAutoLength()
        if barCtx.IsVertical() then return max(content:GetHeight() or 40, 30) end
        return max(content:GetWidth() or 60, 24)
    end
    function inst:Destroy() self._dead = true; content:Hide() end

    return inst
end

ns.BlockFactories.durability = function(blockCfg, slot, content, barCtx)
    -- Same reading as the Chat sidebar's durability icon: the LOWEST percent across equipped slots 1-18.
    local function SampleDurability()
        local lowest = 100
        for slotId = 1, 18 do
            local cur, mx = GetInventoryItemDurability(slotId)
            if cur and mx and mx > 0 then
                local pct = cur / mx * 100
                if pct < lowest then lowest = pct end
            end
        end
        local pct = floor(lowest)
        K.lastDurabilityPct = pct
        return pct
    end

    local function DurabilityTooltip(inst)
        -- Resync the bar text whenever the tooltip opens.
        if inst then inst:ForceSample() end
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(content)
        ns.Tip_AddDouble("Durability", SampleDurability() .. "%",
            1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end

    return MakeStatBlock(blockCfg, slot, content, barCtx, {
        hbPrefix = "durability",
        hasIcon  = true,
        iconExtra = 7,
        -- Durability only moves on damage/repair edges the game announces, so
        -- the block samples on those events alone -- no heartbeat, and with no
        -- other time-driven block enabled the 1s ticker never runs at all.
        -- Self-repair items recalculate alerts without the durability event.
        events   = { "UPDATE_INVENTORY_DURABILITY", "UPDATE_INVENTORY_ALERTS", "PLAYER_ENTERING_WORLD" },
        -- Retry each sample once, a moment later.
        retryDelay = 2,
        sample   = SampleDurability,
        suffix   = function() return "%" end,
        tooltip  = DurabilityTooltip,
    })
end

ns.BlockFactories.combat = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

    local function IsInCombat()
        return UnitAffectingCombat("player") and 1 or 0
    end

    local function CombatLabel(value)
        return value == 1 and L["IN_COMBAT"] or L["OUT_OF_COMBAT"]
    end

    local function CombatTooltip()
        ns.Tip_Begin(content)
        ns.Tip_AddDouble(L["COMBAT_STATUS"], CombatLabel(IsInCombat()), 1, 1, 1, 1, 1, 1)
        ns.Tip_Show()
    end

    local mouseOver = false
    local lastValue = -1
    local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local frame = CreateFrame("Button", nil, content)
    frame:SetSize(60, 20)
    frame:EnableMouse(true)
    frame:RegisterForClicks("AnyUp")

    local text = frame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, text)
    text:SetPoint("LEFT")

    local measureFS = frame:CreateFontString(nil, "OVERLAY")
    measureFS:Hide()

    local function ApplyColors()
        local r, g, b
        if mouseOver then
            r, g, b = ns.GetAccent()
        else
            r, g, b = BlockColorOf(blockCfg)
        end
        text:SetTextColor(r, g, b, 1)
    end

    function inst:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local isSide = barCtx.IsVertical()
        local value = lastValue
        if value < 0 then value = IsInCombat(); lastValue = value end
        local collapsed = D().onlyInCombat == true and value ~= 1

        if not collapsed and not content:IsShown() then content:Show() end

        ns.SetFont(text, fontSize, barCfg)
        text:SetText(EllesmereUI.L(CombatLabel(value)))
        ApplyColors()

        if InCombatLockdown() then
            MaybeRelayout(inst)
            return
        end

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(36, slotW - 8)
            frame:SetSize(innerW, fontSize + 4)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", content, "CENTER", 0, 0)
            text:ClearAllPoints()
            text:SetPoint("CENTER", frame, "CENTER", 0, 0)
            ns.SetWrappedText(text, innerW, "CENTER")
            content:SetSize(slotW, max(fontSize + 12, barH))
        else
            local align = blockCfg.align or "CENTER"
            ns.ResetInlineText(text, align)
            text:ClearAllPoints()
            text:SetPoint("LEFT", frame, "LEFT", 0, 0)
            ns.SetFont(measureFS, fontSize, barCfg)
            -- Fixed width from the wider label so the block never resizes on
            -- combat edges; either label can be the wide one per locale.
            measureFS:SetText(EllesmereUI.L(CombatLabel(0)))
            local wOut = measureFS:GetStringWidth() or 30
            measureFS:SetText(EllesmereUI.L(CombatLabel(1)))
            local width = max(30, ns.SnapToPixelGrid(max(wOut, measureFS:GetStringWidth() or 30)) + 2)
            text:SetWidth(width)
            frame:SetSize(width, barH)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", content, "CENTER", 0, 0)
            content:SetSize(width, barH)
        end
        if collapsed then
            content:Hide()
            ns.Tip_Hide(content)
        end
        MaybeRelayout(inst)
    end

    local function RefreshFromEvent()
        local value = IsInCombat()
        if value == lastValue then return end
        lastValue = value
        inst:Refresh()
        if mouseOver then CombatTooltip() end
    end

    frame:SetScript("OnEnter", function()
        mouseOver = true
        ApplyColors()
        CombatTooltip()
    end)
    frame:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(content)
        ApplyColors()
    end)

    function inst:Enable()
        content:Show()
        lastValue = -1
        if not self.eventFrame then
            self.eventFrame = MakeEventFrame(self, RefreshFromEvent)
        end
        RegisterInstEvents(self)
        RefreshFromEvent()
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if D().onlyInCombat == true and lastValue ~= 1 then return 0 end
        if not content:IsShown() then return 0 end
        if barCtx.IsVertical() then return max(content:GetHeight() or 40, 40) end
        return max(content:GetWidth() or 70, 40)
    end

    function inst:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        content:Hide()
    end

    return inst
end
