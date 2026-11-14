-- Stub harness: Action Bars, the count text of an empty slot (EUI_ActionBars_Events.lua).
-- The forced button refresh (EAB_VTABLE.ForceButtonRefresh: button build at login, the reload
-- sweep, the infrequent full pass, a changed slot) wrote the client's display count to every
-- button, empty slots included. On WoW Forever that read is not blank for an empty slot, so
-- empty slots showed a food or water stack count after login until a hover ran Blizzard's own
-- update. The refresh now writes a blank on an empty slot and reads the count only for a
-- filled one, as Blizzard's update does. Checked here on the real functions, cut from the file:
--   the forced refresh: an empty slot's count is blank and never read, whatever the client
--     would answer; a filled slot keeps its count; a nil count heals to blank; a secret count
--     is written through and handed to the count alpha untouched; the slot is asked once;
--   the slot-changed refresh: an emptied slot ends blank with one write of its count, its
--     memos dropped; the assisted combat slot repaints its icon alone.
--   lua .tools/tests/test_ab_force_refresh_count.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource("EllesmereUIActionBars/EUI_ActionBars_Events.lua")

-- A secret value: indexing, joining, ordering, measuring or calling it raises. (Lua answers
-- `secret == nil` without asking the value, so the guard before that compare is counted instead.)
local SECRET = newproxy(true)
do
    local mt = getmetatable(SECRET)
    local function boom(what) return function() error("a secret value was " .. what, 2) end end
    mt.__index, mt.__newindex, mt.__concat = boom("indexed"), boom("written into"), boom("joined")
    mt.__lt, mt.__le, mt.__len, mt.__call = boom("compared"), boom("compared"), boom("measured"), boom("called")
end
local secretAsks = 0
local function issecretvalue(v) secretAsks = secretAsks + 1; return rawequal(v, SECRET) end

