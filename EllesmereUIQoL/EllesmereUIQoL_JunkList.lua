if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_JunkList.lua
--  Small window listing the N cheapest-to-vendor stacks in your bags.
--    Ctrl + Left Click  : delete the stack
--    Middle Click       : add the item to the exclusion list (never shown again)
--  Each icon shows its stack's vendor value underneath, rounded to silver
--  (1g 15s 12c -> 1g 15s). Copper only appears while the value is under 1g.
-------------------------------------------------------------------------------

local ns = select(2, ...)
local EUI = EllesmereUI
local PP  = EUI and EUI.PP

-- Sits under EllesmereUIQoLDB.profile.junkList so it shares the QoL SavedVariable
-- with the other QoL features without clobbering them.
local defaults = {
    profile = {
        junkList = {
            enabled    = false,  -- opt-in: this window can delete items
            itemCount  = 4,      -- 1..MAX_CELLS
            iconSize   = 32,
            showFreeSlots = false,  -- title reads "Bag Slots - free/total"; off hides the title
            iconSpacing = 6,     -- gap between icons, px
            priceSide  = "bottom",  -- bottom | top
            excluded   = {},     -- [itemID] = true
            pos        = nil,    -- { centerX, centerY } stored after first move
        },
    },
}

local addon = {}
addon.db = nil
local function P()
    return addon.db and addon.db.profile and addon.db.profile.junkList
end

-- Layout
local MAX_CELLS = 6
local ICON_GAP  = 6      -- horizontal gap between icons
local PRICE_H   = 12
local TITLE_H   = 24
local PAD       = 8
local SWAP_GUARD = 0.3  -- seconds a refilled cell ignores clicks (stops a double click acting twice)

local frame, hdrBg, titleFS, emptyFS
local cells = {}
local pending = {}   -- [itemID] = true: item data not cached yet, awaiting GET_ITEM_INFO_RECEIVED
local failed  = {}   -- [itemID] = true: the client said the data will not load; skip it
local eventFrame

