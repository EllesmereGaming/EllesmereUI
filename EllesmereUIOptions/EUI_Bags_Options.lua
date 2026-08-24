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
        pages = { "Bags" },
        buildPage = function(pageName, parent, yOffset)
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

            -- Window Scale | Icon Zoom (crops the item-icon border; applies to
            -- bag AND bank item icons. Paired with Window Scale as both are
            -- display-appearance sliders; no per-item size control exists.)
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
                      if _G.EUI_BankFrame and _G.EUI_BankFrame:IsVisible() then _G.EUI_BankFrame:SetScale(s) end
                  end },
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

            -- Bag Columns | Bank Columns (grid width of each window; the bank
            -- keeps its own count because its frame is a different shape)
            _, h = W:DualRow(parent, y,
                { type="slider", text="Bag Columns", min=8, max=24, step=1,
                  tooltip="Number of item columns in the bag window. With Auto-Size to Fit on this acts as a minimum: Auto-Size adds columns past it to fit the active tab, and never drops below it.",
                  getValue=function() return db.profile.bagColumns or 12 end,
                  setValue=function(v)
                      db.profile.bagColumns = v
                      ResetAndRefreshBagLayout()
                  end },
                { type="slider", text="Bank Columns", min=8, max=24, step=1,
                  tooltip="Number of item columns in the bank window.",
                  getValue=function() return db.profile.bankColumns or 14 end,
                  setValue=function(v)
                      db.profile.bankColumns = v
                      local bank = _G.EUI_BankFrame
                      if bank and bank.RefreshBank then bank:RefreshBank() end
                  end }
            ); y = y - h

            -- Hide Categories with 0 Items | Auto-Size to Fit
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Hide Categories with 0 Items",
                  tooltip="Hide sidebar categories that have no items in them.",
                  getValue=function() return db.profile.bagHideEmptyCategories ~= false end,
                  setValue=function(v)
                      db.profile.bagHideEmptyCategories = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Auto-Size to Fit",
                  tooltip="Grow the bag window (more columns + taller, keeping its shape) so all of the active tab's slots are visible without scrolling. It only grows while open -- switching to a bigger tab enlarges it, smaller tabs keep the size -- and resets when you close the bags. Never smaller than your normal size.",
                  getValue=function() return db.profile.bagAutoSize == true end,
                  setValue=function(v)
                      db.profile.bagAutoSize = v
                      ResetAndRefreshBagLayout()
                  end }
            ); y = y - h

            -- Merge Duplicate Items | Desaturate Junk Items (display effect; moved
            -- up from EXTRAS so no row sits half-empty)
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Merge Duplicate Items",
                  tooltip="Show copies of the same item that sit in separate bag slots as one icon with their counts added together. Turn this off to keep every slot separate, for example when you deliberately split stacks. Merging is always paused while the mail, trade, auction house, bank or guild bank window is open, since those take one bag slot at a time.",
                  getValue=function() return db.profile.bagMergeDuplicates ~= false end,
                  setValue=function(v)
                      db.profile.bagMergeDuplicates = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end },
                { type="toggle", text="Desaturate Junk Items",
                  tooltip="Display junk items in a greyed-out style.",
                  getValue=function() return db.profile.bagDesaturateJunkItems == true end,
                  setValue=function(v)
                      db.profile.bagDesaturateJunkItems = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                  end }
            ); y = y - h

            -- Split Set Gear by Set | Show Set Name on Gear (+ inline cog: Text Size)
            local setNameRow
            setNameRow, h = W:DualRow(parent, y,
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
                  end },
                { type="toggle", text="Show Set Name on Gear",
                  tooltip="Display the equipment set's name at the bottom of bag items that belong to one of your equipment sets.",
                  getValue=function() return db.profile.bagShowSetGearName == true end,
                  setValue=function(v)
                      db.profile.bagShowSetGearName = v
                      if _G.EUI_Bags and _G.EUI_Bags.UpdateSetEventRegistration then _G.EUI_Bags.UpdateSetEventRegistration() end
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      EllesmereUI:RefreshPage()  -- refresh the cog's disabled state
                  end }
            ); y = y - h

            -- Inline cog (RESIZE) on Show Set Name on Gear: text size
            if not EllesmereUI._prebuilding then
                local _, snCogShow = EllesmereUI.BuildCogPopup({
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
                local rightRgn = setNameRow._rightRegion
                local snCog = CreateFrame("Button", nil, rightRgn)
                snCog:SetSize(26, 26)
                snCog:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
                snCog:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
                local snCogTex = snCog:CreateTexture(nil, "OVERLAY")
                snCogTex:SetAllPoints()
                snCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                local function snCogOff() return db.profile.bagShowSetGearName ~= true end
                snCog:SetAlpha(snCogOff() and 0.15 or 0.4)
                snCog:SetScript("OnEnter", function(self)
                    if snCogOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Set Name on Gear"))
                    else self:SetAlpha(0.7) end
                end)
                snCog:SetScript("OnLeave", function(self)
                    self:SetAlpha(snCogOff() and 0.15 or 0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                snCog:SetScript("OnClick", function(self)
                    if not snCogOff() then snCogShow(self) end
                end)
                local snBlock = CreateFrame("Frame", nil, snCog)
                snBlock:SetAllPoints(); snBlock:SetFrameLevel(snCog:GetFrameLevel() + 10); snBlock:EnableMouse(true)
                snBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(snCog, EllesmereUI.DisabledTooltip("Show Set Name on Gear"))
                end)
                snBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if snCogOff() then snBlock:Show() else snBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if snCogOff() then snCog:SetAlpha(0.15); snBlock:Show()
                    else snCog:SetAlpha(0.4); snBlock:Hide() end
                end)
            end

            -- Default Bag Type | Show BoE / Warbound Text (+ inline cog: Text Size)
            local bindRow
            bindRow, h = W:DualRow(parent, y,
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
                  end },
                { type="toggle", text="Show BoE / Warbound Text",
                  tooltip="Display Binds on Equipped / Warbound until Equipped on equipment items in your bags and bank.",
                  getValue=function() return db.profile.bagDisplayBindType end,
                  setValue=function(v)
                      db.profile.bagDisplayBindType = v
                      if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
                      local bank = _G.EUI_BankFrame
                      if bank and bank.RefreshBank then bank:RefreshBank() end
                      EllesmereUI:RefreshPage()  -- refresh the cog's disabled state
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
                local _, btCogShow = EllesmereUI.BuildCogPopup({
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
                local rightRgn = bindRow._rightRegion
                local btCog = CreateFrame("Button", nil, rightRgn)
                btCog:SetSize(26, 26)
                btCog:SetPoint("RIGHT", rightRgn._control, "LEFT", -8, 0)
                btCog:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
                local btCogTex = btCog:CreateTexture(nil, "OVERLAY")
                btCogTex:SetAllPoints()
                btCogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                local function btCogOff() return not db.profile.bagDisplayBindType end
                btCog:SetAlpha(btCogOff() and 0.15 or 0.4)
                btCog:SetScript("OnEnter", function(self)
                    if btCogOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show BoE / Warbound Text"))
                    else self:SetAlpha(0.7) end
                end)
                btCog:SetScript("OnLeave", function(self)
                    self:SetAlpha(btCogOff() and 0.15 or 0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                btCog:SetScript("OnClick", function(self)
                    if not btCogOff() then btCogShow(self) end
                end)
                local btBlock = CreateFrame("Frame", nil, btCog)
                btBlock:SetAllPoints(); btBlock:SetFrameLevel(btCog:GetFrameLevel() + 10); btBlock:EnableMouse(true)
                btBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(btCog, EllesmereUI.DisabledTooltip("Show BoE / Warbound Text"))
                end)
                btBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if btCogOff() then btBlock:Show() else btBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if btCogOff() then btCog:SetAlpha(0.15); btBlock:Show()
                    else btCog:SetAlpha(0.4); btBlock:Hide() end
                end)
            end

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
            if not EllesmereUI._prebuilding then
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
            if not EllesmereUI._prebuilding then
                -- Function, not a static table: re-evaluated on every menu open, so the
                -- list follows split-mode toggles and set changes without a page rebuild.
                local function BuildCatItems()
                    local catItems = {}
                    if _G.EUI_CategoryManager then
                        local cats = _G.EUI_CategoryManager:GetCategories()
                        for ci, cat in ipairs(cats) do
                            -- isEquipSet excluded: per-character keys, governed by the split toggle instead
                            if not cat.isCatchAll and not cat.isPinned and not cat.isRecent and not cat.isReagentBag and not cat.isEquipSet then
                                catItems[#catItems + 1] = { key = cat._defaultName, label = cat.name }
                            end
                        end
                    end
                    return catItems
                end

                if #BuildCatItems() > 0 then
                    local leftRgn = catCurrRow._leftRegion
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

            -- Enabled Currencies dropdown (right side)
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
                                }
                            end
                            for i = #block, 1, -1 do
                                table.insert(currencyItems, 1, block[i])
                            end
                        end
                    end
                end

                if #currencyItems > 0 then
                    local rightRgn = catCurrRow._rightRegion
                    local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                        rightRgn, 210, rightRgn:GetFrameLevel() + 2,
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

            -- Show Sort Icon (+ inline cog: Sort to Bottom) | Gold Tracking and History
            local sortRow
            sortRow, h = W:DualRow(parent, y,
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
                      EllesmereUI:RefreshPage()  -- refresh the cog's disabled state
                  end },
                { type="toggle", text="Gold Tracking and History",
                  tooltip="Track and display gold amounts from all your characters on hover.",
                  getValue=function() return db.profile.enableGoldTracking ~= false end,
                  setValue=function(v) db.profile.enableGoldTracking = v end }
            ); y = y - h

            -- Inline cog for Show Sort Icon: "Sort to Bottom"
            if not EllesmereUI._prebuilding then
                local _, sortCogShow = EllesmereUI.BuildCogPopup({
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
                local leftRgn = sortRow._leftRegion
                local stCog = CreateFrame("Button", nil, leftRgn)
                stCog:SetSize(26, 26)
                stCog:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
                stCog:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                local stCogTex = stCog:CreateTexture(nil, "OVERLAY")
                stCogTex:SetAllPoints()
                stCogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function stCogOff() return db.profile.bagShowSortIcon == false end
                stCog:SetAlpha(stCogOff() and 0.15 or 0.4)
                stCog:SetScript("OnEnter", function(self)
                    if stCogOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Sort Icon"))
                    else self:SetAlpha(0.7) end
                end)
                stCog:SetScript("OnLeave", function(self)
                    self:SetAlpha(stCogOff() and 0.15 or 0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                stCog:SetScript("OnClick", function(self)
                    if not stCogOff() then sortCogShow(self) end
                end)
                local stBlock = CreateFrame("Frame", nil, stCog)
                stBlock:SetAllPoints(); stBlock:SetFrameLevel(stCog:GetFrameLevel() + 10); stBlock:EnableMouse(true)
                stBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(stCog, EllesmereUI.DisabledTooltip("Show Sort Icon"))
                end)
                stBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if stCogOff() then stBlock:Show() else stBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if stCogOff() then stCog:SetAlpha(0.15); stBlock:Show()
                    else stCog:SetAlpha(0.4); stBlock:Hide() end
                end)
            end

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
            if not EllesmereUI._prebuilding then
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
            if not EllesmereUI._prebuilding then
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

            -- Group Armory by Slot (+ inline cog: Compact Slot Groups)
            local armoryRow
            armoryRow, h = W:DualRow(parent, y,
                { type="toggle", text="Group Armory by Slot",
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
                  end },
                { type="label", text="" }
            ); y = y - h

            -- Inline cog for Group Armory by Slot: compact layout
            if not EllesmereUI._prebuilding then
                local _, armoryCogShow = EllesmereUI.BuildCogPopup({
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
                local leftRgn = armoryRow._leftRegion
                local armoryCog = CreateFrame("Button", nil, leftRgn)
                armoryCog:SetSize(26, 26)
                armoryCog:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
                leftRgn._lastInline = armoryCog
                armoryCog:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                local armoryCogTex = armoryCog:CreateTexture(nil, "OVERLAY")
                armoryCogTex:SetAllPoints()
                armoryCogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function ArmoryCogState()
                    local dc = db.profile.bagDisabledCategories
                    if dc and dc["Armor"] == true then return true, "Armor" end
                    if db.profile.bagArmoryGroupBySlot ~= true then
                        return true, "Group Armory by Slot"
                    end
                    return false
                end
                armoryCog:SetAlpha(ArmoryCogState() and 0.15 or 0.4)
                armoryCog:SetScript("OnEnter", function(self)
                    local off, reason = ArmoryCogState()
                    if off then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(reason))
                    else self:SetAlpha(0.7) end
                end)
                armoryCog:SetScript("OnLeave", function(self)
                    self:SetAlpha(ArmoryCogState() and 0.15 or 0.4)
                    EllesmereUI.HideWidgetTooltip()
                end)
                armoryCog:SetScript("OnClick", function(self)
                    if not ArmoryCogState() then armoryCogShow(self) end
                end)
                local armoryBlock = CreateFrame("Frame", nil, armoryCog)
                armoryBlock:SetAllPoints(); armoryBlock:SetFrameLevel(armoryCog:GetFrameLevel() + 10); armoryBlock:EnableMouse(true)
                armoryBlock:SetScript("OnEnter", function()
                    local _, reason = ArmoryCogState()
                    EllesmereUI.ShowWidgetTooltip(armoryCog, EllesmereUI.DisabledTooltip(reason))
                end)
                armoryBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                if ArmoryCogState() then armoryBlock:Show() else armoryBlock:Hide() end
                EllesmereUI.RegisterWidgetRefresh(function()
                    if ArmoryCogState() then armoryCog:SetAlpha(0.15); armoryBlock:Show()
                    else armoryCog:SetAlpha(0.4); armoryBlock:Hide() end
                end)
            end

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
                EllesmereUIDB.bagCurrencyByChar = nil
            end
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
