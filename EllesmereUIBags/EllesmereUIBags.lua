if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags.lua -- Enhanced Bags System for EllesmereUI (Midnight): sidebar category filter + flat item grid layout.
-------------------------------------------------------------------------------
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
local ns = select(2, ...)
EllesmereUI._ModuleNS["EllesmereUIBags"] = ns  -- LOD options files read this module ns via the registry

EUI_Bags = CreateFrame("Frame", "EUI_MainBagFrame", UIParent)
EUI_Bags:SetToplevel(true)
EUI_Bags:Hide()
-- Auto-size state: reset on close (next open sizes from its first/active tab);
-- while open it only grows, never shrinks.
EUI_Bags:HookScript("OnHide", function(self)
    -- WoW Forever sizes every open to its content: a hidden UI (Alt-Z) is not a close, keep the size.
    if EllesmereUI.IS_FOREVER and self:IsShown() then return end
    self._asCols  = nil
    self._asMaxGridW = nil
    self._asMaxH  = nil
end)

EUI_BagsReagent = CreateFrame("Frame", "EUI_ReagentBagFrame", UIParent)
EUI_BagsReagent:Hide()

EUI_BagsWindow = CreateFrame("Frame", "EUI_BagsWindowFrame", UIParent)
EUI_BagsWindow:Hide()

