if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Options.lua
--  Enhanced Bags Module Options for EllesmereUI
--  Registers the Bags module and builds the options UI
-------------------------------------------------------------------------------

if not EllesmereUI._ModuleNS["EllesmereUIBags"] then return end  -- module disabled: no options page

-- DB creation + login seeding live in EllesmereUIBags_DB.lua (resident; this
-- file is LoadOnDemand and only builds the options page).
local db = EllesmereUI._bagsDB

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    EllesmereUI:RegisterModule("EllesmereUIBags", {
        title = "Bags",
        description = "Enhanced inventory system with sidebar categories, item levels, and quality borders.",
        searchTerms = "bags inventory items slots reagent categories columns sidebar",
        pages = { "Bags", "Bank" },
        buildPage = function(pageName, parent, yOffset)
            if pageName == "Bank" then
                local okB, resB = pcall(function()
                local W = EllesmereUI.Widgets
                local y = yOffset
                local h, _
                -- The Bags module namespace: its bank display resolver
                local BagsNS = EllesmereUI._ModuleNS["EllesmereUIBags"]

                local function RefreshBank()
                    local bank = _G.EUI_BankFrame
                    if bank and bank.RefreshBank then bank:RefreshBank() end
                end

                -- Info label
                do
                    local fontPath = (EllesmereUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"
                    local infoFrame = CreateFrame("Frame", nil, parent)
                    infoFrame:SetSize(parent:GetWidth(), 34)
                    infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 10)
                    infoFrame._isSpacer = true
                    local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
                    line1:SetFont(fontPath, 15, "")
                    line1:SetTextColor(1, 1, 1, 0.75)
                    line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
                    line1:SetJustifyH("CENTER")
                    line1:SetText(EllesmereUI.L("Right-click a tab in the bank sidebar to rename it or set its deposit filters."))
                    local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
                    line2:SetFont(fontPath, 15, "")
                    line2:SetTextColor(1, 1, 1, 0.75)
                    line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
                    line2:SetJustifyH("CENTER")
                    line2:SetText(EllesmereUI.L("Window scale, icon zoom and item level settings are shared with the Bags page."))
                    y = y - 50
                end

                _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

                -- Bank Display: a view over bankListView + bankCompactView (List wins when both are set)
                _, h = W:DualRow(parent, y,
                    { type="dropdown", text="Bank Display",
                      tooltip="How items are arranged in the bank window.",
                      values = { grid="Grid", list="List", compact="Compact" },
                      order  = { "grid", "list", "compact" },
                      getValue=function() return BagsNS.BankDisplayMode(db.profile) end,
                      setValue=function(v)
                          if v == BagsNS.BankDisplayMode(db.profile) then return end
                          db.profile.bankListView = (v == "list")
                          db.profile.bankCompactView = (v == "compact")
                          -- Bags page rows depend on this; rebuild it on next visit
                          EllesmereUI:InvalidateModulePageCache("EllesmereUIBags")
                          -- Hide Empty Slots When Grouped greys in List View
                          EllesmereUI:RefreshPage()
                          EllesmereUI:ShowConfirmPopup({
                              title       = "Reload Required",
                              message     = "Bank display changed. A UI reload is needed to apply.",
                              confirmText = "Reload Now",
                              cancelText  = "Later",
                              reload      = true,
                          })
                      end },
                    EllesmereUI.BlankRowCfg()
                ); y = y - h

                _, h = W:SectionHeader(parent, "GROUPING", y); y = y - h

                -- Nest by Expansion | Group by Category
                _, h = W:DualRow(parent, y,
                    { type="toggle", text="Nest by Expansion",
                      tooltip="In the OneBank and OneWarbank views, split the grid under expansion headers, newest first. Per-tab views are unaffected.",
                      getValue=function() return db.profile.bankNestByExpansion == true end,
                      setValue=function(v)
                          db.profile.bankNestByExpansion = v and true or false
                          RefreshBank()
                          EllesmereUI:RefreshPage()
                      end },
                    { type="toggle", text="Group by Category",
                      tooltip="Split items by category -- Armor, Consumables, Professions and so on -- using the same category list, order and renames as the All Items bag view. Nests inside the expansion headers when Nest by Expansion is also on. Categories that split further do so automatically: gear by equipment slot, Professions and Trade Goods by profession and material type.",
                      getValue=function() return db.profile.bankGroupByCategory == true end,
                      setValue=function(v)
                          db.profile.bankGroupByCategory = v and true or false
                          RefreshBank()
                          EllesmereUI:RefreshPage()
                      end }
                ); y = y - h

                _, h = W:SectionHeader(parent, "SIDEBAR", y); y = y - h

                _, h = W:DualRow(parent, y,
                    { type="toggle", text="Category Sidebar",
                      tooltip="List item categories in the bank sidebar the way the bags sidebar does -- groups such as The Armory with Weapons and Armor under them. Selecting one filters the grid to that category. Categories that split further list their parts as a third level while selected: Professions by profession, Armor by equipment slot, Trade Goods by material. Spans your character bank and warband together, so a category shows everything you own.",
                      getValue=function() return db.profile.bankCategorySidebar == true end,
                      setValue=function(v)
                          db.profile.bankCategorySidebar = v and true or false
                          RefreshBank()
                          EllesmereUI:RefreshPage()
                      end },
                    { type="toggle", text="Hide Bank Tabs in Sidebar",
                      tooltip="Drop the individual Tab 1 / Tab 2 / Warbank Tab entries once the category list is doing the navigating. The consolidated views stay. Note that right-clicking a tab entry is the only way to rename a tab or change its deposit filters, so leave this off if you still need that.",
                      disabled = function() return db.profile.bankCategorySidebar ~= true end,
                      disabledTooltip = "Turn on Category Sidebar first, or the sidebar would have nothing left to navigate with.",
                      getValue=function() return db.profile.bankHideTabsInSidebar == true end,
                      setValue=function(v)
                          db.profile.bankHideTabsInSidebar = v and true or false
                          RefreshBank()
                      end }
                ); y = y - h

                _, h = W:DualRow(parent, y,
                    { type="toggle", text="Hide Empty Slots When Grouped",
                      tooltip="While either grouping toggle is on, drop the trailing block of empty slots so the view only shows items. Turn this off to keep the free slots visible for depositing.",
                      disabled = function()
                          return db.profile.bankListView == true
                              or not (db.profile.bankNestByExpansion or db.profile.bankGroupByCategory)
                      end,
                      disabledTooltip = function()
                          if db.profile.bankListView == true then
                              return "The List View never shows empty slots."
                          end
                          return "Turn on Nest by Expansion or Group by Category first; the flat view has nowhere to move empty slots to."
                      end,
                      rawTooltip = true,
                      getValue=function() return db.profile.bankHideEmptyWhenNested == true end,
                      setValue=function(v)
                          db.profile.bankHideEmptyWhenNested = v and true or false
                          RefreshBank()
                      end },
                    EllesmereUI.BlankRowCfg()
                ); y = y - h

                _, h = W:Spacer(parent, y, 20); y = y - h
                return math.abs(y)
                end) -- end pcall
                if not okB then print("|cffff0000[Bank Options ERROR]|r " .. tostring(resB)) end
                return okB and resB or 0
            end

            if pageName ~= "Bags" then return end

            local ok, result = pcall(function()
            local W = EllesmereUI.Widgets
            local PP = EllesmereUI.PanelPP
            local y = yOffset
            local h, _

            local function ResetAndRefreshBagLayout()
                local bags = _G.EUI_Bags
                if not bags then return end
                bags._asCols = nil
                bags._asMaxGridW = nil
                bags._asMaxH = nil
                if bags.RefreshInventory then bags:RefreshInventory() end
            end

            local BagsNS = EllesmereUI._ModuleNS["EllesmereUIBags"]
            -- Bag Style value: "grid" | "list" | "compact" (any other saved value reads as Grid)
            local function BagDisplayValue()
                local m = db.profile.bagDisplayMode
                return (m == "list" or m == "compact") and m or "grid"
            end
            -- The Display sections are only built while the bags or the bank use
            -- that display: Grid and Compact share one, List has its own.
            local bagList = BagDisplayValue() == "list"
            local anyGrid = not bagList or db.profile.bankListView ~= true
            local anyList = bagList or db.profile.bankListView == true

            ---------------------------------------------------------------------------
            --  LAYOUT
            ---------------------------------------------------------------------------
            _, h = W:SectionHeader(parent, "LAYOUT", y); y = y - h

            -- Bag Style | Default Selected Bag | Window Scale | Frame Strata |
            -- Auto-Size to Fit, two per row
            local layoutSlots = {
                { type="dropdown", text="Bag Style",
                  values = { grid="Grid", list="List", compact="Compact" },
                  order  = { "grid", "list", "compact" },
                  getValue=function() return BagDisplayValue() end,
                  setValue=function(v)
                      if v == BagDisplayValue() then return end
                      db.profile.bagDisplayMode = v
                      EllesmereUI:RefreshPage(true)
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Bag display changed. A UI reload is needed to apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          reload      = true,
                      })
                  end },
                { type="dropdown", text="Default Selected Bag",
                  tooltip="Which view bags open to by default.",
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
                  end },
                { type="slider", text="Window Scale", min=50, max=150, step=5,
                  getValue=function() return math.floor((db.profile.bagScale or 1) * 100 + 0.5) end,
                  setValue=function(v)
                      db.profile.bagScale = v / 100
                      local s = v / 100
                      if _G.EUI_Bags then _G.EUI_Bags:SetScale(s) end
                      if _G.EUI_BagsReagent then _G.EUI_BagsReagent:SetScale(s) end
                      if _G.EUI_BagsWindow then _G.EUI_BagsWindow:SetScale(s) end
                      local bank = _G.EUI_BankFrame
                      if bank and bank:IsVisible() then bank:SetScale(s) end
                  end },
                -- Unset reads the retired Allow Windows Over Bags (BagFrameStrata)
                { type="dropdown", text="Frame Strata",
                  tooltip="Controls the order that overlapping elements display in. Set higher to show above other elements.",
                  values = EllesmereUI.FRAME_STRATA_LABELS,
                  order = EllesmereUI.FRAME_STRATA_ORDER_BASE,
                  getValue=function() return BagsNS.BagFrameStrata() end,
                  setValue=function(v)
                      db.profile.bagFrameStrata = v
                      if _G.EUI_Bags and _G.EUI_Bags.ApplyWindowLayering then
                          _G.EUI_Bags:ApplyWindowLayering()
                      end
                  end },
            }
            -- The List display has no Auto-Size to Fit (its rows take the grip-set width)
            if not bagList then
                layoutSlots[#layoutSlots + 1] = { type="toggle", text="Auto-Size to Fit",
                  -- WoW Forever and the Compact display fit the content, with no normal-size floor
                  tooltip=(EllesmereUI.IS_FOREVER or db.profile.bagDisplayMode == "compact")
                      and "Grow the bag window (more columns + taller, keeping its shape) so all of the active tab's slots are visible without scrolling. It only grows while open -- switching to a bigger tab enlarges it, smaller tabs keep the size -- and resets when you close the bags."
                      or "Grow the bag window (more columns + taller, keeping its shape) so all of the active tab's slots are visible without scrolling. It only grows while open -- switching to a bigger tab enlarges it, smaller tabs keep the size -- and resets when you close the bags. Never smaller than your normal size.",
                  getValue=function() return db.profile.bagAutoSize == true end,
                  setValue=function(v)
                      db.profile.bagAutoSize = v
                      ResetAndRefreshBagLayout()
                  end }
            end
            for i = 1, #layoutSlots, 2 do
                _, h = W:DualRow(parent, y, layoutSlots[i], layoutSlots[i + 1] or EllesmereUI.BlankRowCfg()); y = y - h
            end

            ---------------------------------------------------------------------------
            --  CATEGORIES
            ---------------------------------------------------------------------------
            _, h = W:SectionHeader(parent, "CATEGORIES", y); y = y - h

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

            -- Inline cog for Show Pinned Items
            if not EllesmereUI._prebuilding then
                EllesmereUI.BuildInlineCog(pinRecRow._leftRegion, {
                    chain = false,
                    disabled = function() return db.profile.bagShowPinnedItems == false end,
                    disabledTooltip = "Show Pinned Items",
                    title = "Pinned Items Options",
                    rows = {
                        { type="toggle", label="Show in OneBag/MultiBag",
                          get=function() return db.profile.bagPinnedInOneBag ~= false end,
                          set=function(v)
                              db.profile.bagPinnedInOneBag = v
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end },
                        { type="toggle", label="Hide from Other Categories",
                          tooltip="Show pinned items only in Pinned Items, hiding them from other categories and Recent Items. OneBag/MultiBag keep their normal slots. Unpinning an item returns it to its category.",
                          get=function() return db.profile.bagHidePinnedInCategories == true end,
                          set=function(v)
                              db.profile.bagHidePinnedInCategories = v
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end },
                    },
                })
            end

            -- Inline cog for Show Recent Items: "Show in OneBag"
            if not EllesmereUI._prebuilding then
                EllesmereUI.BuildInlineCog(pinRecRow._rightRegion, {
                    chain = false,
                    disabled = function() return db.profile.bagShowRecentItems == false end,
                    disabledTooltip = "Show Recent Items",
                    title = "Recent Items Options",
                    rows = {
                        { type="toggle", label="Show in OneBag/MultiBag",
                          get=function() return db.profile.bagRecentInOneBag == true end,
                          set=function(v)
                              db.profile.bagRecentInOneBag = v
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end },
                        { type="toggle", label="Show Clear Button",
                          get=function() return db.profile.bagShowRecentClear == true end,
                          set=function(v)
                              db.profile.bagShowRecentClear = v
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end },
                    },
                })
            end

            -- Enabled Categories | Hide Categories with 0 Items
            local catRow
            catRow, h = W:DualRow(parent, y,
                { type="label", text="Enabled Categories" },
                { type="toggle", text="Hide Categories with 0 Items",
                  tooltip="Hide sidebar categories that have no items in them.",
                  getValue=function() return db.profile.bagHideEmptyCategories ~= false end,
                  setValue=function(v)
                      db.profile.bagHideEmptyCategories = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            -- Enabled Categories dropdown (left side)
            if not EllesmereUI._prebuilding then
                -- Function, not a static table: re-evaluated on every menu open, so the
                -- list follows split-mode toggles and set changes without a page rebuild.
                local function BuildCatItems()
                    local catItems = {}
                    if _G.EUI_CategoryManager then
                        local cats = _G.EUI_CategoryManager:GetCategories()
                        for ci, cat in ipairs(cats) do
                            -- isEquipSet excluded: per-character keys, governed by the split toggle instead
                            if not cat.isCatchAll and not cat.isPinned and not cat.isRecent and not cat.isReagentBag and not cat.isSpecialBag and not cat.isEquipSet then
                                catItems[#catItems + 1] = { key = cat._defaultName, label = cat.name }
                            end
                        end
                    end
                    return catItems
                end

                if #BuildCatItems() > 0 then
                    local leftRgn = catRow._leftRegion
                    local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                        BuildCatItems,
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
                            EllesmereUI:RefreshPage()
                        end, nil, 10, true)
                    PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                    leftRgn._control = cbDD
                    leftRgn._lastInline = nil
                    EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
                end
            end

            -- Hide 'Add Category' Tab | Split Set Gear by Set
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Hide 'Add Category' Tab",
                  tooltip="Hides the Add Category button at the bottom of the bag sidebar.",
                  getValue=function() return db.profile.bagHideAddCategory or false end,
                  setValue=function(v)
                      db.profile.bagHideAddCategory = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Split Set Gear by Set",
                  tooltip="Show one sub-category per equipment set (named after the set) nested under Item Set Gear. Gear in several sets goes to the first one.",
                  getValue=function() return db.profile.bagSplitSetGearBySet == true end,
                  setValue=function(v)
                      db.profile.bagSplitSetGearBySet = v
                      -- Re-resolves the selected view by stable key (indices shift)
                      if _G.EUI_Bags and _G.EUI_Bags.InvalidateSetCategories then
                          _G.EUI_Bags.InvalidateSetCategories()
                      elseif _G.EUI_CategoryManager then
                          _G.EUI_CategoryManager:OnEquipmentSetsChanged()
                      end
                      if _G.EUI_Bags and _G.EUI_Bags.UpdateSetEventRegistration then _G.EUI_Bags.UpdateSetEventRegistration() end
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            -- Category Title Size (also on the Fonts page) | Hide Sidebar Icons When Collapsed
            _, h = W:DualRow(parent, y,
                { type="slider", text="Category Title Size", min=8, max=16, step=1,
                  tooltip="Font size for the category titles above your items.",
                  getValue=function() return db.profile.bagCatTitleSize or 11 end,
                  setValue=function(v)
                      db.profile.bagCatTitleSize = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Hide Sidebar Icons When Collapsed",
                  tooltip="Hides a collapsed sidebar; its expand arrow sits by the Inventory title.",
                  getValue=function() return db.profile.bagHideSidebarIconsCollapsed == true end,
                  setValue=function(v)
                      db.profile.bagHideSidebarIconsCollapsed = v and true or false
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            if anyGrid then
                ---------------------------------------------------------------------------
                --  DISPLAY (GRID / COMPACT)
                ---------------------------------------------------------------------------
                _, h = W:SectionHeader(parent, "DISPLAY (GRID / COMPACT)", y); y = y - h

                -- Show Item Level (+ inline cog: Gear Track Rank) | Item Level Text Size
                local ilvlRow
                ilvlRow, h = W:DualRow(parent, y,
                    { type="toggle", text="Show Item Level",
                      tooltip="Display item levels on equipment items in the inventory.",
                      getValue=function() return db.profile.showItemlevelInBags ~= false end,
                      setValue=function(v)
                          db.profile.showItemlevelInBags = v
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          EllesmereUI:RefreshPage()  -- refresh the cog's disabled state
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

                -- Inline cog on Show Item Level (left region): Show Gear Track Rank
                -- (gated by Show Item Level; the rank only renders when ilvl is shown).
                if not EllesmereUI._prebuilding then
                    EllesmereUI.BuildInlineCog(ilvlRow._leftRegion, {
                        chain = false,
                        disabled = function() return db.profile.showItemlevelInBags == false end,
                        disabledTooltip = "Show Item Level",
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
                end

                -- Show BoE / Warbound Text (+ inline cog: Text Size) | Item Count Text Size
                local bindRow
                bindRow, h = W:DualRow(parent, y,
                    { type="toggle", text="Show BoE / Warbound Text",
                      tooltip="Display Binds on Equipped / Warbound until Equipped on equipment items in your bags and bank.",
                      getValue=function() return db.profile.bagDisplayBindType end,
                      setValue=function(v)
                          db.profile.bagDisplayBindType = v
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          local bank = _G.EUI_BankFrame
                          if bank and bank.RefreshBank then bank:RefreshBank() end
                          EllesmereUI:RefreshPage()  -- refresh the cog's disabled state
                      end },
                    { type="slider", text="Item Count Text Size", min=8, max=16, step=1,
                      tooltip="Font size for stack counts, keystone levels, and dungeon abbreviations.",
                      getValue=function() return db.profile.bagCountFontSize or 11 end,
                      setValue=function(v)
                          db.profile.bagCountFontSize = v
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshTextSizes then _G.EUI_Bags:RefreshTextSizes() end
                          local bank = _G.EUI_BankFrame
                          if bank and bank.RefreshTextSizes then bank:RefreshTextSizes() end
                      end }
                ); y = y - h

                -- Inline cog (RESIZE) on Show BoE / Warbound Text: text size
                -- Skipped during the hidden search pre-build: that pass swaps the
                -- widget factory for the frameless absorber, so DualRow returns a
                -- plain table and CreateFrame/SetPoint against its regions throw.
                -- Nothing is lost from the index -- cog popup rows are not search
                -- entries, and the host rows were already registered by DualRow.
                -- Same for every region-chrome block below.
                if not EllesmereUI._prebuilding then
                    EllesmereUI.BuildInlineCog(bindRow._leftRegion, {
                        icon = EllesmereUI.RESIZE_ICON, chain = false,
                        disabled = function() return not db.profile.bagDisplayBindType end,
                        disabledTooltip = "Show BoE / Warbound Text",
                        title = "BoE / Warbound Text Options",
                        rows = {
                            { type="slider", label="Text Size", min=8, max=16, step=1,
                              get=function() return db.profile.bagBindTypeFontSize or 11 end,
                              set=function(v)
                                  db.profile.bagBindTypeFontSize = v
                                  if _G.EUI_Bags and _G.EUI_Bags.RefreshTextSizes then _G.EUI_Bags:RefreshTextSizes() end
                                  local bank = _G.EUI_BankFrame
                                  if bank and bank.RefreshTextSizes then bank:RefreshTextSizes() end
                              end },
                        },
                    })
                end

                -- Show Set Name on Gear (+ inline cog: Text Size) | Nest by Expansion:
                -- bags only, so not built while only the bank uses this display
                if not bagList then
                    local setNameRow
                    setNameRow, h = W:DualRow(parent, y,
                        { type="toggle", text="Show Set Name on Gear",
                          tooltip="Display the equipment set's name at the bottom of bag items that belong to one of your equipment sets.",
                          getValue=function() return db.profile.bagShowSetGearName == true end,
                          setValue=function(v)
                              db.profile.bagShowSetGearName = v
                              if _G.EUI_Bags and _G.EUI_Bags.UpdateSetEventRegistration then _G.EUI_Bags.UpdateSetEventRegistration() end
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                              EllesmereUI:RefreshPage()  -- refresh the cog's disabled state
                          end },
                        { type="toggle", text="Nest by Expansion",
                          tooltip="In the All Items bag view, show each category's items under indented expansion sub-headers (newest expansions first), even when everything in that category is from one expansion.",
                          getValue=function() return db.profile.bagNestByExpansion == true end,
                          setValue=function(v)
                              db.profile.bagNestByExpansion = v and true or false
                              if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          end }
                    ); y = y - h

                    -- Inline cog (RESIZE) on Show Set Name on Gear: text size
                    if not EllesmereUI._prebuilding then
                        EllesmereUI.BuildInlineCog(setNameRow._leftRegion, {
                            icon = EllesmereUI.RESIZE_ICON, chain = false,
                            disabled = function() return db.profile.bagShowSetGearName ~= true end,
                            disabledTooltip = "Show Set Name on Gear",
                            title = "Set Name Text Options",
                            rows = {
                                { type="slider", label="Text Size", min=7, max=14, step=1,
                                  get=function() return db.profile.bagSetNameFontSize or 9 end,
                                  set=function(v)
                                      db.profile.bagSetNameFontSize = v
                                      if _G.EUI_Bags and _G.EUI_Bags.RefreshTextSizes then _G.EUI_Bags:RefreshTextSizes() end
                                  end },
                            },
                        })
                    end
                end
            end

            if anyList then
                ---------------------------------------------------------------------------
                --  DISPLAY (LIST)
                ---------------------------------------------------------------------------
                _, h = W:SectionHeader(parent, "DISPLAY (LIST)", y); y = y - h

                -- Left Gap | Right Gap | Row Height | Text Size | Round Icons |
                -- Section Gold Value | Split by Type | Hide Row Stripes, two per row.
                -- Section Gold Value and Split by Type are bags only, so they drop
                -- out while only the bank uses the List display.
                local listSlots = {
                    { type="slider", text="Left Gap", min=0, max=50, step=1,
                      tooltip="Empty space between this side of the bag and bank lists and their rows.",
                      getValue=function() return db.profile.bagListGapL or 15 end,
                      setValue=function(v)
                          db.profile.bagListGapL = v
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          local bank = _G.EUI_BankFrame
                          if bank and bank.RefreshBank then bank:RefreshBank() end
                      end },
                    { type="slider", text="Right Gap", min=0, max=50, step=1,
                      tooltip="Empty space between this side of the bag and bank lists and their rows.",
                      getValue=function() return db.profile.bagListGapR or 23 end,
                      setValue=function(v)
                          db.profile.bagListGapR = v
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          local bank = _G.EUI_BankFrame
                          if bank and bank.RefreshBank then bank:RefreshBank() end
                      end },
                    { type="slider", text="Row Height", min=16, max=32, step=1,
                      tooltip="Height of each row in the bag and bank lists. Icons shrink to fit short rows.",
                      getValue=function() return db.profile.bagListRowHeight or 24 end,
                      setValue=function(v)
                          db.profile.bagListRowHeight = v
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          local bank = _G.EUI_BankFrame
                          if bank and bank.RefreshBank then bank:RefreshBank() end
                      end },
                    -- Also on the Fonts page (List Text Size)
                    { type="slider", text="Text Size", min=8, max=16, step=1,
                      tooltip="Text size of the bag and bank lists.",
                      getValue=function() return db.profile.bagListFontSize or 11 end,
                      setValue=function(v)
                          db.profile.bagListFontSize = v
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          local bank = _G.EUI_BankFrame
                          if bank and bank.RefreshBank then bank:RefreshBank() end
                      end },
                    { type="toggle", text="Round Icons",
                      tooltip="Show the item icons in the bag and bank lists as circles instead of squares.",
                      getValue=function() return db.profile.bagListRoundIcons == true end,
                      setValue=function(v)
                          db.profile.bagListRoundIcons = v and true or false
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                          local bank = _G.EUI_BankFrame
                          if bank and bank.RefreshBank then bank:RefreshBank() end
                      end },
                }
                local splitSlot
                if bagList then
                    listSlots[#listSlots + 1] = { type="toggle", text="Section Gold Value",
                      tooltip="Show the total vendor sell price of each section's items next to its count in the bag list.",
                      getValue=function() return db.profile.bagListSectionValue == true end,
                      setValue=function(v)
                          db.profile.bagListSectionValue = v and true or false
                          if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      end }
                    splitSlot = #listSlots + 1
                    listSlots[splitSlot] = { type="label", text="Split by Type",
                      tooltip="In the list, group the checked kinds of items under sub-headers by armor type, weapon type, or profession and material. Group Gear by Slot sorts the gear in its categories by slot instead." }
                end
                listSlots[#listSlots + 1] = { type="toggle", text="Hide Row Stripes",
                  tooltip="Remove the shading on every other row in the bag and bank lists.",
                  getValue=function() return db.profile.bagListHideStripes == true end,
                  setValue=function(v)
                      db.profile.bagListHideStripes = v and true or false
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      local bank = _G.EUI_BankFrame
                      if bank and bank.RefreshBank then bank:RefreshBank() end
                  end }
                local splitRow, splitLeft
                for i = 1, #listSlots, 2 do
                    local row
                    row, h = W:DualRow(parent, y, listSlots[i], listSlots[i + 1] or EllesmereUI.BlankRowCfg()); y = y - h
                    if splitSlot == i or splitSlot == i + 1 then splitRow, splitLeft = row, splitSlot == i end
                end

                -- Split by Type checkbox dropdown: a view over the three split toggles
                if splitRow and not EllesmereUI._prebuilding then
                    local splitRgn = splitLeft and splitRow._leftRegion or splitRow._rightRegion
                    local SPLIT_TYPES = {
                        { key = "bagListSplitArmor",       label = "Armor" },
                        { key = "bagListSplitWeapons",     label = "Weapons" },
                        { key = "bagListSplitProfessions", label = "Professions" },
                    }
                    local splitDD, splitDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        splitRgn, 210, splitRgn:GetFrameLevel() + 2, SPLIT_TYPES,
                        function(key) return db.profile[key] == true end,
                        function(key, v)
                            db.profile[key] = v and true or false
                            if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                        end, nil, 10)
                    PP.Point(splitDD, "RIGHT", splitRgn, "RIGHT", -20, 0)
                    splitRgn._control = splitDD
                    splitRgn._lastInline = nil
                    EllesmereUI.RegisterWidgetRefresh(splitDDRefresh)
                end
            end

            ---------------------------------------------------------------------------
            --  EXTRAS (every display)
            ---------------------------------------------------------------------------
            _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

            -- Merge Duplicate Items | Group Gear by Slot (+ inline cog: Compact Slot Groups)
            local gearRow
            gearRow, h = W:DualRow(parent, y,
                { type="toggle", text="Merge Duplicate Items",
                  tooltip="Show copies of the same item in separate bag slots as one icon or row, with their counts added together. Gear is never merged, and OneBag and MultiBag always show every slot. Merging pauses while the mail, trade, auction house, vendor, bank or guild bank window is open.",
                  getValue=function() return db.profile.bagMergeDuplicates ~= false end,
                  setValue=function(v)
                      db.profile.bagMergeDuplicates = v and true or false
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Group Gear by Slot",
                  tooltip="In The Armory and the Weapons / Trinkets, Armor, and Item Set Gear category views, group items under equip-slot sub-headers (Head, Shoulders, Chest, Cosmetic, ...). Does not add sidebar views.",
                  disabled=function()
                      local dc = db.profile.bagDisabledCategories
                      return dc and dc["Armor"] == true
                  end,
                  disabledTooltip="Armor",
                  getValue=function() return db.profile.bagArmoryGroupBySlot == true end,
                  setValue=function(v)
                      db.profile.bagArmoryGroupBySlot = v and true or false
                      ResetAndRefreshBagLayout()
                      EllesmereUI:RefreshPage()
                  end }
            ); y = y - h

            -- Inline cog for Group Gear by Slot: Compact Slot Groups. Grid display
            -- only, so not built for any other Bag Style.
            if not EllesmereUI._prebuilding and BagDisplayValue() == "grid" then
                local function SlotCogState()
                    local dc = db.profile.bagDisabledCategories
                    if dc and dc["Armor"] == true then return true, "Armor" end
                    if db.profile.bagArmoryGroupBySlot ~= true then
                        return true, "Group Gear by Slot"
                    end
                    return false
                end
                local gearRgn = gearRow._rightRegion
                EllesmereUI.BuildInlineCog(gearRgn, {
                    anchorTo = gearRgn._control,
                    disabled = function() return (SlotCogState()) end,
                    disabledTooltip = function() local _, why = SlotCogState(); return why end,
                    title = "Armory Slot Group Options",
                    rows = {
                        { type="toggle", label="Compact Slot Groups",
                          tooltip="Place smaller Armory slot groups beside each other and fill the unused end of each row with empty-slot blocks. Large groups still use full rows.",
                          get=function() return db.profile.bagCompactArmorySlotGroups == true end,
                          set=function(v)
                              db.profile.bagCompactArmorySlotGroups = v and true or false
                              ResetAndRefreshBagLayout()
                          end },
                    },
                })
            end

            -- Junk Item Visuals | Quality Item Border
            local junkRow
            junkRow, h = W:DualRow(parent, y,
                { type="label", text="Junk Item Visuals",
                  tooltip="Choose how junk items look in the bags and bank." },
                { type="toggle", text="Quality Item Border",
                  tooltip="Draw a border in the item's quality color around item icons in the bags and bank. Round list icons have no border.",
                  getValue=function() return db.profile.bagQualityBorder ~= false end,
                  setValue=function(v)
                      db.profile.bagQualityBorder = v and true or false
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      if _G.EUI_BagsReagent and _G.EUI_BagsReagent.RefreshInventory then _G.EUI_BagsReagent:RefreshInventory() end
                      if _G.EUI_BagsWindow and _G.EUI_BagsWindow.RefreshBags then _G.EUI_BagsWindow:RefreshBags() end
                      local bank = _G.EUI_BankFrame
                      if bank and bank.RefreshBank then bank:RefreshBank() end
                  end }
            ); y = y - h

            -- Junk Item Visuals dropdown (left side). The coin badge is drawn
            -- only by the bag window's Grid and Compact displays, so the List
            -- display lists Desaturate alone.
            if not EllesmereUI._prebuilding then
                local JUNK_VISUALS = {
                    { key = "bagDesaturateJunkItems", label = "Desaturate",
                      tooltip = "Display junk items in a greyed-out style." },
                }
                if not bagList then
                    JUNK_VISUALS[2] = { key = "bagShowJunkCoin", label = "Show Coin Icon",
                      tooltip = "Show a coin on the corner of each junk item's icon." }
                end
                local junkRgn = junkRow._leftRegion
                local junkDD, junkDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    junkRgn, 210, junkRgn:GetFrameLevel() + 2, JUNK_VISUALS,
                    function(key) return db.profile[key] == true end,
                    function(key, v)
                        db.profile[key] = v and true or false
                        if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                        local bank = _G.EUI_BankFrame
                        if bank and bank.RefreshBank then bank:RefreshBank() end
                    end, nil, 10)
                PP.Point(junkDD, "RIGHT", junkRgn, "RIGHT", -20, 0)
                junkRgn._control = junkDD
                junkRgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(junkDDRefresh)
            end

            -- Bag Top Bar Icons (+ inline cog: Sort to Bottom) | Gold Tracking and History
            local iconsRow
            iconsRow, h = W:DualRow(parent, y,
                { type="label", text="Bag Top Bar Icons",
                  tooltip="Choose which icons show in the bag window's top bar; the Junk Icon is the Junk Marker." },
                { type="toggle", text="Gold Tracking and History",
                  tooltip="Track and display gold amounts from all your characters on hover.",
                  getValue=function() return db.profile.enableGoldTracking ~= false end,
                  setValue=function(v) db.profile.enableGoldTracking = v end }
            ); y = y - h

            -- Bag Top Bar Icons dropdown (left side), its Sort Options cog to the left
            if not EllesmereUI._prebuilding then
                local TOP_BAR_ICONS = {
                    { key = "bagShowBagsIcon", label = "Bags Icon" },
                    { key = "bagShowJunkIcon", label = "Junk Icon" },
                    { key = "bagShowSortIcon", label = "Sort Icon" },
                }
                local leftRgn = iconsRow._leftRegion
                local iconsDD, iconsDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    leftRgn, 210, leftRgn:GetFrameLevel() + 2, TOP_BAR_ICONS,
                    function(key) return db.profile[key] ~= false end,
                    function(key, v)
                        db.profile[key] = v and true or false
                        local bags = _G.EUI_Bags
                        if bags and bags.SyncHeaderIcons then
                            if key == "bagShowJunkIcon" then
                                -- The Junk category exists only while the Junk Marker is
                                -- on: rebuild the categories and re-resolve the selected
                                -- view by stable key
                                bags.InvalidateSetCategories()
                                bags:SyncHeaderIcons()
                                bags:RefreshInventory()
                                -- An open bank greys (or stops greying) its junk too
                                local bank = _G.EUI_BankFrame
                                if bank then bank:RefreshBank() end
                            else
                                bags:SyncHeaderIcons()
                            end
                        end
                        EllesmereUI:RefreshPage()  -- the Sort Options cog follows Sort Icon
                    end, nil, 10)
                PP.Point(iconsDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                leftRgn._control = iconsDD
                leftRgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(iconsDDRefresh)

                EllesmereUI.BuildInlineCog(leftRgn, {
                    disabled = function() return db.profile.bagShowSortIcon == false end,
                    disabledTooltip = "Sort Icon",
                    title = "Sort Options",
                    rows = {
                        { type="toggle", label="Sort to Bottom",
                          tooltip="Sorting normally packs your items into the first free slots, at the top of the grid. Turn this on to pack them into the last slots instead, so the empty slots end up at the top. The item order itself does not change. This affects the OneBag, MultiBag and bank views -- category views fill their own grid with no gaps, so there is nothing to move. MultiBag and the bank use Blizzard's own sorting, so while this is on it also flips Blizzard's cleanup direction; turning it back off restores the direction you had.",
                          get=function() return db.profile.bagSortToBottom == true end,
                          set=function(v)
                              v = v and true or false
                              local p = db.profile
                              if v == (p.bagSortToBottom == true) then return end
                              -- MultiBag and the bank sort through Blizzard, whose
                              -- fill direction is a real game setting shared with
                              -- their Clean Up button. Stash the player's own value
                              -- on the way in so switching back off restores it
                              -- instead of leaving ours behind.
                              if C_Container.SetSortBagsRightToLeft and C_Container.GetSortBagsRightToLeft then
                                  if v then
                                      p.bagSortBlizzRTLWas = C_Container.GetSortBagsRightToLeft() and true or false
                                      C_Container.SetSortBagsRightToLeft(false)
                                  elseif p.bagSortBlizzRTLWas ~= nil then
                                      C_Container.SetSortBagsRightToLeft(p.bagSortBlizzRTLWas)
                                      p.bagSortBlizzRTLWas = nil
                                  end
                              end
                              p.bagSortToBottom = v
                          end },
                    },
                })
            end

            -- Enabled Currencies | Icon Zoom
            local currRow
            currRow, h = W:DualRow(parent, y,
                { type="label", text="Enabled Currencies" },
                { type="slider", text="Icon Zoom", min=0, max=0.20, step=0.01,
                  tooltip="Crops the border of every item icon in bags and bank. 0 shows the full icon.",
                  getValue=function() return db.profile.bagItemIconZoom or 0.08 end,
                  setValue=function(v)
                      db.profile.bagItemIconZoom = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshIconZoom then _G.EUI_Bags:RefreshIconZoom() end
                      local bank = _G.EUI_BankFrame
                      if bank and bank.RefreshIconZoom then bank:RefreshIconZoom() end
                  end }
            ); y = y - h

            -- Enabled Currencies dropdown (left side)
            if not EllesmereUI._prebuilding then
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
                                            icon = (cInfo and cInfo.iconFileID) or info.iconFileID,
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

                -- Retired lane: tracked ids that are no longer in Blizzard's
                -- currency list (seasonal currencies get delisted at rollover)
                -- would otherwise have NO checkbox anywhere -- stuck tracked
                -- forever, with no way off the bag footer. Built from the
                -- tracked set itself so unchecking always works; names resolve
                -- via GetCurrencyInfo, which still answers for delisted ids.
                -- Never auto-pruned: what renders stays the user's choice.
                do
                    local co = EllesmereUI._BagsCurrencyOrder
                        and EllesmereUI._BagsCurrencyOrder()
                    if co then
                        local listed = {}
                        for _, item in ipairs(currencyItems) do
                            if item.key then listed[item.key] = true end
                        end
                        local retired = {}
                        for cID in pairs(co) do
                            if type(cID) == "number" and not listed[cID] then
                                retired[#retired + 1] = cID
                            end
                        end
                        table.sort(retired)
                        if #retired > 0 then
                            -- Top of the menu: a leftover seasonal currency is
                            -- exactly what this dropdown gets opened to remove,
                            -- so it never hides under the live headers.
                            local block = {
                                { isHeader = true, label = EllesmereUI.L("Retired") },
                            }
                            for _, cID in ipairs(retired) do
                                local cInfo = C_CurrencyInfo.GetCurrencyInfo
                                    and C_CurrencyInfo.GetCurrencyInfo(cID)
                                block[#block + 1] = {
                                    key = cID,
                                    label = (cInfo and cInfo.name) or ("Currency " .. cID),
                                    icon = cInfo and cInfo.iconFileID,
                                }
                            end
                            for i = #block, 1, -1 do
                                table.insert(currencyItems, 1, block[i])
                            end
                        end
                    end
                end

                if #currencyItems > 0 then
                    local leftRgn = currRow._leftRegion
                    local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                        currencyItems,
                        -- Tracked currencies are per character (the module owns
                        -- the accessor and its first-use seeding; see
                        -- CurrencyOrder in EllesmereUIBags.lua). Reading
                        -- db.profile.currencyOrder here would edit the legacy
                        -- shared table that nothing renders any more.
                        function(cID)
                            local co = EllesmereUI._BagsCurrencyOrder
                                and EllesmereUI._BagsCurrencyOrder()
                            return co and co[cID] and true or false
                        end,
                        function(cID, v)
                            local co = EllesmereUI._BagsCurrencyOrder
                                and EllesmereUI._BagsCurrencyOrder()
                            if not co then return end
                            if v then
                                local maxOrder = 0
                                for _, ord in pairs(co) do
                                    if type(ord) == "number" and ord > maxOrder then maxOrder = ord end
                                end
                                co[cID] = maxOrder + 1
                            else
                                co[cID] = nil
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

            -- Stack Splitter
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Stack Splitter",
                  tooltip="Also use the split dialog with Auto Split in OneBag, MultiBag, the reagent bag, the bank and the guild bank, replacing Blizzard's split popup there. All Items and category views always use it.",
                  getValue=function() return db.profile.bagStackSplitter == true end,
                  setValue=function(v) db.profile.bagStackSplitter = v and true or false end },
                { type="toggle", text="Toggle Bags with Character Window",
                  tooltip="The bags automatically open when the character window is opened and close again when the character window is closed.",
                  getValue=function() return db.profile.bagOpenWithCharacter == true end,
                  setValue=function(v)
                      db.profile.bagOpenWithCharacter = v and true or false
                      BagsNS.ToggleBagsWithCharacterFrame()
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
            if _G.EUI_Bags and _G.EUI_Bags.ApplyWindowLayering then
                _G.EUI_Bags:ApplyWindowLayering()
            end
            -- Wipe per-character data from root DB
            if EllesmereUIDB then
                EllesmereUIDB.bagPinnedItems = nil
                EllesmereUIDB.bagItemAssignments = nil
                EllesmereUIDB.bagJunkPrev = nil
                EllesmereUIDB.characterGold = nil
                EllesmereUIDB.warbandGold = nil
                EllesmereUIDB.bagCurrencyByChar = nil
            end
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
