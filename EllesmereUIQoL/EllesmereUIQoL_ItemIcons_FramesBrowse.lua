if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_FramesBrowse.lua
--  Item Icons adapters for the load-on-demand browsing windows: auction house,
--  black market, Adventure Guide loot, Great Vault, profession crafting and
--  customer orders. Most of their items have no bag location, so the marks
--  come from the item link; the bag items (the auction house sell slot,
--  crafting slots and choices) pass their location too. A frame's hooks
--  install once, the first time it is managed with its Blizzard addon loaded
--  (II.RegisterLazyFrame), and stay inert while it is released. List rows
--  paint as their ScrollBox initializes them, so only visible rows do work.
--  The adapter contract: EllesmereUIQoL_ItemIcons.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons
local Paint, Clear, HideNative, IsManaged = II.Paint, II.Clear, II.HideNative, II.IsFrameEnabled
local GetItemInfo = C_Item.GetItemInfo

local ctx, facts = {}, {}   -- reused for every paint; the core reads them during Paint only
local OWNER = {}            -- owner of the ScrollBox callbacks

-------------------------------------------------------------------------------
--  Auction house: results rows (browse, your auctions, your bids) and the
--  item displays of the buy, sell and auctions panels
-------------------------------------------------------------------------------
local AH = "auctionhouse"
local BUTTON_SIZE = 37                               -- the item button the mark sizes are set for
local ahCells = setmetatable({}, { __mode = "k" })  -- item-name cells already hooked
local ahLists, ahDisplays                            -- set on install

-- An item key's link: Blizzard links one by its item ID
-- (AuctionHouseBrowseResultsFrameMixin:OnBrowseResultSelected). Until the item's
-- data has loaded there is none; the frame repaints when it arrives.
local function KeyLink(itemID)
    local _, link = GetItemInfo(itemID)
    if not link then II.WaitForItem(itemID, AH) end
    return link
end

-- The source an appearance link names: transmogappearance:<sourceID>
-- (WardrobeCollectionFrameMixin:OpenTransmogLink)
local function AppearanceSource(appearanceLink)
    if type(appearanceLink) == "string" then
        return tonumber(appearanceLink:match("transmogappearance:(%d+)"))
    end
end

-- Fills ctx for an item key. link: the auction's own link when it has one;
-- appearanceLink: its browse result's. False for a battle pet (no item link)
-- or while the key's data loads.
local function SetKeyCtx(itemKey, link, appearanceLink)
    local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
    if not info or info.isPet then return false end
    if not link then
        link = KeyLink(itemKey.itemID)
        if not link then return false end
        -- The item ID's link lacks the auction's bonuses: the key has its item
        -- level, the appearance link its look (none: no transmog mark)
        if info.isEquipment then
            wipe(facts)
            if itemKey.itemLevel > 0 then facts.itemLevel = itemKey.itemLevel end
            facts.transmogSourceID = AppearanceSource(appearanceLink) or AppearanceSource(info.appearanceLink)
                or false
            ctx.facts = facts
        end
    end
    ctx.link, ctx.itemID, ctx.quality = link, itemKey.itemID, info.quality
    return true
end

-- A results row's item-name cell, the pooled unit that carries the 14 px icon:
-- the marks shrink to it. A cell reused for a row whose data is not loaded yet
-- is cleared. Blizzard dims the icon of sold-out and sold auctions; the marks
-- follow.
local function PaintCell(cell)
    if not IsManaged(AH) then return end
    local row = cell.rowData
    wipe(ctx)
    if not (row and row.itemKey and SetKeyCtx(row.itemKey, row.itemLink, row.appearanceLink)) then
        Clear(cell)
        return
    end
    local icon = cell.Icon
    ctx.anchor, ctx.alpha, ctx.scale = icon, icon:GetAlpha(), icon:GetHeight() / BUTTON_SIZE
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

II.RegisterLazyFrame(AH, "Blizzard_AuctionHouseUI", InstallAH, RepaintAH)

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

II.RegisterLazyFrame(BM, "Blizzard_BlackMarketUI", InstallBM, RepaintBM)

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
    scrollBox:HookScript("OnShow", function()
        if IsManaged(EJ) then RepaintEJ() end
    end)
end

II.RegisterLazyFrame(EJ, "Blizzard_EncounterJournal", InstallEJ, RepaintEJ)

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

