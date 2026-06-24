-------------------------------------------------------------------------------
--  EUI_Bags_Options.lua
--  Enhanced Bags Module Options for EllesmereUI
--  Registers the Bags module and builds the options UI
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Bags profile database
-------------------------------------------------------------------------------
local BAGS_DEFAULTS = {
    profile = {
        bagScale              = 1,
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
        bagSidebarCollapsed   = false,
        bankSidebarCollapsed  = false,
        bagShowPinnedItems    = true,
        bagShowRecentItems    = true,
        bagPinnedInOneBag     = true,
        bagRecentInOneBag     = false,
        bagShowPinRecentTips  = true,
        bagShowSortIcon       = true,
        bagHideRandomize      = false,
        bagDefaultBagType     = "all",   -- "all" | "onebag" | "multibag"
        bagDefaultOneBag      = false,   -- legacy; migrated to bagDefaultBagType
        bagNestByExpansion    = false,
        bagHideOneBagWarning  = false,
        bagHideAddCategory    = false,
        bagMoveNoShift        = false,
        enableGoldTracking    = true,
        detachReagentBag      = false,
        enhancedBags          = true,
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

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    EllesmereUI:RegisterModule("EllesmereUIBags", {
        title = "Bags",
        description = "Enhanced inventory system with sidebar categories, item levels, and quality borders.",
        searchTerms = "bags inventory items slots reagent categories columns sidebar",
        pages = { "Bags" },
        buildPage = function(pageName, parent, yOffset)
            if pageName ~= "Bags" then return end

            local ok, result = pcall(function()
            local W = EllesmereUI.Widgets
            local PP = EllesmereUI.PanelPP
            local y = yOffset
            local h, _

            -- Reposition info label
            do
                local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"
                local infoFrame = CreateFrame("Frame", nil, parent)
                infoFrame:SetSize(parent:GetWidth(), 34)
                infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 10)
                infoFrame._isSpacer = true
                local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
                line1:SetFont(fontPath, 15, "")
                line1:SetTextColor(1, 1, 1, 0.75)
                line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
                line1:SetJustifyH("CENTER")
                line1:SetText(EllesmereUI.L("Reposition this element with Shift+Click and Drag."))
                local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
                line2:SetFont(fontPath, 15, "")
                line2:SetTextColor(1, 1, 1, 0.75)
                line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
                line2:SetJustifyH("CENTER")
                line2:SetText(EllesmereUI.L("Drag categories on bag sidebar to reposition, group or ungroup."))
                y = y - 50
            end

            ---------------------------------------------------------------------------
            --  DISPLAY
            ---------------------------------------------------------------------------
            _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

            -- Window Scale | Hide Categories with 0 Items
            _, h = W:DualRow(parent, y,
                { type="slider", text="Window Scale", min=50, max=150, step=5,
                  tooltip="Scale of the bag and bank windows.",
                  getValue=function() return math.floor((db.profile.bagScale or 1) * 100 + 0.5) end,
                  setValue=function(v)
                      db.profile.bagScale = v / 100
                      local s = v / 100
                      if _G.EUI_Bags then _G.EUI_Bags:SetScale(s) end
                      if _G.EUI_BagsReagent then _G.EUI_BagsReagent:SetScale(s) end
                      if _G.EUI_BagsWindow then _G.EUI_BagsWindow:SetScale(s) end
                      if _G.EUI_Bank and _G.EUI_Bank:IsVisible() then _G.EUI_Bank:SetScale(s) end
                  end },
                { type="toggle", text="Hide Categories with 0 Items",
                  tooltip="Hide sidebar categories that have no items in them.",
                  getValue=function() return db.profile.bagHideEmptyCategories ~= false end,
                  setValue=function(v)
                      db.profile.bagHideEmptyCategories = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            -- Auto-Size to Fit | Default Bag Type
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Auto-Size to Fit",
                  tooltip="Grow the bag window (more columns + taller, keeping its shape) so all of the active tab's slots are visible without scrolling. It only grows while open -- switching to a bigger tab enlarges it, smaller tabs keep the size -- and resets when you close the bags. Never smaller than your normal size.",
                  getValue=function() return db.profile.bagAutoSize == true end,
                  setValue=function(v)
                      db.profile.bagAutoSize = v
                      if _G.EUI_Bags then
                          _G.EUI_Bags._asCols = nil
                          _G.EUI_Bags._asMaxW = nil
                          _G.EUI_Bags._asMaxH = nil
                          if _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      end
                  end },
                { type="dropdown", text="Default Bag Type",
                  tooltip="Which view bags (and the bank) open to by default. The bank has no MultiBag view, so MultiBag opens the bank to OneBank.",
                  values = { all="All Items", onebag="OneBag", multibag="MultiBag" },
                  order  = { "all", "onebag", "multibag" },
                  getValue=function()
                      local t = db.profile.bagDefaultBagType
                      if t == "all" or t == "onebag" or t == "multibag" then return t end
                      return db.profile.bagDefaultOneBag and "onebag" or "all"
                  end,
                  setValue=function(v)
                      db.profile.bagDefaultBagType = v
                      if _G.EUI_Bags and _G.EUI_Bags:IsVisible() and _G.EUI_Bags.RefreshInventory then
                          _G.EUI_Bags:RefreshInventory()
                      end
                      EllesmereUI:RefreshPage()
                  end }
            ); y = y - h

            -- Category Title Size | Show Item Level (+ inline cog: Gear Track Rank)
            local ilvlRow
            ilvlRow, h = W:DualRow(parent, y,
                { type="slider", text="Category Title Size", min=8, max=16, step=1,
                  tooltip="Font size for category titles in the sidebar and content grid.",
                  getValue=function() return db.profile.bagCatTitleSize or 11 end,
                  setValue=function(v)
                      db.profile.bagCatTitleSize = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Show Item Level",
                  tooltip="Display item levels on equipment items in the inventory.",
                  getValue=function() return db.profile.showItemlevelInBags ~= false end,
                  setValue=function(v)
                      db.profile.showItemlevelInBags = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      EllesmereUI:RefreshPage()  -- refresh the cog's disabled state
                  end }
            ); y = y - h

            -- Inline cog on Show Item Level (right region): Show Gear Track Rank
            -- (gated by Show Item Level; the rank only renders when ilvl is shown).
            do
                local _, ilCogShow = EllesmereUI.BuildCogPopup({
                    title = "Item Level Options",
                    rows = {
                        { type="toggle", label="Show Gear Track Rank",
                          get=function() return db.profile.bagShowTrackRank or false end,
                          set=function(v)
                              db.profile.bagShowTrackRank = v
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end },
                    },
                })
                local rightRgn = ilvlRow._rightRegion
                local ilCog = CreateFrame("Button", nil, rightRgn)
                ilCog:SetSize(26, 26)
                ilCog:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
                ilCog:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
                local ilCogTex = ilCog:CreateTexture(nil, "OVERLAY")
                ilCogTex:SetAllPoints()
                ilCogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function ilCogOff() return db.profile.showItemlevelInBags == false end
                ilCog:SetAlpha(ilCogOff() and 0.15 or 0.4)
                ilCog:SetScript("OnEnter", function(self)
                    if ilCogOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Item Level"))
                    else self:SetAlpha(0.7) end
                end)
                ilCog:SetScript("OnLeave", function(self)
                    self:SetAlpha(ilCogOff() and 0.15 or 0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                ilCog:SetScript("OnClick", function(self)
                    if not ilCogOff() then ilCogShow(self) end
                end)
                local ilBlock = CreateFrame("Frame", nil, ilCog)
                ilBlock:SetAllPoints(); ilBlock:SetFrameLevel(ilCog:GetFrameLevel() + 10); ilBlock:EnableMouse(true)
                ilBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(ilCog, EllesmereUI.DisabledTooltip("Show Item Level"))
                end)
                ilBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if ilCogOff() then ilBlock:Show() else ilBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if ilCogOff() then ilCog:SetAlpha(0.15); ilBlock:Show()
                    else ilCog:SetAlpha(0.4); ilBlock:Hide() end
                end)
            end

            -- Enabled Categories | Enabled Currencies
            local catCurrRow
            catCurrRow, h = W:DualRow(parent, y,
                { type="label", text="Enabled Categories" },
                { type="label", text="Enabled Currencies" }
            ); y = y - h

            -- Enabled Categories dropdown (left side)
            do
                local catItems = {}
                if _G.EUI_CategoryManager then
                    local cats = _G.EUI_CategoryManager:GetCategories()
                    for ci, cat in ipairs(cats) do
                        if not cat.isCatchAll and not cat.isPinned and not cat.isRecent and not cat.isReagentBag then
                            catItems[#catItems + 1] = { key = cat._defaultName, label = cat.name }
                        end
                    end
                end

                if #catItems > 0 then
                    local leftRgn = catCurrRow._leftRegion
                    local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                        catItems,
                        function(defName)
                            local dc = db.profile.bagDisabledCategories
                            return not (dc and dc[defName])
                        end,
                        function(defName, v)
                            if not db.profile.bagDisabledCategories then db.profile.bagDisabledCategories = {} end
                            if v then
                                db.profile.bagDisabledCategories[defName] = nil
                            else
                                db.profile.bagDisabledCategories[defName] = true
                            end
                            if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then
                                C_Timer.After(0.1, function()
                                    if _G.EUI_Bags:IsVisible() then _G.EUI_Bags:RefreshInventory() end
                                end)
                            end
                        end, nil, 10, true)
                    PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                    leftRgn._control = cbDD
                    leftRgn._lastInline = nil
                    EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
                end
            end

            -- Enabled Currencies dropdown (right side)
            do
                local currencyItems = {}
                if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
                    -- Expand all collapsed headers so we can see every currency,
                    -- then restore them after scanning.
                    local collapsedHeaders = {}
                    local idx = 1
                    while idx <= C_CurrencyInfo.GetCurrencyListSize() do
                        local info = C_CurrencyInfo.GetCurrencyListInfo(idx)
                        if info and info.isHeader and not info.isHeaderExpanded then
                            collapsedHeaders[#collapsedHeaders + 1] = idx
                            C_CurrencyInfo.ExpandCurrencyList(idx, true)
                        end
                        idx = idx + 1
                    end

                    local listSize = C_CurrencyInfo.GetCurrencyListSize()
                    for i = 1, listSize do
                        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
                        if info then
                            if info.isHeader then
                                currencyItems[#currencyItems + 1] = { isHeader = true, label = info.name }
                            else
                                local link = C_CurrencyInfo.GetCurrencyListLink(i)
                                if link then
                                    local cID = C_CurrencyInfo.GetCurrencyIDFromLink(link)
                                    if cID then
                                        local cInfo = C_CurrencyInfo.GetCurrencyInfo(cID)
                                        local cName = cInfo and cInfo.name or info.name
                                        currencyItems[#currencyItems + 1] = {
                                            key = cID, label = cName,
                                        }
                                    end
                                end
                            end
                        end
                    end

                    -- Restore collapsed headers (iterate in reverse so indices stay valid)
                    for i = #collapsedHeaders, 1, -1 do
                        C_CurrencyInfo.ExpandCurrencyList(collapsedHeaders[i], false)
                    end
                end

                if #currencyItems > 0 then
                    local rightRgn = catCurrRow._rightRegion
                    local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                        currencyItems,
                        function(cID)
                            local co = db.profile.currencyOrder
                            return co and co[cID] and true or false
                        end,
                        function(cID, v)
                            if not db.profile.currencyOrder then db.profile.currencyOrder = {} end
                            if v then
                                local maxOrder = 0
                                for _, ord in pairs(db.profile.currencyOrder) do
                                    if type(ord) == "number" and ord > maxOrder then maxOrder = ord end
                                end
                                db.profile.currencyOrder[cID] = maxOrder + 1
                            else
                                db.profile.currencyOrder[cID] = nil
                            end
                            if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then
                                C_Timer.After(0.1, function()
                                    if _G.EUI_Bags:IsVisible() then _G.EUI_Bags:RefreshInventory() end
                                end)
                            end
                        end, nil, 10, true)
                    PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
                    rightRgn._control = cbDD
                    rightRgn._lastInline = nil
                    EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
                end
            end


            -- Item Count Text Size | Item Level Text Size
            _, h = W:DualRow(parent, y,
                { type="slider", text="Item Count Text Size", min=8, max=16, step=1,
                  tooltip="Font size for stack counts, keystone levels, and dungeon abbreviations.",
                  getValue=function() return db.profile.bagCountFontSize or 11 end,
                  setValue=function(v)
                      db.profile.bagCountFontSize = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshTextSizes then _G.EUI_Bags:RefreshTextSizes() end
                      local bank = _G.EUI_BankFrame
                      if bank and bank.RefreshTextSizes then bank:RefreshTextSizes() end
                  end },
                { type="slider", text="Item Level Text Size", min=8, max=16, step=1,
                  tooltip="Font size for item level numbers on equipment items.",
                  getValue=function() return db.profile.itemlevelFontSize or 12 end,
                  setValue=function(v)
                      db.profile.itemlevelFontSize = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshTextSizes then _G.EUI_Bags:RefreshTextSizes() end
                      local bank = _G.EUI_BankFrame
                      if bank and bank.RefreshTextSizes then bank:RefreshTextSizes() end
                  end }
            ); y = y - h

            ---------------------------------------------------------------------------
            --  EXTRAS
            ---------------------------------------------------------------------------
            _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

            -- Show Sort Icon | Gold Tracking and History
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Show Sort Icon",
                  tooltip="Display the sort button in the bag header.",
                  getValue=function() return db.profile.bagShowSortIcon ~= false end,
                  setValue=function(v)
                      db.profile.bagShowSortIcon = v
                      if _G.EUI_Bags and _G.EUI_Bags._sortBtn then
                          if v then
                              _G.EUI_Bags._sortBtn:Show()
                              if _G.EUI_Bags._bagsBtn then
                                  _G.EUI_Bags._bagsBtn:ClearAllPoints()
                                  _G.EUI_Bags._bagsBtn:SetPoint("RIGHT", _G.EUI_Bags._sortBtn, "LEFT", -6, 0)
                              end
                          else
                              _G.EUI_Bags._sortBtn:Hide()
                              if _G.EUI_Bags._bagsBtn and _G.EUI_Bags._searchBox then
                                  _G.EUI_Bags._bagsBtn:ClearAllPoints()
                                  _G.EUI_Bags._bagsBtn:SetPoint("RIGHT", _G.EUI_Bags._searchBox, "LEFT", -13, 0)
                              end
                          end
                      end
                  end },
                { type="toggle", text="Gold Tracking and History",
                  tooltip="Track and display gold amounts from all your characters on hover.",
                  getValue=function() return db.profile.enableGoldTracking ~= false end,
                  setValue=function(v) db.profile.enableGoldTracking = v end }
            ); y = y - h

            -- Show Pinned Items | Show Recent Items (each with inline cog for OneBag)
            local pinRecRow
            pinRecRow, h = W:DualRow(parent, y,
                { type="toggle", text="Show Pinned Items",
                  tooltip="Show the Pinned Items category in the sidebar and content grid.",
                  getValue=function() return db.profile.bagShowPinnedItems ~= false end,
                  setValue=function(v)
                      db.profile.bagShowPinnedItems = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Show Recent Items",
                  tooltip="Show the Recent Items category in the sidebar and content grid for newly acquired items.",
                  getValue=function() return db.profile.bagShowRecentItems ~= false end,
                  setValue=function(v)
                      db.profile.bagShowRecentItems = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      EllesmereUI:RefreshPage()
                  end }
            ); y = y - h

            -- Inline cog for Show Pinned Items: "Show in OneBag"
            do
                local _, pinCogShow = EllesmereUI.BuildCogPopup({
                    title = "Pinned Items Options",
                    rows = {
                        { type="toggle", label="Show in OneBag/MultiBag",
                          get=function() return db.profile.bagPinnedInOneBag ~= false end,
                          set=function(v)
                              db.profile.bagPinnedInOneBag = v
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end },
                    },
                })
                local leftRgn = pinRecRow._leftRegion
                local pcCog = CreateFrame("Button", nil, leftRgn)
                pcCog:SetSize(26, 26)
                pcCog:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
                pcCog:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                local pcCogTex = pcCog:CreateTexture(nil, "OVERLAY")
                pcCogTex:SetAllPoints()
                pcCogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function pcCogOff() return db.profile.bagShowPinnedItems == false end
                pcCog:SetAlpha(pcCogOff() and 0.15 or 0.4)
                pcCog:SetScript("OnEnter", function(self)
                    if pcCogOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Pinned Items"))
                    else self:SetAlpha(0.7) end
                end)
                pcCog:SetScript("OnLeave", function(self)
                    self:SetAlpha(pcCogOff() and 0.15 or 0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                pcCog:SetScript("OnClick", function(self)
                    if not pcCogOff() then pinCogShow(self) end
                end)
                local pcBlock = CreateFrame("Frame", nil, pcCog)
                pcBlock:SetAllPoints(); pcBlock:SetFrameLevel(pcCog:GetFrameLevel() + 10); pcBlock:EnableMouse(true)
                pcBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(pcCog, EllesmereUI.DisabledTooltip("Show Pinned Items"))
                end)
                pcBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if pcCogOff() then pcBlock:Show() else pcBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if pcCogOff() then pcCog:SetAlpha(0.15); pcBlock:Show()
                    else pcCog:SetAlpha(0.4); pcBlock:Hide() end
                end)
            end

            -- Inline cog for Show Recent Items: "Show in OneBag"
            do
                local _, recentCogShow = EllesmereUI.BuildCogPopup({
                    title = "Recent Items Options",
                    rows = {
                        { type="toggle", label="Show in OneBag/MultiBag",
                          get=function() return db.profile.bagRecentInOneBag == true end,
                          set=function(v)
                              db.profile.bagRecentInOneBag = v
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end },
                    },
                })
                local rightRgn = pinRecRow._rightRegion
                local rcCog = CreateFrame("Button", nil, rightRgn)
                rcCog:SetSize(26, 26)
                rcCog:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
                rcCog:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
                local rcCogTex = rcCog:CreateTexture(nil, "OVERLAY")
                rcCogTex:SetAllPoints()
                rcCogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function rcCogOff() return db.profile.bagShowRecentItems == false end
                rcCog:SetAlpha(rcCogOff() and 0.15 or 0.4)
                rcCog:SetScript("OnEnter", function(self)
                    if rcCogOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Recent Items"))
                    else self:SetAlpha(0.7) end
                end)
                rcCog:SetScript("OnLeave", function(self)
                    self:SetAlpha(rcCogOff() and 0.15 or 0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                rcCog:SetScript("OnClick", function(self)
                    if not rcCogOff() then recentCogShow(self) end
                end)
                local rcBlock = CreateFrame("Frame", nil, rcCog)
                rcBlock:SetAllPoints(); rcBlock:SetFrameLevel(rcCog:GetFrameLevel() + 10); rcBlock:EnableMouse(true)
                rcBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(rcCog, EllesmereUI.DisabledTooltip("Show Recent Items"))
                end)
                rcBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if rcCogOff() then rcBlock:Show() else rcBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if rcCogOff() then rcCog:SetAlpha(0.15); rcBlock:Show()
                    else rcCog:SetAlpha(0.4); rcBlock:Hide() end
                end)
            end

            -- Show Pinned & Recent Tips | Hide 'Add Category' Tab
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Show Pinned & Recent Tips",
                  tooltip="Show helpful tip text on Pinned Items and Recent Items category headers.",
                  getValue=function() return db.profile.bagShowPinRecentTips ~= false end,
                  setValue=function(v)
                      db.profile.bagShowPinRecentTips = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Hide 'Add Category' Tab",
                  tooltip="Hides the Add Category button at the bottom of the bag sidebar.",
                  getValue=function() return db.profile.bagHideAddCategory or false end,
                  setValue=function(v)
                      db.profile.bagHideAddCategory = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            -- Move Bags Without Shift | Nest by Expansion
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Move Bags Without Shift",
                  tooltip="When enabled, left-click dragging the bag window will move it without needing to hold Shift.",
                  getValue=function() return db.profile.bagMoveNoShift or false end,
                  setValue=function(v)
                      db.profile.bagMoveNoShift = v
                  end },
                { type="toggle", text="Nest by Expansion",
                  tooltip="In the All Items bag view, show each category's items under indented expansion sub-headers (newest expansions first), even when everything in that category is from one expansion.",
                  getValue=function() return db.profile.bagNestByExpansion == true end,
                  setValue=function(v)
                      db.profile.bagNestByExpansion = v and true or false
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            -- Hide OneBag Warning | Hide Randomize Button
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Hide OneBag/MultiBag Warning",
                  tooltip="Hide the warning text at the top of the OneBag and MultiBag views.",
                  getValue=function() return db.profile.bagHideOneBagWarning == true end,
                  setValue=function(v)
                      db.profile.bagHideOneBagWarning = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Hide OneBag Randomize Button",
                  tooltip="Hide the randomize (dice) button in the OneBag view.",
                  getValue=function() return db.profile.bagHideRandomize == true end,
                  setValue=function(v)
                      db.profile.bagHideRandomize = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            _, h = W:Spacer(parent, y, 20); y = y - h
            return math.abs(y)
            end) -- end pcall
            if not ok then print("|cffff0000[Bags Options ERROR]|r " .. tostring(result)) end
            return ok and result or 0
        end,
        onReset = function()
            -- Wipe per-profile data and re-apply defaults
            local bdb = EllesmereUI._bagsDB
            local p = bdb and bdb.profile
            if p then
                for k in pairs(p) do p[k] = nil end
                if bdb._profileDefaults then
                    EllesmereUI.Lite.DeepMergeDefaults(p, bdb._profileDefaults)
                end
            end
            -- Wipe per-character data from root DB
            if EllesmereUIDB then
                EllesmereUIDB.bagPinnedItems = nil
                EllesmereUIDB.bagItemAssignments = nil
                EllesmereUIDB.characterGold = nil
                EllesmereUIDB.warbandGold = nil
            end
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
