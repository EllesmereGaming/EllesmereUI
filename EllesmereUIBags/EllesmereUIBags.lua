-------------------------------------------------------------------------------
--  EllesmereUIBags.lua
--  Enhanced Bags System for EllesmereUI (Midnight)
--  Sidebar category filter + flat item grid layout.
-------------------------------------------------------------------------------
-- Guard: old Bags saved variables file may contain a stale EllesmereUIDB
-- that overwrites the parent's current data (profiles vanish). Detect by
-- checking if the table reference changed from what the parent saved, and
-- restore it. After one logout the stale entry is purged from the file.
if EllesmereUI and EllesmereUI._parentDBRef and EllesmereUIDB ~= EllesmereUI._parentDBRef then
    EllesmereUIDB = EllesmereUI._parentDBRef
end

EUI_Bags = CreateFrame("Frame", "EUI_MainBagFrame", UIParent)
EUI_Bags:Hide()

EUI_BagsReagent = CreateFrame("Frame", "EUI_ReagentBagFrame", UIParent)
EUI_BagsReagent:Hide()

EUI_BagsWindow = CreateFrame("Frame", "EUI_BagsWindowFrame", UIParent)
EUI_BagsWindow:Hide()

local SLOT_SIZE, SPACING = 34, 4
-- Weak-keyed table for bank-deposit routing state. Writing custom keys onto
-- ContainerFrameItemButtonTemplate frames during PreClick taints the secure
-- execution chain and causes UseContainerItem() ADDON_ACTION_FORBIDDEN.
local _bankRouted = setmetatable({}, { __mode = "k" })

local function ApplyBagScale()
    local s = EllesmereUIDB and EllesmereUIDB.bagScale or 1
    if EUI_Bags then EUI_Bags:SetScale(s) end
    if EUI_BagsReagent then EUI_BagsReagent:SetScale(s) end
    if EUI_BagsWindow then EUI_BagsWindow:SetScale(s) end
end

local EUI = EllesmereUI
local GetUpgradeTrack = EUI.GetUpgradeTrack
-- Locale-safe gear detection: GetItemInfo returns localized type strings
-- ("Armor"/"Weapon" only on enUS). Use GetItemInfoInstant's numeric classID.
local ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon  -- 2
local ITEM_CLASS_ARMOR  = Enum.ItemClass.Armor   -- 4
local function IsGearItem(itemLink)
    if not itemLink then return false end
    local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
    return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
end
local function GetFont() return (EUI.GetFontPath and EUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF" end
local function GetOutline() return (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or "" end
local function SetBagFont(fs, size)
    fs:SetFont(GetFont(), size, GetOutline())
    fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.8)
end
local function GetAccentRGB()
    if EUI.GetAccentColor then return EUI.GetAccentColor() end
    return 0.047, 0.824, 0.616
end

local function GetColumns()
    return EllesmereUIDB and EllesmereUIDB.bagColumns or 12
end
local function GetCatTitleSize()
    return EllesmereUIDB and EllesmereUIDB.bagCatTitleSize or 11
end

-- Abbreviate a dungeon name to initials (skip "of", "the", "a")
local _dungeonAbbrCache = {}
local _skipWords = { ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true }
local function AbbrevDungeon(mapID)
    local cached = _dungeonAbbrCache[mapID]
    if cached then return cached end
    local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
    if not name or name == "" then return "" end
    local abbr = ""
    for word in name:gmatch("%S+") do
        if not _skipWords[word:lower()] then
            abbr = abbr .. word:sub(1, 1):upper()
        end
    end
    _dungeonAbbrCache[mapID] = abbr
    return abbr
end

-------------------------------------------------------------------------------
--  Profiler: zero cost when off, /bagprof to toggle.
--  C_AddOnProfiler for per-frame totals, debugprofilestop for breakdown.
-------------------------------------------------------------------------------
local ProfBegin, ProfEnd
do
    local _profData, _profActive = {}, false
    local dps = debugprofilestop
    local _addonName = "EllesmereUIBags"
    local _frameCount = 0
    local _totalAddonMs = 0
    local _peakAddonMs = 0
    local _startTime = 0

    -- Per-frame tracking using GetTime() to detect frame boundaries
    local _curFrameLabels = {}
    local _curFrameTotal = 0
    local _curFrameTime = 0
    local _peakFrameLabels = {}
    local _peakFrameTotal = 0

    ProfBegin = function(label)
        if not _profActive then return 0 end
        return dps()
    end
    ProfEnd = function(label, t0)
        if not _profActive then return end
        local elapsed = dps() - t0
        -- Detect frame boundary: finalize previous frame on new GetTime()
        local now = GetTime()
        if now ~= _curFrameTime then
            if _curFrameTotal > _peakFrameTotal then
                _peakFrameTotal = _curFrameTotal
                wipe(_peakFrameLabels)
                for k, v in pairs(_curFrameLabels) do _peakFrameLabels[k] = v end
            end
            wipe(_curFrameLabels)
            _curFrameTotal = 0
            _curFrameTime = now
        end
        local d = _profData[label]
        if not d then d = { n = 0, total = 0 }; _profData[label] = d end
        d.n = d.n + 1
        d.total = d.total + elapsed
        _curFrameLabels[label] = (_curFrameLabels[label] or 0) + elapsed
        _curFrameTotal = _curFrameTotal + elapsed
    end

    -- OnUpdate only for C_AddOnProfiler addon total (authoritative reference)
    local _peakAddonFrameMs = 0  -- C_AddOnProfiler value for the peak instrumented frame
    local profFrame = CreateFrame("Frame")
    profFrame:Hide()
    profFrame:SetScript("OnUpdate", function()
        if not _profActive then profFrame:Hide(); return end
        if not C_AddOnProfiler or not C_AddOnProfiler.GetAddOnMetric then return end
        local addonMs = C_AddOnProfiler.GetAddOnMetric(
            _addonName, Enum.AddOnProfilerMetric.LastTime) or 0
        _frameCount = _frameCount + 1
        _totalAddonMs = _totalAddonMs + addonMs
        if addonMs > _peakAddonMs then _peakAddonMs = addonMs end
    end)

    local function ResetProf()
        wipe(_profData); wipe(_curFrameLabels); wipe(_peakFrameLabels)
        _frameCount = 0; _totalAddonMs = 0; _peakAddonMs = 0
        _peakAddonFrameMs = 0; _peakFrameTotal = 0
        _curFrameTotal = 0; _curFrameTime = 0; _startTime = 0
    end

    SLASH_BAGPROF1 = "/bagprof"
    SlashCmdList["BAGPROF"] = function(msg)
        if msg == "reset" then
            ResetProf()
            print("|cff00ccffBagProf:|r data cleared")
            return
        end
        _profActive = not _profActive
        if _profActive then
            ResetProf()
            _startTime = GetTime()
            profFrame:Show()
            print("|cff00ccffBagProf:|r ON -- type /bagprof again to stop")
        else
            profFrame:Hide()
            -- Finalize last frame
            if _curFrameTotal > _peakFrameTotal then
                _peakFrameTotal = _curFrameTotal
                wipe(_peakFrameLabels)
                for k, v in pairs(_curFrameLabels) do _peakFrameLabels[k] = v end
            end
            local dur = GetTime() - _startTime
            local avgAddon = _frameCount > 0
                and (_totalAddonMs / _frameCount) or 0
            print("|cff00ccffBagProf Report:|r  "
                .. _frameCount .. " frames, " .. format("%.1f", dur) .. "s")
            print(format(
                "  |cff00ccffAddon Peak:|r  %.3f ms", _peakAddonMs))
            -- Peak frame breakdown: scale proportionally to C_AddOnProfiler peak
            local scale = (_peakFrameTotal > 0) and (_peakAddonMs / _peakFrameTotal) or 1
            local sorted = {}
            local scaledTotal = 0
            for label, ms in pairs(_peakFrameLabels) do
                local scaled = ms * scale
                sorted[#sorted + 1] = { label = label, ms = scaled }
                scaledTotal = scaledTotal + scaled
            end
            table.sort(sorted, function(a, b) return a.ms > b.ms end)
            print(format("  %-30s %10s %8s", "Label", "ms", "%"))
            for _, e in ipairs(sorted) do
                local pct = _peakAddonMs > 0 and (e.ms / _peakAddonMs * 100) or 0
                print(format("  %-30s %10.3f %7.1f%%", e.label, e.ms, pct))
            end
            local gap = _peakAddonMs - scaledTotal
            if gap > 0.05 then
                local pct = gap / _peakAddonMs * 100
                print(format("  %-30s %10.3f %7.1f%%", "Unaccounted", gap, pct))
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Sidebar constants
-------------------------------------------------------------------------------
local SIDEBAR_W_EXPANDED  = 160
local SIDEBAR_W_COLLAPSED = 32
local SIDEBAR_BTN_H       = 26
local SIDEBAR_ICON_SIZE   = 18
local SIDEBAR_PAD         = 2
local SIDEBAR_INDENT      = 16
local HEADER_H            = 35
local FOOTER_H            = 28

-- Runtime state (never persisted; always "All" on load)
local selectedCategoryIndex = 0  -- 0 = All Items, -1 = OneBag, >0 = category index
local selectedGroupName = nil    -- set when a group header is clicked (overrides selectedCategoryIndex)

function EUI_Bags:SetSelectedView(idx)
    selectedCategoryIndex = idx
    selectedGroupName = nil
end

-- Visual sort comparator: quality (desc) > name (asc) > itemID (asc) > bag (asc) > slot (asc)
-- Final bag+slot tiebreaker guarantees deterministic output (Lua 5.1 sort is unstable).
local _trackRank = EUI._TRACK_RANK
-- Gear category lookup: built lazily, maps catIdx -> true for gear categories
local _gearCatSet
local function IsGearCategory(catIdx)
    if not _gearCatSet then
        _gearCatSet = {}
        local cats = EUI_CategoryManager and EUI_CategoryManager:GetCategories()
        if cats then
            for i, cat in ipairs(cats) do
                if cat.isSetGear
                or (cat.types and (cat._defaultName == "Armor"
                    or cat._defaultName == "Weapons / Trinkets")) then
                    _gearCatSet[i] = true
                end
            end
        end
    end
    return _gearCatSet[catIdx]
end

-- Merge duplicate non-gear items by itemID within an already-ordered list.
-- Must run AFTER ApplySavedOrder so the first occurrence in visual order wins.
-- Returns a new list; originals are not modified (except _mergedCount on winners).
local function MergeDuplicates(items)
    -- Clear stale _mergedCount from prior merge passes in the same refresh
    -- (the same data table can be merged in multiple sections: category + pinned/recent)
    for _, data in ipairs(items) do data._mergedCount = nil end
    local seen = {}
    local out = {}
    for _, data in ipairs(items) do
        local id = data.info and data.info.itemID
        if id and not IsGearCategory(data.categoryIndex or 0) then
            local prev = seen[id]
            if prev then
                prev._mergedCount = (prev._mergedCount or prev.info.stackCount) + (data.info.stackCount or 1)
            else
                seen[id] = data
                out[#out + 1] = data
            end
        else
            out[#out + 1] = data
        end
    end
    return out
end

-- Pre-cache sort fields onto item data tables to avoid API calls in comparator
local function PreCacheSortFields(items)
    for _, d in ipairs(items) do
        if d.itemLink and not d._sortCached then
            local name, _, quality, ilvl, _, itemType = GetItemInfo(d.itemLink)
            d._sortName = name or ""
            d._sortQuality = quality or 0
            d._sortIlvl = ilvl or 0
            d._sortType = itemType or ""
            if GetUpgradeTrack and _trackRank then
                local _, color = GetUpgradeTrack(d.itemLink)
                d._sortTrackRank = color and _trackRank[color] or 0
            else
                d._sortTrackRank = 0
            end
            d._sortGear = d.categoryIndex and IsGearCategory(d.categoryIndex) or false
            if name then d._sortCached = true end
        end
    end
end

local function VisualSortCompare(a, b)
    -- Gear sort: track (descending) > ilvl (descending) -- only for gear categories
    if a._sortGear and b._sortGear then
        if a._sortTrackRank ~= b._sortTrackRank then return a._sortTrackRank > b._sortTrackRank end
        if a._sortTrackRank > 0 and b._sortTrackRank > 0 then
            if a._sortIlvl ~= b._sortIlvl then return a._sortIlvl > b._sortIlvl end
        end
    end
    -- Category grouping (keeps items in the same category together)
    -- Skip for gear categories so track/ilvl take priority in merged gear groups
    local aCat = a.categoryIndex or 9999
    local bCat = b.categoryIndex or 9999
    if aCat ~= bCat and not (a._sortGear and b._sortGear) then return aCat < bCat end
    -- Sub-type grouping within merged categories (e.g. Professions vs Recipes)
    if a._sortType ~= b._sortType then return a._sortType < b._sortType end
    -- Fallback: rarity > name > itemID > bag:slot
    if a._sortQuality ~= b._sortQuality then return a._sortQuality > b._sortQuality end
    if a._sortName ~= b._sortName then return a._sortName < b._sortName end
    local ai = (a.info and a.info.itemID) or 0
    local bi = (b.info and b.info.itemID) or 0
    if ai ~= bi then return ai < bi end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-------------------------------------------------------------------------------
--  Slot data table pool (avoids ~200 table allocations per refresh)
-------------------------------------------------------------------------------
local _slotPool = {}
local _slotPoolN = 0
local _activeSlotTables = {}
local _activeSlotN = 0

local function AcquireSlotTable()
    local t
    if _slotPoolN > 0 then
        t = _slotPool[_slotPoolN]
        _slotPool[_slotPoolN] = nil
        _slotPoolN = _slotPoolN - 1
        wipe(t)
    else
        t = {}
    end
    _activeSlotN = _activeSlotN + 1
    _activeSlotTables[_activeSlotN] = t
    return t
end

local function ReleaseAllSlotTables()
    for i = 1, _activeSlotN do
        _slotPoolN = _slotPoolN + 1
        _slotPool[_slotPoolN] = _activeSlotTables[i]
        _activeSlotTables[i] = nil
    end
    _activeSlotN = 0
end

-- Saved visual order per category/group. Keyed by category index (number) or
-- group name (string). Value is an ordered list of "bag:slot" strings.
-- Persisted in EllesmereUIDB.bagVisualOrder.
-- Items in the saved list display in that order; items not in the list append to end.
local function GetVisualOrder()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.bagVisualOrder then EllesmereUIDB.bagVisualOrder = {} end
    return EllesmereUIDB.bagVisualOrder
end

local function SaveCategoryOrder(key, items)
    local order = GetVisualOrder()
    local list = {}
    for i, data in ipairs(items) do
        list[i] = data.info and data.info.itemID or 0
    end
    order[key] = list
end

local function ApplySavedOrder(key, items)
    local order = GetVisualOrder()
    local saved = order[key]
    if not saved or #saved == 0 then return end

    -- Build position queues per itemID: each ID maps to its saved positions
    local posQueues = {}
    for i, id in ipairs(saved) do
        if not posQueues[id] then posQueues[id] = {} end
        local q = posQueues[id]
        q[#q + 1] = i
    end

    -- Assign each item a saved position (consume from queue) or append to end
    local consumed = {}
    local nextUnsaved = #saved + 1
    for _, data in ipairs(items) do
        local id = data.info and data.info.itemID or 0
        local q = posQueues[id]
        local ci = consumed[id] or 1
        if q and ci <= #q then
            data._savedPos = q[ci]
            consumed[id] = ci + 1
        else
            data._savedPos = nextUnsaved
            nextUnsaved = nextUnsaved + 1
        end
    end

    table.sort(items, function(a, b)
        if a._savedPos ~= b._savedPos then return a._savedPos < b._savedPos end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
end

-- Clear saved visual order for a group (called when ungrouping)
local function ClearGroupOrder(groupName)
    if not groupName then return end
    local order = GetVisualOrder()
    order[groupName] = nil
end

-- Bag snapshot: tracks bag:slot -> itemID between refreshes for swap detection
local _bagSnapshot = {}

local function TakeBagSnapshot(tempItems)
    wipe(_bagSnapshot)
    for _, d in ipairs(tempItems) do
        if d.info and d.info.itemID then
            _bagSnapshot[d.bag * 1000 + d.slot] = d.info.itemID
        end
    end
end

-- Detect manual item swaps. When applySwap is true, updates saved visual order.
-- Returns true if a swap was detected.
local function DetectAndApplySwaps(tempItems, applySwap)
    if not next(_bagSnapshot) then return false end

    -- Build current bag:slot -> itemID from scan
    local current = {}
    for _, d in ipairs(tempItems) do
        if d.info and d.info.itemID then
            current[d.bag * 1000 + d.slot] = d.info.itemID
        end
    end

    -- Find slots where one item was replaced by a different item
    local swapChanges = {}
    for key, oldID in pairs(_bagSnapshot) do
        local curID = current[key]
        if curID and curID ~= oldID then
            swapChanges[#swapChanges + 1] = { curID = curID, oldID = oldID }
        end
    end

    -- Swap pattern: exactly 2 item-to-item changes that cross-match
    if #swapChanges == 2 then
        local c1, c2 = swapChanges[1], swapChanges[2]
        if c1.curID == c2.oldID and c2.curID == c1.oldID and c1.curID ~= c2.curID then
            if applySwap then
                local id1, id2 = c1.curID, c2.curID
                local vo = GetVisualOrder()
                for _, saved in pairs(vo) do
                    local idx1, idx2
                    for i, sid in ipairs(saved) do
                        if sid == id1 and not idx1 then idx1 = i
                        elseif sid == id2 and not idx2 then idx2 = i end
                    end
                    if idx1 and idx2 then
                        saved[idx1], saved[idx2] = saved[idx2], saved[idx1]
                    end
                end
            end
            return true
        end
    end
    return false
end

-- Pending resort: category indices + group names that need re-sorting.
-- Populated by ResortAfterGroupChange, consumed by RefreshInventory.
local _pendingResortCats = {}
local _pendingResortGroups = {}

-- Invalidate saved visual order for affected categories/groups.
-- The actual re-sort happens inside RefreshInventory using already-scanned items.
local function ResortAfterGroupChange(catIndices, groupName)
    local order = GetVisualOrder()
    for _, ci in ipairs(catIndices) do
        order[ci] = nil
        _pendingResortCats[ci] = true
    end
    if groupName then
        order[groupName] = nil
        _pendingResortGroups[groupName] = true
    end
end

-------------------------------------------------------------------------------
--  Slot pools
-------------------------------------------------------------------------------
local itemSlots    = {}
local reagentSlots = {}
local bagSlots     = {}

-------------------------------------------------------------------------------
--  Per-category state (for targeted sidebar updates on item count changes)
-------------------------------------------------------------------------------
local _slotCategories = {}     -- bag*1000+slot -> categoryIndex from last full refresh
local _lastCatCounts = {}      -- category counts from last full refresh
local _lastTotalCount = 0      -- total item count from last full refresh

-------------------------------------------------------------------------------
--  HSV helper (used by upgrade indicator, kept from original)
-------------------------------------------------------------------------------
local function HSVToRGB(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if     i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else                return v, p, q
    end
end

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

    -- Title
    header.title = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.title, 13)
    header.title:SetPoint("LEFT", header, "LEFT", 8, 0)
    header.title:SetText("Inventory")
    header.title:SetTextColor(1, 1, 1)

    -- Item count (updated by RefreshInventory)
    header.itemCount = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.itemCount, 11)
    header.itemCount:SetPoint("LEFT", header.title, "RIGHT", 8, 0)
    header.itemCount:SetTextColor(0.6, 0.6, 0.6)

    -- Search box
    local search = CreateFrame("EditBox", "EUI_BagSearchBox", header)
    search:SetSize(160, 22)
    search:SetPoint("RIGHT", -35, 0)
    search:SetFont(GetFont(), 12, GetOutline())
    search:SetAutoFocus(false)
    search:SetTextInsets(5, 26, 0, 0)
    search.bg = search:CreateTexture(nil, "BACKGROUND")
    search.bg:SetAllPoints()
    search.bg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(search, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7) end

    local placeholder = search:CreateFontString(nil, "OVERLAY")
    SetBagFont(placeholder, 11)
    placeholder:SetPoint("LEFT", search, "LEFT", 5, 0)
    placeholder:SetText("Search...")
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    EUI_Bags._searchBox = search

    -- Sort Button (icon)
    local sort = CreateFrame("Button", nil, header)
    sort:SetSize(24, 24)
    sort:SetPoint("RIGHT", search, "LEFT", -13, 0)
    sort.icon = sort:CreateTexture(nil, "OVERLAY")
    sort.icon:SetAllPoints()
    sort.icon:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\clean-up.png")
    sort.icon:SetAlpha(0.9)

    sort:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Sort Items") end
    end)
    sort:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)

    local sortLocked = false
    local function LockSort()
        sortLocked = true
        sort:EnableMouse(false)
        sort.icon:SetAlpha(0.2)
        if EUI_Bags._diceBtn then
            EUI_Bags._diceBtn:EnableMouse(false)
            EUI_Bags._diceBtn.icon:SetAlpha(0.2)
        end
    end
    local function UnlockSort()
        if not sortLocked then return end
        sortLocked = false
        sort:EnableMouse(true)
        sort.icon:SetAlpha(0.9)
        if EUI_Bags._diceBtn then
            EUI_Bags._diceBtn:EnableMouse(true)
            EUI_Bags._diceBtn.icon:SetAlpha(0.9)
        end
    end
    EUI_Bags._unlockSort = UnlockSort

    local DoVisualSort  -- forward declaration

    local function DoPhysicalSort()
        LockSort()
        EUI_Bags.refreshEnabled = false

        local sfxWas = GetCVar("Sound_EnableSFX")
        SetCVar("Sound_EnableSFX", "0")

        -- Scan bags, compute sorted order, and execute all moves in one pass.
        -- Re-scans on every call so retries always work from fresh state.
        local function ComputeAndExecute()
            local total = 0
            local sBag, sSlot, sKey, sID = {}, {}, {}, {}

            local items = {}
            for bag = 0, 4 do
                local numSlots = C_Container.GetContainerNumSlots(bag)
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

            local moves = {}
            for t = 1, #items do
                local s = whereIs[t]
                if s ~= t then
                    local displaced = atPos[t]
                    if displaced and sID[s] and sID[t] and sID[s] == sID[t] then
                        -- Same itemID: skip to avoid merge, retry will resolve
                    else
                        moves[#moves + 1] = { sBag[s], sSlot[s], sBag[t], sSlot[t] }
                        whereIs[t] = t
                        if displaced then whereIs[displaced] = s end
                        atPos[t] = t
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

        local moved = ComputeAndExecute()

        if not moved then
            SetCVar("Sound_EnableSFX", sfxWas)
            EUI_Bags.refreshEnabled = true
            EUI_Bags:RefreshInventory()
            C_Timer.After(3, UnlockSort)
            return
        end

        local retryCount = 0
        local retryFrame = CreateFrame("Frame")
        retryFrame:RegisterEvent("BAG_UPDATE")
        retryFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            retryCount = retryCount + 1
            C_Timer.After(0.15, function()
                local moved = ComputeAndExecute()
                if moved and retryCount < 15 then
                    self:RegisterEvent("BAG_UPDATE")
                else
                    self:SetScript("OnEvent", nil)
                    SetCVar("Sound_EnableSFX", sfxWas)
                    C_Timer.After(0.3, function()
                        EUI_Bags.refreshEnabled = true
                        EUI_Bags:RefreshInventory()
                        C_Timer.After(3, UnlockSort)
                    end)
                end
            end)
        end)
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

        -- Bucket items by category
        local itemsByCat = {}
        for i = 1, #cats do itemsByCat[i] = {} end
        for _, data in ipairs(tempItems) do
            local ci = data.categoryIndex
            if ci and itemsByCat[ci] then
                itemsByCat[ci][#itemsByCat[ci] + 1] = data
            end
        end

        -- Sort each category/group and save the order
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

    sort:SetScript("OnClick", function()
        if sortLocked then return end
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
        else
            DoVisualSort()
        end
    end)
    EUI_Bags._doVisualSort = DoVisualSort
    EUI_Bags._sortBtn = sort
    if EllesmereUIDB and EllesmereUIDB.bagShowSortIcon == false then sort:Hide() end

    -- Randomize Button (dice icon, OneBag only, top-right of bag frame)
    local dice = CreateFrame("Button", nil, EUI_Bags)
    dice:SetSize(20, 20)
    dice:SetPoint("TOPRIGHT", EUI_Bags, "TOPRIGHT", -12, -(HEADER_H + 6))
    dice:SetFrameLevel(EUI_Bags:GetFrameLevel() + 20)
    dice.icon = dice:CreateTexture(nil, "OVERLAY")
    dice.icon:SetAllPoints()
    dice.icon:SetAtlas("charactercreate-icon-dice")
    dice.icon:SetDesaturated(true)
    dice.icon:SetVertexColor(0.82, 0.7, 0.55)
    dice.icon:SetAlpha(0.9)
    dice:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(0.88, 0.8, 0.7)
        self.icon:SetAlpha(1)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Randomize") end
    end)
    dice:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.82, 0.7, 0.55)
        self.icon:SetAlpha(0.9)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    local function DoRandomize()
        LockSort()
        EUI_Bags.refreshEnabled = false

        local slots = {}
        local items = {}
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                slots[#slots + 1] = { bag = bag, slot = slot }
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    items[#items + 1] = { bag = bag, slot = slot, info = info }
                end
            end
        end

        local targetSlots = {}
        for i = 1, #slots do targetSlots[i] = i end
        for i = #targetSlots, 2, -1 do
            local j = math.random(1, i)
            targetSlots[i], targetSlots[j] = targetSlots[j], targetSlots[i]
        end
        for i = #items, 2, -1 do
            local j = math.random(1, i)
            items[i], items[j] = items[j], items[i]
        end

        local posFromKey = {}
        for i, s in ipairs(slots) do posFromKey[s.bag * 1000 + s.slot] = i end
        local current = {}
        local whereIs = {}
        for i = 1, #slots do current[i] = 0 end
        for si, d in ipairs(items) do
            local pi = posFromKey[d.bag * 1000 + d.slot]
            if pi then current[pi] = si; whereIs[si] = pi end
        end

        local moves = {}
        for si = 1, #items do
            local dest = targetSlots[si]
            local curPos = whereIs[si]
            if curPos ~= dest then
                local displaced = current[dest]
                current[dest] = si
                current[curPos] = displaced
                whereIs[si] = dest
                if displaced > 0 then whereIs[displaced] = curPos end
                moves[#moves + 1] = { slots[curPos].bag, slots[curPos].slot, slots[dest].bag, slots[dest].slot }
            end
        end

        local sfxWas = GetCVar("Sound_EnableSFX")
        SetCVar("Sound_EnableSFX", "0")
        for _, m in ipairs(moves) do
            C_Container.PickupContainerItem(m[1], m[2])
            C_Container.PickupContainerItem(m[3], m[4])
            ClearCursor()
        end
        SetCVar("Sound_EnableSFX", sfxWas)

        C_Timer.After(0.5, function()
            EUI_Bags.refreshEnabled = true
            EUI_Bags:RefreshInventory()
            C_Timer.After(3, UnlockSort)
        end)
    end

    dice:SetScript("OnClick", function()
        if sortLocked then return end
        if EllesmereUIDB and EllesmereUIDB.bagRandomizeWarningDismissed then
            DoRandomize()
        else
            EUI:ShowConfirmPopup({
                title       = "Randomize Bags",
                message     = "This will physically scatter items to random positions in your bags. The changes persist even if you disable EllesmereUI Bags.",
                confirmText = "Randomize",
                cancelText  = "Cancel",
                checkbox    = "Don't show me again",
                onConfirm   = function(dontShowAgain)
                    if dontShowAgain then
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.bagRandomizeWarningDismissed = true
                    end
                    DoRandomize()
                end,
            })
        end
    end)
    dice:Hide()
    EUI_Bags._diceBtn = dice

    -- Bags Button (icon)
    local bagsBtn = CreateFrame("Button", nil, header)
    bagsBtn:SetSize(24, 24)
    if sort:IsShown() then
        bagsBtn:SetPoint("RIGHT", sort, "LEFT", -6, 0)
    else
        bagsBtn:SetPoint("RIGHT", search, "LEFT", -13, 0)
    end
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
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    bagsBtn:SetScript("OnClick", function()
        if EUI_BagsWindow:IsVisible() then
            EUI_BagsWindow:Hide()
        else
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            EUI_BagsWindow:Show()
            EUI_BagsWindow:RefreshBags()
        end
    end)
    EUI_Bags._bagsBtn = bagsBtn

    -- Clear button for search
    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(22, 22)
    clear:SetPoint("RIGHT", search, "RIGHT", 0, 0)
    clear.tex = clear:CreateFontString(nil, "OVERLAY")
    SetBagFont(clear.tex, 14)
    clear.tex:SetText("x")
    clear.tex:SetPoint("CENTER", 0, 1)
    clear.tex:SetTextColor(0.8, 0.8, 0.8)
    clear:Hide()
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus(); C_Container.SetItemSearch("") end)

    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        C_Container.SetItemSearch("")
    end)
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        placeholder:SetShown(text == "")
        clear:SetShown(text ~= "")
        C_Container.SetItemSearch(text)
        if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
    end)

    -- Close button
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
    end)

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

-------------------------------------------------------------------------------
--  Gold tracking + Footer (preserved from original)
-------------------------------------------------------------------------------
local lastCapturedGold = 0
local goldCapturePending = false
local lastCapturedWarbandGold = -1
local warbandGoldCapturePending = false

local function FormatNumberWithCommas(num)
    local str = tostring(math.floor(num))
    local result = ""
    local count = 0
    for i = #str, 1, -1 do
        if count > 0 and count % 3 == 0 then result = "," .. result end
        result = str:sub(i, i) .. result
        count = count + 1
    end
    return result
end

local function FormatGoldWithPadding(gold)
    local goldAmount = math.floor(gold / 10000)
    local silverAmount = math.floor((gold % 10000) / 100)
    local copperAmount = gold % 100
    local result = ""
    if goldAmount > 0 then
        result = FormatNumberWithCommas(goldAmount) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:17|t "
    end
    result = result .. string.format("%02d", silverAmount) .. "|TInterface\\MoneyFrame\\UI-SilverIcon:17|t "
    result = result .. string.format("%02d", copperAmount) .. "|TInterface\\MoneyFrame\\UI-CopperIcon:17|t"
    return result
end

local function FormatGoldOnly(gold)
    local goldAmount = math.floor(gold / 10000)
    return FormatNumberWithCommas(goldAmount) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:14|t"
end

local WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B = 1, 0.8, 0.5

local function UpdateBagMoneyDisplay()
    if not EUI_Bags.Money then return end
    MoneyFrame_UpdateMoney(EUI_Bags.Money)
    local goldBtn = _G["EUI_BagMoneyFrameGoldButton"]
    if goldBtn then
        local txt = goldBtn:GetFontString()
        if txt then
            txt:SetText(FormatNumberWithCommas(math.floor(GetMoney() / 10000)))
        end
    end
end

local function GetCharacterIdentifier()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function InitializeCharacterGold()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.characterGold then EllesmereUIDB.characterGold = {} end
end

local function ResetCurrentCharacterGold()
    if not EllesmereUIDB or not EllesmereUIDB.characterGold then return end
    local charID = GetCharacterIdentifier()
    EllesmereUIDB.characterGold[charID] = nil
end

local function CaptureCurrentCharacterGold()
    InitializeCharacterGold()
    local charID = GetCharacterIdentifier()
    local gold = GetMoney()
    if gold == lastCapturedGold then return end
    if goldCapturePending then return end
    lastCapturedGold = gold
    goldCapturePending = true
    C_Timer.After(0.5, function()
        local currentGold = GetMoney()
        local classColor = RAID_CLASS_COLORS[select(2, UnitClass("player"))] or { r=1, g=1, b=1 }
        EllesmereUIDB.characterGold[charID] = {
            gold = currentGold,
            lastUpdated = time(),
            class = select(2, UnitClass("player")),
            classColor = classColor,
        }
        lastCapturedGold = currentGold
        goldCapturePending = false
    end)
end

local function CaptureWarbandGold()
    if not C_Bank or not C_Bank.FetchDepositedMoney then return end
    InitializeCharacterGold()
    local gold = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    if gold == lastCapturedWarbandGold then return end
    if warbandGoldCapturePending then return end
    lastCapturedWarbandGold = gold
    warbandGoldCapturePending = true
    C_Timer.After(0.5, function()
        local currentGold = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
        EllesmereUIDB.warbandGold = {
            gold = currentGold,
            lastUpdated = time(),
        }
        lastCapturedWarbandGold = currentGold
        warbandGoldCapturePending = false
    end)
end

EUI_Bags.CaptureWarbandGold = CaptureWarbandGold

local function CaptureTrackedGold()
    if EllesmereUIDB and EllesmereUIDB.enableGoldTracking == false then return end
    CaptureCurrentCharacterGold()
    CaptureWarbandGold()
end

local function ResetAllGoldData()
    if not EllesmereUIDB then return end
    EllesmereUIDB.characterGold = {}
    EllesmereUIDB.warbandGold = nil
    lastCapturedGold = -1
    lastCapturedWarbandGold = -1
    goldCapturePending = false
    warbandGoldCapturePending = false
    CaptureTrackedGold()
end

-------------------------------------------------------------------------------
--  Gold tooltip (custom multi-column, matches vault tooltip pattern)
-------------------------------------------------------------------------------
local _goldTT
local _goldTTRows = {}
local GOLD_COL_GAP = 20
local GOLD_ROW_H = 14
local GOLD_PAD = 8

local function GetGoldTooltip()
    if _goldTT then return _goldTT end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()

    local fadeInAG = f:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25); fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function() f:SetAlpha(1) end)
    f._fadeInAG = fadeInAG; f._fadeIn = fadeIn

    local fadeOutAG = f:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25); fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function() f:SetAlpha(0); f:Hide() end)
    f._fadeOutAG = fadeOutAG; f._fadeOut = fadeOut

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", f, "TOP", 0, -GOLD_PAD)
    title:SetText("Gold Summary")
    f._title = title

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hint:SetTextColor(1, 0.4, 0.4, 1)
    hint:SetText("Ctrl + Right-Click: Reset all data")
    f._hint = hint

    _goldTT = f
    return f
