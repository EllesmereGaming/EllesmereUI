if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Refresh.lua
--
--  Category headers, the scroll frame, the resize grip and
--  RefreshInventory for the bags and the reagent bag.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local GetItemInfo = C_Item.GetItemInfo
local EUI = EllesmereUI
local GetUpgradeTrack = EUI.GetUpgradeTrack
local AbbrevDungeon = EUI.AbbrevDungeon

local BP, GetColumns = I.BP, I.GetColumns
local GetItemLevelAtLocation, IsGearItem = I.GetItemLevelAtLocation, I.IsGearItem
local IsItemPinned, SetBagFont, SLOT_SIZE = I.IsItemPinned, I.SetBagFont, I.SLOT_SIZE
local SPACING, _pendingResortCats = I.SPACING, I._pendingResortCats
local _pendingResortGroups, _slotCategories = I._pendingResortGroups, I._slotCategories
local AcquireSlotTable, bagSlots = I.AcquireSlotTable, I.bagSlots
local DetectAndApplySwaps, FOOTER_H, HEADER_H = I.DetectAndApplySwaps, I.FOOTER_H, I.HEADER_H
local PreCacheSortFields, reagentSlots = I.PreCacheSortFields, I.reagentSlots
local ReleaseAllSlotTables, SaveCategoryOrder = I.ReleaseAllSlotTables, I.SaveCategoryOrder
local TakeBagSnapshot, UpdatePawnArrow = I.TakeBagSnapshot, I.UpdatePawnArrow
local VisualSortCompare, UpdateBagMoneyDisplay = I.VisualSortCompare, I.UpdateBagMoneyDisplay
local UpdateCurrencyDisplays, SCROLLBAR_HIT_W = I.UpdateCurrencyDisplays, I.SCROLLBAR_HIT_W
local SetInsetBorderColor, GetOrCreateBagSlot = I.SetInsetBorderColor, I.GetOrCreateBagSlot
local GetOrCreateReagentSlot = I.GetOrCreateReagentSlot
local BuildSidebarButtons, GetSidebarWidth = I.BuildSidebarButtons, I.GetSidebarWidth
local SetGearCatSet, SetPaintedPanelOpen = I.SetGearCatSet, I.SetPaintedPanelOpen

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = I.selectedCategoryIndex
I.categoryIndexSetters[#I.categoryIndexSetters + 1] = function(v) selectedCategoryIndex = v end
local selectedGroupName
I.groupNameSetters[#I.groupNameSetters + 1] = function(v) selectedGroupName = v end
local _anyItemPanelOpen = I._anyItemPanelOpen
I.anyItemPanelOpenSetters[#I.anyItemPanelOpenSetters + 1] = function(v) _anyItemPanelOpen = v end

local _lastCatCounts = {}      -- category counts from last full refresh
local _lastTotalCount = 0      -- total item count from last full refresh

-- RefreshInventory's per-item reads. One location is reused for every slot
-- (CreateFromBagAndSlot builds a new mixin table per call). An item link names
-- one exact item, bonus IDs included, so its quality, bind type, gear flag and
-- upgrade track never change: they are kept per link, and only answers given
-- once the item's data is loaded (a quality came back), never an empty track,
-- so a later read can still fill them in. Bounded like the crafted-track memo.
local _slotLoc = ItemLocation:CreateEmpty()
local _linkFacts, _linkFactsN = {}, 0

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

-- A frame that takes mouse motion is still the mouse focus: it drops every
-- click and item drop on it, and takes hover from the frames beneath (the bag
-- window's drop target), unless it passes them on. Those switches are
-- protected (out of combat only): a frame made in combat takes no mouse until
-- a later paint out of combat turns them on. Returns whether the frame passes
-- clicks on. Shared with the Compact display's labels.
function ns.PassClicks(f)
    if f._passClicks or not f.SetPropagateMouseClicks then return true end
    if InCombatLockdown() then return false end
    f:SetPropagateMouseClicks(true)
    if f.SetPropagateMouseMotion then f:SetPropagateMouseMotion(true) end
    f._passClicks = true
    return true
end

-- The Pinned / Recent header hint, shown while the header's label is
-- hovered; nil clears it. The hover frame is built with the first hint.
do
local function HeaderHintOnEnter(self)
    local hint = self:GetParent()._hintText
    if hint then EUI.ShowWidgetTooltip(self, hint) end
end
function ns.SetHeaderHint(hdr, text)
    hdr._hintText = text
    local hit = hdr._hintHit
    if not hit then
        if not text then return end
        hit = CreateFrame("Frame", nil, hdr)
        hit:SetPoint("TOPLEFT", hdr._label, "TOPLEFT", 0, 2)
        hit:SetPoint("BOTTOMRIGHT", hdr._label, "BOTTOMRIGHT", 0, -2)
        hit:SetScript("OnEnter", HeaderHintOnEnter)
        hit:SetScript("OnLeave", EUI.HideWidgetTooltip)
        -- After the scripts: motion only, never clicks
        hit:SetMouseClickEnabled(false)
        hdr._hintHit = hit
    end
    hit:SetMouseMotionEnabled(text ~= nil and ns.PassClicks(hit))
end
end

-- "Clear" link on a Recent Items header, sitting just left of its "Hide" link
-- (or at the header's right edge when there is none, as in the list).
-- Opt-in (bagShowRecentClear, default off): callers gate on the setting, so a
-- user who never enables it never has the button built. Pooled on the header
-- like _hideBtn; hidden by the per-refresh header reset.
local function ShowRecentClearButton(hdr, hideBtn)
    if not hdr._clearBtn then
        local cb = CreateFrame("Button", nil, hdr)
        cb:SetSize(34, 16)
        cb._fs = cb:CreateFontString(nil, "OVERLAY")
        SetBagFont(cb._fs, 9)
        cb._fs:SetAllPoints()
        cb._fs:SetText(EllesmereUI.L("Clear"))
        cb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
        cb:SetScript("OnEnter", function(self)
            self._fs:SetTextColor(1, 1, 1, 0.9)
            EUI.ShowWidgetTooltip(self, "Clears the Recent Items list.")
        end)
        cb:SetScript("OnLeave", function(self)
            self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
            EUI.HideWidgetTooltip()
        end)
        cb:SetScript("OnClick", function()
            if EUI_Bags.ClearRecentItems then EUI_Bags:ClearRecentItems() end
        end)
        hdr._clearBtn = cb
    end
    hdr._clearBtn:ClearAllPoints()
    if hideBtn then
        hdr._clearBtn:SetPoint("RIGHT", hideBtn, "LEFT", -6, 0)
    else
        hdr._clearBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    end
    hdr._clearBtn:Show()
    return hdr._clearBtn
end

-- Indented subheaders under a category (expansion names) for All Items nesting
local _expSubHeaders = {}

local function GetOrCreateExpSubHeader(idx)
    if _expSubHeaders[idx] then return _expSubHeaders[idx] end
    local f = CreateFrame("Frame", nil, EUI_Bags)
    f:SetHeight(16)
    f._label = f:CreateFontString(nil, "OVERLAY")
    SetBagFont(f._label, 9)
    f._label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._label:SetTextColor(0.55, 0.55, 0.55)
    f._label:SetJustifyH("LEFT")
    _expSubHeaders[idx] = f
    return f
end

-------------------------------------------------------------------------------
--  Scroll Frame + Scrollbar for item grid
-------------------------------------------------------------------------------
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
    local track, thumb, UpdateThumb = ns.AttachGridScrollbar(EUI_Bags, sf, true, false)
    track:SetPoint("TOPRIGHT", EUI_Bags, "TOPRIGHT", -1, -(HEADER_H + 1))
    track:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "TOPRIGHT", -1, 0)

    EUI_Bags._scrollFrame = sf
    EUI_Bags._scrollChild = child
    EUI_Bags._scrollTrack = track
    EUI_Bags._scrollThumb = thumb
    EUI_Bags._updateThumb = UpdateThumb
end

-------------------------------------------------------------------------------
--  RefreshInventory
-------------------------------------------------------------------------------
-- Shared tail of RefreshInventory (grid and list view): scroll child height,
-- scrollbar, frame size, item count. curY = bottom of the rendered content.
-------------------------------------------------------------------------------
--  Resize grip and lock: the bag and bank windows' bottom-right corner, as on
--  a damage meter window. Unlocked: the open lock with the resize grip right
--  of it; locked: the closed lock alone in the corner, and the window neither
--  resizes nor moves. Clicking the lock toggles it. Dragging the grip steps
--  the width unit (a grid column, or 1px for the list views) and sets the
--  height. While dragging, the edges follow the cursor; the content re-lays
--  out every relayoutStep px (frame._resizing set meanwhile) and the width
--  settles on release. OnUpdate only while a drag is held. Double-click
--  resets the window to its default size. The footer's right-edge text keeps
--  clear of whichever icons show (cfg.inset(px)).
--  cfg: step, relayoutStep (optional, default step), minCols, minH,
--  getCols(), getHeight(), save(cols, h), finish(), savePos(left, top),
--  reset(), inset(px), isLocked(), setLocked(v), hidden() (optional: the
--  window sizes itself, so neither icon shows)
-------------------------------------------------------------------------------
do
-- Art, alphas and the footer text clearance (the lock alone, or the grip with
-- the lock beside it), plus the handlers this block adds: one table keeps the
-- chunk's local count low.
local GR = {
    RESIZE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png",
    LOCKED = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-lock-locked.png",
    UNLOCKED = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-lock-unlocked.png",
    A = 0.4, HOVER = 0.8, LOCK_INSET = 18, GRIP_INSET = 36,
}

local function GripStop(grip)
    grip:SetScript("OnUpdate", nil)
    if grip._drag then
        grip._drag = nil
        grip:GetParent()._resizing = nil
        grip._cfg.finish()
    end
    grip:SetAlpha(grip:IsMouseOver() and GR.HOVER or GR.A)
end

local function GripOnUpdate(grip)
    if not IsMouseButtonDown("LeftButton") then GripStop(grip); return end
    local d, cfg = grip._drag, grip._cfg
    local cx, cy = GetCursorPosition()
    local es = grip:GetParent():GetEffectiveScale()
    local step = cfg.step
    local dx = math.floor(cx / es - d.x + 0.5)
    dx = math.max((cfg.minCols - d.cols) * step, math.min((d.maxCols - d.cols) * step, dx))
    local cols = d.cols + math.floor(dx / step)
    local bucket = math.floor(dx / (cfg.relayoutStep or step))
    local h = math.floor(d.h + (d.y - cy / es) + 0.5)
    h = math.max(cfg.minH, math.min(d.maxH, h))
    if dx == d.lastDX and h == d.lastH then return end
    local relayout = bucket ~= d.lastBucket
    d.lastDX, d.lastBucket, d.lastH = dx, bucket, h
    cfg.save(cols, h)
    if relayout then cfg.finish() end
    -- After the refresh, which sets the snapped size
    grip:GetParent():SetSize(d.frameW + dx, h)
end

local function GripOnMouseDown(grip, button)
    if button ~= "LeftButton" then return end
    local frame, cfg = grip:GetParent(), grip._cfg
    local left, top, right, bottom = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
    if not left then return end
    -- Pin the top-left corner so only the right and bottom edges move
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    cfg.savePos(left, top)
    local cx, cy = GetCursorPosition()
    local es = frame:GetEffectiveScale()
    local screenW = UIParent:GetRight() * UIParent:GetEffectiveScale() / es
    local cols, h = cfg.getCols(), cfg.getHeight()
    grip._drag = {
        x = cx / es, y = cy / es, cols = cols, h = h, lastBucket = 0, lastDX = 0, lastH = h,
        frameW = frame:GetWidth(),
        maxCols = math.max(cols, cols + math.floor((screenW - right) / cfg.step)),
        maxH = math.max(h, h + math.floor(bottom)),
    }
    frame._resizing = true
    -- Keep the hover look while the cursor runs ahead of the snapped edge
    grip:SetAlpha(GR.HOVER)
    grip:SetScript("OnUpdate", GripOnUpdate)
end

local function GripReset(grip)
    GripStop(grip)
    grip._cfg.reset()
end

local function GripOnEnter(grip)
    grip:SetAlpha(GR.HOVER)
    EUI.ShowWidgetTooltip(grip, EllesmereUI.L("Drag to resize. Double-click to reset."))
end

function GR.GripOnLeave(grip)
    if not grip._drag then grip:SetAlpha(GR.A) end
    EUI.HideWidgetTooltip()
end

function GR.LockTooltip(lock)
    EUI.ShowWidgetTooltip(lock, EllesmereUI.L(lock._cfg.isLocked() and "Locked" or "Unlocked"))
end

function GR.LockOnEnter(lock)
    lock:SetAlpha(GR.HOVER)
    GR.LockTooltip(lock)
end

function GR.LockOnLeave(lock)
    lock:SetAlpha(GR.A)
    EUI.HideWidgetTooltip()
end

function GR.LockOnClick(lock)
    local cfg = lock._cfg
    cfg.setLocked(not cfg.isLocked())
    ns.UpdateResizeGrip(lock:GetParent(), cfg)
    GR.LockTooltip(lock)
end

function GR.IconButton(frame, w, h, path)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(w, h)
    b:SetFrameLevel(frame:GetFrameLevel() + 50)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetDesaturated(true)
    if path then tex:SetTexture(path) end
    b._icon = tex
    b:SetAlpha(GR.A)
    return b
end

-- The lock always shows (it also holds the window in place); the grip only
-- while unlocked and the window does not size itself. Runs on every refresh,
-- so it repaints only when that state changes.
function ns.UpdateResizeGrip(frame, cfg)
    local grip, lock = frame._resizeGrip, frame._lockBtn
    local locked = cfg.isLocked()
    local noGrip = locked or (cfg.hidden and cfg.hidden()) or false
    if lock and frame._gripCfg == cfg and frame._gripLocked == locked and frame._gripNoGrip == noGrip then return end
    frame._gripCfg, frame._gripLocked, frame._gripNoGrip = cfg, locked, noGrip
    if not lock then
        lock = GR.IconButton(frame, 13, 17)
        lock:SetScript("OnEnter", GR.LockOnEnter)
        lock:SetScript("OnLeave", GR.LockOnLeave)
        lock:SetScript("OnClick", GR.LockOnClick)
        frame._lockBtn = lock
    end
    lock._cfg = cfg
    lock._icon:SetTexture(locked and GR.LOCKED or GR.UNLOCKED)
    lock:ClearAllPoints()
    local inset = GR.LOCK_INSET
    if noGrip then
        if grip then grip:Hide() end
        lock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    else
        if not grip then
            grip = GR.IconButton(frame, 18, 18, GR.RESIZE)
            grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
            grip:SetScript("OnMouseDown", GripOnMouseDown)
            grip:SetScript("OnMouseUp", GripStop)
            grip:SetScript("OnDoubleClick", GripReset)
            grip:SetScript("OnEnter", GripOnEnter)
            grip:SetScript("OnLeave", GR.GripOnLeave)
            -- Window closed mid-drag: end the drag instead of resuming on reopen
            grip:SetScript("OnHide", GripStop)
            frame._resizeGrip = grip
        end
        if not grip._drag then grip._cfg = cfg end
        grip:Show()
        lock:SetPoint("RIGHT", grip, "LEFT", -2, 0)
        inset = GR.GRIP_INSET
    end
    lock:Show()
    if frame._gripInset ~= inset then
        frame._gripInset = inset
        cfg.inset(inset)
    end
end
end -- resize grip

local _bagGripCfg = {
    step = SLOT_SIZE + SPACING, minCols = 8, minH = 300,
    getCols = function() return BP().bagColumns or 12 end,
    getHeight = function() return math.floor(EUI_Bags:GetHeight() + 0.5) end,
    save = function(cols, h)
        BP().bagColumns, BP().bagHeight = cols, h
        if EUI_Bags._updateThumb then EUI_Bags._updateThumb() end
    end,
    finish = function() EUI_Bags:RefreshInventory() end,
    savePos = function(left, top)
        BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
    end,
    reset = function()
        local p = BP()
        p.bagColumns, p.bagHeight, p.bagListWidth = nil, nil, nil
        EUI_Bags:RefreshInventory()
    end,
    -- The gold display sits in the footer's bottom-right corner
    inset = function(px)
        local money = EUI_Bags.Money
        if not money then return end
        money:ClearAllPoints()
        money:SetPoint("BOTTOMRIGHT", EUI_Bags.Footer, "BOTTOMRIGHT", -px, 7)
    end,
    isLocked = function() return BP().bagWindowLocked == true end,
    setLocked = function(v) BP().bagWindowLocked = v and true or false end,
    -- Auto-Size owns the window size
    hidden = function() return EUI_Bags.AutoSizeOn() end,
}

-- List display: free width (rows have no cell grid), saved in pixels
local _bagListGripCfg = setmetatable({
    step = 1, relayoutStep = SLOT_SIZE + SPACING, minCols = 300,
    getCols = function() return BP().bagListWidth or GetColumns() * (SLOT_SIZE + SPACING) end,
    save = function(w, h)
        BP().bagListWidth, BP().bagHeight = w, h
        if EUI_Bags._updateThumb then EUI_Bags._updateThumb() end
    end,
}, { __index = _bagGripCfg })

local function FinishRefresh(curY, gridContentW, sidebarW, totalCount, numEmpty, spItems, spEmpty)
    -- In combat the sort button's lock depends on the view just painted.
    if InCombatLockdown() and EUI_Bags._applySortEnabled then EUI_Bags._applySortEnabled() end
    local sf, child = EUI_Bags._scrollFrame, EUI_Bags._scrollChild
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

    -- 6. Size frame. Default: fixed height, dynamic width. Auto-size: height grows to fit content
    -- (no vertical scroll), width follows column count; both track a running max while open (never shrink mid-session), floored at FIXED_H and capped at the screen.
    -- WoW Forever, and Auto-Size with the Compact display: height fits the content on that running max, with no FIXED_H floor (see below).
    local FIXED_H = 650
    -- Resize grip height: the whole window, footer inside it (so a footer
    -- re-wrap never moves the bottom edge)
    local userH = BP().bagHeight
    local totalW = sidebarW + gridContentW
    local autoSize = EUI_Bags.AutoSizeOn()
    if autoSize then
        EUI_Bags._asMaxGridW = math.max(EUI_Bags._asMaxGridW or 0, gridContentW)
        totalW = sidebarW + EUI_Bags._asMaxGridW
    end
    local currencyFooterH = UpdateCurrencyDisplays(totalW) or FOOTER_H

    -- A grip-set height overrides WoW Forever's grow-only content fit (Auto-Size hides the grip)
    if autoSize or (EUI.IS_FOREVER and not userH) then
        local sc = EUI_Bags:GetScale(); if not sc or sc <= 0 then sc = 1 end
        local maxH = (UIParent:GetHeight() / sc) * 0.95
        local fitH = contentH + HEADER_H + currencyFooterH + 2
        local neededH
        if EUI.IS_FOREVER or EUI_Bags.IsCompactMode() then
            -- Fit the content instead of flooring at FIXED_H (WoW Forever bags hold far fewer slots, and the Compact
            -- display packs them tight), never shorter than the category list; on WoW Forever without Auto-Size the
            -- normal height stays the cap (taller content scrolls).
            if not autoSize then maxH = math.min(maxH, FIXED_H + currencyFooterH - FOOTER_H) end
            local sbHdr, sbChild = EUI_Bags._sidebarHdr, EUI_Bags._sidebarChild
            local sbH = HEADER_H + currencyFooterH + (sbHdr and sbHdr:GetHeight() or 0) + (sbChild and sbChild:GetHeight() or 0)
            -- A hidden sidebar (collapsed, no icon strip) sets no floor
            if sidebarW == 0 then sbH = 0 end
            neededH = math.min(math.max(fitH, sbH), maxH)
        else
            -- Cap at the screen first, then floor at FIXED_H so the window is never smaller than normal (even on short screens).
            neededH = math.max(FIXED_H, math.min(fitH, maxH))
        end
        EUI_Bags._asMaxH = math.max(EUI_Bags._asMaxH or 0, neededH)
        EUI_Bags:SetWidth(totalW)
        EUI_Bags:SetHeight(EUI_Bags._asMaxH)
    else
        EUI_Bags:SetWidth(totalW)
        EUI_Bags:SetHeight(userH or (FIXED_H + currencyFooterH - FOOTER_H))
    end

    if EUI_Bags.Header and EUI_Bags.Header.itemCount then
        if selectedCategoryIndex == 0 or selectedCategoryIndex == -1 or selectedCategoryIndex == -2 then
            -- WoW Forever's special bags stay out of this count (spItems/spEmpty)
            local items = totalCount - (spItems or 0)
            local totalSlots = items + numEmpty - (spEmpty or 0)
            EUI_Bags.Header.itemCount:SetText(EllesmereUI.Lf("%d / %d Items", items, totalSlots))
        else
            EUI_Bags.Header.itemCount:SetText(EllesmereUI.Lf("%d Items", totalCount))
        end
    end

    UpdateBagMoneyDisplay()
    -- View may have changed under a held item (catch layer on / off)
    if EUI_Bags._syncDropTarget and GetCursorInfo() == "item" then EUI_Bags._syncDropTarget() end
    ns.UpdateResizeGrip(EUI_Bags, EUI_Bags.IsListMode() and _bagListGripCfg or _bagGripCfg)
end

function EUI_Bags:RefreshInventory()
    if not EUI_Bags:IsVisible() then return end

    -- A select mode's hover box sits on a button this refresh may refill: put
    -- that button's border back now and re-test the hover after
    local hoverCatcher = EUI_Bags._assignCatcher
    if hoverCatcher and hoverCatcher:IsShown() then hoverCatcher._clearHover(); hoverCatcher._hoverDirty = true end
    hoverCatcher = EUI_Bags._pinCatcher
    if hoverCatcher and hoverCatcher:IsShown() then hoverCatcher._clearHover(); hoverCatcher._hoverDirty = true end

    -- Refreshing during combat (bags opened mid-fight in M+/Delves) is safe: moving already-created
    -- buttons taints nothing; only CREATING a secure ContainerFrameItemButtonTemplate in lockdown
    -- poisons it (UseContainerItem() -> ADDON_ACTION_FORBIDDEN). GetOrCreateSlot returns nil in combat (pre-warmed pool makes this rare); PLAYER_REGEN_ENABLED replays a full refresh for anything skipped.
    if InCombatLockdown() then EUI_Bags._refreshPendingCombat = true end

    -- Category indices shift when the list rebuilds (split-mode set categories
    -- come and go); rebuilt below on first IsGearCategory call, so never stale.
    SetGearCatSet(nil)

    C_NewItems.ClearAll()

    -- 1. Gather items from all bags (0-4 + reagent bag 5)
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
                EUI_Bags.ApplyBindKeyword(info, bag, slot)
                -- Pre-cache per-item data for RenderButton (zero API calls at render time)
                if itemLink then
                    local facts = _linkFacts[itemLink]
                    local q, bindType, isGear
                    if facts then
                        q, bindType, isGear = facts.q, facts.bindType, facts.isGear
                    else
                        local _
                        _, _, q, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemLink)
                        isGear = IsGearItem(itemLink)
                        if q ~= nil then
                            if _linkFactsN >= 4000 then wipe(_linkFacts); _linkFactsN = 0 end
                            facts = { q = q, bindType = bindType, isGear = isGear }
                            _linkFacts[itemLink] = facts
                            _linkFactsN = _linkFactsN + 1
                        end
                    end
                    _slotLoc:SetBagAndSlot(bag, slot)
                    local loc = _slotLoc
                    -- Slot-grouping fields (_equipSlot/_classID/_subclassID) are NOT
                    -- pre-cached here: GetArmorySlotBucket fetches them lazily, only
                    -- for gear items and only while Group Gear by Slot is on, so the
                    -- feature costs nothing on the refresh path when disabled.
                    d._giQuality = q
                    d._giBindType = bindType
                    -- Track rank + cooldown: only for types that need them
                    d._isGear = isGear
                    -- The List view's iLvl column always needs the real level
                    d._giIlvl = isGear and (BP().showItemlevelInBags ~= false or EUI_Bags.IsListMode())
                        and GetItemLevelAtLocation(loc, itemLink) or nil
                    -- Upgrade tracks: the grid's item level colour and rank; the
                    -- List view only while its Track column shows or sorts.
                    if isGear and GetUpgradeTrack
                        and (not EUI_Bags.IsListMode() or ns.ListUsesColumn("track")) then
                        local rankText, trackColor
                        if facts and facts.trackText then
                            rankText, trackColor = facts.trackText, facts.trackColor
                        else
                            rankText, trackColor = GetUpgradeTrack(itemLink)
                            if facts and rankText and rankText ~= "" then
                                facts.trackText, facts.trackColor = rankText, trackColor
                            end
                        end
                        -- false: read and none (nil: not read), so the Item
                        -- Icons takeover passes these as known facts
                        if rankText and rankText ~= "" then
                            d._giTrackRank = rankText
                            d._giTrackColor = trackColor or false
                        else
                            d._giTrackRank = false
                            if d._giIlvl and not (BP().itemlevelUseCustomColor and BP().itemlevelCustomColor) then
                                d._giTrackColor = EUI.GetCraftedTrackColor(itemLink) or false
                            end
                        end
                    end
                    -- Warbound check (warbank dim overlay) + WuE bind check (gear only, when bind-type text is enabled).
                    if loc and C_Item.DoesItemExist(loc) then
                        if C_Bank and C_Bank.IsItemAllowedInBankType then
                            d._isWarbound = C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc)
                        end
                        if isGear and not info.isBound and BP().bagDisplayBindType then
                            d._isWuE = C_Item.IsBoundToAccountUntilEquip(loc)
                        end
                    end
                    -- Keystone data (rare, fast string match gates the API calls)
                    local ksLvl, ksMap = EUI.ParseKeystoneLink(itemLink)
                    if ksLvl then
                        d._ksLevel = ksLvl
                        d._ksAbbrev = AbbrevDungeon(ksMap)
                        local ok, color = pcall(C_ChallengeMode.GetKeystoneLevelRarityColor, ksLvl)
                        if ok and color then
                            d._ksR = color.r; d._ksG = color.g; d._ksB = color.b
                        end
                    end
                    -- Cooldown (any item can have a cooldown: trinkets, consumables, toys, etc.)
                    local cdStart, cdDur, cdEnable = C_Container.GetContainerItemCooldown(bag, slot)
                    if cdEnable and cdEnable ~= 0 and cdStart > 0 and cdDur > 0 then
                        d._cdStart = cdStart; d._cdDuration = cdDur
                    end
                    -- _isQuest (any quest item, incl. active objectives + starters) drives the gold
                    -- border; _isQuestStarter (questID set but inactive) is Blizzard's "!" and drives the corner marker.
                    local qInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
                    if qInfo and (qInfo.isQuestItem or qInfo.questID) then
                        d._isQuest = true
                        if qInfo.questID and not qInfo.isActive then
                            d._isQuestStarter = true
                        end
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

    -- 1b. Detect manual item swaps and update saved visual order
    local isAllItems = selectedCategoryIndex == 0 and not selectedGroupName
    local swapDetected = DetectAndApplySwaps(tempItems, isAllItems)
    TakeBagSnapshot(tempItems)

    -- Show blocked-swap tooltip in category/group views (not All Items, not OneBag)
    if swapDetected and not isAllItems and selectedCategoryIndex ~= -1 and selectedCategoryIndex ~= -2 then
        if EUI.ShowWidgetTooltip then
            -- Controller cursor: the pointer may be hidden, so anchor to the window.
            EUI.ShowWidgetTooltip(EUI_Bags, "Positions can only be changed\nin the All Items, OneBag, or MultiBag views", (not EUI.PadInUse()) and { anchor = "cursor" } or nil)
            C_Timer.After(3, function()
                EUI.HideWidgetTooltip()
            end)
        end
    end

    -- 2. Classify all items and get counts
    local categoryCounts, totalCount = EUI_CategoryManager:ClassifyAll(tempItems)

    -- 2a. Snapshot slot->category mapping for partial refresh
    wipe(_slotCategories)
    for _, data in ipairs(tempItems) do
        if data.categoryIndex and data.bag and data.slot then
            _slotCategories[data.bag * 1000 + data.slot] = data.categoryIndex
        end
    end

    -- 2b. Compute display-only counts for pinned and recent items
    local recentCatIdx, pinnedCatIdx
    do
        local cats = EUI_CategoryManager:GetCategories()
        for i, cat in ipairs(cats) do
            if cat.isRecent then recentCatIdx = i end
            if cat.isPinned then pinnedCatIdx = i end
        end
    end
    local showPinned = BP().bagShowPinnedItems ~= false
    local pinnedSet = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
    local hidePinned = BP().bagHidePinnedInCategories == true
    if pinnedCatIdx and pinnedSet and showPinned then
        local pinnedCount = 0
        for _, data in ipairs(tempItems) do
            if data.info and data.info.itemID and IsItemPinned(pinnedSet, data.itemLink, data.info.itemID) then
                pinnedCount = pinnedCount + 1
                if hidePinned then
                    -- Keep the category for sorting and gear/stack handling.
                    data._pinnedOnly = true
                    local ci = data.categoryIndex
                    if ci then categoryCounts[ci] = categoryCounts[ci] - 1 end
                end
            end
        end
        categoryCounts[pinnedCatIdx] = pinnedCount
    end
    local recentCount = 0
    local showRecent = BP().bagShowRecentItems ~= false
    if recentCatIdx and EUI_Bags._recentItems and showRecent then
        for _, data in ipairs(tempItems) do
            if not data._pinnedOnly and data.info and data.info.itemID and EUI_Bags._recentItems[data.info.itemID] then
                recentCount = recentCount + 1
            end
        end
        categoryCounts[recentCatIdx] = recentCount
    end

    -- 3. Update sidebar
    BuildSidebarButtons(categoryCounts, totalCount)

    -- Cache counts for partial refresh
    _lastCatCounts = categoryCounts
    _lastTotalCount = totalCount

    -- 4. Filter items by selected category/group + search
    local isRecentView = recentCatIdx and selectedCategoryIndex == recentCatIdx
    local isPinnedView = pinnedCatIdx and selectedCategoryIndex == pinnedCatIdx
    local filterSet = nil  -- nil = show all
    do
        local cats = EUI_CategoryManager:GetCategories()
        -- The "Item Set Gear" anchor view (and any group holding it) folds in the
        -- split-mode set children, which hold the actual items.
        local function AddSetChildren(anchorIdx)
            if not BP().bagSplitSetGearBySet then return end
            if not (cats[anchorIdx] and cats[anchorIdx].isSetGear and not cats[anchorIdx].isEquipSet) then return end
            for i, c in ipairs(cats) do
                if c.isEquipSet then filterSet[i] = true end
            end
        end
        if selectedGroupName then
            filterSet = {}
            local members = EUI_CategoryManager:GetGroupMembers(selectedGroupName)
            for _, mi in ipairs(members) do
                filterSet[mi] = true
                AddSetChildren(mi)
            end
        elseif selectedCategoryIndex > 0 and not isRecentView and not isPinnedView then
            filterSet = { [selectedCategoryIndex] = true }
            AddSetChildren(selectedCategoryIndex)
        end
    end

    local displayItems = {}
    for _, data in ipairs(tempItems) do
        local show = true
        if isRecentView then
            show = data.info and data.info.itemID and EUI_Bags._recentItems and EUI_Bags._recentItems[data.info.itemID]
        elseif isPinnedView then
            show = data.info and data.info.itemID and pinnedSet and IsItemPinned(pinnedSet, data.itemLink, data.info.itemID)
        elseif filterSet then
            show = data.categoryIndex and filterSet[data.categoryIndex]
        end
        if data._pinnedOnly and (isRecentView or filterSet) then show = false end
        if show and data.info and data.info.isFiltered then show = false end
        if show then displayItems[#displayItems + 1] = data end
    end

    -- 4b. Pending resort: sort + save order for categories invalidated by group changes (reuses already-scanned tempItems, no bag re-scan).
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

    -- WoW Forever: special bags (ns.SpecialBags) stay out of the header's item
    -- and slot count; OneBag gives each one a section of its own.
    local special = ns.SpecialBags()
    local spItems, spEmpty, spBags = 0, 0, 0
    if special then
        for _ in pairs(special) do spBags = spBags + 1 end
        for _, d in ipairs(tempItems) do
            if special[d.bag] and d.itemLink then spItems = spItems + 1 end
        end
        for _, d in ipairs(emptySlots) do
            if special[d.bag] then spEmpty = spEmpty + 1 end
        end
    end

    -- Auto-size: pick a column count keeping the window near its base shape (columns grow
    -- ~sqrt of slot count) while fitting the active tab. Grows only, never shrinks while open
    -- (running max in _asCols, reset on close); HEIGHT follows rendered content up to the screen cap. Decided BEFORE GetColumns() so the grid renders at this count.
    if EUI_Bags.AutoSizeOn() then
        local baseCols = BP().bagColumns or 12
        local BASE_ROWS = 15  -- rows visible at the base (FIXED_H) height
        local HDR = 0.74      -- section-header height in slot-row units (~28/38)
        -- Slot count (n) + section-header count (S) for the active tab. Headers add HEIGHT
        -- but not WIDTH, so they MUST fold into the estimate or a header-heavy tab (All Items with many categories) grows taller than wide.
        local n, S
        if selectedCategoryIndex > 0 and not selectedGroupName then
            n = (categoryCounts and categoryCounts[selectedCategoryIndex]) or #tempItems
            -- The anchor view folds in its set children's items; count them too
            if BP().bagSplitSetGearBySet then
                local szCats = EUI_CategoryManager:GetCategories()
                local selCat = szCats[selectedCategoryIndex]
                if selCat and selCat.isSetGear and not selCat.isEquipSet and categoryCounts then
                    for i, c in ipairs(szCats) do
                        if c.isEquipSet then n = n + (categoryCounts[i] or 0) end
                    end
                end
            end
            S = 1
        elseif selectedCategoryIndex == 0 and not selectedGroupName then
            -- All Items: one section per non-empty category
            n = #tempItems + #emptySlots
            S = 0
            if categoryCounts then
                -- Set children fold into their anchor's section: count them as one
                local sizeCats = BP().bagSplitSetGearBySet and EUI_CategoryManager:GetCategories() or nil
                local hasSetChild = false
                for i, c in pairs(categoryCounts) do
                    if c and c > 0 then
                        if sizeCats and sizeCats[i] and sizeCats[i].isEquipSet then hasSetChild = true
                        else S = S + 1 end
                    end
                end
                if hasSetChild then S = S + 1 end
            end
            if S < 1 then S = 1 end
        elseif selectedCategoryIndex == -2 then
            -- MultiBag: one section per bag that has slots (+ reagent)
            n = #tempItems + #emptySlots
            S = 0
            for bag = 0, 5 do if C_Container.GetContainerNumSlots(bag) > 0 then S = S + 1 end end
            if S < 1 then S = 1 end
        else
            -- OneBag / group view: a few sections (pinned/recent/main/reagent,
            -- plus OneBag's special bags)
            n = #tempItems + #emptySlots
            S = 3 + (selectedCategoryIndex == -1 and spBags or 0)
        end
        n = math.max(n, 1)
        -- Compact: no header rows; each block's gap and part-filled last row
        -- (about a cell) and the label bands are folded into the cell count
        -- as an estimate
        if EUI_Bags.IsCompactMode() then
            n = (n + S - 1) * (1 + ns.CompactBandHeight() / (SLOT_SIZE + SPACING))
            S = 0
        end
        local ideal = baseCols
        -- Only grow when the tab won't fit at the base column count.
        if math.ceil(n / baseCols) + math.ceil(HDR * S) > BASE_ROWS then
            -- Cols such that item+header rows keep the base rows:cols slope (grow together):
            -- solve A*cols^2 - HDR*S*cols - n = 0, where A = BASE_ROWS/baseCols.
            local A = BASE_ROWS / baseCols
            local hs = HDR * S
            ideal = math.ceil((hs + math.sqrt(hs * hs + 4 * A * n)) / (2 * A))
        end
        local sbW = GetSidebarWidth()
        local sc = EUI_Bags:GetScale(); if not sc or sc <= 0 then sc = 1 end
        local maxGridW = (UIParent:GetWidth() / sc) * 0.95 - sbW - 30
        local maxCols = math.max(baseCols, math.floor(maxGridW / (SLOT_SIZE + SPACING)))
        if ideal < baseCols then ideal = baseCols end
        if ideal > maxCols then ideal = maxCols end
        EUI_Bags._asCols = math.max(EUI_Bags._asCols or baseCols, ideal)
    end

    local columns = GetColumns()
    local sidebarW = GetSidebarWidth()
    local gridPadX = 10
    local gridW = columns * (SLOT_SIZE + SPACING)
    -- List rows take the grip-set width (List has no Auto-Size)
    if EUI_Bags.IsListMode() and BP().bagListWidth then
        gridW = BP().bagListWidth
    end
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

    -- Both views below paint with the current panel state, merging or not
    -- (slot views and an unmerged list never reach MergeDuplicates)
    SetPaintedPanelOpen(_anyItemPanelOpen)

    -- List display (latched per session): rows replace the grid; the column
    -- header bar takes the top of the scroll area
    if EUI_Bags.IsListMode() and sf then
        local listH, colHdrH = ns.RenderListView(displayItems, {
            -- Left / Right Gap: space between the list area edges and the rows
            rowW = math.max(100, gridW + gridPadX * 2 + scrollbarPad - (BP().bagListGapL or 15) - (BP().bagListGapR or 23)),
            startX = BP().bagListGapL or 15,
            leftX = sidebarW, topY = -(HEADER_H + 1),
            allItems = isAllItems,
            slotView = (selectedCategoryIndex == -1 and "one") or (selectedCategoryIndex == -2 and "multi") or nil,
            -- Same rule as the grid's Recent Items section
            recent = (showRecent and (isAllItems or (selectedCategoryIndex < 0 and BP().bagRecentInOneBag == true)))
                and EUI_Bags._recentItems or nil,
            -- The Recent Items tab: its items in one newest-first section
            recentOnly = isRecentView or nil,
            -- Empty rows only when nothing is search-filtered out
            emptySlots = (#displayItems == #tempItems) and emptySlots or nil,
            -- Same rule as the grid's Pinned Items section
            pinned = (showPinned and (isAllItems or (selectedCategoryIndex < 0 and BP().bagPinnedInOneBag ~= false)))
                and pinnedSet or nil,
        })
        sf:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", sidebarW, -(HEADER_H + 1 + colHdrH))
        FinishRefresh(-(listH + colHdrH), gridW + gridPadX * 2 + scrollbarPad + 2, sidebarW, totalCount, #emptySlots, spItems, spEmpty)
        return
    end

    local curY = ns.RenderGridView(tempItems, displayItems, emptySlots, child, columns, gridW, gridPadX, showPinned, pinnedSet)

    -- Compact: the window drops the remainder its widest band leaves short of
    -- the columns, less than a cell (ns.CompactBagsContentW). While open it
    -- only grows back, so a refresh never pulls the edge in under the cursor;
    -- a new column count, or a close, starts over.
    if EUI_Bags.IsCompactMode() then
        local w = ns.CompactBagsContentW()
        if w and w < gridW then
            if EUI_Bags._compactCols ~= columns then
                EUI_Bags._compactCols, EUI_Bags._compactW = columns, w
            elseif w > (EUI_Bags._compactW or 0) then
                EUI_Bags._compactW = w
            end
            gridW = EUI_Bags._compactW
        else
            EUI_Bags._compactCols, EUI_Bags._compactW = columns, gridW
        end
        if child then child:SetWidth(gridW + gridPadX * 2 + scrollbarPad) end
    end

    FinishRefresh(curY, gridW + gridPadX * 2 + scrollbarPad + 2, sidebarW, totalCount, #emptySlots, spItems, spEmpty)
end

-------------------------------------------------------------------------------
--  Reagent Bag Refresh
-------------------------------------------------------------------------------
function EUI_BagsReagent:RefreshInventory()
    if not EUI_BagsReagent:IsVisible() then return end
    -- Same secure-button rule as EUI_Bags:RefreshInventory: viewing in combat is fine, creating is not (GetOrCreateReagentSlot refuses); mark pending so combat-end tops up.
    if InCombatLockdown() then EUI_Bags._refreshPendingCombat = true end
    local tempItems = {}
    local numSlots = C_Container.GetContainerNumSlots(5)
    if numSlots > 0 then
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(5, slot)
            tempItems[#tempItems + 1] = { bag = 5, slot = slot, info = info }
        end
    end

    for _, btn in pairs(reagentSlots) do btn:GetParent():Hide() end
    -- Item Icons takeover: the marks come from it, the item level stays empty;
    -- the Junk Marker's verdict is passed only while the marker is on
    local iiOn = ns.ItemIconsOn()
    local junkOn = iiOn and EUI_CategoryManager:IsJunkMarkerEnabled()

    local startX, startY = 15, -45
    local REAGENT_COLUMNS = 4
    for i, data in ipairs(tempItems) do
        local btn = GetOrCreateReagentSlot(i)
        if btn then  -- nil during combat (avoids minting tainted secure buttons)
        local parent = btn:GetParent()
        parent:ClearAllPoints()
        parent:Show()
        btn:Show()
        btn:SetID(data.slot)
        parent:SetID(data.bag)
        local itemLink = data.info and C_Container.GetContainerItemLink(data.bag, data.slot)

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
            local filtered = data.info.isFiltered
            btn:SetAlpha(filtered and 0.2 or 1)
            if btn._textOverlay then btn._textOverlay:SetAlpha(filtered and 0.2 or 1) end

            if btn.ItemLevelText and data.info.itemID then
                local showItemlevel = BP().showItemlevelInBags ~= false and not iiOn
                if showItemlevel then
                    if itemLink then
                        local _, _, quality = GetItemInfo(itemLink)
                        if IsGearItem(itemLink) then
                            local loc = ItemLocation:CreateFromBagAndSlot(data.bag, data.slot)
                            local level = GetItemLevelAtLocation(loc, itemLink)
                            local fs = BP().itemlevelFontSize or 12
                            btn.ItemLevelText:SetFont(STANDARD_TEXT_FONT, fs, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                            btn.ItemLevelText:SetText(level or "")
                            local r, g, b = EUI.ItemLevelRGB(BP().itemlevelUseCustomColor and BP().itemlevelCustomColor,
                                nil, quality or 1)
                            btn.ItemLevelText:SetTextColor(r, g, b, 1)
                        else btn.ItemLevelText:SetText("") end
                    else btn.ItemLevelText:SetText("") end
                else btn.ItemLevelText:SetText("") end
            end

            local r, g, b = ns.QualityBorderColor(data.info.quality or 1)
            SetInsetBorderColor(btn, r, g, b, 1)
        end
        -- No link: Pawn's arrow stays hidden (Item Icons draws its own upgrade arrow)
        UpdatePawnArrow(btn, not iiOn and itemLink or nil)
        if iiOn and itemLink then
            local info, f = data.info, ns.ItemIconsFacts(btn)
            f.isBound = info.isBound
            if junkOn then f.isJunk = EUI_CategoryManager:IsJunk(info.itemID, info.quality) end
            ns.ItemIconsPaint(btn, data.bag, data.slot, itemLink, info.stackCount,
                info.quality, info.itemID, info.isFiltered)
        elseif iiOn then
            ns.ItemIconsPaint(btn)
        end
        if next(EUI_Bags.itemOverlayIcons) ~= nil then
            data.itemLink = itemLink
            EUI_Bags.RunItemOverlays(btn, data)
        end
        -- Tooltip requery after the slot re-assignment (see RenderButton).
        if GameTooltip:IsOwned(btn) then
            if data.info and btn.UpdateTooltip then btn:UpdateTooltip() else GameTooltip:Hide() end
        end

        local col = (i - 1) % REAGENT_COLUMNS
        local row = math.floor((i - 1) / REAGENT_COLUMNS)
        parent:SetPoint("TOPLEFT", startX + (col * (SLOT_SIZE + SPACING)), startY - (row * (SLOT_SIZE + SPACING)))
        end
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
        local bdrR, bdrG, bdrB = 0.25, 0.25, 0.25
        if quality > 0 then bdrR, bdrG, bdrB = ns.QualityBorderColor(quality) end
        SetInsetBorderColor(btn, bdrR, bdrG, bdrB, 1)
        btn._bdrR, btn._bdrG, btn._bdrB = bdrR, bdrG, bdrB

        -- Blizzard's bag bar order: backpack on the right, reagent bag on the left
        parent:ClearAllPoints()
        parent:SetPoint("TOPLEFT", EUI_BagsWindow, "TOPLEFT", startX + ((BAG_COLUMNS - 1 - i) * (SLOT_SIZE + SPACING)), startY)
    end
    EUI_BagsWindow:SetSize((BAG_COLUMNS * (SLOT_SIZE + SPACING)) + 15, SLOT_SIZE + 20)
end

I._catHeaders, I._expSubHeaders = _catHeaders, _expSubHeaders
I.CreateBagScrollFrame, I.GetOrCreateCatHeader = CreateBagScrollFrame, GetOrCreateCatHeader
I.GetOrCreateExpSubHeader = GetOrCreateExpSubHeader
I.ShowRecentClearButton = ShowRecentClearButton
I.broken = false
