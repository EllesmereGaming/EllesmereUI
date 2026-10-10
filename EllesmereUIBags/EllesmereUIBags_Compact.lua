if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_Compact.lua
--  Compact display (bagDisplayMode = "compact"; bank: bankCompactView): every
--  group is a block, a rectangle of whole cells with its icons row-major
--  inside it. Blocks sit side by side in bands, in group order and BLOCK_GAP
--  apart; a band is one label band (each block's name above its first
--  column) plus its tallest block's rows. CompactPack picks the bands and the
--  block widths: the least height, then the least awkward block shapes
--  within a grid row of that, then blocks widen into the band's spare width.
--  Shared by the bag window (the grid pass feeds its groups to the collector
--  below, then CompactBagsPlace draws them, with drop zones that assign or
--  pin a carried item) and the bank (RefreshBank re-places its layout entries
--  with CompactSegmentLayout + CompactPack).
--  At load this file only defines functions, constants and empty work tables:
--  frames and the pack output are made on the first compact pass, so the Grid
--  and List displays never build anything here.
-------------------------------------------------------------------------------
local ns = select(2, ...)
if not (ns and ns.GetSelection) then return end

local EUI = EllesmereUI
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min

local SLOT_SIZE, SPACING = ns.SLOT_SIZE, ns.SPACING
local PITCH = SLOT_SIZE + SPACING
-- Space between two blocks side by side, and the width it adds over plain
-- icon spacing
local BLOCK_GAP = 14
local GAP_EXTRA = BLOCK_GAP - SPACING
-- The fewest cells a block takes when another block follows it in its band;
-- a band's last block takes what it needs
local MID_MIN_CELLS = 3
-- Band height above the label font size; space a label leaves before the next block
local BAND_PAD, LABEL_PAD = 4, 6
-- Space between a label band and the icons under it (the labels keep their spot)
local LABEL_BELOW = 3
-- Recent Items' Clear link: its width plus a gap, and the label room it needs
local CLEAR_RESERVE, CLEAR_MIN_ROOM = 40, 80
-- A label's divider: its gap after the text, and the shortest one drawn
local LINE_GAP, LINE_MIN = 6, 12
-- A plan may be this many grid rows taller than the shortest one when its
-- blocks are less awkward
local LOOKS_ROWS = 1

local SetBagFont = ns.SetBagFont
local GetCatTitleSize = ns.GetCatTitleSize
local GetOrCreateSlot = ns.GetOrCreateSlot
local RenderButton = ns.RenderButton
local ShowRecentClearButton = ns.ShowRecentClearButton
local BuildSlotBuckets = ns.BuildSlotBuckets
local BuildExpansionBuckets = ns.BuildExpansionBuckets

