if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_JunkItems.lua  (WoW Forever only)
--  Small window listing the cheapest junk stacks in your bags: every stack up
--  to Maximum Quality (gray only by default), and anything marked with the
--  Bags Junk Marker.
--    Ctrl + Left Click  : delete the stack (above Delete Without Confirming: a
--                         second Ctrl + Left Click confirms; Rare and better type DELETE first)
--    Middle Click       : never show this item again (account-wide)
--  Each icon shows its stack's value underneath (vendor, or Auctionator's with
--  Use Auctionator Prices on), cut to whole silver (1g 15s 12c -> 1g 15s).
--  Copper only appears while the value is under 1g.
-------------------------------------------------------------------------------
local _, module = ...
local PP = EllesmereUI.PP

local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local GetContainerNumSlots     = C_Container.GetContainerNumSlots
local GetContainerItemInfo     = C_Container.GetContainerItemInfo
local GetItemInfo              = C_Item.GetItemInfo
local GetItemInfoInstant       = C_Item.GetItemInfoInstant

-- Settings live in EllesmereUIDB.junkList, beside the shared visibility keys
-- (unset = Always); unset keys read these. Excluded items are account-wide
-- too: EllesmereUIDB.junkListExcluded holds [itemID] = true.
local DEFAULTS = {
    enabled          = false,     -- opt-in: this window can delete items
    itemCount        = 4,         -- 1..MAX_CELLS
    iconSize         = 32,
    iconSpacing      = 20,        -- gap between icons, px
    priceSide        = "bottom",  -- bottom | top
    auctionPrices    = false,     -- value stacks at Auctionator's price when it has one
    showFreeSlots    = false,     -- title reads "Bag Slots - free/total"; off hides the title
    onlyLowBagSpace  = false,     -- also hidden until fewer bag slots are free than the threshold
    freeSlotThreshold = 5,        -- free regular bag slots, 1..100
    maxQuality       = 0,         -- Enum.ItemQuality: stacks up to this quality list
    oneClickQuality  = 0,         -- stacks up to this quality (Uncommon at most) delete without asking
}
-- The screen's centre until unlock mode moves it.
local F = module.Feature("junkList", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 })
local Get, Read, Enabled = F.Get, F.Read, F.Enabled

-- Layout
local MAX_CELLS = 6
local PRICE_H   = 12
local TITLE_H   = 24

local RARE = Enum.ItemQuality.Rare
local QUEST_CLASS     = Enum.ItemClass.Questitem
local BATTLEPET_CLASS = Enum.ItemClass.Battlepet

local frame, titleFS, emptyFS, probeFS
local cells = {}
-- Made in the main chunk so their handlers bill to this addon, whatever turns
-- the window on (a login or the options page). Neither holds an event while
-- the window is off or hidden.
local eventFrame = CreateFrame("Frame")
-- Only Show When Bag Space Is Low: a bag watcher of its own, listening while
-- the option is on and the visibility setting lets the window show (shown or
-- not, any bag change can cross the threshold).
local bagSpaceWatch = CreateFrame("Frame")
local bagWatching = false
local ctrlWatch  = CreateFrame("Frame")  -- MODIFIER_STATE_CHANGED while a cell is flagged
local active = false         -- shown, with its events registered
local visRegistered = false  -- on the shared visibility dispatcher
local itemInfoOn = false     -- GET_ITEM_INFO_RECEIVED registered
local confirmHandle          -- the open delete confirmation
local armedCell              -- the cell whose stack the next Ctrl + Left Click deletes
local swapCount = 0          -- cells holding a double-click guard
local priceFitW = 0          -- widest price a cell shows in full (its icon plus the spacing, less 2 px)
local lastFree, lastTotal    -- the title's counts as last drawn
local auctionOn = false      -- Use Auctionator Prices, as the remembered values were priced
local dbHooked = false       -- Auctionator's price-update callback registered