end

local function EnsureGoldRows(count)
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    local tt = GetGoldTooltip()
    for i = 1, count do
        if not _goldTTRows[i] then
            _goldTTRows[i] = {}
            for col = 0, 1 do
                local fs = tt:CreateFontString(nil, "OVERLAY")
                fs:SetFont(fontPath, 11, fontFlags)
                fs:SetJustifyH(col == 0 and "LEFT" or "RIGHT")
                _goldTTRows[i][col] = fs
            end
        end
    end
    -- Update fonts on all rows
    tt._title:SetFont(fontPath, 11, fontFlags)
    tt._hint:SetFont(fontPath, 10, fontFlags)
    for i = 1, count do
        for col = 0, 1 do
            _goldTTRows[i][col]:SetFont(fontPath, 11, fontFlags)
        end
    end
end

local function StripRealm(name)
    if not name then return "Unknown" end
    if Ambiguate then return Ambiguate(name, "short") or name end
    return name
end

local function ShowGoldTooltip(anchor)
    if not EllesmereUIDB then return end
    if EllesmereUIDB.enableGoldTracking == false then return end

    local totalGold = 0
    local charList = {}
    if EllesmereUIDB.characterGold then
        for charID, data in pairs(EllesmereUIDB.characterGold) do
            charList[#charList + 1] = { id = charID, data = data }
            totalGold = totalGold + data.gold
        end
    end
    table.sort(charList, function(a, b) return a.id < b.id end)

    local warbandGold = EllesmereUIDB.warbandGold and EllesmereUIDB.warbandGold.gold
    if warbandGold then
        totalGold = totalGold + warbandGold
    end
    if #charList == 0 and not warbandGold then return end

    local rowCount = #charList + 1
    if warbandGold then rowCount = rowCount + 1 end
    EnsureGoldRows(rowCount)
    local tt = GetGoldTooltip()

    -- Populate text and measure column widths
    local colWidths = { 0, 0 }
    for r, entry in ipairs(charList) do
        local nameFS = _goldTTRows[r][0]
        local goldFS = _goldTTRows[r][1]
        local cc = entry.data.classColor or { r = 1, g = 1, b = 1 }
        local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
        nameFS:SetText("|cff" .. hex .. StripRealm(entry.id) .. "|r")
        goldFS:SetText(FormatGoldOnly(entry.data.gold))
        goldFS:SetTextColor(1, 1, 1, 1)
        nameFS:Show(); goldFS:Show()
        local nw = nameFS:GetStringWidth() or 0
        local gw = goldFS:GetStringWidth() or 0
        if nw > colWidths[1] then colWidths[1] = nw end
        if gw > colWidths[2] then colWidths[2] = gw end
    end

    local totalRow = #charList + 1
    if warbandGold then
        local nameFS = _goldTTRows[totalRow][0]
        local goldFS = _goldTTRows[totalRow][1]
        nameFS:SetText("|cffffcc80Warbank|r")
        goldFS:SetText(FormatGoldOnly(warbandGold))
        goldFS:SetTextColor(WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B, 1)
        nameFS:Show(); goldFS:Show()
        local nw = nameFS:GetStringWidth() or 0
        local gw = goldFS:GetStringWidth() or 0
        if nw > colWidths[1] then colWidths[1] = nw end
        if gw > colWidths[2] then colWidths[2] = gw end
        totalRow = totalRow + 1
    end

    local totalNameFS = _goldTTRows[totalRow][0]
    local totalGoldFS = _goldTTRows[totalRow][1]
    totalNameFS:SetText("|cffffcc80Total|r")
    totalGoldFS:SetText(FormatGoldOnly(totalGold))
    totalGoldFS:SetTextColor(1, 1, 0.5, 1)
    totalNameFS:Show(); totalGoldFS:Show()
    local tnw = totalNameFS:GetStringWidth() or 0
    local tgw = totalGoldFS:GetStringWidth() or 0
    if tnw > colWidths[1] then colWidths[1] = tnw end
    if tgw > colWidths[2] then colWidths[2] = tgw end

    -- Hide excess rows
    for i = totalRow + 1, #_goldTTRows do
        _goldTTRows[i][0]:Hide()
        _goldTTRows[i][1]:Hide()
    end

    -- Position columns
    local titleTop = GOLD_PAD + (tt._title:GetStringHeight() or 14) + 6
    local col1X = GOLD_PAD
    local col2X = col1X + colWidths[1] + GOLD_COL_GAP
    local totalW = col2X + colWidths[2] + GOLD_PAD

    for r = 1, rowCount do
        local y = -(titleTop + (r - 1) * GOLD_ROW_H)
        -- Add gap before total row
        if r == totalRow then y = y - 4 end
        _goldTTRows[r][0]:ClearAllPoints()
        _goldTTRows[r][0]:SetPoint("TOPLEFT", tt, "TOPLEFT", col1X, y)
        _goldTTRows[r][1]:ClearAllPoints()
        _goldTTRows[r][1]:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -GOLD_PAD, y)
    end

    -- Hint at bottom
    local lastRowY = titleTop + (rowCount - 1) * GOLD_ROW_H + 4 + GOLD_ROW_H + 6
    tt._hint:ClearAllPoints()
    tt._hint:SetPoint("TOPLEFT", tt, "TOPLEFT", GOLD_PAD, -lastRowY)
    local hintW = (tt._hint:GetStringWidth() or 0) + GOLD_PAD * 2
    if hintW > totalW then totalW = hintW end
    local totalH = lastRowY + (tt._hint:GetStringHeight() or 10) + GOLD_PAD

    tt:SetSize(totalW, totalH)
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)

    tt._fadeOutAG:Stop()
    tt._fadeInAG:Stop()
    tt:SetAlpha(0)
    tt:Show()
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeInAG:Play()
end

local function HideGoldTooltip()
    if not _goldTT or not _goldTT:IsShown() then return end
    _goldTT._fadeInAG:Stop()
    _goldTT._fadeOutAG:Stop()
    _goldTT._fadeOut:SetFromAlpha(_goldTT:GetAlpha())
    _goldTT._fadeOut:SetToAlpha(0)
    _goldTT._fadeOutAG:Play()
end

local function CreateFooter()
    if EUI_Bags.Footer then return end
    local footer = CreateFrame("Frame", nil, EUI_Bags)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    footer.bg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
    footer.bg:SetAllPoints()
    footer.bg:SetColorTexture(0, 0, 0, 0.35)

    -- Currency displays are created dynamically from Blizzard's tracked currencies
    if not EUI_Bags._currencyPool then
        EUI_Bags._currencyPool = { displays = {}, hitboxes = {} }
    end

    local money = CreateFrame("Frame", "EUI_BagMoneyFrame", footer, "SmallMoneyFrameTemplate")
    money:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    MoneyFrame_SetType(money, "PLAYER")

    -- Style money frame text with our font
    for _, suffix in ipairs({"GoldButton", "SilverButton", "CopperButton"}) do
        local btn = _G["EUI_BagMoneyFrame" .. suffix]
        if btn then
            local txt = btn:GetFontString()
            if txt then SetBagFont(txt, 11) end
        end
    end

    -- Disable mouse on all SmallMoneyFrameTemplate children so our hitbox catches events
    for _, child in pairs({ money:GetChildren() }) do
        child:EnableMouse(false)
    end
    local moneyHitbox = CreateFrame("Frame", nil, footer)
    moneyHitbox:SetPoint("BOTTOMRIGHT", money, "BOTTOMRIGHT", 5, -5)
    moneyHitbox:SetPoint("TOPLEFT", money, "TOPLEFT", -5, 5)
    moneyHitbox:SetFrameLevel(money:GetFrameLevel() + 10)
    moneyHitbox:EnableMouse(true)

    moneyHitbox:SetScript("OnEnter", function(self) ShowGoldTooltip(self) end)
    moneyHitbox:SetScript("OnLeave", function() HideGoldTooltip() end)
    moneyHitbox:SetScript("OnMouseDown", function(self, button)
        if not EllesmereUIDB then return end
        if EllesmereUIDB.enableGoldTracking == false then return end
        if button == "RightButton" and IsControlKeyDown() then
            ResetAllGoldData(); HideGoldTooltip(); return
        end
    end)

    -- Top-edge separator (1px physical pixel)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local ftrSep = footer:CreateTexture(nil, "ARTWORK")
    ftrSep:SetHeight(px)
    ftrSep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    ftrSep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    ftrSep:SetColorTexture(0.15, 0.15, 0.15, 1)

    EUI_Bags.Footer, EUI_Bags.Money = footer, money
end

local function UpdateCurrencyDisplays()
    local pool = EUI_Bags._currencyPool
    if not pool or not EUI_Bags.Footer then return end
    local footer = EUI_Bags.Footer

    -- Hide all existing displays/hitboxes
    for _, d in ipairs(pool.displays) do d:Hide() end
    for _, h in ipairs(pool.hitboxes) do h:Hide() end

    -- Build tracked list from internal order table (decoupled from Blizzard)
    local tracked = {}
    local orderDB = EllesmereUIDB and EllesmereUIDB.currencyOrder
    if orderDB and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for cID, order in pairs(orderDB) do
            if type(order) == "number" then
                tracked[#tracked + 1] = { currencyTypesID = cID, order = order }
            end
        end
        table.sort(tracked, function(a, b) return a.order < b.order end)
    end

    -- Ensure enough display/hitbox objects exist
    for i = #pool.displays + 1, #tracked do
        local display = footer:CreateFontString(nil, "OVERLAY")
        SetBagFont(display, 11)
        display:SetTextColor(1, 1, 1)
        pool.displays[i] = display

        local hb = CreateFrame("Frame", nil, footer)
        hb:SetFrameLevel(footer:GetFrameLevel() + 5)
        hb:EnableMouse(true)
        hb:SetScript("OnEnter", function(self)
            if self._currencyID and GameTooltip.SetCurrencyByID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetCurrencyByID(self._currencyID)
            end
        end)
        hb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        pool.hitboxes[i] = hb
    end

    -- Build currency metrics
    local padding = 5
    local rowHeight = 14
    local rowGap = 8
    local leftOffset = 10
    local rightMargin = 180
    local footerWidth = footer:GetWidth()
    local availableWidth = footerWidth - leftOffset - rightMargin
    local currentRow = 0
    local currentX = leftOffset
    local currencyLayout = {}

    for i, info in ipairs(tracked) do
        local display = pool.displays[i]
        local fullInfo = C_CurrencyInfo.GetCurrencyInfo(info.currencyTypesID)
        local icon = fullInfo and fullInfo.iconFileID or info.iconFileID
        local quantity = fullInfo and fullInfo.quantity or 0
        local name = fullInfo and fullInfo.name or ""
        if icon then
            display:SetText("|T" .. tostring(icon) .. ":17:17:0:0:64:64:5:59:5:59|t " .. quantity)
            local itemWidth = display:GetStringWidth() + padding
            if currentX + itemWidth > leftOffset + availableWidth and currentX > leftOffset then
                currentRow = currentRow + 1
                currentX = leftOffset
            end
            currencyLayout[#currencyLayout + 1] = {
                idx = i, row = currentRow, x = currentX, currencyID = info.currencyTypesID,
            }
            currentX = currentX + itemWidth
        end
    end

    -- Position displays and hitboxes
    local numRows = currentRow + 1
    for _, layout in ipairs(currencyLayout) do
        local display = pool.displays[layout.idx]
        display:ClearAllPoints()
        local yPos = -7 - ((numRows - 1 - layout.row) * (rowHeight + rowGap))
        display:SetPoint("TOPLEFT", footer, "TOPLEFT", layout.x, yPos)
        display:Show()

        local hb = pool.hitboxes[layout.idx]
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", display, "TOPLEFT", 0, 2)
        hb:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 0, -2)
        hb._currencyID = layout.currencyID
        hb:Show()
    end

    footer:SetHeight(FOOTER_H)