-- Height of a label band for a label font size (default: the bags' Category Title Size)
function ns.CompactBandHeight(size)
    return (size or GetCatTitleSize()) + BAND_PAD
end

-- The bank display ("grid" | "list" | "compact") from the bank profile keys:
-- List View keeps its own switch and wins; bankCompactView adds Compact.
function ns.BankDisplayMode(p)
    if p.bankListView == true then return "list" end
    if p.bankCompactView == true then return "compact" end
    return "grid"
end

-------------------------------------------------------------------------------
--  Planner (pure: no game API; allocates nothing once its tables have grown)
-------------------------------------------------------------------------------
-- Output tables for CompactPack; the caller keeps one and reuses it. It also
-- holds that caller's plan memo, so the bag window and the bank never
-- replan for each other.
function ns.CompactNewOut()
    return {
        cellX = {}, cellY = {},                 -- per cell, in group order
        groupX = {}, groupY = {}, groupW = {},  -- per group: its block
        groupH = {}, groupCols = {}, groupBand = {}, labelRoom = {},
        bandTop = {}, bandH = {},               -- per band
        labelBand = 0,                          -- label band height used (0: no labels)
        -- Inputs of the last plan
        _mN = 0, _mColumns = 0, _mBandH = 0, _mLooks = 0, _mSize = {}, _mLabel = {},
        -- The last plan: per group its icon columns and block width in cells,
        -- per band its first and last group and its rows
        _pCols = {}, _pWidth = {}, _pBands = 0, _pFirst = {}, _pLast = {}, _pRows = {},
    }
end

-- The plan being made (planning is synchronous): cells and label cells per
-- group, the column count, the width a band may take (in BandWidth's units),
-- the label band height
local pSize, pColumns, pCap, pBand
local pLabel = {}
-- FitBand: each block's columns, and the widening offers in the order they go
local fbCols = {}
local offG, offCols, offGain, offCost = {}, {}, {}, {}
-- Plans kept to build on, as records: height, awkwardness, wrapped rows, the
-- first band's last group and rows, and the record of the plan after it
local rH, rA, rW, rJ, rK, rRest = {}, {}, {}, {}, {}, {}
-- The kept records for groups i..n: kept[keptAt[i]] .. kept[keptAt[i] + keptN[i] - 1]
local kept, keptAt, keptN = {}, {}, {}
-- Candidate plans for the current first group (candQ: height in half px),
-- and their sort order
local candH, candQ, candA, candW, candJ, candK, candRest, candOrd = {}, {}, {}, {}, {}, {}, {}, {}
local candN, candTop = 0, 0

-- Block width in cells for cols icon columns: at least its label cells, and
-- MID_MIN_CELLS unless it is its band's last block (last), at most the
-- column count
local function BlockW(g, cols, last)
    local w = pLabel[g]
    if cols > w then w = cols end
    if not last and w < MID_MIN_CELLS then w = MID_MIN_CELLS end
    if w > pColumns then w = pColumns end
    return w
end

-- Icon columns of a block held to k rows
local function BandCols(g, k)
    local s = pSize[g]
    if s <= k then return 1 end
    return ceil(s / k)
end

local function Rows(g, cols)
    local s = pSize[g]
    if s == 0 then return 0 end
    return ceil(s / cols)
end

-- 0..2: a block wider than 7 columns or needlessly narrow, and one whose
-- last row holds a single icon. A block with no icons is never awkward.
local function Awk(g, cols)
    local s = pSize[g]
    if s == 0 then return 0 end
    local a = 0
    if cols > 7 or cols < min(3, s) then a = 1 end
    if cols > 1 and s > cols and s % cols == 1 then a = a + 1 end
    return a
end

-- Width of the band i..j with every block held to k rows: its blocks' cells
-- at PITCH each and its gaps at GAP_EXTRA each (its px width plus SPACING)
local function BandWidth(i, j, k)
    local w = (j - i) * GAP_EXTRA
    for m = i, j do w = w + BlockW(m, BandCols(m, k), m == j) * PITCH end
    return w
end

-- The most rows of a block in the band i..j held to k rows
local function BandRows(i, j, k)
    local r = 0
    for m = i, j do
        local rows = Rows(m, BandCols(m, k))
        if rows > r then r = rows end
    end
    return r
end

-- Holds the band i..j to k rows, then spends its spare width widening
-- blocks. First the awkward ones: each block offers its narrowest wider
-- shape that is least awkward, and the offers go best awkwardness gain per
-- extra cell first (group order on ties) while the width lasts. Then the
-- rest fills the band: from its last block back, a block takes its narrowest
-- wider shape with fewer rows that is no more awkward, when it fits, round
-- after round while any block takes one. Widening never adds rows. Leaves
-- each block's columns in fbCols; returns the band's height and awkwardness.
local function FitBand(i, j, k)
    local w, offers = (j - i) * GAP_EXTRA, 0
    for m = i, j do
        local c = BandCols(m, k)
        fbCols[m] = c
        local last = m == j
        w = w + BlockW(m, c, last) * PITCH
        local now = Awk(m, c)
        local bestC, bestA = 0, now
        -- A block at 0 has nothing to gain, and none wider than 7 columns
        -- scores below 1
        for wider = c + 1, (now > 0) and min(pSize[m], pColumns) or 0 do
            if wider > 7 and bestA <= 1 then break end
            local a = Awk(m, wider)
            if a < bestA then
                bestC, bestA = wider, a
                if a == 0 then break end
            end
        end
        if bestC > 0 then
            local gain, cost = now - bestA, BlockW(m, bestC, last) - BlockW(m, c, last)
            offers = offers + 1
            local at = offers
            while at > 1 and cost * offGain[at - 1] < offCost[at - 1] * gain do
                offG[at], offCols[at], offGain[at], offCost[at] = offG[at - 1], offCols[at - 1], offGain[at - 1], offCost[at - 1]
                at = at - 1
            end
            offG[at], offCols[at], offGain[at], offCost[at] = m, bestC, gain, cost
        end
    end
    local spare = pCap - w
    for o = 1, offers do
        local cost = offCost[o] * PITCH
        if cost <= spare then
            spare = spare - cost
            fbCols[offG[o]] = offCols[o]
        end
    end
    local took = true
    while took do
        took = false
        for m = j, i, -1 do
            local c = fbCols[m]
            local rows, now = Rows(m, c), Awk(m, c)
            for wider = c + 1, min(pSize[m], pColumns) do
                -- None wider than 7 columns scores 0
                if wider > 7 and now == 0 then break end
                if Rows(m, wider) < rows and Awk(m, wider) <= now then
                    -- A block wider for its label (or the band's minimum)
                    -- takes its first columns free
                    local cost = (BlockW(m, wider, m == j) - BlockW(m, c, m == j)) * PITCH
                    if cost <= spare then
                        spare = spare - cost
                        fbCols[m] = wider
                        took = true
                    end
                    break
                end
            end
        end
    end
    local r, awk = 0, 0
    for m = i, j do
        local c = fbCols[m]
        local rows = Rows(m, c)
        if rows > r then r = rows end
        awk = awk + Awk(m, c)
    end
    return pBand + r * PITCH, awk
end

-- Adds the candidate plans that open with the band i..j held to k rows: one
-- per kept plan for the groups after it
local function Consider(i, j, k)
    local h, awk = FitBand(i, j, k)
    local at = keptAt[j + 1]
    for x = at, at + keptN[j + 1] - 1 do
        local r = kept[x]
        local total = h + rH[r]
        candN = candN + 1
        candH[candN], candQ[candN] = total, floor(total * 2 + 0.5)
        candA[candN], candW[candN] = awk + rA[r], (k - 1) + rW[r]
        candJ[candN], candK[candN], candRest[candN] = j, k, r
        candOrd[candN] = candN
    end
end

-- Least height first, then least awkward, then fewest wrapped rows, then the
-- order the candidates were made in
local function CandBefore(a, b)
    if candQ[a] ~= candQ[b] then return candQ[a] < candQ[b] end
    if candA[a] ~= candA[b] then return candA[a] < candA[b] end
    if candW[a] ~= candW[b] then return candW[a] < candW[b] end
    return a < b
end

-- Chooses the bands and block widths for groups 1..n by dynamic programming
-- from the last group back: a plan for groups i..n is a first band i..j held
-- to k rows, then a kept plan for groups j + 1..n. Each band tries the fewest
-- rows that fit and more rows while it grows by no more than LOOKS_ROWS;
-- each i keeps its shortest plan and every strictly less awkward one within
-- LOOKS_ROWS grid rows of it. The answer, the least awkward plan kept for
-- group 1, goes to out's plan fields.
local function Plan(n, out)
    -- The empty plan after the last group
    rH[1], rA[1], rW[1], rJ[1] = 0, 0, 0, false
    local rN, kN = 1, 1
    kept[1], keptAt[n + 1], keptN[n + 1] = 1, 1, 1
    local allowQ = 2 * LOOKS_ROWS * PITCH
    for i = n, 1, -1 do
        candN = 0
        -- before: the one-column width of groups i..j-1 as blocks with
        -- another after them, gaps included
        local kMin, kMax, before = 1, 1, -GAP_EXTRA
        for j = i, n do
            local s = pSize[j]
            local need = ceil(s / pColumns)
            if need > kMin then kMin = need end
            if s > kMax then kMax = s end
            -- Stop once even one-column blocks no longer fit (it only grows
            -- with j: the block that was last takes the band's minimum)
            if j > i and before + GAP_EXTRA + BlockW(j, 1, true) * PITCH > pCap then break end
            before = before + GAP_EXTRA + BlockW(j, 1) * PITCH
            -- The fewest rows that fit; a single group takes what full width
            -- needs (at kMax every block is one column wide, which fits here)
            local k = kMin
            if j > i then
                local hi = kMax
                while k < hi do
                    local mid = floor((k + hi) / 2)
                    if BandWidth(i, j, mid) <= pCap then hi = mid else k = mid + 1 end
                end
            end
            Consider(i, j, k)
            local rows = BandRows(i, j, k)
            for more = k + 1, kMax do
                if BandRows(i, j, more) > rows + LOOKS_ROWS then break end
                -- The same block shapes as at more - 1 only add longer copies
                -- of its plans
                local differs = false
                for m = i, j do
                    if BandCols(m, more) ~= BandCols(m, more - 1) then
                        differs = true
                        break
                    end
                end
                if differs then Consider(i, j, more) end
            end
        end
        for x = candN + 1, candTop do candOrd[x] = nil end
        candTop = candN
        table.sort(candOrd, CandBefore)
        local limit = candQ[candOrd[1]] + allowQ
        local first, lastA = kN + 1, nil
        for x = 1, candN do
            local c = candOrd[x]
            if candQ[c] > limit then break end
            if not lastA or candA[c] < lastA then
                lastA = candA[c]
                rN = rN + 1
                rH[rN], rA[rN], rW[rN] = candH[c], lastA, candW[c]
                rJ[rN], rK[rN], rRest[rN] = candJ[c], candK[c], candRest[c]
                kN = kN + 1
                kept[kN] = rN
            end
        end
        keptAt[i], keptN[i] = first, kN - first + 1
    end
    -- Unroll the answer band by band
    local pCols, pWidth, pFirst, pLast, pRows = out._pCols, out._pWidth, out._pFirst, out._pLast, out._pRows
    local r, i, nb = kept[keptAt[1] + keptN[1] - 1], 1, 0
    while rJ[r] do
        local j = rJ[r]
        FitBand(i, j, rK[r])
        nb = nb + 1
        pFirst[nb], pLast[nb] = i, j
        local most = 0
        for m = i, j do
            local c = fbCols[m]
            pCols[m], pWidth[m] = c, BlockW(m, c, m == j)
            local rows = Rows(m, c)
            if rows > most then most = rows end
        end
        pRows[nb] = most
        i, r = j + 1, rRest[r]
    end
    out._pBands = nb
end

-- Lays n groups out as blocks in bands (see the file header). size[g] =
-- cells of group g (0 = a label with no cells), labelW[g] = its label's text
-- width in px (0 = no label); with no label in the pass there are no label
-- bands. A block is at least its label wide, less the part of the gap after
-- it that the label may also use (keeping SPACING before the next block); a
-- band's last block lends its label as much past the right edge. x values
-- are px from the grid's left edge, y values child space (negative down)
-- from startY. The plan is memoised in out and made again only when an input
-- differs; positions follow startY on every call. Fills out (see
-- CompactNewOut; out.contentW: the px width the window gives the grid, see
-- below) and returns cells, bands, bottomY (6 px below the last band, like a
-- grid section end).
function ns.CompactPack(size, labelW, n, columns, bandH, startY, out)
    if n < 1 then
        out.contentW = nil
        return 0, 0, startY
    end
    if columns < 1 then columns = 1 end
    -- Memo inputs: the group count, each group's cells and label width
    -- (rounded up to whole px, which keeps every label cell count), columns,
    -- bandH and LOOKS_ROWS
    local mSize, mLabel = out._mSize, out._mLabel
    local same = out._mN == n and out._mColumns == columns and out._mBandH == bandH
        and out._mLooks == LOOKS_ROWS
    local band = 0
    for g = 1, n do
        local s, lw = size[g], ceil(labelW[g])
        if lw > 0 then band = bandH end
        if mSize[g] ~= s or mLabel[g] ~= lw then
            mSize[g], mLabel[g] = s, lw
            same = false
        end
    end
    -- The labels stay bandH tall at the band's top; the icons start below
    -- LABEL_BELOW more
    if band > 0 then band = band + LABEL_BELOW end
    if not same then
        out._mN, out._mColumns, out._mBandH, out._mLooks = n, columns, bandH, LOOKS_ROWS
        pSize, pColumns, pCap, pBand = mSize, columns, columns * PITCH, band
        for g = 1, n do pLabel[g] = max(1, ceil((mLabel[g] + 2 * SPACING - BLOCK_GAP) / PITCH)) end
        Plan(n, out)
    end

    out.labelBand = band
    local cellX, cellY = out.cellX, out.cellY
    local groupX, groupY, groupW, groupH = out.groupX, out.groupY, out.groupW, out.groupH
    local groupCols, groupBand, labelRoom = out.groupCols, out.groupBand, out.labelRoom
    local bandTop, bandHeight = out.bandTop, out.bandH
    local pCols, pWidth, pFirst, pLast, pRows = out._pCols, out._pWidth, out._pFirst, out._pLast, out._pRows
    local rightX = columns * PITCH - SPACING
    local y, ci, nb, widest = startY, 0, out._pBands, 0
    for b = 1, nb do
        local h = band + pRows[b] * PITCH
        bandTop[b], bandHeight[b] = y, h
        local last, x = pLast[b], 0
        for g = pFirst[b], last do
            local cols, s = pCols[g], size[g]
            local rows = (s > 0) and ceil(s / cols) or 0
            local w = pWidth[g] * PITCH - SPACING
            groupX[g], groupY[g] = x, y
            groupW[g], groupH[g] = w, band + rows * PITCH - SPACING
            groupCols[g], groupBand[g] = cols, b
            -- A label may run to the next block (less LABEL_PAD); the last
            -- one's room is set below, once the right edge is known
            if g < last then labelRoom[g] = w + BLOCK_GAP - LABEL_PAD end
            if g == last and x + w > widest then widest = x + w end
            local top = y - band
            for t = 0, s - 1 do
                local row = floor(t / cols)
                ci = ci + 1
                cellX[ci] = x + (t - row * cols) * PITCH
                cellY[ci] = top - row * PITCH
            end
            x = x + w + BLOCK_GAP
        end
        y = y - h
    end
    -- The right edge: the grid's, unless every band stops short of it by less
    -- than a cell -- a remainder no block can use, which would read as a
    -- missing slot -- where the window hugs the widest band instead
    -- (out.contentW, the width a grid of `columns` would have otherwise).
    -- A band's last label may run to that edge, or a gap past its block.
    local edge = rightX
    if nb > 0 and rightX - widest > 0 and rightX - widest < PITCH then edge = widest end
    out.contentW = edge + SPACING
    for b = 1, nb do
        local g = pLast[b]
        labelRoom[g] = max(edge - groupX[g], groupW[g] + BLOCK_GAP - LABEL_PAD)
    end
    return ci, nb, y - 6
end

-------------------------------------------------------------------------------
--  Bank layout segmentation (pure)
-------------------------------------------------------------------------------
-- Splits a bank layout (header and slot entries as RefreshBank's view builders
-- emit them) into compact groups and compacts it in place: each group keeps
-- one header entry, its label, followed by its slot entries. A group's label
-- joins the names (entry.name, else entry.label) of the headers that open it,
-- outermost first, the innermost by its counted label, entry.label ("Midnight:
-- Armor (8)"). A header with no slots under it is
-- dropped, unless the layout has no slot at all (it then stays as a label-only
-- group); slots before the first header form a group with no label.
-- Fills size[g], labelText[g] (string or false), labelEntry[g] (the kept
-- header entry or false) and returns the group count.
do
    local path = {}
    local function Join(lo, hi)
        local s
        for d = lo, hi do
            local p = path[d]
            if p then s = s and (s .. ": " .. p) or p end
        end
        return s or false
    end
    -- The chain's label, its innermost header by that header's counted label
    local function ChainLabel(lo, hi, last)
        local inner = path[hi]
        path[hi] = last.label or inner
        local s = Join(lo, hi)
        path[hi] = inner
        return s
    end

    function ns.CompactSegmentLayout(layout, size, labelText, labelEntry)
        local n, w, total = 0, 0, #layout
        local chainLast, freshMin, curDepth, maxDepth = nil, nil, 0, -1
        for i = 1, total do
            local e = layout[i]
            if e.isHeader then
                local d = e.depth or 0
                path[d] = e.name or e.label
                for k = d + 1, maxDepth do path[k] = nil end
                if d > maxDepth then maxDepth = d end
                if not freshMin or d < freshMin then freshMin = d end
                curDepth, chainLast = d, e
            else
                if chainLast then
                    n = n + 1
                    size[n], labelText[n], labelEntry[n] = 0, ChainLabel(freshMin, curDepth, chainLast), chainLast
                    w = w + 1; layout[w] = chainLast
                    chainLast, freshMin = nil, nil
                elseif n == 0 then
                    n = 1
                    size[1], labelText[1], labelEntry[1] = 0, false, false
                end
                size[n] = size[n] + 1
                w = w + 1; layout[w] = e
            end
        end
        if chainLast and n == 0 then
            n = 1
            size[1], labelText[1], labelEntry[1] = 0, ChainLabel(freshMin, curDepth, chainLast), chainLast
            w = 1; layout[1] = chainLast
        end
        for i = w + 1, total do layout[i] = nil end
        for d = 0, maxDepth do path[d] = nil end
        return n
    end
end

-------------------------------------------------------------------------------
--  Group labels (bags and bank): pooled plain frames
-------------------------------------------------------------------------------
-- A label is a frame the size of its room in the band: one left-aligned line
-- that ends in "..." when cut off, then a divider to its block's right edge.
-- Hovering a cut-off label shows the full name, and the hint when it has
-- one; clicks and item drops pass through to the window. Only the drawn text
-- takes the hover, and the tooltip centres over it (one reused anchor table).
local labelTipOpts = { anchorPoint = "BOTTOM", anchorTo = "TOPLEFT", anchorX = 0, anchorY = 4 }
local function LabelOnEnter(self)
    local tip = self._cut and self._text or nil
    if self._hint then tip = tip and (tip .. "\n" .. self._hint) or self._hint end
    if tip then
        labelTipOpts.anchorX = self._shownW / 2
        EUI.ShowWidgetTooltip(self, tip, labelTipOpts)
    end
end
local function LabelOnLeave()
    EUI.HideWidgetTooltip()
end

-- A label that takes mouse motion passes clicks and drops on (out of combat
-- only, so one made in combat takes no mouse until a later paint): ns.PassClicks
-- in EllesmereUIBags.lua.
local PassClicks = ns.PassClicks

function ns.CompactLabel(pool, idx, owner)
    local lf = pool[idx]
    if lf then return lf end
    lf = CreateFrame("Frame", nil, owner)
    local fs = lf:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT", lf, "LEFT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetMaxLines(1)
    fs:SetTextColor(0.7, 0.7, 0.7)
    lf._label = fs
    -- The divider: the Grid display's category header line (colour, alpha,
    -- one physical pixel thick)
    local line = lf:CreateTexture(nil, "ARTWORK")
    line:SetHeight(EUI.PP.mult)
    line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    line:Hide()
    lf._line = line
    lf:SetScript("OnEnter", LabelOnEnter)
    lf:SetScript("OnLeave", LabelOnLeave)
    -- After the scripts, which can turn mouse input on: the label never takes
    -- clicks, and CompactShowLabel turns motion on per paint
    lf:SetMouseClickEnabled(false)
    lf:SetMouseMotionEnabled(false)
    PassClicks(lf)
    lf:Hide()
    pool[idx] = lf
    return lf
end

-- Sets the label's font and text and returns the text's full width in px.
function ns.CompactMeasureLabel(lf, text, size)
    local fs = lf._label
    SetBagFont(fs, size)
    fs:SetText(text)
    lf._text = text
    return fs:GetUnboundedStringWidth() or 0
end

-- Places a measured label at (x, y) in parent: room px wide, bandH tall; the
-- text keeps reserveRight px free on the right (Recent Items' Clear link).
-- lineW: the block's width in px; a divider runs from the text end to there,
-- stopping before the reserved space, when at least LINE_MIN px remain
-- (nil: no divider).
function ns.CompactShowLabel(lf, parent, x, y, room, bandH, text, textW, hint, reserveRight, lineW)
    -- CompactMeasureLabel set the text this pass; only a caller showing other text re-sets it
    if lf._text ~= text then lf._label:SetText(text); lf._text = text end
    if room < 1 then room = 1 end
    reserveRight = reserveRight or 0
    local w = room - reserveRight
    if w < 1 then w = 1 end
    -- Blocks are sized so a label keeps SPACING before the next block, while
    -- its room keeps LABEL_PAD: a text over by no more than the difference
    -- still shows whole
    if textW > w and textW <= w + LABEL_PAD - SPACING then w = w + LABEL_PAD - SPACING end
    if lf:GetParent() ~= parent then lf:SetParent(parent) end
    lf:ClearAllPoints()
    lf:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lf:SetSize(room, bandH)
    lf._label:SetWidth(w)
    lf._cut = textW > w
    lf._hint = hint or nil
    -- Hover only for a cut-off name or a hint, and only over the drawn text
    local shownW = min(textW, w)
    lf._shownW = shownW
    lf:SetHitRectInsets(0, room - shownW, 0, 0)
    lf:SetMouseMotionEnabled((lf._cut or lf._hint ~= nil) and PassClicks(lf))
    local line = lf._line
    local lineX = (lf._cut and w or textW) + LINE_GAP
    local lineEnd = lineW and min(lineW, room - reserveRight) or 0
    if lineEnd - lineX >= LINE_MIN then
        line:ClearAllPoints()
        line:SetPoint("LEFT", lf, "LEFT", lineX, 0)
        line:SetWidth(lineEnd - lineX)
        line:Show()
    else
        line:Hide()
    end
    lf:Show()
end

function ns.CompactHideLabels(pool, from)
    for i = from, #pool do pool[i]:Hide() end
end

-------------------------------------------------------------------------------
--  Bag window: group collector (fed by the grid pass)
-------------------------------------------------------------------------------
-- A block's drop zone: none (false), the Pinned block's, or an assignable
-- category's
local ZONE_PIN, ZONE_ASSIGN = 1, 2

-- One pass's groups and cells, reused across passes (entries past the counts are stale)
local gN, cN = 0, 0
local gLabel, gHint, gInter, gClear, gSize, gW, gLi = {}, {}, {}, {}, {}, {}, {}
local gZone, gKey, gPlanW = {}, {}, {}
local cData = {}
-- A counted label per group index and what it was made from, so an
-- unchanged label makes no string
local lblA, lblB, lblN, lblText = {}, {}, {}, {}
local bagLabels = {}
local bagOut
-- Drop zones are never shown in OneBag / MultiBag (read once per pass)
local zonesOn = false

-- Group g's label: "<a>: <b> (<n>)", or "<b> (<n>)" when a is false
local function CountLabel(g, a, b, n)
    if lblA[g] == a and lblB[g] == b and lblN[g] == n then return lblText[g] end
    local text = a and (a .. ": " .. b .. " (" .. n .. ")") or (b .. " (" .. n .. ")")
    lblA[g], lblB[g], lblN[g], lblText[g] = a, b, n, text
    return text
end

local function AddGroup(label, hint, interactive, clear, zone, key)
    gN = gN + 1
    gLabel[gN] = (label and label ~= "") and label or false
    gHint[gN] = hint or false
    gInter[gN] = interactive and true or false
    gClear[gN] = clear and true or false
    gZone[gN] = zone or false
    gKey[gN] = key or false
    gSize[gN] = 0
end

local function AddCell(data)
    cN = cN + 1
    cData[cN] = data
    gSize[gN] = gSize[gN] + 1
end

-- Starts a pass: called by ns.RenderGridView right after its per-pass reset
function ns.CompactBagsBegin()
    gN, cN = 0, 0
    zonesOn = ns.GetSelection() >= 0
end

-- One grid section as compact groups. kind: "flat" | "slot" (armory slot
-- buckets) | "exp" (expansion buckets) | "pinned" | "recent". assignKey: the
-- category a drop zone over the section's blocks assigns to. keepEmpty: show
-- the name even with no cells. hint: a flat group's label tooltip line (the
-- single Pinned / Recent views).
-- A nested section becomes one group per bucket; the first is named
-- "<section>: <bucket>", the others by their bucket. Labels end in their
-- item count.
function ns.CompactBagsSection(name, items, kind, assignKey, keepEmpty, hint)
    local count = #items
    local pin = kind == "pinned"
    local zone = false
    if zonesOn then
        if pin then zone = ZONE_PIN elseif assignKey then zone = ZONE_ASSIGN end
    end
    if (kind == "slot" or kind == "exp") and count > 0 then
        local buckets = (kind == "slot") and BuildSlotBuckets(items) or BuildExpansionBuckets(items)
        local first = true
        for b = 1, #buckets do
            local bucket = buckets[b]
            local bItems = bucket.items
            local bn = #bItems
            if bn > 0 then
                AddGroup(CountLabel(gN + 1, first and name, bucket.label, bn), false, false, false, zone, assignKey)
                for j = 1, bn do AddCell(bItems[j]) end
                first = false
            end
        end
        if not first then return end
    end
    local clear = false
    hint = hint or false
    if pin or kind == "recent" then
        hint = pin and EllesmereUI.L("Middle Click to Add or Remove")
            or EllesmereUI.L("Extra quickview display, your items are also in their category")
        local recent = EUI_Bags._recentItems
        clear = not pin and BP().bagShowRecentClear == true and recent ~= nil and next(recent) ~= nil
    end
    -- An empty section is dropped, but the Pinned block and an assignable
    -- category stay as a label-only block (a drop target)
    if count == 0 and not pin and not assignKey and not keepEmpty then return end
    AddGroup(name ~= "" and CountLabel(gN + 1, false, name, count) or false, hint, false, clear, zone, assignKey)
    for j = 1, count do AddCell(items[j]) end
end

-- One OneBag / MultiBag / Reagent Bag section: slots in bag order, empty
-- slots included and mouse-enabled (drop targets)
function ns.CompactBagsSlots(label, slots)
    local count = #slots
    if count == 0 then return end
    AddGroup(label, false, true, false, false, false)
    for j = 1, count do AddCell(slots[j]) end
end

-------------------------------------------------------------------------------
--  Bag window: drop zones
-------------------------------------------------------------------------------
-- While the cursor holds an item, a pooled "+" button of ours covers every
-- block it can go to: the Pinned block (pins it) and each assignable
-- category's blocks (assigns it there), as the Grid display's "+" cells do.
-- A category whose blocks already hold the item keeps no zone (Pinned: an
-- item already pinned), so a drop on its own category still reaches the item
-- buttons (stack merges, swaps); a nested section's blocks count as one.
-- The zones register no events: the bag window's cursor watch (StartAddon,
-- registered only while the window shows) calls ns.CompactZonesSync on every
-- cursor change and on every lock change under a held item.
local zones = {}
local zoneN = 0                         -- zones placed by the last pass
local zoneItem, zoneItemKey = {}, {}    -- item IDs in the last pass's assign blocks, and their category
local zoneItemN = 0
local zoneHeld = {}                     -- categories whose blocks hold the cursor item
local zoneHooks = false                 -- the window's show / hide hooks, installed with the first zone
local zoneDirty = true                  -- zones placed, or the window shown, since the last sync
-- The cursor item the zones were last synced to, its link, and whether it
-- came from outside the bags
local syncedID, syncedLink, syncedExt

-- Shows each placed zone that takes the cursor item, hides the others
local function SyncZones()
    if zoneN == 0 then return end
    local cursorType, itemID, link = GetCursorInfo()
    if cursorType ~= "item" or not itemID then itemID, link = nil, nil end
    -- An item from outside the bags (bank, mail) still lands where it is
    -- dropped: no zone takes it (the drop target's bag scan in StartAddon,
    -- cached until the cursor or an item lock changes)
    local ext = itemID and ns.CursorItemExternalCached() or false
    -- Memo inputs: the cursor item, its link and ext, and zoneDirty for the
    -- zones and their blocks (pins and assignments refresh, which places the
    -- zones again)
    if not zoneDirty and itemID == syncedID and link == syncedLink and ext == syncedExt then return end
    zoneDirty, syncedID, syncedLink, syncedExt = false, itemID, link, ext
    if ext then itemID = nil end
    local pinned = false
    if itemID then
        wipe(zoneHeld)
        for i = 1, zoneItemN do
            if zoneItem[i] == itemID then zoneHeld[zoneItemKey[i]] = true end
        end
        pinned = ns.IsItemPinned(EllesmereUIDB.bagPinnedItems, link, itemID) and true or false
    end
    for i = 1, zoneN do
        local z = zones[i]
        local show = false
        if itemID then
            if z._pin then show = not pinned else show = not zoneHeld[z._key] end
        end
        if not show then ns.EndPlusHover(z) end
        z:SetShown(show)
    end
end
-- Called by the bag window's cursor watch (StartAddon)
ns.CompactZonesSync = SyncZones

local function ZoneDrop(self)
    if self._pin then ns.PinCursorItem() else ns.AssignCursorItem(self._key) end
end

local function ZonesWindowShown()
    zoneDirty = true
    SyncZones()
end

local function ZonesWindowHidden()
    for i = 1, zoneN do
        local z = zones[i]
        ns.EndPlusHover(z)
        z:Hide()
    end
    zoneDirty = true
end

local function GetZone(i)
    local z = zones[i]
    if z then return z end
    z = ns.CreatePlusButton(EUI_Bags, nil)
    z:SetScript("OnReceiveDrag", ZoneDrop)
    z:SetScript("OnClick", ZoneDrop)
    z:Hide()
    zones[i] = z
    if not zoneHooks then
        -- Installed after StartAddon's hooks, whose show hook marks the
        -- drop target's cache stale before ZonesWindowShown reads it
        zoneHooks = true
        EUI_Bags:HookScript("OnShow", ZonesWindowShown)
        EUI_Bags:HookScript("OnHide", ZonesWindowHidden)
    end
    return z
end

-- Places the pass's zones over their blocks (label band and icons), hides
-- the unused rest of the pool, then syncs them
local function PlaceZones(child, startX, out, n)
    local zn, zin, ci = 0, 0, 0
    for g = 1, n do
        local s, kind = gSize[g], gZone[g]
        if kind then
            zn = zn + 1
            local z = GetZone(zn)
            local h = out.groupH[g]
            -- A block with no icons also takes the empty space below its
            -- label, down to its band's bottom
            if s == 0 then h = max(out.bandH[out.groupBand[g]] - SPACING, out.labelBand) end
            if z:GetParent() ~= child then z:SetParent(child) end
            -- Above the item buttons and their overlays
            z:SetFrameLevel(child:GetFrameLevel() + 20)
            z:ClearAllPoints()
            z:SetPoint("TOPLEFT", child, "TOPLEFT", startX + out.groupX[g], out.groupY[g])
            z:SetSize(out.groupW[g], h)
            local pin = kind == ZONE_PIN
            z._pin, z._key = pin, gKey[g]
            z._plusTip = pin and ns.PIN_PLUS_TIP or ns.ASSIGN_PLUS_TIP
            if not pin then
                -- Plain item IDs: the item tables are recycled by the next refresh
                local key = gKey[g]
                for c = ci + 1, ci + s do
                    local info = cData[c].info
                    zin = zin + 1
                    zoneItem[zin], zoneItemKey[zin] = info and info.itemID or false, key
                end
            end
        end
        ci = ci + s
    end
    for i = zn + 1, #zones do
        local z = zones[i]
        if z:IsShown() then
            ns.EndPlusHover(z)
            z:Hide()
        end
    end
    zoneN, zoneItemN, zoneDirty = zn, zin, true
    SyncZones()
end

-------------------------------------------------------------------------------
--  Bag window: placement
-------------------------------------------------------------------------------
-- The px width the last pass's layout gives the grid (CompactPack's
-- out.contentW), or nil for the grid's own width.
function ns.CompactBagsContentW()
    return bagOut and bagOut.contentW
end

-- Lays out and draws the pass's groups from startY down, then their drop
-- zones; returns the advanced slotIdx and the content bottom (curY)
function ns.CompactBagsPlace(child, startX, startY, columns, slotIdx)
    local n = gN
    local size = GetCatTitleSize()
    local k = 0
    for g = 1, n do
        local text = gLabel[g]
        if text then
            k = k + 1
            local w = ns.CompactMeasureLabel(ns.CompactLabel(bagLabels, k, EUI_Bags), text, size)
            gW[g], gLi[g] = w, k
            -- Recent Items' Clear link is planned into its block's width
            gPlanW[g] = gClear[g] and (w + CLEAR_RESERVE) or w
        else
            gW[g], gLi[g], gPlanW[g] = 0, false, 0
        end
    end
    ns.CompactHideLabels(bagLabels, k + 1)
    if n == 0 then
        if bagOut then bagOut.contentW = nil end
        PlaceZones(child, startX, nil, 0)
        return slotIdx, startY
    end

    if not bagOut then bagOut = ns.CompactNewOut() end
    local out = bagOut
    local bandH = size + BAND_PAD
    local _, _, bottomY = ns.CompactPack(gSize, gPlanW, n, columns, bandH, startY, out)
    local groupX, groupY, groupW = out.groupX, out.groupY, out.groupW

    for g = 1, n do
        local li = gLi[g]
        if li then
            local lf = bagLabels[li]
            local room = out.labelRoom[g]
            local clear = gClear[g] and room >= CLEAR_MIN_ROOM
            ns.CompactShowLabel(lf, child, startX + groupX[g], groupY[g], room, bandH,
                gLabel[g], gW[g], gHint[g] or nil, clear and CLEAR_RESERVE or 0, groupW[g])
            if clear then
                ShowRecentClearButton(lf, nil)
                lf._clearBtn:SetHeight(bandH)  -- inside the band, never over the icons below
            elseif lf._clearBtn then
                lf._clearBtn:Hide()
            end
        end
    end

    local cellX, cellY = out.cellX, out.cellY
    local ci = 0
    for g = 1, n do
        local interactive = gInter[g]
        for _ = 1, gSize[g] do
            ci = ci + 1
            slotIdx = slotIdx + 1
            -- nil in combat past the pre-warmed pool: the cell stays empty
            -- until PLAYER_REGEN_ENABLED replays the refresh
            local btn = GetOrCreateSlot(slotIdx)
            if btn then
                btn:GetParent():SetParent(child)
                RenderButton(btn, cData[ci], slotIdx, 0, 0, startX + cellX[ci], cellY[ci], columns, interactive)
            end
        end
    end
    PlaceZones(child, startX, out, n)
    return slotIdx, bottomY
end