-- The client: slot -> { has, display = what GetActionDisplayCount answers, kind }.
--   1 empty, and the client answers a stack count for it (the WoW Forever report)
--   2 water, 5 left          3 filled, no count          4 filled, a secret count
--   5 empty, and the client answers a secret          6 the assisted combat slot
local WORLD = {
    [1] = { has = false, display = "20" },
    [2] = { has = true, display = "5" },
    [3] = { has = true, display = nil },
    [4] = { has = true, display = SECRET },
    [5] = { has = false, display = SECRET },
    [6] = { has = true, display = "9", kind = "assistedcombat" },
}
local reads, asked = {}, {}
local C_ActionBar = {
    GetActionDisplayCount = function(slot) reads[#reads + 1] = slot; return WORLD[slot].display end,
    UsesActionText = function() return false end,
    GetActionCooldown = function() return { isActive = false } end,
}
local function HasAction(slot) asked[#asked + 1] = slot; return WORLD[slot].has end
local function GetActionTexture(slot) return WORLD[slot].has and 1234 or nil end
local function GetActionInfo(slot) return "spell", 1, WORLD[slot].kind end

local FD = setmetatable({}, { __mode = "k" })
local function EFD(o) local t = FD[o]; if not t then t = {}; FD[o] = t end; return t end
local alphaSeen, attack, rings, borders = {}, 0, {}, 0
local ns = { _eabFD = FD }
function ns._TintUsableIcon() end
function ns._EABZeroCountAlpha(fd, fs, v, action) alphaSeen[action] = { v = v, fs = fs, fd = fd } end
function ns.AB_SyncAttackState() attack = attack + 1 end
function ns.AB_ClassicSlotRing(btn, filled) rings[#rings + 1] = filled end
function ns.AB_SyncEquippedBorder() borders = borders + 1 end
local EAB = { db = { profile = { showBlizzIconBg = true } } }
local EAB_VTABLE = {}

local HEAD = "local EAB_VTABLE, EAB, ns, EFD, HasAction, GetActionTexture, GetActionInfo, C_ActionBar, issecretvalue = ...\n"
assert(loadstring(HEAD .. Cut(SRC, "function EAB_VTABLE.ForceButtonRefresh(btn, action)", "\n-- ", "the forced refresh"), "=EUI_ActionBars_Events.lua"))(
    EAB_VTABLE, EAB, ns, EFD, HasAction, GetActionTexture, GetActionInfo, C_ActionBar, issecretvalue)
check(type(EAB_VTABLE.ForceButtonRefresh) == "function", "the forced refresh was not cut from the file")
assert(loadstring(HEAD .. Cut(SRC, "        ns._eabSlotRefreshBtn = function(btn, action)", "        -- The cast kick: ONE authoritative next-frame pass", "the slot refresh"),
    "=EUI_ActionBars_Events.lua"))(EAB_VTABLE, EAB, ns, EFD, HasAction, GetActionTexture, GetActionInfo, C_ActionBar, issecretvalue)
check(type(ns._eabSlotRefreshBtn) == "function", "the slot-changed refresh was not cut from the file")

local function NewButton(parts)
    local b = {}
    if not (parts and parts.noIcon) then
        b.icon = { shown = "unset" }
        function b.icon:SetTexture(tex) self.tex = tex end
        function b.icon:SetShown(v) self.shown = v end
        function b.icon:SetDesaturation() end
    end
    if not (parts and parts.noCount) then
        b.Count = { text = "stale", writes = 0 }
        function b.Count:SetText(t) self.text = t; self.writes = self.writes + 1 end
    end
    b.Name = { SetText = function() end }
    b.cooldown = { Clear = function() end }
    return b
end
local function Run(fn, btn, slot)
    local r0, a0, s0 = #reads, #asked, secretAsks
    alphaSeen[slot] = nil
    local ok, err = pcall(fn, btn, slot)
    check(ok, "slot " .. slot .. ": " .. tostring(err))
    return { read = #reads - r0, asked = #asked - a0, secretAsks = secretAsks - s0, alpha = alphaSeen[slot] }
end

-------------------------------------------------------------------------------
-- 1. the forced refresh
-------------------------------------------------------------------------------
do
    local Refresh = EAB_VTABLE.ForceButtonRefresh
    -- an empty slot the client answers a count for: blank, never read
    local b = NewButton()
    local r = Run(Refresh, b, 1)
    check(b.Count.text == "" and b.Count.writes == 1, "an empty slot's count is not written blank (" .. tostring(b.Count.text) .. ")")
    check(r.read == 0, "an empty slot's count was read from the client")
    check(r.alpha and r.alpha.v == "" and r.alpha.fs == b.Count and r.alpha.fd == EFD(b), "an empty slot does not hand the blank to the count alpha")
    check(b.icon.shown == false and b.icon.tex == nil, "an empty slot's icon is not hidden")
    check(r.asked == 1, "the slot was asked " .. r.asked .. " times in one refresh")
    -- an empty slot the client answers a secret for: the same
    b = NewButton()
    r = Run(Refresh, b, 5)
    check(b.Count.text == "" and r.read == 0 and r.alpha and r.alpha.v == "", "an empty slot with a secret client answer is not blank and unread")
    -- a filled slot keeps its count
    b = NewButton()
    r = Run(Refresh, b, 2)
    check(b.Count.text == "5" and r.read == 1 and r.alpha and r.alpha.v == "5", "a filled slot does not show its count (" .. tostring(b.Count.text) .. ")")
    check(b.icon.shown == true and b.icon.tex == 1234, "a filled slot's icon is not shown")
    check(r.asked == 1, "a filled slot was asked " .. r.asked .. " times in one refresh")
    check(r.secretAsks == 1, "a plain count was compared without asking whether it is secret first")
    -- a filled slot with no count heals to blank
    b = NewButton()
    r = Run(Refresh, b, 3)
    check(b.Count.text == "" and r.read == 1 and r.alpha and r.alpha.v == "", "a filled slot with no count is not blank (" .. tostring(b.Count.text) .. ")")
    -- a secret count is written through and handed on untouched
    b = NewButton()
    r = Run(Refresh, b, 4)
    check(rawequal(b.Count.text, SECRET), "a secret count is not written through")
    check(r.alpha and rawequal(r.alpha.v, SECRET), "a secret count is not handed to the count alpha")
    check(r.secretAsks == 1, "a secret count was not asked about before the compare")
    -- a button with no count text, and one with no icon
    b = NewButton({ noCount = true })
    r = Run(Refresh, b, 2)
    check(r.read == 0 and r.alpha == nil and b.icon.shown == true, "a button with no count text read a count")
    b = NewButton({ noIcon = true })
    r = Run(Refresh, b, 1)
    check(b.Count.text == "" and r.read == 0, "a button with no icon does not blank its empty slot's count")
    b = NewButton({ noIcon = true })
    r = Run(Refresh, b, 2)
    check(b.Count.text == "5", "a button with no icon does not show its count")
    -- no slot: nothing is asked or written
    b = NewButton()
    local a0 = #asked
    EAB_VTABLE.ForceButtonRefresh(b, nil)
    check(#asked == a0 and b.Count.text == "stale" and b.Count.writes == 0, "a button with no slot was refreshed")
end

-------------------------------------------------------------------------------
-- 2. the slot-changed refresh
-------------------------------------------------------------------------------
do
    local Slot = ns._eabSlotRefreshBtn
    -- a slot that was emptied (the item dragged off): blank, written once
    local b = NewButton()
    local fd = EFD(b)
    fd.lastCountText, fd.usableState = "20", "usable"
    local clip = { shown = "unset" }
    function clip:SetShown(v) self.shown = v end
    fd.iconBgClip, fd.classicArt = clip, true
    attack, rings, borders = 0, {}, 0
    local r = Run(Slot, b, 1)
    check(b.Count.text == "" and r.read == 0, "an emptied slot keeps a count (" .. tostring(b.Count.text) .. ")")
    check(b.Count.writes == 1, "an emptied slot's count was written " .. b.Count.writes .. " times")
    check(fd.lastCountText == nil and fd.usableState == nil, "a changed slot keeps its count or usable memo")
    check(clip.shown == true, "an emptied slot does not show the icon background")
    check(#rings == 1 and rings[1] == false, "an emptied slot's Classic WoW UI ring was not told the slot is empty")
    check(attack == 1 and borders == 1, "a changed slot's attack state or equipped border was not synced")
    -- the same button, filled again
    fd.lastCountText = "old"
    r = Run(Slot, b, 2)
    check(b.Count.text == "5" and b.Count.writes == 2, "a refilled slot does not show its count with one write")
    check(clip.shown == false and rings[2] == true and fd.lastCountText == nil, "a refilled slot keeps the empty slot's background, ring or memo")
    -- Blizzard's icon background switched off: an emptied slot shows none
    EAB.db.profile.showBlizzIconBg = false
    Run(Slot, b, 1)
    check(clip.shown == false, "an emptied slot shows the icon background while the option is off")
    EAB.db.profile.showBlizzIconBg = true
    -- a button with no per-button state: nothing is made for it
    local bare = NewButton()
    r = Run(Slot, bare, 1)
    check(bare.Count.text == "" and bare.Count.writes == 1, "a bare button's emptied slot is not blank with one write")
    -- the assisted combat slot repaints its icon alone
    local ab = NewButton()
    r = Run(Slot, ab, 6)
    check(ab.Count.text == "stale" and ab.Count.writes == 0 and r.read == 0, "the assisted combat slot's count was refreshed")
    check(ab.icon.tex == 1234 and ab.icon.shown == true, "the assisted combat slot's icon was not repainted")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_ab_force_refresh_count (%d checks)"):format(count))
