if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_Grid.lua
--  Grid bag display (bagDisplayMode = "grid"): the secure item-slot factory,
--  RenderButton, and the grid layout pass of EUI_Bags:RefreshInventory.
--  Mode is latched per session (EUI_Bags.IsListMode): in list mode nothing
--  here is ever built.
-------------------------------------------------------------------------------
local ns = select(2, ...)
if not (ns and ns.GetSelection) then return end

local EUI = EllesmereUI
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end
local GetItemInfo = C_Item.GetItemInfo
local GetItemQualityColor = C_Item.GetItemQualityColor

local SLOT_SIZE, SPACING = ns.SLOT_SIZE, ns.SPACING
local itemSlots = ns.itemSlots
local _itemDragFrame = ns.itemDragFrame
local _catHeaders = ns.catHeaders
local _expSubHeaders = ns.expSubHeaders
local QUEST_BORDER_COLOR = ns.QUEST_BORDER_COLOR
local BagsItemUnusable = ns.BagsItemUnusable
local GetFont = ns.GetFont
local GetCatTitleSize = ns.GetCatTitleSize
local SetBagFont = ns.SetBagFont
local CreateInsetBorder = ns.CreateInsetBorder
local SetInsetBorderColor = ns.SetInsetBorderColor
local SetInsetBorderThickness = ns.SetInsetBorderThickness
local SlotMiddleClick = ns.SlotMiddleClick
local UpdatePawnArrow = ns.UpdatePawnArrow
local IsItemPinned = ns.IsItemPinned
local PreCacheSortFields = ns.PreCacheSortFields
local VisualSortCompare = ns.VisualSortCompare
local MergeDuplicates = ns.MergeDuplicates
local ApplySavedOrder = ns.ApplySavedOrder

-- Junk category ordering: most valuable first by vendor sell value (unit sell
-- price x stack count), with the normal visual order as a stable tiebreak.
-- Callers must have run PreCacheSortFields first (the tiebreak relies on it).
local function SortJunkByVendor(items)
    for _, d in ipairs(items) do
        -- Sell price (GetItemInfo index 11) from the item LINK, not a bare
        -- itemID: C_Item.GetItemInfo (what GetItemInfo aliases here) returns nil
        -- for a bare id on this client, so the id form left every value at 0 and
        -- the sort fell back to visual order. The link form is what List view's
        -- Sell Price column uses, and PreCacheSortFields (run just above) has
        -- already warmed it.
        local price = (d.itemLink and select(11, GetItemInfo(d.itemLink))) or 0
        d._junkSell = price * ((d.info and d.info.stackCount) or 1)
    end
    table.sort(items, function(a, b)
        if a._junkSell ~= b._junkSell then return a._junkSell > b._junkSell end
        return VisualSortCompare(a, b)
    end)
end

