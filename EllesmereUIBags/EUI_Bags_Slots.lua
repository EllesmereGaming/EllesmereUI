if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Slots.lua
--
--  Drag-to-drop, the slot factory, the fast font and icon-zoom updates,
--  bind text, border color, the item overlay icons and the Item Icons
--  takeover adapter.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local GetItemInfo = C_Item.GetItemInfo
local EUI = EllesmereUI

local _bankRouted, BP, GetFont, IsGearItem = I._bankRouted, I.BP, I.GetFont, I.IsGearItem
local NormalizePinKey, SLOT_SIZE, bagSlots = I.NormalizePinKey, I.SLOT_SIZE, I.bagSlots
local itemSlots, reagentSlots = I.itemSlots, I.reagentSlots
local CreateInsetBorder, SetInsetBorderColor = I.CreateInsetBorder, I.SetInsetBorderColor

-------------------------------------------------------------------------------
--  Drag-to-drop: template handles pickup, we handle drop on mouse release
-------------------------------------------------------------------------------
local _itemDragFrame = CreateFrame("Frame")
_itemDragFrame:Hide()
_itemDragFrame:SetScript("OnUpdate", function(self)
    if IsMouseButtonDown("LeftButton") then return end
    self:Hide()
    -- Blizzard's OnReceiveDrag (bars/equipment) fires BEFORE OnUpdate in the same
    -- frame; if it consumed the item, GetCursorInfo returns nil.
    if GetCursorInfo() ~= "item" then return end
    -- Cursor into each button's OWN coordinate space: GetRect() is in effective-scale
    -- units, so divide by btn:GetEffectiveScale() (not UIParent's -- matches only at scale 1.0).
    local rawCx, rawCy = GetCursorPosition()
    for _, btn in pairs(itemSlots) do
        if btn:IsShown() and btn:GetParent():IsShown() then
            local es = btn:GetEffectiveScale()
            local cx, cy = rawCx / es, rawCy / es
            local l, b, w, h = btn:GetRect()
            if l and b and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                local destBag = btn:GetParent():GetID()
                local destSlot = btn:GetID()
                if destSlot > 0 then
                    C_Container.PickupContainerItem(destBag, destSlot)
                end
                return
            end
        end
    end
    local bankFrame = _G.EUI_BankFrame
    local bankSlots = bankFrame and bankFrame._bankSlots
    if bankSlots and bankFrame:IsVisible() then
        for _, btn in pairs(bankSlots) do
            if btn:IsShown() and btn:GetParent():IsShown() then
                local es = btn:GetEffectiveScale()
                local cx, cy = rawCx / es, rawCy / es
                local l, b, w, h = btn:GetRect()
                if l and b and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                    local destBag = btn:GetParent():GetID()
                    local destSlot = btn:GetID()
                    if destSlot > 0 then
                        C_Container.PickupContainerItem(destBag, destSlot)
                    end
                    return
                end
            end
        end
    end
    -- Not over a bag/bank slot: leave item on cursor (bars/equipment already handled by OnReceiveDrag).
end)

-------------------------------------------------------------------------------
--  Slot Factory
-------------------------------------------------------------------------------
-- Middle-click: unassign an assigned item, else toggle its pin. Shared by the
-- grid slots and the list rows (ns.SlotMiddleClick).
local function SlotMiddleClick(self, button)
    if button ~= "MiddleButton" then return end
    local bagID = self:GetParent():GetID()
    local slotID = self:GetID()
    if not bagID or not slotID or slotID == 0 then return end
    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    if not info or not info.itemID then return end
    -- If this item has a custom category assignment, middle-click unassigns it
    local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
    if assignments and assignments[info.itemID] then
        EUI_CategoryManager:UnassignItem(info.itemID)
        if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
        return
    end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
    local pinned = EllesmereUIDB.bagPinnedItems
    local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
    local isGear = IsGearItem(itemLink)
    -- Pin key is the normalized itemID+bonusIDs identity (distinguishes
    -- upgrade tracks -- see NormalizePinKey in EllesmereUIBags.lua); pinKey == info.itemID
    -- when no link is available. A legacy itemID-keyed pin (written before
    -- this fix, conflating every track) is adopted into `cur` once and
    -- then always cleared here, regardless of which specific track was
    -- clicked -- there's no way to know which track a legacy entry
    -- originally meant, so the honest self-heal is "this interaction
    -- resolves the ambiguity," not "this interaction guesses which track
    -- it was." Re-pin afterward to set a precise, track-specific entry.
    local pinKey = NormalizePinKey(itemLink, info.itemID)
    local legacyCur = pinned[info.itemID] or 0
    local cur = pinned[pinKey] or 0
    if legacyCur > 0 and cur == 0 then cur = legacyCur end
    pinned[info.itemID] = nil
    if isGear then
        -- Gear: per-stack count toggle
        if cur > 0 then
            cur = cur - 1
            pinned[pinKey] = cur > 0 and cur or nil
        else
            pinned[pinKey] = cur + 1
        end
    else
        -- Non-gear: pin/unpin all stacks at once
        if cur > 0 then
            pinned[pinKey] = nil
        else
            pinned[pinKey] = 999
        end
    end
    if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
end
ns.SlotMiddleClick = SlotMiddleClick

-- Right-click deposit routing: with a bank tab selected, queue the transfer instead of
-- Blizzard's default first-free-slot routing (queue handles locked items/allocation so rapid
-- clicks don't collide). State lives in an EXTERNAL weak table, never on the frame: PreClick
-- custom keys taint the secure chain -> ADDON_ACTION_FORBIDDEN. Shared by grid slots and list rows.
function ns.BankRoutePreClick(self, button)
    if button ~= "RightButton" then return end
    local bank = _G.EUI_BankFrame
    if not bank or not bank:IsVisible() then return end
    local targetBag = bank:GetSelectedTabBagID()
    if not targetBag then return end
    local srcBag = self:GetParent():GetID()
    local srcSlot = self:GetID()
    if not srcBag or not srcSlot or srcSlot == 0 then return end
    local info = C_Container.GetContainerItemInfo(srcBag, srcSlot)
    if not info then return end
    bank:QueueTransfer(srcBag, srcSlot)
    _bankRouted[self] = true
end
function ns.BankRouteOnClick(self, button)
    if button == "RightButton" and _bankRouted[self] then
        _bankRouted[self] = nil
        ClearCursor()
    end
end

local function GetOrCreateReagentSlot(idx)
    if reagentSlots[idx] then return reagentSlots[idx] end
    -- Never create a secure button during combat (taint). See GetOrCreateSlot.
    if InCombatLockdown() then EUI_Bags._poolShort = true; return nil end

    local slotParent = CreateFrame("Frame", nil, EUI_BagsReagent)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    ns.PinItemButton(btn, EUI_BagsReagent)
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- Methods only: writing properties onto Blizzard template sub-objects taints
    if btn.NewItemTexture then btn.NewItemTexture:Hide(); btn.NewItemTexture:SetAlpha(0) end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide(); btn.BattlepayItemTexture:SetAlpha(0) end
    if btn.flash then btn.flash:Hide(); btn.flash:SetAlpha(0) end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end

    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    if btn.icon then
        local z = BP().bagItemIconZoom or 0.08
        btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        btn.icon:ClearAllPoints()
        btn.icon:SetAllPoints(btn)
    end

    local ht = btn:GetHighlightTexture()
    if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\highlight-3.png")
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints(); pt:SetAllPoints(btn)
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
    end

    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end

    if btn.icon and btn.IconMask then
        btn.icon:RemoveMaskTexture(btn.IconMask)
        btn.IconMask:Hide()
        btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints()
        btn.IconMask:SetSize(0.001, 0.001)
    end

    if btn.Cooldown then
        local cdText = btn.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            EllesmereUI.ApplyIconTextFont(cdText, GetFont(), 11, "bags")
        end
    end

    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    -- Text overlay: above the cooldown swipe, so counts and item levels stay visible
    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(btn:GetFrameLevel() + 3)
    btn._textOverlay = textOverlay

    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        EllesmereUI.ApplyIconTextFont(countFS, GetFont(), BP().bagCountFontSize or 11, "bags")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    local fontSize = BP().itemlevelFontSize or 12
    btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, fontSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.ItemLevelText:SetText("")

    btn:HookScript("PostClick", function(self)
        EUI_Bags.ShowStackSplitter(self, ns.SplitTargetBags(5), EUI_BagsReagent)
    end)

    reagentSlots[idx] = btn
    return btn
end

-- Builds the secure item-button pools up to the current bag sizes (main pool = bags 0-5,
-- reagent pool = bag 5), creating only the slots that do not exist yet and hiding only
-- those. Stops at the first slot the combat guard refuses, or once msBudget (ms, optional)
-- is spent; either way EUI_Bags._poolShort stays set so combat end tops the pool up.
-- Returns true when both pools are complete. Callers: the loading-screen pass on a
-- /reload in combat, StartAddon, and PLAYER_REGEN_ENABLED.
function EUI_Bags:WarmSlotPool(msBudget)
    local t0 = msBudget and debugprofilestop()
    local total = 0
    for bag = 0, 5 do
        total = total + (C_Container.GetContainerNumSlots(bag) or 0)
    end
    -- Only the pool for the latched display mode is built; mode unknown
    -- (profile not loaded yet) builds neither and retries at combat end.
    local listMode = EUI_Bags.IsListMode()
    if listMode == nil then
        EUI_Bags._poolShort = true
    elseif listMode then
        -- Pinned and Recent repeat their items as extra rows
        local pinned = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
        if pinned then for _ in pairs(pinned) do total = total + 1 end end
        if EUI_Bags._recentItems then
            for _ in pairs(EUI_Bags._recentItems) do total = total + 1 end
        end
        if not ns.WarmListRows(total, t0, msBudget) then return false end
    else
        for i = 1, total do
            if not itemSlots[i] then
                local b = ns.GetOrCreateSlot(i)
                if not b then EUI_Bags._poolShort = true; return false end
                b:GetParent():Hide()
                if t0 and debugprofilestop() - t0 > msBudget then
                    EUI_Bags._poolShort = true
                    return false
                end
            end
        end
    end
    for i = 1, (C_Container.GetContainerNumSlots(5) or 0) do
        if not reagentSlots[i] then
            local b = GetOrCreateReagentSlot(i)
            if not b then EUI_Bags._poolShort = true; return false end
            b:GetParent():Hide()
            if t0 and debugprofilestop() - t0 > msBudget then
                EUI_Bags._poolShort = true
                return false
            end
        end
    end
    return true
end

local function GetOrCreateBagSlot(idx)
    if bagSlots[idx] then return bagSlots[idx] end
    local slotParent = CreateFrame("Frame", nil, EUI_BagsWindow)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("Button", nil, slotParent)
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    local z = BP().bagItemIconZoom or 0.08
    btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    btn.icon:SetAllPoints(btn)
    btn.Count = btn:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyIconTextFont(btn.Count, GetFont(), BP().bagCountFontSize or 11, "bags")
    btn.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.Count:SetTextColor(1, 1, 1)
    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    -- Drag-and-drop: equip a bag into this slot, or swap it with the
    -- equipped bag on the cursor
    local function TrySwapBag(self)
        if InCombatLockdown() then return end
        if not CursorHasItem() then return end
        local bagID = self:GetID()
        if bagID == 0 then return end  -- can't replace backpack
        PutItemInBag(C_Container.ContainerIDToInventoryID(bagID))
    end
    btn:SetScript("OnReceiveDrag", TrySwapBag)
    btn:HookScript("OnClick", TrySwapBag)
    -- Drag an equipped bag out of its slot (drop it on another slot to swap)
    btn:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local bagID = self:GetID()
        if bagID == 0 then return end  -- the backpack can't be moved
        PickupBagFromSlot(C_Container.ContainerIDToInventoryID(bagID))
    end)

    -- Tooltip: bag name + used/total slots (computed live on hover)
    btn:SetScript("OnEnter", function(self)
        SetInsetBorderColor(self, 1, 1, 1, 1)
        local bagIdx = self:GetID()
        local bName
        if bagIdx == 0 then
            bName = "Backpack"
        else
            local bLink = GetInventoryItemLink("player", C_Container.ContainerIDToInventoryID(bagIdx))
            bName = bLink and GetItemInfo(bLink) or EUI.Lf("Bag %1$d", bagIdx)
        end
        local bTotal = C_Container.GetContainerNumSlots(bagIdx)
        local bFree = C_Container.GetContainerNumFreeSlots(bagIdx)
        local tip = bName
        if bTotal > 0 then tip = tip .. "  (" .. (bTotal - bFree) .. "/" .. bTotal .. ")" end
        EUI.ShowWidgetTooltip(self, tip)
    end)
    btn:SetScript("OnLeave", function(self)
        SetInsetBorderColor(self, self._bdrR, self._bdrG, self._bdrB, 1)
        EUI.HideWidgetTooltip()
    end)

    bagSlots[idx] = btn
    return btn
