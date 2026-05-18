-------------------------------------------------------------------------------
--  EllesmereUIBags_Bank.lua
--  Bank UI module - opens when interacting with a banker NPC
--  Visually matches the Bags module with sidebar, search, and sorting
-------------------------------------------------------------------------------
local EUI = EllesmereUI

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local SLOT_SIZE, SPACING = 34, 4
local HEADER_H    = 35
local FOOTER_H    = 32
local SIDEBAR_W   = 160
local SIDEBAR_W_COLLAPSED = 32
local SIDEBAR_BTN_H   = 26
local SIDEBAR_ICON_SIZE = 18
local SIDEBAR_PAD = 2
local COLUMNS     = 14
local FIXED_H     = 500
local SCROLLBAR_W = 4
local SCROLLBAR_HIT_W = 16
local SCROLL_STEP = 40
local THUMB_MIN_H = 20

-- Runtime state
local _selectedView = 0   -- 0 = All Bank Tabs, -1 = OneBank, -2 = All Warbank, -3 = OneWarbank, >0 = tab index
local _allTabs = {}        -- populated on bank open: { bagID, name, isWarband, numSlots, icon }
local _warbandOnly = false -- true when opened via portable warbank (AccountBanker interaction)

local function GetBankSidebarWidth()
    local collapsed = EllesmereUIDB and EllesmereUIDB.bankSidebarCollapsed
    return collapsed and SIDEBAR_W_COLLAPSED or SIDEBAR_W
end

local BANK_FONT = (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
local function SetBankFont(fs, size) fs:SetFont(BANK_FONT, size, "") end
local GetUpgradeTrack = EUI.GetUpgradeTrack
local ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon
local ITEM_CLASS_ARMOR  = Enum.ItemClass.Armor
local function IsGearItem(itemLink)
    if not itemLink then return false end
    local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
    return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
end
local function GetAccentRGB()
    if EUI.GetAccentColor then return EUI.GetAccentColor() end
    return 0.05, 0.82, 0.62
end

-------------------------------------------------------------------------------
--  Helpers (duplicated from bags for self-contained file)
-------------------------------------------------------------------------------
local function CreateInsetBorder(btn)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local t = btn:CreateTexture(nil, "OVERLAY", nil, 2); t:SetTexture(WHITE)
    t:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0); t:SetHeight(px)
    local b = btn:CreateTexture(nil, "OVERLAY", nil, 2); b:SetTexture(WHITE)
    b:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0); b:SetHeight(px)
    local l = btn:CreateTexture(nil, "OVERLAY", nil, 2); l:SetTexture(WHITE)
    l:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); l:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0); l:SetWidth(px)
    local r = btn:CreateTexture(nil, "OVERLAY", nil, 2); r:SetTexture(WHITE)
    r:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0); r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0); r:SetWidth(px)
    btn._brdT, btn._brdB, btn._brdL, btn._brdR = t, b, l, r
end

local function SetInsetBorderColor(btn, cr, cg, cb, ca)
    if btn._brdT then
        btn._brdT:SetColorTexture(cr, cg, cb, ca)
        btn._brdB:SetColorTexture(cr, cg, cb, ca)
        btn._brdL:SetColorTexture(cr, cg, cb, ca)
        btn._brdR:SetColorTexture(cr, cg, cb, ca)
    end
end

-------------------------------------------------------------------------------
--  Bank Tab Discovery (Midnight 12.0+ uses CharacterBankTab / AccountBankTab enums)
-------------------------------------------------------------------------------
-- Fallback icons for tabs without a user-assigned icon
local FALLBACK_ICONS = {
    5524917, 133668, 4641307, 133659, 133656, 348524, 348520,
    133660, 4549238, 5931149, 4549226, 1379173, 348523, 2023244,
}
local _usedFallbackIdx = 0
local _tabIconCache = {}  -- bagID -> icon (persists for session)

