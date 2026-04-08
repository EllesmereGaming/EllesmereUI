-------------------------------------------------------------------------------
--  EUI_QoL.lua
--  Runtime logic for all Quality-of-Life features toggled in the QoL Features
--  tab of Global Settings. No UI code here -- only gameplay behaviour.
-------------------------------------------------------------------------------

local qolFrame = CreateFrame("Frame")
qolFrame:RegisterEvent("PLAYER_LOGIN")
qolFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    ---------------------------------------------------------------------------
    --  Health Potion Macro
    ---------------------------------------------------------------------------
    do
        -- Item IDs per category (newest expansion first so best items are picked)
        local ITEM_LISTS = {
            -- 1 = Healthstone
            [1] = { 5512 },
            -- 2 = Health Potions  (Midnight → War Within → older)
            [2] = { 241305, 212943, 211880 },
            -- 3 = Combat Potions  (Midnight → War Within)
            [3] = { 241309, 212265, 212259, 212260 },
        }

        local MACRO_NAME = "EUI_Health"
        local MACRO_ICON = "INV_MISC_QUESTIONMARK"

        -- Find the first item from a list that is in the player's bags
        local function FindItemInBags(itemIDs)
            for _, itemID in ipairs(itemIDs) do
                for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                    for slot = 1, C_Container.GetContainerNumSlots(bag) do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID == itemID then
                            return itemID
                        end
                    end
                end
            end
            return nil
        end

        -- Tracks the last written macro body so we skip EditMacro when nothing changed
        local cachedMacroBody = nil

        local function RefreshHealthMacro()
            if not (EllesmereUIDB and EllesmereUIDB.healthMacroEnabled) then return end
            if InCombatLockdown() then return end

            -- Walk priorities in order and grab the first matching item from bags
            local slots = {
                EllesmereUIDB.healthMacroPrio1 or 1,
                EllesmereUIDB.healthMacroPrio2 or 2,
                EllesmereUIDB.healthMacroPrio3 or 3,
            }

            local tokens = {}
            for i = 1, #slots do
                local itemList = ITEM_LISTS[slots[i]]
                if itemList then
                    local found = FindItemInBags(itemList)
                    if found then
                        tokens[#tokens + 1] = "item:" .. found
                    end
                end
            end

            local newBody
            if #tokens == 0 then
                newBody = "#showtooltip\n/run print(\"EUI: No health consumable in bags.\")"
            elseif #tokens == 1 then
                newBody = "#showtooltip " .. tokens[1] .. "\n/use " .. tokens[1]
            else
                newBody = "#showtooltip " .. tokens[1] .. "\n/castsequence reset=combat " .. table.concat(tokens, ", ")
            end

            if newBody == cachedMacroBody then return end
            cachedMacroBody = newBody

            local idx = GetMacroIndexByName(MACRO_NAME)
            if idx == 0 then
                CreateMacro(MACRO_NAME, MACRO_ICON, newBody, nil)
            else
                EditMacro(idx, MACRO_NAME, MACRO_ICON, newBody)
            end
        end

        EllesmereUI._applyHealthMacro = RefreshHealthMacro

        -- Rebuild whenever bags change
        local macroFrame = CreateFrame("Frame")
        macroFrame:RegisterEvent("BAG_UPDATE")
        macroFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        macroFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_ENTERING_WORLD" then
                self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            end
            if EllesmereUIDB and EllesmereUIDB.healthMacroEnabled then
                C_Timer.After(0.5, RefreshHealthMacro)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Food & Drink Macro
    ---------------------------------------------------------------------------
    do
        -- Only Mage food and actual drinks -- NO buff food (stat food stays for raid)
        local CONSUMABLE_LIST = {
            -- Mage food (restores both health and mana, no stat buff)
            { id = 113509 }, -- Conjured Mana Bun
            { id = 80618  }, -- Conjured Mana Fritter
            { id = 80610  }, -- Conjured Mana Pudding
            { id = 65499  }, -- Conjured Mana Cake
            { id = 43523  }, -- Conjured Mana Strudel
            -- Midnight drinks (no stat buff)
            { id = 242298 }, -- Argentleaf Tea
            { id = 242693 }, -- Kafaccino
            -- TWW drinks
            { id = 260260 }, -- Springrunner Sparkling
            { id = 247695 }, -- Sparkling Mana Supplement
            { id = 247694 }, -- Snifted Void Essence
            { id = 227322 }, -- Sanctified Sasparilla
            { id = 202315 }, -- Frozen Solid Tea
            { id = 197771 }, -- Delicious Dragon Spittle
            -- Generic vendor water (fallback)
            { id = 8766   }, -- Refreshing Spring Water
            { id = 159    }, -- Refreshing Spring Water (old)
        }

        local MACRO_NAME = "EUI_FoodDrink"
        local MACRO_ICON = "INV_MISC_QUESTIONMARK"

        local function FindBest()
            for _, e in ipairs(CONSUMABLE_LIST) do
                if (C_Item.GetItemCount(e.id, false, false) or 0) > 0 then
                    return "item:" .. e.id
                end
            end
            return nil
        end

        local function EnsureMacro()
            if InCombatLockdown() then return false end
            if GetMacroInfo(MACRO_NAME) ~= nil then return true end
            return CreateMacro(MACRO_NAME, MACRO_ICON, "#showtooltip", nil) ~= nil
        end

        local lastItem = nil
        local pendingUpdate = false

        local function UpdateMacro(ignoreCombat)
            if not (EllesmereUIDB and EllesmereUIDB.foodMacroEnabled) then return end
            if not ignoreCombat and UnitAffectingCombat("player") then return end
            if InCombatLockdown() then return end
            if not EnsureMacro() then return end

            local bestItem = FindBest()
            if bestItem == lastItem then return end

            local body = bestItem
                and string.format("#showtooltip\n/castsequence reset=combat %s", bestItem)
                or "#showtooltip"

            EditMacro(GetMacroIndexByName(MACRO_NAME), MACRO_NAME, MACRO_ICON, body)
            lastItem = bestItem
        end

        EllesmereUI._applyFoodMacro = function() UpdateMacro(true) end

        local fdFrame = CreateFrame("Frame")
        fdFrame:RegisterEvent("PLAYER_LOGIN")
        fdFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        fdFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        fdFrame:RegisterEvent("SPELLS_CHANGED")

        fdFrame:SetScript("OnEvent", function(self, event)
            if not (EllesmereUIDB and EllesmereUIDB.foodMacroEnabled) then
                if event ~= "PLAYER_LOGIN" then return end
            end
            if event == "PLAYER_LOGIN" then
                C_Timer.After(1, function() UpdateMacro(true) end)
            elseif event == "PLAYER_REGEN_ENABLED" then
                UpdateMacro(true)
            elseif event == "BAG_UPDATE_DELAYED" then
                if not pendingUpdate then
                    pendingUpdate = true
                    C_Timer.After(0.05, function()
                        pendingUpdate = false
                        UpdateMacro(false)
                    end)
                end
            elseif event == "SPELLS_CHANGED" then
                -- Mage food appears/disappears when conjured
                UpdateMacro(false)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Unwrap Collections (Mounts / Pets / Toys)
    ---------------------------------------------------------------------------
    do
        local busy = false

        -- Dismiss the pending "new item" glow on all mounts that need it,
        -- temporarily narrowing the journal filter so we only iterate collected ones.
        local function AckMountAlerts()
            if not C_MountJournal then return false end
            local pending = C_MountJournal.GetNumMountsNeedingFanfare
                and C_MountJournal.GetNumMountsNeedingFanfare()
            if not pending or pending <= 0 then return false end

            -- Snapshot active filters, force "collected only", sweep, then restore
            local snapshot = {}
            for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
                snapshot[i] = C_MountJournal.GetCollectedFilterSetting(i) and true or false
                C_MountJournal.SetCollectedFilterSetting(i, i == LE_MOUNT_JOURNAL_FILTER_COLLECTED)
            end
            for i = 1, C_MountJournal.GetNumDisplayedMounts() do
                local id = C_MountJournal.GetDisplayedMountID(i)
                if id and C_MountJournal.NeedsFanfare(id) then
                    C_MountJournal.ClearFanfare(id)
                end
            end
            for i = LE_MOUNT_JOURNAL_FILTER_COLLECTED, LE_MOUNT_JOURNAL_FILTER_UNUSABLE do
                C_MountJournal.SetCollectedFilterSetting(i, snapshot[i])
            end
            return true
        end

        local function AckPetAlerts()
            if not C_PetJournal or not C_PetJournal.GetNumPetsNeedingFanfare then return false end
            if (C_PetJournal.GetNumPetsNeedingFanfare() or 0) == 0 then return false end
            local any = false
            for _, id in ipairs(C_PetJournal.GetOwnedPetIDs and C_PetJournal.GetOwnedPetIDs() or {}) do
                if id and C_PetJournal.PetNeedsFanfare and C_PetJournal.PetNeedsFanfare(id) then
                    if C_PetJournal.ClearFanfare then C_PetJournal.ClearFanfare(id) end
                    any = true
                end
            end
            return any
        end

        local function AckToyAlerts()
            if not C_ToyBoxInfo or not C_ToyBoxInfo.ClearFanfare then return false end
            local any = false
            -- Fast path via ToyBox.fanfareToys lookup table
            if ToyBox and ToyBox.fanfareToys then
                for id, needs in pairs(ToyBox.fanfareToys) do
                    if needs and id and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(id) then
                        C_ToyBoxInfo.ClearFanfare(id)
                        any = true
                    end
                end
                if any then return true end
            end
            -- Fallback: full scan
            if C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex then
                for i = 1, C_ToyBox.GetNumToys() do
                    local id = C_ToyBox.GetToyFromIndex(i)
                    if id and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(id) then
                        C_ToyBoxInfo.ClearFanfare(id)
                        any = true
                    end
                end
            end
            return any
        end

        local function DismissCollectionAlerts()
            if not (EllesmereUIDB and EllesmereUIDB.autoUnwrapCollections) then return end
            if busy then return end
            busy = true
            C_Timer.After(0.2, function()
                busy = false
                if not (EllesmereUIDB and EllesmereUIDB.autoUnwrapCollections) then return end
                local changed = AckMountAlerts() or AckPetAlerts() or AckToyAlerts()
                if changed then
                    if CollectionsMicroButton and MainMenuMicroButton_HideAlert then
                        MainMenuMicroButton_HideAlert(CollectionsMicroButton)
                    end
                    if CollectionsMicroButton_SetAlertShown then
                        CollectionsMicroButton_SetAlertShown(false)
                    end
                end
            end)
        end

        EllesmereUI._applyAutoUnwrap = function() end

        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(_, text)
            if not (EllesmereUIDB and EllesmereUIDB.autoUnwrapCollections) then return end
            if text == COLLECTION_UNOPENED_PLURAL or text == COLLECTION_UNOPENED_SINGULAR then
                DismissCollectionAlerts()
            end
        end)

        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("NEW_MOUNT_ADDED")
        f:RegisterEvent("NEW_PET_ADDED")
        f:RegisterEvent("NEW_TOY_ADDED")
        f:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_LOGIN" then self:UnregisterEvent("PLAYER_LOGIN") end
            DismissCollectionAlerts()
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Open Containers
    ---------------------------------------------------------------------------
    do
        local openableCache = {}
        local pendingOpen = false

        local function IsOpenable(bag, slot)
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not info or not info.itemID then return false end
            local cached = openableCache[info.itemID]
            if cached ~= nil then return cached end
            -- Check tooltip for the "Right Click to Open" / ITEM_OPENABLE text
            local tip = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
            if tip and tip.lines then
                for _, line in ipairs(tip.lines) do
                    if line and line.leftText and line.leftText == ITEM_OPENABLE then
                        openableCache[info.itemID] = true
                        return true
                    end
                end
            end
            openableCache[info.itemID] = false
            return false
        end

        local containerFrame = CreateFrame("Frame")
        containerFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        containerFrame:SetScript("OnEvent", function()
            if EllesmereUIDB and EllesmereUIDB.autoOpenContainers == false then return end
            if InCombatLockdown() then return end
            if not pendingOpen then
                pendingOpen = true
                C_Timer.After(0.3, function()
                    -- Collect all openable items first
                    local itemsToOpen = {}
                    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                        for slot = 1, C_Container.GetContainerNumSlots(bag) do
                            if IsOpenable(bag, slot) then
                                table.insert(itemsToOpen, { bag = bag, slot = slot })
                            end
                        end
                    end

                    -- Open them one by one with delay between each
                    local function OpenNext(index)
                        if index > #itemsToOpen then
                            pendingOpen = false
                            return
                        end
                        local item = itemsToOpen[index]
                        if IsOpenable(item.bag, item.slot) then
                            C_Container.UseContainerItem(item.bag, item.slot)
                        end
                        C_Timer.After(0.15, function() OpenNext(index + 1) end)
                    end

                    OpenNext(1)
                end)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Hide Screenshot Status
    ---------------------------------------------------------------------------
    do
        local function ApplyScreenshotStatus()
            local actionStatus = _G.ActionStatus
            if not actionStatus then return end
            if not EllesmereUIDB or EllesmereUIDB.hideScreenshotStatus ~= false then
                actionStatus:UnregisterEvent("SCREENSHOT_STARTED")
                actionStatus:UnregisterEvent("SCREENSHOT_SUCCEEDED")
                actionStatus:UnregisterEvent("SCREENSHOT_FAILED")
                actionStatus:Hide()
            else
                actionStatus:RegisterEvent("SCREENSHOT_STARTED")
                actionStatus:RegisterEvent("SCREENSHOT_SUCCEEDED")
                actionStatus:RegisterEvent("SCREENSHOT_FAILED")
            end
        end

        EllesmereUI._applyScreenshotStatus = ApplyScreenshotStatus

        local ssFrame = CreateFrame("Frame")
        ssFrame:RegisterEvent("PLAYER_LOGIN")
        ssFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_LOGIN")
            ApplyScreenshotStatus()
        end)
    end

    ---------------------------------------------------------------------------
    --  Train All Button
    ---------------------------------------------------------------------------
    do
        local trainBtn = nil
        local hooked = false

        -- How many primary profession slots are still free?
        local function FreeProfessionSlots()
            if not GetProfessions then return 2 end
            local a, b = GetProfessions()
            return 2 - (a and 1 or 0) - (b and 1 or 0)
        end

        -- Can skill at index i be purchased given current funds/slots?
        local function SkillIsAffordable(i, wallet, freeSlots)
            if not GetTrainerServiceInfo or not GetTrainerServiceCost then return false, 0, false end
            local _, kind = GetTrainerServiceInfo(i)
            if kind ~= "available" then return false, 0, false end
            local cost, takesProfSlot = GetTrainerServiceCost(i)
            cost = cost or 0
            if cost > wallet then return false, 0, false end
            if takesProfSlot and freeSlots <= 0 then return false, 0, false end
            return true, cost, takesProfSlot
        end

        -- Return total count and total gold cost of everything trainable right now
        local function TrainableSummary()
            if not GetNumTrainerServices then return 0, 0 end
            local n, gold = 0, 0
            local wallet = GetMoney and GetMoney() or 0
            local slots  = FreeProfessionSlots()
            for i = 1, GetNumTrainerServices() do
                local ok, cost = SkillIsAffordable(i, wallet, slots)
                if ok then n = n + 1; gold = gold + cost end
            end
            return n, gold
        end

        local function RefreshButton()
            if not trainBtn then return end
            if not (EllesmereUIDB and EllesmereUIDB.trainAllButton) then
                trainBtn:Hide(); return
            end
            local n = TrainableSummary()
            trainBtn:SetEnabled(n > 0)
            trainBtn:Show()
        end

        local function SpawnButton()
            if not (EllesmereUIDB and EllesmereUIDB.trainAllButton) then return end
            if not ClassTrainerFrame or not ClassTrainerTrainButton then return end
            if trainBtn then trainBtn:Show(); RefreshButton(); return end

            trainBtn = CreateFrame("Button", "EUI_TrainAllButton", ClassTrainerFrame, "MagicButtonTemplate")
            trainBtn:SetText("Train All")
            trainBtn:SetHeight(ClassTrainerTrainButton:GetHeight() or 22)
            trainBtn:SetWidth(80)
            trainBtn:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -2, 0)

            trainBtn:SetScript("OnClick", function()
                local wallet = GetMoney and GetMoney() or 0
                local slots  = FreeProfessionSlots()
                for i = 1, GetNumTrainerServices() do
                    local ok, cost, takesProfSlot = SkillIsAffordable(i, wallet, slots)
                    if ok then
                        BuyTrainerService(i)
                        wallet = wallet - cost
                        if takesProfSlot then slots = slots - 1 end
                    end
                end
            end)

            trainBtn:SetScript("OnEnter", function(self)
                local n, gold = TrainableSummary()
                if n <= 0 then return end
                local msg = string.format("Learn %d skill%s for %s",
                    n, n == 1 and "" or "s",
                    C_CurrencyInfo.GetCoinTextureString(gold))
                EllesmereUI.ShowWidgetTooltip(self, msg)
            end)
            trainBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            if not hooked then
                hooksecurefunc("ClassTrainerFrame_Update", RefreshButton)
                hooked = true
            end
            RefreshButton()
        end

        local function ApplyTrainAllButton()
            if EllesmereUIDB and EllesmereUIDB.trainAllButton then
                EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", SpawnButton)
                if IsAddOnLoaded and IsAddOnLoaded("Blizzard_TrainerUI") then SpawnButton() end
            elseif trainBtn then
                trainBtn:Hide()
            end
        end

        EllesmereUI._applyTrainAllButton = ApplyTrainAllButton

        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_LOGIN")
            ApplyTrainAllButton()
        end)
    end

    ---------------------------------------------------------------------------
    --  AH Current Expansion Only
    ---------------------------------------------------------------------------
    do
        local ahFrame = CreateFrame("Frame")
        ahFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
        ahFrame:SetScript("OnEvent", function()
            if not (EllesmereUIDB and EllesmereUIDB.ahCurrentExpansion) then return end
            if not AuctionHouseFrame or not AuctionHouseFrame.SearchBar then return end
            C_Timer.After(0, function()
                local fb = AuctionHouseFrame.SearchBar.FilterButton
                if not fb or not fb.filters then return end
                if not (Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.CurrentExpansionOnly) then return end
                fb.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
                AuctionHouseFrame.SearchBar:UpdateClearFiltersButton()
            end)
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Sell Junk + Auto Repair
    ---------------------------------------------------------------------------
    local merchantFrame = CreateFrame("Frame", "EUI_MerchantHandler", UIParent)
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:SetScript("OnEvent", function()
        if not EllesmereUIDB then return end

        -- Auto sell junk
        if EllesmereUIDB.autoSellJunk ~= false then
            local soldCount = 0
            for bag = 0, 4 do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                        C_Container.UseContainerItem(bag, slot)
                        soldCount = soldCount + 1
                    end
                end
            end
            if soldCount > 0 then
                print("|cff0CD29DEllesmereUI:|r Sold " .. soldCount .. " junk item" .. (soldCount > 1 and "s" or "") .. ".")
            end
        end

        -- Auto repair
        if EllesmereUIDB.autoRepair ~= false then
            if CanMerchantRepair() then
                local cost, canRepair = GetRepairAllCost()
                if canRepair and cost > 0 then
                    local useGuild = (EllesmereUIDB.autoRepairGuild ~= false)
                        and IsInGuild()
                        and CanGuildBankRepair()
                        and cost <= GetGuildBankWithdrawMoney()
                    RepairAllItems(useGuild)

                    if useGuild then
                        C_Timer.After(0.5, function()
                            local remainCost, stillNeed = GetRepairAllCost()
                            if stillNeed and remainCost > 0 then
                                RepairAllItems(false)
                            end
                        end)
                    end

                    local gold = floor(cost / 10000)
                    local silver = floor((cost % 10000) / 100)
                    local src = useGuild and " (guild bank)" or ""
                    print("|cff0CD29DEllesmereUI:|r Repaired all items for " .. gold .. "g " .. silver .. "s." .. src)
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    --  Quick Loot
    ---------------------------------------------------------------------------
    do
        local lootFrame = CreateFrame("Frame")
        lootFrame:RegisterEvent("LOOT_READY")
        lootFrame:SetScript("OnEvent", function()
            if not (EllesmereUIDB and EllesmereUIDB.quickLoot) then return end
            if IsShiftKeyDown() then return end
            for i = 1, GetNumLootItems() do
                local index = i
                C_Timer.After(0.05 * index, function()
                    LootSlot(index)
                end)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto-Fill Delete Confirmation
    ---------------------------------------------------------------------------
    do
        for i = 1, 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                hooksecurefunc(popup, "Show", function(self)
                    if not self then return end
                    if self.which ~= "DELETE_GOOD_ITEM" and self.which ~= "DELETE_GOOD_QUEST_ITEM" then return end
                    if not (EllesmereUIDB and EllesmereUIDB.autoFillDelete) then return end
                    local editBox = self.editBox or (self.GetEditBox and self:GetEditBox())
                    if not editBox then return end
                    editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
                    editBox:SetFocus()
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Skip Cinematics
    ---------------------------------------------------------------------------
    do
        local cinHooked = false

        local function SetupCinematicHooks()
            if cinHooked then return end
            if not CinematicFrame or not CinematicFrame.HookScript then return end
            cinHooked = true

            CinematicFrame:HookScript("OnKeyDown", function(_, key)
                if not (EllesmereUIDB and EllesmereUIDB.skipCinematics) then return end
                if key == "ESCAPE" then
                    if CinematicFrame:IsShown() and CinematicFrame.closeDialog then
                        CinematicFrame.closeDialog:Hide()
                    end
                end
            end)

            CinematicFrame:HookScript("OnKeyUp", function(_, key)
                if not (EllesmereUIDB and EllesmereUIDB.skipCinematics) then return end
                if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
                    if CinematicFrame:IsShown() and CinematicFrame.closeDialog then
                        local confirmBtn = _G["CinematicFrameCloseDialogConfirmButton"]
                        if confirmBtn then confirmBtn:Click() end
                    end
                end
            end)

            if MovieFrame and MovieFrame.HookScript then
                MovieFrame:HookScript("OnKeyUp", function(_, key)
                    if not (EllesmereUIDB and EllesmereUIDB.skipCinematics) then return end
                    if key == "SPACE" or key == "ESCAPE" or key == "ENTER" then
                        if MovieFrame:IsShown() and MovieFrame.CloseDialog and MovieFrame.CloseDialog.ConfirmButton then
                            MovieFrame.CloseDialog.ConfirmButton:Click()
                        end
                    end
                end)
            end
        end

        local cinEventFrame = CreateFrame("Frame")
        cinEventFrame:RegisterEvent("CINEMATIC_START")
        cinEventFrame:RegisterEvent("PLAY_MOVIE")
        cinEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        cinEventFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_ENTERING_WORLD" then
                self:UnregisterEvent("PLAYER_ENTERING_WORLD")
                SetupCinematicHooks()
                return
            end
            if not (EllesmereUIDB and EllesmereUIDB.skipCinematicsAuto) then return end
            if event == "CINEMATIC_START" then
                if CinematicFrame and CinematicFrame.isRealCinematic then
                    StopCinematic()
                elseif CanCancelScene and CanCancelScene() then
                    CancelScene()
                end
            elseif event == "PLAY_MOVIE" then
                if MovieFrame then MovieFrame:Hide() end
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Accept Role Check
    ---------------------------------------------------------------------------
    do
        -- Premade Groups: skip if Shift is held and shift-bypass is enabled
        LFGListApplicationDialog:HookScript("OnShow", function(self)
            if not (EllesmereUIDB and EllesmereUIDB.autoAcceptRoleCheck) then return end
            local shiftBypass = EllesmereUIDB.autoAcceptRoleCheckShift and IsShiftKeyDown()
            if self.SignUpButton:IsEnabled() and not shiftBypass then
                self.SignUpButton:Click()
            end
        end)

        -- Classic Dungeon Finder role check
        local roleFrame = CreateFrame("Frame")
        roleFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
        roleFrame:SetScript("OnEvent", function()
            if not (EllesmereUIDB and EllesmereUIDB.autoAcceptRoleCheck) then return end
            if not UnitInParty("player") then return end
            -- Skip if Shift is held and shift-bypass is enabled
            if EllesmereUIDB.autoAcceptRoleCheckShift and IsShiftKeyDown() then return end
            local leader, tank, healer, dps = GetLFGRoles()
            if LFDRoleCheckPopupRoleButtonTank.checkButton:IsEnabled() then
                LFDRoleCheckPopupRoleButtonTank.checkButton:SetChecked(tank)
            end
            if LFDRoleCheckPopupRoleButtonHealer.checkButton:IsEnabled() then
                LFDRoleCheckPopupRoleButtonHealer.checkButton:SetChecked(healer)
            end
            if LFDRoleCheckPopupRoleButtonDPS.checkButton:IsEnabled() then
                LFDRoleCheckPopupRoleButtonDPS.checkButton:SetChecked(dps)
            end
            LFDRoleCheckPopupAcceptButton:Enable()
            LFDRoleCheckPopupAcceptButton:Click()
        end)
    end

    ---------------------------------------------------------------------------
    --  Sort by Mythic+ Rating
    ---------------------------------------------------------------------------
    do
        local function GetApplicantScore(applicantID)
            if not C_LFGList or not C_LFGList.GetApplicantMemberInfo then return nil end
            local _, _, _, _, _, _, _, _, _, _, _, dungeonScore = C_LFGList.GetApplicantMemberInfo(applicantID, 1)
            if dungeonScore == nil then return nil end
            if issecretvalue and issecretvalue(dungeonScore) then return nil end
            if type(dungeonScore) ~= "number" then return nil end
            return dungeonScore
        end

        hooksecurefunc("LFGListUtil_SortApplicants", function(applicants)
            if not (EllesmereUIDB and EllesmereUIDB.sortByMythicScore) then return end
            if not applicants then return end

            local scores = {}
            local originalOrder = {}
            local hasSortable = false

            for i, appID in ipairs(applicants) do
                originalOrder[appID] = i
                local score = GetApplicantScore(appID)
                if score ~= nil then
                    scores[appID] = score
                    hasSortable = true
                end
            end

            if not hasSortable then return end

            table.sort(applicants, function(a, b)
                local sa = scores[a]
                local sb = scores[b]
                if sa and sb and sa ~= sb then return sa > sb end
                if sa and not sb then return true end
                if not sa and sb then return false end
                return (originalOrder[a] or 0) < (originalOrder[b] or 0)
            end)
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Insert Keystone
    ---------------------------------------------------------------------------
    do
        local function InsertKeystone()
            if EllesmereUIDB and EllesmereUIDB.autoInsertKeystone == false then return end
            if C_ChallengeMode.GetSlottedKeystoneInfo() then return end
            for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                local slots = C_Container.GetContainerNumSlots(bag)
                for slot = 1, slots do
                    local link = C_Container.GetContainerItemLink(bag, slot)
                    if link and link:find("|Hkeystone:") then
                        C_Container.PickupContainerItem(bag, slot)
                        if CursorHasItem() then
                            C_ChallengeMode.SlotKeystone()
                        end
                        return
                    end
                end
            end
        end

        local ksFrame = CreateFrame("Frame")
        ksFrame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
        ksFrame:RegisterEvent("ADDON_LOADED")
        ksFrame:SetScript("OnEvent", function(self, event, arg1)
            if event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
                InsertKeystone()
            elseif event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
                self:UnregisterEvent("ADDON_LOADED")
                if ChallengesKeystoneFrame then
                    ChallengesKeystoneFrame:HookScript("OnShow", InsertKeystone)
                end
            end
        end)

        if IsAddOnLoaded and IsAddOnLoaded("Blizzard_ChallengesUI") then
            if ChallengesKeystoneFrame then
                ChallengesKeystoneFrame:HookScript("OnShow", InsertKeystone)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Quick Signup (double-click to sign up)
    ---------------------------------------------------------------------------
    do
        local lastClickTime  = 0
        local lastClickEntry = nil
        local DOUBLE_CLICK_THRESHOLD = 0.4

        hooksecurefunc("LFGListSearchEntry_OnClick", function(entry, button)
            if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
            if button == "RightButton" then return end

            local panel = LFGListFrame and LFGListFrame.SearchPanel
            if not panel then return end
            if not LFGListSearchPanelUtil_CanSelectResult(entry.resultID) then return end
            if not panel.SignUpButton or not panel.SignUpButton:IsEnabled() then return end

            local now = GetTime()
            if lastClickEntry == entry.resultID and (now - lastClickTime) < DOUBLE_CLICK_THRESHOLD then
                if panel.selectedResult ~= entry.resultID then
                    LFGListSearchPanel_SelectResult(panel, entry.resultID)
                end
                LFGListSearchPanel_SignUp(panel)
                lastClickEntry = nil
                lastClickTime  = 0
            else
                lastClickEntry = entry.resultID
                lastClickTime  = now
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Persistent LFG Signup Note
    ---------------------------------------------------------------------------
    do
        local vanilla = LFGListApplicationDialog_Show
        local patched = false

        local function PatchedShow(self, resultID)
            if resultID then
                local info = C_LFGList.GetSearchResultInfo(resultID)
                if info then
                    self.resultID   = resultID
                    self.activityID = info.activityID or (info.activityIDs and info.activityIDs[1])
                end
            end
            LFGListApplicationDialog_UpdateRoles(self)
            StaticPopupSpecial_Show(self)
        end

        local function SyncPatch()
            if EllesmereUIDB and EllesmereUIDB.persistSignupNote then
                if not patched then
                    LFGListApplicationDialog_Show = PatchedShow
                    patched = true
                end
            else
                if patched then
                    LFGListApplicationDialog_Show = vanilla
                    patched = false
                end
            end
        end

        EllesmereUI._applyPersistSignupNote = SyncPatch
        SyncPatch()
    end

    ---------------------------------------------------------------------------
    --  Hide Blizzard Party / Raid Manager frame
    ---------------------------------------------------------------------------
    do
        local hookedMgr = false

        local function ApplyHideBlizzardPartyFrame()
            local shouldHide = EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame
            local mgr = CompactRaidFrameManager or _G["CompactRaidFrameManager"]
            if not mgr then return end

            if shouldHide then
                mgr:Hide()
                if not hookedMgr then
                    hookedMgr = true
                    mgr:HookScript("OnShow", function(self)
                        if EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame then
                            self:Hide()
                        end
                    end)
                end
            else
                mgr:Show()
            end
        end

        EllesmereUI._applyHideBlizzardPartyFrame = ApplyHideBlizzardPartyFrame

        local initFrame = CreateFrame("Frame")
        initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        initFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            ApplyHideBlizzardPartyFrame()
        end)
    end

    ---------------------------------------------------------------------------
    --  Instance Reset Announce
    --  After a successful /reset, posts a message to instance chat so the
    --  whole group knows the instance is ready to re-enter.
    ---------------------------------------------------------------------------
    do
        -- Capture the player name once at login; used in the chat message.
        local playerName = UnitName("player") or "Unknown"

        -- We detect a successful reset by watching CHAT_MSG_SYSTEM for the
        -- Blizzard confirmation string.  The exact string varies by locale so
        -- we match the most common substrings used across all WoW clients.
        local RESET_PATTERNS = {
            "has been reset",           -- enUS / enGB
            "wurde zur",                -- deDE (zurückgesetzt)
            "a été réinitialisé",       -- frFR
            "ha sido reiniciada",       -- esES / esMX
            "è stato resettato",        -- itIT
            "foi reiniciada",           -- ptBR / ptPT
            "сброшен",                  -- ruRU
            "已重置",                    -- zhCN / zhTW
            "초기화되었습니다",           -- koKR
        }

        -- Patterns that indicate a reset FAILED because players are still inside.
        local FAIL_PATTERNS = {
            "players still",            -- enUS / enGB: "There are players still inside..."
            "noch spieler",             -- deDE
            "joueurs sont encore",      -- frFR
            "jugadores todavía",        -- esES / esMX
            "giocatori sono ancora",    -- itIT
            "jogadores ainda",          -- ptBR / ptPT
            "игроки ещё",               -- ruRU
            "还有玩家",                  -- zhCN
            "아직 플레이어",             -- koKR
        }

        local function MatchesAny(msg, patterns)
            if not msg then return false end
            local ok, lower = pcall(string.lower, msg)
            if not ok then return false end
            for _, pat in ipairs(patterns) do
                local ok2, result = pcall(string.find, lower, string.lower(pat), 1, true)
                if ok2 and result then
                    return true
                end
            end
            return false
        end

    ---------------------------------------------------------------------------
    --  Bag Item Level Labels
    --  Draws a small item-level number on every equippable item in the bag.
    --  Setting: EllesmereUIDB.bagIlvlEnabled  (default: true)
    ---------------------------------------------------------------------------
    do
        -- Items worth showing a level on: anything that occupies a gear slot.
        -- Bags, tabards, ammo pouches and cosmetics are intentionally excluded.
        local function IsGearSlot(equipSlot, classID, subclassID)
            if not equipSlot or equipSlot == "" then return false end
            if equipSlot == "INVTYPE_NON_EQUIP_IGNORE" then return false end
            if equipSlot == "INVTYPE_TABARD"           then return false end
            if equipSlot == "INVTYPE_BAG"              then return false end
            if equipSlot == "INVTYPE_QUIVER"           then return false end
            -- classID 4 = Armor, subclassID 5 = Cosmetic
            if classID == 4 and subclassID == 5        then return false end
            return true
        end

        -- Pixel nudge per corner so the number sits just inside the icon edge.
        local CORNER_OFFSET = {
            TOPLEFT     = {  1, -1 },
            TOPRIGHT    = { -1, -1 },
            BOTTOMLEFT  = {  1,  1 },
            BOTTOMRIGHT = { -1,  1 },
        }

        local function GetCorner()
            return (EllesmereUIDB and EllesmereUIDB.bagIlvlAnchor) or "BOTTOMLEFT"
        end

        local function GetSize()
            return (EllesmereUIDB and EllesmereUIDB.bagIlvlFontSize) or 11
        end

        local function GetFace()
            return (EllesmereUI and EllesmereUI.GetFont and EllesmereUI.GetFont())
                or STANDARD_TEXT_FONT
        end

        local function IsActive()
            return not (EllesmereUIDB and EllesmereUIDB.bagIlvlEnabled == false)
        end

        -- Retrieve or create the FontString attached to a button.
        local function GetOrCreateTag(btn)
            if btn._euiIlvlTag then return btn._euiIlvlTag end
            -- Use OVERLAY so the text renders above the item icon texture
            -- but stays below Blizzard's own search-dimming overlay.
            local tag = btn:CreateFontString(nil, "OVERLAY")
            tag:SetFont(GetFace(), GetSize(), "THINOUTLINE")
            tag:SetShadowOffset(1, -1)
            tag:SetShadowColor(0, 0, 0, 0.9)
            btn._euiIlvlTag = tag
            return tag
        end

        local function PaintButton(btn, bag, slot)
            if not btn then return end
            local tag = GetOrCreateTag(btn)

            if not IsActive() then tag:Hide(); return end

            local link = C_Container.GetContainerItemLink(bag, slot)
            if not link then tag:Hide(); return end

            local _, _, quality, _, _, classID, subclassID, _, equipSlot =
                C_Item.GetItemInfo(link)

            if not IsGearSlot(equipSlot, classID, subclassID) then
                tag:Hide(); return
            end

            -- GetCurrentItemLevel via ItemLocation is the only reliable way
            -- to get the actual equipped/upgraded level rather than base level.
            local loc  = ItemLocation:CreateFromBagAndSlot(bag, slot)
            local lvl  = loc and C_Item.GetCurrentItemLevel(loc)
            if not lvl or lvl <= 0 then tag:Hide(); return end

            -- Refresh font in case the user changed size in settings
            tag:SetFont(GetFace(), GetSize(), "THINOUTLINE")

            local corner = GetCorner()
            local off    = CORNER_OFFSET[corner] or CORNER_OFFSET.BOTTOMLEFT
            tag:ClearAllPoints()
            tag:SetPoint(corner, btn, corner, off[1], off[2])

            -- Colour by quality; grey fallback for unknown quality
            if quality and quality >= 0 then
                local r, g, b = C_Item.GetItemQualityColor(quality)
                tag:SetTextColor(r, g, b, 1)
            else
                tag:SetTextColor(0.8, 0.8, 0.8, 1)
            end

            tag:SetText(lvl)
            tag:Show()
        end

        local function ScanOpenBags()
            if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
                for _, btn in ContainerFrameCombinedBags:EnumerateValidItems() do
                    PaintButton(btn, btn:GetBagID(), btn:GetID())
                end
            end
            for _, frame in ipairs((ContainerFrameContainer and
                                    ContainerFrameContainer.ContainerFrames) or {}) do
                if frame:IsShown() then
                    for _, btn in frame:EnumerateValidItems() do
                        PaintButton(btn, btn:GetBagID(), btn:GetID())
                    end
                end
            end
        end

        -- Event-driven refresh
        local watchFrame = CreateFrame("Frame")
        watchFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        watchFrame:RegisterEvent("ITEM_UPGRADE_MASTER_SET_ITEM")
        watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        watchFrame:RegisterEvent("BAG_OPEN")
        watchFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                C_Timer.After(2, ScanOpenBags)
            else
                ScanOpenBags()
            end
        end)

        -- Refresh when any individual bag frame becomes visible
        for _, frame in ipairs((ContainerFrameContainer and
                                ContainerFrameContainer.ContainerFrames) or {}) do
            frame:HookScript("OnShow", function()
                C_Timer.After(0.1, ScanOpenBags)
            end)
        end
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:HookScript("OnShow", function()
                C_Timer.After(0.1, ScanOpenBags)
            end)
        end

        -- Expose a refresh handle for the options panel
        EllesmereUI._refreshBagIlvl = ScanOpenBags
    end

    ---------------------------------------------------------------------------
    --  Character Frame Item Level Labels
    --  Draws a small item-level number on each gear slot in the character
    --  panel. Setting: EllesmereUIDB.charIlvlEnabled  (default: false)
    ---------------------------------------------------------------------------
    do
        -- Inventory slot index → { frame name, side }
        -- side: "RIGHT" = right column, "LEFT" = left column, "TOP" = top (weapons)
        local GEAR_SLOTS = {
            [1]  = { "CharacterHeadSlot",           "RIGHT" },
            [2]  = { "CharacterNeckSlot",            "RIGHT" },
            [3]  = { "CharacterShoulderSlot",        "RIGHT" },
            [15] = { "CharacterBackSlot",            "RIGHT" },
            [5]  = { "CharacterChestSlot",           "RIGHT" },
            [4]  = { "CharacterBodySlot",            "RIGHT" },
            [19] = { "CharacterTabardSlot",          "RIGHT" },
            [9]  = { "CharacterWristSlot",           "RIGHT" },
            [10] = { "CharacterHandsSlot",           "LEFT" },
            [6]  = { "CharacterWaistSlot",           "LEFT" },
            [7]  = { "CharacterLegsSlot",            "LEFT" },
            [8]  = { "CharacterFeetSlot",            "LEFT" },
            [11] = { "CharacterFinger0Slot",         "LEFT" },
            [12] = { "CharacterFinger1Slot",         "LEFT" },
            [13] = { "CharacterTrinket0Slot",        "LEFT" },
            [14] = { "CharacterTrinket1Slot",        "LEFT" },
            [16] = { "CharacterMainHandSlot",        "TOP" },
            [17] = { "CharacterSecondaryHandSlot",   "TOP" },
        }

        -- Slots that can be enchanted in Midnight expansion
        local ENCHANTABLE_SLOTS = {
            [1]  = true,   -- Head
            [3]  = true,   -- Shoulders
            [5]  = true,   -- Chest
            [7]  = true,   -- Legs
            [8]  = true,   -- Feet
            [11] = true,   -- Ring 1
            [12] = true,   -- Ring 2
            [16] = true,   -- Main Hand
        }

        -- Strip enchant prefixes (inspired by BetterCharacterPanel's approach)
        local stripEnchantPrefixes = {
            ["Enchant "] = "",
            ["Weapon %- "] = "",
            ["Shoulders %- "] = "",
            ["Chest %- "] = "",
            ["Ring %- "] = "",
            ["Boots %- "] = "",
            ["Helm %- "] = "",
            ["Head %- "] = "",
            ["Legs %- "] = "",
            ["Feet %- "] = "",
            ["Wrist %- "] = "",
            ["%+"] = "",
        }

        -- Generic enchant replacements that apply to all enchants
        local alwaysReplaceNames = {
            ["Stamina"] = "Stam",
            ["Intellect"] = "Int",
            ["Agility"] = "Agi",
            ["Strength"] = "Str",
            ["Mastery"] = "Mast",
            ["Versatility"] = "Vers",
            ["Critical Strike"] = "Crit",
            ["Haste"] = "Haste",
            ["Avoidance"] = "Avoid",
            ["Leech"] = "Leech",
            ["Speed"] = "Speed",
            [" and "] = " & ",
        }

        -- Default enchant shortnames for Midnight expansion
        local DEFAULT_ENCHANT_SHORTNAMES = {
            ["Minor Speed Increase"] = "Speed",
            ["Homebound Speed"] = "Speed & HS Red.",
            ["Plainsrunner's Breeze"] = "Speed",
            ["Graceful Avoidance"] = "Avoid",
            ["Regenerative Leech"] = "Leech",
            ["Watcher's Loam"] = "Stam",
            ["Rider's Reassurance"] = "Mount Speed",
            ["Accelerated Agility"] = "Speed & Agi",
            ["Reserve of Int"] = "Mana & Int",
            ["Sustained Str"] = "Stam & Str",
            ["Waking Stats"] = "Primary Stat",

            ["Cavalry's March"] = "Mount Speed",
            ["Scout's March"] = "Speed",

            ["Defender's March"] = "Stam",
            ["Stormrider's Agi"] = "Agi & Speed",
            ["Council's Intellect"] = "Int & Mana",
            ["Crystalline Radiance"] = "Primary Stat",
            ["Oathsworn's Strength"] = "Str & Stam",

            ["Chant of Armored Avoidance"] = "Avoid",
            ["Chant of Armored Leech"] = "Leech",
            ["Chant of Armored Speed"] = "Speed",
            ["Chant of Winged Grace"] = "Avoid & FallDmg",
            ["Chant of Leeching Fangs"] = "Leech & Recup",
            ["Chant of Burrowing Rapidity"] = "Speed & HScd",

            ["Cursed Haste"] = "Haste & \124cffcc0000-Vers\124r",
            ["Cursed Crit"] = "Crit & \124cffcc0000-Haste\124r",
            ["Cursed Mastery"] = "Mast & \124cffcc0000-Crit\124r",
            ["Cursed Versatility"] = "Vers & \124cffcc0000-Mast\124r",

            ["Shadowed Belt Clasp"] = "Stamina",

            ["Incandescent Essence"] = "Essence",

            ["Acuity of the Ren'dorei"] = "Proc Prim",
            ["Arcane Mastery"] = "Proc Mast",
            ["Berserker's Rage"] = "Proc Haste",
            ["Flames of the Sin'dorei"] = "Dot->AoE",
            ["Jan'alai's Precision"] = "Proc Crit",
            ["Strength of Halazzi"] = "Bleed",
            ["Worldsoul Aegis"] = "Shield->AoE",
            ["Worldsoul Tenacity"] = "Proc Vers",

            ["Empowered Blessing of Speed"] = "Speed+Vigor",
            ["Blessing of Speed"] = "Speed",
            ["Empowered Rune of Avoidance"] = "Avoid+MS",
            ["Rune of Avoidance"] = "Avoid",
            ["Empowered Hex of Leeching"] = "Leech",
            ["Hex of Leeching"] = "Leech",

            ["Akil'zon's Swiftness"] = "Speed",
            ["Flight of the Eagle"] = "Speed",
            ["Amirdrassil's Grace"] = "Avoid",
            ["Nature's Grace"] = "Avoid",
            ["Thalassian Recovery"] = "Leech",

            ["Mark of Nalorakk"] = "Str & Stam",
            ["Mark of the Magister"] = "Int & Mana",
            ["Mark of the Rootwarden"] = "Agi & Speed",
            ["Mark of the Worldsoul"] = "Primary Stat",

            ["Arcanoweave Spellthread"] = "Int & Mana",
            ["Blood Knight's Armor Kit"] = "Agi/Str & Armor",
            ["Forest Hunter's Armor Kit"] = "Ag/Str & Stam",
            ["Thalassian Scout Armor Kit"] = "Agi/Str",
            ["Bright Linen Spellthread"] = "Int",

            ["Shaladrassil's Roots"] = "Leech & Stam",
            ["Farstrider's Hunt"] = "Speed & Stam",
            ["Lynx's Dexterity"] = "Avoid & Stam",

            ["Eyes of the Eagle"] = "Crit%+",
            ["Nature's Fury"] = "Crit",
            ["Nature's Wrath"] = "Crit",
            ["Silvermoon's Alacrity"] = "Haste%",
            ["Silvermoon's Mending"] = "Leech",
            ["Thalassian Haste"] = "Haste",
            ["Zul'jin's Mastery"] = "Mast",
            ["Amani Mastery"] = "Mast",
            ["Silvermoon's Tenacity"] = "Vers",
            ["Thalassian Versatility"] = "Vers",
        }

        local function GetEnchantShortnames()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.enchantShortnames then
                EllesmereUIDB.enchantShortnames = {}
                -- Initialize with defaults
                for k, v in pairs(DEFAULT_ENCHANT_SHORTNAMES) do
                    EllesmereUIDB.enchantShortnames[k] = v
                end
            end
            return EllesmereUIDB.enchantShortnames
        end

        -- Process enchant text with multiple passes (inspired by BetterCharacterPanel)
        local function ProcessEnchantText(enchantText)
            if not enchantText or enchantText == "" then return enchantText end

            -- Pass 1: Apply exact name replacements from user's shortname table
            local shortnames = GetEnchantShortnames()
            if shortnames[enchantText] then
                return shortnames[enchantText]
            end

            -- Pass 2: Remove prefixes
            for prefix, replacement in pairs(stripEnchantPrefixes) do
                enchantText = enchantText:gsub(prefix, replacement)
            end

            -- Pass 3: Apply generic replacements
            for name, replacement in pairs(alwaysReplaceNames) do
                enchantText = enchantText:gsub(name, replacement)
            end

            return enchantText
        end

        local function CharIlvlEnabled()
            return EllesmereUIDB and EllesmereUIDB.charIlvlEnabled == true
        end

        local function CharIlvlSize()
            return (EllesmereUIDB and EllesmereUIDB.charIlvlFontSize) or 11
        end

        local function CharIlvlFont()
            return (EllesmereUI and EllesmereUI.GetFont and EllesmereUI.GetFont())
                or STANDARD_TEXT_FONT
        end

        local function CharTrackLevelEnabled()
            return EllesmereUIDB and EllesmereUIDB.charTrackLevelEnabled == true
        end

        local function CharTrackLevelSize()
            return (EllesmereUIDB and EllesmereUIDB.charTrackLevelFontSize) or 9
        end

        local function CharEnchantsEnabled()
            return EllesmereUIDB and EllesmereUIDB.charEnchantsEnabled == true
        end

        local function CharEnchantsFontSize()
            return (EllesmereUIDB and EllesmereUIDB.charEnchantsFontSize) or 14
        end

        local function CharEnchantsShorten()
            return EllesmereUIDB and EllesmereUIDB.charEnchantsShorten == true
        end

        local function CharSocketsEnabled()
            return EllesmereUIDB and EllesmereUIDB.charSocketsEnabled == true
        end

        local function CharSocketsScale()
            return (EllesmereUIDB and EllesmereUIDB.charSocketsScale) or 1
        end

        local function CharSocketsOffsetX()
            return (EllesmereUIDB and EllesmereUIDB.charSocketsOffsetX) or 0
        end

        local function CharSocketsOffsetY()
            return (EllesmereUIDB and EllesmereUIDB.charSocketsOffsetY) or 0
        end

        -- Returns or creates the tag FontString on a slot frame.
        -- Right-column slots: label sits to the right of the item.
        -- Left-column slots: label sits to the left of the item.
        -- Top slots (weapons): label sits above the item.
        local function GetOrCreateSlotTag(frame, side, slotIndex)
            if frame._euiCharIlvlTag then return frame._euiCharIlvlTag end
            local tag = frame:CreateFontString(nil, "OVERLAY")
            tag:SetFont(CharIlvlFont(), CharIlvlSize(), "THINOUTLINE")
            tag:SetShadowOffset(1, -1)
            tag:SetShadowColor(0, 0, 0, 0.9)
            -- Anchor based on position
            if side == "LEFT" then
                tag:SetPoint("RIGHT", frame, "LEFT", -5, 10)
            elseif side == "TOP" then
                -- Weapons: MainHand left, OffHand right
                if slotIndex == 16 then  -- MainHand
                    tag:SetPoint("RIGHT", frame, "LEFT", -5, 10)
                else  -- OffHand (17)
                    tag:SetPoint("LEFT", frame, "RIGHT", 5, 10)
                end
            else  -- RIGHT
                tag:SetPoint("LEFT", frame, "RIGHT", 5, 10)
            end
            frame._euiCharIlvlTag = tag
            return tag
        end

        -- Returns or creates the upgrade tag FontString on a slot frame (next to itemlevel).
        local function GetOrCreateUpgradeTag(frame, side)
            if frame._euiCharUpgradeTag then return frame._euiCharUpgradeTag end
            local tag = frame:CreateFontString(nil, "OVERLAY")
            tag:SetFont(CharIlvlFont(), CharTrackLevelSize(), "THINOUTLINE")
            tag:SetShadowOffset(1, -1)
            tag:SetShadowColor(0, 0, 0, 0.9)
            -- Store side for later use in PaintSlot
            frame._euiCharUpgradeSide = side
            frame._euiCharUpgradeTag = tag
            return tag
        end

        -- Returns or creates socket icon frames on a slot frame (on item border).
        -- Create global socket container on first use
        local globalSocketContainer = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        globalSocketContainer:SetFrameStrata("TOOLTIP")
        globalSocketContainer:Hide()  -- Hidden by default

        local function GetOrCreateSocketsIcons(frame, side, slotIndex)
            if frame._euiCharSocketsIcons then return frame._euiCharSocketsIcons end

            frame._euiCharSocketsIcons = {}
            for i = 1, 4 do  -- Max 4 sockets per item
                local icon = globalSocketContainer:CreateTexture(nil, "OVERLAY")
                icon:SetSize(16, 16)
                icon:Hide()  -- Hide initially; only show when CharacterFrame is open
                frame._euiCharSocketsIcons[i] = icon
            end

            -- Store side for later positioning
            frame._euiCharSocketsSide = side
            frame._euiCharSocketsSlotIndex = slotIndex

            return frame._euiCharSocketsIcons
        end

        -- Returns or creates the enchants tag FontString on a slot frame.
        local function GetOrCreateEnchantsTag(frame, side, slotIndex)
            if frame._euiCharEnchantsTag then return frame._euiCharEnchantsTag end
            local tag = frame:CreateFontString(nil, "OVERLAY")
            tag:SetFont(CharIlvlFont(), CharEnchantsFontSize(), "THINOUTLINE")
            tag:SetShadowOffset(1, -1)
            tag:SetShadowColor(0, 0, 0, 0.9)
            -- Position one line below item level, aligned with it
            if side == "LEFT" then
                tag:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, -18)
            elseif side == "TOP" then
                -- Weapons: both MainHand and OffHand show enchant below
                if slotIndex == 16 then  -- MainHand - enchant on left
                    tag:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, -18)
                else  -- OffHand (17) - enchant on right
                    tag:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, -18)
                end
            else  -- RIGHT
                tag:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, -18)
            end
            frame._euiCharEnchantsTag = tag
            return tag
        end

        local function PaintSlot(slotIndex, frameName, side)
            local frame = _G[frameName]
            if not frame then return end

            local tag = GetOrCreateSlotTag(frame, side, slotIndex)
            local upgradeTag = GetOrCreateUpgradeTag(frame, side)
            local enchantsTag = GetOrCreateEnchantsTag(frame, side, slotIndex)
            local socketIcons = GetOrCreateSocketsIcons(frame, side, slotIndex)

            local link = GetInventoryItemLink("player", slotIndex)
            if not link then
                tag:Hide()
                upgradeTag:Hide()
                enchantsTag:Hide()
                if socketIcons then
                    for _, icon in ipairs(socketIcons) do icon:Hide() end
                end
                return
            end

            local loc  = ItemLocation:CreateFromEquipmentSlot(slotIndex)
            local lvl  = loc and C_Item.GetCurrentItemLevel(loc)
            if not lvl or lvl <= 0 then
                tag:Hide()
                upgradeTag:Hide()
                return
            end

            -- Show item level if enabled
            if CharIlvlEnabled() then
                -- Keep font in sync with any setting changes
                tag:SetFont(CharIlvlFont(), CharIlvlSize(), "THINOUTLINE")

                -- Item level is always white
                tag:SetTextColor(1, 1, 1, 1)

                tag:SetText(lvl)
                tag:Show()
            else
                tag:Hide()
            end

            -- Show track level if enabled
            if CharTrackLevelEnabled() then
                upgradeTag:SetFont(CharIlvlFont(), CharTrackLevelSize(), "THINOUTLINE")

                -- Track level uses quality color
                local _, _, quality = C_Item.GetItemInfo(link)
                if quality and quality >= 0 then
                    local r, g, b = C_Item.GetItemQualityColor(quality)
                    upgradeTag:SetTextColor(r, g, b, 1)
                else
                    upgradeTag:SetTextColor(1, 1, 1, 1)
                end

                -- Position upgrade tag with dynamic offset based on itemlevel font size
                local side = frame._euiCharUpgradeSide
                local itemLevelFontSize = CharIlvlSize()
                local dynamicOffset = itemLevelFontSize + 15  -- Font size + 15px base offset

                if side == "LEFT" then
                    upgradeTag:SetPoint("RIGHT", frame, "LEFT", -dynamicOffset, 10)
                elseif side == "TOP" then
                    upgradeTag:SetPoint("BOTTOM", frame, "TOP", 0, -6)
                else  -- RIGHT
                    upgradeTag:SetPoint("LEFT", frame, "RIGHT", dynamicOffset, 10)
                end

                local trackText = ""
                local trackColor = { r = 1, g = 1, b = 1 }  -- default white

                -- Try to extract from tooltip
                if frame and link then
                    -- Create a hidden tooltip to scan
                    local tooltip = CreateFrame("GameTooltip", "EUICharIlvlTooltip", nil, "GameTooltipTemplate")
                    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                    tooltip:SetInventoryItem("player", slotIndex)

                    -- Scan all lines in one pass
                    for i = 1, tooltip:NumLines() do
                        local textLeft = _G["EUICharIlvlTooltipTextLeft" .. i]:GetText() or ""

                        -- Look for "Upgrade Level: XYZ X/X" pattern
                        if textLeft:match("Upgrade Level:") then
                            -- Extract the track info after "Upgrade Level: "
                            local trackInfo = textLeft:gsub("Upgrade Level:%s*", "")

                            -- Parse the track type and numbers
                            local trk, nums = trackInfo:match("^(%w+)%s+(.+)$")
                            if trk and nums then
                                local shortName = ""

                                -- Map full names to short names and set colors
                                if trk == "Champion" then
                                    shortName = "Champion"
                                    trackColor = { r = 0.6, g = 0, b = 1 }  -- purple
                                elseif trk:match("Myth") then
                                    shortName = "Myth"
                                    trackColor = { r = 1, g = 0.6, b = 0 }  -- orange
                                elseif trk == "Hero" then
                                    shortName = "Hero"
                                    trackColor = { r = 1, g = 0.3, b = 0.8 }  -- pink
                                elseif trk == "Veteran" then
                                    shortName = "Veteran"
                                    trackColor = { r = 0.2, g = 0.9, b = 0.9 }  -- cyan
                                elseif trk:match("Adv") then
                                    shortName = "Adventurer"
                                    trackColor = { r = 0.2, g = 0.6, b = 1 }  -- blue
                                elseif trk == "Delve" then
                                    shortName = "Delve"
                                    trackColor = { r = 1, g = 1, b = 1 }  -- white
                                end

                                if shortName ~= "" then
                                    trackText = "(" .. shortName .. " " .. nums .. ")"
                                end
                                break
                            end
                        end
                    end

                    tooltip:Hide()
                end

                if trackText ~= "" then
                    upgradeTag:SetText(trackText)
                    upgradeTag:SetTextColor(trackColor.r, trackColor.g, trackColor.b, 1)
                    upgradeTag:Show()
                else
                    upgradeTag:Hide()
                end
            else
                upgradeTag:Hide()
            end

            -- Show enchants if enabled
            if CharEnchantsEnabled() then
                -- Check if this slot can be enchanted in the current expansion
                if ENCHANTABLE_SLOTS[slotIndex] then
                    enchantsTag:SetFont(CharIlvlFont(), CharEnchantsFontSize(), "THINOUTLINE")

                    local tooltip = CreateFrame("GameTooltip", "EUICharEnchantsTooltip", nil, "GameTooltipTemplate")
                    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                    tooltip:SetInventoryItem("player", slotIndex)

                    local enchantText = ""
                    local rankIcon = ""

                    -- Look for "Enchanted:" and "Rank" lines in tooltip
                    for i = 1, tooltip:NumLines() do
                        local textLeft = _G["EUICharEnchantsTooltipTextLeft" .. i]:GetText() or ""
                        if textLeft:match("Enchanted:") then
                            enchantText = textLeft:gsub("Enchanted:%s*", "")
                            -- Remove "Enchant [SlotName] - " prefix, keep only the actual enchant name
                            enchantText = enchantText:gsub("^Enchant%s+[^-]+%s*-%s*", "")
                        end
                        -- Look for rank information in tooltip
                        if textLeft:match("Rank") then
                            rankIcon = textLeft:match("(Rank %d+)") or ""
                        end
                    end

                    tooltip:Hide()

                    -- Clean enchant text: remove trailing non-text characters (icons, etc.)
                    if enchantText ~= "" then
                        -- Match only valid text characters at the beginning
                        enchantText = enchantText:match("^([%w%s'&%-%.%+%%()]+)")
                        if not enchantText or enchantText == "" then
                            enchantText = ""
                        else
                            -- Trim leading and trailing whitespace
                            enchantText = enchantText:match("^%s*(.-)%s*$")
                        end
                    end

                    -- Apply multi-pass processing if shortening is enabled
                    if CharEnchantsShorten() and enchantText ~= "" then
                        enchantText = ProcessEnchantText(enchantText)
                    end

                    if enchantText ~= "" then
                        local displayText = enchantText
                        if rankIcon ~= "" then
                            displayText = enchantText .. " " .. rankIcon
                        end

                        enchantsTag:SetText(displayText)
                        enchantsTag:SetTextColor(1, 1, 1, 1)
                        enchantsTag:Show()
                    else
                        -- No enchant found but slot is enchantable - show "Missing enchant" in red
                        enchantsTag:SetText("<Missing enchant>")
                        enchantsTag:SetTextColor(1, 0, 0, 1)  -- Red
                        enchantsTag:Show()
                    end
                else
                    -- Slot is not enchantable in current expansion
                    enchantsTag:Hide()
                end
            else
                enchantsTag:Hide()
            end

            -- Show sockets if enabled and character frame is open
            if CharSocketsEnabled() and PaperDollFrame and PaperDollFrame:IsShown() then
                local socketIcons = GetOrCreateSocketsIcons(frame, side, slotIndex)

                local tooltip = CreateFrame("GameTooltip", "EUICharSocketsTooltip", nil, "GameTooltipTemplate")
                tooltip:SetOwner(UIParent, "ANCHOR_NONE")
                tooltip:SetInventoryItem("player", slotIndex)

                -- Extract socket textures from tooltip
                local socketTextures = {}
                for i = 1, 10 do
                    local texture = _G["EUICharSocketsTooltipTexture" .. i]
                    if texture and texture:IsShown() then
                        local tex = texture:GetTexture() or texture:GetTextureFileID()
                        if tex then
                            table.insert(socketTextures, tex)
                        end
                    end
                end

                tooltip:Hide()

                -- Position and show socket icons
                if #socketTextures > 0 then
                    local side = frame._euiCharSocketsSide
                    local slotIdx = frame._euiCharSocketsSlotIndex
                    local scale = CharSocketsScale()
                    local offsetX = CharSocketsOffsetX()
                    local offsetY = CharSocketsOffsetY()

                    for i, icon in ipairs(socketIcons) do
                        if socketTextures[i] then
                            icon:SetTexture(socketTextures[i])
                            icon:SetScale(scale)
                            -- Position icons on the outside edge of the item icon, clear of border
                            if side == "LEFT" then
                                icon:SetPoint("LEFT", frame, "LEFT", -16 - offsetX, -3 + offsetY - (i-1)*18)
                            elseif side == "TOP" then
                                if slotIdx == 16 then  -- MainHand - outside right edge
                                    icon:SetPoint("RIGHT", frame, "RIGHT", 16 + offsetX, -3 + offsetY - (i-1)*18)
                                else  -- OffHand - outside left edge
                                    icon:SetPoint("LEFT", frame, "LEFT", -16 - offsetX, -3 + offsetY - (i-1)*18)
                                end
                            else  -- RIGHT
                                icon:SetPoint("RIGHT", frame, "RIGHT", 16 + offsetX, -3 + offsetY - (i-1)*18)
                            end
                            icon:Show()
                        else
                            icon:Hide()
                        end
                    end
                else
                    for _, icon in ipairs(socketIcons) do
                        icon:Hide()
                    end
                end
            else
                -- Sockets disabled or frame not open - hide all icons
                if socketIcons then
                    for _, icon in ipairs(socketIcons) do
                        icon:Hide()
                    end
                end
            end
        end

        local function RefreshCharFrame()
            for slotIndex, data in pairs(GEAR_SLOTS) do
                PaintSlot(slotIndex, data[1], data[2])
            end
        end

        -- Wire up events
        local charWatcher = CreateFrame("Frame")
        charWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        charWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        charWatcher:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                C_Timer.After(1, RefreshCharFrame)
            else
                RefreshCharFrame()
            end
        end)

        -- Refresh when the character panel opens; hide socket icons when it closes
        if PaperDollFrame then
            PaperDollFrame:HookScript("OnShow", function()
                globalSocketContainer:Show()
                RefreshCharFrame()
            end)
            PaperDollFrame:HookScript("OnHide", function()
                globalSocketContainer:Hide()
            end)
        end

        EllesmereUI._refreshCharIlvl = RefreshCharFrame
        EllesmereUI._refreshCharEnchants = RefreshCharFrame
        EllesmereUI._refreshCharSockets = RefreshCharFrame
    end

        local resetAnnounceFrame = CreateFrame("Frame")
        resetAnnounceFrame:RegisterEvent("CHAT_MSG_SYSTEM")
        resetAnnounceFrame:SetScript("OnEvent", function(self, event, msg)
            if not (EllesmereUIDB and EllesmereUIDB.instanceResetAnnounce) then return end

            -- Only announce if we are inside an instance group.
            -- IsInGroup(LE_PARTY_CATEGORY_INSTANCE) covers both party and raid
            -- inside an instance; fall back to IsInGroup() for older API.
            local inInstanceGroup = (IsInGroup and LE_PARTY_CATEGORY_INSTANCE and
                                     IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
                                 or (IsInGroup and IsInGroup())

            if not inInstanceGroup then return end

            -- Small delay so Blizzard's own system message renders first.
            if MatchesAny(msg, RESET_PATTERNS) then
                C_Timer.After(0.3, function()
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    local customMsg = (EllesmereUIDB.instanceResetAnnounceMsg and
                                       EllesmereUIDB.instanceResetAnnounceMsg ~= "")
                                      and EllesmereUIDB.instanceResetAnnounceMsg
                                      or "Instance has been reset - you can re-enter now!"
                    SendChatMessage("[EUI] " .. customMsg, channel)
                end)
            elseif MatchesAny(msg, FAIL_PATTERNS) then
                C_Timer.After(0.3, function()
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    SendChatMessage("[EUI] Reset failed - there are still players inside the instance.", channel)
                end)
            end
        end)
    end

end)