-- Per-slot facts for the scanned bags. A pass re-reads only the bags marked
-- dirty (by BAG_UPDATE, or all of them when the window comes back or a bag is
-- swapped), then picks the list from these facts. Settings, exclusions and
-- Junk Marker changes need a new pick but no re-read (Bags asks for its pick
-- through EllesmereUI._JunkItems.Refresh). recs[bag][slot] lives for the
-- session; scanSlots[bag] = how many slots the last read covered.
local recs, scanSlots, dirty = {}, {}, {}
local pending = {}          -- [itemID] = true: item data not cached yet
local failed  = {}          -- [itemID] = true: the client said the data will not load
local best, bestN = {}, 0   -- the cheapest listable records, in display order

-- How many stacks the window lists.
local function Limit()
    return Clamp(Get("itemCount"), 1, MAX_CELLS)
end

-------------------------------------------------------------------------------
--  Fonts (the Forever Essentials module font)
-------------------------------------------------------------------------------
local function SetJunkFont(fs, size) EllesmereUI.ApplyModuleFont(fs, nil, size, "essentials") end

local function NewText(parent, size, alpha)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetJunkFont(fs, size)
    fs:SetTextColor(1, 1, 1, alpha or 1)
    return fs
end

-------------------------------------------------------------------------------
--  Money text: cut to whole silver, so 1g15s12c reads "1g 15s". Copper only
--  shows while the value is under 1 gold ("15s 12c"). short: the largest coin
--  alone ("1g", "15s"), for a price too wide for its icon's slot.
-------------------------------------------------------------------------------
local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

local function FormatValue(copper, short)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        local out = BreakUpLargeNumbers(g) .. GOLD_ICON
        if s > 0 and not short then out = out .. " " .. s .. SILVER_ICON end
        return out
    end
    if s > 0 then
        local out = s .. SILVER_ICON
        if c > 0 and not short then out = out .. " " .. c .. COPPER_ICON end
        return out
    end
    return c .. COPPER_ICON
end

-------------------------------------------------------------------------------
--  Item rules
-------------------------------------------------------------------------------
-- A bag slot's item as this list sees it: its quality and stack value; nil
-- while its item data is not cached yet; false when it must never list (quest
-- items, battle pets, soulbound items with no vendor value, unknown quality).
local function Classify(info)
    local id = info.itemID
    local _, _, _, _, _, classID = GetItemInfoInstant(id)
    if classID == QUEST_CLASS or classID == BATTLEPET_CLASS then return false end
    local link = info.hyperlink
    if link and link:find("|Hbattlepet:", 1, true) then return false end
    local _, _, itemQuality, _, _, _, _, _, _, _, sell = GetItemInfo(id)
    if sell == nil then return nil end
    -- Fail closed: the higher of the slot's and the item's quality, and never an
    -- item that reports neither.
    local q = info.quality
    if q == nil or (itemQuality and itemQuality > q) then q = itemQuality end
    if q == nil then return false end
    -- No vendor value still wastes a slot, so it lists (at the top), but not
    -- when soulbound: those are keepers (Hearthstone, Marks of Honor).
    local noValue = info.hasNoValue or sell == 0
    if noValue and info.isBound then return false end
    return q, noValue and 0 or sell * (info.stackCount or 1)
end

-- Quest items never list, including ones that start a quest (same check as Bags).
local function IsQuestSlot(bag, slot)
    local qi = C_Container.GetContainerItemQuestInfo(bag, slot)
    return (qi and (qi.isQuestItem or qi.questID)) and true or false
end

local function InEquipmentSet(bag, slot)
    return C_Container.GetContainerItemEquipmentSetInfo(bag, slot) and true or false
end

-- Anything up to Maximum Quality, and anything marked with the Bags Junk
-- Marker: above Poor, IsJunk reports exactly the marks. cm is nil while Bags
-- is not loaded, and then nothing counts as marked.
local function Listable(q, id, maxQuality, cm)
    if q <= maxQuality then return true end
    return cm ~= nil and cm:IsJunk(id, q) == true
end

-------------------------------------------------------------------------------
--  Bag reads and the list
-------------------------------------------------------------------------------
local function ReadSlot(r)
    r.quality, r.pending, r.quest, r.inSet, r.total = nil, false, nil, nil, nil
    local info = GetContainerItemInfo(r.bag, r.slot)
    local id = info and info.itemID
    r.id = id or false
    if not id then return end
    r.count, r.icon, r.link = info.stackCount or 1, info.iconFileID, info.hyperlink
    local q, total = Classify(info)
    if q then
        r.quality, r.vendor, r.bound = q, total, info.isBound
    elseif q == nil then
        r.pending = true  -- its GET_ITEM_INFO_RECEIVED re-reads the bag
    end