local function GetFallbackIcon(bagID)
    if _tabIconCache[bagID] then return _tabIconCache[bagID] end
    _usedFallbackIdx = _usedFallbackIdx + 1
    local icon = FALLBACK_ICONS[((_usedFallbackIdx - 1) % #FALLBACK_ICONS) + 1]
    _tabIconCache[bagID] = icon
    return icon
end

local CHARACTER_BANK_BAGS = {}
local WARBAND_BANK_BAGS = {}
if Enum and Enum.BagIndex then
    -- Midnight character bank: CharacterBankTab_1 through CharacterBankTab_6
    for i = 1, 6 do
        local key = "CharacterBankTab_" .. i
        if Enum.BagIndex[key] then
            CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = Enum.BagIndex[key]
        end
    end
    -- Warband bank: AccountBankTab_1 through AccountBankTab_5
    for i = 1, 5 do
        local key = "AccountBankTab_" .. i
        if Enum.BagIndex[key] then
            WARBAND_BANK_BAGS[#WARBAND_BANK_BAGS + 1] = Enum.BagIndex[key]
        end
    end
end

local function GetCharacterBankTabs()
    local tabs = {}
    -- Use C_Bank.FetchPurchasedBankTabData for tab metadata (name, icon)
    local tabData
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        tabData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
    end
    if tabData then
        for i, td in ipairs(tabData) do
            local bagID = CHARACTER_BANK_BAGS[i]
            if bagID then
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                if numSlots > 0 then
                    local icon = td.icon
                    if not icon or icon == 134400 then icon = GetFallbackIcon(bagID) end
                    tabs[#tabs + 1] = { bagID = bagID, numSlots = numSlots, name = td.name or ("Bank Tab " .. i), icon = icon }
                end
            end
        end
    else
        for i, bagID in ipairs(CHARACTER_BANK_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots > 0 then
                tabs[#tabs + 1] = { bagID = bagID, numSlots = numSlots, name = "Bank Tab " .. #tabs + 1, icon = GetFallbackIcon(bagID) }
            end
        end
    end
    return tabs
end

local function GetWarbandBankTabs()
    local tabs = {}
    -- Check if warband bank is locked
    if C_Bank and C_Bank.FetchBankLockedReason and Enum.BankType then
        if C_Bank.FetchBankLockedReason(Enum.BankType.Account) ~= nil then
            return tabs
        end
    end
    local tabData
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        tabData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
    end
    if tabData then
        for i, td in ipairs(tabData) do
            local bagID = WARBAND_BANK_BAGS[i]
            if bagID then
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                if numSlots > 0 then
                    local name = td.name or ("Tab " .. i)
                    local icon = td.icon
                    if not icon or icon == 134400 then icon = GetFallbackIcon(bagID) end
                    tabs[#tabs + 1] = { bagID = bagID, numSlots = numSlots, name = "Warbank " .. name, icon = icon }
                end
            end
        end
    else
        for i, bagID in ipairs(WARBAND_BANK_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots > 0 then
                tabs[#tabs + 1] = { bagID = bagID, numSlots = numSlots, name = "Warbank Tab " .. #tabs + 1, icon = GetFallbackIcon(bagID) }
            end
        end
    end
    return tabs
end

-------------------------------------------------------------------------------
--  Main Frame
-------------------------------------------------------------------------------
local EUI_Bank = CreateFrame("Frame", "EUI_BankFrame", UIParent)
EUI_Bank:SetFrameStrata("HIGH")
EUI_Bank:SetFrameLevel(50)
EUI_Bank:EnableMouse(true)
EUI_Bank:SetMovable(true)
EUI_Bank:SetClampedToScreen(true)
EUI_Bank:Hide()

-- Background: atlas matching bags module (full alpha, covers entire window)
local bgAtlas = EUI_Bank:CreateTexture(nil, "BACKGROUND")
bgAtlas:SetAllPoints()
bgAtlas:SetAtlas("housing-basic-panel--stone-background")
local bgOverlay = EUI_Bank:CreateTexture(nil, "BACKGROUND", nil, 1)
bgOverlay:SetAllPoints()
bgOverlay:SetColorTexture(0, 0, 0, 0.25)
if EUI.MakeBorder then EUI.MakeBorder(EUI_Bank, 1, 1, 1, 0.15, EUI.PP) end

-------------------------------------------------------------------------------
--  Header
-------------------------------------------------------------------------------
local header = CreateFrame("Frame", nil, EUI_Bank)
header:SetPoint("TOPLEFT", EUI_Bank, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", EUI_Bank, "TOPRIGHT", 0, 0)
header:SetHeight(HEADER_H)
local hdrBg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
hdrBg:SetAllPoints(); hdrBg:SetColorTexture(0, 0, 0, 0.5)

local title = header:CreateFontString(nil, "OVERLAY")
SetBankFont(title, 13)
title:SetPoint("LEFT", header, "LEFT", 8, 0)
title:SetTextColor(1, 1, 1)
title:SetText("Bank")

local itemCount = header:CreateFontString(nil, "OVERLAY")
SetBankFont(itemCount, 11)
itemCount:SetPoint("LEFT", title, "RIGHT", 8, 0)
itemCount:SetTextColor(0.6, 0.6, 0.6)
EUI_Bank._headerItemCount = itemCount

-- Search box
local bankSearch = CreateFrame("EditBox", "EUI_BankSearchBox", header)
bankSearch:SetSize(160, 22)
bankSearch:SetPoint("RIGHT", header, "RIGHT", -35, 0)
bankSearch:SetFont(BANK_FONT, 12, "")
bankSearch:SetAutoFocus(false)
bankSearch:SetTextInsets(5, 26, 0, 0)
local searchBg = bankSearch:CreateTexture(nil, "BACKGROUND")
searchBg:SetAllPoints()
searchBg:SetColorTexture(0.02, 0.02, 0.02, 1)
if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(bankSearch, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7) end

local searchPlaceholder = bankSearch:CreateFontString(nil, "OVERLAY")
SetBankFont(searchPlaceholder, 11)
searchPlaceholder:SetPoint("LEFT", bankSearch, "LEFT", 5, 0)
searchPlaceholder:SetText("Search...")
searchPlaceholder:SetTextColor(0.4, 0.4, 0.4)
EUI_Bank._searchBox = bankSearch

-- Search clear button
local searchClear = CreateFrame("Button", nil, bankSearch)
searchClear:SetSize(22, 22)
searchClear:SetPoint("RIGHT", bankSearch, "RIGHT", 0, 0)
searchClear.tex = searchClear:CreateFontString(nil, "OVERLAY")
SetBankFont(searchClear.tex, 14)
searchClear.tex:SetText("x")
searchClear.tex:SetPoint("CENTER", 0, 1)
searchClear.tex:SetTextColor(0.8, 0.8, 0.8)
searchClear:Hide()
searchClear:SetScript("OnClick", function()
    bankSearch:SetText("")
    bankSearch:ClearFocus()
end)

bankSearch:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
bankSearch:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)
bankSearch:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    searchPlaceholder:SetShown(text == "")
    searchClear:SetShown(text ~= "")
    if EUI_Bank:IsVisible() then EUI_Bank:RefreshBank() end
end)

-- Sort button
local sortBtn = CreateFrame("Button", nil, header)
sortBtn:SetSize(24, 24)
sortBtn:SetPoint("RIGHT", bankSearch, "LEFT", -13, 0)
sortBtn.icon = sortBtn:CreateTexture(nil, "OVERLAY")
sortBtn.icon:SetAllPoints()
sortBtn.icon:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\clean-up.png")
sortBtn.icon:SetAlpha(0.9)

local bankSortLocked = false
local function LockBankSort()
    bankSortLocked = true
    sortBtn:EnableMouse(false)
    sortBtn.icon:SetAlpha(0.2)
end
local function UnlockBankSort()
    if not bankSortLocked then return end
    bankSortLocked = false
    sortBtn:EnableMouse(true)
    sortBtn.icon:SetAlpha(0.9)
end

sortBtn:SetScript("OnEnter", function(self)
    self.icon:SetAlpha(1)
    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Sort Items") end
end)
sortBtn:SetScript("OnLeave", function(self)
    self.icon:SetAlpha(0.9)
    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
end)
sortBtn:SetScript("OnClick", function()
    if bankSortLocked then return end
    LockBankSort()
    local isWarband = (_selectedView == -2 or _selectedView == -3)
    if not isWarband and _selectedView > 0 and _allTabs[_selectedView] then
        isWarband = _allTabs[_selectedView].isWarband
    end
    if isWarband then
        C_Container.SortBank(Enum.BankType.Account)
    else
        C_Container.SortBank(Enum.BankType.Character)
    end
    C_Timer.After(3, UnlockBankSort)
end)

-- Close button (created after search/sort so it renders on top)
local close = CreateFrame("Button", nil, header)
close:SetSize(12, 12)
close:SetPoint("RIGHT", header, "RIGHT", -9, 0)
close.icon = close:CreateTexture(nil, "OVERLAY")
close.icon:SetAllPoints()
close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
close.icon:SetAlpha(0.7)
close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
close:SetScript("OnClick", function()
    EUI_Bank:Hide()
end)

-- Header bottom-edge separator (1px physical pixel)
do
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local hdrSep = header:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(px)
    hdrSep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    hdrSep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    hdrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
end

-------------------------------------------------------------------------------
--  Footer: Player Gold (left) + Warband Gold (right)
-------------------------------------------------------------------------------
do
    local footer = CreateFrame("Frame", nil, EUI_Bank)
    footer:SetPoint("BOTTOMLEFT", EUI_Bank, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", EUI_Bank, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    local ftrBg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
    ftrBg:SetAllPoints(); ftrBg:SetColorTexture(0, 0, 0, 0.35)

    -- Top-edge separator
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local ftrSep = footer:CreateTexture(nil, "ARTWORK")
    ftrSep:SetHeight(px)
    ftrSep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    ftrSep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    ftrSep:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- Shared formatting
    local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t"
    local function FormatGold(copper)
        if not copper or copper == 0 then return "0" .. GOLD_ICON end
        local gold = math.floor(copper / 10000)
        return BreakUpLargeNumbers(gold) .. GOLD_ICON
    end

    -- Layout: | [10px] [player gold] ... [withdraw] [deposit] [10px] [warband gold] [10px] |
    local playerGold = footer:CreateFontString(nil, "OVERLAY")
    SetBankFont(playerGold, 11)
    playerGold:SetPoint("LEFT", footer, "LEFT", 10, 0)
    playerGold:SetTextColor(1, 1, 1)

    local playerHitbox = CreateFrame("Frame", nil, footer)
    playerHitbox:SetPoint("TOPLEFT", playerGold, "TOPLEFT", -4, 4)
    playerHitbox:SetPoint("BOTTOMRIGHT", playerGold, "BOTTOMRIGHT", 4, -4)
    playerHitbox:SetFrameLevel(footer:GetFrameLevel() + 5)
    playerHitbox:EnableMouse(true)
    playerHitbox:SetScript("OnEnter", function(self)
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, "Player Gold")
        end
    end)
    playerHitbox:SetScript("OnLeave", function()
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    local warbandGold = footer:CreateFontString(nil, "OVERLAY")
    SetBankFont(warbandGold, 11)
    warbandGold:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
    warbandGold:SetTextColor(1, 1, 1)

    local warbandHitbox = CreateFrame("Frame", nil, footer)
    warbandHitbox:SetPoint("TOPLEFT", warbandGold, "TOPLEFT", -4, 4)
    warbandHitbox:SetPoint("BOTTOMRIGHT", warbandGold, "BOTTOMRIGHT", 4, -4)
    warbandHitbox:SetFrameLevel(footer:GetFrameLevel() + 5)
    warbandHitbox:EnableMouse(true)
    warbandHitbox:SetScript("OnEnter", function(self)
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, "Warband Gold")
        end
    end)
    warbandHitbox:SetScript("OnLeave", function()
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    -- Withdraw / Deposit styled buttons (next to warband gold)
    local PP = EUI and EUI.PP
    local ar, ag, ab = GetAccentRGB()

    local GOLD_R, GOLD_G, GOLD_B = 0.855, 0.722, 0.259  -- #dab842

    local function MakeStyledFooterBtn(label, tooltipText)
        local btn = CreateFrame("Button", nil, footer)
        btn:SetSize(70, 18)
        btn:EnableMouse(true)
        btn:SetFrameLevel(footer:GetFrameLevel() + 2)

        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, GOLD_R, GOLD_G, GOLD_B, 0.8, 1, "OVERLAY", 7)
        end

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        SetBankFont(lbl, 9)
        lbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
        lbl:SetText(label)
        lbl:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.8)
        btn._label = lbl

        btn:SetScript("OnEnter", function(self)
            self._label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
            if PP and PP.SetBorderColor then PP.SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, 1) end
            if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, tooltipText) end
        end)
        btn:SetScript("OnLeave", function(self)
            self._label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.8)
            if PP and PP.SetBorderColor then PP.SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, 0.8) end
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        end)
        return btn
    end

    local depositMoneyBtn = MakeStyledFooterBtn("Deposit", "Deposit to Warbank")
    depositMoneyBtn:SetPoint("RIGHT", warbandGold, "LEFT", -14, 0)
    local withdrawMoneyBtn = MakeStyledFooterBtn("Withdraw", "Withdraw from Warbank")
    withdrawMoneyBtn:SetPoint("RIGHT", depositMoneyBtn, "LEFT", -8, 0)

    local function ShowMoneyPopup(title, onAccept)
        if not EUI.ShowInputPopup then return end
        EUI:ShowInputPopup({
            title = title,
            message = "Enter amount in gold:",
            placeholder = "1137",
            confirmText = ACCEPT,
            cancelText = CANCEL,
            onConfirm = function(text)
                local gold = tonumber(text)
                if gold and gold > 0 then
                    onAccept(gold * 10000)
                end
            end,
        })
    end

    withdrawMoneyBtn:SetScript("OnClick", function()
        if not C_Bank or not C_Bank.CanWithdrawMoney then return end
        if not C_Bank.CanWithdrawMoney(Enum.BankType.Account) then return end
        ShowMoneyPopup("Withdraw from Warbank", function(copper)
            C_Bank.WithdrawMoney(Enum.BankType.Account, copper)
            if EUI_Bags and EUI_Bags.CaptureWarbandGold then EUI_Bags.CaptureWarbandGold() end
        end)
    end)
    depositMoneyBtn:SetScript("OnClick", function()
        if not C_Bank or not C_Bank.CanDepositMoney then return end
        if not C_Bank.CanDepositMoney(Enum.BankType.Account) then return end
        ShowMoneyPopup("Deposit to Warbank", function(copper)
            C_Bank.DepositMoney(Enum.BankType.Account, copper)
            if EUI_Bags and EUI_Bags.CaptureWarbandGold then EUI_Bags.CaptureWarbandGold() end
        end)
    end)

    -- Deposit Warbound Items / Deposit Reagents button (center)
    local depositItemsBtn = CreateFrame("Button", nil, footer)
    depositItemsBtn:SetHeight(18)
    depositItemsBtn:SetPoint("CENTER", footer, "CENTER", 0, 0)
    depositItemsBtn:EnableMouse(true)

    local depositItemsLabel = depositItemsBtn:CreateFontString(nil, "OVERLAY")
    SetBankFont(depositItemsLabel, 10)
    depositItemsLabel:SetPoint("CENTER", depositItemsBtn, "CENTER", 0, 0)
    depositItemsLabel:SetTextColor(ar, ag, ab, 1)
    depositItemsBtn._label = depositItemsLabel

    depositItemsBtn:SetScript("OnEnter", function(self)
        self._label:SetTextColor(1, 1, 1, 1)
    end)
    depositItemsBtn:SetScript("OnLeave", function(self)
        local r, g, b = GetAccentRGB()
        self._label:SetTextColor(r, g, b, 1)
    end)
    depositItemsBtn:SetScript("OnClick", function(self)
        if not C_Bank or not C_Bank.AutoDepositItemsIntoBank then return end
        local bankType = self._bankType
        if bankType then
            C_Bank.AutoDepositItemsIntoBank(bankType)
        end
    end)

    function EUI_Bank:UpdateFooterGold()
        local pMoney = GetMoney and GetMoney() or 0
        playerGold:SetText(FormatGold(pMoney))
        local wMoney = C_Bank and C_Bank.FetchDepositedMoney and C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
        warbandGold:SetText(FormatGold(wMoney))
    end

    function EUI_Bank:UpdateDepositButton(isWarband)
        if isWarband then
            depositItemsLabel:SetText("Deposit Warbound Items")
            depositItemsBtn._bankType = Enum.BankType.Account
        else
            depositItemsLabel:SetText("Deposit Reagents")
            depositItemsBtn._bankType = Enum.BankType.Character
        end
        local r, g, b = GetAccentRGB()
        depositItemsLabel:SetTextColor(r, g, b, 1)
        depositItemsBtn:SetWidth(depositItemsLabel:GetStringWidth() + 16)
        depositItemsBtn:Show()
        withdrawMoneyBtn:Show()
        depositMoneyBtn:Show()
    end
end

-------------------------------------------------------------------------------
--  Shift+Drag to Move
-------------------------------------------------------------------------------
EUI_Bank:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        self:StartMoving()
        self._moving = true
    end
end)
EUI_Bank:SetScript("OnMouseUp", function(self, button)
    if self._moving then
        self:StopMovingOrSizing()
        self._moving = nil
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point and not EllesmereUIDB then EllesmereUIDB = {} end
        if point then
            EllesmereUIDB.bankPosition = { point = point, relativePoint = relPoint, x = x, y = y }
        end
    end
end)

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local sidebar = CreateFrame("Frame", nil, EUI_Bank)
sidebar:SetPoint("TOPLEFT", EUI_Bank, "TOPLEFT", 0, -HEADER_H)
sidebar:SetPoint("BOTTOMLEFT", EUI_Bank, "BOTTOMLEFT", 0, FOOTER_H)
sidebar:SetWidth(GetBankSidebarWidth())
local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
sidebarBg:SetAllPoints(); sidebarBg:SetColorTexture(0, 0, 0, 0.25)

-- Right-edge separator
do
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local sidebarSep = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetWidth(px)
    sidebarSep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSep:SetColorTexture(0.15, 0.15, 0.15, 1)
end

-- Secure purchase buttons: inherit BankPanelPurchaseButtonScriptTemplate so
-- PurchaseBankTab() runs in Blizzard's secure context, not ours.
local _purchaseBtnChar, _purchaseBtnWarband
do
    local function MakeSecurePurchaseBtn(bankType)
        local b = CreateFrame("Button", nil, sidebar, "BankPanelPurchaseButtonScriptTemplate")
        b:SetAttribute("overrideBankType", bankType)
        b:SetFrameStrata("HIGH")
        b:SetFrameLevel(sidebar:GetFrameLevel() + 20)
        b:EnableMouse(true)
        b:SetAlpha(0)
        b:Hide()
        -- Hover: brighten the visual entry underneath
        b:SetScript("OnEnter", function(self)
            if self._visualBtn then self._visualBtn._bg:SetColorTexture(1, 1, 1, 0.06) end
        end)
        b:SetScript("OnLeave", function(self)
            if self._visualBtn then self._visualBtn._bg:SetColorTexture(1, 1, 1, 0) end
        end)
        return b
    end
    _purchaseBtnChar = MakeSecurePurchaseBtn(Enum.BankType.Character)
    _purchaseBtnWarband = MakeSecurePurchaseBtn(Enum.BankType.Account)
end

-- Sidebar header: "Tabs" label + collapse arrow
local SIDEBAR_HDR_H = 24
local sidebarHdr = CreateFrame("Frame", nil, sidebar)
sidebarHdr:SetHeight(SIDEBAR_HDR_H)
sidebarHdr:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
sidebarHdr:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)

sidebarHdr._label = sidebarHdr:CreateFontString(nil, "OVERLAY")
SetBankFont(sidebarHdr._label, 10)
sidebarHdr._label:SetPoint("LEFT", sidebarHdr, "LEFT", 8, 0)
sidebarHdr._label:SetText("Tabs")
sidebarHdr._label:SetTextColor(0.5, 0.5, 0.5)

local ARROW_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png"
local collapseBtn = CreateFrame("Button", nil, sidebarHdr)
collapseBtn:SetSize(12, 12)
collapseBtn:SetPoint("RIGHT", sidebarHdr, "RIGHT", -6, 0)
collapseBtn._icon = collapseBtn:CreateTexture(nil, "OVERLAY")
collapseBtn._icon:SetAllPoints()
collapseBtn._icon:SetTexture(ARROW_ICON)
collapseBtn._icon:SetAlpha(0.4)

local function UpdateBankCollapseArrow()
    local collapsed = EllesmereUIDB and EllesmereUIDB.bankSidebarCollapsed
    collapseBtn:ClearAllPoints()
    if collapsed then
        collapseBtn._icon:SetRotation(math.pi)
        collapseBtn:SetPoint("CENTER", sidebarHdr, "CENTER", 0, 0)
    else
        collapseBtn._icon:SetRotation(0)
        collapseBtn:SetPoint("RIGHT", sidebarHdr, "RIGHT", -6, 0)
    end
end
UpdateBankCollapseArrow()

collapseBtn:SetScript("OnEnter", function(self)
    self._icon:SetAlpha(0.9)
    local collapsed = EllesmereUIDB and EllesmereUIDB.bankSidebarCollapsed
    if EUI.ShowWidgetTooltip then
        EUI.ShowWidgetTooltip(self, collapsed and "Expand Sidebar" or "Collapse Sidebar")
    end
end)
collapseBtn:SetScript("OnLeave", function(self)
    self._icon:SetAlpha(0.4)
    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
end)
collapseBtn:SetScript("OnClick", function()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    -- Determine which edge to preserve based on screen position
    local center = EUI_Bank:GetCenter()
    local screenW = UIParent:GetWidth()
    local onRightSide = center and screenW and (center > screenW / 2)
    local oldWidth = onRightSide and EUI_Bank:GetWidth() or nil

    EllesmereUIDB.bankSidebarCollapsed = not EllesmereUIDB.bankSidebarCollapsed
    UpdateBankCollapseArrow()
    sidebar:SetWidth(GetBankSidebarWidth())
    EUI_Bank:RefreshBank()

    -- Shift frame by width difference to preserve right edge
    if onRightSide and oldWidth then
        local newWidth = EUI_Bank:GetWidth()
        local shift = oldWidth - newWidth
        if math.abs(shift) > 0.5 then
            local point, rel, relPoint, x, y = EUI_Bank:GetPoint()
            EUI_Bank:ClearAllPoints()
            EUI_Bank:SetPoint(point, rel, relPoint, x + shift, y)
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.bankPosition = { point = point, relativePoint = relPoint, x = x + shift, y = y }
        end
    end
end)

-- Sidebar scroll frame (below header, fills rest of sidebar)
local sidebarSF = CreateFrame("ScrollFrame", nil, sidebar)
sidebarSF:SetPoint("TOPLEFT", sidebarHdr, "BOTTOMLEFT", 0, 0)
sidebarSF:SetSize(GetBankSidebarWidth(), FIXED_H - HEADER_H - FOOTER_H - SIDEBAR_HDR_H)
sidebarSF:EnableMouseWheel(true)
local sidebarChild = CreateFrame("Frame", nil, sidebarSF)
sidebarChild:SetSize(GetBankSidebarWidth(), 1)
sidebarSF:SetScrollChild(sidebarChild)

local SIDEBAR_SCROLL_STEP = 28
sidebarSF:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = sidebarChild:GetHeight() - self:GetHeight()
    if maxScroll <= 0 then return end
    local cur = self:GetVerticalScroll()
    local newVal = math.max(0, math.min(maxScroll, cur - delta * SIDEBAR_SCROLL_STEP))
    self:SetVerticalScroll(newVal)
end)

