if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_DB.lua
--  Bags profile database + login-time seeding. Lives in the resident module
--  (first in the TOC, the options file's old slot) so the DB exists from login
--  regardless of the LoadOnDemand options surface. NewDB stays at Bags
--  file-execution time: the suite-safe window (after the parent's SVs) and, in
--  standalone builds, the pre-SV window the Lite re-root queue handles.
-------------------------------------------------------------------------------
local BAGS_DEFAULTS = {
    profile = {
        bagScale              = 1,
        bagItemIconZoom       = 0.08,
        bagColumns            = 12,
        bagAutoSize           = false,
        bagCatTitleSize       = 11,
        bagCountFontSize      = 11,
        itemlevelFontSize     = 12,
        showItemlevelInBags   = true,
        showUpgradeIndicator  = true,
        bagShowTrackRank      = false,
        itemlevelUseCustomColor = false,
        bagHideEmptyCategories = true,
        bagSplitSetGearBySet  = false,
        bagShowSetGearName    = false,
        bagSetNameFontSize    = 9,
        bagMergeDuplicates    = true,
        bagListMergeDuplicates = false,
        bagSidebarCollapsed   = false,
        bankSidebarCollapsed  = false,
        bagShowPinnedItems    = true,
        bagShowRecentItems    = true,
        bagPinnedInOneBag     = true,
        bagRecentInOneBag     = false,
        bagShowRecentClear    = false,
        bagShowPinRecentTips  = true,
        bagShowSortIcon       = true,
        bagSortToBottom       = false,
        bagHideRandomize      = false,
        bagDefaultBagType     = "all",   -- "all" | "onebag" | "multibag"
        bagDefaultOneBag      = false,   -- legacy; migrated to bagDefaultBagType
        bagNestByExpansion    = false,
        bankNestByExpansion   = false,
        bankGroupByCategory   = false,
        bankCategorySidebar   = false,
        bankHideTabsInSidebar = false,
        bankHideEmptyWhenNested = false,
        bankListView          = false,  -- reload to apply
        bagArmoryGroupBySlot  = false,
        bagCompactArmorySlotGroups = false,
        bagHideOneBagWarning  = false,
        bagHideAddCategory    = false,
        bagMoveNoShift        = false,
        bagAllowWindowsOverBags = true,
        bagStackSplitter      = false,
        bagTrashCan           = false,
        enableGoldTracking    = true,
        detachReagentBag      = false,
        enhancedBags          = true,
        bagDesaturateJunkItems = false,
        bagDisplayBindType    = false,
        bagBindTypeFontSize   = 11,
        -- Junk Marker: whole feature is OFF by default (master toggle lives in
        -- Bags -> Extras). When on, a "Junk" category collects grey (Poor)
        -- items plus anything the player marks, a header button enters
        -- junk-select mode, and a Sell Junk button appears at vendors.
        bagJunkMarker         = false,
        bagJunkAutoSell       = false,   -- auto-sell junk when a merchant opens
        bagJunkOneBag         = false,   -- pull junk into its own category in One Bag
        bagJunkMultiBag       = false,   -- pull junk into its own category in MultiBag
        bagJunkAtTop          = false,   -- render the pulled-out Junk section at top (below Pinned) vs bottom
        bagJunkCoinCorner     = "BOTTOMLEFT",  -- corner for the on-item junk coin badge (TL/TR/BL/BR)
        bagJunkNoSellSummary  = false,   -- suppress the "Sold N junk item(s)" chat line after selling
        bagJunkSortByValue    = false,   -- opt in: order the Junk category by vendor value (else normal saved/visual order)
        bagJunkShowInRecent   = true,    -- show junk items in the Recent Items section (off to declutter Recent)
        bagDisplayMode        = "grid",  -- "grid" | "list" (reload to apply)
        bagListRoundIcons     = false,
        bagListSplitArmor     = false,
        bagListSplitWeapons   = false,
        bagListSplitProfessions = false,
        bagListGapL           = 15,
        bagListGapR           = 23,
        bagListFontSize       = 11,
        bagListRowHeight      = 24,
        bagListQualityBorder  = false,
        bagListHideStripes    = false,
        bagListSectionValue   = false,
    },
}
local db = EllesmereUI.Lite.NewDB("EllesmereUIBagsDB", BAGS_DEFAULTS)
EllesmereUI._bagsDB = db

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUIDB then EllesmereUIDB = {} end
    local p = db.profile

    -- The bank grouping dropdowns were replaced by two toggles. Convert the
    -- short-lived string keys once, then drop them.
    if p.bankGroupBy ~= nil then
        if p.bankGroupBy == "category" then
            p.bankGroupByCategory = true
        elseif p.bankGroupBy == "expansion" then
            p.bankNestByExpansion = true
        end
        p.bankGroupBy = nil
        p.bankSubGroupBy = nil
    end

    -- Default disabled categories: Housing and Quest Items off by default
    if EllesmereUIDB.bagDisabledCategoriesSeeded == nil then
        EllesmereUIDB.bagDisabledCategoriesSeeded = true
        if not p.bagDisabledCategories then p.bagDisabledCategories = {} end
        p.bagDisabledCategories["Housing"] = true
        p.bagDisabledCategories["Quest Items"] = true
    end

    -- Default category groups and order
    if not EllesmereUIDB.bagDefaultGroupsSeeded then
        EllesmereUIDB.bagDefaultGroupsSeeded = true
        -- Only seed if user has no existing customization
        if not p.bagCategoryState and not p.bagCategoryOrder then
            p.bagCategoryState = {
                ["Weapons / Trinkets"] = { groupName = "The Armory", groupNameCustom = true },
                ["Armor"]              = { groupName = "The Armory", groupNameCustom = true },
                ["Item Set Gear"]      = { groupName = "The Armory", groupNameCustom = true },
                ["Consumables"]        = { groupName = "Adventure Prep", groupNameCustom = true },
                ["Gear Enhancements"]  = { groupName = "Adventure Prep", groupNameCustom = true },
            }
            p.bagCategoryOrder = {
                "Pinned Items",
                "Recent Items",
                "Weapons / Trinkets",
                "Armor",
                "Item Set Gear",
                "Consumables",
                "Gear Enhancements",
                "Trade Goods",
                "Professions",
                "Reagent Bag",
                "Miscellaneous",
                "Quest Items",
                "Housing",
            }
            -- Re-init categories with the new state
            if _G.EUI_CategoryManager then
                _G.EUI_CategoryManager:InitCategories()
            end
        end
    end
    -- Migrate old numeric-keyed disabled categories to name-keyed
    if p.bagDisabledCategories and _G.EUI_CategoryManager then
        local dc = p.bagDisabledCategories
        local cats = _G.EUI_CategoryManager:GetCategories()
        local migrated = {}
        local changed = false
        for k, v in pairs(dc) do
            if type(k) == "number" then
                if cats[k] then migrated[cats[k]._defaultName] = v end
                changed = true
            else
                migrated[k] = v
            end
        end
        if changed then p.bagDisabledCategories = migrated end
    end
end)
