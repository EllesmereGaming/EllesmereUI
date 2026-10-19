if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Header.lua
--
--  The header bar: title, search, sort and the header buttons.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local BP, GetFont, SetBagFont, HEADER_H = I.BP, I.GetFont, I.SetBagFont, I.HEADER_H
local PreCacheSortFields, SaveCategoryOrder = I.PreCacheSortFields, I.SaveCategoryOrder
local VisualSortCompare = I.VisualSortCompare

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = I.selectedCategoryIndex
I.categoryIndexSetters[#I.categoryIndexSetters + 1] = function(v) selectedCategoryIndex = v end

-------------------------------------------------------------------------------
--  UI Components -- Header
-------------------------------------------------------------------------------
local function CreateHeader()
    if EUI_Bags.Header then return end
    local header = CreateFrame("Frame", nil, EUI_Bags)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0, 0, 0, 0.5)

    header.title = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.title, 13)
    header.title:SetPoint("LEFT", header, "LEFT", 8, 0)
    header.title:SetText(EllesmereUI.L("Inventory"))
    header.title:SetTextColor(1, 1, 1)

    -- Item count (updated by RefreshInventory)
    header.itemCount = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.itemCount, 11)
    header.itemCount:SetPoint("LEFT", header.title, "RIGHT", 8, 0)
    header.itemCount:SetTextColor(0.6, 0.6, 0.6)

    local search = CreateFrame("EditBox", "EUI_BagSearchBox", header)
    search:SetSize(160, 22)
    search:SetPoint("RIGHT", -35, 0)
    search:SetFont(GetFont(), 12, EUI.GetFontOutlineFlag("bags"))
    search:SetAutoFocus(false)
    search:SetTextInsets(5, 26, 0, 0)
    search.bg = search:CreateTexture(nil, "BACKGROUND")
    search.bg:SetAllPoints()
    search.bg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(search, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7) end

    local placeholder = search:CreateFontString(nil, "OVERLAY")
    SetBagFont(placeholder, 11)
    placeholder:SetPoint("LEFT", search, "LEFT", 5, 0)
    placeholder:SetText(EllesmereUI.L("Search..."))
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    EUI_Bags._searchBox = search

    local sort = CreateFrame("Button", nil, header)
    sort:SetSize(24, 24)
    sort:SetPoint("RIGHT", search, "LEFT", -13, 0)
    sort.icon = sort:CreateTexture(nil, "OVERLAY")
    sort.icon:SetAllPoints()
    sort.icon:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\clean-up.png")
    sort.icon:SetAlpha(0.9)

    sort:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        EUI.ShowWidgetTooltip(self, "Sort Items")
    end)
    sort:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)

    local sortLocked = false
    -- Sorts that move items (OneBag, MultiBag) wait out combat; the other
    -- views' sort only reorders the display.
    local function SortMovesItems()
        return selectedCategoryIndex == -1 or selectedCategoryIndex == -2
    end
    -- The sort button is clickable only while no sort runs, and where it
    -- moves items only out of combat.
    local function ApplySortEnabled()
        local on = not sortLocked and not (InCombatLockdown() and SortMovesItems())
        sort:EnableMouse(on)
        sort.icon:SetAlpha(on and 0.9 or 0.2)
    end
    -- A view switch in combat re-runs it from the refresh (FinishRefresh).
    EUI_Bags._applySortEnabled = ApplySortEnabled
    -- Combat edges only matter while the bags are open; the show edge catches
    -- up on any change while they were closed.
    local combatWatch = CreateFrame("Frame")
    combatWatch:SetScript("OnEvent", ApplySortEnabled)
    EUI_Bags:HookScript("OnShow", function()
        combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        ApplySortEnabled()
    end)
    EUI_Bags:HookScript("OnHide", function()
        combatWatch:UnregisterEvent("PLAYER_REGEN_DISABLED")
        combatWatch:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end)
    -- One reusable BAG_UPDATE listener per role. Both phases are strictly
    -- sequential, and a fresh CreateFrame per round leaked frames per click
    -- (frames are never collected). The run token keeps a second sort from
    -- inheriting the first one's callbacks: EndDragDrop can unlock the button
    -- mid-run, and a stale callback clearing the live chain's OnEvent would
    -- strand it with refreshEnabled false (bags frozen until reload).
    local consolidateFrame, retryFrame
    local function LockSort()
        sortLocked = true
        ApplySortEnabled()
    end
    local function UnlockSort()
        if not sortLocked then return end
        sortLocked = false
        ApplySortEnabled()
    end
    EUI_Bags._unlockSort = UnlockSort

    local DoVisualSort  -- forward declaration

    local function DoPhysicalSort()
        if InCombatLockdown() then return end  -- confirm popup can outlive the pull
        LockSort()
        EUI_Bags.refreshEnabled = false

        local sfxWas = GetCVar("Sound_EnableSFX")
        -- Blizzard's clean-up sound. Sound effects stay muted for the whole
        -- run (item moves), which would cut it short, so it goes out on the
        -- Master channel, and only while the player's sound effects are on
        -- and their volume is above zero.
        if sfxWas == "1" and (tonumber(GetCVar("Sound_SFXVolume")) or 0) > 0 then
            PlaySound(SOUNDKIT.UI_BAG_SORTING_01, "Master")
        end
        EllesmereUI.HoldCVar("Sound_EnableSFX", "0", "EllesmereUIBags")

        -----------------------------------------------------------------------
        --  Phase 1: consolidate partial stacks (smallest onto largest of the same itemID; the engine performs the combine).
        -----------------------------------------------------------------------
        local function ConsolidateStacks(onDone)
            -- Max stack size is a static per-itemID fact, but it was re-read
            -- through GetItemInfo for every occupied slot on every pass (up to
            -- 30 passes over six bags). Memo it for the run instead; the
            -- ItemLocation + DoesItemExist guard it used to sit behind is
            -- redundant, GetContainerItemInfo just returned the item.
            local maxStackByID = {}
            local function ByCount(a, b) return a.count < b.count end
            local function DoOnePass()
                if InCombatLockdown() then return false end  -- combat started: stop moving items
                local stacks = {}  -- itemID -> { {bag,slot,count}, ... }
                -- A WoW Forever special bag's stacks merge only with each other
                -- (a key of their own), so nothing leaves or enters the bag.
                local special = ns.SpecialBags()
                for bag = 0, 5 do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.itemID and info.stackCount then
                            local maxStack = maxStackByID[info.itemID]
                            if not maxStack then
                                maxStack = select(8, C_Item.GetItemInfo(info.itemID))
                                -- Uncached item data: don't memo the fallback,
                                -- a later pass can still resolve it.
                                if maxStack then maxStackByID[info.itemID] = maxStack
                                else maxStack = 1 end
                            end
                            if maxStack > 1 and info.stackCount < maxStack then
                                local key = info.itemID
                                if special and special[bag] then key = bag .. ":" .. key end
                                if not stacks[key] then stacks[key] = {} end
                                stacks[key][#stacks[key] + 1] = {
                                    bag = bag, slot = slot, count = info.stackCount,
                                }
                            end
                        end
                    end
                end
                -- Emptiest partial merges into fullest, second-emptiest into
                -- second-fullest, and so on: every slot is touched at most
                -- once, so all pairs of this pass still fire same-frame -- but
                -- an item with 2n partial stacks now converges in log rounds
                -- instead of n BAG_UPDATE round trips. Overflow waits for a
                -- later pass, same as before.
                local merged = false
                for _, partials in pairs(stacks) do
                    local n = #partials
                    if n >= 2 then
                        table.sort(partials, ByCount)
                        local lo, hi = 1, n
                        while lo < hi do
                            local source, target = partials[lo], partials[hi]
                            local srcLoc = ItemLocation:CreateFromBagAndSlot(source.bag, source.slot)
                            local dstLoc = ItemLocation:CreateFromBagAndSlot(target.bag, target.slot)
                            if not C_Item.IsLocked(srcLoc) and not C_Item.IsLocked(dstLoc) then
                                C_Container.PickupContainerItem(source.bag, source.slot)
                                C_Container.PickupContainerItem(target.bag, target.slot)
                                ClearCursor()
                                merged = true
                            end
                            lo = lo + 1
                            hi = hi - 1
                        end
                    end
                end
                return merged
            end

            if not DoOnePass() then
                onDone()
                return
            end

            local consolidateRetry = 0
            if not consolidateFrame then consolidateFrame = CreateFrame("Frame") end
            local runToken = {}
            consolidateFrame._runToken = runToken
            consolidateFrame:RegisterEvent("BAG_UPDATE")
            consolidateFrame:SetScript("OnEvent", function(self)
                if self._runToken ~= runToken then return end
                self:UnregisterAllEvents()
                consolidateRetry = consolidateRetry + 1
                C_Timer.After(0.15, function()
                    if consolidateFrame._runToken ~= runToken then return end
                    if consolidateRetry < 30 and DoOnePass() then
                        self:RegisterEvent("BAG_UPDATE")
                    else
                        self:SetScript("OnEvent", nil)
                        onDone()
                    end
                end)
            end)
        end

        -----------------------------------------------------------------------
        --  Phase 2: Sort
        -----------------------------------------------------------------------

        -- Scan, compute sorted order and execute all moves in one pass; re-scans every call so retries work from fresh state.
        local function ComputeAndExecute(bagMin, bagMax)
            if InCombatLockdown() then return false end  -- combat started: stop moving items
            bagMin = bagMin or 0
            bagMax = bagMax or 4
            local total = 0
            local sBag, sSlot, sKey, sID = {}, {}, {}, {}

            local items = {}
            -- A WoW Forever special bag adds no slots: its items stay put and
            -- nothing is moved into it.
            local special = ns.SpecialBags()
            for bag = bagMin, bagMax do
                local numSlots = (special and special[bag]) and 0 or C_Container.GetContainerNumSlots(bag)
                for slot = 1, numSlots do
                    total = total + 1
                    sBag[total] = bag
                    sSlot[total] = slot
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info then
                        local link = C_Container.GetContainerItemLink(bag, slot)
                        local key = link .. "\0" .. (info.stackCount or 0)
                        sKey[total] = key
                        sID[total] = info.itemID
                        items[#items + 1] = {
                            pos = total, bag = bag, slot = slot,
                            info = info, itemLink = link, key = key,
                        }
                    end
                end
            end

            if #items == 0 then return false end

            EUI_CategoryManager:ClassifyAll(items)
            local cats = EUI_CategoryManager:GetCategories()
            local sectionOrder = {}
            local ord = 0
            local doneGroups = {}
            for ci, cat in ipairs(cats) do
                if cat.groupName then
                    if not doneGroups[cat.groupName] then
                        doneGroups[cat.groupName] = true
                        ord = ord + 1
                        local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                        if members then
                            for _, mi in ipairs(members) do sectionOrder[mi] = ord end
                        end
                    end
                else
                    ord = ord + 1
                    sectionOrder[ci] = ord
                end
            end

            PreCacheSortFields(items)
            for _, d in ipairs(items) do
                d._sectionOrder = sectionOrder[d.categoryIndex] or 9999
            end
            table.sort(items, function(a, b)
                if a._sectionOrder ~= b._sectionOrder then return a._sectionOrder < b._sectionOrder end
                return VisualSortCompare(a, b)
            end)

            -- Compute moves via selection sort on pre-computed data (zero API calls)
            local atPos = {}
            local whereIs = {}
            for idx, d in ipairs(items) do
                atPos[d.pos] = idx
                whereIs[idx] = d.pos
            end

            -- Sorted item i targets slot i; Sort to Bottom offsets so the block lands in the LAST
            -- #items slots (free slots float up either way). The walk must move toward the free slots
            -- (forward for top, backward for bottom), or a displaced item lands in an already-visited slot -- costing a retry per move, risking the 15-retry cap.
            local offset, first, last, step = 0, 1, #items, 1
            if BP().bagSortToBottom then
                offset = total - #items
                first, last, step = #items, 1, -1
            end

            local moves = {}
            for i = first, last, step do
                local t = i + offset
                local s = whereIs[i]
                if s ~= t then
                    local displaced = atPos[t]
                    if displaced and sID[s] and sID[t] and sID[s] == sID[t] then
                        -- Same itemID: skip to avoid merge, retry will resolve
                    else
                        moves[#moves + 1] = { sBag[s], sSlot[s], sBag[t], sSlot[t] }
                        whereIs[i] = t
                        if displaced then whereIs[displaced] = s end
                        atPos[t] = i
                        atPos[s] = displaced
                        sID[s], sID[t] = sID[t], sID[s]
                        sKey[s], sKey[t] = sKey[t], sKey[s]
                    end
                end
            end

            for _, m in ipairs(moves) do
                C_Container.PickupContainerItem(m[1], m[2])
                C_Container.PickupContainerItem(m[3], m[4])
                ClearCursor()
            end

            return #moves > 0
        end

        local function FinishSort()
            EllesmereUI.ReleaseCVar("Sound_EnableSFX", sfxWas, "EllesmereUIBags")
            C_Timer.After(0.3, function()
                EUI_Bags.refreshEnabled = true
                EUI_Bags:RefreshInventory()
                C_Timer.After(3, UnlockSort)
            end)
        end

        local function RunRetryLoop(bagMin, bagMax, onDone)
            local moved = ComputeAndExecute(bagMin, bagMax)
            if not moved then onDone(); return end

            local retryCount = 0
            if not retryFrame then retryFrame = CreateFrame("Frame") end
            local runToken = {}
            retryFrame._runToken = runToken
            retryFrame:RegisterEvent("BAG_UPDATE")
            retryFrame:SetScript("OnEvent", function(self)
                if self._runToken ~= runToken then return end
                self:UnregisterAllEvents()
                retryCount = retryCount + 1
                C_Timer.After(0.15, function()
                    if retryFrame._runToken ~= runToken then return end
                    local moved = ComputeAndExecute(bagMin, bagMax)
                    if moved and retryCount < 15 then
                        self:RegisterEvent("BAG_UPDATE")
                    else
                        self:SetScript("OnEvent", nil)
                        onDone()
                    end
                end)
            end)
        end

        local function RunSort()
            RunRetryLoop(0, 4, function()
                if C_Container.GetContainerNumSlots(5) > 0 then
                    RunRetryLoop(5, 5, FinishSort)
                else
                    FinishSort()
                end
            end)
        end

        ConsolidateStacks(RunSort)
    end

    DoVisualSort = function()
        -- Sort items per category and save the order
        local cats = EUI_CategoryManager:GetCategories()
        local tempItems = {}
        for bag = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    local itemLink = C_Container.GetContainerItemLink(bag, slot)
                    tempItems[#tempItems + 1] = { bag = bag, slot = slot, info = info, itemLink = itemLink }
                end
            end
        end
        EUI_CategoryManager:ClassifyAll(tempItems)

        local itemsByCat = {}
        for i = 1, #cats do itemsByCat[i] = {} end
        for _, data in ipairs(tempItems) do
            local ci = data.categoryIndex
            if ci and itemsByCat[ci] then
                itemsByCat[ci][#itemsByCat[ci] + 1] = data
            end
        end

        local sortedGroups = {}
        for ci = 1, #cats do
            local cat = cats[ci]
            if cat.groupName then
                if not sortedGroups[cat.groupName] then
                    sortedGroups[cat.groupName] = true
                    -- Merge all members, sort as one, save under group name
                    local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                    local merged = {}
                    for _, mi in ipairs(members) do
                        for _, data in ipairs(itemsByCat[mi] or {}) do
                            merged[#merged + 1] = data
                        end
                    end
                    if #merged > 1 then PreCacheSortFields(merged); table.sort(merged, VisualSortCompare) end
                    SaveCategoryOrder(cat.groupName, merged)
                    -- Also save per-member order for individual category views
                    for _, mi in ipairs(members) do
                        local memberItems = itemsByCat[mi]
                        if memberItems and #memberItems > 1 then
                            PreCacheSortFields(memberItems); table.sort(memberItems, VisualSortCompare)
                        end
                        SaveCategoryOrder(mi, memberItems or {})
                    end
                end
            elseif not cat.isRecent and not cat.isPinned then
                local catItems = itemsByCat[ci]
                if #catItems > 1 then
                    PreCacheSortFields(catItems); table.sort(catItems, VisualSortCompare)
                end
                SaveCategoryOrder(ci, catItems)
            end
        end

        EUI_Bags:RefreshInventory()
        LockSort()
        C_Timer.After(3, UnlockSort)
    end

    -- MultiBag sort defers to Blizzard's native sort (insecure-callable, no taint; BAG_UPDATE
    -- storm drives our refresh). Sort to Bottom rides their fill direction (right-to-left = start
    -- at backpack = our top), floating free slots to our top. Real Blizzard CVar (also drives their Clean Up); set only while the option is on, re-asserted each sort.
    local function DoBlizzardSort()
        if InCombatLockdown() then return end
        PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
        LockSort()
        if BP().bagSortToBottom and C_Container.SetSortBagsRightToLeft then
            C_Container.SetSortBagsRightToLeft(false)
        end
        C_Container.SortBags()
        C_Timer.After(3, UnlockSort)
    end

    sort:SetScript("OnClick", function()
        if sortLocked or (InCombatLockdown() and SortMovesItems()) then return end
        if selectedCategoryIndex == -1 then
            if EllesmereUIDB and EllesmereUIDB.bagSortWarningDismissed then
                DoPhysicalSort()
            else
                EUI:ShowConfirmPopup({
                    title       = "OneBag Sort",
                    message     = "OneBag sorting will physically reorganize items in your bags. The changes persist even if you disable EllesmereUI Bags.",
                    confirmText = "Sort",
                    cancelText  = "Cancel",
                    checkbox    = "Don't show me again",
                    onConfirm   = function(dontShowAgain)
                        if dontShowAgain then
                            if not EllesmereUIDB then EllesmereUIDB = {} end
                            EllesmereUIDB.bagSortWarningDismissed = true
                        end
                        DoPhysicalSort()
                    end,
                })
            end
        elseif selectedCategoryIndex == -2 then
            if EllesmereUIDB and EllesmereUIDB.bagMultiSortWarningDismissed then
                DoBlizzardSort()
            else
                EUI:ShowConfirmPopup({
                    title       = "MultiBag Sort",
                    message     = "MultiBag uses Blizzard's built-in sorting system, which reorganizes the items in your default Blizzard bags. The changes persist even if you disable EllesmereUI Bags.",
                    confirmText = "Sort",
                    cancelText  = "Cancel",
                    checkbox    = "Don't show me again",
                    onConfirm   = function(dontShowAgain)
                        if dontShowAgain then
                            if not EllesmereUIDB then EllesmereUIDB = {} end
                            EllesmereUIDB.bagMultiSortWarningDismissed = true
                        end
                        DoBlizzardSort()
                    end,
                })
            end
        else
            -- Sound here, not in DoVisualSort: the first-open auto sort stays silent.
            PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
            DoVisualSort()
        end
    end)
    EUI_Bags._doVisualSort = DoVisualSort
    EUI_Bags._sortBtn = sort
    ApplySortEnabled()  -- a /reload mid-combat builds the button locked

    local bagsBtn = CreateFrame("Button", nil, header)
    bagsBtn:SetSize(24, 24)
    bagsBtn.icon = bagsBtn:CreateTexture(nil, "ARTWORK")
    bagsBtn.icon:SetAllPoints()
    bagsBtn.icon:SetAtlas("bag-main")
    bagsBtn.icon:SetAlpha(0.9)

    bagsBtn:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if not EUI_BagsWindow:IsVisible() and EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, "Show Bags")
        end
    end)
    bagsBtn:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)
    bagsBtn:SetScript("OnClick", function()
        if EUI_BagsWindow:IsVisible() then
            EUI_BagsWindow:Hide()
        else
            EUI.HideWidgetTooltip()
            EUI_BagsWindow:Show()
            EUI_BagsWindow:RefreshBags()
        end
    end)
    EUI_Bags._bagsBtn = bagsBtn
    EUI_Bags:SyncHeaderIcons()  -- places Sort / Show Bags / the coin (built only while on)

    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(22, 22)
    clear:SetPoint("RIGHT", search, "RIGHT", 0, 0)
    clear.tex = clear:CreateFontString(nil, "OVERLAY")
    SetBagFont(clear.tex, 14)
    clear.tex:SetText("x")
    clear.tex:SetPoint("CENTER", 0, 1)
    clear.tex:SetTextColor(0.8, 0.8, 0.8)
    clear:Hide()
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus(); EUI_Bags.ClearSearch() end)

    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        EUI_Bags.ClearSearch()
    end)
    -- SetItemSearch is client-global and the bank reads isFiltered too: the
    -- bags, the reagent bag and an open bank all repaint when the game reports
    -- the search (EUI_Bags.SetSearchText), so both windows show the same filter.
    local searchChanged = EUI_Bags.WatchSearchBox(search, EUI_Bags.SetSearchText)
    search:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        placeholder:SetShown(text == "")
        clear:SetShown(text ~= "")
        searchChanged(userInput)
    end)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(12, 12)
    close:SetPoint("RIGHT", -9, 0)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
    close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function()
        EUI_Bags:Hide()
        EUI_BagsReagent:Hide()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.bagsVisible = false
        -- Controller cursor: keep Blizzard's hidden bag frames closed too.
        if EUI.PadInUse() then ns.PadReleaseBlizzBags() end
    end)
    EUI_Bags._closeBtn = close  -- Junk Marker mode lets a click on it through
    -- Controller cursor: Cancel finds each window's close control.
    if EUI.PadCP() then
        EUI_Bags.CloseButton = close
        EUI_BagsWindow.CloseButton = bagsBtn
    end

    -- Bottom-edge separator (1px physical pixel)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local hdrSep = header:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(px)
    hdrSep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    hdrSep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    hdrSep:SetColorTexture(0.15, 0.15, 0.15, 1)

    EUI_Bags.Header = header
    EUI_Bags._bagsBtn = bagsBtn
end

I.CreateHeader = CreateHeader
I.broken = false