local SLOT_SIZE, SPACING = 34, 4
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemQualityColor = C_Item.GetItemQualityColor
local IsEquippableItem = C_Item.IsEquippableItem

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
-- WoW Forever: the player's bags (1-4) that hold one kind of item only --
-- quivers, ammo pouches, soul, herb and enchanting bags, by their non-zero bag
-- family. Like the reagent bag they get their own category and sections and
-- stay out of Main Bags, the header count, OneBag's sort, Randomize, Auto
-- Split and drop placement. nil on retail or with none equipped; the next
-- call reuses the set, so read it right away.
do
    local special = {}
    function ns.SpecialBags()
        if not EllesmereUI.IS_FOREVER then return nil end
        wipe(special)
        local any = false
        for bag = 1, 4 do
            local _, family = C_Container.GetContainerNumFreeSlots(bag)
            if family and family ~= 0 then special[bag] = true; any = true end
        end
        return any and special or nil
    end

    -- Auto Split's target bags for a stack in bag, in order: the reagent bag
    -- and a special bag split into themselves first, and no other bag's stack
    -- goes into a special bag.
    function ns.SplitTargetBags(bag)
        local sp = ns.SpecialBags()
        if not sp then
            return bag == 5 and { 5, 0, 1, 2, 3, 4 } or { 0, 1, 2, 3, 4 }
        end
        local t = (sp[bag] or bag == 5) and { bag } or {}
        for b = 0, 4 do
            if not sp[b] then t[#t + 1] = b end
        end
        return t
    end
end
-- Weak-keyed bank-deposit routing state: custom keys written onto a ContainerFrameItemButtonTemplate
-- in PreClick taint the secure execution chain -> UseContainerItem() ADDON_ACTION_FORBIDDEN.
local _bankRouted = setmetatable({}, { __mode = "k" })

local EUI = EllesmereUI
-- Profile access helper (DB created in EUI_Bags_Options.lua, loaded first per TOC)
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end

-- "Show Junk in Recent" (default on): when turned off, junk items (grey +
-- player-marked) are kept out of the Recent Items section. Returns false on the
-- default path with no IsJunk lookup, and is a no-op while the Junk Marker
-- feature is off (IsJunk is false then). Shared by the grid and list recent
-- gatherers. Core loads before Grid/List, so ns has it by the time they run.
function ns.JunkHiddenFromRecent(itemID, quality)
    if BP().bagJunkShowInRecent ~= false then return false end
    return (EUI_CategoryManager and EUI_CategoryManager:IsJunk(itemID, quality)) or false
end

-- Uninstall EUI: Sort to Bottom flips Blizzard's own sort direction, so the
-- player's is handed back, as turning the option off does.
EUI.OnUninstall(function()
    local p = BP()
    if p.bagSortToBottom and p.bagSortBlizzRTLWas ~= nil then
        C_Container.SetSortBagsRightToLeft(p.bagSortBlizzRTLWas)
    end
end)

local layerUpdateFrame = CreateFrame("Frame")
function EUI_Bags:ApplyWindowLayering()
    -- The bank's purchase buttons are secure, so defer layer changes in combat.
    if InCombatLockdown() then
        layerUpdateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    layerUpdateFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local allowOtherWindows = BP().bagAllowWindowsOverBags ~= false
    local strata = allowOtherWindows and "MEDIUM" or "HIGH"
    self:SetFrameStrata(strata)
    self:SetFrameLevel(allowOtherWindows and 1 or 100)
    EUI_BagsWindow:SetFrameStrata(strata)
    EUI_BagsReagent:SetFrameStrata(strata)
    local sf = self._scrollFrame
    if sf and not self._assignSelectMode and not self._pinSelectMode then
        sf:SetFrameStrata(strata)
    end
    local bank = _G.EUI_BankFrame
    if bank and bank.ApplyWindowLayering then bank:ApplyWindowLayering() end
end
layerUpdateFrame:SetScript("OnEvent", function() EUI_Bags:ApplyWindowLayering() end)

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

-- Bag display mode ("grid" | "list"), latched on the first read after the
-- profile loads: switching needs a reload, so only one mode ever builds
-- frames in a session. nil = profile not loaded yet (nothing latched).
local _listMode
function EUI_Bags.IsListMode()
    if _listMode == nil then
        if not EUI.Lite.IsDBReady() then return nil end
        _listMode = BP().bagDisplayMode == "list"
    end
    return _listMode
end

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
-- Pin identity: bare itemID can't distinguish two different upgrade tracks
-- (e.g. Mythic vs Hero) of the same base item -- those share one itemID and
-- only differ in the bonus IDs encoded on the item LINK. The RAW link is not
-- a safe persistent key either: it also embeds linkLevel, specializationID,
-- enchant and gem fields, so the same item's link drifts on level-up, spec
-- swap or re-gem -- a raw-link pin would silently stop matching AND leak its
-- stale entry in the account-global store forever (unpin only removes the
-- current key). The pin key is therefore itemID + the bonus ID list: bonus
-- IDs carry the upgrade track (the exact thing being distinguished) and hold
-- steady across spec, level, enchants and gems. Cached per link string, the
-- same shape as the sort cache -- IsItemPinned runs per item per refresh.
-- itemID stays supported read-only as a legacy fallback: entries written
-- before the link-era fix are itemID-keyed and still match every track, same
-- as before, until the middle-click self-heal clears them.
local pinKeyCache = {}
local function NormalizePinKey(itemLink, itemID)
    if type(itemLink) ~= "string" then return itemID end
    local cached = pinKeyCache[itemLink]
    if cached then return cached end
    local key
    local payload = itemLink:match("|Hitem:([^|]*)|h")
    if payload then
        -- Split keeping empty fields. After "item:": 1 itemID, 2 enchant,
        -- 3-6 gems, 7 suffix, 8 uniqueID, 9 linkLevel, 10 specID,
        -- 11 modifiersMask, 12 itemContext, 13 numBonusIDs, 14.. bonusIDs.
        local f = {}
        for field in (payload .. ":"):gmatch("([^:]*):") do f[#f + 1] = field end
        local id = f[1]
        if id and id ~= "" then
            local n = tonumber(f[13]) or 0
            key = "p" .. id
            for i = 1, n do
                key = key .. ":" .. (f[13 + i] or "")
            end
        end
    end
    key = key or itemID
    if key then pinKeyCache[itemLink] = key end
    return key
end
local function IsItemPinned(pinnedSet, itemLink, itemID)
    if not pinnedSet then return nil end
    local nk = itemLink and NormalizePinKey(itemLink, nil)
    return (nk and pinnedSet[nk]) or (itemID and pinnedSet[itemID])
end
ns.IsItemPinned = IsItemPinned
local function GetItemLevelAtLocation(loc, itemLink)
    if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
        local level = C_Item.GetCurrentItemLevel(loc)
        if level and level > 0 then return level end
    end
    return itemLink and C_Item.GetDetailedItemLevelInfo(itemLink) or nil
end
local function GetFont() return EUI.GetFontPath("bags") end
local function SetBagFont(fs, size)
    EllesmereUI.PrimeFontShadow(fs, true)
    fs:SetFont(GetFont(), size, EUI.GetFontOutlineFlag("bags"))
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

-- Item panels (mail/trade/AH/vendor/bank/guildbank) take one bag slot at a time; a merged button
-- only hands over the slot behind it (3 merged mails would mail 1), so duplicates stay unmerged while any panel is open. bagMergeDuplicates disables merging outright.
local _openItemPanels = {}
local _anyItemPanelOpen = false
-- Unmerge state the CURRENT painted layout was built with; bags OnShow compares against it so a flip while hidden still repaints (closing a mailbox hides both).
local _paintedPanelOpen = false
-- Returns true when the aggregate state flipped and the bags' view merges, so
-- the caller can refresh. A view that does not merge paints the same either
-- way: its painted state just follows, so neither this nor OnShow repaints.
local function SetItemPanelOpen(key, open)
    _openItemPanels[key] = open or nil
    local any = next(_openItemPanels) ~= nil
    if any == _anyItemPanelOpen then return false end
    _anyItemPanelOpen = any
    local merges
    if EUI_Bags.IsListMode() then merges = BP().bagListMergeDuplicates == true
    else merges = BP().bagMergeDuplicates ~= false end
    if not merges then _paintedPanelOpen = any end
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
-- force: skip the bagMergeDuplicates check (list view has its own setting).
-- Must run AFTER ApplySavedOrder so the first occurrence in visual order wins.
-- Returns a new list; the caller's tables are NEVER modified. A merged winner is
-- replaced in the returned list by a pooled, display-only shallow copy carrying
-- the aggregate in _mergedCount. Invariant: only those copies ever carry
-- _mergedCount, which is also the "already a copy" test below. If anyone ever
-- writes _mergedCount back onto a canonical slot table, both break.
-- The result must not outlive the render pass that produced it: the copies come
-- from the slot pool and are recycled by ReleaseAllSlotTables on the next refresh.
local function MergeDuplicates(items, force)
    -- Record what this paint was built with, so the bags OnShow can tell that
    -- the state changed while they were hidden and repaint (see OnShow).
    _paintedPanelOpen = _anyItemPanelOpen
    if _anyItemPanelOpen or (not force and BP().bagMergeDuplicates == false) then return items end
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
    search:SetFont(GetFont(), 12, EUI.GetFontOutlineFlag("bags"))
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
        EUI.ShowWidgetTooltip(self, "Sort Items")
    end)
    sort:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)

    local sortLocked = false
    -- Sorts that move items (OneBag, MultiBag, Randomize) wait out combat; the
    -- other views' sort only reorders the display.
    local function SortMovesItems()
        return selectedCategoryIndex == -1 or selectedCategoryIndex == -2
    end
    -- Sort/randomize buttons are clickable only while no sort runs, and those
    -- that move items only out of combat.
    local function ApplySortEnabled()
        local combat = InCombatLockdown()
        local on = not sortLocked and not (combat and SortMovesItems())
        sort:EnableMouse(on)
        sort.icon:SetAlpha(on and 0.9 or 0.2)
        if EUI_Bags._diceBtn then
            local diceOn = not sortLocked and not combat
            EUI_Bags._diceBtn:EnableMouse(diceOn)
            EUI_Bags._diceBtn.icon:SetAlpha(diceOn and 0.9 or 0.2)
        end
    end
    -- A view switch in combat re-runs it from the refresh (FinishRefresh).
    EUI_Bags._applySortEnabled = ApplySortEnabled
    -- Combat edges only matter while the bags are open; the show edge catches
    -- up on any change while they were closed.
    local combatWatch = CreateFrame("Frame")
    combatWatch:SetScript("OnEvent", ApplySortEnabled)
    EUI_Bags:HookScript("OnShow", function()
        combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        ApplySortEnabled()
    end)
    EUI_Bags:HookScript("OnHide", function()
        combatWatch:UnregisterEvent("PLAYER_REGEN_DISABLED")
        combatWatch:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end)
    -- One reusable BAG_UPDATE listener per role. Both phases are strictly
    -- sequential, and a fresh CreateFrame per round leaked frames per click
    -- (frames are never collected). The run token keeps a second sort from
    -- inheriting the first one's callbacks: EndDragDrop can unlock the button
    -- mid-run, and a stale callback clearing the live chain's OnEvent would
    -- strand it with refreshEnabled false (bags frozen until reload).
    local consolidateFrame, retryFrame
    local function LockSort()
        sortLocked = true
        ApplySortEnabled()
    end
    local function UnlockSort()
        if not sortLocked then return end
        sortLocked = false
        ApplySortEnabled()
    end
    EUI_Bags._unlockSort = UnlockSort

    local DoVisualSort  -- forward declaration

    local function DoPhysicalSort()
        if InCombatLockdown() then return end  -- confirm popup can outlive the pull
        LockSort()
        EUI_Bags.refreshEnabled = false

        local sfxWas = GetCVar("Sound_EnableSFX")
        -- Blizzard's clean-up sound. Sound effects stay muted for the whole
        -- run (item moves), which would cut it short, so it goes out on the
        -- Master channel, and only while the player's sound effects are on
        -- and their volume is above zero.
        if sfxWas == "1" and (tonumber(GetCVar("Sound_SFXVolume")) or 0) > 0 then
            PlaySound(SOUNDKIT.UI_BAG_SORTING_01, "Master")
        end
        EllesmereUI.HoldCVar("Sound_EnableSFX", "0", "EllesmereUIBags")

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
                if InCombatLockdown() then return false end  -- combat started: stop moving items
                local stacks = {}  -- itemID -> { {bag,slot,count}, ... }
                -- A WoW Forever special bag's stacks merge only with each other
                -- (a key of their own), so nothing leaves or enters the bag.
                local special = ns.SpecialBags()
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
                                local key = info.itemID
                                if special and special[bag] then key = bag .. ":" .. key end
                                if not stacks[key] then stacks[key] = {} end
                                stacks[key][#stacks[key] + 1] = {
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
            if InCombatLockdown() then return false end  -- combat started: stop moving items
            bagMin = bagMin or 0
            bagMax = bagMax or 4
            local total = 0
            local sBag, sSlot, sKey, sID = {}, {}, {}, {}

            local items = {}
            -- A WoW Forever special bag adds no slots: its items stay put and
            -- nothing is moved into it.
            local special = ns.SpecialBags()
            for bag = bagMin, bagMax do
                local numSlots = (special and special[bag]) and 0 or C_Container.GetContainerNumSlots(bag)
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
            EllesmereUI.ReleaseCVar("Sound_EnableSFX", sfxWas, "EllesmereUIBags")
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
        if InCombatLockdown() then return end
        PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
        LockSort()
        if BP().bagSortToBottom and C_Container.SetSortBagsRightToLeft then
            C_Container.SetSortBagsRightToLeft(false)
        end
        C_Container.SortBags()
        C_Timer.After(3, UnlockSort)
    end

    sort:SetScript("OnClick", function()
        if sortLocked or (InCombatLockdown() and SortMovesItems()) then return end
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
            -- Sound here, not in DoVisualSort: the first-open auto sort stays silent.
            PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
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
        EUI.ShowWidgetTooltip(self, "Randomize")
    end)
    dice:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.82, 0.7, 0.55)
        self.icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)
    local function DoRandomize()
        if InCombatLockdown() then return end
        LockSort()
        EUI_Bags.refreshEnabled = false

        local slots = {}
        local items = {}
        local special = ns.SpecialBags()  -- WoW Forever: special bags keep their items
        for bag = 0, 4 do
            local numSlots = (special and special[bag]) and 0 or C_Container.GetContainerNumSlots(bag)
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
        EllesmereUI.HoldCVar("Sound_EnableSFX", "0", "EllesmereUIBags")
        for _, m in ipairs(moves) do
            C_Container.PickupContainerItem(m[1], m[2])
            C_Container.PickupContainerItem(m[3], m[4])
            ClearCursor()
        end
        EllesmereUI.ReleaseCVar("Sound_EnableSFX", sfxWas, "EllesmereUIBags")

        C_Timer.After(0.5, function()
            EUI_Bags.refreshEnabled = true
            EUI_Bags:RefreshInventory()
            C_Timer.After(3, UnlockSort)
        end)
    end

    dice:SetScript("OnClick", function()
        if sortLocked or InCombatLockdown() then return end
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
    ApplySortEnabled()  -- a /reload mid-combat builds the buttons locked

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
        EUI.HideWidgetTooltip()
    end)
    bagsBtn:SetScript("OnClick", function()
        if EUI_BagsWindow:IsVisible() then
            EUI_BagsWindow:Hide()
        else
            EUI.HideWidgetTooltip()
            EUI_BagsWindow:Show()
            EUI_BagsWindow:RefreshBags()
        end
    end)
    EUI_Bags._bagsBtn = bagsBtn

    -- Mark-as-Junk button (coin). Anchored to the LEFT of the bags button so it
    -- rides along when "Show Sort Icon" re-anchors that button, and so hiding it
    -- leaves no gap (nothing anchors to the junk button). Only shown while the
    -- Junk Marker feature is enabled; the options toggle flips it live.
    local junk = CreateFrame("Button", nil, header)
    junk:SetSize(22, 22)
    junk:SetPoint("RIGHT", bagsBtn, "LEFT", -6, 0)
    junk.icon = junk:CreateTexture(nil, "OVERLAY")
    junk.icon:SetAllPoints()
    junk.icon:SetTexture(133784)  -- INV_Misc_Coin_01
    junk.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)  -- crop so the round edge is clean
    junk.icon:SetAlpha(0.9)
    -- Rounded look to match the other header buttons: circular alpha mask.
    local jmask = junk:CreateMaskTexture()
    jmask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    jmask:SetAllPoints(junk.icon)
    junk.icon:AddMaskTexture(jmask)
    -- Subtle round border: a thin dark rim just outside the coin so it reads as a
    -- bordered round icon like the other header buttons. ARTWORK sits below the
    -- OVERLAY icon, extended 1px past it, round-masked -> a 1px dark ring.
    junk.ring = junk:CreateTexture(nil, "ARTWORK")
    junk.ring:SetColorTexture(0, 0, 0, 0.85)
    junk.ring:SetPoint("TOPLEFT", junk.icon, "TOPLEFT", -1, 1)
    junk.ring:SetPoint("BOTTOMRIGHT", junk.icon, "BOTTOMRIGHT", 1, -1)
    local jringMask = junk:CreateMaskTexture()
    jringMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    jringMask:SetAllPoints(junk.ring)
    junk.ring:AddMaskTexture(jringMask)
    junk:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, EllesmereUI.L("Mark items as Junk"))
        end
    end)
    junk:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)
    junk:SetScript("OnClick", function()
        EUI.HideWidgetTooltip()
        if EUI_Bags.EnterJunkSelectMode then EUI_Bags:EnterJunkSelectMode() end
    end)
    junk:SetShown(BP().bagJunkMarker == true)
    EUI_Bags._junkBtn = junk

    -- "Sell Junk" text button, to the left of the coin button. Only shown while
    -- a merchant window is open AND the feature is enabled (toggled by the
    -- merchant event handler); hidden otherwise so it never crowds the row.
    local sellJunk = CreateFrame("Button", nil, header)
    sellJunk:SetSize(58, 18)
    sellJunk:SetPoint("RIGHT", junk, "LEFT", -6, 0)
    sellJunk.bg = sellJunk:CreateTexture(nil, "BACKGROUND")
    sellJunk.bg:SetAllPoints()
    sellJunk.bg:SetColorTexture(0, 0, 0, 0.4)
    sellJunk.label = sellJunk:CreateFontString(nil, "OVERLAY")
    SetBagFont(sellJunk.label, 10)
    sellJunk.label:SetPoint("CENTER", 0, 0)
    sellJunk.label:SetText(EllesmereUI.L("Sell Junk"))
    sellJunk.label:SetTextColor(0.85, 0.82, 0.55)
    sellJunk:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 0.96, 0.66)
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, EllesmereUI.L("Sell all Junk items at this merchant. Note: the game only remembers the last 12 sold items for buyback."))
        end
    end)
    sellJunk:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.85, 0.82, 0.55)
        EUI.HideWidgetTooltip()
    end)
    sellJunk:SetScript("OnClick", function()
        EUI.HideWidgetTooltip()
        if EUI_Bags.SellJunk then EUI_Bags:SellJunk() end
    end)
    sellJunk:Hide()
    EUI_Bags._sellJunkBtn = sellJunk
    -- DB is ready by the time the header is built: register the merchant events
    -- now iff the feature is on (the toggle re-syncs them on change).
    if EUI_Bags.SyncJunkMerchantWatcher then EUI_Bags:SyncJunkMerchantWatcher() end

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
        -- Controller cursor: keep Blizzard's hidden bag frames closed too.
        if EUI.PadInUse() then ns.PadReleaseBlizzBags() end
    end)
    -- Controller cursor: Cancel finds each window's close control.
    if EUI.PadCP() then
        EUI_Bags.CloseButton = close
        EUI_BagsWindow.CloseButton = bagsBtn
    end

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
    local fontPath = (EllesmereUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (EllesmereUI.GetFontOutlineFlag("bags")) or ""
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

local TRASH_SIZE = 22

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
    -- Currencies start right of the Trash Can when it is shown
    local trash = EUI_Bags._trashBtn
    local leftOffset = (trash and trash:IsShown()) and (10 + TRASH_SIZE + 8) or 10
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

-- Re-lay-out the currency footer and grow/shrink the bag frame by the height delta (grow-only running max under Auto-Size and on WoW Forever); reads the previous height BEFORE UpdateCurrencyDisplays stamps the new one.
local function SyncBagFrameToFooter()
    local prev = EUI_Bags._footerH or FOOTER_H
    local footerH = UpdateCurrencyDisplays() or FOOTER_H
    if footerH == prev then return end
    if not EUI_Bags:IsVisible() then return end
    local delta = footerH - prev
    if BP().bagAutoSize or (EUI.IS_FOREVER and not BP().bagHeight) then
        EUI_Bags._asMaxH = math.max(EUI_Bags._asMaxH or EUI_Bags:GetHeight() or 0, EUI_Bags:GetHeight() + delta)
        EUI_Bags:SetHeight(EUI_Bags._asMaxH)
    elseif BP().bagHeight then
        -- Grip-set height is the whole window; the content area absorbs it
        return
    else
        EUI_Bags:SetHeight(EUI_Bags:GetHeight() + delta)
    end
end

-------------------------------------------------------------------------------
--  Trash Can (opt-in): a footer button that deletes the cursor item without
--  a popup. Only items Blizzard deletes with a plain yes/no are taken (below
--  Rare, or heirlooms); items that need a typed "DELETE" and quest items go
--  back to their slot. Not created until the setting is turned on.
-------------------------------------------------------------------------------
local function TrashCursorItem()
    local cursorType, _, cursorLink = GetCursorInfo()
    if cursorType ~= "item" or not cursorLink then return end
    local _, _, quality, _, _, _, _, _, _, _, _, classID, _, bindType = C_Item.GetItemInfo(cursorLink)
    local Q = Enum.ItemQuality
    local plain = quality and (quality < Q.Rare or quality == Q.Heirloom)
        and classID ~= Enum.ItemClass.Questitem and bindType ~= Enum.ItemBind.Quest
    if not plain then
        ClearCursor()
        UIErrorsFrame:AddMessage(EllesmereUI.L("Rare and better items and quest items can't go in the Trash Can."), 1, 0.1, 0.1)
        return
    end
    DeleteCursorItem()
end

local function ApplyTrashCan()
    local btn = EUI_Bags._trashBtn
    local on = BP().bagTrashCan == true
    if not btn then
        if not on or not EUI_Bags.Footer then return end
        local footer = EUI_Bags.Footer
        btn = CreateFrame("Button", nil, footer)
        btn:SetSize(TRASH_SIZE, TRASH_SIZE)
        btn:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 10, 3)
        btn:SetFrameLevel(footer:GetFrameLevel() + 5)
        -- Styled like a bag slot with the footer's gold button border
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\icon-bg.png")
        local PP = EUI.PP
        local GOLD_R, GOLD_G, GOLD_B = 0.855, 0.722, 0.259
        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, GOLD_R, GOLD_G, GOLD_B, 0.6, 1, "OVERLAY", 7)
        end
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetPoint("TOPLEFT", 3, -3)
        btn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        EUI.SetDeleteIcon(btn.icon)
        btn.icon:SetDesaturated(true)
        btn.icon:SetAlpha(0.85)
        local pt = btn:CreateTexture(nil, "OVERLAY")
        pt:SetAllPoints()
        pt:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\highlight-3.png")
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
        btn:SetPushedTexture(pt)
        local function SetLook(self, hover)
            local armed = hover and GetCursorInfo() == "item"
            if armed then
                self.icon:SetVertexColor(1, 0.3, 0.3)
            else
                self.icon:SetVertexColor(1, 1, 1)
            end
            self.icon:SetAlpha(hover and 1 or 0.85)
            if PP and PP.SetBorderColor then
                if armed then
                    PP.SetBorderColor(self, 1, 0.25, 0.25, 1)
                else
                    PP.SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, hover and 1 or 0.6)
                end
            end
        end
        local function OnDrop(self)
            TrashCursorItem()
            SetLook(self, self:IsMouseOver())
        end
        btn:SetScript("OnReceiveDrag", OnDrop)
        btn:SetScript("OnClick", OnDrop)
        btn:SetScript("OnEnter", function(self)
            SetLook(self, true)
            EUI.ShowWidgetTooltip(self, EllesmereUI.L("Drop an item here to delete it without confirmation. Rare and better items and quest items are not accepted."))
        end)
        btn:SetScript("OnLeave", function(self)
            SetLook(self, false)
            EUI.HideWidgetTooltip()
        end)
        EUI_Bags._trashBtn = btn
    end
    btn:SetShown(on)
    -- Shift the currencies around the button and refit the footer
    SyncBagFrameToFooter()