local _sidebarBtns = {}
-- _selectedView and _allTabs moved to top of file for scope access

-------------------------------------------------------------------------------
--  Scroll Frame + Scrollbar
-------------------------------------------------------------------------------
local sf = CreateFrame("ScrollFrame", nil, EUI_Bank)
sf:SetPoint("TOPLEFT", EUI_Bank, "TOPLEFT", GetBankSidebarWidth(), -HEADER_H)
sf:SetPoint("BOTTOMRIGHT", EUI_Bank, "BOTTOMRIGHT", -1, FOOTER_H)
sf:EnableMouseWheel(true)
local child = CreateFrame("Frame", nil, sf)
child:SetWidth(1); child:SetHeight(1)
child:EnableMouse(false)
sf:SetScrollChild(child)

-- Track (always visible when content scrolls)
local track = CreateFrame("Button", nil, EUI_Bank)
track:SetWidth(SCROLLBAR_HIT_W)
track:SetPoint("TOPRIGHT", EUI_Bank, "TOPRIGHT", -1, -(HEADER_H + 1))
track:SetPoint("BOTTOMRIGHT", EUI_Bank, "BOTTOMRIGHT", -1, FOOTER_H)
track:SetFrameLevel(sf:GetFrameLevel() + 5)

local trackBg = track:CreateTexture(nil, "BACKGROUND")
trackBg:SetWidth(SCROLLBAR_W)
trackBg:SetPoint("TOP", track, "TOP", 0, 0)
trackBg:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
trackBg:SetPoint("RIGHT", track, "RIGHT", 0, 0)
trackBg:SetColorTexture(1, 1, 1, 0.06)