end

-------------------------------------------------------------------------------
--  Fast font size update (options sliders): no full RefreshInventory
-------------------------------------------------------------------------------
local function RefreshTextSizes()
    local fontPath = GetFont()
    local countSize = BP().bagCountFontSize or 11
    local ilvlSize = BP().itemlevelFontSize or 12
    local bindTypeSize = BP().bagBindTypeFontSize or 11
    for _, btn in pairs(itemSlots) do
        if btn.Count then EllesmereUI.ApplyIconTextFont(btn.Count, fontPath, countSize, "bags") end
        if btn.ItemLevelText then btn.ItemLevelText:SetFont(fontPath, ilvlSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.KeystoneText then btn.KeystoneText:SetFont(fontPath, countSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.KeystoneDungeonText then btn.KeystoneDungeonText:SetFont(fontPath, math.max(countSize - 2, 7), (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.BindTypeText then btn.BindTypeText:SetFont(fontPath, bindTypeSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.SetNameText then btn.SetNameText:SetFont(fontPath, BP().bagSetNameFontSize or 9, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
    end
    for _, btn in pairs(reagentSlots) do
        if btn.Count then EllesmereUI.ApplyIconTextFont(btn.Count, fontPath, countSize, "bags") end
        if btn.ItemLevelText then btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, ilvlSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
    end
end
EUI_Bags.RefreshTextSizes = RefreshTextSizes

-------------------------------------------------------------------------------
--  Fast icon-zoom update (options zoom cog): no full RefreshInventory
-------------------------------------------------------------------------------
local function RefreshIconZoom()
    local z = BP().bagItemIconZoom or 0.08
    for _, btn in pairs(itemSlots) do
        if btn.icon then btn.icon:SetTexCoord(z, 1 - z, z, 1 - z) end
    end
    for _, btn in pairs(reagentSlots) do
        if btn.icon then btn.icon:SetTexCoord(z, 1 - z, z, 1 - z) end
    end
    for _, btn in pairs(bagSlots) do
        if btn.icon then btn.icon:SetTexCoord(z, 1 - z, z, 1 - z) end
    end
end
EUI_Bags.RefreshIconZoom = RefreshIconZoom

-------------------------------------------------------------------------------
--  Bind type text (shared by bags and bank render paths)
-------------------------------------------------------------------------------
-- The label and color of EllesmereUI.BindLabel; empty for any other bind type
function EUI_Bags.SetBindTypeText(fs, isWuE, bindType, quality)
    local text, c = EUI.BindLabel(isWuE, bindType, quality)
    if not text then
        fs:SetText("")
        return
    end
    fs:SetText(text)
    if c then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(1, 1, 1) end
end

-------------------------------------------------------------------------------
--  Bind keyword search (shared by bags and bank): typing exactly BoP / BoE /
--  WuE (any case) filters by bind type instead of the native tooltip search.
-------------------------------------------------------------------------------
-- In a block so the main chunk's local count (close to the 200 cap) stays put.
do
    local BIND_KEYWORDS = { bop = true, boe = true, wue = true }
    -- One location reused for every slot: a keyword pass visits every item on
    -- each refresh, and CreateFromBagAndSlot builds a new mixin table per call.
    local loc = ItemLocation:CreateEmpty()

    -- The game applies a search after SetItemSearch returns and reports the
    -- result with INVENTORY_SEARCH_UPDATE, the event Blizzard's own bags repaint
    -- on, so the open windows repaint there, never at once (they would still
    -- show the previous search). Listened to from a search change until the
    -- search is clear again or no window shows (the next open reads the
    -- settled result).
    local searchWatch
    local function OnSearchUpdate(self)
        local bank = _G.EUI_BankFrame
        if EUI_Bags._appliedSearch == "" or not (EUI_Bags:IsVisible() or (bank and bank:IsVisible())) then
            self:UnregisterEvent("INVENTORY_SEARCH_UPDATE")
        end
        if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
        if BP().detachReagentBag and EUI_BagsReagent:IsVisible() then EUI_BagsReagent:RefreshInventory() end
        ns.RefreshOpenBank()
    end

    -- The game's item search is client-wide and has no getter, so this is its
    -- one writer and keeps the text it last applied: a search box asking for
    -- that same text has nothing to change or repaint.
    function EUI_Bags.SetSearchText(text)
        local k = strtrim(text or ""):lower()
        EUI_Bags._bindKeyword = BIND_KEYWORDS[k] and k or nil
        EUI_Bags._appliedSearch = text
        if not searchWatch then
            searchWatch = CreateFrame("Frame")
            searchWatch:SetScript("OnEvent", OnSearchUpdate)
        end
        searchWatch:RegisterEvent("INVENTORY_SEARCH_UPDATE")
        C_Container.SetItemSearch(text)
    end

    -- Text changes of a search box (the bags and the bank each have one):
    -- typing applies SEARCH_DEBOUNCE seconds after the last keystroke, so a
    -- burst of keystrokes repaints once; any other change (the clear button,
    -- Escape, a window opening or closing) applies at once. A text the game's
    -- search already holds does nothing. apply(text) writes the search (the
    -- windows repaint when the game reports it, see SetSearchText). Returns
    -- the box's change handler.
    local SEARCH_DEBOUNCE = 0.1
    function EUI_Bags.WatchSearchBox(box, apply)
        local armed, lastKeyAt = false, 0
        local function flush()
            local wait = lastKeyAt + SEARCH_DEBOUNCE - GetTime()
            if wait > 0 then
                C_Timer.After(wait, flush)
                return
            end
            armed = false
            local text = box:GetText()
            if text ~= EUI_Bags._appliedSearch then apply(text) end
        end
        return function(userInput)
            if userInput then
                lastKeyAt = GetTime()
                if not armed then
                    armed = true
                    C_Timer.After(SEARCH_DEBOUNCE, flush)
                end
                return
            end
            local text = box:GetText()
            if text ~= EUI_Bags._appliedSearch then apply(text) end
        end
    end

    -- Clears the game's search unless it is already clear (the clear buttons,
    -- Escape and the bank's open and close, after emptying their box).
    function EUI_Bags.ClearSearch()
        if EUI_Bags._appliedSearch ~= "" then EUI_Bags.SetSearchText("") end
    end

    -- Overrides info.isFiltered for the active keyword; no-op when none is active.
    function EUI_Bags.ApplyBindKeyword(info, bag, slot)
        local k = EUI_Bags._bindKeyword
        if not k or not info then return end
        local match = false
        loc:SetBagAndSlot(bag, slot)
        if C_Item.DoesItemExist(loc) then
            if k == "bop" then
                match = info.hyperlink and select(14, GetItemInfo(info.hyperlink)) == Enum.ItemBind.OnAcquire
            elseif not info.isBound then
                -- BoE and WuE both mean "not bound yet". WuE reads as OnEquip
                -- from GetItemInfo, so the account check tells the two apart.
                local isWuE = C_Item.IsBoundToAccountUntilEquip(loc)
                if k == "wue" then
                    match = isWuE
                else
                    match = not isWuE and info.hyperlink
                        and select(14, GetItemInfo(info.hyperlink)) == Enum.ItemBind.OnEquip
                end
            end
        end
        info.isFiltered = not match
    end
end

-------------------------------------------------------------------------------
--  Item border color (shared by bags and bank render paths)
-------------------------------------------------------------------------------
-- Quality Item Border: the item's quality color while the option is on (every
-- display), else the neutral grey an unknown quality gets.
function ns.QualityBorderColor(quality)
    local c = BP().bagQualityBorder ~= false and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 0.25, 0.25, 0.25
end

-------------------------------------------------------------------------------
--  Third-party item overlay icons (opt-in extension point for compatibility bridges with addons like CanIMogIt)
-------------------------------------------------------------------------------
-- Public API (other addons call it): updateFn(btn, data) runs for every
-- painted slot in the bags, the reagent bag and the bank, grid slots and List
-- view rows alike. btn is our secure container item button: keep state off it
-- (parent frames to btn._textOverlay, which covers the item icon, and track
-- them in your own table), never touch it from a click handler.
-- data = { bag, slot, info, itemLink }, valid during the call only (the bank
-- reuses one table); placeholder slots pass bag 0 / slot 0 and no item. A
-- painter error is reported and never stops our render.
EUI_Bags.itemOverlayIcons = EUI_Bags.itemOverlayIcons or {}

function EUI_Bags.RegisterItemOverlayIcon(name, updateFn)
    EUI_Bags.itemOverlayIcons[name] = updateFn
end

function EUI_Bags.UnregisterItemOverlayIcon(name)
    EUI_Bags.itemOverlayIcons[name] = nil
end

function EUI_Bags.RunItemOverlays(btn, data)
    local fns = EUI_Bags.itemOverlayIcons
    if next(fns) == nil then return end
    for _, fn in pairs(fns) do
        securecallfunction(fn, btn, data)
    end
end

-------------------------------------------------------------------------------
--  Item Icons takeover (Quality of Life > Item Icons, frame key "eui_bags").
--  While it manages EUI Bags, the grid, Compact, reagent and bank slots draw
--  their marks through EllesmereUI.ItemIcons.Paint with the facts the render
--  pass already holds, and Bags' own overlays stay empty. Released, or QoL not
--  loaded, they draw from the Bags settings as before. List rows keep their
--  columns. The overlay icons above run in both cases.
-------------------------------------------------------------------------------
do
    local II  -- EllesmereUI.ItemIcons once the adapter is registered
    local FRAME_KEY = "eui_bags"
    -- Per button, the ctx of its last paint (link, bag, slot, count, quality,
    -- itemID, alpha, facts), built once and reused: a Refresh repaints the
    -- shown slots from these without a bag scan. link nil: nothing painted.
    local records = setmetatable({}, { __mode = "k" })

    local function Record(btn)
        local rec = records[btn]
        if not rec then
            rec = { facts = {} }
            records[btn] = rec
        end
        return rec
    end

    -- Read once per render pass
    function ns.ItemIconsOn()
        return II ~= nil and II.IsFrameEnabled(FRAME_KEY)
    end

    -- The button's facts for the ns.ItemIconsPaint that follows, emptied
    -- first: nil = not read (the element reads it if it needs it), false =
    -- known absent
    function ns.ItemIconsFacts(btn)
        local facts = Record(btn).facts
        wipe(facts)
        return facts
    end

    -- Paints a slot's marks with the facts from ns.ItemIconsFacts (none
    -- without a link); the stackCount element replaces the stack count.
    -- filtered: the search dims the slot.
    function ns.ItemIconsPaint(btn, bag, slot, link, count, quality, itemID, filtered)
        if btn.Count then btn.Count:Hide() end
        if not link then
            local rec = records[btn]
            if rec then rec.link = nil end
            II.Clear(btn)
            return
        end
        local rec = Record(btn)
        rec.link, rec.bag, rec.slot, rec.count = link, bag, slot, count
        rec.quality, rec.itemID = quality, itemID
        rec.alpha = filtered and II.DIM_ALPHA or 1
        II.Paint(btn, rec, FRAME_KEY)
    end

    -- Mark mode: a painted slot's Junk Marker verdict changed
    function ns.ItemIconsSetJunk(btn, isJunk)
        local rec = records[btn]
        if rec and rec.link then
            rec.facts.isJunk = isJunk
            II.Paint(btn, rec, FRAME_KEY)
        end
    end

    -- Take and release: the open windows repaint in full (each refresh returns
    -- while its window is closed). A sort running holds the bags' refresh and
    -- repaints them when it ends.
    local function RepaintOpenWindows()
        if EUI_Bags.refreshEnabled ~= false then EUI_Bags:RefreshInventory() end
        EUI_BagsReagent:RefreshInventory()
        ns.RefreshOpenBank()
    end

    local function Release()
        for _, rec in pairs(records) do rec.link = nil end
        RepaintOpenWindows()
    end

    -- Layout, style or item data changes: only the marks of the shown slots
    local function RepaintMarks()
        for btn, rec in pairs(records) do
            if rec.link and btn:IsVisible() then II.Paint(btn, rec, FRAME_KEY) end
        end
    end

    -- At login: QoL (loaded after Bags) has built EllesmereUI.ItemIcons by then
    function ns.RegisterItemIcons()
        II = EUI.ItemIcons
        if II and not II.RegisterFrame(FRAME_KEY, {
            Enable = RepaintOpenWindows, Refresh = RepaintMarks, Disable = Release,
        }) then
            II = nil
        end
    end
end

I._itemDragFrame, I.GetOrCreateBagSlot = _itemDragFrame, GetOrCreateBagSlot
I.GetOrCreateReagentSlot = GetOrCreateReagentSlot
I.broken = false