end
EUI_Bags.ApplyTrashCan = ApplyTrashCan

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
    -- Controller cursor: Cancel finds the close button.
    if EUI.PadCP() then EUI_BagsReagent.CloseButton = close end
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

-------------------------------------------------------------------------------
--  Shared with the bank (EllesmereUIBags_Bank.lua loads after this file) via ns
-------------------------------------------------------------------------------
ns.CreateInsetBorder = CreateInsetBorder
ns.SetBagFont = SetBagFont
ns.SetInsetBorderColor = SetInsetBorderColor

-- Flat look for a ContainerFrameItemButtonTemplate slot, plus the text overlay
-- (above the cooldown swipe) with Count, ItemLevelText and BindTypeText.
-- Methods only: writing properties onto Blizzard template sub-objects taints.
-- opts: anchorIcon (re-anchor icon to the button), cooldownFont (restyle the
-- cooldown text), flatHighlight (bank: 8% white highlight, with highlight and
-- pushed textures looked up by template field first). Returns the overlay.
function ns.SkinItemButton(btn, opts)
    if btn.NewItemTexture then btn.NewItemTexture:Hide(); btn.NewItemTexture:SetAlpha(0) end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide(); btn.BattlepayItemTexture:SetAlpha(0) end
    if btn.flash then btn.flash:Hide(); btn.flash:SetAlpha(0) end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end

    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    if btn.icon then
        local z = BP().bagItemIconZoom or 0.08
        btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        if opts.anchorIcon then
            btn.icon:ClearAllPoints()
            btn.icon:SetAllPoints(btn)
        end
    end

    local ht, pt
    if opts.flatHighlight then
        ht = btn.HighlightTexture or btn:GetHighlightTexture()
        if ht then ht:SetTexture(nil); ht:SetColorTexture(1, 1, 1, 0.08) end
        pt = btn.PushedTexture or btn:GetPushedTexture()
    else
        ht = btn:GetHighlightTexture()
        pt = btn:GetPushedTexture()
    end
    if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
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

    if opts.cooldownFont and btn.Cooldown then
        local cdText = btn.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            EllesmereUI.ApplyIconTextFont(cdText, GetFont(), 11, "bags")
        end
    end

    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 2)
    btn._textOverlay = textOverlay

    local fontPath = GetFont()
    local outline = (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        EllesmereUI.ApplyIconTextFont(countFS, fontPath, BP().bagCountFontSize or 11, "bags")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    -- Item level text (top-left, gear only)
    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    btn.ItemLevelText:SetFont(fontPath, BP().itemlevelFontSize or 12, outline)
    btn.ItemLevelText:SetText("")

    -- Bind Type text (bottom-left)
    if not btn.BindTypeText then
        btn.BindTypeText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.BindTypeText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 2)
        btn.BindTypeText:SetTextColor(1, 1, 1, 1)
    end
    btn.BindTypeText:SetFont(fontPath, BP().bagBindTypeFontSize or 11, outline)
    btn.BindTypeText:SetText("")
    return textOverlay
end

-- Sidebar header: label + collapse arrow for the profile flag dbKey. The
-- caller's OnClick flips the flag, then calls the returned UpdateArrow.
function ns.CreateSidebarHeader(sidebar, label, dbKey)
    local hdr = CreateFrame("Frame", nil, sidebar)
    hdr:SetHeight(24)
    hdr:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)

    hdr._label = hdr:CreateFontString(nil, "OVERLAY")
    SetBagFont(hdr._label, 10)
    hdr._label:SetPoint("LEFT", hdr, "LEFT", 8, 0)
    hdr._label:SetText(label)
    hdr._label:SetTextColor(0.5, 0.5, 0.5)

    local collapseBtn = CreateFrame("Button", nil, hdr)
    collapseBtn:SetSize(12, 12)
    collapseBtn:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
    collapseBtn._icon = collapseBtn:CreateTexture(nil, "OVERLAY")
    collapseBtn._icon:SetAllPoints()
    collapseBtn._icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png")
    collapseBtn._icon:SetAlpha(0.4)

    local function UpdateArrow()
        collapseBtn:ClearAllPoints()
        if BP()[dbKey] then
            collapseBtn._icon:SetRotation(math.pi)
            collapseBtn:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        else
            collapseBtn._icon:SetRotation(0)
            collapseBtn:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
        end
    end
    UpdateArrow()

    collapseBtn:SetScript("OnEnter", function(self)
        self._icon:SetAlpha(0.9)
        EUI.ShowWidgetTooltip(self, BP()[dbKey] and "Expand Sidebar" or "Collapse Sidebar")
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        self._icon:SetAlpha(0.4)
        EUI.HideWidgetTooltip()
    end)
    return hdr, collapseBtn, UpdateArrow
end

-- Item-grid scrollbar: a 4px thumb in a 16px hit strip; the caller anchors the
-- returned track. Scrolls instantly, not smoothed (so not AttachSmoothScrollbar).
-- clamp: pull the scroll back into range on every update (content may have
-- shrunk). rawWheel: the wheel reads sf's scroll range directly rather than the
-- thumb metrics, which give up when the track is too short for a thumb.
local SCROLLBAR_HIT_W = 16  -- invisible hit area width
function ns.AttachGridScrollbar(host, sf, clamp, rawWheel)
    local SCROLLBAR_W = 4   -- thumb width
    local SCROLL_STEP = 40  -- pixels per mouse wheel tick
    local THUMB_MIN_H = 20  -- minimum thumb height

    local track = CreateFrame("Button", nil, host)
    track:SetWidth(SCROLLBAR_HIT_W)
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
        if clamp then
            local range = sf:GetVerticalScrollRange() or 0
            local cur = sf:GetVerticalScroll()
            if cur > range then sf:SetVerticalScroll(range) end
        end
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

    -- On the scroll frame and on host (items might not cover the full area)
    local function OnWheel(_, delta)
        local scrollRange
        if rawWheel then
            scrollRange = sf:GetVerticalScrollRange()
            if scrollRange and scrollRange <= 0 then scrollRange = nil end
        else
            scrollRange = select(4, GetScrollMetrics())
        end
        if not scrollRange then return end
        local cur = sf:GetVerticalScroll()
        local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
        sf:SetVerticalScroll(newVal)
        UpdateThumb()
    end
    sf:SetScript("OnMouseWheel", OnWheel)
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", OnWheel)

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

    -- Controller cursor (a pad has no wheel): one-notch step buttons at the
    -- track ends, a visible track, a thumb that follows every scroll (the
    -- cursor scrolls the grid itself) and a track that is not a cursor stop
    -- (a press there would jump to the hidden pointer). The owner calls
    -- track.PadSync(on) at its show edge; nothing is built before a
    -- controller is in use.
    local padUp, padDown, padOn
    local function PadSteps()
        local show = padOn and trackBg:IsShown() or false
        padUp:SetShown(show)
        padDown:SetShown(show)
    end
    function track.PadSync(on)
        on = on and true or false
        if not padUp then
            if not on then return end
            padUp, padDown = ns.PadStepButtons(host, SCROLLBAR_HIT_W, function(delta) OnWheel(nil, delta) end)
            padUp:SetFrameLevel(track:GetFrameLevel() + 1)
            padDown:SetFrameLevel(track:GetFrameLevel() + 1)
            padUp:SetPoint("TOP", track, "TOP", 0, 0)
            padDown:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
            hooksecurefunc(trackBg, "Show", PadSteps)
            hooksecurefunc(trackBg, "Hide", PadSteps)
            sf:HookScript("OnVerticalScroll", function() UpdateThumb() end)
            EUI.PadHint(track, "nodeignore")
        end
        if on == padOn then return end
        padOn = on
        trackBg:SetColorTexture(1, 1, 1, on and 0.15 or 0.06)
        PadSteps()
    end
    return track, thumb, UpdateThumb
end

