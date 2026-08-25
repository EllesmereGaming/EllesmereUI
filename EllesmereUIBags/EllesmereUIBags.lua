if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags.lua -- Enhanced Bags System for EllesmereUI (Midnight): sidebar category filter + flat item grid layout.
-------------------------------------------------------------------------------
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS["EllesmereUIBags"] = select(2, ...)  -- LOD options files read this module ns via the registry

EUI_Bags = CreateFrame("Frame", "EUI_MainBagFrame", UIParent)
EUI_Bags:Hide()
-- Auto-size state: reset on close (next open sizes from its first/active tab);
-- while open it only grows, never shrinks.
EUI_Bags:HookScript("OnHide", function(self)
    self._asCols  = nil
    self._asMaxGridW = nil
    self._asMaxH  = nil
end)

EUI_BagsReagent = CreateFrame("Frame", "EUI_ReagentBagFrame", UIParent)
EUI_BagsReagent:Hide()

EUI_BagsWindow = CreateFrame("Frame", "EUI_BagsWindowFrame", UIParent)
EUI_BagsWindow:Hide()

local SLOT_SIZE, SPACING = 34, 4

-- Red-tint usability test (shared with the bank module via EUI). Tooltip must come from
-- the real item, never GetItemByID: scaling gear's bonus IDs lower its required level, but
-- GetItemByID shows the unscaled base item's level (reads red). Prefer bag slot > link > ID; cache by link, wipe on level-up.
local _canUseCache = {}
local ITEM_CLASS_RECIPE = Enum.ItemClass.Recipe
local function BagsItemUnusable(bagID, slot, itemLink, itemID)
    local item = itemLink or itemID
    if not item then return false end
    local cached = _canUseCache[item]
    if cached ~= nil then return cached end
    local unusable = false

    -- Recipes also have a spell (the teach effect), so they'd hit the tooltip scan
    -- below. Skip that: the scan can see red from the crafted item's own preview
    -- stats, not just from the recipe's learn requirements. Use the usable check
    -- instead, which reflects skill/known state directly.
    local _, _, _, _, _, classID = GetItemInfoInstant(item)
    if classID == ITEM_CLASS_RECIPE then
        local usable = C_Item.IsUsableItem(item)
        unusable = not usable
        _canUseCache[item] = unusable
        return unusable
    end

    if IsEquippableItem(item) or C_Item.GetItemSpell(item) then
        -- Only use a tooltip from the real bag slot or real item link; both carry
        -- bonus IDs, which set the item's true required level. A bare itemID lacks
        -- those and can read the wrong level requirement either way.
        local tip, reliable
        if bagID and slot then
            tip = C_TooltipInfo.GetBagItem(bagID, slot)
            reliable = true
        elseif itemLink then
            tip = C_TooltipInfo.GetHyperlink(itemLink)
            reliable = true
        end
        if tip and tip.lines then
            for _, row in ipairs(tip.lines) do
                local lc = row.leftColor
                -- Tolerance, not exact equality: rounding can put red just under r=1.
                if lc and lc.r > 0.9 and lc.g < 0.2 and lc.b < 0.2
                   and row.leftText ~= ITEM_SCRAPABLE_NOT
                   and row.leftText ~= CANNOT_UNEQUIP_COMBAT
                   and row.leftText ~= ITEM_DISENCHANT_NOT_DISENCHANTABLE then
                    unusable = true
                    break
                end
                local rc = row.rightColor
                if rc and rc.r > 0.9 and rc.g < 0.2 and rc.b < 0.2 then
                    unusable = true
                    break
                end
            end
        end
        if not reliable then
            -- No bag slot or link yet, so don't cache a guess. A later call with
            -- real data will compute and cache the right answer.
            return unusable
        end
    end
    _canUseCache[item] = unusable
    return unusable
end
EllesmereUI._BagsItemUnusable = BagsItemUnusable  -- local EUI alias is declared further down
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("PLAYER_LEVEL_CHANGED")
    f:SetScript("OnEvent", function() wipe(_canUseCache) end)
end
-- Weak-keyed bank-deposit routing state: custom keys written onto a ContainerFrameItemButtonTemplate
-- in PreClick taint the secure execution chain -> UseContainerItem() ADDON_ACTION_FORBIDDEN.
local _bankRouted = setmetatable({}, { __mode = "k" })

local EUI = EllesmereUI
-- Profile access helper (DB created in EUI_Bags_Options.lua, loaded first per TOC)
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end

-- Tracked currencies are PER CHARACTER: their input feed (Blizzard's currency
-- tab via the TokenFrame.OnTokenWatchChanged sync below) is per-character, so
-- a shared store can only bleed across characters. Stored at the EllesmereUIDB
-- ROOT beside the module's other per-character data (characterGold,
-- bagPinnedItems, bagItemAssignments), NEVER in the bag profile:
-- ApplyProfileData wipes db.profile wholesale on import (would erase every
-- character's currencies), and profile exports must not ship a character
-- roster (the PRIVATE_ADDON_KEYS leak class).
local _bagsCharKey  -- session-constant; UpdateCurrencyDisplays is a render path
local function BagsCharKey()
    if not _bagsCharKey then
        local n, r = UnitName("player"), GetRealmName()
        if not n or not r then return nil end  -- too early; do not cache a stub
        _bagsCharKey = n .. " - " .. r
    end
    return _bagsCharKey
end

-- The per-character order table, seeded on this character's first use.
-- Returns nil only when the DB or the player identity is not up yet (callers
-- already handle that).
local function CurrencyOrder()
    if not EllesmereUIDB then return nil end
    local key = BagsCharKey()
    if not key then return nil end
    local byChar = EllesmereUIDB.bagCurrencyByChar
    if type(byChar) ~= "table" then byChar = {}; EllesmereUIDB.bagCurrencyByChar = byChar end
    local t = byChar[key]
    if type(t) ~= "table" then
        t = {}
        -- Seed once per character from the legacy shared profile table. The
        -- legacy table is deliberately never deleted: a per-character
        -- migration is never a one-shot (a character that has not logged in
        -- yet still seeds from it later), and nothing writes it any more.
        local legacy = BP().currencyOrder
        if type(legacy) == "table" then
            for cID, order in pairs(legacy) do
                if type(order) == "number" then t[cID] = order end
            end
        end
        byChar[key] = t
    end
    return t
end
EUI._BagsCurrencyOrder = CurrencyOrder

-- Default bag-type view ("all"|"onebag"|"multibag"), falling back to legacy
-- bagDefaultOneBag bool (imports converted in ApplyProfileData before DeepMergeDefaults masks it); exposed on EUI so bank file matches.
local function GetDefaultBagType()
    local v = BP().bagDefaultBagType
    if v == "all" or v == "onebag" or v == "multibag" then return v end
    return BP().bagDefaultOneBag and "onebag" or "all"
end
EUI._GetBagDefaultType = GetDefaultBagType

local function ApplyBagScale()
    local s = BP().bagScale or 1
    if EUI_Bags then EUI_Bags:SetScale(s) end
    if EUI_BagsReagent then EUI_BagsReagent:SetScale(s) end
    if EUI_BagsWindow then EUI_BagsWindow:SetScale(s) end
end

local GetUpgradeTrack = EUI.GetUpgradeTrack
-- Locale-safe gear detection: GetItemInfo type strings are localized ("Armor" only on enUS), so use GetItemInfoInstant's numeric classID.
local ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon  -- 2
local ITEM_CLASS_ARMOR  = Enum.ItemClass.Armor   -- 4
local function IsGearItem(itemLink)
    if not itemLink then return false end
    local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
    return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
end
local function GetItemLevelAtLocation(loc, itemLink)
    if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
        local level = C_Item.GetCurrentItemLevel(loc)
        if level and level > 0 then return level end
    end
    return itemLink and C_Item.GetDetailedItemLevelInfo(itemLink) or nil
end
local function GetFont() return (EUI.GetFontPath and EUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF" end
local function GetOutline() return (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("bags")) or "" end
local function SetBagFont(fs, size)
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, true) end
    fs:SetFont(GetFont(), size, GetOutline())
end
local function GetAccentRGB()
    if EUI.GetAccentColor then return EUI.GetAccentColor() end
    return 0.047, 0.824, 0.616
end

local function GetColumns()
    -- Auto-size overrides the user's column count with one that keeps the base aspect ratio while fitting the active tab.
    if EUI_Bags and EUI_Bags._asCols and BP().bagAutoSize then
        return EUI_Bags._asCols
    end
    return BP().bagColumns or 12
end
local function GetCatTitleSize()
    return BP().bagCatTitleSize or 11
end

-- Abbreviate a dungeon name to initials (skipping connector words); Cyrillic entries cover clients where GetMapUIInfo returns translated names.
local _dungeonAbbrCache = {}
local _skipWords = {
    ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true,
    ["из"] = true, ["за"] = true, ["в"] = true, ["на"] = true,
    ["и"] = true, ["под"] = true, ["с"] = true,
}
local function AbbrevDungeon(mapID)
    local cached = _dungeonAbbrCache[mapID]
    if cached then return cached end
    local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
    if not name or name == "" then return "" end
    local abbr = ""
    -- Split on whitespace AND hyphens so "Nexus-Point Xenas" abbreviates to NPX.
    for word in name:gmatch("[^%s%-]+") do
        if not _skipWords[word:lower()] then
            -- First whole UTF-8 char (sub(1,1) would split Cyrillic; same for ASCII)
            local wordUpper = word:upper()
            local firstChar = wordUpper:match("^[%z\1-\127\194-\244][\128-\191]*")
            abbr = abbr .. (firstChar or "")
        end
    end
    -- Locale files may register EllesmereUI._dungeonAbbrevOverride (plain data) for locale-specific cuts; applied here at the single render source, not via hook.
    local ov = EllesmereUI and EllesmereUI._dungeonAbbrevOverride
    if ov and ov[abbr] then abbr = ov[abbr] end
    _dungeonAbbrCache[mapID] = abbr
    return abbr
end

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

function EUI_Bags:SetSelectedView(idx)
    selectedCategoryIndex = idx
    selectedGroupName = nil
end

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
        selectedCategoryIndex = found
    end
    if selectedGroupName then
        local alive = false
        for _, cat in ipairs(mgr:GetCategories()) do
            if cat.groupName == selectedGroupName then alive = true; break end
        end
        if not alive then selectedGroupName = nil; selectedCategoryIndex = 0 end
    end
end

-- Visual sort: quality desc > name > itemID > bag > slot; the bag+slot tiebreaker makes output deterministic (Lua 5.1 sort is unstable).
local _trackRank = EUI._TRACK_RANK
-- Gear category lookup: built lazily, maps catIdx -> true for gear categories
local _gearCatSet
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

-- Item panels (mail/trade/AH/bank/guildbank) take one bag slot at a time; a merged button
-- only hands over the slot behind it (3 merged mails would mail 1), so duplicates stay unmerged while any panel is open. bagMergeDuplicates disables merging outright.
local _openItemPanels = {}
local _anyItemPanelOpen = false
-- Unmerge state the CURRENT painted layout was built with; bags OnShow compares against it so a flip while hidden still repaints (closing a mailbox hides both).
local _paintedPanelOpen = false
-- Returns true when the aggregate state flipped, so the caller can refresh.
local function SetItemPanelOpen(key, open)
    _openItemPanels[key] = open or nil
    local any = next(_openItemPanels) ~= nil
    if any == _anyItemPanelOpen then return false end
    _anyItemPanelOpen = any
    return true
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
-- gear items and only while Group Armory by Slot is on.
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
    _paintedPanelOpen = _anyItemPanelOpen
    if _anyItemPanelOpen or BP().bagMergeDuplicates == false then return items end
    local seen = {}
    local out = {}
    for _, data in ipairs(items) do
        local key = data.itemLink
        if key and not IsGearCategory(data.categoryIndex or 0) then
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
local _lastCatCounts = {}      -- category counts from last full refresh
local _lastTotalCount = 0      -- total item count from last full refresh

-------------------------------------------------------------------------------
--  HSV helper (upgrade indicator)
-------------------------------------------------------------------------------
local function HSVToRGB(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if     i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else                return v, p, q
    end
end

-------------------------------------------------------------------------------
--  UI Components -- Header
-------------------------------------------------------------------------------
local function CreateHeader()
    if EUI_Bags.Header then return end
    local header = CreateFrame("Frame", nil, EUI_Bags)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0, 0, 0, 0.5)

    header.title = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.title, 13)
    header.title:SetPoint("LEFT", header, "LEFT", 8, 0)
    header.title:SetText(EllesmereUI.L("Inventory"))
    header.title:SetTextColor(1, 1, 1)

    -- Item count (updated by RefreshInventory)
    header.itemCount = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.itemCount, 11)
    header.itemCount:SetPoint("LEFT", header.title, "RIGHT", 8, 0)
    header.itemCount:SetTextColor(0.6, 0.6, 0.6)

    local search = CreateFrame("EditBox", "EUI_BagSearchBox", header)
    search:SetSize(160, 22)
    search:SetPoint("RIGHT", -35, 0)
    search:SetFont(GetFont(), 12, GetOutline())
    search:SetAutoFocus(false)
    search:SetTextInsets(5, 26, 0, 0)
    search.bg = search:CreateTexture(nil, "BACKGROUND")
    search.bg:SetAllPoints()
    search.bg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(search, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7) end

    local placeholder = search:CreateFontString(nil, "OVERLAY")
    SetBagFont(placeholder, 11)
    placeholder:SetPoint("LEFT", search, "LEFT", 5, 0)
    placeholder:SetText(EllesmereUI.L("Search..."))
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    EUI_Bags._searchBox = search

    local sort = CreateFrame("Button", nil, header)
    sort:SetSize(24, 24)
    sort:SetPoint("RIGHT", search, "LEFT", -13, 0)
    sort.icon = sort:CreateTexture(nil, "OVERLAY")
    sort.icon:SetAllPoints()
    sort.icon:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\clean-up.png")
    sort.icon:SetAlpha(0.9)

    sort:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Sort Items") end
    end)
    sort:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    local sortLocked = false
    -- One reusable BAG_UPDATE listener per role. Both phases are strictly
    -- sequential, and a fresh CreateFrame per round leaked frames per click
    -- (frames are never collected). The run token keeps a second sort from
    -- inheriting the first one's callbacks: EndDragDrop can unlock the button
    -- mid-run, and a stale callback clearing the live chain's OnEvent would
    -- strand it with refreshEnabled false (bags frozen until reload).
    local consolidateFrame, retryFrame
    local function LockSort()
        sortLocked = true
        sort:EnableMouse(false)
        sort.icon:SetAlpha(0.2)
        if EUI_Bags._diceBtn then
            EUI_Bags._diceBtn:EnableMouse(false)
            EUI_Bags._diceBtn.icon:SetAlpha(0.2)
        end
    end
    local function UnlockSort()
        if not sortLocked then return end
        sortLocked = false
        sort:EnableMouse(true)
        sort.icon:SetAlpha(0.9)
        if EUI_Bags._diceBtn then
            EUI_Bags._diceBtn:EnableMouse(true)
            EUI_Bags._diceBtn.icon:SetAlpha(0.9)
        end
    end
    EUI_Bags._unlockSort = UnlockSort

    local DoVisualSort  -- forward declaration

    local function DoPhysicalSort()
        LockSort()
        EUI_Bags.refreshEnabled = false

        local sfxWas = GetCVar("Sound_EnableSFX")
        SetCVar("Sound_EnableSFX", "0")

        -----------------------------------------------------------------------
        --  Phase 1: consolidate partial stacks (smallest onto largest of the same itemID; the engine performs the combine).
        -----------------------------------------------------------------------
        local function ConsolidateStacks(onDone)
            -- Max stack size is a static per-itemID fact, but it was re-read
            -- through GetItemInfo for every occupied slot on every pass (up to
            -- 30 passes over six bags). Memo it for the run instead; the
            -- ItemLocation + DoesItemExist guard it used to sit behind is
            -- redundant, GetContainerItemInfo just returned the item.
            local maxStackByID = {}
            local function ByCount(a, b) return a.count < b.count end
            local function DoOnePass()
                local stacks = {}  -- itemID -> { {bag,slot,count}, ... }
                for bag = 0, 5 do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID and info.stackCount then
                            local maxStack = maxStackByID[info.itemID]
                            if not maxStack then
                                maxStack = select(8, C_Item.GetItemInfo(info.itemID))
                                -- Uncached item data: don't memo the fallback,
                                -- a later pass can still resolve it.
                                if maxStack then maxStackByID[info.itemID] = maxStack
                                else maxStack = 1 end
                            end
                            if maxStack > 1 and info.stackCount < maxStack then
                                if not stacks[info.itemID] then stacks[info.itemID] = {} end
                                stacks[info.itemID][#stacks[info.itemID] + 1] = {
                                    bag = bag, slot = slot, count = info.stackCount,
                                }
                            end
                        end
                    end
                end
                -- Emptiest partial merges into fullest, second-emptiest into
                -- second-fullest, and so on: every slot is touched at most
                -- once, so all pairs of this pass still fire same-frame -- but
                -- an item with 2n partial stacks now converges in log rounds
                -- instead of n BAG_UPDATE round trips. Overflow waits for a
                -- later pass, same as before.
                local merged = false
                for _, partials in pairs(stacks) do
                    local n = #partials
                    if n >= 2 then
                        table.sort(partials, ByCount)
                        local lo, hi = 1, n
                        while lo < hi do
                            local source, target = partials[lo], partials[hi]
                            local srcLoc = ItemLocation:CreateFromBagAndSlot(source.bag, source.slot)
                            local dstLoc = ItemLocation:CreateFromBagAndSlot(target.bag, target.slot)
                            if not C_Item.IsLocked(srcLoc) and not C_Item.IsLocked(dstLoc) then
                                C_Container.PickupContainerItem(source.bag, source.slot)
                                C_Container.PickupContainerItem(target.bag, target.slot)
                                ClearCursor()
                                merged = true
                            end
                            lo = lo + 1
                            hi = hi - 1
                        end
                    end
                end
                return merged
            end

            if not DoOnePass() then
                onDone()
                return
            end

            local consolidateRetry = 0
            if not consolidateFrame then consolidateFrame = CreateFrame("Frame") end
            local runToken = {}
            consolidateFrame._runToken = runToken
            consolidateFrame:RegisterEvent("BAG_UPDATE")
            consolidateFrame:SetScript("OnEvent", function(self)
                if self._runToken ~= runToken then return end
                self:UnregisterAllEvents()
                consolidateRetry = consolidateRetry + 1
                C_Timer.After(0.15, function()
                    if consolidateFrame._runToken ~= runToken then return end
                    if consolidateRetry < 30 and DoOnePass() then
                        self:RegisterEvent("BAG_UPDATE")
                    else
                        self:SetScript("OnEvent", nil)
                        onDone()
                    end
                end)
            end)
        end

        -----------------------------------------------------------------------
        --  Phase 2: Sort
        -----------------------------------------------------------------------

        -- Scan, compute sorted order and execute all moves in one pass; re-scans every call so retries work from fresh state.
        local function ComputeAndExecute(bagMin, bagMax)
            bagMin = bagMin or 0
            bagMax = bagMax or 4
            local total = 0
            local sBag, sSlot, sKey, sID = {}, {}, {}, {}

            local items = {}
            for bag = bagMin, bagMax do
                local numSlots = C_Container.GetContainerNumSlots(bag)
                for slot = 1, numSlots do
                    total = total + 1
                    sBag[total] = bag
                    sSlot[total] = slot
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info then
                        local link = C_Container.GetContainerItemLink(bag, slot)
                        local key = link .. "\0" .. (info.stackCount or 0)
                        sKey[total] = key
                        sID[total] = info.itemID
                        items[#items + 1] = {
                            pos = total, bag = bag, slot = slot,
                            info = info, itemLink = link, key = key,
                        }
                    end
                end
            end

            if #items == 0 then return false end

            EUI_CategoryManager:ClassifyAll(items)
            local cats = EUI_CategoryManager:GetCategories()
            local sectionOrder = {}
            local ord = 0
            local doneGroups = {}
            for ci, cat in ipairs(cats) do
                if cat.groupName then
                    if not doneGroups[cat.groupName] then
                        doneGroups[cat.groupName] = true
                        ord = ord + 1
                        local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                        if members then
                            for _, mi in ipairs(members) do sectionOrder[mi] = ord end
                        end
                    end
                else
                    ord = ord + 1
                    sectionOrder[ci] = ord
                end
            end

            PreCacheSortFields(items)
            for _, d in ipairs(items) do
                d._sectionOrder = sectionOrder[d.categoryIndex] or 9999
            end
            table.sort(items, function(a, b)
                if a._sectionOrder ~= b._sectionOrder then return a._sectionOrder < b._sectionOrder end
                return VisualSortCompare(a, b)
            end)

            -- Compute moves via selection sort on pre-computed data (zero API calls)
            local atPos = {}
            local whereIs = {}
            for idx, d in ipairs(items) do
                atPos[d.pos] = idx
                whereIs[idx] = d.pos
            end

            -- Sorted item i targets slot i; Sort to Bottom offsets so the block lands in the LAST
            -- #items slots (free slots float up either way). The walk must move toward the free slots
            -- (forward for top, backward for bottom), or a displaced item lands in an already-visited slot -- costing a retry per move, risking the 15-retry cap.
            local offset, first, last, step = 0, 1, #items, 1
            if BP().bagSortToBottom then
                offset = total - #items
                first, last, step = #items, 1, -1
            end

            local moves = {}
            for i = first, last, step do
                local t = i + offset
                local s = whereIs[i]
                if s ~= t then
                    local displaced = atPos[t]
                    if displaced and sID[s] and sID[t] and sID[s] == sID[t] then
                        -- Same itemID: skip to avoid merge, retry will resolve
                    else
                        moves[#moves + 1] = { sBag[s], sSlot[s], sBag[t], sSlot[t] }
                        whereIs[i] = t
                        if displaced then whereIs[displaced] = s end
                        atPos[t] = i
                        atPos[s] = displaced
                        sID[s], sID[t] = sID[t], sID[s]
                        sKey[s], sKey[t] = sKey[t], sKey[s]
                    end
                end
            end

            for _, m in ipairs(moves) do
                C_Container.PickupContainerItem(m[1], m[2])
                C_Container.PickupContainerItem(m[3], m[4])
                ClearCursor()
            end

            return #moves > 0
        end

        local function FinishSort()
            SetCVar("Sound_EnableSFX", sfxWas)
            C_Timer.After(0.3, function()
                EUI_Bags.refreshEnabled = true
                EUI_Bags:RefreshInventory()
                C_Timer.After(3, UnlockSort)
            end)
        end

        local function RunRetryLoop(bagMin, bagMax, onDone)
            local moved = ComputeAndExecute(bagMin, bagMax)
            if not moved then onDone(); return end

            local retryCount = 0
            if not retryFrame then retryFrame = CreateFrame("Frame") end
            local runToken = {}
            retryFrame._runToken = runToken
            retryFrame:RegisterEvent("BAG_UPDATE")
            retryFrame:SetScript("OnEvent", function(self)
                if self._runToken ~= runToken then return end
                self:UnregisterAllEvents()
                retryCount = retryCount + 1
                C_Timer.After(0.15, function()
                    if retryFrame._runToken ~= runToken then return end
                    local moved = ComputeAndExecute(bagMin, bagMax)
                    if moved and retryCount < 15 then
                        self:RegisterEvent("BAG_UPDATE")
                    else
                        self:SetScript("OnEvent", nil)
                        onDone()
                    end
                end)
            end)
        end

        local function RunSort()
            RunRetryLoop(0, 4, function()
                if C_Container.GetContainerNumSlots(5) > 0 then
                    RunRetryLoop(5, 5, FinishSort)
                else
                    FinishSort()
                end
            end)
        end

        ConsolidateStacks(RunSort)
    end

    DoVisualSort = function()
        -- Sort items per category and save the order
        local cats = EUI_CategoryManager:GetCategories()
        local tempItems = {}
        for bag = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    local itemLink = C_Container.GetContainerItemLink(bag, slot)
                    tempItems[#tempItems + 1] = { bag = bag, slot = slot, info = info, itemLink = itemLink }
                end
            end
        end
        EUI_CategoryManager:ClassifyAll(tempItems)

        local itemsByCat = {}
        for i = 1, #cats do itemsByCat[i] = {} end
        for _, data in ipairs(tempItems) do
            local ci = data.categoryIndex
            if ci and itemsByCat[ci] then
                itemsByCat[ci][#itemsByCat[ci] + 1] = data
            end
        end

        local sortedGroups = {}
        for ci = 1, #cats do
            local cat = cats[ci]
            if cat.groupName then
                if not sortedGroups[cat.groupName] then
                    sortedGroups[cat.groupName] = true
                    -- Merge all members, sort as one, save under group name
                    local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                    local merged = {}
                    for _, mi in ipairs(members) do
                        for _, data in ipairs(itemsByCat[mi] or {}) do
                            merged[#merged + 1] = data
                        end
                    end
                    if #merged > 1 then PreCacheSortFields(merged); table.sort(merged, VisualSortCompare) end
                    SaveCategoryOrder(cat.groupName, merged)
                    -- Also save per-member order for individual category views
                    for _, mi in ipairs(members) do
                        local memberItems = itemsByCat[mi]
                        if memberItems and #memberItems > 1 then
                            PreCacheSortFields(memberItems); table.sort(memberItems, VisualSortCompare)
                        end
                        SaveCategoryOrder(mi, memberItems or {})
                    end
                end
            elseif not cat.isRecent and not cat.isPinned then
                local catItems = itemsByCat[ci]
                if #catItems > 1 then
                    PreCacheSortFields(catItems); table.sort(catItems, VisualSortCompare)
                end
                SaveCategoryOrder(ci, catItems)
            end
        end

        EUI_Bags:RefreshInventory()
        LockSort()
        C_Timer.After(3, UnlockSort)
    end

    -- MultiBag sort defers to Blizzard's native sort (insecure-callable, no taint; BAG_UPDATE
    -- storm drives our refresh). Sort to Bottom rides their fill direction (right-to-left = start
    -- at backpack = our top), floating free slots to our top. Real Blizzard CVar (also drives their Clean Up); set only while the option is on, re-asserted each sort.
    local function DoBlizzardSort()
        LockSort()
        if BP().bagSortToBottom and C_Container.SetSortBagsRightToLeft then
            C_Container.SetSortBagsRightToLeft(false)
        end
        C_Container.SortBags()
        C_Timer.After(3, UnlockSort)
    end

    sort:SetScript("OnClick", function()
        if sortLocked then return end
        if selectedCategoryIndex == -1 then
            if EllesmereUIDB and EllesmereUIDB.bagSortWarningDismissed then
                DoPhysicalSort()
            else
                EUI:ShowConfirmPopup({
                    title       = "OneBag Sort",
                    message     = "OneBag sorting will physically reorganize items in your bags. The changes persist even if you disable EllesmereUI Bags.",
                    confirmText = "Sort",
                    cancelText  = "Cancel",
                    checkbox    = "Don't show me again",
                    onConfirm   = function(dontShowAgain)
                        if dontShowAgain then
                            if not EllesmereUIDB then EllesmereUIDB = {} end
                            EllesmereUIDB.bagSortWarningDismissed = true
                        end
                        DoPhysicalSort()
                    end,
                })
            end
        elseif selectedCategoryIndex == -2 then
            if EllesmereUIDB and EllesmereUIDB.bagMultiSortWarningDismissed then
                DoBlizzardSort()
            else
                EUI:ShowConfirmPopup({
                    title       = "MultiBag Sort",
                    message     = "MultiBag uses Blizzard's built-in sorting system, which reorganizes the items in your default Blizzard bags. The changes persist even if you disable EllesmereUI Bags.",
                    confirmText = "Sort",
                    cancelText  = "Cancel",
                    checkbox    = "Don't show me again",
                    onConfirm   = function(dontShowAgain)
                        if dontShowAgain then
                            if not EllesmereUIDB then EllesmereUIDB = {} end
                            EllesmereUIDB.bagMultiSortWarningDismissed = true
                        end
                        DoBlizzardSort()
                    end,
                })
            end
        else
            DoVisualSort()
        end
    end)
    EUI_Bags._doVisualSort = DoVisualSort
    EUI_Bags._sortBtn = sort
    if BP().bagShowSortIcon == false then sort:Hide() end

    -- Randomize Button (dice icon, OneBag only, top-right of bag frame)
    local dice = CreateFrame("Button", nil, EUI_Bags)
    dice:SetSize(20, 20)
    dice:SetFrameLevel(EUI_Bags:GetFrameLevel() + 20)
    dice.icon = dice:CreateTexture(nil, "OVERLAY")
    dice.icon:SetAllPoints()
    dice.icon:SetAtlas("charactercreate-icon-dice")
    dice.icon:SetDesaturated(true)
    dice.icon:SetVertexColor(0.82, 0.7, 0.55)
    dice.icon:SetAlpha(0.9)
    dice:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(0.88, 0.8, 0.7)
        self.icon:SetAlpha(1)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Randomize") end
    end)
    dice:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.82, 0.7, 0.55)
        self.icon:SetAlpha(0.9)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    local function DoRandomize()
        LockSort()
        EUI_Bags.refreshEnabled = false

        local slots = {}
        local items = {}
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                slots[#slots + 1] = { bag = bag, slot = slot }
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    items[#items + 1] = { bag = bag, slot = slot, info = info }
                end
            end
        end

        local targetSlots = {}
        for i = 1, #slots do targetSlots[i] = i end
        for i = #targetSlots, 2, -1 do
            local j = math.random(1, i)
            targetSlots[i], targetSlots[j] = targetSlots[j], targetSlots[i]
        end
        for i = #items, 2, -1 do
            local j = math.random(1, i)
            items[i], items[j] = items[j], items[i]
        end

        local posFromKey = {}
        for i, s in ipairs(slots) do posFromKey[s.bag * 1000 + s.slot] = i end
        local current = {}
        local whereIs = {}
        for i = 1, #slots do current[i] = 0 end
        for si, d in ipairs(items) do
            local pi = posFromKey[d.bag * 1000 + d.slot]
            if pi then current[pi] = si; whereIs[si] = pi end
        end

        local moves = {}
        for si = 1, #items do
            local dest = targetSlots[si]
            local curPos = whereIs[si]
            if curPos ~= dest then
                local displaced = current[dest]
                current[dest] = si
                current[curPos] = displaced
                whereIs[si] = dest
                if displaced > 0 then whereIs[displaced] = curPos end
                moves[#moves + 1] = { slots[curPos].bag, slots[curPos].slot, slots[dest].bag, slots[dest].slot }
            end
        end

        local sfxWas = GetCVar("Sound_EnableSFX")
        SetCVar("Sound_EnableSFX", "0")
        for _, m in ipairs(moves) do
            C_Container.PickupContainerItem(m[1], m[2])
            C_Container.PickupContainerItem(m[3], m[4])
            ClearCursor()
        end
        SetCVar("Sound_EnableSFX", sfxWas)

        C_Timer.After(0.5, function()
            EUI_Bags.refreshEnabled = true
            EUI_Bags:RefreshInventory()
            C_Timer.After(3, UnlockSort)
        end)
    end

    dice:SetScript("OnClick", function()
        if sortLocked then return end
        if EllesmereUIDB and EllesmereUIDB.bagRandomizeWarningDismissed then
            DoRandomize()
        else
            EUI:ShowConfirmPopup({
                title       = "Randomize Bags",
                message     = "This will physically scatter items to random positions in your bags. The changes persist even if you disable EllesmereUI Bags.",
                confirmText = "Randomize",
                cancelText  = "Cancel",
                checkbox    = "Don't show me again",
                onConfirm   = function(dontShowAgain)
                    if dontShowAgain then
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.bagRandomizeWarningDismissed = true
                    end
                    DoRandomize()
                end,
            })
        end
    end)
    dice:Hide()
    EUI_Bags._diceBtn = dice

    local bagsBtn = CreateFrame("Button", nil, header)
    bagsBtn:SetSize(24, 24)
    if sort:IsShown() then
        bagsBtn:SetPoint("RIGHT", sort, "LEFT", -6, 0)
    else
        bagsBtn:SetPoint("RIGHT", search, "LEFT", -13, 0)
    end
    bagsBtn.icon = bagsBtn:CreateTexture(nil, "ARTWORK")
    bagsBtn.icon:SetAllPoints()
    bagsBtn.icon:SetAtlas("bag-main")
    bagsBtn.icon:SetAlpha(0.9)

    bagsBtn:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if not EUI_BagsWindow:IsVisible() and EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, "Show Bags")
        end
    end)
    bagsBtn:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    bagsBtn:SetScript("OnClick", function()
        if EUI_BagsWindow:IsVisible() then
            EUI_BagsWindow:Hide()
        else
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            EUI_BagsWindow:Show()
            EUI_BagsWindow:RefreshBags()
        end
    end)
    EUI_Bags._bagsBtn = bagsBtn

    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(22, 22)
    clear:SetPoint("RIGHT", search, "RIGHT", 0, 0)
    clear.tex = clear:CreateFontString(nil, "OVERLAY")
    SetBagFont(clear.tex, 14)
    clear.tex:SetText("x")
    clear.tex:SetPoint("CENTER", 0, 1)
    clear.tex:SetTextColor(0.8, 0.8, 0.8)
    clear:Hide()
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus(); C_Container.SetItemSearch("") end)

    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        C_Container.SetItemSearch("")
    end)
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        placeholder:SetShown(text == "")
        clear:SetShown(text ~= "")
        C_Container.SetItemSearch(text)
        if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
        -- SetItemSearch is client-global and the bank reads isFiltered too:
        -- re-render an open bank so both windows always show the same filter
        -- state (the bank's box already mirrors this refresh toward bags).
        if EUI_Bank and EUI_Bank:IsVisible() and EUI_Bank.RefreshBank then
            EUI_Bank:RefreshBank()
        end
    end)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(12, 12)
    close:SetPoint("RIGHT", -9, 0)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
    close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function()
        EUI_Bags:Hide()
        EUI_BagsReagent:Hide()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.bagsVisible = false
    end)

    -- Bottom-edge separator (1px physical pixel)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local hdrSep = header:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(px)
    hdrSep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    hdrSep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    hdrSep:SetColorTexture(0.15, 0.15, 0.15, 1)

    EUI_Bags.Header = header
    EUI_Bags._bagsBtn = bagsBtn
