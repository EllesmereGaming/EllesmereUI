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
            if event == "PLAYER_LOGIN" then
                self:UnregisterEvent("PLAYER_LOGIN")
                -- Defer 3s so ToyBox.fanfareToys is available (avoids
                -- the 1000+ toy fallback scan that spikes the login frame)
                C_Timer.After(3, DismissCollectionAlerts)
                return
            end
            DismissCollectionAlerts()
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Open Containers (incremental cache -- no login spike)
    ---------------------------------------------------------------------------
    do
        local _openableCache = {}  -- itemID -> true/false
        local _failedItems = {}   -- itemID -> true (items that failed to open, skip forever)
        local _cacheBuilt = false
        local function IsEnabled()
            return EllesmereUIDB and EllesmereUIDB.autoOpenContainers == true
        end
        local SLOTS_PER_FRAME = 3  -- check 3 slots per OnUpdate tick

        local function IsOpenableByID(itemID, bag, slot)
            local cached = _openableCache[itemID]
            if cached ~= nil then return cached end
            local tip = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
            if tip and tip.lines then
                for _, line in ipairs(tip.lines) do
                    if line and line.leftText and line.leftText == ITEM_OPENABLE then
                        _openableCache[itemID] = true
                        return true
                    end
                end
            end
            _openableCache[itemID] = false
            return false
        end

        -- Incremental scanner: checks SLOTS_PER_FRAME bag slots per tick.
        -- Once all bags are scanned, hides itself (zero CPU when idle).
        local _scanBag = BACKPACK_CONTAINER
        local _scanSlot = 1
        local _pendingOpens = {}

        local scanFrame = CreateFrame("Frame")
        scanFrame:Hide()
        scanFrame:SetScript("OnUpdate", function(self)
            if not IsEnabled() then self:Hide(); return end
            local checked = 0
            while checked < SLOTS_PER_FRAME do
                local numSlots = C_Container.GetContainerNumSlots(_scanBag)
                if _scanSlot > numSlots then
                    _scanBag = _scanBag + 1
                    _scanSlot = 1
                    if _scanBag > NUM_BAG_SLOTS then
                        -- Full scan complete
                        _cacheBuilt = true
                        self:Hide()
                        -- Open any containers found during scan
                        if #_pendingOpens > 0 and not InCombatLockdown() then
                            local function OpenNext(idx)
                                if idx > #_pendingOpens then wipe(_pendingOpens); return end
                                if InCombatLockdown() then wipe(_pendingOpens); return end
                                local item = _pendingOpens[idx]
                                local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
                                if info and info.itemID and _openableCache[info.itemID] and not _failedItems[info.itemID] then
                                    local prevID = info.itemID
                                    local prevCount = info.stackCount or 1
                                    C_Container.UseContainerItem(item.bag, item.slot)
                                    C_Timer.After(0.5, function()
                                        local after = C_Container.GetContainerItemInfo(item.bag, item.slot)
                                        if after and after.itemID == prevID and (after.stackCount or 1) >= prevCount then
                                            _failedItems[prevID] = true
                                        end
                                        OpenNext(idx + 1)
                                    end)
                                    return
                                end
                                C_Timer.After(0.5, function() OpenNext(idx + 1) end)
                            end
                            OpenNext(1)
                        end
                        return
                    end
                else
                    local info = C_Container.GetContainerItemInfo(_scanBag, _scanSlot)
                    if info and info.itemID then
                        if IsOpenableByID(info.itemID, _scanBag, _scanSlot) then
                            _pendingOpens[#_pendingOpens + 1] = { bag = _scanBag, slot = _scanSlot }
                        end
                    end
                    _scanSlot = _scanSlot + 1
                    checked = checked + 1
                end
            end
        end)

        -- Start incremental scan 2s after login
        C_Timer.After(2, function()
            if not IsEnabled() then return end
            _scanBag = BACKPACK_CONTAINER
            _scanSlot = 1
            wipe(_pendingOpens)
            scanFrame:Show()
        end)

        -- After cache is built, BAG_UPDATE_DELAYED only checks changed slots
        local containerFrame = CreateFrame("Frame")
        if EllesmereUIDB and EllesmereUIDB.autoOpenContainers == true then
            containerFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        end
        containerFrame:SetScript("OnEvent", function()
            if not _cacheBuilt then return end
            if not IsEnabled() then return end
            if InCombatLockdown() then return end
            local toOpen = {}
            for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID then
                        -- Only tooltip-check uncached items (new loot)
                        if _openableCache[info.itemID] == nil then
                            IsOpenableByID(info.itemID, bag, slot)
                        end
                        if _openableCache[info.itemID] and not _failedItems[info.itemID] then
                            toOpen[#toOpen + 1] = { bag = bag, slot = slot }
                        end
                    end
                end
            end
            if #toOpen == 0 then return end
            local function OpenNext(idx)
                if idx > #toOpen then return end
                if InCombatLockdown() then return end
                local item = toOpen[idx]
                local info2 = C_Container.GetContainerItemInfo(item.bag, item.slot)
                if info2 and info2.itemID and _openableCache[info2.itemID] and not _failedItems[info2.itemID] then
                    local prevID = info2.itemID
                    local prevCount = info2.stackCount or 1
                    C_Container.UseContainerItem(item.bag, item.slot)
                    C_Timer.After(0.5, function()
                        local after = C_Container.GetContainerItemInfo(item.bag, item.slot)
                        if after and after.itemID == prevID and (after.stackCount or 1) >= prevCount then
                            _failedItems[prevID] = true
                        end
                        OpenNext(idx + 1)
                    end)
                    return
                end
                C_Timer.After(0.5, function() OpenNext(idx + 1) end)
            end
            C_Timer.After(0.5, function() OpenNext(1) end)
        end)
    end

    ---------------------------------------------------------------------------
    --  Hide Screenshot Status
    ---------------------------------------------------------------------------
    do
        local hooked = false

        local function HideActionStatus()
            local actionStatus = _G.ActionStatus
            if actionStatus then
                actionStatus:Hide()
            end
        end

        local function ApplyScreenshotStatus()
            -- ActionStatus is lazy-created by Blizzard on the first screenshot
            -- event, so it may not exist yet. The ssFrame below catches the
            -- events and hides it immediately after Blizzard shows it.
        end

        EllesmereUI._applyScreenshotStatus = ApplyScreenshotStatus

        local ssFrame = CreateFrame("Frame")
        ssFrame:RegisterEvent("SCREENSHOT_SUCCEEDED")
        ssFrame:RegisterEvent("SCREENSHOT_FAILED")
        ssFrame:SetScript("OnEvent", function()
            if not EllesmereUIDB or EllesmereUIDB.hideScreenshotStatus ~= false then
                -- Hide on next frame so Blizzard's handler runs first
                C_Timer.After(0, HideActionStatus)
            end
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
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self, event, addonName)
            if event == "PLAYER_LOGIN" then
                self:UnregisterEvent("PLAYER_LOGIN")
                ApplyTrainAllButton()
            elseif event == "ADDON_LOADED" and addonName == "Blizzard_TrainerUI" then
                self:UnregisterEvent("ADDON_LOADED")
                ApplyTrainAllButton()
            end
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
            if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
                C_MerchantFrame.SellAllJunkItems()
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

                    -- Check if we can actually afford the repair
                    if not useGuild and GetMoney() < cost then
                        EllesmereUI.Print("|cff0CD29DEllesmereUI:|r |cffff6060Not enough gold to repair.|r")
                        return
                    end

                    RepairAllItems(useGuild)

                    if useGuild then
                        C_Timer.After(0.5, function()
                            local remainCost, stillNeed = GetRepairAllCost()
                            if stillNeed and remainCost > 0 then
                                if GetMoney() >= remainCost then
                                    RepairAllItems(false)
                                end
                            end
                        end)
                    end

                    local gold = floor(cost / 10000)
                    local silver = floor((cost % 10000) / 100)
                    local src = useGuild and " (guild bank)" or ""
                    EllesmereUI.Print("|cff0CD29DEllesmereUI:|r Repaired all items for " .. gold .. "g " .. silver .. "s." .. src)
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    --  Quick Loot
    ---------------------------------------------------------------------------
    if EllesmereUIDB and EllesmereUIDB.quickLoot then
        local lootFrame = CreateFrame("Frame")
        lootFrame:RegisterEvent("LOOT_READY")
        lootFrame:SetScript("OnEvent", function()
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

        -- Auto-accept role check for Quick Signup. Holding Shift skips the
        -- auto-accept so the dialog stays open (e.g. to type a signup note).
        LFGListApplicationDialog:HookScript("OnShow", function(self)
            if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
            if self.SignUpButton:IsEnabled() and not IsShiftKeyDown() then
                self.SignUpButton:Click()
            end
        end)

        -- Classic Dungeon Finder role check for Quick Signup
        local roleFrame = CreateFrame("Frame")
        roleFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
        roleFrame:SetScript("OnEvent", function()
            if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
            if not UnitInParty("player") then return end
            -- Holding Shift skips the auto role-check accept
            if IsShiftKeyDown() then return end
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
    --  Implementation moved to the parent (EllesmereUI_BlizzardParty.lua) so the
    --  Raid Frames module shares the exact same logic + saved setting. The QoL
    --  options toggle still drives it via EllesmereUI._applyHideBlizzardPartyFrame.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Hide Talking Head Frame
    --  The big NPC dialogue rectangle that pops up during quests/dungeons.
    ---------------------------------------------------------------------------
    do
        local function HookTalkingHead()
            local thf = _G.TalkingHeadFrame
            if not thf or EllesmereUI._GetFFD(thf).hooked then return end
            EllesmereUI._GetFFD(thf).hooked = true
            hooksecurefunc(thf, "PlayCurrent", function(self)
                if EllesmereUIDB and EllesmereUIDB.hideTalkingHead then
                    self:Hide()
                end
            end)
        end
        -- TalkingHeadFrame is load-on-demand; hook when it becomes available
        if _G.TalkingHeadFrame then
            HookTalkingHead()
        else
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, _, addon)
                if _G.TalkingHeadFrame then
                    HookTalkingHead()
                    self:UnregisterAllEvents()
                end
            end)
        end
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

    ---------------------------------------------------------------------------
    --  24-Hour Clock Fix (Blizzard bug: CVar resets to 12h on every login)
    --  We save the user's preference when they toggle the checkbox, then
    --  restore it on login if Blizzard's bug reset it.
    ---------------------------------------------------------------------------
    do
        local saved = EllesmereUIDB and EllesmereUIDB.clockFormat24h
        -- Restore: only if user previously chose 24h and the CVar got reset
        if saved and GetCVar("timeMgrUseMilitaryTime") ~= "1" then
            C_Timer.After(0.5, function()
                if not TimeManagerFrame then
                    if TimeManager_LoadUI then TimeManager_LoadUI() end
                end
                local cb = TimeManagerMilitaryTimeCheck
                if cb then
                    cb:SetChecked(true)
                    local fn = cb:GetScript("OnClick")
                    if fn then fn(cb) end
                end
            end)
        end
        -- Track: hook the checkbox so we remember whenever the user changes it
        local function HookClockCheckbox()
            local cb = TimeManagerMilitaryTimeCheck
            if not cb then return end
            cb:HookScript("OnClick", function(self)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.clockFormat24h = self:GetChecked() and true or nil
            end)
        end
        -- The TimeManager may not be loaded yet; hook when it appears
        if TimeManagerMilitaryTimeCheck then
            HookClockCheckbox()
        else
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_TimeManager" then
                    self:UnregisterEvent("ADDON_LOADED")
                    HookClockCheckbox()
                end
            end)
        end
    end

end)

