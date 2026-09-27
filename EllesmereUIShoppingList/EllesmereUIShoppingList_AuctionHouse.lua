if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList_AuctionHouse.lua
--  Search only: nothing is ever posted or bought. One button on the Auction
--  House search bar walks the missing reagents - each click searches the
--  next one (the browse query takes one search string at a time); its
--  right-click menu lists them all. A reagent row's right-click menu also
--  searches it while the Auction House is open.
--
--  The search fills the search bar and sends the browse query through the
--  Auction House's own method; both clients ship the modern Auction House
--  (Blizzard_AuctionHouseUI, load on demand).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = ns.EUI
local Get = ns.Get

local btn
local cursor = 0
local missing = {}

local function MissingReagents()
    wipe(missing)
    for _, e in ipairs(ns.reagents) do
        if e.have < e.need then missing[#missing + 1] = e.itemID end
    end
    -- Missing first, the list's own order after that.
    table.sort(missing, function(a, b)
        local ea, eb = ns.needByItem[a], ns.needByItem[b]
        local ha, hb = ea.have > 0, eb.have > 0
        if ha ~= hb then return not ha end
        return ea.seen < eb.seen
    end)
    return missing
end

local function AHOpen()
    return AuctionHouseFrame and AuctionHouseFrame:IsShown()
end

function ns.SearchAuctionHouse(itemID)
    if not AHOpen() then return end
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        return
    end
    -- Quoted = exact name (the Auction House's own exact-match syntax), so
    -- "Heavy Stone" does not also list Heavy Weightstone and friends.
    name = '"' .. name .. '"'
    AuctionHouseFrame.SearchBar:SetSearchText(name)
    -- This one search ignores the user's filters without changing them: the
    -- query goes out with the default filters and no level range (the
    -- dropdown's saved settings are never touched), and a selected category is
    -- set aside only while the query is built (re-selecting it starts no
    -- search), so the next ordinary search is exactly as the user left it.
    -- The WoW Token category is the exception: re-selecting it switches the
    -- window to the token view over our results, and Blizzard's own searches
    -- leave it unselected too.
    local filters = {}
    for filter, on in pairs(AUCTION_HOUSE_DEFAULT_FILTERS) do
        if on then filters[#filters + 1] = filter end
    end
    local categories = AuctionHouseFrame:GetCategoriesList()
    local c1, c2, c3 = categories:GetSelectedCategory()
    local token = categories:IsWoWTokenCategorySelected()
    if c1 then categories:SetSelectedCategory(nil) end
    AuctionHouseFrame:SendBrowseQuery(name, 0, 0, filters)
    if c1 and not token then categories:SetSelectedCategory(c1, c2, c3) end
end

local function UpdateButton()
    if not btn then return end
    local on = ns.IsOn("ah") and AHOpen()
    local list = on and MissingReagents() or missing
    if not on or #list == 0 then
        btn:Hide()
        return
    end
    if cursor > #list then cursor = 0 end
    local nextID = list[cursor + 1]
    local name = nextID and C_Item.GetItemNameByID(nextID) or ""
    btn:SetText(string.format(EUI.L("Search List %d/%d"), cursor + 1, #list))
    btn.nextName = name
    btn:Show()
end

local function OnClick(self, button)
    local list = MissingReagents()
    if #list == 0 then return end
    if button == "RightButton" then
        local items = {}
        for i, itemID in ipairs(list) do
            local e = ns.needByItem[itemID]
            items[#items + 1] = { text = (C_Item.GetItemNameByID(itemID) or ("#" .. itemID))
                .. "  |cffaaaaaa" .. ns.FormatCount(e.have, e.need) .. "|r",
                onClick = function()
                    cursor = i % #list
                    ns.SearchAuctionHouse(itemID)
                    UpdateButton()
                end }
        end
        EUI.ShowContextMenu(self, items, ns.MENU_OPTS)
        return
    end
    if cursor >= #list then cursor = 0 end
    ns.SearchAuctionHouse(list[cursor + 1])
    cursor = (cursor + 1) % #list
    UpdateButton()
end

local function Build()
    if btn or not AuctionHouseFrame then return end
    btn = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
    btn:SetSize(140, 22)
    -- In the search row, left of the favorites star (over the category list).
    btn:SetPoint("RIGHT", AuctionHouseFrame.SearchBar.FavoritesSearchButton, "LEFT", -8, 0)
    btn:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 10)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", OnClick)
    btn:SetScript("OnEnter", function(self)
        local text = EUI.L("Each click searches the next missing reagent. Right-click: pick one.")
        if self.nextName and self.nextName ~= "" then
            text = string.format(EUI.L("Click: search %s"), self.nextName) .. "\n" .. text
        end
        EUI.ShowWidgetTooltip(self, text)
    end)
    btn:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
    btn:Hide()
    ns.OnChanged(UpdateButton)
    -- The first AH open loads Blizzard's AH UI inside that open, before its
    -- window is shown: re-check on every show rather than trusting the event.
    AuctionHouseFrame:HookScript("OnShow", function()
        if not ns.IsOn("ah") then return end
        cursor = 0
        C_Timer.After(0, UpdateButton)
    end)
end

-- The reagent row menu entry.
ns.reagentMenuExtras[#ns.reagentMenuExtras + 1] = function(itemID)
    if not (ns.IsOn("ah") and AHOpen()) then return nil end
    return { text = EUI.L("Search Auction House"), onClick = function() ns.SearchAuctionHouse(itemID) end }
end

ns.RegisterFeature({
    key = "ah",
    isOn = function() return Get("ahButton") end,
    events = {
        AUCTION_HOUSE_SHOW = function()
            cursor = 0
            C_Timer.After(0, UpdateButton)
        end,
        AUCTION_HOUSE_CLOSED = function() if btn then btn:Hide() end end,
    },
    enable = function()
        EventUtil.ContinueOnAddOnLoaded("Blizzard_AuctionHouseUI", function()
            Build()
            UpdateButton()
        end)
    end,
    disable = UpdateButton,
})
