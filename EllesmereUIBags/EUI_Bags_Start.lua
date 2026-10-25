if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Start.lua
--
--  StartAddon, the loader and what EllesmereUIBags_Grid.lua, _List, _Compact
--  and _Bank read from ns.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local ApplyBagScale, BagsItemUnusable, BP = I.ApplyBagScale, I.BagsItemUnusable, I.BP
local CurrencyOrder, GetAccentRGB = I.CurrencyOrder, I.GetAccentRGB
local GetCatTitleSize, GetDefaultBagType = I.GetCatTitleSize, I.GetDefaultBagType
local GetFont, SetBagFont, SLOT_SIZE, SPACING = I.GetFont, I.SetBagFont, I.SLOT_SIZE, I.SPACING
local ApplySavedOrder = I.ApplySavedOrder
local ArmorySlotGroupingEnabled = I.ArmorySlotGroupingEnabled
local BuildExpansionBuckets, BuildSlotBuckets = I.BuildExpansionBuckets, I.BuildSlotBuckets
local GetArmorySlotBucket, IsArmoryGearCategory = I.GetArmorySlotBucket, I.IsArmoryGearCategory
local IsGearOnlyGroup, itemSlots = I.IsGearOnlyGroup, I.itemSlots
local MergeDuplicates, PreCacheSortFields = I.MergeDuplicates, I.PreCacheSortFields
local RegisterPawnIntegration, SetItemPanelOpen = I.RegisterPawnIntegration, I.SetItemPanelOpen
local UpdatePawnArrow, VisualSortCompare = I.UpdatePawnArrow, I.VisualSortCompare
local CreateHeader, CreateFooter = I.CreateHeader, I.CreateFooter
local CreateReagentBagUI, GoldLedger = I.CreateReagentBagUI, I.GoldLedger
local OnGoldChanged, SyncBagFrameToFooter = I.OnGoldChanged, I.SyncBagFrameToFooter
local CreateInsetBorder, QUEST_BORDER_COLOR = I.CreateInsetBorder, I.QUEST_BORDER_COLOR
local SetInsetBorderColor = I.SetInsetBorderColor
local SetInsetBorderThickness, _itemDragFrame = I.SetInsetBorderThickness, I._itemDragFrame
local ExitAssignSelectMode, ExitPinSelectMode = I.ExitAssignSelectMode, I.ExitPinSelectMode
local GetOrCreateAssignOverlay = I.GetOrCreateAssignOverlay
local GetOrCreatePinOverlay = I.GetOrCreatePinOverlay
local ResetAssignOverlays, CreateSidebar = I.ResetAssignOverlays, I.CreateSidebar
local _catHeaders, _expSubHeaders = I._catHeaders, I._expSubHeaders
local CreateBagScrollFrame = I.CreateBagScrollFrame
local GetOrCreateCatHeader = I.GetOrCreateCatHeader
local GetOrCreateExpSubHeader = I.GetOrCreateExpSubHeader
local ShowRecentClearButton = I.ShowRecentClearButton
local SetSelectedCategoryIndex = I.SetSelectedCategoryIndex
local SetSelectedGroupName = I.SetSelectedGroupName

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = I.selectedCategoryIndex
I.categoryIndexSetters[#I.categoryIndexSetters + 1] = function(v) selectedCategoryIndex = v end
local selectedGroupName
I.groupNameSetters[#I.groupNameSetters + 1] = function(v) selectedGroupName = v end
local _anyItemPanelOpen = I._anyItemPanelOpen
I.anyItemPanelOpenSetters[#I.anyItemPanelOpenSetters + 1] = function(v) _anyItemPanelOpen = v end

-- Unmerge state the CURRENT painted layout was built with; the bags OnShow
-- compares against it so a flip while hidden still repaints (closing a
-- mailbox hides both). Written by the earlier files through
-- SetPaintedPanelOpen, read here only.
local _paintedPanelOpen = false
I.paintedPanelOpenSetters[#I.paintedPanelOpenSetters + 1] = function(v) _paintedPanelOpen = v end

-------------------------------------------------------------------------------
--  StartAddon
-------------------------------------------------------------------------------
local function StartAddon()
    RegisterPawnIntegration()

    -- Apply default view based on setting (DB now available)
    local _dbt = GetDefaultBagType()
    if _dbt == "onebag" then
        SetSelectedCategoryIndex(-1)
    elseif _dbt == "multibag" then
        SetSelectedCategoryIndex(-2)
    end

    GoldLedger.Register("bags", OnGoldChanged)

    -- Position: default 50px from bottom-left, saved position overrides
    if BP().bagsPosition then
        local pos = BP().bagsPosition
        EUI_Bags:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        EUI_Bags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 50)
    end

    EUI_Bags:SetClampedToScreen(true)
    EUI_Bags:ApplyWindowLayering()
    EUI_Bags:EnableMouse(true)
    EUI_Bags:SetMovable(true)

    -- Bag frame drag: left-drag while unlocked, OnMouseDown/OnUpdate pattern (no RegisterForDrag)
    local _bagDragging = false
    local _bagDragStartCX, _bagDragStartCY = 0, 0
    local _bagDragStartLeft, _bagDragStartTop = 0, 0
    local _bagDragFrame = CreateFrame("Frame")
    _bagDragFrame:Hide()
    _bagDragFrame:SetScript("OnUpdate", function(self)
        if not _bagDragging then self:Hide(); return end
        if not IsMouseButtonDown("LeftButton") then
            _bagDragging = false
            self:Hide()
            local left, top = EUI_Bags:GetLeft(), EUI_Bags:GetTop()
            if left and top then
                local PP = EUI and EUI.PP
                if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
                BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
                EUI_Bags:ClearAllPoints()
                EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            return
        end
        local cx, cy = GetCursorPosition()
        local es = EUI_Bags:GetEffectiveScale()
        local newLeft = _bagDragStartLeft + (cx / es - _bagDragStartCX)
        local newTop = _bagDragStartTop + (cy / es - _bagDragStartCY)
        EUI_Bags:ClearAllPoints()
        EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)
    EUI_Bags:SetScript("OnMouseDown", function(self, button)
        self:Raise()
        self:RepinIconLevels()
        -- Locked (the footer's lock icon): the window stays put. Nor does it move
        -- while something is on the cursor: a click on its empty space drops an
        -- item from outside the bags (the OnMouseUp hook below).
        if button ~= "LeftButton" or BP().bagWindowLocked or GetCursorInfo() then return end
        local cx, cy = GetCursorPosition()
        local es = self:GetEffectiveScale()
        _bagDragStartCX = cx / es
        _bagDragStartCY = cy / es
        _bagDragStartLeft = self:GetLeft()
        _bagDragStartTop = self:GetTop()
        if not _bagDragStartLeft or not _bagDragStartTop then return end
        _bagDragging = true
        _bagDragFrame:Show()
    end)
    EUI_Bags:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and _bagDragging then
            _bagDragging = false
            _bagDragFrame:Hide()
            local left, top = EUI_Bags:GetLeft(), EUI_Bags:GetTop()
            if left and top then
                local PP = EUI and EUI.PP
                if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
                BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
                EUI_Bags:ClearAllPoints()
                EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
    end)

    EUI_Bags.bg = EUI_Bags:CreateTexture(nil, "BACKGROUND", nil, 0)
    EUI_Bags.bg:SetAllPoints()
    EUI_Bags.bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    EUI_Bags.bg:SetTexCoord(0, 1, 0, 1)

    -- Dark overlay on top of the atlas (25% black)
    EUI_Bags.bgOverlay = EUI_Bags:CreateTexture(nil, "BACKGROUND", nil, 1)
    EUI_Bags.bgOverlay:SetAllPoints()
    EUI_Bags.bgOverlay:SetColorTexture(0, 0, 0, 0.25)

    if EUI and EUI.PanelPP then
        EUI.PanelPP.CreateBorder(EUI_Bags, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end

    local PadBagsShown  -- controller cursor show edge (defined below)

    -- Blizzard's backpack open/close sounds, played on the frame's show/hide
    -- transitions as Blizzard's container frames do: a Show on an already open
    -- bag fires no OnShow, and the login pre-build never shows the frame.
    EUI_Bags:HookScript("OnShow", function(self)
        self:Raise()
        self:RepinIconLevels()
        PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
        -- Repaint if the unmerge state changed while hidden: the flag-flip refresh is gated on
        -- IsVisible, and closing a mailbox hides bags in the same breath so that repaint is thrown away (costs one boolean compare when already matching).
        -- Same for session unmerge marks: the close that hid the bags wiped
        -- them, so a layout painted with marks must merge again on show.
        if _paintedPanelOpen ~= _anyItemPanelOpen or EUI_Bags._paintedUnmerged then
            EUI_Bags:RefreshInventory()
        end
        -- Controller cursor: scroll aids and the carried-item drop button,
        -- built only once a controller is in use.
        if EUI_Bags._padBuilt or EUI.PadInUse() then PadBagsShown() end
        -- The one-time "categories can be dragged" tip, until its Okay
        if not EllesmereUIDB.bagCategoryTipSeen then ns.ShowCategoryTip() end
    end)

    EUI_Bags:HookScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        EUI_Bags._closeSoundAt = GetTime()
        -- A tip left up without Okay must not come back with the window (in combat too)
        if EUI_Bags._catTip then EUI_Bags._catTip:Hide() end
        if EUI_Bags._searchBox then
            EUI_Bags._searchBox:SetText("")
            EUI_Bags._searchBox:ClearFocus()
        end
    end)

    -- An item on the cursor that is not from the player's bags (bank withdrawals, mail, etc.).
    local function CursorItemIsExternal()
        if GetCursorInfo() ~= "item" then return false end
        -- The cursor item's own location is its pickup source: a slot of the
        -- player's bags (bag 0-5, reagent bag included) when it came from them.
        local loc = C_Cursor.GetCursorItem()
        if loc and loc:IsBagAndSlot() then
            local bag = loc:GetBagAndSlot()
            if bag >= 0 and bag <= 5 then return false end
        end
        return true
    end
    -- External item: place in first empty bag slot (same as looting), never in
    -- a WoW Forever special bag.
    local function PlaceExternalCursorItem()
        if not CursorItemIsExternal() then return end
        local special = ns.SpecialBags()
        for bag = 0, 4 do
            local numSlots = (special and special[bag]) and 0 or C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                if not C_Container.GetContainerItemInfo(bag, slot) then
                    C_Container.PickupContainerItem(bag, slot)
                    return
                end
            end
        end
    end
    -- Click or drag release on empty bag window space with an item from
    -- outside the bags (bank, mail, ...) on the cursor: it goes to the first
    -- empty bag slot. An item picked up from the bags stays on the cursor.
    EUI_Bags:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then PlaceExternalCursorItem() end
    end)
    EUI_Bags:SetScript("OnReceiveDrag", PlaceExternalCursorItem)

    -- Drop target: while an item from outside the bags is on the cursor, a
    -- catch layer over the item area's empty space takes the same drop and the
    -- window lights its border. The layer sits UNDER the slots, so a drop on a
    -- slot always reaches the slot (stack merges, gear swaps). Whether the
    -- cursor item is from outside is read from its location, cached until the
    -- cursor or an item lock changes; the Compact display's drop zones read the same cache
    -- and follow the same watch. The events are registered only while the
    -- bags are open; everything is built on first use.
    local dropBorder, dropCatch
    local hoverFrame, hoverCatch = false, false
    local extCache, extDirty = false, true
    function ns.CursorItemExternalCached()
        if extDirty then
            extCache = CursorItemIsExternal()
            extDirty = false
        end
        return extCache
    end
    local function SyncDropBorder()
        local layer = ns.CursorItemExternalCached() and EUI_Bags:IsVisible()
        if layer and not dropCatch then
            dropCatch = CreateFrame("Frame", nil, EUI_Bags)
            dropCatch:Hide()
            dropCatch:EnableMouse(true)
            dropCatch:EnableMouseWheel(true)
            dropCatch:SetScript("OnMouseWheel", function(_, delta)
                local sf = EUI_Bags._scrollFrame
                local wheel = sf and sf:GetScript("OnMouseWheel")
                if wheel then wheel(sf, delta) end
            end)
            dropCatch:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then PlaceExternalCursorItem() end
            end)
            dropCatch:SetScript("OnReceiveDrag", PlaceExternalCursorItem)
            dropCatch:SetScript("OnEnter", function() hoverCatch = true; SyncDropBorder() end)
            dropCatch:SetScript("OnLeave", function() hoverCatch = false; SyncDropBorder() end)
            dropCatch:SetScript("OnHide", function() hoverCatch = false end)
        end
        if dropCatch then
            if layer and not dropCatch:IsShown() then
                -- Just above the window, under the slots.
                dropCatch:SetFrameLevel(EUI_Bags:GetFrameLevel() + 1)
                dropCatch:ClearAllPoints()
                dropCatch:SetAllPoints(EUI_Bags._scrollFrame)
            end
            dropCatch:SetShown(layer and true or false)
        end
        local on = layer and (hoverFrame or hoverCatch)
        if on and not dropBorder then
            dropBorder = CreateFrame("Frame", nil, EUI_Bags)
            dropBorder:SetAllPoints()
            dropBorder:SetFrameLevel(EUI_Bags:GetFrameLevel() + 60)
            dropBorder:EnableMouse(false)
            CreateInsetBorder(dropBorder)
        end
        if not dropBorder then return end
        if on then
            local r, g, bl = GetAccentRGB()
            SetInsetBorderColor(dropBorder, r, g, bl, 1)
        end
        dropBorder:SetShown(on and true or false)
    end
    EUI_Bags._syncDropTarget = SyncDropBorder
    EUI_Bags:HookScript("OnEnter", function() hoverFrame = true; SyncDropBorder() end)
    EUI_Bags:HookScript("OnLeave", function() hoverFrame = false; SyncDropBorder() end)
    local cursorWatch = CreateFrame("Frame")
    cursorWatch:SetScript("OnEvent", function(_, event)
        extDirty = true
        -- A lock change only matters with an item on the cursor (the pickup's
        -- source slot locks); sorts lock and unlock slots constantly.
        if event == "CURSOR_CHANGED" or GetCursorInfo() == "item" then
            SyncDropBorder()
            -- The Compact display's drop zones (EllesmereUIBags_Compact.lua)
            ns.CompactZonesSync()
        end
    end)
    EUI_Bags:HookScript("OnShow", function()
        cursorWatch:RegisterEvent("CURSOR_CHANGED")
        cursorWatch:RegisterEvent("ITEM_LOCK_CHANGED")
        extDirty = true
    end)
    EUI_Bags:HookScript("OnHide", function()
        cursorWatch:UnregisterEvent("CURSOR_CHANGED")
        cursorWatch:UnregisterEvent("ITEM_LOCK_CHANGED")
        hoverFrame = false
        extDirty = true
        SyncDropBorder()
    end)

    -- Controller cursor: empty slots take no presses in the All Items and
    -- category views, so an item carried in from the bank or mail gets a
    -- "Place in Bags" footer button. The cursor watch is registered only
    -- while the bags are open with a controller in use.
    local function PadPlaceSync()
        EUI_Bags._padPlaceBtn:SetShown(CursorItemIsExternal())
    end
    local function PadPlaceButton()
        local footer = EUI_Bags.Footer
        local b = CreateFrame("Button", nil, footer)
        b:SetHeight(22)
        b:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 8, 5)
        b:SetFrameLevel(footer:GetFrameLevel() + 20)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        local PP = EUI and EUI.PP
        if PP and PP.CreateBorder then PP.CreateBorder(b, 0.25, 0.25, 0.25, 1) end
        local fs = b:CreateFontString(nil, "OVERLAY")
        SetBagFont(fs, 11)
        fs:SetPoint("CENTER", 0, 0)
        fs:SetTextColor(1, 1, 1, 0.9)
        fs:SetText(EllesmereUI.L("Place in Bags"))
        b:SetWidth(fs:GetStringWidth() + 20)
        b:SetScript("OnEnter", function() bg:SetColorTexture(0.2, 0.2, 0.2, 1) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(0.15, 0.15, 0.15, 1) end)
        b:SetScript("OnClick", function() PlaceExternalCursorItem() end)
        b:Hide()
        EUI_Bags._padPlaceBtn = b
        local watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", PadPlaceSync)
        EUI_Bags._padCursorWatch = watch
    end
    -- Show edge (gated at the call): scroll aids, sidebar steps, drop button.
    PadBagsShown = function()
        local on = EUI.PadInUse()
        EUI_Bags._padBuilt = true
        if EUI_Bags._scrollTrack then EUI_Bags._scrollTrack.PadSync(on) end
        ns.PadSidebarSync(EUI_Bags._sidebarHdr, EUI_Bags._sidebarSF, EUI_Bags._sidebarChild, "bagSidebarCollapsed", on)
        local watch = EUI_Bags._padCursorWatch
        if on then
            if not watch then PadPlaceButton(); watch = EUI_Bags._padCursorWatch end
            watch:RegisterEvent("CURSOR_CHANGED")
            watch:RegisterEvent("ITEM_LOCK_CHANGED")
            PadPlaceSync()
        elseif watch then
            watch:UnregisterAllEvents()
            EUI_Bags._padPlaceBtn:Hide()
        end
    end

    CreateHeader()
    CreateFooter()
    CreateSidebar()
    CreateBagScrollFrame()
    CreateReagentBagUI()

    -- Bag overview window
    EUI_BagsWindow:SetSize(280, 80)
    EUI_BagsWindow:SetPoint("BOTTOMRIGHT", EUI_Bags._bagsBtn, "TOPRIGHT", 0, 2)
    EUI_BagsWindow:SetFrameStrata(EUI_Bags:GetFrameStrata())
    EUI_BagsWindow:SetToplevel(true)
    -- Toplevel only raises on a click: opening it brings it forward too, over
    -- a panel (Auction House, bank) raised after the bags.
    EUI_BagsWindow:HookScript("OnShow", EUI_BagsWindow.Raise)
    EUI_BagsWindow:EnableMouse(true)
    EUI_BagsWindow.bg = EUI_BagsWindow:CreateTexture(nil, "BACKGROUND")
    EUI_BagsWindow.bg:SetAllPoints()
    EUI_BagsWindow.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(EUI_BagsWindow, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end
    EllesmereUI.RegisterEscapeClose(EUI_BagsWindow)

    EUI_BagsReagent:SetSize(320, 300)
    EUI_BagsReagent:SetPoint("BOTTOMRIGHT", EUI_Bags, "BOTTOMLEFT", -10, 0)
    EUI_BagsReagent:SetFrameStrata(EUI_Bags:GetFrameStrata())
    EUI_BagsReagent:SetToplevel(true)
    EUI_BagsReagent:HookScript("OnShow", function(self)
        self:Raise()
        -- Re-pins the reagent pool too
        EUI_Bags:RepinIconLevels()
    end)
    EUI_BagsReagent:EnableMouse(true)
    EUI_BagsReagent.bg = EUI_BagsReagent:CreateTexture(nil, "BACKGROUND")
    EUI_BagsReagent.bg:SetAllPoints()
    EUI_BagsReagent.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(EUI_BagsReagent, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end

    EUI_BagsReagent:RegisterEvent("BAG_UPDATE")
    EUI_BagsReagent:SetScript("OnEvent", function(self, event)
        if event == "BAG_UPDATE" then
            local detach = BP().detachReagentBag or false
            if detach and EUI_BagsReagent:IsVisible() then EUI_BagsReagent:RefreshInventory() end
        end
    end)
    EllesmereUI.RegisterEscapeClose(EUI_BagsReagent)
    -- The detached reagent bag closed on its own plays the backpack close
    -- sound. Silent when the main bag closed in the same frame (it already
    -- played) or when only its parent hid (its own shown flag is still set).
    EUI_BagsReagent:HookScript("OnHide", function(self)
        if not self:IsShown() and EUI_Bags._closeSoundAt ~= GetTime() then
            PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        end
    end)

    local OriginalToggleAllBags = ToggleAllBags
    local function ToggleEUI()
        if EUI_Bags:IsVisible() then
            EUI_Bags:Hide()
            EUI_BagsReagent:Hide()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.bagsVisible = false
            -- Controller cursor: keep Blizzard's hidden bag frames closed too.
            if EUI.PadInUse() then ns.PadReleaseBlizzBags() end
        else
            -- Controller cursor: gamepad pointer on at this user-requested
            -- open, as Blizzard's own bag toggle does (one C call when no
            -- gamepad is active).
            if EUI.PadNative() then
                EUI.RaiseGamePadCursor()
                -- WoW Forever: the Gamepad interface style was switched on
                -- since login. Its D-pad cannot reach our bags, so they stay
                -- closed until a reload.
                if EUI.IS_FOREVER and EUI.PadGamepadUI() then
                    ns.PadStyleChanged()
                    return
                end
            end
            ApplyBagScale()
            EUI_Bags:Show()
            EUI_Bags:RefreshInventory()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            -- Seed default pinned items on first ever open
            if not EllesmereUIDB.bagPinsSeeded then
                EllesmereUIDB.bagPinsSeeded = true
                if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
                EllesmereUIDB.bagPinnedItems[6948] = 1    -- Hearthstone
                EllesmereUIDB.bagPinnedItems[180653] = 1  -- Nomi Snacks
            end
            -- Auto-sort on first ever open
            if not EllesmereUIDB.bagInitialSortDone and EUI_Bags._doVisualSort then
                EllesmereUIDB.bagInitialSortDone = true
                EUI_Bags._doVisualSort()
            end
            EllesmereUIDB.bagsVisible = true
            local detach = BP().detachReagentBag or false
            if detach then
                EUI_BagsReagent:Show()
                EUI_BagsReagent:RefreshInventory()
            end
        end
    end

    local characterBagHooksInstalled = false
    function ns.ToggleBagsWithCharacterFrame()
        if not BP().bagOpenWithCharacter then return end
        -- WoW Forever's Gamepad interface style: no hooks on Blizzard windows (see the stand-down below).
        if ns.PadUIStandDown() then return end
        local frame = _G.CharacterFrame
        if not frame then return end
        if not characterBagHooksInstalled then
            characterBagHooksInstalled = true
            frame:HookScript("OnShow", function()
                if BP().bagOpenWithCharacter and not EUI_Bags:IsVisible() then
                    ToggleEUI()
                end
            end)
            frame:HookScript("OnHide", function()
                if BP().bagOpenWithCharacter and EUI_Bags:IsVisible() then
                    ToggleEUI()
                end
            end)
        end
    end
    ns.ToggleBagsWithCharacterFrame()

    local _lastToggleTime = 0
    local function SmartToggleBags()
        -- Debounce: Blizzard keybinds can fire both ToggleAllBags and C_Container.ToggleAllBags in the same frame, causing a double-toggle.
        if GetTime() == _lastToggleTime then return end
        _lastToggleTime = GetTime()
        local enhancedEnabled = BP().enhancedBags ~= false
        if enhancedEnabled then ToggleEUI()
        else if OriginalToggleAllBags then OriginalToggleAllBags() end end
    end

    -- WoW Forever with the Gamepad interface style at login: Blizzard's own
    -- bags keep the D-pad navigation, so none of the takeover below runs
    -- (false on retail and for every other Forever player).
    if ns.PadUIStandDown() then
        -- A switch back to another style: the takeover follows a reload.
        local function StyleCheck()
            if not EUI.PadGamepadUI() then ns.PadStyleChanged() end
        end
        hooksecurefunc("ToggleAllBags", StyleCheck)
        hooksecurefunc("ToggleBackpack", StyleCheck)
    else
    ToggleAllBags = SmartToggleBags
    -- Hook ToggleBackpack/ToggleBag via hooksecurefunc (avoids tainting the global)
    hooksecurefunc("ToggleBackpack", SmartToggleBags)

    -- Hide Blizzard bag frames by reparenting to a hidden container (never write .Show/.Hide onto Blizzard frames -- causes taint).
    local _blizzBagHidden = CreateFrame("Frame")
    _blizzBagHidden:Hide()

    -- WoW Forever's keyring (bag -2) has no place in our bag window, so its
    -- button keeps opening Blizzard's own keyring window: the one bag frame
    -- let back out of the hidden container while it shows.
    local KEYRING = EUI.IS_FOREVER and Enum.BagIndex and Enum.BagIndex.Keyring or nil
    local function IsKeyringFrame(f)
        return KEYRING ~= nil and f:IsShown() and f.MatchesBagID ~= nil and f:MatchesBagID(KEYRING)
    end

    local function KillBlizzard()
        for i = 1, 13 do
            local f = _G["ContainerFrame"..i]
            if f and not IsKeyringFrame(f) then f:SetParent(_blizzBagHidden) end
        end
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:SetParent(_blizzBagHidden)
        end
    end
    KillBlizzard()

    local keyringHooked = setmetatable({}, { __mode = "k" })
    hooksecurefunc("ToggleBag", function(id)
        if KEYRING and id == KEYRING then
            -- Blizzard just opened or closed it; only an open one comes out.
            local f = ContainerFrameUtil_GetShownFrameForID and ContainerFrameUtil_GetShownFrameForID(KEYRING)
            if f then
                f:SetParent(ContainerFrameContainer or UIParent)
                if not keyringHooked[f] then
                    keyringHooked[f] = true
                    -- The frames are shared: once closed (its own shown flag
                    -- clear, not just a hidden UI), any bag it shows next stays hidden.
                    f:HookScript("OnHide", function(self)
                        if not self:IsShown() then self:SetParent(_blizzBagHidden) end
                    end)
                end
            end
            return
        end
        SmartToggleBags()
    end)

    hooksecurefunc("OpenAllBags", function()
        if not EUI_Bags:IsVisible() then ToggleEUI() end
        KillBlizzard()
    end)
    end -- not ns.PadUIStandDown()

    -- Recent Items: session-only tracking (resets on login/reload)
    -- Raised from 12 to 15.
    local RECENT_MAX = 15
    EUI_Bags._recentItems = {}      -- itemID -> pickup number (higher = newer; ns.RecentCompare sorts by it)
    EUI_Bags._recentOrder = {}      -- ordered list of itemIDs (oldest first)
    EUI_Bags._recentSeq = 0         -- last pickup number handed out
    local _knownItemCounts = {} -- itemID -> highest carried count (bags + worn gear) since the last bank/mail resync
    local _snapshotReady = false

    -- Both are interaction state, not frame visibility -- a third-party bank/mail
    -- addon can hide the stock frame, but the server-tracked interaction stays
    -- accurate. Bank/warband bank contents are only queryable while physically
    -- there (or via a Personal Distance Inhibitor), so unlike mail there's no
    -- way to count them from a distance -- detection just freezes at the bank
    -- instead, the same as it does for mail.
    local function MailOpen()
        return (C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType
            and C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.MailInfo)) and true or false
    end
    local function BankOpen()
        if not (C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType) then return false end
        return (C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.Banker)
            or C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.AccountBanker)) and true or false
    end

    -- One total per item across the bags AND worn gear: equipping, taking off
    -- and equipment set swaps only move an item between the two, so its total
    -- holds and nothing re-flags, while loot still raises it. Slots 1-30 are
    -- gear and profession gear, 31-35 the equipped bags; a worn stack (a thrown
    -- weapon stack on WoW Forever) counts by its size. The ammo slot (0) is
    -- skipped: it names a type whose ammo is already counted in the bags.
    local function TallyItemCounts()
        local counts, order = {}, {}
        for bag = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    if not counts[info.itemID] then order[#order + 1] = info.itemID end
                    counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 0)
                end
            end
        end
        for slot = INVSLOT_FIRST_EQUIPPED, CONTAINER_BAG_OFFSET + NUM_TOTAL_EQUIPPED_BAG_SLOTS do
            local itemID = GetInventoryItemID("player", slot)
            if itemID then
                if not counts[itemID] then order[#order + 1] = itemID end
                counts[itemID] = (counts[itemID] or 0) + (GetInventoryItemCount("player", slot) or 1)
            end
        end
        return counts, order
    end

    local function SnapshotKnownIDs()
        _knownItemCounts = TallyItemCounts()
        _snapshotReady = true
    end

    -- A rise flags a new pickup; a drop (sold/used/deleted) lowers the known
    -- total so a later re-acquisition below the old peak still registers as
    -- new. Frozen entirely at a bank/warband bank -- depositing and withdrawing
    -- look identical to disposing of and looting, since bag contents are all
    -- this can see. MAIL_CLOSED, BANKFRAME_CLOSED, and
    -- PLAYER_INTERACTION_MANAGER_FRAME_HIDE below silently resync once the
    -- mailbox/bank closes, so none of that traffic falsely flags or evicts
    -- anything.
    --
    -- A mailbox is only half that problem, so it no longer freezes both ways: a
    -- RISE there can only be an item arriving (sending lowers a count, never
    -- raises one), which is what left auction returns landing with no trace.
    -- Drops stay ignored: sent, sold and deleted are indistinguishable.
    local function DetectNewItems()
        if not _snapshotReady or BankOpen() then return end
        local atMail = MailOpen()
        local counts, order = TallyItemCounts()
        for _, itemID in ipairs(order) do
            local count = counts[itemID]
            local known = _knownItemCounts[itemID] or 0
            if count > known then
                -- New, or more of a listed item: either way it is the newest now
                local recent, ro = EUI_Bags._recentItems, EUI_Bags._recentOrder
                if recent[itemID] then
                    for i = #ro, 1, -1 do
                        if ro[i] == itemID then table.remove(ro, i); break end
                    end
                end
                EUI_Bags._recentSeq = EUI_Bags._recentSeq + 1
                recent[itemID] = EUI_Bags._recentSeq
                ro[#ro + 1] = itemID
                while #ro > RECENT_MAX do
                    recent[table.remove(ro, 1)] = nil
                end
            end
            if not atMail or count > known then
                _knownItemCounts[itemID] = count
            end
        end
        -- Items gone entirely (sold/used/deleted) no longer appear in `counts`;
        -- drop their known peak too. Worn gear is in `counts`, so an equipped
        -- item keeps its peak and taking it off later re-flags nothing.
        -- Skipped at the mailbox for the same reason drops are ignored above: an item
        -- gone from bags there was as likely posted or sent as disposed of, and
        -- dropping its peak would re-flag it as new the moment it came back.
        if not atMail then
            for itemID in pairs(_knownItemCounts) do
                if not counts[itemID] then
                    _knownItemCounts[itemID] = nil
                end
            end
        end
    end

    -- "Clear" link on the Recent Items headers. Only the tracked set is dropped --
    -- _knownItemCounts already holds each item's current carried total, so nothing
    -- sitting in bags re-flags as new on the next DetectNewItems pass.
    function EUI_Bags:ClearRecentItems()
        wipe(EUI_Bags._recentItems)
        wipe(EUI_Bags._recentOrder)
        if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
    end

    C_Timer.After(1, function() SnapshotKnownIDs() end)

    -- Debounced full refresh: one code path, no stale state. The first paint of a
    -- window stays at 0.1 s. When events kept landing during that window a burst is
    -- under way, so the NEXT windows re-arm on the trailing edge instead (at most
    -- four 0.1 s deferrals): a loot or vendor burst that fires BAG_UPDATE every few
    -- frames rebuilds about twice a second and once more after it settles, instead
    -- of ten times a second for the whole burst. An isolated event is untouched.
    local refreshPending, refreshAgain, refreshDefers, refreshBurst = false, false, 0, false
    EUI_Bags.refreshEnabled = true
    local function FireRefresh()
        if refreshBurst and refreshAgain and refreshDefers < 4 then
            refreshAgain = false
            refreshDefers = refreshDefers + 1
            C_Timer.After(0.1, FireRefresh)
            return
        end
        refreshBurst = refreshAgain
        if EUI_Bags:IsVisible() then
            EUI_Bags:RefreshInventory()
            local detach = BP().detachReagentBag or false
            if detach and EUI_BagsReagent:IsVisible() then EUI_BagsReagent:RefreshInventory() end
        end
        refreshPending, refreshAgain, refreshDefers = false, false, 0
    end
    local function ScheduleRefresh()
        if not EUI_Bags.refreshEnabled then return end
        if refreshPending then refreshAgain = true; return end
        refreshPending, refreshAgain, refreshDefers = true, false, 0
        C_Timer.After(0.1, FireRefresh)
    end

    EUI_Bags:RegisterEvent("BAG_UPDATE")
    -- Equipping / unequipping a bag: its BAG_UPDATE can land before the slot
    -- counts change; BAG_UPDATE_DELAYED fires once the whole batch settles
    EUI_Bags:RegisterEvent("BAG_UPDATE_DELAYED")
    EUI_Bags:RegisterEvent("ITEM_LOCK_CHANGED")
    EUI_Bags:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    -- A keystone's encoded level changing (downgrade on completion, or on reset)
    -- doesn't reliably fire BAG_UPDATE for its slot, so the keystone level text
    -- painted by RefreshInventory goes stale while bags stay open across the
    -- run -- GameTooltip looks correct because it re-queries fresh on every
    -- hover, independent of our repaint cycle. Force a refresh on these too.
    EUI_Bags:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    EUI_Bags:RegisterEvent("CHALLENGE_MODE_RESET")
    -- Lindormi's NPC-dialogue keystone downgrade is the same in-place encoded-
    -- level change as above, just triggered outside any dungeon run -- neither
    -- CHALLENGE_MODE event applies (both are scoped to an active M+ run's
    -- lifecycle). GOSSIP_CLOSED is the generic "an NPC dialogue just ended"
    -- signal and fires reliably around her interaction; it also fires for every
    -- unrelated NPC gossip close, but ScheduleRefresh below is cheap and gated
    -- on bags being visible, so that's a harmless no-op rather than a real cost.
    EUI_Bags:RegisterEvent("GOSSIP_CLOSED")
    -- Set created/renamed/deleted: rebuild split categories / refresh name labels.
    -- Registered only while a set feature is on: zero event cost when disabled
    -- (merged-mode routing stays correct without it -- the lookup rebuilds per
    -- classify pass; the event only serves the split children and name labels).
    function EUI_Bags.UpdateSetEventRegistration()
        if BP().bagSplitSetGearBySet or BP().bagShowSetGearName == true then
            EUI_Bags:RegisterEvent("EQUIPMENT_SETS_CHANGED")
        else
            EUI_Bags:UnregisterEvent("EQUIPMENT_SETS_CHANGED")
        end
    end
    EUI_Bags.UpdateSetEventRegistration()
    -- Replays a refresh that was deferred during combat (secure-button taint guard).
    EUI_Bags:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Ellesmere: moved unchanged by the file split
    -- Drives the post-mailbox/bank Recent Items resync (see MailOpen/BankOpen/DetectNewItems above).
    if C_PlayerInteractionManager then
        EUI_Bags:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    end

    -- Panels that move items one bag slot at a time (see SetItemPanelOpen).
    local ITEM_PANEL_EVENTS = {
        -- No MAIL_SHOW: the Inbox never takes items OUT of bags, so unmerging there churns for
        -- nothing -- only Send Mail matters (hooked below). MAIL_CLOSED is a belt against a stuck flag if the frame vanishes without its OnHide running.
        MAIL_CLOSED           = { "sendmail",  false },
        TRADE_SHOW            = { "trade",     true  },
        TRADE_CLOSED          = { "trade",     false },
        AUCTION_HOUSE_SHOW    = { "auction",   true  },
        AUCTION_HOUSE_CLOSED  = { "auction",   false },
        MERCHANT_SHOW         = { "merchant",  true  },
        MERCHANT_CLOSED       = { "merchant",  false },
        BANKFRAME_OPENED      = { "bank",      true  },
        BANKFRAME_CLOSED      = { "bank",      false },
        GUILDBANKFRAME_OPENED = { "guildbank", true  },
        GUILDBANKFRAME_CLOSED = { "guildbank", false },
    }
    -- pcall belt: RegisterEvent on an unknown event name is a HARD error, and this loop runs
    -- BEFORE the OnEvent wiring below, so one bad name kills StartAddon; a panel lost to a patch rename must degrade to "that panel doesn't unmerge", never a dead bags addon.
    for evt in pairs(ITEM_PANEL_EVENTS) do
        local ok = pcall(EUI_Bags.RegisterEvent, EUI_Bags, evt)
        if not ok then ITEM_PANEL_EVENTS[evt] = nil end
    end

    -- Send Mail is driven off the frame, not MAIL_SHOW, so switching tabs inside an open
    -- mailbox flips the state too. Blizzard_MailFrame loads with no LoadOnDemand, so the frame exists by now; the guard is belt.
    local function HookSendMail(frame)
        if not frame or not frame.HookScript then return end
        local function flip(open)
            if SetItemPanelOpen("sendmail", open) and EUI_Bags:IsVisible() then
                EUI_Bags:RefreshInventory()
            end
        end
        frame:HookScript("OnShow", function() flip(true) end)
        frame:HookScript("OnHide", function() flip(false) end)
        -- Already on the Send Mail tab when hooked (/reload with mailbox open): OnShow already fired, so seed from live state.
        if frame:IsShown() then flip(true) end
    end
    HookSendMail(_G.SendMailFrame)

    -- Pre-warm the secure item-button pool out of combat: a ContainerFrameItemButtonTemplate created
    -- in lockdown is tainted (UseContainerItem() blocked in M+/Delves), so build every button we could
    -- need up front and let RefreshInventory only position/show clean ones. Slots the loading-screen
    -- pass already built are skipped; in lockdown this builds nothing and combat end tops it up.
    EUI_Bags:WarmSlotPool()

    -- Seed this character's tracked currencies from Blizzard's on first load
    if EllesmereUIDB and C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
        -- Only seed when this character's table is empty: first install, a
        -- fresh profile, or a character whose legacy seed was empty too.
        local co = CurrencyOrder()
        local hasAny = false
        if co then
            for _ in pairs(co) do hasAny = true; break end
        end
        if co and not hasAny then
            local order = 0
            for i = 1, 20 do
                local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                if not info then break end
                order = order + 1
                co[info.currencyTypesID] = order
            end
        end
    end

    -- Snapshot Blizzard's tracked currencies so we can diff on change.
    local _lastBlizzSet = {}
    local function ReadBlizzSet()
        local s = {}
        if C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
            for i = 1, 20 do
                local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                if not info then break end
                s[info.currencyTypesID] = true
            end
        end
        return s
    end
    _lastBlizzSet = ReadBlizzSet()

    -- Sync our currency list with Blizzard's currency tab: newly checked added, newly
    -- unchecked removed. Currencies added through our dropdown (never in Blizzard's set) are untouched.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("TokenFrame.OnTokenWatchChanged", function()
            if not EllesmereUIDB then return end
            local co = CurrencyOrder()
            if not co then return end
            local blizzSet = ReadBlizzSet()
            for cID in pairs(blizzSet) do
                if not co[cID] then
                    local maxOrder = 0
                    for _, ord in pairs(co) do
                        if type(ord) == "number" and ord > maxOrder then maxOrder = ord end
                    end
                    co[cID] = maxOrder + 1
                end
            end
            -- Remove currencies that were in Blizzard's set before but aren't now
            for cID in pairs(_lastBlizzSet) do
                if not blizzSet[cID] then
                    co[cID] = nil
                end
            end
            _lastBlizzSet = blizzSet
            if EUI_Bags:IsVisible() then
                SyncBagFrameToFooter()
            end
            EllesmereUI:RefreshPage()
        end, EUI_Bags)
    end

    -- DetectNewItems: one deferred pass per BAG_UPDATE burst, on the next
    -- frame. Same-frame dedupe alone stranded misses: the first event of a
    -- loot burst can tally before every bag involved is readable, and the
    -- skipped duplicates never re-ran the scan -- an item consumed before the
    -- next bag change (KP studies, planted seeds, learned cosmetics) was then
    -- missed forever. The deferred flush scans once, with the burst settled.
    local _detectQueued = false
    local function _DetectFlush() _detectQueued = false; DetectNewItems() end

    EUI_Bags:SetScript("OnEvent", function(self, event, interactionType)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Combat ended: build any slot the combat guard refused (a /reload in combat, a bag
            -- that grew while locked), shown or not, so the next fight opens a full grid; then
            -- replay any refresh deferred during combat.
            if EUI_Bags._poolShort then
                EUI_Bags._poolShort = nil
                EUI_Bags:WarmSlotPool()
            end
            if EUI_Bags._refreshPendingCombat then
                EUI_Bags._refreshPendingCombat = nil
                if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
                if EUI_BagsReagent:IsVisible() and EUI_BagsReagent.RefreshInventory then
                    EUI_BagsReagent:RefreshInventory()
                end
            end
            return
        end
        if event == "MAIL_CLOSED" or event == "BANKFRAME_CLOSED" then
            -- Legacy belt, doesn't reliably fire on retail; the interaction-
            -- manager HIDE below is the live driver. Settle first: mail's own
            -- delivery, or a bank auto-deposit, can still be landing items just
            -- after close -- and hold detection down through the settle window
            -- too (_snapshotReady gates DetectNewItems), or those in-flight
            -- items would flag against the stale frozen baselines the moment
            -- the interaction check reads closed.
            _snapshotReady = false
            C_Timer.After(0.5, SnapshotKnownIDs)
            -- No return: falls through to the ITEM_PANEL_EVENTS handling below.
        end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            if interactionType == Enum.PlayerInteractionType.MailInfo
                or interactionType == Enum.PlayerInteractionType.Banker
                or interactionType == Enum.PlayerInteractionType.AccountBanker then
                -- Same settle-window hold as the legacy branch above.
                _snapshotReady = false
                C_Timer.After(0.5, SnapshotKnownIDs)
            end
            return
        end
        local panel = ITEM_PANEL_EVENTS[event]
        if panel then
            -- Tracked even while bags are hidden: the panel that opens them (OpenAllBags) can fire in either order with this event.
            if SetItemPanelOpen(panel[1], panel[2]) and EUI_Bags:IsVisible() then
                EUI_Bags:RefreshInventory()
            end
            -- Sell Junk shows with the merchant (only once the Junk Marker built it)
            if panel[1] == "merchant" and EUI_Bags._junkBtn then EUI_Bags:SyncHeaderIcons() end
            return
        end
        if event == "EQUIPMENT_SETS_CHANGED" then
            -- Invalidate even while hidden: the next open must not classify with
            -- categories built from the old set list.
            EUI_Bags.InvalidateSetCategories()
            if EUI_Bags:IsVisible() then ScheduleRefresh() end
            return
        end
        if event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET"
           or event == "GOSSIP_CLOSED" then
            -- A keystone downgrade here doesn't need a hidden-side invalidation:
            -- the next manual open already forces a full RefreshInventory
            -- (ToggleEUI). This only matters while bags are already visible.
            if EUI_Bags:IsVisible() then ScheduleRefresh() end
            return
        end
        if event == "BAG_UPDATE" and EUI_Bags.refreshEnabled ~= false and not _detectQueued then
            _detectQueued = true
            C_Timer.After(0, _DetectFlush)
        end
        if not EUI_Bags:IsVisible() then return end
        if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
            if event == "BAG_UPDATE_DELAYED" then
                -- Equipped bag icons settle with the batch (bag equip / unequip)
                if EUI_BagsWindow:IsVisible() then EUI_BagsWindow:RefreshBags() end
                -- A refresh the batch's own BAG_UPDATE armed already lands after
                -- it; re-arming would mark every single change as a burst.
                if refreshPending then return end
            end
            if not EUI_Bags.refreshEnabled then return end
            if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
            ScheduleRefresh()
        elseif event == "ITEM_LOCK_CHANGED" then
            if not EUI_Bags.refreshEnabled then return end
            if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
            ScheduleRefresh()
        elseif event == "CURRENCY_DISPLAY_UPDATE" then
            SyncBagFrameToFooter()
        end
    end)

    EUI_Bags:HookScript("OnHide", function()
        EUI_BagsWindow:Hide()
        -- Controller cursor: the carried-item watch lives only while the bags are open.
        local watch = EUI_Bags._padCursorWatch
        if watch then
            watch:UnregisterAllEvents()
            EUI_Bags._padPlaceBtn:Hide()
        end
        -- The select modes (pin, assign, Junk Marker) end with the bags: their
        -- click catchers cover the screen (a real close only, not a hidden UI)
        if not EUI_Bags:IsShown() then
            if EUI_Bags._pinSelectMode then ExitPinSelectMode() end
            if EUI_Bags._assignSelectMode then ExitAssignSelectMode() end
        end
        -- Controller cursor: a Back press or a bank close hides the bags
        -- alone, so the detached reagent window goes with them.
        if EUI.PadInUse() and not EUI_Bags:IsShown() then
            EUI_BagsReagent:Hide()
        end
    end)

    EllesmereUI.RegisterEscapeClose(EUI_Bags)
end

-------------------------------------------------------------------------------
--  Loader
-------------------------------------------------------------------------------
-- Per loading-screen event, the most the combat-reload pool pass may take (ms). The pass
-- runs in this frame's own handler (its own script budget); whatever it leaves is built at
-- PLAYER_ENTERING_WORLD, still behind the loading screen, then at combat end.
local WINDOW_WARM_MS = 40
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        EUI_Bags:WarmSlotPool(WINDOW_WARM_MS)
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Scheduled first, so nothing in the pass below can stop the module from starting.
    C_Timer.After(0.5, function()
        StartAddon()
        EUI_Bags:Hide()
        EUI_BagsReagent:Hide()
    end)
    -- A /reload in combat: the 0.5s start lands after the loading screen, in lockdown, where
    -- the combat guard refuses every slot and the bags would open empty all fight. Timers do
    -- not run during the loading screen, so build the pool here, in it. The guard is
    -- untouched: if it refuses here too, nothing is built and combat end builds the pool.
    -- Normal logins skip this and keep the 0.5s pre-warm.
    local inCombat = UnitAffectingCombat("player")
    if not (issecretvalue and issecretvalue(inCombat)) and inCombat then
        if not EUI_Bags:WarmSlotPool(WINDOW_WARM_MS) and not InCombatLockdown() then
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
        end
    end
    -- Quality of Life > Item Icons (EUI_Bags_Slots.lua): nothing while QoL is off
    ns.RegisterItemIcons()
end)

-------------------------------------------------------------------------------
--  Shared with EllesmereUIBags_Grid.lua (loads after this file)
-------------------------------------------------------------------------------
function ns.GetSelection() return selectedCategoryIndex, selectedGroupName end
function ns.SetSelection(idx, group) SetSelectedCategoryIndex(idx); SetSelectedGroupName(group) end
ns.SLOT_SIZE, ns.SPACING = SLOT_SIZE, SPACING
ns.itemSlots = itemSlots
ns.itemDragFrame = _itemDragFrame
ns.catHeaders = _catHeaders
ns.expSubHeaders = _expSubHeaders
ns.QUEST_BORDER_COLOR = QUEST_BORDER_COLOR
ns.BagsItemUnusable = BagsItemUnusable
ns.GetFont = GetFont
ns.GetCatTitleSize = GetCatTitleSize
ns.SetInsetBorderThickness = SetInsetBorderThickness
ns.UpdatePawnArrow = UpdatePawnArrow
ns.PreCacheSortFields = PreCacheSortFields
-- Recent Items order in every view: newest pickup first (pickup numbers in
-- EUI_Bags._recentItems), the bag position breaking ties within one item
function ns.RecentCompare(a, b)
    local rec = EUI_Bags._recentItems
    local ra = (a.info and rec[a.info.itemID]) or 0
    local rb = (b.info and rec[b.info.itemID]) or 0
    if ra ~= rb then return ra > rb end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end
ns.VisualSortCompare = VisualSortCompare
ns.MergeDuplicates = MergeDuplicates
ns.ApplySavedOrder = ApplySavedOrder
ns.BuildExpansionBuckets = BuildExpansionBuckets
ns.BuildSlotBuckets = BuildSlotBuckets
ns.GetArmorySlotBucket = GetArmorySlotBucket
ns.ArmorySlotGroupingEnabled = ArmorySlotGroupingEnabled
ns.IsArmoryGearCategory = IsArmoryGearCategory
ns.IsGearOnlyGroup = IsGearOnlyGroup
ns.GetOrCreateCatHeader = GetOrCreateCatHeader
ns.GetOrCreateExpSubHeader = GetOrCreateExpSubHeader
ns.ShowRecentClearButton = ShowRecentClearButton
ns.GetOrCreatePinOverlay = GetOrCreatePinOverlay
ns.GetOrCreateAssignOverlay = GetOrCreateAssignOverlay
ns.ResetAssignOverlays = ResetAssignOverlays

-- The start values the copies were built from: nothing may read them again.
I._anyItemPanelOpen, I.selectedCategoryIndex = nil, nil
I.broken = false
