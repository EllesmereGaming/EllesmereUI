-- Stub harness: the Action Bars count text alpha (EllesmereUIActionBars.lua,
-- ns._EABZeroCountAlpha) and its re-apply (EUI_ActionBars_Apply.lua,
-- EAB:RefreshCountVisibility). Cuts the real blocks out of the files and drives
-- them over a stubbed C_ActionBar: a bar's Charge Numbers settings
-- (hideChargeCount / hideStackCount / hideItemCount) hide the count of their
-- kind, following Blizzard's count (an item, consumable or stackable action
-- shows its item count; any other action its use count while above 0, else
-- its charges while it has more than one); unset, nothing is called and
-- nothing changes; a secret value is never compared, indexed or joined; and
-- Hide Count at 0 and Charge Numbers never undo each other.
--   lua .tools/tests/test_ab_count_visibility.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local MAIN = ReadSource("EllesmereUIActionBars/EllesmereUIActionBars.lua")
local a = assert(MAIN:find("\ndo -- Count text visibility\n", 1, true), "count visibility block missing")
local e = assert(MAIN:find("\nend -- Count text visibility\n", a + 1, true), "end of the count visibility block missing")
local COUNT_BLOCK = MAIN:sub(a + 1, e + #"\nend -- Count text visibility")

local APPLY = ReadSource("EllesmereUIActionBars/EUI_ActionBars_Apply.lua")
local ra = assert(APPLY:find("\nfunction EAB:RefreshCountVisibility(barKey)\n", 1, true), "RefreshCountVisibility missing")
local rmark = "\nfunction EAB:RefreshAllCounts()\n"
local rb = assert(APPLY:find(rmark, ra, true), "RefreshAllCounts missing")
local re = assert(APPLY:find("\nend\n", rb + #rmark - 1, true), "end of RefreshAllCounts missing")
local REFRESH_BLOCK = APPLY:sub(ra + 1, re + 4)

-------------------------------------------------------------------------------
-- A secret value: any index, join, ordering, arithmetic or call on it raises.
-- (Lua 5.1 cannot trap == against a plain value or a truth test; the code
-- under test guards with issecretvalue before either, which the paths below
-- would expose as a wrong alpha.)
-------------------------------------------------------------------------------
local SECRET = newproxy(true)
do
    local mt = getmetatable(SECRET)
    local function boom(what) return function() error("secret value " .. what, 2) end end
    mt.__index = boom("indexed")
    mt.__newindex = boom("written into")
    mt.__concat = boom("joined")
    mt.__lt = boom("compared")
    mt.__le = boom("compared")
    mt.__eq = boom("compared")
    mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__mod, mt.__pow, mt.__unm = boom("used in arithmetic"),
        boom("used in arithmetic"), boom("used in arithmetic"), boom("used in arithmetic"),
        boom("used in arithmetic"), boom("used in arithmetic"), boom("used in arithmetic")
    mt.__len = boom("measured")
    mt.__call = boom("called")
end
local function IsSecret(v) return rawequal(v, SECRET) end

-------------------------------------------------------------------------------
-- The world: actions by slot, the profile, buttons
-------------------------------------------------------------------------------
-- Action kinds: item (potion), reagent (a consumable spell), stack (a
-- stackable item), charge (2 charges), stacks (a spell showing its use
-- count), plain (a spell with neither).
local function NewWorld()
    local W = { calls = {}, act = {}, profile = { bars = { MainBar = {}, Bar2 = {}, StanceBar = {} } } }
    local function hit(name) W.calls[name] = (W.calls[name] or 0) + 1 end
    W.Calls = function()
        local n = 0
        for _, c in pairs(W.calls) do n = n + c end
        return n
    end
    local CA = {}
    function CA.IsItemAction(slot) hit("IsItemAction"); return W.act[slot].item and true or false end
    function CA.IsConsumableAction(slot) hit("IsConsumableAction"); return W.act[slot].consumable and true or false end
    function CA.IsStackableAction(slot) hit("IsStackableAction"); return W.act[slot].stackable and true or false end
    function CA.GetActionCharges(slot)
        hit("GetActionCharges")
        local x = W.act[slot]
        return { maxCharges = x.maxCharges or 0, currentCharges = x.currentCharges or 0, isActive = false }
    end
    function CA.GetActionUseCount(slot) hit("GetActionUseCount"); return W.act[slot].use or 0 end
    function CA.GetActionDisplayCount(slot)
        hit("GetActionDisplayCount")
        local x = W.act[slot]
        if x.display ~= nil then return x.display end
        if x.item or x.consumable or x.stackable then return tostring(x.use or 0) end
        if not IsSecret(x.use) and (x.use or 0) > 0 then return tostring(x.use) end
        if (x.maxCharges or 0) > 1 then return tostring(x.currentCharges) end
        return ""
    end
    W.CA = CA
    local env = setmetatable({
        C_ActionBar = CA,
        issecretvalue = IsSecret,
        HasAction = function(slot) return W.act[slot] ~= nil end,
        -- The zero rule's non-charge branch reads these globals.
        IsConsumableAction = function(slot) hit("g.IsConsumableAction"); return W.act[slot].consumable and true or false end,
        IsStackableAction = function(slot) hit("g.IsStackableAction"); return W.act[slot].stackable and true or false end,
        GetActionCount = function(slot) hit("g.GetActionCount"); return W.act[slot].use or 0 end,
    }, { __index = _G })
    env._G = env
    W.EAB = { db = { profile = W.profile } }
    W.ns = {}
    W.fds = setmetatable({}, { __mode = "k" })
    W.EFD = function(frame)
        local d = W.fds[frame]
        if not d then d = {}; W.fds[frame] = d end
        return d
    end
    local chunk = assert(loadstring("local EAB, ns = ...\n" .. COUNT_BLOCK, "=count visibility block"))
    setfenv(chunk, env)
    chunk(W.EAB, W.ns)
    W.Alpha = W.ns._EABZeroCountAlpha
    assert(type(W.Alpha) == "function", "the block must define ns._EABZeroCountAlpha")
    W.barButtons = {}
    local BAR_CONFIG = {
        { key = "MainBar" }, { key = "Bar2" }, { key = "StanceBar", isStance = true }, { key = "PetBar", isPetBar = true },
    }
    local rchunk = assert(loadstring("local EAB, ns, BAR_CONFIG, barButtons, EFD = ...\n" .. REFRESH_BLOCK, "=count refresh block"))
    setfenv(rchunk, env)
    rchunk(W.EAB, W.ns, BAR_CONFIG, W.barButtons, W.EFD)
    return W
end

local function NewFS()
    local fs = { alpha = 1, writes = 0 }
    function fs:SetAlpha(v)
        self.writes = self.writes + 1
        if IsSecret(v) then self.alpha = "secret" return end
        assert(type(v) == "number", "SetAlpha takes a number")
        self.alpha = v < 0 and 0 or (v > 1 and 1 or v)
    end
    return fs
end

-- A button on a bar: its EFD carries the bar key, as LayoutBar stamps it.
local function Button(W, barKey, slot)
    local b = { slot = slot, Count = NewFS() }
    function b:GetAttribute(name) if name == "action" then return self.slot end end
    W.EFD(b).barKey = barKey
    return b
end

local function Paint(W, b)
    local slot = b.slot
    W.Alpha(W.EFD(b), b.Count, W.CA.GetActionDisplayCount(slot), slot)
    return b.Count.alpha
end

local SLOTS = { item = 1, reagent = 2, stack = 3, charge = 4, stacks = 5, plain = 6, chargeStacks = 7, itemCharges = 8, chargeOne = 9 }
local function Seed(W)
    W.act[SLOTS.item] = { item = true, consumable = true, use = 3 }
    W.act[SLOTS.reagent] = { consumable = true, use = 12 }
    W.act[SLOTS.stack] = { item = true, stackable = true, use = 20 }
    W.act[SLOTS.charge] = { maxCharges = 2, currentCharges = 2, use = 0 }
    W.act[SLOTS.stacks] = { maxCharges = 1, currentCharges = 1, use = 4 }
    W.act[SLOTS.plain] = { maxCharges = 1, currentCharges = 1, use = 0 }
    W.act[SLOTS.chargeStacks] = { maxCharges = 3, currentCharges = 1, use = 2 }
    W.act[SLOTS.itemCharges] = { item = true, maxCharges = 3, currentCharges = 2, use = 0 }
    -- a charge spell showing a use count of exactly 1 (the use count wins from 1)
    W.act[SLOTS.chargeOne] = { maxCharges = 2, currentCharges = 2, use = 1 }
end

-------------------------------------------------------------------------------
-- 1. Nothing set: no API call, no alpha write, on every kind
-------------------------------------------------------------------------------
do
    local W = NewWorld(); Seed(W)
    for kind, slot in pairs(SLOTS) do
        local b = Button(W, "MainBar", slot)
        W.calls = {}
        local fd = W.EFD(b)
        W.Alpha(fd, b.Count, "3", slot)
        assert(W.Calls() == 0, "unset: an API call on " .. kind)
        assert(b.Count.writes == 0 and fd._zeroCountAlpha == nil, "unset: the count alpha was written on " .. kind)
    end
    -- Another bar's setting changes nothing here, and costs no call either.
    W.profile.bars.Bar2.hideItemCount = true
    W.profile.bars.Bar2.hideChargeCount = true
    local b = Button(W, "MainBar", SLOTS.item)
    W.calls = {}
    W.Alpha(W.EFD(b), b.Count, "3", SLOTS.item)
    assert(W.Calls() == 0 and b.Count.writes == 0, "a setting of Bar2 reached a MainBar button")
    -- A button no bar stamped yet: shown, no call.
    local loose = { slot = SLOTS.item, Count = NewFS() }
    W.calls = {}
    W.Alpha(W.EFD(loose), loose.Count, "3", SLOTS.item)
    assert(W.Calls() == 0 and loose.Count.writes == 0, "a button with no bar key was touched")
end

-------------------------------------------------------------------------------
-- 2. Each kind, each hide flag: hidden exactly on its own kind
-------------------------------------------------------------------------------
-- expected[flag][kind] = alpha
local EXPECT = {
    hideItemCount   = { item = 0, reagent = 0, stack = 0, itemCharges = 0, charge = 1, stacks = 1, plain = 1, chargeStacks = 1, chargeOne = 1 },
    hideChargeCount = { item = 1, reagent = 1, stack = 1, itemCharges = 1, charge = 0, stacks = 1, plain = 1, chargeStacks = 1, chargeOne = 1 },
    hideStackCount  = { item = 1, reagent = 1, stack = 1, itemCharges = 1, charge = 1, stacks = 0, plain = 0, chargeStacks = 0, chargeOne = 0 },
}
for flag, byKind in pairs(EXPECT) do
    for kind, want in pairs(byKind) do
        local W = NewWorld(); Seed(W)
        W.profile.bars.MainBar[flag] = true
        local b = Button(W, "MainBar", SLOTS[kind])
        local got = Paint(W, b)
        assert(got == want, ("%s on %s: alpha %s, want %s"):format(flag, kind, tostring(got), tostring(want)))
        -- The setting is per bar: the same action on Bar2 shows.
        local b2 = Button(W, "Bar2", SLOTS[kind])
        assert(Paint(W, b2) == 1, flag .. " on Bar2's " .. kind)
    end
end

-- Charges and Stacks both hidden: every non-item count hides with no charge
-- or use count read; an item keeps its count.
do
    local W = NewWorld(); Seed(W)
    W.profile.bars.MainBar.hideChargeCount = true
    W.profile.bars.MainBar.hideStackCount = true
    for _, kind in ipairs({ "charge", "stacks", "plain", "chargeStacks" }) do
        local b = Button(W, "MainBar", SLOTS[kind])
        W.calls = {}
        assert(Paint(W, b) == 0, "Charges + Stacks hidden: " .. kind .. " shows")
        assert(not W.calls.GetActionCharges and not W.calls.GetActionUseCount, "a needless read on " .. kind)
    end
    assert(Paint(W, Button(W, "MainBar", SLOTS.item)) == 1, "Charges + Stacks hidden hid an item count")
end

-- Item Count hidden alone reads no charge or use count.
do
    local W = NewWorld(); Seed(W)
    W.profile.bars.MainBar.hideItemCount = true
    local b = Button(W, "MainBar", SLOTS.charge)
    W.calls = {}
    Paint(W, b)
    assert(not W.calls.GetActionCharges and not W.calls.GetActionUseCount, "Item Count alone read a spell's counts")
end

-------------------------------------------------------------------------------
-- 3. Secret values
-------------------------------------------------------------------------------
-- A charge spell whose use count is secret: Charges hidden rides the secret
-- as the alpha (hidden while it reads 0); Stacks hidden shows (fails open).
do
    local W = NewWorld(); Seed(W)
    W.act[SLOTS.charge].use = SECRET
    W.act[SLOTS.charge].display = SECRET
    W.profile.bars.MainBar.hideChargeCount = true
    local b = Button(W, "MainBar", SLOTS.charge)
    assert(Paint(W, b) == "secret", "Charges hidden must hand the secret use count to SetAlpha")
    assert(W.EFD(b)._zeroCountAlpha == false, "a secret write must stamp the memo false")
    W.profile.bars.MainBar.hideChargeCount = nil
    W.profile.bars.MainBar.hideStackCount = true
    local b2 = Button(W, "MainBar", SLOTS.charge)
    assert(Paint(W, b2) == 1 and b2.Count.writes == 0, "Stacks hidden on a secret use count must show the count")
    -- Charges and Stacks both hidden: no read at all, hidden.
    W.profile.bars.MainBar.hideChargeCount = true
    assert(Paint(W, Button(W, "MainBar", SLOTS.charge)) == 0, "both hidden on a secret charge spell")
end

-- A secret display string and secret current charges reach the zero rule
-- untouched (the zero rule writes the secret count through).
do
    local W = NewWorld(); Seed(W)
    W.profile.hideZeroCount = true
    W.act[SLOTS.charge].currentCharges = SECRET
    W.act[SLOTS.charge].display = SECRET
    W.profile.bars.MainBar.hideItemCount = true -- set, but not this kind
    local b = Button(W, "MainBar", SLOTS.charge)
    assert(Paint(W, b) == "secret" and W.EFD(b)._zeroCountAlpha == false, "the zero rule's secret write")
    -- an item with a secret display: Item Count hidden needs no read of it
    W.act[SLOTS.item].display = SECRET
    W.act[SLOTS.item].use = SECRET
    assert(Paint(W, Button(W, "MainBar", SLOTS.item)) == 0, "Item Count hidden on a secret item count")
end

-------------------------------------------------------------------------------
-- 4. Hide Count at 0 and Charge Numbers, both ways
-------------------------------------------------------------------------------
do
    local W = NewWorld(); Seed(W)
    local mb = W.profile.bars.MainBar
    -- zero rule on, a charge spell with charges: shown; Charges hidden wins
    W.profile.hideZeroCount = true
    local b = Button(W, "MainBar", SLOTS.charge)
    assert(Paint(W, b) == 1, "zero rule on, 2 charges")
    mb.hideChargeCount = true
    assert(Paint(W, b) == 0, "Charges hidden must win over a shown zero rule")
    -- unhidden again: the zero rule takes it back at once
    mb.hideChargeCount = nil
    assert(Paint(W, b) == 1, "the zero rule did not take the count back")
    -- zero rule hides a 0 count; a hidden OTHER kind leaves that alone
    W.act[SLOTS.charge].currentCharges = 0
    assert(Paint(W, b) == 0, "zero rule on, 0 charges")
    mb.hideItemCount = true
    assert(Paint(W, b) == 0, "Item Count hidden undid the zero rule's hide")
    mb.hideItemCount = nil
    -- zero rule off, a hidden kind still hides (the off fast path never heals it)
    W.profile.hideZeroCount = nil
    W.act[SLOTS.charge].currentCharges = 2
    mb.hideChargeCount = true
    assert(Paint(W, b) == 0, "Charges hidden with the zero rule off")
    assert(Paint(W, b) == 0, "the zero rule's off path healed a hidden kind")
    -- the kind shown again, zero rule off: healed to 1
    mb.hideChargeCount = nil
    assert(Paint(W, b) == 1, "the off path must heal a count Charge Numbers hid")
    -- a secret written by the gate, then everything off: healed to 1
    W.act[SLOTS.charge].use = SECRET
    mb.hideChargeCount = true
    assert(Paint(W, b) == "secret", "gate write")
    mb.hideChargeCount = nil
    W.act[SLOTS.charge].use = 0
    assert(Paint(W, b) == 1 and W.EFD(b)._zeroCountAlpha == 1, "the off path must heal a secret-written count")
    -- a secret written by the zero rule, then the zero rule off: healed to 1
    W.profile.hideZeroCount = true
    W.act[SLOTS.charge].currentCharges = SECRET
    assert(Paint(W, b) == "secret", "zero rule secret write")
    W.profile.hideZeroCount = nil
    W.act[SLOTS.charge].currentCharges = 2
    assert(Paint(W, b) == 1, "the off path must heal the zero rule's secret write")
    -- steady state: no repeated writes
    local n = b.Count.writes
    Paint(W, b); Paint(W, b)
    assert(b.Count.writes == n, "a steady count rewrote its alpha")
    mb.hideChargeCount = true
    Paint(W, b)
    local n2 = b.Count.writes
    Paint(W, b)
    assert(b.Count.writes == n2, "a steady hidden count rewrote its alpha")
end

-- A kind left to the zero rule reads the action's charges once: the zero
-- rule takes the charge info Charge Numbers already read.
do
    local W = NewWorld(); Seed(W)
    W.profile.hideZeroCount = true
    W.profile.bars.MainBar.hideStackCount = true
    W.act[SLOTS.charge].currentCharges = 0
    local b = Button(W, "MainBar", SLOTS.charge)
    W.calls = {}
    assert(Paint(W, b) == 0, "zero rule on a charge spell at 0 with Stacks hidden")
    assert(W.calls.GetActionCharges == 1, "the charges were read " .. tostring(W.calls.GetActionCharges) .. " times")
    W.act[SLOTS.charge].currentCharges = 2
    W.calls = {}
    assert(Paint(W, b) == 1 and W.calls.GetActionCharges == 1, "zero rule on a charge spell at 2")
    -- A plain spell with Stacks shown and Charges hidden: one read too.
    W.profile.bars.MainBar.hideStackCount = nil
    W.profile.bars.MainBar.hideChargeCount = true
    local p = Button(W, "MainBar", SLOTS.plain)
    W.calls = {}
    assert(Paint(W, p) == 1 and W.calls.GetActionCharges == 1, "a plain spell read its charges twice")
end

-------------------------------------------------------------------------------
-- 5. EAB:RefreshCountVisibility(barKey): that bar only, or every bar
-------------------------------------------------------------------------------
do
    local W = NewWorld(); Seed(W)
    local m1, m2 = Button(W, "MainBar", SLOTS.item), Button(W, "MainBar", SLOTS.charge)
    local b1 = Button(W, "Bar2", SLOTS.item)
    local st = Button(W, "StanceBar", SLOTS.item)
    W.barButtons.MainBar = { m1, m2 }
    W.barButtons.Bar2 = { b1 }
    W.barButtons.StanceBar = { st }
    W.profile.bars.MainBar.hideItemCount = true
    W.profile.bars.Bar2.hideItemCount = true
    W.profile.bars.StanceBar.hideItemCount = true
    W.EAB:RefreshCountVisibility("MainBar")
    assert(m1.Count.alpha == 0 and m2.Count.alpha == 1, "MainBar refresh")
    assert(b1.Count.writes == 0, "a MainBar refresh touched Bar2")
    W.EAB:RefreshCountVisibility()
    assert(b1.Count.alpha == 0, "a refresh of every bar missed Bar2")
    assert(st.Count.writes == 0, "the stance bar shows no counts and must be skipped")
    W.profile.bars.Bar2.hideItemCount = nil
    W.EAB:RefreshAllCounts()
    assert(b1.Count.alpha == 1, "RefreshAllCounts must refresh every bar")
    -- an empty slot is skipped
    local empty = Button(W, "MainBar", 99)
    W.barButtons.MainBar[3] = empty
    W.EAB:RefreshCountVisibility("MainBar")
    assert(empty.Count.writes == 0, "an empty slot was painted")
    -- a button no layout stamped yet takes its bar's key from the refresh
    local fresh = { slot = SLOTS.item, Count = NewFS() }
    function fresh:GetAttribute(name) if name == "action" then return self.slot end end
    W.barButtons.MainBar[4] = fresh
    W.EAB:RefreshCountVisibility("MainBar")
    assert(W.EFD(fresh).barKey == "MainBar" and fresh.Count.alpha == 0, "an unstamped button missed its bar's setting")
end

print("action bars count visibility harness: ok")
