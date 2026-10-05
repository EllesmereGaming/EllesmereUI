if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_List.lua
--  List bag display (bagDisplayMode = "list"): one row per bag slot, grouped by category
--  with optional subtype sub-sections, and a column header bar on the bag
--  frame (click = sort, drag = reorder, right-click = add/remove columns).
--  Mode is latched per session (EUI_Bags.IsListMode): in grid mode nothing
--  here is ever built. The bank's List View (bankListView) reuses the row,
--  column and header bar pieces via ns.
-------------------------------------------------------------------------------
local ns = select(2, ...)
if not (ns and ns.SetBagFont) then return end

local EUI = EllesmereUI
local L = EllesmereUI.L
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end

local ROW_H, ICON_SIZE, COL_GAP = 24, 20, 6
local function RowH() return BP().bagListRowHeight or ROW_H end
local COLHDR_H = 20
local SECTION_H, SUBSECTION_H = 22, 18
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local ROUND_ZOOM = 0.12
local ARROW_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-left.png"
local BAG_GLYPH_TEX = "Interface\\AddOns\\EllesmereUI\\media\\micromenu\\menu-bags.png"

-- Column definitions. width nil = flexible (takes the leftover row width).
-- field = the per-item sort value stamped in StampItem (nil = not
-- sortable); desc = numeric
-- columns sort high-to-low on first click.
local COLUMNS = {
    icon   = { label = "",           width = ICON_SIZE, menuLabel = "Icon" },  -- not sortable
    name   = { label = "Name",       field = "_lvName", justify = "LEFT" },
    ilvl   = { label = "iLvl",       width = 36,  field = "_lvIlvl",  desc = true, justify = "RIGHT" },
    reqlvl = { label = "Req",        width = 32,  field = "_lvReq",   desc = true, justify = "RIGHT", menuLabel = "Required Level" },
    type   = { label = "Type",       width = 96,  field = "_lvType",  justify = "LEFT" },
    bind   = { label = "Bind",       width = 40,  field = "_lvBind",  justify = "LEFT", menuLabel = "Bind Status" },
    track  = { label = "Track",      width = 40,  field = "_lvTrackSort", desc = true, justify = "RIGHT", menuLabel = "Upgrade Track" },
    count  = { label = "#",      width = 40,  field = "_lvCount", desc = true, justify = "RIGHT" },
    sell   = { label = "Sell Price", width = 100, field = "_lvSell",  desc = true, justify = "RIGHT" },
}
local COLUMN_ORDER = { "icon", "name", "ilvl", "track", "reqlvl", "type", "bind", "count", "sell" }
local DEFAULT_COLUMNS = { "icon", "name", "ilvl", "count", "sell" }

local function GetColumns()
    return BP().bagListColumns or DEFAULT_COLUMNS
end

-- Always writes a fresh copy so DEFAULT_COLUMNS is never mutated.
local function SetColumns(list)
    BP().bagListColumns = CopyTable(list)
end

-- List font: resolved once per layout pass, applied only when it changed
local _lfPath, _lfSize, _lfFlag
local function ResolveListFont()
    _lfPath = EUI.GetFontPath("bags")
    _lfSize = BP().bagListFontSize or 11
    _lfFlag = EUI.GetFontOutlineFlag("bags")
end
local function SetListFont(fs, size)
    if not _lfPath then ResolveListFont() end
    size = size or _lfSize
    if fs._lfPath == _lfPath and fs._lfSize == size and fs._lfFlag == _lfFlag then return end
    fs._lfPath, fs._lfSize, fs._lfFlag = _lfPath, size, _lfFlag
    EUI.PrimeFontShadow(fs, true)
    fs:SetFont(_lfPath, size, _lfFlag)
end

-- Repaints both list views; the bank only while it shows its List View.
local function Refresh()
    if EUI_Bags and EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
    local bank = _G.EUI_BankFrame
    if bank and bank.RefreshBank and bank.IsListMode and bank.IsListMode() then bank:RefreshBank() end
end

-------------------------------------------------------------------------------
--  Subtype splitting: classID -> profile toggle
-------------------------------------------------------------------------------
local IC = Enum.ItemClass
local SPLIT_KEY = {
    [IC.Armor]      = "bagListSplitArmor",
    [IC.Weapon]     = "bagListSplitWeapons",
    [IC.Tradegoods] = "bagListSplitProfessions",
    [IC.Reagent]    = "bagListSplitProfessions",
    [IC.Recipe]     = "bagListSplitProfessions",
    [19]            = "bagListSplitProfessions",  -- Enum.ItemClass.Profession (Midnight)
}

-------------------------------------------------------------------------------
--  Bind column: Enum.ItemBind -> short label. Bound BoE / BoU / WuE items
--  read as SB (Soulbound); account binds keep their label.
-------------------------------------------------------------------------------
local IB = Enum.ItemBind
local BIND_ABBR = {
    [IB.OnAcquire]                  = "BoP",
    [IB.OnEquip]                    = "BoE",
    [IB.OnUse]                      = "BoU",
    [IB.Quest]                      = "Quest",
    [IB.ToWoWAccount]               = "BoA",
    [IB.ToBnetAccount]              = "WB",   -- Warbound
    [IB.ToBnetAccountUntilEquipped] = "WuE",
}
local BIND_SOULBOUND = {
    [IB.OnEquip] = true, [IB.OnUse] = true, [IB.ToBnetAccountUntilEquipped] = true,
}
-- Warbound until Equipped reads as OnEquip from GetItemInfo; the item's bag
-- location tells them apart (one reused location, no per-row allocation).
local _bindLoc = ItemLocation:CreateEmpty()