-------------------------------------------------------------------------------
--  Guild Chat Privacy
--  Streamer feature: overlay on CommunitiesFrame guild chat, click to reveal.
-------------------------------------------------------------------------------
do
    local overlay
    local function ShowOverlay()
        if not overlay then return end
        if not (EllesmereUIDB and EllesmereUIDB.guildChatPrivacy) then return end
        local cf = CommunitiesFrame
        if not cf or not cf.Chat or not cf.Chat.MessageFrame then return end
        local mf = cf.Chat.MessageFrame
        overlay:SetParent(mf)
        overlay:SetAllPoints(mf)
        overlay:SetFrameLevel(mf:GetFrameLevel() + 20)
        overlay:Show()
    end

    local function ApplyGuildChatPrivacy()
        local enabled = EllesmereUIDB and EllesmereUIDB.guildChatPrivacy
        if not enabled then
            if overlay then overlay:Hide() end
            return
        end

        if not overlay then
            overlay = CreateFrame("Button", nil, UIParent)
            overlay:SetFrameStrata("DIALOG")
            local bg = overlay:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", -2, 0)
            bg:SetPoint("BOTTOMRIGHT", 2, -4)
            bg:SetColorTexture(0.133, 0.133, 0.133, 1)
            local txt = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            txt:SetPoint("CENTER")
            txt:SetText("Click to Show")
            txt:SetTextColor(0.7, 0.7, 0.7, 1)
            overlay:SetScript("OnClick", function(self)
                self:Hide()
            end)
        end

        if CommunitiesFrame then
            ShowOverlay()
            if not overlay._hooked then
                CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                overlay._hooked = true
            end
        else
            local loader = CreateFrame("Frame")
            loader:RegisterEvent("ADDON_LOADED")
            loader:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_Communities" then
                    self:UnregisterAllEvents()
                    if EllesmereUIDB and EllesmereUIDB.guildChatPrivacy then
                        ShowOverlay()
                        if not overlay._hooked then
                            CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                            overlay._hooked = true
                        end
                    end
                end
            end)
        end
    end
    EllesmereUI._applyGuildChatPrivacy = ApplyGuildChatPrivacy

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyGuildChatPrivacy()
    end)
