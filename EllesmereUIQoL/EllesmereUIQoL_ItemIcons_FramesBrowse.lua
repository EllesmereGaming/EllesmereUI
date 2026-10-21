if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_FramesBrowse.lua
--  Item Icons adapters for the load-on-demand browsing windows: auction house,
--  black market, Adventure Guide loot, Great Vault, profession crafting and
--  customer orders. Their items have no bag location (the auction house sell
--  slot aside), so the marks come from the item link alone. A frame's hooks
--  install once, the first time it is managed with its Blizzard addon loaded,
--  and stay inert while it is released. List rows paint as their ScrollBox
--  initializes them, so only visible rows do work. The adapter contract:
--  EllesmereUIQoL_ItemIcons.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons
local Paint, Clear, HideNative, IsManaged = II.Paint, II.Clear, II.HideNative, II.IsFrameEnabled
local GetItemInfo = C_Item.GetItemInfo

local ctx, facts = {}, {}   -- reused for every paint; the core reads them during Paint only
local OWNER = {}            -- owner of the ScrollBox callbacks

-- Registers frameKey's adapter. Install runs once, when the frame is first
-- managed and addon has loaded (at once, or when it loads); Repaint paints the
-- frame's shown buttons.
local function Adapter(frameKey, addon, Install, Repaint)
    local installed, waiting = false, false
    local function Ready()
        Install()
        installed = true
        if IsManaged(frameKey) then Repaint() end
    end
    II.RegisterFrame(frameKey, {
        Enable = function()
            if installed then
                Repaint()
            elseif not waiting then
                waiting = true
                EventUtil.ContinueOnAddOnLoaded(addon, Ready)
            end
        end,
        Refresh = function()
            if installed then Repaint() end
        end,
    })
end

-------------------------------------------------------------------------------
--  Auction house: results rows (browse, your auctions, your bids) and the
--  item displays of the buy, sell and auctions panels
-------------------------------------------------------------------------------
local AH = "auctionhouse"
local ahCells = setmetatable({}, { __mode = "k" })  -- item-name cells already hooked
local ahLists, ahDisplays                            -- set on install
local awaiting = {}                                  -- item IDs whose link is loading

-- An item key's link: Blizzard links one by its item ID
-- (AuctionHouseBrowseResultsFrameMixin:OnBrowseResultSelected). Until the item's
-- data has loaded there is none; the frame repaints when it arrives.
local function KeyLink(itemID)
    local _, link = GetItemInfo(itemID)
    if not link and not awaiting[itemID] then
        awaiting[itemID] = true
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            awaiting[itemID] = nil
            II.RequestRefresh(AH)
        end)
    end
    return link
end

-- Fills ctx for an item key; link is the auction's own link when it has one.
-- False for a battle pet (no item link) or while the key's data loads.
local function SetKeyCtx(itemKey, link)
    local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
    if not info or info.isPet then return false end
    if not link then
        link = KeyLink(itemKey.itemID)
        if not link then return false end
        -- The item ID's link lacks the auction's bonuses; the key has its item level
        if info.isEquipment and itemKey.itemLevel > 0 then
            wipe(facts)
            facts.itemLevel = itemKey.itemLevel
            ctx.facts = facts
        end
    end
    ctx.link, ctx.itemID, ctx.quality = link, itemKey.itemID, info.quality
    return true
end

-- A results row's item-name cell, the pooled unit that carries the 14 px icon.
-- A cell reused for a row whose data is not loaded yet is cleared. Blizzard dims
-- the icon of sold-out and sold auctions; the marks follow.
local function PaintCell(cell)
    if not IsManaged(AH) then return end
    local row = cell.rowData
    wipe(ctx)
    if not (row and row.itemKey and SetKeyCtx(row.itemKey, row.itemLink)) then
        Clear(cell)
        return
    end
    local icon = cell.Icon
    ctx.anchor, ctx.alpha = icon, icon:GetAlpha()
    Paint(cell, ctx, AH)
end