II.RegisterLazyFrame(GV, "Blizzard_WeeklyRewards", InstallVault, RepaintVault)

-------------------------------------------------------------------------------
--  Profession crafting and customer orders: recipe outputs, reagent, salvage,
--  enchant and recraft slots, the item flyout and the crafting output log.
--  Both windows build them from Blizzard_ProfessionsTemplates, so one set of
--  hooks serves both; a button's window picks its frame key. Starting on an
--  open window reads every shown button from Blizzard's own state.
-------------------------------------------------------------------------------
local PROF, ORDERS = "professions", "customerorders"
local windows = {}                                     -- window -> frame key
local slots = setmetatable({}, { __mode = "k" })       -- reagent, salvage and enchant slots already hooked
local recrafts = setmetatable({}, { __mode = "k" })    -- recraft slots already hooked
local flyouts = setmetatable({}, { __mode = "k" })     -- item flyouts already hooked
local orderView                                        -- the crafter's order view; nil on WoW Forever
local templatesHooked = false

local function AnyManaged()
    return IsManaged(PROF) or IsManaged(ORDERS)
end

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
    if not AnyManaged() then return end
    local key = WindowKey(region)
    if key and IsManaged(key) then return key end
end

-- Fills ctx from an Item (ItemMixin): a bag item by its GUID, with its location;
-- else by its own link. False when it has none.
local function SetItemCtx(item)
    local guid = item:GetItemGUID()
    if guid then
        if issecretvalue(guid) then return false end
        local link = C_Item.GetItemLinkByGUID(guid)
        if not link then return false end
        ctx.link = link
        local location = C_Item.GetItemLocation(guid)
        if location and location:IsBagAndSlot() then
            ctx.bag, ctx.slot = location:GetBagAndSlot()
        else
            ctx.location = location
        end
        return true
    end
    local link = item:GetItemLink()
    if not link then return false end
    ctx.link = link
    return true
end

-- The item a craft or an order makes. Its count is the craft's yield range,
-- not a stack, so it stays Blizzard's.
local function PaintOutput(icon, link)
    local key = ManagedKey(icon)
    if not key then return end
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