-- Thumb
local thumb = track:CreateTexture(nil, "ARTWORK")
thumb:SetWidth(SCROLLBAR_W)
thumb:SetColorTexture(1, 1, 1, 0.25)
thumb:Hide()

local _isDragging = false
local _dragStartY = 0
local _dragStartPct = 0

local function GetScrollMetrics()
    local scrollRange = sf:GetVerticalScrollRange()
    if not scrollRange or scrollRange <= 0 then return nil end
    local trackH = track:GetHeight()
    local ext = sf:GetHeight() / (sf:GetHeight() + scrollRange)
    local thumbH = math.max(THUMB_MIN_H, trackH * ext)
    local maxTravel = trackH - thumbH
    if maxTravel <= 0 then return nil end
    local pct = sf:GetVerticalScroll() / scrollRange
    return pct, thumbH, maxTravel, scrollRange
end

local function UpdateThumb()
    local pct, thumbH, maxTravel = GetScrollMetrics()
    if not pct then
        thumb:Hide()
        trackBg:Hide()
        return
    end
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(pct * maxTravel))
    thumb:Show()
    trackBg:Show()
end

-- Mouse wheel on scroll frame
sf:SetScript("OnMouseWheel", function(self, delta)
    local scrollRange = sf:GetVerticalScrollRange()
    if not scrollRange or scrollRange <= 0 then return end
    local cur = self:GetVerticalScroll()
    local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
    self:SetVerticalScroll(newVal)
    UpdateThumb()
end)

-- Mouse wheel on main bank frame (items might not cover full area)
EUI_Bank:EnableMouseWheel(true)
EUI_Bank:SetScript("OnMouseWheel", function(_, delta)
    local scrollRange = sf:GetVerticalScrollRange()
    if not scrollRange or scrollRange <= 0 then return end
    local cur = sf:GetVerticalScroll()
    local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
    sf:SetVerticalScroll(newVal)
    UpdateThumb()
end)

-- Thumb dragging (dragUpdate must be declared before OnMouseDown uses it)
local dragUpdate = CreateFrame("Frame")
dragUpdate:Hide()
dragUpdate:SetScript("OnUpdate", function(self)
    if not _isDragging then self:Hide(); return end
    if not IsMouseButtonDown("LeftButton") then
        _isDragging = false; self:Hide()
        thumb:SetColorTexture(1, 1, 1, 0.25)
        return
    end
    local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
    if not pct then _isDragging = false; self:Hide(); return end
    local scale = track:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local deltaY = (_dragStartY - cy / scale)
    local deltaPct = deltaY / maxTravel
    local newPct = math.max(0, math.min(1, _dragStartPct + deltaPct))
    sf:SetVerticalScroll(newPct * scrollRange)
    UpdateThumb()
end)

track:RegisterForDrag("LeftButton")
track:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
    if not pct then return end

    local scale = track:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local trackTop = track:GetTop() * scale
    local cursorLocalY = (trackTop - cy) / scale

    -- Check if cursor is on the thumb
    local thumbTop = pct * maxTravel
    local thumbBot = thumbTop + thumbH
    if cursorLocalY >= thumbTop and cursorLocalY <= thumbBot then
        -- Start drag from thumb
        _isDragging = true
        _dragStartY = cy / scale
        _dragStartPct = pct
        dragUpdate:Show()
    else
        -- Click on track: jump to position
        local clickPct = math.max(0, math.min(1, (cursorLocalY - thumbH / 2) / maxTravel))
        sf:SetVerticalScroll(clickPct * scrollRange)
        UpdateThumb()
        -- Start drag from new position
        _isDragging = true
        _dragStartY = cy / scale
        _dragStartPct = clickPct
        dragUpdate:Show()
    end
end)

track:SetScript("OnMouseUp", function()
    _isDragging = false
end)

-- Hover effect on thumb
track:SetScript("OnEnter", function() thumb:SetColorTexture(1, 1, 1, 0.4) end)
track:SetScript("OnLeave", function()
    if not _isDragging then thumb:SetColorTexture(1, 1, 1, 0.25) end
end)

EUI_Bank._scrollFrame = sf
EUI_Bank._scrollChild = child
EUI_Bank._scrollTrack = track
EUI_Bank._scrollThumb = thumb
EUI_Bank._updateThumb = UpdateThumb

-------------------------------------------------------------------------------
--  Button Pool
-------------------------------------------------------------------------------
local _bankSlots = {}
local _bankSlotIdx = 0
EUI_Bank._bankSlots = _bankSlots

--- Returns the bagID of the currently selected bank tab, or nil if viewing
--- "All Tabs" / "OneBank" (in which case default Blizzard routing applies).
--- For aggregate warband views (-2, -3), returns the first warband tab
--- with an empty slot so right-click deposits go to warband, not character bank.
function EUI_Bank:GetSelectedTabBagID()
    if _selectedView == -2 or _selectedView == -3 then
        -- Aggregate warband view: find first warband tab with space
        for _, tab in ipairs(_allTabs) do
            if tab.isWarband then
                local numSlots = C_Container.GetContainerNumSlots(tab.bagID)
                for slot = 1, numSlots do
                    if not C_Container.GetContainerItemInfo(tab.bagID, slot) then
                        return tab.bagID
                    end
                end
            end
        end
        return nil
    end
    if _selectedView <= 0 then return nil end
    local tab = _allTabs[_selectedView]
    return tab and tab.bagID or nil
end

--- Returns true if the current view is any warband view (all warbank,
--- onewarbank, or an individual warband tab).
function EUI_Bank:IsWarbandView()
    if _selectedView == -2 or _selectedView == -3 then return true end
    if _selectedView > 0 and _allTabs[_selectedView] then
        return _allTabs[_selectedView].isWarband
    end
    return false
end

--- Find the first empty slot in a specific bank bag and deposit the cursor
--- item into it. If no empty slot, try stacking with an existing partial stack.
--- Returns true if placement was attempted, false if no space found.
function EUI_Bank:DepositCursorItemIntoTab(bagID)
    if not bagID then return false end
    local numSlots = C_Container.GetContainerNumSlots(bagID)
    if numSlots == 0 then return false end
    -- Try stacking first (same itemID, not full stack)
    local cursorType, cursorItemID = GetCursorInfo()
    if cursorType ~= "item" or not cursorItemID then return false end
    local maxStack = C_Item.GetItemMaxStackSizeByID(cursorItemID) or 1
    if maxStack > 1 then
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID == cursorItemID and info.stackCount < maxStack then
                C_Container.PickupContainerItem(bagID, slot)
                return true
            end
        end
    end
    -- Then try first empty slot
    for slot = 1, numSlots do
        if not C_Container.GetContainerItemInfo(bagID, slot) then
            C_Container.PickupContainerItem(bagID, slot)
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Transfer Queue: queues rapid right-click deposits so they don't collide
--
--  allocatedSlots tracks target bank slots that have a pending transfer so
--  the next deposit picks a different slot.  Items that are still locked from
--  a prior move get queued and re-processed on the next BAG_UPDATE.
-------------------------------------------------------------------------------
local _transferQueue = {}       -- { {bag, slot}, ... }
local _allocatedSlots = {}      -- [bagID*1000+slot] = true
local _transferEventFrame

local function WipeTransferState()
    wipe(_transferQueue)
    wipe(_allocatedSlots)
    if _transferEventFrame then
        _transferEventFrame:UnregisterAllEvents()
    end
end

local function IsSlotAllocated(bagID, slot)
    return _allocatedSlots[bagID * 1000 + slot]
end

local function AllocateSlot(bagID, slot)
    _allocatedSlots[bagID * 1000 + slot] = true
end

--- Find target in a specific bank bag, skipping allocated slots.
--- Tries partial stacks first, then empty slots.
local function FindTargetSlot(targetBag, srcItemID)
    local numSlots = C_Container.GetContainerNumSlots(targetBag)
    if numSlots == 0 then return nil end
    local maxStack = C_Item.GetItemMaxStackSizeByID(srcItemID) or 1
    -- Partial stack first
    if maxStack > 1 then
        for slot = 1, numSlots do
            if not IsSlotAllocated(targetBag, slot) then
                local info = C_Container.GetContainerItemInfo(targetBag, slot)
                if info and info.itemID == srcItemID and info.stackCount < maxStack then
                    return slot
                end
            end
        end
    end
    -- Empty slot
    for slot = 1, numSlots do
        if not IsSlotAllocated(targetBag, slot) then
            if not C_Container.GetContainerItemInfo(targetBag, slot) then
                return slot
            end
        end
    end
    return nil
end

local function ProcessTransfer(srcBag, srcSlot)
    local loc = ItemLocation:CreateFromBagAndSlot(srcBag, srcSlot)
    if not C_Item.DoesItemExist(loc) or C_Item.IsLocked(loc) then
        return false -- still locked, needs re-queue
    end
    local bank = _G.EUI_BankFrame
    if not bank or not bank:IsVisible() then return true end -- bank closed, discard
    local targetBag = bank:GetSelectedTabBagID()
    if not targetBag then return true end -- no tab selected, discard
    local info = C_Container.GetContainerItemInfo(srcBag, srcSlot)
    if not info or not info.itemID then return true end
    local targetSlot = FindTargetSlot(targetBag, info.itemID)
    if not targetSlot then return true end -- no space, discard
    AllocateSlot(targetBag, targetSlot)
    C_Container.PickupContainerItem(srcBag, srcSlot)
    C_Container.PickupContainerItem(targetBag, targetSlot)
    return true
end

