-- Stub harness: the item counts in tooltips (how many of an item each
-- character holds) are switched in Blizzard Skins+ > Tooltips & Menus >
-- Tooltip Extras > Item Counts. The feature is the Bags module's: its
-- account-wide switch EllesmereUIDB.bagTooltipCounts, the inventories it
-- saves and the tooltip lines, all through Offline.Set / Offline.CountsEnabled.
-- The Bags page no longer carries the toggle.
-- Cuts the checklist's items and its read and write functions out of
-- EUI_BlizzardSkin_Options.lua by their first and last lines (a moved line
-- fails here by name) and runs them over stubs.
--   lua .tools/tests/test_tooltip_extras_item_counts.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local SKIN_OPT = ReadSource("EllesmereUIOptions/EUI_BlizzardSkin_Options.lua")
local BAGS_OPT = ReadSource("EllesmereUIOptions/EUI_Bags_Options.lua")
local OFFLINE = ReadSource("EllesmereUIBags/EllesmereUIBags_Offline.lua")
local PROFILES = ReadSource("EllesmereUI_Profiles.lua")

local ITEMS = Cut(SKIN_OPT, "        local function BagOffline()\n", "        local ttExtrasRow\n", "the checklist's items")
local LIST = Cut(SKIN_OPT, "            local extrasDD, extrasRefresh = EllesmereUI.BuildVisOptsCBDropdown(\n", "            PP.Point(extrasDD,", "the checklist")
-- the defaults table the read function falls back to stands right above the list
local DEFAULTS = Cut(SKIN_OPT, "            local EXTRA_DEFAULTS = {\n", "            local extrasDD, extrasRefresh", "the checklist's defaults")

local n = 0
local function check(cond, msg)
    n = n + 1
    assert(cond, msg)
end