-- Hooks a row's item-name cells the first time they are seen; after that each
-- repaints from its own update (TryUpdateDisplay runs on populate and when the
-- key's data arrives)
local function SeeRow(row, repaint)
    local cells = row.cells
    if not cells then return end
    for i = 1, #cells do
        local cell = cells[i]
        if cell.TryUpdateDisplay and cell.Icon then
            if not ahCells[cell] then
                ahCells[cell] = true
                hooksecurefunc(cell, "TryUpdateDisplay", PaintCell)
                PaintCell(cell)
            elseif repaint then
                PaintCell(cell)
            end
        end
    end
end

local function DiscoverRow(row) SeeRow(row, false) end
local function RepaintRow(row) SeeRow(row, true) end

-- The item being bought, sold or reviewed. Sell slots hold a bag item.
local function PaintDisplay(display)
    if not IsManaged(AH) then return end
    local button = display.ItemButton
    local link = display:GetItemLink()
    local itemKey, location = display:GetItemSource()
    wipe(ctx)
    local ok = false
    if link and not display:IsPet() then
        if itemKey then
            ok = SetKeyCtx(itemKey)
        else
            ctx.link, ok = link, true
            if location and location:IsBagAndSlot() then
                ctx.bag, ctx.slot = location:GetBagAndSlot()
            end
        end
    end
    if not ok then
        Clear(button)
        return
    end
    ctx.count = display:GetItemCount()
    Paint(button, ctx, AH)
    HideNative(button.Count, AH)
    HideNative(button.ProfessionQualityOverlay, AH)
end

local function InstallAH()
    local f = AuctionHouseFrame
    local auctions = f.AuctionsFrame
    ahLists = { f.BrowseResultsFrame.ItemList.ScrollBox, auctions.AllAuctionsList.ScrollBox, auctions.BidsList.ScrollBox }
    -- New cells join the pools as rows initialize; the range event follows them
    for i = 1, #ahLists do
        local scrollBox = ahLists[i]
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, function()
            if IsManaged(AH) then scrollBox:ForEachFrame(DiscoverRow) end
        end, OWNER)
    end
    -- Every item change ends in SetItemInternal (AuctionHouseItemDisplayMixin)
    ahDisplays = {
        f.ItemBuyFrame.ItemDisplay, f.CommoditiesBuyFrame.BuyDisplay.ItemDisplay,
        f.ItemSellFrame.ItemDisplay, f.CommoditiesSellFrame.ItemDisplay, auctions.ItemDisplay,
    }
    for i = 1, #ahDisplays do
        local display = ahDisplays[i]
        hooksecurefunc(display, "SetItemInternal", PaintDisplay)
        display:HookScript("OnShow", PaintDisplay)
    end
end

local function RepaintAH()
    for i = 1, #ahLists do
        local scrollBox = ahLists[i]
        if scrollBox:IsVisible() and scrollBox:GetView() then scrollBox:ForEachFrame(RepaintRow) end
    end
    for i = 1, #ahDisplays do
        local display = ahDisplays[i]
        if display:IsVisible() then PaintDisplay(display) end
    end
end

Adapter(AH, "Blizzard_AuctionHouseUI", InstallAH, RepaintAH)

-------------------------------------------------------------------------------
--  Black market: list rows and the hot deal
-------------------------------------------------------------------------------
local BM = "blackmarket"

local function PaintMarketItem(button, link, quantity, quality)
    wipe(ctx)
    if not link then
        Clear(button)
        return
    end
    ctx.link, ctx.count, ctx.quality = link, quantity, quality
    Paint(button, ctx, BM)
    HideNative(button.Count, BM)
    HideNative(button.ProfessionQualityOverlay, BM)
end

-- The returns BlackMarketItemMixin:Init reads
local function PaintMarketRow(row, elementData)
    local _, _, quantity, _, _, _, _, _, _, _, _, _, _, _, link, _, quality =
        C_BlackMarket.GetItemInfoByIndex(elementData.index)
    PaintMarketItem(row.Item, link, quantity, quality)
end

-- BlackMarketFrame_UpdateHotItem shows the hot deal only when there is one
local function PaintHotDeal()
    local name, _, quantity, _, _, _, _, _, _, _, _, _, _, _, link, _, quality = C_BlackMarket.GetHotItem()
    local button = BlackMarketFrame.HotDeal.Item
    if name then
        PaintMarketItem(button, link, quantity, quality)
    else
        Clear(button)
    end
end

local function InstallBM()
    local scrollBox = BlackMarketFrame.ScrollBox
    ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row, elementData)
        if IsManaged(BM) then PaintMarketRow(row, elementData) end
    end, OWNER)
    ScrollUtil.AddReleasedFrameCallback(scrollBox, function(_, row)
        if IsManaged(BM) then Clear(row.Item) end
    end, OWNER)
    hooksecurefunc("BlackMarketFrame_UpdateHotItem", function()
        if IsManaged(BM) then PaintHotDeal() end
    end)
end

-- Showing the window requests the items again and rebuilds the rows
-- (BlackMarketFrame_OnShow)
local function RepaintBM()
    local f = BlackMarketFrame
    if not f:IsVisible() then return end
    f.ScrollBox:ForEachFrame(PaintMarketRow)
    if f.HotDeal:IsShown() then PaintHotDeal() end
end

Adapter(BM, "Blizzard_BlackMarketUI", InstallBM, RepaintBM)

