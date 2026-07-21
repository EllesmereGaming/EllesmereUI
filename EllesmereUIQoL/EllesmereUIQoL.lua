-------------------------------------------------------------------------------
--  EUI_QoL.lua
--  Runtime logic for all Quality-of-Life features toggled in the QoL Features
--  tab of Global Settings. No UI code here -- only gameplay behaviour.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Per-profile storage for QoL "extras" (Secondary Stats + FPS counter).
--  These were account-wide on the EllesmereUIDB root; they now live in the QoL
--  profile DB (folder EllesmereUIQoL) so they travel with profiles, export/
--  import, and module sync. The migration in EllesmereUI_Migration.lua seeds
--  every existing profile from the old account-wide values, so nobody loses
--  their setup. Reads fall back to the frozen account-wide root for any profile
--  that has no per-profile value yet (newly created profiles, sync gaps);
--  writes always go per-profile. Mirrors the crosshair read/fallback pattern.
--
--  This shares EllesmereUIQoLDB with the Cursor / BattleRes / Bloodlust modules
--  -- each NewDB call merges its own defaults into the SAME profile table, and
--  the profile system repoints every handle on a profile swap.
-------------------------------------------------------------------------------
local _qolExtrasDB
local function QoLExtrasProfile()
    if not _qolExtrasDB and EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB then
        _qolExtrasDB = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", { profile = {} })
    end
    return _qolExtrasDB and _qolExtrasDB.profile
end
function EllesmereUI.QoLExtrasGet(k)
    local p = QoLExtrasProfile()
    if p and p[k] ~= nil then return p[k] end
    return EllesmereUIDB and EllesmereUIDB[k]
end
function EllesmereUI.QoLExtrasSet(k, v)
    local p = QoLExtrasProfile()
    if p then p[k] = v; return end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB[k] = v
