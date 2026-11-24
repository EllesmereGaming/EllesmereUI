if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Hold.lua
--
--  Keep Layout While Taking Items Out: per window ("bags", "bank") state that
--  keeps group cells, label widths and order; only item-event passes hold.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local BP = I.BP
local wipe, pairs, ipairs = wipe, pairs, ipairs
local tinsert, ceil = table.insert, math.ceil

local OPTION_KEY = { bags = "bagHoldLayout", bank = "bankHoldLayout" }

-- A child's key is Key(parent, child). EUI's own key parts start with a byte below 32 (no name
-- has one): JUNK, OTHER (Other, or no group key), NAME, LABEL, GAP, EMPTY (bank Empty Slots)
local SEP = "\31"
local function Key(parentKey, childKey)
    return parentKey .. SEP .. childKey
end
local JUNK, OTHER, NAME, LABEL, GAP = "\26", "\27", "\28", "\29", "\30gap"
local EMPTY = Key("", "\30empty")

local states  -- win -> state, made on the first pass with the hold on
-- A site that sets a flag refreshes at once (BeginPass consumes it; Release leaves it alone)
local events = { bags = false, bank = false }   -- win -> the next pass comes from an item event (ns.Hold.events)
local active = { bags = false }  -- this bags pass records or holds (ns.Hold.active; the bank reads BankHold.on)
-- The List display never holds; it is latched until a reload
local function On(win)
    local key = OPTION_KEY[win]
    local p = BP()
    if p[key] ~= true then return false end
    if win == "bags" then return not EUI_Bags.IsListMode() end
    local bank = _G.EUI_BankFrame
    return not (bank and bank.IsListMode())
end

local function State(win)
    local s = states and states[win]
    if not s then
        if not states then states = {} end
        s = {
            started = false,    -- recording since the last reset
            held = false,       -- the current pass keeps the hold
            suspended = 0,      -- sorts running
            release = false,    -- a held group outgrew its cells
            maxQty = {},        -- itemID -> running max qty
            cells = {},         -- group key -> running max cells
            planW = {},         -- group key -> running max planned label width
            modes = {},         -- key -> value recorded at the hold's start
            order = {},         -- parent key -> array of child keys
            last = {},          -- bucket key -> its last bucket
            seen = {},          -- scratch for Merge
        }
        states[win] = s
    end
    return s
end

local function Reset(s)
    s.started, s.held, s.release = false, false, false
    wipe(s.maxQty); wipe(s.cells); wipe(s.planW); wipe(s.modes); wipe(s.last)
    for _, arr in pairs(s.order) do wipe(arr) end
end

-- totals: itemID -> count, nil when the hold is off (On); true: the pass holds
local function BeginPass(win, totals)
    local event = events[win]
    events[win] = false
    local s = states and states[win]
    if win == "bags" then active.bags = totals ~= nil end  -- the bank reads BankHold.on
    if totals == nil then
        if s and s.started then Reset(s) end
        return false
    end
    s = s or State(win)

    -- a sort's passes record but never hold
    local held = event and s.started and s.suspended == 0 and not s.release
    local maxQty = s.maxQty
    if held then
        for id, qty in pairs(totals) do
            if qty > (maxQty[id] or 0) then held = false; break end
        end
    end
    if not held then
        Reset(s)
        s.started = true
        for id, qty in pairs(totals) do maxQty[id] = qty end
    end
    s.held = held
    return held
end

local function Cells(win, key, current)
    local s = states and states[win]
    if not (s and s.started) then return current end
    local c = s.cells[key]
    if not c or current > c then
        s.cells[key] = current
        if s.held and current > (c or 0) then s.release = true end
        return current
    end
    return s.held and c or current
end

-- w plus a fixed reserve per digit of the label's count "(n)", so a lower count with wider
-- digits still fits (size: the font size; digits: room for at least that many)
local function LabelW(text, w, size, digits)
    local a, b = (text or ""):find("%(%d+%)$")
    if not a then return w end
    local n = b - a - 1
    return w + (digits and digits > n and digits or n) * ceil(0.35 * size)
end

