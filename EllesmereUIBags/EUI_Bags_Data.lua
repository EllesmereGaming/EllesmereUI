if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Data.lua
--
--  Layout constants, the selection and item-panel state, the visual sort,
--  the expansion and armory buckets, the slot data pool with saved order
--  and swap detection, the slot pools and the Pawn arrows.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local EUI = EllesmereUI
local GetUpgradeTrack = EUI.GetUpgradeTrack

local BP, SetSelectedCategoryIndex = I.BP, I.SetSelectedCategoryIndex
local SetSelectedGroupName, SetAnyItemPanelOpen = I.SetSelectedGroupName, I.SetAnyItemPanelOpen
local SetPaintedPanelOpen = I.SetPaintedPanelOpen

-------------------------------------------------------------------------------
--  Sidebar constants
-------------------------------------------------------------------------------
local SIDEBAR_W_EXPANDED  = 160
local SIDEBAR_W_COLLAPSED = 32
local SIDEBAR_BTN_H       = 26
local SIDEBAR_ICON_SIZE   = 18
local SIDEBAR_PAD         = 2
local SIDEBAR_INDENT      = 16
local HEADER_H            = 35
local FOOTER_H            = 28

-- Runtime state (never persisted; always "All" on load)
local selectedCategoryIndex = 0  -- 0 = All Items, -1 = OneBag, -2 = MultiBag, >0 = category index
local selectedGroupName = nil    -- set when a group header is clicked (overrides selectedCategoryIndex)
I.categoryIndexSetters[#I.categoryIndexSetters + 1] = function(v) selectedCategoryIndex = v end
I.groupNameSetters[#I.groupNameSetters + 1] = function(v) selectedGroupName = v end

-- Invalidate categories after the equipment-set list changes (event or the
-- split-mode toggle). Re-resolves the selection by stable key: the rebuild
-- shifts indices, and "EquipSet:"..setID survives renames; a vanished
-- category/group falls back to All Items.
function EUI_Bags.InvalidateSetCategories()
    local mgr = _G.EUI_CategoryManager
    if not mgr then return end
    local selKey
    if selectedCategoryIndex > 0 then
        local cat = mgr:GetCategories()[selectedCategoryIndex]
        selKey = cat and cat._defaultName
    end
    mgr:OnEquipmentSetsChanged()
    if selKey then
        local found = 0
        for i, cat in ipairs(mgr:GetCategories()) do
            if cat._defaultName == selKey then found = i; break end
        end
        SetSelectedCategoryIndex(found)
    end
    if selectedGroupName then
        local alive = false
        for _, cat in ipairs(mgr:GetCategories()) do
            if cat.groupName == selectedGroupName then alive = true; break end
        end
        if not alive then SetSelectedGroupName(nil); SetSelectedCategoryIndex(0) end
    end
end

-- Visual sort: quality desc > name > itemID > bag > slot; the bag+slot tiebreaker makes output deterministic (Lua 5.1 sort is unstable).
local _trackRank = EUI._TRACK_RANK
-- Gear category lookup: built lazily, maps catIdx -> true for gear categories
local _gearCatSet
I.gearCatSetSetters[#I.gearCatSetSetters + 1] = function(v) _gearCatSet = v end
local function IsGearCategory(catIdx)
    if not _gearCatSet then
        _gearCatSet = {}
        local cats = EUI_CategoryManager and EUI_CategoryManager:GetCategories()
        if cats then
            for i, cat in ipairs(cats) do
                if cat.isSetGear
                or (cat.types and (cat._defaultName == "Armor"
                    or cat._defaultName == "Weapons / Trinkets")) then
                    _gearCatSet[i] = true
                end
            end
        end
    end
    return _gearCatSet[catIdx]
end

-- Item panels (mail/trade/AH/vendor/bank/guildbank) take one bag slot at a time; a merged button
-- only hands over the slot behind it (3 merged mails would mail 1), so duplicates stay unmerged while any panel is open. bagMergeDuplicates disables merging outright.
local _openItemPanels = {}
local _anyItemPanelOpen = false
I.anyItemPanelOpenSetters[#I.anyItemPanelOpenSetters + 1] = function(v) _anyItemPanelOpen = v end
-- Returns true when the aggregate state flipped and the bags' view merges, so
-- the caller can refresh. A view that does not merge paints the same either
-- way: its painted state just follows, so neither this nor OnShow repaints.
local function SetItemPanelOpen(key, open)
    _openItemPanels[key] = open or nil
    local any = next(_openItemPanels) ~= nil
    if any == _anyItemPanelOpen then return false end
    SetAnyItemPanelOpen(any)
    local merges = BP().bagMergeDuplicates ~= false
    if not merges then SetPaintedPanelOpen(any) end
    return merges
end

-- Pre-cache sort fields onto item data tables to avoid API calls in comparator.
-- The per-table _sortCached flag only covers repeats within one pass: every
-- physical-sort retry builds fresh item tables, so it re-ran GetItemInfo and
-- GetItemUpgradeInfo for every item on every pass. All five fields are pure
-- functions of the item link, so memo them on the link instead. Incomplete
-- item data (nil name) is never stored and still resolves on a later pass.
-- _sortGear stays per item: it follows the category, not the link.
local PreCacheSortFields
do
    local cache = {}
    local cacheCount = 0
    PreCacheSortFields = function(items)
        for _, d in ipairs(items) do
            if d.itemLink and not d._sortCached then
                local c = cache[d.itemLink]
                if not c then
                    local name, _, quality, ilvl, _, itemType = GetItemInfo(d.itemLink)
                    local rank = 0
                    if GetUpgradeTrack and _trackRank then
                        local _, color = GetUpgradeTrack(d.itemLink)
                        rank = color and _trackRank[color] or 0
                        local craftedColor = EUI.GetCraftedTrackColor(d.itemLink)
                        if craftedColor then
                            rank = _trackRank[craftedColor]
                            ilvl = C_Item.GetDetailedItemLevelInfo(d.itemLink) or ilvl
                        end
                    end
                    c = { name = name or "", quality = quality or 0, ilvl = ilvl or 0,
                          itemType = itemType or "", rank = rank, complete = name ~= nil }
                    if c.complete then
                        -- Links are per-item-instance, so the table would grow
                        -- with every distinct item seen in a session.
                        if cacheCount >= 4000 then wipe(cache); cacheCount = 0 end
                        cache[d.itemLink] = c
                        cacheCount = cacheCount + 1
                    end
                end
                d._sortName = c.name
                d._sortQuality = c.quality
                d._sortIlvl = c.ilvl
                d._sortType = c.itemType
                d._sortTrackRank = c.rank
                d._sortGear = d.categoryIndex and IsGearCategory(d.categoryIndex) or false
                if c.complete then d._sortCached = true end
            end
        end
    end
end

local function VisualSortCompare(a, b)
    -- Gear sort: track (descending) > ilvl (descending) -- only for gear categories
    if a._sortGear and b._sortGear then
        if a._sortTrackRank ~= b._sortTrackRank then return a._sortTrackRank > b._sortTrackRank end
        if a._sortTrackRank > 0 and b._sortTrackRank > 0 then
            if a._sortIlvl ~= b._sortIlvl then return a._sortIlvl > b._sortIlvl end
        end
    end
    -- Category grouping; skipped for gear so track/ilvl win in merged gear groups
    local aCat = a.categoryIndex or 9999
    local bCat = b.categoryIndex or 9999
    if aCat ~= bCat and not (a._sortGear and b._sortGear) then return aCat < bCat end
    -- Sub-type grouping within merged categories (e.g. Professions vs Recipes)
    if a._sortType ~= b._sortType then return a._sortType < b._sortType end
    -- Fallback: rarity > name > itemID > bag:slot
    if a._sortQuality ~= b._sortQuality then return a._sortQuality > b._sortQuality end
    if a._sortName ~= b._sortName then return a._sortName < b._sortName end
    local ai = (a.info and a.info.itemID) or 0
    local bi = (b.info and b.info.itemID) or 0
    if ai ~= bi then return ai < bi end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-------------------------------------------------------------------------------
--  Expansion nesting (All Items view): C_Item.GetItemInfo expansionID + labels
-------------------------------------------------------------------------------
local EXPANSION_ID_OVERRIDES = {
    [180653] = 11,
}

local function GetItemExpansionIDFromLink(itemLink)
    if not itemLink then return nil end
    local itemID = tonumber(itemLink:match("item:(%d+)")) or tonumber(itemLink:match("keystone:(%d+)"))
    if itemID and EXPANSION_ID_OVERRIDES[itemID] then
        return EXPANSION_ID_OVERRIDES[itemID]
    end
    if C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expID = C_Item.GetItemInfo(itemLink)
        return expID
    end
    return select(15, GetItemInfo(itemLink))
end

-- sortKey: higher = newer expansion, shown first. Unknown / uncached last.
local function GetExpansionBucketKeyAndLabel(itemLink)
    local expID = GetItemExpansionIDFromLink(itemLink)
    if expID == nil then
        return -999, (UNKNOWN or "Unknown")
    end
    local id = tonumber(expID)
    if id == nil then
        return -999, (UNKNOWN or "Unknown")
    end
    -- Classic-era sentinel from some clients / items
    if id == 254 or id == 255 then
        local name = _G["EXPANSION_NAME0"] or "Classic"
        return 0, name
    end
    local name = _G["EXPANSION_NAME" .. id]
    if name and name ~= "" then
        return id, name
    end
    if id == 11 then return id, "Midnight" end
    return id, "Expansion " .. tostring(id)
end

local function BuildExpansionBuckets(itemList)
    local byKey = {}
    for _, data in ipairs(itemList) do
        local sk, label
        if data.itemLink then
            local _, _, _, ilvl = GetItemInfo(data.itemLink)
            if ilvl and ilvl >= 180 then
                sk, label = 11, "Midnight"
            end
        end
        if not sk then
            sk, label = GetExpansionBucketKeyAndLabel(data.itemLink)
        end
        local b = byKey[sk]
        if not b then
            b = { sortKey = sk, label = label, items = {} }
            byKey[sk] = b
        end
        b.items[#b.items + 1] = data
    end
    local keys = {}
    for sk in pairs(byKey) do
        keys[#keys + 1] = sk
    end
    table.sort(keys, function(a, b) return a > b end)
    local out = {}
    for _, sk in ipairs(keys) do
        out[#out + 1] = byKey[sk]
    end
    return out
end

-------------------------------------------------------------------------------
--  Armory slot grouping: equip-slot sub-headers inside gear-only sidebar groups
-------------------------------------------------------------------------------
local IC_WEAPON = Enum.ItemClass.Weapon
local IC_ARMOR  = Enum.ItemClass.Armor

local function IsArmoryGearCategory(cat)
    if not cat then return false end
    if cat.isEquipSet then return true end
    if cat.isSetGear then return true end
    return cat._defaultName == "Weapons / Trinkets" or cat._defaultName == "Armor"
end

local function IsGearOnlyGroup(groupName)
    if not groupName or not EUI_CategoryManager then return false end
    local members = EUI_CategoryManager:GetGroupMembers(groupName)
    if not members or #members == 0 then return false end
    local cats = EUI_CategoryManager:GetCategories()
    if not cats then return false end
    for _, mi in ipairs(members) do
        if not IsArmoryGearCategory(cats[mi]) then return false end
    end
    return true
end

-- Constants hoisted out of the per-item path (built once at load).
local ARMORY_IDS = {
    wand     = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand) or 19,
    bow      = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Bow) or 2,
    gun      = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Gun) or 3,
    crossbow = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Crossbow) or 18,
    cosmetic = Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic,
}
-- equipSlot -> { sortKey, Blizzard global-string name for the label }
local ARMORY_ARMOR_SLOTS = {
    INVTYPE_HEAD      = { 10, "INVTYPE_HEAD" },
    INVTYPE_NECK      = { 20, "INVTYPE_NECK" },
    INVTYPE_SHOULDER  = { 30, "INVTYPE_SHOULDER" },
    INVTYPE_CLOAK     = { 40, "INVTYPE_CLOAK" },
    INVTYPE_CHEST     = { 50, "INVTYPE_CHEST" },
    INVTYPE_ROBE      = { 50, "INVTYPE_CHEST" },
    INVTYPE_BODY      = { 60, "INVTYPE_BODY" },
    INVTYPE_TABARD    = { 70, "INVTYPE_TABARD" },
    INVTYPE_WRIST     = { 80, "INVTYPE_WRIST" },
    INVTYPE_HAND      = { 90, "INVTYPE_HAND" },
    INVTYPE_WAIST     = { 100, "INVTYPE_WAIST" },
    INVTYPE_LEGS      = { 110, "INVTYPE_LEGS" },
    INVTYPE_FEET      = { 120, "INVTYPE_FEET" },
    INVTYPE_FINGER    = { 140, "INVTYPE_FINGER" },
    INVTYPE_TRINKET   = { 150, "INVTYPE_TRINKET" },
}

-- Sort key + label for one item's equip slot. Item facts are fetched lazily
-- (GetItemInfoInstant, local client DB) and cached on the slot table -- the
-- refresh pre-cache deliberately does not fill them, so this runs only for
-- gear items and only while Group Gear by Slot is on (grid, Compact and the
-- List display's gear categories).
local function GetArmorySlotBucket(data)
    local equipSlot = data._equipSlot
    local classID = data._classID
    local subclassID = data._subclassID
    if data.itemLink and classID == nil then
        local _
        _, _, _, equipSlot, _, classID, subclassID = GetItemInfoInstant(data.itemLink)
        data._equipSlot, data._classID, data._subclassID = equipSlot, classID, subclassID
    end

    if classID == IC_ARMOR and ARMORY_IDS.cosmetic and subclassID == ARMORY_IDS.cosmetic then
        return 130, EllesmereUI.L("Cosmetic")
    end

    equipSlot = equipSlot or ""

    if equipSlot == "INVTYPE_WEAPONOFFHAND" or equipSlot == "INVTYPE_HOLDABLE" or equipSlot == "INVTYPE_SHIELD" then
        return 180, EllesmereUI.L("OH")
    end

    if classID == IC_WEAPON then
        if subclassID == ARMORY_IDS.wand then
            return 170, EllesmereUI.L("1H")
        end
        if subclassID == ARMORY_IDS.bow or subclassID == ARMORY_IDS.gun or subclassID == ARMORY_IDS.crossbow then
            return 190, _G["INVTYPE_RANGED"] or EllesmereUI.L("Ranged")
        end
        if equipSlot == "INVTYPE_2HWEAPON" then
            return 160, EllesmereUI.L("2H")
        end
        if equipSlot == "INVTYPE_RANGED" or equipSlot == "INVTYPE_RANGEDRIGHT" then
            return 190, _G["INVTYPE_RANGED"] or EllesmereUI.L("Ranged")
        end
        if equipSlot == "INVTYPE_WEAPON" or equipSlot == "INVTYPE_WEAPONMAINHAND" then
            return 170, EllesmereUI.L("1H")
        end
    end

    local entry = ARMORY_ARMOR_SLOTS[equipSlot]
    if entry then
        return entry[1], _G[entry[2]] or equipSlot
    end

    return 999, EllesmereUI.L("Other")
end

local function BuildSlotBuckets(itemList)
    local byKey = {}
    for _, data in ipairs(itemList) do
        local sk, label = GetArmorySlotBucket(data)
        local b = byKey[sk]
        if not b then
            b = { sortKey = sk, label = label, items = {} }
            byKey[sk] = b
        end
        b.items[#b.items + 1] = data
    end
    local keys = {}
    for sk in pairs(byKey) do
        keys[#keys + 1] = sk
    end
    table.sort(keys)
    local out = {}
    for _, sk in ipairs(keys) do
        local b = byKey[sk]
        if #b.items > 0 then
            PreCacheSortFields(b.items)
            table.sort(b.items, VisualSortCompare)
            out[#out + 1] = b
        end
    end
    return out
end

local function ArmorySlotGroupingEnabled()
    if not BP().bagArmoryGroupBySlot then return false end
    local dc = BP().bagDisabledCategories
    return not (dc and dc["Armor"])
end

-------------------------------------------------------------------------------
--  Slot data table pool (avoids ~200 table allocations per refresh)
-------------------------------------------------------------------------------
local _slotPool = {}
local _slotPoolN = 0
local _activeSlotTables = {}
local _activeSlotN = 0

local function AcquireSlotTable()
    local t
    if _slotPoolN > 0 then
        t = _slotPool[_slotPoolN]
        _slotPool[_slotPoolN] = nil
        _slotPoolN = _slotPoolN - 1
        wipe(t)
    else
        t = {}
    end
    _activeSlotN = _activeSlotN + 1
    _activeSlotTables[_activeSlotN] = t
    return t
end

local function ReleaseAllSlotTables()
    for i = 1, _activeSlotN do
        _slotPoolN = _slotPoolN + 1
        _slotPool[_slotPoolN] = _activeSlotTables[i]
        _activeSlotTables[i] = nil
    end
    _activeSlotN = 0
end

-- Merge duplicate non-gear items by itemLink within an already-ordered list.
-- itemLink encodes stats/bonuses, so items with different stats stay separate.
-- Must run AFTER ApplySavedOrder so the first occurrence in visual order wins.
-- Returns a new list; the caller's tables are NEVER modified. A merged winner is
-- replaced in the returned list by a pooled, display-only shallow copy carrying
-- the aggregate in _mergedCount. Invariant: only those copies ever carry
-- _mergedCount, which is also the "already a copy" test below. If anyone ever
-- writes _mergedCount back onto a canonical slot table, both break.
-- The result must not outlive the render pass that produced it: the copies come
-- from the slot pool and are recycled by ReleaseAllSlotTables on the next refresh.
local function MergeDuplicates(items)
    -- Record what this paint was built with, so the bags OnShow can tell that
    -- the state changed while they were hidden and repaint (see OnShow).
    SetPaintedPanelOpen(_anyItemPanelOpen)
    if _anyItemPanelOpen or BP().bagMergeDuplicates == false then return items end
    -- Session-only unmerge marks (EUI_Bags._unmergedLinks: set by the split
    -- dialog, wiped when the bags close, never persisted): a marked item keeps
    -- its real stacks apart so a split's pieces are visible in these views.
    local unmerged = EUI_Bags._unmergedLinks
    -- Painted-with-marks state, the same job _paintedPanelOpen does: the bags
    -- OnShow repaints when the marks were wiped by the close that hid them.
    EUI_Bags._paintedUnmerged = (unmerged ~= nil and next(unmerged) ~= nil) or nil
    local seen = {}
    local out = {}
    for _, data in ipairs(items) do
        local key = data.itemLink
        if key and not IsGearCategory(data.categoryIndex or 0) and not (unmerged and unmerged[key]) then
            local idx = seen[key]
            if idx then
                local prev = out[idx]
                if not prev._mergedCount then
                    -- First duplicate for this key: swap the winner out for a copy.
                    -- The aggregate cannot live on the winner itself, because the
                    -- OneBag/MultiBag bag grid paints those same slot tables with no
                    -- merge pass of its own and would show one slot's count inflated
                    -- by its twins. data.info stays shared by reference on purpose.
                    local proxy = AcquireSlotTable()
                    for k, v in pairs(prev) do proxy[k] = v end
                    proxy._mergedCount = prev.info.stackCount or 1
                    out[idx] = proxy
                    prev = proxy
                end
                prev._mergedCount = prev._mergedCount + (data.info.stackCount or 1)
            else
                out[#out + 1] = data
                seen[key] = #out
            end
        else
            out[#out + 1] = data
        end
    end
    return out
end

-- Saved visual order per category/group in BP().bagVisualOrder, keyed by category index
-- (number) or group name (string): an ordered list of "bag:slot" strings; missing items append to the end.
local function GetVisualOrder()
    if not BP().bagVisualOrder then BP().bagVisualOrder = {} end
    return BP().bagVisualOrder
end

local function SaveCategoryOrder(key, items)
    local order = GetVisualOrder()
    local list = {}
    for i, data in ipairs(items) do
        list[i] = data.info and data.info.itemID or 0
    end
    order[key] = list
end

local function ApplySavedOrder(key, items)
    local order = GetVisualOrder()
    local saved = order[key]
    if not saved or #saved == 0 then return end

    -- Build position queues per itemID: each ID maps to its saved positions
    local posQueues = {}
    for i, id in ipairs(saved) do
        if not posQueues[id] then posQueues[id] = {} end
        local q = posQueues[id]
        q[#q + 1] = i
    end

    -- Assign each item a saved position (consume from queue) or append to end
    local consumed = {}
    local nextUnsaved = #saved + 1
    for _, data in ipairs(items) do
        local id = data.info and data.info.itemID or 0
        local q = posQueues[id]
        local ci = consumed[id] or 1
        if q and ci <= #q then
            data._savedPos = q[ci]
            consumed[id] = ci + 1
        else
            data._savedPos = nextUnsaved
            nextUnsaved = nextUnsaved + 1
        end
    end

    table.sort(items, function(a, b)
        if a._savedPos ~= b._savedPos then return a._savedPos < b._savedPos end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
end

-- Clear saved visual order for a group (called when ungrouping)
local function ClearGroupOrder(groupName)
    if not groupName then return end
    local order = GetVisualOrder()
    order[groupName] = nil
end

-- Bag snapshot: tracks bag:slot -> itemID between refreshes for swap detection
local _bagSnapshot = {}

local function TakeBagSnapshot(tempItems)
    wipe(_bagSnapshot)
    for _, d in ipairs(tempItems) do
        if d.info and d.info.itemID then
            _bagSnapshot[d.bag * 1000 + d.slot] = d.info.itemID
        end
    end
end

-- Detect manual item swaps; with applySwap, also updates the saved visual order. Returns true if a swap was detected.
local function DetectAndApplySwaps(tempItems, applySwap)
    if not next(_bagSnapshot) then return false end

    local current = {}
    for _, d in ipairs(tempItems) do
        if d.info and d.info.itemID then
            current[d.bag * 1000 + d.slot] = d.info.itemID
        end
    end

    local swapChanges = {}
    for key, oldID in pairs(_bagSnapshot) do
        local curID = current[key]
        if curID and curID ~= oldID then
            swapChanges[#swapChanges + 1] = { curID = curID, oldID = oldID }
        end
    end

    -- Swap pattern: exactly 2 item-to-item changes that cross-match
    if #swapChanges == 2 then
        local c1, c2 = swapChanges[1], swapChanges[2]
        if c1.curID == c2.oldID and c2.curID == c1.oldID and c1.curID ~= c2.curID then
            if applySwap then
                local id1, id2 = c1.curID, c2.curID
                local vo = GetVisualOrder()
                for _, saved in pairs(vo) do
                    local idx1, idx2
                    for i, sid in ipairs(saved) do
                        if sid == id1 and not idx1 then idx1 = i
                        elseif sid == id2 and not idx2 then idx2 = i end
                    end
                    if idx1 and idx2 then
                        saved[idx1], saved[idx2] = saved[idx2], saved[idx1]
                    end
                end
            end
            return true
        end
    end
    return false
end

-- Category indices + group names needing re-sort: filled by ResortAfterGroupChange, consumed by RefreshInventory.
local _pendingResortCats = {}
local _pendingResortGroups = {}

-- Invalidate saved order; RefreshInventory does the re-sort on already-scanned items.
local function ResortAfterGroupChange(catIndices, groupName)
    local order = GetVisualOrder()
    for _, ci in ipairs(catIndices) do
        order[ci] = nil
        _pendingResortCats[ci] = true
    end
    if groupName then
        order[groupName] = nil
        _pendingResortGroups[groupName] = true
    end
end

-------------------------------------------------------------------------------
--  Slot pools
-------------------------------------------------------------------------------
local itemSlots    = {}
local reagentSlots = {}
local bagSlots     = {}

-------------------------------------------------------------------------------
--  Pawn bag upgrade advisor integration
-------------------------------------------------------------------------------
local pawnRegistered = false
local pawnPending = setmetatable({}, { __mode = "k" })
local pawnPositioned = setmetatable({}, { __mode = "k" })
local pawnRetryScheduled = false
local UpdatePawnArrow

local function RetryPawnArrows()
    pawnRetryScheduled = false
    local pending = pawnPending
    pawnPending = setmetatable({}, { __mode = "k" })

    for btn, expectedLink in pairs(pending) do
        local parent = btn:GetParent()
        local currentLink = parent and C_Container.GetContainerItemLink(parent:GetID(), btn:GetID())
        if btn:IsShown() and currentLink == expectedLink then
            UpdatePawnArrow(btn, currentLink)
        end
    end
end

UpdatePawnArrow = function(btn, itemLink)
    if not pawnRegistered or not btn.UpgradeIcon then return end
    if not pawnPositioned[btn] then
        btn.UpgradeIcon:ClearAllPoints()
        btn.UpgradeIcon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.UpgradeIcon:SetSize(16, 16)
        pawnPositioned[btn] = true
    end
    btn.UpgradeIcon:Hide()

    if not itemLink or not PawnCommon or not PawnCommon.ShowBagUpgradeAdvisor then
        pawnPending[btn] = nil
        return
    end

    local isUpgrade = PawnShouldItemLinkHaveUpgradeArrow(itemLink, true)
    if isUpgrade == nil then
        pawnPending[btn] = itemLink
        if not pawnRetryScheduled then
            pawnRetryScheduled = true
            C_Timer.After(0, RetryPawnArrows)
        end
    else
        pawnPending[btn] = nil
        btn.UpgradeIcon:SetShown(isUpgrade)
    end
end

local function RefreshPawnArrows()
    if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
    if EUI_BagsReagent:IsVisible() then EUI_BagsReagent:RefreshInventory() end
    -- The Item Icons takeover draws Pawn's arrow on the bank's slots too
    -- (RefreshBank returns while the bank is closed)
    if ns.ItemIconsOn() then ns.RefreshOpenBank() end
end

local function RegisterPawnIntegration()
    if pawnRegistered or BP().enhancedBags == false then return end
    if type(PawnRegisterThirdPartyBag) ~= "function"
        or type(PawnShouldItemLinkHaveUpgradeArrow) ~= "function" then return end

    pawnRegistered = true
    PawnRegisterThirdPartyBag("EllesmereUI Bags", {
        RefreshAll = RefreshPawnArrows,
    })
end

-------------------------------------------------------------------------------
--  Per-category state (for targeted sidebar updates on item count changes)
-------------------------------------------------------------------------------
local _slotCategories = {}     -- bag*1000+slot -> categoryIndex from last full refresh

I._anyItemPanelOpen, I._openItemPanels = _anyItemPanelOpen, _openItemPanels
I._pendingResortCats, I._pendingResortGroups = _pendingResortCats, _pendingResortGroups
I._slotCategories, I.AcquireSlotTable = _slotCategories, AcquireSlotTable
I.ApplySavedOrder, I.ArmorySlotGroupingEnabled = ApplySavedOrder, ArmorySlotGroupingEnabled
I.bagSlots, I.BuildExpansionBuckets = bagSlots, BuildExpansionBuckets
I.BuildSlotBuckets, I.ClearGroupOrder = BuildSlotBuckets, ClearGroupOrder
I.DetectAndApplySwaps, I.FOOTER_H = DetectAndApplySwaps, FOOTER_H
I.GetArmorySlotBucket, I.HEADER_H = GetArmorySlotBucket, HEADER_H
I.IsArmoryGearCategory, I.IsGearOnlyGroup = IsArmoryGearCategory, IsGearOnlyGroup
I.itemSlots, I.MergeDuplicates = itemSlots, MergeDuplicates
I.PreCacheSortFields, I.reagentSlots = PreCacheSortFields, reagentSlots
I.RegisterPawnIntegration = RegisterPawnIntegration
I.ReleaseAllSlotTables, I.ResortAfterGroupChange = ReleaseAllSlotTables, ResortAfterGroupChange
I.SaveCategoryOrder, I.selectedCategoryIndex = SaveCategoryOrder, selectedCategoryIndex
I.SetItemPanelOpen, I.SIDEBAR_BTN_H = SetItemPanelOpen, SIDEBAR_BTN_H
I.SIDEBAR_ICON_SIZE, I.SIDEBAR_INDENT = SIDEBAR_ICON_SIZE, SIDEBAR_INDENT
I.SIDEBAR_PAD, I.SIDEBAR_W_COLLAPSED = SIDEBAR_PAD, SIDEBAR_W_COLLAPSED
I.SIDEBAR_W_EXPANDED, I.TakeBagSnapshot = SIDEBAR_W_EXPANDED, TakeBagSnapshot
I.UpdatePawnArrow, I.VisualSortCompare = UpdatePawnArrow, VisualSortCompare
I.broken = false