end

-- Regular bags only: the reagent bag and specialty bags (quiver, ammo pouch,
-- soul bag) hold things this delete list must never offer. A family of 0 is
-- a general-purpose bag (the backpack included).
local function ReadBag(bag)
    dirty[bag] = nil
    local _, family = GetContainerNumFreeSlots(bag)
    local n = (family == 0) and GetContainerNumSlots(bag) or 0
    scanSlots[bag] = n
    local list = recs[bag]
    if not list then
        list = {}
        recs[bag] = list
    end
    for slot = 1, n do
        local r = list[slot]
        if not r then
            r = { bag = bag, slot = slot }
            list[slot] = r
        end
        ReadSlot(r)
    end
end

local function DirtyAll()
    for bag = 0, NUM_BAG_SLOTS do dirty[bag] = true end
end

-- An item finished loading: re-read the bags it sits in.
local function DirtyHolders(id)
    for bag = 0, NUM_BAG_SLOTS do
        local list = recs[bag]
        for slot = 1, scanSlots[bag] or 0 do
            local r = list[slot]
            if r.pending and r.id == id then
                dirty[bag] = true
                break
            end
        end
    end
end

-- A set edit or new prices fire no bag update: drop that remembered fact instead.
local function Forget(key)
    for bag = 0, NUM_BAG_SLOTS do
        local list = recs[bag]
        for slot = 1, scanSlots[bag] or 0 do list[slot][key] = nil end
    end
end

-- Soulbound stacks cannot be auctioned: they keep their vendor value.
local function StackValue(r)
    local each = auctionOn and not r.bound and r.link and module.AuctionPrice(r.link)
    return each and each * r.count or r.vendor
end

-- Cheapest first; ties keep bag order.
local function Better(a, b)
    if a.total ~= b.total then return a.total < b.total end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- Inserts r into the fixed best-N list holding n entries; returns the new count.
local function Offer(r, n, limit)
    if n < limit then
        n = n + 1
    elseif not Better(r, best[n]) then
        return n
    end
    local i = n
    while i > 1 and Better(r, best[i - 1]) do
        best[i] = best[i - 1]
        i = i - 1
    end
    best[i] = r
    return n
end

-- Picks the cheapest listable stacks from the read facts. The quest and set
-- checks and the value run only for items that would otherwise list, once per
-- read (set membership again after a set edit, the value after new prices).
local function Select(limit)
    local maxQuality = Get("maxQuality")
    local cm = _G.EUI_CategoryManager
    local ex = EllesmereUIDB.junkListExcluded
    wipe(pending)
    local n = 0
    for bag = 0, NUM_BAG_SLOTS do
        local list = recs[bag]
        for slot = 1, scanSlots[bag] or 0 do
            local r = list[slot]
            local id, q = r.id, r.quality
            if r.pending then
                if not failed[id] then pending[id] = true end
            elseif q and not (ex and ex[id]) and Listable(q, id, maxQuality, cm) then
                if r.quest == nil then r.quest = IsQuestSlot(bag, slot) end
                if not r.quest then
                    if r.inSet == nil then r.inSet = InEquipmentSet(bag, slot) end
                    if not r.inSet then
                        if r.total == nil then r.total = StackValue(r) end
                        n = Offer(r, n, limit)
                    end
                end
            end
        end
    end
    for i = n + 1, bestN do best[i] = nil end
    bestN = n
end

-------------------------------------------------------------------------------
--  Double-click guard: when a pass puts a different stack in the cell under the
--  cursor while Ctrl is held, that cell refuses Ctrl + Left Click until the
--  cursor enters it again or Ctrl is let go, so the second click of a double
--  click never deletes a stack the player has not seen.
-------------------------------------------------------------------------------
local function ClearSwapFlags()
    if swapCount == 0 then return end
    for i = 1, #cells do cells[i].swapped = nil end
    swapCount = 0
    ctrlWatch:UnregisterEvent("MODIFIER_STATE_CHANGED")
