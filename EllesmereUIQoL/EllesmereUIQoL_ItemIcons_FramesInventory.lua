if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_FramesInventory.lua
--  Item Icons frame adapters for the player's own items and the vendor:
--  Blizzard's bags and bank (only while EUI Bags does not replace them), the
--  vendor (buy and buyback, Blizzard's grid and EUI's list view), the
--  equipment flyout, the character sheet and the inspect sheet
--  (Blizzard_InspectUI, load-on-demand). Each paints through
--  EllesmereUI.ItemIcons (EllesmereUIQoL_ItemIcons.lua) after Blizzard's own
--  update. Hooks go in on a frame's first Enable and stay inert while it is
--  released. The vendor and flyout item levels of EUI step aside while their
--  frame is managed: these adapters refresh them as they take over and let go.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons
local Paint, Clear, IsManaged = II.Paint, II.Clear, II.IsFrameEnabled
local HideNative, RestoreNative = II.HideNative, II.RestoreNative
local FlyoutButtonItem = ns.FlyoutButtonItem   -- EllesmereUIQoL.lua

local BAGS, BANK, MERCHANT = "blizz_bags", "blizz_bank", "merchant"
local FLYOUT, CHARSHEET, INSPECT = "flyout", "charsheet", "inspect"
-- Equipment slot buttons: Character<name>Slot and Inspect<name>Slot. Ranged
-- and Ammo exist on WoW Forever only
local SLOT_NAMES = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand",
    "Ranged", "Ammo",
}

-------------------------------------------------------------------------------
--  Shared painting
-------------------------------------------------------------------------------
local ctx, facts = {}, {}
local equippedLoc = ItemLocation:CreateEmpty()

-- The one paint context, emptied for the next item
local function NewCtx(link)
    wipe(ctx)
    wipe(facts)
    ctx.link, ctx.facts = link, facts
    return ctx
end

-- While a frame is managed its layout decides every mark: Blizzard's count,
-- crafting pip and junk coin stay hidden whether their element is placed or not
local function HideMarks(button, frameKey)
    HideNative(button.Count, frameKey)
    HideNative(button.ProfessionQualityOverlay, frameKey)
    HideNative(button.JunkIcon, frameKey)
end

-- Blizzard's quest starter mark gives way too; the border it puts on other
-- quest items stays
local function SyncQuestMark(button, starter, frameKey)
    if starter then
        HideNative(button.IconQuestTexture, frameKey)
    else
        RestoreNative(button.IconQuestTexture)
    end
end

-- Blizzard dims a button with its black ItemContextOverlay for the search
-- filter and for item contexts (scrapping, socketing and the like)
local function Dimmed(button)
    return button:GetItemContextOverlayMode() == ItemButtonConstants.ContextMatch.Standard
end

-- The WoW Forever UI is unverified: a hook target it lacks leaves that frame
-- unpainted instead of raising an error. True once hooked
local function HookGlobal(name, fn)
    if type(_G[name]) ~= "function" then return false end
    hooksecurefunc(name, fn)
    return true
end

local function HookMethod(object, name, fn)
    if not (object and type(object[name]) == "function") then return false end
    hooksecurefunc(object, name, fn)
    return true
end

-- A bag or bank tab slot
local function PaintContainerItem(button, bag, slot, frameKey)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local link = info and info.hyperlink
    if not link then
        Clear(button)
        return
    end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    local starter = quest.questID ~= nil and not quest.isActive
    local c = NewCtx(link)
    c.bag, c.slot, c.count, c.quality, c.itemID = bag, slot, info.stackCount, info.quality, info.itemID
    if Dimmed(button) then c.alpha = II.DIM_ALPHA end
    facts.isBound, facts.questStarter = info.isBound, starter
    Paint(button, c, frameKey)
    HideMarks(button, frameKey)
    SyncQuestMark(button, starter, frameKey)
end

-- One of the player's items, in a container slot (bag, slot) or equipped
-- (slot alone, and then bound)
local function PaintOwnItem(button, link, bag, slot, frameKey)
    if not link then
        Clear(button)
        return
    end
    local c = NewCtx(link)
    if bag then
        c.bag, c.slot = bag, slot
        local info = C_Container.GetContainerItemInfo(bag, slot)
        c.count = info and info.stackCount
    else
        equippedLoc:SetEquipmentSlot(slot)
        c.location = equippedLoc
        c.count = GetInventoryItemCount("player", slot)
        facts.isBound = true
    end
    Paint(button, c, frameKey)
end

