if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_Categories.lua
--  Category system based on Enum.ItemClass numeric IDs (locale-safe).
--  Categories are hardcoded definitions. Users can rename, reorder, and group
--  them via sidebar context menus. Icons and type rules are not customizable.
-------------------------------------------------------------------------------

local CategoryManager = {}
-- Profile access helper (DB created in EUI_Bags_Options.lua, loaded first per TOC)
local EUI = EllesmereUI
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end

-- Enum.ItemClass numeric IDs (locale-independent)
local IC = Enum.ItemClass
local IC_CONSUMABLE    = IC.Consumable       -- 0
local IC_CONTAINER     = IC.Container        -- 1
local IC_WEAPON        = IC.Weapon           -- 2
local IC_GEM           = IC.Gem              -- 3
local IC_ARMOR         = IC.Armor            -- 4
local IC_REAGENT       = IC.Reagent          -- 5
local IC_TRADESKILL    = IC.Tradegoods       -- 7
local IC_ITEM_ENHANCE  = IC.ItemEnhancement  -- 8
local IC_RECIPE        = IC.Recipe           -- 9
local IC_QUEST         = IC.Questitem        -- 12
local IC_MISC          = IC.Miscellaneous    -- 15
local IC_PROFESSION    = 19                  -- Enum.ItemClass.Profession (Midnight)
local IC_HOUSING       = 20                  -- Enum.ItemClass.Housing (Midnight)

-- Hardcoded category definitions. Order here is the default order.
-- types = list of Enum.ItemClass numeric IDs to match
-- Empty types = catch-all (Uncategorized)
local DEFAULT_CATEGORIES = {
    { name = "Pinned Items",       types = {}, isPinned = true, noGroup = true, noMove = true, icon = "friendslist-recentallies-Pin-yellow", isAtlas = true },
    { name = "Recent Items",       types = {}, isRecent = true, noGroup = true, noMove = true, icon = "auctionhouse-icon-clock", isAtlas = true },
    { name = "Reagent Bag",        types = {}, isReagentBag = true, noGroup = true, icon = 3622222 },
    { name = "Item Set Gear",      types = { IC_ARMOR, IC_WEAPON }, isSetGear = true, icon = 4871338 },
    { name = "Quest Items",        types = { IC_QUEST },                     icon = "Crosshair_Quest_64", isAtlas = true },
    { name = "Weapons / Trinkets", types = { IC_WEAPON }, equipSlots = { "INVTYPE_TRINKET" }, icon = 3751725 },
    { name = "Armor",              types = { IC_ARMOR }, excludeEquipSlots = { "INVTYPE_TRINKET" }, icon = 4382688 },
    { name = "Consumables",        types = { IC_CONSUMABLE },                icon = 7548911 },
    { name = "Trade Goods",        types = { IC_TRADESKILL, IC_REAGENT },    icon = 132996 },
    { name = "Gear Enhancements",  types = { IC_GEM, IC_ITEM_ENHANCE },     icon = 7549094 },
    { name = "Professions",        types = { IC_PROFESSION, IC_RECIPE },     icon = 7548925 },
    { name = "Housing",            types = { IC_HOUSING },                   icon = 7726459 },
    { name = "Miscellaneous",      types = { IC_MISC, IC_CONTAINER }, isCatchAll = true, icon = 5524917 },
}

-------------------------------------------------------------------------------
--  Profession split
--  Replaces the Trade Goods / Professions / Reagent Bag trio with a single
--  "Professions" anchor carrying one child category per profession, the same
--  runtime-only child pattern the "Item Set Gear" anchor uses for equipment
--  sets. Gated on bagSplitByProfession; everything below is inert while off.
-------------------------------------------------------------------------------
local PROFESSION_ORDER = {
    -- Gathering first: raw materials are filed under the profession that
    -- gathers them, not the one that consumes them.
    "Mining", "Herbalism", "Skinning", "Fishing",
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Inscription",
    "Jewelcrafting", "Leatherworking", "Tailoring", "Cooking",
}

-- Texture paths rather than file IDs: these names have been stable since
-- Classic and survive art re-imports that renumber file IDs.
local PROFESSION_ICONS = {
    Mining         = "Interface\\Icons\\Trade_Mining",
    Herbalism      = "Interface\\Icons\\Trade_Herbalism",
    Skinning       = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    Fishing        = "Interface\\Icons\\Trade_Fishing",
    Alchemy        = "Interface\\Icons\\Trade_Alchemy",
    Blacksmithing  = "Interface\\Icons\\Trade_BlackSmithing",
    Enchanting     = "Interface\\Icons\\Trade_Engraving",
    Engineering    = "Interface\\Icons\\Trade_Engineering",
    Inscription    = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    Jewelcrafting  = "Interface\\Icons\\INV_Misc_Gem_01",
    Leatherworking = "Interface\\Icons\\Trade_LeatherWorking",
    Tailoring      = "Interface\\Icons\\Trade_Tailoring",
    Cooking        = "Interface\\Icons\\INV_Misc_Food_15",
}

-- Base (Classic-era) skill line IDs, used only to ask the client for a
-- localized profession name. Stable across expansions.
local PROFESSION_SKILL_LINES = {
    Mining = 186, Herbalism = 182, Skinning = 393, Fishing = 356,
    Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202,
    Inscription = 773, Jewelcrafting = 755, Leatherworking = 165,
    Tailoring = 197, Cooking = 185,
}