end

-------------------------------------------------------------------------------
--  Gold tracking + Footer
-------------------------------------------------------------------------------
local lastCapturedGold = 0
local goldCapturePending = false
local lastCapturedWarbandGold = -1
local warbandGoldCapturePending = false

local function FormatNumberWithCommas(num)
    local str = tostring(math.floor(num))
    local result = ""
    local count = 0
    for i = #str, 1, -1 do
        if count > 0 and count % 3 == 0 then result = "," .. result end
        result = str:sub(i, i) .. result
        count = count + 1
    end
    return result
end

local function FormatGoldWithPadding(gold)
    local goldAmount = math.floor(gold / 10000)
    local silverAmount = math.floor((gold % 10000) / 100)
    local copperAmount = gold % 100
    local result = ""
    if goldAmount > 0 then
        result = FormatNumberWithCommas(goldAmount) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:17|t "
    end
    result = result .. string.format("%02d", silverAmount) .. "|TInterface\\MoneyFrame\\UI-SilverIcon:17|t "
    result = result .. string.format("%02d", copperAmount) .. "|TInterface\\MoneyFrame\\UI-CopperIcon:17|t"
    return result
end

local function FormatGoldOnly(gold)
    local goldAmount = math.floor(gold / 10000)
    return FormatNumberWithCommas(goldAmount) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:14|t"
end

local WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B = 1, 0.8, 0.5

local function UpdateBagMoneyDisplay()
    if not EUI_Bags.Money then return end
    MoneyFrame_UpdateMoney(EUI_Bags.Money)
    local goldBtn = _G["EUI_BagMoneyFrameGoldButton"]
    if goldBtn then
        local txt = goldBtn:GetFontString()
        if txt then
            txt:SetText(FormatNumberWithCommas(math.floor(GetMoney() / 10000)))
        end
    end
end

local function GetCharacterIdentifier()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function InitializeCharacterGold()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.characterGold then EllesmereUIDB.characterGold = {} end
end

local function ResetCurrentCharacterGold()
    if not EllesmereUIDB or not EllesmereUIDB.characterGold then return end
    local charID = GetCharacterIdentifier()
    EllesmereUIDB.characterGold[charID] = nil
end

local function CaptureCurrentCharacterGold()
    InitializeCharacterGold()
    local charID = GetCharacterIdentifier()
    local gold = GetMoney()
    if gold == lastCapturedGold then return end
    if goldCapturePending then return end
    lastCapturedGold = gold
    goldCapturePending = true
    C_Timer.After(0.5, function()
        local currentGold = GetMoney()
        local classColor = RAID_CLASS_COLORS[select(2, UnitClass("player"))] or { r=1, g=1, b=1 }
        EllesmereUIDB.characterGold[charID] = {
            gold = currentGold,
            lastUpdated = time(),
            class = select(2, UnitClass("player")),
            classColor = classColor,
        }
        lastCapturedGold = currentGold
        goldCapturePending = false
    end)
end

local function CaptureWarbandGold()
    if not C_Bank or not C_Bank.FetchDepositedMoney then return end
    InitializeCharacterGold()
    local gold = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    if gold == lastCapturedWarbandGold then return end
    if warbandGoldCapturePending then return end
    lastCapturedWarbandGold = gold
    warbandGoldCapturePending = true
    C_Timer.After(0.5, function()
        local currentGold = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
        EllesmereUIDB.warbandGold = {
            gold = currentGold,
            lastUpdated = time(),
        }
        lastCapturedWarbandGold = currentGold
        warbandGoldCapturePending = false
    end)
end

EUI_Bags.CaptureWarbandGold = CaptureWarbandGold

local function CaptureTrackedGold()
    if BP().enableGoldTracking == false then return end
    CaptureCurrentCharacterGold()
    CaptureWarbandGold()
end

local function ResetAllGoldData()
    if not EllesmereUIDB then return end
    EllesmereUIDB.characterGold = {}
    EllesmereUIDB.warbandGold = nil
    lastCapturedGold = -1
    lastCapturedWarbandGold = -1
    goldCapturePending = false
    warbandGoldCapturePending = false
    CaptureTrackedGold()
end

-------------------------------------------------------------------------------
--  Gold tooltip (custom multi-column, matches vault tooltip pattern)
-------------------------------------------------------------------------------
local _goldTT
local _goldTTRows = {}
local GOLD_COL_GAP = 20
local GOLD_ROW_H = 14
local GOLD_PAD = 8

local function GetGoldTooltip()
    if _goldTT then return _goldTT end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()

    local fadeInAG = f:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25); fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function() f:SetAlpha(1) end)
    f._fadeInAG = fadeInAG; f._fadeIn = fadeIn

    local fadeOutAG = f:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25); fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function() f:SetAlpha(0); f:Hide() end)
    f._fadeOutAG = fadeOutAG; f._fadeOut = fadeOut

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", f, "TOP", 0, -GOLD_PAD)
    title:SetText(EllesmereUI.L("Gold Summary"))
    f._title = title

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hint:SetTextColor(1, 0.4, 0.4, 1)
    hint:SetText(EllesmereUI.L("Ctrl + Right-Click: Reset all data"))
    f._hint = hint

    _goldTT = f
    return f
end

local function EnsureGoldRows(count)
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("bags")) or ""
    local tt = GetGoldTooltip()
    for i = 1, count do
        if not _goldTTRows[i] then
            _goldTTRows[i] = {}
            for col = 0, 1 do
                local fs = tt:CreateFontString(nil, "OVERLAY")
                fs:SetFont(fontPath, 11, fontFlags)
                fs:SetJustifyH(col == 0 and "LEFT" or "RIGHT")
                _goldTTRows[i][col] = fs
            end
        end
    end
    tt._title:SetFont(fontPath, 11, fontFlags)
    tt._hint:SetFont(fontPath, 10, fontFlags)
    for i = 1, count do
        for col = 0, 1 do
            _goldTTRows[i][col]:SetFont(fontPath, 11, fontFlags)
        end
    end
end

local function StripRealm(name)
    if not name then return "Unknown" end
    if Ambiguate then return Ambiguate(name, "short") or name end
    return name
end

local function ShowGoldTooltip(anchor)
    if not EllesmereUIDB then return end
    if BP().enableGoldTracking == false then return end

    local totalGold = 0
    local charList = {}
    if EllesmereUIDB.characterGold then
        for charID, data in pairs(EllesmereUIDB.characterGold) do
            charList[#charList + 1] = { id = charID, data = data }
            totalGold = totalGold + data.gold
        end
    end
    table.sort(charList, function(a, b) return a.id < b.id end)

    local warbandGold = EllesmereUIDB.warbandGold and EllesmereUIDB.warbandGold.gold
    if warbandGold then
        totalGold = totalGold + warbandGold
    end
    if #charList == 0 and not warbandGold then return end

    local rowCount = #charList + 1
    if warbandGold then rowCount = rowCount + 1 end
    EnsureGoldRows(rowCount)
    local tt = GetGoldTooltip()

    local colWidths = { 0, 0 }
    for r, entry in ipairs(charList) do
        local nameFS = _goldTTRows[r][0]
        local goldFS = _goldTTRows[r][1]
        local cc = entry.data.classColor or { r = 1, g = 1, b = 1 }
        local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
        nameFS:SetText("|cff" .. hex .. StripRealm(entry.id) .. "|r")
        goldFS:SetText(FormatGoldOnly(entry.data.gold))
        goldFS:SetTextColor(1, 1, 1, 1)
        nameFS:Show(); goldFS:Show()
        local nw = nameFS:GetStringWidth() or 0
        local gw = goldFS:GetStringWidth() or 0
        if nw > colWidths[1] then colWidths[1] = nw end
        if gw > colWidths[2] then colWidths[2] = gw end
    end

    local totalRow = #charList + 1
    if warbandGold then
        local nameFS = _goldTTRows[totalRow][0]
        local goldFS = _goldTTRows[totalRow][1]
        nameFS:SetText("|cffffcc80" .. EllesmereUI.L("Warbank") .. "|r")
        goldFS:SetText(FormatGoldOnly(warbandGold))
        goldFS:SetTextColor(WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B, 1)
        nameFS:Show(); goldFS:Show()
        local nw = nameFS:GetStringWidth() or 0
        local gw = goldFS:GetStringWidth() or 0
        if nw > colWidths[1] then colWidths[1] = nw end
        if gw > colWidths[2] then colWidths[2] = gw end
        totalRow = totalRow + 1
    end

    local totalNameFS = _goldTTRows[totalRow][0]
    local totalGoldFS = _goldTTRows[totalRow][1]
    totalNameFS:SetText("|cffffcc80" .. EllesmereUI.L("Total") .. "|r")
    totalGoldFS:SetText(FormatGoldOnly(totalGold))
    totalGoldFS:SetTextColor(1, 1, 0.5, 1)
    totalNameFS:Show(); totalGoldFS:Show()
    local tnw = totalNameFS:GetStringWidth() or 0
    local tgw = totalGoldFS:GetStringWidth() or 0
    if tnw > colWidths[1] then colWidths[1] = tnw end
    if tgw > colWidths[2] then colWidths[2] = tgw end

    for i = totalRow + 1, #_goldTTRows do
        _goldTTRows[i][0]:Hide()
        _goldTTRows[i][1]:Hide()
    end

    local titleTop = GOLD_PAD + (tt._title:GetStringHeight() or 14) + 6
    local col1X = GOLD_PAD
    local col2X = col1X + colWidths[1] + GOLD_COL_GAP
    local totalW = col2X + colWidths[2] + GOLD_PAD

    for r = 1, rowCount do
        local y = -(titleTop + (r - 1) * GOLD_ROW_H)
        -- Add gap before total row
        if r == totalRow then y = y - 4 end
        _goldTTRows[r][0]:ClearAllPoints()
        _goldTTRows[r][0]:SetPoint("TOPLEFT", tt, "TOPLEFT", col1X, y)
        _goldTTRows[r][1]:ClearAllPoints()
        _goldTTRows[r][1]:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -GOLD_PAD, y)
    end

    local lastRowY = titleTop + (rowCount - 1) * GOLD_ROW_H + 4 + GOLD_ROW_H + 6
    tt._hint:ClearAllPoints()
    tt._hint:SetPoint("TOPLEFT", tt, "TOPLEFT", GOLD_PAD, -lastRowY)
    local hintW = (tt._hint:GetStringWidth() or 0) + GOLD_PAD * 2
    if hintW > totalW then totalW = hintW end
    local totalH = lastRowY + (tt._hint:GetStringHeight() or 10) + GOLD_PAD

    tt:SetSize(totalW, totalH)
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)

    tt._fadeOutAG:Stop()
    tt._fadeInAG:Stop()
    tt:SetAlpha(0)
    tt:Show()
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeInAG:Play()
end