end

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
        -- Self-tracked in-flight opens, keyed by bag/slot. Set synchronously in
        -- the same tick as UseContainerItem (Lua is single-threaded, so no other
        -- open pass can slip between the use and this write) and cleared at the
        -- 0.5s recheck. This -- not Blizzard's isLocked flag, which isn't set
        -- until a server round-trip completes -- is what stops two overlapping
        -- passes from double-using the same slot and stranding it greyed.
        local _openInProgress = {}
        -- Many payout containers (e.g. Artisan's Consortium Payouts) open a loot
        -- window and linger in the bag until looted. Opening another container --
        -- or re-opening the lingering one -- while that window is up strands it.
        -- Gate all opens on this and resume on LOOT_CLOSED.
        local _lootOpen = false
        -- Attribution for loot windows our own opens spawn. _pendingOpen is
        -- stamped just before UseContainerItem and cleared at that open's
        -- 0.5s recheck; LOOT_OPENED captures it into _lootSource. When the
        -- window closes, the source slot is re-read: a linger-until-looted
        -- container still sitting there with an un-decremented count means
        -- its loot could not be taken (bags full / unique item cap), and
        -- re-opening it would just re-spawn the same un-lootable window in
        -- an endless loop the user cannot escape. It is skipped for the
        -- rest of the session instead (a reload retries it, so freed bag
        -- space recovers naturally).
        local _pendingOpen, _lootSource
        -- Global single-flight: only one open cycle runs at a time. This -- not
        -- the per-slot _openInProgress guard -- is what stops two overlapping
        -- passes from double-using a slow container. A payout container's server
        -- lock latency outlasts the per-slot guard's 0.5s window, so a second
        -- concurrent chain would read the slot as unlocked and use it again,
        -- stranding it greyed. Only one chain ever exists now.
        local _openBusy = false
        local _scanScheduled = false
        -- Cycle generation: bumped when a new cycle starts AND on disable.
        -- Every deferred closure (step timers, the 0.5s open recheck, finish)
        -- captures its own generation and self-aborts when stale. IsEnabled()
        -- alone is not enough: a disable->re-enable inside the 0.5s recheck
        -- window would otherwise resurrect the abandoned chain alongside a
        -- freshly-started one -- two concurrent chains, the exact double-use
        -- bug the single-flight design exists to prevent.
        local _cycleGen = 0
        -- A scan request arrived while a cycle was busy; finish() honors it
        -- even when its own cycle made no progress.
        local _missedScan = false
        -- Forward-declared: scanFrame's OnUpdate (created below) calls ScanAndOpen
        -- once the cache is built, so both must be upvalues in scope before that
        -- closure is defined. Assigned (not re-declared) further down.
        local ScanAndOpen, RequestScan
        local function SlotKey(bag, slot) return bag * 1000 + slot end
        local function IsEnabled()
            return EllesmereUIDB and EllesmereUIDB.autoOpenContainers == true
        end
        -- A merchant being open turns UseContainerItem into a SELL (Blizzard
        -- routes "use item" to the vendor), so auto-open must pause while any
        -- merchant frame is shown -- otherwise freshly-bought containers get
        -- opened at the vendor, or a non-openable item throws "the merchant
        -- doesn't want that item". Re-checked before every open; the pass
        -- re-runs on MERCHANT_CLOSED.
        local function MerchantOpen()
            return (MerchantFrame and MerchantFrame:IsShown()) and true or false
        end
        -- "Exclude Warbound Containers": true only when the option is on AND
        -- the slot is confirmed warband-bank-eligible. Guarded like the bags
        -- module (C_Bank / ItemLocation / DoesItemExist can all be absent or
        -- invalid; a raw call would error mid-open). On any uncertainty it
        -- returns false so the container opens normally rather than being
        -- silently skipped.
        local function IsWarboundExcluded(bag, slot)
            -- Default ON: the options UI shows this checked when unset
            -- (autoOpenContainersExcludeWarbound ~= false), so the runtime must
            -- treat nil the same way. Only an explicit false disables it -- the
            -- old `not value` test made a never-toggled setting (nil) skip the
            -- exclusion, so warbound containers auto-opened despite the toggle
            -- appearing enabled.
            if not EllesmereUIDB or EllesmereUIDB.autoOpenContainersExcludeWarbound == false then return false end
            if not (C_Bank and C_Bank.IsItemAllowedInBankType and ItemLocation
                and C_Item and C_Item.DoesItemExist) then return false end
            local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
            if not (loc and C_Item.DoesItemExist(loc)) then return false end
            return C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc) and true or false
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
                        -- Full scan complete: the openable cache is warm. Hand off
                        -- to the single open cycle, which re-scans the bags itself.
                        _cacheBuilt = true
                        self:Hide()
                        if ScanAndOpen then ScanAndOpen(false) end
                        return
                    end
                else
                    local info = C_Container.GetContainerItemInfo(_scanBag, _scanSlot)
                    if info and info.itemID then
                        -- Warm the openable cache during the incremental scan so the
                        -- open cycle doesn't tooltip-scan on its hot path.
                        IsOpenableByID(info.itemID, _scanBag, _scanSlot)
                    end
                    _scanSlot = _scanSlot + 1
                    checked = checked + 1
                end
            end
        end)

        -- After cache is built, BAG_UPDATE_DELAYED only checks changed slots
        local containerFrame = CreateFrame("Frame")

        -- Live apply: registers the bag listener and (until the cache exists)
        -- runs the incremental scan; disable unregisters and stops any
        -- in-progress scan. Called at login and from the options toggle, so
        -- enabling mid-session works without a reload.
        EllesmereUI._applyAutoOpenContainers = function()
            if IsEnabled() then
                containerFrame:RegisterEvent("BAG_UPDATE_DELAYED")
                -- Re-run once the vendor closes: BAG_UPDATE_DELAYED from a
                -- purchase fires while the merchant is open (when opens are
                -- suppressed), so without this the just-bought containers would
                -- never open after leaving the vendor.
                containerFrame:RegisterEvent("MERCHANT_CLOSED")
                -- Track loot windows so payout containers (which open one and
                -- linger in the bag) aren't opened over / re-opened while looting.
                containerFrame:RegisterEvent("LOOT_OPENED")
                containerFrame:RegisterEvent("LOOT_CLOSED")
                if not _cacheBuilt then
                    _scanBag = BACKPACK_CONTAINER
                    _scanSlot = 1
                    scanFrame:Show()
                end
            else
                containerFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
                containerFrame:UnregisterEvent("MERCHANT_CLOSED")
                containerFrame:UnregisterEvent("LOOT_OPENED")
                containerFrame:UnregisterEvent("LOOT_CLOSED")
                _lootOpen = false
                _pendingOpen = nil
                _lootSource = nil
                -- Clear single-flight state so a mid-cycle disable can't strand
                -- _openBusy true and block a later re-enable. The generation
                -- bump kills every in-flight timer of the old cycle outright,
                -- so a quick re-enable cannot resurrect an abandoned chain.
                _openBusy = false
                _scanScheduled = false
                _missedScan = false
                _cycleGen = _cycleGen + 1
                scanFrame:Hide()
            end
        end

        -- Initial kick 2s after login (bags need a moment to settle)
        C_Timer.After(2, function()
            if IsEnabled() then EllesmereUI._applyAutoOpenContainers() end
        end)
        -- skipMerchantGate: the MERCHANT_CLOSED re-run fires before Blizzard's
        -- MerchantFrame finishes hiding, so its entry check would still read
        -- "merchant open" and bail. That run skips only THIS gate -- actual
        -- safety comes from the 0.15s pre-open delay plus the per-step
        -- MerchantOpen() re-check (by which time the frame has hidden, or a
        -- genuinely re-opened merchant correctly aborts).
        --
        -- Single-flight open cycle: builds the candidate list, then opens one
        -- container at a time. When the pass is exhausted it re-scans once IF
        -- anything progressed -- that subsumes nested containers (a bag yielding
        -- more bags) and lingering payout containers without ever running a
        -- second concurrent chain. _openBusy guards the whole cycle.
        ScanAndOpen = function(skipMerchantGate)
            if not _cacheBuilt then return end
            if not IsEnabled() then return end
            if InCombatLockdown() then return end
            if not skipMerchantGate and MerchantOpen() then return end
            -- A loot window is up (payout container lingering): LOOT_CLOSED
            -- restarts a clean cycle once it has left the bag.
            if _lootOpen then return end
            -- A cycle is already running; its finish() re-scan will pick up
            -- anything this trigger would have started.
            if _openBusy then return end

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

            _openBusy = true
            _cycleGen = _cycleGen + 1
            local myGen = _cycleGen
            local madeProgress = false

            -- The single place _openBusy is cleared. Every step() exit routes
            -- through here so the flag can never leak (a leak would freeze
            -- auto-open until reload). A stale generation must NOT clear the
            -- flag -- it belongs to the newer cycle by then.
            local function finish()
                if myGen ~= _cycleGen then return end
                _openBusy = false
                if (madeProgress or _missedScan) and IsEnabled()
                    and not InCombatLockdown()
                    and not MerchantOpen() and not _lootOpen then
                    _missedScan = false
                    C_Timer.After(0.3, function() ScanAndOpen(false) end)
                end
            end

            local function step(idx)
                if myGen ~= _cycleGen then return end
                if idx > #toOpen then return finish() end
                if not IsEnabled() or InCombatLockdown() or MerchantOpen() then return finish() end
                -- Loot window opened mid-cycle: stop; LOOT_CLOSED restarts cleanly.
                if _lootOpen then return finish() end
                local item = toOpen[idx]
                local key = SlotKey(item.bag, item.slot)
                local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
                -- Never act on a slot mid-action: our own _openInProgress flag
                -- (set synchronously below) or Blizzard's isLocked. Re-using a
                -- container that's still resolving a previous open strands it.
                if info and info.itemID and not info.isLocked and not _openInProgress[key] then
                    if IsWarboundExcluded(item.bag, item.slot) then
                        return step(idx + 1)
                    end
                    if _openableCache[info.itemID] and not _failedItems[info.itemID] then
                        local prevID = info.itemID
                        local prevCount = info.stackCount or 1
                        _openInProgress[key] = true
                        _pendingOpen = { bag = item.bag, slot = item.slot,
                            itemID = prevID, count = prevCount }
                        C_Container.UseContainerItem(item.bag, item.slot)
                        C_Timer.After(0.5, function()
                            -- Always release the slot flag (global bookkeeping),
                            -- but a stale-generation chain goes no further: its
                            -- progress/failure verdicts would race the cycle
                            -- that replaced it.
                            _openInProgress[key] = nil
                            -- The open resolved without spawning a loot window
                            -- (LOOT_OPENED would have claimed it by now): drop
                            -- the attribution so an unrelated later loot window
                            -- (a mob, a chest) can't inherit it.
                            if _pendingOpen and _pendingOpen.bag == item.bag
                                and _pendingOpen.slot == item.slot then
                                _pendingOpen = nil
                            end
                            if myGen ~= _cycleGen then return end
                            local after = C_Container.GetContainerItemInfo(item.bag, item.slot)
                            local progressed = (not after) or after.itemID ~= prevID
                                or (after.stackCount or 1) < prevCount
                            if progressed then
                                madeProgress = true
                            elseif after and after.itemID == prevID and not after.isLocked
                                and not _lootOpen then
                                -- Unchanged, unlocked, no loot window => genuine
                                -- failure. A still-locked slot is in-flight (slow
                                -- container), not failed, so it isn't cached -- a
                                -- later cycle retries it.
                                _failedItems[prevID] = true
                            end
                            step(idx + 1)
                        end)
                        return
                    end
                end
                C_Timer.After(0.1, function() step(idx + 1) end)
            end

            C_Timer.After(0.15, function() step(1) end)
        end

        -- Coalesce a burst of BAG_UPDATE_DELAYED (a single open fires several)
        -- into one next-frame scan; skips entirely while a cycle is in flight.
        RequestScan = function()
            -- Dropped because a cycle is mid-flight: remember it so finish()
            -- reruns the scan even when its own cycle made no progress.
            if _openBusy then _missedScan = true; return end
            if _scanScheduled then return end
            _scanScheduled = true
            C_Timer.After(0, function()
                _scanScheduled = false
                ScanAndOpen(false)
            end)
        end

        containerFrame:SetScript("OnEvent", function(_, event)
            if event == "LOOT_OPENED" then
                _lootOpen = true
                -- Claim the window for the container we just used (if any) so
                -- the LOOT_CLOSED verdict knows which slot to re-examine.
                _lootSource = _pendingOpen
                _pendingOpen = nil
                return
            end
            if event == "LOOT_CLOSED" then
                _lootOpen = false
                -- Resume opens that were deferred while the window was up. Delay
                -- so the looted container has left the bag before we re-scan.
                C_Timer.After(0.5, function()
                    -- Verdict on the container whose open spawned that window:
                    -- still in its slot with an un-decremented count means the
                    -- loot could not be taken (bags full / unique item cap).
                    -- Skip it for the session BEFORE the re-scan below, or the
                    -- re-scan re-opens it and the window loops forever. A
                    -- locked slot is still resolving server-side and gets no
                    -- verdict -- the next window re-attributes it.
                    local src = _lootSource
                    _lootSource = nil
                    if src then
                        local now = C_Container.GetContainerItemInfo(src.bag, src.slot)
                        if now and now.itemID == src.itemID and not now.isLocked
                            and (now.stackCount or 1) >= src.count then
                            _failedItems[src.itemID] = true
                        end
                    end
                    ScanAndOpen(false)
                end)
                return
            end
            if event == "BAG_UPDATE_DELAYED" then
                RequestScan()
                return
            end
            -- MERCHANT_CLOSED: the interaction is over but the frame may not
            -- have hidden yet -- skip the entry gate (see ScanAndOpen note)
            -- instead of settling on a timer.
            ScanAndOpen(event == "MERCHANT_CLOSED")
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
                -- Descending: if a purchase removes its entry and reindexes
                -- the list, only higher (already visited) indices shift, so
                -- no still-trainable skill is skipped.
                for i = GetNumTrainerServices(), 1, -1 do
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
    -- Auto-repair cost string. Coin icons (opt-in via the Auto Repair cog) use
    -- the game's own localized coin textures; the default short text builds
    -- "12o 34a" from localized suffixes (EllesmereUI.L translates g/s -> o/a in
    -- frFR; copper "c" falls through untranslated).
    local function RepairCostString(cost)
        if EllesmereUIDB and EllesmereUIDB.repairCoinIcons then
            return C_CurrencyInfo.GetCoinTextureString(cost)
        end
        local g = floor(cost / 10000)
        local s = floor((cost % 10000) / 100)
        local c = cost % 100
        local out = ""
        if g > 0 then out = g .. EllesmereUI.L("g") end
        if s > 0 then out = out .. (out ~= "" and " " or "") .. s .. EllesmereUI.L("s") end
        if c > 0 then out = out .. (out ~= "" and " " or "") .. c .. EllesmereUI.L("c") end
        if out == "" then out = "0" .. EllesmereUI.L("c") end
        return out
    end

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
                        EllesmereUI.Print("|cff0CD29DEllesmereUI:|r |cffff6060" .. EllesmereUI.L("Not enough gold to repair.") .. "|r")
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

                    local src = useGuild and EllesmereUI.L(" (guild bank)") or ""
                    EllesmereUI.Print("|cff0CD29DEllesmereUI:|r " .. EllesmereUI.Lf("Repaired all items for %s", RepairCostString(cost)) .. src)
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    --  Quick Loot
    --  Frame is created lazily on first enable; LOOT_READY registers and
    --  unregisters with the toggle so it applies live and costs zero when off.
    ---------------------------------------------------------------------------
    do
        local lootFrame
        EllesmereUI._applyQuickLoot = function()
            if EllesmereUIDB and EllesmereUIDB.quickLoot then
                if not lootFrame then
                    lootFrame = CreateFrame("Frame")
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
                lootFrame:RegisterEvent("LOOT_READY")
            elseif lootFrame then
                lootFrame:UnregisterEvent("LOOT_READY")
            end
        end
        EllesmereUI._applyQuickLoot()
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
        local installed = false   -- hooks are installed ONCE, on first enable
        local roleFrame           -- classic role-check listener (created on install)

        -- Hooks/listeners are installed only when Quick Signup is turned on, so
        -- nothing touches the LFG execution path unless the feature is in use.
        -- hooksecurefunc/HookScript can't be undone, so the bodies keep their
        -- setting guard for the toggle-off-after-enable case; the role-check
        -- event is registered/unregistered live for true zero cost when off.
        local function InstallQuickSignupHooks()
            if installed then return end
            installed = true

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
            if LFGListApplicationDialog then
                LFGListApplicationDialog:HookScript("OnShow", function(self)
                    if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
                    if self.SignUpButton:IsEnabled() and not IsShiftKeyDown() then
                        self.SignUpButton:Click()
                    end
                end)
            end

            -- Classic Dungeon Finder role check for Quick Signup
            roleFrame = CreateFrame("Frame")
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

        -- Called at load and from the options toggle. Installs the hooks on
        -- first enable; toggles the role-check event registration to match.
        EllesmereUI._applyQuickSignup = function()
            local on = EllesmereUIDB and EllesmereUIDB.quickSignup
            if on then InstallQuickSignupHooks() end
            if roleFrame then
                if on then
                    roleFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
                else
                    roleFrame:UnregisterEvent("LFG_ROLE_CHECK_SHOW")
                end
            end
        end

        EllesmereUI._applyQuickSignup()
    end

    ---------------------------------------------------------------------------
    --  Persistent LFG Signup Note
    ---------------------------------------------------------------------------
    do
        local vanilla = LFGListApplicationDialog_Show
        local patched = false

        local function PatchedShow(self, resultID)
            if resultID then
                self.resultID = resultID
                -- In Midnight the apply-phase search result is SECRET: activityID
                -- can be a secret value and activityIDs is a secret table whose
                -- indexing throws. Guard every read so we degrade to a nil
                -- activityID rather than erroring out the whole sign-up dialog.
                pcall(function()
                    -- Degrade to nil up-front so a mid-read throw cannot leave a
                    -- stale activityID from a previous dialog open.
                    self.activityID = nil
                    local info = C_LFGList.GetSearchResultInfo(resultID)
                    if type(info) ~= "table" then return end
                    local aid = info.activityID
                    if issecretvalue(aid) then aid = nil end
                    if aid == nil and info.activityIDs and not issecretvalue(info.activityIDs) then
                        aid = info.activityIDs[1]
                        if issecretvalue(aid) then aid = nil end
                    end
                    self.activityID = aid
                end)
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

        local resetAnnouncePending = false -- one announce per /reset batch (multi-dungeon reset = multiple system msgs)
        local resetFailPending = false

        local resetAnnounceFrame = CreateFrame("Frame")
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
                if resetAnnouncePending then return end
                resetAnnouncePending = true
                C_Timer.After(0.3, function()
                    resetAnnouncePending = false
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    local customMsg = (EllesmereUIDB.instanceResetAnnounceMsg and
                                       EllesmereUIDB.instanceResetAnnounceMsg ~= "")
                                      and EllesmereUIDB.instanceResetAnnounceMsg
                                      or "Instance has been reset - you can re-enter now!"
                    SendChatMessage("[EUI] " .. customMsg, channel)
                end)
            elseif MatchesAny(msg, FAIL_PATTERNS) then
                if resetFailPending then return end
                resetFailPending = true
                C_Timer.After(0.3, function()
                    resetFailPending = false
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    SendChatMessage("[EUI] Reset failed - there are still players inside the instance.", channel)
                end)
            end
        end)

        -- CHAT_MSG_SYSTEM fires for all system chat, so it is registered only
        -- while the option is on (options toggle re-applies live).
        EllesmereUI._applyInstanceResetAnnounce = function()
            if EllesmereUIDB and EllesmereUIDB.instanceResetAnnounce then
                resetAnnounceFrame:RegisterEvent("CHAT_MSG_SYSTEM")
            else
                resetAnnounceFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
            end
        end
        EllesmereUI._applyInstanceResetAnnounce()
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

    -- Secret-safe percent text: stat getters can return secret numbers in
    -- restricted content, and string.format errors on a secret value.
    local function PctText(v)
        if v == nil or issecretvalue(v) then return "?" end
        return format("%.2f%%", v)
    end

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
        local c = EllesmereUI.QoLExtrasGet("secondaryStatsColor")
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
        -- Arithmetic on a secret errors; show the rating alone in that case
        local vers
        if issecretvalue(versRating) or issecretvalue(versBase) then
            vers = versRating
        else
            vers = versRating + versBase
        end

        local txt =
            format("|cff%s%s:|r  |cffffffff%s|r", labelHex, EllesmereUI.L("Crit"), PctText(crit)) .. "\n" ..
            format("|cff%s%s:|r  |cffffffff%s|r", labelHex, EllesmereUI.L("Haste"), PctText(haste)) .. "\n" ..
            format("|cff%s%s:|r  |cffffffff%s|r", labelHex, EllesmereUI.L("Mastery"), PctText(mastery)) .. "\n" ..
            format("|cff%s%s:|r  |cffffffff%s|r", labelHex, EllesmereUI.L("Vers"), PctText(vers))

        if EllesmereUI.QoLExtrasGet("showTertiaryStats") then
            local tc = EllesmereUI.QoLExtrasGet("tertiaryStatsColor")
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
                format("|cff%s%s:|r  |cffffffff%s|r", tertHex, EllesmereUI.L("Leech"), PctText(leech)) .. "\n" ..
                format("|cff%s%s:|r  |cffffffff%s|r", tertHex, EllesmereUI.L("Avoidance"), PctText(avoidance)) .. "\n" ..
                format("|cff%s%s:|r  |cffffffff%s|r", tertHex, EllesmereUI.L("Speed"), PctText(speed))
        end

        statsText:SetText(txt)
    end

    local function ApplySecondaryStats()
        local enabled = EllesmereUI.QoLExtrasGet("showSecondaryStats")
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
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(statsText, EllesmereUI.GetFontUseShadow("extras")) end
            statsText:SetFont(font, 12, EllesmereUI.GetFontOutlineFlag("extras"))
        end
        local pos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
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
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(statsText, EllesmereUI.GetFontUseShadow("extras")) end
            statsText:SetFont(font, fontSize, EllesmereUI.GetFontOutlineFlag("extras"))
        end
        -- Unit-scoped events filter at the engine (player only); in a raid a
        -- plain RegisterEvent would deliver every member's stat changes.
        for _, ev in ipairs({
            "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER",
            "UNIT_SPELL_HASTE",
        }) do
            statsFrame:RegisterUnitEvent(ev, "player")
        end
        for _, ev in ipairs({
            "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
            "MASTERY_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
            "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD",
        }) do
            statsFrame:RegisterEvent(ev)
        end
        local _statsPending = false
        -- No runtime unit filter needed: the unit events are engine-filtered
        -- to the player above (the old `unit ~= "player"` check also wrongly
        -- swallowed PLAYER_EQUIPMENT_CHANGED, whose first arg is a slot id).
        statsFrame:SetScript("OnEvent", function()
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
        local FONT_SIZE = EllesmereUI.QoLExtrasGet("fpsTextSize") or 12
        local LABEL_SIZE = FONT_SIZE - 2
        fpsFrame = CreateFrame("Frame", "EUI_FPSCounter", UIParent)
        fpsFrame:SetSize(60, 20)
        fpsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
        fpsFrame:SetFrameStrata("MEDIUM")
        fpsFrame:SetFrameLevel(10)
        fpsFrame:EnableMouse(false)

        local function MakeFS(size)
            local f = fpsFrame:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(f, EllesmereUI.GetFontUseShadow("extras")) end
            f:SetFont(FONT, size, EllesmereUI.GetFontOutlineFlag("extras"))
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
        fpsFrame._lblWorld = fsWorldLbl

        local divLocal = MakeDivider()
        local fsLocalVal = MakeFS(FONT_SIZE)
        local fsLocalLbl = MakeFS(LABEL_SIZE)
        fpsFrame._divLocal = divLocal
        fpsFrame._textLocal = fsLocalVal
        fpsFrame._lblLocal = fsLocalLbl

        local function UpdateFPS(self)
            local c = EllesmereUI.QoLExtrasGet("fpsColor")
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

            local showWorld = EllesmereUI.QoLExtrasGet("fpsShowWorldMS")
            local _localMS = EllesmereUI.QoLExtrasGet("fpsShowLocalMS")
            local showLocal = (_localMS == nil) and true or _localMS
            local hideLabel = EllesmereUI.QoLExtrasGet("fpsHideLabel")
            local _, _, latHome, latWorld = GetNetStats()

            fsFps:ClearAllPoints()
            fsFps:SetPoint("LEFT", fpsFrame, "LEFT", 0, 0)
            local anchor = fsFps

            if showWorld then
                fsWorldVal:SetText(latWorld .. " ms")
                divWorld:ClearAllPoints()
                divWorld:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divWorld:Show()
                fsWorldVal:ClearAllPoints()
                fsWorldVal:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                fsWorldVal:Show()
                if hideLabel then
                    fsWorldLbl:Hide()
                    anchor = fsWorldVal
                else
                    fsWorldLbl:SetText("(world)")
                    fsWorldLbl:ClearAllPoints()
                    fsWorldLbl:SetPoint("LEFT", fsWorldVal, "RIGHT", 3, 0)
                    fsWorldLbl:Show()
                    anchor = fsWorldLbl
                end
            else
                divWorld:Hide(); fsWorldVal:Hide(); fsWorldLbl:Hide()
            end

            if showLocal then
                fsLocalVal:SetText(latHome .. " ms")
                divLocal:ClearAllPoints()
                divLocal:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divLocal:Show()
                fsLocalVal:ClearAllPoints()
                fsLocalVal:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                fsLocalVal:Show()
                if hideLabel then
                    fsLocalLbl:Hide()
                    anchor = fsLocalVal
                else
                    fsLocalLbl:SetText("(local)")
                    fsLocalLbl:ClearAllPoints()
                    fsLocalLbl:SetPoint("LEFT", fsLocalVal, "RIGHT", 3, 0)
                    fsLocalLbl:Show()
                    anchor = fsLocalLbl
                end
            else
                divLocal:Hide(); fsLocalVal:Hide(); fsLocalLbl:Hide()
            end

            local totalW = fsFps:GetStringWidth()
            if showWorld then
                totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsWorldVal:GetStringWidth()
                if not hideLabel then totalW = totalW + 3 + fsWorldLbl:GetStringWidth() end
            end
            if showLocal then
                totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsLocalVal:GetStringWidth()
                if not hideLabel then totalW = totalW + 3 + fsLocalLbl:GetStringWidth() end
            end
            self:SetSize(totalW + 4, 20)
        end

        local elapsed = 0
        fpsFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < (self._interval or 3) then return end
            elapsed = 0
            UpdateFPS(self)
        end)
        fpsFrame._updateNow = function() elapsed = 0; UpdateFPS(fpsFrame) end
        fpsFrame:Hide()
    end

    EllesmereUI._applyFPSCounter = function()
        local shouldShow = EllesmereUI.QoLExtrasGet("showFPS")
        if shouldShow then
            CreateFPSCounter()
            fpsFrame._interval = EllesmereUI.QoLExtrasGet("fpsUpdateInterval") or 3
            local sz = EllesmereUI.QoLExtrasGet("fpsTextSize") or 12
            local lblSz = sz - 2
            local fp = EllesmereUI.GetFontPath("extras")
            local outF = EllesmereUI.GetFontOutlineFlag("extras")
            if fpsFrame._text then fpsFrame._text:SetFont(fp, sz, outF) end
            if fpsFrame._textWorld then fpsFrame._textWorld:SetFont(fp, sz, outF) end
            if fpsFrame._textLocal then fpsFrame._textLocal:SetFont(fp, sz, outF) end
            if fpsFrame._lblWorld then fpsFrame._lblWorld:SetFont(fp, lblSz, outF) end
            if fpsFrame._lblLocal then fpsFrame._lblLocal:SetFont(fp, lblSz, outF) end
            local pos = EllesmereUI.QoLExtrasGet("fpsPos")
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
                    if not point then return end
                    EllesmereUI.QoLExtrasSet("fpsPos", { point = point, relPoint = relPoint, x = x, y = y })
                    if fpsFrame and not EllesmereUI._unlockActive then
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPos = function()
                    return EllesmereUI.QoLExtrasGet("fpsPos")
                end,
                clearPos = function()
                    EllesmereUI.QoLExtrasSet("fpsPos", nil)
                end,
                applyPos = function()
                    if not fpsFrame then return end
                    local pos = EllesmereUI.QoLExtrasGet("fpsPos")
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
                    if not point then return end
                    -- Scale lives in this same table; carry it over so a drag doesn't wipe it.
                    local prev = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                    EllesmereUI.QoLExtrasSet("secondaryStatsPos", { point = point, relPoint = relPoint, x = x, y = y, scale = prev and prev.scale })
                    if not EllesmereUI._unlockActive then
                        local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                        if f then
                            f:ClearAllPoints()
                            f:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                        end
                    end
                end,
                loadPos = function()
                    return EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                end,
                clearPos = function()
                    EllesmereUI.QoLExtrasSet("secondaryStatsPos", nil)
                end,
                applyPos = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if not f then return end
                    local pos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
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
        EllesmereUI.QoLExtrasSet("showFPS", not EllesmereUI.QoLExtrasGet("showFPS"))
        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
    end)

    C_Timer.After(1, function()
        if EllesmereUI.QoLExtrasGet("showFPS") then
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

    -- Events registered only while the warning is enabled; the options toggle
    -- re-syncs live so re-enabling mid-session works without a reload. On
    -- enable, one immediate check surfaces an already-low item.
    EllesmereUI._syncDurWarnEvents = function()
        if EllesmereUIDB and EllesmereUIDB.repairWarning == false then
            repairWarnFrame:UnregisterAllEvents()
            if durWarnOverlay then durWarnOverlay:Hide() end
        else
            repairWarnFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            repairWarnFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            repairWarnFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            repairWarnFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            CheckDurabilityAndShow()
        end
    end
    EllesmereUI._syncDurWarnEvents()
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

    -- Crosshair settings: the account-wide EllesmereUIDB root is the inherited
    -- global default (preserved, never cleared); the QoL per-profile DB holds
    -- per-profile settings. Existing users keep their current crosshair until a
    -- profile overrides it.
    -- CrosshairDB() is nil until the Cursor module creates it.
    local function CrosshairDB()
        return _G._ECL_AceDB and _G._ECL_AceDB.profile
    end
    EllesmereUI.GetCrosshairDB = CrosshairDB

    -- Effective read: profile override -> global root -> nil (inline default).
    local function CrosshairGet(k)
        local p = CrosshairDB()
        if p and p[k] ~= nil then return p[k] end
        return EllesmereUIDB and EllesmereUIDB[k]
    end
    EllesmereUI.GetCrosshairValue = CrosshairGet

    -- Item-based range detection for all specs
    local checkItems = {
        { range = 5,   id = 37727 }, -- Ruby Acorn
        { range = 8,   id = 34368 }, -- Attuned Crystal Cores
        { range = 10,  id = 10699 }, -- Handful of Snowflakes
        { range = 15,  id = 31129 }, -- Blackwhelp Net
        { range = 20,  id = 21519 }, -- Mistletoe
        { range = 25,  id = 13289 }, -- Egan's Blaster
        { range = 30,  id = 17202 }, -- Snowball
        { range = 35,  id = 18904 }, -- Zorbin's Ultra-Shrinker
        { range = 40,  ids = { 18640, 28767 } }, -- Happy Fun Rock / The Decapitator (either works)
        { range = 45,  id = 32698 }, -- Wrangling Rope
        { range = 60,  id = 32825 }, -- Soul Cannon
        { range = 80,  id = 35278 }, -- Reinforced Net
    }

    local DRUID_MELEE_FORMS = { [1] = true, [2] = true }  -- Bear, Cat

    local _, _chPlayerClass = UnitClass("player")
    local _crosshairCutoffRange = 5

    -- Spell probes: the player's own top-range harmful spells, used as the
    -- PRIMARY range test for ranged cutoffs. Probing real spellbook spells is
    -- ground truth -- range-extension talents are included automatically
    -- (reported: priest with extended range stayed "out of range" at the
    -- hardcoded 40). The item ladder below remains as the fallback whenever
    -- no probe answers (ground-targeted spells return nil, early login, or a
    -- spec whose book yields no candidates), so behavior can never be worse
    -- than before. Melee cutoffs (5) never probe: today's behavior preserved.
    local _crosshairProbes = {}

    local function RefreshCrosshairProbeSpells()
        wipe(_crosshairProbes)
        local cutoff = _crosshairCutoffRange
        if cutoff <= 5 then return end
        if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
                and C_Spell and C_Spell.IsSpellHarmful and C_Spell.GetSpellInfo) then
            return
        end
        local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        if not bank then return end
        -- Candidate window: at least the spec's baseline reach, at most a
        -- talent-extension envelope above it (keeps outlier long-range utility
        -- spells from widening the crosshair beyond the spec's real kit).
        local maxWindow = cutoff + 10
        local found = {}
        local numTabs = C_SpellBook.GetNumSpellBookSkillLines() or 0
        for tab = 1, numTabs do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
            if lineInfo and not (lineInfo.offSpecID and lineInfo.offSpecID ~= 0)
               and not lineInfo.shouldHide then
                local offset = lineInfo.itemIndexOffset or 0
                local count = lineInfo.numSpellBookItems or 0
                for si = offset + 1, offset + count do
                    local spellType, actionId, spellId = C_SpellBook.GetSpellBookItemType(si, bank)
                    if spellType == Enum.SpellBookItemType.Spell then
                        local sid = spellId or actionId
                        if sid and not (C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(sid))
                           and C_Spell.IsSpellHarmful(sid) then
                            local info = C_Spell.GetSpellInfo(sid)
                            local mr = info and info.maxRange
                            if mr and mr >= cutoff and mr <= maxWindow then
                                found[#found + 1] = { sid = sid, range = mr }
                            end
                        end
                    end
                end
            end
        end
        table.sort(found, function(a, b) return a.range > b.range end)
        for i = 1, math.min(4, #found) do
            _crosshairProbes[i] = found[i].sid
        end
    end

    local function RefreshCrosshairCutoffRange()
        local _, classFile = UnitClass("player")
        local specIndex = GetSpecialization()
        if not specIndex then
            _crosshairCutoffRange = 5
            return
        end
        
        local specID = GetSpecializationInfo(specIndex)
        if not specID then
            _crosshairCutoffRange = 5
            return
        end
        
        if classFile == "DRUID" then
            if specID == 102 or specID == 105 then -- Balance, Restoration
                if IsPlayerSpell(197488) then -- Astral Influence
                    _crosshairCutoffRange = 45
                else
                    _crosshairCutoffRange = 40
                end
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "DEMONHUNTER" then
            if specIndex == 3 or (specID ~= 577 and specID ~= 581) then
                _crosshairCutoffRange = 25 -- Devourer
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "EVOKER" then
            if specID == 1467 or specID == 1470 then -- Devastation, Augmentation
                _crosshairCutoffRange = 25
            elseif specID == 1468 then -- Preservation
                _crosshairCutoffRange = 30
            else
                _crosshairCutoffRange = 25
            end
        elseif classFile == "HUNTER" then
            if specID == 253 or specID == 254 then -- Beast Mastery, Marksmanship
                _crosshairCutoffRange = 40
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "PALADIN" then
            if specID == 65 then -- Holy
                -- Holy is a 40yd healer by default; opt into melee (5yd) via the
                -- "Show Melee Range for Hpal" crosshair toggle.
                if CrosshairGet("crosshairHpalMelee") then
                    _crosshairCutoffRange = 5
                else
                    _crosshairCutoffRange = 40
                end
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "SHAMAN" then
            if specID == 263 then -- Enhancement
                _crosshairCutoffRange = 5
            else
                _crosshairCutoffRange = 40
            end
        elseif classFile == "MONK" then
            if specID == 270 then -- Mistweaver
                _crosshairCutoffRange = 40
            else
                _crosshairCutoffRange = 5
            end
        elseif classFile == "PRIEST" or classFile == "MAGE" or classFile == "WARLOCK" then
            _crosshairCutoffRange = 40
        else -- WARRIOR, ROGUE, DEATHKNIGHT
            _crosshairCutoffRange = 5
        end
        -- Rebuild the spell probes for the (possibly new) cutoff. Runs on the
        -- same cadence as the cutoff itself: login, spec change, talent change
        -- (TRAIT_CONFIG_UPDATED -- exactly when range talents flip), and the
        -- options toggle. The early returns above leave a stale list, but the
        -- check-time gate (effective cutoff > 5) never consults it then.
        RefreshCrosshairProbeSpells()
    end
    RefreshCrosshairCutoffRange()
    -- Exposed so the crosshair options toggle can re-resolve the cutoff live.
    EllesmereUI._RefreshCrosshairCutoffRange = RefreshCrosshairCutoffRange

    EllesmereUI._getCrosshairCutoffRange = function()
        if _chPlayerClass == "DRUID" and DRUID_MELEE_FORMS[GetShapeshiftForm()] then
            return 5
        end
        return _crosshairCutoffRange
    end

    -- True only when there is an attackable, living target out of range.
    local function TargetOutOfRange()
        if not (UnitExists("target") and UnitCanAttack("player", "target")
                and not UnitIsDead("target")) then
            return false
        end
        local cutoff = EllesmereUI._getCrosshairCutoffRange()

        -- PRIMARY: probe the player's own top-range harmful spells -- exact,
        -- and talented range extensions are reflected automatically. A nil
        -- answer (spell can't unit-target right now) cascades to the next
        -- probe, then to the item ladder below. Melee cutoffs (5, including
        -- druid melee forms via the effective getter) skip straight to the
        -- ladder -- unchanged behavior.
        if cutoff > 5 and _crosshairProbes[1] and C_Spell and C_Spell.IsSpellInRange then
            local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
            for i = 1, #_crosshairProbes do
                local sid = _crosshairProbes[i]
                local live = (FindOvr and FindOvr(sid)) or sid
                local r = C_Spell.IsSpellInRange(live, "target")
                if r ~= nil then return r == false end
            end
        end

        local maxRange = nil
        for _, item in ipairs(checkItems) do
            local inRange
            if item.ids then
                -- Either item satisfies the check: one may be invalid/removed on
                -- some clients, so try each and take an in-range result.
                for _, iid in ipairs(item.ids) do
                    if C_Item.IsItemInRange(iid, "target") == true then inRange = true; break end
                end
            else
                inRange = C_Item.IsItemInRange(item.id, "target")
            end
            if inRange == true then
                maxRange = item.range
                break
            end
            if item.range >= cutoff then
                break
            end
        end
        
        return (maxRange == nil) or (maxRange > cutoff)
    end

    local function CreateCrosshair()
        if crosshairFrame then return end
        crosshairFrame = CreateFrame("Frame", "EUI_CharacterCrosshair", UIParent)
        -- MEDIUM sits above gameplay HUD but below DIALOG/HIGH panels (talents, character, etc.).
        crosshairFrame:SetFrameStrata("MEDIUM")
        crosshairFrame:SetFrameLevel(100)
        crosshairFrame:EnableMouse(false)
        crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        crosshairFrame:SetSize(1, 1)

        local function MakeArm(layer)
            local t = crosshairFrame:CreateTexture(nil, layer or "OVERLAY")
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            return t
        end
        -- Borders sit on artwork so the overlay arms render on top of them.
        crosshairFrame._hBorder = MakeArm("ARTWORK")
        crosshairFrame._vBorder = MakeArm("ARTWORK")
        crosshairFrame._hBar = MakeArm("OVERLAY")
        crosshairFrame._vBar = MakeArm("OVERLAY")

        -- Throttled recolor when the target is out of melee range. No-ops unless
        -- the feature is enabled and the class has a mapped melee spell.
        local meleeAccum = 0
        crosshairFrame:SetScript("OnUpdate", function(self, elapsed)
            meleeAccum = meleeAccum + elapsed
            if meleeAccum < 0.15 then return end
            meleeAccum = 0
            local nc = self._normalColor
            if not nc then return end
            if not CrosshairGet("crosshairMeleeColorEnabled") then
                if self._meleeActive then
                    self._meleeActive = false
                    self._hBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                    self._vBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                end
                return
            end
            local outOfRange = TargetOutOfRange()
            if outOfRange ~= self._meleeActive then
                self._meleeActive = outOfRange
                local c = outOfRange and (CrosshairGet("crosshairMeleeColor") or { r = 1, g = 0, b = 0, a = 1 }) or nc
                self._hBar:SetColorTexture(c.r or 1, c.g or 0, c.b or 0, c.a or 1)
                self._vBar:SetColorTexture(c.r or 1, c.g or 0, c.b or 0, c.a or 1)
            end
        end)
    end

    -- Hardcoded presets (the original look): thickness + total arm length. The
    -- options dropdown stamps these onto the H/V Width/Length values, and they
    -- are the fallback here when those values are unset. Cog sliders fine-tune.
    EllesmereUI.CROSSHAIR_PRESETS = {
        Thin   = { width = 1, length = 40 },
        Normal = { width = 2, length = 40 },
        Thick  = { width = 3, length = 40 },
    }

    -- Re-evaluates visibility on combat / zone transitions and refreshes the
    -- cached melee spell on spec changes. Events are registered only while the
    -- crosshair is enabled: with the size set to "None" nothing fires here.
    -- On the off->on transition the cutoff range is re-read directly to catch
    -- spec changes that happened while unregistered.
    local visWatch = CreateFrame("Frame")
    local visWatchRegistered = false
    visWatch:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "TRAIT_CONFIG_UPDATED" then
            RefreshCrosshairCutoffRange()
        end
        -- _applyCrosshair self-guards: nil DB -> returns, "None" -> hides,
        -- and runs the one-time migration once the profile DB is ready.
        if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
    end)
    local function SyncVisWatch(want)
        if want == visWatchRegistered then return end
        visWatchRegistered = want
        if want then
            visWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
            visWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
            visWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
            visWatch:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            visWatch:RegisterEvent("TRAIT_CONFIG_UPDATED")
            RefreshCrosshairCutoffRange()
        else
            visWatch:UnregisterAllEvents()
        end
    end

    EllesmereUI._applyCrosshair = function()
        local PP = EllesmereUI.PP
        -- Effective reads (profile override -> global root -> inline default)
        local G = CrosshairGet
        local size = G("crosshairSize") or "None"
        if size == "None" then
            SyncVisWatch(false)
            if crosshairFrame then crosshairFrame:Hide() end
            return
        end
        SyncVisWatch(true)

        CreateCrosshair()

        local c = G("crosshairColor")
        local cr = c and c.r or 1
        local cg = c and c.g or 1
        local cb = c and c.b or 1
        local ca = c and c.a or 0.75

        -- Preset gives the baseline width/length, sliders override per axis.
        local preset = EllesmereUI.CROSSHAIR_PRESETS[size] or EllesmereUI.CROSSHAIR_PRESETS.Normal
        local hWidth = G("crosshairHWidth") or preset.width
        local vWidth = G("crosshairVWidth") or preset.width
        local hLen   = G("crosshairHLength") or preset.length
        local vLen   = G("crosshairVLength") or preset.length
        local xOff   = G("crosshairXOffset") or 0
        local yOff   = G("crosshairYOffset") or 0
        local bSize  = G("crosshairBorderSize") or 0
        local bc     = G("crosshairBorderColor") or { r = 0, g = 0, b = 0, a = 1 }

        -- (0,0) = screen center
        crosshairFrame:ClearAllPoints()
        crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", xOff, yOff)

        local hBar, vBar = crosshairFrame._hBar, crosshairFrame._vBar
        local hBorder, vBorder = crosshairFrame._hBorder, crosshairFrame._vBorder

        hBar:ClearAllPoints()
        hBar:SetSize(PP.Scale(hLen), PP.Scale(hWidth))
        hBar:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
        hBar:SetColorTexture(cr, cg, cb, ca)

        vBar:ClearAllPoints()
        vBar:SetSize(PP.Scale(vWidth), PP.Scale(vLen))
        vBar:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
        vBar:SetColorTexture(cr, cg, cb, ca)

        -- Base colour for the out-of-melee-range recolor, reset the melee state
        -- so the OnUpdate re-applies the range colour next tick if still needed.
        crosshairFrame._normalColor = { r = cr, g = cg, b = cb, a = ca }
        crosshairFrame._meleeActive = false

        -- Pixel border: a slightly larger bar of border colour behind each arm.
        if bSize and bSize > 0 then
            local bp = PP.Scale(bSize)
            local br, bg, bb, ba = bc.r or 0, bc.g or 0, bc.b or 0, bc.a or 1
            hBorder:ClearAllPoints()
            hBorder:SetSize(PP.Scale(hLen) + bp * 2, PP.Scale(hWidth) + bp * 2)
            hBorder:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
            hBorder:SetColorTexture(br, bg, bb, ba)
            hBorder:Show()
            vBorder:ClearAllPoints()
            vBorder:SetSize(PP.Scale(vWidth) + bp * 2, PP.Scale(vLen) + bp * 2)
            vBorder:SetPoint("CENTER", crosshairFrame, "CENTER", 0, 0)
            vBorder:SetColorTexture(br, bg, bb, ba)
            vBorder:Show()
        else
            hBorder:Hide()
            vBorder:Hide()
        end

        -- Visibility: always / combat / instances / instances_combat (both).
        local vis = G("crosshairVisibility") or "always"
        local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
        local show = true
        if vis == "combat" then
            show = inCombat
        elseif vis == "instances" then
            show = IsInInstance()
        elseif vis == "instances_combat" then
            show = IsInInstance() and inCombat
        end
        if show then crosshairFrame:Show() else crosshairFrame:Hide() end
    end

    C_Timer.After(1, function()
        if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
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
            local fp = EllesmereUI.GetFontPath("extras")
            local outF = EllesmereUI.GetFontOutlineFlag("extras")
            local sz = (EllesmereUIDB and EllesmereUIDB.mapCoordsTextSize) or 12

            local divider = coordFrame:CreateTexture(nil, "OVERLAY")
            divider:SetColorTexture(1, 1, 1, 0.9)
            PP.Size(divider, 2, sz)
            divider:SetPoint("BOTTOM", coordFrame, "BOTTOM", 0, 0)

            local useShadow = EllesmereUI.GetFontUseShadow("extras")

            local cursorFS = coordFrame:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(cursorFS, useShadow) end
            cursorFS:SetFont(fp, sz, outF)
            cursorFS:SetTextColor(1, 1, 1, 0.9)
            cursorFS:SetJustifyH("RIGHT")
            cursorFS:SetPoint("RIGHT", divider, "LEFT", -10, 0)

            local playerFS = coordFrame:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(playerFS, useShadow) end
            playerFS:SetFont(fp, sz, outF)
            playerFS:SetTextColor(1, 1, 1, 0.9)
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
                    local fp = EllesmereUI.GetFontPath("extras")
                    local outF = EllesmereUI.GetFontOutlineFlag("extras")
                    local useShadow = EllesmereUI.GetFontUseShadow("extras")
                    local sz = (EllesmereUIDB and EllesmereUIDB.mapCoordsTextSize) or 12
                    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(coordText.cursor, useShadow) end
                    coordText.cursor:SetFont(fp, sz, outF)
                    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(coordText.player, useShadow) end
                    coordText.player:SetFont(fp, sz, outF)
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

-------------------------------------------------------------------------------
--  Hide Error Messages
--  Swallows the red UIErrorsFrame spam (e.g. "Not enough rage", "Ability is
--  not ready yet") while keeping a short whitelist of genuinely useful errors
--  visible. The OnEvent override is only installed while the option is on, so
--  it costs nothing for anyone who leaves it off.
-------------------------------------------------------------------------------
do
    local origOnEvent
    local installed = false

    -- Errors worth keeping even while the rest are hidden. Built lazily so we
    -- only touch the ERR_* globals when someone actually enables the feature.
    local keep
    local function BuildKeepList()
        if keep then return end
        keep = {}
        for _, msg in ipairs({
            ERR_INV_FULL, ERR_QUEST_LOG_FULL, ERR_RAID_GROUP_ONLY,
            ERR_PARTY_LFG_BOOT_LIMIT, ERR_PARTY_LFG_BOOT_DUNGEON_COMPLETE,
            ERR_PARTY_LFG_BOOT_IN_COMBAT, ERR_PARTY_LFG_BOOT_IN_PROGRESS,
            ERR_PARTY_LFG_BOOT_LOOT_ROLLS, ERR_PARTY_LFG_TELEPORT_IN_COMBAT,
            ERR_PET_SPELL_DEAD, ERR_PLAYER_DEAD,
            SPELL_FAILED_TARGET_NO_POCKETS, ERR_ALREADY_PICKPOCKETED,
        }) do
            if msg then keep[msg] = true end
        end
    end

    -- The group-kick "not eligible" line is a format string, so it needs a
    -- pattern match rather than a plain equality check.
    local function IsBootNotEligible(err)
        if type(err) ~= "string" or not ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S then return false end
        local ok, found = pcall(function()
            return err:find(string.format(ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S, ".+"))
        end)
        return (ok and found) and true or false
    end

    local function FilteredOnEvent(self, event, id, err, ...)
        if event == "UI_ERROR_MESSAGE" then
            if keep[err] or IsBootNotEligible(err) then
                return origOnEvent(self, event, id, err, ...)
            end
            return
        end
        return origOnEvent(self, event, id, err, ...)
    end

    local function ApplyHideErrorMessages()
        local on = EllesmereUIDB and EllesmereUIDB.hideErrorMessages
        if on and not installed then
            BuildKeepList()
            origOnEvent = UIErrorsFrame:GetScript("OnEvent")
            UIErrorsFrame:SetScript("OnEvent", FilteredOnEvent)
            UIParent:UnregisterEvent("PING_SYSTEM_ERROR")
            installed = true
        elseif not on and installed then
            UIErrorsFrame:SetScript("OnEvent", origOnEvent)
            origOnEvent = nil
            UIParent:RegisterEvent("PING_SYSTEM_ERROR")
            installed = false
        end
    end
    EllesmereUI._applyHideErrorMessages = ApplyHideErrorMessages

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if EllesmereUIDB and EllesmereUIDB.hideErrorMessages then
            ApplyHideErrorMessages()
        end
    end)
end

-------------------------------------------------------------------------------
--  Hide Tutorial Pop-ups
-------------------------------------------------------------------------------
do
    local function Enabled()
        return EllesmereUIDB and EllesmereUIDB.hideTutorials
    end

    -- "i" circles are MainHelpPlateButtons, matched by a method copied from the
    -- Blizzard mixin. Blizzard_HelpPlate is load-on-demand; resolve lazily and
    -- only cache once it exists.
    local fingerprint
    local function GetFingerprint()
        if not fingerprint and MainHelpPlateButtonMixin then
            fingerprint = MainHelpPlateButtonMixin.ShowTooltip
        end
        return fingerprint
    end

    local hiddenByUs = setmetatable({}, { __mode = "k" })
    local function HideButton(btn)
        btn:SetAlpha(0)
        btn:EnableMouse(false)
        hiddenByUs[btn] = true
    end

    -- Hoisted out of the pcall so we reuse one function instead of allocating a
    -- closure on every call (this runs on each panel open + each HelpTip show).
    local function DoHideOpenTips()
        for tip in HelpTip.framePool:EnumerateActive() do
            if tip:IsShown() then
                local info = tip.info
                if info and info.cvarBitfield and info.bitfieldFlag then
                    SetCVarBitfield(info.cvarBitfield, info.bitfieldFlag, true)
                end
                tip:Hide()
            end
        end
    end
    local function HideOpenTips()
        if not (HelpTip and HelpTip.framePool and HelpTip.framePool.EnumerateActive) then return end
        pcall(DoHideOpenTips)
    end

    local HideButtonsUnder
    local function ScanChildren(...)
        for i = 1, select("#", ...) do
            HideButtonsUnder((select(i, ...)))
        end
    end
    -- Some Blizzard frame trees refuse GetChildren from insecure code with a
    -- usage error (house editor list rows do). This walk runs inside a
    -- ShowUIPanel hooksecurefunc, so an uncaught error propagates into the
    -- panel's caller and aborts the rest of its flow (e.g. the house
    -- editor's OnActiveModeChanged). pcall per node: a refusing frame only
    -- skips its own subtree; siblings still get scanned. ScanFrame is
    -- hoisted so the pcall allocates nothing per node.
    local function ScanFrame(root)
        ScanChildren(root:GetChildren())
    end
    function HideButtonsUnder(root)
        if not root then return end
        local fp = GetFingerprint()
        if not fp then return end
        if root.ShowTooltip == fp then HideButton(root) end
        if root.GetChildren then pcall(ScanFrame, root) end
    end

    -- One-time full walk (no allocation, never on a timer) to catch panels that
    -- are already open the moment the feature is switched on.
    local function SweepAll()
        local fp = GetFingerprint()
        if not fp then return end
        local frame = EnumerateFrames()
        while frame do
            if frame.ShowTooltip == fp then HideButton(frame) end
            frame = EnumerateFrames(frame)
        end
    end

    local function RestoreButtons()
        for btn in pairs(hiddenByUs) do
            btn:SetAlpha(1)
            btn:EnableMouse(true)
            hiddenByUs[btn] = nil
        end
    end

    -- Core hooks (HelpTip + ShowUIPanel) install once, only via ApplyHideTutorials
    -- when the feature is enabled. Each body also gates on Enabled().
    local coreHooked = false
    local function InstallCoreHooks()
        if coreHooked then return end
        coreHooked = true
        if HelpTip and HelpTip.Show then
            hooksecurefunc(HelpTip, "Show", function()
                if Enabled() then HideOpenTips() end
            end)
        end
        if ShowUIPanel then
            hooksecurefunc("ShowUIPanel", function(frame)
                if Enabled() and frame then
                    HideButtonsUnder(frame)
                    HideOpenTips()
                end
            end)
        end
    end

    local tooltipHooked = false
    local function InstallTooltipHook()
        if tooltipHooked or not HelpPlateTooltip then return end
        tooltipHooked = true
        if HelpPlate and HelpPlate.ShowTutorialTooltip then
            hooksecurefunc(HelpPlate, "ShowTutorialTooltip", function()
                if Enabled() and HelpPlateTooltip then HelpPlateTooltip:Hide() end
            end)
        end
        if HelpPlateTooltip.Init then
            hooksecurefunc(HelpPlateTooltip, "Init", function(self)
                if Enabled() then self:Hide() end
            end)
        end
    end

    local weSetCVar = false
    local function ApplyHideTutorials()
        if Enabled() then
            InstallCoreHooks()
            InstallTooltipHook()
            pcall(SetCVar, "hideHelptips", "1")
            pcall(SetCVar, "showTutorials", "0")
            weSetCVar = true
            SweepAll()
            HideOpenTips()
        else
            if weSetCVar then
                pcall(SetCVar, "hideHelptips", "0")
                pcall(SetCVar, "showTutorials", "1")
                weSetCVar = false
            end
            RestoreButtons()
        end
    end
    EllesmereUI._applyHideTutorials = ApplyHideTutorials

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" then
            -- Gated: nothing is hooked while the feature is off.
            if addon == "Blizzard_HelpPlate" and Enabled() then
                InstallTooltipHook()
            end
            return
        end
        ApplyHideTutorials()  -- PLAYER_LOGIN
    end)
end

-------------------------------------------------------------------------------
--  Group Death Announcer
--  Shows a large center-screen "<name> DIED!" alert when a party or raid
--  member dies. Midnight removed the combat log, so deaths are detected by
--  polling group units for an alive -> dead transition (feign death and the
--  player's own death are excluded). Fully gated: no ticker runs while the
--  option is off or while solo.
-------------------------------------------------------------------------------
do
    local POLL_INTERVAL = 0.35
    local alertOverlay
    local ticker
    local watcher
    local installed = false
    local deadState = {}   -- [guid] = true while dead/ghost, false while alive

    local DEFAULT_TEXT_SIZE = 34

    -- Applies the configured font size and saved position (or the default
    -- center-top placement) to the overlay.
    local function ApplyOverlaySettings()
        if not alertOverlay then return end
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
            or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        -- Always keep an outline so the alert stays readable over any background.
        local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("extras")) or ""
        if not outline:find("OUTLINE") then
            outline = (outline == "") and "OUTLINE" or (outline .. ", OUTLINE")
        end
        local size = (EllesmereUIDB and EllesmereUIDB.groupDeathTextSize) or DEFAULT_TEXT_SIZE
        alertOverlay._text:SetFont(fontPath, size, outline)
        -- Keep the frame (and therefore the unlock-mode mover) compact and sized
        -- to roughly the alert text rather than a fixed wide box.
        alertOverlay:SetSize(size * 7, size + 14)

        alertOverlay:ClearAllPoints()
        local pos = EllesmereUIDB and EllesmereUIDB.groupDeathAlertPos
        if pos and pos.point then
            alertOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        else
            alertOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        end
    end

    local function CreateAlertOverlay()
        if alertOverlay then return end

        alertOverlay = CreateFrame("Frame", nil, UIParent)
        alertOverlay:SetSize(240, 50)
        alertOverlay:SetFrameStrata("HIGH")
        alertOverlay:SetFrameLevel(60)
        alertOverlay:EnableMouse(false)
        alertOverlay:SetMouseClickEnabled(false)

        local fs = alertOverlay:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER")
        alertOverlay._text = fs
        ApplyOverlaySettings()

        -- Quick fade-in, brief hold, fade-out; hide when finished.
        local ag = alertOverlay:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.15); fadeIn:SetOrder(1)
        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.6); hold:SetOrder(2)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.6); fadeOut:SetOrder(3)
        ag:SetScript("OnFinished", function() alertOverlay:Hide() end)
        alertOverlay._ag = ag

        alertOverlay:SetScript("OnHide", function() ag:Stop() end)
        alertOverlay:Hide()
    end

    local function ShowAlert(name, classToken)
        if not name then return end
        CreateAlertOverlay()
        ApplyOverlaySettings()

        local colored = name
        local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if c then
            colored = "|c" .. (c.colorStr or "ffffffff") .. name .. "|r"
        end
        local skull = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"
        alertOverlay._text:SetText(skull .. " " .. colored .. " |cffff2020DIED!|r")

        alertOverlay._ag:Stop()
        alertOverlay:SetAlpha(1)
        alertOverlay:Show()
        alertOverlay._ag:Play()
    end

    -- Configurable death alert sound (default "none"). The cog dropdown lists the
    -- bundled EllesmereUI sounds plus any SharedMedia sounds, mirroring Chat's
    -- "Whisper Sound". Played on the "Master" channel so it stays audible even
    -- when the SFX slider is low. Tables are exposed on EllesmereUI so the options
    -- file can build the same dropdown.
    local _SOUNDS_DIR = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\"
    local GROUP_DEATH_SOUND_PATHS = {
        ["none"]      = nil,
        ["airhorn"]   = _SOUNDS_DIR .. "AirHorn.ogg",
        ["banana"]    = _SOUNDS_DIR .. "BananaPeelSlip.ogg",
        ["bikehorn"]  = _SOUNDS_DIR .. "BikeHorn.ogg",
        ["bite"]      = _SOUNDS_DIR .. "Bite.ogg",
        ["boxing"]    = _SOUNDS_DIR .. "BoxingArenaSound.ogg",
        ["catmeow"]   = _SOUNDS_DIR .. "CatMeow.ogg",
        ["catmeow2"]  = _SOUNDS_DIR .. "CatMeow2.ogg",
        ["gunshot"]   = _SOUNDS_DIR .. "FrontalsGunshot.wav",
        ["glass"]     = _SOUNDS_DIR .. "Glass.mp3",
        ["kaching"]   = _SOUNDS_DIR .. "Kaching.ogg",
        ["phone"]     = _SOUNDS_DIR .. "Phone.ogg",
        ["robotblip"] = _SOUNDS_DIR .. "RobotBlip.ogg",
        ["sonar"]     = _SOUNDS_DIR .. "Sonar.ogg",
        ["siren"]     = _SOUNDS_DIR .. "WarningSiren.ogg",
        ["water"]     = _SOUNDS_DIR .. "WaterDrop.ogg",
        ["wilhelm"]   = _SOUNDS_DIR .. "Wilhelm.ogg",
    }
    local GROUP_DEATH_SOUND_NAMES = {
        ["none"]      = "None",
        ["airhorn"]   = "Air Horn",
        ["banana"]    = "Banana Peel Slip",
        ["bikehorn"]  = "Bike Horn",
        ["bite"]      = "Bite",
        ["boxing"]    = "Boxing Arena",
        ["catmeow"]   = "Cat Meow",
        ["catmeow2"]  = "Cat Meow 2",
        ["gunshot"]   = "Frontals Gunshot",
        ["glass"]     = "Glass",
        ["kaching"]   = "Kaching",
        ["phone"]     = "Phone",
        ["robotblip"] = "Robot Blip",
        ["sonar"]     = "Sonar",
        ["siren"]     = "Warning Siren",
        ["water"]     = "Water Drop",
        ["wilhelm"]   = "Wilhelm",
    }
    local GROUP_DEATH_SOUND_ORDER = {
        "none", "airhorn", "banana", "bikehorn", "bite", "boxing", "catmeow",
        "catmeow2", "gunshot", "glass", "kaching", "phone", "robotblip", "sonar",
        "siren", "water", "wilhelm",
    }
    -- SharedMedia sounds are appended at PLAYER_LOGIN (see the boot frame at the
    -- end of this block), NOT here: this do-block runs at addon load, before
    -- other addons have registered their LibSharedMedia sounds, so an append now
    -- would miss them. (Chat's whisper-sound append runs from its PLAYER_LOGIN
    -- init for the same reason.) The tables are exposed now by reference, so the
    -- login append fills the same tables the options dropdown reads.
    EllesmereUI._groupDeathSoundPaths = GROUP_DEATH_SOUND_PATHS
    EllesmereUI._groupDeathSoundNames = GROUP_DEATH_SOUND_NAMES
    EllesmereUI._groupDeathSoundOrder = GROUP_DEATH_SOUND_ORDER

    local function PlayDeathSound()
        local key = EllesmereUIDB and EllesmereUIDB.groupDeathSoundKey
        if not key or key == "none" then return end
        local path = GROUP_DEATH_SOUND_PATHS[key]
        if path then PlaySoundFile(path, "Master") end
    end

    local function ForEachGroupUnit(fn)
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local u = "raid" .. i
                if UnitExists(u) and not UnitIsUnit(u, "player") then fn(u) end
            end
        elseif IsInGroup() then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) then fn(u) end
            end
        end
    end

    -- Minimum gap between death sounds. On a group wipe many members die within
    -- the same poll (and across consecutive polls), which would otherwise fire
    -- the sound once per corpse and turn into a spammy overlapping mess. The
    -- cooldown collapses a burst of deaths into a single sound. It is only
    -- applied in larger groups (raids, > 5 players); in a party of 5 or fewer
    -- deaths are sparse enough that no throttling is needed.
    local SOUND_COOLDOWN = 3.0
    local COOLDOWN_MIN_GROUP = 5
    local lastSoundTime = 0

    local function TryPlayDeathSound()
        if GetNumGroupMembers() > COOLDOWN_MIN_GROUP then
            local now = GetTime()
            if now - lastSoundTime < SOUND_COOLDOWN then return end
            lastSoundTime = now
        end
        PlayDeathSound()
    end

    local function Poll()
        if not (EllesmereUIDB and EllesmereUIDB.announceGroupDeaths) then return end
        local seen = {}
        local newlyDeadName, newlyDeadClass, newlyDeadCount
        ForEachGroupUnit(function(u)
            local guid = UnitGUID(u)
            if not guid then return end
            seen[guid] = true
            if not UnitIsConnected(u) then return end
            local dead = (UnitIsDeadOrGhost(u) and not UnitIsFeignDeath(u)) and true or false
            -- prev == false means we previously saw this unit alive; a nil prev
            -- (first sighting / just (re)joined) primes the state silently so we
            -- never announce someone who was already dead when we started.
            if deadState[guid] == false and dead then
                local _, classToken = UnitClass(u)
                newlyDeadName = UnitName(u)
                newlyDeadClass = classToken
                newlyDeadCount = (newlyDeadCount or 0) + 1
            end
            deadState[guid] = dead
        end)
        for guid in pairs(deadState) do
            if not seen[guid] then deadState[guid] = nil end
        end
        -- Show a single alert per poll (the overlay is one frame, so multiple
        -- ShowAlert calls would just clobber each other anyway) and play at most
        -- one sound, throttled by the cooldown, no matter how many died.
        if newlyDeadCount then
            ShowAlert(newlyDeadName, newlyDeadClass)
            TryPlayDeathSound()
        end
    end

    local function StartTicker()
        if ticker then return end
        wipe(deadState)
        Poll()  -- prime alive/dead state without announcing
        ticker = C_Timer.NewTicker(POLL_INTERVAL, Poll)
    end

    local function StopTicker()
        if ticker then ticker:Cancel(); ticker = nil end
        wipe(deadState)
        if alertOverlay then alertOverlay:Hide() end
    end

    local function UpdateActive()
        if EllesmereUIDB and EllesmereUIDB.announceGroupDeaths and IsInGroup() then
            StartTicker()
        else
            StopTicker()
        end
    end

    local function ApplyAnnounceGroupDeaths()
        local on = EllesmereUIDB and EllesmereUIDB.announceGroupDeaths
        if on and not installed then
            watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            installed = true
        elseif not on and installed then
            watcher:UnregisterAllEvents()
            installed = false
        end
        UpdateActive()
    end
    EllesmereUI._applyAnnounceGroupDeaths = ApplyAnnounceGroupDeaths

    -- Fires a sample alert (with sound) so the look/sound can be checked without
    -- a real death. Uses your own name/class purely as preview text.
    EllesmereUI._announceGroupDeathsPreview = function()
        local _, classToken = UnitClass("player")
        ShowAlert(UnitName("player"), classToken)
        PlayDeathSound()
    end

    -- Visual-only preview (used by the Text Size slider so dragging it doesn't
    -- repeatedly fire the sound).
    EllesmereUI._groupDeathShowVisual = function()
        local _, classToken = UnitClass("player")
        ShowAlert(UnitName("player"), classToken)
    end

    EllesmereUI._groupDeathPlaySound = PlayDeathSound

    -- Re-apply font size / position (called from the Text Size slider and from
    -- unlock mode when the saved position changes).
    EllesmereUI._applyGroupDeathAlert = function()
        CreateAlertOverlay()
        ApplyOverlaySettings()
    end

    -- Register the alert with Unlock Mode so its position can be dragged.
    C_Timer.After(2, function()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
        local MK = EllesmereUI.MakeUnlockElement
        if not MK then return end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key      = "EUI_GroupDeathAlert",
                label    = "Group Death Alert",
                group    = "Quality of Life",
                order    = 720,
                noResize = true,
                isHidden = function()
                    return not (EllesmereUIDB and EllesmereUIDB.announceGroupDeaths)
                end,
                getFrame = function()
                    CreateAlertOverlay()
                    return alertOverlay
                end,
                getSize = function()
                    local size = (EllesmereUIDB and EllesmereUIDB.groupDeathTextSize) or DEFAULT_TEXT_SIZE
                    return size * 7, size + 14
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not point then return end
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.groupDeathAlertPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if alertOverlay and not EllesmereUI._unlockActive then
                        ApplyOverlaySettings()
                    end
                end,
                loadPos = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.groupDeathAlertPos
                    if pos and pos.point then return pos end
                    return { point = "CENTER", relPoint = "CENTER", x = 0, y = 180 }
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.groupDeathAlertPos = nil end
                    if alertOverlay then ApplyOverlaySettings() end
                end,
                applyPos = function()
                    CreateAlertOverlay()
                    ApplyOverlaySettings()
                end,
            }),
        })
    end)

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function() UpdateActive() end)

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        -- Append SharedMedia sounds now, at login, once other addons have
        -- registered theirs -- this is the same timing Chat's whisper-sound
        -- dropdown uses. Idempotent: AppendSharedMediaSounds skips keys that
        -- are already present, and the tables are the very ones the options
        -- dropdown (and PlayDeathSound) read, so both pick up the SM sounds.
        if EllesmereUI.AppendSharedMediaSounds then
            EllesmereUI.AppendSharedMediaSounds(
                GROUP_DEATH_SOUND_PATHS, GROUP_DEATH_SOUND_NAMES, GROUP_DEATH_SOUND_ORDER)
        end
        if EllesmereUIDB and EllesmereUIDB.announceGroupDeaths then
            ApplyAnnounceGroupDeaths()
        end
    end)