-------------------------------------------------------------------------------
--  Adventure Guide: the encounter loot list
-------------------------------------------------------------------------------
local EJ = "encounterjournal"
local lootRows = setmetatable({}, { __mode = "k" })  -- loot rows already hooked

-- A loot row is the item button; its 42 px icon sits at the left
local function PaintLootRow(row, elementData)
    if not IsManaged(EJ) then return end
    local info = C_EncounterJournal.GetLootInfoByIndex(elementData.index)
    local link = info and info.link
    wipe(ctx)
    if not link then
        Clear(row)
        return
    end
    ctx.link, ctx.itemID, ctx.anchor = link, info.itemID, row.icon
    Paint(row, ctx, EJ)
    HideNative(row.ProfessionQualityOverlay, EJ)
end

-- Init runs from the list's initializer and again when an item's data arrives
-- (EncounterJournal_LootCallback); headers are divider rows without an item
local function HookLootRow(row, elementData)
    if elementData.header or lootRows[row] then return end
    lootRows[row] = true
    hooksecurefunc(row, "Init", PaintLootRow)
end

local function SeeLootRow(row, elementData)
    if elementData.header then return end
    HookLootRow(row, elementData)
    PaintLootRow(row, elementData)
end

local function LootScrollBox()
    return EncounterJournal.encounter.info.LootContainer.ScrollBox
end

-- The list keeps its rows while hidden: a frame managed meanwhile paints on show
local function RepaintEJ()
    local scrollBox = LootScrollBox()
    if scrollBox:IsVisible() then scrollBox:ForEachFrame(SeeLootRow) end
end

local function InstallEJ()
    local scrollBox = LootScrollBox()
    ScrollUtil.AddAcquiredFrameCallback(scrollBox, function(_, row, elementData)
        if IsManaged(EJ) then HookLootRow(row, elementData) end
    end, OWNER)
    ScrollUtil.AddReleasedFrameCallback(scrollBox, function(_, row)
        if IsManaged(EJ) then Clear(row) end
    end, OWNER)
    scrollBox:HookScript("OnShow", function()
        if IsManaged(EJ) then RepaintEJ() end
    end)
end

Adapter(EJ, "Blizzard_EncounterJournal", InstallEJ, RepaintEJ)

-------------------------------------------------------------------------------
--  Great Vault: each activity's reward and the claim confirmation
-------------------------------------------------------------------------------
local GV = "greatvault"
local vaultConfirm   -- the confirmation frame, once hooked

-- An activity's reward frame; its 37 px icon sits at the left
local function PaintVaultItem(itemFrame)
    if not IsManaged(GV) then return end
    local dbid = itemFrame:GetParent():GetDisplayedItemDBID()
    local link = dbid and C_WeeklyRewards.GetItemHyperlink(dbid)
    wipe(ctx)
    if not link then
        Clear(itemFrame)
        return
    end
    ctx.link, ctx.anchor = link, itemFrame.Icon
    Paint(itemFrame, ctx, GV)
    HideNative(itemFrame.ProfessionQualityOverlay, GV)
end

-- The reward chosen in the confirmation popup (WeeklyRewardConfirmSelectionMixin)
local function PaintVaultConfirm(confirm)
    if not IsManaged(GV) then return end
    local button = confirm.ItemFrame
    local dbid = confirm.itemDBID
    local link = dbid and C_WeeklyRewards.GetItemHyperlink(dbid)
    wipe(ctx)
    if not link then
        Clear(button)
        return
    end
    ctx.link, ctx.anchor, ctx.count = link, button.Icon, GetItemButtonCount(button)
    Paint(button, ctx, GV)
    HideNative(button.Count, GV)
    HideNative(button.ProfessionQualityOverlay, GV)
end

-- The popup is built by the first SelectReward; true when newly hooked
local function HookVaultConfirm(confirm)
    if vaultConfirm or not confirm then return false end
    vaultConfirm = confirm
    hooksecurefunc(confirm, "RefreshRewards", PaintVaultConfirm)
    return true
end

local function InstallVault()
    local f = WeeklyRewardsFrame
    -- SetDisplayedItem runs once the rewards' item data has loaded
    for _, activity in ipairs(f.Activities) do
        local itemFrame = activity.ItemFrame
        if itemFrame then hooksecurefunc(itemFrame, "SetDisplayedItem", PaintVaultItem) end
    end
    hooksecurefunc(f, "SelectReward", function(self)
        local confirm = self.confirmSelectionFrame
        if IsManaged(GV) and HookVaultConfirm(confirm) then PaintVaultConfirm(confirm) end
    end)
end