-------------------------------------------------------------------------------
--  Controller support (the bags and the bank). Everything here runs only on
--  an edge that already exists (a show, a click, a menu open) behind the
--  shared controller signal; mouse/keyboard players never build any of it.
-------------------------------------------------------------------------------
do
    local ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
    local ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"

    local function MakeStep(parent, size, icon, onClick)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(size, size)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(size - 4, size - 4)
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        t:SetTexture(icon)
        b:SetAlpha(0.5)
        b:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        b:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        b:SetScript("OnClick", onClick)
        b:Hide()
        return b
    end

    -- Up/down step buttons for a wheel-only scroller: step(1) scrolls up one
    -- notch, step(-1) down. Created hidden; the caller anchors them.
    function ns.PadStepButtons(parent, size, step)
        return MakeStep(parent, size, ARROW_UP, function() step(1) end),
               MakeStep(parent, size, ARROW_DOWN, function() step(-1) end)
    end

    -- Sidebar step buttons (categories, bank tabs) in the sidebar header, left
    -- of the collapse arrow: shown while a controller is in use, the sidebar
    -- is expanded and its entries overflow. Each click runs the sidebar's own
    -- wheel handler once (one entry). Called at the window's show edge.
    local function SidebarStepsUpdate(st)
        local show = st.on and not BP()[st.key] and (st.child:GetHeight() - st.sf:GetHeight()) > 0.5
        st.up:SetShown(show)
        st.down:SetShown(show)
    end

    function ns.PadSidebarSync(hdr, sf, child, dbKey, on)
        if not (hdr and sf and child) then return end
        local st = hdr._padSteps
        if not st then
            if not on then return end
            local up, down = ns.PadStepButtons(hdr, 14, function(delta)
                local wheel = sf:GetScript("OnMouseWheel")
                if wheel then wheel(sf, delta) end
            end)
            down:SetPoint("RIGHT", hdr, "RIGHT", -22, 0)
            up:SetPoint("RIGHT", down, "LEFT", -2, 0)
            st = { up = up, down = down, sf = sf, child = child, key = dbKey }
            hdr._padSteps = st
            -- The rebuild sets the list height; the window can resize it too.
            local function Update() SidebarStepsUpdate(st) end
            hooksecurefunc(child, "SetHeight", Update)
            sf:HookScript("OnSizeChanged", Update)
        end
        st.on = on and true or false
        SidebarStepsUpdate(st)
    end

    -- Blizzard's bag frames live under a hidden parent. One that its own
    -- toggle opened keeps reporting shown after we close the bags ourselves,
    -- so the next Back press counts as "closed a bag" and does nothing else.
    -- Only frames that are shown but not visible (still under that parent)
    -- are touched, and no Blizzard OnHide runs for them.
    function ns.PadReleaseBlizzBags()
        local f = ContainerFrameCombinedBags
        if f and f:IsShown() and not f:IsVisible() then f:Hide() end
        for i = 1, 13 do
            f = _G["ContainerFrame" .. i]
            if f and f:IsShown() and not f:IsVisible() then f:Hide() end
        end
    end

    -- WoW Forever's Gamepad interface style navigates Blizzard's own bags and
    -- bank with the D-pad, so the takeover stands down for the session there.
    -- Decided once, at login; a later style switch asks for a reload, once.
    local standDown, styleAsked
    function ns.PadUIStandDown()
        if standDown == nil then standDown = EUI.PadGamepadUI() end
        return standDown
    end

    function ns.PadStyleChanged()
        if styleAsked then return end
        styleAsked = true
        -- The Gamepad style's D-pad cannot reach the popup, so chat says it too.
        EllesmereUI.PrintError(EllesmereUI.L("The interface style changed. Type /reload so the bags match it."))
        EUI.RequestReload(EllesmereUI.L("Reload Required"),
            EllesmereUI.L("The interface style changed. Reload so the bags match it."))
    end
end

-- Gold border for quest items (overrides the normal quality border).
local QUEST_BORDER_COLOR = { r = 1.0, g = 0.82, b = 0.0 }

-------------------------------------------------------------------------------
--  Stack splitter: replaces Blizzard's StackSplitFrame on our bag/bank slots
--  and on the guild bank's (opt-in) with a house dialog that adds Auto Split --
--  repeated splits into empty slots until the remainder is at most the chosen size.
-------------------------------------------------------------------------------
do
    local dialog
    local job          -- { bag, slot, itemID, size, targets, window, ops, pending, issuedAt }
    local StepJob

    -- Container and guild bank slots share the dialog and job; only the API differs.
    local containerOps = {
        ownerBag = function(owner) return owner:GetParent():GetID() end,
        info     = C_Container.GetContainerItemInfo,
        numSlots = C_Container.GetContainerNumSlots,
        split    = C_Container.SplitContainerItem,
        pickup   = C_Container.PickupContainerItem,
    }
    local guildOps = {
        ownerBag = function() return GetCurrentGuildBankTab() end,
        -- A tab that is no longer viewed reads as empty so a running job stops there.
        info = function(tab, slot)
            if tab ~= GetCurrentGuildBankTab() then return nil end
            local texture, count, locked = GetGuildBankItemInfo(tab, slot)
            if not texture then return nil end
            local link = GetGuildBankItemLink(tab, slot)
            return { stackCount = count, isLocked = locked, itemID = link and GetItemInfoInstant(link) or 0 }
        end,
        numSlots = function() return 98 end,
        split    = SplitGuildBankItem,
        pickup   = PickupGuildBankItem,
    }

    local function StopJob()
        job = nil
    end

    -- Polled on a short timer. The new stack's slot can still read empty for a
    -- moment after the source count has updated, so slots already used as a
    -- destination are skipped for the rest of the job.
    local function Later()
        local this = job
        C_Timer.After(0.05, function() if job == this then StepJob() end end)
    end

    -- One split per server round trip: issue, wait for the source stack to
    -- settle at the expected count, repeat.
    StepJob = function()
        if not job then return end
        if not job.window:IsVisible() then StopJob(); return end
        local ops = job.ops
        local info = ops.info(job.bag, job.slot)
        if not info or info.itemID ~= job.itemID then StopJob(); return end
        if info.isLocked or (job.pending and info.stackCount ~= job.pending) then
            if GetTime() - job.issuedAt > 2 then ClearCursor(); StopJob() else Later() end
            return
        end
        job.pending = nil
        if info.stackCount <= job.size then StopJob(); return end
        for _, bagID in ipairs(job.targets) do
            for s = 1, ops.numSlots(bagID) do
                local key = bagID * 1000 + s
                if not job.used[key] and not ops.info(bagID, s) then
                    job.used[key] = true
                    ClearCursor()
                    ops.split(job.bag, job.slot, job.size)
                    ops.pickup(bagID, s)
                    -- Single placed split: one issue, no settle polling.
                    if job.once then StopJob(); return end
                    job.pending = info.stackCount - job.size
                    job.issuedAt = GetTime()
                    Later()
                    return
                end
            end
        end
        StopJob()
    end

    -- once = a single split placed into the first empty target slot (the views
    -- that draw no empty slots have nowhere to drop a cursor stack).
    local function StartJob(bag, slot, itemID, size, targets, window, ops, once)
        job = { bag = bag, slot = slot, itemID = itemID, size = size, targets = targets, window = window,
                ops = ops, used = {}, issuedAt = GetTime(), once = once }
        StepJob()
    end

    -- Closing the window a dialog or job belongs to ends it; other windows are unaffected.
    local function WindowHidden(win)
        if dialog and dialog._window == win then dialog:Hide() end
        if job and job.window == win then StopJob() end
        -- Closing the bags ends every session unmerge; the next open merges again.
        if win == EUI_Bags and EUI_Bags._unmergedLinks then wipe(EUI_Bags._unmergedLinks) end
    end

    local function Current()
        return Clamp(dialog._eb:GetNumber(), 1, dialog._max)
    end

    local function SetValue(n)
        n = Clamp(n, 1, dialog._max)
        dialog._eb:SetText(tostring(n))
        dialog._eb:SetCursorPosition(#dialog._eb:GetText())
    end

    -- Re-checks the slot the dialog was opened on after every repaint: pooled
    -- buttons get repurposed, and the count can change under us.
    local function Validate()
        if not dialog or not dialog:IsShown() then return end
        local owner = dialog._owner
        if not owner:IsVisible() or dialog._ops.ownerBag(owner) ~= dialog._bag or owner:GetID() ~= dialog._slot then
            dialog:Hide(); return
        end
        local info = dialog._ops.info(dialog._bag, dialog._slot)
        if not info or info.itemID ~= dialog._itemID or not info.stackCount or info.stackCount < 2 then
            dialog:Hide(); return
        end
        if info.stackCount ~= dialog._max then
            dialog._max = info.stackCount
            dialog._maxLbl:SetText("/ " .. info.stackCount)
            SetValue(Current())
        end
    end

    local function MakeButton(parent, w, h, label, PP)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, h)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        if PP and PP.CreateBorder then PP.CreateBorder(b, 0.25, 0.25, 0.25, 1) end
        local fs = b:CreateFontString(nil, "OVERLAY")
        SetBagFont(fs, 12)
        fs:SetPoint("CENTER", 0, 0)
        fs:SetTextColor(1, 1, 1, 0.9)
        fs:SetText(label)
        b:SetScript("OnEnter", function() bg:SetColorTexture(0.2, 0.2, 0.2, 1) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(0.15, 0.15, 0.15, 1) end)
        return b
    end

    local function DoSplit(auto)
        local d = dialog
        local bag, slot, n, ops = d._bag, d._slot, Current(), d._ops
        d:Hide()
        local info = ops.info(bag, slot)
        if not info or info.isLocked or info.itemID ~= d._itemID or not info.stackCount or n >= info.stackCount then return end
        -- Session unmerge mark, written BEFORE the split so the refresh it
        -- triggers already renders the pieces apart. Same link form the slot
        -- tables key on; bags and reagent window only (bank items never merge here).
        if d._window == EUI_Bags or d._window == EUI_BagsReagent then
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local set = EUI_Bags._unmergedLinks
                if not set then set = {}; EUI_Bags._unmergedLinks = set end
                set[link] = true
            end
        end
        if auto or d._placeOnce then
            StartJob(bag, slot, info.itemID, n, d._targets, d._window, ops, not auto)
        else
            ClearCursor()
            ops.split(bag, slot, n)
        end
    end

    local function CreateDialog()
        local PP = EUI and EUI.PP
        local d = CreateFrame("Frame", "EUI_BagsStackSplitFrame", UIParent)
        d:SetFrameStrata("DIALOG")
        d:SetSize(206, 94)
        d:SetClampedToScreen(true)
        d:EnableMouse(true)
        d:EnableMouseWheel(true)
        d:Hide()
        local bg = d:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        if PP and PP.CreateBorder then PP.CreateBorder(d, 0.2, 0.2, 0.2, 1) end

        local title = d:CreateFontString(nil, "OVERLAY")
        SetBagFont(title, 13)
        title:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -9)
        title:SetTextColor(1, 1, 1, 0.9)
        title:SetText(EllesmereUI.L("Split Stack"))

        local close = CreateFrame("Button", nil, d)
        close:SetSize(12, 12)
        close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -9, -9)
        close.icon = close:CreateTexture(nil, "OVERLAY")
        close.icon:SetAllPoints()
        close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
        close.icon:SetAlpha(0.7)
        close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
        close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
        close:SetScript("OnClick", function() d:Hide() end)

        local minus = MakeButton(d, 22, 22, "-", PP)
        minus:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -30)
        minus:SetScript("OnClick", function() SetValue(Current() - 1) end)

        local eb = CreateFrame("EditBox", nil, d)
        eb:SetSize(56, 22)
        eb:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        eb:SetAutoFocus(false)
        eb:SetNumeric(true)
        eb:SetMaxLetters(5)
        eb:SetFont(GetFont(), 12, "")
        eb:SetTextColor(1, 1, 1, 1)
        eb:SetJustifyH("CENTER")
        eb:SetTextInsets(4, 4, 0, 0)
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints()
        ebBg:SetColorTexture(0.1, 0.1, 0.1, 1)
        if PP and PP.CreateBorder then PP.CreateBorder(eb, 0.15, 0.15, 0.15, 1) end
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput and self:GetNumber() > d._max then SetValue(d._max) end
        end)
        eb:SetScript("OnEditFocusLost", function() SetValue(Current()) end)
        eb:SetScript("OnEnterPressed", function() DoSplit(IsAltKeyDown()) end)
        eb:SetScript("OnEscapePressed", function() d:Hide() end)
        -- Controller cursor: the -/+ buttons cover the amount, so no
        -- on-screen keyboard for this box.
        EUI.PadHint(eb, "hidekeyboard")
        d._eb = eb

        local plus = MakeButton(d, 22, 22, "+", PP)
        plus:SetPoint("LEFT", eb, "RIGHT", 4, 0)
        plus:SetScript("OnClick", function() SetValue(Current() + 1) end)

        local maxLbl = d:CreateFontString(nil, "OVERLAY")
        SetBagFont(maxLbl, 12)
        maxLbl:SetPoint("LEFT", plus, "RIGHT", 8, 0)
        maxLbl:SetTextColor(0.7, 0.7, 0.7, 1)
        d._maxLbl = maxLbl

        local split = MakeButton(d, 88, 24, EllesmereUI.L("Split"), PP)
        split:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 10, 10)
        split:SetScript("OnClick", function() DoSplit(false) end)
        d._split = split
        -- Controller cursor: Cancel finds the dialog's close button.
        if EUI.PadCP() then d.CloseButton = close end

        local auto = MakeButton(d, 88, 24, EllesmereUI.L("Auto Split"), PP)
        auto:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -10, 10)
        auto:SetScript("OnClick", function() DoSplit(true) end)
        auto:HookScript("OnEnter", function()
            EUI.ShowWidgetTooltip(auto, EllesmereUI.L("Split this stack into empty slots repeatedly until only the chosen amount or less remains. Alt+Enter does the same."))
        end)
        auto:HookScript("OnLeave", function() EUI.HideWidgetTooltip() end)

        d:SetScript("OnMouseWheel", function(_, delta) SetValue(Current() + (delta > 0 and 1 or -1)) end)
        d:SetScript("OnHide", function() eb:ClearFocus() end)

        hooksecurefunc(EUI_Bags, "RefreshInventory", Validate)
        EUI_Bags:HookScript("OnHide", function() WindowHidden(EUI_Bags) end)
        hooksecurefunc(EUI_BagsReagent, "RefreshInventory", Validate)
        EUI_BagsReagent:HookScript("OnHide", function() WindowHidden(EUI_BagsReagent) end)
        local bankFrame = _G.EUI_BankFrame
        if bankFrame then
            hooksecurefunc(bankFrame, "RefreshBank", Validate)
            bankFrame:HookScript("OnHide", function() WindowHidden(bankFrame) end)
        end
        EllesmereUI.RegisterEscapeClose(d)
        return d
    end

    -- Runs from the slot PostClick hooks, after Blizzard's OnModifiedClick has
    -- opened StackSplitFrame on this button (its lock/count/cursor checks passed).
    -- targets: bagIDs Auto Split may fill, in order; window: closing it aborts a job.
    function EUI_Bags.ShowStackSplitter(owner, targets, window, ops)
        -- Always on in the bags window's All Items (0) and category (> 0) views:
        -- they draw no empty slots, so Blizzard's cursor split has nowhere to
        -- land and a plain Split places its stack instead. Everywhere else the
        -- Stack Splitter setting decides whether the dialog replaces the popup.
        local placeOnce = (window == EUI_Bags and selectedCategoryIndex >= 0)
        if not placeOnce and BP().bagStackSplitter ~= true then return end
        local ssf = StackSplitFrame
        if not ssf:IsShown() or ssf.owner ~= owner then return end
        local maxStack = ssf.maxStack
        -- Hide only: no field writes on Blizzard's popup. Its OnHide leaves .owner
        -- pointing at our permanent pooled button, which is harmless; the flag it
        -- writes onto that button is read by nothing on a click path.
        ssf:Hide()
        ops = ops or containerOps
        local bag, slot = ops.ownerBag(owner), owner:GetID()
        local info = ops.info(bag, slot)
        if not info or not info.itemID then return end
        dialog = dialog or CreateDialog()
        StopJob()
        dialog._owner, dialog._bag, dialog._slot, dialog._itemID = owner, bag, slot, info.itemID
        dialog._targets, dialog._window, dialog._ops = targets, window, ops
        dialog._placeOnce = placeOnce
        dialog._max = maxStack
        dialog._maxLbl:SetText("/ " .. maxStack)
        SetValue(1)
        dialog:ClearAllPoints()
        dialog:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -4, 6)
        dialog:Show()
        -- Controller cursor on screen: no keyboard focus (it would raise the
        -- on-screen keyboard); the cursor moves onto Split instead.
        if EUI.PadCursorShown() then
            EUI.PadFocus(dialog._split)
        else
            dialog._eb:SetFocus()
            dialog._eb:HighlightText()
        end
    end

    -- Blizzard's guild bank buttons open StackSplitFrame the same way ours do,
    -- so the same PostClick takeover applies. Auto Split stays on the viewed tab.
    local function HookGuildBank()
        local gb = GuildBankFrame
        if not gb or not gb.Columns then return end
        for _, column in ipairs(gb.Columns) do
            for _, b in ipairs(column.Buttons) do
                b:HookScript("PostClick", function(self)
                    EUI_Bags.ShowStackSplitter(self, { GetCurrentGuildBankTab() }, gb, guildOps)
                end)
            end
        end
        hooksecurefunc(gb, "Update", Validate)
        gb:HookScript("OnHide", function() WindowHidden(gb) end)
    end
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_GuildBankUI", HookGuildBank)
    end