-- Paints an item button from ctx; Count shows the stack (count, else the
-- button's own), which an element replaces
local function PaintItemButton(button, key, count)
    ctx.count = count or button:GetItemButtonCount()
    Paint(button, ctx, key)
    HideNative(button.Count, key)
    HideNative(button.ProfessionQualityOverlay, key)
end

-- A slot's item into ctx; false while it is empty, loading or holds a
-- currency. A quality slot stands for every quality of its reagent: Blizzard's
-- own overlay shows what is allocated (ProfessionsReagentSlotMixin:
-- UpdateQualityOverlay). Salvage and enchant slots show their bag item by item
-- ID only (ProfessionsSalvageSlotMixin:SetItem); its GUID tells the real one.
local function SetSlotCtx(slot)
    if slot:IsLoading() then return false end
    if slot.GetReagentSlotSchematic then
        local reagent = slot:GetReagent()
        if not (reagent and reagent.itemID) then return false end
        local mode = Professions.GetReagentInputMode(slot:GetReagentSlotSchematic())
        if mode == Professions.ReagentInputMode.Quality then return false end
        ctx.link = slot.Button:GetItemLink()
        return ctx.link ~= nil
    end
    local item = slot.allocationItem
    return item ~= nil and SetItemCtx(item)
end

-- Update ends every change of a slot's item
local function PaintSlot(slot)
    local key = ManagedKey(slot)
    if not key then return end
    local button = slot.Button
    wipe(ctx)
    if SetSlotCtx(slot) then
        PaintItemButton(button, key)
    else
        Clear(button)
    end
end

local function HookSlot(slot)
    if slots[slot] then return end
    slots[slot] = true
    hooksecurefunc(slot, "Update", PaintSlot)
end

-- A recraft slot's input, or a finished order's crafted output. Known by link
-- alone (a crafting order's), the item may be bound.
local function PaintRecraft(button, item)
    local key = ManagedKey(button)
    if not key then return end
    wipe(ctx)
    if not (item and SetItemCtx(item)) then
        Clear(button)
        return
    end
    if not (ctx.bag or ctx.location) then
        wipe(facts)
        facts.isBound = true
        ctx.facts = facts
    end
    Paint(button, ctx, key)
    HideNative(button.ProfessionQualityOverlay, key)
end

-- crafted: the output slot holds the real crafted item (a finished order,
-- ProfessionsCrafterOrderViewMixin:SetOrder)
local function HookRecraft(recraftSlot, crafted)
    if recrafts[recraftSlot] then return end
    recrafts[recraftSlot] = true
    hooksecurefunc(recraftSlot.InputSlot, "Init", PaintRecraft)
    -- Elsewhere the output shows the input item under Blizzard's predicted quality
    -- pip (SetItemCraftingQualityOverlayOverride): it stays Blizzard's
    if crafted then hooksecurefunc(recraftSlot.OutputSlot, "Init", PaintRecraft) end
end

-- A flyout choice: an owned item by its GUID, else by item ID
local function PaintFlyoutButton(button, elementData)
    local key = ManagedKey(button)
    if not key then return end
    local item = elementData.item
    wipe(ctx)
    if item and SetItemCtx(item) then
        PaintItemButton(button, key)
    else
        Clear(button)
    end
end

-- The flyout is one frame, built when its file loads; a behavior keeps it
-- (FlyoutBehaviorMixin:SetFlyout)
local function HookFlyout(flyout)
    if not flyout or flyouts[flyout] then return end
    flyouts[flyout] = true
    ScrollUtil.AddInitializedFrameCallback(flyout.ScrollBox, function(_, button, elementData)
        PaintFlyoutButton(button, elementData)
    end, OWNER)
    -- The choices it already built (ProfessionsFlyoutMixin:InitializeContents)
    flyout.ScrollBox:ForEachFrame(PaintFlyoutButton)
end

local function PaintLogButton(button, key, link, count)
    wipe(ctx)
    if link then
        ctx.link = link
        PaintItemButton(button, key, count)
    else
        Clear(button)
    end
end

-- A crafting result: its item and, after a multicraft, the bonus row's icon
-- (ProfessionsCraftingOutputLogElementMixin:Init)
local function PaintLogElement(element, resultData)
    local key = ManagedKey(element)
    if not key then return end
    local link = resultData.hyperlink
    PaintLogButton(element.ItemContainer.Item, key, link, resultData.quantity)
    PaintLogButton(element.Multicraft.Item, key, resultData.multicraft > 0 and link or nil)
end

local function HookLog(log)
    ScrollUtil.AddInitializedFrameCallback(log.ScrollBox, function(_, element, resultData)
        PaintLogElement(element, resultData)
    end, OWNER)
end

local function HookTemplates()
    if templatesHooked then return end
    templatesHooked = true
    -- Professions.SetupOutputIcon and the crafter's fulfillment icon end here
    hooksecurefunc(Professions, "SetupOutputIconCommon", function(icon, _, _, _, item)
        PaintOutput(icon, item)
    end)
    -- Every slot type's Init calls the base Init through the mixin table
    hooksecurefunc(ProfessionsRecipeSlotBaseMixin, "Init", function(slot)
        if AnyManaged() then HookSlot(slot) end
    end)
    hooksecurefunc("OpenProfessionsItemFlyout", function(_, _, behavior)
        if AnyManaged() then HookFlyout(behavior.flyout) end
    end)
end

-------------------------------------------------------------------------------
--  Repaint: every shown button, read the way its form sets it
-------------------------------------------------------------------------------
-- The item a recraft slot shows: an order's link, else the transaction's bag item
-- (ProfessionsRecraftSlotMixin:Init)
local function RecraftItem(link, transaction)
    if link then return Item:CreateFromItemLink(link) end
    local guid = transaction and transaction:GetRecraftAllocation()
    if guid then return Item:CreateFromItemGUID(guid) end
end

-- The input only: the output stays Blizzard's (HookRecraft)
local function RepaintRecraft(recraftSlot, item)
    if recraftSlot:IsVisible() then PaintRecraft(recraftSlot.InputSlot, item) end
end

local function RepaintSlot(slot)
    HookSlot(slot)
    if slot:IsVisible() then PaintSlot(slot) end
end

local function RepaintSlots(form)
    for slot in form.reagentSlotPool:EnumerateActive() do RepaintSlot(slot) end
    if form.salvageSlot then RepaintSlot(form.salvageSlot) end
    if form.enchantSlot then RepaintSlot(form.enchantSlot) end
end

-- A recipe schematic: crafting page, crafter order or linked recipe.
-- recraftLink is the crafter order's item (ProfessionsCrafterOrderViewMixin).
local function RepaintSchematic(form, recraftLink)
    if not form:IsVisible() then return end
    local transaction = form:GetTransaction()
    if transaction then
        if form.OutputIcon:IsVisible() then
            -- ProfessionsRecipeSchematicFormMixin:UpdateOutputItem
            local info = C_TradeSkillUI.GetRecipeOutputItemData(transaction:GetRecipeID(),
                transaction:CreateCraftingReagentInfoTbl(), transaction:GetAllocationItemGUID())
            PaintOutput(form.OutputIcon, info and info.hyperlink)
        end
        RepaintRecraft(form.recraftSlot, RecraftItem(recraftLink, transaction))
    end
    RepaintSlots(form)
end

-- A finished crafter order's item (ProfessionsCrafterOrderViewMixin:SetOrder)
local function RepaintFulfillment(view)
    local form, order = view.OrderDetails.FulfillmentForm, view.order
    if not (form:IsVisible() and order and order.outputItemHyperlink) then return end
    if order.isRecraft then
        local recraftSlot = form.RecraftSlot
        if recraftSlot:IsVisible() then
            PaintRecraft(recraftSlot.InputSlot, RecraftItem(order.recraftItemHyperlink))
            PaintRecraft(recraftSlot.OutputSlot, RecraftItem(order.outputItemHyperlink))
        end
    elseif form.ItemIcon:IsVisible() then
        PaintOutput(form.ItemIcon, order.outputItemHyperlink)
    end
end

local function RepaintLog(log)
    if log:IsVisible() then log.ScrollBox:ForEachFrame(PaintLogElement) end
end

local function RepaintFlyouts(frameKey)
    for flyout in pairs(flyouts) do
        if flyout:IsVisible() and WindowKey(flyout) == frameKey then
            flyout.ScrollBox:ForEachFrame(PaintFlyoutButton)
        end
    end
end

local function RepaintProfessions()
    local page = ProfessionsFrame.CraftingPage
    RepaintSchematic(page.SchematicForm)
    RepaintSchematic(InspectRecipeFrame.SchematicForm)
    RepaintLog(page.CraftingOutputLog)
    if orderView then
        local order = orderView.order
        RepaintSchematic(orderView.OrderDetails.SchematicForm,
            order and (order.outputItemHyperlink or order.recraftItemHyperlink))
        RepaintFulfillment(orderView)
        RepaintLog(orderView.CraftingOutputLog)
    end
    RepaintFlyouts(PROF)
end

local function RepaintOrders()
    local form = ProfessionsCustomerOrdersFrame.Form
    if not form:IsVisible() then return end
    local transaction, order = form.transaction, form.order
    if transaction then
        if form.OutputIcon:IsVisible() then
            -- ProfessionsCustomerOrderFormMixin:InitSchematic
            local info = C_TradeSkillUI.GetRecipeOutputItemData(transaction:GetRecipeID())
            PaintOutput(form.OutputIcon, info and info.hyperlink)
        end
        RepaintRecraft(form.RecraftSlot, RecraftItem(order and order.recraftItemHyperlink, transaction))
    end
    RepaintSlots(form)
    RepaintFlyouts(ORDERS)
end

II.RegisterLazyFrame(PROF, "Blizzard_Professions", function()
    windows[ProfessionsFrame] = PROF
    windows[InspectRecipeFrame] = PROF
    HookTemplates()
    local page = ProfessionsFrame.CraftingPage
    HookRecraft(page.SchematicForm.recraftSlot)
    HookRecraft(InspectRecipeFrame.SchematicForm.recraftSlot)
    HookLog(page.CraftingOutputLog)
    -- WoW Forever's (Camelot) ProfessionsFrame has no OrdersPage
    local orders = ProfessionsFrame.OrdersPage
    orderView = orders and orders.OrderView
    if orderView then
        HookRecraft(orderView.OrderDetails.SchematicForm.recraftSlot)
        HookRecraft(orderView.OrderDetails.FulfillmentForm.RecraftSlot, true)
        HookLog(orderView.CraftingOutputLog)
    end
end, RepaintProfessions)

II.RegisterLazyFrame(ORDERS, "Blizzard_ProfessionsCustomerOrders", function()
    windows[ProfessionsCustomerOrdersFrame] = ORDERS
    HookTemplates()
    HookRecraft(ProfessionsCustomerOrdersFrame.Form.RecraftSlot)
end, RepaintOrders)