-------------------------------------------------------------------------------
--  Fonts (same house style as the other QoL popups)
-------------------------------------------------------------------------------
local function MakeLabel(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local flags = (EUI.GetFontOutlineFlag("extras")) or ""
    EUI.PrimeFontShadow(fs, flags == "")
    fs:SetFont((EUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF", size, flags)
    if r then fs:SetTextColor(r, g or 1, b or 1, a or 1) end
    return fs
end

-------------------------------------------------------------------------------
--  Money text: rounded to silver, so 1g15s12c reads "1g 15s". Copper only
--  shows while the value is under 1 gold ("15s 12c").
-------------------------------------------------------------------------------
local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

local function FormatValue(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        local out = BreakUpLargeNumbers(g) .. GOLD_ICON
        if s > 0 then out = out .. " " .. s .. SILVER_ICON end
        return out
    end
    if s > 0 then
        local out = s .. SILVER_ICON
        if c > 0 then out = out .. " " .. c .. COPPER_ICON end
        return out
    end
    return c .. COPPER_ICON
end

-------------------------------------------------------------------------------
--  Bag scan: gray and white stacks sorted by total vendor value, cheapest first
-------------------------------------------------------------------------------
local QUEST_CLASS = Enum.ItemClass.Questitem

-- Junk only: Poor (gray) and Common (white). Anything better never lists, so a
-- one-click delete can never reach it.
local MAX_QUALITY = Enum.ItemQuality.Common

local function Scan(limit, excluded)
    local list = {}
    wipe(pending)
    -- Regular bags only: the reagent bag and specialty bags (quiver, ammo pouch)
    -- hold things this one-click delete list must never offer. A family of 0 is
    -- a general-purpose bag (the backpack included).
    local getSetInfo = C_Container.GetContainerItemEquipmentSetInfo
    for bag = 0, NUM_BAG_SLOTS do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        for slot = 1, (family == 0 and C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and info.hyperlink
                and not failed[info.itemID] and not excluded[info.itemID] and (info.quality or 0) <= MAX_QUALITY
                and not (getSetInfo and getSetInfo(bag, slot)) then
                -- Quest items never list, including ones that start a quest (same check as Bags).
                local qi = C_Container.GetContainerItemQuestInfo(bag, slot)
                if not (qi and (qi.isQuestItem or qi.questID)) then
                    local _, _, _, _, _, _, _, _, _, _, sell, classID = C_Item.GetItemInfo(info.hyperlink)
                    if sell == nil then
                        pending[info.itemID] = true  -- item data not cached yet; its own GET_ITEM_INFO_RECEIVED rescans
                    elseif classID ~= QUEST_CLASS then
                        -- No vendor value still wastes a slot, so it lists (at the top), but
                        -- not when soulbound: those are keepers (Hearthstone, Marks of Honor).
                        local noValue = info.hasNoValue or sell == 0
                        if not (noValue and info.isBound) then
                            local count = info.stackCount or 1
                            list[#list + 1] = {
                                bag = bag, slot = slot, itemID = info.itemID,
                                icon = info.iconFileID, count = count,
                                total = noValue and 0 or sell * count,
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total < b.total end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    for i = #list, limit + 1, -1 do list[i] = nil end
    return list
end

-------------------------------------------------------------------------------
--  Item actions
-------------------------------------------------------------------------------
local Refresh  -- forward

-- Every rescan goes through here: any number of triggers in one frame (bag
-- updates, item loads, settings, an exclude) collapse into a single Refresh.
local refreshQueued = false
local function RunQueuedRefresh()
    refreshQueued = false
    Refresh()
end
local function RequestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, RunQueuedRefresh)
end

-- DeleteCursorItem needs a hardware event, so pickup and delete both run inside
-- the click that called us.
local function DeleteStack(bag, slot, itemID)
    if CursorHasItem() then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.itemID ~= itemID or info.isLocked then return end
    C_Container.PickupContainerItem(bag, slot)
    local kind, id = GetCursorInfo()
    if kind == "item" and id == itemID then
        DeleteCursorItem()
    elseif CursorHasItem() then
        ClearCursor()
    end
end

local function ExcludeItem(cell)
    local p = P(); if not p then return end
    p.excluded = p.excluded or {}
    p.excluded[cell.itemID] = true
    RequestRefresh()
end

local function OnCellClick(self, button)
    if not self.itemID then return end
    -- Add in a SWAP_GUARD timer to prevent accidental double clicks to delete 2 items
    -- However we still want to be able to delete items quickly without needing to move
    -- the mouse cursor in and outside of the icon window
    -- exception for using timers for QoL and expected behaviour of deleting / excluding multiple items
    if self._swapT and GetTime() - self._swapT < SWAP_GUARD then return end
    if button == "LeftButton" and IsControlKeyDown() then
        if InCombatLockdown() then return end
        DeleteStack(self.bag, self.slot, self.itemID)
    elseif button == "MiddleButton" then
        ExcludeItem(self)
    end
end

local function OnCellEnter(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(self.bag, self.slot)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Ctrl + Left Click: delete", 1, 0.3, 0.3)
    GameTooltip:AddLine("Middle Click: never show this item", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnCellEnterScript(self)
    self._swapT = nil
    OnCellEnter(self)
end

-------------------------------------------------------------------------------
--  Frame construction
-------------------------------------------------------------------------------
local function AcquireCell(i)
    if cells[i] then return cells[i] end
    local b = CreateFrame("Button", nil, frame)
    b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    b:SetScript("OnClick", OnCellClick)
    b:SetScript("OnEnter", OnCellEnterScript)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b._icon = b:CreateTexture(nil, "ARTWORK")
    b._icon:SetAllPoints()
    b._icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
    if PP and PP.CreateBorder then PP.CreateBorder(b, 0, 0, 0, 1, 1, "OVERLAY", 7) end

    b._count = MakeLabel(b, 11, 1, 1, 1, 1)
    b._count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)

    b._price = MakeLabel(b, 10, 1, 1, 1, 1)
    b._price:SetPoint("TOP", b, "BOTTOM", 0, -3)

    cells[i] = b
    return b
end

local function ApplyPosition()
    if not frame then return end
    local p = P(); if not p then return end
    frame:ClearAllPoints()
    local pos = p.pos
    frame:SetPoint("CENTER", UIParent, "CENTER", (pos and pos.centerX) or 0, (pos and pos.centerY) or 0)
end

local function BuildFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "EllesmereUIJunkList", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:Hide()

    -- No window art: just the title row, icons and prices. Nothing but the cells
    -- takes the mouse, so the window is click-through; moving is Unlock Mode's job.
    hdrBg = CreateFrame("Frame", nil, frame)
    hdrBg:SetPoint("TOPLEFT", 1, -1); hdrBg:SetPoint("TOPRIGHT", -1, 0); hdrBg:SetHeight(TITLE_H)

    titleFS = MakeLabel(frame, 11, 1, 1, 1, 1)
    titleFS:SetPoint("LEFT", hdrBg, "LEFT", PAD, 0)

    -- Mouse-disabled frame over the header. Unexplained, but on the Forever client
    -- the title is not drawn without it. Keep it.
    local hdrCover = CreateFrame("Frame", nil, frame)
    hdrCover:SetPoint("TOPLEFT", hdrBg, "TOPLEFT")
    hdrCover:SetPoint("BOTTOMRIGHT", hdrBg, "BOTTOMRIGHT")

    emptyFS = MakeLabel(frame, 11, 1, 1, 1, 0.5)
    emptyFS:SetText("Nothing to vendor")

    return frame
end

-------------------------------------------------------------------------------
--  Refresh: rescan the bags and relayout
-------------------------------------------------------------------------------
Refresh = function()
    local p = P()
    if not frame or not p then return end
    if not p.enabled then frame:Hide(); return end

    local iconSz = p.iconSize or 32
    local limit = math.max(1, math.min(MAX_CELLS, p.itemCount or 4))

    if p.showFreeSlots then
        -- Same bags the scan uses: regular bags only, no reagent or specialty bags.
        local free, total = 0, 0
        for bag = 0, NUM_BAG_SLOTS do
            local numFree, family = C_Container.GetContainerNumFreeSlots(bag)
            if family == 0 then
                free = free + (numFree or 0)
                total = total + C_Container.GetContainerNumSlots(bag)
            end
        end
        titleFS:SetFormattedText("Bag Slots - %d/%d", free, total)
        titleFS:Show()
    else
        titleFS:Hide()
    end

    local list = Scan(limit, p.excluded or {})
    -- Column pitch is icon + the Icon Spacing slider and nothing else: it must
    -- not follow the price text, or excluding cheap items (leaving pricier, wider
    -- prices) would stretch the row.
    local cellW = iconSz + (p.iconSpacing or ICON_GAP)
    for i = 1, limit do
        local item = list[i]
        if item then AcquireCell(i)._price:SetText(FormatValue(item.total)) end
    end
    local w = math.max(PAD * 2 + limit * cellW, p.showFreeSlots and 140 or 110)  -- room for the end prices to overhang their icons
    local h = TITLE_H + PAD + iconSz + 3 + PRICE_H + PAD
    if PP and PP.Snap then w, h = PP.Snap(w), PP.Snap(h) end
    frame:SetSize(w, h)

    local top = p.priceSide == "top"
    local rowW = (limit - 1) * cellW + iconSz
    local startX = math.floor((w - rowW) / 2 + 0.5)
    for i = 1, limit do
        local item = list[i]
        local cell = AcquireCell(i)
        if item then
            cell:SetSize(iconSz, iconSz)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * cellW, -(TITLE_H + PAD + (top and (PRICE_H + 3) or 0)))
            cell._price:ClearAllPoints()
            if top then cell._price:SetPoint("BOTTOM", cell, "TOP", 0, 3)
            else cell._price:SetPoint("TOP", cell, "BOTTOM", 0, -3) end
            if cell.itemID and cell:IsMouseOver()
                and (cell.bag ~= item.bag or cell.slot ~= item.slot or cell.itemID ~= item.itemID) then
                cell._swapT = GetTime()
            end
            cell.bag, cell.slot, cell.itemID = item.bag, item.slot, item.itemID
            cell._icon:SetTexture(item.icon)
            cell._count:SetText(item.count > 1 and item.count or "")
            cell:Show()
            if GameTooltip:GetOwner() == cell and GameTooltip:IsShown() then OnCellEnter(cell) end
        else
            if GameTooltip:GetOwner() == cell then GameTooltip:Hide() end
            cell.itemID = nil
            cell:Hide()
        end
    end

    for i = limit + 1, #cells do cells[i].itemID = nil; cells[i]:Hide() end

    emptyFS:ClearAllPoints()
    emptyFS:SetPoint("CENTER", frame, "CENTER", 0, -TITLE_H / 2)
    emptyFS:SetShown(#list == 0)

    if eventFrame then
        if next(pending) then eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        else eventFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
    end

    frame:Show()
end

-------------------------------------------------------------------------------
--  Apply (settings entry point) + events
-------------------------------------------------------------------------------
local function SyncEvents(on)
    if not on and not eventFrame then return end  -- never built: nothing to unregister
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, itemID, success)
            if event == "GET_ITEM_INFO_RECEIVED" then
                if not pending[itemID] then return end
                pending[itemID] = nil
                if success == false then failed[itemID] = true end
            end
            RequestRefresh()
        end)
    end
    if on then
        eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    else
        eventFrame:UnregisterAllEvents()
        wipe(pending)
    end
end

local function Apply()
    local p = P()
    if not p then return end
    if p.enabled then
        BuildFrame()
        ApplyPosition()
        SyncEvents(true)
        RequestRefresh()
    else
        SyncEvents(false)
        if frame then frame:Hide() end
    end
end
_G._EUI_JunkList_Apply = Apply

function _G._EUI_JunkList_ClearExclusions()
    local p = P(); if not p then return end
    p.excluded = {}
    RequestRefresh()
end

-------------------------------------------------------------------------------
--  Unlock mode registration
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EUI.RegisterUnlockElements or not EUI.MakeUnlockElement then return end
    local loadPos, clearPos = ns.CenterPosFns(P)
    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key   = "EUI_JunkList",
            label = "Junk Items",
            group = "Quality of Life",
            order = 610,
            noResize = true,
            noAnchorTarget = true,
            isHidden = function()
                local p = P()
                return not p or not p.enabled
            end,
            getFrame = function()
                local p = P()
                return (p and p.enabled) and frame or nil
            end,
            getSize = function()
                if frame then return frame:GetWidth(), frame:GetHeight() end
                return 110, TITLE_H + PAD + 32 + 3 + PRICE_H + PAD
            end,
            savePos = function(_, _, _, x, y)
                local p = P(); if not p then return end
                p.pos = { centerX = x, centerY = y }
            end,
            loadPos = loadPos,
            clearPos = clearPos,
            applyPos = ApplyPosition,
        }),
    })
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not EUI or not EUI.Lite or not EUI.Lite.NewDB then return end
    addon.db = EUI.Lite.NewDB("EllesmereUIQoLDB", defaults, true)
    _G._EUI_JunkList_DB = function() return addon.db end
    Apply()
    RegisterUnlock()
end)
