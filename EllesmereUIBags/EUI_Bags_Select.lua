if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Select.lua
--
--  Pin and Assign selection modes, the Junk Marker and Sell Junk.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local GetItemInfo = C_Item.GetItemInfo
local EUI = EllesmereUI

local BP, GetAccentRGB, GetFont, IsGearItem = I.BP, I.GetAccentRGB, I.GetFont, I.IsGearItem
local IsItemPinned, NormalizePinKey = I.IsItemPinned, I.NormalizePinKey
local SetBagFont, _openItemPanels = I.SetBagFont, I._openItemPanels
local itemSlots, SetInsetBorderColor = I.itemSlots, I.SetInsetBorderColor

-------------------------------------------------------------------------------
--  Pin Selection Mode
-------------------------------------------------------------------------------
local EnterPinSelectMode  -- forward declaration
local ExitPinSelectMode   -- forward declaration
local EnterAssignSelectMode  -- forward declaration

-- The "+" look shared by the pin and assign "+" overlays and the Compact
-- display's drop zones (EllesmereUIBags_Compact.lua): a dimmed button with a
-- "+" that brightens on hover and shows the button's _plusTip.
ns.PIN_PLUS_TIP = "Pin an Item"
ns.ASSIGN_PLUS_TIP = "Assign an item to this category"
do
    local function PlusOnEnter(self)
        self._hover = true
        self.plus:SetTextColor(1, 1, 1, 1)
        EUI.ShowWidgetTooltip(self, self._plusTip)
    end
    local function PlusOnLeave(self)
        self._hover = nil
        self.plus:SetTextColor(1, 1, 1, 0.5)
        EUI.HideWidgetTooltip()
    end
    function ns.CreatePlusButton(parent, tip)
        local ov = CreateFrame("Button", nil, parent)
        ov.bg = ov:CreateTexture(nil, "BACKGROUND")
        ov.bg:SetAllPoints()
        ov.bg:SetColorTexture(0, 0, 0, 0.4)
        ov.plus = ov:CreateFontString(nil, "OVERLAY")
        ov.plus:SetFont(GetFont(), 18, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
        ov.plus:SetPoint("CENTER", 0, 0)
        ov.plus:SetText("+")
        ov.plus:SetTextColor(1, 1, 1, 0.5)
        ov._plusTip = tip
        ov:SetScript("OnEnter", PlusOnEnter)
        ov:SetScript("OnLeave", PlusOnLeave)
        ov:RegisterForDrag("LeftButton")
        return ov
    end
    -- Ends the hover look of a plus button hidden under the mouse (it may get no OnLeave)
    function ns.EndPlusHover(btn)
        if btn._hover then PlusOnLeave(btn) end
    end
end

-- Pins the item on the cursor (the pin "+" overlay, the Compact Pinned drop
-- zone) and refreshes; returns true when the cursor held an item.
function ns.PinCursorItem()
    -- The third return is the item link: pins are keyed by it (NormalizePinKey)
    local cursorType, itemID, cursorLink = GetCursorInfo()
    if cursorType ~= "item" or not itemID then return false end
    if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
    local pinned = EllesmereUIDB.bagPinnedItems
    if not IsItemPinned(pinned, cursorLink, itemID) then
        pinned[NormalizePinKey(cursorLink, itemID)] = IsGearItem(cursorLink) and 1 or 999
    end
    ClearCursor()
    EUI_Bags:RefreshInventory()
    return true
end

-- Assigns the item on the cursor to the category catKey (the assign "+"
-- overlay, a Compact drop zone) and refreshes; returns true when it did.
function ns.AssignCursorItem(catKey)
    local cursorType, itemID = GetCursorInfo()
    if cursorType ~= "item" or not itemID or not catKey then return false end
    EUI_CategoryManager:AssignItem(itemID, catKey)
    ClearCursor()
    EUI_Bags:RefreshInventory()
    return true
end

-- The "+" overlays lie over an empty slot's item button and its overlays (the
-- window's level + 9 to + 15, ns.PinItemButton), so each placement levels them
-- from the window's current level: 100 over a window at level 1
local function OverSlots(ov)
    ov:SetFrameLevel(EUI_Bags:GetFrameLevel() + 99)
    return ov
end

-- Pin "+" overlay: a click-catcher frame placed over a regular empty slot
local function GetOrCreatePinOverlay()
    if EUI_Bags._pinOverlayBtn then return OverSlots(EUI_Bags._pinOverlayBtn) end
    local ov = ns.CreatePlusButton(EUI_Bags, ns.PIN_PLUS_TIP)
    ns.SizeSlot(ov)
    ov:SetScript("OnReceiveDrag", ns.PinCursorItem)
    ov:SetScript("OnClick", function(self)
        -- Click-to-place also pins
        if ns.PinCursorItem() then return end
        -- Controller cursor on screen: select mode hit-tests the hidden
        -- pointer, so explain the carry-then-press path instead.
        if EUI.PadCursorShown() then
            EUI.ShowWidgetTooltip(self, EllesmereUI.L("Pick up an item, then press + to pin it"))
            return
        end
        EUI.HideWidgetTooltip()
        -- Select modes raise the item grid: out of combat only
        if InCombatLockdown() then return end
        EnterPinSelectMode()
    end)
    ov:Hide()
    EUI_Bags._pinOverlayBtn = ov
    return OverSlots(ov)
end

-- Assign "+" overlay: click/drag an item to assign to a category; pooled so multiple sections can show one simultaneously.
local _assignOverlays = {}
local _assignOverlayIdx = 0

local function GetOrCreateAssignOverlay()
    _assignOverlayIdx = _assignOverlayIdx + 1
    if _assignOverlays[_assignOverlayIdx] then return OverSlots(_assignOverlays[_assignOverlayIdx]) end
    local ov = ns.CreatePlusButton(EUI_Bags, ns.ASSIGN_PLUS_TIP)
    ns.SizeSlot(ov)
    local function DoAssign(self)
        if ns.AssignCursorItem(self._assignCatKey) then return end
        -- No cursor item: enter assign select mode (like pin select)
        if self._assignCatKey then
            -- Controller cursor on screen: select mode hit-tests the hidden
            -- pointer, so explain the carry-then-press path instead.
            if EUI.PadCursorShown() then
                EUI.ShowWidgetTooltip(self, EllesmereUI.L("Pick up an item, then press + to add it to this category"))
                return
            end
            EUI.HideWidgetTooltip()
            -- Select modes raise the item grid: out of combat only
            if InCombatLockdown() then return end
            EnterAssignSelectMode(self._assignCatKey)
        end
    end
    ov:SetScript("OnReceiveDrag", DoAssign)
    ov:SetScript("OnClick", DoAssign)
    ov:Hide()
    _assignOverlays[_assignOverlayIdx] = ov
    return OverSlots(ov)
end

local function ResetAssignOverlays()
    for i = 1, _assignOverlayIdx do
        _assignOverlays[i]:Hide()
    end
    _assignOverlayIdx = 0
end

ExitPinSelectMode = function()
    EUI_Bags._pinSelectMode = false
    local cf = EUI_Bags._pinCatcher
    if cf then
        cf:UnregisterEvent("PLAYER_REGEN_DISABLED")
        cf:Hide()
    end
    local ov = EUI_Bags._pinOverlay
    if ov then
        ov:EnableMouse(false)
        if not ov._fadeOut then
            local fg = ov:CreateAnimationGroup()
            local a = fg:CreateAnimation("Alpha")
            a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(0.15)
            fg:SetScript("OnFinished", function() ov:Hide(); ov:SetAlpha(1) end)
            ov._fadeOut = fg
        end
        ov._fadeOut:Play()
    end
    local sf = EUI_Bags._scrollFrame
    if sf then sf:SetFrameStrata(EUI_Bags:GetFrameStrata()) end
end

-- Repaints an open bank (RefreshBank returns while it is closed), so the
-- search filter and Junk Marker changes show in both windows
function ns.RefreshOpenBank()
    local bank = _G.EUI_BankFrame
    if bank then bank:RefreshBank() end
end

-------------------------------------------------------------------------------
--  Assign Selection Mode: dim the screen, click an item to assign it to a category (mirrors Pin Selection Mode).
-------------------------------------------------------------------------------
local _assignSelectCatKey = nil

local function ExitAssignSelectMode()
    local wasJunk = EUI_Bags._junkMode
    EUI_Bags._assignSelectMode = false
    EUI_Bags._junkMode = nil
    _assignSelectCatKey = nil
    local cf = EUI_Bags._assignCatcher
    if cf then
        cf._clearHover()
        cf:UnregisterEvent("PLAYER_REGEN_DISABLED")
        cf:Hide()
    end
    local ov = EUI_Bags._assignOverlay
    if ov then
        ov:EnableMouse(false)
        if not ov:IsVisible() then
            -- Hidden with the bags: nothing to fade out
            if ov._fadeIn then ov._fadeIn:Stop() end
            ov:Hide()
            ov:SetAlpha(1)
        else
            if not ov._fadeOut then
                local fg = ov:CreateAnimationGroup()
                local a = fg:CreateAnimation("Alpha")
                a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(0.15)
                fg:SetScript("OnFinished", function() ov:Hide(); ov:SetAlpha(1) end)
                ov._fadeOut = fg
            end
            ov._fadeOut:Play()
        end
    end
    local sf = EUI_Bags._scrollFrame
    if sf then sf:SetFrameStrata(EUI_Bags:GetFrameStrata()) end
    -- The coin goes back into the header's layer
    local coin = wasJunk and EUI_Bags._junkBtn
    if coin then
        coin:SetFrameStrata(EUI_Bags:GetFrameStrata())
        coin:SetFrameLevel(coin:GetParent():GetFrameLevel() + 1)
    end
    -- Marks repainted only their own slots: sort them into place now (an open
    -- bank greys and regroups its copies too)
    if wasJunk and EUI_Bags._junkDirty then
        EUI_Bags._junkDirty = nil
        if EUI_Bags:IsShown() then EUI_Bags:RefreshInventory() end
        ns.RefreshOpenBank()
    end
end

-- Select modes' hit-test: the shown grid slot or list row under the cursor,
-- only over the scroll frame (rows scrolled out of view stay shown under the
-- header, the footer or outside the window; the scroll frame only clips them).
-- Cursor / each button's OWN effective scale: GetRect() is in button units.
function ns.SelectSlotUnderCursor()
    if ns.OfflineUp and ns.OfflineUp() then return nil end  -- an alt's items aren't real slots
    local sf = EUI_Bags._scrollFrame
    if not (sf and sf:IsMouseOver()) then return nil end
    local rawCx, rawCy = GetCursorPosition()
    local pool = itemSlots
    for _ = 1, 2 do
        for _, btn in pairs(pool) do
            if btn:IsShown() and btn:GetParent():IsShown() then
                local es = btn:GetEffectiveScale()
                local cx, cy = rawCx / es, rawCy / es
                local l, b, w, h = btn:GetRect()
                if l and b and w and h and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                    return btn
                end
            end
        end
        pool = ns.ListRows
        if not pool then break end
    end
    return nil
end

-- Mark mode: a mark is per item, so every shown slot holding it repaints
-- (the item ID first: only those slots read the full item info)
function ns.RepaintJunkItem(itemID)
    local pool = itemSlots
    for _ = 1, 2 do
        for _, btn in pairs(pool) do
            if btn:IsShown() and btn:GetParent():IsShown() then
                local bag, slot = btn:GetParent():GetID(), btn:GetID()
                if C_Container.GetContainerItemID(bag, slot) == itemID then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info then
                        if btn._lvIcon then ns.ListPaintJunk(btn, info) else ns.GridPaintJunk(btn, info) end
                    end
                end
            end
        end
        pool = ns.ListRows
        if not pool then break end
    end
end

-- junk: Junk Marker mode -- clicks toggle marks, the mode stays open, and only
-- the bag window dims (the "+" assign dims the whole screen).
EnterAssignSelectMode = function(catKey, junk)
    if ns.OfflineUp and ns.OfflineUp() then return end  -- nothing live to pick while an alt or bank is up
    EUI_Bags._assignSelectMode = true
    EUI_Bags._junkMode = junk or nil
    _assignSelectCatKey = catKey

    local cacheKey = junk and "_assignOverlayBag" or "_assignOverlayFull"
    if not EUI_Bags[cacheKey] then
        local ov = CreateFrame("Frame", nil, junk and EUI_Bags or UIParent)
        if junk then
            -- The bag's own strata: the item grid rides the scroll frame, raised
            -- to FULLSCREEN_DIALOG below, so only the bag behind the items dims.
            ov:SetFrameStrata(EUI_Bags:GetFrameStrata())
            ov:SetFrameLevel(EUI_Bags:GetFrameLevel() + 20)
            ov:SetAllPoints(EUI_Bags)
        else
            ov:SetFrameStrata("FULLSCREEN_DIALOG")
            ov:SetFrameLevel(0)
            ov:SetAllPoints(UIParent)
        end
        ov:EnableMouse(true)
        ov.bg = ov:CreateTexture(nil, "BACKGROUND")
        ov.bg:SetAllPoints()
        ov.bg:SetColorTexture(0, 0, 0, 0.6)
        ov:SetScript("OnMouseDown", function() ExitAssignSelectMode() end)
        -- Escape (and controller Back) ends the mode before closing the bags,
        -- through the escape proxy: the overlay takes no keyboard input
        EllesmereUI.RegisterEscapeClose(ov, { notOwned = true, onEscape = function() ExitAssignSelectMode() end })
        EUI_Bags[cacheKey] = ov
    end
    EUI_Bags._assignOverlay = EUI_Bags[cacheKey]
    local ov = EUI_Bags._assignOverlay
    -- A fade-out still running from a quick exit would hide the dim mid-mode,
    -- and the exit turned its mouse off
    if ov._fadeOut then ov._fadeOut:Stop() end
    ov:EnableMouse(true)
    ov:SetAlpha(0)
    ov:Show()
    if not ov._fadeIn then
        local fg = ov:CreateAnimationGroup()
        local a = fg:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.15)
        fg:SetScript("OnFinished", function() ov:SetAlpha(1) end)
        ov._fadeIn = fg
    end
    ov._fadeIn:Play()

    -- Raise scroll frame above overlay
    local sf = EUI_Bags._scrollFrame
    if sf then sf:SetFrameStrata("FULLSCREEN_DIALOG") end

    local FindBtnUnderCursor = ns.SelectSlotUnderCursor

    -- Click catcher with hover highlight
    if not EUI_Bags._assignCatcher then
        local cf = CreateFrame("Frame", nil, UIParent)
        cf:SetFrameStrata("FULLSCREEN_DIALOG")
        cf:SetFrameLevel(500)
        cf:EnableMouse(true)
        -- Combat ends the mode (registered only while it is on)
        cf:SetScript("OnEvent", function() ExitAssignSelectMode() end)

        local hoverOv = cf:CreateTexture(nil, "OVERLAY")
        hoverOv:SetColorTexture(1, 1, 1, 0.4)
        hoverOv:Hide()
        local hoveredBtn = nil
        local savedR, savedG, savedB, savedA, savedBrdSize

        local function ClearHover()
            if hoveredBtn then
                if savedR then SetInsetBorderColor(hoveredBtn, savedR, savedG, savedB, savedA) end
                if savedBrdSize and hoveredBtn._brdT then
                    hoveredBtn._brdT:SetHeight(savedBrdSize)
                    hoveredBtn._brdB:SetHeight(savedBrdSize)
                    hoveredBtn._brdL:SetWidth(savedBrdSize)
                    hoveredBtn._brdR:SetWidth(savedBrdSize)
                end
            end
            hoveredBtn = nil
            savedR = nil
            savedBrdSize = nil
            hoverOv:ClearAllPoints()
            hoverOv:Hide()
        end
        cf._clearHover = ClearHover

        -- Re-tests only when the cursor or the scroll moved, or on a show
        -- (_hoverDirty); the wheel scrolls under a still cursor
        local lastX, lastY, lastScroll
        cf:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local sf = EUI_Bags._scrollFrame
            local s = sf and sf:GetVerticalScroll() or 0
            if x == lastX and y == lastY and s == lastScroll and not self._hoverDirty then return end
            lastX, lastY, lastScroll = x, y, s
            self._hoverDirty = nil
            local btn = FindBtnUnderCursor()
            if btn == hoveredBtn then return end
            ClearHover()
            if btn and btn.icon and btn.icon:IsShown() then
                if btn._brdT then
                    savedR, savedG, savedB, savedA = btn._brdT:GetVertexColor()
                    savedBrdSize = btn._brdT:GetHeight()
                    local ar, ag, ab = GetAccentRGB()
                    SetInsetBorderColor(btn, ar, ag, ab, 1)
                    local PP = EUI and EUI.PP
                    local px2 = ((PP and PP.mult) or 1) * 2
                    btn._brdT:SetHeight(px2)
                    btn._brdB:SetHeight(px2)
                    btn._brdL:SetWidth(px2)
                    btn._brdR:SetWidth(px2)
                end
                hoverOv:ClearAllPoints()
                hoverOv:SetAllPoints(btn)
                hoverOv:Show()
                hoveredBtn = btn
            end
        end)

        cf:SetScript("OnMouseDown", function(_, button)
            if button == "RightButton" then ClearHover(); ExitAssignSelectMode(); return end
            -- Junk Marker: the close button still closes the bags (the coin
            -- sits above this catcher and takes its own clicks)
            local junkMode = EUI_Bags._junkMode
            if junkMode and EUI_Bags._closeBtn and EUI_Bags._closeBtn:IsMouseOver() then
                ExitAssignSelectMode()
                EUI_Bags._closeBtn:Click()
                return
            end
            local btn = FindBtnUnderCursor()
            if btn then
                local bagID = btn:GetParent():GetID()
                local slotID = btn:GetID()
                if bagID and slotID and slotID > 0 then
                    local info = C_Container.GetContainerItemInfo(bagID, slotID)
                    if info and info.itemID and _assignSelectCatKey then
                        if junkMode then
                            -- Only the item's own slots repaint, so nothing moves under
                            -- the cursor; the bag sorts the marks when the mode ends
                            EUI_CategoryManager:ToggleJunk(info.itemID)
                            ns.RepaintJunkItem(info.itemID)
                            EUI_Bags._junkDirty = true
                        else
                            ClearHover()
                            EUI_CategoryManager:AssignItem(info.itemID, _assignSelectCatKey)
                            ExitAssignSelectMode()
                            EUI_Bags:RefreshInventory()
                        end
                        return
                    end
                end
            end
            -- Junk Marker: a click on empty bag space keeps the mode; anywhere
            -- outside the bags, right-click or Esc ends it
            if junkMode and EUI_Bags:IsMouseOver() then return end
            ClearHover()
            ExitAssignSelectMode()
        end)

        cf:SetAllPoints(UIParent)
        cf:Hide()
        EUI_Bags._assignCatcher = cf
    end
    local cf = EUI_Bags._assignCatcher
    cf._hoverDirty = true
    cf:RegisterEvent("PLAYER_REGEN_DISABLED")
    cf:Show()
    -- Junk Marker: the coin stays bright above the dim and takes its own
    -- clicks above the catcher (a click on it ends the mode)
    local coin = junk and EUI_Bags._junkBtn
    if coin then
        coin:SetFrameStrata("FULLSCREEN_DIALOG")
        coin:SetFrameLevel(cf:GetFrameLevel() + 1)
    end
