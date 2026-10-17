if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags.lua -- Enhanced Bags System for EllesmereUI (Midnight): sidebar category filter + flat item grid layout.
-------------------------------------------------------------------------------
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewCombatQueue and EllesmereUI.CreateQuantityDialog) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the stack splitter is the parent's quantity window)
local ns = select(2, ...)
EllesmereUI._ModuleNS["EllesmereUIBags"] = ns  -- LOD options files read this module ns via the registry
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

EUI_Bags = CreateFrame("Frame", "EUI_MainBagFrame", UIParent)
EUI_Bags:SetToplevel(true)
EUI_Bags:Hide()
-- Auto-size state: reset on close (next open sizes from its first/active tab);
-- while open it only grows, never shrinks.
EUI_Bags:HookScript("OnHide", function(self)
    -- WoW Forever and the Compact display size every open to its content: a hidden UI (Alt-Z) is not a close, keep the size.
    if (EllesmereUI.IS_FOREVER or EUI_Bags.IsCompactMode()) and self:IsShown() then return end
    self._asCols  = nil
    self._asMaxGridW = nil
    self._asMaxH  = nil
    -- The Compact display's grow-only width (RefreshInventory)
    self._compactCols, self._compactW = nil, nil
end)

EUI_BagsReagent = CreateFrame("Frame", "EUI_ReagentBagFrame", UIParent)
EUI_BagsReagent:Hide()

EUI_BagsWindow = CreateFrame("Frame", "EUI_BagsWindowFrame", UIParent)
EUI_BagsWindow:Hide()

local SLOT_SIZE, SPACING = 34, 4
local GetItemInfoInstant = C_Item.GetItemInfoInstant
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
-- stay out of Main Bags, the header count, OneBag's sort, Auto Split and drop
-- placement. nil on retail or with none equipped; the next call reuses the
-- set, so read it right away.
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

-- Uninstall EUI: Sort to Bottom flips Blizzard's own sort direction, so the
-- player's is handed back, as turning the option off does.
EUI.OnUninstall(function()
    local p = BP()
    if p.bagSortToBottom and p.bagSortBlizzRTLWas ~= nil then
        C_Container.SetSortBagsRightToLeft(p.bagSortBlizzRTLWas)
    end
end)

-- Frame Strata: the layer of the bags and the bank. Unset reads the retired
-- Allow Windows Over Bags toggle (off = High), so its choice carries over.
function ns.BagFrameStrata()
    local p = BP()
    return p.bagFrameStrata or (p.bagAllowWindowsOverBags == false and "HIGH" or "MEDIUM")
end

local layerUpdateFrame = CreateFrame("Frame")
function EUI_Bags:ApplyWindowLayering()
    -- The bank's purchase buttons are secure, so defer layer changes in combat.
    if InCombatLockdown() then
        layerUpdateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    layerUpdateFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local strata = ns.BagFrameStrata()
    self:SetFrameStrata(strata)
    -- High starts above that layer's other windows, as the retired toggle's
    -- off state did; every other layer starts at its bottom
    self:SetFrameLevel(strata == "HIGH" and 100 or 1)
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
-- ROOT beside the module's other per-character data (goldLedger,
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

-- Bag display mode ("grid" | "list" | "compact"), latched on the first read
-- after the profile loads: switching needs a reload, so only one mode ever
-- builds frames in a session. nil = profile not loaded yet (nothing latched).
-- Any other saved value reads as "grid".
local _listMode
function EUI_Bags.IsListMode()
    if _listMode == nil then
        if not EUI.Lite.IsDBReady() then return nil end
        local mode = BP().bagDisplayMode
        _listMode = mode == "list"
        EUI_Bags._compactMode = mode == "compact"
    end
    return _listMode
end
-- Compact display (EllesmereUIBags_Compact.lua), on IsListMode's latch
function EUI_Bags.IsCompactMode()
    if EUI_Bags.IsListMode() == nil then return nil end
    return EUI_Bags._compactMode
end
-- Auto-Size to Fit: not offered with the List display (its rows take the
-- grip-set width), so a value saved under another display stays off there
function EUI_Bags.AutoSizeOn()
    return BP().bagAutoSize == true and not EUI_Bags.IsListMode()
end

local function ApplyBagScale()
    local s = BP().bagScale or 1
    if EUI_Bags then EUI_Bags:SetScale(s) end
    if EUI_BagsReagent then EUI_BagsReagent:SetScale(s) end
    if EUI_BagsWindow then EUI_BagsWindow:SetScale(s) end
end

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
    if EUI_Bags and EUI_Bags._asCols and EUI_Bags.AutoSizeOn() then
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

-- Main-chunk locals of this file the EUI_Bags_*.lua files re-import by name;
-- each of them adds what the files behind it need.
-- categoryIndexSetters and the lists beside it: every file that reads one of
-- these values keeps its own copy and adds a setter here; each place that
-- assigns it writes through the Set<Name> function built below, which runs
-- them all.
-- broken: true while an EUI_Bags_*.lua file loads; a file that fails leaves
-- it set, and the files behind it return at their first lines.
ns._bagsInternals = {
    _bankRouted = _bankRouted, AbbrevDungeon = AbbrevDungeon, ApplyBagScale = ApplyBagScale,
    BagsItemUnusable = BagsItemUnusable, BP = BP, CurrencyOrder = CurrencyOrder,
    GetAccentRGB = GetAccentRGB, GetCatTitleSize = GetCatTitleSize, GetColumns = GetColumns,
    GetDefaultBagType = GetDefaultBagType, GetFont = GetFont,
    GetItemLevelAtLocation = GetItemLevelAtLocation, IsGearItem = IsGearItem,
    IsItemPinned = IsItemPinned, NormalizePinKey = NormalizePinKey, SetBagFont = SetBagFont,
    SLOT_SIZE = SLOT_SIZE, SPACING = SPACING,
    categoryIndexSetters = {}, groupNameSetters = {}, gearCatSetSetters = {},
    anyItemPanelOpenSetters = {}, paintedPanelOpenSetters = {},
    broken = false,
}
-- Set<Name> hands a new value to every copy registered in <name>Setters.
for setter, listName in pairs({
    SetSelectedCategoryIndex = "categoryIndexSetters",
    SetSelectedGroupName = "groupNameSetters", SetGearCatSet = "gearCatSetSetters",
    SetAnyItemPanelOpen = "anyItemPanelOpenSetters",
    SetPaintedPanelOpen = "paintedPanelOpenSetters",
}) do
    local list = ns._bagsInternals[listName]
    ns._bagsInternals[setter] = function(v)
        for i = 1, #list do list[i](v) end
    end
end
-- A re-import of a name this table lacks fails where the part file loads,
-- not later as a nil upvalue inside one of its functions.
setmetatable(ns._bagsInternals, { __index = function(_, k)
    error("ns._bagsInternals has no entry " .. tostring(k), 2)
end })