end

-------------------------------------------------------------------------------
--  Secondary Stats Display
--  On-screen overlay showing crit/haste/mastery/vers (+ optional tertiaries).
-------------------------------------------------------------------------------
do
    local statsFrame, statsText
    local format = string.format

    local function UpdateSecondaryStats()
        if not statsFrame or not statsFrame:IsShown() then return end
        if not statsFrame._classHex then
            local _, cls = UnitClass("player")
            local cc = cls and EllesmereUI.GetClassColor(cls)
            if cc then
                statsFrame._classR, statsFrame._classG, statsFrame._classB = cc.r, cc.g, cc.b
                statsFrame._classHex = format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
            else
                statsFrame._classR, statsFrame._classG, statsFrame._classB = 1, 1, 1
                statsFrame._classHex = "ffffff"
            end
        end
        local c = EllesmereUIDB and EllesmereUIDB.secondaryStatsColor
        local cr, cg, cb
        if c then
            cr, cg, cb = c.r, c.g, c.b
        else
            cr, cg, cb = statsFrame._classR, statsFrame._classG, statsFrame._classB
        end
        local labelHex = c and format("%02x%02x%02x", cr * 255, cg * 255, cb * 255) or statsFrame._classHex

        local crit = GetCritChance("player")
        local haste = UnitSpellHaste("player")
        local mastery = GetMasteryEffect()
        local versRating = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
        local versBase = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
        local vers = (issecretvalue(versRating) or issecretvalue(versBase)) and versRating or (versRating + versBase)

        local txt =
            format("|cff%sCrit:|r  |cffffffff%.2f%%|r", labelHex, crit) .. "\n" ..
            format("|cff%sHaste:|r  |cffffffff%.2f%%|r", labelHex, haste) .. "\n" ..
            format("|cff%sMastery:|r  |cffffffff%.2f%%|r", labelHex, mastery) .. "\n" ..
            format("|cff%sVers:|r  |cffffffff%.2f%%|r", labelHex, vers)

        if EllesmereUIDB and EllesmereUIDB.showTertiaryStats then
            local tc = EllesmereUIDB.tertiaryStatsColor
            local tr, tg, tb
            if tc then
                tr, tg, tb = tc.r, tc.g, tc.b
            else
                tr, tg, tb = statsFrame._classR, statsFrame._classG, statsFrame._classB
            end
            local tertHex = tc and format("%02x%02x%02x", tr * 255, tg * 255, tb * 255) or statsFrame._classHex

            local leech = GetLifesteal()
            local avoidance = GetAvoidance()
            local speed = GetSpeed()
            txt = txt .. "\n" ..
                format("|cff%sLeech:|r  |cffffffff%.2f%%|r", tertHex, leech) .. "\n" ..
                format("|cff%sAvoidance:|r  |cffffffff%.2f%%|r", tertHex, avoidance) .. "\n" ..
                format("|cff%sSpeed:|r  |cffffffff%.2f%%|r", tertHex, speed)
        end

        statsText:SetText(txt)
    end

    local function ApplySecondaryStats()
        local enabled = EllesmereUIDB and EllesmereUIDB.showSecondaryStats
        if not enabled then
            if statsFrame then
                statsFrame:Hide()
                statsFrame:UnregisterAllEvents()
            end
            return
        end
        if not statsFrame then
            statsFrame = CreateFrame("Frame", "EUI_SecondaryStats", UIParent)
            statsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -12)
            statsFrame:SetSize(160, 60)
            statsFrame:SetFrameStrata("LOW")
            statsText = statsFrame:CreateFontString(nil, "OVERLAY")
            statsText:SetPoint("TOPLEFT")
            statsText:SetJustifyH("LEFT")
        end
        if statsText then
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            statsText:SetFont(font, 12, EllesmereUI.GetFontOutlineFlag("extras"))
            if EllesmereUI.GetFontUseShadow("extras") then
                statsText:SetShadowOffset(1, -1)
            else
                statsText:SetShadowOffset(0, 0)
            end
        end
        local pos = EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
        local scale = 1.0
        if pos then
            if pos.point then
                statsFrame:ClearAllPoints()
                statsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            end
            if pos.scale then
                scale = pos.scale
            end
        end
        if statsText then
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            local fontSize = math.floor(12 * scale + 0.5)
            statsText:SetFont(font, fontSize, EllesmereUI.GetFontOutlineFlag("extras"))
            if EllesmereUI.GetFontUseShadow("extras") then
                statsText:SetShadowOffset(1, -1)
            else
                statsText:SetShadowOffset(0, 0)
            end
        end
        for _, ev in ipairs({
            "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
            "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_SPELL_HASTE",
            "MASTERY_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
            "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD",
        }) do
            statsFrame:RegisterEvent(ev)
        end
        local _statsPending = false
        statsFrame:SetScript("OnEvent", function(_, _, unit)
            if unit and unit ~= "player" then return end
            if _statsPending then return end
            _statsPending = true
            C_Timer.After(0.5, function()
                _statsPending = false
                UpdateSecondaryStats()
            end)
        end)
        statsFrame:Show()
        UpdateSecondaryStats()
    end
    EllesmereUI._applySecondaryStats = ApplySecondaryStats

    EllesmereUI._getSecondaryStatsFrame = function()
        if not statsFrame then
            ApplySecondaryStats()
        end
        return statsFrame
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplySecondaryStats()
    end)