-- Frames Blizzard refills far more often than their items change (the pinned
-- flyout every frame, the character sheet on every item cooldown) repaint a
-- button only when its item, its location or the frame's generation changes.
-- Enable and Refresh start a new generation
local generation = { [FLYOUT] = 0, [CHARSHEET] = 0 }
local memo = setmetatable({}, { __mode = "k" })  -- button -> { gen, link, bag, slot } last painted

local function Unchanged(button, frameKey, link, bag, slot)
    local m = memo[button]
    if not m then
        m = {}
        memo[button] = m
    end
    local gen = generation[frameKey]
    if m.gen == gen and m.link == link and m.bag == bag and m.slot == slot then return true end
    m.gen, m.link, m.bag, m.slot = gen, link, bag, slot
    return false
end

-------------------------------------------------------------------------------
--  Blizzard bags (ContainerFrame1-6, ContainerFrameCombinedBags) and bank
--  (BankPanel: character and warband tabs)
-------------------------------------------------------------------------------
-- EUI Bags replaces both (its own frame key: eui_bags), unless it stood down
-- for WoW Forever's Gamepad interface style (EUI_Bags_Start.lua,
-- EllesmereUIBags_Bank.lua)
local function BlizzardBagsInUse()
    return not C_AddOns.IsAddOnLoaded("EllesmereUIBags")
        or (EllesmereUI.IS_FOREVER and EllesmereUI.PadGamepadUI())
end

-- An item context (scrapper, socketing and the like) dims buttons without a
-- refill: a managed frame repaints once every button has followed it
local contextOwners = {}   -- frame key -> registry owner while watched
local function WatchContext(frameKey, on)
    if on == (contextOwners[frameKey] ~= nil) then return end
    local event = ItemButtonUtil.Event.ItemContextChanged
    if on then
        local owner = {}
        contextOwners[frameKey] = owner
        ItemButtonUtil.RegisterCallback(event, function() II.RequestRefresh(frameKey) end, owner)
    else
        ItemButtonUtil.UnregisterCallback(event, contextOwners[frameKey])
        contextOwners[frameKey] = nil
    end
end

local bagFrames          -- the hooked container frames, once Enable ran
local bankHooked = false

-- After ContainerFrameMixin:UpdateItems, the end of every refill of a frame
local function PaintBagFrame(frame)
    if not IsManaged(BAGS) or not frame:IsShown() then return end
    for _, button in frame:EnumerateValidItems() do
        PaintContainerItem(button, button:GetBagID(), button:GetID(), BAGS)
    end
end

local function RefreshBags()
    if not bagFrames then return end
    for i = 1, #bagFrames do PaintBagFrame(bagFrames[i]) end
end

-- A search only dims: the marks follow once the typing settles
local function RequestBagsRefresh() II.RequestRefresh(BAGS) end

local function HookBagFrame(frame)
    if HookMethod(frame, "UpdateItems", PaintBagFrame) then
        bagFrames[#bagFrames + 1] = frame
        HookMethod(frame, "UpdateSearchResults", RequestBagsRefresh)
    end
end

II.RegisterFrame(BAGS, {
    Enable = function()
        if not BlizzardBagsInUse() then return end
        if not bagFrames then
            bagFrames = {}
            for i = 1, NUM_CONTAINER_FRAMES do HookBagFrame(_G["ContainerFrame" .. i]) end
            HookBagFrame(ContainerFrameCombinedBags)
        end
        WatchContext(BAGS, bagFrames[1] ~= nil)
        RefreshBags()
    end,
    Refresh = RefreshBags,
    Disable = function() WatchContext(BAGS, false) end,
})

-- After BankPanelMixin builds the selected tab's slots or refills them
local function PaintBank()
    if not IsManaged(BANK) or not BankPanel:IsShown() then return end
    for button in BankPanel:EnumerateValidItems() do
        PaintContainerItem(button, button:GetBankTabID(), button:GetContainerSlotID(), BANK)
    end
end

local function RefreshBank()
    if bankHooked then PaintBank() end
end

local function RequestBankRefresh() II.RequestRefresh(BANK) end

II.RegisterFrame(BANK, {
    Enable = function()
        if not BlizzardBagsInUse() then return end
        if not bankHooked and HookMethod(BankPanel, "GenerateItemSlotsForSelectedTab", PaintBank) then
            bankHooked = true
            HookMethod(BankPanel, "RefreshAllItemsForSelectedTab", PaintBank)
            HookMethod(BankPanel, "UpdateSearchResults", RequestBankRefresh)
        end
        WatchContext(BANK, bankHooked)
        RefreshBank()
    end,
    Refresh = RefreshBank,
    Disable = function() WatchContext(BANK, false) end,
})

-------------------------------------------------------------------------------
--  Vendor (MerchantFrame): Blizzard's grid, the latest sale beside it, and the
--  rows of EUI's list view (EUI_MerchantItem<i>, built by
--  EllesmereUIBlizzardSkin_WindowPacks.lua, which hides the grid tiles)
-------------------------------------------------------------------------------
local merchantHooked = false
local gridTiles, gridButtons = {}, {}   -- MerchantItem1-12 and their item buttons