-- Showing the window refreshes every activity (WeeklyRewardsMixin:OnShow)
local function RepaintVault()
    local f = WeeklyRewardsFrame
    if not f:IsVisible() then return end
    for _, activity in ipairs(f.Activities) do
        local itemFrame = activity.ItemFrame
        if itemFrame and itemFrame:IsVisible() then PaintVaultItem(itemFrame) end
    end
    local confirm = f.confirmSelectionFrame
    if confirm then
        HookVaultConfirm(confirm)
        if confirm:IsVisible() then PaintVaultConfirm(confirm) end
    end
end

Adapter(GV, "Blizzard_WeeklyRewards", InstallVault, RepaintVault)

-------------------------------------------------------------------------------
--  Profession crafting and customer orders: recipe output icons and reagent
--  slots. Both windows build them from Blizzard_ProfessionsTemplates, so one
--  set of hooks serves both; a button's window picks its frame key.
-------------------------------------------------------------------------------
local PROF, ORDERS = "professions", "customerorders"
local windows = {}                                     -- window -> frame key
local outputs = setmetatable({}, { __mode = "k" })     -- output icon -> its item link, ID or false
local slots = setmetatable({}, { __mode = "k" })       -- reagent slots already hooked
local templatesHooked = false

local function WindowKey(region)
    local f = region:GetParent()
    while f do
        local key = windows[f]
        if key then return key end
        f = f:GetParent()
    end
end

-- The frame key of region's window while that window is managed
local function ManagedKey(region)
    if not (IsManaged(PROF) or IsManaged(ORDERS)) then return end
    local key = WindowKey(region)
    if key and IsManaged(key) then return key end
end

-- The item a craft or an order makes. Its count is the craft's yield range,
-- not a stack, so it stays Blizzard's.
local function PaintOutput(icon)
    local key = ManagedKey(icon)
    if not key then return end
    local link = outputs[icon]
    if type(link) == "number" then
        local _
        _, link = GetItemInfo(link)
    end
    wipe(ctx)
    if type(link) ~= "string" then
        Clear(icon)
        return
    end
    ctx.link = link
    Paint(icon, ctx, key)
    HideNative(icon.ProfessionQualityOverlay, key)
end

-- A slot's item link, or nil while it is empty, loading or holds a currency. A
-- quality slot stands for every quality of its reagent; Blizzard's own overlay
-- shows what is allocated (ProfessionsReagentSlotMixin:UpdateQualityOverlay).
local function SlotLink(slot)
    if slot:IsLoading() then return end
    if slot.GetReagentSlotSchematic then
        local reagent = slot:GetReagent()
        if not (reagent and reagent.itemID) then return end
        local mode = Professions.GetReagentInputMode(slot:GetReagentSlotSchematic())
        if mode == Professions.ReagentInputMode.Quality then return end
    end
    return slot.Button:GetItemLink()
end

-- Reagent, salvage and enchant slots; Update ends every change of their item
local function PaintSlot(slot)
    local key = ManagedKey(slot)
    if not key then return end
    local button = slot.Button
    local link = SlotLink(slot)
    wipe(ctx)
    if not link then
        Clear(button)
        return
    end
    ctx.link, ctx.count = link, button:GetItemButtonCount()
    Paint(button, ctx, key)
    HideNative(button.Count, key)
    HideNative(button.ProfessionQualityOverlay, key)
end

local function HookTemplates()
    if templatesHooked then return end
    templatesHooked = true
    -- Professions.SetupOutputIcon and the crafter's fulfillment icon end here
    hooksecurefunc(Professions, "SetupOutputIconCommon", function(icon, _, _, _, item)
        outputs[icon] = item or false
        PaintOutput(icon)
    end)
    -- Every slot type's Init calls the base Init through the mixin table
    hooksecurefunc(ProfessionsRecipeSlotBaseMixin, "Init", function(slot)
        if slots[slot] then return end
        slots[slot] = true
        hooksecurefunc(slot, "Update", PaintSlot)
    end)
end

local function Repainter(frameKey)
    return function()
        for icon in pairs(outputs) do
            if icon:IsVisible() and WindowKey(icon) == frameKey then PaintOutput(icon) end
        end
        for slot in pairs(slots) do
            if slot:IsVisible() and WindowKey(slot) == frameKey then PaintSlot(slot) end
        end
    end
end

Adapter(PROF, "Blizzard_Professions", function()
    windows[ProfessionsFrame] = PROF
    HookTemplates()
end, Repainter(PROF))

Adapter(ORDERS, "Blizzard_ProfessionsCustomerOrders", function()
    windows[ProfessionsCustomerOrdersFrame] = ORDERS
    HookTemplates()
end, Repainter(ORDERS))