end

-------------------------------------------------------------------------------
--  FPS Counter
-------------------------------------------------------------------------------
do
    local fpsFrame
    local floor = math.floor

    local function CreateFPSCounter()
        if fpsFrame then return end
        local FONT = EllesmereUI.GetFontPath("extras")
        local FONT_SIZE = (EllesmereUIDB and EllesmereUIDB.fpsTextSize) or 12
        local LABEL_SIZE = FONT_SIZE - 2
        local SHADOW_X, SHADOW_Y = 1, -1
        fpsFrame = CreateFrame("Frame", "EUI_FPSCounter", UIParent)
        fpsFrame:SetSize(60, 20)
        fpsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
        fpsFrame:SetFrameStrata("MEDIUM")
        fpsFrame:SetFrameLevel(10)
        fpsFrame:EnableMouse(false)

        local function MakeFS(size)
            local f = fpsFrame:CreateFontString(nil, "OVERLAY")
            f:SetFont(FONT, size, EllesmereUI.GetFontOutlineFlag("extras"))
            if EllesmereUI.GetFontUseShadow("extras") then f:SetShadowOffset(SHADOW_X, SHADOW_Y) else f:SetShadowOffset(0, 0) end
            f:SetTextColor(1, 1, 1, 1)
            return f
        end

        local fsFps = MakeFS(FONT_SIZE)
        fsFps:SetPoint("LEFT")
        fpsFrame._text = fsFps

        local DIV_W, DIV_H = 1, 10
        local DIV_PAD = 6

        local function MakeDivider()
            local d = fpsFrame:CreateTexture(nil, "OVERLAY")
            d:SetColorTexture(1, 1, 1, 0.25)
            d:SetSize(DIV_W, DIV_H)
            return d
        end

        local divWorld = MakeDivider()
        local fsWorldVal = MakeFS(FONT_SIZE)
        local fsWorldLbl = MakeFS(LABEL_SIZE)
        fpsFrame._divWorld = divWorld
        fpsFrame._textWorld = fsWorldVal

        local divLocal = MakeDivider()
        local fsLocalVal = MakeFS(FONT_SIZE)
        local fsLocalLbl = MakeFS(LABEL_SIZE)
        fpsFrame._divLocal = divLocal
        fpsFrame._textLocal = fsLocalVal

        local function UpdateFPS(self)
            local db = EllesmereUIDB or {}
            local c = db.fpsColor
            local cr, cg, cb, ca = 1, 1, 1, 1
            if c then cr, cg, cb, ca = c.r or 1, c.g or 1, c.b or 1, c.a or 1 end
            fsFps:SetTextColor(cr, cg, cb, ca)
            fsWorldVal:SetTextColor(cr, cg, cb, ca)
            fsWorldLbl:SetTextColor(cr, cg, cb, ca * 0.6)
            fsLocalVal:SetTextColor(cr, cg, cb, ca)
            fsLocalLbl:SetTextColor(cr, cg, cb, ca * 0.6)
            divWorld:SetColorTexture(cr, cg, cb, ca * 0.35)
            divLocal:SetColorTexture(cr, cg, cb, ca * 0.35)

            local fps = floor(GetFramerate() + 0.5)
            fsFps:SetText(fps .. " fps")

            local showWorld = db.fpsShowWorldMS
            local showLocal = (db.fpsShowLocalMS == nil) and true or db.fpsShowLocalMS
            local _, _, latHome, latWorld = GetNetStats()

            fsFps:ClearAllPoints()
            fsFps:SetPoint("LEFT", fpsFrame, "LEFT", 0, 0)
            local anchor = fsFps

            if showWorld then
                fsWorldVal:SetText(latWorld .. " ms")
                fsWorldLbl:SetText("(world)")
                divWorld:ClearAllPoints()
                divWorld:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divWorld:Show()
                fsWorldVal:ClearAllPoints()
                fsWorldVal:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                fsWorldVal:Show()
                fsWorldLbl:ClearAllPoints()
                fsWorldLbl:SetPoint("LEFT", fsWorldVal, "RIGHT", 3, 0)
                fsWorldLbl:Show()
                anchor = fsWorldLbl
            else
                divWorld:Hide(); fsWorldVal:Hide(); fsWorldLbl:Hide()
            end

            if showLocal then
                fsLocalVal:SetText(latHome .. " ms")
                fsLocalLbl:SetText("(local)")
                divLocal:ClearAllPoints()
                divLocal:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divLocal:Show()
                fsLocalVal:ClearAllPoints()
                fsLocalVal:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                fsLocalVal:Show()
                fsLocalLbl:ClearAllPoints()
                fsLocalLbl:SetPoint("LEFT", fsLocalVal, "RIGHT", 3, 0)
                fsLocalLbl:Show()
                anchor = fsLocalLbl
            else
                divLocal:Hide(); fsLocalVal:Hide(); fsLocalLbl:Hide()
            end

            local totalW = fsFps:GetStringWidth()
            if showWorld then totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsWorldVal:GetStringWidth() + 3 + fsWorldLbl:GetStringWidth() end
            if showLocal then totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsLocalVal:GetStringWidth() + 3 + fsLocalLbl:GetStringWidth() end
            self:SetSize(totalW + 4, 20)
        end

        local elapsed = 0
        fpsFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < 1 then return end
            elapsed = 0
            UpdateFPS(self)
        end)
        fpsFrame._updateNow = function() elapsed = 0; UpdateFPS(fpsFrame) end
        fpsFrame:Hide()
    end

    EllesmereUI._applyFPSCounter = function()
        local shouldShow = EllesmereUIDB and EllesmereUIDB.showFPS
        if shouldShow then
            CreateFPSCounter()
            local sz = (EllesmereUIDB and EllesmereUIDB.fpsTextSize) or 12
            local lblSz = sz - 2
            local fp = EllesmereUI.GetFontPath("extras")
            local outF = EllesmereUI.GetFontOutlineFlag("extras")
            if fpsFrame._text then fpsFrame._text:SetFont(fp, sz, outF) end
            if fpsFrame._textWorld then fpsFrame._textWorld:SetFont(fp, sz, outF) end
            if fpsFrame._textLocal then fpsFrame._textLocal:SetFont(fp, sz, outF) end
            if fpsFrame._lblWorld then fpsFrame._lblWorld:SetFont(fp, lblSz, outF) end
            if fpsFrame._lblLocal then fpsFrame._lblLocal:SetFont(fp, lblSz, outF) end
            local pos = EllesmereUIDB and EllesmereUIDB.fpsPos
            if pos and pos.point then
                if pos.scale then pcall(function() fpsFrame:SetScale(pos.scale) end) end
                fpsFrame:ClearAllPoints()
                fpsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            end
            fpsFrame._updateNow()
            fpsFrame:Show()
        elseif fpsFrame then
            fpsFrame:Hide()
        end
    end

    C_Timer.After(2, function()
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_FPS",
                label = "FPS Counter",
                group = "General",
                order = 700,
                getFrame = function()
                    if not fpsFrame then CreateFPSCounter() end
                    return fpsFrame
                end,
                getSize = function()
                    if fpsFrame then return fpsFrame:GetWidth(), fpsFrame:GetHeight() end
                    return 80, 20
                end,
                noResize = true,
                savePos = function(key, point, relPoint, x, y)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.fpsPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if fpsFrame and not EllesmereUI._unlockActive then
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPos = function()
                    return EllesmereUIDB and EllesmereUIDB.fpsPos
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.fpsPos = nil end
                end,
                applyPos = function()
                    if not fpsFrame then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.fpsPos
                    if pos and pos.point then
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            }),
        })
    end)

    C_Timer.After(2.5, function()
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_SecondaryStats",
                label = "Secondary Stats",
                group = "General",
                order = 710,
                getFrame = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    return f
                end,
                getSize = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 160, 60
                end,
                noResize = true,
                savePos = function(key, point, relPoint, x, y)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.secondaryStatsPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                        if f then
                            f:ClearAllPoints()
                            f:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                        end
                    end
                end,
                loadPos = function()
                    return EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.secondaryStatsPos = nil end
                end,
                applyPos = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if not f then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                    if pos and pos.point then
                        f:ClearAllPoints()
                        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            }),
        })
    end)

    local fpsBind = CreateFrame("Button", "EUI_FPSBindBtn", UIParent)
    fpsBind:Hide()
    fpsBind:SetScript("OnClick", function()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.showFPS = not EllesmereUIDB.showFPS
        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
    end)

    C_Timer.After(1, function()
        if EllesmereUIDB and EllesmereUIDB.showFPS then
            EllesmereUI._applyFPSCounter()
        end
        local function ApplyFPSBind()
            if EllesmereUIDB and EllesmereUIDB.fpsToggleKey then
                SetOverrideBindingClick(fpsBind, true, EllesmereUIDB.fpsToggleKey, "EUI_FPSBindBtn")
            end
        end
        if InCombatLockdown() then
            local w = CreateFrame("Frame")
            w:RegisterEvent("PLAYER_REGEN_ENABLED")
            w:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ApplyFPSBind()
            end)
        else
            ApplyFPSBind()
        end
    end)
