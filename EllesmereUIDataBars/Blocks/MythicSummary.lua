if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI.IS_FOREVER then return end -- Mythic+ Tools does not load on WoW Forever: no runs, no factory (the main file drops the block from BLOCK_TYPES too)
-- Blocks\MythicSummary.lua
-- Mythic+ run summary block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local pairs            = pairs
local type             = type
local format           = string.format
local floor            = math.floor
local max              = math.max
local min              = math.min

local CONTENT_BASE     = K.CONTENT_BASE
local InstKey          = K.InstKey
local HBudget          = K.HBudget
local VSlotW           = K.VSlotW
local MaybeRelayout    = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf     = K.BlockColorOf

-------------------------------------------------------------------------------
--  M+ SUMMARY (newest Run Summary record; click opens it like /ov, the
--  tooltip lists every stored run, Right Click clears them)
--
--  Runs are stored by Mythic+ Tools (EllesmereUI._MythicRuns), which calls its
--  OnChanged when one is added or the history is cleared. The hook is set only
--  while a block is enabled and cleared with the last one, so this registers
--  no events.
-------------------------------------------------------------------------------
local liveInsts = {}

local function OnRunsChanged()
    for inst in pairs(liveInsts) do inst:Refresh() end
end

-- Bars are built at login, after Mythic+ Tools has loaded.
local function SyncRunsHook()
    local mr = EllesmereUI._MythicRuns
    if mr then mr.OnChanged = next(liveInsts) and OnRunsChanged or nil end
end

local function Runs()
    local mr = EllesmereUI._MythicRuns
    return mr and mr.Get()
end

local function LatestRun()
    local runs = Runs()
    return runs and runs[1]
end

-- Level in its keystone-rarity color, as in the Run Summary header.
local function RunText(rec)
    if not rec then return EllesmereUI.L("No runs recorded yet") end
    local level = "+" .. (rec.level or 0)
    local kcol = C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor
        and C_ChallengeMode.GetKeystoneLevelRarityColor(rec.level or 0)
    if type(kcol) == "table" and kcol.r then
        level = EllesmereUI.HexColor(kcol.r, kcol.g, kcol.b) .. level .. "|r"
    end
    return level .. " " .. (rec.mapName or "?")
end

-- Completion time as m:ss, green when timed, red when depleted.
local function RunTime(rec)
    local ms = rec.timeMS
    if not ms then return "-", 0.6, 0.6, 0.6 end
    local secs = floor(ms / 1000)
    local text = format("%d:%02d", floor(secs / 60), secs % 60)
    if rec.onTime then return text, 0.176, 0.796, 0.349 end
    return text, 0.9, 0.3, 0.3
end

local function ConfirmClear()
    local mr = EllesmereUI._MythicRuns
    local clear = mr and mr.Clear
    if not clear then return end
    EllesmereUI:ShowConfirmPopup({
        title = "Clear Run History",
        message = "Delete every recorded Mythic+ run for this character?",
        confirmText = "Delete",
        cancelText = "Cancel",
        onConfirm = clear,
    })
end

ns.BlockFactories.mplussummary = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)

    local mouseOver = false

    local function D() return blockCfg.settings or {} end

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local label = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, label)

    function inst:Refresh()
        if self._dead then return end
        local barCfg = barCtx.cfg
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local rec = LatestRun()
        -- Hide When Empty: no runs collapses the block (GetAutoLength reports
        -- 0, so the solver drops the slot). Show/Hide wait out lockdown.
        local collapsed = not rec and D().hideWhenEmpty == true
        if content:IsShown() == collapsed then
            if InCombatLockdown() then
                ns.DeferUntilOOC("mplussummary:" .. inst.key, function() inst:Refresh() end)
            elseif collapsed then
                content:Hide()
            else
                content:Show()
            end
        end
        if collapsed then
            MaybeRelayout(inst)
            return
        end
        local text = RunText(rec)

        ns.SetFont(label, fontSize, barCfg)
        if mouseOver then
            label:SetTextColor(ns.GetAccent())
        else
            label:SetTextColor(BlockColorOf(blockCfg))
        end
        -- A secure overlay elsewhere on the bar protects its geometry in
        -- lockdown: only the text updates now, sizing waits for regen.
        if InCombatLockdown() then
            label:SetText(text)
            ns.DeferUntilOOC("mplussummary:" .. inst.key, function() inst:Refresh() end)
            return
        end
        if barCtx.IsVertical() then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            label:SetText(text)
            ns.SetWrappedText(label, innerW, "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", button, "TOP", 0, -4)
            local totalH = max(8 + ns.SnapToPixelGrid(label:GetStringHeight()) + 4, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 180)
            ns.ResetInlineText(label, "LEFT")
            label:SetText(text)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 0, 0)
            local tw = ns.SnapToPixelGrid(label:GetStringWidth())
            local totalW = max(min(slotW, tw + 4), 10)
            content:SetSize(totalW, barH)
            button:SetSize(totalW, barH)
        end
        MaybeRelayout(inst)
    end

    local function ShowSummaryTooltip()
        local ar, ag, ab = ns.GetAccent()
        local runs = Runs()
        local count = runs and #runs or 0
        ns.Tip_Begin(button)
        ns.Tip_AddLine("|cFFFFFFFF[|r" .. EllesmereUI.L("Run Summary") .. "|cFFFFFFFF]|r", ar, ag, ab)
        ns.Tip_AddLine(" ")
        if count == 0 then
            ns.Tip_AddLine(EllesmereUI.L("No runs recorded yet"), 0.6, 0.6, 0.6)
        end
        for i = 1, count do
            local rec = runs[i]
            local t, tr, tg, tb = RunTime(rec)
            ns.Tip_AddDouble(RunText(rec), t, 0.8, 0.8, 0.8, tr, tg, tb)
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], EllesmereUI.L("Open Run Summary"), 1, 1, 1, ar, ag, ab)
        if count > 0 then
            ns.Tip_AddDouble(L["RIGHT_CLICK"], EllesmereUI.L("Clear Run History"), 1, 1, 1, ar, ag, ab)
        end
        ns.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        ShowSummaryTooltip()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(button)
        inst:Refresh()
    end)
    -- Same path as typing /ov, so a disabled Run Summary prints the same error.
    button:SetScript("OnClick", function(_, mb)
        if mb == "RightButton" then
            if LatestRun() then ConfirmClear() end
            return
        end
        if mb ~= "LeftButton" then return end
        local ov = SlashCmdList and SlashCmdList.EUIMPLUS
        if ov then ov("") end
    end)

    function inst:Enable()
        liveInsts[self] = true
        SyncRunsHook()
        self:Refresh()
    end

    function inst:Disable()
        liveInsts[self] = nil
        SyncRunsHook()
        ns.Tip_Hide(button)
        content:Hide()
    end

    function inst:GetAutoLength()
        if not content:IsShown() then return 0 end
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        liveInsts[self] = nil
        SyncRunsHook()
        content:Hide()
    end

    return inst
end