end

local function OnModifierChanged()
    if not IsControlKeyDown() then ClearSwapFlags() end
end
ctrlWatch:SetScript("OnEvent", OnModifierChanged)

local function FlagSwap(cell)
    if cell.swapped then return end
    cell.swapped = true
    swapCount = swapCount + 1
    if swapCount == 1 then ctrlWatch:RegisterEvent("MODIFIER_STATE_CHANGED") end
end

local function UnflagSwap(cell)
    if not cell.swapped then return end
    cell.swapped = nil
    swapCount = swapCount - 1
    if swapCount == 0 then ctrlWatch:UnregisterEvent("MODIFIER_STATE_CHANGED") end
end

-------------------------------------------------------------------------------
--  Passes
-------------------------------------------------------------------------------
local Refresh  -- forward

-- Every pass goes through here: any number of triggers in one frame (bag
-- updates, item loads, settings, an exclude, a Junk Marker change) collapse
-- into a single Refresh.
local refreshQueued = false
local function RunQueuedRefresh()
    refreshQueued = false
    Refresh()
end
local function RequestRefresh()
    if refreshQueued or not active then return end
    refreshQueued = true
    C_Timer.After(0, RunQueuedRefresh)
end

-------------------------------------------------------------------------------
--  Delete and exclude
-------------------------------------------------------------------------------
-- The slot still holds the stack the player chose and it still qualifies: same
-- item and count, not locked, no better than the quality they saw, and still no
-- quest item, battle pet, keeper or equipment-set item.
local function StillJunk(bag, slot, id, count, maxQuality)
    local info = GetContainerItemInfo(bag, slot)
    if not info or info.itemID ~= id or info.isLocked or (info.stackCount or 1) ~= count then
        return false
    end
    local q = Classify(info)
    if not q or q > maxQuality then return false end
    return not IsQuestSlot(bag, slot) and not InEquipmentSet(bag, slot)
end

-- DeleteCursorItem needs a hardware event, and the game refuses it from a
-- confirmation popup's click: this runs only inside the stack's own Ctrl +
-- Left Click. Never in combat or with anything already on the cursor.
local function DeleteStack(bag, slot, id, count, maxQuality)
    if InCombatLockdown() or GetCursorInfo() then return end
    if not StillJunk(bag, slot, id, count, maxQuality) then return end
    C_Container.PickupContainerItem(bag, slot)
    local kind, cursorID = GetCursorInfo()
    if kind == "item" and cursorID == id then
        DeleteCursorItem()
    elseif CursorHasItem() then
        ClearCursor()
    end
end

local ShowCellTooltip  -- forward (Cells)

local function CloseConfirm()
    if not confirmHandle then return end
    EllesmereUI:CloseConfirmPopup(confirmHandle)
    confirmHandle = nil
    if not armedCell then eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED") end
end

-- A stack that must be confirmed is armed first (white and green stacks above
-- Delete Without Confirming by their first Ctrl + Left Click, Rare and better by
-- the typed confirmation); the next Ctrl + Left Click on it deletes. Arming
-- holds for ARM_SECS and for that stack only: a change to the cell, combat or
-- the time running out ends it.
local ARM_SECS = 6

local function Disarm()
    local cell = armedCell
    if not cell then return end
    armedCell = nil
    cell.armedUntil = nil
    cell._arm:Hide()
    if not confirmHandle then eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED") end
    if GameTooltip:IsOwned(cell) then ShowCellTooltip(cell) end
end

local function Arm(cell)
    Disarm()
    armedCell = cell
    local untilT = GetTime() + ARM_SECS
    cell.armedUntil = untilT
    cell._arm:Show()
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    if GameTooltip:IsOwned(cell) then ShowCellTooltip(cell) end
    C_Timer.After(ARM_SECS, function()
        if armedCell == cell and cell.armedUntil == untilT then Disarm() end
    end)
end