end

-------------------------------------------------------------------------------
--  Combat Alert
--  Shows a large center-screen text alert when you enter and/or leave combat
--  (PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED). Each transition has its own
--  display text and color (a custom color or the player's class color); a single
--  Text Size and a shared unlock-mode position apply to both. The "Show On" mode
--  selects enter-only, leave-only or both. Zero cost when idle: no combat events
--  are registered unless the master toggle is on.
-------------------------------------------------------------------------------
do
    local alertFrame
    local watcher
    local installed = false
    local DEFAULT_TEXT_SIZE = 22
    local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 169 }

    local DEFAULTS = {
        enterText  = "+Combat",
        leaveText  = "-Combat",
        enterColor = { r = 1.00, g = 1.00, b = 1.00 },
        leaveColor = { r = 1.00, g = 1.00, b = 1.00 },
    }

    -- Resolve the effective color for a transition: the player's class color
    -- when the class-color toggle is on, otherwise the stored custom color.
    local function ResolveColor(which)
        local db = EllesmereUIDB
        local useClass = db and db[which == "leave" and "combatAlertLeaveUseClassColor" or "combatAlertEnterUseClassColor"]
        if useClass then
            local _, classToken = UnitClass("player")
            local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
            if c then return c.r, c.g, c.b end
        end
        local c = (db and db[which == "leave" and "combatAlertLeaveColor" or "combatAlertEnterColor"])
            or (which == "leave" and DEFAULTS.leaveColor or DEFAULTS.enterColor)
        return c.r, c.g, c.b
    end

    local function AlertText(which)
        local db = EllesmereUIDB
        if which == "leave" then
            return (db and db.combatAlertLeaveText) or DEFAULTS.leaveText
        end
        return (db and db.combatAlertEnterText) or DEFAULTS.enterText
    end

    -- Applies the configured font size and saved position (or the default
    -- dead-center placement) to the overlay.
    local function ApplyOverlaySettings()
        if not alertFrame then return end
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
            or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        -- Always keep an outline so the alert stays readable over any background.
        local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("extras")) or ""
        if not outline:find("OUTLINE") then
            outline = (outline == "" ) and "OUTLINE" or (outline .. ", OUTLINE")
        end
        local size = (EllesmereUIDB and EllesmereUIDB.combatAlertTextSize) or DEFAULT_TEXT_SIZE
        alertFrame._text:SetFont(fontPath, size, outline)
        -- Keep the frame (and the unlock-mode mover) sized to roughly the text.
        alertFrame:SetSize(size * 7, size + 14)

        alertFrame:ClearAllPoints()
        local pos = EllesmereUIDB and EllesmereUIDB.combatAlertPos
        if pos and pos.point then
            alertFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        else
            alertFrame:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.relPoint, DEFAULT_POS.x, DEFAULT_POS.y)
        end
    end

    local function CreateAlertFrame()
        if alertFrame then return end

        alertFrame = CreateFrame("Frame", nil, UIParent)
        alertFrame:SetSize(240, 50)
        alertFrame:SetFrameStrata("HIGH")
        alertFrame:SetFrameLevel(60)
        alertFrame:EnableMouse(false)
        alertFrame:SetMouseClickEnabled(false)

        local fs = alertFrame:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER")
        alertFrame._text = fs
        ApplyOverlaySettings()

        -- Quick fade-in, brief hold, fade-out; hide when finished.
        local ag = alertFrame:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.15); fadeIn:SetOrder(1)
        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.2); hold:SetOrder(2)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.5); fadeOut:SetOrder(3)
        ag:SetScript("OnFinished", function() alertFrame:Hide() end)
        alertFrame._ag = ag

        alertFrame:SetScript("OnHide", function() ag:Stop() end)
        alertFrame:Hide()
    end

    local function ShowAlert(which)
        -- Never fire live alerts while unlock mode is positioning the frame.
        if EllesmereUI._unlockActive then return end
        CreateAlertFrame()
        ApplyOverlaySettings()

        alertFrame._text:SetText(AlertText(which))
        alertFrame._text:SetTextColor(ResolveColor(which))
        alertFrame._text:SetAlpha(1)

        alertFrame._ag:Stop()
        alertFrame:SetAlpha(1)
        alertFrame:Show()
        alertFrame._ag:Play()
    end

    local function OnCombatEvent(_, event)
        local db = EllesmereUIDB
        if not (db and db.combatAlertEnabled) then return end
        local mode = db.combatAlertMode or "both"
        if event == "PLAYER_REGEN_DISABLED" then
            if mode ~= "leave" then ShowAlert("enter") end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if mode ~= "enter" then ShowAlert("leave") end
        end
    end

    local function ApplyCombatAlert()
        local on = EllesmereUIDB and EllesmereUIDB.combatAlertEnabled
        if on and not installed then
            watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
            watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            installed = true
        elseif not on and installed then
            watcher:UnregisterAllEvents()
            installed = false
        end
        if alertFrame then ApplyOverlaySettings() end
    end
    EllesmereUI._applyCombatAlert = ApplyCombatAlert

    -- Fires a sample alert for the given transition ("enter"/"leave") so the
    -- look can be checked from the options cog without a real combat change.
    EllesmereUI._combatAlertPreview = function(which)
        if EllesmereUI._unlockActive then return end
        CreateAlertFrame()
        ApplyOverlaySettings()
        alertFrame._text:SetText(AlertText(which))
        alertFrame._text:SetTextColor(ResolveColor(which))
        alertFrame._ag:Stop()
        alertFrame:SetAlpha(1)
        alertFrame:Show()
        alertFrame._ag:Play()
    end

    -- Re-apply font size / position (called from the Text Size slider and from
    -- unlock mode when the saved position changes).
    EllesmereUI._applyCombatAlertFrame = function()
        CreateAlertFrame()
        ApplyOverlaySettings()
    end

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", OnCombatEvent)

    -- Register the alert with Unlock Mode so its position can be dragged.
    C_Timer.After(2, function()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
        local MK = EllesmereUI.MakeUnlockElement
        if not MK then return end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key      = "EUI_CombatAlert",
                label    = "Combat Alert",
                group    = "Quality of Life",
                order    = 721,
                noResize = true,
                isHidden = function()
                    return not (EllesmereUIDB and EllesmereUIDB.combatAlertEnabled)
                end,
                getFrame = function()
                    CreateAlertFrame()
                    return alertFrame
                end,
                getSize = function()
                    local size = (EllesmereUIDB and EllesmereUIDB.combatAlertTextSize) or DEFAULT_TEXT_SIZE
                    return size * 7, size + 14
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not point then return end
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if alertFrame and not EllesmereUI._unlockActive then
                        ApplyOverlaySettings()
                    end
                end,
                loadPos = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.combatAlertPos
                    if pos and pos.point then return pos end
                    return { point = DEFAULT_POS.point, relPoint = DEFAULT_POS.relPoint, x = DEFAULT_POS.x, y = DEFAULT_POS.y }
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.combatAlertPos = nil end
                    if alertFrame then ApplyOverlaySettings() end
                end,
                applyPos = function()
                    CreateAlertFrame()
                    ApplyOverlaySettings()
                end,
            }),
        })
    end)

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if EllesmereUIDB and EllesmereUIDB.combatAlertEnabled then
            ApplyCombatAlert()
        end
    end)