end

-------------------------------------------------------------------------------
--  Durability Warning
-------------------------------------------------------------------------------
do
    local durWarnOverlay
    local function CreateDurabilityWarning()
        if durWarnOverlay then return end

        durWarnOverlay = CreateFrame("Frame", nil, UIParent)
        durWarnOverlay:SetSize(400, 40)
        durWarnOverlay:SetFrameStrata("HIGH")
        durWarnOverlay:SetFrameLevel(50)
        durWarnOverlay:EnableMouse(false)
        durWarnOverlay:SetMouseClickEnabled(false)

        local fs = durWarnOverlay:CreateFontString(nil, "OVERLAY")
        fs:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 18, EllesmereUI.GetFontOutlineFlag("extras"))
        fs:SetPoint("CENTER")
        fs:SetText("Low Durability")
        durWarnOverlay._text = fs

        local function ApplySettings()
            durWarnOverlay:ClearAllPoints()
            local pos = EllesmereUIDB and EllesmereUIDB.durWarnPos
            if pos and pos.point then
                durWarnOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 250)
            else
                local yOff = EllesmereUIDB and EllesmereUIDB.durWarnYOffset or 250
                durWarnOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, yOff)
            end
            durWarnOverlay:SetScale(1)

            local fontPath = EllesmereUI.GetFontPath("extras")
            local durSz = (EllesmereUIDB and EllesmereUIDB.durWarnTextSize) or 30
            fs:SetFont(fontPath, durSz, EllesmereUI.GetFontOutlineFlag("extras"))

            local c = EllesmereUIDB and EllesmereUIDB.durWarnColor
            if c then
                fs:SetTextColor(c.r, c.g, c.b, 1)
            else
                fs:SetTextColor(1, 0.27, 0.27, 1)
            end
        end
        durWarnOverlay._applySettings = ApplySettings

        local ag = fs:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.3)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(1)
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.3)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(2)
        ag:SetLooping("REPEAT")

        durWarnOverlay._show = function(pct)
            ApplySettings()
            durWarnOverlay._text:SetText("Low Durability (" .. math.floor(pct) .. "%)")
            durWarnOverlay:Show()
            ag:Play()
        end

        durWarnOverlay:SetScript("OnHide", function()
            ag:Stop()
        end)

        durWarnOverlay:Hide()
    end

    EllesmereUI._applyDurWarn = function()
        CreateDurabilityWarning()
        durWarnOverlay._applySettings()
    end
    EllesmereUI._durWarnApplySettings = EllesmereUI._applyDurWarn

    EllesmereUI._durWarnPreview = function()
        CreateDurabilityWarning()
        durWarnOverlay._show(25)
        durWarnOverlay._text:SetText("Low Durability (Preview)")
    end

    EllesmereUI._durWarnHidePreview = function()
        if durWarnOverlay then durWarnOverlay:Hide() end
    end

    local repairWarnFrame = CreateFrame("Frame", nil, UIParent)
    if not (EllesmereUIDB and EllesmereUIDB.repairWarning == false) then
        repairWarnFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        repairWarnFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        repairWarnFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        repairWarnFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    end

    local function CheckDurabilityAndShow()
        if not EllesmereUIDB then return end
        if EllesmereUIDB.repairWarning == false then
            if durWarnOverlay then durWarnOverlay:Hide() end
            return
        end
        if InCombatLockdown() then return end

        local lowestDur = 100
        for slot = 1, 18 do
            local cur, mx = GetInventoryItemDurability(slot)
            if cur and mx and mx > 0 then
                local pct = (cur / mx) * 100
                if pct < lowestDur then lowestDur = pct end
            end
        end

        if lowestDur < (EllesmereUIDB.durWarnThreshold or 40) then
            CreateDurabilityWarning()
            durWarnOverlay._show(lowestDur)
        elseif durWarnOverlay then
            durWarnOverlay:Hide()
        end
    end

    repairWarnFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if durWarnOverlay then durWarnOverlay:Hide() end
            return
        end
        CheckDurabilityAndShow()
    end)