end

-------------------------------------------------------------------------------
--  Junk Marker: the header coin (mark mode) and Sell Junk (at merchants). Both
--  buttons are built on the first enable; nothing exists while it is off.
-------------------------------------------------------------------------------
do
local function BuildButtons()
    local header = EUI_Bags._bagsBtn:GetParent()
    -- Placed by SyncHeaderIcons, left of the next shown header icon
    local junk = CreateFrame("Button", nil, header)
    junk:SetSize(22, 22)
    -- Our own coin art (the item badge and the Junk category keep the game's
    -- coin). It sits inside a thin margin: drawn 24 px, the coin fills the button
    junk.icon = junk:CreateTexture(nil, "OVERLAY")
    junk.icon:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\gold.png")
    junk.icon:SetSize(24, 24)
    junk.icon:SetPoint("CENTER")
    junk.icon:SetAlpha(0.9)
    junk:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        EUI.ShowWidgetTooltip(self, EllesmereUI.L("Click items to mark or unmark them as junk."))
    end)
    junk:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)
    junk:SetScript("OnClick", function(self)
        EUI.HideWidgetTooltip()
        -- Mark mode on: the coin ends it
        if EUI_Bags._junkMode then ExitAssignSelectMode(); return end
        if InCombatLockdown() then return end
        -- An item on the cursor: mark or unmark that one
        local cursorType, itemID = GetCursorInfo()
        if cursorType == "item" and itemID then
            EUI_CategoryManager:ToggleJunk(itemID)
            ClearCursor()
            EUI_Bags:RefreshInventory()
            ns.RefreshOpenBank()
            return
        end
        -- Controller cursor on screen: mark mode hit-tests the hidden
        -- pointer, so explain the carry-then-press path instead.
        if EUI.PadCursorShown() then
            EUI.ShowWidgetTooltip(self, EllesmereUI.L("Pick up an item, then press the coin to mark it as junk"))
            return
        end
        EnterAssignSelectMode(EUI_CategoryManager.JUNK_KEY, true)
    end)
    -- A double-click is one press: its second click runs this instead of
    -- OnClick, which would end the mode the first click started
    junk:SetScript("OnDoubleClick", function() end)
    EUI_Bags._junkBtn = junk

    local sell = CreateFrame("Button", nil, header)
    sell:SetPoint("RIGHT", junk, "LEFT", -6, 0)
    local bg = sell:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    sell.label = sell:CreateFontString(nil, "OVERLAY")
    SetBagFont(sell.label, 10)
    sell.label:SetPoint("CENTER")
    sell.label:SetText(EllesmereUI.L("Sell Junk"))
    sell.label:SetTextColor(0.85, 0.82, 0.55)
    -- Sized to its label (translations run longer)
    sell:SetSize(math.max(58, math.ceil(sell.label:GetStringWidth()) + 14), 18)
    sell:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 0.96, 0.66)
        EUI.ShowWidgetTooltip(self, EllesmereUI.L("Sells all your junk items."))
    end)
    sell:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.85, 0.82, 0.55)
        EUI.HideWidgetTooltip()
    end)
    sell:SetScript("OnClick", function()
        EUI.HideWidgetTooltip()
        EUI_Bags:SellJunk()
    end)
    EUI_Bags._sellJunkBtn = sell
