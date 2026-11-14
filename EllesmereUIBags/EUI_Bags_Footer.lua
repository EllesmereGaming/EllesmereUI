if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Footer.lua
--
--  Gold tracking and its tooltip, the footer with the tracked currencies
--  and the reagent bag window.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local BP, CurrencyOrder, SetBagFont, FOOTER_H = I.BP, I.CurrencyOrder, I.SetBagFont, I.FOOTER_H

-------------------------------------------------------------------------------
--  Gold tracking + Footer
-------------------------------------------------------------------------------
local GoldLedger = EllesmereUI.GetGoldLedger()

local function FormatNumberWithCommas(num)
    local str = tostring(math.floor(num))
    local result = ""
    local count = 0
    for i = #str, 1, -1 do
        if count > 0 and count % 3 == 0 then result = "," .. result end
        result = str:sub(i, i) .. result
        count = count + 1
    end
    return result
end

local WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B = 1, 0.8, 0.5

local function UpdateBagMoneyDisplay()
    if not EUI_Bags.Money then return end
    MoneyFrame_UpdateMoney(EUI_Bags.Money)
    local goldBtn = _G["EUI_BagMoneyFrameGoldButton"]
    if goldBtn then
        local txt = goldBtn:GetFontString()
        if txt then
            txt:SetText(FormatNumberWithCommas(math.floor((GoldLedger.Money() or 0) / 10000)))
        end
    end
end

local function ResetAllGoldData()
    GoldLedger.Reset()
    GoldLedger.RecordCharacter()
    GoldLedger.RecordWarband()
end

-- Ledger callback: repaint the money readouts after every recorded change.
local function OnGoldChanged()
    UpdateBagMoneyDisplay()
    local bank = _G.EUI_BankFrame
    if bank and bank.UpdateFooterGold and bank:IsVisible() then bank:UpdateFooterGold() end
end

-------------------------------------------------------------------------------
--  Gold tooltip (custom multi-column, matches vault tooltip pattern)
-------------------------------------------------------------------------------
local _goldTT
local _goldTTRows = {}
local GOLD_COL_GAP = 20
local GOLD_ROW_H = 14
local GOLD_PAD = 8
-- Show Coins (the profile's bagGoldCoins): the summary's coin columns, gold alone, gold and
-- silver, or gold, silver and copper. A row's texts are [0] its name and [1..3] its coins;
-- the silver and copper texts are made the first time their column shows.
local COIN_COLS = { gold = 1, silver = 2, copper = 3 }
local COIN_GAP = 6
local COIN_ICON = {
    "|TInterface\\MoneyFrame\\UI-GoldIcon:14|t",
    "|TInterface\\MoneyFrame\\UI-SilverIcon:14|t",
    "|TInterface\\MoneyFrame\\UI-CopperIcon:14|t",
}
-- The widest text of each coin column of the summary being laid out
local _coinW = { 0, 0, 0 }

local function GetGoldTooltip()
    if _goldTT then return _goldTT end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()

    local fadeInAG = f:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25); fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function() f:SetAlpha(1) end)
    f._fadeInAG = fadeInAG; f._fadeIn = fadeIn

    local fadeOutAG = f:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25); fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function() f:SetAlpha(0); f:Hide() end)
    f._fadeOutAG = fadeOutAG; f._fadeOut = fadeOut

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", f, "TOP", 0, -GOLD_PAD)
    title:SetText(EllesmereUI.L("Gold Summary"))
    f._title = title

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hint:SetTextColor(1, 0.4, 0.4, 1)
    hint:SetText(EllesmereUI.L("Ctrl + Right-Click: Reset all data"))
    f._hint = hint

    _goldTT = f
    return f
end

