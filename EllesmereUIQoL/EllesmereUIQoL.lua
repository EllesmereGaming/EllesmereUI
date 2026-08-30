if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL.lua
--  Runtime logic for all Quality-of-Life features toggled in the QoL Features
--  tab of Global Settings. No UI code here -- only gameplay behaviour.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Per-profile storage for QoL "extras" (Secondary Stats + FPS counter): reads
--  fall back to the account-wide EllesmereUIDB root when a profile has no
--  value yet (new profile/sync gap); writes always go per-profile. Mirrors the
--  crosshair read/fallback pattern; EllesmereUI_Migration.lua seeds every
--  existing profile from the old account-wide values. EUIQoLDB is
--  shared with Cursor/BattleRes/Bloodlust: each NewDB merges its own defaults
--  into the SAME profile table, repointed by the profile system on swap.
-------------------------------------------------------------------------------
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS["EllesmereUIQoL"] = select(2, ...)  -- LOD options files read this module ns via the registry

local _qolExtrasDB
local function QoLExtrasProfile()
    if not _qolExtrasDB and EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB then
        _qolExtrasDB = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", {
            profile = {
                secondaryStatsHidden = {
                    leech = true,
                    avoidance = true,
                    speed = true,
                },
            },
        })
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

        -- Clears pending mount fanfare: narrows the journal filter to
        -- collected-only for the sweep, then restores the snapshot.
        local function AckMountAlerts()
            if not C_MountJournal then return false end
            local pending = C_MountJournal.GetNumMountsNeedingFanfare
                and C_MountJournal.GetNumMountsNeedingFanfare()
            if not pending or pending <= 0 then return false end

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
            if ToyBox and ToyBox.fanfareToys then
                for id, needs in pairs(ToyBox.fanfareToys) do
                    if needs and id and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(id) then
                        C_ToyBoxInfo.ClearFanfare(id)
                        any = true
                    end
                end
                if any then return true end
            end
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
                -- Defer 3s so ToyBox.fanfareToys exists (avoids a 1000+ toy full scan at login)
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
        local _failedItems = {}   -- itemID -> true (failed to open, skip forever)
        local _cacheBuilt = false
        -- In-flight opens keyed by bag/slot, set synchronously in the same tick as
        -- UseContainerItem (Lua is single-threaded, so no other pass can slip in) and
        -- cleared at the 0.5s recheck (Blizzard's isLocked isn't set until the round-trip completes) -- stops a double-use stranding a slot.
        local _openInProgress = {}
        -- Payout containers open a loot window and linger until looted; any open while up strands them. Gate on this; resume on LOOT_CLOSED.
        local _lootOpen = false
        -- Attribution for loot windows our opens spawn: _pendingOpen is stamped
        -- before UseContainerItem, cleared at the 0.5s recheck; LOOT_OPENED captures
        -- it into _lootSource. On close, still sitting with an un-decremented count
        -- means it couldn't be looted (bags full/unique cap), so it's skipped for the session (reload retries once space frees).
        local _pendingOpen, _lootSource
        -- Global single-flight: only one open cycle at a time. Per-slot _openInProgress
        -- isn't enough -- a payout container's lock latency outlasts its 0.5s window, so a second chain could reuse and strand it.
        local _openBusy = false
        local _scanScheduled = false
        -- Cycle generation: bumped on cycle start AND disable. Every deferred closure
        -- captures its own generation and self-aborts when stale -- IsEnabled() alone
        -- isn't enough since a disable->re-enable inside the recheck window would resurrect the old chain alongside the new one.
        local _cycleGen = 0
        -- A scan request arrived while busy; finish() honors it even with no progress.
        local _missedScan = false
        -- Pacing: mail's "Open All" lands many items within one second, exactly
        -- when our action can collide with another still resolving and strand a
        -- slot locked until relog -- the client optimistically locks on any action,
        -- clearing only once the server confirms. _lastBagChurn = GetTime() of the
        -- most recent raw BAG_UPDATE (real-time signal; coalesced BAG_UPDATE_DELAYED is too coarse).
        local _lastBagChurn = 0
        local CHURN_SETTLE_WINDOW = 0.35  -- "recent" churn cutoff, seconds
        local CHURN_SETTLE_DELAY = 0.4    -- extra wait when churn was recent
        local function AODbg(...)
            if EllesmereUI._AODEBUG then print("|cff33ff99[AutoOpen]|r", ...) end
        end
        -- Forward-declared: scanFrame's OnUpdate calls ScanAndOpen once cache is built, so both must be in-scope upvalues (assigned further down).
        local ScanAndOpen, RequestScan
        local function SlotKey(bag, slot) return bag * 1000 + slot end
        local function IsEnabled()
            return EllesmereUIDB and EllesmereUIDB.autoOpenContainers == true
        end
        -- This payout can award this capped currency; hold only the known pair.
        local ARTISAN_PAYOUT_ITEM_ID = 246585
        local SHARD_OF_DUNDUN_CURRENCY_ID = 3376
        local function ShouldHoldCappedArtisanPayout(itemID)
            if itemID ~= ARTISAN_PAYOUT_ITEM_ID
                or not (EllesmereUIDB
                    and EllesmereUIDB.autoOpenContainersHoldCappedArtisanPayouts == true) then
                return false
            end
            return C_CurrencyInfo and C_CurrencyInfo.PlayerHasMaxQuantity
                and C_CurrencyInfo.PlayerHasMaxQuantity(SHARD_OF_DUNDUN_CURRENCY_ID) or false
        end
        -- An open merchant turns UseContainerItem into a SELL, so auto-open pauses
        -- while any merchant frame is shown, or bought containers get vendored /
        -- non-openables throw an error. Re-checked per open; re-runs on MERCHANT_CLOSED.
        local function MerchantOpen()
            return (MerchantFrame and MerchantFrame:IsShown()) and true or false
        end
        -- Same reasoning as MerchantOpen: opening while the mailbox is up compounds
        -- the strand-a-slot race with mail's own item delivery. Interaction state,
        -- not frame visibility: third-party mail/bank UIs hide the stock frames,
        -- but the server-tracked interaction is true at the mailbox/banker
        -- regardless of what draws the window.
        local function MailOpen()
            return (C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType
                and C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.MailInfo)) and true or false
        end
        local function BankOpen()
            if not (C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType) then return false end
            -- Both bank types: character banker and the warband (account) bank.
            return (C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.Banker)
                or C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.AccountBanker)) and true or false
        end
        -- "Exclude Warbound Containers": checks the item's own bind type
        -- instead of asking the bank if it would accept a deposit right now --
        -- that answer needs a live bank session and defaults to "no" outdoors,
        -- which let warbound items open anyway. Bind type works anywhere.
        local WARBOUND_BIND_TYPES = {
            [Enum.ItemBind.ToWoWAccount] = true,
            [Enum.ItemBind.ToBnetAccount] = true,
            [Enum.ItemBind.ToBnetAccountUntilEquipped] = true,
        }
        local function IsWarboundExcluded(bag, slot)
            -- Default ON (unset behaves as enabled, matching the options UI's
            -- checked-by-default display); only explicit false disables it -- `not value` would wrongly let nil skip the exclusion.
            if not EllesmereUIDB or EllesmereUIDB.autoOpenContainersExcludeWarbound == false then return false end
            if not (C_Container and C_Container.GetContainerItemInfo and C_Item and C_Item.GetItemInfo) then return false end
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not (info and info.itemID) then return false end
            local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(info.itemID)
            -- Item data not cached yet: fail CLOSED (skip this pass; the scan
            -- re-checks once the data lands) so a warbound container is never
            -- opened just because its bind type was not known yet.
            if not bindType then return true end
            if WARBOUND_BIND_TYPES[bindType] == true then return true end
            -- Warbound Until Equipped containers report bindType == OnEquip, same as
            -- an ordinary BoE item (no dedicated GetItemInfo enum value -- see
            -- EUI_Bags.SetBindTypeText's "WuE items report bindType == OnEquip"), so
            -- ToBnetAccountUntilEquipped above never actually matches one. The item's
            -- own bound-until-equip flag is the only reliable signal.
            if bindType == Enum.ItemBind.OnEquip and ItemLocation and C_Item.IsBoundToAccountUntilEquip then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if loc and C_Item.DoesItemExist(loc) then
                    return C_Item.IsBoundToAccountUntilEquip(loc) == true
                end
            end
            return false
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
            -- A brand-new item's data can still be loading server-side when
            -- this first check runs, so an empty tooltip here doesn't mean
            -- "not openable" -- it can just mean "not loaded yet". Only cache
            -- the negative once the item's data is actually in, so a real
            -- negative sticks but an early miss gets rechecked on the next scan.
            if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
                return false
            end
            _openableCache[itemID] = false
            return false
        end

        -- Incremental scanner: SLOTS_PER_FRAME slots per tick; hides itself once
        -- all bags are scanned (zero CPU when idle).
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
                        -- Cache warm: hand off to the open cycle, which re-scans itself.
                        _cacheBuilt = true
                        self:Hide()
                        if ScanAndOpen then ScanAndOpen(false) end
                        return
                    end
                else
                    local info = C_Container.GetContainerItemInfo(_scanBag, _scanSlot)
                    if info and info.itemID then
                        -- Warm here so the open cycle never tooltip-scans on its hot path.
                        IsOpenableByID(info.itemID, _scanBag, _scanSlot)
                    end
                    _scanSlot = _scanSlot + 1
                    checked = checked + 1
                end
            end
        end)

        -- After cache is built, BAG_UPDATE_DELAYED only checks changed slots
        local containerFrame = CreateFrame("Frame")

        -- Live apply: registers bag listeners and (until cache exists) runs the
        -- incremental scan; disable stops it. Called at login and from the toggle.
        EllesmereUI._applyAutoOpenContainers = function()
            if IsEnabled() then
                containerFrame:RegisterEvent("BAG_UPDATE_DELAYED")
                -- Raw per-slot event, far more frequent than the coalesced DELAYED one; used ONLY to timestamp _lastBagChurn, no scan work here.
                containerFrame:RegisterEvent("BAG_UPDATE")
                -- Re-run on vendor close: a purchase's BAG_UPDATE_DELAYED fires
                -- while opens are suppressed, so bought containers would never open.
                containerFrame:RegisterEvent("MERCHANT_CLOSED")
                -- MailOpen() is read at every entry point so the pause needs no event;
                -- MAIL_CLOSED no longer fires on retail (kept for older clients) -- interaction-manager HIDE drives resume.
                containerFrame:RegisterEvent("MAIL_CLOSED")
                containerFrame:RegisterEvent("BANKFRAME_CLOSED")
                if C_PlayerInteractionManager then
                    containerFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
                end
                -- Loot window tracking (see _lootOpen).
                containerFrame:RegisterEvent("LOOT_OPENED")
                containerFrame:RegisterEvent("LOOT_CLOSED")
                if EllesmereUIDB.autoOpenContainersHoldCappedArtisanPayouts == true
                    and C_CurrencyInfo and C_CurrencyInfo.PlayerHasMaxQuantity then
                    containerFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
                else
                    containerFrame:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
                end
                -- Resume opens deferred while casting, else the deferral stalls until the next bag update.
                containerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                containerFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
                containerFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
                if not _cacheBuilt then
                    _scanBag = BACKPACK_CONTAINER
                    _scanSlot = 1
                    scanFrame:Show()
                elseif RequestScan then
                    RequestScan()
                end
            else
                containerFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
                containerFrame:UnregisterEvent("BAG_UPDATE")
                containerFrame:UnregisterEvent("MERCHANT_CLOSED")
                containerFrame:UnregisterEvent("MAIL_CLOSED")
                containerFrame:UnregisterEvent("BANKFRAME_CLOSED")
                if C_PlayerInteractionManager then
                    containerFrame:UnregisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
                end
                containerFrame:UnregisterEvent("LOOT_OPENED")
                containerFrame:UnregisterEvent("LOOT_CLOSED")
                containerFrame:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
                containerFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                containerFrame:UnregisterEvent("UNIT_SPELLCAST_STOP")
                containerFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
                _lootOpen = false
                _pendingOpen = nil
                _lootSource = nil
                -- Clears single-flight state so a mid-cycle disable can't strand
                -- _openBusy; the generation bump kills in-flight timers so a quick re-enable can't resurrect the old chain.
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
        -- skipMerchantGate: MERCHANT_CLOSED's re-run fires before MerchantFrame
        -- finishes hiding, so its entry check would misread "merchant open" and bail;
        -- that run skips only THIS gate -- safety comes from the 0.15s pre-open delay plus the per-step MerchantOpen() re-check.
        --
        -- Single-flight open cycle: build the candidate list, open one container at a
        -- time, re-scan once IF anything progressed when exhausted (subsumes nested
        -- containers and lingering payout containers, no second concurrent chain).
        -- _openBusy guards the whole cycle. UseContainerItem silently CANCELS the
        -- player's cast (engine treats it as interrupting), eating mounts/ports/hardcasts
        -- with no error -- a cast is transient, so defer rather than blacklist: the spellcast events above resume the cycle.
        local function PlayerIsCasting()
            return (UnitCastingInfo and UnitCastingInfo("player") ~= nil)
                or (UnitChannelInfo and UnitChannelInfo("player") ~= nil)
        end

        -- skipMailGate: MAIL_CLOSED/interaction-manager hide already settle 0.5s
        -- below, so MailOpen() is reliably false by then -- belt and suspenders, not load-bearing like skipMerchantGate.
        ScanAndOpen = function(skipMerchantGate, skipMailGate, skipBankGate)
            if not _cacheBuilt then return end
            if not IsEnabled() then return end
            if InCombatLockdown() then return end
            if not skipMerchantGate and MerchantOpen() then return end
            if not skipMailGate and MailOpen() then return end
            if not skipBankGate and BankOpen() then return end
            if PlayerIsCasting() then _missedScan = true; return end
            -- Loot window up: LOOT_CLOSED restarts once the payout container leaves the bag.
            if _lootOpen then return end
            -- A running cycle's finish() re-scan picks up this trigger.
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
            AODbg(("cycle start: %d candidate(s)"):format(#toOpen))

            -- Only place _openBusy is cleared; every step() exit routes here so it
            -- can't leak (freezes auto-open until reload). A stale generation must NOT clear it -- belongs to the new cycle.
            local function finish()
                if myGen ~= _cycleGen then return end
                _openBusy = false
                if (madeProgress or _missedScan) and IsEnabled()
                    and not InCombatLockdown()
                    and not MerchantOpen() and not MailOpen() and not BankOpen() and not _lootOpen then
                    _missedScan = false
                    C_Timer.After(0.3, function() ScanAndOpen(false, false, false) end)
                end
            end

            local PaceNext  -- forward-declared: assigned after step, below
            local function step(idx)
                if myGen ~= _cycleGen then return end
                if idx > #toOpen then return finish() end
                if not IsEnabled() or InCombatLockdown() or MerchantOpen() or MailOpen() or BankOpen() then return finish() end
                -- Re-checked per step: the cycle paces itself across seconds of timers, so a cast can start long after the entry gate passed.
                if PlayerIsCasting() then _missedScan = true; return finish() end
                -- Loot window opened mid-cycle: stop; LOOT_CLOSED restarts cleanly.
                if _lootOpen then return finish() end
                local item = toOpen[idx]
                local key = SlotKey(item.bag, item.slot)
                local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
                -- Never act on a slot mid-action (_openInProgress, or Blizzard's isLocked): reusing a still-resolving container strands it.
                if info and info.itemID and not info.isLocked and not _openInProgress[key] then
                    if IsWarboundExcluded(item.bag, item.slot)
                        or ShouldHoldCappedArtisanPayout(info.itemID) then
                        return step(idx + 1)
                    end
                    if _openableCache[info.itemID] and not _failedItems[info.itemID] then
                        local prevID = info.itemID
                        local prevCount = info.stackCount or 1
                        _openInProgress[key] = true
                        _pendingOpen = { bag = item.bag, slot = item.slot,
                            itemID = prevID, count = prevCount }
                        AODbg(("open bag=%d slot=%d item=%d"):format(
                            item.bag, item.slot, prevID))
                        C_Container.UseContainerItem(item.bag, item.slot)
                        C_Timer.After(0.5, function()
                            -- Always release the slot flag; a stale-generation chain
                            -- stops here since its verdict would race the cycle that replaced it.
                            _openInProgress[key] = nil
                            -- No loot window claimed this open by now: drop the attribution so an unrelated later window can't inherit it.
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
                                -- Unchanged, unlocked, no loot window => genuine failure.
                                -- A still-locked slot is just slow, so it's left uncached for a later retry.
                                _failedItems[prevID] = true
                                AODbg("genuine fail, item=" .. prevID)
                            end
                            -- A real open resolved: pace before advancing. Non-actionable skips above advance unpaced.
                            PaceNext(idx + 1)
                        end)
                        return
                    end
                end
                C_Timer.After(0.1, function() step(idx + 1) end)
            end

            -- Paces the step AFTER a real open resolves: if something else just touched
            -- the bags (e.g. Blizzard's item delivery), let it settle first. Mailbox is covered separately (pause while open, settle after close).
            PaceNext = function(idx)
                if myGen ~= _cycleGen then return end
                local extra, why = 0, nil
                if GetTime() - _lastBagChurn < CHURN_SETTLE_WINDOW then
                    extra, why = CHURN_SETTLE_DELAY, "churn"
                end
                if extra > 0 then
                    AODbg(("pacing +%.1fs (%s)"):format(extra, why))
                    C_Timer.After(extra, function() step(idx) end)
                else
                    step(idx)
                end
            end

            C_Timer.After(0.15, function() step(1) end)
        end

        -- Coalesce a burst of BAG_UPDATE_DELAYED (a single open fires several) into one next-frame scan; skips while a cycle is in flight.
        RequestScan = function()
            -- Dropped mid-cycle: remembered so finish() re-scans even with no progress.
            if _openBusy then _missedScan = true; return end
            if _scanScheduled then return end
            _scanScheduled = true
            C_Timer.After(0, function()
                _scanScheduled = false
                ScanAndOpen(false)
            end)
        end

        containerFrame:SetScript("OnEvent", function(_, event, interactionType)
            if event == "BAG_UPDATE" then
                _lastBagChurn = GetTime()
                return
            end
            if event == "LOOT_OPENED" then
                _lootOpen = true
                -- Claim the window for the container just used, so LOOT_CLOSED knows which slot to re-examine.
                _lootSource = _pendingOpen
                _pendingOpen = nil
                return
            end
            if event == "LOOT_CLOSED" then
                _lootOpen = false
                -- Delay lets the looted container leave the bag before the re-scan.
                C_Timer.After(0.5, function()
                    -- Verdict on the container that spawned this window: still there with
                    -- an un-decremented count means it couldn't be looted (bags full/unique
                    -- cap) -- skip it BEFORE re-scan or it loops forever; a locked slot (in-flight) gets no verdict.
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
            if event == "CURRENCY_DISPLAY_UPDATE" then
                if not ShouldHoldCappedArtisanPayout(ARTISAN_PAYOUT_ITEM_ID) then
                    RequestScan()
                end
                return
            end
            if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_STOP"
                or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                -- Resume only when the casting gate actually deferred work -- these fire on every instant cast too, and walking bags each time would be constant overhead.
                if _missedScan and not _openBusy then
                    _missedScan = false
                    C_Timer.After(0.1, function() ScanAndOpen(false, false) end)
                end
                return
            end
            if event == "BANKFRAME_CLOSED" then
                -- Legacy path like MAIL_CLOSED below; the interaction-manager
                -- HIDE below is the live driver on retail.
                C_Timer.After(0.5, function() ScanAndOpen(false, false, true) end)
                return
            end
            if event == "MAIL_CLOSED" then
                -- Legacy, doesn't fire on retail (kept for older clients).
                C_Timer.After(0.5, function() ScanAndOpen(false, true, false) end)
                return
            end
            if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
                if interactionType == Enum.PlayerInteractionType.MailInfo then
                    -- The event that actually fires on retail; mail's own delivery can still unlock slots just after close, so settle first like LOOT_CLOSED.
                    C_Timer.After(0.5, function() ScanAndOpen(false, true, false) end)
                elseif interactionType == Enum.PlayerInteractionType.Banker
                    or interactionType == Enum.PlayerInteractionType.AccountBanker then
                    -- AccountBanker: the warband bank signals its own type, and
                    -- BankOpen() gates both (same BankFrame).
                    C_Timer.After(0.5, function() ScanAndOpen(false, false, true) end)
                end
                return
            end
            -- MERCHANT_CLOSED: interaction's over but the frame may not have hidden yet, so skip the entry gate instead of a timer.
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
            -- event; ssFrame below hides it right after Blizzard shows it.
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

        local function FreeProfessionSlots()
            if not GetProfessions then return 2 end
            local a, b = GetProfessions()
            return 2 - (a and 1 or 0) - (b and 1 or 0)
        end

        -- Purchasable given current funds/slots? Returns ok, cost, takesProfSlot.
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
                -- Descending: a purchase reindexes the list, so only already-
                -- visited (higher) indices shift and no skill is skipped.
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
                local goldStr = C_CurrencyInfo.GetCoinTextureString(gold)
                local msg = (n == 1)
                    and EllesmereUI.Lf("Learn %1$d skill for %2$s", n, goldStr)
                    or  EllesmereUI.Lf("Learn %1$d skills for %2$s", n, goldStr)
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
    -- Coin icons (opt-in via the Auto Repair cog) use the game's localized coin
    -- textures; default short text builds "12o 34a" from localized suffixes
    -- (L translates g/s -> o/a in frFR; copper "c" is untranslated).
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

    -- Junk sweep. SellAllJunkItems() is fire-and-forget: the server drops sell
    -- requests past its rate limit, and uncached item data at MERCHANT_SHOW is
    -- skipped, so one call routinely strands grays -- re-count after each pass and
    -- fire again while still falling. Gated on MERCHANT_SHOW/CLOSED, not
    -- MerchantFrame:IsShown(): the interaction (not the frame) allows selling, and the frame may not be shown yet at MERCHANT_SHOW.
    local merchantOpen = false
    local SellJunk, StopJunkSweep
    do
        -- Self-rescheduling timer, not a ticker: a fixed retry cadence against the
        -- same limiter that ate the pass just gets eaten again, so the delay backs off instead.
        local BASE_DELAY  = 0.4
        local MAX_DELAY   = 1.6
        local MAX_PASSES  = 12
        local MAX_STALLS  = 3
        local pending, passes, lastCount, stalls, warned, delay

        local function CountJunk()
            local junk, unknown = 0, 0
            for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID then
                        if info.quality == nil then
                            unknown = unknown + 1
                        elseif info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                            junk = junk + 1
                        end
                    end
                end
            end
            return junk, unknown
        end

        StopJunkSweep = function()
            if pending then pending:Cancel(); pending = nil end
        end

        local Pass
        local function Schedule()
            pending = C_Timer.NewTimer(delay, Pass)
        end

        -- Verify-and-report, no selling: the pass-cap exit's sell is still in flight, so only a re-count after the server answers says what stranded.
        local function Report()
            pending = nil
            if not merchantOpen then return end
            local left = CountJunk()
            if left > 0 and not warned then
                warned = true
                EllesmereUI.Print("|cff0cd29dEllesmereUI:|r " ..
                    EllesmereUI.Lf("%d junk item(s) could not be sold.", left))
            end
        end

        Pass = function()
            pending = nil
            if not merchantOpen then return end
            if EllesmereUIDB and EllesmereUIDB.autoSellJunk == false then return end

            local junk, unknown = CountJunk()
            if junk == 0 and unknown == 0 then return end

            passes = passes + 1
            if junk > lastCount then
                -- Count ROSE: uncached slots resolved into newly visible junk --
                -- discovery, not a stall (the case this sweep exists for).
                stalls, delay = 0, BASE_DELAY
            elseif junk == lastCount then
                -- Nothing shifted: either unsellable (refundable purchases open a
                -- confirm popup) or the limiter dropped the request -- indistinguishable, so back off before giving up.
                stalls = stalls + 1
                delay = math.min(delay * 2, MAX_DELAY)
                if stalls >= MAX_STALLS then
                    if junk > 0 and not warned then
                        warned = true
                        EllesmereUI.Print("|cff0cd29dEllesmereUI:|r " ..
                            EllesmereUI.Lf("%d junk item(s) could not be sold.", junk))
                    end
                    return
                end
            else
                stalls, delay = 0, BASE_DELAY
            end

            lastCount = junk
            -- Only round-trip when there's something to sell; junk-free is just waiting on item data to cache.
            if junk > 0 then C_MerchantFrame.SellAllJunkItems() end
            if passes >= MAX_PASSES then
                -- Cap hit while still moving; bailing silently is the exact failure this sweep fixes, so hand off one verification pass.
                pending = C_Timer.NewTimer(delay, Report)
                return
            end
            Schedule()
        end

        SellJunk = function()
            if not (C_MerchantFrame and C_MerchantFrame.SellAllJunkItems) then return end
            StopJunkSweep()
            passes, lastCount, stalls, warned = 0, math.huge, 0, false
            delay = BASE_DELAY
            -- Pass reschedules itself only when there's more to do, so a no-gray visit costs one bag scan and arms no timer.
            Pass()
        end
    end

    -- Auto-repair result watcher. RepairAllItems(true) never fails for lack of guild
    -- funds -- the server pays what the allowance covers and silently charges the
    -- player the rest, so success alone doesn't say who paid. GetGuildBankMoney()
    -- (GuildRepairFunds) reads 0 until a guild bank opens this session, so it's a
    -- ceiling only. Share is deduced from the player's ledger (outgoing sums only),
    -- immune to an incoming credit except one sharing the SAME PLAYER_MONEY event (nets off) -- hence the caller holds the junk sweep until the debit lands.
    local repairWatcher, repairWatchLast, repairWatchOut
    local repairWatchGen = 0
    local repairWatchSweep  -- junk sweep on hold; see ReleaseJunkSweep

    -- Mirrors Blizzard's guild-repair tooltip: today's remaining allowance, bounded by balance; -1 means an unlimited rank.
    local function GuildRepairFunds()
        local allowance = GetGuildBankWithdrawMoney()
        local balance = GetGuildBankMoney()
        if allowance < 0 or allowance > balance then return balance end
        return allowance
    end

    -- Total, then guild's share; spelled out only on a split bill since a wholly guild-funded one is unambiguous from the suffix alone.
    local function ReportRepairOutcome(guildPart, ownPart)
        local line = EllesmereUI.Lf("Repaired all items for %s", RepairCostString(guildPart + ownPart))
        if guildPart > 0 then
            line = line .. EllesmereUI.L(" (guild bank)")
            if ownPart > 0 then line = line .. " " .. RepairCostString(guildPart) end
        end
        EllesmereUI.Print("|cff0CD29DEllesmereUI:|r " .. line)
    end

    local function ReportRepairBroke()
        EllesmereUI.Print("|cff0CD29DEllesmereUI:|r |cffff6060" .. EllesmereUI.L("Not enough gold to repair.") .. "|r")
    end

    -- Releases the held-back junk sweep. Idempotent: debit or settle timer, whichever arrives first, starts it.
    local function ReleaseJunkSweep()
        local sweep = repairWatchSweep
        repairWatchSweep = nil
        if sweep then sweep() end
    end

    -- A remainder can outlive the watch, so it gets its own waiter instead of a
    -- verdict at the half-second mark: the held-back junk sweep often pays the rest,
    -- its first sale barely landed by then. Ends on enough gold, merchant close, or deadline (only then is broke declared).
    local TOPUP_WINDOW = 8  -- outlasts a full junk sweep (12 passes backing off to 1.6s)
    local repairTopUp, repairTopUpGen = nil, 0

    local function CancelRepairTopUp()
        repairTopUpGen = repairTopUpGen + 1
        if repairTopUp then
            repairTopUp:UnregisterAllEvents()
            repairTopUp:SetScript("OnEvent", nil)
        end
    end

    local function StartRepairTopUp(remainCost)
        CancelRepairTopUp()
        if not repairTopUp then
            repairTopUp = CreateFrame("Frame", "EUI_RepairTopUp", UIParent)
        end
        local gen = repairTopUpGen
        local settled = false

        local function Finish(afford)
            settled = true
            CancelRepairTopUp()
            -- Giving up isn't the same as being broke: gold still in pocket is nobody's fault.
            if not afford then
                if GetMoney() < remainCost then ReportRepairBroke() end
                return
            end
            -- Re-read: seconds have passed, player may have repaired by hand, so the armed figure can't be trusted.
            local nowCost, stillNeed = GetRepairAllCost()
            if not (stillNeed and nowCost > 0) then return end
            RepairAllItems(false)
            ReportRepairOutcome(0, nowCost)
        end

        local function Poll(_, event)
            if settled or gen ~= repairTopUpGen then return end
            -- MERCHANT_CLOSED rather than merchantOpen: two frames listening for
            -- the same event have no defined order, so the flag may not be down yet
            if event == "MERCHANT_CLOSED" or not CanMerchantRepair() then return Finish(false) end
            if GetMoney() >= remainCost then return Finish(true) end
        end

        Poll()
        if settled then return end
        repairTopUp:SetScript("OnEvent", Poll)
        repairTopUp:RegisterEvent("PLAYER_MONEY")
        repairTopUp:RegisterEvent("MERCHANT_CLOSED")
        C_Timer.After(TOPUP_WINDOW, function()
            if settled or gen ~= repairTopUpGen then return end
            Finish(false)
        end)
    end

    local function OnRepairWatchEvent()  -- PLAYER_MONEY: accumulate only, never decide
        local now = GetMoney()
        local spent = repairWatchLast - now
        if spent > 0 then
            repairWatchOut = repairWatchOut + spent
            -- The debit is booked, so nothing later can net against it; holding
            -- the sweep longer only risks losing the sale on a visit that ends within the window.
            ReleaseJunkSweep()
        end
        repairWatchLast = now
    end

    -- One timer settles everything: resolving early on a big-enough deduction would
    -- misread an unrelated purchase as paying the whole bill, and MERCHANT_CLOSED
    -- could fire before an in-flight deduction lands. sweep is the junk sweep this
    -- watch holds back, released on the debit or here at the latest; a watch
    -- superseded by a new merchant never gets this far, which is correct (that merchant holds its own).
    local function StartRepairWatch(cost, moneyBefore, guildFunds, sweep)
        if not repairWatcher then
            repairWatcher = CreateFrame("Frame", "EUI_RepairWatcher", UIParent)
            repairWatcher:SetScript("OnEvent", OnRepairWatchEvent)
        end

        -- The bump IS the cancellation: a timeout still pending from a previous merchant sees a stale gen and dies.
        repairWatchGen = repairWatchGen + 1
        repairWatchLast = moneyBefore
        repairWatchOut = 0
        repairWatchSweep = sweep
        CancelRepairTopUp()  -- a remainder from the last merchant is no longer payable
        repairWatcher:RegisterEvent("PLAYER_MONEY")

        local gen = repairWatchGen
        C_Timer.After(0.5, function()
            if gen ~= repairWatchGen then return end
            repairWatcher:UnregisterAllEvents()
            local remainCost, stillNeed = GetRepairAllCost()
            if not (stillNeed and remainCost > 0) then remainCost = 0 end

            local own = repairWatchOut
            local paid = cost - remainCost
            if own > paid then own = paid end
            local guildPart = paid - own

            -- Backstop for a credit sharing an event with the debit: pre-repair
            -- funds cap the deduced share. Weak alone (unread/empty bank reads 0 --
            -- exactly the guild-is-broke case), so it only ever tightens, never decides.
            if guildFunds > 0 and guildPart > guildFunds then
                guildPart = guildFunds
                own = paid - guildPart
            end

            if paid > 0 then ReportRepairOutcome(guildPart, own) end

            -- Release before handing the remainder over: funds can run dry mid-bill and the sweep's income is what the top-up waits for.
            ReleaseJunkSweep()
            if remainCost > 0 then StartRepairTopUp(remainCost) end
        end)
    end

    local merchantFrame = CreateFrame("Frame", "EUI_MerchantHandler", UIParent)
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:RegisterEvent("MERCHANT_CLOSED")
    merchantFrame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_CLOSED" then
            merchantOpen = false
            return StopJunkSweep()
        end
        merchantOpen = true
        if not EllesmereUIDB then return end

        local sweep = (EllesmereUIDB.autoSellJunk ~= false) and SellJunk or nil

        -- Auto repair goes first; on the guild path the junk sweep is handed to
        -- the watcher instead of started here, since sale income sharing a
        -- PLAYER_MONEY event with the debit would net against it and credit the
        -- whole bill to the guild bank. Held back only until the debit lands.
        if EllesmereUIDB.autoRepair ~= false and CanMerchantRepair() then
            local cost, canRepair = GetRepairAllCost()
            if canRepair and cost > 0 then
                -- No affordability test on purpose: Blizzard's own button just calls
                -- RepairAllItems(true) and lets the server split the bill -- gating on "guild covers it all" would bill the player the lot.
                local useGuild = (EllesmereUIDB.autoRepairGuild ~= false)
                    and IsInGuild()
                    and CanGuildBankRepair()

                if not useGuild and GetMoney() < cost then
                    ReportRepairBroke()  -- nothing was spent, so nothing to watch
                elseif useGuild then
                    -- Both readings must predate the repair; only matter when the guild bank is in play.
                    local moneyBefore, guildFunds = GetMoney(), GuildRepairFunds()
                    RepairAllItems(true)
                    -- Reports once the real payer is known; the sweep rides along, let go the moment the ledger is safe.
                    StartRepairWatch(cost, moneyBefore, guildFunds, sweep)
                    return
                else
                    RepairAllItems(false)
                    ReportRepairOutcome(0, cost)  -- own gold: no ambiguity, report now
                end
            end
        end

        if sweep then sweep() end
    end)

    ---------------------------------------------------------------------------
    --  Quick Loot -- frame created lazily on first enable; LOOT_READY
    --  registers/unregisters with the toggle so it applies live and costs zero when off.
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
        local autoSkipArmed = false

        -- CancelScene() is hardware-gated: blocked from an event handler but
        -- allowed while processing a key press, so auto skip arms a one-shot
        -- cancel the key hooks consume on the cutscene's first keypress.
        local function ConsumeArmedSkip()
            if not autoSkipArmed then return end
            if not (EllesmereUIDB and EllesmereUIDB.skipCinematicsAuto) then return end
            if not (CinematicFrame and CinematicFrame:IsShown()) then return end
            autoSkipArmed = false
            if CinematicFrame.isRealCinematic then
                StopCinematic()
            elseif CanCancelScene and CanCancelScene() then
                CancelScene()
            end
        end

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

            CinematicFrame:HookScript("OnKeyDown", ConsumeArmedSkip)
        end

        local cinEventFrame = CreateFrame("Frame")
        cinEventFrame:RegisterEvent("CINEMATIC_START")
        cinEventFrame:RegisterEvent("CINEMATIC_STOP")
        cinEventFrame:RegisterEvent("PLAY_MOVIE")
        cinEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        cinEventFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_ENTERING_WORLD" then
                self:UnregisterEvent("PLAYER_ENTERING_WORLD")
                SetupCinematicHooks()
                return
            end
            if event == "CINEMATIC_STOP" then
                autoSkipArmed = false
                return
            end
            if not (EllesmereUIDB and EllesmereUIDB.skipCinematicsAuto) then return end
            if event == "CINEMATIC_START" then
                -- Real cinematics can still be stopped from event context;
                -- scenes are left to the armed key-press cancel.
                autoSkipArmed = true
                if CinematicFrame and CinematicFrame.isRealCinematic then
                    StopCinematic()
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

        -- Hooks install only on enable, so nothing touches LFG unless in use.
        -- hooksecurefunc/HookScript can't be undone, so bodies keep a setting
        -- guard for toggle-off; the role-check event alone registers/unregisters live for true zero cost when off.
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

            -- Auto-accept role check; Holding Shift skips it so the dialog stays open (e.g. to type a signup note).
            if LFGListApplicationDialog then
                LFGListApplicationDialog:HookScript("OnShow", function(self)
                    if not (EllesmereUIDB and EllesmereUIDB.quickSignup) then return end
                    if self.SignUpButton:IsEnabled() and not IsShiftKeyDown() then
                        self.SignUpButton:Click()
                    end
                end)
            end

            -- Classic Dungeon Finder role check
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

        -- Called at load and from the options toggle: installs hooks on first enable and matches role-check event registration.
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
                -- Apply-phase search result is SECRET: activityID can be secret and
                -- activityIDs a secret table whose indexing throws. Guard every read; degrade to nil rather than erroring the dialog.
                pcall(function()
                    -- Cleared up-front so a mid-read throw can't leave a stale activityID from a previous dialog open.
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
    --  Hide Blizzard Party / Raid Manager frame -- implemented in the parent
    --  (EllesmereUI_BlizzardParty.lua) so Raid Frames shares the same logic +
    --  saved setting; QoL toggle drives it via EllesmereUI._applyHideBlizzardPartyFrame.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Hide Talking Head Frame (the NPC dialogue rectangle during quests/dungeons)
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
    --  Hide Loot Rolls Window (GroupLootHistoryFrame) -- the running list of
    --  what dropped, who rolled what, and who won. Two modes off one toggle:
    --  hide it outright, or let it appear and close itself after a delay.
    --
    --  Blizzard re-shows the window on every drop and roll result, so a single
    --  Hide() never sticks -- enforcement has to ride the show path. BOTH the
    --  OnShow script and the Show method are hooked: a drop landing while the
    --  window is already up re-calls Show() without firing OnShow, and that is
    --  exactly when the auto-close delay has to restart.
    --
    --  The window is unprotected and purely informational (no secure state, no
    --  managed-position involvement), so a plain Hide() is safe. Nothing is
    --  unregistered or reparented either, so turning the toggle back off hands
    --  the window straight back to Blizzard without a reload.
    ---------------------------------------------------------------------------
    do
        local DEFAULT_DELAY = 5
        local closeGen = 0  -- bumped on every show; invalidates older timers

        local function HistoryFrame()
            local f = _G.GroupLootHistoryFrame
            if not f or not f.HookScript then return nil end
            if f.IsForbidden and f:IsForbidden() then return nil end
            return f
        end

        local function CloseDelay()
            local d = EllesmereUIDB and EllesmereUIDB.lootHistoryDelay
            if type(d) ~= "number" or d <= 0 then return DEFAULT_DELAY end
            return d
        end

        local function Enforce()
            if not (EllesmereUIDB and EllesmereUIDB.hideLootHistory) then return end
            local f = HistoryFrame()
            if not f then return end
            closeGen = closeGen + 1
            if EllesmereUIDB.lootHistoryMode ~= "autoclose" then
                f:Hide()
                return
            end
            local gen = closeGen
            C_Timer.After(CloseDelay(), function()
                -- A newer show (or a settings change) armed its own timer.
                if gen ~= closeGen then return end
                if not (EllesmereUIDB and EllesmereUIDB.hideLootHistory) then return end
                local live = HistoryFrame()
                if live and live:IsShown() then live:Hide() end
            end)
        end

        local function HookHistory()
            local f = HistoryFrame()
            if not f or EllesmereUI._GetFFD(f).lootHistHooked then return end
            EllesmereUI._GetFFD(f).lootHistHooked = true
            f:HookScript("OnShow", Enforce)
            hooksecurefunc(f, "Show", Enforce)
        end

        -- Hook now, or arm ONE waiter for the frame's Blizzard_ addon (it is
        -- created on first use, not necessarily at login). Shared by the
        -- load-time install and a mid-session enable that beats the frame's
        -- creation -- without the waiter half, that enable would silently
        -- never hook.
        local waiterArmed = false
        local function EnsureInstalled()
            if _G.GroupLootHistoryFrame then
                HookHistory()
                return
            end
            if waiterArmed then return end
            waiterArmed = true
            local waiter = CreateFrame("Frame")
            waiter:RegisterEvent("ADDON_LOADED")
            waiter:SetScript("OnEvent", function(self)
                if _G.GroupLootHistoryFrame then
                    HookHistory()
                    self:UnregisterAllEvents()
                end
            end)
        end

        -- Options-side apply: a toggle must bite now, not on the next drop.
        -- The closeGen bump also cancels a pending auto-close when the mode
        -- changes or the feature is switched off mid-countdown.
        EllesmereUI._applyHideLootHistory = function()
            if EllesmereUIDB and EllesmereUIDB.hideLootHistory then
                EnsureInstalled()
            end
            closeGen = closeGen + 1
            local f = HistoryFrame()
            if f and f:IsShown() then Enforce() end
        end

        -- Load-time install ONLY for users with the feature already on
        -- (zero cost disabled: no waiter frame, no ADDON_LOADED listener,
        -- no hooks -- a later enable installs through _applyHideLootHistory
        -- above).
        if EllesmereUIDB and EllesmereUIDB.hideLootHistory then
            EnsureInstalled()
        end
    end

    ---------------------------------------------------------------------------
    --  Instance Reset Announce -- after a successful /reset, posts to instance
    --  chat so the group knows it's ready to re-enter.
    ---------------------------------------------------------------------------
    do
        local playerName = UnitName("player") or "Unknown"

        -- Success detected from Blizzard's CHAT_MSG_SYSTEM confirmation; the string varies by locale, so match common substrings across clients.
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
            -- CHAT_MSG_SYSTEM fires for every system message all session (this frame
            -- stays registered while the toggle is on, not just around /reset), and some
            -- carry secret text in protected content. Bail before touching msg at all.
            if issecretvalue and issecretvalue(msg) then return end
            if not (EllesmereUIDB and EllesmereUIDB.instanceResetAnnounce) then return end

            -- Instance group only: LE_PARTY_CATEGORY_INSTANCE covers party/raid; IsInGroup() is the older-API fallback.
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

        -- CHAT_MSG_SYSTEM fires for all system chat, so registered only while on (toggle re-applies live).
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
    --  24-Hour Clock Fix -- Blizzard's timeMgrUseMilitaryTime CVar resets to 12h
    --  on every login; save the user's choice on toggle, restore it on login.
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
        -- Track: hook the checkbox to remember user changes
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
    local floor = math.floor

    -- Single-string layout: one FontString, "Label:  value" per row. The
    -- two-column split (separate right-justified values FontString) was
    -- reverted -- per-column sizing/anchor interplay caused more issues
    -- than the aligned numbers were worth.
    local ROW_GAP = 3    -- extra pixels between rows (SetSpacing)

    -- Dim span for the attached FPS rows, which build their own bodies. Every
    -- span opens and closes rather than nesting, since |r restores one level
    -- only.
    local DIM = "|cff9d9d9d"

    -- Gap between a label and its figure, and either side of the latency
    -- divider so the whole block keeps one rhythm.
    local LABEL_GAP = " "

    -- Per-stat label colors, used when no custom color is picked in options.
    -- One hue per secondary so the rows scan at a glance; tertiaries share a
    -- single distinct hue so the block reads as its own group.
    local STAT_HEX = {
        crit    = "ffd100",   -- gold
        haste   = "2ecc71",   -- green
        mastery = "55aaff",   -- blue
        vers    = "c77dff",   -- violet
    }
    local DEFAULT_STAT_ORDER = {
        "crit", "haste", "mastery", "vers", "leech", "avoidance", "speed",
    }
    local VALID_STAT = {
        crit = true, haste = true, mastery = true, vers = true,
        leech = true, avoidance = true, speed = true,
    }

    local function SecondaryStatsOrder()
        local saved = EllesmereUI.QoLExtrasGet("secondaryStatsOrder")
        if type(saved) ~= "table" then return DEFAULT_STAT_ORDER end

        local order, added = {}, {}
        for _, key in ipairs(saved) do
            if VALID_STAT[key] and not added[key] then
                added[key] = true
                order[#order + 1] = key
            end
        end
        for _, key in ipairs(DEFAULT_STAT_ORDER) do
            if not added[key] then order[#order + 1] = key end
        end
        return order
    end
    EllesmereUI._secondaryStatsOrder = SecondaryStatsOrder
    -- Tertiaries keep the original default: the player's class color.

    -- SECRET STATS. In restricted content the stat getters return secret
    -- numbers. A secret refuses INSPECTION -- compare one, do arithmetic on
    -- one, or format one in Lua, and that errors -- but it renders perfectly
    -- through an engine sink. SetFormattedText is such a sink (see the CDM
    -- timer and the inspect sheet's M+ score), so every figure below is passed
    -- to it as an ARGUMENT against a template built only from clean data.
    -- That is what keeps the block live in combat instead of reading "?".
    --
    -- The one thing a secret still costs is measurement: GetStringWidth errors
    -- on a FontString that was fed one, so the block keeps its last known size
    -- until the values are readable again (see UpdateSecondaryStats).
    --
    -- Labels are interpolated INTO that template, so a "%" in a translation
    -- would become a stray format spec. Escape it.
    local function Esc(s)
        return (tostring(s):gsub("%%", "%%%%"))
    end

    -- Set when a figure is genuinely absent (nil) -- NOT when it is merely
    -- secret, which now renders fine.
    local statUnreadable = false

    -- Load-in settle heal: the login/zone-in window can outlast the first paint
    -- AND every stat event, leaving a nil figure reading "?" until gear swaps.
    -- There is no event for that settle, so a paint that saw one arms ONE
    -- bounded retry chain -- never a loop: the budget stops it, and a clean
    -- paint resets it.
    local _healPending = false
    local UpdateSecondaryStats

    local function ArmSecretHeal()
        if _healPending then return end
        local tries = statsFrame._secretHeals or 0
        if tries >= 5 then return end
        statsFrame._secretHeals = tries + 1
        _healPending = true
        C_Timer.After(2, function()
            _healPending = false
            UpdateSecondaryStats()
        end)
    end

    -- Latency sources for the attached rows. Local MS defaults to ON when the
    -- setting has never been written, matching the standalone counter.
    local function LatencySources()
        local _localMS = EllesmereUI.QoLExtrasGet("fpsShowLocalMS")
        local showLocal = (_localMS == nil) and true or _localMS
        return EllesmereUI.QoLExtrasGet("fpsShowWorldMS"), showLocal
    end

    -- Position authority. A center names a corner only once you know the size,
    -- so a CENTER/CENTER anchor walks a text-sized block sideways by half of
    -- every width change -- a digit on the latency, a row appearing -- and puts
    -- it somewhere new on each reload. This block stores an EDGE anchor
    -- instead, the convention the growth-direction bars already use, after
    -- which nothing about its size can move it.
    --
    -- Whole pixels: a center lands on a half pixel at odd sizes, and text drawn
    -- from a fractional origin is free to round either way.
    local function CornerFromCenter(cx, cy, w, h)
        return floor(UIParent:GetWidth() / 2 + cx - w / 2 + 0.5),
               floor(UIParent:GetHeight() / 2 + cy + h / 2 + 0.5)
    end
    EllesmereUI._secondaryStatsCorner = CornerFromCenter

    local function ApplyStatsPosition()
        -- Unlock mode owns positioning while a session is open.
        if not statsFrame or EllesmereUI._unlockActive then return end
        local pos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
        if not (pos and pos.point) then return end
        -- Saved as a center by an earlier build. Resolve it once, at a size we
        -- know is real, and keep the corner from then on -- otherwise it would
        -- go on resolving to a different corner for the life of the profile.
        if pos.point == "CENTER" and statsFrame._measured then
            local copy = {}
            for k, v in pairs(pos) do copy[k] = v end
            copy.point, copy.relPoint = "TOPLEFT", "BOTTOMLEFT"
            copy.x, copy.y = CornerFromCenter(pos.x or 0, pos.y or 0,
                statsFrame:GetWidth(), statsFrame:GetHeight())
            EllesmereUI.QoLExtrasSet("secondaryStatsPos", copy)
            pos = copy
        end
        statsFrame:ClearAllPoints()
        statsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
    -- For the unlock element, registered in the FPS block below.
    EllesmereUI._secondaryStatsPin = ApplyStatsPosition

    function UpdateSecondaryStats()
        if not statsFrame or not statsFrame:IsShown() then return end
        statUnreadable = false
        if not statsFrame._classHex then
            -- Cache ONLY a resolved class color: caching the white fallback
            -- here left class-colored labels white for the whole session
            -- when the first paint beat the color system (login timing) --
            -- invisible against bright scenes. Unresolved = retry next
            -- update, white per-use below. issecretvalue FIRST: UnitClass
            -- returns a secret in restricted content and truthiness on it
            -- throws (a /reload inside an instance killed every update).
            local _, cls = UnitClass("player")
            if issecretvalue(cls) then cls = nil end
            local cc = cls and EllesmereUI.GetClassColor(cls)
            if cc then
                statsFrame._classHex = format("%02x%02x%02x",
                    cc.r * 255, cc.g * 255, cc.b * 255)
            end
        end
        -- Label color mode: "palette" (multicolored, one hue per stat),
        -- "class" (default), or "custom". No mode saved: a stored custom
        -- color means the user was using it, so custom wins; otherwise class
        -- color, the pre-mode default look.
        local c = EllesmereUI.QoLExtrasGet("secondaryStatsColor")
        local mode = EllesmereUI.QoLExtrasGet("secondaryStatsColorMode")
            or (c and "custom" or "class")
        local customHex
        if mode == "custom" and c then
            customHex = format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        elseif mode == "class" then
            -- Per-use white fallback while the class color is still
            -- resolving; never cached, so the real color takes over.
            customHex = statsFrame._classHex or "ffffff"
        end

        local crit = GetCritChance("player")
        local haste = UnitSpellHaste("player")
        local mastery = GetMasteryEffect()
        -- Versatility is the only row built by ADDING two getters, and addition
        -- is what a secret refuses -- so under restriction the real total is
        -- not computable here. Blizzard's pane still shows it (its code reads
        -- true values; an addon gets secrets), which is why the two disagreed.
        -- Falling back to the rating alone silently drops the non-rating bonus,
        -- so remember the last clean total and show that instead; "?" is the
        -- floor when there has never been a clean read.
        local versRating = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
        local versBase = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
        local vers
        if issecretvalue(versRating) or issecretvalue(versBase) then
            vers = statsFrame._versLastClean   -- nil until one exists -> "?"
        else
            vers = versRating + versBase
            statsFrame._versLastClean = vers
        end
        local showBoth = EllesmereUI.QoLExtrasGet("showSecondaryStatsBoth")
        local showRawOnly = not showBoth and EllesmereUI.QoLExtrasGet("showSecondaryStatsRaw")
        local showRawValues = showRawOnly or showBoth
        local critRaw, hasteRaw, masteryRaw, versRaw
        if showRawValues then
            critRaw = GetCombatRating(CR_CRIT_MELEE)
            hasteRaw = GetCombatRating(CR_HASTE_MELEE)
            masteryRaw = GetCombatRating(CR_MASTERY)
            versRaw = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)
        end

        -- One template line per row, plus the figures to fill it. Nothing here
        -- reads a figure -- see the SECRET STATS note above.
        local rows, vals = {}, {}
        local anySecret = false
        -- Values are white unless Colored Values is on, which colors
        -- each value with its row so the stat reads as one piece.
        local coloredPct = EllesmereUI.QoLExtrasGet("coloredPercentages")
        local abbreviateLabels = EllesmereUI.QoLExtrasGet("secondaryStatsAbbreviateLabels")
        local function Label(long, short)
            return abbreviateLabels and short or EllesmereUI.L(long)
        end
        local function Row(hex, label, value, raw)
            local body, first, second
            if showRawOnly then
                body, first = "%.0f", raw
            elseif showBoth then
                body, first, second = "%.0f (%.2f%%)", raw, value
            else
                body, first = "%.2f%%", value
            end
            -- The selected figures travel as arguments so secret values are
            -- never inspected. A nil test is safe on a secret.
            if first == nil or (showBoth and second == nil) then
                statUnreadable = true
                body = "?"
            else
                if issecretvalue(first) then anySecret = true end
                vals[#vals + 1] = first
                if showBoth then
                    if issecretvalue(second) then anySecret = true end
                    vals[#vals + 1] = second
                end
            end
            rows[#rows + 1] = format("|cff%s%s:|r%s|cff%s%s|r",
                hex, Esc(label), LABEL_GAP, coloredPct and hex or "ffffff", body)
        end
        -- Sibling for rows whose body is already colored (the FPS pair below):
        -- Row would wrap it in a second span, and |r restores one level only.
        -- Those bodies apply Colored Values themselves, per figure, and are
        -- built from figures that are never secret -- so they carry no
        -- placeholder and must be escaped like any other template text.
        local function RawRow(hex, label, body)
            rows[#rows + 1] = format("|cff%s%s:|r%s%s",
                hex, Esc(label), LABEL_GAP, Esc(body))
        end
        local hiddenStats = EllesmereUI.QoLExtrasGet("secondaryStatsHidden")
        if type(hiddenStats) ~= "table" then hiddenStats = nil end
        local hasVisibleTertiary = not (hiddenStats
            and hiddenStats.leech and hiddenStats.avoidance and hiddenStats.speed)
        local tertHex, leech, avoidance, speed
        local leechRaw, avoidanceRaw, speedRaw
        if hasVisibleTertiary then
            local tc = EllesmereUI.QoLExtrasGet("tertiaryStatsColor")
            local tmode = EllesmereUI.QoLExtrasGet("tertiaryStatsColorMode")
                or (tc and "custom" or "class")
            tertHex = (tmode == "custom" and tc)
                and format("%02x%02x%02x", tc.r * 255, tc.g * 255, tc.b * 255)
                or statsFrame._classHex or "ffffff"

            leech = GetLifesteal()
            avoidance = GetAvoidance()
            speed = GetSpeed()
            if showRawValues then
                leechRaw = GetCombatRating(CR_LIFESTEAL)
                avoidanceRaw = GetCombatRating(CR_AVOIDANCE)
                speedRaw = GetCombatRating(CR_SPEED)
            end
        end

        for _, key in ipairs(SecondaryStatsOrder()) do
            if not (hiddenStats and hiddenStats[key]) then
                if key == "crit" then
                    Row(customHex or STAT_HEX.crit, Label("Crit", "C"), crit, critRaw)
                elseif key == "haste" then
                    Row(customHex or STAT_HEX.haste, Label("Haste", "H"), haste, hasteRaw)
                elseif key == "mastery" then
                    Row(customHex or STAT_HEX.mastery, Label("Mastery", "M"), mastery, masteryRaw)
                elseif key == "vers" then
                    Row(customHex or STAT_HEX.vers, Label("Vers", "V"), vers, versRaw)
                elseif key == "leech" then
                    Row(tertHex, Label("Leech", "L"), leech, leechRaw)
                elseif key == "avoidance" then
                    Row(tertHex, Label("Avoidance", "A"), avoidance, avoidanceRaw)
                elseif key == "speed" then
                    Row(tertHex, Label("Speed", "S"), speed, speedRaw)
                end
            end
        end

        -- FPS and latency, drawn here rather than by the standalone counter
        -- while Attach to Secondary Stats is on. Label color comes from the FPS
        -- swatch, falling back to class color like the other groups.
        if EllesmereUI.QoLExtrasGet("fpsAttachToStats")
           and EllesmereUI.QoLExtrasGet("showFPS") then
            -- Same resolver the standalone counter uses, so the two owners
            -- cannot disagree about the color.
            local fr, fg, fb = EllesmereUI._fpsColorRGB()
            local fpsHex = format("%02x%02x%02x", fr * 255, fg * 255, fb * 255)
            -- The figures follow Colored Values with the rest of the block.
            -- The "(world)"/"(local)" suffixes and the divider stay dim either
            -- way -- they are annotations, not values.
            local VAL = "|cff" .. (coloredPct and fpsHex or "ffffff")

            RawRow(fpsHex, EllesmereUI.L("FPS"),
                VAL .. floor(GetFramerate() + 0.5) .. "|r")

            local showWorld, showLocal = LatencySources()
            if showWorld or showLocal then
                local hideLabel = EllesmereUI.QoLExtrasGet("fpsHideLabel")
                local _, _, latHome, latWorld = GetNetStats()
                local parts = {}
                if showWorld then
                    parts[#parts + 1] = VAL .. latWorld .. " ms|r"
                        .. (hideLabel and "" or (DIM .. " (world)|r"))
                end
                if showLocal then
                    parts[#parts + 1] = VAL .. latHome .. " ms|r"
                        .. (hideLabel and "" or (DIM .. " (local)|r"))
                end
                -- The divider takes LABEL_GAP on both sides. "||" renders one
                -- literal pipe.
                RawRow(fpsHex, EllesmereUI.L("Latency"),
                    table.concat(parts, LABEL_GAP .. DIM .. "||" .. "|r" .. LABEL_GAP))
            end
        end

        -- The engine fills the template. This is the whole point: a secret
        -- figure is never read in Lua, so it draws its true number.
        statsText:SetFormattedText(table.concat(rows, "\n"), unpack(vals))

        -- Measuring is the one thing a secret costs us: GetStringWidth errors
        -- on a FontString that was fed one. Keep the last known size until the
        -- figures are readable again -- only the unlock drag box and the corner
        -- migration below read it, and both can wait for the end of combat
        -- (PLAYER_REGEN_ENABLED is registered, so that repaint comes).
        local staleSize = false
        if not anySecret then
            -- Clean figures do NOT buy a clean measurement: the metrics belong
            -- to the last LAID OUT string, so the first paint AFTER a secret
            -- one still hands back a secret width -- which is what errored
            -- here. Test what the arithmetic is about to touch, not what was
            -- fed in.
            local w, h = statsText:GetStringWidth(), statsText:GetStringHeight()
            if issecretvalue(w) or issecretvalue(h) then
                -- Nothing left to wait on but the next layout, and there is no
                -- event for that -- so borrow the bounded retry chain below.
                staleSize = true
            else
                statsFrame:SetSize(w + 2, h + 2)
                -- The block has now been measured at a real size, which is what
                -- a stored center needs before it can be resolved to a corner.
                -- Only worth a call while one is still stored; the migration
                -- runs once.
                statsFrame._measured = true
                local savedPos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                if savedPos and savedPos.point == "CENTER" then ApplyStatsPosition() end
            end
        end

        -- A missing figure and a not-yet-relaid-out measurement both heal on
        -- their own clock rather than an event, so they share the one chain.
        -- anySecret deliberately does NOT arm it: that clears on
        -- PLAYER_REGEN_ENABLED, and spending the budget on a whole fight would
        -- leave none for the settle that actually needs it.
        if statUnreadable or staleSize then
            ArmSecretHeal()
        else
            statsFrame._secretHeals = nil
        end
    end

    -- The stat rows redraw on events; FPS and latency need their own clock.
    -- Rebuilt on every apply so the interval takes effect and never doubles up.
    local function RefreshFPSTicker()
        if not statsFrame then return end
        if statsFrame._fpsTicker then
            statsFrame._fpsTicker:Cancel()
            statsFrame._fpsTicker = nil
        end
        if not (EllesmereUI.QoLExtrasGet("fpsAttachToStats")
                and EllesmereUI.QoLExtrasGet("showFPS")) then
            return
        end
        statsFrame._fpsTicker = C_Timer.NewTicker(
            EllesmereUI.QoLExtrasGet("fpsUpdateInterval") or 3, UpdateSecondaryStats)
    end

    local function ApplySecondaryStats()
        local enabled = EllesmereUI.QoLExtrasGet("showSecondaryStats")
        if not enabled then
            if statsFrame then
                statsFrame:Hide()
                statsFrame:UnregisterAllEvents()
                if statsFrame._fpsTicker then
                    statsFrame._fpsTicker:Cancel()
                    statsFrame._fpsTicker = nil
                end
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
            statsText:SetSpacing(ROW_GAP)
        end
        ApplyStatsPosition()
        local pos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
        local scale = (pos and pos.scale) or 1.0
        if statsText then
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            local fontSize = math.floor(12 * scale + 0.5)
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(statsText, EllesmereUI.GetFontUseShadow("extras")) end
            statsText:SetFont(font, fontSize, EllesmereUI.GetFontOutlineFlag("extras"))
            -- Row gap scales with the font so the block keeps its rhythm.
            statsText:SetSpacing(math.floor(ROW_GAP * scale + 0.5))
        end
        -- Unit-scoped events filter at the engine (player only); a plain RegisterEvent would deliver every raid member's stat changes.
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
            -- Combat-scoped stat secrecy lifts here. The figures themselves
            -- stay live through a fight (they render as arguments), but the
            -- block cannot be MEASURED while any of them is secret -- so this
            -- is the edge that catches its footprint back up.
            "PLAYER_REGEN_ENABLED",
        }) do
            statsFrame:RegisterEvent(ev)
        end
        local _statsPending = false
        -- No runtime unit filter: unit events are engine-filtered to player above;
        -- a `unit ~= "player"` check would wrongly swallow PLAYER_EQUIPMENT_CHANGED, whose first arg is a slot id.
        --
        -- Leading edge, then a trailing pass. COMBAT_RATING_UPDATE fires many
        -- times a second in combat, so the window has to stay -- but spending it
        -- BEFORE the first redraw is what put the block half a second behind the
        -- character sheet. Redraw at once instead, and again once the burst has
        -- settled, for the same two updates per window.
        statsFrame:SetScript("OnEvent", function()
            if _statsPending then return end
            _statsPending = true
            UpdateSecondaryStats()
            C_Timer.After(0.5, function()
                _statsPending = false
                UpdateSecondaryStats()
            end)
        end)
        statsFrame:Show()
        RefreshFPSTicker()
        UpdateSecondaryStats()
    end
    EllesmereUI._applySecondaryStats = ApplySecondaryStats

    -- The frame is sized from the text on every update, but only while it is
    -- shown. Catch it up when unlock mode opens so the mover box matches.
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EUI_SecondaryStats", function(opening)
            if opening then UpdateSecondaryStats() end
        end)
    end

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

    -- Resolved readout color, shared by this frame and the attached rows so
    -- the two owners can never disagree. No mode saved means "custom", which
    -- with no stored color is white -- the look before the mode existed, so
    -- an existing profile is unchanged.
    local function FPSColorRGB()
        if EllesmereUI.QoLExtrasGet("fpsColorMode") == "class" then
            -- issecretvalue FIRST: UnitClass returns a secret in restricted
            -- content and truthiness on one throws.
            local _, cls = UnitClass("player")
            if issecretvalue(cls) then cls = nil end
            local cc = cls and EllesmereUI.GetClassColor(cls)
            if cc then return cc.r, cc.g, cc.b, 1 end
            return 1, 1, 1, 1   -- class color not resolved yet; retry next update
        end
        local c = EllesmereUI.QoLExtrasGet("fpsColor")
        if c then return c.r or 1, c.g or 1, c.b or 1, c.a or 1 end
        return 1, 1, 1, 1
    end
    EllesmereUI._fpsColorRGB = FPSColorRGB

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
            local cr, cg, cb, ca = EllesmereUI._fpsColorRGB()
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

    -- Attached = drawn as extra rows in the Secondary Stats block rather than by
    -- this frame. Requires that block to be on, so turning it off pops the
    -- counter back to standalone instead of making it disappear.
    local function IsAttached()
        return (EllesmereUI.QoLExtrasGet("fpsAttachToStats")
            and EllesmereUI.QoLExtrasGet("showSecondaryStats")) and true or false
    end
    EllesmereUI._fpsAttachedToStats = IsAttached

    EllesmereUI._applyFPSCounter = function()
        local shouldShow = EllesmereUI.QoLExtrasGet("showFPS") and not IsAttached()
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

    local RegisterFPSUnlockElement  -- forward: defined below

    -- A settings change can move the readout between its two owners, so every
    -- FPS option writes through here rather than calling one side directly.
    EllesmereUI._applyFPSDisplay = function()
        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
        if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
        -- Re-registering is how an open unlock session gains or loses a mover,
        -- so a showFPS flip (options toggle or the keybind, both of which land
        -- here) takes effect without leaving and re-entering.
        if EllesmereUI._unlockActive then RegisterFPSUnlockElement() end
    end

    RegisterFPSUnlockElement = function()
        local MK = EllesmereUI.MakeUnlockElement
        if not MK then return end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_FPS",
                label = "FPS Counter",
                group = "General",
                order = 700,
                -- Off, or dragged by the Secondary Stats element while
                -- attached. Read live, so detaching restores the mover without
                -- re-registering.
                isHidden = function()
                    return not EllesmereUI.QoLExtrasGet("showFPS") or IsAttached()
                end,
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
    end
    C_Timer.After(2, RegisterFPSUnlockElement)

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
                -- Self-positioning: makes NotifyElementResized call applyPos
                -- below rather than re-applying a stored center over the top.
                noInitHook = true,
                savePos = function(key, point, relPoint, x, y)
                    if not point then return end
                    -- Scale lives in this same table; carry it over so a drag doesn't wipe it.
                    local prev = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                    local newPos = { point = point, relPoint = relPoint, x = x, y = y, scale = prev and prev.scale }
                    -- Rebase the center unlock mode hands back onto the corner
                    -- it currently resolves to, and store THAT -- a center would
                    -- name a different corner the moment a figure gains a digit.
                    -- Resolved against the handed-over center, not the frame's
                    -- own point, which on Save & Exit may not have moved yet.
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if f and point == "CENTER" and (relPoint or "CENTER") == "CENTER"
                       and EllesmereUI._secondaryStatsCorner then
                        newPos.point, newPos.relPoint = "TOPLEFT", "BOTTOMLEFT"
                        newPos.x, newPos.y = EllesmereUI._secondaryStatsCorner(
                            x or 0, y or 0, f:GetWidth(), f:GetHeight())
                    end
                    EllesmereUI.QoLExtrasSet("secondaryStatsPos", newPos)
                    if not EllesmereUI._unlockActive and EllesmereUI._secondaryStatsPin then
                        EllesmereUI._secondaryStatsPin()
                    end
                end,
                loadPos = function()
                    return EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                end,
                clearPos = function()
                    EllesmereUI.QoLExtrasSet("secondaryStatsPos", nil)
                end,
                -- NotifyElementResized calls this after every resize. Re-applying
                -- an edge anchor at a new size is a no-op, which is the point.
                applyPos = function()
                    if EllesmereUI._secondaryStatsPin then EllesmereUI._secondaryStatsPin() end
                end,
            }),
        })
    end)

    local fpsBind = CreateFrame("Button", "EUI_FPSBindBtn", UIParent)
    fpsBind:Hide()
    fpsBind:SetScript("OnClick", function()
        EllesmereUI.QoLExtrasSet("showFPS", not EllesmereUI.QoLExtrasGet("showFPS"))
        -- The keybind has to toggle whichever owner is drawing the readout.
        EllesmereUI._applyFPSDisplay()
    end)

    C_Timer.After(1, function()
        if EllesmereUI.QoLExtrasGet("showFPS") then
            EllesmereUI._applyFPSDisplay()
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
        fs:SetText(EllesmereUI.L("Low Durability"))
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
            durWarnOverlay._text:SetText(EllesmereUI.Lf("Low Durability (%d%%)", math.floor(pct)))
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
        durWarnOverlay._text:SetText(EllesmereUI.L("Low Durability (Preview)"))
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

    -- Durability + alert events land together per damaged slot; one check
    -- after the frame settles (the check itself returns in combat, so a flush
    -- landing after PLAYER_REGEN_DISABLED cannot re-show the warning).
    local durCheckPending = false
    local function FlushDurabilityCheck()
        durCheckPending = false
        CheckDurabilityAndShow()
    end
    repairWarnFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if durWarnOverlay then durWarnOverlay:Hide() end
            return
        end
        if durCheckPending then return end
        durCheckPending = true
        C_Timer.After(0, FlushDurabilityCheck)
    end)

    -- Events registered only while enabled; toggle re-syncs live, and one immediate check on enable surfaces an already-low item.
    EllesmereUI._syncDurWarnEvents = function()
        if EllesmereUIDB and EllesmereUIDB.repairWarning == false then
            repairWarnFrame:UnregisterAllEvents()
            if durWarnOverlay then durWarnOverlay:Hide() end
        else
            repairWarnFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            repairWarnFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            repairWarnFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            repairWarnFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            -- Self-repair items recalculate alerts without the durability event.
            repairWarnFrame:RegisterEvent("UPDATE_INVENTORY_ALERTS")
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

    -- The binding is the OR of two states with separate writers:
    --   "mov" -- the secure state driver (engine-evaluated), BOTH arms [combat]:
    --            out of combat the driver's cached value sits at 0 and never
    --            re-pushes, so it can't stomp the Lua lane below.
    --   "rc"  -- Lua-pushed OOC enemy arm. [harm] matches capturable wild pets
    --            (no macro token excludes them), so the OOC verdict is computed
    --            in Lua where UnitIsWildBattlePet can veto -- the pet-capture
    --            right-click fix. In combat this lane is suspended; pets are
    --            not capturable there.
    -- Each snippet's clear defers to the other state, so the writers compose.
    -- "combatclear" zeroes rc from a SECURE snippet at combat entry: Lua cannot
    -- SetAttribute on this protected frame in lockdown, and a stale rc=1
    -- (pulled while hovering an enemy) would otherwise pin the bind on allies
    -- for the whole fight.
    local ONSTATE_MOV = [[
        if newstate == 1 then
            self:SetBindingClick(1, "BUTTON2", "EUI_MouseLookBtn")
        elseif (self:GetAttribute("state-rc") or 0) ~= 1 then
            self:ClearBindings()
        end
    ]]
    local ONSTATE_RC = [[
        if newstate == 1 then
            self:SetBindingClick(1, "BUTTON2", "EUI_MouseLookBtn")
        elseif (self:GetAttribute("state-mov") or 0) ~= 1 then
            self:ClearBindings()
        end
    ]]
    local ONSTATE_COMBATCLEAR = [[
        if newstate == 1 then
            self:SetAttribute("state-rc", 0)
        end
    ]]

    -- OOC enemy-arm verdict, edge-memoed: one attribute push per verdict CHANGE,
    -- not per hover. All reads are clean out of combat.
    local rcLast
    local function PushRCState()
        local match = (UnitExists("mouseover")
            and not UnitIsDeadOrGhost("mouseover")
            and UnitCanAttack("player", "mouseover")
            and not UnitIsWildBattlePet("mouseover")
            and not UnitIsBattlePetCompanion("mouseover")) and 1 or 0
        if match == rcLast then return end
        rcLast = match
        stateFrame:SetAttribute("state-rc", match)
    end

    -- Registered only while the enemy toggle is on (feature-off users pay
    -- nothing); the mouseover event additionally drops during combat.
    local rcHoverFrame = CreateFrame("Frame")
    rcHoverFrame:SetScript("OnEvent", function(self, event)
        if event == "UPDATE_MOUSEOVER_UNIT" then
            PushRCState()
        elseif event == "PLAYER_REGEN_DISABLED" then
            self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
            rcLast = nil
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
            PushRCState()
        end
    end)

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
            -- Capturable pets exist only in the outdoor world, so the Lua rc
            -- lane (and its mouseover listener) runs ONLY there. In instanced
            -- content the driver owns the enemy arm unconditionally -- pure
            -- engine evaluation, zero Lua per hover, and the OOC-between-pulls
            -- suppression still works. Re-applied on PLAYER_ENTERING_WORLD so
            -- the mode follows zone transitions.
            local inInstance = IsInInstance()
            local ruleLaneOn = enemy and not inInstance
            local macro = ""
            if enemy then
                macro = macro .. (inInstance and "[@mouseover,harm,nodead]1;"
                    or "[@mouseover,harm,nodead,combat]1;")
            end
            if allyCombat then macro = macro .. "[@mouseover,help,nodead,combat]1;" end
            macro = macro .. "0"
            SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
            -- [combat] arms re-evaluate on combat edges even when the mouseover
            -- unit hasn't changed.
            SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_DISABLED")
            SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_ENABLED")
            -- Handlers before drivers so the initial evaluation lands on them.
            stateFrame:SetAttribute("_onstate-mov", ONSTATE_MOV)
            stateFrame:SetAttribute("_onstate-rc", ONSTATE_RC)
            stateFrame:SetAttribute("_onstate-combatclear", ONSTATE_COMBATCLEAR)
            RegisterStateDriver(stateFrame, "mov", macro)
            RegisterStateDriver(stateFrame, "combatclear", "[combat]1;0")
            if ruleLaneOn then
                rcHoverFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
                rcHoverFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
                rcHoverFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                rcLast = nil
                PushRCState()
            else
                rcHoverFrame:UnregisterAllEvents()
                rcLast = nil
                stateFrame:SetAttribute("state-rc", 0)
            end
        else
            UnregisterStateDriver(stateFrame, "mov")
            UnregisterStateDriver(stateFrame, "combatclear")
            rcHoverFrame:UnregisterAllEvents()
            rcLast = nil
            stateFrame:SetAttribute("state-rc", 0)
            ClearOverrideBindings(stateFrame)
        end
    end

    EllesmereUI._applyRightClickTarget = ApplyRightClickTarget

    local rcInitFrame = CreateFrame("Frame")
    -- Persistent (not one-shot): the instanced-vs-outdoor mode split above is
    -- re-derived on every zone transition. Feature off = one cheap idempotent
    -- call per loading screen.
    rcInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rcInitFrame:SetScript("OnEvent", function()
        ApplyRightClickTarget()
    end)
end

-------------------------------------------------------------------------------
--  Character Crosshair
-------------------------------------------------------------------------------
do
    local crosshairFrame

    -- The account-wide EllesmereUIDB root is the inherited global default
    -- (preserved, never cleared); QoL per-profile DB holds overrides. Existing
    -- users keep their current crosshair until a profile overrides it.
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

    -- Holy-Paladin melee opt-in, cached: CrosshairGet is a DB read and the
    -- cutoff getter runs at crosshair tick cadence. The engine caches the
    -- spec-derived cutoff itself (invalidated on spec/talent churn) and keeps
    -- the druid-form check live, so this flag is the only local state left.
    local _chHpalMelee = false

    local function RefreshCrosshairCutoffRange()
        _chHpalMelee = CrosshairGet("crosshairHpalMelee") and true or false
    end
    RefreshCrosshairCutoffRange()
    -- Exposed so the crosshair options toggle can re-resolve the cutoff live.
    EllesmereUI._RefreshCrosshairCutoffRange = RefreshCrosshairCutoffRange

    EllesmereUI._getCrosshairCutoffRange = function()
        return EllesmereUI.Range_GetAttackCutoff(nil, _chHpalMelee)
    end

    -- True only when there is an attackable, living target out of range.
    local function TargetOutOfRange()
        if not (UnitExists("target") and UnitCanAttack("player", "target")
                and not UnitIsDead("target")) then
            return false
        end
        local cutoff = EllesmereUI._getCrosshairCutoffRange()

        local beyond = EllesmereUI.Range_IsBeyondAttackRange("target", cutoff)
        return beyond == nil or beyond
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

        -- Throttled recolor when the target is out of melee range. No-ops unless enabled and the class has a mapped melee spell.
        local meleeAccum = 0
        crosshairFrame:SetScript("OnUpdate", function(self, elapsed)
            meleeAccum = meleeAccum + elapsed
            if meleeAccum < 0.15 then return end
            meleeAccum = 0
            local nc = self._normalColor
            if not nc then return end
            if not CrosshairGet("crosshairMeleeColorEnabled") then
                EllesmereUI.Range_SetActive("crosshair", false)
                if self._meleeActive then
                    self._meleeActive = false
                    self._hBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                    self._vBar:SetColorTexture(nc.r, nc.g, nc.b, nc.a)
                end
                return
            end
            -- Cheap and idempotent: keeps the shared engine's activation in step with this live toggle read.
            EllesmereUI.Range_SetActive("crosshair", true)
            local outOfRange = TargetOutOfRange()
            if outOfRange ~= self._meleeActive then
                self._meleeActive = outOfRange
                local c = outOfRange and (CrosshairGet("crosshairMeleeColor") or { r = 1, g = 0, b = 0, a = 1 }) or nc
                self._hBar:SetColorTexture(c.r or 1, c.g or 0, c.b or 0, c.a or 1)
                self._vBar:SetColorTexture(c.r or 1, c.g or 0, c.b or 0, c.a or 1)
            end
        end)
    end

    -- Presets: thickness + total arm length. Options dropdown stamps these onto
    -- H/V Width/Length and they're the fallback when unset; cog sliders fine-tune.
    EllesmereUI.CROSSHAIR_PRESETS = {
        Thin   = { width = 1, length = 40 },
        Normal = { width = 2, length = 40 },
        Thick  = { width = 3, length = 40 },
    }

    -- Re-evaluates visibility on combat/zone transitions, refreshes cutoff on
    -- spec changes. Registered only while enabled (size "None" fires nothing);
    -- off->on re-reads the cutoff directly to catch changes made while unregistered.
    local visWatch = CreateFrame("Frame")
    local visWatchRegistered = false
    visWatch:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "TRAIT_CONFIG_UPDATED" then
            RefreshCrosshairCutoffRange()
        end
        -- _applyCrosshair self-guards: nil DB returns, "None" hides, and it runs
        -- the one-time migration once the profile DB is ready.
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
            -- OnUpdate stops with the frame hidden and can't release the shared range engine itself, so release it here.
            EllesmereUI.Range_SetActive("crosshair", false)
            if crosshairFrame then crosshairFrame:Hide() end
            return
        end
        SyncVisWatch(true)
        EllesmereUI.Range_SetActive("crosshair", G("crosshairMeleeColorEnabled") and true or false)

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

        -- Base colour for out-of-range recolor; melee state resets so OnUpdate re-applies the range colour next tick if still needed.
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
--  Hide Error Messages -- swallows red UIErrorsFrame spam ("Not enough rage",
--  etc.) while keeping a whitelist of useful errors visible. OnEvent override
--  installed only while the option is on; zero cost off.
-------------------------------------------------------------------------------
do
    local origOnEvent
    local installed = false

    -- Kept while the rest are hidden. Built lazily so ERR_* globals are only
    -- touched once the feature is enabled.
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

    -- "i" circles are MainHelpPlateButtons, fingerprinted by a mixin method;
    -- Blizzard_HelpPlate is load-on-demand, so resolve lazily and cache.
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

    -- Hoisted out of the pcall: one reused function, not a closure per call
    -- (runs on each panel open and each HelpTip show).
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
    -- Some Blizzard frame trees refuse GetChildren from insecure code with a usage
    -- error (house editor list rows do). This walk runs inside a ShowUIPanel hooksecurefunc, so an uncaught
    -- error would abort the panel's caller. pcall per node: a refusing frame
    -- skips only its subtree, siblings still get scanned; ScanFrame is hoisted so pcall allocates nothing per node.
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

    local function RestoreButtons()
        for btn in pairs(hiddenByUs) do
            btn:SetAlpha(1)
            btn:EnableMouse(true)
            hiddenByUs[btn] = nil
        end
    end

    -- Core hooks (HelpTip + ShowUIPanel) install once, only via ApplyHideTutorials; each body also gates on Enabled().
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
            -- No global EnumerateFrames walk here (runs inside PLAYER_LOGIN): already-open
            -- panels pick up their "i" buttons on the next ShowUIPanel.
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
--  Group Death Announcer -- shows a center-screen "<name> DIED!" alert on a
--  party/raid death. Midnight has no combat log, so deaths are detected by polling
--  group units for an alive->dead transition (feign/own death excluded). No ticker runs while off or solo.
-------------------------------------------------------------------------------
do
    local POLL_INTERVAL = 0.35
    local alertOverlay
    local ticker
    local watcher
    local installed = false
    local deadState = {}   -- [guid] = true while dead/ghost, false while alive

    local DEFAULT_TEXT_SIZE = 34

    -- Configured font size + saved position (default center-top).
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
        -- Keep the frame (and unlock-mode mover) sized to the alert text, not a fixed wide box.
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

    -- Configurable death alert sound (default "none"): cog dropdown lists
    -- bundled + SharedMedia sounds. Played on "Master" to stay audible with a
    -- low SFX slider; tables exposed on EllesmereUI for the options dropdown.
    local GROUP_DEATH_SOUND_PATHS, GROUP_DEATH_SOUND_NAMES, GROUP_DEATH_SOUND_ORDER =
        EllesmereUI.BuildAlertSoundTables()
    -- SharedMedia sounds append at PLAYER_LOGIN (boot frame below), not here:
    -- this do-block runs at addon load, before other addons register their
    -- LibSharedMedia sounds. Tables exposed now by reference, so the append fills the same ones options reads.
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

    -- Minimum gap between death sounds. On a wipe many die within/across polls,
    -- firing once per corpse; the cooldown collapses the burst into one sound.
    -- Applied only in groups larger than 5 (parties are sparse enough).
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
            -- (first sighting/rejoin) primes state silently so an already-dead member at start is never announced.
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
        -- One alert per poll (extra ShowAlert calls would just clobber each other) and at most one throttled sound.
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

    -- Fires a sample alert (with sound) so the look/sound can be checked without a real death; uses your own name/class as preview text.
    EllesmereUI._announceGroupDeathsPreview = function()
        local _, classToken = UnitClass("player")
        ShowAlert(UnitName("player"), classToken)
        PlayDeathSound()
    end

    -- Visual-only preview (used by the Text Size slider so dragging it doesn't repeatedly fire the sound).
    EllesmereUI._groupDeathShowVisual = function()
        local _, classToken = UnitClass("player")
        ShowAlert(UnitName("player"), classToken)
    end

    EllesmereUI._groupDeathPlaySound = PlayDeathSound

    -- Re-apply font size/position (called from the Text Size slider and from unlock mode on saved-position change).
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
        -- Append now, at login, once other addons have registered theirs (same
        -- timing as Chat's whisper-sound dropdown). Idempotent: skips keys
        -- already present; the tables are the same ones options and PlayDeathSound read.
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
--  Combat Alert -- center-screen text on PLAYER_REGEN_DISABLED/ENABLED. Each
--  transition has its own text/color (custom or class color); one Text Size and
--  shared unlock-mode position apply to both. "Show On" selects enter/leave/both. No events registered unless enabled.
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

    -- Effective color for a transition: player's class color when the class-color toggle is on, else the stored custom color.
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

    -- Applies configured font size and saved position (or default dead-center placement) to the overlay.
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
        -- Keep the frame (and unlock-mode mover) sized to roughly the text.
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

    -- Fires a sample alert for the given transition so the look can be checked from the options cog without a real combat change.
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

    -- Re-apply font size/position (called from the Text Size slider and from unlock mode on saved-position change).
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
--  Target Distance Text -- floating distance text for the target, movable in
--  Unlock Mode. Default format is the item-ladder bracket ("30-35"); optional
--  "30+" (spell-ladder lower bound) or "30" (minimum yards). Answers come from
--  the shared engine (EllesmereUI_Range.lua), activated only while enabled. Color by yard bracket. Off by default.
-------------------------------------------------------------------------------
do
    local distFrame
    local drv
    local evt
    local installed = false
    local acc = 0
    local DEFAULT_TEXT_SIZE = 18
    local DEFAULT_FORMAT = "range" -- "range" (30-35) | "plus" (30+) | "min" (30)
    local DEFAULT_ALIGN = "CENTER" -- "LEFT" | "CENTER" | "RIGHT"
    local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 120 }

    local function GetFormat()
        local f = EllesmereUIDB and EllesmereUIDB.targetDistanceFormat
        if f == "plus" or f == "min" or f == "range" then return f end
        return DEFAULT_FORMAT
    end

    local function GetAlign()
        local a = EllesmereUIDB and EllesmereUIDB.targetDistanceAlign
        if a == "LEFT" or a == "CENTER" or a == "RIGHT" then return a end
        return DEFAULT_ALIGN
    end

    local function ColorForYards(yards)
        if yards <= 8 then
            return 0.30, 0.95, 0.40
        elseif yards <= 15 then
            return 0.85, 0.95, 0.25
        elseif yards <= 25 then
            return 1.00, 0.85, 0.20
        elseif yards <= 40 then
            return 1.00, 0.55, 0.15
        end
        return 0.95, 0.25, 0.20
    end

    local function FormatDistance(fmt, minY, maxY)
        if fmt == "plus" then
            if not minY or minY <= 0 then return nil end
            return minY .. "+"
        elseif fmt == "min" then
            if not minY or minY <= 0 then return nil end
            return tostring(minY)
        end
        -- range (default): "30-35", or "80+" beyond the last rung; inside the closest check shows "1-X" (familiar melee band) not "0-X".
        if maxY then
            local lo = (minY and minY > 0) and minY or 1
            return lo .. "-" .. maxY
        end
        if minY and minY >= 80 then
            return "80+"
        end
        if minY and minY > 0 then
            return minY .. "+"
        end
        return nil
    end

    local function ResolveDisplay(unit)
        local fmt = GetFormat()
        if fmt == "plus" then
            local lower = EllesmereUI.Range_LowerBound(unit)
            if not lower or lower <= 0 then return nil end
            return FormatDistance("plus", lower, nil), lower
        end
        local minY, maxY = EllesmereUI.Range_ItemBracket(unit)
        if minY == nil then return nil end
        local text = FormatDistance(fmt, minY, maxY)
        if not text then return nil end
        local colorY = maxY or minY
        return text, colorY
    end

    local function SampleForFormat()
        local fmt = GetFormat()
        if fmt == "plus" then return "30+", 30 end
        if fmt == "min" then return "30", 30 end
        return "25-30", 25
    end

    local function ApplyFrameSettings()
        if not distFrame then return end
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
            or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("extras")) or ""
        if not outline:find("OUTLINE") then
            outline = (outline == "") and "OUTLINE" or (outline .. ", OUTLINE")
        end
        local size = (EllesmereUIDB and EllesmereUIDB.targetDistanceTextSize) or DEFAULT_TEXT_SIZE
        -- HIGH = the pre-setting strata, so existing installs keep their look; the
        -- setting is the opt-in to sit lower (e.g. under the bank window).
        local strata = (EllesmereUIDB and EllesmereUIDB.targetDistanceStrata) or "HIGH"
        local align = GetAlign()
        distFrame._text:SetFont(fontPath, size, outline)
        distFrame._text:SetJustifyH(align)
        distFrame._text:ClearAllPoints()
        distFrame._text:SetPoint(align, distFrame, align, 0, 0)
        distFrame:SetFrameStrata(strata)
        distFrame:SetSize(size * 5, size + 10)

        -- Unlock Mode owns anchors while dragging, or when Anchor-to is linked.
        if EllesmereUI._unlockActive then return end
        if EllesmereUIDB and EllesmereUIDB.unlockAnchors and EllesmereUIDB.unlockAnchors.EUI_TargetDistance then
            return
        end

        distFrame:ClearAllPoints()
        local pos = EllesmereUIDB and EllesmereUIDB.targetDistancePos
        if pos and pos.point then
            distFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        else
            distFrame:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.relPoint, DEFAULT_POS.x, DEFAULT_POS.y)
        end
    end

    local function CreateDistFrame()
        if distFrame then return end
        distFrame = CreateFrame("Frame", nil, UIParent)
        distFrame:SetSize(100, 28)
        distFrame:SetFrameLevel(55)
        distFrame:EnableMouse(false)
        distFrame:SetMouseClickEnabled(false)
        local fs = distFrame:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER", distFrame, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        distFrame._text = fs
        ApplyFrameSettings()
        distFrame:Hide()
    end

    local function ShowSample()
        CreateDistFrame()
        ApplyFrameSettings()
        local text, colorY = SampleForFormat()
        distFrame._text:SetText(text)
        distFrame._text:SetTextColor(ColorForYards(colorY))
        distFrame:SetAlpha(1)
        distFrame:Show()
    end

    local function IsEnabled()
        return EllesmereUIDB and EllesmereUIDB.targetDistanceEnabled
    end

    local Tick -- forward decl for StartDriver closures

    local function StopDriver()
        EllesmereUI.Range_SetActive("qolTargetDistance", false)
        if evt then evt:UnregisterAllEvents() end
        if drv then
            drv:SetScript("OnUpdate", nil)
            drv:Hide()
        end
        installed = false
        acc = 0
        if distFrame then distFrame:Hide() end
    end

    local function StartDriver()
        if not drv then
            drv = CreateFrame("Frame")
            drv:Hide()
        end
        if not evt then
            evt = CreateFrame("Frame")
            evt:SetScript("OnEvent", function()
                if not IsEnabled() then return end
                Tick()
            end)
        end
        drv:SetScript("OnUpdate", function(_, dt)
            if not IsEnabled() then return end
            acc = acc + dt
            if acc < 0.2 then return end
            acc = 0
            Tick()
        end)
        evt:RegisterEvent("PLAYER_TARGET_CHANGED")
        -- Ladder builds and invalidation live in the shared range engine.
        EllesmereUI.Range_SetActive("qolTargetDistance", true)
        drv:Show()
        installed = true
    end

    Tick = function()
        if not IsEnabled() then return end
        if EllesmereUI._unlockActive then
            ShowSample()
            return
        end
        if not UnitExists("target") then
            if distFrame then distFrame:Hide() end
            return
        end
        local text, colorY = ResolveDisplay("target")
        if not text then
            if distFrame then distFrame:Hide() end
            return
        end
        CreateDistFrame()
        ApplyFrameSettings()
        distFrame._text:SetText(text)
        distFrame._text:SetTextColor(ColorForYards(colorY))
        distFrame:Show()
    end

    local function ApplyTargetDistance()
        if IsEnabled() then
            if not installed then StartDriver() end
            Tick()
            if distFrame then ApplyFrameSettings() end
        else
            StopDriver()
        end
    end
    EllesmereUI._applyTargetDistance = ApplyTargetDistance

    EllesmereUI._applyTargetDistanceFrame = function()
        if not IsEnabled() then return end
        CreateDistFrame()
        ApplyFrameSettings()
        Tick()
    end

    C_Timer.After(2, function()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
        local MK = EllesmereUI.MakeUnlockElement
        if not MK then return end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key      = "EUI_TargetDistance",
                label    = "Target Distance",
                group    = "Quality of Life",
                order    = 722,
                noResize = true,
                isHidden = function()
                    return not IsEnabled()
                end,
                getFrame = function()
                    if not IsEnabled() then return nil end
                    CreateDistFrame()
                    if EllesmereUI._unlockActive then ShowSample() end
                    return distFrame
                end,
                getSize = function()
                    local size = (EllesmereUIDB and EllesmereUIDB.targetDistanceTextSize) or DEFAULT_TEXT_SIZE
                    return size * 5, size + 10
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not point then return end
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.targetDistancePos = { point = point, relPoint = relPoint, x = x, y = y }
                    if distFrame and not EllesmereUI._unlockActive then
                        ApplyFrameSettings()
                    end
                end,
                loadPos = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.targetDistancePos
                    if pos and pos.point then return pos end
                    return { point = DEFAULT_POS.point, relPoint = DEFAULT_POS.relPoint, x = DEFAULT_POS.x, y = DEFAULT_POS.y }
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.targetDistancePos = nil end
                    if distFrame then ApplyFrameSettings() end
                end,
                applyPos = function()
                    if not IsEnabled() then return end
                    CreateDistFrame()
                    ApplyFrameSettings()
                    if EllesmereUI._unlockActive then ShowSample() end
                end,
            }),
        })
    end)

    -- One-shot login: only starts the driver when the option is already on.
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        if IsEnabled() then ApplyTargetDistance() end
    end)
