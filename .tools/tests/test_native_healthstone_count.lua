-- Run from the repository root: lua5.1 .tools/tests/test_native_healthstone_count.lua
local path = arg[1] or "EllesmereUICooldownManager/EUI_CDM_HookPresetCooldowns.lua"
local f = assert(io.open(path, "rb"))
local source = f:read("*a")
f:close()
local rf = assert(io.open("EllesmereUICooldownManager/EUI_CDM_HookReanchor.lua", "rb"))
local reanchor = rf:read("*a")
rf:close()

assert(reanchor:find('hooksecurefunc(frame, "RefreshSpellChargeInfo"', 1, true),
    "native Healthstone count is not restored after Blizzard refreshes charges")

local start = assert(source:find("function ns._ApplyNativeHealthstoneCount(frame)", 1, true),
    "native Healthstone count helper is missing")
local finish = assert(source:find("\n\n-- Count", start, true),
    "native Healthstone refresh helper end is missing")
local helper = source:sub(start, finish - 1)

ns = {}
C_Item = { counts = {} }
function C_Item.GetItemCount(itemID) return C_Item.counts[itemID] or 0 end
assert(loadstring(helper, "=NativeHealthstoneCount"))()

local function NewNativeHealthstone(category)
    local text = {
        SetText = function(self, value) self.text = value end,
    }
    local count = {
        Current = text,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    return { _nativeHealthstoneCategory = category, ChargeCount = count }
end

C_Item.counts[5512], C_Item.counts[224464] = 2, 3
local demonic = NewNativeHealthstone(2566)
ns._ApplyNativeHealthstoneCount(demonic)
assert(demonic.ChargeCount.Current.text == 5)
assert(demonic.ChargeCount.shown == true)

C_Item.counts[5512], C_Item.counts[224464] = 0, 0
local empty = NewNativeHealthstone(1711)
empty.ChargeCount.Current.text, empty.ChargeCount.shown = 7, true
ns._ApplyNativeHealthstoneCount(empty)
assert(empty.ChargeCount.Current.text == nil)
assert(empty.ChargeCount.shown == false)

C_Item.counts[5512] = 4
demonic.ChargeCount.Current.text, demonic.ChargeCount.shown = nil, false
ns._nativeHealthstoneFrames = { [demonic] = true }
ns._RefreshNativeHealthstoneCounts()
assert(demonic.ChargeCount.Current.text == 4)
assert(demonic.ChargeCount.shown == true)

C_Item.counts[5512] = 2
local other = NewNativeHealthstone(nil)
other.ChargeCount.Current.text, other.ChargeCount.shown = 9, true
ns._ApplyNativeHealthstoneCount(other)
assert(other.ChargeCount.Current.text == 9)
assert(other.ChargeCount.shown == true)

print("test_native_healthstone_count: ok")
