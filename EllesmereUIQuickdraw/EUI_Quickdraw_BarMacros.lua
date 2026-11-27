if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_BarMacros.lua
--
--  Action Bar Macros: a menu macro (named after its menu, made by the
--  options page) placed on an action bar lends that button's keybind to the
--  menu whose number its body carries.
--  Moving the macro moves the key; ns.UpdateBindings does the binding.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local tonumber, type = tonumber, type
local GetActionInfo, GetActionText = GetActionInfo, GetActionText
local GetMacroBody, GetMacroInfo = GetMacroBody, GetMacroInfo
local GetBindingKey = GetBindingKey
local EQD, P = I.EQD, I.P

-- The menu number lives in the body, a # line the macro system ignores, so the
-- name is free to be the menu's own. Macros made before that were named
-- EUI_Quickdraw<n>; those still count until Pick Up rewrites them.
local MACRO_TAG = "#EllesmereUI Quickdraw menu "
local TAG_PATTERN = "^" .. MACRO_TAG .. "(%d+)"
local LEGACY_PATTERN = "^EUI_Quickdraw(%d+)$"

function ns.BarMacroBody(index)
    return MACRO_TAG .. index
end

-- The menu a macro belongs to (0: its menu was deleted), or nil.
function ns.BarMacroPalette(name, body)
    local n = type(body) == "string" and body:match(TAG_PATTERN)
        or type(name) == "string" and name:match(LEGACY_PATTERN)
    return n and tonumber(n)
end

-- The bars whose slots never page, by first action slot, and the binding
-- command their keys live under (warcraft.wiki.gg/wiki/ActionSlot; the same
-- table as BAR_SLOT_OFFSETS / BINDING_MAP in EUI_ActionBars_Secure.lua). The
-- main bar is left out: it pages with stances and forms, so its key would open
-- the menu while the bar shows something else. Bars 9 and 10 only have keys
-- with EllesmereUI's action bars; elsewhere GetBindingKey answers nil.
local BAR_RANGES = {
    { 13,  "EUI_BAR9_BUTTON" },
    { 25,  "MULTIACTIONBAR3BUTTON" },
    { 37,  "MULTIACTIONBAR4BUTTON" },
    { 49,  "MULTIACTIONBAR2BUTTON" },
    { 61,  "MULTIACTIONBAR1BUTTON" },
    { 109, "EUI_BAR10_BUTTON" },
    { 145, "MULTIACTIONBAR5BUTTON" },
    { 157, "MULTIACTIONBAR6BUTTON" },
    { 169, "MULTIACTIONBAR7BUTTON" },
}

-- [slot] = menu whose macro sits there; barList is the same, in slot order,
-- with each slot's binding command, for ns.UpdateBindings to read.
local slotPalette = {}
local barList = {}
local active = false

local function SlotRange(slot)
    for r = 1, #BAR_RANGES do
        local first = BAR_RANGES[r][1]
        if slot >= first and slot < first + 12 then return r end
    end
end

-- GetActionInfo's id is the macro's index, except for a macro showing a spell
-- or an item (never a menu macro, whose body is a comment): checked against
-- the name, with the name as the fallback.
local function MacroPalette(slot)
    local kind, id = GetActionInfo(slot)
    if kind ~= "macro" then return nil end
    local name = GetActionText(slot)
    if not name then return nil end
    local body
    if type(id) == "number" and GetMacroInfo(id) == name then
        body = GetMacroBody(id)
    else
        body = GetMacroBody(name)
    end
    return ns.BarMacroPalette(name, body)
end

local function RebuildList()
    for i = #barList, 1, -1 do barList[i] = nil end
    for r = 1, #BAR_RANGES do
        local first, command = BAR_RANGES[r][1], BAR_RANGES[r][2]
        for s = first, first + 11 do
            local idx = slotPalette[s]
            if idx then
                barList[#barList + 1] = { palette = idx, command = command .. (s - first + 1) }
            end
        end
    end
end

local function RescanAll()
    local changed = false
    for r = 1, #BAR_RANGES do
        local first = BAR_RANGES[r][1]
        for s = first, first + 11 do
            local idx = MacroPalette(s)
            if slotPalette[s] ~= idx then
                slotPalette[s] = idx
                changed = true
            end
        end
    end
    if changed then RebuildList() end
    return changed
end

-- The keys menu `index` takes from the bars, written into `out`; returns the
-- count. Nothing while the setting is off, since the list is empty then.
function I.BarKeys(index, out)
    local n = 0
    for e = 1, #barList do
        local entry = barList[e]
        if entry.palette == index then
            local k1, k2 = GetBindingKey(entry.command)
            if k1 then n = n + 1; out[n] = k1 end
            if k2 then n = n + 1; out[n] = k2 end
        end
    end
    return n
end

-- Fires for every slot redraw (assisted combat dirties its slot several times
-- a second), so a slot outside the bars above costs one range test.
local function OnSlotChanged(_, _, slot)
    if type(slot) ~= "number" or slot < 1 then
        if RescanAll() then ns.UpdateBindings() end
        return
    end
    if not SlotRange(slot) then return end
    local idx = MacroPalette(slot)
    if slotPalette[slot] == idx then return end
    slotPalette[slot] = idx
    RebuildList()
    ns.UpdateBindings()
end

-- A macro renamed, deleted or made. Returns whether any slot changed hands.
function I.BarMacrosRescan()
    return active and RescanAll()
end

-- Follows the setting: called by ns.Refresh and at enable, before
-- ns.UpdateBindings reads the list. Off, nothing is registered or kept.
function I.SyncBarMacros()
    local p = P()
    local want = (p and p.enabled and p.barMacros) and true or false
    if want == active then return end
    active = want
    if want then
        EQD:RegisterEvent("ACTIONBAR_SLOT_CHANGED", OnSlotChanged)
        RescanAll()
    else
        EQD:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
        for s in pairs(slotPalette) do slotPalette[s] = nil end
        RebuildList()
    end
end

I.broken = false