end

-------------------------------------------------------------------------------
--  Hide Item Transforms -- cancels cosmetic transform auras (profession gear,
--  holiday costumes, toys, consumables) as soon as they land. CancelUnitBuff is
--  blocked in combat, so mid-fight transforms sweep on the next PLAYER_REGEN_ENABLED.
--  The fishing outfit aura persists for the channel's duration, so it's cleared
--  on channel-stop instead. No events registered unless on AND something's included.
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
        { key = "atomic",     cat = "toys", label = "Atomically Recalibrator",   ids = { 399502 },  defaultOff = true },
        { key = "atomgoblin", cat = "toys", label = "Atomically Regoblinator",   ids = { 1215363 }, defaultOff = true },
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

    -- Per-key default: included unless defaultOff; picker stores only values that differ from default, so nil = default.
    local ITEM_DEFAULT = {}
    for _, item in ipairs(TRANSFORMS) do
        ITEM_DEFAULT[item.key] = not item.defaultOff
    end

    local function ItemEnabled(key)
        local t = EllesmereUIDB and EllesmereUIDB.hideTransformItems
        local v = t and t[key]
        if v ~= nil then return v end
        return ITEM_DEFAULT[key] ~= false
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

    -- Index scans hard-error while aura restrictions are active (M+/raids, even
    -- out of combat); cosmetic transforms just skip there, re-running on the next event outside.
    local function AurasRestricted()
        local AK = EllesmereUI and EllesmereUI.AuraKit
        if AK and AK.AurasRestricted then return AK.AurasRestricted() end
        return false
    end

    -- Sweep current buffs, canceling any included transform. Descending so a cancel (shifts later indices down) can't skip a match.
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
        -- UNIT_AURA (player only, via RegisterUnitEvent). The payload (and its fields) can be secret in
        -- restricted content -- boolean use of a secret errors, so bail rather than error the sweep.
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

    -- Fishing outfit: aura 394009 sticks while the fishing channel (131476) runs,
    -- so it's cleared on channel-stop. Registered only while on and Fishing is included.
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

    -- (Re)decide which events are hooked. Nothing registers unless on AND
    -- something's included, so a disabled feature costs zero: handlers are never installed.
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
        -- Store only values that differ from the per-key default, keeping the table sparse.
        enabled = enabled and true or false
        if enabled == (ITEM_DEFAULT[key] ~= false) then
            EllesmereUIDB.hideTransformItems[key] = nil
        else
            EllesmereUIDB.hideTransformItems[key] = enabled
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
--  Equipment Flyout item levels -- Blizzard's gear flyout (hover a character-
--  sheet slot -> popup of same-slot bag/equipped items) only shows icons; when
--  enabled, overlays each button with the item's level, coloured by quality. Hooks
--  EquipmentFlyout_UpdateItems (after every flyout shape is populated) and reads EllesmereUIDB
--  live, so the toggle applies to the next flyout with no reload. Toggle: EllesmereUIDB.flyoutItemLevels (Quality of Life -> UI).
-------------------------------------------------------------------------------
do
    local function FlyoutEnabled()
        return EllesmereUIDB and EllesmereUIDB.flyoutItemLevels
    end

    -- Item level + quality + link from a decoded bag/slot pair. Prefers the ItemLocation API (exact, no caching); falls back to the item link.
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
        -- Equipped inventory slot.
        if ItemLocation then
            local loc = ItemLocation:CreateFromEquipmentSlot(slot)
            if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
                return C_Item.GetCurrentItemLevel(loc), C_Item.GetItemQuality(loc), C_Item.GetItemLink(loc)
            end
        end
        local link = GetInventoryItemLink("player", slot)
        if link then
            local quality = GetInventoryItemQuality and GetInventoryItemQuality("player", slot)
            return C_Item.GetDetailedItemLevelInfo(link), quality or select(3, C_Item.GetItemInfo(link)), link
        end
    end

    -- Item level + quality + link for a flyout button. Handles all three flyout
    -- shapes: modern buttons storing an ItemLocation object; retail packed location
    -- via EquipmentManager_GetLocationData; older clients via EquipmentManager_UnpackLocation.
    local function ButtonItemInfo(button, useItemLocation)
        if useItemLocation and button.GetItemLocation then
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
    -- button: flyout buttons are Blizzard-owned (secure item-equipping path), so a
    -- custom key would taint execution. Creating the FontString as a child is fine; only the reference stays off the frame table.
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

    local function PaintButton(button, useItemLocation)
        local fs = _flyoutFS[button]
        if not FlyoutEnabled() or not button:IsShown() then
            if fs then fs:SetText("") end
            return
        end

        local ilvl, quality, link = ButtonItemInfo(button, useItemLocation)
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
    end

    local function RefreshFlyoutItemLevels()
        local flyout = EquipmentFlyoutFrame
        if not flyout or not flyout.buttons then return end
        local source = flyout.button
        local parent = source and source:GetParent()
        local settings = parent and parent.flyoutSettings
        local useItemLocation = settings and settings.useItemLocation == true
        for _, button in ipairs(flyout.buttons) do
            PaintButton(button, useItemLocation)
        end
    end

    local function InstallHook()
        if not EquipmentFlyout_UpdateItems then return end
        -- Item-upgrade flyouts use ItemLocation objects and bypass
        -- EquipmentFlyout_DisplayButton entirely. They also leave that ItemLocation
        -- on pooled buttons when an ordinary numeric-location flyout reuses them.
        -- Refresh after the shared update and follow the active flyout's mode, so
        -- both paths repaint instead of inheriting the other's item or overlay.
        hooksecurefunc("EquipmentFlyout_UpdateItems", RefreshFlyoutItemLevels)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        InstallHook()
    end)
end