-- A planned label width: while held, the one at the hold's start; else LabelW's, recorded
local function PlanW(win, key, w, text, size, digits)
    local s = states and states[win]
    if not (s and s.started) then return w end
    local p = s.planW[key]
    if s.held and p then return p end
    w = LabelW(text, w, size, digits)
    if not p or w > p then s.planW[key] = w end
    return w
end

-- A per-group display mode (e.g. how a section nests; false: not drawn): while
-- held, the value at the hold's start, else value (recorded). n: the group's
-- item count; a group held as false that has items again gets value
local function Mode(win, key, value, n)
    local s = states and states[win]
    if not (s and s.started) then return value end
    local modes = s.modes
    if s.held then
        local v = modes[key]
        if v ~= nil then
            if v or not n or n == 0 then return v end
            return value
        end
    end
    modes[key] = value
    return value
end

local function Merge(win, parentKey, keys)
    local s = states and states[win]
    if not (s and s.started) then return keys end
    local arr = s.order[parentKey]
    if s.held and arr and #arr > 0 then
        local seen = s.seen
        wipe(seen)
        for _, k in ipairs(keys) do seen[k] = true end
        for i, k in ipairs(arr) do
            if not seen[k] then
                local n = #keys + 1
                tinsert(keys, i < n and i or n, k)
            end
        end
        wipe(seen)
    end
    if not arr then
        arr = {}
        s.order[parentKey] = arr
    end
    wipe(arr)
    for i, k in ipairs(keys) do arr[i] = k end
    return keys
end

local NONE = {}  -- the items of a held bucket that emptied (read only)

-- A section's buckets in held order, into out (may be buckets), and their keys (reused by the
-- next call): Key(parentKey, b[keyField] or b[keyField][subField]), keyField default sortKey.
-- An emptied held bucket comes back as its last bucket (fresh each pass) with NONE items.
local bucketKeys, bucketByKey
local function Buckets(win, parentKey, buckets, out, itemsField, keyField, subField)
    keyField = keyField or "sortKey"
    if not bucketKeys then bucketKeys, bucketByKey = {}, {} end
    wipe(bucketKeys); wipe(bucketByKey)
    local last = states[win].last
    for i, b in ipairs(buckets) do
        local id = b[keyField]
        if subField then id = id[subField] end
        local key = Key(parentKey, id)
        bucketKeys[i], bucketByKey[key], last[key] = key, b, b
    end
    Merge(win, parentKey, bucketKeys)
    for i = #bucketKeys + 1, #out do out[i] = nil end
    for i, key in ipairs(bucketKeys) do
        local b = bucketByKey[key]
        if not b then b = last[key]; b[itemsField] = NONE end
        out[i] = b
    end
    return out, bucketKeys
end

-- Ends the hold; returns whether the last pass held (the caller repaints)
local function Release(win)
    local s = states and states[win]
    if not s then return false end
    local was = s.held
    Reset(s)
    return was
end

-- Release after a held pass only (a recording is what the window shows)
local function ReleaseHeld(win)
    local s = states and states[win]
    if not (s and s.held) then return false end
    return Release(win)
end

-- A held group outgrew its cells (or force): release, true (lay out again)
local function ReleaseOutgrown(win, force)
    local s = states and states[win]
    if not (s and (s.release or force)) then return false end
    Release(win)
    return true
end

-- A sort starts: no pass holds until its EndSort (sorts overlap); true: a held layout ended
local function BeginSort(win)
    if not On(win) then return false end
    local s = State(win)
    s.suspended = s.suspended + 1
    return ReleaseHeld(win)
end

local function EndSort(win)
    local s = states and states[win]
    if s and s.suspended > 0 then s.suspended = s.suspended - 1 end
end

ns.Hold = {
    active = active, events = events,
    Key = Key, NONE = NONE, JUNK = JUNK, OTHER = OTHER, NAME = NAME, LABEL = LABEL, GAP = GAP, EMPTY = EMPTY,
    On = On, BeginPass = BeginPass,
    Cells = Cells, PlanW = PlanW, LabelW = LabelW, Mode = Mode, Buckets = Buckets,
    Release = Release, ReleaseHeld = ReleaseHeld, ReleaseOutgrown = ReleaseOutgrown,
    BeginSort = BeginSort, EndSort = EndSort,
}

I.broken = false