-- Rows 1..count with their name text and their first `cols` coin texts, in the Bags font.
local function EnsureGoldRows(count, cols)
    local fontPath = (EllesmereUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (EllesmereUI.GetFontOutlineFlag("bags")) or ""
    local tt = GetGoldTooltip()
    tt._title:SetFont(fontPath, 11, fontFlags)
    tt._hint:SetFont(fontPath, 10, fontFlags)
    for i = 1, count do
        local row = _goldTTRows[i]
        if not row then
            row = {}
            _goldTTRows[i] = row
        end
        for col = 0, cols do
            local fs = row[col]
            if fs then
                fs:SetFont(fontPath, 11, fontFlags)
            else
                fs = tt:CreateFontString(nil, "OVERLAY")
                fs:SetFont(fontPath, 11, fontFlags)
                fs:SetJustifyH(col == 0 and "LEFT" or "RIGHT")
                row[col] = fs
            end
        end
    end
end

local function StripRealm(name)
    if not name then return "Unknown" end
    if Ambiguate then return Ambiguate(name, "short") or name end
    return name
end

-- One row of the summary: its name, and its money in the shown coin columns in one colour.
-- Returns the name's width; each coin column's widest text collects in _coinW.
local function FillGoldRow(row, name, money, cols, r, g, b)
    local nameFS = row[0]
    nameFS:SetText(name)
    nameFS:Show()
    for col = 1, cols do
        local fs = row[col]
        local amount
        if col == 1 then
            amount = FormatNumberWithCommas(money / 10000)
        elseif col == 2 then
            amount = math.floor(money % 10000 / 100)
        else
            amount = math.floor(money % 100)
        end
        fs:SetText(amount .. COIN_ICON[col])
        fs:SetTextColor(r, g, b, 1)
        fs:Show()
        local w = fs:GetStringWidth() or 0
        if w > _coinW[col] then _coinW[col] = w end
    end
    for col = cols + 1, 3 do
        if row[col] then row[col]:Hide() end
    end
    return nameFS:GetStringWidth() or 0
end

local function ShowGoldTooltip(anchor)
    if not GoldLedger.IsTracking() then return end

    local ledger = GoldLedger.Data()
    local totalGold = 0
    local charList = {}
    for charID, data in pairs(GoldLedger.Chars()) do
        charList[#charList + 1] = { id = charID, data = data }
        totalGold = totalGold + data.money
    end
    table.sort(charList, function(a, b) return (a.data.name or a.id) < (b.data.name or b.id) end)

    local warbandGold = ledger.warband and ledger.warband.money
    -- An empty warband bank gets no row, as on the Data Bars Gold block.
    if warbandGold and warbandGold <= 0 then warbandGold = nil end
    if warbandGold then
        totalGold = totalGold + warbandGold
    end
    if #charList == 0 and not warbandGold then return end

    local rowCount = #charList + 1
    if warbandGold then rowCount = rowCount + 1 end
    local cols = COIN_COLS[BP().bagGoldCoins] or 1
    EnsureGoldRows(rowCount, cols)
    local tt = GetGoldTooltip()

    local nameW = 0
    _coinW[1], _coinW[2], _coinW[3] = 0, 0, 0
    for r, entry in ipairs(charList) do
        local cc = RAID_CLASS_COLORS[entry.data.class] or { r = 1, g = 1, b = 1 }
        local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
        local w = FillGoldRow(_goldTTRows[r], "|cff" .. hex .. StripRealm(entry.data.name or entry.id) .. "|r",
            entry.data.money, cols, 1, 1, 1)
        if w > nameW then nameW = w end
    end

    local totalRow = #charList + 1
    if warbandGold then
        local w = FillGoldRow(_goldTTRows[totalRow], "|cffffcc80" .. EllesmereUI.L("Warbank") .. "|r",
            warbandGold, cols, WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B)
        if w > nameW then nameW = w end
        totalRow = totalRow + 1
    end

    local totalNameW = FillGoldRow(_goldTTRows[totalRow], "|cffffcc80" .. EllesmereUI.L("Total") .. "|r",
        totalGold, cols, 1, 1, 0.5)
    if totalNameW > nameW then nameW = totalNameW end

    for i = totalRow + 1, #_goldTTRows do
        local row = _goldTTRows[i]
        for col = 0, 3 do
            if row[col] then row[col]:Hide() end
        end
    end

    -- The coin columns end at the summary's right edge, each as wide as its widest text.
    local moneyW = (cols - 1) * COIN_GAP
    for col = 1, cols do moneyW = moneyW + _coinW[col] end

    local titleTop = GOLD_PAD + (tt._title:GetStringHeight() or 14) + 6
    local totalW = GOLD_PAD + nameW + GOLD_COL_GAP + moneyW + GOLD_PAD

    for r = 1, rowCount do
        local y = -(titleTop + (r - 1) * GOLD_ROW_H)
        -- Add gap before total row
        if r == totalRow then y = y - 4 end
        local row = _goldTTRows[r]
        row[0]:ClearAllPoints()
        row[0]:SetPoint("TOPLEFT", tt, "TOPLEFT", GOLD_PAD, y)
        local right = -GOLD_PAD
        for col = cols, 1, -1 do
            row[col]:ClearAllPoints()
            row[col]:SetPoint("TOPRIGHT", tt, "TOPRIGHT", right, y)
            right = right - _coinW[col] - COIN_GAP
        end
    end

    local lastRowY = titleTop + (rowCount - 1) * GOLD_ROW_H + 4 + GOLD_ROW_H + 6
    tt._hint:ClearAllPoints()
    tt._hint:SetPoint("TOPLEFT", tt, "TOPLEFT", GOLD_PAD, -lastRowY)
    local hintW = (tt._hint:GetStringWidth() or 0) + GOLD_PAD * 2
    if hintW > totalW then totalW = hintW end
    local totalH = lastRowY + (tt._hint:GetStringHeight() or 10) + GOLD_PAD

    tt:SetSize(totalW, totalH)
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)

    tt._fadeOutAG:Stop()
    tt._fadeInAG:Stop()
    tt:SetAlpha(0)
    tt:Show()
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeInAG:Play()
end

local function HideGoldTooltip()
    if not _goldTT or not _goldTT:IsShown() then return end
    _goldTT._fadeInAG:Stop()
    _goldTT._fadeOutAG:Stop()
    _goldTT._fadeOut:SetFromAlpha(_goldTT:GetAlpha())
    _goldTT._fadeOut:SetToAlpha(0)
    _goldTT._fadeOutAG:Play()
end

local function PositionBagMoney(inset)
    local footer, money = EUI_Bags.Footer, EUI_Bags.Money
    if not money then return end
    money:ClearAllPoints()
    if footer._coinBox then
        money:SetPoint("RIGHT", footer._coinBox, "RIGHT", -inset, 0)
    else
        money:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -inset, 7)
    end