local function IsBuybackTab()
    return PanelTemplates_GetSelectedTab(MerchantFrame) ~= 1
end

-- The vendor's item at index, or on the buyback tab the sold item there
local function PaintMerchantItem(button, index, isBuyback, anchor)
    local link
    if isBuyback then link = GetBuybackItemLink(index) else link = GetMerchantItemLink(index) end
    if not link then
        Clear(button)
        return
    end
    local c = NewCtx(link)
    c.anchor = anchor
    local starter = false
    if isBuyback then
        local _, _, _, quantity, _, _, isBound = GetBuybackItemInfo(index)
        c.count = quantity
        facts.isBound = isBound
    else
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            c.count = info.stackCount
            starter = info.isQuestStartItem == true
        end
        facts.questStarter = starter
    end
    Paint(button, c, MERCHANT)
    HideMarks(button, MERCHANT)
    SyncQuestMark(button, starter, MERCHANT)
end

-- After MerchantFrame_UpdateMerchantInfo / _UpdateBuybackInfo, which set each
-- shown item button's ID to its index
local function PaintMerchantGrid(isBuyback)
    for i = 1, #gridButtons do
        local button = gridButtons[i]
        if gridTiles[i]:IsShown() and button:IsShown() then
            PaintMerchantItem(button, button:GetID(), isBuyback)
        else
            Clear(button)
        end
    end
    local latest = MerchantBuyBackItemItemButton
    if not isBuyback and MerchantBuyBackItem:IsShown() then
        PaintMerchantItem(latest, GetNumBuybackItems(), true)
    else
        Clear(latest)
    end
end

local function OnMerchantInfo()
    if IsManaged(MERCHANT) then PaintMerchantGrid(false) end
end

local function OnBuybackInfo()
    if IsManaged(MERCHANT) then PaintMerchantGrid(true) end
end

-- A list row covers its icon (SlotTexture), not the row-wide item button
local function PaintListRow(row)
    local button = row.ItemButton
    PaintMerchantItem(button, button:GetID(), IsBuybackTab(), row.SlotTexture)
end

-- EUI's list view sets each row's ID, then its quality through
-- MerchantFrameItem_UpdateQuality, which Blizzard's grid tiles also pass
local function OnUpdateQuality(row)
    if not IsManaged(MERCHANT) then return end
    local name = row:GetName()
    if name and name:find("^EUI_MerchantItem%d+$") then PaintListRow(row) end
end

local function RefreshMerchant()
    if not merchantHooked or not MerchantFrame:IsShown() then return end
    PaintMerchantGrid(IsBuybackTab())
    local i, row = 1, _G.EUI_MerchantItem1
    while row do
        if row:IsShown() then PaintListRow(row) end
        i = i + 1
        row = _G["EUI_MerchantItem" .. i]
    end
end

-- EUI's vendor item levels (Blizzard Skins+), which step aside while managed
local function RefreshVendorItemLevels()
    local refresh = EllesmereUI._Merchant_RefreshItemLevels
    if refresh then refresh() end
end

II.RegisterFrame(MERCHANT, {
    Enable = function()
        if not merchantHooked and HookGlobal("MerchantFrame_UpdateMerchantInfo", OnMerchantInfo) then
            merchantHooked = true
            for i = 1, BUYBACK_ITEMS_PER_PAGE do
                gridTiles[i], gridButtons[i] = _G["MerchantItem" .. i], _G["MerchantItem" .. i .. "ItemButton"]
            end
            HookGlobal("MerchantFrame_UpdateBuybackInfo", OnBuybackInfo)
            HookGlobal("MerchantFrameItem_UpdateQuality", OnUpdateQuality)
        end
        RefreshVendorItemLevels()
        RefreshMerchant()
    end,
    Refresh = RefreshMerchant,
    Disable = RefreshVendorItemLevels,
})

-------------------------------------------------------------------------------
--  Equipment flyout (EquipmentFlyoutFrame): the character sheet's and the
--  item-location flyouts (item upgrade and the like)
-------------------------------------------------------------------------------
local flyoutHooked = false
-- Inert until the flyout is managed: an equipment set change moves the set
-- names the memo keeps
local flyoutEvents = CreateFrame("Frame")
flyoutEvents:SetScript("OnEvent", function() II.RequestRefresh(FLYOUT) end)