end

-------------------------------------------------------------------------------
--  Hide Item Transforms
--  Cancels cosmetic transform auras (profession gear, holiday costumes, toys,
--  consumables) as soon as they land on the player. CancelUnitBuff is blocked
--  during combat, so transforms gained mid-fight are swept on the next
--  PLAYER_REGEN_ENABLED. The fishing outfit aura persists while the fishing
--  channel runs, so it is cleared when the channel stops instead.
--  Zero cost when idle: no events are registered unless the master toggle is
--  on AND at least one transform is still included.
-------------------------------------------------------------------------------
do
    local CATEGORY_ORDER = { "professions", "holiday", "toys", "items" }
    local CATEGORY_LABEL = {
        professions = "Profession Gear",
        holiday     = "Holiday Costumes",
        toys        = "Toys",
        items       = "Consumables & Items",
    }

    -- Each entry: stable settings key, category, display label, aura spell IDs.
    -- Fishing lists no aura IDs -- the channel-stop watcher below owns it.
    local TRANSFORMS = {
        -- Profession gear
        { key = "blacksmithing",  cat = "professions", label = "Blacksmithing",  ids = { 388658 } },
        { key = "jewelcrafting",  cat = "professions", label = "Jewelcrafting",  ids = { 394015 } },
        { key = "tailoring",      cat = "professions", label = "Tailoring",      ids = { 391312 } },
        { key = "engineering",    cat = "professions", label = "Engineering",    ids = { 394007 } },
        { key = "enchanting",     cat = "professions", label = "Enchanting",     ids = { 394008 } },
        { key = "alchemy",        cat = "professions", label = "Alchemy",        ids = { 394003 } },
        { key = "inscription",    cat = "professions", label = "Inscription",    ids = { 394016 } },
        { key = "leatherworking", cat = "professions", label = "Leatherworking", ids = { 394001 } },
        { key = "herbalism",      cat = "professions", label = "Herbalism",      ids = { 394005 } },
        { key = "mining",         cat = "professions", label = "Mining",         ids = { 394006 } },
        { key = "skinning",       cat = "professions", label = "Skinning",       ids = { 394011 } },
        { key = "cooking",        cat = "professions", label = "Cooking (Chef's Hat)", ids = { 391775 } },
        { key = "fishing",        cat = "professions", label = "Fishing",        ids = {} },

        -- Holiday costumes
        { key = "lantern",    cat = "holiday", label = "Weighted Jack-o'-Lantern", ids = { 44212 } },
        { key = "hallowed",   cat = "holiday", label = "Hallowed Wand", ids = {
            172010, 218132, 191703, 24732, 191210, 172015, 24735, 24736, 191698, 191700,
            172008, 24712, 24713, 191701, 191211, 24710, 24711, 191686, 191688, 24708,
            24709, 173958, 173959, 191682, 191683, 24723, 191702, 172003, 172020, 191208, 24740,
        } },
        { key = "noblebunny", cat = "holiday", label = "Noblegarden Bunny", ids = { 61734, 61716 } },
        { key = "turkey",     cat = "holiday", label = "Pilgrim's Turkey", ids = { 61781 } },

        -- Toys
        { key = "aqir",       cat = "toys", label = "Aqir Egg Cluster",          ids = { 318452 } },
        { key = "atomic",     cat = "toys", label = "Atomically Recalibrator",   ids = { 399502 } },
        { key = "atomgoblin", cat = "toys", label = "Atomically Regoblinator",   ids = { 1215363 } },
        { key = "blight",     cat = "toys", label = "Detoxified Blight Grenade", ids = { 290224 } },
        { key = "witch",      cat = "toys", label = "Lucille's Sewing Needle",   ids = { 279509 } },
        { key = "spraybots",  cat = "toys", label = "Spraybots",                 ids = { 301892, 301893, 301894 } },

        -- Consumables & items
        { key = "pickaxe",      cat = "items", label = "Cursed Pickaxe",      ids = { 454405 } },
        { key = "noggenfogger", cat = "items", label = "Noggenfogger Elixir", ids = { 16593, 1223630, 16595, 1223629, 1223631 } },
        { key = "prism",        cat = "items", label = "Reflecting Prism",    ids = { 163267 } },
    }

    -- Runtime lookup: [spellID] = true for every included transform.
    local cTable = {}

    -- Transforms are included by default; the picker stores false to exclude.
    local function ItemEnabled(key)
        local t = EllesmereUIDB and EllesmereUIDB.hideTransformItems
        if t and t[key] == false then return false end
        return true
    end

    local function RebuildList()
        wipe(cTable)
        if not (EllesmereUIDB and EllesmereUIDB.hideTransforms) then return end
        for _, item in ipairs(TRANSFORMS) do
            if ItemEnabled(item.key) then
                for _, id in ipairs(item.ids) do cTable[id] = true end
            end
        end
    end

    local auraFrame = CreateFrame("Frame")

    -- 12.1: index scans hard-error while aura restrictions are active
    -- (M+/raids, even out of combat). Transforms are cosmetic; skipping the
    -- sweep there is fine -- it re-runs on the next event outside.
    local function AurasRestricted()
        local AK = EllesmereUI and EllesmereUI.AuraKit
        if AK and AK.AurasRestricted then return AK.AurasRestricted() end
        return false
    end

    -- Sweep current buffs, canceling any included transform. Descending so a
    -- cancel (which shifts later buff indices down) cannot skip a match.
    local function CancelMatching(force)
        if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
        if not force and UnitAffectingCombat("player") then return end
        if AurasRestricted() then return end
        for i = 40, 1, -1 do
            local data = C_UnitAuras.GetBuffDataByIndex("player", i)
            if data then
                local spellID = data.spellId
                if spellID and not (issecretvalue and issecretvalue(spellID)) and cTable[spellID] then
                    CancelUnitBuff("player", i)
                end
            end
        end
    end

    auraFrame:SetScript("OnEvent", function(_, event, _, updateInfo)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Combat just ended: clear anything that landed while locked.
            CancelMatching(true)
            return
        end
        -- UNIT_AURA (player only, via RegisterUnitEvent). 12.1: the payload
        -- (and its fields) can be secret in restricted content -- boolean
        -- use of a secret errors, and the sweep would error anyway; bail.
        if not updateInfo then return end
        if issecretvalue and issecretvalue(updateInfo) then return end
        local isFull = updateInfo.isFullUpdate
        if isFull ~= nil and issecretvalue and issecretvalue(isFull) then return end
        if isFull then
            CancelMatching(false)
        elseif updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                local spellID = aura.spellId
                if spellID and not (issecretvalue and issecretvalue(spellID)) and cTable[spellID] then
                    CancelMatching(false)
                    break
                end
            end
        end
    end)

    -- Fishing outfit: aura 394009 sticks while the fishing channel (131476)
    -- runs, so it is cleared when the channel stops. Only registered while the
    -- feature is on and the Fishing entry is included.
    local fishFrame = CreateFrame("Frame")
    fishFrame:SetScript("OnEvent", function(_, _, _, _, spellID)
        if issecretvalue and issecretvalue(spellID) then return end
        if spellID ~= 131476 then return end
        if UnitAffectingCombat("player") then return end
        if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
        if AurasRestricted() then return end
        for i = 40, 1, -1 do
            local data = C_UnitAuras.GetBuffDataByIndex("player", i)
            if data then
                local sid = data.spellId
                if sid and not (issecretvalue and issecretvalue(sid)) and sid == 394009 then
                    CancelUnitBuff("player", i)
                end
            end
        end
    end)

    -- (Re)decide which events are hooked. Nothing is registered unless the
    -- feature is on AND something is actually included, so a disabled feature
    -- costs zero per-frame work -- the handlers are simply never installed.
    local function ApplyHideTransforms()
        RebuildList()
        local on = EllesmereUIDB and EllesmereUIDB.hideTransforms

        if on and next(cTable) ~= nil then
            auraFrame:RegisterUnitEvent("UNIT_AURA", "player")
            auraFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            CancelMatching(false)  -- immediate sweep of anything already active
        else
            auraFrame:UnregisterEvent("UNIT_AURA")
            auraFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end

        if on and ItemEnabled("fishing") then
            fishFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        else
            fishFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        end
    end
    EllesmereUI._applyHideTransforms = ApplyHideTransforms

    -- Shared with the options picker popup (EUI_QoL_Options.lua).
    EllesmereUI.HideTransformsData = {
        order  = CATEGORY_ORDER,
        labels = CATEGORY_LABEL,
        items  = TRANSFORMS,
    }
    EllesmereUI.GetHideTransformItem = ItemEnabled
    EllesmereUI.SetHideTransformItem = function(key, enabled)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.hideTransformItems = EllesmereUIDB.hideTransformItems or {}
        -- Included is the default -- store only exclusions, keeping the table sparse.
        if enabled then
            EllesmereUIDB.hideTransformItems[key] = nil
        else
            EllesmereUIDB.hideTransformItems[key] = false
        end
        ApplyHideTransforms()
    end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyHideTransforms()
    end)