-- Rare or better also needs the delete word typed, as the game's own delete
-- does; confirming arms the stack for its final Ctrl + Left Click.
local function AskDelete(cell)
    CloseConfirm()
    local bag, slot, id, count, q = cell.bag, cell.slot, cell.id, cell.count, cell.quality
    local label = count > 1 and (cell.link .. " x" .. count) or cell.link
    local handle
    handle = EllesmereUI:ShowConfirmPopup({
        title         = EllesmereUI.L("Delete Junk Item"),
        message       = DELETE_ITEM:format(label) .. "\n\n"
                        .. EllesmereUI.L("Then Ctrl + Left Click the item again to delete it."),
        confirmText   = DELETE,
        cancelText    = CANCEL,
        typeToConfirm = DELETE_ITEM_CONFIRM_STRING,
        onConfirm = function()
            if confirmHandle ~= handle then return end
            CloseConfirm()
            if cell.id == id and cell.bag == bag and cell.slot == slot and cell.count == count then
                Arm(cell)
            end
        end,
        onCancel = function()
            if confirmHandle == handle then CloseConfirm() end
        end,
    })
    confirmHandle = handle
    -- Closed at combat start: the popup's key handling is restricted in combat.
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function Exclude(id)
    local ex = EllesmereUIDB.junkListExcluded
    if not ex then
        ex = {}
        EllesmereUIDB.junkListExcluded = ex
    end
    ex[id] = true
    RequestRefresh()
end