-- One page build. o.forever: the client; o.bags: the Bags module is loaded;
-- o.db: the account table
local function Build(o)
    local W = { searched = {}, repaints = 0, cvars = {}, sets = {} }
    local db = o.db or {}
    local counts = db.bagTooltipCounts == true
    local offline = {
        CountsEnabled = function() return counts end,
        Set = function(key, on)
            W.sets[#W.sets + 1] = { key, on }
            counts = on and true or false
        end,
    }
    local EllesmereUI = {
        IS_FOREVER = o.forever or nil,
        _ModuleNS = { EllesmereUIBags = o.bags and { Offline = offline } or nil },
        _buildingModule = "EllesmereUIBlizzardSkin", _buildingPage = "Tooltips, Menus & Popups",
        L = function(s) return o.locale and ("<" .. s .. ">") or s end,
        DisabledTooltip = function(what) return "requires " .. what end,
        _RegisterSearchEntry = function(label, labelLoc, text, module, page, section)
            W.searched[#W.searched + 1] = { label = label, loc = labelLoc, text = text, module = module, page = page, section = section }
        end,
        SetCVar = function(name, value, owner) W.cvars[#W.cvars + 1] = { name, value, owner } end,
        BuildVisOptsCBDropdown = function(rgn, width, level, items, get, set)
            W.items, W.get, W.set, W.width = items, get, set, width
            return {}, function() end
        end,
    }
    local env = setmetatable({
        EllesmereUI = EllesmereUI, EllesmereUIDB = db,
        GetCVar = function() return "0" end,
        ttReskinOff = function() return db.customTooltips == false end,
        TooltipPreviewRepaint = function() W.repaints = W.repaints + 1 end,
        parent = { _currentSection = { _sectionName = "BLIZZARD TOOLTIP" } },
        lrgn = { GetFrameLevel = function() return 3 end },
    }, { __index = _G })
    local chunk = assert(loadstring(ITEMS .. DEFAULTS .. LIST .. "\n", "=tooltip-extras"))
    setfenv(chunk, env)
    chunk()
    W.db, W.offline = db, offline
    return W
end
local function Item(W, key)
    for i, it in ipairs(W.items) do if it.key == key then return it, i end end
end

-------------------------------------------------------------------------------
-- 1. the entry: Item Counts, last but for Detailed Tooltips, with the client's
--    own tooltip, never locked by the reskin
-------------------------------------------------------------------------------
for _, forever in ipairs({ false, true }) do
    local W = Build({ forever = forever, bags = true, db = { customTooltips = false } })
    local it, at = Item(W, "bagTooltipCounts")
    check(it ~= nil and it.label == "Item Counts", "Tooltip Extras has no Item Counts entry")
    check(#W.items == 14 and at == 13 and W.items[14].key == "uber", "Item Counts is not the last entry before Detailed Tooltips: " .. tostring(at) .. " of " .. #W.items)
    check(type(it.tooltip) == "string" and (it.tooltip:find("warband bank", 1, true) ~= nil) == (not forever),
        "the entry's tooltip is not the client's own (the warband bank is retail's)")
    check(it.lockedFn() == false, "with Bags loaded and the reskin off the entry is locked")
    check(Item(W, "tooltipAFKTag").lockedFn() == true, "a reskin entry is not locked with the reskin off")
end

-------------------------------------------------------------------------------
-- 2. Bags loaded: read and written through the Bags module alone
-------------------------------------------------------------------------------
do
    local W = Build({ bags = true, db = {} })
    check(W.get("bagTooltipCounts") == false, "unset reads as on")
    W.set("bagTooltipCounts", true)
    check(#W.sets == 1 and W.sets[1][1] == "bagTooltipCounts" and W.sets[1][2] == true, "a tick did not go through the Bags module's setter")
    check(W.get("bagTooltipCounts") == true, "a tick is not read back")
    check(W.db.bagTooltipCounts == nil, "the page wrote the switch itself, round the Bags module")
    check(W.repaints == 0 and #W.cvars == 0, "a tick repainted the tooltip sample or wrote a CVar")
    W.set("bagTooltipCounts", false)
    check(#W.sets == 2 and W.sets[2][2] == false and W.get("bagTooltipCounts") == false, "an untick did not go through the Bags module's setter")
    -- on from before (the Bags page set it): shown ticked
    W = Build({ bags = true, db = { bagTooltipCounts = true } })
    check(W.get("bagTooltipCounts") == true, "a switch turned on before reads unticked")
    -- the other entries keep their own paths
    W.set("tooltipAFKTag", true)
    check(W.db.tooltipAFKTag == true and W.repaints == 1 and #W.sets == 0, "another entry's tick")
    check(W.get("tooltipItemLevel") == true and W.get("tooltipPlayerTitles") == false, "another entry's default")
    W.set("uber", true)
    check(#W.cvars == 1 and W.cvars[1][1] == "UberTooltips" and W.cvars[1][2] == "1" and #W.sets == 0, "Detailed Tooltips' tick")
end

-------------------------------------------------------------------------------
-- 3. Bags not loaded: locked, reads off, a write does nothing
-------------------------------------------------------------------------------
do
    local W = Build({ bags = false, db = { bagTooltipCounts = true } })
    local it = Item(W, "bagTooltipCounts")
    check(it.lockedFn() == true and it.lockedTooltip == "requires Bags", "without Bags the entry is not locked on that module")
    check(W.get("bagTooltipCounts") == false, "without Bags the entry reads ticked")
    W.set("bagTooltipCounts", false)
    W.set("bagTooltipCounts", true)
    check(W.db.bagTooltipCounts == true and #W.sets == 0 and W.repaints == 0, "without Bags a write changed something")
end

-------------------------------------------------------------------------------
-- 4. search: the row answers to its entries' names and to the name the
--    setting had on the Bags page, in the reader's language too
-------------------------------------------------------------------------------
do
    local W = Build({ bags = true })
    check(#W.searched == 1, "search entries registered: " .. #W.searched)
    local e = W.searched[1]
    check(e.label == "Tooltip Extras" and e.loc == nil and e.module == "EllesmereUIBlizzardSkin" and e.section == "BLIZZARD TOOLTIP", "the search entry is not the row's")
    for _, word in ipairs({ "Item Counts", "Tooltip Item Counts", "Away Tag", "Detailed Tooltips" }) do
        check(e.text:find(word, 1, true) ~= nil, "search does not find the row by " .. word)
    end
    W = Build({ bags = true, locale = true })
    e = W.searched[1]
    check(e.loc == "<Tooltip Extras>" and e.text:find("<Tooltip Item Counts>", 1, true) ~= nil and e.text:find("<Item Counts>", 1, true) ~= nil,
        "search does not carry the translated names")
end

-------------------------------------------------------------------------------
-- 5. the Bags page, the two resets, the export list, the runtime
-------------------------------------------------------------------------------
check(not BAGS_OPT:find('text="Tooltip Item Counts"', 1, true), "the Bags page still builds the Tooltip Item Counts toggle")
local row = Cut(BAGS_OPT, '{ type="toggle", text="Offline Bank",', "); y = y - h", "the Offline Bank row")
check(row:find("EllesmereUI.BlankRowCfg()", 1, true) ~= nil and not row:find("bagTooltipCounts", 1, true), "the Offline Bank row's second half is not blank")
check(BAGS_OPT:find("EllesmereUIDB.bagTooltipCounts = nil", 1, true) ~= nil, "the Bags reset does not clear the switch")
local resetAt = assert(SKIN_OPT:find("        onReset = function()\n", 1, true), "the Blizzard Skins+ reset not found")
local reset = SKIN_OPT:sub(resetAt)
check(reset:find("EllesmereUIDB.bagTooltipCounts = nil", 1, true) ~= nil, "the Blizzard Skins+ reset does not clear the switch")
-- never exported with the tooltip settings: a shared profile must not switch
-- another account's inventory saving on
local allow = Cut(PROFILES, "local BLIZZ_SKIN_GLOBAL_KEYS = {}\ndo\n", "\nend\n", "the export list")
check(allow:find('"tooltipAFKTag"', 1, true) ~= nil and not allow:find("bagTooltipCounts", 1, true), "the switch is in the tooltip settings' export list")
check(OFFLINE:find('function Offline.CountsEnabled() return Acct().bagTooltipCounts == true end', 1, true) ~= nil
    and OFFLINE:find("function Offline.Set(key, on)", 1, true) ~= nil, "the Bags module's read or setter moved")

print(("tooltip extras item counts harness: %d checks, ok"):format(n))