local function HideGoldTooltip()
    if not _goldTT or not _goldTT:IsShown() then return end
    _goldTT._fadeInAG:Stop()
    _goldTT._fadeOutAG:Stop()
    _goldTT._fadeOut:SetFromAlpha(_goldTT:GetAlpha())
    _goldTT._fadeOut:SetToAlpha(0)
    _goldTT._fadeOutAG:Play()
end

local function CreateFooter()
    if EUI_Bags.Footer then return end
    local footer = CreateFrame("Frame", nil, EUI_Bags)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    footer.bg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
    footer.bg:SetAllPoints()
    footer.bg:SetColorTexture(0, 0, 0, 0.35)

    -- Currency displays are created dynamically from Blizzard's tracked currencies
    if not EUI_Bags._currencyPool then
        EUI_Bags._currencyPool = { displays = {}, hitboxes = {} }
    end

    local money = CreateFrame("Frame", "EUI_BagMoneyFrame", footer, "SmallMoneyFrameTemplate")
    money:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 7)
    MoneyFrame_SetType(money, "PLAYER")

    for _, suffix in ipairs({"GoldButton", "SilverButton", "CopperButton"}) do
        local btn = _G["EUI_BagMoneyFrame" .. suffix]
        if btn then
            local txt = btn:GetFontString()
            if txt then SetBagFont(txt, 11) end
        end
    end

    -- Disable mouse on all SmallMoneyFrameTemplate children so our hitbox catches events
    for _, child in pairs({ money:GetChildren() }) do
        child:EnableMouse(false)
    end
    local moneyHitbox = CreateFrame("Frame", nil, footer)
    moneyHitbox:SetPoint("BOTTOMRIGHT", money, "BOTTOMRIGHT", 5, -5)
    moneyHitbox:SetPoint("TOPLEFT", money, "TOPLEFT", -5, 5)
    moneyHitbox:SetFrameLevel(money:GetFrameLevel() + 10)
    moneyHitbox:EnableMouse(true)

    moneyHitbox:SetScript("OnEnter", function(self) ShowGoldTooltip(self) end)
    moneyHitbox:SetScript("OnLeave", function() HideGoldTooltip() end)
    moneyHitbox:SetScript("OnMouseDown", function(self, button)
        if not EllesmereUIDB then return end
        if BP().enableGoldTracking == false then return end
        if button == "RightButton" and IsControlKeyDown() then
            ResetAllGoldData(); HideGoldTooltip(); return
        end
    end)

    -- Top-edge separator (1px physical pixel)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local ftrSep = footer:CreateTexture(nil, "ARTWORK")
    ftrSep:SetHeight(px)
    ftrSep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    ftrSep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    ftrSep:SetColorTexture(0.15, 0.15, 0.15, 1)

    EUI_Bags.Footer, EUI_Bags.Money = footer, money
end

local function UpdateCurrencyDisplays(footerWidth)
    local pool = EUI_Bags._currencyPool
    if not pool or not EUI_Bags.Footer then return FOOTER_H end
    local footer = EUI_Bags.Footer

    for _, d in ipairs(pool.displays) do d:Hide() end
    for _, h in ipairs(pool.hitboxes) do h:Hide() end

    -- Build tracked list from internal order table (decoupled from Blizzard)
    local tracked = {}
    local orderDB = CurrencyOrder()
    if orderDB and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for cID, order in pairs(orderDB) do
            if type(order) == "number" then
                tracked[#tracked + 1] = { currencyTypesID = cID, order = order }
            end
        end
        table.sort(tracked, function(a, b) return a.order < b.order end)
    end

    for i = #pool.displays + 1, #tracked do
        local display = footer:CreateFontString(nil, "OVERLAY")
        SetBagFont(display, 11)
        display:SetTextColor(1, 1, 1)
        pool.displays[i] = display

        local hb = CreateFrame("Frame", nil, footer)
        hb:SetFrameLevel(footer:GetFrameLevel() + 5)
        hb:EnableMouse(true)
        hb:SetScript("OnEnter", function(self)
            if self._currencyID and GameTooltip.SetCurrencyByID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetCurrencyByID(self._currencyID)
            end
        end)
        hb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        pool.hitboxes[i] = hb
    end

    local padding = 5
    local rowHeight = 14
    local rowGap = 8
    local bottomPad = 7
    local topPad = 7
    local leftOffset = 10
    local rightMargin = 180
    footerWidth = footerWidth or footer:GetWidth() or EUI_Bags:GetWidth() or 0
    if footerWidth <= 0 then footerWidth = EUI_Bags:GetWidth() or 400 end
    local availableWidth = math.max(40, footerWidth - leftOffset - rightMargin)
    local currentRow = 0
    local currentX = leftOffset
    local currencyLayout = {}

    for i, info in ipairs(tracked) do
        local display = pool.displays[i]
        local fullInfo = C_CurrencyInfo.GetCurrencyInfo(info.currencyTypesID)
        local icon = fullInfo and fullInfo.iconFileID or info.iconFileID
        local quantity = fullInfo and fullInfo.quantity or 0
        local discovered = fullInfo and fullInfo.discovered
        local name = fullInfo and fullInfo.name or ""
        if icon and (discovered ~= false) then
            display:SetText("|T" .. tostring(icon) .. ":17:17:0:0:64:64:5:59:5:59|t " .. quantity)
            local itemWidth = display:GetStringWidth() + padding
            if currentX + itemWidth > leftOffset + availableWidth and currentX > leftOffset then
                currentRow = currentRow + 1
                currentX = leftOffset
            end
            currencyLayout[#currencyLayout + 1] = {
                idx = i, row = currentRow, x = currentX, currencyID = info.currencyTypesID,
            }
            currentX = currentX + itemWidth
        end
    end

    local numRows = math.max(1, currentRow + 1)
    local footerHeight = math.max(
        FOOTER_H,
        bottomPad + topPad + numRows * rowHeight + math.max(0, numRows - 1) * rowGap
    )

    for _, layout in ipairs(currencyLayout) do
        local display = pool.displays[layout.idx]
        display:ClearAllPoints()
        local rowFromBottom = numRows - 1 - layout.row
        local yPos = bottomPad + rowFromBottom * (rowHeight + rowGap)
        display:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", layout.x, yPos)
        display:Show()

        local hb = pool.hitboxes[layout.idx]
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", display, "TOPLEFT", 0, 2)
        hb:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 0, -2)
        hb._currencyID = layout.currencyID
        hb:Show()
    end

    footer:SetHeight(footerHeight)
    EUI_Bags._footerH = footerHeight
    return footerHeight
end

-- Re-lay-out the currency footer and grow/shrink the bag frame by the height delta; reads the previous height BEFORE UpdateCurrencyDisplays stamps the new one.
local function SyncBagFrameToFooter()
    local prev = EUI_Bags._footerH or FOOTER_H
    local footerH = UpdateCurrencyDisplays() or FOOTER_H
    if footerH == prev then return end
    if not EUI_Bags:IsVisible() then return end
    local delta = footerH - prev
    if BP().bagAutoSize then
        EUI_Bags._asMaxH = math.max(EUI_Bags._asMaxH or EUI_Bags:GetHeight() or 0, EUI_Bags:GetHeight() + delta)
        EUI_Bags:SetHeight(EUI_Bags._asMaxH)
    else
        EUI_Bags:SetHeight(EUI_Bags:GetHeight() + delta)
    end
end

-------------------------------------------------------------------------------
--  Reagent Bag UI
-------------------------------------------------------------------------------
local function CreateReagentBagUI()
    if EUI_BagsReagent.Header then return end
    local header = CreateFrame("Frame", nil, EUI_BagsReagent)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(35)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0, 0, 0, 0.5)
    header.title = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.title, 13)
    header.title:SetPoint("LEFT", 15, 0)
    header.title:SetText(EllesmereUI.L("REAGENTS"))
    header.title:SetTextColor(1, 1, 1)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -5, 0)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
    close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() EUI_BagsReagent:Hide() end)
    EUI_BagsReagent.Header = header
    local footer = CreateFrame("Frame", nil, EUI_BagsReagent)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    EUI_BagsReagent.Footer = footer
end

-------------------------------------------------------------------------------
--  Inset border helper (1 physical pixel inside frame edge)
-------------------------------------------------------------------------------
local function CreateInsetBorder(btn)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local t = btn:CreateTexture(nil, "OVERLAY", nil, 2); t:SetTexture(WHITE)
    t:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    t:SetHeight(px)
    local b = btn:CreateTexture(nil, "OVERLAY", nil, 2); b:SetTexture(WHITE)
    b:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(px)
    local l = btn:CreateTexture(nil, "OVERLAY", nil, 2); l:SetTexture(WHITE)
    l:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    l:SetWidth(px)
    local r = btn:CreateTexture(nil, "OVERLAY", nil, 2); r:SetTexture(WHITE)
    r:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    r:SetWidth(px)
    btn._brdT, btn._brdB, btn._brdL, btn._brdR = t, b, l, r
end

local function SetInsetBorderColor(btn, cr, cg, cb, ca)
    if btn._brdT then
        btn._brdT:SetColorTexture(cr, cg, cb, ca)
        btn._brdB:SetColorTexture(cr, cg, cb, ca)
        btn._brdL:SetColorTexture(cr, cg, cb, ca)
        btn._brdR:SetColorTexture(cr, cg, cb, ca)
    end
end

-- Border thickness in px (1 normally, 2 for quest items); must be re-applied per render because item buttons are pooled.
local function SetInsetBorderThickness(btn, px)
    if btn._brdT then
        btn._brdT:SetHeight(px)
        btn._brdB:SetHeight(px)
        btn._brdL:SetWidth(px)
        btn._brdR:SetWidth(px)
    end
end

