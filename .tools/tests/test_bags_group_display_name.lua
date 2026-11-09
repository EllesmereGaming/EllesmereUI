-- Stub harness: Bags' built-in group names (The Armory, Adventure Prep) stay
-- English keys in saved data and show translated wherever a group name is
-- drawn (CategoryManager:GroupDisplayName), while every key use keeps the
-- stored name.
--   lua .tools/tests/test_bags_group_display_name.lua
local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return (s:gsub("\r\n", "\n"))
end

local CATS = Read((arg and arg[1]) or "EllesmereUIBags/EllesmereUIBags_Categories.lua")
local GRID = Read((arg and arg[2]) or "EllesmereUIBags/EllesmereUIBags_Grid.lua")
local SIDEBAR = Read((arg and arg[3]) or "EllesmereUIBags/EUI_Bags_Sidebar.lua")
local BANK = Read((arg and arg[4]) or "EllesmereUIBags/EllesmereUIBags_Bank.lua")

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- 1. GroupDisplayName, cut from the real file.
do
    local s = CATS:find("local DEFAULT_GROUP_NAMES", 1, true)
    assert(s, "DEFAULT_GROUP_NAMES not found")
    local _, e = CATS:find("\nend\n", s, true)
    local T = { ["The Armory"] = "ES Arsenal", ["Adventure Prep"] = "ES Prep", ["Consumables"] = "ES Cons" }
    local CategoryManager = {}
    local env = setmetatable({
        CategoryManager = CategoryManager,
        EllesmereUI = { L = function(k) return T[k] or k end },
    }, { __index = _G })
    local fn = assert(loadstring(CATS:sub(s, e), "@GroupDisplayName"))
    setfenv(fn, env)
    fn()
    local D = function(n) return CategoryManager:GroupDisplayName(n) end
    check(D("The Armory") == "ES Arsenal", "The Armory is not translated")
    check(D("Adventure Prep") == "ES Prep", "Adventure Prep is not translated")
    check(D("Consumables") == "Consumables", "a name that is not a built-in group was translated")
    check(D("My Group") == "My Group", "a user group name changed")
    check(D(nil) == nil, "nil did not pass through")
end

-- 2. Every place that draws a group name shows the display name ...
local function has(src, text, msg) check(src:find(text, 1, true) ~= nil, msg) end
has(GRID, "local label = EUI_CategoryManager:GroupDisplayName(sectionName)", "grid: no display label")
has(GRID, "ns.CompactBagsSection(label, sectionItems, kind, assignKey)", "compact view: group label not translated")
has(GRID, 'hdr._label:SetText(label .. " (" .. itemCount .. ")")', "grid header: group label not translated")
has(SIDEBAR, "name = EUI_CategoryManager:GroupDisplayName(cat.groupName)", "sidebar: group heading not translated")
has(SIDEBAR, "placeholder = EUI_CategoryManager:GroupDisplayName(myGroup)", "rename popup: placeholder not translated")
has(SIDEBAR, "addSub:CreateButton(EUI_CategoryManager:GroupDisplayName(gn)", "Add to Group menu: names not translated")
has(BANK, "EmitHeader(_catSel.detail or _G.EUI_CategoryManager:GroupDisplayName(_catSel.group)", "bank: group header not translated")
has(BANK, "RenderSidebarEntry(nil, CM:GroupDisplayName(cat.groupName)", "bank sidebar: group entry not translated")

-- 3. ... while the key uses keep the stored name.
has(GRID, "IsGearOnlyGroup(sectionName)", "grid: the gear check lost the group key")
has(SIDEBAR, "isGroupHeader = true, groupName = cat.groupName", "sidebar: the heading lost its group key")
has(SIDEBAR, "EUI_CategoryManager:AddToGroup(catIdx, gn)", "Add to Group: the action lost the group key")
has(SIDEBAR, "EUI_CategoryManager:RenameGroup(myGroup, newName)", "rename: the action lost the group key")
has(BANK, "0, { group = cat.groupName },", "bank sidebar: the entry lost its group key")

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_bags_group_display_name")