end

local function CreateFooter()
    if EUI_Bags.Footer then return end
    local footer = CreateFrame("Frame", nil, EUI_Bags)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    footer.bg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
    footer.bg:SetAllPoints()
    footer.bg:SetColorTexture(0, 0, 0, 0.35)

    -- Currency displays are created dynamically from Blizzard's tracked currencies
    if not EUI_Bags._currencyPool then
        EUI_Bags._currencyPool = { displays = {}, hitboxes = {} }
    end

    local money = CreateFrame("Frame", "EUI_BagMoneyFrame", footer, "SmallMoneyFrameTemplate")
    MoneyFrame_SetType(money, "PLAYER")

    for _, suffix in ipairs({"GoldButton", "SilverButton", "CopperButton"}) do
        local btn = _G["EUI_BagMoneyFrame" .. suffix]
        if btn then
            local txt = btn:GetFontString()
            if txt then SetBagFont(txt, 11) end
        end
    end

    -- Disable mouse on all SmallMoneyFrameTemplate children so our hitbox catches events
    for _, child in pairs({ money:GetChildren() }) do
        child:EnableMouse(false)
    end
    local moneyHitbox = CreateFrame("Frame", nil, footer)
    moneyHitbox:SetPoint("BOTTOMRIGHT", money, "BOTTOMRIGHT", 5, -5)
    moneyHitbox:SetPoint("TOPLEFT", money, "TOPLEFT", -5, 5)
    moneyHitbox:SetFrameLevel(money:GetFrameLevel() + 10)
    moneyHitbox:EnableMouse(true)

    moneyHitbox:SetScript("OnEnter", function(self) ShowGoldTooltip(self) end)
    moneyHitbox:SetScript("OnLeave", function() HideGoldTooltip() end)
    moneyHitbox:SetScript("OnMouseDown", function(self, button)
        if not GoldLedger.IsTracking() then return end
        if button == "RightButton" and IsControlKeyDown() then
            ResetAllGoldData(); HideGoldTooltip(); return
        end
    end)

    -- Top-edge separator (1px physical pixel)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local ftrSep = footer:CreateTexture(nil, "ARTWORK")
    ftrSep:SetHeight(px)
    ftrSep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    ftrSep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    ftrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    if ns.BagsForever() then
        ns.SkinForeverBagFooter(footer, footer.bg, ftrSep)
        money:SetHeight(16)
    end

    EUI_Bags.Footer, EUI_Bags.Money = footer, money
    PositionBagMoney(0)