local _profNameCache = {}
local function ProfessionDisplayName(key)
    local cached = _profNameCache[key]
    if cached then return cached end
    local name
    local sl = PROFESSION_SKILL_LINES[key]
    if sl and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, res = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, sl)
        if ok and type(res) == "string" and res ~= "" then name = res end
    end
    -- Only a real skill-line name is cached: GetTradeSkillDisplayName can be
    -- unavailable on the first build, and nothing invalidates this cache.
    if not name then return EllesmereUI.L(key) end
    _profNameCache[key] = name
    return name
end

-- Subclass maps are built from the Enum field names, not hardcoded numbers, so
-- a client that lacks a subclass simply omits that entry instead of erroring.
-- Trade goods subclass IDs are written out numerically on purpose: there is no
-- Enum.ItemTradegoodsSubclass in this client (Enum.ItemRecipeSubclass does
-- exist and is used below). These IDs are stable game data -- Blizzard renames
-- subclasses, as Meat became Cooking, but does not renumber them.
local TG_PARTS, TG_EXPLOSIVES, TG_DEVICES   = 1, 2, 3
local TG_JEWELCRAFTING, TG_CLOTH, TG_LEATHER = 4, 5, 6
local TG_METAL_STONE, TG_COOKING, TG_HERB    = 7, 8, 9
local TG_ELEMENTAL                           = 10
local TG_ENCHANTING                          = 12
local TG_ITEM_ENCHANT, TG_WEAPON_ENCHANT     = 14, 15
local TG_INSCRIPTION, TG_EXPLOSIVES_DEVICES  = 16, 17

-- Raw materials are filed under the profession that GATHERS them, so ore is
-- Mining rather than Blacksmithing and hides are Skinning rather than
-- Leatherworking. Cloth is the exception only because nothing gathers it.
-- Generic crafting reagents (Other, Materials, Optional/Finishing Reagents)
-- are deliberately absent: they stay on the Professions anchor.
local TRADEGOODS_TO_PROFESSION = {
    [TG_HERB]               = "Herbalism",
    [TG_METAL_STONE]        = "Mining",
    [TG_ELEMENTAL]          = "Mining",
    [TG_LEATHER]            = "Skinning",
    [TG_COOKING]            = "Cooking",
    [TG_CLOTH]              = "Tailoring",
    [TG_ENCHANTING]         = "Enchanting",
    [TG_ITEM_ENCHANT]       = "Enchanting",
    [TG_WEAPON_ENCHANT]     = "Enchanting",
    [TG_JEWELCRAFTING]      = "Jewelcrafting",
    [TG_INSCRIPTION]        = "Inscription",
    [TG_PARTS]              = "Engineering",
    [TG_EXPLOSIVES]         = "Engineering",
    [TG_DEVICES]            = "Engineering",
    [TG_EXPLOSIVES_DEVICES] = "Engineering",
}

local RECIPE_TO_PROFESSION = {}
do
    local RC = Enum.ItemRecipeSubclass
    local function put(key, fallback, prof)
        local id = RC and RC[key]
        if id == nil then id = fallback end
        if id ~= nil then RECIPE_TO_PROFESSION[id] = prof end
    end
    put("Leatherworking", 1,  "Leatherworking")
    put("Tailoring",      2,  "Tailoring")
    put("Engineering",    3,  "Engineering")
    put("Blacksmithing",  4,  "Blacksmithing")
    put("Cooking",        5,  "Cooking")
    put("Alchemy",        6,  "Alchemy")
    put("Enchanting",     8,  "Enchanting")
    put("Fishing",        9,  "Fishing")
    put("Jewelcrafting",  10, "Jewelcrafting")
    put("Inscription",    11, "Inscription")
end