end

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
    -- upgrade tracks -- see NormalizePinKey above); pinKey == info.itemID
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
    ov.plus:SetFont(GetFont(), 18, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    ov.plus:SetPoint("CENTER", 0, 0)
    ov.plus:SetText("+")
    ov.plus:SetTextColor(1, 1, 1, 0.5)
    ov:SetScript("OnEnter", function(self)
        self.plus:SetTextColor(1, 1, 1, 1)
        EUI.ShowWidgetTooltip(self, "Pin an Item")
    end)
    ov:SetScript("OnLeave", function(self)
        self.plus:SetTextColor(1, 1, 1, 0.5)
        EUI.HideWidgetTooltip()
    end)
    ov:RegisterForDrag("LeftButton")
    ov:SetScript("OnReceiveDrag", function()
        -- select(3, ...), not select(2, ...): GetCursorInfo() for "item" returns
        -- type, itemID, itemLink -- select(2, ...) into a single local re-grabs
        -- itemID, not the link (see the correct 3-value capture at line ~6988).
        -- Needed here for a real link now that pins are link-keyed.
        local cursorType, itemID, cursorLink = GetCursorInfo()
        if cursorType == "item" and itemID then
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
            local pinned = EllesmereUIDB.bagPinnedItems
            local pinKey = NormalizePinKey(cursorLink, itemID)
            if not IsItemPinned(pinned, cursorLink, itemID) then
                pinned[pinKey] = IsGearItem(cursorLink) and 1 or 999
            end
            ClearCursor()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
        end
    end)
    ov:SetScript("OnClick", function(self)
        local cursorType, itemID, cursorLink = GetCursorInfo()
        if cursorType == "item" and itemID then
            -- Click-to-place also pins
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
            local pinned = EllesmereUIDB.bagPinnedItems
            local pinKey = NormalizePinKey(cursorLink, itemID)
            if not IsItemPinned(pinned, cursorLink, itemID) then
                pinned[pinKey] = IsGearItem(cursorLink) and 1 or 999
            end
            ClearCursor()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
            return
        end
        -- Controller cursor on screen: select mode hit-tests the hidden
        -- pointer, so explain the carry-then-press path instead.
        if EUI.PadCursorShown() then
            EUI.ShowWidgetTooltip(self, EllesmereUI.L("Pick up an item, then press + to pin it"))
            return
        end
        EUI.HideWidgetTooltip()
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
    ov.plus:SetFont(GetFont(), 18, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    ov.plus:SetPoint("CENTER", 0, 0)
    ov.plus:SetText("+")
    ov.plus:SetTextColor(1, 1, 1, 0.5)
    ov:SetScript("OnEnter", function(self)
        self.plus:SetTextColor(1, 1, 1, 1)
        EUI.ShowWidgetTooltip(self, "Assign an item to this category")
    end)
    ov:SetScript("OnLeave", function(self)
        self.plus:SetTextColor(1, 1, 1, 0.5)
        EUI.HideWidgetTooltip()
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
            -- Controller cursor on screen: select mode hit-tests the hidden
            -- pointer, so explain the carry-then-press path instead.
            if EUI.PadCursorShown() then
                EUI.ShowWidgetTooltip(self, EllesmereUI.L("Pick up an item, then press + to add it to this category"))
                return
            end
            EUI.HideWidgetTooltip()
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
    if sf then sf:SetFrameStrata(EUI_Bags:GetFrameStrata()) end
end

-------------------------------------------------------------------------------
--  Assign Selection Mode: dim the screen, click an item to assign it to a category (mirrors Pin Selection Mode).
-------------------------------------------------------------------------------
local _assignSelectCatKey = nil
-- Junk-select mode reuses this machinery with two extra behaviours: toggle
-- (click flips membership instead of only adding) and stay-open (the mode
-- survives each click so several items can be marked in one pass).
local _assignSelectToggle = false
local _assignSelectStayOpen = false

local function ExitAssignSelectMode()
    EUI_Bags._assignSelectMode = false
    _assignSelectCatKey = nil
    _assignSelectToggle = false
    _assignSelectStayOpen = false
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
    if sf then sf:SetFrameStrata(EUI_Bags:GetFrameStrata()) end
end

EnterAssignSelectMode = function(catKey, opts)
    EUI_Bags._assignSelectMode = true
    _assignSelectCatKey = catKey
    _assignSelectToggle = opts and opts.toggle or false
    _assignSelectStayOpen = opts and opts.stayOpen or false

    -- Normal "+" assign dims the whole viewport (its long-standing look); junk
    -- select mode dims ONLY the bag window so the item grid stays bright while the
    -- player clicks several items in a row. The two overlays are cached
    -- separately and picked per mode; the active one is stored in _assignOverlay
    -- so Exit and the fades below operate on whichever is up.
    local bagOnly = opts and opts.bagOnly
    local cacheKey = bagOnly and "_assignOverlayBag" or "_assignOverlayFull"
    if not EUI_Bags[cacheKey] then
        local ov = CreateFrame("Frame", nil, bagOnly and EUI_Bags or UIParent)
        if bagOnly then
            -- Bag-only: sit at the bag's OWN strata (just above its chrome). The
            -- item grid rides the scroll frame, raised a full strata above to
            -- FULLSCREEN_DIALOG below -- so the items stay fully bright and only
            -- the bag behind them dims. (A same-strata overlay left the grid's
            -- layering ambiguous, which dimmed the items.)
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
        ov:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                ExitAssignSelectMode()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        EUI_Bags[cacheKey] = ov
    end
    EUI_Bags._assignOverlay = EUI_Bags[cacheKey]
    local ov = EUI_Bags._assignOverlay
    -- Controller cursor: Back (which never reaches OnKeyDown) cancels the
    -- mode first. Joined only once a controller is in use; the proxy counts
    -- it only when one is in use at its show.
    if not ov._padEsc and EUI.PadInUse() then
        ov._padEsc = true
        EllesmereUI.RegisterEscapeClose(ov, { padOnly = true, notOwned = true, onEscape = function() ExitAssignSelectMode() end })
    end
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
                        if _assignSelectToggle then
                            -- Junk-select mode: click toggles membership.
                            EUI_CategoryManager:ToggleJunk(info.itemID)
                        else
                            EUI_CategoryManager:AssignItem(info.itemID, _assignSelectCatKey)
                        end
                        ClearHover()
                        if not _assignSelectStayOpen then
                            ExitAssignSelectMode()
                        end
                        EUI_Bags:RefreshInventory()
                        -- RefreshInventory can lower the scroll frame back down;
                        -- in a stay-open pass re-raise it above the catcher so the
                        -- next click still hit-tests item buttons.
                        if _assignSelectStayOpen then
                            local sf = EUI_Bags._scrollFrame
                            if sf then sf:SetFrameStrata("FULLSCREEN_DIALOG") end
                        end
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

-- Junk-select mode: enter assign-select targeted at the Junk category, but in
-- toggle + stay-open form so the player can click several items in a row to
-- mark/unmark them. Defined as a method (not a local) so the header button --
-- built earlier in file order than EnterAssignSelectMode -- can reach it at
-- click time.
function EUI_Bags:EnterJunkSelectMode()
    if not (EUI_CategoryManager and EUI_CategoryManager:IsJunkMarkerEnabled()) then return end
    EnterAssignSelectMode(EUI_CategoryManager.JUNK_KEY, { toggle = true, stayOpen = true, bagOnly = true })
end

-- SellJunk: sell every junk item (grey + player-marked) that has a sell value at
-- the open merchant. Selling via UseContainerItem is insecure-callable while a
-- merchant is open, so no secure handler is needed. The client only keeps the
-- last 12 sold items for buyback (surfaced in the button tooltip); this sells
-- everything regardless -- a deliberate "clear my junk" action.
-- Still-refundable purchases are skipped: Blizzard's own right-click never sells
-- them (it pops the refund confirmation instead), and marks are account-wide per
-- itemID -- so a freshly bought copy of a marked item would otherwise auto-sell
-- at the next merchant without asking. GetContainerItemPurchaseInfo reports a
-- refundSeconds while the item is inside its refund window. Capability-guarded.
local function IsRefundable(bag, slot)
    local getInfo = C_Container and C_Container.GetContainerItemPurchaseInfo
    if not getInfo then return false end
    -- Modern ContainerItemPurchaseInfo table carries refundSeconds. Type-guard
    -- the read so a non-table return can never error mid-sell -- a non-refundable
    -- or unbought slot returns nil here, which is simply treated as sellable.
    local purchase = getInfo(bag, slot, false)
    if type(purchase) ~= "table" then return false end
    return (purchase.refundSeconds and purchase.refundSeconds > 0) or false
end

-- Find the first sellable junk slot: grey or player-marked, with vendor value
-- (hasNoValue items can't be sold), not locked, and not still refundable.
-- Re-scanned each step because slots empty as they sell.
local function NextJunkSlot()
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked and not info.hasNoValue
               and EUI_CategoryManager and EUI_CategoryManager:IsJunk(info.itemID, info.quality)
               and not IsRefundable(bag, slot) then
                return bag, slot, info
            end
        end
    end
end

-- Sell all junk at the open merchant, ONE item per short tick rather than dozens
-- of UseContainerItem calls in a single frame -- gentler on the client and it
-- bails cleanly if the merchant closes or combat starts mid-sweep. (WoW still
-- only keeps the last ~12 sold items for buyback; that's inherent to any bulk
-- sell and is called out in the button tooltip.) Re-entrancy guarded so the
-- button + auto-sell can't run two sweeps at once.
function EUI_Bags:SellJunk()
    if not (EUI_CategoryManager and EUI_CategoryManager:IsJunkMarkerEnabled()) then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    if InCombatLockdown() then return end
    if EUI_Bags._junkSelling then return end

    local sold, earned = 0, 0
    local function finish()
        EUI_Bags._junkSelling = nil
        if sold > 0 then
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
            if not BP().bagJunkNoSellSummary then
                local msg = string.format(EllesmereUI.L("Sold %d junk item(s)"), sold)
                if earned > 0 and GetCoinTextureString then
                    msg = msg .. "  " .. GetCoinTextureString(earned)
                end
                if EllesmereUI.Print then EllesmereUI.Print(msg) else print(msg) end
            end
        end
    end

    local function step()
        -- Stop if the merchant window closed or combat started mid-sweep.
        if not (MerchantFrame and MerchantFrame:IsShown()) or InCombatLockdown() then
            finish(); return
        end
        local bag, slot, info = NextJunkSlot()
        if not bag then finish(); return end
        C_Container.UseContainerItem(bag, slot)
        sold = sold + 1
        -- Best-effort earned total for the summary line. Sell price (GetItemInfo
        -- index 11) resolves from the item LINK; the bare-itemID form returns nil
        -- on this client, so the hyperlink is used (same as the Junk sort).
        local sp = (info.hyperlink and select(11, GetItemInfo(info.hyperlink))) or 0
        earned = earned + sp * (info.stackCount or 1)
        C_Timer.After(0.08, step)
    end

    EUI_Bags._junkSelling = true
    step()
end

-- Merchant watcher: show/hide the Sell Junk button with the merchant window, and
-- run an auto-sell pass on open when the player opted in. Self-contained frame so
-- it does not touch the main bag event handler. Its MERCHANT_SHOW/CLOSED events
-- are registered only while the feature is enabled (SyncJunkMerchantWatcher), so
-- a player with the feature off never runs this handler.
local _junkMerchantWatcher = CreateFrame("Frame")
_junkMerchantWatcher:SetScript("OnEvent", function(_, event)
    local btn = EUI_Bags._sellJunkBtn
    if event == "MERCHANT_SHOW" then
        local on = EUI_CategoryManager and EUI_CategoryManager:IsJunkMarkerEnabled()
        if btn then btn:SetShown(on == true) end
        if on and BP().bagJunkAutoSell then
            -- Defer: at MERCHANT_SHOW the MerchantFrame may not be :IsShown() yet
            -- (Blizzard shows it in its own handler, often after addons), which
            -- made the sell bail "no merchant open". Next frame it is up.
            C_Timer.After(0, function() EUI_Bags:SellJunk() end)
        end
    else
        if btn then btn:Hide() end
    end
end)

-- Register the merchant events only while the Junk Marker feature is on; drop
-- them (and hide the Sell Junk button) when it is off. Called once the bag UI is
-- built with a ready DB, and again whenever the master toggle flips.
function EUI_Bags:SyncJunkMerchantWatcher()
    if EUI_CategoryManager and EUI_CategoryManager:IsJunkMarkerEnabled() then
        _junkMerchantWatcher:RegisterEvent("MERCHANT_SHOW")
        _junkMerchantWatcher:RegisterEvent("MERCHANT_CLOSED")
    else
        _junkMerchantWatcher:UnregisterEvent("MERCHANT_SHOW")
        _junkMerchantWatcher:UnregisterEvent("MERCHANT_CLOSED")
        if EUI_Bags._sellJunkBtn then EUI_Bags._sellJunkBtn:Hide() end
    end
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
    -- Controller cursor: Back (which never reaches OnKeyDown) cancels the
    -- mode first. Joined only once a controller is in use; the proxy counts
    -- it only when one is in use at its show.
    if not ov._padEsc and EUI.PadInUse() then
        ov._padEsc = true
        EllesmereUI.RegisterEscapeClose(ov, { padOnly = true, notOwned = true, onEscape = function() ExitPinSelectMode() end })
    end
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
        ghost.icon:SetTexture(EllesmereUI.ClientIcon(catIcon or 134400))
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
    local sidebarHdr, collapseBtn, UpdateCollapseArrow = ns.CreateSidebarHeader(sidebar, EllesmereUI.L("Categories"), "bagSidebarCollapsed")

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

-- Controller cursor: a pad has no middle click and no drag, so while one is in
-- use the category menu also offers unpinning, removing assigned items and
-- moving the entry one place up or down. A move runs the drag's own drop
-- path (StopSidebarDrag) with the neighbour the sidebar shows.
local function PadCategoryEntries(root, btn, cat, catIdx, isGroupHeader, isGroupMember)
    local rows = {}

    -- Pinned Items: every pinned item in the bags, once per pin key.
    if cat.isPinned then
        local pinned = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
        local seen
        for bag = 0, 5 do
            for slot = 1, (pinned and C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local link = info and info.itemID and C_Container.GetContainerItemLink(bag, slot)
                if info and info.itemID and IsItemPinned(pinned, link, info.itemID) then
                    local key = NormalizePinKey(link, info.itemID)
                    seen = seen or {}
                    if key and not seen[key] then
                        seen[key] = true
                        local itemID = info.itemID
                        rows[#rows + 1] = { text = link or tostring(itemID), fn = function()
                            local p = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
                            if p then p[key] = nil; p[itemID] = nil end
                            EUI_Bags:RefreshInventory()
                        end }
                    end
                end
            end
        end
        rows.title = EllesmereUI.L("Unpin Item")
    -- A category items can be assigned to: every item assigned to it.
    elseif not isGroupHeader and EUI_CategoryManager:CanAssignToCategory(catIdx) then
        local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
        local catKey = cat._defaultName
        if assignments and catKey then
            for itemID, aKey in pairs(assignments) do
                if aKey == catKey then
                    local name, link = GetItemInfo(itemID)
                    rows[#rows + 1] = { text = link or name or ("item:" .. itemID), sort = name or "", fn = function()
                        EUI_CategoryManager:UnassignItem(itemID)
                        EUI_Bags:RefreshInventory()
                    end }
                end
            end
            table.sort(rows, function(a, b) return a.sort < b.sort end)
        end
        rows.title = EllesmereUI.L("Remove Assigned Item")
    end

    -- Move Up / Move Down against the neighbouring sidebar rows.
    local me
    for i = 1, #_sidebarBtns do
        if _sidebarBtns[i] == btn and btn:IsShown() then me = i; break end
    end
    local function Row(j)
        local b = _sidebarBtns[j]
        if b and b:IsShown() then return b end
    end
    local upTarget, downTarget, moveGroup
    if me and not cat.noMove and not btn._noMove then
        local group = cat.groupName
        if isGroupMember and group then
            -- Within its own group only (set children are skipped).
            local j = me - 1
            while Row(j) and Row(j)._isEquipSet do j = j - 1 end
            local q = Row(j)
            if q and q._isGroupMember and q._groupName == group then upTarget = q._catIdx end
            j = me + 1
            while Row(j) and Row(j)._isEquipSet do j = j + 1 end
            q = Row(j)
            if q and q._isGroupMember and q._groupName == group then downTarget = q._catIdx + 1 end
            moveGroup = group
        else
            -- A plain category, or a group header moving its whole block past
            -- the neighbouring entry (a whole group counts as one entry).
            local j = me - 1
            while Row(j) and (Row(j)._isEquipSet or Row(j)._isGroupMember) do j = j - 1 end
            local q = Row(j)
            if q and q._catIdx > 0 and not q._noMove then upTarget = q._catIdx end
            j = me + 1
            while Row(j) and (Row(j)._isEquipSet or (isGroupHeader and Row(j)._isGroupMember and Row(j)._groupName == group)) do
                j = j + 1
            end
            q = Row(j)
            if q and q._catIdx > 0 and not q._noMove then
                if q._isGroupHeader and q._groupName then
                    local members = EUI_CategoryManager:GetGroupMembers(q._groupName)
                    if #members > 0 then downTarget = members[#members] + 1 end
                else
                    downTarget = q._catIdx + 1
                end
            end
        end
    end
    local function Move(target)
        -- The sidebar may have been rebuilt while the menu was open: act only
        -- when the same row still shows the same category.
        if EUI_CategoryManager:GetCategories()[catIdx] ~= cat or btn._catIdx ~= catIdx or not btn:IsShown()
            or (btn._isGroupHeader or false) ~= (isGroupHeader or false) then
            return
        end
        _dragFromCatIdx = catIdx
        _dragSourceBtn = btn
        _dragDropMode = "insert"
        _dragDropTarget = target
        _dragInsertGroup = moveGroup
        _dragTargetIsHeader = false
        StopSidebarDrag()
    end

    if #rows == 0 and not upTarget and not downTarget then return end
    root:CreateDivider()
    if upTarget then root:CreateButton(EllesmereUI.L("Move Up"), function() Move(upTarget) end) end
    if downTarget then root:CreateButton(EllesmereUI.L("Move Down"), function() Move(downTarget) end) end
    if #rows > 0 then
        local sub = root:CreateButton(rows.title)
        -- A long list scrolls inside the menu instead of running off screen.
        if #rows > 20 then sub:SetScrollMode(20 * 20) end
        for _, r in ipairs(rows) do sub:CreateButton(r.text, r.fn) end
    end
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

        -- Controller cursor: unpin / remove / move entries (no middle click or drag on a pad).
        if EUI.PadInUse() then
            PadCategoryEntries(rootDescription, btn, cat, catIdx, isGroupHeader, isGroupMember)
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
                EUI.HideWidgetTooltip()
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
            -- Through the client icon map: a default the Forever client
            -- cannot draw takes its vanilla-era stand-in there.
            btn._icon:SetTexture(EllesmereUI.ClientIcon(entry.icon))
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

                    -- Forever does not include the newer icon files used by the
                    -- Midnight picker. Keep its choices to long-standing client
                    -- icons, including a profession icon.
                    local ICON_IDS = EUI_CLIENT_FOREVER and {
                        134400, 132996, 136240, 136241, 136242, 136244, 136245,
                        136246, 136247, 136248, 136249, 132485, 132640, 134332,
                    } or {
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
                    -- Controller cursor: Cancel finds Add Category, which toggles the popup closed.
                    if EUI.PadCP() then popup.CloseButton = self end

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

-- "Clear" link on a Recent Items header, sitting just left of its "Hide" link
-- (or at the header's right edge when there is none, as in the list).
-- Opt-in (bagShowRecentClear, default off): callers gate on the setting, so a
-- user who never enables it never has the button built. Pooled on the header
-- like _hideBtn; hidden by the per-refresh header reset.
local function ShowRecentClearButton(hdr, hideBtn)
    if not hdr._clearBtn then
        local cb = CreateFrame("Button", nil, hdr)
        cb:SetSize(34, 16)
        cb._fs = cb:CreateFontString(nil, "OVERLAY")
        SetBagFont(cb._fs, 9)
        cb._fs:SetAllPoints()
        cb._fs:SetText(EllesmereUI.L("Clear"))
        cb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
        cb:SetScript("OnEnter", function(self)
            self._fs:SetTextColor(1, 1, 1, 0.9)
            EUI.ShowWidgetTooltip(self, "Clears the Recent Items list.")
        end)
        cb:SetScript("OnLeave", function(self)
            self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
            EUI.HideWidgetTooltip()
        end)
        cb:SetScript("OnClick", function()
            if EUI_Bags.ClearRecentItems then EUI_Bags:ClearRecentItems() end
        end)
        hdr._clearBtn = cb
    end
    hdr._clearBtn:ClearAllPoints()
    if hideBtn then
        hdr._clearBtn:SetPoint("RIGHT", hideBtn, "LEFT", -6, 0)
    else
        hdr._clearBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    end
    hdr._clearBtn:Show()
    return hdr._clearBtn
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
    local track, thumb, UpdateThumb = ns.AttachGridScrollbar(EUI_Bags, sf, true, false)
    track:SetPoint("TOPRIGHT", EUI_Bags, "TOPRIGHT", -1, -(HEADER_H + 1))
    track:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)

    EUI_Bags._scrollFrame = sf
    EUI_Bags._scrollChild = child
    EUI_Bags._scrollTrack = track
    EUI_Bags._scrollThumb = thumb
    EUI_Bags._updateThumb = UpdateThumb
end

-------------------------------------------------------------------------------
--  RefreshInventory
-------------------------------------------------------------------------------
-- Shared tail of RefreshInventory (grid and list view): scroll child height,
-- scrollbar, frame size, item count. curY = bottom of the rendered content.
-------------------------------------------------------------------------------
--  Resize grip: bottom-right handle on the bag and bank windows. Dragging
--  steps the width unit (a grid column, or 1px for the list views) and sets
--  the height. While dragging, the edges follow the cursor; the content
--  re-lays out every relayoutStep px (frame._resizing set meanwhile) and
--  the width settles on release. OnUpdate only while a drag is held.
--  Double-click resets the window to its default size. While the grip
--  shows, the footer's right-edge text moves clear of it.
--  cfg: step, relayoutStep (optional, default step), minCols, minH,
--  getCols(), getHeight(), save(cols, h), finish(), savePos(left, top),
--  reset(), inset(shown), hidden() (optional)
-------------------------------------------------------------------------------
do
local function GripStop(grip)
    grip:SetScript("OnUpdate", nil)
    grip:UnlockHighlight()
    grip:SetButtonState("NORMAL")
    if grip._drag then
        grip._drag = nil
        grip:GetParent()._resizing = nil
        grip._cfg.finish()
    end
end

local function GripOnUpdate(grip)
    if not IsMouseButtonDown("LeftButton") then GripStop(grip); return end
    local d, cfg = grip._drag, grip._cfg
    local cx, cy = GetCursorPosition()
    local es = grip:GetParent():GetEffectiveScale()
    local step = cfg.step
    local dx = math.floor(cx / es - d.x + 0.5)
    dx = math.max((cfg.minCols - d.cols) * step, math.min((d.maxCols - d.cols) * step, dx))
    local cols = d.cols + math.floor(dx / step)
    local bucket = math.floor(dx / (cfg.relayoutStep or step))
    local h = math.floor(d.h + (d.y - cy / es) + 0.5)
    h = math.max(cfg.minH, math.min(d.maxH, h))
    if dx == d.lastDX and h == d.lastH then return end
    local relayout = bucket ~= d.lastBucket
    d.lastDX, d.lastBucket, d.lastH = dx, bucket, h
    cfg.save(cols, h)
    if relayout then cfg.finish() end
    -- After the refresh, which sets the snapped size
    grip:GetParent():SetSize(d.frameW + dx, h)
end

local function GripOnMouseDown(grip, button)
    if button ~= "LeftButton" then return end
    local frame, cfg = grip:GetParent(), grip._cfg
    local left, top, right, bottom = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
    if not left then return end
    -- Pin the top-left corner so only the right and bottom edges move
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    cfg.savePos(left, top)
    local cx, cy = GetCursorPosition()
    local es = frame:GetEffectiveScale()
    local screenW = UIParent:GetRight() * UIParent:GetEffectiveScale() / es
    local cols, h = cfg.getCols(), cfg.getHeight()
    grip._drag = {
        x = cx / es, y = cy / es, cols = cols, h = h, lastBucket = 0, lastDX = 0, lastH = h,
        frameW = frame:GetWidth(),
        maxCols = math.max(cols, cols + math.floor((screenW - right) / cfg.step)),
        maxH = math.max(h, h + math.floor(bottom)),
    }
    frame._resizing = true
    -- Hold the pressed look while the cursor runs ahead of the snapped edge
    grip:LockHighlight()
    grip:SetButtonState("PUSHED", true)
    grip:SetScript("OnUpdate", GripOnUpdate)
end

local function GripReset(grip)
    GripStop(grip)
    grip._cfg.reset()
end

local function GripOnEnter(grip)
    EUI.ShowWidgetTooltip(grip, EllesmereUI.L("Drag to resize. Double-click to reset."))
end

function ns.UpdateResizeGrip(frame, cfg)
    local grip = frame._resizeGrip
    local hide = cfg.hidden and cfg.hidden()
    if hide then
        if grip then grip:Hide() end
    else
        if not grip then
            grip = CreateFrame("Button", nil, frame)
            grip:SetSize(16, 16)
            grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
            grip:SetFrameLevel(frame:GetFrameLevel() + 50)
            grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
            grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
            grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
            grip:SetScript("OnMouseDown", GripOnMouseDown)
            grip:SetScript("OnMouseUp", GripStop)
            grip:SetScript("OnDoubleClick", GripReset)
            grip:SetScript("OnEnter", GripOnEnter)
            grip:SetScript("OnLeave", EUI.HideWidgetTooltip)
            -- Window closed mid-drag: end the drag instead of resuming on reopen
            grip:SetScript("OnHide", GripStop)
            frame._resizeGrip = grip
        end
        if not grip._drag then grip._cfg = cfg end
        grip:Show()
    end
    local shown = not hide
    if frame._gripInset ~= shown then
        frame._gripInset = shown
        cfg.inset(shown)
    end
end
end -- resize grip

local _bagGripCfg = {
    step = SLOT_SIZE + SPACING, minCols = 8, minH = 300,
    getCols = function() return BP().bagColumns or 12 end,
    getHeight = function() return math.floor(EUI_Bags:GetHeight() + 0.5) end,
    save = function(cols, h)
        BP().bagColumns, BP().bagHeight = cols, h
        if EUI_Bags._updateThumb then EUI_Bags._updateThumb() end
    end,
    finish = function() EUI_Bags:RefreshInventory() end,
    savePos = function(left, top)
        BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
    end,
    reset = function()
        local p = BP()
        p.bagColumns, p.bagHeight, p.bagListWidth = nil, nil, nil
        EUI_Bags:RefreshInventory()
    end,
    -- The gold display sits in the footer's bottom-right corner
    inset = function(shown)
        local money = EUI_Bags.Money
        if not money then return end
        money:ClearAllPoints()
        money:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "BOTTOMRIGHT", shown and -18 or 0, 7)
    end,
    -- Auto-Size owns the window size
    hidden = function() return BP().bagAutoSize == true end,
}

-- List display: free width (rows have no cell grid), saved in pixels
local _bagListGripCfg = setmetatable({
    step = 1, relayoutStep = SLOT_SIZE + SPACING, minCols = 300,
    getCols = function() return BP().bagListWidth or GetColumns() * (SLOT_SIZE + SPACING) end,
    save = function(w, h)
        BP().bagListWidth, BP().bagHeight = w, h
        if EUI_Bags._updateThumb then EUI_Bags._updateThumb() end
    end,
}, { __index = _bagGripCfg })

local function FinishRefresh(curY, gridContentW, sidebarW, totalCount, numEmpty, spItems, spEmpty)
    -- In combat the sort button's lock depends on the view just painted.
    if InCombatLockdown() and EUI_Bags._applySortEnabled then EUI_Bags._applySortEnabled() end
    local sf, child = EUI_Bags._scrollFrame, EUI_Bags._scrollChild
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
    -- WoW Forever: height always fits the content on that running max, with no FIXED_H floor (see below).
    local FIXED_H = 650
    -- Resize grip height: the whole window, footer inside it (so a footer
    -- re-wrap never moves the bottom edge)
    local userH = BP().bagHeight
    local totalW = sidebarW + gridContentW
    if BP().bagAutoSize then
        EUI_Bags._asMaxGridW = math.max(EUI_Bags._asMaxGridW or 0, gridContentW)
        totalW = sidebarW + EUI_Bags._asMaxGridW
    end
    local currencyFooterH = UpdateCurrencyDisplays(totalW) or FOOTER_H

    -- A grip-set height overrides WoW Forever's grow-only content fit (Auto-Size hides the grip)
    if BP().bagAutoSize or (EUI.IS_FOREVER and not userH) then
        local sc = EUI_Bags:GetScale(); if not sc or sc <= 0 then sc = 1 end
        local maxH = (UIParent:GetHeight() / sc) * 0.95
        local fitH = contentH + HEADER_H + currencyFooterH + 2
        local neededH
        if EUI.IS_FOREVER then
            -- WoW Forever bags hold far fewer slots: fit the content instead of flooring at FIXED_H, never shorter
            -- than the category list; without Auto-Size the normal height stays the cap (taller content scrolls).
            if not BP().bagAutoSize then maxH = math.min(maxH, FIXED_H + currencyFooterH - FOOTER_H) end
            local sbHdr, sbChild = EUI_Bags._sidebarHdr, EUI_Bags._sidebarChild
            local sbH = HEADER_H + currencyFooterH + (sbHdr and sbHdr:GetHeight() or 0) + (sbChild and sbChild:GetHeight() or 0)
            neededH = math.min(math.max(fitH, sbH), maxH)
        else
            -- Cap at the screen first, then floor at FIXED_H so the window is never smaller than normal (even on short screens).
            neededH = math.max(FIXED_H, math.min(fitH, maxH))
        end
        EUI_Bags._asMaxH = math.max(EUI_Bags._asMaxH or 0, neededH)
        EUI_Bags:SetWidth(totalW)
        EUI_Bags:SetHeight(EUI_Bags._asMaxH)
    else
        EUI_Bags:SetWidth(totalW)
        EUI_Bags:SetHeight(userH or (FIXED_H + currencyFooterH - FOOTER_H))
    end

    if EUI_Bags.Header and EUI_Bags.Header.itemCount then
        if selectedCategoryIndex == 0 or selectedCategoryIndex == -1 or selectedCategoryIndex == -2 then
            -- WoW Forever's special bags stay out of this count (spItems/spEmpty)
            local items = totalCount - (spItems or 0)
            local totalSlots = items + numEmpty - (spEmpty or 0)
            EUI_Bags.Header.itemCount:SetText(EllesmereUI.Lf("%d / %d Items", items, totalSlots))
        else
            EUI_Bags.Header.itemCount:SetText(EllesmereUI.Lf("%d Items", totalCount))
        end
    end

    -- Dice button: OneBag only (unless hidden by setting), parented to the scroll child and anchored to the first category header.
    if EUI_Bags._diceBtn then
        local showDice = selectedCategoryIndex == -1
            and not (BP().bagHideRandomize)
            and not EUI_Bags.IsListMode()
        if showDice and EUI_Bags._scrollChild then
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
    -- View may have changed under a held item (catch layer on / off)
    if EUI_Bags._syncDropTarget and GetCursorInfo() == "item" then EUI_Bags._syncDropTarget() end
    ns.UpdateResizeGrip(EUI_Bags, EUI_Bags.IsListMode() and _bagListGripCfg or _bagGripCfg)
end

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
                    -- The List view's iLvl column always needs the real level
                    d._giIlvl = isGear and (BP().showItemlevelInBags ~= false or EUI_Bags.IsListMode())
                        and GetItemLevelAtLocation(loc, itemLink) or nil
                    -- Upgrade tracks: the grid's item level colour and rank; the
                    -- List view only while its Track column shows or sorts.
                    if isGear and GetUpgradeTrack
                        and (not EUI_Bags.IsListMode() or ns.ListUsesColumn("track")) then
                        local rankText, trackColor = GetUpgradeTrack(itemLink)
                        if rankText and rankText ~= "" then
                            d._giTrackRank = rankText
                            d._giTrackColor = trackColor
                        elseif d._giIlvl and not (BP().itemlevelUseCustomColor and BP().itemlevelCustomColor) then
                            d._giTrackColor = EUI.GetCraftedTrackColor(itemLink)
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
            -- Controller cursor: the pointer may be hidden, so anchor to the window.
            EUI.ShowWidgetTooltip(EUI_Bags, "Positions can only be changed\nin the All Items, OneBag, or MultiBag views", (not EUI.PadInUse()) and { anchor = "cursor" } or nil)
            C_Timer.After(3, function()
                EUI.HideWidgetTooltip()
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
            if data.info and data.info.itemID and IsItemPinned(pinnedSet, data.itemLink, data.info.itemID) then
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
            show = data.info and data.info.itemID and pinnedSet and IsItemPinned(pinnedSet, data.itemLink, data.info.itemID)
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

    -- WoW Forever: special bags (ns.SpecialBags) stay out of the header's item
    -- and slot count; OneBag gives each one a section of its own.
    local special = ns.SpecialBags()
    local spItems, spEmpty, spBags = 0, 0, 0
    if special then
        for _ in pairs(special) do spBags = spBags + 1 end
        for _, d in ipairs(tempItems) do
            if special[d.bag] and d.itemLink then spItems = spItems + 1 end
        end
        for _, d in ipairs(emptySlots) do
            if special[d.bag] then spEmpty = spEmpty + 1 end
        end
    end

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
            -- OneBag / group view: a few sections (pinned/recent/main/reagent,
            -- plus OneBag's special bags)
            n = #tempItems + #emptySlots
            S = 3 + (selectedCategoryIndex == -1 and spBags or 0)
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
    -- List rows take the grip-set width (Auto-Size keeps column sizing)
    if EUI_Bags.IsListMode() and BP().bagListWidth and not BP().bagAutoSize then
        gridW = BP().bagListWidth
    end
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

    -- Both views below paint with the current panel state, merging or not
    -- (slot views and an unmerged list never reach MergeDuplicates)
    _paintedPanelOpen = _anyItemPanelOpen

    -- List display (latched per session): rows replace the grid; the column
    -- header bar takes the top of the scroll area
    if EUI_Bags.IsListMode() and sf then
        local listH, colHdrH = ns.RenderListView(displayItems, {
            -- Left / Right Gap: space between the list area edges and the rows
            rowW = math.max(100, gridW + gridPadX * 2 + scrollbarPad - (BP().bagListGapL or 15) - (BP().bagListGapR or 23)),
            startX = BP().bagListGapL or 15,
            leftX = sidebarW, topY = -(HEADER_H + 1),
            allItems = isAllItems,
            slotView = (selectedCategoryIndex == -1 and "one") or (selectedCategoryIndex == -2 and "multi") or nil,
            -- Same rule as the grid's Recent Items section
            recent = (showRecent and (isAllItems or (selectedCategoryIndex < 0 and BP().bagRecentInOneBag == true)))
                and EUI_Bags._recentItems or nil,
            -- Empty rows only when nothing is search-filtered out
            emptySlots = (#displayItems == #tempItems) and emptySlots or nil,
            -- Same rule as the grid's Pinned Items section
            pinned = (showPinned and (isAllItems or (selectedCategoryIndex < 0 and BP().bagPinnedInOneBag ~= false)))
                and pinnedSet or nil,
        })
        sf:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", sidebarW, -(HEADER_H + 1 + colHdrH))
        FinishRefresh(-(listH + colHdrH), gridW + gridPadX * 2 + scrollbarPad + 2, sidebarW, totalCount, #emptySlots, spItems, spEmpty)
        return
    end

    local curY = ns.RenderGridView(tempItems, displayItems, emptySlots, child, columns, gridW, gridPadX, showPinned, pinnedSet)

    FinishRefresh(curY, gridW + gridPadX * 2 + scrollbarPad + 2, sidebarW, totalCount, #emptySlots, spItems, spEmpty)
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
                            btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, fs, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
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
        if next(EUI_Bags.itemOverlayIcons) ~= nil then
            data.itemLink = itemLink
            EUI_Bags.RunItemOverlays(btn, data)
        end
        -- Tooltip requery after the slot re-assignment (see RenderButton).
        if GameTooltip:IsOwned(btn) then
            if data.info and btn.UpdateTooltip then btn:UpdateTooltip() else GameTooltip:Hide() end
        end

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

        -- Blizzard's bag bar order: backpack on the right, reagent bag on the left
        parent:ClearAllPoints()
        parent:SetPoint("TOPLEFT", EUI_BagsWindow, "TOPLEFT", startX + ((BAG_COLUMNS - 1 - i) * (SLOT_SIZE + SPACING)), startY)
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
    EUI_Bags:ApplyWindowLayering()
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
        self:Raise()
        local noShift = BP().bagMoveNoShift
        -- A controller's emulated Shift reads as a Shift key, not the physical
        -- left one, so it also counts while a controller is in use.
        if button ~= "LeftButton" or (not noShift and not IsKeyDown("LSHIFT")
            and not (IsShiftKeyDown() and EUI.PadInUse())) then return end
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
        PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
        CaptureTrackedGold()
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
    end)

    EUI_Bags:HookScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        EUI_Bags._closeSoundAt = GetTime()
        if EUI_Bags._searchBox then
            EUI_Bags._searchBox:SetText("")
            EUI_Bags._searchBox:ClearFocus()
        end
    end)

    -- An item on the cursor that is not from the player's bags (bank withdrawals, mail, etc.).
    local function CursorItemIsExternal()
        if GetCursorInfo() ~= "item" then return false end
        -- Check if the cursor item is from the player's bags (bag 0-5, reagent bag included)
        for bag = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.isLocked then
                    -- Locked = this slot is the pickup source
                    return false
                end
            end
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
    -- cursor item is from outside is a bag scan, cached until the cursor or an
    -- item lock changes. The events are registered only while the bags are
    -- open; everything is built on first use.
    local dropBorder, dropCatch
    local hoverFrame, hoverCatch = false, false
    local extCache, extDirty = false, true
    local function SyncDropBorder()
        if extDirty then
            extCache = CursorItemIsExternal()
            extDirty = false
        end
        local layer = extCache and EUI_Bags:IsVisible()
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
        if event == "CURSOR_CHANGED" or GetCursorInfo() == "item" then SyncDropBorder() end
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
    ApplyTrashCan()
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
    EUI_BagsReagent:HookScript("OnShow", EUI_BagsReagent.Raise)
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
    EUI_Bags._recentItems = {}      -- itemID -> true (set of recent item IDs)
    EUI_Bags._recentOrder = {}      -- ordered list of itemIDs (oldest first)
    local _knownItemCounts = {} -- itemID -> highest bag-visible count since the last bank/mail resync
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
            if count > known and not EUI_Bags._recentItems[itemID] then
                EUI_Bags._recentItems[itemID] = true
                EUI_Bags._recentOrder[#EUI_Bags._recentOrder + 1] = itemID
                while #EUI_Bags._recentOrder > RECENT_MAX do
                    local old = table.remove(EUI_Bags._recentOrder, 1)
                    EUI_Bags._recentItems[old] = nil
                end
            end
            if not atMail or count > known then
                _knownItemCounts[itemID] = count
            end
        end
        -- Items gone from bags entirely (sold/used/deleted) no longer appear
        -- in `counts`; drop their known peak too. Equipped is not disposed:
        -- without the guard, swapping gear on (peak pruned) and later off
        -- again (count rises from 0) would re-flag every swapped piece as
        -- recent and FIFO-evict genuine loot.
        -- Skipped at the mailbox for the same reason drops are ignored above: an item
        -- gone from bags there was as likely posted or sent as disposed of, and
        -- dropping its peak would re-flag it as new the moment it came back.
        if not atMail then
            for itemID in pairs(_knownItemCounts) do
                if not counts[itemID] and not C_Item.IsEquippedItem(itemID) then
                    _knownItemCounts[itemID] = nil
                end
            end
        end
    end

    -- "Clear" link on the Recent Items headers. Only the tracked set is dropped --
    -- _knownItemCounts already holds each item's current bag total, so nothing
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
    EUI_Bags:RegisterEvent("PLAYER_MONEY")
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
    EUI_Bags:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        elseif event == "PLAYER_MONEY" then
            CaptureTrackedGold()
            UpdateBagMoneyDisplay()
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
        -- Controller cursor: a Back press or a bank close hides the bags
        -- alone, so the pin/assign selection and the detached reagent window
        -- go with them (a real close only, not a hidden UI).
        if EUI.PadInUse() and not EUI_Bags:IsShown() then
            if EUI_Bags._pinSelectMode then ExitPinSelectMode() end
            if EUI_Bags._assignSelectMode then ExitAssignSelectMode() end
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
end)

-------------------------------------------------------------------------------
--  Shared with EllesmereUIBags_Grid.lua (loads after this file)
-------------------------------------------------------------------------------
function ns.GetSelection() return selectedCategoryIndex, selectedGroupName end
function ns.SetSelection(idx, group) selectedCategoryIndex, selectedGroupName = idx, group end
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
ns.VisualSortCompare = VisualSortCompare
ns.MergeDuplicates = MergeDuplicates
ns.ApplySavedOrder = ApplySavedOrder
ns.BuildExpansionBuckets = BuildExpansionBuckets
ns.BuildSlotBuckets = BuildSlotBuckets
ns.ArmorySlotGroupingEnabled = ArmorySlotGroupingEnabled
ns.IsArmoryGearCategory = IsArmoryGearCategory
ns.IsGearOnlyGroup = IsGearOnlyGroup
ns.GetOrCreateCatHeader = GetOrCreateCatHeader
ns.GetOrCreateExpSubHeader = GetOrCreateExpSubHeader
ns.ShowRecentClearButton = ShowRecentClearButton
ns.GetOrCreatePinOverlay = GetOrCreatePinOverlay
ns.GetOrCreateAssignOverlay = GetOrCreateAssignOverlay
ns.ResetAssignOverlays = ResetAssignOverlays