end

-------------------------------------------------------------------------------
--  Reagent Bag UI (preserved)
-------------------------------------------------------------------------------
local function CreateReagentBagUI()
    if EUI_BagsReagent.Header then return end
    local header = CreateFrame("Frame", nil, EUI_BagsReagent)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(35)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0, 0, 0, 0.5)
    header.title = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.title, 13)
    header.title:SetPoint("LEFT", 15, 0)
    header.title:SetText("REAGENTS")
    header.title:SetTextColor(1, 1, 1)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -5, 0)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function() close.icon:SetAlpha(0.9) end)
    close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() EUI_BagsReagent:Hide() end)
    EUI_BagsReagent.Header = header
    local footer = CreateFrame("Frame", nil, EUI_BagsReagent)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    EUI_BagsReagent.Footer = footer
end

-------------------------------------------------------------------------------
--  Inset border helper (1 physical pixel inside frame edge)
-------------------------------------------------------------------------------
local function CreateInsetBorder(btn)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local t = btn:CreateTexture(nil, "OVERLAY", nil, 2); t:SetTexture(WHITE)
    t:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    t:SetHeight(px)
    local b = btn:CreateTexture(nil, "OVERLAY", nil, 2); b:SetTexture(WHITE)
    b:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(px)
    local l = btn:CreateTexture(nil, "OVERLAY", nil, 2); l:SetTexture(WHITE)
    l:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    l:SetWidth(px)
    local r = btn:CreateTexture(nil, "OVERLAY", nil, 2); r:SetTexture(WHITE)
    r:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    r:SetWidth(px)
    btn._brdT, btn._brdB, btn._brdL, btn._brdR = t, b, l, r
end

local function SetInsetBorderColor(btn, cr, cg, cb, ca)
    if btn._brdT then
        btn._brdT:SetColorTexture(cr, cg, cb, ca)
        btn._brdB:SetColorTexture(cr, cg, cb, ca)
        btn._brdL:SetColorTexture(cr, cg, cb, ca)
        btn._brdR:SetColorTexture(cr, cg, cb, ca)
    end
end

-------------------------------------------------------------------------------
--  Drag-to-drop: template handles pickup, we handle drop on mouse release
-------------------------------------------------------------------------------
local _itemDragFrame = CreateFrame("Frame")
_itemDragFrame:Hide()
_itemDragFrame:SetScript("OnUpdate", function(self)
    if IsMouseButtonDown("LeftButton") then return end
    self:Hide()
    -- Blizzard's OnReceiveDrag on action bars / equipment slots fires
    -- BEFORE OnUpdate in the same frame. If they consumed the item,
    -- GetCursorInfo returns nil and we exit immediately.
    if GetCursorInfo() ~= "item" then return end
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    for _, btn in pairs(itemSlots) do
        if btn:IsShown() and btn:GetParent():IsShown() then
            local l, b, w, h = btn:GetRect()
            if l and b and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                local destBag = btn:GetParent():GetID()
                local destSlot = btn:GetID()
                if destSlot > 0 then
                    C_Container.PickupContainerItem(destBag, destSlot)
                end
                return
            end
        end
    end
    -- Check bank slots (if bank is open)
    local bankFrame = _G.EUI_BankFrame
    local bankSlots = bankFrame and bankFrame._bankSlots
    if bankSlots and bankFrame:IsVisible() then
        for _, btn in pairs(bankSlots) do
            if btn:IsShown() and btn:GetParent():IsShown() then
                local l, b, w, h = btn:GetRect()
                if l and b and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                    local destBag = btn:GetParent():GetID()
                    local destSlot = btn:GetID()
                    if destSlot > 0 then
                        C_Container.PickupContainerItem(destBag, destSlot)
                    end
                    return
                end
            end
        end
    end
    -- Not over any bag/bank slot: leave item on cursor. Blizzard already
    -- handled action bars / equipment via OnReceiveDrag above. If dropped
    -- over empty space, item stays on cursor (click to place or right-click
    -- to cancel — standard WoW pickup behavior).
end)

-------------------------------------------------------------------------------
--  Slot Factory (preserved with square icon fix)
-------------------------------------------------------------------------------
local function GetOrCreateSlot(idx)
    if itemSlots[idx] then return itemSlots[idx] end

    local slotParent = CreateFrame("Frame", nil, EUI_Bags)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:HookScript("OnDragStart", function()
        _itemDragFrame:Show()
    end)

    -- Right-click deposit routing: when a specific bank tab is selected,
    -- queue the transfer instead of letting Blizzard route to the first
    -- available slot across all tabs. The queue handles locked items and
    -- slot allocation so rapid clicks don't collide.
    -- State stored in external weak table (NOT on the frame) to avoid
    -- tainting the ContainerFrameItemButtonTemplate secure execution chain.
    -- Writing custom keys onto template buttons during PreClick taints the
    -- frame table, causing UseContainerItem() to be blocked as ADDON_ACTION_FORBIDDEN.
    btn:HookScript("PreClick", function(self, button)
        if button ~= "RightButton" then return end
        local bank = _G.EUI_BankFrame
        if not bank or not bank:IsVisible() then return end
        local targetBag = bank:GetSelectedTabBagID()
        if not targetBag then return end
        local srcBag = self:GetParent():GetID()
        local srcSlot = self:GetID()
        if not srcBag or not srcSlot or srcSlot == 0 then return end
        local info = C_Container.GetContainerItemInfo(srcBag, srcSlot)
        if not info then return end
        bank:QueueTransfer(srcBag, srcSlot)
        _bankRouted[self] = true
    end)
    btn:HookScript("OnClick", function(self, button)
        if button == "RightButton" and _bankRouted[self] then
            _bankRouted[self] = nil
            ClearCursor()
        end
    end)

    btn:HookScript("OnMouseUp", function(self, button)
        if button ~= "MiddleButton" then return end
        local bagID = self:GetParent():GetID()
        local slotID = self:GetID()
        if not bagID or not slotID or slotID == 0 then return end
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if not info or not info.itemID then return end
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
        local pinned = EllesmereUIDB.bagPinnedItems
        local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
        local isGear = IsGearItem(itemLink)
        local cur = pinned[info.itemID] or 0
        if isGear then
            -- Gear: per-stack count toggle
            if cur > 0 then
                cur = cur - 1
                pinned[info.itemID] = cur > 0 and cur or nil
            else
                pinned[info.itemID] = cur + 1
            end
        else
            -- Non-gear: pin/unpin all stacks at once
            if cur > 0 then
                pinned[info.itemID] = nil
            else
                pinned[info.itemID] = 999
            end
        end
        if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
    end)

    -- Hide template decorations via methods only (never write properties onto
    -- Blizzard template sub-objects -- causes taint)
    if btn.NewItemTexture then btn.NewItemTexture:Hide(); btn.NewItemTexture:SetAlpha(0) end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide(); btn.BattlepayItemTexture:SetAlpha(0) end
    if btn.flash then btn.flash:Hide(); btn.flash:SetAlpha(0) end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end

    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    if btn.icon then
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon:ClearAllPoints()
        btn.icon:SetAllPoints(btn)
    end

    local ht = btn:GetHighlightTexture()
    if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture("Interface\\AddOns\\EllesmereUIActionBars\\Media\\highlight-3.png")
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints(); pt:SetAllPoints(btn)
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
    end

    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end

    if btn.icon and btn.IconMask then
        btn.icon:RemoveMaskTexture(btn.IconMask)
        btn.IconMask:Hide()
        btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints()
        btn.IconMask:SetSize(0.001, 0.001)
    end

    -- Style cooldown text
    if btn.Cooldown then
        local cdText = btn.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            cdText:SetFont(GetFont(), 11, "OUTLINE")
        end
    end

    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    -- Text overlay frame: sits above Cooldown so count/ilvl aren't covered by swipe
    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 2)
    btn._textOverlay = textOverlay

    local countSize = EllesmereUIDB and EllesmereUIDB.bagCountFontSize or 11
    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        countFS:SetFont(GetFont(), countSize, "OUTLINE")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    local fontSize = EllesmereUIDB and EllesmereUIDB.itemlevelFontSize or 12
    local fontPath = GetFont()
    btn.ItemLevelText:SetFont(fontPath, fontSize, "OUTLINE")
    btn.ItemLevelText:SetText("")

    -- Keystone level text (top-left, same as item level)
    if not btn.KeystoneText then
        btn.KeystoneText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.KeystoneText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.KeystoneText:SetTextColor(1, 1, 1, 1)
    end
    btn.KeystoneText:SetFont(fontPath, countSize, "OUTLINE")
    btn.KeystoneText:SetText("")
    -- Keystone dungeon abbreviation (bottom-right, same position as stack count)
    if not btn.KeystoneDungeonText then
        btn.KeystoneDungeonText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.KeystoneDungeonText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
        btn.KeystoneDungeonText:SetTextColor(1, 1, 1, 1)
        btn.KeystoneDungeonText:SetJustifyH("RIGHT")
    end
    btn.KeystoneDungeonText:SetFont(fontPath, math.max(countSize - 2, 7), "OUTLINE")
    btn.KeystoneDungeonText:SetText("")

    itemSlots[idx] = btn
    return btn
end

local function GetOrCreateReagentSlot(idx)
    if reagentSlots[idx] then return reagentSlots[idx] end

    local slotParent = CreateFrame("Frame", nil, EUI_BagsReagent)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- Hide template decorations via methods only (never write properties onto
    -- Blizzard template sub-objects -- causes taint)
    if btn.NewItemTexture then btn.NewItemTexture:Hide(); btn.NewItemTexture:SetAlpha(0) end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide(); btn.BattlepayItemTexture:SetAlpha(0) end
    if btn.flash then btn.flash:Hide(); btn.flash:SetAlpha(0) end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end

    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    if btn.icon then
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon:ClearAllPoints()
        btn.icon:SetAllPoints(btn)
    end

    local ht = btn:GetHighlightTexture()
    if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture("Interface\\AddOns\\EllesmereUIActionBars\\Media\\highlight-3.png")
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints(); pt:SetAllPoints(btn)
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
    end

    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end

    if btn.icon and btn.IconMask then
        btn.icon:RemoveMaskTexture(btn.IconMask)
        btn.IconMask:Hide()
        btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints()
        btn.IconMask:SetSize(0.001, 0.001)
    end

    -- Style cooldown text
    if btn.Cooldown then
        local cdText = btn.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            cdText:SetFont(GetFont(), 11, "OUTLINE")
        end
    end

    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    -- Text overlay frame: sits above Cooldown so count/ilvl aren't covered by swipe
    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 2)
    btn._textOverlay = textOverlay

    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        countFS:SetFont(GetFont(), EllesmereUIDB and EllesmereUIDB.bagCountFontSize or 11, "OUTLINE")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    local fontSize = EllesmereUIDB and EllesmereUIDB.itemlevelFontSize or 12
    btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    btn.ItemLevelText:SetText("")

    reagentSlots[idx] = btn
    return btn
end

local function GetOrCreateBagSlot(idx)
    if bagSlots[idx] then return bagSlots[idx] end
    local slotParent = CreateFrame("Frame", nil, EUI_BagsWindow)
    slotParent:SetSize(SLOT_SIZE, SLOT_SIZE)
    local btn = CreateFrame("Button", nil, slotParent)
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetAllPoints(btn)
    btn.Count = btn:CreateFontString(nil, "OVERLAY")
    btn.Count:SetFont(GetFont(), EllesmereUIDB and EllesmereUIDB.bagCountFontSize or 11, "OUTLINE")
    btn.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.Count:SetTextColor(1, 1, 1)
    CreateInsetBorder(btn)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    -- Drag-and-drop: equip a bag into this slot
    local function TrySwapBag(self)
        if InCombatLockdown() then return end
        if not CursorHasItem() then return end
        local bagID = self:GetID()
        if bagID == 0 then return end  -- can't replace backpack
        local invID = C_Container.ContainerIDToInventoryID(bagID)
        PickupInventoryItem(invID)
        EUI_Bags._pendingBagSwap = true
    end
    btn:SetScript("OnReceiveDrag", TrySwapBag)
    btn:HookScript("OnClick", TrySwapBag)

    bagSlots[idx] = btn
    return btn
end

-------------------------------------------------------------------------------
--  Fast font size update: re-applies text sizes to all existing slots
--  without a full RefreshInventory. Called by options sliders.
-------------------------------------------------------------------------------
local function RefreshTextSizes()
    local fontPath = GetFont()
    local countSize = EllesmereUIDB and EllesmereUIDB.bagCountFontSize or 11
    local ilvlSize = EllesmereUIDB and EllesmereUIDB.itemlevelFontSize or 12
    for _, btn in pairs(itemSlots) do
        if btn.Count then btn.Count:SetFont(fontPath, countSize, "OUTLINE") end
        if btn.ItemLevelText then btn.ItemLevelText:SetFont(fontPath, ilvlSize, "OUTLINE") end
        if btn.KeystoneText then btn.KeystoneText:SetFont(fontPath, countSize, "OUTLINE") end
        if btn.KeystoneDungeonText then btn.KeystoneDungeonText:SetFont(fontPath, math.max(countSize - 2, 7), "OUTLINE") end
    end
    for _, btn in pairs(reagentSlots) do
        if btn.Count then btn.Count:SetFont(fontPath, countSize, "OUTLINE") end
        if btn.ItemLevelText then btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, ilvlSize, "OUTLINE") end
    end
end
EUI_Bags.RefreshTextSizes = RefreshTextSizes

-------------------------------------------------------------------------------
--  RenderButton (simplified, no placeholder handling)
-------------------------------------------------------------------------------
local function RenderButton(btn, data, _, col, row, startX, currentY, _, interactiveEmpties)
    local parent = btn:GetParent()
    parent:ClearAllPoints()
    parent:SetPoint("TOPLEFT", startX + (col * (SLOT_SIZE + SPACING)), currentY - (row * (SLOT_SIZE + SPACING)))
    parent:Show()
    btn:Show()

    btn:SetID(data.slot or 0)
    parent:SetID(data.bag or 0)

    -- Always clear overlays upfront (pooled buttons carry stale state from prior items)
    if btn.ProfessionQualityOverlay then
        btn.ProfessionQualityOverlay:SetAlpha(0)
    end
    if btn.IconOverlay then btn.IconOverlay:SetAlpha(0); btn.IconOverlay:Hide() end
    if btn.IconOverlay2 then btn.IconOverlay2:SetAlpha(0); btn.IconOverlay2:Hide() end

    -- Empty slot background (created once, reused)
    if not btn._emptyBg then
        btn._emptyBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        btn._emptyBg:SetAllPoints()
        btn._emptyBg:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\icon-bg.png")
    end

    if not data.info then
        -- Empty slot
        btn:SetItemButtonTexture(nil)
        btn:SetItemButtonCount(0)
        SetItemButtonDesaturated(btn, false)
        if btn.icon then btn.icon:Hide() end
        btn._emptyBg:Show()
        if interactiveEmpties then
            btn:EnableMouse(true)
            btn._emptyBg:SetAlpha(0.6)
            SetInsetBorderColor(btn, 0.15, 0.15, 0.15, 0.5)
        else
            btn:EnableMouse(false)
            btn._emptyBg:SetAlpha(0.35)
            SetInsetBorderColor(btn, 0, 0, 0, 0.3)
        end
        if btn.Cooldown then btn.Cooldown:Clear() end
        if btn.ItemLevelText then btn.ItemLevelText:SetText("") end
        if btn.KeystoneText then btn.KeystoneText:SetText("") end
        if btn.KeystoneDungeonText then btn.KeystoneDungeonText:SetText("") end
        if btn.ProfessionQualityOverlay then btn.ProfessionQualityOverlay:Hide() end
        if btn.IconBorder then btn.IconBorder:Hide() end
        if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
        if btn._warbankDim then btn._warbankDim:Hide() end
        btn:SetAlpha(1)
    else
        btn:EnableMouse(true)
        btn._emptyBg:Hide()
        if btn.icon then btn.icon:Show() end
        btn:SetItemButtonTexture(data.info.iconFileID)
        btn:SetItemButtonCount(data._mergedCount or data.info.stackCount)
        btn._isMerged = data._mergedCount and true or nil
        SetItemButtonDesaturated(btn, data.info.isLocked)
        btn:SetAlpha(data.info.isFiltered and 0.2 or 1)

        local iType = data._giType

        -- Item Level + Upgrade Rank (gear only)
        if btn.ItemLevelText then
            if data._isGear then
                local showIlvl = not EllesmereUIDB or EllesmereUIDB.showItemlevelInBags ~= false
                if showIlvl then
                    btn.ItemLevelText:SetText(data._giIlvl or "")
                    -- Track color + rank (pre-cached on data table)
                    local r, g, b
                    local rankText = data._giTrackRank or ""
                    local trackColor = data._giTrackColor
                    if EllesmereUIDB and EllesmereUIDB.itemlevelUseCustomColor and EllesmereUIDB.itemlevelCustomColor then
                        r, g, b = EllesmereUIDB.itemlevelCustomColor.r, EllesmereUIDB.itemlevelCustomColor.g, EllesmereUIDB.itemlevelCustomColor.b
                    elseif rankText ~= "" and trackColor then
                        r, g, b = trackColor.r, trackColor.g, trackColor.b
                    else
                        r, g, b = GetItemQualityColor(data._giQuality or 1)
                    end
                    btn.ItemLevelText:SetTextColor(r, g, b, 1)
                    -- Rank text at bottom-right
                    local countFS = btn.Count
                    if countFS and EllesmereUIDB and EllesmereUIDB.bagShowTrackRank and rankText ~= "" then
                        countFS:SetText(rankText:match("^(%d+)/") or rankText)
                        countFS:SetTextColor(r, g, b, 1)
                        countFS:Show()
                    end
                else
                    btn.ItemLevelText:SetText("")
                end
            else
                btn.ItemLevelText:SetText("")
            end
        end

        -- Keystone: level top-left, abbreviated dungeon name bottom-right
        if btn.KeystoneText then
            if data._ksLevel then
                btn.KeystoneText:SetText(data._ksLevel)
                btn.KeystoneText:SetTextColor(data._ksR or 1, data._ksG or 1, data._ksB or 1, 1)
                if btn.KeystoneDungeonText then
                    btn.KeystoneDungeonText:SetText(data._ksAbbrev or "")
                    btn.KeystoneDungeonText:SetTextColor(1, 1, 1, 1)
                end
            else
                btn.KeystoneText:SetText("")
                if btn.KeystoneDungeonText then btn.KeystoneDungeonText:SetText("") end
            end
        end

        -- Profession quality overlay: let Blizzard decide via SetItemButtonQuality
        -- (handles all item types, not just ones we think are "profession")
        local quality = data.info.quality or 1
        if data.itemLink then
            btn:SetItemButtonQuality(quality, data.itemLink, false, false)
        end
        -- Control overlay via alpha (immune to parent visibility inheritance).
        -- SetItemButtonQuality may have called Show() internally, but we use
        -- alpha 0/1 as the sole visibility control.
        if btn.ProfessionQualityOverlay then
            if btn.ProfessionQualityOverlay:IsShown() then
                btn.ProfessionQualityOverlay:SetAlpha(1)
                if btn._textOverlay then
                    btn.ProfessionQualityOverlay:SetParent(btn._textOverlay)
                end
            else
                btn.ProfessionQualityOverlay:SetAlpha(0)
            end
        end
        -- Cosmetic/warbound overlays: SetItemButtonQuality re-shows these,
        -- so we must handle them AFTER that call. Reparent to textOverlay
        -- so they render above the inset quality borders.
        if btn.IconOverlay then
            if btn.IconOverlay:IsShown() then
                btn.IconOverlay:SetAlpha(1)
                if btn._textOverlay then btn.IconOverlay:SetParent(btn._textOverlay) end
            else
                btn.IconOverlay:SetAlpha(0)
            end
        end
        if btn.IconOverlay2 then
            if btn.IconOverlay2:IsShown() then
                btn.IconOverlay2:SetAlpha(1)
                if btn._textOverlay then btn.IconOverlay2:SetParent(btn._textOverlay) end
            else
                btn.IconOverlay2:SetAlpha(0)
            end
        end
        if btn.IconBorder then btn.IconBorder:Hide() end
        if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end

        -- Quality border color
        local c = ITEM_QUALITY_COLORS[quality]
        if c then
            SetInsetBorderColor(btn, c.r, c.g, c.b, 1)
        else
            SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)
        end

        -- Warbank dim overlay: when a warband bank tab is selected,
        -- dim non-warbound items so the user can see what's eligible.
        if not btn._warbankDim then
            local dimFrame = CreateFrame("Frame", nil, btn)
            dimFrame:SetAllPoints()
            dimFrame:SetFrameLevel((btn._textOverlay and btn._textOverlay:GetFrameLevel() or btn:GetFrameLevel()) + 3)
            local dim = dimFrame:CreateTexture(nil, "OVERLAY")
            dim:SetAllPoints()
            dim:SetColorTexture(0, 0, 0, 0.75)
            dimFrame:Hide()
            btn._warbankDim = dimFrame
        end
        local bank = _G.EUI_BankFrame
        local showDim = bank and bank:IsVisible()
            and bank.IsWarbandView and bank:IsWarbandView()
            and not data._isWarbound
        if showDim then
            btn._warbankDim:Show()
        else
            btn._warbankDim:Hide()
        end

        -- Cooldown
        if btn.Cooldown then
            if data._cdStart then
                btn.Cooldown:SetDrawEdge(true)
                btn.Cooldown:SetCooldown(data._cdStart, data._cdDuration)
            else
                btn.Cooldown:Clear()
            end
        end

    end
end

-------------------------------------------------------------------------------
--  Pin Selection Mode
-------------------------------------------------------------------------------
local EnterPinSelectMode  -- forward declaration
local ExitPinSelectMode   -- forward declaration