-------------------------------------------------------------------------------
--  Per-item values (stamped on the pooled slot tables, wiped on reuse)
-------------------------------------------------------------------------------
local function StampItem(d)
    local info = d.info
    local count = d._mergedCount or info.stackCount or 1
    local _, _, _, baseIlvl, reqLevel, _, _, _, _, _, sellPrice, _, _, bindType = GetItemInfo(d.itemLink)
    local _, _, subType, _, _, classID = GetItemInfoInstant(d.itemLink)
    d._lvName = info.itemName or ""
    d._lvQuality = info.quality or 1
    d._lvIlvl = d._isGear and (tonumber(d._giIlvl) or baseIlvl) or 0
    d._lvReq = (reqLevel and reqLevel > 1) and reqLevel or 0
    d._lvType = subType or ""
    d._lvCount = count
    -- Track sort: tier (EUI._TRACK_RANK) then rank within it
    local rank, tc = d._giTrackRank or "", d._giTrackColor
    d._lvTrack = rank
    d._lvTrackSort = tc and ((EUI._TRACK_RANK and EUI._TRACK_RANK[tc] or 0) * 100 + (tonumber(rank:match("^(%d+)")) or 0)) or 0
    d._lvSell = (not info.hasNoValue and sellPrice) and sellPrice * count or 0
    if bindType == IB.OnEquip and not info.isBound and d.bag and d.slot then
        _bindLoc:SetBagAndSlot(d.bag, d.slot)
        if C_Item.IsBoundToAccountUntilEquip(_bindLoc) then bindType = IB.ToBnetAccountUntilEquipped end
    end
    if info.isBound and BIND_SOULBOUND[bindType] then
        d._lvBind = L("SB")
    else
        d._lvBind = bindType and BIND_ABBR[bindType] and L(BIND_ABBR[bindType]) or ""
    end
    local key = classID and SPLIT_KEY[classID]
    d._lvSub = (key and BP()[key] and subType) or ""
end
ns.StampListItem = StampItem

-- Static comparator (no per-refresh closures); _sk/_sa set before each sort.
local _sk, _sa = "_lvQuality", false
local function ListCompare(a, b)
    local va, vb = a[_sk], b[_sk]
    if va ~= vb then
        if _sa then return va < vb end
        return va > vb
    end
    if a._lvName ~= b._lvName then return a._lvName < b._lvName end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end
ns.ListCompare = ListCompare

-- OneBag / MultiBag: real bag/slot order
local function SlotCompare(a, b)
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

local function SubCompare(a, b)
    -- Unsplit items ("") first, then subtypes alphabetically
    if a.label == "" then return b.label ~= "" end
    if b.label == "" then return false end
    return a.label < b.label
end

-------------------------------------------------------------------------------
--  Frame pools
-------------------------------------------------------------------------------
local _rows, _sections, _hdrBars = {}, {}, {}
local _rowsUsed, _sectionsUsed = 0, 0
local _warn

local function SkinRow(btn)
    -- Methods only on template sub-objects (property writes taint)
    if btn.NewItemTexture then btn.NewItemTexture:Hide(); btn.NewItemTexture:SetAlpha(0) end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide(); btn.BattlepayItemTexture:SetAlpha(0) end
    if btn.flash then btn.flash:Hide(); btn.flash:SetAlpha(0) end
    if btn.newitemglowAnim then btn.newitemglowAnim:Stop() end
    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
    if btn.icon then btn.icon:SetAlpha(0) end
    if btn.Count then btn.Count:SetAlpha(0) end
    local ht = btn:GetHighlightTexture()
    if ht then ht:SetTexture(nil); ht:SetColorTexture(1, 1, 1, 0.08); ht:ClearAllPoints(); ht:SetAllPoints(btn) end
    local pt = btn:GetPushedTexture()
    if pt then pt:SetAtlas(nil); pt:SetTexture(nil); pt:SetColorTexture(1, 1, 1, 0.04); pt:ClearAllPoints(); pt:SetAllPoints(btn) end
end

