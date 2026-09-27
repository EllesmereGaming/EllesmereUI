if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList_Vendor.lua
--  Items bought from a merchant, per character:
--    vendor[itemID]  = { qty = items, name, icon, copper = per item,
--                        costs = { { texture, value = per item, name }, ... }, npc }
--    sources[itemID] = { copper = per item, npc }   (a merchant seen selling a
--                                                     tracked reagent)
--  In the merchant window (our own frames on its item buttons, the page
--  update post-hooked): a highlight on everything the list still needs, a
--  "+" that tracks the item as a vendor item, and a Buy Needed button.
--  Buying happens only from that button's click.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = ns.EUI
local Get = ns.Get

-------------------------------------------------------------------------------
--  Vendor list
-------------------------------------------------------------------------------
local function MerchantName()
    local name = UnitName("npc")
    if issecretvalue(name) then return nil end
    return name
end

-- Price per item and the extended costs per item for a merchant index.
local function ReadPrice(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info then return nil end
    local stack = math.max(1, info.stackCount or 1)
    local costs
    if info.hasExtendedCost then
        costs = {}
        for c = 1, (GetMerchantItemCostInfo(index) or 0) do
            local texture, value, link, name = GetMerchantItemCostItem(index, c)
            if value and value > 0 then
                costs[#costs + 1] = { texture = texture, value = value / stack, name = name, link = link }
            end
        end
    end
    return (info.price or 0) / stack, costs, info, stack
end

function ns.TrackVendorItem(index, qty)
    local itemID = GetMerchantItemID(index)
    if not itemID then return end
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local copper, costs, info = ReadPrice(index)
    local store = ns.Char().vendor
    local v = store[itemID]
    if v then
        v.qty = v.qty + qty
    else
        v = { qty = qty }
        store[itemID] = v
    end
    v.name = (info and info.name) or C_Item.GetItemNameByID(itemID)
    v.icon = (info and info.texture) or C_Item.GetItemIconByID(itemID)
    v.copper, v.costs, v.npc = copper, costs, MerchantName()
    ns.Invalidate()
end

function ns.SetVendorQty(itemID, qty)
    local store = ns.Char().vendor
    local v = store[itemID]
    if not v then return end
    qty = math.floor(tonumber(qty) or 0)
    if qty <= 0 then store[itemID] = nil else v.qty = qty end
    ns.Invalidate()
end

-- Vendor items join the needs map (tooltips, merchant highlight, buying).
-- Entries are kept between passes (one runs on every bag update).
ns.vendorNeed = {}
ns.OnRecompute(function()
    local need, store = ns.vendorNeed, ns.Char().vendor
    for itemID in pairs(need) do
        if not store[itemID] then need[itemID] = nil end
    end
    for itemID, v in pairs(store) do
        local e = need[itemID]
        if not e then
            e = { itemID = itemID }
            need[itemID] = e
        end
        e.need, e.have = v.qty, ns.CountItem(itemID)
        e.state = ns.StateOf(e.have, e.need)
    end
end)

-- What the list still needs of an item: reagent gap + vendor gap.
function ns.StillNeeded(itemID)
    local n = ns.Missing(itemID)
    local v = ns.vendorNeed[itemID]
    if v then n = n + math.max(0, v.need - v.have) end
    return n
end

local sortedVendor = {}
ns.AddSection(30, function(out)
    local store = ns.Char().vendor
    wipe(sortedVendor)
    for itemID in pairs(store) do sortedVendor[#sortedVendor + 1] = itemID end
    -- Merchant prices of missing reagents count toward the list's cost too.
    local cost = 0
    for _, e in ipairs(ns.reagents) do
        local src = ns.Char().sources[e.itemID]
        if src and src.copper then cost = cost + math.max(0, e.need - e.have) * src.copper end
    end
    if #sortedVendor == 0 then return cost end
    table.sort(sortedVendor, function(a, b)
        local na, nb = store[a].name or "", store[b].name or ""
        if na ~= nb then return na < nb end
        return a < b
    end)
    local vendorCost = 0
    for _, itemID in ipairs(sortedVendor) do
        local e = ns.vendorNeed[itemID]
        if e then vendorCost = vendorCost + math.max(0, e.need - e.have) * (store[itemID].copper or 0) end
    end
    cost = cost + vendorCost
    if ns.SectionHeader(out, "vendor", "Vendor", #sortedVendor,
        vendorCost > 0 and ns.FormatMoney(vendorCost) or tostring(#sortedVendor)) then
        return cost
    end
    local hideDone = Get("hideCompleted")
    for _, itemID in ipairs(sortedVendor) do
        local v, e = store[itemID], ns.vendorNeed[itemID]
        if e and not (hideDone and e.state == "complete") then
            local row = ns.NewRow(out, "vendor")
            row.key, row.itemID = itemID, itemID
            row.name = C_Item.GetItemNameByID(itemID) or v.name or ("#" .. itemID)
            row.icon = v.icon or C_Item.GetItemIconByID(itemID)
            row.state, row.ready = e.state, e.state == "complete"
            row.fill = math.min(100, e.have * 100 / math.max(1, e.need))
            row.right = ns.FormatCount(e.have, e.need)
        end
    end
    return cost
end)

ns.rowClick.vendor = function(row, e, button)
    local itemID = e.itemID
    local v = ns.Char().vendor[itemID]
    if not v then return end
    if button == "RightButton" then
        ns.QuantityMenu(row, function() return v.qty end,
            function(q) ns.SetVendorQty(itemID, q) end,
            function() ns.SetVendorQty(itemID, 0) end)
    elseif IsAltKeyDown() then
        ns.SetVendorQty(itemID, v.qty - 1)
    elseif IsShiftKeyDown() then
        ns.InsertLink(ns.ItemLink(itemID))
    end
end

local function AddCostLines(copper, costs, npc)
    if (copper and copper > 0) or costs then
        GameTooltip:AddLine(" ")
        local parts = {}
        if copper and copper > 0 then parts[#parts + 1] = ns.FormatMoney(copper) end
        for _, c in ipairs(costs or {}) do
            parts[#parts + 1] = string.format("%s |T%s:0|t", (c.value % 1 == 0) and c.value or string.format("%.1f", c.value), tostring(c.texture or ""))
        end
        GameTooltip:AddDoubleLine(EUI.L("Price each"), table.concat(parts, " "), 1, 0.82, 0, 1, 1, 1)
        if npc then GameTooltip:AddDoubleLine(EUI.L("Sold by"), npc, 1, 0.82, 0, 1, 1, 1) end
    end
end

ns.rowTooltip.vendor = function(_, e)
    GameTooltip:SetItemByID(e.itemID)
    local v = ns.Char().vendor[e.itemID]
    if v then AddCostLines(v.copper, v.costs, v.npc) end
    GameTooltip:AddLine(" ")
    ns.AddHint("Alt-click: one fewer. Shift-click: link. Right-click: menu.")
end

-- A reagent a merchant was seen selling: its price in the reagent tooltip.
local baseReagentTooltip = ns.rowTooltip.reagent
ns.rowTooltip.reagent = function(row, e)
    baseReagentTooltip(row, e)
    local src = ns.Char().sources[e.itemID]
    if src then AddCostLines(src.copper, nil, src.npc) end
end

-------------------------------------------------------------------------------
--  Merchant window
-------------------------------------------------------------------------------
local overlays = {}   -- merchant item button -> our overlay
local buyBtn
local hooked = false

local function RecordSources()
    local sources, npc = ns.Char().sources, MerchantName()
    for index = 1, (GetMerchantNumItems() or 0) do
        local itemID = GetMerchantItemID(index)
        if itemID and ns.needByItem[itemID] then
            local copper, costs = ReadPrice(index)
            if copper and not costs then sources[itemID] = { copper = copper, npc = npc } end
        end
    end
end

local function TrackMenu(btn, index)
    local items = {}
    for _, n in ipairs({ 1, 5, 20 }) do
        items[#items + 1] = { text = string.format(EUI.L("Track %d"), n),
            onClick = function() ns.TrackVendorItem(index, n) end }
    end
    items[#items + 1] = { text = EUI.L("Quantity"), isInput = true, min = 1,
        getValue = function() return 1 end,
        setValue = function(v) ns.TrackVendorItem(index, v) end }
    EUI.ShowContextMenu(btn, items, ns.MENU_OPTS)
end

local function Overlay(itemButton)
    local o = overlays[itemButton]
    if o then return o end
    o = CreateFrame("Frame", nil, itemButton)
    o:SetAllPoints(itemButton)
    o:SetFrameLevel(itemButton:GetFrameLevel() + 3)
    -- The highlight: a 2 px pixel-snapped outline.
    o.edge = CreateFrame("Frame", nil, o)
    o.edge:SetAllPoints(o)
    EUI.PP.CreateBorder(o.edge, 1, 1, 1, 1, 2, "OVERLAY", 7)
    local plus = CreateFrame("Button", nil, o)
    plus:SetSize(14, 14)
    plus:SetPoint("TOPLEFT", o, "TOPLEFT", -3, 3)
    plus.bg = plus:CreateTexture(nil, "BACKGROUND")
    plus.bg:SetAllPoints()
    plus.bg:SetColorTexture(0, 0, 0, 0.75)
    plus.label = plus:CreateFontString(nil, "OVERLAY")
    plus.label:SetPoint("CENTER", 0, 1)
    EUI.ApplyModuleFont(plus.label, nil, 12, ns.FONT_KEY)
    plus.label:SetText("+")
    plus:SetScript("OnClick", function(self) TrackMenu(self, itemButton:GetID()) end)
    plus:SetScript("OnEnter", function(self)
        EUI.ShowWidgetTooltip(self, EUI.L("Track this item as a vendor item."))
    end)
    plus:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
    o.plus = plus
    overlays[itemButton] = o
    return o
end

local function UpdateBuyButton()
    if not buyBtn then return end
    local count = 0
    if ns.IsOn("merchant") and Get("buyButton") and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1 then
        for index = 1, (GetMerchantNumItems() or 0) do
            local itemID = GetMerchantItemID(index)
            if itemID and ns.StillNeeded(itemID) > 0 then count = count + 1 end
        end
    end
    buyBtn:SetText(string.format(EUI.L("Buy Needed (%d)"), count))
    -- Left of the money box, or of the extra-currency box a currency vendor
    -- shows on the same strip.
    local box = MerchantExtraCurrencyBg:IsShown() and MerchantExtraCurrencyBg or MerchantMoneyBg
    if box ~= buyBtn._box then
        buyBtn._box = box
        buyBtn:ClearAllPoints()
        buyBtn:SetPoint("RIGHT", box, "LEFT", -6, 0)
    end
    buyBtn:SetShown(count > 0)
end

local function UpdateMerchant()
    if not ns.IsOn("merchant") then
        for _, o in pairs(overlays) do o:Hide() end
        if buyBtn then buyBtn:Hide() end
        return
    end
    local merchantTab = MerchantFrame.selectedTab == 1
    local color = Get("vendorHighlightColor")
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
        if itemButton then
            local index = itemButton:GetID()
            local itemID = merchantTab and itemButton:IsShown() and index and GetMerchantItemID(index)
            if itemID then
                local o = Overlay(itemButton)
                local needed = Get("vendorHighlight") and ns.StillNeeded(itemID) > 0
                EUI.PP.SetBorderColor(o.edge, color.r, color.g, color.b, 1)
                o.edge:SetShown(needed)
                o.plus:SetShown(Get("vendorButtons") == true)
                o:Show()
            elseif overlays[itemButton] then
                overlays[itemButton]:Hide()
            end
        end
    end
    UpdateBuyButton()
end

-- The purchases Buy Needed would make at this merchant.
local function PlanPurchases()
    local plan, copper, extended = {}, 0, false
    for index = 1, (GetMerchantNumItems() or 0) do
        local itemID = GetMerchantItemID(index)
        local want = itemID and ns.StillNeeded(itemID) or 0
        if want > 0 then
            local _, costs, info, stack = ReadPrice(index)
            if info and info.isPurchasable ~= false then
                local lots = math.ceil(want / stack)
                if info.numAvailable and info.numAvailable >= 0 then lots = math.min(lots, info.numAvailable) end
                if lots > 0 then
                    plan[#plan + 1] = { index = index, lots = lots, stack = stack, price = info.price or 0 }
                    copper = copper + lots * (info.price or 0)
                    if costs and #costs > 0 then extended = true end
                end
            end
        end
    end
    return plan, copper, extended
end

local function Buy(plan)
    for _, p in ipairs(plan) do
        if p.stack > 1 then
            -- Sold in fixed lots: one lot per call.
            for _ = 1, p.lots do
                if GetMoney() < p.price then return end
                BuyMerchantItem(p.index)
            end
        else
            local left = p.lots
            local maxStack = math.max(1, GetMerchantItemMaxStack(p.index) or 1)
            while left > 0 do
                local n = math.min(left, maxStack)
                if GetMoney() < n * p.price then return end
                BuyMerchantItem(p.index, n)
                left = left - n
            end
        end
    end
end

local function OnBuyClick()
    local plan, copper, extended = PlanPurchases()
    if #plan == 0 then return end
    local limit = Get("buyConfirmGold") * 10000
    if extended or copper > limit then
        local msg = string.format(EUI.L("Buy %d item(s) for %s?"), #plan, ns.FormatMoney(copper))
        if extended then msg = msg .. "\n" .. EUI.L("Some of them also cost other currencies.") end
        EUI:ShowConfirmPopup({ title = "Buy Needed", message = msg, confirmText = "Buy",
            onConfirm = function() Buy(plan) end })
        return
    end
    Buy(plan)
end

local function Build()
    if hooked then return end
    hooked = true
    hooksecurefunc("MerchantFrame_Update", UpdateMerchant)
    buyBtn = CreateFrame("Button", nil, MerchantFrame, "UIPanelButtonTemplate")
    buyBtn:SetSize(130, 22)
    buyBtn:SetFrameLevel(MerchantFrame:GetFrameLevel() + 10)
    buyBtn:SetScript("OnClick", OnBuyClick)
    buyBtn:SetScript("OnEnter", function(self)
        EUI.ShowWidgetTooltip(self, EUI.L("Buys what your shopping list still needs from this merchant."))
    end)
    buyBtn:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
    buyBtn:Hide()
    ns.OnChanged(function() if MerchantFrame:IsShown() then UpdateMerchant() end end)
end

local function OnMerchant()
    RecordSources()
    C_Timer.After(0, UpdateMerchant)
end

ns.RegisterFeature({
    key = "merchant",
    isOn = function() return Get("vendorButtons") or Get("vendorHighlight") or Get("buyButton") end,
    events = {
        MERCHANT_SHOW = OnMerchant,
        MERCHANT_UPDATE = OnMerchant,
        MERCHANT_CLOSED = function() if buyBtn then buyBtn:Hide() end end,
        PLAYER_MONEY = function() if MerchantFrame:IsShown() then UpdateBuyButton() end end,
    },
    enable = function()
        Build()
        if MerchantFrame:IsShown() then OnMerchant() end
    end,
    disable = UpdateMerchant,
})