-- Knowledge items carry no class/subclass signal that names their profession,
-- so they need an explicit list. Item IDs cover The War Within and Midnight.
-- STALENESS: this is a static snapshot and will not cover professions added in
-- a later patch -- those items fall through to the Professions anchor rather
-- than a child, which is a cosmetic miss, not a break.
local KNOWLEDGE_ITEM_PROFESSION = {}
do
    local function Add(prof, ...)
        for i = 1, select("#", ...) do
            KNOWLEDGE_ITEM_PROFESSION[select(i, ...)] = prof
        end
    end
    Add("Alchemy",
        222546, 224024, 224645, 225234, 225235, 226265, 226266, 226267, 226268, 226269,
        226270, 226271, 226272, 227409, 227420, 227431, 228724, 228773, 232499, 235865,
        238532, 238533, 238534, 238535, 238536, 238537, 238538, 238539, 245755, 259188,
        259189, 262645, 263454, 274500
    )

    Add("Blacksmithing",
        222554, 224038, 224647, 225232, 225233, 226276, 226277, 226278, 226279, 226280,
        226281, 226282, 226283, 227407, 227418, 227429, 228726, 228774, 232500, 235864,
        238540, 238541, 238542, 238543, 238544, 238545, 238546, 238547, 245763, 246322,
        259190, 259191, 262644, 263455, 274515
    )

    Add("Enchanting",
        222550, 224050, 224652, 225230, 225231, 226284, 226285, 226286, 226287, 226288,
        226289, 226290, 226291, 227411, 227422, 227433, 227659, 227661, 227662, 227667,
        232501, 235863, 238548, 238549, 238550, 238551, 238552, 238553, 238554, 238555,
        245759, 250445, 257600, 259192, 259193, 263464, 267653, 267654, 267655, 274511
    )

    Add("Engineering",
        222621, 224052, 224653, 225228, 225229, 226292, 226293, 226294, 226295, 226296,
        226297, 226298, 226299, 227412, 227423, 227434, 228730, 228775, 232507, 235862,
        238556, 238557, 238558, 238559, 238560, 238561, 238562, 238563, 245809, 246326,
        259194, 259195, 262646, 263456, 274516
    )

    Add("Herbalism",
        222552, 224023, 224264, 224265, 224656, 224817, 224835, 226300, 226301, 226302,
        226303, 226304, 226305, 226306, 226307, 227415, 227426, 227437, 232503, 235861,
        238465, 238466, 238467, 238468, 238469, 238470, 238471, 238472, 238473, 238474,
        238475, 245761, 250443, 258410, 263462, 274513
    )

    Add("Inscription",
        222548, 224053, 224654, 225226, 225227, 226308, 226309, 226310, 226311, 226312,
        226313, 226314, 226315, 227408, 227419, 227430, 228732, 228776, 232508, 235860,
        238572, 238573, 238574, 238575, 238576, 238577, 238578, 238579, 245757, 246328,
        258411, 259196, 259197, 263457, 274514
    )

    Add("Jewelcrafting",
        222551, 224054, 224655, 225224, 225225, 226316, 226317, 226318, 226319, 226320,
        226321, 226322, 226323, 227413, 227424, 227435, 228734, 228777, 232504, 235859,
        238580, 238581, 238582, 238583, 238584, 238585, 238586, 238587, 245760, 246330,
        257599, 259198, 259199, 263458, 274510
    )

    Add("Leatherworking",
        222549, 224056, 224658, 225222, 225223, 226324, 226325, 226326, 226327, 226328,
        226329, 226330, 226331, 227414, 227425, 227436, 228736, 228778, 232505, 235858,
        238588, 238589, 238590, 238591, 238592, 238593, 238594, 238595, 245758, 246332,
        250922, 259200, 259201, 263459, 274507
    )

    Add("Mining",
        222553, 224055, 224583, 224584, 224651, 224818, 224838, 226332, 226333, 226334,
        226335, 226336, 226337, 226338, 226339, 227416, 227427, 227438, 232509, 235857,
        237496, 237506, 237507, 238596, 238597, 238598, 238599, 238600, 238601, 238602,
        238603, 245762, 250444, 250924, 263463, 274509
    )

    Add("Skinning",
        222649, 224007, 224657, 224780, 224781, 224782, 224807, 226340, 226341, 226342,
        226343, 226344, 226345, 226346, 226347, 227417, 227428, 227439, 232506, 235856,
        238625, 238626, 238627, 238628, 238629, 238630, 238631, 238632, 238633, 238634,
        238635, 245828, 250360, 250923, 263461, 274508
    )

    Add("Tailoring",
        222547, 224036, 224648, 225220, 225221, 226348, 226349, 226350, 226351, 226352,
        226353, 226354, 226355, 227410, 227421, 227432, 228738, 228779, 232502, 235855,
        238612, 238613, 238614, 238615, 238616, 238617, 238618, 238619, 245756, 246334,
        257601, 259202, 259203, 263460, 274512
    )
end

local function GetItemProfession(itemLink, itemID)
    if itemID then
        local known = KNOWLEDGE_ITEM_PROFESSION[itemID]
        if known then return known end
    end
    if not itemLink then return nil end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemLink)
    if classID == nil or subclassID == nil then return nil end
    if classID == IC_TRADESKILL then
        return TRADEGOODS_TO_PROFESSION[subclassID]
    end
    if classID == IC_RECIPE then
        return RECIPE_TO_PROFESSION[subclassID]
    end
    -- IC_PROFESSION (Midnight, class 19) subclass numbering is not verified,
    -- and misfiling is worse than not filing: those items fall through to the
    -- anchor unless the knowledge list above already named them.
    return nil
end

local function ProfessionSplitEnabled()
    return BP().bagSplitByProfession == true
end

-- The reagent bag is a location, not a category. It is always shown as a view
-- alongside OneBag / All Items / MultiBag, the category is dropped, and its
-- contents classify by type like anything else -- so a stack of ore appears
-- under both the Reagent Bag view and Mining. Unconditional by design: this
-- is the one place the patch diverges from stock with every toggle off.
local function ReagentBagIsView()
    return true
end
EllesmereUI._BagsReagentBagIsView = ReagentBagIsView

-- Which built-in categories are dissolved, and by which toggle.
local function CategoryIsDissolved(defName)
    if defName == "Trade Goods" then return ProfessionSplitEnabled() end
    if defName == "Reagent Bag" then return ReagentBagIsView() end
    return false
end