local function DrainQueue()
    -- Clear allocations for slots that now have items (transfer completed)
    for key in pairs(_allocatedSlots) do
        local bagID = math.floor(key / 1000)
        local slot = key % 1000
        if C_Container.GetContainerItemInfo(bagID, slot) then
            _allocatedSlots[key] = nil
        end
    end
    -- Process queued items
    local remaining = {}
    for _, entry in ipairs(_transferQueue) do
        if not ProcessTransfer(entry[1], entry[2]) then
            remaining[#remaining + 1] = entry
        end
    end
    wipe(_transferQueue)
    for _, entry in ipairs(remaining) do
        _transferQueue[#_transferQueue + 1] = entry
    end
    -- Unregister when idle
    if #_transferQueue == 0 and not next(_allocatedSlots) then
        if _transferEventFrame then _transferEventFrame:UnregisterAllEvents() end
    end
end

local function EnsureTransferEventFrame()
    if _transferEventFrame then return end
    _transferEventFrame = CreateFrame("Frame")
    _transferEventFrame:SetScript("OnEvent", function() DrainQueue() end)
end

--- Public: queue a bag item for transfer to the selected bank tab.
--- Called from the bag button PreClick hook.
function EUI_Bank:QueueTransfer(srcBag, srcSlot)
    EnsureTransferEventFrame()
    _transferEventFrame:RegisterEvent("BAG_UPDATE")
    if not ProcessTransfer(srcBag, srcSlot) then
        _transferQueue[#_transferQueue + 1] = { srcBag, srcSlot }
    end
end

local function GetOrCreateBankSlot(idx)
    if _bankSlots[idx] then return _bankSlots[idx] end
    local slotParent = CreateFrame("Frame", nil, EUI_Bank)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- OnReceiveDrag: handles native Blizzard drags (shift-click pickup etc.)
    btn:SetScript("OnReceiveDrag", function(self)
        local bagID = self:GetParent():GetID()
        local slotID = self:GetID()
        C_Container.PickupContainerItem(bagID, slotID)
    end)

    -- Hide template decorations
    if btn.NewItemTexture then btn.NewItemTexture:Hide(); btn.NewItemTexture:SetAlpha(0) end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide(); btn.BattlepayItemTexture:SetAlpha(0) end
    if btn.flash then btn.flash:Hide(); btn.flash:SetAlpha(0) end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end

    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    if btn.icon then btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    -- Remove highlight/pushed textures shape
    local ht = btn.HighlightTexture or btn:GetHighlightTexture()
    if ht then ht:SetTexture(nil); ht:SetColorTexture(1, 1, 1, 0.08); ht:ClearAllPoints(); ht:SetAllPoints(btn) end
    local pt = btn.PushedTexture or btn:GetPushedTexture()
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture("Interface\\AddOns\\EllesmereUIActionBars\\Media\\highlight-3.png")
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints(); pt:SetAllPoints(btn)
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
    end
    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
    if btn.icon and btn.IconMask then
        btn.icon:RemoveMaskTexture(btn.IconMask)
        btn.IconMask:Hide(); btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints(); btn.IconMask:SetSize(0.001, 0.001)
    end

    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    -- Text overlay above cooldown
    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 2)
    btn._textOverlay = textOverlay

    local countSize = EllesmereUIDB and EllesmereUIDB.bagCountFontSize or 11
    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        countFS:SetFont(BANK_FONT, countSize, "OUTLINE")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    -- Item level text (top-left, gear only)
    local ilvlSize = EllesmereUIDB and EllesmereUIDB.itemlevelFontSize or 12
    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    btn.ItemLevelText:SetFont(BANK_FONT, ilvlSize, "OUTLINE")
    btn.ItemLevelText:SetText("")

    -- Empty bg
    btn._emptyBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    btn._emptyBg:SetAllPoints()
    btn._emptyBg:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\icon-bg.png")

    _bankSlots[idx] = btn
    return btn
end

-------------------------------------------------------------------------------
--  Render Button
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Category Headers
-------------------------------------------------------------------------------
local _bankHeaders = {}
local function GetOrCreateBankHeader(idx)
    if _bankHeaders[idx] then return _bankHeaders[idx] end
    local f = CreateFrame("Frame", nil, EUI_Bank)
    f:SetHeight(20)
    f._label = f:CreateFontString(nil, "OVERLAY")
    SetBankFont(f._label, 11)
    f._label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._label:SetTextColor(0.7, 0.7, 0.7)
    f._label:SetJustifyH("LEFT")
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    f._line = f:CreateTexture(nil, "ARTWORK")
    f._line:SetHeight(px)
    f._line:SetPoint("LEFT", f._label, "RIGHT", 6, 0)
    f._line:SetPoint("RIGHT", f, "RIGHT", -SPACING, 0)
    f._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    _bankHeaders[idx] = f
    return f
end

local function DiscoverBankTabs()
    _allTabs = {}
    local charTabs = GetCharacterBankTabs()
    for _, t in ipairs(charTabs) do
        t.isWarband = false
        _allTabs[#_allTabs + 1] = t
    end
    local warbandTabs = GetWarbandBankTabs()
    for _, t in ipairs(warbandTabs) do
        t.isWarband = true
        _allTabs[#_allTabs + 1] = t
    end
    EUI_Bank._allTabs = _allTabs
end

-- Fast font size update for bank slots (mirrors bags RefreshTextSizes)
local function RefreshBankTextSizes()
    local countSize = EllesmereUIDB and EllesmereUIDB.bagCountFontSize or 11
    local ilvlSize = EllesmereUIDB and EllesmereUIDB.itemlevelFontSize or 12
    for _, btn in pairs(_bankSlots) do
        if btn.Count then btn.Count:SetFont(BANK_FONT, countSize, "OUTLINE") end
        if btn.ItemLevelText then btn.ItemLevelText:SetFont(BANK_FONT, ilvlSize, "OUTLINE") end
    end
end
EUI_Bank.RefreshTextSizes = RefreshBankTextSizes

local function CountUsedSlots(bagID, numSlots)
    local used = 0
    for slot = 1, numSlots do
        if C_Container.GetContainerItemInfo(bagID, slot) then used = used + 1 end
    end
    return used
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
function EUI_Bank:RefreshBank()
    if not EUI_Bank:IsVisible() then return end

    -- Re-discover tabs if empty (data may not be ready on the same frame as
    -- BANKFRAME_OPENED; BAG_UPDATE fires shortly after with real slot counts).
    if #_allTabs == 0 then
        DiscoverBankTabs()
        if #_allTabs == 0 then return end
    end


    -- Search filter
    local searchQuery = ""
    if EUI_Bank._searchBox then
        searchQuery = EUI_Bank._searchBox:GetText() or ""
        searchQuery = searchQuery:lower()
    end
    local hasSearch = searchQuery ~= ""

    -- Don't hide slots upfront: the batch renderer overwrites them in place.
    -- Excess slots are hidden after all batches complete (prevents blink).
    for _, hdr in pairs(_bankHeaders) do hdr:Hide() end

    -- Update sidebar and scroll frame widths
    local sidebarW = GetBankSidebarWidth()
    sidebar:SetWidth(sidebarW)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", EUI_Bank, "TOPLEFT", sidebarW, -HEADER_H)
    sf:SetPoint("BOTTOMRIGHT", EUI_Bank, "BOTTOMRIGHT", -1, FOOTER_H)

    local gridPadX = 10
    local gridW = COLUMNS * (SLOT_SIZE + SPACING)
    local startX = gridPadX + 5

    -- Set frame size BEFORE rendering so scroll frame has non-zero bounds
    local totalW = sidebarW + gridW + gridPadX * 2 + SCROLLBAR_HIT_W + 2
    EUI_Bank:SetWidth(totalW)
    EUI_Bank:SetHeight(FIXED_H)
    child:SetWidth(gridW + gridPadX * 2 + SCROLLBAR_HIT_W)

    -- Helper: check if a slot passes the search filter
    local function PassesSearch(bagID, slot)
        if not hasSearch then return true end
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if not info then return false end
        local link = C_Container.GetContainerItemLink(bagID, slot)
        local itemName = link and GetItemInfo(link)
        if not itemName then return false end
        return itemName:lower():find(searchQuery, 1, true) ~= nil
    end

    -- Phase 1: Build flat layout list (no button creation, just positions).
    -- Each entry = { bagID, slot, x, y } for items, or "header" entries.
    local _layout = {}
    local curY = -6
    local headerIdx = 0

    -- Helper: build flat slot list for a set of tabs
    local function BuildOneView(tabs)
        local collected = {}
        local filled = 0
        for _, tab in ipairs(tabs) do
            for slot = 1, tab.numSlots do
                if PassesSearch(tab.bagID, slot) then
                    local info = C_Container.GetContainerItemInfo(tab.bagID, slot)
                    collected[#collected + 1] = { bagID = tab.bagID, slot = slot, _cachedInfo = info }
                    if info then filled = filled + 1 end
                end
            end
        end
        return collected, filled
    end

    local function LayoutFlatSlots(slotList, headerLabel)
        if #slotList > 0 or not hasSearch then
            headerIdx = headerIdx + 1
            _layout[#_layout + 1] = {
                isHeader = true, headerIdx = headerIdx,
                label = headerLabel, x = startX, y = curY, w = gridW,
            }
            curY = curY - 22
            for vi, s in ipairs(slotList) do
                local col = (vi - 1) % COLUMNS
                local row = math.floor((vi - 1) / COLUMNS)
                _layout[#_layout + 1] = {
                    bagID = s.bagID, slot = s.slot, _cachedInfo = s._cachedInfo,
                    x = startX + (col * (SLOT_SIZE + SPACING)),
                    y = curY - (row * (SLOT_SIZE + SPACING)),
                }
            end
            local rows = math.ceil(math.max(#slotList, 1) / COLUMNS)
            curY = curY - (rows * (SLOT_SIZE + SPACING)) - 6
        end
    end

    -- Helper: build per-tab header layout for a set of tabs
    local function LayoutTabHeaders(tabs)
        for _, tab in ipairs(tabs) do
            if tab.numSlots > 0 then
                local visibleSlots = {}
                local used = 0
                for slot = 1, tab.numSlots do
                    local info = C_Container.GetContainerItemInfo(tab.bagID, slot)
                    if info then used = used + 1 end
                    if not hasSearch or info then
                        visibleSlots[#visibleSlots + 1] = { slot = slot, _cachedInfo = info }
                    end
                end
                -- When searching, filter by name
                if hasSearch then
                    local filtered = {}
                    for _, vs in ipairs(visibleSlots) do
                        if vs._cachedInfo then
                            local link = C_Container.GetContainerItemLink(tab.bagID, vs.slot)
                            local itemName = link and GetItemInfo(link)
                            if itemName and itemName:lower():find(searchQuery, 1, true) then
                                filtered[#filtered + 1] = vs
                            end
                        end
                    end
                    visibleSlots = filtered
                end
                if not hasSearch or #visibleSlots > 0 then
                    headerIdx = headerIdx + 1
                    _layout[#_layout + 1] = {
                        isHeader = true, headerIdx = headerIdx,
                        label = tab.name .. " (" .. used .. ")",
                        x = startX, y = curY, w = gridW,
                    }
                    curY = curY - 22
                    local count = hasSearch and #visibleSlots or tab.numSlots
                    for vi = 1, count do
                        local slot, cachedInfo
                        if hasSearch then
                            slot = visibleSlots[vi].slot
                            cachedInfo = visibleSlots[vi]._cachedInfo
                        else
                            slot = vi
                            cachedInfo = visibleSlots[vi] and visibleSlots[vi]._cachedInfo
                        end
                        local col = (vi - 1) % COLUMNS
                        local row = math.floor((vi - 1) / COLUMNS)
                        _layout[#_layout + 1] = {
                            bagID = tab.bagID, slot = slot, _cachedInfo = cachedInfo,
                            x = startX + (col * (SLOT_SIZE + SPACING)),
                            y = curY - (row * (SLOT_SIZE + SPACING)),
                        }
                    end
                    local rows = math.ceil(count / COLUMNS)
                    curY = curY - (rows * (SLOT_SIZE + SPACING)) - 6
                end
            end
        end
    end

    -- Split tabs into char and warband
    local charTabs, warbTabs = {}, {}
    for _, tab in ipairs(_allTabs) do
        if tab.isWarband then warbTabs[#warbTabs + 1] = tab
        else charTabs[#charTabs + 1] = tab end
    end

    if _selectedView == -1 then
        -- OneBank: character bank only, flat with "Bank" header
        local slots, filled = BuildOneView(charTabs)
        LayoutFlatSlots(slots, "Bank (" .. filled .. " / " .. #slots .. ")")

    elseif _selectedView == -3 then
        -- OneWarbank: warband bank only, flat with "Warband Bank" header
        local slots, filled = BuildOneView(warbTabs)
        LayoutFlatSlots(slots, "Warband Bank (" .. filled .. " / " .. #slots .. ")")

    elseif _selectedView == -2 then
        -- All Warbank Tabs: per-tab headers for warband only
        LayoutTabHeaders(warbTabs)

    elseif _selectedView == 0 then
        -- All Bank Tabs: per-tab headers for character only
        LayoutTabHeaders(charTabs)
    else
        local tab = _allTabs[_selectedView]
        if tab then
            local allSlots = {}
            local used = 0
            for slot = 1, tab.numSlots do
                local info = C_Container.GetContainerItemInfo(tab.bagID, slot)
                if info then used = used + 1 end
                allSlots[#allSlots + 1] = { slot = slot, _cachedInfo = info }
            end
            local visibleSlots = allSlots
            if hasSearch then
                local filtered = {}
                for _, vs in ipairs(allSlots) do
                    if vs._cachedInfo then
                        local link = C_Container.GetContainerItemLink(tab.bagID, vs.slot)
                        local itemName = link and GetItemInfo(link)
                        if itemName and itemName:lower():find(searchQuery, 1, true) then
                            filtered[#filtered + 1] = vs
                        end
                    end
                end
                visibleSlots = filtered
            end
            headerIdx = headerIdx + 1
            _layout[#_layout + 1] = {
                isHeader = true, headerIdx = headerIdx,
                label = tab.name .. " (" .. used .. ")",
                x = startX, y = curY, w = gridW,
            }
            curY = curY - 22
            local count = #visibleSlots
            for vi = 1, count do
                local vs = visibleSlots[vi]
                local col = (vi - 1) % COLUMNS
                local row = math.floor((vi - 1) / COLUMNS)
                _layout[#_layout + 1] = {
                    bagID = tab.bagID, slot = vs.slot, _cachedInfo = vs._cachedInfo,
                    x = startX + (col * (SLOT_SIZE + SPACING)),
                    y = curY - (row * (SLOT_SIZE + SPACING)),
                }
            end
            local rows = math.ceil(count / COLUMNS)
            curY = curY - (rows * (SLOT_SIZE + SPACING))
        end
    end

    -- Update deposit button based on current view
    local isWarbandView = (_selectedView == -2 or _selectedView == -3)
    if not isWarbandView and _selectedView > 0 and _allTabs[_selectedView] then
        isWarbandView = _allTabs[_selectedView].isWarband
    end
    EUI_Bank:UpdateDepositButton(isWarbandView)

    -- Set scroll child height from layout
    child:SetHeight(math.abs(curY) + 10)

    -- Phase 2: Render only visible entries (viewport culling).
    -- Re-runs on scroll to update which buttons are shown.
    EUI_Bank._layout = _layout
    EUI_Bank._layoutStartX = startX
    EUI_Bank._layoutGridW = gridW

    -- Shared slot render: updates a single button with item or empty state
    local function RenderSlotContent(btn, bagID, slot, cachedInfo)
        if btn.ProfessionQualityOverlay then btn.ProfessionQualityOverlay:SetAlpha(0) end
        if btn.IconOverlay then btn.IconOverlay:SetAlpha(0); btn.IconOverlay:Hide() end
        if btn.IconOverlay2 then btn.IconOverlay2:SetAlpha(0); btn.IconOverlay2:Hide() end
        local info = cachedInfo or C_Container.GetContainerItemInfo(bagID, slot)
        if not info then
            btn:SetItemButtonTexture(nil)
            btn:SetItemButtonCount(0)
            SetItemButtonDesaturated(btn, false)
            if btn.icon then btn.icon:Hide() end
            btn._emptyBg:Show(); btn._emptyBg:SetAlpha(0.35)
            btn:EnableMouse(true)
            SetInsetBorderColor(btn, 0, 0, 0, 0.3)
            if btn.Cooldown then btn.Cooldown:Clear() end
            if btn.ItemLevelText then btn.ItemLevelText:SetText("") end
            if btn.IconBorder then btn.IconBorder:Hide() end
            if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
        else
            btn:EnableMouse(true)
            btn._emptyBg:Hide()
            if btn.icon then btn.icon:Show() end
            btn:SetItemButtonTexture(info.iconFileID)
            btn:SetItemButtonCount(info.stackCount)
            SetItemButtonDesaturated(btn, info.isLocked)
            local itemLink = C_Container.GetContainerItemLink(bagID, slot)
            local quality = info.quality or 1
            if itemLink then btn:SetItemButtonQuality(quality, itemLink, false, false) end
            if btn.ProfessionQualityOverlay and btn.ProfessionQualityOverlay:IsShown() and btn._textOverlay then
                btn.ProfessionQualityOverlay:SetAlpha(1)
                btn.ProfessionQualityOverlay:SetParent(btn._textOverlay)
            end
            if btn.IconOverlay then
                if btn.IconOverlay:IsShown() then
                    btn.IconOverlay:SetAlpha(1)
                    if btn._textOverlay then btn.IconOverlay:SetParent(btn._textOverlay) end
                else btn.IconOverlay:SetAlpha(0) end
            end
            if btn.IconOverlay2 then
                if btn.IconOverlay2:IsShown() then
                    btn.IconOverlay2:SetAlpha(1)
                    if btn._textOverlay then btn.IconOverlay2:SetParent(btn._textOverlay) end
                else btn.IconOverlay2:SetAlpha(0) end
            end
            if btn.IconBorder then btn.IconBorder:Hide() end
            if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
            local c = ITEM_QUALITY_COLORS[quality]
            if c then SetInsetBorderColor(btn, c.r, c.g, c.b, 1)
            else SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1) end
            -- Item level (gear only)
            if btn.ItemLevelText then
                if itemLink and IsGearItem(itemLink) then
                    local showIlvl = not EllesmereUIDB or EllesmereUIDB.showItemlevelInBags ~= false
                    if showIlvl then
                        local _, _, _, ilvl = GetItemInfo(itemLink)
                        btn.ItemLevelText:SetText(ilvl or "")
                        local r, g, b
                        if GetUpgradeTrack then
                            local rankText, trackColor = GetUpgradeTrack(itemLink)
                            if EllesmereUIDB and EllesmereUIDB.itemlevelUseCustomColor and EllesmereUIDB.itemlevelCustomColor then
                                r, g, b = EllesmereUIDB.itemlevelCustomColor.r, EllesmereUIDB.itemlevelCustomColor.g, EllesmereUIDB.itemlevelCustomColor.b
                            elseif rankText and rankText ~= "" and trackColor then
                                r, g, b = trackColor.r, trackColor.g, trackColor.b
                            end
                        end
                        if not r then
                            r, g, b = GetItemQualityColor(quality)
                        end
                        btn.ItemLevelText:SetTextColor(r, g, b, 1)
                    else
                        btn.ItemLevelText:SetText("")
                    end
                else
                    btn.ItemLevelText:SetText("")
                end
            end
            if btn.Cooldown then
                local cdS, cdD, cdE = C_Container.GetContainerItemCooldown(bagID, slot)
                if cdE and cdE ~= 0 and cdS > 0 and cdD > 0 then
                    btn.Cooldown:SetDrawEdge(true); btn.Cooldown:SetCooldown(cdS, cdD)
                else btn.Cooldown:Clear() end
            end
        end
    end

    -- Render in batches of 100 per frame via OnUpdate.
    local BATCH_SIZE = 100
    local rendered = 0
    local slotIdx = 0

    local function RenderBatch()
        local batchEnd = math.min(rendered + BATCH_SIZE, #_layout)
        for li = rendered + 1, batchEnd do
            local entry = _layout[li]
            if entry.isHeader then
                local hdr = GetOrCreateBankHeader(entry.headerIdx)
                hdr:SetParent(child)
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", entry.x, entry.y)
                hdr:SetWidth(entry.w)
                hdr._label:SetText(entry.label)
                hdr:Show()
            else
                slotIdx = slotIdx + 1
                local btn = GetOrCreateBankSlot(slotIdx)
                btn:GetParent():SetParent(child)
                local parent = btn:GetParent()
                parent:ClearAllPoints()
                parent:SetPoint("TOPLEFT", entry.x, entry.y)
                parent:Show()
                btn:Show()
                btn:SetID(entry.slot)
                parent:SetID(entry.bagID)

                RenderSlotContent(btn, entry.bagID, entry.slot, entry._cachedInfo)
            end
        end
        rendered = batchEnd
    end

    -- Render first batch immediately (same frame) so item moves don't blink.
    -- Remaining batches deferred via OnUpdate for large refreshes (tab open).
    RenderBatch()
    if not EUI_Bank._batchFrame then
        EUI_Bank._batchFrame = CreateFrame("Frame")
    end
    EUI_Bank._batchFrame:SetScript("OnUpdate", function(self)
        if rendered >= #_layout or not EUI_Bank:IsVisible() then
            self:SetScript("OnUpdate", nil)
            -- Hide excess slots that weren't used this refresh
            for si = slotIdx + 1, #_bankSlots do
                if _bankSlots[si] then _bankSlots[si]:GetParent():Hide() end
            end
            return
        end
        RenderBatch()
        if rendered >= #_layout then
            self:SetScript("OnUpdate", nil)
            for si = slotIdx + 1, #_bankSlots do
                if _bankSlots[si] then _bankSlots[si]:GetParent():Hide() end
            end
        end
    end)

    sf:SetVerticalScroll(math.min(sf:GetVerticalScroll(), sf:GetVerticalScrollRange()))
    UpdateThumb()

    -- Build sidebar
    BuildBankSidebar()
end

-------------------------------------------------------------------------------
--  Sidebar Build
-------------------------------------------------------------------------------
function BuildBankSidebar()
    local collapsed = EllesmereUIDB and EllesmereUIDB.bankSidebarCollapsed
    local sidebarW = GetBankSidebarWidth()
    local y = 0
    local ar, ag, ab = GetAccentRGB()
    sidebarSF:SetSize(sidebarW, FIXED_H - HEADER_H - FOOTER_H - SIDEBAR_HDR_H)
    sidebarChild:SetWidth(sidebarW)
    local btnIdx = 0

    -- Update sidebar header label visibility
    if collapsed then sidebarHdr._label:Hide()
    else sidebarHdr._label:Show() end

    local function MakeSidebarBtn(idx)
        if _sidebarBtns[idx] then return _sidebarBtns[idx] end
        local btn = CreateFrame("Button", nil, sidebarChild)
        btn:SetHeight(SIDEBAR_BTN_H)
        btn._indicator = btn:CreateTexture(nil, "OVERLAY")
        local PP = EUI and EUI.PP
        local px = (PP and PP.mult) or 1
        btn._indicator:SetWidth(px * 2)
        btn._indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn._indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        btn._bg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        btn._bg:SetAllPoints(); btn._bg:SetColorTexture(1, 1, 1, 0)
        btn._icon = btn:CreateTexture(nil, "ARTWORK")
        btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn._label = btn:CreateFontString(nil, "OVERLAY")
        SetBankFont(btn._label, 11)
        btn._label:SetJustifyH("LEFT"); btn._label:SetWordWrap(false)
        btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
        btn._label:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
        btn._count = btn:CreateFontString(nil, "OVERLAY")
        SetBankFont(btn._count, 10)
        btn._count:SetJustifyH("RIGHT")
        btn._count:SetTextColor(0.5, 0.5, 0.5)
        btn._count:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        btn:SetScript("OnEnter", function(self)
            if not self._isSelected then self._bg:SetColorTexture(1, 1, 1, 0.06) end
            if (EllesmereUIDB and EllesmereUIDB.bankSidebarCollapsed) and EUI.ShowWidgetTooltip then
                EUI.ShowWidgetTooltip(self, (self._entryName or "?") .. " (" .. (self._entryCount or 0) .. ")")
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self._isSelected then self._bg:SetColorTexture(1, 1, 1, 0) end
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        end)
        btn:SetScript("OnClick", function(self)
            if self._isPurchaseTab then return end
            _selectedView = self._viewIdx
            if EUI_Bank._scrollFrame then EUI_Bank._scrollFrame:SetVerticalScroll(0) end
            EUI_Bank:RefreshBank()
            -- Refresh bags so warbank dim overlay updates immediately
            if _G.EUI_Bags and _G.EUI_Bags:IsVisible() and _G.EUI_Bags.RefreshInventory then
                _G.EUI_Bags:RefreshInventory()
            end
        end)
        _sidebarBtns[idx] = btn
        return btn
    end

    local function RenderPurchaseEntry(bankType, label)
        btnIdx = btnIdx + 1
        local btn = MakeSidebarBtn(btnIdx)
        btn._viewIdx = nil
        btn._isPurchaseTab = true
        btn._purchaseBankType = bankType
        btn._isSelected = false
        btn._entryName = label
        btn._entryCount = 0
        btn._indicator:Hide()
        btn._bg:SetColorTexture(1, 1, 1, 0)
        btn:SetParent(sidebarChild)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", 0, y)
        btn:SetWidth(sidebarW)
        btn._icon:ClearAllPoints()
        if collapsed then
            btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        else
            btn._icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        end
        btn._icon:SetTexture(133784)
        btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn._icon:SetDesaturated(false)
        btn._icon:SetAlpha(0.6)
        if collapsed then
            btn._label:Hide()
            btn._count:Hide()
        else
            btn._label:Show()
            btn._label:SetText(label)
            btn._label:SetTextColor(1, 1, 1, 0.6)
            btn._count:Hide()
        end
        btn:SetAlpha(0.6)
        btn:Show()
        -- Overlay the secure purchase button on top of this visual entry
        local secBtn = (bankType == Enum.BankType.Character) and _purchaseBtnChar or _purchaseBtnWarband
        secBtn._visualBtn = btn
        secBtn:SetParent(sidebarChild)
        secBtn:ClearAllPoints()
        secBtn:SetAllPoints(btn)
        secBtn:SetFrameLevel(btn:GetFrameLevel() + 20)
        secBtn:Show()
        y = y - SIDEBAR_BTN_H - SIDEBAR_PAD
    end

    local function RenderSidebarEntry(viewIdx, name, icon, count, isSelected)
        btnIdx = btnIdx + 1
        local btn = MakeSidebarBtn(btnIdx)
        btn._viewIdx = viewIdx
        btn._isPurchaseTab = false
        btn._isSelected = isSelected
        btn._entryName = name
        btn._entryCount = count
        btn:SetAlpha(1)
        btn:SetParent(sidebarChild)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", 0, y)
        btn:SetWidth(sidebarW)
        btn._icon:ClearAllPoints()
        if collapsed then
            btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        else
            btn._icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        end
        btn._icon:SetTexture(icon)
        btn._icon:SetAlpha(isSelected and 1 or 0.75)

        if collapsed then
            btn._label:Hide()
            btn._count:Hide()
        else
            btn._label:Show()
            btn._label:SetText(name)
            btn._label:SetTextColor(1, 1, 1, isSelected and 1 or 0.75)
            btn._count:Show()
            btn._count:SetText(tostring(count))
        end

        if isSelected then
            btn._indicator:SetColorTexture(ar, ag, ab, 1); btn._indicator:Show()
            btn._bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            btn._indicator:Hide()
            btn._bg:SetColorTexture(1, 1, 1, 0)
        end
        btn:Show()
        y = y - SIDEBAR_BTN_H - SIDEBAR_PAD
    end

    -- Hide all sidebar buttons + secure purchase overlays
    for _, btn in pairs(_sidebarBtns) do btn:Hide() end
    _purchaseBtnChar:Hide()
    _purchaseBtnWarband:Hide()

    -- Count used slots per tab, split by bank/warbank
    local charUsed, charTotal = 0, 0
    local warbUsed, warbTotal = 0, 0
    for _, tab in ipairs(_allTabs) do
        tab._usedSlots = CountUsedSlots(tab.bagID, tab.numSlots)
        if tab.isWarband then
            warbUsed = warbUsed + tab._usedSlots
            warbTotal = warbTotal + tab.numSlots
        else
            charUsed = charUsed + tab._usedSlots
            charTotal = charTotal + tab.numSlots
        end
    end

    -- Update header item count
    if EUI_Bank._headerItemCount then
        if _warbandOnly then
            EUI_Bank._headerItemCount:SetText(warbUsed .. " / " .. warbTotal .. " Items")
        else
            EUI_Bank._headerItemCount:SetText((charUsed + warbUsed) .. " / " .. (charTotal + warbTotal) .. " Items")
        end
    end

    -- View indices: 0 = All Bank Tabs, -1 = OneBank, -2 = All Warbank Tabs, -3 = OneWarbank
    -- >0 = individual tab index in _allTabs

    local defaultOneBag = EllesmereUIDB and EllesmereUIDB.bagDefaultOneBag
    if not _warbandOnly then
        if defaultOneBag then
            RenderSidebarEntry(-1, "OneBank", 1542860, charUsed, _selectedView == -1)
            RenderSidebarEntry(0, "All Bank Tabs", 413587, charUsed, _selectedView == 0)
        else
            RenderSidebarEntry(0, "All Bank Tabs", 413587, charUsed, _selectedView == 0)
            RenderSidebarEntry(-1, "OneBank", 1542860, charUsed, _selectedView == -1)
        end
    end

    -- Warband "All" and "One" entries
    local hasWarband = false
    for _, tab in ipairs(_allTabs) do
        if tab.isWarband then hasWarband = true; break end
    end
    if hasWarband then
        if defaultOneBag then
            RenderSidebarEntry(-3, "OneWarbank", 1542854, warbUsed, _selectedView == -3)
            RenderSidebarEntry(-2, "All Warbank Tabs", 1542854, warbUsed, _selectedView == -2)
        else
            RenderSidebarEntry(-2, "All Warbank Tabs", 1542854, warbUsed, _selectedView == -2)
            RenderSidebarEntry(-3, "OneWarbank", 1542854, warbUsed, _selectedView == -3)
        end
    end

    -- Divider
    local function ShowDivider(key)
        if not sidebarChild[key] then
            local PP = EUI and EUI.PP
            local px = (PP and PP.mult) or 1
            local div = sidebarChild:CreateTexture(nil, "ARTWORK")
            div:SetHeight(px)
            div:SetColorTexture(0.2, 0.2, 0.2, 1)
            sidebarChild[key] = div
        end
        y = y - 4
        local div = sidebarChild[key]
        div:ClearAllPoints()
        local inset = math.floor(sidebarW * 0.08)
        div:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", inset, y)
        div:SetPoint("TOPRIGHT", sidebarChild, "TOPRIGHT", -inset, y)
        div:Show()
        y = y - (div:GetHeight() or 1) - 4
    end

    if not _warbandOnly then
        ShowDivider("_bankTabDivider")

        -- Character bank tabs
        for ti, tab in ipairs(_allTabs) do
            if not tab.isWarband then
                RenderSidebarEntry(ti, tab.name, tab.icon or 133652, tab._usedSlots, _selectedView == ti)
            end
        end
        -- Purchase character bank tab (show one grayed-out entry if more can be bought)
        if C_Bank and C_Bank.CanPurchaseBankTab and C_Bank.HasMaxBankTabs
            and C_Bank.CanPurchaseBankTab(Enum.BankType.Character)
            and not C_Bank.HasMaxBankTabs(Enum.BankType.Character) then
            RenderPurchaseEntry(Enum.BankType.Character, "Buy Bank Tab")
        end
    else
        if sidebarChild._bankTabDivider then sidebarChild._bankTabDivider:Hide() end
    end

    -- Warband individual tabs
    if hasWarband then
        ShowDivider("_warbandDivider")

        for ti, tab in ipairs(_allTabs) do
            if tab.isWarband then
                RenderSidebarEntry(ti, tab.name, tab.icon or 1542854, tab._usedSlots, _selectedView == ti)
            end
        end
    else
        if sidebarChild._warbandDivider then sidebarChild._warbandDivider:Hide() end
        if sidebarChild._warbandTabDivider then sidebarChild._warbandTabDivider:Hide() end
    end
    -- Purchase warband bank tab
    if C_Bank and C_Bank.CanPurchaseBankTab and C_Bank.HasMaxBankTabs
        and C_Bank.CanPurchaseBankTab(Enum.BankType.Account)
        and not C_Bank.HasMaxBankTabs(Enum.BankType.Account) then
        if not hasWarband then
            ShowDivider("_warbandDivider")
        end
        RenderPurchaseEntry(Enum.BankType.Account, "Buy Warbank Tab")
    end

    -- Set scroll child height so scrolling works when content overflows
    sidebarChild:SetHeight(math.abs(y) + 4)
end

-------------------------------------------------------------------------------
--  Events: Open/Close Bank
-------------------------------------------------------------------------------
-- Debounced refresh (many BAG_UPDATE/PLAYERBANKSLOTS_CHANGED fire rapidly)
local bankRefreshPending = false
local function ScheduleBankRefresh()
    if bankRefreshPending then return end
    bankRefreshPending = true
    C_Timer.After(0.1, function()
        bankRefreshPending = false
        if EUI_Bank:IsVisible() then
            EUI_Bank:RefreshBank()
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("BANK_TABS_CHANGED")
eventFrame:RegisterEvent("BANK_TAB_SETTINGS_UPDATED")
eventFrame:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        -- Detect portable warbank (AccountBanker = warband only, no character bank)
        _warbandOnly = C_PlayerInteractionManager
            and C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.AccountBanker)
            or false
        if _warbandOnly then
            local defaultOneBag = EllesmereUIDB and EllesmereUIDB.bagDefaultOneBag
            _selectedView = defaultOneBag and -3 or -2
        end
        -- Position
        EUI_Bank:ClearAllPoints()
        if EllesmereUIDB and EllesmereUIDB.bankPosition then
            local pos = EllesmereUIDB.bankPosition
            EUI_Bank:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        else
            EUI_Bank:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 15, -100)
        end
        -- Clear search on open
        if EUI_Bank._searchBox then
            EUI_Bank._searchBox:SetText("")
            EUI_Bank._searchBox:ClearFocus()
        end
        local bankScale = EllesmereUIDB and EllesmereUIDB.bagScale or 1
        EUI_Bank:SetScale(bankScale)
        EUI_Bank:Show()
        -- Auto-open bags alongside bank if not already visible
        if EUI_Bags and not EUI_Bags:IsVisible() then
            EUI_Bags:Show()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
            EUI_Bank._autoOpenedBags = true
        else
            EUI_Bank._autoOpenedBags = false
            -- Refresh bags so warbank dim overlay applies immediately
            if EUI_Bags and EUI_Bags:IsVisible() and EUI_Bags.RefreshInventory then
                EUI_Bags:RefreshInventory()
            end
        end
        -- Set initial size so frame is visible immediately
        local gridW = COLUMNS * (SLOT_SIZE + SPACING)
        EUI_Bank:SetWidth(GetBankSidebarWidth() + gridW + 10 * 2 + SCROLLBAR_HIT_W + 2)
        EUI_Bank:SetHeight(FIXED_H)
        -- Bank item data loads asynchronously after BANKFRAME_OPENED.
        -- Defer discovery + refresh to next frame via OnUpdate.
        if not EUI_Bank._openPoller then
            EUI_Bank._openPoller = CreateFrame("Frame")
        end
        EUI_Bank._openPoller:SetScript("OnUpdate", function(self)
            self:SetScript("OnUpdate", nil)
            if not EUI_Bank:IsVisible() then return end
            DiscoverBankTabs()
            EUI_Bank:RefreshBank()
            EUI_Bank:UpdateFooterGold()
            if EUI_Bags and EUI_Bags.CaptureWarbandGold then EUI_Bags.CaptureWarbandGold() end
        end)

    elseif event == "BANKFRAME_CLOSED" then
        _warbandOnly = false
        WipeTransferState()
        -- Clear search on close
        if EUI_Bank._searchBox then
            EUI_Bank._searchBox:SetText("")
            EUI_Bank._searchBox:ClearFocus()
        end
        EUI_Bank:Hide()
        -- Auto-close bags if we auto-opened them
        if EUI_Bank._autoOpenedBags and EUI_Bags and EUI_Bags:IsVisible() then
            EUI_Bags:Hide()
        end
        EUI_Bank._autoOpenedBags = false

    elseif event == "BANK_TABS_CHANGED" or event == "BANK_TAB_SETTINGS_UPDATED"
        or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" then
        if EUI_Bank:IsVisible() then
            local prevCount = #_allTabs
            DiscoverBankTabs()
            ScheduleBankRefresh()
            -- Server may not have slot data ready yet for a newly purchased tab.
            -- Poll until tab count changes or we give up after 5 seconds.
            if #_allTabs == prevCount then
                local attempts = 0
                local poller = CreateFrame("Frame")
                poller:SetScript("OnUpdate", function(self, elapsed)
                    attempts = attempts + 1
                    if attempts % 6 ~= 0 then return end -- ~0.1s per check
                    if not EUI_Bank:IsVisible() or attempts > 300 then
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    DiscoverBankTabs()
                    if #_allTabs ~= prevCount then
                        self:SetScript("OnUpdate", nil)
                        EUI_Bank:RefreshBank()
                    end
                end)
            end
        end

    elseif event == "BAG_UPDATE" or event == "PLAYERBANKSLOTS_CHANGED" then
        if EUI_Bank:IsVisible() then
            ScheduleBankRefresh()
        end

    elseif event == "PLAYER_MONEY" then
        if EUI_Bank:IsVisible() then
            EUI_Bank:UpdateFooterGold()
        end
    end
end)

-- Kill Blizzard bank frame: reparent to hidden frame only.
-- Do NOT call BankFrame:Hide() -- that fires BANKFRAME_CLOSED and kills
-- the bank interaction. Reparenting is invisible to the event system.
-- Do NOT use SetScript on BankFrame -- that taints it and breaks
-- PurchaseBankTab() and other secure bank operations.
do
    local hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()
    if BankFrame then
        BankFrame:SetParent(hiddenParent)
    end
end

-- Close bank when pressing Escape
EUI_Bank:SetScript("OnHide", function()
    if C_Bank then C_Bank.CloseBankFrame() end
    -- Clear warbank dim overlays on bags
    if _G.EUI_Bags and _G.EUI_Bags:IsVisible() and _G.EUI_Bags.RefreshInventory then
        _G.EUI_Bags:RefreshInventory()
    end
end)

-------------------------------------------------------------------------------
--  Loader (deferred init)
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    -- Apply default view based on setting
    if EllesmereUIDB and EllesmereUIDB.bagDefaultOneBag then
        _selectedView = -1
    end
    -- Register for Escape close
    if EUI and EUI.RegisterEscapeClose then
        EUI.RegisterEscapeClose(EUI_Bank)
    end
end)