end

-------------------------------------------------------------------------------
--  Pixel-Perfect UI Scale
-------------------------------------------------------------------------------
do
    local function ApplyPPUIScale()
        local scale = EllesmereUIDB and EllesmereUIDB.ppUIScale
        if not scale then return end
        local mf = EllesmereUI._mainFrame
        local panelScaleBefore
        if mf then panelScaleBefore = mf:GetEffectiveScale() end
        EllesmereUI.PP.SetUIScale(scale)
        if mf and panelScaleBefore then
            local newEff = UIParent:GetEffectiveScale()
            if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
        end
    end

    EllesmereUI._applyPPUIScale = ApplyPPUIScale

    local ppScaleFrame = CreateFrame("Frame")
    ppScaleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ppScaleFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ApplyPPUIScale()
    end)
end

-------------------------------------------------------------------------------
--  Disable Right Click Targeting
-------------------------------------------------------------------------------
do
    local mlookBtn = CreateFrame("Button", "EUI_MouseLookBtn", UIParent)
    mlookBtn:RegisterForClicks("AnyDown", "AnyUp")
    mlookBtn:SetScript("OnClick", function(_, _, down)
        if down then MouselookStart() else MouselookStop() end
    end)

    local stateFrame = CreateFrame("Frame", "EUI_NoRightClickState", UIParent, "SecureHandlerStateTemplate")

    local function ApplyRightClickTarget()
        if InCombatLockdown() then
            local deferFrame = CreateFrame("Frame")
            deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            deferFrame:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ApplyRightClickTarget()
            end)
            return
        end
        local db = EllesmereUIDB
        local enemy = db and db.disableRightClickTarget
        local allyCombat = db and db.disableRightClickTargetAllyCombat
        if enemy or allyCombat then
            -- Build the mouseover condition from the two independent toggles.
            -- Enemies fire everywhere. Allies only fire while the player is in
            -- combat (the [combat] conditional), so right clicking friendly NPCs
            -- such as vendors and quest givers still works out of combat.
            local macro = ""
            if enemy then macro = macro .. "[@mouseover,harm,nodead]1;" end
            if allyCombat then macro = macro .. "[@mouseover,help,nodead,combat]1;" end
            macro = macro .. "0"
            SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
            -- [combat] needs regen events so the state re-evaluates on combat
            -- enter/exit even when the mouseover unit has not changed.
            if allyCombat then
                SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_DISABLED")
                SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
            RegisterStateDriver(stateFrame, "mov", macro)
            stateFrame:SetAttribute("_onstate-mov", [[
                if newstate == 1 then
                    self:SetBindingClick(1, "BUTTON2", "EUI_MouseLookBtn")
                else
                    self:ClearBindings()
                end
            ]])
        else
            UnregisterStateDriver(stateFrame, "mov")
            ClearOverrideBindings(stateFrame)
        end
    end

    EllesmereUI._applyRightClickTarget = ApplyRightClickTarget

    local rcInitFrame = CreateFrame("Frame")
    rcInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rcInitFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ApplyRightClickTarget()
    end)
