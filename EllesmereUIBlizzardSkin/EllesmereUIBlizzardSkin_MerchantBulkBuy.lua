if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_MerchantBulkBuy.lua
--  Merchant Bulk Buy (opt-in, EllesmereUIDB.merchantBulkBuy): a shift-click on
--  a vendor item opens a quantity window (EllesmereUI.CreateQuantityDialog) in
--  place of Blizzard's split popup (an item sold one at a time, which gets no
--  popup, opens it from the click alone) and buys any amount, one purchase of
--  at most GetMerchantItemMaxStack at a time, the next sent once the bags show
--  the last.
--  The hooks install on the first enable and return at once while off; events
--  are registered only while the window or a purchase confirm is up or a run
--  is going. A purchase paid in a limited currency keeps Blizzard's popup and
--  its own prompt, and so does everything under WoW Forever's Gamepad
--  interface style (EllesmereUI.StackSplitFor).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local WSkin = ns.WSkin
if not WSkin then return end

local EUI = EllesmereUI
local Theme = WSkin.Theme
local floor, min, max = math.floor, math.min, math.max
local band = bit.band
local MAX_COSTS = MAX_ITEM_COST or 3

local BAGS = { BACKPACK_CONTAINER }
for bag = 1, NUM_BAG_SLOTS do BAGS[#BAGS + 1] = bag end
local REAGENT_BAG = Enum.BagIndex and Enum.BagIndex.ReagentBag
if REAGENT_BAG then BAGS[#BAGS + 1] = REAGENT_BAG end

local events = CreateFrame("Frame")
local dialog, job, hooked
local confirm          -- the open purchase confirm's handle (EUI:ShowConfirmPopup)
local costParts = {}   -- CostText's pieces, reused

local function Enabled()
    return EllesmereUIDB and EllesmereUIDB.merchantBulkBuy == true
end

-- Free room for the item in the bags it may go into: empty slots in bags of
-- its family (a quiver takes only arrows, a soul bag only shards), the reagent
-- bag for reagents, and what its own partial stacks still hold.
local function BagRoom(itemID, stackSize)
    local family = C_Item.GetItemFamily(itemID) or 0
    local isReagent = select(17, C_Item.GetItemInfo(itemID))
    local room = 0
    for _, bag in ipairs(BAGS) do
        local fits
        if bag == REAGENT_BAG then
            fits = isReagent
        else
            local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
            fits = not bagFamily or bagFamily == 0 or band(bagFamily, family) ~= 0
        end
        if fits then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local id = C_Container.GetContainerItemID(bag, slot)
                if not id then
                    room = room + stackSize
                elseif id == itemID then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    room = room + max(stackSize - (info and info.stackCount or stackSize), 0)
                end
            end
        end
    end
    return room
end

-- The most whole purchases the bags, the stock, the gold and every item or
-- currency cost allow.
local function MaxBundles(index, info, itemID, step, stackSize)
    local n = floor(min(BagRoom(itemID, stackSize), 999999) / step)
    if info.numAvailable >= 0 then n = min(n, info.numAvailable) end
    if info.price > 0 then n = min(n, floor(GetMoney() / info.price)) end
    for i = 1, MAX_COSTS do
        local _, value, link, currencyName = GetMerchantItemCostItem(index, i)
        if link and value and value > 0 then
            local have
            if currencyName then
                local c = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
                have = c and c.quantity
            else
                have = C_Item.GetItemCount(link, false, false, true)
            end
            if have then n = min(n, floor(have / value)) end
        end
    end
    return max(n, 0)
end

local function CostText(index, info, bundles)
    local parts = costParts
    wipe(parts)
    if info.price > 0 then
        parts[#parts + 1] = C_CurrencyInfo.GetCoinTextureString(info.price * bundles)
    end
    for i = 1, MAX_COSTS do
        local texture, value = GetMerchantItemCostItem(index, i)
        if texture and value and value > 0 then
            parts[#parts + 1] = (value * bundles) .. " |T" .. texture .. ":0|t"
        end
    end
    return table.concat(parts, "  ")
end

-- A purchase paid in a limited currency: Blizzard confirms it with its own
-- prompt, which says when it is the last one you can make.
local function LimitedCurrencyCost(index)
    if (GetMerchantItemCostInfo(index) or 0) ~= 1 then return false end
    local _, _, link = GetMerchantItemCostItem(index, 1)
    local limited = C_Item.GetLimitedCurrencyItemInfo
    return link ~= nil and limited ~= nil and limited(link) ~= nil
end

local function SyncEvents()
    if job or confirm or (dialog and dialog:IsShown()) then
        events:RegisterEvent("MERCHANT_CLOSED")
    else
        events:UnregisterEvent("MERCHANT_CLOSED")
    end
    if job then
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("UI_ERROR_MESSAGE")
    else
        events:UnregisterEvent("BAG_UPDATE_DELAYED")
        events:UnregisterEvent("UI_ERROR_MESSAGE")
    end
end

-- Ends the run. One that ends short (a red error, full bags, the merchant
-- closed, a new order) says how far it got.
local function StopJob()
    local j = job
    job = nil
    SyncEvents()
    if not j then return end
    local got = C_Item.GetItemCount(j.itemID) - j.base
    if got < j.target then
        EUI.Print(EllesmereUI.Lf("Bulk Buy stopped after %1$d of %2$d.", max(got, 0), j.target))
    end
end

-- Sends the next purchase once the bags show the last one; stops on a drop
-- in the count, at the target, or when the merchant no longer sells the item.
local function StepJob()
    local j = job
    if not j then return end
    local count = C_Item.GetItemCount(j.itemID)
    if count < j.last then StopJob(); return end
    j.last = count
    local got = count - j.base
    if got < j.issued then return end
    local n = floor(min(j.chunk, j.target - got) / j.step) * j.step
    if n <= 0 or GetMerchantItemID(j.index) ~= j.itemID then StopJob(); return end
    j.issued = got + n
    BuyMerchantItem(j.index, n)
end

-- One order at a time: a new one ends the run still going (and says so).
local function StartJob(index, itemID, qty, step, chunk)
    if job then StopJob() end
    if GetMerchantItemID(index) ~= itemID then return end
    local count = C_Item.GetItemCount(itemID)
    job = { index = index, itemID = itemID, target = qty, step = step, chunk = chunk,
            base = count, last = count, issued = 0 }
    SyncEvents()
    StepJob()
end

-- The window's onChange: the total for the amount, Buy only with one to buy.
local function ShowCost(qty)
    local d = dialog
    d._extra:SetText(EllesmereUI.Lf("Total: %s", CostText(d._index, d._info, qty / d._step)))
    local buy = d._buttons.buy
    buy:SetEnabled(qty > 0)
    buy:SetAlpha(qty > 0 and 1 or 0.3)
end

-- Re-reads the item after a merchant repaint (paging, the Buyback tab, stock
-- or money changes) and closes the window once its button moved on.
local function Refresh()
    local d = dialog
    local index, owner = d._index, d._owner
    local info = (MerchantFrame.selectedTab or 1) == 1 and C_MerchantFrame.GetItemInfo(index)
    if not info or GetMerchantItemID(index) ~= d._itemID or not owner:IsVisible() or owner:GetID() ~= index then
        d:Hide()
        return
    end
    d._info = info
    local step = max(info.stackCount, 1)
    d:SetRange(step, MaxBundles(index, info, d._itemID, step, d._stackSize) * step, d._chunk)
    if d._eb:HasFocus() and d._eb:GetNumber() <= d._max then
        ShowCost(d:Current())
    else
        d:SetValue(d:Current())
    end
end

local function DoBuy()
    local d = dialog
    local qty = d:Current()
    local index, itemID, step, chunk, info = d._index, d._itemID, d._step, d._chunk, d._info
    d:Hide()
    if qty < step then return end
    local bundles = qty / step
    local function start()
        confirm = nil
        StartJob(index, itemID, qty, step, chunk)
    end
    if info.hasExtendedCost or info.price * bundles >= (MERCHANT_HIGH_PRICE_COST or 1500000) then
        local msg = EllesmereUI.Lf("Buy %1$d x %2$s for %3$s?", qty,
            GetMerchantItemLink(index) or info.name or "", CostText(index, info, bundles))
        if not C_MerchantFrame.IsMerchantItemRefundable(index) then
            msg = msg .. "\n\n" .. EllesmereUI.L("This purchase is not refundable.")
        end
        confirm = EUI:ShowConfirmPopup({
            title       = "Bulk Buy",
            message     = msg,
            confirmText = "Buy",
            cancelText  = "Cancel",
            onConfirm   = start,
            onCancel    = function() confirm = nil; SyncEvents() end,
        })
        SyncEvents()
    else
        start()
    end
end

-- Enter and Buy: a typed amount that is not a whole number of purchases first
-- snaps to one, so the box shows what is bought.
local function BuyOrSnap()
    local q = dialog:Current()
    if q ~= dialog._eb:GetNumber() then dialog:SetValue(q) return end
    DoBuy()
end

-- +1 Stack: up to the next full stack, at least one more purchase.
local function AddStack()
    local d = dialog
    local cur = d:Current()
    local n = (floor(cur / d._stackSize) + 1) * d._stackSize
    if floor(n / d._step) * d._step <= cur then n = cur + d._step end
    d:SetValue(n)
end

-- Blizzard Skins+' look on the shared quantity window: the theme's surface,
-- border, close button and edit box, popup buttons in the theme's font.
local SKIN = {
    frame = function(d)
        WSkin.SolidTex(d, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, 1):SetAllPoints()
        WSkin.AddBorder(d)
    end,
    font = function(fs, size) WSkin.Font(fs, nil, nil, nil, size) end,
    button = function(parent, w, h, label)
        local b = EUI.MakePopupButton(parent, "CENTER", parent, "CENTER", 0, 0,
            1, 1, 1, 0.7, 1, 1, 1, 0.9, 1, 1, 1, 0.5, 1, 1, 1, 0.6)
        b:SetSize(w, h)
        b:ClearAllPoints()
        WSkin.Font(b._lbl, nil, nil, nil, 12)
        b._lbl:SetText(label)
        return b
    end,
    editBox = function(eb)
        eb:SetFont(Theme.fontPath, 12, Theme.fontFlag or "")
        WSkin.EditBox(eb)
    end,
    close = function(close)
        close:SetSize(18, 18)
        close:SetPoint("TOPRIGHT", close:GetParent(), "TOPRIGHT", -4, -5)
        WSkin.CloseButton(close)
    end,
}

local function CreateDialog()
    if not Theme.fontPath then WSkin.ResolveTheme() end
    return EUI.CreateQuantityDialog({
        name = "EUI_MerchantBulkBuyFrame", width = 232, height = 121,
        title = EllesmereUI.L("Bulk Buy"), editWidth = 64, maxLetters = 6,
        extraLine = true, skin = SKIN,
        onChange = ShowCost, onEnter = BuyOrSnap,
        onShow = SyncEvents, onHide = SyncEvents,
        buttons = {
            { key = "stack", label = EllesmereUI.L("+1 Stack"), width = 66, height = 27,
              point = "BOTTOMLEFT", onClick = AddStack },
            { key = "max", label = EllesmereUI.L("Max"), width = 66, height = 27,
              point = "BOTTOM", onClick = function() dialog:SetValue(dialog._max) end },
            { key = "buy", label = EllesmereUI.L("Buy"), width = 66, height = 27,
              point = "BOTTOMRIGHT", onClick = BuyOrSnap, primary = true },
        },
    })
end

local function Validate()
    if dialog and dialog:IsShown() then Refresh() end
end
-- Merchant repaints come in bursts: one refresh per frame while the window shows.
local refreshSoon = WSkin.Debounce(Validate)

-- A shift-click on an item sold one at a time, unless it went into a focused
-- edit box (not the window's own) as a link.
local function SingleBuyClick(index)
    local focus = GetCurrentKeyBoardFocus()
    return (MerchantFrame.selectedTab or 1) == 1 and IsModifiedClick("SPLITSTACK")
        and GetMerchantItemMaxStack(index) == 1
        and (not focus or (dialog ~= nil and focus == dialog._eb))
        and not EUI.PadGamepadUI()
end

local function TakeOver(button)
    if not Enabled() then return end
    local index = button:GetID()
    local split = EUI.StackSplitFor(button)
    if not split and not (index and SingleBuyClick(index)) then return end
    local itemID = index and GetMerchantItemID(index)
    local info = itemID and C_MerchantFrame.GetItemInfo(index)
    if not info or info.currencyID or LimitedCurrencyCost(index) then return end
    if split then EUI.TakeStackSplit() end
    dialog = dialog or CreateDialog()
    local step = max(info.stackCount, 1)
    dialog._owner, dialog._index, dialog._itemID = button, index, itemID
    local maxStack = GetMerchantItemMaxStack(index)
    dialog._chunk = max(floor((maxStack or step) / step) * step, step)
    -- An item not loaded yet reads no stack size: one purchase's cap stands in.
    dialog._stackSize = max(C_Item.GetItemMaxStackSizeByID(itemID) or maxStack or step, 1)
    dialog._eb:SetText(tostring(step))
    -- Buy wears the accent, read on every open (it can change at any time).
    local b = dialog._buttons
    local EG = EUI.ELLESMERE_GREEN
    b.buy._setColors(EG.r, EG.g, EG.b, 0.9, EG.r, EG.g, EG.b, 1, EG.r, EG.g, EG.b, 0.9, EG.r, EG.g, EG.b, 1)
    b.buy._resetAnim()
    b.max._resetAnim()
    b.stack._resetAnim()
    dialog:Open(button)
    Refresh()
    if dialog:IsShown() then dialog:FocusInput() end
end

local function Install()
    if hooked then return end
    hooked = true
    if type(MerchantItemButton_OnModifiedClick) == "function" then
        hooksecurefunc("MerchantItemButton_OnModifiedClick", TakeOver)
    end
    if type(MerchantFrame_Update) == "function" then
        hooksecurefunc("MerchantFrame_Update", function()
            if dialog and dialog:IsShown() then refreshSoon() end
        end)
    end
end

EllesmereUI._Merchant_RefreshBulkBuy = function()
    if Enabled() then
        Install()
        return
    end
    if confirm then EUI:CloseConfirmPopup(confirm); confirm = nil end
    if dialog then dialog:Hide() end
    StopJob()
end

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        if Enabled() then Install() end
    elseif event == "BAG_UPDATE_DELAYED" then
        StepJob()
    elseif event == "MERCHANT_CLOSED" then
        if confirm then EUI:CloseConfirmPopup(confirm); confirm = nil end
        if dialog then dialog:Hide() end
        StopJob()
    else
        -- UI_ERROR_MESSAGE: any red error during a run ends it, so a purchase
        -- the server refused (full bags, too little money) never stalls it.
        StopJob()
    end
end)
events:RegisterEvent("ADDON_LOADED")
