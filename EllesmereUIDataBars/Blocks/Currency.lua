if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Currency.lua
-- Currency block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local floor       = math.floor
local max         = math.max
local min         = math.min

local ICON_GAP             = K.ICON_GAP
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
local IconColorOf          = K.IconColorOf

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

    local function Num(v)
        if BreakUpLargeNumbers then return BreakUpLargeNumbers(v or 0) end
        return tostring(v or 0)
    end

    function inst:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = ICON_GAP

        local info = GetInfo()
        local text
        if not s.currencyId then
            -- Bar text goes straight through SetText, which does not route through the
            -- locale like the Tip_* helpers, so translate by hand (as the Great Vault block does for its own label).
            text = EllesmereUI.L(L["SELECT_CURRENCY"])
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
        do
            local ir, ig, ib = IconColorOf(blockCfg)
            icon:SetVertexColor(ir, ig, ib, 1)
        end
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
        local ar, ag, ab = ns.GetAccent()
        -- Unconfigured: the placeholder is the whole block, so the tooltip has to say where the currency is actually picked.
        if not s.currencyId then
            ns.Tip_Begin(button)
            ns.Tip_AddLine(L["SELECT_CURRENCY"], 1, 1, 1)
            ns.Tip_AddLine(" ")
            ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_SETTINGS"], 1, 1, 1, ar, ag, ab)
            ns.Tip_Show()
            return
        end
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
        -- Some currencies carry paragraphs of flavor text that tower over the bar. Opt-out keeps name, total and click hint; only the text goes.
        if s.showDescription ~= false and info.description and info.description ~= "" then
            ns.Tip_AddLine(" ")
            ns.Tip_AddWrappedLine(info.description, 280, 0.8, 0.8, 0.8)
        end
        ns.Tip_AddLine(" ")
        local qty = Num(info.quantity)
        local cap = info.maxQuantity
        if cap and cap > 0 then
            -- useTotalEarnedForMaxQty currencies (crests) cap what you EARNED this
            -- season, not what you hold, so the wallet total is the wrong numerator.
            if info.useTotalEarnedForMaxQty then
                ns.Tip_AddDouble(L["TOTAL"], qty .. " |cffaaaaaa(" .. Num(info.totalEarned) .. "/" .. Num(cap) .. ")|r",
                    0.6, 0.6, 0.6, 1, 1, 1)
            else
                ns.Tip_AddDouble(L["TOTAL"], qty .. " / " .. Num(cap), 0.6, 0.6, 0.6, 1, 1, 1)
            end
        else
            ns.Tip_AddDouble(L["TOTAL"], qty, 0.6, 0.6, 0.6, 1, 1, 1)
        end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CURRENCIES"], 1, 1, 1, ar, ag, ab)
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
            -- No currency picked yet: the Blizzard panel cannot assign one, so send the player to the picker instead of dead-ending there.
            if not D().currencyId then
                -- Options surface is LoadOnDemand; load it so OpenBlockSettings exists.
                if not ns.OpenBlockSettings then EllesmereUI:EnsureLoaded() end
                if ns.OpenBlockSettings then
                    ns.OpenBlockSettings(barCtx.id, blockCfg.id, "currency")
                end
                return
            end
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
