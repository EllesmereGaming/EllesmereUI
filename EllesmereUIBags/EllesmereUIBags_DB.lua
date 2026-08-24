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
        bankColumns           = 14,
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
        bagSidebarCollapsed   = false,
        bankSidebarCollapsed  = false,
        bagShowPinnedItems    = true,
        bagShowRecentItems    = true,
        bagPinnedInOneBag     = true,
        bagRecentInOneBag     = false,
        bagShowPinRecentTips  = true,
        bagShowSortIcon       = true,
        bagSortToBottom       = false,
        bagHideRandomize      = false,
        bagDefaultBagType     = "all",   -- "all" | "onebag" | "multibag"
        bagDefaultOneBag      = false,   -- legacy; migrated to bagDefaultBagType
        bagNestByExpansion    = false,
        bagArmoryGroupBySlot  = false,
        bagCompactArmorySlotGroups = false,
        bagHideOneBagWarning  = false,
        bagHideAddCategory    = false,
        bagMoveNoShift        = false,
        enableGoldTracking    = true,
        detachReagentBag      = false,
        enhancedBags          = true,
        bagDesaturateJunkItems = false,
        bagDisplayBindType    = false,
        bagBindTypeFontSize   = 11,
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