-- Bare secure container row (no click hooks) parented under host. Returns
-- nil in combat (a secure button born in lockdown is tainted); callers skip
-- the row and fill it after combat.
local _hostRows = {}  -- host -> rows created under it (live column reflow)
function ns.CreateListRow(host)
    if InCombatLockdown() then return nil end
    local slotParent = CreateFrame("Frame", nil, host)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    SkinRow(btn)

    btn._stripe = btn:CreateTexture(nil, "BACKGROUND")
    btn._stripe:SetAllPoints()
    btn._stripe:SetColorTexture(1, 1, 1, 0.03)

    btn._lvIcon = btn:CreateTexture(nil, "ARTWORK")
    btn._lvIcon:SetSize(ICON_SIZE, ICON_SIZE)
    if btn.Cooldown then
        btn.Cooldown:ClearAllPoints()
        btn.Cooldown:SetAllPoints(btn._lvIcon)
        btn.Cooldown:SetHideCountdownNumbers(true)
    end
    -- Third-party overlay painters (EUI_Bags.RunItemOverlays) parent to this,
    -- as on the grid slots: here it covers the row's icon.
    local ov = CreateFrame("Frame", nil, btn)
    ov:SetAllPoints(btn._lvIcon)
    ov:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 2)
    btn._textOverlay = ov
    btn._cells = {}
    local list = _hostRows[host]
    if not list then list = {}; _hostRows[host] = list end
    list[#list + 1] = btn
    return btn
end

-- Secure container button, one per row. NEVER created in combat (a button
-- born in lockdown is tainted); RefreshInventory flags the combat refresh
-- and PLAYER_REGEN_ENABLED replays it, which fills the gap.
local function GetOrCreateRow(idx)
    if _rows[idx] then return _rows[idx] end
    if InCombatLockdown() then EUI_Bags._poolShort = true; return nil end
    local btn = ns.CreateListRow(EUI_Bags)
    btn:HookScript("OnMouseUp", ns.SlotMiddleClick)
    btn:HookScript("PreClick", ns.BankRoutePreClick)
    btn:HookScript("OnClick", ns.BankRouteOnClick)
    btn:HookScript("PostClick", function(self)
        EUI_Bags.ShowStackSplitter(self, ns.SplitTargetBags(self:GetParent():GetID()), EUI_Bags)
    end)
    _rows[idx] = btn
    return btn
end

-- Pre-build rows out of combat so a first open mid-fight has them.
-- Returns false when combat stopped it (GetOrCreateRow flags _poolShort) or
-- the optional time budget (msBudget ms from t0) ran out.
function ns.WarmListRows(total, t0, msBudget)
    for i = 1, total do
        if not _rows[i] then
            local b = GetOrCreateRow(i)
            if not b then return false end
            b:GetParent():Hide()
            if t0 and debugprofilestop() - t0 > msBudget then
                EUI_Bags._poolShort = true
                return false
            end
        end
    end
    return true
end

local function GetCell(btn, id)
    local fs = btn._cells[id]
    if not fs then
        fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        fs:SetJustifyH(COLUMNS[id].justify or "LEFT")
        btn._cells[id] = fs
    end
    SetListFont(fs)
    return fs
end

local function SetRoundIcon(btn, round)
    if (btn._lvRound or false) == round then return end
    btn._lvRound = round
    if round then
        if not btn._lvMask then
            btn._lvMask = btn:CreateMaskTexture()
            btn._lvMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn._lvMask:SetAllPoints(btn._lvIcon)
        end
        btn._lvIcon:AddMaskTexture(btn._lvMask)
        if btn.Cooldown then btn.Cooldown:SetSwipeTexture(ROUND_MASK) end
    else
        btn._lvIcon:RemoveMaskTexture(btn._lvMask)
        if btn.Cooldown then btn.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8") end
    end
end

-- Collapsed sections, keyed by category _defaultName, "junk", or
-- "<section key>/<subtype>" for sub-sections. Saved in the profile.
-- Shift-click on a top-level section collapses or expands all of them.
local function ToggleCollapsed(self)
    local p = BP()
    local set = p.bagListCollapsed
    if not set then set = {}; p.bagListCollapsed = set end
    if IsShiftKeyDown() and not self._sub then
        local collapse = not set[self._key] or nil
        for i = 1, _sectionsUsed do
            local s = _sections[i]
            if not s._sub then set[s._key] = collapse end
        end
    else
        set[self._key] = not set[self._key] or nil
    end
    Refresh()
end

local function GetOrCreateSection(idx)
    if _sections[idx] then return _sections[idx] end
    local f = CreateFrame("Button", nil, EUI_Bags)
    f._arrow = f:CreateTexture(nil, "OVERLAY")
    f._arrow:SetSize(8, 8)
    f._arrow:SetTexture(ARROW_TEX)
    f._arrow:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._label = f:CreateFontString(nil, "OVERLAY")
    f._label:SetPoint("LEFT", f._arrow, "RIGHT", 4, 0)
    f._label:SetJustifyH("LEFT")
    f._count = f:CreateFontString(nil, "OVERLAY")
    f._count:SetPoint("LEFT", f._label, "RIGHT", 4, 0)
    f._count:SetTextColor(0.7, 0.7, 0.7, 0.9)
    f._line = f:CreateTexture(nil, "ARTWORK")
    f._line:SetHeight(EUI.PP.mult)
    f._line:SetPoint("LEFT", f._count, "RIGHT", 6, 0)
    f._line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    f:SetScript("OnClick", ToggleCollapsed)
    f:SetScript("OnEnter", function(self) self._label:SetAlpha(1); self._arrow:SetAlpha(1) end)
    f:SetScript("OnLeave", function(self) self._label:SetAlpha(0.8); self._arrow:SetAlpha(0.6) end)
    f._label:SetAlpha(0.8)
    f._arrow:SetAlpha(0.6)
    _sections[idx] = f
    return f
end

-------------------------------------------------------------------------------
--  Column layout: x offset + width per visible column
-------------------------------------------------------------------------------
-- Fixed column width: the header-resized width, else the default.
-- The icon column never resizes.
local MIN_COL_W, MIN_FLEX_W = 20, 60
local function FixedWidth(id)
    local def = COLUMNS[id]
    if not def.width then return nil end
    if id == "icon" then return def.width end
    local saved = BP().bagListColWidths
    return (saved and saved[id]) or def.width
end

local _colX, _colW = {}, {}
local _lastRowW
local function LayoutColumns(rowW)
    _lastRowW = rowW
    ResolveListFont()
    local cols = GetColumns()
    local fixed = 0
    for _, id in ipairs(cols) do
        fixed = fixed + (FixedWidth(id) or 0)
    end
    local flexW = math.max(MIN_FLEX_W, rowW - fixed - COL_GAP * (#cols + 1))
    local x = COL_GAP
    for _, id in ipairs(cols) do
        local w = FixedWidth(id) or flexW
        _colX[id], _colW[id] = x, w
        x = x + w + COL_GAP
    end
    return cols
end
ns.ListLayoutColumns = LayoutColumns

-------------------------------------------------------------------------------
--  Column header bar: click sorts, drag reorders, right-click edits columns
-------------------------------------------------------------------------------
local function MoveColumn(id, toIdx)
    local cols = {}
    for _, c in ipairs(GetColumns()) do
        if c ~= id then cols[#cols + 1] = c end
    end
    toIdx = math.max(1, math.min(toIdx, #cols + 1))
    table.insert(cols, toIdx, id)
    SetColumns(cols)
    Refresh()
end

local IndexOf = tIndexOf

local function ToggleColumn(id)
    local cols = GetColumns()
    local at = IndexOf(cols, id)
    local out = {}
    for _, c in ipairs(cols) do out[#out + 1] = c end
    if at then
        if #out == 1 then return end  -- keep at least one column
        table.remove(out, at)
    else
        -- Re-add in its default position relative to the shown columns
        local rank = IndexOf(COLUMN_ORDER, id)
        local insertAt = #out + 1
        for i, c in ipairs(out) do
            if IndexOf(COLUMN_ORDER, c) > rank then insertAt = i; break end
        end
        table.insert(out, insertAt, id)
    end
    SetColumns(out)
    Refresh()
end

-- True while a column is shown or still sorts the list (its data is needed)
function ns.ListUsesColumn(id)
    return IndexOf(GetColumns(), id) ~= nil or BP().bagListSortKey == id
end

local function ShowColumnMenu(owner, id)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L("Columns"))
        for _, cid in ipairs(COLUMN_ORDER) do
            -- WoW Forever has no upgrade tracks: Track is offered there only
            -- to switch off a column an imported profile brought in
            if cid ~= "track" or not EUI.IS_FOREVER or IndexOf(GetColumns(), cid) then
                local def = COLUMNS[cid]
                root:CreateCheckbox(L(def.menuLabel or def.label),
                    function() return IndexOf(GetColumns(), cid) ~= nil end,
                    function() ToggleColumn(cid) end)
            end
        end
        root:CreateDivider()
        local at = IndexOf(GetColumns(), id)
        if at and at > 1 then
            root:CreateButton(L("Move Left"), function() MoveColumn(id, at - 1) end)
        end
        if at and at < #GetColumns() then
            root:CreateButton(L("Move Right"), function() MoveColumn(id, at + 1) end)
        end
        root:CreateCheckbox(L("Round Icons"),
            function() return BP().bagListRoundIcons == true end,
            function() BP().bagListRoundIcons = not BP().bagListRoundIcons; Refresh() end)
        root:CreateButton(L("Reset Columns"), function()
            BP().bagListColumns = nil
            BP().bagListSortKey = nil
            BP().bagListColWidths = nil
            Refresh()
        end)
    end)
end

-- Live column drag: once past 6px, the column moves as the cursor crosses
-- a neighbour's centre (centres of the other columns, so a wide neighbour
-- cannot bounce it back and forth). OnUpdate only while the button is held.
local function OnHeaderDragUpdate(self)
    if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil); return end
    local cx = GetCursorPosition()
    if not self._dragged then
        if math.abs(cx - self._downX) <= 6 then return end
        self._dragged = true
    end
    cx = cx / self:GetEffectiveScale()
    local cols, btns = GetColumns(), self:GetParent()._btns
    local target = 1
    for _, cid in ipairs(cols) do
        local b = btns[cid]
        if cid ~= self._colId and b then
            local l, r = b:GetLeft(), b:GetRight()
            if l and cx > (l + r) / 2 then target = target + 1 end
        end
    end
    if target ~= IndexOf(cols, self._colId) then MoveColumn(self._colId, target) end
end

local function OnHeaderMouseDown(self, button)
    if button ~= "LeftButton" then return end
    self._downX = GetCursorPosition()
    self._dragged = nil
    self:SetScript("OnUpdate", OnHeaderDragUpdate)
end

local function OnHeaderMouseUp(self, button)
    if button == "RightButton" then ShowColumnMenu(self, self._colId); return end
    if button ~= "LeftButton" or not self._downX then return end
    self:SetScript("OnUpdate", nil)
    self._downX = nil
    -- A drag already moved the column live
    if self._dragged then self._dragged = nil; return end
    local def = COLUMNS[self._colId]
    if not def.field then return end
    local p = BP()
    if p.bagListSortKey == self._colId then
        p.bagListSortAsc = not p.bagListSortAsc
    else
        p.bagListSortKey = self._colId
        p.bagListSortAsc = not def.desc
    end
    Refresh()
end

-- Live column reflow: re-place the header buttons and the visible rows'
-- cells from the current widths, without a bag rescan.
local function ReflowHost(host)
    local bar = _hdrBars[host]
    if not bar or not bar:IsShown() or not bar._rowW then return end
    local cols = LayoutColumns(bar._rowW)
    ns.UpdateListHeaderBar(host, cols, bar._leftX, bar._topY, bar._startX, bar._noSort)
    for _, btn in ipairs(_hostRows[host] or _emptyP) do
        if btn:IsVisible() then
            if btn._lvIcon:IsShown() and _colX.icon then
                btn._lvIcon:ClearAllPoints()
                btn._lvIcon:SetPoint("LEFT", btn, "LEFT", _colX.icon, 0)
            end
            for id, fs in pairs(btn._cells) do
                if fs:IsShown() and IndexOf(cols, id) then
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", btn, "LEFT", _colX[id], 0)
                    fs:SetWidth(_colW[id])
                end
            end
        end
    end
end

-- Column resize: a grip on the header edge facing the flexible (Name)
-- column; the flexible column gives or takes the width. OnUpdate only while
-- the grip is held; a full refresh runs once on release.
local function SizerStop(self)
    if not self._startW then return end
    self:SetScript("OnUpdate", nil)
    self._startW = nil
    Refresh()
end

local function SizerOnUpdate(self)
    if not IsMouseButtonDown("LeftButton") then SizerStop(self); return end
    local hdr = self:GetParent()
    local cx = GetCursorPosition() / hdr:GetEffectiveScale()
    local w = math.floor(self._startW + self._sign * (cx - self._startCX) + 0.5)
    w = math.max(MIN_COL_W, math.min(self._maxW, w))
    if w == self._lastW then return end
    self._lastW = w
    local p = BP()
    local t = p.bagListColWidths
    if not t then t = {}; p.bagListColWidths = t end
    t[hdr._colId] = w
    for host in pairs(_hdrBars) do ReflowHost(host) end
end

local function SizerOnMouseDown(self, button)
    if button ~= "LeftButton" then return end
    local hdr = self:GetParent()
    local bar = hdr:GetParent()
    if not bar._rowW then return end
    LayoutColumns(bar._rowW)
    -- Width the flexible column can give up (no flexible column: capped growth)
    local slack = 200
    for _, cid in ipairs(GetColumns()) do
        if not COLUMNS[cid].width then slack = _colW[cid] - MIN_FLEX_W end
    end
    self._startW = FixedWidth(hdr._colId)
    self._lastW = self._startW
    self._maxW = self._startW + math.max(0, slack)
    self._startCX = GetCursorPosition() / hdr:GetEffectiveScale()
    self:SetScript("OnUpdate", SizerOnUpdate)
end

local function GetOrCreateHeaderBtn(bar, id)
    if bar._btns[id] then return bar._btns[id] end
    local b = CreateFrame("Button", nil, bar)
    b:SetHeight(COLHDR_H)
    b._colId = id
    b._label = b:CreateFontString(nil, "OVERLAY")
    SetListFont(b._label, 10)
    b._label:SetAllPoints()
    b._label:SetJustifyH(COLUMNS[id].justify or "LEFT")
    b._label:SetText(COLUMNS[id].label ~= "" and L(COLUMNS[id].label) or "")
    b._label:SetTextColor(0.6, 0.6, 0.6)
    b._arrow = b:CreateTexture(nil, "OVERLAY")
    b._arrow:SetSize(8, 8)
    b._arrow:SetTexture(ARROW_TEX)
    if id == "icon" then
        -- The icon column has no label: a bag glyph over the row icons,
        -- tinted like the labels.
        b._glyph = b:CreateTexture(nil, "OVERLAY")
        b._glyph:SetSize(12, 12)
        b._glyph:SetPoint("CENTER")
        b._glyph:SetTexture(BAG_GLYPH_TEX)
        b._glyph:SetVertexColor(0.6, 0.6, 0.6)
    end
    b:SetScript("OnMouseDown", OnHeaderMouseDown)
    b:SetScript("OnMouseUp", OnHeaderMouseUp)
    if COLUMNS[id].width and id ~= "icon" then
        local g = CreateFrame("Button", nil, b)
        g:SetSize(COL_GAP, COLHDR_H)
        local line = g:CreateTexture(nil, "HIGHLIGHT")
        line:SetWidth(EUI.PP.mult)
        line:SetPoint("TOP"); line:SetPoint("BOTTOM")
        line:SetColorTexture(1, 1, 1, 0.6)
        g:SetScript("OnMouseDown", SizerOnMouseDown)
        g:SetScript("OnMouseUp", SizerStop)
        g:SetScript("OnHide", SizerStop)
        b._sizer = g
    end
    b:SetScript("OnEnter", function(self)
        self._label:SetTextColor(1, 1, 1)
        if self._glyph then self._glyph:SetVertexColor(1, 1, 1) end
        EUI.ShowWidgetTooltip(self, COLUMNS[self._colId].field
            and L("Click to sort. Drag to reorder. Right-click to add or remove columns.")
            or L("Drag to reorder. Right-click to add or remove columns."))
    end)
    b:SetScript("OnLeave", function(self)
        self._label:SetTextColor(0.6, 0.6, 0.6)
        if self._glyph then self._glyph:SetVertexColor(0.6, 0.6, 0.6) end
        EUI.HideWidgetTooltip()
    end)
    bar._btns[id] = b
    return b
end

-- One column header bar per host frame (bags, bank). Returns its height.
function ns.UpdateListHeaderBar(host, cols, leftX, topY, startX, noSort)
    local bar = _hdrBars[host]
    if not bar then
        bar = CreateFrame("Frame", nil, host)
        bar:SetHeight(COLHDR_H)
        bar._btns = {}
        local line = bar:CreateTexture(nil, "ARTWORK")
        line:SetHeight(EUI.PP.mult)
        line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
        line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
        _hdrBars[host] = bar
    end
    -- Kept for live reflow while a column is resized
    bar._rowW, bar._leftX, bar._topY, bar._startX, bar._noSort = _lastRowW, leftX, topY, startX, noSort
    local flexIdx
    for i, id in ipairs(cols) do
        if not COLUMNS[id].width then flexIdx = i end
    end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", leftX, topY)
    bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, topY)
    bar:Show()
    -- Hide only dropped columns: hiding the held button would end its drag
    for id, b in pairs(bar._btns) do
        if not IndexOf(cols, id) then b:Hide() end
    end
    local sortKey = not noSort and BP().bagListSortKey
    for i, id in ipairs(cols) do
        local b = GetOrCreateHeaderBtn(bar, id)
        SetListFont(b._label, 10)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", startX + _colX[id], 0)
        b:SetWidth(math.max(_colW[id], 12))
        if b._sizer then
            -- Grip sits in the gap on the side facing the flexible column
            local g = b._sizer
            g:ClearAllPoints()
            if flexIdx and i > flexIdx then
                g._sign = -1
                g:SetPoint("RIGHT", b, "LEFT", 0, 0)
            else
                g._sign = 1
                g:SetPoint("LEFT", b, "RIGHT", 0, 0)
            end
        end
        b._arrow:ClearAllPoints()
        if id == sortKey and COLUMNS[id].field then
            -- Arrow sits beside the label, on the side away from the text
            if COLUMNS[id].justify == "RIGHT" then
                b._arrow:SetPoint("RIGHT", b, "RIGHT", -(b._label:GetStringWidth() + 3), 0)
            else
                b._arrow:SetPoint("LEFT", b._label, "LEFT", b._label:GetStringWidth() + 3, 0)
            end
            b._arrow:SetRotation(BP().bagListSortAsc and -math.pi / 2 or math.pi / 2)
            b._arrow:Show()
        else
            b._arrow:Hide()
        end
        b:Show()
    end
    return COLHDR_H
end

-- Sets the ListCompare sort field from the saved header sort.
function ns.ListSortSetup()
    local sortDef = BP().bagListSortKey and COLUMNS[BP().bagListSortKey]
    if sortDef and sortDef.field then
        _sk, _sa = sortDef.field, BP().bagListSortAsc == true
    else
        _sk, _sa = "_lvQuality", false
    end
end

-------------------------------------------------------------------------------
--  Render
-------------------------------------------------------------------------------
local function RenderRow(btn, data, cols, rowW, x, y, stripe)
    -- Bags and bank share the column tables at their own row widths: a bank
    -- batch painted after a bags refresh re-lays them out for its width.
    if rowW ~= _lastRowW then LayoutColumns(rowW) end
    local parent = btn:GetParent()
    parent:ClearAllPoints()
    parent:SetSize(rowW, RowH())
    parent:SetPoint("TOPLEFT", x, y)
    parent:SetID(data.bag)
    btn:SetID(data.slot)
    parent:Show()
    btn:Show()
    btn._stripe:SetShown(stripe and BP().bagListHideStripes ~= true)

    local info = data.info
    local q = info.quality or 1
    for _, fs in pairs(btn._cells) do fs:Hide() end
    btn._lvIcon:Hide()
    for _, id in ipairs(cols) do
        local cx, cw = _colX[id], _colW[id]
        if id == "icon" then
            local icon = btn._lvIcon
            local isz = math.min(ICON_SIZE, RowH() - 4)
            icon:SetSize(isz, isz)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", btn, "LEFT", cx, 0)
            icon:SetTexture(info.iconFileID)
            local round = BP().bagListRoundIcons == true
            SetRoundIcon(btn, round)
            -- Round: fixed crop past the icon's baked-in border so the circle edge stays clean
            local z = round and ROUND_ZOOM or (BP().bagItemIconZoom or 0.08)
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
            icon:SetDesaturated(info.isLocked or (BP().bagDesaturateJunkItems and q == 0) or false)
            if EUI._BagsItemUnusable(data.bag, data.slot, data.itemLink, info.itemID) then
                icon:SetVertexColor(1, 0.1, 0.1)
            else
                icon:SetVertexColor(1, 1, 1)
            end
            icon:Show()
            if BP().bagListQualityBorder == true and not round then
                local ov = btn._textOverlay
                if not ov._brdT then ns.CreateInsetBorder(ov) end
                local c = ITEM_QUALITY_COLORS[q]
                if c then ns.SetInsetBorderColor(ov, c.r, c.g, c.b, 1)
                else ns.SetInsetBorderColor(ov, 0.25, 0.25, 0.25, 1) end
            elseif btn._textOverlay._brdT then
                ns.SetInsetBorderColor(btn._textOverlay, 0, 0, 0, 0)
            end
        else
            local fs = GetCell(btn, id)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", cx, 0)
            fs:SetWidth(cw)
            local text
            if id == "name" then
                text = data._lvName
                local c = ITEM_QUALITY_COLORS[q]
                if c then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(1, 1, 1) end
            else
                fs:SetTextColor(0.85, 0.85, 0.85)
                if id == "ilvl" then
                    text = data._lvIlvl > 0 and data._lvIlvl or ""
                elseif id == "reqlvl" then
                    text = data._lvReq > 0 and data._lvReq or ""
                elseif id == "type" then
                    text = data._lvType
                elseif id == "bind" then
                    text = data._lvBind
                elseif id == "track" then
                    text = data._lvTrack
                    local tc = data._giTrackColor
                    if tc then fs:SetTextColor(tc.r, tc.g, tc.b) end
                elseif id == "count" then
                    text = data._lvCount > 1 and data._lvCount or ""
                elseif id == "sell" then
                    text = data._lvSell > 0 and C_CurrencyInfo.GetCoinTextureString(data._lvSell) or ""
                end
            end
            fs:SetText(text)
            fs:Show()
        end
    end

    if btn.Cooldown then
        if data._cdStart and IndexOf(cols, "icon") then
            btn.Cooldown:SetCooldown(data._cdStart, data._cdDuration)
        else
            btn.Cooldown:Clear()
        end
    end
    btn._textOverlay:SetShown(btn._lvIcon:IsShown())
    EUI_Bags.RunItemOverlays(btn, data)
    -- Tooltip requery after the slot re-assignment (see RenderButton)
    if GameTooltip:IsOwned(btn) and btn.UpdateTooltip then btn:UpdateTooltip() end
end
ns.RenderListRow = RenderRow

-- Empty bag slot row (OneBag / MultiBag); clicking or dropping an item
-- places it in that slot.
local function RenderEmptyRow(btn, cols, d, rowW, x, y, stripe)
    if rowW ~= _lastRowW then LayoutColumns(rowW) end
    local parent = btn:GetParent()
    parent:ClearAllPoints()
    parent:SetSize(rowW, RowH())
    parent:SetPoint("TOPLEFT", x, y)
    parent:SetID(d.bag)
    btn:SetID(d.slot)
    parent:Show()
    btn:Show()
    btn._stripe:SetShown(stripe and BP().bagListHideStripes ~= true)
    btn._lvIcon:Hide()
    for _, fs in pairs(btn._cells) do fs:Hide() end
    if btn.Cooldown then btn.Cooldown:Clear() end
    local hasName = IndexOf(cols, "name")
    local fs = GetCell(btn, "name")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", btn, "LEFT", hasName and _colX.name or COL_GAP, 0)
    fs:SetWidth(hasName and _colW.name or (rowW - COL_GAP * 2))
    fs:SetTextColor(0.4, 0.4, 0.4)
    fs:SetText(L("Empty"))
    fs:Show()
    -- No item: painters clear what they drew on this reused row
    btn._textOverlay:Hide()
    EUI_Bags.RunItemOverlays(btn, d)
    if GameTooltip:IsOwned(btn) and btn.UpdateTooltip then btn:UpdateTooltip() end
end
ns.ListRowH = RowH

-- Returns the header height and whether the section is collapsed.
local function PlaceSection(key, label, count, x, y, w, sub)
    _sectionsUsed = _sectionsUsed + 1
    local s = GetOrCreateSection(_sectionsUsed)
    s:SetParent(EUI_Bags._scrollChild)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", x + (sub and 12 or 0), y)
    s:SetSize(w - (sub and 12 or 0), sub and SUBSECTION_H or SECTION_H)
    SetListFont(s._label, sub and 10 or 11)
    SetListFont(s._count, 10)
    s._label:SetTextColor(sub and 0.55 or 0.7, sub and 0.55 or 0.7, sub and 0.55 or 0.7)
    s._label:SetText(label)
    s._count:SetText(count)
    s._key, s._sub = key, sub
    local collapsed = (BP().bagListCollapsed or _emptyP)[key] == true
    -- Arrow points right when collapsed, down when open
    s._arrow:SetRotation(collapsed and math.pi or math.pi / 2)
    if s._clearBtn then
        s._clearBtn:Hide()
        s._line:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    end
    s:Show()
    return sub and SUBSECTION_H or SECTION_H, collapsed
end

-- items: the already-filtered display list. Returns the content height.
-- opts: rowW, startX, leftX (scroll frame left), topY (header bar top),
-- allItems (All Items view: honour Hide in All Items), pinned (pinned set:
-- duplicate pinned items into a Pinned section at the top), slotView ("one" =
-- OneBag, "multi" = MultiBag: bag sections in slot order like the grid),
-- recent (recent itemID set: Recent section in slot views), emptySlots (slot
-- views: empty slots as rows; nil while searching).
function ns.RenderListView(items, opts)
    local child = EUI_Bags._scrollChild
    local cats = EUI_CategoryManager:GetCategories()
    local hidden = opts.allItems and BP().bagHiddenInAllItems or _emptyP
    local rowW = opts.rowW

    -- Bucket: section key (category index, "pinned" or "junk") -> sub label -> items.
    -- Slot views key sections by bag ID (0-5), or "main" for OneBag's bags 0-4.
    local slotView = opts.slotView
    local junkLabel = L("Junk")
    local buckets, order = {}, {}
    local function GetBucket(key)
        local b = buckets[key]
        if not b then
            b = { key = key, subs = {}, subList = {}, n = 0, sell = 0 }
            buckets[key] = b
            order[#order + 1] = b
        end
        return b
    end
    local function Add(key, sub, d)
        local b = GetBucket(key)
        local sl = b.subs[sub]
        if not sl then
            sl = { label = sub }
            b.subs[sub] = sl
            b.subList[#b.subList + 1] = sl
        end
        sl[#sl + 1] = d
        b.n = b.n + 1
        b.sell = b.sell + d._lvSell
    end
    -- OneBag: a WoW Forever special bag (ns.SpecialBags) keeps a section of
    -- its own, as the reagent bag does, after Main Bags.
    local special = slotView == "one" and ns.SpecialBags() or nil
    local function BagKey(bag)
        if slotView == "one" and bag ~= 5 and not (special and special[bag]) then return "main" end
        return bag
    end
    local pinnedSet, recentSet = opts.pinned, opts.recent
    if not slotView and BP().bagListMergeDuplicates == true then
        items = ns.MergeDuplicates(items, true)
    end
    for _, d in ipairs(items) do
        local ci = d.categoryIndex
        local cat = ci and cats[ci]
        if d.info and d.itemLink then
            StampItem(d)
            if pinnedSet and ns.IsItemPinned(pinnedSet, d.itemLink, d.info.itemID) then
                Add("pinned", "", d)
            end
            if recentSet and recentSet[d.info.itemID] then
                Add("recent", "", d)
            end
            if slotView then
                Add(BagKey(d.bag), "", d)
            elseif cat and not hidden[cat._defaultName] and not (cat.groupName and hidden[cat.groupName]) then
                local key = d._lvQuality == 0 and "junk" or ci
                Add(key, key == "junk" and "" or d._lvSub, d)
            end
        end
    end
    if slotView and opts.emptySlots then
        for _, d in ipairs(opts.emptySlots) do
            local b = GetBucket(BagKey(d.bag))
            local sl = b.subs[""]
            if not sl then
                sl = { label = "" }
                b.subs[""] = sl
                b.subList[1] = sl
            end
            sl[#sl + 1] = d
        end
    end
    -- Pinned first, category (or bag) order, Junk last
    local RANK = { pinned = -2, recent = -1, main = 0, junk = math.huge }
    table.sort(order, function(a, b)
        return (RANK[a.key] or a.key) < (RANK[b.key] or b.key)
    end)
    local pinnedLabel, recentLabel = L("Pinned Items"), L("Recent Items")
    for _, c in ipairs(cats) do
        if c.isPinned then pinnedLabel = c.name end
        if c.isRecent then recentLabel = c.name end
    end


    ns.ListSortSetup()
    local rowCompare = slotView and SlotCompare or ListCompare
    local cols = LayoutColumns(rowW)
    ns.UpdateListHeaderBar(EUI_Bags, cols, opts.leftX, opts.topY, opts.startX, slotView ~= nil)

    for _, s in ipairs(_sections) do s:Hide() end
    _sectionsUsed, _rowsUsed = 0, 0
    local x, y = opts.startX, -4
    local showValue = BP().bagListSectionValue == true
    local rowH = RowH()

    -- Same warning the OneBag / MultiBag grid shows
    local warn = slotView and not BP().bagHideOneBagWarning
    if warn then
        if not _warn then
            _warn = child:CreateFontString(nil, "OVERLAY")
            ns.SetBagFont(_warn, 9)
            _warn:SetTextColor(0.5, 0.5, 0.5, 0.9)
            _warn:SetJustifyH("CENTER")
        end
        _warn:ClearAllPoints()
        _warn:SetPoint("TOP", child, "TOP", 0, y - 5)
        _warn:SetText(slotView == "multi"
            and L("Changes made in MultiBag will affect the positions of items in default Blizzard bags")
            or L("Changes made in OneBag will affect the positions of items in default Blizzard bags"))
        y = y - 24
    end
    if _warn then _warn:SetShown(warn) end
    for _, b in ipairs(order) do
        local label, secKey, count
        if b.key == "junk" then label, secKey = junkLabel, "junk"
        elseif b.key == "pinned" then label, secKey = pinnedLabel, "pinned"
        elseif b.key == "recent" then label, secKey = recentLabel, "recent"
        elseif b.key == "main" then
            local total = 0
            for bag = 0, 4 do
                if not (special and special[bag]) then total = total + C_Container.GetContainerNumSlots(bag) end
            end
            label, secKey = L("Main Bags"), "bagmain"
            count = "(" .. b.n .. " / " .. total .. ")"
        elseif slotView then
            label, secKey = ns.BagDisplayName(b.key), "bag" .. b.key
            count = "(" .. b.n .. " / " .. C_Container.GetContainerNumSlots(b.key) .. ")"
        else label, secKey = cats[b.key].name, cats[b.key]._defaultName end
        count = count or ("(" .. b.n .. ")")
        if showValue and b.sell > 0 then count = count .. "  " .. C_CurrencyInfo.GetCoinTextureString(b.sell) end
        local h, collapsed = PlaceSection(secKey, label, count, x, y, rowW, false)
        if secKey == "recent" and BP().bagShowRecentClear == true then
            local s = _sections[_sectionsUsed]
            s._line:SetPoint("RIGHT", ns.ShowRecentClearButton(s), "LEFT", -6, 0)
        end
        y = y - h
        table.sort(b.subList, SubCompare)
        for _, sl in ipairs(b.subList) do
            if collapsed then break end
            local subCollapsed
            if sl.label ~= "" then
                h, subCollapsed = PlaceSection(secKey .. "/" .. sl.label, sl.label, "(" .. #sl .. ")", x, y, rowW, true)
                y = y - h
            end
            if not subCollapsed then table.sort(sl, rowCompare) end
            for i, d in ipairs(subCollapsed and _emptyP or sl) do
                local btn = GetOrCreateRow(_rowsUsed + 1)
                if btn then  -- nil in combat (see GetOrCreateRow)
                    _rowsUsed = _rowsUsed + 1
                    btn:GetParent():SetParent(child)
                    if d.info then
                        RenderRow(btn, d, cols, rowW, x, y, i % 2 == 0)
                    else
                        RenderEmptyRow(btn, cols, d, rowW, x, y, i % 2 == 0)
                    end
                    y = y - rowH
                end
            end
        end
        y = y - 6
    end
    for i = _rowsUsed + 1, #_rows do _rows[i]:GetParent():Hide() end
    return math.abs(y) + 10, COLHDR_H
end