-- Gold border for quest items (overrides the normal quality border).
local QUEST_BORDER_COLOR = { r = 1.0, g = 0.82, b = 0.0 }

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
local function GetOrCreateSlot(idx)
    if itemSlots[idx] then return itemSlots[idx] end
    -- NEVER CreateFrame a secure ContainerFrameItemButtonTemplate in combat -- a button
    -- born in combat is tainted (UseContainerItem() -> ADDON_ACTION_FORBIDDEN in M+/Delves).
    -- Pre-warmed pool covers normal counts; past it, callers skip the slot until PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then return nil end

    local slotParent = CreateFrame("Frame", nil, EUI_Bags)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:HookScript("OnDragStart", function()
        _itemDragFrame:Show()
    end)

    -- Right-click deposit routing: with a bank tab selected, queue the transfer instead of
    -- Blizzard's default first-free-slot routing (queue handles locked items/allocation so rapid
    -- clicks don't collide). State lives in an EXTERNAL weak table, never on the frame: PreClick custom keys taint the secure chain -> ADDON_ACTION_FORBIDDEN.
    btn:HookScript("PreClick", function(self, button)
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
    end)
    btn:HookScript("OnClick", function(self, button)
        if button == "RightButton" and _bankRouted[self] then
            _bankRouted[self] = nil
            ClearCursor()
        end
    end)

    btn:HookScript("OnMouseUp", function(self, button)
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
        local cur = pinned[info.itemID] or 0
        if isGear then
            -- Gear: per-stack count toggle
            if cur > 0 then
                cur = cur - 1
                pinned[info.itemID] = cur > 0 and cur or nil
            else
                pinned[info.itemID] = cur + 1
            end
        else
            -- Non-gear: pin/unpin all stacks at once
            if cur > 0 then
                pinned[info.itemID] = nil
            else
                pinned[info.itemID] = 999
            end
        end
        if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
    end)

    -- Shift-click hint in category views: stacks auto-merge there, split in OneBag.
    btn:HookScript("PostClick", function(self, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        if not IsShiftKeyDown() then return end
        if selectedCategoryIndex == -1 or selectedCategoryIndex == -2 then return end
        if _anyItemPanelOpen or BP().bagMergeDuplicates == false then return end
        local bagID = self:GetParent():GetID()
        local slotID = self:GetID()
        if not bagID or not slotID or slotID == 0 then return end
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
        if not itemInfo or not itemInfo.stackCount or itemInfo.stackCount <= 1 then return end
        if not EUI.ShowWidgetTooltip then return end
        EUI.ShowWidgetTooltip(self,
            "Items in categories auto-merge,\nsplit stacks in OneBag", { anchor = "TOP", scale = 1.25 })
        if EUI_Bags._splitHintTimer then EUI_Bags._splitHintTimer:Cancel() end
        EUI_Bags._splitHintTimer = C_Timer.NewTimer(4, function()
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            EUI_Bags._splitHintTimer = nil
        end)
    end)

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

    -- Text overlay frame: sits above Cooldown so count/ilvl aren't covered by swipe
    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 2)
    btn._textOverlay = textOverlay

    local countSize = BP().bagCountFontSize or 11
    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        EllesmereUI.ApplyIconTextFont(countFS, GetFont(), countSize, "bags")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    local fontSize = BP().itemlevelFontSize or 12
    local fontPath = GetFont()
    btn.ItemLevelText:SetFont(fontPath, fontSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.ItemLevelText:SetText("")

    -- Keystone level text (top-left, same as item level)
    if not btn.KeystoneText then
        btn.KeystoneText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.KeystoneText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.KeystoneText:SetTextColor(1, 1, 1, 1)
    end
    btn.KeystoneText:SetFont(fontPath, countSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.KeystoneText:SetText("")
    -- Keystone dungeon abbreviation (bottom-right, same position as stack count)
    if not btn.KeystoneDungeonText then
        btn.KeystoneDungeonText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.KeystoneDungeonText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
        btn.KeystoneDungeonText:SetTextColor(1, 1, 1, 1)
        btn.KeystoneDungeonText:SetJustifyH("RIGHT")
    end
    btn.KeystoneDungeonText:SetFont(fontPath, math.max(countSize - 2, 7), (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.KeystoneDungeonText:SetText("")

    -- Bind Type text (bottom-left)
    if not btn.BindTypeText then
        btn.BindTypeText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.BindTypeText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 2)
        btn.BindTypeText:SetTextColor(1, 1, 1, 1)
    end
    local bindTypeFontSize = BP().bagBindTypeFontSize or 11
    btn.BindTypeText:SetFont(fontPath, bindTypeFontSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.BindTypeText:SetText("")

    -- Equipment set name FontString is lazy-created in RenderButton: never
    -- built while Show Set Name on Gear is off (zero cost disabled).

    itemSlots[idx] = btn
    return btn
end

local function GetOrCreateReagentSlot(idx)
    if reagentSlots[idx] then return reagentSlots[idx] end
    -- Never create a secure button during combat (taint). See GetOrCreateSlot.
    if InCombatLockdown() then return nil end

    local slotParent = CreateFrame("Frame", nil, EUI_BagsReagent)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
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

    -- Text overlay frame: sits above Cooldown so count/ilvl aren't covered by swipe
    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 2)
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
    btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, fontSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    btn.ItemLevelText:SetText("")

    reagentSlots[idx] = btn
    return btn
end

local function GetOrCreateBagSlot(idx)
    if bagSlots[idx] then return bagSlots[idx] end
    local slotParent = CreateFrame("Frame", nil, EUI_BagsWindow)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("Button", nil, slotParent)
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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

    -- Drag-and-drop: equip a bag into this slot
    local function TrySwapBag(self)
        if InCombatLockdown() then return end
        if not CursorHasItem() then return end
        local bagID = self:GetID()
        if bagID == 0 then return end  -- can't replace backpack
        local invID = C_Container.ContainerIDToInventoryID(bagID)
        PickupInventoryItem(invID)
        EUI_Bags._pendingBagSwap = true
    end
    btn:SetScript("OnReceiveDrag", TrySwapBag)
    btn:HookScript("OnClick", TrySwapBag)

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
        if btn.ItemLevelText then btn.ItemLevelText:SetFont(fontPath, ilvlSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.KeystoneText then btn.KeystoneText:SetFont(fontPath, countSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.KeystoneDungeonText then btn.KeystoneDungeonText:SetFont(fontPath, math.max(countSize - 2, 7), (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.BindTypeText then btn.BindTypeText:SetFont(fontPath, bindTypeSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
        if btn.SetNameText then btn.SetNameText:SetFont(fontPath, BP().bagSetNameFontSize or 9, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
    end
    for _, btn in pairs(reagentSlots) do
        if btn.Count then EllesmereUI.ApplyIconTextFont(btn.Count, fontPath, countSize, "bags") end
        if btn.ItemLevelText then btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, ilvlSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG") end
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
-- WuE items report bindType == OnEquip (no dedicated enum): check WuE first.
function EUI_Bags.SetBindTypeText(fs, isWuE, bindType, quality)
    local c
    if isWuE then
        c = ITEM_QUALITY_COLORS[7] -- Heirloom color (no quality enum for WuE)
        fs:SetText(EllesmereUI.L("WuE"))
    elseif bindType == Enum.ItemBind.OnEquip then
        c = ITEM_QUALITY_COLORS[quality]
        fs:SetText(EllesmereUI.L("BoE"))
    else
        fs:SetText("")
        return
    end
    if c then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(1, 1, 1) end
end

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

        -- Desature: 1) locked items 2) junk items if option is active
        local quality = data.info.quality or 1
        local isJunk = BP().bagDesaturateJunkItems and quality == 0
        SetItemButtonDesaturated(btn, data.info.isLocked or isJunk)

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
                    elseif rankText ~= "" and trackColor then
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
                    btn.SetNameText:SetFont(GetFont(), BP().bagSetNameFontSize or 9, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
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
end

-------------------------------------------------------------------------------
--  Pin Selection Mode
-------------------------------------------------------------------------------
local EnterPinSelectMode  -- forward declaration
local ExitPinSelectMode   -- forward declaration
local EnterAssignSelectMode  -- forward declaration

-- Pin "+" overlay: a click-catcher frame placed over a regular empty slot
local function GetOrCreatePinOverlay()
    if EUI_Bags._pinOverlayBtn then return EUI_Bags._pinOverlayBtn end
    local ov = CreateFrame("Button", nil, EUI_Bags)
    ov:SetSize(SLOT_SIZE, SLOT_SIZE)
    ov:SetFrameLevel(100)
    ov.bg = ov:CreateTexture(nil, "BACKGROUND")
    ov.bg:SetAllPoints()
    ov.bg:SetColorTexture(0, 0, 0, 0.4)
    ov.plus = ov:CreateFontString(nil, "OVERLAY")
    ov.plus:SetFont(GetFont(), 18, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    ov.plus:SetPoint("CENTER", 0, 0)
    ov.plus:SetText("+")
    ov.plus:SetTextColor(1, 1, 1, 0.5)
    ov:SetScript("OnEnter", function(self)
        self.plus:SetTextColor(1, 1, 1, 1)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Pin an Item") end
    end)
    ov:SetScript("OnLeave", function(self)
        self.plus:SetTextColor(1, 1, 1, 0.5)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    ov:RegisterForDrag("LeftButton")
    ov:SetScript("OnReceiveDrag", function()
        local cursorType, itemID = GetCursorInfo()
        if cursorType == "item" and itemID then
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
            local pinned = EllesmereUIDB.bagPinnedItems
            if not pinned[itemID] or pinned[itemID] == 0 then
                local itemLink = select(2, GetCursorInfo())
                pinned[itemID] = IsGearItem(itemLink) and 1 or 999
            end
            ClearCursor()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
        end
    end)
    ov:SetScript("OnClick", function()
        local cursorType, itemID = GetCursorInfo()
        if cursorType == "item" and itemID then
            -- Click-to-place also pins
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
            local pinned = EllesmereUIDB.bagPinnedItems
            if not pinned[itemID] or pinned[itemID] == 0 then
                local itemLink = select(2, GetCursorInfo())
                pinned[itemID] = IsGearItem(itemLink) and 1 or 999
            end
            ClearCursor()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
            return
        end
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        EnterPinSelectMode()
    end)
    ov:Hide()
    EUI_Bags._pinOverlayBtn = ov
    return ov
end

-- Assign "+" overlay: click/drag an item to assign to a category; pooled so multiple sections can show one simultaneously.
local _assignOverlays = {}
local _assignOverlayIdx = 0

local function GetOrCreateAssignOverlay()
    _assignOverlayIdx = _assignOverlayIdx + 1
    if _assignOverlays[_assignOverlayIdx] then return _assignOverlays[_assignOverlayIdx] end
    local ov = CreateFrame("Button", nil, EUI_Bags)
    ov:SetSize(SLOT_SIZE, SLOT_SIZE)
    ov:SetFrameLevel(100)
    ov.bg = ov:CreateTexture(nil, "BACKGROUND")
    ov.bg:SetAllPoints()
    ov.bg:SetColorTexture(0, 0, 0, 0.4)
    ov.plus = ov:CreateFontString(nil, "OVERLAY")
    ov.plus:SetFont(GetFont(), 18, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    ov.plus:SetPoint("CENTER", 0, 0)
    ov.plus:SetText("+")
    ov.plus:SetTextColor(1, 1, 1, 0.5)
    ov:SetScript("OnEnter", function(self)
        self.plus:SetTextColor(1, 1, 1, 1)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Assign an item to this category") end
    end)
    ov:SetScript("OnLeave", function(self)
        self.plus:SetTextColor(1, 1, 1, 0.5)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    local function DoAssign(self)
        local cursorType, itemID = GetCursorInfo()
        if cursorType == "item" and itemID and self._assignCatKey then
            EUI_CategoryManager:AssignItem(itemID, self._assignCatKey)
            ClearCursor()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
            return
        end
        -- No cursor item: enter assign select mode (like pin select)
        if self._assignCatKey then
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            EnterAssignSelectMode(self._assignCatKey)
        end
    end
    ov:RegisterForDrag("LeftButton")
    ov:SetScript("OnReceiveDrag", DoAssign)
    ov:SetScript("OnClick", DoAssign)
    ov:Hide()
    _assignOverlays[_assignOverlayIdx] = ov
    return ov
end

local function ResetAssignOverlays()
    for i = 1, _assignOverlayIdx do
        _assignOverlays[i]:Hide()
    end
    _assignOverlayIdx = 0
end

ExitPinSelectMode = function()
    EUI_Bags._pinSelectMode = false
    if EUI_Bags._pinCatcher then EUI_Bags._pinCatcher:Hide() end
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
    if sf then sf:SetFrameStrata("HIGH") end
end

-------------------------------------------------------------------------------
--  Assign Selection Mode: dim the screen, click an item to assign it to a category (mirrors Pin Selection Mode).
-------------------------------------------------------------------------------
local _assignSelectCatKey = nil

local function ExitAssignSelectMode()
    EUI_Bags._assignSelectMode = false
    _assignSelectCatKey = nil
    if EUI_Bags._assignCatcher then EUI_Bags._assignCatcher:Hide() end
    local ov = EUI_Bags._assignOverlay
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
    if sf then sf:SetFrameStrata("HIGH") end
end

EnterAssignSelectMode = function(catKey)
    EUI_Bags._assignSelectMode = true
    _assignSelectCatKey = catKey

    if not EUI_Bags._assignOverlay then
        local ov = CreateFrame("Frame", nil, UIParent)
        ov:SetFrameStrata("FULLSCREEN_DIALOG")
        ov:SetFrameLevel(0)
        ov:SetAllPoints(UIParent)
        ov:EnableMouse(true)
        ov.bg = ov:CreateTexture(nil, "BACKGROUND")
        ov.bg:SetAllPoints()
        ov.bg:SetColorTexture(0, 0, 0, 0.6)
        ov:SetScript("OnMouseDown", function() ExitAssignSelectMode() end)
        ov:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                ExitAssignSelectMode()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        EUI_Bags._assignOverlay = ov
    end
    local ov = EUI_Bags._assignOverlay
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

    local function FindBtnUnderCursor()
        -- Cursor / each button's OWN effective scale: GetRect() is in button units
        local rawCx, rawCy = GetCursorPosition()
        for _, btn in pairs(itemSlots) do
            if btn:IsShown() and btn:GetParent():IsShown() then
                local es = btn:GetEffectiveScale()
                local cx, cy = rawCx / es, rawCy / es
                local l, b, w, h = btn:GetRect()
                if l and b and w and h and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                    return btn
                end
            end
        end
        return nil
    end

    -- Click catcher with hover highlight
    if not EUI_Bags._assignCatcher then
        local cf = CreateFrame("Frame", nil, UIParent)
        cf:SetFrameStrata("FULLSCREEN_DIALOG")
        cf:SetFrameLevel(500)
        cf:EnableMouse(true)

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

        cf:SetScript("OnUpdate", function()
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
            local btn = FindBtnUnderCursor()
            if btn then
                local bagID = btn:GetParent():GetID()
                local slotID = btn:GetID()
                if bagID and slotID and slotID > 0 then
                    local info = C_Container.GetContainerItemInfo(bagID, slotID)
                    if info and info.itemID and _assignSelectCatKey then
                        EUI_CategoryManager:AssignItem(info.itemID, _assignSelectCatKey)
                        ClearHover()
                        ExitAssignSelectMode()
                        EUI_Bags:RefreshInventory()
                        return
                    end
                end
            end
            ClearHover()
            ExitAssignSelectMode()
        end)

        cf:SetAllPoints(UIParent)
        cf:Hide()
        EUI_Bags._assignCatcher = cf
    end
    EUI_Bags._assignCatcher:Show()
end

EnterPinSelectMode = function()
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
        ov:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                ExitPinSelectMode()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        EUI_Bags._pinOverlay = ov
    end
    local ov = EUI_Bags._pinOverlay
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

    local function FindBtnUnderCursor()
        -- Cursor / each button's OWN effective scale: GetRect() is in button units
        local rawCx, rawCy = GetCursorPosition()
        for _, btn in pairs(itemSlots) do
            if btn:IsShown() and btn:GetParent():IsShown() then
                local es = btn:GetEffectiveScale()
                local cx, cy = rawCx / es, rawCy / es
                local l, b, w, h = btn:GetRect()
                if l and b and w and h and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                    return btn
                end
            end
        end
        return nil
    end

    -- Click catcher above the raised icons: swallows clicks (items aren't used/equipped), then pins whichever icon was clicked.
    if not EUI_Bags._pinCatcher then
        local cf = CreateFrame("Frame", nil, UIParent)
        cf:SetFrameStrata("FULLSCREEN_DIALOG")
        cf:SetFrameLevel(500)
        cf:EnableMouse(true)

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

        cf:SetScript("OnUpdate", function()
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
                        EllesmereUIDB.bagPinnedItems[info.itemID] = (EllesmereUIDB.bagPinnedItems[info.itemID] or 0) + 1
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
    if sf then
        local l, b, w, h = sf:GetRect()
        if l and b and w and h then
            EUI_Bags._pinCatcher:ClearAllPoints()
            EUI_Bags._pinCatcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
            EUI_Bags._pinCatcher:SetSize(w, h)
        end
    end
    EUI_Bags._pinCatcher:Show()
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local _sidebarBtns = {}  -- array of sidebar button frames

local function GetSidebarWidth()
    local collapsed = BP().bagSidebarCollapsed
    return collapsed and SIDEBAR_W_COLLAPSED or SIDEBAR_W_EXPANDED
end

-------------------------------------------------------------------------------
--  Sidebar drag-to-reorder (iOS-style: ghost + insert line + source fade)
-------------------------------------------------------------------------------
local _dragGhost         -- floating ghost frame (scaled 0.5x, 70% opacity)
local _dragFromCatIdx    -- category index being dragged (1-based into bagCategoryDefs)
local _dragSourceBtn     -- the button frame being dragged (to restore alpha)
local _dragInsertLine    -- accent-colored insertion line
local _dragGroupHL       -- accent-colored group highlight overlay
local _dragLastTarget    -- last computed insert target (avoid redundant updates)
local _dragLastMode      -- "above", "below", "group"
local _dragLastBtn       -- last target button (avoid redundant updates)
local _dragDropMode      -- current drop mode for StopSidebarDrag
local _dragDropTarget    -- current drop target catIdx
local _dragTargetIsHeader -- true when resolved target came from a group header button
local _dragInsertGroup    -- group name when insert position is inside a group

local function EnsureDragGhost()
    if _dragGhost then return _dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(SIDEBAR_W_EXPANDED, SIDEBAR_BTN_H)
    g:SetAlpha(0.7)
    g:SetScale(0.5)
    g:EnableMouse(false)
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    g.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
    g.icon:SetPoint("LEFT", 8, 0)
    g.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    g.label = g:CreateFontString(nil, "OVERLAY")
    SetBagFont(g.label, 11)
    g.label:SetPoint("LEFT", g.icon, "RIGHT", 6, 0)
    g.label:SetTextColor(1, 1, 1)
    g:Hide()
    _dragGhost = g
    return g
end

local function EnsureInsertLine()
    if _dragInsertLine then return _dragInsertLine end
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local eg = EUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    local line = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
    line:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    line:SetHeight(px * 2)
    line:Hide()
    _dragInsertLine = line
    return line
end

local function EnsureGroupHighlight()
    if _dragGroupHL then return _dragGroupHL end
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local eg = EUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    local hl = CreateFrame("Frame", nil, sidebar)
    hl:SetFrameLevel(sidebar:GetFrameLevel() + 10)
    hl.bg = hl:CreateTexture(nil, "OVERLAY", nil, 6)
    hl.bg:SetAllPoints()
    hl.bg:SetColorTexture(eg.r, eg.g, eg.b, 0.15)
    -- Accent border
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local function MakeLine(point1, rel1, point2, rel2, w, h)
        local t = hl:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(eg.r, eg.g, eg.b, 0.6)
        t:SetPoint(point1, hl, rel1, 0, 0)
        t:SetPoint(point2, hl, rel2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    MakeLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, px)
    MakeLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, px)
    MakeLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", px, nil)
    MakeLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", px, nil)
    hl:Hide()
    _dragGroupHL = hl
    return hl
end

-- Compute insert position from cursor Y relative to visible sidebar buttons (skips hidden/empty categories).
local function ComputeDropTarget()
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local scale = sidebar:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local sidebarTop = sidebar:GetTop() * scale
    local localY = (sidebarTop - cy) / scale

    -- Offset past sidebar header + "All Items" + "OneBag" + "MultiBag" buttons
    localY = localY - 24 - 3 * (SIDEBAR_BTN_H + SIDEBAR_PAD)

    if localY < 0 then return 1 end

    -- Walk visible category buttons to find which slot the cursor is over
    local cats = EUI_CategoryManager:GetCategories()
    local visIdx = 0
    local lastVisibleCatIdx = 1
    for i = 1, #cats do
        local isVisible = false
        for _, btn in ipairs(_sidebarBtns) do
            if btn:IsShown() and btn._catIdx == i then
                isVisible = true
                break
            end
        end
        if isVisible then
            visIdx = visIdx + 1
            lastVisibleCatIdx = i
            local slotTop = (visIdx - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD)
            local slotMid = slotTop + (SIDEBAR_BTN_H + SIDEBAR_PAD) / 2
            if localY < slotMid then return i end
        end
    end
    return lastVisibleCatIdx
end

-- Compute drop zone: which button the cursor is over and which zone (above/group/below).
-- Returns: targetCatIdx, mode ("above", "below", "group"), targetBtn
local function ComputeDropZone()
    -- Sidebar buttons carry the sidebar's effective scale, so divide the cursor by that
    -- (not UIParent's) to match btn:GetTop()/GetBottom() -- UIParent math picks the wrong row at scale != 100%. Mirrors ComputeDropTarget above.
    local sidebar = EUI_Bags._sidebar
    local scale = (sidebar and sidebar:GetEffectiveScale()) or UIParent:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local cursorY = cy / scale

    local GROUP_ZONE = 4  -- pixels from center that count as "group" zone

    -- Walk visible sidebar buttons to find which one cursor is over
    for _, btn in ipairs(_sidebarBtns) do
        if btn:IsShown() and btn._catIdx and btn._catIdx > 0 then
            local top = btn:GetTop()
            local bot = btn:GetBottom()
            if top and bot and cursorY <= top and cursorY >= bot then
                local mid = (top + bot) / 2
                local distFromMid = math.abs(cursorY - mid)
                if distFromMid <= GROUP_ZONE then
                    return btn._catIdx, "group", btn
                elseif cursorY > mid then
                    return btn._catIdx, "above", btn
                else
                    return btn._catIdx, "below", btn
                end
            end
        end
    end
    -- Fallback: find nearest category button by Y distance
    local bestIdx, bestDist, bestBtn, bestMode = 1, math.huge, nil, "above"
    for _, btn in ipairs(_sidebarBtns) do
        if btn:IsShown() and btn._catIdx and btn._catIdx > 0 then
            local top = btn:GetTop()
            local bot = btn:GetBottom()
            if top and bot then
                local mid = (top + bot) / 2
                local dist = math.abs(cursorY - mid)
                if dist < bestDist then
                    bestDist = dist
                    bestIdx = btn._catIdx
                    bestBtn = btn
                    bestMode = cursorY > mid and "above" or "below"
                end
            end
        end
    end
    return bestIdx, bestMode, bestBtn
end

-- Compute insert line Y position for a given category target index
local function GetInsertLineY(targetCatIdx)
    -- Offset: header (24) + 3 fixed buttons (All Items + OneBag + MultiBag)
    local topOffset = 24 + 3 * (SIDEBAR_BTN_H + SIDEBAR_PAD)
    local visSlot = 0
    local cats = EUI_CategoryManager:GetCategories()
    for i = 1, #cats do
        local isVisible = false
        for _, btn in ipairs(_sidebarBtns) do
            if btn:IsShown() and btn._catIdx == i then
                isVisible = true
                break
            end
        end
        if isVisible then
            visSlot = visSlot + 1
            if i == targetCatIdx then
                return -topOffset - ((visSlot - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD))
            end
        end
    end
    return -topOffset - (visSlot * (SIDEBAR_BTN_H + SIDEBAR_PAD))
end

local StartSidebarDrag  -- forward declaration (defined below)

-- Shared drag-detect frame for sidebar buttons (hidden when not dragging)
local _sidebarDragDetect = CreateFrame("Frame")
_sidebarDragDetect:Hide()
_sidebarDragDetect._btn = nil
_sidebarDragDetect:SetScript("OnUpdate", function(self)
    local btn = self._btn
    if not btn or not btn._dragPending then self:Hide(); return end
    local _, cy = GetCursorPosition()
    if math.abs(cy - (btn._dragStartY or cy)) > 4 then
        btn._dragPending = false
        btn._didDrag = true
        self:Hide()
        StartSidebarDrag(btn, btn._catIdx, btn._catName, btn._catIcon, btn._catIsAtlas)
    end
end)

local _dragUpdateFrame = CreateFrame("Frame")
_dragUpdateFrame:Hide()
_dragUpdateFrame:SetScript("OnUpdate", function()
    if not _dragFromCatIdx then _dragUpdateFrame:Hide(); return end

    local ghost = _dragGhost
    if ghost and ghost:IsShown() then
        local cx, cy = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        local gs = ghost:GetScale() or 1
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / (sc * gs), cy / (sc * gs))
    end

    local target, mode, targetBtn = ComputeDropZone()

    if target ~= _dragLastTarget or mode ~= _dragLastMode or targetBtn ~= _dragLastBtn then
        _dragLastTarget = target
        _dragLastMode = mode
        _dragLastBtn = targetBtn
        local line = EnsureInsertLine()
        local hl = EnsureGroupHighlight()

        -- Don't group with self
        if mode == "group" and target == _dragFromCatIdx then mode = "above" end

        local cats = EUI_CategoryManager:GetCategories()

        -- Block drops onto/above special entries (Pinned Items, Recent Items) -- nothing drags above the divider.
        local targetCatCheck = cats[target]
        if targetCatCheck and (targetCatCheck.isPinned or targetCatCheck.isRecent) then
            line:Hide(); hl:Hide()
            _dragDropMode = nil; _dragDropTarget = nil
            return
        end
        -- Can't group with or from a noGroup category (e.g. Reagent Bag)
        if mode == "group" and cats[target] and cats[target].noGroup then mode = "below" end
        if mode == "group" and cats[_dragFromCatIdx] and cats[_dragFromCatIdx].noGroup then mode = "above" end

        local fromCat = cats[_dragFromCatIdx]
        local targetCat = cats[target]
        -- Can't group with a grouped member (but CAN group with a group header to join that group)
        if mode == "group" and targetCat and targetCat.groupName and not (targetBtn and targetBtn._isGroupHeader) then
            mode = "above"
        end
        -- Can't group something already in a group with an ungrouped category (would nest groups)
        if mode == "group" and fromCat and fromCat.groupName and not (targetBtn and targetBtn._isGroupHeader) then
            mode = "above"
        end

        if mode == "group" and targetBtn then
            if line then line:Hide() end
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", targetBtn, "TOPLEFT", 2, 0)
            hl:SetPoint("BOTTOMRIGHT", targetBtn, "BOTTOMRIGHT", -2, 0)
            hl:Show()
            _dragDropMode = "group"
            _dragDropTarget = target
        else
            if hl then hl:Hide() end
            _dragDropMode = "insert"

            -- Resolve actual target index: "above N" = N, "below N" = N+1
            -- Exception: "below header" = same gap as "above first member" = N (not N+1)
            local resolvedTarget = target
            if mode == "below" then
                if targetBtn and targetBtn._isGroupHeader then
                    resolvedTarget = target
                else
                    resolvedTarget = target + 1
                end
            end

            -- Set children are a contiguous runtime block re-anchored on rebuild:
            -- an insert between them would not actually land there, so suppress
            -- the line instead of promising a position the drop can't keep.
            if targetBtn and targetBtn._isEquipSet then
                if line then line:Hide() end
                _dragDropTarget = nil
                _dragInsertGroup = nil
                return
            end

            -- Determine if insert position is inside a group
            local insideGroup = nil
            local fromNoGroup = cats[_dragFromCatIdx] and cats[_dragFromCatIdx].noGroup
            local posInGroup = targetBtn and targetCat and targetCat.groupName
                and (targetBtn._isGroupMember or (targetBtn._isGroupHeader and mode == "below"))
            if posInGroup then
                if fromNoGroup then
                    -- noGroup categories can't enter groups; suppress line entirely
                    if line then line:Hide() end
                    _dragDropTarget = nil
                    _dragInsertGroup = nil
                    return
                end
                insideGroup = targetCat.groupName
            end

            -- No-op check: skip if same position AND group membership isn't changing
            local fromCatGroup = cats[_dragFromCatIdx] and cats[_dragFromCatIdx].groupName
            local groupChanges = (insideGroup or false) ~= (fromCatGroup or false)
            local isNoOp = not groupChanges
                and (resolvedTarget == _dragFromCatIdx or resolvedTarget == _dragFromCatIdx + 1)

            if isNoOp then
                if line then line:Hide() end
                _dragDropTarget = nil
                _dragInsertGroup = nil
            else
                _dragDropTarget = resolvedTarget
                _dragTargetIsHeader = targetBtn and targetBtn._isGroupHeader or false
                _dragInsertGroup = insideGroup

                if target and line then
                    -- Position line in the gap between buttons (centered in SIDEBAR_PAD)
                    local gapOff = math.floor(SIDEBAR_PAD / 2)
                    local leftOff = insideGroup and (4 + SIDEBAR_INDENT) or 4
                    if mode == "below" and targetBtn then
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", targetBtn, "BOTTOMLEFT", leftOff, -gapOff)
                        line:SetPoint("TOPRIGHT", targetBtn, "BOTTOMRIGHT", -4, -gapOff)
                    elseif targetBtn then
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", targetBtn, "TOPLEFT", leftOff, gapOff)
                        line:SetPoint("TOPRIGHT", targetBtn, "TOPRIGHT", -4, gapOff)
                    else
                        local sidebar = EUI_Bags._sidebar
                        local lineY = GetInsertLineY(target)
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", sidebar, "TOPLEFT", leftOff, lineY)
                        line:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, lineY)
                    end
                    line:Show()
                end
            end
        end
    end
end)

StartSidebarDrag = function(btnSelf, catIdx, catName, catIcon, catIsAtlas)
    _dragFromCatIdx = catIdx
    _dragSourceBtn = btnSelf
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil

    local ghost = EnsureDragGhost()
    ghost:SetSize(GetSidebarWidth(), SIDEBAR_BTN_H)
    if catIsAtlas then
        ghost.icon:SetAtlas(catIcon or "")
        ghost.icon:SetTexCoord(0, 1, 0, 1)
    else
        ghost.icon:SetTexture(catIcon or 134400)
        ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    ghost.label:SetText(catName or "?")
    local collapsed = BP().bagSidebarCollapsed
    if collapsed then ghost.label:Hide() else ghost.label:Show() end
    ghost:Show()

    -- Source button: fade to 30% (iOS lift effect)
    btnSelf:SetAlpha(0.3)

    EnsureInsertLine()
    _dragUpdateFrame:Show()
end

local function StopSidebarDrag()
    if not _dragFromCatIdx then return end

    if _dragSourceBtn then _dragSourceBtn:SetAlpha(1) end

    -- Capture selected category by reference so we can re-find its index after reorder
    local cats = EUI_CategoryManager:GetCategories()
    local selectedCatRef = (selectedCategoryIndex > 0) and cats[selectedCategoryIndex] or nil
    local savedGroupName = selectedGroupName

    local fromCat = cats[_dragFromCatIdx]
    local fromGroup = fromCat and fromCat.groupName
    local isHeader = _dragSourceBtn and _dragSourceBtn._isGroupHeader
    local dropMode = _dragDropMode
    local dropTarget = _dragDropTarget

    if dropMode == "group" and dropTarget and dropTarget ~= _dragFromCatIdx then
        -- GROUP MODE: merge dragged category with target
        local targetCat = cats[dropTarget]
        local targetGroup = targetCat and targetCat.groupName

        if targetCat then
            -- Group-to-group is always allowed (old group may disband, that's fine)
            if fromGroup then
                EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                ClearGroupOrder(fromGroup)
            end

            if targetGroup then
                -- Move to bottom of group
                local groupMembers = EUI_CategoryManager:GetGroupMembers(targetGroup)
                local lastMemberIdx = groupMembers[#groupMembers]
                local curFromIdx
                for i, cat in ipairs(cats) do
                    if cat == fromCat then curFromIdx = i; break end
                end
                if curFromIdx and lastMemberIdx then
                    local dest = lastMemberIdx + 1
                    if dest > #cats + 1 then dest = #cats + 1 end
                    if curFromIdx ~= dest then
                        EUI_CategoryManager:ReorderCategory(curFromIdx, dest)
                    end
                end
                -- Add to group (already in position); re-find index after the move
                for i, cat in ipairs(cats) do
                    if cat == fromCat then
                        EUI_CategoryManager:AddToGroup(i, targetGroup)
                        break
                    end
                end
            else
                -- Create new group: move dragged category to right after target first
                local curFromIdx
                for i, cat in ipairs(cats) do
                    if cat == fromCat then curFromIdx = i; break end
                end
                local curTargetIdx
                for i, cat in ipairs(cats) do
                    if cat == targetCat then curTargetIdx = i; break end
                end
                if curFromIdx and curTargetIdx and curFromIdx ~= curTargetIdx then
                    -- Place after target so target stays first in the new group
                    local dest = curTargetIdx + 1
                    if dest > #cats then dest = #cats end
                    EUI_CategoryManager:ReorderCategory(curFromIdx, dest)
                end
                -- Re-find indices after move
                local idx1, idx2
                for i, cat in ipairs(cats) do
                    if cat == targetCat then idx1 = i end
                    if cat == fromCat then idx2 = i end
                end
                if idx1 and idx2 then
                    EUI_CategoryManager:GroupCategories({ idx1, idx2 })
                end
            end
        end
    elseif dropMode == "insert" and dropTarget then
        local target = dropTarget

        local fromGroupName = fromCat and fromCat.groupName
        local dropGroupChanges = (_dragInsertGroup or false) ~= (fromGroupName or false)
        if target ~= _dragFromCatIdx or dropGroupChanges then
            if isHeader and fromGroup then
                -- Group header drag: move ALL members as a block, using raw dropTarget (not the -1 adjusted target).
                local rawTarget = dropTarget
                local members = EUI_CategoryManager:GetGroupMembers(fromGroup)
                local minIdx = members[1]
                local blockSize = #members
                if rawTarget < minIdx or rawTarget > minIdx + blockSize - 1 then
                    local removed = {}
                    for m = #members, 1, -1 do
                        removed[#removed + 1] = table.remove(cats, members[m])
                    end
                    local ordered = {}
                    for r = #removed, 1, -1 do ordered[#ordered + 1] = removed[r] end
                    local insertAt
                    if rawTarget > minIdx then
                        insertAt = rawTarget - blockSize
                    else
                        insertAt = rawTarget
                    end
                    if insertAt < 1 then insertAt = 1 end
                    if insertAt > #cats + 1 then insertAt = #cats + 1 end
                    for b = #ordered, 1, -1 do
                        table.insert(cats, insertAt, ordered[b])
                    end
                    -- Persist the block move; without this it reverts on the next
                    -- rebuild (equip-set groups rebuild on every set change).
                    EUI_CategoryManager:SaveState()
                end
            elseif fromGroup then
                -- Grouped member dragged to insert position
                local members = EUI_CategoryManager:GetGroupMembers(fromGroup)
                local minIdx, maxIdx = members[1], members[#members]

                local inGroup = (_dragInsertGroup == fromGroup)
                    or (not _dragInsertGroup and target >= minIdx and target <= maxIdx)
                if inGroup and target ~= _dragFromCatIdx then
                    -- Check if trying to move above the group (target == minIdx from the header button, not the first member)
                    if target == minIdx and _dragFromCatIdx ~= minIdx and #members >= 2 and _dragTargetIsHeader then
                        -- Ungroup and place above the group
                        EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(fromGroup)
                        local newIdx
                        for i, cat in ipairs(cats) do
                            if cat == fromCat then newIdx = i; break end
                        end
                        if newIdx then
                            EUI_CategoryManager:ReorderCategory(newIdx, minIdx)
                        end
                    else
                        -- Normal intra-group reorder
                        EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                    end
                    if not EUI_CategoryManager:IsGroupNameCustom(fromGroup) then
                        EUI_CategoryManager:RegenerateGroupName(fromGroup)
                    end
                else
                    -- Drag out of group
                    if #members >= 1 then
                        EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(fromGroup)
                        -- Re-find index after ungroup may have shifted things
                        local newIdx
                        for i, cat in ipairs(cats) do
                            if cat == fromCat then newIdx = i; break end
                        end
                        if newIdx then
                            -- Check if destination is inside another group -- auto-join it
                            local destGroup = _dragInsertGroup
                            if destGroup == fromGroup then destGroup = nil end
                            if destGroup then
                                EUI_CategoryManager:ReorderCategory(newIdx, target)
                                -- Re-find after move
                                for i, cat in ipairs(cats) do
                                    if cat == fromCat then
                                        EUI_CategoryManager:AddToGroup(i, destGroup)
                                        break
                                    end
                                end
                                if not EUI_CategoryManager:IsGroupNameCustom(destGroup) then
                                    EUI_CategoryManager:RegenerateGroupName(destGroup)
                                end
                            else
                                EUI_CategoryManager:ReorderCategory(newIdx, target)
                            end
                        end
                    end
                end
            else
                -- Check if insert position is inside a group -- auto-join that group
                local destGroup = _dragInsertGroup
                if destGroup then
                    EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                    for i, cat in ipairs(cats) do
                        if cat == fromCat then
                            EUI_CategoryManager:AddToGroup(i, destGroup)
                            break
                        end
                    end
                    if not EUI_CategoryManager:IsGroupNameCustom(destGroup) then
                        EUI_CategoryManager:RegenerateGroupName(destGroup)
                    end
                else
                    EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                end
            end
        end
    end

    -- Re-sort any categories affected by group membership changes
    local newFromCat = nil
    for i, cat in ipairs(cats) do if cat == fromCat then newFromCat = cat; break end end
    local oldGroup = fromGroup
    local newGroup = newFromCat and newFromCat.groupName
    if oldGroup ~= newGroup then
        local resortCats = {}
        -- Find the moved category's current index
        for i, cat in ipairs(cats) do
            if cat == fromCat then resortCats[#resortCats + 1] = i; break end
        end
        if oldGroup then
            local oldMembers = EUI_CategoryManager:GetGroupMembers(oldGroup)
            if oldMembers then
                for _, mi in ipairs(oldMembers) do resortCats[#resortCats + 1] = mi end
            end
        end
        if newGroup then
            local newMembers = EUI_CategoryManager:GetGroupMembers(newGroup)
            if newMembers then
                for _, mi in ipairs(newMembers) do resortCats[#resortCats + 1] = mi end
            end
        end
        ResortAfterGroupChange(resortCats, newGroup or oldGroup)
        if oldGroup and newGroup and oldGroup ~= newGroup then
            ResortAfterGroupChange({}, oldGroup)
        end
    end

    -- Restore selection by reference (index may have shifted during reorder)
    if selectedCatRef then
        for i, cat in ipairs(cats) do
            if cat == selectedCatRef then selectedCategoryIndex = i; break end
        end
    end
    selectedGroupName = savedGroupName

    _dragFromCatIdx = nil
    _dragSourceBtn = nil
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil
    _dragTargetIsHeader = nil
    _dragInsertGroup = nil
    _dragUpdateFrame:Hide()
    if _dragGhost then _dragGhost:Hide() end
    if _dragInsertLine then _dragInsertLine:Hide() end
    if _dragGroupHL then _dragGroupHL:Hide() end
    if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
    EUI_Bags:RefreshInventory()
end

local function CreateSidebar()
    if EUI_Bags._sidebar then return end

    local sidebar = CreateFrame("Frame", nil, EUI_Bags)
    sidebar:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", 0, -(HEADER_H))
    sidebar:SetPoint("BOTTOMLEFT", EUI_Bags.Footer, "TOPLEFT", 0, 0)
    sidebar:SetWidth(GetSidebarWidth())
    sidebar.bg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
    sidebar.bg:SetAllPoints()
    sidebar.bg:SetColorTexture(0, 0, 0, 0.25)

    -- Right-edge separator
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    sidebar.sep = sidebar:CreateTexture(nil, "ARTWORK")
    sidebar.sep:SetWidth(px)
    sidebar.sep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebar.sep:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebar.sep:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- Sidebar header: "Categories" label + collapse arrow
    local SIDEBAR_HDR_H = 24
    local sidebarHdr = CreateFrame("Frame", nil, sidebar)
    sidebarHdr:SetHeight(SIDEBAR_HDR_H)
    sidebarHdr:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    sidebarHdr:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)

    sidebarHdr._label = sidebarHdr:CreateFontString(nil, "OVERLAY")
    SetBagFont(sidebarHdr._label, 10)
    sidebarHdr._label:SetPoint("LEFT", sidebarHdr, "LEFT", 8, 0)
    sidebarHdr._label:SetText(EllesmereUI.L("Categories"))
    sidebarHdr._label:SetTextColor(0.5, 0.5, 0.5)

    local ARROW_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png"
    local collapseBtn = CreateFrame("Button", nil, sidebarHdr)
    collapseBtn:SetSize(12, 12)
    collapseBtn:SetPoint("RIGHT", sidebarHdr, "RIGHT", -6, 0)
    collapseBtn._icon = collapseBtn:CreateTexture(nil, "OVERLAY")
    collapseBtn._icon:SetAllPoints()
    collapseBtn._icon:SetTexture(ARROW_ICON)
    collapseBtn._icon:SetAlpha(0.4)

    local function UpdateCollapseArrow()
        local collapsed = BP().bagSidebarCollapsed
        collapseBtn:ClearAllPoints()
        if collapsed then
            collapseBtn._icon:SetRotation(math.pi)
            collapseBtn:SetPoint("CENTER", sidebarHdr, "CENTER", 0, 0)
        else
            collapseBtn._icon:SetRotation(0)
            collapseBtn:SetPoint("RIGHT", sidebarHdr, "RIGHT", -6, 0)
        end
    end
    UpdateCollapseArrow()

    collapseBtn:SetScript("OnEnter", function(self)
        self._icon:SetAlpha(0.9)
        local collapsed = BP().bagSidebarCollapsed
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, collapsed and "Expand Sidebar" or "Collapse Sidebar")
        end
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        self._icon:SetAlpha(0.4)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    collapseBtn:SetScript("OnClick", function()
        local center = EUI_Bags:GetCenter()
        local screenW = UIParent:GetWidth()
        local onRightSide = center and screenW and (center > screenW / 2)
        local oldRight = onRightSide and EUI_Bags:GetRight() or nil
        local oldTop = onRightSide and EUI_Bags:GetTop() or nil

        BP().bagSidebarCollapsed = not BP().bagSidebarCollapsed
        UpdateCollapseArrow()
        sidebar:SetWidth(GetSidebarWidth())
        EUI_Bags:RefreshInventory()

        if onRightSide and oldRight and oldTop then
            local left = oldRight - EUI_Bags:GetWidth()
            EUI_Bags:ClearAllPoints()
            EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, oldTop)
            BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = oldTop }
        end
    end)

    -- Sidebar scroll frame (below header, above footer)
    local sidebarSF = CreateFrame("ScrollFrame", nil, sidebar)
    sidebarSF:SetPoint("TOPLEFT", sidebarHdr, "BOTTOMLEFT", 0, 0)
    sidebarSF:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSF:EnableMouseWheel(true)
    local sidebarChild = CreateFrame("Frame", nil, sidebarSF)
    sidebarChild:SetWidth(GetSidebarWidth())
    sidebarSF:SetScrollChild(sidebarChild)

    local SIDEBAR_SCROLL_STEP = 28
    sidebarSF:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = sidebarChild:GetHeight() - self:GetHeight()
        if maxScroll <= 0 then return end
        local cur = self:GetVerticalScroll()
        local newVal = math.max(0, math.min(maxScroll, cur - delta * SIDEBAR_SCROLL_STEP))
        self:SetVerticalScroll(newVal)
    end)

    EUI_Bags._sidebar = sidebar
    EUI_Bags._sidebarHdr = sidebarHdr
    EUI_Bags._sidebarSF = sidebarSF
    EUI_Bags._sidebarChild = sidebarChild
    EUI_Bags._collapseBtn = collapseBtn
end

-- Show context menu for grouping categories
local function ShowCategoryContextMenu(btn, catIdx, isGroupHeader, isGroupMember)
    local cats = EUI_CategoryManager:GetCategories()
    local cat = cats[catIdx]
    if not cat then return end
    -- Set children have no menu actions (rename/group/hide all N/A): no empty menu
    if cat.isEquipSet then return end

    MenuUtil.CreateContextMenu(btn, function(_, rootDescription)
        local myGroup = cat.groupName

        if not BP().bagHiddenInAllItems then BP().bagHiddenInAllItems = {} end
        local hiddenSet = BP().bagHiddenInAllItems

        if isGroupHeader and myGroup then
            rootDescription:CreateButton(EllesmereUI.L("Rename"), function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Group",
                    message = EllesmereUI.L("Enter a new name for this group:"),
                    placeholder = myGroup,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == myGroup then return end
                        EUI_CategoryManager:RenameGroup(myGroup, newName)
                        EUI_CategoryManager:SetGroupNameCustom(newName, true)
                        if selectedGroupName == myGroup then selectedGroupName = newName end
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            rootDescription:CreateButton(EllesmereUI.L("Disband Group"), function()
                ClearGroupOrder(myGroup)
                EUI_CategoryManager:DisbandGroup(myGroup)
                if selectedGroupName == myGroup then selectedGroupName = nil; selectedCategoryIndex = 0 end
                EUI_Bags:RefreshInventory()
            end)
            local groupHidden = hiddenSet[myGroup]
            rootDescription:CreateButton(groupHidden and EllesmereUI.L("Show in All Items") or EllesmereUI.L("Hide in All Items"), function()
                hiddenSet[myGroup] = not groupHidden or nil
                EUI_Bags:RefreshInventory()
            end)
        elseif isGroupMember and myGroup then
            rootDescription:CreateButton(EllesmereUI.L("Rename"), function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Category",
                    message = EllesmereUI.Lf("Enter a new name for \"%1$s\":", cat.name),
                    placeholder = cat.name,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == cat.name then return end
                        EUI_CategoryManager:RenameCategory(catIdx, newName)
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            rootDescription:CreateButton(EllesmereUI.Lf("Ungroup %1$s", cat.name), function()
                ClearGroupOrder(myGroup)
                EUI_CategoryManager:UngroupCategory(catIdx)
                EUI_Bags:RefreshInventory()
            end)
        else
            -- Equip-set categories are named by the set; renames would not persist
            if not cat.isEquipSet then
            rootDescription:CreateButton(EllesmereUI.L("Rename"), function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Category",
                    message = EllesmereUI.Lf("Enter a new name for \"%1$s\":", cat.name),
                    placeholder = cat.name,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == cat.name then return end
                        EUI_CategoryManager:RenameCategory(catIdx, newName)
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            end

            if not cat.noGroup then
                local groupSub = rootDescription:CreateButton(EllesmereUI.L("Create Group With"))
                local hasOptions = false
                for ci, other in ipairs(cats) do
                    if ci ~= catIdx and not other.groupName and not other.noGroup then
                        hasOptions = true
                        groupSub:CreateButton(other.name, function()
                            EUI_CategoryManager:GroupCategories({ catIdx, ci })
                            EUI_Bags:RefreshInventory()
                        end)
                    end
                end

                local groupNames = EUI_CategoryManager:GetGroupNames()
                if #groupNames > 0 then
                    local addSub = rootDescription:CreateButton(EllesmereUI.L("Add to Group"))
                    for _, gn in ipairs(groupNames) do
                        addSub:CreateButton(gn, function()
                            EUI_CategoryManager:AddToGroup(catIdx, gn)
                            EUI_Bags:RefreshInventory()
                        end)
                    end
                end
            end

            -- Equip-set children don't render standalone in All Items (they fold
            -- into their anchor's section), so hide/show doesn't apply to them.
            if not cat.noMove and not cat.isEquipSet then
                local catKey = cat._defaultName
                local catHidden = hiddenSet[catKey]
                rootDescription:CreateButton(catHidden and EllesmereUI.L("Show in All Items") or EllesmereUI.L("Hide in All Items"), function()
                    hiddenSet[catKey] = not catHidden or nil
                    EUI_Bags:RefreshInventory()
                end)
            end
        end
    end)
end

local function BuildSidebarButtons(categoryCounts, totalCount)
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return end
    local collapsed = BP().bagSidebarCollapsed
    local sidebarW = GetSidebarWidth()
    sidebar:SetWidth(sidebarW)

    if EUI_Bags._sidebarHdr then
        if collapsed then EUI_Bags._sidebarHdr._label:Hide()
        else EUI_Bags._sidebarHdr._label:Show() end
    end

    local cats = EUI_CategoryManager and EUI_CategoryManager:GetCategories() or {}

    -- Build display list: { catIdx, name, icon, count, isGroupHeader, groupName, indent }
    local displayList = {}
    -- Three fixed views; the configured default type first, then canonical order.
    local _fixedViews = {
        all      = { catIdx = 0,  name = EllesmereUI.L("All Items"), icon = 133633, count = totalCount },
        onebag   = { catIdx = -1, name = EllesmereUI.L("OneBag"),    icon = 133634, count = totalCount },
        multibag = { catIdx = -2, name = EllesmereUI.L("MultiBag"),  icon = 133635, count = totalCount },
    }
    local _dbt = GetDefaultBagType()
    displayList[#displayList + 1] = _fixedViews[_dbt] or _fixedViews.all
    for _, _k in ipairs({ "all", "onebag", "multibag" }) do
        if _k ~= _dbt then displayList[#displayList + 1] = _fixedViews[_k] end
    end

    -- Split-mode set children: rendered nested under the "Item Set Gear" anchor
    -- wherever it sits (plain or inside a group), skipped by the main loop.
    -- Scan gated on split mode: zero extra work while it's off.
    local setChildren, setChildTotal = nil, 0
    if BP().bagSplitSetGearBySet then
        for i, c in ipairs(cats) do
            if c.isEquipSet then
                setChildren = setChildren or {}
                setChildren[#setChildren + 1] = i
                setChildTotal = setChildTotal + (categoryCounts and categoryCounts[i] or 0)
            end
        end
    end
    local function EmitSetChildren(level)
        if not setChildren or collapsed then return end
        for _, sci in ipairs(setChildren) do
            local sc = cats[sci]
            displayList[#displayList + 1] = {
                catIdx = sci, name = sc.name, icon = sc.icon or 134400,
                count = categoryCounts and categoryCounts[sci] or 0,
                indent = level, isEquipSet = true,
            }
        end
    end
    local function IsSetAnchor(c) return c and c.isSetGear and not c.isEquipSet end

    local renderedGroups = {}
    for ci, cat in ipairs(cats) do
        if cat.groupName then
            if not renderedGroups[cat.groupName] then
                renderedGroups[cat.groupName] = true
                -- Group header: sum counts of all members (+ set children on the anchor)
                local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                local groupCount = 0
                for _, mi in ipairs(members) do
                    groupCount = groupCount + (categoryCounts and categoryCounts[mi] or 0)
                    if IsSetAnchor(cats[mi]) then groupCount = groupCount + setChildTotal end
                end
                -- Use first member's icon for group
                local firstCat = cats[members[1]]
                local groupIcon = firstCat and firstCat.icon or 134400
                local groupIsAtlas = firstCat and firstCat.isAtlas
                -- Check if any member is user-created (keep group visible if so)
                local groupHasUserCreated = false
                for _, mi in ipairs(members) do
                    if cats[mi] and cats[mi].isUserCreated then groupHasUserCreated = true; break end
                end
                displayList[#displayList + 1] = {
                    catIdx = members[1], name = cat.groupName, icon = groupIcon, isAtlas = groupIsAtlas,
                    count = groupCount, isGroupHeader = true, groupName = cat.groupName,
                    isUserCreated = groupHasUserCreated,
                }
                -- Indented members (hidden when collapsed)
                if not collapsed then
                    for _, mi in ipairs(members) do
                        local mc = cats[mi]
                        local anchor = IsSetAnchor(mc)
                        displayList[#displayList + 1] = {
                            catIdx = mi, name = mc.name, icon = mc.icon or 134400, isAtlas = mc.isAtlas,
                            count = (categoryCounts and categoryCounts[mi] or 0) + (anchor and setChildTotal or 0),
                            indent = true, groupName = cat.groupName, isGroupMember = true,
                            isUserCreated = mc.isUserCreated,
                        }
                        -- Set children: third level under a grouped anchor
                        if anchor then EmitSetChildren(2) end
                    end
                end
            end
        elseif cat.isEquipSet then
            -- Emitted by EmitSetChildren under the anchor
        else
            local anchor = IsSetAnchor(cat)
            local count = (categoryCounts and categoryCounts[ci] or 0) + (anchor and setChildTotal or 0)
            local isUserCreated = not cat.isCatchAll and (not cat.types or #cat.types == 0)
            -- Skip Pinned/Recent Items if disabled
            if cat.isPinned and BP().bagShowPinnedItems == false then
                -- skip
            elseif cat.isRecent and BP().bagShowRecentItems == false then
                -- skip
            else
                displayList[#displayList + 1] = { catIdx = ci, name = cat.name, icon = cat.icon or 134400, isAtlas = cat.isAtlas, count = count, noMove = cat.noMove, isPinned = cat.isPinned, isRecent = cat.isRecent, isUserCreated = cat.isUserCreated }
                if anchor then EmitSetChildren(1) end
            end
        end
    end

    -- Hide empty categories (sidebar-only visual, does not affect grouping)
    local hideEmpty = BP().bagHideEmptyCategories ~= false
    if hideEmpty then
        local filtered = {}
        for _, entry in ipairs(displayList) do
            local keep = true
            if entry.count == 0 then
                -- Always keep: All Items, OneBag, noMove (Pinned/Recent), user-created
                if entry.catIdx >= 1 and not entry.noMove and not entry.isUserCreated then
                    if entry.isGroupHeader then
                        -- Hide group header if all members are 0
                        keep = false
                    elseif entry.isGroupMember then
                        keep = false
                    else
                        keep = false
                    end
                end
            end
            if keep then filtered[#filtered + 1] = entry end
        end
        displayList = filtered
    end

    for i = 1, #displayList do
        if not _sidebarBtns[i] then
            local btn = CreateFrame("Button", nil, EUI_Bags._sidebarChild or sidebar)
            btn:SetHeight(SIDEBAR_BTN_H)
            btn._indicator = btn:CreateTexture(nil, "OVERLAY")
            local PP = EUI and EUI.PP
            local px = (PP and PP.mult) or 1
            btn._indicator:SetWidth(px * 2)
            btn._indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            btn._indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            btn._bg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            btn._bg:SetAllPoints()
            btn._bg:SetColorTexture(1, 1, 1, 0)
            btn._icon = btn:CreateTexture(nil, "ARTWORK")
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._label = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._label, 11)
            btn._label:SetJustifyH("LEFT")
            btn._label:SetWordWrap(false)
            btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
            btn._label:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
            btn._count = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._count, 10)
            btn._count:SetJustifyH("RIGHT")
            btn._count:SetTextColor(0.5, 0.5, 0.5)
            btn._count:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

            btn:SetScript("OnEnter", function(self)
                if _dragFromCatIdx then return end
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (not self._isGroupHeader and self._catIdx == selectedCategoryIndex and not selectedGroupName)
                if not isSel then self._bg:SetColorTexture(1, 1, 1, 0.06) end
                if (BP().bagSidebarCollapsed) and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, (self._catName or "?") .. " (" .. (self._catCount or 0) .. ")")
                end
            end)
            btn:SetScript("OnLeave", function(self)
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (not self._isGroupHeader and self._catIdx == selectedCategoryIndex and not selectedGroupName)
                if not isSel then self._bg:SetColorTexture(1, 1, 1, 0) end
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if self._catIdx > 0 then ShowCategoryContextMenu(self, self._catIdx, self._isGroupHeader, self._isGroupMember) end
                    return
                end
                -- Drag-to-sidebar: if the cursor holds an item, assign it to this category
                if self._catIdx and self._catIdx > 0 then
                    local cursorType, cursorItemID = GetCursorInfo()
                    if cursorType == "item" and cursorItemID then
                        if EUI_CategoryManager and EUI_CategoryManager:CanAssignToCategory(self._catIdx) then
                            local cats = EUI_CategoryManager:GetCategories()
                            local cat = cats[self._catIdx]
                            if cat then
                                EUI_CategoryManager:AssignItem(cursorItemID, cat._defaultName)
                                ClearCursor()
                                EUI_Bags:RefreshInventory()
                                return
                            end
                        end
                    end
                end
                if self._didDrag then self._didDrag = false; return end
                if self._isGroupHeader and self._groupName then
                    selectedGroupName = self._groupName
                    selectedCategoryIndex = 0
                elseif self._isGroupMember and self._groupName then
                    selectedGroupName = nil
                    selectedCategoryIndex = self._catIdx
                else
                    selectedGroupName = nil
                    selectedCategoryIndex = self._catIdx
                end
                if EUI_Bags._scrollFrame then EUI_Bags._scrollFrame:SetVerticalScroll(0) end
                EUI_Bags:RefreshInventory()
            end)
            btn:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                -- Equip-set cats: ReorderCategory rejects them; don't start the drag either
                if self._catIdx <= 0 or self._noMove or self._isEquipSet then return end
                self._didDrag = false
                local _, startY = GetCursorPosition()
                self._dragStartY = startY
                self._dragPending = true
                _sidebarDragDetect._btn = self
                _sidebarDragDetect:Show()
            end)
            btn:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" then return end
                self._dragPending = false
                _sidebarDragDetect:Hide()
                if self._didDrag then StopSidebarDrag() end
            end)


            _sidebarBtns[i] = btn
        end
    end

    for i = #displayList + 1, #_sidebarBtns do _sidebarBtns[i]:Hide() end

    -- Separator line between All Items/OneBag and categories
    if not sidebar._catDivider then
        local PP = EUI and EUI.PP
        local px = (PP and PP.mult) or 1
        local div = (sidebarChild or sidebar):CreateTexture(nil, "ARTWORK")
        div:SetHeight(px)
        div:SetColorTexture(0.2, 0.2, 0.2, 1)
        sidebar._catDivider = div
    end

    -- Position and populate (buttons go in the scroll child)
    local sidebarChild = EUI_Bags._sidebarChild
    if sidebarChild then sidebarChild:SetWidth(sidebarW) end
    local y = 0
    local ar, ag, ab = GetAccentRGB()
    local INDENT = SIDEBAR_INDENT

    for i, entry in ipairs(displayList) do
        local btn = _sidebarBtns[i]
        local isSelected
        if entry.isGroupHeader then
            isSelected = (entry.groupName == selectedGroupName)
        else
            isSelected = (not selectedGroupName and entry.catIdx == selectedCategoryIndex)
        end

        btn._catIdx = entry.catIdx
        btn._catName = entry.name
        btn._catIcon = entry.icon
        btn._catIsAtlas = entry.isAtlas
        btn._catCount = entry.count
        btn._isGroupHeader = entry.isGroupHeader or false
        btn._isGroupMember = entry.isGroupMember or false
        btn._groupName = entry.groupName
        btn._noMove = entry.noMove or false
        btn._isEquipSet = entry.isEquipSet or false
        btn._isPinned = entry.isPinned or false

        btn:SetParent(sidebarChild or sidebar)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", 0, y)
        btn:SetWidth(sidebarW)

        -- entry.indent: true = 1 level (legacy group members), or a number of levels
        local indentLv = (entry.indent == true and 1) or entry.indent or 0
        local leftPad = (indentLv ~= 0 and not collapsed) and (8 + INDENT * indentLv) or 8
        btn._icon:ClearAllPoints()
        if collapsed then
            btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        else
            btn._icon:SetPoint("LEFT", btn, "LEFT", leftPad, 0)
        end
        if entry.isAtlas then
            btn._icon:SetAtlas(entry.icon)
            btn._icon:SetTexCoord(0, 1, 0, 1)
        else
            btn._icon:SetTexture(entry.icon)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        btn._icon:SetAlpha(isSelected and 1 or 0.75)
        -- Smaller icon for indented members
        if entry.indent then
            btn._icon:SetSize(SIDEBAR_ICON_SIZE - 2, SIDEBAR_ICON_SIZE - 2)
        else
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        end

        if collapsed then
            btn._label:Hide()
            btn._count:Hide()
        else
            btn._label:Show()
            btn._label:SetText(entry.name)
            btn._label:SetTextColor(1, 1, 1, isSelected and 1 or 0.75)

            btn._count:Show()
            btn._count:SetText(tostring(entry.count))
        end

        if isSelected then
            btn._indicator:SetColorTexture(ar, ag, ab, 1)
            btn._indicator:Show()
            btn._bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            btn._indicator:Hide()
            btn._bg:SetColorTexture(1, 1, 1, 0)
        end

        btn:Show()
        y = y - SIDEBAR_BTN_H - SIDEBAR_PAD

        -- Divider after the last special entry (Pinned or Recent)
        local isLastSpecial = entry.isPinned or entry.isRecent
        local nextEntry = displayList[i + 1]
        local nextIsRegular = nextEntry and not nextEntry.isPinned and not nextEntry.isRecent
        if isLastSpecial and nextIsRegular and sidebar._catDivider then
            y = y - 4  -- spacing above line
            local div = sidebar._catDivider
            div:SetParent(sidebarChild or sidebar)
            div:ClearAllPoints()
            local inset = math.floor(sidebarW * 0.08)
            div:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", inset, y)
            div:SetPoint("TOPRIGHT", sidebarChild or sidebar, "TOPRIGHT", -inset, y)
            div:Show()
            y = y - (div:GetHeight() or 1) - 4  -- spacing below line
        end
    end

    -- "+Add Category" button at the bottom of the sidebar
    local hideAddCat = BP().bagHideAddCategory
    if not collapsed and not hideAddCat then
        if not sidebar._addCatBtn then
            local btn = CreateFrame("Button", nil, sidebarChild or sidebar)
            btn:SetHeight(SIDEBAR_BTN_H)
            btn._bg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            btn._bg:SetAllPoints()
            btn._bg:SetColorTexture(1, 1, 1, 0)
            btn._icon = btn:CreateTexture(nil, "ARTWORK")
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
            btn._icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
            btn._icon:SetTexture(134400)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._icon:SetAlpha(0.5)
            btn._label = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._label, 11)
            btn._label:SetJustifyH("LEFT")
            btn._label:SetWordWrap(false)
            btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
            btn._label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            btn._label:SetText(EllesmereUI.L("Add Category"))
            btn._label:SetTextColor(1, 1, 1, 0.4)
            btn:SetScript("OnEnter", function(self)
                self._bg:SetColorTexture(1, 1, 1, 0.06)
                self._label:SetTextColor(1, 1, 1, 0.8)
                self._icon:SetAlpha(0.8)
            end)
            btn:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(1, 1, 1, 0)
                self._label:SetTextColor(1, 1, 1, 0.4)
                self._icon:SetAlpha(0.5)
            end)
            btn:SetScript("OnClick", function(self)
                local popup = EUI_Bags._newCatPopup
                if popup and popup:IsShown() then popup:Hide(); return end
                if not popup then
                    popup = CreateFrame("Frame", nil, EUI_Bags)
                    popup:SetFrameStrata("DIALOG")
                    popup:SetSize(240, 230)
                    popup:EnableMouse(true)
                    local bg = popup:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                    local PP = EUI and EUI.PP
                    if PP and PP.CreateBorder then PP.CreateBorder(popup, 0.2, 0.2, 0.2, 1) end

                    local title = popup:CreateFontString(nil, "OVERLAY")
                    SetBagFont(title, 13)
                    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -10)
                    title:SetTextColor(1, 1, 1, 0.9)
                    title:SetText(EllesmereUI.L("New Custom Category"))

                    local eb = CreateFrame("EditBox", nil, popup)
                    eb:SetSize(220, 22)
                    eb:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -30)
                    eb:SetAutoFocus(false)
                    eb:SetFont(GetFont(), 12, "")
                    eb:SetTextColor(1, 1, 1, 1)
                    eb:SetTextInsets(6, 6, 0, 0)
                    eb:SetMaxLetters(30)
                    local ebBg = eb:CreateTexture(nil, "BACKGROUND")
                    ebBg:SetAllPoints()
                    ebBg:SetColorTexture(0.1, 0.1, 0.1, 1)
                    if PP and PP.CreateBorder then PP.CreateBorder(eb, 0.15, 0.15, 0.15, 1) end
                    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
                    eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
                    popup._nameEB = eb

                    local iconLbl = popup:CreateFontString(nil, "OVERLAY")
                    SetBagFont(iconLbl, 11)
                    iconLbl:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -8)
                    iconLbl:SetTextColor(0.7, 0.7, 0.7, 1)
                    iconLbl:SetText(EllesmereUI.L("Icon:"))

                    -- Icon grid (placeholder IDs -- replace with real set)
                    local ICON_IDS = {
                        7514178, 7548926, 7427980, 7548966, 2143125,
                        6025441, 7451177, 7548901, 7501337, 7704166,
                        7549083, 7549010, 7136579, 7549012,
                    }
                    popup._iconIDs = ICON_IDS
                    local ICON_SZ = 28
                    local ICON_PAD = 4
                    local ICONS_PER_ROW = 7
                    local iconBtns = {}
                    popup._selectedIcon = ICON_IDS[1]
                    popup._customMode = false

                    local ar, ag, ab = GetAccentRGB()
                    local bPx = (PP and PP.mult or 1) * 2

                    -- Helper: update selection highlight across grid + custom
                    local function UpdateSelection()
                        for _, ob in ipairs(iconBtns) do ob._border:Hide() end
                        if popup._customBorder then popup._customBorder:Hide() end
                        if popup._customMode then
                            if popup._customBorder then popup._customBorder:Show() end
                        else
                            for _, ob in ipairs(iconBtns) do
                                if ob._iconID == popup._selectedIcon then
                                    ob._border:Show(); break
                                end
                            end
                        end
                    end
                    popup._updateSelection = UpdateSelection

                    for idx, iconID in ipairs(ICON_IDS) do
                        local ib = CreateFrame("Button", nil, popup)
                        ib:SetSize(ICON_SZ, ICON_SZ)
                        local col = (idx - 1) % ICONS_PER_ROW
                        local row = math.floor((idx - 1) / ICONS_PER_ROW)
                        ib:SetPoint("TOPLEFT", iconLbl, "BOTTOMLEFT", col * (ICON_SZ + ICON_PAD), -(4 + row * (ICON_SZ + ICON_PAD)))
                        local tex = ib:CreateTexture(nil, "ARTWORK")
                        tex:SetAllPoints()
                        tex:SetTexture(iconID)
                        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        ib._tex = tex
                        ib._iconID = iconID
                        -- Accent-colored 2px border for selection
                        local border = CreateFrame("Frame", nil, ib)
                        border:SetPoint("TOPLEFT", -bPx, bPx)
                        border:SetPoint("BOTTOMRIGHT", bPx, -bPx)
                        border:SetFrameLevel(ib:GetFrameLevel() + 2)
                        local bTop = border:CreateTexture(nil, "OVERLAY"); bTop:SetColorTexture(ar, ag, ab, 1)
                        bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetHeight(bPx)
                        local bBot = border:CreateTexture(nil, "OVERLAY"); bBot:SetColorTexture(ar, ag, ab, 1)
                        bBot:SetPoint("BOTTOMLEFT"); bBot:SetPoint("BOTTOMRIGHT"); bBot:SetHeight(bPx)
                        local bLeft = border:CreateTexture(nil, "OVERLAY"); bLeft:SetColorTexture(ar, ag, ab, 1)
                        bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetWidth(bPx)
                        local bRight = border:CreateTexture(nil, "OVERLAY"); bRight:SetColorTexture(ar, ag, ab, 1)
                        bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetWidth(bPx)
                        border:Hide()
                        ib._border = border
                        ib:SetScript("OnClick", function(s)
                            popup._selectedIcon = s._iconID
                            popup._customMode = false
                            popup._prevTex:SetTexture(s._iconID)
                            UpdateSelection()
                        end)
                        ib:SetScript("OnEnter", function(s) s._tex:SetAlpha(1) end)
                        ib:SetScript("OnLeave", function(s) s._tex:SetAlpha(0.85) end)
                        ib._tex:SetAlpha(0.85)
                        iconBtns[idx] = ib
                    end
                    popup._iconBtns = iconBtns

                    -- Custom icon ID label + preview + editbox
                    local lastRow = math.ceil(#ICON_IDS / ICONS_PER_ROW)
                    local customLbl = popup:CreateFontString(nil, "OVERLAY")
                    SetBagFont(customLbl, 11)
                    customLbl:SetPoint("TOPLEFT", iconLbl, "BOTTOMLEFT", 0, -(4 + lastRow * (ICON_SZ + ICON_PAD) + 6))
                    customLbl:SetTextColor(0.7, 0.7, 0.7, 1)
                    customLbl:SetText(EllesmereUI.L("Custom Icon ID:"))

                    local preview = CreateFrame("Frame", nil, popup)
                    preview:SetSize(22, 22)
                    preview:SetPoint("TOPLEFT", customLbl, "BOTTOMLEFT", 0, -4)
                    local prevTex = preview:CreateTexture(nil, "ARTWORK")
                    prevTex:SetAllPoints()
                    prevTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    prevTex:SetTexture(ICON_IDS[1])
                    popup._prevTex = prevTex
                    -- Accent border on the preview (for custom mode)
                    local cBorder = CreateFrame("Frame", nil, preview)
                    cBorder:SetPoint("TOPLEFT", -bPx, bPx)
                    cBorder:SetPoint("BOTTOMRIGHT", bPx, -bPx)
                    cBorder:SetFrameLevel(preview:GetFrameLevel() + 2)
                    local cbTop = cBorder:CreateTexture(nil, "OVERLAY"); cbTop:SetColorTexture(ar, ag, ab, 1)
                    cbTop:SetPoint("TOPLEFT"); cbTop:SetPoint("TOPRIGHT"); cbTop:SetHeight(bPx)
                    local cbBot = cBorder:CreateTexture(nil, "OVERLAY"); cbBot:SetColorTexture(ar, ag, ab, 1)
                    cbBot:SetPoint("BOTTOMLEFT"); cbBot:SetPoint("BOTTOMRIGHT"); cbBot:SetHeight(bPx)
                    local cbLeft = cBorder:CreateTexture(nil, "OVERLAY"); cbLeft:SetColorTexture(ar, ag, ab, 1)
                    cbLeft:SetPoint("TOPLEFT"); cbLeft:SetPoint("BOTTOMLEFT"); cbLeft:SetWidth(bPx)
                    local cbRight = cBorder:CreateTexture(nil, "OVERLAY"); cbRight:SetColorTexture(ar, ag, ab, 1)
                    cbRight:SetPoint("TOPRIGHT"); cbRight:SetPoint("BOTTOMRIGHT"); cbRight:SetWidth(bPx)
                    cBorder:Hide()
                    popup._customBorder = cBorder

                    local customEB = CreateFrame("EditBox", nil, popup)
                    customEB:SetSize(80, 22)
                    customEB:SetPoint("LEFT", preview, "RIGHT", 8, 0)
                    customEB:SetAutoFocus(false)
                    customEB:SetFont(GetFont(), 11, "")
                    customEB:SetTextColor(1, 1, 1, 1)
                    customEB:SetTextInsets(4, 4, 0, 0)
                    customEB:SetNumeric(true)
                    local cBg = customEB:CreateTexture(nil, "BACKGROUND")
                    cBg:SetAllPoints()
                    cBg:SetColorTexture(0.1, 0.1, 0.1, 1)
                    if PP and PP.CreateBorder then PP.CreateBorder(customEB, 0.15, 0.15, 0.15, 1) end
                    customEB:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
                    customEB:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
                    customEB:SetScript("OnTextChanged", function(s)
                        local txt = s:GetText()
                        local id = tonumber(txt)
                        if txt and txt ~= "" and id and id > 0 then
                            popup._selectedIcon = id
                            popup._customMode = true
                            prevTex:SetTexture(id)
                        else
                            popup._customMode = false
                        end
                        UpdateSelection()
                    end)
                    popup._customEB = customEB

                    local createBtn = CreateFrame("Button", nil, popup)
                    createBtn:SetSize(220, 26)
                    createBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 10, 10)
                    local cBtnBg = createBtn:CreateTexture(nil, "BACKGROUND")
                    cBtnBg:SetAllPoints()
                    cBtnBg:SetColorTexture(0.15, 0.15, 0.15, 1)
                    if PP and PP.CreateBorder then PP.CreateBorder(createBtn, 0.25, 0.25, 0.25, 1) end
                    local cBtnLbl = createBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(cBtnLbl, 12)
                    cBtnLbl:SetPoint("CENTER")
                    cBtnLbl:SetTextColor(1, 1, 1, 0.9)
                    cBtnLbl:SetText(EllesmereUI.L("Create"))
                    createBtn:SetScript("OnEnter", function() cBtnBg:SetColorTexture(0.2, 0.2, 0.2, 1) end)
                    createBtn:SetScript("OnLeave", function() cBtnBg:SetColorTexture(0.15, 0.15, 0.15, 1) end)
                    -- Red flash validation for empty fields
                    local function MakeFlashBorder(parent)
                        local fb = CreateFrame("Frame", nil, parent)
                        fb:SetPoint("TOPLEFT", -1, 1)
                        fb:SetPoint("BOTTOMRIGHT", 1, -1)
                        fb:SetFrameLevel(parent:GetFrameLevel() + 5)
                        local edges = {}
                        local function MakeEdge(p1, p2, isHoriz)
                            local t = fb:CreateTexture(nil, "OVERLAY")
                            t:SetColorTexture(0.9, 0.15, 0.15, 0)
                            if isHoriz then
                                t:SetPoint(p1); t:SetPoint(p2); t:SetHeight(1)
                            else
                                t:SetPoint(p1); t:SetPoint(p2); t:SetWidth(1)
                            end
                            edges[#edges + 1] = t
                        end
                        MakeEdge("TOPLEFT", "TOPRIGHT", true)
                        MakeEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
                        MakeEdge("TOPLEFT", "BOTTOMLEFT", false)
                        MakeEdge("TOPRIGHT", "BOTTOMRIGHT", false)
                        fb._edges = edges
                        fb._elapsed = 0
                        fb._active = false
                        fb:SetScript("OnUpdate", function(self, dt)
                            if not self._active then self:Hide(); return end
                            self._elapsed = self._elapsed + dt
                            if self._elapsed >= 0.7 then
                                self._active = false
                                for _, e in ipairs(self._edges) do e:SetColorTexture(0.9, 0.15, 0.15, 0) end
                                self:Hide()
                                return
                            end
                            local t = self._elapsed / 0.7
                            local a = 0.7 * (1 - t)
                            for _, e in ipairs(self._edges) do e:SetColorTexture(0.9, 0.15, 0.15, a) end
                        end)
                        fb:Hide()
                        fb.Flash = function(self)
                            self._elapsed = 0
                            self._active = true
                            for _, e in ipairs(self._edges) do e:SetColorTexture(0.9, 0.15, 0.15, 0.7) end
                            self:Show()
                        end
                        return fb
                    end
                    local nameFlash = MakeFlashBorder(eb)
                    popup._nameFlash = nameFlash

                    createBtn:SetScript("OnClick", function()
                        local name = popup._nameEB:GetText()
                        if not name or name == "" then
                            popup._nameFlash:Flash()
                            popup._nameEB:SetFocus()
                            return
                        end
                        local icon = popup._selectedIcon or 134400
                        local idx = EUI_CategoryManager:AddCustomCategory(name)
                        if idx then
                            local cats = EUI_CategoryManager:GetCategories()
                            if cats[idx] then
                                cats[idx].icon = icon
                                cats[idx].isAtlas = nil
                            end
                            EUI_CategoryManager:SaveState()
                        end
                        popup:Hide()
                        EUI_Bags:RefreshInventory()
                    end)

                    popup:SetScript("OnKeyDown", function(s, key)
                        if key == "ESCAPE" then s:Hide(); s:SetPropagateKeyboardInput(false)
                        else s:SetPropagateKeyboardInput(true) end
                    end)
                    popup:EnableKeyboard(true)

                    EUI_Bags._newCatPopup = popup
                end
                popup._nameEB:SetText("")
                popup._customEB:SetText("")
                popup._selectedIcon = popup._iconIDs[1]
                popup._customMode = false
                popup._prevTex:SetTexture(popup._iconIDs[1])
                popup._updateSelection()
                popup:ClearAllPoints()
                popup:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", 4, 0)
                popup:Show()
                popup._nameEB:SetFocus()
            end)
            sidebar._addCatBtn = btn
        end
        local addBtn = sidebar._addCatBtn
        addBtn:SetParent(sidebarChild or sidebar)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", 0, y - 4)
        addBtn:SetWidth(sidebarW)
        addBtn:Show()
        y = y - SIDEBAR_BTN_H - 4
    elseif sidebar._addCatBtn then
        sidebar._addCatBtn:Hide()
    end

    if sidebarChild then
        sidebarChild:SetHeight(math.abs(y) + 4)
    end
end

-------------------------------------------------------------------------------
--  Category header pool (for "All Items" view)
-------------------------------------------------------------------------------
local _catHeaders = {}  -- pool of header frames

local function GetOrCreateCatHeader(idx)
    if _catHeaders[idx] then return _catHeaders[idx] end
    local f = CreateFrame("Frame", nil, EUI_Bags)
    f:SetHeight(20)
    f._label = f:CreateFontString(nil, "OVERLAY")
    SetBagFont(f._label, 11)
    f._label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._label:SetTextColor(0.7, 0.7, 0.7)
    f._label:SetJustifyH("LEFT")
    f._hint = f:CreateFontString(nil, "OVERLAY")
    SetBagFont(f._hint, 10)
    f._hint:SetPoint("LEFT", f._label, "RIGHT", 4, 0)
    f._hint:SetTextColor(0.7, 0.7, 0.7, 0.9)
    f._hint:SetJustifyH("LEFT")
    f._hint:SetText("")
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    f._line = f:CreateTexture(nil, "ARTWORK")
    f._line:SetHeight(px)
    f._line:SetPoint("LEFT", f._hint, "RIGHT", 6, 0)
    f._line:SetPoint("RIGHT", f, "RIGHT", -SPACING, 0)
    f._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    _catHeaders[idx] = f
    return f
end

-- Indented subheaders under a category (expansion names) for All Items nesting
local _expSubHeaders = {}

local function GetOrCreateExpSubHeader(idx)
    if _expSubHeaders[idx] then return _expSubHeaders[idx] end
    local f = CreateFrame("Frame", nil, EUI_Bags)
    f:SetHeight(16)
    f._label = f:CreateFontString(nil, "OVERLAY")
    SetBagFont(f._label, 9)
    f._label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._label:SetTextColor(0.55, 0.55, 0.55)
    f._label:SetJustifyH("LEFT")
    _expSubHeaders[idx] = f
    return f
end

-------------------------------------------------------------------------------
--  Scroll Frame + Scrollbar for item grid
-------------------------------------------------------------------------------
local SCROLLBAR_W     = 4   -- thumb width
local SCROLLBAR_HIT_W = 16  -- invisible hit area width
local SCROLL_STEP     = 40  -- pixels per mouse wheel tick
local THUMB_MIN_H     = 20  -- minimum thumb height

local function CreateBagScrollFrame()
    if EUI_Bags._scrollFrame then return end

    local sidebarW = GetSidebarWidth()

    -- ScrollFrame: fills between header, footer, and sidebar
    local sf = CreateFrame("ScrollFrame", nil, EUI_Bags)
    sf:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", sidebarW, -(HEADER_H + 1))
    sf:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    sf:EnableMouseWheel(true)

    -- Scroll child: tall frame that holds all items
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth())
    child:SetHeight(1)  -- updated by RefreshInventory
    child:EnableMouse(false)  -- let clicks pass through to item buttons
    sf:SetScrollChild(child)

    -- Track (always visible)
    local track = CreateFrame("Button", nil, EUI_Bags)
    track:SetWidth(SCROLLBAR_HIT_W)
    track:SetPoint("TOPRIGHT", EUI_Bags, "TOPRIGHT", -1, -(HEADER_H + 1))
    track:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    track:SetFrameLevel(sf:GetFrameLevel() + 5)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetWidth(SCROLLBAR_W)
    trackBg:SetPoint("TOP", track, "TOP", 0, 0)
    trackBg:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    trackBg:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    trackBg:SetColorTexture(1, 1, 1, 0.06)

    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(SCROLLBAR_W)
    thumb:SetColorTexture(1, 1, 1, 0.25)
    thumb:Hide()

    local _isDragging = false
    local _dragStartY = 0
    local _dragStartPct = 0

    local function GetScrollMetrics()
        local scrollRange = sf:GetVerticalScrollRange()
        if not scrollRange or scrollRange <= 0 then return nil end
        local trackH = track:GetHeight()
        local ext = sf:GetHeight() / (sf:GetHeight() + scrollRange)
        local thumbH = math.max(THUMB_MIN_H, trackH * ext)
        local maxTravel = trackH - thumbH
        if maxTravel <= 0 then return nil end
        local pct = sf:GetVerticalScroll() / scrollRange
        return pct, thumbH, maxTravel, scrollRange
    end

    local function UpdateThumb()
        -- Clamp scroll to current range (content may have shrunk)
        local range = sf:GetVerticalScrollRange() or 0
        local cur = sf:GetVerticalScroll()
        if cur > range then sf:SetVerticalScroll(range) end
        local pct, thumbH, maxTravel = GetScrollMetrics()
        if not pct then
            thumb:Hide()
            trackBg:Hide()
            return
        end
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(pct * maxTravel))
        thumb:Show()
        trackBg:Show()
    end

    sf:SetScript("OnMouseWheel", function(_, delta)
        local _, _, _, scrollRange = GetScrollMetrics()
        if not scrollRange then return end
        local cur = sf:GetVerticalScroll()
        local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
        sf:SetVerticalScroll(newVal)
        UpdateThumb()
    end)

    -- Also enable mouse wheel on the main bag frame (items might not cover full area)
    EUI_Bags:EnableMouseWheel(true)
    EUI_Bags:SetScript("OnMouseWheel", function(_, delta)
        local _, _, _, scrollRange = GetScrollMetrics()
        if not scrollRange then return end
        local cur = sf:GetVerticalScroll()
        local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
        sf:SetVerticalScroll(newVal)
        UpdateThumb()
    end)

    -- Thumb dragging (dragUpdate must be declared before OnMouseDown uses it)
    local dragUpdate = CreateFrame("Frame")
    dragUpdate:Hide()
    dragUpdate:SetScript("OnUpdate", function(self)
        if not _isDragging then self:Hide(); return end
        if not IsMouseButtonDown("LeftButton") then
            _isDragging = false; self:Hide()
            thumb:SetColorTexture(1, 1, 1, 0.25)
            return
        end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then _isDragging = false; self:Hide(); return end
        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local deltaY = (_dragStartY - cy / scale)
        local deltaPct = deltaY / maxTravel
        local newPct = math.max(0, math.min(1, _dragStartPct + deltaPct))
        sf:SetVerticalScroll(newPct * scrollRange)
        UpdateThumb()
    end)

    track:RegisterForDrag("LeftButton")
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then return end

        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local trackTop = track:GetTop() * scale
        local cursorLocalY = (trackTop - cy) / scale

        -- Check if cursor is on the thumb
        local thumbTop = pct * maxTravel
        local thumbBot = thumbTop + thumbH
        if cursorLocalY >= thumbTop and cursorLocalY <= thumbBot then
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = pct
            dragUpdate:Show()
        else
            -- Click on track: jump to position
            local clickPct = math.max(0, math.min(1, (cursorLocalY - thumbH / 2) / maxTravel))
            sf:SetVerticalScroll(clickPct * scrollRange)
            UpdateThumb()
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = clickPct
            dragUpdate:Show()
        end
    end)

    track:SetScript("OnMouseUp", function()
        _isDragging = false
    end)

    track:SetScript("OnEnter", function() thumb:SetColorTexture(1, 1, 1, 0.4) end)
    track:SetScript("OnLeave", function()
        if not _isDragging then thumb:SetColorTexture(1, 1, 1, 0.25) end
    end)

    EUI_Bags._scrollFrame = sf
    EUI_Bags._scrollChild = child
    EUI_Bags._scrollTrack = track
    EUI_Bags._scrollThumb = thumb
    EUI_Bags._updateThumb = UpdateThumb
end

-------------------------------------------------------------------------------
--  RefreshInventory
-------------------------------------------------------------------------------
function EUI_Bags:RefreshInventory()
    if not EUI_Bags:IsVisible() then return end

    -- Refreshing during combat (bags opened mid-fight in M+/Delves) is safe: moving already-created
    -- buttons taints nothing; only CREATING a secure ContainerFrameItemButtonTemplate in lockdown
    -- poisons it (UseContainerItem() -> ADDON_ACTION_FORBIDDEN). GetOrCreateSlot returns nil in combat (pre-warmed pool makes this rare); PLAYER_REGEN_ENABLED replays a full refresh for anything skipped.
    if InCombatLockdown() then EUI_Bags._refreshPendingCombat = true end

    -- Category indices shift when the list rebuilds (split-mode set categories
    -- come and go); rebuilt below on first IsGearCategory call, so never stale.
    _gearCatSet = nil

    C_NewItems.ClearAll()

    -- 1. Gather items from all bags (0-4 + reagent bag 5)
    ReleaseAllSlotTables()
    local tempItems = {}
    local emptySlots = {}

    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                local d = AcquireSlotTable()
                d.bag = bag; d.slot = slot; d.info = info; d.itemLink = itemLink
                -- Pre-cache per-item data for RenderButton (zero API calls at render time)
                if itemLink then
                    local _, _, q, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemLink)
                    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    -- Slot-grouping fields (_equipSlot/_classID/_subclassID) are NOT
                    -- pre-cached here: GetArmorySlotBucket fetches them lazily, only
                    -- for gear items and only while Group Armory by Slot is on, so the
                    -- feature costs nothing on the refresh path when disabled.
                    d._giQuality = q
                    d._giBindType = bindType
                    -- Track rank + cooldown: only for types that need them
                    local isGear = IsGearItem(itemLink)
                    d._isGear = isGear
                    d._giIlvl = isGear and BP().showItemlevelInBags ~= false
                        and GetItemLevelAtLocation(loc, itemLink) or nil
                    if isGear and GetUpgradeTrack then
                        local rankText, trackColor = GetUpgradeTrack(itemLink)
                        if rankText and rankText ~= "" then
                            d._giTrackRank = rankText
                            d._giTrackColor = trackColor
                        end
                    end
                    -- Warbound check (warbank dim overlay) + WuE bind check (gear only, when bind-type text is enabled).
                    if loc and C_Item.DoesItemExist(loc) then
                        if C_Bank and C_Bank.IsItemAllowedInBankType then
                            d._isWarbound = C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc)
                        end
                        if isGear and not info.isBound and BP().bagDisplayBindType then
                            d._isWuE = C_Item.IsBoundToAccountUntilEquip(loc)
                        end
                    end
                    -- Keystone data (rare, fast string match gates the API calls)
                    if info.itemID == 180653 or itemLink:find("keystone:", 1, true) then
                        local ksMap, ksLvl = itemLink:match("keystone:[^:]*:(%d+):(%d+)")
                        if ksLvl then
                            d._ksLevel = ksLvl
                            d._ksAbbrev = AbbrevDungeon(tonumber(ksMap))
                            local ok, color = pcall(C_ChallengeMode.GetKeystoneLevelRarityColor, tonumber(ksLvl))
                            if ok and color then
                                d._ksR = color.r; d._ksG = color.g; d._ksB = color.b
                            end
                        end
                    end
                    -- Cooldown (any item can have a cooldown: trinkets, consumables, toys, etc.)
                    local cdStart, cdDur, cdEnable = C_Container.GetContainerItemCooldown(bag, slot)
                    if cdEnable and cdEnable ~= 0 and cdStart > 0 and cdDur > 0 then
                        d._cdStart = cdStart; d._cdDuration = cdDur
                    end
                    -- _isQuest (any quest item, incl. active objectives + starters) drives the gold
                    -- border; _isQuestStarter (questID set but inactive) is Blizzard's "!" and drives the corner marker.
                    local qInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
                    if qInfo and (qInfo.isQuestItem or qInfo.questID) then
                        d._isQuest = true
                        if qInfo.questID and not qInfo.isActive then
                            d._isQuestStarter = true
                        end
                    end
                end
                tempItems[#tempItems + 1] = d
            else
                local d = AcquireSlotTable()
                d.bag = bag; d.slot = slot
                emptySlots[#emptySlots + 1] = d
            end
        end
    end

    -- 1b. Detect manual item swaps and update saved visual order
    local isAllItems = selectedCategoryIndex == 0 and not selectedGroupName
    local swapDetected = DetectAndApplySwaps(tempItems, isAllItems)
    TakeBagSnapshot(tempItems)

    -- Show blocked-swap tooltip in category/group views (not All Items, not OneBag)
    if swapDetected and not isAllItems and selectedCategoryIndex ~= -1 and selectedCategoryIndex ~= -2 then
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(EUI_Bags, "Positions can only be changed\nin the All Items, OneBag, or MultiBag views", { anchor = "cursor" })
            C_Timer.After(3, function()
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)
        end
    end

    -- 2. Classify all items and get counts
    local categoryCounts, totalCount = EUI_CategoryManager:ClassifyAll(tempItems)

    -- 2a. Snapshot slot->category mapping for partial refresh
    wipe(_slotCategories)
    for _, data in ipairs(tempItems) do
        if data.categoryIndex and data.bag and data.slot then
            _slotCategories[data.bag * 1000 + data.slot] = data.categoryIndex
        end
    end

    -- 2b. Compute display-only counts (pinned + recent stay in normal categories)
    local recentCatIdx, pinnedCatIdx
    do
        local cats = EUI_CategoryManager:GetCategories()
        for i, cat in ipairs(cats) do
            if cat.isRecent then recentCatIdx = i end
            if cat.isPinned then pinnedCatIdx = i end
        end
    end
    local recentCount = 0
    local showRecent = BP().bagShowRecentItems ~= false
    if recentCatIdx and EUI_Bags._recentItems and showRecent then
        for _, data in ipairs(tempItems) do
            if data.info and data.info.itemID and EUI_Bags._recentItems[data.info.itemID] then
                recentCount = recentCount + 1
            end
        end
        categoryCounts[recentCatIdx] = recentCount
    end
    local showPinned = BP().bagShowPinnedItems ~= false
    local pinnedSet = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
    if pinnedCatIdx and pinnedSet and showPinned then
        local pinnedCount = 0
        for _, data in ipairs(tempItems) do
            if data.info and data.info.itemID and pinnedSet[data.info.itemID] then
                pinnedCount = pinnedCount + 1
            end
        end
        categoryCounts[pinnedCatIdx] = pinnedCount
    end

    -- 3. Update sidebar
    BuildSidebarButtons(categoryCounts, totalCount)

    -- Cache counts for partial refresh
    _lastCatCounts = categoryCounts
    _lastTotalCount = totalCount

    -- 4. Filter items by selected category/group + search
    local isRecentView = recentCatIdx and selectedCategoryIndex == recentCatIdx
    local isPinnedView = pinnedCatIdx and selectedCategoryIndex == pinnedCatIdx
    local filterSet = nil  -- nil = show all
    do
        local cats = EUI_CategoryManager:GetCategories()
        -- The "Item Set Gear" anchor view (and any group holding it) folds in the
        -- split-mode set children, which hold the actual items.
        local function AddSetChildren(anchorIdx)
            if not BP().bagSplitSetGearBySet then return end
            if not (cats[anchorIdx] and cats[anchorIdx].isSetGear and not cats[anchorIdx].isEquipSet) then return end
            for i, c in ipairs(cats) do
                if c.isEquipSet then filterSet[i] = true end
            end
        end
        if selectedGroupName then
            filterSet = {}
            local members = EUI_CategoryManager:GetGroupMembers(selectedGroupName)
            for _, mi in ipairs(members) do
                filterSet[mi] = true
                AddSetChildren(mi)
            end
        elseif selectedCategoryIndex > 0 and not isRecentView and not isPinnedView then
            filterSet = { [selectedCategoryIndex] = true }
            AddSetChildren(selectedCategoryIndex)
        end
    end

    local displayItems = {}
    for _, data in ipairs(tempItems) do
        local show = true
        if isRecentView then
            show = data.info and data.info.itemID and EUI_Bags._recentItems and EUI_Bags._recentItems[data.info.itemID]
        elseif isPinnedView then
            show = data.info and data.info.itemID and pinnedSet and pinnedSet[data.info.itemID]
        elseif filterSet then
            show = data.categoryIndex and filterSet[data.categoryIndex]
        end
        if show and data.info and data.info.isFiltered then show = false end
        if show then displayItems[#displayItems + 1] = data end
    end

    -- 4b. Pending resort: sort + save order for categories invalidated by group changes (reuses already-scanned tempItems, no bag re-scan).
    if next(_pendingResortCats) or next(_pendingResortGroups) then
        local cats = EUI_CategoryManager:GetCategories()
        local itemsByCat = {}
        for _, data in ipairs(tempItems) do
            local ci = data.categoryIndex
            if ci then
                if not itemsByCat[ci] then itemsByCat[ci] = {} end
                itemsByCat[ci][#itemsByCat[ci] + 1] = data
            end
        end
        for ci in pairs(_pendingResortCats) do
            local items = itemsByCat[ci] or {}
            if #items > 1 then PreCacheSortFields(items); table.sort(items, VisualSortCompare) end
            SaveCategoryOrder(ci, items)
        end
        for gn in pairs(_pendingResortGroups) do
            local members = EUI_CategoryManager:GetGroupMembers(gn)
            if members and #members > 0 then
                local merged = {}
                for _, mi in ipairs(members) do
                    for _, data in ipairs(itemsByCat[mi] or {}) do
                        merged[#merged + 1] = data
                    end
                end
                if #merged > 1 then PreCacheSortFields(merged); table.sort(merged, VisualSortCompare) end
                SaveCategoryOrder(gn, merged)
            end
        end
        wipe(_pendingResortCats)
        wipe(_pendingResortGroups)
    end


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

    -- Auto-size: pick a column count keeping the window near its base shape (columns grow
    -- ~sqrt of slot count) while fitting the active tab. Grows only, never shrinks while open
    -- (running max in _asCols, reset on close); HEIGHT follows rendered content up to the screen cap. Decided BEFORE GetColumns() so the grid renders at this count.
    if BP().bagAutoSize then
        local baseCols = BP().bagColumns or 12
        local BASE_ROWS = 15  -- rows visible at the base (FIXED_H) height
        local HDR = 0.74      -- section-header height in slot-row units (~28/38)
        -- Slot count (n) + section-header count (S) for the active tab. Headers add HEIGHT
        -- but not WIDTH, so they MUST fold into the estimate or a header-heavy tab (All Items with many categories) grows taller than wide.
        local n, S
        if selectedCategoryIndex > 0 and not selectedGroupName then
            n = (categoryCounts and categoryCounts[selectedCategoryIndex]) or #tempItems
            -- The anchor view folds in its set children's items; count them too
            if BP().bagSplitSetGearBySet then
                local szCats = EUI_CategoryManager:GetCategories()
                local selCat = szCats[selectedCategoryIndex]
                if selCat and selCat.isSetGear and not selCat.isEquipSet and categoryCounts then
                    for i, c in ipairs(szCats) do
                        if c.isEquipSet then n = n + (categoryCounts[i] or 0) end
                    end
                end
            end
            S = 1
        elseif selectedCategoryIndex == 0 and not selectedGroupName then
            -- All Items: one section per non-empty category
            n = #tempItems + #emptySlots
            S = 0
            if categoryCounts then
                -- Set children fold into their anchor's section: count them as one
                local sizeCats = BP().bagSplitSetGearBySet and EUI_CategoryManager:GetCategories() or nil
                local hasSetChild = false
                for i, c in pairs(categoryCounts) do
                    if c and c > 0 then
                        if sizeCats and sizeCats[i] and sizeCats[i].isEquipSet then hasSetChild = true
                        else S = S + 1 end
                    end
                end
                if hasSetChild then S = S + 1 end
            end
            if S < 1 then S = 1 end
        elseif selectedCategoryIndex == -2 then
            -- MultiBag: one section per bag that has slots (+ reagent)
            n = #tempItems + #emptySlots
            S = 0
            for bag = 0, 5 do if C_Container.GetContainerNumSlots(bag) > 0 then S = S + 1 end end
            if S < 1 then S = 1 end
        else
            -- OneBag / group view: a few sections (pinned/recent/main/reagent)
            n = #tempItems + #emptySlots
            S = 3
        end
        n = math.max(n, 1)
        local ideal = baseCols
        -- Only grow when the tab won't fit at the base column count.
        if math.ceil(n / baseCols) + math.ceil(HDR * S) > BASE_ROWS then
            -- Cols such that item+header rows keep the base rows:cols slope (grow together):
            -- solve A*cols^2 - HDR*S*cols - n = 0, where A = BASE_ROWS/baseCols.
            local A = BASE_ROWS / baseCols
            local hs = HDR * S
            ideal = math.ceil((hs + math.sqrt(hs * hs + 4 * A * n)) / (2 * A))
        end
        local sbW = GetSidebarWidth()
        local sc = EUI_Bags:GetScale(); if not sc or sc <= 0 then sc = 1 end
        local maxGridW = (UIParent:GetWidth() / sc) * 0.95 - sbW - 30
        local maxCols = math.max(baseCols, math.floor(maxGridW / (SLOT_SIZE + SPACING)))
        if ideal < baseCols then ideal = baseCols end
        if ideal > maxCols then ideal = maxCols end
        EUI_Bags._asCols = math.max(EUI_Bags._asCols or baseCols, ideal)
    end

    local columns = GetColumns()
    local sidebarW = GetSidebarWidth()
    local gridPadX = 10
    local gridW = columns * (SLOT_SIZE + SPACING)
    local scrollbarPad = SCROLLBAR_HIT_W + 2

    -- Update scroll frame left edge to track sidebar width
    local sf = EUI_Bags._scrollFrame
    local child = EUI_Bags._scrollChild
    if sf then
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", sidebarW, -(HEADER_H + 1))
        sf:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    end
    if child then
        child:SetWidth(gridW + gridPadX * 2 + scrollbarPad)
    end

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
                    if d.info and d.info.itemID and pinnedSet[d.info.itemID] then
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
                    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Hides Pinned Items. Re-show in settings.") end
                end)
                hb:SetScript("OnLeave", function(self)
                    self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
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
                    if d.info and d.info.itemID and EUI_Bags._recentItems[d.info.itemID] then
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
                    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Hides Recent Items. Re-show in settings.") end
                end)
                hb:SetScript("OnLeave", function(self)
                    self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
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
            recHdr._line:ClearAllPoints()
            recHdr._line:SetPoint("LEFT", recHdr._hint, "RIGHT", 6, 0)
            recHdr._line:SetPoint("RIGHT", recHdr._hideBtn, "LEFT", -6, 0)
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

        if not isMulti then
            -- OneBag: Main Bags (0-4) merged, in bag:slot order
            local mainSlots = {}
            local mainFilled = 0
            for _, d in ipairs(tempItems) do
                if d.bag ~= 5 then mainSlots[#mainSlots + 1] = d; mainFilled = mainFilled + 1 end
            end
            for _, d in ipairs(emptySlots) do
                if d.bag ~= 5 then mainSlots[#mainSlots + 1] = d end
            end
            table.sort(mainSlots, function(a, b)
                if a.bag ~= b.bag then return a.bag < b.bag end
                return a.slot < b.slot
            end)
            RenderBagGrid(EllesmereUI.Lf("Main Bags (%d / %d)", mainFilled, #mainSlots), mainSlots)
        else
            -- MultiBag: one section per equipped bag (0-4)
            local function BagDisplayName(bag)
                if bag == 0 then return EllesmereUI.L("Backpack") end
                local invID = C_Container.ContainerIDToInventoryID(bag)
                local link = invID and GetInventoryItemLink("player", invID)
                return (link and GetItemInfo(link)) or EllesmereUI.Lf("Bag %d", bag)
            end
            for bag = 0, 4 do
                local bagList = {}
                local bagFilled = 0
                for _, d in ipairs(tempItems) do
                    if d.bag == bag then bagList[#bagList + 1] = d; bagFilled = bagFilled + 1 end
                end
                for _, d in ipairs(emptySlots) do
                    if d.bag == bag then bagList[#bagList + 1] = d end
                end
                if #bagList > 0 then
                    table.sort(bagList, function(a, b) return a.slot < b.slot end)
                    RenderBagGrid(BagDisplayName(bag) .. " (" .. bagFilled .. " / " .. #bagList .. ")", bagList)
                end
            end
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
                ApplySavedOrder(i, itemsByCat[i])
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
                        if EUI.ShowWidgetTooltip then
                            EUI.ShowWidgetTooltip(self, self._tooltip)
                        end
                    end)
                    hb:SetScript("OnLeave", function(self)
                        self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
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
                hdr._line:ClearAllPoints()
                hdr._line:SetPoint("LEFT", hdr._hint, "RIGHT", 6, 0)
                hdr._line:SetPoint("RIGHT", hdr._hideBtn, "LEFT", -6, 0)
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
        for ci, cat in ipairs(cats) do
            if cat.isPinned then
                -- Pinned Items: display-only duplicate (items also appear in their normal category)
                if pinnedSet and showPinned then
                    local pinItems = {}
                    for _, data in ipairs(displayItems) do
                        if data.info and data.info.itemID and pinnedSet[data.info.itemID] then
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
                        if data.info and data.info.itemID and EUI_Bags._recentItems[data.info.itemID] then
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
                    table.sort(memberItems, VisualSortCompare)
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
                    table.sort(displayItems, VisualSortCompare)
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
                        local ci = selectedCategoryIndex
                        if ci and ci > 0 and EUI_CategoryManager then
                            EUI:ShowConfirmPopup({
                                title = "Delete Category",
                                message = EllesmereUI.L("Are you sure you want to delete this category? All item assignments will be removed."),
                                confirmText = "Delete",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    EUI_CategoryManager:RemoveCustomCategory(ci)
                                    selectedCategoryIndex = 0
                                    selectedGroupName = nil
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
                        local ci = selectedCategoryIndex
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

    local contentH = math.abs(curY) + 10
    if child then child:SetHeight(contentH) end

    -- Update scroll frame position + thumb (deferred one frame so layout updates scrollRange)
    if sf then
        sf:SetVerticalScroll(math.min(sf:GetVerticalScroll(), sf:GetVerticalScrollRange()))
    end
    C_Timer.After(0, function()
        if EUI_Bags._updateThumb then EUI_Bags._updateThumb() end
    end)

    -- Update scroll track left position to match sidebar
    if EUI_Bags._scrollTrack then
        EUI_Bags._scrollTrack:ClearAllPoints()
        EUI_Bags._scrollTrack:SetPoint("TOPRIGHT", EUI_Bags, "TOPRIGHT", -1, -(HEADER_H + 1))
        EUI_Bags._scrollTrack:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    end

    -- 6. Size frame. Default: fixed height, dynamic width. Auto-size: height grows to fit content
    -- (no vertical scroll), width follows column count; both track a running max while open (never shrink mid-session), floored at FIXED_H and capped at the screen.
    local FIXED_H = 650
    local gridContentW = gridW + gridPadX * 2 + scrollbarPad + 2
    local totalW = sidebarW + gridContentW
    if BP().bagAutoSize then
        EUI_Bags._asMaxGridW = math.max(EUI_Bags._asMaxGridW or 0, gridContentW)
        totalW = sidebarW + EUI_Bags._asMaxGridW
    end
    local currencyFooterH = UpdateCurrencyDisplays(totalW) or FOOTER_H

    if BP().bagAutoSize then
        local sc = EUI_Bags:GetScale(); if not sc or sc <= 0 then sc = 1 end
        local maxH = (UIParent:GetHeight() / sc) * 0.95
        -- Cap at the screen first, then floor at FIXED_H so the window is never smaller than normal (even on short screens).
        local neededH = math.max(FIXED_H, math.min(contentH + HEADER_H + currencyFooterH + 2, maxH))
        EUI_Bags._asMaxH = math.max(EUI_Bags._asMaxH or 0, neededH)
        EUI_Bags:SetWidth(totalW)
        EUI_Bags:SetHeight(EUI_Bags._asMaxH)
    else
        EUI_Bags:SetWidth(totalW)
        EUI_Bags:SetHeight(FIXED_H + currencyFooterH - FOOTER_H)
    end

    if EUI_Bags.Header and EUI_Bags.Header.itemCount then
        if selectedCategoryIndex == 0 or selectedCategoryIndex == -1 or selectedCategoryIndex == -2 then
            local totalSlots = totalCount + #emptySlots
            EUI_Bags.Header.itemCount:SetText(EllesmereUI.Lf("%d / %d Items", totalCount, totalSlots))
        else
            EUI_Bags.Header.itemCount:SetText(EllesmereUI.Lf("%d Items", totalCount))
        end
    end

    -- Dice button: OneBag only (unless hidden by setting), parented to the scroll child and anchored to the first category header.
    if EUI_Bags._diceBtn then
        local showDice = selectedCategoryIndex == -1
            and not (BP().bagHideRandomize)
        if showDice and EUI_Bags._scrollChild then
            local child = EUI_Bags._scrollChild
            EUI_Bags._diceBtn:SetParent(child)
            EUI_Bags._diceBtn:ClearAllPoints()
            EUI_Bags._diceBtn:SetPoint("TOPRIGHT", child, "TOPRIGHT", -9, -5)
            EUI_Bags._diceBtn:SetFrameLevel(child:GetFrameLevel() + 20)
            EUI_Bags._diceBtn:Show()
        else
            EUI_Bags._diceBtn:Hide()
        end
    end

    UpdateBagMoneyDisplay()
end

-------------------------------------------------------------------------------
--  Reagent Bag Refresh
-------------------------------------------------------------------------------
function EUI_BagsReagent:RefreshInventory()
    if not EUI_BagsReagent:IsVisible() then return end
    -- Same secure-button rule as EUI_Bags:RefreshInventory: viewing in combat is fine, creating is not (GetOrCreateReagentSlot refuses); mark pending so combat-end tops up.
    if InCombatLockdown() then EUI_Bags._refreshPendingCombat = true end
    local tempItems = {}
    local numSlots = C_Container.GetContainerNumSlots(5)
    if numSlots > 0 then
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(5, slot)
            tempItems[#tempItems + 1] = { bag = 5, slot = slot, info = info }
        end
    end

    for _, btn in pairs(reagentSlots) do btn:GetParent():Hide() end

    local startX, startY = 15, -45
    local REAGENT_COLUMNS = 4
    for i, data in ipairs(tempItems) do
        local btn = GetOrCreateReagentSlot(i)
        if btn then  -- nil during combat (avoids minting tainted secure buttons)
        local parent = btn:GetParent()
        parent:ClearAllPoints()
        parent:Show()
        btn:Show()
        btn:SetID(data.slot)
        parent:SetID(data.bag)
        local itemLink = data.info and C_Container.GetContainerItemLink(data.bag, data.slot)

        if not data.info then
            btn:SetItemButtonTexture(nil)
            btn:SetItemButtonCount(0)
            SetItemButtonDesaturated(btn, false)
            if btn.icon then btn.icon:Hide() end
            if btn.ItemLevelText then btn.ItemLevelText:SetText("") end
            SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)
        else
            if btn.icon then btn.icon:Show() end
            btn:SetItemButtonTexture(data.info.iconFileID)
            btn:SetItemButtonCount(data.info.stackCount)
            SetItemButtonDesaturated(btn, data.info.isLocked)
            local filtered = data.info.isFiltered
            btn:SetAlpha(filtered and 0.2 or 1)
            if btn._textOverlay then btn._textOverlay:SetAlpha(filtered and 0.2 or 1) end

            if btn.ItemLevelText and data.info.itemID then
                local showItemlevel = BP().showItemlevelInBags ~= false
                if showItemlevel then
                    if itemLink then
                        local _, _, quality = GetItemInfo(itemLink)
                        if IsGearItem(itemLink) then
                            local loc = ItemLocation:CreateFromBagAndSlot(data.bag, data.slot)
                            local level = GetItemLevelAtLocation(loc, itemLink)
                            local fs = BP().itemlevelFontSize or 12
                            btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, fs, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                            btn.ItemLevelText:SetText(level or "")
                            local r, g, b
                            if BP().itemlevelUseCustomColor and BP().itemlevelCustomColor then
                                r, g, b = BP().itemlevelCustomColor.r, BP().itemlevelCustomColor.g, BP().itemlevelCustomColor.b
                            else
                                r, g, b = GetItemQualityColor(quality or 1)
                            end
                            btn.ItemLevelText:SetTextColor(r, g, b, 1)
                        else btn.ItemLevelText:SetText("") end
                    else btn.ItemLevelText:SetText("") end
                else btn.ItemLevelText:SetText("") end
            end

            local quality = data.info.quality or 1
            local c = ITEM_QUALITY_COLORS[quality]
            if c then SetInsetBorderColor(btn, c.r, c.g, c.b, 1)
            else SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1) end
        end
        UpdatePawnArrow(btn, itemLink)

        local col = (i - 1) % REAGENT_COLUMNS
        local row = math.floor((i - 1) / REAGENT_COLUMNS)
        parent:SetPoint("TOPLEFT", startX + (col * (SLOT_SIZE + SPACING)), startY - (row * (SLOT_SIZE + SPACING)))
        end
    end

    EUI_BagsReagent:SetWidth((REAGENT_COLUMNS * (SLOT_SIZE + SPACING)) + 30)
    EUI_BagsReagent:SetHeight(math.abs(startY) + (math.ceil(#tempItems / REAGENT_COLUMNS) * (SLOT_SIZE + SPACING)) + 40)
end

function EUI_BagsWindow:RefreshBags()
    if not EUI_BagsWindow:IsVisible() then return end
    for _, btn in pairs(bagSlots) do btn:GetParent():Hide() end
    local startX, startY = 10, -10
    local BAG_COLUMNS = 6
    for i = 0, 5 do
        local displayIdx = i + 1
        local btn = GetOrCreateBagSlot(displayIdx)
        local parent = btn:GetParent()
        btn:SetID(i)
        parent:Show()
        local invID = C_Container.ContainerIDToInventoryID(i)
        local texture = GetInventoryItemTexture("player", invID)
        local quality = GetInventoryItemQuality("player", invID) or 0
        local free = C_Container.GetContainerNumFreeSlots(i)
        local total = C_Container.GetContainerNumSlots(i)
        if i == 0 then btn.icon:SetTexture(133633)
        elseif texture then btn.icon:SetTexture(texture)
        else btn.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag") end
        if total > 0 then btn.Count:SetText(free); btn.Count:Show()
        else btn.Count:Hide() end
        local c = ITEM_QUALITY_COLORS[quality]
        local bdrR, bdrG, bdrB
        if c and quality > 0 then
            bdrR, bdrG, bdrB = c.r, c.g, c.b
        else
            bdrR, bdrG, bdrB = 0.25, 0.25, 0.25
        end
        SetInsetBorderColor(btn, bdrR, bdrG, bdrB, 1)
        btn._bdrR, btn._bdrG, btn._bdrB = bdrR, bdrG, bdrB

        -- Tooltip: bag name + free/total slots (computed live on hover)
        local bagIdx = i
        btn:SetScript("OnEnter", function(self)
            SetInsetBorderColor(self, 1, 1, 1, 1)
            if EUI.ShowWidgetTooltip then
                local bName
                if bagIdx == 0 then
                    bName = "Backpack"
                else
                    local bInvID = C_Container.ContainerIDToInventoryID(bagIdx)
                    local bLink = GetInventoryItemLink("player", bInvID)
                    bName = bLink and GetItemInfo(bLink) or EUI.Lf("Bag %1$d", bagIdx)
                end
                local bTotal = C_Container.GetContainerNumSlots(bagIdx)
                local bFree = C_Container.GetContainerNumFreeSlots(bagIdx)
                local tip = bName
                if bTotal > 0 then tip = tip .. "  (" .. (bTotal - bFree) .. "/" .. bTotal .. ")" end
                EUI.ShowWidgetTooltip(self, tip)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            SetInsetBorderColor(self, self._bdrR, self._bdrG, self._bdrB, 1)
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        end)

        parent:ClearAllPoints()
        parent:SetPoint("TOPLEFT", EUI_BagsWindow, "TOPLEFT", startX + (i * (SLOT_SIZE + SPACING)), startY)
    end
    EUI_BagsWindow:SetSize((BAG_COLUMNS * (SLOT_SIZE + SPACING)) + 15, SLOT_SIZE + 20)
end

-------------------------------------------------------------------------------
--  StartAddon
-------------------------------------------------------------------------------
local function StartAddon()
    RegisterPawnIntegration()

    -- Apply default view based on setting (DB now available)
    local _dbt = GetDefaultBagType()
    if _dbt == "onebag" then
        selectedCategoryIndex = -1
    elseif _dbt == "multibag" then
        selectedCategoryIndex = -2
    end

    InitializeCharacterGold()
    if BP().enableGoldTracking ~= false then
        CaptureTrackedGold()
    end

    -- Position: default 50px from bottom-left, saved position overrides
    if BP().bagsPosition then
        local pos = BP().bagsPosition
        EUI_Bags:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        EUI_Bags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 50)
    end

    EUI_Bags:SetClampedToScreen(true)
    EUI_Bags:SetFrameStrata("HIGH")
    EUI_Bags:SetFrameLevel(100)
    EUI_Bags:EnableMouse(true)
    EUI_Bags:SetMovable(true)

    -- Bag frame drag: shift+click, OnMouseDown/OnUpdate pattern (no RegisterForDrag)
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
        local noShift = BP().bagMoveNoShift
        if button ~= "LeftButton" or (not noShift and not IsKeyDown("LSHIFT")) then return end
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

    EUI_Bags:HookScript("OnShow", function()
        CaptureTrackedGold()
        -- Repaint if the unmerge state changed while hidden: the flag-flip refresh is gated on
        -- IsVisible, and closing a mailbox hides bags in the same breath so that repaint is thrown away (costs one boolean compare when already matching).
        if _paintedPanelOpen ~= _anyItemPanelOpen then
            EUI_Bags:RefreshInventory()
        end
    end)

    EUI_Bags:HookScript("OnHide", function()
        if EUI_Bags._searchBox then
            EUI_Bags._searchBox:SetText("")
            EUI_Bags._searchBox:ClearFocus()
        end
    end)

    -- Click empty space with an external item on the cursor: auto-place in the first free
    -- bag slot (same as looting), only for items not already in the player's bags (bank withdrawals, mail, etc.).
    EUI_Bags:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        local cursorType, cursorItemID, cursorLink = GetCursorInfo()
        if cursorType ~= "item" then return end
        -- Check if the cursor item is from the player's bags (bag 0-4)
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.isLocked then
                    -- Locked = this slot is the pickup source
                    return
                end
            end
        end
        -- External item: place in first empty bag slot
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                if not C_Container.GetContainerItemInfo(bag, slot) then
                    C_Container.PickupContainerItem(bag, slot)
                    return
                end
            end
        end
    end)

    CreateHeader()
    CreateFooter()
    CreateSidebar()
    CreateBagScrollFrame()
    CreateReagentBagUI()

    -- Bag overview window
    EUI_BagsWindow:SetSize(280, 80)
    EUI_BagsWindow:SetPoint("BOTTOMRIGHT", EUI_Bags._bagsBtn, "TOPRIGHT", 0, 2)
    EUI_BagsWindow:SetFrameStrata("HIGH")
    EUI_BagsWindow:EnableMouse(true)
    EUI_BagsWindow.bg = EUI_BagsWindow:CreateTexture(nil, "BACKGROUND")
    EUI_BagsWindow.bg:SetAllPoints()
    EUI_BagsWindow.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(EUI_BagsWindow, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end
    EllesmereUI.RegisterEscapeClose(EUI_BagsWindow)

    EUI_BagsReagent:SetSize(320, 300)
    EUI_BagsReagent:SetPoint("BOTTOMRIGHT", EUI_Bags, "BOTTOMLEFT", -10, 0)
    EUI_BagsReagent:SetFrameStrata("HIGH")
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

    local OriginalToggleAllBags = ToggleAllBags
    local function ToggleEUI()
        if EUI_Bags:IsVisible() then
            EUI_Bags:Hide()
            EUI_BagsReagent:Hide()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.bagsVisible = false
        else
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

    local _lastToggleTime = 0
    local function SmartToggleBags()
        -- Debounce: Blizzard keybinds can fire both ToggleAllBags and C_Container.ToggleAllBags in the same frame, causing a double-toggle.
        if GetTime() == _lastToggleTime then return end
        _lastToggleTime = GetTime()
        local enhancedEnabled = BP().enhancedBags ~= false
        if enhancedEnabled then ToggleEUI()
        else if OriginalToggleAllBags then OriginalToggleAllBags() end end
    end

    ToggleAllBags = SmartToggleBags
    -- Hook ToggleBackpack/ToggleBag via hooksecurefunc (avoids tainting the global)
    hooksecurefunc("ToggleBackpack", SmartToggleBags)
    hooksecurefunc("ToggleBag", function() SmartToggleBags() end)

    -- Hide Blizzard bag frames by reparenting to a hidden container (never write .Show/.Hide onto Blizzard frames -- causes taint).
    local _blizzBagHidden = CreateFrame("Frame")
    _blizzBagHidden:Hide()

    local function KillBlizzard()
        for i = 1, 13 do
            local f = _G["ContainerFrame"..i]
            if f then f:SetParent(_blizzBagHidden) end
        end
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:SetParent(_blizzBagHidden)
        end
    end
    KillBlizzard()

    hooksecurefunc("OpenAllBags", function()
        if not EUI_Bags:IsVisible() then ToggleEUI() end
        KillBlizzard()
    end)

    -- Recent Items: session-only tracking (resets on login/reload)
    local RECENT_MAX = 12
    EUI_Bags._recentItems = {}      -- itemID -> true (set of recent item IDs)
    EUI_Bags._recentOrder = {}      -- ordered list of itemIDs (oldest first)
    local _knownItemCounts = {} -- itemID -> highest stack count seen this session
    local _snapshotReady = false

    -- Track the highest count ever seen per itemID, not current presence: a stack
    -- merge (already have 3, loot 1 more) must register as a new pickup, and a
    -- plain presence set can't see that. Tracking the max instead of the live
    -- count (and never lowering it) also means unequipping/re-equipping, banking,
    -- or mailing an item back to yourself doesn't re-flag it as new.
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
        return counts, order
    end

    local function SnapshotKnownIDs()
        _knownItemCounts = TallyItemCounts()
        _snapshotReady = true
    end

    local function DetectNewItems()
        if not _snapshotReady then return end
        local counts, order = TallyItemCounts()
        for _, itemID in ipairs(order) do
            local count = counts[itemID]
            if count > (_knownItemCounts[itemID] or 0) then
                _knownItemCounts[itemID] = count
                if not EUI_Bags._recentItems[itemID] then
                    EUI_Bags._recentItems[itemID] = true
                    EUI_Bags._recentOrder[#EUI_Bags._recentOrder + 1] = itemID
                    while #EUI_Bags._recentOrder > RECENT_MAX do
                        local old = table.remove(EUI_Bags._recentOrder, 1)
                        EUI_Bags._recentItems[old] = nil
                    end
                end
            end
        end
    end

    C_Timer.After(1, function() SnapshotKnownIDs() end)

    -- Debounced full refresh: one code path, no stale state.
    local refreshPending = false
    EUI_Bags.refreshEnabled = true
    local function ScheduleRefresh()
        if not EUI_Bags.refreshEnabled or refreshPending then return end
        refreshPending = true
        C_Timer.After(0.1, function()
            if EUI_Bags:IsVisible() then
                EUI_Bags:RefreshInventory()
                local detach = BP().detachReagentBag or false
                if detach and EUI_BagsReagent:IsVisible() then EUI_BagsReagent:RefreshInventory() end
            end
            refreshPending = false
        end)
    end

    EUI_Bags:RegisterEvent("BAG_UPDATE")
    EUI_Bags:RegisterEvent("PLAYER_MONEY")
    EUI_Bags:RegisterEvent("ITEM_LOCK_CHANGED")
    EUI_Bags:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
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
    EUI_Bags:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Panels that move items one bag slot at a time (see SetItemPanelOpen).
    local ITEM_PANEL_EVENTS = {
        -- No MAIL_SHOW: the Inbox never takes items OUT of bags, so unmerging there churns for
        -- nothing -- only Send Mail matters (hooked below). MAIL_CLOSED is a belt against a stuck flag if the frame vanishes without its OnHide running.
        MAIL_CLOSED           = { "sendmail",  false },
        TRADE_SHOW            = { "trade",     true  },
        TRADE_CLOSED          = { "trade",     false },
        AUCTION_HOUSE_SHOW    = { "auction",   true  },
        AUCTION_HOUSE_CLOSED  = { "auction",   false },
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
    -- in lockdown is tainted (UseContainerItem() blocked in M+/Delves), so build every button we could need up front and let RefreshInventory only position/show clean ones.
    do
        local total = 0
        for bag = 0, 5 do
            total = total + (C_Container.GetContainerNumSlots(bag) or 0)
        end
        for i = 1, total do
            local b = GetOrCreateSlot(i)
            if b and b:GetParent() then b:GetParent():Hide() end
        end
        -- Reagent bag (bag 5) has its own secure-button pool; pre-warm it too.
        local reagentSlotsN = C_Container.GetContainerNumSlots(5) or 0
        for i = 1, reagentSlotsN do
            local b = GetOrCreateReagentSlot(i)
            if b and b:GetParent() then b:GetParent():Hide() end
        end
    end

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
            if EllesmereUI and EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
        end, EUI_Bags)
    end

    -- DetectNewItems: run synchronously but at most once per frame (zone changes fire many BAG_UPDATEs)
    local _lastDetectFrame = 0

    EUI_Bags:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Combat ended: replay any refresh deferred during combat, and top up the pre-warmed pool in case bag count grew while locked.
            if EUI_Bags._refreshPendingCombat then
                EUI_Bags._refreshPendingCombat = nil
                if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
                if EUI_BagsReagent:IsVisible() and EUI_BagsReagent.RefreshInventory then
                    EUI_BagsReagent:RefreshInventory()
                end
            end
            return
        end
        local panel = ITEM_PANEL_EVENTS[event]
        if panel then
            -- Tracked even while bags are hidden: the panel that opens them (OpenAllBags) can fire in either order with this event.
            if SetItemPanelOpen(panel[1], panel[2]) and EUI_Bags:IsVisible() then
                EUI_Bags:RefreshInventory()
            end
            return
        end
        if event == "EQUIPMENT_SETS_CHANGED" then
            -- Invalidate even while hidden: the next open must not classify with
            -- categories built from the old set list.
            EUI_Bags.InvalidateSetCategories()
            if EUI_Bags:IsVisible() then ScheduleRefresh() end
            return
        end
        if event == "BAG_UPDATE" and EUI_Bags.refreshEnabled ~= false then
            local now = GetTime()
            if now ~= _lastDetectFrame then
                _lastDetectFrame = now
                DetectNewItems()
            end
        end
        if not EUI_Bags:IsVisible() then return end
        if event == "BAG_UPDATE" then
            if EUI_Bags._pendingBagSwap and EUI_BagsWindow:IsVisible() then
                EUI_Bags._pendingBagSwap = nil
                EUI_BagsWindow:RefreshBags()
            end
            if not EUI_Bags.refreshEnabled then return end
            if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
            ScheduleRefresh()
        elseif event == "ITEM_LOCK_CHANGED" then
            if not EUI_Bags.refreshEnabled then return end
            if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
            ScheduleRefresh()
        elseif event == "PLAYER_MONEY" then
            CaptureTrackedGold()
            UpdateBagMoneyDisplay()
        elseif event == "CURRENCY_DISPLAY_UPDATE" then
            SyncBagFrameToFooter()
        end
    end)

    EUI_Bags:HookScript("OnHide", function()
        EUI_BagsWindow:Hide()
    end)

    EllesmereUI.RegisterEscapeClose(EUI_Bags)
end

-------------------------------------------------------------------------------
--  Loader
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0.5, function()
        StartAddon()
        EUI_Bags:Hide()
        EUI_BagsReagent:Hide()

    end)
end)