local function PaintFlyoutButton(button, useItemLocation)
    local link, bag, slot = FlyoutButtonItem(button, useItemLocation)
    if not Unchanged(button, FLYOUT, link, bag, slot) then PaintOwnItem(button, link, bag, slot, FLYOUT) end
    HideMarks(button, FLYOUT)
end

-- After EquipmentFlyout_UpdateItems: every fill, and every frame while a
-- flyout is pinned open
local function PaintFlyout()
    if not IsManaged(FLYOUT) then return end
    local flyout = EquipmentFlyoutFrame
    local source = flyout.button
    if not source then return end
    local settings = source:GetParent().flyoutSettings
    local useItemLocation = settings and settings.useItemLocation
    local buttons = flyout.buttons
    for i = 1, #buttons do
        local button = buttons[i]
        if button:IsShown() then PaintFlyoutButton(button, useItemLocation) end
    end
end

local function RefreshFlyout()
    generation[FLYOUT] = generation[FLYOUT] + 1
    if flyoutHooked and EquipmentFlyoutFrame:IsShown() then PaintFlyout() end
end

II.RegisterFrame(FLYOUT, {
    Enable = function()
        flyoutHooked = flyoutHooked or HookGlobal("EquipmentFlyout_UpdateItems", PaintFlyout)
        if flyoutHooked then flyoutEvents:RegisterEvent("EQUIPMENT_SETS_CHANGED") end
        -- The QoL flyout item level (EllesmereUIQoL.lua) steps aside
        ns.RefreshFlyoutItemLevels()
        RefreshFlyout()
    end,
    Refresh = RefreshFlyout,
    Disable = function()
        flyoutEvents:UnregisterEvent("EQUIPMENT_SETS_CHANGED")
        ns.RefreshFlyoutItemLevels()
    end,
})

-------------------------------------------------------------------------------
--  Character sheet slots (Character<name>Slot)
-------------------------------------------------------------------------------
local charSlots = {}     -- slot button -> true
local charHooked = false

-- After PaperDollItemSlotButton_Update, which other slot buttons also pass
local function PaintCharSlot(button)
    if not IsManaged(CHARSHEET) or not charSlots[button] then return end
    local slot = button:GetID()
    local link = GetInventoryItemLink("player", slot)
    if not Unchanged(button, CHARSHEET, link, nil, slot) then PaintOwnItem(button, link, nil, slot, CHARSHEET) end
    HideMarks(button, CHARSHEET)
end

local function RefreshCharSheet()
    generation[CHARSHEET] = generation[CHARSHEET] + 1
    for button in pairs(charSlots) do
        if button:IsVisible() then PaintCharSlot(button) end
    end
end

II.RegisterFrame(CHARSHEET, {
    Enable = function()
        if not charHooked and HookGlobal("PaperDollItemSlotButton_Update", PaintCharSlot) then
            charHooked = true
            for i = 1, #SLOT_NAMES do
                local button = _G["Character" .. SLOT_NAMES[i] .. "Slot"]
                if button then charSlots[button] = true end
            end
        end
        RefreshCharSheet()
    end,
    Refresh = RefreshCharSheet,
})

-------------------------------------------------------------------------------
--  Inspect sheet slots (Inspect<name>Slot, Blizzard_InspectUI)
-------------------------------------------------------------------------------
local inspectSlots = {}  -- slot button -> true
local inspectHooked = false

-- After InspectPaperDollItemSlotButton_Update. Another player's gear has no
-- location the client can ask about; equipped, it is bound
local function PaintInspectSlot(button)
    if not IsManaged(INSPECT) or not inspectSlots[button] then return end
    local unit, slot = InspectFrame.unit, button:GetID()
    local link = unit and GetInventoryItemLink(unit, slot)
    if link then
        local c = NewCtx(link)
        c.count = GetInventoryItemCount(unit, slot)
        facts.isBound = true
        Paint(button, c, INSPECT)
    else
        Clear(button)
    end
    HideMarks(button, INSPECT)
end

local function RefreshInspect()
    if not inspectHooked or not InspectFrame:IsShown() then return end
    for button in pairs(inspectSlots) do
        if button:IsVisible() then PaintInspectSlot(button) end
    end
end

II.RegisterLazyFrame(INSPECT, "Blizzard_InspectUI", function()
    inspectHooked = HookGlobal("InspectPaperDollItemSlotButton_Update", PaintInspectSlot)
    if not inspectHooked then return end
    for i = 1, #SLOT_NAMES do
        local button = _G["Inspect" .. SLOT_NAMES[i] .. "Slot"]
        if button then inspectSlots[button] = true end
    end
end, RefreshInspect)