end

-- The header's icons (Bag Top Bar Icons), right to left from the search box:
-- Sort, Show Bags, Quick Actions and the Junk Marker's coin, each shown one left of the next
-- shown one; Sell Junk sits left of the coin while a merchant is open, and
-- mark mode ends when the Junk Marker goes off. Hidden icons keep a point (the
-- bags overview window hangs from Show Bags). Run at header build, by the
-- options dropdown, on profile changes and on merchant open / close.
function EUI_Bags:SyncHeaderIcons()
    local bags = self._bagsBtn
    if not bags then return end
    local p = BP()
    local prev, gap = self._searchBox, 13
    local sortOn = p.bagShowSortIcon ~= false
    self._sortBtn:SetShown(sortOn)
    if sortOn then prev, gap = self._sortBtn, 6 end
    local bagsOn = p.bagShowBagsIcon ~= false
    bags:ClearAllPoints()
    bags:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
    bags:SetShown(bagsOn)
    if bagsOn then
        prev, gap = bags, 6
    else
        EUI_BagsWindow:Hide()  -- opened only from Show Bags
    end
    -- Quick Actions (EllesmereUIBags_QuickActions.lua), off by default
    local quick = ns.SyncQuickActionsIcon(prev, gap)
    if quick then prev, gap = quick, 6 end
    local junkOn = EUI_CategoryManager:IsJunkMarkerEnabled()
    if junkOn and not self._junkBtn then BuildButtons() end
    if self._junkBtn then
        self._junkBtn:ClearAllPoints()
        self._junkBtn:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
        self._junkBtn:SetShown(junkOn)
        self._sellJunkBtn:SetShown(junkOn and _openItemPanels.merchant == true)
    end
    if not junkOn and self._junkMode then ExitAssignSelectMode() end