-- Pin "+" overlay: a click-catcher frame placed over a regular empty slot
local function GetOrCreatePinOverlay()
    if EUI_Bags._pinOverlayBtn then return EUI_Bags._pinOverlayBtn end
    local ov = CreateFrame("Button", nil, EUI_Bags)
    ov:SetSize(SLOT_SIZE, SLOT_SIZE)
    ov:SetFrameLevel(100)
    ov.bg = ov:CreateTexture(nil, "BACKGROUND")
    ov.bg:SetAllPoints()
    ov.bg:SetColorTexture(0, 0, 0, 0.4)
    ov.plus = ov:CreateFontString(nil, "OVERLAY")
    ov.plus:SetFont(GetFont(), 18, "OUTLINE")
    ov.plus:SetPoint("CENTER", 0, 0)
    ov.plus:SetText("+")
    ov.plus:SetTextColor(1, 1, 1, 0.5)
    ov:SetScript("OnEnter", function(self)
        self.plus:SetTextColor(1, 1, 1, 1)
        if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Pin an Item") end
    end)
    ov:SetScript("OnLeave", function(self)
        self.plus:SetTextColor(1, 1, 1, 0.5)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    ov:RegisterForDrag("LeftButton")
    ov:SetScript("OnReceiveDrag", function()
        local cursorType, itemID = GetCursorInfo()
        if cursorType == "item" and itemID then
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
            local pinned = EllesmereUIDB.bagPinnedItems
            if not pinned[itemID] or pinned[itemID] == 0 then
                local itemLink = select(2, GetCursorInfo())
                pinned[itemID] = IsGearItem(itemLink) and 1 or 999
            end
            ClearCursor()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
        end
    end)
    ov:SetScript("OnClick", function()
        local cursorType, itemID = GetCursorInfo()
        if cursorType == "item" and itemID then
            -- Click-to-place also pins
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
            local pinned = EllesmereUIDB.bagPinnedItems
            if not pinned[itemID] or pinned[itemID] == 0 then
                local itemLink = select(2, GetCursorInfo())
                pinned[itemID] = IsGearItem(itemLink) and 1 or 999
            end
            ClearCursor()
            if EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
            return
        end
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        EnterPinSelectMode()
    end)
    ov:Hide()
    EUI_Bags._pinOverlayBtn = ov
    return ov
end

ExitPinSelectMode = function()
    EUI_Bags._pinSelectMode = false
    if EUI_Bags._pinCatcher then EUI_Bags._pinCatcher:Hide() end
    local ov = EUI_Bags._pinOverlay
    if ov then
        ov:EnableMouse(false)
        if not ov._fadeOut then
            local fg = ov:CreateAnimationGroup()
            local a = fg:CreateAnimation("Alpha")
            a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(0.15)
            fg:SetScript("OnFinished", function() ov:Hide(); ov:SetAlpha(1) end)
            ov._fadeOut = fg
        end
        ov._fadeOut:Play()
    end
    -- Restore scroll frame strata
    local sf = EUI_Bags._scrollFrame
    if sf then sf:SetFrameStrata("HIGH") end
end

EnterPinSelectMode = function()
    EUI_Bags._pinSelectMode = true

    -- Dark overlay covers the entire screen including bags
    if not EUI_Bags._pinOverlay then
        local ov = CreateFrame("Frame", nil, UIParent)
        ov:SetFrameStrata("FULLSCREEN_DIALOG")
        ov:SetFrameLevel(0)
        ov:SetAllPoints(UIParent)
        ov:EnableMouse(true)
        ov.bg = ov:CreateTexture(nil, "BACKGROUND")
        ov.bg:SetAllPoints()
        ov.bg:SetColorTexture(0, 0, 0, 0.6)
        ov:SetScript("OnMouseDown", function() ExitPinSelectMode() end)
        ov:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                ExitPinSelectMode()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        EUI_Bags._pinOverlay = ov
    end
    local ov = EUI_Bags._pinOverlay
    ov:SetAlpha(0)
    ov:Show()
    if not ov._fadeIn then
        local fg = ov:CreateAnimationGroup()
        local a = fg:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.15)
        fg:SetScript("OnFinished", function() ov:SetAlpha(1) end)
        ov._fadeIn = fg
    end
    ov._fadeIn:Play()

    -- Raise the scroll frame above the overlay so item icons are visible
    local sf = EUI_Bags._scrollFrame
    if sf then sf:SetFrameStrata("FULLSCREEN_DIALOG") end

    -- Hit-test: find the item button under the cursor
    local function FindBtnUnderCursor()
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        for _, btn in pairs(itemSlots) do
            if btn:IsShown() and btn:GetParent():IsShown() then
                local l, b, w, h = btn:GetRect()
                if l and b and w and h and cx >= l and cx <= l + w and cy >= b and cy <= b + h then
                    return btn
                end
            end
        end
        return nil
    end

    -- Click catcher: invisible frame above the raised item icons
    -- Intercepts clicks so items don't get used/equipped, finds which icon
    -- was clicked, and pins it.
    if not EUI_Bags._pinCatcher then
        local cf = CreateFrame("Frame", nil, UIParent)
        cf:SetFrameStrata("FULLSCREEN_DIALOG")
        cf:SetFrameLevel(500)
        cf:EnableMouse(true)

        -- Hover highlight: accent border (2px) + white overlay
        local pinHoverOv = cf:CreateTexture(nil, "OVERLAY")
        pinHoverOv:SetColorTexture(1, 1, 1, 0.4)
        pinHoverOv:Hide()
        local pinHoveredBtn = nil
        local pinSavedR, pinSavedG, pinSavedB, pinSavedA
        local pinSavedBrdSize

        local function ClearPinHover()
            if pinHoveredBtn then
                if pinSavedR then
                    SetInsetBorderColor(pinHoveredBtn, pinSavedR, pinSavedG, pinSavedB, pinSavedA)
                end
                if pinSavedBrdSize and pinHoveredBtn._brdT then
                    pinHoveredBtn._brdT:SetHeight(pinSavedBrdSize)
                    pinHoveredBtn._brdB:SetHeight(pinSavedBrdSize)
                    pinHoveredBtn._brdL:SetWidth(pinSavedBrdSize)
                    pinHoveredBtn._brdR:SetWidth(pinSavedBrdSize)
                end
            end
            pinHoveredBtn = nil
            pinSavedR = nil
            pinSavedBrdSize = nil
            pinHoverOv:ClearAllPoints()
            pinHoverOv:Hide()
        end

        cf:SetScript("OnUpdate", function()
            local btn = FindBtnUnderCursor()
            if btn == pinHoveredBtn then return end
            ClearPinHover()
            if btn and btn.icon and btn.icon:IsShown() then
                if btn._brdT then
                    -- Save current border color + size
                    pinSavedR, pinSavedG, pinSavedB, pinSavedA = btn._brdT:GetVertexColor()
                    pinSavedBrdSize = btn._brdT:GetHeight()
                    -- Apply accent border at 2px
                    local ar, ag, ab = GetAccentRGB()
                    SetInsetBorderColor(btn, ar, ag, ab, 1)
                    local PP = EUI and EUI.PP
                    local px2 = ((PP and PP.mult) or 1) * 2
                    btn._brdT:SetHeight(px2)
                    btn._brdB:SetHeight(px2)
                    btn._brdL:SetWidth(px2)
                    btn._brdR:SetWidth(px2)
                end
                -- Show white overlay
                pinHoverOv:ClearAllPoints()
                pinHoverOv:SetAllPoints(btn)
                pinHoverOv:Show()
                pinHoveredBtn = btn
            end
        end)

        cf:SetScript("OnMouseDown", function(_, button)
            if button == "RightButton" then ClearPinHover(); ExitPinSelectMode(); return end
            local btn = FindBtnUnderCursor()
            if btn then
                local bagID = btn:GetParent():GetID()
                local slotID = btn:GetID()
                if bagID and slotID and slotID > 0 then
                    local info = C_Container.GetContainerItemInfo(bagID, slotID)
                    if info and info.itemID then
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
                        EllesmereUIDB.bagPinnedItems[info.itemID] = (EllesmereUIDB.bagPinnedItems[info.itemID] or 0) + 1
                        ClearPinHover()
                        ExitPinSelectMode()
                        EUI_Bags:RefreshInventory()
                        return
                    end
                end
            end
            ClearPinHover()
            ExitPinSelectMode()
        end)

        cf:SetScript("OnHide", function() ClearPinHover() end)
        EUI_Bags._pinCatcher = cf
    end
    -- Position catcher over the scroll frame area
    local sf = EUI_Bags._scrollFrame
    if sf then
        local l, b, w, h = sf:GetRect()
        if l and b and w and h then
            EUI_Bags._pinCatcher:ClearAllPoints()
            EUI_Bags._pinCatcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
            EUI_Bags._pinCatcher:SetSize(w, h)
        end
    end
    EUI_Bags._pinCatcher:Show()
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local _sidebarBtns = {}  -- array of sidebar button frames

local function GetSidebarWidth()
    local collapsed = EllesmereUIDB and EllesmereUIDB.bagSidebarCollapsed
    return collapsed and SIDEBAR_W_COLLAPSED or SIDEBAR_W_EXPANDED
end

-------------------------------------------------------------------------------
--  Sidebar drag-to-reorder (iOS-style: ghost + insert line + source fade)
-------------------------------------------------------------------------------
local _dragGhost         -- floating ghost frame (scaled 0.5x, 70% opacity)
local _dragFromCatIdx    -- category index being dragged (1-based into bagCategoryDefs)
local _dragSourceBtn     -- the button frame being dragged (to restore alpha)
local _dragInsertLine    -- accent-colored insertion line
local _dragGroupHL       -- accent-colored group highlight overlay
local _dragLastTarget    -- last computed insert target (avoid redundant updates)
local _dragLastMode      -- "above", "below", "group"
local _dragLastBtn       -- last target button (avoid redundant updates)
local _dragDropMode      -- current drop mode for StopSidebarDrag
local _dragDropTarget    -- current drop target catIdx
local _dragTargetIsHeader -- true when resolved target came from a group header button
local _dragInsertGroup    -- group name when insert position is inside a group

local function EnsureDragGhost()
    if _dragGhost then return _dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(SIDEBAR_W_EXPANDED, SIDEBAR_BTN_H)
    g:SetAlpha(0.7)
    g:SetScale(0.5)
    g:EnableMouse(false)
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    g.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
    g.icon:SetPoint("LEFT", 8, 0)
    g.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    g.label = g:CreateFontString(nil, "OVERLAY")
    SetBagFont(g.label, 11)
    g.label:SetPoint("LEFT", g.icon, "RIGHT", 6, 0)
    g.label:SetTextColor(1, 1, 1)
    g:Hide()
    _dragGhost = g
    return g
end

local function EnsureInsertLine()
    if _dragInsertLine then return _dragInsertLine end
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local eg = EUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    local line = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
    line:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    line:SetHeight(px * 2)
    line:Hide()
    _dragInsertLine = line
    return line
end

local function EnsureGroupHighlight()
    if _dragGroupHL then return _dragGroupHL end
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local eg = EUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    local hl = CreateFrame("Frame", nil, sidebar)
    hl:SetFrameLevel(sidebar:GetFrameLevel() + 10)
    hl.bg = hl:CreateTexture(nil, "OVERLAY", nil, 6)
    hl.bg:SetAllPoints()
    hl.bg:SetColorTexture(eg.r, eg.g, eg.b, 0.15)
    -- Accent border
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local function MakeLine(point1, rel1, point2, rel2, w, h)
        local t = hl:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(eg.r, eg.g, eg.b, 0.6)
        t:SetPoint(point1, hl, rel1, 0, 0)
        t:SetPoint(point2, hl, rel2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    MakeLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, px)
    MakeLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, px)
    MakeLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", px, nil)
    MakeLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", px, nil)
    hl:Hide()
    _dragGroupHL = hl
    return hl
end

-- Compute insert position from cursor Y relative to visible sidebar buttons.
-- Maps cursor to the visual button list (which skips hidden/empty categories).
local function ComputeDropTarget()
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local scale = sidebar:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local sidebarTop = sidebar:GetTop() * scale
    local localY = (sidebarTop - cy) / scale

    -- Offset past sidebar header + "All Items" + "OneBag" buttons
    localY = localY - 24 - 2 * (SIDEBAR_BTN_H + SIDEBAR_PAD)

    if localY < 0 then return 1 end

    -- Walk visible category buttons to find which slot the cursor is over
    local cats = EUI_CategoryManager:GetCategories()
    local visIdx = 0
    local lastVisibleCatIdx = 1
    for i = 1, #cats do
        -- Check if this category has a visible button
        local isVisible = false
        for _, btn in ipairs(_sidebarBtns) do
            if btn:IsShown() and btn._catIdx == i then
                isVisible = true
                break
            end
        end
        if isVisible then
            visIdx = visIdx + 1
            lastVisibleCatIdx = i
            local slotTop = (visIdx - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD)
            local slotMid = slotTop + (SIDEBAR_BTN_H + SIDEBAR_PAD) / 2
            if localY < slotMid then return i end
        end
    end
    return lastVisibleCatIdx
end

-- Compute drop zone: which button the cursor is over and which zone (above/group/below).
-- Returns: targetCatIdx, mode ("above", "below", "group"), targetBtn
local function ComputeDropZone()
    local scale = UIParent:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local cursorY = cy / scale

    local GROUP_ZONE = 4  -- pixels from center that count as "group" zone

    -- Walk visible sidebar buttons to find which one cursor is over
    for _, btn in ipairs(_sidebarBtns) do
        if btn:IsShown() and btn._catIdx and btn._catIdx > 0 then
            local top = btn:GetTop()
            local bot = btn:GetBottom()
            if top and bot and cursorY <= top and cursorY >= bot then
                local mid = (top + bot) / 2
                local distFromMid = math.abs(cursorY - mid)
                if distFromMid <= GROUP_ZONE then
                    return btn._catIdx, "group", btn
                elseif cursorY > mid then
                    return btn._catIdx, "above", btn
                else
                    return btn._catIdx, "below", btn
                end
            end
        end
    end
    -- Fallback: find nearest category button by Y distance
    local bestIdx, bestDist, bestBtn, bestMode = 1, math.huge, nil, "above"
    for _, btn in ipairs(_sidebarBtns) do
        if btn:IsShown() and btn._catIdx and btn._catIdx > 0 then
            local top = btn:GetTop()
            local bot = btn:GetBottom()
            if top and bot then
                local mid = (top + bot) / 2
                local dist = math.abs(cursorY - mid)
                if dist < bestDist then
                    bestDist = dist
                    bestIdx = btn._catIdx
                    bestBtn = btn
                    bestMode = cursorY > mid and "above" or "below"
                end
            end
        end
    end
    return bestIdx, bestMode, bestBtn
end

-- Compute insert line Y position for a given category target index
local function GetInsertLineY(targetCatIdx)
    -- Offset: header (24) + 2 fixed buttons (All Items + OneBag)
    local topOffset = 24 + 2 * (SIDEBAR_BTN_H + SIDEBAR_PAD)
    local visSlot = 0
    local cats = EUI_CategoryManager:GetCategories()
    for i = 1, #cats do
        local isVisible = false
        for _, btn in ipairs(_sidebarBtns) do
            if btn:IsShown() and btn._catIdx == i then
                isVisible = true
                break
            end
        end
        if isVisible then
            visSlot = visSlot + 1
            if i == targetCatIdx then
                return -topOffset - ((visSlot - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD))
            end
        end
    end
    return -topOffset - (visSlot * (SIDEBAR_BTN_H + SIDEBAR_PAD))
end

local StartSidebarDrag  -- forward declaration (defined below)

-- Shared drag-detect frame for sidebar buttons (hidden when not dragging)
local _sidebarDragDetect = CreateFrame("Frame")
_sidebarDragDetect:Hide()
_sidebarDragDetect._btn = nil
_sidebarDragDetect:SetScript("OnUpdate", function(self)
    local btn = self._btn
    if not btn or not btn._dragPending then self:Hide(); return end
    local _, cy = GetCursorPosition()
    if math.abs(cy - (btn._dragStartY or cy)) > 4 then
        btn._dragPending = false
        btn._didDrag = true
        self:Hide()
        StartSidebarDrag(btn, btn._catIdx, btn._catName, btn._catIcon, btn._catIsAtlas)
    end
end)

local _dragUpdateFrame = CreateFrame("Frame")
_dragUpdateFrame:Hide()
_dragUpdateFrame:SetScript("OnUpdate", function()
    if not _dragFromCatIdx then _dragUpdateFrame:Hide(); return end

    -- Ghost follows cursor
    local ghost = _dragGhost
    if ghost and ghost:IsShown() then
        local cx, cy = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        local gs = ghost:GetScale() or 1
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / (sc * gs), cy / (sc * gs))
    end

    -- Compute drop zone
    local target, mode, targetBtn = ComputeDropZone()

    if target ~= _dragLastTarget or mode ~= _dragLastMode or targetBtn ~= _dragLastBtn then
        _dragLastTarget = target
        _dragLastMode = mode
        _dragLastBtn = targetBtn
        local line = EnsureInsertLine()
        local hl = EnsureGroupHighlight()

        -- Don't group with self
        if mode == "group" and target == _dragFromCatIdx then mode = "above" end

        local cats = EUI_CategoryManager:GetCategories()

        -- Block drops onto or above special entries (Pinned Items, Recent Items).
        -- Nothing should be draggable above the divider.
        local targetCatCheck = cats[target]
        if targetCatCheck and (targetCatCheck.isPinned or targetCatCheck.isRecent) then
            line:Hide(); hl:Hide()
            _dragDropMode = nil; _dragDropTarget = nil
            return
        end
        -- Can't group with or from a noGroup category (e.g. Reagent Bag)
        if mode == "group" and cats[target] and cats[target].noGroup then mode = "below" end
        if mode == "group" and cats[_dragFromCatIdx] and cats[_dragFromCatIdx].noGroup then mode = "above" end

        local fromCat = cats[_dragFromCatIdx]
        local targetCat = cats[target]
        -- Can't group with a grouped member (but CAN group with a group header to join that group)
        if mode == "group" and targetCat and targetCat.groupName and not (targetBtn and targetBtn._isGroupHeader) then
            mode = "above"
        end
        -- Can't group something already in a group with an ungrouped category (would nest groups)
        if mode == "group" and fromCat and fromCat.groupName and not (targetBtn and targetBtn._isGroupHeader) then
            mode = "above"
        end

        if mode == "group" and targetBtn then
            -- Show group highlight
            if line then line:Hide() end
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", targetBtn, "TOPLEFT", 2, 0)
            hl:SetPoint("BOTTOMRIGHT", targetBtn, "BOTTOMRIGHT", -2, 0)
            hl:Show()
            _dragDropMode = "group"
            _dragDropTarget = target
        else
            -- Show insert line
            if hl then hl:Hide() end
            _dragDropMode = "insert"

            -- Resolve actual target index: "above N" = N, "below N" = N+1
            -- Exception: "below header" = same gap as "above first member" = N (not N+1)
            local resolvedTarget = target
            if mode == "below" then
                if targetBtn and targetBtn._isGroupHeader then
                    -- "below header" and "above first member" are the same visual gap
                    resolvedTarget = target
                else
                    resolvedTarget = target + 1
                end
            end

            -- Determine if insert position is inside a group
            local insideGroup = nil
            local fromNoGroup = cats[_dragFromCatIdx] and cats[_dragFromCatIdx].noGroup
            local posInGroup = targetBtn and targetCat and targetCat.groupName
                and (targetBtn._isGroupMember or (targetBtn._isGroupHeader and mode == "below"))
            if posInGroup then
                if fromNoGroup then
                    -- noGroup categories can't enter groups; suppress line entirely
                    if line then line:Hide() end
                    _dragDropTarget = nil
                    _dragInsertGroup = nil
                    return
                end
                insideGroup = targetCat.groupName
            end

            -- No-op check: skip if same position AND group membership isn't changing
            local fromCatGroup = cats[_dragFromCatIdx] and cats[_dragFromCatIdx].groupName
            local groupChanges = (insideGroup or false) ~= (fromCatGroup or false)
            local isNoOp = not groupChanges
                and (resolvedTarget == _dragFromCatIdx or resolvedTarget == _dragFromCatIdx + 1)

            if isNoOp then
                if line then line:Hide() end
                _dragDropTarget = nil
                _dragInsertGroup = nil
            else
                _dragDropTarget = resolvedTarget
                _dragTargetIsHeader = targetBtn and targetBtn._isGroupHeader or false
                _dragInsertGroup = insideGroup

                if target and line then
                    -- Position line in the gap between buttons (centered in SIDEBAR_PAD)
                    local gapOff = math.floor(SIDEBAR_PAD / 2)
                    local leftOff = insideGroup and (4 + SIDEBAR_INDENT) or 4
                    if mode == "below" and targetBtn then
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", targetBtn, "BOTTOMLEFT", leftOff, -gapOff)
                        line:SetPoint("TOPRIGHT", targetBtn, "BOTTOMRIGHT", -4, -gapOff)
                    elseif targetBtn then
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", targetBtn, "TOPLEFT", leftOff, gapOff)
                        line:SetPoint("TOPRIGHT", targetBtn, "TOPRIGHT", -4, gapOff)
                    else
                        local sidebar = EUI_Bags._sidebar
                        local lineY = GetInsertLineY(target)
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", sidebar, "TOPLEFT", leftOff, lineY)
                        line:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, lineY)
                    end
                    line:Show()
                end
            end
        end
    end
end)

StartSidebarDrag = function(btnSelf, catIdx, catName, catIcon, catIsAtlas)
    _dragFromCatIdx = catIdx
    _dragSourceBtn = btnSelf
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil

    -- Ghost: scaled 0.5x, 70% opacity
    local ghost = EnsureDragGhost()
    ghost:SetSize(GetSidebarWidth(), SIDEBAR_BTN_H)
    if catIsAtlas then
        ghost.icon:SetAtlas(catIcon or "")
        ghost.icon:SetTexCoord(0, 1, 0, 1)
    else
        ghost.icon:SetTexture(catIcon or 134400)
        ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    ghost.label:SetText(catName or "?")
    local collapsed = EllesmereUIDB and EllesmereUIDB.bagSidebarCollapsed
    if collapsed then ghost.label:Hide() else ghost.label:Show() end
    ghost:Show()

    -- Source button: fade to 30% (iOS lift effect)
    btnSelf:SetAlpha(0.3)

    EnsureInsertLine()
    _dragUpdateFrame:Show()
end