end

-------------------------------------------------------------------------------
--  Equipment Flyout item levels
--  Blizzard's character-sheet gear flyout (hover a gear slot -> the popup of
--  same-slot items from your bags/equipped) only shows item icons. When this is
--  enabled we overlay each flyout button with the item level of the item it
--  represents, coloured by item quality, so you can compare upgrades at a
--  glance without reading every tooltip.
--
--  We hook EquipmentFlyout_DisplayButton (called once per button whenever the
--  flyout is populated) and read live from EllesmereUIDB, so toggling the
--  option takes effect on the next flyout without a reload.
--  Toggle: EllesmereUIDB.flyoutItemLevels (Quality of Life -> UI).
-------------------------------------------------------------------------------
do
    local function FlyoutEnabled()
        return EllesmereUIDB and EllesmereUIDB.flyoutItemLevels
    end

    -- Compute item level + quality + link from a decoded bag/slot pair. Prefers
    -- the ItemLocation API (exact per-item level, no caching) and falls back to
    -- the item link when the location can't be built.
    local function LevelFromSlot(isBags, bag, slot)
        if isBags then
            if ItemLocation then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
                    return C_Item.GetCurrentItemLevel(loc), C_Item.GetItemQuality(loc), C_Item.GetItemLink(loc)
                end
            end
            local link = C_Container and C_Container.GetContainerItemLink(bag, slot)
            if link then
                return C_Item.GetDetailedItemLevelInfo(link), select(3, C_Item.GetItemInfo(link)), link
            end
            return
        end
        -- Equipped / bank inventory slot.
        local link = GetInventoryItemLink("player", slot)
        if link then
            local quality = GetInventoryItemQuality and GetInventoryItemQuality("player", slot)
            return C_Item.GetDetailedItemLevelInfo(link), quality or select(3, C_Item.GetItemInfo(link)), link
        end
    end

    -- Return item level + quality + link for a flyout button. Handles all three
    -- flyout shapes across game versions:
    --   * modern flyouts that store an ItemLocation object on the button,
    --   * current retail packed location decoded via EquipmentManager_GetLocationData,
    --   * older clients decoded via EquipmentManager_UnpackLocation.
    local function ButtonItemInfo(button)
        if button.GetItemLocation then
            local ok, loc = pcall(button.GetItemLocation, button)
            if ok and loc and loc.IsValid and loc:IsValid() and C_Item.DoesItemExist(loc) then
                return C_Item.GetCurrentItemLevel(loc), C_Item.GetItemQuality(loc), C_Item.GetItemLink(loc)
            end
        end

        local location = button.location
        if not location or type(location) ~= "number" then return end
        if EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION
            and location >= EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
            return
        end

        if EquipmentManager_GetLocationData then
            local ld = EquipmentManager_GetLocationData(location)
            if not ld or ld.slot == nil then return end
            return LevelFromSlot(ld.isBags, ld.bag, ld.slot)
        elseif EquipmentManager_UnpackLocation then
            local _, _, bags, voidStorage, slot, bag = EquipmentManager_UnpackLocation(location)
            if voidStorage then return end
            return LevelFromSlot(bags, bag, slot)
        end
    end

    -- Item-level FontStrings live in an external weak-keyed table, NOT on the
    -- button. The flyout buttons are Blizzard-owned (and the flyout is the
    -- secure item-equipping path), so writing a custom key onto them would
    -- taint their execution context. Creating the FontString region on the
    -- button is fine; only the state reference must stay off the frame table.
    local _flyoutFS = setmetatable({}, { __mode = "k" })  -- [button] = fontstring

    -- Lazily attach (and return) the item-level FontString for a flyout button.
    local function EnsureText(button)
        local fs = _flyoutFS[button]
        if not fs then
            local font = EllesmereUI._font
                or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
            local flag = (EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG"))
                or "OUTLINE, SLUG"
            fs = button:CreateFontString(nil, "OVERLAY", nil, 7)
            fs:SetFont(font, 12, flag)
            fs:SetPoint("TOP", button, "TOP", 0, -2)
            fs:SetJustifyH("CENTER")
            _flyoutFS[button] = fs
        end
        return fs
    end

    local function InstallHook()
        if not EquipmentFlyout_DisplayButton then return end
        hooksecurefunc("EquipmentFlyout_DisplayButton", function(button)
            local fs = _flyoutFS[button]
            if not FlyoutEnabled() then
                if fs then fs:SetText("") end
                return
            end

            local ilvl, quality, link = ButtonItemInfo(button)
            fs = EnsureText(button)
            if ilvl and ilvl > 0 then
                fs:SetText(ilvl)
                -- Match the character sheet: custom color > upgrade track > rarity.
                local c
                if EllesmereUI.GetItemLevelColor then
                    c = EllesmereUI.GetItemLevelColor(link, quality)
                elseif quality and ITEM_QUALITY_COLORS then
                    c = ITEM_QUALITY_COLORS[quality]
                end
                if c then
                    fs:SetTextColor(c.r, c.g, c.b, 1)
                else
                    fs:SetTextColor(1, 1, 1, 1)
                end
            else
                fs:SetText("")
            end
        end)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        InstallHook()
    end)
end