end

-- The slots one Sell Junk sweep may sell, gathered once as bag * 1000 + slot
-- (ids holds each one's itemID): marked or grey junk worth something, outside
-- WoW Forever's special bags, equipment sets and pins, and not still
-- refundable (Blizzard's own right-click never sells those without asking, and
-- a fresh purchase of a marked item would otherwise go unasked). Returns how
-- many junk items it kept back (the summary counts them as not sold).
local function GatherJunkSlots(slots, ids)
    local special = ns.SpecialBags()
    local setGear = EUI_CategoryManager:GetSetGearLookup()
    local pinned = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
    local kept = 0
    for bag = 0, 5 do
        if not (special and special[bag]) then
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID and EUI_CategoryManager:IsJunk(info.itemID, info.quality) then
                    local keep = info.hasNoValue or setGear[bag * 1000 + slot]
                        or (pinned and IsItemPinned(pinned, info.hyperlink, info.itemID))
                    if not keep then
                        local p = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
                        keep = p and p.refundSeconds and p.refundSeconds > 0
                    end
                    if keep then
                        kept = kept + 1
                    else
                        slots[#slots + 1] = bag * 1000 + slot
                        ids[#ids + 1] = info.itemID
                    end
                end
            end
        end
    end
    return kept
end

-- One item every 0.08 s, until the gathered slots run out, the merchant
-- closes, combat starts or the cursor holds an item (a sale waiting on its
-- confirmation: press Sell Junk again once it is answered). A sale counts once
-- its slot has emptied; the summary (what sold, and what was left unsold)
-- waits for the server to answer the sales in flight, 2 s at most.
-- force: the caller saw MERCHANT_SHOW, which can run before Bags' own merchant
-- flag is set.
function EUI_Bags:SellJunk(force)
    if self._junkSelling or InCombatLockdown() or not (force or _openItemPanels.merchant) then return end
    self._junkSelling = true
    local slots, ids, values, sent = {}, {}, {}, {}
    local kept = GatherJunkSlots(slots, ids)
    local i, done = 0, false
    local function Landed(k)
        local key = slots[k]
        return C_Container.GetContainerItemID(math.floor(key / 1000), key % 1000) ~= ids[k]
    end
    local function InFlight()
        for n = 1, #sent do
            local k = sent[n]
            if not Landed(k) then
                local key = slots[k]
                local info = C_Container.GetContainerItemInfo(math.floor(key / 1000), key % 1000)
                if info and info.isLocked then return true end
            end
        end
        return false
    end
    -- The summary (the bags repaint from the sales' own BAG_UPDATEs)
    local function Finish()
        if done then return end
        done = true
        local f = EUI_Bags._junkSettle
        if f then f:UnregisterAllEvents() end
        EUI_Bags._junkSelling = nil
        local sold, earned = 0, 0
        for n = 1, #sent do
            if Landed(sent[n]) then sold, earned = sold + 1, earned + values[sent[n]] end
        end
        -- Not sold: the junk kept back (no sell price, equipment sets, pins,
        -- refundable), and a gathered slot still holding its item (a sale
        -- refused or waiting on its confirmation, or the sweep cut short)
        local left = kept
        for k = 1, #slots do
            if not Landed(k) then left = left + 1 end
        end
        local tag = EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r "
        if sold > 0 then
            local msg = EllesmereUI.Lf("Sold %1$d junk item(s)", sold)
            if earned > 0 then msg = msg .. "  " .. C_CurrencyInfo.GetCoinTextureString(earned) end
            EllesmereUI.Print(tag .. msg)
        end
        if left > 0 then
            EllesmereUI.Print(tag .. EllesmereUI.Lf("%d junk item(s) could not be sold.", left))
        end
    end
    -- Sales still in flight: finish once the server has answered them (their
    -- slots emptied or unlocked), or after 2 s at the latest
    local function Report()
        if not InFlight() then return Finish() end
        local f = EUI_Bags._junkSettle
        if not f then
            f = CreateFrame("Frame")
            f:SetScript("OnEvent", function(self) self._check() end)
            EUI_Bags._junkSettle = f
        end
        f._check = function() if not InFlight() then Finish() end end
        f:RegisterEvent("BAG_UPDATE_DELAYED")
        f:RegisterEvent("ITEM_LOCK_CHANGED")
        C_Timer.After(2, Finish)
    end
    local function step()
        local live = (force or _openItemPanels.merchant) and not InCombatLockdown() and not CursorHasItem()
        force = nil
        while live and i < #slots do
            i = i + 1
            local key = slots[i]
            local bag, slot = math.floor(key / 1000), key % 1000
            local info = C_Container.GetContainerItemInfo(bag, slot)
            -- Still the gathered item, and not locked
            if info and info.itemID == ids[i] and not info.isLocked then
                values[i] = ((info.hyperlink and select(11, GetItemInfo(info.hyperlink))) or 0) * (info.stackCount or 1)
                sent[#sent + 1] = i
                C_Container.UseContainerItem(bag, slot)
                C_Timer.After(0.08, step)
                return
            end
        end
        Report()
    end
    step()
end

-- Profile switch: the categories (Junk with them) and the header icons follow the new profile
function EUI_Bags:OnProfileApplied()
    self.InvalidateSetCategories()
    self:SyncHeaderIcons()
    if self:IsShown() then self:RefreshInventory() end
    ns.RefreshOpenBank()
    EUI_CategoryManager:OnJunkChanged()  -- the new profile may switch the Junk Marker
    if ns.AutoGold then ns.AutoGold.Sync() end  -- nil on WoW Forever
end
end -- Junk Marker

EnterPinSelectMode = function()
    if ns.OfflineUp and ns.OfflineUp() then return end
    EUI_Bags._pinSelectMode = true

    -- Dark overlay covers the entire screen including bags
    if not EUI_Bags._pinOverlay then
        local ov = CreateFrame("Frame", nil, UIParent)
        ov:SetFrameStrata("FULLSCREEN_DIALOG")
        ov:SetFrameLevel(0)
        ov:SetAllPoints(UIParent)
        ov:EnableMouse(true)
        ov.bg = ov:CreateTexture(nil, "BACKGROUND")
        ov.bg:SetAllPoints()
        ov.bg:SetColorTexture(0, 0, 0, 0.6)
        ov:SetScript("OnMouseDown", function() ExitPinSelectMode() end)
        -- Escape (and controller Back) ends the mode before closing the bags,
        -- through the escape proxy: the overlay takes no keyboard input
        EllesmereUI.RegisterEscapeClose(ov, { notOwned = true, onEscape = function() ExitPinSelectMode() end })
        EUI_Bags._pinOverlay = ov
    end
    local ov = EUI_Bags._pinOverlay
    -- A fade-out still running from a quick exit would hide the dim mid-mode,
    -- and the exit turned its mouse off (clicks outside the grid end the mode)
    if ov._fadeOut then ov._fadeOut:Stop() end
    ov:EnableMouse(true)
    ov:SetAlpha(0)
    ov:Show()
    if not ov._fadeIn then
        local fg = ov:CreateAnimationGroup()
        local a = fg:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.15)
        fg:SetScript("OnFinished", function() ov:SetAlpha(1) end)
        ov._fadeIn = fg
    end
    ov._fadeIn:Play()

    -- Raise the scroll frame above the overlay so item icons are visible
    local sf = EUI_Bags._scrollFrame
    if sf then sf:SetFrameStrata("FULLSCREEN_DIALOG") end

    local FindBtnUnderCursor = ns.SelectSlotUnderCursor

    -- Click catcher above the raised icons: swallows clicks (items aren't used/equipped), then pins whichever icon was clicked.
    if not EUI_Bags._pinCatcher then
        local cf = CreateFrame("Frame", nil, UIParent)
        cf:SetFrameStrata("FULLSCREEN_DIALOG")
        cf:SetFrameLevel(500)
        cf:EnableMouse(true)
        -- Combat ends the mode (registered only while it is on)
        cf:SetScript("OnEvent", function() ExitPinSelectMode() end)

        -- Hover highlight: accent border (2px) + white overlay
        local pinHoverOv = cf:CreateTexture(nil, "OVERLAY")
        pinHoverOv:SetColorTexture(1, 1, 1, 0.4)
        pinHoverOv:Hide()
        local pinHoveredBtn = nil
        local pinSavedR, pinSavedG, pinSavedB, pinSavedA
        local pinSavedBrdSize

        local function ClearPinHover()
            if pinHoveredBtn then
                if pinSavedR then
                    SetInsetBorderColor(pinHoveredBtn, pinSavedR, pinSavedG, pinSavedB, pinSavedA)
                end
                if pinSavedBrdSize and pinHoveredBtn._brdT then
                    pinHoveredBtn._brdT:SetHeight(pinSavedBrdSize)
                    pinHoveredBtn._brdB:SetHeight(pinSavedBrdSize)
                    pinHoveredBtn._brdL:SetWidth(pinSavedBrdSize)
                    pinHoveredBtn._brdR:SetWidth(pinSavedBrdSize)
                end
            end
            pinHoveredBtn = nil
            pinSavedR = nil
            pinSavedBrdSize = nil
            pinHoverOv:ClearAllPoints()
            pinHoverOv:Hide()
        end
        cf._clearHover = ClearPinHover

        -- Re-tests only when the cursor or the scroll moved, or on a show or a
        -- bag refresh (_hoverDirty); the wheel scrolls under a still cursor
        local lastX, lastY, lastScroll
        cf:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local sf = EUI_Bags._scrollFrame
            local s = sf and sf:GetVerticalScroll() or 0
            if x == lastX and y == lastY and s == lastScroll and not self._hoverDirty then return end
            lastX, lastY, lastScroll = x, y, s
            self._hoverDirty = nil
            local btn = FindBtnUnderCursor()
            if btn == pinHoveredBtn then return end
            ClearPinHover()
            if btn and btn.icon and btn.icon:IsShown() then
                if btn._brdT then
                    pinSavedR, pinSavedG, pinSavedB, pinSavedA = btn._brdT:GetVertexColor()
                    pinSavedBrdSize = btn._brdT:GetHeight()
                    local ar, ag, ab = GetAccentRGB()
                    SetInsetBorderColor(btn, ar, ag, ab, 1)
                    local PP = EUI and EUI.PP
                    local px2 = ((PP and PP.mult) or 1) * 2
                    btn._brdT:SetHeight(px2)
                    btn._brdB:SetHeight(px2)
                    btn._brdL:SetWidth(px2)
                    btn._brdR:SetWidth(px2)
                end
                pinHoverOv:ClearAllPoints()
                pinHoverOv:SetAllPoints(btn)
                pinHoverOv:Show()
                pinHoveredBtn = btn
            end
        end)

        cf:SetScript("OnMouseDown", function(_, button)
            if button == "RightButton" then ClearPinHover(); ExitPinSelectMode(); return end
            local btn = FindBtnUnderCursor()
            if btn then
                local bagID = btn:GetParent():GetID()
                local slotID = btn:GetID()
                if bagID and slotID and slotID > 0 then
                    local info = C_Container.GetContainerItemInfo(bagID, slotID)
                    if info and info.itemID then
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
                        local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
                        local pinKey = NormalizePinKey(itemLink, info.itemID)
                        EllesmereUIDB.bagPinnedItems[pinKey] = (EllesmereUIDB.bagPinnedItems[pinKey] or 0) + 1
                        ClearPinHover()
                        ExitPinSelectMode()
                        EUI_Bags:RefreshInventory()
                        return
                    end
                end
            end
            ClearPinHover()
            ExitPinSelectMode()
        end)

        cf:SetScript("OnHide", function() ClearPinHover() end)
        EUI_Bags._pinCatcher = cf
    end
    -- Position catcher over the scroll frame area
    local sf = EUI_Bags._scrollFrame
    if sf and EUI.IS_FOREVER then
        -- WoW Forever: the window can grow while open (fit to content), so the catcher follows the scroll frame.
        EUI_Bags._pinCatcher:ClearAllPoints()
        EUI_Bags._pinCatcher:SetAllPoints(sf)
    elseif sf then
        local l, b, w, h = sf:GetRect()
        if l and b and w and h then
            EUI_Bags._pinCatcher:ClearAllPoints()
            EUI_Bags._pinCatcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
            EUI_Bags._pinCatcher:SetSize(w, h)
        end
    end
    EUI_Bags._pinCatcher._hoverDirty = true
    EUI_Bags._pinCatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    EUI_Bags._pinCatcher:Show()
end

I.ExitAssignSelectMode, I.ExitPinSelectMode = ExitAssignSelectMode, ExitPinSelectMode
I.GetOrCreateAssignOverlay = GetOrCreateAssignOverlay
I.GetOrCreatePinOverlay, I.ResetAssignOverlays = GetOrCreatePinOverlay, ResetAssignOverlays
I.broken = false