-- Junk coin badge placement: each corner anchored to the matching button corner,
-- nudged a few px OUTSIDE so it overhangs the frame like a badge. Corner is picked
-- in the Junk cog; no per-user offsets.
local JUNK_COIN_CORNER = {
    TOPLEFT     = { "TOPLEFT",     "TOPLEFT",     -3,  3 },
    TOPRIGHT    = { "TOPRIGHT",    "TOPRIGHT",     3,  3 },
    BOTTOMLEFT  = { "BOTTOMLEFT",  "BOTTOMLEFT",  -3, -3 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT",  3, -3 },
}

local BuildExpansionBuckets = ns.BuildExpansionBuckets
local BuildSlotBuckets = ns.BuildSlotBuckets
-- Section label for a bag ID (MultiBag grid and list)
function ns.BagDisplayName(bag)
    if bag == 0 then return EllesmereUI.L("Backpack") end
    if bag == 5 then return EllesmereUI.L("Reagent Bag") end
    local invID = C_Container.ContainerIDToInventoryID(bag)
    local link = invID and GetInventoryItemLink("player", invID)
    return (link and GetItemInfo(link)) or EllesmereUI.Lf("Bag %d", bag)
end

local ArmorySlotGroupingEnabled = ns.ArmorySlotGroupingEnabled
local IsArmoryGearCategory = ns.IsArmoryGearCategory
local IsGearOnlyGroup = ns.IsGearOnlyGroup
local GetOrCreateCatHeader = ns.GetOrCreateCatHeader
local GetOrCreateExpSubHeader = ns.GetOrCreateExpSubHeader
local ShowRecentClearButton = ns.ShowRecentClearButton
local GetOrCreatePinOverlay = ns.GetOrCreatePinOverlay
local GetOrCreateAssignOverlay = ns.GetOrCreateAssignOverlay
local ResetAssignOverlays = ns.ResetAssignOverlays

-------------------------------------------------------------------------------
--  Slot Factory
-------------------------------------------------------------------------------
local function GetOrCreateSlot(idx)
    if itemSlots[idx] then return itemSlots[idx] end
    -- NEVER CreateFrame a secure ContainerFrameItemButtonTemplate in combat -- a button
    -- born in combat is tainted (UseContainerItem() -> ADDON_ACTION_FORBIDDEN in M+/Delves).
    -- Pre-warmed pool covers normal counts; past it, callers skip the slot until PLAYER_REGEN_ENABLED
    -- builds it (_poolShort).
    if InCombatLockdown() then EUI_Bags._poolShort = true; return nil end

    local slotParent = CreateFrame("Frame", nil, EUI_Bags)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:HookScript("OnDragStart", function()
        _itemDragFrame:Show()
    end)

    -- Right-click deposit routing to the selected bank tab (see BankRoutePreClick)
    btn:HookScript("PreClick", ns.BankRoutePreClick)
    btn:HookScript("OnClick", ns.BankRouteOnClick)

    btn:HookScript("OnMouseUp", SlotMiddleClick)

    -- Shift-click on a stack: the split dialog. Always on in the All Items and
    -- category views (they draw no empty slots, so Blizzard's cursor split has
    -- nowhere to land there); the Stack Splitter setting extends it to the rest.
    btn:HookScript("PostClick", function(self)
        EUI_Bags.ShowStackSplitter(self, ns.SplitTargetBags(self:GetParent():GetID()), EUI_Bags)
    end)

    local textOverlay = ns.SkinItemButton(btn, { anchorIcon = true, cooldownFont = true })
    local countSize = BP().bagCountFontSize or 11
    local fontPath = GetFont()

    -- Keystone level text (top-left, same as item level)
    if not btn.KeystoneText then
        btn.KeystoneText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.KeystoneText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.KeystoneText:SetTextColor(1, 1, 1, 1)
    end
    btn.KeystoneText:SetFont(fontPath, countSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.KeystoneText:SetText("")
    -- Keystone dungeon abbreviation (bottom-right, same position as stack count)
    if not btn.KeystoneDungeonText then
        btn.KeystoneDungeonText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.KeystoneDungeonText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
        btn.KeystoneDungeonText:SetTextColor(1, 1, 1, 1)
        btn.KeystoneDungeonText:SetJustifyH("RIGHT")
    end
    btn.KeystoneDungeonText:SetFont(fontPath, math.max(countSize - 2, 7), (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.KeystoneDungeonText:SetText("")

    -- Equipment set name FontString is lazy-created in RenderButton: never
    -- built while Show Set Name on Gear is off (zero cost disabled).

    itemSlots[idx] = btn
    return btn
end
ns.GetOrCreateSlot = GetOrCreateSlot

-------------------------------------------------------------------------------
--  RenderButton
-------------------------------------------------------------------------------
local function RenderButton(btn, data, _, col, row, startX, currentY, _, interactiveEmpties)
    local parent = btn:GetParent()
    parent:ClearAllPoints()
    parent:SetPoint("TOPLEFT", startX + (col * (SLOT_SIZE + SPACING)), currentY - (row * (SLOT_SIZE + SPACING)))
    parent:Show()
    btn:Show()

    btn:SetID(data.slot or 0)
    parent:SetID(data.bag or 0)

    -- Always clear overlays upfront (pooled buttons carry stale state from prior items)
    if btn.ProfessionQualityOverlay then
        btn.ProfessionQualityOverlay:SetAlpha(0)
    end
    if btn.IconOverlay then btn.IconOverlay:SetAlpha(0); btn.IconOverlay:Hide() end
    if btn.IconOverlay2 then btn.IconOverlay2:SetAlpha(0); btn.IconOverlay2:Hide() end

    -- Empty slot background (created once, reused)
    if not btn._emptyBg then
        btn._emptyBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        btn._emptyBg:SetAllPoints()
        btn._emptyBg:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\icon-bg.png")
    end

    if not data.info then
        btn:SetItemButtonTexture(nil)
        btn:SetItemButtonCount(0)
        SetItemButtonDesaturated(btn, false)
        if btn.icon then btn.icon:Hide() end
        btn._emptyBg:Show()
        if interactiveEmpties then
            btn:EnableMouse(true)
            btn._emptyBg:SetAlpha(0.6)
            SetInsetBorderColor(btn, 0.15, 0.15, 0.15, 0.5)
        else
            btn:EnableMouse(false)
            btn._emptyBg:SetAlpha(0.35)
            SetInsetBorderColor(btn, 0, 0, 0, 0.3)
        end
        -- Reset to 1px and drop the marker, or a pooled slot vacated by a quest item keeps the 2px gold border + atlas.
        SetInsetBorderThickness(btn, (EUI and EUI.PP and EUI.PP.mult) or 1)
        if btn._questMarker then btn._questMarker:Hide() end
        if btn._junkCoin then btn._junkCoin:Hide() end
        if btn.Cooldown then btn.Cooldown:Clear() end
        if btn.ItemLevelText then btn.ItemLevelText:SetText("") end
        if btn.KeystoneText then btn.KeystoneText:SetText("") end
        if btn.KeystoneDungeonText then btn.KeystoneDungeonText:SetText("") end
        if btn.BindTypeText then btn.BindTypeText:SetText("") end
        if btn.SetNameText then btn.SetNameText:SetText("") end
        if btn.ProfessionQualityOverlay then btn.ProfessionQualityOverlay:Hide() end
        if btn.IconBorder then btn.IconBorder:Hide() end
        if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
        if btn._warbankDim then btn._warbankDim:Hide() end
        btn:SetAlpha(1)
    else
        btn:EnableMouse(true)
        btn._emptyBg:Hide()
        if btn.icon then btn.icon:Show() end
        btn:SetItemButtonTexture(data.info.iconFileID)
        btn:SetItemButtonCount(data._mergedCount or data.info.stackCount)
        btn._isMerged = data._mergedCount and true or nil

        -- Desature: 1) locked items 2) junk items. "Junk" means grey (when the
        -- standalone Desaturate option is on) OR anything the Junk Marker feature
        -- classifies as junk (grey + player-marked). EUI_CategoryManager:IsJunk
        -- returns false whenever the feature is off, so marker items only react
        -- while it is enabled.
        local quality = data.info.quality or 1
        local markerJunk = EUI_CategoryManager and EUI_CategoryManager:IsJunk(data.info.itemID, quality)
        local isJunk = (BP().bagDesaturateJunkItems and quality == 0) or markerJunk
        SetItemButtonDesaturated(btn, data.info.isLocked or isJunk)

        -- Coin corner marker on junk items so marked (non-grey) items read as
        -- junk at a glance. Lazily created once per pooled button, shown/hidden
        -- per render.
        if markerJunk then
            if not btn._junkCoin then
                local c = btn:CreateTexture(nil, "OVERLAY", nil, 6)
                c:SetTexture(133784)  -- INV_Misc_Coin_01
                c:SetTexCoord(0.12, 0.88, 0.12, 0.88)  -- crop for a clean round edge
                c:SetSize(12, 12)
                -- Rounded badge to match the rounded header coin button.
                local cmask = btn:CreateMaskTexture()
                cmask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                cmask:SetAllPoints(c)
                c:AddMaskTexture(cmask)
                btn._junkCoin = c
            end
            -- Re-anchor each render so the chosen corner (and its outward lift)
            -- applies live when the cog option changes.
            local a = JUNK_COIN_CORNER[BP().bagJunkCoinCorner] or JUNK_COIN_CORNER.BOTTOMLEFT
            btn._junkCoin:ClearAllPoints()
            btn._junkCoin:SetPoint(a[1], btn, a[2], a[3], a[4])
            btn._junkCoin:Show()
        elseif btn._junkCoin then
            btn._junkCoin:Hide()
        end

        local filtered = data.info.isFiltered
        btn:SetAlpha(filtered and 0.2 or 1)
        if btn._textOverlay then btn._textOverlay:SetAlpha(filtered and 0.2 or 1) end

        local iType = data._giType

        -- Item Level + Upgrade Rank (gear only)
        if btn.ItemLevelText then
            if data._isGear then
                local showIlvl = BP().showItemlevelInBags ~= false
                if showIlvl then
                    btn.ItemLevelText:SetText(data._giIlvl or "")
                    -- Track color + rank (pre-cached on data table)
                    local r, g, b
                    local rankText = data._giTrackRank or ""
                    local trackColor = data._giTrackColor
                    if BP().itemlevelUseCustomColor and BP().itemlevelCustomColor then
                        r, g, b = BP().itemlevelCustomColor.r, BP().itemlevelCustomColor.g, BP().itemlevelCustomColor.b
                    elseif trackColor then
                        r, g, b = trackColor.r, trackColor.g, trackColor.b
                    else
                        r, g, b = GetItemQualityColor(data._giQuality or 1)
                    end
                    btn.ItemLevelText:SetTextColor(r, g, b, 1)
                    local countFS = btn.Count
                    if countFS and BP().bagShowTrackRank and rankText ~= "" then
                        countFS:SetText(rankText:match("^(%d+)/") or rankText)
                        countFS:SetTextColor(r, g, b, 1)
                        countFS:Show()
                    end
                else
                    btn.ItemLevelText:SetText("")
                end
            else
                btn.ItemLevelText:SetText("")
            end
        end

        -- Keystone: level top-left, abbreviated dungeon name bottom-right
        if btn.KeystoneText then
            if data._ksLevel then
                btn.KeystoneText:SetText(data._ksLevel)
                btn.KeystoneText:SetTextColor(data._ksR or 1, data._ksG or 1, data._ksB or 1, 1)
                if btn.KeystoneDungeonText then
                    btn.KeystoneDungeonText:SetText(data._ksAbbrev or "")
                    btn.KeystoneDungeonText:SetTextColor(1, 1, 1, 1)
                end
            else
                btn.KeystoneText:SetText("")
                if btn.KeystoneDungeonText then btn.KeystoneDungeonText:SetText("") end
            end
        end

        -- BoE/WuE bottom-left (gear only); skipped for quest starters, which use that corner for the quest marker.
        if btn.BindTypeText then
            if data._isGear and not data.info.isBound and not data._isQuestStarter
               and BP().bagDisplayBindType then
                EUI_Bags.SetBindTypeText(btn.BindTypeText, data._isWuE, data._giBindType, quality)
            else
                btn.BindTypeText:SetText("")
            end
        end

        -- Equipment set name bottom-center (stamped by ClassifyAll for set gear;
        -- stamping is gated on the toggle, so _setName is nil while it's off).
        -- FontString is lazy: never built while off; once built it is cleared on
        -- every render because buttons are pooled.
        if data._setName then
            -- Yields when the upgrade-track rank occupies Count in the same row
            -- (mirrors the rank-display condition in the ItemLevelText block above)
            local rankShown = data._isGear and BP().bagShowTrackRank
                and BP().showItemlevelInBags ~= false
                and (data._giTrackRank or "") ~= ""
            if not rankShown then
                if not btn.SetNameText then
                    local overlay = btn._textOverlay or btn
                    btn.SetNameText = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
                    btn.SetNameText:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
                    btn.SetNameText:SetTextColor(1, 1, 1, 1)
                    btn.SetNameText:SetJustifyH("CENTER")
                    btn.SetNameText:SetWordWrap(false)
                    btn.SetNameText:SetMaxLines(1)
                    btn.SetNameText:SetWidth(SLOT_SIZE - 4)
                    btn.SetNameText:SetFont(GetFont(), BP().bagSetNameFontSize or 9, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                end
                btn.SetNameText:SetText(data._setName)
            elseif btn.SetNameText then
                btn.SetNameText:SetText("")
            end
        elseif btn.SetNameText then
            btn.SetNameText:SetText("")
        end

        -- Profession quality overlay: let SetItemButtonQuality decide so every item type is covered, not just guessed "profession" ones.
        if data.itemLink then
            btn:SetItemButtonQuality(quality, data.itemLink, false, false)
        end
        -- Visibility via alpha 0/1 only (immune to parent inheritance), even though SetItemButtonQuality may have called Show() internally.
        if btn.ProfessionQualityOverlay then
            if btn.ProfessionQualityOverlay:IsShown() then
                btn.ProfessionQualityOverlay:SetAlpha(1)
                if btn._textOverlay then
                    btn.ProfessionQualityOverlay:SetParent(btn._textOverlay)
                end
            else
                btn.ProfessionQualityOverlay:SetAlpha(0)
            end
        end
        -- Cosmetic/warbound overlays: SetItemButtonQuality re-shows these, so handle AFTER it; reparent to textOverlay to render above inset borders.
        if btn.IconOverlay then
            if btn.IconOverlay:IsShown() then
                btn.IconOverlay:SetAlpha(1)
                if btn._textOverlay then btn.IconOverlay:SetParent(btn._textOverlay) end
            else
                btn.IconOverlay:SetAlpha(0)
            end
        end
        if btn.icon and data.info and data.info.itemID then
            if BagsItemUnusable(data.bag, data.slot, data.itemLink, data.info.itemID) then
                btn.icon:SetVertexColor(1, 0.1, 0.1)
            else
                btn.icon:SetVertexColor(1, 1, 1)
            end
        end
        if btn.IconOverlay2 then
            if btn.IconOverlay2:IsShown() then
                btn.IconOverlay2:SetAlpha(1)
                if btn._textOverlay then btn.IconOverlay2:SetParent(btn._textOverlay) end
            else
                btn.IconOverlay2:SetAlpha(0)
            end
        end
        if btn.IconBorder then btn.IconBorder:Hide() end
        if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end

        -- Quest items get a gold 2px border overriding the 1px quality border;
        -- thickness is re-set every render because buttons are pooled.
        local _bpx = (EUI and EUI.PP and EUI.PP.mult) or 1
        if data._isQuest then
            SetInsetBorderThickness(btn, _bpx * 2)
            SetInsetBorderColor(btn, QUEST_BORDER_COLOR.r, QUEST_BORDER_COLOR.g, QUEST_BORDER_COLOR.b, filtered and 0.2 or 1)
        else
            SetInsetBorderThickness(btn, _bpx)
            local c = ITEM_QUALITY_COLORS[quality]
            if c then
                SetInsetBorderColor(btn, c.r, c.g, c.b, filtered and 0.2 or 1)
            else
                SetInsetBorderColor(btn, 0.25, 0.25, 0.25, filtered and 0.2 or 1)
            end
        end
        -- Quest marker atlas (lazy, reused). Only for items that START a quest you
        -- have not accepted; active-quest objective items get the border, no marker.
        if data._isQuestStarter then
            if not btn._questMarker then
                local qm = (btn._textOverlay or btn):CreateTexture(nil, "OVERLAY", nil, 6)
                qm:SetAtlas("Crosshair_Quest_64")
                qm:SetSize(22, 22)
                qm:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -3, 2)
                btn._questMarker = qm
            end
            btn._questMarker:Show()
        elseif btn._questMarker then
            btn._questMarker:Hide()
        end

        -- Warbank dim overlay: dim non-warbound items while a warband tab is open.
        if not btn._warbankDim then
            local dimFrame = CreateFrame("Frame", nil, btn)
            dimFrame:SetAllPoints()
            dimFrame:SetFrameLevel((btn._textOverlay and btn._textOverlay:GetFrameLevel() or btn:GetFrameLevel()) + 3)
            local dim = dimFrame:CreateTexture(nil, "OVERLAY")
            dim:SetAllPoints()
            dim:SetColorTexture(0, 0, 0, 0.75)
            dimFrame:Hide()
            btn._warbankDim = dimFrame
        end
        local bank = _G.EUI_BankFrame
        local showDim = bank and bank:IsVisible()
            and bank.IsWarbandView and bank:IsWarbandView()
            and not data._isWarbound
        if showDim then
            btn._warbankDim:Show()
        else
            btn._warbankDim:Hide()
        end

        if btn.Cooldown then
            if data._cdStart then
                btn.Cooldown:SetDrawEdge(true)
                btn.Cooldown:SetCooldown(data._cdStart, data._cdDuration)
            else
                btn.Cooldown:Clear()
            end
        end

    end
    UpdatePawnArrow(btn, data.itemLink)
    EUI_Bags.RunItemOverlays(btn, data)

    -- Same requery the native container update does after re-assigning a slot: the
    -- cursor can be resting on this button while the repaint moves another item under
    -- it, and nothing re-reads the tooltip until the mouse moves (it kept showing the
    -- sold item, or stayed hidden for the one that slid in). Presence comes from our
    -- own render data: the template's HasItem() reads a field only its own update writes.
    if GameTooltip:IsOwned(btn) then
        if data.info and btn.UpdateTooltip then btn:UpdateTooltip() else GameTooltip:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Grid layout pass. Called by RefreshInventory after the shared scan,
--  classify, filter and scroll setup; returns the content bottom (curY).
-------------------------------------------------------------------------------
function ns.RenderGridView(tempItems, displayItems, emptySlots, child, columns, gridW, gridPadX, showPinned, pinnedSet)
    local selectedCategoryIndex, selectedGroupName = ns.GetSelection()

    -- 5. Render grid into scroll child
    for _, btn in pairs(itemSlots) do
        if btn.ProfessionQualityOverlay then btn.ProfessionQualityOverlay:SetAlpha(0) end
        if btn.IconOverlay then btn.IconOverlay:SetAlpha(0); btn.IconOverlay:Hide() end
        if btn.IconOverlay2 then btn.IconOverlay2:SetAlpha(0); btn.IconOverlay2:Hide() end
    end
    if EUI_Bags._emptyPads then
        for _, pad in pairs(EUI_Bags._emptyPads) do pad:Hide() end
    end
    local catTitleSize = GetCatTitleSize()
    for _, hdr in pairs(_catHeaders) do
        hdr:Hide(); hdr._hint:SetText("")
        if hdr._hideBtn then hdr._hideBtn:Hide() end
        if hdr._clearBtn then hdr._clearBtn:Hide() end
        hdr._line:ClearAllPoints()
        hdr._line:SetPoint("LEFT", hdr._hint, "RIGHT", 6, 0)
        hdr._line:SetPoint("RIGHT", hdr, "RIGHT", -SPACING, 0)
        SetBagFont(hdr._label, catTitleSize)
        SetBagFont(hdr._hint, catTitleSize - 1)
    end
    for _, sh in pairs(_expSubHeaders) do
        sh:Hide()
    end
    if EUI_Bags._pinOverlayBtn then EUI_Bags._pinOverlayBtn:Hide() end
    ResetAssignOverlays()
    if EUI_Bags._oneBagWarning then EUI_Bags._oneBagWarning:Hide() end

    -- Items position relative to scroll child (startX = padding only, no sidebar offset)
    local startX = gridPadX + 5
    local curY = -6
    local slotIdx = 0

    -- Lightweight empty pad pool (no ItemButton template, just bg + border)
    if not EUI_Bags._emptyPads then EUI_Bags._emptyPads = {} end
    local _emptyPads = EUI_Bags._emptyPads
    local _emptyPadIdx = 0

    local function GetOrCreateEmptyPad(idx)
        if _emptyPads[idx] then return _emptyPads[idx] end
        local f = CreateFrame("Frame", nil, EUI_Bags)
        f:SetSize(SLOT_SIZE, SLOT_SIZE)
        f:EnableMouse(false)
        f._bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f._bg:SetAllPoints()
        f._bg:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\icon-bg.png")
        f._bg:SetAlpha(0.35)
        CreateInsetBorder(f)
        SetInsetBorderColor(f, 0, 0, 0, 0.3)
        _emptyPads[idx] = f
        return f
    end

    local function RenderEmptyPad(itemCount, padCount)
        for p = 1, padCount do
            _emptyPadIdx = _emptyPadIdx + 1
            local pad = GetOrCreateEmptyPad(_emptyPadIdx)
            pad:SetParent(child)
            pad:ClearAllPoints()
            local totalIdx = itemCount + p
            local col = (totalIdx - 1) % columns
            local row = math.floor((totalIdx - 1) / columns)
            pad:SetPoint("TOPLEFT", startX + (col * (SLOT_SIZE + SPACING)), curY - (row * (SLOT_SIZE + SPACING)))
            pad:Show()
        end
    end

    local function RenderItemBlock(blockItems)
        local n = #blockItems
        for j, data in ipairs(blockItems) do
            slotIdx = slotIdx + 1
            local btn = GetOrCreateSlot(slotIdx)
            if btn then  -- nil during combat (avoids minting tainted secure buttons)
                btn:GetParent():SetParent(child)
                local col = (j - 1) % columns
                local row = math.floor((j - 1) / columns)
                RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
            end
        end
        local remainder = n % columns
        local padCount
        if n == 0 then
            padCount = columns
        elseif remainder == 0 then
            padCount = 0
        else
            padCount = columns - remainder
        end
        -- Filler pads are cosmetic row-fillers (the "+" button is the only real slot); NEVER clamp to #emptySlots or they vanish when bags are full.
        if padCount > 0 then
            RenderEmptyPad(n, padCount)
        end
        local totalInBlock = n + math.max(padCount, 0)
        local blockRows = math.ceil(totalInBlock / columns)
        curY = curY - (blockRows * (SLOT_SIZE + SPACING))
    end

    -- Compact Armory layout. Reuses the existing slot, sub-header, empty-pad,
    -- and assignment pools; only the coordinates differ from the full-row path.
    local armorySlotGrouping = ArmorySlotGroupingEnabled()
    local RenderCompactSlotBuckets
    if BP().bagCompactArmorySlotGroups and armorySlotGrouping then
        RenderCompactSlotBuckets = function(buckets, subHeaderIdx, assignCatKey)
            local stride = SLOT_SIZE + SPACING
            local usableWidth = columns * stride - SPACING
            local headerGap = 18
            local epsilon = 0.5
            local categoryGap = math.max(8, SPACING * 3)
            local assignBucket = assignCatKey and buckets[1] and 1 or nil

            -- Prepare the headers first so their text widths can reserve enough
            -- horizontal space before the buckets are packed into rows.
            for index, bucket in ipairs(buckets) do
                subHeaderIdx = subHeaderIdx + 1
                local header = GetOrCreateExpSubHeader(subHeaderIdx)
                header:SetParent(child)
                header._label:SetText(bucket.label .. " (" .. #bucket.items .. ")")
                SetBagFont(header._label, math.max(8, catTitleSize - 2))

                local itemCount = #bucket.items + ((index == assignBucket) and 1 or 0)
                local span = math.min(columns, itemCount)
                local bucketWidth = span * stride - SPACING
                bucket._compactHeader = header
                bucket._compactItemCount = itemCount
                bucket._compactSpan = span
                bucket._compactRows = math.ceil(itemCount / span)
                bucket._compactWidth = bucketWidth

                if itemCount <= columns then
                    categoryGap = math.max(categoryGap,
                        (header._label:GetStringWidth() or 0) + 6 - bucketWidth)
                end
            end

            local function RenderPadsAt(itemTop, usedWidth)
                local padCount = math.floor((usableWidth - usedWidth + epsilon) / stride)
                for index = 1, padCount do
                    _emptyPadIdx = _emptyPadIdx + 1
                    local pad = GetOrCreateEmptyPad(_emptyPadIdx)
                    pad:SetParent(child)
                    pad:ClearAllPoints()
                    pad:SetPoint("TOPLEFT", child, "TOPLEFT",
                        startX + usedWidth + SPACING + (index - 1) * stride, itemTop)
                    pad:Show()
                end
            end

            local rowTop = curY
            local usedWidth = 0
            local rowItemRows = 0

            for index, bucket in ipairs(buckets) do
                local span = bucket._compactSpan
                local itemRows = bucket._compactRows
                local bucketWidth = bucket._compactWidth
                local startOffset = usedWidth > 0 and usedWidth + categoryGap or 0

                -- Multi-row buckets always begin on a fresh row. Smaller buckets
                -- share a row for as long as the next one still fits.
                if usedWidth > 0
                    and (startOffset + bucketWidth > usableWidth + epsilon or itemRows > 1) then
                    RenderPadsAt(rowTop - headerGap, usedWidth)
                    rowTop = rowTop - headerGap - rowItemRows * stride
                    usedWidth = 0
                    rowItemRows = 0
                    startOffset = 0
                end

                local header = bucket._compactHeader
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", child, "TOPLEFT", startX + startOffset, rowTop)
                header:SetWidth(math.max(1, bucketWidth))
                header:Show()

                for itemIndex, data in ipairs(bucket.items) do
                    slotIdx = slotIdx + 1
                    local btn = GetOrCreateSlot(slotIdx)
                    if btn then
                        btn:GetParent():SetParent(child)
                        local col = (itemIndex - 1) % span
                        local row = math.floor((itemIndex - 1) / span)
                        RenderButton(btn, data, slotIdx, col, row,
                            startX + startOffset, rowTop - headerGap, columns)
                    end
                end

                if index == assignBucket then
                    slotIdx = slotIdx + 1
                    local assignSlot = GetOrCreateSlot(slotIdx)
                    if assignSlot then
                        assignSlot:GetParent():SetParent(child)
                        local itemIndex = #bucket.items + 1
                        local col = (itemIndex - 1) % span
                        local row = math.floor((itemIndex - 1) / span)
                        RenderButton(assignSlot, { bag = 0, slot = 0 }, slotIdx, col, row,
                            startX + startOffset, rowTop - headerGap, columns)
                        local overlay = GetOrCreateAssignOverlay()
                        overlay._assignCatKey = assignCatKey
                        overlay:SetParent(child)
                        overlay:ClearAllPoints()
                        overlay:SetAllPoints(assignSlot)
                        overlay:Show()
                    end
                end

                usedWidth = startOffset + bucketWidth
                rowItemRows = math.max(rowItemRows, itemRows)

                if itemRows > 1 then
                    local remainder = bucket._compactItemCount % columns
                    if remainder > 0 then
                        local lastRowWidth = remainder * stride - SPACING
                        RenderPadsAt(rowTop - headerGap - (itemRows - 1) * stride,
                            lastRowWidth)
                    end
                    rowTop = rowTop - headerGap - itemRows * stride
                    usedWidth = 0
                    rowItemRows = 0
                end
            end

            if usedWidth > 0 then
                RenderPadsAt(rowTop - headerGap, usedWidth)
                rowTop = rowTop - headerGap - rowItemRows * stride
            end

            curY = rowTop - 6
            return subHeaderIdx
        end
    end

    local RenderSlotBuckets
    if armorySlotGrouping then
        RenderSlotBuckets = function(buckets, subHeaderIdx, assignCatKey)
            if RenderCompactSlotBuckets then
                return RenderCompactSlotBuckets(buckets, subHeaderIdx, assignCatKey)
            end

            local assignShown = false
            for _, bucket in ipairs(buckets) do
                if #bucket.items > 0 then
                    subHeaderIdx = subHeaderIdx + 1
                    local header = GetOrCreateExpSubHeader(subHeaderIdx)
                    header:SetParent(child)
                    header:ClearAllPoints()
                    header:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
                    header:SetWidth(gridW)
                    header._label:SetText(bucket.label .. " (" .. #bucket.items .. ")")
                    SetBagFont(header._label, math.max(8, catTitleSize - 2))
                    header:Show()
                    curY = curY - 18
                    RenderItemBlock(bucket.items)

                    if assignCatKey and not assignShown then
                        assignShown = true
                        local remainder = #bucket.items % columns
                        if remainder ~= 0 then
                            curY = curY + (SLOT_SIZE + SPACING)
                        end
                        slotIdx = slotIdx + 1
                        local assignSlot = GetOrCreateSlot(slotIdx)
                        if assignSlot then
                            assignSlot:GetParent():SetParent(child)
                            RenderButton(assignSlot, { bag = 0, slot = 0 }, slotIdx,
                                remainder, 0, startX, curY, columns)
                            local overlay = GetOrCreateAssignOverlay()
                            overlay._assignCatKey = assignCatKey
                            overlay:SetParent(child)
                            overlay:ClearAllPoints()
                            overlay:SetAllPoints(assignSlot)
                            overlay:Show()
                        end
                        curY = curY - (SLOT_SIZE + SPACING)
                    end
                end
            end
            curY = curY - 6
            return subHeaderIdx
        end
    end


    if selectedCategoryIndex == -1 or selectedCategoryIndex == -2 then
        -- OneBag/MultiBag: Pinned Items (display-only) + bag section(s) + Reagent Bag. OneBag
        -- merges bags 0-4 into one "Main Bags" section, MultiBag renders one per bag; reuses tempItems + emptySlots instead of re-querying bags.
        local headerIdx = 0
        local isMulti = (selectedCategoryIndex == -2)

        -- OneBag/MultiBag warning label (created once, reused)
        if not EUI_Bags._oneBagWarning then
            local warn = child:CreateFontString(nil, "OVERLAY")
            SetBagFont(warn, 9)
            warn:SetTextColor(0.5, 0.5, 0.5, 0.9)
            warn:SetJustifyH("LEFT")
            EUI_Bags._oneBagWarning = warn
        end
        local warn = EUI_Bags._oneBagWarning
        local _warnHidden = BP().bagHideOneBagWarning
        if not _warnHidden then
            warn:SetParent(child)
            warn:ClearAllPoints()
            curY = curY - 5
            warn:SetPoint("TOP", child, "TOP", 0, curY)
            warn:SetJustifyH("CENTER")
            warn:SetText(isMulti
                and EllesmereUI.L("Changes made in MultiBag will affect the positions of items in default Blizzard bags")
                or EllesmereUI.L("Changes made in OneBag will affect the positions of items in default Blizzard bags"))
            warn:Show()
            curY = curY - 14 - 5
        end

        -- Pinned Items quickview (display-only duplicates)
        local showPinnedOneBag = (BP().bagPinnedInOneBag ~= false) and showPinned
        if showPinnedOneBag then
            local pinItems = {}
            if pinnedSet then
                for _, d in ipairs(tempItems) do
                    if d.info and d.info.itemID and IsItemPinned(pinnedSet, d.itemLink, d.info.itemID) then
                        pinItems[#pinItems + 1] = d
                    end
                end
            end
            if #pinItems > 0 then pinItems = MergeDuplicates(pinItems) end
            headerIdx = headerIdx + 1
            local pinHdr = GetOrCreateCatHeader(headerIdx)
            pinHdr:SetParent(child)
            pinHdr:ClearAllPoints()
            pinHdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            pinHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
            local showTips = BP().bagShowPinRecentTips ~= false
            pinHdr._label:SetText(EllesmereUI.L("Pinned Items"))
            pinHdr._hint:SetText(showTips and EllesmereUI.L("(Middle Click to Add or Remove)") or "")
            if not pinHdr._hideBtn then
                local hb = CreateFrame("Button", nil, pinHdr)
                hb:SetSize(30, 16)
                hb._fs = hb:CreateFontString(nil, "OVERLAY")
                SetBagFont(hb._fs, 9)
                hb._fs:SetAllPoints()
                hb._fs:SetText(EllesmereUI.L("Hide"))
                hb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                hb:SetScript("OnEnter", function(self)
                    self._fs:SetTextColor(1, 1, 1, 0.9)
                    EUI.ShowWidgetTooltip(self, "Hides Pinned Items. Re-show in settings.")
                end)
                hb:SetScript("OnLeave", function(self)
                    self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    EUI.HideWidgetTooltip()
                end)
                pinHdr._hideBtn = hb
            end
            pinHdr._hideBtn:ClearAllPoints()
            pinHdr._hideBtn:SetPoint("RIGHT", pinHdr, "RIGHT", _warnHidden and -5 or 0, 0)
            pinHdr._hideBtn:SetScript("OnClick", function()
                BP().bagPinnedInOneBag = false
                EUI_Bags:RefreshInventory()
            end)
            pinHdr._hideBtn:Show()
            pinHdr._line:ClearAllPoints()
            pinHdr._line:SetPoint("LEFT", pinHdr._hint, "RIGHT", 6, 0)
            pinHdr._line:SetPoint("RIGHT", pinHdr._hideBtn, "LEFT", -6, 0)
            pinHdr:Show()
            curY = curY - 22

            for j, data in ipairs(pinItems) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                if btn then  -- nil during combat (avoids minting tainted secure buttons)
                    btn:GetParent():SetParent(child)
                    local col = (j - 1) % columns
                    local row = math.floor((j - 1) / columns)
                    RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                end
            end
            local pinItemCount = #pinItems
            do
                local pinIdx = pinItemCount + 1
                slotIdx = slotIdx + 1
                local pinSlot = GetOrCreateSlot(slotIdx)
                if pinSlot then  -- nil during combat (avoids minting tainted secure buttons)
                    pinSlot:GetParent():SetParent(child)
                    local col = (pinIdx - 1) % columns
                    local row = math.floor((pinIdx - 1) / columns)
                    RenderButton(pinSlot, { bag = 0, slot = 0 }, slotIdx, col, row, startX, curY, columns)
                    local ov = GetOrCreatePinOverlay()
                    ov:SetParent(child)
                    ov:ClearAllPoints()
                    ov:SetAllPoints(pinSlot)
                    ov:Show()
                    pinItemCount = pinItemCount + 1
                end
            end
            -- Pad remaining slots in last row
            local pinRemainder = pinItemCount % columns
            local pinPadCount = pinRemainder == 0 and 0 or (columns - pinRemainder)
            if pinItemCount == 0 then pinPadCount = columns end
            if pinPadCount > 0 then
                RenderEmptyPad(pinItemCount, pinPadCount)
            end
            local pinTotal = pinItemCount + pinPadCount
            local pinRows = math.ceil(pinTotal / columns)
            curY = curY - (pinRows * (SLOT_SIZE + SPACING)) - 6
        end

        -- Recent Items quickview (display-only duplicates)
        local showRecentOneBag = BP().bagRecentInOneBag == true
        local showRecent = BP().bagShowRecentItems ~= false
        if showRecentOneBag and showRecent then
            local recentItems = {}
            if EUI_Bags._recentItems then
                for _, d in ipairs(tempItems) do
                    if d.info and d.info.itemID and EUI_Bags._recentItems[d.info.itemID]
                       and not ns.JunkHiddenFromRecent(d.info.itemID, d.info.quality) then
                        recentItems[#recentItems + 1] = d
                    end
                end
            end
            if #recentItems > 0 then recentItems = MergeDuplicates(recentItems) end
            headerIdx = headerIdx + 1
            local recHdr = GetOrCreateCatHeader(headerIdx)
            recHdr:SetParent(child)
            recHdr:ClearAllPoints()
            recHdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            recHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
            local showTips = BP().bagShowPinRecentTips ~= false
            recHdr._label:SetText(EllesmereUI.L("Recent Items"))
            recHdr._hint:SetText(showTips and EllesmereUI.L("(Extra quickview display, your items are also in their category)") or "")
            if not recHdr._hideBtn then
                local hb = CreateFrame("Button", nil, recHdr)
                hb:SetSize(30, 16)
                hb._fs = hb:CreateFontString(nil, "OVERLAY")
                SetBagFont(hb._fs, 9)
                hb._fs:SetAllPoints()
                hb._fs:SetText(EllesmereUI.L("Hide"))
                hb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                hb:SetScript("OnEnter", function(self)
                    self._fs:SetTextColor(1, 1, 1, 0.9)
                    EUI.ShowWidgetTooltip(self, "Hides Recent Items. Re-show in settings.")
                end)
                hb:SetScript("OnLeave", function(self)
                    self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    EUI.HideWidgetTooltip()
                end)
                recHdr._hideBtn = hb
            end
            recHdr._hideBtn:ClearAllPoints()
            recHdr._hideBtn:SetPoint("RIGHT", recHdr, "RIGHT", (_warnHidden and not showPinnedOneBag) and -5 or 0, 0)
            recHdr._hideBtn:SetScript("OnClick", function()
                BP().bagRecentInOneBag = false
                EUI_Bags:RefreshInventory()
            end)
            recHdr._hideBtn:Show()
            local recLineAnchor = recHdr._hideBtn
            if BP().bagShowRecentClear == true
               and EUI_Bags._recentItems and next(EUI_Bags._recentItems) then
                recLineAnchor = ShowRecentClearButton(recHdr, recHdr._hideBtn)
            end
            recHdr._line:ClearAllPoints()
            recHdr._line:SetPoint("LEFT", recHdr._hint, "RIGHT", 6, 0)
            recHdr._line:SetPoint("RIGHT", recLineAnchor, "LEFT", -6, 0)
            recHdr:Show()
            curY = curY - 22

            for j, data in ipairs(recentItems) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                if btn then  -- nil during combat (avoids minting tainted secure buttons)
                    btn:GetParent():SetParent(child)
                    local col = (j - 1) % columns
                    local row = math.floor((j - 1) / columns)
                    RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                end
            end
            local recItemCount = #recentItems
            local recRemainder = recItemCount % columns
            local recPadCount = recRemainder == 0 and 0 or (columns - recRemainder)
            if recItemCount == 0 then recPadCount = columns end
            if recPadCount > 0 then
                RenderEmptyPad(recItemCount, recPadCount)
            end
            local recTotal = recItemCount + recPadCount
            local recRows = math.ceil(recTotal / columns)
            curY = curY - (recRows * (SLOT_SIZE + SPACING)) - 6
        end

        -- One section header + item grid for a slot list, advancing the shared
        -- curY/slotIdx/headerIdx upvalues (used by OneBag's "Main Bags" and MultiBag's per-bag sections).
        local function RenderBagGrid(label, slotList)
            if #slotList == 0 then return end
            headerIdx = headerIdx + 1
            local hdr = GetOrCreateCatHeader(headerIdx)
            hdr:SetParent(child)
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            hdr:SetWidth(columns * (SLOT_SIZE + SPACING))
            hdr._label:SetText(label)
            hdr:Show()
            curY = curY - 22
            for i, data in ipairs(slotList) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                if btn then  -- nil during combat (avoids minting tainted secure buttons)
                    btn:GetParent():SetParent(child)
                    local col = (i - 1) % columns
                    local row = math.floor((i - 1) / columns)
                    RenderButton(btn, data, slotIdx, col, row, startX, curY, columns, true)
                end
            end
            local rows = math.ceil(#slotList / columns)
            curY = curY - (rows * (SLOT_SIZE + SPACING)) - 6
        end

        -- Junk pull-out (OneBag/MultiBag): when enabled, divert player-marked or
        -- grey junk out of the flat bag section(s) into their own "Junk" section,
        -- sorted by vendor value like the category view. Pre-collected here (not
        -- inline in the loops) so it can render either at the very bottom
        -- (default) or at the top just below Pinned Items (bagJunkAtTop). Empty
        -- slots are never diverted. Off by default -> no change.
        -- Nothing below is built unless the pull-out is on: no tables allocated,
        -- no RenderJunkSection closure created, when the feature (or this view's
        -- toggle) is off.
        local pullJunk = (EUI_CategoryManager and EUI_CategoryManager:IsJunkMarkerEnabled()
            and ((not isMulti and BP().bagJunkOneBag) or (isMulti and BP().bagJunkMultiBag))) or false
        local junkItems, diverted, RenderJunkSection, junkAtTop
        if pullJunk then
            junkItems, diverted = {}, {}
            for _, d in ipairs(tempItems) do
                if d.bag ~= 5 and d.info and d.info.itemID
                   and EUI_CategoryManager:IsJunk(d.info.itemID, d.info.quality) then
                    junkItems[#junkItems + 1] = d
                    diverted[d] = true
                end
            end
            RenderJunkSection = function()
                if #junkItems == 0 then return end
                PreCacheSortFields(junkItems)
                if BP().bagJunkSortByValue then
                    SortJunkByVendor(junkItems)
                else
                    table.sort(junkItems, VisualSortCompare)
                end
                RenderBagGrid(EllesmereUI.L("Junk") .. " (" .. #junkItems .. ")", junkItems)
            end
            -- Top placement: below the Pinned Items section (drawn above), before
            -- the bag section(s).
            junkAtTop = BP().bagJunkAtTop and #junkItems > 0
            if junkAtTop then RenderJunkSection() end
        end

        -- One bag's items + empties as a section titled with the bag's name, in
        -- slot order (MultiBag's bags, OneBag's special bags). Diverted junk is
        -- excluded so it only shows in the pulled-out Junk section.
        local BagDisplayName = ns.BagDisplayName
        local function RenderOneBag(bag)
            local bagList = {}
            local bagFilled = 0
            for _, d in ipairs(tempItems) do
                if d.bag == bag and not (diverted and diverted[d]) then bagList[#bagList + 1] = d; bagFilled = bagFilled + 1 end
            end
            for _, d in ipairs(emptySlots) do
                if d.bag == bag then bagList[#bagList + 1] = d end
            end
            if #bagList > 0 then
                table.sort(bagList, function(a, b) return a.slot < b.slot end)
                RenderBagGrid(BagDisplayName(bag) .. " (" .. bagFilled .. " / " .. #bagList .. ")", bagList)
            end
        end

        if not isMulti then
            -- OneBag: Main Bags (0-4) merged, in bag:slot order; a WoW Forever
            -- special bag (ns.SpecialBags) gets its own section after it.
            local special = ns.SpecialBags()
            local mainSlots = {}
            local mainFilled = 0
            for _, d in ipairs(tempItems) do
                if d.bag ~= 5 and not (special and special[d.bag]) and not (diverted and diverted[d]) then mainSlots[#mainSlots + 1] = d; mainFilled = mainFilled + 1 end
            end
            for _, d in ipairs(emptySlots) do
                if d.bag ~= 5 and not (special and special[d.bag]) then mainSlots[#mainSlots + 1] = d end
            end
            table.sort(mainSlots, function(a, b)
                if a.bag ~= b.bag then return a.bag < b.bag end
                return a.slot < b.slot
            end)
            RenderBagGrid(EllesmereUI.Lf("Main Bags (%d / %d)", mainFilled, #mainSlots), mainSlots)
            if special then
                for bag = 1, 4 do
                    if special[bag] then RenderOneBag(bag) end
                end
            end
        else
            -- MultiBag: one section per equipped bag (0-4)
            for bag = 0, 4 do RenderOneBag(bag) end
        end

        -- Reagent Bag (5): items + empties from bag 5
        local reagentSlotList = {}
        for _, d in ipairs(tempItems) do
            if d.bag == 5 then reagentSlotList[#reagentSlotList + 1] = d end
        end
        for _, d in ipairs(emptySlots) do
            if d.bag == 5 then reagentSlotList[#reagentSlotList + 1] = d end
        end
        table.sort(reagentSlotList, function(a, b) return a.slot < b.slot end)

        if #reagentSlotList > 0 then
            headerIdx = headerIdx + 1
            local reagHdr = GetOrCreateCatHeader(headerIdx)
            reagHdr:SetParent(child)
            reagHdr:ClearAllPoints()
            reagHdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            reagHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
            local reagFilled = 0
            for _, d in ipairs(reagentSlotList) do if d.info then reagFilled = reagFilled + 1 end end
            reagHdr._label:SetText(EllesmereUI.Lf("Reagent Bag (%d / %d)", reagFilled, #reagentSlotList))
            reagHdr:Show()
            curY = curY - 22

            for i, data in ipairs(reagentSlotList) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                if btn then  -- nil during combat (avoids minting tainted secure buttons)
                    btn:GetParent():SetParent(child)
                    local col = (i - 1) % columns
                    local row = math.floor((i - 1) / columns)
                    RenderButton(btn, data, slotIdx, col, row, startX, curY, columns, true)
                end
            end
            local reagRows = math.ceil(#reagentSlotList / columns)
            curY = curY - (reagRows * (SLOT_SIZE + SPACING))
        end

        -- Junk category at the very bottom (OneBag/MultiBag pull-out) unless the
        -- player moved it to the top (already rendered above, below Pinned Items).
        if RenderJunkSection and not junkAtTop then RenderJunkSection() end

    elseif selectedCategoryIndex == 0 and not selectedGroupName then
        -- "All Items" view: group by category with headers
        local cats = EUI_CategoryManager:GetCategories()
        local itemsByCat = {}
        for i = 1, #cats do itemsByCat[i] = {} end
        for _, data in ipairs(displayItems) do
            local ci = data.categoryIndex
            if ci and itemsByCat[ci] then
                itemsByCat[ci][#itemsByCat[ci] + 1] = data
            end
        end
        for i = 1, #cats do
            if #itemsByCat[i] > 0 and not cats[i].groupName and not cats[i].isRecent then
                if cats[i].isJunk and BP().bagJunkSortByValue then
                    -- Opt-in: order Junk by vendor value instead of the saved drag
                    -- order -- same as the grouped-member and selected-category
                    -- paths. Off -> Junk behaves like any other category.
                    PreCacheSortFields(itemsByCat[i])
                    SortJunkByVendor(itemsByCat[i])
                else
                    ApplySavedOrder(i, itemsByCat[i])
                end
            end
        end
        -- Merge duplicates after ordering so first-in-visual-order wins
        for i = 1, #cats do
            if #itemsByCat[i] > 1 then itemsByCat[i] = MergeDuplicates(itemsByCat[i]) end
        end

        -- Build render sections: ungrouped = individual, grouped = merged under group name
        local renderedGroups = {}
        local headerIdx = 0
        local expSubIdx = 0

        local function RenderSection(sectionName, sectionItems, isUserCreated, showPinAdd, alwaysShow, assignCatIdx, nestByExpansion)
            local itemCount = #sectionItems
            if itemCount == 0 and not isUserCreated and not showPinAdd and not alwaysShow then return end

            local useSlotNest = armorySlotGrouping
                and IsGearOnlyGroup(sectionName)
                and itemCount > 0
                and not showPinAdd
                and not alwaysShow

            local useExpNest = nestByExpansion
                and BP().bagNestByExpansion
                and not useSlotNest
                and itemCount > 0
                and not showPinAdd
                and not alwaysShow

            headerIdx = headerIdx + 1
            local hdr = GetOrCreateCatHeader(headerIdx)
            hdr:SetParent(child)
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            hdr:SetWidth(gridW)
            local showTips = BP().bagShowPinRecentTips ~= false
            if showPinAdd and showTips then
                hdr._label:SetText(sectionName)
                hdr._hint:SetText(EllesmereUI.L("(Middle Click to Add or Remove)"))
            elseif alwaysShow and showTips then
                hdr._label:SetText(sectionName)
                hdr._hint:SetText(EllesmereUI.L("(Extra quickview display, your items are also in their category)"))
            else
                hdr._label:SetText(sectionName .. " (" .. itemCount .. ")")
                hdr._hint:SetText("")
            end
            -- Hide button for Pinned / Recent sections
            if showPinAdd or alwaysShow then
                if not hdr._hideBtn then
                    local hb = CreateFrame("Button", nil, hdr)
                    hb:SetSize(30, 16)
                    hb._fs = hb:CreateFontString(nil, "OVERLAY")
                    SetBagFont(hb._fs, 9)
                    hb._fs:SetAllPoints()
                    hb._fs:SetText(EllesmereUI.L("Hide"))
                    hb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    hb:SetScript("OnEnter", function(self)
                        self._fs:SetTextColor(1, 1, 1, 0.9)
                        EUI.ShowWidgetTooltip(self, self._tooltip)
                    end)
                    hb:SetScript("OnLeave", function(self)
                        self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                        EUI.HideWidgetTooltip()
                    end)
                    hb:SetScript("OnClick", function(self)
                        BP()[self._dbKey] = false
                        EUI_Bags:RefreshInventory()
                    end)
                    hdr._hideBtn = hb
                end
                hdr._hideBtn._dbKey = showPinAdd and "bagShowPinnedItems" or "bagShowRecentItems"
                hdr._hideBtn._tooltip = showPinAdd and "Hides Pinned Items. Re-show in settings." or "Hides Recent Items. Re-show in settings."
                hdr._hideBtn:ClearAllPoints()
                hdr._hideBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
                hdr._hideBtn:Show()
                -- Recent Items only, opt-in: "Clear" left of "Hide", and only when
                -- there is something to clear.
                local lineAnchor = hdr._hideBtn
                if alwaysShow and not showPinAdd
                   and BP().bagShowRecentClear == true
                   and EUI_Bags._recentItems and next(EUI_Bags._recentItems) then
                    lineAnchor = ShowRecentClearButton(hdr, hdr._hideBtn)
                end
                hdr._line:ClearAllPoints()
                hdr._line:SetPoint("LEFT", hdr._hint, "RIGHT", 6, 0)
                hdr._line:SetPoint("RIGHT", lineAnchor, "LEFT", -6, 0)
            end
            hdr:Show()
            curY = curY - 22

            if useSlotNest then
                local buckets = BuildSlotBuckets(sectionItems)
                if #buckets > 0 then
                    local showAssign = assignCatIdx and EUI_CategoryManager
                        and EUI_CategoryManager:CanAssignToCategory(assignCatIdx)
                    local cats = showAssign and EUI_CategoryManager:GetCategories()
                    local assignCat = cats and cats[assignCatIdx]
                    expSubIdx = RenderSlotBuckets(buckets, expSubIdx,
                        assignCat and assignCat._defaultName)
                    return
                end
            end

            if useExpNest then
                local buckets = BuildExpansionBuckets(sectionItems)
                if #buckets > 0 then
                    local showAssign = assignCatIdx and EUI_CategoryManager
                        and EUI_CategoryManager:CanAssignToCategory(assignCatIdx)
                    local assignShown = false
                    for _, buck in ipairs(buckets) do
                        if #buck.items > 0 then
                            expSubIdx = expSubIdx + 1
                            local sh = GetOrCreateExpSubHeader(expSubIdx)
                            sh:SetParent(child)
                            sh:ClearAllPoints()
                            sh:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
                            sh:SetWidth(gridW)
                            sh._label:SetText(buck.label .. " (" .. #buck.items .. ")")
                            SetBagFont(sh._label, math.max(8, catTitleSize - 2))
                            sh:Show()
                            curY = curY - 18
                            RenderItemBlock(buck.items)
                            -- Place assign "+" after the first bucket's items (newest expansion)
                            if showAssign and not assignShown then
                                assignShown = true
                                local cats = EUI_CategoryManager:GetCategories()
                                local aCat = cats[assignCatIdx]
                                if aCat then
                                    -- RenderItemBlock already advanced curY; back up to place at the next slot after the items.
                                    local n = #buck.items
                                    local remainder = n % columns
                                    if remainder == 0 then
                                        -- Last row filled exactly: curY already sits on the new row the button needs.
                                    else
                                        -- Back up to the row the items are on
                                        curY = curY + (SLOT_SIZE + SPACING)
                                    end
                                    slotIdx = slotIdx + 1
                                    local aSlot = GetOrCreateSlot(slotIdx)
                                    if aSlot then
                                    aSlot:GetParent():SetParent(child)
                                    local col = remainder
                                    RenderButton(aSlot, { bag = 0, slot = 0 }, slotIdx, col, 0, startX, curY, columns)
                                    local aOv = GetOrCreateAssignOverlay()
                                    aOv._assignCatKey = aCat._defaultName
                                    aOv:SetParent(child)
                                    aOv:ClearAllPoints()
                                    aOv:SetAllPoints(aSlot)
                                    aOv:Show()
                                    end
                                    -- Re-advance curY for the row
                                    curY = curY - (SLOT_SIZE + SPACING)
                                end
                            end
                        end
                    end
                    curY = curY - 6
                    return
                end
            end

            for j, data in ipairs(sectionItems) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                if btn then
                    btn:GetParent():SetParent(child)
                    local col = (j - 1) % columns
                    local row = math.floor((j - 1) / columns)
                    RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                end
            end

            -- Pin "+" button: a regular empty slot with a "+" overlay on top
            if showPinAdd then
                local pinIdx = itemCount + 1
                slotIdx = slotIdx + 1
                local pinSlot = GetOrCreateSlot(slotIdx)
                if pinSlot then
                    pinSlot:GetParent():SetParent(child)
                    local col = (pinIdx - 1) % columns
                    local row = math.floor((pinIdx - 1) / columns)
                    RenderButton(pinSlot, { bag = 0, slot = 0 }, slotIdx, col, row, startX, curY, columns)
                    local ov = GetOrCreatePinOverlay()
                    ov:SetParent(child)
                    ov:ClearAllPoints()
                    ov:SetAllPoints(pinSlot)
                    ov:Show()
                    itemCount = itemCount + 1
                end
            end

            -- Assign "+" button: for categories that accept item assignments
            if assignCatIdx and EUI_CategoryManager
               and EUI_CategoryManager:CanAssignToCategory(assignCatIdx) then
                local cats = EUI_CategoryManager:GetCategories()
                local aCat = cats[assignCatIdx]
                if aCat then
                    local aIdx = itemCount + 1
                    slotIdx = slotIdx + 1
                    -- GetOrCreateSlot returns nil in combat lockdown (a slot born in combat is tainted); skip, PLAYER_REGEN_ENABLED replays the refresh.
                    local aSlot = GetOrCreateSlot(slotIdx)
                    if aSlot then
                        aSlot:GetParent():SetParent(child)
                        local col = (aIdx - 1) % columns
                        local row = math.floor((aIdx - 1) / columns)
                        RenderButton(aSlot, { bag = 0, slot = 0 }, slotIdx, col, row, startX, curY, columns)
                        local aOv = GetOrCreateAssignOverlay()
                        aOv._assignCatKey = aCat._defaultName
                        aOv:SetParent(child)
                        aOv:ClearAllPoints()
                        aOv:SetAllPoints(aSlot)
                        aOv:Show()
                        itemCount = itemCount + 1
                    end
                end
            end

            local remainder = itemCount % columns
            local padCount
            if itemCount == 0 then
                padCount = columns
            elseif remainder == 0 then
                padCount = 0
            else
                padCount = columns - remainder
            end
            -- Filler pads are cosmetic (the "+" assign/pin button is the only real slot); NEVER clamp to #emptySlots or they vanish when bags are full.
            if padCount > 0 then
                RenderEmptyPad(itemCount, padCount)
            end

            local totalInSection = itemCount + math.max(padCount, 0)
            local sectionRows = math.ceil(totalInSection / columns)
            curY = curY - (sectionRows * (SLOT_SIZE + SPACING)) - 6
        end

        local hiddenSet = BP().bagHiddenInAllItems or {}
        -- "Move Junk to Top" in All Items: render the Junk category right after
        -- Pinned/Recent (the top display-only sections) and skip its normal order
        -- slot below. Only built while the feature + toggle are on, so the scan
        -- and closure cost nothing per render when off; otherwise Junk stays in
        -- its category-order position.
        local junkAtTopAll, junkCat, junkIdx, RenderJunkCatTop
        local junkRendered = false
        if EUI_CategoryManager:IsJunkMarkerEnabled() and BP().bagJunkAtTop then
            for i, c in ipairs(cats) do if c.isJunk then junkIdx, junkCat = i, c; break end end
            junkAtTopAll = junkIdx and not hiddenSet[junkCat._defaultName]
            RenderJunkCatTop = function()
                junkRendered = true
                RenderSection(junkCat.name, itemsByCat[junkIdx] or {}, false, false, false, junkIdx, true)
            end
        end
        for ci, cat in ipairs(cats) do
            if junkAtTopAll and not junkRendered and not cat.isPinned and not cat.isRecent then
                RenderJunkCatTop()
            end
            if cat.isPinned then
                -- Pinned Items: display-only duplicate (items also appear in their normal category)
                if pinnedSet and showPinned then
                    local pinItems = {}
                    for _, data in ipairs(displayItems) do
                        if data.info and data.info.itemID and IsItemPinned(pinnedSet, data.itemLink, data.info.itemID) then
                            pinItems[#pinItems + 1] = data
                        end
                    end
                    if #pinItems > 0 then pinItems = MergeDuplicates(pinItems) end
                    RenderSection(cat.name, pinItems, false, true)
                end
            elseif cat.isRecent then
                -- Recent Items: display-only duplicate (items also appear in their normal category)
                if EUI_Bags._recentItems
                   and (BP().bagShowRecentItems ~= false) then
                    local recentItems = {}
                    for _, data in ipairs(displayItems) do
                        if data.info and data.info.itemID and EUI_Bags._recentItems[data.info.itemID]
                           and not ns.JunkHiddenFromRecent(data.info.itemID, data.info.quality) then
                            recentItems[#recentItems + 1] = data
                        end
                    end
                    if #recentItems > 0 then recentItems = MergeDuplicates(recentItems) end
                    RenderSection(EllesmereUI.L("Recent Items"), recentItems, false, false, true)
                end
            elseif cat.groupName then
                if not renderedGroups[cat.groupName] then
                    renderedGroups[cat.groupName] = true
                    if not hiddenSet[cat.groupName] then
                        local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                        local merged = {}
                        for _, mi in ipairs(members) do
                            if itemsByCat[mi] then
                                for _, data in ipairs(itemsByCat[mi]) do
                                    merged[#merged + 1] = data
                                end
                            end
                            -- The Item Set Gear anchor folds in its set children's items
                            if BP().bagSplitSetGearBySet and cats[mi] and cats[mi].isSetGear and not cats[mi].isEquipSet then
                                for i, c in ipairs(cats) do
                                    if c.isEquipSet and itemsByCat[i] then
                                        for _, data in ipairs(itemsByCat[i]) do
                                            merged[#merged + 1] = data
                                        end
                                    end
                                end
                            end
                        end
                        if #merged > 0 then
                            ApplySavedOrder(cat.groupName, merged)
                        end
                        RenderSection(cat.groupName, merged, false, nil, nil, members[1], true)
                    end
                end
            elseif cat.isEquipSet then
                -- Set children render inside their anchor's section
            elseif cat.isJunk and junkAtTopAll then
                -- Junk already rendered at the top; skip its normal order slot.
            else
                if not hiddenSet[cat._defaultName] then
                    local catItems = itemsByCat[ci] or {}
                    -- The Item Set Gear anchor folds in its set children's items
                    if cat.isSetGear and BP().bagSplitSetGearBySet then
                        local folded = nil
                        for i, c in ipairs(cats) do
                            if c.isEquipSet and itemsByCat[i] then
                                if not folded then
                                    folded = {}
                                    for _, data in ipairs(catItems) do folded[#folded + 1] = data end
                                end
                                for _, data in ipairs(itemsByCat[i]) do folded[#folded + 1] = data end
                            end
                        end
                        catItems = folded or catItems
                    end
                    local isUserCreated = cat.isUserCreated
                    RenderSection(cat.name, catItems, isUserCreated, cat.isPinned, cat.isRecent, ci, true)
                end
            end
        end
    else
        if selectedGroupName then
            -- Group view: items split by member category with headers
            local cats = EUI_CategoryManager:GetCategories()
            local members = EUI_CategoryManager:GetGroupMembers(selectedGroupName)
            local headerIdx = 0
            local expSubIdx = 0
            local useSlotNest = armorySlotGrouping and IsGearOnlyGroup(selectedGroupName)

            local itemsByMember = {}
            for _, mi in ipairs(members) do itemsByMember[mi] = {} end
            -- Split-mode set children fold into their anchor member's section
            local anchorMi, childSet
            if BP().bagSplitSetGearBySet then
                for _, mi in ipairs(members) do
                    if cats[mi] and cats[mi].isSetGear and not cats[mi].isEquipSet then anchorMi = mi; break end
                end
                if anchorMi then
                    childSet = {}
                    for i, c in ipairs(cats) do if c.isEquipSet then childSet[i] = true end end
                end
            end
            for _, data in ipairs(displayItems) do
                local ci = data.categoryIndex
                if ci and itemsByMember[ci] then
                    itemsByMember[ci][#itemsByMember[ci] + 1] = data
                elseif ci and childSet and childSet[ci] then
                    itemsByMember[anchorMi][#itemsByMember[anchorMi] + 1] = data
                end
            end

            local hideEmpty = BP().bagHideEmptyCategories ~= false
            for _, mi in ipairs(members) do
                local memberCat = cats[mi]
                local memberItems = itemsByMember[mi] or {}
                if not (hideEmpty and #memberItems == 0) then

                if #memberItems > 0 then
                    PreCacheSortFields(memberItems)
                    if memberCat and memberCat.isJunk and BP().bagJunkSortByValue then
                        SortJunkByVendor(memberItems)
                    else
                        table.sort(memberItems, VisualSortCompare)
                    end
                    memberItems = MergeDuplicates(memberItems)
                end

                headerIdx = headerIdx + 1
                local hdr = GetOrCreateCatHeader(headerIdx)
                hdr:SetParent(child)
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
                hdr:SetWidth(gridW)
                hdr._label:SetText((memberCat and memberCat.name or "?") .. " (" .. #memberItems .. ")")
                hdr:Show()
                curY = curY - 22

                if useSlotNest and #memberItems > 0 then
                    local buckets = BuildSlotBuckets(memberItems)
                    local showAssign = EUI_CategoryManager and EUI_CategoryManager:CanAssignToCategory(mi)
                    expSubIdx = RenderSlotBuckets(buckets, expSubIdx,
                        showAssign and memberCat and memberCat._defaultName)
                else
                for j, data in ipairs(memberItems) do
                    slotIdx = slotIdx + 1
                    local btn = GetOrCreateSlot(slotIdx)
                    if btn then
                        btn:GetParent():SetParent(child)
                        local col = (j - 1) % columns
                        local row = math.floor((j - 1) / columns)
                        RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                    end
                end

                -- Assign "+" per member sub-section in group view
                local memberItemCount = #memberItems
                if EUI_CategoryManager and EUI_CategoryManager:CanAssignToCategory(mi) then
                    local aIdx = memberItemCount + 1
                    slotIdx = slotIdx + 1
                    local aSlot = GetOrCreateSlot(slotIdx)
                    if aSlot then  -- nil during combat (avoids minting tainted secure buttons)
                        aSlot:GetParent():SetParent(child)
                        local col = (aIdx - 1) % columns
                        local row = math.floor((aIdx - 1) / columns)
                        RenderButton(aSlot, { bag = 0, slot = 0 }, slotIdx, col, row, startX, curY, columns)
                        local aOv = GetOrCreateAssignOverlay()
                        aOv._assignCatKey = memberCat._defaultName
                        aOv:SetParent(child)
                        aOv:ClearAllPoints()
                        aOv:SetAllPoints(aSlot)
                        aOv:Show()
                        memberItemCount = memberItemCount + 1
                    end
                end

                local remainder = memberItemCount % columns
                local padCount
                if memberItemCount == 0 then padCount = columns
                elseif remainder == 0 then padCount = 0
                else padCount = columns - remainder end
                -- Cosmetic filler pads -- never clamp to free bag slots (see above).
                if padCount > 0 then
                    RenderEmptyPad(memberItemCount, padCount)
                end

                local totalInSection = memberItemCount + math.max(padCount, 0)
                local sectionRows = math.ceil(totalInSection / columns)
                curY = curY - (sectionRows * (SLOT_SIZE + SPACING)) - 6

                end -- slot nest vs flat grid

                end -- hideEmpty guard
            end
        else
            -- Single category view: header + flat grid with empty padding
            local cats = EUI_CategoryManager:GetCategories()
            local selCat = cats[selectedCategoryIndex]
            if #displayItems > 0 then
                if not (selCat and selCat.isRecent) then
                    PreCacheSortFields(displayItems)
                    if selCat and selCat.isJunk and BP().bagJunkSortByValue then
                        SortJunkByVendor(displayItems)
                    else
                        table.sort(displayItems, VisualSortCompare)
                    end
                end
                displayItems = MergeDuplicates(displayItems)
            end
            local headerName = selCat and selCat.name
            if headerName then
                local headerIdx = 1
                local hdr = GetOrCreateCatHeader(headerIdx)

                -- "Edit | Delete" links for user-created categories
                if not hdr._editDeleteFrame then
                    local ef = CreateFrame("Frame", nil, child)
                    ef:SetHeight(16)
                    ef:SetFrameLevel((hdr:GetFrameLevel() or 1) + 1)

                    local delBtn = CreateFrame("Button", nil, ef)
                    delBtn:SetHeight(20)
                    delBtn._fs = delBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(delBtn._fs, 10)
                    delBtn._fs:SetPoint("RIGHT", ef, "RIGHT", 0, 0)
                    delBtn._fs:SetText(EllesmereUI.L("Delete"))
                    delBtn._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    delBtn:SetWidth(delBtn._fs:GetStringWidth() + 4)
                    delBtn:SetAllPoints(delBtn._fs)
                    delBtn:SetScript("OnEnter", function(s) s._fs:SetTextColor(1, 0.3, 0.3, 1) end)
                    delBtn:SetScript("OnLeave", function(s) s._fs:SetTextColor(0.5, 0.5, 0.5, 0.7) end)
                    delBtn:SetScript("OnClick", function()
                        local ci = ns.GetSelection()
                        if ci and ci > 0 and EUI_CategoryManager then
                            EUI:ShowConfirmPopup({
                                title = "Delete Category",
                                message = EllesmereUI.L("Are you sure you want to delete this category? All item assignments will be removed."),
                                confirmText = "Delete",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    EUI_CategoryManager:RemoveCustomCategory(ci)
                                    ns.SetSelection(0, nil)
                                    EUI_Bags:RefreshInventory()
                                end,
                            })
                        end
                    end)
                    ef._delBtn = delBtn

                    local divider = ef:CreateFontString(nil, "OVERLAY")
                    SetBagFont(divider, 10)
                    divider:SetPoint("RIGHT", delBtn._fs, "LEFT", -6, 0)
                    divider:SetText("|")
                    divider:SetTextColor(0.3, 0.3, 0.3, 0.7)
                    ef._divider = divider

                    local editBtn = CreateFrame("Button", nil, ef)
                    editBtn:SetHeight(20)
                    editBtn._fs = editBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(editBtn._fs, 10)
                    editBtn._fs:SetPoint("RIGHT", divider, "LEFT", -6, 0)
                    editBtn._fs:SetText(EllesmereUI.L("Edit"))
                    editBtn._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    editBtn:SetWidth(editBtn._fs:GetStringWidth() + 4)
                    editBtn:SetAllPoints(editBtn._fs)
                    editBtn:SetScript("OnEnter", function(s) s._fs:SetTextColor(1, 1, 1, 1) end)
                    editBtn:SetScript("OnLeave", function(s) s._fs:SetTextColor(0.5, 0.5, 0.5, 0.7) end)
                    editBtn:SetScript("OnClick", function()
                        local ci = ns.GetSelection()
                        if ci and ci > 0 and EUI_CategoryManager and EUI then
                            local cats2 = EUI_CategoryManager:GetCategories()
                            local cat2 = cats2[ci]
                            if not cat2 then return end
                            EUI:ShowInputPopup({
                                title = "Rename Category",
                                message = EllesmereUI.L("Enter a new name:"),
                                placeholder = cat2.name,
                                confirmText = "Rename",
                                cancelText = "Cancel",
                                onConfirm = function(text)
                                    if text and text ~= "" then
                                        EUI_CategoryManager:RenameCategory(ci, text)
                                        EUI_Bags:RefreshInventory()
                                    end
                                end,
                            })
                        end
                    end)
                    ef._editBtn = editBtn

                    ef:SetWidth(60)
                    hdr._editDeleteFrame = ef
                end

                -- Position Edit | Delete above the header, then the header below
                if selCat and selCat.isUserCreated then
                    local ef = hdr._editDeleteFrame
                    ef:SetParent(child)
                    ef:ClearAllPoints()
                    ef:SetPoint("TOPRIGHT", child, "TOPLEFT", startX + gridW, curY)
                    ef:SetWidth(gridW)
                    ef:Show()
                    curY = curY - 18
                elseif hdr._editDeleteFrame then
                    hdr._editDeleteFrame:Hide()
                end

                hdr:SetParent(child)
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
                hdr:SetWidth(gridW)
                local showTips = BP().bagShowPinRecentTips ~= false
                if selCat and selCat.isPinned and showTips then
                    hdr._label:SetText(headerName)
                    hdr._hint:SetText(EllesmereUI.L("(Middle Click to Add or Remove)"))
                elseif selCat and selCat.isRecent and showTips then
                    hdr._label:SetText(headerName)
                    hdr._hint:SetText(EllesmereUI.L("(Extra quickview display, your items are also in their category)"))
                else
                    hdr._label:SetText(headerName .. " (" .. #displayItems .. ")")
                    hdr._hint:SetText("")
                end
                hdr:Show()
                curY = curY - 22
            end

            local itemCount = #displayItems
            local useSlotNest = armorySlotGrouping
                and selCat and IsArmoryGearCategory(selCat)
                and itemCount > 0

            if useSlotNest then
                local expSubIdx = 0
                local buckets = BuildSlotBuckets(displayItems)
                local showAssign = selectedCategoryIndex > 0
                    and EUI_CategoryManager
                    and EUI_CategoryManager:CanAssignToCategory(selectedCategoryIndex)
                expSubIdx = RenderSlotBuckets(buckets, expSubIdx,
                    showAssign and selCat and selCat._defaultName)
            else
            for i, data in ipairs(displayItems) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                if btn then
                    btn:GetParent():SetParent(child)
                    local col = (i - 1) % columns
                    local row = math.floor((i - 1) / columns)
                    RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                end
            end

            local remainder = itemCount % columns
            local padCount
            if itemCount == 0 then
                padCount = columns
            elseif remainder == 0 then
                padCount = 0
            else
                padCount = columns - remainder
            end
            -- Cosmetic filler pads -- never clamp to free bag slots (see above).
            if padCount > 0 then
                RenderEmptyPad(itemCount, padCount)
            end

            local totalItems = itemCount + math.max(padCount, 0)
            local gridRows = math.ceil(totalItems / columns)
            curY = curY - (gridRows * (SLOT_SIZE + SPACING))
            end -- slot nest vs flat grid
        end
    end

    -- Hide slots that were not rendered this pass
    for i = slotIdx + 1, #itemSlots do
        local btn = itemSlots[i]
        if btn then btn:GetParent():Hide() end
    end
    return curY
end