local function StopSidebarDrag()
    if not _dragFromCatIdx then return end

    if _dragSourceBtn then _dragSourceBtn:SetAlpha(1) end

    -- Capture selected category by reference so we can re-find its index after reorder
    local cats = EUI_CategoryManager:GetCategories()
    local selectedCatRef = (selectedCategoryIndex > 0) and cats[selectedCategoryIndex] or nil
    local savedGroupName = selectedGroupName

    local fromCat = cats[_dragFromCatIdx]
    local fromGroup = fromCat and fromCat.groupName
    local isHeader = _dragSourceBtn and _dragSourceBtn._isGroupHeader
    local dropMode = _dragDropMode
    local dropTarget = _dragDropTarget

    if dropMode == "group" and dropTarget and dropTarget ~= _dragFromCatIdx then
        -- GROUP MODE: merge dragged category with target
        local targetCat = cats[dropTarget]
        local targetGroup = targetCat and targetCat.groupName

        if targetCat then
            -- Group-to-group is always allowed (old group may disband, that's fine)
            if fromGroup then
                EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                ClearGroupOrder(fromGroup)
            end

            if targetGroup then
                -- Move to bottom of group
                local groupMembers = EUI_CategoryManager:GetGroupMembers(targetGroup)
                local lastMemberIdx = groupMembers[#groupMembers]
                local curFromIdx
                for i, cat in ipairs(cats) do
                    if cat == fromCat then curFromIdx = i; break end
                end
                if curFromIdx and lastMemberIdx then
                    local dest = lastMemberIdx + 1
                    if dest > #cats + 1 then dest = #cats + 1 end
                    if curFromIdx ~= dest then
                        EUI_CategoryManager:ReorderCategory(curFromIdx, dest)
                    end
                end
                -- Now add to group (category is already in position)
                -- Re-find index after move
                for i, cat in ipairs(cats) do
                    if cat == fromCat then
                        EUI_CategoryManager:AddToGroup(i, targetGroup)
                        break
                    end
                end
            else
                -- Create new group: move dragged category to right after target first
                local curFromIdx
                for i, cat in ipairs(cats) do
                    if cat == fromCat then curFromIdx = i; break end
                end
                local curTargetIdx
                for i, cat in ipairs(cats) do
                    if cat == targetCat then curTargetIdx = i; break end
                end
                if curFromIdx and curTargetIdx and curFromIdx ~= curTargetIdx then
                    -- Place after target so target stays first in the new group
                    local dest = curTargetIdx + 1
                    if dest > #cats then dest = #cats end
                    EUI_CategoryManager:ReorderCategory(curFromIdx, dest)
                end
                -- Re-find indices after move
                local idx1, idx2
                for i, cat in ipairs(cats) do
                    if cat == targetCat then idx1 = i end
                    if cat == fromCat then idx2 = i end
                end
                if idx1 and idx2 then
                    EUI_CategoryManager:GroupCategories({ idx1, idx2 })
                end
            end
        end
    elseif dropMode == "insert" and dropTarget then
        local target = dropTarget

        local fromGroupName = fromCat and fromCat.groupName
        local dropGroupChanges = (_dragInsertGroup or false) ~= (fromGroupName or false)
        if target ~= _dragFromCatIdx or dropGroupChanges then
            if isHeader and fromGroup then
                -- Group header drag: move ALL members as a block
                -- Use raw dropTarget (not the -1 adjusted target) for block moves
                local rawTarget = dropTarget
                local members = EUI_CategoryManager:GetGroupMembers(fromGroup)
                local minIdx = members[1]
                local blockSize = #members
                if rawTarget < minIdx or rawTarget > minIdx + blockSize - 1 then
                    local removed = {}
                    for m = #members, 1, -1 do
                        removed[#removed + 1] = table.remove(cats, members[m])
                    end
                    local ordered = {}
                    for r = #removed, 1, -1 do ordered[#ordered + 1] = removed[r] end
                    local insertAt
                    if rawTarget > minIdx then
                        insertAt = rawTarget - blockSize
                    else
                        insertAt = rawTarget
                    end
                    if insertAt < 1 then insertAt = 1 end
                    if insertAt > #cats + 1 then insertAt = #cats + 1 end
                    for b = #ordered, 1, -1 do
                        table.insert(cats, insertAt, ordered[b])
                    end
                end
            elseif fromGroup then
                -- Grouped member dragged to insert position
                local members = EUI_CategoryManager:GetGroupMembers(fromGroup)
                local minIdx, maxIdx = members[1], members[#members]

                local inGroup = (_dragInsertGroup == fromGroup)
                    or (not _dragInsertGroup and target >= minIdx and target <= maxIdx)
                if inGroup and target ~= _dragFromCatIdx then
                    -- Check if trying to move above the group (target == minIdx from the header button, not the first member)
                    if target == minIdx and _dragFromCatIdx ~= minIdx and #members >= 2 and _dragTargetIsHeader then
                        -- Ungroup and place above the group
                        EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(fromGroup)
                        local newIdx
                        for i, cat in ipairs(cats) do
                            if cat == fromCat then newIdx = i; break end
                        end
                        if newIdx then
                            EUI_CategoryManager:ReorderCategory(newIdx, minIdx)
                        end
                    else
                        -- Normal intra-group reorder
                        EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                    end
                    if not EUI_CategoryManager:IsGroupNameCustom(fromGroup) then
                        EUI_CategoryManager:RegenerateGroupName(fromGroup)
                    end
                else
                    -- Drag out of group
                    if #members >= 1 then
                        EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(fromGroup)
                        -- Re-find index after ungroup may have shifted things
                        local newIdx
                        for i, cat in ipairs(cats) do
                            if cat == fromCat then newIdx = i; break end
                        end
                        if newIdx then
                            -- Check if destination is inside another group -- auto-join it
                            local destGroup = _dragInsertGroup
                            if destGroup == fromGroup then destGroup = nil end
                            if destGroup then
                                EUI_CategoryManager:ReorderCategory(newIdx, target)
                                -- Re-find after move
                                for i, cat in ipairs(cats) do
                                    if cat == fromCat then
                                        EUI_CategoryManager:AddToGroup(i, destGroup)
                                        break
                                    end
                                end
                                if not EUI_CategoryManager:IsGroupNameCustom(destGroup) then
                                    EUI_CategoryManager:RegenerateGroupName(destGroup)
                                end
                            else
                                EUI_CategoryManager:ReorderCategory(newIdx, target)
                            end
                        end
                    end
                end
            else
                -- Check if insert position is inside a group -- auto-join that group
                local destGroup = _dragInsertGroup
                if destGroup then
                    EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                    for i, cat in ipairs(cats) do
                        if cat == fromCat then
                            EUI_CategoryManager:AddToGroup(i, destGroup)
                            break
                        end
                    end
                    if not EUI_CategoryManager:IsGroupNameCustom(destGroup) then
                        EUI_CategoryManager:RegenerateGroupName(destGroup)
                    end
                else
                    EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                end
            end
        end
    end

    -- Re-sort any categories affected by group membership changes
    local newFromCat = nil
    for i, cat in ipairs(cats) do if cat == fromCat then newFromCat = cat; break end end
    local oldGroup = fromGroup
    local newGroup = newFromCat and newFromCat.groupName
    if oldGroup ~= newGroup then
        -- Group membership changed: resort affected groups + the moved category
        local resortCats = {}
        -- Find the moved category's current index
        for i, cat in ipairs(cats) do
            if cat == fromCat then resortCats[#resortCats + 1] = i; break end
        end
        -- Resort old group members
        if oldGroup then
            local oldMembers = EUI_CategoryManager:GetGroupMembers(oldGroup)
            if oldMembers then
                for _, mi in ipairs(oldMembers) do resortCats[#resortCats + 1] = mi end
            end
        end
        -- Resort new group members
        if newGroup then
            local newMembers = EUI_CategoryManager:GetGroupMembers(newGroup)
            if newMembers then
                for _, mi in ipairs(newMembers) do resortCats[#resortCats + 1] = mi end
            end
        end
        ResortAfterGroupChange(resortCats, newGroup or oldGroup)
        -- If both old and new groups exist, resort both
        if oldGroup and newGroup and oldGroup ~= newGroup then
            ResortAfterGroupChange({}, oldGroup)
        end
    end

    -- Restore selection by reference (index may have shifted during reorder)
    if selectedCatRef then
        for i, cat in ipairs(cats) do
            if cat == selectedCatRef then selectedCategoryIndex = i; break end
        end
    end
    selectedGroupName = savedGroupName

    _dragFromCatIdx = nil
    _dragSourceBtn = nil
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil
    _dragTargetIsHeader = nil
    _dragInsertGroup = nil
    _dragUpdateFrame:Hide()
    if _dragGhost then _dragGhost:Hide() end
    if _dragInsertLine then _dragInsertLine:Hide() end
    if _dragGroupHL then _dragGroupHL:Hide() end
    if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
    EUI_Bags:RefreshInventory()
end

local function CreateSidebar()
    if EUI_Bags._sidebar then return end

    local sidebar = CreateFrame("Frame", nil, EUI_Bags)
    sidebar:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", 0, -(HEADER_H))
    sidebar:SetPoint("BOTTOMLEFT", EUI_Bags.Footer, "TOPLEFT", 0, 0)
    sidebar:SetWidth(GetSidebarWidth())
    sidebar.bg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
    sidebar.bg:SetAllPoints()
    sidebar.bg:SetColorTexture(0, 0, 0, 0.25)

    -- Right-edge separator
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    sidebar.sep = sidebar:CreateTexture(nil, "ARTWORK")
    sidebar.sep:SetWidth(px)
    sidebar.sep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebar.sep:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebar.sep:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- Sidebar header: "Categories" label + collapse arrow
    local SIDEBAR_HDR_H = 24
    local sidebarHdr = CreateFrame("Frame", nil, sidebar)
    sidebarHdr:SetHeight(SIDEBAR_HDR_H)
    sidebarHdr:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    sidebarHdr:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)

    sidebarHdr._label = sidebarHdr:CreateFontString(nil, "OVERLAY")
    SetBagFont(sidebarHdr._label, 10)
    sidebarHdr._label:SetPoint("LEFT", sidebarHdr, "LEFT", 8, 0)
    sidebarHdr._label:SetText("Categories")
    sidebarHdr._label:SetTextColor(0.5, 0.5, 0.5)

    local ARROW_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png"
    local collapseBtn = CreateFrame("Button", nil, sidebarHdr)
    collapseBtn:SetSize(12, 12)
    collapseBtn:SetPoint("RIGHT", sidebarHdr, "RIGHT", -6, 0)
    collapseBtn._icon = collapseBtn:CreateTexture(nil, "OVERLAY")
    collapseBtn._icon:SetAllPoints()
    collapseBtn._icon:SetTexture(ARROW_ICON)
    collapseBtn._icon:SetAlpha(0.4)

    local function UpdateCollapseArrow()
        local collapsed = EllesmereUIDB and EllesmereUIDB.bagSidebarCollapsed
        collapseBtn:ClearAllPoints()
        if collapsed then
            collapseBtn._icon:SetRotation(math.pi)
            collapseBtn:SetPoint("CENTER", sidebarHdr, "CENTER", 0, 0)
        else
            collapseBtn._icon:SetRotation(0)
            collapseBtn:SetPoint("RIGHT", sidebarHdr, "RIGHT", -6, 0)
        end
    end
    UpdateCollapseArrow()

    collapseBtn:SetScript("OnEnter", function(self)
        self._icon:SetAlpha(0.9)
        local collapsed = EllesmereUIDB and EllesmereUIDB.bagSidebarCollapsed
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(self, collapsed and "Expand Sidebar" or "Collapse Sidebar")
        end
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        self._icon:SetAlpha(0.4)
        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
    end)
    collapseBtn:SetScript("OnClick", function()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        -- Determine which edge to preserve based on screen position
        local center = EUI_Bags:GetCenter()
        local screenW = UIParent:GetWidth()
        local onRightSide = center and screenW and (center > screenW / 2)
        local oldWidth = onRightSide and EUI_Bags:GetWidth() or nil

        EllesmereUIDB.bagSidebarCollapsed = not EllesmereUIDB.bagSidebarCollapsed
        UpdateCollapseArrow()
        sidebar:SetWidth(GetSidebarWidth())
        EUI_Bags:RefreshInventory()

        -- Shift frame by width difference to preserve right edge
        if onRightSide and oldWidth then
            local newWidth = EUI_Bags:GetWidth()
            local shift = oldWidth - newWidth
            if math.abs(shift) > 0.5 then
                local point, rel, relPoint, x, y = EUI_Bags:GetPoint()
                EUI_Bags:ClearAllPoints()
                EUI_Bags:SetPoint(point, rel, relPoint, x + shift, y)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.bagsPosition = { point = point, relativePoint = relPoint, x = x + shift, y = y }
            end
        end
    end)

    -- Sidebar scroll frame (below header, above footer)
    local sidebarSF = CreateFrame("ScrollFrame", nil, sidebar)
    sidebarSF:SetPoint("TOPLEFT", sidebarHdr, "BOTTOMLEFT", 0, 0)
    sidebarSF:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSF:EnableMouseWheel(true)
    local sidebarChild = CreateFrame("Frame", nil, sidebarSF)
    sidebarChild:SetWidth(GetSidebarWidth())
    sidebarSF:SetScrollChild(sidebarChild)

    local SIDEBAR_SCROLL_STEP = 28
    sidebarSF:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = sidebarChild:GetHeight() - self:GetHeight()
        if maxScroll <= 0 then return end
        local cur = self:GetVerticalScroll()
        local newVal = math.max(0, math.min(maxScroll, cur - delta * SIDEBAR_SCROLL_STEP))
        self:SetVerticalScroll(newVal)
    end)

    EUI_Bags._sidebar = sidebar
    EUI_Bags._sidebarHdr = sidebarHdr
    EUI_Bags._sidebarSF = sidebarSF
    EUI_Bags._sidebarChild = sidebarChild
    EUI_Bags._collapseBtn = collapseBtn
end

-- Show context menu for grouping categories
local function ShowCategoryContextMenu(btn, catIdx, isGroupHeader, isGroupMember)
    local cats = EUI_CategoryManager:GetCategories()
    local cat = cats[catIdx]
    if not cat then return end

    MenuUtil.CreateContextMenu(btn, function(_, rootDescription)
        local myGroup = cat.groupName

        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.bagHiddenInAllItems then EllesmereUIDB.bagHiddenInAllItems = {} end
        local hiddenSet = EllesmereUIDB.bagHiddenInAllItems

        if isGroupHeader and myGroup then
            -- Group header: Rename + Disband
            rootDescription:CreateButton("Rename", function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Group",
                    message = "Enter a new name for this group:",
                    placeholder = myGroup,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == myGroup then return end
                        EUI_CategoryManager:RenameGroup(myGroup, newName)
                        EUI_CategoryManager:SetGroupNameCustom(newName, true)
                        if selectedGroupName == myGroup then selectedGroupName = newName end
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            rootDescription:CreateButton("Disband Group", function()
                ClearGroupOrder(myGroup)
                EUI_CategoryManager:DisbandGroup(myGroup)
                if selectedGroupName == myGroup then selectedGroupName = nil; selectedCategoryIndex = 0 end
                EUI_Bags:RefreshInventory()
            end)
            local groupHidden = hiddenSet[myGroup]
            rootDescription:CreateButton(groupHidden and "Show in All Items" or "Hide in All Items", function()
                hiddenSet[myGroup] = not groupHidden or nil
                EUI_Bags:RefreshInventory()
            end)
        elseif isGroupMember and myGroup then
            -- Group member: Rename + Ungroup
            rootDescription:CreateButton("Rename", function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Category",
                    message = "Enter a new name for \"" .. cat.name .. "\":",
                    placeholder = cat.name,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == cat.name then return end
                        EUI_CategoryManager:RenameCategory(catIdx, newName)
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            rootDescription:CreateButton("Ungroup " .. cat.name, function()
                ClearGroupOrder(myGroup)
                EUI_CategoryManager:UngroupCategory(catIdx)
                EUI_Bags:RefreshInventory()
            end)
        else
            rootDescription:CreateButton("Rename", function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Category",
                    message = "Enter a new name for \"" .. cat.name .. "\":",
                    placeholder = cat.name,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == cat.name then return end
                        EUI_CategoryManager:RenameCategory(catIdx, newName)
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)

            if not cat.noGroup then
                -- "Create Group With" submenu
                local groupSub = rootDescription:CreateButton("Create Group With")
                local hasOptions = false
                for ci, other in ipairs(cats) do
                    if ci ~= catIdx and not other.groupName and not other.noGroup then
                        hasOptions = true
                        groupSub:CreateButton(other.name, function()
                            EUI_CategoryManager:GroupCategories({ catIdx, ci })
                            EUI_Bags:RefreshInventory()
                        end)
                    end
                end

                -- "Add to existing group..." if groups exist
                local groupNames = EUI_CategoryManager:GetGroupNames()
                if #groupNames > 0 then
                    local addSub = rootDescription:CreateButton("Add to Group")
                    for _, gn in ipairs(groupNames) do
                        addSub:CreateButton(gn, function()
                            EUI_CategoryManager:AddToGroup(catIdx, gn)
                            EUI_Bags:RefreshInventory()
                        end)
                    end
                end
            end

            if not cat.noMove then
                local catKey = cat._defaultName
                local catHidden = hiddenSet[catKey]
                rootDescription:CreateButton(catHidden and "Show in All Items" or "Hide in All Items", function()
                    hiddenSet[catKey] = not catHidden or nil
                    EUI_Bags:RefreshInventory()
                end)
            end
        end
    end)
end

local function BuildSidebarButtons(categoryCounts, totalCount)
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return end
    local collapsed = EllesmereUIDB and EllesmereUIDB.bagSidebarCollapsed
    local sidebarW = GetSidebarWidth()
    sidebar:SetWidth(sidebarW)

    if EUI_Bags._sidebarHdr then
        if collapsed then EUI_Bags._sidebarHdr._label:Hide()
        else EUI_Bags._sidebarHdr._label:Show() end
    end

    local cats = EUI_CategoryManager and EUI_CategoryManager:GetCategories() or {}

    -- Build display list: { catIdx, name, icon, count, isGroupHeader, groupName, indent }
    local displayList = {}
    local defaultOneBag = EllesmereUIDB and EllesmereUIDB.bagDefaultOneBag
    if defaultOneBag then
        displayList[#displayList + 1] = { catIdx = -1, name = "OneBag", icon = 133634, count = totalCount }
        displayList[#displayList + 1] = { catIdx = 0, name = "All Items", icon = 133633, count = totalCount }
    else
        displayList[#displayList + 1] = { catIdx = 0, name = "All Items", icon = 133633, count = totalCount }
        displayList[#displayList + 1] = { catIdx = -1, name = "OneBag", icon = 133634, count = totalCount }
    end

    -- Categories with group support
    local renderedGroups = {}
    for ci, cat in ipairs(cats) do
        if cat.groupName then
            if not renderedGroups[cat.groupName] then
                renderedGroups[cat.groupName] = true
                -- Group header: sum counts of all members
                local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                local groupCount = 0
                for _, mi in ipairs(members) do
                    groupCount = groupCount + (categoryCounts and categoryCounts[mi] or 0)
                end
                -- Use first member's icon for group
                local firstCat = cats[members[1]]
                local groupIcon = firstCat and firstCat.icon or 134400
                local groupIsAtlas = firstCat and firstCat.isAtlas
                displayList[#displayList + 1] = {
                    catIdx = members[1], name = cat.groupName, icon = groupIcon, isAtlas = groupIsAtlas,
                    count = groupCount, isGroupHeader = true, groupName = cat.groupName,
                }
                -- Indented members (hidden when collapsed)
                if not collapsed then
                    for _, mi in ipairs(members) do
                        local mc = cats[mi]
                        displayList[#displayList + 1] = {
                            catIdx = mi, name = mc.name, icon = mc.icon or 134400, isAtlas = mc.isAtlas,
                            count = categoryCounts and categoryCounts[mi] or 0,
                            indent = true, groupName = cat.groupName, isGroupMember = true,
                        }
                    end
                end
            end
        else
            local count = categoryCounts and categoryCounts[ci] or 0
            local isUserCreated = not cat.isCatchAll and (not cat.types or #cat.types == 0)
            -- Skip Pinned/Recent Items if disabled
            if cat.isPinned and EllesmereUIDB and EllesmereUIDB.bagShowPinnedItems == false then
                -- skip
            elseif cat.isRecent and EllesmereUIDB and EllesmereUIDB.bagShowRecentItems == false then
                -- skip
            else
                displayList[#displayList + 1] = { catIdx = ci, name = cat.name, icon = cat.icon or 134400, isAtlas = cat.isAtlas, count = count, noMove = cat.noMove, isPinned = cat.isPinned, isRecent = cat.isRecent }
            end
        end
    end

    -- Hide empty categories (sidebar-only visual, does not affect grouping)
    local hideEmpty = not EllesmereUIDB or EllesmereUIDB.bagHideEmptyCategories ~= false
    if hideEmpty then
        local filtered = {}
        for _, entry in ipairs(displayList) do
            local keep = true
            if entry.count == 0 then
                -- Always keep: All Items, OneBag, noMove (Pinned/Recent)
                if entry.catIdx >= 1 and not entry.noMove then
                    if entry.isGroupHeader then
                        -- Hide group header if all members are 0
                        keep = false
                    elseif entry.isGroupMember then
                        keep = false
                    else
                        keep = false
                    end
                end
            end
            if keep then filtered[#filtered + 1] = entry end
        end
        displayList = filtered
    end

    -- Ensure enough buttons exist
    for i = 1, #displayList do
        if not _sidebarBtns[i] then
            local btn = CreateFrame("Button", nil, EUI_Bags._sidebarChild or sidebar)
            btn:SetHeight(SIDEBAR_BTN_H)
            btn._indicator = btn:CreateTexture(nil, "OVERLAY")
            local PP = EUI and EUI.PP
            local px = (PP and PP.mult) or 1
            btn._indicator:SetWidth(px * 2)
            btn._indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            btn._indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            btn._bg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            btn._bg:SetAllPoints()
            btn._bg:SetColorTexture(1, 1, 1, 0)
            btn._icon = btn:CreateTexture(nil, "ARTWORK")
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._label = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._label, 11)
            btn._label:SetJustifyH("LEFT")
            btn._label:SetWordWrap(false)
            btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
            btn._label:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
            btn._count = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._count, 10)
            btn._count:SetJustifyH("RIGHT")
            btn._count:SetTextColor(0.5, 0.5, 0.5)
            btn._count:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

            btn:SetScript("OnEnter", function(self)
                if _dragFromCatIdx then return end
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (not self._isGroupHeader and self._catIdx == selectedCategoryIndex and not selectedGroupName)
                if not isSel then self._bg:SetColorTexture(1, 1, 1, 0.06) end
                if (EllesmereUIDB and EllesmereUIDB.bagSidebarCollapsed) and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, (self._catName or "?") .. " (" .. (self._catCount or 0) .. ")")
                end
            end)
            btn:SetScript("OnLeave", function(self)
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (not self._isGroupHeader and self._catIdx == selectedCategoryIndex and not selectedGroupName)
                if not isSel then self._bg:SetColorTexture(1, 1, 1, 0) end
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if self._catIdx > 0 then ShowCategoryContextMenu(self, self._catIdx, self._isGroupHeader, self._isGroupMember) end
                    return
                end
                if self._didDrag then self._didDrag = false; return end
                if self._isGroupHeader and self._groupName then
                    selectedGroupName = self._groupName
                    selectedCategoryIndex = 0
                elseif self._isGroupMember and self._groupName then
                    selectedGroupName = nil
                    selectedCategoryIndex = self._catIdx
                else
                    selectedGroupName = nil
                    selectedCategoryIndex = self._catIdx
                end
                if EUI_Bags._scrollFrame then EUI_Bags._scrollFrame:SetVerticalScroll(0) end
                EUI_Bags:RefreshInventory()
            end)
            btn:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                if self._catIdx <= 0 or self._noMove then return end
                self._didDrag = false
                local _, startY = GetCursorPosition()
                self._dragStartY = startY
                self._dragPending = true
                _sidebarDragDetect._btn = self
                _sidebarDragDetect:Show()
            end)
            btn:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" then return end
                self._dragPending = false
                _sidebarDragDetect:Hide()
                if self._didDrag then StopSidebarDrag() end
            end)


            _sidebarBtns[i] = btn
        end
    end

    -- Hide excess
    for i = #displayList + 1, #_sidebarBtns do _sidebarBtns[i]:Hide() end

    -- Separator line between All Items/OneBag and categories
    if not sidebar._catDivider then
        local PP = EUI and EUI.PP
        local px = (PP and PP.mult) or 1
        local div = (sidebarChild or sidebar):CreateTexture(nil, "ARTWORK")
        div:SetHeight(px)
        div:SetColorTexture(0.2, 0.2, 0.2, 1)
        sidebar._catDivider = div
    end

    -- Position and populate (buttons go in the scroll child)
    local sidebarChild = EUI_Bags._sidebarChild
    if sidebarChild then sidebarChild:SetWidth(sidebarW) end
    local y = 0
    local ar, ag, ab = GetAccentRGB()
    local INDENT = SIDEBAR_INDENT

    for i, entry in ipairs(displayList) do
        local btn = _sidebarBtns[i]
        local isSelected
        if entry.isGroupHeader then
            isSelected = (entry.groupName == selectedGroupName)
        else
            isSelected = (not selectedGroupName and entry.catIdx == selectedCategoryIndex)
        end

        btn._catIdx = entry.catIdx
        btn._catName = entry.name
        btn._catIcon = entry.icon
        btn._catIsAtlas = entry.isAtlas
        btn._catCount = entry.count
        btn._isGroupHeader = entry.isGroupHeader or false
        btn._isGroupMember = entry.isGroupMember or false
        btn._groupName = entry.groupName
        btn._noMove = entry.noMove or false
        btn._isPinned = entry.isPinned or false

        btn:SetParent(sidebarChild or sidebar)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", 0, y)
        btn:SetWidth(sidebarW)

        local leftPad = (entry.indent and not collapsed) and (8 + INDENT) or 8
        btn._icon:ClearAllPoints()
        if collapsed then
            btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        else
            btn._icon:SetPoint("LEFT", btn, "LEFT", leftPad, 0)
        end
        if entry.isAtlas then
            btn._icon:SetAtlas(entry.icon)
            btn._icon:SetTexCoord(0, 1, 0, 1)
        else
            btn._icon:SetTexture(entry.icon)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        btn._icon:SetAlpha(isSelected and 1 or 0.75)
        -- Smaller icon for indented members
        if entry.indent then
            btn._icon:SetSize(SIDEBAR_ICON_SIZE - 2, SIDEBAR_ICON_SIZE - 2)
        else
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        end

        if collapsed then
            btn._label:Hide()
            btn._count:Hide()
        else
            btn._label:Show()
            btn._label:SetText(entry.name)
            btn._label:SetTextColor(1, 1, 1, isSelected and 1 or 0.75)

            btn._count:Show()
            btn._count:SetText(tostring(entry.count))
        end

        if isSelected then
            btn._indicator:SetColorTexture(ar, ag, ab, 1)
            btn._indicator:Show()
            btn._bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            btn._indicator:Hide()
            btn._bg:SetColorTexture(1, 1, 1, 0)
        end

        btn:Show()
        y = y - SIDEBAR_BTN_H - SIDEBAR_PAD

        -- Divider after the last special entry (Pinned or Recent)
        local isLastSpecial = entry.isPinned or entry.isRecent
        local nextEntry = displayList[i + 1]
        local nextIsRegular = nextEntry and not nextEntry.isPinned and not nextEntry.isRecent
        if isLastSpecial and nextIsRegular and sidebar._catDivider then
            y = y - 4  -- spacing above line
            local div = sidebar._catDivider
            div:SetParent(sidebarChild or sidebar)
            div:ClearAllPoints()
            local inset = math.floor(sidebarW * 0.08)
            div:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", inset, y)
            div:SetPoint("TOPRIGHT", sidebarChild or sidebar, "TOPRIGHT", -inset, y)
            div:Show()
            y = y - (div:GetHeight() or 1) - 4  -- spacing below line
        end
    end

    -- Set scroll child height to content height
    if sidebarChild then
        sidebarChild:SetHeight(math.abs(y) + 4)
    end
end

-------------------------------------------------------------------------------
--  Category header pool (for "All Items" view)
-------------------------------------------------------------------------------
local _catHeaders = {}  -- pool of header frames

local function GetOrCreateCatHeader(idx)
    if _catHeaders[idx] then return _catHeaders[idx] end
    local f = CreateFrame("Frame", nil, EUI_Bags)
    f:SetHeight(20)
    f._label = f:CreateFontString(nil, "OVERLAY")
    SetBagFont(f._label, 11)
    f._label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._label:SetTextColor(0.7, 0.7, 0.7)
    f._label:SetJustifyH("LEFT")
    f._hint = f:CreateFontString(nil, "OVERLAY")
    SetBagFont(f._hint, 10)
    f._hint:SetPoint("LEFT", f._label, "RIGHT", 4, 0)
    f._hint:SetTextColor(0.7, 0.7, 0.7, 0.9)
    f._hint:SetJustifyH("LEFT")
    f._hint:SetText("")
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    f._line = f:CreateTexture(nil, "ARTWORK")
    f._line:SetHeight(px)
    f._line:SetPoint("LEFT", f._hint, "RIGHT", 6, 0)
    f._line:SetPoint("RIGHT", f, "RIGHT", -SPACING, 0)
    f._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    _catHeaders[idx] = f
    return f
end

-------------------------------------------------------------------------------
--  Scroll Frame + Scrollbar for item grid
-------------------------------------------------------------------------------
local SCROLLBAR_W     = 4   -- thumb width
local SCROLLBAR_HIT_W = 16  -- invisible hit area width
local SCROLL_STEP     = 40  -- pixels per mouse wheel tick
local THUMB_MIN_H     = 20  -- minimum thumb height

local function CreateBagScrollFrame()
    if EUI_Bags._scrollFrame then return end

    local sidebarW = GetSidebarWidth()

    -- ScrollFrame: fills between header, footer, and sidebar
    local sf = CreateFrame("ScrollFrame", nil, EUI_Bags)
    sf:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", sidebarW, -(HEADER_H + 1))
    sf:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    sf:EnableMouseWheel(true)

    -- Scroll child: tall frame that holds all items
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(sf:GetWidth())
    child:SetHeight(1)  -- updated by RefreshInventory
    child:EnableMouse(false)  -- let clicks pass through to item buttons
    sf:SetScrollChild(child)

    -- Track (always visible)
    local track = CreateFrame("Button", nil, EUI_Bags)
    track:SetWidth(SCROLLBAR_HIT_W)
    track:SetPoint("TOPRIGHT", EUI_Bags, "TOPRIGHT", -1, -(HEADER_H + 1))
    track:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    track:SetFrameLevel(sf:GetFrameLevel() + 5)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetWidth(SCROLLBAR_W)
    trackBg:SetPoint("TOP", track, "TOP", 0, 0)
    trackBg:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    trackBg:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    trackBg:SetColorTexture(1, 1, 1, 0.06)

    -- Thumb
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(SCROLLBAR_W)
    thumb:SetColorTexture(1, 1, 1, 0.25)
    thumb:Hide()

    local _isDragging = false
    local _dragStartY = 0
    local _dragStartPct = 0

    local function GetScrollMetrics()
        local scrollRange = sf:GetVerticalScrollRange()
        if not scrollRange or scrollRange <= 0 then return nil end
        local trackH = track:GetHeight()
        local ext = sf:GetHeight() / (sf:GetHeight() + scrollRange)
        local thumbH = math.max(THUMB_MIN_H, trackH * ext)
        local maxTravel = trackH - thumbH
        if maxTravel <= 0 then return nil end
        local pct = sf:GetVerticalScroll() / scrollRange
        return pct, thumbH, maxTravel, scrollRange
    end

    local function UpdateThumb()
        -- Clamp scroll to current range (content may have shrunk)
        local range = sf:GetVerticalScrollRange() or 0
        local cur = sf:GetVerticalScroll()
        if cur > range then sf:SetVerticalScroll(range) end
        local pct, thumbH, maxTravel = GetScrollMetrics()
        if not pct then
            thumb:Hide()
            trackBg:Hide()
            return
        end
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(pct * maxTravel))
        thumb:Show()
        trackBg:Show()
    end

    -- Mouse wheel
    sf:SetScript("OnMouseWheel", function(_, delta)
        local _, _, _, scrollRange = GetScrollMetrics()
        if not scrollRange then return end
        local cur = sf:GetVerticalScroll()
        local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
        sf:SetVerticalScroll(newVal)
        UpdateThumb()
    end)

    -- Also enable mouse wheel on the main bag frame (items might not cover full area)
    EUI_Bags:EnableMouseWheel(true)
    EUI_Bags:SetScript("OnMouseWheel", function(_, delta)
        local _, _, _, scrollRange = GetScrollMetrics()
        if not scrollRange then return end
        local cur = sf:GetVerticalScroll()
        local newVal = math.max(0, math.min(scrollRange, cur - delta * SCROLL_STEP))
        sf:SetVerticalScroll(newVal)
        UpdateThumb()
    end)

    -- Thumb dragging (dragUpdate must be declared before OnMouseDown uses it)
    local dragUpdate = CreateFrame("Frame")
    dragUpdate:Hide()
    dragUpdate:SetScript("OnUpdate", function(self)
        if not _isDragging then self:Hide(); return end
        if not IsMouseButtonDown("LeftButton") then
            _isDragging = false; self:Hide()
            thumb:SetColorTexture(1, 1, 1, 0.25)
            return
        end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then _isDragging = false; self:Hide(); return end
        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local deltaY = (_dragStartY - cy / scale)
        local deltaPct = deltaY / maxTravel
        local newPct = math.max(0, math.min(1, _dragStartPct + deltaPct))
        sf:SetVerticalScroll(newPct * scrollRange)
        UpdateThumb()
    end)

    track:RegisterForDrag("LeftButton")
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then return end

        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local trackTop = track:GetTop() * scale
        local cursorLocalY = (trackTop - cy) / scale

        -- Check if cursor is on the thumb
        local thumbTop = pct * maxTravel
        local thumbBot = thumbTop + thumbH
        if cursorLocalY >= thumbTop and cursorLocalY <= thumbBot then
            -- Start drag from thumb
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = pct
            dragUpdate:Show()
        else
            -- Click on track: jump to position
            local clickPct = math.max(0, math.min(1, (cursorLocalY - thumbH / 2) / maxTravel))
            sf:SetVerticalScroll(clickPct * scrollRange)
            UpdateThumb()
            -- Start drag from new position
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = clickPct
            dragUpdate:Show()
        end
    end)

    track:SetScript("OnMouseUp", function()
        _isDragging = false
    end)

    -- Hover effect on thumb
    track:SetScript("OnEnter", function() thumb:SetColorTexture(1, 1, 1, 0.4) end)
    track:SetScript("OnLeave", function()
        if not _isDragging then thumb:SetColorTexture(1, 1, 1, 0.25) end
    end)

    EUI_Bags._scrollFrame = sf
    EUI_Bags._scrollChild = child
    EUI_Bags._scrollTrack = track
    EUI_Bags._scrollThumb = thumb
    EUI_Bags._updateThumb = UpdateThumb
end

-------------------------------------------------------------------------------
--  RefreshInventory -- new pipeline
-------------------------------------------------------------------------------
function EUI_Bags:RefreshInventory()
    if not EUI_Bags:IsVisible() then return end
    local db = EllesmereUIDB or {}

    C_NewItems.ClearAll()

    -- 1. Gather items from all bags (0-4 + reagent bag 5)
    local _t0Scan = ProfBegin("BagScan")
    ReleaseAllSlotTables()
    local tempItems = {}
    local emptySlots = {}

    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                local d = AcquireSlotTable()
                d.bag = bag; d.slot = slot; d.info = info; d.itemLink = itemLink
                -- Pre-cache per-item data for RenderButton (zero API calls at render time)
                if itemLink then
                    local _, _, q, ilvl = GetItemInfo(itemLink)
                    d._giQuality = q
                    d._giIlvl = ilvl
                    -- Track rank + cooldown: only for types that need them
                    local isGear = IsGearItem(itemLink)
                    d._isGear = isGear
                    if isGear and GetUpgradeTrack then
                        local rankText, trackColor = GetUpgradeTrack(itemLink)
                        if rankText and rankText ~= "" then
                            d._giTrackRank = rankText
                            d._giTrackColor = trackColor
                        end
                    end
                    -- Warbound check (for warbank dim overlay)
                    if C_Bank and C_Bank.IsItemAllowedInBankType then
                        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                        if loc and C_Item.DoesItemExist(loc) then
                            d._isWarbound = C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc)
                        end
                    end
                    -- Keystone data (rare, fast string match gates the API calls)
                    if info.itemID == 180653 or itemLink:find("keystone:", 1, true) then
                        local ksMap, ksLvl = itemLink:match("keystone:[^:]*:(%d+):(%d+)")
                        if ksLvl then
                            d._ksLevel = ksLvl
                            d._ksAbbrev = AbbrevDungeon(tonumber(ksMap))
                            local ok, color = pcall(C_ChallengeMode.GetKeystoneLevelRarityColor, tonumber(ksLvl))
                            if ok and color then
                                d._ksR = color.r; d._ksG = color.g; d._ksB = color.b
                            end
                        end
                    end
                    -- Cooldown (any item can have a cooldown: trinkets, consumables, toys, etc.)
                    local cdStart, cdDur, cdEnable = C_Container.GetContainerItemCooldown(bag, slot)
                    if cdEnable and cdEnable ~= 0 and cdStart > 0 and cdDur > 0 then
                        d._cdStart = cdStart; d._cdDuration = cdDur
                    end
                end
                tempItems[#tempItems + 1] = d
            else
                local d = AcquireSlotTable()
                d.bag = bag; d.slot = slot
                emptySlots[#emptySlots + 1] = d
            end
        end
    end
    ProfEnd("BagScan", _t0Scan)

    -- 1b. Detect manual item swaps and update saved visual order
    local isAllItems = selectedCategoryIndex == 0 and not selectedGroupName
    local swapDetected = DetectAndApplySwaps(tempItems, isAllItems)
    TakeBagSnapshot(tempItems)

    -- Show blocked-swap tooltip in category/group views (not All Items, not OneBag)
    if swapDetected and not isAllItems and selectedCategoryIndex ~= -1 then
        if EUI.ShowWidgetTooltip then
            EUI.ShowWidgetTooltip(EUI_Bags, "Positions can only be changed\nin the All Items or OneBag categories", { anchor = "cursor" })
            C_Timer.After(3, function()
                if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
            end)
        end
    end

    -- 2. Classify all items and get counts
    local _t0Classify = ProfBegin("ClassifyAll")
    local categoryCounts, totalCount = EUI_CategoryManager:ClassifyAll(tempItems)
    ProfEnd("ClassifyAll", _t0Classify)

    -- 2a. Snapshot slot->category mapping for partial refresh
    wipe(_slotCategories)
    for _, data in ipairs(tempItems) do
        if data.categoryIndex and data.bag and data.slot then
            _slotCategories[data.bag * 1000 + data.slot] = data.categoryIndex
        end
    end

    -- 2b. Compute display-only counts (pinned + recent stay in normal categories)
    local recentCatIdx, pinnedCatIdx
    do
        local cats = EUI_CategoryManager:GetCategories()
        for i, cat in ipairs(cats) do
            if cat.isRecent then recentCatIdx = i end
            if cat.isPinned then pinnedCatIdx = i end
        end
    end
    local recentCount = 0
    local showRecent = not EllesmereUIDB or EllesmereUIDB.bagShowRecentItems ~= false
    if recentCatIdx and EUI_Bags._recentItems and showRecent then
        for _, data in ipairs(tempItems) do
            if data.info and data.info.itemID and EUI_Bags._recentItems[data.info.itemID] then
                recentCount = recentCount + 1
            end
        end
        categoryCounts[recentCatIdx] = recentCount
    end
    local showPinned = not EllesmereUIDB or EllesmereUIDB.bagShowPinnedItems ~= false
    local pinnedSet = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
    if pinnedCatIdx and pinnedSet and showPinned then
        local pinnedCount = 0
        for _, data in ipairs(tempItems) do
            if data.info and data.info.itemID and pinnedSet[data.info.itemID] then
                pinnedCount = pinnedCount + 1
            end
        end
        categoryCounts[pinnedCatIdx] = pinnedCount
    end

    -- 3. Update sidebar
    local _t0Sidebar = ProfBegin("BuildSidebarButtons")
    BuildSidebarButtons(categoryCounts, totalCount)
    ProfEnd("BuildSidebarButtons", _t0Sidebar)

    -- Cache counts for partial refresh
    _lastCatCounts = categoryCounts
    _lastTotalCount = totalCount

    -- 4. Filter items by selected category/group + search
    local _t0Filter = ProfBegin("FilterAndSort")
    local isRecentView = recentCatIdx and selectedCategoryIndex == recentCatIdx
    local isPinnedView = pinnedCatIdx and selectedCategoryIndex == pinnedCatIdx
    local filterSet = nil  -- nil = show all
    if selectedGroupName then
        filterSet = {}
        local members = EUI_CategoryManager:GetGroupMembers(selectedGroupName)
        for _, mi in ipairs(members) do filterSet[mi] = true end
    elseif selectedCategoryIndex > 0 and not isRecentView and not isPinnedView then
        filterSet = { [selectedCategoryIndex] = true }
    end

    local displayItems = {}
    for _, data in ipairs(tempItems) do
        local show = true
        if isRecentView then
            show = data.info and data.info.itemID and EUI_Bags._recentItems and EUI_Bags._recentItems[data.info.itemID]
        elseif isPinnedView then
            show = data.info and data.info.itemID and pinnedSet and pinnedSet[data.info.itemID]
        elseif filterSet then
            show = data.categoryIndex and filterSet[data.categoryIndex]
        end
        if show and data.info and data.info.isFiltered then show = false end
        if show then displayItems[#displayItems + 1] = data end
    end

    -- 4b. Pending resort: sort + save order for categories invalidated by group changes.
    -- This reuses the already-scanned tempItems instead of re-scanning all bags.
    if next(_pendingResortCats) or next(_pendingResortGroups) then
        local cats = EUI_CategoryManager:GetCategories()
        local itemsByCat = {}
        for _, data in ipairs(tempItems) do
            local ci = data.categoryIndex
            if ci then
                if not itemsByCat[ci] then itemsByCat[ci] = {} end
                itemsByCat[ci][#itemsByCat[ci] + 1] = data
            end
        end
        for ci in pairs(_pendingResortCats) do
            local items = itemsByCat[ci] or {}
            if #items > 1 then PreCacheSortFields(items); table.sort(items, VisualSortCompare) end
            SaveCategoryOrder(ci, items)
        end
        for gn in pairs(_pendingResortGroups) do
            local members = EUI_CategoryManager:GetGroupMembers(gn)
            if members and #members > 0 then
                local merged = {}
                for _, mi in ipairs(members) do
                    for _, data in ipairs(itemsByCat[mi] or {}) do
                        merged[#merged + 1] = data
                    end
                end
                if #merged > 1 then PreCacheSortFields(merged); table.sort(merged, VisualSortCompare) end
                SaveCategoryOrder(gn, merged)
            end
        end
        wipe(_pendingResortCats)
        wipe(_pendingResortGroups)
    end

    ProfEnd("FilterAndSort", _t0Filter)

    -- 5. Render grid into scroll child
    local _t0GridSetup = ProfBegin("GridSetup")
    for _, btn in pairs(itemSlots) do
        btn:GetParent():Hide()
        if btn.ProfessionQualityOverlay then btn.ProfessionQualityOverlay:SetAlpha(0) end
        if btn.IconOverlay then btn.IconOverlay:SetAlpha(0); btn.IconOverlay:Hide() end
        if btn.IconOverlay2 then btn.IconOverlay2:SetAlpha(0); btn.IconOverlay2:Hide() end
    end
    if EUI_Bags._emptyPads then
        for _, pad in pairs(EUI_Bags._emptyPads) do pad:Hide() end
    end
    local catTitleSize = GetCatTitleSize()
    for _, hdr in pairs(_catHeaders) do
        hdr:Hide(); hdr._hint:SetText("")
        if hdr._hideBtn then hdr._hideBtn:Hide() end
        hdr._line:ClearAllPoints()
        hdr._line:SetPoint("LEFT", hdr._hint, "RIGHT", 6, 0)
        hdr._line:SetPoint("RIGHT", hdr, "RIGHT", -SPACING, 0)
        SetBagFont(hdr._label, catTitleSize)
        SetBagFont(hdr._hint, catTitleSize - 1)
    end
    if EUI_Bags._pinOverlayBtn then EUI_Bags._pinOverlayBtn:Hide() end
    if EUI_Bags._oneBagWarning then EUI_Bags._oneBagWarning:Hide() end

    local columns = GetColumns()
    local sidebarW = GetSidebarWidth()
    local gridPadX = 10
    local gridW = columns * (SLOT_SIZE + SPACING)
    local scrollbarPad = SCROLLBAR_HIT_W + 2

    -- Update scroll frame left edge to track sidebar width
    local sf = EUI_Bags._scrollFrame
    local child = EUI_Bags._scrollChild
    if sf then
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", sidebarW, -(HEADER_H + 1))
        sf:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    end
    if child then
        child:SetWidth(gridW + gridPadX * 2 + scrollbarPad)
    end

    -- Items position relative to scroll child (startX = padding only, no sidebar offset)
    local startX = gridPadX + 5
    local curY = -6
    local slotIdx = 0
    local emptyIdx = 0  -- index into emptySlots pool

    -- Lightweight empty pad pool (no ItemButton template, just bg + border)
    if not EUI_Bags._emptyPads then EUI_Bags._emptyPads = {} end
    local _emptyPads = EUI_Bags._emptyPads
    local _emptyPadIdx = 0

    local function GetOrCreateEmptyPad(idx)
        if _emptyPads[idx] then return _emptyPads[idx] end
        local f = CreateFrame("Frame", nil, EUI_Bags)
        f:SetSize(SLOT_SIZE, SLOT_SIZE)
        f:EnableMouse(false)
        f._bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f._bg:SetAllPoints()
        f._bg:SetTexture("Interface\\AddOns\\EllesmereUIBags\\Media\\icon-bg.png")
        f._bg:SetAlpha(0.35)
        CreateInsetBorder(f)
        SetInsetBorderColor(f, 0, 0, 0, 0.3)
        _emptyPads[idx] = f
        return f
    end

    local function RenderEmptyPad(itemCount, padCount)
        for p = 1, padCount do
            _emptyPadIdx = _emptyPadIdx + 1
            local pad = GetOrCreateEmptyPad(_emptyPadIdx)
            pad:SetParent(child)
            pad:ClearAllPoints()
            local totalIdx = itemCount + p
            local col = (totalIdx - 1) % columns
            local row = math.floor((totalIdx - 1) / columns)
            pad:SetPoint("TOPLEFT", startX + (col * (SLOT_SIZE + SPACING)), curY - (row * (SLOT_SIZE + SPACING)))
            pad:Show()
        end
    end

    ProfEnd("GridSetup", _t0GridSetup)

    if selectedCategoryIndex == -1 then
        -- "OneBag" view: Pinned Items (display-only) + Main Bags + Reagent Bag
        -- Reuse already-collected tempItems + emptySlots instead of re-querying bags
        local headerIdx = 0

        -- OneBag warning label (created once, reused)
        if not EUI_Bags._oneBagWarning then
            local warn = child:CreateFontString(nil, "OVERLAY")
            SetBagFont(warn, 9)
            warn:SetTextColor(0.5, 0.5, 0.5, 0.9)
            warn:SetJustifyH("LEFT")
            EUI_Bags._oneBagWarning = warn
        end
        local warn = EUI_Bags._oneBagWarning
        if not (EllesmereUIDB and EllesmereUIDB.bagHideOneBagWarning) then
            warn:SetParent(child)
            warn:ClearAllPoints()
            curY = curY - 5
            warn:SetPoint("TOP", child, "TOP", 0, curY)
            warn:SetJustifyH("CENTER")
            warn:SetText("Changes made in OneBag will affect the positions of items in default Blizzard bags")
            warn:Show()
            curY = curY - 14 - 5
        end

        -- Pinned Items quickview (display-only duplicates)
        local showPinnedOneBag = (not EllesmereUIDB or EllesmereUIDB.bagPinnedInOneBag ~= false) and showPinned
        if showPinnedOneBag then
            local pinItems = {}
            if pinnedSet then
                for _, d in ipairs(tempItems) do
                    if d.info and d.info.itemID and pinnedSet[d.info.itemID] then
                        pinItems[#pinItems + 1] = d
                    end
                end
            end
            if #pinItems > 0 then pinItems = MergeDuplicates(pinItems) end
            headerIdx = headerIdx + 1
            local pinHdr = GetOrCreateCatHeader(headerIdx)
            pinHdr:SetParent(child)
            pinHdr:ClearAllPoints()
            pinHdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            pinHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
            local showTips = not EllesmereUIDB or EllesmereUIDB.bagShowPinRecentTips ~= false
            pinHdr._label:SetText("Pinned Items")
            pinHdr._hint:SetText(showTips and "(Middle Click to Add or Remove)" or "")
            if not pinHdr._hideBtn then
                local hb = CreateFrame("Button", nil, pinHdr)
                hb:SetSize(30, 16)
                hb._fs = hb:CreateFontString(nil, "OVERLAY")
                SetBagFont(hb._fs, 9)
                hb._fs:SetAllPoints()
                hb._fs:SetText("Hide")
                hb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                hb:SetScript("OnEnter", function(self)
                    self._fs:SetTextColor(1, 1, 1, 0.9)
                    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Hides Pinned Items. Re-show in settings.") end
                end)
                hb:SetScript("OnLeave", function(self)
                    self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                end)
                pinHdr._hideBtn = hb
            end
            pinHdr._hideBtn:ClearAllPoints()
            pinHdr._hideBtn:SetPoint("RIGHT", pinHdr, "RIGHT", 0, 0)
            pinHdr._hideBtn:SetScript("OnClick", function()
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.bagPinnedInOneBag = false
                EUI_Bags:RefreshInventory()
            end)
            pinHdr._hideBtn:Show()
            pinHdr._line:ClearAllPoints()
            pinHdr._line:SetPoint("LEFT", pinHdr._hint, "RIGHT", 6, 0)
            pinHdr._line:SetPoint("RIGHT", pinHdr._hideBtn, "LEFT", -6, 0)
            pinHdr:Show()
            curY = curY - 22

            for j, data in ipairs(pinItems) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                btn:GetParent():SetParent(child)
                local col = (j - 1) % columns
                local row = math.floor((j - 1) / columns)
                RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
            end
            -- Pin "+" button
            local pinItemCount = #pinItems
            do
                local pinIdx = pinItemCount + 1
                slotIdx = slotIdx + 1
                local pinSlot = GetOrCreateSlot(slotIdx)
                pinSlot:GetParent():SetParent(child)
                local col = (pinIdx - 1) % columns
                local row = math.floor((pinIdx - 1) / columns)
                RenderButton(pinSlot, { bag = 0, slot = 0 }, slotIdx, col, row, startX, curY, columns)
                local ov = GetOrCreatePinOverlay()
                ov:SetParent(child)
                ov:ClearAllPoints()
                ov:SetAllPoints(pinSlot)
                ov:Show()
                pinItemCount = pinItemCount + 1
            end
            -- Pad remaining slots in last row
            local pinRemainder = pinItemCount % columns
            local pinPadCount = pinRemainder == 0 and 0 or (columns - pinRemainder)
            if pinItemCount == 0 then pinPadCount = columns end
            if pinPadCount > 0 then
                RenderEmptyPad(pinItemCount, pinPadCount)
            end
            local pinTotal = pinItemCount + pinPadCount
            local pinRows = math.ceil(pinTotal / columns)
            curY = curY - (pinRows * (SLOT_SIZE + SPACING)) - 6
        end

        -- Recent Items quickview (display-only duplicates)
        local showRecentOneBag = EllesmereUIDB and EllesmereUIDB.bagRecentInOneBag == true
        local showRecent = not EllesmereUIDB or EllesmereUIDB.bagShowRecentItems ~= false
        if showRecentOneBag and showRecent then
            local recentItems = {}
            if EUI_Bags._recentItems then
                for _, d in ipairs(tempItems) do
                    if d.info and d.info.itemID and EUI_Bags._recentItems[d.info.itemID] then
                        recentItems[#recentItems + 1] = d
                    end
                end
            end
            if #recentItems > 0 then recentItems = MergeDuplicates(recentItems) end
            headerIdx = headerIdx + 1
            local recHdr = GetOrCreateCatHeader(headerIdx)
            recHdr:SetParent(child)
            recHdr:ClearAllPoints()
            recHdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            recHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
            local showTips = not EllesmereUIDB or EllesmereUIDB.bagShowPinRecentTips ~= false
            recHdr._label:SetText("Recent Items")
            recHdr._hint:SetText(showTips and "(Extra quickview display, your items are also in their category)" or "")
            if not recHdr._hideBtn then
                local hb = CreateFrame("Button", nil, recHdr)
                hb:SetSize(30, 16)
                hb._fs = hb:CreateFontString(nil, "OVERLAY")
                SetBagFont(hb._fs, 9)
                hb._fs:SetAllPoints()
                hb._fs:SetText("Hide")
                hb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                hb:SetScript("OnEnter", function(self)
                    self._fs:SetTextColor(1, 1, 1, 0.9)
                    if EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, "Hides Recent Items. Re-show in settings.") end
                end)
                hb:SetScript("OnLeave", function(self)
                    self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                end)
                recHdr._hideBtn = hb
            end
            recHdr._hideBtn:ClearAllPoints()
            recHdr._hideBtn:SetPoint("RIGHT", recHdr, "RIGHT", 0, 0)
            recHdr._hideBtn:SetScript("OnClick", function()
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.bagRecentInOneBag = false
                EUI_Bags:RefreshInventory()
            end)
            recHdr._hideBtn:Show()
            recHdr._line:ClearAllPoints()
            recHdr._line:SetPoint("LEFT", recHdr._hint, "RIGHT", 6, 0)
            recHdr._line:SetPoint("RIGHT", recHdr._hideBtn, "LEFT", -6, 0)
            recHdr:Show()
            curY = curY - 22

            for j, data in ipairs(recentItems) do
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                btn:GetParent():SetParent(child)
                local col = (j - 1) % columns
                local row = math.floor((j - 1) / columns)
                RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
            end
            local recItemCount = #recentItems
            local recRemainder = recItemCount % columns
            local recPadCount = recRemainder == 0 and 0 or (columns - recRemainder)
            if recItemCount == 0 then recPadCount = columns end
            if recPadCount > 0 then
                RenderEmptyPad(recItemCount, recPadCount)
            end
            local recTotal = recItemCount + recPadCount
            local recRows = math.ceil(recTotal / columns)
            curY = curY - (recRows * (SLOT_SIZE + SPACING)) - 6
        end

        -- Main Bags (0-4): all items + empties from bags 0-4 in bag:slot order
        local mainSlots = {}
        local mainFilled = 0
        for _, d in ipairs(tempItems) do
            if d.bag ~= 5 then mainSlots[#mainSlots + 1] = d; mainFilled = mainFilled + 1 end
        end
        for _, d in ipairs(emptySlots) do
            if d.bag ~= 5 then mainSlots[#mainSlots + 1] = d end
        end
        table.sort(mainSlots, function(a, b)
            if a.bag ~= b.bag then return a.bag < b.bag end
            return a.slot < b.slot
        end)

        headerIdx = headerIdx + 1
        local mainHdr = GetOrCreateCatHeader(headerIdx)
        mainHdr:SetParent(child)
        mainHdr:ClearAllPoints()
        mainHdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
        mainHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
        mainHdr._label:SetText("Main Bags (" .. mainFilled .. " / " .. #mainSlots .. ")")
        mainHdr:Show()
        curY = curY - 22

        for i, data in ipairs(mainSlots) do
            local _t0RB = ProfBegin("RenderButton")
            slotIdx = slotIdx + 1
            local btn = GetOrCreateSlot(slotIdx)
            btn:GetParent():SetParent(child)
            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            RenderButton(btn, data, slotIdx, col, row, startX, curY, columns, true)
            ProfEnd("RenderButton", _t0RB)
        end
        local mainRows = math.ceil(#mainSlots / columns)
        curY = curY - (mainRows * (SLOT_SIZE + SPACING)) - 6

        -- Reagent Bag (5): items + empties from bag 5
        local reagentSlotList = {}
        for _, d in ipairs(tempItems) do
            if d.bag == 5 then reagentSlotList[#reagentSlotList + 1] = d end
        end
        for _, d in ipairs(emptySlots) do
            if d.bag == 5 then reagentSlotList[#reagentSlotList + 1] = d end
        end
        table.sort(reagentSlotList, function(a, b) return a.slot < b.slot end)

        if #reagentSlotList > 0 then
            headerIdx = headerIdx + 1
            local reagHdr = GetOrCreateCatHeader(headerIdx)
            reagHdr:SetParent(child)
            reagHdr:ClearAllPoints()
            reagHdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            reagHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
            local reagFilled = 0
            for _, d in ipairs(reagentSlotList) do if d.info then reagFilled = reagFilled + 1 end end
            reagHdr._label:SetText("Reagent Bag (" .. reagFilled .. " / " .. #reagentSlotList .. ")")
            reagHdr:Show()
            curY = curY - 22

            for i, data in ipairs(reagentSlotList) do
                local _t0RB = ProfBegin("RenderButton")
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                btn:GetParent():SetParent(child)
                local col = (i - 1) % columns
                local row = math.floor((i - 1) / columns)
                RenderButton(btn, data, slotIdx, col, row, startX, curY, columns, true)
                ProfEnd("RenderButton", _t0RB)
            end
            local reagRows = math.ceil(#reagentSlotList / columns)
            curY = curY - (reagRows * (SLOT_SIZE + SPACING))
        end

    elseif selectedCategoryIndex == 0 and not selectedGroupName then
        -- "All Items" view: group by category with headers
        local cats = EUI_CategoryManager:GetCategories()
        local itemsByCat = {}
        for i = 1, #cats do itemsByCat[i] = {} end
        for _, data in ipairs(displayItems) do
            local ci = data.categoryIndex
            if ci and itemsByCat[ci] then
                itemsByCat[ci][#itemsByCat[ci] + 1] = data
            end
        end
        for i = 1, #cats do
            if #itemsByCat[i] > 0 and not cats[i].groupName and not cats[i].isRecent then
                ApplySavedOrder(i, itemsByCat[i])
            end
        end
        -- Merge duplicates after ordering so first-in-visual-order wins
        for i = 1, #cats do
            if #itemsByCat[i] > 1 then itemsByCat[i] = MergeDuplicates(itemsByCat[i]) end
        end

        -- Build render sections: ungrouped = individual, grouped = merged under group name
        local renderedGroups = {}
        local headerIdx = 0

        local function RenderSection(sectionName, sectionItems, isUserCreated, showPinAdd, alwaysShow)
            local itemCount = #sectionItems
            if itemCount == 0 and not isUserCreated and not showPinAdd and not alwaysShow then return end

            headerIdx = headerIdx + 1
            local hdr = GetOrCreateCatHeader(headerIdx)
            hdr:SetParent(child)
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
            hdr:SetWidth(gridW)
            local showTips = not EllesmereUIDB or EllesmereUIDB.bagShowPinRecentTips ~= false
            if showPinAdd and showTips then
                hdr._label:SetText(sectionName)
                hdr._hint:SetText("(Middle Click to Add or Remove)")
            elseif alwaysShow and showTips then
                hdr._label:SetText(sectionName)
                hdr._hint:SetText("(Extra quickview display, your items are also in their category)")
            else
                hdr._label:SetText(sectionName .. " (" .. itemCount .. ")")
                hdr._hint:SetText("")
            end
            -- Hide button for Pinned / Recent sections
            if showPinAdd or alwaysShow then
                if not hdr._hideBtn then
                    local hb = CreateFrame("Button", nil, hdr)
                    hb:SetSize(30, 16)
                    hb._fs = hb:CreateFontString(nil, "OVERLAY")
                    SetBagFont(hb._fs, 9)
                    hb._fs:SetAllPoints()
                    hb._fs:SetText("Hide")
                    hb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    hb:SetScript("OnEnter", function(self)
                        self._fs:SetTextColor(1, 1, 1, 0.9)
                        if EUI.ShowWidgetTooltip then
                            EUI.ShowWidgetTooltip(self, self._tooltip)
                        end
                    end)
                    hb:SetScript("OnLeave", function(self)
                        self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                        if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
                    end)
                    hb:SetScript("OnClick", function(self)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB[self._dbKey] = false
                        EUI_Bags:RefreshInventory()
                    end)
                    hdr._hideBtn = hb
                end
                hdr._hideBtn._dbKey = showPinAdd and "bagShowPinnedItems" or "bagShowRecentItems"
                hdr._hideBtn._tooltip = showPinAdd and "Hides Pinned Items. Re-show in settings." or "Hides Recent Items. Re-show in settings."
                hdr._hideBtn:ClearAllPoints()
                hdr._hideBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
                hdr._hideBtn:Show()
                hdr._line:ClearAllPoints()
                hdr._line:SetPoint("LEFT", hdr._hint, "RIGHT", 6, 0)
                hdr._line:SetPoint("RIGHT", hdr._hideBtn, "LEFT", -6, 0)
            end
            hdr:Show()
            curY = curY - 22

            for j, data in ipairs(sectionItems) do
                local _t0RB = ProfBegin("RenderButton")
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                btn:GetParent():SetParent(child)
                local col = (j - 1) % columns
                local row = math.floor((j - 1) / columns)
                RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                ProfEnd("RenderButton", _t0RB)
            end

            -- Pin "+" button: a regular empty slot with a "+" overlay on top
            if showPinAdd then
                local pinIdx = itemCount + 1
                slotIdx = slotIdx + 1
                local pinSlot = GetOrCreateSlot(slotIdx)
                pinSlot:GetParent():SetParent(child)
                local col = (pinIdx - 1) % columns
                local row = math.floor((pinIdx - 1) / columns)
                RenderButton(pinSlot, { bag = 0, slot = 0 }, slotIdx, col, row, startX, curY, columns)
                local ov = GetOrCreatePinOverlay()
                ov:SetParent(child)
                ov:ClearAllPoints()
                ov:SetAllPoints(pinSlot)
                ov:Show()
                itemCount = itemCount + 1
            end

            local remainder = itemCount % columns
            local padCount
            if itemCount == 0 then
                padCount = columns
            elseif remainder == 0 then
                padCount = 0
            else
                padCount = columns - remainder
            end
            padCount = math.min(padCount, #emptySlots - emptyIdx)
            if padCount > 0 then
                RenderEmptyPad(itemCount, padCount)
            end

            local totalInSection = itemCount + math.max(padCount, 0)
            local sectionRows = math.ceil(totalInSection / columns)
            curY = curY - (sectionRows * (SLOT_SIZE + SPACING)) - 6
        end

        local hiddenSet = EllesmereUIDB and EllesmereUIDB.bagHiddenInAllItems or {}
        for ci, cat in ipairs(cats) do
            if cat.isPinned then
                -- Pinned Items: display-only duplicate (items also appear in their normal category)
                if pinnedSet and showPinned then
                    local pinItems = {}
                    for _, data in ipairs(displayItems) do
                        if data.info and data.info.itemID and pinnedSet[data.info.itemID] then
                            pinItems[#pinItems + 1] = data
                        end
                    end
                    if #pinItems > 0 then pinItems = MergeDuplicates(pinItems) end
                    RenderSection(cat.name, pinItems, false, true)
                end
            elseif cat.isRecent then
                -- Recent Items: display-only duplicate (items also appear in their normal category)
                if EUI_Bags._recentItems
                   and (not EllesmereUIDB or EllesmereUIDB.bagShowRecentItems ~= false) then
                    local recentItems = {}
                    for _, data in ipairs(displayItems) do
                        if data.info and data.info.itemID and EUI_Bags._recentItems[data.info.itemID] then
                            recentItems[#recentItems + 1] = data
                        end
                    end
                    if #recentItems > 0 then recentItems = MergeDuplicates(recentItems) end
                    RenderSection("Recent Items", recentItems, false, false, true)
                end
            elseif cat.groupName then
                if not renderedGroups[cat.groupName] then
                    renderedGroups[cat.groupName] = true
                    if not hiddenSet[cat.groupName] then
                        local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                        local merged = {}
                        for _, mi in ipairs(members) do
                            if itemsByCat[mi] then
                                for _, data in ipairs(itemsByCat[mi]) do
                                    merged[#merged + 1] = data
                                end
                            end
                        end
                        if #merged > 0 then
                            ApplySavedOrder(cat.groupName, merged)
                            merged = MergeDuplicates(merged)
                        end
                        RenderSection(cat.groupName, merged, false)
                    end
                end
            else
                if not hiddenSet[cat._defaultName] then
                    local catItems = itemsByCat[ci] or {}
                    local isUserCreated = not cat.isCatchAll and (not cat.types or #cat.types == 0)
                    RenderSection(cat.name, catItems, isUserCreated, cat.isPinned, cat.isRecent)
                end
            end
        end
    else
        if selectedGroupName then
            -- Group view: items split by member category with headers
            local cats = EUI_CategoryManager:GetCategories()
            local members = EUI_CategoryManager:GetGroupMembers(selectedGroupName)
            local headerIdx = 0

            -- Bucket displayItems by member category
            local itemsByMember = {}
            for _, mi in ipairs(members) do itemsByMember[mi] = {} end
            for _, data in ipairs(displayItems) do
                local ci = data.categoryIndex
                if ci and itemsByMember[ci] then
                    itemsByMember[ci][#itemsByMember[ci] + 1] = data
                end
            end

            local hideEmpty = not EllesmereUIDB or EllesmereUIDB.bagHideEmptyCategories ~= false
            for _, mi in ipairs(members) do
                local memberCat = cats[mi]
                local memberItems = itemsByMember[mi] or {}
                if not (hideEmpty and #memberItems == 0) then

                if #memberItems > 0 then
                    PreCacheSortFields(memberItems)
                    table.sort(memberItems, VisualSortCompare)
                    memberItems = MergeDuplicates(memberItems)
                end

                headerIdx = headerIdx + 1
                local hdr = GetOrCreateCatHeader(headerIdx)
                hdr:SetParent(child)
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
                hdr:SetWidth(gridW)
                hdr._label:SetText((memberCat and memberCat.name or "?") .. " (" .. #memberItems .. ")")
                hdr:Show()
                curY = curY - 22

                for j, data in ipairs(memberItems) do
                    local _t0RB = ProfBegin("RenderButton")
                    slotIdx = slotIdx + 1
                    local btn = GetOrCreateSlot(slotIdx)
                    btn:GetParent():SetParent(child)
                    local col = (j - 1) % columns
                    local row = math.floor((j - 1) / columns)
                    RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                    ProfEnd("RenderButton", _t0RB)
                end

                local remainder = #memberItems % columns
                local padCount
                if #memberItems == 0 then padCount = columns
                elseif remainder == 0 then padCount = 0
                else padCount = columns - remainder end
                padCount = math.min(padCount, #emptySlots - emptyIdx)
                if padCount > 0 then
                    RenderEmptyPad(#memberItems, padCount)
                end

                local totalInSection = #memberItems + math.max(padCount, 0)
                local sectionRows = math.ceil(totalInSection / columns)
                curY = curY - (sectionRows * (SLOT_SIZE + SPACING)) - 6

                end -- hideEmpty guard
            end
        else
            -- Single category view: header + flat grid with empty padding
            local cats = EUI_CategoryManager:GetCategories()
            local selCat = cats[selectedCategoryIndex]
            if #displayItems > 0 then
                if not (selCat and selCat.isRecent) then
                    PreCacheSortFields(displayItems)
                    table.sort(displayItems, VisualSortCompare)
                end
                displayItems = MergeDuplicates(displayItems)
            end
            local headerName = selCat and selCat.name
            if headerName then
                local headerIdx = 1
                local hdr = GetOrCreateCatHeader(headerIdx)
                hdr:SetParent(child)
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
                hdr:SetWidth(gridW)
                local showTips = not EllesmereUIDB or EllesmereUIDB.bagShowPinRecentTips ~= false
                if selCat and selCat.isPinned and showTips then
                    hdr._label:SetText(headerName)
                    hdr._hint:SetText("(Middle Click to Add or Remove)")
                elseif selCat and selCat.isRecent and showTips then
                    hdr._label:SetText(headerName)
                    hdr._hint:SetText("(Extra quickview display, your items are also in their category)")
                else
                    hdr._label:SetText(headerName .. " (" .. #displayItems .. ")")
                    hdr._hint:SetText("")
                end
                hdr:Show()
                curY = curY - 22
            end

            local itemCount = #displayItems
            for i, data in ipairs(displayItems) do
                local _t0RB = ProfBegin("RenderButton")
                slotIdx = slotIdx + 1
                local btn = GetOrCreateSlot(slotIdx)
                btn:GetParent():SetParent(child)
                local col = (i - 1) % columns
                local row = math.floor((i - 1) / columns)
                RenderButton(btn, data, slotIdx, col, row, startX, curY, columns)
                ProfEnd("RenderButton", _t0RB)
            end


            local remainder = itemCount % columns
            local padCount
            if itemCount == 0 then
                padCount = columns
            elseif remainder == 0 then
                padCount = 0
            else
                padCount = columns - remainder
            end
            padCount = math.min(padCount, #emptySlots - emptyIdx)
            if padCount > 0 then
                RenderEmptyPad(itemCount, padCount)
            end

            local totalItems = itemCount + math.max(padCount, 0)
            local gridRows = math.ceil(totalItems / columns)
            curY = curY - (gridRows * (SLOT_SIZE + SPACING))
        end
    end

    -- Set scroll child height to content height
    local contentH = math.abs(curY) + 10
    if child then child:SetHeight(contentH) end

    -- Update scroll frame position + thumb (deferred one frame so layout updates scrollRange)
    if sf then
        sf:SetVerticalScroll(math.min(sf:GetVerticalScroll(), sf:GetVerticalScrollRange()))
    end
    C_Timer.After(0, function()
        if EUI_Bags._updateThumb then EUI_Bags._updateThumb() end
    end)

    -- Update scroll track left position to match sidebar
    if EUI_Bags._scrollTrack then
        EUI_Bags._scrollTrack:ClearAllPoints()
        EUI_Bags._scrollTrack:SetPoint("TOPRIGHT", EUI_Bags, "TOPRIGHT", -1, -(HEADER_H + 1))
        EUI_Bags._scrollTrack:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)
    end

    -- 6. Size frame (fixed height, dynamic width)
    local FIXED_H = 650
    local totalW = sidebarW + gridW + gridPadX * 2 + scrollbarPad + 2

    EUI_Bags:SetWidth(totalW)
    EUI_Bags:SetHeight(FIXED_H)

    -- Update header item count
    if EUI_Bags.Header and EUI_Bags.Header.itemCount then
        if selectedCategoryIndex == 0 or selectedCategoryIndex == -1 then
            local totalSlots = totalCount + #emptySlots
            EUI_Bags.Header.itemCount:SetText(totalCount .. " / " .. totalSlots .. " Items")
        else
            EUI_Bags.Header.itemCount:SetText(totalCount .. " Items")
        end
    end

    -- Show dice button only in OneBag mode (unless hidden by setting)
    if EUI_Bags._diceBtn then
        local showDice = selectedCategoryIndex == -1
            and not (EllesmereUIDB and EllesmereUIDB.bagHideRandomize)
        if showDice then EUI_Bags._diceBtn:Show()
        else EUI_Bags._diceBtn:Hide() end
    end

    UpdateBagMoneyDisplay()
    UpdateCurrencyDisplays()
end

-------------------------------------------------------------------------------
--  Reagent Bag Refresh (preserved)
-------------------------------------------------------------------------------
function EUI_BagsReagent:RefreshInventory()
    if not EUI_BagsReagent:IsVisible() then return end
    local tempItems = {}
    local numSlots = C_Container.GetContainerNumSlots(5)
    if numSlots > 0 then
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(5, slot)
            tempItems[#tempItems + 1] = { bag = 5, slot = slot, info = info }
        end
    end

    for _, btn in pairs(reagentSlots) do btn:GetParent():Hide() end

    local startX, startY = 15, -45
    local REAGENT_COLUMNS = 4
    for i, data in ipairs(tempItems) do
        local btn = GetOrCreateReagentSlot(i)
        local parent = btn:GetParent()
        parent:ClearAllPoints()
        parent:Show()
        btn:Show()
        btn:SetID(data.slot)
        parent:SetID(data.bag)

        if not data.info then
            btn:SetItemButtonTexture(nil)
            btn:SetItemButtonCount(0)
            SetItemButtonDesaturated(btn, false)
            if btn.icon then btn.icon:Hide() end
            if btn.ItemLevelText then btn.ItemLevelText:SetText("") end
            SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)
        else
            if btn.icon then btn.icon:Show() end
            btn:SetItemButtonTexture(data.info.iconFileID)
            btn:SetItemButtonCount(data.info.stackCount)
            SetItemButtonDesaturated(btn, data.info.isLocked)
            btn:SetAlpha(data.info.isFiltered and 0.2 or 1)

            if btn.ItemLevelText and data.info.itemID then
                local showItemlevel = not EllesmereUIDB or EllesmereUIDB.showItemlevelInBags ~= false
                if showItemlevel then
                    local itemLink = C_Container.GetContainerItemLink(data.bag, data.slot)
                    if itemLink then
                        local _, _, quality, level = GetItemInfo(itemLink)
                        if IsGearItem(itemLink) then
                            local fs = EllesmereUIDB and EllesmereUIDB.itemlevelFontSize or 12
                            btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, fs, "OUTLINE")
                            btn.ItemLevelText:SetText(level or "")
                            local r, g, b
                            if EllesmereUIDB and EllesmereUIDB.itemlevelUseCustomColor and EllesmereUIDB.itemlevelCustomColor then
                                r, g, b = EllesmereUIDB.itemlevelCustomColor.r, EllesmereUIDB.itemlevelCustomColor.g, EllesmereUIDB.itemlevelCustomColor.b
                            else
                                r, g, b = GetItemQualityColor(quality or 1)
                            end
                            btn.ItemLevelText:SetTextColor(r, g, b, 1)
                        else btn.ItemLevelText:SetText("") end
                    else btn.ItemLevelText:SetText("") end
                else btn.ItemLevelText:SetText("") end
            end

            local quality = data.info.quality or 1
            local c = ITEM_QUALITY_COLORS[quality]
            if c then SetInsetBorderColor(btn, c.r, c.g, c.b, 1)
            else SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1) end
        end

        local col = (i - 1) % REAGENT_COLUMNS
        local row = math.floor((i - 1) / REAGENT_COLUMNS)
        parent:SetPoint("TOPLEFT", startX + (col * (SLOT_SIZE + SPACING)), startY - (row * (SLOT_SIZE + SPACING)))
    end

    EUI_BagsReagent:SetWidth((REAGENT_COLUMNS * (SLOT_SIZE + SPACING)) + 30)
    EUI_BagsReagent:SetHeight(math.abs(startY) + (math.ceil(#tempItems / REAGENT_COLUMNS) * (SLOT_SIZE + SPACING)) + 40)
end

function EUI_BagsWindow:RefreshBags()
    if not EUI_BagsWindow:IsVisible() then return end
    for _, btn in pairs(bagSlots) do btn:GetParent():Hide() end
    local startX, startY = 10, -10
    local BAG_COLUMNS = 6
    for i = 0, 5 do
        local displayIdx = i + 1
        local btn = GetOrCreateBagSlot(displayIdx)
        local parent = btn:GetParent()
        btn:SetID(i)
        parent:Show()
        local invID = C_Container.ContainerIDToInventoryID(i)
        local texture = GetInventoryItemTexture("player", invID)
        local quality = GetInventoryItemQuality("player", invID) or 0
        local free = C_Container.GetContainerNumFreeSlots(i)
        local total = C_Container.GetContainerNumSlots(i)
        if i == 0 then btn.icon:SetTexture(133633)
        elseif texture then btn.icon:SetTexture(texture)
        else btn.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag") end
        if total > 0 then btn.Count:SetText(free); btn.Count:Show()
        else btn.Count:Hide() end
        local c = ITEM_QUALITY_COLORS[quality]
        local bdrR, bdrG, bdrB
        if c and quality > 0 then
            bdrR, bdrG, bdrB = c.r, c.g, c.b
        else
            bdrR, bdrG, bdrB = 0.25, 0.25, 0.25
        end
        SetInsetBorderColor(btn, bdrR, bdrG, bdrB, 1)
        btn._bdrR, btn._bdrG, btn._bdrB = bdrR, bdrG, bdrB

        -- Tooltip: bag name + free/total slots (computed live on hover)
        local bagIdx = i
        btn:SetScript("OnEnter", function(self)
            SetInsetBorderColor(self, 1, 1, 1, 1)
            if EUI.ShowWidgetTooltip then
                local bName
                if bagIdx == 0 then
                    bName = "Backpack"
                else
                    local bInvID = C_Container.ContainerIDToInventoryID(bagIdx)
                    local bLink = GetInventoryItemLink("player", bInvID)
                    bName = bLink and GetItemInfo(bLink) or ("Bag " .. bagIdx)
                end
                local bTotal = C_Container.GetContainerNumSlots(bagIdx)
                local bFree = C_Container.GetContainerNumFreeSlots(bagIdx)
                local tip = bName
                if bTotal > 0 then tip = tip .. "  (" .. (bTotal - bFree) .. "/" .. bTotal .. ")" end
                EUI.ShowWidgetTooltip(self, tip)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            SetInsetBorderColor(self, self._bdrR, self._bdrG, self._bdrB, 1)
            if EUI.HideWidgetTooltip then EUI.HideWidgetTooltip() end
        end)

        parent:ClearAllPoints()
        parent:SetPoint("TOPLEFT", EUI_BagsWindow, "TOPLEFT", startX + (i * (SLOT_SIZE + SPACING)), startY)
    end
    EUI_BagsWindow:SetSize((BAG_COLUMNS * (SLOT_SIZE + SPACING)) + 15, SLOT_SIZE + 20)
end

-------------------------------------------------------------------------------
--  StartAddon
-------------------------------------------------------------------------------
local function StartAddon()
    -- Apply default view based on setting (DB now available)
    if EllesmereUIDB and EllesmereUIDB.bagDefaultOneBag then
        selectedCategoryIndex = -1
    end

    InitializeCharacterGold()
    if not EllesmereUIDB or EllesmereUIDB.enableGoldTracking ~= false then
        CaptureTrackedGold()
    end

    -- Position: default 50px from bottom-left, saved position overrides
    if EllesmereUIDB and EllesmereUIDB.bagsPosition then
        local pos = EllesmereUIDB.bagsPosition
        EUI_Bags:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        EUI_Bags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 50)
    end

    EUI_Bags:SetClampedToScreen(true)
    EUI_Bags:SetFrameStrata("HIGH")
    EUI_Bags:SetFrameLevel(100)
    EUI_Bags:EnableMouse(true)
    EUI_Bags:SetMovable(true)

    -- Bag frame drag: shift+click, OnMouseDown/OnUpdate pattern (no RegisterForDrag)
    local _bagDragging = false
    local _bagDragStartCX, _bagDragStartCY = 0, 0
    local _bagDragStartLeft, _bagDragStartTop = 0, 0
    local _bagDragFrame = CreateFrame("Frame")
    _bagDragFrame:Hide()
    _bagDragFrame:SetScript("OnUpdate", function(self)
        if not _bagDragging then self:Hide(); return end
        if not IsMouseButtonDown("LeftButton") then
            _bagDragging = false
            self:Hide()
            local left, top = EUI_Bags:GetLeft(), EUI_Bags:GetTop()
            if left and top then
                local PP = EUI and EUI.PP
                if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
                EUI_Bags:ClearAllPoints()
                EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            return
        end
        local cx, cy = GetCursorPosition()
        local es = EUI_Bags:GetEffectiveScale()
        local newLeft = _bagDragStartLeft + (cx / es - _bagDragStartCX)
        local newTop = _bagDragStartTop + (cy / es - _bagDragStartCY)
        EUI_Bags:ClearAllPoints()
        EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)
    EUI_Bags:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not IsKeyDown("LSHIFT") then return end
        local cx, cy = GetCursorPosition()
        local es = self:GetEffectiveScale()
        _bagDragStartCX = cx / es
        _bagDragStartCY = cy / es
        _bagDragStartLeft = self:GetLeft()
        _bagDragStartTop = self:GetTop()
        if not _bagDragStartLeft or not _bagDragStartTop then return end
        _bagDragging = true
        _bagDragFrame:Show()
    end)
    EUI_Bags:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and _bagDragging then
            _bagDragging = false
            _bagDragFrame:Hide()
            local left, top = EUI_Bags:GetLeft(), EUI_Bags:GetTop()
            if left and top then
                local PP = EUI and EUI.PP
                if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
                EUI_Bags:ClearAllPoints()
                EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
    end)

    EUI_Bags.bg = EUI_Bags:CreateTexture(nil, "BACKGROUND", nil, 0)
    EUI_Bags.bg:SetAllPoints()
    EUI_Bags.bg:SetAtlas("housing-basic-panel--stone-background")
    EUI_Bags.bg:SetTexCoord(0, 1, 0, 1)

    -- Dark overlay on top of the atlas (25% black)
    EUI_Bags.bgOverlay = EUI_Bags:CreateTexture(nil, "BACKGROUND", nil, 1)
    EUI_Bags.bgOverlay:SetAllPoints()
    EUI_Bags.bgOverlay:SetColorTexture(0, 0, 0, 0.25)

    if EUI and EUI.PanelPP then
        EUI.PanelPP.CreateBorder(EUI_Bags, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end

    EUI_Bags:HookScript("OnShow", function()
        CaptureTrackedGold()
    end)

    EUI_Bags:HookScript("OnHide", function()
        if EUI_Bags._searchBox then
            EUI_Bags._searchBox:SetText("")
            EUI_Bags._searchBox:ClearFocus()
        end
    end)

    -- Click empty space with an external item on cursor: auto-place in
    -- first available bag slot (same as looting). Only fires for items
    -- not already in the player's bags (bank withdrawals, mail, etc.).
    EUI_Bags:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        local cursorType, cursorItemID, cursorLink = GetCursorInfo()
        if cursorType ~= "item" then return end
        -- Check if the cursor item is from the player's bags (bag 0-4)
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.isLocked then
                    -- Locked = this slot is the pickup source
                    return
                end
            end
        end
        -- External item: place in first empty bag slot
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                if not C_Container.GetContainerItemInfo(bag, slot) then
                    C_Container.PickupContainerItem(bag, slot)
                    return
                end
            end
        end
    end)

    CreateHeader()
    CreateFooter()
    CreateSidebar()
    CreateBagScrollFrame()
    CreateReagentBagUI()

    -- Bag overview window
    EUI_BagsWindow:SetSize(280, 80)
    EUI_BagsWindow:SetPoint("BOTTOMRIGHT", EUI_Bags._bagsBtn, "TOPRIGHT", 0, 2)
    EUI_BagsWindow:SetFrameStrata("HIGH")
    EUI_BagsWindow:EnableMouse(true)
    EUI_BagsWindow.bg = EUI_BagsWindow:CreateTexture(nil, "BACKGROUND")
    EUI_BagsWindow.bg:SetAllPoints()
    EUI_BagsWindow.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(EUI_BagsWindow, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end
    EllesmereUI.RegisterEscapeClose(EUI_BagsWindow)

    -- Reagent bag
    EUI_BagsReagent:SetSize(320, 300)
    EUI_BagsReagent:SetPoint("BOTTOMRIGHT", EUI_Bags, "BOTTOMLEFT", -10, 0)
    EUI_BagsReagent:SetFrameStrata("HIGH")
    EUI_BagsReagent:EnableMouse(true)
    EUI_BagsReagent.bg = EUI_BagsReagent:CreateTexture(nil, "BACKGROUND")
    EUI_BagsReagent.bg:SetAllPoints()
    EUI_BagsReagent.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if EUI and EUI.PanelPP then EUI.PanelPP.CreateBorder(EUI_BagsReagent, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end

    EUI_BagsReagent:RegisterEvent("BAG_UPDATE")
    EUI_BagsReagent:SetScript("OnEvent", function(self, event)
        if event == "BAG_UPDATE" then
            local detach = EllesmereUIDB and EllesmereUIDB.detachReagentBag or false
            if detach and EUI_BagsReagent:IsVisible() then EUI_BagsReagent:RefreshInventory() end
        end
    end)
    EllesmereUI.RegisterEscapeClose(EUI_BagsReagent)

    -- Hook Blizzard bag toggles
    local OriginalToggleAllBags = ToggleAllBags
    local function ToggleEUI()
        if EUI_Bags:IsVisible() then
            EUI_Bags:Hide()
            EUI_BagsReagent:Hide()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.bagsVisible = false
        else
            ApplyBagScale()
            EUI_Bags:Show()
            EUI_Bags:RefreshInventory()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            -- Seed default pinned items on first ever open
            if not EllesmereUIDB.bagPinsSeeded then
                EllesmereUIDB.bagPinsSeeded = true
                if not EllesmereUIDB.bagPinnedItems then EllesmereUIDB.bagPinnedItems = {} end
                EllesmereUIDB.bagPinnedItems[6948] = 1    -- Hearthstone
                EllesmereUIDB.bagPinnedItems[180653] = 1  -- Nomi Snacks
            end
            -- Auto-sort on first ever open
            if not EllesmereUIDB.bagInitialSortDone and EUI_Bags._doVisualSort then
                EllesmereUIDB.bagInitialSortDone = true
                EUI_Bags._doVisualSort()
            end
            EllesmereUIDB.bagsVisible = true
            local detach = EllesmereUIDB and EllesmereUIDB.detachReagentBag or false
            if detach then
                EUI_BagsReagent:Show()
                EUI_BagsReagent:RefreshInventory()
            end
        end
    end

    local _lastToggleTime = 0
    local function SmartToggleBags()
        -- Debounce: Blizzard keybinds can fire both ToggleAllBags and
        -- C_Container.ToggleAllBags in the same frame, causing a double-toggle.
        if GetTime() == _lastToggleTime then return end
        _lastToggleTime = GetTime()
        local enhancedEnabled = not EllesmereUIDB or EllesmereUIDB.enhancedBags ~= false
        if enhancedEnabled then ToggleEUI()
        else if OriginalToggleAllBags then OriginalToggleAllBags() end end
    end

    -- Override ToggleAllBags
    ToggleAllBags = SmartToggleBags
    -- Hook ToggleBackpack/ToggleBag via hooksecurefunc (avoids tainting the global)
    hooksecurefunc("ToggleBackpack", SmartToggleBags)
    hooksecurefunc("ToggleBag", function() SmartToggleBags() end)

    -- Hide Blizzard bag frames by reparenting to a hidden container.
    -- Never write .Show/.Hide onto Blizzard frames (causes taint).
    local _blizzBagHidden = CreateFrame("Frame")
    _blizzBagHidden:Hide()

    local function KillBlizzard()
        for i = 1, 13 do
            local f = _G["ContainerFrame"..i]
            if f then f:SetParent(_blizzBagHidden) end
        end
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:SetParent(_blizzBagHidden)
        end
    end
    KillBlizzard()

    hooksecurefunc("OpenAllBags", function()
        if not EUI_Bags:IsVisible() then ToggleEUI() end
        KillBlizzard()
    end)

    -- Recent Items: session-only tracking (resets on login/reload)
    local RECENT_MAX = 12
    EUI_Bags._recentItems = {}      -- itemID -> true (set of recent item IDs)
    EUI_Bags._recentOrder = {}      -- ordered list of itemIDs (oldest first)
    local _knownItemIDs = {}    -- itemID -> true (all item IDs present in bags)
    local _snapshotReady = false

    local function SnapshotKnownIDs()
        for bag = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    _knownItemIDs[info.itemID] = true
                end
            end
        end
        _snapshotReady = true
    end

    local function DetectNewItems()
        if not _snapshotReady then return end
        for bag = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    if not _knownItemIDs[info.itemID] and not EUI_Bags._recentItems[info.itemID] then
                        EUI_Bags._recentItems[info.itemID] = true
                        EUI_Bags._recentOrder[#EUI_Bags._recentOrder + 1] = info.itemID
                        while #EUI_Bags._recentOrder > RECENT_MAX do
                            local old = table.remove(EUI_Bags._recentOrder, 1)
                            EUI_Bags._recentItems[old] = nil
                        end
                    end
                end
            end
        end
        SnapshotKnownIDs()
    end

    C_Timer.After(1, function() SnapshotKnownIDs() end)

    -- Debounced full refresh (replaces FastRefresh -- one code path, no stale state)
    local refreshPending = false
    EUI_Bags.refreshEnabled = true
    local function ScheduleRefresh()
        if not EUI_Bags.refreshEnabled or refreshPending then return end
        refreshPending = true
        C_Timer.After(0.1, function()
            if EUI_Bags:IsVisible() then
                EUI_Bags:RefreshInventory()
                local detach = EllesmereUIDB and EllesmereUIDB.detachReagentBag or false
                if detach and EUI_BagsReagent:IsVisible() then EUI_BagsReagent:RefreshInventory() end
            end
            refreshPending = false
        end)
    end

    EUI_Bags:RegisterEvent("BAG_UPDATE")
    EUI_Bags:RegisterEvent("PLAYER_MONEY")
    EUI_Bags:RegisterEvent("ITEM_LOCK_CHANGED")
    EUI_Bags:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

    -- Seed currencyOrder from Blizzard's tracked currencies on first load
    if EllesmereUIDB and C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
        if not EllesmereUIDB.currencyOrder then EllesmereUIDB.currencyOrder = {} end
        local co = EllesmereUIDB.currencyOrder
        -- Only seed if our table is empty (first install or fresh profile)
        local hasAny = false
        for _ in pairs(co) do hasAny = true; break end
        if not hasAny then
            local order = 0
            for i = 1, 20 do
                local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                if not info then break end
                order = order + 1
                co[info.currencyTypesID] = order
            end
        end
    end

    -- Snapshot Blizzard's tracked currencies so we can diff on change.
    local _lastBlizzSet = {}
    local function ReadBlizzSet()
        local s = {}
        if C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
            for i = 1, 20 do
                local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                if not info then break end
                s[info.currencyTypesID] = true
            end
        end
        return s
    end
    _lastBlizzSet = ReadBlizzSet()

    -- Sync our currency list when user checks/unchecks in Blizzard's currency tab.
    -- Newly checked currencies get added. Newly unchecked currencies get removed.
    -- Currencies added through our dropdown (never in Blizzard's set) are untouched.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("TokenFrame.OnTokenWatchChanged", function()
            if not EllesmereUIDB then return end
            if not EllesmereUIDB.currencyOrder then EllesmereUIDB.currencyOrder = {} end
            local co = EllesmereUIDB.currencyOrder
            local blizzSet = ReadBlizzSet()
            -- Add newly checked currencies
            for cID in pairs(blizzSet) do
                if not co[cID] then
                    local maxOrder = 0
                    for _, ord in pairs(co) do
                        if type(ord) == "number" and ord > maxOrder then maxOrder = ord end
                    end
                    co[cID] = maxOrder + 1
                end
            end
            -- Remove currencies that were in Blizzard's set before but aren't now
            for cID in pairs(_lastBlizzSet) do
                if not blizzSet[cID] then
                    co[cID] = nil
                end
            end
            _lastBlizzSet = blizzSet
            if EUI_Bags:IsVisible() then UpdateCurrencyDisplays() end
            if EllesmereUI and EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
        end, EUI_Bags)
    end

    -- DetectNewItems: run synchronously but at most once per frame (zone changes fire many BAG_UPDATEs)
    local _lastDetectFrame = 0

    EUI_Bags:SetScript("OnEvent", function(self, event)
        if event == "BAG_UPDATE" and EUI_Bags.refreshEnabled ~= false then
            local now = GetTime()
            if now ~= _lastDetectFrame then
                _lastDetectFrame = now
                DetectNewItems()
            end
        end
        if not EUI_Bags:IsVisible() then return end
        if event == "BAG_UPDATE" then
            if EUI_Bags._pendingBagSwap and EUI_BagsWindow:IsVisible() then
                EUI_Bags._pendingBagSwap = nil
                EUI_BagsWindow:RefreshBags()
            end
            if not EUI_Bags.refreshEnabled then return end
            if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
            ScheduleRefresh()
        elseif event == "ITEM_LOCK_CHANGED" then
            if not EUI_Bags.refreshEnabled then return end
            if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
            ScheduleRefresh()
        elseif event == "PLAYER_MONEY" then
            CaptureTrackedGold()
            UpdateBagMoneyDisplay()
        elseif event == "CURRENCY_DISPLAY_UPDATE" then
            UpdateCurrencyDisplays()
        end
    end)

    EUI_Bags:HookScript("OnHide", function()
        EUI_BagsWindow:Hide()
    end)

    EllesmereUI.RegisterEscapeClose(EUI_Bags)
end

-------------------------------------------------------------------------------
--  Loader
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0.5, function()
        StartAddon()
        EUI_Bags:Hide()
        EUI_BagsReagent:Hide()

    end)
end)
