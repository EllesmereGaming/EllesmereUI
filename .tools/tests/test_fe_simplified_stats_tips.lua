-- Stub harness: WoW Forever Simplified Stats rewrites the item tooltips the
-- player reads and leaves every other tooltip as the game wrote it (the hidden
-- tooltips other addons read item stats from).
--   lua .tools/tests/test_fe_simplified_stats_tips.lua [file]
local PATH = (arg and arg[1]) or "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_SimplifiedStats.lua"

local fh = assert(io.open(PATH, "rb"))
local SRC = fh:read("*a")
fh:close()

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- Game stubs ------------------------------------------------------------------
local HOOK
EUI_CLIENT_BLOCKED = nil
EllesmereUI = {
    IS_FOREVER = true,
    FOREVER_STAT_HUES = setmetatable({}, { __index = function() return "abcdef" end }),
}
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) HOOK = fn end }
Enum = { TooltipDataType = { Item = 0 } }
TooltipComparisonManager = nil
issecretvalue = function() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
TOOLTIP_ITEM_STAT_SPELL_POWER_INCREASE =
    "Equip: Increases damage and healing done by magical spells and effects by up to %1$d."
ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Spell Damage"
ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Spell Healing"
ITEM_MOD_SPELL_POWER_SHORT = "Spell Power"

local SETTINGS = { shorten = true, colors = false, merge = false, numColor = "signed" }
local module = {
    Feature = function(_, defaults)
        return {
            Get = function(k)
                local v = SETTINGS[k]
                if v == nil then v = defaults[k] end
                return v
            end,
            Cfg = function() return SETTINGS end,
        }
    end,
}

local fn = assert(loadstring(SRC, "@SimplifiedStats"))
fn("EllesmereUIForeverEssentials", module)
assert(HOOK, "the item post-call was not registered")

-- Tooltip stub: line 1 is the item name, line 2 the stat line.
local STAT = "Equip: Increases damage and healing done by magical spells and effects by up to 12."
local SHORT = "+12 Spell Damage\n+12 Spell Healing"
local function Tip(name, text)
    local tip = { shows = 0 }
    function tip:GetName() return name end
    function tip:NumLines() return 2 end
    function tip:Show() self.shows = self.shows + 1 end
    local lines = {}
    for i, t in ipairs({ "Robe of Tests", text or STAT }) do
        local fs = { text = t }
        function fs:GetText() return self.text end
        function fs:SetText(v) self.text = v end
        lines[i] = fs
        if name then _G[name .. "TextLeft" .. i] = fs end
    end
    tip.lines = lines
    return tip
end

-- 1. The tooltips the player reads are rewritten: the game tooltip, the chat
-- link tooltip, their four comparison tooltips and the Gamepad interface
-- style's loot history item tooltip.
for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                        "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "LootHistoryExtraTooltip" }) do
    local tip = Tip(name)
    HOOK(tip)
    check(tip.lines[2].text == SHORT, name .. " line not shortened: " .. tostring(tip.lines[2].text))
    check(tip.shows == 1, name .. " not shown again after the rewrite")
    check(tip.lines[1].text == "Robe of Tests", name .. " title line touched")
end

-- 2. Another addon's hidden tooltip keeps the game's own line.
local scan = Tip("SomeAddonScanTooltip1")
HOOK(scan)
check(scan.lines[2].text == STAT, "an addon's scan tooltip was rewritten: " .. tostring(scan.lines[2].text))
check(scan.shows == 0, "an addon's scan tooltip was shown")

-- 3. A tooltip without a name is left alone (and does not error).
local anon = Tip(nil)
HOOK(anon)
check(anon.lines[2].text == STAT, "a nameless tooltip was rewritten")

-- 4. With both options off nothing is rewritten, the player's tooltip included.
SETTINGS.shorten = false
local off = Tip("GameTooltip")
HOOK(off)
check(off.lines[2].text == STAT, "rewrote with Shorten and Color off")
SETTINGS.shorten = true

-- 5. The memo serves a repeat, and a scan tooltip after a memo hit still keeps
-- its line (the memo holds the rewrite, not the choice of tooltip).
local again = Tip("GameTooltip")
HOOK(again)
check(again.lines[2].text == SHORT, "memo repeat lost the rewrite")
local scan2 = Tip("SomeAddonScanTooltip2")
HOOK(scan2)
check(scan2.lines[2].text == STAT, "a scan tooltip after a memo hit was rewritten")

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_fe_simplified_stats_tips")