-------------------------------------------------------------------------------
--  Cells
-------------------------------------------------------------------------------
ShowCellTooltip = function(cell)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(cell.bag, cell.slot)
    GameTooltip:AddLine(" ")
    -- No deletes in combat: the hint greys out there.
    if InCombatLockdown() then
        GameTooltip:AddLine(EllesmereUI.L("Ctrl + Left Click: delete"), 0.5, 0.5, 0.5)
    elseif armedCell == cell then
        GameTooltip:AddLine(EllesmereUI.L("Ctrl + Left Click again to delete"), 1, 0.15, 0.15)
    else
        GameTooltip:AddLine(EllesmereUI.L("Ctrl + Left Click: delete"), 1, 0.3, 0.3)
    end
    GameTooltip:AddLine(EllesmereUI.L("Middle Click: never show this item"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnCellClick(self, button)
    local id = self.id
    if not id then return end
    if button == "MiddleButton" then
        Exclude(id)
        return
    end
    if button ~= "LeftButton" or not IsControlKeyDown() then return end
    if self.swapped or InCombatLockdown() or GetCursorInfo() then return end
    local q = self.quality
    -- Rare and better always need the typed confirmation, whatever the setting says.
    if (q < RARE and q <= Get("oneClickQuality"))
       or (armedCell == self and GetTime() <= (self.armedUntil or 0)) then
        Disarm()
        DeleteStack(self.bag, self.slot, id, self.count, q)
    elseif q >= RARE then
        AskDelete(self)
    else
        Arm(self)
    end
end

local function OnCellEnter(self)
    UnflagSwap(self)
    if self.id then ShowCellTooltip(self) end
end

local function OnCellLeave(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function AcquireCell(i)
    local b = cells[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    b:SetScript("OnClick", OnCellClick)
    b:SetScript("OnEnter", OnCellEnter)
    b:SetScript("OnLeave", OnCellLeave)
    b:Hide()

    b._icon = b:CreateTexture(nil, "ARTWORK")
    b._icon:SetAllPoints()
    b._icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
    -- Red wash while the stack is armed for its confirming click.
    b._arm = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b._arm:SetAllPoints()
    b._arm:SetColorTexture(1, 0.1, 0.1, 0.45)
    b._arm:Hide()
    PP.CreateBorder(b, 0, 0, 0, 1, 1, "OVERLAY", 7)

    b._count = b:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyIconTextFont(b._count, EllesmereUI.GetFontPath("essentials"), 11, "essentials")
    b._count:SetTextColor(1, 1, 1, 1)
    b._count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)

    b._price = NewText(b, 10)

    cells[i] = b
    return b
end

-- Repaints one cell only where its stack changed.
local function PaintCell(cell, r)
    if not r then
        if cell.id then
            if armedCell == cell then Disarm() end
            if GameTooltip:IsOwned(cell) then GameTooltip:Hide() end
            UnflagSwap(cell)
            cell.id = nil
            cell:Hide()
        end
        return
    end
    local moved = r.id ~= cell.id or r.bag ~= cell.bag or r.slot ~= cell.slot
    local changed = moved or r.count ~= cell.count
    -- An armed stack that left the cell (or changed size) is not the one confirmed.
    if changed and armedCell == cell then Disarm() end
    if r.count ~= cell.count then cell._count:SetText(r.count > 1 and r.count or "") end
    if r.icon ~= cell.icon then cell._icon:SetTexture(r.icon) end
    -- A price wider than its slot shows its largest coin alone, so prices never collide.
    if r.total ~= cell.total or cell.fitW ~= priceFitW then
        local fs = cell._price
        fs:SetText(FormatValue(r.total))
        if fs:GetStringWidth() > priceFitW then fs:SetText(FormatValue(r.total, true)) end
        cell.fitW = priceFitW
    end
    -- A different stack under the cursor while Ctrl is held: see the double-click guard.
    if moved and cell.id and IsControlKeyDown() and cell:IsMouseOver() then FlagSwap(cell) end
    cell.id, cell.bag, cell.slot, cell.count = r.id, r.bag, r.slot, r.count
    cell.icon, cell.total, cell.quality, cell.link = r.icon, r.total, r.quality, r.link
    if not cell:IsShown() then cell:Show() end
    if changed and GameTooltip:IsOwned(cell) then ShowCellTooltip(cell) end
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
-- The centre snaps to the pixel grid for the window's size.
local function ApplyPosition()
    F.Place(frame, true)
end

-- Width of the widest title, measured once ("Bag Slots - 888/888"), so the window
-- does not change width as the counts do.
local titleW = 0
local function TitleWidth()
    if titleW == 0 then
        probeFS:SetFormattedText(EllesmereUI.L("Bag Slots - %d/%d"), 888, 888)
        local w = probeFS:GetStringWidth() or 0
        if w >= 1 then titleW = math.ceil(w) end
    end
    return titleW
end

-- The window is its content, with no margin (it draws no art): the row of icons
-- (or the title, when it is shown and wider), the title row when shown, then
-- the icons and their prices. Icon Spacing is the gap between icons.
local function WindowSize(limit)
    local iconSz = Get("iconSize")
    local rowW = limit * iconSz + (limit - 1) * Get("iconSpacing")
    local titled = Get("showFreeSlots") and true or false
    local w = titled and math.max(rowW, TitleWidth()) or rowW
    return PP.Snap(w), PP.Snap((titled and TITLE_H or 0) + iconSz + 3 + PRICE_H), rowW
end

local lay = {}  -- the geometry last applied
local function Layout(limit)
    local iconSz = Get("iconSize")
    local pitch = iconSz + Get("iconSpacing")
    local top = Get("priceSide") == "top"
    local titled = Get("showFreeSlots") and true or false
    local mult = PP.mult  -- the pixel grid the size and the centre snap to (moves with the UI scale)
    if iconSz == lay.icon and pitch == lay.pitch and top == lay.top
        and limit == lay.limit and titled == lay.titled and mult == lay.mult then
        return
    end
    lay.icon, lay.pitch, lay.top, lay.limit, lay.titled, lay.mult = iconSz, pitch, top, limit, titled, mult
    -- each price may use its icon's width plus the spacing (less 2 px of air) before it is shortened
    priceFitW = pitch - 2
    local w, h, rowW = WindowSize(limit)
    frame:SetSize(w, h)
    -- The row centred in the window (wider only for the title).
    local x0 = math.floor((w - rowW) / 2 + 0.5)
    local titleH = titled and TITLE_H or 0
    local y0 = -(titleH + (top and (PRICE_H + 3) or 0))
    for i = 1, limit do
        local cell = AcquireCell(i)
        cell:SetSize(iconSz, iconSz)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT", x0 + (i - 1) * pitch, y0)
        cell._price:ClearAllPoints()
        if top then
            cell._price:SetPoint("BOTTOM", cell, "TOP", 0, 3)
        else
            cell._price:SetPoint("TOP", cell, "BOTTOM", 0, -3)
        end
    end
    emptyFS:ClearAllPoints()
    emptyFS:SetPoint("CENTER", frame, "CENTER", 0, -titleH / 2)
    -- The centre snap follows the size; Unlock Mode owns the spot while it is open.
    if not EllesmereUI._unlockActive then ApplyPosition() end
end

local function CountBagSlots()
    -- Same bags the list reads: regular bags only.
    local free, total = 0, 0
    for bag = 0, NUM_BAG_SLOTS do
        local numFree, family = GetContainerNumFreeSlots(bag)
        if family == 0 then
            free = free + (numFree or 0)
            total = total + GetContainerNumSlots(bag)
        end
    end
    return free, total
end

local function UpdateTitle()
    if not Get("showFreeSlots") then
        titleFS:Hide()
        return
    end
    local free, total = CountBagSlots()
    if free ~= lastFree or total ~= lastTotal then
        lastFree, lastTotal = free, total
        titleFS:SetFormattedText(EllesmereUI.L("Bag Slots - %d/%d"), free, total)
    end
    titleFS:Show()
end

-------------------------------------------------------------------------------
--  Events and the window
-------------------------------------------------------------------------------
local function OnEvent(_, event, arg1, arg2)
    if event == "BAG_UPDATE" then
        if arg1 and arg1 >= 0 and arg1 <= NUM_BAG_SLOTS then dirty[arg1] = true end
        return  -- BAG_UPDATE_DELAYED ends the burst
    elseif event == "PLAYER_REGEN_DISABLED" then
        CloseConfirm()
        Disarm()
        return
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if not pending[arg1] then return end
        pending[arg1] = nil
        if arg2 == false then
            failed[arg1] = true
        else
            DirtyHolders(arg1)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        CloseConfirm()  -- the stack a confirmation names may have moved
    elseif event == "BAG_CONTAINER_UPDATE" then
        DirtyAll()
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        Forget("inSet")
    end
    RequestRefresh()
end
eventFrame:SetScript("OnEvent", OnEvent)

local function BuildFrame()
    if frame then return end
    frame = CreateFrame("Frame", "EllesmereUIJunkList", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- No window art: the title row, icons and prices. Nothing but the cells
    -- takes the mouse, so the window is click-through; moving it is Unlock
    -- Mode's job.
    local hdrBg = CreateFrame("Frame", nil, frame)
    hdrBg:SetPoint("TOPLEFT"); hdrBg:SetPoint("TOPRIGHT"); hdrBg:SetHeight(TITLE_H)

    titleFS = NewText(frame, 11)
    titleFS:SetPoint("LEFT", hdrBg, "LEFT", 0, 0)

    -- Empty frame over the header row; kept because the title may not draw
    -- without it on WoW Forever.
    local hdrCover = CreateFrame("Frame", nil, frame)
    hdrCover:SetPoint("TOPLEFT", hdrBg, "TOPLEFT")
    hdrCover:SetPoint("BOTTOMRIGHT", hdrBg, "BOTTOMRIGHT")

    emptyFS = NewText(frame, 11, 0.5)
    emptyFS:SetText(EllesmereUI.L("No junk items"))

    -- measures the widest title (TitleWidth)
    probeFS = NewText(frame, 11)
    probeFS:Hide()
end

-------------------------------------------------------------------------------
--  Auctionator prices: a scan that updates them re-prices the list. The API
--  has no unregister, so the callback is registered once and checks the option.
-------------------------------------------------------------------------------
local function OnPricesUpdated()
    if not (auctionOn and active) then return end
    Forget("total")
    RequestRefresh()
end

local function HookPriceUpdates()
    local api = module.AuctionAPI()
    if not (api and api.RegisterForDBUpdate) then return end
    dbHooked = true
    pcall(api.RegisterForDBUpdate, "EllesmereUI", OnPricesUpdated)
end

-------------------------------------------------------------------------------
--  Refresh: re-read the dirty bags, pick the list, repaint what changed
-------------------------------------------------------------------------------
Refresh = function()
    if not active then return end
    local ah = Get("auctionPrices") == true
    if ah ~= auctionOn then
        auctionOn = ah
        Forget("total")
    end
    if ah and not dbHooked then HookPriceUpdates() end
    for bag = 0, NUM_BAG_SLOTS do
        if dirty[bag] then ReadBag(bag) end
    end
    local limit = Limit()
    Select(limit)
    Layout(limit)
    for i = 1, #cells do PaintCell(cells[i], best[i]) end
    UpdateTitle()
    emptyFS:SetShown(bestN == 0)
    -- GET_ITEM_INFO_RECEIVED only while an item is still loading.
    local want = next(pending) ~= nil
    if want ~= itemInfoOn then
        itemInfoOn = want
        if want then
            eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        else
            eventFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        end
    end
    frame:Show()
end

-------------------------------------------------------------------------------
--  Visibility and settings
-------------------------------------------------------------------------------
-- Active = shown, with its events registered. While enabled but hidden by the
-- visibility setting it costs only that setting's check.
local function SetActive(on)
    if on == active then return end
    active = on
    if on then
        eventFrame:RegisterEvent("BAG_UPDATE")
        eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        eventFrame:RegisterEvent("BAG_CONTAINER_UPDATE")
        eventFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
        DirtyAll()  -- nothing was watched while inactive
        RequestRefresh()
        return
    end
    CloseConfirm()
    eventFrame:UnregisterAllEvents()
    itemInfoOn = false
    wipe(pending)
    ClearSwapFlags()
    for i = 1, #cells do
        if GameTooltip:IsOwned(cells[i]) then GameTooltip:Hide() end
    end
    frame:Hide()
end

-- The shared visibility setting: re-checked by the visibility dispatcher on its
-- own edges (combat, group, zone...) and after every settings change.
local function UpdateVisibility()
    local show = (frame and Enabled() and EllesmereUI.EvalVisibility(Read()) == true) and true or false
    local watch = show and Get("onlyLowBagSpace") == true
    if watch ~= bagWatching then
        bagWatching = watch
        if watch then
            bagSpaceWatch:RegisterEvent("BAG_UPDATE_DELAYED")
            bagSpaceWatch:RegisterEvent("BAG_CONTAINER_UPDATE")
        else
            bagSpaceWatch:UnregisterAllEvents()
        end
    end
    if watch then show = CountBagSlots() < Get("freeSlotThreshold") end
    SetActive(show)
end
bagSpaceWatch:SetScript("OnEvent", UpdateVisibility)

local function Apply()
    if Enabled() then
        BuildFrame()
        if not visRegistered then
            visRegistered = true
            EllesmereUI.RegisterVisibilityUpdater(UpdateVisibility)
        end
        -- Sized and placed even while the visibility setting hides it, so Unlock
        -- Mode always has a mover to show. The fonts may have changed: the title
        -- is measured again and every price fitted again.
        titleW = 0
        wipe(lay)
        for i = 1, #cells do cells[i].fitW = nil end
        Layout(Limit())
        if not EllesmereUI._unlockActive then ApplyPosition() end
    elseif visRegistered then
        visRegistered = false
        EllesmereUI.UnregisterVisibilityUpdater(UpdateVisibility)
    end
    UpdateVisibility()
    RequestRefresh()  -- settings may change what lists and how it looks
end

-- Entry points for the options page and Bags.
EllesmereUI._JunkItems = {
    Get = Get,
    Read = Read,
    Cfg = F.Cfg,
    Apply = Apply,
    -- Every item middle-clicked away can list again.
    ClearExclusions = function()
        EllesmereUIDB.junkListExcluded = nil
        RequestRefresh()
    end,
    -- Bags: a Junk Marker mark came or went, or the marker was switched. Does
    -- nothing while the window is inactive (coming back re-reads every bag).
    Refresh = RequestRefresh,
}

F.Start(Apply, {
    key = "EUI_JunkList", label = "Junk Items", order = 729,
    -- Apply builds and lays out the window whenever it is on.
    frame = function() return frame end,
    -- Follows Items Shown, the icon settings and Show Empty Bag Slots, so
    -- unlock mode moves the window but never resizes it.
    size = function()
        if frame then return frame:GetWidth(), frame:GetHeight() end
        local iconSz, n = Get("iconSize"), Limit()
        return n * iconSz + (n - 1) * Get("iconSpacing"), iconSz + 3 + PRICE_H
    end,
    snap = true, noAnchorTarget = true, noSizeMatchTarget = true,
})