end

local function UpdateCurrencyDisplays(footerWidth)
    local pool = EUI_Bags._currencyPool
    if not pool or not EUI_Bags.Footer then return FOOTER_H end
    local footer = EUI_Bags.Footer

    for _, d in ipairs(pool.displays) do d:Hide() end
    for _, h in ipairs(pool.hitboxes) do h:Hide() end

    -- Build tracked list from internal order table (decoupled from Blizzard)
    local tracked = {}
    local orderDB = CurrencyOrder()
    if orderDB and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for cID, order in pairs(orderDB) do
            if type(order) == "number" then
                tracked[#tracked + 1] = { currencyTypesID = cID, order = order }
            end
        end
        table.sort(tracked, function(a, b) return a.order < b.order end)
    end

    for i = #pool.displays + 1, #tracked do
        local display = footer:CreateFontString(nil, "OVERLAY")
        SetBagFont(display, 11)
        display:SetTextColor(1, 1, 1)
        pool.displays[i] = display

        local hb = CreateFrame("Frame", nil, footer)
        hb:SetFrameLevel(footer:GetFrameLevel() + 5)
        hb:EnableMouse(true)
        hb:SetScript("OnEnter", function(self)
            if self._currencyID and GameTooltip.SetCurrencyByID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetCurrencyByID(self._currencyID)
            end
        end)
        hb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        pool.hitboxes[i] = hb
    end

    local padding = 5
    local rowHeight = 14
    local rowGap = 8
    local bottomPad = 7
    local topPad = 7
    local coinBox = footer._coinBox
    local leftOffset = coinBox and 5 or 10
    local rightMargin = 180
    footerWidth = footerWidth or footer:GetWidth() or EUI_Bags:GetWidth() or 0
    if footerWidth <= 0 then footerWidth = EUI_Bags:GetWidth() or 400 end
    local availableWidth = math.max(40, footerWidth - leftOffset - rightMargin)
    local currentRow = 0
    local currentX = leftOffset
    local currencyLayout = {}

    for i, info in ipairs(tracked) do
        local display = pool.displays[i]
        local fullInfo = C_CurrencyInfo.GetCurrencyInfo(info.currencyTypesID)
        local icon = fullInfo and fullInfo.iconFileID or info.iconFileID
        local quantity = fullInfo and fullInfo.quantity or 0
        local discovered = fullInfo and fullInfo.discovered
        local name = fullInfo and fullInfo.name or ""
        if icon and (discovered ~= false) then
            display:SetText("|T" .. tostring(icon) .. ":17:17:0:0:64:64:5:59:5:59|t " .. quantity)
            local itemWidth = display:GetStringWidth() + padding
            if currentX + itemWidth > leftOffset + availableWidth and currentX > leftOffset then
                currentRow = currentRow + 1
                currentX = leftOffset
            end
            currencyLayout[#currencyLayout + 1] = {
                idx = i, row = currentRow, x = currentX, currencyID = info.currencyTypesID,
            }
            currentX = currentX + itemWidth
        end
    end

    local numRows = math.max(1, currentRow + 1)
    local footerHeight = math.max(
        FOOTER_H,
        bottomPad + topPad + numRows * rowHeight + math.max(0, numRows - 1) * rowGap
    )

    for _, layout in ipairs(currencyLayout) do
        local display = pool.displays[layout.idx]
        display:ClearAllPoints()
        local rowFromBottom = numRows - 1 - layout.row
        local yPos = rowFromBottom * (rowHeight + rowGap)
        if coinBox then
            display:SetPoint("LEFT", coinBox, "LEFT", layout.x, yPos)
        else
            display:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", layout.x, bottomPad + yPos)
        end
        display:Show()

        local hb = pool.hitboxes[layout.idx]
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", display, "TOPLEFT", 0, 2)
        hb:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 0, -2)
        hb._currencyID = layout.currencyID
        hb:Show()
    end

    footer:SetHeight(footerHeight)
    EUI_Bags._footerH = footerHeight
    return footerHeight