end

-------------------------------------------------------------------------------
--  Character Crosshair
-------------------------------------------------------------------------------
do
    local crosshairFrame
    local function CreateCrosshair()
        if crosshairFrame then return end
        crosshairFrame = CreateFrame("Frame", "EUI_CharacterCrosshair", UIParent)
        -- MEDIUM sits above gameplay HUD but below DIALOG/HIGH panels (talents, character, etc.).
        crosshairFrame:SetFrameStrata("MEDIUM")
        crosshairFrame:SetFrameLevel(100)
        crosshairFrame:EnableMouse(false)
        crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        crosshairFrame:SetSize(1, 1)

        local function MakeArm()
            local t = crosshairFrame:CreateTexture(nil, "OVERLAY")
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            return t
        end
        crosshairFrame._hBar = MakeArm()
        crosshairFrame._vBar = MakeArm()
    end

    EllesmereUI._applyCrosshair = function()
        local PP = EllesmereUI.PanelPP
        local size = EllesmereUIDB and EllesmereUIDB.crosshairSize or "None"
        if size == "None" then
            if crosshairFrame then crosshairFrame:Hide() end
            return
        end

        CreateCrosshair()

        local c = EllesmereUIDB and EllesmereUIDB.crosshairColor
        local cr = c and c.r or 1
        local cg = c and c.g or 1
        local cb = c and c.b or 1
        local ca = c and c.a or 0.75

        local thickness = (size == "Thin") and 1 or (size == "Thick") and 3 or 2
        local ARM = PP.Scale(20)

        local hBar = crosshairFrame._hBar
        local vBar = crosshairFrame._vBar

        hBar:SetColorTexture(cr, cg, cb, ca)
        hBar:ClearAllPoints()
        hBar:SetPoint("LEFT",  crosshairFrame, "CENTER", -ARM, 0)
        hBar:SetPoint("RIGHT", crosshairFrame, "CENTER",  ARM, 0)
        hBar:SetHeight(thickness)

        vBar:SetColorTexture(cr, cg, cb, ca)
        vBar:ClearAllPoints()
        vBar:SetPoint("TOP",    crosshairFrame, "CENTER", 0,  ARM)
        vBar:SetPoint("BOTTOM", crosshairFrame, "CENTER", 0, -ARM)
        vBar:SetWidth(thickness)

        crosshairFrame:Show()
    end

    C_Timer.After(1, function()
        if EllesmereUIDB and EllesmereUIDB.crosshairSize and EllesmereUIDB.crosshairSize ~= "None" then
            EllesmereUI._applyCrosshair()
        end
    end)

    ---------------------------------------------------------------------------
    --  Map Coordinates
    ---------------------------------------------------------------------------
    do
        local coordFrame
        local coordText

        local function CreateCoordFrame()
            if coordFrame then return end
            local mapLoaded = C_AddOns.IsAddOnLoaded("Blizzard_WorldMap")
            if not mapLoaded or not WorldMapFrame then return end

            coordFrame = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
            coordFrame:SetFrameStrata("HIGH")
            coordFrame:SetSize(1, 1)
            coordFrame:SetPoint("BOTTOM", WorldMapFrame.ScrollContainer, "BOTTOM", 0, 10)

            local PP = EllesmereUI.PanelPP
            local fp = EllesmereUI.GetFontPath()
            local outF = EllesmereUI.GetFontOutlineFlag()
            local sz = (EllesmereUIDB and EllesmereUIDB.mapCoordsTextSize) or 12

            local divider = coordFrame:CreateTexture(nil, "OVERLAY")
            divider:SetColorTexture(1, 1, 1, 0.9)
            PP.Size(divider, 2, sz)
            divider:SetPoint("BOTTOM", coordFrame, "BOTTOM", 0, 0)

            local useShadow = EllesmereUI.GetFontUseShadow()

            local cursorFS = coordFrame:CreateFontString(nil, "OVERLAY")
            cursorFS:SetFont(fp, sz, outF)
            cursorFS:SetTextColor(1, 1, 1, 0.9)
            cursorFS:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0)
            cursorFS:SetJustifyH("RIGHT")
            cursorFS:SetPoint("RIGHT", divider, "LEFT", -10, 0)

            local playerFS = coordFrame:CreateFontString(nil, "OVERLAY")
            playerFS:SetFont(fp, sz, outF)
            playerFS:SetTextColor(1, 1, 1, 0.9)
            playerFS:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0)
            playerFS:SetJustifyH("LEFT")
            playerFS:SetPoint("LEFT", divider, "RIGHT", 10, 0)

            coordText = { cursor = cursorFS, player = playerFS, divider = divider }

            local elapsed = 0
            coordFrame:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed < 0.05 then return end
                elapsed = 0
                local mapID = WorldMapFrame:GetMapID()
                if not mapID then
                    cursorFS:SetText("")
                    playerFS:SetText("")
                    divider:Hide()
                    return
                end
                -- Player position (hidden in instances)
                local playerPos = C_Map.GetPlayerMapPosition(mapID, "player")
                local hasPlayer = false
                if playerPos then
                    local px, py = playerPos:GetXY()
                    if px and py and px > 0 and py > 0 then
                        playerFS:SetText("P: " .. format("%.0f, %.0f", px * 100, py * 100))
                        hasPlayer = true
                    end
                end
                if hasPlayer then
                    divider:Show()
                    playerFS:Show()
                else
                    divider:Hide()
                    playerFS:Hide()
                end

                -- Cursor position
                local cText = "0, 0"
                local child = WorldMapFrame.ScrollContainer.Child
                if child and child:IsMouseOver() then
                    local cx, cy = child:GetSize()
                    if cx and cx > 0 and cy and cy > 0 then
                        local scale = child:GetEffectiveScale()
                        local left = child:GetLeft()
                        local top = child:GetTop()
                        if scale and left and top then
                            local curX, curY = GetCursorPosition()
                            local nx = (curX / scale - left) / cx
                            local ny = (top - curY / scale) / cy
                            if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                                cText = format("%.0f, %.0f", nx * 100, ny * 100)
                            end
                        end
                    end
                end

                cursorFS:SetText("C: " .. cText)
            end)
        end

        EllesmereUI._applyMapCoords = function()
            local enabled = EllesmereUIDB and EllesmereUIDB.mapCoords
            if enabled then
                CreateCoordFrame()
                if coordFrame then
                    local PP = EllesmereUI.PanelPP
                    local fp = EllesmereUI.GetFontPath()
                    local outF = EllesmereUI.GetFontOutlineFlag()
                    local useShadow = EllesmereUI.GetFontUseShadow()
                    local sz = (EllesmereUIDB and EllesmereUIDB.mapCoordsTextSize) or 12
                    coordText.cursor:SetFont(fp, sz, outF)
                    coordText.cursor:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0)
                    coordText.player:SetFont(fp, sz, outF)
                    coordText.player:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0)
                    PP.Size(coordText.divider, 2, sz)
                    coordFrame:Show()
                end
            elseif coordFrame then
                coordFrame:Hide()
            end
        end

        -- WorldMapFrame is load-on-demand; hook when it loads
        if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            EllesmereUI._applyMapCoords()
        else
            local loader = CreateFrame("Frame")
            loader:RegisterEvent("ADDON_LOADED")
            loader:SetScript("OnEvent", function(self, _, addonName)
                if addonName == "Blizzard_WorldMap" then
                    self:UnregisterEvent("ADDON_LOADED")
                    EllesmereUI._applyMapCoords()
                end
            end)
        end
    end
end