-------------------------------------------------------------------------------
--  Init
--  Builds the runtime category list from hardcoded defaults + saved user state
--  (renames, reorder, grouping). Saved state keyed by default name.
-------------------------------------------------------------------------------
function CategoryManager:InitCategories()
    -- The category list is a DERIVATION of db.profile, cached in _categories
    -- and read BACK by SaveState. In a standalone build every file executes
    -- before the SavedVariables load, so an early build necessarily sees
    -- defaults and BP()'s empty-table fallback hides that. Record whether this
    -- build saw a trustworthy profile; GetCategories re-runs until one did.
    -- Missing framework counts as NOT ready, so the answer can only improve.
    local Lite = EllesmereUI and EllesmereUI.Lite
    self._builtReady = (Lite and Lite.IsDBReady and Lite.IsDBReady()) or false
    -- User state: { [defaultName] = { rename, groupName, groupNameCustom } }
    local userState = BP().bagCategoryState or {}
    -- User order: list of default names in display order
    local userOrder = BP().bagCategoryOrder

    -- Build ordered list of default names
    -- Index DEFAULT_CATEGORIES by name for fast lookup
    local defByName = {}
    for _, def in ipairs(DEFAULT_CATEGORIES) do
        defByName[def.name] = def
    end
    -- Index user-created custom categories by key
    local userCatByKey = {}
    local userCats = BP().bagUserCategories
    if userCats then
        for _, uc in ipairs(userCats) do
            userCatByKey[uc.key] = uc
        end
    end

    local orderedDefs = {}
    if userOrder and #userOrder > 0 then
        -- Use saved order, restoring both built-in and custom categories
        -- at their saved positions
        local seen = {}
        for _, defName in ipairs(userOrder) do
            local def = defByName[defName]
            if def then
                orderedDefs[#orderedDefs + 1] = def
                seen[defName] = true
            elseif userCatByKey[defName] then
                -- Custom category placeholder: mark with _isCustom so the
                -- category builder below can create it at this position
                orderedDefs[#orderedDefs + 1] = { name = defName, _isCustom = true }
                seen[defName] = true
            end
        end
        -- Append any new built-in defaults not in the saved order
        for _, def in ipairs(DEFAULT_CATEGORIES) do
            if not seen[def.name] then
                if def.noMove then
                    -- noMove categories always go to the top
                    table.insert(orderedDefs, 1, def)
                else
                    -- Insert before catch-all
                    local insertIdx = #orderedDefs
                    for i, od in ipairs(orderedDefs) do
                        if od.isCatchAll then insertIdx = i; break end
                    end
                    table.insert(orderedDefs, insertIdx, def)
                end
            end
        end
    else
        for _, def in ipairs(DEFAULT_CATEGORIES) do
            orderedDefs[#orderedDefs + 1] = def
        end
    end

    -- Force noMove categories to the top (in their DEFAULT_CATEGORIES order)
    local pinnedSet = {}
    for _, def in ipairs(orderedDefs) do
        if def.noMove then pinnedSet[def.name] = true end
    end
    local pinned = {}
    -- Use DEFAULT_CATEGORIES order for noMove items (not saved order)
    for _, def in ipairs(DEFAULT_CATEGORIES) do
        if def.noMove and pinnedSet[def.name] then pinned[#pinned + 1] = def end
    end
    local rest = {}
    for _, def in ipairs(orderedDefs) do
        if not def.noMove then rest[#rest + 1] = def end
    end
    orderedDefs = {}
    for _, d in ipairs(pinned) do orderedDefs[#orderedDefs + 1] = d end
    for _, d in ipairs(rest) do orderedDefs[#orderedDefs + 1] = d end

    -- Build runtime categories from ordered defaults + user state.
    -- Custom category placeholders (_isCustom) are expanded inline so
    -- they keep their saved position relative to built-in categories.
    local cats = {}
    local customInserted = {}
    for _, def in ipairs(orderedDefs) do
        if def._isCustom then
            -- Expand custom category placeholder at its saved position
            local uc = userCatByKey[def.name]
            if uc then
                local ucState = userState[uc.key]
                local ucIcon = uc.icon or 134400
                local ucIsAtlas = type(ucIcon) == "string"
                cats[#cats + 1] = {
                    _defaultName  = uc.key,
                    name          = (ucState and ucState.rename) or uc.name,
                    types         = {},
                    icon          = ucIcon,
                    isAtlas       = ucIsAtlas or nil,
                    isUserCreated = true,
                    groupName     = ucState and ucState.groupName,
                    groupNameCustom = ucState and ucState.groupNameCustom,
                }
                customInserted[uc.key] = true
            end
        elseif CategoryIsDissolved(def.name) then
            -- Trade Goods folds into the Professions anchor; Reagent Bag becomes
            -- a location view. Either way the category is not emitted.
        else
            local state = userState[def.name]
            local isProfAnchor = ProfessionSplitEnabled() and def.name == "Professions"
            local defTypes = def.types
            if isProfAnchor then
                -- Absorb the trade goods classes so reagents and materials
                -- reach the anchor and can be routed to a profession child.
                defTypes = { IC_PROFESSION, IC_RECIPE, IC_TRADESKILL, IC_REAGENT }
            end
            cats[#cats + 1] = {
                _defaultName      = def.name,
                name              = (state and state.rename) or EllesmereUI.L(def.name),
                types             = defTypes,
                isProfAnchor      = isProfAnchor,
                icon              = def.icon,
                isAtlas           = def.isAtlas,
                equipSlots        = def.equipSlots,
                excludeEquipSlots = def.excludeEquipSlots,
                isCatchAll        = def.isCatchAll,
                isSetGear         = def.isSetGear,
                isReagentBag      = def.isReagentBag,
                isPinned          = def.isPinned,
                isRecent          = def.isRecent,
                noGroup           = def.noGroup,
                noMove            = def.noMove,
                groupName         = state and state.groupName,
                groupNameCustom   = state and state.groupNameCustom,
            }
            -- Split mode: append one child category per equipment set right after
            -- the "Item Set Gear" anchor. Runtime-only -- SaveState skips them, so
            -- per-character set names never reach the shared profile; the sidebar
            -- renders them nested one level under the anchor, wherever it sits.
            -- Split mode: one runtime-only child per profession, right after the
            -- "Professions" anchor. Same contract as the equipment-set children --
            -- SaveState skips them and the sidebar nests them one level under.
            if isProfAnchor then
                for _, key in ipairs(PROFESSION_ORDER) do
                    cats[#cats + 1] = {
                        _defaultName  = "Prof:" .. key,
                        name          = ProfessionDisplayName(key),
                        types         = defTypes,
                        icon          = PROFESSION_ICONS[key],
                        isProfession  = true,
                        professionKey = key,
                        noGroup       = true,
                    }
                end
            end

            if def.isSetGear and BP().bagSplitSetGearBySet then
                local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                if setIDs then
                    local sets = {}
                    for _, setID in ipairs(setIDs) do
                        local sname, sicon = C_EquipmentSet.GetEquipmentSetInfo(setID)
                        if sname then sets[#sets + 1] = { id = setID, name = sname, icon = sicon } end
                    end
                    table.sort(sets, function(a, b) return a.name < b.name end)
                    for _, s in ipairs(sets) do
                        cats[#cats + 1] = {
                            _defaultName = "EquipSet:" .. s.id,
                            name         = s.name,
                            types        = def.types,
                            icon         = s.icon or def.icon,
                            isSetGear    = true,   -- keeps gear sorting/type-walk exclusion
                            isEquipSet   = true,
                            equipSetID   = s.id,
                            noGroup      = true,
                        }
                    end
                end
            end
        end
    end

    -- Insert any new custom categories not in the saved order (freshly
    -- created since the last save) before the catch-all.
    if userCats then
        local catchIdx
        for i, c in ipairs(cats) do
            if c.isCatchAll then catchIdx = i; break end
        end
        if not catchIdx then catchIdx = #cats + 1 end
        for _, uc in ipairs(userCats) do
            if not customInserted[uc.key] then
                local ucState = userState[uc.key]
                local ucIcon = uc.icon or 134400
                local ucIsAtlas = type(ucIcon) == "string"
                table.insert(cats, catchIdx, {
                    _defaultName  = uc.key,
                    name          = (ucState and ucState.rename) or uc.name,
                    types         = {},
                    icon          = ucIcon,
                    isAtlas       = ucIsAtlas or nil,
                    isUserCreated = true,
                    groupName     = ucState and ucState.groupName,
                    groupNameCustom = ucState and ucState.groupNameCustom,
                })
                catchIdx = catchIdx + 1
            end
        end
    end

    self._categories = cats

    -- setID -> category index, for split-mode classification
    local setCatIdx = {}
    for i, cat in ipairs(cats) do
        if cat.equipSetID then setCatIdx[cat.equipSetID] = i end
    end
    self._setCatIdxBySetID = setCatIdx

    -- Clean up legacy DB keys
    EllesmereUIDB.bagCategoryDefs = nil
    EllesmereUIDB.categoryItems = nil
    EllesmereUIDB.categoryPositions = nil
    EllesmereUIDB.categoryColumns = nil
end

-- Save user state (renames, grouping) and order back to DB
function CategoryManager:SaveState()
    -- Never write a snapshot built before the SavedVariables merged. This is
    -- the destructive half of the bug: the category list is cached and then
    -- written straight back, so a cache built from the pre-SavedVariables
    -- orphan profile does not merely display defaults, it stamps them over
    -- the user's real categories on the very next save.
    local Lite = EllesmereUI and EllesmereUI.Lite
    if Lite and Lite.IsDBReady and not Lite.IsDBReady() then return end
    local cats = self._categories
    if not cats then return end

    local userState = {}
    local userOrder = {}
    for _, cat in ipairs(cats) do
        if cat.isEquipSet or cat.isProfession then
            -- Runtime-only children of the "Item Set Gear" anchor: never persisted;
            -- InitCategories re-appends them after the anchor each rebuild.
            -- (skip)
        else
            userOrder[#userOrder + 1] = cat._defaultName
            local hasState = false
            local entry = {}
            -- Compare against the LOCALIZED default name. cat.name is the localized
            -- display string (state.rename or L(_defaultName)) while _defaultName is the
            -- English identity key. On a non-English client a plain inequality would see
            -- every untouched default category as "renamed" and freeze its localized name
            -- into the DB, so only treat it as a rename when it differs from the locale default.
            if cat.name ~= EllesmereUI.L(cat._defaultName) then
                entry.rename = cat.name
                hasState = true
            end
            if cat.groupName then
                entry.groupName = cat.groupName
                hasState = true
            end
            if cat.groupNameCustom then
                entry.groupNameCustom = cat.groupNameCustom
                hasState = true
            end
            if hasState then
                userState[cat._defaultName] = entry
            end
        end
    end
    BP().bagCategoryState = userState
    BP().bagCategoryOrder = userOrder

    -- Rebuild user-created categories list from runtime state
    local ucList = {}
    for _, cat in ipairs(cats) do
        if cat.isUserCreated then
            ucList[#ucList + 1] = { key = cat._defaultName, name = cat._defaultName, icon = cat.icon }
        end
    end
    BP().bagUserCategories = #ucList > 0 and ucList or nil
end

-------------------------------------------------------------------------------
--  Accessors
-------------------------------------------------------------------------------
function CategoryManager:GetCategories()
    -- Rebuild not just when empty, but while the cached list was built before
    -- the profile could be trusted. Pull, not push: a callback registered at
    -- file scope would depend on the framework having loaded first, which is
    -- the same ordering assumption that caused this bug -- and unverifiable in
    -- the standalone TOC. By the time anything READS categories the framework
    -- is certainly present.
    if not self._categories or not self._builtReady then
        self:InitCategories()
    end
    return self._categories
end

function CategoryManager:GetCategoryCount()
    local cats = self:GetCategories()
    return #cats
end

-------------------------------------------------------------------------------
--  Classification
-------------------------------------------------------------------------------
-- Equipment set lookup: built once per ClassifyAll pass.
-- Maps "bag*1000+slot" -> setID. A slot in several sets keeps the first
-- (enumeration order), matching split-mode classification's first-set-wins.
local _setGearLookup = {}
-- setID -> set name, for the on-item set name label (no API call at stamp time)
local _setNames = {}

local function BuildSetGearLookup()
    wipe(_setGearLookup)
    wipe(_setNames)
    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
    if not setIDs then return end
    -- Names only feed the on-item label; skip the API calls when it's off
    local wantNames = BP().bagShowSetGearName == true
    for _, setID in ipairs(setIDs) do
        if wantNames then
            _setNames[setID] = C_EquipmentSet.GetEquipmentSetInfo(setID)
        end
        local locs = C_EquipmentSet.GetItemLocations(setID)
        if locs then
            for _, loc in pairs(locs) do
                if loc and loc ~= 0 and loc ~= 1 and loc ~= -1 then
                    local data = EquipmentManager_GetLocationData(loc)
                    if data.isBags then
                        local key = data.bag * 1000 + data.slot
                        if not _setGearLookup[key] then _setGearLookup[key] = setID end
                    end
                end
            end
        end
    end
end

-- Manual overrides: itemID -> classID
local ITEM_TYPE_OVERRIDES = {
    [180653] = IC_MISC,
}

-- Classify a single item. Returns category index (1-based) or nil for empty slots.
-- bag/slot are needed for C_Container.GetContainerItemQuestInfo
function CategoryManager:ClassifyItem(itemLink, itemID, bag, slot)
    if not itemLink then return nil end

    local cats = self:GetCategories()

    -- Reagent bag items always go to the Reagent Bag category. While the
    -- profession split is on that category does not exist and reagents are
    -- classified by profession like anything else, so location no longer wins.
    if bag == 5 and not ReagentBagIsView() then
        for i, cat in ipairs(cats) do
            if cat.isReagentBag then return i end
        end
    end

    -- User item assignments: itemID -> category _defaultName.
    -- Checked before type matching so users can override auto-classification.
    if itemID then
        local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
        local assignedKey = assignments and assignments[itemID]
        if assignedKey then
            for i, cat in ipairs(cats) do
                if cat._defaultName == assignedKey then return i end
            end
        end
    end

    -- Check manual overrides first
    if itemID and ITEM_TYPE_OVERRIDES[itemID] then
        local overrideClassID = ITEM_TYPE_OVERRIDES[itemID]
        for i, cat in ipairs(cats) do
            if cat.types then
                for _, t in ipairs(cat.types) do
                    if t == overrideClassID then return i end
                end
            end
        end
    end

    -- Check quest status via dedicated API (catches "begins a quest" items too)
    if bag and slot then
        local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
        if questInfo and (questInfo.isQuestItem or questInfo.questID) then
            for i, cat in ipairs(cats) do
                if cat.types then
                    for _, t in ipairs(cat.types) do
                        if t == IC_QUEST then return i end
                    end
                end
            end
        end
    end

    -- Get classID + equip slot via GetItemInfoInstant (locale-safe numeric IDs)
    local _, _, _, equipSlot, _, classID = GetItemInfoInstant(itemLink)
    if not classID then
        -- Item data not available; classify as catch-all for now
        for i, cat in ipairs(cats) do
            if cat.isCatchAll then return i end
        end
        return #cats
    end

    -- Equipment set gear check: if item is Armor/Weapon AND in an equipment set,
    -- route to its own set's category (split mode; first set wins for items in
    -- several) or the merged "Item Set Gear" category, before normal type matching
    if bag and slot and (classID == IC_ARMOR or classID == IC_WEAPON) then
        local setID = _setGearLookup[bag * 1000 + slot]
        if setID then
            local byID = self._setCatIdxBySetID
            local idx = byID and byID[setID]
            if idx then return idx end
            for i, cat in ipairs(cats) do
                -- Anchor explicitly: children are isSetGear too, and cats order
                -- can put them first after the anchor is drag-reordered
                if cat.isSetGear and not cat.isEquipSet then return i end
            end
        end
    end

    -- Profession split: route to the matching child before the type walk, or
    -- the anchor would swallow everything via its absorbed classes.
    if ProfessionSplitEnabled() then
        local prof = GetItemProfession(itemLink, itemID)
        if prof then
            local wanted = "Prof:" .. prof
            for i, cat in ipairs(cats) do
                if cat._defaultName == wanted then return i end
            end
        end
    end

    -- Walk categories and check if item classID + equip slot matches
    for i, cat in ipairs(cats) do
        if cat.types and #cat.types > 0 and not cat.isSetGear and not cat.isProfession then
            local typeMatch = false
            for _, t in ipairs(cat.types) do
                if t == classID then typeMatch = true; break end
            end

            -- equipSlots: match items of OTHER types that have these equip slots
            -- (e.g. trinkets are classID Armor but equipSlot "INVTYPE_TRINKET")
            if not typeMatch and cat.equipSlots and equipSlot then
                for _, es in ipairs(cat.equipSlots) do
                    if es == equipSlot then typeMatch = true; break end
                end
            end

            -- excludeEquipSlots: reject items that match the classID but have excluded equip slots
            if typeMatch and cat.excludeEquipSlots and equipSlot then
                for _, es in ipairs(cat.excludeEquipSlots) do
                    if es == equipSlot then typeMatch = false; break end
                end
            end

            if typeMatch then return i end
        end
    end

    -- No match: use catch-all category
    for i, cat in ipairs(cats) do
        if cat.isCatchAll then return i end
    end
    return #cats
end

-- Classify all items and return counts per category + total.
-- Each item in the array gets a .categoryIndex field set.
-- Reusable tables for ClassifyAll (wiped each call, avoids per-refresh allocation)
local _claCounts = {}
local _claDisabledIdxSet = {}

function CategoryManager:ClassifyAll(items)
    BuildSetGearLookup()
    local cats = self:GetCategories()
    -- Rebuild setID -> index every pass: drag-reorder and custom-category
    -- add/remove mutate cats in place without InitCategories, shifting indices.
    -- Refill gated on split mode (no children exist when it's off).
    local setCatIdx = self._setCatIdxBySetID or {}
    wipe(setCatIdx)
    if BP().bagSplitSetGearBySet then
        for i, cat in ipairs(cats) do
            if cat.equipSetID then setCatIdx[cat.equipSetID] = i end
        end
    end
    self._setCatIdxBySetID = setCatIdx
    wipe(_claCounts)
    for i = 1, #cats do _claCounts[i] = 0 end
    local counts = _claCounts
    local total = 0

    -- Disabled categories: items route to catch-all instead (keyed by _defaultName)
    local disabledCats = BP().bagDisabledCategories
    local catchAllIdx
    wipe(_claDisabledIdxSet)
    local disabledIdxSet
    if disabledCats then
        disabledIdxSet = _claDisabledIdxSet
        for i, cat in ipairs(cats) do
            if cat.isCatchAll then catchAllIdx = i end
            if cat._defaultName and disabledCats[cat._defaultName] then
                disabledIdxSet[i] = true
            end
            -- Disabling the "Item Set Gear" anchor disables its set children too,
            -- or split mode would silently bypass the user's choice.
            if cat.isEquipSet and disabledCats["Item Set Gear"] then
                disabledIdxSet[i] = true
            end
            -- Same for the "Professions" anchor and its profession children.
            if cat.isProfession and disabledCats["Professions"] then
                disabledIdxSet[i] = true
            end
        end
    end

    -- On-item label stamping gated on its toggle (recycled tables are wiped on
    -- acquire, so no stale _setName survives while it's off)
    local stampNames = BP().bagShowSetGearName == true
    for _, data in ipairs(items) do
        if data.info and data.itemLink then
            local idx = self:ClassifyItem(data.itemLink, data.info.itemID, data.bag, data.slot)
            if stampNames then
                local sid = _setGearLookup[data.bag * 1000 + data.slot]
                data._setName = sid and _setNames[sid] or nil
            end
            -- Reroute disabled categories to catch-all
            if disabledIdxSet and idx and disabledIdxSet[idx] and catchAllIdx then
                idx = catchAllIdx
            end
            data.categoryIndex = idx
            if idx then
                counts[idx] = (counts[idx] or 0) + 1
            end
            total = total + 1
        end
    end

    return counts, total
end

-------------------------------------------------------------------------------
--  Rename / Reorder (user-facing operations)
-------------------------------------------------------------------------------
function CategoryManager:RenameCategory(index, newName)
    local cats = self:GetCategories()
    if not cats[index] then return false end
    if not newName or newName == "" then return false end
    local oldGroup = cats[index].groupName
    local shouldRegenerate = oldGroup and not self:IsGroupNameCustom(oldGroup)
    cats[index].name = newName
    if shouldRegenerate then
        self:RegenerateGroupName(oldGroup)
    end
    self:SaveState()
    return true
end

-- Move category from fromIndex to toIndex.
-- Callers should NOT adjust for remove/insert -- this function handles it internally.
function CategoryManager:ReorderCategory(fromIndex, toIndex)
    local cats = self:GetCategories()
    if not cats[fromIndex] or fromIndex == toIndex then return end
    -- Equip-set categories move as a block via their anchor; a single one dragged
    -- out would snap back on the next rebuild (SaveState collapses the block).
    if cats[fromIndex].isEquipSet or cats[fromIndex].isProfession then return end
    if toIndex < 1 or toIndex > #cats + 1 then return end
    local entry = table.remove(cats, fromIndex)
    local insertAt = toIndex
    if fromIndex < toIndex then insertAt = toIndex - 1 end
    table.insert(cats, insertAt, entry)
    self:SaveState()
end

-------------------------------------------------------------------------------
--  Grouping
-------------------------------------------------------------------------------
-- Group two or more categories together under a shared name.
function CategoryManager:GroupCategories(indices, groupName)
    local cats = self:GetCategories()
    if not indices or #indices < 2 then return end
    if not groupName then
        local names = {}
        for _, idx in ipairs(indices) do
            if cats[idx] then names[#names + 1] = cats[idx].name end
        end
        if #names == 2 then
            groupName = names[1] .. " & " .. names[2]
        elseif #names >= 3 then
            local last = names[#names]
            names[#names] = nil
            groupName = table.concat(names, ", ") .. ", & " .. last
        else
            groupName = "Group"
        end
    end
    for _, idx in ipairs(indices) do
        if cats[idx] then
            cats[idx].groupName = groupName
            cats[idx].groupNameCustom = nil
        end
    end
    self:SaveState()
end

-- Add a category to an existing group.
function CategoryManager:AddToGroup(catIndex, groupName)
    local cats = self:GetCategories()
    if not cats[catIndex] or not groupName then return end
    cats[catIndex].groupName = groupName
    self:RegenerateGroupName(groupName)
    self:SaveState()
end

-- Remove a category from its group.
function CategoryManager:UngroupCategory(catIndex)
    local cats = self:GetCategories()
    if not cats[catIndex] or not cats[catIndex].groupName then return end
    local oldGroup = cats[catIndex].groupName
    local wasCustom = self:IsGroupNameCustom(oldGroup)
    cats[catIndex].groupName = nil
    local remaining = {}
    for i, cat in ipairs(cats) do
        if cat.groupName == oldGroup then remaining[#remaining + 1] = i end
    end
    if #remaining == 0 then
        -- No members left, nothing to do
    elseif #remaining == 1 then
        -- Only 1 member left, auto-disband
        cats[remaining[1]].groupName = nil
    elseif not wasCustom then
        self:RegenerateGroupName(oldGroup)
    end
    self:SaveState()
end

-- Ungroup all members of a group.
function CategoryManager:DisbandGroup(groupName)
    local cats = self:GetCategories()
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName then cat.groupName = nil end
    end
    self:SaveState()
end

-- Rename a group (updates all members).
function CategoryManager:RenameGroup(oldName, newName)
    if not newName or newName == "" then return end
    local cats = self:GetCategories()
    for _, cat in ipairs(cats) do
        if cat.groupName == oldName then cat.groupName = newName end
    end
    self:SaveState()
end

-- Check if the group name was manually customized by the user.
function CategoryManager:IsGroupNameCustom(groupName)
    local cats = self:GetCategories()
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName and cat.groupNameCustom then return true end
    end
    return false
end

-- Mark a group name as manually customized (set on all members).
function CategoryManager:SetGroupNameCustom(groupName, isCustom)
    local cats = self:GetCategories()
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName then
            cat.groupNameCustom = isCustom or nil
        end
    end
    self:SaveState()
end

-- Auto-regenerate group name from member names.
function CategoryManager:RegenerateGroupName(groupName)
    local cats = self:GetCategories()
    local names = {}
    for _, cat in ipairs(cats) do
        if cat.groupName == groupName then names[#names + 1] = cat.name end
    end
    local newName
    if #names == 2 then
        newName = names[1] .. " & " .. names[2]
    elseif #names >= 3 then
        local last = names[#names]
        newName = table.concat(names, ", ", 1, #names - 1) .. ", & " .. last
    else
        return
    end
    if newName ~= groupName then
        self:RenameGroup(groupName, newName)
        self:SetGroupNameCustom(newName, false)
    end
end

-- Get all unique group names.
function CategoryManager:GetGroupNames()
    local cats = self:GetCategories()
    local seen = {}
    local groups = {}
    for _, cat in ipairs(cats) do
        if cat.groupName and not seen[cat.groupName] then
            seen[cat.groupName] = true
            groups[#groups + 1] = cat.groupName
        end
    end
    return groups
end

-- Get all member indices for a group.
function CategoryManager:GetGroupMembers(groupName)
    local cats = self:GetCategories()
    local members = {}
    for i, cat in ipairs(cats) do
        if cat.groupName == groupName then members[#members + 1] = i end
    end
    return members
end

-- Check if a category is in a group.
function CategoryManager:IsGrouped(catIndex)
    local cats = self:GetCategories()
    return cats[catIndex] and cats[catIndex].groupName or nil
end

-------------------------------------------------------------------------------
--  Custom Category CRUD
-------------------------------------------------------------------------------
-- Create a new user category. Returns the new category index.
function CategoryManager:AddCustomCategory(name)
    if not name or name == "" then return nil end
    if not BP().bagUserCategories then BP().bagUserCategories = {} end

    -- Generate a unique key
    local maxN = 0
    for _, uc in ipairs(BP().bagUserCategories) do
        local n = tonumber(uc.key:match("Custom_(%d+)"))
        if n and n > maxN then maxN = n end
    end
    local key = "Custom_" .. (maxN + 1)

    BP().bagUserCategories[#BP().bagUserCategories + 1] = { key = key, name = name }

    -- Insert into runtime list before catch-all
    local cats = self:GetCategories()
    local catchIdx = #cats + 1
    for i, c in ipairs(cats) do
        if c.isCatchAll then catchIdx = i; break end
    end
    table.insert(cats, catchIdx, {
        _defaultName  = key,
        name          = name,
        types         = {},
        icon          = "Petjournalv2-Icon-PlusButton",
        isAtlas       = true,
        isUserCreated = true,
    })
    self:SaveState()
    return catchIdx
end

-- Remove a user-created category. Unassigns all items in it.
function CategoryManager:RemoveCustomCategory(catIndex)
    local cats = self:GetCategories()
    local cat = cats[catIndex]
    if not cat or not cat.isUserCreated then return false end
    local key = cat._defaultName

    -- Remove item assignments pointing to this category
    local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
    if assignments then
        for itemID, aKey in pairs(assignments) do
            if aKey == key then assignments[itemID] = nil end
        end
    end

    -- Remove from runtime list
    table.remove(cats, catIndex)

    -- Remove from disabled list
    if BP().bagDisabledCategories then
        BP().bagDisabledCategories[key] = nil
    end

    self:SaveState()
    return true
end

-------------------------------------------------------------------------------
--  Item Assignment (user overrides auto-classification)
-------------------------------------------------------------------------------
-- Assign an itemID to a category. Pass nil to unassign.
function CategoryManager:AssignItem(itemID, categoryKey)
    if not itemID then return end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.bagItemAssignments then EllesmereUIDB.bagItemAssignments = {} end
    EllesmereUIDB.bagItemAssignments[itemID] = categoryKey
end

-- Unassign an itemID (returns to auto-classification).
function CategoryManager:UnassignItem(itemID)
    if not itemID then return end
    local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
    if assignments then
        assignments[itemID] = nil
    end
end

-- Check if a category can accept item assignments (drag targets).
-- Excludes Pinned, Recent, Reagent Bag (physical bag, not logical).
function CategoryManager:CanAssignToCategory(catIndex)
    local cats = self:GetCategories()
    local cat = cats[catIndex]
    if not cat then return false end
    if cat.isPinned or cat.isRecent or cat.isReagentBag then return false end
    if cat.isEquipSet then return false end  -- membership comes from the set itself
    if cat.isProfession then return false end -- membership comes from the item type
    return true
end

-- Equipment sets changed (created/renamed/deleted): drop the cached list so the
-- next GetCategories rebuilds split-mode categories from the current sets.
function CategoryManager:OnEquipmentSetsChanged()
    self._categories = nil
end

-------------------------------------------------------------------------------
--  Global accessor
-------------------------------------------------------------------------------
if not _G.EUI_CategoryManager then
    _G.EUI_CategoryManager = CategoryManager
end

CategoryManager:InitCategories()