end

-- Re-lay-out the currency footer and grow/shrink the bag frame by the height delta (grow-only running max under Auto-Size and on WoW Forever); reads the previous height BEFORE UpdateCurrencyDisplays stamps the new one.
local function SyncBagFrameToFooter()
    local prev = EUI_Bags._footerH or FOOTER_H
    local footerH = UpdateCurrencyDisplays() or FOOTER_H
    if footerH == prev then return end
    if not EUI_Bags:IsVisible() then return end
    local delta = footerH - prev
    if EUI_Bags.AutoSizeOn() or (EUI.IS_FOREVER and not BP().bagHeight) then
        EUI_Bags._asMaxH = math.max(EUI_Bags._asMaxH or EUI_Bags:GetHeight() or 0, EUI_Bags:GetHeight() + delta)
        EUI_Bags:SetHeight(EUI_Bags._asMaxH)
    elseif BP().bagHeight then
        -- Grip-set height is the whole window; the content area absorbs it
        return
    else
        EUI_Bags:SetHeight(EUI_Bags:GetHeight() + delta)
    end
end

-------------------------------------------------------------------------------
--  Reagent Bag UI
-------------------------------------------------------------------------------
local function CreateReagentBagUI()
    if EUI_BagsReagent.Header then return end
    local header = CreateFrame("Frame", nil, EUI_BagsReagent)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(35)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0, 0, 0, 0.5)
    header.title = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.title, 13)
    header.title:SetPoint("LEFT", 15, 0)
    header.title:SetText(EllesmereUI.L("REAGENTS"))
    header.title:SetTextColor(1, 1, 1)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -5, 0)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
    close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() EUI_BagsReagent:Hide() end)
    if ns.BagsForever() then
        ns.LayoutForeverBagHeader(header, 35)
        header.bg:Hide()
        ns.AddForeverBagPortrait(header, EUI.ClientIcon(3622222))
        ns.SkinForeverBagTitle(header.title)
        ns.PositionForeverBagClose(close)
    end
    -- Controller cursor: Cancel finds the close button.
    if EUI.PadCP() then EUI_BagsReagent.CloseButton = close end
    EUI_BagsReagent.Header = header
    local footer = CreateFrame("Frame", nil, EUI_BagsReagent)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    EUI_BagsReagent.Footer = footer
end

I.CreateFooter, I.CreateReagentBagUI = CreateFooter, CreateReagentBagUI
I.GoldLedger, I.OnGoldChanged = GoldLedger, OnGoldChanged
I.SyncBagFrameToFooter, I.UpdateBagMoneyDisplay = SyncBagFrameToFooter, UpdateBagMoneyDisplay
I.UpdateCurrencyDisplays = UpdateCurrencyDisplays
I.PositionBagMoney = PositionBagMoney
I.broken = false
